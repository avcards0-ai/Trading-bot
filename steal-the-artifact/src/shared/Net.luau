--[[
	Net
	Single registry of every remote in the game. The server creates them at boot; clients
	wait for them. Keeping the list here means a typo in a remote name fails loudly in one
	place instead of silently creating a second remote.

	Security model:
	  * Client -> server traffic only ever *requests* an action. Every request goes through
	    the server RequestRouter (rate limited + argument validated) or a dedicated
	    rate-limited event handler. The client never sends money, items, damage or targets
	    the server takes on faith.
	  * Server -> client traffic is presentation only (data mirror, VFX, toasts).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- server -> client
	"DataInit", -- (snapshot) full mirror of the player's data + session state
	"DataChanged", -- (scope, key, value) one top-level key changed
	"Notify", -- (kind, text, opts) toast
	"Feed", -- (entry) kill / steal feed line
	"Announce", -- (entry) big banner (local legendary steals + cross-server globals)
	"RaidAlert", -- (info) your vault is under attack
	"Leaderboards", -- (boards) cached global + server boards
	"Cinematic", -- (info) rare steal cinematic for the thief
	"Fail", -- (kind, caption) funny fail stamp for the victim
	"Knockback", -- (velocity) physics impulse the owning client applies to itself
	"LevelUp", -- (level, rewards)
	"Reward", -- (rewardTable, title) generic reward popup
	-- client -> server
	"Bonk", -- (hintTarget: Player?) melee; server picks/validates the target
	"Dash", -- () tells anti-cheat to expect a burst of speed
}

-- Fire-and-forget cosmetic traffic that may be dropped under load.
Net.UnreliableEvents = {
	"Effect", -- (kind, data) world VFX for nearby clients
}

Net.Functions = {
	"Request", -- (action, ...) -> { ok, msg, data }
}

local FOLDER_NAME = "Remotes"

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

-- Server only: create every remote up front.
function Net.init()
	assert(RunService:IsServer(), "Net.init is server-only")
	local folder = getFolder()
	local function make(className: string, names: { string })
		for _, name in names do
			if not folder:FindFirstChild(name) then
				local remote = Instance.new(className)
				remote.Name = name
				remote.Parent = folder
			end
		end
	end
	make("RemoteEvent", Net.Events)
	make("UnreliableRemoteEvent", Net.UnreliableEvents)
	make("RemoteFunction", Net.Functions)
end

local cache: { [string]: Instance } = {}

local function get(name: string): Instance
	local cached = cache[name]
	if cached then
		return cached
	end
	local folder = getFolder()
	local remote = if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name, 30)
	assert(remote, "Unknown remote: " .. name)
	cache[name] = remote
	return remote
end

function Net.event(name: string): RemoteEvent
	return get(name) :: RemoteEvent
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	return get(name) :: UnreliableRemoteEvent
end

function Net.func(name: string): RemoteFunction
	return get(name) :: RemoteFunction
end

export type Response = { ok: boolean, msg: string?, data: any? }

-- Client helper: ask the server to do something. Never errors; always returns a Response.
function Net.request(action: string, ...: any): Response
	assert(RunService:IsClient(), "Net.request is client-only")
	local args = table.pack(...)
	local success, result = pcall(function()
		return Net.func("Request"):InvokeServer(action, table.unpack(args, 1, args.n))
	end)
	if not success or type(result) ~= "table" then
		return { ok = false, msg = "Connection hiccup - try again!" }
	end
	return result
end

return Net
