-- CrawlerAnimator
-- Place in: StarterPlayer > StarterPlayerScripts (a LocalScript)
--
-- Makes the Crawler move on every player's screen. CrawlerAI (server) only
-- moves an invisible box around; this script builds the whole body on top of
-- it every frame with CrawlerBody, plays its sounds where its hands, feet and
-- mouth actually are, and acts out the catches from CrawlerShared:
--   * everyone sees the caught player thrown around by the Crawler
--   * the caught player's camera is dragged onto its face, shaking, with red
--     flashes, a heartbeat and a stinger only they hear
--   * anyone close by feels the slams through their camera

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("CrawlerConfig"))
local Shared = require(ReplicatedStorage:WaitForChild("CrawlerShared"))
local Body = require(ReplicatedStorage:WaitForChild("CrawlerBody"))

local player = Players.LocalPlayer

local function lerp(a, b, t)
	return a + (b - a) * t
end

--------------------------------------------------
-- SOUNDS
--------------------------------------------------

local function makeSound(name, parent, volume, speed)
	local spec = Config.Sounds[name]
	if not spec or spec.Id == "" or not parent then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "Crawler" .. name
	s.SoundId = spec.Id
	s.Volume = spec.Volume * (volume or 1)
	s.PlaybackSpeed = spec.Speed * (speed or 1) * (1 + (math.random() * 2 - 1) * spec.Vary)
	if spec.Range > 0 then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 6
		s.RollOffMaxDistance = spec.Range
	end
	s.Parent = parent
	return s
end

local function play(name, parent, volume, speed)
	local s = makeSound(name, parent, volume, speed)
	if s then
		s:Play()
		Debris:AddItem(s, 10)
	end
	return s
end

--------------------------------------------------
-- FIND THE CRAWLER (once the server has re-rigged it)
--------------------------------------------------

local monster = workspace:WaitForChild(Config.MODEL_NAME)
while not monster:GetAttribute("CrawlerReady") do
	monster:GetAttributeChangedSignal("CrawlerReady"):Wait()
end
local humanoid = monster:WaitForChild("Humanoid")
local root = monster:WaitForChild("HumanoidRootPart")
local torso = monster:WaitForChild("Torso")
local headPart = monster:WaitForChild("Head")

local NEEDED = { "RootJoint", "Neck", "Right Shoulder", "Right Elbow", "Right Wrist", "Left Shoulder", "Left Elbow",
	"Left Wrist", "Right Hip", "Right Knee", "Right Ankle", "Left Hip", "Left Knee", "Left Ankle" }

local motors = {}
local deadline = os.clock() + 20
while true do
	table.clear(motors)
	for _, d in ipairs(monster:GetDescendants()) do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	local ok = true
	for _, name in ipairs(NEEDED) do
		if not motors[name] then
			ok = false
		end
	end
	-- and the root joint has the server's new setup
	local wanted = monster:GetAttribute("RootC0")
	if ok and typeof(wanted) == "CFrame" and (motors.RootJoint.C0.Position - wanted.Position).Magnitude > 0.01 then
		ok = false
	end
	if ok then
		break
	end
	if os.clock() > deadline then
		warn("CrawlerAnimator: TheCrawler's joints never all showed up; is the model being streamed out?")
		break
	end
	task.wait(0.2)
end

local rig = Shared.buildRig(function(name)
	return motors[name]
end)
if not rig then
	warn("CrawlerAnimator: couldn't build TheCrawler's skeleton (missing a Motor6D)")
	return
end

-- everything welded to a bone, so the body can keep itself out of floors and ceilings
local weldLinks = {}
for _, d in ipairs(monster:GetDescendants()) do
	if (d:IsA("WeldConstraint") or d:IsA("Weld")) and d.Part0 and d.Part1 then
		weldLinks[d.Part0] = weldLinks[d.Part0] or {}
		weldLinks[d.Part1] = weldLinks[d.Part1] or {}
		table.insert(weldLinks[d.Part0], d.Part1)
		table.insert(weldLinks[d.Part1], d.Part0)
	end
end

