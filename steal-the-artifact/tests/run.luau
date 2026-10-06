--[[
	Headless test suite. Run from the project folder:

	    lune run tests/run

	Covers: every module loads, catalog/config integrity, every artifact model builds,
	progression math, security patterns, quest generation and the full procedural map
	(every Instance property is validated by Lune's reflection database).
]]

local process = require("@lune/process")

local H = require("./harness")
local test, check = H.test, H.check

print("STEAL THE ARTIFACT - headless tests\n")

-- 1. Every module loads -------------------------------------------------------------------------
print("Modules")
for _, path in H.listFilesRecursive("src/shared") do
	test("load " .. path, function()
		H.require(path)
	end)
end
for _, folder in
	{ "src/server/Services", "src/server/Map", "src/client/Controllers", "src/client/UI", "src/client/UI/Windows" }
do
	for _, path in H.listFiles(folder) do
		test("load " .. path, function()
			local result = H.require(path)
			check(result ~= nil, "module returned nil")
		end)
	end
end
test("load src/server/RequestRouter + PromptGuard + GameEvents", function()
	H.require("src/server/RequestRouter.luau")
	H.require("src/server/PromptGuard.luau")
	H.require("src/server/GameEvents.luau")
	H.require("src/server/Private/Codes.luau")
end)

-- 2. Config integrity ----------------------------------------------------------------------------
print("\nConfig integrity")
local Artifacts = H.require("src/shared/Config/Artifacts.luau")
local Rarities = H.require("src/shared/Config/Rarities.luau")
local Zones = H.require("src/shared/Config/Zones.luau")
local Quests = H.require("src/shared/Config/Quests.luau")
local Achievements = H.require("src/shared/Config/Achievements.luau")
local Cosmetics = H.require("src/shared/Config/Cosmetics.luau")
local Upgrades = H.require("src/shared/Config/Upgrades.luau")
local Security = H.require("src/shared/Config/Security.luau")
local ArtifactModels = H.require("src/shared/ArtifactModels.luau")
local Progression = H.require("src/shared/Progression.luau")
local SecurityPatterns = H.require("src/shared/SecurityPatterns.luau")
local Format = H.require("src/shared/Util/Format.luau")

test("artifacts reference valid rarities, zones and shapes", function()
	for _, def in Artifacts.List do
		check(Rarities.ById[def.Rarity] ~= nil, def.Id .. " has unknown rarity " .. def.Rarity)
		check(ArtifactModels.Shapes[def.Shape] ~= nil, def.Id .. " has unknown shape " .. def.Shape)
		for _, zoneId in def.Zones do
			check(zoneId == "Event" or Zones.ById[zoneId] ~= nil, def.Id .. " has unknown zone " .. zoneId)
		end
		check(def.Rarity ~= "Secret" or def.Effect ~= nil, def.Id .. " is Secret but has no Effect")
	end
end)

test("every weighted rarity in every zone has artifacts to spawn", function()
	for _, zone in Zones.List do
		for rarity, weight in zone.RarityWeights do
			if weight > 0 then
				check(
					#Artifacts.pool(zone.Id, rarity) > 0,
					zone.Id .. " can roll " .. rarity .. " but has no artifacts"
				)
			end
		end
	end
end)

test("artifact values climb with rarity", function()
	local maxByRarity = {}
	local minByRarity = {}
	for _, def in Artifacts.List do
		maxByRarity[def.Rarity] = math.max(maxByRarity[def.Rarity] or 0, def.Value)
		minByRarity[def.Rarity] = math.min(minByRarity[def.Rarity] or math.huge, def.Value)
	end
	for i = 2, #Rarities.List do
		local lower, higher = Rarities.List[i - 1].Id, Rarities.List[i].Id
		check(minByRarity[higher] > maxByRarity[lower], higher .. " should always be worth more than " .. lower)
	end
end)

test("event loot pools exist for rain + meteor weights", function()
	for _, rarity in { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" } do
		check(#Artifacts.pool("Event", rarity) > 0, "no event artifacts for " .. rarity)
	end
end)

test("quests reference known events and valid filters", function()
	local known = {
		Steal = true,
		Secure = true,
		SecureValue = true,
		RaidSteal = true,
		BonkCarrier = true,
		Bonk = true,
		Sell = true,
		Defend = true,
		AlarmEscape = true,
		Fail = true,
		EarnCash = true,
		EventSteal = true,
	}
	for _, list in { Quests.Missions, Quests.Daily } do
		for _, def in list do
			check(known[def.Event], def.Id .. " uses unknown event " .. def.Event)
			check(def.MinRarity == nil or Rarities.ById[def.MinRarity], def.Id .. " bad MinRarity")
			check(def.Zone == nil or Zones.ById[def.Zone], def.Id .. " bad Zone")
			check(string.find(def.Text, "%s", 1, true) ~= nil, def.Id .. " text needs a %s for the goal")
			for level = 1, 80, 13 do
				local goal = Quests.goalFor(def, level, 0.5)
				check(goal >= 1, def.Id .. " goal < 1")
			end
		end
	end
end)

test("achievement stats exist in the save template", function()
	local source = H.source("src/server/Services/DataService.luau")
	for _, achievement in Achievements.List do
		local stat = achievement.Stat
		local derived = stat == "Level" or stat == "Rebirths" or stat == "Discovered"
		check(
			derived or string.find(source, "\t\t" .. stat .. " = 0,", 1, true) ~= nil,
			achievement.Id .. " uses stat " .. stat .. " missing from the template"
		)
	end
end)

test("cosmetics are well formed (no pay-to-win fields)", function()
	for _, item in Cosmetics.List do
		local price = item.Price
		check(price.Gems or price.Cash or price.VIP or price.Free, item.Id .. " has no price")
		check(#item.Colors >= 1, item.Id .. " has no colors")
		if item.Type == "Emote" then
			check(item.AnimR15 and item.AnimR6, item.Id .. " needs R15 + R6 animations")
		end
		for key in item :: any do
			check(
				key ~= "Speed" and key ~= "Capacity" and key ~= "CashBoost",
				item.Id .. " looks like a gameplay boost"
			)
		end
	end
end)

test("security track stat tables cover every level", function()
	for _, track in Security.Tracks do
		check(#track.Levels == track.MaxLevel, track.Id .. " needs one description per level")
		local stats = Security.Stats[track.Id]
		check(stats ~= nil, track.Id .. " has no stats")
		for name, values in stats do
			check(#values == track.MaxLevel + 1, track.Id .. "." .. name .. " needs MaxLevel + 1 entries")
		end
	end
end)

-- 3. Models -----------------------------------------------------------------------------------
print("\nArtifact models")
test("every artifact builds (plain, Shiny, Rainbow)", function()
	for _, def in Artifacts.List do
		for _, mutation in { nil, "Shiny", "Rainbow" } :: { string? } do
			local model = ArtifactModels.build(def.Id, mutation)
			check(model.PrimaryPart ~= nil, def.Id .. " has no PrimaryPart")
			local parts = 0
			for _, child in model:GetDescendants() do
				if child:IsA("BasePart") then
					parts += 1
				end
			end
			check(parts >= 3, def.Id .. " built only " .. parts .. " parts")
			check(parts <= 40, def.Id .. " is too heavy (" .. parts .. " parts)")
			check(model:GetAttribute("ArtifactId") == def.Id, def.Id .. " missing ArtifactId attribute")
		end
	end
end)

-- 4. Progression ---------------------------------------------------------------------------------
print("\nProgression")
local function sampleData(overrides: { [string]: any }?)
	local data = {
		Cash = 1000,
		Level = 10,
		XP = 0,
		Rebirths = 0,
		PrestigeTokens = 0,
		Gear = { Backpack = 2, Sneakers = 3, Gloves = 1 },
		Vault = { Display = 1, Storage = 1 },
		Security = { Door = 1, Lasers = 2, Cameras = 0, Traps = 1, Guards = 0, Alarm = 0 },
		Perks = {},
		Artifacts = {
			a = { Id = "golden_idol" },
			b = { Id = "rubber_duck", M = "Shiny" },
			c = { Id = "first_thief_crown" },
		},
		Displayed = { "a", "c" },
		Discovered = { golden_idol = 1, rubber_duck = 3 },
		Stats = { Steals = 5 },
	}
	for key, value in overrides or {} do
		data[key] = value
	end
	return data
end

test("xp curve is increasing and positive", function()
	local previous = 0
	for level = 1, 200 do
		local need = Progression.xpToNext(level)
		check(need > previous, "xpToNext must increase at level " .. level)
		previous = need
	end
end)

test("derived stats", function()
	local data = sampleData()
	check(Progression.capacity(data) == 3 + 2, "capacity")
	check(Progression.walkSpeed(data) == 18 + 3, "walk speed")
	check(Progression.holdMultiplier(data) < 1, "gloves make stealing faster")
	check(Progression.displaySlots(data) == Upgrades.BaseDisplay + 2, "display slots")
	check(Progression.artifactValue("rubber_duck", "Shiny") == 24, "shiny doubles value")
	check(Progression.artifactValue("rubber_duck", "Rainbow") == 60, "rainbow is 5x")
	check(Progression.displayValue(data) == 2000 + 750000, "display value")
	check(Progression.hasDisplayedEffect(data, "ThiefCrown"), "crown effect detected")
	check(Progression.incomePerSecond(data) > 0, "income")
	check(Progression.collectionScore(data) == 20 + 1, "collection score")
	check(Progression.netWorth(data) > data.Cash, "net worth includes vault")
	local level, cash = Progression.rebirthRequirement(0)
	check(level == 20 and cash == 25000, "first rebirth requirement")
	check(Progression.canRebirth(sampleData({ Level = 25, Cash = 30000 })), "can rebirth when qualified")
	check(not Progression.canRebirth(sampleData({ Level = 5, Cash = 1e9 })), "level gate")
end)

test("upgrade costs grow and stay finite", function()
	for _, list in { Upgrades.Gear, Upgrades.Vault, Security.Tracks } do
		for _, track in list :: { any } do
			local previous = 0
			for level = 0, track.MaxLevel - 1 do
				local cost = Progression.trackCost(track, level)
				check(cost > previous and cost < 1e12, track.Id .. " cost curve broken at " .. level)
				previous = cost
			end
		end
	end
end)

test("security patterns stay in range", function()
	for _, pattern in { "Static", "Blink", "Sweep", "Chaos" } do
		for t = 0, 30, 0.37 do
			local _, offset = SecurityPatterns.laser(pattern, 1.3, 0.5, 2.5, t)
			check(math.abs(offset) <= 2.5 + 1e-6, pattern .. " offset out of range")
		end
	end
	local cf = SecurityPatterns.cameraCFrame(H.roblox.Vector3.new(0, 10, 0), 0, 30)
	check(
		SecurityPatterns.inCone(cf, 40, 60, H.roblox.Vector3.new(0, 0, -15)),
		"camera should see a point in front/below"
	)
	check(not SecurityPatterns.inCone(cf, 40, 60, H.roblox.Vector3.new(0, 0, 15)), "camera should not see behind")
end)

test("number formatting", function()
	check(Format.abbreviate(999) == "999", Format.abbreviate(999))
	check(Format.abbreviate(1234) == "1.23K", Format.abbreviate(1234))
	check(Format.abbreviate(15300000) == "15.3M", Format.abbreviate(15300000))
	check(Format.abbreviate(1000000) == "1M", Format.abbreviate(1000000))
	check(Format.cash(2500) == "$2.5K", Format.cash(2500))
	check(Format.clock(75) == "1:15", Format.clock(75))
	check(Format.commas(1234567) == "1,234,567", Format.commas(1234567))
end)

-- 5. Procedural map --------------------------------------------------------------------------------
print("\nProcedural map")
local Instance = H.roblox.Instance
local root = Instance.new("Folder")
local zoneBuilders = { "Marketplace", "Museum", "Laboratory", "Temple", "Warehouse", "HighSecurityVault" }
local built = {}
for _, name in zoneBuilders do
	test("build " .. name, function()
		local zone = H.require("src/server/Map/" .. name .. ".luau")(root)
		check(#zone.Spawns > 0, name .. " has no artifact spawns")
		check(zone.Folder ~= nil, name .. " has no folder")
		built[zone.Id] = zone
	end)
end
test("build Underground (+ secret room)", function()
	local links = {}
	for _, zone in built do
		for _, hatch in zone.Hatches do
			table.insert(links, { Label = "Up", Arrival = hatch.Destination, Exit = hatch.Destination })
		end
	end
	check(#links >= 3, "expected hatches from Marketplace, Laboratory and Temple")
	local zone = H.require("src/server/Map/Underground.luau")(root, links)
	check(#zone.Spawns >= 10, "underground spawns")
	check(#zone.SecretSpawns == 1, "secret room spawn")
	built.Underground = zone
end)
test("zone spawn counts cover MaxActive", function()
	for id, zone in built do
		local config = Zones.ById[id]
		if config then
			check(
				#zone.Spawns >= config.MaxActive,
				string.format("%s has %d spawns but MaxActive %d", id, #zone.Spawns, config.MaxActive)
			)
		end
	end
end)
test("guarded zones have patrol routes", function()
	for _, config in Zones.List do
		if config.Guards > 0 then
			check(built[config.Id] and #built[config.Id].Patrol >= 2, config.Id .. " needs patrol points")
		end
	end
end)
local plots
test("build 12 vault plots", function()
	plots = H.require("src/server/Map/Plots.luau")(root)
	check(#plots == 12, "plot count")
	for _, plot in plots do
		check(#plot.Pedestals == 20, "20 pedestals")
		check(#plot.LaserSlots >= 6 and #plot.CameraSlots >= 4 and #plot.TrapSlots >= 10, "device slots")
		check(plot.Door.Prompt ~= nil, "door prompt")
	end
end)
test("plots don't overlap zones", function()
	for _, plot in plots do
		for _, zone in Zones.List do
			if zone.Center.Y > -40 then
				local flat = (plot.CFrame.Position - H.roblox.Vector3.new(zone.Center.X, 0, zone.Center.Z)).Magnitude
				check(
					flat > zone.Radius + 60,
					string.format("plot %d is too close to %s (%.0f)", plot.Index, zone.Id, flat)
				)
			end
		end
	end
end)
test("environment roads / border / scenery", function()
	local Environment = H.require("src/server/Map/Environment.luau")
	local cframes = {}
	for _, plot in plots do
		table.insert(cframes, plot.CFrame)
	end
	Environment.roads(root, cframes)
	Environment.border(root)
	Environment.scenery(root, cframes)
end)
test("security devices install into a plot", function()
	local Kit = H.require("src/server/Map/Kit.luau")
	local plot = plots[1]
	local laser =
		Kit.laser(plot.Devices, plot.LaserSlots[1].CFrame, 52, "Sweep", 1, 0, 1.2, H.roblox.Vector3.yAxis, "Plot:1")
	check(laser.Part:GetAttribute("Pattern") == "Sweep", "laser attributes")
	local cam =
		Kit.camera(plot.Devices, plot.CameraSlots[1].Position, plot.CameraSlots[1].Yaw, 0.7, 0.5, 40, 50, "Plot:1", 32)
	check(cam.Head:GetAttribute("Range") == nil and cam.Range == 40, "camera def")
	for _, kind in { "Banana", "Spring", "Glue", "Spike", "Toxic" } do
		local trap = Kit.trap(plot.Devices, kind, plot.TrapSlots[1], "Plot:1")
		check(trap.Kind == kind, "trap kind")
	end
end)
test("map size is reasonable", function()
	local parts = 0
	for _, child in root:GetDescendants() do
		if child:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("      (%d parts in the generated city)", parts))
	check(parts > 2000 and parts < 15000, "unexpected part count " .. parts)
end)

local failures = H.summary()
process.exit(failures > 0 and 1 or 0)
