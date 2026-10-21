-- CarPhysics: arcade raycast vehicle simulation.
--
-- Runs on the client that owns the car (network owner). Every physics step it
-- casts one ray per wheel, computes spring/damper suspension and tire forces
-- and applies them to the chassis as impulses. Gravity and collisions are left
-- to the Roblox engine.
--
-- Tire forces are impulse based and integrated internally at ~240 Hz: each
-- wheel removes a share of its sideways slip per sub step, scaled by the
-- effective mass at the contact point, and limited by a friction circle
-- (grip * load). The result is stable and identical at 30, 60 or 144 FPS.

local Config = require(script.Parent.Config)
local CarCatalog = require(script.Parent.CarCatalog)
local Types = require(script.Parent.Types)

type EffectiveStats = Types.EffectiveStats

export type Input = {
	throttle: number, -- -1..1 (negative = brake / reverse)
	steer: number, -- -1..1 (positive = right)
	handbrake: boolean,
	nitro: boolean,
	parked: boolean?, -- nobody driving: hold the car still
}

export type Wheel = {
	part: BasePart?,
	motor: Motor6D?,
	mount: Vector3, -- chassis space, top of the suspension travel
	radius: number,
	steer: boolean,
	drive: boolean,
	side: number,
	staticLen: number,
	-- state (also read by the visuals)
	springLen: number,
	grounded: boolean,
	contact: Vector3,
	normal: Vector3,
	material: Enum.Material?,
	spin: number,
	steerAngle: number,
	slipping: boolean,
	load: number,
}

export type Telemetry = {
	speed: number,
	forwardSpeed: number,
	gear: number,
	rpm: number,
	nitro: number,
	nitroActive: boolean,
	drifting: boolean,
	driftAngle: number,
	airborne: boolean,
	airTime: number,
	grounded: number,
	surface: string,
	braking: boolean,
	slipping: boolean,
}

local CarPhysics = {}
CarPhysics.__index = CarPhysics

export type Sim = typeof(setmetatable(
	{} :: {
		chassis: BasePart,
		model: Model?,
		stats: EffectiveStats,
		wheels: { Wheel },
		steer: number,
		nitro: number,
		nitroActive: boolean,
		airTime: number,
		telemetry: Telemetry,
		raycast: (origin: Vector3, direction: Vector3) -> RaycastResult?,
		rayParams: RaycastParams?,
		inertiaLocal: Vector3,
	},
	CarPhysics
))

local P = Config.Physics
local GEAR_STARTS = { 0, 0.16, 0.31, 0.47, 0.63, 0.8 }

local surfaceCache: { [Enum.Material]: { grip: number, drag: number } } = {}
local function surfaceOf(material: Enum.Material?)
	if not material then
		return Config.Surfaces.Default
	end
	local s = surfaceCache[material]
	if not s then
		s = (Config.Surfaces :: any)[material.Name] or Config.Surfaces.Default
		surfaceCache[material] = s
	end
	return s
end

local function moveTowards(current: number, target: number, maxDelta: number): number
	if math.abs(target - current) <= maxDelta then
		return target
	end
	return current + math.sign(target - current) * maxDelta
end

