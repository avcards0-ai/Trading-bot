--[[
	ArtifactViewport
	3D artifact previews for the UI using the same procedural models as the world.
	Undiscovered artifacts render as black silhouettes for the Collection Book.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArtifactModels = require(ReplicatedStorage.Shared.ArtifactModels)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local ArtifactViewport = {}

type Spinner = { Viewport: ViewportFrame, Model: Model, Speed: number }
local spinners: { Spinner } = {}

export type Props = {
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Silhouette: boolean?,
	Spin: boolean?,
	Parent: Instance?,
	ZIndex: number?,
	LayoutOrder: number?,
}

function ArtifactViewport.new(artifactId: string, mutation: string?, props: Props?): ViewportFrame
	local opts = props or {}
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ArtifactViewport"
	viewport.BackgroundTransparency = 1
	viewport.Size = opts.Size or UDim2.fromScale(1, 1)
	viewport.Position = opts.Position or UDim2.new()
	viewport.AnchorPoint = opts.AnchorPoint or Vector2.zero
	viewport.ZIndex = opts.ZIndex or 1
	viewport.LayoutOrder = opts.LayoutOrder or 0
	viewport.LightDirection = Vector3.new(-0.6, -1, -0.4)
	if opts.Silhouette then
		viewport.Ambient = Color3.new(0, 0, 0)
		viewport.LightColor = Color3.new(0, 0, 0)
		viewport.ImageColor3 = Color3.fromRGB(12, 12, 20)
	else
		viewport.Ambient = Color3.fromRGB(170, 170, 185)
		viewport.LightColor = Color3.fromRGB(255, 250, 240)
	end

	local model = ArtifactModels.build(artifactId, mutation)
	if opts.Silhouette then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Material = Enum.Material.SmoothPlastic
				part.Color = Color3.new(0, 0, 0)
				part.Transparency = part.Name == "Core" and 1 or 0
			end
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = viewport

	local _, size = model:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z) * 0.5
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.15 + 0.5
	camera.CFrame = CFrame.lookAt(Vector3.new(0, radius * 0.35, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	if opts.Spin then
		table.insert(spinners, { Viewport = viewport, Model = model, Speed = 0.8 })
	end
	if opts.Parent then
		viewport.Parent = opts.Parent
	end
	return viewport
end

-- Animate rainbow + spin for previews that asked for it.
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for i = #spinners, 1, -1 do
		local spinner = spinners[i]
		if not spinner.Viewport.Parent then
			table.remove(spinners, i)
		elseif spinner.Viewport.Visible then
			spinner.Model:PivotTo(spinner.Model:GetPivot() * CFrame.Angles(0, dt * spinner.Speed, 0))
			if spinner.Model:GetAttribute("Mutation") == "Rainbow" then
				for _, part in spinner.Model:GetChildren() do
					if part:IsA("BasePart") and part.Name ~= "Core" then
						part.Color = Rarities.rainbow(t, part.Position.Y * 0.2)
					end
				end
			end
		end
	end
end)

return ArtifactViewport
