-- Service: the car-service mode on the server.
--
-- Every player gets one of the plots from World.ServicePlots. Customers drive
-- into its parking lot with an order (wash / repair / paint), the owner takes
-- the order (the vehicle drives into a free bay) and does the hands-on steps in
-- the Workshop controller. The client reports each finished step; the server
-- checks the timing, updates the vehicle for everyone and pays at the end.
-- Hired staff take orders that waited a while and do them on their own.
--
-- Vehicles and staff move with Util/Path: the server sets the path once and
-- parks the model at the end, the clients animate the trip.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local CarBuilder = require(Shared.CarBuilder)
local CarCatalog = require(Shared.CarCatalog)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Paints = require(Shared.Paints)
local Path = require(Shared.Util.Path)
local ServiceConfig = require(Shared.ServiceConfig)
local ServiceModels = require(Shared.ServiceModels)

local Systems = script.Parent
local PlayerData = require(Systems.PlayerData)
local Vehicles = require(Systems.Vehicles)
local World = require(Systems.World)
local ServicePlots = require(Systems.Parent.World.ServicePlots)

local Service = {}

type Order = ServiceConfig.Order

export type Job = {
	id: number,
	order: Order,
	plot: PlotState,
	model: Model,
	size: ServiceConfig.Size,
	steps: { string },
	step: number, -- index of the current step; > #steps when done
	state: "arriving" | "waiting" | "toBay" | "inBay" | "leaving",
	assignee: string?, -- "player" or "worker"
	worker: Worker?,
	spot: number?,
	bay: number?,
	waitingSince: number,
	stepStart: number?,
	working: boolean,
	workStart: number?,
	activeTime: number,
	moveEnd: number?,
	onArrive: (() -> ())?,
	workerStart: number?,
	workerDuration: number?,
	tag: TextLabel?,
	tagText: string?,
}

export type Worker = {
	index: number,
	model: Model,
	state: "idle" | "walking" | "working" | "returning",
	job: Job?,
	moveEnd: number?,
	onArrive: (() -> ())?,
}

export type PlotState = {
	data: ServicePlots.PlotData,
	owner: Player?,
	jobs: { [number]: Job },
	spots: { [number]: Job },
	bays: { [number]: Job },
	workers: { Worker },
	nextArrival: number,
	rng: Random,
	customers: Folder,
	dirty: boolean,
	lastPush: number,
}

local plots: { PlotState } = {}
local plotOf: { [Player]: PlotState } = {}
local nextJobId = 0

local MUD = Color3.fromRGB(92, 74, 56)
local FADED = Color3.fromRGB(150, 146, 140)

-- Clock shared with the clients (overridable in tests).
function Service.now(): number
	return Workspace:GetServerTimeNow()
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function profileService(player: Player): any
	local data = PlayerData.get(player)
	return data and data.service
end

local function upgradesOf(plot: PlotState): { [string]: number }
	local svc = plot.owner and profileService(plot.owner)
	return if svc then svc.upgrades else {}
end

local function levelOf(plot: PlotState): number
	local svc = plot.owner and profileService(plot.owner)
	return if svc then svc.level else 1
end

local function markDirty(plot: PlotState)
	plot.dirty = true
end

local function world(plot: PlotState, x: number, z: number): Vector3
	return plot.data.cf * Vector3.new(x, 0, z)
end

local function groundY(plot: PlotState): number
	return plot.data.cf.Position.Y
end

-- Sets a path on a model; the server parks it at the end, clients animate.
local function move(plot: PlotState, model: Model, points: { Vector3 }, speed: number, reverse: boolean?): number
	local track = Path.new(points)
	local y = groundY(plot)
	model:SetAttribute("MovePath", Path.encode(points))
	model:SetAttribute("MoveStart", Service.now())
	model:SetAttribute("MoveSpeed", speed)
	model:SetAttribute("MoveReverse", reverse == true)
	model:SetAttribute("MoveY", y)
	model:PivotTo(Path.groundCFrame(track, track.length, y, reverse))
	return Service.now() + Path.duration(track.length, speed)
end

local function setLabels(part: BasePart, key: string, arg: string?)
	for _, d in part:GetDescendants() do
		if d:IsA("TextLabel") then
			d:SetAttribute("LocKey", key)
			d:SetAttribute("LocArg", arg)
			d.Text = if arg then arg else d.Text
		end
	end
end

--------------------------------------------------------------------------------
-- Routes (plot space -> world)
--------------------------------------------------------------------------------

local P = ServicePlots

