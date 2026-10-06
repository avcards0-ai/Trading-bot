--[[
	TravelService
	Hatches between the surface and the Underground (great escape routes!), the emergency
	vent out of the High-Security Vault, the "Recall" home button and secret room discovery.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Zones = require(Shared.Config.Zones)

local PromptGuard = require(script.Parent.Parent.PromptGuard)
local RequestRouter = require(script.Parent.Parent.RequestRouter)

local TravelService = { Name = "TravelService" }

local S: { [string]: any }
local recallReady: { [Player]: number } = {}
local visitedSecret: { [Player]: boolean } = {}

function TravelService:Init(services)
	S = services
end

local function useHatch(player: Player, hatch: any)
	if not PromptGuard.validate(player, hatch.Prompt, hatch.Prompt.HoldDuration) then
		return
	end
	if S.PlayerService:HasStatus(player, "Stunned") then
		return
	end
	local root = S.PlayerService:GetRoot(player)
	if root then
		S.AnnouncementService:Effect("Hatch", { Position = root.Position }, root.Position, 120)
	end
	S.PlayerService:Teleport(player, hatch.Destination + Vector3.new(0, 3, 0))
	S.AnnouncementService:Effect("Hatch", { Position = hatch.Destination.Position }, hatch.Destination.Position, 120)
end

function TravelService:Recall(player: Player): (boolean, string?)
	if not S.PlotService:GetPlot(player) then
		return false, "You don't have a vault yet"
	end
	if S.CarryService:Count(player) > 0 then
		return false, "You can't teleport with loot - RUN!"
	end
	if not S.PlayerService:IsAlive(player) or S.PlayerService:HasStatus(player, "Stunned") then
		return false, "Not right now!"
	end
	local now = os.clock()
	local ready = recallReady[player] or 0
	if now < ready then
		return false, string.format("Recall ready in %ds", math.ceil(ready - now))
	end
	recallReady[player] = now + GameConfig.Raid.RecallCooldown
	S.DataService:SetSession(player, "RecallReadyAt", workspace:GetServerTimeNow() + GameConfig.Raid.RecallCooldown)
	local root = S.PlayerService:GetRoot(player)
	if root then
		S.AnnouncementService:Effect("Recall", { Position = root.Position }, root.Position, 150)
	end
	S.PlayerService:SendHome(player)
	return true, "Home sweet vault!"
end

function TravelService:Start()
	for _, hatch in S.MapService:Get().Hatches do
		PromptGuard.watch(hatch.Prompt)
		hatch.Prompt.Triggered:Connect(function(player)
			useHatch(player, hatch)
		end)
	end

	RequestRouter.register("Recall", { Rate = 1, Burst = 2 }, function(player)
		return self:Recall(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		recallReady[player] = nil
		visitedSecret[player] = nil
	end)

	-- Secret room discovery
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local root = S.PlayerService:GetRoot(player)
				if root and not visitedSecret[player] then
					local zone = Zones.at(root.Position)
					if zone and zone.Id == "SecretRoom" then
						visitedSecret[player] = true
						local data = S.DataService:Get(player)
						local first = data and (data.Stats.SecretRoomVisits or 0) == 0
						S.DataService:Increment(player, "SecretRoomVisits")
						if first then
							S.AnnouncementService:Feed("🗝️", string.format("<b>%s</b> found something hidden underground...", S.AnnouncementService.name(player)), Color3.fromRGB(255, 220, 120))
							S.AnnouncementService:Notify(player, "reward", "🗝️ You found the SECRET ROOM!", { Big = true })
						end
					end
				end
			end
		end
	end)
end

return TravelService
