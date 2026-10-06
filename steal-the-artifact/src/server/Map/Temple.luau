--[[
	Ancient Temple - west of the Marketplace.
	A stepped pyramid ringed by a real (terrain) water moat. Climb to the shrine on top or
	sneak into the hidden chamber at its base: spike traps, golden energy beams, mummies,
	and a stairwell down to the Underground.
]]

local Zones = require(game:GetService("ReplicatedStorage").Shared.Config.Zones)
local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local rgb = Kit.rgb

local SAND = rgb(214, 182, 120)
local SAND_DARK = rgb(180, 150, 95)
local STONE = rgb(160, 150, 130)

return function(root: Instance)
	local zone = Zones.get("Temple") :: any
	local center = zone.Center
	local folder = Kit.model("Temple", root)
	-- Local +Z faces the Marketplace (world +X).
	local o = CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0)
	local spawns: { CFrame } = {}
	local patrol: { Vector3 } = {}
	local lasers = {}
	local traps = {}
	local hatches = {}
	local owner = "Zone:Temple"
	local terrain = workspace.Terrain

	-- Moat (terrain water) with two stone bridges
	local moat = {
		{ CFrame = o * CFrame.new(0, -4, 61), Size = Vector3.new(132, 8, 10) },
		{ CFrame = o * CFrame.new(0, -4, -61), Size = Vector3.new(132, 8, 10) },
		{ CFrame = o * CFrame.new(-61, -4, 0), Size = Vector3.new(10, 8, 112) },
		{ CFrame = o * CFrame.new(61, -4, 0), Size = Vector3.new(10, 8, 112) },
	}
	for _, segment in moat do
		terrain:FillBlock(segment.CFrame, segment.Size, Enum.Material.Water)
	end
	Kit.block(folder, Vector3.new(16, 1.2, 14), o * CFrame.new(0, 0.2, 61), STONE, Enum.Material.Slate, "Bridge")
	Kit.block(folder, Vector3.new(14, 1.2, 16), o * CFrame.new(-61, 0.2, 0), STONE, Enum.Material.Slate, "Bridge")

	-- Courtyard floor
	local court = Kit.block(
		folder,
		Vector3.new(112, 1, 112),
		o * CFrame.new(0, -0.3, 0),
		SAND_DARK,
		Enum.Material.Sandstone,
		"Courtyard"
	)
	court.CastShadow = false

	-- Tier 1 is hollow (the chamber); tiers 2-4 are solid.
	local t1 = o * CFrame.new(0, 0.2, 0)
	local wall = 16
	local inner = 96 - wall * 2
	Kit.block(
		folder,
		Vector3.new(96, 10, wall),
		t1 * CFrame.new(0, 5, 48 - wall / 2),
		SAND,
		Enum.Material.Sandstone,
		"TierWall"
	)
	Kit.block(
		folder,
		Vector3.new(96, 10, wall),
		t1 * CFrame.new(0, 5, -48 + wall / 2),
		SAND,
		Enum.Material.Sandstone,
		"TierWall"
	)
	Kit.block(
		folder,
		Vector3.new(wall, 10, inner),
		t1 * CFrame.new(48 - wall / 2, 5, 0),
		SAND,
		Enum.Material.Sandstone,
		"TierWall"
	)
	-- West wall has the chamber entrance corridor (10 wide, 8 tall)
	local sideLen = (inner - 10) / 2
	Kit.block(
		folder,
		Vector3.new(wall, 10, sideLen),
		t1 * CFrame.new(-48 + wall / 2, 5, 5 + sideLen / 2),
		SAND,
		Enum.Material.Sandstone,
		"TierWall"
	)
	Kit.block(
		folder,
		Vector3.new(wall, 10, sideLen),
		t1 * CFrame.new(-48 + wall / 2, 5, -5 - sideLen / 2),
		SAND,
		Enum.Material.Sandstone,
		"TierWall"
	)
	Kit.block(
		folder,
		Vector3.new(wall, 2, 10),
		t1 * CFrame.new(-48 + wall / 2, 9, 0),
		SAND,
		Enum.Material.Sandstone,
		"Lintel"
	)
	Kit.block(
		folder,
		Vector3.new(96, 1.5, 96),
		t1 * CFrame.new(0, 10.75, 0),
		SAND,
		Enum.Material.Sandstone,
		"ChamberCeiling"
	)
	Kit.block(
		folder,
		Vector3.new(76, 10, 76),
		t1 * CFrame.new(0, 16.5, 0),
		SAND:Lerp(SAND_DARK, 0.2),
		Enum.Material.Sandstone,
		"Tier2"
	)
	Kit.block(folder, Vector3.new(56, 10, 56), t1 * CFrame.new(0, 26.5, 0), SAND, Enum.Material.Sandstone, "Tier3")
	Kit.block(
		folder,
		Vector3.new(36, 10, 36),
		t1 * CFrame.new(0, 36.5, 0),
		SAND:Lerp(SAND_DARK, 0.2),
		Enum.Material.Sandstone,
		"Tier4"
	)
	local topY = 41.5

	-- Front staircases (one per tier)
	local tiers =
		{ { Edge = 48, Base = 0 }, { Edge = 38, Base = 11.5 }, { Edge = 28, Base = 21.5 }, { Edge = 18, Base = 31.5 } }
	for i, tier in tiers do
		local rise = (i == 1) and 11.5 or 10
		local steps = (i == 1) and 12 or 10
		Kit.stairs(
			folder,
			t1 * CFrame.new(0, tier.Base - 0.2, tier.Edge + 10),
			steps,
			14,
			rise / steps,
			10 / steps,
			STONE,
			Enum.Material.Slate
		)
	end

	-- Shrine on top
	local shrine = t1 * CFrame.new(0, topY, 0)
	for _, corner in { { -8, -8 }, { 8, -8 }, { -8, 8 }, { 8, 8 } } do
		Kit.pillar(folder, (shrine * CFrame.new(corner[1], 0, corner[2])).Position, 12, 2.2, STONE, Enum.Material.Slate)
	end
	Kit.block(
		folder,
		Vector3.new(22, 1.5, 22),
		shrine * CFrame.new(0, 12.75, 0),
		SAND_DARK,
		Enum.Material.Sandstone,
		"ShrineRoof"
	)
	Kit.wedge(
		folder,
		Vector3.new(22, 5, 11),
		shrine * CFrame.new(0, 16, 5.5) * CFrame.Angles(0, math.pi, 0),
		SAND,
		Enum.Material.Sandstone
	)
	Kit.wedge(folder, Vector3.new(22, 5, 11), shrine * CFrame.new(0, 16, -5.5), SAND, Enum.Material.Sandstone)
	table.insert(spawns, (Kit.pedestal(folder, shrine, STONE, C.Gold)))
	table.insert(spawns, (Kit.pedestal(folder, shrine * CFrame.new(-12, 0, -12), STONE, rgb(80, 220, 160))))
	table.insert(spawns, (Kit.pedestal(folder, shrine * CFrame.new(12, 0, -12), STONE, rgb(80, 220, 160))))
	local eye = Kit.ball(folder, 3, shrine * CFrame.new(0, 10.5, 0), rgb(80, 255, 170), Enum.Material.Neon)
	eye.CanCollide = false
	Kit.light(eye, rgb(80, 255, 170), 3, 40)

	-- Chamber interior
	local chamber = t1
	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			Kit.pillar(folder, (chamber * CFrame.new(x * 12, 0, z * 12)).Position, 10, 2.6, STONE, Enum.Material.Slate)
			local torch = Kit.block(
				folder,
				Vector3.new(0.6, 1.6, 0.6),
				chamber * CFrame.new(x * 12 + x * 1.6, 6, z * 12),
				rgb(90, 60, 40),
				Enum.Material.Wood,
				"Torch"
			)
			torch.CanCollide = false
			local fire = Instance.new("Fire")
			fire.Size = 3
			fire.Heat = 4
			fire.Parent = torch
			Kit.light(torch, rgb(255, 160, 60), 2, 18)
		end
	end
	-- Sarcophagus centerpiece guarded by golden beams
	Kit.block(folder, Vector3.new(5, 3, 9), chamber * CFrame.new(0, 1.5, 0), C.Gold, Enum.Material.Foil, "Sarcophagus")
	Kit.block(
		folder,
		Vector3.new(4.6, 1, 8.4),
		chamber * CFrame.new(0, 3.5, 0),
		rgb(40, 90, 200),
		Enum.Material.SmoothPlastic
	)
	table.insert(spawns, chamber * CFrame.new(0, 6.2, 0))
	for i, z in { -7, 7 } do
		table.insert(
			lasers,
			Kit.laser(
				folder,
				chamber * CFrame.new(0, 2.2, z),
				20,
				"Blink",
				0.9,
				i * 2,
				0,
				Vector3.yAxis,
				owner,
				rgb(255, 200, 40)
			)
		)
	end
	for _, spot in { { -22, -22 }, { 22, -22 }, { 22, 22 }, { -22, 22 }, { 0, -24 } } do
		table.insert(
			spawns,
			(Kit.pedestal(folder, chamber * CFrame.new(spot[1], 0, spot[2]), STONE, rgb(255, 180, 60)))
		)
	end
	-- Hieroglyph wall panels
	for i = -1, 1 do
		local panel = Kit.block(
			folder,
			Vector3.new(12, 6, 0.3),
			chamber * CFrame.new(i * 18, 5, inner / 2 - 0.2),
			rgb(200, 170, 110),
			Enum.Material.Sandstone,
			"Glyphs"
		)
		Kit.label(panel, "𓂀 𓃠 𓆣 𓋹 𓁹", { Face = Enum.NormalId.Front, TextColor = rgb(120, 70, 30) })
	end
	-- Spike traps: entrance corridor + chamber floor
	for _, spot in { { -38, 0 }, { -30, 3 }, { -10, -10 }, { 10, 10 }, { -10, 18 }, { 18, -6 } } do
		table.insert(traps, Kit.trap(folder, "Spike", (chamber * CFrame.new(spot[1], 0, spot[2])).Position, owner))
	end
	-- Stairwell to the Underground
	local hatchCF = chamber * CFrame.new(27, 0, 8)
	local destination = CFrame.new(Vector3.new(-110, -86, 0))
	local hatchPart, hatchPrompt = Kit.hatch(folder, hatchCF, "Descend the Stairs", destination)
	table.insert(hatches, { Part = hatchPart, Prompt = hatchPrompt, Destination = destination })

	-- Ruins, statues and jungle outside the moat
	local ruins = { { -80, 40 }, { -85, -40 }, { 80, -60 }, { 75, 70 } }
	for i, spot in ruins do
		local cf = o * CFrame.new(spot[1], 0, spot[2])
		Kit.pillar(folder, (cf * CFrame.new(-4, 0, 0)).Position, 9 + i, 2.6, STONE, Enum.Material.Slate)
		local broken = Kit.block(
			folder,
			Vector3.new(2.6, 6, 2.6),
			cf * CFrame.new(5, 1.2, 2) * CFrame.Angles(math.rad(80), math.rad(i * 30), 0),
			STONE,
			Enum.Material.Slate
		)
		broken.CastShadow = true
		table.insert(spawns, (Kit.pedestal(folder, cf * CFrame.new(0, 0, -5), STONE, rgb(255, 180, 60))))
	end
	for _, spot in { { -30, 78 }, { 30, 78 } } do
		local cf = o * CFrame.new(spot[1], 0, spot[2]) * CFrame.Angles(0, math.pi, 0)
		local statue = Kit.model("StoneHead", folder)
		Kit.block(statue, Vector3.new(7, 2, 7), cf * CFrame.new(0, 1, 0), STONE, Enum.Material.Slate)
		Kit.block(statue, Vector3.new(6, 12, 5), cf * CFrame.new(0, 8, 0), STONE, Enum.Material.Slate)
		Kit.block(
			statue,
			Vector3.new(6.4, 2.2, 6),
			cf * CFrame.new(0, 12, -0.4),
			STONE:Lerp(C.Black, 0.2),
			Enum.Material.Slate
		)
		Kit.block(
			statue,
			Vector3.new(1.4, 4, 1.6),
			cf * CFrame.new(0, 8.5, -3),
			STONE:Lerp(C.Black, 0.1),
			Enum.Material.Slate
		)
		Kit.block(
			statue,
			Vector3.new(1.4, 0.8, 0.3),
			cf * CFrame.new(-1.5, 10.5, -2.6),
			rgb(80, 255, 170),
			Enum.Material.Neon
		)
		Kit.block(
			statue,
			Vector3.new(1.4, 0.8, 0.3),
			cf * CFrame.new(1.5, 10.5, -2.6),
			rgb(80, 255, 170),
			Enum.Material.Neon
		)
	end
	for i = 1, 22 do
		local angle = i / 22 * math.pi * 2
		local radius = 84 + (i % 3) * 8
		local pos = (o * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)).Position
		-- Keep the front approach (toward the Marketplace) clear.
		local localPos = o:PointToObjectSpace(pos)
		if not (localPos.Z > 50 and math.abs(localPos.X) < 22) then
			Kit.palm(folder, pos, 1 + (i % 3) * 0.15)
		end
	end

	-- Mummy patrol: chamber + courtyard
	for _, p in { { -20, 0 }, { 0, -20 }, { 20, 0 }, { 0, 20 }, { -52, 30 }, { -52, -30 }, { 52, -30 }, { 52, 30 } } do
		table.insert(patrol, (o * CFrame.new(p[1], 3, p[2])).Position)
	end

	return {
		Id = "Temple",
		Folder = folder,
		Spawns = spawns,
		Patrol = patrol,
		Lasers = lasers,
		Cameras = {},
		Traps = traps,
		Hatches = hatches,
	}
end
