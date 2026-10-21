-- Plaza: the spawn hub. Dealership showroom with rotating cars, spawn pads,
-- garage kiosks, race hub pads, leaderboards and the welcome sign.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Layout = require(Shared.WorldLayout)
local CarBuilder = require(Shared.CarBuilder)
local CarCatalog = require(Shared.CarCatalog)
local Tracks = require(Shared.Tracks)

local Plaza = {}

local TOP = Layout.RoadTop
local CONCRETE = Color3.fromRGB(176, 176, 172)
local DARK = Color3.fromRGB(32, 34, 42)
local ACCENT = Color3.fromRGB(255, 128, 32)

local SHOWCASE = { "nebula", "zephyr", "goliath", "apex" }

-- A board with a title and N rows for the Leaderboards system to fill in.
function Plaza.board(parent: Instance, cf: CFrame, width: number, height: number, titleKey: string, kind: string, rows: number, locArg: string?): BasePart
	local board = Build.box(parent, Vector3.new(width, height, 0.8), cf, DARK, Enum.Material.SmoothPlastic, "Leaderboard")
	board:SetAttribute("BoardKind", kind)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.16)
	title.BackgroundColor3 = ACCENT
	title.BorderSizePixel = 0
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = titleKey
	title:SetAttribute("LocKey", titleKey)
	if locArg then
		title:SetAttribute("LocTrack", locArg)
	end
	Build.tag(title, "LocText")
	title.Parent = gui
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.Size = UDim2.fromScale(0.94, 0.8)
	list.Position = UDim2.fromScale(0.03, 0.18)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.01, 0)
	layout.Parent = list
	for i = 1, rows do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.fromScale(1, 1 / rows - 0.012)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(40, 44, 56) else Color3.fromRGB(48, 52, 66)
		row.BorderSizePixel = 0
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1
			then Color3.fromRGB(255, 214, 80)
			elseif i == 2 then Color3.fromRGB(220, 224, 232)
			elseif i == 3 then Color3.fromRGB(230, 160, 100)
			else Color3.fromRGB(235, 235, 240)
		row.Text = if i == 1 then "BoardEmpty" else ""
		if i == 1 then
			row:SetAttribute("LocKey", "BoardEmpty")
			Build.tag(row, "LocText")
		end
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.03, 0)
		pad.PaddingTop = UDim.new(0.12, 0)
		pad.PaddingBottom = UDim.new(0.12, 0)
		pad.Parent = row
		row.Parent = list
	end
	gui.Parent = board
	Build.tag(board, "Leaderboard")
	return board
end

local function spawnPad(parent: Instance, cf: CFrame, index: number)
	local pad = Build.part(parent, {
		size = Vector3.new(24, 0.1, 30),
		cframe = cf * CFrame.new(0, 0.03, 0),
		color = Color3.fromRGB(60, 64, 76),
		material = Enum.Material.SmoothPlastic,
		collide = false,
		shadow = false,
		name = "SpawnPad",
	})
	for _, x in { -12, 12 } do
		Build.part(parent, {
			size = Vector3.new(0.5, 0.12, 30),
			cframe = cf * CFrame.new(x, 0.05, 0),
			color = ACCENT,
			material = Enum.Material.Neon,
			collide = false,
			shadow = false,
		})
	end
	local numberPlate = Build.part(parent, {
		size = Vector3.new(6, 0.12, 3),
		cframe = cf * CFrame.new(0, 0.06, 13),
		color = Color3.fromRGB(60, 64, 76),
		collide = false,
		shadow = false,
	})
	Build.text(numberPlate, Enum.NormalId.Top, tostring(index), { color = ACCENT })
	return pad
end

