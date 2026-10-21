-- Builds every car in the catalog and checks the generated models are sane.

local world = newWorld()
local CarCatalog = world.require(world.shared.CarCatalog)
local CarBuilder = world.require(world.shared.CarBuilder)
local Paints = world.require(world.shared.Paints)
local Config = world.require(world.shared.Config)

local function assertTrue(cond, msg)
	if not cond then
		error(msg, 2)
	end
end

local tests = {}
local function test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

test("catalog has unique ids, valid colors and classes", function()
	local seen = {}
	local classIds = {}
	for _, c in CarCatalog.Classes do
		classIds[c.id] = true
	end
	assertTrue(#CarCatalog.List >= 25, "expected at least 25 cars, got " .. #CarCatalog.List)
	for _, def in CarCatalog.List do
		assertTrue(not seen[def.id], "duplicate id " .. def.id)
		seen[def.id] = true
		assertTrue(classIds[def.class], def.id .. ": unknown class " .. def.class)
		assertTrue(Paints.isValidIndex(def.colors.paint), def.id .. ": bad paint")
		assertTrue(Paints.isValidIndex(def.colors.accent), def.id .. ": bad accent")
		assertTrue(Paints.isValidIndex(def.colors.rim), def.id .. ": bad rim")
		assertTrue(def.price >= 0, def.id .. ": negative price")
		assertTrue(def.description.ru ~= "" and def.description.en ~= "", def.id .. ": missing description")
		local s = def.stats
		assertTrue(s.maxSpeed > 40 and s.maxSpeed < 400, def.id .. ": maxSpeed out of range")
		assertTrue(s.suspension.rest > 0.3, def.id .. ": suspension too short")
	end
	assertTrue(CarCatalog.get(Config.StarterCarId) ~= nil, "starter car missing")
	assertTrue(CarCatalog.get(Config.StarterCarId).price == 0, "starter car must be free")
end)

test("every car builds (preview and drivable) with wheels and a driver seat", function()
	for _, def in CarCatalog.List do
		for _, mode in { { preview = true }, { ownerName = "Tester" } } do
			local ok, modelOrErr = pcall(CarBuilder.build, def, mode)
			assertTrue(ok, def.id .. " failed to build: " .. tostring(modelOrErr))
			local model = modelOrErr
			assertTrue(model.PrimaryPart ~= nil and model.PrimaryPart.Name == "Chassis", def.id .. ": no chassis")
			local wheels, seats, driver, parts = 0, 0, 0, 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					local s = d.Size
					assertTrue(s.X > 0 and s.Y > 0 and s.Z > 0, def.id .. ": zero-size part " .. d.Name)
					assertTrue(s.X == s.X and s.Y == s.Y and s.Z == s.Z, def.id .. ": NaN size on " .. d.Name)
					local p = d.CFrame.Position
					assertTrue(p.X == p.X and p.Y == p.Y and p.Z == p.Z, def.id .. ": NaN position on " .. d.Name)
					if d:GetAttribute("Wheel") then
						wheels += 1
					end
				end
				if d.ClassName == "VehicleSeat" then
					driver += 1
				elseif d.ClassName == "Seat" then
					seats += 1
				end
			end
			assertTrue(wheels >= 4, def.id .. ": expected >= 4 wheels, got " .. wheels)
			assertTrue(parts < 400, def.id .. ": too many parts (" .. parts .. ")")
			if not mode.preview then
				assertTrue(driver == 1, def.id .. ": expected exactly one VehicleSeat")
				assertTrue(seats <= (def.maxSeats or 4), def.id .. ": too many seats")
			end
		end
	end
end)

test("drivers fit under the roof", function()
	for _, def in CarCatalog.List do
		local geo = CarBuilder.measure(def)
		if geo.cabin and not (def.body.cabin and def.body.cabin.open) then
			for _, s in CarBuilder.getSeats(def) do
				local head = s.pos.Y + 3.9
				assertTrue(head <= geo.cabin.yR + 0.06, string.format("%s: head %.2f above roof %.2f", def.id, head, geo.cabin.yR))
			end
		end
	end
end)

test("wheels are inside the body length and touch the ground", function()
	for _, def in CarCatalog.List do
		for _, a in CarCatalog.getAxles(def) do
			assertTrue(math.abs(a.z) <= def.body.length / 2, def.id .. ": axle outside the body")
			assertTrue(a.radius > 0.5, def.id .. ": wheel radius too small")
		end
	end
end)

test("effective stats grow with upgrades", function()
	for _, def in CarCatalog.List do
		local base = CarCatalog.getEffectiveStats(def, nil)
		local save = CarCatalog.defaultSave(def)
		save.engine, save.tires, save.nitro = 5, 5, 5
		local up = CarCatalog.getEffectiveStats(def, save)
		assertTrue(up.maxSpeed > base.maxSpeed and up.accel > base.accel, def.id .. ": engine upgrade does nothing")
		assertTrue(up.grip > base.grip, def.id .. ": tire upgrade does nothing")
		assertTrue(up.nitroPower > base.nitroPower, def.id .. ": nitro upgrade does nothing")
		for _, kind in { "Engine", "Tires", "Nitro" } do
			for lvl = 1, 5 do
				local price = CarCatalog.getUpgradePrice(def, kind, lvl)
				assertTrue(price and price > 0, def.id .. ": missing price " .. kind .. lvl)
			end
			assertTrue(CarCatalog.getUpgradePrice(def, kind, 6) == nil, "level 6 should not exist")
		end
	end
end)

test("dump geometry for the renderer", function()
	local out = {}
	for _, def in CarCatalog.List do
		local model = CarBuilder.build(def, { preview = true })
		local parts = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.99 then
				local cf = d.CFrame
				local c = d.Color
				local shape = "Block"
				if d.ClassName == "WedgePart" then
					shape = "Wedge"
				elseif d.Shape then
					shape = d.Shape.Name
				end
				local comps = { cf:GetComponents() }
				for i, v in comps do
					comps[i] = string.format("%.4f", v)
				end
				table.insert(
					parts,
					string.format(
						'{"s":"%s","size":[%.3f,%.3f,%.3f],"cf":[%s],"c":[%.3f,%.3f,%.3f],"t":%.2f}',
						shape,
						d.Size.X,
						d.Size.Y,
						d.Size.Z,
						table.concat(comps, ","),
						c.R,
						c.G,
						c.B,
						d.Transparency
					)
				)
			end
		end
		table.insert(out, string.format('{"id":"%s","name":"%s","parts":[%s]}', def.id, def.name, table.concat(parts, ",")))
	end
	writefile("tests/out/cars.json", "[" .. table.concat(out, ",\n") .. "]")
end)

return tests
