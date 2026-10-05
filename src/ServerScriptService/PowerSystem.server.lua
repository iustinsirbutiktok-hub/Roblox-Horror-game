-- PowerSystem
-- Place in: ServerScriptService
--
-- The first quest: the power is out. Everything with a "PowerQuest"
-- attribute is part of it:
--   PowerQuest = "Wire"   a junction panel (WirePanelSystem sets Repaired)
--   PowerQuest = "Fuse"   a fuse cabinet   (FuseSystem sets Repaired)
-- When every one of them is repaired the power comes back on.
--
-- ReplicatedStorage.Power carries what every screen (PowerClient) reads:
--   On (bool)  RestoredAt (server time the lights come on)
--   WiresDone  WiresTotal  FusesDone  FusesTotal

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RESTORE_DELAY = 1.1     -- the last repair's sounds play out, then the lights go

local folder = ReplicatedStorage:FindFirstChild("Power") or Instance.new("Folder")
folder.Name = "Power"
folder.Parent = ReplicatedStorage

local function now()
	return workspace:GetServerTimeNow()
end

local quest = {}          -- model -> kind

local function recount()
	local counts = { Wire = { 0, 0 }, Fuse = { 0, 0 } }
	for model, kind in pairs(quest) do
		if not model.Parent then
			quest[model] = nil
		elseif counts[kind] then
			counts[kind][2] += 1
			if model:GetAttribute("Repaired") == true then
				counts[kind][1] += 1
			end
		end
	end
	folder:SetAttribute("WiresDone", counts.Wire[1])
	folder:SetAttribute("WiresTotal", counts.Wire[2])
	folder:SetAttribute("FusesDone", counts.Fuse[1])
	folder:SetAttribute("FusesTotal", counts.Fuse[2])
	local total = counts.Wire[2] + counts.Fuse[2]
	local done = counts.Wire[1] + counts.Fuse[1]
	if total > 0 and done >= total and not folder:GetAttribute("On") then
		folder:SetAttribute("RestoredAt", now() + RESTORE_DELAY)
		folder:SetAttribute("On", true)
	end
end

local function consider(model)
	if not model:IsA("Model") or quest[model] then
		return
	end
	local kind = model:GetAttribute("PowerQuest")
	if kind ~= "Wire" and kind ~= "Fuse" then
		return
	end
	quest[model] = kind
	model:GetAttributeChangedSignal("Repaired"):Connect(recount)
	model.AncestryChanged:Connect(recount)
end

folder:SetAttribute("On", false)
folder:SetAttribute("RestoredAt", 0)
for _, d in ipairs(workspace:GetDescendants()) do
	consider(d)
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(function()
			consider(d)
			recount()
		end)
	end
end)
recount()

-- back to the lobby: the power's out again for next time
task.spawn(function()
	local lobby = ReplicatedStorage:WaitForChild("Lobby", 30)
	if lobby then
		lobby:GetAttributeChangedSignal("InMatch"):Connect(function()
			if lobby:GetAttribute("InMatch") ~= true then
				folder:SetAttribute("On", false)
				folder:SetAttribute("RestoredAt", 0)
			end
		end)
	end
end)

-- testing: set the Power folder's TestCommand attribute to
--   "wire" / "fuse"  repair the next one of those (just marks it repaired)
--   "all"            repair everything left
--   "reset"          power off, everything un-repaired
folder:GetAttributeChangedSignal("TestCommand"):Connect(function()
	local command = folder:GetAttribute("TestCommand")
	if type(command) ~= "string" or command == "" then
		return
	end
	folder:SetAttribute("TestCommand", "")
	command = command:lower()
	if command == "reset" then
		for model in pairs(quest) do
			model:SetAttribute("Repaired", false)
		end
		folder:SetAttribute("On", false)
		folder:SetAttribute("RestoredAt", 0)
		recount()
		return
	end
	for model, kind in pairs(quest) do
		if model:GetAttribute("Repaired") ~= true and (command == "all" or kind:lower() == command) then
			model:SetAttribute("Repaired", true)
			if command ~= "all" then
				break
			end
		end
	end
end)
