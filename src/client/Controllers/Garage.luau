-- Garage: the dealership/garage window. Browse every car by class with a 3D
-- preview and stats, buy and spawn cars, paint them and buy upgrades.

local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local CarBuilder = require(Shared.CarBuilder)
local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Paints = require(Shared.Paints)
local Strings = require(Shared.Strings)

local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Parent.UI.Kit)
local Hud = require(script.Parent.Hud)
local Notifications = require(script.Parent.Notifications)
local T = Kit.Theme

local Garage = {}

local gui: ScreenGui
local window: Frame
local grid: ScrollingFrame
local chips: Frame
local viewport: ViewportFrame
local worldModel: WorldModel
local camera: Camera
local nameLabel: TextLabel
local classLabel: TextLabel
local tabContent: Frame
local primaryButton: TextButton
local secondaryButton: TextButton
local tabButtons: { [string]: TextButton } = {}
local cards: { [string]: Frame } = {}

local selectedId: string = Config.StarterCarId
local classFilter: string? = nil
local currentTab = "Info"
local paintSlot = "paint"
local previewModel: Model? = nil
local previewKey = ""
local orbit = 0
local previewOverride: { [string]: any }? = nil
local busy = false

local function profile()
	return ClientState.profile
end

local function owned(id: string): boolean
	local p = profile()
	return p ~= nil and p.owned[id] == true
end

local function saveFor(id: string)
	local p = profile()
	local def = CarCatalog.get(id)
	local save = if p and p.cars[id] then table.clone(p.cars[id]) else (if def then CarCatalog.defaultSave(def) else nil)
	if save and previewOverride and previewOverride.id == id then
		for k, v in previewOverride do
			if k ~= "id" then
				save[k] = v
			end
		end
	end
	return save
end

local function request(action: string, ...: any)
	if busy then
		return { ok = false }
	end
	busy = true
	local r = Net.request(action, ...)
	busy = false
	if r.message then
		Notifications.notifyKey(r.message, r.args, if r.ok then "success" else "warning")
	end
	return r
end

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------

local function refreshPreview(force: boolean?)
	local def = CarCatalog.get(selectedId)
	if not def then
		return
	end
	local save = saveFor(def.id)
	local key = def.id .. ":" .. (if save then string.format("%d/%d/%d/%s/%d", save.paint, save.accent, save.rim, save.finish, save.glow) else "")
	if key == previewKey and not force then
		return
	end
	previewKey = key
	if previewModel then
		previewModel:Destroy()
	end
	local model = CarBuilder.build(def, { preview = true, save = save })
	model:PivotTo(CFrame.new(0, 0, 0) * (model.PrimaryPart :: BasePart).CFrame)
	model.Parent = worldModel
	previewModel = model
end

local function updateCamera(dt: number)
	if not previewModel then
		return
	end
	local def = CarCatalog.get(selectedId)
	if not def then
		return
	end
	orbit += dt * 0.45
	local ext = CarBuilder.getExtents(def)
	local dist = math.max(ext.Z, ext.X * 1.6) * 1.05 + 6
	local center = Vector3.new(0, ext.Y * 0.4, 0)
	local pos = center + Vector3.new(math.sin(orbit) * dist, ext.Y * 0.55 + dist * 0.22, math.cos(orbit) * dist)
	camera.CFrame = CFrame.lookAt(pos, center)
end

--------------------------------------------------------------------------------
-- Right panel
--------------------------------------------------------------------------------

