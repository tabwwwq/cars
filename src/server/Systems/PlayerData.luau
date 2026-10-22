-- PlayerData: the only module that touches player DataStores.
--
-- * UpdateAsync everywhere, retries with exponential backoff
-- * session lock (JobId + timestamp) so two servers never own one save
-- * autosave (staggered), save on leave and on BindToClose
-- * schema version + migrations + reconcile against the default profile
-- * a failed load kicks the player instead of overwriting real data with a
--   fresh profile (in Studio without API access it runs in session mode)
--
-- Gameplay code reads/writes the in-memory profile through this module only.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Paints = require(Shared.Paints)
local ServiceConfig = require(Shared.ServiceConfig)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

type Profile = Types.Profile

local PlayerData = {}
PlayerData.Loaded = Signal.new() -- (player, profile)
PlayerData.Changed = Signal.new() -- (player, profile)
PlayerData.CashChanged = Signal.new() -- (player, newCash, delta, reason)

local CURRENT_VERSION = 3
local IS_STUDIO = RunService:IsStudio()

type State = {
	data: Profile,
	persistent: boolean, -- false = session only (Studio without API / failed lock)
	released: boolean,
	lastPush: number,
	pushQueued: boolean,
	saving: boolean,
}

local states: { [Player]: State } = {}
local store: DataStore? = nil

--------------------------------------------------------------------------------
-- Profile shape
--------------------------------------------------------------------------------

local function defaultService(): Types.ServiceProfile
	local upgrades = {}
	for _, u in ServiceConfig.Upgrades do
		upgrades[u.id] = 0
	end
	return { level = 1, xp = 0, orders = 0, earned = 0, stars = 0, upgrades = upgrades, tutorial = 0 }
end

local function defaultProfile(): Profile
	local starter = CarCatalog.get(Config.StarterCarId)
	local owned = {}
	local cars = {}
	if starter then
		owned[starter.id] = true
		cars[starter.id] = CarCatalog.defaultSave(starter)
	end
	return {
		version = CURRENT_VERSION,
		cash = Config.StartingCash,
		owned = owned,
		cars = cars,
		selected = Config.StarterCarId,
		bestTimes = {},
		medals = {},
		topSpeed = 0,
		stats = { distance = 0, drifts = 0, airtime = 0, races = 0, earned = 0 },
		daily = { last = 0, streak = 0 },
		finishes = {},
		service = defaultService(),
	}
end
PlayerData.defaultProfile = defaultProfile

local MIGRATIONS: { [number]: (any) -> any } = {
	-- v1 -> v2: medals and owned finishes were added
	[1] = function(data)
		data.medals = data.medals or {}
		data.finishes = data.finishes or {}
		return data
	end,
	-- v2 -> v3: the car-service mode (level, xp, upgrades)
	[2] = function(data)
		data.service = data.service or defaultService()
		return data
	end,
}

local function migrate(data: any): any
	data.version = tonumber(data.version) or 1
	while data.version < CURRENT_VERSION do
		local step = MIGRATIONS[data.version]
		if not step then
			error("missing migration from v" .. tostring(data.version))
		end
		data = step(data)
		data.version += 1
	end
	return data
end

local function num(v: any, default: number, lo: number?, hi: number?): number
	local n = tonumber(v)
	if not n or n ~= n then
		return default
	end
	if lo then
		n = math.max(lo, n)
	end
	if hi then
		n = math.min(hi, n)
	end
	return n
end

