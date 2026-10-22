-- ServiceModels: procedural two-wheelers, quads, golf carts and people for the
-- car-service mode. Same conventions as CarBuilder: y = 0 is the ground, the
-- front is -Z, +X is right, cylinders have their axis along local X.
--
-- Every model has an invisible anchored "Root" part at the ground origin
-- (PrimaryPart), visual parts carry a "Role" attribute (Paint, Accent, Trim,
-- Dark, Chrome, Tire, Rim, Seat, Light, Taillight, Glass, ...) and wheel parts
-- carry Wheel/Radius/Width attributes like CarBuilder wheels.
-- People have limbs joined with Motor6Ds (Joint_<Limb>) for simple animation.

local Paints = require(script.Parent.Paints)

local ServiceModels = {}

export type Colors = { paint: number?, accent: number? }

type Ctx = {
	model: Model,
	root: BasePart,
	paint: Color3,
	accent: Color3,
}

local STYLE: { [string]: { Color3 | Enum.Material | number } } = {
	Trim = { Color3.fromRGB(44, 46, 52), Enum.Material.SmoothPlastic, 0 },
	Dark = { Color3.fromRGB(20, 20, 24), Enum.Material.SmoothPlastic, 0 },
	Chrome = { Color3.fromRGB(214, 218, 226), Enum.Material.Metal, 0.45 },
	Tire = { Color3.fromRGB(28, 28, 31), Enum.Material.SmoothPlastic, 0 },
	Rim = { Color3.fromRGB(186, 190, 198), Enum.Material.SmoothPlastic, 0.25 },
	Seat = { Color3.fromRGB(38, 34, 32), Enum.Material.Fabric, 0 },
	Light = { Color3.fromRGB(255, 250, 230), Enum.Material.Neon, 0 },
	Taillight = { Color3.fromRGB(170, 12, 18), Enum.Material.Neon, 0 },
	Indicator = { Color3.fromRGB(255, 150, 24), Enum.Material.Neon, 0 },
	Glass = { Color3.fromRGB(60, 84, 110), Enum.Material.Glass, 0.2 },
	White = { Color3.fromRGB(242, 242, 244), Enum.Material.SmoothPlastic, 0 },
	Basket = { Color3.fromRGB(156, 110, 62), Enum.Material.WoodPlanks, 0 },
	-- people
	Skin = { Color3.fromRGB(234, 184, 146), Enum.Material.SmoothPlastic, 0 },
	Hair = { Color3.fromRGB(70, 46, 30), Enum.Material.SmoothPlastic, 0 },
	Shirt = { Color3.fromRGB(240, 240, 236), Enum.Material.Fabric, 0 },
	Overalls = { Color3.fromRGB(40, 88, 170), Enum.Material.Fabric, 0 },
	Shoe = { Color3.fromRGB(40, 32, 28), Enum.Material.SmoothPlastic, 0 },
	Cap = { Color3.fromRGB(255, 128, 32), Enum.Material.Fabric, 0 },
	Face = { Color3.fromRGB(30, 24, 22), Enum.Material.SmoothPlastic, 0 },
}

--------------------------------------------------------------------------------
-- Part helpers
--------------------------------------------------------------------------------

local function style(ctx: Ctx, part: BasePart, role: string)
	if role == "Paint" then
		part.Color = ctx.paint
		part.Material = Enum.Material.SmoothPlastic
		part.Reflectance = 0.1
	elseif role == "Accent" then
		part.Color = ctx.accent
		part.Material = Enum.Material.SmoothPlastic
		part.Reflectance = 0.05
	elseif role == "NeonAccent" then
		part.Color = ctx.accent
		part.Material = Enum.Material.Neon
	else
		local s = STYLE[role]
		if s then
			part.Color = s[1] :: Color3
			part.Material = s[2] :: Enum.Material
			part.Reflectance = s[3] :: number
			if role == "Glass" then
				part.Transparency = 0.35
			end
		end
	end
end

local function make(ctx: Ctx, className: string, role: string, size: Vector3, cf: CFrame): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = role
	part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = size.X * size.Y * size.Z > 0.05
	part:SetAttribute("Role", role)
	style(ctx, part, role)
	part.Parent = ctx.model
	return part
end

local function box(ctx: Ctx, role: string, size: Vector3, at: Vector3 | CFrame): BasePart
	return make(ctx, "Part", role, size, if typeof(at) == "CFrame" then at else CFrame.new(at))
end

local function cyl(ctx: Ctx, role: string, length: number, diameter: number, cf: CFrame): BasePart
	local p = make(ctx, "Part", role, Vector3.new(length, diameter, diameter), cf);
	(p :: Part).Shape = Enum.PartType.Cylinder
	return p
end

local function ball(ctx: Ctx, role: string, diameter: number, pos: Vector3): BasePart
	local p = make(ctx, "Part", role, Vector3.new(diameter, diameter, diameter), CFrame.new(pos));
	(p :: Part).Shape = Enum.PartType.Ball
	return p
end

-- Wedge whose slope rises from -Z (low) to +Z (high) in the given frame.
local function wedge(ctx: Ctx, role: string, size: Vector3, cf: CFrame): BasePart
	return make(ctx, "WedgePart", role, size, cf)
end

-- CFrame at the middle of a..b whose X axis points from a to b.
local function alongX(a: Vector3, b: Vector3): CFrame
	local dir = (b - a).Unit
	local up = if math.abs(dir.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
	local z = dir:Cross(up).Unit
	local y = z:Cross(dir).Unit
	return CFrame.fromMatrix((a + b) / 2, dir, y, z)
end
ServiceModels.alongX = alongX

-- Round tube from a to b.
local function tube(ctx: Ctx, role: string, a: Vector3, b: Vector3, d: number): BasePart?
	local len = (b - a).Magnitude
	if len < 0.02 then
		return nil
	end
	return cyl(ctx, role, len + d * 0.3, d, alongX(a, b))
end

-- Polyline of tubes.
local function path(ctx: Ctx, role: string, points: { Vector3 }, d: number)
	for i = 1, #points - 1 do
		tube(ctx, role, points[i], points[i + 1], d)
		if i > 1 then
			ball(ctx, role, d, points[i])
		end
	end
end

-- Arc of blocks around an axis along X through `center`. Angles start at the
-- top (+Y) and grow towards the rear (+Z).
local function arc(ctx: Ctx, role: string, center: Vector3, radius: number, a0: number, a1: number, n: number, width: number, thick: number)
	local step = (a1 - a0) / n
	local seg = radius * math.abs(step) * 1.12
	for k = 0, n - 1 do
		local a = a0 + step * (k + 0.5)
		box(ctx, role, Vector3.new(width, thick, seg), CFrame.new(center) * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius, 0))
	end
end