local function boxesOn(bone)
	local boxes, seen, queue = {}, { [bone] = true }, { bone }
	while #queue > 0 do
		local part = table.remove(queue)
		for _, other in ipairs(weldLinks[part] or {}) do
			if not seen[other] then
				seen[other] = true
				table.insert(queue, other)
				if other.Transparency < 1 and other.Name:sub(1, 6) ~= "Strand" then
					table.insert(boxes, { bone.CFrame:ToObjectSpace(other.CFrame), other.Size })
				end
			end
		end
	end
	if bone.Transparency < 1 then
		table.insert(boxes, { CFrame.identity, bone.Size })
	end
	return boxes
end

local torsoBoxes = boxesOn(torso)
local jawPart = rig.jaw and rig.jaw.Part1
local body = Body.new(rig, {
	groundY = -(root.Size.Y / 2 + humanoid.HipHeight),
	topAboveTorso = monster:GetAttribute("TopAboveTorso"),
	underside = Shared.undersidePoints(rig, torsoBoxes),
	topside = Shared.undersidePoints(rig, torsoBoxes, nil, true),
	headUnder = Shared.undersidePoints(rig, boxesOn(headPart), rig.headRest),
	jawUnder = jawPart and Shared.undersidePoints(rig, boxesOn(jawPart), rig.headRest * rig.jaw.C0 * rig.jaw.C1:Inverse()) or nil,
})

local endParts = {
	RA = monster:FindFirstChild("Right Hand"), LA = monster:FindFirstChild("Left Hand"),
	RL = monster:FindFirstChild("Right Foot"), LL = monster:FindFirstChild("Left Foot"),
}

--------------------------------------------------
-- RAYCASTS (the body feels for floors, ceilings and vent walls)
--------------------------------------------------

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true
local filterAt = 0

local function refreshFilter(now)
	if now < filterAt then
		return
	end
	filterAt = now + 1
	local list = { monster }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	castParams.FilterDescendantsInstances = list
end

local function cast(origin, direction)
	local hit = workspace:Raycast(origin, direction, castParams)
	if hit then
		return hit.Position, hit.Normal, hit.Material
	end
	return nil
end

--------------------------------------------------
-- THE CAUGHT PLAYER
--------------------------------------------------

local function jointsOf(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local t = character:FindFirstChild("Torso")
	return {
		hrp = hrp,
		torso = t,
		root = hrp:FindFirstChild("RootJoint"),
		neck = t and t:FindFirstChild("Neck"),
		rs = t and t:FindFirstChild("Right Shoulder"),
		ls = t and t:FindFirstChild("Left Shoulder"),
		rh = t and t:FindFirstChild("Right Hip"),
		lh = t and t:FindFirstChild("Left Hip"),
	}
end

local posed = nil              -- joints we're currently moving
local victimOut, victimV = {}, {}

local function releaseVictim()
	if posed then
		for _, key in ipairs({ "root", "neck", "rs", "ls", "rh", "lh" }) do
			local motor = posed[key]
			if motor and motor.Parent then
				motor.Transform = CFrame.identity
			end
		end
		posed = nil
	end
end

--------------------------------------------------
-- WHAT THE CAUGHT PLAYER SEES AND HEARS
--------------------------------------------------

--------------------------------------------------
-- LIGHT IN THE DARK
--------------------------------------------------
-- These only exist on your screen (each player makes their own), so nothing
-- here touches the server or other players' lighting.

local glowFolder = Instance.new("Folder")
glowFolder.Name = "CrawlerGlow"
glowFolder.Parent = workspace

local function glowPart(name, size, visible)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size, size, size)
	p.Material = Enum.Material.Neon
	p.Color = Config.EYE_COLOR
	p.Transparency = visible and 0 or 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = glowFolder
	return p
end

local eyes = {}
for _, side in ipairs({ 1, -1 }) do
	local part = glowPart("CrawlerEye", Config.EYE_SIZE, true)
	local light = Instance.new("PointLight")
	light.Color = Config.EYE_COLOR
	light.Range = Config.EYE_LIGHT_RANGE
	light.Brightness = 0
	light.Parent = part
	eyes[side] = { part = part, light = light }
