--[[
	Props
	Everyday objects that make the city feel lived in: vehicles, bins, pallets, utility
	poles with sagging wires, bus stops, fire escapes, yard clutter, construction gear...

	Every prop takes a `seed` and uses it for controlled variation (type, color, rotation,
	wear, open/closed state), so repeated props never look copy-pasted. Proportions follow
	the default character (about 5 studs tall). `cf` is the prop's base on the ground and its
	LookVector is the prop's front unless noted. Decorative sub-parts don't collide.
]]

local Kit = require(script.Parent.Kit)

local rgb = Kit.rgb

local Props = {}

local function pick<T>(list: { T }, seed: number): T
	return list[math.floor(Kit.hash(seed) * #list) + 1]
end
Props.pick = pick

local function chance(seed: number, p: number): boolean
	return Kit.hash(seed) < p
end
Props.chance = chance

local function between(seed: number, low: number, high: number): number
	return low + (high - low) * Kit.hash(seed)
end
Props.between = between

local IRON = rgb(52, 50, 50)
local RUBBER = rgb(32, 32, 34)
local GALVANIZED = rgb(150, 152, 150)

-- Vehicles -------------------------------------------------------------------------------------

Props.CarColors = {
	rgb(224, 224, 220), -- white
	rgb(178, 180, 182), -- silver
	rgb(40, 42, 46), -- black
	rgb(86, 90, 96), -- gunmetal
	rgb(46, 62, 94), -- navy
	rgb(116, 40, 44), -- maroon
	rgb(184, 170, 146), -- beige
	rgb(58, 80, 62), -- green
	rgb(140, 64, 46), -- faded red
	rgb(202, 198, 188), -- cream
}

local function wheels(m: Instance, cf: CFrame, width: number, length: number, axleInset: number, radius: number)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local at = cf * CFrame.new(x * (width / 2 - 0.4), radius, z * (length / 2 - axleInset))
			Kit.detail(
				Kit.cyl(m, 1, radius * 2, at * CFrame.Angles(0, 0, math.rad(90)), RUBBER, Enum.Material.Rubber, "Wheel")
			)
			Kit.detail(
				Kit.cyl(
					m,
					1.05,
					radius * 1.1,
					at * CFrame.Angles(0, 0, math.rad(90)),
					rgb(132, 134, 138),
					Enum.Material.Metal
				)
			)
		end
	end
end

-- Parked car: sedan, hatchback, van or pickup.
function Props.car(parent: Instance, cf: CFrame, seed: number, kind: string?): Model
	local m = Kit.model("Car", parent)
	local carKind = kind or pick({ "Sedan", "Sedan", "Hatch", "Hatch", "Van", "Pickup" }, seed)
	local paint = pick(Props.CarColors, seed + 11)
	local base = Kit.settle(cf, seed, 2.5, 0)
	local glass = rgb(40, 48, 56)
	local length = carKind == "Hatch" and 12 or carKind == "Van" and 14.6 or carKind == "Pickup" and 15.2 or 13.6
	local width = carKind == "Van" and 6.6 or 6.2
	local radius = carKind == "Pickup" and 1.45 or 1.25
	local floor = radius * 0.9
	local bodyH = carKind == "Van" and 4.8 or 1.9

	wheels(m, base, width, length, carKind == "Van" and 2.6 or 2.4, radius)
	local body = Kit.block(
		m,
		Vector3.new(width, bodyH, length),
		base * CFrame.new(0, floor + bodyH / 2, 0),
		paint,
		Enum.Material.SmoothPlastic,
		"Body"
	)
	body.Reflectance = 0.05
	local top = floor + bodyH

	if carKind == "Van" then
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(width + 0.06, 1.5, length - 5),
				base * CFrame.new(0, top - 1.3, 1.2),
				glass,
				Enum.Material.Glass
			)
		)
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(width - 0.8, 1.7, 0.2),
				base * CFrame.new(0, top - 1.3, -length / 2 - 0.02),
				glass,
				Enum.Material.Glass
			)
		)
	else
		local cabinLength = carKind == "Hatch" and 6.4 or carKind == "Pickup" and 4.6 or 5.6
		local cabinZ = carKind == "Hatch" and 1.6 or carKind == "Pickup" and -1.4 or 0.6
		local cabin = Kit.block(
			m,
			Vector3.new(width - 0.5, 1.7, cabinLength),
			base * CFrame.new(0, top + 0.85, cabinZ),
			glass,
			Enum.Material.Glass,
			"Cabin"
		)
		cabin.CastShadow = true
		Kit.block(
			m,
			Vector3.new(width - 0.6, 0.3, cabinLength - 0.4),
			base * CFrame.new(0, top + 1.85, cabinZ),
			paint,
			Enum.Material.SmoothPlastic,
			"Roof"
		).Reflectance =
			0.05
		-- Raked windshield, and a sloped rear window on sedans
		Kit.detail(
			Kit.wedge(
				m,
				Vector3.new(width - 0.5, 1.7, 1.6),
				base * CFrame.new(0, top + 0.85, cabinZ - cabinLength / 2 - 0.8),
				glass,
				Enum.Material.Glass
			)
		)
		if carKind == "Sedan" then
			Kit.detail(
				Kit.wedge(
					m,
					Vector3.new(width - 0.5, 1.7, 1.4),
					base * CFrame.new(0, top + 0.85, cabinZ + cabinLength / 2 + 0.7) * CFrame.Angles(0, math.pi, 0),
					glass,
					Enum.Material.Glass
				)
			)
		elseif carKind == "Pickup" then
			for side = -1, 1, 2 do
				Kit.detail(
					Kit.block(
						m,
						Vector3.new(0.3, 1.2, 6.2),
						base * CFrame.new(side * (width / 2 - 0.15), top + 0.6, 4),
						paint,
						Enum.Material.SmoothPlastic
					)
				)
			end
			Kit.detail(
				Kit.block(
					m,
					Vector3.new(width, 1.2, 0.3),
					base * CFrame.new(0, top + 0.6, length / 2 - 0.15),
					paint,
					Enum.Material.SmoothPlastic
				)
			)
		end
	end

	-- Lights, bumpers
	for side = -1, 1, 2 do
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(1.3, 0.6, 0.12),
				base * CFrame.new(side * (width / 2 - 1), top - 0.55, -length / 2 - 0.04),
				rgb(232, 230, 214),
				Enum.Material.SmoothPlastic
			)
		)
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(1.1, 0.5, 0.12),
				base * CFrame.new(side * (width / 2 - 0.9), top - 0.55, length / 2 + 0.04),
				rgb(150, 34, 32),
				Enum.Material.SmoothPlastic
			)
		)
	end
	for side = -1, 1, 2 do
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(width + 0.1, 0.55, 0.45),
				base * CFrame.new(0, floor + 0.3, side * (length / 2 + 0.1)),
				rgb(38, 40, 42),
				Enum.Material.Plastic
			)
		)
	end
	-- Old cars: a mismatched primer door panel and a bit of rust.
	if chance(seed + 23, 0.18) then
		local side = chance(seed + 29, 0.5) and 1 or -1
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(0.08, bodyH * 0.8, 3.2),
				base * CFrame.new(side * (width / 2 + 0.03), floor + bodyH / 2, -0.4),
				rgb(132, 132, 128),
				Enum.Material.SmoothPlastic
			)
		)
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(width + 0.04, 0.5, 2.4),
				base * CFrame.new(0, floor + 0.35, length / 2 - 3),
				rgb(110, 72, 52),
				Enum.Material.CorrodedMetal
			)
		)
	end
	return m
