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
local Rail = require(script.Parent.Parent.UI.Rail)
local T = Kit.Theme

local Hud = {}
Hud.GarageRequested = Signal.new()

local gui: ScreenGui
local cashLabel: TextLabel
local displayedCash = 0
local targetCash = 0
local daily: Kit.BigButton
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
	-- cash: a deep-blue pill with a drawn coin hanging over its left edge
	local cash = Kit.panel({
		Name = "Cash",
		Position = UDim2.new(0, 34, 0, 18),
		Size = UDim2.new(0, 236, 0, 52),
		Parent = gui,
	})
	Kit.corner(cash, 26)
	Kit.coin(cash, 62, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 2, 0.5, 0) })
	cashLabel = Kit.label({
		Position = UDim2.new(0, 40, 0, 0),
		Size = UDim2.new(1, -50, 1, 0),
		Text = "$0",
		Font = T.FontBlack,
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 2.5,
		Parent = cash,
	})
end

local function buildTopRight()
	-- garage and daily live in the shared rail of big tiles
	Rail.add({
		name = "Garage",
		icon = "🚗",
		caption = Strings.get("Garage"),
		color = Color3.fromRGB(240, 70, 120),
		layoutOrder = 5,
		onClick = function()
			Hud.GarageRequested:Fire()
		end,
	})
	daily = Rail.add({
		name = "Daily",
		icon = "🎁",
		caption = Strings.get("Daily"),
		color = Color3.fromRGB(255, 176, 30),
		layoutOrder = 6,
		onClick = function()
			local r = Net.request("ClaimDaily")
			if r.message then
				require(script.Parent.Notifications).notifyKey(r.message, r.args, if r.ok then "success" else "info")
			end
		end,
	})

	local holder = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 18),
		Size = UDim2.new(0, 300, 0, 50),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local layout = Kit.list(holder, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local function addDevButton()
		if holder:FindFirstChild("DevCash") or not Players.LocalPlayer:GetAttribute("IsDev") then
			return
		end
		local dev = Kit.button({
			Name = "DevCash",
			Size = UDim2.new(0, 130, 0, 42),
			Text = Strings.get("DevCash"),
			TextSize = 18,
			BackgroundColor3 = T.Purple,
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
		Size = UDim2.new(0, 400, 0, 136),
		Visible = false,
		Parent = gui,
	})
	Kit.corner(speedo, 24)
	speedLabel = Kit.label({
		Position = UDim2.new(0, 22, 0, 2),
		Size = UDim2.new(0, 170, 0, 70),
		Text = "0",
		Font = T.FontBlack,
		TextSize = 66,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 3,
		Parent = speedo,
	})
	Kit.label({
		Position = UDim2.new(0, 24, 0, 66),
		Size = UDim2.new(0, 120, 0, 18),
		Text = Strings.get("SpeedUnit"),
		TextColor3 = T.Muted,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 1.5,
		Parent = speedo,
	})
	local gearBox = Kit.new("Frame", {
		Position = UDim2.new(0, 186, 0, 16),
		Size = UDim2.new(0, 58, 0, 58),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = speedo,
	})
	Kit.corner(gearBox, 16)
	Kit.stroke(gearBox, T.Ink, 3, 0)
	Kit.gradient(gearBox, Color3.fromRGB(255, 190, 80), T.Accent, 90)
	gearLabel = Kit.label({ Size = UDim2.fromScale(1, 1), Text = "1", Font = T.FontBlack, TextSize = 38, outline = 2.5, Parent = gearBox })

	-- RPM cells
	local rpm = Kit.new("Frame", {
		Position = UDim2.new(0, 258, 0, 16),
		Size = UDim2.new(0, 124, 0, 58),
		BackgroundTransparency = 1,
		Parent = speedo,
	})
	Kit.list(rpm, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)
	for i = 1, RPM_CELLS do
		local cell = Kit.new("Frame", {
			Size = UDim2.new(0, 4.3, 0, 16 + i * 2),
			BackgroundColor3 = if i > 16 then T.Bad elseif i > 12 then T.Warn else T.Accent2,
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = rpm,
		})
		Kit.corner(cell, 2)
		table.insert(rpmCells, cell)
	end

	-- nitro bar
	local nitroBack = Kit.new("Frame", {
		Position = UDim2.new(0, 22, 1, -28),
		Size = UDim2.new(1, -44, 0, 16),
		BackgroundColor3 = Color3.fromRGB(16, 24, 50),
		BorderSizePixel = 0,
		Parent = speedo,
	})
	Kit.corner(nitroBack, 8)
	Kit.stroke(nitroBack, T.Ink, 2.5, 0)
	nitroFill = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = nitroBack,
	})
	Kit.corner(nitroFill, 8)
	Kit.gradient(nitroFill, Color3.fromRGB(70, 210, 255), Color3.fromRGB(170, 90, 255), 0)
	nitroLabel = Kit.label({
		Position = UDim2.new(0, 2, 0, -20),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "🔥 " .. Strings.get("Nitro"),
		TextColor3 = T.Muted,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 1.5,
		Parent = nitroBack,
	})

	meter = Kit.label({
		Name = "Meter",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -170),
		Size = UDim2.new(0, 460, 0, 56),
		Text = "",
		Font = T.FontBlack,
		TextSize = 44,
		TextColor3 = T.Gold,
		outline = 3,
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
		TextSize = 15,
		Font = T.FontMedium,
		TextColor3 = T.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		outline = 1.5,
		Visible = false,
		Parent = gui,
	})
end

local function updateDaily(profile)
	if not profile or not daily then
		return
	end
	local today = math.floor((profile.serverTime or os.time()) / 86400)
	local last = math.floor((profile.daily and profile.daily.last or 0) / 86400)
	local ready = profile.daily == nil or profile.daily.last == 0 or today > last
	daily.setBadge(if ready then 1 else nil)
	daily.setPulse(ready)
	daily.caption.Text = if ready then Strings.get("DailyReady") else Strings.get("Daily")
	daily.setColor(if ready then Color3.fromRGB(255, 176, 30) else T.Disabled)
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
				cell.BackgroundTransparency = if i <= cells then 0 else 0.8
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
