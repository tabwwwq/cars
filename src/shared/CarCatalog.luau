-- CarCatalog: every car in the game, described as data.
-- CarBuilder turns a definition into a model, CarPhysics drives it.
--
-- Coordinates are in studs in the car's own space: y = 0 is the ground,
-- the front of the car points to -Z, x = 0 is the center line.
-- To add a car: copy an entry with a similar style, change the numbers and
-- give it a unique `id`. Prices and stats are validated on the server.

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

type CarDef = Types.CarDef
type CarSave = Types.CarSave
type EffectiveStats = Types.EffectiveStats

local CarCatalog = {}

CarCatalog.Classes = {
	{ id = "Starter", name = { ru = "Старт", en = "Starter" }, color = Color3.fromRGB(140, 200, 255) },
	{ id = "Street", name = { ru = "Город", en = "Street" }, color = Color3.fromRGB(120, 220, 160) },
	{ id = "Utility", name = { ru = "Рабочие", en = "Utility" }, color = Color3.fromRGB(200, 180, 120) },
	{ id = "Offroad", name = { ru = "Внедорожники", en = "Offroad" }, color = Color3.fromRGB(170, 140, 90) },
	{ id = "Sport", name = { ru = "Спорт", en = "Sport" }, color = Color3.fromRGB(255, 150, 60) },
	{ id = "Muscle", name = { ru = "Маслкары", en = "Muscle" }, color = Color3.fromRGB(240, 90, 70) },
	{ id = "Emergency", name = { ru = "Спецслужбы", en = "Emergency" }, color = Color3.fromRGB(90, 140, 255) },
	{ id = "Super", name = { ru = "Суперкары", en = "Super" }, color = Color3.fromRGB(220, 90, 255) },
	{ id = "Hyper", name = { ru = "Гиперкары", en = "Hyper" }, color = Color3.fromRGB(255, 70, 160) },
	{ id = "Special", name = { ru = "Особые", en = "Special" }, color = Color3.fromRGB(255, 220, 80) },
}

local function stats(
	maxSpeed: number,
	accel: number,
	grip: number,
	steer: number,
	brake: number,
	drift: number,
	nitro: number,
	offroad: number,
	mass: number,
	drive: Types.DriveType,
	rest: number,
	freq: number?,
	damping: number?
): Types.CarStats
	return {
		maxSpeed = maxSpeed,
		accel = accel,
		grip = grip,
		steer = steer,
		brake = brake,
		drift = drift,
		nitro = nitro,
		offroad = offroad,
		mass = mass,
		drive = drive,
		suspension = { rest = rest, freq = freq, damping = damping },
	}
end

