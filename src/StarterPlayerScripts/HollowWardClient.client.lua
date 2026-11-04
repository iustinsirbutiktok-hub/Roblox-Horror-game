-- HollowWardClient
-- Place in: StarterPlayer > StarterPlayerScripts (a LocalScript named "HollowWardClient")
-- Goes with HollowWardBlitz (ServerScriptService) and the HollowWard map.
--
-- On your screen:
--   * the ward's cold light (only while you're in it - your other maps keep theirs),
--     tubes that flicker and buzz
--   * the TIME TO WAKE signs and the task lines at the top right
--   * the Keeper over the PA (paste the uploaded voice line IDs into KEEPER below)
--   * your arms (and everyone's) doing the injection
--   * the patients: twitching harder as they wake, then a jerking puppet walk
--   * the opening: the lights die bank by bank toward you, the far patient sits up
--   * dying: the camcorder hits the floor, the picture cracks and rolls into static

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

-- Upload the .ogg files from assets/VoiceLines/Keeper and paste their IDs here.
local KEEPER = {
	KP_BLITZ_ASYLUM_INTRO = "",
	KP_BLITZ_ASYLUM_TASK = "",
	KP_BLITZ_ASYLUM_FIRST = "",
	KP_BLITZ_ASYLUM_HALF = "",
	KP_BLITZ_ASYLUM_LAST = "",
	KP_BLITZ_ASYLUM_DONE = "",
	KP_BLITZ_ASYLUM_60 = "",
	KP_BLITZ_ASYLUM_30 = "",
	KP_BLITZ_ASYLUM_10 = "",
	KP_BLITZ_ASYLUM_WAKE_ONE = "",
	KP_BLITZ_ASYLUM_WAKE_ALL = "",
	KP_BLITZ_ASYLUM_DROPPED = "",
	KP_DEATH_ASYLUM = "",
	KP_DEATH_01 = "",
	KP_DEATH_02 = "",
	KP_DEATH_03 = "",
}
local SOUND = {
	static = "rbxassetid://9116279560",
	click = "rbxassetid://9114213314",
	heartbeat = "rbxassetid://3012160995",
	straps = "rbxassetid://9113669127",
	buzz = "rbxassetid://111151736519936",
}
local FONT = Enum.Font.SpecialElite
local INK = Color3.fromRGB(214, 206, 190)

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function sound(id, volume, speed, parent)
	if not id or id == "" then
		return
	end
	local s = new("Sound", { SoundId = id, Volume = volume or 0.5, PlaybackSpeed = speed or 1 }, parent or camera)
	s:Play()
	Debris:AddItem(s, 12)
	return s
end

local function smooth(a)
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function now()
	return workspace:GetServerTimeNow()
end

local ward = workspace:FindFirstChild("HollowWard")
while not ward do
	workspace.ChildAdded:Wait()
	ward = workspace:FindFirstChild("HollowWard")
end
local zone = ward:WaitForChild("WardZone")
local remote = ReplicatedStorage:WaitForChild("HollowWardRemote")

local function inBox(part, pos)
	local p = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

local function myRoot()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart"), c
end

--------------------------------------------------
-- THE WARD'S LIGHT (only while you're in it)
--------------------------------------------------

local grade = new("ColorCorrectionEffect", { Name = "HollowWardGrade", Enabled = false, TintColor = Color3.fromRGB(206, 222, 238),
	Saturation = -0.38, Contrast = 0.14, Brightness = -0.02 }, Lighting)
local saved = nil
local inside = false

local function applyWardLight(on)
	if on == inside then
		return
	end
	inside = on
	if on then
		saved = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness,
			ExposureCompensation = Lighting.ExposureCompensation, FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd,
			FogStart = Lighting.FogStart }
		Lighting.Ambient = ward:GetAttribute("Ambient") or Color3.fromRGB(18, 22, 28)
		Lighting.OutdoorAmbient = ward:GetAttribute("OutdoorAmbient") or Color3.fromRGB(10, 12, 16)
		Lighting.Brightness = ward:GetAttribute("Brightness") or 0
		Lighting.ExposureCompensation = ward:GetAttribute("Exposure") or -0.15
		Lighting.FogColor = ward:GetAttribute("FogColor") or Color3.fromRGB(14, 18, 22)
		Lighting.FogStart = 0
		Lighting.FogEnd = ward:GetAttribute("FogEnd") or 140
		grade.Enabled = true
	elseif saved then
		for k, v in pairs(saved) do
			Lighting[k] = v
		end
		grade.Enabled = false
	end
