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
	local back = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.Bg,
		BorderSizePixel = 0,
		Parent = gui,
	})
	Kit.gradient(back, Color3.fromRGB(40, 46, 70), Color3.fromRGB(10, 12, 20), 90)
	Kit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(0, 600, 0, 120),
		Text = "CARS",
		Font = T.FontBlack,
		TextSize = 120,
		TextColor3 = T.Accent,
		Parent = back,
	})
	Kit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(0, 700, 0, 30),
		Text = Strings.get("Loading"),
		TextSize = 22,
		TextColor3 = T.Muted,
		Parent = back,
	})
	spinner = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.new(0, 46, 0, 46),
		Rotation = 0,
		BackgroundColor3 = T.Accent,
		BorderSizePixel = 0,
		Parent = back,
	})
	Kit.corner(spinner, 10)
end

function Loading.start()
	local player = Players.LocalPlayer
	local started = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		spinner.Rotation += dt * 220
		local ready = player.Character ~= nil and ClientState.profile ~= nil
		if ready or os.clock() - started > 45 then
			conn:Disconnect()
			local back = gui:FindFirstChildOfClass("Frame")
			if back then
				Kit.tween(back, 0.5, { BackgroundTransparency = 1 })
				for _, d in back:GetDescendants() do
					if d:IsA("TextLabel") then
						Kit.tween(d, 0.4, { TextTransparency = 1 })
					elseif d:IsA("Frame") then
						Kit.tween(d, 0.4, { BackgroundTransparency = 1 })
					end
				end
			end
			task.delay(0.6, function()
				gui:Destroy()
			end)
		end
	end)
end

return Loading
