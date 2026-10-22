-- Kit: the UI toolkit every screen is built with, so the whole game shares one
-- look: chunky "toy" style like the best Roblox games. Deep-blue panels with a
-- thick ink outline, vivid 3D buttons (gradient face, glossy highlight and a
-- darker lip underneath that the face sinks into when pressed), rounded
-- FredokaOne text with an outline, emoji icons on drawn tiles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Strings = require(ReplicatedStorage:WaitForChild("CarsShared"):WaitForChild("Strings"))

local Kit = {}

-- FredokaOne has no Cyrillic letters (Roblox would mix in a fallback font), so
-- Russian uses the heavy Gotham cut; both read as chunky and round.
local HEADLINE = if Strings.Language == "ru" then Enum.Font.GothamBlack else Enum.Font.FredokaOne

Kit.Theme = {
	Bg = Color3.fromRGB(12, 18, 38),
	Panel = Color3.fromRGB(30, 42, 82), -- panel bottom
	PanelTop = Color3.fromRGB(48, 66, 124), -- panel top
	PanelAlt = Color3.fromRGB(44, 60, 112),
	Card = Color3.fromRGB(42, 58, 108),
	CardTop = Color3.fromRGB(58, 78, 142),
	CardHover = Color3.fromRGB(62, 84, 152),
	Ink = Color3.fromRGB(10, 14, 32), -- outlines
	Stroke = Color3.fromRGB(10, 14, 32),
	Accent = Color3.fromRGB(255, 138, 28),
	Accent2 = Color3.fromRGB(48, 170, 255),
	Good = Color3.fromRGB(52, 200, 84),
	Warn = Color3.fromRGB(255, 194, 36),
	Bad = Color3.fromRGB(236, 56, 70),
	Purple = Color3.fromRGB(150, 90, 245),
	Pink = Color3.fromRGB(240, 80, 170),
	Teal = Color3.fromRGB(24, 196, 170),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(170, 186, 228),
	Gold = Color3.fromRGB(255, 212, 56),
	Silver = Color3.fromRGB(205, 214, 230),
	Bronze = Color3.fromRGB(222, 140, 80),
	Disabled = Color3.fromRGB(120, 130, 156),
	Font = HEADLINE,
	FontBlack = HEADLINE,
	FontMedium = Enum.Font.GothamBold,
}
local T = Kit.Theme

local WHITE = Color3.new(1, 1, 1)
local LIP = 5 -- depth of 3D buttons in pixels