end

task.spawn(function()
	while true do
		task.wait(0.4)
		local root = myRoot()
		applyWardLight(root ~= nil and inBox(zone, root.Position))
	end
end)

-- flickering tubes: stutter off and on, buzzing, now and then
local flickering = {}
local function flicker(m)
	if flickering[m] or m:GetAttribute("Off") or m:GetAttribute("Dead") then
		return
	end
	flickering[m] = true
	local lights, tubes = {}, {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Light") then
			table.insert(lights, d)
		elseif d:IsA("BasePart") and (d.Name == "Tube" or d.Name == "Bulb") then
			table.insert(tubes, d)
		end
	end
	local housing = m:FindFirstChild("Housing") or tubes[1]
	if housing and (housing.Position - camera.CFrame.Position).Magnitude < 40 then
		sound(SOUND.buzz, 0.05, 2.6 + math.random() * 0.4, housing)
	end
	for _ = 1, math.random(3, 9) do
		local on = math.random() < 0.45
		if m:GetAttribute("Off") then
			break
		end
		for _, l in ipairs(lights) do
			l.Enabled = on
		end
		for _, t in ipairs(tubes) do
			t.Material = on and Enum.Material.Neon or Enum.Material.Glass
		end
		task.wait(math.random() * 0.12 + 0.03)
	end
	local lit = not m:GetAttribute("Off")
	for _, l in ipairs(lights) do
		l.Enabled = lit
	end
	for _, t in ipairs(tubes) do
		t.Material = lit and Enum.Material.Neon or Enum.Material.Glass
	end
	flickering[m] = nil
end
task.spawn(function()
	while true do
		task.wait(0.6 + math.random() * 1.2)
		if inside then
			for _, m in ipairs(ward.Lights:GetChildren()) do
				if m:GetAttribute("Flicker") and math.random() < 0.35 then
					task.spawn(flicker, m)
				end
			end
		end
	end
end)

--------------------------------------------------
-- THE SIGNS: TIME TO WAKE
--------------------------------------------------

local signs = {}
local function setupSign(m)
	local board = m:FindFirstChild("Board")
	if not board or signs[m] then
		return
	end
	local gui = new("SurfaceGui", { Face = Enum.NormalId.Front, LightInfluence = 0, Brightness = 2.2,
		CanvasSize = Vector2.new(500, 220), SizingMode = Enum.SurfaceGuiSizingMode.FixedSize }, board)
	local title = new("TextLabel", { Size = UDim2.new(1, 0, 0.24, 0), Position = UDim2.fromScale(0, 0.04), BackgroundTransparency = 1,
		Font = Enum.Font.Arcade, TextScaled = true, TextColor3 = Color3.fromRGB(255, 60, 44), Text = "TIME TO WAKE",
		TextTransparency = 1 }, gui)
	local digits = new("TextLabel", { Size = UDim2.new(1, 0, 0.7, 0), Position = UDim2.fromScale(0, 0.28), BackgroundTransparency = 1,
		Font = Enum.Font.Arcade, TextScaled = true, TextColor3 = Color3.fromRGB(255, 34, 22), Text = "", TextTransparency = 1 }, gui)
	signs[m] = { title = title, digits = digits, lamp = m:FindFirstChild("Lamp"), on = false, flick = 0 }
end
for _, m in ipairs(ward:WaitForChild("Signs"):GetChildren()) do
	setupSign(m)
end

local function formatTime(t)
	t = math.max(0, math.ceil(t))
	return string.format("%d:%02d", t // 60, t % 60)
end

--------------------------------------------------
-- THE HUD: top right, like the other blitz rounds
--------------------------------------------------

local gui = new("ScreenGui", { Name = "HollowWardHUD", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 30,
	Enabled = false }, player:WaitForChild("PlayerGui"))
local function hudLine(y, size, transparency)
	return new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, y), Size = UDim2.new(0, 520, 0, size),
		BackgroundTransparency = 1, Font = FONT, TextSize = size, TextColor3 = INK, TextTransparency = transparency or 0,
		TextStrokeTransparency = 0.55, TextStrokeColor3 = Color3.fromRGB(10, 8, 6), TextXAlignment = Enum.TextXAlignment.Right,
		Text = "" }, gui)
