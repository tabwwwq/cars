-- Decor: trees, boulders, the speed trap gantry, area signs and map bounds.

local Build = require(script.Parent.Build)
local Layout = require(script.Parent.Layout)

local Decor = {}

local TOP = Layout.RoadTop

local function groundY(x: number, z: number, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -500, 0), params)
	return if hit then hit.Position.Y else 0
end

local function roundTree(parent: Instance, base: Vector3, rng: Random)
	local h = rng:NextNumber(10, 16)
	Build.pole(parent, base - Vector3.new(0, 0.5, 0), h, rng:NextNumber(1.4, 2), Color3.fromRGB(96, 66, 42), Enum.Material.Wood)
	local green = Color3.fromRGB(56, 128, 52):Lerp(Color3.fromRGB(110, 160, 60), rng:NextNumber())
	for k = 0, 2 do
		local d = rng:NextNumber(9, 13) - k * 1.5
		local off = Vector3.new(rng:NextNumber(-2, 2), h - 1 + k * 3.2, rng:NextNumber(-2, 2))
		local leaf = Build.ball(parent, d, base + off, green:Lerp(Color3.new(0, 0, 0), k * 0.06), Enum.Material.Grass)
		leaf.CanCollide = false
		leaf.CanQuery = false
	end
end

local function pineTree(parent: Instance, base: Vector3, rng: Random)
	local h = rng:NextNumber(14, 22)
	Build.pole(parent, base - Vector3.new(0, 0.5, 0), h * 0.4, 1.6, Color3.fromRGB(86, 58, 38), Enum.Material.Wood)
	local green = Color3.fromRGB(38, 92, 52):Lerp(Color3.fromRGB(60, 110, 60), rng:NextNumber())
	local layers = 4
	for k = 0, layers - 1 do
		local d = (layers - k) * 3.4 + 1
		local y = h * 0.3 + k * (h * 0.7 / layers)
		local p = Build.cylinder(parent, h * 0.7 / layers + 1, d, CFrame.new(base + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.pi / 2), green, Enum.Material.Grass)
		p.CanCollide = false
		p.CanQuery = false
	end
end

