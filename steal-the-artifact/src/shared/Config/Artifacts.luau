--[[
	Artifacts
	The full catalog. `Shape` picks a procedural model in ArtifactModels, `Zones` decides
	where it can spawn ("Event" = Artifact Rain / Meteor events). Secret artifacts carry an
	`Effect` that gameplay and VFX code react to.
]]

export type Artifact = {
	Id: string,
	Name: string,
	Rarity: string,
	Value: number,
	Shape: string,
	Icon: string,
	C1: Color3,
	C2: Color3,
	Zones: { string },
	Desc: string,
	Effect: string?,
	EffectDesc: string?,
}

local rgb = Color3.fromRGB

local ALL_SURFACE = { "Marketplace", "Museum", "Laboratory", "Temple", "Warehouse", "Event" }

local list: { Artifact } = {
	-- COMMON ------------------------------------------------------------------------------
	{ Id = "rubber_duck", Name = "Rubber Duck", Rarity = "Common", Value = 12, Shape = "Duck", Icon = "🦆",
		C1 = rgb(255, 214, 40), C2 = rgb(255, 140, 30), Zones = { "Marketplace", "Laboratory", "Warehouse", "Event" },
		Desc = "Squeaks when nervous. Which is always." },
	{ Id = "dusty_coin", Name = "Dusty Coin", Rarity = "Common", Value = 9, Shape = "Coin", Icon = "🪙",
		C1 = rgb(196, 140, 70), C2 = rgb(150, 100, 50), Zones = { "Marketplace", "Temple", "Museum", "Event" },
		Desc = "Worth exactly one (1) dusty coin." },
	{ Id = "clay_pot", Name = "Clay Pot", Rarity = "Common", Value = 14, Shape = "Vase", Icon = "🏺",
		C1 = rgb(196, 110, 70), C2 = rgb(150, 80, 50), Zones = { "Temple", "Marketplace", "Museum", "Event" },
		Desc = "Handmade by someone with a lot of patience and no thumbs." },
	{ Id = "old_boot", Name = "Old Boot", Rarity = "Common", Value = 8, Shape = "Boot", Icon = "👢",
		C1 = rgb(110, 76, 50), C2 = rgb(60, 40, 30), Zones = { "Warehouse", "Marketplace", "Underground", "Event" },
		Desc = "One previous owner. One very stinky previous owner." },
	{ Id = "mystery_sandwich", Name = "Mystery Sandwich", Rarity = "Common", Value = 11, Shape = "Sandwich", Icon = "🥪",
		C1 = rgb(230, 190, 120), C2 = rgb(120, 200, 90), Zones = { "Marketplace", "Warehouse", "Event" },
		Desc = "Nobody knows how old it is. Nobody asks." },
	{ Id = "garden_gnome", Name = "Garden Gnome", Rarity = "Common", Value = 18, Shape = "Gnome", Icon = "🧙",
		C1 = rgb(220, 40, 50), C2 = rgb(60, 110, 220), Zones = { "Marketplace", "Museum", "Event" },
		Desc = "Has seen things. Will not elaborate." },
	{ Id = "brass_key", Name = "Brass Key", Rarity = "Common", Value = 15, Shape = "Key", Icon = "🔑",
		C1 = rgb(220, 180, 70), C2 = rgb(170, 130, 40), Zones = ALL_SURFACE,
		Desc = "Opens absolutely nothing. Still feels important." },
	{ Id = "toy_robot", Name = "Toy Robot", Rarity = "Common", Value = 20, Shape = "Robot", Icon = "🤖",
		C1 = rgb(170, 180, 195), C2 = rgb(255, 80, 80), Zones = { "Laboratory", "Warehouse", "Event" },
		Desc = "Batteries not included. Ambition included." },
	{ Id = "fancy_teapot", Name = "Fancy Teapot", Rarity = "Common", Value = 22, Shape = "Teapot", Icon = "🫖",
		C1 = rgb(245, 245, 250), C2 = rgb(70, 110, 220), Zones = { "Museum", "Marketplace", "Event" },
		Desc = "Short and stout. Extremely stealable." },
	{ Id = "snow_globe", Name = "Snow Globe", Rarity = "Common", Value = 19, Shape = "Globe", Icon = "🔮",
		C1 = rgb(200, 235, 255), C2 = rgb(120, 70, 40), Zones = { "Marketplace", "Museum", "Event" },
		Desc = "It's always snowing in there. Rude, honestly." },
	{ Id = "lost_sock", Name = "Lost Sock", Rarity = "Common", Value = 8, Shape = "Sock", Icon = "🧦",
		C1 = rgb(240, 90, 120), C2 = rgb(250, 250, 250), Zones = { "Marketplace", "Warehouse", "Underground", "Event" },
		Desc = "The dryer finally gave it back." },
	{ Id = "okayest_mug", Name = "World's Okayest Mug", Rarity = "Common", Value = 10, Shape = "Mug", Icon = "☕",
		C1 = rgb(250, 250, 250), C2 = rgb(90, 60, 40), Zones = { "Warehouse", "Laboratory", "Event" },
		Desc = "A participation trophy for coffee." },

	-- UNCOMMON ----------------------------------------------------------------------------
	{ Id = "silver_chalice", Name = "Silver Chalice", Rarity = "Uncommon", Value = 70, Shape = "Chalice", Icon = "🏆",
		C1 = rgb(210, 215, 225), C2 = rgb(150, 160, 175), Zones = { "Museum", "Temple", "Event" },
		Desc = "Fancy enough for royalty, small enough for your backpack." },
	{ Id = "jade_frog", Name = "Jade Frog", Rarity = "Uncommon", Value = 85, Shape = "Frog", Icon = "🐸",
		C1 = rgb(70, 190, 120), C2 = rgb(40, 130, 80), Zones = { "Temple", "Museum", "Event" },
		Desc = "Legend says it grants one wish. The wish is 'ribbit'." },
	{ Id = "pocket_watch", Name = "Pocket Watch", Rarity = "Uncommon", Value = 75, Shape = "Watch", Icon = "⌚",
		C1 = rgb(230, 190, 80), C2 = rgb(250, 250, 240), Zones = { "Museum", "Marketplace", "Event" },
		Desc = "Always running five minutes late. Like its owner." },
	{ Id = "ancient_scroll", Name = "Ancient Scroll", Rarity = "Uncommon", Value = 60, Shape = "Scroll", Icon = "📜",
		C1 = rgb(235, 215, 170), C2 = rgb(150, 90, 50), Zones = { "Temple", "Museum", "Event" },
		Desc = "Contains the ancient recipe for... toast?" },
	{ Id = "ceremonial_mask", Name = "Ceremonial Mask", Rarity = "Uncommon", Value = 95, Shape = "Mask", Icon = "🎭",
		C1 = rgb(200, 120, 60), C2 = rgb(250, 230, 90), Zones = { "Temple", "Museum", "Event" },
		Desc = "Makes you look 40% more mysterious." },
	{ Id = "bubbling_flask", Name = "Bubbling Flask", Rarity = "Uncommon", Value = 80, Shape = "Flask", Icon = "🧪",
		C1 = rgb(120, 255, 120), C2 = rgb(220, 240, 255), Zones = { "Laboratory", "Event" },
		Desc = "Do NOT drink. (Someone drank it.)" },
	{ Id = "bronze_helmet", Name = "Bronze Helmet", Rarity = "Uncommon", Value = 65, Shape = "Helmet", Icon = "⛑️",
		C1 = rgb(190, 130, 70), C2 = rgb(220, 60, 50), Zones = { "Museum", "Warehouse", "Event" },
		Desc = "Bonk protection: zero. Style: maximum." },
	{ Id = "ruby_ring", Name = "Ruby Ring", Rarity = "Uncommon", Value = 105, Shape = "Ring", Icon = "💍",
		C1 = rgb(240, 200, 90), C2 = rgb(230, 30, 60), Zones = { "Museum", "Marketplace", "Event" },
		Desc = "One ring to... sell at the Fence." },
	{ Id = "medal_of_valor", Name = "Medal of Valor", Rarity = "Uncommon", Value = 55, Shape = "Medal", Icon = "🎖️",
		C1 = rgb(240, 200, 70), C2 = rgb(60, 90, 220), Zones = { "Warehouse", "Museum", "Event" },
		Desc = "Awarded for bravery. Stolen for profit." },
	{ Id = "walkie_talkie", Name = "Walkie-Talkie", Rarity = "Uncommon", Value = 50, Shape = "Radio", Icon = "📻",
		C1 = rgb(50, 60, 50), C2 = rgb(255, 210, 60), Zones = { "Warehouse", "Event" },
		Desc = "Over. Over? ...Over." },
	{ Id = "prototype_chip", Name = "Prototype Chip", Rarity = "Uncommon", Value = 90, Shape = "Chip", Icon = "💾",
		C1 = rgb(30, 130, 70), C2 = rgb(240, 200, 60), Zones = { "Laboratory", "Warehouse", "Event" },
		Desc = "Runs Doom. Barely." },
	{ Id = "glow_shard", Name = "Glow Shard", Rarity = "Uncommon", Value = 110, Shape = "Crystal", Icon = "💎",
		C1 = rgb(90, 230, 255), C2 = rgb(200, 250, 255), Zones = { "Underground", "Laboratory" },
		Desc = "Nightlight of the underground." },

	-- RARE --------------------------------------------------------------------------------
	{ Id = "golden_goblet", Name = "Golden Goblet", Rarity = "Rare", Value = 320, Shape = "Chalice", Icon = "🏆",
		C1 = rgb(255, 200, 50), C2 = rgb(230, 40, 60), Zones = { "Museum", "Temple", "Event" },
		Desc = "Drink from it and feel 300% fancier." },
	{ Id = "emerald_scarab", Name = "Emerald Scarab", Rarity = "Rare", Value = 380, Shape = "Scarab", Icon = "🪲",
		C1 = rgb(40, 200, 110), C2 = rgb(255, 200, 60), Zones = { "Temple", "Event" },
		Desc = "Sacred beetle. Allegedly bites thieves. Allegedly." },
	{ Id = "plasma_core", Name = "Plasma Core", Rarity = "Rare", Value = 420, Shape = "Core", Icon = "⚛️",
		C1 = rgb(80, 180, 255), C2 = rgb(60, 70, 90), Zones = { "Laboratory", "Event" },
		Desc = "Warm to the touch. Hot to the economy." },
	{ Id = "samurai_kabuto", Name = "Samurai Kabuto", Rarity = "Rare", Value = 450, Shape = "Helmet", Icon = "⛑️",
		C1 = rgb(190, 30, 40), C2 = rgb(240, 200, 70), Zones = { "Museum", "Event" },
		Desc = "Honor not included." },
	{ Id = "fossil_egg", Name = "Fossil Egg", Rarity = "Rare", Value = 300, Shape = "Egg", Icon = "🥚",
		C1 = rgb(170, 160, 140), C2 = rgb(120, 110, 95), Zones = { "Museum", "Underground", "Event" },
		Desc = "Do not incubate. Seriously. We've seen the movies." },
	{ Id = "moon_rock", Name = "Moon Rock", Rarity = "Rare", Value = 280, Shape = "Rock", Icon = "🌑",
		C1 = rgb(170, 170, 180), C2 = rgb(110, 110, 120), Zones = { "Museum", "Laboratory", "Event" },
		Desc = "Smells faintly of cheese." },
	{ Id = "viking_horn", Name = "Viking War Horn", Rarity = "Rare", Value = 260, Shape = "Horn", Icon = "📯",
		C1 = rgb(240, 230, 200), C2 = rgb(150, 100, 60), Zones = { "Museum", "Warehouse", "Event" },
		Desc = "Blow it to summon... the security guards." },
	{ Id = "pharaoh_cat", Name = "Pharaoh's Cat", Rarity = "Rare", Value = 410, Shape = "Cat", Icon = "🐈",
		C1 = rgb(30, 30, 36), C2 = rgb(255, 200, 60), Zones = { "Temple", "Event" },
		Desc = "Judges you silently for all eternity." },
	{ Id = "robot_butler", Name = "Vintage Robot Butler", Rarity = "Rare", Value = 350, Shape = "Robot", Icon = "🤖",
		C1 = rgb(200, 120, 70), C2 = rgb(120, 230, 255), Zones = { "Laboratory", "Warehouse", "Event" },
		Desc = "Very polite. Very rusty. Very heavy." },
	{ Id = "the_not_lisa", Name = "The Not-Lisa", Rarity = "Rare", Value = 480, Shape = "Painting", Icon = "🖼️",
		C1 = rgb(200, 160, 60), C2 = rgb(90, 120, 70), Zones = { "Museum", "Event" },
		Desc = "Her smile follows you. Mostly to the exit." },
	{ Id = "sapphire_lens", Name = "Sapphire Lens", Rarity = "Rare", Value = 400, Shape = "Gem", Icon = "💠",
		C1 = rgb(40, 90, 255), C2 = rgb(160, 200, 255), Zones = { "Underground", "Museum" },
		Desc = "See the world in 4K blue." },
	{ Id = "gold_bar", Name = "Gold Bar", Rarity = "Rare", Value = 500, Shape = "Bar", Icon = "🧈",
		C1 = rgb(255, 205, 60), C2 = rgb(210, 160, 30), Zones = { "Warehouse", "Underground", "Event" },
		Desc = "It's not butter. We checked." },

	-- EPIC --------------------------------------------------------------------------------
	{ Id = "crystal_skull", Name = "Crystal Skull", Rarity = "Epic", Value = 2400, Shape = "Skull", Icon = "💀",
		C1 = rgb(190, 235, 255), C2 = rgb(120, 200, 255), Zones = { "Temple", "Underground", "Event" },
		Desc = "Stares into your soul. Finds nothing. Disappointed." },
	{ Id = "golden_idol", Name = "Golden Idol", Rarity = "Epic", Value = 2000, Shape = "Idol", Icon = "🗿",
		C1 = rgb(255, 200, 50), C2 = rgb(220, 60, 40), Zones = { "Temple", "Museum", "Event" },
		Desc = "Swap it with a bag of sand. That always works. Right?" },
	{ Id = "dragon_egg", Name = "Dragon Egg", Rarity = "Epic", Value = 2800, Shape = "Egg", Icon = "🥚",
		C1 = rgb(200, 40, 50), C2 = rgb(255, 160, 40), Zones = { "Underground", "Temple" },
		Desc = "Warm. Wiggly. Definitely fine." },
	{ Id = "atomic_heart", Name = "Atomic Heart", Rarity = "Epic", Value = 3000, Shape = "Heart", Icon = "💚",
		C1 = rgb(90, 255, 120), C2 = rgb(40, 60, 50), Zones = { "Laboratory", "Vault" },
		Desc = "Beats at 9,000 BPM." },
	{ Id = "phoenix_feather", Name = "Phoenix Feather", Rarity = "Epic", Value = 2200, Shape = "Feather", Icon = "🪶",
		C1 = rgb(255, 120, 30), C2 = rgb(255, 230, 80), Zones = { "Temple", "Museum", "Event" },
		Desc = "Respawns itself if you drop it in lava. Please don't test that." },
	{ Id = "time_crystal", Name = "Time Crystal", Rarity = "Epic", Value = 2600, Shape = "Crystal", Icon = "🔮",
		C1 = rgb(170, 90, 255), C2 = rgb(255, 180, 255), Zones = { "Underground", "Laboratory" },
		Desc = "Ticks backwards. Tock forwards." },
	{ Id = "royal_scepter", Name = "Royal Scepter", Rarity = "Epic", Value = 3200, Shape = "Scepter", Icon = "🪄",
		C1 = rgb(255, 205, 60), C2 = rgb(170, 40, 220), Zones = { "Museum", "Vault" },
		Desc = "Point it at people and say 'Off with their loot!'" },
	{ Id = "alien_specimen", Name = "Alien Specimen", Rarity = "Epic", Value = 2700, Shape = "Jar", Icon = "👽",
		C1 = rgb(120, 255, 90), C2 = rgb(210, 240, 255), Zones = { "Laboratory", "Warehouse" },
		Desc = "It waved at me." },
	{ Id = "holo_diamond", Name = "Holo-Diamond", Rarity = "Epic", Value = 3400, Shape = "Gem", Icon = "💠",
		C1 = rgb(70, 255, 240), C2 = rgb(255, 120, 250), Zones = { "Vault", "Laboratory" },
		Desc = "A diamond from the future. Probably a refund issue." },
	{ Id = "classified_briefcase", Name = "Classified Briefcase", Rarity = "Epic", Value = 2500, Shape = "Briefcase", Icon = "💼",
		C1 = rgb(40, 40, 46), C2 = rgb(220, 200, 120), Zones = { "Warehouse", "Vault" },
		Desc = "Contents: classified. Weight: suspicious." },
	{ Id = "pirate_compass", Name = "Pirate Compass", Rarity = "Epic", Value = 1800, Shape = "Compass", Icon = "🧭",
		C1 = rgb(180, 120, 60), C2 = rgb(240, 220, 160), Zones = { "Underground", "Museum", "Event" },
		Desc = "Points to whatever you want most. Usually snacks." },

	-- LEGENDARY ---------------------------------------------------------------------------
	{ Id = "crown_of_kings", Name = "Crown of Kings", Rarity = "Legendary", Value = 15000, Shape = "Crown", Icon = "👑",
		C1 = rgb(255, 205, 50), C2 = rgb(230, 30, 70), Zones = { "Museum", "Vault", "Event" },
		Desc = "Heavy is the head. Heavier is the backpack." },
	{ Id = "the_sunstone", Name = "The Sunstone", Rarity = "Legendary", Value = 13000, Shape = "Orb", Icon = "🟠",
		C1 = rgb(255, 150, 30), C2 = rgb(255, 240, 120), Zones = { "Temple", "Vault" },
		Desc = "Captured a sunset in 2000 BC. Still glowing." },
	{ Id = "pharaoh_mask", Name = "Mask of the Pharaoh", Rarity = "Legendary", Value = 16000, Shape = "PharaohMask", Icon = "🎭",
		C1 = rgb(255, 200, 50), C2 = rgb(30, 70, 200), Zones = { "Temple" },
		Desc = "The curse is mostly a rumor. Mostly." },
	{ Id = "mech_core", Name = "Prototype Mech Core", Rarity = "Legendary", Value = 12000, Shape = "Core", Icon = "⚙️",
		C1 = rgb(255, 60, 60), C2 = rgb(60, 60, 70), Zones = { "Laboratory", "Warehouse" },
		Desc = "Powers a giant robot. The robot would like it back." },
	{ Id = "starfall_meteorite", Name = "Starfall Meteorite", Rarity = "Legendary", Value = 14000, Shape = "Meteor", Icon = "☄️",
		C1 = rgb(80, 60, 90), C2 = rgb(255, 120, 40), Zones = { "Underground", "Vault", "Event" },
		Desc = "Fell from the sky. Landed in your pocket." },
	{ Id = "golden_throne", Name = "The Golden Throne", Rarity = "Legendary", Value = 18000, Shape = "Toilet", Icon = "🚽",
		C1 = rgb(255, 210, 60), C2 = rgb(250, 250, 250), Zones = { "Vault", "Museum" },
		Desc = "Priceless. Please do not use." },
	{ Id = "hopeful_diamond", Name = "The Hopeful Diamond", Rarity = "Legendary", Value = 20000, Shape = "BigGem", Icon = "💎",
		C1 = rgb(60, 120, 255), C2 = rgb(200, 230, 255), Zones = { "Vault", "Museum" },
		Desc = "Hopes to be stolen by you specifically." },
	{ Id = "heart_of_the_temple", Name = "Heart of the Temple", Rarity = "Legendary", Value = 15500, Shape = "Heart", Icon = "❤️",
		C1 = rgb(255, 40, 60), C2 = rgb(255, 200, 60), Zones = { "Temple", "Underground" },
		Desc = "The temple will be fine. Probably. (It will not be fine.)" },
	{ Id = "sword_in_stone", Name = "Sword in the Stone", Rarity = "Legendary", Value = 17000, Shape = "SwordStone", Icon = "🗡️",
		C1 = rgb(220, 230, 240), C2 = rgb(120, 120, 125), Zones = { "Underground", "Museum" },
		Desc = "You took the whole stone. Technically counts." },

	-- MYTHIC ------------------------------------------------------------------------------
	{ Id = "void_orb", Name = "Void Orb", Rarity = "Mythic", Value = 60000, Shape = "VoidOrb", Icon = "⚫",
		C1 = rgb(20, 10, 30), C2 = rgb(170, 60, 255), Zones = { "Underground", "Vault" },
		Desc = "Looking into it is like reading the terms of service." },
	{ Id = "celestial_compass", Name = "Celestial Compass", Rarity = "Mythic", Value = 75000, Shape = "Compass", Icon = "🧭",
		C1 = rgb(60, 70, 200), C2 = rgb(255, 230, 120), Zones = { "Vault", "Underground" },
		Desc = "Points to the next Mythic. It's pointing at itself." },
	{ Id = "eye_of_the_storm", Name = "Eye of the Storm", Rarity = "Mythic", Value = 85000, Shape = "StormOrb", Icon = "🌩️",
		C1 = rgb(90, 150, 255), C2 = rgb(240, 250, 255), Zones = { "Vault", "Temple" },
		Desc = "Crackles with stolen lightning. Hair-raising." },
	{ Id = "chrono_hourglass", Name = "Chrono Hourglass", Rarity = "Mythic", Value = 70000, Shape = "Hourglass", Icon = "⏳",
		C1 = rgb(255, 200, 60), C2 = rgb(120, 230, 255), Zones = { "Vault", "Laboratory" },
		Desc = "Flip it to get five more minutes in bed." },
	{ Id = "dragons_heart", Name = "Dragon's Heart", Rarity = "Mythic", Value = 95000, Shape = "Heart", Icon = "🐉",
		C1 = rgb(255, 30, 40), C2 = rgb(255, 140, 20), Zones = { "Underground", "Temple" },
		Desc = "Still beating. Still angry." },
	{ Id = "galaxy_shard", Name = "Galaxy Shard", Rarity = "Mythic", Value = 110000, Shape = "Crystal", Icon = "🌌",
		C1 = rgb(120, 40, 220), C2 = rgb(40, 200, 255), Zones = { "Vault", "Underground", "Event" },
		Desc = "There are tiny stars inside. Tiny people too, maybe." },
	{ Id = "kraken_pearl", Name = "Kraken Pearl", Rarity = "Mythic", Value = 65000, Shape = "Pearl", Icon = "🦪",
		C1 = rgb(240, 230, 255), C2 = rgb(60, 50, 120), Zones = { "Underground", "Temple" },
		Desc = "The Kraken wants it back. The Kraken has a lot of arms." },

	-- SECRET ------------------------------------------------------------------------------
	{ Id = "rubber_chicken", Name = "Rubber Chicken of Destiny", Rarity = "Secret", Value = 300000, Shape = "Chicken", Icon = "🐔",
		C1 = rgb(255, 225, 60), C2 = rgb(255, 120, 30), Zones = { "Underground", "Vault", "SecretRoom", "Event" },
		Desc = "Foretold by prophecy. Squeaks the prophecy, too.",
		Effect = "Honk", EffectDesc = "Honks loudly while carried. Everyone knows where you are. Worth it." },
	{ Id = "banana_of_doom", Name = "The Banana of Doom", Rarity = "Secret", Value = 350000, Shape = "Banana", Icon = "🍌",
		C1 = rgb(255, 225, 50), C2 = rgb(90, 60, 30), Zones = { "Underground", "Vault", "SecretRoom", "Event" },
		Desc = "Cursed. Potassium-rich. Mostly cursed.",
		Effect = "BananaTrail", EffectDesc = "Drops slippery peels behind you while carried. Chasers beware." },
	{ Id = "pocket_sun", Name = "Pocket Sun", Rarity = "Secret", Value = 500000, Shape = "Sun", Icon = "☀️",
		C1 = rgb(255, 220, 60), C2 = rgb(255, 120, 20), Zones = { "Underground", "Vault", "SecretRoom", "Event" },
		Desc = "Contains one (1) sun. Keep away from sunscreen.",
		Effect = "Sunlight", EffectDesc = "Lights up everything around you, even during a Blackout." },
	{ Id = "err_404", Name = "ERR_404_ARTIFACT", Rarity = "Secret", Value = 404404, Shape = "GlitchCube", Icon = "⬛",
		C1 = rgb(255, 0, 200), C2 = rgb(0, 255, 230), Zones = { "Underground", "Vault", "SecretRoom" },
		Desc = "This artifact could not be found. And yet, here it is.",
		Effect = "Glitch", EffectDesc = "Your character glitches in and out of reality while you carry it." },
	{ Id = "first_thief_crown", Name = "Crown of the First Thief", Rarity = "Secret", Value = 750000, Shape = "ThiefCrown", Icon = "👑",
		C1 = rgb(25, 25, 30), C2 = rgb(255, 200, 40), Zones = { "Vault", "SecretRoom" },
		Desc = "Stolen from the first thief. By the second thief.",
		Effect = "ThiefCrown", EffectDesc = "While displayed, your whole vault earns +25% income." },
	{ Id = "void_egg", Name = "The Void Egg", Rarity = "Secret", Value = 600000, Shape = "VoidEgg", Icon = "🥚",
		C1 = rgb(10, 5, 20), C2 = rgb(200, 80, 255), Zones = { "Underground", "SecretRoom" },
		Desc = "Something inside is hungry for artifacts.",
		Effect = "Vacuum", EffectDesc = "Pulls nearby dropped artifacts straight into your backpack." },
	{ Id = "grandmas_cookie_jar", Name = "Grandma's Cookie Jar", Rarity = "Secret", Value = 280000, Shape = "CookieJar", Icon = "🍪",
		C1 = rgb(200, 230, 255), C2 = rgb(170, 110, 60), Zones = { "Underground", "Vault", "SecretRoom", "Event" },
		Desc = "Grandma knows. Grandma always knows.",
		Effect = "Cookies", EffectDesc = "Heals you over time while carried. Grandma's love is powerful." },
	{ Id = "devs_keyboard", Name = "The Dev's Keyboard", Rarity = "Secret", Value = 1000000, Shape = "Keyboard", Icon = "⌨️",
		C1 = rgb(40, 40, 50), C2 = rgb(90, 255, 160), Zones = { "SecretRoom", "Vault" },
		Desc = "Ctrl+Z doesn't work on stealing. We tried.",
		Effect = "Code", EffectDesc = "Raining code follows you everywhere. You are the hacker now." },
}

