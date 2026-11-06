-- StitcherPose
-- Place in: ReplicatedStorage (a ModuleScript named exactly "StitcherPose")
--
-- The Stitcher's whole body, worked out fresh every frame (StitcherAnimator
-- applies it to the imported skeleton's ~180 Bones). Every rotation here is
-- around the MODEL's own axes - X = its right, Y = up, Z = behind it - taken
-- at the joint and carried along by everything above it, so "Spine3 tips
-- forward 8 degrees" means exactly that whatever the importer did to the bones.
--
--   * standing: hunched, the long neck craned forward, the head lolling over
--     at a sick angle; slow ragged breathing that heaves the bare ribs in its
--     chest; the left hand's long fingers drumming; the scissors opening
--     slowly... and snapping shut
--   * twitches: the head cracks over to the other side, a shoulder jerks, the
--     ribs spasm open one after another, the forearm bends the wrong way, the
--     whole body shudders, the jaw clacks, a double snip
--   * it sees you: the head snaps round (further than a neck should turn),
--     the eyes lock on, the grin stretches, the jaw chatters, the scissors snip
--     faster and faster and come up; close, the left hand reaches for you
--   * walking: long dragging strides with a limp; running: low, lurching,
--     arms flung loose; the head stays locked on you
--   * attack (when the "Attack" counter changes): rears up, ribs flaring wide,
--     jaw gaping, scissors raised and open - then lunges and SNIPS
--   * hair, cap ties, gown ties, the torn flap, bandage tails and the skirt
--     are simulated (they swing, lag, and the skirt is kicked by its legs)
--
-- Written in plain Lua 5.1 syntax (Luau runs it as is).

local StitcherPose = {}
StitcherPose.__index = StitcherPose

local rad, deg, sin, cos, abs = math.rad, math.deg, math.sin, math.cos, math.abs
local max, min, sqrt, floor = math.max, math.min, math.sqrt, math.floor
local clamp, noise = math.clamp, math.noise

local IDENTITY = CFrame.new()
local ZERO = Vector3.new(0, 0, 0)
local GRAVITY = Vector3.new(0, -35, 0)     -- (studs/s^2 for hair and cloth: about real gravity at stud scale)

local FINGERS = { "Index", "Middle", "Ring", "Pinky" }
local SIDES = { "L", "R" }

local function smooth(a)
	a = clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function spring(x, w, z)
	return { x = x or 0, v = 0, goal = x or 0, w = w, z = z }
end

local function step(s, dt)
	local n = max(1, math.ceil(dt / (1 / 120)))
	local h = dt / n
	for _ = 1, n do
		s.v = s.v + (s.w * s.w * (s.goal - s.x) - 2 * s.z * s.w * s.v) * h
		s.x = s.x + s.v * h
	end
	return s.x
end

local function ang(x, y, z)
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end

-- the turn that takes direction a onto direction b
local function between(a, b)
	local axis = a:Cross(b)
	local s = axis.Magnitude
	if s < 1e-6 then
		if a:Dot(b) >= 0 then
			return IDENTITY
		end
		local p = abs(a.X) < 0.9 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
		return CFrame.fromAxisAngle(a:Cross(p).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, a:Dot(b)))
end

local function rotOnly(cf)
	return cf.Rotation
end

-- how each kind of dangling chain behaves
local function chainKind(prefix)
	if prefix:sub(1, 4) == "Hair" then
		return { stiff = 0.035, damp = 0.9, grav = 1, collide = "head" }
	elseif prefix:sub(1, 5) == "Skirt" then
		return { stiff = 0.22, damp = 0.84, grav = 0.7, collide = "legs" }
	elseif prefix:sub(1, 8) == "GownFlap" then
		return { stiff = 0.07, damp = 0.88, grav = 1, collide = "torso" }
	elseif prefix:sub(1, 3) == "Tie" then
		return { stiff = 0.02, damp = 0.9, grav = 1, collide = "torso" }
	elseif prefix:sub(1, 6) == "CapTie" then
		return { stiff = 0.03, damp = 0.9, grav = 1, collide = "head" }
	end
	return { stiff = 0.03, damp = 0.9, grav = 1 }         -- bandage tails and anything else
