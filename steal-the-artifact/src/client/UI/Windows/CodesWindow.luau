--[[
	Codes - redeem promo codes for free Cash and Gems.
]]

local UI = script.Parent.Parent
local Components = require(UI.Components)
local Theme = require(UI.Theme)

local C = Theme.Colors

return function(ctx)
	local shell = ctx.UI:Shell("Codes", "Codes", "🎟️", Color3.fromRGB(255, 80, 100), UDim2.fromOffset(620, 360))
	local content = shell.Content

	Components.label({
		Text = "Follow the game and join the group for new codes! Codes are not case sensitive.",
		Font = Theme.Fonts.Body,
		TextWrapped = true,
		TextColor3 = C.SubText,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 6),
		MaxTextSize = 17,
		Parent = content,
	})
	local boxFrame = Components.panel({
		Size = UDim2.new(1, -20, 0, 64),
		Position = UDim2.fromOffset(10, 70),
		BackgroundColor3 = C.PanelLight,
		Parent = content,
	})
	local box = Components.new("TextBox", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -12),
		Position = UDim2.fromOffset(12, 6),
		Font = Theme.Fonts.Heading,
		PlaceholderText = "Enter code here...",
		PlaceholderColor3 = C.Muted,
		Text = "",
		TextColor3 = C.Text,
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = boxFrame,
	})
	Components.new("UITextSizeConstraint", { MaxTextSize = 30, Parent = box })
	local result = Components.label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 146),
		MaxTextSize = 20,
		Parent = content,
	})
	Components.textStroke(result, 1.2)

	local busy = false
	local function redeem()
		if busy then
			return
		end
		local code = box.Text:gsub("%s+", "")
		if #code == 0 then
			return
		end
		busy = true
		local response = ctx.Net.request("RedeemCode", string.sub(code, 1, 32))
		busy = false
		result.Text = response.msg or (response.ok and "Redeemed!" or "Nope!")
		result.TextColor3 = response.ok and C.Success or C.Danger
		if response.ok then
			box.Text = ""
			ctx.Sound:Play("Purchase")
			ctx.Controllers.EffectsController:Confetti(C.Accent, 40)
		else
			ctx.Sound:Play("Error")
		end
	end
	local button = Components.button({
		Text = "REDEEM",
		Color = C.Success,
		Size = UDim2.fromOffset(240, 56),
		Position = UDim2.new(0.5, -120, 1, -66),
		MaxTextSize = 26,
		Parent = content,
		OnClick = redeem,
	})
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			redeem()
		end
	end)

	return {
		Name = "Codes",
		Frame = shell.Frame,
		Close = shell.Close,
		FirstSelectable = box,
		OnOpen = function()
			result.Text = ""
		end,
		Button = button,
	}
end
