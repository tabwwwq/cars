-- ClientState: what the local client knows — the profile snapshot from the
-- server, live driving telemetry and whether the player is driving.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Signal = require(Shared.Util.Signal)

local ClientState = {}

ClientState.profile = nil :: any
ClientState.ProfileChanged = Signal.new() -- (profile)

ClientState.car = nil :: Model?
ClientState.CarChanged = Signal.new() -- (car?)

ClientState.driving = false
ClientState.DrivingChanged = Signal.new() -- (isDriving)

ClientState.telemetry = nil :: any -- CarPhysics telemetry of the own car
ClientState.racing = false
ClientState.raceTarget = nil :: Vector3? -- next checkpoint while racing

ClientState.service = nil :: any -- the own service plot snapshot (see Systems/Service)
ClientState.ServiceChanged = Signal.new() -- (snapshot)
ClientState.serviceOffset = 0 -- server time - local clock when the snapshot arrived
ClientState.workingJob = nil :: number? -- job id while the workshop minigame is open
ClientState.WorkingChanged = Signal.new() -- (jobId?)

function ClientState.setService(s)
	ClientState.service = s
	ClientState.ServiceChanged:Fire(s)
end

function ClientState.setWorking(id: number?)
	if ClientState.workingJob == id then
		return
	end
	ClientState.workingJob = id
	ClientState.WorkingChanged:Fire(id)
end

function ClientState.setProfile(p)
	ClientState.profile = p
	ClientState.ProfileChanged:Fire(p)
end

function ClientState.setCar(car: Model?)
	if ClientState.car == car then
		return
	end
	ClientState.car = car
	ClientState.CarChanged:Fire(car)
end

function ClientState.setDriving(v: boolean)
	if ClientState.driving == v then
		return
	end
	ClientState.driving = v
	ClientState.DrivingChanged:Fire(v)
end

return ClientState
