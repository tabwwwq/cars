-- Minimal Roblox API mock so shared modules can be loaded and tested outside Studio.
-- Implements the datatypes the game code uses (Vector3, CFrame, Color3, ...),
-- a property-bag Instance tree, Enum tokens and a tiny module loader that
-- mirrors the Rojo layout (script.Parent works like in Studio).

local M = {}

local function typeName(v)
	local mt = getmetatable(v)
	if type(v) == "table" and type(mt) == "table" and rawget(mt, "__type") then
		return rawget(mt, "__type")
	end
	return type(v)
end
M.typeof = typeName

--------------------------------------------------------------------------------
-- Vector3
--------------------------------------------------------------------------------
local Vector3 = {}
local V3mt = { __type = "Vector3" }
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt)
end
Vector3.new = v3
V3mt.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif k == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(self.X / m, self.Y / m, self.Z / m)
	end
	return Vector3[k]
end
V3mt.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3mt.__tostring = function(a)
	return string.format("%.3f, %.3f, %.3f", a.X, a.Y, a.Z)
end
function Vector3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3.Lerp(a, b, t)
	return a + (b - a) * t
end
function Vector3.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function Vector3.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function Vector3.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function Vector3.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return (a - b).Magnitude <= eps
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
M.Vector3 = Vector3

local Vector2 = {}
local V2mt = { __type = "Vector2" }
V2mt.__index = function(self, k)
	if k == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y)
	end
	return Vector2[k]
end
function Vector2.new(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2mt)
end
V2mt.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
V2mt.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
V2mt.__mul = function(a, b)
	if type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
Vector2.zero = Vector2.new(0, 0)
M.Vector2 = Vector2

--------------------------------------------------------------------------------
-- CFrame (rotation matrix stored row-major: r00 r01 r02 / r10 r11 r12 / r20 r21 r22)
--------------------------------------------------------------------------------
local CFrame = {}
local CFmt = { __type = "CFrame" }
local function cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return setmetatable({
		x = x,
		y = y,
		z = z,
		r00 = r00,
		r01 = r01,
		r02 = r02,
		r10 = r10,
		r11 = r11,
		r12 = r12,
		r20 = r20,
		r21 = r21,
		r22 = r22,
	}, CFmt)
end

