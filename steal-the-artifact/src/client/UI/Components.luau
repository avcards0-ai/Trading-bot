--[[
	Components
	Tiny UI kit used by every window: create helpers, juicy buttons (hover / press scale +
	click sound), panels, windows with headers, tabs, progress bars and scrolling lists.
	Everything works with mouse, touch and gamepad selection.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local C = Theme.Colors
local Components = {}

local soundHandler: ((name: string) -> ())? = nil

function Components.setSoundHandler(handler: (name: string) -> ())
	soundHandler = handler
end

local function playSound(name: string)
	if soundHandler then
		soundHandler(name)
	end
end
Components.playSound = playSound

-- Create ------------------------------------------------------------------------------------

function Components.new(className: string, props: { [any]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local new = Components.new

function Components.corner(parent: Instance, radius: UDim?): UICorner
	return new("UICorner", { CornerRadius = radius or Theme.Corner, Parent = parent })
end

function Components.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = color or C.Stroke,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Components.textStroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return new("UIStroke", { Color = color or Color3.fromRGB(15, 12, 25), Thickness = thickness or 2, Parent = parent })
end

function Components.padding(parent: Instance, pixels: number, horizontal: number?): UIPadding
	return new("UIPadding", {
		PaddingTop = UDim.new(0, pixels),
		PaddingBottom = UDim.new(0, pixels),
		PaddingLeft = UDim.new(0, horizontal or pixels),
		PaddingRight = UDim.new(0, horizontal or pixels),
		Parent = parent,
	})
end

function Components.list(
	parent: Instance,
	direction: Enum.FillDirection?,
	spacing: number?,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	return new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Components.grid(parent: Instance, cell: UDim2, spacing: number?): UIGridLayout
	return new("UIGridLayout", {
		CellSize = cell,
		CellPadding = UDim2.fromOffset(spacing or 8, spacing or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Components.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

function Components.tween(
	inst: Instance,
	time: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- Labels / panels ----------------------------------------------------------------------------

export type LabelProps = { [string]: any }

function Components.label(props: LabelProps): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Heading,
		TextColor3 = C.Text,
		TextScaled = true,
		RichText = true,
		Size = UDim2.fromScale(1, 1),
	}
	for key, value in props do
		-- MaxTextSize / NoConstraint are options for this helper, not TextLabel properties.
		if key ~= "MaxTextSize" and key ~= "NoConstraint" then
			defaults[key] = value
		end
	end
	local label = new("TextLabel", defaults)
	if not props.NoConstraint then
		new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 40, MinTextSize = 8, Parent = label })
	end
	return label
end

function Components.panel(props: { [string]: any }): Frame
	local defaults = {
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
	}
	for key, value in props do
		if key ~= "Stroke" and key ~= "Radius" and key ~= "Gradient" then
			defaults[key] = value
		end
	end
	local frame = new("Frame", defaults)
	Components.corner(frame, props.Radius)
	if props.Stroke ~= false then
		Components.stroke(frame, props.Stroke or C.Stroke, 1.5, 0.35)
	end
	if props.Gradient ~= false then
		local base = defaults.BackgroundColor3 :: Color3
		Components.gradient(frame, Theme.lighten(base, 0.06), Theme.darken(base, 0.12))
	end
	return frame
end

-- Buttons ----------------------------------------------------------------------------------

export type ButtonProps = {
	Text: string?,
	Color: Color3?,
	TextColor: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Font: Enum.Font?,
	Parent: Instance?,
	OnClick: (() -> ())?,
	Radius: UDim?,
	Name: string?,
	MaxTextSize: number?,
	Sound: string?,
}

function Components.button(props: ButtonProps): TextButton
	local color = props.Color or C.Primary
	local button = new("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(140, 44),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		Selectable = true,
	})
	Components.corner(button, props.Radius or Theme.SmallCorner)
	Components.stroke(button, Theme.darken(color, 0.45), 2, 0)
	Components.gradient(button, Theme.lighten(color, 0.18), Theme.darken(color, 0.12))
	local scale = new("UIScale", { Parent = button })
	local label = Components.label({
		Name = "Label",
		Text = props.Text or "",
		Font = props.Font or Theme.Fonts.Heading,
		TextColor3 = props.TextColor or C.White,
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		MaxTextSize = props.MaxTextSize or 24,
		Parent = button,
	})
	Components.textStroke(label, 1.5)

	button.MouseEnter:Connect(function()
		if button.Active then
			Components.tween(scale, 0.12, { Scale = 1.05 })
			playSound("Hover")
		end
	end)
	button.MouseLeave:Connect(function()
		Components.tween(scale, 0.12, { Scale = 1 })
	end)
	button.SelectionGained:Connect(function()
		Components.tween(scale, 0.12, { Scale = 1.06 })
	end)
	button.SelectionLost:Connect(function()
		Components.tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		if button.Active then
			Components.tween(scale, 0.06, { Scale = 0.94 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		Components.tween(scale, 0.1, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		if not button.Active then
			return
		end
		playSound(props.Sound or "Click")
		if props.OnClick then
			props.OnClick()
		end
	end)
	button:SetAttribute("BaseColor", color)
	if props.Parent then
		button.Parent = props.Parent
	end
	return button
end

-- Changes a button's label / color / enabled state.
function Components.setButton(button: TextButton, text: string?, color: Color3?, enabled: boolean?)
	local label = button:FindFirstChild("Label") :: TextLabel?
	if text and label then
		label.Text = text
	end
	if color then
		button.BackgroundColor3 = color
		local gradient = button:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(Theme.lighten(color, 0.18), Theme.darken(color, 0.12))
		end
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Theme.darken(color, 0.45)
		end
	end
	if enabled ~= nil then
		button.Active = enabled
		button.AutoButtonColor = false
		button.BackgroundTransparency = enabled and 0 or 0.45
		if label then
			label.TextTransparency = enabled and 0 or 0.35
		end
	end
end

-- Scrolling / tabs / progress ----------------------------------------------------------------

function Components.scroll(props: { [string]: any }): ScrollingFrame
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
	}
	for key, value in props do
		defaults[key] = value
	end
	return new("ScrollingFrame", defaults)
end

-- Horizontal tab bar. Returns the bar and a function to select a tab by name.
function Components.tabs(
	parent: Instance,
	names: { string },
	onSelect: (string) -> (),
	size: UDim2?,
	position: UDim2?
): (Frame, (string) -> ())
	local bar = new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = size or UDim2.new(1, 0, 0, 40),
		Position = position or UDim2.new(),
		Parent = parent,
	})
	Components.list(bar, Enum.FillDirection.Horizontal, 6)
	local buttons: { [string]: TextButton } = {}
	local function select(name: string)
		for tabName, button in buttons do
			Components.setButton(button, nil, tabName == name and C.Accent or C.PanelLighter)
			local label = button:FindFirstChild("Label") :: TextLabel?
			if label then
				label.TextColor3 = tabName == name and Color3.fromRGB(40, 25, 0) or C.Text
			end
		end
		onSelect(name)
	end
	local width = 1 / math.max(#names, 1)
	for i, name in names do
		buttons[name] = Components.button({
			Name = name,
			Text = name,
			Color = C.PanelLighter,
			Size = UDim2.new(width, -6, 1, 0),
			LayoutOrder = i,
			MaxTextSize = 20,
			Parent = bar,
			OnClick = function()
				select(name)
			end,
		})
	end
	return bar, select
end

function Components.progress(parent: Instance, props: { [string]: any }): (Frame, (number, string?) -> ())
	local bar = new("Frame", {
		Name = props.Name or "Progress",
		Size = props.Size or UDim2.new(1, 0, 0, 16),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = props.Back or Color3.fromRGB(15, 15, 25),
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = parent,
	})
	Components.corner(bar, UDim.new(1, 0))
	Components.stroke(bar, Color3.fromRGB(10, 10, 15), 1.5, 0.2)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = props.Color or C.Success,
		BorderSizePixel = 0,
		Parent = bar,
	})
	Components.corner(fill, UDim.new(1, 0))
	Components.gradient(fill, Theme.lighten(props.Color or C.Success, 0.25), props.Color or C.Success)
	local text = Components.label({
		Name = "Text",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		MaxTextSize = props.TextSize or 14,
		Parent = bar,
	})
	Components.textStroke(text, 1.2)
	local function set(fraction: number, label: string?)
		fraction = math.clamp(fraction, 0, 1)
		Components.tween(fill, 0.25, { Size = UDim2.fromScale(fraction, 1) })
		fill.Visible = fraction > 0.001
		if label then
			text.Text = label
		end
	end
	return bar, set
end

-- Small pill: "💰 1.2K"
function Components.pill(parent: Instance, icon: string, color: Color3, props: { [string]: any }?): (Frame, TextLabel)
	local frame = Components.panel({
		Name = props and props.Name or "Pill",
		Size = props and props.Size or UDim2.fromOffset(150, 40),
		Position = props and props.Position or UDim2.new(),
		BackgroundColor3 = C.Background,
		LayoutOrder = props and props.LayoutOrder or 0,
		Radius = UDim.new(1, 0),
		Stroke = color,
		Parent = parent,
	})
	Components.label({
		Name = "Icon",
		Text = icon,
		Size = UDim2.new(0, 32, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		Parent = frame,
	})
	local value = Components.label({
		Name = "Value",
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Size = UDim2.new(1, -46, 1, -10),
		Position = UDim2.fromOffset(40, 5),
		MaxTextSize = 26,
		Parent = frame,
	})
	Components.textStroke(value, 1.5)
	return frame, value
end

-- A notification dot for menu buttons. Returns a setter.
function Components.badge(parent: Instance): (number) -> ()
	local dot = new("Frame", {
		Name = "Badge",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -14, 0, -6),
		BackgroundColor3 = C.Danger,
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	})
	Components.corner(dot, UDim.new(1, 0))
	Components.stroke(dot, C.White, 2)
	local text = Components.label({ Text = "!", ZIndex = 11, MaxTextSize = 14, Parent = dot })
	return function(count: number)
		dot.Visible = count > 0
		text.Text = count > 9 and "9+" or tostring(count)
	end
end

-- On/off switch. Returns the button and a setter.
function Components.toggle(
	parent: Instance,
	props: { [string]: any },
	onChange: (boolean) -> ()
): (TextButton, (boolean) -> ())
	local state = props.Value == true
	local button = Components.button({
		Text = "",
		Color = C.PanelLighter,
		Size = props.Size or UDim2.fromOffset(110, 40),
		Position = props.Position,
		LayoutOrder = props.LayoutOrder,
		Parent = parent,
	})
	local function render()
		Components.setButton(button, state and "ON" or "OFF", state and C.Success or C.PanelLighter)
	end
	button.Activated:Connect(function()
		state = not state
		render()
		onChange(state)
	end)
	render()
	return button, function(value: boolean)
		state = value
		render()
	end
end

-- Horizontal 0..1 slider (mouse, touch and gamepad left/right).
function Components.slider(
	parent: Instance,
	props: { [string]: any },
	onChange: (number) -> ()
): (Frame, (number) -> ())
	local value = math.clamp(props.Value or 0.5, 0, 1)
	local track = new("TextButton", {
		Name = "Slider",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(15, 15, 25),
		Size = props.Size or UDim2.fromOffset(220, 16),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		Selectable = true,
		Parent = parent,
	})
	Components.corner(track, UDim.new(1, 0))
	local fill = new("Frame", {
		BackgroundColor3 = props.Color or C.Primary,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(value, 1),
		Parent = track,
	})
	Components.corner(fill, UDim.new(1, 0))
	local knob = new("Frame", {
		BackgroundColor3 = C.White,
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(value, 0.5),
		ZIndex = 3,
		Parent = track,
	})
	Components.corner(knob, UDim.new(1, 0))
	Components.stroke(knob, C.Stroke, 2)
	local function set(v: number, notify: boolean?)
		value = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
		if notify then
			onChange(value)
		end
	end
	local dragging = false
	local UserInputService = game:GetService("UserInputService")
	local function fromInput(input: InputObject)
		local x = input.Position.X - track.AbsolutePosition.X
		set(x / math.max(track.AbsoluteSize.X, 1), true)
	end
	track.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			fromInput(input)
		elseif input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then
			set(value + 0.1, true)
		elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then
			set(value - 0.1, true)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			fromInput(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	return track :: any, function(v: number)
		set(v, false)
	end
end

-- Pop-in animation for newly shown frames.
function Components.pop(inst: GuiObject, from: number?)
	local scale = inst:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = inst })
	scale.Scale = from or 0.6
	Components.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

return Components
