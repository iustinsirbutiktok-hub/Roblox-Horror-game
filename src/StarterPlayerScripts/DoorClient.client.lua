-- DoorClient
-- Place in: StarterPlayer > StarterPlayerScripts (a LocalScript named "DoorClient")
--
-- Everything you see and hear of the doors:
--   * look at a door and LEFT CLICK to open or close it. It swings on a spring:
--     a wooden door flaps and bounces off its frame, a steel one drags heavily,
--     a cell gate squeals round. Mobile gets a USE button.
--   * when the Crawler is hunting nearby, E (or HOLD on mobile) slams the door
--     and you throw your weight against it: palms flat on the wood, shoulder
--     in, back leg braced. You see your own hands on the door.
--   * when it hits the door the dial comes up. Push when the red blade
--     crosses the white: every push it slams the door and you hold it; every
--     miss it smashes the door into you and you stagger. 7-8 good pushes and
--     it gives up. 3 misses and the door bursts and throws you on your back.
--   * everyone else sees all of it: your lean, every slam, the door bowing,
--     the dust, the door blowing apart.
--
-- Needs: DoorConfig (ReplicatedStorage) and the DoorSystem/DoorServer scripts.
-- Works with ThirdPersonHorrorCamera: add IsBarricading to its
-- isExternallyControlled list (see the snippet on the scripts page).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("DoorConfig"))
local remote = ReplicatedStorage:WaitForChild("Doors"):WaitForChild("DoorRemote")

local player = Players.LocalPlayer
local UP = Vector3.new(0, 1, 0)
local rad, sin, cos, abs, clamp = math.rad, math.sin, math.cos, math.abs, math.clamp
local rng = Random.new()

local function smooth(a)
	a = clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function angleDiff(a, b)
	return (a - b + 180) % 360 - 180
end

-- a damped spring: w = how fast, z = damping (1 = no wobble)
local function spring(s, goal, w, z, dt)
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for _ = 1, steps do
		s.v += (w * w * (goal - s.x) - 2 * z * w * s.v) * h
		s.x += s.v * h
	end
end

local function newSpring(x)
	return { x = x or 0, v = 0 }
end

local function myCharacter()
	local c = player.Character
	return c, c and c:FindFirstChild("HumanoidRootPart")
end

-- the camera script reads these: a short jolt of the view
local function shake(seconds, amount)
	local c = player.Character
	if not c then
		return
	end
	local untilT = os.clock() + seconds
	if (c:GetAttribute("ShakeUntil") or 0) > untilT and (c:GetAttribute("ShakeAmount") or 0) > amount then
		return
	end
	c:SetAttribute("ShakeUntil", untilT)
	c:SetAttribute("ShakeAmount", amount)
end

--------------------------------------------------
-- SOUND
--------------------------------------------------

local function makeSound(name, parent, volume, speed)
	local spec = Config.Sounds[name]
	if not spec or spec.Id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = spec.Id
	s.Volume = spec.Volume * (volume or 1)
	s.PlaybackSpeed = spec.Speed * (speed or 1) * rng:NextNumber(0.95, 1.05)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = math.max(spec.Range, 10)
	s.Parent = parent
	return s
end

local function playAt(name, position, volume, speed)
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = workspace.Terrain
	local s = makeSound(name, a, volume, speed)
	if s then
		s:Play()
	end
	Debris:AddItem(a, 8)
end

-- only you hear it (heartbeat, the bolt)
local function playLocal(name, volume, speed)
	local s = makeSound(name, SoundService, volume, speed)
	if s then
		s:Play()
		Debris:AddItem(s, 8)
	end
	return s
end

--------------------------------------------------
-- THE DOORS
--------------------------------------------------

local doors = {}       -- model -> door
local byPart = {}      -- leaf part -> model

local fxFolder = Instance.new("Folder")
fxFolder.Name = "DoorFX"
fxFolder.Parent = workspace

-- an invisible part for particles to come out of (only on your screen)
local function fxPart(name, cf, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	p.Parent = fxFolder
	return p
end

-- dust shaken loose from the top of the frame, and sparks off metal
local function makeEffects(door)
	local a = fxPart("DoorDust", door.centre * CFrame.new(0, door.height / 2 - 0.15, 0), Vector3.new(door.width, 0.2, 0.6))
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(120, 108, 92), Color3.fromRGB(70, 64, 58))
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 1) })
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 2.2) })
	dust.Lifetime = NumberRange.new(1.2, 2.6)
	dust.Speed = NumberRange.new(0.5, 2.5)
	dust.SpreadAngle = Vector2.new(60, 25)
	dust.Acceleration = Vector3.new(0, -1.6, 0)
	dust.Drag = 1.5
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.EmissionDirection = Enum.NormalId.Bottom
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.LightInfluence = 1
	dust.Rate = 0
	dust.Parent = a
	door.dust = dust

	local s = fxPart("DoorSparks", door.centre * CFrame.new(door.width / 2 - 0.2, -door.height / 2 + 3.4, 0), Vector3.new(0.2, 2, 0.4))
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 190, 110), Color3.fromRGB(255, 90, 30))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.15, 0.45)
	sparks.Speed = NumberRange.new(8, 18)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.Rate = 0
	sparks.Parent = s
	door.sparks = sparks
	door.effects = { a, s }
end

local function register(model)
	if doors[model] or not model:IsA("Model") then
		return
	end
	local kind = model:GetAttribute("DoorType")
	local hinge, centre = model:GetAttribute("Hinge"), model:GetAttribute("Centre")
	if not (Config.TYPES[kind] and typeof(hinge) == "CFrame" and typeof(centre) == "CFrame") then
		return
	end
	local leaf = model:WaitForChild("Leaf", 10)
	if not leaf or doors[model] then
		return
	end
	local angle = model:GetAttribute("Angle") or 0
	local door = {
		model = model, leaf = leaf, kind = kind, cfg = Config.TYPES[kind],
		hinge = hinge, centre = centre,
		width = model:GetAttribute("Width") or 4, height = model:GetAttribute("Height") or 7,
		angle = newSpring(angle), target = angle, style = "normal",
		kick = newSpring(0), kickHold = 0, kickUntil = 0, rattle = 0,
		predictUntil = 0, predictedOpen = false,
		moving = false, broken = model:GetAttribute("Broken") == true,
		dust = nil, sparks = nil, effects = {},
	}
	doors[model] = door
	local function add(p)
		if p:IsA("BasePart") then
			byPart[p] = model
		end
	end
	for _, p in ipairs(leaf:GetDescendants()) do
		add(p)
	end
	leaf.DescendantAdded:Connect(add)
	makeEffects(door)

	model:GetAttributeChangedSignal("Angle"):Connect(function()
		local a = model:GetAttribute("Angle") or 0
		local style = model:GetAttribute("MoveStyle") or "normal"
		local was = door.target
		door.target, door.style, door.predictUntil = a, style, 0
		door.moving = true
		if was == 0 and a ~= 0 and not door.predictedOpen then
			local where = door.centre.Position
			if style == "creep" then
				playAt(door.cfg.sounds.open, where, 0.9, 0.7)
			elseif style == "shove" then
				playAt(door.cfg.sounds.open, where, 1.1, 1.25)
				playAt(door.cfg.sounds.hit, where, 0.8, 1)
			else
				playAt(door.cfg.sounds.open, where)
			end
		end
		door.predictedOpen = false
	end)
	model:GetAttributeChangedSignal("Broken"):Connect(function()
		door.broken = model:GetAttribute("Broken") == true
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			for _, e in ipairs(door.effects) do
				e:Destroy()
			end
			doors[model] = nil
		end
	end)
