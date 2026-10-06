--[[
	City
	Fills the ground between the gameplay zones so the island reads as a real town:
	  * shops lining every avenue out of the Marketplace
	  * Downtown (north-west), the Financial District (north-east, by the vault),
	    Old Town (south-east) and Central Park (south-west)
	  * suburbs with houses and gardens further out
	Everything is placed through Layout so it never blocks zones, roads or vaults.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Config.Zones)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)

local rgb = Kit.rgb

local City = {}

local SHOPS = {
	{ "PIZZA", rgb(214, 62, 52) },
	{ "ARCADE", rgb(120, 70, 200) },
	{ "PAWN SHOP", rgb(60, 120, 90) },
	{ "DONUTS", rgb(236, 120, 170) },
	{ "BURGERS", rgb(220, 140, 40) },
	{ "BOBA TEA", rgb(150, 110, 80) },
	{ "COMICS", rgb(40, 120, 200) },
	{ "LOCKSMITH", rgb(90, 96, 110) },
	{ "SPY GEAR", rgb(30, 34, 44) },
	{ "TACOS", rgb(230, 170, 40) },
	{ "ICE CREAM", rgb(110, 190, 220) },
	{ "BOOKS", rgb(130, 70, 60) },
	{ "PET SHOP", rgb(90, 170, 90) },
	{ "BAKERY", rgb(200, 150, 90) },
	{ "SUSHI", rgb(200, 60, 70) },
	{ "TOYS", rgb(240, 90, 60) },
	{ "JEWELRY", rgb(180, 150, 60) },
	{ "PHARMACY", rgb(60, 170, 120) },
	{ "FLOWERS", rgb(220, 100, 150) },
	{ "CINEMA", rgb(150, 30, 50) },
	{ "GYM", rgb(50, 60, 80) },
	{ "HOTEL", rgb(120, 40, 60) },
	{ "NOODLES", rgb(230, 110, 50) },
	{ "BANK", rgb(40, 70, 120) },
}

local BRICK = {
	{ Wall = rgb(166, 86, 66), Trim = rgb(236, 228, 212) },
	{ Wall = rgb(138, 92, 74), Trim = rgb(228, 218, 198) },
	{ Wall = rgb(184, 116, 86), Trim = rgb(244, 236, 220) },
	{ Wall = rgb(120, 72, 62), Trim = rgb(214, 204, 188) },
}
local PASTEL = {
	{ Wall = rgb(240, 204, 172), Trim = rgb(250, 248, 242) },
	{ Wall = rgb(176, 212, 222), Trim = rgb(250, 248, 242) },
	{ Wall = rgb(238, 226, 168), Trim = rgb(250, 248, 242) },
	{ Wall = rgb(204, 186, 228), Trim = rgb(250, 248, 242) },
	{ Wall = rgb(186, 220, 182), Trim = rgb(250, 248, 242) },
	{ Wall = rgb(242, 180, 176), Trim = rgb(250, 248, 242) },
}
local STONE = {
	{ Wall = rgb(214, 206, 190), Trim = rgb(150, 140, 126) },
	{ Wall = rgb(190, 186, 178), Trim = rgb(110, 108, 104) },
}
local MODERN = {
	{ Wall = rgb(206, 210, 216), Trim = rgb(124, 130, 140), Glass = rgb(96, 146, 186) },
	{ Wall = rgb(64, 70, 82), Trim = rgb(44, 48, 56), Glass = rgb(110, 164, 206) },
	{ Wall = rgb(226, 222, 212), Trim = rgb(170, 160, 140), Glass = rgb(80, 128, 150) },
}
local HOUSES = {
	{ Wall = rgb(246, 236, 214), Roof = rgb(150, 70, 60), Door = rgb(60, 90, 140) },
	{ Wall = rgb(190, 214, 230), Roof = rgb(70, 76, 90), Door = rgb(200, 70, 60) },
	{ Wall = rgb(236, 214, 170), Roof = rgb(110, 80, 60), Door = rgb(70, 120, 80) },
	{ Wall = rgb(214, 196, 228), Roof = rgb(80, 70, 100), Door = rgb(240, 240, 240) },
	{ Wall = rgb(200, 226, 196), Roof = rgb(124, 64, 52), Door = rgb(110, 70, 50) },
	{ Wall = rgb(250, 250, 246), Roof = rgb(60, 100, 130), Door = rgb(220, 160, 60) },
}
local LEAVES = { rgb(78, 150, 62), rgb(96, 160, 64), rgb(70, 136, 70), rgb(120, 168, 70) }

