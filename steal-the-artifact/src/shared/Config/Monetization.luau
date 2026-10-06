--[[
	Monetization (fair, cosmetic-only)

	Replace the 0 ids with your own Game Pass / Developer Product ids from the Creator
	Dashboard. Anything left at 0 shows as "Coming soon" in the shop and can't be bought.

	What Robux can buy:
	  * Gems           - spent ONLY on cosmetics (trails, auras, vault skins, emotes)
	  * VIP pass       - cosmetics + a gold name tag + a few bonus Gems each daily reward
	  * Cosmetic Locker+ - more outfit loadout slots and emote wheel slots
	  * Private servers - enable them in Game Settings > Monetization (no code needed)

	What Robux can NEVER buy: Cash, XP, levels, artifacts, backpack space, speed, steal
	speed, security upgrades, raid shields, perks or rebirths. That's a hard rule; the
	server has no code path that turns a purchase into any of those.
]]

local Monetization = {}

Monetization.GamePasses = {
	VIP = {
		Id = 0,
		Name = "VIP Thief",
		Icon = "👑",
		PriceHint = 299,
		Perks = {
			"Gold VIP name tag + chat tag",
			"VIP Gold trail, Golden Glow aura, VIP Penthouse vault skin",
			"+10 bonus Gems on every daily reward",
		},
	},
	Locker = {
		Id = 0,
		Name = "Cosmetic Locker+",
		Icon = "🧳",
		PriceHint = 99,
		Perks = {
			"8 saved outfit loadouts (instead of 2)",
			"8 emote wheel slots (instead of 4)",
		},
	},
}

Monetization.Products = {
	{ Key = "Gems100", Id = 0, Gems = 100, Bonus = 0, PriceHint = 49, Name = "Pouch of Gems" },
	{ Key = "Gems550", Id = 0, Gems = 500, Bonus = 50, PriceHint = 229, Name = "Sack of Gems" },
	{ Key = "Gems1200", Id = 0, Gems = 1000, Bonus = 200, PriceHint = 449, Name = "Chest of Gems" },
	{ Key = "Gems3000", Id = 0, Gems = 2400, Bonus = 600, PriceHint = 899, Name = "Vault of Gems" },
}

Monetization.ProductById = {} :: { [number]: any }
for _, product in Monetization.Products do
	if product.Id ~= 0 then
		Monetization.ProductById[product.Id] = product
	end
end

return Monetization
