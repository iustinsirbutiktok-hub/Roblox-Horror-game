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
--   * it runs up walls and creeps along the ceiling upside down (the body is
--     solved as if on a floor, in a "floor world" turned onto the surface),
--     twists its head round to stare at you, and drops - on you, if you're
--     right under it
--   * when it has you: your own arms come up pushing at its face, the rest
--     of your body is hidden so nothing blocks the view, and a cold light
--     and an exposure kick make sure you see it even with the lights out

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
local bodyInfo = {
	groundY = -(root.Size.Y / 2 + humanoid.HipHeight),
	topAboveTorso = monster:GetAttribute("TopAboveTorso"),
	underside = Shared.undersidePoints(rig, torsoBoxes),
	topside = Shared.undersidePoints(rig, torsoBoxes, nil, true),
	headUnder = Shared.undersidePoints(rig, boxesOn(headPart), rig.headRest),
	jawUnder = jawPart and Shared.undersidePoints(rig, boxesOn(jawPart), rig.headRest * rig.jaw.C0 * rig.jaw.C1:Inverse()) or nil,
}
local body = Body.new(rig, bodyInfo)

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

-- (hanging lamps aren't something to walk on: it goes straight past them)
local lamps = {}
do
	local basement = workspace:FindFirstChild("Basement")
	local folder = basement and basement:FindFirstChild("Lights")
	if folder then
		table.insert(lamps, folder)
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:GetAttribute("PowerLight") == true then
			table.insert(lamps, d)
		end
	end
end

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
	for _, lamp in ipairs(lamps) do
		table.insert(list, lamp)
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

-- the same raycasts, felt for from the body's floor version (see CrawlerShared:
-- WALLS AND CEILINGS): turn the ray onto the real surface, turn the hit back
local function spaceCast(space)
	local inv = space:Inverse()
	return function(origin, direction)
		local p, n, m = cast(space * origin, space:VectorToWorldSpace(direction))
		if p then
			return inv * p, inv:VectorToWorldSpace(n), m
		end
		return nil
	end
end

-- running up a wall the floor version walks on a flat strip (the wall and
-- the ceiling unfolded into it)
local function flatCast(floorY)
	return function(origin, direction)
		if math.abs(direction.Y) < 1e-4 then
			return nil
		end
		local t = (floorY - origin.Y) / direction.Y
		if t < 0 or t > 1 then
			return nil
		end
		return origin + direction * t, Vector3.new(0, 1, 0), Enum.Material.Concrete
	end
end

-- upside down on a ceiling it never saw it climb onto (joined late)
local DEFAULT_CEILING = CFrame.fromAxisAngle(Vector3.xAxis, math.pi)
local ceilingSpace = nil

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

-- its throat glows a dull red when the jaw gapes open
local throat = glowPart("CrawlerThroat", 0.1, false)
local throatLight = Instance.new("PointLight")
throatLight.Color = Color3.fromRGB(255, 55, 30)
throatLight.Range = 3.2
throatLight.Brightness = 0
throatLight.Parent = throat

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

	if mouth and head then
		throat.Position = mouth:Lerp(head.Position, 0.25)
		local gape = math.clamp(body.jaw.x - 0.35, 0, 1)
		throatLight.Brightness = gape * (catching and 2.2 or 0.8) * (0.8 + 0.2 * math.noise(now * 7, 9.1))
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
local hidden = {}              -- your own body (all but the arms) hidden from your camera
local arms = {}                -- your arms: kept in view, pushing at it

