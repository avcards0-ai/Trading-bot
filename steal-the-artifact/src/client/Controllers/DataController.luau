--[[
	DataController
	Read-only mirror of the player's server data + session state. UI observes keys and
	re-renders when they change. Nothing here is trusted by the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DataController = {
	Name = "DataController",
	Data = {} :: { [string]: any },
	Session = {} :: { [string]: any },
	Ready = false,
	ReadySignal = Signal.new(),
	Changed = Signal.new(), -- (scope, key, value)
	Mock = false,
}

local signals: { [string]: any } = {}

local function signalFor(scope: string, key: string)
	local id = scope .. "." .. key
	local signal = signals[id]
	if not signal then
		signal = Signal.new()
		signals[id] = signal
	end
	return signal
end

function DataController:Get(key: string): any
	return self.Data[key]
end

function DataController:GetSession(key: string): any
	return self.Session[key]
end

-- Calls fn(value) now (if loaded) and every time Data[key] changes.
function DataController:Observe(key: string, fn: (any) -> ())
	if self.Ready then
		task.spawn(fn, self.Data[key])
	end
	return signalFor("Data", key):Connect(fn)
end

function DataController:ObserveSession(key: string, fn: (any) -> ())
	if self.Ready then
		task.spawn(fn, self.Session[key])
	end
	return signalFor("Session", key):Connect(fn)
end

-- Fires fn() whenever any of `keys` (Data scope) change, and once when ready.
function DataController:ObserveMany(keys: { string }, fn: () -> ())
	local pending = false
	local function schedule()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			fn()
		end)
	end
	for _, key in keys do
		signalFor("Data", key):Connect(schedule)
	end
	if self.Ready then
		schedule()
	else
		self.ReadySignal:Once(schedule)
	end
end

-- Optimistic local update (e.g. settings sliders) - the server's DataChanged follows.
function DataController:Predict(key: string, value: any)
	self.Data[key] = value
	signalFor("Data", key):Fire(value)
	self.Changed:Fire("Data", key, value)
end

function DataController:WaitReady()
	if not self.Ready then
		self.ReadySignal:Wait()
	end
end

local function applySnapshot(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	DataController.Data = snapshot.Data or {}
	DataController.Session = snapshot.Session or {}
	DataController.Mock = snapshot.Mock == true
	local wasReady = DataController.Ready
	DataController.Ready = true
	for key, value in DataController.Data do
		signalFor("Data", key):Fire(value)
	end
	for key, value in DataController.Session do
		signalFor("Session", key):Fire(value)
	end
	if not wasReady then
		DataController.ReadySignal:Fire()
	end
end

function DataController:Start()
	Net.event("DataInit").OnClientEvent:Connect(applySnapshot)
	Net.event("DataChanged").OnClientEvent:Connect(function(scope: string, key: string, value: any)
		if scope == "Data" then
			self.Data[key] = value
		elseif scope == "Session" then
			self.Session[key] = value
		else
			return
		end
		signalFor(scope, key):Fire(value)
		self.Changed:Fire(scope, key, value)
	end)
	-- Fallback in case the snapshot was sent before we were listening.
	task.delay(8, function()
		if not self.Ready then
			local response = Net.request("GetData")
			if response.ok and not self.Ready then
				applySnapshot(response.data)
			end
		end
	end)
end

return DataController
