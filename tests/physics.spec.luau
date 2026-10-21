-- Drives every car in a small rigid-body simulator to check the vehicle physics:
-- the car must settle on its springs, reach a sensible top speed, brake,
-- corner without rolling over, drift with the handbrake and survive jumps.

local world = newWorld()
local env = world.env
local Vector3, CFrame = env.Vector3, env.CFrame
local CarCatalog = world.require(world.shared.CarCatalog)
local CarBuilder = world.require(world.shared.CarBuilder)
local CarPhysics = world.require(world.shared.CarPhysics)

local carsim = loadchunk(readfile("tests/harness/carsim.luau"), "@tests/harness/carsim.luau", getfenv())()
local simulate = carsim.new(world).simulate

local function assertTrue(cond, msg)
	if not cond then
		error(msg, 2)
	end
end

local NONE = { throttle = 0, steer = 0, handbrake = false, nitro = false }
local function input(throttle, steer, handbrake, nitro)
	return { throttle = throttle, steer = steer or 0, handbrake = handbrake or false, nitro = nitro or false }
end

local tests = {}
local function test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

test("every car settles on its suspension", function()
	for _, def in CarCatalog.List do
		local tr = simulate(def, {
			duration = 4,
			drop = 0.8,
			control = function()
				return { throttle = 0, steer = 0, handbrake = false, nitro = false, parked = true }
			end,
		})
		local b = tr.body
		local v = tr.recentVelocity(1).Magnitude
		local w = b.AssemblyAngularVelocity.Magnitude
		assertTrue(v < 0.5, string.format("%s: still moving after settling (%.2f)", def.id, v))
		assertTrue(w < 0.2, string.format("%s: still rotating after settling (%.2f)", def.id, w))
		assertTrue(b.CFrame.UpVector.Y > 0.995, def.id .. ": not level after settling")
		local dy = b.CFrame.Position.Y - (tr.start.Position.Y - 0.8)
		assertTrue(math.abs(dy) < 0.35, string.format("%s: rests %.2f studs off its design height", def.id, dy))
		assertTrue(tr.hullHits == 0, def.id .. ": body scraped the ground while settling")
	end
end)

test("every car accelerates close to its top speed and stays upright", function()
	for _, def in CarCatalog.List do
		local stats = CarCatalog.getEffectiveStats(def, nil)
		local t60
		local tr = simulate(def, {
			duration = 14,
			control = function(t)
				return input(if t > 0.5 then 1 else 0)
			end,
			observe = function(t, sim)
				if not t60 and sim.telemetry.forwardSpeed >= 60 then
					t60 = t
				end
			end,
		})
		local top = tr.body.AssemblyLinearVelocity.Magnitude
		assertTrue(top > stats.maxSpeed * 0.85, string.format("%s: only reached %.0f of %.0f", def.id, top, stats.maxSpeed))
		assertTrue(top < stats.maxSpeed * 1.05, string.format("%s: overshot top speed %.0f > %.0f", def.id, top, stats.maxSpeed))
		assertTrue(tr.minUpY > 0.95, string.format("%s: pitched/rolled too much while accelerating (%.2f)", def.id, tr.minUpY))
		local lateral = math.abs(tr.body.CFrame.Position.X - tr.start.Position.X)
		assertTrue(lateral < 3, string.format("%s: drifted sideways %.1f studs on a straight", def.id, lateral))
		print(string.format("      %-12s top %5.1f/%5.0f  0-60 %s", def.id, top, stats.maxSpeed, if t60 then string.format("%.2fs", t60 - 0.5) else "-"))
	end
end)

test("every car brakes to a stop in a straight line", function()
	for _, def in CarCatalog.List do
		local v0 = math.min(100, def.stats.maxSpeed * 0.8)
		local stopT
		local tr = simulate(def, {
			duration = 5,
			drop = 0,
			initialSpeed = v0,
			control = function(t, tel)
				if t < 0.4 then
					return input(0.3)
				end
				if tel.forwardSpeed < 1 then
					return NONE
				end
				return input(-1)
			end,
			observe = function(t, sim, body)
				local v = body.AssemblyLinearVelocity
				if not stopT and t > 0.5 and Vector3.new(v.X, 0, v.Z).Magnitude < 1 then
					stopT = t
				end
			end,
		})
		assertTrue(stopT ~= nil, def.id .. ": never stopped")
		assertTrue(tr.minUpY > 0.95, def.id .. ": nose-dived too much under braking")
		local lateral = math.abs(tr.body.CFrame.Position.X - tr.start.Position.X)
		assertTrue(lateral < 3, string.format("%s: swerved %.1f studs while braking", def.id, lateral))
	end
end)

test("cornering at speed does not roll cars over", function()
	for _, def in CarCatalog.List do
		local minDot = 1
		local tr = simulate(def, {
			duration = 7,
			drop = 0,
			initialSpeed = math.min(def.stats.maxSpeed * 0.7, 120),
			control = function(t)
				return input(0.8, if t > 0.3 then 1 else 0)
			end,
			observe = function(t, sim, body)
				minDot = math.min(minDot, body.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)))
			end,
		})
		assertTrue(tr.minUpY > 0.6, string.format("%s: rolled over in a turn (up.Y %.2f)", def.id, tr.minUpY))
		assertTrue(minDot < -0.5, def.id .. ": did not turn around")
	end
