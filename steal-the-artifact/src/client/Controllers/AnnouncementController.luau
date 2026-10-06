--[[
	AnnouncementController
	Toasts, the kill/steal feed, big banners for legendary steals (local + GLOBAL from
	other servers), server event banners and level-up popups.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Events = require(Shared.Config.Events)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local UIFolder = script.Parent.Parent.UI
local Components = require(UIFolder.Components)
local Theme = require(UIFolder.Theme)

local C = Theme.Colors

local AnnouncementController = { Name = "AnnouncementController" }

local controllers: { [string]: any }
local Data
local toastList: Frame
local feedList: Frame
local bannerHolder: Frame
local bannerQueue: { { [string]: any } } = {}
local bannerBusy = false
local feedCount = 0

local TOAST_COLORS = {
	info = C.Primary,
	success = C.Success,
	error = C.Danger,
	warning = C.Warning,
	reward = C.Accent,
}
local TOAST_ICONS = { info = "ℹ️", success = "✅", error = "⛔", warning = "⚠️", reward = "🎁" }

function AnnouncementController:Init(all)
	controllers = all
	Data = all.DataController
end

local function setting(key: string, default: any): any
	local settings = Data:Get("Settings")
	if type(settings) == "table" and settings[key] ~= nil then
		return settings[key]
	end
	return default
end

-- Toasts --------------------------------------------------------------------------------------

function AnnouncementController:Toast(kind: string, text: string, options: { [string]: any }?)
	local color = TOAST_COLORS[kind] or C.Primary
	if options and options.Rarity then
		color = Theme.rarity(options.Rarity)
	end
	local big = options and options.Big
	local toast = Components.panel({
		Size = UDim2.fromOffset(big and 520 or 440, big and 52 or 42),
		BackgroundColor3 = Theme.darken(color, 0.65),
		Stroke = color,
		Radius = UDim.new(1, 0),
		LayoutOrder = -math.floor(os.clock() * 100),
		Parent = toastList,
	})
	local label = Components.label({
		Text = (TOAST_ICONS[kind] or "") .. "  " .. text,
		Size = UDim2.new(1, -24, 1, -10),
		Position = UDim2.fromOffset(12, 5),
		MaxTextSize = big and 24 or 19,
		Parent = toast,
	})
	Components.textStroke(label, 1.5)
	Components.pop(toast, 0.7)
	if kind == "error" then
		controllers.SoundController:Play("Error")
	end
	local children = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(children, child)
		end
	end
	if #children > 4 then
		table.sort(children, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		for i = 5, #children do
			children[i]:Destroy()
		end
	end
	task.delay(big and 4.5 or 3.2, function()
		if toast.Parent then
			Components.tween(toast, 0.3, { BackgroundTransparency = 1 })
			Components.tween(label, 0.3, { TextTransparency = 1 })
			task.wait(0.32)
			toast:Destroy()
		end
	end)
end

-- Feed ----------------------------------------------------------------------------------------

function AnnouncementController:Feed(entry: { [string]: any })
	if not setting("Feed", true) then
		return
	end
	feedCount += 1
	local color = typeof(entry.Color) == "Color3" and entry.Color or C.Stroke
	local line = Components.panel({
		Size = UDim2.new(1, 0, 0, entry.Big and 40 or 32),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.15,
		Stroke = color,
		Radius = UDim.new(0, 10),
		LayoutOrder = -feedCount,
		Parent = feedList,
	})
	local label = Components.label({
		Text = tostring(entry.Icon or "") .. " " .. tostring(entry.Text or ""),
		Size = UDim2.new(1, -16, 1, -6),
		Position = UDim2.fromOffset(8, 3),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.Body,
		MaxTextSize = entry.Big and 17 or 15,
		Parent = line,
	})
	Components.textStroke(label, 1)
	line.Position = UDim2.fromOffset(40, 0)
	Components.pop(line, 0.85)
	local lines = {}
	for _, child in feedList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(lines, child)
		end
	end
	if #lines > 6 then
		table.sort(lines, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		for i = 7, #lines do
			lines[i]:Destroy()
		end
	end
	task.delay(12, function()
		if line.Parent then
			Components.tween(line, 0.4, { BackgroundTransparency = 1 })
			Components.tween(label, 0.4, { TextTransparency = 1 })
			local stroke = line:FindFirstChildOfClass("UIStroke")
			if stroke then
				Components.tween(stroke, 0.4, { Transparency = 1 })
			end
			task.wait(0.42)
			line:Destroy()
		end
	end)
end

-- Banners --------------------------------------------------------------------------------------

local function showBanner(entry: { [string]: any })
	bannerBusy = true
	local title, subtitle, color = "", "", C.Accent
	local rainbow = false
	if entry.Kind == "Event" then
		local def = Events.ById[entry.EventId]
		if def then
			title = def.Icon .. " " .. def.Name .. " " .. def.Icon
			subtitle = def.Desc
			color = def.Color
		end
		controllers.SoundController:Play("Announce")
		controllers.SoundController:SetMusic("Event")
		controllers.EffectsController:Flash(color, 0.25)
	else
		local def = Artifacts.get(entry.ArtifactId or "")
		local rarity = Rarities.get(entry.Rarity or "Legendary")
		local name = def and def.Name or "an artifact"
		if entry.Mutation then
			name = entry.Mutation .. " " .. name
		end
		rainbow = rarity.Id == "Secret" or entry.Mutation == "Rainbow"
		color = Theme.rarity(rarity.Id)
		title = (entry.Global and "🌍 GLOBAL  " or "") .. string.upper(rarity.Name) .. " STEAL!"
		subtitle = string.format(
			"%s stole %s%s",
			Format.escape(tostring(entry.PlayerName or "Someone")),
			Format.rich(Format.escape(name), color),
			entry.ZoneName and entry.ZoneName ~= "" and (" from " .. Format.escape(entry.ZoneName)) or ""
		)
		controllers.SoundController:Play("Announce", { Speed = rarity.Index >= 6 and 0.7 or 0.9 })
		if rarity.Id == "Secret" then
			controllers.EffectsController:Flash(Color3.new(1, 1, 1), 0.5)
		end
	end

	local banner = Components.panel({
		Size = UDim2.fromOffset(720, 96),
		Position = UDim2.new(0.5, 0, 0, -120),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.darken(color, 0.7),
		Stroke = color,
		Parent = bannerHolder,
	})
	local titleLabel = Components.label({
		Text = title,
		Font = Theme.Fonts.Title,
		TextColor3 = color,
		Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.fromOffset(10, 6),
		MaxTextSize = 44,
		Parent = banner,
	})
	Components.textStroke(titleLabel, 3)
	local sub = Components.label({
		Text = subtitle,
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 58),
		MaxTextSize = 22,
		Parent = banner,
	})
	Components.textStroke(sub, 1.5)
	TweenService:Create(banner, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 64) })
		:Play()

	local start = os.clock()
	local duration = entry.Kind == "Event" and 4.5 or 4
	while os.clock() - start < duration do
		if rainbow then
			local t = os.clock()
			titleLabel.TextColor3 = Rarities.rainbow(t)
			local stroke = banner:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Rarities.rainbow(t, 0.5)
			end
		end
		task.wait()
	end
	TweenService:Create(
		banner,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, 0, 0, -130) }
	):Play()
	task.wait(0.36)
	banner:Destroy()
	bannerBusy = false
	local nextEntry = table.remove(bannerQueue, 1)
	if nextEntry then
		task.spawn(showBanner, nextEntry)
	end