-- Fills in missing fields and drops garbage so the rest of the game can trust the shape.
local function reconcile(data: any): Profile
	local base = defaultProfile()
	if typeof(data) ~= "table" then
		return base
	end
	local out = base
	out.version = CURRENT_VERSION
	out.cash = math.floor(num(data.cash, base.cash, 0, 1e12))
	out.topSpeed = num(data.topSpeed, 0, 0, 1e4)
	if typeof(data.owned) == "table" then
		for id, v in data.owned do
			if typeof(id) == "string" and v == true then
				out.owned[id] = true
			end
		end
	end
	if typeof(data.cars) == "table" then
		for id, save in data.cars do
			local def = CarCatalog.get(id)
			if def and typeof(save) == "table" then
				local d = CarCatalog.defaultSave(def)
				d.paint = if Paints.isValidIndex(save.paint) then save.paint else d.paint
				d.accent = if Paints.isValidIndex(save.accent) then save.accent else d.accent
				d.rim = if Paints.isValidIndex(save.rim) then save.rim else d.rim
				d.finish = if Paints.isValidFinish(save.finish) then save.finish else "Gloss"
				d.glow = if save.glow == 0 or Paints.isValidIndex(save.glow) then save.glow else 0
				d.glowOwned = save.glowOwned == true
				d.engine = math.floor(num(save.engine, 0, 0, Config.Upgrades.Engine.MaxLevel))
				d.tires = math.floor(num(save.tires, 0, 0, Config.Upgrades.Tires.MaxLevel))
				d.nitro = math.floor(num(save.nitro, 0, 0, Config.Upgrades.Nitro.MaxLevel))
				out.cars[id] = d
			end
		end
	end
	-- every owned car needs a customization entry
	for id in out.owned do
		local def = CarCatalog.get(id)
		if def and not out.cars[id] then
			out.cars[id] = CarCatalog.defaultSave(def)
		end
	end
	if typeof(data.selected) == "string" and out.owned[data.selected] then
		out.selected = data.selected
	end
	for _, key in { "bestTimes", "medals", "finishes" } do
		local src = data[key]
		if typeof(src) == "table" then
			for k, v in src do
				if typeof(k) == "string" and (typeof(v) == "number" or typeof(v) == "string" or v == true) then
					(out :: any)[key][k] = v
				end
			end
		end
	end
	if typeof(data.stats) == "table" then
		for k, v in out.stats do
			(out.stats :: any)[k] = num(data.stats[k], v, 0)
		end
	end
	if typeof(data.daily) == "table" then
		out.daily.last = num(data.daily.last, 0, 0)
		out.daily.streak = math.floor(num(data.daily.streak, 0, 0, 1000))
	end
	local svc = data.service
	if typeof(svc) == "table" then
		local o = out.service
		o.level = math.floor(num(svc.level, 1, 1, ServiceConfig.MaxLevel))
		o.xp = math.floor(num(svc.xp, 0, 0, 1e9))
		o.orders = math.floor(num(svc.orders, 0, 0))
		o.earned = math.floor(num(svc.earned, 0, 0))
		o.stars = math.floor(num(svc.stars, 0, 0))
		o.tutorial = math.floor(num(svc.tutorial, 0, 0, 100))
		if typeof(svc.upgrades) == "table" then
			for _, u in ServiceConfig.Upgrades do
				o.upgrades[u.id] = math.floor(num(svc.upgrades[u.id], 0, 0, #u.levels))
			end
		end
	end
	return out
end
PlayerData.reconcile = reconcile

--------------------------------------------------------------------------------
-- DataStore helpers
--------------------------------------------------------------------------------

local function withRetry(attempts: number, fn: () -> ()): (boolean, any)
	local delaySeconds = 1
	local lastErr
	for attempt = 1, attempts do
		local ok, err = pcall(fn)
		if ok then
			return true, nil
		end
		lastErr = err
		warn(string.format("[PlayerData] attempt %d/%d failed: %s", attempt, attempts, tostring(err)))
		if attempt < attempts then
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, 16)
		end
	end
	return false, lastErr
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

local function lockIsForeign(lock: any): boolean
	if typeof(lock) ~= "table" then
		return false
	end
	if lock.job == game.JobId then
		return false
	end
	local age = os.time() - (tonumber(lock.time) or 0)
	return age < Config.SessionLockTimeout
end

-- Claims the session lock and returns the stored profile.
-- status: "ok" | "locked" | "newer" | "error"
local function claim(player: Player): (string, Profile?)
	local status = "error"
	local loaded: Profile? = nil
	local ok = withRetry(4, function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old)
			if old ~= nil and lockIsForeign(old.lock) then
				status = "locked"
				return nil -- abort: another server owns this save
			end
			if old ~= nil and (tonumber(old.version) or 0) > CURRENT_VERSION then
				status = "newer"
				return nil -- written by a newer game version: never downgrade it
			end
			local data = if old == nil then defaultProfile() else reconcile(migrate(old))
			loaded = data
			status = "ok"
			local stored = table.clone(data) :: any
			stored.lock = { job = game.JobId, time = os.time() }
			return stored
		end)
	end)
	if not ok then
		return "error", nil
	end
	return status, loaded
end

-- Writes the profile. `release` clears the lock (leave / shutdown).
local function save(player: Player, release: boolean): boolean
	local state = states[player]
	if not state or not state.persistent or not store then
		return true
	end
	if state.saving and not release then
		return true
	end
	state.saving = true
	local snapshot = HttpService:JSONDecode(HttpService:JSONEncode(state.data))
	local lostLock = false
	local ok = withRetry(if release then 5 else 3, function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old)
			if old ~= nil and (lockIsForeign(old.lock) or (tonumber(old.version) or 0) > CURRENT_VERSION) then
				lostLock = true
				return nil
			end
			snapshot.lock = if release then nil else { job = game.JobId, time = os.time() }
			return snapshot
		end)
	end)
	state.saving = false
	if lostLock then
		-- another server took over (e.g. very long lag spike); stop writing to avoid dupes
		warn("[PlayerData] lost session lock for " .. player.Name .. ", disabling saves")
		state.persistent = false
		return false
	end
	return ok
end

--------------------------------------------------------------------------------
-- Client snapshot + leaderstats
--------------------------------------------------------------------------------

function PlayerData.publicSnapshot(data: Profile)
	return {
		cash = data.cash,
		owned = data.owned,
		cars = data.cars,
		selected = data.selected,
		bestTimes = data.bestTimes,
		medals = data.medals,
		topSpeed = data.topSpeed,
		stats = data.stats,
		daily = data.daily,
		finishes = data.finishes,
		service = data.service,
		serverTime = os.time(),
	}
end

local function pushNow(player: Player)
	local state = states[player]
	if not state or not player.Parent then
		return
	end
	state.lastPush = os.clock()
	state.pushQueued = false
	Net.fire(player, "Profile", PlayerData.publicSnapshot(state.data))
