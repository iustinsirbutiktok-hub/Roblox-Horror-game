-- LeverClient
-- Place in: StarterPlayer > StarterPlayerScripts (a LocalScript named "LeverClient")
--
-- The main breaker (Workspace > "LEVER LIGHTS") on your screen:
--   * its lamps: red while the circuits are still broken; once every wire
--     panel and fuse cabinet is fixed the green one blinks (pull me); after
--     the pull, steady green
--   * look at it and LEFT CLICK (tap PULL on mobile) to throw it: you step
--     up, take the handle in both hands, haul on it - it sticks, then gives
--     and slams home with a clunk and a shower of sparks - and a moment
--     later the basement lights stutter on (PowerClient)
--   * too early, and it moves a third of the way, spits sparks, kicks back
--     and knocks your hands off it
--   * everyone sees whoever pulls it, hands on the handle, leaning into it
-- Needs BreakerLever (ReplicatedStorage) and PowerSystem (ServerScriptService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local BreakerLever = require(ReplicatedStorage:WaitForChild("BreakerLever"))
local power = ReplicatedStorage:WaitForChild("Power")
local remote = power:WaitForChild("LeverRemote")

local player = Players.LocalPlayer
local T = BreakerLever.T
local UP = Vector3.new(0, 1, 0)
local rad, abs, clamp = math.rad, math.abs, math.clamp
local rng = Random.new()
local notice, noticeUntil = nil, 0       -- (the line under the prompt; made further down)

local SOUND = {
	clunk = "rbxassetid://9116673944",
	zap = "rbxassetid://9116279560",
	hum = "rbxassetid://9116279339",
	tick = "rbxassetid://9119727134",
	strain = "rbxassetid://9116522890",
	grunt = "rbxassetid://9114555699",
}

local function smooth(a)
	a = clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function spring(s, goal, w, z, dt)
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for _ = 1, steps do
		s.v += (w * w * (goal - s.x) - 2 * z * w * s.v) * h
		s.x += s.v * h
	end
	return s.x
end

local function playAt(id, position, volume, speed, range)
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = (speed or 1) * rng:NextNumber(0.96, 1.04)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 5
	s.RollOffMaxDistance = range or 70
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 6)
end

local function shake(seconds, amount)
	local c = player.Character
	if c then
		c:SetAttribute("ShakeUntil", os.clock() + seconds)
		c:SetAttribute("ShakeAmount", amount)
	end
end

local function now()
	return workspace:GetServerTimeNow()
end

--------------------------------------------------
-- THE LEVER ITSELF
--------------------------------------------------

local lever = nil            -- BreakerLever.layout
local shownF = nil
local lastPullAt = 0
local events = {}            -- which moments of the current pull we've played

local sparkPart = nil
local sparks = nil
local lamps = {}

local function makeLamp(part, color)
	if not part then
		return nil
	end
	local light = part:FindFirstChildOfClass("PointLight") or Instance.new("PointLight")
	light.Color = color
	light.Range = 6
	light.Shadows = false
	light.Parent = part
	return { part = part, light = light, color = color, dark = part.Color:Lerp(Color3.new(0.05, 0.05, 0.05), 0.75),
		material = part.Material, lit = nil }
end

local function setLamp(lamp, level)
	if not lamp then
		return
	end
	local on = level > 0.05
	if lamp.lit ~= level then
		lamp.lit = level
		lamp.part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		lamp.part.Color = lamp.dark:Lerp(lamp.color, clamp(level, 0, 1))
		lamp.light.Enabled = on
		lamp.light.Brightness = 1.4 * level
	end
end

