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
