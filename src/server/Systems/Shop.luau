-- Shop: buying cars, upgrades, paint and the daily reward. Every request is
-- validated here; prices come from the shared catalog/config, never the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarCatalog = require(Shared.CarCatalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Net = require(Shared.Net)
local Paints = require(Shared.Paints)

local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)

local Shop = {}

local DAY = 86400

local function needMore(player: Player, price: number)
	local data = PlayerData.get(player)
	local missing = price - (if data then data.cash else 0)
	return { ok = false, message = "NotEnoughCash", args = { Format.money(missing) } }
end

function Shop.buyCar(player: Player, carId: any)
	local data = PlayerData.get(player)
	local def = CarCatalog.get(carId)
	if not data or not def then
		return { ok = false }
	end
	if data.owned[def.id] then
		return { ok = false, message = "AlreadyOwned" }
	end
	if not PlayerData.spend(player, def.price, "car:" .. def.id) then
		return needMore(player, def.price)
	end
	PlayerData.update(player, function(p)
		p.owned[def.id] = true
		p.cars[def.id] = p.cars[def.id] or CarCatalog.defaultSave(def)
		p.selected = def.id
	end)
	return { ok = true, message = "Purchased", args = { def.name } }
end

local UPGRADE_FIELD = { Engine = "engine", Tires = "tires", Nitro = "nitro" }

function Shop.buyUpgrade(player: Player, carId: any, kind: any)
	local data = PlayerData.get(player)
	local def = CarCatalog.get(carId)
	if not data or not def or typeof(kind) ~= "string" then
		return { ok = false }
	end
	local field = UPGRADE_FIELD[kind]
	local spec = (Config.Upgrades :: any)[kind]
	if not field or not spec then
		return { ok = false }
	end
	if not data.owned[def.id] then
		return { ok = false, message = "NotOwned" }
	end
	local save = data.cars[def.id]
	local level = (save :: any)[field] :: number
	if level >= spec.MaxLevel then
		return { ok = false, message = "MaxLevel" }
	end
	local price = CarCatalog.getUpgradePrice(def, kind, level + 1) :: number
	if not PlayerData.spend(player, price, "upgrade:" .. kind) then
		return needMore(player, price)
	end
	PlayerData.update(player, function(p)
		local s = p.cars[def.id] :: any
		s[field] = level + 1
	end)
	Vehicles.refresh(player)
	return { ok = true, message = "Upgraded", args = { "Upgrade" .. (if kind == "Nitro" then "Nitro" else kind), level + 1 } }
end

-- slot: "paint" | "accent" | "rim" | "glow" | "finish"
function Shop.setPaint(player: Player, carId: any, slot: any, value: any)
	local data = PlayerData.get(player)
	local def = CarCatalog.get(carId)
	if not data or not def or typeof(slot) ~= "string" then
		return { ok = false }
	end
	if not data.owned[def.id] then
		return { ok = false, message = "NotOwned" }
	end
	local save = data.cars[def.id]
	local cust = Config.Customization
	local price = 0
	local apply: (any) -> ()

	if slot == "paint" or slot == "accent" or slot == "rim" then
		if not Paints.isValidIndex(value) then
			return { ok = false }
		end
		if (save :: any)[slot] == value then
			return { ok = true }
		end
		price = if slot == "paint" then cust.PaintPrice elseif slot == "accent" then cust.AccentPrice else cust.RimPrice
		apply = function(s)
			s[slot] = value
		end
	elseif slot == "glow" then
		if value ~= 0 and not Paints.isValidIndex(value) then
			return { ok = false }
		end
		if save.glow == value then
			return { ok = true }
		end
		if value == 0 then
			price = 0
		elseif not save.glowOwned then
			price = cust.UnderglowPrice
		else
			price = cust.PaintPrice
		end
		apply = function(s)
			s.glow = value
			if value ~= 0 then
				s.glowOwned = true
			end
		end
	elseif slot == "finish" then
		if not Paints.isValidFinish(value) then
			return { ok = false }
		end
		if save.finish == value then
			return { ok = true }
		end
		-- a finish is unlocked once for the whole garage
		price = if data.finishes[value] or value == "Gloss" then 0 else ((cust.FinishPrices :: any)[value] or 0)
		apply = function(s)
			s.finish = value
		end
	else
		return { ok = false }
	end

	if price > 0 and not PlayerData.spend(player, price, "paint:" .. slot) then
		return needMore(player, price)
	end
	local firstGlow = slot == "glow" and value ~= 0 and not save.glowOwned
	PlayerData.update(player, function(p)
		apply(p.cars[def.id])
		if slot == "finish" then
			p.finishes[value] = true
		end
	end)
	Vehicles.refresh(player)
	return { ok = true, message = if firstGlow then "GlowBought" else "PaintApplied" }
end

function Shop.claimDaily(player: Player)
	local data = PlayerData.get(player)
	if not data then
		return { ok = false }
	end
	local now = os.time()
	local today = math.floor(now / DAY)
	local lastDay = math.floor(data.daily.last / DAY)
	if data.daily.last > 0 and lastDay >= today then
		local left = (today + 1) * DAY - now
		return { ok = false, message = "DailyNotReady", args = { string.format("%d:%02d", left // 3600, (left % 3600) // 60) } }
	end
	local streak = if lastDay == today - 1 then math.min(data.daily.streak + 1, Config.Daily.MaxStreak) else 1
	local amount = Config.Daily.Base + Config.Daily.StreakBonus * (streak - 1)
	PlayerData.update(player, function(p)
		p.daily.last = now
		p.daily.streak = streak
	end)
	PlayerData.addCash(player, amount, "daily")
	return { ok = true, message = "DailyClaimed", args = { Format.money(amount), streak } }
end

function Shop.init()
	Net.handle("BuyCar", function(player, carId)
		return Shop.buyCar(player, carId)
	end)
	Net.handle("BuyUpgrade", function(player, carId, kind)
		return Shop.buyUpgrade(player, carId, kind)
	end)
	Net.handle("SetPaint", function(player, carId, slot, value)
		return Shop.setPaint(player, carId, slot, value)
	end)
	Net.handle("ClaimDaily", function(player)
		return Shop.claimDaily(player)
	end)
	Net.handle("SelectCar", function(player, carId)
		local data = PlayerData.get(player)
		if data and typeof(carId) == "string" and data.owned[carId] then
			PlayerData.update(player, function(p)
				p.selected = carId
			end)
			return { ok = true }
		end
		return { ok = false }
	end)
end

return Shop
