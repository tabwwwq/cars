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
local ORDER = { "Notifications", "Hud", "Drive", "VehicleFX", "Garage", "RaceUI", "WorldText" }

local function fire(service, event, ...)
	game:GetService(service)[event]:Fire(...)
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
	remote.OnClientEvent:Fire({ phase = "racing", nextIndex = 2, lap = 1 })
	fire("RunService", "RenderStepped", 1 / 60)
	remote.OnClientEvent:Fire({ phase = "finished", trackId = "circuit", time = 61.2, medal = "Silver", reward = 1700, newRecord = true, best = 61.2 })
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

return tests
