--[[
	ArtifactService
	Every artifact that physically exists in the world and can be stolen:
	  * World spawns at randomized zone spawn points (rarity odds per zone, mutations)
	  * Dropped loot (from bonks, traps, deaths) - scramble for it! Unclaimed drops are
	    returned to their original vault owner ("insurance") or vanish
	  * Event loot (Artifact Rain, Meteor)
	  * Vault displays on player pedestals (raidable)

	Stealing is a hold-ProximityPrompt validated by PromptGuard (hold time, distance,
	alive) plus capacity/raid rules here on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Zones = require(Shared.Config.Zones)
local Progression = require(Shared.Progression)
local ArtifactModels = require(Shared.ArtifactModels)
local Tables = require(Shared.Util.Tables)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local GameEvents = require(script.Parent.Parent.GameEvents)
local PromptGuard = require(script.Parent.Parent.PromptGuard)

local ArtifactService = { Name = "ArtifactService" }

local S: { [string]: any }

type Loose = {
	Uid: string,
	Id: string,
	M: string?,
	Zone: string,
	Source: string,
	Model: Model,
	Prompt: ProximityPrompt,
	Slot: any?,
	ExpiresAt: number?,
	FromUserId: number?,
	OriginalOwner: number?,
	PlotIndex: number?,
	Hold: number, -- base hold seconds before the player's own multiplier
}

type Slot = { CFrame: CFrame, Zone: string, Uid: string?, ReadyAt: number }

local loose: { [string]: Loose } = {}
local slotsByZone: { [string]: { Slot } } = {}
local folder: Folder
local rng = Random.new()

function ArtifactService:Init(services)
	S = services
end

-- Rolling ------------------------------------------------------------------------------------

function ArtifactService:RollMutation(): string?
	local roll = rng:NextNumber()
	if roll < GameConfig.Mutations.Rainbow.Chance then
		return "Rainbow"
	elseif roll < GameConfig.Mutations.Rainbow.Chance + GameConfig.Mutations.Shiny.Chance then
		return "Shiny"
	end
	return nil
end

function ArtifactService:RollArtifact(zoneId: string, weights: { [string]: number }): (string?, string?)
	local rarity = Tables.weightedPick(weights, rng)
	if not rarity then
		return nil, nil
	end
	local pool = Artifacts.pool(zoneId, rarity)
	local def = Tables.pickRandom(pool, rng)
	return def and def.Id, rarity
end

-- Model + prompt -----------------------------------------------------------------------------

local function zoneHoldMultiplier(zoneId: string): number
	local zone = Zones.get(zoneId)
	return zone and zone.HoldMultiplier or 1
end

local function create(entry: {
	Uid: string,
	Id: string,
	M: string?,
	Zone: string,
	Source: string,
	CFrame: CFrame,
	Hold: number,
	Scale: number?,
	FromUserId: number?,
	OriginalOwner: number?,
	PlotIndex: number?,
	ExpiresAt: number?,
	Slot: Slot?,
	DropFrom: Vector3?,
}): Loose?
	local def = Artifacts.get(entry.Id)
	if not def then
		return nil
	end
	local model = ArtifactModels.build(entry.Id, entry.M, { Scale = entry.Scale })
	model.Name = def.Name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:PivotTo(entry.CFrame)
	model:SetAttribute("Uid", entry.Uid)
	model:SetAttribute("Zone", entry.Zone)
	model:SetAttribute("Source", entry.Source)
	model:SetAttribute("Value", Progression.artifactValue(entry.Id, entry.M))
	model:SetAttribute("BaseCFrame", entry.CFrame)
	model:SetAttribute("SpawnedAt", workspace:GetServerTimeNow())
	if entry.PlotIndex then
		model:SetAttribute("PlotIndex", entry.PlotIndex)
	end
	if entry.FromUserId and entry.Source == "Vault" then
		model:SetAttribute("OwnerUserId", entry.FromUserId)
	end
	if entry.OriginalOwner then
		model:SetAttribute("OriginalOwner", entry.OriginalOwner)
	end
	if entry.ExpiresAt then
		model:SetAttribute("ExpiresAt", workspace:GetServerTimeNow() + (entry.ExpiresAt - os.clock()))
	end
	if entry.DropFrom then
		model:SetAttribute("DropFrom", entry.DropFrom)
	end

	local core = model.PrimaryPart :: BasePart
	core.CanQuery = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = entry.Source == "Vault" and "Raid" or "Steal"
	prompt.ObjectText =
		string.format("%s%s (%s)", entry.M and (entry.M .. " ") or "", def.Name, Rarities.get(def.Rarity).Name)
	prompt.HoldDuration = entry.Hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt:SetAttribute("Steal", true)
	prompt:SetAttribute("BaseHold", entry.Hold)
	prompt.Parent = core
	PromptGuard.watch(prompt)

	local record: Loose = {
		Uid = entry.Uid,
		Id = entry.Id,
		M = entry.M,
		Zone = entry.Zone,
		Source = entry.Source,
		Model = model,
		Prompt = prompt,
		Slot = entry.Slot,
		ExpiresAt = entry.ExpiresAt,
		FromUserId = entry.FromUserId,
		OriginalOwner = entry.OriginalOwner,
		PlotIndex = entry.PlotIndex,
		Hold = entry.Hold,
	}
	loose[entry.Uid] = record

	prompt.Triggered:Connect(function(player)
		ArtifactService:TrySteal(player, entry.Uid)
	end)

	model.Parent = folder
	CollectionService:AddTag(model, "Artifact")
	return record
end

local function destroy(record: Loose)
	loose[record.Uid] = nil
	PromptGuard.forget(record.Prompt)
	record.Model:Destroy()
	if record.Slot then
		local zone = Zones.get(record.Slot.Zone)
		local respawn = zone and zone.Respawn or { 15, 25 }
		record.Slot.Uid = nil
		record.Slot.ReadyAt = os.clock() + rng:NextNumber(respawn[1], respawn[2])
	end
end

-- Stealing -----------------------------------------------------------------------------------

local function announceSteal(player: Player, record: Loose, def: any)
	local rarity = Rarities.get(def.Rarity)
	local zone = Zones.get(record.Zone)
	local zoneName = zone and zone.Name or (record.Source == "Vault" and "a player's vault" or "the streets")
	local name = S.AnnouncementService.name(player)
	local label = (record.M and (record.M .. " ") or "") .. def.Name
	if rarity.Announce == "Global" or record.M == "Rainbow" then
		S.AnnouncementService:Global({
			Kind = "Steal",
			PlayerName = player.DisplayName,
			ArtifactId = def.Id,
			Rarity = def.Rarity,
			Mutation = record.M,
			ZoneName = zoneName,
		})
		S.AnnouncementService:Feed(
			rarity.Index >= 6 and "🌟" or "💎",
			string.format(
				"<b>%s</b> stole %s from %s!",
				name,
				Format.rich(label, Rarities.textColor(def.Rarity)),
				zoneName
			),
			nil,
			true
		)
	elseif rarity.Announce == "Server" then
		S.AnnouncementService:Feed(
			"💎",
			string.format("<b>%s</b> stole %s from %s", name, Format.rich(label, rarity.Color), zoneName)
		)
	end
end

-- Moves a loose artifact into a player's backpack without hold checks (vacuum etc.).
local function take(player: Player, record: Loose)
	local def = Artifacts.get(record.Id)
	if not def then
		return
	end
	local position = record.Model:GetPivot().Position

	-- Your own dropped loot comes straight home ("Recovered!").
	if record.OriginalOwner == player.UserId and record.Source == "Dropped" then
		destroy(record)
		S.InventoryService:AddToVault(
			player,
			{ Uid = record.Uid, Id = record.Id, M = record.M, Z = record.Zone },
			false
		)
		S.InventoryService:AutoDisplay(player, { record.Uid })
		S.PlotService:RefreshDisplay(player)
		S.AnnouncementService:Notify(
			player,
			"success",
			"RECOVERED! " .. def.Name .. " is back in your vault.",
			{ Big = true }
		)
		S.AnnouncementService:Effect("Recover", { Position = position, ArtifactId = record.Id }, position, 200)
		return
	end

	local ownerPlayer: Player? = nil
	if record.Source == "Vault" and record.FromUserId then
		ownerPlayer = Players:GetPlayerByUserId(record.FromUserId)
		if not ownerPlayer then
			return
		end
		-- The artifact leaves the victim's saved data right now.
		if not S.InventoryService:RemoveFromVault(ownerPlayer, record.Uid) then
			destroy(record)
			return
		end
	end

	destroy(record)
	S.CarryService:Add(player, {
		Uid = record.Uid,
		Id = record.Id,
		M = record.M,
		Z = record.Zone,
		Source = record.Source == "Dropped" and (record.FromUserId and "Vault" or "Dropped") or record.Source,
		FromUserId = record.FromUserId,
		OriginalOwner = record.OriginalOwner or (record.Source == "Vault" and record.FromUserId or nil),
		StolenAt = os.clock(),
	})
	S.DataService:Increment(player, "Steals")
	S.PlayerService:UpdateLeaderstats(player)

	local value = Progression.artifactValue(record.Id, record.M)
	GameEvents.ArtifactStolen:Fire(player, {
		Uid = record.Uid,
		Id = record.Id,
		Rarity = def.Rarity,
		Mutation = record.M,
		Zone = record.Zone,
		Source = record.Source,
		Value = value,
		VictimUserId = ownerPlayer and ownerPlayer.UserId or nil,
	})

	-- VFX: everyone nearby sees the grab; the thief gets a cinematic for rare stuff.
	S.AnnouncementService:Effect("Steal", {
		Position = position,
		ArtifactId = record.Id,
		Rarity = def.Rarity,
		Mutation = record.M,
		UserId = player.UserId,
	}, position, 350)
	if Rarities.index(def.Rarity) >= Rarities.index("Epic") or record.M == "Rainbow" then
		Net.event("Cinematic"):FireClient(player, {
			ArtifactId = record.Id,
			Rarity = def.Rarity,
			Mutation = record.M,
			Value = value,
			Raid = record.Source == "Vault",
		})
	end
	announceSteal(player, record, def)

	if ownerPlayer then
		S.RaidService:OnVaultArtifactStolen(player, ownerPlayer, record.Id, record.M)
	end

	-- Zone alarm for valuable steals in guarded zones
	local zone = Zones.get(record.Zone)
	if zone and zone.AlarmMinRarity and Rarities.atLeast(def.Rarity, zone.AlarmMinRarity) then
		S.SecurityService:TriggerZoneAlarm(zone.Id, player)
	end
	S.EventService:OnSteal(player)
end

function ArtifactService:TrySteal(player: Player, uid: string)
	local record = loose[uid]
	local data = S.DataService:Get(player)
	if not record or not data then
		return
	end
	local root = PromptGuard.rootPart(player)
	if not root then
		return
	end
	if S.PlayerService:HasStatus(player, "Stunned") then
		return
	end
	local def = Artifacts.get(record.Id)
	if not def then
		return
	end
	local expected = record.Hold * Progression.holdMultiplier(data)
	if not PromptGuard.validate(player, record.Prompt, expected) then
		return
	end

	if record.Source == "Vault" then
		local ok, msg = S.RaidService:CanStealFromPlot(player, record.PlotIndex, record.FromUserId)
		if not ok then
			if msg then
				S.AnnouncementService:Notify(player, "error", msg)
			end
			return
		end
	end

	local isOwnDrop = record.OriginalOwner == player.UserId and record.Source == "Dropped"
	if not isOwnDrop and not S.CarryService:HasRoom(player) then
		S.AnnouncementService:Notify(player, "error", "Backpack full! Secure your loot at your vault first.")
		return
	end
	take(player, record)
end

-- Spawning -----------------------------------------------------------------------------------

function ArtifactService:SpawnInSlot(slot: Slot, weights: { [string]: number }): Loose?
	local id, rarity = self:RollArtifact(slot.Zone, weights)
	if not id or not rarity then
		return nil
	end
	local uid = S.DataService:GenerateUid()
	local mutation = self:RollMutation()
	local record = create({
		Uid = uid,
		Id = id,
		M = mutation,
		Zone = slot.Zone,
		Source = "World",
		CFrame = slot.CFrame,
		Hold = Rarities.get(rarity).HoldTime * zoneHoldMultiplier(slot.Zone),
		Slot = slot,
	})
	if record then
		slot.Uid = uid
	end
	return record
end

-- Loot dropped by a player. Scatters around `position` and stays for a while.
function ArtifactService:SpawnDropped(carried: any, position: Vector3)
	local def = Artifacts.get(carried.Id)
	if not def then
		return
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(2, GameConfig.Carry.DropScatter)
	local target = position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(target + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), params)
	local ground = hit and hit.Position or Vector3.new(target.X, position.Y - 3, target.Z)
	local lifetime = GameConfig.Carry.DroppedLifetime
	create({
		Uid = carried.Uid,
		Id = carried.Id,
		M = carried.M,
		Zone = carried.Z or "Event",
		Source = "Dropped",
		CFrame = CFrame.new(ground + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
		Hold = Rarities.get(def.Rarity).HoldTime * 0.5,
		FromUserId = carried.FromUserId,
		OriginalOwner = carried.OriginalOwner,
		ExpiresAt = os.clock() + lifetime,
		DropFrom = position,
	})
end

-- Event loot (Artifact Rain / Meteor). Returns the uid.
function ArtifactService:SpawnEvent(
	cframe: CFrame,
	weights: { [string]: number },
	lifetime: number,
	fallFrom: Vector3?
): string?
	local id, rarity = self:RollArtifact("Event", weights)
	if not id or not rarity then
		return nil
	end
	local uid = S.DataService:GenerateUid()
	create({
		Uid = uid,
		Id = id,
		M = self:RollMutation(),
		Zone = "Event",
		Source = "Event",
		CFrame = cframe,
		Hold = Rarities.get(rarity).HoldTime,
		ExpiresAt = os.clock() + lifetime,
		DropFrom = fallFrom,
	})
	return uid
end

-- Vault displays --------------------------------------------------------------------------

function ArtifactService:CreateDisplay(
	plotIndex: number,
	owner: Player,
	uid: string,
	data: { Id: string, M: string? },
	cframe: CFrame
)
	local def = Artifacts.get(data.Id)
	if not def then
		return
	end
	create({
		Uid = uid,
		Id = data.Id,
		M = data.M,
		Zone = "Plot",
		Source = "Vault",
		CFrame = cframe,
		Scale = 0.9,
		Hold = Rarities.get(def.Rarity).HoldTime * GameConfig.Raid.PedestalHoldMultiplier,
		FromUserId = owner.UserId,
		PlotIndex = plotIndex,
	})
end

function ArtifactService:RemoveDisplay(uid: string)
	local record = loose[uid]
	if record and record.Source == "Vault" then
		destroy(record)
	end
end

function ArtifactService:GetLoose(uid: string)
	return loose[uid]
end

-- Void Egg: pulls nearby dropped / event loot into the carrier's backpack.
function ArtifactService:Vacuum(player: Player, position: Vector3, radius: number)
	local root = PromptGuard.rootPart(player)
	if not root then
		return
	end
	for _, record in loose do
		if (record.Source == "Dropped" or record.Source == "Event") and S.CarryService:HasRoom(player) then
			if (record.Model:GetPivot().Position - position).Magnitude <= radius then
				take(player, record)
			end
		end
	end
end

function ArtifactService:Start()
	folder = Instance.new("Folder")
	folder.Name = "Artifacts"
	folder.Parent = workspace

	-- Build spawn slots from the map
	local map = S.MapService:Get()
	for zoneId, zoneData in map.Zones do
		local slots = {}
		for _, cf in zoneData.Spawns do
			table.insert(slots, { CFrame = cf, Zone = zoneId, Uid = nil, ReadyAt = 0 })
		end
		slotsByZone[zoneId] = slots
	end

	-- Keep each zone stocked
	task.spawn(function()
		while true do
			local now = os.clock()
			for zoneId, slots in slotsByZone do
				local zone = Zones.get(zoneId)
				if zone then
					local active = 0
					local free = {}
					for _, slot in slots do
						if slot.Uid then
							active += 1
						elseif slot.ReadyAt <= now then
							table.insert(free, slot)
						end
					end
					Tables.shuffle(free, rng)
					local i = 1
					while active < zone.MaxActive and free[i] do
						if self:SpawnInSlot(free[i], zone.RarityWeights) then
							active += 1
						end
						i += 1
					end
				end
			end
			-- Expire dropped / event loot
			for _, record in loose do
				if record.ExpiresAt and record.ExpiresAt <= now then
					local owner = record.OriginalOwner and Players:GetPlayerByUserId(record.OriginalOwner)
					local def = Artifacts.get(record.Id)
					destroy(record)
					if owner and def and S.DataService:IsLoaded(owner) then
						S.InventoryService:AddToVault(
							owner,
							{ Uid = record.Uid, Id = record.Id, M = record.M, Z = record.Zone },
							true
						)
						S.InventoryService:AutoDisplay(owner, { record.Uid })
						S.PlotService:RefreshDisplay(owner)
						S.AnnouncementService:Notify(
							owner,
							"info",
							"🛡️ Insurance returned your " .. def.Name .. " to your vault!"
						)
					end
				end
			end
			task.wait(1)
		end
	end)
end

return ArtifactService
