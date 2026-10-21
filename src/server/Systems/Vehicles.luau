-- Vehicles: spawning, seating, ownership and driver actions for player cars.
--
-- Every player owns at most one spawned car. The owner's client simulates it
-- (network owner) with CarPhysics; the server keeps ownership, seats and
-- attributes consistent and validates every action.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarBuilder = require(Shared.CarBuilder)
local CarCatalog = require(Shared.CarCatalog)
local CarPhysics = require(Shared.CarPhysics)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local PlayerData = require(script.Parent.PlayerData)
local World = require(script.Parent.World)

local Vehicles = {}
Vehicles.Spawned = Signal.new() -- (player, model)
Vehicles.Despawned = Signal.new() -- (player)
Vehicles.DriverChanged = Signal.new() -- (player, model, isDriving)

local cars: { [Player]: Model } = {}
local lastSpawn: { [Player]: number } = {}
local lastFlip: { [Player]: number } = {}
local carsFolder: Folder

--------------------------------------------------------------------------------
-- Collision groups
--------------------------------------------------------------------------------

local function setupCollisionGroups()
	for _, name in { "Cars", "Players", "WheelRays" } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	-- wheel rays only see the world (terrain, roads, ramps)
	PhysicsService:CollisionGroupSetCollidable("WheelRays", "Cars", false)
	PhysicsService:CollisionGroupSetCollidable("WheelRays", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("WheelRays", "WheelRays", false)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

function Vehicles.getCar(player: Player): Model?
	local car = cars[player]
	if car and car.Parent then
		return car
	end
	return nil
end

local function humanoidOf(player: Player): Humanoid?
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

function Vehicles.isDriving(player: Player): boolean
	local car = Vehicles.getCar(player)
	local hum = humanoidOf(player)
	if not car or not hum then
		return false
	end
	local seat = car:FindFirstChild("DriveSeat")
	return seat ~= nil and hum.SeatPart == seat
end

local function ownerOf(car: Model): Player?
	return Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0)
end

local function setOwner(car: Model, player: Player?)
	local chassis = car.PrimaryPart
	if not chassis or chassis.Anchored or not chassis:IsDescendantOf(workspace) then
		return
	end
	pcall(function()
		if chassis:CanSetNetworkOwnership() then
			chassis:SetNetworkOwner(player)
		end
	end)
end

local function chassisLocal(car: Model): CFrame
	local stored = car:GetAttribute("ChassisLocal")
	if typeof(stored) == "CFrame" then
		return stored
	end
	return CFrame.new(0, 1.5, 0)
end

-- Places a car so its ground contact sits on `groundCf`.
function Vehicles.placeAt(car: Model, groundCf: CFrame)
	local chassis = car.PrimaryPart
	if not chassis then
		return
	end
	car:PivotTo(groundCf * chassisLocal(car) * CFrame.new(0, 0.6, 0))
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
end

local function padIsFree(cf: CFrame, ignore: Model?): boolean
	for _, car in carsFolder:GetChildren() do
		if car ~= ignore and car:IsA("Model") and car.PrimaryPart then
			if (car.PrimaryPart.Position - cf.Position).Magnitude < 20 then
				return false
			end
		end
	end
	return true
end

local function findSpawn(player: Player): CFrame?
	local pads = World.Layout.SpawnPads
	local origin = Vector3.zero
	local char = player.Character
	if char and char.PrimaryPart then
		origin = char.PrimaryPart.Position
	end
	local order = table.clone(pads)
	table.sort(order, function(a, b)
		return (a.Position - origin).Magnitude < (b.Position - origin).Magnitude
	end)
	for _, cf in order do
		if padIsFree(cf, nil) then
			return cf
		end
	end
	return nil
end

local function applyStats(car: Model, player: Player)
	local data = PlayerData.get(player)
	local def = CarCatalog.get(car:GetAttribute("CarId"))
	if not data or not def then
		return
	end
	local save = data.cars[def.id]
	CarPhysics.writeStats(car, CarCatalog.getEffectiveStats(def, save))
end

-- Re-applies paint/upgrades after a purchase in the garage.
function Vehicles.refresh(player: Player)
	local car = Vehicles.getCar(player)
	local data = PlayerData.get(player)
	if not car or not data then
		return
	end
	local id = car:GetAttribute("CarId")
	local save = data.cars[id]
	if save then
		CarBuilder.applyPaint(car, save)
	end
	applyStats(car, player)
end