-- Kit.new("Frame", { Size = ..., Parent = ... }, { children })
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.corner(parent: Instance, radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

-- Border outline around a frame (thick ink by default).
function Kit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Kit.new("UIStroke", {
		Color = color or T.Ink,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Outline around the letters of a text object.
function Kit.outline(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return Kit.new("UIStroke", {
		Color = color or T.Ink,
		Thickness = thickness or 2,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

function Kit.padding(parent: Instance, px: number, py: number?): UIPadding
	return Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, py or px),
		PaddingBottom = UDim.new(0, py or px),
		Parent = parent,
	})
end

function Kit.list(parent: Instance, direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return Kit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Kit.gradient(parent: Instance, a: Color3, b: Color3, rotation: number?): UIGradient
	return Kit.new("UIGradient", {
		Color = ColorSequence.new(a, b),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

-- Light/dark variants of a colour for gradients and button lips.
function Kit.shades(color: Color3): (Color3, Color3, Color3)
	local top = color:Lerp(WHITE, 0.32)
	local lip = color:Lerp(Color3.new(0, 0, 0), 0.42)
	return top, color, lip
end

-- A deep-blue rounded panel with an ink outline.
function Kit.panel(props: { [string]: any }): Frame
	local p = table.clone(props)
	local base = p.BackgroundColor3 or T.Panel
	p.BackgroundColor3 = WHITE
	p.BackgroundTransparency = p.BackgroundTransparency or 0.04
	p.BorderSizePixel = 0
	local frame = Kit.new("Frame", p)
	Kit.corner(frame, 16)
	Kit.stroke(frame, T.Ink, 3, 0)
	local top = if base == T.Panel then T.PanelTop else base:Lerp(WHITE, 0.18)
	Kit.gradient(frame, top, base, 90)
	return frame
end

function Kit.label(props: { [string]: any }): TextLabel
	local p = table.clone(props)
	local outline = p.outline
	p.outline = nil
	p.BackgroundTransparency = p.BackgroundTransparency or 1
	p.Font = p.Font or T.Font
	p.TextColor3 = p.TextColor3 or T.Text
	p.TextSize = p.TextSize or 18
	p.BorderSizePixel = 0
	if p.TextScaled == nil and p.TextWrapped == nil then
		p.TextTruncate = p.TextTruncate or Enum.TextTruncate.AtEnd
	end
	local maxSize = p.maxTextSize
	p.maxTextSize = nil
	local label = Kit.new("TextLabel", p)
	if outline then
		Kit.outline(label, if typeof(outline) == "number" then outline else 2)
	end
	if maxSize then
		Kit.new("UITextSizeConstraint", { MaxTextSize = maxSize, Parent = label })
	end
	return label
end

-- Paints the face and lip of a 3D button in `color`.
local function paintButton(button: GuiObject, color: Color3)
	local face = button:FindFirstChild("Face") :: Frame?
	local lip = button:FindFirstChild("Lip") :: Frame?
	local top, mid, dark = Kit.shades(color)
	if face then
		local g = face:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(top, mid)
		end
	end
	if lip then
		lip.BackgroundColor3 = dark
	end
end

-- 3D button: gradient face with a glossy highlight over a darker lip and an
-- ink outline. The TextButton itself only catches input; its Text/TextSize/
-- TextColor3/Font are mirrored onto the visible label, so callers use it like
-- a normal TextButton. `onClick` is connected to Activated.
function Kit.button(props: { [string]: any }): TextButton
	local p = table.clone(props)
	local onClick = p.onClick
	local radius = p.cornerRadius or 12
	local color = p.BackgroundColor3 or T.Accent
	local faceTransparency = p.BackgroundTransparency or 0
	p.onClick = nil
	p.cornerRadius = nil
	p.BackgroundColor3 = color
	p.BackgroundTransparency = 1
	p.AutoButtonColor = false
	p.Font = p.Font or T.FontBlack
	p.TextColor3 = p.TextColor3 or WHITE
	p.TextSize = p.TextSize or 20
	p.TextTransparency = 1
	p.BorderSizePixel = 0
	local button = Kit.new("TextButton", p)
	button:SetAttribute("BaseColor", color)

	local lip = Kit.new("Frame", {
		Name = "Lip",
		Position = UDim2.fromOffset(0, LIP),
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundTransparency = faceTransparency,
		ZIndex = -2,
		Parent = button,
	})
	Kit.corner(lip, radius)
	Kit.stroke(lip, T.Ink, 2.5, faceTransparency)
	local face = Kit.new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = faceTransparency,
		BorderSizePixel = 0,
		ZIndex = -1,
		Parent = button,
	})
	Kit.corner(face, radius)
	Kit.stroke(face, T.Ink, 2.5, faceTransparency)
	Kit.new("UIGradient", { Rotation = 90, Parent = face })
	local shine = Kit.new("Frame", {
		Name = "Shine",
		Position = UDim2.new(0, 4, 0, 3),
		Size = UDim2.new(1, -8, 0.42, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = if faceTransparency > 0.5 then 1 else 0.72,
		BorderSizePixel = 0,
		Parent = face,
	})
	Kit.corner(shine, math.max(2, radius - 3))
	Kit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.1, 1), Parent = shine })
	local label = Kit.new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		BackgroundTransparency = 1,
		Text = button.Text,
		TextSize = button.TextSize,
		TextColor3 = button.TextColor3,
		Font = button.Font,
		TextScaled = button.TextScaled,
		TextWrapped = button.TextWrapped,
		TextXAlignment = button.TextXAlignment,
		Parent = face,
	})
	Kit.outline(label, 2)
	paintButton(button, color)
	for _, prop in { "Text", "TextSize", "TextColor3", "Font", "TextScaled", "TextWrapped", "TextXAlignment" } do
		button:GetPropertyChangedSignal(prop):Connect(function()
			(label :: any)[prop] = (button :: any)[prop]
		end)
	end
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		paintButton(button, button.BackgroundColor3)
	end)

	-- hover grows a little, pressing sinks the face into the lip
	local scale = Kit.new("UIScale", { Parent = button })
	local function sink(down: boolean)
		local y = if down then LIP - 1 else 0
		TweenService:Create(face, TweenInfo.new(0.06), { Position = UDim2.fromOffset(0, y) }):Play()
	end
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1.04 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		sink(false)
	end)
	button.MouseButton1Down:Connect(function()
		sink(true)
	end)
	button.MouseButton1Up:Connect(function()
		sink(false)
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- Changes a Kit.button's colour.
function Kit.setButtonColor(button: TextButton, color: Color3)
	button:SetAttribute("BaseColor", color)
	button.BackgroundColor3 = color
	paintButton(button, color)
end

-- A drawn gold coin with a "$" (used next to every price).
function Kit.coin(parent: Instance, size: number, props: { [string]: any }?): Frame
	local p = table.clone(props or {})
	p.Size = p.Size or UDim2.fromOffset(size, size)
	p.BackgroundColor3 = WHITE
	p.BorderSizePixel = 0
	p.Parent = parent
	local coin = Kit.new("Frame", p)
	coin.Name = p.Name or "Coin"
	Kit.corner(coin, size)
	Kit.stroke(coin, T.Ink, math.max(2, size / 14), 0)
	Kit.gradient(coin, Color3.fromRGB(255, 236, 120), Color3.fromRGB(240, 160, 20), 90)
	local inner = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		BackgroundColor3 = Color3.fromRGB(255, 196, 40),
		BorderSizePixel = 0,
		Parent = coin,
	})
	Kit.corner(inner, size)
	Kit.stroke(inner, Color3.fromRGB(200, 120, 0), math.max(1, size / 24), 0.2)
	Kit.label({
		Size = UDim2.fromScale(1, 1),
		Text = "$",
		TextScaled = true,
		TextColor3 = WHITE,
		outline = math.max(1, size / 18),
		Parent = inner,
	})
	return coin
