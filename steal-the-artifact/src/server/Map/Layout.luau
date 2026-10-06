--[[
	Layout
	Keeps track of the ground that is already spoken for (zones, vault plots, roads,
	buildings) so the city dressing never lands on top of gameplay space.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Zones = require(ReplicatedStorage.Shared.Config.Zones)

local Layout = {}

type Road = { A: Vector3, B: Vector3, HalfWidth: number }
type Circle = { Center: Vector3, Radius: number }

local roads: { Road } = {}
local circles: { Circle } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Layout.reset()
	table.clear(roads)
	table.clear(circles)
	-- Surface zones keep a little breathing room around their footprint.
	for _, zone in Zones.List do
		if zone.Center.Y > -40 then
			local margin = zone.Id == "Marketplace" and 6 or 18
			table.insert(circles, { Center = flat(zone.Center), Radius = zone.Radius + margin })
		end
	end
end

function Layout.addRoad(a: Vector3, b: Vector3, halfWidth: number)
	table.insert(roads, { A = flat(a), B = flat(b), HalfWidth = halfWidth })
end

function Layout.addCircle(center: Vector3, radius: number)
	table.insert(circles, { Center = flat(center), Radius = radius })
end

local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-6 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / lengthSq, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

-- Distance from `position` to the nearest road edge (negative when on the road).
function Layout.roadClearance(position: Vector3): number
	local p = flat(position)
	local best = math.huge
	for _, road in roads do
		best = math.min(best, distanceToSegment(p, road.A, road.B) - road.HalfWidth)
	end
	return best
end

-- True if a circle of `radius` at `position` touches nothing reserved.
function Layout.isFree(position: Vector3, radius: number, roadGap: number?): boolean
	local p = flat(position)
	if p.Magnitude + radius > GameConfig.Map.WorldRadius - 24 then
		return false
	end
	for _, circle in circles do
		if (p - circle.Center).Magnitude < circle.Radius + radius then
			return false
		end
	end
	return Layout.roadClearance(p) > radius + (roadGap or 2)
end

-- Reserve a footprint (call after placing something solid).
function Layout.claim(position: Vector3, radius: number)
	Layout.addCircle(position, radius)
end

Layout.reset()

return Layout
