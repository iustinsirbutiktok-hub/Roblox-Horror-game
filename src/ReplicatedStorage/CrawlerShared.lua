-- CrawlerShared
-- Place in: ReplicatedStorage (a ModuleScript named exactly "CrawlerShared")
--
-- The maths the Crawler's brain (CrawlerAI, server) and its body
-- (CrawlerAnimator, every player's screen) share:
--   * re-rigging the model so it walks level instead of standing on its tail
--   * two-bone IK for its limbs, and turning a wanted pose into Motor6D moves
--   * posing a caught R6 player
--   * the catch choreography (slam, swipe, finisher, and the vent versions),
--     so the server's damage lines up with what everyone sees

local Shared = {}

local rad = math.rad
local clamp = math.clamp
local UP = Vector3.new(0, 1, 0)

--------------------------------------------------
-- SMALL MATHS
--------------------------------------------------

local EASE = {
	linear = function(a) return a end,
	inOut = function(a) return a * a * (3 - 2 * a) end,
	in2 = function(a) return a * a end,
	in3 = function(a) return a * a * a end,
	out2 = function(a) return 1 - (1 - a) * (1 - a) end,
	out3 = function(a) return 1 - (1 - a) ^ 3 end,
	snap = function(a) return 1 - (1 - a) ^ 5 end,
	back = function(a)
		a -= 1
		return 1 + 2.70158 * a * a * a + 1.70158 * a * a
	end,
}
Shared.EASE = EASE

function Shared.smooth(a)
	a = clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- A keyframe track: { {time, value, ease?}, ... } sorted by time. The ease on
-- a key shapes the stretch leading INTO that key.
function Shared.sample(track, t)
	local first = track[1]
	if t <= first[1] then
		return first[2]
	end
	for i = 2, #track do
		local key = track[i]
		if t < key[1] then
			local prev = track[i - 1]
			local span = key[1] - prev[1]
			local a = span > 0 and (t - prev[1]) / span or 1
			return prev[2] + (key[2] - prev[2]) * EASE[key[3] or "inOut"](a)
		end
	end
	return track[#track][2]
end

-- Springs keep everything a little loose: they overshoot, wobble and settle
-- instead of snapping, which is most of what stops motion looking stiff.
function Shared.spring(value, speed, damping)
	return { x = value, v = value * 0, goal = value, w = speed, z = damping }
end

function Shared.stepSpring(s, dt)
	local steps = math.max(1, math.ceil(dt * 120))
	local h = dt / steps
	local w, z = s.w, s.z
	for _ = 1, steps do
		s.v += ((s.goal - s.x) * (w * w) - s.v * (2 * z * w)) * h
		s.x += s.v * h
	end
	return s.x
end

function Shared.flat(v, fallback)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return f.Unit
end

local function perpendicular(v)
	local p = v:Cross(UP)
	if p.Magnitude < 1e-3 then
		p = v:Cross(Vector3.xAxis)
	end
	return p.Unit
end

local function unit(v, fallback)
	local m = v.Magnitude
	if m < 1e-5 then
		return fallback
	end
	return v / m
end
Shared.unit = unit

-- the smallest rotation that turns direction a into direction b
function Shared.swing(a, b)
	local d = clamp(a:Dot(b), -1, 1)
	if d > 0.99999 then
		return CFrame.identity
	end
	local axis = a:Cross(b)
	axis = axis.Magnitude > 1e-6 and axis.Unit or perpendicular(a)
	return CFrame.fromAxisAngle(axis, math.acos(d))
end

-- a part turned by `rotation`, placed so its point `localPivot` sits on `worldPivot`
function Shared.atPivot(rotation, localPivot, worldPivot)
	return CFrame.new(worldPivot - rotation:VectorToWorldSpace(localPivot)) * rotation
end

-- where the middle joint goes so the chain origin -> target bends towards `pole`
function Shared.twoBone(origin, target, l1, l2, pole)
	local offset = target - origin
	local dist = offset.Magnitude
	local dir = dist > 1e-4 and offset / dist or Vector3.new(0, -1, 0)
	dist = clamp(dist, math.abs(l1 - l2) + 0.05, l1 + l2 - 0.002)
	local along = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
	local out = math.sqrt(math.max(l1 * l1 - along * along, 0))
	local bend = pole - dir * pole:Dot(dir)
	bend = bend.Magnitude > 1e-4 and bend.Unit or perpendicular(dir)
	return origin + dir * along + bend * out, origin + dir * dist
end

-- a smooth path through points (Catmull-Rom); s from 0 to 1 over the whole path,
-- with `marks` saying at which s each point is reached
function Shared.path(points, marks, s)
	local n = #points
	if s <= marks[1] then
		return points[1]
	end
	for i = 2, n do
		if s <= marks[i] or i == n then
			local a = clamp((s - marks[i - 1]) / math.max(marks[i] - marks[i - 1], 1e-4), 0, 1)
			local p0 = points[math.max(i - 2, 1)]
			local p1, p2 = points[i - 1], points[i]
			local p3 = points[math.min(i + 1, n)]
			local a2, a3 = a * a, a * a * a
			return (p1 * 2 + (p2 - p0) * a + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * a2 + (p1 * 3 - p0 - p2 * 3 + p3) * a3) * 0.5
		end
	end
	return points[n]
end

--------------------------------------------------
-- SETTING THE MODEL UP (server, once)
--------------------------------------------------
-- The model was built lying along its root part's Y axis, so a Humanoid would
-- stand it up on its tail. Work out which way its body really faces from
-- where its hands and feet are, and give it an upright root part to walk with.
--
--   torso   = Torso's CFrame in the world, in the model's built pose
--   points  = world positions of LeftHand, RightHand, LeftFoot, RightFoot, LeftArm, RightArm
--   boxes   = { {cframe, size}, ... } every visible part (for how tall it is)
--   floorY  = the floor under it (or nil)
-- Returns the new root part CFrame, the RootJoint C0 (with C1 = identity),
-- and some measurements of the body.
function Shared.planRig(torso, points, boxes, floorY, rootHeight)
	local side = unit(points.LeftArm - points.RightArm, Vector3.xAxis)    -- towards its left
	local handMid = (points.LeftHand + points.RightHand) / 2
	local footMid = (points.LeftFoot + points.RightFoot) / 2
	local fwd = handMid - footMid
	fwd = unit(fwd - side * fwd:Dot(side), Vector3.new(0, 0, -1))
	local up = side:Cross(fwd)
	if up:Dot(torso.Position - handMid) < 0 then
		up = -up
	end
	local right = fwd:Cross(up)
	local level = CFrame.fromMatrix(torso.Position, right, up, -fwd)

	local low, high, back, front = math.huge, -math.huge, math.huge, -math.huge
	for _, box in ipairs(boxes) do
		local cf, size = box[1], box[2] / 2
		for _, c in ipairs({
			Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, 1, 1),
			Vector3.new(1, -1, -1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(1, 1, 1),
		}) do
			local p = level:PointToObjectSpace(cf:PointToWorldSpace(size * c))
			low = math.min(low, p.Y)
			high = math.max(high, p.Y)
			back = math.min(back, -p.Z)
			front = math.max(front, -p.Z)
		end
	end
	local torsoHeight = -low                       -- torso centre above the floor
	local forwardOffset = ((handMid + footMid) / 2 - torso.Position):Dot(fwd)

	local flatFwd = Shared.flat(fwd)
	local groundY = floorY or (torso.Position + up * low).Y
	local centre = torso.Position + flatFwd * forwardOffset
	local rootPos = Vector3.new(centre.X, groundY + rootHeight, centre.Z)
	local rootCF = CFrame.lookAt(rootPos, rootPos + flatFwd)

	local rootC0 = CFrame.new(0, torsoHeight - rootHeight, forwardOffset) * level:ToObjectSpace(torso).Rotation
	return rootCF, rootC0, {
		torsoHeight = torsoHeight,
		topHeight = high - low,                    -- full height standing at rest
		topAboveTorso = high,
		length = front - back,
		forwardOffset = forwardOffset,
	}
end

--------------------------------------------------
-- THE CRAWLER'S SKELETON
--------------------------------------------------

Shared.LIMBS = {
	{ key = "RA", arm = true, side = 1, names = { "Right Shoulder", "Right Elbow", "Right Wrist" } },
	{ key = "LA", arm = true, side = -1, names = { "Left Shoulder", "Left Elbow", "Left Wrist" } },
	{ key = "RL", arm = false, side = 1, names = { "Right Hip", "Right Knee", "Right Ankle" } },
	{ key = "LL", arm = false, side = -1, names = { "Left Hip", "Left Knee", "Left Ankle" } },
}

-- find(name) returns that Motor6D (anything with C0/C1). Everything is
-- measured in root part space, after planRig has re-rigged the model.
function Shared.buildRig(find)
	local root, neck, jaw = find("RootJoint"), find("Neck"), find("Jaw")
	if not (root and neck) then
		return nil
	end
	local torsoRest = root.C0 * root.C1:Inverse()
	local headRest = torsoRest * neck.C0 * neck.C1:Inverse()
	local rig = {
		root = root, neck = neck, jaw = jaw,
		rootC0inv = root.C0:Inverse(),
		neckC0inv = neck.C0:Inverse(),
		torsoRest = torsoRest,
		headRest = headRest,
		neckPivot = torsoRest * neck.C0.Position,
		limbs = {},
		list = {},
	}

	-- which way the face points: from the neck joint towards the jaw hinge
	local face = jaw and (headRest * jaw.C0.Position) - rig.neckPivot or headRest.Position - rig.neckPivot
	rig.faceAxis = unit(face, Vector3.new(0, 0, -1))
	rig.facePitch = math.asin(clamp(rig.faceAxis.Y, -1, 1))
	rig.faceReach = face.Magnitude

	if jaw then
		-- the jaw opens around the body's side-to-side axis; find which way is "down"
		rig.jawAxis = (headRest * jaw.C0).Rotation:VectorToObjectSpace(Vector3.xAxis)
		local upInHead = headRest.Rotation:VectorToObjectSpace(UP)
		local rest = (jaw.C0 * jaw.C1:Inverse()).Position
		local opened = (jaw.C0 * CFrame.fromAxisAngle(rig.jawAxis, 0.4) * jaw.C1:Inverse()).Position
		rig.jawSign = opened:Dot(upInHead) < rest:Dot(upInHead) and 1 or -1
	end

	local hips = {}
	for _, spec in ipairs(Shared.LIMBS) do
		local j1, j2, j3 = find(spec.names[1]), find(spec.names[2]), find(spec.names[3])
		if not (j1 and j2 and j3) then
			return nil
		end
		local upper = j1.C0 * j1.C1:Inverse()                 -- in torso space
		local lower = upper * j2.C0 * j2.C1:Inverse()
		local upperBone = j2.C0.Position - j1.C1.Position
		local lowerBone = j3.C0.Position - j2.C1.Position
		local endRest = (torsoRest * lower * j3.C0 * j3.C1:Inverse()).Rotation
		local limb = {
			key = spec.key, arm = spec.arm, side = spec.side,
			j1 = j1, j2 = j2, j3 = j3,
			c0inv1 = j1.C0:Inverse(), c0inv2 = j2.C0:Inverse(), c0inv3 = j3.C0:Inverse(),
			l1 = upperBone.Magnitude, l2 = lowerBone.Magnitude,
			upperBone = upperBone.Unit, lowerBone = lowerBone.Unit,
			upperRest = upper.Rotation, lowerRest = lower.Rotation,
			endInLower = (j3.C0 * j3.C1:Inverse()).Rotation,
			rootPivot = torsoRest * j1.C0.Position,            -- shoulder / hip, root space
			endPivot = torsoRest * (lower * j3.C0.Position),   -- wrist / ankle, root space
			endRest = endRest,                                 -- hand / foot turn, root space
			curlAxis = endRest:VectorToObjectSpace(Vector3.xAxis),
		}
		rig.limbs[spec.key] = limb
		table.insert(rig.list, limb)
		if not spec.arm then
			table.insert(hips, limb.rootPivot)
		end
	end
	rig.hipMid = (hips[1] + hips[2]) / 2
	return rig
end

-- Points tracing the underside of everything welded to a bone (the torso by
-- default), so it can be kept out of the floor. boxes = { {cframe in that
-- bone's space, size}, ... }; restFrame = that bone in root space at rest.
-- Keeps the two lowest corners of each part (lowest as it stands at rest), or
-- the two highest with topside = true (for keeping its spine under a ceiling).
function Shared.undersidePoints(rig, boxes, restFrame, topside)
	restFrame = restFrame or rig.torsoRest
	local points = {}
	for _, box in ipairs(boxes) do
		local cf, half = box[1], box[2] / 2
		local corners = {}
		for _, c in ipairs({
			Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, 1, 1),
			Vector3.new(1, -1, -1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(1, 1, 1),
		}) do
			local p = cf * (half * c)
			table.insert(corners, { p, (restFrame * p).Y })
		end
		table.sort(corners, function(a, b)
			if topside then
				return a[2] > b[2]
			end
			return a[2] < b[2]
		end)
		table.insert(points, corners[1][1])
		table.insert(points, corners[2][1])
	end
	return points
end

-- Torso placement. body = { offset (root space), pitch, yaw, roll, rear } (radians);
-- `rear` rears it up around its hips, the rest turn around its middle.
function Shared.torsoCFrame(rig, root, body)
	local centre = rig.torsoRest.Position
	local hip = rig.hipMid
	return root * CFrame.new(body.offset)
		* CFrame.new(centre) * CFrame.Angles(body.pitch, body.yaw, body.roll) * CFrame.new(-centre)
		* CFrame.new(hip) * CFrame.Angles(body.rear, 0, 0) * CFrame.new(-hip)
		* rig.torsoRest
end

-- Bend one limb so its wrist/ankle lands on `target`, the elbow/knee pushed
-- towards `pole`. endRotation = how the hand/foot should be turned (nil =
-- hang naturally off the forearm/shin). Writes the three motor transforms
-- into `out` and returns the three parts' CFrames.
function Shared.solveLimb(limb, torso, torsoInv, target, pole, endRotation, out)
	local j1, j2, j3 = limb.j1, limb.j2, limb.j3
	local shoulder = torso * j1.C0.Position
	local elbow, reach = Shared.twoBone(shoulder, target, limb.l1, limb.l2, pole)
	local torsoRot = torso.Rotation

	local upperRot = torsoRot * limb.upperRest
	upperRot = Shared.swing(upperRot:VectorToWorldSpace(limb.upperBone), unit(elbow - shoulder, UP)) * upperRot
	local upper = Shared.atPivot(upperRot, j1.C1.Position, shoulder)

	local elbowPivot = upper * j2.C0.Position
	local lowerRot = torsoRot * limb.lowerRest
	lowerRot = Shared.swing(lowerRot:VectorToWorldSpace(limb.lowerBone), unit(reach - elbowPivot, UP)) * lowerRot
	local lower = Shared.atPivot(lowerRot, j2.C1.Position, elbowPivot)

	local wrist = lower * j3.C0.Position
	local endPart = Shared.atPivot(endRotation or lower.Rotation * limb.endInLower, j3.C1.Position, wrist)

	out[j1] = limb.c0inv1 * torsoInv * upper * j1.C1
	out[j2] = limb.c0inv2 * upper:Inverse() * lower * j2.C1
	out[j3] = limb.c0inv3 * lower:Inverse() * endPart * j3.C1
	return upper, lower, endPart
end

-- The head turned to `headRotation` (world) on its neck, the jaw open `jawAngle` radians.
function Shared.solveHead(rig, torso, torsoInv, headRotation, jawAngle, out)
	local neck = rig.neck
	local head = Shared.atPivot(headRotation, neck.C1.Position, torso * neck.C0.Position)
	out[neck] = rig.neckC0inv * torsoInv * head * neck.C1
	local jawCF = nil
	if rig.jaw then
		local t = CFrame.fromAxisAngle(rig.jawAxis, rig.jawSign * jawAngle)
		out[rig.jaw] = t
		jawCF = head * rig.jaw.C0 * t * rig.jaw.C1:Inverse()
	end
	return head, jawCF
end

-- Head turn from angles relative to the body's facing (`frame`, rotation only).
-- yaw + = its left, pitch + = up, roll + = tilts its head to its left. 0,0,0 = rest.
function Shared.headRotation(rig, frame, yaw, pitch, roll)
	return frame * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		* CFrame.fromAxisAngle(rig.faceAxis, roll) * rig.headRest.Rotation
end

-- yaw/pitch (relative to rest) that point the face along `dir` (root space)
function Shared.lookAngles(rig, dir)
	local flatLen = math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
	return math.atan2(-dir.X, -dir.Z), math.atan2(dir.Y, flatLen) - rig.facePitch
end

--------------------------------------------------
-- A CAUGHT PLAYER (R6)
--------------------------------------------------
-- Same pose numbers as DownedClient, so a finisher hands over to the downed
-- pose without a pop: lean 82 = face down, -82 = on your back, drop = how far
-- the torso sinks below the (standing-height) root part.

Shared.VICTIM_FIELDS = { "x", "z", "y", "yaw", "lean", "roll", "twist", "down", "neck", "neckRoll",
	"rSwing", "rOut", "lSwing", "lOut", "rHip", "rHipOut", "lHip", "lHipOut", "flail", "kick", "struggle" }

function Shared.r6Pose(joints, p, out)
	local function set(motor, r, offset)
		if motor then
			local rest = motor.C0.Rotation
			out[motor] = rest:Inverse() * (CFrame.new(offset or Vector3.zero) * r) * rest
		end
	end
	set(joints.root, CFrame.Angles(-rad(p.lean), rad(p.twist), rad(p.roll)), Vector3.new(0, -p.drop, 0))
	set(joints.neck, CFrame.Angles(-rad(p.neck), 0, rad(p.neckRoll)))
	set(joints.rs, CFrame.Angles(0, 0, rad(p.rOut)) * CFrame.Angles(rad(p.rSwing), 0, 0))
	set(joints.ls, CFrame.Angles(0, 0, -rad(p.lOut)) * CFrame.Angles(rad(p.lSwing), 0, 0))
	set(joints.rh, CFrame.Angles(0, 0, rad(p.rHipOut)) * CFrame.Angles(rad(p.rHip), 0, 0))
	set(joints.lh, CFrame.Angles(0, 0, -rad(p.lHipOut)) * CFrame.Angles(rad(p.lHip), 0, 0))
end

-- the caught player's root part. frame = { base (floor point under the
-- crawler), f (crawler -> you, flat), r (crawler's right), standY }
function Shared.victimRoot(frame, v)
	local pos = frame.base + frame.f * v.x + frame.r * v.z + UP * (frame.standY + v.y)
	local facing = CFrame.fromAxisAngle(UP, rad(v.yaw)):VectorToWorldSpace(-frame.f)
	return CFrame.lookAt(pos, pos + facing)
end

--------------------------------------------------
-- THE CATCHES
--------------------------------------------------
-- Times in seconds from the moment it grabs you. Victim channels:
--   x       studs further from it than where you were grabbed (+ = away from it)
--   z       studs to its right       y   studs above your standing height
--   yaw     degrees you're turned (0 = facing it, 180 = facing away)
--   lean/roll/twist/neck/... degrees, like DownedClient
--   down    0 standing .. 1 your torso is on the floor
--   flail/kick/struggle  how hard your arms/legs/body thrash (0..1)
-- Crawler channels:
--   bx/by   studs forward/up       rear  degrees reared up on its hind legs
--   pitch/yaw/roll  degrees        hold  hands on you (0..1)
--   pin     0 = gripping your sides, 1 = pressing down on you
--   swipe   0..1 along the backhand swing (swipeW = how much of it)
--   jaw     0 shut .. 1 wide open, more than 1 = unhinged
--   shake   head thrashing (0..1+)  headYaw/headPitch/headRoll degrees
-- Events: { time, "sound", name, where ("head"/"victim"/"root"/"local"), volume, speed }
--         { time, "kick", camera kick }   { time, "flash", red flash }
-- Server: hits = when the hit lands (damage), length = when you're let go,
-- backoff = { start, finish, studs } it slides back, resume = when it moves on.

local PRONE = { lean = 82, down = 1, neck = -62, rSwing = 167, lSwing = 167, rOut = 20, lOut = 20,
	rHip = -9, lHip = -9, rHipOut = 7, lHipOut = 7 }
Shared.PRONE = PRONE

Shared.CATCHES = {}

-- grabbed, lifted up to its face, slammed onto your back, it looms over you
-- twitching, then backs off while you scramble up
Shared.CATCHES.Slam = {
	length = 3.9, resume = 5.0, hits = { 1.02 }, lethal = false, beyond = 0.8,
	backoff = { 2.55, 3.15, 2.5 },
	victim = {
		x = { { 0, 0 }, { 0.28, -0.3, "out2" }, { 0.78, -1.0 }, { 1.02, 0.5, "in2" }, { 1.3, 0.55, "out2" } },
		y = { { 0, 0 }, { 0.28, 0.2, "out2" }, { 0.78, 2.3, "out3" }, { 0.9, 2.45, "out2" }, { 1.02, 0, "in3" },
			{ 1.12, 0.22, "out2" }, { 1.24, 0, "in2" } },
		down = { { 0, 0 }, { 0.9, 0 }, { 1.02, 1, "in3" }, { 2.65, 1 }, { 3.05, 0.62 }, { 3.45, 0.53 }, { 3.85, 0, "out2" } },
		lean = { { 0, 0 }, { 0.28, 14, "out2" }, { 0.78, -10 }, { 0.9, -22 }, { 1.02, -84, "in2" }, { 1.25, -80, "out2" },
			{ 2.65, -82 }, { 3.05, -28 }, { 3.45, 38 }, { 3.85, 0, "out2" } },
		roll = { { 0, 0 }, { 0.4, 8 }, { 0.78, -6 }, { 1.02, 4 }, { 1.3, 0 } },
		twist = { { 0, 0 }, { 0.6, 10 }, { 0.9, -8 }, { 1.02, 0 } },
		neck = { { 0, 0 }, { 0.15, 22, "snap" }, { 0.78, -10 }, { 1.02, -45, "in2" }, { 1.12, 30, "out2" }, { 1.4, 25 },
			{ 2.65, 25 }, { 3.05, 10 }, { 3.45, -15 }, { 3.85, 0 } },
		neckRoll = { { 1.4, 0 }, { 2.0, 18 }, { 2.5, -12 }, { 2.8, 0 } },
		rSwing = { { 0, 0 }, { 0.12, 75, "snap" }, { 0.3, 95 }, { 0.78, 120 }, { 1.02, 150, "in2" }, { 1.3, 110 },
			{ 1.6, 95 }, { 2.65, 90 }, { 3.05, -30 }, { 3.45, 35 }, { 3.85, 0, "out2" } },
		lSwing = { { 0, 0 }, { 0.14, 60, "snap" }, { 0.3, 100 }, { 0.78, 105 }, { 1.02, 160, "in2" }, { 1.3, 125 },
			{ 1.6, 100 }, { 2.65, 95 }, { 3.05, -25 }, { 3.45, 45 }, { 3.85, 0, "out2" } },
		rOut = { { 0, 0 }, { 0.12, 25 }, { 0.78, 35 }, { 1.02, 60 }, { 1.3, 30 }, { 2.65, 25 }, { 3.05, 15 }, { 3.45, 10 }, { 3.85, 0 } },
		lOut = { { 0, 0 }, { 0.14, 20 }, { 0.78, 30 }, { 1.02, 55 }, { 1.3, 28 }, { 2.65, 22 }, { 3.05, 15 }, { 3.45, 10 }, { 3.85, 0 } },
		rHip = { { 0, 0 }, { 0.3, 10 }, { 0.78, 25 }, { 1.02, 55, "in2" }, { 1.25, 8, "in2" }, { 2.65, 5 }, { 3.05, 62 },
			{ 3.45, 55 }, { 3.85, 0, "out2" } },
		lHip = { { 0, 0 }, { 0.3, -8 }, { 0.78, -12 }, { 1.02, 40, "in2" }, { 1.25, 4, "in2" }, { 2.65, 0 }, { 3.05, 58 },
			{ 3.45, 20 }, { 3.85, 0, "out2" } },
		rHipOut = { { 0, 0 }, { 1.02, 14 }, { 1.3, 8 }, { 2.65, 8 }, { 3.45, 6 }, { 3.85, 0 } },
		lHipOut = { { 0, 0 }, { 1.02, 14 }, { 1.3, 8 }, { 2.65, 8 }, { 3.45, 6 }, { 3.85, 0 } },
		flail = { { 0, 0 }, { 0.3, 0.6 }, { 0.4, 1 }, { 0.95, 1 }, { 1.02, 0.2 }, { 1.3, 0.5 }, { 2.5, 0.4 }, { 2.65, 0 } },
		kick = { { 0, 0 }, { 0.35, 1 }, { 0.95, 1 }, { 1.02, 0 }, { 1.3, 0.6 }, { 2.5, 0.5 }, { 2.65, 0 } },
		struggle = { { 1.3, 0 }, { 1.5, 1 }, { 2.5, 0.8 }, { 2.65, 0 } },
	},
	crawler = {
		bx = { { 0, 0 }, { 0.15, 0.75, "out2" }, { 0.3, 0.35 }, { 0.78, -0.35 }, { 1.02, 1.0, "in2" }, { 1.3, 1.5, "out2" },
			{ 1.9, 2.35 }, { 2.5, 2.2 }, { 3.2, 0 } },
		by = { { 0, 0 }, { 0.15, -0.35 }, { 0.3, -0.1 }, { 0.78, 0.45 }, { 1.02, -0.45, "in2" }, { 1.3, -0.5 }, { 1.9, -0.9 },
			{ 2.5, -0.75 }, { 3.2, 0 } },
		rear = { { 0, 0 }, { 0.15, -6 }, { 0.3, 6 }, { 0.78, 52, "out2" }, { 0.9, 56 }, { 1.02, -8, "in2" }, { 1.25, -12, "out2" },
			{ 1.9, -16 }, { 2.5, -10 }, { 3.2, 0 } },
		roll = { { 0, 0 }, { 0.78, -6 }, { 1.02, 4 }, { 1.6, 12 }, { 2.1, -9 }, { 2.5, 6 }, { 3.2, 0 } },
		yaw = { { 0, 0 }, { 0.78, 6 }, { 1.02, -4 }, { 1.4, 0 } },
		hold = { { 0, 0 }, { 0.2, 0 }, { 0.3, 1, "out2" }, { 2.5, 1 }, { 2.8, 0 } },
		pin = { { 0, 0 }, { 0.95, 0 }, { 1.1, 1, "out2" }, { 2.8, 1 } },
		jaw = { { 0, 0.25 }, { 0.15, 0.95, "out2" }, { 0.4, 0.5 }, { 0.7, 1.0 }, { 0.95, 1.05 }, { 1.02, 0.55 }, { 1.4, 0.3 },
			{ 1.85, 0.85 }, { 2.15, 0.2 }, { 2.45, 0.75 }, { 3.2, 0.3 } },
		shake = { { 0, 0 }, { 0.68, 0 }, { 0.75, 1 }, { 0.98, 0.7 }, { 1.1, 0 }, { 1.85, 0.6 }, { 2.15, 0 }, { 2.45, 0.5 }, { 2.8, 0 } },
		headRoll = { { 0, 0 }, { 1.3, 0 }, { 1.7, 38 }, { 2.05, -24 }, { 2.4, 52 }, { 2.9, 0 } },
	},
	events = {
		{ 0, "sound", "Lunge", "head" }, { 0, "sound", "Stinger", "local" }, { 0, "sound", "Heartbeat", "local" },
		{ 0, "kick", 0.5 },
		{ 0.3, "sound", "Grab", "victim" }, { 0.3, "kick", 0.6 },
		{ 0.62, "sound", "Screech", "head", 1, 1.25 },
		{ 1.02, "sound", "Slam", "victim" }, { 1.02, "sound", "Crunch", "victim" }, { 1.02, "kick", 1.6 }, { 1.02, "flash", 0.8 },
		{ 1.5, "sound", "Growl", "head" }, { 1.9, "sound", "Chatter", "head" }, { 2.4, "sound", "BoneCrack", "head" },
	},
	fov = { { 0, 70 }, { 0.3, 62 }, { 0.9, 55 }, { 1.02, 72, "snap" }, { 1.4, 58 }, { 2.4, 52 }, { 3.0, 70 } },
	cam = { { 0, 1 }, { 3.3, 1 }, { 3.9, 0 } },
}

-- it rears up and backhands you across the room; you land face down and get up
Shared.CATCHES.Swipe = {
	length = 3.35, resume = 4.4, hits = { 0.56 }, lethal = false, beyond = 5.5,
	victim = {
		x = { { 0, 0.5 }, { 0.45, 0.35 }, { 0.56, 0.35 }, { 1.1, 5, "out2" }, { 1.45, 5.7, "out3" } },
		z = { { 0.56, 0 }, { 1.1, -0.7, "out2" }, { 1.45, -0.8 } },
		y = { { 0, 0 }, { 0.56, 0 }, { 0.78, 1.5, "out2" }, { 1.1, 0, "in2" }, { 1.2, 0.18, "out2" }, { 1.3, 0, "in2" } },
		yaw = { { 0, 0 }, { 0.56, 0 }, { 1.1, 195, "out2" }, { 1.45, 180 } },
		lean = { { 0, 0 }, { 0.4, -8 }, { 0.56, -8 }, { 0.7, -35 }, { 1.1, 86, "in2" }, { 1.45, 82 }, { 2.25, 82 },
			{ 2.75, 38 }, { 3.25, 0, "out2" } },
		down = { { 0, 0 }, { 0.56, 0 }, { 0.85, 0.25 }, { 1.1, 1, "in2" }, { 2.25, 1 }, { 2.75, 0.53 }, { 3.25, 0, "out2" } },
		roll = { { 0.56, 0 }, { 0.8, -40 }, { 1.1, 12 }, { 1.45, 0 } },
		neck = { { 0, 0 }, { 0.12, -20, "snap" }, { 0.56, -25 }, { 0.62, 35, "snap" }, { 0.9, -20 }, { 1.1, -50 }, { 1.45, -62 },
			{ 2.25, -62 }, { 2.75, -15 }, { 3.25, 0 } },
		neckRoll = { { 0.56, 0 }, { 0.62, -30 }, { 0.9, 20 }, { 1.45, 0 } },
		rSwing = { { 0, 0 }, { 0.12, 85, "snap" }, { 0.5, 110 }, { 0.62, 150 }, { 0.9, 60 }, { 1.1, 170 }, { 1.45, 167 },
			{ 2.25, 167 }, { 2.75, 35 }, { 3.25, 0 } },
		lSwing = { { 0, 0 }, { 0.14, 70, "snap" }, { 0.5, 100 }, { 0.62, 40 }, { 0.9, 140 }, { 1.1, 165 }, { 1.45, 167 },
			{ 2.25, 167 }, { 2.75, 45 }, { 3.25, 0 } },
		rOut = { { 0, 0 }, { 0.12, 20 }, { 0.62, 45 }, { 1.1, 20 }, { 2.25, 20 }, { 2.75, 10 }, { 3.25, 0 } },
		lOut = { { 0, 0 }, { 0.14, 18 }, { 0.62, 40 }, { 1.1, 20 }, { 2.25, 20 }, { 2.75, 10 }, { 3.25, 0 } },
		rHip = { { 0, 0 }, { 0.56, 0 }, { 0.7, 45 }, { 0.9, -20 }, { 1.1, 10 }, { 1.45, -9 }, { 2.25, -9 }, { 2.75, 55 }, { 3.25, 0 } },
		lHip = { { 0, 0 }, { 0.56, 0 }, { 0.7, -25 }, { 0.9, 35 }, { 1.1, -15 }, { 1.45, -9 }, { 2.25, -9 }, { 2.75, 20 }, { 3.25, 0 } },
		rHipOut = { { 0, 0 }, { 0.8, 20 }, { 1.45, 7 }, { 2.25, 7 }, { 2.75, 6 }, { 3.25, 0 } },
		lHipOut = { { 0, 0 }, { 0.8, 20 }, { 1.45, 7 }, { 2.25, 7 }, { 2.75, 6 }, { 3.25, 0 } },
		flail = { { 0, 0 }, { 0.56, 0.3 }, { 0.62, 1 }, { 1.05, 1 }, { 1.1, 0.2 }, { 1.45, 0.3 }, { 2.1, 0.3 }, { 2.25, 0 } },
		kick = { { 0.56, 0 }, { 0.62, 1 }, { 1.05, 1 }, { 1.1, 0 } },
		struggle = { { 1.45, 0 }, { 1.6, 0.7 }, { 2.1, 0.5 }, { 2.25, 0 } },
	},
	crawler = {
		bx = { { 0, 0 }, { 0.4, -0.45 }, { 0.56, 0.7, "in2" }, { 1.0, 0.3 }, { 1.3, 0 }, { 2.6, 0.6 }, { 3.6, 0 } },
		by = { { 0, 0 }, { 0.4, 0.25 }, { 1.0, -0.35 }, { 1.3, 0 } },
		rear = { { 0, 0 }, { 0.4, 36, "out2" }, { 0.56, 30 }, { 0.75, 12 }, { 1.0, -6, "in2" }, { 1.25, 0 } },
		yaw = { { 0, 0 }, { 0.4, -20, "out2" }, { 0.56, 24, "out2" }, { 0.9, 6 }, { 1.3, 0 } },
		roll = { { 0, 0 }, { 0.4, 10 }, { 0.56, -14 }, { 0.9, 0 } },
		swipe = { { 0, 0 }, { 0.42, 0.35, "out2" }, { 0.56, 0.6, "in2" }, { 0.68, 1, "out2" }, { 1.3, 1 } },
		swipeW = { { 0, 0 }, { 0.22, 1, "out2" }, { 0.95, 1 }, { 1.3, 0 } },
		jaw = { { 0, 0.3 }, { 0.4, 0.95 }, { 0.56, 1.0 }, { 0.9, 0.6 }, { 1.5, 0.4 }, { 2.2, 0.8 }, { 2.5, 0.3 }, { 3.0, 0.6 }, { 3.6, 0.3 } },
		shake = { { 0, 0 }, { 0.3, 0.7 }, { 0.6, 0 }, { 2.2, 0.5 }, { 2.5, 0 } },
		headRoll = { { 0, 0 }, { 1.3, 0 }, { 1.8, 45 }, { 2.4, -30 }, { 3.0, 20 }, { 3.5, 0 } },
	},
	events = {
		{ 0, "sound", "Lunge", "head" }, { 0, "sound", "Stinger", "local" }, { 0, "sound", "Heartbeat", "local" },
		{ 0.3, "sound", "Screech", "head", 0.8, 1.3 },
		{ 0.45, "sound", "Whoosh", "victim" },
		{ 0.56, "sound", "Hit", "victim" }, { 0.56, "sound", "Crunch", "victim" }, { 0.56, "kick", 1.5 }, { 0.56, "flash", 0.9 },
		{ 1.1, "sound", "Slam", "victim" }, { 1.1, "kick", 1.1 },
		{ 1.3, "sound", "FootStep", "victim", 0.8, 0.8 },
		{ 1.8, "sound", "Chatter", "head" }, { 2.4, "sound", "BoneCrack", "head" }, { 2.9, "sound", "Growl", "head" },
	},
	fov = { { 0, 70 }, { 0.4, 60 }, { 0.56, 78, "snap" }, { 1.1, 66 }, { 1.6, 60 }, { 3.0, 70 } },
	cam = { { 0, 1 }, { 2.7, 1 }, { 3.35, 0 } },
}

-- grabbed, slammed on your back, hauled up and spun round, slammed face down,
-- pinned, and it screams into your face until you black out
Shared.CATCHES.Finisher = {
	length = 4.6, resume = 5.6, hits = {}, lethal = true, beyond = 1.0,
	backoff = { 4.25, 4.85, 3 },
	victim = {
		x = { { 0, 0 }, { 0.28, -0.3, "out2" }, { 0.72, -1.0 }, { 0.95, 0.5, "in2" }, { 1.2, 0.3 }, { 1.5, -0.6 }, { 1.78, 0.7, "in2" } },
		y = { { 0, 0 }, { 0.28, 0.2, "out2" }, { 0.72, 2.2, "out3" }, { 0.82, 2.3 }, { 0.95, 0, "in3" }, { 1.03, 0.15, "out2" },
			{ 1.1, 0, "in2" }, { 1.2, 0.4 }, { 1.5, 2.6, "out3" }, { 1.6, 2.7 }, { 1.78, 0, "in3" }, { 1.88, 0.2, "out2" }, { 1.98, 0, "in2" } },
		yaw = { { 0, 0 }, { 1.1, 0 }, { 1.5, 170 }, { 1.78, 180 } },
		lean = { { 0, 0 }, { 0.28, 14, "out2" }, { 0.72, -10 }, { 0.82, -20 }, { 0.95, -84, "in2" }, { 1.1, -80 }, { 1.2, -60 },
			{ 1.5, -8 }, { 1.6, -14 }, { 1.78, 86, "in2" }, { 2.0, 82 } },
		down = { { 0, 0 }, { 0.82, 0 }, { 0.95, 1, "in3" }, { 1.1, 1 }, { 1.35, 0.3 }, { 1.5, 0 }, { 1.6, 0 }, { 1.78, 1, "in3" } },
		roll = { { 0, 0 }, { 0.4, 8 }, { 0.72, -6 }, { 1.3, 15 }, { 1.6, -10 }, { 1.78, 0 } },
		neck = { { 0, 0 }, { 0.15, 22, "snap" }, { 0.72, -10 }, { 0.95, -45, "in2" }, { 1.03, 30 }, { 1.3, -20 }, { 1.6, -30 },
			{ 1.78, 20, "in2" }, { 1.9, -50 }, { 2.3, -40 }, { 4.2, -45 }, { 4.6, -62 } },
		neckRoll = { { 0, 0 }, { 1.78, 0 }, { 2.0, -35 }, { 2.4, -70 }, { 4.2, -70 }, { 4.6, 0 } },
		rSwing = { { 0, 0 }, { 0.12, 75, "snap" }, { 0.3, 95 }, { 0.72, 120 }, { 0.95, 150, "in2" }, { 1.2, 100 }, { 1.5, 130 },
			{ 1.78, 170, "in2" }, { 2.3, 160 }, { 4.2, 165 }, { 4.6, 167 } },
		lSwing = { { 0, 0 }, { 0.14, 60, "snap" }, { 0.3, 100 }, { 0.72, 105 }, { 0.95, 160, "in2" }, { 1.2, 90 }, { 1.5, 120 },
			{ 1.78, 175, "in2" }, { 2.3, 150 }, { 4.2, 160 }, { 4.6, 167 } },
		rOut = { { 0, 0 }, { 0.12, 25 }, { 0.72, 35 }, { 0.95, 60 }, { 1.3, 40 }, { 1.78, 45 }, { 2.3, 30 }, { 4.6, 20 } },
		lOut = { { 0, 0 }, { 0.14, 20 }, { 0.72, 30 }, { 0.95, 55 }, { 1.3, 38 }, { 1.78, 45 }, { 2.3, 30 }, { 4.6, 20 } },
		rHip = { { 0, 0 }, { 0.3, 10 }, { 0.72, 25 }, { 0.95, 55, "in2" }, { 1.1, 10 }, { 1.5, 20 }, { 1.78, -30, "in2" },
			{ 1.95, -5 }, { 2.3, -9 } },
		lHip = { { 0, 0 }, { 0.3, -8 }, { 0.72, -12 }, { 0.95, 40, "in2" }, { 1.1, 4 }, { 1.5, -15 }, { 1.78, -25, "in2" },
			{ 1.95, -12 }, { 2.3, -9 } },
		rHipOut = { { 0, 0 }, { 0.95, 14 }, { 1.5, 10 }, { 1.78, 15 }, { 2.3, 7 } },
		lHipOut = { { 0, 0 }, { 0.95, 14 }, { 1.5, 10 }, { 1.78, 15 }, { 2.3, 7 } },
		flail = { { 0, 0 }, { 0.3, 0.6 }, { 0.4, 1 }, { 0.9, 1 }, { 0.95, 0.2 }, { 1.2, 1 }, { 1.75, 1 }, { 1.78, 0.2 }, { 2.3, 0.5 },
			{ 3.0, 0.35 }, { 4.2, 0.2 }, { 4.6, 0 } },
		kick = { { 0, 0 }, { 0.35, 1 }, { 0.9, 1 }, { 0.95, 0 }, { 1.2, 1 }, { 1.75, 1 }, { 1.78, 0 }, { 2.3, 0.6 }, { 4.2, 0.3 }, { 4.6, 0 } },
		struggle = { { 1.9, 0 }, { 2.2, 0.6 }, { 4.2, 0.4 }, { 4.6, 0 } },
	},
	crawler = {
		bx = { { 0, 0 }, { 0.15, 0.75, "out2" }, { 0.3, 0.35 }, { 0.72, -0.35 }, { 0.95, 1.0, "in2" }, { 1.2, 0.7 }, { 1.5, -0.3 },
			{ 1.78, 1.3, "in2" }, { 2.3, 2.2 }, { 2.9, 2.5 }, { 4.2, 2.4 }, { 4.6, 0.6 } },
		by = { { 0, 0 }, { 0.15, -0.35 }, { 0.3, -0.1 }, { 0.72, 0.45 }, { 0.95, -0.45, "in2" }, { 1.2, -0.2 }, { 1.5, 0.5 },
			{ 1.78, -0.55, "in2" }, { 2.3, -0.3 }, { 2.9, -0.8 }, { 4.2, -0.8 }, { 4.6, 0 } },
		rear = { { 0, 0 }, { 0.15, -6 }, { 0.3, 6 }, { 0.72, 50, "out2" }, { 0.82, 54 }, { 0.95, -8, "in2" }, { 1.2, 10 },
			{ 1.5, 60, "out2" }, { 1.6, 62 }, { 1.78, -14, "in2" }, { 2.3, -12 }, { 2.9, -20 }, { 4.2, -18 }, { 4.6, 0 } },
		roll = { { 0, 0 }, { 0.72, -6 }, { 0.95, 4 }, { 1.5, -8 }, { 1.78, 6 }, { 2.3, 0 }, { 2.9, 8 }, { 4.2, 4 }, { 4.6, 0 } },
		yaw = { { 0, 0 }, { 1.5, 8 }, { 1.78, -4 }, { 2.3, 0 } },
		hold = { { 0, 0 }, { 0.2, 0 }, { 0.3, 1, "out2" }, { 4.2, 1 }, { 4.45, 0 } },
		pin = { { 0, 0 }, { 0.88, 0 }, { 0.98, 1 }, { 1.15, 0.3 }, { 1.3, 0 }, { 1.72, 0 }, { 1.85, 1 } },
		jaw = { { 0, 0.25 }, { 0.15, 0.95, "out2" }, { 0.4, 0.5 }, { 0.62, 1.0 }, { 0.9, 1.05 }, { 0.97, 0.55 }, { 1.3, 1.0 },
			{ 1.6, 1.05 }, { 1.8, 0.5 }, { 2.3, 0.1 }, { 2.6, 0.25 }, { 2.85, 0.35 }, { 3.0, 1.45, "snap" }, { 4.1, 1.4 },
			{ 4.3, 0.4 }, { 4.6, 0.3 } },
		shake = { { 0, 0 }, { 0.55, 0 }, { 0.62, 1 }, { 0.9, 0.7 }, { 1.0, 0 }, { 1.3, 0.8 }, { 1.6, 0.5 }, { 1.75, 0 }, { 2.95, 0 },
			{ 3.0, 1.3 }, { 4.1, 1.2 }, { 4.2, 0 } },
		headRoll = { { 0, 0 }, { 2.3, 0 }, { 2.75, 75 }, { 4.2, 75 }, { 4.5, 0 } },
		headPitch = { { 0, 0 }, { 2.3, 0 }, { 2.75, -10 }, { 4.2, -10 }, { 4.5, 0 } },
	},
	events = {
		{ 0, "sound", "Lunge", "head" }, { 0, "sound", "Stinger", "local" }, { 0, "sound", "Heartbeat", "local" },
		{ 0, "kick", 0.5 },
		{ 0.3, "sound", "Grab", "victim" }, { 0.3, "kick", 0.6 },
		{ 0.5, "sound", "Screech", "head", 1, 1.25 },
		{ 0.95, "sound", "Slam", "victim" }, { 0.95, "sound", "Crunch", "victim" }, { 0.95, "kick", 1.4 }, { 0.95, "flash", 0.6 },
		{ 1.3, "sound", "Screech", "head", 0.7, 1.4 },
		{ 1.78, "sound", "Slam", "victim", 1.6 }, { 1.78, "sound", "Crunch", "victim", 1.2 },
		{ 1.82, "sound", "BoneCrack", "victim" }, { 1.78, "kick", 2 }, { 1.78, "flash", 1 },
		{ 2.3, "sound", "Growl", "head" }, { 2.6, "sound", "Chatter", "head" }, { 2.75, "sound", "BoneCrack", "head" },
		{ 3.0, "sound", "FaceScream", "head" }, { 3.0, "kick", 1.2 }, { 3.0, "flash", 0.5 },
		{ 4.3, "sound", "Lunge", "head", 0.5, 0.9 },
	},
	fov = { { 0, 70 }, { 0.3, 62 }, { 0.9, 55 }, { 0.95, 72, "snap" }, { 1.5, 58 }, { 1.78, 75, "snap" }, { 2.3, 58 },
		{ 2.95, 52 }, { 3.0, 42, "snap" }, { 4.1, 44 }, { 4.6, 70 } },
	cam = { { 0, 1 }, { 4.3, 1 }, { 4.6, 0 } },
}

-- in a vent: you're crawling away from it, it drags you back by your legs,
-- pounds you into the duct floor and bites at your back
Shared.CATCHES.VentMaul = {
	length = 2.4, resume = 3.4, hits = { 0.66 }, lethal = false, beyond = 0, vent = true,
	backoff = { 1.9, 2.5, 2 },
	victim = {
		x = { { 0, 0 }, { 0.3, -0.9, "out2" } },
		y = { { 0, 0 }, { 0.55, 0.35, "out2" }, { 0.66, 0, "in3" }, { 0.9, 0.3, "out2" }, { 1.0, 0, "in3" } },
		yaw = { { 0, 180 } }, lean = { { 0, 82 } }, down = { { 0, 1 } },
		roll = { { 0, 0 }, { 0.66, -8 }, { 1.0, 8 }, { 1.3, 0 } },
		neck = { { 0, -62 }, { 0.3, -40 }, { 0.66, -20, "in2" }, { 0.75, -50 }, { 1.0, -15 }, { 1.1, -50 }, { 2.4, -62 } },
		neckRoll = { { 0, 0 }, { 0.3, -60 }, { 2.0, -60 }, { 2.4, 0 } },
		rSwing = { { 0, 167 }, { 0.3, 150 }, { 0.66, 175 }, { 1.0, 160 }, { 2.4, 167 } },
		lSwing = { { 0, 167 }, { 0.3, 160 }, { 0.66, 150 }, { 1.0, 172 }, { 2.4, 167 } },
		rOut = { { 0, 20 } }, lOut = { { 0, 20 } },
		rHip = { { 0, -9 }, { 0.3, 10 }, { 0.66, -20 }, { 1.0, 15 }, { 2.4, -9 } },
		lHip = { { 0, -9 }, { 0.3, -15 }, { 0.66, 12 }, { 1.0, -18 }, { 2.4, -9 } },
		rHipOut = { { 0, 7 } }, lHipOut = { { 0, 7 } },
		flail = { { 0, 0.5 }, { 0.3, 1 }, { 1.2, 1 }, { 2.2, 0.3 }, { 2.4, 0 } },
		kick = { { 0, 0.5 }, { 0.3, 1 }, { 1.2, 0.8 }, { 2.4, 0 } },
	},
	crawler = {
		bx = { { 0, 0 }, { 0.18, 0.9, "out2" }, { 0.3, 0.3 }, { 0.55, 0.5 }, { 0.66, 0.9, "in2" }, { 0.9, 0.5 }, { 1.0, 0.95, "in2" },
			{ 1.3, 1.3 }, { 1.5, 1.0 }, { 2.0, 0.4 }, { 2.5, 0 } },
		pitch = { { 0, 0 }, { 0.55, -6 }, { 0.66, 6 }, { 0.9, -6 }, { 1.0, 8 }, { 1.3, 0 } },
		roll = { { 0, 0 }, { 0.66, -8 }, { 1.0, 8 }, { 1.3, 0 } },
		hold = { { 0, 0 }, { 0.15, 0 }, { 0.25, 1 }, { 1.6, 1 }, { 1.9, 0 } },
		pin = { { 0, 1 } },
		jaw = { { 0, 0.3 }, { 0.15, 1.0 }, { 0.4, 0.5 }, { 1.2, 0.9 }, { 1.3, 0.1, "snap" }, { 1.45, 0.8 }, { 1.6, 0.2 }, { 2.5, 0.3 } },
		shake = { { 0, 0 }, { 0.15, 0.8 }, { 0.4, 0 }, { 1.2, 0.6 }, { 1.5, 0 } },
	},
	events = {
		{ 0, "sound", "Lunge", "head" }, { 0, "sound", "Stinger", "local" }, { 0, "sound", "Heartbeat", "local" },
		{ 0, "kick", 0.6 }, { 0.3, "sound", "Grab", "victim" },
		{ 0.66, "sound", "VentStep", "victim", 1.4, 0.8 }, { 0.66, "sound", "Slam", "victim", 0.9 }, { 0.66, "kick", 1.2 },
		{ 0.66, "flash", 0.7 },
		{ 1.0, "sound", "VentStep", "victim", 1.4, 0.75 }, { 1.0, "kick", 1 },
		{ 1.3, "sound", "Hit", "victim" }, { 1.3, "sound", "Crunch", "victim" }, { 1.3, "kick", 0.8 },
		{ 1.6, "sound", "Growl", "head" }, { 2.0, "sound", "BoneCrack", "head" },
	},
	fov = { { 0, 70 }, { 0.3, 60 }, { 0.66, 74, "snap" }, { 1.0, 72, "snap" }, { 1.4, 60 }, { 2.4, 70 } },
	cam = { { 0, 1 }, { 1.9, 1 }, { 2.4, 0 } },
}

-- in a vent, the finisher: dragged back, pounded three times, it crawls up
-- your back and screams into your face
Shared.CATCHES.VentFinisher = {
	length = 3.8, resume = 4.6, hits = {}, lethal = true, beyond = 0, vent = true,
	backoff = { 3.45, 4.05, 2.5 },
	victim = {
		x = { { 0, 0 }, { 0.3, -0.9, "out2" } },
		y = { { 0, 0 }, { 0.55, 0.35, "out2" }, { 0.66, 0, "in3" }, { 0.9, 0.35, "out2" }, { 1.0, 0, "in3" }, { 1.25, 0.45, "out2" },
			{ 1.35, 0, "in3" } },
		yaw = { { 0, 180 } }, lean = { { 0, 82 } }, down = { { 0, 1 } },
		roll = { { 0, 0 }, { 0.66, -8 }, { 1.0, 8 }, { 1.35, -10 }, { 1.6, 0 } },
		neck = { { 0, -62 }, { 0.3, -40 }, { 0.66, -20, "in2" }, { 0.75, -50 }, { 1.0, -15 }, { 1.1, -50 }, { 1.35, -10 },
			{ 1.5, -45 }, { 3.4, -45 }, { 3.8, -62 } },
		neckRoll = { { 0, 0 }, { 0.3, -60 }, { 1.5, -70 }, { 3.4, -70 }, { 3.8, 0 } },
		rSwing = { { 0, 167 }, { 0.3, 150 }, { 0.66, 175 }, { 1.0, 160 }, { 1.35, 178 }, { 3.8, 167 } },
		lSwing = { { 0, 167 }, { 0.3, 160 }, { 0.66, 150 }, { 1.0, 172 }, { 1.35, 150 }, { 3.8, 167 } },
		rOut = { { 0, 20 } }, lOut = { { 0, 20 } },
		rHip = { { 0, -9 }, { 0.3, 10 }, { 0.66, -20 }, { 1.0, 15 }, { 1.35, -20 }, { 1.7, -9 } },
		lHip = { { 0, -9 }, { 0.3, -15 }, { 0.66, 12 }, { 1.0, -18 }, { 1.35, 10 }, { 1.7, -9 } },
		rHipOut = { { 0, 7 } }, lHipOut = { { 0, 7 } },
		flail = { { 0, 0.5 }, { 0.3, 1 }, { 1.3, 1 }, { 1.5, 0.4 }, { 3.4, 0.2 }, { 3.8, 0 } },
		kick = { { 0, 0.5 }, { 0.3, 1 }, { 1.3, 0.8 }, { 1.5, 0.3 }, { 3.8, 0 } },
		struggle = { { 1.4, 0 }, { 1.6, 0.4 }, { 3.4, 0.3 }, { 3.8, 0 } },
	},
	crawler = {
		bx = { { 0, 0 }, { 0.18, 0.9, "out2" }, { 0.3, 0.3 }, { 0.55, 0.5 }, { 0.66, 0.9, "in2" }, { 0.9, 0.5 }, { 1.0, 0.95, "in2" },
			{ 1.25, 0.6 }, { 1.35, 1.1, "in2" }, { 1.9, 2.2 }, { 3.4, 2.3 }, { 3.8, 0.6 } },
		pitch = { { 0, 0 }, { 0.55, -6 }, { 0.66, 6 }, { 0.9, -6 }, { 1.0, 8 }, { 1.25, -8 }, { 1.35, 10 }, { 1.7, 0 } },
		roll = { { 0, 0 }, { 0.66, -8 }, { 1.0, 8 }, { 1.35, -10 }, { 1.7, 0 } },
		hold = { { 0, 0 }, { 0.15, 0 }, { 0.25, 1 }, { 3.4, 1 }, { 3.65, 0 } },
		pin = { { 0, 1 } },
		jaw = { { 0, 0.3 }, { 0.15, 1.0 }, { 0.4, 0.5 }, { 1.35, 0.6 }, { 1.9, 0.15 }, { 2.15, 0.35 }, { 2.3, 1.45, "snap" },
			{ 3.35, 1.4 }, { 3.5, 0.4 }, { 3.8, 0.3 } },
		shake = { { 0, 0 }, { 0.15, 0.8 }, { 0.4, 0 }, { 2.25, 0 }, { 2.3, 1.3 }, { 3.35, 1.2 }, { 3.45, 0 } },
		headRoll = { { 0, 0 }, { 1.6, 0 }, { 2.0, 75 }, { 3.4, 75 }, { 3.7, 0 } },
	},
	events = {
		{ 0, "sound", "Lunge", "head" }, { 0, "sound", "Stinger", "local" }, { 0, "sound", "Heartbeat", "local" },
		{ 0, "kick", 0.6 }, { 0.3, "sound", "Grab", "victim" },
		{ 0.66, "sound", "VentStep", "victim", 1.4, 0.8 }, { 0.66, "sound", "Slam", "victim", 0.9 }, { 0.66, "kick", 1.2 },
		{ 0.66, "flash", 0.6 },
		{ 1.0, "sound", "VentStep", "victim", 1.4, 0.75 }, { 1.0, "kick", 1 },
		{ 1.35, "sound", "VentStep", "victim", 1.6, 0.7 }, { 1.35, "sound", "Slam", "victim", 1.3 },
		{ 1.35, "sound", "Crunch", "victim", 1.2 }, { 1.35, "kick", 1.8 }, { 1.35, "flash", 1 },
		{ 1.7, "sound", "Growl", "head" }, { 2.0, "sound", "BoneCrack", "head" },
		{ 2.3, "sound", "FaceScream", "head" }, { 2.3, "kick", 1.2 }, { 2.3, "flash", 0.5 },
		{ 3.5, "sound", "Lunge", "head", 0.5, 0.9 },
	},
	fov = { { 0, 70 }, { 0.3, 60 }, { 0.66, 74, "snap" }, { 1.0, 72, "snap" }, { 1.35, 78, "snap" }, { 1.9, 55 },
		{ 2.3, 42, "snap" }, { 3.35, 44 }, { 3.8, 70 } },
	cam = { { 0, 1 }, { 3.5, 1 }, { 3.8, 0 } },
}

local VICTIM_DEFAULT = { x = 0, z = 0, y = 0, yaw = 0, lean = 0, roll = 0, twist = 0, down = 0, neck = 0, neckRoll = 0,
	rSwing = 0, rOut = 0, lSwing = 0, lOut = 0, rHip = 0, rHipOut = 0, lHip = 0, lHipOut = 0, flail = 0, kick = 0, struggle = 0 }
Shared.CRAWLER_FIELDS = { "bx", "by", "rear", "pitch", "yaw", "roll", "hold", "pin", "swipe", "swipeW", "jaw", "shake",
	"headYaw", "headPitch", "headRoll" }

-- How much room the catch has, from what the server measured.
--   env = { hold, standY, clear (floor to ceiling), back (free floor behind you) }
function Shared.catchRoom(kind, env)
	local def = Shared.CATCHES[kind]
	local lift = clamp((env.clear - (env.standY + 2.6)) / 2.4, 0.12, 1)
	local rear = clamp((env.clear - 4.3) / 3.5, 0.2, 1)
	local beyond = 1
	if def.beyond > 0 then
		beyond = clamp((env.back - 1.8) / def.beyond, 0.15, 1)
	end
	return lift, rear, beyond
end

-- The victim's channels at time t. Fills `v` (and v.drop, in studs).
function Shared.sampleVictim(kind, t, env, v)
	local def = Shared.CATCHES[kind]
	for _, f in ipairs(Shared.VICTIM_FIELDS) do
		local track = def.victim[f]
		v[f] = track and Shared.sample(track, t) or VICTIM_DEFAULT[f]
	end
	local lift, _, beyond = Shared.catchRoom(kind, env)
	if v.y > 0 then
		v.y *= lift
	end
	if v.x > 0 then
		v.x *= beyond
	end
	v.x += env.hold
	v.z *= beyond
	v.drop = v.down * math.max(env.standY - 0.65, 0)
	return v
end

function Shared.sampleCrawler(kind, t, env, c)
	local def = Shared.CATCHES[kind]
	for _, f in ipairs(Shared.CRAWLER_FIELDS) do
		local track = def.crawler[f]
		c[f] = track and Shared.sample(track, t) or 0
	end
	local _, rear, beyond = Shared.catchRoom(kind, env)
	if c.rear > 0 then
		c.rear *= rear
	end
	if c.by > 0 then
		c.by *= rear
	end
	if c.bx > 1.2 then
		-- it follows you as far as you were thrown
		c.bx = 1.2 + (c.bx - 1.2) * beyond
	end
	return c
end

-- Where the caught player's root part is at the end (the server puts it there).
function Shared.victimEndCFrame(kind, frame, env)
	local def = Shared.CATCHES[kind]
	local v = Shared.sampleVictim(kind, def.length, env, {})
	return Shared.victimRoot(frame, v), v
end

return Shared
