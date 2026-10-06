--[[
	CarryService
	What each player is physically carrying right now (server memory only - loot is not
	yours until you SECURE it at your vault).

	  * Capacity from backpack gear + perks
	  * Carry weight slows you down (heavier rarities = slower)
	  * Visible loot sack + your best artifact floating over your head
	  * Legendary+ makes you "hot": everyone sees a beacon over you
	  * Dropping: death drops everything, bonks/traps knock out your best piece
	  * Secret artifacts apply their unique effects while carried
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Progression = require(Shared.Progression)
local ArtifactModels = require(Shared.ArtifactModels)
local Format = require(Shared.Util.Format)

local CarryService = { Name = "CarryService" }

local S: { [string]: any }

export type CarriedRecord = {
	Uid: string,
	Id: string,
	M: string?,
	Z: string?,
	Source: string, -- "World" | "Vault" | "Dropped" | "Event"
	FromUserId: number?, -- original vault owner if stolen from a player
	OriginalOwner: number?, -- whose vault it originally came from (for insurance returns)
	StolenAt: number,
}

local lastEffectTick: { [Player]: { [string]: number } } = {}

function CarryService:Init(services)
	S = services
end

local function session(player: Player)
	return S.DataService:Session(player)
end

function CarryService:Get(player: Player): { CarriedRecord }
	local sess = session(player)
	return sess and sess.Carried or {}
end

function CarryService:Count(player: Player): number
	return #self:Get(player)
end

function CarryService:Capacity(player: Player): number
	return Progression.capacity(S.DataService:Get(player))
end

function CarryService:HasRoom(player: Player): boolean
	return self:Count(player) < self:Capacity(player)
end

function CarryService:Value(player: Player): number
	local total = 0
	for _, record in self:Get(player) do
		total += Progression.artifactValue(record.Id, record.M)
	end
	return total
end

function CarryService:Weight(player: Player): number
	local total = 0
	for _, record in self:Get(player) do
		local def = Artifacts.get(record.Id)
		total += def and Rarities.get(def.Rarity).Weight or 1
	end
	return total
end

local function bestIndex(list: { CarriedRecord }): number?
	local best, bestValue = nil, -1
	for i, record in list do
		local value = Progression.artifactValue(record.Id, record.M)
		if value > bestValue then
			best, bestValue = i, value
		end
	end
	return best
end

function CarryService:Best(player: Player): CarriedRecord?
	local list = self:Get(player)
	local index = bestIndex(list)
	return index and list[index] or nil
end

-- Speed -------------------------------------------------------------------------------------

function CarryService:RefreshSpeed(player: Player)
	local humanoid = S.PlayerService:GetHumanoid(player)
	local data = S.DataService:Get(player)
	if not humanoid or not data then
		return
	end
	local cfg = GameConfig.Character
	local speed = Progression.walkSpeed(data)
	local slow = math.min(cfg.MaxCarrySlow, self:Weight(player) * cfg.CarrySlowPerWeight)
	speed *= (1 - slow)
	if S.PlayerService:HasStatus(player, "Slowed") then
		speed *= 0.8
	end
	if S.PlayerService:HasStatus(player, "Toxic") then
		speed *= 0.6
	end
	speed = math.max(cfg.MinWalkSpeed, speed)
	if S.PlayerService:HasStatus(player, "Glued") then
		speed = GameConfig.Security.GlueSpeed
	end
	if S.PlayerService:HasStatus(player, "Stunned") then
		speed = 0
	end
	if math.abs(humanoid.WalkSpeed - speed) > 0.05 then
		humanoid.WalkSpeed = speed
	end
end

-- Visuals -----------------------------------------------------------------------------------

local function clearVisuals(character: Model)
	for _, child in character:GetChildren() do
		if child.Name == "LootSack" or child.Name == "LootDisplay" then
			child:Destroy()
		end
	end
end

function CarryService:RefreshVisuals(player: Player)
	local character = player.Character
	if not character then
		return
	end
	clearVisuals(character)
	local list = self:Get(player)
	local head = character:FindFirstChild("Head") :: BasePart?
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	local best = self:Best(player)
	local hot: string? = nil
	local effects = {}
	for _, record in list do
		local def = Artifacts.get(record.Id)
		if def then
			local rarity = Rarities.get(def.Rarity)
			if rarity.Hot and (not hot or Rarities.index(def.Rarity) > Rarities.index(hot)) then
				hot = def.Rarity
			end
			if def.Effect then
				table.insert(effects, def.Effect)
			end
		end
	end
	character:SetAttribute("HotLoot", hot)
	character:SetAttribute("LootEffects", #effects > 0 and table.concat(effects, ",") or nil)
	character:SetAttribute("CarryCount", #list)

	if #list == 0 or not head or not torso then
		return
	end

	-- Sack on the back, grows with the number of items
	local sack = Instance.new("Part")
	sack.Name = "LootSack"
	sack.Shape = Enum.PartType.Ball
	local size = 1.6 + math.min(#list, 12) * 0.12
	sack.Size = Vector3.one * size
	sack.Color = Color3.fromRGB(170, 130, 80)
	sack.Material = Enum.Material.Fabric
	sack.CanCollide = false
	sack.CanQuery = false
	sack.CanTouch = false
	sack.Massless = true
	sack.CFrame = torso.CFrame * CFrame.new(0, 0.1, 0.6 + size / 2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = sack
	weld.Parent = sack
	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(46, 24)
	label.StudsOffset = Vector3.new(0, size / 2 + 0.2, 0)
	label.MaxDistance = 60
	label.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 230, 120)
	text.Text = "x" .. #list
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = text
	text.Parent = label
	label.Parent = sack
	sack.Parent = character

	-- Best artifact floats above your head for everyone to see (and chase)
	if best then
		local model = ArtifactModels.build(best.Id, best.M, { Scale = 0.75, Name = "LootDisplay" })
		model:PivotTo(head.CFrame * CFrame.new(0, 2.6, 0))
		ArtifactModels.weldToCore(model)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Massless = true
			end
		end
		local core = model.PrimaryPart :: BasePart
		local headWeld = Instance.new("WeldConstraint")
		headWeld.Part0 = head
		headWeld.Part1 = core
		headWeld.Parent = core
		model:SetAttribute("Carried", true)
		model.Parent = character
		CollectionService:AddTag(model, "Artifact")
	end
end

-- Mutations ---------------------------------------------------------------------------------

local function changed(player: Player)
	S.DataService:ReplicateSession(player, "Carried")
	CarryService:RefreshVisuals(player)
	CarryService:RefreshSpeed(player)
end

function CarryService:Add(player: Player, record: CarriedRecord): boolean
	local list = self:Get(player)
	if #list >= self:Capacity(player) then
		return false
	end
	table.insert(list, record)
	S.DataService:SetMax(player, "MaxCarried", #list)
	changed(player)
	return true
end

function CarryService:TakeAll(player: Player): { CarriedRecord }
	local sess = session(player)
	if not sess then
		return {}
	end
	local list = sess.Carried
	sess.Carried = {}
	changed(player)
	return list
end

function CarryService:TakeBest(player: Player): CarriedRecord?
	local list = self:Get(player)
	local index = bestIndex(list)
	if not index then
		return nil
	end
	local record = table.remove(list, index)
	changed(player)
	return record
end

function CarryService:TakeUid(player: Player, uid: string): CarriedRecord?
	local list = self:Get(player)
	for i, record in list do
		if record.Uid == uid then
			table.remove(list, i)
			changed(player)
			return record
		end
	end
	return nil
end

-- Drops loot into the world. `count` = number of best pieces, or nil for everything.
function CarryService:Drop(player: Player, count: number?, reason: string?): { CarriedRecord }
	local root = S.PlayerService:GetRoot(player)
	local position = root and root.Position or (S.AntiCheatService:LastSafePosition(player))
	local dropped = {}
	if count == nil then
		dropped = self:TakeAll(player)
	else
		for _ = 1, count do
			local record = self:TakeBest(player)
			if not record then
				break
			end
			table.insert(dropped, record)
		end
	end
	if #dropped == 0 or not position then
		return dropped
	end
	for _, record in dropped do
		S.ArtifactService:SpawnDropped(record, position, player)
	end
	S.DataService:Increment(player, "Drops", #dropped)
	-- Feed the dramatic ones
	local best = dropped[bestIndex(dropped) :: number]
	local def = best and Artifacts.get(best.Id)
	if def and Rarities.index(def.Rarity) >= Rarities.index("Epic") then
		local rarity = Rarities.get(def.Rarity)
		S.AnnouncementService:Feed("💥", string.format("<b>%s</b> dropped %s%s!", S.AnnouncementService.name(player), Format.rich(def.Name, rarity.Color), reason and (" (" .. reason .. ")") or ""))
	end
	return dropped
end

-- Secret artifact effects ------------------------------------------------------------------

local function effectReady(player: Player, effect: string, interval: number): boolean
	local ticks = lastEffectTick[player]
	if not ticks then
		ticks = {}
		lastEffectTick[player] = ticks
	end
	local now = os.clock()
	if now - (ticks[effect] or 0) >= interval then
		ticks[effect] = now
		return true
	end
	return false
end

local function tickEffects(player: Player)
	local root = S.PlayerService:GetRoot(player)
	local humanoid = S.PlayerService:GetHumanoid(player)
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	for _, record in CarryService:Get(player) do
		local def = Artifacts.get(record.Id)
		local effect = def and def.Effect
		if effect == "Honk" and effectReady(player, "Honk", 3.5) then
			S.AnnouncementService:Effect("Honk", { Position = root.Position, UserId = player.UserId }, root.Position, 220)
		elseif effect == "BananaTrail" and effectReady(player, "BananaTrail", 3) then
			S.SecurityService:AddTemporaryTrap("Banana", root.Position - root.CFrame.LookVector * 5 - Vector3.new(0, 2.8, 0), "Carrier:" .. player.UserId, 25)
		elseif effect == "Cookies" and effectReady(player, "Cookies", 1) then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 5)
		elseif effect == "Vacuum" and effectReady(player, "Vacuum", 0.5) then
			S.ArtifactService:Vacuum(player, root.Position, 32)
		end
	end
end

-- Lifecycle ---------------------------------------------------------------------------------

function CarryService:OnCharacterAdded(player: Player, _character: Model)
	-- A fresh character never carries anything (death already dropped it), but keep the
	-- visuals in sync just in case (e.g. LoadCharacter while carrying).
	self:RefreshVisuals(player)
	self:RefreshSpeed(player)
end

function CarryService:Start()
	S.DataService.Removing:Connect(function(player)
		local list = self:Get(player)
		if #list == 0 then
			return
		end
		if S.DataService.ShuttingDown then
			-- Server is closing: don't punish anyone mid-escape, rescue loot into the vault.
			for _, record in self:TakeAll(player) do
				S.InventoryService:AddToVault(player, record, true)
			end
		else
			self:Drop(player, nil, "left the game")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastEffectTick[player] = nil
	end)

	-- Status-driven speed refresh + secret effects
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				if S.DataService:IsLoaded(player) then
					self:RefreshSpeed(player)
					if #self:Get(player) > 0 then
						tickEffects(player)
					end
				end
			end
		end
	end)
end

return CarryService
