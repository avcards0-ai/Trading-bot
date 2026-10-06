--[[
	UIController
	Owns the root ScreenGuis, responsive scaling (phone / tablet / PC / console), the menu
	sidebar and every window (one open at a time, with blur + pop animations).
]]

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local UIFolder = script.Parent.Parent.UI
local Components = require(UIFolder.Components)
local Theme = require(UIFolder.Theme)

local C = Theme.Colors
local player = Players.LocalPlayer

local UIController = {
	Name = "UIController",
	Root = nil :: ScreenGui?,
	Overlay = nil :: ScreenGui?,
	Hud = nil :: Frame?,
	OverlayScaled = nil :: Frame?,
	WindowsFolder = nil :: Frame?,
	Scale = 1,
	OpenWindow = nil :: string?,
	WindowOpened = Signal.new(),
	WindowClosed = Signal.new(),
	Badges = {} :: { [string]: (number) -> () },
	IsMobile = false,
	IsConsole = false,
}

local controllers: { [string]: any }
local windows: { [string]: any } = {}
local windowOrder: { string } = {}
local blur: BlurEffect

export type WindowContext = {
	UI: typeof(UIController),
	Controllers: { [string]: any },
	Data: any,
	Sound: any,
	Net: typeof(Net),
	Notify: (kind: string, text: string) -> (),
	Request: (action: string, ...any) -> Net.Response,
}

local MENU = {
	{ Name = "Inventory", Icon = "🎒", Label = "Loot", Key = Enum.KeyCode.B },
	{ Name = "Vault", Icon = "🏦", Label = "Vault", Key = Enum.KeyCode.V },
	{ Name = "Upgrades", Icon = "⚡", Label = "Upgrades", Key = Enum.KeyCode.U },
	{ Name = "Shop", Icon = "🛒", Label = "Shop", Key = Enum.KeyCode.N },
	{ Name = "Quests", Icon = "📜", Label = "Quests", Key = Enum.KeyCode.J },
	{ Name = "Collection", Icon = "📖", Label = "Collection", Key = Enum.KeyCode.K },
	{ Name = "Leaderboards", Icon = "🏆", Label = "Leaders", Key = Enum.KeyCode.L },
	{ Name = "Daily", Icon = "🎁", Label = "Daily", Key = Enum.KeyCode.Y },
	{ Name = "Codes", Icon = "🎟️", Label = "Codes", Key = Enum.KeyCode.H },
	{ Name = "Settings", Icon = "⚙️", Label = "Settings", Key = Enum.KeyCode.P },
}
UIController.Menu = MENU

function UIController:Init(all)
	controllers = all
end

function UIController:Context(): WindowContext
	return {
		UI = self,
		Controllers = controllers,
		Data = controllers.DataController,
		Sound = controllers.SoundController,
		Net = Net,
		Notify = function(kind, text)
			controllers.AnnouncementController:Toast(kind, text)
		end,
		Request = function(action, ...)
			local response = Net.request(action, ...)
			if response.msg then
				controllers.AnnouncementController:Toast(response.ok and "success" or "error", response.msg)
			end
			if response.ok then
				controllers.SoundController:Play("Purchase")
			elseif response.msg then
				controllers.SoundController:Play("Error")
			end
			return response
		end,
	}
end

-- Scaling --------------------------------------------------------------------------------------

local function updateScale(scale: UIScale)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local value = math.min(viewport.X / 1280, viewport.Y / 760)
	if UIController.IsConsole then
		value *= 1.1
	end
	value = math.clamp(value, 0.5, 1.25)
	scale.Scale = value
	UIController.Scale = value
end

-- Windows ---------------------------------------------------------------------------------------

function UIController:Toggle(name: string)
	if self.OpenWindow == name then
		self:Close()
	else
		self:Open(name)
	end
end

function UIController:Open(name: string)
	local window = windows[name]
	if not window then
		return
	end
	if self.OpenWindow and self.OpenWindow ~= name then
		self:Close(true)
	end
	self.OpenWindow = name
	window.Frame.Visible = true
	Components.pop(window.Frame, 0.82)
	Components.tween(blur, 0.25, { Size = 14 })
	controllers.SoundController:Play("OpenWindow")
	if window.OnOpen then
		task.spawn(window.OnOpen)
	end
	if window.Refresh then
		task.spawn(window.Refresh)
	end
	if UserInputService.GamepadEnabled then
		task.defer(function()
			GuiService.SelectedObject = window.FirstSelectable or window.Close
		end)
	end
	self.WindowOpened:Fire(name)
end

function UIController:Close(silent: boolean?)
	local name = self.OpenWindow
	if not name then
		return
	end
	local window = windows[name]
	self.OpenWindow = nil
	if window then
		window.Frame.Visible = false
		if window.OnClose then
			task.spawn(window.OnClose)
		end
	end
	if not silent then
		Components.tween(blur, 0.2, { Size = 0 })
		controllers.SoundController:Play("CloseWindow")
	end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self.Root :: ScreenGui) then
		GuiService.SelectedObject = nil
	end
	self.WindowClosed:Fire(name)
end

