--[[
	HUDController
	Always-on HUD: cash / gems / level, income, event timer, backpack bar with carried
	loot, action buttons (Bonk / Dash / Home / Emote) with cooldowns, status chips
	(Wanted / Marked / Bounty / Shield), the "bring it home" waypoint and raid alerts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Artifacts = require(Shared.Config.Artifacts)
local Events = require(Shared.Config.Events)
local Upgrades = require(Shared.Config.Upgrades)
local Progression = require(Shared.Progression)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local UIFolder = script.Parent.Parent.UI
local Components = require(UIFolder.Components)
local Theme = require(UIFolder.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local HUDController = { Name = "HUDController", Buttons = {} :: { [string]: TextButton } }

local controllers: { [string]: any }
local Data

local cashLabel: TextLabel
local gemsLabel: TextLabel
local levelLabel: TextLabel
local rankLabel: TextLabel
local incomeLabel: TextLabel
local setXP: (number, string?) -> ()
local eventLabel: TextLabel
local eventBar: Frame
local backpackFrame: Frame
local backpackStroke: UIStroke
local backpackSlots: Frame
local backpackText: TextLabel
local statusFrame: Frame
local raidOverlay: Frame
local raidVignette: Frame
local raidBanner: Frame
local raidText: TextLabel
local waypointArrow: TextLabel
local waypointBillboard: BillboardGui?
local waypointAnchor: Attachment?
local cooldowns: { [string]: { Ends: number, Duration: number, Overlay: Frame } } = {}
local displayedCash = 0

function HUDController:Init(all)
	controllers = all
	Data = all.DataController
end

-- Top-left stats --------------------------------------------------------------------------------

local function buildStats(hud: Frame)
	local column = Components.new("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 200),
		Position = UDim2.fromOffset(12, 10),
		Parent = hud,
	})
	Components.list(column, Enum.FillDirection.Vertical, 6)
	local _, cash =
		Components.pill(column, "💰", C.Cash, { Name = "Cash", Size = UDim2.fromOffset(210, 42), LayoutOrder = 1 })
	cashLabel = cash
	local row = Components.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.fromOffset(300, 34), LayoutOrder = 2, Parent = column }
	)
	Components.list(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local _, gems =
		Components.pill(row, "💎", C.Gem, { Name = "Gems", Size = UDim2.fromOffset(130, 34), LayoutOrder = 1 })
	gemsLabel = gems
	incomeLabel = Components.label({
		Name = "Income",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Cash,
		Size = UDim2.fromOffset(150, 26),
		MaxTextSize = 18,
		LayoutOrder = 2,
		Parent = row,
	})
	Components.textStroke(incomeLabel, 1.5)

	local levelRow = Components.panel({
		Name = "Level",
		Size = UDim2.fromOffset(270, 44),
		BackgroundColor3 = C.Background,
		Stroke = C.XP,
		LayoutOrder = 3,
		Radius = UDim.new(0, 12),
		Parent = column,
	})
	local badge = Components.panel({
		Size = UDim2.fromOffset(52, 36),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = C.XP,
		Stroke = false,
		Radius = UDim.new(0, 10),
		Parent = levelRow,
	})
	levelLabel = Components.label({
		Text = "1",
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.fromOffset(3, 3),
		MaxTextSize = 24,
		Parent = badge,
	})
	Components.textStroke(levelLabel, 1.5)
	local _, setter = Components.progress(
		levelRow,
		{ Size = UDim2.new(1, -70, 0, 14), Position = UDim2.fromOffset(62, 24), Color = C.XP, TextSize = 11 }
	)
	setXP = setter
	rankLabel = Components.label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -70, 0, 18),
		Position = UDim2.fromOffset(62, 4),
		MaxTextSize = 15,
		Parent = levelRow,
	})
	Components.textStroke(rankLabel, 1.2)

	statusFrame = Components.new("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 30),
		LayoutOrder = 4,
		Parent = column,
	})
	Components.list(statusFrame, Enum.FillDirection.Horizontal, 6)
end

local function chip(text: string, color: Color3, order: number)
	local frame = Components.panel({
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.darken(color, 0.4),
		Stroke = color,
		Radius = UDim.new(1, 0),
		LayoutOrder = order,
		Parent = statusFrame,
	})
	Components.padding(frame, 2, 10)
	local label = Components.label({
		Text = text,
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 15,
		NoConstraint = true,
		Parent = frame,
	})
	Components.textStroke(label, 1.2)