end

-- Industrial forklift with its forks down.
function Props.forklift(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("Forklift", parent)
	local base = Kit.settle(cf, seed, 8, 0)
	local yellow = rgb(198, 154, 46)
	wheels(m, base, 4.2, 6.4, 1.3, 1.1)
	Kit.block(m, Vector3.new(4, 2.4, 6), base * CFrame.new(0, 2.1, 0.4), yellow, Enum.Material.Metal, "Body")
	Kit.block(m, Vector3.new(4, 1.8, 1.6), base * CFrame.new(0, 3.9, 2.8), rgb(60, 60, 60), Enum.Material.Metal)
	Kit.detail(
		Kit.block(m, Vector3.new(1.6, 1.2, 1.4), base * CFrame.new(0, 3.9, 0.9), rgb(30, 30, 30), Enum.Material.Leather)
	)
	for x = -1, 1, 2 do
		for _, z in { -1.6, 2.2 } do
			Kit.detail(
				Kit.block(
					m,
					Vector3.new(0.25, 4.2, 0.25),
					base * CFrame.new(x * 1.8, 5.4, z),
					IRON,
					Enum.Material.Metal
				)
			)
		end
		Kit.block(m, Vector3.new(0.4, 7.5, 0.4), base * CFrame.new(x * 1.1, 4.4, -2.8), IRON, Enum.Material.Metal)
		Kit.block(
			m,
			Vector3.new(0.5, 0.25, 4.2),
			base * CFrame.new(x * 1, 0.35, -4.9),
			IRON,
			Enum.Material.Metal,
			"Fork"
		)
	end
	Kit.detail(Kit.block(m, Vector3.new(4.2, 0.25, 4.4), base * CFrame.new(0, 7.6, 0.3), IRON, Enum.Material.Metal))
	return m
end

-- Storage and trash ----------------------------------------------------------------------------

function Props.dumpster(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("Dumpster", parent)
	local base = Kit.settle(cf, seed, 7, 0)
	local color = pick({ rgb(52, 82, 62), rgb(52, 68, 94), rgb(92, 82, 64), rgb(70, 74, 78) }, seed)
	for _, z in { -1.4, 1.4 } do
		Kit.detail(Kit.block(m, Vector3.new(6.4, 0.5, 0.5), base * CFrame.new(0, 0.25, z), IRON, Enum.Material.Metal))
	end
	Kit.block(m, Vector3.new(6.6, 4, 3.8), base * CFrame.new(0, 2.5, 0), color, Enum.Material.Metal, "Body")
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(6.7, 0.9, 3.9),
			base * CFrame.new(0, 1.0, 0),
			color:Lerp(rgb(110, 70, 50), 0.6),
			Enum.Material.CorrodedMetal
		)
	)
	-- Lids: one shut, one propped open (or both shut)
	local hinge = base * CFrame.new(0, 4.55, 1.9)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(3.3, 0.2, 3.9),
			hinge * CFrame.new(-1.65, 0, -1.95),
			rgb(34, 36, 38),
			Enum.Material.Plastic
		)
	)
	local open = chance(seed + 3, 0.5) and math.rad(between(seed + 4, 25, 70)) or 0
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(3.3, 0.2, 3.9),
			hinge * CFrame.new(1.65, 0, 0) * CFrame.Angles(open, 0, 0) * CFrame.new(0, 0, -1.95),
			rgb(34, 36, 38),
			Enum.Material.Plastic
		)
	)
	return m
end