end

for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") and d:GetAttribute("DoorType") then
		task.spawn(register, d)
	end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") then
		task.defer(function()
			if d:GetAttribute("DoorType") then
				register(d)
			end
		end)
	end
end)

local function side(door, position)
	return door.centre:PointToObjectSpace(position).Z >= 0 and 1 or -1
end

-- the door shudders (a slam on it): `degrees` towards side `towards`, held a moment
local function kickDoor(door, degrees, hold, towards)
	local s = -(towards or 1)        -- a positive angle swings it away from +Z
	door.kick.v += s * degrees * 14
	door.kickHold = s * degrees
	door.kickUntil = os.clock() + (hold or 0)
	door.moving = true
end

-- how each kind of door moves for each kind of push
local function feel(door)
	local cfg = door.cfg
	local style = door.style
	if style == "creep" then
		return cfg.speed * 0.32, 1
	elseif style == "shove" then
		return cfg.speed * 1.5, math.max(cfg.bounce * 0.6, 0.25)
	elseif style == "slam" then
		return cfg.speed * 2.1, cfg.bounce * 0.8
	end
	return cfg.speed, 0.55 + cfg.bounce * 0.4
end

local RESTITUTION = { Wood = 0.22, Steel = 0.07, Cell = 0.28 }

local function stepDoor(door, dt, now, camPos)
	if door.broken or not door.leaf.Parent then
		return
	end
	if door.predictUntil > 0 and now > door.predictUntil then
		-- the server didn't agree: go back to how it really is
		door.predictUntil = 0
		door.target = door.model:GetAttribute("Angle") or 0
		door.moving = true
	end
	local fighting = door.model:GetAttribute("Fighting") == true
	if not door.moving and not fighting then
		return
	end
	if (door.centre.Position - camPos).Magnitude > 300 then
		door.angle.x, door.angle.v, door.kick.x, door.kick.v = door.target, 0, 0, 0
		door.leaf:PivotTo(door.hinge * CFrame.Angles(0, rad(door.target), 0))
		door.moving = false
		return
	end

	local w, z = feel(door)
	local prev = door.angle.x
	spring(door.angle, door.target, w, z, dt)
	-- closing, it can't go through the frame: it bangs into it and bounces
	if door.target == 0 and prev ~= 0 and (prev > 0) ~= (door.angle.x > 0) then
		local impact = abs(door.angle.v)
		door.angle.x = 0
		door.angle.v = -door.angle.v * RESTITUTION[door.kind]
		if impact > 25 then
			local loud = clamp(impact / (door.cfg.openAngle * door.cfg.speed * 0.5), 0.25, 1.3)
			local sounds = door.cfg.sounds
			playAt(door.style == "slam" and sounds.slam or sounds.close, door.centre.Position, loud)
			if impact > 120 then
				door.dust:Emit(math.floor(6 + 14 * loud))
			end
		end
	end

	-- slams against it, and the thing leaning on the other side
	local hold = now < door.kickUntil and door.kickHold or 0
	spring(door.kick, hold, 24, 0.32, dt)
	local rattle = 0
	if fighting then
		door.rattle += dt
		rattle = math.noise(door.rattle * 7, 0.5) * 0.7
	end

	door.leaf:PivotTo(door.hinge * CFrame.Angles(0, rad(door.angle.x + door.kick.x + rattle), 0))
	if abs(door.angle.x - door.target) < 0.05 and abs(door.angle.v) < 0.5
		and abs(door.kick.x) < 0.02 and abs(door.kick.v) < 0.5 and not fighting then
		door.angle.x, door.angle.v, door.kick.x, door.kick.v = door.target, 0, 0, 0
		door.leaf:PivotTo(door.hinge * CFrame.Angles(0, rad(door.target), 0))
		door.moving = false
	end
end

--------------------------------------------------
-- BREAKING (everyone sees the splinters fly)
--------------------------------------------------

local function burst(door, push)
	door.broken = true
	local centre = door.centre
	local where = centre.Position
	local sounds = door.cfg.sounds
	playAt(sounds.breaks, where, 1)
	playAt(sounds.slam, where, 1.2, 0.85)
	door.dust:Emit(90)
	if door.kind ~= "Wood" then
		door.sparks:Emit(45)
	end

	-- floor dust thrown out where it lands
	local low = fxPart("DoorBurst", centre * CFrame.new(0, -door.height / 2 + 0.3, 0), Vector3.new(door.width, 0.2, 1))
	local puff = door.dust:Clone()
	puff.EmissionDirection = Enum.NormalId.Top
	puff.SpreadAngle = Vector2.new(80, 80)
	puff.Speed = NumberRange.new(4, 9)
	puff.Parent = low
	puff:Emit(70)
	Debris:AddItem(low, 4)

	-- bits only you simulate
	local folder = Instance.new("Folder")
	folder.Name = "DoorDebris"
	folder.Parent = fxFolder
	Debris:AddItem(folder, 7)
	local count = door.kind == "Wood" and 22 or 12
	for _ = 1, count do
		local p = Instance.new("Part")
		if door.kind == "Wood" then
			p.Size = Vector3.new(rng:NextNumber(0.08, 0.2), rng:NextNumber(0.08, 0.16), rng:NextNumber(0.4, 1.6))
			p.Color = Color3.fromRGB(78, 58, 40):Lerp(Color3.fromRGB(150, 120, 86), rng:NextNumber(0, 0.6))
			p.Material = Enum.Material.Wood
		else
			p.Size = Vector3.new(rng:NextNumber(0.08, 0.25), rng:NextNumber(0.04, 0.08), rng:NextNumber(0.1, 0.35))
			p.Color = Color3.fromRGB(96, 52, 30):Lerp(Color3.fromRGB(40, 36, 34), rng:NextNumber(0, 1))
			p.Material = Enum.Material.CorrodedMetal
		end
		p.CFrame = centre * CFrame.new(rng:NextNumber(-door.width / 2, door.width / 2), rng:NextNumber(-door.height / 2 + 0.5, door.height / 2 - 0.5), 0)
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		p.CanQuery, p.CanTouch = false, false
		p.CanCollide = true
		p.CastShadow = false
		p.Parent = folder
		p.AssemblyLinearVelocity = push * rng:NextNumber(14, 34) + UP * rng:NextNumber(2, 12)
			+ centre:VectorToWorldSpace(Vector3.new(rng:NextNumber(-8, 8), 0, 0))
		p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-25, 25), rng:NextNumber(-25, 25), rng:NextNumber(-25, 25))
	end

	local _, hrp = myCharacter()
	if hrp then
		local d = (hrp.Position - where).Magnitude
		if d < 45 then
			shake(0.6, 10 * (1 - d / 45))
		end
	end
