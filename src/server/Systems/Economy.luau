-- Economy: server-side scoring of driving. Pays for distance, drifts and air
-- time, and runs the highway speed trap. Everything is measured on the server
-- from the replicated car state, with sanity caps against teleports.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local Leaderboards = require(script.Parent.Leaderboards)
local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)
local World = require(script.Parent.World)

local Economy = {}

local TICK = 0.1
local E = Config.Earnings
local P = Config.Physics

type Track = {
	lastPos: Vector3?,
	distance: number, -- unpaid distance
	sincePayout: number,
	driftTime: number,
	driftGrace: number,
	driftSpeedSum: number,
	airTime: number,
	window: { { t: number, amount: number } }, -- payouts in the last minute
	lastTrapX: number?,
}

local tracking: { [Player]: Track } = {}

local function state(player: Player): Track
	local s = tracking[player]
	if not s then
		s = {
			lastPos = nil,
			distance = 0,
			sincePayout = 0,
			driftTime = 0,
			driftGrace = 0,
			driftSpeedSum = 0,
			airTime = 0,
			window = {},
			lastTrapX = nil,
		}
		tracking[player] = s
	end
	return s
end

-- Pays `amount`, respecting the per-minute cap. Returns what was actually paid.
local function pay(player: Player, s: Track, amount: number, kind: string, detail: any): number
	local now = os.clock()
	local recent = 0
	for i = #s.window, 1, -1 do
		if now - s.window[i].t > 60 then
			table.remove(s.window, i)
		else
			recent += s.window[i].amount
		end
	end
	local allowed = math.max(0, math.min(math.floor(amount), E.MaxPerMinute - recent))
	if allowed <= 0 then
		return 0
	end
	table.insert(s.window, { t = now, amount = allowed })
	PlayerData.addCash(player, allowed, kind)
	Net.fire(player, "Reward", kind, allowed, detail)
	return allowed
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.CollisionGroup = "WheelRays"
groundParams.IgnoreWater = true

local function isGrounded(car: Model, chassis: BasePart): boolean
	groundParams.FilterDescendantsInstances = { car }
	local reach = (car:GetAttribute("SuspRest") or 1.5) + 4.5
	local hit = workspace:Raycast(chassis.Position, -chassis.CFrame.UpVector * reach, groundParams)
	return hit ~= nil
end

local function speedTrap(player: Player, s: Track, pos: Vector3, vel: Vector3)
	local st = World.Layout.SpeedTrap
	local lastX = s.lastTrapX
	s.lastTrapX = pos.X
	if not lastX or math.abs(pos.Z - st.z) > st.halfWidth then
		return
	end
	if (lastX < st.x) == (pos.X < st.x) then
		return
	end
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local kmh = Format.speed(speed)
	for _, label in CollectionService:GetTagged("SpeedTrapReadout") do
		if label:IsA("TextLabel") then
			label.Text = string.format("%s  %d", player.DisplayName, kmh)
		end
	end
	local old = data.topSpeed
	if speed <= old then
		Net.notify(player, "SpeedTrapNoReward", { kmh }, "info")
		return
	end
	PlayerData.update(player, function(p)
		p.topSpeed = speed
	end)
	Leaderboards.submitSpeed(player, speed)
	-- one-time rewards for each threshold beaten for the first time
	local reward = 0
	for i, threshold in E.SpeedTrapThresholds do
		if speed >= threshold and old < threshold then
			reward += E.SpeedTrapRewards[i]
		end
	end
	if reward > 0 then
		PlayerData.addCash(player, reward, "speedtrap")
		Net.fire(player, "Reward", "speedtrap", reward, kmh)
	else
		Net.notify(player, "RewardSpeedTrap", { kmh }, "success")
	end
end

local function tickPlayer(player: Player, s: Track, dt: number)
	local car = Vehicles.getCar(player)
	if not car or not Vehicles.isDriving(player) then
		s.lastPos = nil
		s.driftTime, s.airTime = 0, 0
		return
	end
	local chassis = car.PrimaryPart
	if not chassis or chassis.Anchored then
		s.lastPos = nil
		return
	end
	local pos = chassis.Position
	local vel = chassis.AssemblyLinearVelocity
	local maxSpeed = (car:GetAttribute("MaxSpeed") or 150) * 1.6
	local zone, mult = World.zoneAt(pos)

	-- distance
	if s.lastPos then
		local delta = Vector3.new(pos.X - s.lastPos.X, 0, pos.Z - s.lastPos.Z).Magnitude
		local speed = delta / dt
		if speed <= maxSpeed and speed >= E.MinSpeed then
			s.distance += delta
		end
	end
	s.lastPos = pos

	-- speed trap
	speedTrap(player, s, pos, vel)

	-- drift / air
	local grounded = isGrounded(car, chassis)
	local up = chassis.CFrame.UpVector
	local planar = vel - up * vel:Dot(up)
	local speed = planar.Magnitude
	local slip = 0
	if speed > 5 then
		local look = chassis.CFrame.LookVector
		slip = math.deg(math.atan2(math.abs(planar:Dot(chassis.CFrame.RightVector)), math.max(math.abs(planar:Dot(look)), 1e-3)))
	end
	local drifting = grounded and speed > P.DriftMinSpeed and slip > P.DriftSlipAngle and slip < 100 and speed <= maxSpeed
	if drifting then
		s.driftTime += dt
		s.driftSpeedSum += speed * dt
		s.driftGrace = 0.6
	elseif s.driftTime > 0 then
		s.driftGrace -= dt
		if s.driftGrace <= 0 then
			if s.driftTime >= E.DriftMinDuration then
				local avgSpeed = s.driftSpeedSum / s.driftTime
				local speedFactor = math.clamp(avgSpeed / 60, 0.6, 2)
				local zm = if zone == "drift" then mult else 1
				local amount = E.DriftPerSecond * s.driftTime * speedFactor * zm
				pay(player, s, amount, "drift", math.floor(s.driftTime * 10) / 10)
				PlayerData.update(player, function(p)
					p.stats.drifts += 1
				end)
			end
			s.driftTime = 0
			s.driftSpeedSum = 0
		end
	end

	if not grounded and up.Y < 0.2 then
		-- lying on its roof is not air time
		s.airTime = 0
	elseif not grounded then
		s.airTime += dt
	elseif s.airTime > 0 then
		if s.airTime >= E.AirMinDuration then
			local zm = if zone == "stunt" then mult else 1
			local amount = E.AirPerSecond * s.airTime * zm
			local t = s.airTime
			pay(player, s, amount, "air", math.floor(t * 10) / 10)
			PlayerData.update(player, function(p)
				p.stats.airtime += t
			end)
		end
		s.airTime = 0
	end

	-- distance payout
	s.sincePayout += dt
	if s.sincePayout >= E.PayoutInterval then
		s.sincePayout = 0
		local amount = s.distance * E.PerStud
		local dist = s.distance
		s.distance = 0
		if amount >= 1 then
			pay(player, s, amount, "distance", math.floor(dist))
			PlayerData.update(player, function(p)
				p.stats.distance += dist
			end)
		end
	end
end

function Economy.start()
	Players.PlayerRemoving:Connect(function(player)
		tracking[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local dt = math.clamp(now - last, 0.01, 0.5)
			last = now
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, state(player), dt)
				if not ok then
					warn("[Economy] " .. tostring(err))
				end
			end
		end
	end)
end

return Economy