-- Palette indices (see Paints.luau): 1 Snow, 2 Silver, 3 Graphite, 4 Black, 5 Red,
-- 6 Cherry, 7 Orange, 8 Yellow, 9 Lime, 10 Green, 11 Olive, 12 Teal, 13 Sky,
-- 14 Blue, 15 Midnight, 16 Purple, 17 Pink, 18 Sand, 19 Brown, 20 Bronze,
-- 21 Gold, 22 Mint, 23 Lavender, 24 Toxic
local cars: { CarDef } = {
	---------------------------------------------------------------- Starter
	{
		id = "pebble",
		name = "Pebble",
		class = "Starter",
		price = 0,
		description = {
			ru = "Маленький городской хэтчбек. Медленный, но очень послушный.",
			en = "A tiny city hatchback. Slow, but very forgiving.",
		},
		stats = stats(92, 30, 1.0, 36, 85, 0.15, 0.8, 0.25, 0.8, "FWD", 1.3, 2.7),
		wheels = { radius = 1.15, width = 0.95, base = 7.6, track = 5.6, rim = "steel" },
		body = {
			style = "car",
			length = 11.6,
			width = 6.55,
			floor = 0.8,
			belt = 2.95,
			nose = 1.1,
			noseDrop = 0.5,
			tail = 0.5,
			tailDrop = 0.3,
			cabin = { start = 3.4, wind = 2.2, roof = 3.8, back = 1.4, height = 2.3, inset = 0.4 },
		},
		colors = { paint = 13, accent = 1, rim = 2 },
		features = { exhaust = 1, doors = 2 },
	},
	{
		id = "dart",
		name = "Dart",
		class = "Starter",
		price = 4500,
		description = {
			ru = "Лёгкое купе для первых заездов. Хорошо входит в повороты.",
			en = "A light coupe for your first races. Turns in nicely.",
		},
		stats = stats(108, 36, 1.05, 35, 95, 0.3, 0.9, 0.2, 0.85, "FWD", 1.25, 2.8),
		wheels = { radius = 1.2, width = 1.0, base = 8.4, track = 5.9, rim = "star" },
		body = {
			style = "car",
			length = 12.6,
			width = 6.95,
			floor = 0.75,
			belt = 2.9,
			nose = 1.3,
			noseDrop = 0.6,
			tail = 0.7,
			tailDrop = 0.35,
			cabin = { start = 4.4, wind = 2.3, roof = 2.6, back = 2.4, height = 2.1, inset = 0.45 },
		},
		colors = { paint = 7, accent = 4, rim = 3 },
		features = { spoiler = "lip", exhaust = 1, doors = 2 },
	},
	---------------------------------------------------------------- Street
	{
		id = "cruiser",
		name = "Cruiser",
		class = "Street",
		price = 9000,
		description = {
			ru = "Надёжный седан на каждый день. Мягкая подвеска, четыре места.",
			en = "A dependable daily sedan. Soft suspension, four seats.",
		},
		stats = stats(118, 38, 1.05, 33, 100, 0.2, 1.0, 0.25, 1.0, "RWD", 1.4, 2.5),
		wheels = { radius = 1.35, width = 1.1, base = 9.6, track = 6.4, rim = "disc" },
		body = {
			style = "car",
			length = 15.5,
			width = 7.5,
			floor = 0.9,
			belt = 3.35,
			nose = 1.4,
			noseDrop = 0.6,
			tail = 0.9,
			tailDrop = 0.3,
			cabin = { start = 4.9, wind = 2.5, roof = 4.2, back = 2.0, height = 2.15, inset = 0.45 },
		},
		colors = { paint = 14, accent = 2, rim = 2 },
		features = { exhaust = 1, doors = 4, chromeTrim = true },
	},
	{
		id = "taxi",
		name = "Metro Taxi",
		class = "Street",
		price = 12000,
		description = {
			ru = "Жёлтое такси с шашечками. Возит до трёх пассажиров.",
			en = "A yellow checker cab. Carries up to three passengers.",
		},
		stats = stats(122, 40, 1.07, 33, 105, 0.25, 1.0, 0.25, 1.0, "RWD", 1.4, 2.5),
		wheels = { radius = 1.35, width = 1.1, base = 9.6, track = 6.4, rim = "steel" },
		body = {
			style = "car",
			length = 15.5,
			width = 7.5,
			floor = 0.9,
			belt = 3.35,
			nose = 1.4,
			noseDrop = 0.6,
			tail = 0.9,
			tailDrop = 0.3,
			cabin = { start = 4.9, wind = 2.5, roof = 4.2, back = 2.0, height = 2.15, inset = 0.45 },
		},
		colors = { paint = 8, accent = 4, rim = 2 },
		features = { exhaust = 1, doors = 4, taxiSign = true, checker = true },
	},
	{
		id = "volt",
		name = "Volt S",
		class = "Street",
		price = 78000,
		description = {
			ru = "Электроседан: мгновенный разгон, полный привод и стеклянная крыша.",
			en = "Electric sedan: instant torque, all-wheel drive and a glass roof.",
		},
		stats = stats(168, 80, 1.15, 33, 130, 0.2, 1.0, 0.2, 1.25, "AWD", 1.3, 2.7),
		wheels = { radius = 1.35, width = 1.2, base = 10.0, track = 6.6, rim = "aero" },
		body = {
			style = "car",
			length = 15.6,
			width = 7.8,
			floor = 0.7,
			belt = 3.0,
			nose = 2.0,
			noseDrop = 0.9,
			tail = 0.9,
			tailDrop = 0.3,
			cabin = { start = 5.0, wind = 3.0, roof = 3.4, back = 3.0, height = 2.0, inset = 0.55, glassRoof = true },
		},
		colors = { paint = 1, accent = 4, rim = 3 },
		features = { doors = 4, lightbars = true, electric = true },
	},
	---------------------------------------------------------------- Utility
	{
		id = "courier",
		name = "Courier",
		class = "Utility",
		price = 11000,
		description = {
			ru = "Развозной фургон с багажником на крыше. Тяжёлый и устойчивый.",
			en = "A delivery van with a roof rack. Heavy and steady.",
		},
		stats = stats(100, 30, 0.95, 33, 85, 0.1, 0.8, 0.3, 1.4, "RWD", 1.5, 2.4),
		wheels = { radius = 1.4, width = 1.2, base = 10.2, track = 6.6, rim = "steel" },
		body = {
			style = "car",
			length = 15.0,
			width = 7.85,
			floor = 1.0,
			belt = 3.6,
			nose = 1.6,
			noseDrop = 1.2,
			tail = 0.3,
			tailDrop = 0.1,
			cabin = { start = 2.0, wind = 2.0, roof = 10.7, back = 0, height = 3.4, inset = 0.25, sideWindows = 2.6 },
		},
		colors = { paint = 1, accent = 14, rim = 2 },
		features = { exhaust = 1, doors = 2, roofRack = true, sideStripe = true },
	},
	{
		id = "hauler",
		name = "Hauler",
		class = "Utility",
		price = 16000,
		description = {
			ru = "Полноприводный пикап с кенгурятником. Не боится бездорожья.",
			en = "An all-wheel-drive pickup with a bull bar. Shrugs off rough ground.",
		},
		stats = stats(112, 38, 1.0, 32, 95, 0.25, 0.9, 0.6, 1.4, "AWD", 1.7, 2.3),
		wheels = { radius = 1.6, width = 1.35, base = 11.2, track = 7.0, rim = "offroad" },
		body = {
			style = "pickup",
			length = 17.5,
			width = 8.4,
			floor = 1.3,
			belt = 4.0,
			nose = 1.2,
			noseDrop = 0.5,
			tail = 0.3,
			tailDrop = 0,
			cabin = { start = 5.2, wind = 2.2, roof = 3.4, back = 0.6, height = 2.3, inset = 0.45 },
			bed = { start = 11.6 },
		},
		colors = { paint = 5, accent = 3, rim = 3 },
		features = { exhaust = 1, doors = 2, bullbar = true, fenderFlares = true },
	},
	{
		id = "metroliner",
		name = "Metroliner",
		class = "Utility",
		price = 40000,
		description = {
			ru = "Городской автобус на девять мест. Катай друзей по всей карте!",
			en = "A nine-seat city bus. Give your friends a ride around the map!",
		},
		stats = stats(92, 26, 0.95, 36, 85, 0.05, 0.7, 0.2, 3.0, "RWD", 1.8, 2.0),
		wheels = {
			radius = 1.7,
			width = 1.4,
			base = 16.6,
			track = 7.8,
			rim = "steel",
			axles = {
				{ z = -9.6, steer = true, drive = false },
				{ z = 7.0, steer = false, drive = true },
			},
		},
		body = {
			style = "car",
			length = 32.0,
			width = 9.8,
			floor = 1.3,
			belt = 3.8,
			nose = 0.4,
			noseDrop = 0.2,
			tail = 0.3,
			tailDrop = 0.1,
			cabin = {
				start = 0.5,
				wind = 1.0,
				roof = 30.2,
				back = 0,
				height = 4.4,
				inset = 0.2,
				windowPillars = 4.2,
			},
		},
		colors = { paint = 7, accent = 1, rim = 2 },
		features = { exhaust = 1, routeSign = true, sideStripe = true, busDoors = true },
		seats = {
			{ x = -3.0, z = -12.6, driver = true },
			{ x = -2.6, z = -6.0 },
			{ x = 2.6, z = -6.0 },
			{ x = -2.6, z = -1.5 },
			{ x = 2.6, z = -1.5 },
			{ x = -2.6, z = 3.0 },
			{ x = 2.6, z = 3.0 },
			{ x = -2.6, z = 10.5 },
			{ x = 2.6, z = 10.5 },
		},
		maxSeats = 9,
	},
	{
		id = "titan",
		name = "Titan",
		class = "Utility",
		price = 95000,
		description = {
			ru = "Седельный тягач: три оси, хромированные трубы и мощный нитро.",
			en = "A semi tractor: three axles, chrome stacks and a mighty nitro.",
		},
		stats = stats(115, 30, 1.0, 30, 90, 0.05, 1.3, 0.3, 3.2, "RWD", 1.9, 2.0),
		wheels = {
			radius = 1.9,
			width = 1.5,
			base = 11.6,
			track = 8.0,
			rim = "disc",
			axles = {
				{ z = -6.0, steer = true, drive = false },
				{ z = 3.6, steer = false, drive = true },
				{ z = 7.6, steer = false, drive = true },
			},
		},
		body = {
			style = "semi",
			length = 21.0,
			width = 9.6,
			floor = 1.7,
			belt = 5.3,
			nose = 1.0,
			noseDrop = 0.4,
			tail = 0.2,
			tailDrop = 0,
			cabin = { start = 4.6, wind = 1.4, roof = 4.6, back = 0, height = 3.6, inset = 0.3, sideWindows = 2.6 },
			box = { start = 10.6, top = 9.4, length = 2.6 },
		},
		colors = { paint = 14, accent = 2, rim = 2 },
		features = { stacks = true, fuelTanks = true, bigGrille = true, visor = true },
	},
	---------------------------------------------------------------- Offroad
	{
		id = "ranger",
		name = "Ranger",
		class = "Offroad",
		price = 22000,
		description = {
			ru = "Рамный внедорожник со шноркелем и запаской. Король грязи.",
			en = "A body-on-frame SUV with a snorkel and spare wheel. King of mud.",
		},
		stats = stats(115, 38, 1.0, 32, 95, 0.15, 0.9, 0.75, 1.5, "AWD", 1.9, 2.2),
		wheels = { radius = 1.65, width = 1.35, base = 10.6, track = 7.0, rim = "offroad" },
		body = {
			style = "car",
			length = 16.0,
			width = 8.4,
			floor = 1.4,
			belt = 4.1,
			nose = 1.0,
			noseDrop = 0.4,
			tail = 0.4,
			tailDrop = 0.2,
			cabin = { start = 4.6, wind = 2.0, roof = 7.8, back = 1.0, height = 2.5, inset = 0.45 },
		},
		colors = { paint = 11, accent = 4, rim = 4 },
		features = { exhaust = 1, doors = 4, roofRack = true, spareTire = true, snorkel = true, fenderFlares = true },
	},
	{
		id = "rallyfox",
		name = "Rally Fox",
		class = "Offroad",
		price = 58000,
		description = {
			ru = "Раллийный хэтчбек: полный привод, длинный ход подвески, люстра фар.",
			en = "A rally hatch: all-wheel drive, long-travel suspension, light pod.",
		},
		stats = stats(146, 55, 1.12, 37, 115, 0.55, 1.0, 0.85, 1.0, "AWD", 1.8, 2.4),
		wheels = { radius = 1.4, width = 1.25, base = 9.2, track = 6.6, rim = "disc" },
		body = {
			style = "car",
			length = 13.4,
			width = 7.6,
			floor = 1.2,
			belt = 3.4,
			nose = 1.2,
			noseDrop = 0.5,
			tail = 0.5,
			tailDrop = 0.2,
			cabin = { start = 4.2, wind = 2.3, roof = 3.6, back = 1.8, height = 2.1, inset = 0.5 },
		},
		colors = { paint = 14, accent = 8, rim = 1 },
		features = {
			exhaust = 1,
			doors = 2,
			spoiler = "wing",
			roofScoop = true,
			mudFlaps = true,
			rallyLights = true,
			raceNumber = 7,
		},
	},
	{
		id = "sandhopper",
		name = "Sandhopper",
		class = "Offroad",
		price = 26000,
		description = {
			ru = "Багги с трубчатой рамой. Прыгает по дюнам как кузнечик.",
			en = "A tube-frame dune buggy. Hops across the dunes like a grasshopper.",
		},
		stats = stats(132, 54, 1.05, 37, 100, 0.5, 1.0, 0.95, 0.8, "RWD", 2.0, 2.2),
		wheels = { radius = 1.6, width = 1.4, base = 9.0, track = 7.2, rearWidth = 1.7, rim = "offroad" },
		body = { style = "buggy", length = 12.0, width = 6.0, floor = 1.5, belt = 3.0 },
		colors = { paint = 13, accent = 3, rim = 4 },
		features = { exhaust = 2 },
		seats = { { x = 0, z = 0.4, driver = true } },
	},
	{
		id = "goliath",
		name = "Goliath",
		class = "Offroad",
		price = 120000,
		description = {
			ru = "Монстр-трак на гигантских колёсах. Переезжает всё, что видит.",
			en = "A monster truck on giant tires. Drives over anything in sight.",
		},
		stats = stats(118, 46, 1.1, 30, 100, 0.3, 1.1, 1.0, 2.2, "AWD", 3.4, 1.7, 0.5),
		wheels = { radius = 3.4, width = 2.6, base = 13.0, track = 10.4, rim = "offroad" },
		body = {
			style = "pickup",
			length = 16.5,
			width = 9.4,
			floor = 5.8,
			belt = 8.3,
			nose = 1.2,
			noseDrop = 0.5,
			tail = 0.3,
			tailDrop = 0,
			cabin = { start = 5.0, wind = 2.0, roof = 3.4, back = 0.6, height = 2.3, inset = 0.6 },
			bed = { start = 11.2 },
		},
		colors = { paint = 10, accent = 4, rim = 3 },
		features = { monster = true, fenderFlares = true, roofLights = true, bullbar = true, stacks = true },
	},
	---------------------------------------------------------------- Sport
	{
		id = "stinger",
		name = "Stinger RS",
		class = "Sport",
		price = 28000,
		description = {
			ru = "Заряженный хэтчбек с полным приводом. Цепко держит дорогу.",
			en = "An all-wheel-drive hot hatch. Grips like glue.",
		},
		stats = stats(140, 52, 1.15, 35, 120, 0.35, 1.0, 0.3, 0.9, "AWD", 1.2, 2.9),
		wheels = { radius = 1.25, width = 1.15, base = 8.6, track = 6.2, rim = "spoke" },
		body = {
			style = "car",
			length = 12.8,
			width = 7.35,
			floor = 0.65,
			belt = 2.85,
			nose = 1.3,
			noseDrop = 0.6,
			tail = 0.5,
			tailDrop = 0.2,
			cabin = { start = 4.0, wind = 2.3, roof = 3.6, back = 1.8, height = 2.05, inset = 0.45 },
		},
		colors = { paint = 9, accent = 4, rim = 3 },
		features = { exhaust = 2, doors = 2, spoiler = "roof", hoodVents = true, sideSkirts = true, stripes = true },
	},
	{
		id = "comet",
		name = "Comet GT",
		class = "Sport",
		price = 36000,
		description = {
			ru = "Классическое спортивное купе: задний привод и идеальный баланс.",
			en = "A classic sports coupe: rear-wheel drive and perfect balance.",
		},
		stats = stats(158, 58, 1.18, 33, 130, 0.35, 1.0, 0.15, 0.95, "RWD", 1.15, 3.0),
		wheels = { radius = 1.3, width = 1.2, base = 9.4, track = 6.5, rim = "star" },
		body = {
			style = "car",
			length = 14.6,
			width = 7.75,
			floor = 0.6,
			belt = 2.7,
			nose = 1.9,
			noseDrop = 0.8,
			tail = 0.9,
			tailDrop = 0.3,
			cabin = { start = 5.6, wind = 2.6, roof = 2.4, back = 3.0, height = 1.8, inset = 0.6 },
		},
		colors = { paint = 5, accent = 4, rim = 2 },
		features = { exhaust = 2, doors = 2, spoiler = "ducktail", sideSkirts = true, hoodVents = true },
	},
	{
		id = "kitsune",
		name = "Kitsune",
		class = "Sport",
		price = 48000,
		description = {
			ru = "Японское дрифт-купе. Огромный угол руля и лёгкий занос.",
			en = "A Japanese drift coupe. Huge steering lock and an easy slide.",
		},
		stats = stats(150, 55, 1.08, 44, 120, 0.9, 1.0, 0.15, 0.95, "RWD", 1.15, 3.0),
		wheels = { radius = 1.25, width = 1.2, base = 9.2, track = 6.4, rim = "spoke" },
		body = {
			style = "car",
			length = 14.0,
			width = 7.6,
			floor = 0.6,
			belt = 2.75,
			nose = 1.6,
			noseDrop = 0.7,
			tail = 0.7,
			tailDrop = 0.25,
			cabin = { start = 5.0, wind = 2.4, roof = 2.8, back = 2.4, height = 1.9, inset = 0.55 },
		},
		colors = { paint = 1, accent = 5, rim = 20 },
		features = { exhaust = 1, doors = 2, spoiler = "wing", sideSkirts = true, canards = true, raceNumber = 86 },
	},
	{
		id = "sunset",
		name = "Sunset",
		class = "Sport",
		price = 70000,
		description = {
			ru = "Родстер с открытым верхом для поездок на закате.",
			en = "An open-top roadster made for sunset drives.",
		},
		stats = stats(160, 57, 1.15, 34, 125, 0.4, 1.0, 0.15, 0.9, "RWD", 1.15, 3.0),
		wheels = { radius = 1.3, width = 1.2, base = 9.0, track = 6.4, rim = "spoke" },
		body = {
			style = "car",
			length = 13.8,
			width = 7.6,
			floor = 0.65,
			belt = 2.8,
			nose = 2.0,
			noseDrop = 0.9,
			tail = 0.8,
			tailDrop = 0.25,
			cabin = { start = 5.2, wind = 1.6, roof = 3.0, back = 0, height = 1.4, inset = 0.5, open = true },
		},
		colors = { paint = 6, accent = 18, rim = 2 },
		features = { exhaust = 2, doors = 2, chromeTrim = true, rollHoops = true },
	},
	---------------------------------------------------------------- Muscle
	{
		id = "thunder",
		name = "Thunder V8",
		class = "Muscle",
		price = 42000,
		description = {
			ru = "Маслкар с огромным воздухозаборником. Любит прямые и бёрнауты.",
			en = "A muscle car with a huge hood scoop. Loves straights and burnouts.",
		},
		stats = stats(162, 64, 1.04, 31, 110, 0.6, 1.15, 0.2, 1.25, "RWD", 1.3, 2.7),
		wheels = { radius = 1.4, width = 1.35, base = 10.0, track = 6.8, rearWidth = 1.6, rim = "star" },
		body = {
			style = "car",
			length = 16.2,
			width = 8.35,
			floor = 0.8,
			belt = 3.2,
			nose = 0.8,
			noseDrop = 0.3,
			tail = 0.6,
			tailDrop = 0.2,
			cabin = { start = 6.4, wind = 2.4, roof = 2.6, back = 2.6, height = 1.95, inset = 0.6 },
		},
		colors = { paint = 4, accent = 7, rim = 2 },
		features = { exhaust = 2, doors = 2, hoodScoop = "big", stripes = true, spoiler = "lip" },
	},
	{
		id = "bandit",
		name = "Bandit '77",
		class = "Muscle",
		price = 52000,
		description = {
			ru = "Легенда семидесятых: чёрный с золотом, хром и рык мотора.",
			en = "A seventies legend: black and gold, chrome and a growling engine.",
		},
		stats = stats(166, 60, 1.02, 31, 105, 0.65, 1.1, 0.25, 1.3, "RWD", 1.35, 2.6),
		wheels = { radius = 1.4, width = 1.3, base = 10.4, track = 6.8, rim = "spoke" },
		body = {
			style = "car",
			length = 17.0,
			width = 8.1,
			floor = 0.85,
			belt = 3.0,
			nose = 0.6,
			noseDrop = 0.2,
			tail = 0.4,
			tailDrop = 0.1,
			cabin = { start = 6.8, wind = 2.6, roof = 3.4, back = 1.6, height = 1.9, inset = 0.7 },
		},
		colors = { paint = 4, accent = 21, rim = 21 },
		features = { exhaust = 2, doors = 2, chromeTrim = true, hoodScoop = "small", stripes = true, spoiler = "ducktail" },
	},
	---------------------------------------------------------------- Emergency
	{
		id = "interceptor",
		name = "Interceptor",
		class = "Emergency",
		price = 65000,
		description = {
			ru = "Полицейский перехватчик с мигалками (клавиша K) и отбойником.",
			en = "A police interceptor with a light bar (press K) and push bumper.",
		},
		stats = stats(165, 60, 1.12, 33, 130, 0.3, 1.2, 0.3, 1.2, "AWD", 1.3, 2.7),
		wheels = { radius = 1.4, width = 1.2, base = 10.0, track = 6.6, rim = "steel" },
		body = {
			style = "car",
			length = 16.0,
			width = 7.8,
			floor = 0.85,
			belt = 3.3,
			nose = 1.4,
			noseDrop = 0.6,
			tail = 0.9,
			tailDrop = 0.3,
			cabin = { start = 5.2, wind = 2.5, roof = 4.2, back = 2.0, height = 2.1, inset = 0.5 },
		},
		colors = { paint = 4, accent = 1, rim = 3 },
		features = { exhaust = 2, doors = 4, siren = "police", pushBumper = true, livery = "POLICE", antenna = true },
	},
	{
		id = "medic",
		name = "Medic One",
		class = "Emergency",
		price = 45000,
		description = {
			ru = "Скорая помощь с салоном-кубом и проблесковыми маячками.",
			en = "An ambulance with a box body and flashing beacons.",
		},
		stats = stats(126, 40, 1.0, 32, 100, 0.1, 1.0, 0.35, 1.7, "RWD", 1.7, 2.3),
		wheels = { radius = 1.55, width = 1.3, base = 11.0, track = 7.0, offset = 0.6, rim = "steel" },
		body = {
			style = "box",
			length = 18.5,
			width = 8.6,
			floor = 1.2,
			belt = 3.8,
			nose = 1.2,
			noseDrop = 0.8,
			tail = 0.2,
			tailDrop = 0,
			cabin = { start = 2.2, wind = 2.0, roof = 2.6, back = 0, height = 2.4, inset = 0.4 },
			box = { start = 6.8, top = 8.0 },
		},
		colors = { paint = 1, accent = 5, rim = 2 },
		features = { siren = "medic", medicCross = true, sideStripe = true, doors = 2 },
	},
	{
		id = "blaze",
		name = "Blaze",
		class = "Emergency",
		price = 110000,
		description = {
			ru = "Пожарная машина: три оси, лестница, сирена и катушки рукавов.",
			en = "A fire engine: three axles, a ladder, siren and hose reels.",
		},
		stats = stats(112, 34, 1.0, 32, 90, 0.05, 1.0, 0.35, 2.6, "RWD", 1.9, 2.1),
		wheels = {
			radius = 1.8,
			width = 1.4,
			base = 13.0,
			track = 7.6,
			rim = "disc",
			axles = {
				{ z = -7.4, steer = true, drive = false },
				{ z = 4.2, steer = false, drive = true },
				{ z = 8.0, steer = false, drive = true },
			},
		},
		body = {
			style = "box",
			length = 26.0,
			width = 9.4,
			floor = 1.5,
			belt = 4.7,
			nose = 0.8,
			noseDrop = 0.4,
			tail = 0.2,
			tailDrop = 0,
			cabin = { start = 1.2, wind = 1.8, roof = 4.8, back = 0, height = 2.8, inset = 0.35 },
			box = { start = 7.8, top = 7.3 },
		},
		colors = { paint = 5, accent = 1, rim = 2 },
		features = { siren = "fire", ladder = true, hoseReels = true, doors = 4, sideStripe = true },
		seats = {
			{ x = -2.4, z = -9.0, driver = true },
			{ x = 2.4, z = -9.0 },
			{ x = -2.4, z = -6.2 },
			{ x = 2.4, z = -6.2 },
		},
	},
	---------------------------------------------------------------- Super
	{
		id = "zephyr",
		name = "Zephyr S",
		class = "Super",
		price = 140000,
		description = {
			ru = "Среднемоторный суперкар с большим антикрылом.",
			en = "A mid-engined supercar with a big rear wing.",
		},
		stats = stats(200, 78, 1.28, 32, 150, 0.3, 1.1, 0.05, 1.1, "RWD", 1.0, 3.2),
		wheels = { radius = 1.35, width = 1.35, base = 10.0, track = 6.9, rearWidth = 1.5, rim = "star" },
		body = {
			style = "car",
			length = 15.6,
			width = 8.45,
			floor = 0.5,
			belt = 2.55,
			nose = 3.0,
			noseDrop = 1.3,
			tail = 1.0,
			tailDrop = 0.25,
			cabin = { start = 5.4, wind = 3.2, roof = 1.8, back = 3.6, height = 1.75, inset = 0.8 },
		},
		colors = { paint = 8, accent = 4, rim = 3 },
		features = { exhaust = 2, doors = 2, spoiler = "bigwing", sideIntakes = true, diffuser = true },
	},
	{
		id = "vortex",
		name = "Vortex",
		class = "Super",
		price = 210000,
		description = {
			ru = "Полноприводный суперкар с воздухозаборником на крыше.",
			en = "An all-wheel-drive supercar with a roof air scoop.",
		},
		stats = stats(218, 86, 1.3, 31, 155, 0.35, 1.15, 0.05, 1.1, "AWD", 1.0, 3.2),
		wheels = { radius = 1.4, width = 1.4, base = 10.4, track = 7.0, rearWidth = 1.55, rim = "spoke" },
		body = {
			style = "car",
			length = 16.2,
			width = 8.6,
			floor = 0.45,
			belt = 2.45,
			nose = 3.4,
			noseDrop = 1.3,
			tail = 0.8,
			tailDrop = 0.2,
			cabin = { start = 5.8, wind = 3.4, roof = 1.6, back = 3.8, height = 1.85, inset = 0.9 },
		},
		colors = { paint = 16, accent = 4, rim = 3 },
		features = { exhaust = 4, doors = 2, spoiler = "wing", sideIntakes = true, roofScoop = true, diffuser = true },
	},
	---------------------------------------------------------------- Hyper
	{
		id = "nebula",
		name = "Nebula",
		class = "Hyper",
		price = 480000,
		description = {
			ru = "Гиперкар с акульим плавником и неоновыми акцентами.",
			en = "A hypercar with a shark fin and neon accents.",
		},
		stats = stats(245, 96, 1.36, 31, 165, 0.3, 1.25, 0.05, 1.15, "AWD", 0.95, 3.3),
		wheels = { radius = 1.4, width = 1.45, base = 10.6, track = 7.2, rearWidth = 1.6, rim = "aero" },
		body = {
			style = "car",
			length = 17.0,
			width = 9.0,
			floor = 0.4,
			belt = 2.35,
			nose = 3.8,
			noseDrop = 1.3,
			tail = 1.2,
			tailDrop = 0.3,
			cabin = { start = 6.2, wind = 3.6, roof = 1.4, back = 4.2, height = 1.9, inset = 1.1 },
		},
		colors = { paint = 15, accent = 13, rim = 3 },
		features = { exhaust = 2, doors = 2, spoiler = "bigwing", fin = true, sideIntakes = true, neonAccents = true, diffuser = true },
	},
	{
		id = "quasar",
		name = "Quasar",
		class = "Hyper",
		price = 900000,
		description = {
			ru = "Электрический гиперкар. Самый быстрый разгон в игре.",
			en = "An electric hypercar. The quickest launch in the game.",
		},
		stats = stats(265, 112, 1.42, 31, 175, 0.25, 1.3, 0.05, 1.2, "AWD", 0.95, 3.3),
		wheels = { radius = 1.45, width = 1.5, base = 11.0, track = 7.4, rearWidth = 1.65, rim = "aero" },
		body = {
			style = "car",
			length = 17.6,
			width = 9.2,
			floor = 0.38,
			belt = 2.25,
			nose = 4.2,
			noseDrop = 1.25,
			tail = 1.4,
			tailDrop = 0.4,
			cabin = { start = 6.6, wind = 3.8, roof = 1.2, back = 4.6, height = 2.0, inset = 1.1 },
		},
		colors = { paint = 4, accent = 24, rim = 4 },
		features = {
			doors = 2,
			spoiler = "bigwing",
			fin = true,
			sideIntakes = true,
			neonAccents = true,
			lightbars = true,
			electric = true,
			diffuser = true,
		},
	},
	{
		id = "apex",
		name = "Apex F1",
		class = "Hyper",
		price = 1250000,
		description = {
			ru = "Болид с открытыми колёсами. Невероятное сцепление и скорость.",
			en = "An open-wheel racer. Unreal grip and top speed.",
		},
		stats = stats(280, 115, 1.6, 26, 200, 0.1, 1.2, 0.0, 0.8, "RWD", 0.8, 3.2, 0.6),
		wheels = {
			radius = 1.25,
			width = 1.35,
			base = 12.0,
			track = 7.4,
			rearRadius = 1.4,
			rearWidth = 1.75,
			rim = "disc",
		},
		body = { style = "openwheel", length = 19.0, width = 3.0, floor = 0.35, belt = 1.9 },
		colors = { paint = 5, accent = 1, rim = 4 },
		features = { raceNumber = 1 },
		seats = { { x = 0, z = 0.6, driver = true } },
	},
	---------------------------------------------------------------- Special
	{
		id = "zippy",
		name = "Zippy",
		class = "Special",
		price = 5000,
		description = {
			ru = "Карт. Низкий, вёрткий и невероятно весёлый.",
			en = "A go-kart. Low, twitchy and ridiculously fun.",
		},
		stats = stats(95, 50, 1.3, 38, 110, 0.5, 1.0, 0.1, 0.5, "RWD", 0.6, 3.4),
		wheels = { radius = 0.8, width = 0.9, base = 5.6, track = 4.8, rearWidth = 1.1, rim = "disc" },
		body = { style = "kart", length = 8.0, width = 4.6, floor = 0.35, belt = 1.2 },
		colors = { paint = 7, accent = 4, rim = 4 },
		features = { raceNumber = 3 },
		seats = { { x = 0, z = 0.8, driver = true } },
	},
	{
		id = "frosty",
		name = "Frosty",
		class = "Special",
		price = 18000,
		description = {
			ru = "Фургон с мороженым. Огромный рожок на крыше прилагается!",
			en = "An ice cream van. Giant cone on the roof included!",
		},
		stats = stats(98, 28, 0.95, 32, 85, 0.1, 0.8, 0.25, 1.5, "RWD", 1.5, 2.4),
		wheels = { radius = 1.4, width = 1.2, base = 10.0, track = 6.6, offset = 0.4, rim = "steel" },
		body = {
			style = "box",
			length = 16.4,
			width = 8.0,
			floor = 1.0,
			belt = 3.6,
			nose = 1.4,
			noseDrop = 1.0,
			tail = 0.2,
			tailDrop = 0,
			cabin = { start = 1.8, wind = 2.0, roof = 2.4, back = 0, height = 2.5, inset = 0.4 },
			box = { start = 6.2, top = 7.6 },
		},
		colors = { paint = 22, accent = 17, rim = 1 },
		features = { iceCream = true, servingWindow = true, doors = 2 },
	},
	{
		id = "prestige",
		name = "Prestige",
		class = "Special",
		price = 85000,
		description = {
			ru = "Лимузин на семь мест. Хром, длинная база и красная дорожка.",
			en = "A seven-seat limousine. Chrome, a long wheelbase and red-carpet style.",
		},
		stats = stats(130, 38, 1.0, 31, 100, 0.15, 0.9, 0.15, 1.9, "RWD", 1.4, 2.4),
		wheels = { radius = 1.4, width = 1.2, base = 15.6, track = 6.8, rim = "spoke" },
		body = {
			style = "car",
			length = 22.5,
			width = 8.05,
			floor = 0.9,
			belt = 3.3,
			nose = 1.2,
			noseDrop = 0.5,
			tail = 0.9,
			tailDrop = 0.3,
			cabin = { start = 5.6, wind = 2.4, roof = 10.6, back = 1.8, height = 2.15, inset = 0.5, windowPillars = 3.6 },
		},
		colors = { paint = 4, accent = 2, rim = 2 },
		features = { exhaust = 2, doors = 6, chromeTrim = true, ornament = true },
		seats = {
			{ x = -1.6, z = -4.4, driver = true },
			{ x = 1.6, z = -4.4 },
			{ x = -1.6, z = -0.4 },
			{ x = 1.6, z = -0.4 },
			{ x = -1.6, z = 3.4 },
			{ x = 1.6, z = 3.4 },
			{ x = 0, z = 6.0 },
		},
		maxSeats = 7,
	},
	{
		id = "harvester",
		name = "Harvester",
		class = "Special",
		price = 14000,
		description = {
			ru = "Трактор с огромными задними колёсами. Медленный, но пройдёт везде.",
			en = "A tractor with huge rear wheels. Slow, but goes anywhere.",
		},
		stats = stats(70, 30, 1.2, 36, 90, 0.05, 0.7, 1.0, 1.6, "RWD", 1.2, 2.4),
		wheels = {
			radius = 1.3,
			width = 1.0,
			base = 8.6,
			track = 5.8,
			rearRadius = 2.6,
			rearWidth = 1.8,
			rearTrack = 7.6,
			rim = "offroad",
		},
		body = { style = "tractor", length = 12.4, width = 3.8, floor = 1.6, belt = 4.4 },
		colors = { paint = 10, accent = 8, rim = 8 },
		features = { exhaust = 1 },
		seats = { { x = 0, z = 3.2, driver = true } },
	},
}

