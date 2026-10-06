--[[
	ArtifactVisualsController
	Makes artifacts look as valuable as they are. Each tier adds more: sparkles, glow,
	swirls, a light pillar visible across the map, pulsing rings, rainbow color cycling for
	Rainbow mutations / SECRET items. Loose artifacts bob and spin, dropped loot arcs out of
	the victim and blinks before it despawns, event loot falls from the sky.

	Streaming-aware: visuals attach when an artifact streams in (CollectionService tag) and
	are cleaned up automatically when it streams out.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)

local UIFolder = script.Parent.Parent.UI
local Components = require(UIFolder.Components)
local Theme = require(UIFolder.Theme)

local player = Players.LocalPlayer

local ArtifactVisualsController = { Name = "ArtifactVisualsController" }

local Data

type Entry = {
	Model: Model,
	Core: BasePart,
	Base: CFrame,
	Phase: number,
	Carried: boolean,
	Rainbow: boolean,
	Secret: boolean,
	Parts: { BasePart },
	Light: PointLight?,
	SpawnedAt: number,
	DropFrom: Vector3?,
	ExpiresAt: number?,
	NextRing: number,
	Tier: number,
	Color: Color3,
}

local entries: { [Model]: Entry } = {}
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

function ArtifactVisualsController:Init(all)
	Data = all.DataController
end

local function lowVfx(): boolean
	local settings = Data:Get("Settings")
	return type(settings) == "table" and settings.VFX == "Low"
end

local function emitter(
	parent: Instance,
	color: Color3,
	rate: number,
	size: number,
	speed: number,
	lifetime: number
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLES
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
	return e
end

local function decorate(model: Model)
	if entries[model] then
		return
	end
	local core = model.PrimaryPart or model:FindFirstChild("Core") :: BasePart?
	local id = model:GetAttribute("ArtifactId")
	local def = type(id) == "string" and Artifacts.get(id)
	if not core or not def then
		return
	end
	local rarity = Rarities.get(def.Rarity)
	local mutation = model:GetAttribute("Mutation")
	local carried = model:GetAttribute("Carried") == true
	local color = Theme.rarity(def.Rarity)
	local low = lowVfx()
	local tier = rarity.Vfx

	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= core then
			table.insert(parts, part)
		end
	end

	-- Tiered effects
	if tier >= 1 and not (low and tier < 4) then
		emitter(core, color, 1.5 + tier * 1.5, 0.35 + tier * 0.06, 1.5, 1.2)
	end
	local light: PointLight? = nil
	if tier >= 2 then
		local newLight = Instance.new("PointLight")
		newLight.Color = color
		newLight.Range = 6 + tier * 2.5
		newLight.Brightness = 1 + tier * 0.35
		newLight.Parent = core
		light = newLight
	end
	if tier >= 3 and not low then
		local swirl = emitter(core, color:Lerp(Color3.new(1, 1, 1), 0.3), 6, 0.5, 0.5, 2)
		swirl.RotSpeed = NumberRange.new(-180, 180)
		swirl.Acceleration = Vector3.new(0, 1.5, 0)
	end
	if tier >= 4 and not carried then
		-- Light pillar so you can spot it from far away
		local a0 = Instance.new("Attachment")
		a0.Parent = core
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 40 + tier * 18, 0)
		a1.Parent = core
		local pillar = Instance.new("Beam")
		pillar.Attachment0 = a0
		pillar.Attachment1 = a1
		pillar.Width0 = 1.6 + (tier - 4) * 0.6
		pillar.Width1 = 0.2
		pillar.FaceCamera = true
		pillar.LightEmission = 1
		pillar.Color = ColorSequence.new(color)
		pillar.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		pillar.Parent = core
	end
	if mutation == "Shiny" then
		emitter(core, Color3.fromRGB(255, 245, 170), 6, 0.45, 2, 0.8)
	end

	-- Floating label for loose / displayed artifacts
	if not carried then
		local gui = Instance.new("BillboardGui")
		gui.Name = "ArtifactLabel"
		gui.Size = UDim2.fromOffset(200, 54)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = tier >= 4 and 90 or 42
		gui.LightInfluence = 0
		gui.Adornee = core
		local nameLabel = Components.label({
			Text = (mutation and (mutation .. " ") or "") .. def.Name,
			TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1, 0, 0.5, 0),
			MaxTextSize = 20,
			Parent = gui,
		})
		Components.textStroke(nameLabel, 1.5)
		local owner = model:GetAttribute("OwnerUserId")
		local extra = Format.cash(tonumber(model:GetAttribute("Value")) or def.Value)
		if owner == player.UserId then
			extra ..= "  ·  🏦 yours"
		elseif model:GetAttribute("Source") == "Vault" then
			extra ..= "  ·  🏴‍☠️ raid!"
		end
		local rarityLabel = Components.label({
			Name = "Rarity",
			Text = string.upper(rarity.Name) .. "  ·  " .. extra,
			TextColor3 = color,
			Size = UDim2.new(1, 0, 0.42, 0),
			Position = UDim2.fromScale(0, 0.52),
			MaxTextSize = 16,
			Parent = gui,
		})
		Components.textStroke(rarityLabel, 1.5)
		gui.Parent = core
	end

	local base = model:GetAttribute("BaseCFrame")
	entries[model] = {
		Model = model,
		Core = core,
		Base = typeof(base) == "CFrame" and base or model:GetPivot(),
		Phase = math.random() * math.pi * 2,
		Carried = carried,
		Rainbow = mutation == "Rainbow",
		Secret = def.Rarity == "Secret",
		Parts = parts,
		Light = light,
		SpawnedAt = tonumber(model:GetAttribute("SpawnedAt")) or 0,
		DropFrom = model:GetAttribute("DropFrom") :: Vector3?,
		ExpiresAt = model:GetAttribute("ExpiresAt") :: number?,
		NextRing = 0,
		Tier = tier,
		Color = color,
	}