end

--------------------------------------------------
-- BODIES ON DOORS (yours and everyone else's)
--------------------------------------------------
-- R6. Hands are planted on the door and feet on the floor: each rigid limb is
-- swung so its end lands exactly on the surface, as close to where it wants
-- to be as its length allows. All angles are around the parent part's axes,
-- the same way DownedClient poses you.

local posers = {}      -- character -> poser

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
	-- from each joint to the far end of its limb, at rest (in the torso's axes)
	local function reach(motor)
		local part = motor.Part1
		local size = part and part.Size or Vector3.new(1, 2, 1)
		return (motor.C0 * motor.C1:Inverse() * Vector3.new(0, -size.Y / 2, 0)) - motor.C0.Position
	end
	j.uRA, j.uLA, j.uRL, j.uLL = reach(j.rs), reach(j.ls), reach(j.rh), reach(j.lh)
	return j
end

-- the turn that takes direction a onto direction b
local function between(a, b)
	local axis = a:Cross(b)
	local s = axis.Magnitude
	if s < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, a:Dot(b)))
end

-- swing a limb hanging from `pivot` (rest vector `u`) so its end lands on the
-- plane through `onPlane` (normal `n`, facing the limb), near `want`
local function plant(pivot, u, want, onPlane, n)
	local r = u.Magnitude
	local h = math.max((pivot - onPlane):Dot(n), 0.05)
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

local function conj(motor, cf)
	local rest = motor.C0.Rotation
	return rest:Inverse() * cf * rest
end

-- the same, but backed off so the limb's square end sits flat against the
-- surface instead of its corners digging in
local function plantFlat(motor, u, want, onPlane, n)
	local r = plant(motor.C0.Position, u, want, onPlane, n)
	local axes = r * (motor.C0.Rotation * motor.C1.Rotation:Inverse())
	local size = motor.Part1 and motor.Part1.Size or Vector3.new(1, 2, 1)
	local back = abs(axes.XVector:Dot(n)) * size.X / 2 + abs(axes.ZVector:Dot(n)) * size.Z / 2
	return plant(motor.C0.Position, u, want, onPlane + n * back, n)
end

-- where a limb or the torso ends up, in the root part's space
local function limbIn(torso, motor, r)
	return torso * motor.C0 * conj(motor, r) * motor.C1:Inverse()
end

local function lowest(cf, size)
	local y = math.huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				y = math.min(y, (cf * Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)).Y)
			end
		end
	end
	return y
end

-- leaning into the door. s = the pose numbers (see poseBrace)
local function solveBrace(j, s)
	local rootCF = CFrame.new(s.x, -s.drop, -s.fwd) * CFrame.Angles(-rad(s.lean), rad(s.twist), rad(s.roll))
	local torso = j.root.C0 * conj(j.root, rootCF) * j.root.C1:Inverse()     -- torso, in the root part's space
	local function toTorso(p)
		return torso:PointToObjectSpace(p)
	end
	local doorN = torso:VectorToObjectSpace(Vector3.new(0, 0, 1))
	local doorP = toTorso(Vector3.new(0, 0, -s.handPlane))
	local floorN = torso:VectorToObjectSpace(UP)
	local floorP = toTorso(Vector3.new(0, -s.floor, 0))
	return {
		root = rootCF,
		neck = CFrame.Angles(-rad(s.neck), rad(s.neckYaw), rad(s.neckRoll)),
		rs = plantFlat(j.rs, j.uRA, toTorso(s.rHand), doorP, doorN),
		ls = plantFlat(j.ls, j.uLA, toTorso(s.lHand), doorP, doorN),
		rh = plantFlat(j.rh, j.uRL, toTorso(s.rFoot), floorP, floorN),
		lh = plantFlat(j.lh, j.uLL, toTorso(s.lFoot), floorP, floorN),
	}
end

-- the door's face, in front of the root part (it stands 1.75 from the door's middle)
local HAND_PLANE = 1.75 - 0.24

-- p = poser, t = seconds leaning, now = clock
local function poseBrace(p, t, now)
	local breath = sin(t * 5.4)                                   -- fast, scared breathing
	local scared = 0.6 + 0.45 * p.misses
	local tremble = math.noise(now * 9, p.seed) * scared
	local sway = math.noise(now * 0.7, p.seed + 3.3)
	local drive, recoil = p.drive.x, p.recoil.x
	local slipR, slipL = p.slipR.x, p.slipL.x
	local H = p.height
	return {
		lean = 15 + 7 * drive - 24 * recoil + breath * 1.4 + tremble * 0.7,
		fwd = -0.02 - 0.06 * drive - 0.55 * recoil,
		drop = 0.12 + 0.05 * drive + 0.08 * recoil - breath * 0.015,
		x = sway * 0.06,
		twist = 4 + sway * 3 - recoil * 7,
		roll = sway * 2 + tremble * 0.6 + recoil * p.slipSide * 6,
		neck = 5 + 4 * drive - 20 * recoil + breath * 1.5,
		neckYaw = 14 * math.noise(now * 0.35, p.seed + 7.1) + p.slipSide * recoil * 10,
		neckRoll = tremble * 1.5,
		handPlane = HAND_PLANE - 0.45 * recoil,
		rHand = Vector3.new(0.55, 1.05 + breath * 0.03 - 0.75 * slipR, -HAND_PLANE),
		lHand = Vector3.new(-0.55, 1.12 + breath * 0.03 - 0.75 * slipL, -HAND_PLANE),
		rFoot = Vector3.new(0.8, -H, -0.3),
		lFoot = Vector3.new(-0.75, -H, 1.35),
		floor = H - 0.02,
	}
end

