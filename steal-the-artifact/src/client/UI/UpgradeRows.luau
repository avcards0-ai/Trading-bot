--[[
	UpgradeRows
	Shared "upgrade track" row used by the Vault and Upgrades windows: icon, name,
	description, level pips and a buy button.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors

local UpgradeRows = {}

-- A reusable upgrade row (also used by the Upgrades window).
function UpgradeRows.trackRow(parent: Instance, order: number, track: any, onBuy: () -> ())
	local row = Components.panel({
		Size = UDim2.new(1, -8, 0, 76),
		BackgroundColor3 = C.Panel,
		LayoutOrder = order,
		Parent = parent,
	})
	Components.label({
		Text = track.Icon,
		Size = UDim2.fromOffset(56, 56),
		Position = UDim2.fromOffset(10, 10),
		MaxTextSize = 40,
		Parent = row,
	})
	local title = Components.label({
		Name = "Title",
		Text = track.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -260, 0, 26),
		Position = UDim2.fromOffset(74, 6),
		MaxTextSize = 22,
		Parent = row,
	})
	Components.textStroke(title, 1.2)
	Components.label({
		Name = "Desc",
		Text = "",
		Font = Theme.Fonts.Body,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, -260, 0, 22),
		Position = UDim2.fromOffset(74, 32),
		MaxTextSize = 14,
		Parent = row,
	})
	local pips = Components.new("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -260, 0, 12),
		Position = UDim2.fromOffset(74, 58),
		Parent = row,
	})
	Components.list(pips, Enum.FillDirection.Horizontal, 4)
	for i = 1, track.MaxLevel do
		local pip = Components.new("Frame", {
			Name = tostring(i),
			BackgroundColor3 = C.PanelLighter,
			Size = UDim2.fromOffset(math.clamp(160 / track.MaxLevel, 12, 30), 10),
			LayoutOrder = i,
			Parent = pips,
		})
		Components.corner(pip, UDim.new(1, 0))
	end
	Components.button({
		Name = "Buy",
		Text = "",
		Color = C.Success,
		Size = UDim2.fromOffset(170, 52),
		Position = UDim2.new(1, -180, 0.5, -26),
		MaxTextSize = 18,
		Parent = row,
		OnClick = onBuy,
	})
	return row
end

function UpgradeRows.updateRow(
	row: Frame,
	level: number,
	maxLevel: number,
	desc: string,
	cost: number?,
	affordable: boolean,
	costLabel: string?
)
	(row:FindFirstChild("Desc") :: TextLabel).Text = desc
	for _, pip in (row:FindFirstChild("Pips") :: Frame):GetChildren() do
		if pip:IsA("Frame") then
			pip.BackgroundColor3 = (tonumber(pip.Name) or 0) <= level and C.Accent or C.PanelLighter
		end
	end
	local buy = row:FindFirstChild("Buy") :: TextButton
	if level >= maxLevel then
		Components.setButton(buy, "MAXED ✓", C.PanelLighter, false)
	else
		Components.setButton(
			buy,
			"⬆ " .. (costLabel or Format.cash(cost or 0)),
			affordable and C.Success or C.DangerDark,
			true
		)
	end
end

return UpgradeRows
