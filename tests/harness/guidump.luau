-- guidump: serializes a mock ScreenGui tree to JSON for tools/render_ui.py,
-- so UI changes can be looked at as images without Roblox Studio.
--
--   local dump = loadchunk(readfile("tests/harness/guidump.luau"), "@guidump")()
--   writefile("tests/out/ui_hud.json", dump(playerGui, viewportSize))

local function props(inst)
	return rawget(inst, "__props")
end

local function num(v)
	if v ~= v or v == math.huge or v == -math.huge then
		return "0"
	end
	return string.format("%.4g", v)
end

local function str(s)
	s = tostring(s)
	s = string.gsub(s, '[%c"\\]', function(c)
		if c == "\n" then
			return "\\n"
		elseif c == '"' then
			return '\\"'
		elseif c == "\\" then
			return "\\\\"
		end
		return ""
	end)
	return '"' .. s .. '"'
end

local function udim2(u)
	if not u then
		return "null"
	end
	return string.format("[%s,%s,%s,%s]", num(u.XScale or 0), num(u.XOffset or 0), num(u.YScale or 0), num(u.YOffset or 0))
end

local function udim(u)
	if not u then
		return "null"
	end
	return string.format("[%s,%s]", num(u.Scale or 0), num(u.Offset or 0))
end

local function color(c)
	if not c then
		return "null"
	end
	return string.format("[%s,%s,%s]", num(c.R), num(c.G), num(c.B))
end

local function vec2(v)
	if not v then
		return "null"
	end
	return string.format("[%s,%s]", num(v.X), num(v.Y))
end

local function enum(e)
	if e == nil then
		return "null"
	end
	if type(e) == "table" and e.Name then
		return str(e.Name)
	end
	return str(e)
end

local function sequence(seq, isColor)
	if not seq or not seq.Keypoints then
		return "null"
	end
	local out = {}
	for _, k in seq.Keypoints do
		if isColor then
			table.insert(out, string.format("[%s,%s]", num(k.Time), color(k.Value)))
		else
			table.insert(out, string.format("[%s,%s]", num(k.Time), num(k.Value)))
		end
	end
	return "[" .. table.concat(out, ",") .. "]"
end

local GUI = {
	Frame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
	ViewportFrame = true,
	CanvasGroup = true,
}