-- Checks the center, corners and edge midpoints of a footprint.
local function rectFree(cf: CFrame, w: number, d: number, gap: number): boolean
	for _, p in
		{
			{ 0, 0 },
			{ -1, -1 },
			{ 1, -1 },
			{ -1, 1 },
			{ 1, 1 },
			{ 0, -1 },
			{ 0, 1 },
			{ -1, 0 },
			{ 1, 0 },
		}
	do
		local point = (cf * CFrame.new(p[1] * w / 2, 0, p[2] * d / 2)).Position
		if not Layout.isFree(point, gap, 0.5) then
			return false
		end
	end
	return true
end

local function claimRect(cf: CFrame, w: number, d: number)
	local r = math.min(w, d) / 2
	local long = math.max(w, d)
	local steps = math.max(1, math.ceil(long / (r * 2)))
	for i = 0, steps - 1 do
		local t = (i + 0.5) / steps - 0.5
		local offset = w >= d and Vector3.new(t * w, 0, 0) or Vector3.new(0, 0, t * d)
		Layout.claim((cf * CFrame.new(offset)).Position, r * 1.25)
	end
end

-- Paved apron around a building so blocks read as city, not field.
local function apron(parent: Instance, cf: CFrame, w: number, d: number, color: Color3?)
	local slab = Kit.block(
		parent,
		Vector3.new(w, 0.5, d),
		cf * CFrame.new(0, 0.25, 0),
		color or rgb(188, 184, 176),
		Enum.Material.Pavement,
		"Apron"
	)
	slab.CastShadow = false
	return slab
end

