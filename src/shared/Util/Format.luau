-- Format: number/time/speed formatting shared by the HUD, garage and boards.

local Config = require(script.Parent.Parent.Config)

local Format = {}

-- 1234567 -> "1,234,567"
function Format.int(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return if n < 0 then "-" .. out else out
end

function Format.money(n: number): string
	return "$" .. Format.int(n)
end

-- Short form for big prices: 1250000 -> "$1.25M", 48000 -> "$48K"
function Format.moneyShort(n: number): string
	if n >= 1e6 then
		return (string.format("$%.2fM", n / 1e6):gsub("%.?0+M$", "M"))
	elseif n >= 1e4 then
		return string.format("$%dK", math.floor(n / 1000))
	end
	return Format.money(n)
end

-- 83.456 -> "1:23.46"
function Format.time(seconds: number): string
	if seconds ~= seconds or seconds == math.huge then
		return "--:--.--"
	end
	local m = math.floor(seconds / 60)
	local s = seconds - m * 60
	return string.format("%d:%05.2f", m, s)
end

-- studs/s -> displayed km/h
function Format.speed(studsPerSecond: number): number
	return math.floor(math.abs(studsPerSecond) * Config.SpeedDisplayFactor + 0.5)
end

return Format
