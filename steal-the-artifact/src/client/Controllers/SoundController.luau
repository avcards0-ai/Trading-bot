--[[
	SoundController
	UI + 3D sound effects and background music, respecting the player's volume settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local Components = require(script.Parent.Parent.UI.Components)

local SoundController = { Name = "SoundController" }

local Data
local sfxGroup: SoundGroup
local musicGroup: SoundGroup
local templates: { [string]: Sound } = {}
local music: Sound?
local musicState = ""
local lastPlayed: { [string]: number } = {}

function SoundController:Init(controllers)
	Data = controllers.DataController
end

local function template(name: string): Sound?
	if templates[name] then
		return templates[name]
	end
	local def = Sounds[name]
	if not def or def.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	sound.PlaybackSpeed = def.Speed or 1
	sound.SoundGroup = sfxGroup
	templates[name] = sound
	return sound
end

export type PlayOptions = { Volume: number?, Speed: number? }

function SoundController:Play(name: string, options: PlayOptions?)
	local base = template(name)
	if not base then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < 0.03 then
		return
	end
	lastPlayed[name] = now
	local def = Sounds[name]
	local sound = base:Clone()
	local variance = def.Variance or 0
	sound.PlaybackSpeed = ((options and options.Speed) or (def.Speed or 1)) * (1 + (math.random() * 2 - 1) * variance)
	sound.Volume = def.Volume * ((options and options.Volume) or 1)
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 6)
end

function SoundController:PlayAt(name: string, position: Vector3, options: PlayOptions?)
	local base = template(name)
	if not base then
		return
	end
	local def = Sounds[name]
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local sound = base:Clone()
	sound.RollOffMaxDistance = 220
	sound.RollOffMinDistance = 12
	local variance = def.Variance or 0
	sound.PlaybackSpeed = ((options and options.Speed) or (def.Speed or 1)) * (1 + (math.random() * 2 - 1) * variance)
	sound.Volume = def.Volume * ((options and options.Volume) or 1)
	sound.Parent = attachment
	sound:Play()
	Debris:AddItem(attachment, 6)
end

-- "Calm" | "Event" | "Chase"
function SoundController:SetMusic(state: string)
	if state == musicState then
		return
	end
	musicState = state
	local def = Sounds["Music" .. state]
	if music then
		local old = music
		Components.tween(old, 1.5, { Volume = 0 })
		task.delay(1.6, function()
			old:Destroy()
		end)
		music = nil
	end
	if not def or def.Id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	sound:Play()
	Components.tween(sound, 1.5, { Volume = def.Volume })
	music = sound
end

local function applyVolumes(settings: any)
	if type(settings) ~= "table" then
		return
	end
	sfxGroup.Volume = settings.SFX or 0.8
	musicGroup.Volume = settings.Music or 0.5
end

function SoundController:Start()
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "SFX"
	sfxGroup.Parent = SoundService
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Parent = SoundService

	Components.setSoundHandler(function(name)
		self:Play(name)
	end)
	Data:Observe("Settings", applyVolumes)
	self:SetMusic("Calm")
end

return SoundController
