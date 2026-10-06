--[[
	Upgrades - Gear (backpack, sneakers, gloves), Rebirth and permanent Perks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Upgrades = require(Shared.Config.Upgrades)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)
local UpgradeRows = require(UI.UpgradeRows)

local C = Theme.Colors

return function(ctx)
	local shell = ctx.UI:Shell("Upgrades", "Upgrades & Prestige", "⚡", C.XP)
	local content = shell.Content
	local pages: { [string]: Frame } = {}

	local _, selectTab = Components.tabs(content, { "Gear", "Rebirth", "Perks" }, function(name)
		for pageName, page in pages do
			page.Visible = pageName == name
		end
	end)

	local function page(name: string): ScrollingFrame
		local frame = Components.scroll({
			Name = name,
			Size = UDim2.new(1, 0, 1, -50),
			Position = UDim2.fromOffset(0, 50),
			Parent = content,
		})
		Components.list(frame, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
		Components.padding(frame, 4)
		pages[name] = frame :: any
		return frame
	end

	-- Gear ------------------------------------------------------------------------------------
	local gearPage = page("Gear")
	Components.label({
		Text = "Gear resets when you rebirth. Your vault, artifacts, cosmetics and security stay forever.",
		Font = Theme.Fonts.Body,
		TextColor3 = C.SubText,
		Size = UDim2.new(1, -8, 0, 22),
		LayoutOrder = 0,
		MaxTextSize = 15,
		Parent = gearPage,
	})
	local gearRows = {}
	for i, track in Upgrades.Gear do
		gearRows[track.Id] = UpgradeRows.trackRow(gearPage, i, track, function()
			ctx.Request("BuyGear", track.Id)
		end)
	end

	-- Rebirth ----------------------------------------------------------------------------------
	local rebirthPage = page("Rebirth")
	local card = Components.panel({
		Size = UDim2.new(1, -8, 0, 330),
		BackgroundColor3 = C.Panel,
		Stroke = C.Accent,
		LayoutOrder = 1,
		Parent = rebirthPage,
	})
	local rankLabel = Components.label({
		Text = "",
		Font = Theme.Fonts.Title,
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.fromOffset(10, 8),
		MaxTextSize = 34,
		Parent = card,
	})
	Components.textStroke(rankLabel, 2)
	local info = Components.label({
		Text = "",
		Font = Theme.Fonts.Body,
		TextWrapped = true,
		TextColor3 = C.SubText,
		Size = UDim2.new(1, -40, 0, 70),
		Position = UDim2.fromOffset(20, 56),
		MaxTextSize = 16,
		Parent = card,
	})
	local _, setLevel = Components.progress(
		card,
		{ Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 134), Color = C.XP, TextSize = 16 }
	)
	local _, setCash = Components.progress(
		card,
		{ Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 168), Color = C.Cash, TextSize = 16 }
	)
	local rewardLabel = Components.label({
		Text = "",
		Size = UDim2.new(1, -40, 0, 50),
		Position = UDim2.fromOffset(20, 204),
		MaxTextSize = 20,
		TextColor3 = C.Accent,
		Parent = card,
	})
	Components.textStroke(rewardLabel, 1.5)
	local rebirthButton = Components.button({
		Text = "🔄 REBIRTH",
		Color = C.Accent,
		TextColor = Color3.fromRGB(50, 30, 0),
		Size = UDim2.fromOffset(260, 56),
		Position = UDim2.new(0.5, -130, 1, -70),
		MaxTextSize = 28,
		Parent = card,
	})
	local confirm = false
	rebirthButton.Activated:Connect(function()
		if not confirm then
			confirm = true
			Components.setButton(rebirthButton, "ARE YOU SURE?", C.Danger)
			task.delay(3, function()
				confirm = false
				Components.setButton(rebirthButton, "🔄 REBIRTH", C.Accent)
			end)
			return
		end
		confirm = false
		Components.setButton(rebirthButton, "🔄 REBIRTH", C.Accent)
		ctx.Request("Rebirth")
	end)
	local ranks = Components.label({
		Text = "",
		Font = Theme.Fonts.Body,
		TextWrapped = true,
		Size = UDim2.new(1, -8, 0, 120),
		LayoutOrder = 2,
		MaxTextSize = 15,
		Parent = rebirthPage,
	})

	-- Perks -------------------------------------------------------------------------------------
	local perkPage = page("Perks")
	local tokensLabel = Components.label({
		Text = "",
		Size = UDim2.new(1, -8, 0, 30),
		LayoutOrder = 0,
		MaxTextSize = 22,
		TextColor3 = C.Accent,
		Parent = perkPage,
	})
	Components.textStroke(tokensLabel, 1.5)
	local perkRows = {}
	for i, perk in Upgrades.Perks do
		perkRows[perk.Id] = UpgradeRows.trackRow(perkPage, i, perk, function()
			ctx.Request("BuyPerk", perk.Id)
		end)
	end

	local function refresh()
		local data = ctx.Data.Data
		if not data or not data.Gear then
			return
		end
		for _, track in Upgrades.Gear do
			local level = data.Gear[track.Id] or 0
			local cost = Progression.trackCost(track, level)
			local now
			if track.Id == "Backpack" then
				now = string.format("Carry %d artifacts", Progression.capacity(data))
			elseif track.Id == "Sneakers" then
				now = string.format("Walk speed %d", Progression.walkSpeed(data))
			else
				now = string.format("Steal %d%% faster", math.floor((1 - Progression.holdMultiplier(data)) * 100 + 0.5))
			end
			UpgradeRows.updateRow(
				gearRows[track.Id],
				level,
				track.MaxLevel,
				track.Desc .. "  (" .. now .. ")",
				cost,
				data.Cash >= cost
			)
		end

		local rank = Upgrades.rank(data.Rebirths)
		rankLabel.Text = string.format("%s  ·  Rebirth %d", rank.Name, data.Rebirths)
		rankLabel.TextColor3 = rank.Color
		local requiredLevel, requiredCash = Progression.rebirthRequirement(data.Rebirths)
		info.Text =
			"Rebirth resets your Cash, Level and Gear. You keep your vault, artifacts, security, cosmetics and collection - and earn permanent bonuses."
		setLevel(data.Level / requiredLevel, string.format("Level %d / %d", data.Level, requiredLevel))
		setCash(data.Cash / requiredCash, string.format("%s / %s", Format.cash(data.Cash), Format.cash(requiredCash)))
		local tokens = Progression.rebirthTokens(data.Rebirths)
		rewardLabel.Text = string.format(
			"Rewards: +%d Prestige Token%s · +%d%% cash forever · +%d%% XP forever",
			tokens,
			tokens == 1 and "" or "s",
			20,
			10
		)
		local can = Progression.canRebirth(data)
		if not confirm then
			Components.setButton(rebirthButton, "🔄 REBIRTH", can and C.Accent or C.PanelLighter, can)
		end
		local lines = { "<b>PRESTIGE RANKS</b>" }
		for _, r in Upgrades.Ranks do
			table.insert(
				lines,
				string.format(
					"%s  %s - %d rebirth%s",
					r.Rebirths <= data.Rebirths and "✅" or "🔒",
					Format.rich(r.Name, r.Color),
					r.Rebirths,
					r.Rebirths == 1 and "" or "s"
				)
			)
		end
		ranks.Text = table.concat(lines, "\n")

		tokensLabel.Text = string.format("🎖️ %d Prestige Tokens  ·  earn more by rebirthing", data.PrestigeTokens)
		for _, perk in Upgrades.Perks do
			local level = data.Perks[perk.Id] or 0
			local cost = Progression.perkCost(level)
			UpgradeRows.updateRow(
				perkRows[perk.Id],
				level,
				perk.MaxLevel,
				perk.Desc,
				nil,
				data.PrestigeTokens >= cost,
				cost .. " 🎖️"
			)
		end
	end

	ctx.Data:ObserveMany({ "Gear", "Perks", "Cash", "Level", "Rebirths", "PrestigeTokens" }, function()
		if shell.Frame.Visible then
			refresh()
		end
	end)
	selectTab("Gear")

	return {
		Name = "Upgrades",
		Frame = shell.Frame,
		Close = shell.Close,
		Refresh = refresh,
		FirstSelectable = gearRows.Backpack:FindFirstChild("Buy"),
	}
end