local function node(inst)
	local p = props(inst)
	local cls = p.ClassName
	local fields = { '"c":' .. str(cls), '"n":' .. str(p.Name) }
	local function add(k, v)
		table.insert(fields, '"' .. k .. '":' .. v)
	end
	add("v", tostring(p.Visible ~= false))
	add("size", udim2(p.Size))
	add("pos", udim2(p.Position))
	add("ap", vec2(p.AnchorPoint))
	add("bg", color(p.BackgroundColor3))
	add("bt", num(p.BackgroundTransparency or 0))
	add("bs", num(p.BorderSizePixel or 1))
	add("bc", color(p.BorderColor3))
	add("z", num(p.ZIndex or 1))
	add("lo", num(p.LayoutOrder or 0))
	add("as", enum(p.AutomaticSize))
	add("clip", tostring(p.ClipsDescendants == true))
	add("rot", num(p.Rotation or 0))
	if cls == "TextLabel" or cls == "TextButton" or cls == "TextBox" then
		add("t", str(p.Text or (if cls == "TextBox" then "" else "Label")))
		add("ts", num(p.TextSize or 14))
		add("tsc", tostring(p.TextScaled == true))
		add("f", enum(p.Font))
		add("tc", color(p.TextColor3))
		add("tt", num(p.TextTransparency or 0))
		add("tst", num(p.TextStrokeTransparency or 1))
		add("tsc3", color(p.TextStrokeColor3))
		add("xa", enum(p.TextXAlignment))
		add("ya", enum(p.TextYAlignment))
		add("tw", tostring(p.TextWrapped == true))
		add("trunc", tostring(p.TextTruncate ~= nil and p.TextTruncate.Name == "AtEnd"))
	end
	if cls == "ScrollingFrame" then
		add("canvas", vec2(p.CanvasPosition))
	end
	if cls == "ViewportFrame" then
		-- the 3D contents, so the renderer can draw previews
		local parts = {}
		for _, d in inst:GetDescendants() do
			local dp = props(d)
			if d:IsA("BasePart") and (dp.Transparency or 0) < 0.99 then
				local shape = "Block"
				if dp.ClassName == "WedgePart" then
					shape = "Wedge"
				elseif dp.Shape then
					shape = dp.Shape.Name
				end
				local comps = { dp.CFrame:GetComponents() }
				for i, v in comps do
					comps[i] = num(v)
				end
				table.insert(
					parts,
					string.format(
						'{"s":"%s","size":[%s,%s,%s],"cf":[%s],"c":%s,"t":%s}',
						shape,
						num(dp.Size.X),
						num(dp.Size.Y),
						num(dp.Size.Z),
						table.concat(comps, ","),
						color(dp.Color),
						num(dp.Transparency or 0)
					)
				)
			end
		end
		local cam = p.CurrentCamera
		local look = if cam then props(cam).CFrame.LookVector else nil
		add("vp", string.format('{"look":%s,"parts":[%s]}', if look then string.format("[%s,%s,%s]", num(look.X), num(look.Y), num(look.Z)) else "null", table.concat(parts, ",")))
	end
	local mods, kids = {}, {}
	for _, child in inst:GetChildren() do
		local cp = props(child)
		local c = cp.ClassName
		if c == "UICorner" then
			table.insert(mods, '"corner":' .. udim(cp.CornerRadius))
		elseif c == "UIStroke" and cp.Enabled ~= false then
			table.insert(
				mods,
				string.format(
					'"stroke":{"c":%s,"th":%s,"t":%s,"mode":%s}',
					color(cp.Color),
					num(cp.Thickness or 1),
					num(cp.Transparency or 0),
					enum(cp.ApplyStrokeMode)
				)
			)
		elseif c == "UIGradient" and cp.Enabled ~= false then
			table.insert(
				mods,
				string.format(
					'"grad":{"cs":%s,"rot":%s,"ts":%s,"off":%s}',
					sequence(cp.Color, true),
					num(cp.Rotation or 0),
					sequence(cp.Transparency, false),
					vec2(cp.Offset)
				)
			)
		elseif c == "UIPadding" then
			table.insert(
				mods,
				string.format('"pad":[%s,%s,%s,%s]', udim(cp.PaddingLeft), udim(cp.PaddingRight), udim(cp.PaddingTop), udim(cp.PaddingBottom))
			)
		elseif c == "UIListLayout" then
			table.insert(
				mods,
				string.format(
					'"list":{"dir":%s,"pad":%s,"ha":%s,"va":%s}',
					enum(cp.FillDirection),
					udim(cp.Padding),
					enum(cp.HorizontalAlignment),
					enum(cp.VerticalAlignment)
				)
			)
		elseif c == "UIGridLayout" then
			table.insert(
				mods,
				string.format(
					'"grid":{"cell":%s,"pad":%s,"ha":%s,"va":%s,"dir":%s}',
					udim2(cp.CellSize),
					udim2(cp.CellPadding),
					enum(cp.HorizontalAlignment),
					enum(cp.VerticalAlignment),
					enum(cp.FillDirection)
				)
			)
		elseif c == "UIScale" then
			table.insert(mods, '"scale":' .. num(cp.Scale or 1))
		elseif c == "UITextSizeConstraint" then
			table.insert(mods, '"maxts":' .. num(cp.MaxTextSize or 100))
			table.insert(mods, '"mints":' .. num(cp.MinTextSize or 1))
		elseif c == "UISizeConstraint" then
			table.insert(mods, '"minsize":' .. vec2(cp.MinSize))
		elseif c == "UIAspectRatioConstraint" then
			table.insert(mods, '"aspect":' .. num(cp.AspectRatio or 1))
		elseif GUI[c] then
			table.insert(kids, node(child))
		end
	end
	for _, m in mods do
		table.insert(fields, m)
	end
	table.insert(fields, '"kids":[' .. table.concat(kids, ",") .. "]")
	return "{" .. table.concat(fields, ",") .. "}"
end

-- Every enabled ScreenGui under `playerGui`, sorted by DisplayOrder.
return function(playerGui, viewport)
	local guis = {}
	for _, g in playerGui:GetChildren() do
		local p = props(g)
		if p.ClassName == "ScreenGui" and p.Enabled ~= false then
			table.insert(guis, g)
		end
	end
	table.sort(guis, function(a, b)
		return (props(a).DisplayOrder or 0) < (props(b).DisplayOrder or 0)
	end)
	local out = {}
	for _, g in guis do
		local scale = 1
		local kids = {}
		for _, child in g:GetChildren() do
			local cp = props(child)
			if cp.ClassName == "UIScale" then
				scale = cp.Scale or 1
			elseif GUI[cp.ClassName] then
				table.insert(kids, node(child))
			end
		end
		table.insert(out, string.format('{"n":%s,"scale":%s,"kids":[%s]}', str(props(g).Name), num(scale), table.concat(kids, ",")))
	end
	return string.format('{"viewport":%s,"guis":[%s]}', vec2(viewport), table.concat(out, ","))
end
