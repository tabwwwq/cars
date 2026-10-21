-- DevTools: gated test helpers (Studio or Config.Admins only) for quick QA:
-- free cash and a progress reset. Never available to normal players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("CarsShared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)

local DevTools = {}

local function isDev(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return table.find(Config.Admins, player.UserId) ~= nil
end
DevTools.isDev = isDev

function DevTools.init()
	Net.handle("DevCash", function(player)
		if not isDev(player) then
			return { ok = false }
		end
		PlayerData.addCash(player, 100000, "dev")
		return { ok = true }
	end)
	Net.handle("DevReset", function(player)
		if not isDev(player) then
			return { ok = false }
		end
		Vehicles.despawn(player)
		PlayerData.reset(player)
		return { ok = true }
	end)
end

function DevTools.start()
	local function mark(player: Player)
		if isDev(player) then
			player:SetAttribute("IsDev", true)
		end
	end
	Players.PlayerAdded:Connect(mark)
	for _, p in Players:GetPlayers() do
		mark(p)
	end
end

return DevTools
