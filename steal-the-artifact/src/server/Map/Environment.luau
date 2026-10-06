--[[
	Environment
	Terrain (island, beach, ocean, border hills), roads, lighting/post-processing, world
	border and scattered scenery. Runs before the zone builders so they can carve into it.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Zones = require(ReplicatedStorage.Shared.Config.Zones)
local Kit = require(script.Parent.Kit)

local rgb = Kit.rgb

local Environment = {}

function Environment.terrain()
	local terrain = workspace.Terrain
	local radius = GameConfig.Map.WorldRadius
	terrain:Clear()
	-- Ocean, beach ring, then the grassy island on top.
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(2000, 8, 2000), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(0, -16, 0), Vector3.new(2000, 8, 2000), Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -6, 0), 12, radius + 60, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -6, 0), 12, radius + 10, Enum.Material.Grass)
	-- Rolling border hills
	local rng = Random.new(42)
	for i = 1, 40 do
		local angle = i / 40 * math.pi * 2
		local r = radius + rng:NextNumber(-10, 25)
		local size = rng:NextNumber(40, 70)
		local material = (i % 3 == 0) and Enum.Material.Rock or Enum.Material.Grass
		terrain:FillBall(Vector3.new(math.cos(angle) * r, -size * 0.35, math.sin(angle) * r), size, material)
	end
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

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = rgb(255, 255, 255)
	clouds.Parent = workspace.Terrain
end

local function road(parent: Instance, from: Vector3, to: Vector3, width: number)
	local delta = to - from
	local length = delta.Magnitude
	if length < 1 then
		return
	end
	local cf = CFrame.lookAt((from + to) / 2, to)
	local asphalt = Kit.block(parent, Vector3.new(width, 0.4, length), cf * CFrame.new(0, 0.05, 0), rgb(70, 72, 80), Enum.Material.Asphalt, "Road")
	asphalt.CastShadow = false
	local dashes = math.floor(length / 12)
	for i = 0, dashes - 1 do
		local dash = Kit.block(parent, Vector3.new(0.6, 0.42, 5), cf * CFrame.new(0, 0.06, -length / 2 + 6 + i * 12), rgb(255, 214, 70), Enum.Material.SmoothPlastic)
		dash.CastShadow = false
		dash.CanCollide = false
	end
	for side = -1, 1, 2 do
		local curb = Kit.block(parent, Vector3.new(1, 0.6, length), cf * CFrame.new(side * (width / 2 + 0.5), 0.1, 0), rgb(200, 200, 205), Enum.Material.Concrete)
		curb.CastShadow = false
	end
end

function Environment.roads(root: Instance, plotCFrames: { CFrame })
	local folder = Kit.folder("Roads", root)
	-- Spokes from the Marketplace to each surface zone's front entrance
	local entrances = { Museum = 268, Laboratory = 274, Temple = 281, Warehouse = 264, Vault = 420 }
	for zoneId, stop in entrances do
		local zone = Zones.get(zoneId) :: any
		local dir = Vector3.new(zone.Center.X, 0, zone.Center.Z).Unit
		road(folder, dir * 100, dir * stop, 18)
	end
	-- Ring road around the city that every vault connects to
	local ringRadius = GameConfig.Plots.Radius - 80
	local segments = 48
	for i = 0, segments - 1 do
		local a0 = i / segments * math.pi * 2
		local a1 = (i + 1) / segments * math.pi * 2
		road(folder, Vector3.new(math.cos(a0), 0, math.sin(a0)) * ringRadius, Vector3.new(math.cos(a1), 0, math.sin(a1)) * ringRadius, 16)
	end
	for _, plotCF in plotCFrames do
		local front = (plotCF * CFrame.new(0, 0, -48)).Position
		local dir = Vector3.new(front.X, 0, front.Z).Unit
		road(folder, dir * (ringRadius + 8), Vector3.new(front.X, 0, front.Z), 12)
	end
	-- Ring road connectors to the zone spokes
	for _, zoneId in { "Museum", "Laboratory", "Temple", "Warehouse" } do
		local zone = Zones.get(zoneId) :: any
		local dir = Vector3.new(zone.Center.X, 0, zone.Center.Z).Unit
		road(folder, dir * (zone.Center.Magnitude + zone.Radius - 10), dir * (ringRadius - 8), 14)
	end
end

function Environment.border(root: Instance)
	local folder = Kit.folder("Border", root)
	local radius = GameConfig.Map.WorldRadius
	local segments = 36
	local length = 2 * math.pi * radius / segments * 1.05
	for i = 0, segments - 1 do
		local angle = i / segments * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * radius, 60, math.sin(angle) * radius)
		local wall = Kit.block(folder, Vector3.new(length, 160, 4), CFrame.lookAt(pos, Vector3.new(0, 60, 0)), rgb(255, 255, 255), Enum.Material.ForceField, "Border")
		wall.Transparency = 1
		wall.CastShadow = false
		wall.CanQuery = false
	end
end

-- Scatter trees / rocks / flowers in open ground (away from zones, plots and roads).
function Environment.scenery(root: Instance, plotCFrames: { CFrame })
	local folder = Kit.folder("Scenery", root)
	local rng = Random.new(2024)
	local function clear(pos: Vector3): boolean
		for _, zone in Zones.List do
			if zone.Center.Y > -40 and (Vector3.new(zone.Center.X, 0, zone.Center.Z) - pos).Magnitude < zone.Radius + 40 then
				return false
			end
		end
		for _, cf in plotCFrames do
			if (cf.Position - pos).Magnitude < 85 then
				return false
			end
		end
		local r = pos.Magnitude
		if r < 130 or math.abs(r - (GameConfig.Plots.Radius - 80)) < 18 or r > GameConfig.Map.WorldRadius - 30 then
			return false
		end
		-- Stay off the spoke roads (cardinal + north-east directions).
		local angle = math.deg(math.atan2(pos.Z, pos.X)) % 360
		for _, roadAngle in { 0, 90, 180, 270, 315 } do
			local diff = math.abs(((angle - roadAngle) + 180) % 360 - 180)
			if diff * math.pi / 180 * r < 18 then
				return false
			end
		end
		return true
	end
	local placed = 0
	local attempts = 0
	while placed < 90 and attempts < 1500 do
		attempts += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(130, GameConfig.Map.WorldRadius - 30)
		local pos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		if clear(pos) then
			placed += 1
			local roll = rng:NextNumber()
			if roll < 0.6 then
				local leafColors = { rgb(70, 160, 70), rgb(90, 175, 60), rgb(255, 150, 190), rgb(230, 150, 60) }
				Kit.tree(folder, pos, rng:NextNumber(0.8, 1.4), leafColors[rng:NextInteger(1, #leafColors)])
			elseif roll < 0.8 then
				local rock = Kit.block(folder, Vector3.new(rng:NextNumber(4, 9), rng:NextNumber(3, 6), rng:NextNumber(4, 9)), CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)), rgb(140, 140, 150), Enum.Material.Rock, "Rock")
				rock.CastShadow = true
			else
				local colors = { rgb(255, 90, 120), rgb(255, 220, 80), rgb(150, 120, 255), rgb(255, 255, 255) }
				for j = 1, 5 do
					local flower = Kit.ball(folder, 0.9, CFrame.new(pos + Vector3.new(rng:NextNumber(-4, 4), 0.4, rng:NextNumber(-4, 4))), colors[(j % #colors) + 1], Enum.Material.SmoothPlastic)
					flower.CanCollide = false
					flower.CastShadow = false
				end
			end
		end
	end
end

return Environment