--------------------------------------------------------------------------------
-- Seats
--------------------------------------------------------------------------------

local function seatPlayer(player: Player, seat: Seat | VehicleSeat): boolean
	local hum = humanoidOf(player)
	if not hum or seat.Occupant then
		return false
	end
	local root = (player.Character :: Model).PrimaryPart
	if not root or (root.Position - seat.Position).Magnitude > 40 then
		return false
	end
	if hum.SeatPart then
		local weld = hum.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	seat:Sit(hum)
	return true
end

local function exitSeat(player: Player)
	local hum = humanoidOf(player)
	if not hum or not hum.SeatPart then
		return
	end
	local seat = hum.SeatPart
	local car = seat:FindFirstAncestorOfClass("Model")
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	hum.Sit = false
	-- step out beside the car instead of on its roof
	local char = player.Character
	if char and car and car.PrimaryPart then
		local size = car:GetExtentsSize()
		local side = if seat.CFrame:PointToObjectSpace(car.PrimaryPart.Position).X > 0 then -1 else 1
		local out = seat.CFrame * CFrame.new(side * (size.X / 2 + 3), 0, 0)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { car, char }
		local hit = workspace:Raycast(out.Position + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), params)
		local y = if hit then hit.Position.Y else out.Position.Y
		local look = car.PrimaryPart.CFrame.LookVector
		local pos = Vector3.new(out.Position.X, y + 3.5, out.Position.Z)
		task.defer(function()
			if char.Parent then
				char:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z)))
			end
		end)
	end
end
Vehicles.exitSeat = exitSeat

local function wireCar(car: Model, owner: Player)
	local driveSeat = car:FindFirstChild("DriveSeat") :: VehicleSeat?
	if driveSeat then
		driveSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occ = driveSeat.Occupant
			if occ then
				local p = Players:GetPlayerFromCharacter(occ.Parent)
				if p ~= owner then
					-- only the owner may drive
					local weld = driveSeat:FindFirstChild("SeatWeld")
					if weld then
						weld:Destroy()
					end
					return
				end
				setOwner(car, owner)
				Vehicles.DriverChanged:Fire(owner, car, true)
			else
				Vehicles.DriverChanged:Fire(owner, car, false)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------

function Vehicles.despawn(player: Player)
	local car = cars[player]
	cars[player] = nil
	if car then
		-- free anyone sitting inside first
		for _, seat in car:GetChildren() do
			if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
				local weld = seat:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy()
				end
			end
		end
		car:Destroy()
		Vehicles.Despawned:Fire(player)
	end
end

export type SpawnResult = { ok: boolean, message: string?, args: { any }? }

