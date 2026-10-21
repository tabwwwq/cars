-- Notifications: toasts at the top of the screen and "+$" reward popups.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)

local Kit = require(script.Parent.Parent.UI.Kit)
local T = Kit.Theme

local Notifications = {}

local toastHolder: Frame
local rewardHolder: Frame

local KIND_COLORS = {
	info = T.Accent2,
	success = T.Good,
	warning = T.Warn,
	error = T.Bad,
}

-- Translates arguments that are themselves string keys.
local function localizeArgs(args: { any }?): { any }
	local out = {}
	for i, a in args or {} do
		if typeof(a) == "string" and Strings.Tables.en[a] then
			out[i] = Strings.get(a)
		else
			out[i] = a
		end
	end
	return out
end

function Notifications.show(text: string, kind: string?)
	local color = KIND_COLORS[kind or "info"] or T.Accent2
	local toast = Kit.panel({
		Size = UDim2.new(0, 460, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.05,
		Parent = toastHolder,
	})
	Kit.padding(toast, 14, 10)
	local strip = Kit.new("Frame", {
		Size = UDim2.new(0, 4, 1, 0),
		Position = UDim2.new(0, -10, 0, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = toast,
	})
	Kit.corner(strip, 2)
	local label = Kit.label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextWrapped = true,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = toast,
	})
	label.TextTransparency = 1
	toast.BackgroundTransparency = 1
	Kit.tween(label, 0.2, { TextTransparency = 0 })
	Kit.tween(toast, 0.2, { BackgroundTransparency = 0.05 })
	-- keep at most 4 toasts
	local children = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(children, c)
		end
	end
	if #children > 4 then
		children[1]:Destroy()
	end
	task.delay(3.6, function()
		if toast.Parent then
			Kit.tween(label, 0.3, { TextTransparency = 1 })
			Kit.tween(toast, 0.3, { BackgroundTransparency = 1 })
			local s = toast:FindFirstChildOfClass("UIStroke")
			if s then
				Kit.tween(s, 0.3, { Transparency = 1 })
			end
			strip:Destroy()
			task.wait(0.32)
			toast:Destroy()
		end
	end)
end

function Notifications.notifyKey(key: string, args: { any }?, kind: string?)
	Notifications.show(Strings.get(key, table.unpack(localizeArgs(args))), kind)
end

local REWARD_KEYS = {
	distance = "RewardDistance",
	drift = "RewardDrift",
	air = "RewardAir",
	race = "RewardRace",
}

function Notifications.reward(kind: string, amount: number, detail: any)
	local title
	if kind == "speedtrap" then
		title = Strings.get("RewardSpeedTrap", detail)
	elseif kind == "drift" or kind == "air" then
		title = Strings.get(REWARD_KEYS[kind]) .. " " .. tostring(detail) .. "s"
	else
		title = Strings.get(REWARD_KEYS[kind] or "Cash")
	end
	local big = kind ~= "distance"
	local label = Kit.label({
		Size = UDim2.new(1, 0, 0, if big then 30 else 22),
		Text = string.format("+%s  %s", Format.money(amount), title),
		TextColor3 = if big then T.Gold else T.Good,
		Font = T.FontBlack,
		TextSize = if big then 24 else 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
		Parent = rewardHolder,
	})
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	Kit.tween(label, 0.15, { TextTransparency = 0, TextStrokeTransparency = 0.5 })
	task.delay(if big then 2.6 else 1.6, function()
		Kit.tween(label, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.45)
		label:Destroy()
	end)
end

function Notifications.init()
	local gui = Kit.screen("CarsNotifications", 20)
	toastHolder = Kit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.new(0, 460, 0, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.list(toastHolder, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	rewardHolder = Kit.new("Frame", {
		Name = "Rewards",
		Position = UDim2.new(0, 24, 0, 86),
		Size = UDim2.new(0, 360, 0, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.list(rewardHolder, Enum.FillDirection.Vertical, 2)
end

function Notifications.start()
	Net.on("Notify", function(key, args, kind)
		if typeof(key) == "string" then
			Notifications.notifyKey(key, args, kind)
		end
	end)
	Net.on("Reward", function(kind, amount, detail)
		if typeof(kind) == "string" and typeof(amount) == "number" then
			Notifications.reward(kind, amount, detail)
		end
	end)
end

return Notifications
