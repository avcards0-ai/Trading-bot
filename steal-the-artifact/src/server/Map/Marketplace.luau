--[[
	Central Marketplace - the safe social hub.
	Fence (sell), Gear Shop, Drip Shop (cosmetics), Quest Board, Daily Chest, Code Machine,
	leaderboard walls, market stalls with cheap loot and the sewer hatch to the Underground.
]]

local Zones = require(game:GetService("ReplicatedStorage").Shared.Config.Zones)
local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local rgb = Kit.rgb

local STALL_COLORS = {
	{ rgb(255, 90, 90), rgb(255, 255, 255) },
	{ rgb(80, 170, 255), rgb(255, 255, 255) },
	{ rgb(255, 200, 60), rgb(255, 120, 40) },
	{ rgb(120, 220, 120), rgb(255, 255, 255) },
	{ rgb(200, 120, 255), rgb(255, 230, 255) },
	{ rgb(255, 140, 200), rgb(255, 255, 255) },
}

local function stall(parent: Instance, cf: CFrame, colors: { Color3 }, spawns: { CFrame })
	local m = Kit.model("Stall", parent)
	Kit.block(m, Vector3.new(12, 3.5, 4), cf * CFrame.new(0, 1.75, 0), C.Wood, Enum.Material.WoodPlanks, "Counter")
	Kit.block(m, Vector3.new(12.4, 0.4, 4.4), cf * CFrame.new(0, 3.7, 0), C.DarkWood, Enum.Material.Wood)
	for x = -1, 1, 2 do
		Kit.cyl(m, 10, 0.6, cf * CFrame.new(x * 5.6, 5, 2.6), C.DarkWood, Enum.Material.Wood)
		Kit.cyl(m, 10, 0.6, cf * CFrame.new(x * 5.6, 5, -1.8), C.DarkWood, Enum.Material.Wood)
	end
	-- Striped awning
	for i = 0, 5 do
		local color = colors[(i % 2) + 1]
		local awning = Kit.wedge(m, Vector3.new(2.2, 1.6, 6.5), cf * CFrame.new(-5.5 + i * 2.2, 10.6, 0.4) * CFrame.Angles(0, math.rad(180), 0), color, Enum.Material.Fabric)
		awning.CastShadow = true
	end
	table.insert(spawns, cf * CFrame.new(-3, 5.4, 0))
	table.insert(spawns, cf * CFrame.new(3, 5.4, 0))
	-- Goods for flavor
	Kit.crate(m, cf * CFrame.new(-5, 1, -3.5), 2, rgb(190, 140, 90))
	Kit.barrel(m, cf * CFrame.new(5, 1.8, -3.5), colors[1])
end

local function shopBooth(parent: Instance, cf: CFrame, title: string, color: Color3, action: string, uiName: string, blurb: string)
	local m = Kit.model(title, parent)
	Kit.block(m, Vector3.new(16, 1, 12), cf * CFrame.new(0, 0.5, 0), color:Lerp(C.Black, 0.5), Enum.Material.WoodPlanks)
	Kit.block(m, Vector3.new(16, 12, 1), cf * CFrame.new(0, 6.5, 5.5), color:Lerp(C.Black, 0.25), Enum.Material.SmoothPlastic)
	Kit.block(m, Vector3.new(1, 12, 12), cf * CFrame.new(-7.5, 6.5, 0), color:Lerp(C.Black, 0.25), Enum.Material.SmoothPlastic)
	Kit.block(m, Vector3.new(1, 12, 12), cf * CFrame.new(7.5, 6.5, 0), color:Lerp(C.Black, 0.25), Enum.Material.SmoothPlastic)
	Kit.block(m, Vector3.new(17, 1, 13), cf * CFrame.new(0, 13, 0), color, Enum.Material.SmoothPlastic)
	local counter = Kit.block(m, Vector3.new(12, 3.6, 2.4), cf * CFrame.new(0, 2.8, -3), C.Wood, Enum.Material.WoodPlanks, "Counter")
	local trim = Kit.block(m, Vector3.new(12.4, 0.3, 2.8), cf * CFrame.new(0, 4.75, -3), color, Enum.Material.Neon)
	trim.CastShadow = false
	Kit.light(trim, color, 1.2, 16)
	Kit.sign(m, Vector3.new(15, 3.6, 0.6), cf * CFrame.new(0, 15.6, -1), title, color:Lerp(C.Black, 0.6), C.White)
	local blurbSign = Kit.sign(m, Vector3.new(10, 2.2, 0.3), cf * CFrame.new(0, 9, 4.9), blurb, rgb(30, 30, 40), rgb(230, 230, 240))
	blurbSign.CanCollide = false
	Kit.uiPrompt(counter, action, title, uiName)
	return m
