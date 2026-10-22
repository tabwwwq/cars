-- ServiceConfig: the car-service mode. Customers park at your plot, you take
-- their order, wash / repair / paint the vehicle by hand (mouse or finger) and
-- level up from bicycles to hypercars. Later you buy more bays and hire staff.
--
-- Everything here is plain data plus a few pure helpers, so the server, the
-- client UI and the tests all agree on prices, unlocks and rewards.

local ServiceConfig = {}

ServiceConfig.MaxLevel = 30
ServiceConfig.Plots = 6

-- XP needed to go from `level` to `level + 1`.
function ServiceConfig.xpToNext(level: number): number
	return math.floor(60 * level ^ 1.35)
end

--------------------------------------------------------------------------------
-- Vehicle sizes: drive the minigame (spot count/size, camera) and the timing
--------------------------------------------------------------------------------

export type Size = {
	minStep: number, -- fastest legal step, seconds (server check, divided by tool power)
	par: number, -- "3 stars" seconds per step at tool level 0
	spots: number, -- dirt spots on the body
	spotSize: number, -- spot diameter in studs
	brush: number, -- tool radius in studs at tool level 0
	camera: number, -- orbit distance
	workerStep: number, -- seconds a worker needs per step at training level 0
	speed: number, -- studs/s when driving in and out
}

ServiceConfig.Sizes = {
	tiny = { minStep = 1.75, par = 7, spots = 16, spotSize = 0.75, brush = 0.9, camera = 9, workerStep = 5, speed = 11 },
	small = { minStep = 2.25, par = 9, spots = 20, spotSize = 1.0, brush = 1.2, camera = 12, workerStep = 6, speed = 14 },
	car = { minStep = 3.0, par = 12, spots = 28, spotSize = 1.5, brush = 2.0, camera = 21, workerStep = 8, speed = 18 },
	big = { minStep = 3.75, par = 15, spots = 34, spotSize = 2.1, brush = 2.8, camera = 30, workerStep = 10, speed = 16 },
} :: { [string]: Size }

--------------------------------------------------------------------------------
-- Vehicle tiers (unlocked by level)
--------------------------------------------------------------------------------

export type Tier = {
	id: string,
	level: number,
	icon: string,
	name: { ru: string, en: string },
	size: string,
	reward: number, -- base cash for one service
	xp: number,
	models: { string }?, -- ServiceModels ids
	cars: { string }?, -- CarCatalog ids
}

ServiceConfig.Tiers = {
	{
		id = "bikes",
		level = 1,
		icon = "🚲",
		name = { ru = "Велосипеды", en = "Bicycles" },
		size = "tiny",
		reward = 45,
		xp = 10,
		models = { "citybike", "mtb", "bmx", "roadbike", "kidsbike" },
	},
	{
		id = "scooters",
		level = 2,
		icon = "🛴",
		name = { ru = "Самокаты", en = "Scooters" },
		size = "tiny",
		reward = 60,
		xp = 13,
		models = { "kickscooter", "escooter" },
	},
	{
		id = "mopeds",
		level = 3,
		icon = "🛵",
		name = { ru = "Мопеды", en = "Mopeds" },
		size = "small",
		reward = 95,
		xp = 18,
		models = { "moped", "deliverymoped" },
	},
	{
		id = "moto",
		level = 4,
		icon = "🏍",
		name = { ru = "Мотоциклы", en = "Motorcycles" },
		size = "small",
		reward = 150,
		xp = 25,
		models = { "sportbike", "chopper", "dirtbike", "classicbike" },
	},
	{
		id = "atv",
		level = 5,
		icon = "⛳",
		name = { ru = "Квадроциклы и гольф-кары", en = "Quads & golf carts" },
		size = "small",
		reward = 210,
		xp = 32,
		models = { "quad", "golfcart" },
	},
	{
		id = "compact",
		level = 6,
		icon = "🚗",
		name = { ru = "Городские машины", en = "City cars" },
		size = "car",
		reward = 360,
		xp = 44,
		cars = { "pebble", "dart", "zippy", "cruiser", "taxi" },
	},
	{
		id = "work",
		level = 8,
		icon = "🚚",
		name = { ru = "Рабочие машины", en = "Work vehicles" },
		size = "car",
		reward = 500,
		xp = 58,
		cars = { "courier", "hauler", "frosty", "harvester", "ranger", "sandhopper" },
	},
	{
		id = "sport",
		level = 10,
		icon = "🏎",
		name = { ru = "Спорткары", en = "Sports cars" },
		size = "car",
		reward = 780,
		xp = 78,
		cars = { "stinger", "comet", "kitsune", "thunder", "bandit", "rallyfox", "medic", "interceptor" },
	},
	{
		id = "luxury",
		level = 13,
		icon = "💎",
		name = { ru = "Люкс и суперкары", en = "Luxury & super" },
		size = "car",
		reward = 1300,
		xp = 105,
		cars = { "sunset", "volt", "prestige", "zephyr", "vortex" },
	},
	{
		id = "hyper",
		level = 16,
		icon = "🚀",
		name = { ru = "Гиперкары", en = "Hypercars" },
		size = "car",
		reward = 2400,
		xp = 150,
		cars = { "nebula", "quasar", "apex" },
	},
	{
		id = "heavy",
		level = 19,
		icon = "🚌",
		name = { ru = "Автобусы и грузовики", en = "Buses & trucks" },
		size = "big",
		reward = 2900,
		xp = 185,
		cars = { "metroliner", "titan", "goliath", "blaze" },
	},
} :: { Tier }