local function setup(model)
	lever = BreakerLever.layout(model)
	if not lever then
		return
	end
	-- the moving parts are driven from here: keep them from dragging the
	-- rest of the panel along
	local moving = {}
	for _, p in ipairs(lever.moving) do
		moving[p] = true
	end
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("WeldConstraint") or d:IsA("Weld")) and d.Part0 and d.Part1 and moving[d.Part0] ~= moving[d.Part1] then
			d.Enabled = false
		end
	end
	for _, p in ipairs(lever.moving) do
		p.Anchored = true
	end

	sparkPart = Instance.new("Part")
	sparkPart.Name = "BreakerSparks"
	sparkPart.Anchored = true
	sparkPart.CanCollide, sparkPart.CanQuery, sparkPart.CanTouch = false, false, false
	sparkPart.Transparency = 1
	sparkPart.Size = Vector3.new(0.4, 0.4, 0.4)
	sparkPart.CFrame = CFrame.lookAt(lever.gripRest.Position, lever.gripRest.Position + lever.normal)
	sparkPart.Parent = workspace.CurrentCamera
	sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 110, 40))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.2, 0.6)
	sparks.Speed = NumberRange.new(6, 16)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -55, 0)
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks.Rate = 0
	sparks.Parent = sparkPart
	local flash = Instance.new("PointLight")
	flash.Name = "Flash"
	flash.Color = Color3.fromRGB(255, 200, 120)
	flash.Range = 12
	flash.Brightness = 0
	flash.Parent = sparkPart

	lamps.red = makeLamp(lever.lamps.red, Color3.fromRGB(255, 40, 30))
	lamps.green = makeLamp(lever.lamps.green, Color3.fromRGB(60, 255, 90))
	shownF = nil
end

local function burst(at, count, flashPower)
	if not sparkPart then
		return
	end
	sparkPart.Position = at
	sparks:Emit(count)
	local flash = sparkPart:FindFirstChild("Flash")
	if flash then
		flash.Brightness = flashPower
	end
end

-- the contacts the lever slams into (or the handle if there are none)
local function contactPoint()
	local best = nil
	for _, c in ipairs(lever.contacts) do
		local g = BreakerLever.gripAt(lever, 1).Position
		if not best or (c.Position - g).Magnitude < (best - g).Magnitude then
			best = c.Position
		end
	end
	return best or BreakerLever.gripAt(lever, 1).Position
end

local function stepLever(dt)
	local model = lever and lever.model
	if not model or not model.Parent then
		lever = nil
		local found = BreakerLever.find()
		if found then
			setup(found)
		end
		return
	end
	local pullAt = model:GetAttribute("PullAt") or 0
	local ok = model:GetAttribute("PullOk") == true
	local t = now() - pullAt
	local active = pullAt > 0 and t > -0.5 and t < (ok and T.done or T.failDone) + 0.5
	local f
	if active then
		f = BreakerLever.fraction(t, ok)
	else
		f = model:GetAttribute("Pulled") and 1 or 0
	end
	if f ~= shownF then
		shownF = f
		local swing = BreakerLever.swing(lever, f)
		for _, p in ipairs(lever.moving) do
			if p.Parent then
				p.CFrame = swing * lever.rest[p]
			end
		end
	end

	-- the moments of a pull
	if pullAt ~= lastPullAt then
		lastPullAt = pullAt
		events = {}
	end
	if active then
		local grip = BreakerLever.gripAt(lever, f).Position
		local function once(name, at, fn)
			if not events[name] and t >= at and t < at + 0.5 then
				events[name] = true
				fn()
			end
		end
		once("grab", T.grip, function()
			playAt(SOUND.tick, grip, 0.5, 0.6, 40)
		end)
		once("strain", T.pull, function()
			playAt(SOUND.strain, grip, 0.45, 0.45, 50)          -- old metal grinding
		end)
		if ok then
			once("clunk", T.clunk, function()
				local at = contactPoint()
				playAt(SOUND.clunk, at, 1.6, 0.7, 120)
				playAt(SOUND.zap, at, 0.5, 0.8, 60)
				playAt(SOUND.hum, at, 0.5, 0.6, 90)
				burst(at, 40, 4)
				local _, hrp = (function()
					local c = player.Character
					return c, c and c:FindFirstChild("HumanoidRootPart")
				end)()
				if hrp and (hrp.Position - at).Magnitude < 25 then
					shake(0.3, 4 * (1 - (hrp.Position - at).Magnitude / 25) + 1)
				end
			end)
		else
			once("fail", T.fail, function()
				local at = contactPoint()
				playAt(SOUND.zap, at, 0.9, 0.9, 70)
				playAt(SOUND.clunk, grip, 0.8, 1.3, 60)
				burst(at, 28, 3)
			end)
		end
	end
	if sparkPart then
		local flash = sparkPart:FindFirstChild("Flash")
		if flash and flash.Brightness > 0 then
			flash.Brightness = math.max(flash.Brightness - dt * 14, 0)
		end
	end

	-- the lamps
	local clock = os.clock()
	local pulled = model:GetAttribute("Pulled") == true and not (active and t < T.clunk)
	local failing = active and not ok and t >= T.fail and t < T.fail + 0.7
	if failing then
		setLamp(lamps.red, (clock * 18) % 1 < 0.5 and 1 or 0.1)
		setLamp(lamps.green, 0)
	elseif pulled or power:GetAttribute("On") == true then
		setLamp(lamps.red, 0)
		setLamp(lamps.green, 1)
	elseif power:GetAttribute("Ready") == true then
		setLamp(lamps.red, 0)
		setLamp(lamps.green, (clock % 1.1) < 0.55 and 1 or 0.08)      -- ready: blinking at you
	else
		setLamp(lamps.red, 0.85 + 0.15 * math.noise(clock * 3, 1.3))
		setLamp(lamps.green, 0)
	end
