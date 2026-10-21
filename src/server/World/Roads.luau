-- Roads: asphalt network with markings, intersections, curbs and street lamps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Layout = require(ReplicatedStorage:WaitForChild("CarsShared"):WaitForChild("WorldLayout"))

local Roads = {}

local ASPHALT = Color3.fromRGB(58, 60, 66)
local ASPHALT_DARK = Color3.fromRGB(48, 50, 55)
local WHITE = Color3.fromRGB(232, 232, 228)
local YELLOW = Color3.fromRGB(240, 190, 40)
local TOP = Layout.RoadTop
local MARK_Y = TOP + 0.03

local lampPositions: { { pos: Vector3, facing: Vector3 } } = {}

local function mark(parent: Instance, a: Vector3, b: Vector3, width: number, color: Color3)
	local strip = Build.strip(parent, a, b, width, 0.06, MARK_Y, color, Enum.Material.SmoothPlastic)
	if strip then
		strip.CanCollide = false
		strip.CanQuery = false
		strip.CanTouch = false
		strip.CastShadow = false
		strip.Name = "Marking"
	end
end

local function dashed(parent: Instance, a: Vector3, b: Vector3, width: number, color: Color3, dash: number, gap: number)
	local dir = b - a
	local len = dir.Magnitude
	if len < 1 then
		return
	end
	local u = dir / len
	local d = gap / 2
	while d + dash <= len do
		mark(parent, a + u * d, a + u * (d + dash), width, color)
		d += dash + gap
	end
end

-- One straight road from a to b (endpoints exactly where the asphalt starts/ends).
function Roads.segment(parent: Instance, a: Vector3, b: Vector3, w: number, style: string, opts: { lamps: boolean? }?)
	local road = Build.strip(parent, a, b, w, 1, TOP, ASPHALT, Enum.Material.Asphalt)
	if road then
		road.Name = "Road"
	end
	local dir = (b - a)
	local len = dir.Magnitude
	if len < 4 then
		return
	end
	local u = dir / len
	local right = Vector3.new(-u.Z, 0, u.X)
	local inset = 6 -- keep markings out of the junction boxes
	local ma, mb = a + u * inset, b - u * inset
	if (mb - ma):Dot(u) <= 0 then
		return
	end
	if style == "highway" then
		mark(parent, ma + right * 0.6, mb + right * 0.6, 0.45, YELLOW)
		mark(parent, ma - right * 0.6, mb - right * 0.6, 0.45, YELLOW)
		for _, s in { -1, 1 } do
			dashed(parent, ma + right * s * 14.5, mb + right * s * 14.5, 0.5, WHITE, 14, 22)
			mark(parent, ma + right * s * (w / 2 - 1.6), mb + right * s * (w / 2 - 1.6), 0.6, WHITE)
		end
	elseif style == "avenue" then
		mark(parent, ma + right * 0.5, mb + right * 0.5, 0.4, YELLOW)
		mark(parent, ma - right * 0.5, mb - right * 0.5, 0.4, YELLOW)
		for _, s in { -1, 1 } do
			mark(parent, ma + right * s * (w / 2 - 1.5), mb + right * s * (w / 2 - 1.5), 0.5, WHITE)
		end
	else
		dashed(parent, ma, mb, 0.45, WHITE, 10, 14)
		for _, s in { -1, 1 } do
			mark(parent, ma + right * s * (w / 2 - 1.4), mb + right * s * (w / 2 - 1.4), 0.45, WHITE)
		end
	end
	local o = opts or {}
	if o.lamps ~= false then
		local spacing = if style == "highway" then 160 else 130
		local d = spacing / 2
		local side = 1
		while d < len do
			local p = a + u * d + right * side * (w / 2 + 3)
			table.insert(lampPositions, { pos = p, facing = -right * side })
			if style ~= "highway" then
				side = -side
			end
			d += spacing
		end
	end
end