local function clearTab()
	for _, c in tabContent:GetChildren() do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function statRow(parent: Instance, order: number, label: string, value: number, color: Color3)
	local row = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	Kit.label({ Size = UDim2.new(0, 150, 1, 0), Text = label, TextSize = 15, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	local holder = Kit.new("Frame", { Position = UDim2.new(0, 150, 0.5, -4), Size = UDim2.new(1, -200, 0, 8), BackgroundTransparency = 1, Parent = row })
	local _, set = Kit.bar(holder, color)
	set(value)
	Kit.label({
		Position = UDim2.new(1, -44, 0, 0),
		Size = UDim2.new(0, 44, 1, 0),
		Text = string.format("%.1f", value),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
end

local function drawInfo()
	local def = CarCatalog.get(selectedId)
	if not def then
		return
	end
	local list = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = tabContent })
	Kit.list(list, Enum.FillDirection.Vertical, 6)
	Kit.label({
		Size = UDim2.new(1, 0, 0, 40),
		Text = Strings.pick(def.description),
		TextWrapped = true,
		TextSize = 15,
		TextColor3 = T.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 0,
		Parent = list,
	})
	local p = profile()
	local stats = CarCatalog.getEffectiveStats(def, if p then p.cars[def.id] else nil)
	local r = CarCatalog.getRatings(stats)
	statRow(list, 1, Strings.get("StatSpeed"), r.speed, T.Accent)
	statRow(list, 2, Strings.get("StatAccel"), r.accel, T.Warn)
	statRow(list, 3, Strings.get("StatHandling"), r.handling, T.Accent2)
	statRow(list, 4, Strings.get("StatOffroad"), r.offroad, Color3.fromRGB(190, 150, 90))
	statRow(list, 5, Strings.get("StatNitro"), r.nitro, Color3.fromRGB(170, 100, 255))
	local seats = #CarBuilder.getSeats(def)
	Kit.label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = Strings.get("TopSpeed", Format.speed(stats.maxSpeed)) .. "   ·   " .. Strings.get("DriveType", stats.drive) .. "   ·   " .. Strings.get(
			"Seats",
			seats
		),
		TextSize = 15,
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 6,
		Parent = list,
	})
end

local SLOT_KEYS = { paint = "PaintBody", accent = "PaintAccent", rim = "PaintRims", glow = "PaintGlow", finish = "PaintFinish" }
local SLOT_ORDER = { "paint", "accent", "rim", "glow", "finish" }

local function slotPrice(slot: string, value: any, save): number
	local c = Config.Customization
	local p = profile()
	if slot == "paint" then
		return c.PaintPrice
	elseif slot == "accent" then
		return c.AccentPrice
	elseif slot == "rim" then
		return c.RimPrice
	elseif slot == "glow" then
		if value == 0 then
			return 0
		end
		return if save and save.glowOwned then c.PaintPrice else c.UnderglowPrice
	elseif slot == "finish" then
		if value == "Gloss" or (p and p.finishes[value]) then
			return 0
		end
		return (c.FinishPrices :: any)[value] or 0
	end
	return 0
end

local drawTab: () -> ()

local function drawPaint()
	local def = CarCatalog.get(selectedId)
	if not def then
		return
	end
	if not owned(def.id) then
		Kit.label({ Size = UDim2.fromScale(1, 1), Text = Strings.get("BuyCarFirst"), TextColor3 = T.Muted, TextSize = 18, Parent = tabContent })
		return
	end
	local save = saveFor(def.id)
	local slots = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Parent = tabContent })
	Kit.list(slots, Enum.FillDirection.Horizontal, 6)
	for i, slot in SLOT_ORDER do
		Kit.button({
			Size = UDim2.new(0, 108, 1, 0),
			Text = Strings.get(SLOT_KEYS[slot]),
			TextSize = 14,
			LayoutOrder = i,
			BackgroundColor3 = if slot == paintSlot then T.Accent else T.Card,
			onClick = function()
				paintSlot = slot
				drawTab()
			end,
			Parent = slots,
		})
	end
	local area = Kit.new("Frame", {
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -76),
		BackgroundTransparency = 1,
		Parent = tabContent,
	})
	local priceLabel = Kit.label({
		Position = UDim2.new(0, 0, 1, -24),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		TextSize = 15,
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = tabContent,
	})

	local function apply(value: any)
		previewOverride = { id = def.id, [paintSlot] = value }
		refreshPreview()
		task.spawn(function()
			local r = request("SetPaint", def.id, paintSlot, value)
			previewOverride = nil
			if not r.ok then
				refreshPreview(true)
			end
		end)
	end

	if paintSlot == "finish" then
		local list = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = area })
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0, 186, 0, 44),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})
		for i, f in Paints.Finishes do
			local price = slotPrice("finish", f.id, save)
			local current = save and save.finish == f.id
			Kit.button({
				Text = Strings.pick(f.name) .. (if price > 0 then "  " .. Format.moneyShort(price) else ""),
				TextSize = 15,
				LayoutOrder = i,
				BackgroundColor3 = if current then T.Accent else T.Card,
				onClick = function()
					apply(f.id)
				end,
				Parent = list,
			})
		end
		priceLabel.Text = ""
	else
		local list = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = area })
		Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0, 40, 0, 40),
			CellPadding = UDim2.new(0, 7, 0, 7),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})
		if paintSlot == "glow" then
			local off = Kit.button({
				Text = Strings.get("GlowOff"),
				TextSize = 11,
				LayoutOrder = 0,
				BackgroundColor3 = T.Card,
				onClick = function()
					apply(0)
				end,
				Parent = list,
			})
			if save and save.glow == 0 then
				Kit.stroke(off, T.Accent, 3, 0)
			end
		end
		for i, swatch in Paints.Palette do
			local b = Kit.button({
				Text = "",
				LayoutOrder = i,
				BackgroundColor3 = swatch.color,
				cornerRadius = 20,
				onClick = function()
					apply(i)
				end,
				Parent = list,
			})
			local current = save and (save :: any)[paintSlot] == i
			Kit.stroke(b, if current then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), if current then 3 else 1, if current then 0 else 0.6)
		end
		priceLabel.Text = Strings.get("PriceEach", Format.money(slotPrice(paintSlot, 1, save)))
	end
