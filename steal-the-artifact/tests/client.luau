--[[
	Client UI smoke test. Run from the project folder:

	    lune run tests/client

	Boots every client controller against stubbed services, feeds the UI a realistic data
	snapshot, then opens and refreshes every window. Lune instances validate every property
	write, so a typo anywhere in the UI code fails this test. Lune doesn't implement GUI
	events, so instances are wrapped in proxies that hand out inert signals for events.
]]

local process = require("@lune/process")
local task = require("@lune/task")

local H = require("./harness")
local roblox = H.roblox
local test, check = H.test, H.check

print("STEAL THE ARTIFACT - client UI smoke test\n")

-- Instance proxies ----------------------------------------------------------------------------

local proxies = setmetatable({}, { __mode = "k" })
local Proxy = {}

local EVENTS = {
	Activated = true,
	MouseEnter = true,
	MouseLeave = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseButton1Click = true,
	SelectionGained = true,
	SelectionLost = true,
	InputBegan = true,
	InputChanged = true,
	InputEnded = true,
	FocusLost = true,
	Focused = true,
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	AncestryChanged = true,
	Triggered = true,
	PromptButtonHoldBegan = true,
	PromptButtonHoldEnded = true,
	Died = true,
	Running = true,
	Touched = true,
	Completed = true,
	DescendantAdded = true,
}

local wrap, unwrap

local function isProxy(value)
	return type(value) == "table" and rawget(value, "__inst") ~= nil
end

unwrap = function(value)
	if isProxy(value) then
		return rawget(value, "__inst")
	end
	return value
end

wrap = function(value)
	if typeof(value) == "Instance" then
		local existing = proxies[value]
		if existing then
			return existing
		end
		local proxy = setmetatable({ __inst = value }, Proxy)
		proxies[value] = proxy
		return proxy
	elseif type(value) == "table" and not isProxy(value) and getmetatable(value) == nil then
		local out = {}
		for k, v in value do
			out[k] = wrap(v)
		end
		return out
	end
	return value
end

local function wrapAll(...)
	local results = table.pack(...)
	for i = 1, results.n do
		results[i] = wrap(results[i])
	end
	return table.unpack(results, 1, results.n)
end

local FALLBACK_METHODS = {
	GetPropertyChangedSignal = function()
		return H.signalStub()
	end,
	GetAttributeChangedSignal = function()
		return H.signalStub()
	end,
	PivotTo = function() end,
	ScaleTo = function() end,
	GetPivot = function()
		return roblox.CFrame.new()
	end,
	GetBoundingBox = function()
		return roblox.CFrame.new(), roblox.Vector3.new(2, 2, 2)
	end,
	IsDescendantOf = function(inst, ancestor)
		local node = inst.Parent
		while node do
			if node == ancestor then
				return true
			end
			node = node.Parent
		end
		return false
	end,
	CaptureFocus = function() end,
	ReleaseFocus = function() end,
}

-- Per-instance event objects whose handlers the test can fire.
local events = setmetatable({}, { __mode = "k" })
local function eventFor(inst, key)
	local byKey = events[inst]
	if not byKey then
		byKey = {}
		events[inst] = byKey
	end
	local signal = byKey[key]
	if not signal then
		local handlers = {}
		signal = {
			Handlers = handlers,
			Connect = function(_, fn)
				table.insert(handlers, fn)
				return { Disconnect = function() end, Connected = true }
			end,
			Once = function(_, fn)
				table.insert(handlers, fn)
				return { Disconnect = function() end }
			end,
			Wait = function() end,
		}
		byKey[key] = signal
	end
	return signal
end

local function fire(proxy, key: string, ...)
	local byKey = events[unwrap(proxy)]
	local signal = byKey and byKey[key]
	if signal then
		for _, fn in signal.Handlers do
			fn(...)
		end
	end
end

Proxy.__index = function(self, key)
	local inst = rawget(self, "__inst")
	if EVENTS[key] then
		return eventFor(inst, key)
	end
	local ok, value = pcall(function()
		return inst[key]
	end)
	if not ok then
		local fallback = FALLBACK_METHODS[key]
		if fallback then
			return function(_, ...)
				return wrapAll(fallback(inst, ...))
			end
		end
		-- Engine methods Lune doesn't implement (Sound:Play, ParticleEmitter:Emit, ...).
		-- Reads and method names are already verified by luau-lsp; this test is about
		-- property WRITES, which stay strictly validated in __newindex below.
		return function() end
	end
	if type(value) == "function" then
		return function(_, ...)
			local args = table.pack(...)
			for i = 1, args.n do
				args[i] = unwrap(args[i])
			end
			return wrapAll(value(inst, table.unpack(args, 1, args.n)))
		end
	end
	return wrap(value)