local Artifacts = {}
Artifacts.List = list
Artifacts.ById = {} :: { [string]: Artifact }
Artifacts.ByRarity = {} :: { [string]: { Artifact } }
Artifacts.ByZoneRarity = {} :: { [string]: { [string]: { Artifact } } }

for _, artifact in list do
	assert(Artifacts.ById[artifact.Id] == nil, "Duplicate artifact id " .. artifact.Id)
	Artifacts.ById[artifact.Id] = artifact
	Artifacts.ByRarity[artifact.Rarity] = Artifacts.ByRarity[artifact.Rarity] or {}
	table.insert(Artifacts.ByRarity[artifact.Rarity], artifact)
	for _, zoneId in artifact.Zones do
		local byRarity = Artifacts.ByZoneRarity[zoneId] or {}
		Artifacts.ByZoneRarity[zoneId] = byRarity
		byRarity[artifact.Rarity] = byRarity[artifact.Rarity] or {}
		table.insert(byRarity[artifact.Rarity], artifact)
	end
end

function Artifacts.get(id: string): Artifact?
	return Artifacts.ById[id]
end

-- Candidates for a zone + rarity, falling back to every artifact of that rarity.
function Artifacts.pool(zoneId: string, rarity: string): { Artifact }
	local byRarity = Artifacts.ByZoneRarity[zoneId]
	local pool = byRarity and byRarity[rarity]
	if pool and #pool > 0 then
		return pool
	end
	return Artifacts.ByRarity[rarity] or {}
end

return Artifacts
