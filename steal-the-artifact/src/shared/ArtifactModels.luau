--[[
	ArtifactModels
	Builds every artifact procedurally from primitives (no uploaded meshes needed), so the
	same function produces world pickups, pedestal displays, carried loot and the 3D
	previews in UI ViewportFrames.

	Every model has an invisible "Core" PrimaryPart at its center (~2.6 studs) that holds
	prompts / welds, and attributes: ArtifactId, Rarity, Mutation.
]]

local Config = script.Parent.Config
local Artifacts = require(Config.Artifacts)

local ArtifactModels = {}

local M = {
	Metal = Enum.Material.Metal,
	Neon = Enum.Material.Neon,
	Glass = Enum.Material.Glass,
	Plastic = Enum.Material.SmoothPlastic,
	Wood = Enum.Material.Wood,
	Slate = Enum.Material.Slate,
	Fabric = Enum.Material.Fabric,
	Foil = Enum.Material.Foil,
	Marble = Enum.Material.Marble,
	Rock = Enum.Material.Rock,
	Basalt = Enum.Material.Basalt,
	Sand = Enum.Material.Sandstone,
	FF = Enum.Material.ForceField,
	Ice = Enum.Material.Ice,
	Granite = Enum.Material.Granite,
}

local WHITE = Color3.fromRGB(250, 250, 250)
local BLACK = Color3.fromRGB(20, 20, 24)
local SKIN = Color3.fromRGB(250, 205, 160)

type Builder = {
	model: Model,
	c1: Color3,
	c2: Color3,
	parts: { BasePart },
}

