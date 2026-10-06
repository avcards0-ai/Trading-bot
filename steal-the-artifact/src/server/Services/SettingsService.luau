--[[
	SettingsService
	Saves the player's client settings (volumes, VFX quality, accessibility toggles).
	Every key and value is validated against a whitelist.
]]

local RequestRouter = require(script.Parent.Parent.RequestRouter)

local SettingsService = { Name = "SettingsService" }

local S: { [string]: any }

local VALIDATORS: { [string]: (any) -> boolean } = {
	Music = function(v)
		return type(v) == "number" and v >= 0 and v <= 1
	end,
	SFX = function(v)
		return type(v) == "number" and v >= 0 and v <= 1
	end,
	VFX = function(v)
		return v == "Low" or v == "High"
	end,
	Shake = function(v)
		return type(v) == "boolean"
	end,
	Feed = function(v)
		return type(v) == "boolean"
	end,
	Global = function(v)
		return type(v) == "boolean"
	end,
	ReduceFlashing = function(v)
		return type(v) == "boolean"
	end,
}

function SettingsService:Init(services)
	S = services
end

function SettingsService:Start()
	RequestRouter.register("UpdateSetting", { Rate = 6, Burst = 12 }, function(player, key, value)
		local validate = type(key) == "string" and VALIDATORS[key]
		local data = S.DataService:Get(player)
		if not validate or not data or not validate(value) then
			return false, "Invalid setting"
		end
		data.Settings[key] = value
		S.DataService:MarkChanged(player, "Settings")
		return true
	end)
end

return SettingsService