local function p(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function markWheel(part: BasePart, radius: number, width: number)
	part:SetAttribute("Wheel", true)
	part:SetAttribute("Radius", radius)
	part:SetAttribute("Width", width)
end

type WheelStyle = "spoke" | "solid" | "knobby" | "small"

local function wheel(ctx: Ctx, center: Vector3, r: number, w: number, kind: WheelStyle, tubeThick: number?)
	if kind == "spoke" then
		local thick = tubeThick or 0.2
		local n = if r > 1 then 18 else 14
		arc(ctx, "Tire", center, r - thick / 2, 0, math.pi * 2, n, w, thick)
		arc(ctx, "Rim", center, r - thick - 0.04, 0, math.pi * 2, n, w * 0.7, 0.08)
		for k = 0, 5 do
			box(ctx, "Chrome", Vector3.new(0.035, (r - thick) * 2, 0.035), CFrame.new(center) * CFrame.Angles(k * math.pi / 6, 0, 0))
		end
		local hub = cyl(ctx, "Chrome", w + 0.12, 0.28, CFrame.new(center))
		markWheel(hub, r, w)
		return hub
	end
	local tire = cyl(ctx, "Tire", w, r * 2, CFrame.new(center))
	markWheel(tire, r, w)
	local rimD = r * 2 * (if kind == "small" then 0.5 else 0.6)
	cyl(ctx, "Rim", w + 0.04, rimD, CFrame.new(center))
	cyl(ctx, "Chrome", w + 0.1, math.max(0.18, r * 0.25), CFrame.new(center))
	if kind == "knobby" then
		for k = 0, 13 do
			box(ctx, "Tire", Vector3.new(w * 1.06, 0.14, r * 0.3), CFrame.new(center) * CFrame.Angles(k * math.pi / 7, 0, 0) * CFrame.new(0, r - 0.03, 0))
		end
	elseif kind == "solid" then
		for k = 0, 4 do
			box(ctx, "Rim", Vector3.new(w + 0.06, rimD * 0.42, 0.12), CFrame.new(center) * CFrame.Angles(k * math.pi * 2 / 5, 0, 0) * CFrame.new(0, rimD * 0.22, 0))
		end
	end
	return tire
end

--------------------------------------------------------------------------------
-- Bicycles
--------------------------------------------------------------------------------

type BikeSpec = {
	r: number,
	tire: number,
	base: number, -- half wheelbase
	bb: Vector3, -- bottom bracket (x = 0)
	seat: Vector3, -- top of the seat tube
	headTop: Vector3,
	headBottom: Vector3,
	stepThrough: boolean?,
	bar: "upright" | "flat" | "drop" | "bmx",
	fenders: boolean?,
	basket: boolean?,
	rack: boolean?,
	suspension: boolean?,
	discs: boolean?,
	training: boolean?,
	pegs: boolean?,
	lamp: boolean?,
	streamers: boolean?,
	tubeD: number?,
}

local function bicycle(ctx: Ctx, s: BikeSpec)
	local r = s.r
	local R = p(0, r, s.base)
	local F = p(0, r, -s.base)
	local BB, S, HT, HB = s.bb, s.seat, s.headTop, s.headBottom
	local d = s.tubeD or 0.2

	wheel(ctx, R, r, s.tire, "spoke", s.tire)
	wheel(ctx, F, r, s.tire, "spoke", s.tire)

	-- frame
	tube(ctx, "Paint", BB, S, d)
	tube(ctx, "Paint", HB, HT, d * 1.3)
	if s.stepThrough then
		local low = p(0, BB.Y + 0.3, (BB.Z + HB.Z) / 2 - 0.2)
		path(ctx, "Paint", { BB, low, HB }, d * 1.1)
		path(ctx, "Paint", { BB:Lerp(S, 0.45), low:Lerp(HB, 0.45) + p(0, 0.35, 0), HB:Lerp(HT, 0.6) }, d * 0.9)
	else
		tube(ctx, "Paint", BB, HB, d * 1.1)
		tube(ctx, "Paint", S:Lerp(BB, 0.08), HT:Lerp(HB, 0.15), d)
	end
	for _, side in { -1, 1 } do
		tube(ctx, "Paint", BB + p(side * 0.06, 0, 0), R + p(side * 0.16, 0, 0), d * 0.6)
		tube(ctx, "Paint", S:Lerp(BB, 0.1) + p(side * 0.05, 0, 0), R + p(side * 0.16, 0, 0), d * 0.6)
		if s.suspension then
			local mid = HB:Lerp(F, 0.5)
			tube(ctx, "Dark", HB + p(side * 0.16, 0, 0), mid + p(side * 0.2, 0, 0), 0.26)
			tube(ctx, "Chrome", mid + p(side * 0.2, 0, 0), F + p(side * 0.2, 0, 0), 0.16)
		else
			tube(ctx, "Paint", HB + p(side * 0.12, 0, 0), F + p(side * 0.17, 0, 0), d * 0.7)
		end
	end
	if s.suspension then
		box(ctx, "Dark", Vector3.new(0.5, 0.14, 0.3), HB:Lerp(F, 0.05))
	end

	-- saddle
	local postTop = S + (S - BB).Unit * 0.45
	tube(ctx, "Chrome", S, postTop, 0.12)
	box(ctx, "Seat", Vector3.new(0.5, 0.16, 0.55), postTop + p(0, 0.1, 0.12))
	box(ctx, "Seat", Vector3.new(0.24, 0.13, 0.5), postTop + p(0, 0.1, -0.35))

	-- bars
	local stemTop = HT + p(0, 0.35, -0.12)
	tube(ctx, "Chrome", HT, stemTop, 0.13)
	if s.bar == "upright" then
		path(ctx, "Chrome", { stemTop + p(-0.95, 0.05, 0.4), stemTop + p(-0.4, 0, 0), stemTop + p(0.4, 0, 0), stemTop + p(0.95, 0.05, 0.4) }, 0.1)
		for _, side in { -1, 1 } do
			tube(ctx, "Dark", stemTop + p(side * 0.8, 0.04, 0.32), stemTop + p(side * 1.05, 0.06, 0.45), 0.16)
		end
	elseif s.bar == "flat" then
		tube(ctx, "Dark", stemTop + p(-1.05, 0, 0), stemTop + p(1.05, 0, 0), 0.1)
		for _, side in { -1, 1 } do
			tube(ctx, "Dark", stemTop + p(side * 0.8, 0, 0), stemTop + p(side * 1.08, 0, 0), 0.17)
			box(ctx, "Trim", Vector3.new(0.08, 0.06, 0.4), stemTop + p(side * 0.7, 0.02, -0.2))
		end
	elseif s.bar == "drop" then
		tube(ctx, "Dark", stemTop + p(-0.6, 0, 0), stemTop + p(0.6, 0, 0), 0.11)
		for _, side in { -1, 1 } do
			path(ctx, "Dark", {
				stemTop + p(side * 0.6, 0, 0),
				stemTop + p(side * 0.62, -0.05, -0.35),
				stemTop + p(side * 0.62, -0.45, -0.32),
				stemTop + p(side * 0.62, -0.55, 0.05),
			}, 0.12)
			box(ctx, "Trim", Vector3.new(0.1, 0.3, 0.12), stemTop + p(side * 0.62, -0.12, -0.38))
		end
	else -- bmx
		for _, side in { -1, 1 } do
			tube(ctx, "Chrome", stemTop + p(side * 0.2, 0, 0), stemTop + p(side * 0.5, 0.65, 0.12), 0.1)
			tube(ctx, "Dark", stemTop + p(side * 0.8, 0.65, 0.12), stemTop + p(side * 1.05, 0.65, 0.12), 0.18)
		end
		tube(ctx, "Chrome", stemTop + p(-0.35, 0.35, 0.06), stemTop + p(0.35, 0.35, 0.06), 0.08)
		tube(ctx, "Chrome", stemTop + p(-1.0, 0.65, 0.12), stemTop + p(1.0, 0.65, 0.12), 0.1)
		box(ctx, "Accent", Vector3.new(0.6, 0.18, 0.18), stemTop + p(0, 0.35, 0.06))
	end
	if s.streamers then
		for _, side in { -1, 1 } do
			for k = -1, 1 do
				box(ctx, "NeonAccent", Vector3.new(0.04, 0.7, 0.06), stemTop + p(side * (1.08 + k * 0.04), -0.32, 0.45 + k * 0.05))
			end
		end
	end

	-- drivetrain
	local ringD = math.max(0.6, r * 0.62)
	cyl(ctx, "Chrome", 0.06, ringD, CFrame.new(BB + p(0.22, 0, 0)))
	cyl(ctx, "Dark", 0.08, ringD * 0.45, CFrame.new(BB + p(0.24, 0, 0)))
	cyl(ctx, "Chrome", 0.06, ringD * 0.45, CFrame.new(R + p(0.22, 0, 0)))
	tube(ctx, "Dark", BB + p(0.24, ringD / 2, 0), R + p(0.24, ringD * 0.22, 0), 0.05)
	tube(ctx, "Dark", BB + p(0.24, -ringD / 2, 0), R + p(0.24, -ringD * 0.22, 0), 0.05)
	local crank = r * 0.42
	for _, side in { -1, 1 } do
		local tip = BB + p(side * 0.32, -side * crank * 0.5, side * crank * 0.86)
		tube(ctx, "Trim", BB + p(side * 0.3, 0, 0), tip, 0.09)
		box(ctx, "Dark", Vector3.new(0.4, 0.07, 0.24), tip + p(side * 0.2, 0, 0))
	end

	-- extras
	if s.fenders then
		arc(ctx, "Accent", F, r + 0.15, -1.9, 0.5, 7, s.tire + 0.14, 0.06)
		arc(ctx, "Accent", R, r + 0.15, -0.35, 1.9, 7, s.tire + 0.14, 0.06)
	end
	if s.basket then
		local c = F + p(0, r + 0.75, -0.15)
		box(ctx, "Basket", Vector3.new(1.1, 0.06, 0.85), c - p(0, 0.32, 0))
		for _, side in { -1, 1 } do
			box(ctx, "Basket", Vector3.new(0.06, 0.65, 0.85), c + p(side * 0.55, 0, 0))
			box(ctx, "Basket", Vector3.new(1.1, 0.65, 0.06), c + p(0, 0, side * 0.42))
		end
		tube(ctx, "Trim", c - p(0, 0.34, 0), HB, 0.06)
	end
	if s.rack then
		local top = R + p(0, r + 0.32, -0.05)
		box(ctx, "Trim", Vector3.new(0.65, 0.06, 1.3), top)
		for _, side in { -1, 1 } do
			tube(ctx, "Trim", top + p(side * 0.3, 0, 0.45), R + p(side * 0.18, 0, 0), 0.06)
		end
		box(ctx, "Taillight", Vector3.new(0.3, 0.14, 0.06), top + p(0, -0.05, 0.68))
	else
		box(ctx, "Taillight", Vector3.new(0.18, 0.12, 0.06), S:Lerp(BB, 0.05) + p(0, 0, 0.14))
	end
	if s.lamp then
		local at = HT:Lerp(HB, 0.4) + p(0, 0, -0.2)
		cyl(ctx, "Trim", 0.22, 0.3, CFrame.new(at) * CFrame.Angles(0, math.pi / 2, 0))
		ball(ctx, "Light", 0.24, at + p(0, 0, -0.1))
		ball(ctx, "Chrome", 0.16, stemTop + p(-0.55, 0.12, 0.05))
	end
	if s.discs then
		for _, c in { F, R } do
			cyl(ctx, "Chrome", 0.03, r * 0.5, CFrame.new(c + p(-0.2, 0, 0)))
			box(ctx, "Dark", Vector3.new(0.1, 0.25, 0.3), c + p(-0.22, r * 0.25, -0.12))
		end
		cyl(ctx, "Dark", 0.5, 0.2, alongX(BB:Lerp(HB, 0.3), BB:Lerp(HB, 0.6)) * CFrame.new(0, 0.14, 0))
	end
	if s.training then
		for _, side in { -1, 1 } do
			local c = R + p(side * 0.85, -r + 0.32, 0.15)
			wheel(ctx, c, 0.32, 0.14, "small")
			tube(ctx, "Chrome", c, R + p(side * 0.18, 0, 0), 0.07)
		end
	end
	if s.pegs then
		for _, c in { F, R } do
			cyl(ctx, "Chrome", 0.9, 0.14, CFrame.new(c))
		end
	end
	-- kickstand
	tube(ctx, "Trim", BB:Lerp(R, 0.35) + p(-0.15, 0, 0), BB:Lerp(R, 0.15) + p(-0.55, -BB.Y + 0.05, 0), 0.07)
end

local function citybike(ctx: Ctx)
	bicycle(ctx, {
		r = 1.25,
		tire = 0.2,
		base = 2.05,
		bb = p(0, 0.95, 0.3),
		seat = p(0, 2.95, 0.85),
		headTop = p(0, 3.35, -1.35),
		headBottom = p(0, 2.55, -1.55),
		stepThrough = true,
		bar = "upright",
		fenders = true,
		basket = true,
		rack = true,
		lamp = true,
	})
end

local function mtb(ctx: Ctx)
	bicycle(ctx, {
		r = 1.3,
		tire = 0.34,
		base = 2.15,
		bb = p(0, 1.1, 0.25),
		seat = p(0, 2.85, 0.75),
		headTop = p(0, 3.25, -1.4),
		headBottom = p(0, 2.55, -1.6),
		bar = "flat",
		suspension = true,
		discs = true,
		tubeD = 0.26,
	})
end

local function bmx(ctx: Ctx)
	bicycle(ctx, {
		r = 0.95,
		tire = 0.3,
		base = 1.65,
		bb = p(0, 0.85, 0.2),
		seat = p(0, 2.2, 0.55),
		headTop = p(0, 2.6, -1.1),
		headBottom = p(0, 2.05, -1.25),
		bar = "bmx",
		pegs = true,
		tubeD = 0.24,
	})
end

local function roadbike(ctx: Ctx)
	bicycle(ctx, {
		r = 1.3,
		tire = 0.15,
		base = 2.0,
		bb = p(0, 0.95, 0.3),
		seat = p(0, 3.05, 0.95),
		headTop = p(0, 3.25, -1.3),
		headBottom = p(0, 2.65, -1.45),
		bar = "drop",
		tubeD = 0.18,
	})
end

local function kidsbike(ctx: Ctx)
	bicycle(ctx, {
		r = 0.85,
		tire = 0.22,
		base = 1.4,
		bb = p(0, 0.7, 0.2),
		seat = p(0, 1.9, 0.55),
		headTop = p(0, 2.2, -0.9),
		headBottom = p(0, 1.7, -1.05),
		stepThrough = true,
		bar = "upright",
		fenders = true,
		basket = true,
		training = true,
		streamers = true,
		tubeD = 0.18,
	})
end

--------------------------------------------------------------------------------
-- Scooters
--------------------------------------------------------------------------------

local function kickscooter(ctx: Ctx)
	local r = 0.42
	wheel(ctx, p(0, r, -1.65), r, 0.24, "small")
	wheel(ctx, p(0, r, 1.6), r, 0.24, "small")
	box(ctx, "Paint", Vector3.new(0.62, 0.16, 2.5), p(0, 0.55, 0.1))
	box(ctx, "Dark", Vector3.new(0.56, 0.03, 2.3), p(0, 0.645, 0.1))
	arc(ctx, "Trim", p(0, r, 1.6), r + 0.1, -0.6, 1.4, 4, 0.3, 0.05)
	tube(ctx, "Paint", p(0, 0.55, -1.15), p(0, 0.9, -1.55), 0.22)
	local base = p(0, 0.95, -1.6)
	local top = p(0, 3.6, -1.95)
	tube(ctx, "Paint", base, top, 0.18)
	box(ctx, "Accent", Vector3.new(0.3, 0.3, 0.3), base:Lerp(top, 0.45))
	for _, side in { -1, 1 } do
		tube(ctx, "Chrome", base + p(side * 0.08, 0, 0), p(side * 0.16, r, -1.65), 0.09)
	end
	tube(ctx, "Chrome", top + p(-0.75, 0, 0), top + p(0.75, 0, 0), 0.1)
	for _, side in { -1, 1 } do
		tube(ctx, "Dark", top + p(side * 0.55, 0, 0), top + p(side * 0.8, 0, 0), 0.17)
	end
	box(ctx, "Trim", Vector3.new(0.08, 0.06, 0.35), top + p(0.5, 0.02, -0.18))
	tube(ctx, "Trim", p(-0.2, 0.5, 0.6), p(-0.45, 0.04, 0.9), 0.06)
end

local function escooter(ctx: Ctx)
	local r = 0.55
	wheel(ctx, p(0, r, -1.8), r, 0.3, "solid")
	wheel(ctx, p(0, r, 1.75), r, 0.3, "solid")
	box(ctx, "Paint", Vector3.new(0.78, 0.26, 2.6), p(0, 0.66, 0.05))
	box(ctx, "Dark", Vector3.new(0.7, 0.03, 2.4), p(0, 0.8, 0.05))
	box(ctx, "Trim", Vector3.new(0.6, 0.2, 2.2), p(0, 0.45, 0.05))
	for _, side in { -1, 1 } do
		box(ctx, "NeonAccent", Vector3.new(0.03, 0.06, 2.3), p(side * 0.4, 0.66, 0.05))
	end
	arc(ctx, "Paint", p(0, r, 1.75), r + 0.12, -0.5, 1.5, 4, 0.36, 0.07)
	box(ctx, "Taillight", Vector3.new(0.3, 0.1, 0.05), p(0, 1.05, 2.42))
	arc(ctx, "Paint", p(0, r, -1.8), r + 0.12, -1.3, 0.4, 4, 0.36, 0.07)
	tube(ctx, "Paint", p(0, 0.7, -1.2), p(0, 1.1, -1.6), 0.3)
	local base = p(0, 1.1, -1.62)
	local top = p(0, 3.75, -1.95)
	tube(ctx, "Paint", base, top, 0.26)
	cyl(ctx, "Chrome", 0.36, 0.34, CFrame.new(base:Lerp(top, 0.12)))
	for _, side in { -1, 1 } do
		tube(ctx, "Trim", base + p(side * 0.1, 0, 0), p(side * 0.2, r, -1.8), 0.12)
	end
	local lamp = base:Lerp(top, 0.55) + p(0, 0, -0.16)
	box(ctx, "Trim", Vector3.new(0.3, 0.22, 0.12), lamp)
	box(ctx, "Light", Vector3.new(0.22, 0.12, 0.04), lamp + p(0, 0, -0.07))
	tube(ctx, "Trim", top + p(-0.8, 0, 0), top + p(0.8, 0, 0), 0.12)
	for _, side in { -1, 1 } do
		tube(ctx, "Dark", top + p(side * 0.58, 0, 0), top + p(side * 0.85, 0, 0), 0.18)
	end
	box(ctx, "Dark", Vector3.new(0.5, 0.08, 0.3), top + p(0, 0.08, 0.02))
	box(ctx, "NeonAccent", Vector3.new(0.36, 0.02, 0.18), top + p(0, 0.13, 0.02))
end

--------------------------------------------------------------------------------
-- Mopeds
--------------------------------------------------------------------------------

local function moped(ctx: Ctx, delivery: boolean)
	local r = 0.78
	local front, rear = -2.15, 2.0
	wheel(ctx, p(0, r, front), r, 0.42, "solid")
	wheel(ctx, p(0, r, rear), r, 0.46, "solid")
	-- floor and leg shield
	box(ctx, "Paint", Vector3.new(1.25, 0.22, 1.9), p(0, 0.95, -0.25))
	box(ctx, "Dark", Vector3.new(1.1, 0.03, 1.7), p(0, 1.07, -0.25))
	box(ctx, "Paint", Vector3.new(1.5, 2.0, 0.22), CFrame.new(0, 2.0, -1.3) * CFrame.Angles(math.rad(10), 0, 0))
	for _, side in { -1, 1 } do
		cyl(ctx, "Paint", 2.0, 0.3, CFrame.new(side * 0.72, 2.0, -1.3) * CFrame.Angles(math.rad(10), 0, 0) * CFrame.Angles(0, 0, math.pi / 2))
	end
	box(ctx, "Chrome", Vector3.new(1.5, 0.06, 0.26), CFrame.new(0, 3.0, -1.12) * CFrame.Angles(math.rad(10), 0, 0))
	-- steering head and handlebar cover
	box(ctx, "Paint", Vector3.new(0.5, 1.1, 0.45), p(0, 2.7, -1.62))
	box(ctx, "Paint", Vector3.new(1.45, 0.38, 0.55), p(0, 3.3, -1.6))
	cyl(ctx, "Trim", 0.18, 0.55, CFrame.new(0, 3.33, -1.92) * CFrame.Angles(0, math.pi / 2, 0))
	cyl(ctx, "Light", 0.06, 0.44, CFrame.new(0, 3.33, -2.02) * CFrame.Angles(0, math.pi / 2, 0))
	box(ctx, "Dark", Vector3.new(0.4, 0.06, 0.3), p(0, 3.5, -1.5))
	for _, side in { -1, 1 } do
		tube(ctx, "Dark", p(side * 0.7, 3.32, -1.58), p(side * 0.98, 3.32, -1.55), 0.17)
		tube(ctx, "Chrome", p(side * 0.55, 3.45, -1.6), p(side * 0.8, 3.95, -1.62), 0.05)
		cyl(ctx, "Chrome", 0.06, 0.28, CFrame.new(side * 0.82, 4.02, -1.62) * CFrame.Angles(0, math.pi / 2, 0))
		box(ctx, "Indicator", Vector3.new(0.12, 0.08, 0.06), p(side * 0.66, 3.27, -1.9))
	end
	-- front fender and fork (single sided)
	arc(ctx, "Paint", p(0, r, front), r + 0.12, -1.1, 0.9, 5, 0.6, 0.1)
	tube(ctx, "Trim", p(0.25, 2.2, -1.68), p(0.3, r, front), 0.2)
	-- rear body
	cyl(ctx, "Paint", 1.95, 1.35, CFrame.new(0, 1.55, 1.45) * CFrame.Angles(0, math.pi / 2, 0))
	box(ctx, "Paint", Vector3.new(1.35, 0.7, 1.9), p(0, 1.9, 1.45))
	for _, side in { -1, 1 } do
		ball(ctx, "Paint", 1.15, p(side * 0.42, 1.48, 1.55))
	end
	box(ctx, "Seat", Vector3.new(0.92, 0.32, 1.75), p(0, 2.38, 1.05))
	box(ctx, "Seat", Vector3.new(0.7, 0.28, 0.4), p(0, 2.34, 0.05))
	box(ctx, "Chrome", Vector3.new(1.0, 0.05, 0.08), p(0, 2.3, 1.95))
	box(ctx, "Taillight", Vector3.new(0.5, 0.18, 0.08), p(0, 1.95, 2.42))
	-- engine and exhaust
	box(ctx, "Dark", Vector3.new(0.5, 0.6, 1.1), p(0.3, 0.95, 1.45))
	cyl(ctx, "Chrome", 1.1, 0.26, CFrame.new(0.55, 0.75, 2.05) * CFrame.Angles(0, math.pi / 2, 0))
	tube(ctx, "Trim", p(-0.3, 0.8, 0.4), p(-0.45, 0.05, 0.75), 0.07)
	-- rack
	local rackY = 2.5
	box(ctx, "Chrome", Vector3.new(0.9, 0.05, 0.8), p(0, rackY, 2.15))
	if delivery then
		local c = p(0, rackY + 0.8, 2.15)
		box(ctx, "Accent", Vector3.new(1.6, 1.5, 1.4), c)
		box(ctx, "Paint", Vector3.new(1.64, 0.18, 1.44), c + p(0, 0.75, 0))
		for _, side in { -1, 1 } do
			cyl(ctx, "White", 0.04, 0.8, CFrame.new(c + p(side * 0.81, 0, 0)))
		end
		box(ctx, "Chrome", Vector3.new(0.5, 0.1, 0.05), c + p(0, 0.2, 0.71))
	end
end

--------------------------------------------------------------------------------
-- Motorcycles
--------------------------------------------------------------------------------

local function sportbike(ctx: Ctx)
	local rf, rr = 1.02, 1.04
	local zf, zr = -2.7, 2.55
	wheel(ctx, p(0, rf, zf), rf, 0.55, "solid")
	wheel(ctx, p(0, rr, zr), rr, 0.7, "solid")
	for _, side in { -1, 1 } do
		tube(ctx, "Trim", p(side * 0.42, 3.0, -1.7), p(side * 0.42, 1.6, 0.6), 0.28)
		tube(ctx, "Trim", p(side * 0.4, 1.5, 0.6), p(side * 0.4, rr, zr), 0.22)
		tube(ctx, "Dark", p(side * 0.3, 3.2, -1.78), p(side * 0.3, 2.1, -2.25), 0.26)
		tube(ctx, "Chrome", p(side * 0.3, 2.1, -2.25), p(side * 0.3, rf, zf), 0.18)
		tube(ctx, "Dark", p(side * 0.32, 3.38, -1.6), p(side * 0.62, 3.32, -1.5), 0.15)
		box(ctx, "Trim", Vector3.new(0.4, 0.08, 0.18), p(side * 0.45, 1.85, 0.75))
	end
	box(ctx, "Dark", Vector3.new(1.0, 1.0, 1.4), p(0, 1.65, -0.55))
	for k = -1, 1 do
		cyl(ctx, "Chrome", 0.2, 0.32, CFrame.new(k * 0.3, 2.2, -0.95) * CFrame.Angles(0, 0, math.pi / 2))
	end
	-- tank and fairing
	box(ctx, "Paint", Vector3.new(1.1, 0.72, 1.45), p(0, 3.15, -0.75))
	cyl(ctx, "Paint", 1.45, 1.1, CFrame.new(0, 3.42, -0.75) * CFrame.Angles(0, math.pi / 2, 0))
	box(ctx, "Paint", Vector3.new(1.2, 1.15, 0.75), p(0, 3.0, -2.0))
	wedge(ctx, "Paint", Vector3.new(1.2, 0.9, 0.85), CFrame.new(0, 3.12, -2.78))
	box(ctx, "Paint", Vector3.new(1.1, 0.45, 0.5), p(0, 2.3, -2.3))
	wedge(ctx, "Glass", Vector3.new(0.95, 0.55, 0.75), CFrame.new(0, 3.85, -2.05))
	for _, side in { -1, 1 } do
		box(ctx, "Paint", Vector3.new(0.1, 1.3, 2.1), p(side * 0.62, 2.25, -1.05))
		box(ctx, "Accent", Vector3.new(0.12, 0.25, 2.0), p(side * 0.63, 2.05, -1.05))
		box(ctx, "Light", Vector3.new(0.32, 0.18, 0.08), p(side * 0.27, 3.05, -3.2))
		tube(ctx, "Trim", p(side * 0.55, 3.55, -2.1), p(side * 0.85, 3.7, -2.0), 0.05)
		box(ctx, "Trim", Vector3.new(0.3, 0.16, 0.08), p(side * 0.92, 3.72, -2.0))
	end
	box(ctx, "Accent", Vector3.new(1.0, 0.25, 1.6), p(0, 1.1, -0.8))
	-- seat and tail
	box(ctx, "Seat", Vector3.new(0.85, 0.22, 1.1), p(0, 3.08, 0.5))
	wedge(ctx, "Paint", Vector3.new(0.95, 0.75, 1.7), CFrame.new(0, 3.05, 1.55))
	box(ctx, "Paint", Vector3.new(0.95, 0.35, 1.7), p(0, 2.55, 1.55))
	box(ctx, "Taillight", Vector3.new(0.45, 0.14, 0.06), p(0, 2.95, 2.42))
	box(ctx, "Dark", Vector3.new(0.7, 0.05, 0.6), CFrame.new(0, 2.3, 2.55) * CFrame.Angles(math.rad(-30), 0, 0))
	-- exhaust
	tube(ctx, "Chrome", p(0.35, 1.2, -0.3), p(0.55, 1.55, 1.1), 0.22)
	cyl(ctx, "Chrome", 1.2, 0.46, alongX(p(0.6, 1.6, 1.0), p(0.62, 2.05, 2.1)))
	arc(ctx, "Paint", p(0, rf, zf), rf + 0.12, -1.0, 0.5, 4, 0.5, 0.08)
end

local function chopper(ctx: Ctx)
	local rf, rr = 1.0, 1.15
	local zf, zr = -3.75, 2.3
	wheel(ctx, p(0, rf, zf), rf, 0.3, "solid")
	wheel(ctx, p(0, rr, zr), rr, 0.85, "solid")
	local head = p(0, 3.35, -1.85)
	path(ctx, "Paint", { head, p(0, 2.9, -0.6), p(0, 2.2, 0.8), p(0, rr + 0.2, zr) }, 0.24)
	for _, side in { -1, 1 } do
		path(ctx, "Paint", { head + p(side * 0.1, -0.2, 0), p(side * 0.35, 0.7, -0.8), p(side * 0.4, 0.75, 1.2), p(side * 0.42, rr, zr) }, 0.18)
		tube(ctx, "Chrome", head + p(side * 0.28, 0.25, -0.05), p(side * 0.3, rf, zf), 0.18)
		-- ape hangers
		path(ctx, "Chrome", { head + p(side * 0.25, 0.35, -0.1), head + p(side * 0.48, 1.55, 0.05), head + p(side * 0.8, 1.55, 0.3) }, 0.1)
		tube(ctx, "Dark", head + p(side * 0.75, 1.55, 0.28), head + p(side * 1.0, 1.55, 0.38), 0.17)
		-- exhausts
		path(ctx, "Chrome", { p(0.5, 1.5, -0.3), p(0.6, 1.0 + side * 0.18, 0.4), p(0.62, 1.15 + side * 0.18, 2.6) }, 0.2)
		box(ctx, "Chrome", Vector3.new(0.5, 0.06, 0.3), p(side * 0.55, 1.0, -1.5))
	end
	cyl(ctx, "Chrome", 0.7, 0.55, CFrame.new(head + p(0, 0.05, -0.35)) * CFrame.Angles(0, math.pi / 2, 0))
	cyl(ctx, "Light", 0.05, 0.46, CFrame.new(head + p(0, 0.05, -0.71)) * CFrame.Angles(0, math.pi / 2, 0))
	-- tank
	ball(ctx, "Paint", 1.0, p(0, 3.1, -1.2))
	cyl(ctx, "Paint", 1.0, 0.95, alongX(p(0, 3.1, -1.2), p(0, 2.95, -0.25)))
	box(ctx, "Accent", Vector3.new(0.12, 0.4, 0.9), p(0.47, 3.05, -0.75))
	box(ctx, "Accent", Vector3.new(0.12, 0.4, 0.9), p(-0.47, 3.05, -0.75))
	-- V-twin
	box(ctx, "Dark", Vector3.new(0.8, 0.8, 1.1), p(0, 1.2, -0.25))
	for _, ang in { -0.5, 0.5 } do
		local base = p(0, 1.5, -0.25)
		local top = base + p(0, math.cos(ang) * 1.2, math.sin(ang) * 1.2)
		tube(ctx, "Chrome", base, top, 0.6)
		for k = 1, 3 do
			cyl(ctx, "Chrome", 0.06, 0.75, alongX(base:Lerp(top, 0.25 * k), top))
		end
	end
	-- seat, sissy bar, fender
	box(ctx, "Seat", Vector3.new(1.0, 0.28, 1.25), p(0, 2.3, 0.75))
	box(ctx, "Seat", Vector3.new(0.6, 0.25, 0.6), p(0, 2.55, 1.35))
	path(ctx, "Chrome", { p(-0.45, 2.2, 1.6), p(-0.4, 3.9, 1.85), p(0.4, 3.9, 1.85), p(0.45, 2.2, 1.6) }, 0.1)
	arc(ctx, "Paint", p(0, rr, zr), rr + 0.15, -0.6, 1.7, 6, 0.95, 0.1)
	box(ctx, "Taillight", Vector3.new(0.4, 0.14, 0.08), p(0, 2.0, 3.45))
end

local function dirtbike(ctx: Ctx)
	local rf, rr = 1.2, 1.12
	local zf, zr = -2.75, 2.3
	wheel(ctx, p(0, rf, zf), rf, 0.4, "knobby")
	wheel(ctx, p(0, rr, zr), rr, 0.52, "knobby")
	for _, side in { -1, 1 } do
		tube(ctx, "Trim", p(side * 0.25, 3.3, -1.55), p(side * 0.3, 1.2, -0.3), 0.18)
		tube(ctx, "Trim", p(side * 0.3, 1.5, 0.4), p(side * 0.38, rr, zr), 0.2)
		tube(ctx, "Accent", p(side * 0.3, 3.4, -1.6), p(side * 0.3, 2.2, -2.2), 0.28)
		tube(ctx, "Chrome", p(side * 0.3, 2.2, -2.2), p(side * 0.3, rf, zf), 0.18)
	end
	box(ctx, "Dark", Vector3.new(0.75, 0.9, 1.0), p(0, 1.55, -0.2))
	cyl(ctx, "Chrome", 0.3, 0.45, CFrame.new(0, 2.15, -0.5) * CFrame.Angles(0, 0, math.pi / 2))
	box(ctx, "Paint", Vector3.new(1.0, 0.7, 1.15), p(0, 3.15, -0.9))
	for _, side in { -1, 1 } do
		wedge(ctx, "Paint", Vector3.new(0.12, 1.0, 1.0), CFrame.new(side * 0.55, 2.85, -1.25) * CFrame.Angles(0, math.pi, 0))
		box(ctx, "Paint", Vector3.new(0.1, 0.8, 1.2), p(side * 0.42, 2.85, 1.0))
	end
	box(ctx, "Seat", Vector3.new(0.7, 0.24, 2.6), CFrame.new(0, 3.45, 0.4) * CFrame.Angles(math.rad(-3), 0, 0))
	wedge(ctx, "Paint", Vector3.new(0.6, 0.5, 1.4), CFrame.new(0, 3.35, 2.4))
	box(ctx, "Taillight", Vector3.new(0.3, 0.1, 0.05), p(0, 3.3, 3.12))
	-- beak fender and plate
	box(ctx, "Paint", Vector3.new(0.6, 0.08, 1.7), CFrame.new(0, 3.05, -2.8) * CFrame.Angles(math.rad(8), 0, 0))
	box(ctx, "White", Vector3.new(1.0, 0.8, 0.08), CFrame.new(0, 3.55, -2.05) * CFrame.Angles(math.rad(-20), 0, 0))
	box(ctx, "Light", Vector3.new(0.3, 0.18, 0.04), CFrame.new(0, 3.45, -2.12) * CFrame.Angles(math.rad(-20), 0, 0))
	-- bars
	local bar = p(0, 4.0, -1.45)
	tube(ctx, "Dark", bar + p(-1.1, 0, 0), bar + p(1.1, 0, 0), 0.1)
	box(ctx, "Accent", Vector3.new(0.6, 0.16, 0.16), bar + p(0, 0.12, 0))
	for _, side in { -1, 1 } do
		tube(ctx, "Dark", bar + p(side * 0.85, 0, 0), bar + p(side * 1.12, 0, 0), 0.17)
	end
	tube(ctx, "Trim", bar, p(0, 3.4, -1.6), 0.15)
	-- high exhaust
	path(ctx, "Chrome", { p(0.2, 1.8, -0.7), p(0.45, 2.3, 0.2), p(0.5, 2.75, 1.4) }, 0.2)
	cyl(ctx, "Trim", 1.2, 0.4, alongX(p(0.5, 2.75, 1.4), p(0.5, 3.0, 2.55)))
end

local function classicbike(ctx: Ctx)
	local r = 1.05
	local zf, zr = -2.6, 2.4
	wheel(ctx, p(0, r, zf), r, 0.34, "spoke", 0.3)
	wheel(ctx, p(0, r, zr), r, 0.38, "spoke", 0.32)
	for _, side in { -1, 1 } do
		path(ctx, "Dark", { p(side * 0.2, 3.1, -1.65), p(side * 0.3, 1.1, -0.9), p(side * 0.35, 1.0, 1.1), p(side * 0.35, r, zr) }, 0.16)
		tube(ctx, "Dark", p(side * 0.3, 2.75, 1.0), p(side * 0.35, r, zr), 0.14)
		tube(ctx, "Chrome", p(side * 0.25, 3.15, -1.7), p(side * 0.3, r, zf), 0.17)
		tube(ctx, "Chrome", p(side * 0.42, 1.25, -0.3), p(side * 0.48, 1.25, 2.9), 0.24)
		cyl(ctx, "Chrome", 0.8, 0.34, CFrame.new(side * 0.48, 1.25, 2.6) * CFrame.Angles(0, math.pi / 2, 0))
	end
	tube(ctx, "Dark", p(0, 3.1, -1.65), p(0, 2.85, 0.9), 0.18)
	box(ctx, "Dark", Vector3.new(0.8, 0.8, 1.0), p(0, 1.4, -0.2))
	for _, z in { -0.45, 0.05 } do
		cyl(ctx, "Chrome", 0.9, 0.5, CFrame.new(0, 2.1, z) * CFrame.Angles(0, 0, math.pi / 2))
	end
	-- tank with stripe and knee pads
	box(ctx, "Paint", Vector3.new(0.95, 0.7, 1.4), p(0, 3.05, -0.85))
	cyl(ctx, "Paint", 1.4, 0.95, CFrame.new(0, 3.35, -0.85) * CFrame.Angles(0, math.pi / 2, 0))
	box(ctx, "Accent", Vector3.new(0.97, 0.12, 1.42), p(0, 3.1, -0.85))
	for _, side in { -1, 1 } do
		box(ctx, "Dark", Vector3.new(0.06, 0.35, 0.45), p(side * 0.48, 2.95, -0.4))
		box(ctx, "Paint", Vector3.new(0.12, 0.6, 0.75), p(side * 0.38, 2.3, 0.65))
	end
	box(ctx, "Seat", Vector3.new(0.85, 0.28, 1.8), p(0, 2.95, 0.7))
	arc(ctx, "Chrome", p(0, r, zf), r + 0.14, -1.2, 0.9, 6, 0.42, 0.06)
	arc(ctx, "Chrome", p(0, r, zr), r + 0.14, -0.5, 1.7, 6, 0.46, 0.06)
	-- headlight and gauges
	cyl(ctx, "Chrome", 0.45, 0.62, CFrame.new(0, 3.05, -2.05) * CFrame.Angles(0, math.pi / 2, 0))
	cyl(ctx, "Light", 0.05, 0.52, CFrame.new(0, 3.05, -2.29) * CFrame.Angles(0, math.pi / 2, 0))
	for _, side in { -1, 1 } do
		cyl(ctx, "Dark", 0.1, 0.24, CFrame.new(side * 0.18, 3.55, -1.65) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(25)))
	end
	path(ctx, "Chrome", { p(-0.95, 3.6, -1.35), p(-0.4, 3.5, -1.6), p(0.4, 3.5, -1.6), p(0.95, 3.6, -1.35) }, 0.1)
	for _, side in { -1, 1 } do
		tube(ctx, "Dark", p(side * 0.75, 3.58, -1.4), p(side * 1.0, 3.62, -1.3), 0.16)
	end
	box(ctx, "Taillight", Vector3.new(0.3, 0.16, 0.1), p(0, 1.95, 3.35))
