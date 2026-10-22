-- RaceUI: countdown, race timer, lap/checkpoint counters, the guide arrow to
-- the next checkpoint, gate highlighting and the results screen.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)
local Tracks = require(Shared.Tracks)

local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local Notifications = require(script.Parent.Notifications)
local T = Kit.Theme

local RaceUI = {}

local gui: ScreenGui
local panel: Frame
local trackLabel: TextLabel
local timerLabel: TextLabel
local progressLabel: TextLabel
local bestLabel: TextLabel
local medalsLabel: TextLabel
local countdownLabel: TextLabel
local results: Frame

type RaceInfo = {
	trackId: string,
	goAt: number,
	checkpoints: { { cf: CFrame, width: number } },
	laps: number,
	medals: { gold: number, silver: number, bronze: number },
	best: number?,
	nextIndex: number,
	lap: number,
	running: boolean,
}

local race: RaceInfo? = nil
local arrow: Model? = nil
local highlighted: Model? = nil
local highlight: Highlight? = nil
local lastFinished: string? = nil

local MEDAL_COLORS = { Gold = T.Gold, Silver = T.Silver, Bronze = T.Bronze }

local function trackName(id: string): string
	local t = Tracks.get(id)
	return if t then Strings.pick(t.name) else id
end

local function findGate(trackId: string, index: number): Model?
	for _, g in CollectionService:GetTagged("CheckpointGate") do
		if g:GetAttribute("Track") == trackId and g:GetAttribute("Index") == index then
			return g :: Model
		end
	end
	return nil
end

local function setTarget()
	local r = race
	local cp = r and r.checkpoints[r.nextIndex]
	ClientState.raceTarget = if cp then cp.cf.Position else nil
end

local function clearHighlight()
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	if highlighted then
		local banner = highlighted:FindFirstChild("Banner") :: BasePart?
		if banner then
			banner.Transparency = 0.35
		end
	end
	highlighted = nil
end

local function highlightGate()
	clearHighlight()
	local r = race
	if not r then
		return
	end
	local gate = findGate(r.trackId, r.nextIndex)
	if not gate then
		return
	end
	highlighted = gate
	local banner = gate:FindFirstChild("Banner") :: BasePart?
	if banner then
		banner.Transparency = 0
	end
	local h = Instance.new("Highlight")
	h.FillColor = T.Gold
	h.FillTransparency = 0.5
	h.OutlineColor = Color3.new(1, 1, 1)
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = gate
	h.Parent = gate
	highlight = h
end

local function makeArrow(): Model
	local model = Instance.new("Model")
	model.Name = "RaceArrow"
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Size = Vector3.new(1.4, 0.6, 4)
	shaft.Color = T.Gold
	shaft.Material = Enum.Material.Neon
	shaft.Anchored = true
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.CastShadow = false
	shaft.Parent = model
	for _, name in { "HeadL", "HeadR" } do
		local head = Instance.new("Part")
		head.Name = name
		head.Size = Vector3.new(1.2, 0.6, 3.6)
		head.Color = T.Gold
		head.Material = Enum.Material.Neon
		head.Anchored = true
		head.CanCollide = false
		head.CanQuery = false
		head.CanTouch = false
		head.CastShadow = false
		head.Parent = model
	end
	model.PrimaryPart = shaft
	model.Parent = Workspace
	return model
end

local function updateTexts()
	local r = race
	if not r then
		return
	end
	trackLabel.Text = trackName(r.trackId)
	local cps = #r.checkpoints
	local parts = {}
	if r.laps > 1 then
		table.insert(parts, Strings.get("RaceLap", r.lap, r.laps))
	end
	table.insert(parts, Strings.get("RaceCheckpoint", math.min(r.nextIndex, cps), cps))
	progressLabel.Text = table.concat(parts, "   ")
	bestLabel.Text = Strings.get("RaceBest") .. ": " .. (if r.best then Format.time(r.best) else "--:--.--")
	medalsLabel.Text = Strings.get("MedalTargets", Format.time(r.medals.gold), Format.time(r.medals.silver), Format.time(r.medals.bronze))
