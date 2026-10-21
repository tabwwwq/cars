-- Installer for an existing place. In Roblox Studio:
--   1. Right-click Workspace > Insert from File... > build/CarsMode.rbxmx
--   2. In the Command Bar run:
--        require(workspace.CarsModeInstall.Installer)()
-- It moves the three Cars folders into their services. If something with the
-- same name already exists it is kept as "<Name>_old" instead of being deleted.

return function()
	local root = script.Parent
	local StarterPlayer = game:GetService("StarterPlayer")
	local targets = {
		CarsShared = game:GetService("ReplicatedStorage"),
		CarsAssets = game:GetService("ReplicatedStorage"),
		CarsServer = game:GetService("ServerScriptService"),
		CarsClient = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
			or Instance.new("StarterPlayerScripts", StarterPlayer),
	}
	for name, service in targets do
		local item = root:FindFirstChild(name)
		if item then
			local existing = service:FindFirstChild(name)
			if existing then
				existing.Name = name .. "_old"
				warn("[Cars] kept the previous " .. name .. " as " .. existing.Name)
			end
			item.Parent = service
		end
	end
	workspace.StreamingEnabled = false
	root:Destroy()
	print("[Cars] installed. Press Play to try it.")
end
