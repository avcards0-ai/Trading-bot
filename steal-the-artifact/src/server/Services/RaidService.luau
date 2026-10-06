--[[
	RaidService
	Breaking into other players' vaults.

	  * Crack the door (hold prompt; time from the owner's Door level) -> door opens briefly,
	    alarm trips, owner gets a RAID ALERT. Anyone who slips in while it's open can raid
	    (tailgating is a feature).
	  * Alarm levels add marks, lockdown, slowdown, bounties and citywide alerts.
	  * Intrusion check: anyone inside a vault who didn't come through an open door is
	    put back outside (stops wall-glitching / noclip).
	  * Fairness: Rookie Shield below level 5, a shield after every successful raid, and a
	    revenge bonus for raiding whoever just robbed you.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Security = require(Shared.Config.Security)
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local GameEvents = require(script.Parent.Parent.GameEvents)
local PromptGuard = require(script.Parent.Parent.PromptGuard)

local RaidService = { Name = "RaidService" }

local S: { [string]: any }
local MapService

local authorized: { [number]: { [Player]: boolean } } = {}
local lastAlert: { [number]: number } = {}
local bounties: { [Player]: { Amount: number, Until: number } } = {}

function RaidService:Init(services)
	S = services
	MapService = services.MapService
end

-- Queries -------------------------------------------------------------------------------------

function RaidService:IsInsidePlot(player: Player, index: number): boolean
	local plot = S.MapService:GetPlot(index)
	local root = S.PlayerService:GetRoot(player)
	return plot ~= nil and root ~= nil and MapService.inRegion(plot.Interior, root.Position)
end

function RaidService:IsIntruding(player: Player, index: number): boolean
	local owner = S.PlotService:GetOwner(index)
	return owner ~= nil and owner ~= player and self:IsInsidePlot(player, index)
end

local function shieldRemaining(owner: Player): number
	local session = S.DataService:Session(owner)
	return session and math.max(0, (session.ShieldUntil or 0) - os.clock()) or 0
end

-- Shared raid eligibility checks. Returns ok, reason.
function RaidService:CanRaid(raider: Player, owner: Player): (boolean, string?)
	local raiderData = S.DataService:Get(raider)
	local ownerData = S.DataService:Get(owner)
	if not raiderData or not ownerData then
		return false, nil
	end
	if raiderData.Level < GameConfig.Raid.MinLevelToRaid and raiderData.Rebirths == 0 then
		return false, string.format("Reach level %d to start raiding vaults!", GameConfig.Raid.MinLevelToRaid)
	end
	if ownerData.Level < GameConfig.Raid.MinLevelToBeRaided and ownerData.Rebirths == 0 then
		return false, "This vault has a Rookie Shield 🛡️"
	end
	local shield = shieldRemaining(owner)
	if shield > 0 then
		return false, string.format("This vault is shielded for %ds", math.ceil(shield))
	end
	return true, nil
end

function RaidService:CanStealFromPlot(raider: Player, plotIndex: number?, ownerUserId: number?): (boolean, string?)
	if not plotIndex then
		return false, nil
	end
	local owner = S.PlotService:GetOwner(plotIndex)
	if not owner or owner.UserId ~= ownerUserId or owner == raider then
		return false, nil
	end
	local ok, reason = self:CanRaid(raider, owner)
	if not ok then
		return false, reason
	end
	if not self:IsInsidePlot(raider, plotIndex) then
		return false, nil
	end
	return true, nil
end

-- Alarms --------------------------------------------------------------------------------------

function RaidService:TriggerAlarm(index: number, raider: Player, cause: string)
	local owner = S.PlotService:GetOwner(index)
	local ownerData = owner and S.DataService:Get(owner)
	if not owner or not ownerData then
		return
	end
	local level = ownerData.Security.Alarm or 0
	local plot = S.MapService:GetPlot(index)
	plot.Folder:SetAttribute("AlarmUntil", workspace:GetServerTimeNow() + 15)
	S.PlayerService:SetStatus(raider, "Marked", Security.stat("Alarm", "MarkDuration", level))

	if level >= 2 and cause ~= "crack" then
		S.PlotService:CloseDoorNow(index)
	end
	if level >= 3 then
		S.PlayerService:SetStatus(raider, "Slowed", 10)
	end
	if level >= 4 then
		local raiderData = S.DataService:Get(raider)
		local amount = GameConfig.Raid.BountyPerAlarmLevel * level * math.max(1, math.floor((raiderData and raiderData.Level or 1) / 5))
		bounties[raider] = { Amount = amount, Until = os.clock() + 30 }
		raider:SetAttribute("Bounty", amount)
		task.delay(30, function()
			local bounty = bounties[raider]
			if bounty and bounty.Until <= os.clock() then
				bounties[raider] = nil
				raider:SetAttribute("Bounty", nil)
			end
		end)
	end

	local now = os.clock()
	if now - (lastAlert[index] or 0) > 8 then
		lastAlert[index] = now
		Net.event("RaidAlert"):FireClient(owner, {
			Raider = raider.DisplayName,
			Cause = cause,
			PlotIndex = index,
			Position = plot.SecurePad.Position,
		})
		if level >= 5 then
			S.AnnouncementService:Feed("🚨", string.format("<b>%s</b> is raiding <b>%s</b>'s vault! Bonk them for a bounty!", S.AnnouncementService.name(raider), S.AnnouncementService.name(owner)), Color3.fromRGB(255, 90, 90), true)
		end
	end
end

function RaidService:OnSpotted(index: number, raider: Player)
	self:TriggerAlarm(index, raider, "camera")
end

function RaidService:ClaimBounty(victim: Player, attacker: Player): number
	local bounty = bounties[victim]
	if not bounty or bounty.Until < os.clock() or attacker == victim then
		return 0
	end
	bounties[victim] = nil
	victim:SetAttribute("Bounty", nil)
	return S.EconomyService:AddCash(attacker, bounty.Amount, true)
end

-- Door prompt ---------------------------------------------------------------------------------

local function crackTime(owner: Player): number
	local data = S.DataService:Get(owner)
	return Security.stat("Door", "CrackTime", data and data.Security.Door or 0)
end

function RaidService:UpdateDoorPrompt(owner: Player)
	local index = S.PlotService:GetPlotIndex(owner)
	local data = S.DataService:Get(owner)
	if not index or not data then
		return
	end
	local plot = S.MapService:GetPlot(index)
	local prompt = plot.Door.Prompt
	prompt.HoldDuration = crackTime(owner)
	prompt:SetAttribute("BaseHold", prompt.HoldDuration)
	prompt.ObjectText = string.format("%s's Vault (Door Lv %d)", owner.DisplayName, data.Security.Door or 0)
end

local function onCrack(player: Player, index: number, prompt: ProximityPrompt)
	local owner = S.PlotService:GetOwner(index)
	if not owner then
		return
	end
	if owner == player then
		S.PlotService:OpenDoor(index, GameConfig.Raid.DoorOpenTime)
		return
	end
	local ok, reason = RaidService:CanRaid(player, owner)
	if not ok then
		if reason then
			S.AnnouncementService:Notify(player, "error", reason)
		end
		return
	end
	local raiderData = S.DataService:Get(player)
	local expected = crackTime(owner) * Progression.crackMultiplier(raiderData)
	if not PromptGuard.validate(player, prompt, expected) then
		return
	end
	S.PlotService:OpenDoor(index, GameConfig.Raid.DoorOpenTime)
	authorized[index] = authorized[index] or {}
	authorized[index][player] = true
	RaidService:TriggerAlarm(index, player, "crack")
	local plot = S.MapService:GetPlot(index)
	S.AnnouncementService:Effect("Crack", { Position = plot.Door.Part.Position, UserId = player.UserId }, plot.Door.Part.Position, 250)
	S.AnnouncementService:Notify(player, "success", "Door cracked! Grab what you can and RUN!")
	GameEvents.VaultCracked:Fire(player, owner)
end

-- Stolen from a vault ---------------------------------------------------------------------

function RaidService:OnVaultArtifactStolen(raider: Player, owner: Player, artifactId: string, mutation: string?)
	local ownerSession = S.DataService:Session(owner)
	if ownerSession then
		-- ShieldUntil is server-clock (os.clock); ShieldEnds is server time for the client UI.
		ownerSession.ShieldUntil = os.clock() + GameConfig.Raid.ShieldAfterRaid
		S.DataService:SetSession(owner, "ShieldEnds", workspace:GetServerTimeNow() + GameConfig.Raid.ShieldAfterRaid)
		ownerSession.Revenge = ownerSession.Revenge or {}
		ownerSession.Revenge[raider.UserId] = os.clock() + GameConfig.Raid.RevengeWindow
	end
	S.DataService:Increment(owner, "TimesRaided")
	S.PlotService:RefreshDisplay(owner)
	S.PlotService:RefreshSign(owner)
	S.DataService:RequestSave(owner)

	local def = Artifacts.get(artifactId)
	local name = def and ((mutation and (mutation .. " ") or "") .. def.Name) or "an artifact"
	local color = def and Rarities.textColor(def.Rarity) or Color3.new(1, 1, 1)
	Net.event("RaidAlert"):FireClient(owner, {
		Raider = raider.DisplayName,
		Cause = "stolen",
		Artifact = artifactId,
		Mutation = mutation,
	})
	S.AnnouncementService:Feed("🏴‍☠️", string.format("<b>%s</b> raided <b>%s</b>'s vault and grabbed %s!", S.AnnouncementService.name(raider), S.AnnouncementService.name(owner), Format.rich(name, color)))
	S.AnnouncementService:Notify(owner, "error", string.format("%s stole your %s! Bonk them to get it back - revenge pays +%d%%!", raider.DisplayName, name, GameConfig.Raid.RevengeBonusPercent * 100))
end

-- Intrusion loop ---------------------------------------------------------------------------

local function intrusionTick()
	for index, owner in S.PlotService:AllOwned() do
		local plot = S.MapService:GetPlot(index)
		local allowed = authorized[index] or {}
		authorized[index] = allowed
		local doorOpen = S.PlotService:IsDoorOpen(index)
		local ownerData = S.DataService:Get(owner)
		local alarmLevel = ownerData and ownerData.Security.Alarm or 0
		for _, player in Players:GetPlayers() do
			if player ~= owner then
				local root = S.PlayerService:GetRoot(player)
				if root then
					local inside = MapService.inRegion(plot.Interior, root.Position)
					local nearDoor = (root.Position - plot.Door.Part.Position).Magnitude < 10
					if doorOpen and (inside or nearDoor) then
						allowed[player] = true
					end
					if inside then
						if not allowed[player] then
							S.PlayerService:Teleport(player, plot.Front)
							S.AnnouncementService:Notify(player, "error", "Nice try! Vault walls are solid. Crack the door instead.")
						elseif alarmLevel >= 3 and S.PlayerService:HasStatus(player, "Marked") then
							S.PlayerService:SetStatus(player, "Slowed", 1)
						end
					elseif not nearDoor then
						allowed[player] = nil
					end
				end
			end
		end
	end
end

function RaidService:Start()
	local map = S.MapService:Get()
	for index, plot in map.Plots do
		local prompt = plot.Door.Prompt
		PromptGuard.watch(prompt)
		prompt.Triggered:Connect(function(player)
			onCrack(player, index, prompt)
		end)
	end

	S.DataService.Changed:Connect(function(player, key)
		if key == "Security" then
			self:UpdateDoorPrompt(player)
		end
	end)
	S.DataService.Loaded:Connect(function(player)
		task.defer(function()
			self:UpdateDoorPrompt(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		bounties[player] = nil
		for _, allowed in authorized do
			allowed[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(intrusionTick)
			if not ok then
				warn("[Raid]", err)
			end
		end
	end)
end

return RaidService