end

local function stopRace()
	race = nil
	ClientState.racing = false
	ClientState.raceTarget = nil
	panel.Visible = false
	countdownLabel.Visible = false
	clearHighlight()
	if arrow then
		arrow:Destroy()
		arrow = nil
	end
end

local function showResults(payload)
	for _, c in results:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local medal = payload.medal
	Kit.label({ Size = UDim2.new(1, 0, 0, 30), Text = "🏁 " .. trackName(payload.trackId), TextSize = 24, TextColor3 = T.Muted, outline = 2, LayoutOrder = 1, Parent = results })
	Kit.label({ Size = UDim2.new(1, 0, 0, 68), Text = Format.time(payload.time), Font = T.FontBlack, TextSize = 64, outline = 3.5, LayoutOrder = 2, Parent = results })
	Kit.label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = if medal then "★ " .. Strings.get("Medal" .. medal) .. " ★" else Strings.get("MedalNone"),
		Font = T.FontBlack,
		TextSize = 34,
		TextColor3 = if medal then MEDAL_COLORS[medal] else T.Muted,
		outline = 3,
		LayoutOrder = 3,
		Parent = results,
	})
	if payload.newRecord then
		Kit.pill(results, "🏆 " .. Strings.get("RaceNewRecord"), T.Good, 4).TextSize = 20
	end
	Kit.label({
		Size = UDim2.new(1, 0, 0, 32),
		Text = "💰 " .. Strings.get("RaceReward", Format.money(payload.reward or 0)),
		TextSize = 26,
		TextColor3 = T.Gold,
		outline = 2.5,
		LayoutOrder = 5,
		Parent = results,
	})
	local row = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, LayoutOrder = 6, Parent = results })
	Kit.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	Kit.button({
		Size = UDim2.new(0, 190, 1, -6),
		Text = "▶ " .. Strings.get("RaceStart"),
		TextSize = 22,
		BackgroundColor3 = T.Good,
		onClick = function()
			results.Visible = false
			local trackId = lastFinished
			if trackId then
				local r = Net.request("StartRace", trackId)
				if r.message then
					Notifications.notifyKey(r.message, r.args, "warning")
				end
			end
		end,
		Parent = row,
	})
	Kit.button({
		Size = UDim2.new(0, 150, 1, -6),
		Text = Strings.get("Close"),
		TextSize = 22,
		BackgroundColor3 = T.Bad,
		onClick = function()
			results.Visible = false
		end,
		Parent = row,
	})
	results.Visible = true
	results.Size = UDim2.new(0, 400, 0, 0)
	Kit.tween(results, 0.25, { Size = UDim2.new(0, 460, 0, 0) }, Enum.EasingStyle.Back)
	task.delay(12, function()
		if results.Visible and lastFinished == payload.trackId then
			results.Visible = false
		end
	end)
end

