-- Service: the car-service screens. A rail of big drawn buttons on the left
-- (my service, orders, work, business), the orders window with 3D previews of
-- the waiting vehicles, the business window (upgrades and staff), the result
-- card with stars after an order, the level-up card, first-time hints and the
-- world prompts on the player's own plot.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local CarBuilder = require(Shared.CarBuilder)
local CarCatalog = require(Shared.CarCatalog)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Paints = require(Shared.Paints)
local ServiceConfig = require(Shared.ServiceConfig)
local ServiceModels = require(Shared.ServiceModels)
local Strings = require(Shared.Strings)

local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local Rail = require(script.Parent.Parent.UI.Rail)
local Notifications = require(script.Parent.Notifications)
local Workshop = require(script.Parent.Workshop)
local T = Kit.Theme

local Service = {}

local gui: ScreenGui
local buttons: { [string]: Kit.BigButton } = {}
local levelBadge: TextLabel
local xpFill: Frame
local xpText: TextLabel
local hint: Frame
local hintLabel: TextLabel

local ordersWindow: Frame
local ordersList: ScrollingFrame
local ordersInfo: TextLabel
local setOrdersOpen: (boolean) -> ()
local ordersOpen = false

local businessWindow: Frame
local businessBody: ScrollingFrame
local setBusinessOpen: (boolean) -> ()
local businessOpen = false

local resultWindow: Frame
local setResultOpen: (boolean) -> ()
local levelWindow: Frame
local setLevelOpen: (boolean) -> ()

local previews: { [number]: ViewportFrame } = {}
local lastResult = 0
-- labels and bars in the open orders window that change every second
local live: { { job: any, fill: Frame?, label: TextLabel? } } = {}
local prompts: { [Instance]: ProximityPrompt } = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function svcProfile(): any
	local p = ClientState.profile
	return p and p.service
end

local function jobs(): { any }
	local s = ClientState.service
	return if s then s.jobs else {}
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function myJob(): any
	-- the order the player took (closest to being workable first)
	local best = nil
	for _, job in jobs() do
		if job.assignee == "player" and job.state ~= "leaving" then
			if not best or (job.state == "inBay" and best.state ~= "inBay") then
				best = job
			end
		end
	end
	return best
end

local function waitingJobs(): { any }
	local out = {}
	for _, job in jobs() do
		if job.state == "waiting" and job.assignee == nil then
			table.insert(out, job)
		end
	end
	return out
end

local function serviceNames(job: any): string
	local names = {}
	for _, id in job.services do
		table.insert(names, Strings.get("Service_" .. id))
	end
	return table.concat(names, " + ")
end

local function request(action: string, ...: any): Net.Result
	local r = Net.request(action, ...)
	if r.message then
		Notifications.notifyKey(r.message, r.args, if r.ok then "success" else "warning")
	end
	return r
end

--------------------------------------------------------------------------------
-- Vehicle previews
--------------------------------------------------------------------------------

local function buildPreview(job: any): Model?
	if job.source == "model" then
		return ServiceModels.build(job.vehicle, { paint = job.paint })
	end
	local def = CarCatalog.get(job.vehicle)
	if not def then
		return nil
	end
	local save = CarCatalog.defaultSave(def)
	save.paint = job.paint
	return CarBuilder.build(def, { preview = true, save = save })
end

local function previewFor(job: any, parent: Instance): ViewportFrame
	local existing = previews[job.id]
	if existing then
		existing.Parent = parent
		return existing
	end
	local vp = Kit.new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -2, -1),
		Parent = parent,
	})
	local model = buildPreview(job)
	if model then
		model.Parent = vp
		local _, size = model:GetBoundingBox()
		local extent = math.max(size.X, size.Y * 1.4, size.Z)
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		local center = Vector3.new(0, size.Y * 0.42, 0)
		local eye = center + Vector3.new(-0.75, 0.42, -0.85).Unit * (extent * 2.1 + 2)
		cam.CFrame = CFrame.lookAt(eye, center)
		cam.Parent = vp
		vp.CurrentCamera = cam
	end
	previews[job.id] = vp
	return vp
end

local function dropPreviews()
	local alive = {}
	for _, job in jobs() do
		alive[job.id] = true
	end
	for id, vp in previews do
		if not alive[id] then
			vp:Destroy()
			previews[id] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Orders window
--------------------------------------------------------------------------------

