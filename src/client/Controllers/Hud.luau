-- Hud: cash, garage/daily buttons, the speedometer with gear/RPM/nitro, live
-- drift and air meters, the controls hint and the Studio test panel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)

local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local T = Kit.Theme

local Hud = {}
Hud.GarageRequested = Signal.new()

local gui: ScreenGui
local cashLabel: TextLabel
local displayedCash = 0
local targetCash = 0
local dailyButton: TextButton
local dailyDot: Frame
local speedo: Frame
local speedLabel: TextLabel
local gearLabel: TextLabel
local rpmCells: { Frame } = {}
local nitroFill: Frame
local nitroLabel: TextLabel
local meter: TextLabel
local hint: TextLabel

local RPM_CELLS = 20

local function buildTopLeft()
	local cash = Kit.panel({
		Name = "Cash",
		Position = UDim2.new(0, 20, 0, 18),
		Size = UDim2.new(0, 230, 0, 54),
		Parent = gui,
	})
	Kit.gradient(cash, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 205, 220), 90)
	local icon = Kit.new("Frame", {
		Size = UDim2.new(0, 38, 0, 38),
		Position = UDim2.new(0, 8, 0.5, -19),
		BackgroundColor3 = T.Good,
		BorderSizePixel = 0,
		Parent = cash,
	})
	Kit.corner(icon, 19)
	Kit.label({ Size = UDim2.fromScale(1, 1), Text = "$", Font = T.FontBlack, TextSize = 26, Parent = icon })
	cashLabel = Kit.label({
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.new(0, 54, 0, 0),
		Text = "$0",
		Font = T.FontBlack,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = cash,
	})
end

local function buildTopRight()
	local holder = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 18),
		Size = UDim2.new(0, 520, 0, 54),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local layout = Kit.list(holder, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	local garage = Kit.button({
		Name = "GarageButton",
		Size = UDim2.new(0, 170, 0, 50),
		Text = Strings.get("Garage") .. "  [G]",
		LayoutOrder = 3,
		onClick = function()
			Hud.GarageRequested:Fire()
		end,
		Parent = holder,
	})
	Kit.stroke(garage, Color3.new(1, 1, 1), 2, 0.7)

	dailyButton = Kit.button({
		Name = "DailyButton",
		Size = UDim2.new(0, 150, 0, 50),
		Text = Strings.get("Daily"),
		BackgroundColor3 = T.PanelAlt,
		LayoutOrder = 2,
		onClick = function()
			local r = Net.request("ClaimDaily")
			if r.message then
				require(script.Parent.Notifications).notifyKey(r.message, r.args, if r.ok then "success" else "info")
			end
		end,
		Parent = holder,
	})
	dailyDot = Kit.new("Frame", {
		Size = UDim2.new(0, 14, 0, 14),
		Position = UDim2.new(1, -10, 0, -4),
		BackgroundColor3 = T.Bad,
		BorderSizePixel = 0,
		Visible = false,
		Parent = dailyButton,
	})
	Kit.corner(dailyDot, 7)

	local function addDevButton()
		if holder:FindFirstChild("DevCash") or not Players.LocalPlayer:GetAttribute("IsDev") then
			return
		end
		local dev = Kit.button({
			Name = "DevCash",
			Size = UDim2.new(0, 120, 0, 40),
			Text = Strings.get("DevCash"),
			TextSize = 15,
			BackgroundColor3 = Color3.fromRGB(110, 60, 200),
			LayoutOrder = 1,
			onClick = function()
				Net.request("DevCash")
			end,
			Parent = holder,
		})
		dev:SetAttribute("Dev", true)
	end
	addDevButton()
	Players.LocalPlayer:GetAttributeChangedSignal("IsDev"):Connect(addDevButton)
end

local function buildSpeedo()
	speedo = Kit.panel({
		Name = "Speedometer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(0, 380, 0, 128),
		Visible = false,
		Parent = gui,
	})
	speedLabel = Kit.label({
		Position = UDim2.new(0, 18, 0, 6),
		Size = UDim2.new(0, 170, 0, 70),
		Text = "0",
		Font = T.FontBlack,
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = speedo,
	})
	Kit.label({
		Position = UDim2.new(0, 20, 0, 70),
		Size = UDim2.new(0, 120, 0, 20),
		Text = Strings.get("SpeedUnit"),
		TextColor3 = T.Muted,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = speedo,
	})
	local gearBox = Kit.new("Frame", {
		Position = UDim2.new(0, 186, 0, 14),
		Size = UDim2.new(0, 56, 0, 56),
		BackgroundColor3 = T.PanelAlt,
		BorderSizePixel = 0,
		Parent = speedo,
	})
	Kit.corner(gearBox, 10)
	Kit.stroke(gearBox, T.Accent, 2, 0.3)
	gearLabel = Kit.label({ Size = UDim2.fromScale(1, 1), Text = "1", Font = T.FontBlack, TextSize = 34, Parent = gearBox })

	-- RPM cells
	local rpm = Kit.new("Frame", {
		Position = UDim2.new(0, 256, 0, 14),
		Size = UDim2.new(0, 108, 0, 56),
		BackgroundTransparency = 1,
		Parent = speedo,
	})
	Kit.list(rpm, Enum.FillDirection.Horizontal, 1, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)
	for i = 1, RPM_CELLS do
		local cell = Kit.new("Frame", {
			Size = UDim2.new(0, 4.3, 0, 16 + i * 2),
			BackgroundColor3 = if i > 16 then T.Bad elseif i > 12 then T.Warn else T.Accent2,
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = rpm,
		})
		table.insert(rpmCells, cell)
	end

	-- nitro bar
	local nitroBack = Kit.new("Frame", {
		Position = UDim2.new(0, 18, 1, -28),
		Size = UDim2.new(1, -36, 0, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = speedo,
	})
	Kit.corner(nitroBack, 7)
	nitroFill = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.Accent2,
		BorderSizePixel = 0,
		Parent = nitroBack,
	})
	Kit.corner(nitroFill, 7)
	Kit.gradient(nitroFill, Color3.fromRGB(70, 196, 255), Color3.fromRGB(170, 90, 255), 0)
	nitroLabel = Kit.label({
		Position = UDim2.new(0, 0, 0, -18),
		Size = UDim2.new(1, 0, 0, 16),
		Text = Strings.get("Nitro"),
		TextColor3 = T.Muted,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = nitroBack,
	})

	meter = Kit.label({
		Name = "Meter",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -160),
		Size = UDim2.new(0, 400, 0, 44),
		Text = "",
		Font = T.FontBlack,
		TextSize = 34,
		TextColor3 = T.Gold,
		TextStrokeTransparency = 0.4,
		Visible = false,
		Parent = gui,
	})
