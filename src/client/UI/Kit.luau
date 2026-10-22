-- Kit: tiny UI toolkit so every screen shares one look (dark glass panels,
-- orange accent, rounded corners) and one way of building instances.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Kit = {}

Kit.Theme = {
	Bg = Color3.fromRGB(14, 17, 26),
	Panel = Color3.fromRGB(20, 24, 36),
	PanelAlt = Color3.fromRGB(28, 33, 48),
	Card = Color3.fromRGB(32, 38, 56),
	CardHover = Color3.fromRGB(42, 50, 72),
	Stroke = Color3.fromRGB(255, 255, 255),
	Accent = Color3.fromRGB(255, 128, 32),
	Accent2 = Color3.fromRGB(70, 196, 255),
	Good = Color3.fromRGB(70, 214, 120),
	Warn = Color3.fromRGB(255, 196, 60),
	Bad = Color3.fromRGB(255, 76, 76),
	Text = Color3.fromRGB(240, 242, 248),
	Muted = Color3.fromRGB(150, 158, 178),
	Gold = Color3.fromRGB(255, 208, 70),
	Silver = Color3.fromRGB(205, 212, 224),
	Bronze = Color3.fromRGB(214, 140, 84),
	Font = Enum.Font.GothamBold,
	FontBlack = Enum.Font.GothamBlack,
	FontMedium = Enum.Font.GothamMedium,
}
local T = Kit.Theme

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

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Kit.new("UIStroke", {
		Color = color or T.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0.85,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
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

-- A dark rounded panel.
function Kit.panel(props: { [string]: any }): Frame
	local p = table.clone(props)
	p.BackgroundColor3 = p.BackgroundColor3 or T.Panel
	p.BackgroundTransparency = p.BackgroundTransparency or 0.08
	p.BorderSizePixel = 0
	local frame = Kit.new("Frame", p)
	Kit.corner(frame, 14)
	Kit.stroke(frame)
	return frame
end

function Kit.label(props: { [string]: any }): TextLabel
	local p = table.clone(props)
	p.BackgroundTransparency = p.BackgroundTransparency or 1
	p.Font = p.Font or T.Font
	p.TextColor3 = p.TextColor3 or T.Text
	p.TextSize = p.TextSize or 18
	p.BorderSizePixel = 0
	if p.TextScaled == nil and p.TextWrapped == nil then
		p.TextTruncate = p.TextTruncate or Enum.TextTruncate.AtEnd
	end
	return Kit.new("TextLabel", p)
end

-- Button with hover/press animation. `onClick` is connected to Activated.
function Kit.button(props: { [string]: any }): TextButton
	local p = table.clone(props)
	local onClick = p.onClick
	local radius = p.cornerRadius
	p.onClick = nil
	p.cornerRadius = nil
	local color = p.BackgroundColor3 or T.Accent
	p.BackgroundColor3 = color
	p.AutoButtonColor = false
	p.Font = p.Font or T.FontBlack
	p.TextColor3 = p.TextColor3 or Color3.new(1, 1, 1)
	p.TextSize = p.TextSize or 18
	p.BorderSizePixel = 0
	local button = Kit.new("TextButton", p)
	Kit.corner(button, radius or 10)
	local scale = Kit.new("UIScale", { Parent = button })
	local hoverColor = color:Lerp(Color3.new(1, 1, 1), 0.12)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = button:GetAttribute("BaseColor") or color }):Play()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.95 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- Big square icon button drawn from frames: drop shadow, gradient body, glossy