function Props.trashBags(parent: Instance, position: Vector3, seed: number, count: number?): Model
	local m = Kit.model("TrashBags", parent)
	for i = 1, count or 3 do
		local d = between(seed + i * 1.3, 1.4, 2.4)
		local offset =
			Vector3.new((Kit.hash(seed + i * 3.1) - 0.5) * 3, d * 0.36, (Kit.hash(seed + i * 5.7) - 0.5) * 2.2)
		local color = chance(seed + i * 7.9, 0.18) and rgb(54, 66, 90) or rgb(30, 30, 32)
		local bag = Kit.ball(m, d, CFrame.new(position + offset), color, Enum.Material.Plastic)
		bag.Reflectance = 0.06
		Kit.noCollide(bag)
	end
	return m
end

function Props.wheelieBin(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("Bin", parent)
	local base = Kit.settle(cf, seed, 12, 0)
	local color = pick({ rgb(58, 92, 62), rgb(78, 82, 86), rgb(56, 82, 120), rgb(120, 92, 54) }, seed)
	Kit.block(m, Vector3.new(2.4, 3.4, 2.6), base * CFrame.new(0, 2, 0), color, Enum.Material.Plastic, "Bin")
	local lidOpen = chance(seed + 2, 0.25) and math.rad(30) or 0
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(2.6, 0.25, 2.9),
			base * CFrame.new(0, 3.8, 1.35) * CFrame.Angles(lidOpen, 0, 0) * CFrame.new(0, 0, -1.4),
			color:Lerp(rgb(0, 0, 0), 0.2),
			Enum.Material.Plastic
		)
	)
	for x = -1, 1, 2 do
		Kit.detail(
			Kit.cyl(
				m,
				0.35,
				0.9,
				base * CFrame.new(x * 0.9, 0.45, 1.2) * CFrame.Angles(0, 0, math.rad(90)),
				RUBBER,
				Enum.Material.Rubber
			)
		)
	end
	return m
end

function Props.pallet(parent: Instance, cf: CFrame, seed: number): BasePart
	local wood = rgb(176, 146, 104):Lerp(rgb(120, 104, 84), Kit.hash(seed) * 0.6)
	for _, z in { -1.95, 0, 1.95 } do
		Kit.detail(
			Kit.block(parent, Vector3.new(4, 0.55, 0.5), cf * CFrame.new(0, 0.28, z), wood, Enum.Material.WoodPlanks)
		)
	end
	return Kit.block(
		parent,
		Vector3.new(4, 0.28, 4.4),
		cf * CFrame.new(0, 0.69, 0),
		wood,
		Enum.Material.WoodPlanks,
		"Pallet"
	)
end

-- A few pallets stacked unevenly, sometimes with boxes on top.
function Props.palletStack(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("Pallets", parent)
	local count = 1 + math.floor(Kit.hash(seed) * 4)
	for i = 0, count - 1 do
		local layer = Kit.settle(cf * CFrame.new((Kit.hash(seed + i) - 0.5) * 0.6, i * 0.83, 0), seed + i * 3, 6, 0)
		Props.pallet(m, layer, seed + i)
	end
	if chance(seed + 9, 0.5) then
		Props.box(m, cf * CFrame.new(-0.6, count * 0.83, 0.4), seed + 13)
	end
	return m
end

-- Cardboard box, taped shut.
function Props.box(parent: Instance, cf: CFrame, seed: number, size: Vector3?): BasePart
	local s = size or Vector3.new(between(seed, 1.6, 2.8), between(seed + 1, 1.2, 2.2), between(seed + 2, 1.6, 2.6))
	local at = Kit.settle(cf, seed, 20, 0) * CFrame.new(0, s.Y / 2, 0)
	local box = Kit.block(parent, s, at, rgb(168, 134, 94), Enum.Material.Cardboard, "Box")
	Kit.detail(
		Kit.block(
			parent,
			Vector3.new(0.45, 0.04, s.Z + 0.02),
			at * CFrame.new(0, s.Y / 2, 0),
			rgb(196, 170, 120),
			Enum.Material.SmoothPlastic
		)
	)
	return box
end

-- Street furniture -----------------------------------------------------------------------------

-- Traffic cone; sometimes knocked over.
function Props.cone(parent: Instance, position: Vector3, seed: number): Model
	local m = Kit.model("Cone", parent)
	local base = CFrame.new(position) * CFrame.Angles(0, Kit.hash(seed) * 6.28, 0)
	if chance(seed + 1, 0.15) then
		base = base * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, -1.1, 0)
	end
	local orange = rgb(214, 96, 40)
	Kit.block(m, Vector3.new(1.5, 0.2, 1.5), base * CFrame.new(0, 0.1, 0), rgb(30, 30, 30), Enum.Material.Rubber)
	Kit.cyl(m, 0.8, 1.1, base * CFrame.new(0, 0.6, 0), orange, Enum.Material.Plastic)
	Kit.detail(Kit.cyl(m, 0.5, 0.82, base * CFrame.new(0, 1.25, 0), rgb(226, 226, 220), Enum.Material.SmoothPlastic))
	Kit.detail(Kit.cyl(m, 0.7, 0.5, base * CFrame.new(0, 1.85, 0), orange, Enum.Material.Plastic))
	return m
end

function Props.mailbox(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("Mailbox", parent)
	local base = Kit.settle(cf, seed, 10, 3)
	Kit.block(m, Vector3.new(0.45, 3.6, 0.45), base * CFrame.new(0, 1.8, 0), rgb(110, 90, 70), Enum.Material.Wood)
	local color = pick({ rgb(60, 62, 66), rgb(150, 50, 44), rgb(220, 218, 210), rgb(52, 76, 60) }, seed)
	Kit.detail(Kit.block(m, Vector3.new(1.2, 0.8, 2), base * CFrame.new(0, 3.9, 0), color, Enum.Material.Metal))
	Kit.detail(
		Kit.cyl(m, 2, 1.2, base * CFrame.new(0, 4.3, 0) * CFrame.Angles(math.rad(90), 0, 0), color, Enum.Material.Metal)
	)
	local flagUp = chance(seed + 5, 0.4)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(0.08, flagUp and 1.2 or 0.3, flagUp and 0.3 or 1.1),
			base * CFrame.new(0.65, flagUp and 4.6 or 4.1, 0.2),
			rgb(196, 44, 36),
			Enum.Material.SmoothPlastic
		)
	)
	return m
