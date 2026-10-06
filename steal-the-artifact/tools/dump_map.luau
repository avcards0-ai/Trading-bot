--[[
	Generates the map headlessly (same code the server runs) and writes its geometry to
	JSON so it can be previewed outside Roblox.  Usage (from the project folder):
	  lune run tools/dump_map [out.json]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local H = require("../tests/harness")
local roblox = H.roblox

-- A real Workspace + Terrain so MapBuilder can parent into it. Terrain voxels can't be
-- written outside Roblox, so fills are recorded instead.
local terrainCalls = {}
local function record(kind)
	return function(_, ...)
		local args = { ... }
		local entry: { [string]: any } = { Kind = kind }
		if kind == "Block" then
			entry.CFrame = { args[1]:GetComponents() }
			entry.Size = { args[2].X, args[2].Y, args[2].Z }
			entry.Material = args[3].Name
		elseif kind == "Cylinder" then
			entry.CFrame = { args[1]:GetComponents() }
			entry.Height = args[2]
			entry.Radius = args[3]
			entry.Material = args[4].Name
		elseif kind == "Ball" then
			entry.Center = { args[1].X, args[1].Y, args[1].Z }
			entry.Radius = args[2]
			entry.Material = args[3].Name
		elseif kind == "Wedge" then
			entry.CFrame = { args[1]:GetComponents() }
			entry.Size = { args[2].X, args[2].Y, args[2].Z }
			entry.Material = args[3].Name
		end
		table.insert(terrainCalls, entry)
	end
end
roblox.implementMethod("Terrain", "FillBlock", record("Block"))
roblox.implementMethod("Terrain", "FillCylinder", record("Cylinder"))
roblox.implementMethod("Terrain", "FillBall", record("Ball"))
roblox.implementMethod("Terrain", "FillWedge", record("Wedge"))
roblox.implementMethod("Terrain", "SetMaterialColor", function() end)
roblox.implementMethod("Terrain", "Clear", function()
	table.clear(terrainCalls)
end)

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local terrain = roblox.Instance.new("Terrain")
terrain.Parent = workspace
H.env.workspace = workspace

H.useDataModel(game)
local Environment = H.require("src/server/Map/Environment.luau")
local MapBuilder = H.require("src/server/Map/MapBuilder.luau")
Environment.terrain()
local map = MapBuilder.generate()

local function round(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end
local function vec(v): { number }
	return { round(v.X), round(v.Y), round(v.Z) }
end
local function cframe(cf): { number }
	local out = {}
	for i, n in { cf:GetComponents() } do
		out[i] = round(n)
	end
	return out
end
local function color(c): { number }
	return { round(c.R), round(c.G), round(c.B) }
end

local parts = {}
local beams = {}
local nextModelId = 0
local function modelOf(inst)
	-- Lune hands out a fresh wrapper per lookup, so tag models with a stable id instead.
	local model = inst:FindFirstAncestorWhichIsA("Model")
	if not model then
		return nil, nil
	end
	local id = model:GetAttribute("QAModelId")
	if not id then
		nextModelId += 1
		id = nextModelId
		model:SetAttribute("QAModelId", id)
	end
	return id, model.Name
end
local lights = {}
local labels = {}
for _, inst in map.Root:GetDescendants() do
	if inst:IsA("BasePart") then
		local entry: { [string]: any } = {
			Class = inst.ClassName,
			CFrame = cframe(inst.CFrame),
			Size = vec(inst.Size),
			Color = color(inst.Color),
			Material = inst.Material.Name,
			Transparency = round(inst.Transparency),
			Reflectance = round(inst.Reflectance),
			Name = inst.Name,
			CanCollide = inst.CanCollide,
			CastShadow = inst.CastShadow,
		}
		entry.Model, entry.ModelName = modelOf(inst)
		local holder = inst:FindFirstAncestorWhichIsA("Model")
		if holder then
			entry.ParentModel = modelOf(holder)
		end
		if inst:IsA("Part") then
			entry.Shape = inst.Shape.Name
		end
		local mesh = inst:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			entry.Mesh = mesh.MeshType.Name
			entry.MeshScale = vec(mesh.Scale)
		end
		table.insert(parts, entry)
	elseif inst:IsA("Beam") then
		local a0, a1 = inst.Attachment0, inst.Attachment1
		if a0 and a1 then
			local w0 = (a0.Parent :: any).CFrame * a0.CFrame
			local w1 = (a1.Parent :: any).CFrame * a1.CFrame
			table.insert(beams, {
				P0 = vec(w0.Position),
				P1 = vec(w1.Position),
				X0 = vec(w0.RightVector),
				X1 = vec(w1.RightVector),
				C0 = round(inst.CurveSize0),
				C1 = round(inst.CurveSize1),
				Width = round(inst.Width0),
			})
		end
	elseif inst:IsA("Light") then
		local parent = inst.Parent
		if parent and parent:IsA("BasePart") then
			table.insert(lights, {
				Class = inst.ClassName,
				Position = vec(parent.CFrame.Position),
				Color = color(inst.Color),
				Brightness = round(inst.Brightness),
				Range = round((inst :: any).Range or 0),
			})
		end
	elseif inst:IsA("TextLabel") then
		local gui = inst:FindFirstAncestorWhichIsA("SurfaceGui")
		local part = gui and gui.Parent
		if gui and part and part:IsA("BasePart") then
			table.insert(labels, {
				Text = inst.Text,
				Face = gui.Face.Name,
				Part = { CFrame = cframe(part.CFrame), Size = vec(part.Size) },
				Color = color(inst.TextColor3),
				Background = color(inst.BackgroundColor3),
				BackgroundTransparency = round(inst.BackgroundTransparency),
			})
		end
	end
end

local spawn = map.SpawnLocation
local plotSpawns = {}
local plotCFrames = {}
for _, plot in map.Plots do
	table.insert(plotSpawns, cframe(plot.SpawnCFrame))
	table.insert(plotCFrames, cframe(plot.CFrame))
end
local zones = {}
for _, zone in H.require("src/shared/Config/Zones.luau").List do
	table.insert(zones, { Id = zone.Id, Center = vec(zone.Center), Radius = zone.Radius })
end

local out = process.args[1] or "map.json"
fs.writeFile(
	out,
	serde.encode("json", {
		Parts = parts,
		Beams = beams,
		Lights = lights,
		Labels = labels,
		Terrain = terrainCalls,
		Spawn = spawn and cframe(spawn.CFrame) or nil,
		PlotSpawns = plotSpawns,
		PlotCFrames = plotCFrames,
		Zones = zones,
		Mounds = (function()
			local list = {}
			for _, mound in (map :: any).Terrain.Mounds do
				table.insert(list, { Center = vec(mound.Center), Radius = mound.Radius, Height = mound.Height })
			end
			return list
		end)(),
	})
)
print(
	string.format(
		"Wrote %d parts, %d lights, %d labels, %d terrain fills to %s",
		#parts,
		#lights,
		#labels,
		#terrainCalls,
		out
	)
)