end

-- Sends the snapshot at most 4 times per second.
local function queuePush(player: Player)
	local state = states[player]
	if not state or state.pushQueued then
		return
	end
	local wait = 0.25 - (os.clock() - state.lastPush)
	if wait <= 0 then
		pushNow(player)
	else
		state.pushQueued = true
		task.delay(wait, pushNow, player)
	end
end

local function updateLeaderstats(player: Player, data: Profile)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		local cash = Instance.new("IntValue")
		cash.Name = "Cash"
		cash.Parent = ls
		local cars = Instance.new("IntValue")
		cars.Name = "Cars"
		cars.Parent = ls
		ls.Parent = player
	end
	local count = 0
	for _ in data.owned do
		count += 1
	end
	(ls :: any).Cash.Value = math.min(data.cash, 2 ^ 31 - 1);
	(ls :: any).Cars.Value = count
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function PlayerData.get(player: Player): Profile?
	local state = states[player]
	return if state then state.data else nil
end

function PlayerData.isPersistent(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.persistent
end

function PlayerData.waitFor(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local data = PlayerData.get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return PlayerData.get(player)
end

-- Mutates the profile through a callback, then syncs leaderstats and the client.
function PlayerData.update(player: Player, fn: (Profile) -> ())
	local state = states[player]
	if not state then
		return
	end
	fn(state.data)
	updateLeaderstats(player, state.data)
	queuePush(player)
	PlayerData.Changed:Fire(player, state.data)
end

function PlayerData.addCash(player: Player, amount: number, reason: string?): boolean
	local state = states[player]
	if not state or amount ~= amount then
		return false
	end
	amount = math.floor(amount)
	if amount == 0 then
		return true
	end
	PlayerData.update(player, function(data)
		data.cash = math.max(0, data.cash + amount)
		if amount > 0 then
			data.stats.earned += amount
		end
	end)
	PlayerData.CashChanged:Fire(player, state.data.cash, amount, reason)
	return true
end

-- Atomically checks and spends cash. Returns false if the player can't afford it.
function PlayerData.spend(player: Player, amount: number, reason: string?): boolean
	local state = states[player]
	if not state or amount ~= amount or amount < 0 then
		return false
	end
	amount = math.floor(amount)
	if state.data.cash < amount then
		return false
	end
	PlayerData.update(player, function(data)
		data.cash -= amount
	end)
	PlayerData.CashChanged:Fire(player, state.data.cash, -amount, reason)
	return true
end

function PlayerData.reset(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.data = defaultProfile()
	PlayerData.update(player, function() end)
end

function PlayerData.forcePush(player: Player)
	pushNow(player)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local data: Profile? = nil
	local persistent = false
	local message: string? = nil

	if store then
		local status, loaded
		for _ = 1, 5 do
			status, loaded = claim(player)
			if status ~= "locked" then
				break
			end
			-- the previous server may still be releasing the lock
			task.wait(3)
			if not player.Parent then
				return
			end
		end
		if status == "ok" then
			data = loaded
			persistent = true
		elseif IS_STUDIO then
			data = defaultProfile()
			message = "DataStudio"
		else
			player:Kick(
				if status == "locked"
					then "Ваши данные ещё сохраняются на другом сервере. Перезайдите через минуту. / Your data is still saving on another server, please rejoin in a minute."
					elseif status == "newer"
					then "Этот сервер устарел — перезайдите, чтобы попасть на новую версию игры. / This server runs an old version, please rejoin."
					else "Не удалось загрузить сохранение. Перезайдите. / Could not load your save, please rejoin."
			)
			return
		end
	else
		data = defaultProfile()
		message = "DataStudio"
	end

	if not player.Parent then
		-- left while loading: release the lock we just took
		if persistent then
			states[player] = {
				data = data :: Profile,
				persistent = true,
				released = false,
				lastPush = 0,
				pushQueued = false,
				saving = false,
			}
			save(player, true)
			states[player] = nil
		end
		return
	end

	states[player] = {
		data = data :: Profile,
		persistent = persistent,
		released = false,
		lastPush = 0,
		pushQueued = false,
		saving = false,
	}
	updateLeaderstats(player, data :: Profile)
	pushNow(player)
	if message then
		Net.notify(player, message, {}, "warning")
	end
	PlayerData.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if not state or state.released then
		states[player] = nil
		return
	end
	state.released = true
	save(player, true)
	states[player] = nil
end

function PlayerData.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStores unavailable: " .. tostring(result))
		store = nil
	end
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		local pending = 0
		for player, state in states do
			if not state.released then
				state.released = true
				pending += 1
				task.spawn(function()
					save(player, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + (if IS_STUDIO then 3 else 25)
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	-- staggered autosave: each player saves at their own offset within the interval
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.time()
			for player, state in states do
				if state.persistent and not state.released then
					local offset = player.UserId % Config.AutosaveInterval
					if (now + offset) % Config.AutosaveInterval < 5 then
						task.spawn(save, player, false)
					end
				end
			end
		end
	end)
end

return PlayerData
