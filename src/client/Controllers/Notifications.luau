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
local KIND_ICONS = {
	info = "💬",
	success = "✅",
	warning = "⚠️",
	error = "⛔",
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
	local k = kind or "info"
	local color = KIND_COLORS[k] or T.Accent2
	local toast = Kit.panel({
		Size = UDim2.new(0, 500, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = toastHolder,
	})
	Kit.corner(toast, 20)
	Kit.padding(toast, 12, 10)
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(500, 64), Parent = toast })
	Kit.iconTile(toast, KIND_ICONS[k] or "💬", color, 46, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) })
	Kit.label({
		Position = UDim2.fromOffset(58, 0),
		Size = UDim2.new(1, -58, 0, 44),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextWrapped = true,
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 2,
		Parent = toast,
	})
	local scale = Kit.new("UIScale", { Scale = 0.6, Parent = toast })
	Kit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
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
			Kit.tween(scale, 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.wait(0.22)
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
	service = "RewardService",
	serviceWorker = "RewardServiceWorker",
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
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, if big then 40 else 30),
		BackgroundTransparency = 1,
		Parent = rewardHolder,
	})
	Kit.coin(row, if big then 34 else 24, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) })
	Kit.label({
		Position = UDim2.fromOffset(if big then 42 else 32, 0),
		Size = UDim2.new(1, -42, 1, 0),
		Text = string.format("+%s  %s", Format.money(amount), title),
		TextColor3 = if big then T.Gold else Color3.fromRGB(150, 255, 150),
		TextSize = if big then 30 else 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.None,
		outline = 2.5,
		Parent = row,
	})
	local scale = Kit.new("UIScale", { Scale = 0.4, Parent = row })
	Kit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(if big then 2.6 else 1.6, function()
		Kit.tween(scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.27)
		row:Destroy()
	end)
end

function Notifications.init()
	local gui = Kit.screen("CarsNotifications", 20)
	toastHolder = Kit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104), -- below the hint card
		Size = UDim2.new(0, 500, 0, 320),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.list(toastHolder, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	rewardHolder = Kit.new("Frame", {
		Name = "Rewards",
		Position = UDim2.new(0, 216, 0, 300), -- right of the rail, under the toasts
		Size = UDim2.new(0, 460, 0, 260),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.list(rewardHolder, Enum.FillDirection.Vertical, 4)
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
