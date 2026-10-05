-- BodyMotion
-- Place in: StarterPlayer > StarterPlayerScripts (a LocalScript named "BodyMotion")
--
-- Walking, strafing, walking backwards, sprinting, dropping into a crawl, the
-- crawl itself and getting back up, worked out fresh every frame from how
-- each body is really moving (speed, direction, speeding up, turning, how
-- hurt it is) instead of played from a canned loop. Nothing snaps: every
-- part of it rides on springs, so you lean into a sprint, stagger to a stop,
-- bank into turns, and your arms and head lag and settle.
--   * walk: heel-to-toe sway, hips and shoulders counter-twisting, arms
--     swinging a beat behind the legs, head held level
--   * strafe: side-steps (feet apart, together), leaning into it
--   * backwards: shorter, careful steps, arms held in
--   * sprint: driving forward lean, big arm pumps, the body pounding up and
--     down; lunges forward as you set off, rocks back as you pull up
--   * hurt (under 25% health): a limp, dipping onto the bad leg
--   * crawl: drop forward onto your hands and down onto your chest, then
--     drag yourself along on your forearms, hands planted on the real floor,
--     legs pushing out frog-like; push yourself back up when you stand
-- Everyone sees everyone else's (BodyMotionServer shares the stance).
--
-- It steps aside for anything else that moves your body: tools in your hand,
-- other animations (bandaging, the axe...), jumping and falling, climbing,
-- hiding, holding a door, being caught, being downed. Crouching stays your
-- own crouch animation.
-- Needs ThirdPersonHorrorCamera (the version that leaves walk/sprint/crawl to
-- this script) and BodyMotionServer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("BodyMotion", 30)

local UP = Vector3.new(0, 1, 0)
local rad, sin, cos, abs, clamp = math.rad, math.sin, math.cos, math.abs, math.clamp
local noise = math.noise
local TAU = 2 * math.pi

-- other things that move your body: while any of these is on, hands off
local OTHER_SYSTEMS = {
	"IsClimbing", "IsCrawlingThrough", "IsHanging", "IsTurningValve", "IsFuelAction", "IsLeverPush",
	"IsFuseRepair", "IsTightSqueeze", "IsAxeInspect", "IsAxeChop", "IsHiding", "IsCoopClimbing",
	"IsFusePickup", "IsFuseInstall", "IsBearTrapped", "IsGeneratorStarting", "BeingKilled",
	"IsBarricading", "Downed", "IsLeverPull",
}

-- your own movement animations (the camera script's): not "something else"
local OWN_ANIMS = {
	["rbxassetid://103384558824413"] = true, ["rbxassetid://82219891063668"] = true,
	["rbxassetid://120341809907353"] = true, ["rbxassetid://99723290210220"] = true,
	["rbxassetid://83040982292864"] = true, ["rbxassetid://94285423391710"] = true,
}

local GROUNDED = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

local function lerp(a, b, t)
	return a + (b - a) * t
end

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

local function newSpring(x)
	return { x = x or 0, v = 0 }
end

--------------------------------------------------
-- THE R6 BODY
--------------------------------------------------
-- Every joint is turned around its parent part's own axes (the same way
-- DownedClient and DoorClient pose you), so poses mix cleanly.

local function rigOf(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (hrp and torso and humanoid) then
		return nil
	end
	local j = {
		hrp = hrp, torso = torso, humanoid = humanoid,
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

-- the turn that takes direction a onto direction b
local function between(a, b)
	local axis = a:Cross(b)
	local s = axis.Magnitude
	if s < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, a:Dot(b)))
end

-- swing a rigid limb hanging from `pivot` so its end lands on a plane
-- (through `onPlane`, normal `n` facing the limb), as near `want` as its
-- length allows; too far away, it just reaches straight at the plane
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

