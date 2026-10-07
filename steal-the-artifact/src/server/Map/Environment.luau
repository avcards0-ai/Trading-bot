--[[
	Environment
	Ground, terrain coastline (beach, ocean, hills), roads with sidewalks and street lights,
	lighting/post-processing, the world border and the wild scenery around the city edge.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Zones = require(ReplicatedStorage.Shared.Config.Zones)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local Props = require(script.Parent.Props)

local rgb = Kit.rgb

local Environment = {}

Environment.GrassColor = rgb(94, 126, 62)

export type TerrainPlan = {
	Mounds: { { Center: Vector3, Radius: number, Height: number } },
	Paths: { { A: Vector3, B: Vector3, Width: number } },
}

local TERRAIN_COLORS = {
	{ Enum.Material.Grass, rgb(94, 126, 62) },
	{ Enum.Material.LeafyGrass, rgb(80, 110, 54) },
	{ Enum.Material.Ground, rgb(106, 94, 74) },
	{ Enum.Material.Mud, rgb(82, 68, 56) },
	{ Enum.Material.Sand, rgb(190, 172, 132) },
	{ Enum.Material.Rock, rgb(112, 110, 106) },
}

-- Soft, large patches of lush and dry grass so the ground never reads as one flat color.
local function surfaceMaterial(x: number, z: number): Enum.Material
	local n = math.noise(x / 110, z / 110, 0.31) + 0.5 * math.noise(x / 37, z / 37, 2.7)
	if n > 0.36 then
		return Enum.Material.LeafyGrass
	elseif n < -0.5 then
		return Enum.Material.Ground
	end
	return Enum.Material.Grass
end

local function segmentDistance(px: number, pz: number, a: Vector3, b: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local lengthSq = abx * abx + abz * abz
	local t = if lengthSq > 0 then math.clamp(((px - a.X) * abx + (pz - a.Z) * abz) / lengthSq, 0, 1) else 0
	local dx, dz = px - (a.X + abx * t), pz - (a.Z + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- Ground cover -----------------------------------------------------------------------------------
-- The place file turns on Terrain.Decoration, so Grass terrain grows animated blades. Blades
-- would poke straight up through thin floors, so the ground under any low, flat part (roads,
-- sidewalks, plazas, floors, paths) is leafy grass instead, which grows none. So is the shade
-- under each tree's crown, with bare soil around the trunk.

local COVER_RES = 4
local LUSH, SOIL = 1, 2

local function coverCell(x: number, z: number): number
	return (math.floor(x / COVER_RES) + 2048) * 4096 + math.floor(z / COVER_RES) + 2048
end

local function markCircle(cover: { [number]: number }, x: number, z: number, radius: number, value: number)
	for gx = math.floor((x - radius) / COVER_RES), math.floor((x + radius) / COVER_RES) do
		for gz = math.floor((z - radius) / COVER_RES), math.floor((z + radius) / COVER_RES) do
			local cx, cz = (gx + 0.5) * COVER_RES, (gz + 0.5) * COVER_RES
			if (cx - x) ^ 2 + (cz - z) ^ 2 <= radius * radius then
				local key = (gx + 2048) * 4096 + gz + 2048
				cover[key] = math.max(cover[key] or 0, value)
			end
		end
	end
end

-- Marks every terrain column a low, flat part sits on (any quarter of the column will do).
local function markPart(cover: { [number]: number }, part: BasePart)
	local cf, size = part.CFrame, part.Size
	local c = cf.Position
	local axes = { cf.RightVector, cf.UpVector, -cf.LookVector }
	local half = { size.X / 2, size.Y / 2, size.Z / 2 }
	local ex, ey, ez = 0, 0, 0
	local vertical = 1
	for k = 1, 3 do
		ex += math.abs(axes[k].X) * half[k]
		ey += math.abs(axes[k].Y) * half[k]
		ez += math.abs(axes[k].Z) * half[k]
		if math.abs(axes[k].Y) > math.abs(axes[vertical].Y) then
			vertical = k
		end
	end
	if c.Y - ey > 0.6 or c.Y + ey < -0.2 or c.Y + ey > 2.2 or math.min(ex, ez) < 0.4 then
		return -- not lying on the ground, or too slim to matter
	end
	local a, b = if vertical == 1 then 2 else 1, if vertical == 3 then 2 else 3
	local round = (part:IsA("Part") and part.Shape == Enum.PartType.Cylinder and vertical == 1)
		or (part:IsA("Part") and part.Shape == Enum.PartType.Ball)
	local radius = math.min(half[a], half[b])
	for gx = math.floor((c.X - ex) / COVER_RES), math.floor((c.X + ex) / COVER_RES) do
		for gz = math.floor((c.Z - ez) / COVER_RES), math.floor((c.Z + ez) / COVER_RES) do
			local key = (gx + 2048) * 4096 + gz + 2048
			if not cover[key] then
				for q = 0, 3 do
					local d = Vector3.new(
						(gx + 0.25 + (q % 2) * 0.5) * COVER_RES - c.X,
						0,
						(gz + 0.25 + math.floor(q / 2) * 0.5) * COVER_RES - c.Z
					)
					local u, v = d:Dot(axes[a]), d:Dot(axes[b])
					local inside = if round
						then u * u + v * v <= radius * radius
						else math.abs(u) <= half[a] and math.abs(v) <= half[b]
					if inside then
						cover[key] = LUSH
						break
					end
				end
			end
		end
	end
end

local function groundCover(root: Instance?): { [number]: number }
	local cover: { [number]: number } = {}
	if not root then
		return cover
	end
	local standIns = root:FindFirstChild("TerrainStandIns")
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			local shade = inst.Name == "Trunk" and inst.Parent and inst.Parent:GetAttribute("Shade")
			if type(shade) == "number" then
				local at = inst.CFrame.Position
				markCircle(cover, at.X, at.Z, shade, LUSH)
				markCircle(cover, at.X, at.Z, 2.2, SOIL)
			elseif inst.Transparency < 1 and not (standIns and inst:IsDescendantOf(standIns)) then
				markPart(cover, inst)
			end
		end
	end
	return cover
end

-- Writes the island surface voxel by voxel: hills, patchy grass and worn dirt paths.
local function sculptIsland(terrain: Terrain, plan: TerrainPlan, root: Instance?)
	local islandR = GameConfig.Map.WorldRadius + 6
	local res, chunk = COVER_RES, 128
	local cover = groundCover(root)
	for cx = -islandR, islandR, chunk do
		for cz = -islandR, islandR, chunk do
			local nearX = math.clamp(0, cx, cx + chunk)
			local nearZ = math.clamp(0, cz, cz + chunk)
			if nearX * nearX + nearZ * nearZ < islandR * islandR then
				local region = Region3.new(Vector3.new(cx, -8, cz), Vector3.new(cx + chunk, 8, cz + chunk))
					:ExpandToGrid(res)
				local corner = region.CFrame.Position - region.Size / 2
				-- Only test the hills and paths that can touch this chunk.
				local mounds, paths = {}, {}
				for _, mound in plan.Mounds do
					local c = mound.Center
					if
						c.X + mound.Radius > cx
						and c.X - mound.Radius < cx + chunk
						and c.Z + mound.Radius > cz
						and c.Z - mound.Radius < cz + chunk
					then
						table.insert(mounds, mound)
					end
				end
				for _, path in plan.Paths do
					local minX, maxX =
						math.min(path.A.X, path.B.X) - path.Width, math.max(path.A.X, path.B.X) + path.Width
					local minZ, maxZ =
						math.min(path.A.Z, path.B.Z) - path.Width, math.max(path.A.Z, path.B.Z) + path.Width
					if maxX > cx and minX < cx + chunk and maxZ > cz and minZ < cz + chunk then
						table.insert(paths, path)
					end
				end
				local materials, occupancies = terrain:ReadVoxels(region, res)
				local size = materials.Size
				for ix = 1, size.X do
					local x = corner.X + (ix - 0.5) * res
					for iz = 1, size.Z do
						local z = corner.Z + (iz - 0.5) * res
						if x * x + z * z < (islandR - 4) ^ 2 then
							local h = 0
							for _, mound in mounds do
								h = math.max(
									h,
									Layout.moundHeight(mound.Center, mound.Radius, mound.Height, Vector3.new(x, 0, z))
								)
							end
							local material = surfaceMaterial(x, z)
							for _, path in paths do
								local wobble = math.noise(x / 9, z / 9, 5.5) * 1.2
								if segmentDistance(x, z, path.A, path.B) < path.Width / 2 + wobble then
									material = Enum.Material.Ground
								end
							end
							if h > 1.5 and material == Enum.Material.Ground then
								material = Enum.Material.Grass -- hilltops stay green
							end
							local covered = cover[coverCell(x, z)]
							if covered == SOIL then
								material = Enum.Material.Ground
							elseif covered == LUSH and material == Enum.Material.Grass then
								material = Enum.Material.LeafyGrass
							end
							for iy = 1, size.Y do
								local y0 = corner.Y + (iy - 1) * res
								local occupancy = math.clamp((h - y0) / res, 0, 1)
								occupancies[ix][iy][iz] = occupancy
								materials[ix][iy][iz] = if occupancy <= 0
									then Enum.Material.Air
									elseif y0 < -res then Enum.Material.Ground
									else material
							end
						end
					end
				end
				terrain:WriteVoxels(region, res, materials, occupancies)
			end
		end
	end
end

-- Terrain only exists in a running server (it can't be saved into the place file from
-- outside Studio). It replaces the Ground stand-in parts with the real thing: ocean, beach,
-- hills ringing the island, and the island surface itself. `root` is the built map, which
-- decides where grass may grow blades.
function Environment.terrain(plan: TerrainPlan?, root: Instance?): boolean
	local terrain = workspace.Terrain
	local radius = GameConfig.Map.WorldRadius
	terrain:Clear()
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(2400, 8, 2400), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(0, -16, 0), Vector3.new(2400, 8, 2400), Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -7.5, 0), 12, radius + 70, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -6, 0), 12, radius + 12, Enum.Material.Grass)
	-- Rolling hills and rocky bluffs just outside the border wall.
	local rng = Random.new(42)
	for i = 1, 64 do
		local angle = i / 64 * math.pi * 2 + rng:NextNumber(-0.03, 0.03)
		local r = radius + rng:NextNumber(4, 30)
		local size = rng:NextNumber(34, 78)
		local material = (i % 5 == 0) and Enum.Material.Rock
			or (i % 3 == 0 and Enum.Material.LeafyGrass)
			or Enum.Material.Grass
		terrain:FillBall(Vector3.new(math.cos(angle) * r, -size * 0.45, math.sin(angle) * r), size, material)
		if i % 4 == 0 then
			local peak = size * rng:NextNumber(0.35, 0.55)
			terrain:FillBall(
				Vector3.new(math.cos(angle) * (r + 12), size * 0.15, math.sin(angle) * (r + 12)),
				peak,
				Enum.Material.Rock
			)
		end
	end
	for _, entry in TERRAIN_COLORS do
		terrain:SetMaterialColor(entry[1], entry[2])
	end
	if not plan then
		return false
	end
	local ok, err = pcall(sculptIsland, terrain, plan, root)
	if not ok then
		warn("[Map] Couldn't sculpt the island terrain (keeping it flat):", err)
	end
	return ok
end

-- Parts that stand in for the terrain in Studio's edit view (the server removes them once
-- the real terrain exists): the flat island, the hills and the worn paths.
function Environment.standIns(root: Instance): Folder
	return root:FindFirstChild("TerrainStandIns") :: Folder or Kit.folder("TerrainStandIns", root)
