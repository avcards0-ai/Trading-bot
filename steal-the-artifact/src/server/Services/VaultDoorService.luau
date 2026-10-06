--[[
	VaultDoorService
	The High-Security Vault's giant round door opens on a server-wide cycle. Everyone sees
	the countdown, everyone rushes in, and anyone still inside when it slams shut has to
	crawl out through the emergency vent. Anyone inside without coming through the open
	door (wall glitching) is put back outside.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local VaultDoorService = { Name = "VaultDoorService" }

local S: { [string]: any }

local isOpen = false
local nextChange = 0
local forcedUntil = 0
local warned = false
local allowed: { [Player]: boolean } = {}
local doorValue: CFrameValue

function VaultDoorService:Init(services)
	S = services
end

function VaultDoorService:IsOpen(): boolean
	return isOpen
end

local function setDoor(open: boolean)
	local zone = S.MapService:GetZone("Vault")
	if not zone or not zone.Door then
		return
	end
	isOpen = open
	local door = zone.Door
	local tween = TweenService:Create(
		doorValue,
		TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Value = open and door.Open or door.Closed }
	)
	tween:Play()
	door.Light.Color = open and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 60, 60)
	for _, part in door.Model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = not open or part.Name ~= "Disc"
		end
	end
	zone.Folder:SetAttribute("DoorOpen", open)
	zone.Folder:SetAttribute("DoorChangeAt", workspace:GetServerTimeNow() + math.max(0, nextChange - os.clock()))

	if open then
		S.AnnouncementService:Feed(
			"🏦",
			"The <b>High-Security Vault</b> is OPEN! Get in, grab the loot, get out!",
			Color3.fromRGB(120, 220, 255),
			true
		)
		S.AnnouncementService:Effect("VaultOpen", {}, nil)
	else
		for player in allowed do
			if player.Parent then
				S.AnnouncementService:Notify(
					player,
					"warning",
					"LOCKED IN! The vault door slammed shut - crawl out through the emergency vent!",
					{ Big = true }
				)
			end
		end
		S.AnnouncementService:Effect("VaultClose", {}, nil)
	end
end

function VaultDoorService:ForceOpen(duration: number)
	forcedUntil = os.clock() + duration
	if not isOpen then
		nextChange = forcedUntil
		setDoor(true)
	else
		nextChange = math.max(nextChange, forcedUntil)
		local zone = S.MapService:GetZone("Vault")
		if zone then
			zone.Folder:SetAttribute("DoorChangeAt", workspace:GetServerTimeNow() + (nextChange - os.clock()))
		end
	end
end

local function tick()
	local now = os.clock()
	local cfg = GameConfig.HighSecurityVault
	if now >= nextChange and now >= forcedUntil then
		if isOpen then
			nextChange = now + (cfg.Cycle - cfg.OpenFor)
			warned = false
			setDoor(false)
		else
			nextChange = now + cfg.OpenFor
			setDoor(true)
		end
	elseif not isOpen and not warned and nextChange - now <= 10 then
		warned = true
		S.AnnouncementService:Feed(
			"⏳",
			"The High-Security Vault opens in <b>10 seconds</b>...",
			Color3.fromRGB(120, 220, 255)
		)
	end

	-- Intrusion check
	local zone = S.MapService:GetZone("Vault")
	if not zone or not zone.Interior then
		return
	end
	for _, player in Players:GetPlayers() do
		local root = S.PlayerService:GetRoot(player)
		if root then
			local inside = S.MapService.inRegion(zone.Interior, root.Position)
			if inside then
				if isOpen then
					allowed[player] = true
				elseif not allowed[player] then
					S.PlayerService:Teleport(player, zone.Outside)
					S.AnnouncementService:Notify(player, "error", "The vault is sealed! Wait for the door to open.")
				end
			else
				allowed[player] = nil
			end
		end
	end
end

function VaultDoorService:Start()
	local zone = S.MapService:GetZone("Vault")
	if not zone or not zone.Door then
		return
	end
	doorValue = Instance.new("CFrameValue")
	doorValue.Value = zone.Door.Closed
	doorValue.Changed:Connect(function(value)
		zone.Door.Model:PivotTo(value)
	end)
	nextChange = os.clock() + GameConfig.HighSecurityVault.Cycle - GameConfig.HighSecurityVault.OpenFor
	zone.Folder:SetAttribute("DoorOpen", false)
	zone.Folder:SetAttribute("DoorChangeAt", workspace:GetServerTimeNow() + (nextChange - os.clock()))

	Players.PlayerRemoving:Connect(function(player)
		allowed[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(tick)
			if not ok then
				warn("[VaultDoor]", err)
			end
		end
	end)
end

return VaultDoorService
