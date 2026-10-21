-- Environment: lighting, atmosphere, post effects and the day/night cycle.
-- Street lamps (tag "StreetLight") switch on at night.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Config = require(Shared.Config)

local World = require(script.Parent.World)

local Environment = {}

local function ensure(className: string, name: string): Instance
	local inst = Lighting:FindFirstChild(name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
	end
	return inst
end

local nightLights = false

local function setStreetLights(on: boolean)
	nightLights = on
	for _, head in CollectionService:GetTagged("StreetLight") do
		if head:IsA("BasePart") then
			head.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local light = head:FindFirstChildWhichIsA("Light")
			if light then
				light.Enabled = on
			end
		end
	end
end

function Environment.isNight(): boolean
	local t = Lighting.ClockTime
	return t >= Config.DayNight.NightStart or t < Config.DayNight.NightEnd
end

function Environment.init()
	Lighting.ClockTime = Config.DayNight.StartClock
	Lighting.Brightness = 2.6
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 136)
	Lighting.Ambient = Color3.fromRGB(70, 70, 80)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.GeographicLatitude = 35

	local atmosphere = ensure("Atmosphere", "CarsAtmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(199, 214, 228)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2

	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "CarsSky"
		sky.SunAngularSize = 14
		sky.MoonAngularSize = 9
		sky.Parent = Lighting
	end

	local bloom = ensure("BloomEffect", "CarsBloom") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 26
	bloom.Threshold = 1.6

	local rays = ensure("SunRaysEffect", "CarsSunRays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.6

	local cc = ensure("ColorCorrectionEffect", "CarsColor") :: ColorCorrectionEffect
	cc.Saturation = 0.12
	cc.Contrast = 0.06
	cc.Brightness = 0.01
end

function Environment.start()
	setStreetLights(Environment.isNight())
	-- lamps are created while the world builds
	World.ReadySignal:Connect(function()
		setStreetLights(Environment.isNight())
	end)
	if not Config.DayNight.Enabled then
		return
	end
	local hoursPerSecond = 24 / (Config.DayNight.MinutesPerDay * 60)
	RunService.Heartbeat:Connect(function(dt)
		Lighting.ClockTime = (Lighting.ClockTime + dt * hoursPerSecond) % 24
		local night = Environment.isNight()
		if night ~= nightLights then
			setStreetLights(night)
			local cc = Lighting:FindFirstChild("CarsColor") :: ColorCorrectionEffect?
			if cc then
				cc.TintColor = if night then Color3.fromRGB(205, 215, 255) else Color3.new(1, 1, 1)
			end
			Lighting.OutdoorAmbient = if night then Color3.fromRGB(70, 74, 96) else Color3.fromRGB(128, 128, 136)
		end
	end)
end

return Environment
