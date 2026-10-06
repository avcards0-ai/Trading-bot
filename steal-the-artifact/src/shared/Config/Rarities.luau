--[[
	Rarities
	Common -> Uncommon -> Rare -> Epic -> Legendary -> Mythic -> Secret.
	Each tier gets more value, a longer steal, more carry weight and louder visuals.
]]

export type Rarity = {
	Id: string,
	Index: number,
	Name: string,
	Color: Color3,
	Glow: Color3,
	HoldTime: number, -- base seconds to steal
	Weight: number, -- carry weight (slows you down)
	XP: number, -- XP for securing one
	Score: number, -- collection score per unique discovered
	Hot: boolean, -- carrier gets a beacon everyone can see
	Announce: "None" | "Server" | "Global",
	Vfx: number, -- 0..6 visual intensity tier
	SetReward: number, -- Gems for discovering every artifact of this rarity
}

local list: { Rarity } = {
	{
		Id = "Common",
		Index = 1,
		Name = "Common",
		Color = Color3.fromRGB(196, 200, 210),
		Glow = Color3.fromRGB(230, 232, 240),
		HoldTime = 0.5,
		Weight = 1,
		XP = 10,
		Score = 1,
		Hot = false,
		Announce = "None",
		Vfx = 0,
		SetReward = 10,
	},
	{
		Id = "Uncommon",
		Index = 2,
		Name = "Uncommon",
		Color = Color3.fromRGB(88, 222, 112),
		Glow = Color3.fromRGB(150, 255, 160),
		HoldTime = 0.8,
		Weight = 1,
		XP = 22,
		Score = 3,
		Hot = false,
		Announce = "None",
		Vfx = 1,
		SetReward = 15,
	},
	{
		Id = "Rare",
		Index = 3,
		Name = "Rare",
		Color = Color3.fromRGB(64, 156, 255),
		Glow = Color3.fromRGB(120, 200, 255),
		HoldTime = 1.2,
		Weight = 1,
		XP = 45,
		Score = 8,
		Hot = false,
		Announce = "None",
		Vfx = 2,
		SetReward = 25,
	},
	{
		Id = "Epic",
		Index = 4,
		Name = "Epic",
		Color = Color3.fromRGB(176, 86, 255),
		Glow = Color3.fromRGB(215, 150, 255),
		HoldTime = 2.0,
		Weight = 2,
		XP = 100,
		Score = 20,
		Hot = false,
		Announce = "Server",
		Vfx = 3,
		SetReward = 40,
	},
	{
		Id = "Legendary",
		Index = 5,
		Name = "Legendary",
		Color = Color3.fromRGB(255, 190, 40),
		Glow = Color3.fromRGB(255, 225, 120),
		HoldTime = 3.0,
		Weight = 2,
		XP = 280,
		Score = 60,
		Hot = true,
		Announce = "Global",
		Vfx = 4,
		SetReward = 75,
	},
	{
		Id = "Mythic",
		Index = 6,
		Name = "Mythic",
		Color = Color3.fromRGB(255, 58, 112),
		Glow = Color3.fromRGB(255, 130, 170),
		HoldTime = 4.0,
		Weight = 3,
		XP = 900,
		Score = 200,
		Hot = true,
		Announce = "Global",
		Vfx = 5,
		SetReward = 150,
	},
	{
		Id = "Secret",
		Index = 7,
		Name = "SECRET",
		Color = Color3.fromRGB(30, 30, 40),
		Glow = Color3.fromRGB(255, 255, 255),
		HoldTime = 5.0,
		Weight = 3,
		XP = 4000,
		Score = 1000,
		Hot = true,
		Announce = "Global",
		Vfx = 6,
		SetReward = 500,
	},
}

local Rarities = {}
Rarities.List = list
Rarities.ById = {} :: { [string]: Rarity }
for _, rarity in list do
	Rarities.ById[rarity.Id] = rarity
end

function Rarities.get(id: string): Rarity
	return Rarities.ById[id] or list[1]
end

function Rarities.index(id: string): number
	local rarity = Rarities.ById[id]
	return rarity and rarity.Index or 1
end

function Rarities.atLeast(id: string, minimum: string): boolean
	return Rarities.index(id) >= Rarities.index(minimum)
end

-- Rainbow color for Secret text / effects at time t.
function Rarities.rainbow(t: number, offset: number?): Color3
	return Color3.fromHSV(((t * 0.25) + (offset or 0)) % 1, 0.75, 1)
end

-- Text color for a rarity (Secret is animated elsewhere; fall back to white here).
function Rarities.textColor(id: string): Color3
	if id == "Secret" then
		return Color3.fromRGB(255, 255, 255)
	end
	return Rarities.get(id).Color
end

return Rarities
