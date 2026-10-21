-- Drive: simulates the local player's own car (the client is its network
-- owner), reads driving input on every platform, binds driver actions with
-- touch buttons, and adds speed feel to the camera.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarPhysics = require(Shared.CarPhysics)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)

local ClientState = require(script.Parent.Parent.ClientState)

local Drive = {}

local player = Players.LocalPlayer
local car: Model? = nil
local sim: CarPhysics.Sim? = nil
local carConns: { RBXScriptConnection } = {}
local keys = { handbrake = false, nitro = false }
local lastNitroSent = false
local actionsBound = false
local cameraMode = 0
local CAMERA_MODES = { 0, 22, 34 } -- 0 = free zoom
local baseFov = 70

local STAT_ATTRIBUTES = {
	"MaxSpeed",
	"Accel",
	"Grip",
	"SteerAngle",
	"Brake",
	"Drift",
	"NitroPower",
	"NitroRecharge",
	"Offroad",
	"SuspRest",
	"SuspFreq",
	"SuspDamping",
}

local function detach()
	for _, c in carConns do
		c:Disconnect()
	end
	table.clear(carConns)
	car = nil
	sim = nil
	ClientState.telemetry = nil
	ClientState.setCar(nil)
end

local function attach(model: Model)
	detach()
	local chassis = model:WaitForChild("Chassis", 10) :: BasePart?
	if not chassis or not model.Parent then
		return
	end
	-- wait until all wheels are here
	local deadline = os.clock() + 5
	local wheels = CarPhysics.readWheels(model)
	while #wheels < 4 and os.clock() < deadline do
		task.wait(0.1)
		wheels = CarPhysics.readWheels(model)
	end
	car = model
	local s = CarPhysics.new(chassis, wheels, CarPhysics.readStats(model), model)
	sim = s
	for _, name in STAT_ATTRIBUTES do
		table.insert(
			carConns,
			model:GetAttributeChangedSignal(name):Connect(function()
				s.stats = CarPhysics.readStats(model)
			end)
		)
	end
	table.insert(
		carConns,
		model.AncestryChanged:Connect(function(_, parent)
			if parent == nil and car == model then
				detach()
			end
		end)
	)
	ClientState.setCar(model)
end

local function isMine(model: Instance): boolean
	return model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId
end

local function onCarAdded(model: Instance)
	if isMine(model) then
		task.spawn(attach, model :: Model)
	end
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local function send(action: string, value: any?)
	Net.send("VehicleAction", action, value)
end

local function setCameraMode(index: number)
	cameraMode = index
	local d = CAMERA_MODES[index + 1] or 0
	if d == 0 then
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 400
	else
		player.CameraMaxZoomDistance = d
		player.CameraMinZoomDistance = d
	end
end