-- the same, backed off so the limb's square end lies flat instead of its
-- corners digging in
local function plantFlat(motor, u, want, onPlane, n)
	local r = plant(motor.C0.Position, u, want, onPlane, n)
	local axes = r * (motor.C0.Rotation * motor.C1.Rotation:Inverse())
	local size = motor.Part1 and motor.Part1.Size or Vector3.new(1, 2, 1)
	local back = abs(axes.XVector:Dot(n)) * size.X / 2 + abs(axes.ZVector:Dot(n)) * size.Z / 2
	return plant(motor.C0.Position, u, want, onPlane + n * back, n)
end

local function rootCF(p)
	return CFrame.new(p.x, -p.drop, p.z) * CFrame.Angles(-rad(p.lean), rad(p.twist), rad(p.roll))
end

local function angles(p)
	return {
		root = rootCF(p),
		neck = CFrame.Angles(-rad(p.neck), rad(p.neckYaw), rad(p.neckRoll)),
		rs = CFrame.Angles(0, 0, rad(p.rOut)) * CFrame.Angles(rad(p.rSwing), 0, 0),
		ls = CFrame.Angles(0, 0, -rad(p.lOut)) * CFrame.Angles(rad(p.lSwing), 0, 0),
		rh = CFrame.Angles(0, 0, rad(p.rHipOut)) * CFrame.Angles(rad(p.rHip), 0, 0),
		lh = CFrame.Angles(0, 0, -rad(p.lHipOut)) * CFrame.Angles(rad(p.lHip), 0, 0),
	}
end

