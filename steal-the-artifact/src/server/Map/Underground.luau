--[[
	Secret Underground - a glowing crystal cavern beneath the city.
	Reached through hatches in the Marketplace (sewers), Laboratory (elevator) and Temple
	(stairwell). High rarity odds, no guards, but sticky mud and crystal spikes in the dark.
	One wall in the north-west corner isn't really a wall...
]]

local Zones = require(game:GetService("ReplicatedStorage").Shared.Config.Zones)
local Kit = require(script.Parent.Kit)

local rgb = Kit.rgb

local ROCK = rgb(62, 56, 78)
local ROCK_LIGHT = rgb(86, 78, 104)
local CRYSTAL_COLORS = { rgb(120, 90, 255), rgb(60, 220, 255), rgb(255, 90, 220), rgb(90, 255, 170) }

export type Link = { Label: string, Arrival: CFrame, Exit: CFrame }

local function crystalCluster(parent: Instance, base: Vector3, color: Color3, scale: number)
	local m = Kit.model("Crystals", parent)
	local cf = CFrame.new(base)
	for i = 1, 4 do
		local h = (3 + (i * 7) % 5) * scale
		local shard = Kit.block(m, Vector3.new(1.4 * scale, h, 1.4 * scale), cf * CFrame.Angles(math.rad((i - 2.5) * 14), math.rad(i * 70), math.rad((i % 2 == 0 and 1 or -1) * 12)) * CFrame.new(0, h / 2, 0), color, Enum.Material.Neon, "Crystal")
		shard.CastShadow = false
	end
	local glow = Kit.ghost(m, Vector3.one, cf * CFrame.new(0, 3 * scale, 0))
	Kit.light(glow, color, 1.8, 22 * scale)
	return m
end

local function mushroom(parent: Instance, base: Vector3, color: Color3, scale: number)
	local m = Kit.model("Mushroom", parent)
	Kit.cyl(m, 3 * scale, 0.8 * scale, CFrame.new(base + Vector3.new(0, 1.5 * scale, 0)), rgb(230, 220, 200), Enum.Material.SmoothPlastic)
	local cap = Kit.ball(m, 3.2 * scale, CFrame.new(base + Vector3.new(0, 3.2 * scale, 0)), color, Enum.Material.Neon)
	cap.Size = Vector3.new(3.2, 3.2, 3.2) * scale
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 0.5, 1)
	mesh.Parent = cap
	Kit.light(cap, color, 1, 10 * scale)
	return m
end

