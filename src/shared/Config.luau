-- Config: all gameplay tunables in one place.
-- NOTE: this module replicates to clients, so it holds nothing secret.
-- Every number that matters for the economy is re-checked on the server.

local Config = {}

Config.Version = "2.0.0"

-- Data ----------------------------------------------------------------------
Config.DataStoreName = "CarsMode_PlayerData_v1"
Config.AutosaveInterval = 90 -- seconds
Config.SessionLockTimeout = 600 -- a lock older than this is considered dead
Config.StartingCash = 7500
Config.StarterCarId = "pebble" -- given for free to every new player

-- Admins (UserIds) may use the dev panel in live servers. In Studio it is always on.
Config.Admins = {} :: { number }

-- Vehicles ------------------------------------------------------------------
Config.SpawnCooldown = 3 -- seconds between spawns
Config.FlipCooldown = 2
Config.VoidY = -80 -- cars below this height are rescued to a spawn pad
Config.SpeedDisplayFactor = 1.3 -- studs/s -> "km/h" on the HUD
Config.MaxPassengerSeats = 3

-- Physics defaults (overridden per car in CarCatalog)
Config.Physics = {
	SuspensionFrequency = 2.6, -- Hz
	SuspensionDamping = 0.55, -- damping ratio (1 = critically damped)
	LateralGripRate = 0.62, -- 0..1 share of sideways slip removed each step
	AntiRoll = 0.72, -- 0 = forces at contact point, 1 = at center of mass height
	SteerRate = 4.2, -- rad/s the front wheels turn towards the target angle
	SteerReturnRate = 6.0,
	HighSpeedSteer = 0.38, -- share of max steer left at top speed
	CoastDecel = 7, -- studs/s^2 when no throttle
	ReverseShare = 0.42, -- reverse top speed as share of max speed
	DownforceG = 0.45, -- extra downforce at top speed, in g
	AirControl = 2.2, -- rad/s^2 of player pitch/yaw control in the air
	AirLevelling = 1.6, -- how strongly the car rights itself in the air
	MaxAngularSpeed = 14,
	NitroDrain = 0.28, -- share of the tank per second
	NitroRecharge = 0.05, -- per second while not boosting
	NitroDriftRecharge = 0.12, -- extra per second while drifting
	NitroAirRecharge = 0.1,
	NitroSpeedBonus = 0.28, -- top speed multiplier while boosting
	NitroAccelBonus = 0.9, -- acceleration multiplier added while boosting
	DriftSlipAngle = 14, -- degrees of slip before a slide counts as a drift
	DriftMinSpeed = 30,
	DriftMaxAngle = 32, -- past this slip angle the rear tires start to bite again
	DriftThrust = 0.45, -- share of acceleration that pushes along the slide
	DriftScrubKeep = 0.7, -- share of tire scrub returned while sliding
	CorneringDrag = 0.03, -- speed lost per unit of cornering force
	MaxYawRate = 3.0, -- rad/s
	CounterSteer = 0.85, -- 0..1 automatic counter-steer while sliding
}

-- Grip and rolling drag per surface. `offroad` stat on the car shrinks the penalty.
Config.Surfaces = {
	Default = { grip = 1.0, drag = 0 },
	Asphalt = { grip = 1.05, drag = 0 },
	Concrete = { grip = 1.0, drag = 0 },
	SmoothPlastic = { grip = 1.0, drag = 0 },
	Plastic = { grip = 1.0, drag = 0 },
	Pavement = { grip = 1.0, drag = 0 },
	Slate = { grip = 0.95, drag = 1 },
	Brick = { grip = 0.95, drag = 1 },
	Cobblestone = { grip = 0.9, drag = 3 },
	Wood = { grip = 0.9, drag = 1 },
	WoodPlanks = { grip = 0.9, drag = 1 },
	Metal = { grip = 0.9, drag = 0 },
	DiamondPlate = { grip = 0.95, drag = 0 },
	Grass = { grip = 0.78, drag = 7 },
	LeafyGrass = { grip = 0.75, drag = 8 },
	Ground = { grip = 0.8, drag = 6 },
	Rock = { grip = 0.85, drag = 4 },
	Basalt = { grip = 0.85, drag = 4 },
	Sand = { grip = 0.62, drag = 16 },
	Sandstone = { grip = 0.8, drag = 5 },
	Mud = { grip = 0.55, drag = 22 },
	Snow = { grip = 0.5, drag = 12 },
	Ice = { grip = 0.22, drag = 0 },
	Glacier = { grip = 0.25, drag = 0 },
}