local function handle(name: string, state: Enum.UserInputState): Enum.ContextActionResult
	local began = state == Enum.UserInputState.Begin
	if name == "CarsHandbrake" then
		keys.handbrake = began or state == Enum.UserInputState.Change
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			keys.handbrake = false
		end
	elseif name == "CarsNitro" then
		keys.nitro = began or state == Enum.UserInputState.Change
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			keys.nitro = false
		end
	elseif began then
		if name == "CarsFlip" then
			send("Flip")
		elseif name == "CarsExit" then
			send("Exit")
		elseif name == "CarsLights" then
			send("Lights")
		elseif name == "CarsSiren" then
			send("Siren")
		elseif name == "CarsHorn" then
			send("Horn")
		elseif name == "CarsCamera" then
			setCameraMode((cameraMode + 1) % #CAMERA_MODES)
		end
	end
	return Enum.ContextActionResult.Sink
end

local ACTIONS = {
	{ name = "CarsHandbrake", keys = Config.Keys.Handbrake, title = "Handbrake", touch = true, pos = UDim2.new(1, -170, 1, -170) },
	{ name = "CarsNitro", keys = Config.Keys.Nitro, title = "Nitro", touch = true, pos = UDim2.new(1, -95, 1, -230) },
	{ name = "CarsFlip", keys = Config.Keys.Flip, title = "Flip", touch = true, pos = UDim2.new(1, -245, 1, -110) },
	{ name = "CarsExit", keys = Config.Keys.Exit, title = "Exit", touch = true, pos = UDim2.new(1, -95, 1, -310) },
	{ name = "CarsLights", keys = Config.Keys.Lights, title = "Lights", touch = false },
	{ name = "CarsSiren", keys = Config.Keys.Siren, title = "Siren", touch = true, pos = UDim2.new(1, -170, 1, -280), sirenOnly = true },
	{ name = "CarsHorn", keys = Config.Keys.Horn, title = "Horn", touch = true, pos = UDim2.new(1, -245, 1, -200) },
	{ name = "CarsCamera", keys = Config.Keys.Camera, title = "Camera", touch = false },
}

local function bindActions()
	if actionsBound then
		return
	end
	actionsBound = true
	local hasSiren = car ~= nil and car:GetAttribute("HasSiren") == true
	for _, a in ACTIONS do
		if a.sirenOnly and not hasSiren then
			continue
		end
		ContextActionService:BindActionAtPriority(a.name, handle, a.touch, Enum.ContextActionPriority.High.Value, table.unpack(a.keys))
		if a.touch then
			ContextActionService:SetTitle(a.name, Strings.get(a.title))
			if a.pos then
				ContextActionService:SetPosition(a.name, a.pos)
			end
		end
	end
end

local function unbindActions()
	if not actionsBound then
		return
	end
	actionsBound = false
	for _, a in ACTIONS do
		ContextActionService:UnbindAction(a.name)
	end
	keys.handbrake = false
	keys.nitro = false
end

--------------------------------------------------------------------------------
-- Simulation loop
--------------------------------------------------------------------------------

local parkedInput = { throttle = 0, steer = 0, handbrake = true, nitro = false, parked = true }
local driveInput = { throttle = 0, steer = 0, handbrake = false, nitro = false, parked = false }

local function step(dt: number)
	local s = sim
	local model = car
	if not s or not model or not model.Parent then
		ClientState.setDriving(false)
		return
	end
	local chassis = s.chassis
	if not chassis.Parent then
		return
	end
	local seat = model:FindFirstChild("DriveSeat") :: VehicleSeat?
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local driving = hum ~= nil and seat ~= nil and hum.SeatPart == seat and hum.Health > 0
	ClientState.setDriving(driving)

	local input = parkedInput
	if driving and seat then
		driveInput.throttle = seat.ThrottleFloat
		driveInput.steer = seat.SteerFloat
		driveInput.handbrake = keys.handbrake
		driveInput.nitro = keys.nitro
		input = driveInput
	end

	if not chassis.Anchored then
		s:step(dt, input)
	end
	s:updateVisuals()
	ClientState.telemetry = s.telemetry

	if driving and s.nitroActive ~= lastNitroSent then
		lastNitroSent = s.nitroActive
		send("Nitro", lastNitroSent)
	elseif not driving and lastNitroSent then
		lastNitroSent = false
		send("Nitro", false)
	end
end

local function updateCamera(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local target = baseFov
	local s = sim
	if ClientState.driving and s then
		local frac = math.clamp(s.telemetry.speed / math.max(s.stats.maxSpeed, 1), 0, 1.3)
		target = baseFov + 14 * frac + (if s.nitroActive then 9 else 0)
	end
	camera.FieldOfView += (target - camera.FieldOfView) * math.clamp(dt * 4, 0, 1)
end

function Drive.init()
	baseFov = 70
end

function Drive.start()
	for _, model in CollectionService:GetTagged("Car") do
		onCarAdded(model)
	end
	CollectionService:GetInstanceAddedSignal("Car"):Connect(onCarAdded)
	CollectionService:GetInstanceRemovedSignal("Car"):Connect(function(model)
		if model == car then
			detach()
		end
	end)

	ClientState.DrivingChanged:Connect(function(driving)
		if driving then
			bindActions()
		else
			unbindActions()
			setCameraMode(0)
		end
	end)

	RunService.PreSimulation:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[Drive] " .. tostring(err))
		end
	end)
	RunService.PreRender:Connect(updateCamera)
end

function Drive.getSim(): CarPhysics.Sim?
	return sim
end

return Drive
