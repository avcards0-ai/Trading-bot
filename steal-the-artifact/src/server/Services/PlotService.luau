--[[
	PlotService
	Assigns each player a vault plot, keeps the pedestal displays in sync with their data,
	runs the SECURE pad (stand on it with loot) and the owner's auto-opening door.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Security = require(Shared.Config.Security)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)

local PlotService = { Name = "PlotService" }

local S: { [string]: any }

local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}
local pedestalUids: { [number]: { [number]: string } } = {} -- plot -> pedestal index -> uid
local doorOpenUntil: { [number]: number } = {}
local doorTweens: { [number]: Tween } = {}

local INACTIVE_PEDESTAL = Color3.fromRGB(70, 70, 80)

function PlotService:Init(services)
	S = services
end

function PlotService:GetPlotIndex(player: Player): number?
	return plotOf[player]
end

function PlotService:GetPlot(player: Player)
	local index = plotOf[player]
	return index and S.MapService:GetPlot(index) or nil
end

function PlotService:GetOwner(index: number): Player?
	return owners[index]
end

function PlotService:AllOwned(): { [number]: Player }
	return owners
end

-- Door ------------------------------------------------------------------------------------

function PlotService:IsDoorOpen(index: number): boolean
	return (doorOpenUntil[index] or 0) > os.clock()
end

function PlotService:SetDoor(index: number, open: boolean)
	local plot = S.MapService:GetPlot(index)
	if not plot then
		return
	end
	local door = plot.Door.Part
	local target = open and plot.Door.Open or plot.Door.Closed
	if doorTweens[index] then
		doorTweens[index]:Cancel()
	end
	local tween = TweenService:Create(door, TweenInfo.new(open and 0.35 or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target })
	doorTweens[index] = tween
	tween:Play()
	door.CanCollide = not open
end

function PlotService:OpenDoor(index: number, duration: number)
	local wasOpen = self:IsDoorOpen(index)
	local untilTime = os.clock() + duration
	doorOpenUntil[index] = math.max(doorOpenUntil[index] or 0, untilTime)
	if not wasOpen then
		self:SetDoor(index, true)
	end
	task.delay(duration + 0.05, function()
		if (doorOpenUntil[index] or 0) <= os.clock() then
			self:SetDoor(index, false)
		end
	end)
end

function PlotService:CloseDoorNow(index: number)
	doorOpenUntil[index] = 0
	self:SetDoor(index, false)
end

-- Sign / pedestals ----------------------------------------------------------------------------

function PlotService:RefreshSign(player: Player)
	local plot = self:GetPlot(player)
	local data = S.DataService:Get(player)
	if not plot or not data then
		return
	end
	local rating = Security.rating(data.Security)
	plot.Sign.Label.Text = string.format(
		"<b>%s's VAULT</b>\n💎 %s on display · 🔒 %d%%",
		Format.escape(player.DisplayName),
		Format.cash(Progression.displayValue(data)),
		rating
	)
	plot.Folder:SetAttribute("OwnerUserId", player.UserId)
	plot.Folder:SetAttribute("OwnerName", player.DisplayName)
	plot.Folder:SetAttribute("SecurityRating", rating)
end

function PlotService:RefreshDisplay(player: Player)
	local index = plotOf[player]
	local data = S.DataService:Get(player)
	if not index or not data then
		return
	end
	local plot = S.MapService:GetPlot(index)
	local slots = math.min(Progression.displaySlots(data), #plot.Pedestals)
	local assigned = pedestalUids[index] or {}
	pedestalUids[index] = assigned

	local wanted: { [string]: boolean } = {}
	for i, uid in data.Displayed do
		if i > slots then
			break
		end
		if data.Artifacts[uid] then
			wanted[uid] = true
		end
	end
	-- Remove displays that are no longer wanted (or whose pedestal got deactivated)
	for pedestal, uid in assigned do
		if not wanted[uid] or pedestal > slots then
			S.ArtifactService:RemoveDisplay(uid)
			assigned[pedestal] = nil
		end
	end
	local placed: { [string]: boolean } = {}
	for _, uid in assigned do
		placed[uid] = true
	end
	-- Place new ones on the lowest free pedestals
	for _, uid in data.Displayed do
		if wanted[uid] and not placed[uid] then
			for pedestal = 1, slots do
				if not assigned[pedestal] then
					assigned[pedestal] = uid
					placed[uid] = true
					S.ArtifactService:CreateDisplay(index, player, uid, data.Artifacts[uid], plot.Pedestals[pedestal].CFrame)
					break
				end
			end
		end
	end
	-- Skin first, then dim the locked pedestals on top of it.
	S.CosmeticService:ApplyVaultSkin(player)
	for i, pedestal in plot.Pedestals do
		local active = i <= slots
		pedestal.Glow.Transparency = active and 0 or 0.6
		if not active then
			pedestal.Glow.Color = INACTIVE_PEDESTAL
		end
	end
end

local function clearDisplays(index: number)
	local assigned = pedestalUids[index]
	if assigned then
		for _, uid in assigned do
			S.ArtifactService:RemoveDisplay(uid)
		end
	end
	pedestalUids[index] = {}
end

-- Assignment ---------------------------------------------------------------------------------

function PlotService:Assign(player: Player): number?
	if plotOf[player] then
		return plotOf[player]
	end
	local map = S.MapService:Get()
	for index = 1, #map.Plots do
		if not owners[index] then
			owners[index] = player
			plotOf[player] = index
			local plot = map.Plots[index]
			S.DataService:SetSession(player, "PlotIndex", index)
			S.DataService:SetSession(player, "SecurePad", plot.SecurePad.Position)
			plot.Door.Prompt.Enabled = true
			self:RefreshSign(player)
			self:RefreshDisplay(player)
			S.SecurityService:InstallPlot(player)
			S.GuardService:RefreshPlot(player)
			S.PlayerService:SendHome(player)
			return index
		end
	end
	S.AnnouncementService:Notify(player, "warning", "All vault plots are taken - you can still steal and sell!")
	return nil
end

function PlotService:Release(player: Player)
	local index = plotOf[player]
	if not index then
		return
	end
	plotOf[player] = nil
	owners[index] = nil
	local plot = S.MapService:GetPlot(index)
	clearDisplays(index)
	S.SecurityService:ClearPlot(index)
	S.GuardService:ClearPlot(index)
	self:CloseDoorNow(index)
	plot.Door.Prompt.Enabled = false
	plot.Sign.Label.Text = "EMPTY LOT"
	plot.Folder:SetAttribute("OwnerUserId", nil)
	plot.Folder:SetAttribute("OwnerName", nil)
	plot.Folder:SetAttribute("AlarmUntil", nil)
	S.CosmeticService:ResetVaultSkin(index)
end

-- Loops -----------------------------------------------------------------------------------

local function tick()
	for index, player in owners do
		local plot = S.MapService:GetPlot(index)
		local root = S.PlayerService:GetRoot(player)
		if root and S.PlayerService:IsAlive(player) then
			local pos = root.Position
			-- SECURE pad
			if S.CarryService:Count(player) > 0 then
				local pad = plot.SecurePad
				local flat = Vector3.new(pos.X - pad.Position.X, 0, pos.Z - pad.Position.Z).Magnitude
				if flat <= pad.Radius and math.abs(pos.Y - pad.Position.Y) < 7 then
					S.InventoryService:SecureCarried(player)
				end
			end
			-- Owner's door opens automatically
			if (pos - plot.Door.Part.Position).Magnitude <= GameConfig.Raid.OwnerDoorRange then
				if (doorOpenUntil[index] or 0) - os.clock() < 1 then
					PlotService:OpenDoor(index, GameConfig.Raid.DoorOpenTime)
				end
			end
		end
	end
end

function PlotService:Start()
	S.DataService.Loaded:Connect(function(player)
		self:Assign(player)
	end)
	S.DataService.Removing:Connect(function(player)
		self:Release(player)
	end)
	S.DataService.Changed:Connect(function(player, key)
		if key == "Security" then
			self:RefreshSign(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:Release(player)
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			tick()
		end
	end)
end

return PlotService