end

local function pulseRing(entry: Entry)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = entry.Color
	ring.Size = Vector3.new(0.15, 2, 2)
	ring.Transparency = 0.3
	ring.CFrame = CFrame.new(entry.Core.Position - Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace.Terrain
	Components.tween(ring, 1.2, { Size = Vector3.new(0.15, 14, 14), Transparency = 1 })
	task.delay(1.25, function()
		ring:Destroy()
	end)
end

local function update()
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
	local camera = workspace.CurrentCamera
	local cameraPos = camera and camera.CFrame.Position or Vector3.zero
	for model, entry in entries do
		if not model.Parent then
			entries[model] = nil
			continue
		end
		if entry.Carried then
			if entry.Rainbow or entry.Secret then
				for i, part in entry.Parts do
					if part.Material == Enum.Material.Neon or entry.Rainbow then
						part.Color = Rarities.rainbow(t, i * 0.08)
					end
				end
			end
			continue
		end
		local distance = (entry.Base.Position - cameraPos).Magnitude
		if distance > 220 then
			continue
		end
		-- Arc in from the drop origin / fall from the sky
		local age = now - entry.SpawnedAt
		local offset = Vector3.zero
		if entry.DropFrom and age < 1.2 then
			local alpha = math.clamp(age / 0.7, 0, 1)
			local from = entry.DropFrom
			local to = entry.Base.Position
			local mid = from:Lerp(to, alpha)
			local height = (from.Y > to.Y + 40) and 0 or math.sin(alpha * math.pi) * 6
			offset = mid + Vector3.new(0, height, 0) - to
		end
		local bob = math.sin(t * 2 + entry.Phase) * 0.25
		local spin = t * 0.9 + entry.Phase
		model:PivotTo(CFrame.new(entry.Base.Position + offset + Vector3.new(0, bob, 0)) * CFrame.Angles(0, spin, 0))

		-- Despawn warning blink
		if entry.ExpiresAt then
			local remaining = entry.ExpiresAt - now
			local hidden = remaining < 10 and (math.floor(t * (remaining < 4 and 8 or 4)) % 2 == 0)
			for _, part in entry.Parts do
				part.LocalTransparencyModifier = hidden and 0.7 or 0
			end
		end
		if entry.Rainbow or entry.Secret then
			for i, part in entry.Parts do
				if entry.Rainbow or part.Material == Enum.Material.Neon then
					part.Color = Rarities.rainbow(t, i * 0.08)
				end
			end
			if entry.Light then
				entry.Light.Color = Rarities.rainbow(t)
			end
		end
		if entry.Tier >= 5 and t >= entry.NextRing and not lowVfx() then
			entry.NextRing = t + 2
			pulseRing(entry)
		end
	end
end

function ArtifactVisualsController:Start()
	for _, model in CollectionService:GetTagged("Artifact") do
		if model:IsA("Model") then
			task.spawn(decorate, model)
		end
	end
	CollectionService:GetInstanceAddedSignal("Artifact"):Connect(function(model)
		if model:IsA("Model") then
			-- Wait a frame so streamed-in children are present
			task.defer(decorate, model)
		end
	end)
	CollectionService:GetInstanceRemovedSignal("Artifact"):Connect(function(model)
		entries[model :: Model] = nil
	end)
	RunService.RenderStepped:Connect(update)
end

return ArtifactVisualsController
