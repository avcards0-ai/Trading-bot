--[[
	Tables
	Small table helpers: deep copy, reconcile against a template, weighted picks.
]]

local Tables = {}

function Tables.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[Tables.deepCopy(k)] = Tables.deepCopy(v)
	end
	return copy :: any
end

-- Fills in any keys missing from `target` with copies from `template` (recursively for
-- dictionaries). Used to migrate old save data forward when new fields are added.
function Tables.reconcile(target: { [any]: any }, template: { [any]: any })
	for key, templateValue in template do
		local current = target[key]
		if current == nil then
			target[key] = Tables.deepCopy(templateValue)
		elseif type(current) == "table" and type(templateValue) == "table" and next(templateValue) ~= nil then
			-- Only recurse into dictionaries; array templates are defaults, not shapes.
			if templateValue[1] == nil then
				Tables.reconcile(current, templateValue)
			end
		end
	end
end

function Tables.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Tables.keys(t: { [any]: any }): { any }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	return keys
end

-- weights: { [key]: weight } -> picked key
function Tables.weightedPick<K>(weights: { [K]: number }, rng: Random?): K?
	local total = 0
	for _, weight in weights do
		total += math.max(weight, 0)
	end
	if total <= 0 then
		return nil
	end
	local roll = (rng and rng:NextNumber() or math.random()) * total
	local last: K? = nil
	for key, weight in weights do
		if weight > 0 then
			last = key
			roll -= weight
			if roll <= 0 then
				return key
			end
		end
	end
	return last
end

function Tables.shuffle<T>(list: { T }, rng: Random?): { T }
	for i = #list, 2, -1 do
		local j = rng and rng:NextInteger(1, i) or math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function Tables.pickRandom<T>(list: { T }, rng: Random?): T?
	if #list == 0 then
		return nil
	end
	return list[rng and rng:NextInteger(1, #list) or math.random(1, #list)]
end

return Tables