function Vehicles.spawn(player: Player, carId: string): SpawnResult
	local data = PlayerData.get(player)
	local def = CarCatalog.get(carId)
	if not data or not def then
		return { ok = false }
	end
	if not data.owned[def.id] then
		return { ok = false, message = "NotOwned" }
	end
	local now = os.clock()
	local wait = Config.SpawnCooldown - (now - (lastSpawn[player] or -math.huge))
	if wait > 0 then
		return { ok = false, message = "SpawnCooldown", args = { math.ceil(wait) } }
	end

	local old = cars[player]
	local pad = findSpawn(player)
	if not pad then
		-- re-use our own pad slot if the old car was blocking one
		if old then
			for _, cf in World.Layout.SpawnPads do
				if padIsFree(cf, old) then
					pad = cf
					break
				end
			end
		end
		if not pad then
			return { ok = false, message = "NoSpawnSpace" }
		end
	end
	lastSpawn[player] = now
	Vehicles.despawn(player)

	local save = data.cars[def.id] or CarCatalog.defaultSave(def)
	local car = CarBuilder.build(def, { save = save, ownerName = player.DisplayName })
	car.Name = player.Name .. "_" .. def.id
	car:SetAttribute("OwnerUserId", player.UserId)
	car:SetAttribute("ChassisLocal", (car.PrimaryPart :: BasePart).CFrame)
	car:SetAttribute("Lights", true)
	car:SetAttribute("Siren", false)
	car:SetAttribute("Nitro", false)
	CarPhysics.writeStats(car, CarCatalog.getEffectiveStats(def, save))
	car.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	Vehicles.placeAt(car, pad)
	car.Parent = carsFolder
	CollectionService:AddTag(car, "Car")
	cars[player] = car
	setOwner(car, player)
	wireCar(car, player)

	PlayerData.update(player, function(p)
		p.selected = def.id
	end)
	Vehicles.Spawned:Fire(player, car)

	-- jump straight in
	local seat = car:FindFirstChild("DriveSeat") :: VehicleSeat?
	if seat then
		task.defer(function()
			if car.Parent then
				seatPlayer(player, seat)
			end
		end)
	end
	return { ok = true, message = "Spawned", args = { def.name } }
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local function flip(player: Player)
	local car = Vehicles.getCar(player)
	if not car or not car.PrimaryPart or car.PrimaryPart.Anchored then
		return
	end
	local now = os.clock()
	if now - (lastFlip[player] or -math.huge) < Config.FlipCooldown then
		return
	end
	lastFlip[player] = now
	local chassis = car.PrimaryPart
	local look = chassis.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.1 then
		flatLook = Vector3.new(0, 0, -1)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car }
	for _, p in Players:GetPlayers() do
		if p.Character then
			params:AddToFilter(p.Character)
		end
	end
	local origin = chassis.Position + Vector3.new(0, 30, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
	local groundY = if hit then hit.Position.Y else chassis.Position.Y - 2
	local pos = Vector3.new(chassis.Position.X, groundY, chassis.Position.Z)
	Vehicles.placeAt(car, CFrame.lookAt(pos, pos + flatLook) * CFrame.new(0, 1.5, 0))
	Net.notify(player, "Flipped", {}, "info")
end

local function onVehicleAction(player: Player, action: any, value: any)
	if typeof(action) ~= "string" then
		return
	end
	local car = Vehicles.getCar(player)
	if action == "Exit" then
		exitSeat(player)
		return
	end
	if not car then
		return
	end
	local driving = Vehicles.isDriving(player)
	if action == "Flip" then
		flip(player)
	elseif action == "Lights" and driving then
		car:SetAttribute("Lights", not car:GetAttribute("Lights"))
	elseif action == "Siren" and driving and car:GetAttribute("HasSiren") then
		car:SetAttribute("Siren", not car:GetAttribute("Siren"))
	elseif action == "Horn" and driving then
		car:SetAttribute("Horn", (car:GetAttribute("Horn") or 0) + 1)
	elseif action == "Nitro" and driving then
		car:SetAttribute("Nitro", value == true)
	end
end

local function onPrompt(prompt: ProximityPrompt, player: Player)
	if prompt.Name ~= "SitPrompt" then
		return
	end
	local seat = prompt.Parent
	if not seat or not (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
		return
	end
	local car = seat:FindFirstAncestorOfClass("Model")
	if not car or not CollectionService:HasTag(car, "Car") then
		return
	end
	if seat.Name == "DriveSeat" and car:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end
	seatPlayer(player, seat :: any)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Vehicles.init()
	setupCollisionGroups()
	local existing = workspace:FindFirstChild("Cars")
	if existing then
		existing:Destroy()
	end
	carsFolder = Instance.new("Folder")
	carsFolder.Name = "Cars"
	carsFolder.Parent = workspace

	Net.handle("SpawnCar", function(player, carId)
		if typeof(carId) ~= "string" then
			return { ok = false }
		end
		return Vehicles.spawn(player, carId)
	end)
	Net.handle("DespawnCar", function(player)
		Vehicles.despawn(player)
		return { ok = true, message = "CarParked" }
	end)
	Net.onEvent("VehicleAction", onVehicleAction, 12)
	ProximityPromptService.PromptTriggered:Connect(onPrompt)
end

function Vehicles.start()
	Players.PlayerRemoving:Connect(function(player)
		Vehicles.despawn(player)
		lastSpawn[player] = nil
		lastFlip[player] = nil
	end)

	-- housekeeping: void rescue and network ownership
	task.spawn(function()
		while true do
			task.wait(1)
			for player, car in cars do
				local chassis = car.PrimaryPart
				if not car.Parent or not chassis then
					cars[player] = nil
					continue
				end
				if chassis.Position.Y < Config.VoidY then
					local pad = findSpawn(player) or World.Layout.SpawnPads[1]
					Vehicles.placeAt(car, pad)
					Net.notify(player, "Rescued", {}, "warning")
				end
				if not chassis.Anchored then
					local ok, owner = pcall(chassis.GetNetworkOwner, chassis)
					if ok and owner ~= player then
						setOwner(car, player)
					end
				end
			end
		end
	end)
end

Vehicles.ownerOf = ownerOf
Vehicles.setOwner = setOwner

return Vehicles