-- a cold light from your side onto its face, so the scare is seen even in
-- pitch black (only on your screen)
local faceLamp = Instance.new("Part")
faceLamp.Name = "CrawlerFaceLight"
faceLamp.Size = Vector3.new(0.2, 0.2, 0.2)
faceLamp.Transparency = 1
faceLamp.Anchored = true
faceLamp.CanCollide, faceLamp.CanQuery, faceLamp.CanTouch = false, false, false
faceLamp.CastShadow = false
local faceLight = Instance.new("SpotLight")
faceLight.Face = Enum.NormalId.Front
faceLight.Angle = 70
faceLight.Range = 16
faceLight.Brightness = 0
faceLight.Color = Color3.fromRGB(215, 222, 255)
faceLight.Shadows = true
faceLight.Parent = faceLamp
local FACE_LIGHT = 4.2
local EXPOSURE_KICK = 0.6

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
	-- hide your own body from the inside (it only gets in the way) but keep
	-- your arms: they come up between you and it
	table.clear(hidden)
	table.clear(arms)
	local character = player.Character
	if character then
		-- your arms are the arm parts plus everything welded onto them
		-- (sleeves, gloves, wrist tape...): all of that stays in view
		local links = {}
		for _, w in ipairs(character:GetDescendants()) do
			if (w:IsA("Weld") or w:IsA("WeldConstraint") or w:IsA("ManualWeld")) and w.Part0 and w.Part1 then
				links[w.Part0] = links[w.Part0] or {}
				links[w.Part1] = links[w.Part1] or {}
				table.insert(links[w.Part0], w.Part1)
				table.insert(links[w.Part1], w.Part0)
			end
		end
		local BODY = { Torso = true, Head = true, ["Left Leg"] = true, ["Right Leg"] = true, HumanoidRootPart = true }
		local onArm = {}
		for _, name in ipairs({ "Left Arm", "Right Arm" }) do
			local arm = character:FindFirstChild(name)
			if arm then
				onArm[arm] = "skin"
				local queue = { arm }
				while #queue > 0 do
					local part = table.remove(queue)
					for _, other in ipairs(links[part] or {}) do
						if not onArm[other] and not BODY[other.Name] and other.Parent then
							onArm[other] = "worn"
							table.insert(queue, other)
						end
					end
				end
			end
		end
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				local kind = onArm[d]
				if kind then
					arms[d] = { ltm = d.LocalTransparencyModifier, color = d.Color }
					if kind == "skin" then
						-- (bare skin shaded down a little: right under its light, it glares)
						d.Color = d.Color:Lerp(Color3.fromRGB(40, 30, 26), 0.45)
					end
				else
					hidden[d] = d.LocalTransparencyModifier
				end
			end
		end
	end
	faceLamp.Parent = glowFolder
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
	for part, saved in pairs(arms) do
		if part.Parent then
			part.LocalTransparencyModifier = saved.ltm
			part.Color = saved.color
		end
	end
	table.clear(arms)
	TweenService:Create(faceLight, fade, { Brightness = 0 }):Play()
	task.delay(0.7, function()
		if not myCatch then
			faceLamp.Parent = nil
		end
	end)
	player:SetAttribute("ExposureBoost", nil)
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
		-- (aimed between its mouth and its eyes, so you get both)
		local aim = body.headCF and mouthPos:Lerp(body.headCF.Position, 0.4) or mouthPos
		local look = CFrame.lookAt(eyePos, aim)
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
		if myCatch then
			for part in pairs(arms) do
				if part.Parent then
					part.LocalTransparencyModifier = 0
				end
			end
			-- light its face from part way between you and it (in front of your
			-- arms, so they stay dark shapes against its lit face), and open the
			-- exposure up
			local eye = cam.CFrame.Position
			local from = eye:Lerp(mouthPos, 0.42) - cam.CFrame.UpVector * 0.25
			faceLamp.CFrame = CFrame.lookAt(from, mouthPos)
			-- (softer the closer it is, so its face never burns out to white)
			local near = math.clamp(((mouthPos - from).Magnitude - 0.8) / 3.5, 0.55, 1)
			faceLight.Brightness = FACE_LIGHT * near * camWeight * (0.88 + 0.12 * math.noise(now * 9, 3.7))
			-- (the kick is for the dark: with the lights on it only needs a touch)
			local power = ReplicatedStorage:FindFirstChild("Power")
			local lit = power and power:GetAttribute("On") == true
			player:SetAttribute("ExposureBoost", EXPOSURE_KICK * camWeight * (lit and 0.25 or 1))
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

