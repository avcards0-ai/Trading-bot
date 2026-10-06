--[[
	RequestRouter
	The single entry point for client -> server requests ("Request" RemoteFunction).

	Every action is registered with:
	  * a token-bucket rate limit (per player, per action)
	  * an argument validator (types + ranges) - anything that fails is dropped
	  * a handler that returns ok, msg?, data?

	Handlers run inside pcall so a bug can never hang a client's InvokeServer or leak
	an error message. Nothing the client sends is trusted beyond "which action, which
	ids" - all prices, ownership and outcomes are decided here on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

export type Handler = (player: Player, ...any) -> (boolean, string?, any?)
export type Validator = (...any) -> boolean

type Route = {
	Handler: Handler,
	Validate: Validator?,
	Rate: number, -- tokens per second
	Burst: number,
}

local RequestRouter = {}

local routes: { [string]: Route } = {}
local buckets: { [Player]: { [string]: { Tokens: number, Updated: number } } } = {}

-- Token bucket; returns true if the request may proceed.
local function consume(player: Player, action: string, rate: number, burst: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[action]
	if not bucket then
		bucket = { Tokens = burst, Updated = now }
		playerBuckets[action] = bucket
	end
	bucket.Tokens = math.min(burst, bucket.Tokens + (now - bucket.Updated) * rate)
	bucket.Updated = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end
RequestRouter.consume = consume

function RequestRouter.register(action: string, options: { Rate: number?, Burst: number?, Validate: Validator? }, handler: Handler)
	assert(routes[action] == nil, "Duplicate request route " .. action)
	routes[action] = {
		Handler = handler,
		Validate = options.Validate,
		Rate = options.Rate or 4,
		Burst = options.Burst or 8,
	}
end

-- Validator helpers ---------------------------------------------------------------------

local V = {}
RequestRouter.V = V

function V.str(maxLength: number?)
	return function(value: any): boolean
		return type(value) == "string" and #value > 0 and #value <= (maxLength or 64) and utf8.len(value) ~= nil
	end
end

function V.int(min: number, max: number)
	return function(value: any): boolean
		return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
	end
end

function V.bool()
	return function(value: any): boolean
		return type(value) == "boolean"
	end
end

function V.optional(inner: (any) -> boolean)
	return function(value: any): boolean
		return value == nil or inner(value)
	end
end

function V.array(inner: (any) -> boolean, maxLength: number)
	return function(value: any): boolean
		if type(value) ~= "table" then
			return false
		end
		local count = 0
		for key, item in value do
			count += 1
			if type(key) ~= "number" or count > maxLength or not inner(item) then
				return false
			end
		end
		return count == #value
	end
end

-- Builds a validator for positional arguments.
function V.args(...: (any) -> boolean): Validator
	local checks = { ... }
	return function(...: any): boolean
		local values = table.pack(...)
		if values.n > #checks then
			return false
		end
		for i, check in checks do
			if not check(values[i]) then
				return false
			end
		end
		return true
	end
end

-- Dispatch ------------------------------------------------------------------------------

function RequestRouter.start()
	local remote = Net.func("Request")
	remote.OnServerInvoke = function(player: Player, action: any, ...: any)
		if type(action) ~= "string" then
			return { ok = false, msg = "Bad request" }
		end
		local route = routes[action]
		if not route then
			return { ok = false, msg = "Unknown action" }
		end
		if not consume(player, action, route.Rate, route.Burst) then
			return { ok = false, msg = "Slow down!" }
		end
		if route.Validate and not route.Validate(...) then
			return { ok = false, msg = "Invalid request" }
		end
		local args = table.pack(...)
		local success, ok, msg, data = pcall(route.Handler, player, table.unpack(args, 1, args.n))
		if not success then
			warn(string.format("[Request] %s failed for %s: %s", action, player.Name, tostring(ok)))
			return { ok = false, msg = "Something went wrong" }
		end
		return { ok = ok == true, msg = msg, data = data }
	end

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return RequestRouter
