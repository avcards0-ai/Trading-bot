--[[
	Kit
	Building blocks for the procedural map: primitives, signs, lights, props and the
	security devices (lasers / cameras / traps) whose definitions the SecurityService reads.
]]

local CollectionService = game:GetService("CollectionService")

local Kit = {}

local rgb = Color3.fromRGB
Kit.rgb = rgb
local C_WHITE = Color3.fromRGB(250, 248, 244)

Kit.Colors = {
	Grass = rgb(98, 176, 82),
	Path = rgb(214, 196, 160),
	Asphalt = rgb(58, 60, 68),
	Line = rgb(255, 214, 70),
	Concrete = rgb(170, 172, 180),
	DarkConcrete = rgb(110, 112, 122),
	Marble = rgb(236, 232, 222),
	Wood = rgb(150, 100, 60),
	DarkWood = rgb(95, 62, 40),
	Gold = rgb(255, 196, 60),
	Red = rgb(225, 60, 60),
	Blue = rgb(60, 130, 230),
	Green = rgb(80, 200, 110),
	Purple = rgb(150, 90, 230),
	Orange = rgb(255, 150, 50),
	Pink = rgb(255, 130, 190),
	Teal = rgb(60, 200, 200),
	White = rgb(245, 245, 248),
	Black = rgb(25, 25, 30),
	Metal = rgb(140, 145, 155),
	Toxic = rgb(120, 255, 90),
	Sand = rgb(220, 190, 130),
	Stone = rgb(150, 140, 125),
	Laser = rgb(255, 40, 40),
}

export type LaserDef = {
	Part: BasePart,
	BaseCFrame: CFrame,
	Pattern: string,
	Speed: number,
	Phase: number,
	Amplitude: number,
	Axis: Vector3, -- world-space sweep direction
	Owner: string, -- "Zone:<id>" or "Plot:<index>"
}

export type CameraDef = {
	Model: Model,
	Head: BasePart,
	Position: Vector3,
	BaseYaw: number,
	Sweep: number,
	Speed: number,
	Phase: number,
	Pitch: number,
	Range: number,
	Fov: number,
	Owner: string,
}

export type TrapDef = {
	Part: BasePart,
	Kind: string, -- Banana / Spring / Glue / Spike / Toxic
	Position: Vector3,
	Radius: number,
	Owner: string,
	ReadyAt: number,
}

-- Primitives ---------------------------------------------------------------------------

local function applyDefaults(p: BasePart, color: Color3, material: Enum.Material?)
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

function Kit.block(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	name: string?
): Part
	local p = Instance.new("Part")
	p.Name = name or "Part"
	p.Size = size
	p.CFrame = cf
	applyDefaults(p, color, material)
	p.Parent = parent
	return p
end

-- Vertical cylinder centered on cf.
function Kit.cyl(
	parent: Instance,
	height: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	name: string?
): Part
	local p = Instance.new("Part")
	p.Name = name or "Cylinder"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	applyDefaults(p, color, material)
	p.Parent = parent
	return p
end

function Kit.ball(parent: Instance, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = "Ball"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * diameter
	p.CFrame = cf
	applyDefaults(p, color, material)
	p.Parent = parent
	return p
end

function Kit.wedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): WedgePart
	local p = Instance.new("WedgePart")
	p.Size = size
	p.CFrame = cf
	applyDefaults(p, color, material)
	p.Parent = parent
	return p
end

