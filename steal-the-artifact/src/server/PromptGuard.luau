--[[
	PromptGuard
	ProximityPrompt.Triggered can be fired instantly by exploit tools, skipping the hold.
	PromptGuard records when each player *started* holding each prompt (the server sees
	PromptButtonHoldBegan too) and only accepts a trigger once the player has held for the
	duration the server expects, from close enough, while alive.
]]

local Players = game:GetService("Players")

local PromptGuard = {}

local holdStarts: { [Player]: { [ProximityPrompt]: number } } = {}

local TOLERANCE = 0.82 -- network jitter allowance
local DISTANCE_SLACK = 6

function PromptGuard.watch(prompt: ProximityPrompt)
	prompt.PromptButtonHoldBegan:Connect(function(player)
		local starts = holdStarts[player]
		if not starts then
			starts = {}
			holdStarts[player] = starts
		end
		starts[prompt] = os.clock()
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		-- Keep the start time briefly: Triggered may arrive right after HoldEnded.
		local starts = holdStarts[player]
		if starts and starts[prompt] then
			local started = starts[prompt]
			task.delay(1, function()
				if holdStarts[player] and holdStarts[player][prompt] == started then
					holdStarts[player][prompt] = nil
				end
			end)
		end
	end)
end

function PromptGuard.rootPart(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Validates a Triggered call. `expectedHold` is the per-player hold time in seconds.
function PromptGuard.validate(player: Player, prompt: ProximityPrompt, expectedHold: number): boolean
	local root = PromptGuard.rootPart(player)
	if not root then
		return false
	end
	local parent = prompt.Parent
	local position: Vector3? = nil
	if parent and parent:IsA("BasePart") then
		position = parent.Position
	elseif parent and parent:IsA("Attachment") then
		position = parent.WorldPosition
	end
	if not position then
		return false
	end
	if (root.Position - position).Magnitude > prompt.MaxActivationDistance + DISTANCE_SLACK then
		return false
	end
	if expectedHold > 0.05 then
		local starts = holdStarts[player]
		local started = starts and starts[prompt]
		if not started then
			return false
		end
		if os.clock() - started < expectedHold * TOLERANCE then
			return false
		end
		starts[prompt] = nil
	end
	return true
end

function PromptGuard.forget(prompt: ProximityPrompt)
	for _, starts in holdStarts do
		starts[prompt] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	holdStarts[player] = nil
end)

return PromptGuard
