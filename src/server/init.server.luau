-- Server entry point. Every system is a ModuleScript in Systems/ with an
-- optional init() (synchronous setup, runs in ORDER) and start() (long-running
-- work, runs after every init has finished).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("CarsShared"):WaitForChild("Net"))

local Systems = script:WaitForChild("Systems")

-- Order matters for init(): later systems may use earlier ones.
local ORDER = {
	"Characters", -- disables auto spawning before anyone joins
	"World", -- builds the map in start(); characters spawn when it's done
	"PlayerData",
	"Environment",
	"Vehicles",
	"Shop",
	"Leaderboards",
	"Economy",
	"Races",
	"DevTools",
}

Net.init()

local loaded: { [string]: any } = {}
for _, name in ORDER do
	local module = Systems:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		loaded[name] = require(module)
	else
		warn("[Server] missing system " .. name)
	end
end
-- any extra system dropped into Systems/ is picked up too (merged work from other places)
for _, module in Systems:GetChildren() do
	if module:IsA("ModuleScript") and not loaded[module.Name] then
		loaded[module.Name] = require(module)
		table.insert(ORDER, module.Name)
	end
end

for _, name in ORDER do
	local system = loaded[name]
	if system and typeof(system.init) == "function" then
		local ok, err = pcall(system.init)
		if not ok then
			warn(string.format("[Server] %s.init failed: %s", name, tostring(err)))
		end
	end
end

for _, name in ORDER do
	local system = loaded[name]
	if system and typeof(system.start) == "function" then
		task.spawn(function()
			local ok, err = pcall(system.start)
			if not ok then
				warn(string.format("[Server] %s.start failed: %s", name, tostring(err)))
			end
		end)
	end
end

print("[Server] Cars mode ready")
