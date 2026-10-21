-- Races: solo time trials on every track. The server teleports the car to the
-- start, runs the countdown, detects checkpoint crossings (plane crossing, so
-- it works at any speed), validates timing and pays medals and records.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)

local Leaderboards = require(script.Parent.Leaderboards)
local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)
local World = require(script.Parent.World)

local Races = {}

type Race = {
	trackId: string,
	phase: "countdown" | "racing",
	startClock: number,
	nextIndex: number,
	lap: number,
	lastCpClock: number,
	lastPos: Vector3?,
	outOfCarSince: number?,
	car: Model,
	token: number,
}

local races: { [Player]: Race } = {}
local tokens = 0

local MEDALS = { "Gold", "Silver", "Bronze" }

local function send(player: Player, payload: { [string]: any })
	Net.fire(player, "RaceState", payload)
end

local function unfreeze(race: Race, player: Player)
	local chassis = race.car.PrimaryPart
	if chassis and chassis.Parent then
		chassis.Anchored = false
		Vehicles.setOwner(race.car, player)
	end
end

function Races.cancel(player: Player, reason: string?)
	local race = races[player]
	if not race then
		return
	end
	races[player] = nil
	unfreeze(race, player)
	send(player, { phase = "cancelled", reason = reason or "RaceCancelled" })
end

function Races.isRacing(player: Player): boolean
	return races[player] ~= nil
end

local function checkpointPayload(trackId: string)
	local data = World.getTrack(trackId)
	if not data then
		return {}
	end
	local list = {}
	for _, cp in data.checkpoints do
		table.insert(list, { cf = cp.cf, width = cp.width })
	end
	return list
end

function Races.begin(player: Player, trackId: any)
	local track = World.getTrack(trackId)
	if not track then
		return { ok = false }
	end
	local car = Vehicles.getCar(player)
	if not car then
		return { ok = false, message = "NeedCar" }
	end
	if not Vehicles.isDriving(player) then
		return { ok = false, message = "MustDrive" }
	end
	if races[player] then
		Races.cancel(player, "RaceCancelled")
	end
	local data = PlayerData.get(player)
	if not data then
		return { ok = false }
	end

	-- move to the start and hold the car during the countdown
	Vehicles.placeAt(car, track.start)
	local chassis = car.PrimaryPart :: BasePart
	chassis.Anchored = true
	tokens += 1
	local race: Race = {
		trackId = track.id,
		phase = "countdown",
		startClock = 0,
		nextIndex = 1,
		lap = 1,
		lastCpClock = 0,
		lastPos = nil,
		outOfCarSince = nil,
		car = car,
		token = tokens,
	}
	races[player] = race
	local countdown = Config.Races.CountdownSeconds
	send(player, {
		phase = "countdown",
		trackId = track.id,
		goAt = workspace:GetServerTimeNow() + countdown,
		checkpoints = checkpointPayload(track.id),
		laps = track.laps,
		medals = track.medals,
		best = data.bestTimes[track.id],
	})
	local token = race.token
	task.delay(countdown, function()
		local current = races[player]
		if not current or current.token ~= token then
			return
		end
		unfreeze(current, player)
		current.phase = "racing"
		current.startClock = os.clock()
		current.lastCpClock = current.startClock
		current.lastPos = chassis.Position
		send(player, { phase = "racing", nextIndex = 1, lap = 1 })
	end)
	return { ok = true }
end

local function medalFor(seconds: number, medals): string?
	for _, m in MEDALS do
		if seconds <= medals[string.lower(m)] then
			return m
		end
	end
	return nil
end