local function onState(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local phase = payload.phase
	if phase == "countdown" then
		results.Visible = false
		race = {
			trackId = payload.trackId,
			goAt = payload.goAt,
			checkpoints = payload.checkpoints or {},
			laps = payload.laps or 1,
			medals = payload.medals,
			best = payload.best,
			nextIndex = 1,
			lap = 1,
			running = false,
		}
		ClientState.racing = true
		panel.Visible = true
		countdownLabel.Visible = true
		if not arrow then
			arrow = makeArrow()
		end
		updateTexts()
		highlightGate()
		setTarget()
	elseif phase == "racing" and race then
		race.running = true
		race.nextIndex = payload.nextIndex or race.nextIndex
		race.lap = payload.lap or race.lap
		updateTexts()
		highlightGate()
		setTarget()
	elseif phase == "finished" then
		lastFinished = payload.trackId
		stopRace()
		showResults(payload)
	elseif phase == "cancelled" then
		stopRace()
		Notifications.notifyKey(payload.reason or "RaceCancelled", {}, "warning")
	end
end

local function build()
	gui = Kit.screen("CarsRace", 8)
	panel = Kit.panel({
		Name = "RacePanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.new(0, 420, 0, 150),
		Visible = false,
		Parent = gui,
	})
	Kit.corner(panel, 22)
	trackLabel = Kit.label({ Position = UDim2.new(0, 0, 0, 8), Size = UDim2.new(1, 0, 0, 24), Text = "", TextSize = 20, TextColor3 = T.Accent, outline = 2, Parent = panel })
	timerLabel = Kit.label({ Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 54), Text = "0:00.00", Font = T.FontBlack, TextSize = 52, outline = 3, Parent = panel })
	progressLabel = Kit.label({ Position = UDim2.new(0, 0, 0, 84), Size = UDim2.new(1, 0, 0, 22), Text = "", TextSize = 18, outline = 2, Parent = panel })
	bestLabel = Kit.label({ Position = UDim2.new(0, 0, 0, 106), Size = UDim2.new(1, 0, 0, 18), Text = "", TextSize = 15, Font = T.FontMedium, TextColor3 = T.Muted, Parent = panel })
	medalsLabel = Kit.label({ Position = UDim2.new(0, 0, 0, 124), Size = UDim2.new(1, 0, 0, 18), Text = "", TextSize = 13, Font = T.FontMedium, TextColor3 = T.Muted, Parent = panel })
	Kit.button({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.new(0, 200, 0, 40),
		Text = "🏳 " .. Strings.get("RaceLeave"),
		TextSize = 17,
		BackgroundColor3 = T.Bad,
		onClick = function()
			Net.request("LeaveRace")
		end,
		Parent = panel,
	})
	countdownLabel = Kit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(0, 400, 0, 160),
		Text = "",
		Font = T.FontBlack,
		TextSize = 150,
		TextColor3 = T.Gold,
		outline = 6,
		Visible = false,
		Parent = gui,
	})
	results = Kit.panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0, 460, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = gui,
	})
	Kit.corner(results, 24)
	Kit.padding(results, 20, 18)
	Kit.list(results, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
end

local function frame()
	local r = race
	if not r then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local elapsed = now - r.goAt
	if elapsed < 0 then
		countdownLabel.Visible = true
		countdownLabel.Text = tostring(math.ceil(-elapsed))
		timerLabel.Text = Format.time(0)
	else
		if elapsed < 0.9 then
			countdownLabel.Visible = true
			countdownLabel.Text = Strings.get("RaceGo")
		else
			countdownLabel.Visible = false
		end
		timerLabel.Text = Format.time(elapsed)
	end
	-- guide arrow above the car
	local car = ClientState.car
	local cp = r.checkpoints[r.nextIndex]
	if arrow and car and car.PrimaryPart and cp then
		local chassis = car.PrimaryPart
		local size = car:GetExtentsSize()
		local base = chassis.Position + Vector3.new(0, size.Y + 3, 0)
		local target = cp.cf.Position
		local dir = Vector3.new(target.X - base.X, 0, target.Z - base.Z)
		if dir.Magnitude > 1 then
			local cf = CFrame.lookAt(base, base + dir)
			local shaft = arrow:FindFirstChild("Shaft") :: BasePart
			shaft.CFrame = cf * CFrame.new(0, 0, 1)
			-- chevron tip: two bars from the tip back to each side
			for side, name in { [-1] = "HeadL", [1] = "HeadR" } do
				local bar = arrow:FindFirstChild(name) :: BasePart
				local tip = Vector3.new(0, 0, -2.6)
				local back = Vector3.new(side * 2.2, 0, -0.2)
				local mid = (tip + back) / 2
				bar.CFrame = cf * CFrame.lookAt(mid, tip)
			end
		end
	end
end

function RaceUI.init()
	build()
end

function RaceUI.start()
	Net.on("RaceState", onState)
	RunService.RenderStepped:Connect(frame)
end

return RaceUI
