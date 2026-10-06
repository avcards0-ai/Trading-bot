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

local rgb = Kit.rgb

local Environment = {}

Environment.GrassColor = rgb(104, 150, 72)

-- Terrain only exists in a running server (it can't be saved into the place file from
-- outside Studio), so it is limited to the coastline: ocean, beach and the hills that
-- ring the island. The walkable island itself is the Ground part below.
function Environment.terrain()
	local terrain = workspace.Terrain
	local radius = GameConfig.Map.WorldRadius
	terrain:Clear()
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(2400, 8, 2400), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(0, -16, 0), Vector3.new(2400, 8, 2400), Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -7.5, 0), 12, radius + 70, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -7, 0), 12, radius + 12, Enum.Material.Grass)
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
end

-- The walkable island: one big grass disc (visible in Studio too).
function Environment.ground(root: Instance)
	local radius = GameConfig.Map.WorldRadius + 6
	local ground =
		Kit.cyl(root, 2, radius * 2, CFrame.new(0, -1, 0), Environment.GrassColor, Enum.Material.Grass, "Ground")
	ground.CastShadow = false
	ground.CanTouch = false
	return ground
end

function Environment.lighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.4
	Lighting.Ambient = rgb(70, 70, 85)
	Lighting.OutdoorAmbient = rgb(140, 140, 160)
	Lighting.ColorShift_Top = rgb(255, 245, 230)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.ShadowSoftness = 0.25
	Lighting.GeographicLatitude = 30

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = rgb(200, 215, 240)
	atmosphere.Decay = rgb(120, 140, 190)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 26
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "WorldColor"
	color.Saturation = 0.18
	color.Contrast = 0.08
	color.Brightness = 0.02
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.05
	rays.Spread = 0.6
	rays.Parent = Lighting
end

function Environment.clouds()
	if workspace.Terrain:FindFirstChildOfClass("Clouds") then
		return
	end
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = rgb(255, 255, 255)
	clouds.Parent = workspace.Terrain
end

local ASPHALT = rgb(62, 64, 70)
local SIDEWALK = rgb(198, 194, 186)
local CURB = rgb(170, 166, 160)

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
	local dashes = math.floor(length / 12)
	for i = 0, dashes - 1 do
		Kit.detail(
			Kit.block(
				parent,
				Vector3.new(0.6, 0.42, 5),
				cf * CFrame.new(0, 0.06, -length / 2 + 6 + i * 12),
				rgb(250, 206, 70),
				Enum.Material.SmoothPlastic
			)
		)
	end
	for side = -1, 1, 2 do
		Kit.detail(
			Kit.block(
				parent,
				Vector3.new(0.45, 0.42, length),
				cf * CFrame.new(side * (width / 2 - 1.1), 0.06, 0),
				rgb(236, 236, 230),
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

-- Zone entrances along their spoke from the Marketplace.
Environment.SpokeStops = { Museum = 268, Laboratory = 274, Temple = 281, Warehouse = 264, Vault = 420 }

function Environment.roads(root: Instance, plotCFrames: { CFrame })
	local folder = Kit.folder("Roads", root)
	local ringRadius = GameConfig.Plots.Radius - 80

	-- Avenues from the Marketplace to each surface zone's front entrance
	for zoneId, stop in Environment.SpokeStops do
		local zone = Zones.get(zoneId) :: any
		local dir = flatDir(zone.Center)
		road(folder, dir * 104, dir * stop, 18, { Sidewalk = 7, LampSpacing = 36 })
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

-- Wild edge of the island: a forest belt between the vaults, boulders and meadows.
function Environment.scenery(root: Instance)
	local folder = Kit.folder("Scenery", root)
	local rng = Random.new(2024)
	local radius = GameConfig.Map.WorldRadius
	local oak = { rgb(78, 150, 62), rgb(96, 160, 64), rgb(70, 136, 70), rgb(120, 168, 70) }
	local autumn = { rgb(214, 128, 52), rgb(232, 176, 70), rgb(196, 84, 60) }

	-- Forest belt
	local placed = 0
	for _ = 1, 1400 do
		if placed >= 170 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(radius - 125, radius - 26)
		local pos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		local scale = rng:NextNumber(0.9, 1.5)
		if Layout.isFree(pos, 6 * scale, 4) then
			Layout.claim(pos, 4 * scale)
			placed += 1
			local roll = rng:NextNumber()
			if roll < 0.55 then
				Kit.pine(folder, pos, scale * 1.15, rgb(48, 104, 66):Lerp(rgb(70, 126, 70), rng:NextNumber()))
			elseif roll < 0.9 then
				Kit.tree(folder, pos, scale, oak[rng:NextInteger(1, #oak)])
			else
				Kit.tree(folder, pos, scale, autumn[rng:NextInteger(1, #autumn)])
			end
			if rng:NextNumber() < 0.35 then
				local offset = Vector3.new(rng:NextNumber(-7, 7), 0, rng:NextNumber(-7, 7))
				if Layout.isFree(pos + offset, 3, 2) then
					Kit.bush(folder, pos + offset, rng:NextNumber(0.8, 1.3))
				end
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
		if Layout.isFree(pos, 7, 4) then
			clutter += 1
			local roll = rng:NextNumber()
			if roll < 0.3 then
				Kit.rocks(folder, pos, rng:NextNumber(0.8, 1.5))
				Layout.claim(pos, 5)
			elseif roll < 0.65 then
				for j = 1, rng:NextInteger(2, 4) do
					local offset = Vector3.new(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
					if Layout.isFree(pos + offset, 3, 3) then
						Kit.bush(folder, pos + offset, rng:NextNumber(0.7, 1.2), oak[(j % #oak) + 1])
					end
				end
				Layout.claim(pos, 8)
			else
				Kit.tree(folder, pos, rng:NextNumber(0.9, 1.3), oak[rng:NextInteger(1, #oak)])
				Layout.claim(pos, 6)
			end
		end
	end
end

return Environment
