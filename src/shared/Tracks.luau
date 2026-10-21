-- Tracks: race routes. The World builds roads for "road"/"dirt" surfaces from
-- these points; RaceService turns them into checkpoints.
-- Coordinates are world studs (y = 0 is ground level, -Z is north).

local Tracks = {}

export type Track = {
	id: string,
	name: { ru: string, en: string },
	kind: "circuit" | "sprint",
	laps: number,
	surface: "road" | "dirt" | "existing",
	width: number,
	points: { Vector3 },
	checkpointSpacing: number, -- studs between checkpoints along the spline
	medalSpeeds: { gold: number, silver: number, bronze: number }, -- average studs/s
	hub: Vector3, -- start pad in the plaza race hub
}

local function v(x: number, z: number): Vector3
	return Vector3.new(x, 0, z)
end

Tracks.List = {
	{
		id = "circuit",
		name = { ru = "Гран-при", en = "Grand Circuit" },
		kind = "circuit",
		laps = 2,
		surface = "road",
		width = 48,
		points = {
			v(1000, -300),
			v(1350, -300),
			v(1640, -330),
			v(1760, -480),
			v(1760, -760),
			v(1640, -900),
			v(1470, -920),
			v(1360, -1020),
			v(1350, -1180),
			v(1200, -1290),
			v(960, -1270),
			v(850, -1120),
			v(940, -980),
			v(1060, -870),
			v(980, -720),
			v(860, -560),
			v(880, -400),
		},
		checkpointSpacing = 280,
		medalSpeeds = { gold = 125, silver = 100, bronze = 75 },
		hub = Vector3.new(145, 0, -82),
	},
	{
		id = "city",
		name = { ru = "Городской спринт", en = "City Sprint" },
		kind = "sprint",
		laps = 1,
		surface = "existing",
		width = 44,
		points = {
			v(0, -180),
			v(0, -450),
			v(0, -800),
			v(350, -800),
			v(700, -800),
			v(700, -1150),
			v(350, -1150),
			v(0, -1150),
			v(-350, -1150),
			v(-350, -1500),
			v(-700, -1500),
			v(-700, -800),
			v(-700, -450),
			v(-350, -450),
		},
		checkpointSpacing = 0, -- one checkpoint per point (street corners)
		medalSpeeds = { gold = 95, silver = 75, bronze = 55 },
		hub = Vector3.new(115, 0, -82),
	},
	{
		id = "trail",
		name = { ru = "Тропа дюн", en = "Dune Trail" },
		kind = "sprint",
		laps = 1,
		surface = "dirt",
		width = 36,
		points = {
			v(-1000, 485),
			v(-1000, 640),
			v(-900, 800),
			v(-680, 880),
			v(-500, 840),
			v(-300, 1000),
			v(-420, 1260),
			v(-180, 1460),
			v(120, 1400),
			v(300, 1180),
			v(560, 1260),
			v(760, 1500),
			v(1020, 1400),
			v(1140, 1120),
			v(1000, 880),
			v(980, 660),
			v(980, 485),
		},
		checkpointSpacing = 260,
		medalSpeeds = { gold = 85, silver = 65, bronze = 48 },
		hub = Vector3.new(85, 0, -82),
	},
	{
		id = "highway",
		name = { ru = "Рывок по шоссе", en = "Highway Dash" },
		kind = "sprint",
		laps = 1,
		surface = "existing",
		width = 60,
		points = {
			v(-1760, 450),
			v(-900, 450),
			v(0, 450),
			v(900, 450),
			v(1760, 450),
		},
		checkpointSpacing = 0,
		medalSpeeds = { gold = 170, silver = 135, bronze = 100 },
		hub = Vector3.new(55, 0, -82),
	},
} :: { Track }

local byId: { [string]: Track } = {}
for _, t in Tracks.List do
	byId[t.id] = t
end

function Tracks.get(id: any): Track?
	if typeof(id) ~= "string" then
		return nil
	end
	return byId[id]
end

return Tracks
