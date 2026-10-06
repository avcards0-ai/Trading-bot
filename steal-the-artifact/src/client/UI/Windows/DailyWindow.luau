--[[
	Daily Rewards - 7-day streak calendar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local DailyRewards = require(Shared.Config.DailyRewards)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local C = Theme.Colors

return function(ctx)
	local shell = ctx.UI:Shell("Daily", "Daily Rewards", "🎁", C.Danger, UDim2.fromOffset(820, 470))
	local content = shell.Content

	local subtitle = Components.label({ Text = "", Size = UDim2.new(1, 0, 0, 30), MaxTextSize = 20, Parent = content })
	Components.textStroke(subtitle, 1.2)
	local row = Components.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 220),
		Position = UDim2.fromOffset(0, 40),
		Parent = content,
	})
	Components.list(
		row,
		Enum.FillDirection.Horizontal,
		8,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local cards = {}
	for i, day in DailyRewards.Days do
		local card = Components.panel({
			Size = UDim2.fromOffset(100, 200),
			BackgroundColor3 = C.Panel,
			LayoutOrder = i,
			Parent = row,
		})
		Components.label({
			Text = "DAY " .. day.Day,
			Size = UDim2.new(1, 0, 0, 28),
			Position = UDim2.fromOffset(0, 6),
			MaxTextSize = 18,
			Parent = card,
		})
		Components.label({
			Text = day.Icon,
			Size = UDim2.new(1, 0, 0, 60),
			Position = UDim2.fromOffset(0, 40),
			MaxTextSize = 46,
			Parent = card,
		})
		local label = Components.label({
			Text = day.Label,
			TextWrapped = true,
			Size = UDim2.new(1, -10, 0, 50),
			Position = UDim2.fromOffset(5, 108),
			MaxTextSize = 15,
			Parent = card,
		})
		Components.textStroke(label, 1)
		local check = Components.label({
			Name = "Check",
			Text = "",
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.new(0, 0, 1, -36),
			MaxTextSize = 22,
			Parent = card,
		})
		cards[i] = { Card = card, Check = check }
	end
	local claim = Components.button({
		Text = "CLAIM",
		Color = C.Success,
		Size = UDim2.fromOffset(280, 60),
		Position = UDim2.new(0.5, -140, 1, -80),
		MaxTextSize = 28,
		Parent = content,
	})
	claim.Activated:Connect(function()
		local response = ctx.Request("ClaimDaily")
		if response.ok then
			ctx.Controllers.EffectsController:Confetti(C.Accent, 50)
		end
	end)
	Components.label({
		Text = "👑 VIP thieves get +10 bonus Gems on every daily reward",
		Font = Theme.Fonts.Body,
		TextColor3 = C.SubText,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -18),
		MaxTextSize = 14,
		Parent = content,
	})

	-- Returns: next day to claim, can claim now, seconds until claimable, days claimed this cycle
	local function state(): (number, boolean, number, number)
		local data = ctx.Data.Data
		local daily = data and data.DailyReward
		if not daily then
			return 1, false, 0, 0
		end
		local since = os.time() - (daily.LastClaim or 0)
		local ready = daily.LastClaim == 0 or since >= GameConfig.DailyRewards.ClaimCooldown
		local continuing = daily.LastClaim > 0 and since <= GameConfig.DailyRewards.StreakBreak
		local nextDay = continuing and (daily.Streak % #DailyRewards.Days + 1) or 1
		local claimed = ready and (nextDay - 1) or daily.Streak
		return nextDay, ready, math.max(0, GameConfig.DailyRewards.ClaimCooldown - since), claimed
	end

	local function refresh()
		local nextDay, ready, wait, claimed = state()
		for i, entry in cards do
			local isNext = i == nextDay
			local stroke = entry.Card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = isNext and (ready and C.Success or C.Accent) or C.Stroke
				stroke.Thickness = isNext and 3 or 1.5
			end
			entry.Card.BackgroundColor3 = isNext and C.PanelLight or C.Panel
			entry.Check.Text = i <= claimed and "✅" or (isNext and (ready and "TODAY" or "NEXT") or "")
		end
		local data = ctx.Data.Data
		local consecutive = data and data.DailyReward and data.DailyReward.Consecutive or 0
		subtitle.Text = string.format("🔥 Login streak: %d day%s", consecutive, consecutive == 1 and "" or "s")
		if ready then
			Components.setButton(claim, "🎁 CLAIM DAY " .. nextDay, C.Success, true)
		else
			Components.setButton(claim, "⏳ " .. Format.clock(wait), C.PanelLighter, false)
		end
		ctx.UI:SetBadge("Daily", ready and 1 or 0)
	end

	ctx.Data:ObserveMany({ "DailyReward" }, refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			if shell.Frame.Visible or select(2, state()) then
				refresh()
			end
		end
	end)

	return {
		Name = "Daily",
		Frame = shell.Frame,
		Close = shell.Close,
		Refresh = refresh,
		FirstSelectable = claim,
	}
end