-- Reads effective stats from model attributes (written by the server) and
-- falls back to the catalog definition.
function CarPhysics.readStats(model: Model): EffectiveStats
	local def = CarCatalog.get(model:GetAttribute("CarId"))
	local base = if def then CarCatalog.getEffectiveStats(def, nil) else nil
	local function num(name: string, fallback: number): number
		local v = model:GetAttribute(name)
		if typeof(v) == "number" then
			return v
		end
		return fallback
	end
	local fallback = base
		or {
			maxSpeed = 100,
			accel = 35,
			grip = 1,
			steer = 32,
			brake = 100,
			drift = 0.2,
			nitroPower = 1,
			nitroRecharge = 1,
			offroad = 0.2,
			drive = "RWD",
			suspRest = 1.3,
			suspFreq = P.SuspensionFrequency,
			suspDamping = P.SuspensionDamping,
		}
	return {
		maxSpeed = num("MaxSpeed", fallback.maxSpeed),
		accel = num("Accel", fallback.accel),
		grip = num("Grip", fallback.grip),
		steer = num("SteerAngle", fallback.steer),
		brake = num("Brake", fallback.brake),
		drift = num("Drift", fallback.drift),
		nitroPower = num("NitroPower", fallback.nitroPower),
		nitroRecharge = num("NitroRecharge", fallback.nitroRecharge),
		offroad = num("Offroad", fallback.offroad),
		drive = (model:GetAttribute("Drive") or fallback.drive) :: any,
		suspRest = num("SuspRest", fallback.suspRest),
		suspFreq = num("SuspFreq", fallback.suspFreq),
		suspDamping = num("SuspDamping", fallback.suspDamping),
	}
end

function CarPhysics.writeStats(model: Model, stats: EffectiveStats)
	model:SetAttribute("MaxSpeed", stats.maxSpeed)
	model:SetAttribute("Accel", stats.accel)
	model:SetAttribute("Grip", stats.grip)
	model:SetAttribute("SteerAngle", stats.steer)
	model:SetAttribute("Brake", stats.brake)
	model:SetAttribute("Drift", stats.drift)
	model:SetAttribute("NitroPower", stats.nitroPower)
	model:SetAttribute("NitroRecharge", stats.nitroRecharge)
	model:SetAttribute("Offroad", stats.offroad)
	model:SetAttribute("Drive", stats.drive)
	model:SetAttribute("SuspRest", stats.suspRest)
	model:SetAttribute("SuspFreq", stats.suspFreq)
	model:SetAttribute("SuspDamping", stats.suspDamping)
end

-- Collects the wheel rig (mount points etc.) from the tire parts of a car model.
function CarPhysics.readWheels(model: Model): { Wheel }
	local wheels: { Wheel } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("Wheel") then
			local motor = child:FindFirstChild("Axle")
			table.insert(wheels, {
				part = child,
				motor = if motor and motor:IsA("Motor6D") then motor else nil,
				mount = child:GetAttribute("Mount") :: Vector3,
				radius = child:GetAttribute("Radius") :: number,
				steer = child:GetAttribute("Steer") == true,
				drive = child:GetAttribute("Drive") == true,
				side = child:GetAttribute("Side") :: number,
				staticLen = child:GetAttribute("StaticLen") :: number,
				springLen = child:GetAttribute("StaticLen") :: number,
				grounded = false,
				contact = Vector3.zero,
				normal = Vector3.yAxis,
				material = nil,
				spin = 0,
				steerAngle = 0,
				slipping = false,
				load = 0,
				index = child:GetAttribute("Index"),
			} :: any)
		end
	end
	table.sort(wheels, function(a: any, b: any)
		return (a.index or 0) < (b.index or 0)
	end)
	return wheels
end

function CarPhysics.new(chassis: BasePart, wheels: { Wheel }, stats: EffectiveStats, model: Model?): Sim
	local self = setmetatable({
		chassis = chassis,
		model = model,
		stats = stats,
		wheels = wheels,
		steer = 0,
		nitro = 1,
		nitroActive = false,
		airTime = 0,
		telemetry = {
			speed = 0,
			forwardSpeed = 0,
			gear = 1,
			rpm = 0,
			nitro = 1,
			nitroActive = false,
			drifting = false,
			driftAngle = 0,
			airborne = false,
			airTime = 0,
			grounded = 0,
			surface = "Default",
			braking = false,
			slipping = false,
		},
		raycast = nil :: any,
		rayParams = nil,
		inertiaLocal = Vector3.one,
	}, CarPhysics)

	if model then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		params.IgnoreWater = true
		params.RespectCanCollide = true
		params.CollisionGroup = "WheelRays"
		self.rayParams = params
		self.raycast = function(origin: Vector3, direction: Vector3)
			return workspace:Raycast(origin, direction, params)
		end
	end
	self:refreshInertia()
	return self
