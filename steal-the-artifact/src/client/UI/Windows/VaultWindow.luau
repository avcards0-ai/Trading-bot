--[[
	Vault - security upgrades (door, lasers, cameras, traps, guards, alarm), pedestal and
	storage upgrades, and your vault's stats.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Security = require(Shared.Config.Security)
local Upgrades = require(Shared.Config.Upgrades)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local C = Theme.Colors

local UpgradeRows = require(UI.UpgradeRows)
local trackRow = UpgradeRows.trackRow
local updateRow = UpgradeRows.updateRow

return function(ctx)
	local shell = ctx.UI:Shell("Vault", "Vault Security", "🏦", C.Accent)
	local content = shell.Content

	local stats = Components.panel({ Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.PanelLight, Parent = content })
	local statsLabel = Components.label({
		Text = "",
		Size = UDim2.new(1, -20, 1, -12),
		Position = UDim2.fromOffset(10, 6),
		MaxTextSize = 18,
		Parent = stats,
	})
	Components.textStroke(statsLabel, 1.2)

	local list =
		Components.scroll({ Size = UDim2.new(1, 0, 1, -72), Position = UDim2.fromOffset(0, 72), Parent = content })
	Components.list(list, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	Components.padding(list, 4)

	local header1 = Components.label({
		Text = "🛡️ SECURITY - make raiders regret it",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -8, 0, 28),
		LayoutOrder = 0,
		MaxTextSize = 20,
		TextColor3 = C.Accent,
		Parent = list,
	})
	Components.textStroke(header1, 1.2)
	local rows = {}
	for i, track in Security.Tracks do
		rows[track.Id] = trackRow(list, i, track, function()
			ctx.Request("BuySecurity", track.Id)
		end)
	end
	local header2 = Components.label({
		Text = "🏛️ VAULT - more pedestals, more storage",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -8, 0, 28),
		LayoutOrder = 20,
		MaxTextSize = 20,
		TextColor3 = C.Accent,
		Parent = list,
	})
	Components.textStroke(header2, 1.2)
	local vaultRows = {}
	for i, track in Upgrades.Vault do
		vaultRows[track.Id] = trackRow(list, 20 + i, track, function()
			ctx.Request("BuyVault", track.Id)
		end)
	end

	local function refresh()
		local data = ctx.Data.Data
		if not data or not data.Security then
			return
		end
		for _, track in Security.Tracks do
			local level = data.Security[track.Id] or 0
			local cost = Progression.trackCost(track, level)
			local desc = level > 0 and ("Now: " .. track.Levels[level]) or track.Desc
			if level < track.MaxLevel then
				desc ..= "   →   Next: " .. track.Levels[level + 1]
			end
			updateRow(rows[track.Id], level, track.MaxLevel, desc, cost, data.Cash >= cost)
		end
		for _, track in Upgrades.Vault do
			local level = data.Vault[track.Id] or 0
			local cost = Progression.trackCost(track, level)
			local now = track.Id == "Display" and Progression.displaySlots(data) or Progression.storageSize(data)
			updateRow(
				vaultRows[track.Id],
				level,
				track.MaxLevel,
				string.format("%s  (now %d %s, +%d per level)", track.Desc, now, track.Unit, track.PerLevel),
				cost,
				data.Cash >= cost
			)
		end
		local shield = ctx.Data:GetSession("ShieldEnds")
		local shieldText = ""
		if type(shield) == "number" and shield > workspace:GetServerTimeNow() then
			shieldText = "   ·   🛡️ Shield " .. Format.clock(shield - workspace:GetServerTimeNow())
		end
		statsLabel.Text = string.format(
			"🔒 Security %d%%   ·   💎 On display %s   ·   💸 %s/s   ·   🏴‍☠️ Raided %d   ·   🛡️ Defends %d%s",
			Security.rating(data.Security),
			Format.cash(Progression.displayValue(data)),
			Format.cash(Progression.incomePerSecond(data)),
			data.Stats.TimesRaided or 0,
			data.Stats.Defends or 0,
			shieldText
		)
	end

	ctx.Data:ObserveMany({ "Security", "Vault", "Cash", "Displayed", "Artifacts", "Stats" }, function()
		if shell.Frame.Visible then
			refresh()
		end
	end)

	return {
		Name = "Vault",
		Frame = shell.Frame,
		Close = shell.Close,
		Refresh = refresh,
		FirstSelectable = rows.Door:FindFirstChild("Buy"),
	}
end
