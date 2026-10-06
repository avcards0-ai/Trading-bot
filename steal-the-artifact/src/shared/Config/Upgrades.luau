--[[
	Upgrades
	  * Gear      - bought with Cash, resets on rebirth (the "run" upgrades)
	  * Vault     - bought with Cash, permanent (display slots, storage)
	  * Perks     - bought with Prestige Tokens earned from rebirths, permanent
	  * Rebirth   - requirements and rewards

	None of these can be bought with Robux. See Monetization.luau.
]]

export type Track = {
	Id: string,
	Name: string,
	Icon: string,
	Desc: string,
	MaxLevel: number,
	BaseCost: number,
	Growth: number,
	PerLevel: number,
	Unit: string,
}

local Upgrades = {}

Upgrades.Gear = {
	{
		Id = "Backpack",
		Name = "Bigger Backpack",
		Icon = "🎒",
		Desc = "Carry more artifacts per trip.",
		MaxLevel = 9,
		BaseCost = 150,
		Growth = 2.05,
		PerLevel = 1,
		Unit = "slot",
	},
	{
		Id = "Sneakers",
		Name = "Sneaky Sneakers",
		Icon = "👟",
		Desc = "Run faster. Escape faster. Laugh at guards.",
		MaxLevel = 10,
		BaseCost = 120,
		Growth = 1.95,
		PerLevel = 1,
		Unit = "speed",
	},
	{
		Id = "Gloves",
		Name = "Sticky Gloves",
		Icon = "🧤",
		Desc = "Steal artifacts faster (shorter hold time).",
		MaxLevel = 8,
		BaseCost = 200,
		Growth = 2.15,
		PerLevel = 0.06,
		Unit = "steal speed",
	},
} :: { Track }

Upgrades.Vault = {
	{
		Id = "Display",
		Name = "Display Pedestals",
		Icon = "🏛️",
		Desc = "Show off more artifacts. Displayed artifacts earn passive income... and can be raided.",
		MaxLevel = 8,
		BaseCost = 300,
		Growth = 2.3,
		PerLevel = 2,
		Unit = "pedestals",
	},
	{
		Id = "Storage",
		Name = "Vault Storage",
		Icon = "🗄️",
		Desc = "Room for artifacts that aren't on display. Stored artifacts are raid-proof.",
		MaxLevel = 10,
		BaseCost = 250,
		Growth = 1.9,
		PerLevel = 20,
		Unit = "storage",
	},
} :: { Track }

Upgrades.BaseDisplay = 4
Upgrades.BaseStorage = 30

export type Perk = {
	Id: string,
	Name: string,
	Icon: string,
	Desc: string,
	MaxLevel: number,
	PerLevel: number,
}

Upgrades.Perks = {
	{
		Id = "DeepPockets",
		Name = "Deep Pockets",
		Icon = "👖",
		Desc = "+1 backpack slot per level.",
		MaxLevel = 5,
		PerLevel = 1,
	},
	{
		Id = "GoldenTouch",
		Name = "Golden Touch",
		Icon = "✨",
		Desc = "+10% cash from everything per level.",
		MaxLevel = 10,
		PerLevel = 0.1,
	},
	{
		Id = "QuickHands",
		Name = "Quick Hands",
		Icon = "🤏",
		Desc = "-5% steal hold time per level.",
		MaxLevel = 5,
		PerLevel = 0.05,
	},
	{
		Id = "FastLearner",
		Name = "Fast Learner",
		Icon = "🧠",
		Desc = "+10% XP per level.",
		MaxLevel = 10,
		PerLevel = 0.1,
	},
	{
		Id = "FenceFriend",
		Name = "Fence's Friend",
		Icon = "🤝",
		Desc = "+5% sell price per level.",
		MaxLevel = 6,
		PerLevel = 0.05,
	},
	{
		Id = "SafeCracker",
		Name = "Safe Cracker",
		Icon = "🔓",
		Desc = "-8% vault door crack time per level.",
		MaxLevel = 5,
		PerLevel = 0.08,
	},
	{
		Id = "ShowRoom",
		Name = "Show Room",
		Icon = "🏺",
		Desc = "+1 display pedestal per level.",
		MaxLevel = 4,
		PerLevel = 1,
	},
	{
		Id = "ThickSkin",
		Name = "Thick Skin",
		Icon = "🛡️",
		Desc = "-10% stun time per level.",
		MaxLevel = 5,
		PerLevel = 0.1,
	},
	{
		Id = "HeadStart",
		Name = "Head Start",
		Icon = "🚀",
		Desc = "Start each rebirth with +1 level of every gear.",
		MaxLevel = 3,
		PerLevel = 1,
	},
} :: { Perk }

Upgrades.GearById = {} :: { [string]: Track }
for _, track in Upgrades.Gear do
	Upgrades.GearById[track.Id] = track
end
Upgrades.VaultById = {} :: { [string]: Track }
for _, track in Upgrades.Vault do
	Upgrades.VaultById[track.Id] = track
end
Upgrades.PerkById = {} :: { [string]: Perk }
for _, perk in Upgrades.Perks do
	Upgrades.PerkById[perk.Id] = perk
end

Upgrades.Rebirth = {
	BaseLevel = 20,
	LevelPerRebirth = 5,
	MaxLevelRequirement = 80,
	BaseCash = 25000,
	CashGrowth = 2.2,
	TokensBase = 1,
	TokensEvery = 2, -- +1 extra token every N rebirths
}

-- Prestige ranks shown on name tags and in the UI.
Upgrades.Ranks = {
	{ Rebirths = 0, Name = "Rookie Thief", Color = Color3.fromRGB(200, 200, 210) },
	{ Rebirths = 1, Name = "Pickpocket", Color = Color3.fromRGB(120, 230, 130) },
	{ Rebirths = 3, Name = "Burglar", Color = Color3.fromRGB(90, 170, 255) },
	{ Rebirths = 5, Name = "Cat Burglar", Color = Color3.fromRGB(180, 110, 255) },
	{ Rebirths = 8, Name = "Master Thief", Color = Color3.fromRGB(255, 195, 60) },
	{ Rebirths = 12, Name = "Phantom", Color = Color3.fromRGB(255, 80, 130) },
	{ Rebirths = 18, Name = "Living Legend", Color = Color3.fromRGB(255, 255, 255) },
	{ Rebirths = 25, Name = "The Uncatchable", Color = Color3.fromRGB(80, 255, 230) },
}

function Upgrades.rank(rebirths: number)
	local current = Upgrades.Ranks[1]
	for _, rank in Upgrades.Ranks do
		if rebirths >= rank.Rebirths then
			current = rank
		end
	end
	return current
end

return Upgrades
