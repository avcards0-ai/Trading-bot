--[[
	High-Security Vault - north-east of the Marketplace.
	A fortress bank whose giant round door only opens every few minutes. Inside: the best
	loot in the city, sweeping lasers, cameras and elite guards. An emergency vent lets
	trapped thieves crawl out when the door slams shut.
]]

local Zones = require(game:GetService("ReplicatedStorage").Shared.Config.Zones)
local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local rgb = Kit.rgb

local STEEL = rgb(138, 146, 160)
local DARK_STEEL = rgb(70, 78, 92)
local MARBLE = rgb(235, 235, 240)

return function(root: Instance)
	local zone = Zones.get("Vault") :: any
	local center = zone.Center
	local folder = Kit.model("HighSecurityVault", root)
	-- Local +Z faces the Marketplace.
	local o = CFrame.new(center) * CFrame.Angles(0, math.rad(-45), 0)
	local spawns: { CFrame } = {}
	local patrol: { Vector3 } = {}
	local lasers = {}
	local cameras = {}
	local hatches = {}
	local owner = "Zone:Vault"

	local BASE_Y = 3
	-- Raised plaza + steps
	Kit.block(
		folder,
		Vector3.new(124, BASE_Y, 124),
		o * CFrame.new(0, BASE_Y / 2, 0),
		MARBLE,
		Enum.Material.Marble,
		"Plaza"
	)
	Kit.stairs(folder, o * CFrame.new(0, 0, 62 + 6), 6, 40, BASE_Y / 6, 1, MARBLE, Enum.Material.Marble)

	-- Building shell (80 x 80, door opening 18 x 18 in the front wall)
	local b = o * CFrame.new(0, BASE_Y, -5)
	local H = 26
	local floor = Kit.block(
		folder,
		Vector3.new(80, 0.4, 80),
		b * CFrame.new(0, 0.2, 0),
		rgb(60, 62, 70),
		Enum.Material.DiamondPlate,
		"VaultFloor"
	)
	floor.CastShadow = false
	Kit.room(
		folder,
		b * CFrame.new(0, 0.4, 0),
		Vector3.new(80, H, 80),
		3,
		STEEL,
		Enum.Material.Metal,
		{ Back = 18 },
		18
	)
	Kit.block(folder, Vector3.new(84, 2, 84), b * CFrame.new(0, H + 1.4, 0), DARK_STEEL, Enum.Material.Metal, "Roof")
	-- Facade trim + sign
	Kit.block(folder, Vector3.new(84, 4, 2), b * CFrame.new(0, H - 1, 41.5), C.Gold, Enum.Material.Metal)
	Kit.sign(
		folder,
		Vector3.new(44, 5, 0.8),
		b * CFrame.new(0, H + 5, 41) * CFrame.Angles(0, math.pi, 0),
		"🏦 HIGH-SECURITY VAULT 🏦",
		rgb(20, 30, 50),
		rgb(120, 220, 255),
		{ Font = Enum.Font.LuckiestGuy }
	)

	-- Bank-fortress dressing: marble pilasters, cornice, a crown with a gold dome
	for x = -1, 1, 2 do
		for z = -1, 1, 2 do
			Kit.block(
				folder,
				Vector3.new(5, H + 1, 5),
				b * CFrame.new(x * 40.5, H / 2 + 0.4, z * 40.5),
				MARBLE,
				Enum.Material.Marble,
				"Pilaster"
			)
			Kit.block(
				folder,
				Vector3.new(6.4, 1.4, 6.4),
				b * CFrame.new(x * 40.5, 1.1, z * 40.5),
				rgb(200, 200, 206),
				Enum.Material.Marble
			)
		end
		-- Barred slit windows down each side
		for i = -1, 1 do
			local cf = b * CFrame.new(x * 41.6, 15, i * 22) * CFrame.Angles(0, math.rad(90), 0)
			Kit.detail(Kit.block(folder, Vector3.new(4, 8, 0.4), cf, rgb(40, 60, 80), Enum.Material.Glass))
			for bar = -1, 1 do
				Kit.detail(
					Kit.block(
						folder,
						Vector3.new(0.4, 8.4, 0.6),
						cf * CFrame.new(bar * 1.2, 0, 0),
						DARK_STEEL,
						Enum.Material.Metal
					)
				)
			end
			Kit.detail(
				Kit.block(folder, Vector3.new(5, 0.6, 1), cf * CFrame.new(0, -4.3, 0), MARBLE, Enum.Material.Marble)
			)
		end
	end
	Kit.block(folder, Vector3.new(86, 1.2, 86), b * CFrame.new(0, H + 2.8, 0), MARBLE, Enum.Material.Marble, "Cornice")
	local crownY = H + 3.4
	Kit.block(folder, Vector3.new(50, 6, 50), b * CFrame.new(0, crownY + 3, -6), STEEL, Enum.Material.Metal, "Crown")
	Kit.block(folder, Vector3.new(53, 1.2, 53), b * CFrame.new(0, crownY + 6.4, -6), MARBLE, Enum.Material.Marble)
	Kit.cyl(folder, 3, 28, b * CFrame.new(0, crownY + 8.5, -6), MARBLE, Enum.Material.Marble, "DomeBase")
	Kit.ball(folder, 26, b * CFrame.new(0, crownY + 10, -6), C.Gold, Enum.Material.Foil).Name = "Dome"
	Kit.cyl(folder, 4, 3, b * CFrame.new(0, crownY + 24.5, -6), MARBLE, Enum.Material.Marble)
	local beacon = Kit.ball(folder, 3, b * CFrame.new(0, crownY + 27.6, -6), rgb(120, 220, 255), Enum.Material.Neon)
	Kit.detail(beacon)
	Kit.light(beacon, rgb(150, 230, 255), 2, 40)
	-- Flags on the front corners
	for x = -1, 1, 2 do
		Kit.detail(
			Kit.cyl(folder, 14, 0.5, b * CFrame.new(x * 40.5, H + 10.4, 40.5), rgb(220, 220, 225), Enum.Material.Metal)
		)
		Kit.detail(
			Kit.block(
				folder,
				Vector3.new(0.2, 4, 7),
				b * CFrame.new(x * 40.5, H + 15, 37),
				rgb(30, 60, 120),
				Enum.Material.Fabric
			)
		)
		Kit.detail(Kit.ball(folder, 1, b * CFrame.new(x * 40.5, H + 17.6, 40.5), C.Gold, Enum.Material.Metal))
	end

	-- The giant round door
	local doorModel = Kit.model("VaultDoor", folder, Enum.ModelStreamingMode.Atomic)
	local doorClosed = b * CFrame.new(0, 9.4, 41.6)
	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(3, 21, 21)
	disc.CFrame = doorClosed * CFrame.Angles(0, math.rad(90), 0)
	disc.Anchored = true
	disc.Color = rgb(200, 205, 215)
	disc.Material = Enum.Material.DiamondPlate
	disc.Parent = doorModel
	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Shape = Enum.PartType.Cylinder
	hub.Size = Vector3.new(1.4, 6, 6)
	hub.CFrame = doorClosed * CFrame.new(0, 0, 1.8) * CFrame.Angles(0, math.rad(90), 0)
	hub.Anchored = true
	hub.Color = C.Gold
	hub.Material = Enum.Material.Metal
	hub.Parent = doorModel
	for i = 1, 3 do
		local spoke = Kit.block(
			doorModel,
			Vector3.new(14, 0.8, 0.8),
			doorClosed * CFrame.new(0, 0, 2.2) * CFrame.Angles(0, 0, i * math.pi / 3),
			C.Gold,
			Enum.Material.Metal,
			"Spoke"
		)
		spoke.CastShadow = false
	end
	local ringLight = Kit.block(
		doorModel,
		Vector3.new(2, 2, 0.6),
		doorClosed * CFrame.new(0, 8, 1.8),
		rgb(255, 60, 60),
		Enum.Material.Neon,
		"StatusLight"
	)
	ringLight.CastShadow = false
	doorModel.PrimaryPart = disc
	local doorOpen = doorClosed * CFrame.new(-21, 0, 3) * CFrame.Angles(0, 0, math.rad(-200))

	-- Countdown board above the door (client renders the timer)
	local timerBoard = Kit.block(
		folder,
		Vector3.new(16, 3.5, 0.6),
		b * CFrame.new(0, 21, 41.8),
		rgb(15, 15, 22),
		Enum.Material.SmoothPlastic,
		"TimerBoard"
	)
	local _, timerLabel = Kit.label(
		timerBoard,
		"VAULT SEALED",
		{ Face = Enum.NormalId.Back, TextColor = rgb(255, 80, 80), Font = Enum.Font.Code, Name = "Timer" }
	)
	timerLabel.Name = "TimerText"

	-- Interior: gold piles, pedestal ring, lasers, cameras
	local inner = b * CFrame.new(0, 0.4, 0)
	for i = 1, 6 do
		local x = (i % 2 == 0) and 30 or -30
		local z = -30 + math.floor((i - 1) / 2) * 18
		for j = 0, 2 do
			Kit.block(
				folder,
				Vector3.new(4, 1.2, 2),
				inner * CFrame.new(x + (j - 1) * 2.2, 0.6 + (j % 2) * 1.2, z) * CFrame.Angles(0, math.rad(j * 15), 0),
				C.Gold,
				Enum.Material.Foil,
				"GoldBar"
			)
		end
	end
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		local cf = inner * CFrame.new(math.cos(angle) * 22, 0, math.sin(angle) * 22 - 6)
		table.insert(spawns, (Kit.pedestal(folder, cf, rgb(40, 44, 55), rgb(120, 220, 255))))
	end
	table.insert(
		spawns,
		(Kit.pedestal(folder, inner * CFrame.new(0, 0, -6) * CFrame.new(0, 0.5, 0), C.Gold, rgb(255, 255, 255)))
	)
	local crown = Kit.ghost(folder, Vector3.one, inner * CFrame.new(0, 20, -6))
	Kit.light(crown, rgb(200, 240, 255), 3, 40, "Spot")

	local laserSpecs = {
		{ Z = 26, H = 1.4, Pattern = "Sweep", Speed = 1.3, Amp = 2.5, Axis = Vector3.yAxis },
		{ Z = 20, H = 3.2, Pattern = "Chaos", Speed = 1.5, Amp = 2.0, Axis = Vector3.yAxis },
		{ Z = 0, H = 2.0, Pattern = "Sweep", Speed = 1.0, Amp = 3.0, Axis = Vector3.zAxis },
		{ Z = -18, H = 1.2, Pattern = "Blink", Speed = 1.6, Amp = 0, Axis = Vector3.yAxis },
		{ Z = -24, H = 3.8, Pattern = "Sweep", Speed = 1.8, Amp = 2.2, Axis = Vector3.yAxis },
		{ Z = -32, H = 2.4, Pattern = "Chaos", Speed = 1.2, Amp = 2.5, Axis = Vector3.yAxis },
	}
	local worldZ = (o.LookVector * -1) -- local +Z in world space
	for i, spec in laserSpecs do
		local axis = spec.Axis == Vector3.zAxis and worldZ or spec.Axis
		table.insert(
			lasers,
			Kit.laser(
				folder,
				inner * CFrame.new(0, spec.H, spec.Z),
				74,
				spec.Pattern,
				spec.Speed,
				i * 0.9,
				spec.Amp,
				axis,
				owner
			)
		)
	end
	-- Corner cameras look diagonally across the room toward its center.
	for _, spec in
		{
			{ -36, 36, -math.pi / 4 },
			{ 36, 36, math.pi / 4 },
			{ -36, -36, -3 * math.pi / 4 },
			{ 36, -36, 3 * math.pi / 4 },
		}
	do
		local pos = (inner * CFrame.new(spec[1], 17, spec[2])).Position
		local worldYaw = select(2, (o * CFrame.Angles(0, spec[3], 0)):ToEulerAnglesYXZ())
		table.insert(cameras, Kit.camera(folder, pos, worldYaw, 0.7, 0.6, 46, 52, owner))
	end
	-- Interior lights
	for _, p in { { -20, -20 }, { 20, -20 }, { -20, 20 }, { 20, 20 } } do
		local lamp = Kit.block(
			folder,
			Vector3.new(5, 0.4, 5),
			inner * CFrame.new(p[1], H - 1, p[2]),
			rgb(200, 230, 255),
			Enum.Material.Neon
		)
		lamp.CastShadow = false
		Kit.light(lamp, rgb(200, 230, 255), 1.4, 34, "Spot")
	end

	-- Emergency vent (inside, back-left) -> outside behind the building
	local ventCF = inner * CFrame.new(-33, 0, -33)
	local ventExit = o * CFrame.new(-50, BASE_Y + 3, -58)
	local ventPart, ventPrompt = Kit.hatch(folder, ventCF, "Crawl Through Vent", ventExit, 2.5)
	ventPrompt.ObjectText = "Emergency Vent"
	table.insert(hatches, { Part = ventPart, Prompt = ventPrompt, Destination = ventExit, OneWay = true })

	-- Outside decor: barriers, searchlight posts, armored truck
	for i = -2, 2 do
		if i ~= 0 then
			local barrier = Kit.block(
				folder,
				Vector3.new(6, 2.4, 2),
				o * CFrame.new(i * 12, BASE_Y + 1.2, 52),
				rgb(230, 200, 40),
				Enum.Material.Concrete,
				"Barrier"
			)
			Kit.block(
				folder,
				Vector3.new(6.05, 0.5, 2.05),
				barrier.CFrame * CFrame.new(0, 0.4, 0),
				C.Black,
				Enum.Material.SmoothPlastic
			)
		end
	end
	for side = -1, 1, 2 do
		local post = o * CFrame.new(side * 56, BASE_Y, 56)
		Kit.cyl(folder, 16, 1.2, post * CFrame.new(0, 8, 0), DARK_STEEL, Enum.Material.Metal)
		local lamp = Kit.block(
			folder,
			Vector3.new(3, 2, 3),
			post * CFrame.new(0, 16.5, 0),
			rgb(255, 250, 220),
			Enum.Material.Neon
		)
		Kit.light(lamp, rgb(255, 250, 220), 2, 50, "Spot")
	end
	local truck = Kit.model("ArmoredTruck", folder)
	local tcf = o * CFrame.new(46, BASE_Y, 30) * CFrame.Angles(0, math.rad(80), 0)
	Kit.block(truck, Vector3.new(9, 8, 20), tcf * CFrame.new(0, 5, 0), rgb(60, 80, 70), Enum.Material.Metal)
	Kit.block(truck, Vector3.new(9.2, 3, 5), tcf * CFrame.new(0, 7, -8), rgb(130, 180, 220), Enum.Material.Glass)
	Kit.label(
		Kit.block(truck, Vector3.new(0.2, 3, 8), tcf * CFrame.new(4.6, 5, 2), rgb(60, 80, 70), Enum.Material.Metal),
		"$$$",
		{ Face = Enum.NormalId.Right, TextColor = C.Gold }
	)
	for _, wz in { -6, 6 } do
		for _, wx in { -4.6, 4.6 } do
			Kit.cyl(
				truck,
				1.4,
				3.6,
				tcf * CFrame.new(wx, 1.8, wz) * CFrame.Angles(0, 0, math.rad(90)),
				C.Black,
				Enum.Material.Fabric
			)
		end
	end

	-- Elite guard patrol (inside the vault)
	for _, p in { { 0, 28 }, { -26, 10 }, { 26, 10 }, { -26, -26 }, { 26, -26 }, { 0, -34 } } do
		table.insert(patrol, (inner * CFrame.new(p[1], 3, p[2])).Position)
	end

	return {
		Id = "Vault",
		Folder = folder,
		Spawns = spawns,
		Patrol = patrol,
		Lasers = lasers,
		Cameras = cameras,
		Traps = {},
		Hatches = hatches,
		Door = {
			Model = doorModel,
			Closed = doorClosed * CFrame.Angles(0, math.rad(90), 0),
			Open = doorOpen * CFrame.Angles(0, math.rad(90), 0),
			Light = ringLight,
			TimerLabel = timerLabel,
		},
		Interior = { CFrame = inner * CFrame.new(0, 12, 0), Size = Vector3.new(74, 24, 74) },
		Outside = o * CFrame.new(0, BASE_Y + 3, 50),
	}
end
