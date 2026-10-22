-- ServicePlots: the car-service plots along the west street. Each plot has a
-- parking lot where customers wait, an order board, a glass office with the
-- business desk and a workshop with four bays (bays 2-4 start behind closed
-- roller doors until the owner buys them).
--
-- Plot space: +Z points at the street, x -100..100, z -85..85 (see
-- WorldLayout.ServicePlots). The Service system uses the exported constants
-- to route customers and staff.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Layout = require(Shared.WorldLayout)

local ServicePlots = {}

-- routing constants (plot space)
ServicePlots.SpotX = { -55, -33, -11, 11, 33, 55 }
ServicePlots.SpotZ = 40
ServicePlots.BayX = { -66, -22, 22, 66 }
ServicePlots.BayZ = -40
ServicePlots.LaneZ = 10
ServicePlots.AisleZ = 70
ServicePlots.EntryX = -78
ServicePlots.ExitX = 78
ServicePlots.RoadZ = 106 -- the lane of the street closest to the plot
ServicePlots.Front = 85

export type PlotData = {
	index: number,
	cf: CFrame,
	folder: Folder,
	spots: { CFrame },
	bays: { CFrame },
	doors: { [number]: BasePart },
	board: BasePart,
	boardRows: { TextLabel },
	desk: BasePart,
	sign: BasePart, -- entry arch, its labels show the owner's name
	reception: CFrame,
	idle: { CFrame },
}

local CONCRETE = Color3.fromRGB(150, 152, 156)
local LOT = Color3.fromRGB(70, 72, 78)
local WALL = Color3.fromRGB(232, 228, 220)
local WALL_DARK = Color3.fromRGB(52, 56, 66)
local TRIM = Color3.fromRGB(255, 128, 32)
local STEEL = Color3.fromRGB(120, 124, 132)
local WHITE = Color3.fromRGB(240, 240, 236)
local YELLOW = Color3.fromRGB(255, 200, 40)
local RED = Color3.fromRGB(200, 40, 40)
local BLUE = Color3.fromRGB(40, 110, 210)
local GLASS = Color3.fromRGB(150, 200, 230)

type Ctx = { folder: Instance, cf: CFrame }

local function at(ctx: Ctx, x: number, y: number, z: number): CFrame
	return ctx.cf * CFrame.new(x, y, z)
end

local function block(ctx: Ctx, size: Vector3, x: number, y: number, z: number, color: Color3, material: Enum.Material?, name: string?, collide: boolean?): BasePart
	return Build.part(ctx.folder, {
		size = size,
		cframe = at(ctx, x, y, z),
		color = color,
		material = material,
		name = name,
		collide = collide,
	})
end

local function flat(ctx: Ctx, w: number, d: number, x: number, z: number, color: Color3, name: string, y: number?)
	local part = Build.part(ctx.folder, {
		size = Vector3.new(w, 0.06, d),
		cframe = at(ctx, x, (y or 0) + 0.03, z),
		color = color,
		material = Enum.Material.SmoothPlastic,
		name = name,
		collide = false,
		shadow = false,
	})
	return part
end

