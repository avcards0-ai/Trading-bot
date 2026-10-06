--[[
	SecurityPatterns
	Deterministic motion for lasers and cameras, driven by workspace:GetServerTimeNow().
	The server uses these to decide hits/detection; each client uses the exact same math
	to animate the devices locally. Nothing moves on the server, so lasers and cameras cost
	zero replication bandwidth while staying perfectly in sync with what the server checks.
]]

local SecurityPatterns = {}

-- Returns whether a beam is active and its offset (studs) along its sweep axis.
function SecurityPatterns.laser(pattern: string, speed: number, phase: number, amplitude: number, t: number): (boolean, number)
	if pattern == "Static" then
		return true, 0
	elseif pattern == "Blink" then
		return math.sin(t * speed * math.pi + phase) > -0.25, 0
	elseif pattern == "Sweep" then
		return true, math.sin(t * speed + phase) * amplitude
	elseif pattern == "Chaos" then
		local offset = math.sin(t * speed + phase) * amplitude
		local on = math.sin(t * speed * 1.7 + phase * 2.3) > -0.45
		return on, offset
	end
	return false, 0
end

-- Camera yaw (radians) at time t.
function SecurityPatterns.cameraYaw(baseYaw: number, sweep: number, speed: number, phase: number, t: number): number
	return baseYaw + math.sin(t * speed + phase) * sweep
end

-- CFrame of a camera head at time t looking along its yaw, pitched down.
function SecurityPatterns.cameraCFrame(position: Vector3, yaw: number, pitchDegrees: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-pitchDegrees), 0, 0)
end

-- Cone test (line of sight is checked separately by the server with a raycast).
function SecurityPatterns.inCone(cameraCF: CFrame, range: number, fovDegrees: number, target: Vector3): boolean
	local offset = target - cameraCF.Position
	local distance = offset.Magnitude
	if distance > range or distance < 0.01 then
		return false
	end
	local cosAngle = cameraCF.LookVector:Dot(offset / distance)
	return cosAngle >= math.cos(math.rad(fovDegrees / 2))
end

return SecurityPatterns
