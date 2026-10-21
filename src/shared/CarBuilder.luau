-- CarBuilder: turns a CarCatalog definition into a drivable Model made of parts.
--
-- Layout of the produced model:
--   Model "Car"            PrimaryPart = Chassis, attributes CarId/OwnerUserId/...
--     Chassis              invisible, the only part with mass (center of mass)
--     Hull_*               invisible collision boxes (massless)
--     Body (Folder)        all visual parts, tagged with a "Role" attribute
--     Wheel_<i>            tire parts joined to the chassis with a Motor6D "Axle";
--                          the client animates Axle.Transform for spin/steer/suspension
--     DriveSeat            VehicleSeat for the owner, Seat_<n> for passengers
--
-- The same builder makes garage previews (preview = true: anchored, no seats/joints).

local CarCatalog = require(script.Parent.CarCatalog)
local Paints = require(script.Parent.Paints)
local Types = require(script.Parent.Types)

type CarDef = Types.CarDef
type CarSave = Types.CarSave

export type BuildOptions = {
	preview: boolean?, -- anchored model for ViewportFrames / showrooms
	showroom: boolean?, -- anchored, but keeps decals and lights
	ownerName: string?,
	save: CarSave?,
}

local CarBuilder = {}

local ROLE_STYLE: { [string]: { color: Color3?, material: Enum.Material, reflectance: number?, transparency: number? } } =
	{
		Trim = { color = Color3.fromRGB(34, 35, 40), material = Enum.Material.SmoothPlastic },
		Dark = { color = Color3.fromRGB(14, 14, 17), material = Enum.Material.SmoothPlastic },
		Chrome = { color = Color3.fromRGB(214, 218, 224), material = Enum.Material.SmoothPlastic, reflectance = 0.55 },
		Glass = {
			color = Color3.fromRGB(28, 38, 54),
			material = Enum.Material.Glass,
			reflectance = 0.15,
			transparency = 0.35,
		},
		TintGlass = {
			color = Color3.fromRGB(12, 14, 20),
			material = Enum.Material.Glass,
			reflectance = 0.2,
			transparency = 0.15,
		},
		Tire = { color = Color3.fromRGB(30, 30, 33), material = Enum.Material.SmoothPlastic },
		Interior = { color = Color3.fromRGB(44, 44, 50), material = Enum.Material.Fabric },
		Headlight = { color = Color3.fromRGB(255, 249, 228), material = Enum.Material.Neon },
		Taillight = { color = Color3.fromRGB(120, 8, 12), material = Enum.Material.Neon },
		Indicator = { color = Color3.fromRGB(255, 150, 24), material = Enum.Material.Neon },
		Light = { color = Color3.fromRGB(255, 252, 240), material = Enum.Material.Neon },
		Plate = { color = Color3.fromRGB(236, 238, 240), material = Enum.Material.SmoothPlastic },
		SirenA = { color = Color3.fromRGB(150, 20, 20), material = Enum.Material.SmoothPlastic, transparency = 0.15 },
		SirenB = { color = Color3.fromRGB(20, 40, 160), material = Enum.Material.SmoothPlastic, transparency = 0.15 },
		White = { color = Color3.fromRGB(245, 245, 245), material = Enum.Material.SmoothPlastic },
	}

local SIREN_COLORS = {
	police = { Color3.fromRGB(255, 30, 30), Color3.fromRGB(30, 90, 255) },
	medic = { Color3.fromRGB(255, 30, 30), Color3.fromRGB(255, 255, 255) },
	fire = { Color3.fromRGB(255, 30, 30), Color3.fromRGB(255, 140, 20) },
}

CarBuilder.SirenColors = SIREN_COLORS

local SEATED_HEAD = 3.9 -- seat top to head top of a seated R15 character

-- collision hulls start a little above the visual floor so low cars don't scrape on bumps
CarBuilder.HullLift = 0.3

--------------------------------------------------------------------------------
-- Builder context
--------------------------------------------------------------------------------

type Ctx = {
	def: CarDef,
	save: CarSave,
	opts: BuildOptions,
	model: Model,
	body: Folder,
	chassis: BasePart,
	anchored: boolean,
	decor: boolean, -- SurfaceGuis, lights, attachments
	seatCount: number,
}

local function applyRole(part: BasePart, role: string, save: CarSave)
	if role == "Paint" then
		local finish = Paints.getFinish(save.finish)
		part.Color = Paints.getColor(save.paint)
		part.Material = finish.material
		part.Reflectance = finish.reflectance
		part.Transparency = 0
	elseif role == "Accent" then
		part.Color = Paints.getColor(save.accent)
		part.Material = Enum.Material.SmoothPlastic
		part.Reflectance = 0.1
	elseif role == "NeonAccent" then
		part.Color = Paints.getColor(save.accent)
		part.Material = Enum.Material.Neon
	elseif role == "Rim" then
		part.Color = Paints.getColor(save.rim)
		part.Material = Enum.Material.SmoothPlastic
		part.Reflectance = 0.25
	elseif role == "Glow" then
		local on = save.glow ~= nil and save.glow > 0
		part.Color = Paints.getColor(if on then save.glow else 1)
		part.Material = Enum.Material.Neon
		part.Transparency = if on then 0 else 1
		local light = part:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = part.Color
			light.Enabled = on
		end
	else
		local style = ROLE_STYLE[role]
		if style then
			if style.color then
				part.Color = style.color
			end
			part.Material = style.material
			part.Reflectance = style.reflectance or 0
			part.Transparency = style.transparency or 0
		end
	end
end

local function makePart(ctx: Ctx, className: string, role: string, size: Vector3, cf: CFrame, parent: Instance?): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = role
	part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	part.CFrame = cf
	part.Anchored = ctx.anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = size.X * size.Y * size.Z > 0.3
	part:SetAttribute("Role", role)
	applyRole(part, role, ctx.save)
	part.Parent = parent or ctx.body
	return part
end

local function box(ctx: Ctx, role: string, size: Vector3, at: Vector3 | CFrame, parent: Instance?): BasePart
	local cf = if typeof(at) == "CFrame" then at else CFrame.new(at)
	return makePart(ctx, "Part", role, size, cf, parent)
end

-- Box spanning two y values and two z values at a given x range.
local function slab(ctx: Ctx, role: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number): BasePart?
	if x1 - x0 < 0.02 or y1 - y0 < 0.02 or z1 - z0 < 0.02 then
		return nil
	end
	return box(
		ctx,
		role,
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	)
end

-- Wedge whose high side faces +Z (rear) when `risingToRear` is true.
local function wedge(ctx: Ctx, role: string, size: Vector3, center: Vector3, risingToRear: boolean): BasePart
	local cf = CFrame.new(center)
	if not risingToRear then
		cf = cf * CFrame.Angles(0, math.pi, 0)
	end
	local part = Instance.new("WedgePart")
	part.Name = role
	part.Size = size
	part.CFrame = cf
	part.Anchored = ctx.anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = true
	part:SetAttribute("Role", role)
	applyRole(part, role, ctx.save)
	part.Parent = ctx.body
	return part
end

-- Cylinder with its axis along the local X of `cf`.
local function cylinder(ctx: Ctx, role: string, length: number, diameter: number, cf: CFrame, parent: Instance?): BasePart
	local part = makePart(ctx, "Part", role, Vector3.new(length, diameter, diameter), cf, parent);
	(part :: Part).Shape = Enum.PartType.Cylinder
	return part
end

local function ball(ctx: Ctx, role: string, diameter: number, pos: Vector3): BasePart
	local part = makePart(ctx, "Part", role, Vector3.new(diameter, diameter, diameter), CFrame.new(pos));
	(part :: Part).Shape = Enum.PartType.Ball
	return part
end

-- Box stretched between two points (thickness x height across the line).
local function beam(ctx: Ctx, role: string, p0: Vector3, p1: Vector3, thickness: number, height: number?): BasePart?
	local d = p1 - p0
	local len = d.Magnitude
	if len < 0.02 then
		return nil
	end
	local mid = (p0 + p1) / 2
	local up = if math.abs(d.Unit.Y) > 0.98 then Vector3.new(0, 0, -1) else Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt(mid, p1, up)
	return box(ctx, role, Vector3.new(thickness, height or thickness, len), cf)
end

-- Cylinder tube between two points.
local function tube(ctx: Ctx, role: string, p0: Vector3, p1: Vector3, diameter: number): BasePart?
	local d = p1 - p0
	local len = d.Magnitude
	if len < 0.02 then
		return nil
	end
	local mid = (p0 + p1) / 2
	local up = if math.abs(d.Unit.Y) > 0.98 then Vector3.new(0, 0, -1) else Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt(mid, p1, up) * CFrame.Angles(0, math.pi / 2, 0)
	return cylinder(ctx, role, len, diameter, cf)
end

local function hull(ctx: Ctx, size: Vector3, center: Vector3)
	if ctx.opts.preview or ctx.opts.showroom then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Hull"
	part.Size = size
	part.CFrame = CFrame.new(center)
	part.Transparency = 1
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Anchored = false
	part.CastShadow = false
	part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.25, 0.15, 1, 1)
	part.Parent = ctx.model
end

