-- Stunts: the stunt park (kickers, a bus jump, a mega ramp, quarter pipes,
-- bumps) and the drift arena (skid pads, cones, tire walls, grandstand).

local Build = require(script.Parent.Build)
local Layout = require(script.Parent.Layout)

local Stunts = {}

local TOP = Layout.RoadTop
local RAMP = Color3.fromRGB(210, 120, 40)
local RAMP2 = Color3.fromRGB(70, 140, 220)
local CONCRETE = Color3.fromRGB(150, 150, 148)

-- Wedge ramp: `foot` is the bottom-center of the low edge (on the ground),
-- `dir` the horizontal direction it rises towards.
local function ramp(parent: Instance, foot: Vector3, dir: Vector3, width: number, height: number, length: number, color: Color3?)
	local u = Vector3.new(dir.X, 0, dir.Z).Unit
	local center = foot + u * (length / 2) + Vector3.new(0, height / 2, 0)
	-- wedge rises towards its local +Z: point +Z along u
	local cf = CFrame.lookAt(center, center - u)
	local w = Build.wedge(parent, Vector3.new(width, height, length), cf, color or RAMP, Enum.Material.Concrete)
	-- stripes on the lip
	local lip = foot + u * length + Vector3.new(0, height, 0)
	Build.part(parent, {
		size = Vector3.new(width, 0.3, 1),
		cframe = CFrame.lookAt(lip - u * 0.5 + Vector3.new(0, 0.15, 0), lip - u * 0.5 + Vector3.new(0, 0.15, 0) + u),
		color = Color3.fromRGB(250, 250, 250),
		material = Enum.Material.SmoothPlastic,
		collide = false,
		shadow = false,
	})
	return w
end

-- Quarter pipe: a curved wall made of slabs along an arc.
local function quarterPipe(parent: Instance, foot: Vector3, dir: Vector3, width: number, radius: number, maxAngle: number)
	local u = Vector3.new(dir.X, 0, dir.Z).Unit
	local segments = 8
	local step = math.rad(maxAngle) / segments
	local center = foot + u * 0 + Vector3.new(0, radius, 0) -- arc center above the foot
	for i = 0, segments - 1 do
		local a0, a1 = i * step, (i + 1) * step
		-- points on the arc (start at the bottom, curve up towards u)
		local p0 = center + u * (math.sin(a0) * radius) - Vector3.new(0, math.cos(a0) * radius, 0)
		local p1 = center + u * (math.sin(a1) * radius) - Vector3.new(0, math.cos(a1) * radius, 0)
		local mid = (p0 + p1) / 2
		local len = (p1 - p0).Magnitude + 0.6
		local tangent = (p1 - p0).Unit
		local inward = (center - mid).Unit
		local cf = CFrame.lookAt(mid - inward * 0.5, mid - inward * 0.5 + tangent, inward)
		Build.part(parent, {
			size = Vector3.new(width, 1, len),
			cframe = cf,
			color = RAMP2,
			material = Enum.Material.Concrete,
			name = "QuarterPipe",
		})
	end
	-- backing wall
	local top = center + u * radius
	Build.box(parent, Vector3.new(width, radius * math.sin(math.rad(maxAngle)) + 1, 3), CFrame.lookAt(
		Vector3.new(top.X, TOP + radius * 0.5, top.Z) + u * 2,
		Vector3.new(top.X, TOP + radius * 0.5, top.Z) + u * 3
	), CONCRETE, Enum.Material.Concrete)
end

local function barrier(parent: Instance, a: Vector3, b: Vector3)
	local s = Build.strip(parent, a, b, 2, 2.4, TOP + 2.4, Color3.fromRGB(205, 205, 200), Enum.Material.Concrete)
	if s then
		s.Name = "Barrier"
	end
end

local function bus(parent: Instance, cf: CFrame)
	local body = Build.box(parent, Vector3.new(9, 9, 34), cf * CFrame.new(0, 5.5, 0), Color3.fromRGB(245, 190, 30), Enum.Material.SmoothPlastic, "WreckBus")
	Build.box(parent, Vector3.new(9.2, 3, 30), cf * CFrame.new(0, 7.5, 0), Color3.fromRGB(40, 50, 64), Enum.Material.Glass).CanCollide = false
	for _, z in { -11, 11 } do
		for _, x in { -4.6, 4.6 } do
			Build.cylinder(parent, 1.4, 3.6, cf * CFrame.new(x, 1.8, z), Color3.fromRGB(28, 28, 30))
		end
	end
	return body
end

