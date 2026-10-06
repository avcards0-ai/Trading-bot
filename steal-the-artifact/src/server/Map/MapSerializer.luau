--[[
	MapSerializer
	Lets the place file ship with the city already built (Workspace.Map), so Studio shows
	the real world in edit mode and hand edits survive. The descriptor tables the gameplay
	services need (spawn points, patrols, lasers, plots...) are stored next to it:

	  ServerStorage.MapData            ModuleScript returning the descriptors as JSON
	  ServerStorage.MapData.Refs       ObjectValues "1".."n" pointing at the map instances

	Encoded values: numbers, strings, booleans, { t = table } (shared tables keep their
	identity), { i = ref }, { c = CFrame components }, { v = Vector3 }, { k = Color3 }.
]]

local MapSerializer = {}

MapSerializer.FormatVersion = 1

local function number(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		error("can't encode non-finite number")
	end
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	return string.format("%.9g", n)
end

local function str(s: string): string
	return '"'
		.. string.gsub(s, '[%c"\\]', function(c)
			local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return escapes[c] or string.format("\\u%04x", string.byte(c))
		end)
		.. '"'
end

local function list(values: { number }): string
	local out = table.create(#values)
	for i, v in values do
		out[i] = number(v)
	end
	return "[" .. table.concat(out, ",") .. "]"
end

-- Returns the JSON text and the instances it refers to (index = ref number).
function MapSerializer.encode(data: { [any]: any }): (string, { Instance })
	local tables: { string } = {}
	local tableIds: { [any]: number } = {}
	local refs: { Instance } = {}
	local refIds: { [Instance]: number } = {}

	local encodeValue: (any) -> string
	local function encodeTable(t: { [any]: any }): number
		local existing = tableIds[t]
		if existing then
			return existing
		end
		local id = #tables + 1
		tableIds[t] = id
		tables[id] = "" -- reserve the slot before recursing
		local keys = {}
		for key in t do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then
				return a < b
			end
			return type(a) == "number"
		end)
		local entries = table.create(#keys)
		for i, key in keys do
			local keyText
			if type(key) == "number" then
				keyText = number(key)
			elseif type(key) == "string" then
				keyText = str(key)
			else
				error("map descriptors can only use string or number keys, got " .. typeof(key))
			end
			entries[i] = "[" .. keyText .. "," .. encodeValue(t[key]) .. "]"
		end
		tables[id] = "[" .. table.concat(entries, ",") .. "]"
		return id
	end

	encodeValue = function(value: any): string
		local kind = typeof(value)
		if kind == "number" then
			return number(value)
		elseif kind == "string" then
			return str(value)
		elseif kind == "boolean" then
			return value and "true" or "false"
		elseif kind == "table" then
			return '{"t":' .. encodeTable(value) .. "}"
		elseif kind == "Instance" then
			local id = refIds[value]
			if not id then
				table.insert(refs, value)
				id = #refs
				refIds[value] = id
			end
			return '{"i":' .. id .. "}"
		elseif kind == "CFrame" then
			return '{"c":' .. list({ value:GetComponents() }) .. "}"
		elseif kind == "Vector3" then
			return '{"v":' .. list({ value.X, value.Y, value.Z }) .. "}"
		elseif kind == "Color3" then
			return '{"k":' .. list({ value.R, value.G, value.B }) .. "}"
		end
		error("can't encode a " .. kind .. " in the map descriptors")
	end

	local root = encodeValue(data)
	local json = string.format(
		'{"format":%d,"root":%s,"tables":[%s]}',
		MapSerializer.FormatVersion,
		root,
		table.concat(tables, ",")
	)
	return json, refs
end

-- `decoded` is the parsed JSON; `resolve(i)` returns the instance for ref i (or nil).
function MapSerializer.decode(decoded: any, resolve: (number) -> Instance?): any
	assert(type(decoded) == "table" and decoded.format == MapSerializer.FormatVersion, "unknown map data format")
	local built: { [number]: { [any]: any } } = {}
	local raw = decoded.tables

	local decodeValue: (any) -> any
	local function decodeTable(id: number): { [any]: any }
		local existing = built[id]
		if existing then
			return existing
		end
		local t = {}
		built[id] = t
		for _, entry in raw[id] do
			t[entry[1]] = decodeValue(entry[2])
		end
		return t
	end

	decodeValue = function(value: any): any
		if type(value) ~= "table" then
			return value
		elseif value.t then
			return decodeTable(value.t)
		elseif value.i then
			local instance = resolve(value.i)
			if instance == nil then
				error(string.format("map reference %d is missing (was part of the map deleted?)", value.i))
			end
			return instance
		elseif value.c then
			return CFrame.new(table.unpack(value.c))
		elseif value.v then
			return Vector3.new(value.v[1], value.v[2], value.v[3])
		elseif value.k then
			return Color3.new(value.k[1], value.k[2], value.k[3])
		end
		error("unknown value in map data")
	end

	return decodeValue(decoded.root)
end

-- Writes ServerStorage.MapData (+ Refs) for a freshly generated map.
function MapSerializer.store(serverStorage: Instance, data: { [any]: any }, version: string): ModuleScript
	local json, refs = MapSerializer.encode(data)
	local old = serverStorage:FindFirstChild("MapData")
	if old then
		old:Destroy()
	end
	local module = Instance.new("ModuleScript")
	module.Name = "MapData"
	assert(not string.find(json, "]==]", 1, true), "map data contains the long-string terminator")
	module.Source = table.concat({
		"-- Generated by tools/build_place.luau: the gameplay descriptors for Workspace.Map.",
		"-- The server reads this instead of regenerating the city, so edits made in Studio stay.",
		"-- To start over from the generator, delete Workspace.Map (this module is then ignored).",
		"return [==[" .. json .. "]==]",
	}, "\n")
	module:SetAttribute("MapVersion", version)
	local folder = Instance.new("Folder")
	folder.Name = "Refs"
	for i, instance in refs do
		local ref = Instance.new("ObjectValue")
		ref.Name = tostring(i)
		ref.Value = instance
		ref.Parent = folder
	end
	folder.Parent = module
	module.Parent = serverStorage
	return module
end

return MapSerializer
