--[[
	Military Warehouse - south of the Marketplace.
	A fenced yard with a shipping-container maze, searchlight watchtowers, a huge warehouse
	of crate racks and a laser-caged armory in the back.
]]

local Zones = require(game:GetService("ReplicatedStorage").Shared.Config.Zones)
local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local rgb = Kit.rgb

local OLIVE = rgb(110, 125, 80)
local DARK_OLIVE = rgb(80, 92, 60)

local CONTAINER_COLORS = {
	rgb(200, 60, 50),
	rgb(50, 110, 200),
	rgb(60, 160, 90),
	rgb(230, 140, 40),
	rgb(40, 170, 170),
	rgb(220, 190, 50),
	rgb(140, 80, 200),
}

local function container(parent: Instance, cf: CFrame, color: Color3)
	local m = Kit.model("Container", parent)
	Kit.block(m, Vector3.new(8, 8.5, 24), cf * CFrame.new(0, 4.25, 0), color, Enum.Material.CorrodedMetal, "Container")
	for i = -5, 5 do
		local rib = Kit.block(
			m,
			Vector3.new(8.2, 8.2, 0.3),
			cf * CFrame.new(0, 4.25, i * 2.1),
			color:Lerp(C.Black, 0.18),
			Enum.Material.Metal
		)
		rib.CastShadow = false
	end
	return m
end

