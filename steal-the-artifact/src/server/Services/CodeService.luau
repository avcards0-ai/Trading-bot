--[[
	CodeService
	Redeem promo codes. The code list is server-only, each code works once per player,
	and attempts are rate limited so codes can't be brute-forced.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)

local Codes = require(script.Parent.Parent.Private.Codes)
local RequestRouter = require(script.Parent.Parent.RequestRouter)
local V = RequestRouter.V

local CodeService = { Name = "CodeService" }

local S: { [string]: any }

function CodeService:Init(services)
	S = services
end

function CodeService:Redeem(player: Player, raw: string): (boolean, string?)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Still loading..."
	end
	local code = string.upper((string.gsub(raw, "%s+", "")))
	local def = Codes[code]
	if not def then
		return false, "That code doesn't exist (or it's a secret we haven't revealed yet 👀)"
	end
	if data.Codes[code] then
		return false, "You already redeemed that code!"
	end
	if def.Expires and os.time() > def.Expires then
		return false, "That code has expired"
	end
	if def.MinLevel and data.Level < def.MinLevel and data.Rebirths == 0 then
		return false, string.format("Reach level %d to use this code", def.MinLevel)
	end
	data.Codes[code] = os.time()
	S.DataService:MarkChanged(player, "Codes")
	local parts = {}
	if def.Cash then
		local cash = S.EconomyService:AddCash(player, def.Cash * (1 + (data.Level - 1) * 0.1), false)
		table.insert(parts, "+" .. Format.cash(cash))
	end
	if def.Gems then
		S.EconomyService:AddGems(player, def.Gems)
		table.insert(parts, "+" .. def.Gems .. " 💎")
	end
	return true, "Code redeemed! " .. table.concat(parts, "  ")
end

function CodeService:Start()
	RequestRouter.register("RedeemCode", { Rate = 0.4, Burst = 3, Validate = V.args(V.str(32)) }, function(player, code)
		return self:Redeem(player, code)
	end)
end

return CodeService
