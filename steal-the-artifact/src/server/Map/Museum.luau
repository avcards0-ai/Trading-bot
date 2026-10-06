--[[
	Grand Artifact Museum - north of the Marketplace.
	Main hall of display cases, a laser-filled Gem Wing (west), a Natural History wing with
	a dinosaur skeleton (east), a rotunda centerpiece, cameras everywhere and guards.
]]

local Zones = require(game:GetService("ReplicatedStorage").Shared.Config.Zones)
local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local rgb = Kit.rgb

local WIDTH, DEPTH, HEIGHT = 150, 110, 30
local FLOOR_Y = 4

return function(root: Instance)
	local zone = Zones.get("Museum") :: any
	local center = zone.Center
	local folder = Kit.model("Museum", root)
	local o = CFrame.new(center)
	local spawns: { CFrame } = {}
	local patrol: { Vector3 } = {}
	local lasers = {}
	local cameras = {}
	local owner = "Zone:Museum"

	local frontZ = DEPTH / 2 -- local +Z faces the Marketplace

	-- Foundation + floor
	Kit.block(
		folder,
		Vector3.new(WIDTH + 8, FLOOR_Y, DEPTH + 8),
		o * CFrame.new(0, FLOOR_Y / 2, 0),
		rgb(200, 195, 185),
		Enum.Material.Concrete,
		"Foundation"
	)
	local floor = Kit.block(
		folder,
		Vector3.new(WIDTH, 0.4, DEPTH),
		o * CFrame.new(0, FLOOR_Y + 0.2, 0),
		rgb(232, 226, 214),
		Enum.Material.Marble,
		"Floor"
	)
	floor.CastShadow = false
	-- Checker accents in the main hall
	for z = -4, 4 do
		local tile = Kit.block(
			folder,
			Vector3.new(10, 0.45, 10),
			o * CFrame.new(0, FLOOR_Y + 0.2, z * 11),
			(z % 2 == 0) and rgb(60, 60, 70) or rgb(240, 236, 228),
			Enum.Material.Marble
		)
		tile.CastShadow = false
	end

	-- Grand stairs
	Kit.stairs(
		folder,
		o * CFrame.new(0, 0, frontZ + 4 + 12) * CFrame.Angles(0, 0, 0),
		8,
		46,
		FLOOR_Y / 8,
		1.5,
		rgb(225, 220, 210),
		Enum.Material.Marble
	)

	-- Walls
	local wallColor = rgb(236, 230, 218)
	local y = FLOOR_Y + HEIGHT / 2
	-- Front wall with three doorways (center 18 wide, sides 10 wide)
	local segments = {
		{ -75, -42 },
		{ -32, -9 },
		{ 9, 32 },
		{ 42, 75 },
	}
	for _, seg in segments do
		local width = seg[2] - seg[1]
		Kit.block(
			folder,
			Vector3.new(width, HEIGHT, 2),
			o * CFrame.new((seg[1] + seg[2]) / 2, y, frontZ),
			wallColor,
			Enum.Material.Marble,
			"Wall"
		)
	end
	for _, gap in { { -42, -32 }, { -9, 9 }, { 32, 42 } } do
		local width = gap[2] - gap[1]
		Kit.block(
			folder,
			Vector3.new(width, HEIGHT - 14, 2),
			o * CFrame.new((gap[1] + gap[2]) / 2, FLOOR_Y + 14 + (HEIGHT - 14) / 2, frontZ),
			wallColor,
			Enum.Material.Marble,
			"Lintel"
		)
	end
	Kit.block(
		folder,
		Vector3.new(WIDTH, HEIGHT, 2),
		o * CFrame.new(0, y, -DEPTH / 2),
		wallColor,
		Enum.Material.Marble,
		"Wall"
	)
	-- Side walls with one service door each
	for side = -1, 1, 2 do
		local x = side * WIDTH / 2
		Kit.block(
			folder,
			Vector3.new(2, HEIGHT, 45),
			o * CFrame.new(x, y, -DEPTH / 2 + 22.5),
			wallColor,
			Enum.Material.Marble,
			"Wall"
		)
		Kit.block(
			folder,
			Vector3.new(2, HEIGHT, 55),
			o * CFrame.new(x, y, DEPTH / 2 - 27.5),
			wallColor,
			Enum.Material.Marble,
			"Wall"
		)
		Kit.block(
			folder,
			Vector3.new(2, HEIGHT - 12, 10),
			o * CFrame.new(x, FLOOR_Y + 12 + (HEIGHT - 12) / 2, -DEPTH / 2 + 50),
			wallColor,
			Enum.Material.Marble,
			"Lintel"
		)
	end
	-- Ramps up to the side doors
	for side = -1, 1, 2 do
		local x = side * (WIDTH / 2 + 4 + 5)
		Kit.wedge(
			folder,
			Vector3.new(10, FLOOR_Y, 10),
			o * CFrame.new(x, FLOOR_Y / 2, -5) * CFrame.Angles(0, -side * math.rad(90), 0),
			rgb(200, 195, 185),
			Enum.Material.Concrete
		)
	end

	-- Interior partitions between the main hall and the wings (two openings each)
	for side = -1, 1, 2 do
		local x = side * 30
		Kit.block(
			folder,
			Vector3.new(1.5, HEIGHT, 30),
			o * CFrame.new(x, y, 40),
			rgb(210, 200, 185),
			Enum.Material.Marble,
			"Partition"
		)
		Kit.block(
			folder,
			Vector3.new(1.5, HEIGHT, 30),
			o * CFrame.new(x, y, -2),
			rgb(210, 200, 185),
			Enum.Material.Marble,
			"Partition"
		)
		Kit.block(
			folder,
			Vector3.new(1.5, HEIGHT, 22),
			o * CFrame.new(x, y, -44),
			rgb(210, 200, 185),
			Enum.Material.Marble,
			"Partition"
		)
	end

	-- Roof with a glass skylight over the rotunda
	local roofY = FLOOR_Y + HEIGHT + 0.75
	Kit.block(
		folder,
		Vector3.new(WIDTH + 6, 1.5, 70),
		o * CFrame.new(0, roofY, 20),
		rgb(170, 160, 150),
		Enum.Material.Slate,
		"Roof"
	)
	Kit.block(
		folder,
		Vector3.new(55, 1.5, 40),
		o * CFrame.new(-50.5, roofY, -35),
		rgb(170, 160, 150),
		Enum.Material.Slate,
		"Roof"
	)
	Kit.block(
		folder,
		Vector3.new(55, 1.5, 40),
		o * CFrame.new(50.5, roofY, -35),
		rgb(170, 160, 150),
		Enum.Material.Slate,
		"Roof"
	)
	local skylight = Kit.block(
		folder,
		Vector3.new(46, 1, 40),
		o * CFrame.new(0, roofY, -35),
		rgb(200, 230, 255),
		Enum.Material.Glass,
		"Skylight"
	)
	skylight.Transparency = 0.5

	-- Facade: columns + pediment + sign
	-- Columns stand between the doorways (gaps at -42..-32, -9..9, 32..42).
	for _, x in { -70, -60, -50, -24, -16, 16, 24, 50, 60, 70 } do
		Kit.pillar(
			folder,
			center + Vector3.new(x, FLOOR_Y, frontZ + 3),
			HEIGHT - 2,
			3.2,
			rgb(244, 240, 230),
			Enum.Material.Marble
		)
	end
	Kit.block(
		folder,
		Vector3.new(WIDTH + 6, 2, 10),
		o * CFrame.new(0, FLOOR_Y + HEIGHT - 1, frontZ + 5),
		rgb(244, 240, 230),
		Enum.Material.Marble
	)
	-- Pediment: two wedges rising to a ridge over the middle of the portico.
	for side = -1, 1, 2 do
		Kit.wedge(
			folder,
			Vector3.new(10, 16, (WIDTH + 6) / 2),
			o
				* CFrame.new(side * (WIDTH + 6) / 4, FLOOR_Y + HEIGHT + 8, frontZ + 5)
				* CFrame.Angles(0, math.rad(-side * 90), 0),
			rgb(244, 240, 230),
			Enum.Material.Marble
		)
		-- Raking cornice along each slope
		local slope = math.atan2(16, (WIDTH + 6) / 2)
		Kit.detail(
			Kit.block(
				folder,
				Vector3.new((WIDTH + 6) / 2 / math.cos(slope) + 1, 1.2, 11),
				o
					* CFrame.new(side * (WIDTH + 6) / 4, FLOOR_Y + HEIGHT + 8.6, frontZ + 5)
					* CFrame.Angles(0, 0, side * -slope),
				rgb(226, 220, 206),
				Enum.Material.Marble
			)
		)
	end
	Kit.detail(
		Kit.cyl(
			folder,
			0.6,
			7,
			o * CFrame.new(0, FLOOR_Y + HEIGHT + 6, frontZ + 10.4) * CFrame.Angles(math.rad(90), 0, 0),
			C.Gold,
			Enum.Material.Metal
		)
	)
	Kit.sign(
		folder,
		Vector3.new(60, 5, 1),
		o * CFrame.new(0, FLOOR_Y + HEIGHT - 5.5, frontZ + 5.5) * CFrame.Angles(0, math.pi, 0),
		"GRAND ARTIFACT MUSEUM",
		rgb(140, 30, 40),
		C.Gold,
		{ Font = Enum.Font.LuckiestGuy }
	)
	-- Banners
	for side = -1, 1, 2 do
		local banner = Kit.block(
			folder,
			Vector3.new(6, 14, 0.3),
			o * CFrame.new(side * 50, FLOOR_Y + 14, frontZ + 1.3),
			rgb(170, 30, 50),
			Enum.Material.Fabric
		)
		Kit.label(banner, "🏛️<br/>EXHIBIT<br/>OPEN", { Face = Enum.NormalId.Back, TextColor = C.Gold })
	end

	-- Main hall: two rows of display cases
	for row = 0, 3 do
		for side = -1, 1, 2 do
			local cf = o * CFrame.new(side * 14, FLOOR_Y + 0.4, 30 - row * 17)
			table.insert(spawns, Kit.displayCase(folder, cf, rgb(240, 235, 225)))
		end
	end

	-- Rotunda centerpiece
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		Kit.pillar(
			folder,
			center + Vector3.new(math.cos(angle) * 15, FLOOR_Y, -35 + math.sin(angle) * 15),
			HEIGHT,
			2.4,
			rgb(245, 242, 235),
			Enum.Material.Marble
		)
	end
	Kit.cyl(folder, 1.2, 14, o * CFrame.new(0, FLOOR_Y + 0.6, -35), rgb(140, 30, 40), Enum.Material.Fabric)
	table.insert(spawns, (Kit.pedestal(folder, o * CFrame.new(0, FLOOR_Y + 1.2, -35), rgb(250, 245, 235), C.Gold)))
	local spotlight = Kit.ghost(folder, Vector3.one, o * CFrame.new(0, FLOOR_Y + HEIGHT - 2, -35))
	Kit.light(spotlight, rgb(255, 240, 200), 4, 40, "Spot")

	-- Gem Wing (west): cases + laser grid
	for i = 0, 3 do
		local cf = o * CFrame.new(-52 + (i % 2) * 12, FLOOR_Y + 0.4, 34 - i * 22)
		table.insert(spawns, Kit.displayCase(folder, cf, rgb(220, 230, 250)))
	end
	table.insert(
		spawns,
		(Kit.pedestal(folder, o * CFrame.new(-52, FLOOR_Y + 0.4, -46), rgb(220, 230, 250), rgb(120, 200, 255)))
	)
	local gemSign = Kit.sign(
		folder,
		Vector3.new(16, 3, 0.5),
		o * CFrame.new(-52, FLOOR_Y + 22, DEPTH / 2 - 1.5),
		"💎 THE GEM WING 💎",
		rgb(20, 30, 60),
		rgb(140, 210, 255)
	)
	gemSign.CanCollide = false
	local laserSpecs = {
		{ Z = 26, H = 1.4, Pattern = "Sweep", Speed = 1.2, Amp = 2.4, Axis = Vector3.yAxis },
		{ Z = 20, H = 3.4, Pattern = "Blink", Speed = 1.0, Amp = 0, Axis = Vector3.yAxis },
		{ Z = 3, H = 2.2, Pattern = "Sweep", Speed = 1.6, Amp = 2.5, Axis = Vector3.zAxis },
		{ Z = -18, H = 1.0, Pattern = "Static", Speed = 0, Amp = 0, Axis = Vector3.yAxis },
		{ Z = -18, H = 4.6, Pattern = "Blink", Speed = 1.4, Amp = 0, Axis = Vector3.yAxis },
		{ Z = -25, H = 2.6, Pattern = "Chaos", Speed = 1.3, Amp = 2.0, Axis = Vector3.yAxis },
	}
	for i, spec in laserSpecs do
		local cf = o * CFrame.new(-52.5, FLOOR_Y + 0.4 + spec.H, spec.Z)
		table.insert(lasers, Kit.laser(folder, cf, 43, spec.Pattern, spec.Speed, i * 1.3, spec.Amp, spec.Axis, owner))
	end

	-- Natural History (east): dinosaur skeleton + cases
	local bone = rgb(236, 226, 196)
	local dino = Kit.model("Dinosaur", folder)
	local dBase = o * CFrame.new(52, FLOOR_Y + 0.4, 5)
	Kit.block(dino, Vector3.new(16, 1, 30), dBase * CFrame.new(0, 0.5, 0), rgb(90, 80, 70), Enum.Material.Slate)
	for i = 0, 11 do
		local z = -12 + i * 2.2
		local height = 9 + math.sin(i / 11 * math.pi) * 3
		Kit.ball(dino, 1.2, dBase * CFrame.new(0, height, z), bone, Enum.Material.Marble)
		if i > 2 and i < 9 then
			Kit.block(
				dino,
				Vector3.new(0.4, 4, 0.4),
				dBase * CFrame.new(-1.4, height - 2, z) * CFrame.Angles(0, 0, math.rad(-25)),
				bone,
				Enum.Material.Marble
			)
			Kit.block(
				dino,
				Vector3.new(0.4, 4, 0.4),
				dBase * CFrame.new(1.4, height - 2, z) * CFrame.Angles(0, 0, math.rad(25)),
				bone,
				Enum.Material.Marble
			)
		end
	end
	Kit.block(dino, Vector3.new(3, 3, 5), dBase * CFrame.new(0, 12, -15), bone, Enum.Material.Marble)
	Kit.wedge(
		dino,
		Vector3.new(3, 1.5, 4),
		dBase * CFrame.new(0, 10.4, -16) * CFrame.Angles(math.rad(180), 0, 0),
		bone,
		Enum.Material.Marble
	)
	for _, leg in { { -2, -6 }, { 2, -6 }, { -2, 6 }, { 2, 6 } } do
		Kit.block(dino, Vector3.new(0.8, 9, 0.8), dBase * CFrame.new(leg[1], 5, leg[2]), bone, Enum.Material.Marble)
	end
	for i = 0, 2 do
		local cf = o * CFrame.new(64, FLOOR_Y + 0.4, 34 - i * 30)
		table.insert(spawns, Kit.displayCase(folder, cf, rgb(240, 230, 210)))
	end
	table.insert(spawns, Kit.displayCase(folder, o * CFrame.new(40, FLOOR_Y + 0.4, -45), rgb(240, 230, 210)))

	-- Paintings along the walls (decor)
	local canvasColors =
		{ rgb(90, 140, 220), rgb(220, 120, 80), rgb(120, 190, 110), rgb(230, 200, 90), rgb(170, 110, 200) }
	for i = 0, 4 do
		local z = 40 - i * 20
		local frame = Kit.block(
			folder,
			Vector3.new(0.4, 7, 9),
			o * CFrame.new(WIDTH / 2 - 1.3, FLOOR_Y + 10, z),
			C.Gold,
			Enum.Material.Metal
		)
		frame.CanCollide = false
		local canvas = Kit.block(
			folder,
			Vector3.new(0.45, 5.6, 7.6),
			o * CFrame.new(WIDTH / 2 - 1.35, FLOOR_Y + 10, z),
			canvasColors[i + 1],
			Enum.Material.Fabric
		)
		canvas.CanCollide = false
	end

	-- Cameras
	local camSpecs = {
		{ Pos = Vector3.new(-27, FLOOR_Y + 15, 52), Yaw = -0.35 },
		{ Pos = Vector3.new(27, FLOOR_Y + 15, 52), Yaw = 0.35 },
		{ Pos = Vector3.new(-27, FLOOR_Y + 15, -52), Yaw = math.pi + 0.35 },
		{ Pos = Vector3.new(27, FLOOR_Y + 15, -52), Yaw = math.pi - 0.35 },
		{ Pos = Vector3.new(-52, FLOOR_Y + 15, 52), Yaw = 0 },
		{ Pos = Vector3.new(52, FLOOR_Y + 15, -52), Yaw = math.pi },
	}
	for _, spec in camSpecs do
		table.insert(cameras, Kit.camera(folder, center + spec.Pos, spec.Yaw, 0.55, 0.5, 42, 44, owner))
	end

	-- Ceiling lights
	for x = -1, 1 do
		for z = -1, 1 do
			local lamp = Kit.block(
				folder,
				Vector3.new(4, 0.4, 4),
				o * CFrame.new(x * 48, FLOOR_Y + HEIGHT - 0.5, z * 32),
				rgb(255, 245, 220),
				Enum.Material.Neon
			)
			lamp.CastShadow = false
			Kit.light(lamp, rgb(255, 240, 210), 1.4, 36, "Spot")
		end
	end

	-- Guard patrol route (main hall + wings)
	for _, p in
		{
			{ 0, 40 },
			{ 0, 10 },
			{ 0, -20 },
			{ -20, -48 },
			{ 20, -48 },
			{ -52, 40 },
			{ -40, -20 },
			{ 52, 40 },
			{ 45, -25 },
			{ 0, 50 },
		}
	do
		table.insert(patrol, center + Vector3.new(p[1], FLOOR_Y + 3, p[2]))
	end

	-- Outside: garden + ticket booth
	for _, x in { -64, -32, 32, 64 } do
		Kit.tree(folder, center + Vector3.new(x, 0, frontZ + 34), 1.0)
	end
	local booth = Kit.block(
		folder,
		Vector3.new(8, 8, 6),
		o * CFrame.new(38, 4, frontZ + 26),
		rgb(140, 30, 40),
		Enum.Material.SmoothPlastic,
		"TicketBooth"
	)
	Kit.label(booth, "🎟️ TICKETS<br/>(steal one)", { Face = Enum.NormalId.Back, TextColor = C.Gold })

	return {
		Id = "Museum",
		Folder = folder,
		Spawns = spawns,
		Patrol = patrol,
		Lasers = lasers,
		Cameras = cameras,
		Traps = {},
		Hatches = {},
	}
end
