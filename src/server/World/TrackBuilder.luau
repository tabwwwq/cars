-- TrackBuilder: lays the circuit road from its spline, builds checkpoint gates
-- and start areas for every track, and returns the data RaceService needs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Layout = require(script.Parent.Layout)

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Spline = require(Shared.Util.Spline)
local Tracks = require(Shared.Tracks)

local TrackBuilder = {}

local TOP = Layout.RoadTop
local TRACK_COLOR = Color3.fromRGB(52, 54, 60)

export type Checkpoint = { cf: CFrame, width: number, index: number }
export type TrackData = {
	id: string,
	def: Tracks.Track,
	length: number,
	laps: number,
	start: CFrame,
	checkpoints: { Checkpoint },
	medals: { gold: number, silver: number, bronze: number },
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Gate with two pillars and a translucent neon banner.
local function gate(parent: Instance, cf: CFrame, width: number, trackId: string, index: number, isFinish: boolean)
	local model = Instance.new("Model")
	model.Name = "Checkpoint_" .. index
	local color = if isFinish then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(80, 200, 255)
	local half = width / 2 + 3
	for _, side in { -1, 1 } do
		local base = (cf * CFrame.new(side * half, 0, 0)).Position
		Build.pole(model, base, 16, 1.4, Color3.fromRGB(40, 42, 50), Enum.Material.Metal)
		Build.part(model, {
			size = Vector3.new(0.6, 14, 0.6),
			cframe = CFrame.new(base + Vector3.new(0, 8, 0)) * cf.Rotation * CFrame.new(-side * 0.8, 0, 0),
			color = color,
			material = Enum.Material.Neon,
			collide = false,
			shadow = false,
			name = "Glow",
		})
	end
	local banner = Build.part(model, {
		size = Vector3.new(width + 6, 2.6, 0.6),
		cframe = cf * CFrame.new(0, 15, 0),
		color = color,
		material = Enum.Material.Neon,
		transparency = 0.35,
		collide = false,
		shadow = false,
		name = "Banner",
	})
	if isFinish then
		Build.text(banner, Enum.NormalId.Front, "FINISH", { color = Color3.fromRGB(20, 20, 24) })
		Build.text(banner, Enum.NormalId.Back, "FINISH", { color = Color3.fromRGB(20, 20, 24) })
	else
		Build.text(banner, Enum.NormalId.Front, tostring(index), { color = Color3.fromRGB(10, 30, 50) })
		Build.text(banner, Enum.NormalId.Back, tostring(index), { color = Color3.fromRGB(10, 30, 50) })
	end
	model:SetAttribute("Track", trackId)
	model:SetAttribute("Index", index)
	model.PrimaryPart = banner
	model.Parent = parent
	Build.tag(model, "CheckpointGate")
	return model
end

local function checkered(parent: Instance, cf: CFrame, width: number)
	local cols = math.floor(width / 3)
	local size = width / cols
	for row = 0, 1 do
		for col = 0, cols - 1 do
			local black = (row + col) % 2 == 0
			Build.part(parent, {
				size = Vector3.new(size, 0.06, size),
				cframe = cf * CFrame.new(-width / 2 + size * (col + 0.5), 0.03, (row - 0.5) * size),
				color = if black then Color3.fromRGB(20, 20, 22) else Color3.fromRGB(245, 245, 245),
				collide = false,
				shadow = false,
				name = "StartLine",
			})
		end
	end
end

local function startPad(parent: Instance, track: Tracks.Track, cf: CFrame)
	local trigger = Build.part(parent, {
		size = Vector3.new(10, 4, 10),
		cframe = cf * CFrame.new(0, 2, 0),
		transparency = 1,
		collide = false,
		name = "RaceStart_" .. track.id,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RacePrompt"
	prompt.ActionText = "Start race"
	prompt.ObjectText = track.name.en
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 26
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("TrackId", track.id)
	prompt:SetAttribute("LocAction", "PromptRace")
	prompt:SetAttribute("LocTrack", track.id)
	prompt.Parent = trigger
	-- painted start box
	for _, x in { -1, 1 } do
		Build.part(parent, {
			size = Vector3.new(0.6, 0.06, 26),
			cframe = cf * CFrame.new(x * 9, 0.04, 0),
			color = Color3.fromRGB(80, 200, 255),
			material = Enum.Material.Neon,
			collide = false,
			shadow = false,
		})
	end
end

local function buildCircuitRoad(parent: Instance, track: Tracks.Track, samples)
	local w = track.width
	local n = #samples
	for i = 1, n do
		local a = samples[i]
		local b = samples[(i % n) + 1]
		local seg = Build.strip(parent, a.pos, b.pos, w, 1, TOP, TRACK_COLOR, Enum.Material.SmoothPlastic, 1.2)
		if seg then
			seg.Name = "Track"
		end
		-- curbs where the track bends
		local nextDir = samples[((i + 1) % n) + 1].dir
		local turn = math.abs(a.dir:Cross(nextDir).Y)
		local right = Vector3.new(-a.dir.Z, 0, a.dir.X)
		if turn > 0.035 then
			local color = if i % 2 == 0 then Color3.fromRGB(220, 30, 30) else Color3.fromRGB(245, 245, 245)
			for _, side in { -1, 1 } do
				local off = right * side * (w / 2 + 1.5)
				Build.strip(parent, a.pos + off, b.pos + off, 3, 0.5, TOP + 0.15, color, Enum.Material.SmoothPlastic, 0.4)
			end
		end
	end
end

-- `buildParts = false` only computes the data (for worlds baked in Studio).
function TrackBuilder.build(root: Instance, trailHeights: { number }?, trailSamples, buildParts: boolean): { [string]: TrackData }
	local folder = Build.folder("Tracks", root)
	local result: { [string]: TrackData } = {}
	for _, track in Tracks.List do
		local tf = Build.folder(track.id, folder)
		local closed = track.kind == "circuit"
		local samples, length
		if track.surface == "dirt" and trailSamples then
			samples = trailSamples
			length = samples[#samples].dist
		else
			samples, length = Spline.sample(track.points, closed, 14)
		end

		local function heightAt(i: number): number
			if track.surface == "dirt" and trailHeights then
				return trailHeights[i] or 0
			end
			return TOP
		end

		if track.surface == "road" and buildParts then
			buildCircuitRoad(tf, track, samples)
		end

		-- checkpoints
		local cps: { Checkpoint } = {}
		local gateWidth = track.width
		if track.checkpointSpacing > 0 then
			local nextDist = track.checkpointSpacing
			local lastIndex = #samples
			for i, s in samples do
				if s.dist >= nextDist and (closed or s.dist < length - track.checkpointSpacing * 0.5) then
					local pos = Vector3.new(s.pos.X, heightAt(i), s.pos.Z)
					table.insert(cps, { cf = CFrame.lookAt(pos, pos + flat(s.dir)), width = gateWidth, index = #cps + 1 })
					nextDist += track.checkpointSpacing
				end
				lastIndex = i
			end
			if closed then
				-- finish = the start line
				local s = samples[1]
				local pos = Vector3.new(s.pos.X, TOP, s.pos.Z)
				table.insert(cps, { cf = CFrame.lookAt(pos, pos + flat(s.dir)), width = gateWidth, index = #cps + 1 })
			else
				local s = samples[lastIndex]
				local prev = samples[math.max(lastIndex - 1, 1)]
				local pos = Vector3.new(s.pos.X, heightAt(lastIndex), s.pos.Z)
				local dir = flat(s.pos - prev.pos)
				table.insert(cps, { cf = CFrame.lookAt(pos, pos + dir), width = gateWidth, index = #cps + 1 })
			end
		else
			for i = 2, #track.points do
				local p = track.points[i]
				local prev = track.points[i - 1]
				local dir = flat(p - prev).Unit
				local pos = Vector3.new(p.X, TOP, p.Z)
				table.insert(cps, { cf = CFrame.lookAt(pos, pos + dir), width = gateWidth, index = #cps + 1 })
			end
		end

		if buildParts then
			for i, cp in cps do
				gate(tf, cp.cf, cp.width, track.id, i, i == #cps)
			end
		end

		-- start position (cars placed here at race start)
		local first = samples[1]
		local startDir = flat(first.dir)
		local startPos = Vector3.new(first.pos.X, heightAt(1), first.pos.Z)
		if closed then
			startPos -= startDir * 24 -- grid slot behind the line
			if buildParts then
				local lineCf = CFrame.lookAt(Vector3.new(first.pos.X, TOP, first.pos.Z), Vector3.new(first.pos.X, TOP, first.pos.Z) + startDir)
				checkered(tf, lineCf, track.width)
			end
		end
		local startCf = CFrame.lookAt(startPos, startPos + startDir)
		if buildParts then
			startPad(tf, track, startCf)
		end

		local laps = if closed then track.laps else 1
		local total = length * laps
		result[track.id] = {
			id = track.id,
			def = track,
			length = total,
			laps = laps,
			start = startCf,
			checkpoints = cps,
			medals = {
				gold = total / track.medalSpeeds.gold,
				silver = total / track.medalSpeeds.silver,
				bronze = total / track.medalSpeeds.bronze,
			},
		}
	end
	return result
end

return TrackBuilder