--------------------------------------------------
-- YOUR ARMS, PUSHING AT ITS FACE (only on the caught player's screen)
--------------------------------------------------

local function pushArm(motor, torsoCF, target, w)
	if not motor then
		return
	end
	local shoulder = torsoCF * motor.C0.Position
	local reach = target - shoulder
	if reach.Magnitude < 0.1 then
		return
	end
	-- the arm's length runs along its Y axis: point it from the shoulder at its face
	local up = -reach.Unit
	local right = torsoCF.RightVector - up * torsoCF.RightVector:Dot(up)
	right = right.Magnitude > 1e-3 and right.Unit or torsoCF.LookVector
	local rot = CFrame.fromMatrix(Vector3.zero, right, up, right:Cross(up))
	local armCF = Shared.atPivot(rot, motor.C1.Position, shoulder)
	local want = motor.C0:Inverse() * torsoCF:Inverse() * armCF * motor.C1
	victimOut[motor] = (victimOut[motor] or CFrame.identity):Lerp(want, w)
end

local function pushArms(joints, torsoCF, headCF, now)
	local cam = workspace.CurrentCamera
	if not (mouthPos and cam and torsoCF and headCF) then
		return
	end
	local distance = (mouthPos - headCF.Position).Magnitude
	local w = Shared.smooth((5.5 - distance) / 2) * math.max(camWeight, 0.3)
	if w < 0.01 then
		return
	end
	local right = cam.CFrame.RightVector
	local down = -cam.CFrame.UpVector
	for _, spec in ipairs({ { joints.rs, 1, 0.3 }, { joints.ls, -1, 7.1 } }) do
		-- each hand shoves at its jaw from its own side, shaking with effort,
		-- now and then slipping off and grabbing again
		local slip = math.max(math.noise(now * 1.3, spec[3]) - 0.25, 0) * 1.6
		local tremble = Vector3.new(math.noise(now * 11, spec[3], 1), math.noise(now * 13, spec[3], 2), math.noise(now * 12, spec[3], 3)) * 0.22
		local target = mouthPos + right * (spec[2] * (0.75 + slip * 0.4)) + down * (0.3 + slip * 0.5) + tremble
		pushArm(spec[1], torsoCF, target, w)
	end
end

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
		ceilL = monster:GetAttribute("CatchCeilL") or 8,
		start = monster:GetAttribute("CatchStart") or 0,
		victimId = victimId,
		frame = { base = base, f = dir, r = dir:Cross(Vector3.new(0, 1, 0)), standY = standY },
		env = {
			hold = monster:GetAttribute("CatchHold") or Config.HOLD_DISTANCE,
			standY = standY,
			clear = monster:GetAttribute("CatchClear") or 99,
			back = monster:GetAttribute("CatchBack") or 14,
			yank = monster:GetAttribute("CatchYank") or 0,
			fling = monster:GetAttribute("CatchFling") or 0,
			side = monster:GetAttribute("CatchSide") or 1,
		},
	}
end

-- how far into a catch we are (testing: your player's "CrawlerFreezeAt"
-- attribute holds every catch at that moment, on your screen only)
local function catchTime(catch, serverNow)
	local t = math.max(serverNow - catch.start, 0)
	local freeze = player:GetAttribute("CrawlerFreezeAt")
	return freeze and math.min(t, freeze) or t
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

