-- Workshop: the hands-on part of the car service. The camera orbits the
-- vehicle in its bay and you hold the mouse button (or a finger) and move the
-- tool over the body: mud turns into foam, the sponge scrubs it into suds,
-- the hose rinses them into drops and the towel dries them off. Repairs are
-- done with a wrench on the damaged spots and a pump on every tyre; paint jobs
-- sand the rusty spots and then spray the new colour part by part.
--
-- The client only reports "step N finished"; the server checks the timing,
-- pays and moves the vehicle (Systems/Service).

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local CarCatalog = require(Shared.CarCatalog)
local Net = require(Shared.Net)
local Paints = require(Shared.Paints)
local ServiceConfig = require(Shared.ServiceConfig)
local ServiceModels = require(Shared.ServiceModels)
local Strings = require(Shared.Strings)

local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local T = Kit.Theme

local Workshop = {}

--------------------------------------------------------------------------------
-- Spot states and how each step changes them
--------------------------------------------------------------------------------

type Look = { color: Color3, material: Enum.Material, transparency: number?, scale: number, thick: number }

local LOOK: { [string]: Look } = {
	dirt = { color = Color3.fromRGB(96, 72, 50), material = Enum.Material.Mud, scale = 1, thick = 0.08 },
	foam = { color = Color3.fromRGB(248, 250, 255), material = Enum.Material.Snow, scale = 1.3, thick = 0.24 },
	suds = { color = Color3.fromRGB(214, 236, 255), material = Enum.Material.Glass, transparency = 0.3, scale = 0.95, thick = 0.1 },
	drops = { color = Color3.fromRGB(150, 210, 255), material = Enum.Material.Glass, transparency = 0.25, scale = 0.55, thick = 0.08 },
	rust = { color = Color3.fromRGB(152, 80, 38), material = Enum.Material.CorrodedMetal, scale = 1, thick = 0.07 },
	primer = { color = Color3.fromRGB(180, 180, 174), material = Enum.Material.SmoothPlastic, scale = 1, thick = 0.05 },
	damage = { color = Color3.fromRGB(36, 36, 42), material = Enum.Material.Slate, scale = 0.9, thick = 0.06 },
	wheel = { color = Color3.fromRGB(255, 210, 60), material = Enum.Material.Neon, transparency = 0.55, scale = 1, thick = 0.04 },
}

local STEP_FLOW: { [string]: { from: string?, to: string? } } = {
	foam = { from = "dirt", to = "foam" },
	scrub = { from = "foam", to = "suds" },
	rinse = { from = "suds", to = "drops" },
	dry = { from = "drops", to = "done" },
	sand = { from = "rust", to = "primer" },
	wrench = { from = "damage", to = "done" },
	pump = { from = "wheel", to = "done" },
	spray = {},
}

local DAMAGE_COUNT = { tiny = 3, small = 4, car = 6, big = 8 }

export type Spot = {
	part: BasePart,
	offset: CFrame, -- spot frame in part space, X axis = surface normal
	size: number,
	state: string,
	value: number, -- work left in the current step (1 = untouched)
	visual: BasePart?,
	gui: BillboardGui?,
	label: TextLabel?,
}

type PaintUnit = { part: BasePart, area: number, progress: number, from: Color3, to: Color3 }

--------------------------------------------------------------------------------
-- Spot placement (pure, testable): rays from the bounding box towards the body
--------------------------------------------------------------------------------

export type RayFn = (origin: Vector3, direction: Vector3) -> (Vector3?, Vector3?, BasePart?)

