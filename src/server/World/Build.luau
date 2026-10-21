-- Build: small helpers for constructing the static world out of anchored parts.

local CollectionService = game:GetService("CollectionService")

local Build = {}

export type PartProps = {
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	name: string?,
	shape: Enum.PartType?,
	transparency: number?,
	collide: boolean?,
	shadow: boolean?,
	reflectance: number?,
	class: string?,
}

function Build.folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Build.part(parent: Instance, p: PartProps): BasePart
	local part = Instance.new(p.class or "Part") :: BasePart
	part.Name = p.name or "Part"
	part.Anchored = true
	part.Size = p.size
	part.CFrame = p.cframe
	part.Color = p.color or Color3.fromRGB(163, 162, 165)
	part.Material = p.material or Enum.Material.SmoothPlastic
	part.Transparency = p.transparency or 0
	part.Reflectance = p.reflectance or 0
	part.CanCollide = if p.collide == nil then true else p.collide
	part.CastShadow = if p.shadow == nil then true else p.shadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if p.shape and part:IsA("Part") then
		part.Shape = p.shape
	end
	if not part.CanCollide then
		part.CanTouch = false
		part.CanQuery = false
	end
	part.Parent = parent
	return part
end

function Build.box(parent: Instance, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?, name: string?): BasePart
	return Build.part(parent, { size = size, cframe = cf, color = color, material = material, name = name })
end

-- Wedge rising towards the local +Z of `cf`.
function Build.wedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?): BasePart
	return Build.part(parent, { size = size, cframe = cf, color = color, material = material, class = "WedgePart", name = "Ramp" })
end

-- Cylinder whose axis is the local X of `cf`.
function Build.cylinder(parent: Instance, length: number, diameter: number, cf: CFrame, color: Color3?, material: Enum.Material?): BasePart
	return Build.part(parent, {
		size = Vector3.new(length, diameter, diameter),
		cframe = cf,
		color = color,
		material = material,
		shape = Enum.PartType.Cylinder,
		name = "Cylinder",
	})
end

-- Vertical cylinder standing on `base` (bottom center).
function Build.pole(parent: Instance, base: Vector3, height: number, diameter: number, color: Color3?, material: Enum.Material?): BasePart
	return Build.cylinder(
		parent,
		height,
		diameter,
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material
	)
end

function Build.ball(parent: Instance, diameter: number, pos: Vector3, color: Color3?, material: Enum.Material?): BasePart
	return Build.part(parent, {
		size = Vector3.new(diameter, diameter, diameter),
		cframe = CFrame.new(pos),
		color = color,
		material = material,
		shape = Enum.PartType.Ball,
		name = "Ball",
	})
end

-- Flat box between two points on the ground plane, top surface at `topY`.
function Build.strip(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	width: number,
	thickness: number,
	topY: number,
	color: Color3?,
	material: Enum.Material?,
	extra: number?
): BasePart?
	local flatA = Vector3.new(a.X, 0, a.Z)
	local flatB = Vector3.new(b.X, 0, b.Z)
	local len = (flatB - flatA).Magnitude
	if len < 0.05 then
		return nil
	end
	local mid = (flatA + flatB) / 2
	local cf = CFrame.lookAt(Vector3.new(mid.X, topY - thickness / 2, mid.Z), Vector3.new(flatB.X, topY - thickness / 2, flatB.Z))
	return Build.part(parent, {
		size = Vector3.new(width, thickness, len + (extra or 0)),
		cframe = cf,
		color = color,
		material = material,
		name = "Strip",
	})
end

-- A SurfaceGui text panel. `locKey` makes the client translate it (see WorldText controller).
function Build.text(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	opts: {
		color: Color3?,
		background: Color3?,
		font: Enum.Font?,
		locKey: string?,
		locArg: string?,
		pixelsPerStud: number?,
		lightInfluence: number?,
	}?
): TextLabel
	local o = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.pixelsPerStud or 30
	gui.LightInfluence = o.lightInfluence or 0
	gui.MaxDistance = 600
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if o.background then 0 else 1
	label.BackgroundColor3 = o.background or Color3.new(0, 0, 0)
	label.BorderSizePixel = 0
	label.Text = text
	label.TextScaled = true
	label.Font = o.font or Enum.Font.GothamBlack
	label.TextColor3 = o.color or Color3.new(1, 1, 1)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = label
	label.Parent = gui
	if o.locKey then
		label:SetAttribute("LocKey", o.locKey)
		if o.locArg then
			label:SetAttribute("LocArg", o.locArg)
		end
		CollectionService:AddTag(label, "LocText")
	end
	gui.Parent = part
	return label
end

-- Billboard style sign on two posts. Returns the board part.
function Build.sign(parent: Instance, base: CFrame, width: number, height: number, text: string, locKey: string?, color: Color3?): BasePart
	local postH = height + 6
	for _, x in { -width / 2 + 1, width / 2 - 1 } do
		Build.pole(parent, (base * CFrame.new(x, 0, 0)).Position, postH, 0.8, Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
	end
	local board = Build.box(parent, Vector3.new(width, height, 0.6), base * CFrame.new(0, 6 + height / 2, 0), color or Color3.fromRGB(24, 28, 40))
	board.Name = "Sign"
	Build.text(board, Enum.NormalId.Front, text, { locKey = locKey, color = Color3.fromRGB(255, 255, 255) })
	Build.text(board, Enum.NormalId.Back, text, { locKey = locKey, color = Color3.fromRGB(255, 255, 255) })
	-- neon frame
	Build.part(parent, {
		size = Vector3.new(width + 0.4, 0.35, 0.7),
		cframe = base * CFrame.new(0, 6 + height + 0.17, 0),
		color = color and color:Lerp(Color3.new(1, 1, 1), 0.3) or Color3.fromRGB(255, 140, 40),
		material = Enum.Material.Neon,
		collide = false,
		shadow = false,
	})
	return board
end

function Build.tag(inst: Instance, tag: string)
	CollectionService:AddTag(inst, tag)
end

-- Deterministic random numbers so every server builds the same world.
function Build.rng(seed: number): Random
	return Random.new(seed)
end

return Build