end

local function buildHint()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local text = if touch
		then Strings.get("ControlsBodyTouch")
		elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then Strings.get("ControlsBodyGamepad")
		else Strings.get("ControlsBody")
	hint = Kit.label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -20),
		Size = UDim2.new(0, 520, 0, 50),
		Text = text,
		TextWrapped = true,
		TextSize = 14,
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextStrokeTransparency = 0.6,
		Visible = false,
		Parent = gui,
	})
end

local function updateDaily(profile)
	if not profile or not dailyButton then
		return
	end
	local today = math.floor((profile.serverTime or os.time()) / 86400)
	local last = math.floor((profile.daily and profile.daily.last or 0) / 86400)
	local ready = profile.daily == nil or profile.daily.last == 0 or today > last
	dailyDot.Visible = ready
	dailyButton.Text = if ready then Strings.get("DailyReady") else Strings.get("Daily")
	Kit.setButtonColor(dailyButton, if ready then T.Good else T.PanelAlt)
end

function Hud.init()
	gui = Kit.screen("CarsHud", 5)
	buildTopLeft()
	buildTopRight()
	buildSpeedo()
	buildHint()
end

function Hud.start()
	ClientState.ProfileChanged:Connect(function(p)
		targetCash = p.cash
		updateDaily(p)
	end)
	if ClientState.profile then
		targetCash = ClientState.profile.cash
		updateDaily(ClientState.profile)
	end
	ClientState.DrivingChanged:Connect(function(driving)
		speedo.Visible = driving
		hint.Visible = driving
		if driving then
			hint.TextTransparency = 0
			task.delay(12, function()
				if hint.Visible then
					Kit.tween(hint, 1, { TextTransparency = 1 })
				end
			end)
		end
	end)

	local lit = -1
	RunService.RenderStepped:Connect(function(dt)
		-- cash count-up
		if displayedCash ~= targetCash then
			local diff = targetCash - displayedCash
			local step = math.max(1, math.abs(diff) * math.min(1, dt * 8))
			if math.abs(diff) <= step then
				displayedCash = targetCash
			else
				displayedCash += math.sign(diff) * step
			end
			cashLabel.Text = Format.money(displayedCash)
		end
		local tel = ClientState.telemetry
		if not ClientState.driving or not tel then
			meter.Visible = false
			return
		end
		speedLabel.Text = tostring(Format.speed(tel.speed))
		gearLabel.Text = if tel.gear == 0 then Strings.get("GearReverse") else tostring(tel.gear)
		local cells = math.floor(tel.rpm * RPM_CELLS + 0.5)
		if cells ~= lit then
			lit = cells
			for i, cell in rpmCells do
				cell.BackgroundTransparency = if i <= cells then 0 else 0.82
			end
		end
		nitroFill.Size = UDim2.fromScale(math.clamp(tel.nitro, 0, 1), 1)
		nitroLabel.TextColor3 = if tel.nitroActive then T.Accent2 else T.Muted
		if tel.drifting then
			meter.Visible = true
			meter.Text = Strings.get("DriftScore", math.floor(tel.driftAngle))
			meter.TextColor3 = T.Gold
		elseif tel.airborne and tel.airTime > 0.4 then
			meter.Visible = true
			meter.Text = Strings.get("AirScore", string.format("%.1f", tel.airTime))
			meter.TextColor3 = T.Accent2
		else
			meter.Visible = false
		end
	end)

end

return Hud
