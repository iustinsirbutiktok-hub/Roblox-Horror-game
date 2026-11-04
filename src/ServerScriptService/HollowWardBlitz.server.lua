-- HollowWardBlitz
-- Place in: ServerScriptService (a Script named "HollowWardBlitz")
-- Needs the HollowWard map (tools/BuildHollowWard.lua) in Workspace and
-- HollowWardClient in StarterPlayerScripts.
--
-- The Hollow Ward blitz: the sedative is wearing off. Carry vials from the
-- pharmacy and put every restrained patient back to sleep before TIME TO WAKE
-- hits zero. The ones you don't reach tear free of their straps and hunt you;
-- being caught kills you. Then get to the lift.
--
--   Idle -> Intro (the lights die bank by bank down the gallery toward you, a
--   patient sits up, the sign flickers on) -> Running -> Done (all asleep: go
--   to the lift) or Overrun (time's up: they're awake, run for the lift) -> End
--
-- Starting it from your own round code:
--   game.ServerStorage.HollowWardBlitz:Fire("Start")     (and "Stop" to cancel)
-- When it ends it fires game.ServerStorage.HollowWardBlitzFinished:Fire(result)
--   result = { escaped = {players}, died = {players}, sedated = n, patients = n }
-- In Studio, say /ward (teleport into the lift) and /blitz (start it) in chat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TextChatService = game:GetService("TextChatService")
local Debris = game:GetService("Debris")

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local CONFIG = {
	TIME = 165,                 -- seconds on TIME TO WAKE
	SEDATE_HOLD = 1.6,          -- hold E this long on a patient
	SPRINT_DROP = 3.0,          -- sprinting this long with a vial in hand drops it (0 = never)
	EARLY_WAKER_AT = 40,        -- with this many seconds left, one patient wakes early (0 = never)
	HUNT_SPEED = 12,
	HUNT_SPEED_LATE = 15,       -- (when only a few are left awake)
	CATCH_RANGE = 3.4,
	KILL_TIME = 2.6,            -- the death screen plays this long before you die
	BANK_INTERVAL = 0.55,       -- the lights going out, bank by bank
	AUTO_START = true,          -- start by itself when someone stands in the lift (handy for testing)
	TEST_COMMANDS = true,       -- /ward and /blitz in chat (Studio only)
	CLUNK = "rbxassetid://9114213314",
	GLASS = "rbxassetid://9119727134",
	STRAPS = "rbxassetid://9113669127",
}

--------------------------------------------------
-- SHARED
--------------------------------------------------

local remote = ReplicatedStorage:FindFirstChild("HollowWardRemote") or Instance.new("RemoteEvent")
remote.Name = "HollowWardRemote"
remote.Parent = ReplicatedStorage
local control = ServerStorage:FindFirstChild("HollowWardBlitz") or Instance.new("BindableEvent")
control.Name = "HollowWardBlitz"
control.Parent = ServerStorage
local finished = ServerStorage:FindFirstChild("HollowWardBlitzFinished") or Instance.new("BindableEvent")
finished.Name = "HollowWardBlitzFinished"
finished.Parent = ServerStorage

local ward = workspace:WaitForChild("HollowWard")
local zone = ward:WaitForChild("WardZone")
local liftZone = ward:WaitForChild("Lift"):WaitForChild("LiftZone")

local state = "Idle"
local round = 0
local patients = {}        -- { model, bed, sedated, awake, prompt, hunting }
local players = {}         -- player -> { vial = part?, sprintFor = 0, escaped, died }
local endsAt = 0
local sedatedCount = 0
local liftMustEmpty = false   -- (after a round, nobody restarts it by standing in the lift)

local function setState(s)
	state = s
	ward:SetAttribute("BlitzState", s)
end

local function now()
	return workspace:GetServerTimeNow()
end

local function inBox(part, pos)
	local p = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

local function alive(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if h and root and h.Health > 0 then
		return c, h, root
	end
end

local function sound(id, parent, volume, speed)
	if id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 80
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 6)
end

local function keeper(key)
	remote:FireAllClients("Keeper", key)