end

-- Wooden utility pole. Returns the attachments wires hang from (left, middle, right).
function Props.utilityPole(parent: Instance, cf: CFrame, seed: number, height: number?): (Model, { Attachment })
	local h = height or 24
	local m = Kit.model("UtilityPole", parent)
	local base = Kit.settle(cf, seed, 4, 1.2)
	local wood = rgb(98, 80, 64)
	Kit.cyl(m, h + 1, 0.95, base * CFrame.new(0, h / 2 - 0.5, 0), wood, Enum.Material.Wood, "Pole")
	local arm =
		Kit.block(m, Vector3.new(7.4, 0.5, 0.5), base * CFrame.new(0, h - 2.6, 0), wood, Enum.Material.Wood, "Crossarm")
	Kit.detail(arm)
	local attachments = {}
	for _, x in { -3.2, -1.1, 3.2 } do
		Kit.detail(
			Kit.cyl(m, 0.55, 0.4, base * CFrame.new(x, h - 2.1, 0), rgb(118, 132, 126), Enum.Material.SmoothPlastic)
		)
		local attachment = Instance.new("Attachment")
		-- X axis points down so the wire's curve sags.
		attachment.CFrame = CFrame.fromMatrix(Vector3.new(x, 0.6, 0), Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
		attachment.Parent = arm
		table.insert(attachments, attachment)
	end
	if chance(seed + 7, 0.3) then
		Kit.detail(Kit.cyl(m, 2.6, 1.7, base * CFrame.new(1.4, h - 6.5, 0), rgb(118, 120, 118), Enum.Material.Metal))
		Kit.detail(
			Kit.block(m, Vector3.new(0.9, 0.3, 0.3), base * CFrame.new(0.7, h - 5.4, 0), IRON, Enum.Material.Metal)
		)
	end
	return m, attachments
end

-- A drooping wire between two attachments.
function Props.wire(parent: Instance, a0: Attachment, a1: Attachment, sag: number, width: number?): Beam
	local beam = Instance.new("Beam")
	beam.Name = "Wire"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.CurveSize0 = sag
	beam.CurveSize1 = -sag
	beam.Width0 = width or 0.12
	beam.Width1 = width or 0.12
	beam.FaceCamera = true
	beam.Segments = 12
	beam.LightInfluence = 1
	beam.Color = ColorSequence.new(rgb(30, 30, 32))
	beam.Parent = parent
	return beam
end

-- Bus shelter facing the road along cf.LookVector.
function Props.busStop(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("BusStop", parent)
	local frame = rgb(70, 76, 84)
	for x = -1, 1, 2 do
		for _, z in { -1.5, 1.5 } do
			Kit.block(m, Vector3.new(0.3, 7, 0.3), cf * CFrame.new(x * 4.2, 3.5, z), frame, Enum.Material.Metal)
		end
	end
	Kit.block(m, Vector3.new(9.2, 0.35, 3.9), cf * CFrame.new(0, 7.15, 0), frame, Enum.Material.Metal, "Roof")
	local back = Kit.block(
		m,
		Vector3.new(8.2, 5.2, 0.15),
		cf * CFrame.new(0, 3.9, 1.5),
		rgb(190, 205, 210),
		Enum.Material.Glass,
		"Glass"
	)
	back.Transparency = 0.6
	local side = Kit.block(
		m,
		Vector3.new(0.15, 5.2, 2.8),
		cf * CFrame.new(-4.2, 3.9, 0),
		rgb(190, 205, 210),
		Enum.Material.Glass,
		"Glass"
	)
	side.Transparency = 0.6
	-- Ad panel on the side, bench inside
	local ad = Kit.block(
		m,
		Vector3.new(0.2, 4, 2.4),
		cf * CFrame.new(4.25, 3.9, 0.1),
		rgb(40, 44, 50),
		Enum.Material.SmoothPlastic
	)
	Kit.detail(ad)
	Kit.label(
		ad,
		pick({ "VISIT THE MUSEUM", "NEW DRIP AT THE MARKET", "SECURE YOUR LOOT", "DON'T GET BONKED" }, seed),
		{
			Face = Enum.NormalId.Left,
			TextColor = rgb(236, 230, 214),
			Background = rgb(120, 44, 40):Lerp(rgb(40, 70, 110), Kit.hash(seed + 3)),
			BackgroundTransparency = 0,
		}
	)
	Kit.bench(m, cf * CFrame.new(0, 0, 0.6) * CFrame.Angles(0, math.pi, 0))
	Kit.cyl(m, 9, 0.3, cf * CFrame.new(5.6, 4.5, -1.6), GALVANIZED, Enum.Material.Metal)
	local sign = Kit.block(
		m,
		Vector3.new(1.8, 1.8, 0.12),
		cf * CFrame.new(5.6, 8.2, -1.6),
		rgb(40, 90, 150),
		Enum.Material.SmoothPlastic
	)
	Kit.detail(sign)
	Kit.label(sign, "BUS", { TextColor = rgb(240, 240, 236) })
	Kit.label(sign, "BUS", { Face = Enum.NormalId.Back, TextColor = rgb(240, 240, 236) })
	return m
end

-- Square of soil set into the sidewalk with a street tree.
function Props.streetTree(parent: Instance, position: Vector3, seed: number, surfaceY: number)
	Kit.block(
		parent,
		Vector3.new(3.8, 0.12, 3.8),
		CFrame.new(position.X, surfaceY + 0.04, position.Z),
		rgb(150, 146, 140),
		Enum.Material.Concrete
	).CastShadow =
		false
	local soil = Kit.block(
		parent,
		Vector3.new(3, 0.14, 3),
		CFrame.new(position.X, surfaceY + 0.06, position.Z),
		rgb(72, 58, 46),
		Enum.Material.Ground
	)
	soil.CastShadow = false
	Kit.tree(
		parent,
		Vector3.new(position.X, surfaceY, position.Z),
		between(seed, 0.68, 0.86),
		pick({
			rgb(74, 112, 56),
			rgb(88, 122, 60),
			rgb(64, 104, 62),
		}, seed + 2)
	)
end

-- Wall-mounted details -------------------------------------------------------------------------
-- `face` is a frame on a wall surface whose LookVector points away from the wall.

function Props.downspout(parent: Instance, face: CFrame, x: number, height: number)
	local metal = rgb(118, 118, 112)
	Kit.detail(
		Kit.cyl(parent, height - 1, 0.45, face * CFrame.new(x, (height + 1) / 2, -0.3), metal, Enum.Material.Metal)
	)
	Kit.detail(
		Kit.block(parent, Vector3.new(0.5, 0.5, 1), face * CFrame.new(x, 0.75, -0.65), metal, Enum.Material.Metal)
	)
	Kit.detail(
		Kit.block(
			parent,
			Vector3.new(1.4, 0.4, 0.6),
			face * CFrame.new(x, height - 0.2, -0.35),
			metal,
			Enum.Material.Metal
		)
	)
end

function Props.windowAC(parent: Instance, face: CFrame, x: number, y: number, seed: number)
	local unit = face * CFrame.new(x, y, -0.9) * CFrame.Angles(0, 0, math.rad((Kit.hash(seed) - 0.5) * 3))
	Kit.detail(Kit.block(parent, Vector3.new(2.4, 1.5, 1.8), unit, rgb(206, 202, 190), Enum.Material.Metal))
	Kit.detail(
		Kit.block(
			parent,
			Vector3.new(2, 1.1, 0.06),
			unit * CFrame.new(0, 0, -0.92),
			rgb(90, 92, 94),
			Enum.Material.DiamondPlate
		)
	)
	-- Drip stain running down the wall below it
	Kit.detail(
		Kit.block(
			parent,
			Vector3.new(0.4, between(seed + 1, 2, 4), 0.04),
			face * CFrame.new(x + 0.6, y - 2.2, -0.03),
			rgb(70, 66, 60),
			Enum.Material.SmoothPlastic
		)
	)
end

function Props.electricBox(parent: Instance, face: CFrame, x: number, seed: number)
	local gray = rgb(150, 152, 148)
	Kit.detail(
		Kit.block(parent, Vector3.new(1.8, 2.6, 0.7), face * CFrame.new(x, 3.4, -0.35), gray, Enum.Material.Metal)
	)
	Kit.detail(Kit.cyl(parent, 5, 0.3, face * CFrame.new(x + 0.5, 7.2, -0.2), gray, Enum.Material.Metal))
	Kit.detail(
		Kit.cyl(
			parent,
			0.4,
			0.9,
			face * CFrame.new(x - 1.6, 4.2, -0.25) * CFrame.Angles(math.rad(90), 0, 0),
			rgb(196, 200, 196),
			Enum.Material.Glass
		)
	)
	if chance(seed, 0.5) then
		Kit.detail(Kit.cyl(parent, 3.2, 0.25, face * CFrame.new(x - 0.5, 0.4 + 1.6, -0.2), gray, Enum.Material.Metal))
	end
end

local POSTERS = {
	"LOST CAT",
	"BAND TONIGHT",
	"FOR RENT",
	"WANTED: ARTIFACT THIEF",
	"GRAND OPENING",
	"YARD SALE SAT",
	"MUSEUM GALA",
	"NO PARKING",
}
local POSTER_COLORS =
	{ rgb(214, 200, 160), rgb(186, 196, 200), rgb(200, 150, 120), rgb(220, 214, 196), rgb(150, 170, 140) }

-- Old flyer pasted on a wall: faded, slightly crooked, sometimes torn.
function Props.poster(parent: Instance, face: CFrame, x: number, y: number, seed: number)
	local w, h = between(seed, 1.8, 3), between(seed + 1, 2.4, 3.8)
	local tilt = math.rad((Kit.hash(seed + 2) - 0.5) * 7)
	local part = Kit.block(
		parent,
		Vector3.new(w, h, 0.05),
		face * CFrame.new(x, y, -0.04) * CFrame.Angles(0, 0, tilt),
		pick(POSTER_COLORS, seed + 3),
		Enum.Material.SmoothPlastic,
		"Poster"
	)
	Kit.detail(part)
	if chance(seed + 4, 0.55) then
		Kit.label(part, pick(POSTERS, seed + 5), {
			TextColor = rgb(50, 46, 42),
			Font = Enum.Font.Arial,
			Face = Enum.NormalId.Front,
			PixelsPerStud = 24,
		}).MaxDistance =
			80
	end
end

-- Road surface wear ----------------------------------------------------------------------------
-- `road` is the center of a road segment (top surface at y = top), LookVector along the road.

function Props.roadWear(parent: Instance, road: CFrame, length: number, width: number, top: number, seed: number)
	local asphalt = rgb(60, 61, 64)
	-- Repaired patches (lighter or darker than the old surface)
	for i = 1, 1 + math.floor(Kit.hash(seed) * 2) do
		local along = (Kit.hash(seed + i * 2.1) - 0.5) * (length - 8)
		local across = (Kit.hash(seed + i * 3.3) - 0.5) * (width - 6)
		local size = Vector3.new(between(seed + i, 3, 7), 0.04, between(seed + i * 1.7, 4, 10))
		local shade = chance(seed + i * 4.4, 0.5) and rgb(48, 49, 52) or rgb(74, 75, 77)
		local patch =
			Kit.block(parent, size, road * CFrame.new(across, top + 0.02, along), shade, Enum.Material.Asphalt)
		Kit.detail(patch)
	end
	-- Hairline cracks
	if chance(seed + 9, 0.6) then
		local at = road
			* CFrame.new(
				(Kit.hash(seed + 10) - 0.5) * (width - 4),
				top + 0.025,
				(Kit.hash(seed + 11) - 0.5) * (length - 6)
			)
		local heading = Kit.hash(seed + 12) * 6.28
		for j = 1, 3 do
			local seg = between(seed + j * 13, 1.5, 3.5)
			heading += (Kit.hash(seed + j * 17) - 0.5) * 1.6
			local piece = at * CFrame.Angles(0, heading, 0) * CFrame.new(0, 0, -seg / 2)
			local tip = road:PointToObjectSpace((piece * CFrame.new(0, 0, -seg / 2)).Position)
			if math.abs(tip.X) > width / 2 - 1 or math.abs(tip.Z) > length / 2 - 1 then
				break -- cracks stay on the asphalt
			end
			Kit.detail(
				Kit.block(parent, Vector3.new(0.14, 0.03, seg), piece, rgb(34, 34, 36), Enum.Material.SmoothPlastic)
			)
			at = piece * CFrame.new(0, 0, -seg / 2)
		end
	end
	-- Oil stain in a lane
	if chance(seed + 20, 0.45) then
		local stain = Kit.cyl(
			parent,
			0.03,
			between(seed + 21, 1.8, 3.4),
			road
				* CFrame.new(
					width * 0.25 * (chance(seed + 22, 0.5) and 1 or -1),
					top + 0.02,
					(Kit.hash(seed + 23) - 0.5) * length * 0.8
				),
			asphalt:Lerp(rgb(20, 20, 22), 0.55),
			Enum.Material.SmoothPlastic
		)
		Kit.detail(stain)
	end
	-- Manhole cover
	if chance(seed + 30, 0.35) then
		Kit.detail(
			Kit.cyl(
				parent,
				0.05,
				3.2,
				road * CFrame.new(width * 0.22, top + 0.02, (Kit.hash(seed + 31) - 0.5) * length * 0.7),
				rgb(64, 62, 60),
				Enum.Material.DiamondPlate
			)
		)
	end
end

-- Faded zebra crossing across a road (cf at the road center, LookVector along the road).
function Props.crosswalk(parent: Instance, cf: CFrame, width: number, top: number, seed: number)
	local stripes = math.floor((width - 2) / 2.4)
	for i = 0, stripes - 1 do
		if not chance(seed + i * 1.9, 0.08) then -- a worn-away stripe now and then
			local x = -width / 2 + 1.6 + i * 2.4
			local fade = Kit.hash(seed + i * 2.7) * 0.35
			Kit.detail(
				Kit.block(
					parent,
					Vector3.new(1.3, 0.04, 6),
					cf * CFrame.new(x, top + 0.02, 0),
					rgb(214, 214, 206):Lerp(rgb(110, 110, 110), fade),
					Enum.Material.SmoothPlastic
				)
			)
		end
	end
end

-- Yard and park ---------------------------------------------------------------------------------

function Props.bike(parent: Instance, cf: CFrame, seed: number, lying: boolean?): Model
	local m = Kit.model("Bike", parent)
	local frameColor = pick({ rgb(160, 40, 40), rgb(40, 90, 150), rgb(40, 40, 44), rgb(70, 130, 90) }, seed)
	local center = if lying
		then cf * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90))
		else cf * CFrame.new(0, 1.5, 0)
	for _, z in { -1.8, 1.8 } do
		Kit.detail(
			Kit.cyl(
				m,
				0.15,
				2.4,
				center * CFrame.new(0, -0.3, z) * CFrame.Angles(0, 0, math.rad(90)),
				RUBBER,
				Enum.Material.Rubber
			)
		)
	end
	Kit.detail(
		Kit.block(m, Vector3.new(0.15, 0.15, 2.8), center * CFrame.new(0, 0.6, 0), frameColor, Enum.Material.Metal)
	)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(0.15, 0.15, 2.3),
			center * CFrame.new(0, 0.1, -0.5) * CFrame.Angles(math.rad(-35), 0, 0),
			frameColor,
			Enum.Material.Metal
		)
	)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(0.5, 0.2, 0.9),
			center * CFrame.new(0, 1.2, 0.9),
			rgb(30, 30, 30),
			Enum.Material.Leather
		)
	)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(1.6, 0.15, 0.15),
			center * CFrame.new(0, 1.3, -1.6),
			rgb(40, 40, 40),
			Enum.Material.Metal
		)
	)
	return m
