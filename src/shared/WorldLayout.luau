-- Layout: where everything in the world lives. All values are world studs,
-- y = 0 is the ground, -Z is north. Roads sit on top of the ground at ROAD_TOP.

local Layout = {}

Layout.Half = 1952 -- terrain half size (multiple of 4)
Layout.WallHalf = 1940 -- invisible boundary walls
Layout.RoadTop = 0.2

local function v(x: number, z: number): Vector3
	return Vector3.new(x, 0, z)
end
Layout.v = v

-- Areas (center + size on the ground plane)
Layout.Plaza = { center = v(0, 0), size = Vector2.new(320, 240) }
Layout.StuntPark = { center = v(-1200, -100), size = Vector2.new(600, 600) }
Layout.DriftArena = { center = v(700, 0), size = Vector2.new(360, 300) }
Layout.SpeedTrap = { x = 1500, z = 450, halfWidth = 32 }

-- City grid
Layout.CityX = { -700, -350, 0, 350, 700 }
Layout.CityZ = { -450, -800, -1150, -1500 }
Layout.CityStreetWidth = 40

-- Road segments { a, b, width, style } ("city" streets are generated from the grid)
Layout.Roads = {
	{ a = v(0, -120), b = v(0, -430), w = 44, style = "avenue" },
	{ a = v(0, 120), b = v(0, 420), w = 44, style = "avenue" },
	{ a = v(-160, 0), b = v(-900, 0), w = 40, style = "street", lamps = false }, -- the service plots light it
	{ a = v(160, 0), b = v(520, 0), w = 40, style = "street" },
	{ a = v(-1800, 450), b = v(0, 450), w = 60, style = "highway" },
	{ a = v(0, 450), b = v(1800, 450), w = 60, style = "highway" },
	{ a = v(-1200, 420), b = v(-1200, 200), w = 40, style = "street" },
	{ a = v(700, 420), b = v(700, 150), w = 40, style = "street" },
	{ a = v(1150, 420), b = v(1150, -276), w = 40, style = "street" },
}

-- Spawn pads in the plaza (cars face south, towards the exit)
Layout.SpawnPads = {}
for i = 0, 9 do
	local x = -135 + i * 30
	table.insert(Layout.SpawnPads, CFrame.new(x, Layout.RoadTop, 82) * CFrame.Angles(0, math.pi, 0))
end

Layout.PlayerSpawn = v(0, 10)
Layout.GarageKiosks = { v(-120, 30), v(120, 30) }
Layout.Showroom = { min = v(-152, -116), max = v(-36, -42) }

-- Mesh for terrain hills: masks are 0 on the flat playfield, 1 in the hills.
Layout.SouthHills = { start = 640, full = 880 }
Layout.NorthHills = { start = -1620, full = -1780 }
Layout.Rim = { width = 140, height = 70 }

-- Car-service plots on both sides of the west street (z = 0). In plot space
-- +Z points at the street and the plot spans x -100..100, z -85..85; north
-- plots use the identity rotation, south plots are turned around.
Layout.ServicePlotSize = Vector2.new(200, 170)
Layout.ServicePlots = {} :: { CFrame }
for _, x in { -310, -530, -750 } do
	table.insert(Layout.ServicePlots, CFrame.new(x, Layout.RoadTop, -115))
	table.insert(Layout.ServicePlots, CFrame.new(x, Layout.RoadTop, 115) * CFrame.Angles(0, math.pi, 0))
end

-- Driving zones with bonus rewards
Layout.Zones = {
	drift = { center = Layout.DriftArena.center, size = Vector3.new(360, 60, 300), multiplier = 2 },
	stunt = { center = Layout.StuntPark.center, size = Vector3.new(600, 400, 600), multiplier = 2 },
}

return Layout
