--[[
	Leaderboards - Richest, Best Vault, Most Steals, Rarest Collection. Global (all
	servers) and This Server views.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Util.Format)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local BOARDS = {
	{ Key = "Richest", Tab = "Richest" },
	{ Key = "BestVault", Tab = "Best Vault" },
	{ Key = "MostSteals", Tab = "Most Steals" },
	{ Key = "Collection", Tab = "Collection" },
}

return function(ctx)
	local shell = ctx.UI:Shell("Leaderboards", "Leaderboards", "🏆", C.Accent)
	local content = shell.Content
	local board = "Richest"
	local scope = "Global"
	local snapshot: any = nil
	local refresh: () -> ()

	local tabNames = {}
	local keyForTab = {}
	for _, entry in BOARDS do
		table.insert(tabNames, entry.Tab)
		keyForTab[entry.Tab] = entry.Key
	end
	Components.tabs(content, tabNames, function(name)
		board = keyForTab[name]
		if refresh then
			refresh()
		end
	end, UDim2.new(0.7, -6, 0, 40))
	local _, selectScope = Components.tabs(content, { "Global", "Server" }, function(name)
		scope = name
		if refresh then
			refresh()
		end
	end, UDim2.new(0.3, -6, 0, 40), UDim2.new(0.7, 6, 0, 0))

	local status = Components.label({
		Text = "",
		Font = Theme.Fonts.Body,
		TextColor3 = C.SubText,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 46),
		MaxTextSize = 14,
		Parent = content,
	})
	local list =
		Components.scroll({ Size = UDim2.new(1, 0, 1, -72), Position = UDim2.fromOffset(0, 70), Parent = content })
	Components.list(list, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	Components.padding(list, 4)

	refresh = function()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if not snapshot then
			status.Text = "Loading leaderboards..."
			return
		end
		local entries = (scope == "Global" and snapshot.Global or snapshot.Server or {})[board] or {}
		if scope == "Global" and #entries == 0 then
			status.Text = snapshot.GlobalAvailable
					and "Global boards update every couple of minutes - showing nothing yet."
				or "Global boards are unavailable here (Studio without API access). Showing this server."
			entries = (snapshot.Server or {})[board] or {}
		else
			status.Text = scope == "Global" and "Top thieves across every server" or "Everyone in this server right now"
		end
		for i, entry in entries do
			local mine = entry.UserId == player.UserId
			local medal = i == 1 and "🥇" or i == 2 and "🥈" or i == 3 and "🥉" or ("#" .. i)
			local color = i == 1 and C.Accent
				or (i == 2 and Color3.fromRGB(210, 215, 230) or (i == 3 and Color3.fromRGB(220, 150, 90) or C.Text))
			local row = Components.panel({
				Size = UDim2.new(1, -8, 0, 46),
				BackgroundColor3 = mine and Theme.darken(C.Primary, 0.4) or C.Panel,
				Stroke = mine and C.Primary or (i <= 3 and color or C.Stroke),
				LayoutOrder = i,
				Parent = list,
			})
			Components.label({
				Text = medal,
				TextColor3 = color,
				Size = UDim2.fromOffset(70, 34),
				Position = UDim2.fromOffset(8, 6),
				MaxTextSize = 24,
				Parent = row,
			})
			local name = Components.label({
				Text = Format.escape(entry.Name or "?") .. (mine and "  (you)" or ""),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -280, 0, 34),
				Position = UDim2.fromOffset(84, 6),
				MaxTextSize = 22,
				Parent = row,
			})
			Components.textStroke(name, 1.2)
			local value = Components.label({
				Text = entry.Text or Format.abbreviate(entry.Value or 0),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = C.Accent,
				Size = UDim2.fromOffset(180, 34),
				Position = UDim2.new(1, -192, 0, 6),
				MaxTextSize = 22,
				Parent = row,
			})
			Components.textStroke(value, 1.2)
		end
	end

	Net.event("Leaderboards").OnClientEvent:Connect(function(data)
		snapshot = data
		if shell.Frame.Visible then
			refresh()
		end
	end)
	selectScope("Global")

	return {
		Name = "Leaderboards",
		Frame = shell.Frame,
		Close = shell.Close,
		Refresh = refresh,
		OnOpen = function()
			local response = Net.request("GetLeaderboards")
			if response.ok and response.data then
				snapshot = response.data
				refresh()
			end
		end,
	}
end