-- Economy -------------------------------------------------------------------
Config.Earnings = {
	PerStud = 0.08, -- cash per stud driven (100 studs/s = $480 per minute)
	MinSpeed = 12, -- below this nothing is paid for distance
	PayoutInterval = 5, -- seconds between distance payouts
	DriftPerSecond = 30,
	DriftMinDuration = 1.2,
	AirPerSecond = 45,
	AirMinDuration = 0.9,
	SpeedTrapThresholds = { 120, 160, 200, 240 }, -- studs/s
	SpeedTrapRewards = { 300, 700, 1500, 3000 },
	MaxPerMinute = 12000, -- hard cap on passive earnings (distance/drift/air)
}

Config.Daily = {
	Base = 2000,
	StreakBonus = 750,
	MaxStreak = 7,
}

Config.Races = {
	CountdownSeconds = 3,
	CheckpointTimeout = 75, -- seconds without a checkpoint -> DNF
	FinishReward = 600,
	MedalRewards = { Gold = 3500, Silver = 1800, Bronze = 900 },
	RepeatMedalShare = 0.25, -- medals already earned pay this share again
}

-- Upgrades: level 0..MaxLevel, price for level n is Prices[n]
Config.Upgrades = {
	Engine = {
		MaxLevel = 5,
		Prices = { 2500, 6000, 12000, 22000, 40000 },
		MaxSpeedPerLevel = 0.045,
		AccelPerLevel = 0.07,
	},
	Tires = {
		MaxLevel = 5,
		Prices = { 1500, 4000, 8500, 15000, 26000 },
		GripPerLevel = 0.045,
		OffroadPerLevel = 0.04,
	},
	Nitro = {
		MaxLevel = 5,
		Prices = { 2000, 5000, 10000, 18000, 32000 },
		PowerPerLevel = 0.08,
		RechargePerLevel = 0.12,
	},
}
Config.UpgradePriceScale = { -- multiplier by car class so hypercars cost more to tune
	Starter = 0.6,
	Street = 0.8,
	Utility = 0.8,
	Offroad = 1.0,
	Sport = 1.0,
	Muscle = 1.0,
	Emergency = 1.1,
	Super = 1.6,
	Hyper = 2.4,
	Special = 1.4,
}

Config.Customization = {
	PaintPrice = 400,
	AccentPrice = 250,
	RimPrice = 300,
	UnderglowPrice = 2500, -- first time; changing color after that costs PaintPrice
	FinishPrices = { Gloss = 0, Matte = 1200, Metallic = 2500, Pearl = 4000, Chrome = 9000, Neon = 15000 },
}

-- World ---------------------------------------------------------------------
Config.DayNight = {
	Enabled = true,
	MinutesPerDay = 18, -- real minutes for a full 24h cycle
	StartClock = 13.5,
	NightStart = 18.4,
	NightEnd = 6.2,
}

Config.Leaderboards = {
	RefreshInterval = 120,
	Size = 10,
}

-- UI ------------------------------------------------------------------------
Config.Language = "auto" -- "auto" (by player locale), "ru" or "en"

Config.Keys = {
	Handbrake = { Enum.KeyCode.Space, Enum.KeyCode.ButtonX },
	Nitro = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR1 },
	Flip = { Enum.KeyCode.R, Enum.KeyCode.DPadUp },
	Lights = { Enum.KeyCode.L, Enum.KeyCode.DPadRight },
	Siren = { Enum.KeyCode.K, Enum.KeyCode.DPadLeft },
	Horn = { Enum.KeyCode.H, Enum.KeyCode.ButtonL3 },
	Exit = { Enum.KeyCode.F, Enum.KeyCode.ButtonB },
	Garage = { Enum.KeyCode.G, Enum.KeyCode.ButtonSelect },
	Camera = { Enum.KeyCode.V, Enum.KeyCode.ButtonR3 },
}

-- Optional sounds. Paste asset ids ("rbxassetid://123") from the Creator Store.
-- Empty strings are skipped, so the game works without any audio.
Config.Sounds = {
	Engine = "", -- looped engine tone, pitch follows RPM
	Horn = "",
	Siren = "",
	Nitro = "",
	Skid = "",
	Checkpoint = "",
	Countdown = "",
	Finish = "",
	Purchase = "",
}

return Config
