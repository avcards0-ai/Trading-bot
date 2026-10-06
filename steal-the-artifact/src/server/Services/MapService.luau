--[[
	MapService
	Builds the world and exposes the map descriptors to every other service.
]]

local MapBuilder = require(script.Parent.Parent.Map.MapBuilder)

local MapService = {
	Name = "MapService",
	Data = nil :: MapBuilder.MapData?,
}

function MapService:Start()
	self.Data = MapBuilder.build()
end

function MapService:Get(): MapBuilder.MapData
	return assert(self.Data, "Map not built yet")
end

function MapService:GetZone(zoneId: string): MapBuilder.ZoneData?
	return self:Get().Zones[zoneId]
end

function MapService:GetPlot(index: number)
	return self:Get().Plots[index]
end

-- True if `position` is inside an oriented box region { CFrame, Size }.
function MapService.inRegion(region: { CFrame: CFrame, Size: Vector3 }, position: Vector3, padding: number?): boolean
	local localPos = region.CFrame:PointToObjectSpace(position)
	local half = region.Size / 2 + Vector3.one * (padding or 0)
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

return MapService