-- Local bounding box of `parts` in the frame `rootCf`.
function Workshop.localBounds(parts: { BasePart }, rootCf: CFrame): (Vector3, Vector3)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, part in parts do
		local h = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = rootCf:PointToObjectSpace(part.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					minV = minV:Min(corner)
					maxV = maxV:Max(corner)
				end
			end
		end
	end
	return minV, maxV
end

-- Places up to `count` spots on the visible surface, at least `minDist` apart.
function Workshop.placeSpots(parts: { BasePart }, rootCf: CFrame, count: number, minDist: number, cast: RayFn, rng: Random): { { pos: Vector3, normal: Vector3, part: BasePart } }
	local out = {}
	if #parts == 0 or count <= 0 then
		return out
	end
	local lo, hi = Workshop.localBounds(parts, rootCf)
	local size = hi - lo
	-- faces of the box weighted by area: top, left, right, front, back
	local faces = {
		{ w = size.X * size.Z * 1.3, axis = "top" },
		{ w = size.Y * size.Z, axis = "left" },
		{ w = size.Y * size.Z, axis = "right" },
		{ w = size.X * size.Y * 0.6, axis = "front" },
		{ w = size.X * size.Y * 0.6, axis = "back" },
	}
	local total = 0
	for _, f in faces do
		total += f.w
	end
	local margin = 2
	for _ = 1, count * 14 do
		if #out >= count then
			break
		end
		local roll = rng:NextNumber() * total
		local face = faces[#faces]
		for _, f in faces do
			roll -= f.w
			if roll <= 0 then
				face = f
				break
			end
		end
		local u, v = rng:NextNumber(), rng:NextNumber()
		local origin, dir
		if face.axis == "top" then
			origin = Vector3.new(lo.X + u * size.X, hi.Y + margin, lo.Z + v * size.Z)
			dir = Vector3.new(0, -(size.Y + margin * 2), 0)
		elseif face.axis == "left" or face.axis == "right" then
			local s = if face.axis == "left" then -1 else 1
			origin = Vector3.new(if s < 0 then lo.X - margin else hi.X + margin, lo.Y + (0.15 + u * 0.85) * size.Y, lo.Z + v * size.Z)
			dir = Vector3.new(-s * (size.X + margin * 2), 0, 0)
		else
			local s = if face.axis == "front" then -1 else 1
			origin = Vector3.new(lo.X + u * size.X, lo.Y + (0.15 + v * 0.85) * size.Y, if s < 0 then lo.Z - margin else hi.Z + margin)
			dir = Vector3.new(0, 0, -s * (size.Z + margin * 2))
		end
		local pos, normal, part = cast(rootCf * origin, rootCf:VectorToWorldSpace(dir))
		if pos and normal and part then
			local ok = true
			for _, s in out do
				if (s.pos - pos).Magnitude < minDist then
					ok = false
					break
				end
			end
			if ok then
				table.insert(out, { pos = pos, normal = normal, part = part })
			end
		end
	end
	return out
end

-- Ray against the part boxes (fallback when the engine raycast is unavailable).
function Workshop.boxCast(parts: { BasePart }): RayFn
	return function(origin: Vector3, direction: Vector3)
		local bestT, bestPart, bestNormal = math.huge, nil, nil
		for _, part in parts do
			local o = part.CFrame:PointToObjectSpace(origin)
			local d = part.CFrame:VectorToObjectSpace(direction)
			local h = part.Size / 2
			local tmin, tmax = -math.huge, math.huge
			local nAxis, nSign = 0, 0
			local hit = true
			for axis = 1, 3 do
				local oa = if axis == 1 then o.X elseif axis == 2 then o.Y else o.Z
				local da = if axis == 1 then d.X elseif axis == 2 then d.Y else d.Z
				local ha = if axis == 1 then h.X elseif axis == 2 then h.Y else h.Z
				if math.abs(da) < 1e-8 then
					if oa < -ha or oa > ha then
						hit = false
						break
					end
				else
					local t1, t2 = (-ha - oa) / da, (ha - oa) / da
					local sign = -1
					if t1 > t2 then
						t1, t2 = t2, t1
						sign = 1
					end
					if t1 > tmin then
						tmin = t1
						nAxis, nSign = axis, sign
					end
					tmax = math.min(tmax, t2)
					if tmin > tmax then
						hit = false
						break
					end
				end
			end
			if hit and tmin >= 0 and tmin <= 1 and tmin < bestT then
				bestT = tmin
				bestPart = part
				local n = if nAxis == 1 then Vector3.new(nSign, 0, 0) elseif nAxis == 2 then Vector3.new(0, nSign, 0) else Vector3.new(0, 0, nSign)
				bestNormal = part.CFrame:VectorToWorldSpace(n)
			end
		end
		if bestPart then
			return origin + direction * bestT, bestNormal, bestPart
		end
		return nil, nil, nil
	end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

type Session = {
	jobId: number,
	model: Model,
	root: BasePart,
	parts: { BasePart },
	partSet: { [BasePart]: boolean },
	queryBackup: { [BasePart]: boolean },
	size: ServiceConfig.Size,
	sizeId: string,
	steps: { string },
	step: number,
	target: Color3,
	spots: { Spot },
	paint: { PaintUnit },
	power: number,
	radius: number,
	params: RaycastParams,
	center: Vector3,
	extent: number,
	yaw: number,
	pitch: number,
	dist: number,
	yawGoal: number,
	pitchGoal: number,
	distGoal: number,
	busy: boolean,
	finished: boolean,
	progress: number,
	stepTotal: number,
	started: number, -- the step whose spots/tool are set up
	rng: Random,
	tool: Model?,
	emitter: ParticleEmitter?,
	walkSpeed: number?,
	jumpPower: number?,
	jumpHeight: number?,
	touchControls: boolean?,
	mouseIcon: boolean?,
	faded: { [BasePart]: boolean }, -- walls/roof between the camera and the vehicle
}

local session: Session? = nil
local entering = false
local brushing = false
local rotating = false
local touchInput: InputObject? = nil
local pointer: Vector2? = nil
local pointerIsTouch = false
local keys: { [Enum.KeyCode]: boolean } = {}

-- UI
local gui: ScreenGui
local topBar: Frame
local titleLabel: TextLabel
local chips: Frame
local card: Frame
local cardIcon: TextLabel
local cardIconBack: Frame
local cardTitle: TextLabel
local cardHint: TextLabel
local barFill: Frame
local percent: TextLabel
local ring: Frame
local ringStroke: UIStroke
local cheer: TextLabel
local controlsHint: TextLabel

--------------------------------------------------------------------------------
-- Visuals
--------------------------------------------------------------------------------

local function spotWorld(s: Spot): CFrame
	return s.part.CFrame * s.offset
end

local function styleSpot(s: Spot, pop: boolean)
	local look = LOOK[s.state]
	if not look then
		return
	end
	local v = s.visual
	if not v then
		local p = Instance.new("Part")
		p.Name = "Spot"
		p.Shape = Enum.PartType.Cylinder
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = Workspace.CurrentCamera
		s.visual = p
		v = p
	end
	local part = v :: BasePart
	local d = s.size * look.scale
	part.Size = Vector3.new(look.thick, d, d)
	part.Color = look.color
	part.Material = look.material
	part.Transparency = look.transparency or 0
	part.CFrame = spotWorld(s) * CFrame.new(look.thick / 2, 0, 0)
	if pop then
		local small = Vector3.new(look.thick, d * 0.4, d * 0.4)
		part.Size = small
		Kit.tween(part, 0.18, { Size = Vector3.new(look.thick, d, d) }, Enum.EasingStyle.Back)
	end
end

local function markerGui(s: Spot, text: string, color: Color3)
	local g = s.gui
	if not g then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(64, 40)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 0.6, 0)
		local label = Kit.label({ Size = UDim2.fromScale(1, 1), Text = text, TextScaled = true, Font = T.FontBlack, TextStrokeTransparency = 0.2 })
		label.Parent = billboard
		billboard.Adornee = s.visual
		billboard.Parent = gui
		s.gui = billboard
		s.label = label
		g = billboard
	end
	local label = s.label :: TextLabel
	label.Text = text
	label.TextColor3 = color
end

local function removeSpot(s: Spot, sparkle: boolean)
	local v = s.visual
	s.visual = nil
	if s.gui then
		local g = s.gui
		s.gui = nil
		if s.label then
			s.label.Text = "✅"
		end
		task.delay(0.5, function()
			g:Destroy()
		end)
	end
	if v then
		if sparkle then
			v.Material = Enum.Material.Neon
			v.Color = Color3.fromRGB(255, 255, 255)
			Kit.tween(v, 0.3, { Size = v.Size * Vector3.new(1, 1.6, 1.6), Transparency = 1 })
			task.delay(0.32, function()
				v:Destroy()
			end)
		else
			v:Destroy()
		end
	end
end

local function clearSpots(sess: Session)
	for _, s in sess.spots do
		removeSpot(s, false)
	end
	table.clear(sess.spots)
end

local function makeSpot(sess: Session, pos: Vector3, normal: Vector3, part: BasePart, size: number, state: string): Spot
	local frame = ServiceModels.alongX(pos, pos + normal)
	frame = CFrame.fromMatrix(pos, frame.XVector, frame.YVector, frame.ZVector)
	local s: Spot = {
		part = part,
		offset = part.CFrame:ToObjectSpace(frame),
		size = size,
		state = state,
		value = 1,
	}
	styleSpot(s, false)
	table.insert(sess.spots, s)
	return s
end

local function engineCast(sess: Session): Workshop.RayFn
	return function(origin, direction)
		local hit = Workspace:Raycast(origin, direction, sess.params)
		if hit and sess.partSet[hit.Instance :: BasePart] then
			return hit.Position, hit.Normal, hit.Instance :: BasePart
		end
		return nil, nil, nil
	end
end

-- The engine raycast sees the exact shapes; the box fallback keeps the game
-- playable where raycasts against the vehicle don't work (and in tests).
local function castFor(sess: Session): Workshop.RayFn
	local biggest: BasePart? = nil
	for _, part in sess.parts do
		if not biggest or part.Size.Magnitude > biggest.Size.Magnitude then
			biggest = part
		end
	end
	if biggest then
		local target = biggest.Position
		local origin = target + Vector3.new(0, biggest.Size.Magnitude + 10, 0)
		local pos = engineCast(sess)(origin, target - origin)
		if pos then
			return engineCast(sess)
		end
	end
	return Workshop.boxCast(sess.parts)
end

local function generateSpots(sess: Session, state: string)
	clearSpots(sess)
	local size = sess.size
	if state == "wheel" then
		for _, part in sess.parts do
			local radius = part:GetAttribute("Radius")
			if part:GetAttribute("Wheel") and typeof(radius) == "number" then
				local width = part:GetAttribute("Width") or 0.4
				local localPos = sess.root.CFrame:PointToObjectSpace(part.Position)
				local side = if localPos.X < -0.2 then -1 else 1
				local normal = sess.root.CFrame.RightVector * side
				local pos = part.Position + normal * (width / 2 + 0.06)
				local s = makeSpot(sess, pos, normal, part, radius * 1.8, "wheel")
				markerGui(s, "💨 0%", T.Warn)
			end
		end
		return
	end
	local count = if state == "damage" then DAMAGE_COUNT[sess.sizeId] or 4 else size.spots
	local minDist = if state == "damage" then size.spotSize * 3 else size.spotSize * 1.05
	local placed = Workshop.placeSpots(sess.parts, sess.root.CFrame, count, minDist, castFor(sess), sess.rng)
	for _, p in placed do
		local d = size.spotSize * sess.rng:NextNumber(0.8, 1.25)
		if state == "damage" then
			d = size.spotSize * 1.3
		end
		local s = makeSpot(sess, p.pos, p.normal, p.part, d, state)
		if state == "damage" then
			markerGui(s, "⚠", T.Bad)
		end
	end
end

local function buildPaintUnits(sess: Session)
	table.clear(sess.paint)
	for _, part in sess.parts do
		if part:GetAttribute("Role") == "Paint" then
			local s = part.Size
			table.insert(sess.paint, {
				part = part,
				area = 2 * (s.X * s.Y + s.Y * s.Z + s.X * s.Z),
				progress = 0,
				from = part.Color,
				to = sess.target,
			})
		end
	end
end

--------------------------------------------------------------------------------
-- Tools (3D model that follows the cursor + particles)
--------------------------------------------------------------------------------

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function toolPart(model: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- Tools are built pointing at -Z (the tip touches the surface at the origin).
local function buildTool(stepId: string, target: Color3): (Model, Attachment)
	local model = Instance.new("Model")
	model.Name = "WorkshopTool"
	local cyl = Enum.PartType.Cylinder
	local along = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis along Z
	local tip: BasePart
	if stepId == "foam" then
		tip = toolPart(model, Vector3.new(0.9, 0.22, 0.22), CFrame.new(0, 0, 0.45) * along, Color3.fromRGB(40, 40, 46), nil, cyl)
		toolPart(model, Vector3.new(1.1, 0.5, 0.5), CFrame.new(0, 0, 1.3) * along, Color3.fromRGB(255, 205, 40), nil, cyl)
		toolPart(model, Vector3.new(0.9, 0.75, 0.75), CFrame.new(0, -0.55, 1.4) * along, Color3.fromRGB(70, 160, 255), Enum.Material.Glass, cyl)
		toolPart(model, Vector3.new(0.25, 0.7, 0.3), CFrame.new(0, -0.45, 1.85), Color3.fromRGB(30, 30, 34))
	elseif stepId == "scrub" then
		tip = toolPart(model, Vector3.new(1.2, 0.8, 0.5), CFrame.new(0, 0, 0.3), Color3.fromRGB(255, 214, 50), Enum.Material.Sand)
		toolPart(model, Vector3.new(1.22, 0.82, 0.14), CFrame.new(0, 0, 0.02), Color3.fromRGB(60, 170, 80), Enum.Material.Fabric)
	elseif stepId == "rinse" then
		tip = toolPart(model, Vector3.new(0.9, 0.2, 0.2), CFrame.new(0, 0, 0.45) * along, Color3.fromRGB(200, 205, 214), Enum.Material.Metal, cyl)
		toolPart(model, Vector3.new(0.7, 0.35, 0.35), CFrame.new(0, 0, 1.1) * along, Color3.fromRGB(40, 120, 230), nil, cyl)
		toolPart(model, Vector3.new(0.25, 0.8, 0.35), CFrame.new(0, -0.45, 1.35), Color3.fromRGB(30, 30, 34))
		toolPart(model, Vector3.new(1.6, 0.18, 0.18), CFrame.new(0, -0.9, 2.0) * along, Color3.fromRGB(240, 200, 40), nil, cyl)
	elseif stepId == "dry" then
		tip = toolPart(model, Vector3.new(1.4, 1.0, 0.16), CFrame.new(0, 0, 0.08), Color3.fromRGB(110, 220, 170), Enum.Material.Fabric)
		toolPart(model, Vector3.new(1.4, 0.5, 0.16), CFrame.new(0, -0.62, 0.2) * CFrame.Angles(math.rad(-30), 0, 0), Color3.fromRGB(90, 200, 150), Enum.Material.Fabric)
	elseif stepId == "wrench" then
		tip = toolPart(model, Vector3.new(0.5, 0.18, 0.5), CFrame.new(0, 0, 0.25), Color3.fromRGB(205, 210, 220), Enum.Material.Metal)
		toolPart(model, Vector3.new(0.18, 1.6, 0.14), CFrame.new(0, 0.9, 0.3), Color3.fromRGB(205, 210, 220), Enum.Material.Metal)
		toolPart(model, Vector3.new(0.24, 0.6, 0.2), CFrame.new(0, 1.55, 0.3), Color3.fromRGB(220, 60, 50))
	elseif stepId == "pump" then
		tip = toolPart(model, Vector3.new(0.6, 0.16, 0.16), CFrame.new(0, 0, 0.3) * along, Color3.fromRGB(200, 205, 214), Enum.Material.Metal, cyl)
		toolPart(model, Vector3.new(0.8, 0.4, 0.4), CFrame.new(0, 0, 0.9) * along, Color3.fromRGB(30, 30, 34), nil, cyl)
		toolPart(model, Vector3.new(0.12, 0.5, 0.5), CFrame.new(0.26, 0.2, 0.9), Color3.fromRGB(230, 60, 50), nil, cyl)
		toolPart(model, Vector3.new(1.5, 0.12, 0.12), CFrame.new(0, -0.3, 1.6) * along, Color3.fromRGB(30, 30, 34), nil, cyl)
	elseif stepId == "sand" then
		tip = toolPart(model, Vector3.new(1.1, 0.7, 0.12), CFrame.new(0, 0, 0.06), Color3.fromRGB(170, 160, 140), Enum.Material.Sand)
		toolPart(model, Vector3.new(1.0, 0.6, 0.45), CFrame.new(0, 0, 0.35), Color3.fromRGB(255, 130, 40))
		toolPart(model, Vector3.new(0.7, 0.2, 0.3), CFrame.new(0, 0, 0.7), Color3.fromRGB(30, 30, 34))
	else -- spray
		tip = toolPart(model, Vector3.new(0.6, 0.16, 0.16), CFrame.new(0, 0, 0.3) * along, Color3.fromRGB(200, 205, 214), Enum.Material.Metal, cyl)
		toolPart(model, Vector3.new(0.8, 0.45, 0.45), CFrame.new(0, 0, 0.9) * along, Color3.fromRGB(200, 205, 214), Enum.Material.Metal, cyl)
		toolPart(model, Vector3.new(0.6, 0.55, 0.55), CFrame.new(0, 0.5, 0.8), target, nil, cyl).CFrame = CFrame.new(0, 0.55, 0.85) * CFrame.Angles(0, 0, math.pi / 2)
		toolPart(model, Vector3.new(0.22, 0.8, 0.3), CFrame.new(0, -0.5, 1.15), Color3.fromRGB(30, 30, 34))
	end
	tip.Name = "Tip"
	model.WorldPivot = CFrame.new() -- the tip touches the surface at the origin
	local attachment = Instance.new("Attachment")
	attachment.CFrame = CFrame.new(0, 0, -0.1) * CFrame.Angles(-math.pi / 2, 0, 0) -- particles shoot along -Z
	attachment.Parent = tip
	return model, attachment
end

local function buildEmitter(stepId: string, target: Color3, attachment: Attachment): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightInfluence = 0
	e.Rate = 60
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Speed = NumberRange.new(6, 10)
	e.SpreadAngle = Vector2.new(14, 14)
	e.Texture = SPARKLE
	e.Size = NumberSequence.new(0.3, 0.1)
	e.Transparency = NumberSequence.new(0.1, 1)
	if stepId == "foam" or stepId == "scrub" then
		e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		e.Texture = SMOKE
		e.Size = NumberSequence.new(0.5, 0.9)
		e.Speed = NumberRange.new(if stepId == "foam" then 8 else 1, if stepId == "foam" then 12 else 3)
		e.SpreadAngle = Vector2.new(25, 25)
	elseif stepId == "rinse" then
		e.Color = ColorSequence.new(Color3.fromRGB(120, 200, 255))
		e.Rate = 120
		e.Speed = NumberRange.new(14, 18)
		e.Size = NumberSequence.new(0.25, 0.15)
	elseif stepId == "dry" then
		e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 220))
		e.Rate = 25
		e.Speed = NumberRange.new(1, 3)
		e.SpreadAngle = Vector2.new(80, 80)
	elseif stepId == "wrench" then
		e.Color = ColorSequence.new(Color3.fromRGB(255, 190, 60))
		e.Rate = 40
		e.Speed = NumberRange.new(4, 9)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Lifetime = NumberRange.new(0.15, 0.3)
	elseif stepId == "pump" then
		e.Color = ColorSequence.new(Color3.fromRGB(230, 240, 255))
		e.Texture = SMOKE
		e.Rate = 30
		e.Size = NumberSequence.new(0.3, 0.8)
		e.Transparency = NumberSequence.new(0.5, 1)
	elseif stepId == "sand" then
		e.Color = ColorSequence.new(Color3.fromRGB(200, 180, 140))
		e.Texture = SMOKE
		e.Rate = 40
		e.Speed = NumberRange.new(1, 4)
		e.SpreadAngle = Vector2.new(90, 90)
		e.Size = NumberSequence.new(0.3, 0.9)
	else
		e.Color = ColorSequence.new(target)
		e.Texture = SMOKE
		e.Rate = 90
		e.Speed = NumberRange.new(9, 13)
		e.Size = NumberSequence.new(0.3, 1.2)
		e.Transparency = NumberSequence.new(0.2, 1)
	end
	e.Parent = attachment
	return e