end

-- rig = {
--   pos = { boneName = Vector3 (model space, at rest) },
--   parent = { boneName = parent bone's name (nil for the top one) },
--   order = { bone names, every parent before its children },
-- }
function StitcherPose.new(rig, seed)
	local self = setmetatable({}, StitcherPose)
	self.rig = rig
	self.seed = seed or math.random() * 100
	self.rng = Random.new(floor(self.seed * 1000))
	self.out = {}
	self.D, self.P = {}, {}
	self.has = {}
	for _, name in ipairs(rig.order) do
		self.has[name] = true
	end

	-- twitches: wobbly springs kicked now and then
	self.jerk = {}
	for _, k in ipairs({ "clavL", "clavR", "head", "spine", "kneeL", "kneeR", "lift", "fingers", "jaw",
		"wrongArm", "armR" }) do
		self.jerk[k] = spring(0, 13, 0.22)
	end
	self.nextJerk = 2
	self.shudder = 0
	self.events = {}

	-- the head: snaps between where it has decided to look; lolls over to one side
	self.headYaw = spring(0, 26, 0.42)
	self.headPitch = spring(0, 26, 0.42)
	self.headRoll = spring(rad(24), 7, 0.45)
	self.tiltSide = 1
	self.nextLook = 0
	self.eyeYaw = spring(0, 40, 0.6)
	self.eyePitch = spring(0, 40, 0.6)
	self.nextDart = 0

	-- moods
	self.excite = spring(0, 3, 1)
	self.reach = spring(0, 2.2, 0.9)
	self.ready = spring(0, 4, 0.8)
	self.grin = spring(0.3, 5, 0.7)
	self.jaw = spring(0.1, 8, 0.55)

	-- the ribs (6 a side), each its own spring, so spasms ripple down the chest
	self.ribs = {}
	for i = 1, 6 do
		self.ribs[i] = spring(0, 16, 0.3)
	end
	self.ribKicks = {}

	-- the scissors
	self.snip = spring(0, 8, 0.7)
	self.snipState = "closed"
	self.nextSnip = 3
	self.snipQueue = 0

	-- walking
	self.phase = 0
	self.move = spring(0, 4, 1)
	self.run = spring(0, 3, 1)
	self.swingL = spring(0, 5, 0.35)
	self.swingR = spring(0, 5, 0.35)

	-- attacks
	self.lastAttack = nil
	self.attackT = 99

	-- the dangling chains: bones named <prefix>_1, <prefix>_2...
	local groups = {}
	for _, name in ipairs(rig.order) do
		local prefix, idx = string.match(name, "^(.-_)(%d+)$")
		if prefix then
			groups[prefix] = groups[prefix] or {}
			groups[prefix][tonumber(idx)] = name
		end
	end
	self.chains = {}
	local prefixes = {}
	for prefix in pairs(groups) do
		table.insert(prefixes, prefix)
	end
	table.sort(prefixes)
	for _, prefix in ipairs(prefixes) do
		local list = groups[prefix]
		local bones = {}
		local i = 1
		while list[i] do
			bones[i] = list[i]
			i = i + 1
		end
		local parent = bones[1] and rig.parent[bones[1]]
		if #bones >= 2 and parent and rig.pos[parent] then
			local rest = {}
			for k = 1, #bones do
				rest[k - 1] = rig.pos[bones[k]]
			end
			local n = #bones
			rest[n] = rest[n - 1] + (rest[n - 1] - rest[n - 2])          -- (the last bone's tip)
			local seg = {}
			for k = 1, n do
				seg[k] = (rest[k] - rest[k - 1]).Magnitude
			end
			local ch = chainKind(prefix)
			ch.name, ch.bones, ch.parent, ch.rest, ch.seg, ch.n = prefix, bones, parent, rest, seg, n
			table.insert(self.chains, ch)
		end
	end

	-- a few measurements
	local pos = rig.pos
	local eyeL, eyeR = pos["Eye.L"], pos["Eye.R"]
	self.headCentre = eyeL and eyeR and ((eyeL + eyeR) / 2 + Vector3.new(0, 0.03, 0.24)) or ZERO
	self.headRadius = eyeL and eyeR and (eyeL - eyeR).Magnitude * 1.27 or 0.33
	local blade, hinge = pos.ScissorBlade, pos.ScissorHinge
	self.scissorAxis = (blade and hinge) and (hinge - blade).Unit or Vector3.new(1, 0, 0)
	return self
end

-- give a twitch, an event the animator can play a sound for
function StitcherPose:event(name)
	table.insert(self.events, name)
end

-- accumulated model-space turn after these bones (in order, root first)
function StitcherPose:accum(names)
	local d = IDENTITY
	local out = self.out
	for _, n in ipairs(names) do
		local r = out[n]
		if r then
			d = d * rotOnly(r)
		end
	end
	return d
end

local ARM_CHAIN = {
	L = { "Root", "Spine1", "Spine2", "Spine3", "Spine4", "Spine5", "Clavicle.L" },
	R = { "Root", "Spine1", "Spine2", "Spine3", "Spine4", "Spine5", "Clavicle.R" },
}

-- input = {
--   dt, t (seconds), speed (studs/s forward), target (Vector3, model space, or nil),
--   near (0..1: how close the nearest player is), aggro (0..1: forced hunting mood),
--   attack (any value: each time it changes, it attacks), frame (CFrame: the model's
--   frame in the world, for the hanging hair and cloth)
-- }
-- returns { boneName = CFrame } (model-space turns; "Root" and the face also move),
-- and fills self.events with "snip" / "crack" / "shriek" this frame
function StitcherPose:update(input)
	local dt = clamp(input.dt, 1 / 240, 0.1)
	local t = input.t + self.seed
	local rng = self.rng
	local J = self.jerk
	local out = self.out
	for k in pairs(out) do
		out[k] = nil
	end
	for k in pairs(self.events) do
		self.events[k] = nil
	end
	local pos = self.rig.pos
	local target = input.target
	local near = clamp(input.near or 0, 0, 1)

	------------------------------------------------ mood
	self.excite.goal = max(input.aggro or 0, near, target and 0.3 or 0)
	local excite = clamp(step(self.excite, dt), 0, 1)

	------------------------------------------------ attack
	if input.attack ~= nil and input.attack ~= self.lastAttack then
		if self.lastAttack ~= nil then
			self.attackT = 0
			self.snapped = false
			self:event("shriek")
		end
		self.lastAttack = input.attack
	end
	if self.attackT < 2 then
		self.attackT = self.attackT + dt
	end
	local at = self.attackT
	local windup = smooth(at / 0.34) * (1 - smooth((at - 0.34) / 0.1))
	local strike = smooth((at - 0.34) / 0.1) * (1 - smooth((at - 0.62) / 0.6))
	local attacking = at < 1.25

	------------------------------------------------ twitches
	if t >= self.nextJerk and not attacking then
		self.nextJerk = t + rng:NextNumber(1.4, 4.5) * (1 - 0.45 * excite)
		local r = rng:NextNumber()
		local s = rng:NextNumber() < 0.5 and 1 or -1
		if r < 0.13 then
			J[s > 0 and "clavR" or "clavL"].v = J[s > 0 and "clavR" or "clavL"].v + 170      -- a shoulder yanked up
			J.lift.v = J.lift.v + 1.5
		elseif r < 0.27 then
			self.tiltSide = -self.tiltSide                       -- the head cracks over to the other side
			J.head.v = J.head.v + 420 * self.tiltSide
			self:event("crack")
		elseif r < 0.38 then
			for i = 1, 6 do                                      -- the ribs spasm open, top to bottom
				table.insert(self.ribKicks, { at = t + (i - 1) * 0.045, rib = i, v = 600 })
			end
		elseif r < 0.48 then
			J.spine.v = J.spine.v + 260                          -- the whole body jolts
			J.lift.v = J.lift.v + 2.5
		elseif r < 0.56 then
			J[s > 0 and "kneeR" or "kneeL"].v = J[s > 0 and "kneeR" or "kneeL"].v + 380      -- a knee buckles
		elseif r < 0.65 then
			J.fingers.v = J.fingers.v + 520                      -- the fingers spasm open
		elseif r < 0.73 then
			J.jaw.v = J.jaw.v + 420                              -- the jaw drops and clacks shut
		elseif r < 0.81 then
			J.wrongArm.v = J.wrongArm.v + 520                    -- the left forearm bends the wrong way
			self:event("crack")
		elseif r < 0.9 then
			self.shudder = 0.55                                  -- a long shudder
		else
			self.snipQueue = 2                                   -- snip snip
			self.nextSnip = t
		end
	end
	for _, s in pairs(J) do
		step(s, dt)
	end
	local shud = 0
	if self.shudder > 0 then
		self.shudder = self.shudder - dt
		shud = smooth(self.shudder / 0.55)
	end
	local function jitter(i)
		return shud * 4 * noise(t * 31, i * 1.7, self.seed)
	end

	------------------------------------------------ walking / running
	local speed = max(input.speed or 0, 0)
	self.move.goal = clamp(speed / 3, 0, 1)
	self.run.goal = smooth((speed - 5) / 5)
	local mv = step(self.move, dt)
	local run = step(self.run, dt)
	local stride = 5 + 5 * run
	-- the limp: the stride hitches, the right leg drags
	local warp = 1 + 0.4 * sin(self.phase * 2 * math.pi) * (1 - run)
	self.phase = (self.phase + speed / stride * dt * warp) % 1
	local p = self.phase * 2 * math.pi
	local s1 = sin(p)
	local thighAmp = 24 + 26 * run
	local kneeAmp = 46 + 50 * run
	local thighR = thighAmp * s1 * mv
	local thighL = -thighAmp * s1 * mv
	local kneeR = -kneeAmp * max(0, sin(p + 1.1)) * mv * (1 - 0.45 * (1 - run))    -- (dragged)
	local kneeL = -kneeAmp * max(0, sin(p + 1.1 + math.pi)) * mv
	local bob = (-0.12 - 0.14 * run) * abs(s1) * mv - 0.1 * (1 - run) * max(0, -s1) * mv
	local sway = (5 - 2 * run) * s1 * mv
	self.swingR.goal = (-18 - 30 * run) * s1 * mv
	self.swingL.goal = (18 + 30 * run) * s1 * mv
	local swingR, swingL = step(self.swingR, dt), step(self.swingL, dt)

	------------------------------------------------ breathing: slow and ragged; panting when it's excited
	local bt = t * (1.2 + 1.8 * excite)
	local breath = sin(bt) + 0.35 * sin(bt * 2.7 + 1)
	local breath01 = 0.5 + 0.5 * sin(bt)

	------------------------------------------------ the head: snaps to look; lolls over
	local yawGoal, pitchGoal = self.headYaw.goal, self.headPitch.goal
	if target then
		local neck = pos.Neck3 or Vector3.new(0, 7, 0)
		local d = target - neck
		local flat = sqrt(d.X * d.X + d.Z * d.Z)
		-- (close up, it turns its head further round than a neck should go)
		local limit = rad(95 + 45 * smooth((near - 0.5) / 0.5))
		local wantYaw = clamp(math.atan2(-d.X, -d.Z), -limit, limit)
		local wantPitch = clamp(math.atan2(d.Y, max(flat, 0.1)), rad(-55), rad(40))
		if t >= self.nextLook or abs(wantYaw - yawGoal) > rad(25) then
			self.nextLook = t + rng:NextNumber(0.2, 0.9) * (1 - 0.5 * excite)
			yawGoal, pitchGoal = wantYaw, wantPitch
		end
	elseif t >= self.nextLook then
		self.nextLook = t + rng:NextNumber(0.9, 3)
		yawGoal = rad(rng:NextNumber(-70, 70))
		pitchGoal = rad(rng:NextNumber(-30, 8))
		if rng:NextNumber() < 0.25 then
			self.tiltSide = -self.tiltSide
		end
	end
	self.headYaw.goal, self.headPitch.goal = yawGoal, pitchGoal
	local hy, hp = step(self.headYaw, dt), step(self.headPitch, dt)
	-- the tilt: further over the more it wants you; right up close, nearly sideways
	local tilt = 22 + 12 * excite + 28 * smooth((near - 0.55) / 0.45) + 6 * sin(t * 0.37)
	self.headRoll.goal = rad(tilt) * self.tiltSide
	local hr = step(self.headRoll, dt) + rad(J.head.x * 0.3)

	------------------------------------------------ the body
	local hunch = 1 + 0.35 * excite + 0.4 * run - 0.9 * windup + 1.1 * strike
	local lift = -0.03 + bob + 0.06 * J.lift.x - 0.015 * breath + 0.12 * windup - 0.25 * strike
	out.Root = CFrame.new(0, lift, -0.35 * strike) * ang(-6 * run * mv - 10 * strike, sway, -sway * 0.4 + jitter(1))
	out.Spine1 = ang(-2 * hunch + J.spine.x * 0.2 + jitter(2), -sway * 0.6, 0)
	out.Spine2 = ang(-3 * hunch + breath * 0.8 + jitter(3), -sway * 0.3, 0)
	out.Spine3 = ang(-5 * hunch + breath * 1.2 - J.spine.x * 0.1 + jitter(4), 0, 0)
	out.Spine4 = ang(-5 * hunch + breath * 0.9 + jitter(5), 0, 0)
	out.Spine5 = ang(-4 * hunch + 8 * windup + jitter(6), 0, 0)
	-- the neck cranes forward out of the hunch, then the head comes back up to look (it still
	-- hangs a little); the turn is spread down the neck
	local yd, pd, rd = deg(hy), deg(hp), deg(hr)
	local lean = 19 * hunch + 20 - 8 * windup
	local up = lean - 8 + 12 * windup
	out.Neck1 = ang(-14 + 8 * windup + jitter(7), yd * 0.15, rd * 0.1)
	out.Neck2 = ang(-6 + pd * 0.25, yd * 0.25, rd * 0.15)
	out.Neck3 = ang(up * 0.32 + pd * 0.25, yd * 0.25, rd * 0.25)
	out.Neck4 = ang(up * 0.38 + pd * 0.25, yd * 0.2, rd * 0.2)
	out.Head = ang(up * 0.3 + pd * 0.25 + jitter(8), yd * 0.15 + J.head.x * 0.2, rd * 0.3)

	------------------------------------------------ the face
	self.grin.goal = 0.3 + 0.5 * excite + 0.4 * max(windup, strike)
	local g = step(self.grin, dt)
	self.jaw.goal = 0.12 + 0.25 * excite + 1.0 * max(windup, strike * 0.6)
	local jaw = step(self.jaw, dt)
	local chatter = 3 * noise(t * 14, self.seed + 3) * smooth((excite - 0.4) / 0.6)
	out.Jaw = ang(-(4 + 30 * jaw + J.jaw.x * 0.5 + chatter), 0, 0)
	-- the grin: the corners dragged back towards the ears and up, the lips peeled off the teeth
	out["MouthCorner.L"] = CFrame.new(-0.02 * g, 0.016 * g, 0.012 * g)
	out["MouthCorner.R"] = CFrame.new(0.02 * g, 0.016 * g, 0.012 * g)
	out.UpperLip = ang(12 * g, 0, 0)
	out.LowerLip = ang(-10 * g, 0, 0)
	out["Cheek.L"] = CFrame.new(-0.006 * g, 0.014 * g, 0.006 * g)
	out["Cheek.R"] = CFrame.new(0.006 * g, 0.014 * g, 0.006 * g)
	-- staring: brows up, eyes wide; one brow twitches
	local stare = target and smooth(excite) or 0
	out["Brow.L"] = CFrame.new(0, 0.014 * stare + 0.006 * max(0, noise(t * 3, 9)), 0)
	out["Brow.R"] = CFrame.new(0, 0.01 * stare, 0)
	out.Mask = ang(2 * breath + 4 * jaw, 0, 0)

	------------------------------------------------ the ribs: heaving, spasming, flaring wide
	for i = #self.ribKicks, 1, -1 do
		local k = self.ribKicks[i]
		if t >= k.at then
			self.ribs[k.rib].v = self.ribs[k.rib].v + k.v
			table.remove(self.ribKicks, i)
		end
	end
	for i = 1, 6 do
		local r = self.ribs[i]
		r.goal = 0
		local spasm = step(r, dt)
		local heave = (2 + 4 * excite) * (0.5 + 0.5 * sin(bt - i * 0.35))
		local flare = heave + spasm * 0.08 + (38 - i * 2.5) * windup + 14 * strike
		out["Rib" .. i .. ".L"] = ang(0, flare, 0)
		out["Rib" .. i .. ".R"] = ang(0, -flare, 0)
	end

	------------------------------------------------ the scissors: slow, slow open... SNIP
	self.ready.goal = attacking and 1 or smooth((excite - 0.35) / 0.5)
	local ready = step(self.ready, dt)
	local snipping = self.snipState
	if attacking then
		self.snip.w = 30
		self.snip.goal = windup > 0.2 and 50 or 0
		if not self.snapped and at > 0.42 then
			self.snapped = true
			self:event("snip")
		end
		self.snipState = "closed"
		self.nextSnip = t + 0.6
	elseif snipping == "closed" and t >= self.nextSnip then
		self.snipState = "opening"
		self.snip.goal = rng:NextNumber(28, 46) * (1 - 0.3 * excite)
		self.snip.w = 5 + 18 * excite
	elseif snipping == "opening" and self.snip.x >= self.snip.goal * 0.88 then
		self.snipState = "shutting"
		self.snip.goal = -3
		self.snip.w = 45
	elseif snipping == "shutting" and self.snip.x <= 2 then
		self.snipState = "closed"
		self:event("snip")
		if self.snipQueue > 0 then
			self.snipQueue = self.snipQueue - 1
			self.nextSnip = t + 0.12
		elseif excite > 0.6 then
			self.nextSnip = t + rng:NextNumber(0.12, 0.45) * (1.6 - near)
		else
			self.nextSnip = t + rng:NextNumber(2.5, 6.5) * (1 - 0.6 * excite)
		end
	end
	local open = max(step(self.snip, dt), 0)
	out.ScissorBlade = CFrame.fromAxisAngle(self.scissorAxis, -rad(open))

	------------------------------------------------ arms
	self.reach.goal = (target and not attacking) and smooth((near - 0.15) / 0.6) or 0
	local reach = step(self.reach, dt)
	local wrong = J.wrongArm.x
	for _, side in ipairs(SIDES) do
		local m = side == "R" and 1 or -1                  -- mirror: +1 for its right (+X)
		local swing = side == "R" and swingR or swingL
		local clav = J[side == "R" and "clavR" or "clavL"].x
		out["Clavicle." .. side] = ang(0, 4 * m, m * (8 + clav * 0.3 + breath * 0.8 + 6 * windup))
		-- hanging too long, close in, swinging like dead weight
		local fwd = 4 + swing + jitter(10 + m)
		local inward = 17 - 6 * run
		local upper = ang(fwd, 0, -m * inward)
		local fore = ang(10 + jitter(12 + m), 0, 0)
		local hand = ang(-6, 0, 0)
		if side == "R" then
			-- the scissors come up as it gets worked up; in an attack, raised high, then slashed down
			local armUp = 10 + 40 * ready + J.armR.x * 0.2
			armUp = armUp + 120 * windup - 70 * strike * (1 - windup)
			upper = ang(fwd * (1 - ready) + armUp, 0, -m * (inward - 8 * ready - 10 * windup))
			fore = ang(10 + 45 * ready + 30 * windup - 40 * strike, 0, 0)
			hand = ang(-6 - 25 * ready + 30 * strike, 0, 0)
		else
			-- the left hand reaches for you: the whole arm swung round to point at you
			if reach > 0.001 and target then
				local shoulder = pos["UpperArm1.L"]
				local wrist = pos["Hand.L"]
				if shoulder and wrist then
					local rest = (wrist - shoulder).Unit
					local carried = self:accum(ARM_CHAIN.L)
					local want = target - shoulder
					want = want.Magnitude > 0.1 and want.Unit or rest
					local aim = between(rest, carried:Inverse() * want)
					upper = upper:Lerp(aim, reach * 0.9)
				end
			end
			-- an attack flings it out wide
			upper = upper * ang(40 * windup, 0, 30 * windup)
			fore = fore * ang(-wrong * 0.25 * (1 - reach), 0, 0)
		end
		out["UpperArm1." .. side] = upper
		out["UpperArm2." .. side] = ang(2 * noise(t * 0.7, m), 0, 0)
		out["Forearm1." .. side] = fore
		out["Forearm2." .. side] = ang(side == "L" and -wrong * 0.35 or 0, 0, 0)
		out["Hand." .. side] = hand
	end

	------------------------------------------------ fingers
	-- (the hands hang with their palms in, so fingers curl round the model's Z - the
	-- front-to-back axis - towards the palm: +Z on the left hand, -Z on the right)
	local spasm = J.fingers.x
	for i, f in ipairs(FINGERS) do
		-- left: long fingers drumming one after another; reaching, splayed, then clawing
		local wave = 0.5 + 0.5 * sin(t * 2.4 - i * 0.8)
		local curl = 6 + 22 * wave * (1 - reach) - 14 * reach + 46 * smooth((reach - 0.8) / 0.2) - spasm * 0.12
		local spread = (2.5 - i) * (3 + 8 * reach + spasm * 0.02)
		out[f .. "Meta.L"] = ang(0, 0, 0)
		out[f .. "1.L"] = ang(spread, 0, curl * 0.5)
		out[f .. "2.L"] = ang(0, 0, curl)
		out[f .. "3.L"] = ang(0, 0, curl * 0.8)
		-- right: clenched round the scissors, squeezing as they shut
		local squeeze = 5 * smooth(1 - open / 20) * (self.snipState == "closed" and 1 or 0)
		out[f .. "1.R"] = ang(0, 0, -squeeze)
		out[f .. "2.R"] = ang(0, 0, -squeeze * 0.6)
	end
	out["Thumb2.L"] = ang(0, 0, 8 * (1 - reach))

	------------------------------------------------ legs
	for _, side in ipairs(SIDES) do
		local thigh = side == "R" and thighR or thighL
		local knee = side == "R" and kneeR or kneeL
		local buckle = J[side == "R" and "kneeR" or "kneeL"].x
		local crouch = 6 * run + 10 * strike
		out["Thigh." .. side] = ang(5 + crouch + thigh + buckle * 0.3, 0, 0)
		out["Shin." .. side] = ang(-10 - crouch * 1.6 + knee - buckle * 0.6, 0, 0)
		out["Foot." .. side] = ang(5 + crouch * 0.6 - knee * 0.3 + buckle * 0.25, 0, 0)
		out["Toe." .. side] = ang(-6 * mv * max(0, side == "R" and -s1 or s1), 0, 0)
	end

	------------------------------------------------ forward kinematics (where every joint is now)
	local D, P = self.D, self.P
	local par = self.rig.parent
	for _, name in ipairs(self.rig.order) do
		local r = out[name] or IDENTITY
		local parent = par[name]
		if parent and D[parent] then
			local dp = D[parent]
			D[name] = dp * rotOnly(r)
			P[name] = P[parent] + dp * (pos[name] - pos[parent] + r.Position)
		else
			D[name] = rotOnly(r)
			P[name] = pos[name] + r.Position
		end
	end

	------------------------------------------------ the eyes: locked on you, or darting about
	local eyeYaw, eyePitch = self.eyeYaw.goal, self.eyePitch.goal
	if target and D.Head and pos["Eye.L"] then
		local eye = (P["Eye.L"] + P["Eye.R"]) / 2
		local l = D.Head:Inverse() * (target - eye)
		eyeYaw = clamp(math.atan2(-l.X, -l.Z), rad(-28), rad(28))
		eyePitch = clamp(math.atan2(l.Y, sqrt(l.X * l.X + l.Z * l.Z)), rad(-22), rad(22))
	elseif t >= self.nextDart then
		self.nextDart = t + rng:NextNumber(0.25, 1.4)
		eyeYaw, eyePitch = rad(rng:NextNumber(-25, 25)), rad(rng:NextNumber(-15, 12))
	end
	self.eyeYaw.goal, self.eyePitch.goal = eyeYaw, eyePitch
	local ey, ep = step(self.eyeYaw, dt), step(self.eyePitch, dt)
	out["Eye.L"] = CFrame.Angles(ep, ey, 0)
	out["Eye.R"] = CFrame.Angles(ep, ey, 0)

	------------------------------------------------ hair and cloth
	self:dangle(dt, input.frame or IDENTITY)
	return out
end

-- every dangling chain: a little rope simulation in the world (so walking,
-- turning and head-snaps all swing it), pulled gently back towards how it
-- hangs on the model, then turned into bone rotations
function StitcherPose:dangle(dt, frame)
	local D, P, pos, out = self.D, self.P, self.rig.pos, self.out
	local h = min(dt, 1 / 30)
	local teleported = self.lastFrame == nil or (frame.Position - self.lastFrame.Position).Magnitude > 8
	self.lastFrame = frame
	local headC, headR = nil, self.headRadius
	if D.Head then
		headC = frame * (P.Head + D.Head * (self.headCentre - pos.Head))
	end
	local legs = {}
	for _, side in ipairs({ "L", "R" }) do
		local a, b, c = P["Thigh." .. side], P["Shin." .. side], P["Foot." .. side]
		if a and b and c then
			table.insert(legs, { frame * a, frame * b })
			table.insert(legs, { frame * b, frame * c })
		end
	end
	local torsoA = P.Root and frame * P.Root
	local torsoB = P.Spine5 and frame * P.Spine5

	local function pushOutSegment(x, a, b, r)
		local ab = b - a
		local tt = clamp((x - a):Dot(ab) / max(ab:Dot(ab), 1e-6), 0, 1)
		local c = a + ab * tt
		local d = x - c
		local dist = d.Magnitude
		if dist < r and dist > 1e-5 then
			return c + d * (r / dist)
		end
		return x
	end

	for _, ch in ipairs(self.chains) do
		local parent = ch.parent
		local Dp = D[parent] or IDENTITY
		local Pp = P[parent] or pos[parent]
		local rp = pos[parent]
		local n = ch.n
		-- where each point would be if the chain were stiff
		local rigid = {}
		for i = 0, n do
			rigid[i] = frame * (Pp + Dp * (ch.rest[i] - rp))
		end
		if teleported or not ch.p then
			ch.p, ch.prev = {}, {}
			for i = 0, n do
				ch.p[i], ch.prev[i] = rigid[i], rigid[i]
			end
		end
		local p, prev = ch.p, ch.prev
		local damp = ch.damp ^ (h * 60)
		local pull = 1 - (1 - ch.stiff) ^ (h * 60)
		p[0] = rigid[0]
		prev[0] = rigid[0]
		for i = 1, n do
			local cur = p[i]
			local vel = (cur - prev[i]) * damp
			prev[i] = cur
			p[i] = cur + vel + GRAVITY * (ch.grav * h * h) + (rigid[i] - cur) * pull
		end
		for _ = 1, 3 do
			for i = 1, n do
				local a, b = p[i - 1], p[i]
				local d = b - a
				local L = d.Magnitude
				if L > 1e-6 then
					local corr = d * ((L - ch.seg[i]) / L)
					if i == 1 then
						p[i] = b - corr
					else
						p[i - 1] = a + corr * 0.5
						p[i] = b - corr * 0.5
					end
				end
			end
			for i = 1, n do
				if ch.collide == "head" and headC then
					local d = p[i] - headC
					local dist = d.Magnitude
					if dist < headR and dist > 1e-5 then
						p[i] = headC + d * (headR / dist)
					end
				elseif ch.collide == "legs" then
					for _, seg in ipairs(legs) do
						p[i] = pushOutSegment(p[i], seg[1], seg[2], 0.26)
					end
				elseif ch.collide == "torso" and torsoA and torsoB then
					p[i] = pushOutSegment(p[i], torsoA, torsoB, 0.26)
				end
			end
		end
		-- the points, back into bone turns
		local Dcur = Dp
		for i = 1, n do
			local want = frame:VectorToObjectSpace(p[i] - p[i - 1])
			local restDir = ch.rest[i] - ch.rest[i - 1]
			if want.Magnitude > 1e-6 and restDir.Magnitude > 1e-6 then
				local r = between(restDir.Unit, (Dcur:Inverse() * want).Unit)
				out[ch.bones[i]] = r
				Dcur = Dcur * r
			end
		end
	end
end

return StitcherPose