local function surfaceText(
	ctx: Ctx,
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	textColor: Color3,
	bg: Color3?,
	font: Enum.Font?
): SurfaceGui?
	if not ctx.decor then
		return nil
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.6
	gui.ZOffset = 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	label.BackgroundColor3 = bg or Color3.new(1, 1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = font or Enum.Font.GothamBlack
	label.TextColor3 = textColor
	label.BorderSizePixel = 0
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = label
	gui.Parent = part
	return gui
end

local function roundel(ctx: Ctx, part: BasePart, face: Enum.NormalId, text: string)
	if not ctx.decor then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.6
	local circle = Instance.new("Frame")
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundColor3 = Color3.new(1, 1, 1)
	circle.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.8, 0.8)
	label.Position = UDim2.fromScale(0.1, 0.1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(15, 15, 20)
	label.Parent = circle
	circle.Parent = gui
	gui.Parent = part
end

local function attachment(ctx: Ctx, name: string, worldPos: Vector3)
	if not ctx.decor or ctx.opts.preview or ctx.opts.showroom then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = ctx.chassis.CFrame:PointToObjectSpace(worldPos)
	a.Parent = ctx.chassis
end

--------------------------------------------------------------------------------
-- Shared measurements
--------------------------------------------------------------------------------

type Geo = {
	L: number,
	W: number,
	zF: number,
	zR: number,
	floor: number,
	belt: number,
	nose: number,
	noseDrop: number,
	tail: number,
	tailDrop: number,
	axles: { CarCatalog.Axle },
	innerHalf: number,
	topAt: (z: number) -> number,
	cabin: {
		z0: number,
		z1: number,
		z2: number,
		z3: number,
		yR: number,
		gw: number,
		yBase: number,
	}?,
	hullEnd: number,
	bedStart: number?,
	bedFloor: number?,
	wells: { { z0: number, z1: number, top: number, axle: CarCatalog.Axle } },
}

local ARCH_GAP = 0.3

local function measure(def: CarDef): Geo
	local b = def.body
	local L, W = b.length, b.width
	local zF, zR = -L / 2, L / 2
	local nose = b.nose or 0
	local noseDrop = b.noseDrop or 0
	local tail = b.tail or 0
	local tailDrop = b.tailDrop or 0
	local belt = b.belt
	local axles = CarCatalog.getAxles(def)

	local minInner = math.huge
	for _, a in axles do
		minInner = math.min(minInner, a.track / 2 - a.width / 2 - 0.12)
	end

	local function topAt(z: number): number
		if nose > 0 and z < zF + nose then
			return belt - noseDrop * (1 - (z - zF) / nose)
		elseif tail > 0 and z > zR - tail then
			return belt - tailDrop * ((z - (zR - tail)) / tail)
		end
		return belt
	end

	local wells = {}
	for _, a in axles do
		table.insert(wells, {
			z0 = a.z - a.radius - ARCH_GAP,
			z1 = a.z + a.radius + ARCH_GAP,
			top = a.radius * 2 + ARCH_GAP,
			axle = a,
		})
	end

	local geo: Geo = {
		L = L,
		W = W,
		zF = zF,
		zR = zR,
		floor = b.floor,
		belt = belt,
		nose = nose,
		noseDrop = noseDrop,
		tail = tail,
		tailDrop = tailDrop,
		axles = axles,
		innerHalf = math.max(minInner, 0.5),
		topAt = topAt,
		cabin = nil,
		hullEnd = zR,
		bedStart = nil,
		bedFloor = nil,
		wells = wells,
	}

	if b.style == "semi" and b.box then
		geo.hullEnd = zF + b.box.start + (b.box.length or 2.5)
	end
	if b.bed then
		geo.bedStart = zF + b.bed.start
		local maxTop = 0
		for _, well in wells do
			if well.z1 > geo.bedStart then
				maxTop = math.max(maxTop, well.top)
			end
		end
		geo.bedFloor = math.min(math.max(maxTop + 0.05, b.floor + 0.6), belt - 0.8)
	end

	local c = b.cabin
	if c then
		local z0 = zF + c.start
		local z1 = z0 + c.wind
		local z2 = z1 + c.roof
		local z3 = math.min(z2 + c.back, geo.hullEnd - tail)
		geo.cabin = {
			z0 = z0,
			z1 = z1,
			z2 = z2,
			z3 = z3,
			yR = belt + c.height,
			gw = W - 2 * c.inset,
			yBase = topAt(z0),
		}
	end
	return geo
end

CarBuilder.measure = measure

-- Seat layout (car-space positions of the seat tops).
export type SeatPos = { pos: Vector3, driver: boolean }

function CarBuilder.getSeats(def: CarDef): { SeatPos }
	local geo = measure(def)
	local b = def.body
	local seats: { SeatPos } = {}
	local cab = geo.cabin
	local headroom = if cab then cab.yR - SEATED_HEAD - 0.05 else math.huge
	local function seatY(custom: number?): number
		if custom then
			return custom
		end
		return math.clamp(b.floor + 0.45, 0.35, math.max(headroom, 0.35))
	end
	if def.seats then
		for _, s in def.seats do
			table.insert(seats, { pos = Vector3.new(s.x, seatY(s.y), s.z), driver = s.driver == true })
		end
		return seats
	end
	if not cab then
		table.insert(seats, { pos = Vector3.new(0, seatY(nil), 0), driver = true })
		return seats
	end
	local y = seatY(nil)
	local dz = cab.z1 + 0.9
	local off = math.clamp(cab.gw / 2 - 1.15, 0, 1.6)
	table.insert(seats, { pos = Vector3.new(-off, y, dz), driver = true })
	local limit = def.maxSeats or 4
	if off >= 0.9 and #seats < limit then
		table.insert(seats, { pos = Vector3.new(off, y, dz), driver = false })
	end
	local rearZ = dz + 2.7
	if b.cabin and (cab.z2 + (b.cabin.back * 0.35)) - rearZ > 0.4 then
		if #seats < limit then
			table.insert(seats, { pos = Vector3.new(-off, y, rearZ), driver = false })
		end
		if off >= 0.9 and #seats < limit then
			table.insert(seats, { pos = Vector3.new(off, y, rearZ), driver = false })
		end
	end
	return seats
end

--------------------------------------------------------------------------------
-- Body sections
--------------------------------------------------------------------------------

-- Lower body "loft": slices the body along z, cutting wheel wells into the outer bands.
local function buildLowerBody(ctx: Ctx, geo: Geo)
	local breaks = { geo.zF, geo.hullEnd }
	local function addBreak(z: number)
		if z > geo.zF + 0.01 and z < geo.hullEnd - 0.01 then
			table.insert(breaks, z)
		end
	end
	addBreak(geo.zF + geo.nose)
	addBreak(geo.hullEnd - geo.tail)
	for _, w in geo.wells do
		addBreak(w.z0)
		addBreak(w.z1)
	end
	if geo.bedStart then
		addBreak(geo.bedStart)
	end
	table.sort(breaks)

	local W2 = geo.W / 2
	local inner = geo.innerHalf
	local floor = geo.floor
	local topAt = geo.topAt
	-- the tail chamfer must end at the hull end for semis
	if geo.hullEnd < geo.zR then
		local hullEnd = geo.hullEnd
		local belt, tail, tailDrop = geo.belt, geo.tail, geo.tailDrop
		topAt = function(z: number): number
			if tail > 0 and z > hullEnd - tail then
				return belt - tailDrop * ((z - (hullEnd - tail)) / tail)
			end
			return geo.topAt(math.min(z, hullEnd - tail - 0.001))
		end
	end

	for i = 1, #breaks - 1 do
		local a, b = breaks[i], breaks[i + 1]
		if b - a < 0.02 then
			continue
		end
		local mid = (a + b) / 2
		local ta, tb = topAt(a), topAt(b)
		local inBed = geo.bedStart ~= nil and mid > geo.bedStart
		if inBed then
			ta, tb = geo.bedFloor :: number, geo.bedFloor :: number
		end
		local tMin, tMax = math.min(ta, tb), math.max(ta, tb)
		local well = nil
		for _, w in geo.wells do
			if mid > w.z0 and mid < w.z1 then
				well = w
				break
			end
		end

		local function column(x0: number, x1: number, bottom: number)
			if tMin - bottom > 0.02 then
				slab(ctx, "Paint", x0, x1, bottom, tMin, a, b)
			end
			if tMax - tMin > 0.02 then
				local base = math.max(bottom, tMin)
				local h = tMax - base
				if h > 0.02 then
					wedge(ctx, "Paint", Vector3.new(x1 - x0, h, b - a), Vector3.new((x0 + x1) / 2, base + h / 2, mid), tb > ta)
				end
			end
		end

		if well then
			-- inner core is solid, the outer bands only exist above the arch
			column(-inner, inner, floor)
			local archTop = well.top
			if archTop < tMax - 0.05 then
				column(-W2, -inner, archTop)
				column(inner, W2, archTop)
			end
		else
			column(-W2, W2, floor)
		end
	end

	-- dark liners inside the wheel wells so the arches read as openings
	for _, w in geo.wells do
		if w.z0 < geo.hullEnd - 0.1 then
			local z1 = math.min(w.z1, geo.hullEnd)
			local top = math.min(w.top, geo.belt)
			for _, side in { -1, 1 } do
				box(
					ctx,
					"Dark",
					Vector3.new(0.12, top - floor, z1 - w.z0),
					Vector3.new(side * (inner + 0.06), (top + floor) / 2, (w.z0 + z1) / 2)
				)
			end
			-- flared arch over wheels that poke above the body line
			local lowTop = math.min(topAt(math.max(w.z0, geo.zF)), topAt(math.min(z1, geo.hullEnd)), topAt(w.axle.z))
			if w.top > lowTop - 0.15 then
				local flareTop = w.top + 0.35
				local zLen = z1 - w.z0
				for _, side in { -1, 1 } do
					local x0 = side * inner
					local x1 = side * W2
					local cx = (x0 + x1) / 2
					local wx = math.abs(x1 - x0) + 0.05
					box(ctx, "Paint", Vector3.new(wx, flareTop - w.top, zLen), Vector3.new(cx, (w.top + flareTop) / 2, (w.z0 + z1) / 2))
					-- ramps that blend the arch into the body in front of and behind the wheel
					for _, dir in { -1, 1 } do
						local edge = if dir < 0 then w.z0 else z1
						local room = if dir < 0 then edge - geo.zF else geo.hullEnd - edge
						local base = topAt(math.clamp(edge + dir * 0.4, geo.zF, geo.hullEnd))
						local h = flareTop - base
						local len = math.min(math.clamp(h * 1.3, 0.6, 2.2), room)
						if h > 0.05 and len > 0.1 then
							wedge(ctx, "Paint", Vector3.new(wx, h, len), Vector3.new(cx, base + h / 2, edge + dir * len / 2), dir < 0)
						end
					end
				end
			end
		end
	end
end

local function buildBed(ctx: Ctx, geo: Geo)
	if not geo.bedStart then
		return
	end
	local bedFloor = geo.bedFloor :: number
	local W2 = geo.W / 2
	local zEnd = geo.zR
	local t = 0.35
	-- side walls, front wall, tailgate
	for _, side in { -1, 1 } do
		slab(ctx, "Paint", side > 0 and W2 - t or -W2, side > 0 and W2 or -W2 + t, bedFloor, geo.belt, geo.bedStart, zEnd)
		box(ctx, "Trim", Vector3.new(t + 0.06, 0.12, zEnd - geo.bedStart), Vector3.new(side * (W2 - t / 2), geo.belt + 0.06, (geo.bedStart + zEnd) / 2))
	end
	slab(ctx, "Paint", -W2, W2, bedFloor, geo.belt, geo.bedStart, geo.bedStart + t)
	slab(ctx, "Paint", -W2, W2, bedFloor, geo.belt - 0.05, zEnd - t, zEnd)
	slab(ctx, "Dark", -W2 + t, W2 - t, bedFloor, bedFloor + 0.06, geo.bedStart + t, zEnd - t)
	hull(ctx, Vector3.new(geo.W, bedFloor - geo.floor, zEnd - geo.bedStart), Vector3.new(0, (bedFloor + geo.floor) / 2, (geo.bedStart + zEnd) / 2))
end

local function buildCabin(ctx: Ctx, geo: Geo)
	local cab = geo.cabin
	local spec = ctx.def.body.cabin
	if not cab or not spec then
		return
	end
	local belt = geo.belt
	local z0, z1, z2, z3 = cab.z0, cab.z1, cab.z2, cab.z3
	local yR, gw = cab.yR, cab.gw
	local yB = cab.yBase
	local roofT = 0.3
	local features = ctx.def.features
	local gx = gw / 2

	if spec.open then
		-- convertible: raked windscreen in a frame, no roof
		local p0 = Vector3.new(0, yB, z0)
		local p1 = Vector3.new(0, yR, z1)
		local d = p1 - p0
		local cf = CFrame.lookAt((p0 + p1) / 2, p1)
		box(ctx, "Glass", Vector3.new(gw - 0.3, 0.12, d.Magnitude), cf)
		beam(ctx, "Trim", Vector3.new(-gx + 0.1, yR, z1), Vector3.new(gx - 0.1, yR, z1), 0.22)
		for _, side in { -1, 1 } do
			beam(ctx, "Trim", Vector3.new(side * (gx - 0.1), yB, z0), Vector3.new(side * (gx - 0.1), yR, z1), 0.22)
		end
		-- cockpit tub (recessed look)
		slab(ctx, "Interior", -gx + 0.2, gx - 0.2, belt, belt + 0.04, z1, z2 + 0.5)
		hull(ctx, Vector3.new(gw, 0.8, z2 - z0), Vector3.new(0, belt + 0.4, (z0 + z2) / 2))
		if features.rollHoops then
			for _, side in { -1, 1 } do
				local x = side * math.clamp(gx - 1.15, 0, 1.6)
				local zh = z2 + 0.2
				tube(ctx, "Chrome", Vector3.new(x - 0.7, belt, zh), Vector3.new(x - 0.7, belt + 1.4, zh), 0.22)
				tube(ctx, "Chrome", Vector3.new(x + 0.7, belt, zh), Vector3.new(x + 0.7, belt + 1.4, zh), 0.22)
				tube(ctx, "Chrome", Vector3.new(x - 0.75, belt + 1.4, zh), Vector3.new(x + 0.75, belt + 1.4, zh), 0.22)
			end
		end
		return
	end

	local glassRole = "Glass"
	local roofRole = if spec.glassRoof then "TintGlass" else "Paint"

	-- windshield
	if z1 - z0 > 0.05 then
		wedge(ctx, glassRole, Vector3.new(gw, yR - yB, z1 - z0), Vector3.new(0, (yB + yR) / 2, (z0 + z1) / 2), true)
	end
	-- side windows / panels under the roof
	local sideGlassEnd = z2
	if spec.sideWindows then
		sideGlassEnd = math.min(z2, z1 + spec.sideWindows)
	end
	slab(ctx, glassRole, -gx, gx, belt, yR - roofT, z1, sideGlassEnd)
	if sideGlassEnd < z2 then
		slab(ctx, "Paint", -gx, gx, belt, yR - roofT, sideGlassEnd, z2)
	end
	-- roof panel
	slab(ctx, roofRole, -gx - 0.04, gx + 0.04, yR - roofT, yR, z1 - 0.05, z2 + 0.05)
	if spec.glassRoof then
		for _, side in { -1, 1 } do
			slab(ctx, "Paint", side * gx - 0.2, side * gx + 0.06, yR - roofT - 0.02, yR + 0.02, z1 - 0.05, z2 + 0.05)
		end
	end
	-- rear glass
	if z3 - z2 > 0.05 then
		wedge(ctx, glassRole, Vector3.new(gw, yR - belt, z3 - z2), Vector3.new(0, (belt + yR) / 2, (z2 + z3) / 2), false)
	end

	-- pillars
	for _, side in { -1, 1 } do
		local x = side * (gx + 0.02)
		beam(ctx, "Paint", Vector3.new(x, yB, z0), Vector3.new(x, yR, z1), 0.28)
		if z3 - z2 > 0.05 then
			beam(ctx, "Paint", Vector3.new(x, yR, z2), Vector3.new(x, belt, z3), 0.34)
		else
			beam(ctx, "Paint", Vector3.new(x, belt, z2 - 0.15), Vector3.new(x, yR, z2 - 0.15), 0.34)
		end
		local spacing = spec.windowPillars
		if spacing then
			local z = z1 + spacing
			while z < sideGlassEnd - 0.8 do
				beam(ctx, "Paint", Vector3.new(x, belt, z), Vector3.new(x, yR - roofT, z), 0.3)
				z += spacing
			end
		elseif spec.roof > 3.2 and sideGlassEnd >= z2 then
			local bz = z1 + math.min(spec.roof * 0.48, 2.6)
			beam(ctx, "Paint", Vector3.new(x, belt, bz), Vector3.new(x, yR - roofT, bz), 0.3)
		end
		-- window sill trim
		local trimRole = if features.chromeTrim then "Chrome" else "Trim"
		box(ctx, trimRole, Vector3.new(0.1, 0.08, z2 - z1), Vector3.new(x, belt + 0.04, (z1 + z2) / 2))
	end

	-- dashboard visible through the windshield
	slab(ctx, "Interior", -gx + 0.15, gx - 0.15, belt, belt + 0.4, z0 + 0.1, z0 + (z1 - z0) * 0.7)

	hull(ctx, Vector3.new(gw, yR - belt, math.max(z3 - z0, 1) * 0.85), Vector3.new(0, (belt + yR) / 2, (z0 + z3) / 2))
end

local function buildBox(ctx: Ctx, geo: Geo)
	local spec = ctx.def.body.box
	if not spec then
		return
	end
	local zs = geo.zF + spec.start
	local ze = if spec.length then zs + spec.length else geo.zR
	local W = geo.W - (if ctx.def.body.style == "semi" then 0.3 else 0)
	local yb = geo.belt
	local top = spec.top
	slab(ctx, "Paint", -W / 2, W / 2, yb, top - 0.25, zs, ze)
	-- slightly inset roof cap
	slab(ctx, "Paint", -W / 2 + 0.15, W / 2 - 0.15, top - 0.25, top, zs + 0.1, ze - 0.1)
	-- corner trims
	for _, side in { -1, 1 } do
		beam(ctx, "Trim", Vector3.new(side * W / 2, top - 0.25, zs), Vector3.new(side * W / 2, top - 0.25, ze), 0.18)
	end
	hull(ctx, Vector3.new(W, top - yb, ze - zs), Vector3.new(0, (yb + top) / 2, (zs + ze) / 2))
	if ctx.def.features.sideStripe then
		for _, side in { -1, 1 } do
			box(ctx, "Accent", Vector3.new(0.06, 0.6, ze - zs - 0.4), Vector3.new(side * (W / 2 + 0.03), yb + 1.2, (zs + ze) / 2))
		end
	end
	-- rear doors
	if ctx.def.body.style == "box" then
		box(ctx, "Dark", Vector3.new(0.08, top - yb - 0.6, 0.06), Vector3.new(0, (yb + top) / 2 - 0.2, ze + 0.03))
		box(ctx, "Glass", Vector3.new(W * 0.3, 1.2, 0.06), Vector3.new(-W * 0.22, top - 1.4, ze + 0.03))
		box(ctx, "Glass", Vector3.new(W * 0.3, 1.2, 0.06), Vector3.new(W * 0.22, top - 1.4, ze + 0.03))
	end
end

local function buildSemiFrame(ctx: Ctx, geo: Geo)
	if ctx.def.body.style ~= "semi" then
		return
	end
	local zs = geo.hullEnd - 0.5
	local ze = geo.zR
	local y = geo.floor + 0.4
	for _, side in { -1, 1 } do
		slab(ctx, "Trim", side * 2.2 - 0.35, side * 2.2 + 0.35, y - 0.4, y + 0.5, zs, ze)
	end
	slab(ctx, "Chrome", -2.9, 2.9, y + 0.5, y + 0.7, zs + 0.5, ze - 0.2)
	-- fifth wheel
	local rearMid = 0
	local n = 0
	for _, a in geo.axles do
		if a.drive then
			rearMid += a.z
			n += 1
		end
	end
	rearMid = if n > 0 then rearMid / n else (zs + ze) / 2
	cylinder(ctx, "Dark", 0.35, 3.6, CFrame.new(0, y + 0.85, rearMid) * CFrame.Angles(0, 0, math.pi / 2))
	-- rear fenders and mud flaps
	for _, a in geo.axles do
		if a.z > zs then
			for _, side in { -1, 1 } do
				local x = side * a.track / 2
				box(ctx, "Trim", Vector3.new(a.width + 0.4, 0.2, a.radius * 2 + 0.4), Vector3.new(x, a.radius * 2 + 0.35, a.z))
			end
		end
	end
	for _, side in { -1, 1 } do
		box(ctx, "Dark", Vector3.new(1.6, 1.4, 0.1), Vector3.new(side * geo.axles[1].track / 2, 1.1, ze - 0.2))
	end
	hull(ctx, Vector3.new(5.8, 1.2, ze - zs), Vector3.new(0, y + 0.1, (zs + ze) / 2))
end

local function buildBumpersAndLights(ctx: Ctx, geo: Geo)
	local f = ctx.def.features
	local W2 = geo.W / 2
	local floor = geo.floor
	local zF, zR = geo.zF, geo.zR
	local frontTop = geo.topAt(zF)
	local rearTop = if geo.bedStart then geo.belt else geo.topAt(zR)
	local trimRole = if f.chromeTrim then "Chrome" else "Trim"

	-- bumpers
	local bh = math.min(0.7, (frontTop - floor) * 0.5)
	box(ctx, trimRole, Vector3.new(geo.W - 0.3, bh, 0.45), Vector3.new(0, floor + bh / 2 + 0.05, zF + 0.12))
	local rbh = math.min(0.7, (rearTop - floor) * 0.5)
	box(ctx, trimRole, Vector3.new(geo.W - 0.3, rbh, 0.45), Vector3.new(0, floor + rbh / 2 + 0.05, zR - 0.12))

	-- grille
	local faceH = frontTop - floor
	local lightH = math.clamp(faceH * 0.22, 0.22, 0.5)
	local lightY = math.max(frontTop - lightH / 2 - 0.12, floor + bh + lightH / 2 + 0.08)
	if f.bigGrille then
		box(ctx, "Chrome", Vector3.new(3.6, faceH * 0.75, 0.2), Vector3.new(0, floor + faceH * 0.5, zF - 0.06))
		for i = 1, 5 do
			box(ctx, "Dark", Vector3.new(3.2, 0.12, 0.06), Vector3.new(0, floor + faceH * (0.2 + i * 0.11), zF - 0.17))
		end
	elseif not f.electric then
		box(ctx, "Dark", Vector3.new(math.min(geo.W * 0.4, 3.2), math.max(lightH * 0.9, 0.25), 0.1), Vector3.new(0, lightY - 0.05, zF - 0.03))
	end

	-- headlights / taillights
	local hlW = math.clamp(geo.W * 0.17, 0.8, 1.5)
	local hx = W2 - hlW / 2 - 0.25
	for _, side in { -1, 1 } do
		box(ctx, "Headlight", Vector3.new(hlW, lightH, 0.12), Vector3.new(side * hx, lightY, zF - 0.04))
		box(ctx, "Indicator", Vector3.new(0.35, lightH * 0.6, 0.1), Vector3.new(side * (W2 - 0.12), lightY - lightH * 0.1, zF + 0.05))
	end
	local rearFaceTop = rearTop
	local tH = math.clamp((rearFaceTop - floor) * 0.2, 0.22, 0.5)
	local tY = math.max(rearFaceTop - tH / 2 - 0.15, floor + rbh + tH / 2 + 0.08)
	for _, side in { -1, 1 } do
		box(ctx, "Taillight", Vector3.new(hlW, tH, 0.12), Vector3.new(side * hx, tY, zR + 0.04))
	end
	if f.lightbars then
		box(ctx, "Headlight", Vector3.new(geo.W - 1.2, 0.1, 0.1), Vector3.new(0, lightY + lightH / 2 + 0.08, zF - 0.02))
		box(ctx, "Taillight", Vector3.new(geo.W - 1.0, 0.14, 0.1), Vector3.new(0, tY + tH / 2 + 0.06, zR + 0.03))
	end

	-- plates
	local plateRear = box(ctx, "Plate", Vector3.new(1.9, 0.55, 0.06), Vector3.new(0, floor + rbh + 0.38, zR + 0.03))
	local plateText = string.upper(string.sub(ctx.opts.ownerName or ctx.def.name, 1, 10))
	surfaceText(ctx, plateRear, Enum.NormalId.Back, plateText, Color3.fromRGB(20, 40, 110))
	local plateFront = box(ctx, "Plate", Vector3.new(1.9, 0.5, 0.06), Vector3.new(0, floor + bh + 0.32, zF - 0.03))
	surfaceText(ctx, plateFront, Enum.NormalId.Front, plateText, Color3.fromRGB(20, 40, 110))

	-- light source for the headlights
	if ctx.decor then
		local beamPart = box(ctx, "Trim", Vector3.new(0.2, 0.2, 0.2), Vector3.new(0, lightY, zF + 0.3))
		beamPart.Transparency = 1
		beamPart.Name = "HeadlightBeam"
		local spot = Instance.new("SpotLight")
		spot.Name = "Beam"
		spot.Face = Enum.NormalId.Front
		spot.Angle = 75
		spot.Range = 60
		spot.Brightness = 3
		spot.Shadows = false
		spot.Color = Color3.fromRGB(255, 244, 220)
		spot.Parent = beamPart
		local glow = Instance.new("SurfaceLight")
		glow.Name = "BrakeGlow"
		glow.Face = Enum.NormalId.Back
		glow.Range = 8
		glow.Angle = 120
		glow.Brightness = 0
		glow.Color = Color3.fromRGB(255, 30, 30)
		local tailAnchor = box(ctx, "Trim", Vector3.new(0.2, 0.2, 0.2), Vector3.new(0, tY, zR - 0.3))
		tailAnchor.Transparency = 1
		tailAnchor.Name = "TailGlow"
		glow.Parent = tailAnchor
	end

	-- exhausts
	local n = f.exhaust or 0
	if n > 0 then
		local positions = {}
		if n == 1 then
			positions = { -W2 + 1.3 }
		elseif n == 2 then
			positions = { -W2 + 1.3, W2 - 1.3 }
		else
			positions = { -W2 + 1.1, -W2 + 1.6, W2 - 1.6, W2 - 1.1 }
		end
		for i, x in positions do
			local pipe = cylinder(
				ctx,
				"Chrome",
				0.8,
				0.42,
				CFrame.new(x, floor + 0.28, zR + 0.12) * CFrame.Angles(0, math.pi / 2, 0)
			)
			pipe.Name = "Exhaust"
			attachment(ctx, "Exhaust" .. i, Vector3.new(x, floor + 0.28, zR + 0.55))
		end
	end

	-- underglow (hidden until bought)
	local glow = box(ctx, "Glow", Vector3.new(geo.W - 1.2, 0.08, geo.L * 0.72), Vector3.new(0, floor - 0.02, 0))
	glow.CastShadow = false
	if ctx.decor then
		local light = Instance.new("PointLight")
		light.Range = 14
		light.Brightness = 2.5
		light.Shadows = false
		light.Parent = glow
	end
	applyRole(glow, "Glow", ctx.save)

	-- side mirrors
	local cab = geo.cabin
	if cab then
		for _, side in { -1, 1 } do
			local mx = side * (cab.gw / 2 + 0.45)
			box(ctx, "Accent", Vector3.new(0.5, 0.35, 0.3), Vector3.new(mx, geo.belt + 0.55, cab.z0 + 0.5))
			box(ctx, "Trim", Vector3.new(0.4, 0.12, 0.12), Vector3.new(side * (cab.gw / 2 + 0.2), geo.belt + 0.45, cab.z0 + 0.55))
		end
	end
end

local function buildDoors(ctx: Ctx, geo: Geo)
	local doors = ctx.def.features.doors or 0
	local cab = geo.cabin
	if doors <= 0 or not cab then
		return
	end
	local W2 = geo.W / 2
	local yTop = geo.belt - 0.05
	local yBot = geo.floor + 0.25
	local front = cab.z0 + 0.25
	local perSide = math.max(1, math.floor(doors / 2))
	local doorLen = math.min((cab.z2 - cab.z0) / perSide, 4.2)
	local edges = { front }
	for i = 1, perSide do
		table.insert(edges, front + doorLen * i)
	end
	for _, side in { -1, 1 } do
		local x = side * (W2 + 0.015)
		for _, z in edges do
			box(ctx, "Dark", Vector3.new(0.04, yTop - yBot, 0.06), Vector3.new(x, (yTop + yBot) / 2, z))
		end
		for i = 1, perSide do
			local hz = front + doorLen * i - 0.7
			box(ctx, "Trim", Vector3.new(0.08, 0.14, 0.5), Vector3.new(x + side * 0.03, geo.belt - 0.45, hz))
		end
	end
end

--------------------------------------------------------------------------------
-- Features
--------------------------------------------------------------------------------

local function buildFeatures(ctx: Ctx, geo: Geo)
	local f = ctx.def.features
	local cab = geo.cabin
	local W2 = geo.W / 2
	local belt = geo.belt
	local zF, zR = geo.zF, geo.zR
	local floor = geo.floor
	local hoodStart = zF + geo.nose
	local hoodEnd = if cab then cab.z0 else zF + geo.L * 0.35
	local trunkStart = if cab then cab.z3 else zR - geo.L * 0.3
	local trunkEnd = zR - geo.tail

	-- spoilers
	local spoiler = f.spoiler
	if spoiler == "lip" then
		wedge(ctx, "Accent", Vector3.new(geo.W - 1.2, 0.3, 0.7), Vector3.new(0, geo.topAt(zR - 0.6) + 0.15, zR - 0.6), true)
	elseif spoiler == "ducktail" then
		wedge(ctx, "Paint", Vector3.new(geo.W - 0.8, 0.55, 1.4), Vector3.new(0, geo.topAt(zR - 0.9) + 0.27, zR - 0.9), true)
	elseif spoiler == "roof" and cab then
		box(ctx, "Accent", Vector3.new(cab.gw + 0.1, 0.16, 1.0), CFrame.new(0, cab.yR + 0.02, cab.z2 + 0.35) * CFrame.Angles(math.rad(6), 0, 0))
	elseif spoiler == "wing" or spoiler == "bigwing" then
		local big = spoiler == "bigwing"
		local postH = if big then 1.5 else 0.9
		local zW = zR - (if big then 1.1 else 0.9)
		local baseY = geo.topAt(zW)
		local width = geo.W - (if big then 0.5 else 1.2)
		local px = width / 2 - 1.1
		for _, side in { -1, 1 } do
			box(ctx, "Trim", Vector3.new(0.18, postH, 0.6), Vector3.new(side * px, baseY + postH / 2, zW))
		end
		local plateY = baseY + postH + 0.1
		box(ctx, "Accent", Vector3.new(width, 0.2, if big then 1.7 else 1.3), CFrame.new(0, plateY, zW + 0.1) * CFrame.Angles(math.rad(-8), 0, 0))
		for _, side in { -1, 1 } do
			box(ctx, "Trim", Vector3.new(0.14, if big then 0.8 else 0.55, if big then 1.9 else 1.4), Vector3.new(side * width / 2, plateY + 0.05, zW + 0.1))
		end
	end

	-- hood details
	if f.hoodScoop then
		local big = f.hoodScoop == "big"
		local sw, sh, sl = (if big then 2.2 else 1.6), (if big then 0.7 else 0.35), (if big then 2.6 else 1.8)
		local zc = hoodStart + (hoodEnd - hoodStart) * 0.45
		box(ctx, "Paint", Vector3.new(sw, sh * 0.5, sl), Vector3.new(0, belt + sh * 0.25, zc))
		wedge(ctx, "Paint", Vector3.new(sw, sh * 0.5, sl), Vector3.new(0, belt + sh * 0.75, zc), false)
		box(ctx, "Dark", Vector3.new(sw - 0.3, sh * 0.6, 0.08), Vector3.new(0, belt + sh * 0.45, zc - sl / 2 - 0.02))
		if big then
			box(ctx, "Chrome", Vector3.new(sw - 0.4, 0.1, 0.1), Vector3.new(0, belt + sh * 0.7, zc - sl / 2 - 0.04))
		end
	end
	if f.hoodVents then
		for _, side in { -1, 1 } do
			box(ctx, "Dark", Vector3.new(0.9, 0.06, 1.3), Vector3.new(side * 1.1, belt + 0.03, hoodStart + (hoodEnd - hoodStart) * 0.55))
		end
	end
	if f.stripes then
		for _, side in { -1, 1 } do
			local x = side * 0.55
			slab(ctx, "Accent", x - 0.3, x + 0.3, belt, belt + 0.04, hoodStart, hoodEnd)
			if cab and not (ctx.def.body.cabin and ctx.def.body.cabin.open) then
				slab(ctx, "Accent", x - 0.3, x + 0.3, cab.yR, cab.yR + 0.04, cab.z1, cab.z2)
			end
			if trunkEnd > trunkStart + 0.2 then
				slab(ctx, "Accent", x - 0.3, x + 0.3, belt, belt + 0.04, trunkStart, trunkEnd)
			end
			-- down the nose slope
			if geo.nose > 0.2 then
				local p0 = Vector3.new(x, geo.topAt(zF) + 0.03, zF)
				local p1 = Vector3.new(x, belt + 0.03, hoodStart)
				beam(ctx, "Accent", p0, p1, 0.6, 0.04)
			end
		end
	end
	if f.ornament then
		box(ctx, "Chrome", Vector3.new(0.15, 0.45, 0.4), Vector3.new(0, belt + 0.22, hoodStart + 0.3))
	end

	-- body kit
	if f.sideSkirts or f.neonAccents then
		local role = if f.neonAccents then "NeonAccent" else "Trim"
		local z0 = geo.axles[1].z + geo.axles[1].radius + 0.4
		local z1 = geo.axles[#geo.axles].z - geo.axles[#geo.axles].radius - 0.4
		for _, side in { -1, 1 } do
			slab(ctx, role, side > 0 and W2 - 0.02 or -W2 - 0.18, side > 0 and W2 + 0.18 or -W2 + 0.02, floor, floor + 0.28, z0, z1)
		end
		if f.neonAccents then
			slab(ctx, "NeonAccent", -W2 + 0.5, W2 - 0.5, floor - 0.02, floor + 0.12, zF - 0.25, zF + 0.4)
		end
	end
	if f.diffuser then
		for i = -2, 2 do
			box(ctx, "Dark", Vector3.new(0.1, 0.45, 1.0), Vector3.new(i * 0.9, floor + 0.15, zR - 0.4))
		end
	end
	if f.canards then
		for _, side in { -1, 1 } do
			wedge(ctx, "Trim", Vector3.new(0.9, 0.12, 0.6), Vector3.new(side * (W2 - 0.5), floor + 0.75, zF + 0.25), true)
		end
	end
	if f.sideIntakes and cab then
		for _, side in { -1, 1 } do
			local zc = cab.z2 + 0.4
			local h = math.min(belt - floor - 0.5, 1.2)
			box(ctx, "Dark", Vector3.new(0.1, h, 1.8), Vector3.new(side * (W2 + 0.02), floor + 0.35 + h / 2, zc))
			wedge(ctx, "Paint", Vector3.new(0.4, h, 1.2), CFrame.new(side * (W2 - 0.1), floor + 0.35 + h / 2, zc - 1.4).Position, true)
		end
	end
	if f.fin and cab then
		local p0 = Vector3.new(0, cab.yR, cab.z2)
		local p1 = Vector3.new(0, belt + 0.3, trunkEnd)
		beam(ctx, "Paint", p0, p1, 0.14, 0.6)
	end
	if f.roofScoop and cab then
		box(ctx, "Trim", Vector3.new(1.2, 0.45, 1.4), Vector3.new(0, cab.yR + 0.22, (cab.z1 + cab.z2) / 2 + 0.3))
		box(ctx, "Dark", Vector3.new(1.0, 0.32, 0.06), Vector3.new(0, cab.yR + 0.24, (cab.z1 + cab.z2) / 2 - 0.42))
	end
	if f.sideStripe and not ctx.def.body.box then
		for _, side in { -1, 1 } do
			box(ctx, "Accent", Vector3.new(0.05, 0.35, geo.hullEnd - zF - 1.2), Vector3.new(side * (W2 + 0.02), belt - 0.3, (zF + geo.hullEnd) / 2))
		end
	end
	if f.chromeTrim then
		for _, side in { -1, 1 } do
			box(ctx, "Chrome", Vector3.new(0.06, 0.12, geo.L - 1.6), Vector3.new(side * (W2 + 0.03), belt - 0.5, 0))
		end
	end

	-- utility
	if f.roofRack and cab then
		local y = cab.yR + 0.25
		for _, side in { -1, 1 } do
			beam(ctx, "Trim", Vector3.new(side * (cab.gw / 2 - 0.3), y, cab.z1 + 0.3), Vector3.new(side * (cab.gw / 2 - 0.3), y, cab.z2 - 0.3), 0.2)
			for _, zz in { cab.z1 + 0.5, cab.z2 - 0.5 } do
				box(ctx, "Trim", Vector3.new(0.2, 0.25, 0.2), Vector3.new(side * (cab.gw / 2 - 0.3), cab.yR + 0.12, zz))
			end
		end
		local n = math.max(2, math.floor((cab.z2 - cab.z1) / 2.2))
		for i = 0, n do
			local zz = cab.z1 + 0.4 + (cab.z2 - cab.z1 - 0.8) * i / n
			box(ctx, "Trim", Vector3.new(cab.gw - 0.4, 0.12, 0.18), Vector3.new(0, y + 0.1, zz))
		end
	end
	if f.spareTire then
		local cy = (floor + belt) / 2 + 0.3
		cylinder(ctx, "Tire", 0.7, 2.6, CFrame.new(0, cy, zR + 0.4) * CFrame.Angles(0, math.pi / 2, 0))
		cylinder(ctx, "Rim", 0.74, 1.4, CFrame.new(0, cy, zR + 0.4) * CFrame.Angles(0, math.pi / 2, 0))
	end
	if f.snorkel and cab then
		local x = W2 - 0.2
		tube(ctx, "Trim", Vector3.new(x, belt - 1.0, cab.z0 - 0.3), Vector3.new(x, belt + 0.1, cab.z0 - 0.3), 0.35)
		tube(ctx, "Trim", Vector3.new(x, belt + 0.1, cab.z0 - 0.3), Vector3.new(x, cab.yR + 0.2, cab.z1 - 0.2), 0.35)
		box(ctx, "Trim", Vector3.new(0.45, 0.4, 0.7), Vector3.new(x, cab.yR + 0.3, cab.z1 - 0.4))
	end
	if f.fenderFlares then
		for _, w in geo.wells do
			for _, side in { -1, 1 } do
				box(ctx, "Trim", Vector3.new(0.35, 0.32, w.z1 - w.z0 + 0.3), Vector3.new(side * (W2 + 0.15), math.min(w.top, belt) - 0.12, (w.z0 + w.z1) / 2))
			end
		end
	end
	if f.bullbar then
		local z = zF - 0.55
		local top = geo.topAt(zF) + 0.2
		for _, side in { -1, 1 } do
			tube(ctx, "Trim", Vector3.new(side * 1.2, floor + 0.1, z), Vector3.new(side * 1.2, top, z), 0.28)
			tube(ctx, "Trim", Vector3.new(side * 1.2, floor + 0.3, z), Vector3.new(side * 1.2, floor + 0.3, zF + 0.1), 0.24)
		end
		tube(ctx, "Trim", Vector3.new(-1.25, top, z), Vector3.new(1.25, top, z), 0.28)
		tube(ctx, "Trim", Vector3.new(-W2 + 0.4, (floor + top) / 2, z + 0.1), Vector3.new(W2 - 0.4, (floor + top) / 2, z + 0.1), 0.26)
	end
	if f.pushBumper then
		local z = zF - 0.5
		local top = geo.topAt(zF) + 0.15
		for _, side in { -1, 1 } do
			box(ctx, "Dark", Vector3.new(0.3, top - floor, 0.3), Vector3.new(side * 0.9, (floor + top) / 2, z))
		end
		box(ctx, "Dark", Vector3.new(2.4, 0.3, 0.3), Vector3.new(0, floor + 0.5, z))
		box(ctx, "Dark", Vector3.new(2.4, 0.3, 0.3), Vector3.new(0, top - 0.2, z))
	end
	if f.mudFlaps then
		for _, a in geo.axles do
			for _, side in { -1, 1 } do
				box(ctx, "Dark", Vector3.new(a.width, 0.9, 0.08), Vector3.new(side * a.track / 2, 0.75, a.z + a.radius + 0.35))
			end
		end
	end
	if f.rallyLights and cab then
		for i = -1.5, 1.5 do
			local x = i * 0.85
			local pos = CFrame.new(x, cab.yR + 0.35, cab.z1 + 0.2) * CFrame.Angles(0, math.pi / 2, 0)
			cylinder(ctx, "Trim", 0.4, 0.62, pos)
			cylinder(ctx, "Light", 0.06, 0.5, pos * CFrame.new(0.21, 0, 0))
		end
		box(ctx, "Trim", Vector3.new(3.6, 0.12, 0.25), Vector3.new(0, cab.yR + 0.06, cab.z1 + 0.3))
	end
	if f.roofLights and cab then
		box(ctx, "Trim", Vector3.new(cab.gw - 0.2, 0.15, 0.3), Vector3.new(0, cab.yR + 0.2, cab.z1 + 0.25))
		for i = -2, 2 do
			cylinder(ctx, "Light", 0.3, 0.45, CFrame.new(i * 0.8, cab.yR + 0.5, cab.z1 + 0.15) * CFrame.Angles(0, math.pi / 2, 0))
		end
	end
	if f.antenna then
		tube(ctx, "Dark", Vector3.new(W2 - 1.0, belt, zR - 1.2), Vector3.new(W2 - 1.0, belt + 2.4, zR - 1.3), 0.08)
	end
	if f.raceNumber and ctx.decor then
		local zc = if cab then (cab.z0 + cab.z2) / 2 else 0
		local y = (floor + belt) / 2 + 0.1
		for _, side in { -1, 1 } do
			local p = box(ctx, "Plate", Vector3.new(0.04, 1.3, 1.3), Vector3.new(side * (W2 + 0.03), y, zc))
			p.Transparency = 1
			roundel(ctx, p, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, tostring(f.raceNumber))
		end
	end
	if f.taxiSign and cab then
		local sign = box(ctx, "Accent", Vector3.new(2.2, 0.65, 0.8), Vector3.new(0, cab.yR + 0.33, (cab.z1 + cab.z2) / 2))
		surfaceText(ctx, sign, Enum.NormalId.Front, "TAXI", Color3.fromRGB(255, 210, 40), Color3.fromRGB(20, 20, 24))
		surfaceText(ctx, sign, Enum.NormalId.Back, "TAXI", Color3.fromRGB(255, 210, 40), Color3.fromRGB(20, 20, 24))
	end
	if f.checker and ctx.decor then
		for _, side in { -1, 1 } do
			local strip = box(ctx, "Plate", Vector3.new(0.04, 0.5, geo.L - 3.2), Vector3.new(side * (W2 + 0.03), belt - 0.35, 0))
			strip.Transparency = 1
			local gui = Instance.new("SurfaceGui")
			gui.Face = if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.LightInfluence = 0.6
			local grid = Instance.new("UIGridLayout")
			local count = math.floor((geo.L - 3.2) / 0.25)
			grid.CellSize = UDim2.new(1 / count, 0, 0.5, 0)
			grid.CellPadding = UDim2.new()
			grid.SortOrder = Enum.SortOrder.LayoutOrder
			grid.Parent = gui
			for i = 1, count * 2 do
				local cell = Instance.new("Frame")
				cell.BorderSizePixel = 0
				local row = if i > count then 1 else 0
				cell.BackgroundColor3 = if (i + row) % 2 == 0 then Color3.fromRGB(15, 15, 18) else Color3.fromRGB(250, 250, 250)
				cell.LayoutOrder = i
				cell.Parent = gui
			end
			gui.Parent = strip
		end
	end
	if f.livery and cab then
		local zc = (cab.z0 + cab.z2) / 2
		for _, side in { -1, 1 } do
			slab(ctx, "Accent", side > 0 and W2 - 0.02 or -W2 - 0.04, side > 0 and W2 + 0.04 or -W2 + 0.02, floor + 0.3, belt - 0.1, cab.z0 + 0.3, cab.z2 - 0.4)
			if ctx.decor then
				local p = box(ctx, "Plate", Vector3.new(0.04, 0.8, cab.z2 - cab.z0 - 1), Vector3.new(side * (W2 + 0.06), (floor + belt) / 2, zc))
				p.Transparency = 1
				surfaceText(ctx, p, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, f.livery, Color3.fromRGB(20, 30, 70))
			end
		end
	end
	if f.medicCross and ctx.def.body.box and ctx.decor then
		local spec = ctx.def.body.box
		local zs = zF + spec.start
		local yc = (belt + spec.top) / 2 + 0.3
		for _, side in { -1, 1 } do
			local p = box(ctx, "Plate", Vector3.new(0.04, 2.4, 2.4), Vector3.new(side * (W2 + 0.05), yc, (zs + zR) / 2))
			p.Transparency = 1
			surfaceText(ctx, p, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, "+", Color3.fromRGB(220, 20, 30), nil, Enum.Font.GothamBlack)
		end
		local back = box(ctx, "Plate", Vector3.new(2.0, 2.0, 0.04), Vector3.new(0, spec.top - 1.4, zR + 0.06))
		back.Transparency = 1
		surfaceText(ctx, back, Enum.NormalId.Back, "+", Color3.fromRGB(220, 20, 30))
	end
	if f.routeSign and cab then
		local sign = box(ctx, "Dark", Vector3.new(geo.W - 2.4, 0.8, 0.12), Vector3.new(0, cab.yR - 0.55, zF - 0.02))
		surfaceText(ctx, sign, Enum.NormalId.Front, "42  CITY LOOP", Color3.fromRGB(255, 170, 30), Color3.fromRGB(10, 10, 12), Enum.Font.Code)
	end
	if f.busDoors and cab then
		for _, zc in { zF + 2.6, 1.0 } do
			box(ctx, "TintGlass", Vector3.new(0.08, cab.yR - belt + 2.2, 2.4), Vector3.new(W2 + 0.02, (belt - 2.2 + cab.yR) / 2, zc))
		end
	end

	-- emergency
	if f.siren and cab then
		local colors = SIREN_COLORS[f.siren] or SIREN_COLORS.police
		local roofTop = cab.yR
		local zc = cab.z1 + math.min(1.2, (cab.z2 - cab.z1) / 2)
		box(ctx, "Trim", Vector3.new(math.min(cab.gw - 0.4, 4.6), 0.2, 0.8), Vector3.new(0, roofTop + 0.1, zc))
		local half = math.min(cab.gw - 0.4, 4.6) / 2
		for i, x in { -half + 0.6, -half + 1.5, half - 1.5, half - 0.6 } do
			local role = if x < 0 then "SirenA" else "SirenB"
			local p = box(ctx, role, Vector3.new(0.85, 0.4, 0.7), Vector3.new(x, roofTop + 0.4, zc))
			p.Color = (if x < 0 then colors[1] else colors[2]):Lerp(Color3.new(0, 0, 0), 0.45)
			p.Name = "Siren" .. i
			if ctx.decor and not ctx.opts.preview and (i == 1 or i == 4) then
				local light = Instance.new("PointLight")
				light.Color = if x < 0 then colors[1] else colors[2]
				light.Range = 18
				light.Brightness = 3
				light.Enabled = false
				light.Shadows = false
				light.Parent = p
			end
		end
		if ctx.def.body.box and ctx.decor then
			-- extra beacons on the box corners
			local spec = ctx.def.body.box
			for i, x in { -W2 + 0.5, W2 - 0.5 } do
				local p = box(ctx, if i == 1 then "SirenA" else "SirenB", Vector3.new(0.5, 0.4, 0.5), Vector3.new(x, spec.top + 0.2, zR - 0.6))
				p.Color = colors[i]:Lerp(Color3.new(0, 0, 0), 0.45)
				p.Name = "Siren" .. (4 + i)
			end
		end
	end
	if f.ladder and ctx.def.body.box then
		local spec = ctx.def.body.box
		local y = spec.top + 0.55
		local zs = zF + spec.start + 0.8
		local ze = zR + 1.6
		for _, side in { -1, 1 } do
			beam(ctx, "Chrome", Vector3.new(side * 1.2, y, zs), Vector3.new(side * 1.2, y, ze), 0.22, 0.4)
		end
		local z = zs + 0.6
		while z < ze - 0.3 do
			box(ctx, "Chrome", Vector3.new(2.4, 0.12, 0.12), Vector3.new(0, y, z))
			z += 1.1
		end
		for _, zz in { zs + 1.0, ze - 3.0 } do
			box(ctx, "Trim", Vector3.new(2.8, 0.45, 0.5), Vector3.new(0, spec.top + 0.22, zz))
		end
		cylinder(ctx, "Trim", 0.5, 2.6, CFrame.new(0, spec.top + 0.25, zR - 2.0) * CFrame.Angles(0, 0, math.pi / 2))
	end
	if f.hoseReels and ctx.def.body.box then
		local spec = ctx.def.body.box
		for _, side in { -1, 1 } do
			cylinder(ctx, "Chrome", 0.5, 1.6, CFrame.new(side * (W2 + 0.2), belt + 1.0, zF + spec.start + 2.2))
			cylinder(ctx, "Accent", 0.52, 1.0, CFrame.new(side * (W2 + 0.21), belt + 1.0, zF + spec.start + 2.2))
			for i = 0, 2 do
				box(ctx, "Trim", Vector3.new(0.06, spec.top - belt - 0.8, 0.08), Vector3.new(side * (W2 + 0.02), (belt + spec.top) / 2, zF + spec.start + 4.5 + i * 4))
			end
		end
	end

	-- big trucks
	if f.stacks and cab then
		local top = (if ctx.def.body.box then ctx.def.body.box.top else cab.yR) + 1.4
		local z = if geo.hullEnd < zR then geo.hullEnd + 0.4 else cab.z2 + 0.3
		for _, side in { -1, 1 } do
			local x = side * (W2 - 0.3)
			tube(ctx, "Chrome", Vector3.new(x, belt - 0.6, z), Vector3.new(x, top, z), 0.42)
			tube(ctx, "Dark", Vector3.new(x, top, z), Vector3.new(x, top + 0.12, z), 0.44)
		end
	end
	if f.fuelTanks and #geo.axles >= 2 then
		local z0 = geo.axles[1].z + geo.axles[1].radius + 0.6
		local z1 = geo.axles[2].z - geo.axles[2].radius - 0.6
		for _, side in { -1, 1 } do
			local x = side * (W2 - 0.9)
			cylinder(ctx, "Chrome", z1 - z0, 1.5, CFrame.new(x, floor + 0.2, (z0 + z1) / 2) * CFrame.Angles(0, math.pi / 2, 0))
		end
	end
	if f.visor and cab then
		box(ctx, "Paint", Vector3.new(cab.gw + 0.2, 0.15, 0.9), CFrame.new(0, cab.yR - 0.05, cab.z1 - 0.35) * CFrame.Angles(math.rad(-10), 0, 0))
		if ctx.def.body.box then
			local spec = ctx.def.body.box
			local h = spec.top - cab.yR
			if h > 0.2 then
				wedge(ctx, "Paint", Vector3.new(cab.gw, h, math.min(2.4, cab.z2 - cab.z1)), Vector3.new(0, cab.yR + h / 2, cab.z2 - math.min(2.4, cab.z2 - cab.z1) / 2), true)
			end
		end
	end

	-- novelty
	if f.iceCream and ctx.def.body.box then
		local spec = ctx.def.body.box
		local base = Vector3.new(0, spec.top, zF + spec.start + 2.2)
		for i = 0, 4 do
			local d = 0.5 + i * 0.32
			cylinder(ctx, "Plate", 0.42, d, CFrame.new(base + Vector3.new(0, 0.2 + i * 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2)).Color =
				Color3.fromRGB(214, 160, 90)
		end
		ball(ctx, "Plate", 2.2, base + Vector3.new(0, 2.6, 0)).Color = Color3.fromRGB(255, 190, 220)
		ball(ctx, "Plate", 1.7, base + Vector3.new(0, 3.6, 0)).Color = Color3.fromRGB(150, 236, 200)
		ball(ctx, "Plate", 0.5, base + Vector3.new(0, 4.5, 0)).Color = Color3.fromRGB(220, 20, 40)
	end
	if f.servingWindow and ctx.def.body.box then
		local spec = ctx.def.body.box
		local zs = zF + spec.start
		local zc = (zs + zR) / 2
		local yc = (belt + spec.top) / 2 + 0.2
		box(ctx, "TintGlass", Vector3.new(0.08, 1.8, 4.2), Vector3.new(W2 + 0.03, yc, zc))
		box(ctx, "Plate", Vector3.new(0.6, 0.12, 4.4), Vector3.new(W2 + 0.3, yc - 1.0, zc))
		for i = 0, 5 do
			local stripe = wedge(ctx, if i % 2 == 0 then "Accent" else "White", Vector3.new(4.4 / 6, 0.5, 1.2), Vector3.new(0, 0, 0), true)
			stripe.CFrame = CFrame.new(W2 + 0.55, yc + 1.25, zc - 2.2 + 4.4 / 12 + i * 4.4 / 6) * CFrame.Angles(0, -math.pi / 2, 0)
		end
	end
end

--------------------------------------------------------------------------------
-- Special styles
--------------------------------------------------------------------------------

local function suspensionArms(ctx: Ctx, geo: Geo, mountHalf: number, y: number)
	for _, a in geo.axles do
		for _, side in { -1, 1 } do
			local hub = Vector3.new(side * (a.track / 2 - a.width / 2), a.radius, a.z)
			tube(ctx, "Dark", Vector3.new(side * mountHalf, y + 0.15, a.z - 0.6), hub, 0.16)
			tube(ctx, "Dark", Vector3.new(side * mountHalf, y + 0.15, a.z + 0.6), hub, 0.16)
		end
	end
end

local function buildOpenWheel(ctx: Ctx, geo: Geo)
	local floor = geo.floor
	local zF, zR = geo.zF, geo.zR
	local front = geo.axles[1]
	local rear = geo.axles[#geo.axles]
	local tubW = 2.4
	local tubTop = floor + 1.3
	local cockpitZ0 = -1.4
	-- monocoque
	slab(ctx, "Paint", -tubW / 2, tubW / 2, floor, tubTop, front.z + 0.6, rear.z - 0.6)
	-- cockpit opening rim
	slab(ctx, "Dark", -0.9, 0.9, tubTop, tubTop + 0.04, cockpitZ0, cockpitZ0 + 3.0)
	-- nose cone (tapering down towards the front)
	wedge(ctx, "Paint", Vector3.new(1.6, 1.0, front.z + 0.6 - (zF + 0.9)), Vector3.new(0, floor + 0.5, (zF + 0.9 + front.z + 0.6) / 2), true)
	box(ctx, "Accent", Vector3.new(1.0, 0.06, 2.4), Vector3.new(0, floor + 0.85, front.z - 0.6))
	-- front wing
	local fwW = front.track + front.width + 0.2
	box(ctx, "Accent", Vector3.new(fwW, 0.12, 1.4), Vector3.new(0, 0.42, zF + 0.6))
	box(ctx, "Paint", Vector3.new(fwW - 0.6, 0.1, 0.7), CFrame.new(0, 0.62, zF + 1.1) * CFrame.Angles(math.rad(-14), 0, 0))
	for _, side in { -1, 1 } do
		box(ctx, "Trim", Vector3.new(0.1, 0.7, 1.6), Vector3.new(side * fwW / 2, 0.6, zF + 0.7))
	end
	-- sidepods
	local spZ0 = front.z + front.radius + 0.9
	local spZ1 = rear.z - rear.radius - 0.4
	for _, side in { -1, 1 } do
		local x0 = side * tubW / 2
		local x1 = side * (tubW / 2 + 1.6)
		slab(ctx, "Paint", math.min(x0, x1), math.max(x0, x1), floor, floor + 1.0, spZ0, spZ1 - 1.2)
		wedge(ctx, "Paint", Vector3.new(1.6, 1.0, 1.2), Vector3.new((x0 + x1) / 2, floor + 0.5, spZ1 - 0.6), false)
		box(ctx, "Dark", Vector3.new(1.4, 0.8, 0.08), Vector3.new((x0 + x1) / 2, floor + 0.5, spZ0 - 0.03))
	end
	-- engine cover + airbox
	wedge(ctx, "Paint", Vector3.new(1.8, 1.4, rear.z - cockpitZ0 - 3.0), Vector3.new(0, tubTop + 0.7, (cockpitZ0 + 3.0 + rear.z) / 2), false)
	box(ctx, "Paint", Vector3.new(1.0, 1.4, 1.2), Vector3.new(0, tubTop + 0.7, cockpitZ0 + 3.6))
	box(ctx, "Dark", Vector3.new(0.7, 0.6, 0.08), Vector3.new(0, tubTop + 0.95, cockpitZ0 + 2.98))
	-- halo
	local hz = cockpitZ0 + 0.2
	tube(ctx, "Trim", Vector3.new(0, tubTop, hz - 0.6), Vector3.new(0, tubTop + 1.4, hz), 0.2)
	for _, side in { -1, 1 } do
		tube(ctx, "Trim", Vector3.new(0, tubTop + 1.4, hz), Vector3.new(side * 0.85, tubTop + 1.3, hz + 1.4), 0.2)
		tube(ctx, "Trim", Vector3.new(side * 0.85, tubTop + 1.3, hz + 1.4), Vector3.new(side * 0.95, tubTop, hz + 2.2), 0.2)
	end
	-- rear wing
	local rwZ = zR - 0.7
	local rwW = 5.6
	box(ctx, "Trim", Vector3.new(0.2, 1.8, 0.5), Vector3.new(0, floor + 1.7, rwZ))
	box(ctx, "Accent", Vector3.new(rwW, 0.18, 1.2), CFrame.new(0, floor + 2.7, rwZ) * CFrame.Angles(math.rad(-10), 0, 0))
	box(ctx, "Paint", Vector3.new(rwW, 0.14, 0.7), CFrame.new(0, floor + 3.15, rwZ + 0.3) * CFrame.Angles(math.rad(-22), 0, 0))
	for _, side in { -1, 1 } do
		box(ctx, "Paint", Vector3.new(0.12, 1.4, 1.6), Vector3.new(side * rwW / 2, floor + 2.7, rwZ + 0.1))
	end
	-- rear light
	box(ctx, "Taillight", Vector3.new(0.5, 0.3, 0.08), Vector3.new(0, floor + 0.9, rwZ + 0.3))
	suspensionArms(ctx, geo, tubW / 2, floor + 0.3)
	if ctx.def.features.raceNumber and ctx.decor then
		local p = box(ctx, "Plate", Vector3.new(0.9, 0.04, 0.9), Vector3.new(0, floor + 0.95, front.z - 1.6))
		p.Transparency = 1
		roundel(ctx, p, Enum.NormalId.Top, tostring(ctx.def.features.raceNumber))
	end
	hull(ctx, Vector3.new(tubW + 3.2, 1.3, rear.z - front.z), Vector3.new(0, floor + 0.65, (front.z + rear.z) / 2))
	hull(ctx, Vector3.new(1.6, 1.0, front.z - zF), Vector3.new(0, floor + 0.5, (zF + front.z) / 2))
end

local function buildKart(ctx: Ctx, geo: Geo)
	local floor = geo.floor
	local zF, zR = geo.zF, geo.zR
	local W2 = geo.W / 2
	slab(ctx, "Trim", -1.6, 1.6, floor, floor + 0.18, zF + 1.0, zR - 0.8)
	-- bumpers
	tube(ctx, "Chrome", Vector3.new(-W2 + 0.6, floor + 0.35, zF + 0.3), Vector3.new(W2 - 0.6, floor + 0.35, zF + 0.3), 0.22)
	tube(ctx, "Chrome", Vector3.new(-W2 + 0.4, floor + 0.35, zR - 0.3), Vector3.new(W2 - 0.4, floor + 0.35, zR - 0.3), 0.22)
	-- side pods and nose
	local a1, a2 = geo.axles[1], geo.axles[2]
	for _, side in { -1, 1 } do
		slab(ctx, "Paint", side > 0 and 1.0 or -2.0, side > 0 and 2.0 or -1.0, floor + 0.05, floor + 0.55, a1.z + a1.radius + 0.25, a2.z - a2.radius - 0.25)
	end
	wedge(ctx, "Paint", Vector3.new(2.4, 0.8, 2.0), Vector3.new(0, floor + 0.5, zF + 1.5), true)
	-- seat
	local seats = CarBuilder.getSeats(ctx.def)
	local sp = seats[1].pos
	box(ctx, "Interior", Vector3.new(1.6, 0.3, 1.5), Vector3.new(sp.X, sp.Y - 0.15, sp.Z))
	box(ctx, "Interior", Vector3.new(1.6, 1.6, 0.3), CFrame.new(sp.X, sp.Y + 0.75, sp.Z + 0.85) * CFrame.Angles(math.rad(-12), 0, 0))
	-- steering
	tube(ctx, "Trim", Vector3.new(0, floor + 0.3, zF + 2.2), Vector3.new(0, floor + 1.4, sp.Z - 1.5), 0.15)
	cylinder(ctx, "Trim", 0.15, 1.1, CFrame.new(0, floor + 1.45, sp.Z - 1.45) * CFrame.Angles(math.rad(-35), 0, 0) * CFrame.Angles(0, math.pi / 2, 0))
	-- engine
	box(ctx, "Trim", Vector3.new(1.0, 0.9, 1.0), Vector3.new(1.1, floor + 0.6, zR - 1.6))
	tube(ctx, "Chrome", Vector3.new(1.5, floor + 0.7, zR - 1.6), Vector3.new(1.9, floor + 0.7, zR - 0.6), 0.25)
	attachment(ctx, "Exhaust1", Vector3.new(1.9, floor + 0.7, zR - 0.5))
	box(ctx, "Taillight", Vector3.new(0.6, 0.2, 0.06), Vector3.new(0, floor + 0.45, zR - 0.15))
	if ctx.def.features.raceNumber and ctx.decor then
		local p = box(ctx, "Plate", Vector3.new(1.0, 0.8, 0.04), CFrame.new(0, floor + 0.7, zF + 0.55) * CFrame.Angles(math.rad(-38), 0, 0))
		p.Transparency = 1
		roundel(ctx, p, Enum.NormalId.Front, tostring(ctx.def.features.raceNumber))
	end
	hull(ctx, Vector3.new(geo.W - 0.4, 0.6, geo.L - 0.4), Vector3.new(0, floor + 0.3, 0))
end

local function buildBuggy(ctx: Ctx, geo: Geo)
	local floor = geo.floor
	local zF, zR = geo.zF, geo.zR
	slab(ctx, "Trim", -2.0, 2.0, floor, floor + 0.3, zF + 1.2, zR - 1.4)
	local x = 1.9
	local zA, zB = -1.8, 2.2
	local top = floor + 4.4
	local frameRole = "Paint"
	for _, s in { -1, 1 } do
		local sx = s * x
		tube(ctx, frameRole, Vector3.new(sx, floor + 0.3, zA), Vector3.new(sx * 0.85, top, zA + 0.8), 0.3)
		tube(ctx, frameRole, Vector3.new(sx, floor + 0.3, zB), Vector3.new(sx * 0.85, top, zB - 0.3), 0.3)
		tube(ctx, frameRole, Vector3.new(sx * 0.85, top, zA + 0.8), Vector3.new(sx * 0.85, top, zB - 0.3), 0.3)
		tube(ctx, frameRole, Vector3.new(sx, floor + 0.3, zA), Vector3.new(sx * 0.7, floor + 1.2, zF + 0.8), 0.28)
		tube(ctx, frameRole, Vector3.new(sx, floor + 0.3, zB), Vector3.new(sx * 0.8, floor + 1.0, zR - 0.4), 0.28)
		tube(ctx, frameRole, Vector3.new(sx * 0.85, top, zB - 0.3), Vector3.new(sx * 0.8, floor + 1.0, zR - 0.4), 0.26)
		tube(ctx, frameRole, Vector3.new(sx, floor + 1.4, zA + 0.2), Vector3.new(sx, floor + 1.4, zB), 0.24)
	end
	tube(ctx, frameRole, Vector3.new(-x * 0.85, top, zA + 0.8), Vector3.new(x * 0.85, top, zA + 0.8), 0.3)
	tube(ctx, frameRole, Vector3.new(-x * 0.85, top, zB - 0.3), Vector3.new(x * 0.85, top, zB - 0.3), 0.3)
	tube(ctx, frameRole, Vector3.new(-x * 0.7, floor + 1.2, zF + 0.8), Vector3.new(x * 0.7, floor + 1.2, zF + 0.8), 0.28)
	-- nose panel and hood
	wedge(ctx, "Accent", Vector3.new(2.6, 0.9, zA - zF - 0.8), Vector3.new(0, floor + 0.75, (zF + 0.8 + zA) / 2), true)
	-- roof light bar
	box(ctx, "Trim", Vector3.new(2.8, 0.15, 0.25), Vector3.new(0, top + 0.18, zA + 0.8))
	for _, lx in { -0.8, 0.8 } do
		cylinder(ctx, "Light", 0.3, 0.5, CFrame.new(lx, top + 0.45, zA + 0.75) * CFrame.Angles(0, math.pi / 2, 0))
	end
	-- seat
	local sp = CarBuilder.getSeats(ctx.def)[1].pos
	box(ctx, "Interior", Vector3.new(1.7, 0.3, 1.6), Vector3.new(sp.X, sp.Y - 0.15, sp.Z))
	box(ctx, "Interior", Vector3.new(1.7, 2.0, 0.35), CFrame.new(sp.X, sp.Y + 0.95, sp.Z + 0.9) * CFrame.Angles(math.rad(-10), 0, 0))
	cylinder(ctx, "Trim", 0.15, 1.2, CFrame.new(sp.X, sp.Y + 1.7, sp.Z - 1.6) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.Angles(0, math.pi / 2, 0))
	tube(ctx, "Trim", Vector3.new(sp.X, sp.Y + 1.7, sp.Z - 1.6), Vector3.new(sp.X, floor + 0.8, zA - 0.6), 0.14)
	-- exposed engine
	box(ctx, "Trim", Vector3.new(2.0, 1.2, 1.6), Vector3.new(0, floor + 0.9, zR - 1.6))
	for _, ex in { -0.5, 0.5 } do
		cylinder(ctx, "Chrome", 0.5, 0.5, CFrame.new(ex, floor + 1.7, zR - 1.6) * CFrame.Angles(0, 0, math.pi / 2))
	end
	for i, ex in { -0.7, 0.7 } do
		tube(ctx, "Chrome", Vector3.new(ex, floor + 1.0, zR - 0.8), Vector3.new(ex, floor + 1.6, zR + 0.1), 0.28)
		attachment(ctx, "Exhaust" .. i, Vector3.new(ex, floor + 1.7, zR + 0.25))
	end
	for _, side in { -1, 1 } do
		box(ctx, "Taillight", Vector3.new(0.4, 0.3, 0.08), Vector3.new(side * 1.5, floor + 1.2, zR - 0.35))
		box(ctx, "Headlight", Vector3.new(0.5, 0.35, 0.08), Vector3.new(side * 0.9, floor + 0.9, zF + 0.75))
	end
	suspensionArms(ctx, geo, 1.9, floor + 0.2)
	hull(ctx, Vector3.new(4.2, 1.4, geo.L - 1.6), Vector3.new(0, floor + 0.7, 0))
	hull(ctx, Vector3.new(3.4, 0.3, 4.0), Vector3.new(0, top, (zA + zB) / 2 + 0.25))
end

local function buildTractor(ctx: Ctx, geo: Geo)
	local floor = geo.floor
	local zF = geo.zF
	local front, rear = geo.axles[1], geo.axles[2]
	-- hood and engine
	local hoodW = 3.0
	local hoodTop = floor + 2.4
	slab(ctx, "Paint", -hoodW / 2, hoodW / 2, floor, hoodTop, zF + 0.6, rear.z - 1.2)
	wedge(ctx, "Paint", Vector3.new(hoodW, 0.4, 1.2), Vector3.new(0, hoodTop + 0.2, rear.z - 1.8), true)
	box(ctx, "Dark", Vector3.new(hoodW - 0.4, 1.6, 0.1), Vector3.new(0, floor + 1.2, zF + 0.56))
	for _, side in { -1, 1 } do
		box(ctx, "Headlight", Vector3.new(0.45, 0.4, 0.1), Vector3.new(side * 1.0, hoodTop - 0.3, zF + 0.55))
		for i = 0, 3 do
			box(ctx, "Dark", Vector3.new(0.05, 0.12, 1.4), Vector3.new(side * (hoodW / 2 + 0.02), floor + 1.0 + i * 0.3, zF + 3.0))
		end
	end
	-- front weights
	slab(ctx, "Trim", -1.4, 1.4, floor - 0.4, floor + 0.6, zF, zF + 0.6)
	-- exhaust stack
	tube(ctx, "Trim", Vector3.new(0.8, hoodTop, zF + 2.4), Vector3.new(0.8, hoodTop + 2.2, zF + 2.4), 0.3)
	attachment(ctx, "Exhaust1", Vector3.new(0.8, hoodTop + 2.3, zF + 2.4))
	-- rear body, fenders
	slab(ctx, "Paint", -2.4, 2.4, floor, floor + 1.4, rear.z - 1.6, rear.z + 1.4)
	for _, side in { -1, 1 } do
		local x = side * rear.track / 2
		box(ctx, "Accent", Vector3.new(rear.width + 0.5, 0.25, rear.radius * 2 + 0.6), Vector3.new(x, rear.radius * 2 + 0.3, rear.z))
		box(ctx, "Accent", Vector3.new(rear.width + 0.5, 0.9, 0.25), Vector3.new(x, rear.radius * 2 - 0.15, rear.z - rear.radius - 0.2))
		box(ctx, "Taillight", Vector3.new(0.3, 0.3, 0.08), Vector3.new(side * 2.0, floor + 1.1, rear.z + 1.43))
	end
	-- ROPS cab
	local sp = CarBuilder.getSeats(ctx.def)[1].pos
	local roofY = sp.Y + 4.4
	for _, side in { -1, 1 } do
		for _, zz in { rear.z - 1.4, rear.z + 1.2 } do
			tube(ctx, "Trim", Vector3.new(side * 1.9, floor + 1.4, zz), Vector3.new(side * 1.9, roofY, zz), 0.25)
		end
	end
	slab(ctx, "Paint", -2.3, 2.3, roofY, roofY + 0.25, rear.z - 1.8, rear.z + 1.6)
	box(ctx, "Interior", Vector3.new(1.6, 0.35, 1.4), Vector3.new(sp.X, sp.Y - 0.17, sp.Z))
	box(ctx, "Interior", Vector3.new(1.6, 1.6, 0.3), CFrame.new(sp.X, sp.Y + 0.8, sp.Z + 0.8) * CFrame.Angles(math.rad(-8), 0, 0))
	cylinder(ctx, "Trim", 0.15, 1.1, CFrame.new(sp.X, sp.Y + 1.6, sp.Z - 1.4) * CFrame.Angles(math.rad(-40), 0, 0) * CFrame.Angles(0, math.pi / 2, 0))
	-- front axle beam
	tube(ctx, "Dark", Vector3.new(-front.track / 2 + 0.4, front.radius, front.z), Vector3.new(front.track / 2 - 0.4, front.radius, front.z), 0.35)
	hull(ctx, Vector3.new(hoodW, hoodTop - floor, rear.z - zF - 1.8), Vector3.new(0, (floor + hoodTop) / 2, (zF + 0.6 + rear.z - 1.2) / 2))
	hull(ctx, Vector3.new(4.8, 1.4, 3.0), Vector3.new(0, floor + 0.7, rear.z - 0.1))
end

local function buildMonsterExtras(ctx: Ctx, geo: Geo)
	if not ctx.def.features.monster then
		return
	end
	for _, a in geo.axles do
		tube(ctx, "Dark", Vector3.new(-a.track / 2 + a.width / 2, a.radius, a.z), Vector3.new(a.track / 2 - a.width / 2, a.radius, a.z), 0.6)
		for _, side in { -1, 1 } do
			local hub = Vector3.new(side * (a.track / 2 - a.width / 2 - 0.3), a.radius, a.z)
			tube(ctx, "Chrome", hub, Vector3.new(side * (geo.innerHalf - 0.4), geo.floor + 0.2, a.z - 0.5), 0.35)
			tube(ctx, "Accent", hub, Vector3.new(side * (geo.innerHalf - 0.4), geo.floor + 0.2, a.z + 0.5), 0.3)
		end
	end
	slab(ctx, "Trim", -1.0, 1.0, geo.axles[1].radius - 0.3, geo.floor, geo.axles[1].z, geo.axles[#geo.axles].z)
end

--------------------------------------------------------------------------------
-- Wheels, seats, interior
--------------------------------------------------------------------------------

local function buildWheels(ctx: Ctx, geo: Geo)
	local def = ctx.def
	local rimStyle = def.wheels.rim or "disc"
	local rest = def.stats.suspension.rest
	local freq = def.stats.suspension.freq or 2.6
	local omega = 2 * math.pi * freq
	local gravity = workspace.Gravity
	local sag = math.min(gravity / (omega * omega), rest * 0.85)
	local staticLen = rest - sag
	local index = 0
	for axleIndex, a in geo.axles do
		for _, side in { -1, 1 } do
			index += 1
			local r, w = a.radius, a.width
			local center = Vector3.new(side * a.track / 2, r, a.z)
			local tire = makePart(ctx, "Part", "Tire", Vector3.new(w, r * 2, r * 2), CFrame.new(center), ctx.model);
			(tire :: Part).Shape = Enum.PartType.Cylinder
			tire.Name = "Wheel_" .. index
			tire.CastShadow = true
			local rimParts = {}
			local outer = side * (w / 2)
			local function add(p: BasePart?)
				if p then
					p.Parent = tire
					table.insert(rimParts, p)
				end
			end
			local rimD = r * 2 * (if rimStyle == "offroad" then 0.52 else 0.64)
			add(cylinder(ctx, "Rim", w * 0.5, rimD, CFrame.new(center + Vector3.new(outer - side * w * 0.22, 0, 0))))
			add(cylinder(ctx, "Dark", 0.05, rimD * 0.92, CFrame.new(center + Vector3.new(outer + side * 0.035, 0, 0))))
			if rimStyle == "aero" then
				add(cylinder(ctx, "Rim", 0.06, rimD * 0.95, CFrame.new(center + Vector3.new(outer + side * 0.07, 0, 0))))
				for k = 0, 2 do
					local ang = k * math.pi * 2 / 3
					local p = box(ctx, "Dark", Vector3.new(0.04, rimD * 0.5, 0.12), CFrame.new(center + Vector3.new(outer + side * 0.1, 0, 0)) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, rimD * 0.2, 0))
					add(p)
				end
			elseif rimStyle == "spoke" or rimStyle == "star" then
				local n = if rimStyle == "spoke" then 6 else 5
				for k = 0, n - 1 do
					local ang = k * math.pi * 2 / n
					local p = box(ctx, "Rim", Vector3.new(0.12, rimD * 0.46, 0.22), CFrame.new(center + Vector3.new(outer + side * 0.07, 0, 0)) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, rimD * 0.24, 0))
					add(p)
				end
			elseif rimStyle == "steel" then
				for k = 0, 3 do
					local ang = k * math.pi / 2 + math.pi / 4
					local p = cylinder(ctx, "Dark", 0.06, rimD * 0.16, CFrame.new(center + Vector3.new(outer + side * 0.06, 0, 0)) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, rimD * 0.3, 0))
					add(p)
				end
				add(cylinder(ctx, "Rim", 0.06, rimD * 0.75, CFrame.new(center + Vector3.new(outer + side * 0.05, 0, 0))))
			elseif rimStyle == "offroad" then
				for k = 0, 5 do
					local ang = k * math.pi / 3
					local p = box(ctx, "Rim", Vector3.new(0.12, rimD * 0.4, 0.3), CFrame.new(center + Vector3.new(outer + side * 0.07, 0, 0)) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, rimD * 0.25, 0))
					add(p)
				end
				-- chunky tread blocks on the shoulder
				for k = 0, 11 do
					local ang = k * math.pi / 6
					local p = box(ctx, "Tire", Vector3.new(w * 1.02, 0.18, r * 0.42), CFrame.new(center) * CFrame.Angles(ang, 0, 0) * CFrame.new(0, r - 0.05, 0))
					add(p)
				end
			end
			add(cylinder(ctx, "Chrome", 0.1, r * 0.32, CFrame.new(center + Vector3.new(outer + side * 0.12, 0, 0))))

			if not ctx.anchored then
				for _, p in rimParts do
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = tire
					weld.Part1 = p
					weld.Parent = p
				end
				local motor = Instance.new("Motor6D")
				motor.Name = "Axle"
				motor.Part0 = ctx.chassis
				motor.Part1 = tire
				motor.C0 = ctx.chassis.CFrame:ToObjectSpace(CFrame.new(center))
				motor.C1 = CFrame.new()
				motor.Parent = tire
			end

			-- data for physics and visuals
			local mountWorld = center + Vector3.new(0, staticLen, 0)
			tire:SetAttribute("Wheel", true)
			tire:SetAttribute("Index", index)
			tire:SetAttribute("Axle", axleIndex)
			tire:SetAttribute("Mount", ctx.chassis.CFrame:PointToObjectSpace(mountWorld))
			tire:SetAttribute("Radius", r)
			tire:SetAttribute("Width", w)
			tire:SetAttribute("Steer", a.steer)
			tire:SetAttribute("Drive", a.drive)
			tire:SetAttribute("Side", side)
			tire:SetAttribute("StaticLen", staticLen)

			if not a.steer then
				attachment(ctx, "SkidA_" .. index, Vector3.new(side * a.track / 2 - w * 0.4, 0.06, a.z))
				attachment(ctx, "SkidB_" .. index, Vector3.new(side * a.track / 2 + w * 0.4, 0.06, a.z))
			end
		end
	end
end

local function buildSeats(ctx: Ctx, geo: Geo)
	local seats = CarBuilder.getSeats(ctx.def)
	local style = ctx.def.body.style
	local custom = style == "kart" or style == "buggy" or style == "tractor"
	local cab = geo.cabin
	local passengerIndex = 0
	for _, s in seats do
		local p = s.pos
		if not custom then
			-- visible seat
			local backH = if cab then math.min(2.3, cab.yR - p.Y - 0.35) else 2.0
			local cushionBottom = math.max(p.Y - 0.4, geo.floor + 0.02)
			if p.Y - cushionBottom > 0.08 then
				slab(ctx, "Interior", p.X - 0.9, p.X + 0.9, cushionBottom, p.Y, p.Z - 0.85, p.Z + 0.85)
			end
			box(ctx, "Interior", Vector3.new(1.8, backH, 0.35), CFrame.new(p.X, p.Y + backH / 2, p.Z + 0.95) * CFrame.Angles(math.rad(-8), 0, 0))
			if s.driver then
				local swY = if cab then math.max(p.Y + 1.5, geo.belt + 0.35) else p.Y + 1.5
				local swZ = if cab then math.max(cab.z0 + (cab.z1 - cab.z0) * 0.75, p.Z - 2.0) else p.Z - 1.6
				cylinder(ctx, "Trim", 0.14, 1.15, CFrame.new(p.X, swY, swZ) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.Angles(0, math.pi / 2, 0))
			end
		end
		if ctx.opts.preview or ctx.opts.showroom then
			continue
		end
		local seat: Seat | VehicleSeat
		if s.driver then
			local vs = Instance.new("VehicleSeat")
			vs.Name = "DriveSeat"
			vs.MaxSpeed = 0
			vs.Torque = 0
			vs.TurnSpeed = 0
			vs.HeadsUpDisplay = false
			seat = vs
		else
			passengerIndex += 1
			local ps = Instance.new("Seat")
			ps.Name = "Seat_" .. passengerIndex
			seat = ps
		end
		seat.Size = Vector3.new(1.6, 0.2, 1.6)
		seat.CFrame = CFrame.new(p.X, p.Y - 0.1, p.Z)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.CanTouch = false -- players sit only through prompts
		seat.CanQuery = false
		seat.Massless = true
		seat.Anchored = false
		seat.Parent = ctx.model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = ctx.chassis
		weld.Part1 = seat
		weld.Parent = seat
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SitPrompt"
		prompt.ActionText = if s.driver then "Drive" else "Sit"
		prompt.ObjectText = ctx.def.name
		prompt.KeyboardKeyCode = if s.driver then Enum.KeyCode.E else Enum.KeyCode.F
		prompt.GamepadKeyCode = if s.driver then Enum.KeyCode.ButtonY else Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt:SetAttribute("LocAction", if s.driver then "PromptDrive" else "PromptSit")
		prompt.Parent = seat
	end
	ctx.seatCount = #seats
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local function makeChassis(ctx: Ctx, geo: Geo): BasePart
	local def = ctx.def
	local zSum, rSum, minTrack = 0, 0, math.huge
	for _, a in geo.axles do
		zSum += a.z
		rSum += a.radius
		minTrack = math.min(minTrack, a.track - a.width)
	end
	local cz = zSum / #geo.axles
	local avgR = rSum / #geo.axles
	local cy = math.min(def.body.floor + 0.5, avgR + 0.25)
	local frontZ = geo.axles[1].z
	local rearZ = geo.axles[#geo.axles].z
	local length = math.max(rearZ - frontZ, 4) * 1.1
	local width = math.max(minTrack, 2)
	local size = Vector3.new(width, 1.6, length)
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = size
	chassis.CFrame = CFrame.new(0, cy, cz)
	chassis.Transparency = 1
	chassis.CanCollide = false
	chassis.CanTouch = false
	chassis.CanQuery = false
	chassis.Anchored = ctx.anchored
	chassis.CastShadow = false
	chassis.RootPriority = 127
	local targetMass = 420 * def.stats.mass
	local density = math.clamp(targetMass / (size.X * size.Y * size.Z), 0.5, 100)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(density, 0.3, 0.1, 1, 1)
	chassis.Parent = ctx.model
	return chassis
end

function CarBuilder.build(def: CarDef, opts: BuildOptions?): Model
	local o: BuildOptions = opts or {}
	local save = o.save or CarCatalog.defaultSave(def)
	local model = Instance.new("Model")
	model.Name = def.id
	local body = Instance.new("Folder")
	body.Name = "Body"
	body.Parent = model

	local anchored = o.preview == true or o.showroom == true
	local ctx: Ctx = {
		def = def,
		save = save,
		opts = o,
		model = model,
		body = body,
		chassis = nil :: any,
		anchored = anchored,
		decor = not o.preview,
		seatCount = 0,
	}
	local geo = measure(def)
	ctx.chassis = makeChassis(ctx, geo)
	model.PrimaryPart = ctx.chassis

	local style = def.body.style
	if style == "openwheel" then
		buildOpenWheel(ctx, geo)
	elseif style == "kart" then
		buildKart(ctx, geo)
	elseif style == "buggy" then
		buildBuggy(ctx, geo)
	elseif style == "tractor" then
		buildTractor(ctx, geo)
	else
		buildLowerBody(ctx, geo)
		buildBed(ctx, geo)
		buildCabin(ctx, geo)
		buildBox(ctx, geo)
		buildSemiFrame(ctx, geo)
		buildBumpersAndLights(ctx, geo)
		buildDoors(ctx, geo)
		buildFeatures(ctx, geo)
		buildMonsterExtras(ctx, geo)
		local hullTop = math.min(geo.belt, geo.topAt(0))
		local hullEnd = geo.bedStart or geo.hullEnd
		local hullBottom = geo.floor + CarBuilder.HullLift
		hull(
			ctx,
			Vector3.new(geo.W, hullTop - hullBottom, hullEnd - geo.zF - 0.3),
			Vector3.new(0, (hullBottom + hullTop) / 2, (geo.zF + hullEnd) / 2)
		)
	end
	buildWheels(ctx, geo)
	buildSeats(ctx, geo)

	-- weld everything visual to the chassis
	if not anchored then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= ctx.chassis and d:GetAttribute("Wheel") == nil then
				local parent = d.Parent
				local isRimPart = parent and parent:IsA("BasePart") and parent:GetAttribute("Wheel") ~= nil
				local hasWeld = d:FindFirstChildOfClass("WeldConstraint") ~= nil
				if not isRimPart and not hasWeld then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = ctx.chassis
					weld.Part1 = d
					weld.Parent = d
				end
			end
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CollisionGroup = "Cars"
			end
		end
	end

	model:SetAttribute("CarId", def.id)
	model:SetAttribute("Seats", ctx.seatCount)
	model:SetAttribute("HasSiren", def.features.siren ~= nil)
	if def.features.siren then
		model:SetAttribute("SirenType", def.features.siren)
	end
	return model
end

-- Re-applies paint, finish, rims and underglow to an existing model.
function CarBuilder.applyPaint(model: Model, save: CarSave)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Role")
			if role == "Paint" or role == "Accent" or role == "NeonAccent" or role == "Rim" or role == "Glow" then
				applyRole(d, role, save)
			end
		end
	end
end

-- Approximate bounding size of a car (for spawn spacing and cameras).
function CarBuilder.getExtents(def: CarDef): Vector3
	local maxR = 0
	local maxTrack = 0
	for _, a in CarCatalog.getAxles(def) do
		maxR = math.max(maxR, a.radius)
		maxTrack = math.max(maxTrack, a.track + a.width)
	end
	local geo = measure(def)
	local height = def.body.belt
	if geo.cabin then
		height = geo.cabin.yR
	end
	if def.body.box then
		height = math.max(height, def.body.box.top)
	end
	return Vector3.new(math.max(def.body.width, maxTrack), math.max(height, maxR * 2) + 0.5, def.body.length)
end

return CarBuilder
