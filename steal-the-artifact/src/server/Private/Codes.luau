--[[
	Codes (server-only - lives in ServerScriptService, never replicated to clients)

	Keys are upper-case. Optional fields:
	  Cash, Gems   - rewards (Cash is multiplied by the player's level scale)
	  Expires      - os.time() after which the code stops working
	  MinLevel     - level required to redeem
	Add a new code here and publish; every server picks it up on its next start.
]]

return {
	LAUNCH = { Cash = 1000, Gems = 25 },
	STICKYFINGERS = { Cash = 750 },
	BONK = { Gems = 15 },
	BANANA = { Cash = 500, Gems = 10 },
	SECRETROOM = { Gems = 40, MinLevel = 10 },
	THANKYOU = { Cash = 2500, Gems = 20, MinLevel = 5 },
}
