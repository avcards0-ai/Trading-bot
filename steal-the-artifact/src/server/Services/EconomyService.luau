--[[
	EconomyService
	Cash, Gems, XP/levels, gear + vault + security + perk purchases, and rebirth.
	All prices come from shared config via Progression; the client only names what it
	wants to buy.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Upgrades = require(Shared.Config.Upgrades)
local Security = require(Shared.Config.Security)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local GameEvents = require(script.Parent.Parent.GameEvents)
local RequestRouter = require(script.Parent.Parent.RequestRouter)
local V = RequestRouter.V

local EconomyService = { Name = "EconomyService" }

local S: { [string]: any }

function EconomyService:Init(services)
	S = services
end

-- Cash ---------------------------------------------------------------------------------

-- Adds cash (optionally applying rebirth/perk multipliers). Returns the amount added.
function EconomyService:AddCash(player: Player, amount: number, applyMultiplier: boolean?): number
	local data = S.DataService:Get(player)
	if not data or amount ~= amount or amount <= 0 then
		return 0
	end
	if applyMultiplier then
		amount *= Progression.cashMultiplier(data)
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return 0
	end
	data.Cash += amount
	S.DataService:MarkChanged(player, "Cash")
	S.DataService:Increment(player, "TotalEarned", amount)
	S.PlayerService:UpdateLeaderstats(player)
	GameEvents.CashEarned:Fire(player, amount)
	return amount
end

function EconomyService:SpendCash(player: Player, amount: number): boolean
	local data = S.DataService:Get(player)
	if not data or amount < 0 or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	S.DataService:MarkChanged(player, "Cash")
	S.PlayerService:UpdateLeaderstats(player)
	return true
end

function EconomyService:AddGems(player: Player, amount: number)
	local data = S.DataService:Get(player)
	if not data or amount <= 0 then
		return
	end
	data.Gems += math.floor(amount)
	S.DataService:MarkChanged(player, "Gems")
end

function EconomyService:SpendGems(player: Player, amount: number): boolean
	local data = S.DataService:Get(player)
	if not data or amount < 0 or data.Gems < amount then
		return false
	end
	data.Gems -= amount
	S.DataService:MarkChanged(player, "Gems")
	return true
end

-- XP / levels ----------------------------------------------------------------------------

function EconomyService:AddXP(player: Player, amount: number)
	local data = S.DataService:Get(player)
	if not data or amount <= 0 then
		return
	end
	data.XP += math.floor(amount * Progression.xpMultiplier(data))
	local levelsGained = 0
	local cashReward, gemReward = 0, 0
	while data.XP >= Progression.xpToNext(data.Level) do
		data.XP -= Progression.xpToNext(data.Level)
		data.Level += 1
		levelsGained += 1
		cashReward += 40 * data.Level
		if data.Level % 5 == 0 then
			gemReward += 5
		end
	end
	S.DataService:MarkChanged(player, "XP")
	if levelsGained > 0 then
		S.DataService:MarkChanged(player, "Level")
		if cashReward > 0 then
			self:AddCash(player, cashReward, true)
		end
		if gemReward > 0 then
			self:AddGems(player, gemReward)
		end
		Net.event("LevelUp"):FireClient(player, data.Level, { Cash = cashReward, Gems = gemReward })
		S.AnnouncementService:Effect("LevelUp", { UserId = player.UserId }, nil)
		if data.Level % 10 == 0 then
			S.AnnouncementService:Feed(
				"🎉",
				string.format("<b>%s</b> reached <b>level %d</b>!", S.AnnouncementService.name(player), data.Level)
			)
		end
		S.PlayerService:RefreshNameTag(player)
		GameEvents.LevelUp:Fire(player, data.Level)
	end
end

-- Purchases ------------------------------------------------------------------------------

local function buyTrack(player: Player, bucket: string, track: any): (boolean, string?)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Still loading..."
	end
	local current = data[bucket][track.Id] or 0
	if current >= track.MaxLevel then
		return false, "Already maxed!"
	end
	local cost = Progression.trackCost(track, current)
	if not EconomyService:SpendCash(player, cost) then
		return false, "Not enough cash"
	end
	data[bucket][track.Id] = current + 1
	S.DataService:MarkChanged(player, bucket)
	return true, string.format("%s upgraded to level %d!", track.Name, current + 1)
end

function EconomyService:Rebirth(player: Player): (boolean, string?)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Still loading..."
	end
	local can, reason = Progression.canRebirth(data)
	if not can then
		return false, reason
	end
	if #S.DataService:Session(player).Carried > 0 then
		return false, "Secure your loot before rebirthing!"
	end
	local tokens = Progression.rebirthTokens(data.Rebirths)
	local headStart = Progression.level(data, "Perks", "HeadStart")
	data.Cash = 0
	data.Level = 1
	data.XP = 0
	data.Rebirths += 1
	data.PrestigeTokens += tokens
	for _, track in Upgrades.Gear do
		data.Gear[track.Id] = math.min(headStart, track.MaxLevel)
	end
	for _, key in { "Cash", "Level", "XP", "Rebirths", "PrestigeTokens", "Gear" } do
		S.DataService:MarkChanged(player, key)
	end
	S.PlayerService:UpdateLeaderstats(player)
	S.PlayerService:RefreshNameTag(player)
	S.CarryService:RefreshSpeed(player)
	local rank = Upgrades.rank(data.Rebirths)
	S.AnnouncementService:Feed(
		"🔄",
		string.format(
			"<b>%s</b> rebirthed! Now a <b>%s</b> (Rebirth #%d)",
			S.AnnouncementService.name(player),
			rank.Name,
			data.Rebirths
		),
		rank.Color
	)
	S.AnnouncementService:Effect("Rebirth", { UserId = player.UserId }, nil)
	GameEvents.Rebirthed:Fire(player)
	return true,
		string.format(
			"Reborn! +%d Prestige Token%s and +%d%% cash forever!",
			tokens,
			tokens == 1 and "" or "s",
			math.floor(Progression.cashMultiplier(data) * 100 - 100)
		)
end

function EconomyService:Start()
	RequestRouter.register("BuyGear", { Rate = 4, Burst = 6, Validate = V.args(V.str(24)) }, function(player, trackId)
		local track = Upgrades.GearById[trackId]
		if not track then
			return false, "Unknown upgrade"
		end
		local ok, msg = buyTrack(player, "Gear", track)
		if ok then
			S.CarryService:RefreshSpeed(player)
		end
		return ok, msg
	end)

	RequestRouter.register("BuyVault", { Rate = 4, Burst = 6, Validate = V.args(V.str(24)) }, function(player, trackId)
		local track = Upgrades.VaultById[trackId]
		if not track then
			return false, "Unknown upgrade"
		end
		local ok, msg = buyTrack(player, "Vault", track)
		if ok then
			S.InventoryService:AutoDisplay(player)
			S.PlotService:RefreshDisplay(player)
		end
		return ok, msg
	end)

	RequestRouter.register(
		"BuySecurity",
		{ Rate = 3, Burst = 5, Validate = V.args(V.str(24)) },
		function(player, trackId)
			local track = Security.ById[trackId]
			if not track then
				return false, "Unknown upgrade"
			end
			local ok, msg = buyTrack(player, "Security", track)
			if ok then
				S.SecurityService:InstallPlot(player)
				S.GuardService:RefreshPlot(player)
				S.PlotService:RefreshSign(player)
			end
			return ok, msg
		end
	)

	RequestRouter.register("BuyPerk", { Rate = 3, Burst = 5, Validate = V.args(V.str(24)) }, function(player, perkId)
		local perk = Upgrades.PerkById[perkId]
		local data = S.DataService:Get(player)
		if not perk or not data then
			return false, "Unknown perk"
		end
		local current = data.Perks[perk.Id] or 0
		if current >= perk.MaxLevel then
			return false, "Already maxed!"
		end
		local cost = Progression.perkCost(current)
		if data.PrestigeTokens < cost then
			return false, "Not enough Prestige Tokens"
		end
		data.PrestigeTokens -= cost
		data.Perks[perk.Id] = current + 1
		S.DataService:MarkChanged(player, "PrestigeTokens")
		S.DataService:MarkChanged(player, "Perks")
		S.CarryService:RefreshSpeed(player)
		if perk.Id == "ShowRoom" then
			S.InventoryService:AutoDisplay(player)
			S.PlotService:RefreshDisplay(player)
		end
		return true, string.format("%s is now level %d!", perk.Name, current + 1)
	end)

	RequestRouter.register("Rebirth", { Rate = 0.5, Burst = 1 }, function(player)
		return self:Rebirth(player)
	end)
end

EconomyService.format = Format.cash

return EconomyService