local function arrivalPath(plot: PlotState, spot: number): { Vector3 }
	local sx = P.SpotX[spot]
	local pts = {
		Vector3.new(P.EntryX - 150, 0, P.RoadZ),
		Vector3.new(P.EntryX - 34, 0, P.RoadZ),
		Vector3.new(P.EntryX, 0, P.Front + 6),
		Vector3.new(P.EntryX, 0, P.AisleZ + 6),
		Vector3.new(P.EntryX + 14, 0, P.AisleZ),
	}
	if sx - 16 > P.EntryX + 22 then
		table.insert(pts, Vector3.new(sx - 16, 0, P.AisleZ))
	end
	table.insert(pts, Vector3.new(sx, 0, P.SpotZ + 16))
	table.insert(pts, Vector3.new(sx, 0, P.SpotZ))
	local out = {}
	for i, p in pts do
		out[i] = world(plot, p.X, p.Z)
	end
	return out
end

local function spotToBayPath(plot: PlotState, spot: number, bay: number): { Vector3 }
	local sx, bx = P.SpotX[spot], P.BayX[bay]
	local pts = { Vector3.new(sx, 0, P.SpotZ), Vector3.new(sx, 0, P.SpotZ - 16) }
	local dx = bx - sx
	if math.abs(dx) > 24 then
		local dir = math.sign(dx)
		table.insert(pts, Vector3.new(sx + dir * 12, 0, P.LaneZ))
		table.insert(pts, Vector3.new(bx - dir * 12, 0, P.LaneZ))
	elseif math.abs(dx) > 1 then
		table.insert(pts, Vector3.new((sx + bx) / 2, 0, P.LaneZ))
	end
	table.insert(pts, Vector3.new(bx, 0, -6))
	table.insert(pts, Vector3.new(bx, 0, P.BayZ))
	local out = {}
	for i, p in pts do
		out[i] = world(plot, p.X, p.Z)
	end
	return out
end

-- Forward route from the work lane (heading east) out to the street.
local function exitTail(fromX: number): { Vector3 }
	local pts = {}
	if P.ExitX - 16 > fromX + 10 then
		table.insert(pts, Vector3.new(P.ExitX - 16, 0, P.LaneZ + 2))
	end
	table.insert(pts, Vector3.new(P.ExitX, 0, P.LaneZ + 18))
	table.insert(pts, Vector3.new(P.ExitX, 0, P.AisleZ + 8))
	table.insert(pts, Vector3.new(P.ExitX + 6, 0, P.Front + 8))
	table.insert(pts, Vector3.new(P.ExitX + 36, 0, P.RoadZ))
	table.insert(pts, Vector3.new(P.ExitX + 170, 0, P.RoadZ))
	return pts
end

local function toWorld(plot: PlotState, pts: { Vector3 }): { Vector3 }
	local out = {}
	for i, p in pts do
		out[i] = world(plot, p.X, p.Z)
	end
	return out
end

--------------------------------------------------------------------------------
-- Customer vehicles
--------------------------------------------------------------------------------

local function buildVehicle(order: Order): Model?
	local model: Model? = nil
	if order.source == "model" then
		model = ServiceModels.build(order.vehicle, { paint = order.paint })
	else
		local def = CarCatalog.get(order.vehicle)
		if def then
			local save = CarCatalog.defaultSave(def)
			save.paint = order.paint
			local car = CarBuilder.build(def, { preview = true, save = save })
			local root = Instance.new("Part")
			root.Name = "Root"
			root.Size = Vector3.new(1, 1, 1)
			root.CFrame = CFrame.new()
			root.Transparency = 1
			root.Anchored = true
			root.CanCollide = false
			root.CanQuery = false
			root.CanTouch = false
			root.Parent = car
			car.PrimaryPart = root
			model = car
		end
	end
	if not model then
		return nil
	end
	local m = model :: Model
	local dirty = table.find(order.services, "wash") ~= nil
	local faded = table.find(order.services, "paint") ~= nil
	local broken = table.find(order.services, "repair") ~= nil
	local height = 0
	local front: BasePart? = nil
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			height = math.max(height, d.Position.Y + d.Size.Y / 2)
			if d:GetAttribute("Role") == "Paint" and (front == nil or d.Position.Z < front.Position.Z) then
				front = d
			end
			local role = d:GetAttribute("Role")
			local clean = d.Color
			if faded and role == "Paint" then
				d:SetAttribute("PaintColor", clean)
				d.Color = clean:Lerp(FADED, 0.55)
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0
				clean = d.Color
			end
			if dirty and role ~= "Light" and role ~= "Taillight" and role ~= "Headlight" and role ~= "Indicator" then
				d:SetAttribute("CleanColor", clean)
				d.Color = clean:Lerp(MUD, 0.38)
			end
		end
	end
	if broken then
		local smoke = Instance.new("Smoke")
		smoke.Name = "BrokenSmoke"
		smoke.Color = Color3.fromRGB(70, 70, 76)
		smoke.Opacity = 0.12
		smoke.RiseVelocity = 3
		smoke.Size = math.clamp(height * 0.3, 0.6, 2.5)
		smoke.Parent = front or m.PrimaryPart
	end
	m:SetAttribute("Height", height)
	ServiceModels.weldToRoot(m)
	return m
