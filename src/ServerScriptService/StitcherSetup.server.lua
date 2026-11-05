-- StitcherSetup
-- Place in: ServerScriptService (a Script named "StitcherSetup")
--
-- Gets every imported Stitcher (a Model named "TheStitcher", or with a
-- "Stitcher" attribute set to true) ready for StitcherAnimator: anchored where
-- you put it, nothing to trip over, and the attributes it listens to:
--   Patrol          tick it to watch it stalk back and forth (a test walk, on each screen)
--   PatrolDistance  how far it goes (studs)
--   PatrolSpeed     how fast (studs/second; above about 6 it runs)
--   Aggro           0..1, how worked up it is
--   Attack          change it (e.g. +1) and it lunges with the scissors
--   Procedural      untick to play your own animations instead

local function prepare(model)
	if not model:IsA("Model") or not (model.Name == "TheStitcher" or model:GetAttribute("Stitcher") == true) then
		return
	end
	model:SetAttribute("Stitcher", true)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CastShadow = true
		end
	end
	local defaults = { Patrol = true, PatrolDistance = 18, PatrolSpeed = 3, Aggro = 0, Attack = 0, Procedural = true }
	for key, value in pairs(defaults) do
		if model:GetAttribute(key) == nil then
			model:SetAttribute(key, value)
		end
	end
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
end

for _, d in ipairs(workspace:GetDescendants()) do
	prepare(d)
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(prepare, d)
	end
end)
