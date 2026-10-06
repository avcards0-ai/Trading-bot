--[[
	Loading screen (ReplicatedFirst)
	Replaces the default Roblox loading screen with a branded one that cycles tips until
	the main client signals it has built the UI (or a timeout passes).
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local TIPS = {
	"FIND -> STEAL -> ESCAPE -> SECURE -> UPGRADE -> RAID -> REPEAT",
	"Bonk players carrying loot to knock it out of their hands!",
	"Loot only counts once you carry it back to YOUR vault.",
	"Displayed artifacts earn cash every second... and can be raided.",
	"Stored artifacts are raid-proof. Displayed ones are bragging rights.",
	"The High-Security Vault door opens every few minutes. Be ready.",
	"Legendary carriers glow for the whole server. Run!",
	"Banana peels are a valid security strategy.",
	"Rumor has it there's a hidden room in the Underground...",
	"Shiny artifacts are worth 2x. Rainbow ones are worth 5x!",
}

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(14, 14, 24)
background.BorderSizePixel = 0
background.Parent = gui

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 22, 70)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(14, 14, 28)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 40, 10)),
})
gradient.Rotation = 35
gradient.Parent = background

local icon = Instance.new("TextLabel")
icon.BackgroundTransparency = 1
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.32)
icon.Size = UDim2.fromScale(0.2, 0.2)
icon.Font = Enum.Font.FredokaOne
icon.Text = "💎"
icon.TextScaled = true
icon.Parent = background

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromScale(0.8, 0.13)
title.Font = Enum.Font.LuckiestGuy
title.Text = "STEAL THE ARTIFACT"
title.TextScaled = true
title.TextColor3 = Color3.new(1, 1, 1)
title.Parent = background

local titleGradient = Instance.new("UIGradient")
titleGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 90)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 150, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 90)),
})
titleGradient.Parent = title

local stroke = Instance.new("UIStroke")
stroke.Thickness = 4
stroke.Color = Color3.fromRGB(40, 20, 0)
stroke.Parent = title

local tip = Instance.new("TextLabel")
tip.BackgroundTransparency = 1
tip.AnchorPoint = Vector2.new(0.5, 0.5)
tip.Position = UDim2.fromScale(0.5, 0.66)
tip.Size = UDim2.fromScale(0.8, 0.05)
tip.Font = Enum.Font.FredokaOne
tip.TextScaled = true
tip.TextColor3 = Color3.fromRGB(220, 220, 235)
tip.Text = TIPS[math.random(1, #TIPS)]
tip.Parent = background

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.new(0.5, 0, 1, -30)
status.Size = UDim2.fromScale(0.5, 0.035)
status.Font = Enum.Font.GothamMedium
status.TextScaled = true
status.TextColor3 = Color3.fromRGB(150, 150, 175)
status.Text = "Casing the joint..."
status.Parent = background

gui.Parent = playerGui

local start = os.clock()
local connection = RunService.RenderStepped:Connect(function()
	local t = os.clock() - start
	icon.Rotation = math.sin(t * 2) * 12
	icon.Size = UDim2.fromScale(0.2 + math.sin(t * 3) * 0.01, 0.2 + math.sin(t * 3) * 0.01)
	titleGradient.Offset = Vector2.new(math.sin(t * 1.5) * 0.4, 0)
end)

local lines = { "Casing the joint...", "Disabling cameras...", "Peeling bananas...", "Bribing the guards...", "Polishing artifacts..." }
task.spawn(function()
	local i = 1
	while gui.Parent do
		task.wait(1.6)
		i = i % #lines + 1
		status.Text = lines[i]
		tip.Text = TIPS[math.random(1, #TIPS)]
	end
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- Wait for the main client to finish building its UI (it sets this attribute).
local deadline = os.clock() + 15
while not player:GetAttribute("ClientReady") and os.clock() < deadline do
	task.wait(0.1)
end

status.Text = "Go steal something!"
task.wait(0.4)

local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad)
TweenService:Create(background, fade, { BackgroundTransparency = 1 }):Play()
for _, label in { icon, title, tip, status } do
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
end
TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
task.wait(0.65)
connection:Disconnect()
gui:Destroy()