local tierById: { [string]: Tier } = {}
for _, t in ServiceConfig.Tiers do
	tierById[t.id] = t
end

function ServiceConfig.getTier(id: any): Tier?
	return if typeof(id) == "string" then tierById[id] else nil
end

--------------------------------------------------------------------------------
-- Services and their hands-on steps
--------------------------------------------------------------------------------

export type Step = {
	id: string,
	icon: string,
	target: "spots" | "damage" | "wheels" | "paint",
	work: number, -- seconds of brushing one spot needs at tool power 1
	color: Color3, -- tool / cursor color
}

ServiceConfig.Steps = {
	wrench = { id = "wrench", icon = "🔧", target = "damage", work = 1.1, color = Color3.fromRGB(255, 170, 60) },
	pump = { id = "pump", icon = "💨", target = "wheels", work = 1.0, color = Color3.fromRGB(120, 200, 255) },
	sand = { id = "sand", icon = "🧤", target = "spots", work = 0.4, color = Color3.fromRGB(230, 190, 120) },
	spray = { id = "spray", icon = "🎨", target = "paint", work = 0.55, color = Color3.fromRGB(255, 110, 200) },
	foam = { id = "foam", icon = "🧼", target = "spots", work = 0.3, color = Color3.fromRGB(240, 246, 255) },
	scrub = { id = "scrub", icon = "🧽", target = "spots", work = 0.4, color = Color3.fromRGB(255, 220, 60) },
	rinse = { id = "rinse", icon = "🚿", target = "spots", work = 0.28, color = Color3.fromRGB(90, 190, 255) },
	dry = { id = "dry", icon = "🧻", target = "spots", work = 0.32, color = Color3.fromRGB(120, 230, 170) },
} :: { [string]: Step }

export type Service = {
	id: string,
	level: number,
	icon: string,
	mult: number, -- reward multiplier
	weight: number, -- how often customers ask for it
	steps: { string },
	color: Color3,
}

-- Listed in the order the steps are done when an order has several services.
ServiceConfig.Services = {
	{
		id = "repair",
		level = 2,
		icon = "🔧",
		mult = 1.3,
		weight = 2,
		steps = { "wrench", "pump" },
		color = Color3.fromRGB(255, 160, 50),
	},
	{
		id = "paint",
		level = 4,
		icon = "🎨",
		mult = 1.7,
		weight = 1.5,
		steps = { "sand", "spray" },
		color = Color3.fromRGB(230, 90, 220),
	},
	{
		id = "wash",
		level = 1,
		icon = "🧽",
		mult = 1.0,
		weight = 3,
		steps = { "foam", "scrub", "rinse", "dry" },
		color = Color3.fromRGB(70, 180, 255),
	},
} :: { Service }

local serviceById: { [string]: Service } = {}
for _, s in ServiceConfig.Services do
	serviceById[s.id] = s
end

function ServiceConfig.getService(id: any): Service?
	return if typeof(id) == "string" then serviceById[id] else nil
end

