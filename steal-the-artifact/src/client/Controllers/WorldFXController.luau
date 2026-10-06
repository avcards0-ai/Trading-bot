--[[
	WorldFXController
	World-space VFX driven by the server's unreliable "Effect" remote (steal bursts, BONK
	popups, secure confetti, meteors...) plus status visuals on every character:
	dizzy stars, WANTED / MARKED highlights, hot-loot beacons, bounties and the unique
	effects of SECRET artifacts. Also renders guard speech bubbles.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local UIFolder = script.Parent.Parent.UI
local Components = require(UIFolder.Components)
local Theme = require(UIFolder.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local WorldFXController = { Name = "WorldFXController" }

local controllers: { [string]: any }
local Data
local fxFolder: Folder

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

function WorldFXController:Init(all)
	controllers = all
	Data = all.DataController
end

local function vfxQuality(): string
	local settings = Data:Get("Settings")
	return type(settings) == "table" and settings.VFX or "High"
end

local function characterOf(userId: number?): Model?
	local target = userId and Players:GetPlayerByUserId(userId)
	return target and target.Character or nil
end

-- Primitives ----------------------------------------------------------------------------------

local function anchorAt(position: Vector3, lifetime: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	Debris:AddItem(attachment, lifetime)
	return attachment
end

local function burst(position: Vector3, color: Color3, count: number, options: { [string]: any }?)
	local opts = options or {}
	if vfxQuality() == "Low" then
		count = math.ceil(count / 3)
	end
	local attachment = anchorAt(position, 3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = opts.Texture or SPARKLES
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.5, opts.Lifetime or 1.1)
	emitter.Speed = NumberRange.new(opts.Speed or 14, (opts.Speed or 14) * 1.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, opts.Size or 1.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Acceleration = opts.Acceleration or Vector3.new(0, -20, 0)
	emitter.Drag = 2
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
	if opts.Light then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 20
		light.Brightness = 4
		light.Parent = attachment
		TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	end
end

local function popup(position: Vector3, text: string, color: Color3, size: number?)
	controllers.EffectsController:FloatText(position + Vector3.new(0, 3, 0), text, color, size)
end

local function beam(position: Vector3, color: Color3, height: number, duration: number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, 4, 4)
	part.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Transparency = 0.2
	part.Parent = fxFolder
	TweenService:Create(
		part,
		TweenInfo.new(duration, Enum.EasingStyle.Quad),
		{ Transparency = 1, Size = Vector3.new(height, 0.5, 0.5) }
	):Play()
	Debris:AddItem(part, duration + 0.1)
end

local function ring(position: Vector3, color: Color3, radius: number, duration: number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.3, 2, 2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Transparency = 0.3
	part.Parent = fxFolder
	TweenService:Create(
		part,
		TweenInfo.new(duration, Enum.EasingStyle.Quad),
		{ Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 }
	):Play()
	Debris:AddItem(part, duration + 0.1)
end

-- Cartoon hammer swing on any character ("Swing" effect).
local function swingHammer(character: Model)
	local arm = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not arm or not root then
		return
	end
	local model = Instance.new("Model")
	model.Name = "BonkHammer"
	local handle = Instance.new("Part")
	handle.Size = Vector3.new(0.4, 3.2, 0.4)
	handle.Color = Color3.fromRGB(150, 100, 60)
	handle.Material = Enum.Material.Wood
	local head = Instance.new("Part")
	head.Shape = Enum.PartType.Cylinder
	head.Size = Vector3.new(2.6, 1.8, 1.8)
	head.Color = Color3.fromRGB(255, 80, 120)
	head.Material = Enum.Material.SmoothPlastic
	for _, part in { handle, head } do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Parent = model
	end
	model.Parent = fxFolder
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / 0.28, 0, 1)
		if not arm.Parent then
			connection:Disconnect()
			model:Destroy()
			return
		end
		local angle = math.rad(-110 + t * 200)
		local base = root.CFrame * CFrame.new(0.9, 1.2, -0.5) * CFrame.Angles(angle, 0, 0)
		handle.CFrame = base * CFrame.new(0, 1.6, 0)
		head.CFrame = base * CFrame.new(0, 3.3, 0) * CFrame.Angles(0, math.rad(90), 0)
		if t >= 1 then
			connection:Disconnect()
			task.delay(0.08, function()
				model:Destroy()
			end)
		end
	end)
end

-- Meteor -------------------------------------------------------------------------------------

local function meteorIncoming(position: Vector3, impactAt: number)
	local warning = Instance.new("Part")
	warning.Anchored = true
	warning.CanCollide = false
	warning.CanQuery = false
	warning.Shape = Enum.PartType.Cylinder
	warning.Size = Vector3.new(0.2, 26, 26)
	warning.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	warning.Color = Color3.fromRGB(255, 80, 40)
	warning.Material = Enum.Material.Neon
	warning.Transparency = 0.5
	warning.Parent = fxFolder
	local rock = Instance.new("Part")
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanQuery = false
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.one * 9
	rock.Color = Color3.fromRGB(90, 60, 50)
	rock.Material = Enum.Material.Basalt
	rock.Parent = fxFolder
	local fire = Instance.new("Fire")
	fire.Size = 18
	fire.Heat = 20
	fire.Parent = rock
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 60
	light.Brightness = 4
	light.Parent = rock
	local from = position + Vector3.new(220, 420, -160)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local remaining = impactAt - workspace:GetServerTimeNow()
		local alpha = 1 - math.clamp(remaining / 8, 0, 1)
		rock.CFrame = CFrame.new(from:Lerp(position, alpha))
		warning.Transparency = 0.35 + math.sin(os.clock() * 12) * 0.25
		if remaining <= 0 then
			connection:Disconnect()
			rock:Destroy()
			warning:Destroy()
		end
	end)
end

local function meteorImpact(position: Vector3)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastPressure = 0
	explosion.BlastRadius = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
	burst(
		position + Vector3.new(0, 3, 0),
		Color3.fromRGB(255, 140, 60),
		60,
		{ Texture = FIRE, Speed = 40, Size = 4, Light = true }
	)
	ring(position + Vector3.new(0, 0.5, 0), Color3.fromRGB(255, 160, 80), 50, 1)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local distance = (root.Position - position).Magnitude
		controllers.EffectsController:Shake(math.clamp(3 - distance / 80, 0.2, 3), 1)
	end
	controllers.SoundController:PlayAt("Bonk", position, { Speed = 0.3, Volume = 2 })
end

-- Effect dispatch ---------------------------------------------------------------------------------

local HANDLERS: { [string]: (data: { [string]: any }) -> () } = {}

HANDLERS.Steal = function(data)
	local def = Artifacts.get(data.ArtifactId or "")
	if not def or typeof(data.Position) ~= "Vector3" then
		return
	end
	local rarity = Rarities.get(def.Rarity)
	local color = Theme.rarity(def.Rarity)
	burst(data.Position, color, 10 + rarity.Index * 6, { Light = rarity.Index >= 3 })
	if rarity.Index >= 4 then
		beam(data.Position, color, 60 + rarity.Index * 20, 1.4)
		ring(data.Position, color, 10 + rarity.Index * 2, 0.8)
	end
	if data.UserId ~= player.UserId then
		controllers.SoundController:PlayAt(rarity.Index >= 4 and "StealRare" or "Steal", data.Position)
		if rarity.Index >= 4 then
			popup(data.Position, string.upper(rarity.Name) .. "!", color, 30)
		end
	else
		controllers.SoundController:Play("Steal")
		if rarity.Index < 4 then
			popup(data.Position, "+" .. def.Icon .. " " .. def.Name, color, 22)
		end
	end
end

HANDLERS.Secure = function(data)
	if typeof(data.Position) ~= "Vector3" then
		return
	end
	burst(
		data.Position + Vector3.new(0, 2, 0),
		C.Success,
		40,
		{ Speed = 24, Acceleration = Vector3.new(0, -40, 0), Light = true }
	)
	ring(data.Position, C.Success, 14, 0.8)
	popup(data.Position, "+" .. Format.cash(data.Cash or 0), C.Cash, 40)
	if data.UserId == player.UserId then
		controllers.SoundController:Play("Secure")
		controllers.EffectsController:Confetti(C.Success, 24)
		controllers.EffectsController:Shake(0.25, 0.3)
	else
		controllers.SoundController:PlayAt("Secure", data.Position)
	end
end

HANDLERS.Bonk = function(data)
	if typeof(data.Position) ~= "Vector3" then
		return
	end
	popup(
		data.Position,
		(data.Dropped and data.Dropped > 0) and "BONK! 💥" or "BONK!",
		Color3.fromRGB(255, 220, 80),
		34
	)
	burst(data.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 240, 150), 14, { Speed = 10 })
	controllers.SoundController:PlayAt("Bonk", data.Position)
	if data.Attacker == player.UserId then
		controllers.EffectsController:Shake(0.25, 0.15)
	end
end

HANDLERS.FailPop = function(data)
	if typeof(data.Position) ~= "Vector3" or data.UserId == player.UserId then
		return
	end
	local colors = {
		Zap = Color3.fromRGB(110, 200, 255),
		Slip = Color3.fromRGB(255, 225, 60),
		Spring = Color3.fromRGB(255, 120, 120),
		Tackle = Color3.fromRGB(90, 140, 255),
	}
	local color = colors[data.Kind] or C.Accent
	popup(data.Position, tostring(data.Caption or "OOF!"), color, 28)
	if data.Kind == "Zap" then
		burst(data.Position, color, 20, { Speed = 18, Light = true })
		controllers.SoundController:PlayAt("Zap", data.Position)
	elseif data.Kind == "Spring" then
		controllers.SoundController:PlayAt("Spring", data.Position)
	else
		controllers.SoundController:PlayAt("Hurt", data.Position)
	end
end

HANDLERS.Swing = function(data)
	local character = characterOf(data.UserId)
	if character then
		swingHammer(character)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			controllers.SoundController:PlayAt("Whoosh", root.Position)
		end
	end
end

HANDLERS.Dash = function(data)
	local character = characterOf(data.UserId)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and data.UserId ~= player.UserId then
		burst(
			root.Position,
			Color3.fromRGB(220, 235, 255),
			12,
			{ Texture = SMOKE, Speed = 6, Size = 2.5, Acceleration = Vector3.zero }
		)
		controllers.SoundController:PlayAt("Dash", root.Position)
	end
end

HANDLERS.Spotted = function(data)
	local character = characterOf(data.UserId)
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if head then
		popup(head.Position + Vector3.new(0, 1, 0), "❗", C.Danger, 48)
	end
	if data.UserId == player.UserId then
		controllers.SoundController:Play("Alarm")
		controllers.AnnouncementController:Toast("warning", "📹 Spotted by a camera!")
	end
end

HANDLERS.ZoneAlarm = function(data)
	if typeof(data.Position) == "Vector3" then
		controllers.SoundController:PlayAt("Alarm", data.Position, { Volume = 2 })
	end
end

HANDLERS.Crack = function(data)
	if typeof(data.Position) == "Vector3" then
		burst(data.Position, Color3.fromRGB(255, 200, 80), 30, { Speed = 20, Light = true })
		controllers.SoundController:PlayAt("Zap", data.Position, { Speed = 0.6 })
	end
end

HANDLERS.Recover = function(data)
	if typeof(data.Position) == "Vector3" then
		burst(data.Position, C.Primary, 24, { Light = true })
		popup(data.Position, "RECOVERED!", C.Primary, 30)
	end
end

HANDLERS.Hatch = function(data)
	if typeof(data.Position) == "Vector3" then
		burst(
			data.Position,
			Color3.fromRGB(150, 130, 255),
			16,
			{ Texture = SMOKE, Speed = 5, Size = 3, Acceleration = Vector3.new(0, 4, 0) }
		)
	end
end

HANDLERS.Recall = function(data)
	if typeof(data.Position) == "Vector3" then
		beam(data.Position, C.Success, 40, 0.8)
		burst(data.Position, C.Success, 20, { Light = true })
	end
end

HANDLERS.Honk = function(data)
	if typeof(data.Position) == "Vector3" then
		controllers.SoundController:PlayAt("Honk", data.Position, { Volume = 1.5 })
		popup(data.Position + Vector3.new(0, 3, 0), "HONK! 🐔", Color3.fromRGB(255, 225, 60), 30)
	end
end

local function playerFlourish(data, color: Color3, text: string?)
	local character = characterOf(data.UserId)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		ring(root.Position - Vector3.new(0, 2.5, 0), color, 12, 0.8)
		burst(root.Position, color, 26, { Light = true })
		if text then
			popup(root.Position + Vector3.new(0, 3, 0), text, color, 30)
		end
	end
end

HANDLERS.LevelUp = function(data)
	playerFlourish(data, C.XP, data.UserId ~= player.UserId and "LEVEL UP!" or nil)
end
HANDLERS.Rebirth = function(data)
	local character = characterOf(data.UserId)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		beam(root.Position - Vector3.new(0, 3, 0), C.Accent, 200, 2.5)
	end
	playerFlourish(data, C.Accent, "REBIRTH!")
	if data.UserId == player.UserId then
		controllers.EffectsController:Flash(C.Accent, 0.6)
		controllers.EffectsController:Confetti(C.Accent, 60)
	end
end
HANDLERS.Achievement = function(data)
	playerFlourish(data, C.Accent, nil)
	if data.UserId == player.UserId then
		controllers.EffectsController:Confetti(C.Accent, 30)
		controllers.SoundController:Play("LevelUp", { Speed = 1.5 })
	end
end
HANDLERS.Purchase = function(data)
	playerFlourish(data, C.Gem, nil)
end
HANDLERS.VaultOpen = function()
	controllers.SoundController:Play("Announce", { Speed = 0.6 })
end
HANDLERS.VaultClose = function()
	controllers.SoundController:Play("Alarm", { Speed = 0.4 })
end
HANDLERS.MeteorIncoming = function(data)
	if typeof(data.Position) == "Vector3" and type(data.ImpactAt) == "number" then
		meteorIncoming(data.Position, data.ImpactAt)
	end
end
HANDLERS.MeteorImpact = function(data)
	if typeof(data.Position) == "Vector3" then
		meteorImpact(data.Position)
	end
end

-- Character status visuals --------------------------------------------------------------------

type Visuals = {
	Stars: BillboardGui?,
	Highlight: Highlight?,
	Wanted: BillboardGui?,
	Beacon: Beam?,
	BeaconA0: Attachment?,
	BeaconA1: Attachment?,
	Bounty: BillboardGui?,
	SecretFx: { Instance },
	SecretKey: string,
	Hot: string?,
}

local visuals: { [Model]: Visuals } = setmetatable({}, { __mode = "k" }) :: any

local function billboard(adornee: BasePart, text: string, color: Color3, offset: number, size: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size or 120, 44)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 200
	gui.Adornee = adornee
	local label =
		Components.label({ Text = text, TextColor3 = color, Font = Theme.Fonts.Title, MaxTextSize = 30, Parent = gui })
	Components.textStroke(label, 2)
	gui.Parent = fxFolder
	return gui
end

local function clearSecret(entry: Visuals)
	for _, inst in entry.SecretFx do
		inst:Destroy()
	end
	entry.SecretFx = {}
end

local function updateCharacter(character: Model, now: number, t: number)
	local head = character:FindFirstChild("Head") :: BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not head or not root then
		return
	end
	local entry = visuals[character]
	if not entry then
		entry = { SecretFx = {}, SecretKey = "" }
		visuals[character] = entry
	end
	local function active(name: string): boolean
		local value = character:GetAttribute(name)
		return type(value) == "number" and value > now
	end

	-- Dizzy stars
	if active("Dazed") or active("Stunned") then
		if not entry.Stars then
			entry.Stars = billboard(head, "💫 ⭐ 💫", Color3.fromRGB(255, 230, 120), 2.6, 120)
		end
		local label = (entry.Stars :: BillboardGui):FindFirstChildOfClass("TextLabel")
		if label then
			label.Rotation = math.sin(t * 8) * 15
		end
	elseif entry.Stars then
		entry.Stars:Destroy()
		entry.Stars = nil
	end

	-- Wanted / Marked
	local marked = active("Marked")
	local wanted = active("Wanted")
	if marked or wanted then
		if not entry.Highlight then
			local highlight = Instance.new("Highlight")
			highlight.FillTransparency = 0.75
			highlight.OutlineTransparency = 0
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Adornee = character
			highlight.Parent = fxFolder
			entry.Highlight = highlight
		end
		local color = marked and Color3.fromRGB(255, 170, 40) or Color3.fromRGB(255, 60, 60)
		local highlight = entry.Highlight :: Highlight
		highlight.FillColor = color
		highlight.OutlineColor = color:Lerp(Color3.new(1, 1, 1), (math.sin(t * 10) + 1) * 0.25)
		if not entry.Wanted then
			entry.Wanted = billboard(head, marked and "🎯 MARKED" or "🚨 WANTED", color, 4.2, 150)
		end
	else
		if entry.Highlight then
			entry.Highlight:Destroy()
			entry.Highlight = nil
		end
		if entry.Wanted then
			entry.Wanted:Destroy()
			entry.Wanted = nil
		end
	end

	-- Hot loot beacon: a light pillar everyone can see from across the map
	local hot = character:GetAttribute("HotLoot")
	if hot ~= entry.Hot then
		entry.Hot = hot
		if entry.Beacon then
			entry.Beacon:Destroy()
			if entry.BeaconA0 then
				entry.BeaconA0:Destroy()
			end
			if entry.BeaconA1 then
				entry.BeaconA1:Destroy()
			end
			entry.Beacon = nil
		end
		if type(hot) == "string" then
			local color = Theme.rarity(hot)
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 3, 0)
			a0.Parent = root
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, 160, 0)
			a1.Parent = root
			local pillar = Instance.new("Beam")
			pillar.Attachment0 = a0
			pillar.Attachment1 = a1
			pillar.Width0 = 3
			pillar.Width1 = 1
			pillar.FaceCamera = true
			pillar.LightEmission = 1
			pillar.Color = ColorSequence.new(color)
			pillar.Transparency =
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			pillar.Parent = root
			entry.Beacon = pillar
			entry.BeaconA0 = a0
			entry.BeaconA1 = a1
		end
	end
	if entry.Beacon and entry.Hot == "Secret" then
		entry.Beacon.Color = ColorSequence.new(Rarities.rainbow(t), Rarities.rainbow(t, 0.4))
	end

	-- Bounty
	local owner = Players:GetPlayerFromCharacter(character)
	local bounty = owner and owner:GetAttribute("Bounty")
	if type(bounty) == "number" then
		if not entry.Bounty then
			entry.Bounty = billboard(head, "💰 BOUNTY " .. Format.cash(bounty), C.Accent, 5.6, 200)
		end
	elseif entry.Bounty then
		entry.Bounty:Destroy()
		entry.Bounty = nil
	end

	-- Secret artifact effects
	local effects = character:GetAttribute("LootEffects")
	local key = type(effects) == "string" and effects or ""
	if key ~= entry.SecretKey then
		entry.SecretKey = key
		clearSecret(entry)
		for effect in string.gmatch(key, "[^,]+") do
			if effect == "Sunlight" then
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 220, 140)
				light.Range = 60
				light.Brightness = 5
				light.Shadows = true
				light.Parent = root
				table.insert(entry.SecretFx, light)
			elseif effect == "Code" then
				local emitter = Instance.new("ParticleEmitter")
				emitter.Texture = SPARKLES
				emitter.Color = ColorSequence.new(Color3.fromRGB(90, 255, 160))
				emitter.LightEmission = 1
				emitter.Rate = 30
				emitter.Lifetime = NumberRange.new(1, 1.6)
				emitter.Speed = NumberRange.new(2, 4)
				emitter.EmissionDirection = Enum.NormalId.Bottom
				emitter.Size = NumberSequence.new(0.4)
				emitter.Parent = head
				table.insert(entry.SecretFx, emitter)
			elseif effect == "Cookies" then
				local emitter = Instance.new("ParticleEmitter")
				emitter.Texture = SPARKLES
				emitter.Color = ColorSequence.new(Color3.fromRGB(255, 150, 190))
				emitter.Rate = 8
				emitter.Lifetime = NumberRange.new(1, 1.5)
				emitter.Speed = NumberRange.new(1, 2)
				emitter.Acceleration = Vector3.new(0, 3, 0)
				emitter.Parent = root
				table.insert(entry.SecretFx, emitter)
			elseif effect == "Vacuum" then
				local emitter = Instance.new("ParticleEmitter")
				emitter.Texture = SMOKE
				emitter.Color = ColorSequence.new(Color3.fromRGB(120, 40, 200))
				emitter.Rate = 20
				emitter.Lifetime = NumberRange.new(0.8, 1.2)
				emitter.Speed = NumberRange.new(-12, -8)
				emitter.SpreadAngle = Vector2.new(180, 180)
				emitter.Size = NumberSequence.new(1.2, 0)
				emitter.Parent = root
				table.insert(entry.SecretFx, emitter)
			elseif effect == "Glitch" then
				-- handled per-frame below
				local marker = Instance.new("BoolValue")
				marker.Name = "GlitchMarker"
				table.insert(entry.SecretFx, marker)
			end
		end
	end
	if string.find(key, "Glitch", 1, true) then
		local flicker = math.random() < 0.15
		for _, part in character:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.LocalTransparencyModifier = flicker and 0.85 or 0
			end
		end
	end