end

--------------------------------------------------------------------------------
-- Quad bike and golf cart
--------------------------------------------------------------------------------

local function quad(ctx: Ctx)
	local r = 0.85
	for _, z in { -1.95, 2.0 } do
		for _, side in { -1, 1 } do
			wheel(ctx, p(side * 1.6, r, z), r, 0.85, "knobby")
		end
	end
	box(ctx, "Trim", Vector3.new(1.1, 0.5, 4.3), p(0, 1.05, 0))
	box(ctx, "Dark", Vector3.new(0.9, 0.8, 1.2), p(0, 1.35, 0.4))
	-- front body
	box(ctx, "Paint", Vector3.new(1.5, 0.6, 1.4), p(0, 2.05, -1.2))
	wedge(ctx, "Paint", Vector3.new(1.5, 0.5, 0.8), CFrame.new(0, 2.0, -2.2))
	for _, side in { -1, 1 } do
		box(ctx, "Paint", Vector3.new(1.05, 0.12, 2.0), CFrame.new(side * 1.45, 2.0, -1.9) * CFrame.Angles(0, 0, side * math.rad(-8)))
		box(ctx, "Paint", Vector3.new(1.05, 0.12, 2.0), CFrame.new(side * 1.45, 2.0, 2.0) * CFrame.Angles(0, 0, side * math.rad(-8)))
		box(ctx, "Light", Vector3.new(0.35, 0.2, 0.05), p(side * 0.45, 2.0, -2.62))
		box(ctx, "Taillight", Vector3.new(0.3, 0.14, 0.05), p(side * 0.5, 1.95, 2.85))
	end
	box(ctx, "Paint", Vector3.new(1.5, 0.55, 1.4), p(0, 2.0, 2.15))
	box(ctx, "Seat", Vector3.new(0.9, 0.35, 1.8), p(0, 2.48, 0.55))
	-- racks
	for _, z in { -2.25, 2.5 } do
		box(ctx, "Chrome", Vector3.new(1.4, 0.06, 0.9), p(0, 2.48, z))
		for _, side in { -1, 1 } do
			box(ctx, "Chrome", Vector3.new(0.06, 0.12, 0.9), p(side * 0.7, 2.56, z))
		end
	end
	-- bumpers
	box(ctx, "Dark", Vector3.new(1.6, 0.25, 0.2), p(0, 1.3, -2.75))
	box(ctx, "Dark", Vector3.new(1.6, 0.25, 0.2), p(0, 1.3, 2.95))
	-- steering
	tube(ctx, "Trim", p(0, 1.9, -0.95), p(0, 2.95, -0.75), 0.18)
	tube(ctx, "Dark", p(-0.95, 3.0, -0.7), p(0.95, 3.0, -0.7), 0.12)
	for _, side in { -1, 1 } do
		tube(ctx, "Dark", p(side * 0.7, 3.0, -0.7), p(side * 0.98, 3.0, -0.7), 0.18)
	end
	box(ctx, "Accent", Vector3.new(0.5, 0.18, 0.18), p(0, 3.05, -0.72))
