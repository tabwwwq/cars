-- Client entry point. Controllers are ModuleScripts in Controllers/ with an
-- optional init() (build UI, synchronous) and start() (connect events).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)

local ClientState = require(script:WaitForChild("ClientState"))

-- language: from the player's locale unless Config forces one
local player = Players.LocalPlayer
local language = if Config.Language == "auto" then Strings.languageForLocale(player.LocaleId) else Config.Language
Strings.setLanguage(language)

-- profile snapshots arrive as soon as the save is loaded
Net.on("Profile", function(profile)
	ClientState.setProfile(profile)
end)

local Controllers = script:WaitForChild("Controllers")
local ORDER = {
	"Loading",
	"Notifications",
	"Hud",
	"Drive",
	"VehicleFX",
	"Garage",
	"RaceUI",
	"Minimap",
	"WorldText",
}

local loaded: { [string]: any } = {}
for _, name in ORDER do
	local module = Controllers:WaitForChild(name, 10)
	if module and module:IsA("ModuleScript") then
		loaded[name] = require(module)
	else
		warn("[Client] missing controller " .. name)
	end
end
for _, module in Controllers:GetChildren() do
	if module:IsA("ModuleScript") and not loaded[module.Name] then
		loaded[module.Name] = require(module)
		table.insert(ORDER, module.Name)
	end
end

for _, name in ORDER do
	local c = loaded[name]
	if c and typeof(c.init) == "function" then
		local ok, err = pcall(c.init)
		if not ok then
			warn(string.format("[Client] %s.init failed: %s", name, tostring(err)))
		end
	end
end
for _, name in ORDER do
	local c = loaded[name]
	if c and typeof(c.start) == "function" then
		task.spawn(function()
			local ok, err = pcall(c.start)
			if not ok then
				warn(string.format("[Client] %s.start failed: %s", name, tostring(err)))
			end
		end)
	end
end

-- first-time hint
task.delay(4, function()
	loaded.Notifications.notifyKey("Welcome", {}, "info")
end)
