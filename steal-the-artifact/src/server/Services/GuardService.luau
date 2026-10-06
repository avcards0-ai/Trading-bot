--[[
	GuardService
	NPC guards for zones (museum security, lab robots, temple mummies, warehouse soldiers,
	elite vault guards) and for player vaults (bought with the Guards security upgrade).

	Server-owned R6 rigs built from parts, animated with Roblox's default R6 animations.
	Cheap state machine on a 5 Hz tick: patrol -> spot -> chase (direct MoveTo with line of
	sight, PathfindingService when blocked) -> tackle (loot drops) -> give up at the leash.
	Guards bark funny lines that clients render as speech bubbles.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Security = require(Shared.Config.Security)
local Zones = require(Shared.Config.Zones)
local Animations = require(Shared.Config.Animations)
local Tables = require(Shared.Util.Tables)

local GuardService = { Name = "GuardService" }

local S: { [string]: any }

type Guard = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Style: string,
	ZoneId: string?,
	PlotIndex: number?,
	Patrol: { Vector3 },
	PatrolIndex: number,
	PatrolSince: number,
	Home: Vector3,
	Leash: number,
	PatrolSpeed: number,
	ChaseSpeed: number,
	Sight: number,
	Target: Player?,
	LastSeen: number,
	Waypoints: { Vector3 }?,
	WaypointIndex: number,
	PathBusy: boolean,
	NextPathAt: number,
	LastPos: Vector3,
	StuckSince: number,
	TackleReadyAt: number,
	Ignore: { [Player]: number },
	NextBarkAt: number,
	WalkTrack: AnimationTrack?,
	IdleTrack: AnimationTrack?,
}

local guards: { Guard } = {}
local folder: Folder

local BARKS = {
	Spot = { "HEY! Put that back!", "STOP, THIEF!", "Not on my watch!", "I see you!", "FREEZE!", "Oh no you don't!" },
	Tackle = { "GOTCHA!", "Nice try!", "Caught red-handed!", "Book 'em!", "And STAY down!" },
	Lost = { "Where'd they go?", "*huff* *puff*", "I'm too old for this...", "Must've been the wind.", "I'll get you next time!" },
	Strike = { "ON STRIKE!", "Fair wages for guards!", "Not my problem today!", "Union rules, pal." },
	Idle = { "*yawn*", "Quiet night...", "I love my job.", "Did I leave the stove on?", "*whistles*" },
	RobotSpot = { "INTRUDER DETECTED.", "BEEP BOOP. STOP.", "TARGET ACQUIRED.", "ERROR: THIEF FOUND." },
	MummySpot = { "Mmmmhhh!!", "*angry mummy noises*", "CURSE YOUUU!", "Mmmph mmph!" },
	Sleepy = { "Zzz...", "*snore*", "Five more minutes...", "Huh? Wha-?" },
}

local STYLES = {
	Security = { Torso = Color3.fromRGB(40, 60, 130), Arms = Color3.fromRGB(40, 60, 130), Legs = Color3.fromRGB(30, 30, 40), Head = Color3.fromRGB(245, 205, 160), Hat = "Cap", HatColor = Color3.fromRGB(30, 45, 100) },
	Sleepy = { Torso = Color3.fromRGB(60, 80, 150), Arms = Color3.fromRGB(60, 80, 150), Legs = Color3.fromRGB(40, 40, 55), Head = Color3.fromRGB(245, 205, 160), Hat = "Nightcap", HatColor = Color3.fromRGB(80, 120, 220) },
	Robot = { Torso = Color3.fromRGB(150, 160, 175), Arms = Color3.fromRGB(120, 130, 145), Legs = Color3.fromRGB(100, 105, 120), Head = Color3.fromRGB(170, 180, 195), Hat = "Antenna", HatColor = Color3.fromRGB(90, 255, 140), Material = Enum.Material.Metal, BoxHead = true },
	Mummy = { Torso = Color3.fromRGB(225, 215, 185), Arms = Color3.fromRGB(225, 215, 185), Legs = Color3.fromRGB(215, 205, 175), Head = Color3.fromRGB(230, 220, 190), Hat = "None", HatColor = Color3.fromRGB(0, 0, 0), Material = Enum.Material.Fabric, GlowEyes = Color3.fromRGB(120, 255, 170) },
	Soldier = { Torso = Color3.fromRGB(95, 110, 70), Arms = Color3.fromRGB(95, 110, 70), Legs = Color3.fromRGB(75, 85, 55), Head = Color3.fromRGB(220, 180, 140), Hat = "Helmet", HatColor = Color3.fromRGB(80, 95, 60), Shades = true },
	Elite = { Torso = Color3.fromRGB(25, 25, 30), Arms = Color3.fromRGB(25, 25, 30), Legs = Color3.fromRGB(20, 20, 25), Head = Color3.fromRGB(240, 200, 160), Hat = "Earpiece", HatColor = Color3.fromRGB(255, 200, 60), Shades = true, Tie = true },
}

function GuardService:Init(services)
	S = services
end

-- Rig ----------------------------------------------------------------------------------------

local function part(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
end

local function accessory(model: Model, head: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = part(model, "Accessory", size, color, material)
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.Massless = true
	p.CFrame = head.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function buildRig(styleName: string, position: Vector3): Model
	local style = STYLES[styleName] or STYLES.Security
	local model = Instance.new("Model")
	model.Name = styleName .. "Guard"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local mat = style.Material
	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), style.Torso)
	root.Transparency = 1
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), style.Torso, mat)
	local head = part(model, "Head", Vector3.new(2, 1, 1), style.Head, mat)
	if not style.BoxHead then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Head
		mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
		mesh.Parent = head
	end
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head
	local leftArm = part(model, "Left Arm", Vector3.new(1, 2, 1), style.Arms, mat)
	local rightArm = part(model, "Right Arm", Vector3.new(1, 2, 1), style.Arms, mat)
	local leftLeg = part(model, "Left Leg", Vector3.new(1, 2, 1), style.Legs, mat)
	local rightLeg = part(model, "Right Leg", Vector3.new(1, 2, 1), style.Legs, mat)
	for _, limb in { leftArm, rightArm, leftLeg, rightLeg } do
		limb.CanCollide = false
	end

	local rootCF = CFrame.new(position)
	root.CFrame = rootCF
	torso.CFrame = rootCF
	head.CFrame = rootCF * CFrame.new(0, 1.5, 0)
	leftArm.CFrame = rootCF * CFrame.new(-1.5, 0, 0)
	rightArm.CFrame = rootCF * CFrame.new(1.5, 0, 0)
	leftLeg.CFrame = rootCF * CFrame.new(-0.5, -2, 0)
	rightLeg.CFrame = rootCF * CFrame.new(0.5, -2, 0)

	-- Standard R6 joints (so Roblox's default R6 animations play correctly)
	local axis = CFrame.fromMatrix(Vector3.zero, Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1))
	motor("RootJoint", root, torso, axis, axis)
	motor("Neck", torso, head, CFrame.new(0, 1, 0) * axis, CFrame.new(0, -0.5, 0) * axis)
	motor("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, rightLeg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, leftLeg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

	-- Style accessories
	if style.Hat == "Cap" then
		accessory(model, head, Vector3.new(1.35, 0.45, 1.3), CFrame.new(0, 0.6, 0), style.HatColor)
		accessory(model, head, Vector3.new(1.3, 0.12, 0.6), CFrame.new(0, 0.42, -0.85), style.HatColor)
		accessory(model, head, Vector3.new(0.3, 0.3, 0.05), CFrame.new(0, 0.62, -0.66), Color3.fromRGB(255, 205, 60), Enum.Material.Neon)
	elseif style.Hat == "Nightcap" then
		accessory(model, head, Vector3.new(1.3, 0.6, 1.3), CFrame.new(0, 0.6, 0), style.HatColor)
		accessory(model, head, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0.5, 0.9, 0.4), Color3.new(1, 1, 1), nil, Enum.PartType.Ball)
	elseif style.Hat == "Antenna" then
		accessory(model, head, Vector3.new(0.15, 1, 0.15), CFrame.new(0, 1, 0), Color3.fromRGB(80, 80, 90), Enum.Material.Metal)
		accessory(model, head, Vector3.new(0.35, 0.35, 0.35), CFrame.new(0, 1.55, 0), style.HatColor, Enum.Material.Neon, Enum.PartType.Ball)
		accessory(model, head, Vector3.new(1.6, 0.25, 0.1), CFrame.new(0, 0.1, -0.55), style.HatColor, Enum.Material.Neon)
		face:Destroy()
	elseif style.Hat == "Helmet" then
		local helmet = accessory(model, head, Vector3.new(1.45, 1.45, 1.45), CFrame.new(0, 0.35, 0), style.HatColor, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		helmet.Name = "Helmet"
	elseif style.Hat == "Earpiece" then
		accessory(model, head, Vector3.new(0.12, 0.6, 0.12), CFrame.new(0.68, -0.1, 0), style.HatColor, Enum.Material.Neon)
	end
	if style.Shades then
		accessory(model, head, Vector3.new(1.15, 0.22, 0.1), CFrame.new(0, 0.18, -0.6), Color3.fromRGB(15, 15, 20))
	end
	if style.GlowEyes then
		face:Destroy()
		accessory(model, head, Vector3.new(0.18, 0.12, 0.05), CFrame.new(-0.25, 0.15, -0.6), style.GlowEyes, Enum.Material.Neon)
		accessory(model, head, Vector3.new(0.18, 0.12, 0.05), CFrame.new(0.25, 0.15, -0.6), style.GlowEyes, Enum.Material.Neon)
	end
	if style.Tie then
		local tie = part(model, "Tie", Vector3.new(0.3, 1.2, 0.05), Color3.fromRGB(200, 30, 40))
		tie.CanCollide = false
		tie.Massless = true
		tie.CFrame = torso.CFrame * CFrame.new(0, 0.2, -0.53)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = tie
		weld.Parent = tie
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	model.PrimaryPart = root
	return model
end

-- Lifecycle --------------------------------------------------------------------------------

local function bark(guard: Guard, kind: string)
	local now = os.clock()
	if now < guard.NextBarkAt then
		return
	end
	guard.NextBarkAt = now + 3
	local key = kind
	if kind == "Spot" and guard.Style == "Robot" then
		key = "RobotSpot"
	elseif kind == "Spot" and guard.Style == "Mummy" then
		key = "MummySpot"
	end
	local line = Tables.pickRandom(BARKS[key] or BARKS[kind])
	if line then
		guard.Model:SetAttribute("Bark", line)
		guard.Model:SetAttribute("BarkAt", workspace:GetServerTimeNow())
	end
end

local function spawnGuard(style: string, position: Vector3, patrol: { Vector3 }, options: { ZoneId: string?, PlotIndex: number?, Leash: number, PatrolSpeed: number, ChaseSpeed: number, Sight: number }): Guard
	local model = buildRig(style, position + Vector3.new(0, 1, 0))
	model.Parent = folder
	model.PrimaryPart:SetNetworkOwner(nil)
	CollectionService:AddTag(model, "Guard")
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = options.PatrolSpeed
	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator
	local walkAnim = Instance.new("Animation")
	walkAnim.AnimationId = Animations.R6.Walk
	local idleAnim = Instance.new("Animation")
	idleAnim.AnimationId = Animations.R6.Idle
	local walkTrack, idleTrack
	pcall(function()
		walkTrack = animator:LoadAnimation(walkAnim)
		walkTrack.Looped = true
		idleTrack = animator:LoadAnimation(idleAnim)
		idleTrack.Looped = true
		idleTrack:Play()
	end)
	local guard: Guard = {
		Model = model,
		Humanoid = humanoid,
		Root = model.PrimaryPart :: BasePart,
		Style = style,
		ZoneId = options.ZoneId,
		PlotIndex = options.PlotIndex,
		Patrol = patrol,
		PatrolIndex = math.random(1, math.max(1, #patrol)),
		PatrolSince = os.clock(),
		Home = position,
		Leash = options.Leash,
		PatrolSpeed = options.PatrolSpeed,
		ChaseSpeed = options.ChaseSpeed,
		Sight = options.Sight,
		Target = nil,
		LastSeen = 0,
		Waypoints = nil,
		WaypointIndex = 1,
		PathBusy = false,
		NextPathAt = 0,
		LastPos = position,
		StuckSince = os.clock(),
		TackleReadyAt = 0,
		Ignore = {},
		NextBarkAt = os.clock() + math.random() * 10,
		WalkTrack = walkTrack,
		IdleTrack = idleTrack,
	}
	table.insert(guards, guard)
	return guard
end

local function removeGuard(guard: Guard)
	local index = table.find(guards, guard)
	if index then
		table.remove(guards, index)
	end
	guard.Model:Destroy()
end

-- AI ------------------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function lineOfSight(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	rayParams.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(from, to - from, rayParams)
	return result == nil or not result.Instance.CanCollide
end

local function carryingFromZone(player: Player, zoneId: string): boolean
	for _, record in S.CarryService:Get(player) do
		if record.Z == zoneId then
			return true
		end
	end
	return false
end

-- Is `player` a valid target for this guard?
local function isHostile(guard: Guard, player: Player): boolean
	if (guard.Ignore[player] or 0) > os.clock() then
		return false
	end
	if not S.PlayerService:IsAlive(player) or S.PlayerService:HasStatus(player, "Protected") then
		return false
	end
	if guard.PlotIndex then
		return S.RaidService:IsIntruding(player, guard.PlotIndex)
	end
	local zoneId = guard.ZoneId :: string
	return S.SecurityService:IsWanted(player, zoneId) or carryingFromZone(player, zoneId)
end

local function setAnimation(guard: Guard, moving: boolean)
	if not guard.WalkTrack or not guard.IdleTrack then
		return
	end
	if moving and not guard.WalkTrack.IsPlaying then
		guard.IdleTrack:Stop(0.2)
		guard.WalkTrack:Play(0.2)
	elseif not moving and guard.WalkTrack.IsPlaying then
		guard.WalkTrack:Stop(0.2)
		guard.IdleTrack:Play(0.2)
	end
	if moving then
		guard.WalkTrack:AdjustSpeed(guard.Humanoid.WalkSpeed / 14)
	end
end

local function requestPath(guard: Guard, goal: Vector3)
	if guard.PathBusy or os.clock() < guard.NextPathAt then
		return
	end
	guard.PathBusy = true
	guard.NextPathAt = os.clock() + 1
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function()
			path:ComputeAsync(guard.Root.Position, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local points = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
			guard.Waypoints = points
			guard.WaypointIndex = math.min(2, #points)
		else
			guard.Waypoints = nil
		end
		guard.PathBusy = false
	end)
end

local function moveToward(guard: Guard, goal: Vector3, ignore: { Instance })
	local from = guard.Root.Position
	if lineOfSight(from, goal, ignore) then
		guard.Waypoints = nil
		guard.Humanoid:MoveTo(goal)
		return
	end
	requestPath(guard, goal)
	local points = guard.Waypoints
	if points and points[guard.WaypointIndex] then
		local waypoint = points[guard.WaypointIndex]
		if (Vector3.new(waypoint.X, from.Y, waypoint.Z) - from).Magnitude < 3 then
			guard.WaypointIndex += 1
			waypoint = points[guard.WaypointIndex] or goal
		end
		guard.Humanoid:MoveTo(waypoint)
	else
		guard.Humanoid:MoveTo(goal)
	end
end

local function updateGuard(guard: Guard, ignore: { Instance })
	local root = guard.Root
	if not root.Parent then
		return
	end
	local position = root.Position
	local strike = guard.ZoneId ~= nil and S.EventService:IsActive("GuardStrike")
	local moving = root.AssemblyLinearVelocity.Magnitude > 1.5
	setAnimation(guard, moving)

	if strike then
		guard.Target = nil
		guard.Humanoid:MoveTo(position)
		if math.random() < 0.05 then
			bark(guard, "Strike")
		end
		return
	end

	-- Acquire / keep target
	local target = guard.Target
	if target and (not target.Parent or not isHostile(guard, target)) then
		target = nil
	end
	if not target then
		local bestDistance = guard.Sight
		for _, player in Players:GetPlayers() do
			local proot = S.PlayerService:GetRoot(player)
			if proot and isHostile(guard, player) then
				local distance = (proot.Position - position).Magnitude
				local alerted = guard.ZoneId and S.SecurityService:IsWanted(player, guard.ZoneId)
				if (distance < bestDistance or (alerted and distance < guard.Leash)) and (alerted or lineOfSight(position + Vector3.new(0, 1.5, 0), proot.Position, ignore)) then
					target = player
					bestDistance = distance
				end
			end
		end
		if target then
			bark(guard, guard.Style == "Sleepy" and "Sleepy" or "Spot")
		end
	end
	if guard.Target and not target then
		bark(guard, "Lost")
	end
	guard.Target = target

	-- Leash: never chase too far from home
	if target then
		local proot = S.PlayerService:GetRoot(target)
		if not proot or (proot.Position - guard.Home).Magnitude > guard.Leash then
			guard.Target = nil
			target = nil
		end
	end

	if target then
		local proot = S.PlayerService:GetRoot(target) :: BasePart
		guard.Humanoid.WalkSpeed = guard.ChaseSpeed
		moveToward(guard, proot.Position, ignore)
		if (proot.Position - position).Magnitude <= GameConfig.Security.GuardTackleRange and os.clock() >= guard.TackleReadyAt then
			guard.TackleReadyAt = os.clock() + 2.2
			guard.Ignore[target] = os.clock() + 4
			bark(guard, "Tackle")
			local styleName = guard.Style == "Robot" and "a robot" or guard.Style == "Mummy" and "a mummy" or "a guard"
			S.CombatService:ApplyFail(target, "Tackle", {
				Damage = GameConfig.Security.GuardTackleDamage,
				Stun = GameConfig.Security.GuardTackleStun,
				Drop = 1,
				By = styleName,
				Knockback = (proot.Position - position).Unit * 40 + Vector3.new(0, 30, 0),
			})
			guard.Target = nil
		end
	else
		-- Patrol
		guard.Humanoid.WalkSpeed = guard.PatrolSpeed
		local point = guard.Patrol[guard.PatrolIndex]
		if point then
			local flat = Vector3.new(point.X - position.X, 0, point.Z - position.Z).Magnitude
			if flat < 4 or os.clock() - guard.PatrolSince > 12 then
				guard.PatrolIndex = guard.PatrolIndex % #guard.Patrol + 1
				guard.PatrolSince = os.clock()
				point = guard.Patrol[guard.PatrolIndex]
			end
			moveToward(guard, point, ignore)
		end
		if math.random() < 0.004 then
			bark(guard, guard.Style == "Sleepy" and "Sleepy" or "Idle")
		end
	end

	-- Unstick: jump if we haven't moved while trying to
	if (position - guard.LastPos).Magnitude > 0.6 then
		guard.LastPos = position
		guard.StuckSince = os.clock()
	elseif os.clock() - guard.StuckSince > 1.6 then
		guard.Humanoid.Jump = true
		guard.StuckSince = os.clock()
		guard.Waypoints = nil
		if not target and #guard.Patrol > 0 then
			guard.PatrolIndex = guard.PatrolIndex % #guard.Patrol + 1
		end
	end
	-- Fell out of the world? Back to post.
	if position.Y < -200 then
		guard.Model:PivotTo(CFrame.new(guard.Home + Vector3.new(0, 3, 0)))
	end
end

-- Public -------------------------------------------------------------------------------------

function GuardService:Alert(zoneId: string, player: Player)
	for _, guard in guards do
		if guard.ZoneId == zoneId and not guard.Target then
			local proot = S.PlayerService:GetRoot(player)
			if proot and (proot.Position - guard.Home).Magnitude < guard.Leash then
				guard.Target = player
				bark(guard, "Spot")
			end
		end
	end
end

function GuardService:ClearPlot(index: number)
	for i = #guards, 1, -1 do
		if guards[i].PlotIndex == index then
			removeGuard(guards[i])
		end
	end
end

function GuardService:RefreshPlot(player: Player)
	local index = S.PlotService:GetPlotIndex(player)
	local data = S.DataService:Get(player)
	if not index or not data then
		return
	end
	self:ClearPlot(index)
	local level = data.Security.Guards or 0
	local count = Security.stat("Guards", "Count", level)
	if count <= 0 then
		return
	end
	local plot = S.MapService:GetPlot(index)
	local style = level <= 1 and "Sleepy" or (level >= 5 and "Elite" or "Security")
	local speed = Security.stat("Guards", "Speed", level)
	for i = 1, count do
		spawnGuard(style, (plot.GuardSpawn * CFrame.new((i - 1) * 4 - 4, 0, 0)).Position, plot.Patrol, {
			PlotIndex = index,
			Leash = 40,
			PatrolSpeed = 7,
			ChaseSpeed = speed,
			Sight = Security.stat("Guards", "Sight", level),
		})
	end
end

function GuardService:Start()
	folder = Instance.new("Folder")
	folder.Name = "Guards"
	folder.Parent = workspace

	local map = S.MapService:Get()
	for _, zone in Zones.List do
		local zoneData = map.Zones[zone.Id]
		if zone.Guards > 0 and zoneData and #zoneData.Patrol > 0 then
			local elite = zone.GuardStyle == "Elite"
			for i = 1, zone.Guards do
				local start = zoneData.Patrol[(i - 1) % #zoneData.Patrol + 1]
				spawnGuard(zone.GuardStyle or "Security", start, zoneData.Patrol, {
					ZoneId = zone.Id,
					Leash = zone.Radius + 70,
					PatrolSpeed = elite and 9 or 8,
					ChaseSpeed = elite and 20.5 or 18.5,
					Sight = elite and 48 or 40,
				})
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.2)
			local ignore: { Instance } = { folder }
			local artifacts = workspace:FindFirstChild("Artifacts")
			if artifacts then
				table.insert(ignore, artifacts)
			end
			for _, player in Players:GetPlayers() do
				if player.Character then
					table.insert(ignore, player.Character)
				end
			end
			for _, guard in table.clone(guards) do
				local ok, err = pcall(updateGuard, guard, ignore)
				if not ok then
					warn("[Guards]", err)
				end
			end
		end
	end)
end

return GuardService