end

-- Big square tile for the side rail: drop shadow, lip, gradient face with a
-- glossy top, a large emoji icon, the caption on a ribbon over the bottom edge
-- and a red badge. `setPulse(true)` makes the icon wiggle for attention.
export type BigButton = {
	root: Frame,
	button: TextButton,
	icon: TextLabel,
	caption: TextLabel,
	setBadge: (count: number?) -> (),
	setPulse: (on: boolean) -> (),
	setColor: (color: Color3) -> (),
}

function Kit.bigButton(props: {
	icon: string,
	caption: string,
	color: Color3,
	size: number?,
	onClick: (() -> ())?,
	parent: Instance?,
	layoutOrder: number?,
	name: string?,
}): BigButton
	local size = props.size or 78
	local radius = math.floor(size * 0.24)
	local root = Kit.new("Frame", {
		Name = props.name or "BigButton",
		Size = UDim2.fromOffset(size, size + LIP + 8),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Parent = props.parent,
	})
	local lip = Kit.new("Frame", {
		Name = "Lip",
		Position = UDim2.fromOffset(0, LIP),
		Size = UDim2.fromOffset(size, size),
		BorderSizePixel = 0,
		Parent = root,
	})
	Kit.corner(lip, radius)
	Kit.stroke(lip, T.Ink, 3, 0)
	local button = Kit.new("TextButton", {
		Name = "Button",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		Parent = root,
	})
	Kit.corner(button, radius)
	Kit.stroke(button, T.Ink, 3, 0)
	local gradient = Kit.new("UIGradient", { Rotation = 90, Parent = button })
	local shine = Kit.new("Frame", {
		Position = UDim2.new(0, 5, 0, 4),
		Size = UDim2.new(1, -10, 0.45, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.68,
		BorderSizePixel = 0,
		Parent = button,
	})
	Kit.corner(shine, radius - 4)
	Kit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1), Parent = shine })
	local function setColor(color: Color3)
		local top, mid, dark = Kit.shades(color)
		gradient.Color = ColorSequence.new(top, mid)
		lip.BackgroundColor3 = dark
	end
	setColor(props.color)
	-- icon with a soft drop shadow
	local iconSize = math.floor(size * 0.5)
	Kit.label({
		Name = "IconShadow",
		Position = UDim2.new(0, 2, 0, size * 0.1 + 3),
		Size = UDim2.new(1, 0, 0, size * 0.56),
		Text = props.icon,
		TextSize = iconSize,
		TextColor3 = Color3.new(0, 0, 0),
		TextTransparency = 0.75,
		TextTruncate = Enum.TextTruncate.None,
		Parent = button,
	})
	local icon = Kit.label({
		Name = "Icon",
		Position = UDim2.new(0, 0, 0, size * 0.1),
		Size = UDim2.new(1, 0, 0, size * 0.56),
		Text = props.icon,
		TextSize = iconSize,
		TextTruncate = Enum.TextTruncate.None,
		Parent = button,
	})
	local caption = Kit.label({
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -size * 0.12),
		Size = UDim2.new(1, 10, 0, size * 0.27),
		Text = props.caption,
		TextScaled = true,
		Font = T.FontBlack,
		outline = 2,
		Parent = button,
	})
	local badge = Kit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = root,
	})
	Kit.corner(badge, 14)
	Kit.stroke(badge, T.Ink, 2.5, 0)
	Kit.gradient(badge, Color3.fromRGB(255, 110, 110), T.Bad, 90)
	local badgeText = Kit.label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 16, ZIndex = 4, outline = 1.5, Parent = badge })

	local scale = Kit.new("UIScale", { Parent = root })
	local hovered = false
	local function sink(down: boolean)
		local y = if down then LIP - 1 else 0
		Kit.tween(button, 0.06, { Position = UDim2.fromOffset(0, y) })
	end
	button.MouseEnter:Connect(function()
		hovered = true
		Kit.tween(scale, 0.12, { Scale = 1.06 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		Kit.tween(scale, 0.12, { Scale = 1 })
		sink(false)
	end)
	button.MouseButton1Down:Connect(function()
		sink(true)
	end)
	button.MouseButton1Up:Connect(function()
		sink(false)
		Kit.tween(scale, 0.18, { Scale = if hovered then 1.06 else 1 }, Enum.EasingStyle.Back)
	end)
	if props.onClick then
		button.Activated:Connect(props.onClick)
	end

	local pulsing = false
	local function setPulse(on: boolean)
		if on == pulsing then
			return
		end
		pulsing = on
		if on then
			task.spawn(function()
				while pulsing and root.Parent do
					Kit.tween(icon, 0.3, { Rotation = 14, TextSize = math.floor(size * 0.58) }, Enum.EasingStyle.Sine)
					task.wait(0.3)
					Kit.tween(icon, 0.3, { Rotation = -14 }, Enum.EasingStyle.Sine)
					task.wait(0.3)
					Kit.tween(icon, 0.25, { Rotation = 0, TextSize = iconSize }, Enum.EasingStyle.Sine)
					task.wait(0.9)
				end
			end)
		else
			icon.Rotation = 0
			icon.TextSize = iconSize
		end
	end
	local function setBadge(count: number?)
		badge.Visible = count ~= nil and count > 0
		badgeText.Text = if count and count > 9 then "9+" else tostring(count or "")
	end
	return {
		root = root,
		button = button,
		icon = icon,
		caption = caption,
		setBadge = setBadge,
		setPulse = setPulse,
		setColor = setColor,
	}
end

-- A card inside a panel: lighter blue gradient, rounded, ink outline.
function Kit.card(props: { [string]: any }): Frame
	local p = table.clone(props)
	local base = p.BackgroundColor3 or T.Card
	p.BackgroundColor3 = WHITE
	p.BorderSizePixel = 0
	local frame = Kit.new("Frame", p)
	Kit.corner(frame, 16)
	Kit.stroke(frame, T.Ink, 2.5, 0)
	local top = if base == T.Card then T.CardTop else base:Lerp(WHITE, 0.25)
	Kit.gradient(frame, top, base, 90)
	return frame
end

-- A rounded colour tile with an emoji on it (icons on cards and windows).
function Kit.iconTile(parent: Instance, icon: string, color: Color3, size: number, props: { [string]: any }?): Frame
	local p = table.clone(props or {})
	p.Size = p.Size or UDim2.fromOffset(size, size)
	p.BackgroundColor3 = WHITE
	p.BorderSizePixel = 0
	p.Parent = parent
	local tile = Kit.new("Frame", p)
	Kit.corner(tile, math.floor(size * 0.28))
	Kit.stroke(tile, T.Ink, math.max(2, size / 24), 0)
	local top, mid = Kit.shades(color)
	Kit.gradient(tile, top, mid, 90)
	local shine = Kit.new("Frame", {
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(1, -6, 0.45, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Parent = tile,
	})
	Kit.corner(shine, math.floor(size * 0.22))
	Kit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1), Parent = shine })
	Kit.label({
		Name = "Icon",
		Size = UDim2.fromScale(1, 1),
		Text = icon,
		TextSize = math.floor(size * 0.58),
		TextTruncate = Enum.TextTruncate.None,
		Parent = tile,
	})
	return tile
