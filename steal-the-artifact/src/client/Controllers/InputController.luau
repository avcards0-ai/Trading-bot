--[[
	InputController
	One mapping for every platform:
	  PC       F bonk · Q dash · R home · G emotes · B/V/U/N/J/K/L/Y/H/P windows · E interact
	  Console  RT bonk · RB dash · Y home · D-pad down emotes · D-pad up menu · B close · X interact
	  Mobile   on-screen action buttons (HUD) + the default thumbstick / jump
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local InputController = { Name = "InputController" }

local controllers: { [string]: any }

function InputController:Init(all)
	controllers = all
end

local function action(name: string)
	local character = controllers.CharacterController
	if name == "Bonk" then
		character:Bonk()
	elseif name == "Dash" then
		character:Dash()
	elseif name == "Home" then
		character:Recall()
	elseif name == "Emote" then
		character:ToggleWheel()
	end
end

local KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.F] = "Bonk",
	[Enum.KeyCode.Q] = "Dash",
	[Enum.KeyCode.R] = "Home",
	[Enum.KeyCode.G] = "Emote",
	[Enum.KeyCode.ButtonR2] = "Bonk",
	[Enum.KeyCode.ButtonR1] = "Dash",
	[Enum.KeyCode.ButtonY] = "Home",
	[Enum.KeyCode.DPadDown] = "Emote",
}

function InputController:Start()
	local ui = controllers.UIController
	local windowKeys: { [Enum.KeyCode]: string } = {}
	for _, entry in ui.Menu do
		windowKeys[entry.Key] = entry.Name
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		-- Close windows with gamepad B even if the GUI consumed the input
		if key == Enum.KeyCode.ButtonB and ui.OpenWindow then
			ui:Close()
			return
		end
		if processed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			and ui.OpenWindow == nil
			and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		then
			-- Shift-lock players can click to bonk
			action("Bonk")
			return
		end
		local mapped = KEYS[key]
		if mapped then
			action(mapped)
			return
		end
		local window = windowKeys[key]
		if window then
			ui:Toggle(window)
			return
		end
		if key == Enum.KeyCode.DPadUp then
			local menu = ui.Root and ui.Root:FindFirstChild("Scaled") and ui.Root.Scaled:FindFirstChild("Menu")
			local first = menu and menu:FindFirstChild("Inventory")
			if first then
				GuiService.SelectedObject = first
			end
		end
	end)

	-- On-screen action buttons (mobile + mouse)
	for name, button in controllers.HUDController.Buttons do
		button.Activated:Connect(function()
			action(name)
		end)
	end
end

return InputController