end

--------------------------------------------------
-- WHOEVER PULLS IT (every screen)
--------------------------------------------------
-- R6, the same way DoorClient poses you: hands on the handle, body leaning
-- into it, feet planted on the floor.

local posers = {}

local function rigOf(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso")
	if not (hrp and torso) then
		return nil
	end
	local j = {
		hrp = hrp, torso = torso,
		root = hrp:FindFirstChild("RootJoint"), neck = torso:FindFirstChild("Neck"),
		rs = torso:FindFirstChild("Right Shoulder"), ls = torso:FindFirstChild("Left Shoulder"),
		rh = torso:FindFirstChild("Right Hip"), lh = torso:FindFirstChild("Left Hip"),
	}
	if not (j.root and j.neck and j.rs and j.ls and j.rh and j.lh) then
		return nil
	end
	local function reach(motor)
		local part = motor.Part1
		local size = part and part.Size or Vector3.new(1, 2, 1)
		return (motor.C0 * motor.C1:Inverse() * Vector3.new(0, -size.Y / 2, 0)) - motor.C0.Position
	end
	j.uRA, j.uLA, j.uRL, j.uLL = reach(j.rs), reach(j.ls), reach(j.rh), reach(j.lh)
	return j
end

local function conj(motor, cf)
	local rest = motor.C0.Rotation
	return rest:Inverse() * cf * rest
end

local function between(a, b)
	local axis = a:Cross(b)
	local s = axis.Magnitude
	if s < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, a:Dot(b)))
end

-- a rigid leg hanging from `pivot`, its foot set down flat on the floor near `want`
local function plantFoot(motor, u, want, onPlane, n)
	local function solve(plane)
		local r = u.Magnitude
		local pivot = motor.C0.Position
		local h = math.max((pivot - plane):Dot(n), 0.05)
		local foot = pivot - n * h
		local dest
		if h >= r - 0.01 then
			dest = pivot - n * r
		else
			local flat = want - foot
			flat -= n * flat:Dot(n)
			if flat.Magnitude < 1e-3 then
				flat = u - n * u:Dot(n)
			end
			dest = foot + flat.Unit * math.sqrt(r * r - h * h)
		end
		return between(u.Unit, (dest - pivot).Unit)
	end
	local r = solve(onPlane)
	local axes = r * (motor.C0.Rotation * motor.C1.Rotation:Inverse())
	local size = motor.Part1 and motor.Part1.Size or Vector3.new(1, 2, 1)
	local back = abs(axes.XVector:Dot(n)) * size.X / 2 + abs(axes.ZVector:Dot(n)) * size.Z / 2
	return solve(onPlane + n * back)
end

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local JOINTS = { "root", "neck", "rs", "ls", "rh", "lh" }