end

function AnnouncementController:Banner(entry: { [string]: any })
	if entry.Remote and not setting("Global", true) then
		return
	end
	if bannerBusy then
		if #bannerQueue < 4 then
			table.insert(bannerQueue, entry)
		end
		return
	end
	task.spawn(showBanner, entry)
end

-- Level up ---------------------------------------------------------------------------------------

local function levelUp(level: number, rewards: { [string]: any })
	local overlay = controllers.UIController.OverlayScaled
	local frame = Components.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(500, 160),
		Position = UDim2.fromScale(0.5, 0.32),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = overlay,
	})
	local title = Components.label({
		Text = "LEVEL UP!",
		Font = Theme.Fonts.Title,
		TextColor3 = C.XP,
		Size = UDim2.new(1, 0, 0, 70),
		MaxTextSize = 64,
		Parent = frame,
	})
	Components.textStroke(title, 4)
	local levelText = Components.label({
		Text = "Level " .. level,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 70),
		MaxTextSize = 38,
		Parent = frame,
	})
	Components.textStroke(levelText, 2.5)
	local parts = {}
	if rewards.Cash and rewards.Cash > 0 then
		table.insert(parts, "+" .. Format.cash(rewards.Cash))
	end
	if rewards.Gems and rewards.Gems > 0 then
		table.insert(parts, "+" .. rewards.Gems .. " 💎")
	end
	local rewardText = Components.label({
		Text = table.concat(parts, "   "),
		TextColor3 = C.Accent,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 116),
		MaxTextSize = 26,
		Parent = frame,
	})
	Components.textStroke(rewardText, 2)
	Components.pop(frame, 0.3)
	controllers.SoundController:Play("LevelUp")
	controllers.EffectsController:Confetti(C.XP)
	task.delay(2.6, function()
		for _, label in { title, levelText, rewardText } do
			Components.tween(label, 0.4, { TextTransparency = 1 })
		end
		task.wait(0.45)
		frame:Destroy()
	end)
end

function AnnouncementController:Start()
	local hud = controllers.UIController.Hud
	local overlay = controllers.UIController.OverlayScaled

	toastList = Components.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(540, 260),
		Position = UDim2.new(0.5, 0, 1, -120),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = hud,
	})
	Components.list(
		toastList,
		Enum.FillDirection.Vertical,
		6,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Bottom
	)

	feedList = Components.new("Frame", {
		Name = "Feed",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(380, 280),
		Position = UDim2.new(1, -12, 0.3, 0),
		AnchorPoint = Vector2.new(1, 0),
		Parent = hud,
	})
	Components.list(feedList, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right)

	bannerHolder = Components.new(
		"Frame",
		{ Name = "Banners", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = overlay }
	)

	Net.event("Notify").OnClientEvent:Connect(function(kind, text, options)
		self:Toast(kind, text, options)
	end)
	Net.event("Feed").OnClientEvent:Connect(function(entry)
		self:Feed(entry)
	end)
	Net.event("Announce").OnClientEvent:Connect(function(entry)
		self:Banner(entry)
	end)
	Net.event("LevelUp").OnClientEvent:Connect(levelUp)
	Data:Observe("Settings", function(settings)
		if type(settings) == "table" then
			feedList.Visible = settings.Feed ~= false
		end
	end)

	-- Music returns to calm when the event ends
	ReplicatedStorage:GetAttributeChangedSignal("EventId"):Connect(function()
		if not ReplicatedStorage:GetAttribute("EventId") then
			controllers.SoundController:SetMusic("Calm")
		end
	end)
end

return AnnouncementController