end

function Props.shed(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("Shed", parent)
	local wood = pick({ rgb(120, 96, 72), rgb(150, 132, 104), rgb(96, 108, 90), rgb(160, 150, 136) }, seed)
	Kit.block(m, Vector3.new(6, 6.4, 5), cf * CFrame.new(0, 3.2, 0), wood, Enum.Material.WoodPlanks, "Shed")
	Kit.gable(m, cf * CFrame.new(0, 7.6, 0), Vector3.new(6.8, 2.4, 5.8), rgb(70, 66, 62), Enum.Material.RoofShingles)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(2.4, 5, 0.12),
			cf * CFrame.new(0.8, 2.6, -2.53),
			wood:Lerp(rgb(0, 0, 0), 0.25),
			Enum.Material.Wood
		)
	)
	return m
end

function Props.doghouse(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("Doghouse", parent)
	local base = Kit.settle(cf, seed, 15, 0)
	local paint = pick({ rgb(170, 60, 50), rgb(200, 186, 150), rgb(90, 110, 140) }, seed)
	Kit.block(m, Vector3.new(3.2, 2.6, 3.6), base * CFrame.new(0, 1.3, 0), paint, Enum.Material.WoodPlanks, "Doghouse")
	Kit.gable(m, base * CFrame.new(0, 3.3, 0), Vector3.new(3.8, 1.4, 4.2), rgb(70, 64, 60), Enum.Material.RoofShingles)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(1.3, 1.7, 0.1),
			base * CFrame.new(0, 0.95, -1.81),
			rgb(24, 22, 20),
			Enum.Material.SmoothPlastic
		)
	)
	Kit.detail(Kit.cyl(m, 0.3, 1, base * CFrame.new(1.4, 0.15, -2.6), rgb(170, 60, 50), Enum.Material.Plastic))
	return m
