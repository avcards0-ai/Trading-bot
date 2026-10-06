--[[
	LeaderboardService
	Global leaderboards (OrderedDataStore) for Richest, Best Vault, Most Steals and Rarest
	Collection, plus live server boards. Fills the physical boards in the Marketplace and
	serves the leaderboard UI. Writes are batched on an interval to respect DataStore limits.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local RequestRouter = require(script.Parent.Parent.RequestRouter)

local LeaderboardService = { Name = "LeaderboardService" }

local S: { [string]: any }

local BOARDS = {
	{ Key = "Richest", Store = "STA_Richest_v1", Title = "💰 Richest Thieves", Value = function(data)
		return Progression.netWorth(data)
	end, Format = Format.cash },
	{ Key = "BestVault", Store = "STA_BestVault_v1", Title = "🏦 Best Vaults", Value = function(data)
		return Progression.vaultScore(data)
	end, Format = Format.abbreviate },
	{ Key = "MostSteals", Store = "STA_MostSteals_v1", Title = "🖐️ Most Steals", Value = function(data)
		return data.Stats.Steals
	end, Format = Format.abbreviate },
	{ Key = "Collection", Store = "STA_Collection_v1", Title = "📖 Rarest Collections", Value = function(data)
		return Progression.collectionScore(data)
	end, Format = Format.abbreviate },
}

type Entry = { Rank: number, UserId: number, Name: string, Value: number, Text: string }

local stores: { [string]: OrderedDataStore } = {}
local globalCache: { [string]: { Entry } } = {}
local nameCache: { [number]: string } = {}
local globalAvailable = true

function LeaderboardService:Init(services)
	S = services
end

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local result = ok and name or ("Thief #" .. userId)
	nameCache[userId] = result
	return result
end

local function serverBoards(): { [string]: { Entry } }
	local result = {}
	for _, board in BOARDS do
		local list = {}
		for _, player in Players:GetPlayers() do
			local data = S.DataService:Get(player)
			if data then
				local value = math.floor(board.Value(data))
				table.insert(list, { Rank = 0, UserId = player.UserId, Name = player.DisplayName, Value = value, Text = board.Format(value) })
			end
		end
		table.sort(list, function(a, b)
			return a.Value > b.Value
		end)
		for i, entry in list do
			entry.Rank = i
		end
		result[board.Key] = list
	end
	return result
end

function LeaderboardService:Snapshot()
	return {
		Global = globalCache,
		Server = serverBoards(),
		GlobalAvailable = globalAvailable,
		Titles = (function()
			local titles = {}
			for _, board in BOARDS do
				titles[board.Key] = board.Title
			end
			return titles
		end)(),
	}
end

local function submit(player: Player)
	if not globalAvailable then
		return
	end
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	for _, board in BOARDS do
		local store = stores[board.Key]
		if store then
			local value = math.max(0, math.floor(board.Value(data)))
			local ok, err = pcall(store.SetAsync, store, tostring(player.UserId), value)
			if not ok then
				warn("[Leaderboards] Submit failed:", err)
			end
		end
	end
end

local function refreshGlobal()
	if not globalAvailable then
		return
	end
	for _, board in BOARDS do
		local store = stores[board.Key]
		if store then
			local ok, pages = pcall(store.GetSortedAsync, store, false, GameConfig.Leaderboards.TopCount)
			if ok and pages then
				local list = {}
				for rank, item in pages:GetCurrentPage() do
					local userId = tonumber(item.key) or 0
					local value = tonumber(item.value) or 0
					table.insert(list, { Rank = rank, UserId = userId, Name = nameFor(userId), Value = value, Text = board.Format(value) })
				end
				globalCache[board.Key] = list
			end
		end
	end
end

local function renderBoards()
	local boards = S.MapService:Get().Boards
	local server = serverBoards()
	for _, board in BOARDS do
		local part = boards[board.Key]
		if part then
			local gui = part:FindFirstChild("BoardGui") :: SurfaceGui?
			if not gui then
				local newGui = Instance.new("SurfaceGui")
				newGui.Name = "BoardGui"
				newGui.Face = Enum.NormalId.Front
				newGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				newGui.PixelsPerStud = 24
				newGui.LightInfluence = 0
				newGui.MaxDistance = 220
				local title = Instance.new("TextLabel")
				title.Name = "Title"
				title.BackgroundColor3 = Color3.fromRGB(40, 30, 70)
				title.Size = UDim2.fromScale(1, 0.12)
				title.Font = Enum.Font.LuckiestGuy
				title.TextScaled = true
				title.TextColor3 = Color3.fromRGB(255, 210, 80)
				title.Text = board.Title
				title.Parent = newGui
				local body = Instance.new("TextLabel")
				body.Name = "Body"
				body.BackgroundTransparency = 1
				body.Position = UDim2.fromScale(0.05, 0.14)
				body.Size = UDim2.fromScale(0.9, 0.84)
				body.Font = Enum.Font.FredokaOne
				body.TextScaled = true
				body.RichText = true
				body.TextXAlignment = Enum.TextXAlignment.Left
				body.TextYAlignment = Enum.TextYAlignment.Top
				body.TextColor3 = Color3.new(1, 1, 1)
				body.Parent = newGui
				newGui.Parent = part
				gui = newGui
			end
			local list = globalCache[board.Key]
			local label = "GLOBAL"
			if not list or #list == 0 then
				list = server[board.Key]
				label = "THIS SERVER"
			end
			local lines = { Format.rich(label, Color3.fromRGB(150, 150, 190)) }
			for i = 1, math.min(10, #list) do
				local entry = list[i]
				local medal = i == 1 and "🥇" or i == 2 and "🥈" or i == 3 and "🥉" or (i .. ".")
				table.insert(lines, string.format("%s %s  %s", medal, Format.escape(entry.Name), Format.rich(entry.Text, Color3.fromRGB(255, 220, 120))))
			end
			((gui :: SurfaceGui):FindFirstChild("Body") :: TextLabel).Text = table.concat(lines, "\n")
		end
	end
end

function LeaderboardService:Start()
	local ok = pcall(function()
		for _, board in BOARDS do
			stores[board.Key] = DataStoreService:GetOrderedDataStore(board.Store)
		end
	end)
	globalAvailable = ok and not S.DataService:IsMock()

	RequestRouter.register("GetLeaderboards", { Rate = 0.5, Burst = 2 }, function()
		return true, nil, self:Snapshot()
	end)

	S.DataService.Removing:Connect(function(player)
		task.spawn(submit, player)
	end)

	-- Submit periodically (staggered), refresh + broadcast periodically.
	task.spawn(function()
		while true do
			task.wait(GameConfig.Leaderboards.SubmitInterval)
			for _, player in Players:GetPlayers() do
				submit(player)
				task.wait(0.5)
			end
		end
	end)
	task.spawn(function()
		task.wait(5)
		while true do
			refreshGlobal()
			renderBoards()
			Net.event("Leaderboards"):FireAllClients(self:Snapshot())
			task.wait(GameConfig.Leaderboards.RefreshInterval)
		end
	end)
	-- Server boards change quickly; redraw the physical ones more often.
	task.spawn(function()
		while true do
			task.wait(20)
			renderBoards()
		end
	end)
end

return LeaderboardService