-- Steps of an order, in work order.
function ServiceConfig.stepsFor(services: { string }): { string }
	local wanted = {}
	for _, id in services do
		wanted[id] = true
	end
	local out = {}
	for _, s in ServiceConfig.Services do
		if wanted[s.id] then
			for _, step in s.steps do
				table.insert(out, step)
			end
		end
	end
	return out
end

-- Which service a step belongs to.
function ServiceConfig.serviceOfStep(stepId: string): string?
	for _, s in ServiceConfig.Services do
		if table.find(s.steps, stepId) then
			return s.id
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Upgrades and staff
--------------------------------------------------------------------------------

export type UpgradeLevel = { price: number, level: number }
export type Upgrade = { id: string, icon: string, levels: { UpgradeLevel } }

ServiceConfig.Upgrades = {
	{
		id = "bays",
		icon = "🏗",
		levels = { { price = 1500, level = 2 }, { price = 9000, level = 5 }, { price = 30000, level = 9 } },
	},
	{
		id = "parking",
		icon = "🅿",
		levels = { { price = 800, level = 1 }, { price = 3500, level = 3 }, { price = 12000, level = 6 } },
	},
	{
		id = "tools",
		icon = "🛠",
		levels = {
			{ price = 600, level = 1 },
			{ price = 2500, level = 3 },
			{ price = 7000, level = 5 },
			{ price = 18000, level = 8 },
			{ price = 45000, level = 12 },
		},
	},
	{
		id = "marketing",
		icon = "📣",
		levels = {
			{ price = 1000, level = 2 },
			{ price = 4000, level = 4 },
			{ price = 11000, level = 7 },
			{ price = 26000, level = 10 },
			{ price = 60000, level = 14 },
		},
	},
	{
		id = "staff",
		icon = "👷",
		levels = { { price = 2500, level = 4 }, { price = 10000, level = 7 }, { price = 35000, level = 11 } },
	},
	{
		id = "training",
		icon = "🎓",
		levels = {
			{ price = 3000, level = 5 },
			{ price = 9000, level = 8 },
			{ price = 20000, level = 11 },
			{ price = 42000, level = 14 },
			{ price = 80000, level = 18 },
		},
	},
} :: { Upgrade }

local upgradeById: { [string]: Upgrade } = {}
for _, u in ServiceConfig.Upgrades do
	upgradeById[u.id] = u
end

function ServiceConfig.getUpgrade(id: any): Upgrade?
	return if typeof(id) == "string" then upgradeById[id] else nil
end

-- The next purchasable level of an upgrade, or nil at max.
function ServiceConfig.nextLevel(id: string, current: number): UpgradeLevel?
	local u = upgradeById[id]
	return if u then u.levels[current + 1] else nil
end

ServiceConfig.BaseBays = 1
ServiceConfig.BaseParking = 3

function ServiceConfig.bayCount(upgrades: { [string]: number }): number
	return ServiceConfig.BaseBays + (upgrades.bays or 0)
end

function ServiceConfig.parkingCount(upgrades: { [string]: number }): number
	return ServiceConfig.BaseParking + (upgrades.parking or 0)
end

function ServiceConfig.toolPower(level: number): number
	return 1 + 0.3 * level
end

function ServiceConfig.toolRadius(level: number): number
	return 1 + 0.12 * level
end

function ServiceConfig.arrivalInterval(marketing: number): number
	return ServiceConfig.ArrivalInterval * 0.82 ^ marketing
end

function ServiceConfig.tipBonus(marketing: number): number
	return 0.05 * marketing
end

function ServiceConfig.workerSpeed(training: number): number
	return 1 + 0.3 * training
end

ServiceConfig.ArrivalInterval = 14 -- seconds between customers (marketing makes it shorter)
ServiceConfig.FirstArrival = 2
ServiceConfig.Patience = 300 -- a waiting customer leaves after this many seconds
ServiceConfig.WorkerShare = 0.7 -- the owner keeps 70% of what a worker earns
ServiceConfig.WorkerXp = 0.5
ServiceConfig.WorkerPickDelay = 8 -- staff only take orders that waited this long (you get first pick)
ServiceConfig.StarTips = { 0, 0.1, 0.25 } -- tip for 1/2/3 stars

ServiceConfig.WorkerNames = {
	{ ru = "Вася", en = "Vasya" },
	{ ru = "Аня", en = "Anya" },
	{ ru = "Дима", en = "Dima" },
	{ ru = "Катя", en = "Katya" },
}

