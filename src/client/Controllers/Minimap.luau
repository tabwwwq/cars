-- Minimap: a round map in the corner that turns with the camera. Shows roads,
-- the city, race tracks, areas, other cars and the next race checkpoint.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Layout = require(Shared.WorldLayout)
local Spline = require(Shared.Util.Spline)
local Tracks = require(Shared.Tracks)

local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local T = Kit.Theme

local Minimap = {}

local SIZE = 220
local SCALE = 0.13 -- pixels per stud
local HALF = Layout.Half

local root: CanvasGroup
local pivot: Frame
local map: Frame
local arrow: Frame
local target: Frame
local dots: { [Model]: Frame } = {}
local homeMarker: TextLabel

local function toMap(x: number, z: number): UDim2
	return UDim2.fromOffset((x + HALF) * SCALE, (z + HALF) * SCALE)
end

local function line(a: Vector3, b: Vector3, width: number, color: Color3, z: number?)
	local dx, dz = b.X - a.X, b.Z - a.Z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1 then
		return
	end
	Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = toMap((a.X + b.X) / 2, (a.Z + b.Z) / 2),
		Size = UDim2.fromOffset(len * SCALE + width * SCALE, math.max(width * SCALE, 2)),
		Rotation = math.deg(math.atan2(dz, dx)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z or 2,
		Parent = map,
	})
end

local function rect(center: Vector3, size: Vector2, color: Color3, transparency: number?)
	Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = toMap(center.X, center.Z),
		Size = UDim2.fromOffset(size.X * SCALE, size.Y * SCALE),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = map,
	})
end

local function drawWorld()
	local road = Color3.fromRGB(70, 74, 84)
	rect(Vector3.zero, Vector2.new(HALF * 2, HALF * 2), Color3.fromRGB(64, 110, 62))
	-- hills
	rect(Vector3.new(0, 0, (Layout.SouthHills.start + HALF) / 2), Vector2.new(HALF * 2, HALF - Layout.SouthHills.start), Color3.fromRGB(96, 128, 74))
	-- areas
	rect(Layout.Plaza.center, Layout.Plaza.size, Color3.fromRGB(170, 170, 166))
	rect(Layout.StuntPark.center, Layout.StuntPark.size, Color3.fromRGB(110, 80, 60))
	rect(Layout.DriftArena.center, Layout.DriftArena.size, Color3.fromRGB(120, 60, 110))
	rect(Vector3.new(0, 0, -975), Vector2.new(1400, 1050), Color3.fromRGB(120, 124, 134))
	-- roads
	for _, r in Layout.Roads do
		line(r.a, r.b, r.w, road)
	end
	for _, x in Layout.CityX do
		line(Vector3.new(x, 0, -450), Vector3.new(x, 0, -1500), 40, road)
	end
	for _, z in Layout.CityZ do
		line(Vector3.new(-700, 0, z), Vector3.new(700, 0, z), 40, road)
	end
	-- tracks
	for _, t in Tracks.List do
		if t.surface ~= "existing" then
			local samples = Spline.sample(t.points, t.kind == "circuit", 60)
			local color = if t.surface == "dirt" then Color3.fromRGB(150, 110, 70) else Color3.fromRGB(40, 42, 50)
			for i = 1, #samples - (if t.kind == "circuit" then 0 else 1) do
				local a = samples[i].pos
				local b = samples[(i % #samples) + 1].pos
				line(a, b, t.width, color, 3)
			end
		end
	end
	-- speed trap
	rect(Vector3.new(Layout.SpeedTrap.x, 0, Layout.SpeedTrap.z), Vector2.new(30, 80), Color3.fromRGB(230, 60, 60))
	-- car-service plots
	for _, cf in Layout.ServicePlots do
		rect(cf.Position, Layout.ServicePlotSize, Color3.fromRGB(150, 150, 156))
		rect(cf * Vector3.new(0, 0, -44), Vector2.new(186, 82), Color3.fromRGB(70, 74, 92))
	end
end

local function heading(look: Vector3): number
	return math.deg(math.atan2(look.X, -look.Z))
end

local function dotFor(model: Model): Frame
	local dot = dots[model]
	if not dot then
		dot = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = T.Accent2,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = map,
		})
		Kit.corner(dot, 4)
		dots[model] = dot
	end
	return dot