local function vcyl(ctx: Ctx, height: number, d: number, x: number, y: number, z: number, color: Color3, material: Enum.Material?, collide: boolean?): BasePart
	local part = Build.cylinder(ctx.folder, height, d, at(ctx, x, y + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	part.CanCollide = collide ~= false
	return part
end

local function hcyl(ctx: Ctx, length: number, d: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Build.cylinder(ctx.folder, length, d, cf, color, material)
	part.CanCollide = false
	return part
end

--------------------------------------------------------------------------------
-- Props
--------------------------------------------------------------------------------

local function toolChest(ctx: Ctx, x: number, z: number, yaw: number)
	local base = at(ctx, x, 0, z) * CFrame.Angles(0, yaw, 0)
	Build.box(ctx.folder, Vector3.new(5, 4, 2.4), base * CFrame.new(0, 2, 0), RED, Enum.Material.SmoothPlastic, "ToolChest")
	for k = 0, 4 do
		local drawer = Build.part(ctx.folder, {
			size = Vector3.new(4.6, 0.6, 0.1),
			cframe = base * CFrame.new(0, 0.6 + k * 0.72, -1.22),
			color = Color3.fromRGB(170, 30, 30),
			collide = false,
		})
		drawer.Reflectance = 0.1
		Build.part(ctx.folder, { size = Vector3.new(2, 0.12, 0.12), cframe = base * CFrame.new(0, 0.6 + k * 0.72, -1.3), color = STEEL, material = Enum.Material.Metal, collide = false })
	end
	-- wrench and spray can on top
	Build.part(ctx.folder, { size = Vector3.new(1.6, 0.12, 0.3), cframe = base * CFrame.new(-1, 4.06, 0), color = STEEL, material = Enum.Material.Metal, collide = false })
	local can = vcyl(ctx, 0.9, 0.45, 0, 0, 0, Color3.fromRGB(60, 170, 90), nil, false)
	can.CFrame = base * CFrame.new(1.4, 4.45, 0) * CFrame.Angles(0, 0, math.pi / 2)
end

local function tireStack(ctx: Ctx, x: number, z: number, count: number)
	for k = 0, count - 1 do
		vcyl(ctx, 1.2, 4, x, k * 1.2, z, Color3.fromRGB(30, 30, 33))
		vcyl(ctx, 1.22, 2.2, x, k * 1.2, z, Color3.fromRGB(70, 72, 78), Enum.Material.Metal, false)
	end
end

local function pressureWasher(ctx: Ctx, x: number, z: number)
	Build.box(ctx.folder, Vector3.new(2.6, 2.2, 3.4), at(ctx, x, 1.5, z), YELLOW, Enum.Material.SmoothPlastic, "Washer")
	Build.part(ctx.folder, { size = Vector3.new(2.7, 0.3, 3.5), cframe = at(ctx, x, 2.7, z), color = Color3.fromRGB(40, 40, 44), collide = false })
	for _, side in { -1, 1 } do
		hcyl(ctx, 0.4, 1.2, at(ctx, x + side * 1.4, 0.6, z + 1.1), Color3.fromRGB(30, 30, 33))
	end
	-- hose reel on the wall side
	hcyl(ctx, 0.6, 2.4, at(ctx, x, 5.5, z + 1.5) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(30, 120, 220))
	hcyl(ctx, 0.62, 1.2, at(ctx, x, 5.5, z + 1.5) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(230, 230, 230))
end

local function oilDrum(ctx: Ctx, x: number, z: number, color: Color3)
	vcyl(ctx, 3.4, 2.4, x, 0, z, color, Enum.Material.Metal)
	for _, y in { 0.9, 2.5 } do
		vcyl(ctx, 0.15, 2.5, x, y, z, Color3.fromRGB(40, 40, 44), Enum.Material.Metal, false)
	end
end

local function compressor(ctx: Ctx, x: number, z: number)
	hcyl(ctx, 4, 2, at(ctx, x, 1.4, z) * CFrame.Angles(0, math.pi / 2, 0), RED, Enum.Material.SmoothPlastic).CanCollide = true
	Build.box(ctx.folder, Vector3.new(1.4, 1.2, 1.6), at(ctx, x, 3.0, z - 0.6), Color3.fromRGB(40, 40, 44))
	vcyl(ctx, 0.3, 0.5, x + 0.4, 3.6, z + 0.6, STEEL, Enum.Material.Metal, false)
end

local function workbench(ctx: Ctx, x: number, z: number, yaw: number)
	local base = at(ctx, x, 0, z) * CFrame.Angles(0, yaw, 0)
	Build.box(ctx.folder, Vector3.new(8, 0.4, 3), base * CFrame.new(0, 3.2, 0), Color3.fromRGB(150, 104, 60), Enum.Material.WoodPlanks, "Workbench")
	for _, sx in { -3.7, 3.7 } do
		Build.part(ctx.folder, { size = Vector3.new(0.4, 3, 2.6), cframe = base * CFrame.new(sx, 1.5, 0), color = STEEL, material = Enum.Material.Metal })
	end
	-- vise and a tool board behind
	Build.part(ctx.folder, { size = Vector3.new(0.8, 0.6, 0.8), cframe = base * CFrame.new(-2.8, 3.7, -0.6), color = BLUE, collide = false })
	Build.part(ctx.folder, { size = Vector3.new(8, 4, 0.2), cframe = base * CFrame.new(0, 6.5, 1.4), color = Color3.fromRGB(196, 170, 120), material = Enum.Material.Cardboard, collide = false })
	for k = 0, 4 do
		local tool = Build.part(ctx.folder, {
			size = Vector3.new(0.25, 1.6 - (k % 2) * 0.4, 0.1),
			cframe = base * CFrame.new(-3 + k * 1.5, 6.5, 1.25) * CFrame.Angles(0, 0, math.rad(15 - k * 7)),
			color = if k % 2 == 0 then STEEL else RED,
			material = Enum.Material.Metal,
			collide = false,
		})
		tool.Name = "Tool"
	end
end

local function paintShelf(ctx: Ctx, x: number, z: number, yaw: number)
	local base = at(ctx, x, 0, z) * CFrame.Angles(0, yaw, 0)
	for k = 0, 2 do
		Build.part(ctx.folder, { size = Vector3.new(6, 0.25, 1.8), cframe = base * CFrame.new(0, 1 + k * 2, 0), color = STEEL, material = Enum.Material.Metal })
		for c = 0, 3 do
			local color = Color3.fromHSV(((c + k * 4) * 0.13) % 1, 0.7, 0.9)
			local can = Build.cylinder(ctx.folder, 0.9, 0.7, base * CFrame.new(-2.2 + c * 1.45, 1.6 + k * 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color)
			can.CanCollide = false
		end
	end
	for _, sx in { -2.9, 2.9 } do
		Build.part(ctx.folder, { size = Vector3.new(0.25, 6, 1.8), cframe = base * CFrame.new(sx, 3, 0), color = STEEL, material = Enum.Material.Metal })
	end
end

local function cone(ctx: Ctx, x: number, z: number)
	Build.box(ctx.folder, Vector3.new(1.6, 0.25, 1.6), at(ctx, x, 0.12, z), Color3.fromRGB(30, 30, 33)).CanCollide = false
	local c = Build.part(ctx.folder, {
		size = Vector3.new(2, 1.0, 1.0),
		cframe = at(ctx, x, 1.1, z) * CFrame.Angles(0, 0, math.pi / 2),
		color = Color3.fromRGB(255, 110, 20),
		shape = Enum.PartType.Cylinder,
		collide = false,
	})
	c.Name = "ServiceCone"
	Build.part(ctx.folder, { size = Vector3.new(0.5, 1.05, 1.05), cframe = at(ctx, x, 1.2, z) * CFrame.Angles(0, 0, math.pi / 2), color = WHITE, shape = Enum.PartType.Cylinder, collide = false })
end

local function lampPost(ctx: Ctx, x: number, z: number, facing: Vector3)
	local base = (ctx.cf * CFrame.new(x, 0, z)).Position
	Build.pole(ctx.folder, base, 16, 0.6, Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
	local dir = ctx.cf:VectorToWorldSpace(facing)
	local headPos = base + Vector3.new(0, 16, 0) + dir * 2.5
	local head = Build.part(ctx.folder, {
		size = Vector3.new(1.4, 0.5, 3.2),
		cframe = CFrame.lookAt(headPos, headPos + dir),
		color = Color3.fromRGB(255, 236, 190),
		collide = false,
		shadow = false,
		name = "LampHead",
	})
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 120
	light.Range = 44
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Shadows = false
	light.Enabled = false
	light.Parent = head
	Build.tag(head, "StreetLight")
end

local function planter(ctx: Ctx, x: number, z: number, w: number, d: number)
	block(ctx, Vector3.new(w, 1.6, d), x, 0.8, z, WALL_DARK, Enum.Material.Concrete, "Planter")
	local hedge = block(ctx, Vector3.new(w - 0.6, 1.6, d - 0.6), x, 2.2, z, Color3.fromRGB(60, 130, 58), Enum.Material.Grass, "Hedge")
	hedge.CanCollide = false
	for k = 1, math.floor(w / 8) do
		local fx = x - w / 2 + k * 8 - 4
		Build.ball(ctx.folder, 1.4, (ctx.cf * CFrame.new(fx, 3.1, z)).Position, Color3.fromHSV((k * 0.17) % 1, 0.6, 1), Enum.Material.SmoothPlastic).CanCollide = false
	end
end

--------------------------------------------------------------------------------
-- Plot
--------------------------------------------------------------------------------

local function buildBay(ctx: Ctx, i: number, bx: number)
	-- epoxy floor, yellow lines and the lift
	flat(ctx, 40, 74, bx, -42, Color3.fromRGB(78, 92, 110), "BayFloor", 0.01)
	for _, side in { -1, 1 } do
		flat(ctx, 0.5, 74, bx + side * 19.5, -42, YELLOW, "Marking", 0.02)
		block(ctx, Vector3.new(1.6, 0.4, 30), bx + side * 4, 0.2, -42, YELLOW, Enum.Material.DiamondPlate, "Lift", false)
		block(ctx, Vector3.new(1.4, 12, 1.4), bx + side * 14, 6, -60, Color3.fromRGB(40, 110, 210), Enum.Material.Metal, "LiftPost")
	end
	block(ctx, Vector3.new(29.4, 1, 1.4), bx, 12.5, -60, Color3.fromRGB(40, 110, 210), Enum.Material.Metal, "LiftBeam", false)
	-- ceiling light
	local lamp = block(ctx, Vector3.new(16, 0.3, 2), bx, 21.2, -40, Color3.fromRGB(255, 252, 240), Enum.Material.Neon, "BayLight", false)
	local light = Instance.new("PointLight")
	light.Range = 40
	light.Brightness = 1.4
	light.Color = Color3.fromRGB(255, 246, 230)
	light.Shadows = false
	light.Parent = lamp
	-- props along the walls (vary per bay)
	local left, right = bx - 18, bx + 18
	toolChest(ctx, left + 1.5, -78, 0)
	if i % 2 == 1 then
		pressureWasher(ctx, right - 2, -76)
		tireStack(ctx, left + 1, -22, 3)
		workbench(ctx, right - 2, -50, -math.pi / 2)
	else
		compressor(ctx, right - 2, -76)
		oilDrum(ctx, left + 1.5, -24, Color3.fromRGB(40, 110, 210))
		oilDrum(ctx, left + 1.5, -28, Color3.fromRGB(200, 60, 40))
		paintShelf(ctx, right - 1.2, -50, -math.pi / 2)
	end
	-- bay number on the floor at the entrance
	local plate = flat(ctx, 7, 7, bx, -8, Color3.fromRGB(78, 92, 110), "BayNumber", 0.04)
	Build.text(plate, Enum.NormalId.Top, tostring(i), { color = YELLOW, pixelsPerStud = 20 })
	return lamp
end

function ServicePlots.build(root: Instance, index: number, cf: CFrame): PlotData
	local folder = Build.folder("ServicePlot" .. index, root)
	folder:SetAttribute("PlotIndex", index)
	local ctx: Ctx = { folder = folder, cf = cf }
	local W, D = Layout.ServicePlotSize.X, Layout.ServicePlotSize.Y

	-- ground: concrete lot with darker parking asphalt and driveway aprons to the street
	block(ctx, Vector3.new(W, 1, D), 0, -0.5, 0, CONCRETE, Enum.Material.Concrete, "Parking")
	flat(ctx, 160, 64, 0, 52, LOT, "Parking", 0.0)
	flat(ctx, 184, 26, 0, 8, LOT, "Parking", 0.0)
	for _, x in { ServicePlots.EntryX, ServicePlots.ExitX } do
		block(ctx, Vector3.new(26, 1, 10), x, -0.5, 90, LOT, Enum.Material.Asphalt, "Parking")
		flat(ctx, 24, 64, x, 52, LOT, "Parking", 0.0)
	end
	-- parking spot lines and arrows
	for k = 0, 6 do
		flat(ctx, 0.5, 36, -66 + k * 22, 40, WHITE, "Marking", 0.02)
	end
	flat(ctx, 132, 0.5, 0, 22, WHITE, "Marking", 0.02)
	for _, x in { ServicePlots.EntryX, ServicePlots.ExitX } do
		local dirSign = if x < 0 then -1 else 1
		flat(ctx, 0.8, 8, x, 72 + dirSign * 4, WHITE, "Marking", 0.02)
		for _, s in { -1, 1 } do
			local tip = Build.part(folder, {
				size = Vector3.new(0.8, 0.06, 4),
				cframe = at(ctx, x + s * 1.2, 0.03, 72 - dirSign * 1.2) * CFrame.Angles(0, s * dirSign * math.rad(35), 0),
				color = WHITE,
				collide = false,
				name = "Marking",
			})
			tip.CastShadow = false
		end
	end

	-- front fence: planters between and beside the gates, lamp posts
	planter(ctx, 0, 83.5, 128, 3)
	planter(ctx, -95.5, 83.5, 9, 3)
	planter(ctx, 95.5, 83.5, 9, 3)
	for _, x in { -96, 96 } do
		lampPost(ctx, x, 78, Vector3.new(-math.sign(x), 0, 0))
		lampPost(ctx, x, 10, Vector3.new(-math.sign(x), 0, 0))
	end
	-- entry arch with the owner's name
	for _, x in { -91.5, -64.5 } do
		block(ctx, Vector3.new(1.6, 16, 1.6), x, 8, 84, WALL_DARK, Enum.Material.Metal, "GatePost")
	end
	local arch = block(ctx, Vector3.new(30, 4.5, 1), ServicePlots.EntryX, 17.2, 84, WALL_DARK, Enum.Material.SmoothPlastic, "OwnerSign", false)
	Build.text(arch, Enum.NormalId.Back, "SERVICE", { locKey = "ServiceSignFree", color = WHITE })
	Build.text(arch, Enum.NormalId.Front, "SERVICE", { locKey = "ServiceSignFree", color = WHITE })
	block(ctx, Vector3.new(30.4, 0.4, 1.1), ServicePlots.EntryX, 19.6, 84, TRIM, Enum.Material.Neon, "SignTrim", false)
	for _, x in { 64.5, 91.5 } do
		block(ctx, Vector3.new(1.4, 6, 1.4), x, 3, 84, WALL_DARK, Enum.Material.Metal, "GatePost")
	end
	local exitSign = block(ctx, Vector3.new(10, 2.4, 0.5), 91.5, 7.2, 84, Color3.fromRGB(40, 140, 70), nil, "ExitSign", false)
	Build.text(exitSign, Enum.NormalId.Back, "EXIT", { locKey = "ServiceExit", color = WHITE })

	-- workshop building
	block(ctx, Vector3.new(186, 24, 2), 0, 12, -85, WALL, Enum.Material.Concrete, "Wall")
	for _, x in { -93, 93 } do
		block(ctx, Vector3.new(2, 24, 82), x, 12, -45, WALL, Enum.Material.Concrete, "Wall")
	end
	for _, x in { -44, 0, 44 } do
		block(ctx, Vector3.new(1, 18, 50), x, 9, -60, WALL, Enum.Material.Concrete, "Divider")
		block(ctx, Vector3.new(2.2, 18, 2.2), x, 9, -4.5, WALL_DARK, Enum.Material.Concrete, "Column")
	end
	block(ctx, Vector3.new(188, 1.2, 84), 0, 24.6, -44, WALL_DARK, Enum.Material.Concrete, "Roof")
	block(ctx, Vector3.new(188, 6, 2), 0, 21, -4, WALL_DARK, Enum.Material.SmoothPlastic, "Fascia", false)
	block(ctx, Vector3.new(188, 0.5, 2.2), 0, 18.2, -4, TRIM, Enum.Material.Neon, "FasciaTrim", false)
	-- rooftop sign
	local roofSign = block(ctx, Vector3.new(70, 9, 1.2), 0, 30.5, -6, Color3.fromRGB(24, 28, 40), nil, "RoofSign", false)
	Build.text(roofSign, Enum.NormalId.Back, "CAR SERVICE", { locKey = "ServiceRoofSign", color = Color3.fromRGB(255, 200, 80) })
	block(ctx, Vector3.new(70.6, 0.5, 1.4), 0, 35.2, -6, TRIM, Enum.Material.Neon, "SignTrim", false)
	for _, x in { -30, 30 } do
		block(ctx, Vector3.new(1, 6, 1), x, 27.5, -7, WALL_DARK, Enum.Material.Metal, "SignPost", false)
	end

	local bays, doors = {}, {}
	for i, bx in ServicePlots.BayX do
		buildBay(ctx, i, bx)
		table.insert(bays, at(ctx, bx, 0, ServicePlots.BayZ))
		if i > 1 then
			local door = block(ctx, Vector3.new(42, 17.6, 1), bx, 8.8, -3.5, Color3.fromRGB(176, 180, 188), Enum.Material.DiamondPlate, "BayDoor")
			door:SetAttribute("Bay", i)
			door:SetAttribute("ClosedCFrame", door.CFrame)
			doors[i] = door
		end
	end
	local spots = {}
	for _, sx in ServicePlots.SpotX do
		table.insert(spots, at(ctx, sx, 0, ServicePlots.SpotZ))
	end

	-- office: glass booth next to spot 1 with the order board and the business desk
	local ox, oz = -84, 39
	block(ctx, Vector3.new(28, 0.4, 34), ox, 0.2, oz, Color3.fromRGB(196, 190, 180), Enum.Material.WoodPlanks, "OfficeFloor", false)
	block(ctx, Vector3.new(1, 12, 34), -98, 6, oz, WALL, Enum.Material.Concrete, "Wall")
	block(ctx, Vector3.new(28, 12, 1), ox, 6, 56, WALL, Enum.Material.Concrete, "Wall")
	local glass = block(ctx, Vector3.new(0.4, 10, 34), -70.5, 5.2, oz, GLASS, Enum.Material.Glass, "OfficeGlass")
	glass.Transparency = 0.6
	-- south wall with a door gap (x -80..-72) and the order board on its outside
	block(ctx, Vector3.new(17, 12, 1), -89, 6, 22, WALL, Enum.Material.Concrete, "Wall")
	block(ctx, Vector3.new(1.5, 12, 1), -71, 6, 22, WALL, Enum.Material.Concrete, "Wall")
	block(ctx, Vector3.new(10, 2, 1), -76, 11, 22, WALL, Enum.Material.Concrete, "Wall")
	block(ctx, Vector3.new(30, 1, 36), ox, 12.5, oz, WALL_DARK, Enum.Material.Concrete, "OfficeRoof")
	block(ctx, Vector3.new(30.2, 0.6, 0.6), ox, 13.1, 21.2, TRIM, Enum.Material.Neon, "OfficeTrim", false)
	block(ctx, Vector3.new(0.6, 0.6, 36.2), -68.9, 13.1, oz, TRIM, Enum.Material.Neon, "OfficeTrim", false)

	local board = Build.box(folder, Vector3.new(15, 8.5, 0.5), at(ctx, -89, 5.6, 21.3), Color3.fromRGB(24, 28, 40), Enum.Material.SmoothPlastic, "OrderBoard")
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 28
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.18)
	title.BackgroundColor3 = TRIM
	title.BorderSizePixel = 0
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = WHITE
	title.Text = "ORDERS"
	title:SetAttribute("LocKey", "ServiceBoardTitle")
	Build.tag(title, "LocText")
	title.Parent = gui
	local rows = {}
	for r = 1, 6 do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. r
		row.Size = UDim2.fromScale(0.94, 0.12)
		row.Position = UDim2.fromScale(0.03, 0.2 + (r - 1) * 0.133)
		row.BackgroundColor3 = Color3.fromRGB(40, 46, 64)
		row.BackgroundTransparency = if r % 2 == 0 then 0.4 else 0.15
		row.BorderSizePixel = 0
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = WHITE
		row.Text = ""
		row.Parent = gui
		table.insert(rows, row)
	end
	gui.Parent = board
	block(ctx, Vector3.new(15.4, 0.4, 0.7), -89, 10.05, 21.4, TRIM, Enum.Material.Neon, "BoardTrim", false)

	-- desk with a computer, a chair, a sofa for the staff and a plant
	local desk = block(ctx, Vector3.new(8, 3, 3.5), -88, 1.9, 48, Color3.fromRGB(120, 84, 54), Enum.Material.WoodPlanks, "Desk")
	block(ctx, Vector3.new(3.4, 2.2, 0.3), -88, 4.6, 48.6, Color3.fromRGB(30, 30, 34), nil, "Monitor", false)
	local screen = Build.part(folder, { size = Vector3.new(3.1, 1.9, 0.05), cframe = at(ctx, -88, 4.6, 48.43), color = Color3.fromRGB(70, 200, 255), material = Enum.Material.Neon, collide = false, name = "Screen" })
	Build.text(screen, Enum.NormalId.Back, "$", { color = WHITE })
	block(ctx, Vector3.new(2.6, 2, 2.6), -88, 1.2, 44, Color3.fromRGB(30, 30, 34), nil, "Chair", false)
	block(ctx, Vector3.new(4, 1.6, 10), -95, 1.2, 33, Color3.fromRGB(60, 110, 170), Enum.Material.Fabric, "Sofa")
	block(ctx, Vector3.new(1.2, 3, 10), -96.6, 2.5, 33, Color3.fromRGB(60, 110, 170), Enum.Material.Fabric, "SofaBack", false)
	vcyl(ctx, 2, 2, -96, 0.4, 53.5, Color3.fromRGB(160, 100, 60), Enum.Material.Concrete, false)
	Build.ball(folder, 3.4, (cf * CFrame.new(-96, 4.2, 53.5)).Position, Color3.fromRGB(60, 140, 60), Enum.Material.Grass).CanCollide = false
	-- vending machine and bench outside the office
	block(ctx, Vector3.new(4, 8, 3), -68, 4, 18, Color3.fromRGB(200, 40, 50), nil, "Vending")
	Build.part(folder, { size = Vector3.new(2.6, 5, 0.1), cframe = at(ctx, -68, 4.6, 16.45), color = Color3.fromRGB(180, 230, 255), material = Enum.Material.Neon, collide = false })
	cone(ctx, 86, 22)
	cone(ctx, 86, 30)
	cone(ctx, 72, -1)

	local reception = at(ctx, -76, 3, 16) * CFrame.Angles(0, math.pi, 0)
	local idle = {
		at(ctx, -94, 0, 28) * CFrame.Angles(0, -math.pi / 2, 0),
		at(ctx, -94, 0, 33) * CFrame.Angles(0, -math.pi / 2, 0),
		at(ctx, -94, 0, 38) * CFrame.Angles(0, -math.pi / 2, 0),
		at(ctx, -82, 0, 30),
	}
	return {
		index = index,
		cf = cf,
		folder = folder,
		spots = spots,
		bays = bays,
		doors = doors,
		board = board,
		boardRows = rows,
		desk = desk,
		sign = arch,
		reception = reception,
		idle = idle,
	}
end

-- Builds every plot from the layout.
function ServicePlots.buildAll(root: Instance): { PlotData }
	local folder = Build.folder("Service", root)
	local plots = {}
	for i, cf in Layout.ServicePlots do
		table.insert(plots, ServicePlots.build(folder, i, cf))
	end
	return plots
end

-- Finds the plots again in a baked map (instances only, no rebuilding).
function ServicePlots.find(root: Instance): { PlotData }?
	local folder = root:FindFirstChild("Service")
	if not folder then
		return nil
	end
	local plots = {}
	for i, cf in Layout.ServicePlots do
		local f = folder:FindFirstChild("ServicePlot" .. i)
		if not f then
			return nil
		end
		local board = f:FindFirstChild("OrderBoard") :: BasePart
		local arch = f:FindFirstChild("OwnerSign") :: BasePart
		local doors = {}
		for _, d in f:GetChildren() do
			local bay = d:GetAttribute("Bay")
			if d:IsA("BasePart") and d.Name == "BayDoor" and typeof(bay) == "number" then
				doors[bay] = d
			end
		end
		local rows = {}
		local gui = board and board:FindFirstChild("BoardGui")
		for r = 1, 6 do
			local row = gui and gui:FindFirstChild("Row" .. r)
			if row then
				table.insert(rows, row :: TextLabel)
			end
		end
		local spots, bays = {}, {}
		for _, sx in ServicePlots.SpotX do
			table.insert(spots, cf * CFrame.new(sx, 0, ServicePlots.SpotZ))
		end
		for _, bx in ServicePlots.BayX do
			table.insert(bays, cf * CFrame.new(bx, 0, ServicePlots.BayZ))
		end
		table.insert(plots, {
			index = i,
			cf = cf,
			folder = f :: Folder,
			spots = spots,
			bays = bays,
			doors = doors,
			board = board,
			boardRows = rows,
			desk = f:FindFirstChild("Desk") :: BasePart,
			sign = arch,
			reception = cf * CFrame.new(-76, 3, 16) * CFrame.Angles(0, math.pi, 0),
			idle = {
				cf * CFrame.new(-94, 0, 28) * CFrame.Angles(0, -math.pi / 2, 0),
				cf * CFrame.new(-94, 0, 33) * CFrame.Angles(0, -math.pi / 2, 0),
				cf * CFrame.new(-94, 0, 38) * CFrame.Angles(0, -math.pi / 2, 0),
				cf * CFrame.new(-82, 0, 30),
			},
		})
	end
	return plots
end

return ServicePlots
