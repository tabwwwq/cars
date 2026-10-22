-- Loading: a splash screen shown until the world is built, the save is loaded
-- and the character has spawned.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Strings = require(Shared.Strings)

local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local T = Kit.Theme

local Loading = {}

local gui: ScreenGui
local spinner: Frame

function Loading.init()
	gui = Kit.screen("CarsLoading", 100)
	-- one CanvasGroup so the whole splash fades out together
	local back = Kit.new("CanvasGroup", {
		Name = "Splash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = gui,
	})
	Kit.gradient(back, Color3.fromRGB(70, 110, 230), Color3.fromRGB(20, 26, 70), 90)
	-- logo: chunky orange letters with a thick outline on a tilted ribbon
	local ribbon = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(0, 620, 0, 170),
		Rotation = -3,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = back,
	})
	Kit.corner(ribbon, 34)
	Kit.stroke(ribbon, T.Ink, 6, 0)
	Kit.gradient(ribbon, Color3.fromRGB(255, 200, 80), T.Accent, 90)
	Kit.label({
		Size = UDim2.fromScale(1, 1),
		Text = "CARS",
		Font = Enum.Font.FredokaOne,
		TextSize = 140,
		outline = 6,
		Parent = ribbon,
	})
	Kit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.new(0, 700, 0, 40),
		Text = "🚗  🔧  🏁",
		TextSize = 34,
		Parent = back,
	})
	Kit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.65),
		Size = UDim2.new(0, 800, 0, 34),
		Text = Strings.get("Loading"),
		TextSize = 26,
		outline = 2.5,
		Parent = back,
	})
	local barBack = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.new(0, 460, 0, 28),
		BackgroundColor3 = Color3.fromRGB(14, 20, 50),
		BorderSizePixel = 0,
		Parent = back,
	})
	Kit.corner(barBack, 14)
	Kit.stroke(barBack, T.Ink, 4, 0)
	spinner = Kit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.05, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = barBack,
	})
	Kit.corner(spinner, 14)
	Kit.gradient(spinner, Color3.fromRGB(140, 255, 150), T.Good, 90)
end

function Loading.start()
	local player = Players.LocalPlayer
	local started = os.clock()
	local progress = 0.05
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		-- creeps towards 90% while we wait, jumps to 100% when ready
		progress += (0.9 - progress) * math.min(1, dt * 0.8)
		spinner.Size = UDim2.fromScale(progress, 1)
		local ready = player.Character ~= nil and ClientState.profile ~= nil
		if ready or os.clock() - started > 45 then
			conn:Disconnect()
			spinner.Size = UDim2.fromScale(1, 1)
			local back = gui:FindFirstChild("Splash") :: CanvasGroup?
			if back then
				Kit.tween(back, 0.5, { GroupTransparency = 1 })
			end
			task.delay(0.6, function()
				gui:Destroy()
			end)
		end
	end)
end

return Loading