function Stunts.buildPark(root: Instance)
	local folder = Build.folder("StuntPark", root)
	local c = Layout.StuntPark.center
	local s = Layout.StuntPark.size
	local x0, x1 = c.X - s.X / 2, c.X + s.X / 2
	local z0, z1 = c.Z - s.Y / 2, c.Z + s.Y / 2
	Build.box(folder, Vector3.new(s.X, 1, s.Y), CFrame.new(c.X, TOP - 0.5, c.Z), Color3.fromRGB(78, 80, 86), Enum.Material.Asphalt, "ParkFloor")

	-- perimeter barriers with entries (east at z = 0, south at x = -1200)
	barrier(folder, Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0))
	barrier(folder, Vector3.new(x0, 0, z0), Vector3.new(x0, 0, z1))
	barrier(folder, Vector3.new(x1, 0, z0), Vector3.new(x1, 0, -24))
	barrier(folder, Vector3.new(x1, 0, 24), Vector3.new(x1, 0, z1))
	barrier(folder, Vector3.new(x0, 0, z1), Vector3.new(-1224, 0, z1))
	barrier(folder, Vector3.new(-1176, 0, z1), Vector3.new(x1, 0, z1))

	-- kicker row near the south entry (rising north)
	local north = Vector3.new(0, 0, -1)
	ramp(folder, Vector3.new(-1350, TOP, 150), north, 24, 3, 14)
	ramp(folder, Vector3.new(-1300, TOP, 150), north, 24, 6, 24)
	ramp(folder, Vector3.new(-1245, TOP, 160), north, 28, 10, 36)

	-- bus jump: launch westwards over three buses, land on a down ramp
	ramp(folder, Vector3.new(-980, TOP, -150), Vector3.new(-1, 0, 0), 34, 14, 24)
	for _, x in { -1013, -1024, -1035 } do
		bus(folder, CFrame.new(x, TOP, -150))
	end
	ramp(folder, Vector3.new(-1114, TOP, -150), Vector3.new(1, 0, 0), 34, 12, 70, RAMP2)

	-- mega ramp along the west side: long climb, a deck with a kicker and a
	-- landing slope right behind it (works at any speed thanks to the slope)
	local mx = -1440
	local climbFoot, climbLen, deckH = 150, 200, 42
	local deckStart = climbFoot - climbLen
	ramp(folder, Vector3.new(mx, TOP, climbFoot), north, 40, deckH, climbLen)
	Build.box(folder, Vector3.new(40, deckH, 24), CFrame.new(mx, TOP + deckH / 2, deckStart - 12), RAMP, Enum.Material.Concrete, "MegaDeck")
	ramp(folder, Vector3.new(mx, TOP + deckH, deckStart - 10), north, 40, 4, 14)
	ramp(folder, Vector3.new(mx, TOP, deckStart - 30 - 220), Vector3.new(0, 0, 1), 46, deckH - 2, 220, RAMP2)
	for _, side in { -1, 1 } do
		Build.part(folder, {
			size = Vector3.new(1, 3, climbLen),
			cframe = CFrame.new(mx + side * 20.5, TOP + deckH / 2 + 1.5, climbFoot - climbLen / 2)
				* CFrame.Angles(math.atan2(deckH, climbLen), 0, 0),
			color = Color3.fromRGB(255, 200, 40),
			material = Enum.Material.Neon,
			collide = false,
			shadow = false,
		})
	end

	-- quarter pipes along the north barrier, facing south
	for _, x in { -1300, -1150, -1020 } do
		quarterPipe(folder, Vector3.new(x, TOP, -372), north, 60, 18, 72)
	end

	-- bumps field in the middle
	for i = 0, 9 do
		Build.cylinder(folder, 40, 5, CFrame.new(-1180, TOP - 0.6, 40 - i * 13), Color3.fromRGB(230, 200, 60), Enum.Material.Concrete)
	end

	-- a few container stacks as obstacles
	local rng = Build.rng(99)
	for _, p in { Vector3.new(-1060, 0, 120), Vector3.new(-990, 0, 60), Vector3.new(-1280, 0, -40), Vector3.new(-1080, 0, -280) } do
		local color = Color3.fromHSV(rng:NextNumber(), 0.6, 0.75)
		Build.box(folder, Vector3.new(12, 12, 30), CFrame.new(p.X, TOP + 6, p.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), color, Enum.Material.DiamondPlate, "Container")
	end

	Build.sign(folder, CFrame.new(-890, TOP, -36) * CFrame.Angles(0, -math.pi / 2, 0), 30, 7, "STUNT PARK", "SignStunts", Color3.fromRGB(120, 40, 20))
end

