--[[
	Quests - personal Missions, shared Daily Challenges (+ bonus) and Achievements.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Quests = require(Shared.Config.Quests)
local Achievements = require(Shared.Config.Achievements)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local C = Theme.Colors

return function(ctx)
	local shell = ctx.UI:Shell("Quests", "Quests & Achievements", "📜", C.Warning)
	local content = shell.Content
	local current = "Missions"
	local refresh: () -> ()

	local _, selectTab = Components.tabs(content, { "Missions", "Daily", "Achievements" }, function(name)
		current = name
		if refresh then
			refresh()
		end
	end)
	local list =
		Components.scroll({ Size = UDim2.new(1, 0, 1, -50), Position = UDim2.fromOffset(0, 50), Parent = content })
	Components.list(list, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	Components.padding(list, 4)

	local function questText(def: any, goal: number): string
		local goalText = (def.Event == "SecureValue" or def.Event == "EarnCash") and Format.cash(goal) or tostring(goal)
		return string.format(def.Text, goalText)
	end

	local function rewardText(reward: any, level: number): string
		local scale = Quests.rewardScale(level)
		local parts = {}
		if reward.Cash then
			table.insert(parts, "💰 " .. Format.abbreviate(reward.Cash * scale))
		end
		if reward.XP then
			table.insert(parts, "⭐ " .. Format.abbreviate(reward.XP * scale) .. " XP")
		end
		if reward.Gems then
			table.insert(parts, "💎 " .. reward.Gems)
		end
		return table.concat(parts, "   ")
	end

	local function questCard(order: number, def: any, quest: any, level: number, kind: string, index: number)
		local done = quest.Progress >= quest.Goal
		local accent = quest.Claimed and C.Muted or (done and C.Success or C.Warning)
		local card = Components.panel({
			Size = UDim2.new(1, -8, 0, 92),
			BackgroundColor3 = C.Panel,
			Stroke = accent,
			LayoutOrder = order,
			Parent = list,
		})
		local title = Components.label({
			Text = questText(def, quest.Goal),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -230, 0, 28),
			Position = UDim2.fromOffset(14, 8),
			MaxTextSize = 20,
			Parent = card,
		})
		Components.textStroke(title, 1.2)
		Components.label({
			Text = rewardText(def.Reward, level),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.Accent,
			Size = UDim2.new(1, -230, 0, 20),
			Position = UDim2.fromOffset(14, 36),
			MaxTextSize = 16,
			Parent = card,
		})
		local _, set = Components.progress(card, {
			Size = UDim2.new(1, -240, 0, 18),
			Position = UDim2.fromOffset(14, 64),
			Color = done and C.Success or C.Warning,
			TextSize = 13,
		})
		local progressText = (def.Event == "SecureValue" or def.Event == "EarnCash")
				and (Format.cash(quest.Progress) .. " / " .. Format.cash(quest.Goal))
			or (quest.Progress .. " / " .. quest.Goal)
		set(quest.Progress / quest.Goal, progressText)
		local button = Components.button({
			Text = "",
			Color = C.Success,
			Size = UDim2.fromOffset(190, 46),
			Position = UDim2.new(1, -200, 0.5, -23),
			MaxTextSize = 18,
			Parent = card,
		})
		if quest.Claimed then
			Components.setButton(button, "CLAIMED ✓", C.PanelLighter, false)
		elseif done then
			Components.setButton(button, "🎁 CLAIM", C.Success, true)
			button.Activated:Connect(function()
				ctx.Request("ClaimQuest", kind, index)
			end)
		elseif kind == "Mission" then
			local cost = math.floor(Quests.RerollCost * Quests.rewardScale(level))
			Components.setButton(button, "🎲 Re-roll " .. Format.cash(cost), C.PanelLighter, true)
			button.Activated:Connect(function()
				ctx.Request("RerollMission", index)
			end)
		else
			Components.setButton(button, "In progress...", C.PanelLighter, false)
		end
		return button
	end

	refresh = function()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = ctx.Data.Data
		if not data or not data.Quests then
			return
		end
		local first: GuiObject? = nil
		local claimable = 0
		for _, quest in data.Quests.Missions do
			if not quest.Claimed and quest.Progress >= quest.Goal then
				claimable += 1
			end
		end
		for _, quest in data.Quests.Daily.List do
			if not quest.Claimed and quest.Progress >= quest.Goal then
				claimable += 1
			end
		end
		ctx.UI:SetBadge("Quests", claimable)

		if current == "Missions" then
			for i, quest in data.Quests.Missions do
				local def = Quests.MissionById[quest.Id]
				if def then
					local button = questCard(i, def, quest, data.Level, "Mission", i)
					first = first or button
				end
			end
		elseif current == "Daily" then
			local resetIn = (Quests.dayNumber() + 1) * 86400 - os.time()
			Components.label({
				Text = "Daily challenges are the same for everyone today · new ones in " .. Format.duration(resetIn),
				Font = Theme.Fonts.Body,
				TextColor3 = C.SubText,
				Size = UDim2.new(1, -8, 0, 22),
				LayoutOrder = 0,
				MaxTextSize = 15,
				Parent = list,
			})
			local allClaimed = #data.Quests.Daily.List > 0
			for i, quest in data.Quests.Daily.List do
				local def = Quests.DailyById[quest.Id]
				if def then
					local button = questCard(i, def, quest, data.Level, "Daily", i)
					first = first or button
				end
				allClaimed = allClaimed and quest.Claimed
			end
			local bonus = Components.panel({
				Size = UDim2.new(1, -8, 0, 70),
				BackgroundColor3 = C.PanelLight,
				Stroke = C.Accent,
				LayoutOrder = 10,
				Parent = list,
			})
			Components.label({
				Text = "🏆 DAILY BONUS - clear all three: " .. rewardText(Quests.DailyBonus, data.Level),
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -230, 1, -16),
				Position = UDim2.fromOffset(14, 8),
				MaxTextSize = 18,
				Parent = bonus,
			})
			local claim = Components.button({
				Text = "",
				Color = C.Accent,
				Size = UDim2.fromOffset(190, 46),
				Position = UDim2.new(1, -200, 0.5, -23),
				Parent = bonus,
			})
			if data.Quests.Daily.BonusClaimed then
				Components.setButton(claim, "CLAIMED ✓", C.PanelLighter, false)
			else
				Components.setButton(claim, "🎁 CLAIM BONUS", allClaimed and C.Accent or C.PanelLighter, allClaimed)
				claim.Activated:Connect(function()
					ctx.Request("ClaimDailyBonus")
				end)
			end
		else
			local unlocked = 0
			for _ in data.Achievements or {} do
				unlocked += 1
			end
			Components.label({
				Text = string.format("🏅 %d / %d unlocked", unlocked, #Achievements.List),
				Size = UDim2.new(1, -8, 0, 28),
				LayoutOrder = 0,
				MaxTextSize = 20,
				TextColor3 = C.Accent,
				Parent = list,
			})
			for i, achievement in Achievements.List do
				local done = data.Achievements[achievement.Id] ~= nil
				local hidden = achievement.Hidden and not done
				local value
				if achievement.Stat == "Level" then
					value = data.Level
				elseif achievement.Stat == "Rebirths" then
					value = data.Rebirths
				elseif achievement.Stat == "Discovered" then
					value = Progression.discoveredCount(data)
				else
					value = data.Stats[achievement.Stat] or 0
				end
				local row = Components.panel({
					Size = UDim2.new(1, -8, 0, 64),
					BackgroundColor3 = done and Theme.darken(C.Success, 0.7) or C.Panel,
					Stroke = done and C.Success or C.Stroke,
					LayoutOrder = i,
					Parent = list,
				})
				Components.label({
					Text = hidden and "❓" or achievement.Icon,
					Size = UDim2.fromOffset(48, 48),
					Position = UDim2.fromOffset(8, 8),
					MaxTextSize = 34,
					Parent = row,
				})
				local name = Components.label({
					Text = hidden and "???" or achievement.Name,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -330, 0, 24),
					Position = UDim2.fromOffset(64, 6),
					MaxTextSize = 19,
					Parent = row,
				})
				Components.textStroke(name, 1.2)
				Components.label({
					Text = hidden and "A secret achievement. Keep exploring..." or achievement.Desc,
					Font = Theme.Fonts.Body,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = C.SubText,
					Size = UDim2.new(1, -330, 0, 20),
					Position = UDim2.fromOffset(64, 34),
					MaxTextSize = 14,
					Parent = row,
				})
				Components.label({
					Text = string.format(
						"💎 %d%s",
						achievement.Gems,
						achievement.Title and ("  🏷️ " .. achievement.Title) or ""
					),
					TextColor3 = C.Accent,
					Size = UDim2.fromOffset(150, 24),
					Position = UDim2.new(1, -260, 0, 6),
					MaxTextSize = 15,
					Parent = row,
				})
				local _, set = Components.progress(row, {
					Size = UDim2.fromOffset(240, 16),
					Position = UDim2.new(1, -252, 0, 38),
					Color = done and C.Success or C.Primary,
					TextSize = 12,
				})
				set(
					done and 1 or value / achievement.Goal,
					done and "UNLOCKED" or (Format.abbreviate(value) .. " / " .. Format.abbreviate(achievement.Goal))
				)
			end
		end
		local window = ctx.UI:GetWindow("Quests")
		if window then
			window.FirstSelectable = first or shell.Close
		end
	end

	ctx.Data:ObserveMany({ "Quests", "Achievements", "Stats", "Level" }, function()
		if shell.Frame.Visible then
			refresh()
		else
			-- keep the menu badge fresh
			local data = ctx.Data.Data
			if data and data.Quests then
				local count = 0
				for _, quest in data.Quests.Missions do
					if not quest.Claimed and quest.Progress >= quest.Goal then
						count += 1
					end
				end
				for _, quest in data.Quests.Daily.List do
					if not quest.Claimed and quest.Progress >= quest.Goal then
						count += 1
					end
				end
				ctx.UI:SetBadge("Quests", count)
			end
		end
	end)
	selectTab("Missions")

	return {
		Name = "Quests",
		Frame = shell.Frame,
		Close = shell.Close,
		Refresh = refresh,
	}
end