local shopIndex = 0
local function nextShop()
	shopIndex += 1
	return SHOPS[(shopIndex - 1) % #SHOPS + 1]
end

-- Shops along both sides of an avenue running from `from` along `dir`.
local function lineAvenue(parent: Instance, rng: Random, dir: Vector3, startR: number, endR: number, setback: number)
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	for side = -1, 1, 2 do
		local t = startR
		while t < endR do
			local w = rng:NextInteger(20, 28)
			local d = rng:NextInteger(18, 24)
			local h = rng:NextInteger(2, 3) * 10 + rng:NextInteger(0, 4)
			local center = dir * (t + w / 2) + perp * side * (setback + d / 2)
			local cf = CFrame.lookAt(center, center - perp * side)
			if rectFree(cf, w + 2, d, 0.5) then
				local palette = rng:NextNumber() < 0.5 and BRICK[rng:NextInteger(1, #BRICK)]
					or PASTEL[rng:NextInteger(1, #PASTEL)]
				local shop = nextShop()
				Kit.building(parent, cf, {
					Name = shop[1],
					Size = Vector3.new(w, h, d),
					Wall = palette.Wall,
					WallMaterial = table.find(BRICK, palette) and Enum.Material.Brick or Enum.Material.Plaster,
					Trim = palette.Trim,
					Floors = math.max(2, math.floor(h / 10)),
					Shop = { Text = shop[1], Color = shop[2] },
					Seed = rng:NextInteger(1, 1e6),
				})
				claimRect(cf, w + 4, d + 4)
				t += w + rng:NextInteger(5, 9)
			else
				t += 5
			end
		end
	end
end

type District = {
	Name: string,
	Sign: Vector3, -- quadrant direction
	MinR: number,
	MaxR: number,
	Kind: string,
}

local DISTRICTS: { District } = {
	{ Name = "Downtown", Sign = Vector3.new(-1, 0, -1), MinR = 128, MaxR = 320, Kind = "Downtown" },
	{ Name = "FinancialDistrict", Sign = Vector3.new(1, 0, -1), MinR = 128, MaxR = 330, Kind = "Financial" },
	{ Name = "OldTown", Sign = Vector3.new(1, 0, 1), MinR = 128, MaxR = 320, Kind = "OldTown" },
}

local function districtBuilding(
	parent: Instance,
	rng: Random,
	kind: string,
	cf: CFrame,
	w: number,
	d: number,
	r: number
)
	-- Taller near the middle of town.
	local closeness = math.clamp(1 - (r - 128) / 200, 0, 1)
	if kind == "Financial" then
		local palette = MODERN[rng:NextInteger(1, #MODERN)]
		local h = math.floor(36 + closeness * 36 + rng:NextNumber(0, 14))
		Kit.building(parent, cf, {
			Name = "Tower",
			Size = Vector3.new(w, h, d),
			Wall = palette.Wall,
			WallMaterial = Enum.Material.Concrete,
			Trim = palette.Trim,
			Glass = palette.Glass,
			Floors = math.floor(h / 9),
			Style = "Modern",
			Seed = rng:NextInteger(1, 1e6),
		})
	elseif kind == "Downtown" then
		local modern = rng:NextNumber() < 0.35
		if modern then
			local palette = MODERN[rng:NextInteger(1, #MODERN)]
			local h = math.floor(34 + closeness * 30 + rng:NextNumber(0, 10))
			Kit.building(parent, cf, {
				Name = "Office",
				Size = Vector3.new(w, h, d),
				Wall = palette.Wall,
				WallMaterial = Enum.Material.Concrete,
				Trim = palette.Trim,
				Glass = palette.Glass,
				Floors = math.floor(h / 9),
				Style = "Modern",
				Seed = rng:NextInteger(1, 1e6),
			})
		else
			local palette = rng:NextNumber() < 0.5 and STONE[rng:NextInteger(1, #STONE)]
				or BRICK[rng:NextInteger(1, #BRICK)]
			local h = math.floor(26 + closeness * 22 + rng:NextNumber(0, 8))
			local shop = rng:NextNumber() < 0.5 and nextShop() or nil
			Kit.building(parent, cf, {
				Name = "Building",
				Size = Vector3.new(w, h, d),
				Wall = palette.Wall,
				WallMaterial = table.find(STONE, palette) and Enum.Material.Limestone or Enum.Material.Brick,
				Trim = palette.Trim,
				Floors = math.floor(h / 10),
				Shop = shop and { Text = shop[1], Color = shop[2] } or nil,
				Seed = rng:NextInteger(1, 1e6),
			})
		end
	else -- Old Town: low brick and pastel shops
		local brick = rng:NextNumber() < 0.5
		local palette = brick and BRICK[rng:NextInteger(1, #BRICK)] or PASTEL[rng:NextInteger(1, #PASTEL)]
		local h = rng:NextInteger(2, 3) * 10 + rng:NextInteger(0, 3)
		local shop = nextShop()
		Kit.building(parent, cf, {
			Name = shop[1],
			Size = Vector3.new(w, h, d),
			Wall = palette.Wall,
			WallMaterial = brick and Enum.Material.Brick or Enum.Material.Plaster,
			Trim = palette.Trim,
			Floors = math.max(2, math.floor(h / 10)),
			Shop = { Text = shop[1], Color = shop[2] },
			Seed = rng:NextInteger(1, 1e6),
		})
	end
end

-- Faces the nearer avenue (the avenues run along the X and Z axes).
local function facing(position: Vector3): CFrame
	local target
	if math.abs(position.X) < math.abs(position.Z) then
		target = position - Vector3.new(math.sign(position.X), 0, 0)
	else
		target = position - Vector3.new(0, 0, math.sign(position.Z))
	end
	return CFrame.lookAt(position, target)
end

local function buildDistricts(parent: Instance, rng: Random)
	local spacing = 46
	for _, district in DISTRICTS do
		local folder = Kit.folder(district.Name, parent)
		for gx = 0, 10 do
			for gz = 0, 10 do
				local p = Vector3.new(district.Sign.X * (24 + gx * spacing), 0, district.Sign.Z * (24 + gz * spacing))
				local r = p.Magnitude
				if r >= district.MinR and r <= district.MaxR and rng:NextNumber() < 0.86 then
					local w = rng:NextInteger(24, 34)
					local d = rng:NextInteger(22, 30)
					local cf = facing(p)
					if rectFree(cf, w + 8, d + 8, 1) then
						apron(folder, cf, w + 8, d + 8)
						districtBuilding(folder, rng, district.Kind, cf, w, d, r)
						claimRect(cf, w + 10, d + 10)
						if rng:NextNumber() < 0.5 then
							local corner = (cf * CFrame.new(w / 2 + 2.5, 0.5, -d / 2 - 2.5)).Position
							if rng:NextNumber() < 0.5 then
								Kit.hydrant(folder, corner)
							else
								Kit.trashCan(folder, corner)
							end
						end
					end
				end
			end
		end
	end
end

-- Central Park (south-west): pond, gazebo, paths, trees, flower beds and benches.
local function buildPark(parent: Instance, rng: Random)
	local folder = Kit.folder("CentralPark", parent)
	local center = Vector3.new(-205, 0, 205)
	-- Pond
	local pond = Kit.model("Pond", folder)
	Kit.cyl(pond, 1.2, 64, CFrame.new(center + Vector3.new(0, 0.6, 0)), rgb(150, 144, 134), Enum.Material.Cobblestone)
	local water =
		Kit.cyl(pond, 0.4, 59, CFrame.new(center + Vector3.new(0, 1.05, 0)), rgb(70, 150, 190), Enum.Material.Glass)
	water.Transparency = 0.15
	water.Reflectance = 0.15
	water.Name = "Water"
	local bed = Kit.cyl(
		pond,
		0.2,
		59,
		CFrame.new(center + Vector3.new(0, 0.9, 0)),
		rgb(40, 90, 100),
		Enum.Material.SmoothPlastic
	)
	Kit.detail(bed)
	for i = 1, 5 do
		local angle = i / 5 * math.pi * 2 + 0.3
		local pad = Kit.cyl(
			pond,
			0.15,
			rng:NextNumber(2.5, 4),
			CFrame.new(center + Vector3.new(math.cos(angle) * 18, 1.3, math.sin(angle) * 18)),
			rgb(90, 160, 70),
			Enum.Material.LeafyGrass
		)
		Kit.detail(pad)
	end
	-- Fountain spout in the middle of the pond
	Kit.cyl(pond, 3, 4, CFrame.new(center + Vector3.new(0, 2.5, 0)), rgb(220, 214, 200), Enum.Material.Marble)
	local spray =
		Kit.cyl(pond, 5, 1.6, CFrame.new(center + Vector3.new(0, 6, 0)), rgb(200, 235, 255), Enum.Material.Glass)
	spray.Transparency = 0.4
	Kit.detail(spray)
	Layout.claim(center, 36)

	-- Paths from the pond out to the avenues
	local pathColor = rgb(214, 200, 170)
	local ends = {
		Vector3.new(-16.5, 0, center.Z),
		Vector3.new(center.X, 0, 16.5),
		Vector3.new(-80, 0, 80),
		Vector3.new(-300, 0, 300),
	}
	for _, target in ends do
		local dir = (target - center) * Vector3.new(1, 0, 1)
		local startPoint = center + dir.Unit * 33
		local length = (target - startPoint).Magnitude
		local cf = CFrame.lookAt(startPoint, target) * CFrame.new(0, 0.15, -length / 2)
		local path = Kit.block(folder, Vector3.new(8, 0.3, length), cf, pathColor, Enum.Material.Pavement, "Path")
		path.CastShadow = false
		for along = 18, length - 10, 26 do
			local side = (math.floor(along / 26) % 2 == 0) and 1 or -1
			local benchCF = cf
				* CFrame.new(side * 6, -0.15, -length / 2 + along)
				* CFrame.Angles(0, side * math.pi / 2, 0)
			Kit.bench(folder, benchCF)
			Kit.lamp(folder, (cf * CFrame.new(-side * 5.5, -0.15, -length / 2 + along + 6)).Position, nil, 11)
		end
		Layout.addRoad(startPoint, target, 4)
	end

	-- Gazebo on the north-west bank
	local gazeboPos = center + Vector3.new(-52, 0, -18)
	if Layout.isFree(gazeboPos, 12, 1) then
		local gazebo = Kit.model("Gazebo", folder)
		Kit.cyl(
			gazebo,
			1.2,
			20,
			CFrame.new(gazeboPos + Vector3.new(0, 0.6, 0)),
			rgb(236, 230, 218),
			Enum.Material.WoodPlanks
		)
		for i = 1, 6 do
			local angle = i / 6 * math.pi * 2
			Kit.cyl(
				gazebo,
				10,
				0.9,
				CFrame.new(gazeboPos + Vector3.new(math.cos(angle) * 8.5, 6.2, math.sin(angle) * 8.5)),
				rgb(250, 248, 242),
				Enum.Material.Wood
			)
		end
		Kit.cyl(gazebo, 1, 21, CFrame.new(gazeboPos + Vector3.new(0, 11.6, 0)), rgb(250, 248, 242), Enum.Material.Wood)
		for i = 0, 1 do
			Kit.gable(
				gazebo,
				CFrame.new(gazeboPos + Vector3.new(0, 15, 0)) * CFrame.Angles(0, i * math.pi / 2, 0),
				Vector3.new(15, 6, 21),
				rgb(70, 110, 90),
				Enum.Material.RoofShingles
			)
		end
		Layout.claim(gazeboPos, 12)
	end

	-- Trees and flower beds around the lawns
	local placed = 0
	for _ = 1, 400 do
		if placed >= 42 then
			break
		end
		local pos = center + Vector3.new(rng:NextNumber(-110, 110), 0, rng:NextNumber(-110, 110))
		if pos.Magnitude > 130 and Layout.isFree(pos, 6, 3) then
			placed += 1
			if placed % 6 == 0 then
				Kit.flowerBed(folder, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector2.new(8, 4))
				Layout.claim(pos, 6)
			else
				Kit.tree(folder, pos, rng:NextNumber(0.95, 1.35), LEAVES[rng:NextInteger(1, #LEAVES)])
				Layout.claim(pos, 7)
			end
		end
	end
end

-- Suburbs: small houses with gardens on the open ground further out.
local function buildSuburbs(parent: Instance, rng: Random)
	local folder = Kit.folder("Suburbs", parent)
	local spacing = 40
	for gx = -12, 12 do
		for gz = -12, 12 do
			local p = Vector3.new(gx * spacing + 20, 0, gz * spacing + 20)
			local r = p.Magnitude
			if r > 300 and r < 485 and rng:NextNumber() < 0.7 then
				local w = rng:NextInteger(16, 20)
				local d = rng:NextInteger(13, 16)
				local cf = facing(p)
				if rectFree(cf, w + 12, d + 14, 1) then
					local palette = HOUSES[rng:NextInteger(1, #HOUSES)]
					Kit.house(folder, cf, {
						Size = Vector3.new(w, rng:NextInteger(9, 11), d),
						Wall = palette.Wall,
						Roof = palette.Roof,
						Door = palette.Door,
					})
					-- Front walk, garden fence and a tree in the yard
					local walk = Kit.block(
						folder,
						Vector3.new(3, 0.3, 6),
						cf * CFrame.new(0, 0.15, -d / 2 - 4.5),
						rgb(200, 196, 188),
						Enum.Material.Pavement
					)
					walk.CastShadow = false
					local yardW = w / 2 + 5
					local front = -d / 2 - 7
					Kit.fence(
						folder,
						(cf * CFrame.new(-yardW, 0, front)).Position,
						(cf * CFrame.new(-2.5, 0, front)).Position
					)
					Kit.fence(
						folder,
						(cf * CFrame.new(2.5, 0, front)).Position,
						(cf * CFrame.new(yardW, 0, front)).Position
					)
					local treeSide = rng:NextNumber() < 0.5 and -1 or 1
					Kit.tree(
						folder,
						(cf * CFrame.new(treeSide * (w / 2 + 1), 0, -d / 2 - 3.5)).Position,
						rng:NextNumber(0.6, 0.8),
						LEAVES[rng:NextInteger(1, #LEAVES)]
					)
					Kit.bush(folder, (cf * CFrame.new(-treeSide * (w / 2 - 2), 0, -d / 2 - 2)).Position, 0.7)
					claimRect(cf, w + 14, d + 16)
				end
			end
		end
	end
end

function City.build(root: Instance)
	local folder = Kit.folder("City", root)
	local rng = Random.new(1337)
	shopIndex = 0

	buildPark(folder, rng)

	-- Shops along the avenues, starting just outside the Marketplace.
	for _, zoneId in { "Museum", "Laboratory", "Temple", "Warehouse", "Vault" } do
		local zone = Zones.get(zoneId) :: any
		local dir = Vector3.new(zone.Center.X, 0, zone.Center.Z).Unit
		local stop = zone.Center.Magnitude - zone.Radius - 20
		lineAvenue(folder, rng, dir, 118, stop, 18.5)
	end

	buildDistricts(folder, rng)
	buildSuburbs(folder, rng)
end

return City