local function updatePoser(p, dt, clock)
	local character, j = p.character, p.j
	if not character.Parent or not j.hrp.Parent then
		posers[character] = nil
		return
	end
	local pulling = character:GetAttribute("IsLeverPull") == true and lever ~= nil
	spring(p.w, pulling and 1 or 0, pulling and 12 or 9, 1, dt)
	if p.w.x < 0.002 and not pulling then
		for _, key in ipairs(JOINTS) do
			if j[key].Parent then
				j[key].Transform = CFrame.identity
			end
		end
		posers[character] = nil
		return
	end
	if not lever then
		return
	end

	local hrp = j.hrp.CFrame
	local ok = character:GetAttribute("LeverPullOk") == true
	local t = now() - (character:GetAttribute("LeverPullAt") or 0)
	local f = BreakerLever.fraction(t, ok)
	local grip = BreakerLever.gripAt(lever, f)
	local gripAxis = grip.Rotation * lever.gripRest.Rotation:Inverse() * lever.gripAxis
	local spread = math.min(0.42, lever.gripLength * 0.32)

	-- how much the hands are on it
	local hold
	if t < 0 then
		hold = 0
	elseif t < T.grip then
		hold = smooth(t / T.grip)
	elseif ok then
		hold = 1 - smooth((t - T.release) / 0.3)
	else
		hold = 1 - smooth((t - T.fail - 0.02) / 0.12)                -- knocked off it
	end
	local recoil = (not ok and t > T.fail) and smooth((t - T.fail) / 0.12) * (1 - smooth((t - T.fail - 0.35) / 0.4)) or 0
	if ok and t > T.clunk and not p.jolted then
		p.jolted = true
		p.jolt.v += 9
	end
	spring(p.jolt, 0, 16, 0.4, dt)

	-- the body follows the handle down (or up), leaning into it
	local gLocal = hrp:PointToObjectSpace(grip.Position)
	local gRest = hrp:PointToObjectSpace(lever.gripRest.Position)
	local move = (gLocal - gRest) * 0.3 * hold
	local low = clamp(0.6 - gLocal.Y, 0, 1.6)                     -- a handle below the chest: bend down to it
	local effort = (t > T.pull and t < (ok and T.clunk or T.fail)) and 1 or 0
	local tremble = math.noise(clock * 11, p.seed) * effort * hold
	local lean = (6 + low * 14) * hold + 4 * effort * hold - 14 * recoil + p.jolt.x * 0.6 + tremble * 1.5
	local drop = (0.06 + low * 0.35) * hold - move.Y * 0.6 + 0.05 * effort * hold
	local rootCF = CFrame.new(move.X, -drop, move.Z * 0.5 + 0.35 * recoil)
		* CFrame.Angles(-rad(lean), rad(tremble), rad(tremble * 0.8))
	local torso = j.root.C0 * conj(j.root, rootCF) * j.root.C1:Inverse()

	-- hands on the handle, one at each end
	local a = hrp:PointToObjectSpace(grip.Position + gripAxis * spread)
	local b = hrp:PointToObjectSpace(grip.Position - gripAxis * spread)
	local rightEnd, leftEnd = a, b
	if a.X < b.X then
		rightEnd, leftEnd = b, a
	end
	local function arm(motor, u, target, side)
		local pivot = motor.C0.Position
		local aim = between(u.Unit, (torso:PointToObjectSpace(target) - pivot).Unit)
		-- knocked off it: the arms fly up and back
		local flung = CFrame.Angles(0, 0, rad(side * 25)) * CFrame.Angles(rad(70), 0, 0)
		local free = CFrame.identity:Lerp(flung, recoil)
		return free:Lerp(aim, hold)
	end

	-- feet stay planted on the floor
	castParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(j.hrp.Position, Vector3.new(0, -7, 0), castParams)
	local H = hit and clamp(j.hrp.Position.Y - hit.Position.Y, 2, 4) or 3
	local floorN = torso:VectorToObjectSpace(UP)
	local floorP = torso:PointToObjectSpace(Vector3.new(0, -H, 0))
	local function leg(motor, u, x, z)
		return plantFoot(motor, u, torso:PointToObjectSpace(Vector3.new(x, -H, z)), floorP, floorN)
	end

	-- the head watches the handle
	local torsoWorld = hrp * torso
	local look = torsoWorld:VectorToObjectSpace(grip.Position - torsoWorld * Vector3.new(0, 1.5, 0))
	local flat = math.sqrt(look.X * look.X + look.Z * look.Z)
	local neckPitch = clamp(math.deg(math.atan2(-look.Y, math.max(flat, 0.01))), -30, 45) * hold
	local neckYaw = clamp(math.deg(math.atan2(-look.X, -look.Z)), -50, 50) * hold

	local pose = {
		root = rootCF,
		neck = CFrame.Angles(-rad(neckPitch), rad(neckYaw), 0),
		rs = arm(j.rs, j.uRA, rightEnd, 1),
		ls = arm(j.ls, j.uLA, leftEnd, -1),
		rh = leg(j.rh, j.uRL, 0.65, -0.25),
		lh = leg(j.lh, j.uLL, -0.6, 0.55),
	}
	local w = p.w.x
	for _, key in ipairs(JOINTS) do
		local motor = j[key]
		motor.Transform = conj(motor, CFrame.identity:Lerp(pose[key], w))
	end

	-- the one pulling it feels it
	if p.mine then
		if ok and t > T.clunk and not p.felt then
			p.felt = true
			shake(0.35, 5)
		elseif not ok and t > T.fail and not p.felt then
			p.felt = true
			shake(0.4, 7)
			playAt(SOUND.grunt, j.hrp.Position, 0.6, 0.9, 30)
		end
	end
