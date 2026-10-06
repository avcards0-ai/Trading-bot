--[[
	Progression
	Pure formulas shared by the server (authoritative) and the client (UI previews), so the
	numbers a player sees are always the numbers the server uses.
]]

local Config = script.Parent.Config
local GameConfig = require(Config.GameConfig)
local Upgrades = require(Config.Upgrades)
local Artifacts = require(Config.Artifacts)
local Rarities = require(Config.Rarities)
local Security = require(Config.Security)

local Progression = {}

export type ArtifactRecord = {
	Id: string, -- catalog id
	M: string?, -- mutation ("Shiny" / "Rainbow")
	T: number?, -- time acquired
	Z: string?, -- zone it came from
}

-- XP -----------------------------------------------------------------------------------

function Progression.xpToNext(level: number): number
	return math.floor(25 * level ^ 1.35 + 40)
end

-- Upgrade tracks -----------------------------------------------------------------------

function Progression.trackCost(track: { BaseCost: number, Growth: number }, currentLevel: number): number
	return math.floor(track.BaseCost * track.Growth ^ currentLevel)
end

function Progression.perkCost(currentLevel: number): number
	return currentLevel + 1
end

local function level(data: any, group: string, id: string): number
	local bucket = data and data[group]
	return bucket and bucket[id] or 0
end
Progression.level = level

-- Derived stats ------------------------------------------------------------------------

function Progression.capacity(data: any): number
	return GameConfig.Carry.BaseCapacity + level(data, "Gear", "Backpack") + level(data, "Perks", "DeepPockets")
end

function Progression.walkSpeed(data: any): number
	return GameConfig.Character.BaseWalkSpeed + level(data, "Gear", "Sneakers")
end

-- Multiplier applied to every steal hold duration (lower = faster).
function Progression.holdMultiplier(data: any): number
	local gloves = level(data, "Gear", "Gloves") * Upgrades.GearById.Gloves.PerLevel
	local quick = level(data, "Perks", "QuickHands") * Upgrades.PerkById.QuickHands.PerLevel
	return math.max(0.3, (1 - gloves) * (1 - quick))
end

function Progression.cashMultiplier(data: any): number
	local rebirths = data and data.Rebirths or 0
	return (1 + rebirths * GameConfig.Economy.RebirthCashBonusPerRebirth)
		* (1 + level(data, "Perks", "GoldenTouch") * Upgrades.PerkById.GoldenTouch.PerLevel)
end

function Progression.xpMultiplier(data: any): number
	local rebirths = data and data.Rebirths or 0
	return (1 + rebirths * GameConfig.Economy.RebirthXPBonusPerRebirth)
		* (1 + level(data, "Perks", "FastLearner") * Upgrades.PerkById.FastLearner.PerLevel)
end

function Progression.sellMultiplier(data: any): number
	return 1 + level(data, "Perks", "FenceFriend") * Upgrades.PerkById.FenceFriend.PerLevel
end

function Progression.crackMultiplier(data: any): number
	return math.max(0.4, 1 - level(data, "Perks", "SafeCracker") * Upgrades.PerkById.SafeCracker.PerLevel)
end

function Progression.stunMultiplier(data: any): number
	return math.max(0.4, 1 - level(data, "Perks", "ThickSkin") * Upgrades.PerkById.ThickSkin.PerLevel)
end

function Progression.displaySlots(data: any): number
	return Upgrades.BaseDisplay
		+ level(data, "Vault", "Display") * Upgrades.VaultById.Display.PerLevel
		+ level(data, "Perks", "ShowRoom") * Upgrades.PerkById.ShowRoom.PerLevel
end

function Progression.storageSize(data: any): number
	return Upgrades.BaseStorage + level(data, "Vault", "Storage") * Upgrades.VaultById.Storage.PerLevel
end

-- Steal hold time in seconds for a rarity in a zone for this player.
function Progression.holdTime(rarityId: string, zoneMultiplier: number, data: any): number
	local rarity = Rarities.get(rarityId)
	return math.max(0.25, rarity.HoldTime * zoneMultiplier * Progression.holdMultiplier(data))