-- thrown off the door: knocked onto your back, lie there a second, get up.
-- { time, value, ease } - the ease is how it moves INTO that key
local function thrownKeys(H)
	return {
		height = { { 0, H - 0.12 }, { 0.1, H - 0.4 }, { 0.42, 0.55, "in2" }, { 0.5, 0.75, "out2" }, { 0.6, 0.5, "in2" },
			{ 1.35, 0.5 }, { 1.75, 1.45, "out2" }, { 2.05, 1.4 }, { 2.28, H - 0.4 }, { 2.5, H, "out2" } },
		lean = { { 0, 12 }, { 0.1, -32, "out2" }, { 0.42, -86, "in2" }, { 0.5, -80, "out2" }, { 0.6, -85 },
			{ 1.35, -84 }, { 1.75, -22, "out2" }, { 2.05, 10 }, { 2.28, 18 }, { 2.5, 0, "out2" } },
		roll = { { 0, 0 }, { 0.5, 0 }, { 0.8, 7 }, { 1.15, -5 }, { 1.5, 16 }, { 1.9, 4 }, { 2.5, 0 } },
		twist = { { 0, 8 }, { 0.3, -10 }, { 0.6, 0 }, { 1.6, 12 }, { 2.1, -6 }, { 2.5, 0 } },
		neck = { { 0, 0 }, { 0.1, 32, "out2" }, { 0.42, -12 }, { 0.5, 24, "out2" }, { 0.75, 14 }, { 1.2, 30 },
			{ 1.6, 18 }, { 2.05, 5 }, { 2.5, 0 } },
		rSwing = { { 0, 70 }, { 0.1, 125, "out2" }, { 0.42, 160 }, { 0.5, 120, "out2" }, { 0.7, 60 }, { 1.35, 45 },
			{ 1.6, -15 }, { 1.95, -30 }, { 2.28, 25 }, { 2.5, 0, "out2" } },
		lSwing = { { 0, 70 }, { 0.12, 110, "out2" }, { 0.42, 150 }, { 0.5, 105, "out2" }, { 0.75, 30 }, { 1.35, 20 },
			{ 1.6, -25 }, { 1.95, -35 }, { 2.28, 10 }, { 2.5, 0, "out2" } },
		rOut = { { 0, 10 }, { 0.1, 38 }, { 0.42, 55 }, { 0.6, 40 }, { 1.35, 28 }, { 1.75, 18 }, { 2.5, 0 } },
		lOut = { { 0, 10 }, { 0.1, 30 }, { 0.42, 60 }, { 0.6, 45 }, { 1.35, 35 }, { 1.75, 15 }, { 2.5, 0 } },
		rHip = { { 0, 0 }, { 0.1, 20 }, { 0.42, 40 }, { 0.5, 10, "in2" }, { 0.7, 18 }, { 1.35, 14 }, { 1.75, 75 },
			{ 2.05, 80 }, { 2.28, 50 }, { 2.5, 0, "out2" } },
		lHip = { { 0, 0 }, { 0.1, 30 }, { 0.42, 50 }, { 0.5, 6, "in2" }, { 0.7, 4 }, { 1.35, 30 }, { 1.75, 85 },
			{ 2.05, 40 }, { 2.28, -14 }, { 2.5, 0, "out2" } },
		rHipOut = { { 0, 4 }, { 0.5, 12 }, { 1.35, 10 }, { 2.05, 6 }, { 2.5, 0 } },
		lHipOut = { { 0, 4 }, { 0.5, 10 }, { 1.35, 16 }, { 2.05, 6 }, { 2.5, 0 } },
	}
end

local function ease(kind, a)
	if kind == "in2" then
		return a * a
	elseif kind == "out2" then
		return 1 - (1 - a) * (1 - a)
	end
	return a * a * (3 - 2 * a)
end

local function sample(keys, t)
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 2, #keys do
		local k = keys[i]
		if t <= k[1] then
			local prev = keys[i - 1]
			return prev[2] + (k[2] - prev[2]) * ease(k[3], (t - prev[1]) / (k[1] - prev[1]))
		end
	end
	return keys[#keys][2]
end

local function solveThrown(j, p, t)
	local k = p.thrownKeys
	local v = {}
	for name, keys in pairs(k) do
		v[name] = sample(keys, t)
	end
	-- still twitching on the floor
	local writhe = (t > 0.5 and t < 1.4) and 1 or 0
	v.neck += math.noise(t * 3, p.seed) * 10 * writhe
	v.rSwing += math.noise(t * 2.5, p.seed + 2) * 18 * writhe
	v.lHip += math.noise(t * 2.2, p.seed + 4) * 14 * writhe
	local pose = {
		root = CFrame.new(0, -(p.height - v.height), 0) * CFrame.Angles(-rad(v.lean), rad(v.twist), rad(v.roll)),
		neck = CFrame.Angles(-rad(v.neck), 0, 0),
		rs = CFrame.Angles(0, 0, rad(v.rOut)) * CFrame.Angles(rad(v.rSwing), 0, 0),
		ls = CFrame.Angles(0, 0, -rad(v.lOut)) * CFrame.Angles(rad(v.lSwing), 0, 0),
		rh = CFrame.Angles(0, 0, rad(v.rHipOut)) * CFrame.Angles(rad(v.rHip), 0, 0),
		lh = CFrame.Angles(0, 0, -rad(v.lHipOut)) * CFrame.Angles(rad(v.lHip), 0, 0),
	}
	-- never through the floor: lift the whole body if a leg or the torso would go in
	local torso = j.root.C0 * conj(j.root, pose.root) * j.root.C1:Inverse()
	local low = lowest(torso, j.torso.Size or Vector3.new(2, 2, 1))
	for _, key in ipairs({ "rh", "lh" }) do
		local motor = j[key]
		low = math.min(low, lowest(limbIn(torso, motor, pose[key]), motor.Part1 and motor.Part1.Size or Vector3.new(1, 2, 1)))
	end
	local lift = -p.height - low
	if lift > 0 then
		pose.root = CFrame.new(0, lift, 0) * pose.root
	end
	return pose
end

local JOINTS = { "root", "neck", "rs", "ls", "rh", "lh" }

local function floorHeight(character, hrp)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), params)
	return hit and clamp(hrp.Position.Y - hit.Position.Y, 2.4, 3.6) or 3
end

local function getPoser(character)
	local p = posers[character]
	if p then
		return p
	end
	local j = rigOf(character)
	if not j then
		return nil
	end
	p = {
		character = character, j = j, seed = rng:NextNumber(0, 100),
		w = newSpring(0), drive = newSpring(0), recoil = newSpring(0),
		slipR = newSpring(0), slipL = newSpring(0), slipSide = 1, slipUntil = 0, recoilUntil = 0,
		misses = 0, start = os.clock(), thudDone = false,
		height = floorHeight(character, j.hrp), thrownKeys = nil, lastBrace = 0,
		mine = character == player.Character, lookDown = false, landed = false,
	}
	p.thrownKeys = thrownKeys(p.height)
	posers[character] = p
	return p
end

-- a slam landed on the door this body is holding
local function bodySlam(character, kind)
	local p = character and posers[character]
	if not p then
		return
	end
	local now = os.clock()
	if kind == "hit" then
		p.drive.v += 9
		p.recoil.v += 2.5
	else
		p.misses += 1
		p.recoil.v += 16
		p.recoilUntil = now + 0.28
		p.slipSide = rng:NextNumber() < 0.5 and 1 or -1
		p.slipUntil = now + 0.22
	end
end

