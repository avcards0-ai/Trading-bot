--[[
	Plots - one vault per player, arranged in a ring around the city.
	Each plot gets: a vault building with a crackable door, a SECURE pad just inside,
	a laser band, trap slots, camera mounts, 20 display pedestals, an owner sign,
	a control terminal and alarm lights. Security devices are installed later by the
	SecurityService based on the owner's upgrades.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local rgb = Kit.rgb

export type Pedestal = { CFrame: CFrame, Glow: BasePart, Top: BasePart }

export type PlotData = {
	Index: number,
	CFrame: CFrame,
	Folder: Model,
	Devices: Folder,
	SpawnCFrame: CFrame,
	Front: CFrame,
	SecurePad: { Position: Vector3, Radius: number, Part: BasePart },
	Door: { Part: BasePart, Closed: CFrame, Open: CFrame, Prompt: ProximityPrompt },
	Pedestals: { Pedestal },
	Interior: { CFrame: CFrame, Size: Vector3 },
	Sign: { Part: BasePart, Label: TextLabel },
	Terminal: BasePart,
	LaserSlots: { { CFrame: CFrame, Length: number } },
	CameraSlots: { { Position: Vector3, Yaw: number } },
	TrapSlots: { Vector3 },
	GuardSpawn: CFrame,
	Patrol: { Vector3 },
	AlarmLights: { BasePart },
	Skin: { Primary: { BasePart }, Secondary: { BasePart }, Accent: { BasePart } },
}

local function worldYaw(plotCF: CFrame, fromLocal: Vector3, toLocal: Vector3): number
	local dir = plotCF:VectorToWorldSpace(toLocal - fromLocal)
	return math.atan2(-dir.X, -dir.Z)
end

local function buildPlot(root: Instance, index: number, plotCF: CFrame): PlotData
	local folder = Kit.model("Plot" .. index, root)
	folder:SetAttribute("PlotIndex", index)
	local devices = Kit.folder("Devices", folder)
	local skin = { Primary = {}, Secondary = {}, Accent = {} }
	local function tag(part: BasePart, group: string): BasePart
		table.insert(skin[group], part)
		return part
	end

	-- Platform + path
	local platform = Kit.block(
		folder,
		Vector3.new(96, 2, 96),
		plotCF * CFrame.new(0, 0, 0),
		rgb(120, 190, 100),
		Enum.Material.Grass,
		"Platform"
	)
	platform.CastShadow = false
	local edge = Kit.block(
		folder,
		Vector3.new(97, 1.6, 97),
		plotCF * CFrame.new(0, -0.3, 0),
		rgb(150, 140, 120),
		Enum.Material.Cobblestone
	)
	edge.CastShadow = false
	local path = Kit.block(
		folder,
		Vector3.new(12, 0.2, 42),
		plotCF * CFrame.new(0, 1.05, -27),
		rgb(215, 205, 185),
		Enum.Material.Pavement,
		"Path"
	)
	path.CastShadow = false

	-- Vault building
	local b = plotCF * CFrame.new(0, 1, 18)
	local floor = tag(
		Kit.block(
			folder,
			Vector3.new(56, 0.3, 48),
			b * CFrame.new(0, 0.15, 0),
			rgb(90, 95, 110),
			Enum.Material.SmoothPlastic,
			"VaultFloor"
		),
		"Secondary"
	)
	floor.CastShadow = false
	for _, wall in
		Kit.room(
			folder,
			b * CFrame.new(0, 0.3, 0),
			Vector3.new(56, 20, 48),
			2,
			rgb(150, 155, 165),
			Enum.Material.Concrete,
			{ Front = 10 },
			12
		)
	do
		tag(wall, "Primary")
	end
	tag(
		Kit.block(
			folder,
			Vector3.new(58, 1.5, 50),
			b * CFrame.new(0, 21, 0),
			rgb(90, 95, 110),
			Enum.Material.Concrete,
			"Roof"
		),
		"Secondary"
	)
	-- Trim + accent stripes
	tag(
		Kit.block(
			folder,
			Vector3.new(58.2, 0.6, 0.6),
			b * CFrame.new(0, 20, -24.4),
			rgb(255, 200, 60),
			Enum.Material.Neon,
			"Trim"
		),
		"Accent"
	)
	tag(
		Kit.block(
			folder,
			Vector3.new(12, 0.6, 0.6),
			b * CFrame.new(0, 13.5, -24.4),
			rgb(255, 200, 60),
			Enum.Material.Neon,
			"Trim"
		),
		"Accent"
	)
	for side = -1, 1, 2 do
		tag(
			Kit.block(
				folder,
				Vector3.new(0.6, 12.6, 0.6),
				b * CFrame.new(side * 5.6, 6.6, -24.4),
				rgb(255, 200, 60),
				Enum.Material.Neon,
				"Trim"
			),
			"Accent"
		)
	end

	-- Door (slides up into the wall when open)
	local doorClosed = b * CFrame.new(0, 6.3, -24)
	local door = Kit.block(
		folder,
		Vector3.new(10, 12, 1.2),
		doorClosed,
		rgb(70, 75, 90),
		Enum.Material.DiamondPlate,
		"VaultDoor"
	)
	tag(door, "Secondary")
	local doorOpen = doorClosed * CFrame.new(0, 12.2, 0)
	local crack = Instance.new("ProximityPrompt")
	crack.Name = "CrackPrompt"
	crack.ActionText = "Crack Vault"
	crack.ObjectText = "Vault Door"
	crack.HoldDuration = 3
	crack.MaxActivationDistance = 9
	crack.RequiresLineOfSight = false
	crack.KeyboardKeyCode = Enum.KeyCode.E
	crack:SetAttribute("PlotIndex", index)
	crack.Enabled = false
	crack.Parent = door

	-- Secure pad
	local padPos = (b * CFrame.new(0, 0.35, -19.5)).Position
	local pad = Kit.cyl(
		folder,
		0.2,
		8,
		CFrame.new(padPos) * (plotCF - plotCF.Position),
		rgb(80, 255, 140),
		Enum.Material.Neon,
		"SecurePad"
	)
	pad.CanCollide = false
	pad.CastShadow = false
	tag(pad, "Accent")
	local padRing = Kit.cyl(
		folder,
		0.15,
		9.2,
		CFrame.new(padPos - Vector3.new(0, 0.05, 0)),
		rgb(30, 30, 40),
		Enum.Material.SmoothPlastic
	)
	padRing.CanCollide = false
	-- Flat label lying on the pad (front face rotated to point up).
	local padLabelPart = Kit.ghost(
		folder,
		Vector3.new(8, 8, 0.1),
		CFrame.new(padPos + Vector3.new(0, 0.12, 0)) * (plotCF - plotCF.Position) * CFrame.Angles(math.rad(90), 0, 0)
	)
	Kit.label(padLabelPart, "SECURE", { Face = Enum.NormalId.Front, TextColor = rgb(20, 60, 30), PixelsPerStud = 20 })

	-- Pedestals (5 x 4 grid)
	local pedestals: { Pedestal } = {}
	for row = 0, 3 do
		for col = -2, 2 do
			local cf = b * CFrame.new(col * 10, 0.3, 4 + row * 5.5)
			local spot, glowPart, top = Kit.pedestal(folder, cf, rgb(225, 225, 235), rgb(255, 200, 60))
			local glow = glowPart :: BasePart
			tag(glow, "Accent")
			table.insert(pedestals, { CFrame = spot, Glow = glow, Top = top })
		end
	end

	-- Laser slots across the entry band, camera mounts, trap slots
	local laserSlots = {}
	for i, z in { -14, -12, -10, -8, -6, -4 } do
		table.insert(laserSlots, { CFrame = b * CFrame.new(0, 0.3 + 1 + (i % 3) * 1.6, z), Length = 52 })
	end
	local cameraSlots = {}
	local roomCenter = Vector3.new(0, 1, 16)
	for _, spot in
		{ Vector3.new(-26, 15, -4), Vector3.new(26, 15, -4), Vector3.new(-26, 15, 40), Vector3.new(26, 15, 40) }
	do
		table.insert(cameraSlots, {
			Position = (plotCF * CFrame.new(spot)).Position,
			Yaw = worldYaw(plotCF, spot, roomCenter),
		})
	end
	local trapSlots = {}
	for _, p in
		{
			{ -18, 7 },
			{ 14, 8 },
			{ -6, 12 },
			{ 20, 14 },
			{ -22, 16 },
			{ 6, 17 },
			{ 0, 10 },
			{ -12, 19 },
			{ 16, 19 },
			{ 24, 9 },
		}
	do
		table.insert(trapSlots, (plotCF * CFrame.new(p[1], 1.3, p[2])).Position)
	end
	local patrol = {}
	-- Patrol points sit in the aisles between pedestal rows / columns.
	for _, p in { { -25, 30 }, { 25, 30 }, { -5, 36 }, { 5, 24.75 }, { -15, 16 }, { 15, 16 } } do
		table.insert(patrol, (plotCF * CFrame.new(p[1], 4, p[2])).Position)
	end

	-- Alarm lights on the roof
	local alarms = {}
	for side = -1, 1, 2 do
		local light = Kit.ball(folder, 2.2, b * CFrame.new(side * 26, 22.6, -22), rgb(120, 30, 30), Enum.Material.Neon)
		light.Name = "AlarmLight"
		light:SetAttribute("PlotIndex", index)
		table.insert(alarms, light)
	end

	-- Owner sign out front
	for side = -1, 1, 2 do
		Kit.cyl(folder, 9, 0.8, plotCF * CFrame.new(side * 9, 5.5, -44), rgb(60, 60, 70), Enum.Material.Metal)
	end
	local signPart = Kit.block(
		folder,
		Vector3.new(20, 6, 0.8),
		plotCF * CFrame.new(0, 9, -44),
		rgb(25, 25, 35),
		Enum.Material.SmoothPlastic,
		"OwnerSign"
	)
	tag(
		Kit.block(
			folder,
			Vector3.new(20.6, 6.6, 0.6),
			plotCF * CFrame.new(0, 9, -43.7),
			rgb(255, 200, 60),
			Enum.Material.Neon
		),
		"Accent"
	)
	local _, signLabel =
		Kit.label(signPart, "EMPTY LOT", { Face = Enum.NormalId.Front, TextColor = C.White, Name = "OwnerLabel" })

	-- Control terminal
	local terminal = Kit.block(
		folder,
		Vector3.new(3, 4.5, 2),
		plotCF * CFrame.new(12, 3.25, -10),
		rgb(50, 55, 70),
		Enum.Material.Metal,
		"Terminal"
	)
	local screen = Kit.block(
		folder,
		Vector3.new(2.4, 1.8, 0.2),
		plotCF * CFrame.new(12, 4.6, -11.05),
		rgb(80, 200, 255),
		Enum.Material.Neon,
		"Screen"
	)
	screen.CastShadow = false
	Kit.uiPrompt(terminal, "Vault Controls", "Terminal", "Vault")

	-- Yard dressing
	for side = -1, 1, 2 do
		Kit.lamp(folder, (plotCF * CFrame.new(side * 9, 1, -20)).Position, rgb(255, 230, 170), 9)
		Kit.lamp(folder, (plotCF * CFrame.new(side * 9, 1, -36)).Position, rgb(255, 230, 170), 9)
		Kit.tree(folder, (plotCF * CFrame.new(side * 36, 1, -32)).Position, 0.9)
		local hedge = Kit.block(
			folder,
			Vector3.new(2.5, 3, 40),
			plotCF * CFrame.new(side * 46, 2.5, 0),
			rgb(70, 150, 70),
			Enum.Material.Grass,
			"Hedge"
		)
		hedge.CastShadow = false
	end

	return {
		Index = index,
		CFrame = plotCF,
		Folder = folder,
		Devices = devices,
		SpawnCFrame = plotCF * CFrame.new(0, 4.5, -30),
		Front = plotCF * CFrame.new(0, 4.5, -16),
		SecurePad = { Position = padPos, Radius = 4.6, Part = pad },
		Door = { Part = door, Closed = doorClosed, Open = doorOpen, Prompt = crack },
		Pedestals = pedestals,
		Interior = { CFrame = b * CFrame.new(0, 10.3, 0.5), Size = Vector3.new(53, 20, 45) },
		Sign = { Part = signPart, Label = signLabel },
		Terminal = terminal,
		LaserSlots = laserSlots,
		CameraSlots = cameraSlots,
		TrapSlots = trapSlots,
		GuardSpawn = b * CFrame.new(5, 4, 12.25),
		Patrol = patrol,
		AlarmLights = alarms,
		Skin = skin,
	}
end

return function(root: Instance): { PlotData }
	local folder = Kit.folder("Plots", root)
	local plots = {}
	local cfg = GameConfig.Plots
	for i = 1, cfg.Count do
		local angle = (i - 1) / cfg.Count * math.pi * 2
		local position = Vector3.new(math.cos(angle) * cfg.Radius, 0, math.sin(angle) * cfg.Radius)
		-- Plot fronts (local -Z) face the city center.
		local plotCF = CFrame.lookAt(position, Vector3.zero)
		table.insert(plots, buildPlot(folder, i, plotCF))
	end
	return plots
end
