--[[
	ShopService
	Cosmetic purchases (Gems / Cash), equipping, emote wheel slots, outfit loadouts,
	Game Passes and Robux Developer Products.

	Fair-play rule: the only things Robux can buy are Gems (cosmetic currency), the VIP pass
	(cosmetics + name tag) and the Cosmetic Locker+ pass (more loadout / emote slots).
	Nothing in this file grants Cash, XP, artifacts, upgrades or anything with a gameplay
	effect for Robux.

	Receipts: a purchase is recorded in the player's data and saved BEFORE we tell Roblox
	it was granted, so a crash can never lose (or double-grant) a purchase.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Config.Cosmetics)
local Monetization = require(Shared.Config.Monetization)

local RequestRouter = require(script.Parent.Parent.RequestRouter)
local V = RequestRouter.V

local ShopService = { Name = "ShopService" }

local S: { [string]: any }

local MAX_RECEIPTS = 200
local SLOTS = { Trail = true, Aura = true, VaultSkin = true, Title = true }

function ShopService:Init(services)
	S = services
end

local function isVIP(player: Player): boolean
	local session = S.DataService:Session(player)
	return session ~= nil and session.IsVIP == true
end

local function hasLocker(player: Player): boolean
	local session = S.DataService:Session(player)
	return session ~= nil and session.HasLocker == true
end

function ShopService:Owns(player: Player, item: Cosmetics.Cosmetic): boolean
	local data = S.DataService:Get(player)
	if not data then
		return false
	end
	if item.Price.Free then
		return true
	end
	if item.Price.VIP then
		return isVIP(player)
	end
	return data.Cosmetics.Owned[item.Id] == true
end

local function refreshVisuals(player: Player, slot: string)
	if slot == "VaultSkin" then
		S.PlotService:RefreshDisplay(player)
	elseif slot == "Title" then
		S.PlayerService:RefreshNameTag(player)
	else
		S.CosmeticService:ApplyCharacter(player)
	end
end

-- Game passes ------------------------------------------------------------------------------

local function checkPass(player: Player, key: string): boolean
	local pass = Monetization.GamePasses[key]
	if not pass or pass.Id == 0 then
		return false
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
	return ok and owns == true
end

local function applyPasses(player: Player)
	local vip = checkPass(player, "VIP")
	local locker = checkPass(player, "Locker")
	S.DataService:SetSession(player, "IsVIP", vip)
	S.DataService:SetSession(player, "HasLocker", locker)
	local data = S.DataService:Get(player)
	if data then
		if vip then
			data.Titles["VIP"] = true
			S.DataService:MarkChanged(player, "Titles")
		end
		-- If VIP was refunded, unequip VIP-only cosmetics.
		if not vip then
			for slot, id in data.Cosmetics.Equipped do
				local item = Cosmetics.ById[id]
				if item and item.Price.VIP then
					data.Cosmetics.Equipped[slot] = slot == "VaultSkin" and "skin_default" or ""
				end
			end
			if data.Cosmetics.Equipped.Title == "VIP" then
				data.Cosmetics.Equipped.Title = ""
			end
			S.DataService:MarkChanged(player, "Cosmetics")
		end
	end
	S.PlayerService:RefreshNameTag(player)
	S.CosmeticService:ApplyCharacter(player)
end

-- Developer products --------------------------------------------------------------------------

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = S.DataService:WaitForData(player, 15)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if not data.Receipts[purchaseId] then
		local product = Monetization.ProductById[receipt.ProductId]
		if not product then
			warn("[Shop] Unknown product id", receipt.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local total = product.Gems + product.Bonus
		data.Gems += total
		data.Receipts[purchaseId] = os.time()
		-- Keep the receipt log bounded
		local count = 0
		local oldestId, oldestTime = nil, math.huge
		for id, at in data.Receipts do
			count += 1
			if at < oldestTime then
				oldestId, oldestTime = id, at
			end
		end
		if count > MAX_RECEIPTS and oldestId and oldestId ~= purchaseId then
			data.Receipts[oldestId] = nil
		end
		S.DataService:MarkChanged(player, "Gems")
		S.AnnouncementService:Notify(player, "reward", string.format("Thank you! +%d 💎 Gems", total), { Big = true })
		S.AnnouncementService:Effect("Purchase", { UserId = player.UserId }, nil)
	end
	if not S.DataService:SaveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Start ------------------------------------------------------------------------------------------

function ShopService:Start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			for _, pass in Monetization.GamePasses do
				if pass.Id == passId then
					S.AnnouncementService:Notify(
						player,
						"reward",
						"Thanks for buying " .. pass.Name .. "! Enjoy your perks.",
						{ Big = true }
					)
					S.AnnouncementService:Feed(
						"👑",
						string.format("<b>%s</b> just got <b>%s</b>!", S.AnnouncementService.name(player), pass.Name)
					)
				end
			end
			task.defer(applyPasses, player)
		end
	end)

	S.DataService.Loaded:Connect(function(player)
		task.spawn(applyPasses, player)
	end)

	RequestRouter.register("BuyCosmetic", { Rate = 3, Burst = 5, Validate = V.args(V.str(40)) }, function(player, id)
		local item = Cosmetics.ById[id]
		local data = S.DataService:Get(player)
		if not item or not data then
			return false, "Unknown item"
		end
		if self:Owns(player, item) then
			return false, "You already own this!"
		end
		if item.Price.VIP then
			return false, "Get the VIP pass to unlock this!"
		end
		if item.Price.Gems then
			if not S.EconomyService:SpendGems(player, item.Price.Gems) then
				return false, "Not enough Gems"
			end
		elseif item.Price.Cash then
			if not S.EconomyService:SpendCash(player, item.Price.Cash) then
				return false, "Not enough Cash"
			end
		else
			return false, "Not for sale"
		end
		data.Cosmetics.Owned[item.Id] = true
		-- Auto-equip what you just bought (emotes go to the first free wheel slot).
		if item.Type == "Emote" then
			local max = hasLocker(player) and Cosmetics.LockerEmoteSlots or Cosmetics.DefaultEmoteSlots
			if #data.Cosmetics.Emotes < max then
				table.insert(data.Cosmetics.Emotes, item.Id)
			end
		else
			data.Cosmetics.Equipped[item.Type] = item.Id
			refreshVisuals(player, item.Type)
		end
		S.DataService:MarkChanged(player, "Cosmetics")
		return true, "Unlocked " .. item.Name .. "!"
	end)

	RequestRouter.register("EquipCosmetic", {
		Rate = 5,
		Burst = 8,
		Validate = V.args(
			V.str(16),
			V.optional(function(v)
				return type(v) == "string" and #v <= 40
			end)
		),
	}, function(player, slot, id)
		local data = S.DataService:Get(player)
		if not data or not SLOTS[slot] then
			return false, "Invalid slot"
		end
		id = id or ""
		if slot == "Title" then
			if id ~= "" and not data.Titles[id] then
				return false, "You haven't earned that title"
			end
			if id == "VIP" and not isVIP(player) then
				return false, "VIP only"
			end
		elseif id ~= "" then
			local item = Cosmetics.ById[id]
			if not item or item.Type ~= slot then
				return false, "Wrong item for that slot"
			end
			if not self:Owns(player, item) then
				return false, "You don't own that yet"
			end
		end
		if slot == "VaultSkin" and id == "" then
			id = "skin_default"
		end
		data.Cosmetics.Equipped[slot] = id
		S.DataService:MarkChanged(player, "Cosmetics")
		refreshVisuals(player, slot)
		return true
	end)

	RequestRouter.register(
		"SetEmoteSlot",
		{ Rate = 5, Burst = 8, Validate = V.args(V.int(1, 8), V.str(40)) },
		function(player, slot, id)
			local data = S.DataService:Get(player)
			local item = Cosmetics.ById[id]
			if not data or not item or item.Type ~= "Emote" then
				return false, "Unknown emote"
			end
			local max = hasLocker(player) and Cosmetics.LockerEmoteSlots or Cosmetics.DefaultEmoteSlots
			if slot > max then
				return false, "Cosmetic Locker+ unlocks more emote slots"
			end
			if not self:Owns(player, item) then
				return false, "You don't own that emote"
			end
			local emotes = data.Cosmetics.Emotes
			local existing = table.find(emotes, id)
			if existing then
				table.remove(emotes, existing)
			end
			table.insert(emotes, math.min(slot, #emotes + 1), id)
			while #emotes > max do
				table.remove(emotes)
			end
			S.DataService:MarkChanged(player, "Cosmetics")
			return true
		end
	)

	RequestRouter.register(
		"SaveLoadout",
		{ Rate = 2, Burst = 4, Validate = V.args(V.int(1, 8)) },
		function(player, index)
			local data = S.DataService:Get(player)
			local max = hasLocker(player) and Cosmetics.LockerLoadouts or Cosmetics.DefaultLoadouts
			if not data then
				return false
			end
			if index > max then
				return false, "Cosmetic Locker+ unlocks more loadout slots"
			end
			local equipped = data.Cosmetics.Equipped
			data.Cosmetics.Loadouts[tostring(index)] = {
				Trail = equipped.Trail,
				Aura = equipped.Aura,
				VaultSkin = equipped.VaultSkin,
				Title = equipped.Title,
				Emotes = table.clone(data.Cosmetics.Emotes),
			}
			S.DataService:MarkChanged(player, "Cosmetics")
			return true, "Outfit saved to slot " .. index
		end
	)

	RequestRouter.register(
		"ApplyLoadout",
		{ Rate = 2, Burst = 4, Validate = V.args(V.int(1, 8)) },
		function(player, index)
			local data = S.DataService:Get(player)
			local loadout = data and data.Cosmetics.Loadouts[tostring(index)]
			if not loadout then
				return false, "That slot is empty"
			end
			for _, slot in { "Trail", "Aura", "VaultSkin" } do
				local item = Cosmetics.ById[loadout[slot] or ""]
				if item == nil or self:Owns(player, item) then
					data.Cosmetics.Equipped[slot] = loadout[slot] or (slot == "VaultSkin" and "skin_default" or "")
				end
			end
			if loadout.Title == "" or data.Titles[loadout.Title] then
				data.Cosmetics.Equipped.Title = loadout.Title or ""
			end
			local emotes = {}
			for _, id in loadout.Emotes or {} do
				local item = Cosmetics.ById[id]
				if item and self:Owns(player, item) then
					table.insert(emotes, id)
				end
			end
			data.Cosmetics.Emotes = emotes
			S.DataService:MarkChanged(player, "Cosmetics")
			S.CosmeticService:ApplyCharacter(player)
			S.PlotService:RefreshDisplay(player)
			S.PlayerService:RefreshNameTag(player)
			return true, "Outfit applied!"
		end
	)

	RequestRouter.register("ProductInfo", { Rate = 1, Burst = 2 }, function()
		-- Real prices for the shop UI (falls back to the PriceHint in config).
		local info = {}
		for _, product in Monetization.Products do
			if product.Id ~= 0 then
				local ok, result =
					pcall(MarketplaceService.GetProductInfo, MarketplaceService, product.Id, Enum.InfoType.Product)
				if ok and result then
					info[product.Key] = result.PriceInRobux
				end
			end
		end
		return true, nil, info
	end)
end

return ShopService