end

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------

local function stepName(stepId: string): string
	return Strings.get("Step_" .. stepId)
end

local function vehicleName(job: any): string
	if job.source == "model" then
		local def = ServiceModels.get(job.vehicle)
		return if def then Strings.pick(def.name) else tostring(job.vehicle)
	end
	local def = CarCatalog.get(job.vehicle)
	return if def then def.name else tostring(job.vehicle)
end
Workshop.vehicleName = vehicleName

local function renderChips(sess: Session)
	for _, c in chips:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i, stepId in sess.steps do
		local def = ServiceConfig.Steps[stepId]
		local done = i < sess.step
		local current = i == sess.step
		local chip = Kit.new("Frame", {
			Size = UDim2.fromOffset(if current then 58 else 46, if current then 58 else 46),
			BackgroundColor3 = if done then T.Good elseif current then def.color else T.Card,
			BackgroundTransparency = if current or done then 0 else 0.2,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = chips,
		})
		Kit.corner(chip, 29)
		Kit.stroke(chip, Color3.new(1, 1, 1), if current then 3 else 1, if current then 0.1 else 0.7)
		Kit.label({ Size = UDim2.fromScale(1, 1), Text = if done then "✓" else def.icon, TextSize = if current then 30 else 22, Font = T.FontBlack, Parent = chip })
	end