end

local function tagText(job: Job): string
	local icons = {}
	for _, s in job.order.services do
		local svc = ServiceConfig.getService(s)
		if svc then
			table.insert(icons, svc.icon)
		end
	end
	local base = table.concat(icons, " ") .. "  $" .. tostring(job.order.reward)
	if job.state == "leaving" then
		return "✅"
	elseif job.assignee == "worker" and job.workerStart and job.workerDuration then
		local pct = math.clamp((Service.now() - job.workerStart) / job.workerDuration, 0, 1)
		return string.format("👷 %d%%", math.floor(pct * 100))
	elseif job.assignee == "player" then
		return string.format("🛠 %d/%d", math.min(job.step, #job.steps), #job.steps)
	end
	return base
end

local function makeTag(job: Job)
	local gui = Instance.new("BillboardGui")
	gui.Name = "OrderTag"
	gui.Size = UDim2.fromOffset(150, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (job.model:GetAttribute("Height") or 4) + 2.2, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 36)
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = tagText(job)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 128, 32)
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = job.model.PrimaryPart
	job.tag = label
end

local function refreshTag(job: Job)
	local tag = job.tag
	if tag then
		local text = tagText(job)
		if text ~= job.tagText then
			job.tagText = text
			tag.Text = text
		end
	end
end

-- Visual changes for everyone when a whole service is finished.
local function finishServiceVisuals(job: Job, serviceId: string)
	local model = job.model
	if serviceId == "repair" then
		for _, d in model:GetDescendants() do
			if d:IsA("Smoke") then
				d:Destroy()
			end
		end
	elseif serviceId == "paint" then
		local target = Paints.getColor(job.order.target)
		local stillDirty = table.find(job.order.services, "wash") ~= nil and job.step <= #job.steps
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Role") == "Paint" then
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0.12
				if d:GetAttribute("CleanColor") ~= nil then
					d:SetAttribute("CleanColor", target)
				end
				d.Color = if stillDirty then target:Lerp(MUD, 0.38) else target
			end
		end
	elseif serviceId == "wash" then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local clean = d:GetAttribute("CleanColor")
				if typeof(clean) == "Color3" then
					d.Color = clean
					d:SetAttribute("CleanColor", nil)
				end
			end
		end
	end
end

local function updateBoard(plot: PlotState)
	local rows = plot.data.boardRows
	local waiting = {}
	for _, job in plot.jobs do
		if job.state == "waiting" and job.assignee == nil then
			table.insert(waiting, job)
		end
	end
	table.sort(waiting, function(a, b)
		return a.id < b.id
	end)
	for i, row in rows do
		local job = waiting[i]
		if job then
			local tier = ServiceConfig.getTier(job.order.tier)
			row.Text = string.format("  %s  %s", if tier then tier.icon else "", tagText(job))
		else
			row.Text = ""
		end
	end
end

local function destroyJob(job: Job)
	local plot = job.plot
	plot.jobs[job.id] = nil
	if job.spot and plot.spots[job.spot] == job then
		plot.spots[job.spot] = nil
	end
	if job.bay and plot.bays[job.bay] == job then
		plot.bays[job.bay] = nil
	end
	if job.model then
		job.model:Destroy()
	end
	markDirty(plot)
end

-- Drives a vehicle out of the plot and removes it.
local function leave(job: Job, fromBay: boolean)
	local plot = job.plot
	job.state = "leaving"
	job.working = false
	refreshTag(job)
	local speed = job.size.speed
	if fromBay and job.bay then
		local bx = P.BayX[job.bay]
		plot.bays[job.bay] = nil
		job.bay = nil
		job.moveEnd = move(plot, job.model, toWorld(plot, {
			Vector3.new(bx, 0, P.BayZ),
			Vector3.new(bx, 0, -4),
			Vector3.new(bx - 6, 0, P.LaneZ),
			Vector3.new(bx - 18, 0, P.LaneZ + 4),
		}), speed * 0.6, true)
		job.onArrive = function()
			local pts = { Vector3.new(bx - 18, 0, P.LaneZ + 4), Vector3.new(bx - 4, 0, P.LaneZ + 2) }
			for _, p in exitTail(bx - 4) do
				table.insert(pts, p)
			end
			job.moveEnd = move(plot, job.model, toWorld(plot, pts), speed)
			job.onArrive = function()
				destroyJob(job)
			end
		end
	else
		local sx = if job.spot then P.SpotX[job.spot] else 0
		if job.spot then
			plot.spots[job.spot] = nil
			job.spot = nil
		end
		local pts = { Vector3.new(sx, 0, P.SpotZ), Vector3.new(sx, 0, P.SpotZ - 14), Vector3.new(sx + 12, 0, P.LaneZ + 2) }
		for _, p in exitTail(sx + 12) do
			table.insert(pts, p)
		end
		job.moveEnd = move(plot, job.model, toWorld(plot, pts), speed)
		job.onArrive = function()
			destroyJob(job)
		end
	end
	markDirty(plot)
end

local function spawnCustomer(plot: PlotState): Job?
	local owner = plot.owner
	if not owner then
		return nil
	end
	local upgrades = upgradesOf(plot)
	local spot: number? = nil
	for i = 1, math.min(ServiceConfig.parkingCount(upgrades), #P.SpotX) do
		if plot.spots[i] == nil then
			spot = i
			break
		end
	end
	if not spot then
		return nil
	end
	local order = ServiceConfig.makeOrder(levelOf(plot), plot.rng, upgrades.marketing or 0)
	local model = buildVehicle(order)
	if not model then
		return nil
	end
	local tier = ServiceConfig.getTier(order.tier) :: ServiceConfig.Tier
	nextJobId += 1
	local job: Job = {
		id = nextJobId,
		order = order,
		plot = plot,
		model = model,
		size = ServiceConfig.Sizes[tier.size],
		steps = ServiceConfig.stepsFor(order.services),
		step = 1,
		state = "arriving",
		spot = spot,
		waitingSince = Service.now(),
		working = false,
		activeTime = 0,
	}
	model.Name = "Customer_" .. job.id
	model:SetAttribute("ServiceJob", job.id)
	model:SetAttribute("Owner", owner.UserId)
	model:SetAttribute("Tier", order.tier)
	model:SetAttribute("Size", tier.size)
	model.Parent = plot.customers
	CollectionService:AddTag(model, "ServiceCustomer")
	makeTag(job)
	plot.jobs[job.id] = job
	plot.spots[spot] = job
	job.moveEnd = move(plot, model, arrivalPath(plot, spot), job.size.speed)
	job.onArrive = function()
		job.state = "waiting"
		job.waitingSince = Service.now()
		refreshTag(job)
		updateBoard(plot)
		markDirty(plot)
		if plot.owner then
			Net.fire(plot.owner, "ServiceEvent", "arrived", job.id)
		end
	end
	markDirty(plot)
	return job
end

local function freeBay(plot: PlotState): number?
	local count = math.min(ServiceConfig.bayCount(upgradesOf(plot)), #P.BayX)
	for i = 1, count do
		if plot.bays[i] == nil then
			return i
		end
	end
	return nil
end

-- Sends a waiting customer into a bay.
local function sendToBay(job: Job, bay: number, onArrive: () -> ())
	local plot = job.plot
	local spot = job.spot :: number
	plot.spots[spot] = nil
	plot.bays[bay] = job
	job.bay = bay
	job.state = "toBay"
	job.moveEnd = move(plot, job.model, spotToBayPath(plot, spot, bay), job.size.speed * 0.8)
	job.spot = nil
	job.onArrive = function()
		job.state = "inBay"
		onArrive()
		markDirty(plot)
	end
	updateBoard(plot)
	markDirty(plot)
end

--------------------------------------------------------------------------------
-- Rewards and levels
--------------------------------------------------------------------------------

local function addXp(player: Player, amount: number)
	local levels = {}
	PlayerData.update(player, function(data)
		local svc = data.service
		svc.xp += amount
		while svc.level < ServiceConfig.MaxLevel and svc.xp >= ServiceConfig.xpToNext(svc.level) do
			svc.xp -= ServiceConfig.xpToNext(svc.level)
			svc.level += 1
			table.insert(levels, svc.level)
		end
		if svc.level >= ServiceConfig.MaxLevel then
			svc.xp = 0
		end
	end)
	for _, level in levels do
		Net.fire(player, "ServiceEvent", "levelup", level)
	end
end

local function complete(job: Job, byWorker: boolean)
	local plot = job.plot
	local owner = plot.owner
	if owner then
		local reward = job.order.reward
		local xp = job.order.xp
		local stars = 0
		local tip = 0
		if byWorker then
			reward = math.floor(reward * ServiceConfig.WorkerShare)
			xp = math.max(1, math.floor(xp * ServiceConfig.WorkerXp))
		else
			local svc = profileService(owner)
			local tools = if svc then svc.upgrades.tools or 0 else 0
			local par = ServiceConfig.parTime(job.size, #job.steps, tools)
			stars = ServiceConfig.stars(job.activeTime, par)
			tip = math.floor(reward * ServiceConfig.StarTips[stars])
		end
		local total = reward + tip
		PlayerData.addCash(owner, total, "service")
		PlayerData.update(owner, function(data)
			data.service.orders += 1
			data.service.earned += total
			data.service.stars += stars
		end)
		addXp(owner, xp)
		Net.fire(owner, "Reward", if byWorker then "serviceWorker" else "service", total, stars)
		Net.fire(owner, "ServiceEvent", "done", {
			job = job.id,
			reward = reward,
			tip = tip,
			xp = xp,
			stars = stars,
			worker = byWorker,
			vehicle = job.order.vehicle,
			source = job.order.source,
		})
	end
	leave(job, true)
end

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

local LOOKS = {
	{ shirt = Color3.fromRGB(240, 240, 236), pants = Color3.fromRGB(40, 88, 170), cap = Color3.fromRGB(255, 128, 32) },
	{ shirt = Color3.fromRGB(255, 220, 90), pants = Color3.fromRGB(60, 60, 70), cap = Color3.fromRGB(220, 50, 50), hair = Color3.fromRGB(150, 80, 40) },
	{ shirt = Color3.fromRGB(120, 200, 140), pants = Color3.fromRGB(70, 60, 50), cap = Color3.fromRGB(40, 120, 220), skin = Color3.fromRGB(150, 100, 70) },
	{ shirt = Color3.fromRGB(230, 120, 160), pants = Color3.fromRGB(40, 88, 170), hair = Color3.fromRGB(230, 200, 120) },
}

local function spawnWorker(plot: PlotState, index: number)
	local look = LOOKS[((index - 1) % #LOOKS) + 1]
	local model = ServiceModels.person("Worker_" .. index, look)
	ServiceModels.weldToRoot(model)
	model:SetAttribute("Worker", index)
	model:SetAttribute("Owner", if plot.owner then plot.owner.UserId else 0)
	local idle = plot.data.idle[((index - 1) % #plot.data.idle) + 1]
	model:PivotTo(idle)
	model.Parent = plot.customers
	CollectionService:AddTag(model, "ServiceWorker")
	table.insert(plot.workers, { index = index, model = model, state = "idle" })
end

local function workerPath(plot: PlotState, worker: Worker, bay: number, toBay: boolean): { Vector3 }
	local idle = plot.data.cf:PointToObjectSpace(plot.data.idle[((worker.index - 1) % #plot.data.idle) + 1].Position)
	local bx = P.BayX[bay] + 9
	local pts = {
		Vector3.new(idle.X, 0, idle.Z),
		Vector3.new(-76, 0, 26),
		Vector3.new(-76, 0, 16),
		Vector3.new(bx, 0, P.LaneZ - 4),
		Vector3.new(bx, 0, -10),
		Vector3.new(bx, 0, P.BayZ + 4),
	}
	if not toBay then
		local rev = {}
		for i = #pts, 1, -1 do
			table.insert(rev, pts[i])
		end
		pts = rev
	end
	return toWorld(plot, pts)
end

local function assignWorker(plot: PlotState, worker: Worker, job: Job, bay: number)
	worker.job = job
	worker.state = "walking"
	job.assignee = "worker"
	job.worker = worker
	local arrived = { car = false, worker = false }
	local function begin()
		if not (arrived.car and arrived.worker) or job.state ~= "inBay" then
			return
		end
		local svc = plot.owner and profileService(plot.owner)
		local training = if svc then svc.upgrades.training or 0 else 0
		worker.state = "working"
		worker.model:SetAttribute("Working", true)
		job.workerStart = Service.now()
		job.workerDuration = #job.steps * job.size.workerStep / ServiceConfig.workerSpeed(training)
		job.model:SetAttribute("WorkerStart", job.workerStart)
		job.model:SetAttribute("WorkerDuration", job.workerDuration)
		markDirty(plot)
	end
	sendToBay(job, bay, function()
		arrived.car = true
		begin()
	end)
	worker.moveEnd = move(plot, worker.model, workerPath(plot, worker, bay, true), 11)
	worker.onArrive = function()
		arrived.worker = true
		-- face the vehicle
		local cf = worker.model:GetPivot()
		local target = plot.data.bays[bay].Position
		worker.model:PivotTo(CFrame.lookAt(cf.Position, Vector3.new(target.X, cf.Position.Y, target.Z)))
		begin()
	end
	markDirty(plot)
end

local function workerDone(plot: PlotState, worker: Worker, bay: number)
	worker.job = nil
	worker.state = "returning"
	worker.model:SetAttribute("Working", false)
	worker.moveEnd = move(plot, worker.model, workerPath(plot, worker, bay, false), 11)
	worker.onArrive = function()
		worker.state = "idle"
		worker.model:PivotTo(plot.data.idle[((worker.index - 1) % #plot.data.idle) + 1])
		markDirty(plot)
	end
end

--------------------------------------------------------------------------------
-- Snapshot for the owner's client
--------------------------------------------------------------------------------

function Service.snapshot(plot: PlotState)
	local jobs = {}
	for _, job in plot.jobs do
		table.insert(jobs, {
			id = job.id,
			tier = job.order.tier,
			source = job.order.source,
			vehicle = job.order.vehicle,
			services = job.order.services,
			paint = job.order.paint,
			target = job.order.target,
			reward = job.order.reward,
			xp = job.order.xp,
			state = job.state,
			assignee = job.assignee,
			worker = if job.worker then job.worker.index else nil,
			spot = job.spot,
			bay = job.bay,
			steps = job.steps,
			step = job.step,
			size = job.model:GetAttribute("Size"),
			waitingSince = job.waitingSince,
			workerStart = job.workerStart,
			workerDuration = job.workerDuration,
			arriveAt = job.moveEnd,
		})
	end
	table.sort(jobs, function(a, b)
		return a.id < b.id
	end)
	local workers = {}
	for _, w in plot.workers do
		table.insert(workers, { index = w.index, state = w.state, job = if w.job then w.job.id else nil })
	end
	return {
		plot = plot.data.index,
		origin = plot.data.cf,
		reception = plot.data.reception,
		jobs = jobs,
		workers = workers,
		serverTime = Service.now(),
	}
end

local function push(plot: PlotState)
	plot.dirty = false
	plot.lastPush = os.clock()
	if plot.owner and plot.owner.Parent then
		Net.fire(plot.owner, "ServiceState", Service.snapshot(plot))
	end
end

--------------------------------------------------------------------------------
-- Plots
--------------------------------------------------------------------------------

local function openDoor(plot: PlotState, bay: number, instant: boolean?)
	local door = plot.data.doors[bay]
	if not door then
		return
	end
	local closed = door:GetAttribute("ClosedCFrame")
	if typeof(closed) ~= "CFrame" then
		return
	end
	local open = closed * CFrame.new(0, 7.6, 0)
	door.CanCollide = false
	if instant then
		door.CFrame = open
		door.Size = Vector3.new(door.Size.X, 2.4, door.Size.Z)
	else
		TweenService:Create(door, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { CFrame = open, Size = Vector3.new(door.Size.X, 2.4, door.Size.Z) }):Play()
	end
end

local function closeDoor(plot: PlotState, bay: number)
	local door = plot.data.doors[bay]
	if not door then
		return
	end
	local closed = door:GetAttribute("ClosedCFrame")
	if typeof(closed) == "CFrame" then
		door.CFrame = closed
		door.Size = Vector3.new(door.Size.X, 17.6, door.Size.Z)
		door.CanCollide = true
	end
end

local function syncPlotToProfile(plot: PlotState)
	local upgrades = upgradesOf(plot)
	for bay = 2, #P.BayX do
		if bay <= ServiceConfig.bayCount(upgrades) then
			openDoor(plot, bay, true)
		else
			closeDoor(plot, bay)
		end
	end
	while #plot.workers < (upgrades.staff or 0) do
		spawnWorker(plot, #plot.workers + 1)
	end
end

local function claim(player: Player): PlotState?
	if plotOf[player] then
		return plotOf[player]
	end
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = player
			plotOf[player] = plot
			plot.nextArrival = Service.now() + ServiceConfig.FirstArrival
			plot.rng = Random.new(player.UserId + os.time())
			plot.customers:SetAttribute("Owner", player.UserId)
			plot.data.folder:SetAttribute("Owner", player.UserId)
			setLabels(plot.data.sign, "ServiceSignOwner", player.DisplayName)
			syncPlotToProfile(plot)
			player:SetAttribute("ServicePlot", plot.data.index)
			push(plot)
			return plot
		end
	end
	Net.notify(player, "ServiceNoPlot", {}, "warning")
	return nil
end

local function release(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	plotOf[player] = nil
	for _, job in plot.jobs do
		if job.model then
			job.model:Destroy()
		end
	end
	for _, w in plot.workers do
		w.model:Destroy()
	end
	table.clear(plot.jobs)
	table.clear(plot.spots)
	table.clear(plot.bays)
	table.clear(plot.workers)
	plot.owner = nil
	plot.customers:SetAttribute("Owner", nil)
	plot.data.folder:SetAttribute("Owner", nil)
	setLabels(plot.data.sign, "ServiceSignFree", nil)
	for bay = 2, #P.BayX do
		closeDoor(plot, bay)
	end
	updateBoard(plot)
end

function Service.getPlot(player: Player): PlotState?
	return plotOf[player]
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

local function stepMovers(now: number, holder: { moveEnd: number?, onArrive: (() -> ())? })
	if holder.moveEnd and now >= holder.moveEnd then
		holder.moveEnd = nil
		local cb = holder.onArrive
		holder.onArrive = nil
		if cb then
			cb()
		end
	end
end

function Service.update(now: number?)
	local t = now or Service.now()
	for _, plot in plots do
		if plot.owner then
			-- movement callbacks
			for _, job in plot.jobs do
				stepMovers(t, job :: any)
			end
			for _, w in plot.workers do
				stepMovers(t, w :: any)
			end
			-- staff progress
			for _, w in plot.workers do
				local job = w.job
				if w.state == "working" and job and job.workerStart and job.workerDuration then
					refreshTag(job)
					if t - job.workerStart >= job.workerDuration then
						local bay = job.bay :: number
						workerDone(plot, w, bay)
						complete(job, true)
					end
				end
			end
			-- idle staff take orders that waited long enough
			for _, w in plot.workers do
				if w.state == "idle" then
					local bay = freeBay(plot)
					if not bay then
						break
					end
					local pick: Job? = nil
					for _, job in plot.jobs do
						if job.state == "waiting" and job.assignee == nil and t - job.waitingSince >= ServiceConfig.WorkerPickDelay then
							if not pick or job.id < pick.id then
								pick = job
							end
						end
					end
					if pick then
						assignWorker(plot, w, pick, bay)
					end
				end
			end
			-- impatient customers leave
			for _, job in plot.jobs do
				if job.state == "waiting" and job.assignee == nil and t - job.waitingSince > ServiceConfig.Patience then
					leave(job, false)
					updateBoard(plot)
				end
			end
			-- new customers
			if t >= plot.nextArrival then
				local job = spawnCustomer(plot)
				local marketing = upgradesOf(plot).marketing or 0
				local interval = ServiceConfig.arrivalInterval(marketing)
				plot.nextArrival = t + (if job then interval * plot.rng:NextNumber(0.8, 1.2) else 3)
			end
			if plot.dirty and os.clock() - plot.lastPush > 0.2 then
				push(plot)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------------

local function ownJob(player: Player, id: any): Job?
	local plot = plotOf[player]
	if not plot or typeof(id) ~= "number" then
		return nil
	end
	return plot.jobs[id]
end

local function character(player: Player): Model?
	local char = player.Character
	if char and char.PrimaryPart then
		return char
	end
	return nil
end

local function teleport(player: Player, cf: CFrame)
	local char = character(player)
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart then
		Vehicles.exitSeat(player)
	end
	task.defer(function()
		if char.Parent then
			char:PivotTo(cf)
		end
	end)
end

local function stopWorking(job: Job)
	if job.working and job.workStart then
		job.activeTime += Service.now() - job.workStart
	end
	job.working = false
	job.workStart = nil
end

local function onTake(player: Player, id: any): Net.Result
	local job = ownJob(player, id)
	if not job or job.state ~= "waiting" or job.assignee ~= nil then
		return { ok = false, message = "ServiceGone" }
	end
	local bay = freeBay(job.plot)
	if not bay then
		return { ok = false, message = "ServiceNoBay" }
	end
	job.assignee = "player"
	sendToBay(job, bay, function()
		refreshTag(job)
		Net.fire(player, "ServiceEvent", "ready", job.id)
	end)
	refreshTag(job)
	return { ok = true }
end

local function onWork(player: Player, id: any): Net.Result
	local job = ownJob(player, id)
	if not job or job.assignee ~= "player" then
		return { ok = false, message = "ServiceGone" }
	end
	if job.state ~= "inBay" then
		return { ok = false, message = "ServiceArriving" }
	end
	-- only one job at a time
	for _, other in job.plot.jobs do
		if other ~= job and other.working then
			stopWorking(other)
		end
	end
	job.working = true
	job.workStart = Service.now()
	job.stepStart = job.stepStart or Service.now()
	local bay = job.plot.data.bays[job.bay :: number]
	local width = math.max(4, job.model:GetExtentsSize().X / 2)
	local stand = bay * CFrame.new(-(width + 4), 3, 6)
	teleport(player, CFrame.lookAt(stand.Position, Vector3.new(bay.Position.X, stand.Position.Y, bay.Position.Z)))
	markDirty(job.plot)
	return { ok = true, args = { job.step } }
end

local function onStep(player: Player, id: any, stepIndex: any): Net.Result
	local job = ownJob(player, id)
	if not job or job.assignee ~= "player" or job.state ~= "inBay" or not job.working then
		return { ok = false, message = "ServiceGone" }
	end
	if stepIndex ~= job.step then
		return { ok = false, args = { job.step } }
	end
	local char = character(player)
	local bayPos = job.plot.data.bays[job.bay :: number].Position
	if not char or ((char.PrimaryPart :: BasePart).Position - bayPos).Magnitude > 80 then
		return { ok = false, message = "ServiceTooFar" }
	end
	local svc = profileService(player)
	local tools = if svc then svc.upgrades.tools or 0 else 0
	local minimum = job.size.minStep / ServiceConfig.toolPower(tools)
	local now = Service.now()
	if now - (job.stepStart or now) < minimum * 0.85 then
		return { ok = false, message = "ServiceTooFast", args = { job.step } }
	end
	local stepId = job.steps[job.step]
	job.step += 1
	job.stepStart = now
	-- a whole service finished?
	local serviceId = ServiceConfig.serviceOfStep(stepId)
	local nextService = if job.steps[job.step] then ServiceConfig.serviceOfStep(job.steps[job.step]) else nil
	if serviceId and nextService ~= serviceId then
		finishServiceVisuals(job, serviceId)
	end
	refreshTag(job)
	if job.step > #job.steps then
		stopWorking(job)
		complete(job, false)
		return { ok = true, args = { job.step, true } }
	end
	markDirty(job.plot)
	return { ok = true, args = { job.step, false } }
end

local function onLeave(player: Player, id: any): Net.Result
	local job = ownJob(player, id)
	if job then
		stopWorking(job)
		markDirty(job.plot)
	end
	return { ok = true }
end

local function onDismiss(player: Player, id: any): Net.Result
	local job = ownJob(player, id)
	if not job or job.state ~= "waiting" or job.assignee ~= nil then
		return { ok = false }
	end
	leave(job, false)
	updateBoard(job.plot)
	return { ok = true }
end

local function onBuy(player: Player, upgradeId: any): Net.Result
	local upgrade = ServiceConfig.getUpgrade(upgradeId)
	local svc = profileService(player)
	if not upgrade or not svc then
		return { ok = false }
	end
	local current = svc.upgrades[upgrade.id] or 0
	local nextLevel = upgrade.levels[current + 1]
	if not nextLevel then
		return { ok = false, message = "MaxLevel" }
	end
	if svc.level < nextLevel.level then
		return { ok = false, message = "ServiceNeedLevel", args = { nextLevel.level } }
	end
	if not PlayerData.spend(player, nextLevel.price, "service:" .. upgrade.id) then
		local data = PlayerData.get(player)
		return { ok = false, message = "NotEnoughCash", args = { Format.money(nextLevel.price - (if data then data.cash else 0)) } }
	end
	PlayerData.update(player, function(data)
		data.service.upgrades[upgrade.id] = current + 1
	end)
	local plot = plotOf[player]
	if plot then
		syncPlotToProfile(plot)
		markDirty(plot)
	end
	return { ok = true, message = "ServiceUpgraded", args = { "Upgrade_" .. upgrade.id, current + 1 } }
end

local function onHome(player: Player): Net.Result
	local plot = plotOf[player] or claim(player)
	if not plot then
		return { ok = false, message = "ServiceNoPlot" }
	end
	teleport(player, plot.data.reception)
	return { ok = true }
end

local function onTutorial(player: Player, step: any): Net.Result
	if typeof(step) ~= "number" or step ~= math.floor(step) or step < 0 or step > 100 then
		return { ok = false }
	end
	PlayerData.update(player, function(data)
		data.service.tutorial = math.max(data.service.tutorial, step)
	end)
	return { ok = true }
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Service.setupPlots(list: { ServicePlots.PlotData })
	table.clear(plots)
	for _, data in list do
		local customers = data.folder:FindFirstChild("Customers")
		if not customers then
			customers = Instance.new("Folder")
			customers.Name = "Customers"
			customers.Parent = data.folder
		end
		table.insert(plots, {
			data = data,
			owner = nil,
			jobs = {},
			spots = {},
			bays = {},
			workers = {},
			nextArrival = 0,
			rng = Random.new(data.index),
			customers = customers :: Folder,
			dirty = false,
			lastPush = 0,
		})
	end
end

Service.claim = claim
Service.release = release
Service.spawnCustomer = spawnCustomer
Service.handlers = {
	take = onTake,
	work = onWork,
	step = onStep,
	leave = onLeave,
	dismiss = onDismiss,
	buy = onBuy,
	home = onHome,
	tutorial = onTutorial,
}

function Service.init()
	Net.handle("ServiceTake", onTake)
	Net.handle("ServiceWork", onWork)
	Net.handle("ServiceStep", onStep)
	Net.handle("ServiceLeave", onLeave)
	Net.handle("ServiceDismiss", onDismiss)
	Net.handle("ServiceBuy", onBuy)
	Net.handle("ServiceHome", onHome)
	Net.handle("ServiceTutorial", onTutorial)
end

function Service.start()
	World.waitUntilReady()
	Service.setupPlots(World.ServicePlots)
	PlayerData.Loaded:Connect(function(player)
		claim(player)
	end)
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			claim(player)
		end
	end
	Players.PlayerRemoving:Connect(release)
	RunService.Heartbeat:Connect(function()
		Service.update()
	end)
end

return Service