end

-- a cold light that floods the spot while it's got someone
local catchLamp = glowPart("CrawlerCatchLight", 0.2, false)
local catchLight = Instance.new("PointLight")
catchLight.Color = Config.CATCH_LIGHT_COLOR
catchLight.Range = Config.CATCH_LIGHT_RANGE
catchLight.Brightness = 0
catchLight.Shadows = true
catchLight.Parent = catchLamp

local lampLevel = 0
local lampKick = 0
local nextBlink = os.clock() + 3
local blinkUntil = 0

local function updateGlow(dt, now, catching, chasing, victimHead, mouth)
	-- eyes: always on, brighter when it's hunting you, a slow blink now and then
	if now >= nextBlink then
		blinkUntil = now + 0.13
		nextBlink = now + 2.5 + math.random() * 5
	end
	local open = now >= blinkUntil
	local glow = (catching and 1.7 or chasing and 1.2 or 0.75) * (0.85 + 0.15 * math.noise(now * 6, 0.5))
	local head = body.headCF
	for side, eye in pairs(eyes) do
		if head then
			local o = Config.EYE_OFFSET
			eye.part.CFrame = head * CFrame.new(o.X * side, o.Y, o.Z)
		end
		eye.part.Transparency = open and 0 or 1
		eye.light.Brightness = open and Config.EYE_LIGHT_BRIGHTNESS * glow or 0
	end

	-- the catch light: fades in on the grab, flares with every slam, fades out after
	local goal = catching and 1 or 0
	lampLevel += (goal - lampLevel) * math.clamp(dt * (catching and 8 or 1.5), 0, 1)
	lampKick = math.max(lampKick - dt * 3, 0)
	if mouth then
		local centre = victimHead and victimHead.Position:Lerp(mouth, 0.45) or mouth
		catchLamp.Position = centre + Vector3.new(0, 1.8, 0)
	end
	catchLight.Brightness = Config.CATCH_LIGHT_BRIGHTNESS * lampLevel * (0.82 + 0.18 * math.noise(now * 11, 7.3))
		+ lampKick * 2 * lampLevel
end

local camShake = 0
local camWeight = 0
local savedFov = nil
local myCatch = nil            -- { def, t } while YOU are the one caught
local eyeCF, mouthPos = nil, nil
local hidden = {}              -- your own head/hat parts we hid from your camera

local fx = Instance.new("ScreenGui")
fx.Name = "CrawlerCatchFX"
fx.ResetOnSpawn = false
fx.IgnoreGuiInset = true
fx.DisplayOrder = 30
fx.Enabled = false
fx.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 5
flash.Parent = fx

local edges = {}
for _, spec in ipairs({
	{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.4), 90 },
	{ UDim2.fromScale(0, 0.6), UDim2.fromScale(1, 0.4), -90 },
	{ UDim2.fromScale(0, 0), UDim2.fromScale(0.35, 1), 0 },
	{ UDim2.fromScale(0.65, 0), UDim2.fromScale(0.35, 1), 180 },
}) do
	local edge = Instance.new("Frame")
	edge.Position = spec[1]
	edge.Size = spec[2]
	edge.BackgroundColor3 = Color3.fromRGB(20, 0, 0)
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.Parent = fx
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = spec[3]
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge
	table.insert(edges, edge)
end

local blur, colour, heartbeat = nil, nil, nil

local function startMyCatch()
	fx.Enabled = true
	for _, e in ipairs(edges) do
		e.BackgroundTransparency = 1
		TweenService:Create(e, TweenInfo.new(0.35), { BackgroundTransparency = 0.05 }):Play()
	end
	blur = Instance.new("BlurEffect")
	blur.Name = "CrawlerBlur"
	blur.Size = 0
	blur.Parent = Lighting
	colour = Instance.new("ColorCorrectionEffect")
	colour.Name = "CrawlerColour"
	colour.Parent = Lighting
	TweenService:Create(colour, TweenInfo.new(0.4), {
		Saturation = -0.45, Contrast = 0.25, Brightness = 0.03, TintColor = Color3.fromRGB(255, 205, 200),
	}):Play()
	local cam = workspace.CurrentCamera
	savedFov = cam and cam.FieldOfView or 70
	-- hide your own head from the inside
	table.clear(hidden)
	local character = player.Character
	if character then
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "Head" or d:FindFirstAncestorOfClass("Accessory")) then
				hidden[d] = d.LocalTransparencyModifier
			end
		end
	end