end

-- A small rounded "pill" with an emoji and text (used on cards).
function Kit.pill(parent: Instance, text: string, color: Color3, order: number?): TextLabel
	local pill = Kit.label({
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		Text = text,
		TextSize = 16,
		Font = T.FontBlack,
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = order or 0,
		outline = 1.5,
		Parent = parent,
	})
	Kit.corner(pill, 14)
	Kit.padding(pill, 10, 0)
	local top = color:Lerp(WHITE, 0.25)
	Kit.gradient(pill, top, color, 90)
	return pill
end

-- Modal window: dimmed backdrop, deep-blue body with an ink outline, a
-- coloured header ribbon with the title and a red 3D close button sitting on
-- the corner. Returns the window, its content frame and an open/close function.
function Kit.modal(gui: Instance, name: string, title: string, size: Vector2, accent: Color3?): (Frame, Frame, (open: boolean) -> ())
	local color = accent or T.Accent
	local dim = Kit.new("TextButton", {
		Name = name .. "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(4, 8, 20),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	local window = Kit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 21,
		Visible = false,
		Parent = gui,
	})
	Kit.corner(window, 22)
	Kit.stroke(window, T.Ink, 4, 0)
	Kit.gradient(window, T.PanelTop, T.Panel, 90)
	local scale = Kit.new("UIScale", { Parent = window })
	-- header ribbon
	local header = Kit.new("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 62),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = window,
	})
	Kit.corner(header, 16)
	Kit.stroke(header, T.Ink, 3, 0)
	local top, mid = Kit.shades(color)
	Kit.gradient(header, top, mid, 90)
	local headerShine = Kit.new("Frame", {
		Position = UDim2.new(0, 6, 0, 4),
		Size = UDim2.new(1, -12, 0.45, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		Parent = header,
	})
	Kit.corner(headerShine, 12)
	Kit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1), Parent = headerShine })
	Kit.label({
		Name = "Title",
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(1, -100, 1, 0),
		Text = title,
		TextSize = 34,
		Font = T.FontBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
		outline = 3,
		ZIndex = 23,
		Parent = header,
	})
	local content = Kit.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -80),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = window,
	})
	local isOpen = false
	local function setOpen(open: boolean)
		if open == isOpen then
			return
		end
		isOpen = open
		if open then
			dim.Visible = true
			window.Visible = true
			scale.Scale = 0.8
			Kit.tween(dim, 0.2, { BackgroundTransparency = 0.4 })
			Kit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			Kit.tween(dim, 0.15, { BackgroundTransparency = 1 })
			Kit.tween(scale, 0.15, { Scale = 0.85 })
			task.delay(0.15, function()
				if not isOpen then
					dim.Visible = false
					window.Visible = false
				end
			end)
		end
	end
	Kit.button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(54, 50),
		Text = "✖",
		TextSize = 26,
		BackgroundColor3 = T.Bad,
		cornerRadius = 14,
		ZIndex = 30,
		onClick = function()
			setOpen(false)
		end,
		Parent = window,
	})
	dim.Activated:Connect(function()
		setOpen(false)
	end)
	return window, content, setOpen
end

-- Horizontal stat bar 0..10 with an ink outline.
function Kit.bar(parent: Instance, color: Color3?): (Frame, (value: number) -> ())
	local back = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = Color3.fromRGB(18, 26, 52),
		BorderSizePixel = 0,
		Parent = parent,
	})
	Kit.corner(back, 6)
	Kit.stroke(back, T.Ink, 2, 0)
	local fill = Kit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = back,
	})
	Kit.corner(fill, 6)
	local c = color or T.Accent
	Kit.gradient(fill, c:Lerp(WHITE, 0.3), c, 90)
	local function set(value: number)
		TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(value / 10, 0, 1), 1) })
			:Play()
	end
	return back, set
end

-- ScreenGui with a UIScale that adapts to the screen size.
function Kit.screen(name: string, displayOrder: number?): (ScreenGui, UIScale)
	local player = Players.LocalPlayer
	local gui = Kit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local scale = Kit.new("UIScale", { Parent = gui })
	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local vp = camera.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / 1500, vp.Y / 860), 0.38, 1.35)
	end
	update()
	local function watch()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
	end
	watch()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watch()
		update()
	end)
	return gui, scale
end

function Kit.tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

return Kit
