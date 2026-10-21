-- Leaderboards: global top lists (OrderedDataStore) for cash, top speed and
-- best race times, drawn on the boards in the plaza. Without DataStore access
-- (Studio) the boards still work for the current session.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Tracks = require(Shared.Tracks)

local PlayerData = require(script.Parent.PlayerData)

local Leaderboards = {}

type Entry = { userId: number, value: number }

local stores: { [string]: OrderedDataStore } = {}
local session: { [string]: { [number]: number } } = {} -- kind -> userId -> value
local ascending: { [string]: boolean } = {}
local cached: { [string]: { Entry } } = {}
local names: { [number]: string } = {}
local available = true

local function kinds(): { string }
	local list = { "cash", "speed" }
	for _, t in Tracks.List do
		table.insert(list, "track:" .. t.id)
	end
	return list
end

local function storeName(kind: string): string
	if kind == "cash" then
		return "CarsMode_TopCash_v1"
	elseif kind == "speed" then
		return "CarsMode_TopSpeed_v1"
	end
	return "CarsMode_Time_" .. string.sub(kind, 7) .. "_v1"
end

local function nameOf(userId: number): string
	local cachedName = names[userId]
	if cachedName then
		return cachedName
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local result = if ok and name then name else ("#" .. userId)
	names[userId] = result
	return result
end

local function formatValue(kind: string, value: number): string
	if kind == "cash" then
		return Format.money(value)
	elseif kind == "speed" then
		return tostring(Format.speed(value)) .. " km/h"
	end
	return Format.time(value)
end

-- Stored values are integers: cash as is, speed x100, times in milliseconds.
local function encode(kind: string, value: number): number
	if kind == "cash" then
		return math.floor(value)
	elseif kind == "speed" then
		return math.floor(value * 100)
	end
	return math.floor(value * 1000)
end

local function decode(kind: string, value: number): number
	if kind == "cash" then
		return value
	elseif kind == "speed" then
		return value / 100
	end
	return value / 1000
end

local function write(kind: string, userId: number, value: number)
	session[kind] = session[kind] or {}
	local prev = session[kind][userId]
	local better = prev == nil or (if ascending[kind] then value < prev else value > prev)
	if kind == "cash" or better then
		session[kind][userId] = value
	end
	local store = stores[kind]
	if not store or not available then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			store:UpdateAsync(tostring(userId), function(old)
				local encoded = encode(kind, value)
				if kind ~= "cash" and old ~= nil then
					if ascending[kind] and old <= encoded then
						return nil
					elseif not ascending[kind] and old >= encoded then
						return nil
					end
				end
				return encoded
			end)
		end)
		if not ok then
			warn("[Leaderboards] write failed, using session boards: " .. tostring(err))
			available = false
		end
	end)
	Leaderboards.refreshSoon()
end

function Leaderboards.submitSpeed(player: Player, speed: number)
	write("speed", player.UserId, speed)
end

function Leaderboards.submitTime(player: Player, trackId: string, seconds: number)
	write("track:" .. trackId, player.UserId, seconds)
end

function Leaderboards.submitCash(player: Player)
	local data = PlayerData.get(player)
	if data then
		write("cash", player.UserId, data.cash)
	end
end

local function fetch(kind: string): { Entry }
	local merged: { [number]: number } = {}
	local store = stores[kind]
	if store and available then
		local ok, pages = pcall(function()
			return store:GetSortedAsync(ascending[kind], Config.Leaderboards.Size)
		end)
		if ok and pages then
			for _, item in pages:GetCurrentPage() do
				local id = tonumber(item.key)
				if id then
					merged[id] = decode(kind, item.value)
				end
			end
		end
	end
	for id, v in session[kind] or {} do
		local cur = merged[id]
		if cur == nil or kind == "cash" or (if ascending[kind] then v < cur else v > cur) then
			merged[id] = v
		end
	end
	local list: { Entry } = {}
	for id, v in merged do
		table.insert(list, { userId = id, value = v })
	end
	table.sort(list, function(a, b)
		if ascending[kind] then
			return a.value < b.value
		end
		return a.value > b.value
	end)
	while #list > Config.Leaderboards.Size do
		table.remove(list)
	end
	return list
end

local function draw(board: BasePart, kind: string, list: { Entry })
	local gui = board:FindFirstChild("BoardGui")
	local rows = gui and gui:FindFirstChild("Rows")
	if not rows then
		return
	end
	for _, row in rows:GetChildren() do
		if row:IsA("TextLabel") then
			local i = row.LayoutOrder
			local e = list[i]
			if e then
				if row:GetAttribute("LocKey") then
					row:SetAttribute("LocKey", nil)
					CollectionService:RemoveTag(row, "LocText")
				end
				row.Text = string.format("%d. %s   %s", i, nameOf(e.userId), formatValue(kind, e.value))
			elseif i == 1 then
				row.Text = "BoardEmpty"
				row:SetAttribute("LocKey", "BoardEmpty")
				CollectionService:AddTag(row, "LocText")
			else
				row.Text = ""
			end
		end
	end
end

function Leaderboards.refresh()
	for _, kind in kinds() do
		cached[kind] = fetch(kind)
	end
	for _, board in CollectionService:GetTagged("Leaderboard") do
		local kind = board:GetAttribute("BoardKind")
		if typeof(kind) == "string" and cached[kind] and board:IsA("BasePart") then
			draw(board, kind, cached[kind])
		end
	end
end

local refreshQueued = false
-- Redraws the boards a few seconds after a new record (debounced).
function Leaderboards.refreshSoon()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(4, function()
		refreshQueued = false
		pcall(Leaderboards.refresh)
	end)
end

function Leaderboards.init()
	for _, kind in kinds() do
		ascending[kind] = string.sub(kind, 1, 6) == "track:"
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(storeName(kind))
		end)
		if ok then
			stores[kind] = store
		else
			available = false
		end
	end
end

function Leaderboards.start()
	-- seed session values from loaded profiles so the boards fill up in Studio too
	PlayerData.Loaded:Connect(function(player, data)
		session.cash = session.cash or {}
		session.cash[player.UserId] = data.cash
		if data.topSpeed > 0 then
			session.speed = session.speed or {}
			session.speed[player.UserId] = math.max(session.speed[player.UserId] or 0, data.topSpeed)
		end
		for trackId, t in data.bestTimes do
			local kind = "track:" .. trackId
			session[kind] = session[kind] or {}
			local cur = session[kind][player.UserId]
			if cur == nil or t < cur then
				session[kind][player.UserId] = t
			end
		end
		names[player.UserId] = player.DisplayName
	end)
	Players.PlayerRemoving:Connect(Leaderboards.submitCash)
	task.spawn(function()
		task.wait(8)
		while true do
			for _, p in Players:GetPlayers() do
				Leaderboards.submitCash(p)
			end
			local ok, err = pcall(Leaderboards.refresh)
			if not ok then
				warn("[Leaderboards] refresh failed: " .. tostring(err))
				available = false
			end
			task.wait(Config.Leaderboards.RefreshInterval)
		end
	end)
end

return Leaderboards
