-- CrawlerAI
-- Place in: ServerScriptService (a Script)
--
-- Brain for Workspace.TheCrawler:
--   * re-rigs the model once so it can walk level and fit through vents
--   * prowls when it has no one: creeps, freezes, scurries, freezes again
--   * spots players by sight (or notices them when they're very close),
--     never while they're hidden
--   * shrieks when it first spots you, then bursts into a sprint
--   * chases on real pathfinding, follows you into vents
--   * catches you: a random slam or backhand that takes HIT_DAMAGE, or, if
--     that would put you down, the finisher. In a vent it drags you back and
--     mauls you instead. A finisher drops you to 0 health, so DownedSystem
--     takes over with the revive.
--
-- How it LOOKS doing all of this is StarterPlayerScripts > CrawlerAnimator,
-- which reads the attributes this script sets on the model. The settings are
-- in ReplicatedStorage > CrawlerConfig, the catch timings in CrawlerShared.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("CrawlerConfig"))
local Shared = require(ReplicatedStorage:WaitForChild("CrawlerShared"))

local UP = Vector3.new(0, 1, 0)
local WANDER_RADIUS = 70

--------------------------------------------------
-- FIND IT
--------------------------------------------------

local monster = workspace:WaitForChild(Config.MODEL_NAME)
local humanoid = monster:WaitForChild("Humanoid")
local root = monster:WaitForChild("HumanoidRootPart")
local torso = monster:WaitForChild("Torso")

