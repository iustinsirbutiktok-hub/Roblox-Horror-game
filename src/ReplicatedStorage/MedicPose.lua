-- MedicPose
-- Place in: ReplicatedStorage (a ModuleScript named exactly "MedicPose")
--
-- The Medic's body, worked out fresh every frame (MedicAnimator applies it to
-- the imported skeleton's Bones). Every rotation here is around the MODEL's
-- own axes - X = its right, Y = up, Z = behind it - taken at the joint and
-- carried along by everything above it, so "Spine3 tips forward 10 degrees"
-- means exactly that whatever the importer did to the bones.
--
--   * standing: hunched, shoulders hitched up, arms hanging too long, knees
--     soft, breathing slow and shallow, fingers twitching one after another
--   * like a puppet: now and then a string yanks - a shoulder jerks up, an
--     arm flies forward, a knee buckles, the head cracks sideways - and it
--     wobbles back down, never quite settling
--   * its head snaps round to you (in jumps, not smoothly), tilted
--   * close by, its nearest arm comes up slowly to reach for you, both
--     elbows straightening, the fingers spreading, then curling; the jaw drops
--   * walking: long, uneven strides, the arms swinging late and loose, the
--     head held dead still

local MedicPose = {}
MedicPose.__index = MedicPose

local rad = math.rad
local sin = math.sin
local clamp = math.clamp
local noise = math.noise

local FINGERS = { "Thumb", "Index", "Middle", "Ring", "Pinky" }
local SIDES = { L = -1, R = 1 }             -- which way is "out" along X for each side

local function smooth(a)
	a = clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function spring(x, w, z)
	return { x = x or 0, v = 0, goal = x or 0, w = w, z = z }
end

local function step(s, dt)
	local n = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / n
	for _ = 1, n do
		s.v += (s.w * s.w * (s.goal - s.x) - 2 * s.z * s.w * s.v) * h
		s.x += s.v * h
	end
	return s.x
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

local function ang(x, y, z)
	return CFrame.Angles(rad(x or 0), rad(y or 0), rad(z or 0))
end

-- rig = { pos = { boneName = Vector3 (model space, at rest) } }
function MedicPose.new(rig, seed)
	local self = setmetatable({}, MedicPose)
	self.rig = rig
	self.seed = seed or math.random() * 100
	self.rng = Random.new(math.floor(self.seed * 1000))
	self.phase = 0
	self.out = {}
	-- string pulls: each a wobbly spring kicked now and then
	self.jerk = {}
	for _, k in ipairs({ "clavL", "clavR", "armL", "armR", "head", "headRoll", "spine", "kneeL", "kneeR", "lift",
		"fingersL", "fingersR", "jaw" }) do
		self.jerk[k] = spring(0, 13, 0.22)
	end
	self.nextJerk = 1.5
	-- head: snaps between where it's decided to look
	self.headYaw = spring(0, 26, 0.38)
	self.headPitch = spring(0, 26, 0.38)
	self.headRoll = spring(rad(18), 9, 0.5)
	self.nextLook = 0
	-- the arm reaching for you, and how open the jaw is
	self.reachL = spring(0, 2.6, 0.9)
	self.reachR = spring(0, 2.6, 0.9)
	self.jawOpen = spring(0.2, 6, 0.6)
	-- the arms swing like dead weight
	self.swingL = spring(0, 5, 0.35)
	self.swingR = spring(0, 5, 0.35)
	self.move = spring(0, 4, 1)
	return self
end

