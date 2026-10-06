--[[
	Format
	Number / time / text helpers shared by the server (signs, feed) and the client (UI).
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234 -> "1.23K", 15300000 -> "15.3M"
function Format.abbreviate(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local text = tostring(math.floor(n))
		return negative and "-" .. text or text
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / (1000 ^ tier)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	text = text:gsub("%.?0+$", "") .. SUFFIXES[tier + 1]
	return negative and "-" .. text or text
end

function Format.cash(n: number): string
	return "$" .. Format.abbreviate(n)
end

-- 1234567 -> "1,234,567"
function Format.commas(n: number): string
	local text = tostring(math.floor(n))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""):gsub("^%-,", "-"))
end

-- 75 -> "1:15", 3725 -> "1:02:05"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- 3725 -> "1h 2m"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 86400 then
		return string.format("%dd %dh", seconds // 86400, (seconds % 86400) // 3600)
	elseif seconds >= 3600 then
		return string.format("%dh %dm", seconds // 3600, (seconds % 3600) // 60)
	elseif seconds >= 60 then
		return string.format("%dm %ds", seconds // 60, seconds % 60)
	end
	return string.format("%ds", seconds)
end

function Format.percent(fraction: number, decimals: number?): string
	return string.format("%." .. tostring(decimals or 0) .. "f%%", fraction * 100)
end

function Format.ordinal(n: number): string
	local lastTwo = n % 100
	if lastTwo >= 11 and lastTwo <= 13 then
		return n .. "th"
	end
	local last = n % 10
	if last == 1 then
		return n .. "st"
	elseif last == 2 then
		return n .. "nd"
	elseif last == 3 then
		return n .. "rd"
	end
	return n .. "th"
end

function Format.colorHex(color: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

-- Wraps text in a RichText color tag.
function Format.rich(text: string, color: Color3): string
	return string.format('<font color="%s">%s</font>', Format.colorHex(color), text)
end

-- Escapes characters that would break RichText markup (player names can't contain these,
-- but this keeps any future user-facing strings safe).
function Format.escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

return Format
