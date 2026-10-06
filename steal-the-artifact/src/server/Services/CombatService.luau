--[[
	CombatService
	BONK! The melee that makes loot carriers drop their best artifact, plus every "fail"
	(zaps, banana slips, spring launches, guard tackles...), stuns, ragdolls and deaths.

	Bonk security: the client only says "I swung" (with an optional target hint). The server
	enforces cooldown + rate limit, finds a target in front of the attacker within range,
	applies safe-zone / home-advantage rules and decides damage and drops itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Zones = require(Shared.Config.Zones)
local Progression = require(Shared.Progression)
local Tables = require(Shared.Util.Tables)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local GameEvents = require(script.Parent.Parent.GameEvents)
local RequestRouter = require(script.Parent.Parent.RequestRouter)

local CombatService = { Name = "CombatService" }

local S: { [string]: any }

local lastBonk: { [Player]: number } = {}
local lastBonkedBy: { [Player]: { Attacker: Player, At: number } } = {}
local ragdollJoints: { [Model]: { { Motor: Motor6D, Socket: BallSocketConstraint } } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any
local stunTokens: { [Player]: number } = {}

local CAPTIONS = {
	Bonk = { "BONK!", "Get bonked!", "Skill issue.", "Knocked silly!", "That's gonna leave a mark." },
	Zap = { "SHOCKING!", "Bzzzzt!", "Crispy!", "Well, that was electrifying.", "Lasers: 1, You: 0" },
	Slip = { "BANANA'D!", "Classic.", "Watch your step!", "Peeled it.", "A true comedy legend." },
	Spring = { "YEET!", "To infinity!", "Launch successful.", "Frequent flyer miles +1", "Have a nice flight!" },
	Glue = { "STUCK!", "Sticky situation...", "Glued to the spot!" },
	Tackle = { "BUSTED!", "Caught red-handed!", "Guard: 1, You: 0", "TACKLED!", "Not very sneaky." },
	Spike = { "OUCH!", "Pointy!", "Ancient traps still work." },
	Toxic = { "Ew. Ew. Ew.", "That's not water.", "Toxic!" },
	Fall = { "Gravity wins.", "Oops." },
}

local STAT_FOR_FAIL =
	{ Zap = "Zapped", Slip = "Slipped", Spring = "Sprung", Glue = "Glued", Tackle = "Tackled", Spike = "Spiked" }

function CombatService:Init(services)
	S = services
end

-- Ragdoll ------------------------------------------------------------------------------------

local function setupRagdoll(character: Model)
	local joints = {}
	for _, motor in character:GetDescendants() do
		if
			motor:IsA("Motor6D")
			and motor.Name ~= "RootJoint"
			and motor.Name ~= "Root"
			and motor.Part0
			and motor.Part1
		then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.TwistLimitsEnabled = true
			socket.UpperAngle = 55
			socket.TwistLowerAngle = -50
			socket.TwistUpperAngle = 50
			socket.Enabled = false
			socket.Parent = motor.Parent
			table.insert(joints, { Motor = motor, Socket = socket })
		end
	end
	ragdollJoints[character] = joints
end

function CombatService:SetRagdoll(player: Player, enabled: boolean)
	local character = player.Character
	if not character then
		return
	end
	local joints = ragdollJoints[character]
	if joints then
		for _, joint in joints do
			if joint.Motor.Parent then
				joint.Motor.Enabled = not enabled
				joint.Socket.Enabled = enabled
			end
		end
	end
	-- The owning client flips the humanoid into / out of the Physics state.
	character:SetAttribute("Ragdoll", enabled)
end

-- Stun: freezes movement, optionally ragdolls. Thick Skin perk shortens it.
function CombatService:Stun(player: Player, duration: number, ragdoll: boolean?)
	local data = S.DataService:Get(player)
	duration *= Progression.stunMultiplier(data)
	if duration <= 0 then
		return
	end
	S.PlayerService:SetStatus(player, "Stunned", duration)
	S.CarryService:RefreshSpeed(player)
	local token = (stunTokens[player] or 0) + 1
	stunTokens[player] = token
	if ragdoll then
		self:SetRagdoll(player, true)
	end
	task.delay(duration, function()
		if stunTokens[player] ~= token then
			return
		end
		local humanoid = S.PlayerService:GetHumanoid(player)
		if humanoid and humanoid.Health > 0 then
			self:SetRagdoll(player, false)
		end
		S.CarryService:RefreshSpeed(player)
	end)
end

local function knockback(player: Player, velocity: Vector3)
	S.AntiCheatService:Allow(player, 2)
	Net.event("Knockback"):FireClient(player, velocity)
end

-- Fails (traps, lasers, guards) ----------------------------------------------------------------

export type FailOptions = { Damage: number?, Stun: number?, Drop: number?, Knockback: Vector3?, By: string? }

function CombatService:ApplyFail(player: Player, kind: string, options: FailOptions)
	local humanoid = S.PlayerService:GetHumanoid(player)
	local root = S.PlayerService:GetRoot(player)
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local caption = Tables.pickRandom(CAPTIONS[kind] or CAPTIONS.Bonk) or "OOF!"
	local dropped = {}
	if options.Drop and options.Drop > 0 and S.CarryService:Count(player) > 0 then
		local verb = kind == "Zap" and "zapped"
			or kind == "Slip" and "slipped"
			or kind == "Spring" and "launched"
			or kind == "Tackle" and "tackled"
			or "hit"
		dropped = S.CarryService:Drop(player, options.Drop, options.By and (verb .. " by " .. options.By) or verb)
	end
	if options.Stun then
		self:Stun(player, options.Stun, kind ~= "Glue")
	end
	if options.Knockback then
		knockback(player, options.Knockback)
	end
	if options.Damage then
		humanoid:TakeDamage(options.Damage)
	end
	local stat = STAT_FOR_FAIL[kind]
	if stat then
		S.DataService:Increment(player, stat)
	end
	Net.event("Fail"):FireClient(player, kind, caption, { By = options.By, Dropped = #dropped })
	S.AnnouncementService:Effect(
		"FailPop",
		{ Kind = kind, Position = root.Position, UserId = player.UserId, Caption = caption },
		root.Position,
		180
	)
	GameEvents.Failed:Fire(player, kind)
end

-- Bonk ---------------------------------------------------------------------------------------

local function inSafeZone(position: Vector3): boolean
	local zone = Zones.at(position)
	return zone ~= nil and zone.Safe
end

local function findTarget(attacker: Player, root: BasePart, hint: Player?): Player?
	local cfg = GameConfig.Combat
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0 and look.Unit or Vector3.zAxis
	local cosLimit = math.cos(math.rad(cfg.BonkConeDegrees / 2))
	local best, bestScore = nil, math.huge
	for _, player in Players:GetPlayers() do
		if
			player ~= attacker
			and S.PlayerService:IsAlive(player)
			and not S.PlayerService:HasStatus(player, "Protected")
		then
			local proot = S.PlayerService:GetRoot(player)
			if proot then
				local offset = proot.Position - root.Position
				local distance = offset.Magnitude
				if distance <= cfg.BonkRange and math.abs(offset.Y) < 6 then
					local flat = offset * Vector3.new(1, 0, 1)
					local cos = flat.Magnitude > 0.1 and look:Dot(flat.Unit) or 1
					if cos >= cosLimit or distance < 3.5 then
						local score = distance - (player == hint and 100 or 0)
						if score < bestScore then
							best, bestScore = player, score
						end
					end
				end
			end
		end
	end
	return best
end

local function onBonk(attacker: Player, hint: any)
	if not RequestRouter.consume(attacker, "Bonk", 2, 3) then
		return
	end
	local now = os.clock()
	if now - (lastBonk[attacker] or 0) < GameConfig.Combat.BonkCooldown * 0.9 then
		return
	end
	lastBonk[attacker] = now
	local root = S.PlayerService:GetRoot(attacker)
	if not root or not S.PlayerService:IsAlive(attacker) or not S.DataService:IsLoaded(attacker) then
		return
	end
	if S.PlayerService:HasStatus(attacker, "Stunned") then
		return
	end
	S.AnnouncementService:Effect("Swing", { UserId = attacker.UserId }, root.Position, 120)
	if inSafeZone(root.Position) then
		return
	end
	local hintPlayer = (typeof(hint) == "Instance" and hint:IsA("Player")) and hint or nil
	local victim = findTarget(attacker, root, hintPlayer)
	if not victim then
		return
	end
	local vroot = S.PlayerService:GetRoot(victim) :: BasePart
	if inSafeZone(vroot.Position) then
		S.AnnouncementService:Notify(attacker, "info", "No bonking in the Marketplace - it's a safe zone!")
		return
	end
	-- Home advantage: you can't be bonked inside your own vault.
	local victimPlot = S.PlotService:GetPlotIndex(victim)
	if victimPlot and S.RaidService:IsInsidePlot(victim, victimPlot) then
		S.AnnouncementService:Notify(attacker, "info", "Home advantage! You can't bonk someone inside their own vault.")
		return
	end

	local cfg = GameConfig.Combat
	local carrying = S.CarryService:Count(victim) > 0
	local attackerPlot = S.PlotService:GetPlotIndex(attacker)
	local isDefend = attackerPlot ~= nil and S.RaidService:IsIntruding(victim, attackerPlot)
	local direction = (vroot.Position - root.Position) * Vector3.new(1, 0, 1)
	direction = direction.Magnitude > 0.1 and direction.Unit or root.CFrame.LookVector

	local dropped = {}
	if carrying then
		dropped = S.CarryService:Drop(victim, 1, "bonked by " .. S.AnnouncementService.name(attacker))
		CombatService:Stun(victim, cfg.BonkStunCarrier, true)
		S.DataService:Increment(attacker, "BonkedCarriers")
	else
		S.PlayerService:SetStatus(victim, "Dazed", cfg.BonkDazeEmpty)
	end
	S.PlayerService:SetStatus(victim, "Dazed", math.max(cfg.BonkDazeEmpty, carrying and cfg.BonkStunCarrier or 0))
	knockback(victim, direction * cfg.BonkKnockback + Vector3.new(0, 22, 0))
	local vhum = S.PlayerService:GetHumanoid(victim)
	if vhum then
		vhum:TakeDamage(cfg.BonkDamage)
	end
	lastBonkedBy[victim] = { Attacker = attacker, At = now }

	S.DataService:Increment(attacker, "Bonks")
	if isDefend then
		S.DataService:Increment(attacker, "Defends")
		S.AnnouncementService:Feed(
			"🛡️",
			string.format(
				"<b>%s</b> defended their vault from <b>%s</b>!",
				S.AnnouncementService.name(attacker),
				S.AnnouncementService.name(victim)
			)
		)
	end
	local bounty = S.RaidService:ClaimBounty(victim, attacker)
	if bounty > 0 then
		S.AnnouncementService:Notify(attacker, "reward", "BOUNTY! +" .. Format.cash(bounty))
	end

	Net.event("Fail"):FireClient(
		victim,
		"Bonk",
		Tables.pickRandom(CAPTIONS.Bonk) or "BONK!",
		{ By = attacker.DisplayName, Dropped = #dropped }
	)
	S.AnnouncementService:Effect(
		"Bonk",
		{ Position = vroot.Position, Attacker = attacker.UserId, Victim = victim.UserId, Dropped = #dropped },
		vroot.Position,
		220
	)
	GameEvents.Bonked:Fire(attacker, victim, { Carrier = carrying, Defend = isDefend, Dropped = #dropped })
end

-- Lifecycle ----------------------------------------------------------------------------------

function CombatService:OnCharacterAdded(player: Player, character: Model)
	setupRagdoll(character)
	stunTokens[player] = (stunTokens[player] or 0) + 1
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		-- Funny death flop + drop EVERYTHING
		self:SetRagdoll(player, true)
		local count = S.CarryService:Count(player)
		if count > 0 then
			S.CarryService:Drop(player, nil, "knocked out")
		end
		S.DataService:Increment(player, "Deaths")
		local credit = lastBonkedBy[player]
		if credit and os.clock() - credit.At <= GameConfig.Combat.KillCreditWindow and credit.Attacker.Parent then
			S.AnnouncementService:Feed(
				"👊",
				string.format(
					"<b>%s</b> knocked out <b>%s</b>%s",
					S.AnnouncementService.name(credit.Attacker),
					S.AnnouncementService.name(player),
					count > 0 and " and scattered their loot!" or ""
				)
			)
		end
		lastBonkedBy[player] = nil
	end)
end

function CombatService:Start()
	Net.event("Bonk").OnServerEvent:Connect(onBonk)
	Players.PlayerRemoving:Connect(function(player)
		lastBonk[player] = nil
		lastBonkedBy[player] = nil
		stunTokens[player] = nil
	end)
end

return CombatService