-- input = { dt, t (seconds), speed (studs/s forward), target (Vector3 in
-- model space, or nil), near (0..1: how close the nearest player is) }
-- returns { boneName = CFrame } (model-space turn, plus a lift on "Root")
function MedicPose:update(input)
	local dt = clamp(input.dt, 1 / 240, 0.1)
	local t = input.t + self.seed
	local rng = self.rng
	local J = self.jerk
	local out = self.out
	table.clear(out)

	------------------------------------------------ string pulls
	if t >= self.nextJerk then
		self.nextJerk = t + rng:NextNumber(1.2, 4.2) * (input.target and 0.7 or 1)
		local r = rng:NextNumber()
		local s = rng:NextNumber() < 0.5 and 1 or -1
		if r < 0.18 then
			J[s > 0 and "clavR" or "clavL"].v += 160          -- a shoulder yanked up
			J.lift.v += 1.5
		elseif r < 0.36 then
			J[s > 0 and "armR" or "armL"].v += 420            -- an arm thrown forward
		elseif r < 0.52 then
			J.headRoll.v += 520 * s                           -- the head cracks over
			J.head.v += 200 * s
		elseif r < 0.64 then
			J.spine.v += 260                                  -- the whole body jolts
			J.lift.v += 2.5
		elseif r < 0.76 then
			J[s > 0 and "kneeR" or "kneeL"].v += 380           -- a knee buckles
		elseif r < 0.9 then
			J.fingersL.v += 500                               -- the fingers spasm open
			J.fingersR.v += 500
		else
			J.jaw.v += 300                                    -- the jaw drops
		end
	end
	for _, s in pairs(J) do
		step(s, dt)
	end

	------------------------------------------------ walking
	local speed = input.speed or 0
	self.move.goal = clamp(speed / 3, 0, 1)
	local mv = step(self.move, dt)
	-- uneven, lurching strides
	local stride = 6.5
	self.phase = (self.phase + speed / stride * dt * (1 + 0.35 * sin(self.phase * 4 * math.pi))) % 1
	local p = self.phase * 2 * math.pi
	local s1 = sin(p)
	local thighR = 24 * s1 * mv
	local thighL = -24 * s1 * mv
	local kneeR = -48 * math.max(0, sin(p + 1.1)) * mv
	local kneeL = -48 * math.max(0, sin(p + 1.1 + math.pi)) * mv
	local bob = -0.18 * math.abs(s1) * mv
	local sway = 4 * sin(p) * mv
	-- arms: dead weight dragged along, swinging late
	self.swingR.goal = -18 * s1 * mv
	self.swingL.goal = 18 * s1 * mv
	local swingR, swingL = step(self.swingR, dt), step(self.swingL, dt)

	------------------------------------------------ breathing (slow, shallow, ragged)
	local breath = sin(t * 1.6) + 0.3 * sin(t * 4.1)

	------------------------------------------------ the head: snaps to look
	local yawGoal, pitchGoal = self.headYaw.goal, self.headPitch.goal
	if input.target then
		local neck = self.rig.pos.Neck3 or Vector3.new(0, 7, 0)
		local d = input.target - neck
		local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
		local wantYaw = clamp(math.atan2(-d.X, -d.Z), rad(-85), rad(85))
		local wantPitch = clamp(math.atan2(d.Y, math.max(flat, 0.1)), rad(-50), rad(35))
		-- it doesn't track you smoothly: it jumps, now and then, or when you've moved a lot
		if t >= self.nextLook or math.abs(wantYaw - yawGoal) > rad(30) then
			self.nextLook = t + rng:NextNumber(0.25, 1.1)
			yawGoal, pitchGoal = wantYaw, wantPitch
		end
	elseif t >= self.nextLook then
		-- nothing to look at: it searches, in jerks
		self.nextLook = t + rng:NextNumber(0.8, 2.8)
		yawGoal = rad(rng:NextNumber(-60, 60))
		pitchGoal = rad(rng:NextNumber(-25, 10))
		if rng:NextNumber() < 0.3 then
			self.headRoll.goal = rad(rng:NextNumber(-30, 30))
		end
	end
	self.headYaw.goal, self.headPitch.goal = yawGoal, pitchGoal
	local hy, hp = step(self.headYaw, dt), step(self.headPitch, dt)
	local hr = step(self.headRoll, dt) + rad(J.headRoll.x)

	------------------------------------------------ reaching for you
	local near = input.near or 0
	local reachSide = nil
	if input.target and near > 0 then
		reachSide = input.target.X >= 0 and "R" or "L"
	end
	self.reachR.goal = reachSide == "R" and smooth(near) or 0
	self.reachL.goal = reachSide == "L" and smooth(near) or 0
	local reach = { R = step(self.reachR, dt), L = step(self.reachL, dt) }
	self.jawOpen.goal = 0.18 + 0.12 * (0.5 + 0.5 * sin(t * 0.7)) + 0.6 * near
	local jaw = step(self.jawOpen, dt)

	------------------------------------------------ the body
	local hunch = 1 - 0.25 * mv
	out.Root = CFrame.new(0, -0.03 + bob + 0.06 * J.lift.x - 0.05 * breath * 0.2, 0) * ang(0, sway, -sway * 0.4)
	out.Spine1 = ang(-5 * hunch + J.spine.x * 0.2, -sway * 0.6, 0)
	out.Spine2 = ang(-8 * hunch + breath * 0.6, 0, 0)
	out.Spine3 = ang(-10 * hunch + breath * 1.0 - J.spine.x * 0.1, 0, 0)
	out.Spine4 = ang(-9 * hunch + breath * 0.8, 0, 0)
	out.Spine5 = ang(-6 * hunch - 4 * mv, 0, 0)
	-- the neck cranes up out of the hunch to look; the head turns in jumps
	local look = 1 - 0.3 * smooth(math.abs(hp) / rad(40))
	out.Neck1 = ang(12 * look, math.deg(hy) * 0.2, 0)
	out.Neck2 = ang(10 * look + math.deg(hp) * 0.35, math.deg(hy) * 0.3, 0)
	out.Neck3 = ang(6 + math.deg(hp) * 0.35, math.deg(hy) * 0.25, math.deg(hr) * 0.4)
	out.Head = ang(4 + math.deg(hp) * 0.3, math.deg(hy) * 0.25 + J.head.x * 0.3, math.deg(hr) * 0.6)
	out.Jaw = ang(-(8 + 34 * jaw + J.jaw.x * 0.5 + 3 * noise(t * 9, self.seed) * near), 0, 0)

	------------------------------------------------ arms and hands
	for side, out_ in pairs(SIDES) do
		local m = side == "R" and 1 or -1                    -- mirror for the left
		local swing = side == "R" and swingR or swingL
		local r = reach[side]
		-- shoulders hitched up and rolled forward
		out["Clavicle." .. side] = ang(0, 6 * m, m * (10 + J[side == "R" and "clavR" or "clavL"].x * 0.3 + breath * 0.8))
		-- hanging in close, too long, swinging dead
		local armJerk = J[side == "R" and "armR" or "armL"].x
		local hang = ang(6 + swing + armJerk * 0.35, 0, -m * 24)
		-- reaching: the whole arm swung round to point at you
		local upper = hang
		if r > 0.001 and input.target then
			local shoulder = self.rig.pos["UpperArm." .. side] or Vector3.new(m * 0.66, 6.05, 0)
			local wrist = self.rig.pos["Hand." .. side] or (shoulder + Vector3.new(m * 2, -2.7, 0))
			local rest = (wrist - shoulder).Unit
			local want = (input.target - shoulder)
			want = want.Magnitude > 0.1 and want.Unit or rest
			upper = hang:Lerp(between(rest, want), r)
		end
		out["UpperArm." .. side] = upper
		-- the first elbow bends forward, the second the wrong way; reaching, they straighten
		out["Forearm1." .. side] = ang(14 * (1 - r) + armJerk * 0.15, 0, 0)
		out["Forearm2." .. side] = ang(-16 * (1 - r) - 6 * noise(t * 0.8, m * 3.1), 0, 0)
		-- (towards the palm is -m round Z on both sides)
		out["Hand." .. side] = ang(-8 + 12 * r, 0, -m * (6 - 10 * r))
		-- fingers: twitching one after another; reaching, splayed wide, then clawing
		local spasm = J[side == "R" and "fingersR" or "fingersL"].x
		for i, f in ipairs(FINGERS) do
			local wave = 0.5 + 0.5 * sin(t * 2.3 - i * 0.7 + (side == "R" and 0 or 1.7))
			local curl = 14 + 22 * wave * (1 - r) - 25 * r + 40 * smooth((r - 0.85) / 0.15) - spasm * 0.12
			local spread = (3 - i) * (4 + 10 * r + spasm * 0.03)
			if f == "Thumb" then
				out["Thumb1." .. side] = ang(0, m * (10 + 10 * r), 0)
				out["Thumb2." .. side] = ang(0, 0, -m * curl * 0.5)
				out["Thumb3." .. side] = ang(0, 0, -m * curl * 0.4)
			else
				-- (curling is round the model's Z, towards the palm: -m on both sides)
				out[f .. "1." .. side] = ang(spread, 0, -m * curl * 0.6)
				out[f .. "2." .. side] = ang(0, 0, -m * curl)
				out[f .. "3." .. side] = ang(0, 0, -m * curl * 0.8)
			end
		end
	end

	------------------------------------------------ legs
	for side, _ in pairs(SIDES) do
		local thigh = side == "R" and thighR or thighL
		local knee = side == "R" and kneeR or kneeL
		local buckle = J[side == "R" and "kneeR" or "kneeL"].x
		out["Thigh." .. side] = ang(6 + thigh + buckle * 0.3, 0, 0)
		out["Shin." .. side] = ang(-12 + knee - buckle * 0.6, 0, 0)
		out["Foot." .. side] = ang(6 - knee * 0.3 + buckle * 0.25, 0, 0)
	end
	return out
end

return MedicPose