end

-- Artifact values ----------------------------------------------------------------------

function Progression.mutationMultiplier(mutation: string?): number
	local def = mutation and GameConfig.Mutations[mutation]
	return def and def.ValueMultiplier or 1
end

function Progression.artifactValue(artifactId: string, mutation: string?): number
	local def = Artifacts.get(artifactId)
	if not def then
		return 0
	end
	return math.floor(def.Value * Progression.mutationMultiplier(mutation))
end

function Progression.sellPrice(artifactId: string, mutation: string?, data: any, eventMultiplier: number?): number
	return math.floor(
		Progression.artifactValue(artifactId, mutation)
			* GameConfig.Economy.SellPercent
			* Progression.sellMultiplier(data)
			* Progression.cashMultiplier(data)
			* (eventMultiplier or 1)
	)
end

-- Vault / collection scores ------------------------------------------------------------

function Progression.vaultValue(data: any): number
	local total = 0
	for _, record in (data and data.Artifacts or {}) do
		total += Progression.artifactValue(record.Id, record.M)
	end
	return total
end

function Progression.displayValue(data: any): number
	local total = 0
	local artifacts = data and data.Artifacts or {}
	for _, uid in (data and data.Displayed or {}) do
		local record = artifacts[uid]
		if record then
			total += Progression.artifactValue(record.Id, record.M)
		end
	end
	return total
end

function Progression.hasDisplayedEffect(data: any, effect: string): boolean
	local artifacts = data and data.Artifacts or {}
	for _, uid in (data and data.Displayed or {}) do
		local record = artifacts[uid]
		local def = record and Artifacts.get(record.Id)
		if def and def.Effect == effect then
			return true
		end
	end
	return false
end

function Progression.incomePerSecond(data: any): number
	local base = Progression.displayValue(data) * GameConfig.Economy.IncomePerValuePerSecond
	local crown = Progression.hasDisplayedEffect(data, "ThiefCrown") and 1.25 or 1
	return base * crown * Progression.cashMultiplier(data)
end

function Progression.vaultScore(data: any): number
	local rating = Security.rating(data and data.Security or {})
	return math.floor(Progression.displayValue(data) * (1 + rating / 100))
end

function Progression.collectionScore(data: any): number
	local total = 0
	for artifactId in (data and data.Discovered or {}) do
		local def = Artifacts.get(artifactId)
		if def then
			total += Rarities.get(def.Rarity).Score
		end
	end
	return total
end

function Progression.discoveredCount(data: any): number
	local count = 0
	for artifactId in (data and data.Discovered or {}) do
		if Artifacts.get(artifactId) then
			count += 1
		end
	end
	return count
end

function Progression.netWorth(data: any): number
	return math.floor((data and data.Cash or 0) + Progression.vaultValue(data))
end

-- Rebirth ------------------------------------------------------------------------------

function Progression.rebirthRequirement(rebirths: number): (number, number)
	local cfg = Upgrades.Rebirth
	local requiredLevel = math.min(cfg.BaseLevel + rebirths * cfg.LevelPerRebirth, cfg.MaxLevelRequirement)
	local requiredCash = math.floor(cfg.BaseCash * cfg.CashGrowth ^ rebirths)
	return requiredLevel, requiredCash
end

function Progression.rebirthTokens(rebirths: number): number
	local cfg = Upgrades.Rebirth
	return cfg.TokensBase + math.floor(rebirths / cfg.TokensEvery)
end

function Progression.canRebirth(data: any): (boolean, string?)
	local requiredLevel, requiredCash = Progression.rebirthRequirement(data.Rebirths or 0)
	if (data.Level or 1) < requiredLevel then
		return false, string.format("Reach level %d first", requiredLevel)
	end
	if (data.Cash or 0) < requiredCash then
		return false, "Not enough cash"
	end
	return true, nil
end

return Progression
