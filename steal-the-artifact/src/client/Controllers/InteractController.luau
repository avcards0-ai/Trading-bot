--[[
	InteractController
	Client-side ProximityPrompt behaviour:
	  * Prompts tagged OpensUI (shops, quest board, terminals...) open the matching window
	  * Steal / crack prompts get the player's own hold time (gloves, perks); the server
	    validates the same numbers
	  * Your own displayed artifacts and your own vault door never show a steal / crack prompt
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progression = require(ReplicatedStorage.Shared.Progression)

local player = Players.LocalPlayer

local InteractController = { Name = "InteractController" }

local controllers: { [string]: any }

function InteractController:Init(all)
	controllers = all
end

local function findModelAttribute(prompt: ProximityPrompt, name: string): any
	local node: Instance? = prompt.Parent
	while node and node ~= workspace do
		local value = node:GetAttribute(name)
		if value ~= nil then
			return value
		end
		node = node.Parent
	end
	return nil
end

local function adjust(prompt: ProximityPrompt)
	local data = controllers.DataController.Data
	local baseHold = prompt:GetAttribute("BaseHold")
	if prompt:GetAttribute("Steal") then
		if findModelAttribute(prompt, "OwnerUserId") == player.UserId then
			prompt.Enabled = false
			return
		end
		if type(baseHold) == "number" then
			prompt.HoldDuration = baseHold * Progression.holdMultiplier(data)
		end
	elseif prompt.Name == "CrackPrompt" then
		local index = prompt:GetAttribute("PlotIndex")
		if index == controllers.DataController:GetSession("PlotIndex") then
			prompt.ActionText = "Open Door"
			prompt.HoldDuration = 0
		elseif type(baseHold) == "number" then
			prompt.ActionText = "Crack Vault"
			prompt.HoldDuration = baseHold * Progression.crackMultiplier(data)
		end
	end
end

function InteractController:Start()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		adjust(prompt)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local uiName = prompt:GetAttribute("OpensUI")
		if type(uiName) == "string" then
			controllers.UIController:Open(uiName)
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if prompt:GetAttribute("Steal") or prompt.Name == "CrackPrompt" then
			controllers.SoundController:Play("Hover")
		end
	end)
end

return InteractController
