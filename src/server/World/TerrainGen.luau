-- TerrainGen: grass base, rolling hills (south/north), a mountain rim around
-- the map and the dirt trail carved through the southern hills.
-- Heights come from layered math.noise and are written with WriteVoxels
-- in 64-stud chunks; chunks that are completely flat are skipped.


local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage:WaitForChild("CarsShared"):WaitForChild("WorldLayout"))

local TerrainGen = {}

local VOXEL = 4
local CHUNK = 64
local BASE = -8 -- bottom of the terrain

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Raw terrain height and surface material at (x, z), before the trail is carved.
function TerrainGen.rawHeight(x: number, z: number): (number, Enum.Material)
	local half = Layout.Half
	local h = 0
	local material = Enum.Material.Grass

	local south = smoothstep(Layout.SouthHills.start, Layout.SouthHills.full, z)
	if south > 0 then
		local n = math.noise(x / 460, z / 460, 1.7) * 0.65 + math.noise(x / 180, z / 180, 8.3) * 0.28 + math.noise(x / 55, z / 55, 3.1) * 0.06
		h = math.max(h, south * (16 + n * 46))
		-- dunes in the south east
		local dune = math.noise(x / 300, z / 300, 21.5)
		if x > 250 and dune > 0.05 then
			material = Enum.Material.Sand
		end
	end
	local north = smoothstep(Layout.NorthHills.start, Layout.NorthHills.full, z)
	if north > 0 then
		local n = math.noise(x / 300, z / 300, 5.5) * 0.7 + math.noise(x / 90, z / 90, 2.2) * 0.2
		h = math.max(h, north * (22 + n * 40))
	end

	-- mountain rim close to the map edge
	local edge = math.min(half - math.abs(x), half - math.abs(z))
	local rim = smoothstep(Layout.Rim.width, 0, edge)
	if rim > 0 then
		local n = math.noise(x / 120, z / 120, 9.9) * 0.5 + 0.5
		local rh = rim * (Layout.Rim.height * (0.6 + 0.6 * n))
		if rh > h then
			h = rh
			if rim > 0.45 then
				material = Enum.Material.Rock
			end
		end
	end
	if h > 52 and material == Enum.Material.Grass then
		material = Enum.Material.Rock
	end
	return math.max(h, 0), material
end

-- Returns true if a chunk can't contain any hills (fast path).
local function chunkIsFlat(x0: number, z0: number): boolean
	local half = Layout.Half
	local x1, z1 = x0 + CHUNK, z0 + CHUNK
	if z1 > Layout.SouthHills.start or z0 < Layout.NorthHills.start then
		return false
	end
	local edge = math.min(half - math.max(math.abs(x0), math.abs(x1)), half - math.max(math.abs(z0), math.abs(z1)))
	return edge > Layout.Rim.width
end

export type TrailInfo = {
	samples: { { pos: Vector3, dir: Vector3, dist: number } },
	width: number,
}