local function updatePoser(p, dt, now)
	local character = p.character
	local j = p.j
	if not character.Parent or not j.hrp.Parent then
		posers[character] = nil
		return
	end
	local bracing = character:GetAttribute("IsBarricading") == true
	local braceAt = character:GetAttribute("BraceAt") or 0
	if braceAt ~= p.lastBrace and bracing then
		-- a new hold: step in and throw your weight on it
		p.lastBrace = braceAt
		p.start = now
		p.thudDone = false
		p.misses = 0
		p.height = floorHeight(character, j.hrp)
		p.thrownKeys = thrownKeys(p.height)
	end
	local thrownAt = character:GetAttribute("ThrownAt") or 0
	local thrownT = thrownAt > 0 and workspace:GetServerTimeNow() - thrownAt or -1
	if thrownT > 3 then
		thrownT = -1
	end

	spring(p.w, bracing and 1 or 0, bracing and 8 or 11, 0.8, dt)
	spring(p.drive, 0, 11, 0.42, dt)
	spring(p.recoil, now < p.recoilUntil and 1 or 0, 10, 0.55, dt)
	spring(p.slipR, (now < p.slipUntil and p.slipSide > 0) and 1 or 0, 16, 0.5, dt)
	spring(p.slipL, (now < p.slipUntil and p.slipSide < 0) and 1 or 0, 16, 0.5, dt)

	local t = now - p.start
	if bracing and not p.thudDone and t > 0.2 then
		-- shoulder hits the wood
		p.thudDone = true
		p.drive.v += 7
		local link = character:FindFirstChild("BarricadeDoor")
		local door = link and link.Value and doors[link.Value]
		if door then
			playAt(door.cfg.sounds.hit, door.centre.Position, 0.45, 1.2)
			kickDoor(door, 1.2, 0, -(character:GetAttribute("BraceSide") or 1))
		end
		playAt("Brace", j.hrp.Position)
		if p.mine then
			shake(0.2, 2)
		end
	end

	if p.w.x < 0.002 and not bracing then
		for _, key in ipairs(JOINTS) do
			if j[key].Parent then
				j[key].Transform = CFrame.identity
			end
		end
		if p.mine and p.lookDown then
			character:SetAttribute("LookDownDegrees", 0)
		end
		posers[character] = nil
		return
	end

	local pose = solveBrace(j, poseBrace(p, t, now))
	if thrownT >= 0 then
		local thrown = solveThrown(j, p, thrownT)
		local k = smooth(thrownT / 0.08)
		for _, key in ipairs(JOINTS) do
			pose[key] = pose[key]:Lerp(thrown[key], k)
		end
		if p.mine then
			-- flat on your back you're staring at the ceiling
			local want = (thrownT > 0.35 and thrownT < 1.6) and -50 or 0
			if want ~= 0 or p.lookDown then
				character:SetAttribute("LookDownDegrees", want)
				p.lookDown = want ~= 0
			end
			if thrownT > 0.42 and not p.landed then
				p.landed = true
				shake(0.45, 9)
				playAt("Shoved", j.hrp.Position, 1, 0.8)
			end
		end
	else
		p.landed = false
	end

	local weight = p.w.x
	for _, key in ipairs(JOINTS) do
		local motor = j[key]
		motor.Transform = conj(motor, CFrame.identity:Lerp(pose[key], weight))
	end
end

local function watchCharacter(character)
	local function check()
		if character:GetAttribute("IsBarricading") then
			getPoser(character)
		end
	end
	character:GetAttributeChangedSignal("IsBarricading"):Connect(check)
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

-- after the Animator, so the lean wins over walk/idle animations
RunService.PreSimulation:Connect(function(dt)
	local now = os.clock()
	for _, p in pairs(posers) do
		updatePoser(p, dt, now)
	end
end)

--------------------------------------------------
-- THE SCREEN
--------------------------------------------------

local FONT = Enum.Font.SpecialElite
local BONE = Color3.fromRGB(226, 216, 196)
local DIM = Color3.fromRGB(150, 138, 122)
local BLOOD = Color3.fromRGB(150, 14, 14)
local EMBER = Color3.fromRGB(255, 64, 44)
local INK = Color3.fromRGB(9, 7, 7)
local RUST = Color3.fromRGB(58, 40, 34)
local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local gui = Instance.new("ScreenGui")
gui.Name = "DoorGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function label(parent, props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1, Font = FONT, TextColor3 = BONE, TextSize = 20,
		TextStrokeColor3 = INK, TextStrokeTransparency = 0.5,
	}, parent)
	for k, v in pairs(props) do
		l[k] = v
	end
	return l
end

local uiScale = 1
local scales = {}
local function scaled(frame)
	local s = new("UIScale", { Scale = 1 }, frame)
	table.insert(scales, s)
	return s
end

-- the edges of the screen close in while you hold the door
local vignette = new("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local edges = {}
for i, spec in ipairs({
	{ UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0), 90 },
	{ UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.68), -90 },
	{ UDim2.fromScale(0.26, 1), UDim2.fromScale(0, 0), 0 },
	{ UDim2.fromScale(0.26, 1), UDim2.fromScale(0.74, 0), 180 },
}) do
	local f = new("Frame", { Size = spec[1], Position = spec[2], BackgroundColor3 = INK, BorderSizePixel = 0, BackgroundTransparency = 1 }, vignette)
	new("UIGradient", {
		Rotation = spec[3],
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	}, f)
	edges[i] = f
end
local flash = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLOOD, BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)

--------------------------------------------------
-- the prompt: what left click / E will do
--------------------------------------------------

local prompt = new("CanvasGroup", {
	Name = "Prompt", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.86, 0),
	Size = UDim2.fromOffset(420, 84), BackgroundTransparency = 1, GroupTransparency = 1,
}, gui)
scaled(prompt)
new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, prompt)

local function promptRow(order, key, text, colour)
	local row = new("Frame", { Size = UDim2.fromOffset(420, 32), BackgroundTransparency = 1, LayoutOrder = order }, prompt)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10) }, row)
	local chip = new("Frame", { Size = UDim2.fromOffset(52, 26), BackgroundColor3 = INK, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, row)
	new("UIStroke", { Color = colour, Thickness = 1, Transparency = 0.35 }, chip)
	local k = label(chip, { Size = UDim2.fromScale(1, 1), Text = key, TextSize = 15, TextColor3 = colour })
	local l = label(row, { Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Text = text, TextColor3 = colour,
		TextXAlignment = Enum.TextXAlignment.Left })
	return row, k, l
end
local _, _, useText = promptRow(1, touch and "TAP" or "LMB", "OPEN", BONE)
local holdRow, holdKey, holdText = promptRow(2, touch and "HOLD" or "E", "HOLD IT SHUT", EMBER)
holdKey.Text = touch and "HOLD" or Config.HOLD_KEY.Name

-- mobile buttons
local function roundButton(text, pos)
	local b = new("TextButton", {
		AnchorPoint = Vector2.new(1, 1), Position = pos, Size = UDim2.fromOffset(86, 86),
		BackgroundColor3 = INK, BackgroundTransparency = 0.3, AutoButtonColor = false,
		Font = FONT, Text = text, TextColor3 = BONE, TextSize = 18, Visible = false,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
	new("UIStroke", { Color = BONE, Thickness = 1.5, Transparency = 0.4 }, b)
	return b
end
local useButton = roundButton("OPEN", UDim2.new(1, -24, 1, -200))
local holdButton = roundButton("HOLD", UDim2.new(1, -120, 1, -170))
holdButton.TextColor3 = EMBER
local letGoButton = roundButton("LET GO", UDim2.new(1, -24, 1, -200))

-- while you're leaning on it, before it hits
local holdHint = new("CanvasGroup", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.14, 0), Size = UDim2.fromOffset(520, 70),
	BackgroundTransparency = 1, GroupTransparency = 1,
}, gui)
scaled(holdHint)
local holdHintTop = label(holdHint, { Size = UDim2.new(1, 0, 0, 34), Text = "LEAN ON IT. IT'S COMING.", TextSize = 26 })
label(holdHint, { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 22), TextColor3 = DIM, TextSize = 15,
	Text = touch and "LET GO  -  TAP LET GO" or ("LET GO  -  " .. Config.HOLD_KEY.Name) })

