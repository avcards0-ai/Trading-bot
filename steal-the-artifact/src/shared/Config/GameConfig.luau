--[[
	GameConfig
	Core tunables. Everything a designer is likely to tweak lives here or in the other
	Config modules; gameplay code reads these instead of hard-coding numbers.
]]

local GameConfig = {}

GameConfig.GameName = "STEAL THE ARTIFACT"
GameConfig.DataVersion = 1
GameConfig.DataStoreName = "STA_PlayerData_v1"

-- Player movement / character
GameConfig.Character = {
	BaseWalkSpeed = 18,
	JumpPower = 52,
	MinWalkSpeed = 9, -- never slower than this from carry weight
	CarrySlowPerWeight = 0.035, -- 3.5% slower per unit of carry weight
	MaxCarrySlow = 0.38,
	SpawnProtection = 4,
	RespawnTime = 3,
}

-- Carrying
GameConfig.Carry = {
	BaseCapacity = 3,
	DroppedLifetime = 75, -- seconds a dropped artifact stays in the world
	DropScatter = 7, -- studs
	PickupOwnBackDistance = 14,
}

-- Combat (Bonk)
GameConfig.Combat = {
	BonkCooldown = 0.9,
	BonkRange = 9.5,
	BonkConeDegrees = 80,
	BonkDamage = 18,
	BonkStunCarrier = 1.25,
	BonkDazeEmpty = 0.5,
	BonkKnockback = 38,
	KillCreditWindow = 6,
	DashCooldown = 4.5,
	DashSpeed = 78,
}

-- Raiding
GameConfig.Raid = {
	MinLevelToRaid = 5, -- you must be this level to raid ...
	MinLevelToBeRaided = 5, -- ... and so must your victim ("Rookie Shield")
	ShieldAfterRaid = 90, -- seconds of protection after an artifact is stolen from you
	DoorOpenTime = 4,
	OwnerDoorRange = 11,
	RaidBonusPercent = 0.25, -- extra cash when you secure a raided artifact
	RevengeWindow = 300,
	RevengeBonusPercent = 0.5,
	PedestalHoldMultiplier = 1.5,
	BountyPerAlarmLevel = 150,
	RecallCooldown = 40,
}

-- Economy
GameConfig.Economy = {
	SecureBonusPercent = 0.25, -- instant cash on securing, as a fraction of value
	SellPercent = 1.0,
	OverflowSellPercent = 0.6, -- auto-sale when the vault is full
	IncomePerValuePerSecond = 0.0008, -- displayed artifacts pay this * value every second
	IncomeTick = 5,
	RebirthCashBonusPerRebirth = 0.2, -- +20% cash per rebirth (permanent)
	RebirthXPBonusPerRebirth = 0.1,
}

-- Mutations rolled when an artifact spawns.
GameConfig.Mutations = {
	Shiny = { Chance = 0.05, ValueMultiplier = 2, Label = "Shiny", Color = Color3.fromRGB(255, 245, 170) },
	Rainbow = { Chance = 0.006, ValueMultiplier = 5, Label = "Rainbow", Color = Color3.fromRGB(255, 120, 255) },
}

-- Server-wide events
GameConfig.Events = {
	FirstEventDelay = 150,
	MinInterval = 420,
	MaxInterval = 600,
}

GameConfig.Plots = {
	Count = 12,
	Radius = 600,
	Size = 96,
}

GameConfig.Map = {
	WorldRadius = 760,
	UndergroundY = -90,
}

GameConfig.Leaderboards = {
	SubmitInterval = 180,
	RefreshInterval = 120,
	TopCount = 50,
}

GameConfig.Data = {
	AutosaveInterval = 60,
	SessionLockExpiry = 1800, -- a lock older than this is considered abandoned
	LoadRetries = 5,
	MinSaveGap = 7,
}

GameConfig.DailyRewards = {
	ClaimCooldown = 20 * 3600,
	StreakBreak = 48 * 3600,
}

-- Security device timing
GameConfig.Security = {
	TrapRearm = 4.5,
	ZapStun = 1.4,
	ZapDamage = 22,
	SlipStun = 1.8,
	SpringStun = 1.6,
	GlueDuration = 3.5,
	GlueSpeed = 5,
	MarkedDuration = 12,
	ZoneAlarmDuration = 22,
	GuardTackleDamage = 28,
	GuardTackleStun = 1.6,
	GuardTackleRange = 4.6,
}

GameConfig.HighSecurityVault = {
	Cycle = 180, -- door opens every N seconds ...
	OpenFor = 45, -- ... and stays open this long
}

GameConfig.Debug = {
	-- Studio-only conveniences; ignored in live servers.
	StudioStartingCash = 0,
	StudioFastEvents = false,
}

return GameConfig