end
local hudTitle = hudLine(14, 20)
local hudTask = hudLine(38, 20)
local hudHint = hudLine(62, 17, 0.25)
local hudCarry = hudLine(86, 17)
local hint = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150), Size = UDim2.new(0, 700, 0, 26),
	BackgroundTransparency = 1, Font = FONT, TextSize = 21, TextColor3 = INK, TextStrokeTransparency = 0.5, Text = "",
	TextTransparency = 1 }, gui)
local function showHint(text)
	hint.Text = text
	hint.TextTransparency = 0
	hint.TextStrokeTransparency = 0.5
	task.delay(2.8, function()
		if hint.Text == text then
			TweenService:Create(hint, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

--------------------------------------------------
-- THE KEEPER
--------------------------------------------------

local voice
local function keeper(key)
	local id = KEEPER[key]
	if not id or id == "" then
		return
	end
	if voice then
		voice:Stop()
	end
	voice = sound(id, 0.9, 1)
end

--------------------------------------------------
-- POSES: arms (injection, the opening), patients (twitching, sitting up, the puppet walk)
--------------------------------------------------

local function jointsOf(model)
	local torso = model:FindFirstChild("Torso")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not torso or not root then
		return nil
	end
	return {
		rs = torso:FindFirstChild("Right Shoulder"), ls = torso:FindFirstChild("Left Shoulder"),
		rh = torso:FindFirstChild("Right Hip"), lh = torso:FindFirstChild("Left Hip"),
		neck = torso:FindFirstChild("Neck"), root = root:FindFirstChild("RootJoint") or root:FindFirstChild("Root Hip"),
	}
end

-- turn a limb round its joint by R (given in the parent part's own axes)
local function turn(motor, R)
	if motor then
		local rest = motor.C0.Rotation
		motor.Transform = rest:Inverse() * R * rest
	end
end

local cinematicArms = 0          -- 0..1 (the opening)
local sitUp = { model = nil, amount = 0 }

local function posePlayer(c, t)
	local j = jointsOf(c)
	if not j then
		return
	end
	if c:GetAttribute("IsSedating") then
		-- the right hand brings the needle down, the left holds the patient still
		local push = math.sin(t * 2.6) * 0.06
		turn(j.rs, CFrame.Angles(math.rad(72) + push, 0, math.rad(-14)))
		turn(j.ls, CFrame.Angles(math.rad(58) - push, 0, math.rad(18)))
	elseif c == player.Character and cinematicArms > 0.01 then
		-- the opening: hands up a little, not quite steady
		local w = cinematicArms
		local tremble = math.sin(t * 23) * 0.012 + math.sin(t * 9.7) * 0.01
		turn(j.rs, CFrame.Angles(math.rad(38 * w) + tremble, 0, math.rad(-10 * w)))
		turn(j.ls, CFrame.Angles(math.rad(32 * w) - tremble, 0, math.rad(12 * w)))
	end
end

local function posePatient(m, t, dt)
	local j = jointsOf(m)
	if not j then
		return
	end
	local seed = (#m.Name * 7.31) % 10
	if m:GetAttribute("Hunting") then
		-- the puppet walk: jerked along by strings - legs swing too far, arms dangle and snap, head lolls
		local root = m:FindFirstChild("HumanoidRootPart")
		local speed = root and (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude or 0
		local walk = math.clamp(speed / 10, 0, 1.3)
		local ph = t * 7.5
		local jerk = math.noise(t * 3, seed) > 0.3 and 1 or 0
		local snap = math.sin(ph) > 0 and 1 or -1
		turn(j.rh, CFrame.Angles(math.rad(48) * walk * snap, 0, math.rad(4)))
		turn(j.lh, CFrame.Angles(-math.rad(48) * walk * snap, 0, math.rad(-4)))
		turn(j.rs, CFrame.Angles(math.rad(20 + 70 * jerk) + math.noise(t * 6, seed) * 0.8, 0, math.rad(-8)))
		turn(j.ls, CFrame.Angles(math.rad(10 + 60 * jerk) + math.noise(t * 6, seed + 3) * 0.8, 0, math.rad(8)))
		turn(j.neck, CFrame.Angles(math.rad(-20) + math.noise(t * 4, seed + 5) * 0.6, math.noise(t * 5, seed + 7) * 0.9,
			math.rad(35) * math.sin(t * 0.9 + seed)))
		turn(j.root, CFrame.Angles(math.rad(10) * walk + math.noise(t * 8, seed) * 0.2, math.noise(t * 2, seed) * 0.3, 0))
		return
	end
	if m:GetAttribute("Sedated") then
		for _, motor in pairs(j) do
			if motor then
				motor.Transform = motor.Transform:Lerp(CFrame.identity, math.min(dt * 3, 1))
			end
		end
		return
	end
	-- asleep under the straps: twitches, more and harder as the sedative wears off
	local wake = m:GetAttribute("Wake") or 0
	local amp = 0.05 + wake * wake * 0.9
	local spasm = math.noise(t * (1.5 + wake * 5), seed) > 0.55 - wake * 0.3 and 1 or 0.15
	turn(j.rs, CFrame.Angles(math.noise(t * 7, seed) * amp * spasm, 0, math.noise(t * 6, seed + 1) * amp * 0.5 * spasm))
	turn(j.ls, CFrame.Angles(math.noise(t * 7, seed + 2) * amp * spasm, 0, math.noise(t * 6, seed + 3) * amp * 0.5 * spasm))
	turn(j.rh, CFrame.Angles(math.noise(t * 5, seed + 4) * amp * 0.4 * spasm, 0, 0))
	turn(j.lh, CFrame.Angles(math.noise(t * 5, seed + 5) * amp * 0.4 * spasm, 0, 0))
	local neck = CFrame.Angles(math.noise(t * 9, seed + 6) * amp * spasm, math.noise(t * 4, seed + 7) * amp * 1.4 * spasm, 0)
	-- the one in the opening sits bolt upright, then lies back
	if sitUp.model == m and sitUp.amount > 0.001 and j.root then
		local a = sitUp.amount
		local hip = Vector3.new(0, -1, 0)
		local M = CFrame.new(hip) * CFrame.Angles(-math.rad(80) * a, 0, 0) * CFrame.new(-hip)
		j.root.Transform = j.root.C0:Inverse() * M * j.root.C0
		-- (the legs stay flat on the bed)
		for _, hipMotor in ipairs({ j.rh, j.lh }) do
			if hipMotor then
				local torsoRel = j.root.C0 * j.root.C1:Inverse()
				hipMotor.Transform = hipMotor.C0:Inverse() * torsoRel:Inverse() * M:Inverse() * torsoRel * hipMotor.C0
			end
		end
		neck = neck * CFrame.Angles(math.rad(25) * a, 0, math.rad(20) * a)
	elseif j.root then
		j.root.Transform = CFrame.Angles(math.noise(t * 3, seed + 8) * amp * 0.25 * spasm, 0, 0)
	end
	turn(j.neck, neck)
end

local afterAnimation = RunService.PreSimulation or RunService.Stepped
afterAnimation:Connect(function(_, dtMaybe)
	local t = os.clock()
	local dt = typeof(dtMaybe) == "number" and dtMaybe or 1 / 60
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		if c and (c:GetAttribute("IsSedating") or (p == player and cinematicArms > 0.01)) then
			posePlayer(c, t)
		end
	end
	if inside or ward:GetAttribute("BlitzState") ~= "Idle" then
		for _, m in ipairs(ward:GetChildren()) do
			if m:GetAttribute("Patient") then
				posePatient(m, t, dt)
			end
		end
	end
end)

--------------------------------------------------
-- THE OPENING
--------------------------------------------------

local cinematic = nil       -- { start, look }
local function freeze(on)
	if on then
		ContextActionService:BindActionAtPriority("HollowWardFreeze", function()
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.LeftShift)
	else
		ContextActionService:UnbindAction("HollowWardFreeze")
	end
end

local function nearestFitting(pos)
	local best, bestD
	for _, m in ipairs(ward.Lights:GetChildren()) do
		local h = m:FindFirstChild("Housing")
		if h and not m:GetAttribute("Dead") then
			local d = (h.Position - pos).Magnitude
			if not bestD or d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

local function localLight(m, on)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Light") then
			d.Enabled = on
		elseif d:IsA("BasePart") and d.Name == "Tube" then
			d.Material = on and Enum.Material.Neon or Enum.Material.Glass
			d.Color = on and Color3.fromRGB(196, 222, 236) or Color3.fromRGB(70, 74, 72)
		end
	end
end

local function playOpening()
	local root, c = myRoot()
	if not root or not inBox(zone, root.Position) or cinematic then
		return
	end
	local look = ward:FindFirstChild("CinematicLook")
	cinematic = { start = os.clock(), look = look and look.Position or (root.Position + root.CFrame.LookVector * 50),
		fromCF = camera.CFrame }
	c:SetAttribute("InCutscene", true)       -- (the camcorder comes down for it)
	freeze(true)
	gui.Enabled = false
	local banks = ward:GetAttribute("Banks") or 8
	local interval = ward:GetAttribute("BankInterval") or 0.55
	local bankEnd = 1.2 + banks * interval
	local patient
	for _, m in ipairs(ward:GetChildren()) do
		if m:GetAttribute("Cinematic") then
			patient = m
		end
	end
	cinematic.bankEnd = bankEnd
	cinematic.patient = patient
	-- the reveal: a dead tube over the far bed stutters back on, it sits up, the tube dies
	task.delay(bankEnd + 0.3, function()
		if not patient then
			return
		end
		local tube = nearestFitting(patient:GetPivot().Position)
		sitUp.model = patient
		for i = 1, 7 do
			if tube then
				localLight(tube, i % 2 == 1)
			end
			task.wait(0.06 + math.random() * 0.08)
		end
		if tube then
			localLight(tube, true)
		end
		sound(SOUND.straps, 0.6, 0.55, patient:FindFirstChild("Torso"))
		local t0 = os.clock()
		while os.clock() - t0 < 1.6 do
			local u = (os.clock() - t0) / 1.6
			sitUp.amount = u < 0.25 and smooth(u / 0.25) or (u > 0.75 and smooth(1 - (u - 0.75) / 0.25) or 1)
			task.wait()
		end
		sitUp.amount = 0
		if tube then
			for i = 1, 5 do
				localLight(tube, i % 2 == 0)
				task.wait(0.05)
			end
			localLight(tube, false)
		end
		sitUp.model = nil
	end)
	task.delay(bankEnd + 4.6, function()
		cinematic.ending = os.clock()
		freeze(false)
		task.delay(0.7, function()
			cinematic = nil
			cinematicArms = 0
			if c.Parent then
				c:SetAttribute("InCutscene", nil)
			end
			gui.Enabled = true
		end)
	end)
end

RunService:BindToRenderStep("HollowWardCinematic", Enum.RenderPriority.Camera.Value + 55, function()
	if not cinematic then
		return
	end
	local root = myRoot()
	if not root then
		return
	end
	local t = os.clock() - cinematic.start
	local eye = camera.CFrame.Position
	local target = cinematic.look
	local handheld = CFrame.Angles(math.noise(t * 0.7, 1) * 0.02, math.noise(t * 0.6, 2) * 0.025, math.noise(t * 0.5, 3) * 0.01)
	local want = CFrame.lookAt(eye, target) * handheld
	local blendIn = smooth(t / 0.9)
	local blendOut = cinematic.ending and (1 - smooth((os.clock() - cinematic.ending) / 0.7)) or 1
	local w = blendIn * blendOut
	camera.CFrame = camera.CFrame:Lerp(want, w)
	cinematicArms = w
	-- the reveal: the view narrows on the far bed
	local reveal = cinematic.bankEnd and smooth((t - cinematic.bankEnd) / 0.8) * blendOut or 0
	if reveal > 0 then
		camera.FieldOfView = camera.FieldOfView + (42 - camera.FieldOfView) * reveal
		if cinematic.patient then
			local p = cinematic.patient:GetPivot().Position
			camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, p + Vector3.new(0, 1, 0)) * handheld, reveal * 0.8)
		end
	end
	-- the body faces the way we're looking
	local flat = (target - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > 1 and w > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end
end)

--------------------------------------------------
-- DYING: the camcorder hits the floor
--------------------------------------------------

local deathGui = new("ScreenGui", { Name = "HollowWardDeath", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 100,
	Enabled = false }, player.PlayerGui)
local dying = nil

local function deathScreen(killer)
	if dying then
		return
	end
	local root, c = myRoot()
	if not root then
		return
	end
	deathGui:ClearAllChildren()
	deathGui.Enabled = true
	dying = { start = os.clock(), from = camera.CFrame, killer = killer, floorY = root.Position.Y - 2.6, roll = math.random() < 0.5 and 1 or -1 }
	sound(SOUND.click, 0.9, 0.5)
	-- the crack: lines out from where the screen hit
	local cx, cy = math.random(30, 70) / 100, math.random(25, 65) / 100
	for i = 1, 14 do
		local a = math.rad(i * (360 / 14) + math.random(-12, 12))
		local len = math.random(140, 520)
		for k, w in ipairs({ 5, 2 }) do
			new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(cx, cy), Size = UDim2.fromOffset(len, w),
				Rotation = math.deg(a), BackgroundColor3 = k == 1 and Color3.new(0, 0, 0) or Color3.fromRGB(220, 226, 220),
				BackgroundTransparency = k == 1 and 0.55 or 0.25, BorderSizePixel = 0, ZIndex = 3 }, deathGui)
		end
	end
	local static = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 160, 150),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 }, deathGui)
	local grain = {}
	for i = 1, 140 do
		grain[i] = new("Frame", { Size = UDim2.fromOffset(math.random(2, 7), 2), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 4, Visible = false }, deathGui)
	end
	local rec = new("TextLabel", { Position = UDim2.new(0, 34, 0, 30), Size = UDim2.fromOffset(160, 26), BackgroundTransparency = 1,
		Font = FONT, TextScaled = true, TextColor3 = Color3.fromRGB(235, 60, 50), Text = "● REC",
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }, deathGui)
	local stamp = os.date("!%H:%M:%S") .. ":" .. string.format("%02d", math.random(0, 29))
	new("TextLabel", { Position = UDim2.new(0, 180, 0, 32), Size = UDim2.fromOffset(170, 22), BackgroundTransparency = 1,
		Font = FONT, TextScaled = true, TextColor3 = Color3.fromRGB(235, 60, 50), Text = stamp, ZIndex = 5 }, deathGui)
	local lost = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 40),
		BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = INK, Text = "NO SIGNAL", TextTransparency = 1,
		ZIndex = 6 }, deathGui)
	local black = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(4, 6, 10), BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 5 }, deathGui)
	task.spawn(function()
		local st = sound(SOUND.static, 0.0, 1.0)
		if st then
			st.Looped = true
		end
		while dying do
			local t = os.clock() - dying.start
			local noise = math.clamp((t - 0.45) / 1.6, 0, 1)
			if st then
				st.Volume = 0.35 * noise
			end
			static.BackgroundTransparency = 1 - 0.55 * noise * (0.6 + 0.4 * math.random())
			for _, g in ipairs(grain) do
				g.Visible = math.random() < noise
				g.Position = UDim2.fromScale(math.random(), math.random())
			end
			if t > 1.0 then
				rec.Text = "■ STOP"
				rec.TextColor3 = Color3.fromRGB(170, 170, 160)
			end
			if t > 1.9 then
				black.BackgroundTransparency = math.max(0, 1 - (t - 1.9) / 0.6)
				lost.TextTransparency = math.max(0, 1 - (t - 2.1) / 0.4)
			end
			task.wait(0.05)
		end
		if st then
			st:Destroy()
		end
	end)
	task.delay(1.0, function()
		local lines = { "KP_DEATH_ASYLUM", "KP_DEATH_01", "KP_DEATH_02", "KP_DEATH_03" }
		keeper(math.random() < 0.5 and lines[1] or lines[math.random(2, 4)])
	end)
	_ = c
