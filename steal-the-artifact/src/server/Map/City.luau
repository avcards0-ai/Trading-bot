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
local Props = require(script.Parent.Props)

local rgb = Kit.rgb

local City = {}

local SHOPS = {
	{ "PIZZA", rgb(176, 58, 48) },
	{ "ARCADE", rgb(92, 64, 140) },
	{ "PAWN SHOP", rgb(52, 98, 76) },
	{ "DONUTS", rgb(190, 110, 140) },
	{ "BURGERS", rgb(182, 118, 44) },
	{ "BOBA TEA", rgb(128, 96, 74) },
	{ "COMICS", rgb(46, 96, 152) },
	{ "LOCKSMITH", rgb(78, 82, 92) },
	{ "SPY GEAR", rgb(34, 38, 46) },
	{ "TACOS", rgb(190, 142, 46) },
	{ "ICE CREAM", rgb(98, 156, 176) },
	{ "BOOKS", rgb(112, 64, 56) },
	{ "PET SHOP", rgb(78, 136, 82) },
	{ "BAKERY", rgb(170, 128, 84) },
	{ "SUSHI", rgb(166, 56, 62) },
	{ "TOYS", rgb(196, 86, 58) },
	{ "JEWELRY", rgb(150, 126, 62) },
	{ "PHARMACY", rgb(54, 138, 104) },
	{ "FLOWERS", rgb(176, 92, 124) },
	{ "CINEMA", rgb(124, 34, 46) },
	{ "GYM", rgb(48, 54, 68) },
	{ "HOTEL", rgb(104, 42, 56) },
	{ "NOODLES", rgb(186, 98, 50) },
	{ "BANK", rgb(40, 62, 100) },
}

-- Real-world facade tones: brick, painted stucco, limestone and curtain-wall offices.
local BRICK = {
	{ Wall = rgb(146, 82, 64), Trim = rgb(218, 210, 194) },
	{ Wall = rgb(124, 86, 72), Trim = rgb(206, 198, 182) },
	{ Wall = rgb(160, 104, 82), Trim = rgb(224, 216, 200) },
	{ Wall = rgb(110, 70, 60), Trim = rgb(196, 188, 174) },
	{ Wall = rgb(136, 112, 96), Trim = rgb(214, 206, 192) },
}
local PASTEL = {
	{ Wall = rgb(214, 200, 174), Trim = rgb(236, 232, 222) },
	{ Wall = rgb(164, 180, 186), Trim = rgb(232, 230, 222) },
	{ Wall = rgb(208, 194, 150), Trim = rgb(236, 232, 222) },
	{ Wall = rgb(178, 186, 160), Trim = rgb(232, 230, 220) },
	{ Wall = rgb(196, 146, 118), Trim = rgb(236, 230, 218) },
	{ Wall = rgb(188, 162, 156), Trim = rgb(234, 228, 220) },
	{ Wall = rgb(180, 178, 172), Trim = rgb(226, 224, 218) },
}
local STONE = {
	{ Wall = rgb(204, 196, 180), Trim = rgb(150, 140, 126) },
	{ Wall = rgb(182, 178, 170), Trim = rgb(112, 110, 106) },
	{ Wall = rgb(194, 182, 160), Trim = rgb(132, 122, 108) },
}
local MODERN = {
	{ Wall = rgb(196, 198, 200), Trim = rgb(118, 122, 128), Glass = rgb(84, 104, 118) },
	{ Wall = rgb(66, 70, 78), Trim = rgb(46, 49, 55), Glass = rgb(92, 116, 130) },
	{ Wall = rgb(214, 210, 200), Trim = rgb(160, 152, 136), Glass = rgb(76, 98, 104) },
}
local HOUSES = {
	{ Wall = rgb(232, 224, 206), Roof = rgb(120, 62, 54), Door = rgb(52, 76, 110) },
	{ Wall = rgb(176, 192, 200), Roof = rgb(64, 66, 72), Door = rgb(150, 56, 48) },
	{ Wall = rgb(214, 196, 160), Roof = rgb(96, 74, 58), Door = rgb(62, 98, 70) },
	{ Wall = rgb(196, 186, 198), Roof = rgb(74, 68, 84), Door = rgb(224, 222, 216) },
	{ Wall = rgb(184, 198, 172), Roof = rgb(108, 60, 50), Door = rgb(96, 66, 48) },
	{ Wall = rgb(238, 236, 228), Roof = rgb(58, 78, 96), Door = rgb(170, 128, 58) },
	{ Wall = rgb(168, 140, 116), Roof = rgb(84, 80, 76), Door = rgb(236, 232, 222) },
}
local LEAVES = { rgb(74, 112, 56), rgb(88, 122, 60), rgb(64, 104, 62), rgb(102, 124, 64) }

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

