--[[
	Collection Book - every artifact in the game. Discovered ones show in 3D, the rest are
	mysterious silhouettes. Complete a rarity set for a Gem reward.
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
	local shell = ctx.UI:Shell("Collection", "Collection Book", "📖", C.Success, UDim2.fromOffset(900, 560))
	local content = shell.Content
	local rarity = "Common"
	local selected: string? = nil
	local cells: { [string]: { Frame: TextButton, Discovered: boolean } } = {}
	local refresh: () -> ()

	local tabNames = {}
	for _, r in Rarities.List do
		table.insert(tabNames, r.Name == "SECRET" and "Secret" or r.Name)
	end
	local _, selectTab = Components.tabs(content, tabNames, function(name)
		rarity = name
		selected = nil
		if refresh then
			refresh()
		end
	end)

	local header = Components.panel({
		Size = UDim2.new(0.62, -8, 0, 54),
		Position = UDim2.fromOffset(0, 48),
		BackgroundColor3 = C.PanelLight,
		Parent = content,
	})
	local headerLabel = Components.label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -200, 1, -12),
		Position = UDim2.fromOffset(12, 6),
		MaxTextSize = 18,
		Parent = header,
	})
	Components.textStroke(headerLabel, 1.2)
	local claim = Components.button({
		Text = "",
		Color = C.Accent,
		Size = UDim2.fromOffset(180, 42),
		Position = UDim2.new(1, -188, 0.5, -21),
		MaxTextSize = 16,
		Parent = header,
	})
	claim.Activated:Connect(function()
		ctx.Request("ClaimCollection", rarity)
	end)

	local grid = Components.scroll({
		Size = UDim2.new(0.62, -8, 1, -110),
		Position = UDim2.fromOffset(0, 110),
		Parent = content,
	})
	Components.grid(grid, UDim2.fromOffset(122, 140), 8)
	Components.padding(grid, 4)

	local detail = Components.panel({
		Size = UDim2.new(0.38, -8, 1, -48),
		Position = UDim2.new(0.62, 8, 0, 48),
		BackgroundColor3 = C.Panel,
		Parent = content,
	})
	local detailView =
		Components.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 200), Parent = detail })
	local detailName = Components.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 32),
		Position = UDim2.fromOffset(10, 200),
		MaxTextSize = 24,
		Parent = detail,
	})
	Components.textStroke(detailName, 1.5)
	local detailInfo = Components.label({
		Text = "",
		Font = Theme.Fonts.Body,
		TextWrapped = true,
		TextColor3 = C.SubText,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -24, 1, -250),
		Position = UDim2.fromOffset(12, 240),
		MaxTextSize = 16,
		Parent = detail,
	})

	local function showDetail(id: string?)
		detailView:ClearAllChildren()
		local def = id and Artifacts.get(id)
		if not def then
			detailName.Text = "Pick an artifact"
			detailInfo.Text =
				"Steal and secure an artifact to add it to your collection. Silhouettes are artifacts you haven't found yet."
			return
		end
		local data = ctx.Data.Data
		local count = data.Discovered and data.Discovered[def.Id] or 0
		local found = count > 0
		ArtifactViewport.new(def.Id, nil, {
			Size = UDim2.fromOffset(200, 200),
			Position = UDim2.fromScale(0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			Silhouette = not found,
			Spin = true,
			Parent = detailView,
		})
		detailName.Text = found and def.Name or "???"
		detailName.TextColor3 = Theme.rarity(def.Rarity)
		local zoneNames = {}
		for _, zoneId in def.Zones do
			local zone = Zones.get(zoneId)
			if zone and zone.Id ~= "SecretRoom" then
				table.insert(zoneNames, zone.Icon .. " " .. zone.Name)
			elseif zoneId == "Event" then
				table.insert(zoneNames, "🎉 Server events")
			end
		end
		if found then
			detailInfo.Text = string.format(
				"%s\n\n💰 %s   ·   Found ×%d\n%s\n\nWhere: %s",
				def.Desc,
				Format.cash(def.Value),
				count,
				def.EffectDesc and ("✨ " .. def.EffectDesc) or "",
				table.concat(zoneNames, ", ")
			)
		else
			detailInfo.Text = string.format(
				"Not discovered yet.\n\n💰 Worth about %s\n\nHint: try %s",
				Format.cash(def.Value),
				def.Rarity == "Secret" and "somewhere nobody looks..." or table.concat(zoneNames, ", ")
			)
		end
	end

	refresh = function()
		local data = ctx.Data.Data
		if not data or not data.Discovered then
			return
		end
		local list = Artifacts.ByRarity[rarity] or {}
		local wanted: { [string]: boolean } = {}
		local found = 0
		for i, def in list do
			wanted[def.Id] = true
			local discovered = (data.Discovered[def.Id] or 0) > 0
			if discovered then
				found += 1
			end
			local cell = cells[def.Id]
			if cell and cell.Discovered ~= discovered then
				cell.Frame:Destroy()
				cells[def.Id] = nil
				cell = nil
			end
			if not cell then
				local color = Theme.rarity(def.Rarity)
				local button = Components.new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = Theme.darken(color, discovered and 0.6 or 0.85),
					LayoutOrder = i,
					Parent = grid,
				})
				Components.corner(button, UDim.new(0, 12))
				Components.stroke(button, discovered and color or C.Stroke, 1.5)
				ArtifactViewport.new(def.Id, nil, {
					Size = UDim2.new(1, -10, 0, 100),
					Position = UDim2.fromOffset(5, 4),
					Silhouette = not discovered,
					Parent = button,
				})
				local name = Components.label({
					Text = discovered and def.Name or "???",
					Size = UDim2.new(1, -8, 0, 28),
					Position = UDim2.new(0, 4, 1, -32),
					MaxTextSize = 14,
					Parent = button,
				})
				Components.textStroke(name, 1)
				button.Activated:Connect(function()
					selected = def.Id
					ctx.Sound:Play("Click")
					showDetail(def.Id)
				end)
				cells[def.Id] = { Frame = button, Discovered = discovered }
			end
			cells[def.Id].Frame.Visible = true
		end
		for id, cell in cells do
			cell.Frame.Visible = wanted[id] == true
		end
		local reward = Rarities.get(rarity).SetReward
		local complete = found == #list and #list > 0
		local claimed = data.CollectionClaims and data.CollectionClaims[rarity]
		headerLabel.Text = string.format(
			"%s set: %d / %d found   ·   Total score %s   ·   %d / %d overall",
			string.upper(rarity),
			found,
			#list,
			Format.abbreviate(Progression.collectionScore(data)),
			Progression.discoveredCount(data),
			#Artifacts.List
		)
		headerLabel.TextColor3 = Theme.rarity(rarity)
		if claimed then
			Components.setButton(claim, "CLAIMED ✓", C.PanelLighter, false)
		else
			Components.setButton(
				claim,
				string.format("🎁 %d 💎", reward),
				complete and C.Accent or C.PanelLighter,
				complete
			)
		end
		showDetail(selected)

		-- Menu badge: any completed-but-unclaimed set?
		local claimable = 0
		for _, rarityDef in Rarities.List do
			local rarityId = rarityDef.Id
			if not (data.CollectionClaims and data.CollectionClaims[rarityId]) then
				local all = true
				for _, def in Artifacts.ByRarity[rarityId] or {} do
					if (data.Discovered[def.Id] or 0) == 0 then
						all = false
						break
					end
				end
				if all then
					claimable += 1
				end
			end
		end
		ctx.UI:SetBadge("Collection", claimable)
	end

	ctx.Data:ObserveMany({ "Discovered", "CollectionClaims" }, function()
		if shell.Frame.Visible then
			refresh()
		end
	end)
	selectTab("Common")

	return {
		Name = "Collection",
		Frame = shell.Frame,
		Close = shell.Close,
		Refresh = refresh,
		FirstSelectable = claim,
	}
end