-- Builds the standard window shell. Window modules fill `Content`.
function UIController:Shell(name: string, title: string, icon: string, accent: Color3?, size: UDim2?)
	local color = accent or C.Accent
	local frame = Components.panel({
		Name = name .. "Window",
		Size = size or UDim2.fromOffset(820, 540),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Background,
		Stroke = color,
		Visible = false,
		ZIndex = 20,
		Parent = self.WindowsFolder,
	})
	local header = Components.panel({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Theme.darken(color, 0.25),
		Stroke = false,
		Parent = frame,
	})
	Components.gradient(header, Theme.lighten(color, 0.1), Theme.darken(color, 0.35), 0)
	local titleLabel = Components.label({
		Name = "Title",
		Text = icon .. "  " .. string.upper(title),
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -90, 1, -14),
		Position = UDim2.fromOffset(18, 7),
		MaxTextSize = 34,
		Parent = header,
	})
	Components.textStroke(titleLabel, 2.5)
	local close = Components.button({
		Name = "Close",
		Text = "✕",
		Color = C.Danger,
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, -52, 0, 6),
		Sound = "CloseWindow",
		Parent = header,
		OnClick = function()
			self:Close()
		end,
	})
	local content = Components.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -72),
		Position = UDim2.fromOffset(12, 64),
		Parent = frame,
	})
	return { Frame = frame, Content = content, Close = close, Header = header, TitleLabel = titleLabel }
end

function UIController:RegisterWindow(name: string, window: any)
	windows[name] = window
	table.insert(windowOrder, name)
end

function UIController:GetWindow(name: string)
	return windows[name]
end

-- Menu -----------------------------------------------------------------------------------------

local function buildMenu(root: ScreenGui)
	local menu = Components.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(152, 370),
		Position = UDim2.new(0, 12, 0.46, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = root:FindFirstChild("Scaled") :: Frame,
	})
	Components.grid(menu, UDim2.fromOffset(70, 70), 8)
	for i, entry in MENU do
		local button = Components.button({
			Name = entry.Name,
			Text = "",
			Color = C.PanelLight,
			Size = UDim2.fromOffset(70, 70),
			LayoutOrder = i,
			Parent = menu,
			OnClick = function()
				UIController:Toggle(entry.Name)
			end,
		})
		Components.label({
			Text = entry.Icon,
			Size = UDim2.new(1, 0, 0.62, 0),
			Position = UDim2.fromScale(0, 0.04),
			MaxTextSize = 34,
			Parent = button,
		})
		local caption = Components.label({
			Text = entry.Label,
			Size = UDim2.new(1, -4, 0.3, 0),
			Position = UDim2.new(0, 2, 0.66, 0),
			MaxTextSize = 13,
			Parent = button,
		})
		Components.textStroke(caption, 1.2)
		UIController.Badges[entry.Name] = Components.badge(button)
	end
	return menu
end

function UIController:SetBadge(name: string, count: number)
	local setter = self.Badges[name]
	if setter then
		setter(count)
	end
end

function UIController:Start()
	self.IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	self.IsConsole = GuiService:IsTenFootInterface()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	local playerGui = player:WaitForChild("PlayerGui")
	local root = Components.new("ScreenGui", {
		Name = "MainUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		IgnoreGuiInset = false,
		Parent = playerGui,
	})
	self.Root = root
	-- Everything lives inside a full-screen frame with one UIScale so the layout is
	-- authored at 1280x760 and scales cleanly to phones and TVs.
	-- Centered so the result is correct whether UIScale scales about the center or the anchor.
	local function scaledFrame(parent: Instance): (Frame, UIScale)
		local frame = Components.new("Frame", {
			Name = "Scaled",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Parent = parent,
		})
		return frame, Components.new("UIScale", { Parent = frame })
	end
	local scaled, scale = scaledFrame(root)
	local overlayScale: UIScale? = nil
	local overlayScaled: Frame? = nil
	-- Counter-scale the container so children positioned with Scale still fill the screen.
	local function resize()
		updateScale(scale)
		scaled.Size = UDim2.fromScale(1 / self.Scale, 1 / self.Scale)
		if overlayScale and overlayScaled then
			overlayScale.Scale = self.Scale
			overlayScaled.Size = scaled.Size
		end
	end
	resize()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end

	local hud = Components.new(
		"Frame",
		{ Name = "HUD", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = scaled }
	)
	self.Hud = hud
	self.WindowsFolder = Components.new(
		"Frame",
		{ Name = "Windows", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = scaled }
	)

	self.Overlay = Components.new("ScreenGui", {
		Name = "Overlay",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 30,
		IgnoreGuiInset = true,
		Parent = playerGui,
	})
	-- Scaled layer for authored-size overlays (cinematics, banners, stamps). Things that
	-- use raw screen pixels (waypoint arrow, flashes) go straight on Overlay.
	local frame, frameScale = scaledFrame(self.Overlay :: ScreenGui)
	overlayScaled = frame
	overlayScale = frameScale
	self.OverlayScaled = frame
	resize()

	blur = Instance.new("BlurEffect")
	blur.Name = "UIBlur"
	blur.Size = 0
	blur.Parent = Lighting

	buildMenu(root)

	-- Build every window up front (hidden) so opening is instant.
	local context = self:Context()
	for _, module in UIFolder.Windows:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, result = pcall(function()
				return (require(module) :: any)(context)
			end)
			if ok and result then
				self:RegisterWindow(result.Name, result)
			else
				warn("[UI] Window failed to build:", module.Name, result)
			end
		end
	end
end

return UIController