-- top highlight, emoji icon, caption and a red badge. `pulse(on)` makes it
-- bounce to ask for attention.
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
	local root = Kit.new("Frame", {
		Name = props.name or "BigButton",
		Size = UDim2.fromOffset(size, size + 4),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Parent = props.parent,
	})
	local shadow = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Parent = root,
	})
	Kit.corner(shadow, math.floor(size * 0.26))
	local button = Kit.new("TextButton", {
		Name = "Button",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		Parent = root,
	})
	Kit.corner(button, math.floor(size * 0.26))
	local gradient = Kit.new("UIGradient", { Rotation = 90, Parent = button })
	local stroke = Kit.stroke(button, Color3.new(1, 1, 1), 2.5, 0.55)
	local function setColor(color: Color3)
		gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.28), color:Lerp(Color3.new(0, 0, 0), 0.22))
		stroke.Color = color:Lerp(Color3.new(1, 1, 1), 0.6)
	end
	setColor(props.color)
	-- glossy highlight on the upper half
	local shine = Kit.new("Frame", {
		Position = UDim2.new(0, 5, 0, 4),
		Size = UDim2.new(1, -10, 0.42, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Parent = button,
	})
	Kit.corner(shine, math.floor(size * 0.2))
	Kit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.2, 1),
		Parent = shine,
	})
	local icon = Kit.label({
		Name = "Icon",
		Position = UDim2.new(0, 0, 0, size * 0.08),
		Size = UDim2.new(1, 0, 0, size * 0.55),
		Text = props.icon,
		TextSize = math.floor(size * 0.46),
		Font = T.FontBlack,
		TextTruncate = Enum.TextTruncate.None,
		Parent = button,
	})
	local caption = Kit.label({
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -6, 0, size * 0.22),
		Text = props.caption,
		TextScaled = true,
		Font = T.FontBlack,
		TextStrokeTransparency = 0.45,
		Parent = button,
	})
	local badge = Kit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = T.Bad,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = root,
	})
	Kit.corner(badge, 13)
	Kit.stroke(badge, Color3.new(1, 1, 1), 2, 0)
	local badgeText = Kit.label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 15, Font = T.FontBlack, ZIndex = 4, Parent = badge })

	local scale = Kit.new("UIScale", { Parent = button })
	local hovered = false
	button.MouseEnter:Connect(function()
		hovered = true
		Kit.tween(scale, 0.12, { Scale = 1.07 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		Kit.tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		Kit.tween(scale, 0.06, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		Kit.tween(scale, 0.18, { Scale = if hovered then 1.07 else 1 }, Enum.EasingStyle.Back)
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
					Kit.tween(icon, 0.35, { Rotation = 12, TextSize = math.floor(size * 0.52) }, Enum.EasingStyle.Sine)
					task.wait(0.35)
					Kit.tween(icon, 0.35, { Rotation = -12 }, Enum.EasingStyle.Sine)
					task.wait(0.35)
					Kit.tween(icon, 0.3, { Rotation = 0, TextSize = math.floor(size * 0.46) }, Enum.EasingStyle.Sine)
					task.wait(0.9)
				end
			end)
		else
			icon.Rotation = 0
			icon.TextSize = math.floor(size * 0.46)
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

-- A small rounded "pill" with an emoji and text (used on cards).
function Kit.pill(parent: Instance, text: string, color: Color3, order: number?): TextLabel
	local pill = Kit.label({
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.15,
		Text = text,
		TextSize = 15,
		Font = T.FontBlack,
		TextTruncate = Enum.TextTruncate.None,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	Kit.corner(pill, 13)
	Kit.padding(pill, 10, 0)
	return pill
end

-- Modal window with a dimmed backdrop, a title bar and a close button.
-- Returns the window frame, its content frame and an open/close function.
function Kit.modal(gui: Instance, name: string, title: string, size: Vector2, accent: Color3?): (Frame, Frame, (open: boolean) -> ())
	local dim = Kit.new("TextButton", {
		Name = name .. "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	local window = Kit.panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 0.02,
		ZIndex = 21,
		Visible = false,
		Parent = gui,
	})
	local scale = Kit.new("UIScale", { Parent = window })
	local header = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = accent or T.Accent,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = window,
	})
	Kit.corner(header, 14)
	Kit.gradient(header, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210), 90)
	Kit.new("Frame", { -- square off the header's bottom corners
		Position = UDim2.new(0, 0, 1, -14),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = accent or T.Accent,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = header,
	})
	Kit.label({
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.new(1, -100, 1, 0),
		Text = title,
		TextSize = 30,
		Font = T.FontBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.6,
		ZIndex = 23,
		Name = "Title",
		Parent = header,
	})
	local content = Kit.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
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
			scale.Scale = 0.85
			Kit.tween(dim, 0.2, { BackgroundTransparency = 0.45 })
			Kit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			Kit.tween(dim, 0.15, { BackgroundTransparency = 1 })
			Kit.tween(scale, 0.15, { Scale = 0.9 })
			task.delay(0.15, function()
				if not isOpen then
					dim.Visible = false
					window.Visible = false
				end
			end)
		end
	end
	local close = Kit.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		Text = "✕",
		TextSize = 24,
		BackgroundColor3 = Color3.fromRGB(30, 34, 48),
		cornerRadius = 23,
		ZIndex = 24,
		onClick = function()
			setOpen(false)
		end,
		Parent = header,
	})
	close.Name = "Close"
	dim.Activated:Connect(function()
		setOpen(false)
	end)
	return window, content, setOpen
end

-- Changes a Kit.button's base color (keeps hover behaviour right).
function Kit.setButtonColor(button: TextButton, color: Color3)
	button:SetAttribute("BaseColor", color)
	button.BackgroundColor3 = color
end

-- Horizontal stat bar 0..10.
function Kit.bar(parent: Instance, color: Color3?): (Frame, (value: number) -> ())
	local back = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = parent,
	})
	Kit.corner(back, 4)
	local fill = Kit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color or T.Accent,
		BorderSizePixel = 0,
		Parent = back,
	})
	Kit.corner(fill, 4)
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
