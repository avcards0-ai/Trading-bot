--[[
	InventoryService
	Vault storage, the SECURE step, display pedestals, selling, the collection book and
	passive income from displayed artifacts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)

local GameEvents = require(script.Parent.Parent.GameEvents)
local RequestRouter = require(script.Parent.Parent.RequestRouter)
local V = RequestRouter.V

local InventoryService = { Name = "InventoryService" }

local S: { [string]: any }

local COLLECTION_REWARDS = { Common = 10, Uncommon = 15, Rare = 25, Epic = 40, Legendary = 75, Mythic = 150, Secret = 500 }
InventoryService.CollectionRewards = COLLECTION_REWARDS

function InventoryService:Init(services)
	S = services
end

local function countVault(data: any): number
	local n = 0
	for _ in data.Artifacts do
		n += 1
	end
	return n
end

local function isDisplayed(data: any, uid: string): number?
	return table.find(data.Displayed, uid)
end

function InventoryService:UpdateIncome(player: Player)
	local data = S.DataService:Get(player)
	if data then
		S.DataService:SetSession(player, "Income", Progression.incomePerSecond(data))
	end
end

-- Adds a record to vault storage. Returns "stored" or "sold" (vault full -> auto-sold).
function InventoryService:AddToVault(player: Player, record: { [string]: any }, silent: boolean?): string
	local data = S.DataService:Get(player)
	if not data then
		return "lost"
	end
	if countVault(data) >= Progression.storageSize(data) then
		local price = math.floor(Progression.artifactValue(record.Id, record.M) * GameConfig.Economy.OverflowSellPercent)
		S.EconomyService:AddCash(player, price, true)
		if not silent then
			S.AnnouncementService:Notify(player, "warning", "Vault storage full! Auto-sold for " .. Format.cash(price) .. ". Upgrade storage!")
		end
		return "sold"
	end
	data.Artifacts[record.Uid] = { Id = record.Id, M = record.M, T = os.time(), Z = record.Z }
	data.Discovered[record.Id] = (data.Discovered[record.Id] or 0) + 1
	S.DataService:MarkChanged(player, "Artifacts")
	S.DataService:MarkChanged(player, "Discovered")
	return "stored"
end

function InventoryService:RemoveFromVault(player: Player, uid: string): { [string]: any }?
	local data = S.DataService:Get(player)
	local record = data and data.Artifacts[uid]
	if not record then
		return nil
	end
	data.Artifacts[uid] = nil
	local index = isDisplayed(data, uid)
	if index then
		table.remove(data.Displayed, index)
		S.DataService:MarkChanged(player, "Displayed")
	end
	S.DataService:MarkChanged(player, "Artifacts")
	self:UpdateIncome(player)
	return record
end

-- Keeps the display list valid. If `candidates` are given (e.g. freshly secured loot),
-- free pedestals are filled with the most valuable of them. Artifacts a player moved to
-- storage on purpose are never pulled back out automatically.
function InventoryService:AutoDisplay(player: Player, candidates: { string }?)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local slots = Progression.displaySlots(data)
	for i = #data.Displayed, 1, -1 do
		if not data.Artifacts[data.Displayed[i]] then
			table.remove(data.Displayed, i)
		end
	end
	while #data.Displayed > slots do
		table.remove(data.Displayed)
	end
	if candidates and #data.Displayed < slots then
		local list = {}
		for _, uid in candidates do
			local record = data.Artifacts[uid]
			if record and not isDisplayed(data, uid) then
				table.insert(list, { Uid = uid, Value = Progression.artifactValue(record.Id, record.M) })
			end
		end
		table.sort(list, function(a, b)
			return a.Value > b.Value
		end)
		for _, candidate in list do
			if #data.Displayed >= slots then
				break
			end
			table.insert(data.Displayed, candidate.Uid)
		end
	end
	S.DataService:MarkChanged(player, "Displayed")
	self:UpdateIncome(player)
end

-- The SECURE step: everything you're carrying goes into your vault.
function InventoryService:SecureCarried(player: Player)
	local records = S.CarryService:TakeAll(player)
	if #records == 0 then
		return
	end
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local session = S.DataService:Session(player)
	local totalValue, totalCash, totalXP = 0, 0, 0
	local newDiscoveries = {}
	local stored = {}
	local best, bestValue = nil, -1
	local wasWanted = S.PlayerService:HasStatus(player, "Marked") or S.PlayerService:HasStatus(player, "Wanted")
	local eventMultiplier = S.EventService:SecureMultiplier()

	for _, record in records do
		local def = Artifacts.get(record.Id)
		if def then
			local rarity = Rarities.get(def.Rarity)
			local value = Progression.artifactValue(record.Id, record.M)
			local raided = record.Source == "Vault" and record.FromUserId ~= nil and record.FromUserId ~= player.UserId
			local firstTime = (data.Discovered[record.Id] or 0) == 0
			if self:AddToVault(player, record) == "stored" then
				table.insert(stored, record.Uid)
			end
			if firstTime then
				table.insert(newDiscoveries, def)
			end

			local bonus = GameConfig.Economy.SecureBonusPercent
			if raided then
				bonus += GameConfig.Raid.RaidBonusPercent
				local revenge = session.Revenge and session.Revenge[record.FromUserId]
				if revenge and revenge > os.clock() then
					bonus += GameConfig.Raid.RevengeBonusPercent
				end
				S.DataService:Increment(player, "Raids")
			end
			totalCash += value * bonus * eventMultiplier
			totalXP += rarity.XP * (raided and 1.5 or 1)
			totalValue += value

			S.DataService:Increment(player, "Secured")
			if def.Rarity == "Legendary" then
				S.DataService:Increment(player, "LegendarySecured")
			elseif def.Rarity == "Mythic" then
				S.DataService:Increment(player, "MythicSecured")
			elseif def.Rarity == "Secret" then
				S.DataService:Increment(player, "SecretSecured")
			end
			if record.M == "Shiny" then
				S.DataService:Increment(player, "ShinySecured")
			elseif record.M == "Rainbow" then
				S.DataService:Increment(player, "RainbowSecured")
			end
			S.DataService:SetMax(player, "HighestSecure", value)
			if value > bestValue then
				best, bestValue = def, value
			end
			GameEvents.ArtifactSecured:Fire(player, {
				Id = record.Id,
				Rarity = def.Rarity,
				Mutation = record.M,
				Zone = record.Z,
				Source = record.Source,
				Value = value,
				Alarm = wasWanted,
				Raided = raided,
			})
		end
	end

	local cash = S.EconomyService:AddCash(player, totalCash, true)
	S.EconomyService:AddXP(player, totalXP)
	self:AutoDisplay(player, stored)
	S.PlotService:RefreshDisplay(player)
	S.PlotService:RefreshSign(player)

	local plot = S.PlotService:GetPlot(player)
	S.AnnouncementService:Effect("Secure", {
		UserId = player.UserId,
		Position = plot and plot.SecurePad.Position or nil,
		Count = #records,
		Cash = cash,
		Best = best and best.Id or nil,
		Value = totalValue,
	}, plot and plot.SecurePad.Position or nil, 200)
	S.AnnouncementService:Notify(player, "success", string.format("SECURED %d artifact%s! +%s", #records, #records == 1 and "" or "s", Format.cash(cash)), { Big = true })
	for _, def in newDiscoveries do
		S.AnnouncementService:Notify(player, "reward", "📖 NEW! " .. def.Name .. " added to your Collection", { Rarity = def.Rarity })
	end
	if best and Rarities.index(best.Rarity) >= Rarities.index("Legendary") then
		S.AnnouncementService:Feed("🏦", string.format("<b>%s</b> secured %s in their vault!", S.AnnouncementService.name(player), Format.rich(best.Name, Rarities.get(best.Rarity).Color)))
	end
	S.DataService:RequestSave(player)
end

-- Selling ---------------------------------------------------------------------------------

local function sell(player: Player, uids: { string }): (number, number)
	local data = S.DataService:Get(player)
	if not data then
		return 0, 0
	end
	local total, count = 0, 0
	local eventMultiplier = S.EventService:SellMultiplier()
	for _, uid in uids do
		local record = data.Artifacts[uid]
		if record then
			local price = Progression.sellPrice(record.Id, record.M, data, eventMultiplier)
			InventoryService:RemoveFromVault(player, uid)
			total += price
			count += 1
		end
	end
	if count > 0 then
		-- sellPrice already includes the player's cash multiplier
		S.EconomyService:AddCash(player, total, false)
		S.DataService:Increment(player, "Sold", count)
		GameEvents.ArtifactSold:Fire(player, count, total)
		InventoryService:AutoDisplay(player)
		S.PlotService:RefreshDisplay(player)
		S.PlotService:RefreshSign(player)
	end
	return count, total
end

function InventoryService:Start()
	RequestRouter.register("Sell", { Rate = 3, Burst = 6, Validate = V.args(V.array(V.str(40), 60)) }, function(player, uids)
		local count, total = sell(player, uids)
		if count == 0 then
			return false, "Nothing to sell"
		end
		return true, string.format("Sold %d artifact%s for %s!", count, count == 1 and "" or "s", Format.cash(total)), { Cash = total }
	end)

	RequestRouter.register("SellBulk", { Rate = 1, Burst = 2, Validate = V.args(V.str(16)) }, function(player, maxRarity)
		local data = S.DataService:Get(player)
		local cap = Rarities.ById[maxRarity]
		if not data or not cap or cap.Index > Rarities.index("Epic") then
			return false, "You can only bulk-sell up to Epic"
		end
		local uids = {}
		for uid, record in data.Artifacts do
			local def = Artifacts.get(record.Id)
			if def and Rarities.index(def.Rarity) <= cap.Index and not isDisplayed(data, uid) then
				table.insert(uids, uid)
			end
		end
		local count, total = sell(player, uids)
		if count == 0 then
			return false, "Nothing to sell"
		end
		return true, string.format("Sold %d artifacts for %s!", count, Format.cash(total)), { Cash = total }
	end)

	RequestRouter.register("SetDisplay", { Rate = 6, Burst = 10, Validate = V.args(V.str(40), V.bool()) }, function(player, uid, shown)
		local data = S.DataService:Get(player)
		if not data or not data.Artifacts[uid] then
			return false, "You don't own that"
		end
		local index = isDisplayed(data, uid)
		if shown then
			if index then
				return true
			end
			if #data.Displayed >= Progression.displaySlots(data) then
				return false, "No free pedestals - remove one or upgrade Display Pedestals"
			end
			table.insert(data.Displayed, uid)
		else
			if not index then
				return true
			end
			table.remove(data.Displayed, index)
		end
		S.DataService:MarkChanged(player, "Displayed")
		self:UpdateIncome(player)
		S.PlotService:RefreshDisplay(player)
		S.PlotService:RefreshSign(player)
		return true, shown and "Now on display!" or "Moved to storage (raid-proof)"
	end)

	RequestRouter.register("ClaimCollection", { Rate = 2, Burst = 4, Validate = V.args(V.str(16)) }, function(player, rarityId)
		local data = S.DataService:Get(player)
		local reward = COLLECTION_REWARDS[rarityId]
		if not data or not reward then
			return false, "Unknown set"
		end
		if data.CollectionClaims[rarityId] then
			return false, "Already claimed"
		end
		for _, def in Artifacts.ByRarity[rarityId] or {} do
			if not data.Discovered[def.Id] then
				return false, "Discover every " .. rarityId .. " artifact first"
			end
		end
		data.CollectionClaims[rarityId] = true
		S.DataService:MarkChanged(player, "CollectionClaims")
		S.EconomyService:AddGems(player, reward)
		return true, string.format("%s set complete! +%d Gems", rarityId, reward)
	end)

	S.DataService.Loaded:Connect(function(player)
		self:AutoDisplay(player)
	end)

	-- Passive income from displayed artifacts
	task.spawn(function()
		local tick = GameConfig.Economy.IncomeTick
		while true do
			task.wait(tick)
			for _, player in Players:GetPlayers() do
				local data = S.DataService:Get(player)
				if data and S.PlotService:GetPlot(player) then
					local income = Progression.incomePerSecond(data) * tick
					if income >= 1 then
						S.EconomyService:AddCash(player, income, false)
					end
				end
			end
		end
	end)
end

return InventoryService