local function at(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

local function finish(b: Builder, p: BasePart, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): BasePart
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = material ~= M.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if material == M.Glass then
		p.Transparency = 0.35
	end
	p.Parent = b.model
	table.insert(b.parts, p)
	return p
end

local function box(b: Builder, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	return finish(b, Instance.new("Part"), size, cf, color, material or M.Plastic)
end

local function ball(b: Builder, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	return finish(b, p, Vector3.one * diameter, cf, color, material or M.Plastic)
end

-- Vertical cylinder (Roblox cylinders run along X, so rotate onto Y).
local function cyl(b: Builder, height: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	return finish(b, p, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material or M.Plastic)
end

-- Cylinder facing the viewer (axis along Z) - coins, watch faces.
local function disc(b: Builder, thickness: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	return finish(b, p, Vector3.new(thickness, diameter, diameter), cf * CFrame.Angles(0, math.rad(90), 0), color, material or M.Plastic)
end

local function wedge(b: Builder, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	return finish(b, Instance.new("WedgePart"), size, cf, color, material or M.Plastic)
end

-- Ellipsoid: a block with a sphere mesh stretched to its size.
local function blob(b: Builder, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = box(b, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Ring of small blocks. `cf` orients the ring; the ring lies in cf's XZ plane.
local function ring(b: Builder, radius: number, thickness: number, segments: number, cf: CFrame, color: Color3, material: Enum.Material?)
	local arc = 2 * math.pi * radius / segments * 1.08
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local offset = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
		box(b, Vector3.new(arc, thickness, thickness), cf * offset, color, material)
	end
end

-- Stacked shrinking cylinders approximating a cone.
local function cone(b: Builder, height: number, diameter: number, steps: number, cf: CFrame, color: Color3, material: Enum.Material?)
	for i = 0, steps - 1 do
		local f = i / steps
		local h = height / steps
		cyl(b, h, diameter * (1 - f) + 0.05, cf * CFrame.new(0, h * i + h / 2, 0), color, material)
	end
end

local function gem(b: Builder, size: number, cf: CFrame, outer: Color3, inner: Color3)
	box(b, Vector3.one * size, cf * CFrame.Angles(math.rad(45), 0, math.rad(45)), outer, M.Glass)
	box(b, Vector3.one * size * 0.6, cf * CFrame.Angles(math.rad(45), math.rad(20), math.rad(45)), inner, M.Neon)
end

local function eyes(b: Builder, spread: number, cf: CFrame, size: number, color: Color3?, material: Enum.Material?)
	ball(b, size, cf * CFrame.new(-spread, 0, 0), color or BLACK, material)
	ball(b, size, cf * CFrame.new(spread, 0, 0), color or BLACK, material)
end

local function rock(b: Builder, scale: number, cf: CFrame, color: Color3, material: Enum.Material)
	box(b, Vector3.new(1.4, 1.1, 1.2) * scale, cf * CFrame.Angles(0.3, 0.5, 0.2), color, material)
	box(b, Vector3.new(1.1, 1.2, 1.0) * scale, cf * CFrame.new(0.3 * scale, 0.15 * scale, 0.1) * CFrame.Angles(0.8, 0.1, 0.6), color, material)
	box(b, Vector3.new(1.0, 0.9, 1.2) * scale, cf * CFrame.new(-0.3 * scale, -0.1 * scale, -0.2) * CFrame.Angles(0.2, 1.1, 0.9), color:Lerp(BLACK, 0.12), material)
end

local function crownShape(b: Builder, band: Color3, accent: Color3, bandMaterial: Enum.Material)
	ring(b, 0.85, 0.42, 12, at(0, -0.3, 0), band, bandMaterial)
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local cf = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.3, -0.85)
		wedge(b, Vector3.new(0.2, 0.75, 0.45), cf * CFrame.Angles(0, math.rad(90), 0), band, bandMaterial)
		ball(b, 0.26, CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.75, -0.85), accent, M.Neon)
		ball(b, 0.22, CFrame.Angles(0, angle + math.pi / 6, 0) * CFrame.new(0, -0.3, -0.92), accent, M.Glass)
	end
	blob(b, Vector3.new(1.5, 0.9, 1.5), at(0, 0, 0), accent:Lerp(BLACK, 0.35), M.Fabric)
end

local SHAPES: { [string]: (Builder) -> () } = {}

SHAPES.Duck = function(b)
	blob(b, Vector3.new(1.5, 1.15, 1.9), at(0, -0.35, 0.1), b.c1)
	ball(b, 1.05, at(0, 0.55, -0.55), b.c1)
	wedge(b, Vector3.new(0.6, 0.25, 0.55), at(0, 0.45, -1.2, 0, 180, 0), b.c2)
	eyes(b, 0.28, at(0, 0.72, -0.98), 0.18)
	blob(b, Vector3.new(0.3, 0.6, 0.9), at(0.72, -0.25, 0.15, 0, 0, -15), b.c1:Lerp(b.c2, 0.2))
	blob(b, Vector3.new(0.3, 0.6, 0.9), at(-0.72, -0.25, 0.15, 0, 0, 15), b.c1:Lerp(b.c2, 0.2))
end

SHAPES.Coin = function(b)
	disc(b, 0.25, 1.9, at(0, 0, 0), b.c1, M.Metal)
	disc(b, 0.3, 1.35, at(0, 0, 0), b.c2, M.Metal)
	box(b, Vector3.new(0.18, 0.8, 0.34), at(0, 0, 0), b.c1, M.Metal)
end

SHAPES.Vase = function(b)
	cyl(b, 0.3, 1.0, at(0, -1.05, 0), b.c2)
	blob(b, Vector3.new(1.6, 1.7, 1.6), at(0, -0.25, 0), b.c1)
	cyl(b, 0.25, 1.62, at(0, -0.15, 0), b.c2)
	cyl(b, 0.8, 0.7, at(0, 0.85, 0), b.c1)
	cyl(b, 0.18, 1.0, at(0, 1.25, 0), b.c2)
end

SHAPES.Boot = function(b)
	box(b, Vector3.new(1.0, 0.65, 1.9), at(0, -0.7, -0.35), b.c1, M.Fabric)
	box(b, Vector3.new(1.0, 1.7, 1.05), at(0, 0.2, 0.3), b.c1, M.Fabric)
	box(b, Vector3.new(1.1, 0.2, 2.0), at(0, -1.1, -0.35), b.c2)
	box(b, Vector3.new(1.06, 0.2, 1.1), at(0, 0.95, 0.3), b.c2)
end

SHAPES.Sandwich = function(b)
	box(b, Vector3.new(1.9, 0.38, 1.9), at(0, -0.45, 0), b.c1)
	box(b, Vector3.new(2.05, 0.12, 2.05), at(0, -0.2, 0, 0, 12, 0), b.c2, M.Fabric)
	cyl(b, 0.14, 0.9, at(0.4, -0.08, 0.3), Color3.fromRGB(230, 60, 50))
	box(b, Vector3.new(1.85, 0.12, 1.85), at(0, 0.02, 0, 0, -8, 0), Color3.fromRGB(255, 200, 60))
	box(b, Vector3.new(1.9, 0.4, 1.9), at(0, 0.3, 0), b.c1)
	cyl(b, 1.2, 0.08, at(0, 0.9, 0), WHITE, M.Wood)
	ball(b, 0.32, at(0, 1.5, 0), Color3.fromRGB(80, 140, 50))
end

SHAPES.Gnome = function(b)
	cyl(b, 1.1, 1.2, at(0, -0.65, 0), b.c2)
	ball(b, 0.85, at(0, 0.2, 0), SKIN)
	wedge(b, Vector3.new(0.75, 0.75, 0.4), at(0, -0.15, -0.35, 0, 0, 180), WHITE)
	ball(b, 0.25, at(0, 0.18, -0.42), Color3.fromRGB(255, 150, 140))
	cone(b, 1.2, 1.0, 4, at(0, 0.45, 0), b.c1)
end

SHAPES.Key = function(b)
	disc(b, 0.25, 1.0, at(0, 0.7, 0), b.c1, M.Metal)
	disc(b, 0.3, 0.5, at(0, 0.7, 0), b.c2, M.Metal)
	box(b, Vector3.new(0.22, 1.6, 0.22), at(0, -0.4, 0), b.c1, M.Metal)
	box(b, Vector3.new(0.45, 0.18, 0.2), at(0.3, -0.95, 0), b.c1, M.Metal)
	box(b, Vector3.new(0.35, 0.18, 0.2), at(0.25, -0.6, 0), b.c1, M.Metal)
end

SHAPES.Robot = function(b)
	box(b, Vector3.new(1.2, 1.15, 0.9), at(0, -0.4, 0), b.c1, M.Metal)
	box(b, Vector3.new(0.95, 0.75, 0.85), at(0, 0.6, 0), b.c1, M.Metal)
	box(b, Vector3.new(0.2, 0.15, 0.05), at(-0.22, 0.65, -0.44), b.c2, M.Neon)
	box(b, Vector3.new(0.2, 0.15, 0.05), at(0.22, 0.65, -0.44), b.c2, M.Neon)
	cyl(b, 0.45, 0.08, at(0, 1.18, 0), b.c1, M.Metal)
	ball(b, 0.2, at(0, 1.45, 0), b.c2, M.Neon)
	box(b, Vector3.new(0.3, 0.9, 0.3), at(-0.78, -0.4, 0, 0, 0, 10), b.c1, M.Metal)
	box(b, Vector3.new(0.3, 0.9, 0.3), at(0.78, -0.4, 0, 0, 0, -10), b.c1, M.Metal)
	box(b, Vector3.new(0.6, 0.35, 0.05), at(0, -0.35, -0.46), b.c2, M.Neon)
end

SHAPES.Teapot = function(b)
	blob(b, Vector3.new(1.7, 1.3, 1.7), at(0, -0.3, 0), b.c1)
	cyl(b, 0.2, 1.0, at(0, 0.38, 0), b.c2)
	ball(b, 0.3, at(0, 0.6, 0), b.c2)
	cyl(b, 0.9, 0.25, at(0, -0.1, -1.0, -50, 0, 0), b.c1)
	ring(b, 0.35, 0.15, 6, at(0, -0.2, 0.95, 0, 0, 90), b.c1)
	cyl(b, 0.12, 1.4, at(0, -0.65, 0), b.c2)
end

SHAPES.Globe = function(b)
	cyl(b, 0.5, 1.4, at(0, -0.85, 0), b.c2, M.Wood)
	ball(b, 1.7, at(0, 0.3, 0), b.c1, M.Glass)
	ball(b, 0.55, at(0, -0.05, 0), WHITE)
	ball(b, 0.38, at(0, 0.38, 0), WHITE)
	box(b, Vector3.new(0.12, 0.12, 0.25), at(0, 0.38, -0.25), Color3.fromRGB(255, 140, 40))
end

SHAPES.Sock = function(b)
	box(b, Vector3.new(0.8, 1.4, 0.65), at(0, 0.35, 0.25), b.c1, M.Fabric)
	box(b, Vector3.new(0.8, 0.6, 1.4), at(0, -0.55, -0.15), b.c1, M.Fabric)
	box(b, Vector3.new(0.84, 0.2, 0.69), at(0, 0.8, 0.25), b.c2, M.Fabric)
	box(b, Vector3.new(0.84, 0.2, 0.69), at(0, 0.35, 0.25), b.c2, M.Fabric)
	box(b, Vector3.new(0.84, 0.64, 0.3), at(0, -0.55, -0.75), b.c2, M.Fabric)
end

SHAPES.Mug = function(b)
	cyl(b, 1.3, 1.15, at(0, -0.1, 0), b.c1)
	cyl(b, 0.05, 1.0, at(0, 0.56, 0), b.c2)
	box(b, Vector3.new(0.18, 0.18, 0.5), at(0, 0.3, 0.7), b.c1)
	box(b, Vector3.new(0.18, 0.7, 0.18), at(0, -0.05, 0.9), b.c1)
	box(b, Vector3.new(0.18, 0.18, 0.5), at(0, -0.4, 0.7), b.c1)
end

SHAPES.Chalice = function(b)
	cyl(b, 0.15, 1.15, at(0, -1.05, 0), b.c1, M.Metal)
	cyl(b, 1.0, 0.25, at(0, -0.45, 0), b.c1, M.Metal)
	ball(b, 0.4, at(0, -0.3, 0), b.c1, M.Metal)
	cyl(b, 0.95, 1.25, at(0, 0.45, 0), b.c1, M.Metal)
	blob(b, Vector3.new(1.25, 0.5, 1.25), at(0, -0.05, 0), b.c1, M.Metal)
	ball(b, 0.32, at(0, 0.45, -0.6), b.c2, M.Glass)
	ball(b, 0.32, at(0, 0.45, 0.6), b.c2, M.Glass)
end

SHAPES.Frog = function(b)
	blob(b, Vector3.new(1.6, 0.95, 1.5), at(0, -0.35, 0), b.c1, M.Marble)
	ball(b, 0.5, at(-0.42, 0.18, -0.4), b.c1, M.Marble)
	ball(b, 0.5, at(0.42, 0.18, -0.4), b.c1, M.Marble)
	eyes(b, 0.42, at(0, 0.24, -0.6), 0.2)
	blob(b, Vector3.new(0.5, 0.35, 1.0), at(-0.75, -0.65, 0.15), b.c2, M.Marble)
	blob(b, Vector3.new(0.5, 0.35, 1.0), at(0.75, -0.65, 0.15), b.c2, M.Marble)
	box(b, Vector3.new(0.7, 0.06, 0.06), at(0, -0.12, -0.74), BLACK)
end

SHAPES.Watch = function(b)
	disc(b, 0.3, 1.6, at(0, -0.1, 0), b.c1, M.Metal)
	disc(b, 0.32, 1.3, at(0, -0.1, 0), b.c2)
	box(b, Vector3.new(0.08, 0.5, 0.36), at(0, 0.1, 0), BLACK)
	box(b, Vector3.new(0.38, 0.08, 0.36), at(0.15, -0.1, 0), BLACK)
	cyl(b, 0.3, 0.25, at(0, 0.82, 0), b.c1, M.Metal)
	disc(b, 0.12, 0.42, at(0, 1.05, 0), b.c1, M.Metal)
end

SHAPES.Scroll = function(b)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	finish(b, p, Vector3.new(1.9, 0.6, 0.6), at(0, 0, 0), b.c1, M.Fabric)
	local c1 = Instance.new("Part")
	c1.Shape = Enum.PartType.Cylinder
	finish(b, c1, Vector3.new(0.2, 0.75, 0.75), at(-1.0, 0, 0), b.c2, M.Wood)
	local c2 = Instance.new("Part")
	c2.Shape = Enum.PartType.Cylinder
	finish(b, c2, Vector3.new(0.2, 0.75, 0.75), at(1.0, 0, 0), b.c2, M.Wood)
	box(b, Vector3.new(0.25, 0.64, 0.64), at(0, 0, 0), Color3.fromRGB(200, 40, 50), M.Fabric)
end

SHAPES.Mask = function(b)
	blob(b, Vector3.new(1.45, 1.85, 0.45), at(0, 0, 0), b.c1, M.Wood)
	box(b, Vector3.new(0.35, 0.18, 0.1), at(-0.33, 0.25, -0.22, 0, 0, -12), BLACK)
	box(b, Vector3.new(0.35, 0.18, 0.1), at(0.33, 0.25, -0.22, 0, 0, 12), BLACK)
	box(b, Vector3.new(0.6, 0.12, 0.1), at(0, -0.45, -0.21), BLACK)
	for i = -2, 2 do
		wedge(b, Vector3.new(0.12, 0.7, 0.35), at(i * 0.28, 1.1, 0, 0, 90, i * 12), b.c2, M.Neon)
	end
end

SHAPES.Flask = function(b)
	ball(b, 1.4, at(0, -0.45, 0), Color3.fromRGB(220, 240, 255), M.Glass)
	ball(b, 1.05, at(0, -0.5, 0), b.c1, M.Neon)
	cyl(b, 0.95, 0.45, at(0, 0.6, 0), Color3.fromRGB(220, 240, 255), M.Glass)
	cyl(b, 0.3, 0.5, at(0, 1.15, 0), Color3.fromRGB(150, 100, 60), M.Wood)
	ball(b, 0.25, at(0.2, 0.2, -0.1), b.c1, M.Neon)
end

SHAPES.Helmet = function(b)
	blob(b, Vector3.new(1.6, 1.3, 1.7), at(0, 0.1, 0), b.c1, M.Metal)
	cyl(b, 0.16, 2.0, at(0, -0.35, 0), b.c1, M.Metal)
	box(b, Vector3.new(0.22, 0.6, 1.4), at(0, 0.85, 0.05), b.c2, M.Fabric)
	box(b, Vector3.new(0.9, 0.12, 0.2), at(0, -0.1, -0.8), b.c2, M.Metal)
end

SHAPES.Ring = function(b)
	ring(b, 0.75, 0.28, 12, at(0, -0.2, 0, 90, 0, 0), b.c1, M.Metal)
	gem(b, 0.55, at(0, 0.75, 0), b.c2, b.c2)
	box(b, Vector3.new(0.5, 0.2, 0.3), at(0, 0.45, 0), b.c1, M.Metal)
end

SHAPES.Medal = function(b)
	box(b, Vector3.new(0.65, 0.95, 0.1), at(0, 0.6, 0), b.c2, M.Fabric)
	disc(b, 0.18, 1.1, at(0, -0.25, 0), b.c1, M.Metal)
	ball(b, 0.38, at(0, -0.25, -0.1), b.c1:Lerp(WHITE, 0.3), M.Neon)
	box(b, Vector3.new(0.75, 0.15, 0.15), at(0, 0.15, 0), b.c1, M.Metal)
end

SHAPES.Radio = function(b)
	box(b, Vector3.new(0.85, 1.5, 0.45), at(0, -0.15, 0), b.c1)
	cyl(b, 1.0, 0.12, at(0.25, 1.1, 0), b.c1, M.Metal)
	box(b, Vector3.new(0.6, 0.5, 0.05), at(0, -0.4, -0.24), BLACK, M.Fabric)
	box(b, Vector3.new(0.5, 0.25, 0.05), at(0, 0.25, -0.24), b.c2, M.Neon)
	ball(b, 0.18, at(-0.25, 0.65, -0.2), Color3.fromRGB(255, 60, 60), M.Neon)
end

SHAPES.Chip = function(b)
	box(b, Vector3.new(1.8, 0.15, 1.8), at(0, 0, 0, 20, 0, 0), b.c1)
	box(b, Vector3.new(0.8, 0.22, 0.8), at(0, 0.05, 0, 20, 0, 0), BLACK)
	for i = -1, 1 do
		box(b, Vector3.new(0.12, 0.06, 0.4), at(i * 0.5, 0.0, 0, 20, 0, 0) * CFrame.new(0, 0, 1.05), b.c2, M.Metal)
		box(b, Vector3.new(0.12, 0.06, 0.4), at(i * 0.5, 0.0, 0, 20, 0, 0) * CFrame.new(0, 0, -1.05), b.c2, M.Metal)
	end
	box(b, Vector3.new(0.15, 0.25, 0.15), at(0.6, 0.1, 0.5, 20, 0, 0), b.c2, M.Neon)
end

SHAPES.Crystal = function(b)
	box(b, Vector3.new(0.65, 2.0, 0.65), at(0, 0.05, 0, 0, 45, 0), b.c1, M.Neon)
	box(b, Vector3.new(0.5, 1.4, 0.5), at(0.45, -0.25, 0.1, 0, 30, -25), b.c2, M.Glass)
	box(b, Vector3.new(0.45, 1.2, 0.45), at(-0.42, -0.35, -0.1, 0, 60, 28), b.c1, M.Glass)
	box(b, Vector3.new(0.4, 0.9, 0.4), at(0.05, -0.5, 0.45, 25, 15, 0), b.c2, M.Neon)
	rock(b, 0.6, at(0, -0.85, 0), Color3.fromRGB(70, 70, 80), M.Slate)
end

SHAPES.Scarab = function(b)
	blob(b, Vector3.new(1.3, 0.7, 1.7), at(0, -0.2, 0.15), b.c1, M.Glass)
	blob(b, Vector3.new(0.75, 0.5, 0.6), at(0, -0.25, -0.85), b.c2, M.Metal)
	box(b, Vector3.new(0.06, 0.72, 1.6), at(0, -0.15, 0.15), b.c2, M.Metal)
	for side = -1, 1, 2 do
		for i = -1, 1 do
			box(b, Vector3.new(0.6, 0.08, 0.08), at(side * 0.75, -0.45, i * 0.45, 0, i * 20 * side, side * -25), b.c2, M.Metal)
		end
	end
	box(b, Vector3.new(0.08, 0.08, 0.5), at(-0.18, -0.15, -1.25, 0, -20, 0), b.c2, M.Metal)
	box(b, Vector3.new(0.08, 0.08, 0.5), at(0.18, -0.15, -1.25, 0, 20, 0), b.c2, M.Metal)
end

SHAPES.Core = function(b)
	ball(b, 1.1, at(0, 0, 0), b.c1, M.Neon)
	ring(b, 0.85, 0.14, 12, at(0, 0, 0, 90, 0, 0), b.c2, M.Metal)
	ring(b, 0.85, 0.14, 12, at(0, 0, 0, 90, 90, 0), b.c2, M.Metal)
	ring(b, 0.95, 0.12, 12, at(0, 0, 0, 0, 0, 0), b.c2, M.Metal)
	cyl(b, 0.25, 1.2, at(0, -1.0, 0), b.c2, M.Metal)
end

SHAPES.Egg = function(b)
	blob(b, Vector3.new(1.45, 1.95, 1.45), at(0, 0, 0), b.c1, M.Marble)
	ball(b, 0.38, at(0.45, 0.35, -0.48), b.c2, M.Marble)
	ball(b, 0.3, at(-0.5, -0.1, -0.45), b.c2, M.Marble)
	ball(b, 0.34, at(0.1, -0.55, -0.6), b.c2, M.Marble)
	ball(b, 0.28, at(-0.2, 0.6, 0.55), b.c2, M.Marble)
end

SHAPES.Rock = function(b)
	rock(b, 1.0, at(0, 0, 0), b.c1, M.Slate)
	ball(b, 0.35, at(0.3, 0.45, -0.5), b.c2, M.Slate)
	ball(b, 0.25, at(-0.4, 0.1, -0.6), b.c2, M.Slate)
end

SHAPES.Horn = function(b)
	local diameters = { 0.75, 0.62, 0.5, 0.38, 0.28 }
	for i, d in diameters do
		cyl(b, 0.6, d, at(-0.9 + i * 0.32, (i - 3) ^ 2 * -0.09 + 0.2, 0, 0, 0, 90 - (i - 3) * 18), b.c1, M.Marble)
	end
	cyl(b, 0.15, 0.82, at(-0.62, -0.15, 0, 0, 0, 125), b.c2, M.Metal)
	cyl(b, 0.15, 0.36, at(0.7, -0.15, 0, 0, 0, 55), b.c2, M.Metal)
end

SHAPES.Cat = function(b)
	blob(b, Vector3.new(1.1, 1.5, 1.2), at(0, -0.35, 0.1), b.c1, M.Marble)
	ball(b, 0.85, at(0, 0.65, -0.1), b.c1, M.Marble)
	wedge(b, Vector3.new(0.12, 0.45, 0.3), at(-0.25, 1.15, -0.1), b.c1, M.Marble)
	wedge(b, Vector3.new(0.12, 0.45, 0.3), at(0.25, 1.15, -0.1), b.c1, M.Marble)
	eyes(b, 0.18, at(0, 0.72, -0.48), 0.15, Color3.fromRGB(120, 255, 120), M.Neon)
	ring(b, 0.42, 0.12, 8, at(0, 0.28, -0.08), b.c2, M.Metal)
	ball(b, 0.2, at(0, 0.2, -0.55), b.c2, M.Neon)
	cyl(b, 0.25, 1.4, at(0, -1.1, 0.1), b.c2, M.Metal)
end

SHAPES.Painting = function(b)
	box(b, Vector3.new(2.3, 1.75, 0.18), at(0, 0, 0), b.c1, M.Wood)
	box(b, Vector3.new(1.95, 1.4, 0.2), at(0, 0, 0), b.c2)
	blob(b, Vector3.new(0.55, 0.72, 0.05), at(0, 0.2, -0.1), SKIN)
	blob(b, Vector3.new(0.85, 0.9, 0.04), at(0, 0.25, -0.08), Color3.fromRGB(60, 40, 30))
	box(b, Vector3.new(0.9, 0.55, 0.05), at(0, -0.45, -0.1), Color3.fromRGB(40, 30, 30))
	box(b, Vector3.new(0.18, 0.04, 0.03), at(0, 0.08, -0.13), Color3.fromRGB(180, 80, 80))
end

SHAPES.Gem = function(b)
	gem(b, 1.25, at(0, 0, 0), b.c1, b.c2)
	cyl(b, 0.15, 0.9, at(0, 0.72, 0), b.c1, M.Glass)
end

SHAPES.BigGem = function(b)
	gem(b, 1.55, at(0, 0.1, 0), b.c1, b.c2)
	ring(b, 1.2, 0.1, 14, at(0, -0.35, 0), Color3.fromRGB(230, 230, 240), M.Metal)
	cyl(b, 0.2, 1.4, at(0, -1.05, 0), Color3.fromRGB(230, 230, 240), M.Metal)
end

SHAPES.Bar = function(b)
	box(b, Vector3.new(1.4, 0.6, 0.8), at(0, 0, 0), b.c1, M.Foil)
	wedge(b, Vector3.new(0.8, 0.6, 0.25), at(-0.82, 0, 0, 0, -90, 0), b.c1, M.Foil)
	wedge(b, Vector3.new(0.8, 0.6, 0.25), at(0.82, 0, 0, 0, 90, 0), b.c1, M.Foil)
	box(b, Vector3.new(0.6, 0.05, 0.4), at(0, 0.31, 0), b.c2, M.Metal)
	box(b, Vector3.new(1.4, 0.6, 0.8), at(0.15, 0.6, 0.1, 0, 12, 0), b.c1, M.Foil)
end

SHAPES.Skull = function(b)
	ball(b, 1.55, at(0, 0.25, 0.05), b.c1, M.Glass)
	box(b, Vector3.new(1.0, 0.5, 0.95), at(0, -0.5, -0.15), b.c1, M.Glass)
	ball(b, 0.42, at(-0.32, 0.18, -0.6), b.c2, M.Neon)
	ball(b, 0.42, at(0.32, 0.18, -0.6), b.c2, M.Neon)
	wedge(b, Vector3.new(0.2, 0.25, 0.15), at(0, -0.15, -0.7), BLACK)
	for i = -2, 2 do
		box(b, Vector3.new(0.12, 0.18, 0.05), at(i * 0.16, -0.48, -0.64), WHITE)
	end
end

SHAPES.Idol = function(b)
	box(b, Vector3.new(1.4, 0.3, 1.1), at(0, -1.05, 0), b.c1, M.Foil)
	box(b, Vector3.new(1.0, 1.25, 0.8), at(0, -0.3, 0), b.c1, M.Foil)
	box(b, Vector3.new(1.15, 0.95, 0.95), at(0, 0.8, 0), b.c1, M.Foil)
	box(b, Vector3.new(0.28, 0.14, 0.05), at(-0.25, 0.9, -0.48), b.c2, M.Neon)
	box(b, Vector3.new(0.28, 0.14, 0.05), at(0.25, 0.9, -0.48), b.c2, M.Neon)
	box(b, Vector3.new(0.5, 0.1, 0.05), at(0, 0.55, -0.48), BLACK)
	wedge(b, Vector3.new(1.15, 0.4, 0.4), at(0, 1.45, 0), b.c1, M.Foil)
	box(b, Vector3.new(1.3, 0.12, 0.85), at(0, 0.2, 0), b.c2, M.Metal)
end

SHAPES.Heart = function(b)
	ball(b, 1.05, at(-0.36, 0.3, 0), b.c1, M.Neon)
	ball(b, 1.05, at(0.36, 0.3, 0), b.c1, M.Neon)
	box(b, Vector3.new(1.05, 1.05, 0.9), at(0, -0.12, 0, 0, 0, 45), b.c1, M.Neon)
	ball(b, 1.25, at(-0.36, 0.3, 0.05), b.c2, M.Glass)
	ball(b, 1.25, at(0.36, 0.3, 0.05), b.c2, M.Glass)
end

SHAPES.Feather = function(b)
	cyl(b, 2.3, 0.08, at(0, 0, 0, 0, 0, -18), b.c2, M.Plastic)
	for i = 0, 6 do
		local f = i / 6
		local color = b.c1:Lerp(b.c2, f)
		local cf = at(0, 0, 0, 0, 0, -18) * CFrame.new(0, -0.8 + i * 0.3, 0)
		local width = 0.9 * math.sin((f * 0.85 + 0.1) * math.pi)
		box(b, Vector3.new(width, 0.32, 0.05), cf * CFrame.new(width / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(25)), color, M.Neon)
		box(b, Vector3.new(width, 0.32, 0.05), cf * CFrame.new(-width / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(-25)), color, M.Neon)
	end
end

SHAPES.Scepter = function(b)
	cyl(b, 2.3, 0.22, at(0, -0.15, 0), b.c1, M.Metal)
	ball(b, 0.7, at(0, 1.15, 0), b.c2, M.Neon)
	ring(b, 0.38, 0.1, 8, at(0, 0.82, 0), b.c1, M.Metal)
	ball(b, 0.32, at(0, -1.3, 0), b.c1, M.Metal)
	for i = 1, 4 do
		wedge(b, Vector3.new(0.08, 0.4, 0.25), CFrame.Angles(0, i * math.pi / 2, 0) * at(0, 1.55, -0.2), b.c1, M.Metal)
	end
end

SHAPES.Jar = function(b)
	cyl(b, 1.7, 1.3, at(0, -0.1, 0), Color3.fromRGB(210, 240, 255), M.Glass)
	cyl(b, 0.25, 1.4, at(0, 0.85, 0), Color3.fromRGB(120, 130, 140), M.Metal)
	cyl(b, 0.2, 1.4, at(0, -1.0, 0), Color3.fromRGB(120, 130, 140), M.Metal)
	blob(b, Vector3.new(0.8, 0.95, 0.7), at(0, -0.25, 0), b.c1, M.Neon)
	ball(b, 0.22, at(-0.15, -0.05, -0.3), BLACK)
	ball(b, 0.22, at(0.15, -0.05, -0.3), BLACK)
end

SHAPES.Briefcase = function(b)
	box(b, Vector3.new(1.9, 1.35, 0.5), at(0, -0.2, 0), b.c1, M.Fabric)
	box(b, Vector3.new(0.12, 0.35, 0.12), at(-0.35, 0.65, 0), b.c2, M.Metal)
	box(b, Vector3.new(0.12, 0.35, 0.12), at(0.35, 0.65, 0), b.c2, M.Metal)
	box(b, Vector3.new(0.82, 0.12, 0.14), at(0, 0.8, 0), b.c2, M.Metal)
	box(b, Vector3.new(0.25, 0.18, 0.05), at(-0.55, 0.25, -0.26), b.c2, M.Metal)
	box(b, Vector3.new(0.25, 0.18, 0.05), at(0.55, 0.25, -0.26), b.c2, M.Metal)
	box(b, Vector3.new(1.92, 0.08, 0.52), at(0, 0.0, 0), b.c2, M.Metal)
end

SHAPES.Compass = function(b)
	cyl(b, 0.28, 1.7, at(0, -0.1, 0, -55, 0, 0), b.c1, M.Metal)
	cyl(b, 0.3, 1.35, at(0, -0.1, 0, -55, 0, 0), b.c2)
	local face = at(0, -0.1, 0, -55, 0, 0) * CFrame.new(0, 0.18, 0)
	wedge(b, Vector3.new(0.12, 0.08, 0.55), face * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(230, 40, 40), M.Neon)
	wedge(b, Vector3.new(0.12, 0.08, 0.55), face * CFrame.new(0, 0, 0.3), WHITE)
	ball(b, 0.16, face, b.c1, M.Metal)
	disc(b, 0.15, 0.35, at(0, 0.75, -0.6, -55, 0, 0), b.c1, M.Metal)
end

SHAPES.Crown = function(b)
	crownShape(b, b.c1, b.c2, M.Foil)
end

SHAPES.ThiefCrown = function(b)
	crownShape(b, b.c1, b.c2, M.Metal)
	ring(b, 0.88, 0.12, 12, at(0, -0.1, 0), b.c2, M.Neon)
	gem(b, 0.45, at(0, 0.1, -0.95), Color3.fromRGB(255, 40, 60), Color3.fromRGB(255, 120, 120))
end

SHAPES.Orb = function(b)
	ball(b, 1.4, at(0, 0.15, 0), b.c1, M.Neon)
	ball(b, 1.85, at(0, 0.15, 0), b.c2, M.Glass)
	cyl(b, 0.3, 1.0, at(0, -0.95, 0), Color3.fromRGB(90, 70, 60), M.Wood)
	ring(b, 0.55, 0.15, 8, at(0, -0.72, 0), b.c2, M.Metal)
end

SHAPES.PharaohMask = function(b)
	blob(b, Vector3.new(1.25, 1.6, 0.65), at(0, 0, -0.1), b.c1, M.Foil)
	for i = 0, 4 do
		local color = (i % 2 == 0) and b.c2 or b.c1
		box(b, Vector3.new(0.35, 1.7 - i * 0.12, 0.6), at(-0.78, -0.15 - i * 0.05, 0.2, 0, 0, 8), color, M.Metal)
		box(b, Vector3.new(0.35, 1.7 - i * 0.12, 0.6), at(0.78, -0.15 - i * 0.05, 0.2, 0, 0, -8), color, M.Metal)
	end
	box(b, Vector3.new(1.55, 0.4, 1.0), at(0, 0.75, 0.15), b.c2, M.Metal)
	box(b, Vector3.new(0.25, 0.6, 0.25), at(0, -1.0, -0.2), b.c2, M.Metal)
	box(b, Vector3.new(0.3, 0.1, 0.05), at(-0.25, 0.2, -0.45), BLACK)
	box(b, Vector3.new(0.3, 0.1, 0.05), at(0.25, 0.2, -0.45), BLACK)
	ball(b, 0.22, at(0, 0.98, -0.3), b.c2, M.Neon)
end

SHAPES.Meteor = function(b)
	rock(b, 1.15, at(0, 0, 0), b.c1, M.Basalt)
	box(b, Vector3.new(0.08, 1.2, 0.08), at(0.2, 0.1, -0.68, 0, 0, 30), b.c2, M.Neon)
	box(b, Vector3.new(0.08, 0.9, 0.08), at(-0.35, -0.1, -0.62, 0, 0, -40), b.c2, M.Neon)
	box(b, Vector3.new(0.08, 0.7, 0.08), at(0.5, 0.3, 0.4, 20, 0, 60), b.c2, M.Neon)
	ball(b, 0.5, at(0, 0.0, 0), b.c2, M.Neon)
end

SHAPES.Toilet = function(b)
	cyl(b, 0.9, 1.25, at(0, -0.6, -0.15), b.c1, M.Foil)
	ring(b, 0.55, 0.16, 10, at(0, -0.12, -0.15), b.c2, M.Plastic)
	box(b, Vector3.new(1.25, 1.1, 0.45), at(0, 0.3, 0.65), b.c1, M.Foil)
	box(b, Vector3.new(1.3, 0.12, 0.5), at(0, 0.9, 0.65), b.c1, M.Foil)
	box(b, Vector3.new(0.3, 0.08, 0.1), at(-0.35, 0.65, 0.41), b.c2, M.Metal)
	blob(b, Vector3.new(0.9, 0.08, 1.0), at(0, -0.08, -0.2), BLACK)
end

SHAPES.SwordStone = function(b)
	rock(b, 0.85, at(0, -0.85, 0), b.c2, M.Slate)
	box(b, Vector3.new(0.14, 1.7, 0.36), at(0, 0.4, 0), b.c1, M.Metal)
	wedge(b, Vector3.new(0.14, 0.3, 0.36), at(0, -0.6, 0, 180, 0, 0), b.c1, M.Metal)
	box(b, Vector3.new(0.18, 0.15, 1.0), at(0, 1.25, 0), Color3.fromRGB(255, 200, 60), M.Metal)
	cyl(b, 0.5, 0.16, at(0, 1.55, 0), Color3.fromRGB(110, 60, 40), M.Fabric)
	ball(b, 0.26, at(0, 1.85, 0), Color3.fromRGB(80, 160, 255), M.Neon)
end

SHAPES.VoidOrb = function(b)
	ball(b, 1.3, at(0, 0.1, 0), b.c1, M.Plastic)
	ball(b, 1.75, at(0, 0.1, 0), b.c2, M.FF)
	ring(b, 1.05, 0.08, 16, at(0, 0.1, 0, 20, 0, 15), b.c2, M.Neon)
	ring(b, 1.15, 0.06, 16, at(0, 0.1, 0, -30, 0, -20), b.c2, M.Neon)
end

SHAPES.StormOrb = function(b)
	ball(b, 1.85, at(0, 0.1, 0), b.c2, M.Glass)
	ball(b, 0.85, at(0, 0.1, 0), b.c1, M.Neon)
	box(b, Vector3.new(0.06, 0.6, 0.06), at(0.25, 0.45, 0, 0, 0, 30), b.c2, M.Neon)
	box(b, Vector3.new(0.06, 0.55, 0.06), at(-0.3, -0.2, 0.1, 0, 0, -35), b.c2, M.Neon)
	box(b, Vector3.new(0.06, 0.5, 0.06), at(0.1, -0.3, -0.35, 40, 0, 10), b.c2, M.Neon)
	cyl(b, 0.3, 1.0, at(0, -0.95, 0), Color3.fromRGB(50, 55, 70), M.Metal)
end

SHAPES.Hourglass = function(b)
	cyl(b, 0.2, 1.45, at(0, 1.05, 0), b.c1, M.Foil)
	cyl(b, 0.2, 1.45, at(0, -1.05, 0), b.c1, M.Foil)
	blob(b, Vector3.new(1.0, 0.95, 1.0), at(0, 0.48, 0), Color3.fromRGB(220, 240, 255), M.Glass)
	blob(b, Vector3.new(1.0, 0.95, 1.0), at(0, -0.48, 0), Color3.fromRGB(220, 240, 255), M.Glass)
	blob(b, Vector3.new(0.6, 0.35, 0.6), at(0, 0.35, 0), b.c2, M.Neon)
	blob(b, Vector3.new(0.75, 0.45, 0.75), at(0, -0.65, 0), b.c2, M.Neon)
	for i = 1, 3 do
		local angle = i / 3 * math.pi * 2
		cyl(b, 2.0, 0.1, CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -0.62), b.c1, M.Foil)
	end
end

SHAPES.Pearl = function(b)
	blob(b, Vector3.new(1.9, 0.45, 1.5), at(0, -0.55, 0), b.c2, M.Marble)
	blob(b, Vector3.new(1.9, 0.4, 1.5), at(0, 0.45, 0.45, -40, 0, 0), b.c2, M.Marble)
	local pearl = ball(b, 0.95, at(0, -0.1, -0.1), b.c1, M.Plastic)
	pearl.Reflectance = 0.35
end

SHAPES.Chicken = function(b)
	blob(b, Vector3.new(1.0, 0.95, 1.7), at(0, -0.3, 0.2), b.c1)
	cyl(b, 1.0, 0.36, at(0, 0.35, -0.45, -25, 0, 0), b.c1)
	ball(b, 0.62, at(0, 0.85, -0.7), b.c1)
	wedge(b, Vector3.new(0.3, 0.2, 0.45), at(0, 0.8, -1.12, 0, 180, 0), b.c2)
	box(b, Vector3.new(0.08, 0.3, 0.4), at(0, 1.2, -0.68), Color3.fromRGB(240, 40, 40))
	eyes(b, 0.18, at(0, 0.95, -0.95), 0.1)
	cyl(b, 0.7, 0.08, at(-0.25, -1.0, 0.25), b.c2)
	cyl(b, 0.7, 0.08, at(0.25, -1.0, 0.25), b.c2)
end

SHAPES.Banana = function(b)
	for i = 0, 5 do
		local angle = (i - 2.5) * 16
		local cf = CFrame.Angles(0, 0, math.rad(angle)) * CFrame.new(0, -1.1, 0)
		local d = 0.5 - math.abs(i - 2.5) * 0.05
		cyl(b, 0.42, d, cf * CFrame.Angles(0, 0, math.rad(90)), b.c1)
	end
	ball(b, 0.2, CFrame.Angles(0, 0, math.rad(-48)) * CFrame.new(0, -1.1, 0), b.c2)
	ball(b, 0.2, CFrame.Angles(0, 0, math.rad(48)) * CFrame.new(0, -1.1, 0), b.c2)
	eyes(b, 0.13, at(0, -1.0, -0.2), 0.12, Color3.fromRGB(200, 40, 255), M.Neon)
	box(b, Vector3.one * 0.05, at(0, 0.6, 0), b.c1)
end

SHAPES.Sun = function(b)
	ball(b, 1.45, at(0, 0, 0), b.c1, M.Neon)
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		wedge(b, Vector3.new(0.12, 0.55, 0.3), CFrame.Angles(0, 0, angle) * CFrame.new(0, 1.0, 0), b.c2, M.Neon)
	end
	ball(b, 1.7, at(0, 0, 0), b.c2, M.FF)
end

SHAPES.GlitchCube = function(b)
	box(b, Vector3.one * 1.3, at(0.08, 0, 0, 0, 12, 0), b.c1, M.Neon).Transparency = 0.35
	box(b, Vector3.one * 1.3, at(-0.08, 0.05, 0, 0, 12, 0), b.c2, M.Neon).Transparency = 0.35
	box(b, Vector3.one * 1.2, at(0, 0, 0, 0, 12, 0), BLACK, M.Plastic)
	box(b, Vector3.new(1.4, 0.1, 0.4), at(0.4, 0.3, -0.5), WHITE, M.Neon)
	box(b, Vector3.new(0.5, 0.1, 1.4), at(-0.3, -0.4, 0.2), b.c2, M.Neon)
end

SHAPES.VoidEgg = function(b)
	blob(b, Vector3.new(1.35, 1.85, 1.35), at(0, 0, 0), b.c1, M.Plastic)
	blob(b, Vector3.new(1.7, 2.2, 1.7), at(0, 0, 0), b.c2, M.FF)
	box(b, Vector3.new(0.06, 0.7, 0.06), at(0.2, 0.2, -0.66, 0, 0, 25), b.c2, M.Neon)
	box(b, Vector3.new(0.06, 0.5, 0.06), at(0.0, -0.2, -0.68, 0, 0, -35), b.c2, M.Neon)
end

SHAPES.CookieJar = function(b)
	cyl(b, 1.6, 1.4, at(0, -0.15, 0), b.c1, M.Glass)
	cyl(b, 0.25, 1.5, at(0, 0.75, 0), Color3.fromRGB(250, 240, 230), M.Marble)
	ball(b, 0.4, at(0, 1.0, 0), Color3.fromRGB(250, 240, 230), M.Marble)
	for i = 0, 3 do
		cyl(b, 0.18, 0.75, at((i % 2) * 0.25 - 0.12, -0.75 + i * 0.25, 0, (i % 2) * 12, 0, (i % 2) * 10), b.c2)
	end
	box(b, Vector3.new(0.6, 0.35, 0.05), at(0, 0.1, -0.72), Color3.fromRGB(255, 120, 160))
end

SHAPES.Keyboard = function(b)
	box(b, Vector3.new(2.5, 0.25, 1.0), at(0, 0, 0, -20, 0, 0), b.c1, M.Plastic)
	local base = at(0, 0, 0, -20, 0, 0)
	for row = 0, 2 do
		for col = 0, 5 do
			local keyColor = (row + col) % 4 == 0 and b.c2 or Color3.fromRGB(70, 70, 85)
			box(b, Vector3.new(0.3, 0.14, 0.24), base * CFrame.new(-0.95 + col * 0.38, 0.17, -0.3 + row * 0.3), keyColor, (row + col) % 4 == 0 and M.Neon or M.Plastic)
		end
	end
	box(b, Vector3.new(1.4, 0.14, 0.18), base * CFrame.new(0, 0.17, 0.42), Color3.fromRGB(70, 70, 85))
end

local function buildShape(b: Builder, shape: string)
	local fn = SHAPES[shape] or SHAPES.Orb
	fn(b)
end

export type BuildOptions = {
	Scale: number?,
	Anchored: boolean?,
	Name: string?,
}

-- Builds an artifact model centered on the origin. Use model:PivotTo() to place it.
function ArtifactModels.build(artifactId: string, mutation: string?, options: BuildOptions?): Model
	local opts = options or {}
	local def = Artifacts.get(artifactId)
	local model = Instance.new("Model")
	model.Name = opts.Name or (def and def.Name) or "Artifact"

	local b: Builder = {
		model = model,
		c1 = def and def.C1 or Color3.new(1, 1, 1),
		c2 = def and def.C2 or Color3.new(0.5, 0.5, 0.5),
		parts = {},
	}
	buildShape(b, def and def.Shape or "Orb")

	if mutation == "Shiny" then
		for _, p in b.parts do
			if p.Material ~= M.Neon and p.Material ~= M.Glass and p.Material ~= M.FF then
				p.Reflectance = 0.3
				p.Color = p.Color:Lerp(Color3.fromRGB(255, 250, 210), 0.25)
			end
		end
	end

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Size = Vector3.new(2.6, 2.6, 2.6)
	core.CFrame = CFrame.new()
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = false
	core.Massless = true
	core.Parent = model
	model.PrimaryPart = core

	local scale = opts.Scale or 1
	if scale ~= 1 then
		model:ScaleTo(scale)
	end

	if opts.Anchored == false then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = false
			end
		end
	end

	model:SetAttribute("ArtifactId", artifactId)
	model:SetAttribute("Rarity", def and def.Rarity or "Common")
	if mutation then
		model:SetAttribute("Mutation", mutation)
	end
	return model
end

-- Welds every part of a built model to its Core (for carried / physics use).
function ArtifactModels.weldToCore(model: Model)
	local core = model.PrimaryPart
	if not core then
		return
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= core then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = core
			weld.Part1 = p
			weld.Parent = p
			p.Anchored = false
		end
	end
	core.Anchored = false
end

ArtifactModels.Shapes = SHAPES

return ArtifactModels
