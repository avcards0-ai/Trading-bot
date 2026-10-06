--[[
	Server bootstrap.
	1. Creates every remote (Net.init)
	2. Init() every service (they grab references to each other here, nothing else)
	3. Start() every service (MapService first, so the world exists before anything uses it)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local RequestRouter = require(script.Parent.RequestRouter)

Net.init()
-- Hook the Request remote immediately; services register their actions during Init/Start.
RequestRouter.start()

local servicesFolder = script.Parent.Services

-- Explicit start order: world first, then data, then everything that depends on both.
local ORDER = {
	"MapService",
	"AnnouncementService",
	"DataService",
	"EconomyService",
	"PlayerService",
	"CarryService",
	"InventoryService",
	"ArtifactService",
	"PlotService",
	"SecurityService",
	"GuardService",
	"CombatService",
	"RaidService",
	"VaultDoorService",
	"TravelService",
	"AntiCheatService",
	"QuestService",
	"AchievementService",
	"DailyRewardService",
	"CodeService",
	"CosmeticService",
	"ShopService",
	"LeaderboardService",
	"EventService",
}

local services: { [string]: any } = {}
local ordered = {}

for _, name in ORDER do
	local module = servicesFolder:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), "Missing service " .. name)
	local service = require(module) :: any
	services[name] = service
	table.insert(ordered, service)
end
-- Pick up any service that was added without being listed above.
for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") and not services[module.Name] then
		local service = require(module) :: any
		services[module.Name] = service
		table.insert(ordered, service)
	end
end

for _, service in ordered do
	if type(service.Init) == "function" then
		service:Init(services)
	end
end

for _, service in ordered do
	if type(service.Start) == "function" then
		local ok, err = pcall(service.Start, service)
		if not ok then
			warn("[Server] Service failed to start:", err)
		end
	end
end

print("[Server] STEAL THE ARTIFACT is running")
