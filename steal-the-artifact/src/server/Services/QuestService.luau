--[[
	QuestService
	3 personal Missions (re-roll on claim) + 3 Daily Challenges shared by everyone on the
	same UTC day (seeded by the date, so friends can grind the same goals together) and a
	bonus for clearing all three. Progress comes from the GameEvents bus.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Quests = require(Shared.Config.Quests)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)

local GameEvents = require(script.Parent.Parent.GameEvents)
local RequestRouter = require(script.Parent.Parent.RequestRouter)
local V = RequestRouter.V

local QuestService = { Name = "QuestService" }

local S: { [string]: any }
local rng = Random.new()

function QuestService:Init(services)
	S = services
end

local function eligibleMissions(level: number, exclude: { [string]: boolean }): { any }
	local list = {}
	for _, def in Quests.Missions do
		if (def.LevelReq or 0) <= level and not exclude[def.Id] then
			table.insert(list, def)
		end
	end
	return list
end

local function newMission(data: any): any?
	local exclude = {}
	for _, quest in data.Quests.Missions do
		exclude[quest.Id] = true
	end
	local pool = eligibleMissions(data.Level, exclude)
	if #pool == 0 then
		pool = eligibleMissions(data.Level, {})
	end
	local def = pool[rng:NextInteger(1, #pool)]
	if not def then
		return nil
	end
	return { Id = def.Id, Goal = Quests.goalFor(def, data.Level, rng:NextNumber()), Progress = 0, Claimed = false }
end

local function ensureMissions(data: any)
	local missions = data.Quests.Missions
	for i = #missions, 1, -1 do
		if not Quests.MissionById[missions[i].Id] then
			table.remove(missions, i)
		end
	end
	while #missions < Quests.ActiveMissions do
		local quest = newMission(data)
		if not quest then
			break
		end
		table.insert(missions, quest)
	end
end

local function ensureDaily(data: any): boolean
	local today = Quests.dayNumber()
	local daily = data.Quests.Daily
	if daily.Day == today and #daily.List == Quests.DailyCount then
		return false
	end
	local seeded = Random.new(today * 7919)
	local pool = table.clone(Quests.Daily)
	local list = {}
	for _ = 1, Quests.DailyCount do
		if #pool == 0 then
			break
		end
		local def = table.remove(pool, seeded:NextInteger(1, #pool))
		table.insert(list, { Id = def.Id, Goal = Quests.goalFor(def, data.Level, seeded:NextNumber()), Progress = 0, Claimed = false })
	end
	data.Quests.Daily = { Day = today, List = list, BonusClaimed = false }
	return true
end

local function matches(def: any, event: string, context: { Rarity: string?, Zone: string? }?): boolean
	if def.Event ~= event then
		return false
	end
	if def.MinRarity and not (context and context.Rarity and Rarities.atLeast(context.Rarity, def.MinRarity)) then
		return false
	end
	if def.Zone and not (context and context.Zone == def.Zone) then
		return false
	end
	return true
end

function QuestService:Progress(player: Player, event: string, amount: number, context: { Rarity: string?, Zone: string? }?)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local changed = false
	local function bump(quest: any, def: any, label: string)
		if quest.Claimed or quest.Progress >= quest.Goal or not def or not matches(def, event, context) then
			return
		end
		quest.Progress = math.min(quest.Goal, quest.Progress + amount)
		changed = true
		if quest.Progress >= quest.Goal then
			S.AnnouncementService:Notify(player, "reward", label .. " complete! Claim your reward in Quests 📜")
		end
	end
	for _, quest in data.Quests.Missions do
		bump(quest, Quests.MissionById[quest.Id], "Mission")
	end
	for _, quest in data.Quests.Daily.List do
		bump(quest, Quests.DailyById[quest.Id], "Daily challenge")
	end
	if changed then
		S.DataService:MarkChanged(player, "Quests")
	end
end

local function grant(player: Player, reward: any, level: number): string
	local scale = Quests.rewardScale(level)
	local parts = {}
	if reward.Cash then
		local cash = S.EconomyService:AddCash(player, reward.Cash * scale, true)
		table.insert(parts, "+" .. Format.cash(cash))
	end
	if reward.XP then
		S.EconomyService:AddXP(player, reward.XP * scale)
		table.insert(parts, "+" .. math.floor(reward.XP * scale) .. " XP")
	end
	if reward.Gems then
		S.EconomyService:AddGems(player, reward.Gems)
		table.insert(parts, "+" .. reward.Gems .. " 💎")
	end
	return table.concat(parts, "  ")
end

function QuestService:Start()
	S.DataService.Loaded:Connect(function(player, data)
		ensureMissions(data)
		ensureDaily(data)
		S.DataService:MarkChanged(player, "Quests")
	end)

	GameEvents.ArtifactStolen:Connect(function(player, info)
		local context = { Rarity = info.Rarity, Zone = info.Zone }
		self:Progress(player, "Steal", 1, context)
		if info.Source == "Vault" then
			self:Progress(player, "RaidSteal", 1, context)
		end
		if S.EventService:ActiveEventId() then
			self:Progress(player, "EventSteal", 1, context)
		end
	end)
	GameEvents.ArtifactSecured:Connect(function(player, info)
		local context = { Rarity = info.Rarity, Zone = info.Zone }
		self:Progress(player, "Secure", 1, context)
		self:Progress(player, "SecureValue", info.Value, context)
		if info.Alarm then
			self:Progress(player, "AlarmEscape", 1, context)
		end
	end)
	GameEvents.ArtifactSold:Connect(function(player, count)
		self:Progress(player, "Sell", count)
	end)
	GameEvents.Bonked:Connect(function(attacker, _victim, info)
		self:Progress(attacker, "Bonk", 1)
		if info.Carrier then
			self:Progress(attacker, "BonkCarrier", 1)
		end
		if info.Defend then
			self:Progress(attacker, "Defend", 1)
		end
	end)
	GameEvents.Failed:Connect(function(player, kind)
		if kind == "Zap" or kind == "Slip" or kind == "Tackle" or kind == "Spring" or kind == "Spike" then
			self:Progress(player, "Fail", 1)
		end
	end)
	GameEvents.CashEarned:Connect(function(player, amount)
		self:Progress(player, "EarnCash", amount)
	end)

	RequestRouter.register("ClaimQuest", { Rate = 4, Burst = 6, Validate = V.args(V.str(10), V.int(1, 5)) }, function(player, kind, index)
		local data = S.DataService:Get(player)
		if not data then
			return false
		end
		local list = kind == "Mission" and data.Quests.Missions or kind == "Daily" and data.Quests.Daily.List or nil
		local quest = list and list[index]
		if not quest then
			return false, "Quest not found"
		end
		if quest.Claimed or quest.Progress < quest.Goal then
			return false, "Not finished yet!"
		end
		local def = kind == "Mission" and Quests.MissionById[quest.Id] or Quests.DailyById[quest.Id]
		if not def then
			return false
		end
		local summary = grant(player, def.Reward, data.Level)
		if kind == "Mission" then
			local replacement = newMission(data)
			if replacement then
				list[index] = replacement
			else
				quest.Claimed = true
			end
		else
			quest.Claimed = true
		end
		S.DataService:MarkChanged(player, "Quests")
		return true, "Reward claimed! " .. summary
	end)

	RequestRouter.register("ClaimDailyBonus", { Rate = 1, Burst = 2 }, function(player)
		local data = S.DataService:Get(player)
		if not data then
			return false
		end
		local daily = data.Quests.Daily
		if daily.BonusClaimed then
			return false, "Already claimed today"
		end
		for _, quest in daily.List do
			if not quest.Claimed then
				return false, "Claim all three daily challenges first"
			end
		end
		daily.BonusClaimed = true
		local summary = grant(player, Quests.DailyBonus, data.Level)
		S.DataService:MarkChanged(player, "Quests")
		return true, "Daily bonus! " .. summary
	end)

	RequestRouter.register("RerollMission", { Rate = 2, Burst = 3, Validate = V.args(V.int(1, 5)) }, function(player, index)
		local data = S.DataService:Get(player)
		local quest = data and data.Quests.Missions[index]
		if not quest then
			return false
		end
		local cost = math.floor(Quests.RerollCost * Quests.rewardScale(data.Level))
		if not S.EconomyService:SpendCash(player, cost) then
			return false, "Need " .. Format.cash(cost) .. " to re-roll"
		end
		local replacement = newMission(data)
		if replacement then
			data.Quests.Missions[index] = replacement
		end
		S.DataService:MarkChanged(player, "Quests")
		return true, "New mission!"
	end)

	-- UTC day rollover for players who stay online past midnight
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				local data = S.DataService:Get(player)
				if data and ensureDaily(data) then
					S.DataService:MarkChanged(player, "Quests")
					S.AnnouncementService:Notify(player, "info", "New daily challenges are here! 📜")
				end
			end
		end
	end)
end

return QuestService