CarCatalog.List = cars

local byId: { [string]: CarDef } = {}
for i, def in cars do
	assert(byId[def.id] == nil, "Duplicate car id " .. def.id)
	byId[def.id] = def
	;(def :: any).order = i
end

function CarCatalog.get(id: any): CarDef?
	if typeof(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function CarCatalog.getClass(id: string)
	for _, class in CarCatalog.Classes do
		if class.id == id then
			return class
		end
	end
	return CarCatalog.Classes[1]
end

-- Resolves the axle layout of a car (shared by the builder and physics).
export type Axle = { z: number, steer: boolean, drive: boolean, radius: number, width: number, track: number }

function CarCatalog.getAxles(def: CarDef): { Axle }
	local w = def.wheels
	local result: { Axle } = {}
	local drive = def.stats.drive
	if w.axles then
		for _, a in w.axles do
			table.insert(result, {
				z = a.z,
				steer = a.steer,
				drive = a.drive,
				radius = a.radius or w.radius,
				width = a.width or w.width,
				track = a.track or w.track,
			})
		end
		return result
	end
	local offset = w.offset or 0
	table.insert(result, {
		z = -w.base / 2 + offset,
		steer = true,
		drive = drive ~= "RWD",
		radius = w.radius,
		width = w.width,
		track = w.track,
	})
	table.insert(result, {
		z = w.base / 2 + offset,
		steer = false,
		drive = drive ~= "FWD",
		radius = w.rearRadius or w.radius,
		width = w.rearWidth or w.width,
		track = w.rearTrack or w.track,
	})
	return result
end

-- Default customization for a freshly bought car.
function CarCatalog.defaultSave(def: CarDef): CarSave
	return {
		paint = def.colors.paint,
		accent = def.colors.accent,
		rim = def.colors.rim,
		finish = "Gloss",
		glow = 0,
		glowOwned = false,
		engine = 0,
		tires = 0,
		nitro = 0,
	}
end

-- Stats after upgrades. Used by the server (authoritative, written to the model)
-- and by the garage UI (preview only).
function CarCatalog.getEffectiveStats(def: CarDef, save: CarSave?): EffectiveStats
	local s = def.stats
	local up = Config.Upgrades
	local engine = if save then save.engine else 0
	local tires = if save then save.tires else 0
	local nitro = if save then save.nitro else 0
	local susp = s.suspension
	return {
		maxSpeed = s.maxSpeed * (1 + engine * up.Engine.MaxSpeedPerLevel),
		accel = s.accel * (1 + engine * up.Engine.AccelPerLevel),
		grip = s.grip * (1 + tires * up.Tires.GripPerLevel),
		steer = s.steer,
		brake = s.brake,
		drift = s.drift,
		nitroPower = s.nitro * (1 + nitro * up.Nitro.PowerPerLevel),
		nitroRecharge = 1 + nitro * up.Nitro.RechargePerLevel,
		offroad = math.min(1, s.offroad + tires * up.Tires.OffroadPerLevel),
		drive = s.drive,
		suspRest = susp.rest,
		suspFreq = susp.freq or Config.Physics.SuspensionFrequency,
		suspDamping = susp.damping or Config.Physics.SuspensionDamping,
	}
end

-- 0..10 ratings for the garage bars.
function CarCatalog.getRatings(stats: EffectiveStats)
	local function scale(v: number, lo: number, hi: number): number
		return math.clamp((v - lo) / (hi - lo) * 10, 0.3, 10)
	end
	return {
		speed = scale(stats.maxSpeed, 60, 300),
		accel = scale(stats.accel, 20, 125),
		handling = scale(stats.grip * 0.7 + stats.steer / 40 * 0.3, 0.75, 1.5),
		offroad = scale(stats.offroad, -0.05, 1.05),
		nitro = scale(stats.nitroPower, 0.6, 1.8),
	}
end

function CarCatalog.getUpgradePrice(def: CarDef, kind: string, level: number): number?
	local up = (Config.Upgrades :: any)[kind]
	if not up or level < 1 or level > up.MaxLevel then
		return nil
	end
	local scale = (Config.UpgradePriceScale :: any)[def.class] or 1
	return math.floor(up.Prices[level] * scale / 50 + 0.5) * 50
end

return CarCatalog
