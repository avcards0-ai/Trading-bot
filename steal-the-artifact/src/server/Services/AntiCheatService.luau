--[[
	AntiCheatService
	Movement is client-authoritative in Roblox, so the one exploit that breaks the core
	loop is teleporting loot home. This watches the horizontal speed of everyone who is
	carrying loot; sustained impossible speed drops their loot where they last were legit
	and pulls them back. Server-initiated teleports, dashes and knockbacks get a grace window.
	Deliberately lenient - false positives on laggy players are worse than a rare cheater.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local RequestRouter = require(script.Parent.Parent.RequestRouter)

local AntiCheatService = { Name = "AntiCheatService" }

local S: { [string]: any }

type Track = {
	Position: Vector3,
	Time: number,
	Strikes: number,
	SafePosition: Vector3,
	GraceUntil: number,
	LastDash: number,
}

local tracks: { [Player]: Track } = {}

local CHECK_INTERVAL = 0.5
local SLACK = 1.7
local DASH_ALLOWANCE = 90

function AntiCheatService:Init(services)
	S = services
end

-- Expect a burst of movement (teleport, launch, knockback).
function AntiCheatService:Allow(player: Player, seconds: number)
	local track = tracks[player]
	if track then
		track.GraceUntil = math.max(track.GraceUntil, os.clock() + seconds)
	end
end

function AntiCheatService:LastSafePosition(player: Player): Vector3?
	local track = tracks[player]
	return track and track.SafePosition
end

local function check(player: Player)
	local root = S.PlayerService:GetRoot(player)
	if not root then
		tracks[player] = nil
		return
	end
	local now = os.clock()
	local track = tracks[player]
	if not track then
		tracks[player] = {
			Position = root.Position,
			Time = now,
			Strikes = 0,
			SafePosition = root.Position,
			GraceUntil = now + 2,
			LastDash = 0,
		}
		return
	end
	local dt = now - track.Time
	local delta = (root.Position - track.Position) * Vector3.new(1, 0, 1)
	local speed = delta.Magnitude / math.max(dt, 0.001)
	local humanoid = S.PlayerService:GetHumanoid(player)
	local allowed = ((humanoid and humanoid.WalkSpeed or 16) * SLACK) + 8
	if now - track.LastDash < 1 then
		allowed += DASH_ALLOWANCE
	end
	local carrying = S.CarryService:Count(player) > 0

	if now < track.GraceUntil or not carrying or speed <= allowed then
		track.Strikes = math.max(0, track.Strikes - 1)
		if speed <= allowed then
			track.SafePosition = root.Position
		end
	else
		track.Strikes += 1
		if track.Strikes >= 2 then
			track.Strikes = 0
			local safe = track.SafePosition
			S.CarryService:Drop(player, nil, "moving suspiciously fast")
			AntiCheatService:Allow(player, 2)
			local character = player.Character
			if character then
				character:PivotTo(CFrame.new(safe + Vector3.new(0, 3, 0)))
			end
			S.AnnouncementService:Notify(player, "warning", "Whoa, too fast! Your loot fell out.")
		end
	end
	track.Position = root.Position
	track.Time = now
end

function AntiCheatService:Start()
	Net.event("Dash").OnServerEvent:Connect(function(player)
		if not RequestRouter.consume(player, "Dash", 0.5, 1) then
			return
		end
		local track = tracks[player]
		if track and os.clock() - track.LastDash >= GameConfig.Combat.DashCooldown * 0.8 then
			track.LastDash = os.clock()
			local root = S.PlayerService:GetRoot(player)
			if root then
				S.AnnouncementService:Effect("Dash", { UserId = player.UserId }, root.Position, 150)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(check, player)
				if not ok then
					warn("[AntiCheat]", err)
				end
			end
		end
	end)
end

return AntiCheatService
