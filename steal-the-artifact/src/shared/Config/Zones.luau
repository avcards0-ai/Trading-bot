--[[
	Zones
	Every place artifacts can spawn. The map builders place geometry around `Center`;
	gameplay services read rarity odds, guard setup and pacing from here.
]]

export type Zone = {
	Id: string,
	Name: string,
	Icon: string,
	Center: Vector3,
	Radius: number,
	Safe: boolean, -- no bonking (social hub)
	MaxActive: number, -- loose artifacts alive at once
	Respawn: { number }, -- min/max seconds before an empty spawn refills
	RarityWeights: { [string]: number },
	HoldMultiplier: number,
	Guards: number,
	GuardStyle: string?,
	AlarmMinRarity: string?, -- stealing this rarity or better trips the zone alarm
	Color: Color3,
	Blurb: string,
}

local Zones = {}

Zones.List = {
	{
		Id = "Marketplace",
		Name = "Central Marketplace",
		Icon = "🏪",
		Center = Vector3.new(0, 0, 0),
		Radius = 110,
		Safe = true,
		MaxActive = 9,
		Respawn = { 10, 18 },
		RarityWeights = { Common = 72, Uncommon = 26, Rare = 2 },
		HoldMultiplier = 1,
		Guards = 0,
		AlarmMinRarity = nil,
		Color = Color3.fromRGB(255, 196, 80),
		Blurb = "Safe zone. Sell loot to the Fence, grab quests, flex on the leaderboards.",
	},
	{
		Id = "Museum",
		Name = "Grand Artifact Museum",
		Icon = "🏛️",
		Center = Vector3.new(0, 0, -340),
		Radius = 115,
		Safe = false,
		MaxActive = 14,
		Respawn = { 14, 26 },
		RarityWeights = { Common = 10, Uncommon = 34, Rare = 36, Epic = 17, Legendary = 3 },
		HoldMultiplier = 1,
		Guards = 3,
		GuardStyle = "Security",
		AlarmMinRarity = "Rare",
		Color = Color3.fromRGB(235, 225, 205),
		Blurb = "Lasers, cameras and very serious security guards.",
	},
	{
		Id = "Laboratory",
		Name = "Abandoned Laboratory",
		Icon = "🧪",
		Center = Vector3.new(350, 0, 0),
		Radius = 105,
		Safe = false,
		MaxActive = 12,
		Respawn = { 14, 24 },
		RarityWeights = { Common = 20, Uncommon = 40, Rare = 27, Epic = 11, Legendary = 2 },
		HoldMultiplier = 1,
		Guards = 2,
		GuardStyle = "Robot",
		AlarmMinRarity = "Rare",
		Color = Color3.fromRGB(120, 255, 140),
		Blurb = "Toxic puddles, flickering lights and robots that never sleep.",
	},
	{
		Id = "Temple",
		Name = "Ancient Temple",
		Icon = "🗿",
		Center = Vector3.new(-350, 0, 0),
		Radius = 105,
		Safe = false,
		MaxActive = 11,
		Respawn = { 18, 30 },
		RarityWeights = { Uncommon = 26, Rare = 40, Epic = 24, Legendary = 8.5, Mythic = 1.5 },
		HoldMultiplier = 1.1,
		Guards = 2,
		GuardStyle = "Mummy",
		AlarmMinRarity = "Epic",
		Color = Color3.fromRGB(214, 180, 110),
		Blurb = "Spike traps, ancient curses and two extremely grumpy mummies.",
	},
	{
		Id = "Warehouse",
		Name = "Military Warehouse",
		Icon = "📦",
		Center = Vector3.new(0, 0, 350),
		Radius = 115,
		Safe = false,
		MaxActive = 13,
		Respawn = { 12, 22 },
		RarityWeights = { Common = 30, Uncommon = 40, Rare = 22, Epic = 7, Legendary = 1 },
		HoldMultiplier = 1,
		Guards = 3,
		GuardStyle = "Soldier",
		AlarmMinRarity = "Rare",
		Color = Color3.fromRGB(120, 140, 90),
		Blurb = "Crates on crates on crates. Searchlights sweep the yard.",
	},
	{
		Id = "Underground",
		Name = "Secret Underground",
		Icon = "🕳️",
		Center = Vector3.new(0, -90, 0),
		Radius = 150,
		Safe = false,
		MaxActive = 10,
		Respawn = { 20, 34 },
		RarityWeights = { Rare = 30, Epic = 41, Legendary = 22, Mythic = 6.95, Secret = 0.05 },
		HoldMultiplier = 1.15,
		Guards = 0,
		AlarmMinRarity = nil,
		Color = Color3.fromRGB(110, 90, 255),
		Blurb = "Glowing crystal caves under the city. Rumor says there's a hidden room...",
	},
	{
		Id = "Vault",
		Name = "High-Security Vault",
		Icon = "🏦",
		Center = Vector3.new(345, 0, -345),
		Radius = 75,
		Safe = false,
		MaxActive = 7,
		Respawn = { 30, 45 },
		RarityWeights = { Epic = 46, Legendary = 40, Mythic = 13.85, Secret = 0.15 },
		HoldMultiplier = 1.3,
		Guards = 4,
		GuardStyle = "Elite",
		AlarmMinRarity = "Epic",
		Color = Color3.fromRGB(80, 200, 255),
		Blurb = "The door only opens every few minutes. The best loot in the city.",
	},
	{
		-- Hidden room in the Underground. One spawn, slow refill, absurd odds.
		Id = "SecretRoom",
		Name = "???",
		Icon = "❓",
		Center = Vector3.new(-130, -90, 129),
		Radius = 28,
		Safe = false,
		MaxActive = 1,
		Respawn = { 120, 180 },
		RarityWeights = { Legendary = 62, Mythic = 37.2, Secret = 0.8 },
		HoldMultiplier = 1.2,
		Guards = 0,
		AlarmMinRarity = nil,
		Color = Color3.fromRGB(255, 255, 255),
		Blurb = "You found it. Tell no one. (Tell everyone.)",
	},
} :: { Zone }

Zones.ById = {} :: { [string]: Zone }
for _, zone in Zones.List do
	Zones.ById[zone.Id] = zone
end

-- Zone a world position is inside of (nil = the open city / plots).
function Zones.at(position: Vector3): Zone?
	local best: Zone? = nil
	local bestDistance = math.huge
	for _, zone in Zones.List do
		local offset = position - zone.Center
		local underground = zone.Center.Y < -40
		-- Underground zones only count when you're actually underground and vice versa.
		if (position.Y < -40) == underground then
			local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if flat <= zone.Radius and flat < bestDistance then
				best = zone
				bestDistance = flat
			end
		end
	end
	return best
end

function Zones.get(id: string): Zone?
	return Zones.ById[id]
end

return Zones