end

local function renderCard(sess: Session)
	local stepId = sess.steps[sess.step]
	if not stepId then
		return
	end
	local def = ServiceConfig.Steps[stepId]
	cardIcon.Text = def.icon
	cardIconBack.BackgroundColor3 = def.color
	cardTitle.Text = string.format("%s %d/%d · %s", Strings.get("ServiceStep"), sess.step, #sess.steps, stepName(stepId))
	local touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	cardHint.Text = Strings.get("StepHint_" .. stepId) .. "\n" .. Strings.get(if touch then "ServiceHowTouch" else "ServiceHowMouse")
	barFill.BackgroundColor3 = def.color
	barFill.Size = UDim2.fromScale(0, 1)
	percent.Text = "0%"
	ringStroke.Color = def.color
	card.Position = UDim2.new(0.5, 0, 1, 40)
	Kit.tween(card, 0.3, { Position = UDim2.new(0.5, 0, 1, -24) }, Enum.EasingStyle.Back)
end

local function showCheer(text: string, color: Color3)
	cheer.Text = text
	cheer.TextColor3 = color
	cheer.Visible = true
	cheer.TextTransparency = 0
	cheer.TextStrokeTransparency = 0.3
	cheer.Size = UDim2.fromOffset(200, 50)
	Kit.tween(cheer, 0.25, { Size = UDim2.fromOffset(600, 110) }, Enum.EasingStyle.Back)
	task.delay(0.9, function()
		Kit.tween(cheer, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
end

local function buildHud()
	gui = Kit.screen("CarsWorkshop", 6)
	gui.Enabled = false

	topBar = Kit.panel({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(620, 112),
		Parent = gui,
	})
	titleLabel = Kit.label({
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		TextSize = 24,
		Font = T.FontBlack,
		Parent = topBar,
	})
	chips = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		Parent = topBar,
	})
	local chipLayout = Kit.list(chips, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	chipLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	card = Kit.panel({
		Name = "ToolCard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(600, 132),
		Parent = gui,
	})
	cardIconBack = Kit.new("Frame", {
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(100, 100),
		BackgroundColor3 = T.Accent,
		BorderSizePixel = 0,
		Parent = card,
	})
	Kit.corner(cardIconBack, 50)
	Kit.gradient(cardIconBack, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 180), 90)
	Kit.stroke(cardIconBack, Color3.new(1, 1, 1), 3, 0.3)
	cardIcon = Kit.label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 56, Parent = cardIconBack })
	cardTitle = Kit.label({
		Position = UDim2.fromOffset(134, 14),
		Size = UDim2.new(1, -150, 0, 32),
		Text = "",
		TextSize = 26,
		Font = T.FontBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	cardHint = Kit.label({
		Position = UDim2.fromOffset(134, 48),
		Size = UDim2.new(1, -150, 0, 36),
		Text = "",
		TextSize = 17,
		Font = T.FontMedium,
		TextColor3 = T.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	local barBack = Kit.new("Frame", {
		Position = UDim2.fromOffset(134, 94),
		Size = UDim2.new(1, -220, 0, 20),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = card,
	})
	Kit.corner(barBack, 10)
	barFill = Kit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Good, BorderSizePixel = 0, Parent = barBack })
	Kit.corner(barFill, 10)
	percent = Kit.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 88),
		Size = UDim2.fromOffset(70, 30),
		Text = "0%",
		TextSize = 24,
		Font = T.FontBlack,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})

	-- exit
	local exit = Kit.button({
		Name = "ExitWork",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(150, 56),
		Text = "✕  " .. Strings.get("ServiceExitWork"),
		BackgroundColor3 = Color3.fromRGB(60, 66, 86),
		onClick = function()
			Workshop.exit()
		end,
		Parent = gui,
	})
	Kit.stroke(exit, Color3.new(1, 1, 1), 2, 0.7)

	-- rotate buttons (also A/D, arrows or right mouse drag)
	local rotate = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(170, 110),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	for i, dir in { -1, 1 } do
		local b = Kit.bigButton({
			icon = if dir < 0 then "⟲" else "⟳",
			caption = "",
			color = Color3.fromRGB(70, 90, 140),
			size = 70,
			layoutOrder = i,
			parent = rotate,
		})
		b.root.Position = UDim2.fromOffset((i - 1) * 84, 0)
		local held = false
		b.button.MouseButton1Down:Connect(function()
			held = true
			task.spawn(function()
				while held and session do
					local sess = session :: Session
					sess.yawGoal += dir * 0.06
					task.wait()
				end
			end)
		end)
		b.button.MouseButton1Up:Connect(function()
			held = false
		end)
		b.button.MouseLeave:Connect(function()
			held = false
		end)
		b.button.Activated:Connect(function()
			if session then
				(session :: Session).yawGoal += dir * 0.35
			end
		end)
	end
	controlsHint = Kit.label({
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.fromOffset(260, 24),
		Text = Strings.get("ServiceRotateHint"),
		TextSize = 14,
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.6,
		Parent = rotate,
	})

	-- brush cursor
	ring = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(60, 60),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = gui,
	})
	Kit.corner(ring, 1000)
	ringStroke = Kit.stroke(ring, T.Accent, 3, 0.15)
	local dot = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = ring,
	})
	Kit.corner(dot, 3)

	cheer = Kit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(600, 110),
		Text = "",
		TextScaled = true,
		Font = T.FontBlack,
		TextStrokeTransparency = 0.3,
		Visible = false,
		ZIndex = 40,
		Parent = gui,
	})
