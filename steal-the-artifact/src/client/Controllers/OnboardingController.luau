--[[
	OnboardingController
	A tiny guided first session that teaches the loop by doing it:
	FIND -> STEAL -> ESCAPE -> SECURE -> UPGRADE -> RAID. Steps are derived from real stats,
	so it never gets out of sync and disappears once you've done each thing once.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local UIFolder = script.Parent.Parent.UI
local Components = require(UIFolder.Components)
local Theme = require(UIFolder.Theme)

local C = Theme.Colors

local OnboardingController = { Name = "OnboardingController" }

local controllers: { [string]: any }
local panel: Frame
local stepLabel: TextLabel
local lastStep = 0

local STEPS = {
	{ Icon = "🔎", Text = "FIND an artifact - check the Marketplace stalls or the Museum. Glowing = valuable!" },
	{ Icon = "🖐️", Text = "STEAL it - hold [E] / [X] / tap the prompt. Rarer loot takes longer to grab." },
	{ Icon = "🏃", Text = "ESCAPE to your vault - follow the green arrow. Don't get bonked or tackled!" },
	{ Icon = "🏦", Text = "SECURE it - step on the glowing SECURE pad inside your vault." },
	{ Icon = "⚡", Text = "UPGRADE - open Upgrades and buy a Bigger Backpack or Sneaky Sneakers." },
	{
		Icon = "🏴‍☠️",
		Text = string.format(
			"RAID - at level %d you can crack other vaults. Protect yours with security!",
			GameConfig.Raid.MinLevelToRaid
		),
	},
}

function OnboardingController:Init(all)
	controllers = all
end

local function currentStep(): number
	local Data = controllers.DataController
	local data = Data.Data
	if not data or not data.Stats then
		return 0
	end
	local carried = Data:GetSession("Carried") or {}
	local gearLevels = 0
	for _, level in data.Gear or {} do
		gearLevels += level
	end
	if (data.Stats.Raids or 0) > 0 or data.Rebirths > 0 then
		return 0
	end
	if #carried > 0 then
		return (data.Stats.Secured or 0) == 0 and 3 or 0
	end
	if (data.Stats.Steals or 0) == 0 then
		return 1
	end
	if (data.Stats.Secured or 0) == 0 then
		return 2
	end
	if gearLevels == 0 then
		return 5
	end
	if data.Level < GameConfig.Raid.MinLevelToRaid + 3 then
		return 6
	end
	return 0
end

local function refresh()
	local step = currentStep()
	if step == lastStep then
		return
	end
	lastStep = step
	if step == 0 then
		panel.Visible = false
		return
	end
	local entry = STEPS[step]
	stepLabel.Text = string.format("%s  <b>STEP %d/%d</b>  %s", entry.Icon, step, #STEPS, entry.Text)
	panel.Visible = true
	Components.pop(panel, 0.8)
	controllers.SoundController:Play("Click", { Speed = 1.4 })
end

function OnboardingController:Start()
	panel = Components.panel({
		Name = "Onboarding",
		Size = UDim2.fromOffset(640, 52),
		Position = UDim2.new(0.5, 0, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.darken(C.Primary, 0.55),
		Stroke = C.Primary,
		Radius = UDim.new(1, 0),
		Visible = false,
		Parent = controllers.UIController.Hud,
	})
	stepLabel = Components.label({
		Text = "",
		Size = UDim2.new(1, -30, 1, -10),
		Position = UDim2.fromOffset(15, 5),
		MaxTextSize = 18,
		Parent = panel,
	})
	Components.textStroke(stepLabel, 1.2)

	local Data = controllers.DataController
	Data:ObserveMany({ "Stats", "Gear", "Level", "Rebirths" }, refresh)
	Data:ObserveSession("Carried", function()
		task.defer(refresh)
	end)
	-- Step 4 (secure) shows when you're carrying loot near home
	task.spawn(function()
		while true do
			task.wait(1)
			if lastStep == 3 then
				local pad = Data:GetSession("SecurePad")
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if typeof(pad) == "Vector3" and root and (root.Position - pad).Magnitude < 60 then
					local entry = STEPS[4]
					stepLabel.Text = string.format("%s  <b>STEP %d/%d</b>  %s", entry.Icon, 4, #STEPS, entry.Text)
				end
			end
		end
	end)
end

return OnboardingController
