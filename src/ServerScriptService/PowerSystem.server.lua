-- PowerSystem
-- Place in: ServerScriptService
--
-- The first quest: the power is out. Everything with a "PowerQuest"
-- attribute is part of it:
--   PowerQuest = "Wire"   a junction panel (WirePanelSystem sets Repaired)
--   PowerQuest = "Fuse"   a fuse cabinet   (FuseSystem sets Repaired)
-- When every one of them is repaired the main breaker (Workspace >
-- "LEVER LIGHTS", see BreakerLever) is live: pull it and the power comes back
-- on. Pull it before then and it sparks and kicks back. (No breaker in the
-- map: the power comes on by itself, like before.)
--
-- ReplicatedStorage.Power carries what every screen (PowerClient, LeverClient) reads:
--   On (bool)  RestoredAt (server time the lights come on)
--   Ready (bool: every repair done, waiting on the breaker)
--   WiresDone  WiresTotal  FusesDone  FusesTotal  LeverDone  LeverTotal

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RESTORE_DELAY = 1.1     -- the last repair's sounds play out, then the lights go

local BreakerLever = require(ReplicatedStorage:WaitForChild("BreakerLever"))

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
	local ready = total > 0 and done >= total
	folder:SetAttribute("Ready", ready)
	if ready and not folder:GetAttribute("On") and not BreakerLever.find() then
		-- (no breaker in this map: straight on, like it always was)
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
folder:SetAttribute("Ready", false)
folder:SetAttribute("LeverDone", 0)
folder:SetAttribute("LeverTotal", BreakerLever.find() and 1 or 0)
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

--------------------------------------------------
-- THE MAIN BREAKER
--------------------------------------------------
-- LeverClient asks; this checks you're there and free, walks you up to it
-- and puts your hands on it (every screen acts it out from the lever's
-- PullAt / PullOk and your IsLeverPull / LeverPullAt attributes).

local leverRemote = folder:FindFirstChild("LeverRemote") or Instance.new("RemoteEvent")
leverRemote.Name = "LeverRemote"
leverRemote.Parent = folder

local lever = nil          -- BreakerLever.layout, once found
local pulling = false

local function getLever()
	local model = BreakerLever.find()
	if not model then
		lever = nil
		return nil
	end
	if not lever or lever.model ~= model then
		lever = BreakerLever.layout(model)
	end
	return lever
end

local function setPulled(on)
	local l = getLever()
	if l then
		l.model:SetAttribute("Pulled", on)
	end
	folder:SetAttribute("LeverDone", on and 1 or 0)
end

-- the lever moves (with or without someone on it); if the circuits are
-- fixed, the lights come on after the clunk
local function throw(ok)
	local l = getLever()
	if not l then
		return
	end
	local T = BreakerLever.T
	local start = now() + 0.3                   -- (they're walked up to it first)
	l.model:SetAttribute("PullOk", ok)
	l.model:SetAttribute("PullAt", start)
	if ok then
		setPulled(true)
		folder:SetAttribute("RestoredAt", start + T.clunk + T.lightsAfter)
		folder:SetAttribute("On", true)
	end
	return start
end

local function canPull(player)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) or hum.Health <= 0 then
		return nil
	end
	for _, name in ipairs({ "Downed", "BeingKilled", "IsBarricading", "IsHiding", "IsLeverPull" }) do
		if character:GetAttribute(name) then
			return nil
		end
	end
	return character, hrp
end

leverRemote.OnServerEvent:Connect(function(player, action)
	if action ~= "Pull" or pulling then
		return
	end
	local l = getLever()
	if not l or l.model:GetAttribute("Pulled") or folder:GetAttribute("On") then
		return
	end
	local character, hrp = canPull(player)
	if not character or (hrp.Position - l.gripRest.Position).Magnitude > BreakerLever.USE_RANGE + 3 then
		return
	end
	pulling = true
	local ok = folder:GetAttribute("Ready") == true
	local T = BreakerLever.T

	-- step up to it
	local from = hrp.CFrame
	local to = BreakerLever.standSpot(l, hrp.Position.Y)
	hrp.Anchored = true
	hrp.AssemblyLinearVelocity = Vector3.zero
	local start = throw(ok)
	character:SetAttribute("LeverPullOk", ok)
	character:SetAttribute("LeverPullAt", start)
	character:SetAttribute("IsLeverPull", true)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.3 do
			local a = (os.clock() - t0) / 0.3
			a = a * a * (3 - 2 * a)
			if hrp.Parent and hrp.Anchored then
				hrp.CFrame = from:Lerp(to, a)
			end
			RunService.Heartbeat:Wait()
		end
		if hrp.Parent and hrp.Anchored then
			hrp.CFrame = to
		end
		-- hold still while it's pulled, then let go
		task.wait((ok and T.done or T.failDone))
		character:SetAttribute("IsLeverPull", false)
		if hrp.Parent and not character:GetAttribute("BeingKilled") and not character:GetAttribute("Downed") then
			hrp.Anchored = false
		end
		pulling = false
	end)
end)

-- back to the lobby: the power's out again for next time
task.spawn(function()
	local lobby = ReplicatedStorage:WaitForChild("Lobby", 30)
	if lobby then
		lobby:GetAttributeChangedSignal("InMatch"):Connect(function()
			if lobby:GetAttribute("InMatch") ~= true then
				folder:SetAttribute("On", false)
				folder:SetAttribute("RestoredAt", 0)
				setPulled(false)
			end
		end)
	end
end)

-- testing: set the Power folder's TestCommand attribute to
--   "wire" / "fuse"  repair the next one of those (just marks it repaired)
--   "all"            repair everything left
--   "lever"          throw the breaker (lights on if everything's repaired)
--   "reset"          power off, everything un-repaired, breaker back up
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
		setPulled(false)
		recount()
		return
	end
	if command == "lever" then
		if not folder:GetAttribute("On") then
			throw(folder:GetAttribute("Ready") == true)
		end
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
