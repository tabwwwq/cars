-- Net: the one place where remotes are declared, created and wired.
--
-- Server: Net.init() creates the remotes; Net.handle(action, fn) registers a
-- request handler; Net.onEvent(name, fn, ratePerSecond) listens to a client event.
-- Client: Net.request(action, ...) -> { ok, message, args }; Net.on(name, fn).
--
-- Every client -> server call passes through a per-player token bucket and a
-- type check on the action name. Handlers still validate their own arguments.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local FOLDER_NAME = "CarsRemotes"

-- server -> client
Net.ServerEvents = {
	"Profile", -- full public profile snapshot
	"Notify", -- (key, args, kind)
	"Reward", -- (kind, amount, detail)
	"RaceState", -- race updates for one player
	"ServiceState", -- the owner's service plot: orders, bays, staff
	"ServiceEvent", -- (kind, data): arrived / ready / done / levelup
}
-- client -> server
Net.ClientEvents = {
	"VehicleAction", -- (action, value)
}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	return folder :: Folder
end

--------------------------------------------------------------------------------
-- Rate limiting
--------------------------------------------------------------------------------

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

local function allow(player: Player, key: string, perSecond: number, burst: number): boolean
	local byKey = buckets[player]
	if not byKey then
		byKey = {}
		buckets[player] = byKey
	end
	local now = os.clock()
	local b = byKey[key]
	if not b then
		b = { tokens = burst, last = now }
		byKey[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * perSecond)
	b.last = now
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end
Net.allow = allow

--------------------------------------------------------------------------------
-- Server
--------------------------------------------------------------------------------

export type Result = { ok: boolean, message: string?, args: { any }? }
type Handler = (player: Player, ...any) -> Result

local handlers: { [string]: Handler } = {}

function Net.init()
	assert(RunService:IsServer(), "Net.init is server only")
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	for _, name in Net.ServerEvents do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = f
	end
	for _, name in Net.ClientEvents do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = f
	end
	local request = Instance.new("RemoteFunction")
	request.Name = "Request"
	request.Parent = f
	f.Parent = ReplicatedStorage
	folder = f

	request.OnServerInvoke = function(player: Player, action: any, ...: any): Result
		if typeof(action) ~= "string" or #action > 40 then
			return { ok = false }
		end
		local handler = handlers[action]
		if not handler then
			return { ok = false }
		end
		if not allow(player, "request", 6, 12) then
			return { ok = false, message = "TooManyRequests" }
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] %s failed for %s: %s", action, player.Name, tostring(result)))
			return { ok = false }
		end
		return result or { ok = true }
	end

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

function Net.handle(action: string, handler: Handler)
	assert(handlers[action] == nil, "Duplicate handler " .. action)
	handlers[action] = handler
end

function Net.onEvent(name: string, handler: (Player, ...any) -> (), perSecond: number?)
	local remote = getFolder():FindFirstChild(name) :: RemoteEvent
	assert(remote, "Unknown client event " .. name)
	local rate = perSecond or 10
	remote.OnServerEvent:Connect(function(player, ...)
		if not allow(player, "event:" .. name, rate, rate * 2) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] event %s failed for %s: %s", name, player.Name, tostring(err)))
		end
	end)
end

function Net.fire(player: Player, name: string, ...: any)
	local remote = getFolder():FindFirstChild(name) :: RemoteEvent
	remote:FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	local remote = getFolder():FindFirstChild(name) :: RemoteEvent
	remote:FireAllClients(...)
end

function Net.notify(player: Player, key: string, args: { any }?, kind: string?)
	Net.fire(player, "Notify", key, args or {}, kind or "info")
end

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

function Net.request(action: string, ...: any): Result
	local remote = getFolder():WaitForChild("Request") :: RemoteFunction
	local ok, result = pcall(remote.InvokeServer, remote, action, ...)
	if not ok or typeof(result) ~= "table" then
		return { ok = false }
	end
	return result
end

function Net.on(name: string, handler: (...any) -> ())
	local remote = getFolder():WaitForChild(name) :: RemoteEvent
	return remote.OnClientEvent:Connect(handler)
end

function Net.send(name: string, ...: any)
	local remote = getFolder():WaitForChild(name) :: RemoteEvent
	remote:FireServer(...)
end

return Net
