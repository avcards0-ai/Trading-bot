--[[
	WorldController
	Client-side animation of the world, all deterministic or attribute-driven so the server
	never has to replicate motion:
	  * Lasers and security cameras follow SecurityPatterns on server time
	  * Trap re-arm visuals, flickering lab lights, spinning statues
	  * Vault alarm lights + zone alarm tint, the High-Security Vault countdown board
	  * Mood lighting: Underground caves, Blackout night + flashlight, Golden Hour, Low Gravity
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local SecurityPatterns = require(Shared.SecurityPatterns)
local Zones = require(Shared.Config.Zones)
local Format = require(Shared.Util.Format)

local player = Players.LocalPlayer

local WorldController = { Name = "WorldController" }

local controllers: { [string]: any }

type Laser = {
	Part: BasePart,
	Base: CFrame,
	Pattern: string,
	Speed: number,
	Phase: number,
	Amplitude: number,
	Axis: Vector3,
	Owner: string,
}
type Cam = {
	Head: BasePart,
	Lens: BasePart?,
	Position: Vector3,
	BaseYaw: number,
	Sweep: number,
	Speed: number,
	Phase: number,
	Pitch: number,
	Owner: string,
}

local lasers: { [BasePart]: Laser } = {}
local cams: { [BasePart]: Cam } = {}
local spinners: { [BasePart]: CFrame } = {}
local tint: ColorCorrectionEffect
local flashlight: SpotLight?
local moodState = ""
local currentZone: string? = nil
local alarmTinting = false

function WorldController:Init(all)
	controllers = all
end

local function ownerIsMe(owner: string): boolean
	local kind, id = string.match(owner, "^(%a+):(.+)$")
	if kind == "Plot" then
		local index = controllers.DataController:GetSession("PlotIndex")
		return tostring(index) == id
	elseif kind == "Carrier" then
		return tostring(player.UserId) == id
	end
	return false
end

-- Registration (stream-aware) -------------------------------------------------------------------

local function addLaser(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local base = part:GetAttribute("BaseCFrame")
	lasers[part] = {
		Part = part,
		Base = typeof(base) == "CFrame" and base or part.CFrame,
		Pattern = tostring(part:GetAttribute("Pattern") or "Static"),
		Speed = tonumber(part:GetAttribute("Speed")) or 0,
		Phase = tonumber(part:GetAttribute("Phase")) or 0,
		Amplitude = tonumber(part:GetAttribute("Amplitude")) or 0,
		Axis = (part:GetAttribute("Axis") :: Vector3?) or Vector3.yAxis,
		Owner = tostring(part:GetAttribute("Owner") or ""),
	}
end

local function addCamera(head: Instance)
	if not head:IsA("BasePart") then
		return
	end
	local model = head.Parent
	cams[head] = {
		Head = head,
		Lens = model and model:FindFirstChild("Lens") :: BasePart?,
		Position = head.Position,
		BaseYaw = tonumber(head:GetAttribute("BaseYaw")) or 0,
		Sweep = tonumber(head:GetAttribute("Sweep")) or 0,
		Speed = tonumber(head:GetAttribute("Speed")) or 0,
		Phase = tonumber(head:GetAttribute("Phase")) or 0,
		Pitch = tonumber(head:GetAttribute("Pitch")) or 28,
		Owner = tostring(head:GetAttribute("Owner") or ""),
	}
end

local function track(tag: string, add: (Instance) -> (), store: { [any]: any })
	for _, inst in CollectionService:GetTagged(tag) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		store[inst] = nil
	end)
end

-- Mood lighting ----------------------------------------------------------------------------------

local MOODS = {
	Day = {
		ClockTime = 14.5,
		Brightness = 2.4,
		Ambient = Color3.fromRGB(70, 70, 85),
		OutdoorAmbient = Color3.fromRGB(140, 140, 160),
		FogEnd = 100000,
		FogColor = Color3.fromRGB(200, 215, 240),
		Tint = Color3.new(1, 1, 1),
		TintBrightness = 0,
	},
	Cave = {
		ClockTime = 14.5,
		Brightness = 0.4,
		Ambient = Color3.fromRGB(40, 30, 70),
		OutdoorAmbient = Color3.fromRGB(30, 25, 55),
		FogEnd = 260,
		FogColor = Color3.fromRGB(20, 15, 40),
		Tint = Color3.fromRGB(210, 200, 255),
		TintBrightness = -0.02,
	},
	Blackout = {
		ClockTime = 0.2,
		Brightness = 0.6,
		Ambient = Color3.fromRGB(25, 25, 45),
		OutdoorAmbient = Color3.fromRGB(40, 40, 70),
		FogEnd = 600,
		FogColor = Color3.fromRGB(10, 10, 25),
		Tint = Color3.fromRGB(190, 200, 255),
		TintBrightness = -0.04,
	},
	GoldenHour = {
		ClockTime = 17.6,
		Brightness = 2.6,
		Ambient = Color3.fromRGB(90, 70, 60),
		OutdoorAmbient = Color3.fromRGB(170, 130, 100),
		FogEnd = 100000,
		FogColor = Color3.fromRGB(255, 200, 150),
		Tint = Color3.fromRGB(255, 225, 190),
		TintBrightness = 0.03,
	},
	LowGravity = {
		ClockTime = 21,
		Brightness = 1.4,
		Ambient = Color3.fromRGB(80, 60, 120),
		OutdoorAmbient = Color3.fromRGB(120, 100, 170),
		FogEnd = 100000,
		FogColor = Color3.fromRGB(120, 100, 170),
		Tint = Color3.fromRGB(230, 210, 255),
		TintBrightness = 0,
	},
}

local function applyMood(name: string)
	if name == moodState then
		return
	end
	moodState = name
	local mood = MOODS[name] or MOODS.Day
	local info = TweenInfo.new(2, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, {
		ClockTime = mood.ClockTime,
		Brightness = mood.Brightness,
		Ambient = mood.Ambient,
		OutdoorAmbient = mood.OutdoorAmbient,
		FogEnd = mood.FogEnd,
		FogColor = mood.FogColor,
	}):Play()
	TweenService:Create(tint, info, { TintColor = mood.Tint, Brightness = mood.TintBrightness }):Play()
	-- Flashlight during a blackout or underground
	local wantsLight = name == "Blackout" or name == "Cave"
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if wantsLight and head and not (flashlight and flashlight.Parent == head) then
		local light = Instance.new("SpotLight")
		light.Name = "Flashlight"
		light.Range = 50
		light.Angle = 55
		light.Brightness = 2.5
		light.Color = Color3.fromRGB(255, 245, 220)
		light.Shadows = true
		light.Parent = head
		flashlight = light
	elseif not wantsLight and flashlight then
		flashlight:Destroy()
		flashlight = nil
	end
end

local function zoneBanner(zoneId: string?)
	if zoneId == currentZone then
		return
	end
	currentZone = zoneId
	local zone = zoneId and Zones.get(zoneId)
	if zone and zone.Id ~= "SecretRoom" then
		controllers.AnnouncementController:Toast("info", string.format("%s %s - %s", zone.Icon, zone.Name, zone.Blurb))
	end
end

-- Per-frame --------------------------------------------------------------------------------------

local function animateDevices(t: number)
	local blackout = ReplicatedStorage:GetAttribute("EventId") == "Blackout"
	for part, laser in lasers do
		if not part.Parent then
			lasers[part] = nil
			continue
		end
		local on, offset = SecurityPatterns.laser(laser.Pattern, laser.Speed, laser.Phase, laser.Amplitude, t)
		if blackout and string.sub(laser.Owner, 1, 5) == "Zone:" then
			on = false
		end
		part.CFrame = laser.Base + laser.Axis * offset
		local mine = ownerIsMe(laser.Owner)
		part.LocalTransparencyModifier = on and (mine and 0.7 or 0) or 1
	end
	for head, cam in cams do
		if not head.Parent then
			cams[head] = nil
			continue
		end
		local yaw = SecurityPatterns.cameraYaw(cam.BaseYaw, cam.Sweep, cam.Speed, cam.Phase, t)
		local cf = SecurityPatterns.cameraCFrame(cam.Position, yaw, cam.Pitch)
		head.CFrame = cf
		if cam.Lens then
			cam.Lens.CFrame = cf * CFrame.new(0, 0, -1.25)
		end
		local cone = head:FindFirstChild("ViewCone") :: SpotLight?
		if cone then
			cone.Enabled = not (blackout and string.sub(cam.Owner, 1, 5) == "Zone:")
		end
	end
end

local function animateMisc(now: number, t: number)
	for _, trap in CollectionService:GetTagged("Trap") do
		if trap:IsA("BasePart") then
			local readyAt = trap:GetAttribute("ReadyAt")
			local armed = type(readyAt) ~= "number" or readyAt <= now
			local modifier = armed and 0 or 0.85
			trap.LocalTransparencyModifier = modifier
			for _, child in trap:GetChildren() do
				if child:IsA("BasePart") then
					child.LocalTransparencyModifier = modifier
				end
			end
		end
	end
	for _, part in CollectionService:GetTagged("Flicker") do
		if part:IsA("BasePart") and math.random() < 0.08 then
			part.LocalTransparencyModifier = math.random() < 0.5 and 0.7 or 0
		end
	end
	for part, base in spinners do
		if part.Parent then
			part.CFrame = base * CFrame.Angles(0, t * (tonumber(part:GetAttribute("Spin")) or 0.5), 0)
		else
			spinners[part] = nil
		end
	end

	-- Plot alarm lights
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			local alarmUntil = plot:GetAttribute("AlarmUntil")
			local alarming = type(alarmUntil) == "number" and alarmUntil > now
			for _, child in plot:GetChildren() do
				if child.Name == "AlarmLight" and child:IsA("BasePart") then
					local on = alarming and math.floor(t * 6) % 2 == 0
					child.Color = on and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(110, 30, 30)
				end
			end
		end
	end

	-- High-Security Vault countdown board
	local vault = map and map:FindFirstChild("HighSecurityVault")
	if vault then
		local board = vault:FindFirstChild("TimerBoard")
		local gui = board and board:FindFirstChild("Timer")
		local label = gui and gui:FindFirstChild("TimerText") :: TextLabel?
		local change = vault:GetAttribute("DoorChangeAt")
		if label and type(change) == "number" then
			if vault:GetAttribute("DoorOpen") then
				label.Text = "OPEN! CLOSES IN " .. Format.clock(change - now)
				label.TextColor3 = Color3.fromRGB(90, 255, 130)
			else
				label.Text = "OPENS IN " .. Format.clock(change - now)
				label.TextColor3 = Color3.fromRGB(255, 80, 80)
			end
		end
	end
end

local function updateMood(now: number, t: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local eventId = ReplicatedStorage:GetAttribute("EventId")
	local mood = "Day"
	if root and root.Position.Y < -40 then
		mood = "Cave"
	elseif eventId == "Blackout" then
		mood = "Blackout"
	elseif eventId == "GoldenHour" then
		mood = "GoldenHour"
	elseif eventId == "LowGravity" then
		mood = "LowGravity"
	end
	applyMood(mood)

	-- Zone entry toast + red alarm tint while inside an alarmed zone
	local zone = root and Zones.at(root.Position)
	zoneBanner(zone and zone.Id or nil)
	local alarm = false
	if zone then
		local map = workspace:FindFirstChild("Map")
		local folderName = ({ Vault = "HighSecurityVault" })[zone.Id] or zone.Id
		local folder = map and map:FindFirstChild(folderName)
		local alarmUntil = folder and folder:GetAttribute("AlarmUntil")
		alarm = type(alarmUntil) == "number" and alarmUntil > now
	end
	local settings = controllers.DataController:Get("Settings")
	local reduce = type(settings) == "table" and settings.ReduceFlashing
	if alarm and not reduce then
		alarmTinting = true
		local pulse = (math.sin(t * 6) + 1) / 2
		tint.TintColor = (MOODS[moodState] or MOODS.Day).Tint:Lerp(Color3.fromRGB(255, 120, 120), pulse * 0.6)
	elseif alarmTinting then
		alarmTinting = false
		tint.TintColor = (MOODS[moodState] or MOODS.Day).Tint
	end
end

function WorldController:Start()
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "ClientMood"
	tint.Parent = Lighting

	track("Laser", addLaser, lasers)
	track("SecurityCameraHead", addCamera, cams)
	track("Spinner", function(part)
		if part:IsA("BasePart") then
			spinners[part] = part.CFrame
		end
	end, spinners)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		local now = workspace:GetServerTimeNow()
		local t = os.clock()
		animateDevices(now)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			animateMisc(now, t)
			updateMood(now, t)
		end
	end)

	player.CharacterAdded:Connect(function()
		moodState = ""
		flashlight = nil
	end)
end

return WorldController