function Kit.folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Kit.model(name: string, parent: Instance, streaming: Enum.ModelStreamingMode?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = streaming or Enum.ModelStreamingMode.Default
	m.Parent = parent
	return m
end

-- Invisible, non-colliding helper part.
function Kit.ghost(parent: Instance, size: Vector3, cf: CFrame, name: string?): Part
	local p = Kit.block(parent, size, cf, Kit.Colors.White, Enum.Material.SmoothPlastic, name)
	p.Transparency = 1
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

function Kit.noCollide(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	return p
end

-- Lights / text ------------------------------------------------------------------------

function Kit.light(part: BasePart, color: Color3, brightness: number, range: number, kind: string?): Light
	local light: Light
	if kind == "Spot" then
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 70
		light = spot
	else
		light = Instance.new("PointLight")
	end
	light.Color = color
	light.Brightness = brightness;
	(light :: any).Range = range
	light.Shadows = false
	light.Parent = part
	return light
end

export type LabelOptions = {
	Face: Enum.NormalId?,
	TextColor: Color3?,
	Font: Enum.Font?,
	Stroke: Color3?,
	Background: Color3?,
	BackgroundTransparency: number?,
	PixelsPerStud: number?,
	LightInfluence: number?,
	Name: string?,
}

function Kit.label(part: BasePart, text: string, options: LabelOptions?): (SurfaceGui, TextLabel)
	local opts = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = opts.Name or "Label"
	gui.Face = opts.Face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PixelsPerStud or 30
	gui.LightInfluence = opts.LightInfluence or 0
	gui.MaxDistance = 260
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = opts.Background or Kit.Colors.Black
	label.BackgroundTransparency = opts.BackgroundTransparency or 1
	label.Font = opts.Font or Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = opts.TextColor or Kit.Colors.White
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label

	if opts.Stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = opts.Stroke
		stroke.Thickness = 3
		stroke.Parent = label
	end
	return gui, label
end

-- A free-standing sign board with text on its front face.
function Kit.sign(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	text: string,
	board: Color3,
	textColor: Color3?,
	options: LabelOptions?
): Part
	local p = Kit.block(parent, size, cf, board, Enum.Material.SmoothPlastic, "Sign")
	local opts = options or {}
	opts.TextColor = textColor or opts.TextColor
	opts.Stroke = opts.Stroke or Kit.Colors.Black
	Kit.label(p, text, opts)
	return p
end

-- Interaction prompt that the client turns into a UI shortcut (see InteractController).
function Kit.uiPrompt(
	part: BasePart,
	action: string,
	object: string,
	uiName: string,
	key: Enum.KeyCode?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = key or Enum.KeyCode.E
	prompt:SetAttribute("OpensUI", uiName)
	prompt.Parent = part
	return prompt
end

-- Props --------------------------------------------------------------------------------

-- Leafy tree: trunk, two branches and a lumpy canopy. Same position -> same tree.
function Kit.tree(parent: Instance, position: Vector3, scale: number?, leafColor: Color3?)
	local s = scale or 1
	local rng = Random.new(math.floor(position.X * 7.3 + position.Z * 13.1) % 100000)
	local m = Kit.model("Tree", parent)
	local bark = rgb(104, 74, 52)
	Kit.cyl(m, 9 * s, 1.7 * s, CFrame.new(position + Vector3.new(0, 4.5 * s, 0)), bark, Enum.Material.Wood, "Trunk")
	for side = -1, 1, 2 do
		local branch = Kit.cyl(
			m,
			4.5 * s,
			0.8 * s,
			CFrame.new(position + Vector3.new(side * 1.3 * s, 8.6 * s, 0))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
				* CFrame.Angles(0, 0, math.rad(side * 38)),
			bark,
			Enum.Material.Wood
		)
		Kit.noCollide(branch)
	end
	local leaves = leafColor or rgb(78, 150, 62)
	local blobs = {
		{ 0, 13, 0, 10.5 },
		{ 3.4, 11.4, 1.6, 7.5 },
		{ -3.2, 11.8, -1.4, 7.2 },
		{ 0.8, 15.6, -1.8, 6.4 },
		{ -1.4, 11, 3, 6.6 },
	}
	for i, blob in blobs do
		local shade =
			leaves:Lerp(i % 2 == 0 and Color3.new(0, 0, 0) or Color3.new(1, 1, 0.8), rng:NextNumber(0.02, 0.12))
		local ball = Kit.ball(
			m,
			blob[4] * s,
			CFrame.new(position + Vector3.new(blob[1], blob[2], blob[3]) * s),
			shade,
			Enum.Material.LeafyGrass
		)
		ball.Name = "Leaves"
		if i > 1 then
			Kit.noCollide(ball)
		end
	end
	return m
end

-- Evergreen: a trunk and three crossed tiers.
function Kit.pine(parent: Instance, position: Vector3, scale: number?, color: Color3?)
	local s = scale or 1
	local m = Kit.model("Pine", parent)
	Kit.cyl(m, 7 * s, 1.3 * s, CFrame.new(position + Vector3.new(0, 3.5 * s, 0)), rgb(92, 64, 46), Enum.Material.Wood)
	local green = color or rgb(52, 112, 70)
	local yaw = (position.X * 0.37 + position.Z * 0.11) % 1.57
	for tier = 0, 2 do
		local width = (12 - tier * 3.2) * s
		local height = (7.5 - tier * 1.2) * s
		local base = CFrame.new(position + Vector3.new(0, (4 + tier * 4.6) * s + height / 2, 0))
			* CFrame.Angles(0, yaw, 0)
		local shade = green:Lerp(Color3.new(1, 1, 1), tier * 0.04)
		for _, part in Kit.gable(m, base, Vector3.new(width * 0.72, height, width), shade, Enum.Material.LeafyGrass) do
			Kit.noCollide(part)
		end
		for _, part in
			Kit.gable(
				m,
				base * CFrame.Angles(0, math.rad(90), 0),
				Vector3.new(width * 0.72, height, width),
				shade:Lerp(Color3.new(0, 0, 0), 0.06),
				Enum.Material.LeafyGrass
			)
		do
			Kit.noCollide(part)
		end
	end
	return m
end

-- Round shrub.
function Kit.bush(parent: Instance, position: Vector3, scale: number?, color: Color3?)
	local s = scale or 1
	local green = color or rgb(74, 140, 60)
	local m = Kit.model("Bush", parent)
	Kit.ball(m, 4.6 * s, CFrame.new(position + Vector3.new(0, 1.4 * s, 0)), green, Enum.Material.LeafyGrass)
	Kit.noCollide(
		Kit.ball(
			m,
			3.4 * s,
			CFrame.new(position + Vector3.new(1.9 * s, 1 * s, 0.6 * s)),
			green:Lerp(Color3.new(0, 0, 0), 0.08),
			Enum.Material.LeafyGrass
		)
	)
	Kit.noCollide(
		Kit.ball(
			m,
			3 * s,
			CFrame.new(position + Vector3.new(-1.6 * s, 0.9 * s, -0.9 * s)),
			green:Lerp(Color3.new(1, 1, 1), 0.06),
			Enum.Material.LeafyGrass
		)
	)
	return m
end

function Kit.palm(parent: Instance, position: Vector3, scale: number?)
	local s = scale or 1
	local m = Kit.model("Palm", parent)
	for i = 0, 4 do
		Kit.cyl(
			m,
			3.2 * s,
			(1.5 - i * 0.1) * s,
			CFrame.new(position + Vector3.new(i * 0.35 * s, (1.6 + i * 3) * s, 0)) * CFrame.Angles(0, 0, math.rad(-6)),
			rgb(150, 110, 70),
			Enum.Material.Wood
		)
	end
	local top = position + Vector3.new(1.8 * s, 15.5 * s, 0)
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local cf = CFrame.new(top)
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, -0.8 * s, -3.5 * s)
			* CFrame.Angles(math.rad(-25), 0, 0)
		Kit.block(m, Vector3.new(1.6 * s, 0.3 * s, 7 * s), cf, rgb(60, 170, 70), Enum.Material.Grass)
	end
	return m
end

-- Park lamp: post, collar and a glowing lantern.
function Kit.lamp(parent: Instance, position: Vector3, color: Color3?, height: number?)
	local h = height or 12
	local glow = color or rgb(255, 228, 170)
	local m = Kit.model("Lamp", parent)
	local iron = rgb(38, 40, 46)
	Kit.cyl(m, 1.2, 1.4, CFrame.new(position + Vector3.new(0, 0.6, 0)), iron, Enum.Material.Metal)
	Kit.cyl(m, h, 0.55, CFrame.new(position + Vector3.new(0, h / 2, 0)), iron, Enum.Material.Metal)
	Kit.noCollide(
		Kit.block(m, Vector3.new(1.5, 0.3, 1.5), CFrame.new(position + Vector3.new(0, h, 0)), iron, Enum.Material.Metal)
	)
	local bulb = Kit.block(
		m,
		Vector3.new(1.1, 1.4, 1.1),
		CFrame.new(position + Vector3.new(0, h + 0.85, 0)),
		glow,
		Enum.Material.Neon,
		"Bulb"
	)
	bulb.CastShadow = false
	Kit.noCollide(bulb)
	Kit.noCollide(
		Kit.wedge(
			m,
			Vector3.new(1.6, 0.6, 0.8),
			CFrame.new(position + Vector3.new(0, h + 1.85, -0.4)),
			iron,
			Enum.Material.Metal
		)
	)
	Kit.noCollide(
		Kit.wedge(
			m,
			Vector3.new(1.6, 0.6, 0.8),
			CFrame.new(position + Vector3.new(0, h + 1.85, 0.4)) * CFrame.Angles(0, math.pi, 0),
			iron,
			Enum.Material.Metal
		)
	)
	Kit.light(bulb, glow, 1.4, 20)
	return m
end

-- Street light: base at cf, arm reaching over the road along cf.LookVector.
function Kit.streetLamp(parent: Instance, cf: CFrame, height: number?)
	local h = height or 15
	local m = Kit.model("StreetLamp", parent)
	local pole = rgb(70, 74, 82)
	Kit.block(m, Vector3.new(1.4, 1, 1.4), cf * CFrame.new(0, 0.5, 0), pole, Enum.Material.Metal)
	Kit.cyl(m, h, 0.6, cf * CFrame.new(0, h / 2, 0), pole, Enum.Material.Metal)
	Kit.noCollide(Kit.block(m, Vector3.new(0.4, 0.4, 4.2), cf * CFrame.new(0, h - 0.2, -2), pole, Enum.Material.Metal))
	local head = Kit.block(
		m,
		Vector3.new(1.4, 0.6, 2.4),
		cf * CFrame.new(0, h - 0.4, -4.2),
		pole,
		Enum.Material.Metal,
		"LampHead"
	)
	Kit.noCollide(head)
	local bulb = Kit.block(
		m,
		Vector3.new(1, 0.12, 1.8),
		cf * CFrame.new(0, h - 0.75, -4.2),
		rgb(255, 236, 190),
		Enum.Material.Neon
	)
	bulb.CastShadow = false
	Kit.noCollide(bulb)
	Kit.light(bulb, rgb(255, 226, 170), 1.2, 26, "Spot")
	return m
end

function Kit.bench(parent: Instance, cf: CFrame)
	local m = Kit.model("Bench", parent)
	Kit.block(m, Vector3.new(6, 0.4, 1.8), cf * CFrame.new(0, 1.6, 0), Kit.Colors.Wood, Enum.Material.Wood)
	Kit.block(m, Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 2.6, 0.8), Kit.Colors.Wood, Enum.Material.Wood)
	Kit.block(m, Vector3.new(0.3, 1.6, 1.6), cf * CFrame.new(-2.6, 0.8, 0), Kit.Colors.Black, Enum.Material.Metal)
	Kit.block(m, Vector3.new(0.3, 1.6, 1.6), cf * CFrame.new(2.6, 0.8, 0), Kit.Colors.Black, Enum.Material.Metal)
	return m
end

function Kit.crate(parent: Instance, cf: CFrame, size: number?, color: Color3?)
	local s = size or 4
	local c = color or rgb(170, 125, 75)
	local p = Kit.block(parent, Vector3.one * s, cf, c, Enum.Material.WoodPlanks, "Crate")
	local trim = c:Lerp(Color3.new(0, 0, 0), 0.3)
	Kit.block(parent, Vector3.new(s + 0.1, 0.3, s + 0.1), cf * CFrame.new(0, s / 2 - 0.15, 0), trim, Enum.Material.Wood)
	Kit.block(
		parent,
		Vector3.new(s + 0.1, 0.3, s + 0.1),
		cf * CFrame.new(0, -s / 2 + 0.15, 0),
		trim,
		Enum.Material.Wood
	)
	return p
end

function Kit.barrel(parent: Instance, cf: CFrame, color: Color3?, glow: boolean?)
	local p = Kit.cyl(parent, 3.6, 2.6, cf, color or rgb(60, 110, 60), Enum.Material.Metal, "Barrel")
	Kit.cyl(parent, 0.2, 2.7, cf * CFrame.new(0, 1, 0), Kit.Colors.Black, Enum.Material.Metal)
	Kit.cyl(parent, 0.2, 2.7, cf * CFrame.new(0, -1, 0), Kit.Colors.Black, Enum.Material.Metal)
	if glow then
		local top = Kit.cyl(parent, 0.1, 2.2, cf * CFrame.new(0, 1.82, 0), Kit.Colors.Toxic, Enum.Material.Neon)
		Kit.light(top, Kit.Colors.Toxic, 1.2, 10)
	end
	return p
end

function Kit.pillar(
	parent: Instance,
	base: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
)
	Kit.block(
		parent,
		Vector3.new(diameter + 1.2, 1, diameter + 1.2),
		CFrame.new(base + Vector3.new(0, 0.5, 0)),
		color,
		material
	)
	Kit.cyl(parent, height - 2, diameter, CFrame.new(base + Vector3.new(0, height / 2, 0)), color, material)
	Kit.block(
		parent,
		Vector3.new(diameter + 1.2, 1, diameter + 1.2),
		CFrame.new(base + Vector3.new(0, height - 0.5, 0)),
		color,
		material
	)
end

-- Climbable truss ladder standing on `base` (height is rounded to a multiple of 2).
function Kit.truss(parent: Instance, base: CFrame, height: number, color: Color3?): TrussPart
	local h = math.max(2, math.floor(height / 2 + 0.5) * 2)
	local truss = Instance.new("TrussPart")
	truss.Size = Vector3.new(2, h, 2)
	truss.CFrame = base * CFrame.new(0, h / 2, 0)
	truss.Anchored = true
	truss.Color = color or Kit.Colors.Metal
	truss.Material = Enum.Material.Metal
	truss.Parent = parent
	return truss
end

-- Pedestal; returns the CFrame an artifact should float at (plus the glow strip and top).
function Kit.pedestal(parent: Instance, cf: CFrame, color: Color3?, glow: Color3?): (CFrame, BasePart?, BasePart)
	local c = color or Kit.Colors.Marble
	Kit.block(
		parent,
		Vector3.new(3.4, 0.5, 3.4),
		cf * CFrame.new(0, 0.25, 0),
		c:Lerp(Color3.new(0, 0, 0), 0.15),
		Enum.Material.Marble,
		"PedestalBase"
	)
	Kit.block(parent, Vector3.new(2.6, 3, 2.6), cf * CFrame.new(0, 2, 0), c, Enum.Material.Marble, "Pedestal")
	local top = Kit.block(
		parent,
		Vector3.new(3.2, 0.35, 3.2),
		cf * CFrame.new(0, 3.65, 0),
		c:Lerp(Color3.new(0, 0, 0), 0.15),
		Enum.Material.Marble,
		"PedestalTop"
	)
	local strip: BasePart? = nil
	if glow then
		local glowPart = Kit.block(
			parent,
			Vector3.new(2.7, 0.15, 2.7),
			cf * CFrame.new(0, 3.88, 0),
			glow,
			Enum.Material.Neon,
			"Glow"
		)
		glowPart.CastShadow = false
		Kit.noCollide(glowPart)
		strip = glowPart
	end
	return top.CFrame * CFrame.new(0, 2.1, 0), strip, top
end

-- Glass display case on a pedestal; returns artifact CFrame.
function Kit.displayCase(parent: Instance, cf: CFrame, color: Color3?): CFrame
	local spot = Kit.pedestal(parent, cf, color, Kit.Colors.Gold)
	local glass = Kit.block(
		parent,
		Vector3.new(0.2, 3.6, 3.0),
		cf * CFrame.new(1.5, 5.8, 0),
		rgb(200, 230, 255),
		Enum.Material.Glass,
		"Glass"
	)
	glass.Transparency = 0.75
	Kit.noCollide(glass)
	local glass2 = Kit.block(
		parent,
		Vector3.new(0.2, 3.6, 3.0),
		cf * CFrame.new(-1.5, 5.8, 0),
		rgb(200, 230, 255),
		Enum.Material.Glass,
		"Glass"
	)
	glass2.Transparency = 0.75
	Kit.noCollide(glass2)
	return spot
end

-- Stairs climbing along cf.LookVector.
function Kit.stairs(
	parent: Instance,
	cf: CFrame,
	steps: number,
	width: number,
	rise: number,
	run: number,
	color: Color3,
	material: Enum.Material?
)
	for i = 0, steps - 1 do
		Kit.block(
			parent,
			Vector3.new(width, rise * (i + 1), run),
			cf * CFrame.new(0, rise * (i + 1) / 2, -run * i - run / 2),
			color,
			material,
			"Step"
		)
	end
end

-- Four walls with optional door gaps. `doors` maps "Front"/"Back"/"Left"/"Right" to a gap width.
function Kit.room(
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	doors: { [string]: number }?,
	doorHeight: number?
)
	local gaps = doors or {}
	local dh = math.min(doorHeight or 12, size.Y)
	local walls = {}
	local function wall(name: string, length: number, center: CFrame, gap: number?)
		if gap and gap > 0 then
			local side = (length - gap) / 2
			table.insert(
				walls,
				Kit.block(
					parent,
					Vector3.new(side, size.Y, thickness),
					center * CFrame.new(-(gap / 2 + side / 2), 0, 0),
					color,
					material,
					name
				)
			)
			table.insert(
				walls,
				Kit.block(
					parent,
					Vector3.new(side, size.Y, thickness),
					center * CFrame.new(gap / 2 + side / 2, 0, 0),
					color,
					material,
					name
				)
			)
			if size.Y > dh then
				table.insert(
					walls,
					Kit.block(
						parent,
						Vector3.new(gap, size.Y - dh, thickness),
						center * CFrame.new(0, dh / 2, 0),
						color,
						material,
						name
					)
				)
			end
		else
			table.insert(
				walls,
				Kit.block(parent, Vector3.new(length, size.Y, thickness), center, color, material, name)
			)
		end
	end
	local y = size.Y / 2
	wall("WallFront", size.X, cf * CFrame.new(0, y, -size.Z / 2), gaps.Front)
	wall("WallBack", size.X, cf * CFrame.new(0, y, size.Z / 2), gaps.Back)
	wall("WallLeft", size.Z, cf * CFrame.new(-size.X / 2, y, 0) * CFrame.Angles(0, math.rad(90), 0), gaps.Left)
	wall("WallRight", size.Z, cf * CFrame.new(size.X / 2, y, 0) * CFrame.Angles(0, math.rad(90), 0), gaps.Right)
	return walls
end

-- Security devices ---------------------------------------------------------------------

-- A laser beam centered at `cf` spanning `length` along cf.RightVector, sweeping along `axis`.
function Kit.laser(
	parent: Instance,
	cf: CFrame,
	length: number,
	pattern: string,
	speed: number,
	phase: number,
	amplitude: number,
	axis: Vector3,
	owner: string,
	color: Color3?
): LaserDef
	local beam = Instance.new("Part")
	beam.Name = "Laser"
	beam.Size = Vector3.new(length, 0.22, 0.22)
	beam.CFrame = cf
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CanQuery = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color or Kit.Colors.Laser
	beam:SetAttribute("Pattern", pattern)
	beam:SetAttribute("Speed", speed)
	beam:SetAttribute("Phase", phase)
	beam:SetAttribute("Amplitude", amplitude)
	beam:SetAttribute("Axis", axis)
	beam:SetAttribute("BaseCFrame", cf)
	beam:SetAttribute("Owner", owner)
	beam.Parent = parent
	CollectionService:AddTag(beam, "Laser")

	-- Emitters at both ends so the grid reads clearly even when a beam blinks off.
	for side = -1, 1, 2 do
		local emitter = Kit.block(
			parent,
			Vector3.new(0.6, 0.6, 0.6),
			cf * CFrame.new(side * (length / 2 + 0.3), 0, 0),
			Kit.Colors.Black,
			Enum.Material.Metal,
			"LaserEmitter"
		)
		emitter.CanCollide = false
		emitter.CastShadow = false
	end

	return {
		Part = beam,
		BaseCFrame = cf,
		Pattern = pattern,
		Speed = speed,
		Phase = phase,
		Amplitude = amplitude,
		Axis = axis,
		Owner = owner,
	}
end

function Kit.camera(
	parent: Instance,
	position: Vector3,
	baseYaw: number,
	sweep: number,
	speed: number,
	range: number,
	fov: number,
	owner: string,
	pitch: number?
): CameraDef
	local m = Kit.model("SecurityCamera", parent)
	local mount = Kit.block(
		m,
		Vector3.new(0.8, 1.2, 0.8),
		CFrame.new(position + Vector3.new(0, 0.9, 0)),
		Kit.Colors.Black,
		Enum.Material.Metal,
		"Mount"
	)
	mount.CanCollide = false
	local head = Kit.block(
		m,
		Vector3.new(1.2, 1.1, 2.4),
		CFrame.new(position),
		rgb(235, 235, 240),
		Enum.Material.SmoothPlastic,
		"Head"
	)
	head.CanCollide = false
	local lens = Kit.block(
		m,
		Vector3.new(0.6, 0.6, 0.2),
		head.CFrame * CFrame.new(0, 0, -1.25),
		rgb(255, 40, 40),
		Enum.Material.Neon,
		"Lens"
	)
	lens.CanCollide = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = lens
	weld.Parent = lens
	local light = Instance.new("SpotLight")
	light.Name = "ViewCone"
	light.Face = Enum.NormalId.Front
	light.Angle = fov
	light.Range = range
	light.Brightness = 2
	light.Color = rgb(255, 230, 160)
	light.Shadows = true
	light.Parent = head
	local p = pitch or 28
	head:SetAttribute("BaseYaw", baseYaw)
	head:SetAttribute("Sweep", sweep)
	head:SetAttribute("Speed", speed)
	head:SetAttribute("Phase", baseYaw * 1.7)
	head:SetAttribute("Pitch", p)
	head:SetAttribute("Owner", owner)
	CollectionService:AddTag(head, "SecurityCameraHead")
	return {
		Model = m,
		Head = head,
		Position = position,
		BaseYaw = baseYaw,
		Sweep = sweep,
		Speed = speed,
		Phase = baseYaw * 1.7,
		Pitch = p,
		Range = range,
		Fov = fov,
		Owner = owner,
	}
end

local TRAP_LOOKS = {
	Banana = {
		Size = Vector3.new(2.2, 0.3, 1.2),
		Color = rgb(255, 225, 60),
		Material = Enum.Material.SmoothPlastic,
		Radius = 2.6,
	},
	Spring = {
		Size = Vector3.new(3.4, 0.5, 3.4),
		Color = rgb(255, 90, 90),
		Material = Enum.Material.SmoothPlastic,
		Radius = 2.4,
	},
	Glue = { Size = Vector3.new(6, 0.12, 6), Color = rgb(240, 240, 255), Material = Enum.Material.Glass, Radius = 3.2 },
	Spike = { Size = Vector3.new(5, 0.3, 5), Color = rgb(120, 110, 100), Material = Enum.Material.Slate, Radius = 2.8 },
	Toxic = { Size = Vector3.new(9, 0.2, 9), Color = rgb(120, 255, 90), Material = Enum.Material.Neon, Radius = 4.4 },
}

function Kit.trap(parent: Instance, kind: string, position: Vector3, owner: string, rotation: number?): TrapDef
	local look = TRAP_LOOKS[kind] or TRAP_LOOKS.Banana
	local cf = CFrame.new(position + Vector3.new(0, look.Size.Y / 2, 0)) * CFrame.Angles(0, rotation or 0, 0)
	local part
	if kind == "Glue" or kind == "Toxic" then
		part = Kit.cyl(parent, look.Size.Y, look.Size.X, cf, look.Color, look.Material, kind .. "Trap")
		if kind == "Glue" then
			part.Transparency = 0.25
		end
	else
		part = Kit.block(parent, look.Size, cf, look.Color, look.Material, kind .. "Trap")
	end
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part:SetAttribute("Kind", kind)
	part:SetAttribute("Owner", owner)
	CollectionService:AddTag(part, "Trap")

	if kind == "Banana" then
		-- Peel flaps
		for i = 1, 3 do
			local flap = Kit.block(
				parent,
				Vector3.new(1.4, 0.2, 0.5),
				cf * CFrame.Angles(0, i * math.pi * 2 / 3, 0) * CFrame.new(0, 0, -0.8),
				look.Color,
				Enum.Material.SmoothPlastic,
				"Peel"
			)
			Kit.noCollide(flap)
			flap.Parent = part
		end
	elseif kind == "Spring" then
		local coil =
			Kit.cyl(parent, 0.6, 2.6, cf * CFrame.new(0, -0.4, 0), Kit.Colors.Metal, Enum.Material.Metal, "Coil")
		Kit.noCollide(coil)
		coil.Parent = part
	elseif kind == "Spike" then
		for x = -1, 1 do
			for z = -1, 1 do
				local spike = Kit.wedge(
					parent,
					Vector3.new(0.6, 1.2, 0.6),
					cf * CFrame.new(x * 1.5, 0.6, z * 1.5),
					rgb(200, 200, 205),
					Enum.Material.Metal
				)
				Kit.noCollide(spike)
				spike.Name = "Spike"
				spike.Parent = part
			end
		end
	elseif kind == "Toxic" then
		Kit.light(part, look.Color, 1.5, 14)
	end

	return {
		Part = part,
		Kind = kind,
		Position = position,
		Radius = look.Radius,
		Owner = owner,
		ReadyAt = 0,
	}
end

-- Teleport hatch with a hold prompt.
function Kit.hatch(
	parent: Instance,
	cf: CFrame,
	label: string,
	destination: CFrame,
	hold: number?
): (Part, ProximityPrompt)
	local base =
		Kit.cyl(parent, 0.4, 5, cf * CFrame.new(0, 0.2, 0), rgb(70, 72, 80), Enum.Material.DiamondPlate, "Hatch")
	local rim = Kit.cyl(parent, 0.5, 5.8, cf * CFrame.new(0, 0.1, 0), Kit.Colors.Black, Enum.Material.Metal)
	rim.CanCollide = false
	local glow = Kit.cyl(parent, 0.45, 2, cf * CFrame.new(0, 0.25, 0), rgb(110, 90, 255), Enum.Material.Neon)
	Kit.noCollide(glow)
	Kit.light(glow, rgb(140, 120, 255), 1.4, 12)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = label
	prompt.ObjectText = "Hatch"
	prompt.HoldDuration = hold or 0.6
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Hatch", true)
	prompt.Parent = base
	base:SetAttribute("Destination", destination)
	return base, prompt
end

-- Architecture -----------------------------------------------------------------------------

-- Decorative part: no collisions, queries, touches or shadows.
function Kit.detail(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

-- Triangular prism (two wedges back to back). Ridge runs along cf.RightVector at the top.
function Kit.gable(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): { BasePart }
	local half = Vector3.new(size.X, size.Y, size.Z / 2)
	return {
		Kit.wedge(parent, half, cf * CFrame.new(0, 0, -size.Z / 4), color, material),
		Kit.wedge(parent, half, cf * CFrame.new(0, 0, size.Z / 4) * CFrame.Angles(0, math.pi, 0), color, material),
	}
end

-- Striped fabric awning hanging off a wall. cf sits on the wall face; it slopes toward cf.LookVector.
function Kit.awning(parent: Instance, cf: CFrame, width: number, depth: number, colors: { Color3 })
	local stripes = math.max(2, math.floor(width / 2.6))
	local stripe = width / stripes
	for i = 0, stripes - 1 do
		local part = Kit.wedge(
			parent,
			Vector3.new(stripe, 1.5, depth),
			cf * CFrame.new(-width / 2 + stripe * (i + 0.5), 0, -depth / 2),
			colors[(i % #colors) + 1],
			Enum.Material.Fabric
		)
		part.CanCollide = false
	end
	local valance = Kit.block(
		parent,
		Vector3.new(width, 0.7, 0.2),
		cf * CFrame.new(0, -1.1, -depth),
		colors[1],
		Enum.Material.Fabric
	)
	Kit.detail(valance)
end

-- Picket fence from a to b (posts every ~6 studs, two rails).
function Kit.fence(parent: Instance, a: Vector3, b: Vector3, color: Color3?, height: number?)
	local h = height or 3.2
	local c = color or rgb(236, 232, 222)
	local delta = (b - a) * Vector3.new(1, 0, 1)
	local length = delta.Magnitude
	if length < 1 then
		return
	end
	local cf = CFrame.lookAt(a, a + delta)
	local posts = math.max(1, math.floor(length / 6 + 0.5))
	for i = 0, posts do
		Kit.block(
			parent,
			Vector3.new(0.6, h, 0.6),
			cf * CFrame.new(0, h / 2, -length * i / posts),
			c,
			Enum.Material.Wood
		)
	end
	for _, y in { h * 0.35, h * 0.8 } do
		Kit.detail(
			Kit.block(parent, Vector3.new(0.25, 0.4, length), cf * CFrame.new(0, y, -length / 2), c, Enum.Material.Wood)
		)
	end
	-- One invisible collider so the rails can stay cheap.
	local wall = Kit.ghost(parent, Vector3.new(0.6, h, length), cf * CFrame.new(0, h / 2, -length / 2), "FenceCollider")
	wall.CanCollide = true
end

-- Raised bed of soil with a few flowers.
function Kit.flowerBed(parent: Instance, cf: CFrame, size: Vector2, colors: { Color3 }?)
	local palette = colors or { rgb(255, 96, 120), rgb(255, 214, 90), rgb(190, 130, 255), rgb(255, 255, 255) }
	local m = Kit.model("FlowerBed", parent)
	Kit.block(
		m,
		Vector3.new(size.X + 0.8, 1, size.Y + 0.8),
		cf * CFrame.new(0, 0.5, 0),
		rgb(160, 150, 140),
		Enum.Material.Cobblestone
	)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(size.X, 0.3, size.Y),
			cf * CFrame.new(0, 1.05, 0),
			rgb(92, 66, 48),
			Enum.Material.Ground
		)
	)
	local n = math.max(3, math.floor(size.X * size.Y / 5))
	local seed = math.floor(math.abs(cf.Position.X * 3.1 + cf.Position.Z * 5.7)) % 9973
	for i = 1, n do
		local u = ((i * 0.618 + seed * 0.013) % 1 - 0.5) * (size.X - 1)
		local v = ((i * 0.377 + seed * 0.029) % 1 - 0.5) * (size.Y - 1)
		local bud =
			Kit.ball(m, 0.9, cf * CFrame.new(u, 1.55, v), palette[(i % #palette) + 1], Enum.Material.SmoothPlastic)
		Kit.detail(bud)
		if i % 2 == 0 then
			Kit.detail(
				Kit.ball(m, 1.1, cf * CFrame.new(u + 0.4, 1.3, v - 0.3), rgb(70, 140, 60), Enum.Material.LeafyGrass)
			)
		end
	end
	return m
end

-- Cluster of weathered boulders.
function Kit.rocks(parent: Instance, position: Vector3, scale: number?)
	local s = scale or 1
	local seed = math.floor(math.abs(position.X * 1.7 + position.Z * 2.3)) % 997
	local m = Kit.model("Rocks", parent)
	for i = 0, 2 do
		local size = Vector3.new(5 - i, 3.6 - i * 0.7, 4.4 - i * 0.8) * s
		local offset =
			Vector3.new((i == 1 and 3.2 or i == 2 and -2.6 or 0) * s, size.Y * 0.35, (i == 2 and 2 or -0.5 * i) * s)
		Kit.block(
			m,
			size,
			CFrame.new(position + offset) * CFrame.Angles(0.12 * i, (seed + i * 47) % 360, -0.1 * i),
			rgb(128, 126, 122):Lerp(rgb(160, 156, 148), i / 3),
			Enum.Material.Rock,
			"Rock"
		)
	end
	return m
end

function Kit.trashCan(parent: Instance, position: Vector3)
	local m = Kit.model("TrashCan", parent)
	Kit.cyl(m, 3, 2, CFrame.new(position + Vector3.new(0, 1.5, 0)), rgb(60, 110, 80), Enum.Material.Metal)
	Kit.detail(
		Kit.cyl(m, 0.3, 2.3, CFrame.new(position + Vector3.new(0, 3.1, 0)), rgb(45, 80, 60), Enum.Material.Metal)
	)
	return m
end

function Kit.hydrant(parent: Instance, position: Vector3)
	local m = Kit.model("Hydrant", parent)
	local red = rgb(205, 50, 45)
	Kit.cyl(m, 2.2, 1.1, CFrame.new(position + Vector3.new(0, 1.1, 0)), red, Enum.Material.Metal)
	Kit.detail(Kit.ball(m, 1.15, CFrame.new(position + Vector3.new(0, 2.25, 0)), red, Enum.Material.Metal))
	Kit.detail(
		Kit.cyl(
			m,
			1.6,
			0.5,
			CFrame.new(position + Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			rgb(230, 230, 230),
			Enum.Material.Metal
		)
	)
	return m
end

export type BuildingOptions = {
	Name: string?,
	Size: Vector3, -- width (X), height (Y), depth (Z); the front faces cf.LookVector
	Wall: Color3,
	WallMaterial: Enum.Material?,
	Trim: Color3,
	Floors: number?,
	Glass: Color3?,
	Style: string?, -- "Classic" (punched windows) or "Modern" (curtain wall)
	Shop: { Text: string, Color: Color3, TextColor: Color3?, Awning: { Color3 }? }?,
	RoofProps: boolean?,
	Seed: number?,
}

-- City building with floors, windows, a cornice, rooftop clutter and an optional shopfront.
function Kit.building(parent: Instance, cf: CFrame, o: BuildingOptions): Model
	local m = Kit.model(o.Name or "Building", parent)
	local w, h, d = o.Size.X, o.Size.Y, o.Size.Z
	local floors = o.Floors or math.max(1, math.floor(h / 11))
	local fh = h / floors
	local trimMaterial = Enum.Material.Concrete
	local glass = o.Glass or rgb(70, 96, 122)
	local seed = o.Seed or math.floor(math.abs(cf.Position.X * 3 + cf.Position.Z * 7))

	Kit.block(m, Vector3.new(w + 0.8, 1, d + 0.8), cf * CFrame.new(0, 0.5, 0), o.Trim, trimMaterial, "Plinth")
	Kit.block(
		m,
		Vector3.new(w, h, d),
		cf * CFrame.new(0, h / 2, 0),
		o.Wall,
		o.WallMaterial or Enum.Material.Brick,
		"Body"
	)
	for f = 1, floors - 1 do
		Kit.detail(
			Kit.block(m, Vector3.new(w + 0.5, 0.7, d + 0.5), cf * CFrame.new(0, f * fh, 0), o.Trim, trimMaterial)
		)
	end
	Kit.block(m, Vector3.new(w + 1.6, 1.2, d + 1.6), cf * CFrame.new(0, h + 0.4, 0), o.Trim, trimMaterial, "Cornice")
	Kit.block(
		m,
		Vector3.new(w + 0.4, 1.4, d + 0.4),
		cf * CFrame.new(0, h + 1.6, 0),
		o.Wall,
		o.WallMaterial or Enum.Material.Brick
	)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(w - 1.6, 0.2, d - 1.6),
			cf * CFrame.new(0, h + 2.35, 0),
			rgb(78, 80, 86),
			Enum.Material.Asphalt
		)
	)

	-- Facades: { frame on the wall whose LookVector points outward, face width }
	local faces = {
		{ CFrame.new(0, 0, -d / 2), w },
		{ CFrame.new(0, 0, d / 2) * CFrame.Angles(0, math.pi, 0), w },
		{ CFrame.new(-w / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0), d },
		{ CFrame.new(w / 2, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), d },
	}
	local firstFloor = o.Shop and 1 or 0
	if o.Style == "Modern" then
		for _, face in faces do
			local faceCF = cf * face[1]
			local width = face[2]
			local top = h - 1.2
			local bottom = firstFloor * fh + 1.2
			Kit.detail(
				Kit.block(
					m,
					Vector3.new(width - 2.4, top - bottom, 0.3),
					faceCF * CFrame.new(0, (top + bottom) / 2, -0.1),
					glass,
					Enum.Material.Glass
				)
			)
			local mullions = math.max(2, math.floor(width / 6))
			for i = 0, mullions do
				local x = -width / 2 + 1.2 + (width - 2.4) * i / mullions
				Kit.detail(
					Kit.block(
						m,
						Vector3.new(0.5, top - bottom, 0.5),
						faceCF * CFrame.new(x, (top + bottom) / 2, -0.25),
						o.Trim,
						Enum.Material.Metal
					)
				)
			end
		end
	else
		for _, face in faces do
			local faceCF = cf * face[1]
			local width = face[2]
			local count = math.max(1, math.floor((width - 2) / 7))
			local spacing = (width - 2) / count
			local winW = math.min(spacing * 0.55, 4.4)
			local winH = math.min(fh * 0.5, 6)
			for f = firstFloor, floors - 1 do
				for i = 0, count - 1 do
					local x = -width / 2 + 1 + spacing * (i + 0.5)
					local y = f * fh + fh * 0.55
					Kit.detail(
						Kit.block(
							m,
							Vector3.new(winW, winH, 0.3),
							faceCF * CFrame.new(x, y, -0.1),
							glass,
							Enum.Material.Glass
						)
					)
					Kit.detail(
						Kit.block(
							m,
							Vector3.new(winW + 0.8, 0.35, 0.7),
							faceCF * CFrame.new(x, y - winH / 2 - 0.15, -0.3),
							o.Trim,
							trimMaterial
						)
					)
				end
			end
		end
	end

	if o.Shop then
		local front = cf * CFrame.new(0, 0, -d / 2)
		local shopH = fh
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(w * 0.62, shopH * 0.55, 0.3),
				front * CFrame.new(-w * 0.1, shopH * 0.42, -0.1),
				rgb(150, 190, 210),
				Enum.Material.Glass
			)
		)
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(w * 0.62 + 0.8, 0.5, 0.8),
				front * CFrame.new(-w * 0.1, shopH * 0.42 - shopH * 0.275 - 0.2, -0.35),
				o.Trim,
				trimMaterial
			)
		)
		local doorX = w * 0.32
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(4, 7, 0.4),
				front * CFrame.new(doorX, 4, -0.15),
				rgb(70, 50, 40),
				Enum.Material.Wood
			)
		)
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(2.6, 3.2, 0.45),
				front * CFrame.new(doorX, 5, -0.2),
				rgb(150, 190, 210),
				Enum.Material.Glass
			)
		)
		Kit.awning(m, front * CFrame.new(0, shopH * 0.86, 0), w - 2, 4.5, o.Shop.Awning or { o.Shop.Color, C_WHITE })
		local sign = Kit.block(
			m,
			Vector3.new(math.min(w - 4, 22), 2.6, 0.4),
			front * CFrame.new(0, shopH * 0.86 + 2.3, -0.3),
			o.Shop.Color,
			Enum.Material.SmoothPlastic,
			"ShopSign"
		)
		Kit.detail(sign)
		Kit.label(
			sign,
			o.Shop.Text,
			{ TextColor = o.Shop.TextColor or C_WHITE, Font = Enum.Font.FredokaOne, Stroke = rgb(30, 30, 35) }
		)
	end

	if o.RoofProps ~= false then
		local rng = Random.new(seed)
		local roofY = h + 2.45
		for _ = 1, rng:NextInteger(1, 3) do
			local size = Vector3.new(rng:NextNumber(3, 5), rng:NextNumber(1.8, 2.8), rng:NextNumber(2.5, 4))
			local x = rng:NextNumber(-w / 2 + 3.5, w / 2 - 3.5)
			local z = rng:NextNumber(-d / 2 + 3.5, d / 2 - 3.5)
			Kit.block(m, size, cf * CFrame.new(x, roofY + size.Y / 2, z), rgb(186, 190, 196), Enum.Material.Metal, "AC")
			Kit.detail(
				Kit.block(
					m,
					Vector3.new(size.X * 0.7, 0.1, size.Z * 0.7),
					cf * CFrame.new(x, roofY + size.Y + 0.05, z),
					rgb(60, 62, 68),
					Enum.Material.DiamondPlate
				)
			)
		end
		if h > 30 and rng:NextNumber() < 0.6 then
			-- Water tower
			local x, z = w / 4, d / 4
			for _, leg in { { -1.6, -1.6 }, { 1.6, -1.6 }, { -1.6, 1.6 }, { 1.6, 1.6 } } do
				Kit.detail(
					Kit.block(
						m,
						Vector3.new(0.4, 5, 0.4),
						cf * CFrame.new(x + leg[1], roofY + 2.5, z + leg[2]),
						rgb(70, 60, 50),
						Enum.Material.Wood
					)
				)
			end
			Kit.cyl(
				m,
				6,
				5.4,
				cf * CFrame.new(x, roofY + 8, z),
				rgb(150, 110, 80),
				Enum.Material.WoodPlanks,
				"WaterTower"
			)
			Kit.cyl(m, 1.4, 5.8, cf * CFrame.new(x, roofY + 11.6, z), rgb(80, 70, 66), Enum.Material.Metal)
		elseif rng:NextNumber() < 0.5 then
			Kit.detail(
				Kit.cyl(m, 8, 0.3, cf * CFrame.new(-w / 4, roofY + 4, d / 5), rgb(200, 200, 205), Enum.Material.Metal)
			)
			local tip =
				Kit.ball(m, 0.6, cf * CFrame.new(-w / 4, roofY + 8.2, d / 5), rgb(255, 70, 70), Enum.Material.Neon)
			Kit.detail(tip)
		end
	end
	return m