end

local UPGRADES = {
	{ kind = "Engine", field = "engine", title = "UpgradeEngine", desc = "UpgradeEngineDesc", color = T.Accent },
	{ kind = "Tires", field = "tires", title = "UpgradeTires", desc = "UpgradeTiresDesc", color = T.Accent2 },
	{ kind = "Nitro", field = "nitro", title = "UpgradeNitro", desc = "UpgradeNitroDesc", color = Color3.fromRGB(170, 100, 255) },
}

local function drawTuning()
	local def = CarCatalog.get(selectedId)
	if not def then
		return
	end
	if not owned(def.id) then
		Kit.label({ Size = UDim2.fromScale(1, 1), Text = Strings.get("BuyCarFirst"), TextColor3 = T.Muted, TextSize = 18, Parent = tabContent })
		return
	end
	local save = saveFor(def.id)
	local list = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = tabContent })
	Kit.list(list, Enum.FillDirection.Vertical, 10)
	for i, u in UPGRADES do
		local spec = (Config.Upgrades :: any)[u.kind]
		local level = if save then (save :: any)[u.field] else 0
		local row = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 62),
			BackgroundColor3 = T.Card,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = list,
		})
		Kit.corner(row, 10)
		Kit.label({
			Position = UDim2.new(0, 14, 0, 8),
			Size = UDim2.new(0, 220, 0, 22),
			Text = Strings.get(u.title),
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		Kit.label({
			Position = UDim2.new(0, 14, 0, 32),
			Size = UDim2.new(0, 230, 0, 18),
			Text = Strings.get(u.desc),
			TextSize = 13,
			TextColor3 = T.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local pips = Kit.new("Frame", {
			Position = UDim2.new(0, 250, 0.5, -8),
			Size = UDim2.new(0, 130, 0, 16),
			BackgroundTransparency = 1,
			Parent = row,
		})
		Kit.list(pips, Enum.FillDirection.Horizontal, 4)
		for k = 1, spec.MaxLevel do
			local pip = Kit.new("Frame", {
				Size = UDim2.new(0, 22, 1, 0),
				BackgroundColor3 = if k <= level then u.color else Color3.fromRGB(70, 76, 96),
				BorderSizePixel = 0,
				LayoutOrder = k,
				Parent = pips,
			})
			Kit.corner(pip, 4)
		end
		local maxed = level >= spec.MaxLevel
		local price = if maxed then 0 else CarCatalog.getUpgradePrice(def, u.kind, level + 1)
		Kit.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.new(0, 170, 0, 40),
			Text = if maxed then Strings.get("MaxLevel") else Strings.get("Upgrade", Format.money(price :: number)),
			TextSize = 15,
			BackgroundColor3 = if maxed then T.PanelAlt else T.Good,
			onClick = function()
				if not maxed then
					task.spawn(request, "BuyUpgrade", def.id, u.kind)
				end
			end,
			Parent = row,
		})
	end
end

drawTab = function()
	clearTab()
	for name, b in tabButtons do
		Kit.setButtonColor(b, if name == currentTab then T.Accent else T.Card)
	end
	if currentTab == "Info" then
		drawInfo()
	elseif currentTab == "Paint" then
		drawPaint()
	else
		drawTuning()
	end
end

local function updateActions()
	local def = CarCatalog.get(selectedId)
	if not def then
		return
	end
	local p = profile()
	local isOwned = owned(def.id)
	local spawned = ClientState.car ~= nil and ClientState.car.Parent ~= nil
	local spawnedThis = spawned and (ClientState.car :: Model):GetAttribute("CarId") == def.id
	if isOwned then
		primaryButton.Text = if spawnedThis then Strings.get("Respawn") else Strings.get("Spawn")
		Kit.setButtonColor(primaryButton, T.Good)
	else
		local price = if def.price == 0 then Strings.get("Free") else Format.money(def.price)
		primaryButton.Text = Strings.get("Buy", price)
		local afford = p ~= nil and p.cash >= def.price
		Kit.setButtonColor(primaryButton, if afford then T.Accent else Color3.fromRGB(110, 70, 50))
	end
	secondaryButton.Visible = spawned
	nameLabel.Text = def.name
	local class = CarCatalog.getClass(def.class)
	classLabel.Text = Strings.pick(class.name)
	classLabel.TextColor3 = class.color
end

--------------------------------------------------------------------------------
-- Car list
--------------------------------------------------------------------------------

local function styleCard(id: string)
	local card = cards[id]
	if not card then
		return
	end
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if id == selectedId then T.Accent else Color3.new(1, 1, 1)
		stroke.Transparency = if id == selectedId then 0 else 0.88
		stroke.Thickness = if id == selectedId then 2 else 1
	end
	local def = CarCatalog.get(id)
	local status = card:FindFirstChild("Status") :: TextLabel?
	if def and status then
		if owned(id) then
			local p = profile()
			status.Text = if p and p.selected == id then "✓ " .. Strings.get("Owned") else Strings.get("Owned")
			status.TextColor3 = T.Good
		else
			status.Text = if def.price == 0 then Strings.get("Free") else Format.money(def.price)
			local p = profile()
			status.TextColor3 = if p and p.cash >= def.price then T.Gold else T.Muted
		end
	end
end

local function selectCar(id: string)
	local previous = selectedId
	selectedId = id
	styleCard(previous)
	styleCard(id)
	previewOverride = nil
	refreshPreview()
	updateActions()
	drawTab()
end

local function buildCards()
	for _, c in grid:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	table.clear(cards)
	for i, def in CarCatalog.List do
		if classFilter and def.class ~= classFilter then
			continue
		end
		local class = CarCatalog.getClass(def.class)
		local card = Kit.new("Frame", {
			Name = def.id,
			BackgroundColor3 = T.Card,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = grid,
		})
		Kit.corner(card, 10)
		Kit.stroke(card)
		local strip = Kit.new("Frame", {
			Size = UDim2.new(0, 6, 1, -16),
			Position = UDim2.new(0, 8, 0, 8),
			BackgroundColor3 = class.color,
			BorderSizePixel = 0,
			Parent = card,
		})
		Kit.corner(strip, 3)
		Kit.label({
			Position = UDim2.new(0, 22, 0, 10),
			Size = UDim2.new(1, -30, 0, 24),
			Text = def.name,
			TextSize = 19,
			Font = T.FontBlack,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		Kit.label({
			Position = UDim2.new(0, 22, 0, 34),
			Size = UDim2.new(1, -30, 0, 18),
			Text = Strings.pick(class.name),
			TextSize = 13,
			TextColor3 = class.color,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		Kit.label({
			Name = "Status",
			Position = UDim2.new(0, 22, 1, -30),
			Size = UDim2.new(0.6, 0, 0, 22),
			Text = "",
			TextSize = 16,
			Font = T.FontBlack,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
		local stats = CarCatalog.getEffectiveStats(def, nil)
		local speedHolder = Kit.new("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -12, 1, -16),
			Size = UDim2.new(0.35, 0, 0, 6),
			BackgroundTransparency = 1,
			Parent = card,
		})
		local _, set = Kit.bar(speedHolder, class.color)
		set(CarCatalog.getRatings(stats).speed)
		local hit = Kit.new("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 5,
			Parent = card,
		})
		hit.MouseEnter:Connect(function()
			Kit.tween(card, 0.1, { BackgroundColor3 = T.CardHover })
		end)
		hit.MouseLeave:Connect(function()
			Kit.tween(card, 0.1, { BackgroundColor3 = T.Card })
		end)
		hit.Activated:Connect(function()
			selectCar(def.id)
		end)
		cards[def.id] = card
		styleCard(def.id)
	end
end

local function buildChips()
	local entries = { { id = nil, name = Strings.get("AllClasses"), color = T.Text } }
	for _, c in CarCatalog.Classes do
		table.insert(entries, { id = c.id, name = Strings.pick(c.name), color = c.color })
	end
	for i, e in entries do
		local chip = Kit.button({
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "  " .. e.name .. "  ",
			TextSize = 14,
			Font = T.Font,
			LayoutOrder = i,
			BackgroundColor3 = if e.id == classFilter then T.Accent else T.Card,
			onClick = function()
				classFilter = e.id
				for _, c in chips:GetChildren() do
					if c:IsA("TextButton") then
						Kit.setButtonColor(c, if c:GetAttribute("ClassId") == classFilter then T.Accent else T.Card)
					end
				end
				buildCards()
			end,
			Parent = chips,
		})
		chip:SetAttribute("ClassId", e.id)
		chip.TextColor3 = if e.id then e.color else T.Text
	end
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local function buildWindow()
	gui = Kit.screen("CarsGarage", 10)
	gui.Enabled = false
	Kit.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		Parent = gui,
	})
	window = Kit.panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 1180, 0, 700),
		BackgroundColor3 = T.Bg,
		BackgroundTransparency = 0.04,
		Parent = gui,
	})
	-- header
	Kit.label({
		Position = UDim2.new(0, 22, 0, 12),
		Size = UDim2.new(0, 300, 0, 40),
		Text = Strings.get("GarageTitle"),
		Font = T.FontBlack,
		TextSize = 32,
		TextColor3 = T.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})
	Kit.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.new(0, 44, 0, 40),
		Text = "✕",
		TextSize = 22,
		BackgroundColor3 = T.PanelAlt,
		onClick = function()
			Garage.close()
		end,
		Parent = window,
	})

	-- left: class chips + grid
	chips = Kit.new("ScrollingFrame", {
		Position = UDim2.new(0, 16, 0, 64),
		Size = UDim2.new(0, 540, 0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = window,
	})
	Kit.list(chips, Enum.FillDirection.Horizontal, 6)
	grid = Kit.new("ScrollingFrame", {
		Position = UDim2.new(0, 16, 0, 112),
		Size = UDim2.new(0, 540, 1, -128),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = T.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = window,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0, 260, 0, 92),
		CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	Kit.padding(grid, 2)

	-- right: preview + tabs + actions
	local right = Kit.new("Frame", {
		Position = UDim2.new(0, 572, 0, 64),
		Size = UDim2.new(1, -588, 1, -80),
		BackgroundTransparency = 1,
		Parent = window,
	})
	viewport = Kit.new("ViewportFrame", {
		Size = UDim2.new(1, 0, 0, 270),
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0,
		Ambient = Color3.fromRGB(150, 150, 160),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = right,
	})
	Kit.corner(viewport, 12)
	worldModel = Kit.new("WorldModel", { Parent = viewport })
	camera = Kit.new("Camera", { FieldOfView = 40, Parent = viewport })
	viewport.CurrentCamera = camera
	-- floor disc under the preview
	local floor = Instance.new("Part")
	floor.Shape = Enum.PartType.Cylinder
	floor.Size = Vector3.new(0.4, 40, 40)
	floor.CFrame = CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, math.pi / 2)
	floor.Color = Color3.fromRGB(40, 44, 58)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Anchored = true
	floor.Parent = viewport

	nameLabel = Kit.label({
		Position = UDim2.new(0, 16, 0, 10),
		Size = UDim2.new(1, -32, 0, 36),
		Text = "",
		Font = T.FontBlack,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.6,
		ZIndex = 3,
		Parent = viewport,
	})
	classLabel = Kit.label({
		Position = UDim2.new(0, 18, 0, 44),
		Size = UDim2.new(1, -32, 0, 20),
		Text = "",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.6,
		ZIndex = 3,
		Parent = viewport,
	})

	local tabs = Kit.new("Frame", {
		Position = UDim2.new(0, 0, 0, 280),
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
		Parent = right,
	})
	Kit.list(tabs, Enum.FillDirection.Horizontal, 8)
	for i, name in { "Info", "Paint", "Tuning" } do
		local key = if name == "Info" then "TabCars" elseif name == "Paint" then "TabPaint" else "TabTuning"
		tabButtons[name] = Kit.button({
			Size = UDim2.new(0, 150, 1, 0),
			Text = Strings.get(key),
			TextSize = 16,
			LayoutOrder = i,
			BackgroundColor3 = T.Card,
			onClick = function()
				currentTab = name
				drawTab()
			end,
			Parent = tabs,
		})
	end
	tabContent = Kit.new("Frame", {
		Position = UDim2.new(0, 0, 0, 326),
		Size = UDim2.new(1, 0, 1, -396),
		BackgroundTransparency = 1,
		Parent = right,
	})
	Kit.padding(tabContent, 4)

	primaryButton = Kit.button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.62, -6, 0, 58),
		Text = "",
		TextSize = 22,
		onClick = function()
			local def = CarCatalog.get(selectedId)
			if not def then
				return
			end
			if owned(def.id) then
				local r = request("SpawnCar", def.id)
				if r.ok then
					Garage.close()
				end
			else
				request("BuyCar", def.id)
			end
		end,
		Parent = right,
	})
	secondaryButton = Kit.button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.38, -6, 0, 58),
		Text = Strings.get("Despawn"),
		TextSize = 18,
		BackgroundColor3 = T.PanelAlt,
		onClick = function()
			request("DespawnCar")
			task.wait(0.2)
			updateActions()
		end,
		Parent = right,
	})
