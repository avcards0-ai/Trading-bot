--[[
	GameEvents
	Server-side event bus. Gameplay services fire these; quests, achievements, feed and
	analytics listen. Keeps systems decoupled (the steal code doesn't know quests exist).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local GameEvents = {
	-- (player, info) info: { Uid, Id, Rarity, Mutation, Zone, Source, Value, VictimUserId? }
	ArtifactStolen = Signal.new(),
	-- (player, info) info: { Id, Rarity, Mutation, Zone, Source, Value, Alarm, Raided }
	ArtifactSecured = Signal.new(),
	-- (player, count, value)
	ArtifactSold = Signal.new(),
	-- (attacker, victim, info) info: { Carrier, Defend, Dropped }
	Bonked = Signal.new(),
	-- (player, kind)
	Failed = Signal.new(),
	-- (player, amount)
	CashEarned = Signal.new(),
	-- (player, newLevel)
	LevelUp = Signal.new(),
	-- (player)
	Rebirthed = Signal.new(),
	-- (raider, ownerPlayer)
	VaultCracked = Signal.new(),
}

return GameEvents