local function rayParams(ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

-- every player's character, plus the monster: things rays should pass through
local function bodies(extra)
	local list = { monster }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	if extra then
		table.insert(list, extra)
	end
	return list
end

local function floorBelow(position, ignore)
	local hit = workspace:Raycast(position + UP, Vector3.new(0, -40, 0), rayParams(ignore or { monster }))
	return hit and hit.Position.Y or nil
end

--------------------------------------------------
-- SETUP: RE-RIG THE MODEL
--------------------------------------------------
-- The model was built lying along its root part's Y axis, so a Humanoid
-- would stand it up on its tail. Give it an upright, low, flat root part to
-- walk with (that's the only part that touches anything); every player's
-- screen animates the whole body on top of it.

local rootJoint = nil
for _, d in ipairs(monster:GetDescendants()) do
	if d:IsA("Motor6D") and d.Name == "RootJoint" then
		rootJoint = d
	end
end
assert(rootJoint, "TheCrawler needs its RootJoint (HumanoidRootPart -> Torso)")

local function rigOnce()
	local function pos(name)
		local part = monster:FindFirstChild(name)
		assert(part and part:IsA("BasePart"), "TheCrawler is missing its part: " .. name)
		return part.Position
	end
	local points = {
		LeftHand = pos("Left Hand"), RightHand = pos("Right Hand"),
		LeftFoot = pos("Left Foot"), RightFoot = pos("Right Foot"),
		LeftArm = pos("Left Arm"), RightArm = pos("Right Arm"),
	}
	local boxes = {}
	for _, d in ipairs(monster:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(boxes, { d.CFrame, d.Size })
		end
	end
	local floorY = floorBelow(torso.Position)
	local rootCF, rootC0, info = Shared.planRig(torso.CFrame, points, boxes, floorY, Config.ROOT_HEIGHT)

	root.Anchored = true
	for _, d in ipairs(monster:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	root.Size = Config.ROOT_SIZE
	root.CanCollide = true
	root.Massless = false
	root.RootPriority = 127
	rootJoint.C1 = CFrame.identity
	rootJoint.C0 = rootC0
	root.CFrame = rootCF

	monster:SetAttribute("RootC0", rootC0)
	monster:SetAttribute("TopAboveTorso", info.topAboveTorso)
	monster.PrimaryPart = root
	return rootCF
end

local spawnCF = rigOnce()

-- if your game uses StreamingEnabled, everyone needs the whole model at once
pcall(function()
	monster.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
end)

humanoid.RigType = Enum.HumanoidRigType.R15          -- the mode that respects HipHeight
humanoid.HipHeight = Config.ROOT_HEIGHT - Config.ROOT_SIZE.Y / 2
humanoid.WalkSpeed = Config.STALK_SPEED
humanoid.UseJumpPower = true
humanoid.JumpPower = 0
humanoid.AutoRotate = true
humanoid.BreakJointsOnDeath = false
humanoid.RequiresNeck = false
humanoid.MaxHealth = math.huge
humanoid.Health = math.huge
humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
for _, state in ipairs({ Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.GettingUp }) do
	humanoid:SetStateEnabled(state, false)
end

root.Anchored = false
root:SetNetworkOwner(nil)

local spawnPoint = spawnCF.Position

local function setState(name)
	monster:SetAttribute("State", name)
	monster:SetAttribute("StateStart", workspace:GetServerTimeNow())
end

monster:SetAttribute("Chasing", false)
monster:SetAttribute("TargetId", 0)
monster:SetAttribute("CatchVictim", 0)
setState("Move")
monster:SetAttribute("CrawlerReady", true)

--------------------------------------------------
-- SENSES
--------------------------------------------------

local graceUntil = {}      -- player -> time it can catch them again

local function alive(player)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) or hum.Health <= 0 then
		return nil
	end
	if character:GetAttribute("IsHiding") or character:GetAttribute("BeingKilled") or character:GetAttribute("Downed") then
		return nil
	end
	return character, hrp, hum
end

local function eye()
	return root.Position + root.CFrame.LookVector * 2.4 + UP * 0.5
end

local function canSee(character, hrp)
	local from = eye()
	local targetPoint = (character:FindFirstChild("Head") or hrp).Position
	local offset = targetPoint - from
	local distance = offset.Magnitude
	if distance > Config.SIGHT_RANGE then
		return false
	end
	-- it sees best straight ahead; behind it, only up close
	local facing = root.CFrame.LookVector:Dot(Shared.flat(offset))
	if facing < -0.35 and distance > 22 then
		return false
	end
	local hit = workspace:Raycast(from, offset, rayParams({ monster }))
	return hit == nil or hit.Instance:IsDescendantOf(character)
end

local function findTarget()
	local best, bestDistance = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character, hrp = alive(player)
		if character then
			local offset = hrp.Position - root.Position
			local distance = offset.Magnitude
			local close = distance <= Config.NOTICE_RANGE and math.abs(offset.Y) < 8
			if distance < bestDistance and (close or canSee(character, hrp)) then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

-- how much headroom there is above a point on the floor
local function ceilingAbove(floorPoint, ignore)
	local hit = workspace:Raycast(floorPoint + UP * 0.5, UP * 30, rayParams(ignore))
	return hit and hit.Position.Y - floorPoint.Y or 99
end

local function inVent()
	local floor = root.Position.Y - Config.ROOT_HEIGHT
	return ceilingAbove(Vector3.new(root.Position.X, floor, root.Position.Z), bodies()) < Config.VENT_CEILING
end

--------------------------------------------------
-- MOVEMENT
--------------------------------------------------

local path = PathfindingService:CreatePath({
	AgentRadius = 1.3,
	AgentHeight = 2.6,          -- it flattens itself into vents
	AgentCanJump = false,
	AgentCanClimb = false,
	WaypointSpacing = 3,
})

local waypoints = {}
local waypointIndex = 1
local busy = false

local function computePath(goal)
	local ok = pcall(function()
		path:ComputeAsync(root.Position, goal)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		waypoints = path:GetWaypoints()
		waypointIndex = 2
		return true
	end
	return false
end

local function face(point)
	local look = Shared.flat(point - root.Position)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
end

-- slide the (anchored) root part smoothly to a new CFrame
local function slide(to, duration)
	local from = root.CFrame
	local start = os.clock()
	while true do
		local a = math.clamp((os.clock() - start) / duration, 0, 1)
		a = a * a * (3 - 2 * a)
		root.CFrame = from:Lerp(to, a)
		if a >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

-- prowling: it doesn't walk, it creeps in fits and starts
local stalkSpeed = Config.STALK_SPEED
local stalkUntil = 0
local function prowlSpeed(now)
	if now >= stalkUntil then
		local r = math.random()
		if r < 0.22 then
			stalkSpeed, stalkUntil = 0, now + 0.4 + math.random() * 1.0           -- freezes
		elseif r < 0.32 then
			stalkSpeed, stalkUntil = 13, now + 0.25 + math.random() * 0.35         -- sudden scurry
		else
			stalkSpeed = Config.STALK_SPEED * (0.55 + math.random() * 0.45)        -- creeping
			stalkUntil = now + 0.7 + math.random() * 1.4
		end
	end
	return stalkSpeed
end

--------------------------------------------------
-- THE CATCH
--------------------------------------------------

local function clearCatch()
	monster:SetAttribute("CatchVictim", 0)
	monster:SetAttribute("CatchKind", "")
end

local function doCatch(player)
	local character, hrp, hum = alive(player)
	if not character then
		return false
	end
	busy = true
	waypoints = {}
	humanoid:MoveTo(root.Position)
	character:SetAttribute("BeingKilled", true)

	local ignore = bodies()
	local victimPos = hrp.Position
	local floorY = floorBelow(victimPos, ignore) or (victimPos.Y - 3)
	local standY = math.clamp(victimPos.Y - floorY, 1, 3.6)
	local floorPoint = Vector3.new(victimPos.X, floorY, victimPos.Z)
	local f = Shared.flat(victimPos - root.Position, root.CFrame.LookVector)

	-- room overhead (vent?) and free floor behind you (how far you can be thrown)
	local clear = math.min(ceilingAbove(floorPoint, ignore), ceilingAbove(floorPoint - f * Config.HOLD_DISTANCE, ignore))
	local back = 14
	for _, h in ipairs({ 0.6, 2.2 }) do
		local origin = floorPoint + UP * h
		local hit = workspace:Raycast(origin, f * 14, rayParams(ignore))
		if hit then
			back = math.min(back, (hit.Position - origin).Magnitude)
		end
	end

	local lethal = hum.Health - Config.HIT_DAMAGE <= 0
	local kind
	if clear < Config.VENT_CEILING then
		kind = lethal and "VentFinisher" or "VentMaul"
	elseif lethal then
		kind = "Finisher"
	else
		kind = math.random() < 0.5 and "Slam" or "Swipe"
	end
	local def = Shared.CATCHES[kind]

	-- where it plants itself: HOLD_DISTANCE in front of you, if that's free
	local base = floorPoint - f * Config.HOLD_DISTANCE
	local rootPos = Vector3.new(base.X, root.Position.Y, base.Z)
	local toSpot = rootPos - root.Position
	if toSpot.Magnitude > 0.05 and workspace:Raycast(root.Position, toSpot, rayParams(ignore)) then
		rootPos = root.Position                                   -- a wall's in the way: stay put
		base = Vector3.new(rootPos.X, floorY, rootPos.Z)
	end
	local env = {
		hold = (Vector3.new(victimPos.X, 0, victimPos.Z) - Vector3.new(rootPos.X, 0, rootPos.Z)).Magnitude,
		standY = standY, clear = clear, back = back,
	}
	local frame = { base = base, f = f, r = f:Cross(UP), standY = standY }

	root.Anchored = true
	hrp.Anchored = true
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = Shared.victimRoot(frame, Shared.sampleVictim(kind, 0, env, {}))

	-- your view gets dragged onto its face (CrawlerAnimator does the camera)
	local lookAt = Instance.new("ObjectValue")
	lookAt.Name = "LookAtOverride"
	lookAt.Value = monster:FindFirstChild("Head")
	lookAt.Parent = character

	local start = workspace:GetServerTimeNow() + 0.12            -- a moment for everyone to get the news
	monster:SetAttribute("CatchKind", kind)
	monster:SetAttribute("CatchStart", start)
	monster:SetAttribute("CatchBase", base)
	monster:SetAttribute("CatchDir", f)
	monster:SetAttribute("CatchStandY", standY)
	monster:SetAttribute("CatchClear", clear)
	monster:SetAttribute("CatchBack", back)
	monster:SetAttribute("CatchHold", env.hold)
	monster:SetAttribute("CatchVictim", player.UserId)
	setState("Catch")

	slide(CFrame.lookAt(rootPos, rootPos + f), 0.15)

	local function waitUntil(t)
		local remaining = start + t - workspace:GetServerTimeNow()
		if remaining > 0 then
			task.wait(remaining)
		end
	end
	local function stillThere()
		return character.Parent ~= nil and hrp.Parent ~= nil and hum.Parent ~= nil
	end

	-- it backs off (on its own clock, it can run past the end of the catch)
	local backedOff = def.backoff == nil
	if def.backoff then
		task.spawn(function()
			local b = def.backoff
			waitUntil(b[1])
			local behind = -f
			local hit = workspace:Raycast(root.Position, behind * (b[3] + 2), rayParams(bodies()))
			local distance = hit and math.max((hit.Position - root.Position).Magnitude - 2, 0) or b[3]
			slide(root.CFrame + behind * distance, b[2] - b[1])
			backedOff = true
		end)
	end

	-- the hits land
	for _, t in ipairs(def.hits) do
		waitUntil(t)
		if stillThere() then
			hum.Health = math.max(hum.Health - Config.HIT_DAMAGE, 1)
		end
	end

	-- let go
	waitUntil(def.length)
	if stillThere() then
		local endCF = Shared.victimEndCFrame(kind, frame, env)
		hrp.CFrame = endCF
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.Anchored = false
		if def.lethal then
			hum.Health = 0                       -- DownedSystem puts you down from here
		else
			character:SetAttribute("BeingKilled", false)
			graceUntil[player] = os.clock() + (def.resume - def.length) + Config.GRACE_AFTER_HIT
		end
	end
	lookAt:Destroy()

	while not backedOff do
		task.wait()
	end
	clearCatch()
	root.Anchored = false
	setState("Move")

	-- it stays there twitching while you get up, then comes again
	waitUntil(def.resume)
	busy = false
	return not def.lethal
end

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

local target = nil
local lastSeenPosition = nil
local lastSeenTime = 0
local burstUntil = 0
local nextWanderAt = 0
local lastRepath = 0
local stuckCheckAt = os.clock()
local stuckCheckPosition = root.Position
local stuckCount = 0
local ventCheckAt = 0
local venting = false

local function randomWanderPoint()
	for _ = 1, 8 do
		local angle = math.random() * math.pi * 2
		local distance = 15 + math.random() * (WANDER_RADIUS - 15)
		local point = spawnPoint + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if computePath(point) then
			return true
		end
	end
	return false
end

local function spot(player)
	-- freezes, snaps its head round at you and shrieks, then goes
	busy = true
	waypoints = {}
	humanoid:MoveTo(root.Position)
	local _, hrp = alive(player)
	if hrp then
		face(hrp.Position)
	end
	monster:SetAttribute("TargetId", player.UserId)
	setState("Spot")
	task.wait(Config.SPOT_TIME)
	setState("Move")
	burstUntil = os.clock() + Config.BURST_TIME
	busy = false
end

while monster.Parent do
	task.wait(0.1)
	if busy then
		continue
	end

	local now = os.clock()

	-- who can it sense right now?
	local seen = findTarget()
	if seen then
		if not target then
			target = seen
			spot(seen)
			lastSeenTime = os.clock()
			continue
		end
		target = seen
		local _, hrp = alive(seen)
		if hrp then
			lastSeenPosition = hrp.Position
			lastSeenTime = now
		end
	elseif target and (now - lastSeenTime > Config.GIVE_UP_AFTER or not alive(target)) then
		target = nil
	end

	local chasing = target ~= nil
	monster:SetAttribute("Chasing", chasing)
	monster:SetAttribute("TargetId", target and target.UserId or 0)

	if now >= ventCheckAt then
		ventCheckAt = now + 0.3
		venting = inVent()
	end
	local speed
	if chasing then
		speed = now < burstUntil and Config.BURST_SPEED or Config.CHASE_SPEED
	else
		speed = prowlSpeed(now)
	end
	if venting then
		speed = math.min(speed, Config.VENT_SPEED)
	end
	humanoid.WalkSpeed = speed

	-- caught you?
	if target then
		local character, hrp = alive(target)
		if character and (graceUntil[target] or 0) < now then
			local offset = hrp.Position - root.Position
			local flatDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if flatDistance <= Config.CATCH_RANGE and math.abs(offset.Y) < 4
				and not workspace:Raycast(root.Position, offset, rayParams(bodies())) then
				local victim = target
				local survived = doCatch(victim)
				if survived and alive(victim) then
					-- straight back after you
					target = victim
					lastSeenTime = os.clock()
					burstUntil = 0
				else
					target = nil
					nextWanderAt = os.clock() + 2
				end
				continue
			end
		end
	end

	-- where to go
	local goal = nil
	if chasing then
		local character, hrp = alive(target)
		goal = (character and seen == target) and hrp.Position or lastSeenPosition
	end

	if goal then
		-- in a straight line with nothing in the way (a straight vent, an
		-- open room): run right at you; otherwise follow a path
		local offset = goal - root.Position
		local low = root.Position - UP * (Config.ROOT_HEIGHT - 0.7)
		local lowGoal = Vector3.new(goal.X, low.Y, goal.Z)
		local ignore = bodies()
		local clear = offset.Magnitude < 40
			and workspace:Raycast(low, lowGoal - low, rayParams(ignore)) == nil
			and workspace:Raycast(root.Position, Vector3.new(goal.X, root.Position.Y, goal.Z) - root.Position, rayParams(ignore)) == nil
		if clear then
			waypoints = {}
			humanoid:MoveTo(goal)
		elseif now - lastRepath > 0.3 then
			lastRepath = now
			computePath(goal)
		end

		-- reached the last place it saw you and you're gone: look around
		if not seen and Vector3.new(offset.X, 0, offset.Z).Magnitude < 4 then
			target = nil
			nextWanderAt = now + 2
		end
	elseif now >= nextWanderAt and #waypoints == 0 then
		if randomWanderPoint() then
			nextWanderAt = math.huge
		else
			nextWanderAt = now + 2
		end
	end

	-- follow the path
	if #waypoints > 0 then
		local waypoint = waypoints[waypointIndex]
		while waypoint and
			(Vector3.new(waypoint.Position.X, 0, waypoint.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude < 2.2 do
			waypointIndex += 1
			waypoint = waypoints[waypointIndex]
		end
		if waypoint then
			humanoid:MoveTo(waypoint.Position)
		else
			waypoints = {}
			if not chasing then
				humanoid:MoveTo(root.Position)
				nextWanderAt = now + 2 + math.random() * 4
			end
		end
	end

	-- stuck check: wants to move but hasn't got anywhere
	if now - stuckCheckAt > 1.2 then
		local moved = (root.Position - stuckCheckPosition).Magnitude
		local wantsToMove = (chasing or #waypoints > 0) and humanoid.WalkSpeed > 0
		if wantsToMove and moved < 1.0 then
			stuckCount += 1
			if goal then
				computePath(goal)
			end
			if stuckCount >= 3 then
				local sideways = root.CFrame.RightVector * (math.random() < 0.5 and -4 or 4)
				humanoid:MoveTo(root.Position + sideways)
				stuckCount = 0
			end
		else
			stuckCount = 0
		end
		stuckCheckAt = now
		stuckCheckPosition = root.Position
	end
end