end

export type HouseOptions = {
	Size: Vector3?, -- width, wall height, depth
	Wall: Color3,
	Roof: Color3,
	Trim: Color3?,
	Door: Color3?,
}

-- Little suburban house with a gable roof, porch and chimney. Front faces cf.LookVector.
function Kit.house(parent: Instance, cf: CFrame, o: HouseOptions): Model
	local size = o.Size or Vector3.new(18, 10, 15)
	local w, h, d = size.X, size.Y, size.Z
	local trim = o.Trim or rgb(245, 242, 235)
	local m = Kit.model("House", parent)
	Kit.block(
		m,
		Vector3.new(w + 0.6, 1, d + 0.6),
		cf * CFrame.new(0, 0.5, 0),
		rgb(150, 145, 140),
		Enum.Material.Cobblestone
	)
	Kit.block(m, Vector3.new(w, h, d), cf * CFrame.new(0, 1 + h / 2, 0), o.Wall, Enum.Material.Plaster, "Body")
	local roofH = math.min(w, d) * 0.42
	Kit.gable(
		m,
		cf * CFrame.new(0, 1 + h + roofH / 2, 0),
		Vector3.new(w + 2.4, roofH, d + 2.4),
		o.Roof,
		Enum.Material.RoofShingles
	)
	Kit.detail(Kit.block(m, Vector3.new(w + 0.4, 0.5, d + 0.4), cf * CFrame.new(0, 1 + h, 0), trim, Enum.Material.Wood))
	-- Chimney
	Kit.block(
		m,
		Vector3.new(2.2, roofH + 2, 2.2),
		cf * CFrame.new(w * 0.28, 1 + h + roofH / 2 + 1, d * 0.18),
		rgb(150, 80, 64),
		Enum.Material.Brick
	)
	-- Door, porch, windows
	local front = cf * CFrame.new(0, 1, -d / 2)
	Kit.detail(
		Kit.block(
			m,
			Vector3.new(3.4, 6.4, 0.3),
			front * CFrame.new(0, 3.2, -0.1),
			o.Door or rgb(110, 60, 50),
			Enum.Material.Wood
		)
	)
	Kit.block(
		m,
		Vector3.new(6, 0.6, 3),
		front * CFrame.new(0, -0.2, -1.5),
		rgb(170, 160, 150),
		Enum.Material.Concrete,
		"Porch"
	)
	Kit.detail(
		Kit.wedge(m, Vector3.new(6, 1.2, 2.6), front * CFrame.new(0, 7.4, -1.3), o.Roof, Enum.Material.RoofShingles)
	)
	for side = -1, 1, 2 do
		local x = side * w * 0.3
		Kit.detail(
			Kit.block(
				m,
				Vector3.new(3.4, 3.4, 0.3),
				front * CFrame.new(x, 4.6, -0.1),
				rgb(120, 160, 190),
				Enum.Material.Glass
			)
		)
		Kit.detail(
			Kit.block(m, Vector3.new(4.2, 0.4, 0.6), front * CFrame.new(x, 2.75, -0.3), trim, Enum.Material.Wood)
		)
		for edge = -1, 1, 2 do
			Kit.detail(
				Kit.block(
					m,
					Vector3.new(0.9, 3.6, 0.2),
					front * CFrame.new(x + edge * 2.25, 4.6, -0.15),
					o.Door or rgb(110, 60, 50),
					Enum.Material.Wood
				)
			)
		end
	end
	return m
end

return Kit
