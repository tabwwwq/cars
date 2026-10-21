-- WorldText: translates signs, boards and prompts in the world to the
-- player's language, and spins the showroom cars.

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Strings = require(Shared.Strings)
local Tracks = require(Shared.Tracks)

local WorldText = {}

local function trackName(id: any): string
	local t = Tracks.get(id)
	return if t then Strings.pick(t.name) else tostring(id or "")
end

local function translate(label: Instance)
	if not label:IsA("TextLabel") then
		return
	end
	local key = label:GetAttribute("LocKey")
	if typeof(key) ~= "string" then
		return
	end
	local track = label:GetAttribute("LocTrack")
	if track then
		label.Text = Strings.get(key, trackName(track))
	else
		label.Text = Strings.get(key)
	end
end

local function translatePrompt(prompt: ProximityPrompt)
	local action = prompt:GetAttribute("LocAction")
	if typeof(action) == "string" then
		prompt.ActionText = Strings.get(action)
	end
	local track = prompt:GetAttribute("LocTrack")
	if track then
		prompt.ObjectText = trackName(track)
	end
	local object = prompt:GetAttribute("LocObject")
	if typeof(object) == "string" then
		prompt.ObjectText = Strings.get(object)
	end
end

-- showroom turntables
type Spinner = { model: Model, center: Vector3, offset: CFrame, angle: number, speed: number }
local spinners: { [Model]: Spinner } = {}

local function addSpinner(model: Instance)
	if not model:IsA("Model") or spinners[model] then
		return
	end
	local center = model:GetAttribute("SpinCenter")
	if typeof(center) ~= "Vector3" then
		return
	end
	local pivot = model:GetPivot()
	spinners[model] = {
		model = model,
		center = center,
		offset = CFrame.new(center):ToObjectSpace(pivot),
		angle = 0,
		speed = model:GetAttribute("SpinSpeed") or 0.25,
	}
end

function WorldText.start()
	for _, label in CollectionService:GetTagged("LocText") do
		translate(label)
	end
	CollectionService:GetInstanceAddedSignal("LocText"):Connect(translate)
	-- leaderboards switch rows between "empty" and names at runtime
	CollectionService:GetInstanceAddedSignal("LocText"):Connect(function(label)
		label:GetAttributeChangedSignal("LocKey"):Connect(function()
			translate(label)
		end)
	end)

	ProximityPromptService.PromptShown:Connect(function(prompt)
		translatePrompt(prompt)
	end)

	for _, m in CollectionService:GetTagged("Showcase") do
		addSpinner(m)
	end
	CollectionService:GetInstanceAddedSignal("Showcase"):Connect(addSpinner)
	CollectionService:GetInstanceRemovedSignal("Showcase"):Connect(function(m)
		spinners[m :: Model] = nil
	end)
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local camPos = camera.CFrame.Position
		for model, s in spinners do
			if not model.Parent then
				spinners[model] = nil
			elseif (s.center - camPos).Magnitude < 250 then
				s.angle += dt * s.speed
				model:PivotTo(CFrame.new(s.center) * CFrame.Angles(0, s.angle, 0) * s.offset)
			end
		end
	end)
end

return WorldText
