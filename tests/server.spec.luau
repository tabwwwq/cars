-- Server systems in the mock environment: world generation, track data,
-- save reconciliation and the shop/economy rules.

local world = newWorld()
local env = world.env
local Vector3, Instance = env.Vector3, env.Instance
local game = world.game

local function assertTrue(cond, msg)
	if not cond then
		error(msg, 2)
	end
end

local tests = {}
local function test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

local WorldModules = world.server.World
local Systems = world.server.Systems

local Net = world.require(world.shared.Net)
Net.init()

test("terrain height function is smooth and flat on the playfield", function()
	local TerrainGen = world.require(WorldModules.TerrainGen)
	local Layout = world.require(world.shared.WorldLayout)
	-- flat where we drive
	for _, p in { Vector3.new(0, 0, 0), Vector3.new(1300, 0, -700), Vector3.new(-1200, 0, -100), Vector3.new(0, 0, 450), Vector3.new(0, 0, -1000) } do
		local h = TerrainGen.rawHeight(p.X, p.Z)
		assertTrue(h == 0, string.format("terrain not flat at %s (%.2f)", tostring(p), h))
	end
	-- hills exist in the south and slopes are drivable
	local maxH, maxSlope = 0, 0
	for x = -1800, 1800, 40 do
		for z = Layout.SouthHills.full, 1700, 40 do
			local h = TerrainGen.rawHeight(x, z)
			local h2 = TerrainGen.rawHeight(x + 4, z)
			maxH = math.max(maxH, h)
			maxSlope = math.max(maxSlope, math.abs(h2 - h) / 4)
		end
	end
	assertTrue(maxH > 20, "southern hills are missing")
	assertTrue(maxSlope < 1.2, string.format("hills too steep (%.2f)", maxSlope))
	-- heightmap dump for the map renderer
	local rows = {}
	for z = -Layout.Half, Layout.Half - 1, 16 do
		local row = {}
		for x = -Layout.Half, Layout.Half - 1, 16 do
			local h, m = TerrainGen.rawHeight(x, z)
			table.insert(row, string.format("%.1f:%s", h, string.sub(m.Name, 1, 2)))
		end
		table.insert(rows, '"' .. table.concat(row, " ") .. '"')
	end
	writefile("tests/out/heightmap.json", "[" .. table.concat(rows, ",\n") .. "]")
end)

