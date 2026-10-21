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