end

local function watchCharacter(character)
	local function check()
		if character:GetAttribute("IsLeverPull") and not posers[character] then
			local j = rigOf(character)
			if j then
				posers[character] = {
					character = character, j = j, seed = rng:NextNumber(0, 100),
					w = { x = 0, v = 0 }, jolt = { x = 0, v = 0 },
					mine = character == player.Character, jolted = false, felt = false,
				}
			end
		end
	end
	character:GetAttributeChangedSignal("IsLeverPull"):Connect(check)
	character:GetAttributeChangedSignal("LeverPullAt"):Connect(function()
		local p = posers[character]
		if p then
			p.jolted, p.felt = false, false
		end
		-- your own pull, too early: say why nothing happened
		if character == player.Character and character:GetAttribute("LeverPullOk") == false then
			task.delay(0.3 + T.fail + 0.4, function()
				noticeUntil = os.clock() + 2.8
				notice.Text = "Nothing. The circuits are still dead."
			end)
		end
	end)
	check()
end
local function watchPlayer(p)
	p.CharacterAdded:Connect(watchCharacter)
	if p.Character then
		watchCharacter(p.Character)
	end
end
for _, p in ipairs(Players:GetPlayers()) do
	watchPlayer(p)
end
Players.PlayerAdded:Connect(watchPlayer)

RunService.PreSimulation:Connect(function(dt)
	local clock = os.clock()
	for _, p in pairs(posers) do
		updatePoser(p, math.min(dt, 0.1), clock)
	end
end)

--------------------------------------------------
-- LOOKING AT IT, PULLING IT
--------------------------------------------------

local FONT = Enum.Font.SpecialElite
local BONE = Color3.fromRGB(226, 216, 196)
local DIM = Color3.fromRGB(150, 138, 122)
local INK = Color3.fromRGB(9, 7, 7)
local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local gui = Instance.new("ScreenGui")
gui.Name = "LeverGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Parent = player:WaitForChild("PlayerGui")

