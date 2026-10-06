--[[
	DataService
	Session-locked player data on DataStoreService.

	  * Loads with UpdateAsync and stamps a session lock (JobId + time). If another server
	    still holds the lock we retry, then take it over. Every save re-checks the lock and
	    refuses to write if another server has taken over, so two servers can never both
	    commit the same player (no item duplication through server hopping).
	  * Autosaves on an interval, saves + releases on leave, and flushes everyone on
	    BindToClose.
	  * In Studio without API access it falls back to an in-memory store so the game is
	    fully playable offline.
	  * Mirrors data to the owning client: one DataInit snapshot, then batched
	    DataChanged(scope, key, value) updates (flushed once per frame).
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Tables = require(Shared.Util.Tables)

local RequestRouter = require(script.Parent.Parent.RequestRouter)

local DataService = {
	Name = "DataService",
	Loaded = Signal.new(), -- (player, data)
	Removing = Signal.new(), -- (player, data) fired before the final save
	StatChanged = Signal.new(), -- (player, statKey, value)
	Changed = Signal.new(), -- (player, key)
	ShuttingDown = false,
}

local TEMPLATE = {
	Version = GameConfig.DataVersion,
	Cash = 0,
	Gems = 0,
	Level = 1,
	XP = 0,
	Rebirths = 0,
	PrestigeTokens = 0,
	Gear = { Backpack = 0, Sneakers = 0, Gloves = 0 },
	Vault = { Display = 0, Storage = 0 },
	Security = { Door = 0, Lasers = 0, Cameras = 0, Traps = 0, Guards = 0, Alarm = 0 },
	Perks = {},
	Artifacts = {},
	Displayed = {},
	Discovered = {},
	Stats = {
		Steals = 0,
		Secured = 0,
		Raids = 0,
		TimesRaided = 0,
		Defends = 0,
		Bonks = 0,
		BonkedCarriers = 0,
		Zapped = 0,
		Slipped = 0,
		Sprung = 0,
		Tackled = 0,
		Glued = 0,
		Spiked = 0,
		Drops = 0,
		Sold = 0,
		TotalEarned = 0,
		LegendarySecured = 0,
		MythicSecured = 0,
		SecretSecured = 0,
		ShinySecured = 0,
		RainbowSecured = 0,
		EventsJoined = 0,
		SecretRoomVisits = 0,
		DailyStreakBest = 0,
		MaxCarried = 0,
		HighestSecure = 0,
		Deaths = 0,
		PlayTime = 0,
	},
	Quests = { Missions = {}, Daily = { Day = 0, List = {}, BonusClaimed = false } },
	Achievements = {},
	CollectionClaims = {},
	DailyReward = { Streak = 0, Consecutive = 0, LastClaim = 0 },
	Codes = {},
	Cosmetics = {
		Owned = { skin_default = true, emote_wave = true, emote_point = true },
		Equipped = { Trail = "", Aura = "", VaultSkin = "skin_default", Title = "" },
		Emotes = { "emote_wave", "emote_point" },
		Loadouts = {},
	},
	Titles = {},
	Settings = {
		Music = 0.5,
		SFX = 0.8,
		VFX = "High",
		Shake = true,
		Feed = true,
		Global = true,
		ReduceFlashing = false,
	},
	Receipts = {},
	FirstJoin = 0,
	LastJoin = 0,
	Joins = 0,
}

-- Never sent to the client.
local PRIVATE_KEYS = { Receipts = true, Codes = true }

type Profile = {
	Player: Player,
	Key: string,
	Data: any,
	Session: { [string]: any },
	LastSave: number,
	Saving: boolean,
	Released: boolean,
}

local profiles: { [Player]: Profile } = {}
local pending: { [Player]: { [string]: boolean } } = {}

-- Store -------------------------------------------------------------------------------

local store: any = nil
local usingMock = false

local MockStore = {}
MockStore.__index = MockStore
function MockStore.new()
	return setmetatable({ _data = {} }, MockStore)
end
function MockStore:GetAsync(key: string)
	return Tables.deepCopy(self._data[key])
end
function MockStore:UpdateAsync(key: string, transform: (any) -> any)
	local result = transform(Tables.deepCopy(self._data[key]))
	if result ~= nil then
		self._data[key] = Tables.deepCopy(result)
	end
	return result
end

local function initStore()
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(GameConfig.DataStoreName)
		store:GetAsync("__probe")
	end)
	if not ok then
		if RunService:IsStudio() then
			warn(
				"[Data] DataStore unavailable in Studio ("
					.. tostring(err)
					.. "). Using an in-memory store - progress won't persist. Enable 'Studio Access to API Services' to test saving."
			)
			store = MockStore.new()
			usingMock = true
		else
			warn("[Data] DataStore probe failed, continuing with live store:", err)
			store = DataStoreService:GetDataStore(GameConfig.DataStoreName)
		end
	end
end

local function keyFor(userId: number): string
	return "player_" .. userId
end

-- Replication ---------------------------------------------------------------------------

local function sanitized(data: any): any
	local copy = {}
	for key, value in data do
		if not PRIVATE_KEYS[key] then
			copy[key] = value
		end
	end
	return copy
end

local function queue(player: Player, scope: string, key: string)
	local playerPending = pending[player]
	if not playerPending then
		playerPending = {}
		pending[player] = playerPending
	end
	playerPending[scope .. "|" .. key] = true
end

local function flush()
	local remote = Net.event("DataChanged")
	for player, keys in pending do
		local profile = profiles[player]
		if profile and player.Parent then
			for compound in keys do
				local scope, key = string.match(compound, "^(%a+)|(.+)$")
				if scope and key then
					local value = if scope == "Data" then profile.Data[key] else profile.Session[key]
					remote:FireClient(player, scope, key, value)
				end
			end
		end
	end
	table.clear(pending)
end

-- Load / save ---------------------------------------------------------------------------

local function newData(): any
	local data = Tables.deepCopy(TEMPLATE)
	data.FirstJoin = os.time()
	if RunService:IsStudio() and GameConfig.Debug.StudioStartingCash > 0 then
		data.Cash = GameConfig.Debug.StudioStartingCash
	end
	return data
end

local function loadAsync(player: Player): any?
	local key = keyFor(player.UserId)
	local retries = GameConfig.Data.LoadRetries
	for attempt = 1, retries do
		local lockedOut = false
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(stored)
				stored = stored or {}
				local lock = stored.Lock
				if
					lock
					and lock.JobId ~= game.JobId
					and os.time() - (lock.Time or 0) < GameConfig.Data.SessionLockExpiry
				then
					-- Another server still holds this player. Back off and retry; on the final
					-- attempt take over (that server's saves will then be rejected).
					if attempt < retries then
						lockedOut = true
						return nil
					end
				end
				stored.Lock = { JobId = game.JobId, Time = os.time() }
				stored.Data = stored.Data or newData()
				return stored
			end)
		end)
		if ok and result and not lockedOut then
			return result.Data
		end
		if not ok then
			warn(string.format("[Data] Load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
		end
		if not player.Parent then
			return nil
		end
		task.wait(lockedOut and 2.5 or (1.5 * attempt))
	end
	return nil
end

local function saveAsync(profile: Profile, release: boolean): boolean
	if profile.Saving and not release then
		return false
	end
	profile.Saving = true
	local ok, err = pcall(function()
		store:UpdateAsync(profile.Key, function(stored)
			stored = stored or {}
			local lock = stored.Lock
			if lock and lock.JobId ~= game.JobId then
				-- Another server took over this session: never overwrite its data.
				return nil
			end
			stored.Data = profile.Data
			stored.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
			stored.Meta = { Version = GameConfig.DataVersion, Updated = os.time() }
			return stored
		end)
	end)
	profile.Saving = false
	if ok then
		profile.LastSave = os.clock()
	else
		warn("[Data] Save failed for " .. profile.Player.Name .. ": " .. tostring(err))
	end
	return ok
end

-- Public API ------------------------------------------------------------------------------

function DataService:Get(player: Player): any?
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService:Session(player: Player): { [string]: any }?
	local profile = profiles[player]
	return profile and profile.Session
end

function DataService:IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService:WaitForData(player: Player, timeout: number?): any?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local data = self:Get(player)
		if data then
			return data
		end
		task.wait(0.2)
	end
	return self:Get(player)
end

-- Call after mutating a top-level key to replicate it.
function DataService:MarkChanged(player: Player, key: string)
	if profiles[player] then
		queue(player, "Data", key)
		self.Changed:Fire(player, key)
	end
end

function DataService:Set(player: Player, key: string, value: any)
	local data = self:Get(player)
	if data then
		data[key] = value
		self:MarkChanged(player, key)
	end
end

function DataService:SetSession(player: Player, key: string, value: any)
	local profile = profiles[player]
	if profile then
		profile.Session[key] = value
		queue(player, "Session", key)
	end
end

function DataService:ReplicateSession(player: Player, key: string)
	if profiles[player] then
		queue(player, "Session", key)
	end
end

function DataService:Increment(player: Player, stat: string, amount: number?)
	local data = self:Get(player)
	if not data then
		return
	end
	local value = (data.Stats[stat] or 0) + (amount or 1)
	data.Stats[stat] = value
	self:MarkChanged(player, "Stats")
	self.StatChanged:Fire(player, stat, value)
end

function DataService:SetMax(player: Player, stat: string, value: number)
	local data = self:Get(player)
	if data and value > (data.Stats[stat] or 0) then
		data.Stats[stat] = value
		self:MarkChanged(player, "Stats")
		self.StatChanged:Fire(player, stat, value)
	end
end

-- Ask for a save soon (used after high-stakes changes like being raided).
function DataService:RequestSave(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	local wait = GameConfig.Data.MinSaveGap - (os.clock() - profile.LastSave)
	task.delay(math.max(0, wait), function()
		if profiles[player] == profile and not profile.Released then
			saveAsync(profile, false)
		end
	end)
end

-- Saves immediately (yields). Used before confirming Robux purchases.
function DataService:SaveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile or profile.Released then
		return false
	end
	while profile.Saving do
		task.wait(0.1)
	end
	return saveAsync(profile, false)
end

function DataService:GenerateUid(): string
	return string.sub(HttpService:GenerateGUID(false), 1, 18)
end

function DataService:IsMock(): boolean
	return usingMock
end

-- Lifecycle -------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local data = loadAsync(player)
	if not player.Parent then
		-- Left while loading: release the lock we just took.
		if data then
			saveAsync({
				Player = player,
				Key = keyFor(player.UserId),
				Data = data,
				Session = {},
				LastSave = 0,
				Saving = false,
				Released = false,
			}, true)
		end
		return
	end
	if not data then
		player:Kick("We couldn't load your save data. Please rejoin in a moment - your progress is safe!")
		return
	end

	Tables.reconcile(data, TEMPLATE)
	data.Version = GameConfig.DataVersion
	data.LastJoin = os.time()
	data.Joins = (data.Joins or 0) + 1

	local profile: Profile = {
		Player = player,
		Key = keyFor(player.UserId),
		Data = data,
		Session = {
			Carried = {},
			PlotIndex = 0,
			RecallReadyAt = 0, -- server time (for the UI cooldown)
			ShieldUntil = 0, -- os.clock (server only)
			ShieldEnds = 0, -- server time (for the UI)
			IsVIP = false,
			HasLocker = false,
			Income = 0,
			SecurePad = Vector3.zero,
		},
		LastSave = os.clock(),
		Saving = false,
		Released = false,
	}
	profiles[player] = profile

	Net.event("DataInit"):FireClient(player, { Data = sanitized(data), Session = profile.Session, Mock = usingMock })
	DataService.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	DataService.Removing:Fire(player, profile.Data)
	-- Give Removing handlers (drop carried loot, etc.) a frame to run.
	task.wait()
	profiles[player] = nil
	pending[player] = nil
	profile.Released = true
	saveAsync(profile, true)
end

function DataService:Init()
	initStore()
end

function DataService:Start()
	Players.PlayerAdded:Connect(function(player)
		onPlayerAdded(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	RunService.Heartbeat:Connect(flush)

	-- Snapshot fallback for clients that missed DataInit.
	RequestRouter.register("GetData", { Rate = 0.2, Burst = 2 }, function(player)
		local profile = profiles[player]
		if not profile then
			return false, "Still loading..."
		end
		return true, nil, { Data = sanitized(profile.Data), Session = profile.Session, Mock = usingMock }
	end)

	-- Autosave
	task.spawn(function()
		while true do
			task.wait(GameConfig.Data.AutosaveInterval)
			for player, profile in profiles do
				if player.Parent and not profile.Released then
					task.spawn(saveAsync, profile, false)
				end
			end
		end
	end)

	-- Play time
	task.spawn(function()
		while true do
			task.wait(60)
			for player in profiles do
				self:Increment(player, "PlayTime", 60)
			end
		end
	end)

	game:BindToClose(function()
		local remaining = 0
		for player, profile in profiles do
			remaining += 1
			task.spawn(function()
				DataService.ShuttingDown = true
				DataService.Removing:Fire(player, profile.Data)
				task.wait()
				-- Removing from the table first makes the later PlayerRemoving a no-op.
				profiles[player] = nil
				profile.Released = true
				saveAsync(profile, true)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