end

--------------------------------------------------
-- THE LIGHTS
--------------------------------------------------

local function fittings()
	local list = {}
	for _, m in ipairs(ward.Lights:GetChildren()) do
		table.insert(list, m)
	end
	return list
end

local function setFitting(m, on)
	if m:GetAttribute("Dead") then
		on = false
	end
	m:SetAttribute("Off", not on)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Light") then
			d.Enabled = on
		elseif d:IsA("BasePart") and (d.Name == "Tube" or d.Name == "Bulb") then
			d.Material = on and Enum.Material.Neon or Enum.Material.Glass
			d.Color = on and (d.Name == "Tube" and Color3.fromRGB(196, 222, 236) or Color3.fromRGB(206, 220, 226))
				or Color3.fromRGB(70, 74, 72)
		end
	end
end

local function allLights(on)
	for _, m in ipairs(fittings()) do
		setFitting(m, on)
	end
end

local function signLamps(on)
	for _, s in ipairs(ward.Signs:GetChildren()) do
		local lamp = s:FindFirstChild("Lamp")
		if lamp then
			lamp.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
			lamp.Color = on and Color3.fromRGB(255, 40, 30) or Color3.fromRGB(90, 14, 12)
			local l = lamp:FindFirstChild("Emergency") or Instance.new("PointLight")
			l.Name = "Emergency"
			l.Color = Color3.fromRGB(255, 50, 36)
			l.Range = 18
			l.Brightness = 0.9
			l.Shadows = true
			l.Enabled = on
			l.Parent = lamp
		end
	end
end

--------------------------------------------------
-- PATIENTS
--------------------------------------------------

local function bedTop(bed)
	local cf, size = bed:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { bed }
	local hit = workspace:Raycast(cf.Position + Vector3.new(0, size.Y, 0), Vector3.new(0, -size.Y * 2, 0), params)
	return hit and hit.Position.Y or (cf.Position.Y + size.Y * 0.2), cf, size
end

local function dress(model)
	local pale = Color3.fromRGB(188, 182, 168)
	local gown = Color3.fromRGB(146, 158, 150)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Decal") and d.Name == "face" then
			d:Destroy()
		elseif d:IsA("Accessory") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") then
			d:Destroy()
		end
	end
	local colours = model:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	colours.HeadColor3, colours.LeftArmColor3, colours.RightArmColor3 = pale, pale, pale
	colours.TorsoColor3, colours.LeftLegColor3, colours.RightLegColor3 = gown, gown:Lerp(pale, 0.3), gown:Lerp(pale, 0.3)
	colours.Parent = model
	-- the head wrapped in old stained gauze, dark where the eyes are
	local head = model:FindFirstChild("Head")
	if head then
		local wrap = Instance.new("Part")
		wrap.Name = "Gauze"
		wrap.Size = head.Size * 1.08
		wrap.Material = Enum.Material.Fabric
		wrap.Color = Color3.fromRGB(196, 186, 156)
		wrap.CanCollide = false
		wrap.Massless = true
		local mesh = head:FindFirstChildOfClass("SpecialMesh")
		if mesh then
			mesh:Clone().Parent = wrap
		end
		wrap.CFrame = head.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = head, wrap
		weld.Parent = wrap
		wrap.Parent = model
		for _, x in ipairs({ -0.22, 0.22 }) do
			local eye = Instance.new("Part")
			eye.Name = "EyeStain"
			eye.Size = Vector3.new(0.3, 0.16, 0.05)
			eye.Material = Enum.Material.Fabric
			eye.Color = Color3.fromRGB(40, 24, 18)
			eye.CanCollide = false
			eye.Massless = true
			eye.CFrame = head.CFrame * CFrame.new(x, 0.12, -head.Size.Z * 0.55)
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = head, eye
			w.Parent = eye
			eye.Parent = model
		end
	end
end

