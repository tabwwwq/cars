-- VehicleFX: everything visual about cars, for every car near the camera:
-- wheel animation of other players' cars, head/brake lights, sirens,
-- exhaust smoke, nitro flames, skid marks, tire smoke, optional sounds and
-- the visibility of seat prompts.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarBuilder = require(Shared.CarBuilder)
local CarPhysics = require(Shared.CarPhysics)
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)

local Drive = require(script.Parent.Drive)

local VehicleFX = {}

local player = Players.LocalPlayer
local MAX_DISTANCE = 450
local TAIL_OFF = Color3.fromRGB(120, 8, 12)
local TAIL_ON = Color3.fromRGB(255, 40, 40)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

type Rig = {
	model: Model,
	chassis: BasePart,
	wheels: { CarPhysics.Wheel },
	rays: RaycastParams,
	heads: { BasePart },
	tails: { BasePart },
	beam: Light?,
	brakeGlow: Light?,
	sirens: { BasePart },
	sirenLights: { Light },
	exhausts: { ParticleEmitter },
	flames: { ParticleEmitter },
	trails: { Trail },
	smokes: { ParticleEmitter },
	lastSpeed: number,
	brakeHold: number,
	sirenClock: number,
	engine: Sound?,
	conns: { RBXScriptConnection },
	isMine: boolean,
	prompts: { ProximityPrompt },
}

local rigs: { [Model]: Rig } = {}