end

local function golfcart(ctx: Ctx)
	local r = 0.62
	for _, z in { -2.4, 2.15 } do
		for _, side in { -1, 1 } do
			wheel(ctx, p(side * 1.62, r, z), r, 0.55, "solid")
		end
	end
	box(ctx, "Paint", Vector3.new(3.3, 0.85, 5.5), p(0, 1.2, 0))
	box(ctx, "Dark", Vector3.new(3.0, 0.05, 2.0), p(0, 1.65, -0.9))
	wedge(ctx, "Paint", Vector3.new(3.3, 1.2, 1.4), CFrame.new(0, 2.2, -2.15))
	box(ctx, "Trim", Vector3.new(3.1, 0.7, 0.3), p(0, 2.2, -1.35))
	for _, side in { -1, 1 } do
		box(ctx, "Light", Vector3.new(0.45, 0.22, 0.05), p(side * 1.0, 1.85, -2.77))
		box(ctx, "Taillight", Vector3.new(0.35, 0.18, 0.05), p(side * 1.3, 1.5, 2.77))
	end
	box(ctx, "Seat", Vector3.new(3.0, 0.4, 1.3), p(0, 2.25, 0.55))
	box(ctx, "Seat", Vector3.new(3.0, 1.2, 0.3), p(0, 2.95, 1.25))
	-- canopy
	box(ctx, "White", Vector3.new(3.6, 0.22, 4.7), p(0, 6.4, 0.35))
	box(ctx, "Accent", Vector3.new(3.65, 0.12, 4.75), p(0, 6.25, 0.35))
	for _, side in { -1, 1 } do
		tube(ctx, "Trim", p(side * 1.5, 1.7, -1.35), p(side * 1.5, 6.3, -1.75), 0.14)
		tube(ctx, "Trim", p(side * 1.5, 1.7, 1.4), p(side * 1.5, 6.3, 2.2), 0.14)
	end
	box(ctx, "Glass", Vector3.new(3.0, 2.1, 0.06), CFrame.new(0, 4.9, -1.62) * CFrame.Angles(math.rad(-5), 0, 0))
	-- steering wheel
	tube(ctx, "Trim", p(-0.75, 2.2, -1.25), p(-0.75, 3.15, -0.85), 0.1)
	cyl(ctx, "Dark", 0.1, 0.9, CFrame.new(-0.75, 3.2, -0.82) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(55)))
	-- golf bags
	box(ctx, "Trim", Vector3.new(2.6, 0.12, 1.0), p(0, 1.85, 3.1))
	for i, x in { -0.6, 0.6 } do
		local base = p(x, 1.95, 3.15)
		local top = base + p(0, 2.3, 0.35)
		tube(ctx, if i == 1 then "Accent" else "Paint", base, top, 0.75)
		for k = -1, 1 do
			tube(ctx, "Chrome", top + p(k * 0.15, 0, 0), top + p(k * 0.18, 0.6, 0.12), 0.06)
			box(ctx, "Dark", Vector3.new(0.16, 0.12, 0.26), top + p(k * 0.18, 0.66, 0.05))
		end
	end