end

local function refreshStatus()
	for _, child in statusFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local now = workspace:GetServerTimeNow()
	local character = player.Character
	local function active(name: string): boolean
		local value = character and character:GetAttribute(name)
		return type(value) == "number" and value > now
	end
	if active("Wanted") then
		chip("🚨 WANTED", C.Danger, 1)
	end
	if active("Marked") then
		chip("🎯 MARKED", C.Warning, 2)
	end
	local bounty = player:GetAttribute("Bounty")
	if type(bounty) == "number" then
		chip("💰 BOUNTY " .. Format.cash(bounty), C.Accent, 3)
	end
	local shield = Data:GetSession("ShieldEnds")
	if type(shield) == "number" and shield > now then
		chip("🛡️ SHIELD " .. Format.clock(shield - now), C.Primary, 4)
	end
	if active("Glued") then
		chip("🫠 STUCK", C.Muted, 5)
	end
end

-- Event strip (top center) ------------------------------------------------------------------------

local function buildEventStrip(hud: Frame)
	eventBar = Components.panel({
		Name = "Event",
		Size = UDim2.fromOffset(420, 44),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.Background,
		Radius = UDim.new(1, 0),
		Parent = hud,
	})
	eventLabel = Components.label({
		Text = "",
		Size = UDim2.new(1, -24, 1, -10),
		Position = UDim2.fromOffset(12, 5),
		MaxTextSize = 22,
		Parent = eventBar,
	})
	Components.textStroke(eventLabel, 1.5)
end

local function refreshEvent()
	local now = workspace:GetServerTimeNow()
	local id = ReplicatedStorage:GetAttribute("EventId")
	local def = id and Events.ById[id]
	local stroke = eventBar:FindFirstChildOfClass("UIStroke")
	if def then
		local ends = ReplicatedStorage:GetAttribute("EventEndsAt") or now
		eventLabel.Text = string.format("%s <b>%s</b>  %s", def.Icon, def.Name, Format.clock(ends - now))
		eventLabel.TextColor3 = def.Color
		if stroke then
			stroke.Color = def.Color
			stroke.Transparency = 0.5 + math.sin(os.clock() * 5) * 0.4
		end
	else
		local nextAt = ReplicatedStorage:GetAttribute("NextEventAt")
		local vault = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("HighSecurityVault")
		local parts = {}
		if type(nextAt) == "number" then
			table.insert(parts, "🎉 Next event " .. Format.clock(nextAt - now))
		end
		if vault then
			local open = vault:GetAttribute("DoorOpen")
			local change = vault:GetAttribute("DoorChangeAt")
			if type(change) == "number" then
				table.insert(parts, (open and "🏦 Vault OPEN " or "🏦 Vault opens ") .. Format.clock(change - now))
			end
		end
		eventLabel.Text = table.concat(parts, "   ·   ")
		eventLabel.TextColor3 = C.SubText
		if stroke then
			stroke.Color = C.Stroke
			stroke.Transparency = 0.35
		end
	end
end

-- Backpack bar (bottom center) --------------------------------------------------------------------

