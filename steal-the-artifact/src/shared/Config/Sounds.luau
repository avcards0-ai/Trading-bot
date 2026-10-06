--[[
	Sounds
	Defaults use sounds that ship inside the Roblox client (rbxasset://), so the game
	makes noise out of the box with no uploads. Swap any Id for your own
	"rbxassetid://..." audio from the Creator Store for a more polished mix.
	An empty Id is silently skipped.
]]

export type SoundDef = { Id: string, Volume: number, Speed: number?, Variance: number? }

local Sounds: { [string]: SoundDef } = {
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 1.1 },
	Hover = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.15, Speed = 1.6 },
	OpenWindow = { Id = "rbxasset://sounds/button.wav", Volume = 0.35, Speed = 1.2 },
	CloseWindow = { Id = "rbxasset://sounds/button.wav", Volume = 0.3, Speed = 0.9 },
	Purchase = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 1.3 },
	Error = { Id = "rbxasset://sounds/button.wav", Volume = 0.5, Speed = 0.6 },
	Steal = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 1.0, Variance = 0.08 },
	StealRare = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Speed = 0.75 },
	Secure = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Speed = 1.5 },
	CashTick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.25, Speed = 2.0, Variance = 0.15 },
	Bonk = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.8, Speed = 0.7, Variance = 0.1 },
	Whoosh = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.6, Speed = 1.2, Variance = 0.1 },
	Hurt = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.7, Speed = 1.0, Variance = 0.15 },
	Fail = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.9, Speed = 0.8 },
	Zap = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Speed = 0.35 },
	Spring = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 1, Speed = 0.6 },
	Splash = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.7, Speed = 1.0 },
	Alarm = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Speed = 0.5 },
	LevelUp = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Speed = 1.8 },
	Announce = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 0.9 },
	Honk = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 1, Speed = 2.2 },
	Dash = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.5, Speed = 1.4 },
	-- Background music: add your own licensed tracks.
	MusicCalm = { Id = "", Volume = 0.3 },
	MusicEvent = { Id = "", Volume = 0.35 },
	MusicChase = { Id = "", Volume = 0.35 },
}

return Sounds
