--[[
	Achievements
	`Stat` is a key in the player's Stats table, or one of the derived stats computed by
	AchievementService: Level, Rebirths, Discovered, DailyStreakBest.
	Rewards are Gems (cosmetic currency) and Titles (cosmetic name-tag text).
]]

export type Achievement = {
	Id: string,
	Name: string,
	Desc: string,
	Stat: string,
	Goal: number,
	Gems: number,
	Title: string?,
	Hidden: boolean?,
	Icon: string,
}

local Artifacts = require(script.Parent.Artifacts)

local list: { Achievement } = {
	{ Id = "first_steal", Name = "Sticky Fingers", Desc = "Steal your first artifact.", Stat = "Steals", Goal = 1, Gems = 5, Icon = "🖐️" },
	{ Id = "steals_50", Name = "Kleptomaniac", Desc = "Steal 50 artifacts.", Stat = "Steals", Goal = 50, Gems = 15, Icon = "🎒" },
	{ Id = "steals_500", Name = "Professional", Desc = "Steal 500 artifacts.", Stat = "Steals", Goal = 500, Gems = 40, Title = "Professional", Icon = "🕶️" },
	{ Id = "steals_5000", Name = "Grand Theft Artifact", Desc = "Steal 5,000 artifacts.", Stat = "Steals", Goal = 5000, Gems = 100, Title = "Grand Thief", Icon = "🦹" },
	{ Id = "secure_legendary", Name = "Legendary Heist", Desc = "Secure a Legendary artifact.", Stat = "LegendarySecured", Goal = 1, Gems = 25, Icon = "🌟" },
	{ Id = "secure_mythic", Name = "Myth Buster", Desc = "Secure a Mythic artifact.", Stat = "MythicSecured", Goal = 1, Gems = 50, Title = "Myth Buster", Icon = "🔥" },
	{ Id = "secure_secret", Name = "Keeper of Secrets", Desc = "Secure a SECRET artifact.", Stat = "SecretSecured", Goal = 1, Gems = 150, Title = "Secret Keeper", Hidden = true, Icon = "❔" },
	{ Id = "raid_1", Name = "Home Invader", Desc = "Steal from another player's vault.", Stat = "Raids", Goal = 1, Gems = 10, Icon = "🏠" },
	{ Id = "raid_50", Name = "Vault Breaker", Desc = "Steal 50 artifacts from player vaults.", Stat = "Raids", Goal = 50, Gems = 50, Title = "Vault Breaker", Icon = "💣" },
	{ Id = "defend_10", Name = "Home Security", Desc = "Bonk 10 raiders inside your vault.", Stat = "Defends", Goal = 10, Gems = 25, Title = "Guardian", Icon = "🛡️" },
	{ Id = "bonk_100", Name = "Bonk Master", Desc = "Bonk 100 players.", Stat = "Bonks", Goal = 100, Gems = 20, Title = "Bonker", Icon = "🔨" },
	{ Id = "bonk_carriers_50", Name = "Loot Interceptor", Desc = "Knock loot out of 50 carriers.", Stat = "BonkedCarriers", Goal = 50, Gems = 25, Icon = "🥅" },
	{ Id = "zapped_25", Name = "Shocking Performance", Desc = "Get zapped by lasers 25 times.", Stat = "Zapped", Goal = 25, Gems = 15, Title = "Crispy", Icon = "⚡" },
	{ Id = "slipped_25", Name = "Banana Victim", Desc = "Slip on 25 banana peels.", Stat = "Slipped", Goal = 25, Gems = 15, Title = "Banana Victim", Icon = "🍌" },
	{ Id = "sprung_10", Name = "Frequent Flyer", Desc = "Get launched by 10 spring traps.", Stat = "Sprung", Goal = 10, Gems = 10, Icon = "🚀" },
	{ Id = "tackled_25", Name = "Caught Red-Handed", Desc = "Get tackled by guards 25 times.", Stat = "Tackled", Goal = 25, Gems = 10, Title = "Usual Suspect", Icon = "🚓" },
	{ Id = "drops_100", Name = "Butterfingers", Desc = "Drop 100 artifacts.", Stat = "Drops", Goal = 100, Gems = 20, Title = "Butterfingers", Icon = "🧈" },
	{ Id = "sold_100", Name = "Fence's Favorite", Desc = "Sell 100 artifacts.", Stat = "Sold", Goal = 100, Gems = 15, Icon = "🤝" },
	{ Id = "earned_100k", Name = "Six Figures", Desc = "Earn $100K in total.", Stat = "TotalEarned", Goal = 100000, Gems = 20, Icon = "💵" },
	{ Id = "earned_10m", Name = "Tycoon", Desc = "Earn $10M in total.", Stat = "TotalEarned", Goal = 10000000, Gems = 60, Title = "Tycoon", Icon = "💰" },
	{ Id = "earned_1b", Name = "Billionaire Bandit", Desc = "Earn $1B in total.", Stat = "TotalEarned", Goal = 1000000000, Gems = 200, Title = "Billionaire", Icon = "🏦" },
	{ Id = "level_10", Name = "Getting Good", Desc = "Reach level 10.", Stat = "Level", Goal = 10, Gems = 10, Icon = "📈" },
	{ Id = "level_25", Name = "Seasoned", Desc = "Reach level 25.", Stat = "Level", Goal = 25, Gems = 25, Icon = "🧂" },
	{ Id = "level_50", Name = "Veteran Thief", Desc = "Reach level 50.", Stat = "Level", Goal = 50, Gems = 60, Title = "Veteran", Icon = "🎖️" },
	{ Id = "rebirth_1", Name = "Born Again", Desc = "Rebirth for the first time.", Stat = "Rebirths", Goal = 1, Gems = 25, Icon = "🔄" },
	{ Id = "rebirth_5", Name = "Phoenix", Desc = "Rebirth 5 times.", Stat = "Rebirths", Goal = 5, Gems = 60, Title = "Reborn", Icon = "🔥" },
	{ Id = "rebirth_10", Name = "Infinite Loop", Desc = "Rebirth 10 times.", Stat = "Rebirths", Goal = 10, Gems = 120, Title = "Eternal", Icon = "♾️" },
	{ Id = "collection_25", Name = "Collector", Desc = "Discover 25 different artifacts.", Stat = "Discovered", Goal = 25, Gems = 20, Icon = "📖" },
	{ Id = "collection_50", Name = "Curator", Desc = "Discover 50 different artifacts.", Stat = "Discovered", Goal = 50, Gems = 50, Title = "Curator", Icon = "🏛️" },
	{ Id = "collection_all", Name = "Completionist", Desc = "Discover every artifact. Yes, even the secret ones.", Stat = "Discovered", Goal = #Artifacts.List, Gems = 300, Title = "Completionist", Icon = "👑" },
	{ Id = "events_10", Name = "Party Animal", Desc = "Steal during 10 server events.", Stat = "EventsJoined", Goal = 10, Gems = 20, Icon = "🎉" },
	{ Id = "shiny_1", Name = "Ooh, Shiny!", Desc = "Secure a Shiny artifact.", Stat = "ShinySecured", Goal = 1, Gems = 10, Icon = "✨" },
	{ Id = "rainbow_1", Name = "Taste the Rainbow", Desc = "Secure a Rainbow artifact.", Stat = "RainbowSecured", Goal = 1, Gems = 50, Title = "Rainbow Hunter", Icon = "🌈" },
	{ Id = "secret_room", Name = "Explorer", Desc = "Find the hidden room.", Stat = "SecretRoomVisits", Goal = 1, Gems = 25, Hidden = true, Icon = "🗝️" },
	{ Id = "streak_7", Name = "Loyal Thief", Desc = "Reach a 7-day login streak.", Stat = "DailyStreakBest", Goal = 7, Gems = 30, Icon = "📅" },
	{ Id = "pack_mule", Name = "Pack Mule", Desc = "Carry 10 artifacts at once.", Stat = "MaxCarried", Goal = 10, Gems = 20, Icon = "🐴" },
	{ Id = "big_score", Name = "Big Score", Desc = "Secure a single artifact worth $100K+.", Stat = "HighestSecure", Goal = 100000, Gems = 40, Icon = "💸" },
}

local Achievements = {}
Achievements.List = list
Achievements.ById = {} :: { [string]: Achievement }
Achievements.ByStat = {} :: { [string]: { Achievement } }
for _, achievement in list do
	Achievements.ById[achievement.Id] = achievement
	Achievements.ByStat[achievement.Stat] = Achievements.ByStat[achievement.Stat] or {}
	table.insert(Achievements.ByStat[achievement.Stat], achievement)
end

return Achievements
