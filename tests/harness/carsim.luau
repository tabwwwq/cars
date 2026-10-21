-- Tiny rigid-body simulator used by the physics tests and debug scripts.
-- `carsim.new(world)` returns { simulate = fn(def, opts) -> trace }.

local carsim = {}

function carsim.new(world)
	local env = world.env
	local Vector3, CFrame = env.Vector3, env.CFrame
	local CarCatalog = world.require(world.shared.CarCatalog)
	local CarBuilder = world.require(world.shared.CarBuilder)
	local CarPhysics = world.require(world.shared.CarPhysics)

	local function assertTrue(cond, msg)
		if not cond then
			error(msg, 2)
		end
	end

	local GRAVITY = 196.2
	local SUBSTEPS = 4
	local FRAME = 1 / 60

	local function assertTrue(cond, msg)
		if not cond then
			error(msg, 2)
		end
	end

	local function isFinite(v)
		return v == v and v ~= math.huge and v ~= -math.huge
	end

	-- orthonormalize a CFrame rotation
	local function orthonormal(cf)
		local look = cf.LookVector.Unit
		local up = cf.UpVector
		local right = look:Cross(up).Unit
		up = right:Cross(look).Unit
		return CFrame.fromMatrix(cf.Position, right, up, -look)
	end

	-- Ground: list of planes { point, normal } plus optional box ramps (as planes with bounds)
	local function makeGround(kind)
		local planes = {}
		if kind == "slope" then
			local angle = math.rad(18)
			table.insert(planes, { p = Vector3.new(0, 0, 0), n = Vector3.new(0, math.cos(angle), -math.sin(angle)) })
		else
			table.insert(planes, { p = Vector3.new(0, 0, 0), n = Vector3.new(0, 1, 0) })
		end
		local ground = {}
		function ground.height(x, z)
			local best = -math.huge
			for _, pl in planes do
				-- n.x*(x-px) + n.y*(y-py) + n.z*(z-pz) = 0
				local y = pl.p.Y - (pl.n.X * (x - pl.p.X) + pl.n.Z * (z - pl.p.Z)) / pl.n.Y
				best = math.max(best, y)
			end
			return best
		end
		function ground.normal()
			return planes[1].n
		end
		function ground.raycast(origin, dir)
			local best
			for _, pl in planes do
				local denom = dir:Dot(pl.n)
				if denom < -1e-6 then
					local t = (pl.p - origin):Dot(pl.n) / denom
					if t >= 0 and t <= 1 then
						if not best or t < best.t then
							best = { t = t, pl = pl }
						end
					end
				end
			end
			if not best then
				return nil
			end
			return {
				Position = origin + dir * best.t,
				Normal = best.pl.n,
				Distance = dir.Magnitude * best.t,
				Material = env.Enum.Material.Asphalt,
			}
		end
		return ground
	end

	-- Rigid body standing in for the chassis assembly.
	local function makeBody(chassisPart, extraMass)
		local size = chassisPart.Size
		local density = chassisPart.CustomPhysicalProperties.Density
		local mass = size.X * size.Y * size.Z * density + (extraMass or 0)
		local m12 = mass / 12
		-- real assemblies carry a bit more inertia (character, rounding) than the estimate
		local I = Vector3.new(m12 * (size.Y ^ 2 + size.Z ^ 2), m12 * (size.X ^ 2 + size.Z ^ 2), m12 * (size.X ^ 2 + size.Y ^ 2)) * 1.1
		local body = {
			CFrame = chassisPart.CFrame,
			Size = size,
			AssemblyMass = mass,
			AssemblyLinearVelocity = Vector3.zero,
			AssemblyAngularVelocity = Vector3.zero,
			I = I,
		}
		setmetatable(body, {
			__index = function(t, k)
				if k == "AssemblyCenterOfMass" then
					return rawget(t, "CFrame").Position
				end
				return nil
			end,
		})
		function body:invI(v)
			local l = self.CFrame:VectorToObjectSpace(v)
			return self.CFrame:VectorToWorldSpace(Vector3.new(l.X / I.X, l.Y / I.Y, l.Z / I.Z))
		end
		function body:ApplyImpulse(j)
			self.AssemblyLinearVelocity += j / mass
		end
		function body:ApplyAngularImpulse(l)
			self.AssemblyAngularVelocity += self:invI(l)
		end
		function body:applyAt(j, point)
			self.AssemblyLinearVelocity += j / mass
			self.AssemblyAngularVelocity += self:invI((point - self.CFrame.Position):Cross(j))
		end
		return body
	end

	-- Runs a scenario. `control(t, telemetry, body)` returns an input table.
	local function simulate(def, opts)
		local model = CarBuilder.build(def, { preview = true })
		local chassisPart = model.PrimaryPart
		local wheels = CarPhysics.readWheels(model)
		local stats = CarCatalog.getEffectiveStats(def, nil)
		local body = makeBody(chassisPart, 15)
		local ground = makeGround(opts.ground)
		local geo = CarBuilder.measure(def)

		-- start pose
		local startCF = chassisPart.CFrame + Vector3.new(0, opts.drop or 0.5, 0)
		if opts.ground == "slope" then
			local n = ground.normal()
			local look = Vector3.new(0, 0, -1)
			look = (look - n * look:Dot(n)).Unit
			local right = look:Cross(n).Unit
			startCF = CFrame.fromMatrix(Vector3.zero, right, n, -look) * (chassisPart.CFrame + Vector3.new(0, 0.4, 0))
		end
		if opts.yaw then
			startCF = CFrame.Angles(0, opts.yaw, 0) * startCF
		end
		body.CFrame = startCF
		if opts.initialSpeed then
			body.AssemblyLinearVelocity = startCF.LookVector * opts.initialSpeed
		end
		if opts.initialVelocity then
			body.AssemblyLinearVelocity = opts.initialVelocity
		end

		local sim = CarPhysics.new(body :: any, wheels, stats, nil)
		sim.raycast = ground.raycast

		-- hull corners in chassis space for body/ground collisions
		local c0 = chassisPart.CFrame
		local corners = {}
		for _, x in { -geo.W / 2, geo.W / 2 } do
			for _, y in { geo.floor + CarBuilder.HullLift, geo.belt } do
				for _, z in { geo.zF, geo.zR } do
					table.insert(corners, c0:PointToObjectSpace(Vector3.new(x, y, z)))
				end
			end
		end
		local roof = if geo.cabin then geo.cabin.yR else geo.belt + 1
		for _, x in { -geo.W / 2 + 0.5, geo.W / 2 - 0.5 } do
			table.insert(corners, c0:PointToObjectSpace(Vector3.new(x, roof, 0)))
		end

		local trace = { maxTilt = 0, maxSpeed = 0, minUpY = 1, hullHits = 0, history = {} }
		local t = 0
		local duration = opts.duration
		local FRAME = opts.frame or FRAME
		local SUBSTEPS = math.max(1, math.floor(FRAME * 240 + 0.5))
		while t < duration do
			local input = opts.control(t, sim.telemetry, body)
			sim:step(FRAME, input)
			for _ = 1, SUBSTEPS do
				local h = FRAME / SUBSTEPS
				body.AssemblyLinearVelocity += Vector3.new(0, -GRAVITY * h, 0)
				-- hull vs ground
				for _, lc in corners do
					local p = body.CFrame:PointToWorldSpace(lc)
					local gy = ground.height(p.X, p.Z)
					if p.Y < gy then
						trace.hullHits += 1
						local n = ground.normal()
						local r = p - body.CFrame.Position
						local pv = body.AssemblyLinearVelocity + body.AssemblyAngularVelocity:Cross(r)
						local vn = pv:Dot(n)
						if vn < 0 then
							local rn = r:Cross(n)
							local k = 1 / body.AssemblyMass + rn:Dot(body:invI(rn))
							body:applyAt(n * (-vn / k), p)
							-- friction
							local pv2 = body.AssemblyLinearVelocity + body.AssemblyAngularVelocity:Cross(r)
							local vt = pv2 - n * pv2:Dot(n)
							if vt.Magnitude > 1e-3 then
								local dir = vt.Unit
								local rt = r:Cross(dir)
								local kt = 1 / body.AssemblyMass + rt:Dot(body:invI(rt))
								local jt = math.min(vt.Magnitude / kt, 0.4 * (-vn / k))
								body:applyAt(-dir * jt, p)
							end
						end
						body.CFrame = body.CFrame + n * math.min(gy - p.Y, 0.05)
					end
				end
				-- integrate
				body.CFrame = body.CFrame + body.AssemblyLinearVelocity * h
				local w = body.AssemblyAngularVelocity
				local wm = w.Magnitude
				if wm > 1e-9 then
					local rot = CFrame.fromAxisAngle(w / wm, wm * h)
					local pos = body.CFrame.Position
					body.CFrame = orthonormal(CFrame.new(pos) * rot * body.CFrame.Rotation)
				end
			end
			t += FRAME
			local p = body.CFrame.Position
			assertTrue(isFinite(p.X) and isFinite(p.Y) and isFinite(p.Z), def.id .. ": position became NaN")
			table.insert(trace.history, p)
			trace.frame = FRAME
			local up = body.CFrame.UpVector
			trace.minUpY = math.min(trace.minUpY, up.Y)
			trace.maxSpeed = math.max(trace.maxSpeed, body.AssemblyLinearVelocity.Magnitude)
			if opts.observe then
				opts.observe(t, sim, body, trace)
			end
		end
		-- average velocity over the last second (removes per-frame impulse sawtooth)
		function trace.recentVelocity(seconds)
			local fps = 1 / (trace.frame or (1 / 60))
			local frames = math.floor((seconds or 1) * fps + 0.5)
			local h = trace.history
			if #h <= frames then
				return Vector3.zero
			end
			return (h[#h] - h[#h - frames]) / (frames / fps)
		end
		trace.body = body
		trace.sim = sim
		trace.geo = geo
		trace.start = startCF
		return trace
	end

	return { simulate = simulate }
end

return carsim