local function emitter(parent: Instance, texture: string, color: Color3, size: number, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(18, 18)
	e.Rate = rate
	e.LightInfluence = 0.8
	e.Enabled = false
	e.Parent = parent
	return e
end

local function sound(parent: Instance, id: string, looped: boolean, volume: number): Sound?
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = looped
	s.Volume = volume
	s.RollOffMaxDistance = 260
	s.RollOffMinDistance = 12
	s.Parent = parent
	return s
end

local function updatePrompts(rig: Rig)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local seated = hum ~= nil and hum.SeatPart ~= nil
	for _, prompt in rig.prompts do
		local seat = prompt.Parent :: Seat
		local free = seat.Occupant == nil
		if seat.Name == "DriveSeat" then
			prompt.Enabled = rig.isMine and free and not seated
		else
			prompt.Enabled = free and not seated
		end
		prompt.ActionText = Strings.get(prompt:GetAttribute("LocAction") or "PromptSit")
	end
end

local function build(model: Model)
	if rigs[model] then
		return
	end
	local chassis = model:WaitForChild("Chassis", 10) :: BasePart?
	if not chassis or not model.Parent then
		return
	end
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude
	rays.FilterDescendantsInstances = { model }
	rays.CollisionGroup = "WheelRays"
	rays.IgnoreWater = true
	local rig: Rig = {
		model = model,
		chassis = chassis,
		wheels = CarPhysics.readWheels(model),
		rays = rays,
		heads = {},
		tails = {},
		beam = nil,
		brakeGlow = nil,
		sirens = {},
		sirenLights = {},
		exhausts = {},
		flames = {},
		trails = {},
		smokes = {},
		lastSpeed = 0,
		brakeHold = 0,
		sirenClock = 0,
		engine = nil,
		conns = {},
		isMine = model:GetAttribute("OwnerUserId") == player.UserId,
		prompts = {},
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Role")
			if role == "Headlight" then
				table.insert(rig.heads, d)
			elseif role == "Taillight" then
				table.insert(rig.tails, d)
			elseif role == "SirenA" or role == "SirenB" then
				table.insert(rig.sirens, d)
				local l = d:FindFirstChildOfClass("PointLight")
				if l then
					table.insert(rig.sirenLights, l)
				end
			end
		elseif d:IsA("ProximityPrompt") and d.Name == "SitPrompt" then
			table.insert(rig.prompts, d)
		end
	end
	local beamPart = model:FindFirstChild("HeadlightBeam", true)
	rig.beam = beamPart and beamPart:FindFirstChildWhichIsA("Light")
	local tailPart = model:FindFirstChild("TailGlow", true)
	rig.brakeGlow = tailPart and tailPart:FindFirstChildWhichIsA("Light")

	-- exhaust + nitro
	for _, a in chassis:GetChildren() do
		if a:IsA("Attachment") and string.sub(a.Name, 1, 7) == "Exhaust" then
			local smoke = emitter(a, SMOKE, Color3.fromRGB(150, 150, 155), 1.6, 12)
			smoke.EmissionDirection = Enum.NormalId.Back
			table.insert(rig.exhausts, smoke)
			local flame = emitter(a, FIRE, Color3.fromRGB(90, 170, 255), 1.4, 60)
			flame.LightEmission = 1
			flame.Lifetime = NumberRange.new(0.12, 0.22)
			flame.Speed = NumberRange.new(14, 20)
			flame.EmissionDirection = Enum.NormalId.Back
			flame.Transparency = NumberSequence.new(0.1, 1)
			table.insert(rig.flames, flame)
		end
	end
	-- skid marks and tire smoke on the rear wheels
	for _, w in rig.wheels do
		local index = w.part and w.part:GetAttribute("Index")
		local a0 = chassis:FindFirstChild("SkidA_" .. tostring(index))
		local a1 = chassis:FindFirstChild("SkidB_" .. tostring(index))
		if a0 and a1 then
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0 :: Attachment
			trail.Attachment1 = a1 :: Attachment
			trail.Color = ColorSequence.new(Color3.fromRGB(20, 20, 22))
			trail.Transparency = NumberSequence.new(0.35, 1)
			trail.Lifetime = 3
			trail.MinLength = 0.2
			trail.FaceCamera = false
			trail.LightInfluence = 1
			trail.Enabled = false
			trail.Parent = chassis
			table.insert(rig.trails, trail)
			local smoke = emitter(a0, SMOKE, Color3.fromRGB(225, 225, 228), 4, 40)
			smoke.Lifetime = NumberRange.new(0.8, 1.6)
			smoke.Speed = NumberRange.new(1, 3)
			smoke.Acceleration = Vector3.new(0, 3, 0)
			table.insert(rig.smokes, smoke)
		end
	end

	-- optional sounds
	rig.engine = sound(chassis, Config.Sounds.Engine, true, 0.45)
	if rig.engine then
		rig.engine:Play()
	end
	local horn = sound(chassis, Config.Sounds.Horn, false, 0.8)
	local siren = sound(chassis, Config.Sounds.Siren, true, 0.6)
	table.insert(
		rig.conns,
		model:GetAttributeChangedSignal("Horn"):Connect(function()
			if horn then
				horn:Play()
			end
		end)
	)

	local function applyLights()
		local on = model:GetAttribute("Lights") == true
		for _, h in rig.heads do
			h.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		if rig.beam then
			rig.beam.Enabled = on
		end
	end
	applyLights()
	table.insert(rig.conns, model:GetAttributeChangedSignal("Lights"):Connect(applyLights))
	table.insert(
		rig.conns,
		model:GetAttributeChangedSignal("Siren"):Connect(function()
			local on = model:GetAttribute("Siren") == true
			if siren then
				if on then
					siren:Play()
				else
					siren:Stop()
				end
			end
			if not on then
				for _, p in rig.sirens do
					p.Material = Enum.Material.SmoothPlastic
				end
				for _, l in rig.sirenLights do
					l.Enabled = false
				end
			end
		end)
	)
	for _, prompt in rig.prompts do
		local seat = prompt.Parent :: Seat
		table.insert(
			rig.conns,
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				updatePrompts(rig)
			end)
		)
	end
	updatePrompts(rig)
	rigs[model] = rig
end

local function remove(model: Instance)
	local rig = rigs[model :: Model]
	if rig then
		for _, c in rig.conns do
			c:Disconnect()
		end
		rigs[model :: Model] = nil
	end
end

local function setEnabled(list: { any }, on: boolean)
	for _, e in list do
		if e.Enabled ~= on then
			e.Enabled = on
		end
	end
end

local function updateRig(rig: Rig, dt: number, camPos: Vector3)
	local chassis = rig.chassis
	if not chassis.Parent then
		return
	end
	local cf = chassis.CFrame
	local dist = (cf.Position - camPos).Magnitude
	local near = dist < MAX_DISTANCE
	local vel = chassis.AssemblyLinearVelocity
	local look = cf.LookVector
	local fwd = vel:Dot(look)
	local speed = vel.Magnitude
	local up = cf.UpVector
	local planar = vel - up * vel:Dot(up)
	local slip = 0
	if planar.Magnitude > 5 then
		slip = math.deg(math.atan2(math.abs(planar:Dot(cf.RightVector)), math.max(math.abs(planar:Dot(look)), 1e-3)))
	end

	local sim = if rig.isMine then Drive.getSim() else nil
	local grounded = true
	local braking, nitro, drifting, throttleish
	if sim and sim.chassis == chassis then
		local t = sim.telemetry
		braking = t.braking
		nitro = sim.nitroActive
		drifting = t.drifting or (t.slipping and t.grounded >= 2 and math.abs(t.forwardSpeed) < 25 and t.rpm > 0.6)
		throttleish = t.rpm
		grounded = t.grounded >= 2
	else
		-- other cars: animate wheels locally and infer the rest from motion
		if near then
			local yawRate = chassis.AssemblyAngularVelocity:Dot(up)
			local steer = 0
			if math.abs(fwd) > 3 then
				-- yaw rate is negative in a right turn, steer is positive to the right
				steer = math.clamp(math.atan(-yawRate * 9 / fwd), -0.6, 0.6)
			end
			local hits = 0
			for _, w in rig.wheels do
				local mount = cf:PointToWorldSpace(w.mount)
				local rest = (rig.model:GetAttribute("SuspRest") or 1.4) :: number
				local hit = Workspace:Raycast(mount, -up * (rest + w.radius), rig.rays)
				if hit then
					hits += 1
					w.springLen = math.clamp(hit.Distance - w.radius, 0, rest)
				else
					w.springLen += (rest - w.springLen) * math.clamp(dt * 8, 0, 1)
				end
				w.steerAngle = if w.steer then steer else 0
				w.spin += fwd / w.radius * dt
				if w.motor then
					w.motor.Transform = CFrame.new(0, w.staticLen - w.springLen, 0)
						* CFrame.Angles(0, -w.steerAngle, 0)
						* CFrame.Angles(-w.spin, 0, 0)
				end
			end
			grounded = hits >= 2
		end
		local decel = (rig.lastSpeed - math.abs(fwd)) / math.max(dt, 1e-3)
		if decel > 30 and math.abs(fwd) > 3 then
			rig.brakeHold = 0.25
		end
		rig.brakeHold -= dt
		braking = rig.brakeHold > 0
		nitro = rig.model:GetAttribute("Nitro") == true
		drifting = grounded and planar.Magnitude > 28 and slip > 14 and slip < 110
		throttleish = math.clamp(speed / 120, 0.2, 1)
	end
	rig.lastSpeed = math.abs(fwd)

	if not near then
		setEnabled(rig.exhausts, false)
		setEnabled(rig.flames, false)
		setEnabled(rig.trails, false)
		setEnabled(rig.smokes, false)
		return
	end

	-- brake lights
	for _, p in rig.tails do
		local c = if braking then TAIL_ON else TAIL_OFF
		if p.Color ~= c then
			p.Color = c
		end
	end
	if rig.brakeGlow then
		rig.brakeGlow.Brightness = if braking then 3 else 0
	end

	-- exhaust, nitro, skids
	for _, e in rig.exhausts do
		e.Rate = 6 + throttleish * 26
	end
	setEnabled(rig.exhausts, speed < 160)
	setEnabled(rig.flames, nitro)
	setEnabled(rig.trails, drifting and grounded)
	setEnabled(rig.smokes, drifting and grounded)

	-- siren
	if rig.model:GetAttribute("Siren") == true and #rig.sirens > 0 then
		rig.sirenClock += dt
		local phase = math.floor(rig.sirenClock * 6) % 2
		local sirenType = rig.model:GetAttribute("SirenType") or "police"
		local colors = CarBuilder.SirenColors[sirenType] or CarBuilder.SirenColors.police
		for _, p in rig.sirens do
			local isA = p:GetAttribute("Role") == "SirenA"
			local lit = (isA and phase == 0) or (not isA and phase == 1)
			p.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			p.Color = (if isA then colors[1] else colors[2]):Lerp(Color3.new(0, 0, 0), if lit then 0 else 0.55)
			local l = p:FindFirstChildOfClass("PointLight")
			if l then
				l.Enabled = lit
			end
		end
	end

	-- engine sound pitch
	if rig.engine then
		rig.engine.PlaybackSpeed = 0.7 + throttleish * 1.1
	end
end

function VehicleFX.start()
	for _, m in CollectionService:GetTagged("Car") do
		task.spawn(build, m)
	end
	CollectionService:GetInstanceAddedSignal("Car"):Connect(function(m)
		task.spawn(build, m)
	end)
	CollectionService:GetInstanceRemovedSignal("Car"):Connect(remove)

	-- seat prompts depend on whether the local player sits
	local function watchCharacter(character: Model)
		local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
				for _, rig in rigs do
					updatePrompts(rig)
				end
			end)
		end
		for _, rig in rigs do
			updatePrompts(rig)
		end
	end
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	RunService.PreSimulation:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		for model, rig in rigs do
			if not model.Parent then
				remove(model)
			else
				local ok, err = pcall(updateRig, rig, dt, camPos)
				if not ok then
					warn("[VehicleFX] " .. tostring(err))
					remove(model)
				end
			end
		end
	end)
end

return VehicleFX