-- Square junction patch without markings.
function Roads.junction(parent: Instance, center: Vector3, size: number)
	local p = Build.box(
		parent,
		Vector3.new(size, 1, size),
		CFrame.new(center.X, TOP - 0.5, center.Z),
		ASPHALT_DARK,
		Enum.Material.Asphalt,
		"Junction"
	)
	return p
end

-- Zebra crossing across a road at `center`, stripes parallel to `along`.
function Roads.crosswalk(parent: Instance, center: Vector3, along: Vector3, roadWidth: number)
	local u = along.Unit
	local right = Vector3.new(-u.Z, 0, u.X)
	local n = math.floor((roadWidth - 4) / 3)
	for i = 0, n - 1 do
		local off = -roadWidth / 2 + 2.5 + i * 3
		local c = center + right * off
		mark(parent, c - u * 4, c + u * 4, 1.6, WHITE)
	end
end

local function buildLamps(parent: Instance)
	for _, l in lampPositions do
		local base = Vector3.new(l.pos.X, TOP, l.pos.Z)
		Build.pole(parent, base, 18, 0.7, Color3.fromRGB(70, 72, 80), Enum.Material.Metal)
		local armEnd = base + Vector3.new(0, 18, 0) + l.facing * 5
		local arm = Build.strip(parent, base + Vector3.new(0, 18, 0), armEnd, 0.4, 0.4, TOP + 18.2, Color3.fromRGB(70, 72, 80), Enum.Material.Metal)
		if arm then
			arm.CanCollide = false
		end
		local head = Build.part(parent, {
			size = Vector3.new(1.6, 0.5, 2.4),
			cframe = CFrame.lookAt(armEnd + Vector3.new(0, -0.1, 0), armEnd + Vector3.new(0, -0.1, 0) + l.facing),
			color = Color3.fromRGB(255, 236, 190),
			material = Enum.Material.SmoothPlastic,
			collide = false,
			shadow = false,
			name = "LampHead",
		})
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 110
		light.Range = 42
		light.Brightness = 2.2
		light.Color = Color3.fromRGB(255, 220, 170)
		light.Shadows = false
		light.Enabled = false
		light.Parent = head
		Build.tag(head, "StreetLight")
	end
	table.clear(lampPositions)
end

function Roads.build(root: Instance)
	local folder = Build.folder("Roads", root)
	local lamps = Build.folder("StreetLights", root)

	for _, r in Layout.Roads do
		Roads.segment(folder, r.a, r.b, r.w, r.style)
	end

	-- city grid: junction boxes at every node, streets between them
	local xs, zs = Layout.CityX, Layout.CityZ
	local sw = Layout.CityStreetWidth
	local function widthAt(x: number): number
		return if x == 0 then 44 else sw
	end
	for _, x in xs do
		for _, z in zs do
			Roads.junction(folder, Vector3.new(x, 0, z), sw).Size = Vector3.new(widthAt(x), 1, sw)
		end
	end
	for _, x in xs do
		local w = widthAt(x)
		for i = 1, #zs - 1 do
			local z0, z1 = zs[i], zs[i + 1]
			local half = sw / 2
			Roads.segment(folder, Vector3.new(x, 0, z0 - half), Vector3.new(x, 0, z1 + half), w, if x == 0 then "avenue" else "street")
		end
	end
	for _, z in zs do
		for i = 1, #xs - 1 do
			local x0, x1 = xs[i], xs[i + 1]
			Roads.segment(folder, Vector3.new(x0 + widthAt(x0) / 2, 0, z), Vector3.new(x1 - widthAt(x1) / 2, 0, z), sw, "street")
		end
	end
	-- crosswalks next to the junctions on the avenue
	for i, z in zs do
		Roads.crosswalk(folder, Vector3.new(0, 0, z + 28), Vector3.new(0, 0, 1), 44)
		if i < #zs then
			Roads.crosswalk(folder, Vector3.new(0, 0, z - 28), Vector3.new(0, 0, 1), 44)
		end
	end

	buildLamps(lamps)
end

return Roads
