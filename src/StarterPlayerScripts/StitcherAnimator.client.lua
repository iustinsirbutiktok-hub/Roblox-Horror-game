-- StitcherAnimator
-- Place in: StarterPlayer > StarterPlayerScripts (a LocalScript named "StitcherAnimator")
--
-- Brings every imported Stitcher in Workspace to life on your screen (any Model
-- named "TheStitcher", or with a "Stitcher" attribute set to true). Every frame
-- it moves the skeleton's ~180 Bones with StitcherPose (ReplicatedStorage):
-- the hunch and the lolling head, the breathing ribs, the twitches, the
-- scissors, the head snapping round to the nearest player, the reach, the
-- walk and the run, and the hair and cloth swinging.
--
-- Your AI (a server Script) drives it with attributes on the model:
--   Aggro         number 0..1   how worked up it is (it also gets worked up by itself when you're close)
--   Attack        any value     change it (e.g. add 1) and it rears up and lunges with the scissors
--   TargetUserId  number        stare at this player instead of the nearest one
--   Procedural    bool          untick to let your own Animation Editor animations play instead
-- Just move the model (PivotTo / CFrame its root part) and it walks or runs at
-- the speed it's going.
--
-- Sounds (optional): put Sounds named "Snip", "Crack" and "Shriek" anywhere in
-- the model and they play on the snips, the joint cracks and the attacks.
--
-- Patrol test: tick the model's "Patrol" attribute (StitcherSetup adds it) and
-- it stalks back and forth in front of where you placed it. That walk is only
-- on each player's own screen - it's for seeing the animation, not real AI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StitcherPose = require(ReplicatedStorage:WaitForChild("StitcherPose"))

local UP = Vector3.new(0, 1, 0)
local LOOK_RANGE = 80                 -- notices you this far away
local NEAR_FAR, NEAR_CLOSE = 16, 4    -- gets worked up from 16 studs, fully at 4
local SKIP_DISTANCE = 120             -- further than this from the camera: every third frame
local SLEEP_DISTANCE = 300            -- further than this: not animated at all

local monsters = {}

local function isStitcher(model)
	return model:IsA("Model") and (model.Name == "TheStitcher" or model:GetAttribute("Stitcher") == true)
end

local function setup(model)
	if monsters[model] then
		return
	end
	-- (name -> every Bone with it, in case the importer gave more than one mesh its own copy)
	local bones, first = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Bone") then
			bones[d.Name] = bones[d.Name] or {}
			table.insert(bones[d.Name], d)
			first[d.Name] = first[d.Name] or d
		end
	end
	if not (first.Root and first["UpperArm1.L"] and first["UpperArm1.R"]) then
		warn("StitcherAnimator: " .. model:GetFullName() .. " has no Stitcher skeleton (needs Root, UpperArm1.L, UpperArm1.R)")
		return
	end
	local root = model.PrimaryPart
	if not root then
		local node = first.Root.Parent
		while node and not node:IsA("BasePart") do
			node = node.Parent
		end
		root = node or model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not root then
		return
	end

	-- the model's own frame, worked out from its bones: X = its right, Y = up,
	-- Z = behind it (so it doesn't matter which way the importer turned it),
	-- with its origin on the floor under its hips
	local right = first["UpperArm1.R"].WorldPosition - first["UpperArm1.L"].WorldPosition
	right = Vector3.new(right.X, 0, right.Z).Unit
	local box, size = model:GetBoundingBox()
	local hips = first.Root.WorldPosition
	local frame = CFrame.fromMatrix(Vector3.new(hips.X, box.Position.Y - size.Y / 2, hips.Z), right, UP)
	local inverse = frame:Inverse()
	local rest, pos, parent = {}, {}, {}
	for name, list in pairs(bones) do
		for _, bone in ipairs(list) do
			rest[bone] = (inverse * bone.WorldCFrame).Rotation
		end
		pos[name] = (inverse * first[name].WorldCFrame).Position
		local p = first[name].Parent
		if p and p:IsA("Bone") then
			parent[name] = p.Name
		end
	end
	-- every parent before its children
	local order, visited = {}, {}
	local function visit(name)
		if visited[name] then
			return
		end
		visited[name] = true
		if parent[name] then
			visit(parent[name])
		end
		table.insert(order, name)
	end
	local names = {}
	for name in pairs(first) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		visit(name)
	end

	local sounds = {}
	for _, key in ipairs({ "Snip", "Crack", "Shriek" }) do
		local s = model:FindFirstChild(key, true)
		if s and s:IsA("Sound") then
			sounds[string.lower(key)] = s
		end
	end

	local m = {
		model = model, root = root, bones = bones, rest = rest, sounds = sounds,
		offset = root.CFrame:ToObjectSpace(frame),
		pose = StitcherPose.new({ pos = pos, parent = parent, order = order },
			(frame.Position.X * 0.37 + frame.Position.Z * 0.71) % 50),
		lastPos = nil, speed = 0, frameCount = 0, accum = 0, released = false,
		home = model:GetPivot(), homeFrame = frame,
		walked = 0, dir = 1, turn = 0, turning = 0,
	}
	monsters[model] = m
	model.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			monsters[model] = nil
		end
	end)
end

for _, d in ipairs(workspace:GetDescendants()) do
	if isStitcher(d) then
		task.defer(setup, d)
	end
end
workspace.DescendantAdded:Connect(function(d)
	if isStitcher(d) then
		task.delay(0.5, setup, d)      -- (let the rest of it stream in)
	end
end)

-- the patrol test: out and back along the way it faces, stalking, stopping dead, lurching
local function patrol(m, dt, now)
	local model = m.model
	if model:GetAttribute("Patrol") ~= true then
		return
	end
	local distance = model:GetAttribute("PatrolDistance") or 18
	local speed = model:GetAttribute("PatrolSpeed") or 3
	if m.turning > 0 then
		local stepTime = math.min(dt, m.turning)
		m.turning = m.turning - stepTime
		m.turn = m.turn + math.pi * stepTime / 2.2
	else
		local stall = math.noise(now * 0.3, m.pose.seed) > 0.3 and 0 or 1            -- stops dead
		local lurch = math.noise(now * 0.9, m.pose.seed + 4) > 0.42 and 2.2 or 1     -- a sudden lunge forward
		m.walked = m.walked + m.dir * speed * stall * lurch * dt
		if m.walked >= distance or m.walked <= 0 then
			m.walked = math.clamp(m.walked, 0, distance)
			m.dir = -m.dir
			m.turning = 2.2
		end
	end
	local f = m.homeFrame
	local at = f.Position + f.LookVector * m.walked
	local turned = CFrame.new(at) * CFrame.Angles(0, m.turn, 0) * CFrame.new(-f.Position)
	model:PivotTo(turned * m.home)
end

local function headOf(player)
	local character = player and player.Character
	local head = character and character:FindFirstChild("Head")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if head and hum and hum.Health > 0 and not character:GetAttribute("IsHiding") then
		return head
	end
	return nil
end

local function targetFor(m, frame)
	local wanted = m.model:GetAttribute("TargetUserId")
	if wanted then
		local head = headOf(Players:GetPlayerByUserId(wanted))
		if head then
			return head, (head.Position - frame.Position).Magnitude
		end
	end
	local best, bestD = nil, LOOK_RANGE
	for _, p in ipairs(Players:GetPlayers()) do
		local head = headOf(p)
		if head then
			local d = (head.Position - frame.Position).Magnitude
			if d < bestD then
				best, bestD = head, d
			end
		end
	end
	return best, bestD
end

local function release(m)
	for _, list in pairs(m.bones) do
		for _, bone in ipairs(list) do
			bone.Transform = CFrame.new()
		end
	end
end

local function play(m, eventName)
	local s = m.sounds[eventName]
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	for model, m in pairs(monsters) do
		if not m.root.Parent then
			monsters[model] = nil
		elseif model:GetAttribute("Procedural") == false then
			if not m.released then
				release(m)
				m.released = true
			end
		else
			m.released = false
			patrol(m, dt, now)
			local frame = m.root.CFrame * m.offset

			-- how fast it's going (forward)
			if m.lastPos then
				local v = (frame.Position - m.lastPos) / math.max(dt, 1 / 240)
				m.speed = m.speed + (v:Dot(frame.LookVector) - m.speed) * math.min(dt * 8, 1)
			end
			m.lastPos = frame.Position

			m.accum = m.accum + dt
			m.frameCount = m.frameCount + 1
			local fromCamera = camera and (camera.CFrame.Position - frame.Position).Magnitude or 0
			local skip = fromCamera > SLEEP_DISTANCE or (fromCamera > SKIP_DISTANCE and m.frameCount % 3 ~= 0)
			if not skip then
				local head, distance = targetFor(m, frame)
				local target, near = nil, 0
				if head then
					target = frame:PointToObjectSpace(head.Position)
					near = math.clamp((NEAR_FAR - distance) / (NEAR_FAR - NEAR_CLOSE), 0, 1)
				end
				local out = m.pose:update({
					dt = m.accum, t = now, speed = math.max(m.speed, 0), target = target, near = near,
					aggro = model:GetAttribute("Aggro") or 0, attack = model:GetAttribute("Attack"), frame = frame,
				})
				m.accum = 0
				for name, cf in pairs(out) do
					local list = m.bones[name]
					if list then
						for _, bone in ipairs(list) do
							local q = m.rest[bone]
							bone.Transform = q:Inverse() * cf * q
						end
					end
				end
				for _, e in ipairs(m.pose.events) do
					play(m, e)
				end
			end
		end
	end
end)
