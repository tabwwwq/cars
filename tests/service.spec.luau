-- Car-service mode: config sanity, every service vehicle and person builds,
-- order generation and the full server loop (customers, orders, hands-on
-- steps with anti-cheat timing, workers, upgrades, saves).

local world = newWorld()
local ServiceConfig = world.require(world.shared.ServiceConfig)
local ServiceModels = world.require(world.shared.ServiceModels)
local CarCatalog = world.require(world.shared.CarCatalog)
local Paints = world.require(world.shared.Paints)
local Strings = world.require(world.shared.Strings)

local function assertTrue(cond, msg)
	if not cond then
		error(msg, 2)
	end
end

local tests = {}
local function test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

local function dumpModel(model)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local shape = "Block"
			if d.ClassName == "WedgePart" then
				shape = "Wedge"
			elseif d.Shape then
				shape = d.Shape.Name
			end
			local comps = { d.CFrame:GetComponents() }
			for i, v in comps do
				comps[i] = string.format("%.4f", v)
			end
			local c = d.Color
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
	return table.concat(parts, ",")
end

test("config: tiers, services, steps and upgrades are consistent", function()
	local lastLevel = 0
	for _, tier in ServiceConfig.Tiers do
		assertTrue(tier.level >= lastLevel, tier.id .. ": tiers must be sorted by level")
		lastLevel = tier.level
		assertTrue(ServiceConfig.Sizes[tier.size] ~= nil, tier.id .. ": unknown size")
		local pool = tier.models or tier.cars
		assertTrue(pool and #pool > 0, tier.id .. ": no vehicles")
		for _, id in pool do
			if tier.models then
				assertTrue(ServiceModels.get(id) ~= nil, tier.id .. ": unknown model " .. id)
			else
				assertTrue(CarCatalog.get(id) ~= nil, tier.id .. ": unknown car " .. id)
			end
		end
		assertTrue(tier.name.ru ~= "" and tier.name.en ~= "", tier.id .. ": missing name")
	end
	for _, s in ServiceConfig.Services do
		for _, step in s.steps do
			assertTrue(ServiceConfig.Steps[step] ~= nil, s.id .. ": unknown step " .. step)
			assertTrue(ServiceConfig.serviceOfStep(step) == s.id, "step owner mismatch " .. step)
		end
	end
	for _, u in ServiceConfig.Upgrades do
		local last = 0
		for _, l in u.levels do
			assertTrue(l.price > last, u.id .. ": prices must grow")
			last = l.price
		end
	end
	assertTrue(ServiceConfig.xpToNext(1) > 0 and ServiceConfig.xpToNext(20) > ServiceConfig.xpToNext(10), "xp curve")
	local steps = ServiceConfig.stepsFor({ "wash", "repair" })
	assertTrue(steps[1] == "wrench" and steps[#steps] == "dry", "repair before wash")
end)

test("every text key used by the service mode exists in both languages", function()
	local keys = {}
	for _, file in { "src/client/Controllers/Service.luau", "src/client/Controllers/Workshop.luau", "src/server/Systems/Service.luau", "src/server/World/ServicePlots.luau" } do
		local ok, src = pcall(readfile, file)
		if ok and src then
			for key in string.gmatch(src, 'Strings%.get%("([%w_]+)"') do
				keys[key] = true
			end
			for key in string.gmatch(src, 'notify%(player, "([%w_]+)"') do
				keys[key] = true
			end
			for key in string.gmatch(src, 'message = "([%w_]+)"') do
				keys[key] = true
			end
			for _, pattern in { 'setHint%("([%w_]+)"', 'notifyKey%("([%w_]+)"', '"(ServiceHint[%w_]+)"', 'prompt%([%w_]+, "([%w_]+)"', 'locKey = "([%w_]+)"' } do
				for key in string.gmatch(src, pattern) do
					keys[key] = true
				end
			end
		end
	end
	for _, prefix in { "Step_", "StepHint_", "Service_", "Upgrade_", "UpgradeDesc_" } do
		local list = if prefix == "Step_" or prefix == "StepHint_"
			then ServiceConfig.Steps
			elseif prefix == "Service_" then ServiceConfig.Services
			else ServiceConfig.Upgrades
		for k, v in list do
			keys[prefix .. (if typeof(k) == "string" then k else v.id)] = true
		end
	end
	for _, state in { "idle", "walking", "working", "returning" } do
		keys["ServiceWorker_" .. state] = true
	end
	for _, key in { "ServiceSignOwner", "ServiceSignFree", "RewardService", "RewardServiceWorker", "ServiceHowTouch" } do
		keys[key] = true
	end
	local missing = {}
	for key in keys do
		if string.sub(key, -1) == "_" then
			continue -- prefix of a key built at runtime (checked above)
		end
		for _, lang in { "ru", "en" } do
			if Strings.Tables[lang][key] == nil then
				table.insert(missing, lang .. ":" .. key)
			end
		end
	end
	table.sort(missing)
	assertTrue(#missing == 0, "missing strings: " .. table.concat(missing, ", "))
end)

test("every service vehicle builds with wheels, paint and a sane size", function()
	assertTrue(#ServiceModels.List >= 15, "expected at least 15 service models")
	local out = {}
	for _, def in ServiceModels.List do
		local model = ServiceModels.build(def.id)
		assertTrue(model ~= nil, def.id .. ": build failed")
		assertTrue(model.PrimaryPart and model.PrimaryPart.Name == "Root", def.id .. ": no root")
		local wheels, paint, count = 0, 0, 0
		local minV, maxV
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= model.PrimaryPart then
				count += 1
				local pos = d.Position
				assertTrue(pos.X == pos.X and pos.Y == pos.Y and pos.Z == pos.Z, def.id .. ": NaN position")
				assertTrue(d.Size.X > 0 and d.Size.Y > 0 and d.Size.Z > 0, def.id .. ": bad size")
				minV = if minV then minV:Min(pos - d.Size / 2) else pos - d.Size / 2
				maxV = if maxV then maxV:Max(pos + d.Size / 2) else pos + d.Size / 2
				if d:GetAttribute("Wheel") then
					wheels += 1
					assertTrue((d:GetAttribute("Radius") or 0) > 0.2, def.id .. ": wheel radius")
				end
				if d:GetAttribute("Role") == "Paint" then
					paint += 1
				end
				assertTrue(d:GetAttribute("Role") ~= nil, def.id .. ": part without role")
			end
		end
		assertTrue(wheels >= 2, def.id .. ": expected wheels, got " .. wheels)
		assertTrue(paint >= 3, def.id .. ": expected paintable parts")
		assertTrue(count >= 18, def.id .. ": too few parts (" .. count .. ")")
		local size = maxV - minV
		assertTrue(size.Z > 2.5 and size.Z < 9, def.id .. ": odd length " .. size.Z)
		assertTrue(size.Y > 2 and size.Y < 8, def.id .. ": odd height " .. size.Y)
		assertTrue(minV.Y > -0.3, def.id .. ": below the ground " .. minV.Y)
		table.insert(out, string.format('{"id":"%s","name":"%s","parts":[%s]}', def.id, def.name.en, dumpModel(model)))
	end
	local person = ServiceModels.person("Worker", { cap = world.env.Color3.fromRGB(255, 128, 32) })
	local joints = 0
	for _, d in person:GetDescendants() do
		if d:IsA("Motor6D") then
			joints += 1
		end
	end
	assertTrue(joints == 4, "person should have 4 limb joints")
	table.insert(out, string.format('{"id":"worker","name":"Worker","parts":[%s]}', dumpModel(person)))
	ServiceModels.weldToRoot(person)
	for _, d in person:GetDescendants() do
		if d:IsA("BasePart") and d ~= person.PrimaryPart then
			assertTrue(not d.Anchored, "welded part still anchored: " .. d.Name)
		end
	end
	writefile("tests/out/service.json", "[" .. table.concat(out, ",\n") .. "]")
end)

test("orders follow the unlocks of the level", function()
	local rng = world.env.Random.new(7)
	for level = 1, ServiceConfig.MaxLevel, 3 do
		for _ = 1, 40 do
			local o = ServiceConfig.makeOrder(level, rng, 0)
			local tier = ServiceConfig.getTier(o.tier)
			assertTrue(tier and tier.level <= level, "tier above level")
			assertTrue(#o.services >= 1, "no services")
			for _, s in o.services do
				assertTrue(ServiceConfig.getService(s).level <= level, "service above level " .. s)
			end
			assertTrue(o.reward > 0 and o.xp > 0, "reward/xp")
			assertTrue(Paints.isValidIndex(o.paint), "paint index")
			if table.find(o.services, "paint") then
				assertTrue(Paints.isValidIndex(o.target) and o.target ~= o.paint, "paint target")
			end
		end
	end
	local first = ServiceConfig.makeOrder(1, world.env.Random.new(1), 0)
	assertTrue(first.tier == "bikes" and first.services[1] == "wash", "level 1 is only bike washes")
end)

--------------------------------------------------------------------------------
-- Server loop
--------------------------------------------------------------------------------

local env = world.env
local Instance, Vector3, CFrame = env.Instance, env.Vector3, env.CFrame
local game = world.game
local Systems = world.server.Systems
local Net = world.require(world.shared.Net)
Net.init()

local PlayerData = world.require(Systems.PlayerData)
local Service = world.require(Systems.Service)
local ServicePlots = world.require(world.server.World.ServicePlots)
PlayerData.init()
PlayerData.start()
local root = Instance.new("Folder")
root.Name = "CarsWorld"
root.Parent = env.workspace
Service.setupPlots(ServicePlots.buildAll(root))
local clock = 1000
Service.now = function()
	return clock
end

local function makePlayer(userId)
	local p = Instance.new("Player")
	p.Name = "Tester" .. userId
	p.DisplayName = "Tester" .. userId
	p.UserId = userId
	p.Parent = game:GetService("Players")
	game:GetService("Players").PlayerAdded:Fire(p)
	local char = Instance.new("Model")
	char.Name = p.Name
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Parent = char
	char.PrimaryPart = hrp
	char.Parent = env.workspace
	p.Character = char
	return p
end

local function advance(seconds)
	local stepSize = 0.5
	local t = 0
	while t < seconds do
		t += stepSize
		clock += stepSize
		Service.update(clock)
	end
end

local function onlyJob(plot, state)
	for _, job in plot.jobs do
		if not state or job.state == state then
			return job
		end
	end
	return nil
end

test("profiles get a service section and old saves migrate to it", function()
	local fresh = PlayerData.defaultProfile()
	assertTrue(fresh.version == 3 and fresh.service.level == 1, "default service profile")
	for _, u in ServiceConfig.Upgrades do
		assertTrue(fresh.service.upgrades[u.id] == 0, "upgrade default " .. u.id)
	end
	local r = PlayerData.reconcile({
		version = 3,
		cash = 10,
		service = { level = 99, xp = -5, orders = 3, upgrades = { bays = 9, tools = 2, junk = 4 } },
	})
	assertTrue(r.service.level == ServiceConfig.MaxLevel, "level not clamped")
	assertTrue(r.service.xp == 0 and r.service.orders == 3, "xp/orders not sanitized")
	assertTrue(r.service.upgrades.bays == 3 and r.service.upgrades.tools == 2, "upgrades not clamped")
	assertTrue(r.service.upgrades.junk == nil, "unknown upgrade kept")
	local old = PlayerData.reconcile({ version = 2, cash = 50 })
	assertTrue(old.service and old.service.level == 1, "v2 save without service")
end)

test("a customer arrives, you take the order, do every step by hand and get paid", function()
	local player = makePlayer(3001)
	local data = PlayerData.get(player)
	assertTrue(data ~= nil, "profile did not load")
	local plot = Service.claim(player)
	assertTrue(plot ~= nil, "no plot")
	assertTrue(Service.getPlot(player) == plot, "plot lookup")
	assertTrue(player:GetAttribute("ServicePlot") == plot.data.index, "plot attribute")

	advance(3)
	local job = onlyJob(plot)
	assertTrue(job ~= nil, "no customer arrived")
	assertTrue(job.state == "arriving" and job.order.tier == "bikes", "first customer should be a bike")
	assertTrue(job.model.Parent ~= nil and job.model:GetAttribute("MovePath") ~= nil, "customer model/path missing")
	assertTrue(job.steps[1] == "foam" and #job.steps == 4, "level 1 orders are washes")
	advance(40)
	assertTrue(job.state == "waiting", "customer did not park (" .. job.state .. ")")
	assertTrue(string.find(plot.data.boardRows[1].Text, "$", 1, true) ~= nil, "order board empty")

	-- can't work before taking it
	assertTrue(not Service.handlers.work(player, job.id).ok, "worked on an untaken order")
	assertTrue(Service.handlers.take(player, job.id).ok, "take failed")
	assertTrue(not Service.handlers.take(player, job.id).ok, "took twice")
	assertTrue(job.state == "toBay" and job.bay == 1, "not sent to bay 1")
	local r = Service.handlers.work(player, job.id)
	assertTrue(not r.ok and r.message == "ServiceArriving", "worked while driving in")
	advance(30)
	assertTrue(job.state == "inBay", "vehicle did not reach the bay")

	-- a second customer can't get a bay while bay 1 is busy
	local second
	advance(40)
	for _, j in plot.jobs do
		if j ~= job and j.state == "waiting" then
			second = j
		end
	end
	assertTrue(second ~= nil, "second customer missing")
	assertTrue(Service.handlers.take(player, second.id).message == "ServiceNoBay", "two jobs in one bay")

	assertTrue(Service.handlers.work(player, job.id).ok, "work failed")
	assertTrue(job.working, "not marked working")
	r = Service.handlers.step(player, job.id, 1)
	assertTrue(not r.ok and r.message == "ServiceTooFast", "instant step accepted")
	r = Service.handlers.step(player, job.id, 3)
	assertTrue(not r.ok, "skipped a step")
	-- garbage input
	assertTrue(not Service.handlers.step(player, "x", 1).ok, "string job id accepted")
	assertTrue(not Service.handlers.step(player, job.id, nil).ok, "nil step accepted")

	local cash0, xp0 = data.cash, data.service.xp
	for i = 1, #job.steps do
		clock += 4
		r = Service.handlers.step(player, job.id, i)
		assertTrue(r.ok, "step " .. i .. " rejected: " .. tostring(r.message))
	end
	assertTrue(r.args[2] == true, "last step did not finish the order")
	assertTrue(data.cash >= cash0 + job.order.reward, "not paid")
	assertTrue(data.service.orders == 1 and data.service.xp > xp0, "order/xp not counted")
	assertTrue(data.service.stars >= 1, "no stars")
	assertTrue(job.state == "leaving", "vehicle not leaving")
	for _, d in job.model:GetDescendants() do
		if d:IsA("BasePart") then
			assertTrue(d:GetAttribute("CleanColor") == nil, "vehicle still dirty after the wash")
		end
	end
	advance(60)
	assertTrue(plot.jobs[job.id] == nil, "vehicle never left")
	assertTrue(not Service.handlers.step(player, job.id, 1).ok, "stepped on a finished job")
end)

test("level ups, upgrades with level gates and staff that work on their own", function()
	local player = makePlayer(3002)
	local data = PlayerData.get(player)
	local plot = Service.claim(player)
	assertTrue(plot ~= nil, "no plot")

	-- level gate and money check
	PlayerData.addCash(player, 1000000)
	local r = Service.handlers.buy(player, "bays")
	assertTrue(not r.ok and r.message == "ServiceNeedLevel", "bought a bay below its level")
	assertTrue(not Service.handlers.buy(player, "rocket").ok, "unknown upgrade accepted")
	PlayerData.update(player, function(d)
		d.service.xp = ServiceConfig.xpToNext(1) + ServiceConfig.xpToNext(2) + ServiceConfig.xpToNext(3) - 1
	end)
	-- finishing orders levels up: fake an order completion through the normal path
	advance(3)
	local job = onlyJob(plot)
	advance(40)
	assertTrue(Service.handlers.take(player, job.id).ok, "take failed")
	advance(30)
	assertTrue(Service.handlers.work(player, job.id).ok, "work failed")
	for i = 1, #job.steps do
		clock += 30
		assertTrue(Service.handlers.step(player, job.id, i).ok, "step failed")
	end
	assertTrue(data.service.level == 4, "expected level 4, got " .. data.service.level)

	local cash = data.cash
	r = Service.handlers.buy(player, "bays")
	assertTrue(r.ok, "bay purchase failed: " .. tostring(r.message))
	assertTrue(data.cash == cash - ServiceConfig.Upgrades[1].levels[1].price, "bay price wrong")
	assertTrue(plot.data.doors[2].CanCollide == false, "bay 2 door still closed")
	assertTrue(Service.handlers.buy(player, "staff").ok, "hire failed")
	assertTrue(#plot.workers == 1, "worker not spawned")
	assertTrue(plot.workers[1].model.Parent ~= nil, "worker model missing")

	-- the worker takes an order that waited long enough and finishes it alone
	local cash1, orders1 = data.cash, data.service.orders
	local picked
	for _ = 1, 400 do
		advance(1)
		for _, j in plot.jobs do
			if j.assignee == "worker" then
				picked = j
			end
		end
		if picked and picked.state == "leaving" then
			break
		end
	end
	assertTrue(picked ~= nil, "worker never took an order")
	assertTrue(picked.state == "leaving" or plot.jobs[picked.id] == nil, "worker never finished")
	assertTrue(data.cash > cash1 and data.service.orders > orders1, "worker order not paid")

	-- releasing the plot cleans up
	Service.release(player)
	assertTrue(next(plot.jobs) == nil and #plot.workers == 0 and plot.owner == nil, "plot not released")
	assertTrue(plot.data.doors[2].CanCollide == true, "doors not closed for the next owner")
end)

test("dump one dressed plot for the renderer", function()
	local CarBuilder = world.require(world.shared.CarBuilder)
	local folder = Instance.new("Folder")
	folder.Parent = env.workspace
	local plot = ServicePlots.build(folder, 99, CFrame.new())
	local function place(model, cf)
		model:PivotTo(cf)
		model.Parent = folder
	end
	place(ServiceModels.build("citybike", { paint = 5 }), plot.spots[1])
	place(ServiceModels.build("moped", { paint = 22 }), plot.spots[2])
	place(CarBuilder.build(CarCatalog.get("comet"), { preview = true }), plot.spots[4])
	place(ServiceModels.build("quad"), plot.spots[5])
	place(CarBuilder.build(CarCatalog.get("taxi"), { preview = true }), plot.bays[1])
	place(ServiceModels.build("sportbike"), plot.bays[2])
	plot.doors[2]:Destroy()
	local worker = ServiceModels.person("W", { cap = world.env.Color3.fromRGB(255, 128, 32) })
	place(worker, plot.bays[2] * CFrame.new(9, 0, 4) * CFrame.Angles(0, math.pi / 2, 0))
	local boss = ServiceModels.person("P", { shirt = world.env.Color3.fromRGB(230, 70, 60) })
	place(boss, plot.bays[1] * CFrame.new(-10, 0, 6) * CFrame.Angles(0, -math.pi / 2, 0))
	writefile("tests/out/plot.json", '[{"id":"plot","name":"Car service plot","parts":[' .. dumpModel(folder) .. "]}]")
	folder:Destroy()
end)

return tests
