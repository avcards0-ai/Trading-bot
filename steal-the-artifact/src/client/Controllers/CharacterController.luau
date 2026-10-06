--[[
	CharacterController
	The local character's actions and physics reactions:
	  * Bonk (asks the server; server decides hits), Dash, Recall home
	  * Ragdoll on stun (server toggles joints, we flip the Humanoid state + limb collision)
	  * Knockback impulses from bonks / spring traps
	  * Emotes + the emote wheel
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Cosmetics = require(Shared.Config.Cosmetics)
local Net = require(Shared.Net)

local UIFolder = script.Parent.Parent.UI
local Components = require(UIFolder.Components)
local Theme = require(UIFolder.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local CharacterController = { Name = "CharacterController" }

local controllers: { [string]: any }
local Data
local lastBonk = 0
local lastDash = 0
local emoteTrack: AnimationTrack?
local wheel: Frame?
local savedCollision: { [BasePart]: boolean } = {}

function CharacterController:Init(all)
	controllers = all
	Data = all.DataController
end

local function parts()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, root
end

local function stunned(): boolean
	local character = player.Character
	local value = character and character:GetAttribute("Stunned")
	return type(value) == "number" and value > workspace:GetServerTimeNow()
end

-- Actions ---------------------------------------------------------------------------------------

-- Nearest player in front of us (just a hint; the server re-checks everything).
local function targetHint(root: BasePart): Player?
	local best, bestDistance = nil, GameConfig.Combat.BonkRange
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character then
			local oroot = other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if oroot then
				local offset = oroot.Position - root.Position
				local distance = offset.Magnitude
				if distance < bestDistance and root.CFrame.LookVector:Dot(offset.Unit) > 0.3 then
					best, bestDistance = other, distance
				end
			end
		end
	end
	return best
end

function CharacterController:Bonk()
	local _, humanoid, root = parts()
	if not humanoid or not root or humanoid.Health <= 0 or stunned() then
		return
	end
	local now = os.clock()
	if now - lastBonk < GameConfig.Combat.BonkCooldown then
		return
	end
	lastBonk = now
	self:StopEmote()
	Net.event("Bonk"):FireServer(targetHint(root))
	controllers.WorldFXController:Punch(root.Parent)
	controllers.SoundController:PlayAt("Whoosh", root.Position)
	controllers.HUDController:SetCooldown("Bonk", GameConfig.Combat.BonkCooldown)
	controllers.EffectsController:FovPunch(-4)
end

function CharacterController:Dash()
	local _, humanoid, root = parts()
	if not humanoid or not root or humanoid.Health <= 0 or stunned() then
		return
	end
	local now = os.clock()
	if now - lastDash < GameConfig.Combat.DashCooldown then
		return
	end
	lastDash = now
	self:StopEmote()
	local direction = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.MoveDirection or root.CFrame.LookVector
	direction = Vector3.new(direction.X, 0, direction.Z)
	direction = direction.Magnitude > 0 and direction.Unit or Vector3.zAxis
	Net.event("Dash"):FireServer()

	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = 60000
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * GameConfig.Combat.DashSpeed
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.Parent = root
	task.delay(0.18, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
	controllers.HUDController:SetCooldown("Dash", GameConfig.Combat.DashCooldown)
	controllers.EffectsController:FovPunch(10)
	controllers.SoundController:Play("Dash")
end

function CharacterController:Recall()
	local response = Net.request("Recall")
	if response.msg then
		controllers.AnnouncementController:Toast(response.ok and "success" or "error", response.msg)
	end
	if response.ok then
		controllers.HUDController:SetCooldown("Home", GameConfig.Raid.RecallCooldown)
	end
end

-- Emotes ----------------------------------------------------------------------------------------

function CharacterController:StopEmote()
	if emoteTrack then
		emoteTrack:Stop(0.2)
		emoteTrack = nil
	end
end

function CharacterController:PlayEmote(id: string)
	local item = Cosmetics.ById[id]
	local _, humanoid = parts()
	if not item or not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local animId = humanoid.RigType == Enum.HumanoidRigType.R15 and item.AnimR15 or item.AnimR6
	if not animator or not animId then
		return
	end
	self:StopEmote()
	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = item.Looped == true
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.2)
		emoteTrack = track
	end
end

function CharacterController:ToggleWheel()
	if wheel then
		wheel:Destroy()
		wheel = nil
		return
	end
	local emotes = (Data:Get("Cosmetics") or {}).Emotes or {}
	local overlay = controllers.UIController.OverlayScaled
	local frame = Components.new("Frame", {
		Name = "EmoteWheel",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(320, 320),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = overlay,
	})
	local center = Components.panel({
		Size = UDim2.fromOffset(90, 90),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Background,
		Radius = UDim.new(1, 0),
		Parent = frame,
	})
	Components.label({
		Text = "EMOTES",
		Size = UDim2.new(1, -10, 1, -10),
		Position = UDim2.fromOffset(5, 5),
		MaxTextSize = 18,
		Parent = center,
	})
	local first: GuiObject? = nil
	for i, id in emotes do
		local item = Cosmetics.ById[id]
		if item then
			local angle = (i - 1) / math.max(#emotes, 1) * math.pi * 2 - math.pi / 2
			local button = Components.button({
				Text = item.Icon,
				Color = C.PanelLight,
				Size = UDim2.fromOffset(74, 74),
				Position = UDim2.new(0.5, math.cos(angle) * 115, 0.5, math.sin(angle) * 115),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Radius = UDim.new(1, 0),
				MaxTextSize = 36,
				Parent = frame,
				OnClick = function()
					self:PlayEmote(id)
					self:ToggleWheel()
				end,
			})
			first = first or button
		end
	end
	if #emotes == 0 then
		Components.label({
			Text = "No emotes equipped - get some in the Shop!",
			Size = UDim2.fromOffset(300, 40),
			Position = UDim2.new(0.5, -150, 1, 0),
			MaxTextSize = 18,
			Parent = frame,
		})
	end
	Components.pop(frame, 0.5)
	wheel = frame
	if first and game:GetService("UserInputService").GamepadEnabled then
		game:GetService("GuiService").SelectedObject = first
	end
end

-- Physics reactions ---------------------------------------------------------------------------

local function setRagdoll(character: Model, enabled: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Parent == character then
			if enabled then
				if savedCollision[part] == nil then
					savedCollision[part] = part.CanCollide
				end
				part.CanCollide = true
			elseif savedCollision[part] ~= nil then
				part.CanCollide = savedCollision[part]
				savedCollision[part] = nil
			end
		end
	end
	if enabled then
		CharacterController:StopEmote()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	elseif humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function onCharacter(character: Model)
	table.clear(savedCollision)
	emoteTrack = nil
	character:GetAttributeChangedSignal("Ragdoll"):Connect(function()
		setRagdoll(character, character:GetAttribute("Ragdoll") == true)
	end)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.Running:Connect(function(speed)
			if speed > 1 and emoteTrack and emoteTrack.Looped then
				CharacterController:StopEmote()
			end
		end)
	end
end

function CharacterController:Start()
	Net.event("Knockback").OnClientEvent:Connect(function(velocity: Vector3)
		local _, humanoid, root = parts()
		if typeof(velocity) ~= "Vector3" or not root or velocity.Magnitude > 400 then
			return
		end
		if humanoid and humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		root.AssemblyLinearVelocity = velocity
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	Data:ObserveSession("RecallReadyAt", function(value)
		if type(value) == "number" then
			local remaining = value - workspace:GetServerTimeNow()
			if remaining > 0 then
				controllers.HUDController:SetCooldown("Home", remaining)
			end
		end
	end)
end

return CharacterController
