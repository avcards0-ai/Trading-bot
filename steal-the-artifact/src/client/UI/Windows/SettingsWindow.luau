--[[
	Settings - audio, visual quality (great for low-end phones), camera shake, feed,
	global announcements, reduced flashing, plus a controls reference.
]]

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local C = Theme.Colors

return function(ctx)
	local shell = ctx.UI:Shell("Settings", "Settings", "⚙️", C.Stroke, UDim2.fromOffset(760, 540))
	local content = shell.Content
	local list = Components.scroll({ Parent = content })
	Components.list(list, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	Components.padding(list, 4)

	local setters: { [string]: (any) -> () } = {}
	local pending: { [string]: any } = {}

	local function save(key: string, value: any)
		pending[key] = value
		task.delay(0.4, function()
			if pending[key] == value then
				pending[key] = nil
				ctx.Net.request("UpdateSetting", key, value)
			end
		end)
		-- Apply instantly on the client mirror so sounds/visuals react right away
		local settings = ctx.Data.Data.Settings
		if type(settings) == "table" then
			settings[key] = value
			ctx.Data:Predict("Settings", settings)
		end
	end

	local function row(order: number, title: string, subtitle: string): Frame
		local frame = Components.panel({
			Size = UDim2.new(1, -8, 0, 64),
			BackgroundColor3 = C.Panel,
			LayoutOrder = order,
			Parent = list,
		})
		local titleLabel = Components.label({
			Text = title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -280, 0, 26),
			Position = UDim2.fromOffset(14, 6),
			MaxTextSize = 20,
			Parent = frame,
		})
		Components.textStroke(titleLabel, 1.2)
		Components.label({
			Text = subtitle,
			Font = Theme.Fonts.Body,
			TextColor3 = C.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -280, 0, 20),
			Position = UDim2.fromOffset(14, 34),
			MaxTextSize = 14,
			Parent = frame,
		})
		return frame
	end

	local function sliderRow(order: number, key: string, title: string, subtitle: string)
		local frame = row(order, title, subtitle)
		local _, set = Components.slider(
			frame,
			{ Size = UDim2.fromOffset(230, 14), Position = UDim2.new(1, -250, 0.5, -7) },
			function(value)
				save(key, math.floor(value * 100 + 0.5) / 100)
			end
		)
		setters[key] = set
	end

	local function toggleRow(order: number, key: string, title: string, subtitle: string)
		local frame = row(order, title, subtitle)
		local _, set = Components.toggle(
			frame,
			{ Size = UDim2.fromOffset(120, 42), Position = UDim2.new(1, -134, 0.5, -21) },
			function(value)
				save(key, value)
			end
		)
		setters[key] = set
	end

	sliderRow(1, "Music", "🎵 Music volume", "Background tracks")
	sliderRow(2, "SFX", "🔊 Sound effects", "Bonks, alarms, cha-ching")
	local vfx = row(3, "✨ Visual effects", "Low = fewer particles (great for older phones)")
	local vfxButton = Components.button({
		Text = "High",
		Color = C.Primary,
		Size = UDim2.fromOffset(120, 42),
		Position = UDim2.new(1, -134, 0.5, -21),
		Parent = vfx,
	})
	vfxButton.Activated:Connect(function()
		local settings = ctx.Data.Data.Settings or {}
		local nextValue = settings.VFX == "High" and "Low" or "High"
		Components.setButton(vfxButton, nextValue)
		save("VFX", nextValue)
	end)
	toggleRow(4, "Shake", "📳 Camera shake", "Screen shake on bonks, fails and explosions")
	toggleRow(5, "Feed", "📰 Steal feed", "The live feed of steals, raids and bonks")
	toggleRow(6, "Global", "🌍 Global announcements", "Legendary steals from other servers")
	toggleRow(7, "ReduceFlashing", "🕶️ Reduce flashing", "Turns off screen flashes and alarm pulses")

	local controlsText = table.concat({
		"<b>CONTROLS</b>",
		"PC: WASD move · Space jump · E interact/steal · F bonk · Q dash · R home · G emotes",
		"     B loot · V vault · U upgrades · N shop · J quests · K collection · L leaders · Y daily · H codes · P settings",
		"Console: X interact · RT bonk · RB dash · Y home · D-pad ↓ emotes · D-pad ↑ menu · B close",
		"Mobile: on-screen buttons for bonk, dash, home and emotes",
	}, "\n")
	local controls = Components.panel({
		Size = UDim2.new(1, -8, 0, 130),
		BackgroundColor3 = C.PanelLight,
		LayoutOrder = 20,
		Parent = list,
	})
	Components.label({
		Text = controlsText,
		Font = Theme.Fonts.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -24, 1, -16),
		Position = UDim2.fromOffset(12, 8),
		MaxTextSize = 15,
		Parent = controls,
	})

	local function refresh()
		local settings = ctx.Data.Data.Settings
		if type(settings) ~= "table" then
			return
		end
		for key, set in setters do
			if settings[key] ~= nil then
				set(settings[key])
			end
		end
		Components.setButton(vfxButton, settings.VFX or "High")
	end

	return {
		Name = "Settings",
		Frame = shell.Frame,
		Close = shell.Close,
		Refresh = refresh,
		FirstSelectable = vfxButton,
	}
end
