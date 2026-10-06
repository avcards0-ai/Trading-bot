--[[
	Kit
	Building blocks for the procedural map: primitives, signs, lights, props and the
	security devices (lasers / cameras / traps) whose definitions the SecurityService reads.
]]

local CollectionService = game:GetService("CollectionService")

local Kit = {}

local rgb = Color3.fromRGB
Kit.rgb = rgb

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

function Kit.block(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, name: string?): Part
	local p = Instance.new("Part")
	p.Name = name or "Part"
	p.Size = size
	p.CFrame = cf
	applyDefaults(p, color, material)
	p.Parent = parent
	return p
end

-- Vertical cylinder centered on cf.
function Kit.cyl(parent: Instance, height: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, name: string?): Part
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
	light.Brightness = brightness
	;(light :: any).Range = range
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
function Kit.sign(parent: Instance, size: Vector3, cf: CFrame, text: string, board: Color3, textColor: Color3?, options: LabelOptions?): Part
	local p = Kit.block(parent, size, cf, board, Enum.Material.SmoothPlastic, "Sign")
	local opts = options or {}
	opts.TextColor = textColor or opts.TextColor
	opts.Stroke = opts.Stroke or Kit.Colors.Black
	Kit.label(p, text, opts)
	return p
end

-- Interaction prompt that the client turns into a UI shortcut (see InteractController).
function Kit.uiPrompt(part: BasePart, action: string, object: string, uiName: string, key: Enum.KeyCode?): ProximityPrompt
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

function Kit.tree(parent: Instance, position: Vector3, scale: number?, leafColor: Color3?)
	local s = scale or 1
	local m = Kit.model("Tree", parent)
	Kit.cyl(m, 10 * s, 1.8 * s, CFrame.new(position + Vector3.new(0, 5 * s, 0)), Kit.Colors.DarkWood, Enum.Material.Wood)
	local leaves = leafColor or rgb(70, 160, 70)
	Kit.ball(m, 10 * s, CFrame.new(position + Vector3.new(0, 12 * s, 0)), leaves, Enum.Material.Grass)
	Kit.ball(m, 7 * s, CFrame.new(position + Vector3.new(2.5 * s, 10 * s, 1.5 * s)), leaves:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Grass)
	Kit.ball(m, 6.5 * s, CFrame.new(position + Vector3.new(-2 * s, 14 * s, -1.5 * s)), leaves:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Grass)
	return m
end

function Kit.palm(parent: Instance, position: Vector3, scale: number?)
	local s = scale or 1
	local m = Kit.model("Palm", parent)
	for i = 0, 4 do
		Kit.cyl(m, 3.2 * s, (1.5 - i * 0.1) * s, CFrame.new(position + Vector3.new(i * 0.35 * s, (1.6 + i * 3) * s, 0)) * CFrame.Angles(0, 0, math.rad(-6)), rgb(150, 110, 70), Enum.Material.Wood)
	end
	local top = position + Vector3.new(1.8 * s, 15.5 * s, 0)
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local cf = CFrame.new(top) * CFrame.Angles(0, angle, 0) * CFrame.new(0, -0.8 * s, -3.5 * s) * CFrame.Angles(math.rad(-25), 0, 0)
		Kit.block(m, Vector3.new(1.6 * s, 0.3 * s, 7 * s), cf, rgb(60, 170, 70), Enum.Material.Grass)
	end
	return m
end

function Kit.lamp(parent: Instance, position: Vector3, color: Color3?, height: number?)
	local h = height or 12
	local m = Kit.model("Lamp", parent)
	Kit.cyl(m, h, 0.6, CFrame.new(position + Vector3.new(0, h / 2, 0)), Kit.Colors.Black, Enum.Material.Metal)
	local bulb = Kit.ball(m, 1.6, CFrame.new(position + Vector3.new(0, h + 0.4, 0)), color or rgb(255, 230, 170), Enum.Material.Neon)
	bulb.CastShadow = false
	Kit.light(bulb, color or rgb(255, 220, 160), 1.6, 22)
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
	Kit.block(parent, Vector3.new(s + 0.1, 0.3, s + 0.1), cf * CFrame.new(0, -s / 2 + 0.15, 0), trim, Enum.Material.Wood)
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

function Kit.pillar(parent: Instance, base: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?)
	Kit.block(parent, Vector3.new(diameter + 1.2, 1, diameter + 1.2), CFrame.new(base + Vector3.new(0, 0.5, 0)), color, material)
	Kit.cyl(parent, height - 2, diameter, CFrame.new(base + Vector3.new(0, height / 2, 0)), color, material)
	Kit.block(parent, Vector3.new(diameter + 1.2, 1, diameter + 1.2), CFrame.new(base + Vector3.new(0, height - 0.5, 0)), color, material)
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
	Kit.block(parent, Vector3.new(3.4, 0.5, 3.4), cf * CFrame.new(0, 0.25, 0), c:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Marble, "PedestalBase")
	Kit.block(parent, Vector3.new(2.6, 3, 2.6), cf * CFrame.new(0, 2, 0), c, Enum.Material.Marble, "Pedestal")
	local top = Kit.block(parent, Vector3.new(3.2, 0.35, 3.2), cf * CFrame.new(0, 3.65, 0), c:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Marble, "PedestalTop")
	local strip: BasePart? = nil
	if glow then
		local glowPart = Kit.block(parent, Vector3.new(2.7, 0.15, 2.7), cf * CFrame.new(0, 3.88, 0), glow, Enum.Material.Neon, "Glow")
		glowPart.CastShadow = false
		Kit.noCollide(glowPart)
		strip = glowPart
	end
	return top.CFrame * CFrame.new(0, 2.1, 0), strip, top
