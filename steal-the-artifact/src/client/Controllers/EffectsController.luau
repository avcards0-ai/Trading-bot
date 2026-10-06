--[[
	EffectsController
	Screen-space juice: camera shake, FOV punch, flashes, UI confetti, the rare-steal
	cinematic (sunburst + spinning 3D artifact + rarity slam) and the funny FAIL stamps.
	Everything is non-blocking: you keep control of your character the whole time, because
	the escape starts the moment you grab the loot.
]]

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
local ArtifactViewport = require(UIFolder.ArtifactViewport)

local C = Theme.Colors
local EffectsController = { Name = "EffectsController" }

local controllers: { [string]: any }
local Data
local overlay: ScreenGui
local scaledOverlay: Frame
local shakeIntensity = 0
local shakeUntil = 0
local fovOffset = 0

local FAIL_STYLE = {
	Bonk = { Icon = "💫", Color = Color3.fromRGB(255, 220, 80), Sound = "Bonk" },
	Zap = { Icon = "⚡", Color = Color3.fromRGB(110, 200, 255), Sound = "Zap" },
	Slip = { Icon = "🍌", Color = Color3.fromRGB(255, 225, 60), Sound = "Fail" },
	Spring = { Icon = "🚀", Color = Color3.fromRGB(255, 120, 120), Sound = "Spring" },
	Glue = { Icon = "🫠", Color = Color3.fromRGB(230, 230, 255), Sound = "Splash" },
	Tackle = { Icon = "🚓", Color = Color3.fromRGB(90, 140, 255), Sound = "Hurt" },
	Spike = { Icon = "📌", Color = Color3.fromRGB(200, 200, 210), Sound = "Hurt" },
	Toxic = { Icon = "☣️", Color = Color3.fromRGB(120, 255, 90), Sound = "Splash" },
}

function EffectsController:Init(all)
	controllers = all
	Data = all.DataController
end

local function setting(key: string, default: any): any
	local settings = Data:Get("Settings")
	if type(settings) == "table" and settings[key] ~= nil then
		return settings[key]
	end
	return default
end

-- Camera -----------------------------------------------------------------------------------------

function EffectsController:Shake(intensity: number, duration: number)
	if not setting("Shake", true) then
		return
	end
	shakeIntensity = math.max(shakeIntensity, intensity)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

function EffectsController:FovPunch(amount: number)
	fovOffset = amount
end

-- Screen effects ----------------------------------------------------------------------------------

function EffectsController:Flash(color: Color3, duration: number)
	if setting("ReduceFlashing", false) then
		return
	end
	local flash = Components.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = overlay,
	})
	Components.tween(flash, duration, { BackgroundTransparency = 1 })
	task.delay(duration + 0.05, function()
		flash:Destroy()
	end)
end

function EffectsController:Confetti(color: Color3?, count: number?)
	local colors = { C.Accent, C.Primary, C.Success, C.Danger, C.XP, color or C.Gem }
	for _ = 1, count or 36 do
		local piece = Components.new("Frame", {
			BackgroundColor3 = colors[math.random(1, #colors)],
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20)),
			Position = UDim2.new(0.5, math.random(-60, 60), 0.45, math.random(-30, 30)),
			Rotation = math.random(0, 360),
			ZIndex = 40,
			Parent = scaledOverlay,
		})
		local target = UDim2.new(0.5 + (math.random() - 0.5) * 1.1, 0, 1.1, 0)
		local duration = 1.2 + math.random() * 1
		TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = target,
			Rotation = piece.Rotation + math.random(-540, 540),
		}):Play()
		task.delay(duration, function()
			piece:Destroy()
		end)
	end
end