end

RunService:BindToRenderStep("HollowWardDeathCam", Enum.RenderPriority.Camera.Value + 56, function()
	if not dying then
		return
	end
	local t = os.clock() - dying.start
	local from = dying.from
	-- a jerk toward whatever caught you, then the drop: falls, hits, rolls on its side, settles
	local look = from
	if dying.killer and dying.killer.Parent then
		local head = dying.killer:FindFirstChild("Head")
		if head then
			look = CFrame.lookAt(from.Position, head.Position)
		end
	end
	local fall = smooth((t - 0.25) / 0.4)
	local bounce = t > 0.65 and math.exp(-(t - 0.65) * 7) * math.abs(math.sin((t - 0.65) * 18)) * 0.35 or 0
	local y = from.Position.Y + (dying.floorY + 0.35 - from.Position.Y) * fall + bounce
	local base = from:Lerp(look, smooth(t / 0.2))
	local pos = Vector3.new(base.Position.X, y, base.Position.Z) + base.LookVector * 0.8 * fall
	camera.CFrame = CFrame.new(pos) * base.Rotation * CFrame.Angles(math.rad(-25) * fall, 0, math.rad(78) * dying.roll * fall)
		* CFrame.Angles(math.noise(t * 30, 1) * 0.03 * (1 - fall), 0, 0)
end)