--------------------------------------------------------------------------------
-- Orders
--------------------------------------------------------------------------------

export type Order = {
	tier: string,
	source: "model" | "car",
	vehicle: string,
	services: { string },
	paint: number, -- current body color (palette index)
	target: number?, -- requested color for paint orders
	reward: number,
	xp: number,
}

function ServiceConfig.unlockedTiers(level: number): { Tier }
	local out = {}
	for _, t in ServiceConfig.Tiers do
		if level >= t.level then
			table.insert(out, t)
		end
	end
	return out
end

function ServiceConfig.unlockedServices(level: number): { Service }
	local out = {}
	for _, s in ServiceConfig.Services do
		if level >= s.level then
			table.insert(out, s)
		end
	end
	return out
end

-- What a level unlocks (for the level-up screen).
function ServiceConfig.unlocksAt(level: number): { { kind: string, id: string, icon: string } }
	local out = {}
	for _, t in ServiceConfig.Tiers do
		if t.level == level then
			table.insert(out, { kind = "tier", id = t.id, icon = t.icon })
		end
	end
	for _, s in ServiceConfig.Services do
		if s.level == level then
			table.insert(out, { kind = "service", id = s.id, icon = s.icon })
		end
	end
	for _, u in ServiceConfig.Upgrades do
		for _, l in u.levels do
			if l.level == level then
				table.insert(out, { kind = "upgrade", id = u.id, icon = u.icon })
				break
			end
		end
	end
	return out
end

local function weightedPick<T>(rng: Random, items: { T }, weightOf: (T, number) -> number): T
	local total = 0
	for i, item in items do
		total += weightOf(item, i)
	end
	local roll = rng:NextNumber() * total
	for i, item in items do
		roll -= weightOf(item, i)
		if roll <= 0 then
			return item
		end
	end
	return items[#items]
end

-- Rolls a new customer for a service of the given level.
function ServiceConfig.makeOrder(level: number, rng: Random, marketing: number?): Order
	local tiers = ServiceConfig.unlockedTiers(level)
	local tier = weightedPick(rng, tiers, function(_, i)
		-- the newest tiers come most often, older ones still show up
		local fromTop = #tiers - i
		return if fromTop == 0 then 4 elseif fromTop == 1 then 2.5 else 1
	end)
	local pool = if tier.models then tier.models else tier.cars :: { string }
	local vehicle = pool[rng:NextInteger(1, #pool)]

	local available = ServiceConfig.unlockedServices(level)
	local count = 1
	if level >= 12 and #available >= 3 and rng:NextNumber() < 0.12 then
		count = 3
	elseif level >= 6 and #available >= 2 and rng:NextNumber() < 0.28 then
		count = 2
	end
	local chosen: { string } = {}
	local left = table.clone(available)
	for _ = 1, count do
		local s = weightedPick(rng, left, function(item)
			return item.weight
		end)
		table.insert(chosen, s.id)
		table.remove(left, table.find(left, s) :: number)
	end

	local mult = 0
	for _, id in chosen do
		mult += (serviceById[id] :: Service).mult
	end
	local tip = 1 + ServiceConfig.tipBonus(marketing or 0)
	local reward = math.floor(tier.reward * mult * rng:NextNumber(0.9, 1.15) * tip / 5 + 0.5) * 5
	local xp = math.floor(tier.xp * (1 + 0.5 * (count - 1)) + 0.5)

	local paint = rng:NextInteger(1, 24)
	local target: number? = nil
	if table.find(chosen, "paint") then
		local t = rng:NextInteger(1, 23)
		target = if t >= paint then t + 1 else t
	end
	return {
		tier = tier.id,
		source = if tier.models then "model" else "car",
		vehicle = vehicle,
		services = chosen,
		paint = paint,
		target = target,
		reward = reward,
		xp = xp,
	}
end

-- Seconds an order should take for 3 stars.
function ServiceConfig.parTime(size: Size, steps: number, toolLevel: number): number
	return size.par * steps / ServiceConfig.toolPower(toolLevel)
end

function ServiceConfig.stars(elapsed: number, par: number): number
	if elapsed <= par then
		return 3
	elseif elapsed <= par * 1.7 then
		return 2
	end
	return 1
end

return ServiceConfig