--------------------------------------------------
-- ON YOUR FEET: walk, strafe, backwards, sprint, limp
--------------------------------------------------
-- m = { phase, fwd, side (-1..1 direction you're moving, body space),
--       speed, move (0..1 how much you're moving), run (0..1 walk..sprint),
--       lean, bank (degrees, from the springs), limp (0..1), now, seed }

local function poseFeet(m)
	local p = TAU * m.phase
	local s1, c1 = sin(p), cos(p)
	local mv, run, limp = m.move, m.run, m.limp
	local back = m.fwd < -0.2 and smooth((-m.fwd - 0.2) / 0.5) or 0       -- walking backwards
	local sag = m.fwd                                                       -- forward/back share
	local lat = m.side                                                      -- sideways share
	local spread = lerp(0.7, 1, smooth(m.speed / lerp(7, 16, run)))         -- small steps when slow

	-- legs: swing fore and aft, step out and in sideways
	local legA = lerp(28, 50, run) * lerp(1, 0.72, back) * spread * mv
	local outA = lerp(13, 9, run) * spread * mv
	local rHip = legA * s1 * sag + run * 10 * math.max(s1, 0) * mv
	local lHip = -legA * s1 * sag + run * 10 * math.max(-s1, 0) * mv
	local hipOut = -outA * lat * c1
	local rHipOut = 3 * mv + hipOut
	local lHipOut = 3 * mv - hipOut
	-- hurt: the right leg barely swings, you dip onto it and hurry off it
	rHip *= lerp(1, 0.5, limp)

	-- the body: lowest as the feet spread, shifting over the standing foot
	local bob = -lerp(0.11, 0.24, run) * abs(s1) * mv
	local sway = -lerp(0.07, 0.03, run) * c1 * mv
	local dip = limp * 0.1 * math.max(-c1, 0) * mv
	local lean = lerp(3, 15, run) * mv * (1 - back) + 2 * back * mv + m.lean
	local twist = -lerp(6, 11, run) * s1 * sag * mv
	local roll = lerp(2.2, 1.2, run) * -c1 * mv + lat * 5 * mv + m.bank + limp * 6 * math.max(-c1, 0) * mv

	-- arms: opposite the legs, a beat behind, pumping when you sprint
	local lag = p - 0.35
	local armA = lerp(20, 48, run) * lerp(1, 0.55, back) * (1 - 0.6 * abs(lat)) * spread * mv
	local rSwing = -armA * sin(lag) * sag + run * 10 * mv
	local lSwing = armA * sin(lag) * sag + run * 10 * mv
	local rOut = lerp(4, 11, run) * mv + 8 * abs(lat) * mv + limp * 8
	local lOut = lerp(4, 11, run) * mv + 8 * abs(lat) * mv
	rSwing *= lerp(1, 0.35, limp)

	-- the head stays level and looks where you're going
	local breathe = noise(m.now * 0.6, m.seed) * 1.5
	return {
		x = sway, drop = -bob + dip + run * 0.12 * mv, z = 0,
		lean = lean + breathe * 0.3, twist = twist, roll = roll,
		neck = -lean * 0.75 + breathe, neckYaw = -twist * 0.8, neckRoll = -roll * 0.6,
		rSwing = rSwing, lSwing = lSwing, rOut = rOut, lOut = lOut,
		rHip = rHip, lHip = lHip, rHipOut = rHipOut, lHipOut = lHipOut,
	}
end

--------------------------------------------------
-- ON YOUR BELLY: the crawl
--------------------------------------------------
-- c = { height (torso centre above the floor), lean, phase, move, H (root
--       part above the floor), fwdSign, now, seed, settle }

local CRAWL_HEIGHT = 0.72

local function poseCrawl(j, c)
	local p = TAU * c.phase
	local mv = c.move
	local prone = smooth((c.lean - 40) / 40)            -- how far down onto your chest you are
	local roll = 7 * sin(p) * mv * prone
	local twist = 5 * sin(p) * mv * prone
	local surge = -0.12 * sin(2 * p) * mv * prone
	local breathe = sin(c.now * 2.6) * 0.03
	local body = {
		x = 0, z = surge,
		drop = c.H - c.height - breathe * prone,
		lean = c.lean + 1.5 * noise(c.now * 0.8, c.seed) * prone,
		twist = twist, roll = roll,
	}
	local root = rootCF(body)
	local torso = j.root.C0 * conj(j.root, root) * j.root.C1:Inverse()    -- in the root part's space
	local floorN = torso:VectorToObjectSpace(UP)
	local function onFloor(lift)
		return torso:PointToObjectSpace(Vector3.new(0, -c.H + lift, 0))
	end

	-- each hand reaches forward, plants, and drags you up to it; then the other.
	-- (right hand: pulling during the first 65% of a cycle, reaching the rest)
	local function arm(motor, u, side, offset)
		local a = (c.phase + offset) % 1
		local reach, lift
		if a < 0.65 then
			reach = lerp(12, 105, smooth(a / 0.65))             -- swept from out front round to your side
			lift = 0
		else
			local b = (a - 0.65) / 0.35
			reach = lerp(105, 12, smooth(b))
			lift = 0.45 * sin(math.pi * b)
		end
		reach = lerp(35, reach, mv)                            -- lying still: hands out in front
		local dir = Vector3.new(side * sin(rad(reach)) * 0.9 + side * 0.25, 0, -cos(rad(reach)))
		local shoulder = torso * motor.C0.Position
		local want = Vector3.new(shoulder.X, -c.H, shoulder.Z) + dir * 2
		lift = lift * mv * prone
		return plantFlat(motor, u, torso:PointToObjectSpace(want), onFloor(lift), floorN)
	end
	-- legs drag behind, the knee side kicking out as the same-side hand reaches
	local function leg(motor, u, side, offset)
		local a = (c.phase + offset) % 1
		local kick = a > 0.6 and sin(math.pi * (a - 0.6) / 0.4) or 0
		local out = rad(10 + 26 * kick * mv)
		local hip = torso * motor.C0.Position
		local want = Vector3.new(hip.X, -c.H, hip.Z) + Vector3.new(side * sin(out), 0, cos(out)) * 2.2
		return plantFlat(motor, u, torso:PointToObjectSpace(want), onFloor(0), floorN)
	end

	return {
		root = root,
		-- chin up, looking ahead along the floor
		neck = CFrame.Angles(-rad(-(c.lean * 0.8) + 4 * sin(2 * p) * mv), rad(-twist * 0.6), rad(-roll * 0.7)),
		rs = arm(j.rs, j.uRA, 1, 0),
		ls = arm(j.ls, j.uLA, -1, 0.5),
		rh = leg(j.rh, j.uRL, 1, 0),
		lh = leg(j.lh, j.uLL, -1, 0.5),
	}
end

-- dropping down: { time, torso height (H = standing), lean }
-- (the ease is how it moves INTO that key)
local function downKeys(H)
	return {
		height = { { 0, H }, { 0.2, H - 0.3 }, { 0.42, 1.65, "in2" }, { 0.66, 0.95 }, { 0.8, 0.6, "in2" },
			{ 0.92, 0.78, "out2" }, { 1.05, CRAWL_HEIGHT } },
		lean = { { 0, 0 }, { 0.2, 24 }, { 0.42, 55 }, { 0.66, 74 }, { 0.8, 82 }, { 1.05, 80 } },
	}
end
local DOWN_TIME = 1.05

-- pushing back up
local function upKeys(H)
	return {
		height = { { 0, CRAWL_HEIGHT }, { 0.12, 0.62 }, { 0.32, 1.25, "out2" }, { 0.55, 2.1 }, { 0.75, H - 0.2 },
			{ 0.85, H } },
		lean = { { 0, 80 }, { 0.12, 82 }, { 0.32, 66, "out2" }, { 0.55, 36 }, { 0.75, 8 }, { 0.85, 0 } },
	}
end
local UP_TIME = 0.85

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

--------------------------------------------------
-- EACH BODY
--------------------------------------------------

local JOINTS = { "root", "neck", "rs", "ls", "rh", "lh" }
local bodies = {}          -- character -> state

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local function stanceOf(character)
	if character == player.Character then
		return character:GetAttribute("MoveState") or "Walk"
	end
	return character:GetAttribute("Stance") or "Walk"
end

local function otherSystem(character)
	for _, name in ipairs(OTHER_SYSTEMS) do
		if character:GetAttribute(name) then
			return true
		end
	end
	return false
end

-- is something else animating the arms (an item, bandaging, the axe...)?
local function armsBusy(j, character)
	local tool = character:FindFirstChildOfClass("Tool") ~= nil
	local animator = j.humanoid:FindFirstChildOfClass("Animator")
	local other = false
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local anim = track.Animation
			if track.Priority.Value >= Enum.AnimationPriority.Action.Value and track.WeightCurrent > 0.05
				and not (anim and OWN_ANIMS[anim.AnimationId]) then
				other = true
				break
			end
		end
	end
	return tool, other
end

local function newBody(character, j)
	return {
		character = character, j = j, seed = math.random() * 100,
		mine = character == player.Character,
		w = newSpring(0), move = newSpring(0), run = newSpring(0), limp = newSpring(0),
		lean = newSpring(0), bank = newSpring(0), fwd = newSpring(1), side = newSpring(0),
		phase = 0, crawlPhase = 0, lastVel = Vector3.zero, lastYaw = nil, yawRate = 0,
		H = newSpring(3), stance = "Walk", crawlMode = nil, crawlT = 0,
		landing = newSpring(0), written = {}, armsW = newSpring(1), rArmW = newSpring(1),
	}
end

local function update(b, dt, now)
	local character, j = b.character, b.j
	local hrp, humanoid = j.hrp, j.humanoid

	-- floor under you (smoothed: it steps up and down stairs, it doesn't jump)
	castParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -7, 0), castParams)
	local H = hit and clamp(hrp.Position.Y - hit.Position.Y, 1.2, 4.5) or b.H.x
	spring(b.H, H, 14, 1, dt)
	H = b.H.x

	-- how you're moving, in your body's own terms
	local cf = hrp.CFrame
	local vel = hrp.AssemblyLinearVelocity
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local localVel = cf:VectorToObjectSpace(flat)
	local fwd, side = 1, 0
	if speed > 0.3 then
		fwd, side = -localVel.Z / speed, localVel.X / speed
	end
	spring(b.fwd, fwd, 9, 1, dt)
	spring(b.side, side, 9, 1, dt)
	local accel = ((flat - b.lastVel) / math.max(dt, 1 / 240)):Dot(cf.LookVector)
	b.lastVel = flat
	local _, yaw = cf:ToOrientation()
	if b.lastYaw then
		local d = (yaw - b.lastYaw + math.pi) % TAU - math.pi
		b.yawRate = lerp(b.yawRate, d / math.max(dt, 1 / 240), clamp(dt * 8, 0, 1))
	end
	b.lastYaw = yaw

	-- what you're doing
	local stance = stanceOf(character)
	local state = humanoid:GetState()
	local grounded = GROUNDED[state] == true
	local busy = otherSystem(character) or humanoid.Health <= 0 or humanoid.Sit
	local crawling = stance == "Crawl" and not busy

	-- into and out of the crawl
	if crawling and b.crawlMode ~= "down" and b.crawlMode ~= "prone" then
		-- (changed your mind halfway up: go back down from where you are)
		local t = b.crawlMode == "up" and DOWN_TIME * (1 - clamp(b.crawlT / UP_TIME, 0, 1)) or 0
		b.crawlMode, b.crawlT = "down", t
		b.downKeys = downKeys(H)
	elseif not crawling and (b.crawlMode == "down" or b.crawlMode == "prone") then
		if busy then
			b.crawlMode = nil                                        -- something else takes over
		else
			local t = b.crawlMode == "down" and UP_TIME * (1 - clamp(b.crawlT / DOWN_TIME, 0, 1)) or 0
			b.crawlMode, b.crawlT = "up", t
			b.upKeys = upKeys(H)
		end
	end
	b.crawlT += dt
	if b.crawlMode == "down" and b.crawlT >= DOWN_TIME then
		b.crawlMode = "prone"
		if b.mine then
			-- chest hits the floor
			character:SetAttribute("ShakeUntil", os.clock() + 0.2)
			character:SetAttribute("ShakeAmount", 1.6)
		end
	elseif b.crawlMode == "up" and b.crawlT >= UP_TIME then
		b.crawlMode = nil
	end

	-- ours, or someone else's?
	local onFeet = (stance == "Walk" or stance == "Sprint") and grounded and not busy
	local want = 0
	if b.crawlMode then
		want = 1
	elseif onFeet then
		want = smooth(speed / 1.2)
	end
	if busy and not b.crawlMode then
		b.w.x, b.w.v = 0, 0                                         -- let go straight away
	else
		spring(b.w, want, grounded and 9 or 18, 1, dt)
	end

	-- the walk's springs
	local running = stance == "Sprint" and 1 or 0
	spring(b.run, running, 4.5, 0.9, dt)
	local move = smooth(speed / 3.5)
	spring(b.move, move, 8, 0.85, dt)
	local hurt = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth < 0.25
		and (character:GetAttribute("AdrenalineUntil") or 0) < workspace:GetServerTimeNow()
	spring(b.limp, hurt and 1 or 0, 3, 1, dt)
	-- lean into speeding up, rock back stopping, bank into turns
	spring(b.lean, clamp(accel * 0.55, -9, 13) * (1 - 0.5 * b.run.x), 10, 0.45, dt)
	spring(b.bank, clamp(-b.yawRate * speed * 0.35, -9, 9), 8, 0.6, dt)

	local stride = lerp(4.6, 8.8, b.run.x) * (b.fwd.x < -0.2 and 0.75 or 1)
	local limpRush = 1 + b.limp.x * 0.35 * sin(TAU * b.phase)                       -- hurry off the bad leg
	b.phase = (b.phase + speed / stride * dt * limpRush) % 1
	local crawlDir = (b.fwd.x < -0.3) and -1 or 1
	b.crawlPhase = (b.crawlPhase + crawlDir * speed / 2.8 * dt) % 1

	if b.w.x < 0.002 then
		if next(b.written) then
			table.clear(b.written)
		end
		return
	end

	-- the pose
	local pose
	local feet = poseFeet({
		phase = b.phase, fwd = b.fwd.x, side = b.side.x, speed = speed, move = b.move.x,
		run = b.run.x, lean = b.lean.x, bank = b.bank.x, limp = b.limp.x, now = now, seed = b.seed,
	})
	if b.mine then
		-- (in first person your eyes ride on your head: the camera adds its own bob)
		feet.drop *= 0.5
		feet.x *= 0.5
	end
	pose = angles(feet)
	if b.crawlMode then
		local height, lean
		if b.crawlMode == "down" then
			height, lean = sample(b.downKeys.height, b.crawlT), sample(b.downKeys.lean, b.crawlT)
		elseif b.crawlMode == "up" then
			height, lean = sample(b.upKeys.height, b.crawlT), sample(b.upKeys.lean, b.crawlT)
		else
			height, lean = CRAWL_HEIGHT, 80
		end
		local crawl = poseCrawl(j, {
			height = height, lean = lean, phase = b.crawlPhase, move = b.crawlMode == "prone" and smooth(speed / 2) or 0,
			H = H, now = now, seed = b.seed,
		})
		-- getting up: hand back to your feet over the last stretch
		local k = 1
		if b.crawlMode == "up" then
			k = 1 - smooth((b.crawlT - UP_TIME * 0.6) / (UP_TIME * 0.4))
		end
		for _, key in ipairs(JOINTS) do
			pose[key] = pose[key]:Lerp(crawl[key], k)
		end
	end

	-- arms something else is using stay theirs
	local tool, otherAnim = armsBusy(j, character)
	spring(b.armsW, otherAnim and 0 or 1, 12, 1, dt)
	spring(b.rArmW, (tool or otherAnim) and 0 or 1, 12, 1, dt)

	local weight = b.w.x
	for _, key in ipairs(JOINTS) do
		local motor = j[key]
		local wk = weight
		if key == "rs" then
			wk *= b.rArmW.x
		elseif key == "ls" then
			wk *= b.armsW.x
		end
		-- what the Animator is doing underneath (if it didn't touch this joint
		-- this frame, it's still showing what we wrote: start from rest)
		local base = motor.Transform
		if b.written[motor] and base == b.written[motor] then
			base = CFrame.identity
		end
		local out = base:Lerp(conj(motor, pose[key]), wk)
		motor.Transform = out
		b.written[motor] = out
	end
end

-- after the Animator, so this wins over the animations it replaces
RunService.PreSimulation:Connect(function(dt)
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		if character and character.Parent then
			local b = bodies[character]
			if not b or not b.j.hrp.Parent then
				local j = rigOf(character)
				if j then
					b = newBody(character, j)
					bodies[character] = b
				end
			end
			if b then
				update(b, math.min(dt, 0.1), now)
			end
		end
	end
	for character in pairs(bodies) do
		if not character.Parent then
			bodies[character] = nil
		end
	end
end)

--------------------------------------------------
-- TELL EVERYONE HOW YOU'RE MOVING
--------------------------------------------------

local sent = nil
local function share(character)
	local state = character:GetAttribute("MoveState") or "Walk"
	if state ~= sent and remote then
		sent = state
		remote:FireServer(state)
	end
end
local function watch(character)
	sent = nil
	character:GetAttributeChangedSignal("MoveState"):Connect(function()
		share(character)
	end)
	share(character)
end
player.CharacterAdded:Connect(watch)
if player.Character then
	watch(player.Character)
end
