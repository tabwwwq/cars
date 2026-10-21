-- Types: shared type definitions that cross the client/server boundary.

export type Localized = { ru: string, en: string }

export type DriveType = "RWD" | "FWD" | "AWD"

export type SuspensionSpec = {
	rest: number, -- spring travel in studs
	freq: number?, -- natural frequency (Hz)
	damping: number?, -- damping ratio
}

export type CarStats = {
	maxSpeed: number, -- studs/s
	accel: number, -- studs/s^2
	grip: number, -- tire friction coefficient (~1)
	steer: number, -- max steering angle, degrees
	brake: number, -- braking deceleration, studs/s^2
	drift: number, -- 0..1, how easily the rear lets go
	nitro: number, -- nitro power multiplier
	offroad: number, -- 0..1, how little rough surfaces slow the car
	mass: number, -- relative mass (1 = a normal car)
	drive: DriveType,
	suspension: SuspensionSpec,
}

export type AxleSpec = {
	z: number, -- axle position along the car (front is negative)
	steer: boolean,
	drive: boolean,
	radius: number?,
	width: number?,
	track: number?,
}

export type WheelSpec = {
	radius: number,
	width: number,
	base: number, -- wheelbase (front axle to rear axle)
	track: number, -- distance between left and right wheel centers
	offset: number?, -- shifts both axles along z
	rearRadius: number?,
	rearWidth: number?,
	rearTrack: number?,
	axles: { AxleSpec }?, -- full override (trucks with 3 axles, etc.)
	rim: string?, -- "steel" | "disc" | "spoke" | "star" | "offroad" | "aero"
}

export type CabinSpec = {
	start: number, -- distance from the front of the car to the windshield base
	wind: number, -- windshield length (z)
	roof: number, -- flat roof length (z)
	back: number, -- rear glass length (z); 0 = vertical back
	height: number, -- roof height above the belt line
	inset: number, -- glasshouse inset from the body sides
	open: boolean?, -- convertible
	sideWindows: number?, -- only the first N studs of the roof section are glass (vans)
	windowPillars: number?, -- spacing of pillars along long side windows (bus, limo)
	glassRoof: boolean?,
}

export type BodySpec = {
	style: string, -- "car" | "pickup" | "box" | "semi" | "openwheel" | "kart" | "buggy" | "tractor"
	length: number,
	width: number,
	floor: number, -- body bottom height
	belt: number, -- hood/shoulder height
	nose: number?,
	noseDrop: number?,
	tail: number?,
	tailDrop: number?,
	cabin: CabinSpec?,
	bed: { start: number }?,
	box: { start: number, top: number, length: number? }?,
}

export type CarColors = { paint: number, accent: number, rim: number }

export type SeatSpec = { x: number, z: number, y: number?, driver: boolean? }

export type CarDef = {
	id: string,
	name: string,
	class: string,
	price: number,
	description: Localized,
	stats: CarStats,
	wheels: WheelSpec,
	body: BodySpec,
	colors: CarColors,
	features: { [string]: any },
	seats: { SeatSpec }?,
	maxSeats: number?,
	-- optional: name of a template model in ReplicatedStorage.CarsAssets.Cars
	-- used as the visual body (see CarBuilder.findTemplate)
	customModel: string?,
}

-- Saved per-car customization and upgrades
export type CarSave = {
	paint: number,
	accent: number,
	rim: number,
	finish: string,
	glow: number, -- 0 = no underglow, otherwise palette index
	glowOwned: boolean,
	engine: number,
	tires: number,
	nitro: number,
}

export type Profile = {
	version: number,
	cash: number,
	owned: { [string]: boolean },
	cars: { [string]: CarSave },
	selected: string,
	bestTimes: { [string]: number },
	medals: { [string]: string },
	topSpeed: number,
	stats: {
		distance: number,
		drifts: number,
		airtime: number,
		races: number,
		earned: number,
	},
	daily: { last: number, streak: number },
	finishes: { [string]: boolean },
}

-- Effective (upgraded) stats the physics actually uses
export type EffectiveStats = {
	maxSpeed: number,
	accel: number,
	grip: number,
	steer: number,
	brake: number,
	drift: number,
	nitroPower: number,
	nitroRecharge: number,
	offroad: number,
	drive: DriveType,
	suspRest: number,
	suspFreq: number,
	suspDamping: number,
}

export type RequestResult = { ok: boolean, message: string?, args: { any }? }

return {}
