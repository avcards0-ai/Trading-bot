--[[
	Shop - cosmetics only. Gems (Robux or earned), VIP / Locker+ passes, trails, auras,
	vault skins, emotes, titles and saved outfits. Nothing here affects gameplay.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Config.Cosmetics)
local Monetization = require(Shared.Config.Monetization)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local TABS = { "Gems", "Passes", "Trails", "Auras", "Skins", "Emotes", "Titles", "Outfits" }
local TYPE_FOR_TAB = { Trails = "Trail", Auras = "Aura", Skins = "VaultSkin", Emotes = "Emote" }

return function(ctx)
	local shell = ctx.UI:Shell("Shop", "Drip Shop", "🛒", Color3.fromRGB(220, 90, 220), UDim2.fromOffset(900, 560))
	local content = shell.Content
	local current = "Trails"
	local prices: { [string]: number } = {}

	local balance = Components.label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(300, 34),
		Position = UDim2.new(1, -310, 0, -52),
		MaxTextSize = 22,
		TextColor3 = C.Gem,
		ZIndex = 25,
		Parent = content,
	})
	Components.textStroke(balance, 1.5)

	local refresh: () -> ()
	local _, selectTab = Components.tabs(content, TABS, function(name)
		current = name
		if refresh then
			refresh()
		end
	end)
	local note = Components.label({
		Text = "100% cosmetic - nothing here makes you stronger. Earn Gems from achievements, daily rewards and challenges too!",
		Font = Theme.Fonts.Body,
		TextColor3 = C.SubText,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 46),
		MaxTextSize = 14,
		Parent = content,
	})
	note.TextWrapped = true
	local grid =
		Components.scroll({ Size = UDim2.new(1, 0, 1, -74), Position = UDim2.fromOffset(0, 72), Parent = content })
	Components.grid(grid, UDim2.fromOffset(200, 214), 10)
	Components.padding(grid, 4)

	local function card(order: number, icon: string, title: string, desc: string, accent: Color3): (Frame, TextButton)
		local frame =
			Components.panel({ BackgroundColor3 = C.Panel, Stroke = accent, LayoutOrder = order, Parent = grid })
		Components.label({
			Text = icon,
			Size = UDim2.new(1, 0, 0, 64),
			Position = UDim2.fromOffset(0, 8),
			MaxTextSize = 52,
			Parent = frame,
		})
		local titleLabel = Components.label({
			Text = title,
			Size = UDim2.new(1, -12, 0, 26),
			Position = UDim2.fromOffset(6, 74),
			MaxTextSize = 20,
			Parent = frame,
		})
		Components.textStroke(titleLabel, 1.2)
		Components.label({
			Text = desc,
			Font = Theme.Fonts.Body,
			TextColor3 = C.SubText,
			TextWrapped = true,
			Size = UDim2.new(1, -16, 0, 50),
			Position = UDim2.fromOffset(8, 102),
			MaxTextSize = 14,
			Parent = frame,
		})
		local button = Components.button({
			Text = "",
			Color = C.Success,
			Size = UDim2.new(1, -20, 0, 42),
			Position = UDim2.new(0, 10, 1, -52),
			MaxTextSize = 18,
			Parent = frame,
		})
		return frame, button
	end

	local function owns(item: Cosmetics.Cosmetic): boolean
		local data = ctx.Data.Data
		if item.Price.Free then
			return true
		end
		if item.Price.VIP then
			return ctx.Data:GetSession("IsVIP") == true
		end
		return data.Cosmetics and data.Cosmetics.Owned[item.Id] == true
	end

	local function priceText(item: Cosmetics.Cosmetic): string
		if item.Price.Gems then
			return "💎 " .. item.Price.Gems
		elseif item.Price.Cash then
			return "💰 " .. Format.abbreviate(item.Price.Cash)
		elseif item.Price.VIP then
			return "👑 VIP"
		end
		return "Free"
	end

	refresh = function()
		for _, child in grid:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = ctx.Data.Data
		if not data or not data.Cosmetics then
			return
		end
		balance.Text = string.format("💎 %s   💰 %s", Format.abbreviate(data.Gems), Format.abbreviate(data.Cash))
		local first: GuiObject? = nil

		if current == "Gems" then
			for i, product in Monetization.Products do
				local robux = prices[product.Key] or product.PriceHint
				local _, button = card(
					i,
					"💎",
					product.Name,
					string.format(
						"%d Gems%s",
						product.Gems,
						product.Bonus > 0 and string.format(" + %d BONUS", product.Bonus) or ""
					),
					C.Gem
				)
				if product.Id == 0 then
					Components.setButton(button, "Coming soon", C.PanelLighter, false)
				else
					Components.setButton(button, "R$ " .. robux, C.Success)
					button.Activated:Connect(function()
						MarketplaceService:PromptProductPurchase(player, product.Id)
					end)
				end
				first = first or button
			end
		elseif current == "Passes" then
			local i = 0
			for key, pass in Monetization.GamePasses do
				i += 1
				local owned = (key == "VIP" and ctx.Data:GetSession("IsVIP"))
					or (key == "Locker" and ctx.Data:GetSession("HasLocker"))
				local _, button = card(i, pass.Icon, pass.Name, table.concat(pass.Perks, " · "), C.Accent)
				if owned then
					Components.setButton(button, "OWNED ✓", C.PanelLighter, false)
				elseif pass.Id == 0 then
					Components.setButton(button, "Coming soon", C.PanelLighter, false)
				else
					Components.setButton(button, "R$ " .. pass.PriceHint, C.Success)
					button.Activated:Connect(function()
						MarketplaceService:PromptGamePassPurchase(player, pass.Id)
					end)
				end
				first = first or button
			end
		elseif TYPE_FOR_TAB[current] then
			local kind = TYPE_FOR_TAB[current]
			for i, item in Cosmetics.ByType[kind] or {} do
				local accent = item.Colors[#item.Colors]
				local _, button = card(i, item.Icon, item.Name, item.Desc, accent)
				local owned = owns(item)
				if kind == "Emote" then
					local inWheel = table.find(data.Cosmetics.Emotes, item.Id) ~= nil
					if not owned then
						Components.setButton(button, priceText(item), C.Success)
						button.Activated:Connect(function()
							ctx.Request("BuyCosmetic", item.Id)
						end)
					elseif inWheel then
						Components.setButton(button, "▶ Play", C.Primary)
						button.Activated:Connect(function()
							ctx.UI:Close()
							task.defer(function()
								ctx.Controllers.CharacterController:PlayEmote(item.Id)
							end)
						end)
					else
						Components.setButton(button, "+ Add to wheel", C.Accent)
						button.Activated:Connect(function()
							ctx.Request("SetEmoteSlot", #data.Cosmetics.Emotes + 1, item.Id)
						end)
					end
				else
					local equipped = data.Cosmetics.Equipped[kind] == item.Id
					if equipped then
						Components.setButton(
							button,
							kind == "VaultSkin" and "EQUIPPED ✓" or "Unequip",
							C.PanelLighter,
							kind ~= "VaultSkin"
						)
						button.Activated:Connect(function()
							if kind ~= "VaultSkin" then
								ctx.Request("EquipCosmetic", kind, "")
							end
						end)
					elseif owned then
						Components.setButton(button, "Equip", C.Primary)
						button.Activated:Connect(function()
							ctx.Request("EquipCosmetic", kind, item.Id)
						end)
					else
						Components.setButton(
							button,
							priceText(item),
							item.Price.VIP and C.PanelLighter or C.Success,
							not item.Price.VIP
						)
						button.Activated:Connect(function()
							ctx.Request("BuyCosmetic", item.Id)
						end)
					end
				end
				first = first or button
			end
		elseif current == "Titles" then
			local titles = {}
			for title in data.Titles or {} do
				table.insert(titles, title)
			end
			table.sort(titles)
			if #titles == 0 then
				card(1, "🏷️", "No titles yet", "Unlock achievements to earn titles for your name tag!", C.Stroke)
			end
			for i, title in titles do
				local equipped = data.Cosmetics.Equipped.Title == title
				local _, button =
					card(i, "🏷️", "«" .. title .. "»", "Shows under your name for everyone to see.", C.Accent)
				Components.setButton(
					button,
					equipped and "Unequip" or "Equip",
					equipped and C.PanelLighter or C.Primary
				)
				button.Activated:Connect(function()
					ctx.Request("EquipCosmetic", "Title", equipped and "" or title)
				end)
				first = first or button
			end
		elseif current == "Outfits" then
			local locker = ctx.Data:GetSession("HasLocker") == true
			local slots = locker and Cosmetics.LockerLoadouts or Cosmetics.DefaultLoadouts
			for i = 1, Cosmetics.LockerLoadouts do
				local saved = data.Cosmetics.Loadouts[tostring(i)]
				local unlocked = i <= slots
				local desc = "Empty slot"
				if saved then
					local parts = {}
					for _, key in { "Trail", "Aura", "VaultSkin" } do
						local item = Cosmetics.ById[saved[key] or ""]
						if item then
							table.insert(parts, item.Icon .. " " .. item.Name)
						end
					end
					desc = #parts > 0 and table.concat(parts, " · ") or "Default look"
				end
				if not unlocked then
					desc = "🔒 Cosmetic Locker+ pass"
				end
				local frame, button =
					card(i, unlocked and "👕" or "🔒", "Outfit " .. i, desc, unlocked and C.Primary or C.Stroke)
				if not unlocked then
					Components.setButton(button, "Locked", C.PanelLighter, false)
				else
					Components.setButton(button, "💾 Save", C.Accent)
					button.Size = UDim2.new(0.5, -14, 0, 42)
					button.Activated:Connect(function()
						ctx.Request("SaveLoadout", i)
					end)
					local apply = Components.button({
						Text = "Wear",
						Color = saved and C.Success or C.PanelLighter,
						Size = UDim2.new(0.5, -14, 0, 42),
						Position = UDim2.new(0.5, 4, 1, -52),
						MaxTextSize = 18,
						Parent = frame,
					})
					Components.setButton(apply, nil, nil, saved ~= nil)
					apply.Activated:Connect(function()
						ctx.Request("ApplyLoadout", i)
					end)
				end
				first = first or button
			end
		end
		local window = ctx.UI:GetWindow("Shop")
		if window then
			window.FirstSelectable = first or shell.Close
		end
	end

	ctx.Data:ObserveMany({ "Cosmetics", "Gems", "Cash", "Titles" }, function()
		if shell.Frame.Visible then
			refresh()
		end
	end)
	ctx.Data:ObserveSession("IsVIP", function()
		if shell.Frame.Visible then
			refresh()
		end
	end)
	selectTab("Trails")

	return {
		Name = "Shop",
		Frame = shell.Frame,
		Close = shell.Close,
		Refresh = refresh,
		OnOpen = function()
			if next(prices) == nil then
				local response = ctx.Net.request("ProductInfo")
				if response.ok and type(response.data) == "table" then
					prices = response.data
				end
			end
		end,
	}
end
