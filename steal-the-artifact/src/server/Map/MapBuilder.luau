--[[
	MapBuilder
	Generates the whole world at server start and returns descriptors the gameplay
	services consume (spawn points, patrol routes, security devices, plots, hatches...).
	Everything is deterministic, so every server gets the same city.
]]

local Environment = require(script.Parent.Environment)
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
}

local MapBuilder = {}

function MapBuilder.build(): MapData
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Map"

	local started = os.clock()
	Environment.terrain()
	Environment.lighting()

	local plots = Plots(root)
	local plotCFrames = {}
	for _, plot in plots do
		table.insert(plotCFrames, plot.CFrame)
	end
	Environment.roads(root, plotCFrames)
	Environment.border(root)
	Environment.scenery(root, plotCFrames)

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
				Exit = CFrame.new(hatch.Part.Position + Vector3.new(6, 3.5, 0)),
			})
		end
	end
	zones.Underground = Underground(root, links)
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

	root.Parent = workspace
	print(string.format("[Map] Generated %d instances in %.2fs", #root:GetDescendants(), os.clock() - started))

	return {
		Root = root,
		Zones = zones,
		Plots = plots,
		Hatches = hatches,
		Boards = zones.Marketplace.Boards,
		SpawnLocation = zones.Marketplace.SpawnLocation,
	}
end

return MapBuilder