end

-- Glass display case on a pedestal; returns artifact CFrame.
function Kit.displayCase(parent: Instance, cf: CFrame, color: Color3?): CFrame
	local spot = Kit.pedestal(parent, cf, color, Kit.Colors.Gold)
	local glass = Kit.block(parent, Vector3.new(0.2, 3.6, 3.0), cf * CFrame.new(1.5, 5.8, 0), rgb(200, 230, 255), Enum.Material.Glass, "Glass")
	glass.Transparency = 0.75
	Kit.noCollide(glass)
	local glass2 = Kit.block(parent, Vector3.new(0.2, 3.6, 3.0), cf * CFrame.new(-1.5, 5.8, 0), rgb(200, 230, 255), Enum.Material.Glass, "Glass")
	glass2.Transparency = 0.75
	Kit.noCollide(glass2)
	return spot
end

-- Stairs climbing along cf.LookVector.
function Kit.stairs(parent: Instance, cf: CFrame, steps: number, width: number, rise: number, run: number, color: Color3, material: Enum.Material?)
	for i = 0, steps - 1 do
		Kit.block(parent, Vector3.new(width, rise * (i + 1), run), cf * CFrame.new(0, rise * (i + 1) / 2, -run * i - run / 2), color, material, "Step")
	end
end

-- Four walls with optional door gaps. `doors` maps "Front"/"Back"/"Left"/"Right" to a gap width.
function Kit.room(parent: Instance, cf: CFrame, size: Vector3, thickness: number, color: Color3, material: Enum.Material?, doors: { [string]: number }?, doorHeight: number?)
	local gaps = doors or {}
	local dh = math.min(doorHeight or 12, size.Y)
	local walls = {}
	local function wall(name: string, length: number, center: CFrame, gap: number?)
		if gap and gap > 0 then
			local side = (length - gap) / 2
			table.insert(walls, Kit.block(parent, Vector3.new(side, size.Y, thickness), center * CFrame.new(-(gap / 2 + side / 2), 0, 0), color, material, name))
			table.insert(walls, Kit.block(parent, Vector3.new(side, size.Y, thickness), center * CFrame.new(gap / 2 + side / 2, 0, 0), color, material, name))
			if size.Y > dh then
				table.insert(walls, Kit.block(parent, Vector3.new(gap, size.Y - dh, thickness), center * CFrame.new(0, dh / 2, 0), color, material, name))
			end
		else
			table.insert(walls, Kit.block(parent, Vector3.new(length, size.Y, thickness), center, color, material, name))
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
function Kit.laser(parent: Instance, cf: CFrame, length: number, pattern: string, speed: number, phase: number, amplitude: number, axis: Vector3, owner: string, color: Color3?): LaserDef
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
		local emitter = Kit.block(parent, Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(side * (length / 2 + 0.3), 0, 0), Kit.Colors.Black, Enum.Material.Metal, "LaserEmitter")
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

function Kit.camera(parent: Instance, position: Vector3, baseYaw: number, sweep: number, speed: number, range: number, fov: number, owner: string, pitch: number?): CameraDef
	local m = Kit.model("SecurityCamera", parent)
	local mount = Kit.block(m, Vector3.new(0.8, 1.2, 0.8), CFrame.new(position + Vector3.new(0, 0.9, 0)), Kit.Colors.Black, Enum.Material.Metal, "Mount")
	mount.CanCollide = false
	local head = Kit.block(m, Vector3.new(1.2, 1.1, 2.4), CFrame.new(position), rgb(235, 235, 240), Enum.Material.SmoothPlastic, "Head")
	head.CanCollide = false
	local lens = Kit.block(m, Vector3.new(0.6, 0.6, 0.2), head.CFrame * CFrame.new(0, 0, -1.25), rgb(255, 40, 40), Enum.Material.Neon, "Lens")
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
	Banana = { Size = Vector3.new(2.2, 0.3, 1.2), Color = rgb(255, 225, 60), Material = Enum.Material.SmoothPlastic, Radius = 2.6 },
	Spring = { Size = Vector3.new(3.4, 0.5, 3.4), Color = rgb(255, 90, 90), Material = Enum.Material.SmoothPlastic, Radius = 2.4 },
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
			local flap = Kit.block(parent, Vector3.new(1.4, 0.2, 0.5), cf * CFrame.Angles(0, i * math.pi * 2 / 3, 0) * CFrame.new(0, 0, -0.8), look.Color, Enum.Material.SmoothPlastic, "Peel")
			Kit.noCollide(flap)
			flap.Parent = part
		end
	elseif kind == "Spring" then
		local coil = Kit.cyl(parent, 0.6, 2.6, cf * CFrame.new(0, -0.4, 0), Kit.Colors.Metal, Enum.Material.Metal, "Coil")
		Kit.noCollide(coil)
		coil.Parent = part
	elseif kind == "Spike" then
		for x = -1, 1 do
			for z = -1, 1 do
				local spike = Kit.wedge(parent, Vector3.new(0.6, 1.2, 0.6), cf * CFrame.new(x * 1.5, 0.6, z * 1.5), rgb(200, 200, 205), Enum.Material.Metal)
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
function Kit.hatch(parent: Instance, cf: CFrame, label: string, destination: CFrame, hold: number?): (Part, ProximityPrompt)
	local base = Kit.cyl(parent, 0.4, 5, cf * CFrame.new(0, 0.2, 0), rgb(70, 72, 80), Enum.Material.DiamondPlate, "Hatch")
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

return Kit
