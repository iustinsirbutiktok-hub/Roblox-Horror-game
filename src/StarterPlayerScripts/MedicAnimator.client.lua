-- MedicAnimator
-- Place in: StarterPlayer > StarterPlayerScripts (a LocalScript named "MedicAnimator")
--
-- Brings every imported Medic in Workspace to life on your screen (any Model
-- named "TheMedic", or with a "Medic" attribute set to true). It moves the
-- skeleton's Bones every frame with MedicPose (ReplicatedStorage):
-- the hunch, the breathing, the puppet-string jerks, the head snapping round
-- to the nearest player, the slow reach when you get close, the walk.
--
-- Patrol test: tick the model's "Patrol" attribute (MedicSetup adds it) and it
-- stalks back and forth in front of where you placed it (PatrolDistance studs,
-- PatrolSpeed studs/second), stopping dead now and then. That walk is only on
-- each player's own screen - it's for seeing the animation, not real AI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MedicPose = require(ReplicatedStorage:WaitForChild("MedicPose"))

local UP = Vector3.new(0, 1, 0)
local LOOK_RANGE = 60         -- notices you this far away
local REACH_FAR, REACH_NEAR = 12, 4   -- starts reaching at 12 studs, fully at 4

local medics = {}

local function isMedic(model)
	return model:IsA("Model") and (model.Name == "TheMedic" or model:GetAttribute("Medic") == true)
end

local function setup(model)
	if medics[model] then
		return
	end
	local bones = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Bone") then
			bones[d.Name] = d
		end
	end
	if not (bones.Root and bones["UpperArm.L"] and bones["UpperArm.R"]) then
		return
	end
	local root = model.PrimaryPart
	if not root then
		local node = bones.Root.Parent
		while node and not node:IsA("BasePart") do
			node = node.Parent
		end
		root = node or model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not root then
		return
	end

	-- the model's own frame, worked out from its bones: X = its right, Y = up,
	-- Z = behind it (so it doesn't matter which way the importer turned it)
	local right = bones["UpperArm.R"].WorldPosition - bones["UpperArm.L"].WorldPosition
	right = Vector3.new(right.X, 0, right.Z).Unit
	-- (its origin on the floor under its hips)
	local box, size = model:GetBoundingBox()
	local hips = bones.Root.WorldPosition
	local frame = CFrame.fromMatrix(Vector3.new(hips.X, box.Position.Y - size.Y / 2, hips.Z), right, UP)
	local inverse = frame:Inverse()
	local rest, pos = {}, {}
	for name, bone in pairs(bones) do
		local cf = inverse * bone.WorldCFrame
		rest[bone] = cf.Rotation
		pos[name] = cf.Position
	end

	local m = {
		model = model, root = root, bones = bones, rest = rest,
		offset = root.CFrame:ToObjectSpace(frame),
		pose = MedicPose.new({ pos = pos }, (frame.Position.X * 0.37 + frame.Position.Z * 0.71) % 50),
		lastPos = nil, speed = 0, frameCount = 0, accum = 0,
		home = model:GetPivot(), homeFrame = frame,
		walked = 0, dir = 1, turn = 0, turning = 0,
	}
	medics[model] = m
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			medics[model] = nil
		end
	end)
end

for _, d in ipairs(workspace:GetDescendants()) do
	if isMedic(d) then
		task.defer(setup, d)
	end
end
workspace.DescendantAdded:Connect(function(d)
	if isMedic(d) then
		task.delay(0.5, setup, d)      -- (let the rest of it stream in)
	end
end)

-- the patrol test: out and back along the way it faces, stalling and lurching
local function patrol(m, dt, now)
	local model = m.model
	if model:GetAttribute("Patrol") ~= true then
		return
	end
	local distance = model:GetAttribute("PatrolDistance") or 16
	local speed = model:GetAttribute("PatrolSpeed") or 3
	if m.turning > 0 then
		-- turning round, slowly, on the spot
		local step = math.min(dt, m.turning)
		m.turning -= step
		m.turn += math.pi * step / 1.8
	else
		local stall = math.noise(now * 0.33, m.pose.seed) > 0.32 and 0 or 1      -- stops dead
		local lurch = math.noise(now * 0.9, m.pose.seed + 4) > 0.45 and 1.9 or 1   -- a sudden lunge forward
		m.walked += m.dir * speed * stall * lurch * dt
		if m.walked >= distance or m.walked <= 0 then
			m.walked = math.clamp(m.walked, 0, distance)
			m.dir = -m.dir
			m.turning = 1.8
		end
	end
	local f = m.homeFrame
	local at = f.Position + f.LookVector * m.walked
	local turned = CFrame.new(at) * CFrame.Angles(0, m.turn, 0) * CFrame.new(-f.Position)
	model:PivotTo(turned * m.home)
end

local function nearestPlayer(frame)
	local best, bestD = nil, LOOK_RANGE
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		local head = character and character:FindFirstChild("Head")
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if head and hum and hum.Health > 0 and not character:GetAttribute("IsHiding") then
			local d = (head.Position - frame.Position).Magnitude
			if d < bestD then
				best, bestD = head, d
			end
		end
	end
	return best, bestD
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	for model, m in pairs(medics) do
		if not m.root.Parent then
			medics[model] = nil
			continue
		end
		patrol(m, dt, now)
		local frame = m.root.CFrame * m.offset

		-- how fast it's going (forward)
		if m.lastPos then
			local v = (frame.Position - m.lastPos) / math.max(dt, 1 / 240)
			m.speed += (v:Dot(frame.LookVector) - m.speed) * math.min(dt * 8, 1)
		end
		m.lastPos = frame.Position

		-- far away: every third frame is plenty
		m.accum += dt
		m.frameCount += 1
		local far = camera and (camera.CFrame.Position - frame.Position).Magnitude > 150
		if far and m.frameCount % 3 ~= 0 then
			continue
		end

		local head, distance = nearestPlayer(frame)
		local target, near = nil, 0
		if head then
			target = frame:PointToObjectSpace(head.Position)
			near = math.clamp((REACH_FAR - distance) / (REACH_FAR - REACH_NEAR), 0, 1)
		end
		local out = m.pose:update({ dt = m.accum, t = now, speed = math.max(m.speed, 0), target = target, near = near })
		m.accum = 0
		for name, cf in pairs(out) do
			local bone = m.bones[name]
			if bone then
				local q = m.rest[bone]
				bone.Transform = q:Inverse() * cf * q
			end
		end
	end
end)
