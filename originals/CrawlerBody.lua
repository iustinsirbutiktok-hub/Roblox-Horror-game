-- CrawlerBody
-- Place in: ReplicatedStorage (a ModuleScript named exactly "CrawlerBody")
--
-- The Crawler's body, worked out fresh every frame on each player's screen.
-- Nothing here is a canned animation: every hand and foot is planted on the
-- real floor and only lifts when it has to, the body rides on springs so it
-- sways, overshoots and settles, the head locks onto you while the body
-- moves under it, and it twitches, cracks and contorts on its own.
--   * prowling: slow, deliberate, one limb at a time, hands lifted high
--   * chasing: a low spider-like gallop, jaw hanging open
--   * vents: flattens itself, splays its limbs out wide, head turned sideways
--   * catches: follows the choreography in CrawlerShared
--   * walls and ceilings: the body is always solved as if on a floor; the
--     animator hands it a turned "floor world" (input.space) and it turns the
--     result back onto the wall or ceiling. Up there its head twists round
--     the right way up to stare at you (input.flip).
-- CrawlerAnimator feeds it what the world looks like (where the root part is,
-- raycasts, the server's state) and applies what comes out.

local Body = {}
Body.__index = Body

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = require(ReplicatedStorage:WaitForChild("CrawlerShared"))
local Config = require(ReplicatedStorage:WaitForChild("CrawlerConfig"))

local clamp = math.clamp
local rad = math.rad
local noise = math.noise
local sin, cos, pi = math.sin, math.cos, math.pi
local UP = Vector3.new(0, 1, 0)

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function wrapAngle(a)
	return (a + pi) % (2 * pi) - pi
end

-- which beat of the stride each limb steps on
local WALK_PHASE = { RA = 0.25, LA = 0.75, RL = 0.5, LL = 0 }      -- one at a time: back, front, back, front
local RUN_PHASE = { RA = 0, LA = 0.12, RL = 0.55, LL = 0.67 }      -- a bounding gallop

local JAW_OPEN = rad(38)

--------------------------------------------------
-- SETUP
--------------------------------------------------

-- info = { groundY = floor height in root space at rest (negative),
--          topAboveTorso = how far its highest point sits above the torso centre,
--          underside = points (torso space) around the bottom of everything welded to its torso,
--          topside = the same along the top of it,
--          headUnder / jawUnder = the same for the head and jaw (in their own space) }
function Body.new(rig, info)
	local self = setmetatable({}, Body)
	self.rig = rig
	self.groundY = info.groundY
	self.topAbove = info.topAboveTorso or 1.3
	self.underside = info.underside or {}                -- torso-space points along its belly
	self.topside = info.topside or {}                    -- and along its spine
	self.headUnder = info.headUnder or {}                -- same for the head and the jaw
	self.jawUnder = info.jawUnder or {}
	self.out = {}
	self.events = {}
	self.limb = {}
	for _, l in ipairs(rig.list) do
		local home
		if l.arm then
			home = Vector3.new(l.endPivot.X * 1.15, 0, l.endPivot.Z + 0.7)
		else
			home = Vector3.new(l.endPivot.X * 1.2, 0, l.endPivot.Z - 0.1)
		end
		self.limb[l.key] = {
			home = home,
			lift = l.endPivot.Y - info.groundY,     -- wrist/ankle height above the floor when planted
			plant = nil, ground = nil, material = nil,
			swing = nil, swung = false,
		}
	end
	self.phase = 0
	self.vel = Vector3.zero
	self.yawRate = 0
	self.lastYaw = nil
	self.lastPos = nil
	self.squeeze = Shared.spring(0, 5, 0.9)
	self.room = Shared.spring(Config.PROWL_HEIGHT, 7, 1)
	self.ceiling = 99
	self.walls = { [1] = 99, [-1] = 99 }
	self.nextSense = 0
	self.offset = Shared.spring(Vector3.zero, 15, 0.62)
	self.pitch = Shared.spring(0, 13, 0.58)
	self.yaw = Shared.spring(0, 11, 0.6)
	self.roll = Shared.spring(0, 12, 0.5)
	self.rear = Shared.spring(0, 16, 0.65)
	self.headYaw = Shared.spring(0, 17, 0.48)
	self.headPitch = Shared.spring(0, 17, 0.5)
	self.headRoll = Shared.spring(0, 12, 0.45)
	self.flip = Shared.spring(0, 5.5, 0.62)              -- head twisted round (0..pi)
	self.flipWanted = false
	self.jaw = Shared.spring(0.1, 26, 0.42)
	self.tilt = 0
	self.tiltUntil = 0
	self.nextTwitch = 2
	self.chatterUntil = 0
	self.wasSqueezed = false
	self.lastState = nil
	self.lastStateStart = nil
	self.seed = math.random() * 100
	self.headCF = nil
	self.mouth = nil
	self.cc = {}
	return self
end

-- forget where the hands and feet are (after it teleports, or first frame)
function Body:resetFeet()
	for _, st in pairs(self.limb) do
		st.plant = nil
		st.swing = nil
	end
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function emit(self, kind, a, b, c, d)
	table.insert(self.events, { kind, a, b, c, d })
end

-- floor under a point: raycast down from the root's height
function Body:groundAt(point, root, cast)
	local origin = Vector3.new(point.X, root.Position.Y + 1, point.Z)
	local hit, normal, material = cast(origin, Vector3.new(0, -7, 0))
	if hit then
		return hit, material
	end
	return Vector3.new(point.X, root.Position.Y + self.groundY, point.Z), nil
end

-- how hard a hand/foot is curled: lifts with the claws dangling, reaches,
-- then settles flat
local function curlAt(a)
	if a < 0.45 then
		return -1.0 * Shared.smooth(a / 0.45)
	elseif a < 0.85 then
		return lerp(-1.0, 0.25, Shared.smooth((a - 0.45) / 0.4))
	end
	return lerp(0.25, 0, Shared.smooth((a - 0.85) / 0.15))
end

--------------------------------------------------
-- SENSING THE SPACE AROUND IT (vents)
--------------------------------------------------

function Body:sense(root, cast, now)
	if now < self.nextSense then
		return
	end
	self.nextSense = now + 0.08
	local look = root.LookVector
	local floor = root.Position.Y + self.groundY
	local lowest = 99
	for _, along in ipairs({ 2.4, 0, -1.8 }) do
		local p = root.Position + look * along
		local origin = Vector3.new(p.X, floor + 0.6, p.Z)
		local hit = cast(origin, Vector3.new(0, 9, 0))
		if hit then
			lowest = math.min(lowest, hit.Y - floor)
		end
	end
	self.ceiling = lowest
	for _, side in ipairs({ 1, -1 }) do
		local origin = root.Position + UP * (self.groundY + 0.9)
		local hit = cast(origin, root.RightVector * (side * 4))
		self.walls[side] = hit and (hit - origin).Magnitude or 99
	end
end

--------------------------------------------------
-- STEPPING
--------------------------------------------------

function Body:homeWorld(st, l, root, spread)
	local x = st.home.X * spread
	local wall = self.walls[l.side]
	if wall < 10 then
		x = clamp(math.abs(x), 0.4, math.max(wall - 0.35, 0.4)) * math.sign(st.home.X)
	end
	return root * Vector3.new(x, 0, st.home.Z)
end

function Body:startSwing(st, l, from, to, material, duration, arc)
	st.swing = { from = from, to = to, t = 0, dur = duration, arc = arc }
	st.material = material
end

function Body:stepLimbs(root, dt, now, cast, gait)
	local swinging = 0
	for _, st in pairs(self.limb) do
		if st.swing then
			swinging += 1
		end
	end

	for _, l in ipairs(self.rig.list) do
		local st = self.limb[l.key]
		local home = self:homeWorld(st, l, root, gait.spread)
		if not st.plant then
			st.plant, st.material = self:groundAt(home, root, cast)
		end
		if gait.frozen[l.key] then
			if st.swing then
				st.swing = nil                              -- that hand's busy holding you
				swinging -= 1
			end
			continue
		end

		-- where it wants this hand/foot to land: ahead of home by how far
		-- the body will travel before it lands again
		local lead = gait.vel * gait.leadTime
		local maxLead = l.arm and gait.armLead or gait.legLead
		if lead.Magnitude > maxLead then
			lead = lead.Unit * maxLead
		end
		local want = home + lead

		local drift = Vector3.new(st.plant.X - want.X, 0, st.plant.Z - want.Z).Magnitude
		if drift > 9 then
			-- it teleported; just put the foot down where it should be
			st.plant, st.material = self:groundAt(want, root, cast)
			st.swing = nil
			drift = 0
		end

		if st.swing then
			local s = st.swing
			s.t += dt / s.dur
			if s.t < 0.6 then
				-- keep aiming at where it now needs to land
				s.to = s.to:Lerp((self:groundAt(want, root, cast)), clamp(dt * 12, 0, 1))
			end
			if s.t >= 1 then
				st.plant = s.to
				st.swing = nil
				st.swung = gait.moving
				emit(self, "step", l, st.plant, st.material, gait.speed)
				self.offset.v += Vector3.new(0, -(0.3 + gait.speed * 0.01) * (1 - 0.5 * gait.run), 0)
				swinging -= 1
			end
		else
			local phase = (self.phase + lerp(WALK_PHASE[l.key], RUN_PHASE[l.key], gait.run)) % 1
			local inSwing = phase >= gait.duty
			if not inSwing then
				st.swung = false
			end
			local fromHome = Vector3.new(st.plant.X - home.X, 0, st.plant.Z - home.Z).Magnitude
			local go = false
			local duration = gait.swingTime
			if gait.moving then
				go = inSwing and not st.swung and drift > 0.25
			elseif drift > 0.75 and swinging == 0 then
				go = true                                   -- standing still but this one's out of place
				duration = 0.24
			end
			if not go and fromHome > (l.arm and 2.6 or 2.9) + gait.run * 0.7 then
				go = true                                   -- overstretched: step now
				duration = 0.16
			end
			if go then
				local to, material = self:groundAt(want, root, cast)
				local arc = l.arm and gait.armArc or gait.legArc
				-- now and then a hand hesitates: lifts too high, hangs there
				-- feeling the air, then comes down
				if l.arm and gait.run < 0.4 and math.random() < 0.16 then
					duration *= 1.9
					arc *= 1.6
				end
				arc = math.min(arc, math.max(self.ceiling - 1.6, 0.15))
				self:startSwing(st, l, st.plant, to, material, duration, arc)
				swinging += 1
			end
		end
	end
end

-- where a hand/foot is right now, and how curled
function Body:limbPoint(l, st, root)
	if st.swing then
		local s = st.swing
		local a = clamp(s.t, 0, 1)
		-- snatched up and thrown forward, then set down slowly and carefully:
		-- jerky, insect-like, never a smooth robotic arc
		local e = lerp(Shared.smooth(a), 1 - (1 - a) ^ 2.6, 0.7)
		local p = s.from:Lerp(s.to, e)
		local h = s.arc * math.sin(pi * a) ^ 0.7
		p += UP * h + root.RightVector * (l.side * 0.2 * sin(pi * a))
		-- curl the claws only as far as they stay clear of the floor
		return p, math.max(curlAt(a) * (l.arm and 1 or 0.6), -h * 0.8)
	end
	return st.plant, 0
end

--------------------------------------------------
-- EVERY FRAME
--------------------------------------------------

-- input = {
--   dt, now (os.clock), root (CFrame), cast (function(origin, dir) -> hit, normal, material),
--   state ("Move" / "Spot" / "Catch"), stateTime (seconds into that state), stateStart,
--   chasing (bool), target (Vector3: what it's looking at, or nil),
--   catch = nil or { kind, t, env, victimTorso, victimHead, standY },
-- }
-- Returns the Motor6D transforms (motor -> CFrame) and a list of events.
function Body:update(input)
	local dt = clamp(input.dt, 1 / 240, 0.1)
	local now = input.now
	local root = input.root
	local rig = self.rig
	local cast = input.cast
	table.clear(self.events)

	-- how it's moving
	local pos = root.Position
	if not self.lastPos or (pos - self.lastPos).Magnitude > 12 then
		self.lastPos = pos
		self:resetFeet()
	end
	local rawVel = (pos - self.lastPos) / dt
	self.lastPos = pos
	local prevFlat = Vector3.new(self.vel.X, 0, self.vel.Z)
	self.vel = self.vel:Lerp(rawVel, clamp(dt * 9, 0, 1))
	local flatVel = Vector3.new(self.vel.X, 0, self.vel.Z)
	local speed = flatVel.Magnitude
	local look = root.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local yawRate = self.lastYaw and wrapAngle(yaw - self.lastYaw) / dt or 0
	self.lastYaw = yaw
	self.yawRate = lerp(self.yawRate, yawRate, clamp(dt * 8, 0, 1))
	local accel = (flatVel - prevFlat) / dt
	local forwardAccel = accel:Dot(look)

	self:sense(root, cast, now)

	-- room to stand up in?
	local catch = input.catch
	local chasing = input.chasing
	local baseHeight = chasing and Config.CHASE_HEIGHT or Config.PROWL_HEIGHT
	-- the highest its torso can be with its spine under the ceiling
	self.room.goal = math.min(self.ceiling - self.topAbove - 0.15, baseHeight)
	local room = Shared.stepSpring(self.room, dt)
	if room > self.room.goal then
		room = math.max(self.room.goal, room - dt * 6)    -- never lag into the ceiling
		self.room.x = room
	end
	local torsoHeight = clamp(room, Config.MIN_SQUEEZE_HEIGHT, baseHeight)
	-- how folded up it is: drives the splayed limbs and the sideways head
	self.squeeze.goal = clamp((baseHeight - torsoHeight) / 0.8, 0, 1)
	local squeeze = clamp(Shared.stepSpring(self.squeeze, dt), 0, 1)
	if squeeze > 0.55 and not self.wasSqueezed then
		-- folding itself into the vent
		self.wasSqueezed = true
		emit(self, "sound", "BoneCrack", "head", 1, 0.9)
		emit(self, "sound", "BoneCrack", "root", 0.8, 1.15)
	elseif squeeze < 0.3 then
		self.wasSqueezed = false
	end

	-- state changes (the shriek when it spots you)
	if input.stateStart ~= self.lastStateStart then
		self.lastStateStart = input.stateStart
		if input.state == "Spot" then
			emit(self, "sound", "Screech", "head")
			self.headRoll.v += (math.random() < 0.5 and -6 or 6)
		elseif input.state == "Watch" then
			emit(self, "sound", "Growl", "head", 0.6, 0.75)
		elseif input.state == "Stun" then
			-- blinded by the flash
			emit(self, "sound", "Screech", "head", 1, 1.35)
			emit(self, "sound", "BoneCrack", "head", 0.9, 0.9)
			self.headPitch.v += 9
			self.offset.v += Vector3.new(0, 2.5, 0)
		end
		self.lastState = input.state
	end

	--------------------------------------------------
	-- gait settings for this frame
	--------------------------------------------------
	local run = clamp((speed - 9) / 7, 0, 1)
	local stride = lerp(3.8, 8, run) * (1 - 0.3 * squeeze)
	local duty = lerp(lerp(0.72, 0.4, run), 0.78, squeeze)
	local freq = speed / stride
	local turnFreq = math.abs(self.yawRate) * 0.32
	local cycle = math.max(freq, turnFreq)
	local moving = cycle > 0.12 and not catch
	if moving then
		self.phase = (self.phase + cycle * dt) % 1
	end
	local swingTime = clamp((1 - duty) / math.max(cycle, 0.01), 0.11, 0.42)
	local stanceTime = duty / math.max(cycle, 0.01)
	local gait = {
		vel = flatVel,
		speed = speed,
		moving = moving,
		run = run,
		duty = duty,
		stride = stride,
		swingTime = swingTime,
		leadTime = moving and math.min(stanceTime * 0.5 + swingTime, 0.6) or 0,
		armLead = lerp(1.2, 1.6, run),
		legLead = lerp(1.5, 1.8, run),
		spread = lerp(1, 1.55, squeeze),
		armArc = lerp(lerp(0.95, 0.6, run), 0.3, squeeze),
		legArc = lerp(lerp(0.6, 0.5, run), 0.25, squeeze),
		frozen = {},
	}

	--------------------------------------------------
	-- body pose
	--------------------------------------------------
	-- blinded by a flash: claws over its eyes, rearing back, staggering
	local stun = 0
	if input.state == "Stun" and not catch then
		local s = input.stateTime or 0
		stun = Shared.smooth(s / 0.12) * (1 - Shared.smooth((s - 1.45) / 0.45))
		if stun > 0.02 then
			gait.frozen.RA = true
			gait.frozen.LA = true
		end
	end

	local cc = nil
	if catch then
		cc = Shared.sampleCrawler(catch.kind, catch.t, catch.env, self.cc)
		if cc.hold > 0.02 then
			gait.frozen.RA = true
			gait.frozen.LA = true
		end
		if cc.swipeW > 0.02 then
			gait.frozen.RA = true
		end
	end
	self:stepLimbs(root, dt, now, cast, gait)

	-- the floor under its front and back ends
	local front, back = 0, 0
	for _, l in ipairs(rig.list) do
		local st = self.limb[l.key]
		local y = st.swing and st.swing.to.Y or st.plant.Y
		if l.arm then
			front += y / 2
		else
			back += y / 2
		end
	end
	local floorMid = (front + back) / 2
	local slope = math.atan2(front - back, 4.6)

	local restY = rig.torsoRest.Position.Y
	local lift = (floorMid + torsoHeight) - (pos.Y + restY)

	local t = now + self.seed
	local breath = sin(t * 2.1)
	local stepPhase = self.phase * 2 * pi
	local swingR, swingL = 0, 0
	for _, l in ipairs(rig.list) do
		if self.limb[l.key].swing then
			if l.side > 0 then swingR += 1 else swingL += 1 end
		end
	end

	local offY, offZ = lift + breath * 0.035, 0
	local pitch, yawB, roll, rear = slope + breath * 0.012, 0, 0, 0
	if catch then
		offY += cc.by
		offZ -= cc.bx
		pitch += rad(cc.pitch)
		yawB = rad(cc.yaw)
		roll = rad(cc.roll)
		rear = rad(cc.rear)
		self.offset.w, self.pitch.w, self.rear.w = 24, 20, 22
	else
		self.offset.w, self.pitch.w, self.rear.w = 15, 13, 16
		local gallop = run * (moving and 1 or 0)
		offY += gallop * 0.16 * sin(stepPhase + pi / 2) - (swingR + swingL) * 0.03 * (1 - gallop)
		offZ += gallop * 0.25 * sin(stepPhase)
		pitch += gallop * 0.13 * sin(stepPhase) - (chasing and 0.1 or 0.05) * (1 - squeeze)
		pitch += clamp(-forwardAccel * 0.012, -0.15, 0.15)
		yawB = clamp(-self.yawRate * 0.08, -0.3, 0.3) + (moving and 0.05 * sin(stepPhase) or 0)
		roll = 0.06 * (swingR - swingL) + clamp(self.yawRate * speed * 0.012, -0.25, 0.25)
		roll += squeeze * 0.08 * sin(t * 1.3)
		if input.state == "Spot" then
			-- jolts upright, then drops low ready to run
			local s = input.stateTime or 0
			rear = s < 0.3 and rad(16) or rad(-4)
			offY += s < 0.3 and 0.2 or -0.35
		elseif input.state == "Watch" then
			-- dead still, pressed flat, every muscle drawn in
			offY -= 0.25
			rear = rad(-6)
		elseif stun > 0 then
			-- reared up and back off the light, swaying, half off balance
			local s = input.stateTime or 0
			rear = rad(30) * stun + rad(6) * sin(s * 7) * stun
			offY += 0.3 * stun
			pitch -= 0.12 * stun
			roll += 0.16 * sin(s * 5.3) * stun
			yawB += 0.2 * sin(s * 3.1) * stun
		end
	end
	self.offset.goal = Vector3.new(0, offY, offZ)
	self.pitch.goal, self.yaw.goal, self.roll.goal, self.rear.goal = pitch, yawB, roll, rear

	--------------------------------------------------
	-- twitches (only when it isn't busy killing you)
	--------------------------------------------------
	if not catch and input.state ~= "Spot" and input.state ~= "Watch" and input.state ~= "Stun" and now >= self.nextTwitch then
		local calm = not chasing
		self.nextTwitch = now + (calm and 1.2 + math.random() * 2.6 or 2.5 + math.random() * 3)
		local r = math.random()
		if r < 0.35 then
			-- head snaps to one side with a crack
			self.headYaw.v += (math.random() - 0.5) * 16
			self.headRoll.v += (math.random() - 0.5) * 22
			if math.random() < 0.6 or squeeze > 0.5 then
				emit(self, "sound", "BoneCrack", "head")
			end
		elseif r < 0.55 then
			-- a shudder runs through its whole body
			self.roll.v += (math.random() < 0.5 and -1 or 1) * 3.5
			self.offset.v += Vector3.new(0, 1.2, 0)
		elseif r < 0.75 and calm then
			-- slow, curious head tilt, held
			self.tilt = (math.random() < 0.5 and -1 or 1) * (0.6 + math.random() * 0.9)
			self.tiltUntil = now + 0.8 + math.random() * 1.2
		elseif r < 0.88 then
			self.chatterUntil = now + 0.45 + math.random() * 0.5
			emit(self, "sound", "Chatter", "head")
		else
			-- taps one hand in place, fingers drumming the floor
			local st = self.limb[math.random() < 0.5 and "RA" or "LA"]
			if not st.swing and st.plant then
				self:startSwing(st, nil, st.plant, st.plant, st.material, 0.3, 0.45)
			end
		end
	end

	--------------------------------------------------
	-- solve the torso
	--------------------------------------------------
	local body = {
		offset = Shared.stepSpring(self.offset, dt),
		pitch = Shared.stepSpring(self.pitch, dt),
		yaw = Shared.stepSpring(self.yaw, dt),
		roll = Shared.stepSpring(self.roll, dt),
		rear = Shared.stepSpring(self.rear, dt),
	}
	local torso = Shared.torsoCFrame(rig, root, body)

	-- never let its belly sink through the floor (or through you, when it's on top of you)
	local lowest = math.huge
	for _, p in ipairs(self.underside) do
		lowest = math.min(lowest, (torso * p).Y)
	end
	local allowed = floorMid + 0.12
	if catch then
		allowed += 0.5 * clamp(cc.pin, 0, 1) * clamp(cc.hold, 0, 1)
	end
	if lowest < allowed then
		local push = allowed - lowest
		torso = CFrame.new(0, push, 0) * torso
		self.offset.x += Vector3.new(0, push, 0)
		if self.offset.v.Y < 0 then
			self.offset.v = Vector3.new(self.offset.v.X, 0, self.offset.v.Z)
		end
	end
	-- and keep its spine under the ceiling (a vent), as long as that doesn't
	-- push it into the floor
	if self.ceiling < 50 then
		local highest = -math.huge
		for _, p in ipairs(self.topside) do
			highest = math.max(highest, (torso * p).Y)
		end
		local lowestNow = math.huge
		for _, p in ipairs(self.underside) do
			lowestNow = math.min(lowestNow, (torso * p).Y)
		end
		local over = highest - (floorMid + self.ceiling - 0.06)
		local spare = lowestNow - (floorMid + 0.02)
		local down = math.min(over, spare)
		if down > 0 then
			torso = CFrame.new(0, -down, 0) * torso
			self.offset.x -= Vector3.new(0, down, 0)
		end
	end
	local torsoInv = torso:Inverse()
	local out = self.out
	out[rig.root] = rig.rootC0inv * root:Inverse() * torso * rig.root.C1
	self.torsoCF = torso

	--------------------------------------------------
	-- limbs
	--------------------------------------------------
	local rootRot = root.Rotation
	local holdPoints = nil
	if catch and cc.hold > 0.001 and catch.victimTorso then
		holdPoints = self:holdPoints(root, catch.victimTorso, cc.pin, Shared.CATCHES[catch.kind].yank)
	end
	local ends = {}
	for _, l in ipairs(rig.list) do
		local st = self.limb[l.key]
		local p, curl = self:limbPoint(l, st, root)
		local target = p + UP * self.limb[l.key].lift
		local endRot = rootRot * l.endRest * CFrame.fromAxisAngle(l.curlAxis, curl)
		local pole
		if l.arm then
			-- elbows hitched up high and out to the sides, like a spider's
			pole = Vector3.new(l.side * lerp(1.3, 1.6, squeeze), lerp(lerp(1.25, 0.55, run), 0.15, squeeze), lerp(0.15, 0.9, run))
		else
			-- knees up and out, like a frog's when it's flattened, but not through the vent walls
			local room = clamp((self.walls[l.side] - 0.8) / 1.5, 0.3, 1)
			pole = Vector3.new(l.side * lerp(0.8, 1.4 * room, squeeze), lerp(0.6, 0.6 - 0.4 * room, squeeze), lerp(-0.7, -0.4, squeeze))
		end

		if stun > 0.01 and l.arm and self.vHeadCF then
			-- claws dragged over its eyes, rubbing, scratching at its own face
			local s = input.stateTime or 0
			local face = self.vHeadCF.Position
			local rub = Vector3.new(noise(s * 6, l.side * 3.1), noise(s * 7, l.side * 5.3) * 0.6, noise(s * 5, l.side * 7.7)) * 0.35
			local claw = face + root.RightVector * (l.side * 0.42) + root.LookVector * 0.25 - UP * 0.1 + rub
			target = target:Lerp(claw, Shared.smooth(stun))
			endRot = nil
			pole = Vector3.new(l.side * 1.3, 0.4, 0.5)
		end
		if catch and l.arm then
			if holdPoints and cc.hold > 0.001 then
				local grip = holdPoints[l.key]
				target = target:Lerp(grip, Shared.smooth(cc.hold))
				endRot = nil
				pole = Vector3.new(l.side * 1.0, 0.5, 0.6)
			end
			if l.key == "RA" and cc.swipeW > 0.001 then
				target = target:Lerp(self:swipePoint(root, catch, cc.swipe), Shared.smooth(cc.swipeW))
				endRot = nil
				pole = Vector3.new(1, 0.6, 0.8)
			end
		end
		local _, _, endPart = Shared.solveLimb(l, torso, torsoInv, target, rootRot:VectorToWorldSpace(pole), endRot, out)
		ends[l.key] = endPart
	end
	self.ends = ends

	--------------------------------------------------
	-- head and jaw
	--------------------------------------------------
	local headPos = self.vHeadCF and self.vHeadCF.Position or torso * rig.torsoRest:Inverse() * rig.neckPivot
	local lookAt = nil
	if catch and catch.victimHead then
		lookAt = catch.victimHead.Position
	elseif input.target and (chasing or input.state == "Spot" or input.state == "Watch" or input.stare) then
		lookAt = input.target
	end
	local yawGoal, pitchGoal
	if lookAt then
		local dir = root:VectorToObjectSpace(lookAt - headPos)
		yawGoal, pitchGoal = Shared.lookAngles(rig, dir)
	else
		-- nothing to look at: it searches, slowly, with sudden jerks
		yawGoal = noise(t * 0.33, 1.7) * 1.6
		pitchGoal = noise(t * 0.29, 8.3) * 0.45 + 0.2
	end
	yawGoal = clamp(yawGoal, -1.7, 1.7)
	-- (upside down, "up" in its floor version is down at you: it can crane further)
	-- (and with you pinned under it, it can stare straight down into your face)
	pitchGoal = clamp(pitchGoal, catch and -0.85 or -0.35, input.space and 1.45 or 1.0)

	local rollGoal = 0
	if now < self.tiltUntil then
		rollGoal = self.tilt
	end
	rollGoal += squeeze * 1.25                         -- head turned sideways to fit
	pitchGoal += squeeze * 0.15
	if chasing and not catch then
		rollGoal += 0.18 * sin(t * 1.7)
	end
	local shake = 0
	if catch then
		yawGoal += rad(cc.headYaw)
		pitchGoal += rad(cc.headPitch)
		rollGoal += rad(cc.headRoll)
		shake = cc.shake
	elseif input.state == "Spot" then
		shake = (input.stateTime or 0) < 0.6 and 0.7 or 0
	elseif input.state == "Watch" then
		shake = 0.12
	elseif stun > 0 then
		-- head thrown back and shaking, trying to clear its eyes
		local s = input.stateTime or 0
		shake = s < 1.1 and 1.1 or 0.45
		pitchGoal += 0.55 * stun
		yawGoal += 0.7 * sin(s * 4.2) * stun
	end

	-- upside down and staring at you: the head twists round the right way
	-- up, slowly, the neck cracking as it goes
	local wantFlip = input.flip == true
	if wantFlip ~= self.flipWanted then
		self.flipWanted = wantFlip
		emit(self, "sound", "BoneCrack", "head", 1, 0.8)
		self.nextNeckCrack = now + 0.25
	end
	self.flip.goal = wantFlip and pi or 0
	local flip = Shared.stepSpring(self.flip, dt)
	if self.nextNeckCrack and now >= self.nextNeckCrack then
		self.nextNeckCrack = nil
		emit(self, "sound", "BoneCrack", "head", 0.9, 1.15)
	end
	self.headYaw.goal, self.headPitch.goal, self.headRoll.goal = yawGoal, pitchGoal, rollGoal
	local hy = Shared.stepSpring(self.headYaw, dt) + noise(t * 23, 3.3) * 0.22 * shake
	local hp = Shared.stepSpring(self.headPitch, dt) + noise(t * 21, 5.9) * 0.16 * shake
	local hr = Shared.stepSpring(self.headRoll, dt) + noise(t * 27, 9.1) * 0.3 * shake

	-- jaw
	local jawGoal
	if catch then
		jawGoal = cc.jaw
	elseif input.state == "Spot" then
		jawGoal = (input.stateTime or 0) < 0.65 and 1.15 or 0.5
	elseif input.state == "Watch" then
		-- the jaw creeps open while it stares
		jawGoal = 0.15 + 0.95 * Shared.smooth((input.stateTime or 0) / 1.1)
	elseif stun > 0 then
		jawGoal = (input.stateTime or 0) < 0.9 and 1.3 or 0.55        -- shrieking, then gasping
	elseif chasing then
		jawGoal = 0.45 + 0.15 * sin(t * 7.3)
	else
		jawGoal = 0.08 + 0.04 * breath + squeeze * 0.1
	end
	if now < self.chatterUntil then
		jawGoal += 0.3 * math.max(sin(t * 38), 0)
	end
	self.jaw.goal = jawGoal
	local jaw = math.max(Shared.stepSpring(self.jaw, dt), 0) + noise(t * 30, 2.2) * 0.12 * shake

	hr += flip
	local headRot = Shared.headRotation(rig, rootRot, hy, hp, hr)
	local head, jawCF = Shared.solveHead(rig, torso, torsoInv, headRot, JAW_OPEN * jaw, out)

	-- and keep its chin off the floor: tip the head up if it would dig in
	local low, lowPoint = math.huge, nil
	for _, p in ipairs(self.headUnder) do
		local w = head * p
		if w.Y < low then
			low, lowPoint = w.Y, w
		end
	end
	if jawCF then
		for _, p in ipairs(self.jawUnder) do
			local w = jawCF * p
			if w.Y < low then
				low, lowPoint = w.Y, w
			end
		end
	end
	local headFloor = floorMid + 0.08
	if catch and catch.victimTorso and cc.pin > 0.5 then
		headFloor = math.min(headFloor, catch.victimTorso.Position.Y - 0.3)
	end
	if lowPoint and low < headFloor then
		local pivot = torso * rig.neck.C0.Position
		local reach = math.max((lowPoint - pivot).Magnitude, 0.5)
		local fix = math.asin(clamp((headFloor - low) / reach, 0, 1))
		self.headPitch.x += fix
		hp += fix
		headRot = Shared.headRotation(rig, rootRot, hy, hp, hr)
		head, jawCF = Shared.solveHead(rig, torso, torsoInv, headRot, JAW_OPEN * jaw, out)
	end
	self.vHeadCF = head
	local mouth = jawCF and head.Position:Lerp(jawCF.Position, 0.5) or head.Position

	-- on a wall / the ceiling: turn the whole body from its floor version onto
	-- the surface (only the root joint changes; every other joint is relative)
	local space = input.space
	if space then
		local actual = input.actualRoot or root
		out[rig.root] = rig.rootC0inv * actual:Inverse() * space * torso * rig.root.C1
		self.headCF = space * head
		self.mouth = space * mouth
		self.torsoCF = space * torso
	else
		self.headCF = head
		self.mouth = mouth
	end
	return out, self.events
end

-- where its hands go on a caught body: gripping your sides, or pressing down on top
function Body:holdPoints(root, victimTorso, pin, ankles)
	local points = {}
	local right = root.RightVector
	local fwd = root.LookVector
	local centre = victimTorso.Position
	if ankles then
		-- a hand clamped round each of your ankles
		local feet = { victimTorso * Vector3.new(0.5, -2.75, 0), victimTorso * Vector3.new(-0.5, -2.75, 0) }
		for _, key in ipairs({ "RA", "LA" }) do
			local side = key == "RA" and 1 or -1
			local a, b = feet[1], feet[2]
			points[key] = ((a - root.Position):Dot(right) * side > (b - root.Position):Dot(right) * side) and a or b
		end
		return points
	end
	-- the side of your torso nearest each of its hands
	local sides = {
		victimTorso * Vector3.new(1.15, 0.2, 0),
		victimTorso * Vector3.new(-1.15, 0.2, 0),
	}
	for _, key in ipairs({ "RA", "LA" }) do
		local side = key == "RA" and 1 or -1
		local a, b = sides[1], sides[2]
		local grip = ((a - root.Position):Dot(right) * side > (b - root.Position):Dot(right) * side) and a or b
		local press = centre + UP * 0.55 + right * (side * 0.6) - fwd * 0.15
		points[key] = grip:Lerp(press, clamp(pin, 0, 1))
	end
	return points
end

-- the backhand swing's path for its right hand (see the Swipe catch)
function Body:swipePoint(root, catch, s)
	local g = self.groundY
	local hold = catch.env.hold
	local standY = catch.env.standY
	local st = self.limb.RA
	local home = st.plant and root:PointToObjectSpace(st.plant) + UP * st.lift or Vector3.new(1.2, g + 0.5, -1.6)
	-- straight through your chest, wherever you're standing
	local chest = catch.victimTorso and root:PointToObjectSpace(catch.victimTorso.Position) + Vector3.new(0.3, 0.3, 0.35)
		or Vector3.new(0.4, g + standY + 0.5, -(hold - 0.2))
	local points = {
		home,
		Vector3.new(2.1, g + 4.3, 0.3),                    -- cocked back over its shoulder
		chest,
		Vector3.new(-2.3, g + 2.4, -1.7),                  -- follow through
	}
	return root * Shared.path(points, { 0, 0.35, 0.6, 1 }, s)
end

--------------------------------------------------
-- THE CAUGHT PLAYER
--------------------------------------------------
-- joints = { root, neck, rs, ls, rh, lh } (the R6 Motor6Ds; any may be nil)
-- frame = { base, f, r, standY }. Writes their transforms into `out` and
-- returns their root part, torso and head CFrames.
function Body.poseVictim(kind, t, env, frame, joints, out, v)
	v = Shared.sampleVictim(kind, t, env, v or {})
	local n = t * 9
	local fl, kk, st = v.flail, v.kick, v.struggle
	-- thrash away from the floor: lying face down your arms and legs flail
	-- upwards, on your back your legs kick up
	local prone, onBack = v.lean > 45, v.lean < -45
	local function arm(x)
		return prone and math.abs(x) or x
	end
	local function leg(x)
		if prone then
			return -math.abs(x)
		elseif onBack then
			return math.abs(x)
		end
		return x
	end
	v.rSwing += arm(noise(n, 1.3)) * 80 * fl
	v.lSwing += arm(noise(n, 7.7)) * 80 * fl
	v.rOut += math.abs(noise(n, 3.1)) * 40 * fl
	v.lOut += math.abs(noise(n, 5.3)) * 40 * fl
	v.rHip += leg(noise(n * 1.2, 11.5)) * 60 * kk
	v.lHip += leg(noise(n * 1.2, 13.9)) * 60 * kk
	v.roll += noise(t * 4, 21.1) * 16 * st
	v.twist += noise(t * 4, 31.7) * 20 * st
	v.neck += noise(t * 5, 41.3) * 14 * (fl + st)

	local hrp = Shared.victimRoot(frame, v)
	Shared.r6Pose(joints, v, out)
	local torso, head = hrp, hrp
	if joints.root then
		torso = hrp * joints.root.C0 * out[joints.root] * joints.root.C1:Inverse()
		head = torso * CFrame.new(0, 1.5, 0)
		if joints.neck then
			head = torso * joints.neck.C0 * out[joints.neck] * joints.neck.C1:Inverse()
		end
	end
	return hrp, torso, head, v
end

return Body