end

function Minimap.init()
	local gui = Kit.screen("CarsMinimap", 4)
	root = Kit.new("CanvasGroup", {
		Name = "Minimap",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 84),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = T.Bg,
		BorderSizePixel = 0,
		Parent = gui,
	})
	Kit.corner(root, SIZE / 2)
	pivot = Kit.new("Frame", {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Rotation = 0,
		Parent = root,
	})
	map = Kit.new("Frame", {
		Size = UDim2.fromOffset(HALF * 2 * SCALE, HALF * 2 * SCALE),
		BackgroundTransparency = 1,
		Parent = pivot,
	})
	drawWorld()
	target = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = T.Gold,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 7,
		Parent = map,
	})
	Kit.corner(target, 6)
	Kit.stroke(target, Color3.new(0, 0, 0), 2, 0.2)
	-- the own car-service plot
	homeMarker = Kit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Color3.fromRGB(40, 170, 160),
		BackgroundTransparency = 0,
		Text = "🔧",
		TextSize = 15,
		Visible = false,
		ZIndex = 8,
		Parent = map,
	})
	Kit.corner(homeMarker, 13)
	Kit.stroke(homeMarker, Color3.new(1, 1, 1), 2, 0.1)
	-- the player's arrow stays in the middle
	arrow = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		Rotation = 0,
		ZIndex = 10,
		Parent = root,
	})
	Kit.label({
		Size = UDim2.fromScale(1, 1),
		Text = "▲",
		TextSize = 18,
		TextColor3 = T.Accent,
		TextStrokeTransparency = 0.2,
		ZIndex = 10,
		Parent = arrow,
	})
	-- ring
	local ring = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = root,
	})
	Kit.corner(ring, SIZE / 2)
	Kit.stroke(ring, Color3.new(1, 1, 1), 3, 0.6)
	Kit.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(20, 16),
		Text = "N",
		TextSize = 13,
		TextColor3 = T.Muted,
		ZIndex = 12,
		Name = "North",
		Parent = root,
	})
end

function Minimap.start()
	local player = Players.LocalPlayer
	ClientState.ServiceChanged:Connect(function(s)
		local origin = s and s.origin
		if typeof(origin) == "CFrame" then
			homeMarker.Visible = true
			homeMarker.Position = toMap(origin.X, origin.Z)
		end
	end)
	CollectionService:GetInstanceRemovedSignal("Car"):Connect(function(model)
		local dot = dots[model :: Model]
		if dot then
			dot:Destroy()
			dots[model :: Model] = nil
		end
	end)
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local focus = ClientState.car
		local pos: Vector3? = nil
		local look: Vector3? = nil
		if ClientState.driving and focus and focus.PrimaryPart then
			pos = focus.PrimaryPart.Position
			look = focus.PrimaryPart.CFrame.LookVector
		elseif character and character.PrimaryPart then
			pos = character.PrimaryPart.Position
			look = character.PrimaryPart.CFrame.LookVector
		end
		if not pos or not look or not camera then
			return
		end
		local camHeading = heading(camera.CFrame.LookVector)
		pivot.Rotation = -camHeading
		map.Position = UDim2.fromOffset(-(pos.X + HALF) * SCALE, -(pos.Z + HALF) * SCALE)
		arrow.Rotation = heading(look) - camHeading
		local north = root:FindFirstChild("North") :: TextLabel?
		if north then
			local a = math.rad(-camHeading)
			local r = SIZE / 2 - 12
			north.Position = UDim2.new(0.5, math.sin(a) * r, 0.5, -math.cos(a) * r - 8)
		end

		-- other cars
		for _, model in CollectionService:GetTagged("Car") do
			if model:IsA("Model") and model ~= ClientState.car and model.PrimaryPart then
				local p = model.PrimaryPart.Position
				local dot = dotFor(model)
				dot.Position = toMap(p.X, p.Z)
			end
		end

		-- race target
		local t = ClientState.raceTarget
		if t then
			target.Visible = true
			target.Position = toMap(t.X, t.Z)
		else
			target.Visible = false
		end
	end)
end

return Minimap