end

--------------------------------------------------------------------------------
-- Steps
--------------------------------------------------------------------------------

local function jobFromState(id: number): any
	local s = ClientState.service
	if not s then
		return nil
	end
	for _, job in s.jobs do
		if job.id == id then
			return job
		end
	end
	return nil
end

local function setTool(sess: Session)
	if sess.tool then
		sess.tool:Destroy()
		sess.tool = nil
		sess.emitter = nil
	end
	local stepId = sess.steps[sess.step]
	if not stepId then
		return
	end
	local model, attachment = buildTool(stepId, sess.target)
	sess.emitter = buildEmitter(stepId, sess.target, attachment)
	model.Parent = Workspace.CurrentCamera
	sess.tool = model
end

local function startStep(sess: Session)
	local stepId = sess.steps[sess.step]
	if not stepId then
		return
	end
	sess.progress = 0
	sess.started = sess.step
	sess.busy = false
	local flow = STEP_FLOW[stepId]
	if stepId == "spray" then
		buildPaintUnits(sess)
	elseif flow.from then
		local have = 0
		for _, s in sess.spots do
			if s.state == flow.from then
				s.value = 1
				have += 1
			end
		end
		if have == 0 then
			generateSpots(sess, flow.from)
		end
		-- drop leftovers of the previous service
		for i = #sess.spots, 1, -1 do
			if sess.spots[i].state ~= flow.from then
				removeSpot(sess.spots[i], false)
				table.remove(sess.spots, i)
			end
		end
		sess.stepTotal = #sess.spots
	end
	setTool(sess)
	renderChips(sess)
	renderCard(sess)