local function lieDown(p)
	local model, bed = p.model, p.bed
	local top, cf = bedTop(bed)
	local headDir = p.headDir
	local pos = Vector3.new(cf.Position.X, top + 0.55, cf.Position.Z) + headDir * 0.5
	local back = Vector3.new(0, -1, 0)          -- lying on its back: its front faces the ceiling
	model:PivotTo(CFrame.fromMatrix(pos, headDir:Cross(back), headDir, back))
	local root = model:FindFirstChild("HumanoidRootPart")
	root.Anchored = true
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	local h = model:FindFirstChildOfClass("Humanoid")
	h.PlatformStand = true
end

local function spawnPatients()
	for _, p in ipairs(patients) do
		if p.model then
			p.model:Destroy()
		end
	end
	patients = {}
	local props = ward:FindFirstChild("Props")
	if not props then
		warn("HollowWardBlitz: no HollowWard.Props (run BuildHollowWard)")
		return
	end
	local desc = Instance.new("HumanoidDescription")
	local index = 0
	for _, bed in ipairs(props:GetChildren()) do
		if bed:GetAttribute("Patient") then
			index += 1
			local ok, model = pcall(function()
				return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
			end)
			if ok and model then
				model.Name = "Patient" .. index
				model:SetAttribute("Patient", true)
				model:SetAttribute("Wake", 0)
				dress(model)
				local h = model:FindFirstChildOfClass("Humanoid")
				h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				h.MaxHealth, h.Health = math.huge, math.huge
				h.BreakJointsOnDeath = false
				local spot = bed:GetPivot()
				local p = { model = model, bed = bed, headDir = spot.LookVector * Vector3.new(1, 0, 1), sedated = false, awake = false }
				p.headDir = p.headDir.Magnitude > 0.1 and p.headDir.Unit or Vector3.new(0, 0, -1)
				model.Parent = ward
				lieDown(p)
				-- the prompt: hold to sedate
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "SedatePrompt"
				prompt.ActionText = "Sedate"
				prompt.ObjectText = "Patient"
				prompt.HoldDuration = CONFIG.SEDATE_HOLD
				prompt.MaxActivationDistance = 7
				prompt.RequiresLineOfSight = false
				prompt.Enabled = false
				prompt:SetAttribute("NeedsVial", true)
				prompt.Parent = model:FindFirstChild("Torso")
				p.prompt = prompt
				table.insert(patients, p)
			end
		end
	end
	ward:SetAttribute("Patients", #patients)
	ward:SetAttribute("Sedated", 0)
	-- the one in the cinematic: farthest down the gallery from the lift
	local liftPos = liftZone.Position
	local far, farD = nil, -1
	for _, p in ipairs(patients) do
		local d = (p.model:GetPivot().Position - liftPos).Magnitude
		if p.bed:GetAttribute("Room") == "Gallery" and d > farD then
			far, farD = p, d
		end
	end
	if far then
		far.model:SetAttribute("Cinematic", true)
	end
end

--------------------------------------------------
-- VIALS
--------------------------------------------------

local function dropVial(player, shattered)
	local info = players[player]
	if not info or not info.vial then
		return
	end
	local vial = info.vial
	info.vial = nil
	local c = player.Character
	if c then
		c:SetAttribute("CarryingVial", nil)
	end
	if shattered then
		vial:ClearAllChildren()
		vial.Anchored = false
		vial.CanCollide = true
		sound(CONFIG.GLASS, vial, 0.7, 1.4)
		Debris:AddItem(vial, 3)
		keeper("KP_BLITZ_ASYLUM_DROPPED")
		remote:FireClient(player, "Hint", "You dropped the vial. Get another from the pharmacy.")
	else
		vial:Destroy()
	end
end

local function giveVial(player)
	local c = alive(player)
	local info = players[player]
	if not c or not info or info.vial or (state ~= "Running" and state ~= "Intro") then
		return
	end
	local arm = c:FindFirstChild("Right Arm")
	if not arm then
		return
	end
	local vial = Instance.new("Part")
	vial.Name = "SedativeVial"
	vial.Shape = Enum.PartType.Cylinder
	vial.Size = Vector3.new(0.5, 0.18, 0.18)
	vial.Material = Enum.Material.Glass
	vial.Color = Color3.fromRGB(150, 190, 170)
	vial.Transparency = 0.15
	vial.CanCollide = false
	vial.Massless = true
	vial.CFrame = arm.CFrame * CFrame.new(0, -1.05, -0.2) * CFrame.Angles(0, math.rad(90), 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = arm, vial
	weld.Parent = vial
	vial.Parent = c
	info.vial = vial
	info.sprintFor = 0
	c:SetAttribute("CarryingVial", true)
	sound(CONFIG.GLASS, arm, 0.25, 2.2)
end

local function setupShelf()
	local shelf = ward:FindFirstChild("VialShelf")
	local tray = shelf and shelf:FindFirstChild("Tray")
	if not tray then
		return
	end
	local prompt = tray:FindFirstChild("VialPrompt") or Instance.new("ProximityPrompt")
	prompt.Name = "VialPrompt"
	prompt.ActionText = "Take sedative"
	prompt.ObjectText = "Vials"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = tray
	prompt.Triggered:Connect(giveVial)
	return prompt
end
local shelfPrompt = setupShelf()

--------------------------------------------------
-- SEDATING
--------------------------------------------------

local function sedate(p, player)
	if p.sedated or p.awake or state ~= "Running" then
		return
	end
	local info = players[player]
	if not info or not info.vial then
		remote:FireClient(player, "Hint", "You need a sedative vial - the pharmacy, north wing.")
		return
	end
	dropVial(player, false)
	p.sedated = true
	p.prompt.Enabled = false
	p.model:SetAttribute("Sedated", true)
	p.model:SetAttribute("Wake", 0)
	sedatedCount += 1
	ward:SetAttribute("Sedated", sedatedCount)
	sound(CONFIG.STRAPS, p.model:FindFirstChild("Torso"), 0.3, 0.7)
	local left = #patients - sedatedCount
	if left == 0 then
		keeper("KP_BLITZ_ASYLUM_DONE")
	elseif left == 1 then
		keeper("KP_BLITZ_ASYLUM_LAST")
	elseif sedatedCount == math.floor(#patients / 2) then
		keeper("KP_BLITZ_ASYLUM_HALF")
	elseif sedatedCount == 1 then
		keeper("KP_BLITZ_ASYLUM_FIRST")
	end
end

local function hookPrompts()
	for _, p in ipairs(patients) do
		p.prompt.Triggered:Connect(function(player)
			sedate(p, player)
		end)
		p.prompt.PromptButtonHoldBegan:Connect(function(player)
			local c = player.Character
			if c and players[player] and players[player].vial then
				c:SetAttribute("IsSedating", true)
				c:SetAttribute("SedateTarget", p.model.Name)
			end
		end)
		p.prompt.PromptButtonHoldEnded:Connect(function(player)
			local c = player.Character
			if c then
				c:SetAttribute("IsSedating", nil)
				c:SetAttribute("SedateTarget", nil)
			end
		end)
	end
end

--------------------------------------------------
-- WAKING AND HUNTING
--------------------------------------------------

local function kill(player, p)
	local c, h = alive(player)
	if not c or c:GetAttribute("BeingKilled") then
		return
	end
	c:SetAttribute("BeingKilled", true)
	c:SetAttribute("CarryingVial", nil)
	dropVial(player, true)
	p.killing = true
	remote:FireClient(player, "Death", p.model)
	remote:FireAllClients("Caught", player, p.model)
	task.delay(CONFIG.KILL_TIME, function()
		if h.Parent then
			h.Health = 0
		end
		if players[player] then
			players[player].died = true
		end
		c:SetAttribute("BeingKilled", nil)
		p.killing = false
	end)
end

local function standUp(p)
	local model = p.model
	local root = model:FindFirstChild("HumanoidRootPart")
	local top, cf, size = bedTop(p.bed)
	-- step out at the side of the bed nearest the aisle
	local side = p.headDir:Cross(Vector3.yAxis).Unit
	local toCentre = (zone.Position - cf.Position) * Vector3.new(1, 0, 1)
	if side:Dot(toCentre) < 0 then
		side = -side
	end
	local floorY = cf.Position.Y - size.Y / 2
	local at = Vector3.new(cf.Position.X, floorY + 3, cf.Position.Z) + side * (size.X / 2 + 1.6)
	model:PivotTo(CFrame.lookAt(at, at + side))
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = d.Name == "Torso" or d.Name == "Head" or d.Name == "HumanoidRootPart"
		end
	end
	local h = model:FindFirstChildOfClass("Humanoid")
	h.PlatformStand = false
	root.Anchored = false
	h:ChangeState(Enum.HumanoidStateType.GettingUp)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	h.WalkSpeed = CONFIG.HUNT_SPEED
	_ = top
end

local function nearestTarget(pos)
	local best, bestD
	for player, info in pairs(players) do
		local c, _, root = alive(player)
		if c and not info.escaped and not c:GetAttribute("BeingKilled") and inBox(zone, root.Position) then
			local d = (root.Position - pos).Magnitude
			if not bestD or d < bestD then
				best, bestD = player, d
			end
		end
	end
	return best, bestD
end

local function hunt(p, myRound)
	local model = p.model
	local h = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local path = PathfindingService:CreatePath({ AgentRadius = 1.6, AgentHeight = 5.2, AgentCanJump = false,
		AgentCanClimb = false, WaypointSpacing = 4 })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	while round == myRound and model.Parent and p.awake do
		if p.killing then
			h:MoveTo(root.Position)
			task.wait(0.2)
			continue
		end
		local target, dist = nearestTarget(root.Position)
		if not target then
			h:MoveTo(root.Position)
			task.wait(0.5)
			continue
		end
		local c, _, troot = alive(target)
		if not c then
			task.wait(0.2)
			continue
		end
		local awakeCount = 0
		for _, q in ipairs(patients) do
			if q.awake then
				awakeCount += 1
			end
		end
		h.WalkSpeed = awakeCount <= 2 and CONFIG.HUNT_SPEED_LATE or CONFIG.HUNT_SPEED
		if dist <= CONFIG.CATCH_RANGE and math.abs(troot.Position.Y - root.Position.Y) < 3 then
			kill(target, p)
			task.wait(0.3)
			continue
		end
		-- in plain sight: straight at you; otherwise follow a path
		params.FilterDescendantsInstances = { model, c }
		local seen = workspace:Raycast(root.Position, troot.Position - root.Position, params) == nil
		if seen and dist < 30 then
			h:MoveTo(troot.Position)
			task.wait(0.15)
		else
			local ok = pcall(function()
				path:ComputeAsync(root.Position, troot.Position)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				local points = path:GetWaypoints()
				for i = 2, math.min(#points, 4) do
					h:MoveTo(points[i].Position)
					local t0 = os.clock()
					while os.clock() - t0 < 0.6 and (root.Position - points[i].Position).Magnitude > 2 do
						task.wait(0.1)
					end
				end
			else
				-- no way through (you're in a duct): it waits, twitching, as close as it can get
				h:MoveTo(troot.Position)
				task.wait(0.6)
			end
		end
	end
end

local function wake(p)
	if p.awake or p.sedated then
		return
	end
	p.awake = true
	p.prompt.Enabled = false
	p.model:SetAttribute("Wake", 1)
	p.model:SetAttribute("Hunting", true)
	sound(CONFIG.STRAPS, p.model:FindFirstChild("Torso"), 0.8, 0.5)
	remote:FireAllClients("Woke", p.model)
	task.delay(0.9, function()
		if p.model.Parent then
			standUp(p)
			task.spawn(hunt, p, round)
		end
	end)
end

--------------------------------------------------
-- THE ROUND
--------------------------------------------------

local function participants()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local c, _, root = alive(player)
		if c and inBox(zone, root.Position) then
			table.insert(list, player)
		end
	end
	return list
end

local function reset()
	round += 1
	for player, info in pairs(players) do
		if info.vial then
			dropVial(player, false)
		end
		local c = player.Character
		if c then
			c:SetAttribute("IsSedating", nil)
			c:SetAttribute("CarryingVial", nil)
		end
	end
	players = {}
	for _, p in ipairs(patients) do
		if p.model then
			p.model:Destroy()
		end
	end
	patients = {}
	sedatedCount = 0
	if shelfPrompt then
		shelfPrompt.Enabled = false
	end
	allLights(true)
	signLamps(false)
	ward:SetAttribute("SignOn", false)
	ward:SetAttribute("TimeLeft", CONFIG.TIME)
	ward:SetAttribute("LiftOpen", false)
	setState("Idle")
end

local function finish()
	local result = { escaped = {}, died = {}, sedated = sedatedCount, patients = #patients }
	for player, info in pairs(players) do
		if info.escaped then
			table.insert(result.escaped, player)
		else
			table.insert(result.died, player)
		end
	end
	setState("End")
	liftMustEmpty = true
	remote:FireAllClients("End", #result.escaped > 0)
	finished:Fire(result)
	task.delay(8, function()
		if state == "End" then
			reset()
		end
	end)
end

local function start()
	if state ~= "Idle" then
		return
	end
	reset()
	local myRound = round
	for _, player in ipairs(participants()) do
		players[player] = { sprintFor = 0 }
	end
	if next(players) == nil then
		return
	end
	spawnPatients()
	hookPrompts()
	setState("Intro")
	ward:SetAttribute("IntroStart", now())
	ward:SetAttribute("BankInterval", CONFIG.BANK_INTERVAL)
	keeper("KP_BLITZ_ASYLUM_INTRO")
	-- the banks go out one by one, far end first
	local banks = ward:GetAttribute("Banks") or 0
	task.wait(1.2)
	for b = 1, banks do
		for _, m in ipairs(fittings()) do
			if m:GetAttribute("Bank") == b then
				setFitting(m, false)
				local housing = m:FindFirstChild("Housing")
				if housing then
					sound(CONFIG.CLUNK, housing, 0.9, 0.35)
				end
			end
		end
		task.wait(CONFIG.BANK_INTERVAL)
		if round ~= myRound then
			return
		end
	end
	-- (the client has the far patient sit up now, then the sign flickers on)
	task.wait(2.2)
	signLamps(true)
	ward:SetAttribute("SignOn", true)
	task.wait(1.2)
	if round ~= myRound then
		return
	end
	-- the rest of the ward's lights go too: just the red lamps and your camcorder
	for _, m in ipairs(fittings()) do
		if not m:GetAttribute("Bank") and math.random() < 0.6 then
			setFitting(m, false)
		end
	end
	endsAt = now() + CONFIG.TIME
	for _, p in ipairs(patients) do
		p.prompt.Enabled = true
	end
	if shelfPrompt then
		shelfPrompt.Enabled = true
	end
	setState("Running")
	task.wait(4)
	keeper("KP_BLITZ_ASYLUM_TASK")
end

control.Event:Connect(function(what)
	if what == "Start" then
		task.spawn(start)
	elseif what == "Stop" then
		reset()
	end
end)

-- every quarter second: the clock, the wake levels, sprinting with a vial, the lift
local spoken = {}
task.spawn(function()
	while true do
		task.wait(0.25)
		if state == "Running" then
			local left = math.max(0, endsAt - now())
			ward:SetAttribute("TimeLeft", left)
			for _, mark in ipairs({ 60, 30, 10 }) do
				if left <= mark and not spoken[mark] then
					spoken[mark] = true
					keeper("KP_BLITZ_ASYLUM_" .. mark)
				end
			end
			for _, p in ipairs(patients) do
				if not p.sedated and not p.awake then
					p.model:SetAttribute("Wake", math.clamp(1 - left / CONFIG.TIME, 0, 1))
				end
			end
			if CONFIG.EARLY_WAKER_AT > 0 and left <= CONFIG.EARLY_WAKER_AT and not spoken.early then
				spoken.early = true
				local left2 = {}
				for _, p in ipairs(patients) do
					if not p.sedated and not p.awake then
						table.insert(left2, p)
					end
				end
				if #left2 >= 2 then
					wake(left2[math.random(#left2)])
					keeper("KP_BLITZ_ASYLUM_WAKE_ONE")
				end
			end
			if sedatedCount >= #patients and #patients > 0 then
				setState("Done")
				ward:SetAttribute("LiftOpen", true)
			elseif left <= 0 then
				setState("Overrun")
				ward:SetAttribute("LiftOpen", true)
				keeper("KP_BLITZ_ASYLUM_WAKE_ALL")
				for _, p in ipairs(patients) do
					wake(p)
				end
			end
		elseif state == "Idle" then
			spoken = {}
		end
		-- sprinting with a vial
		if CONFIG.SPRINT_DROP > 0 and (state == "Running" or state == "Done" or state == "Overrun") then
			for player, info in pairs(players) do
				local c, _, root = alive(player)
				if c and info.vial then
					local sprinting = c:GetAttribute("Stance") == "Sprint"
						or (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 17
					info.sprintFor = sprinting and (info.sprintFor + 0.25) or math.max(0, info.sprintFor - 0.5)
					if info.sprintFor >= CONFIG.SPRINT_DROP then
						dropVial(player, true)
					elseif info.sprintFor >= CONFIG.SPRINT_DROP - 1 and not info.warned then
						info.warned = true
						remote:FireClient(player, "Hint", "Careful - you'll drop it if you keep running.")
					end
				end
			end
		end
		-- the lift: once it's open, standing in it gets you out
		if (state == "Done" or state == "Overrun") and ward:GetAttribute("LiftOpen") then
			local waiting = false
			for player, info in pairs(players) do
				local c, _, root = alive(player)
				if c and not info.escaped and not info.died then
					if inBox(liftZone, root.Position) then
						info.escaped = true
						c:SetAttribute("Escaped", true)
						remote:FireClient(player, "Escaped")
					else
						waiting = true
					end
				end
			end
			if not waiting then
				finish()
			end
		end
	end
end)

-- someone left or died before the end
Players.PlayerRemoving:Connect(function(player)
	players[player] = nil
end)

--------------------------------------------------
-- STARTING IT (auto / test commands)
--------------------------------------------------

if CONFIG.AUTO_START then
	task.spawn(function()
		local since = nil
		while true do
			task.wait(0.5)
			if state == "Idle" then
				local anyone = false
				for _, player in ipairs(Players:GetPlayers()) do
					local c, _, root = alive(player)
					if c and inBox(liftZone, root.Position) then
						anyone = true
					end
				end
				if not anyone then
					liftMustEmpty = false
				end
				since = (anyone and not liftMustEmpty) and (since or os.clock()) or nil
				if since and os.clock() - since > 2 then
					since = nil
					task.spawn(start)
				end
			end
		end
	end)
end

local function teleport(player)
	local c, _, root = alive(player)
	local spawnPart
	for _, d in ipairs(ward.Lift:GetChildren()) do
		if d:GetAttribute("Spawn") then
			spawnPart = d
		end
	end
	if c and spawnPart then
		c:PivotTo(spawnPart.CFrame * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(-90), 0))
		_ = root
	end
end

local function command(player, text)
	if not CONFIG.TEST_COMMANDS or not RunService:IsStudio() then
		return
	end
	text = string.lower(text)
	if text == "/ward" then
		teleport(player)
	elseif text == "/blitz" then
		task.spawn(start)
	elseif text == "/stopblitz" then
		reset()
	end
end
Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(msg)
		command(player, msg)
	end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player.Chatted:Connect(function(msg)
		command(player, msg)
	end)
end
pcall(function()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		for _, name in ipairs({ "ward", "blitz", "stopblitz" }) do
			local cmd = Instance.new("TextChatCommand")
			cmd.Name = "HollowWard_" .. name
			cmd.PrimaryAlias = "/" .. name
			cmd.Parent = TextChatService
			cmd.Triggered:Connect(function(source)
				local player = Players:GetPlayerByUserId(source.UserId)
				if player then
					command(player, "/" .. name)
				end
			end)
		end
	end
end)

reset()
