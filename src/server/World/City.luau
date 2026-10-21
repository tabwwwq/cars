-- City: downtown blocks between the street grid — sidewalks, skyscrapers,
-- small parks and parking lots. Deterministic, so every server matches.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(script.Parent.Build)
local Layout = require(ReplicatedStorage:WaitForChild("CarsShared"):WaitForChild("WorldLayout"))

local City = {}

local TOP = Layout.RoadTop
local SIDEWALK_TOP = TOP + 0.25

local FACADES = {
	{ wall = Color3.fromRGB(196, 190, 176), glass = Color3.fromRGB(60, 90, 120), mat = Enum.Material.Concrete },
	{ wall = Color3.fromRGB(150, 74, 56), glass = Color3.fromRGB(40, 50, 64), mat = Enum.Material.Brick },
	{ wall = Color3.fromRGB(70, 96, 130), glass = Color3.fromRGB(120, 170, 210), mat = Enum.Material.Glass },
	{ wall = Color3.fromRGB(44, 46, 54), glass = Color3.fromRGB(90, 140, 180), mat = Enum.Material.SmoothPlastic },
	{ wall = Color3.fromRGB(226, 226, 222), glass = Color3.fromRGB(50, 70, 100), mat = Enum.Material.SmoothPlastic },
	{ wall = Color3.fromRGB(176, 150, 110), glass = Color3.fromRGB(40, 60, 80), mat = Enum.Material.Sandstone },
}