local function stateText(job: any): (string, Color3)
	if job.state == "arriving" then
		return Strings.get("ServiceStateArriving"), T.Muted
	elseif job.state == "toBay" then
		return Strings.get("ServiceStateToBay"), T.Accent2
	elseif job.state == "leaving" then
		return Strings.get("ServiceStateDone"), T.Good
	elseif job.assignee == "worker" then
		local pct = 0
		if job.workerStart and job.workerDuration then
			pct = math.clamp((serverNow() - job.workerStart) / job.workerDuration, 0, 1)
		end
		return Strings.get("ServiceStateWorker", math.floor(pct * 100)), T.Warn
	elseif job.assignee == "player" then
		return Strings.get("ServiceStateYours", math.min(job.step, #job.steps), #job.steps), T.Good
	end
	return Strings.get("ServiceStateWaiting"), T.Text
end

local function orderCard(job: any, order: number)
	local tier = ServiceConfig.getTier(job.tier)
	local yours = job.assignee == "player"
	local cardFrame = Kit.card({
		Name = "Order" .. job.id,
		Size = UDim2.fromOffset(400, 222),
		LayoutOrder = order,
		Parent = ordersList,
	})
	if yours then
		local s = cardFrame:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = T.Good
			s.Thickness = 4
		end
	end
	-- vehicle preview on a little stage
	local stage = Kit.new("Frame", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = cardFrame,
	})
	Kit.corner(stage, 14)
	Kit.stroke(stage, T.Ink, 2.5, 0)
	Kit.gradient(stage, Color3.fromRGB(150, 210, 255), Color3.fromRGB(70, 120, 200), 90)
	previewFor(job, stage)
	if tier then
		local tag = Kit.pill(cardFrame, tier.icon .. " " .. Strings.pick(tier.name), T.PanelAlt, 0)
		tag.AnchorPoint = Vector2.new(0.5, 0.5)
		tag.Position = UDim2.fromOffset(87, 176)
		tag.TextSize = 13
		tag.Size = UDim2.fromOffset(0, 24)
	end
	-- text side
	Kit.label({
		Position = UDim2.fromOffset(176, 10),
		Size = UDim2.fromOffset(212, 30),
		Text = Workshop.vehicleName(job),
		TextScaled = true,
		maxTextSize = 23,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 2,
		Parent = cardFrame,
	})
	local pills = Kit.new("Frame", {
		Position = UDim2.fromOffset(176, 44),
		Size = UDim2.fromOffset(214, 62),
		BackgroundTransparency = 1,
		Parent = cardFrame,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(105, 28),
		CellPadding = UDim2.fromOffset(4, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = pills,
	})
	for i, id in job.services do
		local svc = ServiceConfig.getService(id)
		if svc then
			local pill = Kit.pill(pills, svc.icon .. " " .. Strings.get("Service_" .. id), svc.color, i)
			pill.AutomaticSize = Enum.AutomaticSize.None
			pill.TextScaled = true
		end
	end
	if job.target then
		local sw = Kit.new("Frame", {
			Position = UDim2.fromOffset(176, 104),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = Paints.getColor(job.target),
			BorderSizePixel = 0,
			Parent = cardFrame,
		})
		Kit.corner(sw, 11)
		Kit.stroke(sw, T.Ink, 2.5, 0)
		local swatch = Paints.Palette[job.target]
		Kit.label({
			Position = UDim2.fromOffset(204, 104),
			Size = UDim2.fromOffset(184, 22),
			Text = Strings.get("ServicePaintTo", if swatch then Strings.pick(swatch.name) else ""),
			TextScaled = true,
			maxTextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			outline = 1.5,
			Parent = cardFrame,
		})
	end
	-- reward with a coin, xp chip
	Kit.coin(cardFrame, 30, { Position = UDim2.fromOffset(176, 130) })
	Kit.label({
		Position = UDim2.fromOffset(212, 128),
		Size = UDim2.fromOffset(110, 34),
		Text = Format.money(job.reward),
		TextSize = 30,
		TextColor3 = T.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 2.5,
		Parent = cardFrame,
	})
	local xp = Kit.pill(cardFrame, "+" .. tostring(job.xp) .. " XP", T.Accent2, 0)
	xp.AnchorPoint = Vector2.new(1, 0)
	xp.Position = UDim2.fromOffset(390, 132)
	xp.TextSize = 15
	-- action
	local text, color = stateText(job)
	if job.state == "waiting" and job.assignee == nil then
		local patience = math.clamp(1 - (serverNow() - job.waitingSince) / ServiceConfig.Patience, 0, 1)
		local bar = Kit.new("Frame", {
			Position = UDim2.fromOffset(14, 194),
			Size = UDim2.fromOffset(146, 12),
			BackgroundColor3 = Color3.fromRGB(16, 24, 50),
			BorderSizePixel = 0,
			Parent = cardFrame,
		})
		Kit.corner(bar, 6)
		Kit.stroke(bar, T.Ink, 2, 0)
		local fill = Kit.new("Frame", {
			Size = UDim2.fromScale(patience, 1),
			BackgroundColor3 = if patience > 0.5 then T.Good elseif patience > 0.2 then T.Warn else T.Bad,
			BorderSizePixel = 0,
			Parent = bar,
		})
		Kit.corner(fill, 6)
		table.insert(live, { job = job, fill = fill })
		Kit.button({
			Position = UDim2.fromOffset(176, 172),
			Size = UDim2.fromOffset(160, 40),
			Text = "✋ " .. Strings.get("ServiceTake"),
			TextSize = 20,
			BackgroundColor3 = T.Good,
			onClick = function()
				local r = request("ServiceTake", job.id)
				if r.ok then
					setOrdersOpen(false)
				end
			end,
			Parent = cardFrame,
		})
		Kit.button({
			Position = UDim2.fromOffset(344, 172),
			Size = UDim2.fromOffset(44, 40),
			Text = "✖",
			TextSize = 18,
			BackgroundColor3 = T.Bad,
			onClick = function()
				Net.request("ServiceDismiss", job.id)
			end,
			Parent = cardFrame,
		})
	elseif job.assignee == "player" and job.state == "inBay" then
		Kit.button({
			Position = UDim2.fromOffset(176, 172),
			Size = UDim2.fromOffset(160, 40),
			Text = "🧽 " .. Strings.get("ServiceWork"),
			TextSize = 21,
			BackgroundColor3 = T.Accent,
			onClick = function()
				setOrdersOpen(false)
				Workshop.enter(job.id)
			end,
			Parent = cardFrame,
		})
		Kit.button({
			Position = UDim2.fromOffset(344, 172),
			Size = UDim2.fromOffset(44, 40),
			Text = "✖",
			TextSize = 18,
			BackgroundColor3 = T.Bad,
			onClick = function()
				Net.request("ServiceCancel", job.id)
			end,
			Parent = cardFrame,
		})
	else
		local label = Kit.label({
			Position = UDim2.fromOffset(176, 174),
			Size = UDim2.fromOffset(212, 36),
			Text = text,
			TextSize = 19,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			outline = 2,
			Parent = cardFrame,
		})
		table.insert(live, { job = job, label = label })
	end
end

local function updateLive()
	for _, item in live do
		local job = item.job
		if item.fill then
			local patience = math.clamp(1 - (serverNow() - job.waitingSince) / ServiceConfig.Patience, 0, 1)
			item.fill.Size = UDim2.fromScale(patience, 1)
			item.fill.BackgroundColor3 = if patience > 0.5 then T.Good elseif patience > 0.2 then T.Warn else T.Bad
		end
		if item.label then
			item.label.Text = (stateText(job))
		end
	end
end

local function renderOrders()
	if not ordersOpen then
		return
	end
	table.clear(live)
	for _, c in ordersList:GetChildren() do
		if c:IsA("GuiObject") then
			for _, d in c:GetDescendants() do
				if d:IsA("ViewportFrame") then
					d.Parent = nil -- keep cached previews alive
				end
			end
			c:Destroy()
		end
	end
	local list = {}
	for _, job in jobs() do
		if job.state ~= "leaving" and job.state ~= "arriving" then
			table.insert(list, job)
		end
	end
	-- your jobs first, then waiting ones, then staff
	local function rank(job: any): number
		if job.assignee == "player" then
			return 0
		elseif job.assignee == nil then
			return 1
		end
		return 2
	end
	table.sort(list, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a.id < b.id
	end)
	for i, job in list do
		orderCard(job, i)
	end
	if #list == 0 then
		Kit.label({
			Size = UDim2.new(1, -20, 0, 120),
			Text = Strings.get("ServiceNoOrders"),
			TextSize = 22,
			TextColor3 = T.Muted,
			TextWrapped = true,
			LayoutOrder = 1,
			Parent = ordersList,
		})
	end
	local svc = svcProfile()
	local upgrades = if svc then svc.upgrades else {}
	local busy = 0
	for _, job in jobs() do
		if job.bay then
			busy += 1
		end
	end
	local bays = ServiceConfig.bayCount(upgrades)
	ordersInfo.Text = Strings.get("ServiceOrdersInfo", math.max(0, bays - busy), bays, ServiceConfig.parkingCount(upgrades))
end

--------------------------------------------------------------------------------
-- Business window
--------------------------------------------------------------------------------

local function renderBusiness()
	if not businessOpen then
		return
	end
	for _, c in businessBody:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local svc = svcProfile()
	if not svc then
		return
	end
	local cash = if ClientState.profile then ClientState.profile.cash else 0
	-- stats row: four chips
	local stats = Kit.new("Frame", {
		Size = UDim2.new(1, -16, 0, 84),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = businessBody,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.25, -9, 1, 0),
		CellPadding = UDim2.fromOffset(12, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = stats,
	})
	for i, item in
		{
			{ "⭐", Strings.get("ServiceLevelShort", svc.level), T.Warn },
			{ "✅", Strings.get("ServiceOrdersDone", Format.int(svc.orders)), T.Good },
			{ "🌟", Strings.get("ServiceStars", Format.int(svc.stars)), T.Gold },
			{ "💰", Format.money(svc.earned), T.Accent },
		}
	do
		local cell = Kit.card({ LayoutOrder = i, Parent = stats })
		Kit.iconTile(cell, item[1], item[3], 52, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0) })
		Kit.label({
			Position = UDim2.fromOffset(72, 0),
			Size = UDim2.new(1, -80, 1, 0),
			Text = item[2],
			TextScaled = true,
			maxTextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			outline = 2,
			Parent = cell,
		})
	end

	-- upgrade cards
	local grid = Kit.new("Frame", {
		Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = businessBody,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(272, 190),
		CellPadding = UDim2.fromOffset(12, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local UPGRADE_COLORS = {
		bays = T.Accent2,
		parking = T.Teal,
		tools = T.Accent,
		marketing = T.Pink,
		staff = T.Good,
		training = T.Purple,
	}
	for i, u in ServiceConfig.Upgrades do
		local level = svc.upgrades[u.id] or 0
		local nextLevel = u.levels[level + 1]
		local cardFrame = Kit.card({ LayoutOrder = i, Parent = grid })
		Kit.iconTile(cardFrame, u.icon, UPGRADE_COLORS[u.id] or T.Accent, 60, { Position = UDim2.fromOffset(12, 12) })
		Kit.label({
			Position = UDim2.fromOffset(84, 12),
			Size = UDim2.fromOffset(178, 30),
			Text = Strings.get("Upgrade_" .. u.id),
			TextSize = 23,
			TextXAlignment = Enum.TextXAlignment.Left,
			outline = 2,
			Parent = cardFrame,
		})
		-- level pips
		local pips = Kit.new("Frame", { Position = UDim2.fromOffset(84, 48), Size = UDim2.fromOffset(178, 16), BackgroundTransparency = 1, Parent = cardFrame })
		Kit.list(pips, Enum.FillDirection.Horizontal, 5)
		for k = 1, #u.levels do
			local pip = Kit.new("Frame", {
				Size = UDim2.fromOffset(26, 14),
				BackgroundColor3 = if k <= level then T.Good else Color3.fromRGB(20, 30, 62),
				BorderSizePixel = 0,
				LayoutOrder = k,
				Parent = pips,
			})
			Kit.corner(pip, 7)
			Kit.stroke(pip, T.Ink, 2, 0)
		end
		Kit.label({
			Position = UDim2.fromOffset(14, 80),
			Size = UDim2.new(1, -28, 0, 44),
			Text = Strings.get("UpgradeDesc_" .. u.id),
			TextSize = 16,
			Font = T.FontMedium,
			TextColor3 = T.Muted,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = cardFrame,
		})
		local buttonText, buttonColor, enabled
		if not nextLevel then
			buttonText, buttonColor, enabled = "✔ " .. Strings.get("MaxLevel"), T.Disabled, false
		elseif svc.level < nextLevel.level then
			buttonText, buttonColor, enabled = "🔒 " .. Strings.get("ServiceNeedLevelShort", nextLevel.level), T.Disabled, false
		else
			buttonText = "💰 " .. Format.money(nextLevel.price)
			buttonColor = if cash >= nextLevel.price then T.Good else T.Bad
			enabled = true
		end
		Kit.button({
			Position = UDim2.fromOffset(14, 132),
			Size = UDim2.new(1, -28, 0, 42),
			Text = buttonText,
			TextSize = 21,
			BackgroundColor3 = buttonColor,
			onClick = function()
				if enabled then
					request("ServiceBuy", u.id)
				end
			end,
			Parent = cardFrame,
		})
	end

	-- staff
	local s = ClientState.service
	Kit.label({
		Size = UDim2.new(1, -16, 0, 40),
		Text = "👷 " .. Strings.get("ServiceStaffTitle"),
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 2.5,
		LayoutOrder = 3,
		Parent = businessBody,
	})
	local staff = Kit.new("Frame", {
		Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = businessBody,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(272, 72),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = staff,
	})
	local workers = if s then s.workers else {}
	if #workers == 0 then
		local empty = Kit.card({ LayoutOrder = 0, Parent = staff })
		Kit.label({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -24, 1, -12),
			Text = Strings.get("ServiceNoStaff"),
			TextSize = 14,
			Font = T.FontMedium,
			TextColor3 = T.Muted,
			TextWrapped = true,
			Parent = empty,
		})
	end
	for _, w in workers do
		local name = ServiceConfig.WorkerNames[((w.index - 1) % #ServiceConfig.WorkerNames) + 1]
		local row = Kit.card({ LayoutOrder = w.index, Parent = staff })
		Kit.iconTile(row, "👷", if w.state == "idle" then T.Disabled else T.Good, 50, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 11, 0.5, 0) })
		Kit.label({
			Position = UDim2.fromOffset(72, 8),
			Size = UDim2.fromOffset(190, 28),
			Text = Strings.pick(name),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			outline = 2,
			Parent = row,
		})
		Kit.label({
			Position = UDim2.fromOffset(72, 38),
			Size = UDim2.fromOffset(190, 22),
			Text = Strings.get("ServiceWorker_" .. w.state),
			TextSize = 15,
			Font = T.FontMedium,
			TextColor3 = if w.state == "idle" then T.Muted else Color3.fromRGB(140, 255, 160),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
	end
end

--------------------------------------------------------------------------------
-- Result and level-up cards
--------------------------------------------------------------------------------

local resultStars: { TextLabel } = {}
local resultTitle: TextLabel
local resultVehicle: TextLabel
local resultMoney: TextLabel
local resultDetail: TextLabel

local function showResult(data: any, instant: boolean?)
	resultVehicle.Text = Workshop.vehicleName({ source = data.source, vehicle = data.vehicle })
	resultTitle.Text = Strings.get("ServiceResultTitle")
	resultMoney.Text = "+" .. Format.money((data.reward or 0) + (data.tip or 0))
	local detail = Strings.get("ServiceResultXp", data.xp or 0)
	if (data.tip or 0) > 0 then
		detail = Strings.get("ServiceResultTip", Format.money(data.tip)) .. "   ·   " .. detail
	end
	resultDetail.Text = detail
	local stars = data.stars or 0
	for i, star in resultStars do
		local lit = i <= stars
		star.TextColor3 = if lit then T.Gold else Color3.fromRGB(26, 36, 70)
		star.TextSize = if lit then 76 else 62
		if lit and not instant then
			-- pop the earned stars one after another
			star.TextTransparency = 1
			task.delay(0.3 + i * 0.25, function()
				star.TextTransparency = 0
				star.TextSize = 96
				Kit.tween(star, 0.3, { TextSize = 76 }, Enum.EasingStyle.Back)
			end)
		end
	end
	setResultOpen(true)
end

local levelTitle: TextLabel
local levelList: Frame

local function showLevelUp(level: number)
	levelTitle.Text = Strings.get("ServiceLevelUp", level)
	for _, c in levelList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local unlocks = ServiceConfig.unlocksAt(level)
	if #unlocks == 0 then
		table.insert(unlocks, { kind = "more", id = "", icon = "💰" })
	end
	for i, u in unlocks do
		local text
		if u.kind == "more" then
			text = Strings.get("ServiceUnlockMore")
		elseif u.kind == "tier" then
			local tier = ServiceConfig.getTier(u.id)
			text = Strings.get("ServiceUnlockTier", if tier then Strings.pick(tier.name) else u.id)
		elseif u.kind == "service" then
			text = Strings.get("ServiceUnlockService", Strings.get("Service_" .. u.id))
		else
			text = Strings.get("ServiceUnlockUpgrade", Strings.get("Upgrade_" .. u.id))
		end
		local row = Kit.card({ Size = UDim2.new(1, 0, 0, 64), LayoutOrder = i, Parent = levelList })
		Kit.iconTile(row, u.icon, if u.kind == "tier" then T.Accent2 elseif u.kind == "service" then T.Pink else T.Good, 48, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
		})
		Kit.label({
			Position = UDim2.fromOffset(70, 0),
			Size = UDim2.new(1, -80, 1, 0),
			Text = text,
			TextSize = 21,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			outline = 2,
			Parent = row,
		})
	end
	setLevelOpen(true)
end

--------------------------------------------------------------------------------
-- Rail, level bar and hints
--------------------------------------------------------------------------------

local function refreshLevel()
	local svc = svcProfile()
	if not svc then
		return
	end
	levelBadge.Text = tostring(svc.level)
	local need = ServiceConfig.xpToNext(svc.level)
	local frac = if svc.level >= ServiceConfig.MaxLevel then 1 else math.clamp(svc.xp / need, 0, 1)
	Kit.tween(xpFill, 0.35, { Size = UDim2.fromScale(frac, 1) })
	xpText.Text = if svc.level >= ServiceConfig.MaxLevel then "MAX" else string.format("%d / %d XP", svc.xp, need)
end

local function setHint(key: string?, ...: any)
	if not key or ClientState.workingJob or ClientState.racing then
		hint.Visible = false
		return
	end
	hintLabel.Text = Strings.get(key, ...)
	if not hint.Visible then
		hint.Visible = true
		hint.Position = UDim2.new(0.5, 0, 0, -80)
		Kit.tween(hint, 0.35, { Position = UDim2.new(0.5, 0, 0, 18) }, Enum.EasingStyle.Back)
	end
end

local function nearMyPlot(): boolean
	local s = ClientState.service
	local char = Players.LocalPlayer.Character
	if not s or not char or not char.PrimaryPart or typeof(s.origin) ~= "CFrame" then
		return false
	end
	local rel = (s.origin :: CFrame):PointToObjectSpace(char.PrimaryPart.Position)
	return math.abs(rel.X) < 120 and math.abs(rel.Z) < 110
end

local function refreshRail()
	local waiting = #waitingJobs()
	local mine = myJob()
	buttons.orders.setBadge(waiting)
	buttons.orders.setPulse(waiting > 0 and mine == nil)
	local canWork = mine ~= nil and mine.state == "inBay"
	buttons.work.setPulse(canWork and not ClientState.workingJob)
	buttons.work.setColor(if canWork then T.Accent elseif mine then T.Warn else T.Disabled)
	buttons.work.caption.Text = if mine and not canWork then Strings.get("ServiceStateToBayShort") else Strings.get("ServiceWork")
	buttons.work.setBadge(if canWork then 1 else nil)
	-- business: badge when something is affordable
	local svc = svcProfile()
	local cash = if ClientState.profile then ClientState.profile.cash else 0
	local affordable = 0
	if svc then
		for _, u in ServiceConfig.Upgrades do
			local nextLevel = u.levels[(svc.upgrades[u.id] or 0) + 1]
			if nextLevel and svc.level >= nextLevel.level and cash >= nextLevel.price then
				affordable += 1
			end
		end
	end
	buttons.business.setBadge(affordable)

	-- first-time hints until the first order is done
	local tutorial = if svc then svc.tutorial else 99
	if tutorial >= 1 or (svc and svc.orders > 0) then
		setHint(nil)
	elseif mine and mine.state == "inBay" then
		setHint("ServiceHintWork")
	elseif mine then
		setHint("ServiceHintToBay")
	elseif waiting > 0 then
		setHint(if nearMyPlot() then "ServiceHintTake" else "ServiceHintGoTake")
	elseif not nearMyPlot() then
		setHint("ServiceHintHome")
	else
		setHint("ServiceHintWait")
	end
end

--------------------------------------------------------------------------------
-- World prompts on the own plot
--------------------------------------------------------------------------------

local function prompt(parent: Instance, key: string, objectKey: string?, onTrigger: () -> (), distance: number?): ProximityPrompt
	local existing = prompts[parent]
	if existing then
		existing.ActionText = Strings.get(key)
		return existing
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "ServicePrompt"
	p.ActionText = Strings.get(key)
	p.ObjectText = if objectKey then Strings.get(objectKey) else ""
	p.HoldDuration = 0
	p.MaxActivationDistance = distance or 14
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Triggered:Connect(onTrigger)
	p.Parent = parent
	prompts[parent] = p
	return p
end

local function clearPrompt(parent: Instance)
	local p = prompts[parent]
	if p then
		p:Destroy()
		prompts[parent] = nil
	end
end

local function plotFolder(): Instance?
	local s = ClientState.service
	local worldRoot = Workspace:FindFirstChild("CarsWorld")
	local folder = worldRoot and worldRoot:FindFirstChild("Service")
	return if s and folder then folder:FindFirstChild("ServicePlot" .. tostring(s.plot)) else nil
end

local function refreshPrompts()
	local folder = plotFolder()
	if not folder then
		return
	end
	local board = folder:FindFirstChild("OrderBoard")
	if board then
		prompt(board, "ServiceOpenOrders", "ServiceBoardObject", function()
			Service.openOrders()
		end, 18)
	end
	local desk = folder:FindFirstChild("Desk")
	if desk then
		prompt(desk, "ServiceOpenBusiness", "ServiceDeskObject", function()
			Service.openBusiness()
		end)
	end
	-- vehicles: take waiting ones, work on yours
	local byId = {}
	for _, job in jobs() do
		byId[job.id] = job
	end
	for _, model in CollectionService:GetTagged("ServiceCustomer") do
		local id = model:GetAttribute("ServiceJob")
		local job = byId[id]
		local root = (model :: Model).PrimaryPart
		if root then
			local anchor = root:FindFirstChild("PromptAnchor") :: Attachment?
			if not anchor and job then
				local a = Instance.new("Attachment")
				a.Name = "PromptAnchor"
				a.Position = Vector3.new(0, ((model:GetAttribute("Height") or 4) :: number) * 0.5, 0)
				a.Parent = root
				anchor = a
			end
			if anchor then
				if job and job.state == "waiting" and job.assignee == nil then
					local p = prompt(anchor, "ServiceTake", nil, function()
						request("ServiceTake", job.id)
					end, 16)
					p.ObjectText = Workshop.vehicleName(job) .. " · " .. Format.money(job.reward)
				elseif job and job.assignee == "player" and job.state == "inBay" then
					local p = prompt(anchor, "ServiceWork", nil, function()
						Workshop.enter(job.id)
					end, 20)
					p.ObjectText = serviceNames(job)
				else
					clearPrompt(anchor)
				end
			end
		end
	end
	for parent in prompts do
		if not parent.Parent then
			prompts[parent] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function Service.openOrders()
	if businessOpen then
		setBusinessOpen(false)
		businessOpen = false
	end
	ordersOpen = true
	setOrdersOpen(true)
	renderOrders()
end

function Service.openBusiness()
	if ordersOpen then
		setOrdersOpen(false)
		ordersOpen = false
	end
	businessOpen = true
	setBusinessOpen(true)
	renderBusiness()
end

function Service.goHome()
	request("ServiceHome")
end

local function onWork()
	local mine = myJob()
	if not mine then
		Service.openOrders()
	elseif mine.state == "inBay" then
		Workshop.enter(mine.id)
	else
		Notifications.notifyKey("ServiceArriving", {}, "info")
	end
end

function Service.init()
	gui = Kit.screen("CarsService", 5)

	-- service level under the cash: a star badge and an xp bar
	local levelBar = Kit.panel({
		Name = "ServiceLevel",
		Position = UDim2.new(0, 34, 0, 82),
		Size = UDim2.fromOffset(236, 46),
		Parent = gui,
	})
	Kit.corner(levelBar, 23)
	local badge = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = levelBar,
	})
	Kit.corner(badge, 28)
	Kit.stroke(badge, T.Ink, 3, 0)
	Kit.gradient(badge, Color3.fromRGB(120, 220, 255), T.Accent2, 90)
	Kit.label({ Size = UDim2.fromScale(1, 1), Text = "⭐", TextSize = 34, TextTransparency = 0.25, Parent = badge })
	levelBadge = Kit.label({ Size = UDim2.fromScale(1, 1), Text = "1", TextSize = 24, outline = 2.5, Parent = badge })
	Kit.label({
		Position = UDim2.fromOffset(36, 3),
		Size = UDim2.fromOffset(190, 18),
		Text = "🔧 " .. Strings.get("ServiceTitle"),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 1.5,
		Parent = levelBar,
	})
	local xpBack = Kit.new("Frame", {
		Position = UDim2.fromOffset(36, 23),
		Size = UDim2.fromOffset(188, 16),
		BackgroundColor3 = Color3.fromRGB(16, 24, 50),
		BorderSizePixel = 0,
		Parent = levelBar,
	})
	Kit.corner(xpBack, 8)
	Kit.stroke(xpBack, T.Ink, 2, 0)
	xpFill = Kit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = xpBack })
	Kit.corner(xpFill, 8)
	Kit.gradient(xpFill, Color3.fromRGB(140, 235, 255), T.Accent2, 90)
	xpText = Kit.label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 12, outline = 1.5, Parent = xpBack })

	-- big tiles in the shared rail
	buttons.home = Rail.add({
		name = "Home",
		icon = "🏠",
		caption = Strings.get("ServiceHome"),
		color = T.Teal,
		layoutOrder = 1,
		onClick = Service.goHome,
	})
	buttons.orders = Rail.add({
		name = "Orders",
		icon = "📋",
		caption = Strings.get("ServiceOrders"),
		color = T.Accent2,
		layoutOrder = 2,
		onClick = function()
			if ordersOpen then
				ordersOpen = false
				setOrdersOpen(false)
			else
				Service.openOrders()
			end
		end,
	})
	buttons.work = Rail.add({
		name = "Work",
		icon = "🧽",
		caption = Strings.get("ServiceWork"),
		color = T.Disabled,
		layoutOrder = 3,
		onClick = onWork,
	})
	buttons.business = Rail.add({
		name = "Business",
		icon = "💼",
		caption = Strings.get("ServiceBusiness"),
		color = T.Purple,
		layoutOrder = 4,
		onClick = function()
			if businessOpen then
				businessOpen = false
				setBusinessOpen(false)
			else
				Service.openBusiness()
			end
		end,
	})

	-- tutorial hint: a bright card at the top with a pointing icon
	hint = Kit.panel({
		Name = "ServiceHint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(600, 66),
		BackgroundColor3 = Color3.fromRGB(255, 176, 30),
		Visible = false,
		Parent = gui,
	})
	Kit.corner(hint, 20)
	Kit.iconTile(hint, "💡", Color3.fromRGB(255, 230, 90), 54, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0) })
	hintLabel = Kit.label({
		Size = UDim2.new(1, -86, 1, -12),
		Position = UDim2.fromOffset(72, 6),
		Text = "",
		TextScaled = true,
		maxTextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 2.5,
		Parent = hint,
	})

	-- orders window
	local content
	ordersWindow, content, setOrdersOpen = Kit.modal(gui, "Orders", "📋 " .. Strings.get("ServiceOrdersTitle"), Vector2.new(870, 640), T.Accent2)
	ordersInfo = Kit.label({
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -44, 0, 28),
		Text = "",
		TextSize = 18,
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 1.5,
		Parent = content,
	})
	ordersList = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 34),
		Size = UDim2.new(1, -24, 1, -46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(150, 180, 255),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	})
	Kit.padding(ordersList, 4, 6)
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(400, 222),
		CellPadding = UDim2.fromOffset(14, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = ordersList,
	})
	ordersWindow:GetPropertyChangedSignal("Visible"):Connect(function()
		ordersOpen = ordersWindow.Visible
	end)

	-- business window
	businessWindow, content, setBusinessOpen = Kit.modal(gui, "Business", "💼 " .. Strings.get("ServiceBusinessTitle"), Vector2.new(920, 660), T.Purple)
	businessBody = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -24, 1, -14),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(190, 160, 255),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	})
	Kit.list(businessBody, Enum.FillDirection.Vertical, 14)
	Kit.padding(businessBody, 4, 6)
	businessWindow:GetPropertyChangedSignal("Visible"):Connect(function()
		businessOpen = businessWindow.Visible
	end)

	-- result card
	resultWindow, content, setResultOpen = Kit.modal(gui, "Result", "🎉", Vector2.new(540, 430), T.Good)
	resultTitle = resultWindow:FindFirstChild("Title", true) :: TextLabel
	resultVehicle = Kit.label({ Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 34), Text = "", TextSize = 28, outline = 2.5, Parent = content })
	local starRow = Kit.new("Frame", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1, Parent = content })
	Kit.list(starRow, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i = 1, 3 do
		local star = Kit.label({
			Size = UDim2.fromOffset(96, 96),
			Text = "★",
			TextSize = 76,
			TextColor3 = T.Gold,
			LayoutOrder = i,
			TextTruncate = Enum.TextTruncate.None,
			outline = 3.5,
			Parent = starRow,
		})
		table.insert(resultStars, star)
	end
	local moneyRow = Kit.card({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 142),
		Size = UDim2.fromOffset(300, 64),
		Parent = content,
	})
	Kit.coin(moneyRow, 46, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0) })
	resultMoney = Kit.label({ Position = UDim2.fromOffset(66, 0), Size = UDim2.new(1, -76, 1, 0), Text = "", TextSize = 44, TextColor3 = T.Gold, outline = 3, Parent = moneyRow })
	resultDetail = Kit.label({ Position = UDim2.fromOffset(0, 214), Size = UDim2.new(1, 0, 0, 28), Text = "", TextSize = 20, TextColor3 = Color3.fromRGB(150, 225, 255), outline = 2, Parent = content })
	Kit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(260, 60),
		Text = Strings.get("ServiceContinue"),
		TextSize = 28,
		BackgroundColor3 = T.Good,
		cornerRadius = 16,
		onClick = function()
			setResultOpen(false)
		end,
		Parent = content,
	})

	-- level-up card
	levelWindow, content, setLevelOpen = Kit.modal(gui, "LevelUp", "⭐", Vector2.new(580, 470), Color3.fromRGB(255, 170, 20))
	levelTitle = levelWindow:FindFirstChild("Title", true) :: TextLabel
	levelList = Kit.new("Frame", { Position = UDim2.fromOffset(24, 8), Size = UDim2.new(1, -48, 1, -110), BackgroundTransparency = 1, Parent = content })
	Kit.list(levelList, Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center)
	Kit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(260, 60),
		Text = Strings.get("ServiceCool"),
		TextSize = 28,
		cornerRadius = 16,
		BackgroundColor3 = T.Accent,
		onClick = function()
			setLevelOpen(false)
		end,
		Parent = content,
	})