-- Distance from point to segment on the ground plane
local function segDist(px: number, pz: number, a: Vector3, b: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local apx, apz = px - a.X, pz - a.Z
	local len2 = abx * abx + abz * abz
	local t = if len2 > 0 then math.clamp((apx * abx + apz * abz) / len2, 0, 1) else 0
	local dx, dz = apx - abx * t, apz - abz * t
	return math.sqrt(dx * dx + dz * dz)
end

local function inRect(x: number, z: number, center: Vector3, size: Vector2, margin: number): boolean
	return math.abs(x - center.X) < size.X / 2 + margin and math.abs(z - center.Z) < size.Y / 2 + margin
end

-- `paths` = list of { points = {Vector3}, clearance = number } (tracks, trail)
function Decor.build(root: Instance, cityTrees: { Vector3 }, paths: { { points: { Vector3 }, clearance: number } })
	local folder = Build.folder("Decor", root)
	local treeFolder = Build.folder("Trees", folder)
	local rng = Build.rng(4242)
	local ignore = { treeFolder }

	for _, p in cityTrees do
		roundTree(treeFolder, p, rng)
	end

	local function free(x: number, z: number): boolean
		if inRect(x, z, Layout.Plaza.center, Layout.Plaza.size, 25) then
			return false
		end
		if inRect(x, z, Layout.StuntPark.center, Layout.StuntPark.size, 25) then
			return false
		end
		if inRect(x, z, Layout.DriftArena.center, Layout.DriftArena.size, 40) then
			return false
		end
		if x > -735 and x < 735 and z > -1535 and z < -415 then
			return false -- city
		end
		if math.abs(z - 450) < 50 then
			return false -- highway band
		end
		for _, r in Layout.Roads do
			if segDist(x, z, r.a, r.b) < r.w / 2 + 14 then
				return false
			end
		end
		for _, path in paths do
			local pts = path.points
			for i = 1, #pts - 1 do
				if segDist(x, z, pts[i], pts[i + 1]) < path.clearance then
					return false
				end
			end
		end
		return true
	end

	local half = Layout.Half - Layout.Rim.width - 20
	local placed = 0
	local attempts = 0
	while placed < 240 and attempts < 4000 do
		attempts += 1
		local x = rng:NextNumber(-half, half)
		local z = rng:NextNumber(-half, half)
		if free(x, z) then
			local y = groundY(x, z, ignore)
			local base = Vector3.new(x, y, z)
			if z > Layout.SouthHills.start or z < Layout.NorthHills.start or y > 8 then
				pineTree(treeFolder, base, rng)
			else
				roundTree(treeFolder, base, rng)
			end
			placed += 1
		end
	end

	-- boulders in the hills
	local rocks = Build.folder("Rocks", folder)
	local count = 0
	attempts = 0
	while count < 45 and attempts < 1500 do
		attempts += 1
		local x = rng:NextNumber(-half, half)
		local z = rng:NextNumber(Layout.SouthHills.start + 80, half)
		if free(x, z) then
			local y = groundY(x, z, ignore)
			local d = rng:NextNumber(5, 14)
			local rock = Build.ball(rocks, d, Vector3.new(x, y + d * 0.2, z), Color3.fromRGB(110, 108, 104):Lerp(Color3.fromRGB(150, 140, 120), rng:NextNumber()), Enum.Material.Slate)
			rock.Size = Vector3.new(d * rng:NextNumber(1, 1.6), d * rng:NextNumber(0.6, 1), d * rng:NextNumber(1, 1.5))
			count += 1
		end
	end

	-- speed trap gantry over the highway
	local st = Layout.SpeedTrap
	local gantry = Build.folder("SpeedTrap", folder)
	for _, side in { -1, 1 } do
		Build.box(gantry, Vector3.new(2.5, 26, 2.5), CFrame.new(st.x, TOP + 13, st.z + side * (st.halfWidth + 4)), Color3.fromRGB(60, 64, 74), Enum.Material.Metal)
	end
	local beam = Build.box(gantry, Vector3.new(4, 7, (st.halfWidth + 5) * 2), CFrame.new(st.x, TOP + 24, st.z), Color3.fromRGB(26, 28, 36), Enum.Material.SmoothPlastic, "SpeedTrapBeam")
	local display = Build.text(beam, Enum.NormalId.Left, "SPEED TRAP", { locKey = "SignSpeedTrap", color = Color3.fromRGB(255, 70, 50) })
	display.Size = UDim2.fromScale(1, 0.45)
	local readout = Build.text(beam, Enum.NormalId.Left, "---", { color = Color3.fromRGB(255, 220, 60), font = Enum.Font.Code })
	readout.Name = "Readout"
	readout.Size = UDim2.fromScale(1, 0.55)
	readout.Position = UDim2.fromScale(0, 0.45)
	readout:SetAttribute("SpeedTrapReadout", true)
	Build.tag(readout, "SpeedTrapReadout")
	for _, side in { -1, 1 } do
		local cam = Build.box(gantry, Vector3.new(2, 1.4, 2), CFrame.new(st.x - 2.5, TOP + 20, st.z + side * 12), Color3.fromRGB(40, 40, 46))
		cam.CanCollide = false
		Build.part(gantry, {
			size = Vector3.new(0.2, 0.8, 0.8),
			cframe = CFrame.new(st.x - 3.6, TOP + 20, st.z + side * 12),
			color = Color3.fromRGB(255, 40, 40),
			material = Enum.Material.Neon,
			collide = false,
		})
	end

	-- area signs
	Build.sign(folder, CFrame.new(-1030, TOP, 492) * CFrame.Angles(0, math.pi / 2, 0), 26, 6, "OFFROAD", "SignTrail", Color3.fromRGB(110, 80, 30))
	Build.sign(folder, CFrame.new(1180, TOP, 380) * CFrame.Angles(0, math.pi / 2, 0), 26, 6, "RACES", "SignRaces", Color3.fromRGB(20, 60, 90))
	Build.sign(folder, CFrame.new(-1600, TOP, 410), 26, 6, "HIGHWAY", "SignHighway", Color3.fromRGB(20, 90, 50))

	-- invisible map bounds
	local bounds = Build.folder("Bounds", folder)
	local wh = Layout.WallHalf
	-- parts are limited to 2048 studs, so each side is two halves
	for _, axis in { "x", "z" } do
		for _, sign in { -1, 1 } do
			for _, halfSign in { -1, 1 } do
				local along = halfSign * wh / 2
				local pos = if axis == "x" then Vector3.new(sign * wh, 300, along) else Vector3.new(along, 300, sign * wh)
				local size = if axis == "x" then Vector3.new(4, 800, wh) else Vector3.new(wh, 800, 4)
				local wall = Build.part(bounds, {
					size = size,
					cframe = CFrame.new(pos),
					transparency = 1,
					name = "Bound",
					shadow = false,
				})
				wall.CanQuery = false
			end
		end
	end
end

return Decor
