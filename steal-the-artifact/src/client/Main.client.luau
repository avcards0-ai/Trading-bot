--[[
	Client bootstrap. Same Init -> Start pattern as the server.
]]

local Players = game:GetService("Players")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local controllersFolder = script.Parent.Controllers

local ORDER = {
	"DataController",
	"SoundController",
	"UIController",
	"HUDController",
	"AnnouncementController",
	"EffectsController",
	"ArtifactVisualsController",
	"WorldController",
	"CharacterController",
	"InputController",
	"InteractController",
}

local controllers: { [string]: any } = {}
local ordered = {}
for _, name in ORDER do
	local module = controllersFolder:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), "Missing controller " .. name)
	local controller = require(module) :: any
	controllers[name] = controller
	table.insert(ordered, controller)
end
for _, module in controllersFolder:GetChildren() do
	if module:IsA("ModuleScript") and not controllers[module.Name] then
		local controller = require(module) :: any
		controllers[module.Name] = controller
		table.insert(ordered, controller)
	end
end

for _, controller in ordered do
	if type(controller.Init) == "function" then
		controller:Init(controllers)
	end
end
for _, controller in ordered do
	if type(controller.Start) == "function" then
		local ok, err = pcall(controller.Start, controller)
		if not ok then
			warn("[Client] Controller failed to start:", err)
		end
	end
end

-- Tell the loading screen we're ready (local attribute; never replicated).
Players.LocalPlayer:SetAttribute("ClientReady", true)