end

function Props.grill(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("Grill", parent)
	local base = Kit.settle(cf, seed, 30, 0)
	for i = 0, 2 do
		local angle = i / 3 * math.pi * 2
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(0.15, 2.4, 0.15),
				base * CFrame.new(math.cos(angle) * 0.6, 1.2, math.sin(angle) * 0.6),
				IRON,
				Enum.Material.Metal
			)
		)
	end
	Kit.ball(m, 2, base * CFrame.new(0, 2.6, 0), rgb(30, 30, 32), Enum.Material.Metal).Name = "Grill"
	return m
end

function Props.flowerPot(parent: Instance, position: Vector3, seed: number): Model
	local m = Kit.model("FlowerPot", parent)
	local d = between(seed, 1.1, 1.8)
	Kit.cyl(m, d * 0.9, d, CFrame.new(position + Vector3.new(0, d * 0.45, 0)), rgb(166, 94, 66), Enum.Material.Ground)
	Kit.noCollide(
		Kit.ball(
			m,
			d * 1.15,
			CFrame.new(position + Vector3.new(0, d * 1.05, 0)),
			pick({ rgb(70, 110, 54), rgb(84, 118, 60), rgb(96, 112, 58) }, seed + 1),
			Enum.Material.LeafyGrass
		)
	)
	return m