player.CharacterAdded:Connect(function()
	if dying then
		dying = nil
		task.delay(0.4, function()
			deathGui.Enabled = false
			deathGui:ClearAllChildren()
		end)
	end
	cinematic = nil
	cinematicArms = 0
	freeze(false)
end)

--------------------------------------------------
-- EVENTS FROM THE SERVER
--------------------------------------------------

remote.OnClientEvent:Connect(function(what, a)
	if what == "Keeper" then
		keeper(a)
	elseif what == "Hint" then
		showHint(a)
	elseif what == "Death" then
		deathScreen(a)
	elseif what == "Woke" then
		local root = myRoot()
		local torso = a and a:FindFirstChild("Torso")
		if root and torso and (torso.Position - root.Position).Magnitude < 70 then
			sound(SOUND.static, 0.5, 0.35, torso)
			sound(SOUND.heartbeat, 0.6, 1.0)
		end
	elseif what == "Escaped" then
		showHint("You made it to the lift.")
	elseif what == "End" then
		showHint(a and "The doors grind shut. The ward goes quiet." or "Nobody made it out.")
	end
end)

ward:GetAttributeChangedSignal("BlitzState"):Connect(function()
	local s = ward:GetAttribute("BlitzState")
	if s == "Intro" then
		playOpening()
	elseif s == "Idle" then
		gui.Enabled = false
	end
end)