end

return function(root: Instance)
	local zone = Zones.get("Marketplace") :: any
	local center = zone.Center
	local folder = Kit.model("Marketplace", root, Enum.ModelStreamingMode.Default)
	local spawns: { CFrame } = {}
	local origin = CFrame.new(center)

	-- Plaza floor: concentric rings of colored tiles
	Kit.cyl(folder, 1, 200, origin * CFrame.new(0, -0.3, 0), rgb(228, 214, 184), Enum.Material.Pavement, "Plaza")
	Kit.cyl(folder, 1.04, 150, origin * CFrame.new(0, -0.28, 0), rgb(214, 196, 160), Enum.Material.Pavement)
	Kit.cyl(folder, 1.08, 70, origin * CFrame.new(0, -0.26, 0), rgb(240, 228, 200), Enum.Material.Pavement)
	for i = 1, 16 do
		local angle = i / 16 * math.pi * 2
		local stripe = Kit.block(folder, Vector3.new(2, 1.1, 40), origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, -0.25, -55), rgb(200, 150, 90), Enum.Material.Pavement)
		stripe.CastShadow = false
	end

	-- Fountain with the giant diamond statue
	local fountain = Kit.model("Fountain", folder)
	Kit.cyl(fountain, 2.4, 34, origin * CFrame.new(0, 1.2, 0), C.Marble, Enum.Material.Marble)
	local water = Kit.cyl(fountain, 0.6, 31, origin * CFrame.new(0, 2.3, 0), rgb(80, 180, 255), Enum.Material.Glass)
	water.Transparency = 0.25
	water.CanCollide = false
	Kit.cyl(fountain, 7, 6, origin * CFrame.new(0, 5, 0), C.Marble, Enum.Material.Marble)
	Kit.cyl(fountain, 1, 12, origin * CFrame.new(0, 8.6, 0), C.Marble, Enum.Material.Marble)
	local statue = Kit.block(fountain, Vector3.new(7, 7, 7), origin * CFrame.new(0, 15, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), rgb(120, 220, 255), Enum.Material.Glass, "DiamondStatue")
	statue.Transparency = 0.1
	local core = Kit.block(fountain, Vector3.new(4, 4, 4), origin * CFrame.new(0, 15, 0) * CFrame.Angles(math.rad(45), math.rad(20), math.rad(45)), rgb(170, 240, 255), Enum.Material.Neon)
	core.CastShadow = false
	Kit.light(core, rgb(150, 230, 255), 3, 40)
	statue:SetAttribute("Spin", 0.4)
	core:SetAttribute("Spin", -0.6)
	game:GetService("CollectionService"):AddTag(statue, "Spinner")
	game:GetService("CollectionService"):AddTag(core, "Spinner")

	-- Default spawn (players are moved to their vault once it's ready).
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "CitySpawn"
	spawnLocation.Size = Vector3.new(10, 1, 10)
	spawnLocation.CFrame = origin * CFrame.new(0, 0.3, 26)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.Parent = folder
	local decal = spawnLocation:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	-- Shops
	local function at(angle: number): CFrame
		-- Booth fronts (local -Z) face the fountain.
		return origin * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(0, 0, -78) * CFrame.Angles(0, math.pi, 0)
	end
	-- Roads leave the plaza at 0 (N), 90 (W), 180 (S), 270 (E) and 315 (NE); shops sit between them.
	shopBooth(folder, at(205), "THE FENCE", rgb(60, 60, 75), "Sell Loot", "Inventory", "We buy anything. No questions.")
	shopBooth(folder, at(230), "GEAR SHOP", rgb(60, 140, 255), "Upgrade Gear", "Upgrades", "Backpacks, sneakers, sticky gloves.")
	shopBooth(folder, at(255), "DRIP SHOP", rgb(220, 90, 220), "Browse Cosmetics", "Shop", "Trails, auras, emotes, vault skins.")
	shopBooth(folder, at(30), "QUEST BOARD", rgb(255, 170, 40), "View Quests", "Quests", "Missions, daily challenges, achievements.")
	shopBooth(folder, at(60), "COLLECTION", rgb(90, 200, 140), "Open Collection", "Collection", "Gotta steal 'em all.")
	shopBooth(folder, at(292), "CODE MACHINE", rgb(255, 80, 100), "Enter Codes", "Codes", "Follow the game for free codes!")

	-- Daily reward chest
	local chestCF = origin * CFrame.Angles(0, math.rad(30), 0) * CFrame.new(0, 0, 48)
	local chest = Kit.model("DailyChest", folder)
	local chestBase = Kit.block(chest, Vector3.new(6, 3.5, 4), chestCF * CFrame.new(0, 1.75, 0), rgb(150, 90, 40), Enum.Material.WoodPlanks, "Chest")
	Kit.block(chest, Vector3.new(6.2, 1.6, 4.2), chestCF * CFrame.new(0, 4.3, 0), rgb(170, 105, 50), Enum.Material.WoodPlanks)
	local lock = Kit.block(chest, Vector3.new(1, 1.2, 0.4), chestCF * CFrame.new(0, 3.5, -2.2), C.Gold, Enum.Material.Neon)
	Kit.light(lock, C.Gold, 2, 14)
	Kit.uiPrompt(chestBase, "Claim Reward", "Daily Chest", "Daily")

	-- Leaderboard walls (LeaderboardService fills the SurfaceGuis)
	local boards = {}
	local boardDefs = {
		{ Key = "Richest", Title = "💰 RICHEST THIEVES", Angle = 112 },
		{ Key = "BestVault", Title = "🏦 BEST VAULTS", Angle = 128 },
		{ Key = "MostSteals", Title = "🖐️ MOST STEALS", Angle = 144 },
		{ Key = "Collection", Title = "📖 RAREST COLLECTIONS", Angle = 160 },
	}
	for _, def in boardDefs do
		local cf = origin * CFrame.Angles(0, math.rad(def.Angle), 0) * CFrame.new(0, 13, -96) * CFrame.Angles(0, math.rad(180), 0)
		local board = Kit.block(folder, Vector3.new(15, 24, 1), cf, rgb(25, 25, 35), Enum.Material.SmoothPlastic, "Board_" .. def.Key)
		Kit.block(folder, Vector3.new(16, 25, 0.8), cf * CFrame.new(0, 0, 0.3), C.Gold, Enum.Material.Metal)
		board:SetAttribute("BoardTitle", def.Title)
		boards[def.Key] = board
	end

	-- Market stalls with low-tier loot
	for i = 1, 6 do
		local angle = math.rad(i * 60 + 30)
		stall(folder, origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -44) * CFrame.Angles(0, math.rad(180), 0), STALL_COLORS[i], spawns)
	end

	-- Lamps, benches, trees around the plaza ring
	for i = 1, 12 do
		local angle = i / 12 * math.pi * 2
		Kit.lamp(folder, center + Vector3.new(math.cos(angle) * 64, 0, math.sin(angle) * 64), rgb(255, 225, 160))
		if i % 2 == 0 then
			Kit.bench(folder, origin * CFrame.Angles(0, angle + math.pi / 12, 0) * CFrame.new(0, 0, -30))
		end
		Kit.tree(folder, center + Vector3.new(math.cos(angle + 0.25) * 102, 0, math.sin(angle + 0.25) * 102), 1.1)
	end

	-- Sewer hatch to the Underground
	local hatches = {}
	local hatchCF = origin * CFrame.new(-22, 0, -14)
	local undergroundEntry = CFrame.new(Vector3.new(0, -86, 30))
	local hatchPart, hatchPrompt = Kit.hatch(folder, hatchCF, "Enter Sewers", undergroundEntry)
	table.insert(hatches, { Part = hatchPart, Prompt = hatchPrompt, Destination = undergroundEntry })
	Kit.noCollide(Kit.sign(folder, Vector3.new(6, 2, 0.3), hatchCF * CFrame.new(0, 5, 3) * CFrame.Angles(0, math.rad(180), 0), "⬇ SEWERS ⬇", rgb(40, 35, 60), rgb(190, 170, 255)))

	-- Welcome arch facing south
	local arch = Kit.model("WelcomeArch", folder)
	for x = -1, 1, 2 do
		Kit.pillar(arch, center + Vector3.new(x * 14, 0, 104), 22, 3, C.Gold, Enum.Material.Metal)
	end
	Kit.sign(arch, Vector3.new(32, 5, 1.5), origin * CFrame.new(0, 24, 104) * CFrame.Angles(0, math.rad(180), 0), "STEAL THE ARTIFACT", rgb(40, 25, 70), C.Gold, { Font = Enum.Font.LuckiestGuy })

	return {
		Id = "Marketplace",
		Folder = folder,
		Spawns = spawns,
		Patrol = {},
		Lasers = {},
		Cameras = {},
		Traps = {},
		Hatches = hatches,
		Boards = boards,
		SpawnLocation = spawnLocation,
	}
end