end

function Props.swingSet(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("SwingSet", parent)
	local metal = pick({ rgb(60, 110, 150), rgb(170, 70, 50), rgb(90, 130, 80) }, seed)
	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			Kit.block(
				m,
				Vector3.new(0.3, 8.6, 0.3),
				cf * CFrame.new(x * 4.4, 4.1, z * 1.1) * CFrame.Angles(math.rad(z * 14), 0, 0),
				metal,
				Enum.Material.Metal
			)
		end
	end
	Kit.cyl(m, 9.2, 0.35, cf * CFrame.new(0, 8.2, 0) * CFrame.Angles(0, 0, math.rad(90)), metal, Enum.Material.Metal)
	for i, x in { -1.8, 1.8 } do
		local swing = math.rad((Kit.hash(seed + i) - 0.5) * 16)
		local pivot = cf * CFrame.new(x, 8.1, 0) * CFrame.Angles(swing, 0, 0)
		for side = -1, 1, 2 do
			Kit.detail(
				Kit.block(
					m,
					Vector3.new(0.08, 5.8, 0.08),
					pivot * CFrame.new(side * 0.8, -2.9, 0),
					rgb(120, 120, 116),
					Enum.Material.Metal
				)
			)
		end
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(1.9, 0.2, 0.8),
				pivot * CFrame.new(0, -5.8, 0),
				rgb(40, 40, 40),
				Enum.Material.Rubber
			)
		)
	end
	return m
end

-- Construction ----------------------------------------------------------------------------------

-- Scaffolding against a wall (face LookVector points away from the wall).
function Props.scaffold(parent: Instance, face: CFrame, width: number, height: number)
	local m = Kit.model("Scaffold", parent)
	local tube = rgb(150, 150, 146)
	local columns = math.max(2, math.floor(width / 6) + 1)
	local levels = math.max(1, math.floor(height / 6.5))
	for i = 0, columns - 1 do
		local x = -width / 2 + width * i / (columns - 1)
		for _, z in { -0.8, -4 } do
			Kit.block(m, Vector3.new(0.3, height, 0.3), face * CFrame.new(x, height / 2, z), tube, Enum.Material.Metal)
		end
	end
	for level = 1, levels do
		local y = level * 6.5
		Kit.block(
			m,
			Vector3.new(width, 0.25, 3),
			face * CFrame.new(0, y, -2.4),
			rgb(150, 120, 80),
			Enum.Material.WoodPlanks,
			"Plank"
		)
		Kit.detail(
			Kit.block(m, Vector3.new(width, 0.2, 0.2), face * CFrame.new(0, y + 3, -4), tube, Enum.Material.Metal)
		)
	end
	return m
end

