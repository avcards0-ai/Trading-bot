--[[
	SecurityService
	All lasers, cameras and traps - in NPC zones and in player vaults - plus zone alarms.

	Devices never move on the server: lasers/cameras follow deterministic patterns
	(SecurityPatterns) that the server evaluates for hits and every client animates
	locally with the same math. Hit detection is done with spatial checks against
	player root positions on a fixed tick; nothing relies on client Touched events.

	Who gets hurt:
	  * Zone devices: everyone (lasers/traps). Zone cameras only care about loot carriers.
	    Blackout events switch zone lasers + cameras off.
	  * Vault devices: everyone except the vault owner.
	  * Banana-trail peels (Banana of Doom): everyone except the carrier who dropped them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Security = require(Shared.Config.Security)
local Zones = require(Shared.Config.Zones)
local SecurityPatterns = require(Shared.SecurityPatterns)

local Kit = require(script.Parent.Parent.Map.Kit)

local SecurityService = { Name = "SecurityService" }

local S: { [string]: any }

local zoneLasers: { Kit.LaserDef } = {}
local zoneCameras: { Kit.CameraDef } = {}
local zoneTraps: { Kit.TrapDef } = {}
local plotLasers: { [number]: { Kit.LaserDef } } = {}
local plotCameras: { [number]: { Kit.CameraDef } } = {}
local plotTraps: { [number]: { Kit.TrapDef } } = {}
local tempTraps: { { Trap: Kit.TrapDef, ExpiresAt: number } } = {}
local tempFolder: Folder

local lastHit: { [Player]: number } = {}
local cameraSeen: { [string]: number } = {}
local zoneAlarmFeed: { [string]: number } = {}
local wanted: { [Player]: { Zone: string, Until: number } } = {}

function SecurityService:Init(services)
	S = services
end

local function parseOwner(owner: string): (string, string)
	local kind, id = string.match(owner, "^(%a+):(.+)$")
	return kind or "", id or ""
end

-- Candidates: alive, loaded, not spawn-protected.
local function candidates(): { { Player: Player, Root: BasePart, Position: Vector3 } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local root = S.PlayerService:GetRoot(player)
		if
			root
			and S.PlayerService:IsAlive(player)
			and S.DataService:IsLoaded(player)
			and not S.PlayerService:HasStatus(player, "Protected")
		then
			table.insert(list, { Player = player, Root = root, Position = root.Position })
		end
	end
	return list
end

-- True if this device may affect this player.
local function affects(owner: string, player: Player): boolean
	local kind, id = parseOwner(owner)
	if kind == "Plot" then
		local plotOwner = S.PlotService:GetOwner(tonumber(id) or 0)
		return plotOwner ~= nil and plotOwner ~= player
	elseif kind == "Carrier" then
		return tostring(player.UserId) ~= id
	end
	return true
end

local function ownerLabel(owner: string): string?
	local kind, id = parseOwner(owner)
	if kind == "Plot" then
		local plotOwner = S.PlotService:GetOwner(tonumber(id) or 0)
		return plotOwner and (S.AnnouncementService.name(plotOwner) .. "'s") or nil
	elseif kind == "Carrier" then
		local carrier = Players:GetPlayerByUserId(tonumber(id) or 0)
		return carrier and (S.AnnouncementService.name(carrier) .. "'s") or nil
	end
	return nil
end

local function zoneDeviceActive(owner: string): boolean
	local kind = parseOwner(owner)
	if kind == "Zone" then
		return not S.EventService:IsActive("Blackout")
	end
	return true
end

-- Zone alarms -----------------------------------------------------------------------------

function SecurityService:IsWanted(player: Player, zoneId: string?): boolean
	local entry = wanted[player]
	if not entry or entry.Until < os.clock() then
		return false
	end
	return zoneId == nil or entry.Zone == zoneId
end

function SecurityService:TriggerZoneAlarm(zoneId: string, player: Player)
	local zone = Zones.get(zoneId)
	local zoneData = S.MapService:GetZone(zoneId)
	if not zone or not zoneData then
		return
	end
	local duration = GameConfig.Security.ZoneAlarmDuration
	wanted[player] = { Zone = zoneId, Until = os.clock() + duration }
	S.PlayerService:SetStatus(player, "Wanted", duration)
	zoneData.Folder:SetAttribute("AlarmUntil", workspace:GetServerTimeNow() + duration)
	S.GuardService:Alert(zoneId, player)
	S.AnnouncementService:Effect("ZoneAlarm", { Zone = zoneId, Position = zone.Center }, zone.Center, 450)
	if os.clock() - (zoneAlarmFeed[zoneId] or 0) > 12 then
		zoneAlarmFeed[zoneId] = os.clock()
		S.AnnouncementService:Feed(
			"🚨",
			string.format("ALARM at the %s! <b>%s</b> is on the run!", zone.Name, S.AnnouncementService.name(player)),
			Color3.fromRGB(255, 90, 90)
		)
	end
end

-- Effects ------------------------------------------------------------------------------------

local function hit(player: Player, kind: string, owner: string, origin: Vector3?)
	local now = os.clock()
	if now - (lastHit[player] or 0) < 1.4 then
		return
	end
	lastHit[player] = now
	local cfg = GameConfig.Security
	local label = ownerLabel(owner)
	local root = S.PlayerService:GetRoot(player)
	if kind == "Zap" then
		S.CombatService:ApplyFail(
			player,
			"Zap",
			{ Damage = cfg.ZapDamage, Stun = cfg.ZapStun, Drop = 1, By = label and (label .. " lasers") or "lasers" }
		)
	elseif kind == "Banana" then
		local forward = root and root.CFrame.LookVector or Vector3.zAxis
		S.CombatService:ApplyFail(player, "Slip", {
			Stun = cfg.SlipStun,
			Drop = 1,
			Knockback = forward * 30 + Vector3.new(0, 35, 0),
			By = label and (label .. " banana peel") or "a banana peel",
		})
	elseif kind == "Spring" then
		local away = Vector3.new(0, 0, 0)
		if root and origin then
			local kindName, id = parseOwner(owner)
			local plot = kindName == "Plot" and S.MapService:GetPlot(tonumber(id) or 0)
			if plot then
				-- Launch them back out the vault door
				away = (plot.Front.Position - root.Position) * Vector3.new(1, 0, 1)
			else
				away = (root.Position - origin) * Vector3.new(1, 0, 1)
			end
			away = away.Magnitude > 0.1 and away.Unit or Vector3.zero
		end
		S.CombatService:ApplyFail(player, "Spring", {
			Stun = cfg.SpringStun,
			Drop = 1,
			Knockback = away * 75 + Vector3.new(0, 130, 0),
			By = label and (label .. " spring trap") or "a spring trap",
		})
	elseif kind == "Glue" then
		S.PlayerService:SetStatus(player, "Glued", cfg.GlueDuration)
		S.CombatService:ApplyFail(player, "Glue", { By = label and (label .. " glue trap") or "sticky mud" })
	elseif kind == "Spike" then
		S.CombatService:ApplyFail(player, "Spike", { Damage = 15, Stun = 0.8, Drop = 1, By = "spikes" })
	elseif kind == "Toxic" then
		S.PlayerService:SetStatus(player, "Toxic", 2.5)
		S.CombatService:ApplyFail(player, "Toxic", { Damage = 6, By = "toxic sludge" })
	end
end

-- Device checks ------------------------------------------------------------------------------

local function checkLasers(list: { Kit.LaserDef }, players, t: number)
	for _, laser in list do
		if zoneDeviceActive(laser.Owner) then
			local on, offset = SecurityPatterns.laser(laser.Pattern, laser.Speed, laser.Phase, laser.Amplitude, t)
			if on then
				local cf = laser.BaseCFrame + laser.Axis * offset
				local halfLength = laser.Part.Size.X / 2
				for _, entry in players do
					if
						(entry.Position - cf.Position).Magnitude <= halfLength + 5
						and affects(laser.Owner, entry.Player)
					then
						local p = cf:PointToObjectSpace(entry.Position)
						-- Body spans ~3 studs below the root to ~2 above; ~1.1 studs thick.
						if
							math.abs(p.X) <= halfLength + 0.3
							and math.abs(p.Z) <= 1.2
							and p.Y >= -2.1
							and p.Y <= 3.1
						then
							hit(entry.Player, "Zap", laser.Owner, cf.Position)
						end
					end
				end
			end
		end
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function canSee(from: Vector3, entry): boolean
	local exclude: { Instance } = { tempFolder }
	local artifacts = workspace:FindFirstChild("Artifacts")
	if artifacts then
		table.insert(exclude, artifacts)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local guards = workspace:FindFirstChild("Guards")
	if guards then
		table.insert(exclude, guards)
	end
	rayParams.FilterDescendantsInstances = exclude
	local direction = entry.Position - from
	local result = workspace:Raycast(from, direction, rayParams)
	-- Ignore glass / non-colliding geometry by checking what we hit
	return result == nil or not result.Instance.CanCollide or result.Instance.Transparency > 0.5
end

local function checkCameras(list: { Kit.CameraDef }, players, t: number)
	for i, cam in list do
		if zoneDeviceActive(cam.Owner) then
			local yaw = SecurityPatterns.cameraYaw(cam.BaseYaw, cam.Sweep, cam.Speed, cam.Phase, t)
			local cf = SecurityPatterns.cameraCFrame(cam.Position, yaw, cam.Pitch)
			local kind, id = parseOwner(cam.Owner)
			for _, entry in players do
				local player = entry.Player
				local relevant
				if kind == "Zone" then
					relevant = S.CarryService:Count(player) > 0 and not S.PlayerService:HasStatus(player, "Wanted")
				else
					relevant = affects(cam.Owner, player) and S.RaidService:IsIntruding(player, tonumber(id) or 0)
				end
				if
					relevant
					and SecurityPatterns.inCone(cf, cam.Range, cam.Fov, entry.Position)
					and canSee(cf.Position, entry)
				then
					local key = cam.Owner .. i .. player.UserId
					if os.clock() - (cameraSeen[key] or 0) > 4 then
						cameraSeen[key] = os.clock()
						S.AnnouncementService:Effect(
							"Spotted",
							{ UserId = player.UserId, Position = cam.Position },
							entry.Position,
							200
						)
						if kind == "Zone" then
							SecurityService:TriggerZoneAlarm(id, player)
						else
							S.RaidService:OnSpotted(tonumber(id) or 0, player)
						end
					end
				end
			end
		end
	end
end

local function checkTraps(list: { Kit.TrapDef }, players)
	local now = os.clock()
	for _, trap in list do
		if trap.ReadyAt <= now and trap.Part.Parent then
			for _, entry in players do
				local offset = entry.Position - trap.Position
				local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
				if flat <= trap.Radius and offset.Y > -1 and offset.Y < 5.5 and affects(trap.Owner, entry.Player) then
					hit(entry.Player, trap.Kind, trap.Owner, trap.Position)
					if trap.Kind ~= "Toxic" and trap.Kind ~= "Glue" then
						trap.ReadyAt = now + GameConfig.Security.TrapRearm
						trap.Part:SetAttribute("ReadyAt", workspace:GetServerTimeNow() + GameConfig.Security.TrapRearm)
					end
					break
				end
			end
		end
	end
end

-- Plot installs ------------------------------------------------------------------------------

function SecurityService:ClearPlot(index: number)
	local plot = S.MapService:GetPlot(index)
	if plot then
		plot.Devices:ClearAllChildren()
	end
	plotLasers[index] = nil
	plotCameras[index] = nil
	plotTraps[index] = nil
end

function SecurityService:InstallPlot(player: Player)
	local index = S.PlotService:GetPlotIndex(player)
	local data = S.DataService:Get(player)
	if not index or not data then
		return
	end
	self:ClearPlot(index)
	local plot = S.MapService:GetPlot(index)
	local levels = data.Security
	local owner = "Plot:" .. index

	local lasers = {}
	local laserLevel = levels.Lasers or 0
	local beams = Security.stat("Lasers", "Beams", laserLevel)
	local pattern = Security.stat("Lasers", "Pattern", laserLevel)
	local speed = Security.stat("Lasers", "Speed", laserLevel)
	local forward = plot.CFrame.LookVector
	for i = 1, math.min(beams, #plot.LaserSlots) do
		local slot = plot.LaserSlots[i]
		local axis = (i % 2 == 0) and forward or Vector3.yAxis
		local amplitude = (pattern == "Static" or pattern == "Blink") and 0 or ((i % 2 == 0) and 1.6 or 1.2)
		table.insert(
			lasers,
			Kit.laser(plot.Devices, slot.CFrame, slot.Length, pattern, speed, i * 1.37, amplitude, axis, owner)
		)
	end
	plotLasers[index] = lasers

	local cameras = {}
	local camLevel = levels.Cameras or 0
	for i = 1, math.min(Security.stat("Cameras", "Count", camLevel), #plot.CameraSlots) do
		local slot = plot.CameraSlots[i]
		table.insert(
			cameras,
			Kit.camera(
				plot.Devices,
				slot.Position,
				slot.Yaw,
				0.7,
				Security.stat("Cameras", "Sweep", camLevel),
				Security.stat("Cameras", "Range", camLevel),
				Security.stat("Cameras", "Fov", camLevel),
				owner,
				32
			)
		)
	end
	plotCameras[index] = cameras

	local traps = {}
	local trapLevel = levels.Traps or 0
	local slotIndex = 1
	for _, kind in { "Banana", "Spring", "Glue" } do
		for _ = 1, Security.stat("Traps", kind, trapLevel) do
			local position = plot.TrapSlots[slotIndex]
			if position then
				table.insert(traps, Kit.trap(plot.Devices, kind, position, owner, slotIndex * 0.7))
			end
			slotIndex += 1
		end
	end
	plotTraps[index] = traps
	S.RaidService:UpdateDoorPrompt(player)
end

function SecurityService:AddTemporaryTrap(kind: string, position: Vector3, owner: string, lifetime: number)
	local trap = Kit.trap(tempFolder, kind, position, owner, math.random() * 6)
	table.insert(tempTraps, { Trap = trap, ExpiresAt = os.clock() + lifetime })
end

function SecurityService:Start()
	tempFolder = Instance.new("Folder")
	tempFolder.Name = "TemporaryTraps"
	tempFolder.Parent = workspace

	local map = S.MapService:Get()
	for _, zone in map.Zones do
		if zone.Id ~= "SecretRoom" then
			for _, laser in zone.Lasers do
				table.insert(zoneLasers, laser)
			end
			for _, cam in zone.Cameras do
				table.insert(zoneCameras, cam)
			end
			for _, trap in zone.Traps do
				table.insert(zoneTraps, trap)
			end
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
		wanted[player] = nil
	end)

	-- Lasers + traps: fast tick. Cameras: slower tick (raycasts).
	task.spawn(function()
		local cameraAccumulator = 0
		while true do
			local dt = task.wait(0.1)
			local t = workspace:GetServerTimeNow()
			local players = candidates()
			if #players > 0 then
				checkLasers(zoneLasers, players, t)
				checkTraps(zoneTraps, players)
				for _, list in plotLasers do
					checkLasers(list, players, t)
				end
				for _, list in plotTraps do
					checkTraps(list, players)
				end
				local temps = {}
				for _, entry in tempTraps do
					table.insert(temps, entry.Trap)
				end
				checkTraps(temps, players)

				cameraAccumulator += dt
				if cameraAccumulator >= 0.25 then
					cameraAccumulator = 0
					checkCameras(zoneCameras, players, t)
					for _, list in plotCameras do
						checkCameras(list, players, t)
					end
				end
			end
			-- Expire temporary traps
			local now = os.clock()
			for i = #tempTraps, 1, -1 do
				if tempTraps[i].ExpiresAt <= now then
					tempTraps[i].Trap.Part:Destroy()
					table.remove(tempTraps, i)
				end
			end
		end
	end)
end

return SecurityService