local function building(parent: Instance, rng: Random, cx: number, cz: number, w: number, d: number, h: number)
	local style = FACADES[rng:NextInteger(1, #FACADES)]
	local model = Instance.new("Model")
	model.Name = "Building"
	local base = Build.box(model, Vector3.new(w, h, d), CFrame.new(cx, SIDEWALK_TOP + h / 2, cz), style.wall, style.mat, "Tower")
	base.CastShadow = true
	-- window bands wrap all four sides with one slightly larger box each
	local floorH = 12
	local y = SIDEWALK_TOP + 10
	while y < SIDEWALK_TOP + h - 6 do
		Build.part(model, {
			size = Vector3.new(w + 0.3, 4.5, d + 0.3),
			cframe = CFrame.new(cx, y, cz),
			color = style.glass,
			material = Enum.Material.Glass,
			reflectance = 0.2,
			collide = false,
			shadow = false,
			name = "Windows",
		})
		y += floorH
	end
	-- ground floor shop front
	Build.part(model, {
		size = Vector3.new(w + 0.4, 6, d + 0.4),
		cframe = CFrame.new(cx, SIDEWALK_TOP + 3.2, cz),
		color = Color3.fromRGB(30, 34, 42),
		material = Enum.Material.Glass,
		reflectance = 0.25,
		collide = false,
		name = "ShopFront",
	})
	-- roof: parapet and a few machines
	Build.box(model, Vector3.new(w + 0.6, 1.6, d + 0.6), CFrame.new(cx, SIDEWALK_TOP + h + 0.8, cz), style.wall:Lerp(Color3.new(0, 0, 0), 0.2), style.mat)
	for _ = 1, rng:NextInteger(1, 3) do
		local sx, sz = rng:NextNumber(4, 10), rng:NextNumber(4, 10)
		local px = cx + rng:NextNumber(-w / 2 + sx, w / 2 - sx)
		local pz = cz + rng:NextNumber(-d / 2 + sz, d / 2 - sz)
		Build.box(model, Vector3.new(sx, rng:NextNumber(2, 6), sz), CFrame.new(px, SIDEWALK_TOP + h + 2.5, pz), Color3.fromRGB(150, 152, 158), Enum.Material.Metal)
	end
	if h > 140 then
		-- antenna with a blinking-looking red tip
		Build.pole(model, Vector3.new(cx, SIDEWALK_TOP + h + 1.6, cz), 26, 0.6, Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		Build.ball(model, 1.6, Vector3.new(cx, SIDEWALK_TOP + h + 28, cz), Color3.fromRGB(255, 40, 40), Enum.Material.Neon).CanCollide = false
	end
	model.PrimaryPart = base
	model.Parent = parent
end

local function park(parent: Instance, rng: Random, cx: number, cz: number, w: number, d: number, treeSpots: { Vector3 })
	Build.box(parent, Vector3.new(w, 0.4, d), CFrame.new(cx, SIDEWALK_TOP + 0.05, cz), Color3.fromRGB(80, 140, 70), Enum.Material.Grass, "Park")
	for _ = 1, 6 do
		table.insert(treeSpots, Vector3.new(cx + rng:NextNumber(-w / 2 + 8, w / 2 - 8), SIDEWALK_TOP + 0.25, cz + rng:NextNumber(-d / 2 + 8, d / 2 - 8)))
	end
	-- fountain
	Build.cylinder(parent, 1.4, 22, CFrame.new(cx, SIDEWALK_TOP + 0.7, cz) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(190, 190, 186), Enum.Material.Concrete)
	Build.cylinder(parent, 0.2, 19, CFrame.new(cx, SIDEWALK_TOP + 1.35, cz) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 150, 220), Enum.Material.Glass).CanCollide = false
	Build.pole(parent, Vector3.new(cx, SIDEWALK_TOP + 1, cz), 5, 1.4, Color3.fromRGB(190, 190, 186), Enum.Material.Concrete)
end

local function parking(parent: Instance, cx: number, cz: number, w: number, d: number)
	Build.box(parent, Vector3.new(w, 0.3, d), CFrame.new(cx, SIDEWALK_TOP + 0.02, cz), Color3.fromRGB(64, 66, 72), Enum.Material.Asphalt, "Parking")
	local n = math.floor((w - 10) / 12)
	for i = 0, n do
		local x = cx - w / 2 + 5 + i * 12
		for _, side in { -1, 1 } do
			Build.part(parent, {
				size = Vector3.new(0.4, 0.05, d / 2 - 12),
				cframe = CFrame.new(x, SIDEWALK_TOP + 0.2, cz + side * (d / 4 + 3)),
				color = Color3.fromRGB(235, 235, 230),
				collide = false,
				shadow = false,
			})
		end
	end
end

-- Returns tree positions for the Decor builder.
function City.build(root: Instance): { Vector3 }
	local folder = Build.folder("City", root)
	local rng = Build.rng(1337)
	local xs, zs = Layout.CityX, Layout.CityZ
	local sw = Layout.CityStreetWidth
	local trees: { Vector3 } = {}
	local function halfWidth(x: number): number
		return (if x == 0 then 44 else sw) / 2
	end
	for i = 1, #xs - 1 do
		for j = 1, #zs - 1 do
			local x0, x1 = xs[i] + halfWidth(xs[i]), xs[i + 1] - halfWidth(xs[i + 1])
			local z1, z0 = zs[j] - sw / 2, zs[j + 1] + sw / 2 -- z decreases northwards
			local bw, bd = x1 - x0, z1 - z0
			local bcx, bcz = (x0 + x1) / 2, (z0 + z1) / 2
			-- sidewalk slab
			Build.box(folder, Vector3.new(bw, 1, bd), CFrame.new(bcx, SIDEWALK_TOP - 0.5, bcz), Color3.fromRGB(190, 188, 182), Enum.Material.Concrete, "Sidewalk")
			-- 2x2 lots
			local lotW, lotD = (bw - 24) / 2, (bd - 24) / 2
			local distToCenter = math.abs(bcx) + math.abs(bcz + 975) * 0.6
			for li = 0, 1 do
				for lj = 0, 1 do
					local lcx = x0 + 12 + lotW / 2 + li * lotW
					local lcz = z0 + 12 + lotD / 2 + lj * lotD
					local roll = rng:NextNumber()
					if roll < 0.12 then
						park(folder, rng, lcx, lcz, lotW - 6, lotD - 6, trees)
					elseif roll < 0.2 then
						parking(folder, lcx, lcz, lotW - 6, lotD - 6)
					else
						local w = lotW * rng:NextNumber(0.62, 0.9)
						local d = lotD * rng:NextNumber(0.62, 0.9)
						local tall = math.clamp(1 - distToCenter / 1100, 0.15, 1)
						local h = math.floor(rng:NextNumber(30, 60) + tall * rng:NextNumber(40, 170))
						building(folder, rng, lcx, lcz, w, d, h)
					end
				end
			end
			-- street trees on the sidewalk corners
			for _, cx in { x0 + 5, x1 - 5 } do
				for _, cz in { z0 + 5, z1 - 5 } do
					table.insert(trees, Vector3.new(cx, SIDEWALK_TOP, cz))
				end
			end
		end
	end
	return trees
end

return City