end)

test("slalom keeps cars stable", function()
	for _, def in CarCatalog.List do
		local tr = simulate(def, {
			duration = 8,
			drop = 0,
			initialSpeed = math.min(def.stats.maxSpeed * 0.6, 100),
			control = function(t)
				return input(0.7, if math.floor(t / 0.9) % 2 == 0 then 1 else -1)
			end,
		})
		assertTrue(tr.minUpY > 0.6, string.format("%s: flipped in a slalom (up.Y %.2f)", def.id, tr.minUpY))
	end
end)

test("handbrake turn starts a drift", function()
	for _, id in { "kitsune", "thunder", "comet", "stinger", "rallyfox" } do
		local def = CarCatalog.get(id)
		local drifted = 0
		local minFwd = math.huge
		local tr = simulate(def, {
			duration = 4,
			drop = 0,
			initialSpeed = 80,
			control = function(t)
				if t < 0.3 then
					return input(0.6)
				end
				return input(0.8, 1, t < 1.2)
			end,
			observe = function(t, sim)
				if sim.telemetry.drifting then
					drifted += 1 / 60
				end
				minFwd = math.min(minFwd, sim.telemetry.forwardSpeed)
			end,
		})
		assertTrue(drifted > 0.4, string.format("%s: drift time only %.2fs", id, drifted))
		assertTrue(minFwd > 0, string.format("%s: spun out backwards (%.1f)", id, minFwd))
		assertTrue(tr.minUpY > 0.6, id .. ": flipped while drifting")
	end
end)

test("cars hold still on an 18 degree slope when parked", function()
	for _, def in CarCatalog.List do
		local tr = simulate(def, {
			duration = 4,
			ground = "slope",
			control = function()
				return { throttle = 0, steer = 0, handbrake = true, nitro = false, parked = true }
			end,
		})
		local v = tr.recentVelocity(1).Magnitude
		assertTrue(v < 0.3, string.format("%s: slides down the slope at %.2f", def.id, v))
	end
end)

test("landing a jump does not explode or flip", function()
	for _, def in CarCatalog.List do
		local tr = simulate(def, {
			duration = 4,
			drop = 18,
			initialVelocity = Vector3.new(0, 10, -90),
			control = function()
				return input(0.5)
			end,
		})
		assertTrue(tr.minUpY > 0.7, string.format("%s: tumbled after a jump (%.2f)", def.id, tr.minUpY))
		assertTrue(tr.body.AssemblyAngularVelocity.Magnitude < 3, def.id .. ": still spinning after landing")
	end
end)

test("nitro raises speed and drains the tank", function()
	local def = CarCatalog.get("comet")
	local tr = simulate(def, {
		duration = 12,
		control = function(t)
			return input(1, 0, false, t > 6)
		end,
	})
	local top = tr.body.AssemblyLinearVelocity.Magnitude
	assertTrue(top > def.stats.maxSpeed * 1.02, string.format("nitro top speed %.1f not above %.1f", top, def.stats.maxSpeed))
	assertTrue(tr.sim.nitro < 0.5, "nitro tank did not drain")
end)

test("reverse works", function()
	local def = CarCatalog.get("cruiser")
	local tr = simulate(def, {
		duration = 5,
		control = function()
			return input(-1)
		end,
	})
	local fwd = tr.body.AssemblyLinearVelocity:Dot(tr.body.CFrame.LookVector)
	assertTrue(fwd < -20, string.format("reverse speed only %.1f", fwd))
end)

test("handling does not depend on the frame rate", function()
	local def = CarCatalog.get("comet")
	local results = {}
	for _, fps in { 30, 60, 144 } do
		local yaw = 0
		local tr = simulate(def, {
			duration = 6,
			drop = 0,
			frame = 1 / fps,
			initialSpeed = 90,
			control = function(t)
				return input(0.6, if t > 1 then 0.6 else 0)
			end,
			observe = function(t, sim, body)
				if t > 4 then
					yaw = body.AssemblyAngularVelocity.Y
				end
			end,
		})
		results[fps] = { speed = tr.body.AssemblyLinearVelocity.Magnitude, yaw = yaw }
		print(string.format("      %3d fps: speed %.1f yaw %.3f", fps, results[fps].speed, yaw))
	end
	local ref = results[60]
	for fps, r in results do
		assertTrue(math.abs(r.speed - ref.speed) / ref.speed < 0.1, string.format("%d fps speed %.1f vs %.1f", fps, r.speed, ref.speed))
		assertTrue(math.abs(r.yaw - ref.yaw) / math.abs(ref.yaw) < 0.15, string.format("%d fps yaw %.2f vs %.2f", fps, r.yaw, ref.yaw))
	end
end)

return tests
