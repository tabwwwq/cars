-- ServiceFX: animates customers and staff of every service plot. The server
-- stores a path on the model (Util/Path attributes) and parks it at the end;
-- here every client replays the trip smoothly. Staff swing their arms and
-- legs while walking and scrub while working.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Path = require(Shared.Util.Path)

local ServiceFX = {}

type Mover = {
	model: Model,
	track: Path.Track?,
	key: string?,
	start: number,
	speed: number,
	reverse: boolean,
	y: number,
	duration: number,
	done: boolean,
	joints: { [string]: Motor6D },
	phase: number,
}

local movers: { [Model]: Mover } = {}

local function readPath(m: Mover)
	local model = m.model
	local text = model:GetAttribute("MovePath")
	if typeof(text) ~= "string" or text == "" then
		m.track = nil
		m.done = true
		return
	end
	local key = text .. "|" .. tostring(model:GetAttribute("MoveStart"))
	if key == m.key then
		return
	end
	m.key = key
	m.track = Path.new(Path.decode(text))
	m.start = tonumber(model:GetAttribute("MoveStart")) or 0
	m.speed = tonumber(model:GetAttribute("MoveSpeed")) or 10
	m.reverse = model:GetAttribute("MoveReverse") == true
	m.y = tonumber(model:GetAttribute("MoveY")) or 0
	m.duration = Path.duration((m.track :: Path.Track).length, m.speed)
	m.done = false
end

local function add(model: Instance)
	if not model:IsA("Model") or movers[model] then
		return
	end
	local m: Mover = {
		model = model,
		track = nil,
		key = nil,
		start = 0,
		speed = 10,
		reverse = false,
		y = 0,
		duration = 0,
		done = true,
		joints = {},
		phase = math.random() * 10,
	}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			m.joints[d.Name] = d
		end
	end
	movers[model] = m
	readPath(m)
	for _, attr in { "MovePath", "MoveStart" } do
		model:GetAttributeChangedSignal(attr):Connect(function()
			readPath(m)
		end)
	end
end

local function remove(model: Instance)
	movers[model :: Model] = nil
end

local function animateLimbs(m: Mover, walking: boolean, working: boolean, t: number)
	local j = m.joints
	if not next(j) then
		return
	end
	local swing = 0
	if walking then
		swing = math.sin(t * 9 + m.phase) * 0.7
	end
	local armR = -swing
	local armL = swing
	if working then
		armR = -1.3 + math.sin(t * 11 + m.phase) * 0.45
		armL = -0.9 + math.sin(t * 11 + m.phase + 1.5) * 0.3
	end
	if j.Joint_LegL then
		j.Joint_LegL.Transform = CFrame.Angles(swing, 0, 0)
	end
	if j.Joint_LegR then
		j.Joint_LegR.Transform = CFrame.Angles(-swing, 0, 0)
	end
	if j.Joint_ArmL then
		j.Joint_ArmL.Transform = CFrame.Angles(armL, 0, 0)
	end
	if j.Joint_ArmR then
		j.Joint_ArmR.Transform = CFrame.Angles(armR, 0, 0)
	end
end

function ServiceFX.start()
	for _, tag in { "ServiceCustomer", "ServiceWorker" } do
		for _, model in CollectionService:GetTagged(tag) do
			add(model)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(add)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
	end
	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		local t = os.clock()
		for model, m in movers do
			if not model.Parent then
				movers[model] = nil
				continue
			end
			local root = model.PrimaryPart
			if not root then
				continue
			end
			local moving = false
			if not m.done and m.track then
				local track = m.track :: Path.Track
				local elapsed = now - m.start
				local d = Path.distanceAt(track.length, m.speed, elapsed)
				root.CFrame = Path.groundCFrame(track, d, m.y, m.reverse)
				moving = elapsed < m.duration
				if not moving then
					m.done = true
				end
			end
			if (root.Position - camPos).Magnitude < 220 then
				animateLimbs(m, moving, model:GetAttribute("Working") == true, t)
			end
		end
	end)
end

return ServiceFX