-- a line that fades out on its own
local notice = label(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.78, 0), Size = UDim2.fromOffset(600, 30),
	Text = "", TextTransparency = 1, TextStrokeTransparency = 1, TextColor3 = DIM, TextSize = 18 })
local noticeUntil = 0
local function say(text, seconds)
	notice.Text = text
	noticeUntil = os.clock() + (seconds or 1.6)
end

--------------------------------------------------
-- the dial
--------------------------------------------------

local SEGMENTS = 60
local RING_R = 112

local dialGui = new("CanvasGroup", {
	Name = "Dial", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromOffset(360, 470), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false,
}, gui)
local dialScale = scaled(dialGui)
local title = label(dialGui, { Size = UDim2.new(1, 0, 0, 34), Text = "HOLD THE DOOR", TextSize = 30 })
local subtitle = label(dialGui, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 20), Text = "CELLAR DOOR",
	TextSize = 14, TextColor3 = EMBER })

local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66), Size = UDim2.fromOffset(280, 280),
	BackgroundTransparency = 1 }, dialGui)
local disc = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(268, 268),
	BackgroundColor3 = INK, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, ring)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, disc)
local discStroke = new("UIStroke", { Color = BLOOD, Thickness = 1, Transparency = 0.55 }, disc)
local inner = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(150, 150),
	BackgroundColor3 = INK, BackgroundTransparency = 0.15, BorderSizePixel = 0 }, ring)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, inner)
new("UIStroke", { Color = RUST, Thickness = 1, Transparency = 0.3 }, inner)

-- the worn track and the bone-white window, one tick per segment
local track, zoneTicks = {}, {}
for i = 1, SEGMENTS do
	local a = (i - 0.5) * 360 / SEGMENTS
	local pos = UDim2.new(0.5, sin(rad(a)) * RING_R, 0.5, -cos(rad(a)) * RING_R)
	local worn = rng:NextNumber() < 0.15
	track[i] = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Rotation = a,
		Size = UDim2.fromOffset(4, worn and 9 or rng:NextInteger(13, 17)),
		BackgroundColor3 = worn and Color3.fromRGB(40, 28, 26) or RUST, BackgroundTransparency = worn and 0.4 or 0.1, BorderSizePixel = 0,
	}, ring)
	local z = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Rotation = a, Size = UDim2.fromOffset(6, 22),
		BackgroundColor3 = BONE, BorderSizePixel = 0, Visible = false,
	}, ring)
	new("UIStroke", { Color = BONE, Thickness = 1.5, Transparency = 0.7 }, z)
	zoneTicks[i] = { frame = z, angle = a }
end

-- the blade, with a smear behind it
local blades = {}
for i = 0, 3 do
	local arm = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = 5 - i }, ring)
	local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, -RING_R - 18),
		Size = UDim2.fromOffset(i == 0 and 4 or 3, 52), BackgroundColor3 = i == 0 and BLOOD or Color3.fromRGB(90, 8, 8),
		BackgroundTransparency = i == 0 and 0 or 0.45 + i * 0.15, BorderSizePixel = 0, ZIndex = 5 - i }, arm)
	if i == 0 then
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(9, 9), Rotation = 45,
			BackgroundColor3 = EMBER, BorderSizePixel = 0, ZIndex = 6 }, bar)
		new("UIStroke", { Color = EMBER, Thickness = 2, Transparency = 0.6 }, bar)
	end
	blades[i] = arm
end

local count = label(ring, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -10), Size = UDim2.fromOffset(120, 60),
	Text = "0", TextSize = 56, ZIndex = 7 })
local countOf = label(ring, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 30), Size = UDim2.fromOffset(120, 22),
	Text = "OF 8", TextSize = 15, TextColor3 = DIM, ZIndex = 7 })

-- three strikes
local strikes = {}
local strikeRow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 356), Size = UDim2.fromOffset(130, 26),
	BackgroundTransparency = 1 }, dialGui)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 12) }, strikeRow)
for i = 1, Config.MISSES_TO_BREACH do
	local box = new("Frame", { Size = UDim2.fromOffset(24, 24), BackgroundColor3 = INK, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, strikeRow)
	new("UIStroke", { Color = BLOOD, Thickness = 1, Transparency = 0.3 }, box)
	strikes[i] = label(box, { Size = UDim2.fromScale(1, 1), Text = "X", TextSize = 20, TextColor3 = EMBER, TextTransparency = 1, TextStrokeTransparency = 1 })
end

local hint = label(dialGui, { Position = UDim2.fromOffset(0, 388), Size = UDim2.new(1, 0, 0, 20), TextSize = 14, TextColor3 = DIM,
	Text = "PUSH WHEN THE RED HITS THE WHITE" })
local pushButton = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 416), Size = UDim2.fromOffset(250, 46),
	BackgroundColor3 = INK, BackgroundTransparency = 0.2, AutoButtonColor = false, Font = FONT, TextSize = 21, TextColor3 = BONE,
	Text = touch and "PUSH  -  TAP" or "PUSH  -  LEFT CLICK",
}, dialGui)
local pushStroke = new("UIStroke", { Color = BONE, Thickness = 1.5, Transparency = 0.35 }, pushButton)

--------------------------------------------------
-- THE FIGHT AT THE DOOR (your screen)
--------------------------------------------------

local dial = {
	active = false, model = nil, door = nil, need = 8, hits = 0, misses = 0,
	angle = 0, dir = 1, spin = 200, zone = 40, centre = 0, travelled = 0,
	pending = false, pendingAt = 0, nextRound = 0, closing = 0, punch = newSpring(0), jolt = newSpring(0),
	heat = 0,
}
local heartbeat = nil

local function setZone()
	for _, z in ipairs(zoneTicks) do
		z.frame.Visible = abs(angleDiff(z.angle, dial.centre)) <= dial.zone / 2
	end
end

local function newRound()
	-- the window turns up somewhere ahead of the blade
	dial.centre = (dial.angle + dial.dir * rng:NextNumber(110, 250)) % 360
	dial.travelled = 0
	dial.pending = false
	setZone()
end

local function refreshCounts()
	count.Text = tostring(dial.hits)
	countOf.Text = "OF " .. dial.need
	for i, s in ipairs(strikes) do
		s.TextTransparency = i <= dial.misses and 0 or 1
		s.Parent.BackgroundColor3 = i <= dial.misses and Color3.fromRGB(60, 6, 6) or INK
	end
end