local function buildBackpack(hud: Frame)
	backpackFrame = Components.panel({
		Name = "Backpack",
		Size = UDim2.fromOffset(520, 92),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.Background,
		Parent = hud,
	})
	backpackStroke = backpackFrame:FindFirstChildOfClass("UIStroke") :: UIStroke
	backpackText = Components.label({
		Text = "",
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(10, 4),
		MaxTextSize = 18,
		Parent = backpackFrame,
	})
	Components.textStroke(backpackText, 1.5)
	backpackSlots = Components.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 52),
		Position = UDim2.fromOffset(10, 32),
		Parent = backpackFrame,
	})
	Components.list(
		backpackSlots,
		Enum.FillDirection.Horizontal,
		6,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
end

local function refreshBackpack()
	local carried = Data:GetSession("Carried") or {}
	local capacity = Progression.capacity(Data.Data)
	for _, child in backpackSlots:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local slotSize = capacity > 8 and 38 or 48
	backpackFrame.Size = UDim2.fromOffset(math.max(340, capacity * (slotSize + 6) + 30), 92)
	local total = 0
	for i = 1, capacity do
		local record = carried[i]
		local def = record and Artifacts.get(record.Id)
		local color = def and Theme.rarity(def.Rarity) or C.PanelLight
		local slot = Components.panel({
			Size = UDim2.fromOffset(slotSize, slotSize),
			BackgroundColor3 = def and Theme.darken(color, 0.55) or C.Panel,
			Stroke = def and color or C.PanelLighter,
			Radius = UDim.new(0, 10),
			LayoutOrder = i,
			Parent = backpackSlots,
		})
		if def then
			total += Progression.artifactValue(record.Id, record.M)
			Components.label({
				Text = def.Icon,
				Size = UDim2.new(1, -8, 1, -8),
				Position = UDim2.fromOffset(4, 4),
				MaxTextSize = 30,
				Parent = slot,
			})
			if record.M then
				Components.label({
					Text = record.M == "Rainbow" and "🌈" or "✨",
					Size = UDim2.fromOffset(16, 16),
					Position = UDim2.new(1, -16, 0, 0),
					MaxTextSize = 14,
					Parent = slot,
				})
			end
		end
	end
	if #carried > 0 then
		backpackText.Text =
			string.format('CARRYING <font color="#FFD24D">%s</font> - BRING IT HOME! 🏦', Format.cash(total))
		backpackStroke.Color = C.Accent
	else
		backpackText.Text = string.format("🎒 Backpack %d/%d - go steal something!", #carried, capacity)
		backpackStroke.Color = C.Stroke
	end
end

-- Action buttons (bottom right) -------------------------------------------------------------------

local ACTIONS = {
	{ Name = "Bonk", Icon = "👊", Key = "F", Pad = "RT", Color = C.Danger },
	{ Name = "Dash", Icon = "💨", Key = "Q", Pad = "RB", Color = C.Primary },
	{ Name = "Home", Icon = "🏠", Key = "R", Pad = "Y", Color = C.Success },
	{ Name = "Emote", Icon = "😀", Key = "G", Pad = "↓", Color = C.Warning },
}

local function buildActions(hud: Frame)
	local mobile = controllers.UIController.IsMobile
	local size = mobile and 76 or 64
	local frame = Components.new("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size * 2 + 12, size * 2 + 12),
		Position = mobile and UDim2.new(1, -150, 1, -170) or UDim2.new(1, -16, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		Parent = hud,
	})
	Components.grid(frame, UDim2.fromOffset(size, size), 10)
	for i, action in ACTIONS do
		local button = Components.button({
			Name = action.Name,
			Text = "",
			Color = action.Color,
			Size = UDim2.fromOffset(size, size),
			LayoutOrder = i,
			Radius = UDim.new(1, 0),
			Parent = frame,
		})
		Components.label({
			Text = action.Icon,
			Size = UDim2.fromScale(0.62, 0.62),
			Position = UDim2.fromScale(0.19, 0.12),
			MaxTextSize = 34,
			Parent = button,
		})
		local hint = Components.label({
			Name = "Hint",
			Text = UserInputService.GamepadEnabled and action.Pad or action.Key,
			Size = UDim2.fromScale(0.5, 0.28),
			Position = UDim2.fromScale(0.25, 0.7),
			MaxTextSize = 14,
			Visible = not mobile,
			Parent = button,
		})
		Components.textStroke(hint, 1.2)
		local overlay = Components.new("Frame", {
			Name = "Cooldown",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			Size = UDim2.fromScale(1, 0),
			Position = UDim2.fromScale(0, 1),
			AnchorPoint = Vector2.new(0, 1),
			ZIndex = 5,
			Parent = button,
		})
		Components.corner(overlay, UDim.new(1, 0))
		cooldowns[action.Name] = { Ends = 0, Duration = 1, Overlay = overlay }
		HUDController.Buttons[action.Name] = button
	end
end

function HUDController:SetCooldown(action: string, duration: number)
	local entry = cooldowns[action]
	if entry then
		entry.Ends = os.clock() + duration
		entry.Duration = duration
	end
end

-- Waypoint (bring loot home) ------------------------------------------------------------------------

local function buildWaypoint(overlay: ScreenGui)
	waypointArrow = Components.label({
		Name = "WaypointArrow",
		Text = "➤",
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = C.Success,
		Visible = false,
		MaxTextSize = 44,
		Parent = overlay,
	})
	Components.textStroke(waypointArrow, 2.5)
end

local function ensureBillboard(position: Vector3, text: string, color: Color3)
	local anchor = waypointAnchor
	local billboard = waypointBillboard
	if not anchor or not billboard then
		local newAnchor = Instance.new("Attachment")
		newAnchor.Name = "HUDWaypoint"
		newAnchor.Parent = workspace.Terrain
		local newBillboard = Instance.new("BillboardGui")
		newBillboard.AlwaysOnTop = true
		newBillboard.Size = UDim2.fromOffset(190, 64)
		newBillboard.LightInfluence = 0
		newBillboard.Adornee = newAnchor
		newBillboard.Parent = newAnchor
		local newLabel = Components.label({ Name = "Text", Text = "", MaxTextSize = 22, Parent = newBillboard })
		Components.textStroke(newLabel, 2)
		waypointAnchor = newAnchor
		waypointBillboard = newBillboard
		anchor = newAnchor
		billboard = newBillboard
	end
	local attachment = anchor :: Attachment
	local gui = billboard :: BillboardGui
	attachment.WorldPosition = position + Vector3.new(0, 6, 0)
	local label = gui:FindFirstChild("Text") :: TextLabel
	label.Text = text
	label.TextColor3 = color
	gui.Enabled = true
end

local function updateWaypoint()
	local carried = Data:GetSession("Carried") or {}
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local target: Vector3? = nil
	local color = C.Success
	local marker = ReplicatedStorage:GetAttribute("EventMarker")
	if #carried > 0 then
		local pad = Data:GetSession("SecurePad")
		if typeof(pad) == "Vector3" and pad.Magnitude > 1 then
			target = pad
			color = C.Success
		end
	elseif typeof(marker) == "Vector3" then
		target = marker
		color = C.Warning
	end
	if not target or not root then
		waypointArrow.Visible = false
		if waypointBillboard then
			waypointBillboard.Enabled = false
		end
		return
	end
	local distance = (target - root.Position).Magnitude
	local label = (#carried > 0 and "🏦 SECURE HERE\n" or "☄️ METEOR\n")
		.. string.format("%dm", math.floor(distance / 3.57))
	ensureBillboard(target, label, color)

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local screen, onScreen = camera:WorldToViewportPoint(target)
	if onScreen and screen.Z > 0 then
		waypointArrow.Visible = false
		return
	end
	-- Off-screen: pin an arrow to the edge pointing toward the target.
	local size = camera.ViewportSize
	local center = size / 2
	local direction = Vector2.new(screen.X, screen.Y) - center
	if screen.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, -1)
	end
	direction = direction.Unit
	local margin = 60
	local edge = center
		+ direction
			* math.min(
				(size.X / 2 - margin) / math.max(math.abs(direction.X), 0.01),
				(size.Y / 2 - margin) / math.max(math.abs(direction.Y), 0.01)
			)
	waypointArrow.Position = UDim2.fromOffset(edge.X, edge.Y)
	waypointArrow.Rotation = math.deg(math.atan2(direction.Y, direction.X))
	waypointArrow.TextColor3 = color
	waypointArrow.Visible = true
end

-- Raid alert overlay --------------------------------------------------------------------------------

local function buildRaidOverlay(overlay: Instance)
	raidOverlay = Components.new("Frame", {
		Name = "RaidAlert",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = overlay,
	})
	local vignette = Components.new(
		"Frame",
		{ BackgroundColor3 = C.Danger, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = raidOverlay }
	)
	raidVignette = vignette
	Components.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.25, 1),
			NumberSequenceKeypoint.new(0.75, 1),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		Parent = vignette,
	})
	local banner = Components.panel({
		Name = "Banner",
		Size = UDim2.fromOffset(560, 70),
		Position = UDim2.new(0.5, 0, 0, 120),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.DangerDark,
		Stroke = C.White,
		Parent = raidOverlay,
	})
	raidBanner = banner
	raidText = Components.label({
		Text = "",
		Size = UDim2.new(1, -170, 1, -12),
		Position = UDim2.fromOffset(12, 6),
		MaxTextSize = 24,
		Font = Theme.Fonts.Title,
		Parent = banner,
	})
	Components.textStroke(raidText, 2)
	Components.button({
		Text = "🏠 GO HOME",
		Color = C.Success,
		Size = UDim2.fromOffset(140, 50),
		Position = UDim2.new(1, -150, 0, 10),
		Parent = banner,
		OnClick = function()
			Net.request("Recall")
		end,
	})