function CFrame.new(...)
	local n = select("#", ...)
	local a = { ... }
	if n == 0 then
		return cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 1 then
		local p = a[1]
		return cf(p.X, p.Y, p.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 2 then
		return CFrame.lookAt(a[1], a[2])
	elseif n == 3 then
		return cf(a[1], a[2], a[3], 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 7 then
		-- quaternion form
		local x, y, z, qx, qy, qz, qw = a[1], a[2], a[3], a[4], a[5], a[6], a[7]
		return cf(
			x,
			y,
			z,
			1 - 2 * (qy * qy + qz * qz),
			2 * (qx * qy - qz * qw),
			2 * (qx * qz + qy * qw),
			2 * (qx * qy + qz * qw),
			1 - 2 * (qx * qx + qz * qz),
			2 * (qy * qz - qx * qw),
			2 * (qx * qz - qy * qw),
			2 * (qy * qz + qx * qw),
			1 - 2 * (qx * qx + qy * qy)
		)
	elseif n == 12 then
		return cf(table.unpack(a))
	end
	error("CFrame.new: unsupported argument count " .. n)
end

local function mulRot(a, b)
	return a.r00 * b.r00 + a.r01 * b.r10 + a.r02 * b.r20,
		a.r00 * b.r01 + a.r01 * b.r11 + a.r02 * b.r21,
		a.r00 * b.r02 + a.r01 * b.r12 + a.r02 * b.r22,
		a.r10 * b.r00 + a.r11 * b.r10 + a.r12 * b.r20,
		a.r10 * b.r01 + a.r11 * b.r11 + a.r12 * b.r21,
		a.r10 * b.r02 + a.r11 * b.r12 + a.r12 * b.r22,
		a.r20 * b.r00 + a.r21 * b.r10 + a.r22 * b.r20,
		a.r20 * b.r01 + a.r21 * b.r11 + a.r22 * b.r21,
		a.r20 * b.r02 + a.r21 * b.r12 + a.r22 * b.r22
end

local function rotVec(c, v)
	return v3(
		c.r00 * v.X + c.r01 * v.Y + c.r02 * v.Z,
		c.r10 * v.X + c.r11 * v.Y + c.r12 * v.Z,
		c.r20 * v.X + c.r21 * v.Y + c.r22 * v.Z
	)
end

local function rotVecT(c, v)
	return v3(
		c.r00 * v.X + c.r10 * v.Y + c.r20 * v.Z,
		c.r01 * v.X + c.r11 * v.Y + c.r21 * v.Z,
		c.r02 * v.X + c.r12 * v.Y + c.r22 * v.Z
	)
end

local function rx(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function ry(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rz(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end

function CFrame.Angles(x, y, z)
	return rx(x) * ry(y) * rz(z)
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(x, y, z)
	return ry(y) * rx(x) * rz(z)
end
function CFrame.fromOrientation(x, y, z)
	return ry(y) * rx(x) * rz(z)
end

function CFrame.fromAxisAngle(axis, angle)
	local u = axis.Unit
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	local x, y, z = u.X, u.Y, u.Z
	return cf(
		0,
		0,
		0,
		t * x * x + c,
		t * x * y - s * z,
		t * x * z + s * y,
		t * x * y + s * z,
		t * y * y + c,
		t * y * z - s * x,
		t * x * z - s * y,
		t * y * z + s * x,
		t * z * z + c
	)
end

function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cf(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end

function CFrame.lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(v3(0, 0, 1))
		if right.Magnitude < 1e-6 then
			right = look:Cross(v3(1, 0, 0))
		end
	end
	right = right.Unit
	local upv = right:Cross(look).Unit
	return CFrame.fromMatrix(at, right, upv, -look)
end

CFrame.identity = cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)

CFmt.__mul = function(a, b)
	if typeName(b) == "Vector3" then
		local r = rotVec(a, b)
		return v3(r.X + a.x, r.Y + a.y, r.Z + a.z)
	end
	local p = rotVec(a, v3(b.x, b.y, b.z))
	return cf(p.X + a.x, p.Y + a.y, p.Z + a.z, mulRot(a, b))
end
CFmt.__add = function(a, v)
	return cf(a.x + v.X, a.y + v.Y, a.z + v.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
CFmt.__sub = function(a, v)
	return cf(a.x - v.X, a.y - v.Y, a.z - v.Z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
end
CFmt.__tostring = function(a)
	return string.format("CFrame(%.2f, %.2f, %.2f)", a.x, a.y, a.z)
end

local CFmethods = {}
function CFmethods.Inverse(a)
	local p = rotVecT(a, v3(-a.x, -a.y, -a.z))
	return cf(p.X, p.Y, p.Z, a.r00, a.r10, a.r20, a.r01, a.r11, a.r21, a.r02, a.r12, a.r22)
end
function CFmethods.ToObjectSpace(a, b)
	return a:Inverse() * b
end
function CFmethods.ToWorldSpace(a, b)
	return a * b
end
function CFmethods.PointToWorldSpace(a, v)
	return a * v
end
function CFmethods.PointToObjectSpace(a, v)
	return rotVecT(a, v3(v.X - a.x, v.Y - a.y, v.Z - a.z))
end
function CFmethods.VectorToWorldSpace(a, v)
	return rotVec(a, v)
end
function CFmethods.VectorToObjectSpace(a, v)
	return rotVecT(a, v)
end
function CFmethods.GetComponents(a)
	return a.x, a.y, a.z, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22
end
CFmethods.components = CFmethods.GetComponents
function CFmethods.Lerp(a, b, t)
	-- good enough for tests: lerp position, take b's rotation past halfway
	local p = v3(a.x, a.y, a.z):Lerp(v3(b.x, b.y, b.z), t)
	local r = if t < 0.5 then a else b
	return cf(p.X, p.Y, p.Z, r.r00, r.r01, r.r02, r.r10, r.r11, r.r12, r.r20, r.r21, r.r22)
end
function CFmethods.ToEulerAnglesXYZ(a)
	local y = math.asin(math.clamp(a.r02, -1, 1))
	local x = math.atan2(-a.r12, a.r22)
	local z = math.atan2(-a.r01, a.r00)
	return x, y, z
end
function CFmethods.ToEulerAnglesYXZ(a)
	local x = math.asin(math.clamp(-a.r12, -1, 1))
	local y = math.atan2(a.r02, a.r22)
	local z = math.atan2(a.r10, a.r11)
	return x, y, z
end
CFmethods.ToOrientation = CFmethods.ToEulerAnglesYXZ
function CFmethods.ToAxisAngle(a)
	local angle = math.acos(math.clamp((a.r00 + a.r11 + a.r22 - 1) / 2, -1, 1))
	local axis = v3(a.r21 - a.r12, a.r02 - a.r20, a.r10 - a.r01)
	if axis.Magnitude < 1e-9 then
		return v3(0, 1, 0), 0
	end
	return axis.Unit, angle
end

CFmt.__index = function(a, k)
	if k == "Position" or k == "p" then
		return v3(a.x, a.y, a.z)
	elseif k == "X" then
		return a.x
	elseif k == "Y" then
		return a.y
	elseif k == "Z" then
		return a.z
	elseif k == "LookVector" then
		return v3(-a.r02, -a.r12, -a.r22)
	elseif k == "RightVector" or k == "XVector" then
		return v3(a.r00, a.r10, a.r20)
	elseif k == "UpVector" or k == "YVector" then
		return v3(a.r01, a.r11, a.r21)
	elseif k == "ZVector" then
		return v3(a.r02, a.r12, a.r22)
	elseif k == "Rotation" then
		return cf(0, 0, 0, a.r00, a.r01, a.r02, a.r10, a.r11, a.r12, a.r20, a.r21, a.r22)
	end
	return CFmethods[k]
end
M.CFrame = CFrame

--------------------------------------------------------------------------------
-- Color3 and friends
--------------------------------------------------------------------------------
local Color3 = {}
local C3mt = { __type = "Color3" }
C3mt.__index = Color3
C3mt.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then
		return Color3.new(v, t, p)
	elseif i == 1 then
		return Color3.new(q, v, p)
	elseif i == 2 then
		return Color3.new(p, v, t)
	elseif i == 3 then
		return Color3.new(p, q, v)
	elseif i == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end
function Color3.fromHex(hex)
	hex = hex:gsub("#", "")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end
function Color3.Lerp(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function Color3.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then
			h = ((g - b) / d) % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h = h / 6
	end
	return h, if max == 0 then 0 else d / max, max
end
M.Color3 = Color3

local function simpleType(name, fields)
	local T = {}
	local mt = { __type = name }
	mt.__index = T
	function T.new(...)
		local args = { ... }
		local o = {}
		for i, f in fields do
			o[f] = args[i]
		end
		return setmetatable(o, mt)
	end
	return T
end

M.UDim = simpleType("UDim", { "Scale", "Offset" })
local UDim2 = simpleType("UDim2", { "XScale", "XOffset", "YScale", "YOffset" })
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
M.UDim2 = UDim2
M.NumberRange = simpleType("NumberRange", { "Min", "Max" })
M.NumberSequence = simpleType("NumberSequence", { "Keypoints" })
M.NumberSequenceKeypoint = simpleType("NumberSequenceKeypoint", { "Time", "Value", "Envelope" })
M.ColorSequence = simpleType("ColorSequence", { "Keypoints" })
M.ColorSequenceKeypoint = simpleType("ColorSequenceKeypoint", { "Time", "Value" })
M.PhysicalProperties = simpleType("PhysicalProperties", { "Density", "Friction", "Elasticity", "FrictionWeight", "ElasticityWeight" })
M.TweenInfo = simpleType("TweenInfo", { "Time", "EasingStyle", "EasingDirection" })
M.Rect = simpleType("Rect", { "Min", "Max" })
M.Font = simpleType("Font", { "Family", "Weight", "Style" })
function M.Font.fromEnum(e)
	return M.Font.new(e)
end

--------------------------------------------------------------------------------
-- Enum
--------------------------------------------------------------------------------
local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, enumName)
		local e = enumCache[enumName]
		if not e then
			local items = {}
			e = setmetatable({}, {
				__index = function(_, itemName)
					local item = items[itemName]
					if not item then
						item = setmetatable({ Name = itemName, EnumType = enumName }, {
							__type = "EnumItem",
							__tostring = function()
								return "Enum." .. enumName .. "." .. itemName
							end,
						})
						items[itemName] = item
					end
					return item
				end,
			})
			enumCache[enumName] = e
		end
		return e
	end,
})
M.Enum = Enum

--------------------------------------------------------------------------------
-- Signals
--------------------------------------------------------------------------------
local function newSignal()
	local s = { handlers = {} }
	function s:Connect(fn)
		local conn = { Connected = true }
		self.handlers[conn] = fn
		function conn.Disconnect()
			conn.Connected = false
			s.handlers[conn] = nil
		end
		return conn
	end
	s.Once = s.Connect
	function s:Fire(...)
		for _, fn in self.handlers do
			fn(...)
		end
	end
	function s:Wait()
		return nil
	end
	return s
end
M.newSignal = newSignal

--------------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------------
local classParents = {
	Part = "BasePart",
	WedgePart = "BasePart",
	CornerWedgePart = "BasePart",
	MeshPart = "BasePart",
	TrussPart = "BasePart",
	Seat = "BasePart",
	VehicleSeat = "BasePart",
	SpawnLocation = "Part",
	BasePart = "PVInstance",
	Model = "PVInstance",
	WorldModel = "Model",
	Workspace = "Model",
	SpotLight = "Light",
	PointLight = "Light",
	SurfaceLight = "Light",
	Script = "LuaSourceContainer",
	LocalScript = "Script",
	ModuleScript = "LuaSourceContainer",
	TextLabel = "GuiObject",
	TextButton = "GuiButton",
	ImageButton = "GuiButton",
	GuiButton = "GuiObject",
	ImageLabel = "GuiObject",
	Frame = "GuiObject",
	ScrollingFrame = "GuiObject",
	ViewportFrame = "GuiObject",
	CanvasGroup = "GuiObject",
	TextBox = "GuiObject",
	GuiObject = "GuiBase2d",
	ScreenGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	LayerCollector = "GuiBase2d",
	Weld = "JointInstance",
	Motor6D = "JointInstance",
	WeldConstraint = "Constraint",
	RemoteEvent = "BaseRemoteEvent",
	UnreliableRemoteEvent = "BaseRemoteEvent",
}

local function isA(className, target)
	local c = className
	while c do
		if c == target then
			return true
		end
		c = classParents[c]
	end
	return target == "Instance"
end

local Instance = {}
local Imt = { __type = "Instance" }
local defaults = {
	BasePart = function(o)
		o.Size = v3(4, 1, 2)
		o.CFrame = CFrame.new()
		o.Anchored = false
		o.CanCollide = true
		o.Transparency = 0
		o.Massless = false
		o.Color = Color3.fromRGB(163, 162, 165)
	end,
}

local methods = {}

function Instance.new(className, parent)
	local o = {
		__props = { ClassName = className, Name = className },
		__children = {},
		__attrs = {},
		__signals = {},
	}
	setmetatable(o, Imt)
	local c = className
	while c do
		if defaults[c] then
			defaults[c](o)
		end
		c = classParents[c]
	end
	if parent then
		o.Parent = parent
	end
	return o
end

Imt.__index = function(self, k)
	local props = rawget(self, "__props")
	local v = props[k]
	if v ~= nil then
		return v
	end
	if k == "Position" and props.CFrame and isA(props.ClassName, "BasePart") then
		return props.CFrame.Position
	end
	if k == "Orientation" then
		return v3(0, 0, 0)
	end
	if k == "AssemblyMass" or k == "Mass" then
		local s = props.Size or v3(1, 1, 1)
		local density = if props.CustomPhysicalProperties then props.CustomPhysicalProperties.Density else 0.7
		return s.X * s.Y * s.Z * density
	end
	if k == "AssemblyCenterOfMass" then
		return props.CFrame.Position
	end
	if k == "AssemblyLinearVelocity" or k == "AssemblyAngularVelocity" then
		return v3(0, 0, 0)
	end
	if methods[k] then
		return methods[k]
	end
	-- child lookup like Roblox (instance.ChildName)
	for _, child in rawget(self, "__children") do
		if child.Name == k then
			return child
		end
	end
	-- unknown events
	local signals = rawget(self, "__signals")
	if string.match(k, "^[A-Z]") and (k:match("ed$") or k:match("^On") or k == "Triggered") then
		signals[k] = signals[k] or newSignal()
		return signals[k]
	end
	return nil
end

Imt.__newindex = function(self, k, v)
	local props = rawget(self, "__props")
	if k == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "__children")
			for i, c in list do
				if c == self then
					table.remove(list, i)
					break
				end
			end
		end
		props.Parent = v
		if v then
			table.insert(rawget(v, "__children"), self)
		end
		return
	end
	if k == "Position" and isA(props.ClassName, "BasePart") then
		local c = props.CFrame or CFrame.new()
		props.CFrame = c - c.Position + v
		return
	end
	props[k] = v
end

Imt.__tostring = function(self)
	return self.Name
end

function methods.IsA(self, className)
	return isA(self.ClassName, className)
end
function methods.GetChildren(self)
	return table.clone(rawget(self, "__children"))
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(o)
		for _, c in rawget(o, "__children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	for _, c in rawget(self, "__children") do
		if c.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in rawget(self, "__children") do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
methods.WaitForChild = methods.FindFirstChild
function methods.FindFirstChildOfClass(self, className)
	for _, c in rawget(self, "__children") do
		if c.ClassName == className then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, className, recursive)
	for _, c in rawget(self, "__children") do
		if c:IsA(className) then
			return c
		end
	end
	if recursive then
		for _, c in rawget(self, "__children") do
			local f = c:FindFirstChildWhichIsA(className, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods.FindFirstAncestorWhichIsA(self, className)
	local p = self.Parent
	while p do
		if p:IsA(className) then
			return p
		end
		p = p.Parent
	end
	return nil
end
function methods.FindFirstAncestorOfClass(self, className)
	local p = self.Parent
	while p do
		if p.ClassName == className then
			return p
		end
		p = p.Parent
	end
	return nil
end
function methods.IsDescendantOf(self, other)
	local p = self.Parent
	while p do
		if p == other then
			return true
		end
		p = p.Parent
	end
	return false
end
function methods.Destroy(self)
	self.Parent = nil
	for _, c in methods.GetChildren(self) do
		c:Destroy()
	end
end
function methods.ClearAllChildren(self)
	for _, c in methods.GetChildren(self) do
		c:Destroy()
	end
end
function methods.Clone(self)
	local o = Instance.new(self.ClassName)
	for k, v in rawget(self, "__props") do
		if k ~= "Parent" then
			rawget(o, "__props")[k] = v
		end
	end
	for k, v in rawget(self, "__attrs") do
		rawget(o, "__attrs")[k] = v
	end
	for _, c in rawget(self, "__children") do
		c:Clone().Parent = o
	end
	return o
end
function methods.SetAttribute(self, k, v)
	rawget(self, "__attrs")[k] = v
end
function methods.GetAttribute(self, k)
	return rawget(self, "__attrs")[k]
end
function methods.GetAttributes(self)
	return table.clone(rawget(self, "__attrs"))
end
function methods.GetAttributeChangedSignal(self, k)
	return newSignal()
end
function methods.GetPropertyChangedSignal(self, k)
	return newSignal()
end
function methods.AddTag(self, tag)
	rawget(self, "__attrs")["__tag_" .. tag] = true
end
function methods.HasTag(self, tag)
	return rawget(self, "__attrs")["__tag_" .. tag] == true
end
function methods.GetFullName(self)
	local parts = {}
	local o = self
	while o do
		table.insert(parts, 1, o.Name)
		o = o.Parent
	end
	return table.concat(parts, ".")
end
-- PVInstance / Model
function methods.GetPivot(self)
	if self:IsA("BasePart") then
		return self.CFrame
	end
	local pp = self.PrimaryPart
	if pp then
		return pp.CFrame
	end
	return CFrame.new()
end
function methods.PivotTo(self, target)
	local current = methods.GetPivot(self)
	local delta = target * current:Inverse()
	if self:IsA("BasePart") then
		self.CFrame = target
		return
	end
	for _, d in methods.GetDescendants(self) do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end
function methods.GetBoundingBox(self)
	local minV, maxV
	for _, d in methods.GetDescendants(self) do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			minV = if minV then minV:Min(p) else p
			maxV = if maxV then maxV:Max(p) else p
		end
	end
	if not minV then
		return CFrame.new(), v3(0, 0, 0)
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end
function methods.ApplyImpulse() end
function methods.ApplyAngularImpulse() end
function methods.SetNetworkOwner() end
function methods.GetNetworkOwner()
	return nil
end
function methods.CanSetNetworkOwnership()
	return true
end
function methods.Play() end
function methods.Stop() end
function methods.Emit() end

M.Instance = Instance

--------------------------------------------------------------------------------
-- Services / globals
--------------------------------------------------------------------------------
function M.makeGame()
	local game = Instance.new("DataModel")
	game.Name = "Game"
	local services = {}
	local function service(name)
		local s = services[name]
		if not s then
			s = Instance.new(name)
			s.Name = name
			s.Parent = game
			services[name] = s
		end
		return s
	end
	rawget(game, "__props").GetService = function(_, name)
		return service(name)
	end
	local workspace = service("Workspace")
	workspace.Gravity = 196.2
	rawget(workspace, "__props").Raycast = function()
		return nil
	end
	rawget(workspace, "__props").GetServerTimeNow = function()
		return os.time()
	end
	local terrain = Instance.new("Terrain")
	terrain.Name = "Terrain"
	terrain.Parent = workspace
	for _, fn in { "FillBlock", "FillBall", "FillCylinder", "FillWedge", "Clear" } do
		rawget(terrain, "__props")[fn] = function() end
	end
	local players = service("Players")
	rawget(players, "__props").GetPlayers = function()
		return {}
	end
	local runService = service("RunService")
	rawget(runService, "__props").IsStudio = function()
		return true
	end
	rawget(runService, "__props").IsServer = function()
		return true
	end
	rawget(runService, "__props").IsClient = function()
		return false
	end
	local cs = service("CollectionService")
	rawget(cs, "__props").AddTag = function(_, inst, tag)
		inst:AddTag(tag)
	end
	rawget(cs, "__props").HasTag = function(_, inst, tag)
		return inst:HasTag(tag)
	end
	rawget(cs, "__props").GetTagged = function()
		return {}
	end
	local ps = service("PhysicsService")
	rawget(ps, "__props").RegisterCollisionGroup = function() end
	rawget(ps, "__props").CollisionGroupSetCollidable = function() end
	rawget(ps, "__props").IsCollisionGroupRegistered = function()
		return false
	end
	return game, workspace
end

-- Module loader that understands `script.Parent.X` the Rojo way.
function M.makeLoader(env)
	local cache = {}
	local function makeTree(root, dirPath, className)
		-- builds ModuleScript instances for a directory (non-recursive listing is given by caller)
		return root
	end
	local loader = {}
	function loader.module(parent, name, path)
		local inst = Instance.new("ModuleScript")
		inst.Name = name
		rawget(inst, "__props").__path = path
		inst.Parent = parent
		return inst
	end
	function loader.require(inst)
		if cache[inst] ~= nil then
			return cache[inst]
		end
		local path = rawget(inst, "__props").__path
		assert(path, "require: not a mocked ModuleScript " .. tostring(inst))
		local src = readfile(path)
		assert(src, "cannot read " .. path)
		local menv = setmetatable({ script = inst }, { __index = env })
		local fn = loadchunk(src, "@" .. path, menv)
		local result = fn()
		cache[inst] = result
		return result
	end
	return loader
end

-- Builds a global environment with all mocks installed.
function M.environment()
	local game, workspace = M.makeGame()
	local env = setmetatable({}, { __index = _G })
	env.game = game
	env.workspace = workspace
	env.Workspace = workspace
	env.Vector3 = Vector3
	env.Vector2 = Vector2
	env.CFrame = CFrame
	env.Color3 = Color3
	env.UDim = M.UDim
	env.UDim2 = M.UDim2
	env.NumberRange = M.NumberRange
	env.NumberSequence = M.NumberSequence
	env.NumberSequenceKeypoint = M.NumberSequenceKeypoint
	env.ColorSequence = M.ColorSequence
	env.ColorSequenceKeypoint = M.ColorSequenceKeypoint
	env.PhysicalProperties = M.PhysicalProperties
	env.TweenInfo = M.TweenInfo
	env.Rect = M.Rect
	env.Font = M.Font
	env.Enum = Enum
	env.Instance = Instance
	env.typeof = typeName
	env.task = {
		spawn = function(f, ...)
			return f(...)
		end,
		defer = function(f, ...)
			return f(...)
		end,
		delay = function() end,
		wait = function()
			return 0
		end,
	}
	env.tick = os.clock
	env.time = os.clock
	env.warn = function(...)
		print("WARN:", ...)
	end
	local loader = M.makeLoader(env)
	env.require = function(x)
		return loader.require(x)
	end
	return env, loader, game
end

return M
