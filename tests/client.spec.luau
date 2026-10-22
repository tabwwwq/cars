-- Client smoke test: boots every controller against the mock, opens the
-- garage on every tab, plays through a race and drives the own car for a bit.

local world = newWorld()
local env = world.env
local game = world.game
local Instance, Vector3, Vector2 = env.Instance, env.Vector3, env.Vector2

harness.permissive = true

local function assertTrue(cond, msg)
	if not cond then
		error(msg, 2)
	end
end

local tests = {}
local function test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

-- local player + camera
local players = game:GetService("Players")
local localPlayer = Instance.new("Player")
localPlayer.Name = "Driver"
localPlayer.DisplayName = "Driver"
localPlayer.UserId = 77
localPlayer.LocaleId = "ru-ru"
localPlayer.Parent = players
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = localPlayer
players.LocalPlayer = localPlayer
local camera = Instance.new("Camera")
camera.ViewportSize = Vector2.new(1920, 1080)
camera.CFrame = env.CFrame.new(0, 20, 40)
camera.FieldOfView = 70
env.workspace.CurrentCamera = camera

local Net = world.require(world.shared.Net)
Net.init() -- the client reuses the folder the server would create

local controllers = {}
local ORDER = { "Loading", "Notifications", "Hud", "Drive", "VehicleFX", "Garage", "RaceUI", "Minimap", "WorldText", "ServiceFX", "Workshop", "Service" }

local function fire(service, event, ...)
	game:GetService(service)[event]:Fire(...)
end

-- writes tests/out/ui_<name>.json for tools/render_ui.py
local dumpGui = loadchunk(readfile("tests/harness/guidump.luau"), "@tests/harness/guidump.luau", setmetatable({}, { __index = _G }))()
local function uiShot(name)
	for _, gname in { "CarsLoading" } do
		local g = playerGui:FindFirstChild(gname)
		if g then
			g.Enabled = false
		end
	end
	writefile("tests/out/ui_" .. name .. ".json", dumpGui(playerGui, camera.ViewportSize))
end

test("every controller initializes and starts", function()
	local Strings = world.require(world.shared.Strings)
	Strings.setLanguage("ru")
	for _, name in ORDER do
		controllers[name] = world.require(world.client.Controllers[name])
	end
	for _, name in ORDER do
		local c = controllers[name]
		if c.init then
			c.init()
		end
	end
	for _, name in ORDER do
		local c = controllers[name]
		if c.start then
			c.start()
		end
	end
	assertTrue(playerGui:FindFirstChild("CarsHud") ~= nil, "HUD not created")
	assertTrue(playerGui:FindFirstChild("CarsGarage") ~= nil, "garage not created")
end)

local function snapshot()
	local PlayerData = world.require(world.server.Systems.PlayerData)
	local p = PlayerData.defaultProfile()
	p.owned.comet = true
	p.cars.comet = world.require(world.shared.CarCatalog).defaultSave(world.require(world.shared.CarCatalog).get("comet"))
	return PlayerData.publicSnapshot(p)
end