end

function HUDController:ShowRaidAlert(info: { [string]: any })
	local text
	if info.Cause == "stolen" then
		local def = info.Artifact and Artifacts.get(info.Artifact)
		text = string.format(
			"💀 %s STOLE YOUR %s!",
			string.upper(info.Raider or "SOMEONE"),
			def and string.upper(def.Name) or "LOOT"
		)
	else
		text = string.format("🚨 %s IS RAIDING YOUR VAULT!", string.upper(info.Raider or "SOMEONE"))
	end
	raidText.Text = text
	raidOverlay.Visible = true
	Components.pop(raidBanner)
	controllers.SoundController:Play("Alarm")
	controllers.EffectsController:Shake(0.6, 0.5)
	local token = os.clock()
	raidOverlay:SetAttribute("Token", token)
	task.delay(6, function()
		if raidOverlay:GetAttribute("Token") == token then
			raidOverlay.Visible = false
		end
	end)
end

-- Start ------------------------------------------------------------------------------------------

function HUDController:Start()
	local hud = controllers.UIController.Hud
	local overlay = controllers.UIController.Overlay
	buildStats(hud)
	buildEventStrip(hud)
	buildBackpack(hud)
	buildActions(hud)
	buildWaypoint(overlay)
	buildRaidOverlay(controllers.UIController.OverlayScaled)

	Data:Observe("Cash", function(value)
		local target = value or 0
		local start = displayedCash
		displayedCash = target
		if math.abs(target - start) < 1 then
			cashLabel.Text = Format.cash(target)
			return
		end
		-- Satisfying count-up
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.5 and displayedCash == target do
				local alpha = (os.clock() - t0) / 0.5
				cashLabel.Text = Format.cash(start + (target - start) * (1 - (1 - alpha) ^ 3))
				task.wait()
			end
			if displayedCash == target then
				cashLabel.Text = Format.cash(target)
			end
		end)
		if target > start then
			Components.pop(cashLabel.Parent :: GuiObject, 0.9)
		end
	end)
	Data:Observe("Gems", function(value)
		gemsLabel.Text = Format.abbreviate(value or 0)
	end)
	Data:ObserveMany({ "Level", "XP", "Rebirths" }, function()
		local level = Data:Get("Level") or 1
		local xp = Data:Get("XP") or 0
		local need = Progression.xpToNext(level)
		levelLabel.Text = tostring(level)
		setXP(xp / need, string.format("%s / %s XP", Format.abbreviate(xp), Format.abbreviate(need)))
		local rank = Upgrades.rank(Data:Get("Rebirths") or 0)
		rankLabel.Text = rank.Name .. ((Data:Get("Rebirths") or 0) > 0 and ("  🔁" .. Data:Get("Rebirths")) or "")
		rankLabel.TextColor3 = rank.Color
	end)
	Data:ObserveSession("Income", function(value)
		incomeLabel.Text = (value and value >= 0.1) and ("+" .. Format.cash(value) .. "/s") or ""
	end)
	Data:ObserveSession("Carried", refreshBackpack)
	Data:ObserveMany({ "Gear", "Perks" }, refreshBackpack)

	Net.event("RaidAlert").OnClientEvent:Connect(function(info)
		self:ShowRaidAlert(info)
	end)

	local statusTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		updateWaypoint()
		-- Cooldown overlays
		local now = os.clock()
		for _, entry in cooldowns do
			local remaining = math.max(0, entry.Ends - now)
			entry.Overlay.Size = UDim2.fromScale(1, remaining / math.max(entry.Duration, 0.01))
		end
		if raidOverlay.Visible then
			raidVignette.BackgroundTransparency = 0.55 + math.sin(now * 8) * 0.25
		end
		statusTimer += dt
		if statusTimer > 0.5 then
			statusTimer = 0
			refreshStatus()
			refreshEvent()
		end
	end)
end

return HUDController