end

local function computeProgress(sess: Session): number
	local stepId = sess.steps[sess.step]
	if stepId == "spray" then
		local total, done = 0, 0
		for _, u in sess.paint do
			total += u.area
			done += u.area * math.min(1, u.progress)
		end
		return if total > 0 then done / total else 1
	end
	local flow = STEP_FLOW[stepId]
	local left = 0
	for _, s in sess.spots do
		if s.state == flow.from then
			left += math.clamp(s.value, 0, 1)
		end
	end
	return if sess.stepTotal > 0 then 1 - left / sess.stepTotal else 1
end

local function advanceSpot(s: Spot, stepId: string)
	local flow = STEP_FLOW[stepId]
	if flow.to == "done" then
		s.state = "done"
		removeSpot(s, true)
	elseif flow.to then
		s.state = flow.to
		s.value = 1
		styleSpot(s, true)
	end
end

local finishStep: (sess: Session) -> ()

local function finishOrder(sess: Session)
	sess.finished = true
	showCheer("🎉 " .. Strings.get("ServiceAllDone"), T.Gold)
	task.delay(1.4, function()
		if session == sess then
			Workshop.exit(true)
		end
	end)
end

finishStep = function(sess: Session)
	if sess.busy or sess.finished then
		return
	end
	sess.busy = true
	local stepId = sess.steps[sess.step]
	-- complete what's left of this step
	if stepId == "spray" then
		for _, u in sess.paint do
			u.progress = 1
			u.part.Color = u.to
			u.part.Material = Enum.Material.SmoothPlastic
			u.part.Reflectance = 0.12
		end
		for i = #sess.spots, 1, -1 do
			removeSpot(sess.spots[i], true)
			table.remove(sess.spots, i)
		end
	else
		local flow = STEP_FLOW[stepId]
		for _, s in sess.spots do
			if s.state == flow.from then
				advanceSpot(s, stepId)
			end
		end
		for i = #sess.spots, 1, -1 do
			if sess.spots[i].state == "done" then
				table.remove(sess.spots, i)
			end
		end
	end
	if sess.emitter then
		sess.emitter.Enabled = false
	end
	barFill.Size = UDim2.fromScale(1, 1)
	percent.Text = "100%"
	showCheer("✓ " .. Strings.get("ServiceGreat"), T.Good)
	task.spawn(function()
		for _ = 1, 12 do
			if session ~= sess then
				return
			end
			local r = Net.request("ServiceStep", sess.jobId, sess.step)
			if r.ok then
				local args = r.args or {}
				sess.step = tonumber(args[1]) or (sess.step + 1)
				-- stay busy until the next step is set up (startStep clears it)
				if args[2] == true or sess.step > #sess.steps then
					sess.busy = false
					renderChips(sess)
					finishOrder(sess)
				else
					task.wait(0.5)
					if session == sess then
						startStep(sess)
					end
				end
				return
			elseif r.message == "ServiceTooFast" then
				task.wait(0.4)
			else
				if r.message then
					require(script.Parent.Notifications).notifyKey(r.message, r.args, "warning")
				end
				sess.busy = false
				Workshop.exit()
				return
			end
		end
		sess.busy = false
	end)
end

--------------------------------------------------------------------------------
-- Brushing
--------------------------------------------------------------------------------

local function pointerRay(camera: Camera): Ray?
	if not pointer then
		return nil
	end
	local p = pointer :: Vector2
	if pointerIsTouch then
		return camera:ScreenPointToRay(p.X, p.Y)
	end
	return camera:ViewportPointToRay(p.X, p.Y)
end

local function closestDistance(part: BasePart, pos: Vector3): number
	local o = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	local c = Vector3.new(math.clamp(o.X, -h.X, h.X), math.clamp(o.Y, -h.Y, h.Y), math.clamp(o.Z, -h.Z, h.Z))
	return (o - c).Magnitude
end

local function brush(sess: Session, pos: Vector3, dt: number)
	local stepId = sess.steps[sess.step]
	local def = ServiceConfig.Steps[stepId]
	local rate = dt * sess.power / def.work
	if stepId == "spray" then
		for _, u in sess.paint do
			if u.progress < 1 and closestDistance(u.part, pos) <= sess.radius then
				local scale = 0.6 + u.area / (sess.radius * sess.radius * 6)
				u.progress = math.min(1, u.progress + rate / scale)
				u.part.Color = u.from:Lerp(u.to, u.progress)
				if u.progress >= 1 then
					u.part.Material = Enum.Material.SmoothPlastic
					u.part.Reflectance = 0.12
				end
			end
		end
		for i = #sess.spots, 1, -1 do
			local s = sess.spots[i]
			if s.state == "primer" and (spotWorld(s).Position - pos).Magnitude <= sess.radius + s.size / 2 then
				removeSpot(s, true)
				table.remove(sess.spots, i)
			end
		end
		return
	end
	local flow = STEP_FLOW[stepId]
	for _, s in sess.spots do
		if s.state == flow.from and s.value > 0 then
			local reach = sess.radius + s.size / 2
			if (spotWorld(s).Position - pos).Magnitude <= reach then
				s.value -= rate
				local v = s.visual
				if s.state == "wheel" then
					markerGui(s, string.format("💨 %d%%", math.floor((1 - math.max(0, s.value)) * 100)), T.Warn)
				elseif v then
					local look = LOOK[s.state]
					local k = math.clamp(s.value, 0, 1)
					local d = s.size * look.scale * (0.55 + 0.45 * k)
					v.Size = Vector3.new(look.thick, d, d)
				end
				if s.value <= 0 then
					advanceSpot(s, stepId)
				end
			end
		end
	end
	for i = #sess.spots, 1, -1 do
		if sess.spots[i].state == "done" then
			table.remove(sess.spots, i)
		end
	end