local builtRoot
local builtTracks
test("the whole world builds without errors", function()
	local Build = world.require(WorldModules.Build)
	local Roads = world.require(WorldModules.Roads)
	local Plaza = world.require(WorldModules.Plaza)
	local City = world.require(WorldModules.City)
	local Stunts = world.require(WorldModules.Stunts)
	local TrackBuilder = world.require(WorldModules.TrackBuilder)
	local Decor = world.require(WorldModules.Decor)
	local TerrainGen = world.require(WorldModules.TerrainGen)
	local Tracks = world.require(world.shared.Tracks)
	local Spline = world.require(world.shared.Util.Spline)
	local workspace = env.workspace

	local root = Instance.new("Folder")
	root.Name = "CarsWorld"
	root.Parent = workspace
	local trailDef = Tracks.get("trail")
	local trail = { samples = Spline.sample(trailDef.points, false, 6), width = trailDef.width }
	local heights = TerrainGen.trailHeights(trail)
	assertTrue(#heights == #trail.samples, "trail heights missing")
	Roads.build(root)
	Plaza.build(root)
	local trees = City.build(root)
	Stunts.buildPark(root)
	Stunts.buildDrift(root)
	local data = TrackBuilder.build(root, heights, trail.samples, true)
	local paths = {}
	for _, t in Tracks.List do
		table.insert(paths, { points = t.points, clearance = t.width / 2 + 14 })
	end
	Decor.build(root, trees, paths)
	builtRoot = root
	builtTracks = data

	local parts = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			local s = d.Size
			assertTrue(s.X <= 2048 and s.Y <= 2048 and s.Z <= 2048, "part too large: " .. d:GetFullName())
			assertTrue(s.X > 0 and s.Y > 0 and s.Z > 0, "zero size part: " .. d:GetFullName())
			local p = d.CFrame.Position
			assertTrue(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "NaN position: " .. d:GetFullName())
		end
	end
	print(string.format("      world parts: %d", parts))
	assertTrue(parts < 9000, "world has too many parts: " .. parts)

	-- track data sanity
	for _, t in Tracks.List do
		local td = data[t.id]
		assertTrue(td ~= nil, "missing track data " .. t.id)
		assertTrue(#td.checkpoints >= 3, t.id .. ": too few checkpoints")
		assertTrue(td.medals.gold < td.medals.silver and td.medals.silver < td.medals.bronze, t.id .. ": medal order")
		print(string.format("      %-8s length %5.0f  checkpoints %2d  gold %s", t.id, td.length, #td.checkpoints, tostring(math.floor(td.medals.gold))))
		-- consecutive checkpoints must be reachable and ordered along the route
		for i = 2, #td.checkpoints do
			local a, b = td.checkpoints[i - 1].cf.Position, td.checkpoints[i].cf.Position
			assertTrue((a - b).Magnitude > 30, t.id .. ": checkpoints too close")
		end
	end

	-- dump top-down geometry for the map renderer
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.9 then
			local s = d.Size
			if s.X * s.Z > 12 then
				local comps = { d.CFrame:GetComponents() }
				for i, v in comps do
					comps[i] = string.format("%.2f", v)
				end
				local c = d.Color
				table.insert(out, string.format('{"size":[%.1f,%.1f,%.1f],"cf":[%s],"c":[%.2f,%.2f,%.2f],"w":%s}', s.X, s.Y, s.Z, table.concat(comps, ","), c.R, c.G, c.B, tostring(d.ClassName == "WedgePart")))
			end
		end
	end
	local cps = {}
	for id, td in data do
		for i, cp in td.checkpoints do
			local p = cp.cf.Position
			table.insert(cps, string.format('{"t":"%s","i":%d,"x":%.1f,"z":%.1f}', id, i, p.X, p.Z))
		end
	end
	writefile("tests/out/map.json", '{"parts":[' .. table.concat(out, ",") .. '],"checkpoints":[' .. table.concat(cps, ",") .. "]}")
end)

test("nothing solid stands on the roads or race tracks", function()
	assertTrue(builtRoot ~= nil, "world not built")
	local Layout = world.require(world.shared.WorldLayout)
	local Spline = world.require(world.shared.Util.Spline)
	local Tracks = world.require(world.shared.Tracks)

	-- drivable rectangles: { center (x,z), dir (unit x,z), halfLen, halfWidth, name }
	local lanes = {}
	local function lane(a, b, w, name)
		local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local len = d.Magnitude
		if len < 1 then
			return
		end
		table.insert(lanes, { c = (a + b) / 2, u = d / len, hl = len / 2, hw = w / 2 - 1.5, name = name })
	end
	for _, r in Layout.Roads do
		lane(r.a, r.b, r.w, "road")
	end
	for _, x in Layout.CityX do
		lane(Vector3.new(x, 0, -450), Vector3.new(x, 0, -1500), if x == 0 then 44 else 40, "street x=" .. x)
	end
	for _, z in Layout.CityZ do
		lane(Vector3.new(-700, 0, z), Vector3.new(700, 0, z), 40, "street z=" .. z)
	end
	local trail = Tracks.get("trail")
	local trailSamples = Spline.sample(trail.points, false, 12)
	for i = 1, #trailSamples - 1 do
		lane(trailSamples[i].pos, trailSamples[i + 1].pos, trail.width, "trail")
	end
	local circuit = Tracks.get("circuit")
	local samples = Spline.sample(circuit.points, true, 14)
	for i = 1, #samples do
		local a, b = samples[i].pos, samples[(i % #samples) + 1].pos
		lane(a, b, circuit.width, "circuit")
	end

	local SURFACE = {
		Road = true,
		Junction = true,
		Marking = true,
		Track = true,
		Strip = true,
		Sidewalk = true,
		PlazaFloor = true,
		StartLine = true,
		ParkFloor = true,
		ArenaFloor = true,
		Parking = true,
	}
	local function overlaps(part, l)
		-- separating axis test of the part's footprint against the lane rectangle
		local cf, size = part.CFrame, part.Size
		local px, pz = cf.Position.X, cf.Position.Z
		local rx = cf.RightVector
		local lz = cf.LookVector
		local ax1 = Vector3.new(rx.X, 0, rx.Z)
		local ax2 = Vector3.new(lz.X, 0, lz.Z)
		local h1, h2 = size.X / 2, size.Z / 2
		local u = l.u
		local v = Vector3.new(-u.Z, 0, u.X)
		local d = Vector3.new(px - l.c.X, 0, pz - l.c.Z)
		for _, axis in { u, v, ax1.Magnitude > 1e-3 and ax1.Unit or u, ax2.Magnitude > 1e-3 and ax2.Unit or v } do
			local rp = math.abs(ax1:Dot(axis)) * h1 + math.abs(ax2:Dot(axis)) * h2
			local rl = math.abs(u:Dot(axis)) * l.hl + math.abs(v:Dot(axis)) * l.hw
			if math.abs(d:Dot(axis)) > rp + rl then
				return false
			end
		end
		return true
	end
	local hits = {}
	for _, part in builtRoot:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide and part.Transparency < 1 and not SURFACE[part.Name] then
			local top = part.CFrame.Position.Y + part.Size.Y / 2
			local bottom = part.CFrame.Position.Y - part.Size.Y / 2
			if top > 0.9 and bottom < 12 then
				local p = part.CFrame.Position
				for _, l in lanes do
					local reach = l.hl + l.hw + part.Size.Magnitude
					if (Vector3.new(p.X, 0, p.Z) - l.c).Magnitude < reach and overlaps(part, l) then
						table.insert(hits, string.format("%s at (%.0f, %.0f) blocks %s", part:GetFullName(), p.X, p.Z, l.name))
						break
					end
				end
			end
		end
	end
	if #hits > 0 then
		error(#hits .. " obstacles on roads:\n        " .. table.concat(hits, "\n        ", 1, math.min(#hits, 25)))
	end
end)

test("spawn pads do not overlap the plaza furniture", function()
	local Layout = world.require(world.shared.WorldLayout)
	for i, a in Layout.SpawnPads do
		for j, b in Layout.SpawnPads do
			if i ~= j then
				assertTrue((a.Position - b.Position).Magnitude >= 30, "spawn pads too close")
			end
		end
		local p = a.Position
		assertTrue(math.abs(p.X) < Layout.Plaza.size.X / 2 - 10 and math.abs(p.Z) < Layout.Plaza.size.Y / 2, "pad outside plaza")
	end
end)

test("save data is reconciled and migrated safely", function()
	local PlayerData = world.require(Systems.PlayerData)
	local Config = world.require(world.shared.Config)
	local fresh = PlayerData.defaultProfile()
	assertTrue(fresh.owned[Config.StarterCarId], "starter car not owned")
	assertTrue(fresh.cash == Config.StartingCash, "wrong starting cash")
	local junk = {
		version = 1,
		cash = "999",
		owned = { comet = true, nope = true, [5] = true },
		cars = { comet = { paint = 999, accent = 3, engine = 99, finish = "Lava" }, nope = { paint = 1 } },
		selected = "zephyr",
		bestTimes = { circuit = 61.5, bad = {} },
		stats = { distance = -5, races = "x" },
		daily = { last = "abc", streak = 3 },
	}
	local r = PlayerData.reconcile(junk)
	assertTrue(r.cash == 999, "cash string not converted")
	assertTrue(r.owned.comet and r.owned[Config.StarterCarId], "owned cars lost")
	assertTrue(r.cars.comet.paint == world.require(world.shared.CarCatalog).get("comet").colors.paint, "invalid paint not reset")
	assertTrue(r.cars.comet.accent == 3, "valid accent lost")
	assertTrue(r.cars.comet.engine == Config.Upgrades.Engine.MaxLevel, "engine level not clamped")
	assertTrue(r.cars.comet.finish == "Gloss", "invalid finish kept")
	assertTrue(r.cars.nope == nil, "unknown car kept in customization")
	assertTrue(r.selected ~= "zephyr", "selected an unowned car")
	assertTrue(r.bestTimes.circuit == 61.5 and r.bestTimes.bad == nil, "best times not filtered")
	assertTrue(r.stats.distance == 0, "negative stat kept")
	assertTrue(r.daily.streak == 3 and r.daily.last == 0, "daily not sanitized")
end)

-- A fake player wired through the real PlayerData lifecycle
local function makePlayer(userId)
	local p = Instance.new("Player")
	p.Name = "Tester" .. userId
	p.DisplayName = "Tester" .. userId
	p.UserId = userId
	p.Parent = game:GetService("Players")
	return p
end

test("shop: buying, upgrading, painting and daily rewards", function()
	local PlayerData = world.require(Systems.PlayerData)
	local Shop = world.require(Systems.Shop)
	local Config = world.require(world.shared.Config)
	local CarCatalog = world.require(world.shared.CarCatalog)
	PlayerData.init()
	PlayerData.start()
	local player = makePlayer(1001)
	game:GetService("Players").PlayerAdded:Fire(player)
	local data = PlayerData.get(player)
	assertTrue(data ~= nil, "profile did not load")

	-- can't afford a hypercar
	local r = Shop.buyCar(player, "quasar")
	assertTrue(not r.ok and r.message == "NotEnoughCash", "bought a car without money")
	-- buy an affordable car
	local cash0 = data.cash
	r = Shop.buyCar(player, "dart")
	assertTrue(r.ok, "could not buy dart: " .. tostring(r.message))
	assertTrue(data.cash == cash0 - CarCatalog.get("dart").price, "price not charged")
	assertTrue(Shop.buyCar(player, "dart").message == "AlreadyOwned", "bought twice")
	-- garbage input
	assertTrue(not Shop.buyCar(player, nil).ok, "nil car accepted")
	assertTrue(not Shop.buyCar(player, { id = "dart" }).ok, "table car accepted")

	-- upgrades
	PlayerData.addCash(player, 1000000)
	for lvl = 1, 5 do
		r = Shop.buyUpgrade(player, "dart", "Engine")
		assertTrue(r.ok, "upgrade failed at " .. lvl)
	end
	assertTrue(Shop.buyUpgrade(player, "dart", "Engine").message == "MaxLevel", "upgraded past max")
	assertTrue(not Shop.buyUpgrade(player, "dart", "Turbo").ok, "unknown upgrade accepted")
	assertTrue(not Shop.buyUpgrade(player, "comet", "Engine").ok, "upgraded an unowned car")

	-- paint
	assertTrue(Shop.setPaint(player, "dart", "paint", 5).ok, "paint failed")
	assertTrue(data.cars.dart.paint == 5, "paint not stored")
	assertTrue(not Shop.setPaint(player, "dart", "paint", 0).ok, "invalid color accepted")
	assertTrue(not Shop.setPaint(player, "dart", "paint", 2.5).ok, "fractional color accepted")
	local before = data.cash
	assertTrue(Shop.setPaint(player, "dart", "glow", 3).ok, "glow failed")
	assertTrue(before - data.cash == Config.Customization.UnderglowPrice, "glow price wrong")
	assertTrue(Shop.setPaint(player, "dart", "glow", 0).ok and data.cars.dart.glow == 0, "glow off failed")
	before = data.cash
	assertTrue(Shop.setPaint(player, "dart", "finish", "Chrome").ok, "finish failed")
	assertTrue(before - data.cash == Config.Customization.FinishPrices.Chrome, "finish price wrong")
	before = data.cash
	assertTrue(Shop.setPaint(player, "pebble", "finish", "Chrome").ok, "finish reuse failed")
	assertTrue(before == data.cash, "unlocked finish charged again")
	assertTrue(not Shop.setPaint(player, "dart", "finish", "Gold").ok, "unknown finish accepted")

	-- daily
	r = Shop.claimDaily(player)
	assertTrue(r.ok, "daily failed")
	r = Shop.claimDaily(player)
	assertTrue(not r.ok and r.message == "DailyNotReady", "daily claimed twice")
	data.daily.last -= 86400
	r = Shop.claimDaily(player)
	assertTrue(r.ok and data.daily.streak == 2, "streak did not grow")
end)

test("vehicles: spawning builds a car on a pad with stats", function()
	local Vehicles = world.require(Systems.Vehicles)
	local PlayerData = world.require(Systems.PlayerData)
	Vehicles.init()
	local player = makePlayer(1002)
	game:GetService("Players").PlayerAdded:Fire(player)
	assertTrue(PlayerData.get(player) ~= nil, "profile did not load")
	local r = Vehicles.spawn(player, "comet")
	assertTrue(not r.ok and r.message == "NotOwned", "spawned an unowned car")
	r = Vehicles.spawn(player, "pebble")
	assertTrue(r.ok, "spawn failed: " .. tostring(r.message))
	local car = Vehicles.getCar(player)
	assertTrue(car ~= nil and car:GetAttribute("OwnerUserId") == 1002, "car not registered")
	assertTrue(car:GetAttribute("MaxSpeed") ~= nil, "stats not written")
	assertTrue(car.PrimaryPart.Position.Y > 0.5, "car spawned in the ground")
	r = Vehicles.spawn(player, "pebble")
	assertTrue(not r.ok and r.message == "SpawnCooldown", "no spawn cooldown")
	Vehicles.despawn(player)
	assertTrue(Vehicles.getCar(player) == nil, "despawn failed")
end)

return tests
