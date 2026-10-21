-- Spline: Catmull-Rom curves used to lay out race tracks and their checkpoints.

local Spline = {}

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- Samples the curve densely, then resamples at an even spacing.
-- Returns { { pos: Vector3, dir: Vector3, dist: number } }
export type Sample = { pos: Vector3, dir: Vector3, dist: number }

function Spline.sample(points: { Vector3 }, closed: boolean, spacing: number): ({ Sample }, number)
	local n = #points
	assert(n >= 2, "Spline needs at least two points")
	local function at(i: number): Vector3
		if closed then
			return points[((i - 1) % n) + 1]
		end
		return points[math.clamp(i, 1, n)]
	end
	local dense: { Vector3 } = {}
	local segments = if closed then n else n - 1
	local per = 24
	for i = 1, segments do
		for k = 0, per - 1 do
			table.insert(dense, catmull(at(i - 1), at(i), at(i + 1), at(i + 2), k / per))
		end
	end
	table.insert(dense, if closed then dense[1] else points[n])

	-- cumulative length
	local cum = { 0 }
	for i = 2, #dense do
		cum[i] = cum[i - 1] + (dense[i] - dense[i - 1]).Magnitude
	end
	local total = cum[#dense]
	local count = math.max(2, math.floor(total / spacing + 0.5))
	local step = total / count
	local out: { Sample } = {}
	local j = 1
	local last = if closed then count - 1 else count
	for i = 0, last do
		local d = i * step
		while j < #dense - 1 and cum[j + 1] < d do
			j += 1
		end
		local segLen = cum[j + 1] - cum[j]
		local t = if segLen > 0 then (d - cum[j]) / segLen else 0
		local pos = dense[j]:Lerp(dense[j + 1], math.clamp(t, 0, 1))
		local dir = dense[j + 1] - dense[j]
		dir = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.new(0, 0, -1)
		table.insert(out, { pos = pos, dir = dir, dist = d })
	end
	return out, total
end

return Spline
