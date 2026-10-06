--[[
	Quests
	Missions: 3 personal quests that re-roll when claimed.
	Daily challenges: 3 shared by every player in every server on the same UTC day
	(seeded by the date), plus a bonus for clearing all three.

	`Event` names match the server GameEvents tracked by QuestService.
	Goals scale with `Scale` ("level" multiplies by player level for money goals).
]]

export type QuestDef = {
	Id: string,
	Text: string, -- %s is replaced with the goal
	Event: string,
	Goal: { number },
	Scale: string?, -- "level" -> goal * (1 + level * 0.35)
	MinRarity: string?,
	Zone: string?,
	LevelReq: number?,
	Reward: { Cash: number, XP: number, Gems: number? },
}

local Quests = {}

Quests.Missions = {
	{
		Id = "steal_any",
		Text = "Steal %s artifacts",
		Event = "Steal",
		Goal = { 4, 9 },
		Reward = { Cash = 120, XP = 60 },
	},
	{
		Id = "steal_rare",
		Text = "Steal %s Rare or better artifacts",
		Event = "Steal",
		MinRarity = "Rare",
		Goal = { 2, 4 },
		Reward = { Cash = 250, XP = 120 },
	},
	{
		Id = "steal_epic",
		Text = "Steal %s Epic or better artifacts",
		Event = "Steal",
		MinRarity = "Epic",
		Goal = { 1, 2 },
		LevelReq = 6,
		Reward = { Cash = 600, XP = 260 },
	},
	{
		Id = "secure_value",
		Text = "Secure %s worth of loot",
		Event = "SecureValue",
		Goal = { 250, 600 },
		Scale = "level",
		Reward = { Cash = 200, XP = 110 },
	},
	{
		Id = "zone_museum",
		Text = "Steal %s artifacts from the Museum",
		Event = "Steal",
		Zone = "Museum",
		Goal = { 3, 5 },
		Reward = { Cash = 220, XP = 100 },
	},
	{
		Id = "zone_lab",
		Text = "Steal %s artifacts from the Laboratory",
		Event = "Steal",
		Zone = "Laboratory",
		Goal = { 3, 5 },
		Reward = { Cash = 220, XP = 100 },
	},
	{
		Id = "zone_temple",
		Text = "Steal %s artifacts from the Temple",
		Event = "Steal",
		Zone = "Temple",
		Goal = { 2, 4 },
		Reward = { Cash = 260, XP = 120 },
	},
	{
		Id = "zone_warehouse",
		Text = "Steal %s artifacts from the Warehouse",
		Event = "Steal",
		Zone = "Warehouse",
		Goal = { 3, 6 },
		Reward = { Cash = 200, XP = 90 },
	},
	{
		Id = "zone_underground",
		Text = "Steal %s artifacts in the Underground",
		Event = "Steal",
		Zone = "Underground",
		Goal = { 2, 3 },
		LevelReq = 4,
		Reward = { Cash = 450, XP = 200 },
	},
	{
		Id = "zone_vault",
		Text = "Steal %s artifacts from the High-Security Vault",
		Event = "Steal",
		Zone = "Vault",
		Goal = { 1, 2 },
		LevelReq = 8,
		Reward = { Cash = 900, XP = 400 },
	},
	{
		Id = "raid",
		Text = "Steal %s artifacts from other players' vaults",
		Event = "RaidSteal",
		Goal = { 1, 2 },
		LevelReq = 5,
		Reward = { Cash = 700, XP = 300 },
	},
	{
		Id = "bonk_carrier",
		Text = "Bonk %s players who are carrying loot",
		Event = "BonkCarrier",
		Goal = { 2, 4 },
		Reward = { Cash = 250, XP = 110 },
	},
	{ Id = "sell", Text = "Sell %s artifacts", Event = "Sell", Goal = { 3, 8 }, Reward = { Cash = 150, XP = 70 } },
	{
		Id = "defend",
		Text = "Bonk %s raiders inside your vault",
		Event = "Defend",
		Goal = { 1, 2 },
		LevelReq = 5,
		Reward = { Cash = 500, XP = 220 },
	},
	{
		Id = "alarm_escape",
		Text = "Secure %s artifacts after tripping an alarm",
		Event = "AlarmEscape",
		Goal = { 1, 3 },
		Reward = { Cash = 400, XP = 180 },
	},
	{
		Id = "fail",
		Text = "Get zapped, slipped or tackled %s times (it builds character)",
		Event = "Fail",
		Goal = { 2, 4 },
		Reward = { Cash = 120, XP = 80 },
	},
	{
		Id = "earn",
		Text = "Earn %s",
		Event = "EarnCash",
		Goal = { 400, 900 },
		Scale = "level",
		Reward = { Cash = 150, XP = 90 },
	},
} :: { QuestDef }