end

-- Fades whatever stands between the camera and the vehicle (bay walls, the
-- roof, lift posts) so orbiting never hides the work.
local occluderParams = RaycastParams.new()
occluderParams.FilterType = Enum.RaycastFilterType.Exclude

local function fadeOccluders(sess: Session, camera: Camera)
	local hits: { [BasePart]: boolean } = {}
	local exclude: { Instance } = { sess.model, camera }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(exclude, character)
	end
	local from = camera.CFrame.Position
	for _ = 1, 6 do
		occluderParams.FilterDescendantsInstances = exclude
		local result = Workspace:Raycast(from, sess.center - from, occluderParams)
		if not result then
			break
		end
		local part = result.Instance
		if part:IsA("BasePart") then
			hits[part] = true
			table.insert(exclude, part)
		else
			break
		end
	end
	for part in hits do
		if not sess.faded[part] then
			sess.faded[part] = true
			part.LocalTransparencyModifier = 0.85
		end
	end
	for part in sess.faded do
		if not hits[part] then
			sess.faded[part] = nil
			part.LocalTransparencyModifier = 0
		end
	end
end

local function update(dt: number)
	local sess = session
	if not sess then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if not sess.model.Parent or not sess.root.Parent then
		Workshop.exit()
		return
	end
	-- camera orbit
	local turn = 0
	if keys[Enum.KeyCode.A] or keys[Enum.KeyCode.Left] then
		turn -= 1
	end
	if keys[Enum.KeyCode.D] or keys[Enum.KeyCode.Right] then
		turn += 1
	end
	sess.yawGoal += turn * dt * 1.8
	if keys[Enum.KeyCode.W] or keys[Enum.KeyCode.Up] then
		sess.pitchGoal = math.clamp(sess.pitchGoal + dt * 0.9, -0.1, 1.25)
	end
	if keys[Enum.KeyCode.S] or keys[Enum.KeyCode.Down] then
		sess.pitchGoal = math.clamp(sess.pitchGoal - dt * 0.9, -0.1, 1.25)
	end
	local k = 1 - math.exp(-dt * 10)
	sess.yaw += (sess.yawGoal - sess.yaw) * k
	sess.pitch += (sess.pitchGoal - sess.pitch) * k
	sess.dist += (sess.distGoal - sess.dist) * k
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(sess.center) * CFrame.Angles(0, sess.yaw, 0) * CFrame.Angles(-sess.pitch, 0, 0) * CFrame.new(0, 0, sess.dist)
	fadeOccluders(sess, camera)

	-- pointer
	if not pointerIsTouch then
		pointer = UserInputService:GetMouseLocation()
	end
	local ray = pointerRay(camera)
	local hitPos, hitNormal = nil, nil
	if ray then
		local result = Workspace:Raycast(ray.Origin, ray.Direction * (sess.dist * 3 + 60), sess.params)
		if result and sess.partSet[result.Instance :: BasePart] then
			hitPos, hitNormal = result.Position, result.Normal
		end
	end
	-- cursor ring sized to the brush
	if pointer and (not pointerIsTouch or brushing) then
		ring.Visible = true
		-- the gui ignores the top bar inset: mouse positions are already in its
		-- space, touch positions are measured below the inset
		local p = pointer :: Vector2
		if pointerIsTouch then
			p += GuiService:GetGuiInset()
		end
		local scale = gui:FindFirstChildOfClass("UIScale")
		local s = if scale then scale.Scale else 1
		ring.Position = UDim2.fromOffset(p.X / s, p.Y / s)
		local px = 50
		if hitPos then
			local a = camera:WorldToViewportPoint(hitPos)
			local b = camera:WorldToViewportPoint(hitPos + camera.CFrame.RightVector * sess.radius)
			px = math.clamp((Vector2.new(b.X, b.Y) - Vector2.new(a.X, a.Y)).Magnitude * 2, 24, 400)
		end
		ring.Size = UDim2.fromOffset(px / s, px / s)
		ringStroke.Transparency = if hitPos then 0.1 else 0.7
	else
		ring.Visible = false
	end
	-- tool follows the surface
	local tool = sess.tool
	if tool then
		if hitPos and hitNormal then
			local stepId = sess.steps[sess.step]
			local t = os.clock()
			local wobble = Vector3.zero
			if brushing and (stepId == "scrub" or stepId == "dry" or stepId == "sand") then
				local right = hitNormal:Cross(Vector3.yAxis)
				right = if right.Magnitude > 0.1 then right.Unit else Vector3.xAxis
				local up = right:Cross(hitNormal).Unit
				wobble = right * math.cos(t * 16) * sess.radius * 0.35 + up * math.sin(t * 16) * sess.radius * 0.25
			end
			local away = if brushing then 0.15 else 0.8
			local pos = hitPos + hitNormal * away + wobble
			local look = CFrame.lookAt(pos, pos - hitNormal)
			if stepId == "wrench" and brushing then
				look *= CFrame.Angles(0, 0, math.sin(t * 12) * 0.6)
			end
			tool:PivotTo(look)
			if sess.emitter then
				sess.emitter.Enabled = brushing and not sess.busy
			end
		else
			tool:PivotTo(CFrame.new(0, -1000, 0))
			if sess.emitter then
				sess.emitter.Enabled = false
			end
		end
	end
	-- work
	if brushing and hitPos and not sess.busy and not sess.finished then
		brush(sess, hitPos, dt)
		sess.progress = computeProgress(sess)
		barFill.Size = UDim2.fromScale(math.clamp(sess.progress, 0, 1), 1)
		percent.Text = string.format("%d%%", math.floor(sess.progress * 100))
		if sess.progress >= 0.96 then
			finishStep(sess)
		end
	end
end

--------------------------------------------------------------------------------
-- Enter / exit
--------------------------------------------------------------------------------

local function findModel(id: number): Model?
	for _, m in CollectionService:GetTagged("ServiceCustomer") do
		if m:IsA("Model") and m:GetAttribute("ServiceJob") == id then
			return m
		end
	end
	return nil
end

function Workshop.isActive(): boolean
	return session ~= nil
end