end

Proxy.__newindex = function(self, key, value)
	local inst = rawget(self, "__inst")
	local ok, err = pcall(function()
		inst[key] = unwrap(value)
	end)
	if not ok then
		error(string.format("%s.%s = %s failed: %s", inst.ClassName, tostring(key), tostring(value), tostring(err)), 2)
	end
end
Proxy.__tostring = function(self)
	return "Proxy(" .. tostring(rawget(self, "__inst")) .. ")"
end
Proxy.__eq = function(a, b)
	return unwrap(a) == unwrap(b)
end

-- Client environment -----------------------------------------------------------------------------

local env = H.env
env.Instance = {
	new = function(className: string)
		return wrap(roblox.Instance.new(className))
	end,
}
local realTypeof = typeof
env.typeof = function(value)
	if isProxy(value) then
		return "Instance"
	end
	return realTypeof(value)
end

local services = H.services
services.RunService.IsServer = function()
	return false
end
services.RunService.IsClient = function()
	return true
end

local playerGui = wrap(roblox.Instance.new("Folder"))
playerGui.Name = "PlayerGui"
local localPlayer = services.Players.LocalPlayer
localPlayer.WaitForChild = function(_, name)
	if name == "PlayerGui" then
		return playerGui
	end
	return nil
end
localPlayer.GetAttributeChangedSignal = function()
	return H.signalStub()
end

local lighting = wrap(roblox.Instance.new("DataModel"):GetService("Lighting"))
local realGetService = env.game.GetService
env.game.GetService = function(self, name)
	if name == "Lighting" then
		return lighting
	elseif name == "SoundService" then
		return wrap(roblox.Instance.new("Folder"))
	elseif name == "StarterGui" then
		return { SetCoreGuiEnabled = function() end }
	elseif name == "ProximityPromptService" then
		return { PromptShown = H.signalStub(), PromptTriggered = H.signalStub(), PromptButtonHoldBegan = H.signalStub() }
	elseif name == "MarketplaceService" then
		return { PromptProductPurchase = function() end, PromptGamePassPurchase = function() end }
	elseif name == "Debris" then
		return { AddItem = function() end }
	end
	return realGetService(self, name)
end

local camera = {
	ViewportSize = roblox.Vector2.new(1280, 720),
	CFrame = roblox.CFrame.new(),
	FieldOfView = 70,
	GetPropertyChangedSignal = function()
		return H.signalStub()
	end,
	WorldToViewportPoint = function()
		return roblox.Vector3.new(640, 360, 10), true
	end,
}
H.workspace.CurrentCamera = camera
-- Let scripts parent things to `workspace` (unwrap() turns the stub into this Folder).
rawset(H.workspace, "__inst", roblox.Instance.new("Folder"))
H.workspace.Terrain = wrap(roblox.Instance.new("Folder"))

-- Remotes: capture client handlers so the test can push server messages.
local handlers: { [string]: (...any) -> () } = {}
local function remoteStub(name: string)
	return {
		OnClientEvent = {
			Connect = function(_, fn)
				handlers[name] = fn
				return { Disconnect = function() end }
			end,
		},
		FireServer = function() end,
		InvokeServer = function(_, action)
			return {
				ok = true,
				msg = nil,
				data = action == "GetLeaderboards" and { Global = {}, Server = {}, GlobalAvailable = false } or nil,
			}
		end,
	}
end
local remotes = {
	WaitForChild = function(_, name)
		return remoteStub(name)
	end,
	FindFirstChild = function(_, name)
		return remoteStub(name)
	end,
}
services.ReplicatedStorage.WaitForChild = function(_, name)
	if name == "Remotes" then
		return remotes
	end
	return nil
end
services.ReplicatedStorage.FindFirstChild = services.ReplicatedStorage.WaitForChild

-- Boot -------------------------------------------------------------------------------------------

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
	"WorldFXController",
	"OnboardingController",
}
-- Capture RunService.Stepped so per-frame logic (the punch animation) can be driven here.
local steppedHandlers = {}
services.RunService.Stepped = {
	Connect = function(_, fn)
		table.insert(steppedHandlers, fn)
		return { Disconnect = function() end, Connected = true }
	end,
}

local controllers = {}
test("require every controller", function()
	for _, name in ORDER do
		controllers[name] = H.require("src/client/Controllers/" .. name .. ".luau")
	end
end)
test("Init + Start every controller (builds HUD + all windows)", function()
	for _, name in ORDER do
		local controller = controllers[name]
		if controller.Init then
			controller:Init(controllers)
		end
	end
	for _, name in ORDER do
		local controller = controllers[name]
		if controller.Start then
			local ok, err = pcall(controller.Start, controller)
			check(ok, name .. ":Start failed: " .. tostring(err))
		end
	end
end)

