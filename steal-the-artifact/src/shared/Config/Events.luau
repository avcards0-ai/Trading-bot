--[[
	Events
	Server-wide events that shake up the loop every few minutes.
]]

export type EventDef = {
	Id: string,
	Name: string,
	Icon: string,
	Desc: string,
	Duration: number,
	Weight: number,
	Color: Color3,
}

local rgb = Color3.fromRGB

local list: { EventDef } = {
	{
		Id = "ArtifactRain",
		Name = "ARTIFACT RAIN",
		Icon = "🌧️",
		Desc = "Artifacts are falling from the sky around the Marketplace!",
		Duration = 75,
		Weight = 3,
		Color = rgb(90, 200, 255),
	},
	{
		Id = "GoldenHour",
		Name = "GOLDEN HOUR",
		Icon = "🌅",
		Desc = "Securing loot pays DOUBLE cash!",
		Duration = 120,
		Weight = 3,
		Color = rgb(255, 200, 60),
	},
	{
		Id = "Blackout",
		Name = "BLACKOUT",
		Icon = "🔦",
		Desc = "City power is out! Zone cameras and lasers are offline.",
		Duration = 90,
		Weight = 2,
		Color = rgb(120, 120, 160),
	},
	{
		Id = "Meteor",
		Name = "METEOR STRIKE",
		Icon = "☄️",
		Desc = "A meteor is about to hit the city. Something rare is inside!",
		Duration = 90,
		Weight = 2,
		Color = rgb(255, 110, 40),
	},
	{
		Id = "GuardStrike",
		Name = "GUARD STRIKE",
		Icon = "🪧",
		Desc = "The guards are on strike! Zones are unguarded.",
		Duration = 90,
		Weight = 2,
		Color = rgb(255, 120, 120),
	},
	{
		Id = "LowGravity",
		Name = "LOW GRAVITY",
		Icon = "🌙",
		Desc = "The gravity machine broke. Jump to the moon!",
		Duration = 75,
		Weight = 2,
		Color = rgb(180, 140, 255),
	},
	{
		Id = "BlackMarket",
		Name = "BLACK MARKET",
		Icon = "🕶️",
		Desc = "The Fence pays 1.5x for everything!",
		Duration = 120,
		Weight = 2,
		Color = rgb(60, 220, 140),
	},
	{
		Id = "VaultBreach",
		Name = "VAULT BREACH",
		Icon = "🏦",
		Desc = "The High-Security Vault door is jammed OPEN!",
		Duration = 75,
		Weight = 1,
		Color = rgb(80, 200, 255),
	},
}

local Events = {}
Events.List = list
Events.ById = {} :: { [string]: EventDef }
for _, event in list do
	Events.ById[event.Id] = event
end

Events.Multipliers = {
	GoldenHourSecure = 2,
	BlackMarketSell = 1.5,
	LowGravity = 70,
}

return Events