end

-- Inertia of the chassis box (the only part with mass) in chassis space.
function CarPhysics.refreshInertia(self: Sim)
	local s = self.chassis.Size
	local m = 1 / 12
	self.inertiaLocal = Vector3.new(m * (s.Y * s.Y + s.Z * s.Z), m * (s.X * s.X + s.Z * s.Z), m * (s.X * s.X + s.Y * s.Y))
end

-- Excludes extra instances (e.g. the driver's character) from wheel rays.
function CarPhysics.setIgnoreList(self: Sim, list: { Instance })
	if self.rayParams then
		self.rayParams.FilterDescendantsInstances = list
	end
end

local function curve(x: number): number
	if x >= 1 then
		return 0
	end
	if x <= 0 then
		return 1
	end
	return 1 - x * x
end

function CarPhysics.step(self: Sim, dtRaw: number, input: Input)
	local chassis = self.chassis
	local dt = math.clamp(dtRaw, 1 / 240, 1 / 20)
	local st = self.stats
	local wheels = self.wheels
	local n = #wheels
	if n == 0 then
		return
	end

	local cf = chassis.CFrame
	local up = cf.UpVector
	local look = cf.LookVector
	local right = cf.RightVector
	local mass = chassis.AssemblyMass
	local com = chassis.AssemblyCenterOfMass
	local vel = chassis.AssemblyLinearVelocity
	local angVel = chassis.AssemblyAngularVelocity
	local gravity = workspace.Gravity
	local gravityVec = Vector3.new(0, -gravity, 0)

	local mShare = mass / n
	local omega = 2 * math.pi * st.suspFreq
	local springK = mShare * omega * omega
	local damperC = 2 * st.suspDamping * mShare * omega
	local rest = st.suspRest

	local fwdSpeed = vel:Dot(look)
	local speed = vel.Magnitude
	local maxSpeed = math.max(st.maxSpeed, 1)

	-- inverse inertia (world) and effective mass at a point
	local invI = Vector3.new(
		1 / (self.inertiaLocal.X * mass),
		1 / (self.inertiaLocal.Y * mass),
		1 / (self.inertiaLocal.Z * mass)
	)
	local function invInertia(v: Vector3): Vector3
		return cf:VectorToWorldSpace(cf:VectorToObjectSpace(v) * invI)
	end
	local function effMass(r: Vector3, dir: Vector3): number
		local rn = r:Cross(dir)
		return 1 / (1 / mass + rn:Dot(invInertia(rn)))
	end

	-- 1) suspension rays (once per frame)
	local grounded = 0
	local drivenGrounded = 0
	local rearCount = 0
	for _, w in wheels do
		local mount = cf:PointToWorldSpace(w.mount)
		local hit = self.raycast(mount, -up * (rest + w.radius))
		if hit then
			w.grounded = true
			w.springLen = math.clamp(hit.Distance - w.radius, 0, rest)
			w.contact = hit.Position
			w.normal = hit.Normal
			w.material = hit.Material
			grounded += 1
			if w.drive then
				drivenGrounded += 1
			end
		else
			w.grounded = false
			w.springLen = moveTowards(w.springLen, rest, dt * 12)
			w.material = nil
			w.load = 0
		end
		if not w.steer then
			rearCount += 1
		end
	end

	-- 2) driver input
	local throttle = math.clamp(input.throttle, -1, 1)
	local steerInput = math.clamp(input.steer, -1, 1)
	local speedFrac = math.clamp(math.abs(fwdSpeed) / maxSpeed, 0, 1)
	local maxSteer = math.rad(st.steer) * (1 - (1 - P.HighSpeedSteer) * speedFrac)
	local target = steerInput * maxSteer
	local rate = if math.abs(target) < math.abs(self.steer) then P.SteerReturnRate else P.SteerRate
	self.steer = moveTowards(self.steer, target, rate * dt)

	local wantsNitro = input.nitro and throttle > 0.1 and not input.parked
	if wantsNitro and self.nitro > 0.01 then
		self.nitroActive = true
		self.nitro = math.max(0, self.nitro - P.NitroDrain * dt)
	else
		self.nitroActive = false
		self.nitro = math.min(1, self.nitro + P.NitroRecharge * st.nitroRecharge * dt)
	end
	local boost = if self.nitroActive then st.nitroPower else 0
	local vmax = maxSpeed * (1 + P.NitroSpeedBonus * boost)
	local accel = st.accel * (1 + P.NitroAccelBonus * boost)

	local driveAccel = 0
	local brakeAmount = 0
	if input.parked then
		brakeAmount = 1
	elseif throttle > 0.05 then
		if fwdSpeed < -1.5 then
			brakeAmount = throttle
		else
			driveAccel = accel * throttle * curve(fwdSpeed / vmax)
		end
	elseif throttle < -0.05 then
		if fwdSpeed > 1.5 then
			brakeAmount = -throttle
		else
			driveAccel = accel * 0.7 * throttle * curve(-fwdSpeed / (vmax * P.ReverseShare))
		end
	end
	local handbrake = input.handbrake or input.parked == true

	-- body slip (drift) and assisted wheel angle
	local planarVel = vel - up * vel:Dot(up)
	local planarSpeed = planarVel.Magnitude
	local bodySlip = 0
	local wheelAngle = self.steer
	if planarSpeed > 5 then
		local vRight, vLook = planarVel:Dot(right), planarVel:Dot(look)
		bodySlip = math.deg(math.atan2(math.abs(vRight), math.max(math.abs(vLook), 1e-3)))
		if vLook > 5 and grounded > 0 and not input.parked then
			-- auto counter-steer: while sliding, the front wheels follow the direction of travel
			local signedSlip = math.atan2(vRight, vLook)
			local assist = P.CounterSteer * math.clamp((bodySlip - 6) / 14, 0, 1)
			local limit = math.rad(st.steer) + math.rad(15)
			wheelAngle = math.clamp(self.steer + signedSlip * assist, -limit, limit)
		end
	end
	local steerRot = CFrame.fromAxisAngle(up, -wheelAngle)

	local driftLoss = 0
	if throttle > 0 and speed > 25 then
		driftLoss = st.drift * 0.45 * math.abs(steerInput) * throttle * math.clamp((speed - 25) / 40, 0, 1)
	end
	-- the rear regains grip as the slide gets too wide, so slides settle at a
	-- controllable angle instead of spinning the car around
	local recover = math.clamp((bodySlip - P.DriftMaxAngle) / 20, 0, 1)
	local hbGrip = 0.55 - 0.37 * st.drift

	-- per-wheel constants for this frame
	local surfaceName = "Default"
	for _, w in wheels do
		w.steerAngle = if w.steer then wheelAngle else 0
		w.slipping = false
		if not w.grounded then
			continue
		end
		local wheelLook = if w.steer then steerRot:VectorToWorldSpace(look) else look
		local normal = w.normal
		local fwd = wheelLook - normal * wheelLook:Dot(normal)
		if fwd.Magnitude < 1e-3 then
			fwd = look
		end
		fwd = fwd.Unit
		local side = fwd:Cross(normal)
		local r = w.contact - com
		local tirePoint = w.contact + up * ((com - w.contact):Dot(up) * P.AntiRoll)
		local rt = tirePoint - com
		local surface = surfaceOf(w.material)
		local surfaceGrip = 1 - (1 - surface.grip) * (1 - st.offroad * 0.85)
		if surface.grip > 1 then
			surfaceGrip = surface.grip
		end
		if w.material then
			surfaceName = w.material.Name
		end
		local latGrip = 1
		if not w.steer then
			if handbrake then
				latGrip = hbGrip
			end
			latGrip *= 1 - driftLoss
			latGrip += (1 - latGrip) * recover
		end
		local stopForce = 0
		if brakeAmount > 0 then
			stopForce += st.brake * brakeAmount * mass / grounded
		elseif driveAccel == 0 then
			stopForce += P.CoastDecel * mass / grounded
		end
		if input.parked then
			stopForce += st.brake * mass / grounded
		elseif handbrake and not w.steer then
			-- a light lock at speed (to start slides), a firm one when crawling
			local lock = if planarSpeed > 20 then 0.15 else 0.8
			stopForce += st.brake * lock * mass / math.max(rearCount, 1)
		end
		stopForce += surface.drag * (1 - st.offroad) * mass / grounded
		local driveForce = 0
		if w.drive and drivenGrounded > 0 and driveAccel ~= 0 and not (handbrake and not w.steer) then
			driveForce = driveAccel * mass / drivenGrounded
		end
		local cache = w :: any
		cache._fwd = fwd
		cache._side = side
		cache._r = r
		cache._rt = rt
		cache._mUp = effMass(r, up)
		cache._mSide = effMass(rt, side)
		cache._mFwd = effMass(rt, fwd)
		cache._gripLimit = st.grip * surfaceGrip
		cache._latGrip = latGrip
		cache._stop = stopForce
		cache._drive = driveForce
		cache._len = w.springLen
	end

	-- 3) wheel forces, integrated internally at ~240 Hz so the result does not
	-- depend on the client's frame rate. The engine receives the sum once.
	local steps = math.clamp(math.floor(dt * 240 + 0.5), 1, 12)
	local h = dt / steps
	local latRate = 1 - (1 - P.LateralGripRate) ^ (h * 60)
	local linImpulse = Vector3.zero
	local angImpulse = Vector3.zero
	local tireSum = Vector3.zero
	local anySlip = false
	local pVel, pAng = vel, angVel
	local gStep = math.max(grounded, 1)

	for _ = 1, steps do
		local stepLin = Vector3.zero
		local stepAng = Vector3.zero
		for _, w in wheels do
			if not w.grounded then
				continue
			end
			local c = w :: any
			local r: Vector3 = c._r
			local rt: Vector3 = c._rt
			local pointVel = pVel + pAng:Cross(r)

			-- suspension
			local len: number = c._len
			local vUp = pointVel:Dot(up)
			local compression = rest - len
			local damper = damperC * vUp
			local maxDamper = math.abs(vUp) * c._mUp * 0.9 / (gStep * h)
			if math.abs(damper) > maxDamper then
				damper = math.sign(damper) * maxDamper
			end
			local springF = springK * compression - damper
			if springF < 0 then
				springF = 0
			end
			local suspImpulse = up * (springF * h)
			if len <= 0.02 and vUp < 0 then
				-- bump stop: never let the wheel sink through the body
				suspImpulse += up * (-vUp * c._mUp / gStep)
			end
			w.load = springF

			-- tires
			local fwd: Vector3 = c._fwd
			local side: Vector3 = c._side
			local tireVel = pVel + pAng:Cross(rt)
			local vF = tireVel:Dot(fwd)
			local vS = tireVel:Dot(side)
			local limit = c._gripLimit * springF
			local fLat = -vS * c._mSide * latRate / (gStep * h)
			local fLong = c._drive
			local stop = c._stop
			if stop > 0 then
				local maxStop = math.abs(vF) * c._mFwd / (gStep * h)
				fLong -= math.sign(vF) * math.min(stop, maxStop)
			end
			local latLimit = limit * c._latGrip
			local longLimit = limit * 1.05
			local fLatC = math.clamp(fLat, -latLimit, latLimit)
			local fLongC = math.clamp(fLong, -longLimit, longLimit)
			local combined = math.sqrt((fLatC / math.max(latLimit, 1e-6)) ^ 2 + (fLongC / math.max(longLimit, 1e-6)) ^ 2)
			if combined > 1 then
				fLatC /= combined
				fLongC /= combined
			end
			if math.abs(fLat) > latLimit * 1.02 or math.abs(fLong) > longLimit * 1.02 then
				w.slipping = true
				anySlip = true
			end
			local tireImpulse = (side * fLatC + fwd * fLongC) * h
			stepLin += suspImpulse + tireImpulse
			stepAng += r:Cross(suspImpulse) + rt:Cross(tireImpulse)
			tireSum += tireImpulse

			-- predicted spring length for the next sub step
			c._len = math.clamp(len + vUp * h, 0, rest)
		end
		linImpulse += stepLin
		angImpulse += stepAng
		pVel += stepLin / mass + gravityVec * h
		pAng += invInertia(stepAng)
	end

	-- visual wheel spin
	for _, w in wheels do
		local c = w :: any
		local vF = if w.grounded then (vel + angVel:Cross(c._rt)):Dot(c._fwd) else 0
		if not w.grounded then
			if w.drive and math.abs(throttle) > 0.05 and not handbrake then
				w.spin += throttle * 30 * dt
			end
		elseif handbrake and not w.steer then
			-- locked
		elseif w.slipping and w.drive and driveAccel ~= 0 then
			w.spin += (vF + math.sign(driveAccel) * 25) / w.radius * dt
		else
			w.spin += vF / w.radius * dt
		end
	end

	-- 4) holding still, drifting, aero, air control
	local hold = input.parked or (math.abs(throttle) < 0.05 and planarSpeed < 2.5)
	if hold and grounded >= 3 then
		-- static friction: cancel gravity along the ground and any creeping
		local nSum = Vector3.zero
		for _, w in wheels do
			if w.grounded then
				nSum += w.normal
			end
		end
		local nrm = nSum.Unit
		local gTan = gravityVec - nrm * gravityVec:Dot(nrm)
		local holdLimit = st.grip * gravity * nrm.Y
		if gTan.Magnitude <= holdLimit then
			-- aim for a velocity that gravity brings back to zero halfway through the step
			local vAfter = vel + linImpulse / mass
			local vTan = vAfter - nrm * vAfter:Dot(nrm)
			local targetVel = -gTan * (dt * 0.5)
			linImpulse += (targetVel - vTan) * mass
		end
	end
	if grounded >= 2 and bodySlip > 10 and planarSpeed > 15 and not input.parked then
		-- sliding tires scrub off a lot of speed; give most of it back so drifts flow
		local dir = planarVel.Unit
		local along = tireSum:Dot(dir)
		if along < 0 then
			local keep = P.DriftScrubKeep * math.clamp((bodySlip - 10) / 20, 0, 1)
			linImpulse += dir * (-along * keep)
		end
	end
	if grounded >= 2 and bodySlip > 8 and throttle > 0 and planarSpeed < vmax * 0.92 and planarSpeed > 10 then
		-- keep momentum through slides
		local keep = math.clamp(bodySlip / 30, 0, 1) * throttle
		linImpulse += planarVel.Unit * (st.accel * P.DriftThrust * keep * mass * dt)
	end
	if grounded >= 2 then
		-- yaw limiter: arcade cars never spin faster than this
		local yawRate = angVel:Dot(up)
		if math.abs(yawRate) > P.MaxYawRate then
			local excess = (math.abs(yawRate) - P.MaxYawRate) * math.sign(yawRate)
			local Iy = self.inertiaLocal.Y * mass
			angImpulse -= up * (excess * (1 - 0.2 ^ (dt * 60)) * Iy)
		end
		local df = P.DownforceG * gravity * (speed / maxSpeed) ^ 2 * mass
		linImpulse += -up * (df * dt)
	end
	local worldUp = Vector3.yAxis
	local I = self.inertiaLocal * mass
	if grounded == 0 then
		self.airTime += dt
		local levelAxis = up:Cross(worldUp)
		local desired = levelAxis * P.AirLevelling
		if not input.parked then
			desired += right * (-throttle * P.AirControl) + up * (-steerInput * P.AirControl)
		end
		-- damp pitch/roll spin a little
		local spinNoYaw = angVel - up * angVel:Dot(up)
		desired -= spinNoYaw * 0.6
		angImpulse += cf:VectorToWorldSpace(cf:VectorToObjectSpace(desired * dt) * I)
	else
		self.airTime = 0
		-- gently pull a car lying on its side back to its wheels at low speed
		if up.Y < 0.3 and speed < 8 then
			local axis = up:Cross(worldUp)
			angImpulse += cf:VectorToWorldSpace(cf:VectorToObjectSpace(axis * (3 * dt)) * I)
		end
	end

	-- clamp crazy spins (after collisions)
	local predicted = angVel + invInertia(angImpulse)
	local predictedSpeed = predicted.Magnitude
	if predictedSpeed > P.MaxAngularSpeed then
		local excess = predicted * (1 - P.MaxAngularSpeed / predictedSpeed)
		angImpulse -= cf:VectorToWorldSpace(cf:VectorToObjectSpace(excess) * I)
	end

	chassis:ApplyImpulse(linImpulse)
	chassis:ApplyAngularImpulse(angImpulse)

	-- 5) telemetry
	local t = self.telemetry
	t.speed = speed
	t.forwardSpeed = fwdSpeed
	t.grounded = grounded
	t.airborne = grounded == 0
	t.airTime = self.airTime
	t.nitro = self.nitro
	t.nitroActive = self.nitroActive
	t.braking = brakeAmount > 0 or (handbrake and not input.parked)
	t.slipping = anySlip
	t.surface = surfaceName
	t.driftAngle = bodySlip
	t.drifting = grounded >= 2 and planarSpeed > P.DriftMinSpeed and bodySlip > P.DriftSlipAngle and bodySlip < 110
	if t.drifting then
		self.nitro = math.min(1, self.nitro + P.NitroDriftRecharge * dt)
	elseif grounded == 0 and self.airTime > 0.3 then
		self.nitro = math.min(1, self.nitro + P.NitroAirRecharge * dt)
	end
	local frac = math.clamp(math.abs(fwdSpeed) / vmax, 0, 1)
	local gear = 1
	for i = #GEAR_STARTS, 1, -1 do
		if frac >= GEAR_STARTS[i] then
			gear = i
			break
		end
	end
	local gStart = GEAR_STARTS[gear]
	local gEnd = GEAR_STARTS[gear + 1] or 1.05
	local within = math.clamp((frac - gStart) / (gEnd - gStart), 0, 1)
	local rpm = 0.22 + 0.78 * within
	if fwdSpeed < -1 then
		gear = 0 -- reverse
		rpm = 0.25 + 0.6 * math.clamp(-fwdSpeed / (vmax * P.ReverseShare), 0, 1)
	end
	if t.slipping and driveAccel ~= 0 then
		rpm = math.min(1, rpm + 0.25)
	end
	t.gear = gear
	t.rpm = t.rpm + (rpm - t.rpm) * math.clamp(dt * 10, 0, 1)
end

-- Positions the visual wheels (Motor6D.Transform) from the current wheel state.
function CarPhysics.updateVisuals(self: Sim)
	for _, w in self.wheels do
		local motor = w.motor
		if motor then
			local offset = w.staticLen - w.springLen
			motor.Transform = CFrame.new(0, offset, 0) * CFrame.Angles(0, -w.steerAngle, 0) * CFrame.Angles(-w.spin, 0, 0)
		end
	end
end

return CarPhysics