local function cone(parent: Instance, pos: Vector3): BasePart
	local base = Instance.new("Part")
	base.Name = "Cone"
	base.Size = Vector3.new(2, 0.3, 2)
	base.CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0))
	base.Color = Color3.fromRGB(255, 110, 20)
	base.Material = Enum.Material.SmoothPlastic
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Anchored = false
	base.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.5, 0.2, 1, 1)
	local body = Instance.new("Part")
	body.Name = "ConeBody"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(2.4, 1.1, 1.1)
	body.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	body.Color = Color3.fromRGB(255, 110, 20)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = false
	body.CustomPhysicalProperties = PhysicalProperties.new(0.2, 0.5, 0.2, 1, 1)
	local stripe = Instance.new("Part")
	stripe.Name = "ConeStripe"
	stripe.Shape = Enum.PartType.Cylinder
	stripe.Size = Vector3.new(0.4, 1.15, 1.15)
	stripe.CFrame = CFrame.new(pos + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	stripe.Color = Color3.fromRGB(245, 245, 245)
	stripe.Material = Enum.Material.SmoothPlastic
	stripe.Anchored = false
	stripe.Massless = true
	stripe.CanCollide = false
	for _, p in { body, stripe } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = base
		weld.Part1 = p
		weld.Parent = p
		p.Parent = base
	end
	base:SetAttribute("Home", base.CFrame)
	base.Parent = parent
	Build.tag(base, "Cone")
	return base
end

function Stunts.buildDrift(root: Instance)
	local folder = Build.folder("DriftArena", root)
	local c = Layout.DriftArena.center
	local s = Layout.DriftArena.size
	local x0, x1 = c.X - s.X / 2, c.X + s.X / 2
	local z0, z1 = c.Z - s.Y / 2, c.Z + s.Y / 2
	Build.box(folder, Vector3.new(s.X, 1, s.Y), CFrame.new(c.X, TOP - 0.5, c.Z), Color3.fromRGB(110, 112, 118), Enum.Material.Concrete, "ArenaFloor")
	-- skid pads
	for i, p in { Vector3.new(c.X - 90, 0, c.Z), Vector3.new(c.X + 90, 0, c.Z) } do
		Build.cylinder(folder, 0.06, 110, CFrame.new(p.X, TOP + 0.03, p.Z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 72, 78), Enum.Material.Asphalt).CanCollide =
			false
		Build.cylinder(folder, 0.08, 16, CFrame.new(p.X, TOP + 0.04, p.Z) * CFrame.Angles(0, 0, math.pi / 2), if i == 1 then Color3.fromRGB(255, 90, 40) else Color3.fromRGB(60, 160, 255), Enum.Material.Neon).CanCollide =
			false
	end
	-- tire walls around the arena (gaps at the west and south entries)
	local function tires(a: Vector3, b: Vector3)
		local d = b - a
		local n = math.floor(d.Magnitude / 4)
		for i = 0, n do
			local p = a + d * (i / math.max(n, 1))
			Build.cylinder(folder, 3, 4, CFrame.new(p.X, TOP + 1.5, p.Z) * CFrame.Angles(0, 0, math.pi / 2), if i % 2 == 0 then Color3.fromRGB(30, 30, 32) else Color3.fromRGB(230, 40, 40), Enum.Material.SmoothPlastic)
		end
	end
	tires(Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0))
	tires(Vector3.new(x1, 0, z0), Vector3.new(x1, 0, z1))
	tires(Vector3.new(x0, 0, z0), Vector3.new(x0, 0, -26))
	tires(Vector3.new(x0, 0, 26), Vector3.new(x0, 0, z1))
	tires(Vector3.new(x0, 0, z1), Vector3.new(c.X - 26, 0, z1))
	tires(Vector3.new(c.X + 26, 0, z1), Vector3.new(x1, 0, z1))
	-- cone slalom through the middle
	local cones = Build.folder("Cones", folder)
	for i = 0, 9 do
		cone(cones, Vector3.new(c.X - 135 + i * 30, TOP, c.Z + (if i % 2 == 0 then -60 else -80)))
		cone(cones, Vector3.new(c.X - 135 + i * 30, TOP, c.Z + 90))
	end
	-- grandstand on the north side
	for i = 0, 4 do
		Build.box(folder, Vector3.new(120, 2, 6), CFrame.new(c.X, TOP + 1 + i * 2, z0 - 8 - i * 6), Color3.fromRGB(70, 90, 130), Enum.Material.SmoothPlastic, "Stand")
	end
	Build.sign(folder, CFrame.new(x0 - 6, TOP, -40) * CFrame.Angles(0, math.pi / 2, 0), 30, 7, "DRIFT ARENA", "SignDrift", Color3.fromRGB(110, 20, 60))
end

return Stunts