--------------------------------------------------
-- EVERY FRAME: signs and HUD
--------------------------------------------------

RunService.Heartbeat:Connect(function()
	local s = ward:GetAttribute("BlitzState")
	local signOn = ward:GetAttribute("SignOn") == true
	local left = ward:GetAttribute("TimeLeft") or 0
	local t = os.clock()
	for m, sg in pairs(signs) do
		if signOn and not sg.on then
			sg.on = true
			sg.flick = t
		elseif not signOn then
			sg.on = false
		end
		local visible = sg.on and (t - sg.flick > 0.9 or math.random() < 0.5)
		sg.title.TextTransparency = visible and 0 or 1
		sg.digits.TextTransparency = visible and 0 or 1
		sg.digits.Text = (s == "Overrun" or s == "End") and "0:00" or formatTime(left)
		if sg.lamp and sg.on then
			sg.lamp.Material = (t * 2) % 2 < 1 and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
		_ = m
	end
	local root, c = myRoot()
	local active = s ~= "Idle" and s ~= "Intro" and root ~= nil and inBox(zone, root.Position)
	if not cinematic then
		gui.Enabled = active
	end
	if active then
		local total = ward:GetAttribute("Patients") or 0
		local done = ward:GetAttribute("Sedated") or 0
		hudTitle.Text = "HOLLOW WARD  ·  SEDATION  ·  " .. formatTime(left)
		if s == "Running" then
			hudTask.Text = string.format("1/2  ·  Sedate the patients (%d/%d)", done, total)
			hudHint.Text = c and c:GetAttribute("CarryingVial") and "find a patient who's stirring"
				or "the sedatives are in the pharmacy, north wing"
		elseif s == "Done" then
			hudTask.Text = "2/2  ·  Get to the lift"
			hudHint.Text = "back through the gallery"
		elseif s == "Overrun" then
			hudTask.Text = "They're awake.  Get to the lift."
			hudHint.Text = "the ducts are too low for them"
		else
			hudTask.Text = ""
			hudHint.Text = ""
		end
		hudCarry.Text = c and c:GetAttribute("CarryingVial") and "carrying: sedative vial  (don't run)" or ""
	end
	-- the patients' prompts tell you when you've got nothing to give them
	if c then
		local has = c:GetAttribute("CarryingVial") == true
		for _, m in ipairs(ward:GetChildren()) do
			local torso = m:GetAttribute("Patient") and m:FindFirstChild("Torso")
			local prompt = torso and torso:FindFirstChild("SedatePrompt")
			if prompt then
				prompt.ObjectText = has and "Patient" or "Patient  (needs a sedative vial)"
			end
		end
	end
end)
