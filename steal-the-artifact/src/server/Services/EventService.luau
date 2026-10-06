--[[
	EventService
	Server-wide events every few minutes: Artifact Rain, Golden Hour, Blackout, Meteor
	Strike, Guard Strike, Low Gravity, Black Market and Vault Breach. State is mirrored to
	clients through ReplicatedStorage attributes (EventId / EventEndsAt / NextEventAt).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Events = require(Shared.Config.Events)
local Zones = require(Shared.Config.Zones)
local Tables = require(Shared.Util.Tables)

local EventService = { Name = "EventService" }

local S: { [string]: any }

local active: { Id: string, EndsAt: number }? = nil
local nextEventAt = 0
local lastEventId: string? = nil
local joined: { [Player]: boolean } = {}
local rng = Random.new()
local eventFolder: Folder

local RAIN_WEIGHTS = { Common = 28, Uncommon = 34, Rare = 24, Epic = 11, Legendary = 2.7, Mythic = 0.3 }
local METEOR_CORE = { Legendary = 70, Mythic = 27, Secret = 3 }
local METEOR_SHARDS = { Rare = 55, Epic = 40, Legendary = 5 }

function EventService:Init(services)
	S = services
end

function EventService:IsActive(id: string): boolean
	return active ~= nil and active.Id == id
end

function EventService:ActiveEventId(): string?
	return active and active.Id or nil
end

function EventService:SecureMultiplier(): number
	return self:IsActive("GoldenHour") and Events.Multipliers.GoldenHourSecure or 1
end

function EventService:SellMultiplier(): number
	return self:IsActive("BlackMarket") and Events.Multipliers.BlackMarketSell or 1
end

function EventService:OnSteal(player: Player)
	if active and not joined[player] then
		joined[player] = true
		S.DataService:Increment(player, "EventsJoined")
	end
end

local function groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local artifacts = workspace:FindFirstChild("Artifacts")
	if artifacts then
		table.insert(exclude, artifacts)
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(position + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), params)
	return hit and hit.Position or Vector3.new(position.X, 0, position.Z)
end

-- Event behaviours ----------------------------------------------------------------------------

local function artifactRain(duration: number)
	local endsAt = os.clock() + duration
	while active and active.Id == "ArtifactRain" and os.clock() < endsAt do
		for _ = 1, rng:NextInteger(1, 2) do
			local angle = rng:NextNumber(0, math.pi * 2)
			local radius = rng:NextNumber(30, 150)
			local ground = groundAt(Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
			local cf = CFrame.new(ground + Vector3.new(0, 1.9, 0))
			S.ArtifactService:SpawnEvent(cf, RAIN_WEIGHTS, 60, ground + Vector3.new(0, 140, 0))
		end
		task.wait(1.6)
	end
end

local function meteor()
	-- Pick an open spot between the zones
	local target
	for _ = 1, 20 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(160, 470)
		local candidate = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local clear = true
		for _, zone in Zones.List do
			if
				zone.Center.Y > -40
				and (Vector3.new(zone.Center.X, 0, zone.Center.Z) - candidate).Magnitude < zone.Radius + 15
			then
				clear = false
				break
			end
		end
		if clear then
			target = candidate
			break
		end
	end
	target = groundAt(target or Vector3.new(220, 0, 220))
	local impactIn = 8
	ReplicatedStorage:SetAttribute("EventMarker", target)
	S.AnnouncementService:Effect(
		"MeteorIncoming",
		{ Position = target, ImpactAt = workspace:GetServerTimeNow() + impactIn },
		nil
	)
	S.AnnouncementService:Feed(
		"☄️",
		"A <b>METEOR</b> is about to hit the city! Follow the marker!",
		Color3.fromRGB(255, 140, 60),
		true
	)
	task.wait(impactIn)
	if not active or active.Id ~= "Meteor" then
		return
	end
	S.AnnouncementService:Effect("MeteorImpact", { Position = target }, nil)
	-- Crater
	local crater = Instance.new("Model")
	crater.Name = "MeteorCrater"
	for i = 1, 10 do
		local angle = i / 10 * math.pi * 2
		local rock = Instance.new("Part")
		rock.Anchored = true
		rock.Size = Vector3.new(rng:NextNumber(4, 7), rng:NextNumber(2, 4), rng:NextNumber(4, 7))
		rock.CFrame = CFrame.new(target + Vector3.new(math.cos(angle) * 11, 0.8, math.sin(angle) * 11))
			* CFrame.Angles(rng:NextNumber(-0.5, 0.5), angle, rng:NextNumber(-0.5, 0.5))
		rock.Color = Color3.fromRGB(70, 55, 60)
		rock.Material = Enum.Material.Basalt
		rock.Parent = crater
	end
	local glow = Instance.new("Part")
	glow.Anchored = true
	glow.CanCollide = false
	glow.Shape = Enum.PartType.Cylinder
	glow.Size = Vector3.new(0.3, 18, 18)
	glow.CFrame = CFrame.new(target + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	glow.Color = Color3.fromRGB(255, 120, 40)
	glow.Material = Enum.Material.Neon
	glow.Parent = crater
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 40
	light.Brightness = 3
	light.Parent = glow
	crater.Parent = eventFolder
	task.delay(150, function()
		crater:Destroy()
	end)

	S.ArtifactService:SpawnEvent(
		CFrame.new(target + Vector3.new(0, 2.2, 0)),
		METEOR_CORE,
		120,
		target + Vector3.new(0, 30, 0)
	)
	for i = 1, 3 do
		local angle = i / 3 * math.pi * 2
		local spot = groundAt(target + Vector3.new(math.cos(angle) * 7, 0, math.sin(angle) * 7))
		S.ArtifactService:SpawnEvent(
			CFrame.new(spot + Vector3.new(0, 1.9, 0)),
			METEOR_SHARDS,
			120,
			target + Vector3.new(0, 20, 0)
		)
	end
end

-- Scheduler -------------------------------------------------------------------------------

function EventService:StartEvent(id: string)
	local def = Events.ById[id]
	if not def or active then
		return
	end
	active = { Id = id, EndsAt = os.clock() + def.Duration }
	lastEventId = id
	table.clear(joined)
	ReplicatedStorage:SetAttribute("EventId", id)
	ReplicatedStorage:SetAttribute("EventEndsAt", workspace:GetServerTimeNow() + def.Duration)
	S.AnnouncementService:Announce({ Kind = "Event", EventId = id })
	S.AnnouncementService:Feed(def.Icon, string.format("<b>%s</b> - %s", def.Name, def.Desc), def.Color, true)

	if id == "ArtifactRain" then
		task.spawn(artifactRain, def.Duration)
	elseif id == "Meteor" then
		task.spawn(meteor)
	elseif id == "LowGravity" then
		workspace.Gravity = Events.Multipliers.LowGravity
	elseif id == "VaultBreach" then
		S.VaultDoorService:ForceOpen(def.Duration)
	end
end

function EventService:EndEvent()
	if not active then
		return
	end
	local id = active.Id
	active = nil
	if id == "LowGravity" then
		workspace.Gravity = 196.2
	end
	ReplicatedStorage:SetAttribute("EventId", nil)
	ReplicatedStorage:SetAttribute("EventEndsAt", nil)
	ReplicatedStorage:SetAttribute("EventMarker", nil)
	local def = Events.ById[id]
	if def then
		S.AnnouncementService:Feed("✅", string.format("%s is over!", def.Name))
	end
end

local function scheduleNext()
	local cfg = GameConfig.Events
	local fast = RunService:IsStudio() and GameConfig.Debug.StudioFastEvents
	local delay = fast and 40 or rng:NextNumber(cfg.MinInterval, cfg.MaxInterval)
	nextEventAt = os.clock() + delay
	ReplicatedStorage:SetAttribute("NextEventAt", workspace:GetServerTimeNow() + delay)
end

function EventService:Start()
	eventFolder = Instance.new("Folder")
	eventFolder.Name = "EventProps"
	eventFolder.Parent = workspace

	local fast = RunService:IsStudio() and GameConfig.Debug.StudioFastEvents
	local first = fast and 20 or GameConfig.Events.FirstEventDelay
	nextEventAt = os.clock() + first
	ReplicatedStorage:SetAttribute("NextEventAt", workspace:GetServerTimeNow() + first)

	Players.PlayerRemoving:Connect(function(player)
		joined[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			if active and now >= active.EndsAt then
				self:EndEvent()
				scheduleNext()
			elseif not active and now >= nextEventAt and #Players:GetPlayers() > 0 then
				local weights = {}
				for _, def in Events.List do
					if def.Id ~= lastEventId then
						weights[def.Id] = def.Weight
					end
				end
				local id = Tables.weightedPick(weights, rng)
				if id then
					self:StartEvent(id)
				else
					scheduleNext()
				end
			end
		end
	end)
end

return EventService
