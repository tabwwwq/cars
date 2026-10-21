-- Test runner: `luaurun run tests/run.luau [filter]` from the repo root.
-- Loads the Roblox mock, mirrors the Rojo tree from default.project.json and
-- runs every tests/*.spec.luau file.

local baseEnv = setmetatable({}, { __index = _G })
local harness = loadchunk(readfile("tests/harness/roblox.luau"), "@tests/harness/roblox.luau", baseEnv)()

local function newWorld()
	local env, loader, game = harness.environment()
	local Instance = env.Instance

	local function mount(parent, dir)
		for _, entry in listdir(dir) do
			if string.sub(entry, -1) == "/" then
				local name = string.sub(entry, 1, -2)
				local folder = Instance.new("Folder")
				folder.Name = name
				folder.Parent = parent
				mount(folder, dir .. "/" .. name)
			else
				local name = string.match(entry, "^(.-)%.luau$")
				if name and not string.match(name, "%.server$") and not string.match(name, "%.client$") and name ~= "init" then
					loader.module(parent, name, dir .. "/" .. entry)
				end
			end
		end
	end

	local rs = game:GetService("ReplicatedStorage")
	local shared = Instance.new("Folder")
	shared.Name = "CarsShared"
	shared.Parent = rs
	mount(shared, "src/shared")

	local sss = game:GetService("ServerScriptService")
	local server = Instance.new("Script")
	server.Name = "CarsServer"
	server.Parent = sss
	mount(server, "src/server")

	local sp = game:GetService("StarterPlayer")
	local sps = Instance.new("StarterPlayerScripts")
	sps.Name = "StarterPlayerScripts"
	sps.Parent = sp
	local client = Instance.new("LocalScript")
	client.Name = "CarsClient"
	client.Parent = sps
	mount(client, "src/client")

	return {
		env = env,
		game = game,
		shared = shared,
		server = server,
		client = client,
		require = function(inst)
			return loader.require(inst)
		end,
	}
end

local filter = ARGS[1]
local passed, failed = 0, 0
local failures = {}

for _, file in listdir("tests") do
	if string.match(file, "%.spec%.luau$") and (not filter or string.find(file, filter, 1, true)) then
		local path = "tests/" .. file
		local specEnv = setmetatable({ newWorld = newWorld, harness = harness }, { __index = _G })
		local ok, specOrErr = pcall(function()
			return loadchunk(readfile(path), "@" .. path, specEnv)()
		end)
		if not ok then
			failed += 1
			table.insert(failures, path .. ": " .. tostring(specOrErr))
			continue
		end
		for _, case in specOrErr do
			if os.getenv and os.getenv("TEST_VERBOSE") then
				print("  ..   " .. case.name)
			end
			local okCase, err = pcall(case.fn)
			if okCase then
				passed += 1
				print("  ok   " .. file .. " :: " .. case.name)
			else
				failed += 1
				print("  FAIL " .. file .. " :: " .. case.name)
				table.insert(failures, file .. " :: " .. case.name .. "\n      " .. tostring(err))
			end
		end
	end
end

print(string.format("\n%d passed, %d failed", passed, failed))
for _, f in failures do
	print("  - " .. f)
end
if failed > 0 then
	error("tests failed")
end
