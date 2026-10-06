--[[
	Bakes the city into a place file so it opens in Studio fully built (Workspace.Map with
	a SpawnLocation, lighting and post-processing), with ServerStorage.MapData telling the
	server how to hook up to it.

	  rojo build default.project.json -o StealTheArtifact.rbxlx
	  lune run tools/build_place StealTheArtifact.rbxlx StealTheArtifact.rbxl

	The output format follows the extension (.rbxl binary, .rbxlx XML).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local H = require("../tests/harness")
local roblox = H.roblox

local input = process.args[1] or "StealTheArtifact.rbxlx"
local output = process.args[2] or input

local game = roblox.deserializePlace(fs.readFile(input))
H.useDataModel(game)
local workspace = game:GetService("Workspace")
local serverStorage = game:GetService("ServerStorage")
H.env.workspace = workspace

-- Start from a clean slate if the place already had a baked map.
for _, old in { workspace:FindFirstChild("Map"), serverStorage:FindFirstChild("MapData") } do
	old:Destroy()
end

local Environment = H.require("src/server/Map/Environment.luau")
local MapBuilder = H.require("src/server/Map/MapBuilder.luau")
local MapSerializer = H.require("src/server/Map/MapSerializer.luau")

local started = os.clock()
Environment.lighting()
local data = MapBuilder.generate()
local version = string.format("%x-%x", os.time(), math.random(0, 0xffffff))
data.Root:SetAttribute("MapVersion", version)
data.Root.Parent = workspace
local module = MapSerializer.store(serverStorage, data, version)

-- Prove the server will be able to hook up to what we just wrote.
local loaded = MapBuilder.loadPrebuilt(data.Root, serverStorage)
assert(loaded, "the baked map didn't load back")
assert(loaded.SpawnLocation == data.SpawnLocation, "spawn location didn't round-trip")
assert(#loaded.Plots == #data.Plots, "plots didn't round-trip")

local parts = 0
for _, child in data.Root:GetDescendants() do
	if child:IsA("BasePart") then
		parts += 1
	end
end
local binary = string.sub(output, -6) ~= ".rbxlx"
fs.writeFile(output, roblox.serializePlace(game, not binary))
print(
	string.format(
		"Baked %d parts (%d map references, %d KB of descriptors) into %s in %.1fs",
		parts,
		#module.Refs:GetChildren(),
		math.floor(#module.Source / 1024),
		output,
		os.clock() - started
	)
)