local function finish(player: Player, race: Race)
	races[player] = nil
	local track = World.getTrack(race.trackId)
	local data = PlayerData.get(player)
	if not track or not data then
		return
	end
	local seconds = os.clock() - race.startClock
	local medal = medalFor(seconds, track.medals)
	local previousBest = data.bestTimes[race.trackId]
	local newRecord = previousBest == nil or seconds < previousBest

	-- rewards: base + medal (full the first time a medal tier is reached)
	local reward = Config.Races.FinishReward
	local medalRank = { Gold = 3, Silver = 2, Bronze = 1 }
	local prevMedal = data.medals[race.trackId]
	if medal then
		local full = (Config.Races.MedalRewards :: any)[medal] :: number
		local firstTime = prevMedal == nil or (medalRank[medal] or 0) > (medalRank[prevMedal] or 0)
		reward += if firstTime then full else math.floor(full * Config.Races.RepeatMedalShare)
	end
	-- longer tracks pay more
	reward = math.floor(reward * math.clamp(track.length / 3000, 0.7, 2.5))

	PlayerData.update(player, function(p)
		p.stats.races += 1
		if newRecord then
			p.bestTimes[race.trackId] = seconds
		end
		if medal and (prevMedal == nil or medalRank[medal] > (medalRank[prevMedal] or 0)) then
			p.medals[race.trackId] = medal
		end
	end)
	PlayerData.addCash(player, reward, "race")
	if newRecord then
		Leaderboards.submitTime(player, race.trackId, seconds)
	end
	send(player, {
		phase = "finished",
		trackId = race.trackId,
		time = seconds,
		medal = medal,
		reward = reward,
		newRecord = newRecord,
		best = if newRecord then seconds else previousBest,
		timeText = Format.time(seconds),
	})
end

-- Did the car cross the checkpoint plane between two positions?
local function crossed(cp, a: Vector3, b: Vector3): boolean
	local la = cp.cf:PointToObjectSpace(a)
	local lb = cp.cf:PointToObjectSpace(b)
	-- gates look along the track: behind = +Z, ahead = -Z
	if not (la.Z > 0 and lb.Z <= 0) then
		return false
	end
	local t = la.Z / (la.Z - lb.Z)
	local hit = la:Lerp(lb, t)
	return math.abs(hit.X) <= cp.width / 2 + 8 and hit.Y > -12 and hit.Y < 40
end

local function tick()
	local now = os.clock()
	for player, race in races do
		if race.phase ~= "racing" then
			continue
		end
		local car = race.car
		local chassis = car.PrimaryPart
		if not car.Parent or not chassis then
			Races.cancel(player, "RaceCancelled")
			continue
		end
		if not Vehicles.isDriving(player) then
			race.outOfCarSince = race.outOfCarSince or now
			if now - race.outOfCarSince > 3 then
				Races.cancel(player, "RaceLeftCar")
			end
			continue
		end
		race.outOfCarSince = nil
		if now - race.lastCpClock > Config.Races.CheckpointTimeout then
			Races.cancel(player, "RaceTimeout")
			continue
		end
		local track = World.getTrack(race.trackId)
		if not track then
			continue
		end
		local pos = chassis.Position
		local prev = race.lastPos or pos
		race.lastPos = pos
		local cp = track.checkpoints[race.nextIndex]
		if cp and crossed(cp, prev, pos) then
			-- sanity: the car can't have covered the distance faster than its top speed allows
			local prevCp = track.checkpoints[race.nextIndex - 1]
			local from = if prevCp then prevCp.cf.Position else track.start.Position
			local dist = (cp.cf.Position - from).Magnitude
			local maxSpeed = (car:GetAttribute("MaxSpeed") or 200) * 1.75
			if now - race.lastCpClock < dist / maxSpeed - 0.3 then
				Races.cancel(player, "RaceInvalid")
				continue
			end
			race.lastCpClock = now
			race.nextIndex += 1
			if race.nextIndex > #track.checkpoints then
				if race.lap >= track.laps then
					finish(player, race)
					continue
				end
				race.lap += 1
				race.nextIndex = 1
			end
			send(player, { phase = "racing", nextIndex = race.nextIndex, lap = race.lap, split = now - race.startClock })
		end
	end
end

function Races.init()
	Net.handle("StartRace", function(player, trackId)
		return Races.begin(player, trackId)
	end)
	Net.handle("LeaveRace", function(player)
		Races.cancel(player, "RaceCancelled")
		return { ok = true }
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local trackId = prompt:GetAttribute("TrackId")
		if typeof(trackId) ~= "string" then
			return
		end
		local result = Races.begin(player, trackId)
		if not result.ok and result.message then
			Net.notify(player, result.message, result.args, "warning")
		end
	end)
	Vehicles.Despawned:Connect(function(player)
		Races.cancel(player, "RaceCancelled")
	end)
	Players.PlayerRemoving:Connect(function(player)
		races[player] = nil
	end)
end

function Races.start()
	task.spawn(function()
		while true do
			task.wait(0.05)
			local ok, err = pcall(tick)
			if not ok then
				warn("[Races] " .. tostring(err))
			end
		end
	end)
end

return Races