return function(root: Instance, links: { Link })
	local zone = Zones.get("Underground") :: any
	local center = zone.Center
	local folder = Kit.model("Underground", root)
	local o = CFrame.new(center)
	local spawns: { CFrame } = {}
	local secretSpawns: { CFrame } = {}
	local traps = {}
	local hatches = {}
	local owner = "Zone:Underground"

	-- Shell: floor, ceiling, outer walls
	local floor = Kit.block(folder, Vector3.new(320, 4, 320), o * CFrame.new(0, -2, 0), ROCK, Enum.Material.Slate, "CaveFloor")
	floor.CastShadow = false
	Kit.block(folder, Vector3.new(320, 4, 320), o * CFrame.new(0, 34, 0), rgb(40, 36, 52), Enum.Material.Slate, "CaveCeiling")
	for _, spec in { { 0, 162, 324, 4 }, { 0, -162, 324, 4 }, { 162, 0, 4, 324 }, { -162, 0, 4, 324 } } do
		Kit.block(folder, Vector3.new(spec[3], 36, spec[4]), o * CFrame.new(spec[1], 16, spec[2]), ROCK, Enum.Material.Slate, "CaveWall")
	end

	-- Stalagmite / stalactite columns
	local rng = Random.new(1337)
	for i = 1, 14 do
		local angle = i / 14 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local radius = rng:NextNumber(55, 135)
		local pos = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		-- Leave the secret corner alone
		if not (pos.X < -90 and pos.Z > 90) then
			local width = rng:NextNumber(6, 12)
			Kit.block(folder, Vector3.new(width, 36, width), o * CFrame.new(pos.X, 16, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), ROCK_LIGHT, Enum.Material.Rock, "Column")
			Kit.block(folder, Vector3.new(width * 1.6, 6, width * 1.6), o * CFrame.new(pos.X, 2, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, 3), 0.2), ROCK, Enum.Material.Rock)
		end
	end

	-- Glowing river with bridges
	for i = -3, 3 do
		local river = Kit.block(folder, Vector3.new(44, 0.3, 14), o * CFrame.new(i * 42, 0.1, -60 + math.sin(i) * 12) * CFrame.Angles(0, math.rad(math.cos(i) * 10), 0), rgb(60, 140, 255), Enum.Material.Neon, "River")
		river.Transparency = 0.25
		river.CanCollide = false
		river.CastShadow = false
	end
	for _, x in { -80, 0, 80 } do
		Kit.block(folder, Vector3.new(10, 1, 20), o * CFrame.new(x, 0.6, -60 + math.sin(x / 42) * 12), rgb(110, 80, 50), Enum.Material.WoodPlanks, "Bridge")
	end

	-- Crystal clusters with loot spawns in front of them
	local spots = {
		{ 40, 40 }, { -40, 50 }, { 60, -20 }, { -60, -10 }, { 100, 60 }, { -100, 40 }, { 120, -100 }, { -110, -110 },
		{ 0, -110 }, { 80, -130 }, { -60, 110 }, { 130, 20 }, { 20, 120 }, { -130, -40 }, { 50, 95 }, { -20, -30 },
	}
	for i, spot in spots do
		local color = CRYSTAL_COLORS[(i - 1) % #CRYSTAL_COLORS + 1]
		crystalCluster(folder, (o * CFrame.new(spot[1], 0, spot[2])).Position, color, 1 + (i % 3) * 0.3)
		local spawnBase = o * CFrame.new(spot[1] + 6, 0, spot[2] + 4)
		local rock = Kit.block(folder, Vector3.new(4, 2, 4), spawnBase * CFrame.new(0, 1, 0) * CFrame.Angles(0, i, 0), ROCK_LIGHT, Enum.Material.Rock, "LootRock")
		rock.CastShadow = false
		table.insert(spawns, spawnBase * CFrame.new(0, 3.6, 0))
	end
	for i = 1, 12 do
		local angle = i / 12 * math.pi * 2
		mushroom(folder, (o * CFrame.new(math.cos(angle) * 90 + 12, 0, math.sin(angle) * 80)).Position, CRYSTAL_COLORS[(i % 4) + 1], 0.8 + (i % 3) * 0.3)
	end

	-- Traps: sticky mud + crystal spikes
	for _, spot in { { 30, -60 }, { -30, -75 }, { 90, 30 }, { -90, 70 } } do
		table.insert(traps, Kit.trap(folder, "Glue", (o * CFrame.new(spot[1], 0.05, spot[2])).Position, owner))
	end
	for _, spot in { { 70, -80 }, { -70, -60 }, { 110, 90 }, { -30, 80 } } do
		table.insert(traps, Kit.trap(folder, "Spike", (o * CFrame.new(spot[1], 0, spot[2])).Position, owner))
	end

	-- Arrival pads + hatches back up to the surface
	for _, link in links do
		local arrival = link.Arrival
		local pad = Kit.cyl(folder, 0.4, 10, CFrame.new(arrival.Position.X, center.Y + 0.2, arrival.Position.Z), rgb(90, 80, 130), Enum.Material.DiamondPlate, "ArrivalPad")
		pad.CastShadow = false
		local hatchCF = CFrame.new(arrival.Position.X + 9, center.Y, arrival.Position.Z)
		local part, prompt = Kit.hatch(folder, hatchCF, link.Label, link.Exit)
		table.insert(hatches, { Part = part, Prompt = prompt, Destination = link.Exit })
		local ladder = Kit.truss(folder, hatchCF * CFrame.new(0, 0, 3.5), 34, rgb(90, 85, 100))
		ladder.CanCollide = false
		Kit.noCollide(Kit.sign(folder, Vector3.new(9, 2, 0.3), hatchCF * CFrame.new(0, 6, 3), "⬆ " .. string.upper(link.Label), rgb(30, 25, 45), rgb(200, 180, 255)))
	end

	-- THE SECRET ROOM (north-west corner, walled off). One panel of the south wall is fake.
	local secretZone = Zones.get("SecretRoom") :: any
	local sc = CFrame.new(secretZone.Center.X, center.Y, secretZone.Center.Z)
	local wallH, wallY = 34, 17
	-- East wall: x = -98, from z = 98 to the cave's north wall
	Kit.block(folder, Vector3.new(4, wallH, 64), o * CFrame.new(-98, wallY, 128), ROCK_LIGHT, Enum.Material.Rock, "SecretWall")
	-- South wall: z = 96, from the cave's west wall to x = -96, with the fake panel at x -124..-116
	Kit.block(folder, Vector3.new(36, wallH, 4), o * CFrame.new(-142, wallY, 96), ROCK_LIGHT, Enum.Material.Rock, "SecretWall")
	Kit.block(folder, Vector3.new(20, wallH, 4), o * CFrame.new(-106, wallY, 96), ROCK_LIGHT, Enum.Material.Rock, "SecretWall")
	local fake = Kit.block(folder, Vector3.new(8, wallH, 4), o * CFrame.new(-120, wallY, 96), ROCK_LIGHT, Enum.Material.Rock, "SecretWall")
	fake.CanCollide = false
	fake.CanQuery = false
	fake:SetAttribute("FakeWall", true)
	-- Golden treasure room
	local gold = Kit.block(folder, Vector3.new(52, 0.3, 54), o * CFrame.new(-130, 0.15, 129), rgb(255, 205, 80), Enum.Material.Foil, "SecretFloor")
	gold.CastShadow = false
	for i = 1, 6 do
		local pile = Kit.ball(folder, 4 + (i % 3), o * CFrame.new(-150 + i * 7, -0.5, 152 - (i % 2) * 6), rgb(255, 200, 60), Enum.Material.Foil)
		pile.CastShadow = false
	end
	local secretPedestal = Kit.pedestal(folder, sc * CFrame.new(0, 0.3, 4), rgb(255, 230, 150), rgb(255, 255, 255))
	table.insert(secretSpawns, secretPedestal)
	local beacon = Kit.ghost(folder, Vector3.one, sc * CFrame.new(0, 14, 4))
	Kit.light(beacon, rgb(255, 240, 200), 3, 46)
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = rgb(255, 230, 150)
	sparkles.Parent = beacon
	local note = Kit.sign(folder, Vector3.new(14, 3.5, 0.4), o * CFrame.new(-130, 9, 158), "YOU FOUND IT.<br/>Tell no one. (Tell everyone.)", rgb(40, 30, 20), rgb(255, 220, 120))
	note.CanCollide = false

	return {
		Id = "Underground",
		Folder = folder,
		Spawns = spawns,
		SecretSpawns = secretSpawns,
		Patrol = {},
		Lasers = {},
		Cameras = {},
		Traps = traps,
		Hatches = hatches,
	}
end
