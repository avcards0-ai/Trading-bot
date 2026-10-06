--[[
	Cosmetics
	Purely visual items. Nothing here changes stats, speed, capacity, income or security.

	Price kinds:
	  { Gems = n }     - premium currency (bought with Robux OR earned from achievements,
	                     daily rewards and challenges)
	  { Cash = n }     - earned in-game
	  { VIP = true }   - included with the VIP game pass
	  { Free = true }  - everyone owns it
]]

export type Cosmetic = {
	Id: string,
	Type: "Trail" | "Aura" | "VaultSkin" | "Emote",
	Name: string,
	Desc: string,
	Price: { Gems: number?, Cash: number?, VIP: boolean?, Free: boolean? },
	Colors: { Color3 },
	Texture: string?,
	Material: Enum.Material?,
	AccentMaterial: Enum.Material?,
	AnimR15: string?,
	AnimR6: string?,
	Looped: boolean?,
	Icon: string,
}

local rgb = Color3.fromRGB

local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local list: { Cosmetic } = {
	-- TRAILS ------------------------------------------------------------------------------
	{
		Id = "trail_speed",
		Type = "Trail",
		Name = "Speed Lines",
		Desc = "Clean white streaks. Classic getaway.",
		Price = { Cash = 2500 },
		Colors = { rgb(255, 255, 255), rgb(190, 220, 255) },
		Icon = "💨",
	},
	{
		Id = "trail_fire",
		Type = "Trail",
		Name = "Hot Pursuit",
		Desc = "Leave a blazing streak behind you.",
		Price = { Gems = 90 },
		Colors = { rgb(255, 230, 80), rgb(255, 90, 20), rgb(200, 20, 20) },
		Icon = "🔥",
	},
	{
		Id = "trail_ice",
		Type = "Trail",
		Name = "Cold Feet",
		Desc = "Frosty, like your heists.",
		Price = { Gems = 90 },
		Colors = { rgb(255, 255, 255), rgb(120, 220, 255), rgb(60, 120, 255) },
		Icon = "❄️",
	},
	{
		Id = "trail_toxic",
		Type = "Trail",
		Name = "Toxic Getaway",
		Desc = "Straight out of the lab.",
		Price = { Cash = 25000 },
		Colors = { rgb(200, 255, 80), rgb(60, 220, 90) },
		Icon = "☣️",
	},
	{
		Id = "trail_rainbow",
		Type = "Trail",
		Name = "Rainbow Dash",
		Desc = "Every color. Every escape.",
		Price = { Gems = 120 },
		Colors = { rgb(255, 60, 60), rgb(255, 200, 40), rgb(80, 230, 90), rgb(60, 160, 255), rgb(190, 80, 255) },
		Icon = "🌈",
	},
	{
		Id = "trail_galaxy",
		Type = "Trail",
		Name = "Galaxy Brain",
		Desc = "A trail of tiny universes.",
		Price = { Gems = 180 },
		Colors = { rgb(40, 20, 90), rgb(150, 60, 255), rgb(60, 200, 255) },
		Icon = "🌌",
	},
	{
		Id = "trail_shadow",
		Type = "Trail",
		Name = "Shadow Step",
		Desc = "Were you even here?",
		Price = { Gems = 150 },
		Colors = { rgb(20, 10, 30), rgb(120, 40, 180) },
		Icon = "🌑",
	},
	{
		Id = "trail_money",
		Type = "Trail",
		Name = "Money Talks",
		Desc = "For thieves who made it.",
		Price = { Cash = 250000 },
		Colors = { rgb(120, 255, 120), rgb(255, 215, 60) },
		Icon = "💵",
	},
	{
		Id = "trail_vip",
		Type = "Trail",
		Name = "VIP Gold",
		Desc = "Exclusive to VIP thieves.",
		Price = { VIP = true },
		Colors = { rgb(255, 240, 160), rgb(255, 190, 40) },
		Icon = "⭐",
	},

	-- AURAS -------------------------------------------------------------------------------
	{
		Id = "aura_sparkle",
		Type = "Aura",
		Name = "Sparkle Aura",
		Desc = "A little bit of glitter never hurt.",
		Price = { Cash = 10000 },
		Colors = { rgb(255, 255, 255) },
		Texture = SPARKLES,
		Icon = "✨",
	},
	{
		Id = "aura_hearts",
		Type = "Aura",
		Name = "Lovebug",
		Desc = "Steal hearts. And artifacts.",
		Price = { Gems = 100 },
		Colors = { rgb(255, 120, 180) },
		Texture = SPARKLES,
		Icon = "💖",
	},
	{
		Id = "aura_flame",
		Type = "Aura",
		Name = "Flame Aura",
		Desc = "Literally on fire.",
		Price = { Gems = 150 },
		Colors = { rgb(255, 160, 40) },
		Texture = FIRE,
		Icon = "🔥",
	},
	{
		Id = "aura_frost",
		Type = "Aura",
		Name = "Frost Aura",
		Desc = "Chill vibes only.",
		Price = { Gems = 150 },
		Colors = { rgb(160, 230, 255) },
		Texture = SMOKE,
		Icon = "🧊",
	},
	{
		Id = "aura_shadow",
		Type = "Aura",
		Name = "Shadow Aura",
		Desc = "Dark smoke that follows you around.",
		Price = { Gems = 200 },
		Colors = { rgb(40, 20, 60) },
		Texture = SMOKE,
		Icon = "👤",
	},
	{
		Id = "aura_lightning",
		Type = "Aura",
		Name = "Static Charge",
		Desc = "Crackling energy. Please don't touch the lasers.",
		Price = { Gems = 220 },
		Colors = { rgb(120, 200, 255) },
		Texture = SPARKLES,
		Icon = "⚡",
	},
	{
		Id = "aura_bubbles",
		Type = "Aura",
		Name = "Bubbles",
		Desc = "Blub blub.",
		Price = { Cash = 60000 },
		Colors = { rgb(170, 230, 255) },
		Texture = SPARKLES,
		Icon = "🫧",
	},
	{
		Id = "aura_gold",
		Type = "Aura",
		Name = "Golden Glow",
		Desc = "Exclusive to VIP thieves.",
		Price = { VIP = true },
		Colors = { rgb(255, 210, 80) },
		Texture = SPARKLES,
		Icon = "🌟",
	},

	-- VAULT SKINS -------------------------------------------------------------------------
	{
		Id = "skin_default",
		Type = "VaultSkin",
		Name = "Classic Concrete",
		Desc = "Sturdy. Gray. Reliable.",
		Price = { Free = true },
		Colors = { rgb(150, 155, 165), rgb(90, 95, 110), rgb(255, 200, 60) },
		Material = Enum.Material.Concrete,
		AccentMaterial = Enum.Material.Neon,
		Icon = "🧱",
	},
	{
		Id = "skin_stone",
		Type = "VaultSkin",
		Name = "Ancient Ruins",
		Desc = "Your vault, but make it archaeological.",
		Price = { Cash = 50000 },
		Colors = { rgb(196, 170, 120), rgb(130, 110, 80), rgb(80, 220, 160) },
		Material = Enum.Material.Sandstone,
		AccentMaterial = Enum.Material.Neon,
		Icon = "🗿",
	},
	{
		Id = "skin_candy",
		Type = "VaultSkin",
		Name = "Candy Land",
		Desc = "Sweet on the outside. Lasers on the inside.",
		Price = { Gems = 150 },
		Colors = { rgb(255, 170, 210), rgb(140, 220, 255), rgb(255, 255, 140) },
		Material = Enum.Material.SmoothPlastic,
		AccentMaterial = Enum.Material.Neon,
		Icon = "🍭",
	},
	{
		Id = "skin_neon",
		Type = "VaultSkin",
		Name = "Neon Cyber",
		Desc = "Hack the planet.",
		Price = { Gems = 200 },
		Colors = { rgb(25, 25, 40), rgb(15, 15, 25), rgb(0, 255, 220) },
		Material = Enum.Material.Metal,
		AccentMaterial = Enum.Material.Neon,
		Icon = "🌐",
	},
	{
		Id = "skin_ice",
		Type = "VaultSkin",
		Name = "Ice Palace",
		Desc = "Frozen assets.",
		Price = { Gems = 200 },
		Colors = { rgb(200, 235, 255), rgb(140, 200, 240), rgb(255, 255, 255) },
		Material = Enum.Material.Ice,
		AccentMaterial = Enum.Material.Neon,
		Icon = "🏔️",
	},
	{
		Id = "skin_gold",
		Type = "VaultSkin",
		Name = "Gold Rush",
		Desc = "Solid gold walls. Subtle.",
		Price = { Gems = 250 },
		Colors = { rgb(255, 205, 70), rgb(200, 150, 40), rgb(255, 255, 255) },
		Material = Enum.Material.Foil,
		AccentMaterial = Enum.Material.Neon,
		Icon = "🪙",
	},
	{
		Id = "skin_lava",
		Type = "VaultSkin",
		Name = "Volcano Lair",
		Desc = "Every villain needs one.",
		Price = { Gems = 300 },
		Colors = { rgb(50, 40, 40), rgb(30, 25, 25), rgb(255, 90, 20) },
		Material = Enum.Material.Basalt,
		AccentMaterial = Enum.Material.Neon,
		Icon = "🌋",
	},
	{
		Id = "skin_galaxy",
		Type = "VaultSkin",
		Name = "Galaxy Vault",
		Desc = "Your loot, among the stars.",
		Price = { Gems = 400 },
		Colors = { rgb(40, 25, 80), rgb(20, 15, 50), rgb(180, 120, 255) },
		Material = Enum.Material.Glass,
		AccentMaterial = Enum.Material.Neon,
		Icon = "🪐",
	},
	{
		Id = "skin_vip",
		Type = "VaultSkin",
		Name = "VIP Penthouse",
		Desc = "Exclusive to VIP thieves.",
		Price = { VIP = true },
		Colors = { rgb(30, 30, 35), rgb(255, 205, 70), rgb(255, 235, 150) },
		Material = Enum.Material.Marble,
		AccentMaterial = Enum.Material.Neon,
		Icon = "🏙️",
	},

	-- EMOTES ------------------------------------------------------------------------------
	{
		Id = "emote_wave",
		Type = "Emote",
		Name = "Wave",
		Desc = "Hi! (I'm stealing your stuff.)",
		Price = { Free = true },
		Colors = { rgb(255, 255, 255) },
		AnimR15 = "rbxassetid://507770239",
		AnimR6 = "rbxassetid://128777973",
		Icon = "👋",
	},
	{
		Id = "emote_point",
		Type = "Emote",
		Name = "Point",
		Desc = "Point at your next victim.",
		Price = { Free = true },
		Colors = { rgb(255, 255, 255) },
		AnimR15 = "rbxassetid://507770453",
		AnimR6 = "rbxassetid://128853357",
		Icon = "👉",
	},
	{
		Id = "emote_cheer",
		Type = "Emote",
		Name = "Cheer",
		Desc = "Celebrate a clean escape.",
		Price = { Cash = 5000 },
		Colors = { rgb(255, 255, 255) },
		AnimR15 = "rbxassetid://507770677",
		AnimR6 = "rbxassetid://129423030",
		Icon = "🙌",
	},
	{
		Id = "emote_laugh",
		Type = "Emote",
		Name = "Laugh",
		Desc = "For when they slip on your banana.",
		Price = { Gems = 40 },
		Colors = { rgb(255, 255, 255) },
		AnimR15 = "rbxassetid://507770818",
		AnimR6 = "rbxassetid://129423131",
		Icon = "😂",
	},
	{
		Id = "emote_dance",
		Type = "Emote",
		Name = "Victory Dance",
		Desc = "Dance on their empty pedestals.",
		Price = { Gems = 60 },
		Colors = { rgb(255, 255, 255) },
		AnimR15 = "rbxassetid://507771019",
		AnimR6 = "rbxassetid://182435998",
		Looped = true,
		Icon = "💃",
	},
	{
		Id = "emote_groove",
		Type = "Emote",
		Name = "Groove",
		Desc = "Smooth moves for smooth criminals.",
		Price = { Gems = 60 },
		Colors = { rgb(255, 255, 255) },
		AnimR15 = "rbxassetid://507776043",
		AnimR6 = "rbxassetid://182491037",
		Looped = true,
		Icon = "🕺",
	},
	{
		Id = "emote_boogie",
		Type = "Emote",
		Name = "Boogie",
		Desc = "Full-body flex.",
		Price = { Gems = 80 },
		Colors = { rgb(255, 255, 255) },
		AnimR15 = "rbxassetid://507777268",
		AnimR6 = "rbxassetid://182491065",
		Looped = true,
		Icon = "🪩",
	},
}

local Cosmetics = {}
Cosmetics.List = list
Cosmetics.ById = {} :: { [string]: Cosmetic }
Cosmetics.ByType = {} :: { [string]: { Cosmetic } }
for _, item in list do
	Cosmetics.ById[item.Id] = item
	Cosmetics.ByType[item.Type] = Cosmetics.ByType[item.Type] or {}
	table.insert(Cosmetics.ByType[item.Type], item)
end

Cosmetics.Slots = { "Trail", "Aura", "VaultSkin", "Title" }
Cosmetics.DefaultEmoteSlots = 4
Cosmetics.LockerEmoteSlots = 8
Cosmetics.DefaultLoadouts = 2
Cosmetics.LockerLoadouts = 8

function Cosmetics.colorSequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for i, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

return Cosmetics