end

function Garage.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function Garage.open()
	if not gui then
		return
	end
	local p = profile()
	if ClientState.car and ClientState.car.Parent then
		selectedId = ClientState.car:GetAttribute("CarId") or selectedId
	elseif p and p.selected then
		selectedId = p.selected
	end
	gui.Enabled = true
	window.Size = UDim2.new(0, 1100, 0, 650)
	Kit.tween(window, 0.22, { Size = UDim2.new(0, 1180, 0, 700) }, Enum.EasingStyle.Back)
	buildCards()
	selectCar(selectedId)
end

function Garage.close()
	if gui then
		gui.Enabled = false
	end
end

function Garage.toggle()
	if Garage.isOpen() then
		Garage.close()
	else
		Garage.open()
	end
end

function Garage.init()
	buildWindow()
	buildChips()
end

function Garage.start()
	Hud.GarageRequested:Connect(Garage.toggle)
	ContextActionService:BindAction("CarsGarage", function(_, state)
		if state == Enum.UserInputState.Begin then
			Garage.toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(Config.Keys.Garage))
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Action") == "OpenGarage" then
			Garage.open()
		end
	end)
	ClientState.ProfileChanged:Connect(function()
		if Garage.isOpen() then
			for id in cards do
				styleCard(id)
			end
			refreshPreview()
			updateActions()
			drawTab()
		end
	end)
	ClientState.CarChanged:Connect(function()
		if Garage.isOpen() then
			updateActions()
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if Garage.isOpen() then
			updateCamera(dt)
		end
	end)
end

return Garage