local function openDial(model, need)
	local door = doors[model]
	dial.active, dial.model, dial.door = true, model, door
	dial.need, dial.hits, dial.misses = need, 0, 0
	dial.spin = door and door.cfg.spin or 210
	dial.zone = door and door.cfg.zone or 40
	dial.dir = 1
	dial.closing = 0
	dial.nextRound = os.clock() + 0.25
	dial.pending = true
	dial.pendingAt = os.clock()
	title.Text = "HOLD THE DOOR"
	title.TextColor3 = BONE
	subtitle.Text = door and door.cfg.label or ""
	for _, z in ipairs(zoneTicks) do
		z.frame.Visible = false
		z.frame.BackgroundColor3 = BONE
	end
	refreshCounts()
	dialGui.Visible = true
	dialGui.GroupTransparency = 1
	dial.punch.x, dial.punch.v = -0.15, 0
end

local function closeDial(delay)
	if dial.active then
		dial.closing = os.clock() + (delay or 0)
	end
end

local function push()
	if not dial.active or dial.closing > 0 or dial.pending or os.clock() < dial.nextRound then
		return
	end
	local inside = abs(angleDiff(dial.angle, dial.centre)) <= dial.zone / 2 + 4
	dial.pending = true
	dial.pendingAt = os.clock()
	dial.nextRound = math.huge
	remote:FireServer("Result", inside and "hit" or "miss")
	-- your side of it happens right away
	if inside then
		playLocal("Bolt", 1, rng:NextNumber(0.95, 1.1))
		dial.punch.v += 3
		for _, z in ipairs(zoneTicks) do
			z.frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		end
		local p = posers[player.Character]
		if p then
			p.drive.v += 5
		end
	else
		dial.jolt.v += 30
	end
end

pushButton.Activated:Connect(push)

-- the Crawler hit the door. Everyone gets this.
local function onSlam(model, kind, hits, misses, need, userId)
	local door = doors[model]
	local holder = Players:GetPlayerByUserId(userId)
	local character = holder and holder.Character
	local braceSide = character and character:GetAttribute("BraceSide") or 1
	if door then
		local where = door.centre.Position
		local sounds = door.cfg.sounds
		if kind == "hit" then
			-- it holds: the door jumps in the frame and shudders
			playAt(sounds.hit, where, 1, rng:NextNumber(0.9, 1.1))
			playAt(sounds.slam, where, 0.7, 1.1)
			kickDoor(door, door.kind == "Steel" and 1.6 or 3, 0.05, braceSide)
			door.dust:Emit(14)
		else
			-- it gets a hand-width in before you slam it back
			playAt(sounds.slam, where, 1.3, 0.9)
			playAt(sounds.hit, where, 1.1, 0.8)
			kickDoor(door, door.kind == "Steel" and 9 or 15, 0.32, braceSide)
			door.dust:Emit(40)
		end
		if door.kind ~= "Wood" then
			door.sparks:Emit(kind == "hit" and 8 or 22)
		end
	end
	bodySlam(character, kind)

	if userId == player.UserId then
		if kind == "hit" then
			shake(0.25, 2.5)
			flash.BackgroundColor3 = BONE
			flash.BackgroundTransparency = 0.9
		else
			shake(0.5, 7)
			local _, myRoot = myCharacter()
			if myRoot then
				playAt("Shoved", myRoot.Position, 1)
			end
			flash.BackgroundColor3 = BLOOD
			flash.BackgroundTransparency = 0.45
		end
		if dial.active and model == dial.model then
			dial.hits, dial.misses, dial.need = hits, misses, need
			refreshCounts()
			dial.jolt.v += kind == "hit" and 12 or 45
			dial.heat = math.min(dial.heat + (kind == "hit" and 0.15 or 0.4), 1)
			-- it gets harder: a narrower window, a faster blade that may turn back
			if kind == "hit" then
				dial.zone = math.max(dial.zone * 0.9, 16)
				dial.spin = math.min(dial.spin * 1.07, 420)
				if dial.hits >= 2 and rng:NextNumber() < 0.3 then
					dial.dir = -dial.dir
				end
			end
			for _, z in ipairs(zoneTicks) do
				z.frame.Visible = false
				z.frame.BackgroundColor3 = BONE
			end
			dial.pending = true
			dial.pendingAt = os.clock()
			dial.nextRound = os.clock() + (kind == "hit" and 0.45 or 0.75)
		end
	end
end

remote.OnClientEvent:Connect(function(action, model, ...)
	if action == "Slam" then
		onSlam(model, ...)
	elseif action == "Dial" then
		openDial(model, ...)
	elseif action == "Held" then
		local userId = ...
		local door = doors[model]
		if door then
			-- it throws itself at the door once more, screaming... then nothing
			task.delay(0.3, function()
				kickDoor(door, door.kind == "Steel" and 2.5 or 5, 0.1, nil)
				playAt(door.cfg.sounds.slam, door.centre.Position, 1.4, 0.8)
				door.dust:Emit(50)
			end)
		end
		if userId == player.UserId and dial.active then
			title.Text = "IT'S GIVING UP..."
			subtitle.Text = "DON'T MOVE"
			for _, z in ipairs(zoneTicks) do
				z.frame.Visible = false
			end
			closeDial(1.9)
		end
	elseif action == "Broken" then
		local push = select(1, ...)
		local door = doors[model]
		if door and typeof(push) == "Vector3" then
			burst(door, push)
		end
		if dial.active and model == dial.model then
			title.Text = "IT'S THROUGH"
			title.TextColor3 = EMBER
			flash.BackgroundColor3 = BLOOD
			flash.BackgroundTransparency = 0.2
			closeDial(0.5)
		end
	elseif action == "End" then
		closeDial(0)
	elseif action == "Denied" then
		say("NOTHING TO HOLD IT AGAINST... YET")
	end
end)

--------------------------------------------------
-- LOOKING AT DOORS, CLICKING THEM
--------------------------------------------------

local hovered, holdable = nil, false

local function threatNear(door)
	local m = workspace:FindFirstChild("TheCrawler")
	local root = m and m:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local hunting = m:GetAttribute("Chasing") == true or (m:GetAttribute("State") or ""):sub(1, 4) == "Door"
	return hunting and (root.Position - door.centre.Position).Magnitude <= Config.CHASE_NEAR
end

local function canHold(door, hrp)
	if door.broken or (door.model:GetAttribute("BarricadedBy") or 0) ~= 0 then
		return false
	end
	local flat = door.centre:PointToObjectSpace(hrp.Position)
	return abs(flat.Z) <= Config.HOLD_RANGE and abs(flat.X) <= door.width / 2 + 2.5 and threatNear(door)
end

local function busy(character)
	return character:GetAttribute("IsBarricading") or character:GetAttribute("Downed") or character:GetAttribute("BeingKilled")
end

local function findHovered()
	local character, hrp = myCharacter()
	local camera = workspace.CurrentCamera
	if not (character and hrp and camera) or busy(character) then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local origin = camera.CFrame.Position
	local hit = workspace:Raycast(origin, camera.CFrame.LookVector * (Config.USE_RANGE + 4), params)
	local model = hit and byPart[hit.Instance]
	local door = model and doors[model]
	if not door or door.broken then
		return nil
	end
	if (hit.Position - hrp.Position).Magnitude > Config.USE_RANGE then
		return nil
	end
	return door