end

-- Guard speech bubbles
local function watchGuard(guard: Instance)
	guard:GetAttributeChangedSignal("BarkAt"):Connect(function()
		local head = guard:FindFirstChild("Head") :: BasePart?
		local text = guard:GetAttribute("Bark")
		if not head or type(text) ~= "string" then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(220, 56)
		gui.StudsOffset = Vector3.new(0, 3.4, 0)
		gui.LightInfluence = 0
		gui.MaxDistance = 90
		gui.Adornee = head
		local bubble = Components.panel({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.White,
			Stroke = C.Black,
			Radius = UDim.new(0, 14),
			Gradient = false,
			Parent = gui,
		})
		Components.label({
			Text = text,
			TextColor3 = C.Black,
			Size = UDim2.new(1, -12, 1, -8),
			Position = UDim2.fromOffset(6, 4),
			MaxTextSize = 22,
			Parent = bubble,
		})
		gui.Parent = fxFolder
		Components.pop(bubble, 0.5)
		Debris:AddItem(gui, 2.6)
	end)
end

function WorldFXController:Start()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientFX"
	fxFolder.Parent = workspace

	Net.unreliable("Effect").OnClientEvent:Connect(function(kind, data)
		local handler = HANDLERS[kind]
		if handler and type(data) == "table" then
			local ok, err = pcall(handler, data)
			if not ok then
				warn("[WorldFX]", kind, err)
			end
		end
	end)

	for _, guard in CollectionService:GetTagged("Guard") do
		watchGuard(guard)
	end
	CollectionService:GetInstanceAddedSignal("Guard"):Connect(watchGuard)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 / 15 then
			return
		end
		accumulator = 0
		local now = workspace:GetServerTimeNow()
		local t = os.clock()
		-- Clean up visuals for characters that despawned
		for model, entry in visuals do
			if not model.Parent then
				for _, inst in { entry.Stars, entry.Highlight, entry.Wanted, entry.Bounty } do
					if inst then
						inst:Destroy()
					end
				end
				clearSecret(entry)
				visuals[model] = nil
			end
		end
		for _, other in Players:GetPlayers() do
			local character = other.Character
			if character then
				local ok, err = pcall(updateCharacter, character, now, t)
				if not ok then
					warn("[WorldFX] status", err)
				end
			end
		end
	end)
end

return WorldFXController