-- Tower crane: lattice mast, jib with trolley and hook, counterweights and a cab.
function Props.crane(parent: Instance, cf: CFrame, seed: number, height: number): Model
	local m = Kit.model("TowerCrane", parent)
	local yellow = rgb(206, 164, 50)
	Kit.block(m, Vector3.new(8, 1.5, 8), cf * CFrame.new(0, 0.75, 0), rgb(150, 148, 142), Enum.Material.Concrete)
	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			local mast = Instance.new("TrussPart")
			mast.Size = Vector3.new(2, math.floor(height / 2) * 2, 2)
			mast.CFrame = cf * CFrame.new(x * 1.5, 1.5 + mast.Size.Y / 2, z * 1.5)
			mast.Anchored = true
			mast.Color = yellow
			mast.Material = Enum.Material.Metal
			mast.Parent = m
		end
	end
	local top = cf * CFrame.new(0, height + 1.5, 0) * CFrame.Angles(0, Kit.hash(seed) * 6.28, 0)
	Kit.block(m, Vector3.new(4.5, 1.6, 54), top * CFrame.new(0, 0.8, -18), yellow, Enum.Material.Metal, "Jib")
	Kit.block(m, Vector3.new(4, 4, 4), top * CFrame.new(2.6, -1.4, 0), rgb(220, 218, 210), Enum.Material.Metal, "Cab")
	Kit.detail(
		Kit.block(m, Vector3.new(3.4, 2, 0.1), top * CFrame.new(2.6, -1, -2.02), rgb(60, 80, 90), Enum.Material.Glass)
	)
	for i = 0, 1 do
		Kit.block(
			m,
			Vector3.new(4, 2.6, 2.4),
			top * CFrame.new(0, -0.6, 7 + i * 2.6),
			rgb(140, 138, 132),
			Enum.Material.Concrete,
			"Counterweight"
		)
	end
	Kit.wedge(
		m,
		Vector3.new(1.2, 6, 4),
		top * CFrame.new(0, 4.6, -2) * CFrame.Angles(0, math.pi, 0),
		yellow,
		Enum.Material.Metal
	)
	local trolley = between(seed + 2, 16, 36)
	local hookY = between(seed + 3, 18, height - 12)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(0.12, hookY, 0.12),
			top * CFrame.new(0, -hookY / 2, -trolley),
			rgb(40, 40, 40),
			Enum.Material.Metal
		)
	)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(1.2, 1.6, 1.2),
			top * CFrame.new(0, -hookY - 0.8, -trolley),
			rgb(200, 150, 40),
			Enum.Material.Metal
		)
	)
	return m
end

function Props.portaPotty(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("PortaPotty", parent)
	local base = Kit.settle(cf, seed, 8, 0)
	local color = pick({ rgb(52, 92, 140), rgb(60, 120, 80), rgb(150, 120, 60) }, seed)
	Kit.block(m, Vector3.new(3.8, 7.4, 3.8), base * CFrame.new(0, 3.7, 0), color, Enum.Material.Plastic, "Toilet")
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(4.1, 0.4, 4.1),
			base * CFrame.new(0, 7.55, 0),
			rgb(230, 230, 226),
			Enum.Material.Plastic
		)
	)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(0.12, 6.6, 0.12),
			base * CFrame.new(0, 3.5, -1.92),
			color:Lerp(rgb(0, 0, 0), 0.3),
			Enum.Material.Plastic
		)
	)
	return m
end

-- Concrete jersey barrier.
function Props.barrier(parent: Instance, cf: CFrame, seed: number): Model
	local m = Kit.model("Barrier", parent)
	local base = Kit.settle(cf, seed, 5, 0)
	local concrete = rgb(176, 172, 164)
	Kit.block(m, Vector3.new(8, 1.4, 2.4), base * CFrame.new(0, 0.7, 0), concrete, Enum.Material.Concrete, "Barrier")
	Kit.block(m, Vector3.new(8, 1.6, 1), base * CFrame.new(0, 2.2, 0), concrete, Enum.Material.Concrete)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(8.02, 0.4, 1.02),
			base * CFrame.new(0, 2.6, 0),
			rgb(200, 150, 50),
			Enum.Material.SmoothPlastic
		)
	)
	return m
end

function Props.tireStack(parent: Instance, position: Vector3, seed: number): Model
	local m = Kit.model("Tires", parent)
	local count = 2 + math.floor(Kit.hash(seed) * 3)
	for i = 0, count - 1 do
		local offset =
			Vector3.new((Kit.hash(seed + i) - 0.5) * 0.6, 0.45 + i * 0.9, (Kit.hash(seed + i * 2) - 0.5) * 0.6)
		Kit.cyl(m, 0.9, 3, CFrame.new(position + offset), RUBBER, Enum.Material.Rubber, "Tire")
	end
	return m
end

-- Two parallel skid marks curving across the ground (cf at the start, heading along LookVector).
function Props.tireMarks(parent: Instance, cf: CFrame, seed: number, surfaceY: number)
	local turn = (Kit.hash(seed) - 0.5) * 0.5
	for side = -1, 1, 2 do
		local at = cf * CFrame.new(side * 2.6, 0, 0)
		for _ = 1, 6 do
			at = at * CFrame.Angles(0, turn, 0)
			local piece = at * CFrame.new(0, 0, -1.6)
			local p = piece.Position
			Kit.detail(
				Kit.block(
					parent,
					Vector3.new(0.8, 0.03, 3.3),
					CFrame.new(p.X, surfaceY + 0.02, p.Z) * (piece - piece.Position),
					rgb(36, 36, 38),
					Enum.Material.SmoothPlastic
				)
			)
			at = piece * CFrame.new(0, 0, -1.6)
		end
	end
end

-- Yellow caution tape strung in an X across an opening (face on the opening, LookVector out).
function Props.cautionTape(parent: Instance, face: CFrame, width: number, height: number)
	local length = math.sqrt(width * width + height * height)
	local angle = math.atan2(height, width)
	for side = -1, 1, 2 do
		Kit.detail(
			Kit.block(
				parent,
				Vector3.new(length, 0.35, 0.05),
				face * CFrame.new(0, height / 2, -0.1) * CFrame.Angles(0, 0, side * angle),
				rgb(232, 196, 40),
				Enum.Material.SmoothPlastic
			)
		)
	end
end

return Props
