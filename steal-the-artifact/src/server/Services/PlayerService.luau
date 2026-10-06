--[[
	PlayerService
	Character lifecycle: spawning at your vault, spawn protection, overhead name tags,
	leaderstats, and timed status attributes (Dazed / Stunned / Marked / Glued ...)
	that every client renders.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Upgrades = require(Shared.Config.Upgrades)
local Format = require(Shared.Util.Format)

local PlayerService = { Name = "PlayerService" }

local S: { [string]: any }

function PlayerService:Init(services)
	S = services
end

function PlayerService.now(): number
	return workspace:GetServerTimeNow()
end

function PlayerService:GetRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function PlayerService:GetHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function PlayerService:IsAlive(player: Player): boolean
	local humanoid = self:GetHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Status attributes -----------------------------------------------------------------------

-- Sets a timed status on the character (value = server time it ends).
function PlayerService:SetStatus(player: Player, status: string, duration: number)
	local character = player.Character
	if not character then
		return
	end
	local untilTime = self.now() + duration
	local current = character:GetAttribute(status)
	if type(current) ~= "number" or current < untilTime then
		character:SetAttribute(status, untilTime)
	end
end

function PlayerService:HasStatus(player: Player, status: string): boolean
	local character = player.Character
	local value = character and character:GetAttribute(status)
	return type(value) == "number" and value > self.now()
end

function PlayerService:ClearStatus(player: Player, status: string)
	local character = player.Character
	if character then
		character:SetAttribute(status, nil)
	end
end

-- Leaderstats -----------------------------------------------------------------------------

function PlayerService:UpdateLeaderstats(player: Player)
	local data = S.DataService:Get(player)
	local stats = player:FindFirstChild("leaderstats")
	if not data or not stats then
		return
	end
	local cash = stats:FindFirstChild("Cash") :: StringValue?
	local steals = stats:FindFirstChild("Steals") :: IntValue?
	local rebirths = stats:FindFirstChild("Rebirths") :: IntValue?
	if cash then
		cash.Value = Format.cash(data.Cash)
	end
	if steals then
		steals.Value = data.Stats.Steals
	end
	if rebirths then
		rebirths.Value = data.Rebirths
	end
end

local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = folder
	local steals = Instance.new("IntValue")
	steals.Name = "Steals"
	steals.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	folder.Parent = player
end

-- Name tags -------------------------------------------------------------------------------

function PlayerService:RefreshNameTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local data = S.DataService:Get(player)
	if not head or not data then
		return
	end
	local session = S.DataService:Session(player)
	local tag = head:FindFirstChild("NameTag") :: BillboardGui?
	if not tag then
		local gui = Instance.new("BillboardGui")
		gui.Name = "NameTag"
		gui.Size = UDim2.fromOffset(220, 58)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 110
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlayerName"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.fromScale(1, 0.55)
		nameLabel.Font = Enum.Font.FredokaOne
		nameLabel.TextScaled = true
		nameLabel.RichText = true
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(20, 20, 30)
		stroke.Parent = nameLabel

		local info = Instance.new("TextLabel")
		info.Name = "Info"
		info.BackgroundTransparency = 1
		info.Position = UDim2.fromScale(0, 0.55)
		info.Size = UDim2.fromScale(1, 0.4)
		info.Font = Enum.Font.FredokaOne
		info.TextScaled = true
		info.RichText = true
		info.TextColor3 = Color3.fromRGB(230, 230, 240)
		info.Parent = gui
		local stroke2 = Instance.new("UIStroke")
		stroke2.Thickness = 1.5
		stroke2.Color = Color3.fromRGB(20, 20, 30)
		stroke2.Parent = info

		gui.Parent = head
		tag = gui
	end
	local gui = tag :: BillboardGui
	local rank = Upgrades.rank(data.Rebirths)
	local vip = session and session.IsVIP
	local nameText = Format.escape(player.DisplayName)
	if vip then
		nameText = Format.rich("[VIP] ", Color3.fromRGB(255, 205, 60))
			.. Format.rich(nameText, Color3.fromRGB(255, 235, 150))
	end
	local title = data.Cosmetics.Equipped.Title
	local parts = { "Lv " .. data.Level }
	if data.Rebirths > 0 then
		table.insert(parts, "🔁" .. data.Rebirths)
	end
	table.insert(parts, Format.rich(rank.Name, rank.Color))
	if title ~= "" then
		table.insert(parts, Format.rich("«" .. Format.escape(title) .. "»", Color3.fromRGB(255, 200, 90)))
	end
	(gui:FindFirstChild("PlayerName") :: TextLabel).Text = nameText;
	(gui:FindFirstChild("Info") :: TextLabel).Text = table.concat(parts, " · ")
end

-- Spawning --------------------------------------------------------------------------------

function PlayerService:GetSpawnCFrame(player: Player): CFrame?
	local plot = S.PlotService:GetPlot(player)
	return plot and plot.SpawnCFrame
end

-- Teleports the player's character (and tells anti-cheat to expect it).
function PlayerService:Teleport(player: Player, target: CFrame)
	local character = player.Character
	if not character then
		return
	end
	S.AntiCheatService:Allow(player, 2)
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 3)
		end)
	end)
	character:PivotTo(target)
end

function PlayerService:SendHome(player: Player)
	local target = self:GetSpawnCFrame(player)
	if target then
		self:Teleport(player, target)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.UseJumpPower = true
	humanoid.JumpPower = GameConfig.Character.JumpPower

	-- Spawn protection
	local field = Instance.new("ForceField")
	field.Visible = true
	field.Parent = character
	PlayerService:SetStatus(player, "Protected", GameConfig.Character.SpawnProtection)
	task.delay(GameConfig.Character.SpawnProtection, function()
		if field.Parent then
			field:Destroy()
		end
	end)

	-- Go home
	task.defer(function()
		if character.Parent and player.Character == character then
			PlayerService:SendHome(player)
		end
	end)

	PlayerService:RefreshNameTag(player)
	S.CarryService:OnCharacterAdded(player, character)
	S.CombatService:OnCharacterAdded(player, character)
	S.CosmeticService:ApplyCharacter(player)
end

function PlayerService:Start()
	Players.RespawnTime = GameConfig.Character.RespawnTime

	local function setup(player: Player)
		createLeaderstats(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end

	S.DataService.Loaded:Connect(function(player)
		self:UpdateLeaderstats(player)
		self:RefreshNameTag(player)
	end)
	S.DataService.Changed:Connect(function(player, key)
		if key == "Cosmetics" then
			self:RefreshNameTag(player)
		end
	end)
end

return PlayerService