end

--------------------------------------------------------------------------------
-- Catalog
--------------------------------------------------------------------------------

export type ModelDef = {
	id: string,
	name: { ru: string, en: string },
	colors: { paint: number, accent: number },
	build: (Ctx) -> (),
}

ServiceModels.List = {
	{ id = "citybike", name = { ru = "Городской велосипед", en = "City bike" }, colors = { paint = 13, accent = 1 }, build = citybike },
	{ id = "mtb", name = { ru = "Горный велосипед", en = "Mountain bike" }, colors = { paint = 9, accent = 4 }, build = mtb },
	{ id = "bmx", name = { ru = "BMX", en = "BMX" }, colors = { paint = 17, accent = 8 }, build = bmx },
	{ id = "roadbike", name = { ru = "Шоссейный велосипед", en = "Road bike" }, colors = { paint = 5, accent = 1 }, build = roadbike },
	{ id = "kidsbike", name = { ru = "Детский велосипед", en = "Kids bike" }, colors = { paint = 23, accent = 17 }, build = kidsbike },
	{ id = "kickscooter", name = { ru = "Самокат", en = "Kick scooter" }, colors = { paint = 12, accent = 8 }, build = kickscooter },
	{ id = "escooter", name = { ru = "Электросамокат", en = "E-scooter" }, colors = { paint = 3, accent = 13 }, build = escooter },
	{
		id = "moped",
		name = { ru = "Мопед", en = "Moped" },
		colors = { paint = 22, accent = 1 },
		build = function(ctx)
			moped(ctx, false)
		end,
	},
	{
		id = "deliverymoped",
		name = { ru = "Мопед доставки", en = "Delivery moped" },
		colors = { paint = 1, accent = 7 },
		build = function(ctx)
			moped(ctx, true)
		end,
	},
	{ id = "sportbike", name = { ru = "Спортбайк", en = "Sport bike" }, colors = { paint = 14, accent = 1 }, build = sportbike },
	{ id = "chopper", name = { ru = "Чоппер", en = "Chopper" }, colors = { paint = 6, accent = 21 }, build = chopper },
	{ id = "dirtbike", name = { ru = "Кроссовый мотоцикл", en = "Dirt bike" }, colors = { paint = 7, accent = 4 }, build = dirtbike },
	{ id = "classicbike", name = { ru = "Классический мотоцикл", en = "Classic bike" }, colors = { paint = 15, accent = 21 }, build = classicbike },
	{ id = "quad", name = { ru = "Квадроцикл", en = "Quad bike" }, colors = { paint = 10, accent = 8 }, build = quad },
	{ id = "golfcart", name = { ru = "Гольф-кар", en = "Golf cart" }, colors = { paint = 1, accent = 10 }, build = golfcart },
} :: { ModelDef }

