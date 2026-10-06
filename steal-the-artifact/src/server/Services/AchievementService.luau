--[[
	AchievementService
	Grants achievements (Gems + cosmetic Titles) as stats cross their goals. Checks run on
	stat changes plus level / rebirth / collection changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Achievements = require(Shared.Config.Achievements)
local Progression = require(Shared.Progression)

local GameEvents = require(script.Parent.Parent.GameEvents)

local AchievementService = { Name = "AchievementService" }

local S: { [string]: any }

function AchievementService:Init(services)
	S = services
end

local function statValue(data: any, stat: string): number
	if stat == "Level" then
		return data.Level
	elseif stat == "Rebirths" then
		return data.Rebirths
	elseif stat == "Discovered" then
		return Progression.discoveredCount(data)
	end
	return data.Stats[stat] or 0
end

function AchievementService:Check(player: Player, stat: string?)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local list = stat and Achievements.ByStat[stat] or Achievements.List
	for _, achievement in list do
		if not data.Achievements[achievement.Id] and statValue(data, achievement.Stat) >= achievement.Goal then
			data.Achievements[achievement.Id] = os.time()
			S.DataService:MarkChanged(player, "Achievements")
			S.EconomyService:AddGems(player, achievement.Gems)
			if achievement.Title then
				data.Titles[achievement.Title] = true
				S.DataService:MarkChanged(player, "Titles")
			end
			S.AnnouncementService:Notify(
				player,
				"reward",
				string.format(
					"%s ACHIEVEMENT: %s  +%d 💎%s",
					achievement.Icon,
					achievement.Name,
					achievement.Gems,
					achievement.Title and ("  + Title «" .. achievement.Title .. "»") or ""
				),
				{ Big = true }
			)
			S.AnnouncementService:Effect("Achievement", { UserId = player.UserId, Id = achievement.Id }, nil)
			if achievement.Hidden or achievement.Gems >= 100 then
				S.AnnouncementService:Feed(
					"🏅",
					string.format("<b>%s</b> unlocked <b>%s</b>!", S.AnnouncementService.name(player), achievement.Name)
				)
			end
		end
	end
end

function AchievementService:Start()
	S.DataService.StatChanged:Connect(function(player, stat)
		self:Check(player, stat)
	end)
	S.DataService.Changed:Connect(function(player, key)
		if key == "Discovered" then
			self:Check(player, "Discovered")
		end
	end)
	GameEvents.LevelUp:Connect(function(player)
		self:Check(player, "Level")
	end)
	GameEvents.Rebirthed:Connect(function(player)
		self:Check(player, "Rebirths")
	end)
	S.DataService.Loaded:Connect(function(player, data)
		-- VIP title is granted by ShopService; make sure older saves have earned titles too.
		for id in data.Achievements do
			local achievement = Achievements.ById[id]
			if achievement and achievement.Title then
				data.Titles[achievement.Title] = true
			end
		end
		self:Check(player)
	end)
end

return AchievementService