-- Carves the trail: returns a column map { [index] = { h, dist } } and the
-- smoothed trail heights per sample (so checkpoints know where the road is).
local function rasterizeTrail(trail: TrailInfo): ({ [number]: { h: number, d: number } }, { number })
	local samples = trail.samples
	local raw = {}
	for i, s in samples do
		raw[i] = TerrainGen.rawHeight(s.pos.X, s.pos.Z)
	end
	-- smooth twice with a moving average so the road has gentle grades
	local smooth = raw
	for _ = 1, 3 do
		local nxt = {}
		for i = 1, #smooth do
			local sum, n = 0, 0
			for k = -8, 8 do
				local j = math.clamp(i + k, 1, #smooth)
				sum += smooth[j]
				n += 1
			end
			nxt[i] = sum / n
		end
		smooth = nxt
	end

	local half = Layout.Half
	local cols = math.floor(half * 2 / VOXEL)
	local reach = trail.width / 2 + 30
	local map: { [number]: { h: number, d: number } } = {}
	for i, s in samples do
		local cx0 = math.floor((s.pos.X - reach + half) / VOXEL)
		local cx1 = math.floor((s.pos.X + reach + half) / VOXEL)
		local cz0 = math.floor((s.pos.Z - reach + half) / VOXEL)
		local cz1 = math.floor((s.pos.Z + reach + half) / VOXEL)
		for cx = cx0, cx1 do
			for cz = cz0, cz1 do
				local x = cx * VOXEL - half + VOXEL / 2
				local z = cz * VOXEL - half + VOXEL / 2
				local dx, dz = x - s.pos.X, z - s.pos.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d <= reach then
					local key = cx * cols + cz
					local cur = map[key]
					if not cur or d < cur.d then
						map[key] = { h = smooth[i], d = d }
					end
				end
			end
		end
	end
	return map, smooth
end

-- Final height/material including the trail.
local function finalHeight(x: number, z: number, trailMap, trailWidth: number): (number, Enum.Material)
	local h, mat = TerrainGen.rawHeight(x, z)
	if trailMap then
		local half = Layout.Half
		local cols = math.floor(half * 2 / VOXEL)
		local key = math.floor((x + half) / VOXEL) * cols + math.floor((z + half) / VOXEL)
		local t = trailMap[key]
		if t then
			local inner = trailWidth / 2
			local blend = smoothstep(inner, inner + 30, t.d)
			h = t.h + (h - t.h) * blend
			-- dirt road with a ragged edge
			local edge = inner + 2 + (if math.noise(x / 9, z / 9, 4.4) > 0 then 4 else 0)
			if t.d < edge then
				mat = Enum.Material.Ground
			end
		end
	end
	return h, mat
end

-- Only the smoothed trail heights (used when the world was baked in Studio).
function TerrainGen.trailHeights(trail: TrailInfo): { number }
	local _, heights = rasterizeTrail(trail)
	return heights
end

-- Writes the whole terrain. `trail` may be nil. Returns trail heights (or nil).
function TerrainGen.generate(terrain: Terrain, trail: TrailInfo?): { number }?
	local half = Layout.Half
	terrain:Clear()

	-- flat grass base everywhere (8 studs deep), in tiles
	local tile = 512
	local x = -half
	while x < half do
		local z = -half
		while z < half do
			local sx = math.min(tile, half - x)
			local sz = math.min(tile, half - z)
			terrain:FillBlock(CFrame.new(x + sx / 2, BASE / 2, z + sz / 2), Vector3.new(sx, -BASE, sz), Enum.Material.Grass)
			z += tile
		end
		x += tile
	end

	local trailMap, trailHeights = nil, nil
	local trailWidth = 0
	if trail then
		trailMap, trailHeights = rasterizeTrail(trail)
		trailWidth = trail.width
	end

	local cpc = CHUNK // VOXEL -- columns per chunk
	local cx = -half
	local written = 0
	while cx < half do
		local cz = -half
		while cz < half do
			if not chunkIsFlat(cx, cz) then
				local heights = table.create(cpc * cpc)
				local mats = table.create(cpc * cpc)
				local maxH = 0
				for i = 0, cpc - 1 do
					for k = 0, cpc - 1 do
						local wx = cx + i * VOXEL + VOXEL / 2
						local wz = cz + k * VOXEL + VOXEL / 2
						local h, m = finalHeight(wx, wz, trailMap, trailWidth)
						heights[i * cpc + k + 1] = h
						mats[i * cpc + k + 1] = m
						if h > maxH then
							maxH = h
						end
					end
				end
				if maxH > 0.5 then
					local top = math.ceil((maxH + VOXEL) / VOXEL) * VOXEL
					local layers = (top - BASE) // VOXEL
					local materials = table.create(cpc)
					local occupancy = table.create(cpc)
					for i = 1, cpc do
						local mx = table.create(layers)
						local ox = table.create(layers)
						for j = 1, layers do
							mx[j] = table.create(cpc)
							ox[j] = table.create(cpc)
						end
						for k = 1, cpc do
							local h = heights[(i - 1) * cpc + k]
							local m = mats[(i - 1) * cpc + k]
							for j = 1, layers do
								local y0 = BASE + (j - 1) * VOXEL
								local occ = math.clamp((h - y0) / VOXEL, 0, 1)
								if occ > 0.02 then
									mx[j][k] = m
									ox[j][k] = occ
								else
									mx[j][k] = Enum.Material.Air
									ox[j][k] = 0
								end
							end
						end
						materials[i] = mx
						occupancy[i] = ox
					end
					local region = Region3.new(Vector3.new(cx, BASE, cz), Vector3.new(cx + CHUNK, top, cz + CHUNK))
					terrain:WriteVoxels(region, VOXEL, materials, occupancy)
					written += 1
				end
			end
			cz += CHUNK
		end
		cx += CHUNK
		-- keep the server responsive while generating
		task.wait()
	end
	return trailHeights
end

return TerrainGen