test("profile updates reach the HUD and the garage opens on every tab", function()
	local ClientState = world.require(world.client.ClientState)
	ClientState.setProfile(snapshot())
	for _ = 1, 30 do
		fire("RunService", "RenderStepped", 1 / 60)
	end
	local Garage = controllers.Garage
	Garage.open()
	assertTrue(Garage.isOpen(), "garage did not open")
	for _ = 1, 10 do
		fire("RunService", "RenderStepped", 1 / 60)
	end
	-- click through cars and tabs by calling the same paths the buttons use
	local gui = playerGui:FindFirstChild("CarsGarage")
	local grid
	for _, d in gui:GetDescendants() do
		if d.ClassName == "ScrollingFrame" and d:FindFirstChild("comet") then
			grid = d
		end
	end
	assertTrue(grid ~= nil, "car grid missing")
	local cardCount = 0
	for _, c in grid:GetChildren() do
		if c.ClassName == "Frame" then
			cardCount += 1
		end
	end
	assertTrue(cardCount == #world.require(world.shared.CarCatalog).List, "not every car has a card")
	-- press every TextButton in the garage once (tabs, chips, swatches, cards)
	local pressed = 0
	for _ = 1, 2 do
		for _, d in gui:GetDescendants() do
			if d.ClassName == "TextButton" and d.Parent then
				d.Activated:Fire()
				pressed += 1
			end
		end
	end
	assertTrue(pressed > 20, "too few buttons in the garage: " .. pressed)
	Garage.close()
end)

test("a race plays through countdown, checkpoints and results", function()
	local ClientState = world.require(world.client.ClientState)
	local Tracks = world.require(world.shared.Tracks)
	local track = Tracks.get("circuit")
	local cps = {}
	for i, p in track.points do
		table.insert(cps, { cf = env.CFrame.new(p), width = 48 })
	end
	local remote = game:GetService("ReplicatedStorage").CarsRemotes.RaceState
	remote.OnClientEvent:Fire({
		phase = "countdown",
		trackId = "circuit",
		goAt = env.workspace:GetServerTimeNow() + 3,
		checkpoints = cps,
		laps = 2,
		medals = { gold = 50, silver = 60, bronze = 70 },
		best = nil,
	})
	assertTrue(ClientState.racing, "race did not start on the client")
	fire("RunService", "RenderStepped", 1 / 60)
	uiShot("race_countdown")
	remote.OnClientEvent:Fire({ phase = "racing", nextIndex = 2, lap = 1 })
	fire("RunService", "RenderStepped", 1 / 60)
	uiShot("race_running")
	remote.OnClientEvent:Fire({ phase = "finished", trackId = "circuit", time = 61.2, medal = "Silver", reward = 1700, newRecord = true, best = 61.2 })
	uiShot("race_finished")
	assertTrue(not ClientState.racing, "race did not end")
	remote.OnClientEvent:Fire({ phase = "cancelled", reason = "RaceTimeout" })
end)

test("the own car is simulated and animated", function()
	local ClientState = world.require(world.client.ClientState)
	local CarBuilder = world.require(world.shared.CarBuilder)
	local CarCatalog = world.require(world.shared.CarCatalog)
	local CarPhysics = world.require(world.shared.CarPhysics)
	local def = CarCatalog.get("comet")
	local car = CarBuilder.build(def, { ownerName = "Driver" })
	car:SetAttribute("OwnerUserId", 77)
	car:SetAttribute("Lights", true)
	CarPhysics.writeStats(car, CarCatalog.getEffectiveStats(def, nil))
	car.Parent = env.workspace
	game:GetService("CollectionService"):AddTag(car, "Car")
	assertTrue(ClientState.car == car, "own car not detected")
	for _ = 1, 20 do
		fire("RunService", "PreSimulation", 1 / 60)
		fire("RunService", "PreRender", 1 / 60)
		fire("RunService", "RenderStepped", 1 / 60)
	end
	assertTrue(ClientState.telemetry ~= nil, "no telemetry")
	ClientState.setDriving(true)
	ClientState.telemetry.drifting = true
	ClientState.telemetry.driftAngle = 34
	ClientState.telemetry.speed = 60
	ClientState.telemetry.rpm = 0.7
	ClientState.telemetry.nitro = 0.6
	fire("RunService", "RenderStepped", 1 / 60)
	uiShot("driving")
	ClientState.setDriving(false)
	-- other players' cars get visual rigs too
	local other = CarBuilder.build(CarCatalog.get("interceptor"), { ownerName = "Cop" })
	other:SetAttribute("OwnerUserId", 5)
	other:SetAttribute("Siren", true)
	other.Parent = env.workspace
	game:GetService("CollectionService"):AddTag(other, "Car")
	for _ = 1, 20 do
		fire("RunService", "PreSimulation", 1 / 60)
	end
end)

test("notifications and rewards render", function()
	local remotes = game:GetService("ReplicatedStorage").CarsRemotes
	remotes.Notify.OnClientEvent:Fire("NotEnoughCash", { "$500" }, "warning")
	remotes.Notify.OnClientEvent:Fire("Upgraded", { "UpgradeEngine", 2 }, "success")
	remotes.Reward.OnClientEvent:Fire("drift", 120, 3.4)
	remotes.Reward.OnClientEvent:Fire("speedtrap", 350, 210)
	remotes.Reward.OnClientEvent:Fire("distance", 12, 300)
end)

test("car service: orders and business windows, and a full hands-on wash", function()
	local ClientState = world.require(world.client.ClientState)
	local ServiceModels = world.require(world.shared.ServiceModels)
	local CFrame = env.CFrame
	local remotes = game:GetService("ReplicatedStorage").CarsRemotes
	local now = env.workspace:GetServerTimeNow()

	-- a customer bike parked in bay 1, animated by ServiceFX
	local bike = ServiceModels.build("citybike", { paint = 5 })
	ServiceModels.weldToRoot(bike)
	bike:SetAttribute("ServiceJob", 1)
	bike:SetAttribute("Size", "tiny")
	bike:SetAttribute("Height", 3.5)
	bike:SetAttribute("Move", string.format("%.3f|10|0|0|0,0;0,-20;10,-40", now - 1))
	bike.Parent = env.workspace
	game:GetService("CollectionService"):AddTag(bike, "ServiceCustomer")
	local worker = ServiceModels.person("Worker_1", {})
	ServiceModels.weldToRoot(worker)
	worker:SetAttribute("Working", true)
	worker.Parent = env.workspace
	game:GetService("CollectionService"):AddTag(worker, "ServiceWorker")

	local job = {
		id = 1,
		tier = "bikes",
		source = "model",
		vehicle = "citybike",
		services = { "wash" },
		paint = 5,
		reward = 50,
		xp = 10,
		state = "waiting",
		steps = { "foam", "scrub", "rinse", "dry" },
		step = 1,
		size = "tiny",
		waitingSince = now,
	}
	local paintJob = {
		id = 2,
		tier = "moto",
		source = "car",
		vehicle = "comet",
		services = { "repair", "paint" },
		paint = 3,
		target = 5,
		reward = 400,
		xp = 30,
		state = "inBay",
		assignee = "worker",
		worker = 1,
		steps = { "wrench", "pump", "sand", "spray" },
		step = 1,
		size = "car",
		workerStart = now - 5,
		workerDuration = 20,
	}
	local function push(jobs)
		remotes.ServiceState.OnClientEvent:Fire({
			plot = 1,
			origin = CFrame.new(-310, 0.2, -115),
			reception = CFrame.new(-386, 3, -99),
			jobs = jobs,
			workers = { { index = 1, state = "working", job = 2 } },
			serverTime = now,
		})
	end
	push({ job, paintJob })
	assertTrue(ClientState.service ~= nil and #ClientState.service.jobs == 2, "service snapshot not stored")
	for _ = 1, 5 do
		fire("RunService", "RenderStepped", 1 / 60)
		fire("RunService", "Heartbeat", 1)
	end

	local Service = controllers.Service
	Service.openOrders()
	local gui = playerGui:FindFirstChild("CarsService")
	local cards = 0
	for _, d in gui:GetDescendants() do
		if d.ClassName == "Frame" and string.match(d.Name, "^Order%d") then
			cards += 1
		end
	end
	assertTrue(cards == 2, "expected 2 order cards, got " .. cards)
	Service.openBusiness()
	local upgradeButtons = 0
	for _, d in gui:GetDescendants() do
		if d.ClassName == "TextButton" and d.Parent then
			upgradeButtons += 1
			d.Activated:Fire()
		end
	end
	assertTrue(upgradeButtons > 8, "business window has too few buttons")
	remotes.ServiceEvent.OnClientEvent:Fire("arrived", 1)
	remotes.ServiceEvent.OnClientEvent:Fire("levelup", 4)
	remotes.ServiceEvent.OnClientEvent:Fire("done", { job = 9, reward = 50, tip = 12, xp = 10, stars = 3, worker = false, vehicle = "bmx", source = "model" })
	remotes.Reward.OnClientEvent:Fire("service", 62, 3)

	-- take it and work on it: stub the server answers
	local Net = world.require(world.shared.Net)
	local realRequest = Net.request
	local stepCalls = 0
	Net.request = function(action, id, step)
		if action == "ServiceWork" then
			return { ok = true, args = { 1 } }
		elseif action == "ServiceStep" then
			stepCalls += 1
			return { ok = true, args = { step + 1, step == 4 } }
		end
		return { ok = true }
	end
	job.state = "inBay"
	job.assignee = "player"
	job.bay = 1
	push({ job, paintJob })
	local Workshop = controllers.Workshop
	assertTrue(Workshop.enter(1), "workshop did not open")
	assertTrue(ClientState.workingJob == 1, "working state not set")
	local hooks = Workshop._test
	-- brush every spot of the current step until the whole order is done
	local seenSteps = {}
	for _ = 1, 400 do
		local sess = hooks.session()
		if sess.finished then
			break
		end
		if sess.started ~= sess.step then
			hooks.startStep() -- the real client waits half a second first
		end
		if not seenSteps[sess.step] then
			seenSteps[sess.step] = #sess.spots
		end
		for _, spot in table.clone(sess.spots) do
			hooks.brushAt(hooks.spotPosition(spot), 0.2)
		end
		fire("RunService", "RenderStepped", 1 / 60)
	end
	for stepIndex = 1, 4 do
		assertTrue((seenSteps[stepIndex] or 0) >= 4, "too few spots on step " .. stepIndex .. ": " .. tostring(seenSteps[stepIndex]))
	end
	assertTrue(stepCalls == 4, "expected 4 step reports, got " .. stepCalls)
	assertTrue(hooks.session().finished, "order not finished")
	Workshop.exit(true)
	assertTrue(ClientState.workingJob == nil and not Workshop.isActive(), "workshop did not close")

	-- paint job: sanding then spraying the body parts
	paintJob.assignee = "player"
	paintJob.step = 3
	push({ paintJob })
	local car = world.require(world.shared.CarBuilder).build(world.require(world.shared.CarCatalog).get("comet"), { preview = true })
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Parent = car
	car.PrimaryPart = root
	car:SetAttribute("ServiceJob", 2)
	car.Parent = env.workspace
	game:GetService("CollectionService"):AddTag(car, "ServiceCustomer")
	Net.request = function(action, id, step)
		if action == "ServiceWork" then
			return { ok = true, args = { 3 } }
		elseif action == "ServiceStep" then
			return { ok = true, args = { step + 1, step == 4 } }
		end
		return { ok = true }
	end
	assertTrue(Workshop.enter(2), "paint job did not open")
	local sess = hooks.session()
	assertTrue(sess.steps[sess.step] == "sand" and #sess.spots > 0, "sanding spots missing")
	for _ = 1, 40 do
		if sess.step ~= 3 then
			break
		end
		for _, spot in table.clone(sess.spots) do
			hooks.brushAt(hooks.spotPosition(spot), 0.25)
		end
	end
	if sess.started ~= sess.step then
		hooks.startStep()
	end
	assertTrue(sess.steps[sess.step] == "spray" and #sess.paint > 3, "spray step has no paint parts")
	for _ = 1, 60 do
		if sess.finished then
			break
		end
		for _, unit in sess.paint do
			hooks.brushAt(unit.part.Position, 0.3)
		end
	end
	assertTrue(sess.finished, "paint job did not finish")
	for _, unit in sess.paint do
		assertTrue(unit.progress >= 1, "a body part was left unpainted")
	end
	Workshop.exit(true)
	Net.request = realRequest
end)

test("dump the screens for the UI renderer", function()
	local dump = loadchunk(readfile("tests/harness/guidump.luau"), "@tests/harness/guidump.luau", setmetatable({}, { __index = _G }))()
	local ClientState = world.require(world.client.ClientState)
	local remotes = game:GetService("ReplicatedStorage").CarsRemotes
	local Service, Workshop, Garage = controllers.Service, controllers.Workshop, controllers.Garage
	local CFrame = env.CFrame
	local now = env.workspace:GetServerTimeNow()
	local function hideModals()
		for _, gui in playerGui:GetChildren() do
			for _, d in gui:GetChildren() do
				if d.ClassName ~= "UIScale" and (string.match(d.Name, "Dim$") or d.Name == "Orders" or d.Name == "Business" or d.Name == "Result" or d.Name == "LevelUp") then
					d.Visible = false
				end
			end
		end
	end
	local function shot(name)
		for _ = 1, 3 do
			fire("RunService", "RenderStepped", 1 / 60)
		end
		for _, name in { "CarsLoading", "CarsRace" } do
			local g = playerGui:FindFirstChild(name)
			if g then
				g.Enabled = false
			end
		end
		writefile("tests/out/ui_" .. name .. ".json", dump(playerGui, camera.ViewportSize))
	end

	-- start from a clean screen: no toasts or reward popups from earlier tests
	local notes = playerGui:FindFirstChild("CarsNotifications")
	for _, holder in notes:GetChildren() do
		for _, c in holder:GetChildren() do
			if c.ClassName == "Frame" then
				c:Destroy()
			end
		end
	end
	local character = Instance.new("Model")
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.CFrame = CFrame.new(-330, 3, -95)
	hrp.Parent = character
	character.PrimaryPart = hrp
	character.Parent = env.workspace
	localPlayer.Character = character

	local p = snapshot()
	p.cash = 48250
	p.service.level = 5
	p.service.xp = 290
	p.service.orders = 23
	p.service.stars = 61
	p.service.earned = 18400
	p.service.upgrades.bays = 1
	p.service.upgrades.tools = 2
	p.service.tutorial = 0
	p.service.orders = 0
	ClientState.setProfile(p)
	local function job(id, vehicle, source, services, state, extra)
		local j = {
			id = id,
			tier = if source == "model" then "mopeds" else "compact",
			source = source,
			vehicle = vehicle,
			services = services,
			paint = 13,
			reward = 180 + id * 37,
			xp = 18 + id,
			state = state,
			steps = world.require(world.shared.ServiceConfig).stepsFor(services),
			step = 1,
			size = if source == "model" then "small" else "car",
			waitingSince = now - id * 20,
		}
		for k, v in extra or {} do
			j[k] = v
		end
		return j
	end
	remotes.ServiceState.OnClientEvent:Fire({
		plot = 1,
		origin = CFrame.new(-310, 0.2, -115),
		reception = CFrame.new(-386, 3, -99),
		jobs = {
			job(11, "moped", "model", { "wash" }, "waiting"),
			job(12, "dirtbike", "model", { "repair", "wash" }, "waiting"),
			job(13, "pebble", "car", { "paint" }, "waiting", { target = 5 }),
			job(14, "classicbike", "model", { "wash" }, "inBay", { assignee = "worker", worker = 1, workerStart = now - 6, workerDuration = 20 }),
		},
		workers = { { index = 1, state = "working", job = 14 } },
		serverTime = now,
	})
	for _ = 1, 3 do
		fire("RunService", "Heartbeat", 1)
	end
	hideModals()
	remotes.Notify.OnClientEvent:Fire("ServiceArrived", {}, "info")
	remotes.Reward.OnClientEvent:Fire("service", 240, 3)
	remotes.Reward.OnClientEvent:Fire("drift", 120, 3.4)
	shot("hud")
	for _, holder in notes:GetChildren() do
		for _, c in holder:GetChildren() do
			if c.ClassName == "Frame" then
				c:Destroy()
			end
		end
	end
	Service.openOrders()
	shot("orders")
	hideModals()
	Service.openBusiness()
	shot("business")
	hideModals()
	Service._test.showResult({ job = 9, reward = 240, tip = 60, xp = 22, stars = 3, worker = false, vehicle = "moped", source = "model" })
	shot("result")
	hideModals()
	Service._test.showLevelUp(4)
	shot("levelup")
	hideModals()

	-- the workshop minigame on a parked moped
	local moped = world.require(world.shared.ServiceModels).build("moped", { paint = 22 })
	world.require(world.shared.ServiceModels).weldToRoot(moped)
	moped:SetAttribute("ServiceJob", 21)
	moped.Parent = env.workspace
	game:GetService("CollectionService"):AddTag(moped, "ServiceCustomer")
	remotes.ServiceState.OnClientEvent:Fire({
		plot = 1,
		origin = CFrame.new(-310, 0.2, -115),
		jobs = { job(21, "moped", "model", { "repair", "wash" }, "inBay", { assignee = "player", bay = 1, step = 3 }) },
		workers = {},
		serverTime = now,
	})
	local Net = world.require(world.shared.Net)
	local realRequest = Net.request
	Net.request = function(action)
		if action == "ServiceWork" then
			return { ok = true, args = { 3 } }
		end
		return { ok = true }
	end
	assertTrue(Workshop.enter(21), "workshop did not open for the screenshot")
	local sess = Workshop._test.session()
	for i = 1, 6 do
		local spot = sess.spots[i]
		if spot then
			Workshop._test.brushAt(Workshop._test.spotPosition(spot), 0.05)
		end
	end
	shot("workshop")
	Workshop.exit(true)
	Net.request = realRequest

	Garage.open()
	shot("garage")
	Garage.close()
	hideModals()
end)

return tests