local function showroom(parent: Instance)
	local folder = Build.folder("Showroom", parent)
	local min, max = Layout.Showroom.min, Layout.Showroom.max
	local size = max - min
	local center = (min + max) / 2
	local h = 18
	-- floor
	Build.box(folder, Vector3.new(size.X, 0.4, size.Z), CFrame.new(center.X, TOP + 0.2, center.Z), Color3.fromRGB(230, 232, 236), Enum.Material.Marble)
	-- back wall + side walls (glass front)
	Build.box(folder, Vector3.new(size.X, h, 1), CFrame.new(center.X, TOP + h / 2, min.Z), Color3.fromRGB(40, 44, 58), Enum.Material.SmoothPlastic)
	for _, x in { min.X, max.X } do
		Build.box(folder, Vector3.new(1, h, size.Z), CFrame.new(x, TOP + h / 2, center.Z), Color3.fromRGB(40, 44, 58), Enum.Material.SmoothPlastic)
	end
	Build.part(folder, {
		size = Vector3.new(size.X, h - 2, 0.4),
		cframe = CFrame.new(center.X, TOP + (h - 2) / 2 + 2, max.Z),
		color = Color3.fromRGB(150, 190, 220),
		material = Enum.Material.Glass,
		transparency = 0.7,
		name = "ShowroomGlass",
	})
	Build.box(folder, Vector3.new(size.X, 2, 0.6), CFrame.new(center.X, TOP + 1, max.Z), Color3.fromRGB(40, 44, 58))
	-- roof with neon edge and sign
	Build.box(folder, Vector3.new(size.X + 4, 1.2, size.Z + 4), CFrame.new(center.X, TOP + h + 0.6, center.Z), Color3.fromRGB(30, 32, 40))
	Build.part(folder, {
		size = Vector3.new(size.X + 4.2, 0.4, 0.4),
		cframe = CFrame.new(center.X, TOP + h + 1.3, max.Z + 2),
		color = ACCENT,
		material = Enum.Material.Neon,
		collide = false,
	})
	local sign = Build.box(folder, Vector3.new(40, 6, 0.8), CFrame.new(center.X, TOP + h + 4.2, max.Z + 1.6), DARK)
	Build.text(sign, Enum.NormalId.Back, "GARAGE", { locKey = "SignGarage", color = ACCENT })

	-- turntables with showcase cars
	local slots = #SHOWCASE
	for i, id in SHOWCASE do
		local def = CarCatalog.get(id)
		if def then
			local x = min.X + size.X * (i - 0.5) / slots
			local z = center.Z + 2
			local base = Vector3.new(x, TOP + 0.4, z)
			Build.cylinder(folder, 0.6, 24, CFrame.new(base + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(40, 42, 50), Enum.Material.Metal)
			Build.cylinder(folder, 0.65, 24.4, CFrame.new(base + Vector3.new(0, 0.28, 0)) * CFrame.Angles(0, 0, math.pi / 2), ACCENT, Enum.Material.Neon).CanCollide = false
			local ok, model = pcall(CarBuilder.build, def, { showroom = true, ownerName = def.name })
			if ok and model then
				local chassis = model.PrimaryPart :: BasePart
				local rel = chassis.CFrame
				local pivot = CFrame.new(base + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, math.rad(35 + i * 50), 0)
				model:PivotTo(pivot * rel)
				model.Name = "Showcase_" .. id
				model:SetAttribute("SpinCenter", base)
				model:SetAttribute("SpinSpeed", 0.25)
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") then
						d.CanCollide = false
						d.CanQuery = false
					end
				end
				model.Parent = folder
				Build.tag(model, "Showcase")
				local label = Build.part(folder, {
					size = Vector3.new(14, 2.6, 0.3),
					cframe = CFrame.new(x, TOP + 1.6, max.Z - 0.6) * CFrame.Angles(math.rad(-15), 0, 0),
					color = DARK,
					collide = false,
				})
				Build.text(label, Enum.NormalId.Back, def.name, { color = Color3.new(1, 1, 1) })
			end
		end
	end
end

local function kiosk(parent: Instance, pos: Vector3)
	local base = Build.box(parent, Vector3.new(6, 7, 3), CFrame.new(pos.X, TOP + 3.5, pos.Z), DARK, Enum.Material.SmoothPlastic, "GarageKiosk")
	local screen = Build.part(parent, {
		size = Vector3.new(5, 3.2, 0.2),
		cframe = CFrame.new(pos.X, TOP + 4.6, pos.Z + 1.55),
		color = Color3.fromRGB(20, 24, 34),
		material = Enum.Material.SmoothPlastic,
		collide = false,
	})
	Build.text(screen, Enum.NormalId.Back, "GARAGE", { locKey = "SignGarage", color = ACCENT, background = Color3.fromRGB(20, 24, 34) })
	Build.part(parent, {
		size = Vector3.new(6.2, 0.3, 3.2),
		cframe = CFrame.new(pos.X, TOP + 7.1, pos.Z),
		color = ACCENT,
		material = Enum.Material.Neon,
		collide = false,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open garage"
	prompt.ObjectText = "Garage"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "OpenGarage")
	prompt:SetAttribute("LocAction", "PromptGarage")
	prompt:SetAttribute("LocObject", "Garage")
	prompt.Parent = base
end

-- Race hub: one pad per track with a sign, a prompt and a mini leaderboard.
local function raceHub(parent: Instance): { [string]: BasePart }
	local pads = {}
	for _, track in Tracks.List do
		local p = track.hub
		Build.part(parent, {
			size = Vector3.new(24, 0.1, 30),
			cframe = CFrame.new(p.X, TOP + 0.03, p.Z),
			color = Color3.fromRGB(46, 50, 64),
			collide = false,
			shadow = false,
			name = "RacePad_" .. track.id,
		})
		for _, x in { -12, 12 } do
			Build.part(parent, {
				size = Vector3.new(0.5, 0.12, 30),
				cframe = CFrame.new(p.X + x, TOP + 0.05, p.Z),
				color = Color3.fromRGB(80, 200, 255),
				material = Enum.Material.Neon,
				collide = false,
				shadow = false,
			})
		end
		-- sign at the back (north end) of the pad
		local signBase = CFrame.new(p.X, TOP, p.Z - 17)
		local board = Plaza.board(parent, signBase * CFrame.new(0, 11, 0) * CFrame.Angles(0, math.pi, 0), 22, 12, "BoardTrack", "track:" .. track.id, 5, track.id)
		board.Name = "TrackBoard_" .. track.id
		for _, x in { -10, 10 } do
			Build.pole(parent, (signBase * CFrame.new(x, 0, 0)).Position, 17, 0.8, Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
		end
		local trigger = Build.part(parent, {
			size = Vector3.new(8, 4, 8),
			cframe = CFrame.new(p.X, TOP + 2, p.Z),
			transparency = 1,
			collide = false,
			name = "RaceTrigger",
		})
		trigger.CanQuery = false
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RacePrompt"
		prompt.ActionText = "Start race"
		prompt.ObjectText = track.name.en
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 22
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("TrackId", track.id)
		prompt:SetAttribute("LocAction", "PromptRace")
		prompt:SetAttribute("LocTrack", track.id)
		prompt.Parent = trigger
		pads[track.id] = trigger
	end
	return pads
end

function Plaza.build(root: Instance)
	local folder = Build.folder("Plaza", root)
	local c = Layout.Plaza.center
	local s = Layout.Plaza.size
	Build.box(folder, Vector3.new(s.X, 1, s.Y), CFrame.new(c.X, TOP - 0.5, c.Z), CONCRETE, Enum.Material.Concrete, "PlazaFloor")
	-- curb around the plaza (gaps for the four exits)
	local curbColor = Color3.fromRGB(120, 120, 118)
	local hx, hz = s.X / 2, s.Y / 2
	for _, z in { -hz, hz } do
		for _, seg in { { -hx, -24 }, { 24, hx } } do
			Build.box(folder, Vector3.new(seg[2] - seg[1], 1.2, 2), CFrame.new((seg[1] + seg[2]) / 2, TOP + 0.6, z), curbColor, Enum.Material.Concrete)
		end
	end
	for _, x in { -hx, hx } do
		for _, seg in { { -hz, -22 }, { 22, hz } } do
			Build.box(folder, Vector3.new(2, 1.2, seg[2] - seg[1]), CFrame.new(x, TOP + 0.6, (seg[1] + seg[2]) / 2), curbColor, Enum.Material.Concrete)
		end
	end
	-- painted lanes
	for _, z in { -30, 52 } do
		Build.part(folder, {
			size = Vector3.new(s.X - 20, 0.06, 0.6),
			cframe = CFrame.new(0, TOP + 0.03, z),
			color = Color3.fromRGB(240, 240, 236),
			collide = false,
			shadow = false,
		})
	end

	local pads = Build.folder("SpawnPads", folder)
	for i, cf in Layout.SpawnPads do
		spawnPad(pads, cf, i)
	end

	-- player spawn with a neon ring
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 0.4, 14)
	spawn.CFrame = CFrame.new(Layout.PlayerSpawn.X, TOP + 0.2, Layout.PlayerSpawn.Z)
	spawn.Color = Color3.fromRGB(60, 64, 76)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = folder
	Build.cylinder(folder, 0.3, 16, CFrame.new(Layout.PlayerSpawn.X, TOP + 0.1, Layout.PlayerSpawn.Z) * CFrame.Angles(0, 0, math.pi / 2), ACCENT, Enum.Material.Neon).CanCollide = false

	-- entrance arch over the north exit with the game logo
	for _, x in { -28, 28 } do
		Build.box(folder, Vector3.new(4, 30, 4), CFrame.new(x, TOP + 15, -117), DARK, Enum.Material.SmoothPlastic, "ArchPillar")
		Build.part(folder, {
			size = Vector3.new(4.3, 30, 0.4),
			cframe = CFrame.new(x, TOP + 15, -114.9),
			color = ACCENT,
			material = Enum.Material.Neon,
			collide = false,
		})
	end
	local arch = Build.box(folder, Vector3.new(62, 9, 3), CFrame.new(0, TOP + 25, -117), Color3.fromRGB(28, 30, 44), Enum.Material.SmoothPlastic, "Arch")
	Build.text(arch, Enum.NormalId.Back, "CARS", { locKey = "SignWelcome", color = ACCENT })
	Build.text(arch, Enum.NormalId.Front, "CITY", { locKey = "SignCity", color = Color3.new(1, 1, 1) })

	-- controls help on the showroom's outer wall, facing the player spawn
	local controls = Build.box(
		folder,
		Vector3.new(34, 11, 0.6),
		CFrame.new(Layout.Showroom.max.X + 0.8, TOP + 9, (Layout.Showroom.min.Z + Layout.Showroom.max.Z) / 2) * CFrame.Angles(0, -math.pi / 2, 0),
		DARK,
		Enum.Material.SmoothPlastic,
		"ControlsBoard"
	)
	local title = Build.text(controls, Enum.NormalId.Front, "ControlsTitle", { locKey = "ControlsTitle", color = ACCENT })
	title.Size = UDim2.fromScale(1, 0.25)
	local label = Build.text(controls, Enum.NormalId.Front, "ControlsBody", { locKey = "ControlsBody", font = Enum.Font.GothamBold, color = Color3.fromRGB(235, 235, 240) })
	label.Size = UDim2.fromScale(1, 0.75)
	label.Position = UDim2.fromScale(0, 0.25)

	showroom(folder)
	for _, p in Layout.GarageKiosks do
		kiosk(folder, p)
	end
	local hubs = raceHub(Build.folder("RaceHub", folder))
	local hubSign = Build.sign(folder, CFrame.new(100, TOP, -112), 30, 6, "RACES", "SignRaces", Color3.fromRGB(20, 60, 90))
	hubSign.Name = "RaceHubSign"

	-- leaderboards on the east and west edges
	Plaza.board(folder, CFrame.new(-hx + 3, TOP + 12, 20) * CFrame.Angles(0, -math.pi / 2, 0), 34, 22, "BoardCash", "cash", 10).Name =
		"CashBoard"
	Plaza.board(folder, CFrame.new(hx - 3, TOP + 12, 20) * CFrame.Angles(0, math.pi / 2, 0), 34, 22, "BoardSpeed", "speed", 10).Name =
		"SpeedBoard"
	for _, x in { -hx + 3, hx - 3 } do
		for _, z in { 4, 36 } do
			Build.pole(folder, Vector3.new(x, TOP, z), 12, 1, Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
		end
	end

	return hubs
end

return Plaza
