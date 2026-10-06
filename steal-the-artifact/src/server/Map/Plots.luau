--[[
	Plots - one vault per player, arranged in a ring around the city.
	Each plot gets: a vault building with a crackable door, a SECURE pad just inside,
	a laser band, trap slots, camera mounts, 20 display pedestals, an owner sign,
	a control terminal and alarm lights. Security devices are installed later by the
	SecurityService based on the owner's upgrades.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)

local C = Kit.Colors
local rgb = Kit.rgb

export type Pedestal = { CFrame: CFrame, Glow: BasePart, Top: BasePart }

export type PlotData = {
	Index: number,
	CFrame: CFrame,
	Folder: Model,
	Devices: Folder,
	SpawnCFrame: CFrame,
	Front: CFrame,
	SecurePad: { Position: Vector3, Radius: number, Part: BasePart },
	Door: { Part: BasePart, Closed: CFrame, Open: CFrame, Prompt: ProximityPrompt },
	Pedestals: { Pedestal },
	Interior: { CFrame: CFrame, Size: Vector3 },
	Sign: { Part: BasePart, Label: TextLabel, Labels: { TextLabel } },
	Terminal: BasePart,
	LaserSlots: { { CFrame: CFrame, Length: number } },
	CameraSlots: { { Position: Vector3, Yaw: number } },
	TrapSlots: { Vector3 },
	GuardSpawn: CFrame,
	Patrol: { Vector3 },
	AlarmLights: { BasePart },
	Skin: { Primary: { BasePart }, Secondary: { BasePart }, Accent: { BasePart } },
}

local function worldYaw(plotCF: CFrame, fromLocal: Vector3, toLocal: Vector3): number
	local dir = plotCF:VectorToWorldSpace(toLocal - fromLocal)
	return math.atan2(-dir.X, -dir.Z)
end

local function buildPlot(root: Instance, index: number, plotCF: CFrame): PlotData
	local folder = Kit.model("Plot" .. index, root)
	folder:SetAttribute("PlotIndex", index)
	local devices = Kit.folder("Devices", folder)
	local skin = { Primary = {}, Secondary = {}, Accent = {} }
	local function tag(part: BasePart, group: string): BasePart
		table.insert(skin[group], part)
		return part
	end

	local SECONDARY = rgb(90, 95, 110)
	local ACCENT = rgb(255, 200, 60)
	local STONE = rgb(176, 168, 154)

	-- Lot: lawn with a stone curb (open at the gate) and a paved front walk
	local platform = Kit.block(
		folder,
		Vector3.new(96, 2, 96),
		plotCF * CFrame.new(0, 0, 0),
		rgb(98, 130, 70),
		Enum.Material.Grass,
		"Platform"
	)
	platform.CastShadow = false
	local edge = Kit.block(
		folder,
		Vector3.new(97, 1.6, 97),
		plotCF * CFrame.new(0, -0.3, 0),
		rgb(150, 140, 120),
		Enum.Material.Cobblestone
	)
	edge.CastShadow = false
	for _, wall in
		{
			{ Vector3.new(96, 1.4, 1.6), Vector3.new(0, 1.7, 47.2) },
			{ Vector3.new(1.6, 1.4, 96), Vector3.new(-47.2, 1.7, 0) },
			{ Vector3.new(1.6, 1.4, 96), Vector3.new(47.2, 1.7, 0) },
			{ Vector3.new(40, 1.4, 1.6), Vector3.new(-28, 1.7, -47.2) },
			{ Vector3.new(40, 1.4, 1.6), Vector3.new(28, 1.7, -47.2) },
		}
	do
		Kit.block(folder, wall[1], plotCF * CFrame.new(wall[2]), STONE, Enum.Material.Cobblestone, "Curb")
	end
	local path = Kit.block(
		folder,
		Vector3.new(12, 0.2, 42),
		plotCF * CFrame.new(0, 1.05, -27),
		rgb(222, 214, 196),
		Enum.Material.Pavement,
		"Path"
	)
	path.CastShadow = false
	for side = -1, 1, 2 do
		Kit.detail(
			Kit.block(
				folder,
				Vector3.new(1, 0.24, 42),
				plotCF * CFrame.new(side * 6.5, 1.07, -27),
				rgb(150, 144, 132),
				Enum.Material.Cobblestone
			)
		)
	end

	-- Spawn pad on the front walk
	local spawnPad =
		Kit.cyl(folder, 0.3, 11, plotCF * CFrame.new(0, 1.2, -30), rgb(236, 232, 222), Enum.Material.Marble, "SpawnPad")
	spawnPad.CastShadow = false
	local spawnRing =
		Kit.cyl(folder, 0.25, 11.8, plotCF * CFrame.new(0, 1.15, -30), ACCENT, Enum.Material.Neon, "SpawnRing")
	Kit.detail(spawnRing)
	tag(spawnRing, "Accent")
	local spawnEmblem = Kit.cyl(folder, 0.34, 4, plotCF * CFrame.new(0, 1.21, -30), SECONDARY, Enum.Material.Metal)
	Kit.detail(spawnEmblem)
	tag(spawnEmblem, "Secondary")

	-- Vault building
	local b = plotCF * CFrame.new(0, 1, 18)
	local floor = tag(
		Kit.block(
			folder,
			Vector3.new(56, 0.3, 48),
			b * CFrame.new(0, 0.15, 0),
			SECONDARY,
			Enum.Material.SmoothPlastic,
			"VaultFloor"
		),
		"Secondary"
	)
	floor.CastShadow = false
	for _, wall in
		Kit.room(
			folder,
			b * CFrame.new(0, 0.3, 0),
			Vector3.new(56, 20, 48),
			2,
			rgb(150, 155, 165),
			Enum.Material.Concrete,
			{ Front = 10 },
			12
		)
	do
		tag(wall, "Primary")
	end
	tag(
		Kit.block(folder, Vector3.new(58, 1.5, 50), b * CFrame.new(0, 21, 0), SECONDARY, Enum.Material.Concrete, "Roof"),
		"Secondary"
	)

	-- Architecture: plinth, pilasters, belt course, cornice, parapet
	local function trim(size: Vector3, cf: CFrame, name: string?)
		local part = Kit.block(folder, size, cf, SECONDARY, Enum.Material.Concrete, name or "Trim")
		part.CastShadow = false
		part.CanQuery = false
		return tag(part, "Secondary")
	end
	trim(Vector3.new(58.4, 1.4, 1.4), b * CFrame.new(0, 0.7, 24.4), "Plinth")
	for side = -1, 1, 2 do
		trim(Vector3.new(1.4, 1.4, 50.2), b * CFrame.new(side * 28.4, 0.7, 0), "Plinth")
		trim(Vector3.new(22.6, 1.4, 1.4), b * CFrame.new(side * 17, 0.7, -24.4), "Plinth")
		for _, z in { -24, -8, 8, 24 } do
			trim(Vector3.new(3, 21, 3), b * CFrame.new(side * 28, 10.8, z), "Pilaster")
		end
		trim(Vector3.new(3, 21, 3), b * CFrame.new(side * 17, 10.8, -24.2), "Pilaster")
		-- Belt course (kept clear of the doorway)
		trim(Vector3.new(0.8, 1, 48.6), b * CFrame.new(side * 28.4, 13.4, 0))
		trim(Vector3.new(19.6, 1, 0.8), b * CFrame.new(side * 18.6, 13.4, -24.4))
	end
	trim(Vector3.new(56.6, 1, 0.8), b * CFrame.new(0, 13.4, 24.4))
	trim(Vector3.new(60, 1.2, 52), b * CFrame.new(0, 20.2, 0), "Cornice")
	for _, wall in
		{
			{ Vector3.new(58.4, 2.4, 1.2), Vector3.new(0, 22.9, -24.6) },
			{ Vector3.new(58.4, 2.4, 1.2), Vector3.new(0, 22.9, 24.6) },
			{ Vector3.new(1.2, 2.4, 48), Vector3.new(-28.6, 22.9, 0) },
			{ Vector3.new(1.2, 2.4, 48), Vector3.new(28.6, 22.9, 0) },
		}
	do
		trim(wall[1], b * CFrame.new(wall[2]), "Parapet")
	end
	-- Housing that hides the door when it slides up
	trim(Vector3.new(13, 5.4, 3.4), b * CFrame.new(0, 24.4, -24), "DoorHousing")

	-- Steel portal around the doorway
	local steel = rgb(70, 74, 86)
	for side = -1, 1, 2 do
		Kit.block(
			folder,
			Vector3.new(2.4, 13.6, 1.4),
			b * CFrame.new(side * 6.4, 7.1, -25.6),
			steel,
			Enum.Material.DiamondPlate,
			"DoorFrame"
		)
		for i = 0, 2 do
			Kit.detail(
				Kit.cyl(
					folder,
					0.4,
					0.9,
					b * CFrame.new(side * 6.4, 3 + i * 4, -26.35) * CFrame.Angles(math.rad(90), 0, 0),
					rgb(190, 192, 200),
					Enum.Material.Metal
				)
			)
		end
	end
	Kit.block(
		folder,
		Vector3.new(15.2, 2.4, 1.4),
		b * CFrame.new(0, 13.2, -25.6),
		steel,
		Enum.Material.DiamondPlate,
		"DoorFrame"
	)
	local vaultSign = Kit.block(
		folder,
		Vector3.new(16, 3.4, 0.5),
		b * CFrame.new(0, 16.6, -25.3),
		rgb(30, 32, 40),
		Enum.Material.Metal,
		"VaultSign"
	)
	Kit.detail(vaultSign)
	tag(vaultSign, "Secondary")
	Kit.label(
		vaultSign,
		"VAULT",
		{ TextColor = rgb(255, 214, 90), Font = Enum.Font.LuckiestGuy, Stroke = rgb(40, 30, 10) }
	)
	-- Hazard stripes on the threshold
	for i = 0, 4 do
		Kit.detail(
			Kit.block(
				folder,
				Vector3.new(2, 0.12, 2.4),
				b * CFrame.new(-4 + i * 2, 0.36, -26.8),
				i % 2 == 0 and rgb(250, 200, 40) or rgb(30, 30, 34),
				Enum.Material.SmoothPlastic
			)
		)
	end
	-- Wall lanterns
	for side = -1, 1, 2 do
		local lantern = Kit.block(
			folder,
			Vector3.new(1.2, 2, 1.2),
			b * CFrame.new(side * 10.5, 9.5, -25.8),
			ACCENT,
			Enum.Material.Neon,
			"Lantern"
		)
		Kit.detail(lantern)
		Kit.detail(
			Kit.block(
				folder,
				Vector3.new(1.6, 0.4, 1.6),
				b * CFrame.new(side * 10.5, 10.7, -25.8),
				steel,
				Enum.Material.Metal
			)
		)
		Kit.light(lantern, rgb(255, 214, 140), 1, 14)
	end
	-- Rooftop clutter
	Kit.block(
		folder,
		Vector3.new(6, 3, 4.5),
		b * CFrame.new(-14, 23.25, 12),
		rgb(186, 190, 196),
		Enum.Material.Metal,
		"AC"
	)
	Kit.detail(Kit.cyl(folder, 0.4, 4, b * CFrame.new(-14, 24.9, 12), rgb(60, 62, 68), Enum.Material.DiamondPlate))
	Kit.block(
		folder,
		Vector3.new(4, 2.4, 4),
		b * CFrame.new(12, 22.95, 14),
		rgb(170, 174, 180),
		Enum.Material.Metal,
		"Vent"
	)
	for i = 0, 1 do
		Kit.detail(
			Kit.cyl(folder, 3, 1, b * CFrame.new(18 + i * 2.4, 23.5, -6), rgb(160, 164, 170), Enum.Material.Metal)
		)
	end
	local dishPole = Kit.cyl(folder, 3, 0.5, b * CFrame.new(16, 23.5, 4), rgb(70, 72, 80), Enum.Material.Metal)
	Kit.detail(dishPole)
	Kit.detail(
		Kit.cyl(
			folder,
			0.5,
			5,
			b * CFrame.new(16, 25.6, 4.6) * CFrame.Angles(math.rad(-55), math.rad(30), 0),
			rgb(230, 232, 236),
			Enum.Material.Metal
		)
	)
	-- Door (slides up into the wall when open)
	local doorClosed = b * CFrame.new(0, 6.3, -24)
	local door = Kit.block(
		folder,
		Vector3.new(10, 12, 1.2),
		doorClosed,
		rgb(70, 75, 90),
		Enum.Material.DiamondPlate,
		"VaultDoor"
	)
	tag(door, "Secondary")
	local doorOpen = doorClosed * CFrame.new(0, 12.2, 0)
	local crack = Instance.new("ProximityPrompt")
	crack.Name = "CrackPrompt"
	crack.ActionText = "Crack Vault"
	crack.ObjectText = "Vault Door"
	crack.HoldDuration = 3
	crack.MaxActivationDistance = 9
	crack.RequiresLineOfSight = false
	crack.KeyboardKeyCode = Enum.KeyCode.E
	crack:SetAttribute("PlotIndex", index)
	crack.Enabled = false
	crack.Parent = door

	-- Secure pad
	local padPos = (b * CFrame.new(0, 0.35, -19.5)).Position
	local pad = Kit.cyl(
		folder,
		0.2,
		8,
		CFrame.new(padPos) * (plotCF - plotCF.Position),
		rgb(80, 255, 140),
		Enum.Material.Neon,
		"SecurePad"
	)
	pad.CanCollide = false
	pad.CastShadow = false
	tag(pad, "Accent")
	local padRing = Kit.cyl(
		folder,
		0.15,
		9.2,
		CFrame.new(padPos - Vector3.new(0, 0.05, 0)),
		rgb(30, 30, 40),
		Enum.Material.SmoothPlastic
	)
	padRing.CanCollide = false
	-- Flat label lying on the pad (front face rotated to point up).
	local padLabelPart = Kit.ghost(
		folder,
		Vector3.new(8, 8, 0.1),
		CFrame.new(padPos + Vector3.new(0, 0.12, 0)) * (plotCF - plotCF.Position) * CFrame.Angles(math.rad(90), 0, 0)
	)
	Kit.label(padLabelPart, "SECURE", { Face = Enum.NormalId.Front, TextColor = rgb(20, 60, 30), PixelsPerStud = 20 })

	-- Pedestals (5 x 4 grid)
	local pedestals: { Pedestal } = {}
	for row = 0, 3 do
		for col = -2, 2 do
			local cf = b * CFrame.new(col * 10, 0.3, 4 + row * 5.5)
			local spot, glowPart, top = Kit.pedestal(folder, cf, rgb(225, 225, 235), rgb(255, 200, 60))
			local glow = glowPart :: BasePart
			tag(glow, "Accent")
			table.insert(pedestals, { CFrame = spot, Glow = glow, Top = top })
		end
	end

	-- Laser slots across the entry band, camera mounts, trap slots
	local laserSlots = {}
	for i, z in { -14, -12, -10, -8, -6, -4 } do
		table.insert(laserSlots, { CFrame = b * CFrame.new(0, 0.3 + 1 + (i % 3) * 1.6, z), Length = 52 })
	end
	local cameraSlots = {}
	local roomCenter = Vector3.new(0, 1, 16)
	for _, spot in
		{ Vector3.new(-26, 15, -4), Vector3.new(26, 15, -4), Vector3.new(-26, 15, 40), Vector3.new(26, 15, 40) }
	do
		table.insert(cameraSlots, {
			Position = (plotCF * CFrame.new(spot)).Position,
			Yaw = worldYaw(plotCF, spot, roomCenter),
		})
	end
	local trapSlots = {}
	for _, p in
		{
			{ -18, 7 },
			{ 14, 8 },
			{ -6, 12 },
			{ 20, 14 },
			{ -22, 16 },
			{ 6, 17 },
			{ 0, 10 },
			{ -12, 19 },
			{ 16, 19 },
			{ 24, 9 },
		}
	do
		table.insert(trapSlots, (plotCF * CFrame.new(p[1], 1.3, p[2])).Position)
	end
	local patrol = {}
	-- Patrol points sit in the aisles between pedestal rows / columns.
	for _, p in { { -25, 30 }, { 25, 30 }, { -5, 36 }, { 5, 24.75 }, { -15, 16 }, { 15, 16 } } do
		table.insert(patrol, (plotCF * CFrame.new(p[1], 4, p[2])).Position)
	end

	-- Alarm lights on the roof
	local alarms = {}
	for side = -1, 1, 2 do
		local light =
			Kit.ball(folder, 2.2, b * CFrame.new(side * 27.4, 25.3, -24.6), rgb(120, 30, 30), Enum.Material.Neon)
		light.Name = "AlarmLight"
		light:SetAttribute("PlotIndex", index)
		table.insert(alarms, light)
	end

	-- Entrance gate with the owner's name on both faces
	local gate = Kit.model("Gate", folder)
	for side = -1, 1, 2 do
		local pillarCF = plotCF * CFrame.new(side * 9.5, 0, -45)
		tag(
			Kit.block(
				gate,
				Vector3.new(3.4, 1.2, 3.4),
				pillarCF * CFrame.new(0, 1.6, 0),
				SECONDARY,
				Enum.Material.Concrete,
				"GateBase"
			),
			"Secondary"
		)
		tag(
			Kit.block(
				gate,
				Vector3.new(2.6, 13, 2.6),
				pillarCF * CFrame.new(0, 8.5, 0),
				rgb(150, 155, 165),
				Enum.Material.Concrete,
				"GatePillar"
			),
			"Primary"
		)
		tag(
			Kit.block(
				gate,
				Vector3.new(3.4, 1, 3.4),
				pillarCF * CFrame.new(0, 15.5, 0),
				SECONDARY,
				Enum.Material.Concrete,
				"GateCap"
			),
			"Secondary"
		)
		local beacon = Kit.block(
			gate,
			Vector3.new(1.1, 1.3, 1.1),
			pillarCF * CFrame.new(0, 16.65, 0),
			rgb(255, 226, 178),
			Enum.Material.Neon,
			"GateLight"
		)
		Kit.detail(beacon)
		Kit.detail(
			Kit.block(
				gate,
				Vector3.new(1.7, 0.35, 1.7),
				pillarCF * CFrame.new(0, 17.45, 0),
				rgb(46, 48, 54),
				Enum.Material.Metal
			)
		)
		Kit.light(beacon, rgb(255, 220, 160), 0.9, 14)
	end
	local signPart = Kit.block(
		gate,
		Vector3.new(16.4, 4.2, 1),
		plotCF * CFrame.new(0, 12.6, -45),
		rgb(25, 25, 35),
		Enum.Material.SmoothPlastic,
		"OwnerSign"
	)
	tag(
		Kit.detail(
			Kit.block(
				gate,
				Vector3.new(16.8, 4.6, 0.6),
				plotCF * CFrame.new(0, 12.6, -45),
				SECONDARY,
				Enum.Material.Metal,
				"SignFrame"
			)
		),
		"Secondary"
	)
	local _, signLabel =
		Kit.label(signPart, "EMPTY LOT", { Face = Enum.NormalId.Front, TextColor = C.White, Name = "OwnerLabel" })
	local _, signLabelBack =
		Kit.label(signPart, "EMPTY LOT", { Face = Enum.NormalId.Back, TextColor = C.White, Name = "OwnerLabelBack" })

	-- Control terminal
	local terminal = Kit.block(
		folder,
		Vector3.new(3, 4.5, 2),
		plotCF * CFrame.new(12, 3.25, -10),
		rgb(50, 55, 70),
		Enum.Material.Metal,
		"Terminal"
	)
	local screen = Kit.block(
		folder,
		Vector3.new(2.4, 1.8, 0.2),
		plotCF * CFrame.new(12, 4.6, -11.05),
		rgb(70, 150, 190),
		Enum.Material.Neon,
		"Screen"
	)
	screen.CastShadow = false
	Kit.uiPrompt(terminal, "Vault Controls", "Terminal", "Vault")

	-- Yard dressing: lamps and flower beds along the walk, then the things that make each
	-- vault's yard its own (the gameplay layout above is identical on every plot).
	local seed = index * 97.31
	for side = -1, 1, 2 do
		local sideSeed = seed + side * 13
		Kit.lamp(folder, (plotCF * CFrame.new(side * 8.5, 1, -20)).Position, rgb(255, 230, 170), 9)
		Kit.lamp(folder, (plotCF * CFrame.new(side * 8.5, 1, -38)).Position, rgb(255, 230, 170), 9)
		Kit.flowerBed(folder, plotCF * CFrame.new(side * 12.5, 1, -29), Vector2.new(3.5, 12))
		local frontTree = plotCF
			* CFrame.new(side * (36 + Props.between(sideSeed, -2, 2)), 1, -33 + Props.between(sideSeed + 1, -3, 3))
		if Props.chance(sideSeed + 2, 0.35) then
			Kit.pine(folder, frontTree.Position, Props.between(sideSeed + 3, 1, 1.25))
		else
			Kit.tree(
				folder,
				frontTree.Position,
				Props.between(sideSeed + 4, 0.9, 1.2),
				Props.pick({ rgb(74, 112, 56), rgb(88, 122, 60), rgb(102, 124, 64), rgb(150, 116, 56) }, sideSeed + 5)
			)
		end
		Kit.tree(
			folder,
			(plotCF * CFrame.new(side * 38, 1, 36 + Props.between(sideSeed + 6, -3, 2))).Position,
			Props.between(sideSeed + 7, 0.8, 1.05)
		)
		for k, z in { -42, -36, 40 } do
			if Props.chance(sideSeed + k * 3, 0.75) then
				Kit.bush(
					folder,
					(plotCF * CFrame.new(side * 42, 1, z + Props.between(sideSeed + k, -1.5, 1.5))).Position,
					Props.between(sideSeed + k * 5, 0.65, 0.95)
				)
			end
		end
		local hedge = Kit.block(
			folder,
			Vector3.new(2.5, 3, 40),
			plotCF * CFrame.new(side * 44, 2.5, 4),
			rgb(62, 104, 54),
			Enum.Material.LeafyGrass,
			"Hedge"
		)
		hedge.CastShadow = false
		if side == -1 or Props.chance(seed + 9, 0.6) then
			Kit.bench(
				folder,
				Kit.settle(plotCF * CFrame.new(side * 24, 1, -40) * CFrame.Angles(0, math.pi, 0), sideSeed + 8, 5, 0)
			)
		end
	end
	-- Personal touches in the side yards: one front-yard item per side, one by the building
	local frontItems = {
		function(at: CFrame, s: number)
			Props.shed(folder, at * CFrame.Angles(0, math.rad(90), 0), s)
		end,
		function(at: CFrame, s: number)
			Props.car(folder, at * CFrame.new(0, 0, -2), s)
		end,
		function(at: CFrame, s: number)
			Props.doghouse(folder, at, s)
		end,
		function(at: CFrame, s: number)
			Props.grill(folder, at, s)
			Props.flowerPot(folder, (at * CFrame.new(2.5, 0, 1)).Position, s + 1)
		end,
		function(at: CFrame, s: number)
			for i = 0, 2 do
				Props.flowerPot(folder, (at * CFrame.new(i * 1.8 - 1.8, 0, (i % 2) * 0.9)).Position, s + i)
			end
		end,
		function(at: CFrame, s: number)
			Props.bike(folder, at * CFrame.Angles(0, Kit.hash(s) * 3, 0), s, Props.chance(s + 1, 0.5))
		end,
	}
	local sideItems = {
		function(at: CFrame, s: number)
			Props.palletStack(folder, at, s)
		end,
		function(at: CFrame, s: number)
			for i = 0, 2 do
				Props.box(folder, at * CFrame.new(0, 0, i * 2.4 - 2.4), s + i)
			end
		end,
		function(at: CFrame, s: number)
			Props.wheelieBin(folder, at * CFrame.Angles(0, math.rad(90), 0), s)
			Props.wheelieBin(folder, at * CFrame.new(0, 0, 3) * CFrame.Angles(0, math.rad(90), 0), s + 1)
		end,
		function(_at: CFrame, _s: number) end,
	}
	local first = math.floor(Kit.hash(seed + 20) * #frontItems) + 1
	local second = (first + 1 + math.floor(Kit.hash(seed + 21) * (#frontItems - 1))) % #frontItems + 1
	frontItems[first](plotCF * CFrame.new(-26, 1, -14), seed + 30)
	frontItems[second](plotCF * CFrame.new(26, 1, -15), seed + 40)
	local sideX = Props.chance(seed + 22, 0.5) and -37 or 37
	Props.pick(sideItems, seed + 23)(plotCF * CFrame.new(sideX, 1, 20), seed + 50)
	-- A worn line across the lawn where the owner always cuts the corner
	local from = Vector3.new(Props.chance(seed + 24, 0.5) and 6.5 or -6.5, 0, -42)
	local to = Vector3.new(from.X * 4, 0, -18)
	local wornLength = (to - from).Magnitude
	Kit.detail(
		Kit.block(
			folder,
			Vector3.new(2.2, 0.04, wornLength),
			plotCF * CFrame.lookAt((from + to) / 2, to) * CFrame.new(0, 1.02, 0),
			rgb(118, 104, 80),
			Enum.Material.Ground
		)
	)

	return {
		Index = index,
		CFrame = plotCF,
		Folder = folder,
		Devices = devices,
		SpawnCFrame = plotCF * CFrame.new(0, 4.5, -30),
		Front = plotCF * CFrame.new(0, 4.5, -16),
		SecurePad = { Position = padPos, Radius = 4.6, Part = pad },
		Door = { Part = door, Closed = doorClosed, Open = doorOpen, Prompt = crack },
		Pedestals = pedestals,
		Interior = { CFrame = b * CFrame.new(0, 10.3, 0.5), Size = Vector3.new(53, 20, 45) },
		Sign = { Part = signPart, Label = signLabel, Labels = { signLabel, signLabelBack } },
		Terminal = terminal,
		LaserSlots = laserSlots,
		CameraSlots = cameraSlots,
		TrapSlots = trapSlots,
		GuardSpawn = b * CFrame.new(5, 4, 12.25),
		Patrol = patrol,
		AlarmLights = alarms,
		Skin = skin,
	}
end

return function(root: Instance): { PlotData }
	local folder = Kit.folder("Plots", root)
	local plots = {}
	local cfg = GameConfig.Plots
	for i = 1, cfg.Count do
		local angle = (i - 1) / cfg.Count * math.pi * 2
		local position = Vector3.new(math.cos(angle) * cfg.Radius, 0, math.sin(angle) * cfg.Radius)
		-- Plot fronts (local -Z) face the city center.
		local plotCF = CFrame.lookAt(position, Vector3.zero)
		table.insert(plots, buildPlot(folder, i, plotCF))
	end
	return plots
end
