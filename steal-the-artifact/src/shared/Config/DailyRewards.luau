--[[
	DailyRewards
	A 7-day streak calendar. Claim once every 20h; miss 48h and the streak resets.
	Cash rewards scale with level so they stay meaningful. Artifact rewards go straight
	into your vault storage.
]]

export type DailyReward = {
	Day: number,
	Cash: number?,
	Gems: number?,
	ArtifactRarity: string?,
	Label: string,
	Icon: string,
}

local DailyRewards = {}

DailyRewards.Days = {
	{ Day = 1, Cash = 300, Label = "Pocket Money", Icon = "💵" },
	{ Day = 2, Cash = 500, Gems = 5, Label = "Cash + Gems", Icon = "💎" },
	{ Day = 3, ArtifactRarity = "Rare", Label = "Rare Artifact", Icon = "🎁" },
	{ Day = 4, Cash = 1200, Label = "Fat Stack", Icon = "💰" },
	{ Day = 5, Gems = 15, Label = "Gem Pile", Icon = "💎" },
	{ Day = 6, Cash = 2500, Gems = 5, Label = "Big Payday", Icon = "🤑" },
	{ Day = 7, ArtifactRarity = "Epic", Gems = 30, Label = "Epic Artifact + Gems", Icon = "👑" },
} :: { DailyReward }

function DailyRewards.cashScale(level: number): number
	return 1 + (level - 1) * 0.25
end

return DailyRewards