local Artifacts = H.require("src/shared/Config/Artifacts.luau")
local snapshot = {
	Data = {
		Cash = 123456,
		Gems = 250,
		Level = 12,
		XP = 40,
		Rebirths = 1,
		PrestigeTokens = 2,
		Gear = { Backpack = 2, Sneakers = 1, Gloves = 0 },
		Vault = { Display = 1, Storage = 0 },
		Security = { Door = 1, Lasers = 2, Cameras = 1, Traps = 0, Guards = 0, Alarm = 3 },
		Perks = { GoldenTouch = 1 },
		Artifacts = {},
		Displayed = {},
		Discovered = {},
		Stats = { Steals = 12, Secured = 9, Raids = 1, TimesRaided = 2, Defends = 1, Bonks = 4, TotalEarned = 50000 },
		Quests = {
			Missions = {
				{ Id = "steal_any", Goal = 5, Progress = 5, Claimed = false },
				{ Id = "secure_value", Goal = 800, Progress = 100, Claimed = false },
				{ Id = "sell", Goal = 4, Progress = 1, Claimed = false },
			},
			Daily = {
				Day = 1,
				List = {
					{ Id = "d_steal", Goal = 20, Progress = 3, Claimed = false },
					{ Id = "d_bonk", Goal = 8, Progress = 8, Claimed = true },
					{ Id = "d_value", Goal = 3000, Progress = 0, Claimed = false },
				},
				BonusClaimed = false,
			},
		},
		Achievements = { first_steal = 1 },
		CollectionClaims = {},
		DailyReward = { Streak = 2, Consecutive = 2, LastClaim = 0 },
		Cosmetics = {
			Owned = { skin_default = true, emote_wave = true, emote_point = true, trail_fire = true },
			Equipped = { Trail = "trail_fire", Aura = "", VaultSkin = "skin_default", Title = "" },
			Emotes = { "emote_wave", "emote_point" },
			Loadouts = {
				["1"] = {
					Trail = "trail_fire",
					Aura = "",
					VaultSkin = "skin_default",
					Title = "",
					Emotes = { "emote_wave" },
				},
			},
		},
		Titles = { Professional = true },
		Settings = {
			Music = 0.5,
			SFX = 0.8,
			VFX = "High",
			Shake = true,
			Feed = true,
			Global = true,
			ReduceFlashing = false,
		},
	},
	Session = {
		Carried = {},
		PlotIndex = 3,
		RecallReadyAt = 0,
		ShieldEnds = 0,
		IsVIP = false,
		HasLocker = false,
		Income = 4.2,
		SecurePad = roblox.Vector3.new(10, 1, 10),
	},
}
for i, def in Artifacts.List do
	if i % 3 == 0 then
		local uid = "uid" .. i
		snapshot.Data.Artifacts[uid] = { Id = def.Id, M = (i % 9 == 0) and "Shiny" or nil, T = 0, Z = "Museum" }
		snapshot.Data.Discovered[def.Id] = 1
		if #snapshot.Data.Displayed < 6 then
			table.insert(snapshot.Data.Displayed, uid)
		end
	end
end
snapshot.Session.Carried = {
	{ Uid = "c1", Id = "golden_idol", Z = "Temple", Source = "World", StolenAt = 0 },
	{ Uid = "c2", Id = "rubber_duck", M = "Rainbow", Z = "Marketplace", Source = "World", StolenAt = 0 },
}

test("DataInit snapshot drives HUD + windows", function()
	check(handlers.DataInit ~= nil, "DataController did not listen for DataInit")
	handlers.DataInit(snapshot)
	task.wait(0.1)
end)

local ui = controllers.UIController
for _, name in
	{ "Inventory", "Vault", "Upgrades", "Shop", "Quests", "Collection", "Leaderboards", "Daily", "Codes", "Settings" }
do
	test("window " .. name .. " opens and refreshes", function()
		local window = ui:GetWindow(name)
		check(window ~= nil, "window not registered: " .. name)
		ui:Open(name)
		if window.Refresh then
			window.Refresh()
		end
		task.wait(0.05)
		check(ui.OpenWindow == name, "window did not open")
		ui:Close()
	end)
end

-- Monkey test: click every button in every window (tabs, buy, equip, sell, claim...).
local function buttonsIn(root): { any }
	local list = {}
	for _, child in root:GetDescendants() do
		if child:IsA("GuiButton") then
			table.insert(list, child)
		end
	end
	return list
end

for _, name in
	{ "Inventory", "Vault", "Upgrades", "Shop", "Quests", "Collection", "Leaderboards", "Daily", "Codes", "Settings" }