local prompt = Instance.new("CanvasGroup")
prompt.AnchorPoint = Vector2.new(0.5, 1)
prompt.Position = UDim2.new(0.5, 0, 0.86, 0)
prompt.Size = UDim2.fromOffset(420, 34)
prompt.BackgroundTransparency = 1
prompt.GroupTransparency = 1
prompt.Parent = gui
local scale = Instance.new("UIScale")
scale.Parent = prompt
local row = Instance.new("UIListLayout")
row.FillDirection = Enum.FillDirection.Horizontal
row.HorizontalAlignment = Enum.HorizontalAlignment.Center
row.VerticalAlignment = Enum.VerticalAlignment.Center
row.Padding = UDim.new(0, 10)
row.Parent = prompt
local chip = Instance.new("Frame")
chip.Size = UDim2.fromOffset(52, 26)
chip.BackgroundColor3 = INK
chip.BackgroundTransparency = 0.25
chip.BorderSizePixel = 0
chip.Parent = prompt
local chipStroke = Instance.new("UIStroke")
chipStroke.Color = BONE
chipStroke.Transparency = 0.35
chipStroke.Parent = chip
local function label(parent, text, size, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeColor3 = INK
	l.TextStrokeTransparency = 0.5
	l.Text = text
	l.Parent = parent
	return l
end
local key = label(chip, touch and "TAP" or "LMB", 15, BONE)
key.Size = UDim2.fromScale(1, 1)
local action = label(prompt, "THROW THE BREAKER", 20, BONE)
action.Size = UDim2.fromOffset(0, 32)
action.AutomaticSize = Enum.AutomaticSize.X

local button = Instance.new("TextButton")
button.AnchorPoint = Vector2.new(1, 1)
button.Position = UDim2.new(1, -24, 1, -200)
button.Size = UDim2.fromOffset(86, 86)
button.BackgroundColor3 = INK
button.BackgroundTransparency = 0.3
button.AutoButtonColor = false
button.Font = FONT
button.Text = "PULL"
button.TextColor3 = BONE
button.TextSize = 18
button.Visible = false
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)
local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = BONE
buttonStroke.Thickness = 1.5
buttonStroke.Transparency = 0.4
buttonStroke.Parent = button

notice = label(gui, "", 18, DIM)
notice.AnchorPoint = Vector2.new(0.5, 1)
notice.Position = UDim2.new(0.5, 0, 0.78, 0)
notice.Size = UDim2.fromOffset(600, 30)
notice.TextTransparency = 1
notice.TextStrokeTransparency = 1

local hovering = false
local shown = 0

local function busy(character)
	for _, name in ipairs({ "Downed", "BeingKilled", "IsBarricading", "IsHiding", "IsLeverPull", "IsClimbing" }) do
		if character:GetAttribute(name) then
			return true
		end
	end
	return false
end

local function available()
	if not lever or not lever.model.Parent then
		return false
	end
	local model = lever.model
	if model:GetAttribute("Pulled") or power:GetAttribute("On") == true then
		return false
	end
	local pullAt = model:GetAttribute("PullAt") or 0
	return now() - pullAt > T.failDone + 0.2
end

local function lookingAtIt()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not (hrp and camera and lever) or busy(character) or not available() then
		return false
	end
	if (hrp.Position - lever.gripRest.Position).Magnitude > BreakerLever.USE_RANGE then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * (BreakerLever.USE_RANGE + 4), params)
	return hit ~= nil and hit.Instance:IsDescendantOf(lever.model)
end

local function pull()
	if hovering then
		remote:FireServer("Pull")
		hovering = false
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonX then
		pull()
	end
end)
button.Activated:Connect(pull)

RunService.RenderStepped:Connect(function(dt)
	stepLever(math.min(dt, 0.1))

	hovering = lookingAtIt()
	shown += ((hovering and 1 or 0) - shown) * math.min(dt * 12, 1)
	prompt.GroupTransparency = 1 - shown
	prompt.Visible = shown > 0.01
	button.Visible = touch and hovering
	local camera = workspace.CurrentCamera
	if camera then
		scale.Scale = clamp(camera.ViewportSize.Y / 900, 0.62, 1.25)
	end
	local ready = power:GetAttribute("Ready") == true
	action.TextColor3 = ready and BONE or DIM
	local clock = os.clock()
	notice.TextTransparency = clamp(1 - (noticeUntil - clock) / 0.4, 0, 1)
	notice.TextStrokeTransparency = 0.5 + notice.TextTransparency * 0.5
end)

-- (the lever may stream in later)
task.spawn(function()
	while not lever do
		local model = BreakerLever.find()
		if model then
			setup(model)
		end
		task.wait(2)
	end
end)