-- Floating "+$123" text in the world (local only).
function EffectsController:FloatText(position: Vector3, text: string, color: Color3, size: number?)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 60)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 250
	billboard.Parent = anchor
	local label = Components.label({
		Text = text,
		TextColor3 = color,
		Font = Theme.Fonts.Title,
		MaxTextSize = size or 36,
		Parent = billboard,
	})
	Components.textStroke(label, 2.5)
	TweenService:Create(billboard, TweenInfo.new(1.4, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, 5, 0) })
		:Play()
	task.delay(0.9, function()
		Components.tween(label, 0.5, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Components.tween(stroke, 0.5, { Transparency = 1 })
		end
	end)
	task.delay(1.5, function()
		anchor:Destroy()
	end)
end

-- Rare steal cinematic ---------------------------------------------------------------------------

function EffectsController:StealCinematic(info: { [string]: any })
	local def = Artifacts.get(info.ArtifactId or "")
	if not def then
		return
	end
	local rarity = Rarities.get(def.Rarity)
	local color = Theme.rarity(def.Rarity)
	local rainbow = rarity.Id == "Secret" or info.Mutation == "Rainbow"
	local duration = ({ Epic = 1.4, Legendary = 1.9, Mythic = 2.3, Secret = 3.2 })[rarity.Id] or 1.6

	local root = Components.new("Frame", {
		Name = "Cinematic",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Active = false,
		Parent = scaledOverlay,
	})
	-- Letterbox bars
	local top = Components.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		ZIndex = 31,
		Parent = root,
	})
	local bottom = Components.new("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 31,
		Parent = root,
	})
	Components.tween(top, 0.25, { Size = UDim2.new(1, 0, 0.09, 0) })
	Components.tween(bottom, 0.25, { Size = UDim2.new(1, 0, 0.09, 0) })

	-- Sunburst
	local burst = Components.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(700, 700),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 31,
		Parent = root,
	})
	for i = 1, 14 do
		local ray = Components.new("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 26, 0.5, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 1),
			Rotation = i * (360 / 14),
			ZIndex = 31,
			Parent = burst,
		})
		Components.new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) }),
			Rotation = 90,
			Parent = ray,
		})
	end
	local scale = Components.new("UIScale", { Scale = 0.2, Parent = burst })
	Components.tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)

	-- Spinning artifact
	local viewport = ArtifactViewport.new(def.Id, info.Mutation, {
		Size = UDim2.fromOffset(260, 260),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Spin = true,
		ZIndex = 32,
		Parent = root,
	})
	local vpScale = Components.new("UIScale", { Scale = 0.1, Parent = viewport })
	Components.tween(vpScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)

	local title = Components.label({
		Text = (info.Raid and "VAULT RAID! " or "") .. string.upper(rarity.Name) .. "!",
		Font = Theme.Fonts.Title,
		TextColor3 = color,
		Size = UDim2.fromOffset(800, 90),
		Position = UDim2.fromScale(0.5, 0.66),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 80,
		ZIndex = 33,
		Parent = root,
	})
	Components.textStroke(title, 5)
	local titleScale = Components.new("UIScale", { Scale = 3, Parent = title })
	Components.tween(titleScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	local name = Components.label({
		Text = string.format(
			"%s%s  ·  %s",
			info.Mutation and (info.Mutation .. " ") or "",
			def.Name,
			Format.cash(info.Value or def.Value)
		),
		Size = UDim2.fromOffset(700, 44),
		Position = UDim2.fromScale(0.5, 0.74),
		AnchorPoint = Vector2.new(0.5, 0.5),
		MaxTextSize = 34,
		ZIndex = 33,
		Parent = root,
	})
	Components.textStroke(name, 3)

	controllers.SoundController:Play("StealRare", { Speed = 1.1 - rarity.Index * 0.06 })
	self:Shake(0.3 + rarity.Index * 0.08, 0.5)
	self:FovPunch(8 + rarity.Index)
	if rarity.Index >= 5 then
		self:Flash(color, 0.35)
		self:Confetti(color, 30 + rarity.Index * 6)
	end

	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		burst.Rotation += dt * 25
		if rainbow then
			local t = os.clock()
			title.TextColor3 = Rarities.rainbow(t)
			for i, ray in burst:GetChildren() do
				if ray:IsA("Frame") then
					ray.BackgroundColor3 = Rarities.rainbow(t, i / 14)
				end
			end
		end
	end)
	task.delay(duration, function()
		for _, inst in root:GetDescendants() do
			if inst:IsA("TextLabel") then
				Components.tween(inst, 0.35, { TextTransparency = 1 })
			elseif inst:IsA("Frame") then
				Components.tween(inst, 0.35, { BackgroundTransparency = 1 })
			elseif inst:IsA("ViewportFrame") then
				Components.tween(inst, 0.35, { ImageTransparency = 1 })
			elseif inst:IsA("UIStroke") then
				Components.tween(inst, 0.35, { Transparency = 1 })
			end
		end
		task.wait(0.4)
		connection:Disconnect()
		root:Destroy()
	end)