local byId: { [string]: ModelDef } = {}
for _, def in ServiceModels.List do
	byId[def.id] = def
end

function ServiceModels.get(id: any): ModelDef?
	return if typeof(id) == "string" then byId[id] else nil
end

local function newCtx(name: string, paint: Color3, accent: Color3): Ctx
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root
	return { model = model, root = root, paint = paint, accent = accent }
end

-- Builds an anchored model at the origin (ground level, facing -Z).
function ServiceModels.build(id: string, colors: Colors?): Model?
	local def = byId[id]
	if not def then
		return nil
	end
	local c = colors or {}
	local ctx = newCtx(id, Paints.getColor(c.paint or def.colors.paint), Paints.getColor(c.accent or def.colors.accent))
	def.build(ctx)
	ctx.model:SetAttribute("ServiceModel", id)
	return ctx.model
end

--------------------------------------------------------------------------------
-- People (workers and customers)
--------------------------------------------------------------------------------

export type PersonLook = {
	skin: Color3?,
	hair: Color3?,
	shirt: Color3?,
	pants: Color3?,
	cap: Color3?, -- nil = no cap
}

-- A blocky person standing on the ground at the origin, facing -Z. Limbs are
-- Motor6D-jointed to the torso: Joint_ArmL/ArmR/LegL/LegR (swing around X).
function ServiceModels.person(name: string, look: PersonLook?): Model
	local l = look or {}
	local ctx = newCtx(name, Color3.new(1, 1, 1), Color3.new(1, 1, 1))
	local function tint(part: BasePart, color: Color3?)
		if color then
			part.Color = color
		end
	end
	local torso = box(ctx, "Overalls", Vector3.new(2, 2, 1), p(0, 3, 0))
	torso.Name = "Torso"
	tint(torso, l.pants)
	local shirt = box(ctx, "Shirt", Vector3.new(2.02, 0.9, 1.02), p(0, 3.56, 0))
	tint(shirt, l.shirt)
	for _, side in { -1, 1 } do
		box(ctx, "Overalls", Vector3.new(0.3, 0.92, 1.04), p(side * 0.55, 3.56, 0)).Color = torso.Color
	end
	local head = box(ctx, "Skin", Vector3.new(1.15, 1.15, 1.15), p(0, 4.6, 0))
	head.Name = "Head"
	tint(head, l.skin)
	local hair = box(ctx, "Hair", Vector3.new(1.2, 0.35, 1.2), p(0, 5.1, 0.03))
	tint(hair, l.hair)
	box(ctx, "Hair", Vector3.new(1.2, 0.6, 0.2), p(0, 4.85, 0.53)).Color = hair.Color
	for _, side in { -1, 1 } do
		box(ctx, "Face", Vector3.new(0.14, 0.2, 0.05), p(side * 0.24, 4.72, -0.58))
	end
	box(ctx, "Face", Vector3.new(0.4, 0.07, 0.05), p(0, 4.38, -0.58))
	if l.cap then
		local cap = box(ctx, "Cap", Vector3.new(1.24, 0.36, 1.24), p(0, 5.25, 0))
		cap.Color = l.cap
		local brim = box(ctx, "Cap", Vector3.new(1.1, 0.08, 0.55), p(0, 5.1, -0.82))
		brim.Color = l.cap
	end

	local function limb(limbName: string, size: Vector3, center: Vector3, joint: Vector3, role: string, color: Color3?)
		local part = box(ctx, role, size, center)
		part.Name = limbName
		tint(part, color)
		part:SetAttribute("Jointed", true)
		local motor = Instance.new("Motor6D")
		motor.Name = "Joint_" .. limbName
		motor.Part0 = torso
		motor.Part1 = part
		motor.C0 = torso.CFrame:ToObjectSpace(CFrame.new(joint))
		motor.C1 = part.CFrame:ToObjectSpace(CFrame.new(joint))
		motor.Parent = part
		return part
	end
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local arm = limb("Arm" .. tag, Vector3.new(0.9, 2, 0.9), p(side * 1.47, 3, 0), p(side * 1.47, 3.85, 0), "Shirt", l.shirt)
		local hand = box(ctx, "Skin", Vector3.new(0.92, 0.4, 0.92), p(side * 1.47, 2.15, 0))
		tint(hand, l.skin)
		hand:SetAttribute("JointedTo", arm.Name)
		local leg = limb("Leg" .. tag, Vector3.new(0.95, 2, 0.95), p(side * 0.5, 1, 0), p(side * 0.5, 2, 0), "Overalls", l.pants)
		local shoe = box(ctx, "Shoe", Vector3.new(0.97, 0.35, 1.1), p(side * 0.5, 0.17, -0.07))
		shoe:SetAttribute("JointedTo", leg.Name)
	end
	ctx.model:SetAttribute("Person", true)
	return ctx.model
end

-- Joins every part to the anchored Root so moving Root moves the model
-- (cheap to replicate). Parts marked JointedTo are welded to their limb.
function ServiceModels.weldToRoot(model: Model)
	local root = model.PrimaryPart :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local jointedTo = d:GetAttribute("JointedTo")
			if d:GetAttribute("Jointed") then
				d.Anchored = false -- held by its Motor6D
			else
				local target = root
				if typeof(jointedTo) == "string" then
					target = (model:FindFirstChild(jointedTo, true) :: BasePart?) or root
				end
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = target
				weld.Part1 = d
				weld.Parent = d
				d.Anchored = false
			end
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	root.Anchored = true
end

return ServiceModels
