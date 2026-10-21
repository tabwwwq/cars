-- World: builds the map at server start (or uses one baked in Studio) and
-- exposes track data, spawn pads and bonus zones to the other systems.
--
-- Bake the map into the place (to look at or edit it in Studio):
--   require(game.ServerScriptService.CarsServer.Systems.World).bake()
-- in the Studio command bar, then save the place. The server will then skip
-- building and only compute the data.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Signal = require(Shared.Util.Signal)
local Spline = require(Shared.Util.Spline)
local Tracks = require(Shared.Tracks)

local WorldModules = script.Parent.Parent:WaitForChild("World")
local Build = require(WorldModules.Build)
local City = require(WorldModules.City)
local Decor = require(WorldModules.Decor)
local Layout = require(Shared.WorldLayout)
local Plaza = require(WorldModules.Plaza)
local Roads = require(WorldModules.Roads)
local Stunts = require(WorldModules.Stunts)
local TerrainGen = require(WorldModules.TerrainGen)
local TrackBuilder = require(WorldModules.TrackBuilder)

local World = {}

World.VERSION = 3
World.Layout = Layout
World.Ready = false
World.ReadySignal = Signal.new()
World.Tracks = {} :: { [string]: TrackBuilder.TrackData }
World.Root = nil :: Folder?

local function trailInfo()
	local def = Tracks.get("trail")
	if not def then
		return nil
	end
	local samples = Spline.sample(def.points, false, 6)
	return { samples = samples, width = def.width }
end

local function buildAll(): Folder
	local existing = workspace:FindFirstChild("CarsWorld")
	if existing then
		existing:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "CarsWorld"
	root.Parent = workspace

	local trail = trailInfo()
	local started = os.clock()
	local trailHeights = TerrainGen.generate(workspace.Terrain, trail)
	print(string.format("[World] terrain %.2fs", os.clock() - started))
	Roads.build(root)
	Plaza.build(root)
	local cityTrees = City.build(root)
	Stunts.buildPark(root)
	Stunts.buildDrift(root)
	World.Tracks = TrackBuilder.build(root, trailHeights, if trail then trail.samples else nil, true)

	local paths = {}
	for _, t in Tracks.List do
		table.insert(paths, { points = t.points, clearance = t.width / 2 + 14 })
	end
	Decor.build(root, cityTrees, paths)
	root:SetAttribute("Version", World.VERSION)
	print(string.format("[World] built in %.2fs, %d instances", os.clock() - started, #root:GetDescendants()))
	return root
end

function World.bake()
	local root = buildAll()
	root:SetAttribute("Baked", true)
	print("[World] baked. Save the place to keep it.")
	return root
end

function World.getTrack(id: string): TrackBuilder.TrackData?
	return World.Tracks[id]
end

-- Name of the bonus zone the position is in ("drift" / "stunt"), if any.
function World.zoneAt(pos: Vector3): (string?, number)
	for name, zone in Layout.Zones do
		local d = pos - zone.center
		if math.abs(d.X) <= zone.size.X / 2 and math.abs(d.Z) <= zone.size.Z / 2 and d.Y <= zone.size.Y then
			return name, zone.multiplier
		end
	end
	return nil, 1
end

function World.waitUntilReady()
	while not World.Ready do
		task.wait(0.1)
	end
end

-- Building takes a few seconds, so it runs in start(); other systems wait on
-- World.Ready / World.ReadySignal where they need the map.
local function setup()
	local root = workspace:FindFirstChild("CarsWorld")
	if root and root:GetAttribute("Baked") and root:GetAttribute("Version") == World.VERSION then
		-- baked in Studio: only compute data
		local trail = trailInfo()
		local heights = if trail then TerrainGen.trailHeights(trail) else nil
		World.Tracks = TrackBuilder.build(root, heights, if trail then trail.samples else nil, false)
		World.Root = root
	else
		World.Root = buildAll()
	end
	World.Ready = true
	World.ReadySignal:Fire()
end

function World.start()
	local ok, err = pcall(setup)
	if not ok then
		warn("[World] build failed: " .. tostring(err))
		World.Ready = true
		World.ReadySignal:Fire()
	end
	-- put knocked-over cones back when nobody is around
	task.spawn(function()
		while true do
			task.wait(45)
			for _, cone in CollectionService:GetTagged("Cone") do
				if cone:IsA("BasePart") then
					local home = cone:GetAttribute("Home")
					if typeof(home) == "CFrame" and (cone.Position - home.Position).Magnitude > 3 then
						local busy = false
						for _, car in CollectionService:GetTagged("Car") do
							local pp = (car :: Model).PrimaryPart
							if pp and (pp.Position - home.Position).Magnitude < 80 then
								busy = true
								break
							end
						end
						if not busy then
							cone.AssemblyLinearVelocity = Vector3.zero
							cone.AssemblyAngularVelocity = Vector3.zero
							cone.CFrame = home
						end
					end
				end
			end
		end
	end)
end

-- keep Build referenced for command bar users who want helpers
World.Build = Build

return World
