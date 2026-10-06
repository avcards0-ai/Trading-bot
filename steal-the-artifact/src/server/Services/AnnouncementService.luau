--[[
	AnnouncementService
	Toasts, the kill/steal feed, big banners and cross-server GLOBAL announcements
	(MessagingService) for Legendary+ steals. Also routes world VFX to nearby clients.
]]

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Util.Format)

local AnnouncementService = { Name = "AnnouncementService" }

local GLOBAL_TOPIC = "STA_GlobalAnnouncements_v1"
local MAX_GLOBALS_PER_MINUTE = 20

local publishTimes: { number } = {}
local seenGlobals: { [string]: number } = {}

export type FeedEntry = { Icon: string, Text: string, Color: Color3?, Big: boolean? }

-- Toast for one player. kind: info | success | error | warning | reward
function AnnouncementService:Notify(player: Player, kind: string, text: string, options: { [string]: any }?)
	Net.event("Notify"):FireClient(player, kind, text, options)
end

function AnnouncementService:NotifyAll(kind: string, text: string, options: { [string]: any }?)
	Net.event("Notify"):FireAllClients(kind, text, options)
end

-- Feed line for everyone. `text` may contain RichText.
function AnnouncementService:Feed(icon: string, text: string, color: Color3?, big: boolean?)
	Net.event("Feed"):FireAllClients({ Icon = icon, Text = text, Color = color, Big = big })
end

function AnnouncementService.name(player: Player): string
	return Format.escape(player.DisplayName)
end

-- Big banner in this server only.
function AnnouncementService:Announce(entry: { [string]: any })
	Net.event("Announce"):FireAllClients(entry)
end

-- Banner in EVERY server. Falls back to local-only if MessagingService is unavailable.
function AnnouncementService:Global(entry: { [string]: any })
	entry.Global = true
	entry.Id = entry.Id or (game.JobId .. "_" .. tostring(os.clock()))
	entry.ServerId = game.JobId
	-- Always show locally right away (and remember it so the echo isn't shown twice).
	seenGlobals[entry.Id] = os.clock()
	self:Announce(entry)

	local now = os.clock()
	for i = #publishTimes, 1, -1 do
		if now - publishTimes[i] > 60 then
			table.remove(publishTimes, i)
		end
	end
	if #publishTimes >= MAX_GLOBALS_PER_MINUTE then
		return
	end
	table.insert(publishTimes, now)
	task.spawn(function()
		local ok, err = pcall(MessagingService.PublishAsync, MessagingService, GLOBAL_TOPIC, entry)
		if not ok then
			warn("[Announce] Global publish failed:", err)
		end
	end)
end

-- World VFX to every client within `radius` of `position` (or everyone if no position).
function AnnouncementService:Effect(kind: string, data: { [string]: any }, position: Vector3?, radius: number?)
	local remote = Net.unreliable("Effect")
	if not position then
		remote:FireAllClients(kind, data)
		return
	end
	local range = radius or 300
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - position).Magnitude <= range then
			remote:FireClient(player, kind, data)
		end
	end
end

function AnnouncementService:Start()
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(GLOBAL_TOPIC, function(message)
				local entry = message.Data
				if type(entry) ~= "table" or type(entry.Id) ~= "string" then
					return
				end
				if seenGlobals[entry.Id] then
					return
				end
				seenGlobals[entry.Id] = os.clock()
				-- Only fields we expect; this payload came from another server.
				Net.event("Announce"):FireAllClients({
					Kind = tostring(entry.Kind or "Steal"),
					PlayerName = tostring(entry.PlayerName or "Someone"),
					ArtifactId = tostring(entry.ArtifactId or ""),
					Rarity = tostring(entry.Rarity or "Legendary"),
					Mutation = entry.Mutation and tostring(entry.Mutation) or nil,
					ZoneName = tostring(entry.ZoneName or ""),
					Global = true,
					Remote = true,
				})
			end)
		end)
		if not ok then
			warn("[Announce] Cross-server announcements unavailable:", err)
		end
	end)

	-- Forget old global ids
	task.spawn(function()
		while true do
			task.wait(120)
			local now = os.clock()
			for id, at in seenGlobals do
				if now - at > 300 then
					seenGlobals[id] = nil
				end
			end
		end
	end)
end

return AnnouncementService