function Workshop.enter(id: number): boolean
	if session or entering then
		return false
	end
	local job = jobFromState(id)
	local model = findModel(id)
	if not job or not model or not model.PrimaryPart then
		return false
	end
	-- a double click or a second prompt press must not start a second session
	entering = true
	local r = Net.request("ServiceWork", id)
	entering = false
	if session or not model.Parent or not model.PrimaryPart then
		return false
	end
	if not r.ok then
		if r.message then
			require(script.Parent.Notifications).notifyKey(r.message, r.args, "warning")
		end
		return false
	end
	local root = model.PrimaryPart :: BasePart
	local parts: { BasePart } = {}
	local partSet: { [BasePart]: boolean } = {}
	local backup: { [BasePart]: boolean } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root and d.Transparency < 0.95 then
			table.insert(parts, d)
			partSet[d] = true
			backup[d] = d.CanQuery
			d.CanQuery = true
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local sizeId = job.size or "car"
	local size = ServiceConfig.Sizes[sizeId] or ServiceConfig.Sizes.car
	local profile = ClientState.profile
	local tools = if profile and profile.service then profile.service.upgrades.tools or 0 else 0
	local lo, hi = Workshop.localBounds(parts, root.CFrame)
	local center = root.CFrame * ((lo + hi) / 2)
	local extent = (hi - lo).Magnitude
	local _, ry = root.CFrame:ToOrientation()
	local yaw = ry + math.pi + math.rad(35)
	local step = tonumber(r.args and r.args[1]) or job.step or 1
	local sess: Session = {
		jobId = id,
		model = model,
		root = root,
		parts = parts,
		partSet = partSet,
		queryBackup = backup,
		size = size,
		sizeId = sizeId,
		steps = job.steps,
		step = step,
		target = Paints.getColor(job.target or job.paint),
		spots = {},
		paint = {},
		power = ServiceConfig.toolPower(tools),
		radius = size.brush * ServiceConfig.toolRadius(tools),
		params = params,
		center = center,
		extent = extent,
		yaw = yaw - 0.6,
		pitch = 0.5,
		dist = size.camera * 1.4,
		yawGoal = yaw,
		pitchGoal = 0.42,
		distGoal = math.max(size.camera, extent * 0.95),
		busy = false,
		finished = false,
		progress = 0,
		stepTotal = 0,
		started = 0,
		faded = {},
		rng = Random.new(id),
	}
	session = sess
	-- freeze the character and take over the camera
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		sess.walkSpeed = humanoid.WalkSpeed
		sess.jumpPower = humanoid.JumpPower
		sess.jumpHeight = humanoid.JumpHeight
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
	sess.touchControls = GuiService.TouchControlsEnabled
	GuiService.TouchControlsEnabled = false
	sess.mouseIcon = UserInputService.MouseIconEnabled
	UserInputService.MouseIconEnabled = false
	titleLabel.Text = string.format("%s  ·  %s", vehicleName(job), Strings.get("ServiceReward", "$" .. tostring(job.reward)))
	controlsHint.Visible = not UserInputService.TouchEnabled or UserInputService.MouseEnabled
	gui.Enabled = true
	ClientState.setWorking(id)
	startStep(sess)
	return true
end

function Workshop.exit(completed: boolean?)
	local sess = session
	if not sess then
		return
	end
	session = nil
	brushing = false
	rotating = false
	touchInput = nil
	clearSpots(sess)
	if sess.tool then
		sess.tool:Destroy()
	end
	for part, value in sess.queryBackup do
		if part.Parent then
			part.CanQuery = value
		end
	end
	for part in sess.faded do
		part.LocalTransparencyModifier = 0
	end
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- never "restore" a frozen character
		humanoid.WalkSpeed = if sess.walkSpeed and sess.walkSpeed > 0 then sess.walkSpeed else StarterPlayer.CharacterWalkSpeed
		humanoid.JumpPower = if sess.jumpPower and sess.jumpPower > 0 then sess.jumpPower else StarterPlayer.CharacterJumpPower
		humanoid.JumpHeight = if sess.jumpHeight and sess.jumpHeight > 0 then sess.jumpHeight else StarterPlayer.CharacterJumpHeight
	end
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	if sess.touchControls ~= nil then
		GuiService.TouchControlsEnabled = sess.touchControls
	end
	if sess.mouseIcon ~= nil then
		UserInputService.MouseIconEnabled = sess.mouseIcon
	end
	gui.Enabled = false
	cheer.Visible = false
	if not completed then
		task.spawn(Net.request, "ServiceLeave", sess.jobId)
	end
	ClientState.setWorking(nil)
end

-- Hooks for the client smoke test (no mouse or camera rays in the mock).
Workshop._test = {
	session = function()
		return session
	end,
	brushAt = function(pos: Vector3, dt: number)
		local sess = session
		if sess and not sess.busy and not sess.finished then
			brush(sess, pos, dt)
			sess.progress = computeProgress(sess)
			if sess.progress >= 0.96 then
				finishStep(sess)
			end
		end
	end,
	spotPosition = function(s: Spot): Vector3
		return spotWorld(s).Position
	end,
	startStep = function()
		if session then
			startStep(session)
		end
	end,
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Workshop.init()
	buildHud()
end

function Workshop.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not session or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			keys[input.KeyCode] = true
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
				Workshop.exit()
			end
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 then
			brushing = true
			pointerIsTouch = false
		elseif t == Enum.UserInputType.MouseButton2 then
			rotating = true
		elseif t == Enum.UserInputType.Touch and not touchInput then
			touchInput = input
			pointerIsTouch = true
			pointer = Vector2.new(input.Position.X, input.Position.Y)
			brushing = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		local sess = session
		if not sess then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement then
			pointerIsTouch = false
			if rotating then
				sess.yawGoal -= input.Delta.X * 0.008
				sess.pitchGoal = math.clamp(sess.pitchGoal + input.Delta.Y * 0.006, -0.1, 1.25)
			end
		elseif t == Enum.UserInputType.MouseWheel and not processed then
			sess.distGoal = math.clamp(sess.distGoal * (1 - input.Position.Z * 0.1), sess.size.camera * 0.45, sess.size.camera * 1.8)
		elseif t == Enum.UserInputType.Touch and input == touchInput then
			pointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		keys[input.KeyCode] = nil
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 then
			brushing = false
		elseif t == Enum.UserInputType.MouseButton2 then
			rotating = false
		elseif t == Enum.UserInputType.Touch and input == touchInput then
			touchInput = nil
			brushing = false
		end
	end)
	RunService.RenderStepped:Connect(update)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		Workshop.exit()
	end)
end

return Workshop
