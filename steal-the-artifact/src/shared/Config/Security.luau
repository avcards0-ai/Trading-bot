--[[
	Security
	Vault security upgrade tracks. Index tables by (level + 1): level 0 = not installed.
	All numbers are read by the server for gameplay and by the client for UI previews.
]]

export type SecurityTrack = {
	Id: string,
	Name: string,
	Icon: string,
	Desc: string,
	MaxLevel: number,
	BaseCost: number,
	Growth: number,
	Levels: { string }, -- one-line description of each level (1..Max)
}

local Security = {}

Security.Tracks = {
	{
		Id = "Door",
		Name = "Vault Door",
		Icon = "🚪",
		Desc = "Raiders must crack your door before getting in. Cracking it trips your alarm.",
		MaxLevel = 5,
		BaseCost = 400,
		Growth = 2.6,
		Levels = {
			"Reinforced Wood - 4s to crack",
			"Steel Door - 6s to crack",
			"Titanium Door - 8s to crack",
			"Bank Door - 11s to crack",
			"Mega Vault Door - 14s to crack",
		},
	},
	{
		Id = "Lasers",
		Name = "Laser Grid",
		Icon = "🔴",
		Desc = "Laser beams zap raiders, stun them and knock loot out of their hands.",
		MaxLevel = 5,
		BaseCost = 650,
		Growth = 2.6,
		Levels = {
			"2 static beams",
			"3 blinking beams",
			"4 sweeping beams",
			"5 fast sweeping beams",
			"6 chaos beams (good luck)",
		},
	},
	{
		Id = "Cameras",
		Name = "Security Cameras",
		Icon = "📹",
		Desc = "Sweeping cameras spot raiders, mark them for everyone and alert your guards.",
		MaxLevel = 5,
		BaseCost = 550,
		Growth = 2.6,
		Levels = {
			"1 camera, narrow view",
			"2 cameras",
			"2 cameras, wider view",
			"3 cameras, long range",
			"4 cameras, eagle eye",
		},
	},
	{
		Id = "Traps",
		Name = "Silly Traps",
		Icon = "🍌",
		Desc = "Banana peels, spring pads and glue puddles. Hilarious. For you.",
		MaxLevel = 5,
		BaseCost = 350,
		Growth = 2.6,
		Levels = {
			"2 banana peels",
			"3 peels + 1 spring pad",
			"3 peels + 2 springs + 1 glue",
			"4 peels + 2 springs + 2 glue",
			"5 peels + 3 springs + 2 glue",
		},
	},
	{
		Id = "Guards",
		Name = "Vault Guards",
		Icon = "👮",
		Desc = "Guards patrol your vault and tackle anyone who isn't you.",
		MaxLevel = 5,
		BaseCost = 1500,
		Growth = 2.6,
		Levels = {
			"1 sleepy guard",
			"1 alert guard",
			"2 guards",
			"2 fast guards",
			"3 elite guards",
		},
	},
	{
		Id = "Alarm",
		Name = "Alarm System",
		Icon = "🚨",
		Desc = "Bigger alarms mark raiders longer and add nasty surprises.",
		MaxLevel = 5,
		BaseCost = 300,
		Growth = 2.6,
		Levels = {
			"Raiders marked for 10s",
			"+ Lockdown: door slams shut behind raiders",
			"+ Raiders move 20% slower inside",
			"+ Bounty: anyone who bonks your raider earns cash",
			"+ Citywide alert: the whole server is told",
		},
	},
} :: { SecurityTrack }

Security.ById = {} :: { [string]: SecurityTrack }
for _, track in Security.Tracks do
	Security.ById[track.Id] = track
end

-- Per-level stats (index = level + 1)
Security.Stats = {
	Door = { CrackTime = { 2.5, 4, 6, 8, 11, 14 } },
	Lasers = {
		Beams = { 0, 2, 3, 4, 5, 6 },
		Pattern = { "None", "Static", "Blink", "Sweep", "Sweep", "Chaos" },
		Speed = { 0, 0, 1.1, 0.9, 1.4, 1.8 },
	},
	Cameras = {
		Count = { 0, 1, 2, 2, 3, 4 },
		Range = { 0, 30, 34, 40, 46, 54 },
		Fov = { 0, 34, 40, 50, 55, 62 },
		Sweep = { 0, 0.45, 0.55, 0.6, 0.7, 0.85 },
	},
	Traps = {
		Banana = { 0, 2, 3, 3, 4, 5 },
		Spring = { 0, 0, 1, 2, 2, 3 },
		Glue = { 0, 0, 0, 1, 2, 2 },
	},
	Guards = {
		Count = { 0, 1, 1, 2, 2, 3 },
		Speed = { 0, 14, 17, 17, 20, 21 },
		Sight = { 0, 26, 34, 36, 42, 48 },
	},
	Alarm = {
		MarkDuration = { 6, 10, 14, 18, 22, 26 },
	},
}

function Security.stat(trackId: string, statName: string, level: number): any
	local track = (Security.Stats :: any)[trackId]
	local values = track and track[statName]
	if not values then
		return nil
	end
	return values[math.clamp(level, 0, #values - 1) + 1]
end

-- Rough 0-100 rating used on vault signs and the "Best Vault" leaderboard.
function Security.rating(levels: { [string]: number }): number
	local total, max = 0, 0
	for _, track in Security.Tracks do
		total += levels[track.Id] or 0
		max += track.MaxLevel
	end
	return math.floor(total / max * 100 + 0.5)
end

return Security
