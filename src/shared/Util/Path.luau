-- Path: smooth movement for service customers and staff. The server stores a
-- path as model attributes once (MovePath, MoveStart, MoveSpeed, MoveReverse,
-- MoveY) and parks the model at the end; every client animates the trip
-- locally, so nothing is replicated per frame.

local Spline = require(script.Parent.Spline)

local Path = {}

export type Track = { samples: { Spline.Sample }, length: number }

function Path.encode(points: { Vector3 }): string
	local parts = table.create(#points)
	for i, p in points do
		parts[i] = string.format("%.1f,%.1f", p.X, p.Z)
	end
	return table.concat(parts, ";")
end

function Path.decode(text: string): { Vector3 }
	local out = {}
	for x, z in string.gmatch(text, "(-?[%d%.]+),(-?[%d%.]+)") do
		table.insert(out, Vector3.new(tonumber(x) :: number, 0, tonumber(z) :: number))
	end
	return out
end

function Path.new(points: { Vector3 }): Track
	if #points < 2 then
		local p = points[1] or Vector3.zero
		return { samples = { { pos = p, dir = Vector3.new(0, 0, -1), dist = 0 } }, length = 0 }
	end
	local samples, length = Spline.sample(points, false, 1)
	return { samples = samples, length = length }
end

-- Position and travel direction `d` studs along the track.
function Path.at(track: Track, d: number): (Vector3, Vector3)
	local s = track.samples
	if #s == 1 or d <= 0 then
		return s[1].pos, s[1].dir
	end
	if d >= track.length then
		return s[#s].pos, s[#s].dir
	end
	-- samples are evenly spaced
	local step = track.length / (#s - 1)
	local i = math.clamp(math.floor(d / step) + 1, 1, #s - 1)
	local a, b = s[i], s[i + 1]
	local t = math.clamp((d - a.dist) / step, 0, 1)
	local dir = a.dir:Lerp(b.dir, t)
	return a.pos:Lerp(b.pos, t), if dir.Magnitude > 1e-4 then dir.Unit else a.dir
end

-- Seconds a trip takes (eased start and stop).
function Path.duration(length: number, speed: number): number
	if length <= 0 or speed <= 0 then
		return 0
	end
	return length / speed + math.min(1.2, length / speed * 0.5)
end

-- Distance travelled after `elapsed` seconds (smooth start and stop).
function Path.distanceAt(length: number, speed: number, elapsed: number): number
	local total = Path.duration(length, speed)
	if total <= 0 or elapsed >= total then
		return length
	end
	if elapsed <= 0 then
		return 0
	end
	local t = elapsed / total
	return length * (t * t * (3 - 2 * t))
end

-- Ground CFrame for a model at distance d (reverse = driving backwards).
function Path.groundCFrame(track: Track, d: number, y: number, reverse: boolean?): CFrame
	local pos, dir = Path.at(track, d)
	local facing = if reverse then -dir else dir
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 1e-4 then
		flat = Vector3.new(0, 0, -1)
	end
	local at = Vector3.new(pos.X, y, pos.Z)
	return CFrame.lookAt(at, at + flat.Unit)
end

return Path
