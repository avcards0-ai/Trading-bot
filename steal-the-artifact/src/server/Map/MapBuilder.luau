--[[
	MapBuilder
	Produces the world plus the descriptors the gameplay services consume (spawn points,
	patrol routes, security devices, plots, hatches...).

	The place file ships with the city prebuilt in Workspace.Map (see tools/build_place.luau),
	so `build` normally just reads ServerStorage.MapData and hooks up to it; edits made in
	Studio are kept. If the prebuilt map is missing or doesn't match, the city is generated
	from code instead. Everything is deterministic, so every server gets the same city.
]]

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local City = require(script.Parent.City)
local Environment = require(script.Parent.Environment)
local Layout = require(script.Parent.Layout)
local MapSerializer = require(script.Parent.MapSerializer)
local Plots = require(script.Parent.Plots)
local Marketplace = require(script.Parent.Marketplace)
local Museum = require(script.Parent.Museum)
local Laboratory = require(script.Parent.Laboratory)
local Temple = require(script.Parent.Temple)
local Warehouse = require(script.Parent.Warehouse)
local HighSecurityVault = require(script.Parent.HighSecurityVault)
local Underground = require(script.Parent.Underground)

export type ZoneData = {
	Id: string,
	Folder: Instance,
	Spawns: { CFrame },
	Patrol: { Vector3 },
	Lasers: { any },
	Cameras: { any },
	Traps: { any },
	Hatches: { any },
	[string]: any,
}

export type MapData = {
	Root: Folder,
	Zones: { [string]: ZoneData },
	Plots: { Plots.PlotData },
	Hatches: { any },
	Boards: { [string]: BasePart },
	SpawnLocation: SpawnLocation,
	Terrain: Environment.TerrainPlan,
}

local MapBuilder = {}

-- Builds a fresh city into a new, unparented "Map" folder. Terrain and lighting are separate.
function MapBuilder.generate(): MapData
	local root = Instance.new("Folder")
	root.Name = "Map"

	Layout.reset()
	Environment.ground(root)

	local plots = Plots(root)
	local plotCFrames = {}
	for _, plot in plots do
		table.insert(plotCFrames, plot.CFrame)
		Layout.addCircle(plot.CFrame.Position, 74)
	end
	Environment.roads(root, plotCFrames)
	Environment.border(root)

	local zones: { [string]: ZoneData } = {}
	zones.Marketplace = Marketplace(root)
	zones.Museum = Museum(root)
	zones.Laboratory = Laboratory(root)
	zones.Temple = Temple(root)
	zones.Warehouse = Warehouse(root)
	zones.Vault = HighSecurityVault(root)

	-- Every surface hatch leads down; each arrival gets a matching hatch back up.
	local links = {}
	local labels =
		{ Marketplace = "Up to the Marketplace", Laboratory = "Up to the Laboratory", Temple = "Up to the Temple" }
	for zoneId, label in labels do
		for _, hatch in zones[zoneId].Hatches do
			table.insert(links, {
				Label = label,
				Arrival = hatch.Destination,
				Exit = CFrame.new(hatch.Part.CFrame.Position + Vector3.new(6, 3.5, 0)),
			})
		end
	end
	zones.Underground = Underground(root, links)

	-- Dressing goes last so it can fit around everything above.
	City.build(root)
	local terrainPlan = Environment.planTerrain(root)
	Environment.scenery(root)
	zones.SecretRoom = {
		Id = "SecretRoom",
		Folder = zones.Underground.Folder,
		Spawns = zones.Underground.SecretSpawns,
		Patrol = {},
		Lasers = {},
		Cameras = {},
		Traps = {},
		Hatches = {},
	}

	local hatches = {}
	for _, zone in zones do
		if zone.Id ~= "SecretRoom" then
			for _, hatch in zone.Hatches do
				table.insert(hatches, hatch)
			end
		end
	end

	return {
		Root = root,
		Zones = zones,
		Plots = plots,
		Hatches = hatches,
		Boards = zones.Marketplace.Boards,
		SpawnLocation = zones.Marketplace.SpawnLocation,
		Terrain = terrainPlan,
	}
end

-- Hooks up to the map that shipped in the place file, or returns nil (with a warning).
function MapBuilder.loadPrebuilt(root: Instance, storage: Instance?): MapData?
	local module = (storage or ServerStorage):FindFirstChild("MapData")
	if not module or not module:IsA("ModuleScript") then
		warn("[Map] Workspace.Map has no ServerStorage.MapData next to it; generating the city instead")
		return nil
	end
	if module:GetAttribute("MapVersion") ~= root:GetAttribute("MapVersion") then
		warn("[Map] ServerStorage.MapData belongs to a different Workspace.Map; generating the city instead")
		return nil
	end
	local refs = module:FindFirstChild("Refs")
	local ok, result = pcall(function()
		local decoded = HttpService:JSONDecode(require(module) :: any)
		return MapSerializer.decode(decoded, function(i)
			local ref = refs and refs:FindFirstChild(tostring(i))
			return if ref and ref:IsA("ObjectValue") then ref.Value else nil
		end)
	end)
	if not ok then
		warn("[Map] Couldn't use the prebuilt map (" .. tostring(result) .. "); generating the city instead")
		return nil
	end
	return result
end

function MapBuilder.build(): MapData
	local started = os.clock()
	local existing = workspace:FindFirstChild("Map")
	local prebuilt = if existing then MapBuilder.loadPrebuilt(existing) else nil
	local map: MapData
	local source = "prebuilt"
	if prebuilt then
		map = prebuilt
	else
		if existing then
			existing:Destroy()
		end
		Environment.lighting()
		map = MapBuilder.generate()
		map.Root.Parent = workspace
		source = "generated"
	end

	-- Terrain can't be stored in the place from outside Studio, so it's built here and replaces
	-- the stand-in parts (unless someone has already sculpted terrain of their own in Studio).
	if workspace.Terrain:CountCells() == 0 then
		local sculpted = Environment.terrain(map.Terrain, map.Root)
		local standIns = map.Root:FindFirstChild("TerrainStandIns")
		if standIns and sculpted then
			standIns:Destroy()
		elseif standIns then
			-- Flat terrain only: drop the flat stand-in, keep the hills and paths as visuals.
			local ground = standIns:FindFirstChild("Ground")
			if ground then
				ground:Destroy()
			end
		end
	end
	Environment.clouds()
	print(string.format("[Map] Ready (%s city, %.2fs)", source, os.clock() - started))
	return map
end

return MapBuilder