end

-- Fail stamp -------------------------------------------------------------------------------------

function EffectsController:FailStamp(kind: string, caption: string, info: { [string]: any }?)
	local style = FAIL_STYLE[kind] or FAIL_STYLE.Bonk
	local frame = Components.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(640, 170),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = math.random(-12, 12),
		ZIndex = 35,
		Parent = scaledOverlay,
	})
	local stamp = Components.label({
		Text = style.Icon .. " " .. caption,
		Font = Theme.Fonts.Title,
		TextColor3 = style.Color,
		Size = UDim2.new(1, 0, 0, 100),
		MaxTextSize = 84,
		ZIndex = 36,
		Parent = frame,
	})
	Components.textStroke(stamp, 5)
	local subtitle = ""
	if info and info.By then
		subtitle = "by " .. tostring(info.By)
	end
	if info and info.Dropped and info.Dropped > 0 then
		subtitle = subtitle .. (subtitle ~= "" and "  ·  " or "") .. "you dropped your loot!"
	end
	local sub = Components.label({
		Text = subtitle,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 104),
		MaxTextSize = 30,
		ZIndex = 36,
		Parent = frame,
	})
	Components.textStroke(sub, 2.5)
	Components.pop(frame, 2.2)
	controllers.SoundController:Play(style.Sound)
	self:Shake(kind == "Spring" and 0.4 or 0.7, 0.4)
	local wobble = 0
	local connection = RunService.RenderStepped:Connect(function(dt)
		wobble += dt
		frame.Rotation = math.sin(wobble * 18) * math.max(0, 8 - wobble * 10)
	end)
	task.delay(1.7, function()
		Components.tween(stamp, 0.3, { TextTransparency = 1 })
		Components.tween(sub, 0.3, { TextTransparency = 1 })
		for _, stroke in frame:GetDescendants() do
			if stroke:IsA("UIStroke") then
				Components.tween(stroke, 0.3, { Transparency = 1 })
			end
		end
		task.wait(0.32)
		connection:Disconnect()
		frame:Destroy()
	end)
end

function EffectsController:Start()
	overlay = controllers.UIController.Overlay
	scaledOverlay = controllers.UIController.OverlayScaled

	Net.event("Cinematic").OnClientEvent:Connect(function(info)
		self:StealCinematic(info)
	end)
	Net.event("Fail").OnClientEvent:Connect(function(kind, caption, info)
		self:FailStamp(kind, caption, info)
	end)

	-- Camera shake + FOV punch, applied after the default camera update.
	local baseFov = 70
	RunService:BindToRenderStep("STA_CameraFX", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		if os.clock() < shakeUntil and shakeIntensity > 0 then
			local remaining = shakeUntil - os.clock()
			local magnitude = shakeIntensity * math.min(1, remaining * 3)
			camera.CFrame *= CFrame.Angles(
				math.rad((math.random() - 0.5) * magnitude * 2),
				math.rad((math.random() - 0.5) * magnitude * 2),
				math.rad((math.random() - 0.5) * magnitude)
			)
		else
			shakeIntensity = 0
		end
		fovOffset = fovOffset + (0 - fovOffset) * math.min(1, dt * 4)
		camera.FieldOfView = baseFov + fovOffset
	end)
end

return EffectsController