end

-- The walkable island: one big grass disc.
function Environment.ground(root: Instance)
	local radius = GameConfig.Map.WorldRadius + 6
	local ground = Kit.cyl(
		Environment.standIns(root),
		2,
		radius * 2,
		CFrame.new(0, -1, 0),
		Environment.GrassColor,
		Enum.Material.Grass,
		"Ground"
	)
	ground.CastShadow = false
	ground.CanTouch = false
	return ground
end

-- Decides where the land rises and where people have worn paths, before the scenery is
-- planted (so trees sit on the hills). Returns the plan the runtime terrain is built from.
function Environment.planTerrain(root: Instance): TerrainPlan
	local folder = Environment.standIns(root)
	local rng = Random.new(77)
	local radius = GameConfig.Map.WorldRadius
	local plan: TerrainPlan = { Mounds = {}, Paths = {} }

	-- A dirt trail looping through the woods behind the vaults
	local trail = {}
	local steps = 72
	for i = 0, steps - 1 do
		local angle = i / steps * math.pi * 2
		local r = radius - 74 + math.noise(i / 7, 0.5, 1.3) * 18
		table.insert(trail, Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r))
	end
	for i, a in trail do
		local b = trail[i % #trail + 1]
		local width = 4 + math.noise(i / 5, 2.2, 0) * 1.2
		table.insert(plan.Paths, { A = a, B = b, Width = width })
		Layout.addRoad(a, b, width / 2 + 1)
	end
	-- Shortcuts worn across Central Park's lawns
	local park = Vector3.new(-205, 0, 205)
	for _, pair in
		{
			{ park + Vector3.new(-52, 0, -18), park + Vector3.new(-96, 0, -76) },
			{ park + Vector3.new(40, 0, 30), park + Vector3.new(96, 0, 70) },
		}
	do
		table.insert(plan.Paths, { A = pair[1], B = pair[2], Width = 3.2 })
	end
	for _, path in plan.Paths do
		local delta = (path.B - path.A) * Vector3.new(1, 0, 1)
		local length = delta.Magnitude
		if length > 0.5 then
			local strip = Kit.block(
				folder,
				Vector3.new(path.Width, 0.06, length + 1),
				CFrame.lookAt(path.A, path.B) * CFrame.new(0, 0.03, -length / 2),
				rgb(106, 94, 74),
				Enum.Material.Ground,
				"Path"
			)
			Kit.detail(strip)
		end
	end

	-- Hills: rolling ground in the woods, a few low swells in open meadows
	local function addHill(center: Vector3, size: number, height: number)
		Layout.addMound(center, size, height)
		table.insert(plan.Mounds, { Center = center, Radius = size, Height = height })
		local hill = Kit.block(
			folder,
			Vector3.new(size * 1.6, height * 2, size * 1.6),
			CFrame.new(center.X, 0, center.Z),
			Environment.GrassColor,
			Enum.Material.Grass,
			"Hill"
		)
		Kit.detail(hill)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = hill
	end
	local placed = 0
	for _ = 1, 800 do
		if placed >= 28 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(radius - 125, radius - 40)
		local pos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		local size = rng:NextNumber(18, 34)
		if Layout.isFree(pos, size * 0.8, 2) and Layout.groundHeight(pos) == 0 then
			addHill(pos, size, rng:NextNumber(2.5, 7))
			placed += 1
		end
	end
	placed = 0
	for _ = 1, 600 do
		if placed >= 10 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(140, radius - 140)
		local pos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		local size = rng:NextNumber(16, 26)
		if Layout.isFree(pos, size * 0.85, 3) and Layout.groundHeight(pos) == 0 then
			addHill(pos, size, rng:NextNumber(1.5, 3.2))
			placed += 1
		end
	end
	return plan
end

-- Natural daylight: warm low-ish sun, cool sky fill, light haze. Post-processing is kept
-- subtle on purpose (no heavy bloom or saturation). The client's Day mood matches this.
function Environment.lighting()
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 34
	Lighting.Brightness = 2.2
	Lighting.Ambient = rgb(58, 60, 68)
	Lighting.OutdoorAmbient = rgb(118, 122, 134)
	Lighting.ColorShift_Top = rgb(255, 238, 214)
	Lighting.ColorShift_Bottom = rgb(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ShadowSoftness = 0.18
	Lighting.ExposureCompensation = 0

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.22
	atmosphere.Color = rgb(198, 207, 219)
	atmosphere.Decay = rgb(104, 112, 126)
	atmosphere.Glare = 0.12
	atmosphere.Haze = 1.1
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 11
	sky.MoonAngularSize = 9
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.12
	bloom.Size = 22
	bloom.Threshold = 2.2
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "WorldColor"
	color.Saturation = -0.05
	color.Contrast = 0.04
	color.Brightness = 0
	color.TintColor = rgb(255, 252, 247)
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.02
	rays.Spread = 0.4
	rays.Parent = Lighting
end

function Environment.clouds()
	if workspace.Terrain:FindFirstChildOfClass("Clouds") then
		return
	end
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.46
	clouds.Density = 0.55
	clouds.Color = rgb(242, 242, 246)
	clouds.Parent = workspace.Terrain
end

local ASPHALT = rgb(60, 61, 64)
local SIDEWALK = rgb(178, 174, 166)
local CURB = rgb(156, 152, 146)

type Gap = { Side: number, From: number, To: number } -- distances along the road

-- Road from `from` to `to` with lane markings, raised sidewalks (with optional gaps where
-- other roads join) and street lights every `lampSpacing` studs.
local function road(
	parent: Instance,
	from: Vector3,
	to: Vector3,
	width: number,
	options: {
		Sidewalk: number?,
		LampSpacing: number?,
		LampOffset: number?,
		Gaps: { Gap }?,
		Overlap: number?,
	}?
)
	local opts = options or {}
	local delta = to - from
	local length = delta.Magnitude
	if length < 1 then
		return
	end
	local cf = CFrame.lookAt((from + to) / 2, to)
	local sidewalk = opts.Sidewalk or 6
	Layout.addRoad(from, to, width / 2 + sidewalk)

	local asphalt = Kit.block(
		parent,
		Vector3.new(width, 0.4, length + (opts.Overlap or 0)),
		cf * CFrame.new(0, 0.05, 0),
		ASPHALT,
		Enum.Material.Asphalt,
		"Road"
	)
	asphalt.CastShadow = false
	local seed = Kit.seedOf(cf)
	-- Centre dashes: repainted at different times, so some are faded and a few worn away.
	local dashes = math.floor(length / 12)
	for i = 0, dashes - 1 do
		if not Props.chance(seed + i * 1.37, 0.07) then
			local fade = Kit.hash(seed + i * 2.11) * 0.45
			Kit.detail(
				Kit.block(
					parent,
					Vector3.new(0.6, 0.42, 5),
					cf * CFrame.new(0, 0.06, -length / 2 + 6 + i * 12),
					rgb(214, 178, 82):Lerp(ASPHALT, fade),
					Enum.Material.SmoothPlastic
				)
			)
		end
	end
	Props.roadWear(parent, cf, length, width, 0.25, seed)
	for side = -1, 1, 2 do
		Kit.detail(
			Kit.block(
				parent,
				Vector3.new(0.45, 0.42, length),
				cf * CFrame.new(side * (width / 2 - 1.1), 0.06, 0),
				rgb(206, 206, 198):Lerp(ASPHALT, Kit.hash(seed + side) * 0.3),
				Enum.Material.SmoothPlastic
			)
		)
	end
	if sidewalk <= 0 then
		return
	end

	-- Sidewalk pieces, skipping any gaps on that side.
	for side = -1, 1, 2 do
		local pieces = { { 0, length } }
		for _, gap in opts.Gaps or {} do
			if gap.Side == side then
				local nextPieces = {}
				for _, piece in pieces do
					if gap.To <= piece[1] or gap.From >= piece[2] then
						table.insert(nextPieces, piece)
					else
						if gap.From > piece[1] + 1 then
							table.insert(nextPieces, { piece[1], gap.From })
						end
						if gap.To < piece[2] - 1 then
							table.insert(nextPieces, { gap.To, piece[2] })
						end
					end
				end
				pieces = nextPieces
			end
		end
		for _, piece in pieces do
			local a, b = piece[1], piece[2]
			local extra = (a <= 0 and 1 or 0) + (b >= length and 1 or 0)
			local mid = (a + b) / 2 - length / 2 + ((a <= 0 and -0.5 or 0) + (b >= length and 0.5 or 0))
			local walk = Kit.block(
				parent,
				Vector3.new(sidewalk, 0.7, b - a + extra),
				cf * CFrame.new(side * (width / 2 + sidewalk / 2), 0.35, -mid),
				SIDEWALK,
				Enum.Material.Pavement,
				"Sidewalk"
			)
			walk.CastShadow = false
			Kit.detail(
				Kit.block(
					parent,
					Vector3.new(0.7, 0.75, b - a + extra),
					cf * CFrame.new(side * (width / 2 + 0.35), 0.38, -mid),
					CURB,
					Enum.Material.Concrete
				)
			)
			-- A newer replacement slab here and there, and a storm drain in the gutter
			local pieceLength = b - a
			for k = 1, math.floor(pieceLength / 40) do
				if Props.chance(seed + side * 31 + k * 7.7 + a, 0.5) then
					local along = a + Kit.hash(seed + k * 3.3 + side) * pieceLength
					Kit.detail(
						Kit.block(
							parent,
							Vector3.new(sidewalk - 1.4, 0.04, Props.between(seed + k, 3, 5)),
							cf * CFrame.new(side * (width / 2 + sidewalk / 2 + 0.35), 0.71, -(along - length / 2)),
							SIDEWALK:Lerp(rgb(214, 210, 200), 0.45),
							Enum.Material.Concrete
						)
					)
				end
			end
			if pieceLength > 20 and Props.chance(seed + side * 5.5 + a, 0.6) then
				local along = a + pieceLength * (0.3 + Kit.hash(seed + side + a) * 0.4)
				Kit.detail(
					Kit.block(
						parent,
						Vector3.new(1.1, 0.06, 2.6),
						cf * CFrame.new(side * (width / 2 - 0.6), 0.26, -(along - length / 2)),
						rgb(52, 50, 48),
						Enum.Material.DiamondPlate
					)
				)
			end
		end
	end

	local spacing = opts.LampSpacing
	if spacing then
		local i = 0
		local d = opts.LampOffset or spacing / 2
		while d < length - 4 do
			local side = (i % 2 == 0) and 1 or -1
			local blocked = false
			for _, gap in opts.Gaps or {} do
				if gap.Side == side and d > gap.From - 4 and d < gap.To + 4 then
					blocked = true
				end
			end
			if not blocked then
				local base = (cf * CFrame.new(side * (width / 2 + sidewalk - 1.2), 0.7, -(d - length / 2))).Position
				local inward = (cf * CFrame.new(0, 0.7, -(d - length / 2))).Position
				Kit.streetLamp(parent, CFrame.lookAt(base, Vector3.new(inward.X, base.Y, inward.Z)), 15)
			end
			i += 1
			d += spacing
		end
	end
end

local function flatDir(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z).Unit
end

-- Crosswalks at both ends, street trees in sidewalk pits, cars parked at the curb and the
-- odd bus stop. Lamps sit every `lampSpacing` studs, alternating sides (see `road`).
local function dressAvenue(
	parent: Instance,
	from: Vector3,
	to: Vector3,
	width: number,
	lampSpacing: number,
	seed: number,
	busStopAt: number?
)
	local folder = Kit.folder("StreetLife", parent)
	local length = (to - from).Magnitude
	local dir = (to - from).Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local function at(d: number, offset: number): Vector3
		return from + dir * d + right * offset
	end
	local center = CFrame.lookAt((from + to) / 2, to)
	for _, d in { 7, length - 7 } do
		Props.crosswalk(folder, center * CFrame.new(0, 0, -(d - length / 2)), width, 0.25, seed + d)
	end
	for side = -1, 1, 2 do
		-- Lamps on this side stand at lampOffset + k * 2 * spacing.
		local lampStart = side == 1 and lampSpacing / 2 or lampSpacing * 1.5
		local function nearLamp(d: number): boolean
			local k = (d - lampStart) / (lampSpacing * 2)
			return math.abs(k - math.floor(k + 0.5)) * lampSpacing * 2 < 7
		end
		local busStop = busStopAt and side == 1
		local d = 22 + Kit.hash(seed + side) * 10
		while d < length - 18 do
			local nearStop = busStop and math.abs(d - (busStopAt :: number)) < 12
			if not nearLamp(d) and not nearStop then
				Props.streetTree(folder, at(d, side * (width / 2 + 2.3)), seed + d * 1.3 + side, 0.7)
			end
			d += Props.between(seed + d + side * 9, 20, 30)
		end
		-- Parked cars along the curb (right-hand traffic, so they face the way their lane runs)
		local c = 18 + Kit.hash(seed + side * 3) * 12
		while c < length - 20 do
			local nearStop = busStop and math.abs(c - (busStopAt :: number)) < 14
			if not nearStop and Props.chance(seed + c * 0.7 + side * 13, 0.42) then
				local pos = at(c, side * (width / 2 - 3.5))
				Props.car(folder, CFrame.lookAt(pos, pos + dir * side), seed + c * 2.1 + side)
			end
			c += Props.between(seed + c * 1.9 + side, 16, 26)
		end
	end
	if busStopAt then
		local pos = at(busStopAt, width / 2 + 3.6) + Vector3.new(0, 0.7, 0)
		Props.busStop(folder, CFrame.lookAt(pos, pos - right), seed + 77)
	end
end

-- Wooden power poles just outside the ring road, wired together with sagging cables.
local function powerLines(parent: Instance, radius: number)
	local folder = Kit.folder("PowerLines", parent)
	local poles = {}
	local count = 48
	for i = 0, count - 1 do
		-- Offset by half a step so poles never land on a vault driveway.
		local angle = (i + 0.5) / count * math.pi * 2
		local pos = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local model, attachments = Props.utilityPole(folder, CFrame.lookAt(pos, pos + tangent), i * 7.7, 23 + (i % 3))
		Layout.claim(pos, 3)
		table.insert(poles, { Model = model, Attachments = attachments })
	end
	for i, pole in poles do
		local nextPole = poles[i % #poles + 1]
		for k, attachment in pole.Attachments do
			Props.wire(pole.Model, attachment, nextPole.Attachments[k], 2.4 + (k % 2) * 0.6)
		end
	end
end

-- Zone entrances along their spoke from the Marketplace.
Environment.SpokeStops = { Museum = 268, Laboratory = 274, Temple = 281, Warehouse = 264, Vault = 356 }

function Environment.roads(root: Instance, plotCFrames: { CFrame })
	local folder = Kit.folder("Roads", root)
	local ringRadius = GameConfig.Plots.Radius - 80

	-- Avenues from the Marketplace to each surface zone's front entrance
	for zoneId, stop in Environment.SpokeStops do
		local zone = Zones.get(zoneId) :: any
		local dir = flatDir(zone.Center)
		road(folder, dir * 104, dir * stop, 18, { Sidewalk = 7, LampSpacing = 36 })
		local busStops = { Warehouse = 70, Laboratory = 96, Vault = 180 }
		dressAvenue(folder, dir * 104, dir * stop, 18, 36, Kit.seedOf(CFrame.new(dir * stop)), busStops[zoneId])
	end

	-- Ring road that every vault connects to. Sidewalks open up wherever a road joins.
	-- { angle, side, half width }; going counter-clockwise, side +1 is the inner sidewalk.
	local crossings = {}
	for _, plotCF in plotCFrames do
		local p = plotCF.Position
		table.insert(crossings, { math.atan2(p.Z, p.X), -1, 8 })
	end
	for _, zoneId in { "Museum", "Laboratory", "Temple", "Warehouse" } do
		local c = (Zones.get(zoneId) :: any).Center
		table.insert(crossings, { math.atan2(c.Z, c.X), 1, 9 })
	end
	local segments = 48
	local ringWidth = 16
	for i = 0, segments - 1 do
		local a0 = i / segments * math.pi * 2
		local a1 = (i + 1) / segments * math.pi * 2
		local p0 = Vector3.new(math.cos(a0), 0, math.sin(a0)) * ringRadius
		local p1 = Vector3.new(math.cos(a1), 0, math.sin(a1)) * ringRadius
		local length = (p1 - p0).Magnitude
		local gaps = {}
		for _, crossing in crossings do
			local angle, side, halfWidth = crossing[1], crossing[2], crossing[3]
			local rel = (angle - a0) % (math.pi * 2)
			if rel > math.pi then
				rel -= math.pi * 2
			end
			local along = rel / (a1 - a0) * length
			table.insert(gaps, { Side = side, From = along - halfWidth - 1, To = along + halfWidth + 1 })
		end
		road(folder, p0, p1, ringWidth, {
			Sidewalk = 6,
			Gaps = gaps,
			LampSpacing = i % 2 == 0 and 200 or nil,
			LampOffset = length / 2,
			Overlap = 1.2,
		})
	end

	powerLines(folder, ringRadius + 8 + 6 + 3)

	-- Driveways from the ring out to every vault
	for _, plotCF in plotCFrames do
		local front = (plotCF * CFrame.new(0, 0, -48)).Position
		local dir = flatDir(front)
		road(folder, dir * (ringRadius + 7), Vector3.new(front.X, 0, front.Z), 12, { Sidewalk = 0 })
	end
	-- Back roads from each zone to the ring
	for _, zoneId in { "Museum", "Laboratory", "Temple", "Warehouse" } do
		local zone = Zones.get(zoneId) :: any
		local dir = flatDir(zone.Center)
		road(folder, dir * (zone.Center.Magnitude + zone.Radius - 10), dir * (ringRadius - 7), 14, {
			Sidewalk = 0,
		})
	end
	return ringRadius
end

function Environment.border(root: Instance)
	local folder = Kit.folder("Border", root)
	local radius = GameConfig.Map.WorldRadius
	local segments = 36
	local length = 2 * math.pi * radius / segments * 1.05
	for i = 0, segments - 1 do
		local angle = i / segments * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * radius, 60, math.sin(angle) * radius)
		local wall = Kit.block(
			folder,
			Vector3.new(length, 160, 4),
			CFrame.lookAt(pos, Vector3.new(0, 60, 0)),
			rgb(255, 255, 255),
			Enum.Material.ForceField,
			"Border"
		)
		wall.Transparency = 1
		wall.CastShadow = false
		wall.CanQuery = false
	end
end

-- Plants things on the natural ground (hills included), bedded in slightly.
local function onGround(position: Vector3): Vector3
	local h = Layout.groundHeight(position)
	return Vector3.new(position.X, h > 0 and h - 0.4 or 0, position.Z)
end

-- True if the ground under a circle of `radius` is flat (no hill under any part of it).
local function flatGround(position: Vector3, radius: number): boolean
	for _, offset in { Vector3.zero, Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		if Layout.groundHeight(position + offset * radius) > 0 then
			return false
		end
	end
	return true
end

-- Wild edge of the island: a forest belt between the vaults, boulders and meadows.
function Environment.scenery(root: Instance)
	local folder = Kit.folder("Scenery", root)
	local rng = Random.new(2024)
	-- Undergrowth draws from its own stream so the trees and rocks keep their places.
	local under = Random.new(808)
	local function nearby(center: Vector3, low: number, high: number): Vector3
		local a = under:NextNumber(0, math.pi * 2)
		return center + Vector3.new(math.cos(a), 0, math.sin(a)) * under:NextNumber(low, high)
	end
	local radius = GameConfig.Map.WorldRadius
	local oak = { rgb(74, 112, 56), rgb(88, 122, 60), rgb(64, 104, 62), rgb(102, 124, 64) }
	local autumn = { rgb(176, 112, 52), rgb(190, 148, 66), rgb(150, 84, 56) }

	-- Forest belt: groves and clearings rather than an even scatter, with stands of pine in
	-- some places and broadleaf woods in others
	local placed = 0
	for _ = 1, 4000 do
		if placed >= 180 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(radius - 125, radius - 26)
		local pos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		local density = math.noise(pos.X / 95, pos.Z / 95, 3.3) + 0.35 * math.noise(pos.X / 31, pos.Z / 31, 8.1)
		local conifers = math.noise(pos.X / 150, pos.Z / 150, 6.6) > -0.05
		pos = onGround(pos)
		local scale = rng:NextNumber(0.9, 1.5)
		if rng:NextNumber() < 0.45 + density * 1.8 and Layout.isFree(pos, 6 * scale, 4) then
			Layout.claim(pos, 4 * scale)
			placed += 1
			local roll = rng:NextNumber()
			if roll < (if conifers then 0.8 else 0.2) then
				Kit.pine(folder, pos, scale * 1.15, rgb(44, 78, 56):Lerp(rgb(62, 96, 62), rng:NextNumber()))
			elseif roll < 0.92 then
				Kit.tree(folder, pos, scale, oak[rng:NextInteger(1, #oak)])
			else
				Kit.tree(folder, pos, scale, autumn[rng:NextInteger(1, #autumn)])
			end
			if rng:NextNumber() < 0.35 then
				local offset = Vector3.new(rng:NextNumber(-7, 7), 0, rng:NextNumber(-7, 7))
				if Layout.isFree(pos + offset, 3, 2) then
					Kit.bush(folder, onGround(pos + offset), rng:NextNumber(0.8, 1.3))
				end
			end
			-- Forest floor: ferns between the trunks, long grass against them
			if under:NextNumber() < 0.3 then
				local at = nearby(pos, 2.6 * scale, 5 * scale)
				if Layout.roadClearance(at) > 1.5 then
					Kit.fern(folder, onGround(at), under:NextInteger(1, 1e6), under:NextNumber(0.8, 1.2))
				end
			end
			if under:NextNumber() < 0.2 then
				local at = nearby(pos, 1.3 * scale, 1.8 * scale)
				if Layout.roadClearance(at) > 1.5 then
					Kit.tuft(folder, onGround(at), under:NextInteger(1, 1e6))
				end
			end
		end
	end

	-- Not every tree is still standing: stumps where some were cut, a few fallen logs
	local fallen = 0
	for _ = 1, 500 do
		if fallen >= 21 then
			break
		end
		local angle = under:NextNumber(0, math.pi * 2)
		local r = under:NextNumber(radius - 120, radius - 30)
		local pos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		local isLog = fallen % 3 == 2
		if Layout.isFree(pos, if isLog then 6.5 else 2.5, 2) and (not isLog or flatGround(pos, 6.5)) then
			fallen += 1
			if isLog then
				Kit.log(folder, pos, under:NextInteger(1, 1e6))
				Layout.claim(pos, 6.5)
			else
				Kit.stump(folder, onGround(pos), under:NextInteger(1, 1e6))
				Layout.claim(pos, 2.5)
			end
		end
	end

	-- Boulders and meadow clutter anywhere that is still open ground
	local clutter = 0
	for _ = 1, 900 do
		if clutter >= 90 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(150, radius - 30)
		local pos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		pos = onGround(pos)
		if Layout.isFree(pos, 7, 4) then
			clutter += 1
			local roll = rng:NextNumber()
			if roll < 0.3 then
				Kit.rocks(folder, pos, rng:NextNumber(0.8, 1.5))
				Layout.claim(pos, 5)
				-- the mower never gets close to a boulder
				for _ = 1, under:NextInteger(1, 3) do
					Kit.tuft(folder, onGround(nearby(pos, 3.6, 5)), under:NextInteger(1, 1e6))
				end
			elseif roll < 0.65 then
				for j = 1, rng:NextInteger(2, 4) do
					local offset = Vector3.new(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
					if Layout.isFree(pos + offset, 3, 3) then
						Kit.bush(folder, onGround(pos + offset), rng:NextNumber(0.7, 1.2), oak[(j % #oak) + 1])
					end
				end
				Layout.claim(pos, 8)
			else
				Kit.tree(folder, pos, rng:NextNumber(0.9, 1.3), oak[rng:NextInteger(1, #oak)])
				Layout.claim(pos, 6)
			end
		end
	end

	-- Drifts of wildflowers in the open meadows, a few patches of one kind together
	local blooms = { rgb(238, 234, 224), rgb(238, 204, 84), rgb(190, 142, 206), rgb(222, 124, 120) }
	local drifts = 0
	for _ = 1, 800 do
		if drifts >= 10 then
			break
		end
		local angle = under:NextNumber(0, math.pi * 2)
		local r = under:NextNumber(160, radius - 34)
		local pos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		if Layout.isFree(pos, 9, 3) then
			drifts += 1
			local kind = blooms[under:NextInteger(1, #blooms)]
			for _ = 1, under:NextInteger(2, 3) do
				Kit.wildflowers(
					folder,
					onGround(nearby(pos, 0, 6)),
					under:NextInteger(1, 1e6),
					{ kind, kind, kind, blooms[1] }
				)
			end
			Layout.claim(pos, 9)
		end
	end
end

return Environment
