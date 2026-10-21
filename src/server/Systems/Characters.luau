-- Characters: spawns characters only after the world and the save are ready,
-- respawns them after death, and puts character parts in the "Players"
-- collision group (so wheel rays ignore people).

local Players = game:GetService("Players")

local PlayerData = require(script.Parent.PlayerData)
local World = require(script.Parent.World)

local Characters = {}

local RESPAWN_DELAY = 3

local function setGroup(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = "Players"
	end
end

local function onCharacter(player: Player, character: Model)
	for _, d in character:GetDescendants() do
		setGroup(d)
	end
	character.DescendantAdded:Connect(setGroup)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum.Died:Connect(function()
			task.delay(RESPAWN_DELAY, function()
				if player.Parent and player.Character == character then
					player:LoadCharacter()
				end
			end)
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
	if player.Character then
		-- spawned before this script ran (Studio play solo)
		onCharacter(player, player.Character)
	end
	World.waitUntilReady()
	PlayerData.waitFor(player, 60)
	if player.Parent then
		-- (re)spawn on the plaza now that the world exists
		player:LoadCharacter()
	end
end

function Characters.init()
	Players.CharacterAutoLoads = false
end

function Characters.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
end

return Characters
