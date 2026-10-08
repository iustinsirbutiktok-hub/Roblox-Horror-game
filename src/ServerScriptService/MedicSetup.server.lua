-- MedicSetup
-- Place in: ServerScriptService (a Script named "MedicSetup")
--
-- Gets every imported Medic (a Model named "TheMedic", or with a "Medic"
-- attribute set to true) ready for MedicAnimator: anchored where you put it,
-- nothing to trip over, and a couple of attributes to play with:
--   Patrol          tick it to watch it stalk back and forth (test walk)
--   PatrolDistance  how far it goes (studs)
--   PatrolSpeed     how fast (studs/second)

local function prepare(model)
	if not model:IsA("Model") or not (model.Name == "TheMedic" or model:GetAttribute("Medic") == true) then
		return
	end
	model:SetAttribute("Medic", true)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CastShadow = true
		end
	end
	if model:GetAttribute("Patrol") == nil then
		model:SetAttribute("Patrol", true)
	end
	if model:GetAttribute("PatrolDistance") == nil then
		model:SetAttribute("PatrolDistance", 16)
	end
	if model:GetAttribute("PatrolSpeed") == nil then
		model:SetAttribute("PatrolSpeed", 3)
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