do
	test("click every button in " .. name, function()
		local window = ui:GetWindow(name)
		ui:Open(name)
		task.wait(0.05)
		-- Several passes: clicking a tab reveals new buttons.
		local clicked = {}
		for _ = 1, 3 do
			for _, button in buttonsIn(window.Frame) do
				local key = unwrap(button)
				if not clicked[key] and button.Name ~= "Close" then
					clicked[key] = true
					fire(button, "MouseEnter")
					fire(button, "MouseButton1Down")
					fire(button, "MouseButton1Up")
					fire(button, "Activated")
					fire(button, "MouseLeave")
					task.wait()
				end
			end
		end
		local count = 0
		for _ in clicked do
			count += 1
		end
		check(count > 0, "no buttons found in " .. name)
		print(string.format("      (%d buttons clicked)", count))
		if ui.OpenWindow ~= name then
			ui:Open(name)
		end
		ui:Close()
	end)
end

test("menu sidebar + HUD action buttons", function()
	local root = ui.Root
	for _, button in buttonsIn(root) do
		local parent = button.Parent
		if parent and (parent.Name == "Menu" or parent.Name == "Actions") then
			fire(button, "Activated")
			task.wait()
		end
	end
	ui:Close()
end)

test("server messages render (feed, toast, banner, level up, fail, cinematic, raid alert)", function()
	handlers.Feed({ Icon = "💎", Text = "<b>Bob</b> stole something", Big = true })
	handlers.Notify("success", "SECURED 3 artifacts! +$120", { Big = true })
	handlers.Notify("reward", "NEW! Golden Idol added", { Rarity = "Epic" })
	handlers.Announce({
		Kind = "Steal",
		PlayerName = "Bob",
		ArtifactId = "crown_of_kings",
		Rarity = "Legendary",
		ZoneName = "Museum",
		Global = true,
	})
	handlers.Announce({ Kind = "Event", EventId = "ArtifactRain" })
	handlers.LevelUp(13, { Cash = 520, Gems = 5 })
	handlers.Fail("Slip", "BANANA'D!", { By = "a banana peel", Dropped = 1 })
	handlers.Cinematic({ ArtifactId = "rubber_chicken", Rarity = "Secret", Mutation = "Rainbow", Value = 1500000 })
	handlers.RaidAlert({ Raider = "Bob", Cause = "crack", PlotIndex = 3 })
	handlers.RaidAlert({ Raider = "Bob", Cause = "stolen", Artifact = "golden_idol" })
	handlers.DataChanged("Data", "Cash", 999999)
	handlers.DataChanged("Session", "Carried", {})
	task.wait(0.2)
end)

test("character actions don't error without a character", function()
	controllers.CharacterController:Bonk()
	controllers.CharacterController:Dash()
	controllers.CharacterController:ToggleWheel()
	controllers.CharacterController:ToggleWheel()
end)

test("punch swings the arm, then resets it (R15 + R6)", function()
	local identity = roblox.CFrame.identity
	local holder = wrap(roblox.Instance.new("Folder"))
	for _, r15 in { true, false } do
		local character = wrap(roblox.Instance.new("Model"))
		local function joint(partName: string, jointName: string)
			local part = wrap(roblox.Instance.new("Part"))
			part.Name = partName
			part.Parent = character
			local motor = wrap(roblox.Instance.new("Motor6D"))
			motor.Name = jointName
			motor.Parent = part
			return motor
		end
		local shoulder, elbow
		if r15 then
			shoulder = joint("RightUpperArm", "RightShoulder")
			elbow = joint("RightLowerArm", "RightElbow")
			joint("UpperTorso", "Waist")
			local hand = wrap(roblox.Instance.new("Part"))
			hand.Name = "RightHand"
			hand.Parent = character
		else
			shoulder = joint("Torso", "Right Shoulder")
			local arm = wrap(roblox.Instance.new("Part"))
			arm.Name = "Right Arm"
			arm.Parent = character
		end
		character.Parent = holder
		controllers.WorldFXController:Punch(character)
		task.wait(0.05) -- wind-up / jab: the arm is moving and the elbow is bent
		for _, step in steppedHandlers do
			step(0, 1 / 60)
		end
		check(shoulder.Transform ~= identity, "the arm should be mid-punch")
		if elbow then
			check(elbow.Transform ~= identity, "the elbow should bend during the punch")
		end
		task.wait(0.4)
		for _, step in steppedHandlers do
			step(0, 1 / 60)
		end
		check(shoulder.Transform == identity, "the arm should return to normal after the punch")
	end
end)

local failures = H.summary()
process.exit(failures > 0 and 1 or 0)
