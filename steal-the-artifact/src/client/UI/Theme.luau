--[[
	Theme
	One place for colors, fonts and sizing so every window looks like the same game.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local rgb = Color3.fromRGB

local Theme = {}

Theme.Colors = {
	Backdrop = rgb(8, 8, 16),
	Background = rgb(20, 21, 34),
	Panel = rgb(30, 32, 50),
	PanelLight = rgb(42, 45, 68),
	PanelLighter = rgb(56, 60, 88),
	Stroke = rgb(84, 90, 140),
	Text = rgb(246, 246, 255),
	SubText = rgb(170, 176, 205),
	Muted = rgb(110, 115, 145),
	Accent = rgb(255, 198, 60),
	AccentDark = rgb(200, 140, 20),
	Primary = rgb(72, 144, 255),
	PrimaryDark = rgb(40, 90, 210),
	Success = rgb(70, 212, 120),
	SuccessDark = rgb(30, 150, 80),
	Danger = rgb(240, 72, 92),
	DangerDark = rgb(170, 30, 50),
	Warning = rgb(255, 170, 50),
	Gem = rgb(120, 220, 255),
	Cash = rgb(120, 235, 130),
	XP = rgb(170, 120, 255),
	Black = rgb(0, 0, 0),
	White = rgb(255, 255, 255),
}

Theme.Fonts = {
	Title = Enum.Font.LuckiestGuy,
	Heading = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
}

Theme.Corner = UDim.new(0, 14)
Theme.SmallCorner = UDim.new(0, 10)

function Theme.rarity(id: string): Color3
	return Rarities.textColor(id)
end

function Theme.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function Theme.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

return Theme