end

function Service.start()
	Net.on("ServiceState", function(snapshot)
		if typeof(snapshot) == "table" then
			ClientState.setService(snapshot)
		end
	end)
	Net.on("ServiceEvent", function(kind, data)
		if kind == "arrived" then
			Notifications.notifyKey("ServiceArrived", {}, "info")
		elseif kind == "ready" then
			Notifications.notifyKey("ServiceReady", {}, "success")
		elseif kind == "done" and typeof(data) == "table" then
			if not data.worker then
				lastResult = os.clock()
				task.delay(0.8, showResult, data)
				local svc = svcProfile()
				if svc and svc.tutorial < 1 then
					task.spawn(Net.request, "ServiceTutorial", 1)
				end
			end
		elseif kind == "levelup" and typeof(data) == "number" then
			-- after the result card has had its moment
			local recent = os.clock() - lastResult < 2
			task.delay(if recent or resultWindow.Visible then 3 else 1, showLevelUp, data)
		end
	end)
	ClientState.ServiceChanged:Connect(function()
		dropPreviews()
		refreshRail()
		refreshPrompts()
		renderOrders()
		renderBusiness()
	end)
	ClientState.ProfileChanged:Connect(function()
		refreshLevel()
		refreshRail()
		renderBusiness()
	end)
	ClientState.WorkingChanged:Connect(function(id)
		Rail.setVisible(id == nil)
		gui.Enabled = id == nil
		refreshRail()
	end)
	CollectionService:GetInstanceAddedSignal("ServiceCustomer"):Connect(function()
		task.defer(refreshPrompts)
	end)
	refreshLevel()
	-- live bits: worker progress in the open orders window, hints
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 then
			return
		end
		acc = 0
		refreshRail()
		if ordersOpen then
			updateLive()
		end
	end)
end

-- Hooks for the UI screenshot test (the mock has no task.delay).
Service._test = {
	showResult = function(data)
		showResult(data, true)
	end,
	showLevelUp = function(level)
		showLevelUp(level)
	end,
}

return Service
