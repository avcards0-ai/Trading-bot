--[[
	DailyRewardService
	7-day streak calendar. Claim every 20h; miss 48h and you start over at day 1.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local DailyRewards = require(Shared.Config.DailyRewards)
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local Tables = require(Shared.Util.Tables)

local RequestRouter = require(script.Parent.Parent.RequestRouter)

local DailyRewardService = { Name = "DailyRewardService" }

local S: { [string]: any }

function DailyRewardService:Init(services)
	S = services
end

function DailyRewardService:Claim(player: Player): (boolean, string?, any?)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Still loading..."
	end
	local state = data.DailyReward
	local now = os.time()
	local since = now - (state.LastClaim or 0)
	if state.LastClaim > 0 and since < GameConfig.DailyRewards.ClaimCooldown then
		return false, "Come back in " .. Format.duration(GameConfig.DailyRewards.ClaimCooldown - since)
	end
	local continuing = state.LastClaim > 0 and since <= GameConfig.DailyRewards.StreakBreak
	local day = continuing and (state.Streak % #DailyRewards.Days + 1) or 1
	state.Consecutive = continuing and (state.Consecutive or 0) + 1 or 1
	state.Streak = day
	state.LastClaim = now
	S.DataService:MarkChanged(player, "DailyReward")
	S.DataService:SetMax(player, "DailyStreakBest", state.Consecutive)

	local reward = DailyRewards.Days[day]
	local parts = {}
	if reward.Cash then
		local cash = S.EconomyService:AddCash(player, reward.Cash * DailyRewards.cashScale(data.Level), true)
		table.insert(parts, "+" .. Format.cash(cash))
	end
	local gems = reward.Gems or 0
	local session = S.DataService:Session(player)
	if session and session.IsVIP then
		gems += 10
	end
	if gems > 0 then
		S.EconomyService:AddGems(player, gems)
		table.insert(parts, "+" .. gems .. " 💎")
	end
	if reward.ArtifactRarity then
		local def = Tables.pickRandom(Artifacts.ByRarity[reward.ArtifactRarity] or {})
		if def then
			local uid = S.DataService:GenerateUid()
			S.InventoryService:AddToVault(player, { Uid = uid, Id = def.Id, Z = "Daily" })
			table.insert(parts, Format.rich(def.Name, Rarities.get(def.Rarity).Color) .. " in your vault")
		end
	end
	return true, string.format("Day %d reward! %s", day, table.concat(parts, "  ")), { Day = day }
end

function DailyRewardService:Start()
	RequestRouter.register("ClaimDaily", { Rate = 0.5, Burst = 2 }, function(player)
		return self:Claim(player)
	end)
end

return DailyRewardService
