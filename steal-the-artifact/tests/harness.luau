--[[
	Test harness for running game modules outside Roblox with Lune (https://lune-org.github.io).

	It emulates just enough of the DataModel for our code:
	  * `script` references that follow the Rojo layout (src/shared -> ReplicatedStorage.Shared, ...)
	  * `require(script.Parent.Foo)` resolution onto files
	  * Roblox datatypes / Instance.new from @lune/roblox (which validates property names!)
	  * light stubs for services and the few engine APIs Lune doesn't implement
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Harness = {}
Harness.VoxelWrites = {} :: { any }

local ROOT = process.cwd
if string.sub(ROOT, -1) ~= "/" then
	ROOT ..= "/"
end
Harness.Root = ROOT

-- Deterministic stand-in for Roblox's Random datatype.
local RandomStub = {}
RandomStub.__index = RandomStub
function RandomStub.new(seed: number?)
	return setmetatable({ state = (seed or 12345) % 2147483647 + 1 }, RandomStub)
end
function RandomStub:_next(): number
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function RandomStub:NextNumber(min: number?, max: number?): number
	local low, high = min or 0, max or 1
	return low + (high - low) * self:_next()
end
function RandomStub:NextInteger(min: number, max: number): number
	return math.min(max, min + math.floor(self:_next() * (max - min + 1)))
end

local function signalStub()
	return {
		Connect = function()
			return { Disconnect = function() end, Connected = true }
		end,
		Once = function()
			return { Disconnect = function() end }
		end,
		Wait = function() end,
	}
end

local attributes: { [string]: any } = {}

-- Module references --------------------------------------------------------------------------

local Ref = {}
local cache: { [string]: any } = {}
local refs: { [string]: any } = {}

-- Lune's fs calls yield, which isn't allowed inside metamethods, so snapshot the source
-- tree (paths + contents) up front.
local files: { [string]: string } = {}
local dirs: { [string]: { string } } = {}
local function scan(dir: string)
	local entries = fs.readDir(ROOT .. dir)
	table.sort(entries)
	dirs[dir] = entries
	for _, entry in entries do
		local path = dir .. "/" .. entry
		if fs.isDir(ROOT .. path) then
			scan(path)
		elseif string.match(entry, "%.luau$") then
			files[path] = fs.readFile(ROOT .. path)
		end
	end
end
scan("src")

local function isFile(path: string): boolean
	return files[path] ~= nil
end
local function isDir(path: string): boolean
	return dirs[path] ~= nil
end

local function makeRef(path: string, name: string, kind: string)
	local key = path
	if refs[key] then
		return refs[key]
	end
	local ref = setmetatable({ __path = path, __name = name, __kind = kind }, Ref)
	refs[key] = ref
	return ref
end

local function dirOf(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or ""
end

local function childOf(ref, name: string)
	local base = ref.__kind == "folder" and ref.__path or dirOf(ref.__path)
	if ref.__kind ~= "folder" then
		return nil
	end
	for _, suffix in { ".luau", ".server.luau", ".client.luau" } do
		local candidate = base .. "/" .. name .. suffix
		if isFile(candidate) then
			return makeRef(candidate, name, suffix == ".luau" and "module" or "script")
		end
	end
	if isDir(base .. "/" .. name) then
		return makeRef(base .. "/" .. name, name, "folder")
	end
	return nil
end

-- Logical parents follow the Rojo project, not the filesystem root.
local function parentOf(ref)
	local path = ref.__path
	local parentPath = dirOf(path)
	if parentPath == "" or parentPath == "src" then
		return nil
	end
	return makeRef(parentPath, string.match(parentPath, "([^/]+)$") or parentPath, "folder")
end

Ref.__index = function(self, key)
	if key == "Parent" then
		return parentOf(self)
	elseif key == "Name" then
		return rawget(self, "__name")
	elseif key == "FindFirstChild" or key == "WaitForChild" then
		return function(this, name)
			return childOf(this, name)
		end
	elseif key == "IsA" then
		return function(this, className)
			if className == "ModuleScript" then
				return this.__kind == "module"
			elseif className == "Folder" then
				return this.__kind == "folder"
			end
			return false
		end
	elseif key == "GetChildren" then
		return function(this)
			local children = {}
			if this.__kind == "folder" then
				for _, entry in dirs[this.__path] or {} do
					local name = string.match(entry, "^(.-)%.luau$") or entry
					name = string.gsub(name, "%.server$", "")
					name = string.gsub(name, "%.client$", "")
					local child = childOf(this, name)
					if child then
						table.insert(children, child)
					end
				end
			end
			return children
		end
	end
	local child = childOf(self, key)
	if child == nil then
		error(string.format("%s is not a valid member of %s", tostring(key), self.__path), 2)
	end
	return child
end

-- Services ----------------------------------------------------------------------------------

local dataModel = roblox.Instance.new("DataModel")

local services = {}
services.ReplicatedStorage = setmetatable({
	Shared = makeRef("src/shared", "Shared", "folder"),
	GetAttribute = function(_, key)
		return attributes[key]
	end,
	SetAttribute = function(_, key, value)
		attributes[key] = value
	end,
	GetAttributeChangedSignal = function()
		return signalStub()
	end,
	FindFirstChild = function()
		return nil
	end,
}, {})
services.RunService = {
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
	IsStudio = function()
		return true
	end,
	Heartbeat = signalStub(),
	RenderStepped = signalStub(),
	Stepped = signalStub(),
	BindToRenderStep = function() end,
}
services.CollectionService = {
	AddTag = function(_, instance, tag)
		pcall(function()
			instance:AddTag(tag)
		end)
	end,
	GetTagged = function()
		return {}
	end,
	GetInstanceAddedSignal = function()
		return signalStub()
	end,
	GetInstanceRemovedSignal = function()
		return signalStub()
	end,
}
services.Players = {
	LocalPlayer = {
		UserId = 1,
		Name = "Tester",
		DisplayName = "Tester",
		GetAttribute = function()
			return nil
		end,
		SetAttribute = function() end,
		CharacterAdded = signalStub(),
		Character = nil,
	},
	PlayerAdded = signalStub(),
	PlayerRemoving = signalStub(),
	GetPlayers = function()
		return {}
	end,
	GetPlayerByUserId = function()
		return nil
	end,
}
services.TweenService = {
	Create = function()
		return { Play = function() end, Cancel = function() end, Completed = signalStub() }
	end,
}
services.HttpService = {
	JSONEncode = function(_, value)
		return serde.encode("json", value)
	end,
	JSONDecode = function(_, text)
		return serde.decode("json", text)
	end,
	GenerateGUID = function()
		return string.format(
			"%08x-%04x-%04x",
			math.random(0, 0x7fffffff),
			math.random(0, 0xffff),
			math.random(0, 0xffff)
		)
	end,
}
services.UserInputService = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	GamepadEnabled = false,
	InputBegan = signalStub(),
	InputChanged = signalStub(),
	InputEnded = signalStub(),
}
services.GuiService = {
	IsTenFootInterface = function()
		return false
	end,
}

local game = {
	GetService = function(_, name: string)
		if services[name] then
			return services[name]
		end
		local ok, service = pcall(function()
			return dataModel:GetService(name)
		end)
		if ok then
			return service
		end
		return setmetatable({}, {
			__index = function()
				return signalStub()
			end,
		})
	end,
	IsLoaded = function()
		return true
	end,
	Loaded = signalStub(),
	JobId = "test-job",
	BindToClose = function() end,
}

local terrain = {
	FillBlock = function() end,
	FillCylinder = function() end,
	FillBall = function() end,
	Clear = function() end,
	CountCells = function()
		return 0
	end,
	SetMaterialColor = function() end,
	-- Voxel API emulation: reads come back empty (air) and writes are recorded for tests.
	ReadVoxels = function(_, region, resolution)
		local size = region.Size / resolution
		local materials, occupancies = { Size = size }, { Size = size }
		for x = 1, size.X do
			materials[x], occupancies[x] = {}, {}
			for y = 1, size.Y do
				materials[x][y], occupancies[x][y] = {}, {}
				for z = 1, size.Z do
					materials[x][y][z] = roblox.Enum.Material.Air
					occupancies[x][y][z] = 0
				end
			end
		end
		return materials, occupancies
	end,
	WriteVoxels = function(_, region, resolution, materials, occupancies)
		table.insert(Harness.VoxelWrites, {
			Region = region,
			Resolution = resolution,
			Materials = materials,
			Occupancies = occupancies,
		})
	end,
	FindFirstChildOfClass = function()
		return nil
	end,
}
local workspaceStub = {
	Terrain = terrain,
	Gravity = 196.2,
	FindFirstChild = function()
		return nil
	end,
	GetServerTimeNow = function()
		return os.clock()
	end,
	Raycast = function()
		return nil
	end,
}

-- Loader --------------------------------------------------------------------------------------

local env: { [string]: any } = {}

local function requireRef(ref: any)
	if typeof(ref) == "Instance" and ref:IsA("ModuleScript") then
		-- Generated modules (e.g. ServerStorage.MapData) live in the DataModel, not on disk.
		local moduleEnv = table.clone(env)
		moduleEnv.script = ref
		return luau.load(ref.Source, { debugName = ref:GetFullName(), environment = moduleEnv })()
	end
	assert(type(ref) == "table" and ref.__path, "require() expects a module reference")
	local path = ref.__path
	if ref.__kind == "folder" then
		if isFile(path .. "/init.luau") then
			path ..= "/init.luau"
		else
			error("Cannot require folder " .. path)
		end
	end
	if cache[path] ~= nil then
		return cache[path]
	end
	local source = files[path]
	local moduleEnv = table.clone(env)
	moduleEnv.script = ref
	local chunk = luau.load(source, { debugName = path, environment = moduleEnv })
	local result = chunk()
	cache[path] = result
	return result
end

env.require = requireRef
env.game = game
env.workspace = workspaceStub
env.Random = RandomStub
env.warn = function(...)
	print("[warn]", ...)
end
env.tick = os.clock
for _, name in
	{
		"Instance",
		"Vector3",
		"Vector2",
		"CFrame",
		"Color3",
		"ColorSequence",
		"ColorSequenceKeypoint",
		"NumberSequence",
		"NumberSequenceKeypoint",
		"NumberRange",
		"UDim",
		"UDim2",
		"Enum",
		"Rect",
		"BrickColor",
		"Font",
		"PhysicalProperties",
		"Region3",
		"Region3int16",
	}
do
	env[name] = (roblox :: any)[name]
end
-- Lune 0.8's CFrame.lookAt mirrors the Z axis of the look direction; use Roblox's math.
do
	local RobloxCFrame = (roblox :: any).CFrame
	local Vector3 = (roblox :: any).Vector3
	local function lookAt(at, target, up)
		local look = (target - at).Unit
		local upVector = up or Vector3.yAxis
		local right = look:Cross(upVector)
		if right.Magnitude < 1e-5 then
			right = look:Cross(Vector3.zAxis)
		end
		right = right.Unit
		return RobloxCFrame.fromMatrix(at, right, right:Cross(look))
	end
	env.CFrame = setmetatable({ lookAt = lookAt }, { __index = RobloxCFrame })
end
env.task = require("@lune/task")
local function paramsStub()
	return {
		new = function()
			return { FilterType = nil, FilterDescendantsInstances = {}, IgnoreWater = false }
		end,
	}
end
env.TweenInfo = (roblox :: any).TweenInfo or {
	new = function(...)
		return { ... }
	end,
}
env.RaycastParams = paramsStub()
env.OverlapParams = paramsStub()

Harness.require = function(path: string)
	local name = string.match(path, "([^/]+)%.luau$") or path
	return requireRef(makeRef(path, name, "module"))
end
Harness.ref = function(path: string, kind: string?)
	local name = string.match(path, "([^/%.]+)[^/]*$") or path
	return makeRef(path, name, kind or "module")
end
Harness.roblox = roblox
Harness.Attributes = attributes
Harness.env = env
Harness.services = services
-- Route game:GetService to another DataModel (e.g. a place file being edited).
function Harness.useDataModel(model: any)
	dataModel = model
end
Harness.workspace = workspaceStub
Harness.signalStub = signalStub

-- Assertions ------------------------------------------------------------------------------------

local passed, failed = 0, 0
local failures: { string } = {}

function Harness.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ✓ " .. name)
	else
		failed += 1
		table.insert(failures, name .. ": " .. tostring(err))
		print("  ✗ " .. name .. "\n      " .. tostring(err))
	end
end

function Harness.check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

function Harness.summary(): number
	print(string.format("\n%d passed, %d failed", passed, failed))
	return failed
end

function Harness.listFiles(dir: string): { string }
	local list = {}
	for path in files do
		if
			string.sub(path, 1, #dir + 1) == dir .. "/" and not string.find(string.sub(path, #dir + 2), "/", 1, true)
		then
			table.insert(list, path)
		end
	end
	table.sort(list)
	return list
end

function Harness.listFilesRecursive(dir: string): { string }
	local list = {}
	for path in files do
		if string.sub(path, 1, #dir + 1) == dir .. "/" then
			table.insert(list, path)
		end
	end
	table.sort(list)
	return list
end

function Harness.source(path: string): string
	return files[path]
end

return Harness