end

local function toggle()
	local door = hovered
	local _, hrp = myCharacter()
	if not (door and hrp) or (door.model:GetAttribute("BarricadedBy") or 0) ~= 0 then
		return
	end
	remote:FireServer("Toggle", door.model)
	-- start swinging now; the server answers a moment later
	if door.target == 0 then
		door.target = side(door, hrp.Position) * door.cfg.openAngle
		door.predictedOpen = true
		playAt(door.cfg.sounds.open, door.centre.Position)
	else
		door.target = 0
	end
	door.style = "normal"
	door.predictUntil = os.clock() + 1.2
	door.moving = true
end

local function hold()
	local door = hovered
	if door and holdable then
		remote:FireServer("Hold", door.model)
	end
end

local function letGo()
	local character = player.Character
	if character and character:GetAttribute("IsBarricading") and not dial.active then
		remote:FireServer("Release")
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if dial.active then
			push()
		else
			toggle()
		end
	elseif input.KeyCode == Config.HOLD_KEY or input.KeyCode == Enum.KeyCode.ButtonX then
		local character = player.Character
		if character and character:GetAttribute("IsBarricading") then
			letGo()
		else
			hold()
		end
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 and dial.active then
		push()
	end
end)
useButton.Activated:Connect(toggle)
holdButton.Activated:Connect(hold)
letGoButton.Activated:Connect(letGo)

--------------------------------------------------
-- EVERY FRAME
--------------------------------------------------

local promptShown = 0
local hintShown = 0
local vignetteNow = 0

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero

	if camera then
		uiScale = clamp(camera.ViewportSize.Y / 900, 0.62, 1.25)
		for _, s in ipairs(scales) do
			s.Scale = uiScale
		end
	end

	for _, door in pairs(doors) do
		stepDoor(door, dt, now, camPos)
	end

	local character, hrp = myCharacter()
	local bracing = character and character:GetAttribute("IsBarricading") == true

	-- what you're looking at
	hovered = findHovered()
	holdable = hovered ~= nil and hrp ~= nil and canHold(hovered, hrp)
	if hovered then
		useText.Text = hovered.target == 0 and "OPEN" or "CLOSE"
		useButton.Text = useText.Text
		holdRow.Visible = holdable
	end
	local wantPrompt = hovered ~= nil and (hovered.model:GetAttribute("BarricadedBy") or 0) == 0
	promptShown += ((wantPrompt and 1 or 0) - promptShown) * math.min(dt * 12, 1)
	prompt.GroupTransparency = 1 - promptShown
	prompt.Visible = promptShown > 0.01
	if holdable then
		holdText.TextTransparency = 0.15 + 0.15 * sin(now * 6)
	end
	useButton.Visible = touch and wantPrompt
	holdButton.Visible = touch and holdable
	letGoButton.Visible = touch and bracing and not dial.active and (character:GetAttribute("ThrownAt") or 0) == 0

	-- leaning on it, waiting for the hit
	local wantHint = bracing and not dial.active and (character:GetAttribute("ThrownAt") or 0) == 0
	hintShown += ((wantHint and 1 or 0) - hintShown) * math.min(dt * 6, 1)
	holdHint.GroupTransparency = 1 - hintShown
	holdHint.Visible = hintShown > 0.01
	holdHintTop.TextTransparency = 0.1 + 0.1 * sin(now * 3)

	-- the screen closes in
	local wantVignette = (bracing and 0.55 or 0) + (dial.active and 0.25 + 0.2 * dial.heat or 0)
	vignetteNow += (wantVignette - vignetteNow) * math.min(dt * 4, 1)
	for _, e in ipairs(edges) do
		e.BackgroundTransparency = 1 - vignetteNow
	end
	flash.BackgroundTransparency = math.min(flash.BackgroundTransparency + dt * 1.6, 1)
	dial.heat = math.max(dial.heat - dt * 0.05, 0)

	-- a heartbeat only you can hear
	if bracing then
		if not heartbeat then
			heartbeat = makeSound("Heartbeat", SoundService)
			if heartbeat then
				heartbeat.Looped = true
				heartbeat.Volume = 0
				heartbeat:Play()
			end
		end
	end
	if heartbeat then
		local spec = Config.Sounds.Heartbeat
		local want = bracing and spec.Volume * (0.7 + 0.25 * dial.misses) or 0
		heartbeat.Volume += (want - heartbeat.Volume) * math.min(dt * 3, 1)
		heartbeat.PlaybackSpeed = spec.Speed * (1 + 0.1 * dial.misses + 0.15 * dial.heat)
		if not bracing and heartbeat.Volume < 0.02 then
			heartbeat:Destroy()
			heartbeat = nil
		end
	end

	notice.TextTransparency = clamp(1 - (noticeUntil - now) / 0.4, 0, 1)
	notice.TextStrokeTransparency = 0.5 + notice.TextTransparency * 0.5

	-- the dial
	if dial.active then
		if dial.closing > 0 and now >= dial.closing then
			dialGui.GroupTransparency = math.min(dialGui.GroupTransparency + dt * 3, 1)
			if dialGui.GroupTransparency >= 1 then
				dial.active = false
				dial.closing = 0
				dialGui.Visible = false
				dial.misses = 0
			end
		else
			dialGui.GroupTransparency = math.max(dialGui.GroupTransparency - dt * 5, 0)
		end

		-- the next window, once the slam has landed (or if the answer got lost)
		if dial.pending and dial.closing == 0 and (now >= dial.nextRound or now - dial.pendingAt > 1.6) then
			newRound()
		end
		if not dial.pending and dial.closing == 0 then
			local step = dial.spin * dt
			dial.angle = (dial.angle + dial.dir * step) % 360
			dial.travelled += step
			-- let it go round twice and it slams the door anyway
			if dial.travelled > 720 + dial.zone then
				dial.pending = true
				dial.pendingAt = now
				dial.nextRound = math.huge
				remote:FireServer("Result", "miss")
			end
		end
		for i = 0, 3 do
			blades[i].Rotation = dial.angle - dial.dir * i * dial.spin * 0.02
		end

		-- the whole thing jumps when the door's hit, and pulses with your heart
		spring(dial.jolt, 0, 22, 0.25, dt)
		spring(dial.punch, 0, 16, 0.4, dt)
		local beat = math.max(sin(now * 7.5 * (1 + 0.1 * dial.misses)), 0) ^ 8
		local jx = math.noise(now * 30, 1.7) * dial.jolt.x * 0.35
		local jy = math.noise(now * 30, 9.1) * dial.jolt.x * 0.35
		ring.Position = UDim2.new(0.5, jx, 0, 66 + jy)
		dialScale.Scale = uiScale * (1 + dial.punch.x * 0.06 + beat * 0.012)
		discStroke.Transparency = 0.55 - 0.4 * beat - 0.3 * dial.heat
		pushStroke.Transparency = 0.35 - 0.25 * beat
		hint.TextTransparency = dial.hits > 1 and math.min(hint.TextTransparency + dt * 0.5, 0.6) or 0
	end
end)