local nanWarned = false
local climbSeen, climbCorners = nil, 0
local dropSeen, dropLanded = nil, true
local nextCreak = 0
local ceilingScrape = makeSound("CeilingScrape", torso)
if ceilingScrape then
	ceilingScrape.Looped = true
	ceilingScrape.Volume = 0
	ceilingScrape:Play()
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
		local t = catchTime(catch, serverNow)
		local def = catch.def
		local victim = Players:GetPlayerByUserId(catch.victimId)
		local character = victim and victim.Character
		local joints = character and jointsOf(character)

		if joints and t < def.length then
			table.clear(victimOut)
			local hrpCF, torsoCF, headCF = Body.poseVictim(catch.kind, t, catch.env, catch.frame, joints, victimOut, victimV)
			joints.hrp.CFrame = hrpCF
			-- (in a duct you're clawing at the metal ahead, not pushing at it)
			if catch.victimId == player.UserId and not catch.def.vent then
				pushArms(joints, torsoCF, headCF, now)
			end
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

	--------------------------------------------------
	-- where its body is: the floor, a wall, the ceiling, or falling
	--------------------------------------------------
	local stateTime = serverNow - stateStart
	local surface = monster:GetAttribute("Surface") or "Floor"
	local space, vRoot, vCast = nil, root.CFrame, cast
	local stare = false
	local flip = false
	if state == "ClimbUp" then
		local plan = Shared.readClimb(monster)
		if plan then
			local s = math.clamp((serverNow - plan.start) * plan.speed, 0, plan.total)
			space, vRoot = Shared.climbSpace(plan, s)
			vCast = flatCast(plan.p0.Y - plan.h)
			ceilingSpace = Shared.climbSpace(plan, plan.total)
			-- its joints crack as it bends itself round each corner
			local key = plan.start
			if climbSeen ~= key then
				climbSeen, climbCorners = key, 0
				play("Chatter", headPart, 0.8)
			end
			if climbCorners < 1 and s >= plan.c1 - 0.6 then
				climbCorners = 1
				play("BoneCrack", torso, 1, 0.9)
				play("BoneCrack", headPart, 0.8, 1.2)
				play("HandStep", torso, 1.4)
			elseif climbCorners < 2 and s >= plan.c2 - 0.6 then
				climbCorners = 2
				play("BoneCrack", torso, 1, 0.8)
				play("BoneCrack", headPart, 0.9, 1.1)
				play("Creak", torso, 0.8)
			end
		end
	elseif surface == "Ceiling" then
		space = ceilingSpace or DEFAULT_CEILING
		vRoot = space:Inverse() * (root.CFrame * CFrame.Angles(0, 0, math.pi))
		vCast = spaceCast(space)
		-- up there it stares at whoever's below, head twisted the right way up
		local myHead = player.Character and player.Character:FindFirstChild("Head")
		if state == "Watch" then
			flip = true
		elseif not target and myHead and (myHead.Position - root.Position).Magnitude < 24 then
			target = myHead.Position
			stare = true
			flip = true
		end
	else
		ceilingSpace = nil
		if state == "Drop" then
			-- falling off the ceiling: it lets go, twists over and lands
			local quiet = monster:GetAttribute("DropQuiet") == true
			local duration = quiet and Config.QUIET_DROP_TIME or Config.DROP_TIME
			local a = math.clamp(stateTime / duration, 0, 1)
			local hang = quiet and 1 - Shared.smooth(a) or 1 - a * a
			if hang > 0.001 then
				space = Shared.hangSpace(root.CFrame, (monster:GetAttribute("DropL") or 8) * hang,
					Shared.smooth((hang - 0.15) / 0.85))
			end
			if dropSeen ~= stateStart then
				dropSeen, dropLanded = stateStart, false
				play("BoneCrack", torso, 1, 0.85)
				if not quiet then
					play("Lunge", headPart, 0.7, 1.1)
				end
			end
			if not dropLanded and a >= 1 then
				dropLanded = true
				play("Land", torso, quiet and 0.45 or 1)
				body.offset.v += Vector3.new(0, quiet and -3 or -7, 0)
				if not quiet then
					local cam = workspace.CurrentCamera
					local distance = cam and (cam.CFrame.Position - root.Position).Magnitude or 999
					camShake += 0.8 * math.clamp(1 - distance / 40, 0, 1)
				end
			end
		end
		if catch and catch.def.fromCeiling and catch.def.crawler.drop then
			-- it came down on you from the ceiling
			local hang = Shared.sample(catch.def.crawler.drop, catchTime(catch, serverNow))
			if hang > 0.001 then
				space = Shared.hangSpace(root.CFrame, catch.ceilL * hang, Shared.smooth((hang - 0.15) / 0.85))
			end
		end
	end

	-- what it looks at and holds, in its floor version
	local vTarget, vCatch = target, catchInput
	if space then
		local inv = space:Inverse()
		vTarget = target and inv * target
		if catchInput then
			vCatch = table.clone(catchInput)
			vCatch.victimTorso = catchInput.victimTorso and inv * catchInput.victimTorso
			vCatch.victimHead = catchInput.victimHead and inv * catchInput.victimHead
		end
	end

	local out, events = body:update({
		dt = accum,
		now = now,
		root = vRoot,
		actualRoot = root.CFrame,
		space = space,
		cast = vCast,
		state = state,
		stateTime = stateTime,
		stateStart = stateStart,
		chasing = monster:GetAttribute("Chasing") == true,
		target = vTarget,
		stare = stare,
		flip = flip,
		catch = vCatch,
	})
	accum = 0
	-- (never let a bad frame poison the body: start it fresh instead)
	local check = out[rig.root]
	if not check or check.X ~= check.X or check.XVector.X ~= check.XVector.X then
		if not nanWarned then
			nanWarned = true
			warn("CrawlerAnimator: body went NaN", state, surface, space, vRoot, catch and catch.kind, stateTime)
		end
		body = Body.new(rig, bodyInfo)
		return
	end
	for motor, cf in pairs(out) do
		motor.Transform = cf
	end
	mouthPos = body.mouth

	-- claws dragging across the ceiling, and the ceiling groaning under it
	local up = surface == "Ceiling" or state == "ClimbUp"
	if ceilingScrape then
		local speed = Vector3.new(body.vel.X, 0, body.vel.Z).Magnitude
		local goal = up and Config.Sounds.CeilingScrape.Volume * math.clamp(speed / 5, 0, 1.2) or 0
		ceilingScrape.Volume += (goal - ceilingScrape.Volume) * math.clamp(dt * 6, 0, 1)
	end
	if up and now >= nextCreak then
		nextCreak = now + 3 + math.random() * 5
		local creak = makeSound("Creak", torso, 0.6 + math.random() * 0.5)
		if creak then
			creak.TimePosition = math.random() * 4
			creak:Play()
			task.delay(1.2 + math.random() * 0.8, function()
				TweenService:Create(creak, TweenInfo.new(0.3), { Volume = 0 }):Play()
				Debris:AddItem(creak, 0.4)
			end)
		end
	elseif not up then
		nextCreak = math.max(nextCreak, now + 1)
	end
	updateGlow(dt, now, catch ~= nil and catch.start ~= nil and catchTime(catch, serverNow) < catch.def.length + 0.4,
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