Quests.Daily = {
	{
		Id = "d_steal",
		Text = "Steal %s artifacts",
		Event = "Steal",
		Goal = { 20, 30 },
		Reward = { Cash = 800, XP = 400, Gems = 3 },
	},
	{
		Id = "d_epic",
		Text = "Secure %s Epic or better artifacts",
		Event = "Secure",
		MinRarity = "Epic",
		Goal = { 3, 5 },
		Reward = { Cash = 1500, XP = 700, Gems = 4 },
	},
	{
		Id = "d_raid",
		Text = "Steal %s artifacts from player vaults",
		Event = "RaidSteal",
		Goal = { 3, 5 },
		Reward = { Cash = 1500, XP = 700, Gems = 4 },
	},
	{
		Id = "d_bonk",
		Text = "Bonk %s loot carriers",
		Event = "BonkCarrier",
		Goal = { 8, 12 },
		Reward = { Cash = 900, XP = 450, Gems = 3 },
	},
	{
		Id = "d_value",
		Text = "Secure %s worth of loot",
		Event = "SecureValue",
		Goal = { 2500, 5000 },
		Scale = "level",
		Reward = { Cash = 1200, XP = 600, Gems = 4 },
	},
	{
		Id = "d_event",
		Text = "Steal %s artifacts during server events",
		Event = "EventSteal",
		Goal = { 5, 8 },
		Reward = { Cash = 1000, XP = 500, Gems = 4 },
	},
	{
		Id = "d_underground",
		Text = "Steal %s artifacts in the Underground",
		Event = "Steal",
		Zone = "Underground",
		Goal = { 6, 10 },
		Reward = { Cash = 1300, XP = 650, Gems = 4 },
	},
	{
		Id = "d_alarm",
		Text = "Secure %s artifacts after tripping alarms",
		Event = "AlarmEscape",
		Goal = { 4, 6 },
		Reward = { Cash = 1200, XP = 600, Gems = 4 },
	},
	{
		Id = "d_sell",
		Text = "Sell %s artifacts",
		Event = "Sell",
		Goal = { 25, 40 },
		Reward = { Cash = 700, XP = 350, Gems = 2 },
	},
	{
		Id = "d_defend",
		Text = "Defend your vault from %s raiders",
		Event = "Defend",
		Goal = { 3, 5 },
		Reward = { Cash = 1400, XP = 650, Gems = 4 },
	},
} :: { QuestDef }

Quests.DailyBonus = { Cash = 2500, XP = 1200, Gems = 15 }
Quests.ActiveMissions = 3
Quests.DailyCount = 3
Quests.RerollCost = 100 -- cash, scaled by level

Quests.MissionById = {} :: { [string]: QuestDef }
for _, def in Quests.Missions do
	Quests.MissionById[def.Id] = def
end
Quests.DailyById = {} :: { [string]: QuestDef }
for _, def in Quests.Daily do
	Quests.DailyById[def.Id] = def
end

-- Days since the Unix epoch (UTC). Every server agrees on this.
function Quests.dayNumber(now: number?): number
	return math.floor((now or os.time()) / 86400)
end

function Quests.rewardScale(level: number): number
	return 1 + (level - 1) * 0.18
end

function Quests.goalFor(def: QuestDef, level: number, roll: number): number
	local low, high = def.Goal[1], def.Goal[2]
	local goal = low + math.floor((high - low) * roll + 0.5)
	if def.Scale == "level" then
		goal = math.floor(goal * (1 + (level - 1) * 0.35))
	end
	return math.max(1, goal)
end

return Quests