return function(root: Instance)
	local zone = Zones.get("Warehouse") :: any
	local center = zone.Center
	local folder = Kit.model("Warehouse", root)
	-- Local +Z faces the Marketplace (world -Z).
	local o = CFrame.new(center) * CFrame.Angles(0, math.pi, 0)
	local spawns: { CFrame } = {}
	local patrol: { Vector3 } = {}
	local lasers = {}
	local cameras = {}
	local owner = "Zone:Warehouse"

	-- Yard
	local yard = Kit.block(
		folder,
		Vector3.new(220, 1, 170),
		o * CFrame.new(0, -0.3, 0),
		rgb(95, 98, 100),
		Enum.Material.Asphalt,
		"Yard"
	)
	yard.CastShadow = false
	for i = -4, 4 do
		local line = Kit.block(
			folder,
			Vector3.new(0.6, 0.05, 30),
			o * CFrame.new(i * 18, 0.23, 40),
			rgb(240, 220, 80),
			Enum.Material.SmoothPlastic
		)
		line.CastShadow = false
	end

	-- Perimeter fence (chain link look) with a gate at +Z
	local function fence(cf: CFrame, length: number)
		local mesh = Kit.block(
			folder,
			Vector3.new(length, 10, 0.3),
			cf * CFrame.new(0, 5, 0),
			rgb(150, 155, 160),
			Enum.Material.DiamondPlate,
			"Fence"
		)
		mesh.Transparency = 0.55
		for i = 0, math.floor(length / 12) do
			Kit.cyl(
				folder,
				11,
				0.5,
				cf * CFrame.new(-length / 2 + i * 12, 5.5, 0),
				rgb(90, 95, 100),
				Enum.Material.Metal
			)
		end
	end
	fence(o * CFrame.new(-61.5, 0, 85), 97)
	fence(o * CFrame.new(61.5, 0, 85), 97)
	fence(o * CFrame.new(0, 0, -85), 220)
	fence(o * CFrame.new(-110, 0, 0) * CFrame.Angles(0, math.rad(90), 0), 170)
	fence(o * CFrame.new(110, 0, 0) * CFrame.Angles(0, math.rad(90), 0), 170)
	-- Gate booth + barrier
	local booth =
		Kit.block(folder, Vector3.new(7, 9, 7), o * CFrame.new(20, 4.5, 80), OLIVE, Enum.Material.Concrete, "GateBooth")
	Kit.block(folder, Vector3.new(7.4, 0.6, 7.4), o * CFrame.new(20, 9.3, 80), DARK_OLIVE, Enum.Material.Metal)
	local window =
		Kit.block(folder, Vector3.new(5, 3, 0.2), o * CFrame.new(20, 6, 83.55), rgb(150, 200, 230), Enum.Material.Glass)
	window.CanCollide = false
	local arm = Kit.block(
		folder,
		Vector3.new(24, 0.6, 0.6),
		o * CFrame.new(5, 4, 86),
		C.Red,
		Enum.Material.SmoothPlastic,
		"BarrierArm"
	)
	arm.CanCollide = false
	Kit.label(booth, "🪖", { Face = Enum.NormalId.Back })
	Kit.sign(
		folder,
		Vector3.new(34, 4, 0.6),
		o * CFrame.new(0, 13, 86) * CFrame.Angles(0, math.pi, 0),
		"🪖 MILITARY WAREHOUSE 🪖",
		DARK_OLIVE,
		rgb(240, 230, 160),
		{ Font = Enum.Font.LuckiestGuy }
	)
	for side = -1, 1, 2 do
		Kit.block(folder, Vector3.new(2, 15, 2), o * CFrame.new(side * 17.5, 7.5, 86), DARK_OLIVE, Enum.Material.Metal)
	end

	-- Warehouse building
	local w = o * CFrame.new(0, 0.2, -45)
	local floor = Kit.block(
		folder,
		Vector3.new(110, 0.6, 60),
		w * CFrame.new(0, 0, 0),
		rgb(130, 132, 135),
		Enum.Material.Concrete,
		"WarehouseFloor"
	)
	floor.CastShadow = false
	Kit.room(
		folder,
		w * CFrame.new(0, 0.3, 0),
		Vector3.new(110, 28, 60),
		2,
		OLIVE,
		Enum.Material.CorrodedMetal,
		{ Back = 30, Left = 12, Right = 12 },
		18
	)
	Kit.block(
		folder,
		Vector3.new(112, 1.5, 62),
		w * CFrame.new(0, 29, 0),
		DARK_OLIVE,
		Enum.Material.CorrodedMetal,
		"Roof"
	)
	Kit.sign(
		folder,
		Vector3.new(20, 3.5, 0.4),
		w * CFrame.new(0, 23, 30.4) * CFrame.Angles(0, math.pi, 0),
		"STORAGE 51",
		DARK_OLIVE,
		rgb(255, 230, 120)
	)
	-- Roller door (raised) above the opening
	Kit.block(
		folder,
		Vector3.new(30, 3, 1.2),
		w * CFrame.new(0, 19.8, 31),
		rgb(170, 170, 170),
		Enum.Material.Metal,
		"RollerDoor"
	)

	-- Racks of crates (spawns on shelves)
	for _, x in { -36, -14, 14, 36 } do
		for _, z in { 12, -2 } do
			local rack = w * CFrame.new(x, 0.3, z)
			for _, lx in { -6, 6 } do
				for _, lz in { -5, 5 } do
					Kit.block(
						folder,
						Vector3.new(0.6, 14, 0.6),
						rack * CFrame.new(lx, 7, lz),
						rgb(230, 120, 40),
						Enum.Material.Metal
					)
				end
			end
			for level = 1, 3 do
				Kit.block(
					folder,
					Vector3.new(13, 0.4, 11),
					rack * CFrame.new(0, level * 4.4 - 1.8, 0),
					rgb(60, 110, 200),
					Enum.Material.Metal,
					"Shelf"
				)
			end
			-- Shelf tops sit at 2.8 / 7.2 / 11.6 above the rack base.
			Kit.crate(folder, rack * CFrame.new(-3.5, 4.4, 2), 3.2, rgb(160, 130, 90))
			Kit.crate(folder, rack * CFrame.new(3, 8.8, -2), 3.2, OLIVE)
			Kit.crate(folder, rack * CFrame.new(-2, 13.2, -2), 3.2, rgb(160, 130, 90))
			table.insert(spawns, rack * CFrame.new(3, 4.2, 2.5))
		end
	end

	-- Armory cage with lasers (back-left)
	local cage = w * CFrame.new(-38, 0.3, -22)
	for _, x in { -10, 10 } do
		local bars = Kit.block(
			folder,
			Vector3.new(0.4, 14, 16),
			cage * CFrame.new(x, 7, 0),
			rgb(120, 125, 130),
			Enum.Material.DiamondPlate
		)
		bars.Transparency = 0.45
	end
	local top = Kit.block(
		folder,
		Vector3.new(20, 0.4, 16),
		cage * CFrame.new(0, 14, 0),
		rgb(120, 125, 130),
		Enum.Material.DiamondPlate
	)
	top.Transparency = 0.45
	local armorySign = Kit.sign(
		folder,
		Vector3.new(12, 2, 0.3),
		cage * CFrame.new(0, 12, 8.2) * CFrame.Angles(0, math.pi, 0),
		"⚠ ARMORY - KEEP OUT ⚠",
		rgb(230, 200, 40),
		C.Black
	)
	armorySign.CanCollide = false
	for i, h in { 1.0, 2.8, 4.6 } do
		table.insert(
			lasers,
			Kit.laser(folder, cage * CFrame.new(0, h, 8), 20, "Sweep", 1.1 + i * 0.2, i, 1.2, Vector3.yAxis, owner)
		)
	end
	for _, x in { -5, 0, 5 } do
		table.insert(spawns, (Kit.pedestal(folder, cage * CFrame.new(x, 0, -3), rgb(70, 75, 80), rgb(255, 80, 60))))
	end

	-- Container maze in the yard
	local layout = {
		{ -84, 40, 0 },
		{ -84, 10, 0 },
		{ -60, 58, 90 },
		{ 60, 58, 90 },
		{ 84, 40, 0 },
		{ 84, 10, 0 },
		{ -38, 28, 90 },
		{ 38, 28, 90 },
	}
	for i, spec in layout do
		local cf = o * CFrame.new(spec[1], 0.2, spec[2]) * CFrame.Angles(0, math.rad(spec[3]), 0)
		container(folder, cf, CONTAINER_COLORS[(i - 1) % #CONTAINER_COLORS + 1])
		if i <= 2 or i == 5 then
			container(folder, cf * CFrame.new(0, 8.5, 0), CONTAINER_COLORS[(i + 2) % #CONTAINER_COLORS + 1])
			table.insert(spawns, cf * CFrame.new(0, 18.6, 6))
			-- Ladder up the stack, on the side facing the yard center.
			Kit.truss(folder, cf * CFrame.new(spec[1] < 0 and 5 or -5, 0, 0), 18)
		else
			table.insert(spawns, cf * CFrame.new(0, 10.1, -6))
		end
	end
	-- Crate steps so you can climb the containers
	for _, spec in { { -40, 34 }, { 40, 34 }, { -60, 64 }, { 60, 64 } } do
		Kit.crate(folder, o * CFrame.new(spec[1], 6.2, spec[2]), 4, rgb(170, 130, 80))
		Kit.crate(folder, o * CFrame.new(spec[1], 2.2, spec[2] + 4), 4, rgb(170, 130, 80))
	end
	for _, spec in { { 0, 40 }, { -20, 62 }, { 22, 66 } } do
		local cf = o * CFrame.new(spec[1], 2.2, spec[2])
		Kit.crate(folder, cf, 4, OLIVE)
		table.insert(spawns, cf * CFrame.new(0, 3.3, 0))
	end

	-- Watchtowers with searchlights
	for side = -1, 1, 2 do
		local base = o * CFrame.new(side * 98, 0.2, 72)
		for _, leg in { { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } } do
			Kit.block(
				folder,
				Vector3.new(0.8, 18, 0.8),
				base * CFrame.new(leg[1], 9, leg[2]),
				DARK_OLIVE,
				Enum.Material.Metal
			)
		end
		Kit.block(folder, Vector3.new(9, 0.6, 9), base * CFrame.new(0, 18, 0), DARK_OLIVE, Enum.Material.Metal)
		Kit.block(folder, Vector3.new(10, 0.6, 10), base * CFrame.new(0, 24, 0), OLIVE, Enum.Material.Metal)
		local yaw = math.atan2(side * 98, 62) -- local yaw that looks back toward the yard center
		local worldYaw = select(2, (o * CFrame.Angles(0, yaw, 0)):ToEulerAnglesYXZ())
		table.insert(
			cameras,
			Kit.camera(folder, (base * CFrame.new(0, 21, 0)).Position, worldYaw, 0.7, 0.35, 60, 30, owner, 22)
		)
	end
	table.insert(
		cameras,
		Kit.camera(
			folder,
			(w * CFrame.new(-50, 20, 26)).Position,
			select(2, (o * CFrame.Angles(0, math.rad(-20), 0)):ToEulerAnglesYXZ()),
			0.6,
			0.5,
			44,
			44,
			owner
		)
	)
	table.insert(
		cameras,
		Kit.camera(
			folder,
			(w * CFrame.new(50, 20, 26)).Position,
			select(2, (o * CFrame.Angles(0, math.rad(20), 0)):ToEulerAnglesYXZ()),
			0.6,
			0.5,
			44,
			44,
			owner
		)
	)

	-- Army truck + forklift (decor)
	local truck = Kit.model("Truck", folder)
	local tcf = o * CFrame.new(-60, 0.2, -2) * CFrame.Angles(0, math.rad(90), 0)
	Kit.block(truck, Vector3.new(8, 4, 22), tcf * CFrame.new(0, 3.5, 0), DARK_OLIVE, Enum.Material.Metal)
	Kit.block(truck, Vector3.new(8, 4, 6), tcf * CFrame.new(0, 7.5, -7), DARK_OLIVE, Enum.Material.Metal)
	local canvas = Kit.block(truck, Vector3.new(8.2, 6, 14), tcf * CFrame.new(0, 8.5, 4), OLIVE, Enum.Material.Fabric)
	canvas.CastShadow = true
	for _, wz in { -8, 0, 8 } do
		for _, wx in { -4.2, 4.2 } do
			Kit.cyl(
				truck,
				1.4,
				3.6,
				tcf * CFrame.new(wx, 1.8, wz) * CFrame.Angles(0, 0, math.rad(90)),
				C.Black,
				Enum.Material.Fabric
			)
		end
	end
	local forklift = Kit.model("Forklift", folder)
	local fcf = o * CFrame.new(30, 0.2, 2)
	Kit.block(forklift, Vector3.new(5, 4, 7), fcf * CFrame.new(0, 2.6, 0), rgb(240, 190, 30), Enum.Material.Metal)
	Kit.block(forklift, Vector3.new(0.4, 8, 0.4), fcf * CFrame.new(-1.8, 4, -3.8), C.Black, Enum.Material.Metal)
	Kit.block(forklift, Vector3.new(0.4, 8, 0.4), fcf * CFrame.new(1.8, 4, -3.8), C.Black, Enum.Material.Metal)
	Kit.block(forklift, Vector3.new(4.5, 0.3, 4), fcf * CFrame.new(0, 1, -6), C.Black, Enum.Material.Metal)

	-- Guard patrol
	for _, p in
		{
			{ 0, 70 },
			{ -60, 40 },
			{ 60, 40 },
			{ 0, 25 },
			{ -30, -30 },
			{ 30, -30 },
			{ 0, -50 },
			{ -90, -20 },
			{ 90, -20 },
			{ 0, 5 },
		}
	do
		table.insert(patrol, (o * CFrame.new(p[1], 3, p[2])).Position)
	end

	return {
		Id = "Warehouse",
		Folder = folder,
		Spawns = spawns,
		Patrol = patrol,
		Lasers = lasers,
		Cameras = cameras,
		Traps = {},
		Hatches = {},
	}
end