local FADED = rgb(170, 166, 158)

-- Shop options with real-world wear: faded awnings and the odd closed-down unit.
local function shopFront(shop: { any }, seed: number): { [string]: any }
	local fade = Kit.hash(seed) * 0.4
	return {
		Text = shop[1],
		Color = shop[2],
		Awning = { (shop[2] :: Color3):Lerp(FADED, fade), rgb(232, 226, 212):Lerp(FADED, fade) },
		Closed = Kit.hash(seed + 1) < 0.09,
	}
end

-- Old flyers in the alleys between buildings.
local function postersOnSides(seed: number)
	return function(model: Model, faces: { { any } }, _floors: number, _floorHeight: number)
		for k = 3, 4 do
			local face, width = faces[k][1], faces[k][2]
			for i = 1, math.floor(Kit.hash(seed + k * 3) * 3) do
				Props.poster(
					model,
					face,
					(Kit.hash(seed + k + i * 5) - 0.5) * (width - 6),
					Props.between(seed + i * 7 + k, 3.5, 6),
					seed + k * 11 + i
				)
			end
		end
	end
end

-- Back door with a light, plus whatever piles up beside it: a dumpster, bags, pallets, boxes.
local function backAlley(parent: Instance, cf: CFrame, w: number, d: number, seed: number)
	local back = cf * CFrame.new(0, 0, d / 2) * CFrame.Angles(0, math.pi, 0) -- LookVector out of the back wall
	local doorX = (Kit.hash(seed) - 0.5) * (w - 10)
	Kit.detail(
		Kit.block(
			parent,
			Vector3.new(3.6, 7, 0.3),
			back * CFrame.new(doorX, 3.5, -0.1),
			rgb(70, 74, 78),
			Enum.Material.Metal
		)
	)
	local lamp = Kit.block(
		parent,
		Vector3.new(1, 0.6, 0.8),
		back * CFrame.new(doorX, 8, -0.5),
		rgb(255, 226, 170),
		Enum.Material.Neon
	)
	Kit.detail(lamp)
	local function spot(x: number, out: number): (CFrame?, Vector3)
		local cfAt = back * CFrame.new(x, 0, -out)
		local pos = cfAt.Position
		if Layout.isFree(pos, 2.5, 0.5) then
			return cfAt, pos
		end
		return nil, pos
	end
	local dumpX = doorX + (Kit.hash(seed + 1) < 0.5 and -1 or 1) * Props.between(seed + 2, 6, 9)
	local dumpCF = spot(dumpX, 2.4)
	if dumpCF and Kit.hash(seed + 3) < 0.7 then
		Props.dumpster(parent, dumpCF * CFrame.Angles(0, math.pi, 0), seed + 4)
		Layout.claim(dumpCF.Position, 4)
		local _, bagPos = spot(dumpX + 4.5, 1.8)
		if Kit.hash(seed + 5) < 0.6 then
			Props.trashBags(parent, bagPos, seed + 6, 2 + math.floor(Kit.hash(seed + 7) * 3))
		end
	end
	local palletCF = spot(doorX - (dumpX - doorX) * 0.8, 2.8)
	if palletCF and Kit.hash(seed + 8) < 0.5 then
		Layout.claim(palletCF.Position, 3)
		if Kit.hash(seed + 9) < 0.5 then
			Props.palletStack(parent, palletCF, seed + 10)
		else
			for i = 0, 1 + math.floor(Kit.hash(seed + 11) * 2) do
				Props.box(parent, palletCF * CFrame.new(i * 1.9 - 1, 0, (i % 2) * 0.8), seed + 12 + i)
			end
		end
	end
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
				local seed = rng:NextInteger(1, 1e6)
				Kit.building(parent, cf, {
					Name = shop[1],
					Size = Vector3.new(w, h, d),
					Wall = palette.Wall,
					WallMaterial = table.find(BRICK, palette) and Enum.Material.Brick or Enum.Material.Plaster,
					Trim = palette.Trim,
					Floors = math.max(2, math.floor(h / 10)),
					Shop = shopFront(shop, seed),
					Seed = seed,
					Dress = postersOnSides(seed),
				})
				backAlley(parent, cf, w, d, seed)
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
			local seed = rng:NextInteger(1, 1e6)
			Kit.building(parent, cf, {
				Name = "Building",
				Size = Vector3.new(w, h, d),
				Wall = palette.Wall,
				WallMaterial = table.find(STONE, palette) and Enum.Material.Limestone or Enum.Material.Brick,
				Trim = palette.Trim,
				Floors = math.floor(h / 10),
				Shop = shop and shopFront(shop, seed) or nil,
				Seed = seed,
			})
		end
	else -- Old Town: low brick and pastel shops
		local brick = rng:NextNumber() < 0.5
		local palette = brick and BRICK[rng:NextInteger(1, #BRICK)] or PASTEL[rng:NextInteger(1, #PASTEL)]
		local h = rng:NextInteger(2, 3) * 10 + rng:NextInteger(0, 3)
		local shop = nextShop()
		local seed = rng:NextInteger(1, 1e6)
		Kit.building(parent, cf, {
			Name = shop[1],
			Size = Vector3.new(w, h, d),
			Wall = palette.Wall,
			WallMaterial = brick and Enum.Material.Brick or Enum.Material.Plaster,
			Trim = palette.Trim,
			Floors = math.max(2, math.floor(h / 10)),
			Shop = shopFront(shop, seed),
			Seed = seed,
			Dress = postersOnSides(seed),
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

-- A half-built office block: fenced dirt lot, concrete frame, scaffolding, a tower crane
-- and the usual site clutter. Everything a crew would actually leave lying around.
local function constructionSite(parent: Instance, cf: CFrame, w: number, d: number, seed: number)
	local m = Kit.model("ConstructionSite", parent)
	local concrete = rgb(168, 164, 156)
	local galvanized = rgb(150, 152, 150)
	local dirt = Kit.block(
		m,
		Vector3.new(w + 8, 0.4, d + 8),
		cf * CFrame.new(0, 0.2, 0),
		rgb(116, 98, 76),
		Enum.Material.Ground,
		"SiteGround"
	)
	dirt.CastShadow = false
	local hw, hd = w / 2 + 3.6, d / 2 + 3.6
	local function fenceRun(ax: number, az: number, bx: number, bz: number)
		local a = (cf * CFrame.new(ax, 0.4, az)).Position
		local b = (cf * CFrame.new(bx, 0.4, bz)).Position
		local length = (b - a).Magnitude
		local run = CFrame.lookAt(a, b)
		local posts = math.max(1, math.floor(length / 8))
		for i = 0, posts do
			Kit.block(
				m,
				Vector3.new(0.3, 7, 0.3),
				run * CFrame.new(0, 3.5, -length * i / posts),
				galvanized,
				Enum.Material.Metal
			)
		end
		local mesh = Kit.block(
			m,
			Vector3.new(0.08, 6.4, length),
			run * CFrame.new(0, 3.6, -length / 2),
			galvanized,
			Enum.Material.DiamondPlate,
			"SiteFence"
		)
		mesh.Transparency = 0.55
		mesh.CastShadow = false
	end
	fenceRun(-hw, -hd, -7, -hd)
	fenceRun(7, -hd, hw, -hd)
	fenceRun(hw, -hd, hw, hd)
	fenceRun(hw, hd, -hw, hd)
	fenceRun(-hw, hd, -hw, -hd)
	local sign = Kit.block(
		m,
		Vector3.new(6, 3, 0.1),
		cf * CFrame.new(-12, 4, -hd - 0.1),
		rgb(226, 190, 50),
		Enum.Material.SmoothPlastic
	)
	Kit.detail(sign)
	Kit.label(sign, "HARD HAT AREA", { TextColor = rgb(30, 30, 30) })

	-- Concrete frame: columns, a finished first slab, half of the second, rebar poking out
	local fw, fd, fz = w - 8, d - 12, 1.5
	for ix = -1, 1 do
		for iz = -1, 1, 2 do
			Kit.block(
				m,
				Vector3.new(1.6, 21, 1.6),
				cf * CFrame.new(ix * fw / 2, 10.9, fz + iz * fd / 2),
				concrete,
				Enum.Material.Concrete,
				"Column"
			)
			if iz == -1 then
				for r = -1, 1, 2 do
					Kit.detail(
						Kit.block(
							m,
							Vector3.new(0.15, 3, 0.15),
							cf * CFrame.new(ix * fw / 2 + r * 0.4, 22.9, fz - fd / 2),
							rgb(110, 70, 50),
							Enum.Material.CorrodedMetal
						)
					)
				end
			end
		end
	end
	Kit.block(m, Vector3.new(fw + 2, 1, fd + 2), cf * CFrame.new(0, 10.4, fz), concrete, Enum.Material.Concrete, "Slab")
	Kit.block(
		m,
		Vector3.new(fw + 2, 1, fd / 2 + 1),
		cf * CFrame.new(0, 20.9, fz + fd / 4),
		concrete,
		Enum.Material.Concrete,
		"Slab"
	)
	Kit.block(
		m,
		Vector3.new(fw, 0.9, 0.7),
		cf * CFrame.new(0, 21.4, fz - fd / 2),
		rgb(120, 70, 50),
		Enum.Material.CorrodedMetal,
		"Beam"
	)
	Props.scaffold(m, cf * CFrame.new(0, 0.4, fz - fd / 2 - 1), fw + 2, 20)
	Props.crane(m, cf * CFrame.new(hw - 6, 0.4, hd - 6), seed, 80)

	-- Materials and kit around the yard
	local yard = {
		function(at: CFrame)
			Props.pallet(m, at, seed + 1)
			Kit.block(
				m,
				Vector3.new(3.6, 2, 4),
				at * CFrame.new(0, 1.85, 0),
				rgb(150, 84, 64),
				Enum.Material.Brick,
				"Bricks"
			)
		end,
		function(at: CFrame)
			for i = 0, 3 do
				Kit.cyl(
					m,
					8,
					2.6,
					at
						* CFrame.new(-2 + (i % 3) * 2.7, 1.3 + math.floor(i / 3) * 2.3, 0)
						* CFrame.Angles(math.rad(90), 0, 0),
					rgb(170, 166, 158),
					Enum.Material.Concrete,
					"Pipe"
				)
			end
		end,
		function(at: CFrame)
			Kit.ball(m, 11, at * CFrame.new(0, -2.8, 0), rgb(196, 176, 128), Enum.Material.Sand).Name = "SandPile"
		end,
		function(at: CFrame)
			Props.portaPotty(m, at, seed + 5)
		end,
		function(at: CFrame)
			Props.dumpster(m, at * CFrame.Angles(0, math.rad(90), 0), seed + 6)
		end,
		function(at: CFrame)
			Props.palletStack(m, at, seed + 7)
		end,
	}
	local spots = {
		{ -hw + 4, hd - 5 },
		{ -hw + 5, 0 },
		{ -6, hd - 5 },
		{ -hw + 3, -hd + 4 },
		{ hw - 3.6, -1 },
		{ 4, hd - 4 },
	}
	for i, place in yard do
		local spot = spots[i]
		place(Kit.settle(cf * CFrame.new(spot[1], 0.4, spot[2]), seed + i * 3, 25, 0))
	end
	for i = 1, 4 do
		Props.cone(m, (cf * CFrame.new(-6 + i * 2.6, 0, -hd - 2)).Position, seed + i * 9)
	end
	Props.barrier(m, cf * CFrame.new(hw - 6, 0, -hd - 2.5), seed + 40)
end

-- Surface car park: painted bays, a pay machine and whoever happens to be parked.
local function parkingLot(parent: Instance, cf: CFrame, w: number, d: number, seed: number)
	local m = Kit.model("ParkingLot", parent)
	local lot = Kit.block(
		m,
		Vector3.new(w + 8, 0.35, d + 8),
		cf * CFrame.new(0, 0.18, 0),
		rgb(66, 66, 68),
		Enum.Material.Asphalt,
		"Lot"
	)
	lot.CastShadow = false
	local bays = math.floor((w + 4) / 8)
	for row = -1, 1, 2 do
		for i = 0, bays do
			local x = -(w + 4) / 2 + i * 8
			Kit.detail(
				Kit.block(
					m,
					Vector3.new(0.35, 0.04, 9),
					cf * CFrame.new(x, 0.37, row * (d / 2 - 3)),
					rgb(200, 200, 192):Lerp(rgb(80, 80, 80), Kit.hash(seed + i) * 0.4),
					Enum.Material.SmoothPlastic
				)
			)
			if i < bays and Props.chance(seed + i * 3.3 + row, 0.55) then
				local center = cf * CFrame.new(x + 4, 0.35, row * (d / 2 - 3))
				Props.car(m, center * CFrame.Angles(0, row == 1 and math.pi or 0, 0), seed + i * 7 + row)
			end
		end
	end
	Kit.block(
		m,
		Vector3.new(1.4, 4.4, 1),
		cf * CFrame.new(w / 2 + 2, 2.55, 0),
		rgb(70, 90, 120),
		Enum.Material.Metal,
		"PayMachine"
	)
	Props.wheelieBin(m, cf * CFrame.new(-w / 2 - 2, 0.35, 2), seed + 99)
end

local function buildDistricts(parent: Instance, rng: Random)
	local spacing = 46
	local siteBuilt = false
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
						local lotSeed = rng:NextInteger(1, 1e6)
						if district.Kind == "Downtown" and not siteBuilt and r > 170 and r < 270 then
							siteBuilt = true
							constructionSite(folder, cf, w, d, lotSeed)
							claimRect(cf, w + 10, d + 10)
							continue
						elseif district.Kind ~= "OldTown" and Kit.hash(lotSeed) < 0.16 then
							parkingLot(folder, cf, w, d, lotSeed)
							claimRect(cf, w + 10, d + 10)
							continue
						end
						apron(folder, cf, w + 8, d + 8)
						districtBuilding(folder, rng, district.Kind, cf, w, d, r)
						claimRect(cf, w + 10, d + 10)
						if Kit.hash(lotSeed + 1) < 0.35 then
							local side = Kit.hash(lotSeed + 2) < 0.5 and -1 or 1
							local at = cf
								* CFrame.new(side * (w / 2 + 2.1), 0.5, d / 4)
								* CFrame.Angles(0, side * math.pi / 2, 0)
							if Kit.hash(lotSeed + 3) < 0.5 then
								Props.dumpster(folder, at, lotSeed + 4)
							else
								Props.wheelieBin(folder, at, lotSeed + 5)
								Props.wheelieBin(folder, at * CFrame.new(2.8, 0, 0.3), lotSeed + 6)
							end
						end
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
		Layout.addRoad(startPoint, target, 8) -- the walk plus its benches and lamps
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
					-- Front walk, garden, fence and whatever the family keeps in the yard
					local seed = rng:NextInteger(1, 1e6)
					local walk = Kit.block(
						folder,
						Vector3.new(3, 0.3, 6),
						cf * CFrame.new(0, 0.15, -d / 2 - 4.5),
						rgb(196, 192, 184),
						Enum.Material.Pavement
					)
					walk.CastShadow = false
					local yardW = w / 2 + 5
					local front = -d / 2 - 7
					local treeSide = Kit.hash(seed) < 0.5 and -1 or 1
					local driveSide = -treeSide
					local hasCar = Kit.hash(seed + 1) < 0.5
					local fenceColor = Props.pick(
						{ rgb(232, 230, 222), rgb(232, 230, 222), rgb(150, 118, 86), rgb(140, 138, 132) },
						seed + 2
					)
					if Kit.hash(seed + 3) > 0.18 then
						for side = -1, 1, 2 do
							local outer = (hasCar and side == driveSide) and (w / 2 - 1) or yardW
							local broken = Kit.hash(seed + 4 + side) < 0.12
							local from = cf * CFrame.new(side * 2.5, 0, front)
							local to = cf * CFrame.new(side * outer, 0, front)
							if broken then
								-- A section knocked down: the fence stops short and a rail lies in the grass
								to = cf * CFrame.new(side * (2.5 + (outer - 2.5) * 0.55), 0, front)
								Kit.detail(
									Kit.block(
										folder,
										Vector3.new(0.25, 0.4, (outer - 2.5) * 0.4),
										cf
											* CFrame.new(side * (outer - 1.5), 0.2, front - 1.2)
											* CFrame.Angles(0, math.rad(78), 0),
										fenceColor,
										Enum.Material.Wood
									)
								)
							end
							Kit.fence(folder, from.Position, to.Position, fenceColor)
							if Kit.hash(seed + 40 + side) < 0.45 then
								-- long grass where the mower can't reach the end post
								Kit.tuft(folder, (to * CFrame.new(-side * 0.7, 0, 0.6)).Position, seed + 41 + side)
							end
						end
					end
					Props.mailbox(folder, cf * CFrame.new(3.4, 0, front - 1), seed + 5)
					Kit.tree(
						folder,
						(cf * CFrame.new(treeSide * (w / 2 + 3), 0, -d / 2 - 6.6)).Position,
						rng:NextNumber(0.6, 0.7),
						LEAVES[rng:NextInteger(1, #LEAVES)]
					)
					Kit.bush(folder, (cf * CFrame.new(-treeSide * 3.6, 0, -d / 2 - 1.6)).Position, 0.7)
					if Kit.hash(seed + 6) < 0.5 then
						for i = 0, 1 do
							Props.flowerPot(
								folder,
								(cf * CFrame.new(3.8 + i * 1.6, 0, -d / 2 - 1.6)).Position,
								seed + 7 + i
							)
						end
					end
					-- Driveway and the family car
					if hasCar then
						local x = driveSide * (w / 2 + 4)
						local pad = Kit.block(
							folder,
							Vector3.new(7.5, 0.2, d + 10),
							cf * CFrame.new(x, 0.1, -5),
							rgb(176, 172, 164),
							Enum.Material.Concrete
						)
						pad.CastShadow = false
						Props.car(
							folder,
							cf * CFrame.new(x, 0.2, -3),
							seed + 8,
							Props.pick({ "Sedan", "Hatch", "Van", "Pickup" }, seed + 9)
						)
					end
					-- Bins: by the side wall, or out at the curb on collection day
					local binsAtCurb = Kit.hash(seed + 10) < 0.3
					local binCF = if binsAtCurb
						then cf * CFrame.new(6.6, 0, front - 1.6) * CFrame.Angles(0, math.pi, 0)
						else cf * CFrame.new(-driveSide * (w / 2 + 1.8), 0, d / 4)
					Props.wheelieBin(folder, binCF, seed + 11)
					if Kit.hash(seed + 12) < 0.5 then
						Props.wheelieBin(folder, binCF * CFrame.new(0, 0, 3), seed + 13)
					end
					-- Back yard
					local backyard = cf * CFrame.new(Props.between(seed + 14, -w / 3, w / 3), 0, d / 2 + 7)
					local roll = Kit.hash(seed + 15)
					if Layout.isFree(backyard.Position, 5, 0.5) then
						if roll < 0.22 then
							Props.swingSet(
								folder,
								backyard * CFrame.Angles(0, math.rad(Props.between(seed + 16, -20, 20)), 0),
								seed + 17
							)
						elseif roll < 0.45 then
							Props.shed(folder, Kit.settle(backyard, seed + 18, 15, 0), seed + 19)
						elseif roll < 0.6 then
							Props.doghouse(folder, backyard, seed + 20)
						elseif roll < 0.75 then
							Props.grill(folder, backyard, seed + 21)
						end
					end
					if Kit.hash(seed + 22) < 0.12 then
						Props.bike(
							folder,
							cf
								* CFrame.new(treeSide * (w / 2 - 2), 0, -d / 2 - 5)
								* CFrame.Angles(0, Kit.hash(seed + 23) * 3, 0),
							seed + 24,
							true
						)
					end
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
