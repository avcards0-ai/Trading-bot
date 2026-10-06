--[[
	Inventory - your vault storage and what you're carrying.
	Select an artifact to see it in 3D, put it on display (earns income, raidable) or in
	storage (raid-proof), or sell it. Bulk-sell junk in one click.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Zones = require(Shared.Config.Zones)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)
local ArtifactViewport = require(UI.ArtifactViewport)

local C = Theme.Colors

return function(ctx)
	local shell = ctx.UI:Shell("Inventory", "Loot & Vault Storage", "🎒", C.Primary)
	local content = shell.Content
	local tab = "Vault"
	local filter = "All"
	local selected: string? = nil
	local confirmSell: string? = nil

	-- Layout: tabs + filters on top, grid left, details right
	local refresh: () -> ()
	local _, selectTab = Components.tabs(content, { "Vault", "Backpack" }, function(name)
		tab = name
		selected = nil
		if refresh then
			refresh()
		end
	end, UDim2.new(0.5, -6, 0, 40))

	local filters = Components.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, -6, 0, 40),
		Position = UDim2.new(0.5, 6, 0, 0),
		Parent = content,
	})
	Components.list(filters, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right)
	local filterButtons = {}
	local filterNames = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
	for i, name in filterNames do
		local color = name == "All" and C.PanelLighter or Theme.rarity(name)
		filterButtons[name] = Components.button({
			Text = name == "All" and "All" or string.sub(name, 1, 1),
			Color = color,
			Size = UDim2.fromOffset(38, 36),
			LayoutOrder = i,
			MaxTextSize = 16,
			Parent = filters,
			OnClick = function()
				filter = name
				refresh()
			end,
		})
	end

	local summary = Components.label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.6, 0, 0, 26),
		Position = UDim2.fromOffset(4, 46),
		MaxTextSize = 18,
		Parent = content,
	})
	local grid =
		Components.scroll({ Size = UDim2.new(0.6, -8, 1, -130), Position = UDim2.fromOffset(0, 76), Parent = content })
	Components.grid(grid, UDim2.fromOffset(78, 78), 8)
	Components.padding(grid, 4)

	-- Bulk sell row
	local bulk = Components.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.6, -8, 0, 44),
		Position = UDim2.new(0, 0, 1, -46),
		Parent = content,
	})
	Components.list(bulk, Enum.FillDirection.Horizontal, 6)
	for i, rarity in { "Common", "Uncommon", "Rare" } do
		Components.button({
			Text = "Sell all ≤ " .. rarity,
			Color = Theme.darken(Theme.rarity(rarity), 0.2),
			Size = UDim2.fromOffset(150, 40),
			LayoutOrder = i,
			MaxTextSize = 15,
			Parent = bulk,
			OnClick = function()
				ctx.Request("SellBulk", rarity)
			end,
		})
	end

	-- Detail panel
	local detail = Components.panel({
		Size = UDim2.new(0.4, -8, 1, -46),
		Position = UDim2.new(0.6, 8, 0, 46),
		BackgroundColor3 = C.Panel,
		Parent = content,
	})
	local preview =
		Components.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 170), Parent = detail })
	local nameLabel = Components.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 170),
		MaxTextSize = 24,
		Parent = detail,
	})
	Components.textStroke(nameLabel, 1.5)
	local rarityLabel = Components.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.fromOffset(10, 200),
		MaxTextSize = 18,
		Parent = detail,
	})
	local descLabel = Components.label({
		Text = "",
		Font = Theme.Fonts.Body,
		TextColor3 = C.SubText,
		TextWrapped = true,
		Size = UDim2.new(1, -20, 0, 66),
		Position = UDim2.fromOffset(10, 224),
		MaxTextSize = 15,
		Parent = detail,
	})
	local displayButton = Components.button({
		Text = "Display",
		Color = C.Accent,
		Size = UDim2.new(0.5, -15, 0, 42),
		Position = UDim2.new(0, 10, 1, -52),
		Parent = detail,
	})
	local sellButton = Components.button({
		Text = "Sell",
		Color = C.Success,
		Size = UDim2.new(0.5, -15, 0, 42),
		Position = UDim2.new(0.5, 5, 1, -52),
		Parent = detail,
	})

	local function showDetail(uid: string?, record: any?)
		preview:ClearAllChildren()
		local def = record and Artifacts.get(record.Id)
		displayButton.Visible = false
		sellButton.Visible = false
		if not def then
			nameLabel.Text = tab == "Vault" and "Select an artifact" or "Your backpack"
			rarityLabel.Text = ""
			descLabel.Text = tab == "Vault"
					and "Displayed artifacts earn cash every second but can be raided. Stored ones are safe."
				or "Loot only counts once you carry it onto the SECURE pad in your vault. Don't get bonked!"
			return
		end
		local rarity = Rarities.get(def.Rarity)
		ArtifactViewport.new(def.Id, record.M, {
			Size = UDim2.fromOffset(170, 170),
			Position = UDim2.fromScale(0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			Spin = true,
			Parent = preview,
		})
		nameLabel.Text = (record.M and (record.M .. " ") or "") .. def.Name
		rarityLabel.Text = string.format(
			"%s  ·  %s",
			string.upper(rarity.Name),
			Format.cash(Progression.artifactValue(def.Id, record.M))
		)
		rarityLabel.TextColor3 = Theme.rarity(def.Rarity)
		local zone = record.Z and Zones.get(record.Z)
		descLabel.Text = def.Desc
			.. (def.EffectDesc and ("\n✨ " .. def.EffectDesc) or "")
			.. (zone and ("\nFrom: " .. zone.Name) or "")
		if tab == "Vault" and uid then
			local data = ctx.Data.Data
			local displayed = table.find(data.Displayed or {}, uid) ~= nil
			displayButton.Visible = true
			sellButton.Visible = true
			Components.setButton(
				displayButton,
				displayed and "📦 Store" or "🏛️ Display",
				displayed and C.PanelLighter or C.Accent
			)
			local price = Progression.sellPrice(def.Id, record.M, data, 1)
			local needsConfirm = Rarities.index(def.Rarity) >= Rarities.index("Epic")
			Components.setButton(
				sellButton,
				(confirmSell == uid) and "Confirm?" or ("Sell " .. Format.cash(price)),
				(confirmSell == uid) and C.Danger or C.Success
			)
			sellButton:SetAttribute("NeedsConfirm", needsConfirm)
		end
	end

	displayButton.Activated:Connect(function()
		if not selected then
			return
		end
		local displayed = table.find(ctx.Data.Data.Displayed or {}, selected) ~= nil
		ctx.Request("SetDisplay", selected, not displayed)
	end)
	sellButton.Activated:Connect(function()
		if not selected then
			return
		end
		if sellButton:GetAttribute("NeedsConfirm") and confirmSell ~= selected then
			confirmSell = selected
			refresh()
			return
		end
		confirmSell = nil
		local response = ctx.Request("Sell", { selected })
		if response.ok then
			selected = nil
		end
	end)

	refresh = function()
		for name, button in filterButtons do
			button.BackgroundTransparency = name == filter and 0 or 0.5
		end
		for _, child in grid:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local data = ctx.Data.Data
		if not data or not data.Artifacts then
			return
		end
		local items = {}
		if tab == "Vault" then
			for uid, record in data.Artifacts do
				table.insert(items, { Uid = uid, Record = record })
			end
		else
			for _, record in ctx.Data:GetSession("Carried") or {} do
				table.insert(items, { Uid = record.Uid, Record = record })
			end
		end
		local displayedSet = {}
		for _, uid in data.Displayed or {} do
			displayedSet[uid] = true
		end
		table.sort(items, function(a, b)
			return Progression.artifactValue(a.Record.Id, a.Record.M)
				> Progression.artifactValue(b.Record.Id, b.Record.M)
		end)
		local shown = 0
		local first: GuiObject? = nil
		for _, item in items do
			local def = Artifacts.get(item.Record.Id)
			if def and (filter == "All" or def.Rarity == filter) then
				shown += 1
				local color = Theme.rarity(def.Rarity)
				local cell = Components.new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = item.Uid == selected and Theme.darken(color, 0.3) or Theme.darken(color, 0.65),
					LayoutOrder = shown,
					Parent = grid,
				})
				Components.corner(cell, UDim.new(0, 12))
				Components.stroke(cell, color, item.Uid == selected and 3 or 1.5)
				Components.label({
					Text = def.Icon,
					Size = UDim2.new(1, -10, 0.7, 0),
					Position = UDim2.fromOffset(5, 4),
					MaxTextSize = 36,
					Parent = cell,
				})
				local value = Components.label({
					Text = Format.cash(Progression.artifactValue(def.Id, item.Record.M)),
					Size = UDim2.new(1, -4, 0.26, 0),
					Position = UDim2.new(0, 2, 0.72, 0),
					MaxTextSize = 13,
					Parent = cell,
				})
				Components.textStroke(value, 1)
				if displayedSet[item.Uid] then
					Components.label({
						Text = "🏛️",
						Size = UDim2.fromOffset(20, 20),
						Position = UDim2.fromOffset(2, 2),
						MaxTextSize = 16,
						Parent = cell,
					})
				end
				if item.Record.M then
					Components.label({
						Text = item.Record.M == "Rainbow" and "🌈" or "✨",
						Size = UDim2.fromOffset(20, 20),
						Position = UDim2.new(1, -22, 0, 2),
						MaxTextSize = 16,
						Parent = cell,
					})
				end
				cell.Activated:Connect(function()
					selected = item.Uid
					if confirmSell ~= item.Uid then
						confirmSell = nil
					end
					ctx.Sound:Play("Click")
					refresh()
				end)
				first = first or cell
			end
		end
		local window = ctx.UI:GetWindow("Inventory")
		if window then
			window.FirstSelectable = first or shell.Close
		end
		if tab == "Vault" then
			summary.Text = string.format(
				"🗄️ %d/%d stored   ·   🏛️ %d/%d on display   ·   %s/s income",
				#items,
				Progression.storageSize(data),
				#(data.Displayed or {}),
				Progression.displaySlots(data),
				Format.cash(Progression.incomePerSecond(data))
			)
		else
			summary.Text = string.format("🎒 %d/%d carried", #items, Progression.capacity(data))
		end
		bulk.Visible = tab == "Vault"
		local record = nil
		if selected then
			if tab == "Vault" then
				record = data.Artifacts[selected]
			else
				for _, item in items do
					if item.Uid == selected then
						record = item.Record
					end
				end
			end
		end
		showDetail(record and selected or nil, record)
	end

	ctx.Data:ObserveMany({ "Artifacts", "Displayed", "Gear", "Perks", "Vault" }, function()
		local window = ctx.UI:GetWindow("Inventory")
		if window and window.Frame.Visible then
			refresh()
		end
	end)
	ctx.Data:ObserveSession("Carried", function()
		if tab == "Backpack" and shell.Frame.Visible then
			refresh()
		end
	end)
	selectTab("Vault")

	return {
		Name = "Inventory",
		Frame = shell.Frame,
		Close = shell.Close,
		Refresh = refresh,
	}
end
