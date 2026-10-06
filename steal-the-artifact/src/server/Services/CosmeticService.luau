--[[
	CosmeticService
	Applies equipped cosmetics so everyone sees them: trails and auras on characters,
	vault skins on plots. Purely visual - no gameplay effect.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cosmetics = require(Shared.Config.Cosmetics)

local CosmeticService = { Name = "CosmeticService" }

local S: { [string]: any }

function CosmeticService:Init(services)
	S = services
end

local function clear(container: Instance, names: { string })
	for _, name in names do
		local existing = container:FindFirstChild(name)
		while existing do
			existing:Destroy()
			existing = container:FindFirstChild(name)
		end
	end
end

function CosmeticService:ApplyCharacter(player: Player)
	local data = S.DataService:Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not data or not root then
		return
	end
	clear(root, { "CosmeticTrail", "CosmeticTrailA0", "CosmeticTrailA1", "CosmeticAura" })

	local trailDef = Cosmetics.ById[data.Cosmetics.Equipped.Trail or ""]
	if trailDef and trailDef.Type == "Trail" then
		local a0 = Instance.new("Attachment")
		a0.Name = "CosmeticTrailA0"
		a0.Position = Vector3.new(0, 0.9, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "CosmeticTrailA1"
		a1.Position = Vector3.new(0, -1.4, 0)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Name = "CosmeticTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = Cosmetics.colorSequence(trailDef.Colors)
		trail.Lifetime = 0.55
		trail.MinLength = 0.1
		trail.LightEmission = 0.7
		trail.FaceCamera = true
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Parent = root
	end

	local auraDef = Cosmetics.ById[data.Cosmetics.Equipped.Aura or ""]
	if auraDef and auraDef.Type == "Aura" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "CosmeticAura"
		emitter.Texture = auraDef.Texture or "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = Cosmetics.colorSequence(auraDef.Colors)
		emitter.LightEmission = 0.8
		emitter.Rate = 14
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Acceleration = Vector3.new(0, 2, 0)
		emitter.Parent = root
	end
end

local function paint(plot: any, skin: any)
	if not plot or not skin then
		return
	end
	for _, part in plot.Skin.Primary do
		part.Color = skin.Colors[1]
		part.Material = skin.Material or Enum.Material.Concrete
	end
	for _, part in plot.Skin.Secondary do
		part.Color = skin.Colors[2]
		part.Material = skin.Material or Enum.Material.Concrete
	end
	for _, part in plot.Skin.Accent do
		part.Color = skin.Colors[3]
		part.Material = skin.AccentMaterial or Enum.Material.Neon
	end
end

function CosmeticService:ApplyVaultSkin(player: Player)
	local data = S.DataService:Get(player)
	local plot = S.PlotService:GetPlot(player)
	if not data or not plot then
		return
	end
	local skin = Cosmetics.ById[data.Cosmetics.Equipped.VaultSkin or ""] or Cosmetics.ById.skin_default
	paint(plot, skin)
end

function CosmeticService:ResetVaultSkin(index: number)
	paint(S.MapService:GetPlot(index), Cosmetics.ById.skin_default)
end

function CosmeticService:Start() end

return CosmeticService
