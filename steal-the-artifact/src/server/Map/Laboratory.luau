--[[
	Abandoned Laboratory - east of the Marketplace.
	A fenced compound with a half-wrecked lab, specimen tubes, a laser-locked containment
	room, toxic puddles, flickering lights, robot guards and an elevator to the Underground.
]]

local CollectionService = game:GetService("CollectionService")
local Zones = require(game:GetService("ReplicatedStorage").Shared.Config.Zones)
local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)

local C = Kit.Colors
local rgb = Kit.rgb

return function(root: Instance)
	local zone = Zones.get("Laboratory") :: any
	local center = zone.Center
	local folder = Kit.model("Laboratory", root)
	-- Local +Z faces the Marketplace (world -X).
	local o = CFrame.new(center) * CFrame.Angles(0, math.rad(-90), 0)
	local spawns: { CFrame } = {}
	local patrol: { Vector3 } = {}
	local lasers = {}
	local cameras = {}
	local traps = {}
	local hatches = {}
	local owner = "Zone:Laboratory"

	-- Yard ground
	local yard = Kit.block(
		folder,
		Vector3.new(180, 1, 160),
		o * CFrame.new(0, -0.3, -5),
		rgb(120, 120, 115),
		Enum.Material.Asphalt,
		"Yard"
	)
	yard.CastShadow = false

	-- Perimeter wall with a front gate
	local wallColor = rgb(150, 150, 145)
	local function fence(cf: CFrame, length: number)
		Kit.block(
			folder,
			Vector3.new(length, 5, 1.2),
			cf * CFrame.new(0, 2.5, 0),
			wallColor,
			Enum.Material.Concrete,
			"Fence"
		)
		local wire = Kit.cyl(
			folder,
			length,
			0.5,
			cf * CFrame.new(0, 5.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
			rgb(90, 90, 95),
			Enum.Material.Metal
		)
		wire.CanCollide = false
	end
	fence(o * CFrame.new(-52, 0, 75), 76)
	fence(o * CFrame.new(52, 0, 75), 76)
	fence(o * CFrame.new(0, 0, -85), 180)
	fence(o * CFrame.new(-90, 0, -5) * CFrame.Angles(0, math.rad(90), 0), 160)
	fence(o * CFrame.new(90, 0, -5) * CFrame.Angles(0, math.rad(90), 0), 160)
	-- Gate posts + hazard sign
	for side = -1, 1, 2 do
		Kit.block(
			folder,
			Vector3.new(3, 10, 3),
			o * CFrame.new(side * 14, 5, 75),
			rgb(230, 200, 40),
			Enum.Material.Metal
		)
	end
	Kit.sign(
		folder,
		Vector3.new(30, 4, 0.6),
		o * CFrame.new(0, 11, 75) * CFrame.Angles(0, math.pi, 0),
		"☣️ ABANDONED LABORATORY ☣️",
		rgb(30, 30, 30),
		C.Toxic,
		{ Font = Enum.Font.LuckiestGuy }
	)

	-- Main building
	local bCenter = o * CFrame.new(0, 0, -25)
	local floor = Kit.block(
		folder,
		Vector3.new(90, 1, 60),
		bCenter * CFrame.new(0, 0, 0),
		rgb(200, 205, 210),
		Enum.Material.SmoothPlastic,
		"LabFloor"
	)
	floor.CastShadow = false
	Kit.room(
		folder,
		bCenter * CFrame.new(0, 0.5, 0),
		Vector3.new(90, 22, 60),
		2,
		rgb(215, 220, 225),
		Enum.Material.Concrete,
		{ Back = 14, Left = 12, Right = 10 },
		12
	)
	-- Partial roof (part of it collapsed - you can see the sky through the hole)
	Kit.block(
		folder,
		Vector3.new(90, 1.2, 36),
		bCenter * CFrame.new(0, 23, 12),
		rgb(160, 165, 170),
		Enum.Material.Concrete,
		"Roof"
	)
	Kit.block(
		folder,
		Vector3.new(50, 1.2, 24),
		bCenter * CFrame.new(20, 23, -18),
		rgb(160, 165, 170),
		Enum.Material.Concrete,
		"Roof"
	)
	for i = 1, 5 do
		local rubble = Kit.block(
			folder,
			Vector3.new(4 + i, 2 + i % 3, 3 + i % 2),
			bCenter
				* CFrame.new(-25 + i * 2, 1.5, -20 + i * 1.5)
				* CFrame.Angles(math.rad(i * 17), math.rad(i * 31), math.rad(i * 11)),
			rgb(140, 140, 140),
			Enum.Material.Concrete,
			"Rubble"
		)
		rubble.CastShadow = true
	end
	local labSign = Kit.sign(
		folder,
		Vector3.new(24, 3, 0.4),
		bCenter * CFrame.new(0, 16, 30.3) * CFrame.Angles(0, math.pi, 0),
		"DR. KLEPTO'S RESEARCH LAB",
		rgb(20, 30, 30),
		rgb(150, 255, 200)
	)
	labSign.CanCollide = false

	-- Exterior: window band, teal trim, rooftop tanks, smoking stacks and pipes
	local glassColor = rgb(60, 90, 100)
	local teal = rgb(60, 170, 160)
	for _, spec in
		{
			{ Vector3.new(86, 3.2, 0.3), CFrame.new(0, 18.5, 31.1) },
			{ Vector3.new(86, 3.2, 0.3), CFrame.new(0, 18.5, -31.1) },
			{ Vector3.new(0.3, 3.2, 56), CFrame.new(-46.1, 18.5, 0) },
			{ Vector3.new(0.3, 3.2, 56), CFrame.new(46.1, 18.5, 0) },
		}
	do
		Kit.detail(Kit.block(folder, spec[1], bCenter * spec[2], glassColor, Enum.Material.Glass))
		local stripe = spec[1] + Vector3.new(spec[1].X > 1 and 4 or 0.1, -2.4, spec[1].Z > 1 and 4 or 0.1)
		Kit.detail(
			Kit.block(folder, stripe, bCenter * spec[2] * CFrame.new(0, 3, 0), teal, Enum.Material.SmoothPlastic)
		)
		Kit.detail(
			Kit.block(
				folder,
				stripe,
				bCenter * spec[2] * CFrame.new(0, -15.6, 0),
				rgb(90, 96, 104),
				Enum.Material.Concrete
			)
		)
	end
	for i, x in { -30, -19 } do
		local tank = bCenter * CFrame.new(x, 23.6, 20)
		Kit.cyl(folder, 8, 7, tank * CFrame.new(0, 4, 0), rgb(226, 230, 232), Enum.Material.Metal, "Tank")
		Kit.ball(folder, 7, tank * CFrame.new(0, 8, 0), rgb(226, 230, 232), Enum.Material.Metal)
		local band = Kit.cyl(folder, 0.8, 7.2, tank * CFrame.new(0, 2.5 + i, 0), C.Toxic, Enum.Material.Neon)
		Kit.detail(band)
	end
	for i, x in { 28, 34, 40 } do
		local stack = bCenter * CFrame.new(x, 23.6, 24)
		Kit.cyl(
			folder,
			12 + i * 2,
			2.4,
			stack * CFrame.new(0, (12 + i * 2) / 2, 0),
			rgb(150, 150, 155),
			Enum.Material.CorrodedMetal,
			"Stack"
		)
		local cap = Kit.cyl(folder, 0.6, 2.8, stack * CFrame.new(0, 12 + i * 2, 0), C.Toxic, Enum.Material.Neon)
		Kit.detail(cap)
		local smoke = Instance.new("Smoke")
		smoke.Color = rgb(150, 255, 150)
		smoke.Opacity = 0.12
		smoke.RiseVelocity = 5
		smoke.Size = 3
		smoke.Parent = cap
	end
	for z = 0, 1 do
		Kit.detail(
			Kit.cyl(
				folder,
				60,
				1.2,
				bCenter * CFrame.new(5, 25, 26 - z * 3) * CFrame.Angles(0, 0, math.rad(90)),
				z == 0 and rgb(200, 120, 40) or rgb(110, 150, 170),
				Enum.Material.Metal
			)
		)
	end

	-- Tank farm in the side yard
	for i, z in { -46, -66 } do
		local base = o * CFrame.new(-74, 0, z)
		Kit.cyl(folder, 1, 16, base * CFrame.new(0, 0.5, 0), rgb(150, 150, 150), Enum.Material.Concrete)
		Kit.cyl(folder, 18, 13, base * CFrame.new(0, 10, 0), rgb(232, 234, 236), Enum.Material.Metal, "ChemTank")
		Kit.ball(folder, 13, base * CFrame.new(0, 19, 0), rgb(232, 234, 236), Enum.Material.Metal)
		Kit.detail(
			Kit.cyl(
				folder,
				2,
				13.3,
				base * CFrame.new(0, 12, 0),
				i == 1 and C.Toxic or rgb(90, 180, 255),
				Enum.Material.Neon
			)
		)
		Kit.truss(folder, base * CFrame.new(6.8, 1, 0), 18, rgb(230, 200, 40))
		local warn = Kit.block(
			folder,
			Vector3.new(5, 5, 0.2),
			base * CFrame.new(0, 7, 6.6),
			rgb(250, 210, 40),
			Enum.Material.SmoothPlastic
		)
		Kit.detail(warn)
		Kit.label(warn, "☣", { TextColor = rgb(20, 20, 20), Face = Enum.NormalId.Back })
	end
	-- Hazard barriers by the gate
	for side = -1, 1, 2 do
		for i = 0, 1 do
			local cf = o * CFrame.new(side * (22 + i * 8), 0, 64)
			Kit.block(
				folder,
				Vector3.new(6, 2.6, 1.4),
				cf * CFrame.new(0, 1.3, 0),
				rgb(250, 200, 40),
				Enum.Material.Plastic,
				"Barrier"
			)
			for stripe = -1, 1 do
				Kit.detail(
					Kit.block(
						folder,
						Vector3.new(0.8, 2.7, 1.5),
						cf * CFrame.new(stripe * 1.8, 1.3, 0) * CFrame.Angles(0, 0, math.rad(30)),
						rgb(30, 30, 34),
						Enum.Material.Plastic
					)
				)
			end
		end
	end

	-- Lab tables with loot
	local tableSpots = { { -30, -8 }, { -15, -8 }, { 15, -8 }, { 30, -8 }, { -15, -24 }, { 15, -24 } }
	for i, spot in tableSpots do
		local cf = bCenter * CFrame.new(spot[1], 0.5, spot[2] + 25)
		Kit.block(
			folder,
			Vector3.new(9, 0.6, 4.5),
			cf * CFrame.new(0, 3.4, 0),
			rgb(235, 240, 245),
			Enum.Material.SmoothPlastic,
			"LabTable"
		)
		for lx = -1, 1, 2 do
			Kit.block(
				folder,
				Vector3.new(0.5, 3.1, 4),
				cf * CFrame.new(lx * 4, 1.55, 0),
				rgb(120, 125, 135),
				Enum.Material.Metal
			)
		end
		-- Beakers
		local beaker = Kit.cyl(folder, 1.4, 0.9, cf * CFrame.new(3, 4.4, 1), rgb(200, 255, 220), Enum.Material.Glass)
		beaker.CanCollide = false
		local liquid = Kit.cyl(
			folder,
			0.8,
			0.7,
			cf * CFrame.new(3, 4.1, 1),
			(i % 2 == 0) and C.Toxic or rgb(90, 180, 255),
			Enum.Material.Neon
		)
		liquid.CanCollide = false
		table.insert(spawns, cf * CFrame.new(-1.5, 5.5, 0))
	end

	-- Specimen tubes (west wall) + pedestals
	for i = 0, 3 do
		local cf = bCenter * CFrame.new(-40, 0.5, ({ 20, 11, -11, -20 })[i + 1])
		Kit.cyl(folder, 1, 5, cf * CFrame.new(0, 0.5, 0), rgb(80, 85, 95), Enum.Material.Metal)
		local glass = Kit.cyl(folder, 12, 4.4, cf * CFrame.new(0, 7, 0), rgb(200, 255, 230), Enum.Material.Glass)
		glass.Transparency = 0.6
		local fluid = Kit.cyl(
			folder,
			10,
			4,
			cf * CFrame.new(0, 6.5, 0),
			C.Toxic:Lerp(rgb(80, 200, 255), i / 3),
			Enum.Material.Neon
		)
		fluid.Transparency = 0.55
		fluid.CanCollide = false
		Kit.cyl(folder, 1, 5, cf * CFrame.new(0, 13.5, 0), rgb(80, 85, 95), Enum.Material.Metal)
		local specimen =
			Kit.ball(folder, 2.2, cf * CFrame.new(0, 7, 0), rgb(255, 160, 200), Enum.Material.SmoothPlastic)
		specimen.CanCollide = false
		Kit.light(fluid, C.Toxic, 1.2, 14)
		table.insert(spawns, (Kit.pedestal(folder, cf * CFrame.new(6, 0, 0), rgb(200, 205, 210), C.Toxic)))
	end

	-- Computer banks (east wall)
	for i = 0, 3 do
		local cf = bCenter * CFrame.new(41, 0.5, ({ 22, 13, -13, -22 })[i + 1])
		Kit.block(
			folder,
			Vector3.new(4, 7, 8),
			cf * CFrame.new(0, 3.5, 0),
			rgb(60, 65, 75),
			Enum.Material.Metal,
			"Computer"
		)
		local screen = Kit.block(
			folder,
			Vector3.new(0.3, 3, 6),
			cf * CFrame.new(-2.1, 5, 0),
			rgb(60, 255, 140),
			Enum.Material.Neon,
			"Screen"
		)
		screen.CastShadow = false
		CollectionService:AddTag(screen, "Flicker")
	end

	-- Containment room (back) with a laser-locked doorway
	local cc = bCenter * CFrame.new(0, 0.5, -21.5)
	Kit.block(
		folder,
		Vector3.new(15, 22, 1.5),
		cc * CFrame.new(-12.5, 11, 4.5),
		rgb(80, 85, 95),
		Enum.Material.DiamondPlate,
		"ContainmentWall"
	)
	Kit.block(
		folder,
		Vector3.new(15, 22, 1.5),
		cc * CFrame.new(12.5, 11, 4.5),
		rgb(80, 85, 95),
		Enum.Material.DiamondPlate,
		"ContainmentWall"
	)
	Kit.block(
		folder,
		Vector3.new(10, 10, 1.5),
		cc * CFrame.new(0, 17, 4.5),
		rgb(80, 85, 95),
		Enum.Material.DiamondPlate,
		"ContainmentWall"
	)
	Kit.block(
		folder,
		Vector3.new(1.5, 22, 13),
		cc * CFrame.new(-20, 11, -2),
		rgb(80, 85, 95),
		Enum.Material.DiamondPlate,
		"ContainmentWall"
	)
	Kit.block(
		folder,
		Vector3.new(1.5, 22, 13),
		cc * CFrame.new(20, 11, -2),
		rgb(80, 85, 95),
		Enum.Material.DiamondPlate,
		"ContainmentWall"
	)
	local warn = Kit.sign(
		folder,
		Vector3.new(10, 2, 0.3),
		cc * CFrame.new(0, 13.6, 5.4) * CFrame.Angles(0, math.pi, 0),
		"⚠ CONTAINMENT ⚠",
		rgb(230, 200, 40),
		C.Black
	)
	warn.CanCollide = false
	for i, h in { 1.2, 3.0, 4.8 } do
		table.insert(
			lasers,
			Kit.laser(
				folder,
				cc * CFrame.new(0, h, 5.4),
				10,
				i == 2 and "Static" or "Blink",
				1.2,
				i * 1.1,
				0,
				Vector3.yAxis,
				owner
			)
		)
	end
	for i = -1, 1 do
		table.insert(spawns, (Kit.pedestal(folder, cc * CFrame.new(i * 10, 0, -4), rgb(60, 65, 75), rgb(255, 60, 60))))
	end

	-- Flickering ceiling lights
	for x = -1, 1 do
		for z = 0, 1 do
			local lamp = Kit.block(
				folder,
				Vector3.new(6, 0.4, 2),
				bCenter * CFrame.new(x * 28, 21.5, 15 - z * 20),
				rgb(220, 255, 230),
				Enum.Material.Neon,
				"LabLight"
			)
			lamp.CastShadow = false
			Kit.light(lamp, rgb(200, 255, 220), 1.6, 30, "Spot")
			CollectionService:AddTag(lamp, "Flicker")
		end
	end

	-- Yard: toxic puddles, barrels, wrecked van, satellite dish, crates with loot
	for _, spot in { { -55, 35 }, { 55, 45 }, { -65, -55 }, { 62, -50 }, { -24, 52 } } do
		table.insert(traps, Kit.trap(folder, "Toxic", (o * CFrame.new(spot[1], 0.1, spot[2])).Position, owner))
	end
	for i = 0, 7 do
		Kit.barrel(
			folder,
			o * CFrame.new(-75 + (i % 4) * 3.2, 1.8, 60 - math.floor(i / 4) * 3.2),
			rgb(60, 110, 60),
			true
		)
	end
	local van = Kit.model("WreckedVan", folder)
	Kit.block(
		van,
		Vector3.new(8, 7, 16),
		o * CFrame.new(65, 4, 20) * CFrame.Angles(0, math.rad(20), math.rad(8)),
		rgb(240, 240, 240),
		Enum.Material.Metal
	)
	Kit.block(
		van,
		Vector3.new(8.2, 2, 6),
		o * CFrame.new(65, 6.4, 13) * CFrame.Angles(0, math.rad(20), math.rad(8)),
		rgb(80, 160, 220),
		Enum.Material.Glass
	)
	for _, w in { { -4, -5 }, { 4, -5 }, { -4, 5 }, { 4, 5 } } do
		local wheel = Kit.cyl(
			van,
			1.2,
			3.2,
			o
				* CFrame.new(65, 1.4, 20)
				* CFrame.Angles(0, math.rad(20), 0)
				* CFrame.new(w[1], 0, w[2])
				* CFrame.Angles(0, 0, math.rad(90)),
			C.Black,
			Enum.Material.Fabric
		)
		wheel.CanCollide = false
	end
	local dish = Kit.model("SatelliteDish", folder)
	Kit.cyl(dish, 12, 1.2, o * CFrame.new(-70, 6, -20), C.Metal, Enum.Material.Metal)
	Kit.cyl(
		dish,
		1,
		14,
		o * CFrame.new(-70, 13, -20) * CFrame.Angles(math.rad(50), 0, 0),
		rgb(230, 230, 235),
		Enum.Material.Metal
	)
	for i, spot in { { -60, 10 }, { 70, -10 }, { 30, 60 } } do
		local cf = o * CFrame.new(spot[1], 2, spot[2])
		Kit.crate(folder, cf, 4, rgb(120, 140, 120))
		table.insert(spawns, cf * CFrame.new(0, 3.4, 0))
		if i == 1 then
			Kit.crate(folder, cf * CFrame.new(4.2, 0, 0), 4, rgb(120, 140, 120))
		end
	end

	-- Elevator hatch to the Underground
	local hatchCF = o * CFrame.new(70, 0, 55)
	local destination = CFrame.new(Vector3.new(110, -86, 0))
	local hatchPart, hatchPrompt = Kit.hatch(folder, hatchCF, "Take Elevator Down", destination)
	table.insert(hatches, { Part = hatchPart, Prompt = hatchPrompt, Destination = destination })
	Kit.noCollide(
		Kit.sign(
			folder,
			Vector3.new(7, 2, 0.3),
			hatchCF * CFrame.new(0, 5, 3.5) * CFrame.Angles(0, math.pi, 0),
			"⬇ SERVICE ELEVATOR",
			rgb(40, 40, 50),
			rgb(200, 200, 255)
		)
	)

	-- Cameras
	-- World yaw pi/2 looks toward world -X, i.e. out of the lab toward the Marketplace.
	table.insert(
		cameras,
		Kit.camera(folder, (bCenter * CFrame.new(-40, 16, 31.5)).Position, math.pi / 2 + 0.35, 0.6, 0.55, 40, 46, owner)
	)
	table.insert(
		cameras,
		Kit.camera(folder, (bCenter * CFrame.new(40, 16, 31.5)).Position, math.pi / 2 - 0.35, 0.6, 0.5, 40, 46, owner)
	)
	table.insert(
		cameras,
		Kit.camera(folder, (bCenter * CFrame.new(0, 18, -12)).Position, math.pi / 2, 0.9, 0.4, 36, 50, owner)
	)

	-- Robot patrol
	for _, p in { { 0, 50 }, { -50, 20 }, { 50, 20 }, { -20, -2 }, { 20, -2 }, { 0, -30 }, { -60, -40 }, { 60, -40 } } do
		table.insert(patrol, (o * CFrame.new(p[1], 3, p[2])).Position)
	end

	-- Story: abandoned in a hurry. Taped-off side doors, smashed and boarded windows, weeds
	-- pushing through the asphalt, papers blown against the fence, a barrel on its side.
	Props.cautionTape(folder, bCenter * CFrame.new(-46.2, 0.5, 0) * CFrame.Angles(0, math.rad(90), 0), 12, 11)
	Props.cautionTape(folder, bCenter * CFrame.new(46.2, 0.5, 0) * CFrame.Angles(0, math.rad(-90), 0), 10, 11)
	for _, spec in { { -28, 31.3 }, { 6, 31.3 }, { 33, 31.3 }, { -12, -31.3 }, { 24, -31.3 } } do
		Kit.detail(
			Kit.block(
				folder,
				Vector3.new(2.8, 2.6, 0.2),
				bCenter * CFrame.new(spec[1], 18.4, spec[2]),
				rgb(18, 20, 22),
				Enum.Material.SmoothPlastic
			)
		)
	end
	for _, x in { -14, 20 } do
		for k = -1, 1, 2 do
			Kit.detail(
				Kit.block(
					folder,
					Vector3.new(4, 0.7, 0.2),
					bCenter * CFrame.new(x, 18.5 + k * 0.6, 31.45) * CFrame.Angles(0, 0, math.rad(k * 14)),
					rgb(140, 116, 86),
					Enum.Material.WoodPlanks
				)
			)
		end
	end
	local weedSeed = 41
	for i = 1, 26 do
		local along = Props.between(weedSeed + i, -86, 86)
		local spot = if i % 3 == 0
			then Vector3.new(Props.between(weedSeed + i * 2, -80, 80), 0, Props.between(weedSeed + i * 3, -78, 70))
			elseif i % 3 == 1 then Vector3.new(along, 0, 72.5)
			else Vector3.new(i % 2 == 0 and -88.5 or 88.5, 0, along * 0.85 - 5)
		if not (spot.Z > 70 and math.abs(spot.X) < 16) then
			local tuft = Kit.ball(
				folder,
				Props.between(weedSeed + i * 5, 0.9, 1.9),
				o * CFrame.new(spot.X, 0.25, spot.Z),
				rgb(86, 108, 54):Lerp(rgb(120, 116, 64), Kit.hash(weedSeed + i)),
				Enum.Material.LeafyGrass
			)
			Kit.detail(tuft)
		end
	end
	for i = 1, 9 do
		local base = if i <= 5 then Vector3.new(58, 0, 8) else Vector3.new(-40, 0, 66)
		local at = o
			* CFrame.new(base.X + Props.between(i * 7, -9, 9), 0.23, base.Z + Props.between(i * 11, -7, 7))
			* CFrame.Angles(0, Kit.hash(i * 13) * 6.28, 0)
		Kit.detail(Kit.block(folder, Vector3.new(1.1, 0.03, 1.5), at, rgb(226, 222, 210), Enum.Material.SmoothPlastic))
	end
	local tipped = Kit.barrel(
		folder,
		o * CFrame.new(-62, 1.5, 63) * CFrame.Angles(math.rad(90), 0, math.rad(25)),
		rgb(60, 104, 60),
		false
	)
	tipped.Name = "TippedBarrel"

	return {
		Id = "Laboratory",
		Folder = folder,
		Spawns = spawns,
		Patrol = patrol,
		Lasers = lasers,
		Cameras = cameras,
		Traps = traps,
		Hatches = hatches,
	}
end