end

local function endMyCatch()
	local fade = TweenInfo.new(0.6)
	for _, e in ipairs(edges) do
		TweenService:Create(e, fade, { BackgroundTransparency = 1 }):Play()
	end
	TweenService:Create(flash, fade, { BackgroundTransparency = 1 }):Play()
	local b, c, h = blur, colour, heartbeat
	blur, colour, heartbeat = nil, nil, nil
	if b then
		TweenService:Create(b, fade, { Size = 0 }):Play()
		Debris:AddItem(b, 1)
	end
	if c then
		TweenService:Create(c, fade, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
		Debris:AddItem(c, 1)
	end
	if h then
		TweenService:Create(h, TweenInfo.new(1.2), { Volume = 0 }):Play()
		Debris:AddItem(h, 1.5)
	end
	for part, value in pairs(hidden) do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
	table.clear(hidden)
	task.delay(0.7, function()
		if not myCatch then
			fx.Enabled = false
		end
	end)
end

local function redFlash(amount)
	flash.BackgroundTransparency = 1 - 0.55 * math.clamp(amount, 0, 1)
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	if blur then
		blur.Size = 16 * amount
		TweenService:Create(blur, TweenInfo.new(0.5), { Size = 3 }):Play()
	end
end

RunService:BindToRenderStep("CrawlerCamera", Enum.RenderPriority.Camera.Value + 10, function(dt)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local now = os.clock()

	-- dragged onto its face
	local goal = 0
	local fov = savedFov or cam.FieldOfView
	if myCatch then
		goal = Shared.sample(myCatch.def.cam, myCatch.t) * Shared.smooth(myCatch.t / 0.2)
		fov = Shared.sample(myCatch.def.fov, myCatch.t)
	end
	camWeight = goal >= camWeight and goal or math.max(goal, camWeight - dt * 2)
	if camWeight > 0.001 and eyeCF and mouthPos then
		local eyePos = eyeCF.Position + eyeCF.LookVector * 0.25 + eyeCF.UpVector * 0.15
		local look = CFrame.lookAt(eyePos, mouthPos)
		-- your view tilts with your head
		local up = eyeCF.UpVector
		local roll = math.atan2(-up:Dot(look.RightVector), up:Dot(look.UpVector))
		local face = look * CFrame.Angles(0, 0, roll * 0.6)
		cam.CFrame = cam.CFrame:Lerp(face, camWeight)
		cam.FieldOfView = lerp(savedFov or cam.FieldOfView, fov, camWeight)
		for part in pairs(hidden) do
			if part.Parent then
				part.LocalTransparencyModifier = camWeight > 0.4 and 1 or part.LocalTransparencyModifier
			end
		end
	elseif savedFov and not myCatch then
		cam.FieldOfView = savedFov
		savedFov = nil
	end

	-- slams you can feel
	camShake = math.max(camShake - dt * 2.4 * (1 + camShake), 0)
	if camShake > 0.001 then
		local s = math.min(camShake, 2.5)
		cam.CFrame = cam.CFrame * CFrame.Angles(
			math.noise(now * 31, 1.1) * 0.07 * s,
			math.noise(now * 29, 2.7) * 0.07 * s,
			math.noise(now * 23, 4.4) * 0.12 * s)
	end
end)

--------------------------------------------------
-- THE BODY'S OWN SOUNDS
--------------------------------------------------

local breath = makeSound("Breath", headPart)
if breath then
	breath.Looped = true
	breath:Play()
end
local scrape = makeSound("VentScrape", torso)
if scrape then
	scrape.Looped = true
	scrape.Volume = 0
	scrape:Play()
end

local METAL = {
	[Enum.Material.Metal] = true, [Enum.Material.DiamondPlate] = true,
	[Enum.Material.CorrodedMetal] = true, [Enum.Material.Foil] = true,
}

local function onBodyEvent(e)
	local kind = e[1]
	if kind == "step" then
		local limb, material, speed = e[2], e[4], e[5]
		local vent = (material and METAL[material]) or body.squeeze.x > 0.5
		local name = vent and "VentStep" or (limb.arm and "HandStep" or "FootStep")
		play(name, endParts[limb.key] or torso, 0.45 + math.min(speed / 18, 1) * 0.8)
	elseif kind == "sound" then
		local where = e[3] == "head" and headPart or torso
		play(e[2], where, e[4], e[5])
	end
end

--------------------------------------------------
-- EVERY FRAME
--------------------------------------------------

local lastCatchStart = nil
local prevCatchT = -1
local accum = 0
local frameCount = 0
local lastVictimTorso, lastVictimHead = nil, nil

local function readCatch()
	if monster:GetAttribute("State") ~= "Catch" then
		return nil
	end
	local kind = monster:GetAttribute("CatchKind")
	local victimId = monster:GetAttribute("CatchVictim") or 0
	local base, dir = monster:GetAttribute("CatchBase"), monster:GetAttribute("CatchDir")
	if not kind or not Shared.CATCHES[kind] or victimId == 0 or typeof(base) ~= "Vector3" or typeof(dir) ~= "Vector3" then
		return nil
	end
	local standY = monster:GetAttribute("CatchStandY") or 3
	return {
		kind = kind,
		def = Shared.CATCHES[kind],
		start = monster:GetAttribute("CatchStart") or 0,
		victimId = victimId,
		frame = { base = base, f = dir, r = dir:Cross(Vector3.new(0, 1, 0)), standY = standY },
		env = {
			hold = monster:GetAttribute("CatchHold") or Config.HOLD_DISTANCE,
			standY = standY,
			clear = monster:GetAttribute("CatchClear") or 99,
			back = monster:GetAttribute("CatchBack") or 14,
		},
	}
end

local function catchEvent(e, catch, victimParts)
	local mine = catch.victimId == player.UserId
	local kind = e[2]
	if kind == "sound" then
		local name, where = e[3], e[4]
		if where == "local" then
			if mine then
				if name == "Heartbeat" then
					if heartbeat then
						heartbeat:Destroy()
					end
					heartbeat = makeSound("Heartbeat", SoundService)
					if heartbeat then
						heartbeat.Looped = true
						heartbeat:Play()
					end
				else
					play(name, SoundService, e[5], e[6])
				end
			end
		else
			local parent = where == "head" and headPart or where == "victim" and victimParts or torso
			play(name, parent, e[5], e[6])
		end
	elseif kind == "kick" then
		lampKick += e[3]
		if mine then
			camShake += e[3]
		else
			local cam = workspace.CurrentCamera
			local distance = cam and (cam.CFrame.Position - root.Position).Magnitude or 999
			camShake += e[3] * 0.5 * math.clamp(1 - distance / 45, 0, 1)
		end
	elseif kind == "flash" and mine then
		redFlash(e[3])
	end
end

local afterAnimation = RunService.PreSimulation or RunService.Stepped
afterAnimation:Connect(function(a, b)
	local dt = typeof(b) == "number" and b or a
	if not (root.Parent and torso.Parent and headPart.Parent) then
		return
	end
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	refreshFilter(now)

	local state = monster:GetAttribute("State") or "Move"
	local stateStart = monster:GetAttribute("StateStart") or 0
	local catch = readCatch()
	local catchInput = nil

	if catch then
		if catch.start ~= lastCatchStart then
			lastCatchStart = catch.start
			prevCatchT = -1
			lastVictimTorso, lastVictimHead = nil, nil
			if catch.victimId == player.UserId then
				startMyCatch()
			end
		end
		local t = math.max(serverNow - catch.start, 0)
		local def = catch.def
		local victim = Players:GetPlayerByUserId(catch.victimId)
		local character = victim and victim.Character
		local joints = character and jointsOf(character)

		if joints and t < def.length then
			table.clear(victimOut)
			local hrpCF, torsoCF, headCF = Body.poseVictim(catch.kind, t, catch.env, catch.frame, joints, victimOut, victimV)
			joints.hrp.CFrame = hrpCF
			for motor, cf in pairs(victimOut) do
				motor.Transform = cf
			end
			posed = joints
			lastVictimTorso, lastVictimHead = torsoCF, headCF
			if catch.victimId == player.UserId then
				eyeCF = headCF
			end
		elseif posed then
			releaseVictim()
		end

		for _, e in ipairs(def.events) do
			if e[1] > prevCatchT and e[1] <= t and t - e[1] < 0.35 then
				catchEvent(e, catch, joints and (joints.torso or joints.hrp))
			end
		end
		prevCatchT = t

		if catch.victimId == player.UserId then
			myCatch = { def = def, t = t }
		end
		catchInput = {
			kind = catch.kind, t = t, env = catch.env,
			victimTorso = lastVictimTorso, victimHead = lastVictimHead,
		}
	else
		if posed then
			releaseVictim()
		end
		if lastCatchStart then
			lastCatchStart = nil
			if myCatch then
				myCatch = nil
				endMyCatch()
			end
		end
	end

	-- far away and nothing happening: don't bother every frame
	accum += dt
	frameCount += 1
	local cam = workspace.CurrentCamera
	local far = cam and (cam.CFrame.Position - root.Position).Magnitude > 260
	if far and not catch and frameCount % 4 ~= 0 then
		return
	end

	local target = nil
	local targetId = monster:GetAttribute("TargetId") or 0
	if targetId ~= 0 then
		local p = Players:GetPlayerByUserId(targetId)
		local head = p and p.Character and p.Character:FindFirstChild("Head")
		target = head and head.Position
	end

	-- at a door: where it is and which way it faces (CrawlerAI sets these)
	local doorInput = nil
	if state == "DoorSlam" or state == "DoorBash" or state == "DoorRage" then
		local point, normal = monster:GetAttribute("DoorPoint"), monster:GetAttribute("DoorNormal")
		local edge = monster:GetAttribute("DoorEdge")
		if typeof(point) == "Vector3" and typeof(normal) == "Vector3" then
			doorInput = { point = point, normal = normal, edge = typeof(edge) == "Vector3" and edge or point }
		end
	end

	local out, events = body:update({
		dt = accum,
		now = now,
		root = root.CFrame,
		cast = cast,
		state = state,
		stateTime = serverNow - stateStart,
		stateStart = stateStart,
		chasing = monster:GetAttribute("Chasing") == true,
		target = target,
		catch = catchInput,
		door = doorInput,
		slamAt = monster:GetAttribute("SlamAt") or 0,
		slamKind = monster:GetAttribute("SlamKind"),
	})
	accum = 0
	for motor, cf in pairs(out) do
		motor.Transform = cf
	end
	mouthPos = body.mouth
	updateGlow(dt, now, catch ~= nil and catch.start ~= nil and serverNow - catch.start < catch.def.length + 0.4,
		monster:GetAttribute("Chasing") == true, lastVictimHead, mouthPos)

	for _, e in ipairs(events) do
		onBodyEvent(e)
	end

	-- breathing gets faster and louder when it's after someone; metal scraping in vents
	local chasing = monster:GetAttribute("Chasing") == true
	local squeeze = body.squeeze.x
	if breath then
		local spec = Config.Sounds.Breath
		breath.Volume = spec.Volume * (chasing and 1.35 or 1) * (catch and 0.4 or 1)
		breath.PlaybackSpeed = spec.Speed * (chasing and 1.25 or 1)
	end
	if scrape then
		local speed = Vector3.new(body.vel.X, 0, body.vel.Z).Magnitude
		scrape.Volume = Config.Sounds.VentScrape.Volume * math.clamp(squeeze, 0, 1) * math.clamp(speed / 6, 0, 1)
	end
end)
