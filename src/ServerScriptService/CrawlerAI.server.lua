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
--   * walls and ceilings: about half its wanders it runs up a flat wall and
--     creeps along the ceiling upside down (the root part is carried along
--     under the ceiling, anchored). Walk right under it and it drops on you
--     (the Pounce catch). See you from up there and it stops, stares (head
--     twisting round), then drops to the floor, shrieks and comes. A camera
--     flash knocks it off. Bored, it lowers itself back down.
--   * doors (if you've added the door system): prowling, it creeps a closed
--     door open; chasing, it smashes straight through. If someone's holding
--     it shut, it throws itself at it until they slip (it bursts through) or
--     it gives up, growls, and leaves everyone alone for a while.
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

-- doors (optional: only if you've added the door system)
local Doors, DoorConfig = nil, nil
local doorModule = script.Parent and script.Parent:FindFirstChild("DoorServer")
if doorModule and ReplicatedStorage:FindFirstChild("DoorConfig") then
	Doors = require(doorModule)
	DoorConfig = require(ReplicatedStorage.DoorConfig)
end

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

-- hanging lamps: not a ceiling it can hold on to (it goes straight past them)
local lampList = {}
do
	local basement = workspace:FindFirstChild("Basement")
	local folder = basement and basement:FindFirstChild("Lights")
	if folder then
		table.insert(lampList, folder)
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:GetAttribute("PowerLight") == true then
			table.insert(lampList, d)
		end
	end
end
local function ignoreUp()
	local list = { monster }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, lamp in ipairs(lampList) do
		table.insert(list, lamp)
	end
	return list
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

-- "Floor" or "Ceiling" (CrawlerAnimator draws it upside down on the ceiling)
local surface = "Floor"
local ceilingFloorY = nil        -- the floor under it while it's up there
local function setSurface(name)
	surface = name
	monster:SetAttribute("Surface", name)
end
setSurface("Floor")

monster:SetAttribute("Chasing", false)
monster:SetAttribute("TargetId", 0)
monster:SetAttribute("CatchVictim", 0)
setState("Move")
monster:SetAttribute("CrawlerReady", true)

--------------------------------------------------
-- SENSES
--------------------------------------------------

local graceUntil = {}      -- player -> time it can catch them again
local ignoreUntil = 0      -- after a door beats it, it sulks off and ignores everyone

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
	if surface == "Ceiling" then
		return root.Position + root.CFrame.LookVector * 2.4 - UP * 0.6
	end
	return root.Position + root.CFrame.LookVector * 2.4 + UP * 0.5
end

--------------------------------------------------
-- WHAT IT CAN SEE
--------------------------------------------------
-- Eyes, not radar:
--   * how far depends on the light: 40 studs in the dark, 70 once the power
--     is back on; your camcorder light on: half as far again
--   * crouching it has to be 35% closer to spot you, crawling 55% closer
--   * only what's in front of it (a 120 degree cone); behind it, it only
--     notices you if you're right on top of it
--   * any part of you counts: head, chest or legs poking out from cover
--   * close up it's instant; far off it needs to keep you in sight a moment
--     (up to half a second at the edge of its range) - a glimpse can slip by
--   * once it's after you it keeps its eyes on you: no cone, no delay

local SIGHT = {
	DARK = 40,              -- studs, power out
	LIT = 70,               -- studs, lights back on
	LIGHT_BONUS = 1.5,      -- your camcorder light on: this much further
	CROUCH = 0.65,          -- crouching: its range shrinks to this
	CRAWL = 0.45,           -- crawling
	CONE = 120,             -- degrees in front of it
	CHASE_RANGE = 1.3,      -- the one it's chasing: it can follow you this much further
	INSTANT_WITHIN = 0.35,  -- inside this share of its range it spots you at once
	LONGEST_LOOK = 0.5,     -- seconds it needs at the very edge of its range
}

-- everyone's stance, for the above (the camera script reports it; BodyMotionServer does the same)
local stanceRelay = ReplicatedStorage:FindFirstChild("BodyMotion") or Instance.new("RemoteEvent")
stanceRelay.Name = "BodyMotion"
stanceRelay.Parent = ReplicatedStorage
local STANCES = { Walk = true, Sprint = true, Crouch = true, Crawl = true }
stanceRelay.OnServerEvent:Connect(function(player, stance)
	if player.Character and type(stance) == "string" and STANCES[stance] then
		player.Character:SetAttribute("Stance", stance)
	end
end)

local function powerOn()
	local power = ReplicatedStorage:FindFirstChild("Power")
	return power ~= nil and power:GetAttribute("On") == true
end

-- your camcorder's light, if it's switched on
local function camcorderLightOn(player, character)
	for _, owner in ipairs({ character, player }) do
		for _, name in ipairs({ "CamcorderLight", "CamcorderLightOn", "LightOn" }) do
			if owner:GetAttribute(name) == true then
				return true
			end
		end
	end
	for _, light in ipairs(character:GetDescendants()) do
		if light:IsA("Light") and light.Enabled and light.Brightness > 0 then
			local node = light
			while node and node ~= character do
				local name = node.Name:lower()
				if name:find("camcorder") or name:find("camera") then
					return true
				end
				node = node.Parent
			end
		end
	end
	return false
end

-- how far it can see this player right now
local function sightRange(player, character)
	local range = powerOn() and SIGHT.LIT or SIGHT.DARK
	if surface == "Ceiling" and Config.CEILING_SIGHT then
		range = math.min(range, Config.CEILING_SIGHT)
	end
	if camcorderLightOn(player, character) then
		range *= SIGHT.LIGHT_BONUS
	end
	local stance = character:GetAttribute("Stance")
	if stance == "Crawl" then
		range *= SIGHT.CRAWL
	elseif stance == "Crouch" then
		range *= SIGHT.CROUCH
	end
	return range
end

-- a straight look from its eyes to a point: true if nothing solid is in the
-- way (it sees through glass and invisible walls)
local function clearLine(from, to, character)
	local ignore = { monster }
	for _ = 1, 4 do
		local hit = workspace:Raycast(from, to - from, rayParams(ignore))
		if not hit or hit.Instance:IsDescendantOf(character) then
			return true
		end
		if hit.Instance.Transparency < 0.6 then
			return false
		end
		table.insert(ignore, hit.Instance)
	end
	return false
end

-- can it see any part of you? (chasing = you're the one it's after)
local function canSee(player, character, hrp, chasing)
	local from = eye()
	local range = sightRange(player, character) * (chasing and SIGHT.CHASE_RANGE or 1)
	local offset = hrp.Position - from
	if offset.Magnitude > range + 3 then
		return false, 0
	end
	-- only what's in front of it (while it hunts you down, it's facing you anyway)
	if not chasing then
		local look = Shared.flat(root.CFrame.LookVector)
		local dir = Shared.flat(offset)
		if dir.Magnitude > 0.01 and look:Dot(dir.Unit) < math.cos(math.rad(SIGHT.CONE / 2)) then
			return false, 0
		end
	end
	local points = {}
	for _, name in ipairs({ "Head", "Torso", "UpperTorso", "Left Leg", "Right Leg", "LeftLowerLeg", "RightLowerLeg" }) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(points, part.Position)
		end
	end
	if #points == 0 then
		table.insert(points, hrp.Position)
	end
	for _, point in ipairs(points) do
		local distance = (point - from).Magnitude
		if distance <= range and clearLine(from, point, character) then
			return true, distance / range
		end
	end
	return false, 0
end

local target = nil         -- the player it's after (set by the main loop further down)
local seenFor = {}         -- player -> seconds it's had you in sight (for the far-off delay)
local lastLook = os.clock()

-- someone crawling through a duct: the metal booms under every move, and it
-- hears it (it doesn't need to see you to come straight in after you)
local DUCT_HEARING = 32
local function inDuct(hrp)
	local ignore = bodies()
	local down = workspace:Raycast(hrp.Position + UP, Vector3.new(0, -10, 0), rayParams(ignore))
	if not down then
		return false
	end
	local up = workspace:Raycast(down.Position + UP * 0.5, UP * 30, rayParams(ignore))
	return up ~= nil and (up.Position.Y - down.Position.Y) < Config.VENT_CEILING
end

local function findTarget()
	local now = os.clock()
	local dt = math.min(now - lastLook, 0.5)
	lastLook = now
	if now < ignoreUntil then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character, hrp = alive(player)
		if character then
			local offset = hrp.Position - root.Position
			local distance = offset.Magnitude
			-- right on top of it, it notices you without looking (quieter crouched or crawling)
			local stance = character:GetAttribute("Stance")
			local notice = Config.NOTICE_RANGE * (stance == "Crawl" and 0.5 or stance == "Crouch" and 0.7 or 1)
			local close = distance <= notice and math.abs(offset.Y) < 8
			if surface == "Ceiling" then
				-- up there: whoever passes underneath
				local flatDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
				local standY = (ceilingFloorY or (root.Position.Y - 10)) + 3
				close = flatDistance <= notice and math.abs(hrp.Position.Y - standY) < 6
				distance = flatDistance
			end
			local heard = surface ~= "Ceiling" and distance < DUCT_HEARING and inDuct(hrp)

			local chasingThem = target == player
			local visible, howFar = canSee(player, character, hrp, chasingThem)
			local spotted = false
			if visible then
				-- far off it takes a moment to be sure; close up it's instant
				local need = 0
				if not chasingThem then
					need = math.clamp((howFar - SIGHT.INSTANT_WITHIN) / (1 - SIGHT.INSTANT_WITHIN), 0, 1) * SIGHT.LONGEST_LOOK
				end
				seenFor[player] = (seenFor[player] or 0) + dt
				spotted = seenFor[player] >= need
			else
				seenFor[player] = math.max((seenFor[player] or 0) - dt * 1.5, 0)
			end

			if distance < bestDistance and (close or heard or spotted) then
				best, bestDistance = player, distance
			end
		else
			seenFor[player] = nil
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
	-- (from the ceiling: the path is worked out on the floor below it)
	local from = root.Position
	if surface == "Ceiling" and ceilingFloorY then
		from = Vector3.new(from.X, ceilingFloorY + Config.ROOT_HEIGHT, from.Z)
	end
	local ok = pcall(function()
		path:ComputeAsync(from, goal)
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
			stalkSpeed, stalkUntil = 0, now + 0.25 + math.random() * 0.55          -- freezes (a beat, no more)
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

-- fromCeiling: it lets go of the ceiling and comes down on top of you
local function doCatch(player, fromCeiling)
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

	-- in a duct: how far you'd have to be dragged (back the way it came at
	-- you) to be out of it, and how much room there is out there to throw you
	local yank, fling, side = nil, 0, 1
	if not fromCeiling and clear < Config.VENT_CEILING then
		for d = 0.5, 16, 0.5 do
			local p = floorPoint - f * d
			if ceilingAbove(p + UP * 0.2, ignore) >= Config.VENT_CEILING + 0.5 then
				yank = d + 1.3
				break
			end
		end
		if yank then
			local out = floorPoint - f * yank + UP * 1.4
			local best = -1
			for _, s in ipairs({ 1, -1 }) do
				local hit = workspace:Raycast(out, f:Cross(UP) * (s * 9), rayParams(ignore))
				local room = hit and (hit.Position - out).Magnitude - 1.4 or 9
				if room > best then
					best, side = room, s
				end
			end
			fling = math.clamp(best, 0, 6.5)
		end
	end

	local lethal = hum.Health - Config.HIT_DAMAGE <= 0
	local kind
	if fromCeiling then
		kind = lethal and "PounceFinisher" or "Pounce"
	elseif clear < Config.VENT_CEILING then
		-- it drags you out by the ankles and throws you (if there's an out
		-- and the landing won't finish you); otherwise it mauls you in there
		if yank and hum.Health - Shared.CATCHES.VentYank.damage > 0 then
			kind = "VentYank"
		else
			kind = lethal and "VentFinisher" or "VentMaul"
		end
	elseif lethal then
		kind = "Finisher"
	else
		kind = math.random() < 0.5 and "Slam" or "Swipe"
	end
	local def = Shared.CATCHES[kind]
	if def.yank then
		standY = 3                   -- (you'll be standing again out there, not in the duct)
	end

	-- where it plants itself: HOLD_DISTANCE in front of you, if that's free
	local base = floorPoint - f * Config.HOLD_DISTANCE
	local rootPos = Vector3.new(base.X, root.Position.Y, base.Z)
	local ceilLift = 0
	if fromCeiling then
		-- it lands on the floor there (or closer, if a wall's in the way)
		local low = floorPoint + UP * 1.2
		local hit = workspace:Raycast(low, -f * Config.HOLD_DISTANCE, rayParams(ignore))
		local hold = hit and math.max((hit.Position - low).Magnitude - 0.7, 1.2) or Config.HOLD_DISTANCE
		base = floorPoint - f * hold
		rootPos = Vector3.new(base.X, floorY + Config.ROOT_HEIGHT, base.Z)
		ceilLift = math.max(root.Position.Y - rootPos.Y, 0)
		root.Anchored = true
		root.CFrame = CFrame.lookAt(rootPos, rootPos + f)
		setSurface("Floor")
	else
		local toSpot = rootPos - root.Position
		if toSpot.Magnitude > 0.05 and workspace:Raycast(root.Position, toSpot, rayParams(ignore)) then
			rootPos = root.Position                                   -- a wall's in the way: stay put
			base = Vector3.new(rootPos.X, floorY, rootPos.Z)
		end
	end
	monster:SetAttribute("CatchCeilL", ceilLift)
	local env = {
		hold = (Vector3.new(victimPos.X, 0, victimPos.Z) - Vector3.new(rootPos.X, 0, rootPos.Z)).Magnitude,
		standY = standY, clear = clear, back = back,
		yank = yank or 0, fling = fling, side = side,
	}
	monster:SetAttribute("CatchYank", env.yank)
	monster:SetAttribute("CatchFling", fling)
	monster:SetAttribute("CatchSide", side)
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

	-- pulling you out of the duct: it backs out with you, jerk by jerk
	if def.yank then
		task.spawn(function()
			local from = root.CFrame
			while true do
				local t = workspace:GetServerTimeNow() - start
				root.CFrame = from - f * (env.yank * Shared.sample(def.victim.yankA, t))
				if t > 1.3 then
					break
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end

	local function waitUntil(t)
		-- (testing: the model's "HoldCatch" attribute pauses the catch here)
		while monster:GetAttribute("HoldCatch") do
			task.wait(0.1)
			start = workspace:GetServerTimeNow() - t
		end
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
			hum.Health = math.max(hum.Health - (def.damage or Config.HIT_DAMAGE), 1)
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

target = nil
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

-- every room in the basement: somewhere to go
local roomFloors = {}
do
	local basement = workspace:FindFirstChild("Basement")
	if basement then
		for _, room in ipairs(basement:GetChildren()) do
			local f = room:FindFirstChild("Floor")
			if f and f:IsA("BasePart") and f.Size.X > 6 and f.Size.Z > 6 then
				table.insert(roomFloors, f)
			end
		end
	end
end

-- It roams the whole basement, room to room; now and then it drifts towards
-- where people are (a rough idea, never exactly where).
local function randomWanderPoint()
	local people = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local character, hrp = alive(p)
		if character then
			table.insert(people, hrp)
		end
	end
	for _ = 1, 8 do
		local point
		if #people > 0 and math.random() < 0.3 then
			local hrp = people[math.random(#people)]
			local a = math.random() * math.pi * 2
			local d = 12 + math.random() * 16
			point = hrp.Position + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		elseif #roomFloors > 0 then
			local f = roomFloors[math.random(#roomFloors)]
			point = (f.CFrame * CFrame.new((math.random() - 0.5) * f.Size.X * 0.7, f.Size.Y / 2 + Config.ROOT_HEIGHT,
				(math.random() - 0.5) * f.Size.Z * 0.7)).Position
		else
			local angle = math.random() * math.pi * 2
			local distance = 15 + math.random() * (WANDER_RADIUS - 15)
			point = spawnPoint + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		end
		if computePath(point) then
			return true
		end
	end
	return false
end

local function spot(player)
	-- snaps its head round at you and shrieks - already lunging at you
	waypoints = {}
	local _, hrp = alive(player)
	if hrp then
		face(hrp.Position)
		lastSeenPosition = hrp.Position
		humanoid.WalkSpeed = Config.BURST_SPEED
		humanoid:MoveTo(hrp.Position)
	end
	monster:SetAttribute("TargetId", player.UserId)
	monster:SetAttribute("Chasing", true)
	setState("Spot")
	local spottedAt = monster:GetAttribute("StateStart")
	task.delay(Config.SPOT_TIME, function()
		if monster:GetAttribute("State") == "Spot" and monster:GetAttribute("StateStart") == spottedAt then
			setState("Move")
		end
	end)
	burstUntil = os.clock() + Config.BURST_TIME + 0.3
end

--------------------------------------------------
-- WALLS AND CEILINGS
--------------------------------------------------

local nextClimbAt = os.clock() + 8
local ceilingUntil = 0
local needDrop = false

-- the nearest mouth of the duct a point is in (just outside it), or nil
local function ductMouth(pos)
	local ignore = bodies()
	local floorY = floorBelow(pos, ignore)
	if not floorY then
		return nil
	end
	local base = Vector3.new(pos.X, floorY, pos.Z)
	if ceilingAbove(base, ignore) >= Config.VENT_CEILING then
		return nil
	end
	local best, bestD
	for _, dir in ipairs({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }) do
		for d = 1, 24 do
			if workspace:Raycast(base + UP, dir * d, rayParams(ignore)) then
				break                                   -- the duct wall that way
			end
			local p = base + dir * d
			if ceilingAbove(p + UP * 0.2, ignore) >= Config.VENT_CEILING + 0.5 then
				local out = p + dir * 1.4 + UP * Config.ROOT_HEIGHT
				local dist = (out - root.Position).Magnitude
				if not bestD or dist < bestD then
					best, bestD = out, dist
				end
				break
			end
		end
	end
	return best
end

-- find a flat bit of wall nearby with a ceiling it can hold on to, run at
-- it, up it and out onto the ceiling
local function tryClimb()
	if surface ~= "Floor" or inVent() then
		return false
	end
	local ignore = bodies()
	local floorY = floorBelow(root.Position, ignore)
	if not floorY then
		return false
	end
	local h = Config.ROOT_HEIGHT
	local from = Vector3.new(root.Position.X, floorY + 1.2, root.Position.Z)
	local turn = math.random() * math.pi * 2
	local best = nil
	for i = 0, 11 do
		local a = turn + i / 12 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local hit = workspace:Raycast(from, dir * 14, rayParams(ignore))
		if hit and math.abs(hit.Normal.Y) < 0.15 then
			local n = Shared.flat(hit.Normal)
			local f = -n
			local wallFoot = Vector3.new(hit.Position.X, floorY, hit.Position.Z)
			local d0 = h + 1.6
			local p0 = wallFoot + n * d0 + UP * h
			local up = workspace:Raycast(p0, UP * (Config.CEILING_MAX + 2), rayParams(ignoreUp()))
			local height = up and up.Position.Y - floorY
			local ok = height ~= nil and height >= Config.CEILING_MIN and height <= Config.CEILING_MAX
			-- the wall is flat all the way up
			if ok then
				for _, k in ipairs({ 0.12, 0.5, 0.85 }) do
					local o = Vector3.new(p0.X, floorY + height * k, p0.Z)
					local w = workspace:Raycast(o, f * (d0 + 1.2), rayParams(ignore))
					if not w or math.abs((w.Position - o):Dot(f) - d0) > 0.6 or math.abs(w.Normal.Y) > 0.2 then
						ok = false
						break
					end
				end
			end
			-- nothing on it in the way, and a ceiling where it comes out
			if ok and workspace:Raycast(wallFoot + n * h + UP * 0.5, UP * (height - 1.2), rayParams(ignoreUp())) then
				ok = false
			end
			if ok then
				local out = wallFoot + n * (h + 2.5) + UP
				local c = workspace:Raycast(out, UP * (height + 2), rayParams(ignoreUp()))
				if not c or math.abs(c.Position.Y - (floorY + height)) > 0.9 then
					ok = false
				end
			end
			-- and it can get to where it starts
			if ok and workspace:Raycast(root.Position, p0 - root.Position, rayParams(ignore)) then
				ok = false
			end
			if ok then
				local distance = (p0 - root.Position).Magnitude
				if not best or distance < best.distance then
					best = { p0 = p0, f = f, height = height, floorY = floorY, distance = distance }
				end
			end
		end
	end
	if not best then
		return false
	end

	busy = true
	waypoints = {}
	humanoid.WalkSpeed = Config.STALK_SPEED
	humanoid:MoveTo(best.p0)
	local walkStart = os.clock()
	while os.clock() - walkStart < 4 do
		if (Vector3.new(best.p0.X, 0, best.p0.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude < 0.8 then
			break
		end
		task.wait(0.05)
	end
	humanoid:MoveTo(root.Position)

	-- how far the wall really is from where it ended up
	local p0 = Vector3.new(root.Position.X, best.floorY + h, root.Position.Z)
	local wall = workspace:Raycast(Vector3.new(p0.X, best.floorY + 1.2, p0.Z), best.f * 6, rayParams(bodies()))
	local d0 = wall and (wall.Position - Vector3.new(p0.X, best.floorY + 1.2, p0.Z)):Dot(best.f)
	if not d0 or d0 < h + 0.5 or d0 > h + 3.5 then
		busy = false
		return false
	end

	root.Anchored = true
	slide(CFrame.lookAt(p0, p0 + best.f), 0.3)
	local plan = Shared.climbPlan(p0, best.f, d0, best.height, 2.5, h)
	local start = workspace:GetServerTimeNow() + 0.05
	monster:SetAttribute("ClimbP0", p0)
	monster:SetAttribute("ClimbDir", best.f)
	monster:SetAttribute("ClimbD0", d0)
	monster:SetAttribute("ClimbH", best.height)
	monster:SetAttribute("ClimbOnto", 2.5)
	monster:SetAttribute("ClimbRootH", h)
	monster:SetAttribute("ClimbSpeed", Config.CLIMB_SPEED)
	monster:SetAttribute("ClimbStart", start)
	setState("ClimbUp")

	-- carry the root part along with the body: up the wall, out under the ceiling
	while true do
		local s = math.clamp((workspace:GetServerTimeNow() - start) * Config.CLIMB_SPEED, 0, plan.total)
		local space, floorRoot = Shared.climbSpace(plan, s)
		local real = space * floorRoot
		local look = Shared.flat(real.LookVector, s > plan.c2 and -best.f or best.f)
		root.CFrame = CFrame.lookAt(real.Position, real.Position + look)
		if s >= plan.total then
			break
		end
		RunService.Heartbeat:Wait()
	end

	ceilingFloorY = best.floorY
	ceilingUntil = os.clock() + Config.CEILING_STAY[1] + math.random() * (Config.CEILING_STAY[2] - Config.CEILING_STAY[1])
	needDrop = false
	nextWanderAt = os.clock() + 0.6 + math.random() * 1.5     -- clings there a moment first
	setSurface("Ceiling")
	setState("Move")
	busy = false
	return true
end

-- let go of the ceiling. quiet = lowering itself down because it's bored;
-- otherwise it falls, twisting over, and lands hard
local function dropDown(quiet)
	busy = true
	waypoints = {}
	local floorY = floorBelow(root.Position, bodies()) or ceilingFloorY or (root.Position.Y - 10)
	local look = Shared.flat(root.CFrame.LookVector)
	local landing = Vector3.new(root.Position.X, floorY + Config.ROOT_HEIGHT, root.Position.Z)
	local lift = math.max(root.Position.Y - landing.Y, 0)
	root.Anchored = true
	root.CFrame = CFrame.lookAt(landing, landing + look)
	monster:SetAttribute("DropL", lift)
	monster:SetAttribute("DropQuiet", quiet == true)
	setSurface("Floor")
	setState("Drop")
	task.wait((quiet and Config.QUIET_DROP_TIME or Config.DROP_TIME) + 0.15)
	root.Anchored = false
	setState("Move")
	nextClimbAt = os.clock() + Config.CLIMB_COOLDOWN
	nextWanderAt = os.clock() + 1 + math.random() * 2
	busy = false
end

-- seen you from up there: freezes, turns to you, its head twisting round
-- the right way up. Come close enough meanwhile and it drops on you.
local function watch(player)
	busy = true
	waypoints = {}
	monster:SetAttribute("TargetId", player.UserId)
	setState("Watch")
	local started = os.clock()
	local result = "drop"
	while os.clock() - started < Config.WATCH_TIME do
		local dt = RunService.Heartbeat:Wait()
		local character, hrp = alive(player)
		if not character then
			result = "gone"
			break
		end
		local offset = hrp.Position - root.Position
		local want = Shared.flat(offset, root.CFrame.LookVector)
		local look = root.CFrame.LookVector:Lerp(want, math.clamp(dt * 4, 0, 1))
		root.CFrame = CFrame.lookAt(root.Position, root.Position + Shared.flat(look, want))
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.POUNCE_RANGE then
			result = "pounce"
			break
		end
	end
	busy = false
	return result
end

-- creeping along the ceiling, following a path worked out on the floor below
local ceilingTurnSpeed = 2.6
RunService.Heartbeat:Connect(function(dt)
	if surface ~= "Ceiling" or busy or needDrop then
		return
	end
	local pos = root.Position
	local look = Shared.flat(root.CFrame.LookVector)
	local waypoint = waypoints[waypointIndex]
	while waypoint and (Vector3.new(waypoint.Position.X - pos.X, 0, waypoint.Position.Z - pos.Z)).Magnitude < 1.6 do
		waypointIndex += 1
		waypoint = waypoints[waypointIndex]
	end
	if not waypoint then
		if #waypoints > 0 then
			waypoints = {}
			nextWanderAt = os.clock() + 2 + math.random()              -- hangs there a moment
		end
		return
	end
	local want = Shared.flat(waypoint.Position - pos, look)
	local angle = math.atan2(look:Cross(want).Y, look:Dot(want))
	local step = math.clamp(angle, -ceilingTurnSpeed * dt, ceilingTurnSpeed * dt)
	look = CFrame.fromAxisAngle(UP, step):VectorToWorldSpace(look)
	local speed = prowlSpeed(os.clock()) * (Config.CEILING_SPEED / Config.STALK_SPEED)
	if math.abs(angle) > 1.1 then
		speed *= 0.25                                                  -- turns on the spot first
	end
	local nextPos = pos + look * speed * dt

	-- the ceiling there: felt for from a little under where it hangs (so it
	-- finds a lower door head coming up, but not the furniture far below)
	local c = workspace:Raycast(Vector3.new(nextPos.X, pos.Y - 3.2, nextPos.Z), UP * 9, rayParams(ignoreUp()))
	local floorY = floorBelow(Vector3.new(nextPos.X, pos.Y - 3.2, nextPos.Z), bodies()) or ceilingFloorY
	if not c or (floorY and c.Position.Y - floorY > Config.CEILING_MAX + 1) then
		needDrop = true                                                -- nothing to hold on to ahead
		return
	end
	ceilingFloorY = floorY or ceilingFloorY
	local goalY = c.Position.Y - Config.ROOT_HEIGHT
	local y = pos.Y + math.clamp(goalY - pos.Y, -5 * dt, 5 * dt)
	local at = Vector3.new(nextPos.X, y, nextPos.Z)
	root.CFrame = CFrame.lookAt(at, at + look)
end)

local function pounce(player)
	target = player
	local survived = doCatch(player, true)
	if survived and alive(player) then
		target = player
		lastSeenTime = os.clock()
		burstUntil = 0
	else
		target = nil
		nextWanderAt = os.clock() + 2
	end
end

-- one tick of thinking while it's up on the ceiling
local function ceilingBrain()
	local now = os.clock()
	monster:SetAttribute("Chasing", false)
	local seen = findTarget()
	if seen then
		local _, hrp = alive(seen)
		local offset = hrp.Position - root.Position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.POUNCE_RANGE then
			pounce(seen)
			return
		end
		local result = watch(seen)
		if result == "pounce" then
			pounce(seen)
		else
			dropDown(false)
			if alive(seen) then
				target = seen
				lastSeenTime = os.clock()
				spot(seen)
			end
		end
		return
	end
	monster:SetAttribute("TargetId", 0)
	if #waypoints == 0 and nextWanderAt == math.huge then
		nextWanderAt = now                    -- (its path was dropped: find another)
	end
	if needDrop then
		needDrop = false
		dropDown(true)
		return
	end
	if #waypoints == 0 then
		if now >= ceilingUntil and math.random() < 0.5 then
			dropDown(true)
			return
		end
		if now >= nextWanderAt then
			if randomWanderPoint() then
				nextWanderAt = math.huge
			else
				nextWanderAt = now + 2
			end
		end
	end
end

--------------------------------------------------
-- DOORS
--------------------------------------------------
-- Prowling, it creeps a closed door open. Chasing, it smashes straight
-- through it. If someone's leaning on the other side it throws itself at the
-- door until they break or it gives up.

local function publishDoor(layout)
	monster:SetAttribute("DoorPoint", layout.point)
	monster:SetAttribute("DoorNormal", layout.normal)
	monster:SetAttribute("DoorEdge", layout.edge)
end

local DOOR_STAND = 4.0     -- how far from the door it plants itself (its head and claws just reach it)

-- plant itself on its side of the door, facing it
local function squareUp(layout, distance)
	local spot = layout.centre:PointToWorldSpace(Vector3.new(0, 0, layout.side * distance))
	local pos = Vector3.new(spot.X, root.Position.Y, spot.Z)
	local look = Vector3.new(-layout.normal.X, 0, -layout.normal.Z)
	root.Anchored = true
	slide(CFrame.lookAt(pos, pos + look), 0.22)
end

local function smashDoor(model)
	busy = true
	waypoints = {}
	humanoid:MoveTo(root.Position)
	local layout = Doors.layout(model, root.Position)
	publishDoor(layout)
	squareUp(layout, DOOR_STAND)
	setState("DoorBash")
	task.wait(0.5)                          -- rears back...
	Doors.breakDoor(model, -layout.normal)  -- ...and goes through it
	task.wait(0.3)
	root.Anchored = false
	setState("Move")
	burstUntil = os.clock() + 0.6
	busy = false
end

local function doorFight(model)
	busy = true
	waypoints = {}
	humanoid:MoveTo(root.Position)
	local layout = Doors.layout(model, root.Position)
	publishDoor(layout)
	squareUp(layout, DOOR_STAND)
	monster:SetAttribute("SlamAt", 0)
	setState("DoorSlam")
	local outcome = Doors.fight(model, monster)
	if outcome == "won" then
		-- one last furious slam and a growl... then it gives up and slinks off
		setState("DoorRage")
		task.wait(2.0)
		root.Anchored = false
		setState("Move")
		target = nil
		monster:SetAttribute("Chasing", false)
		monster:SetAttribute("TargetId", 0)
		ignoreUntil = os.clock() + DoorConfig.GIVE_UP_TIME
		computePath(root.Position + layout.normal * 35)
		nextWanderAt = math.huge
	elseif outcome == "breach" then
		-- through, roaring
		task.wait(0.2)
		setState("DoorRage")
		task.wait(0.9)
		root.Anchored = false
		setState("Move")
		burstUntil = os.clock() + 0.8
	else
		-- nobody holding it (or they let go): straight through
		if not model:GetAttribute("Broken") then
			setState("DoorBash")
			task.wait(0.45)
			Doors.breakDoor(model, -layout.normal)
			task.wait(0.3)
		end
		root.Anchored = false
		setState("Move")
	end
	busy = false
end

local nextDoorCheck = 0

local stunned = false
while monster.Parent do
	task.wait(0.1)
	if busy then
		continue
	end

	-- testing (command bar, server): workspace.TheCrawler:SetAttribute("TestClimb", true)
	-- / ("TestDrop", true)
	if monster:GetAttribute("TestClimb") then
		monster:SetAttribute("TestClimb", nil)
		if surface == "Floor" and not tryClimb() then
			warn("CrawlerAI: no wall to climb near", root.Position)
		end
		continue
	end
	if monster:GetAttribute("TestDrop") then
		monster:SetAttribute("TestDrop", nil)
		if surface == "Ceiling" then
			dropDown(false)
		end
		continue
	end

	-- blinded by a camera flash (PhotoServer): it freezes, recoils and shrieks
	-- (and up on the ceiling, it loses its grip and falls)
	if workspace:GetServerTimeNow() < (monster:GetAttribute("StunnedUntil") or 0) then
		if surface == "Ceiling" then
			dropDown(false)
		end
		if not stunned then
			stunned = true
			waypoints = {}
			setState("Stun")
			-- blinded: it staggers back a few steps, still facing the light
			-- (CrawlerBody acts out the rest: claws at its eyes, shrieking)
			humanoid.AutoRotate = false
			humanoid.WalkSpeed = 6
			local look = Shared.flat(root.CFrame.LookVector)
			local hit = workspace:Raycast(root.Position, -look * 4, rayParams(bodies()))
			local step = hit and math.max((hit.Position - root.Position).Magnitude - 1.6, 0) or 2.8
			humanoid:MoveTo(root.Position - look * math.min(step, 2.8))
			task.delay(0.6, function()
				if stunned then
					humanoid.WalkSpeed = 0
					humanoid:MoveTo(root.Position)
				end
			end)
		end
		continue
	elseif stunned then
		stunned = false
		humanoid.AutoRotate = true
		setState("Move")
		lastRepath = 0
	end

	if surface == "Ceiling" then
		ceilingBrain()
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
			-- (you in a duct: its arm reaches further in after you)
			local reach = Config.CATCH_RANGE
			if flatDistance > reach and flatDistance <= Config.VENT_REACH then
				local fy = floorBelow(hrp.Position, bodies())
				if fy and ceilingAbove(Vector3.new(hrp.Position.X, fy, hrp.Position.Z), bodies()) < Config.VENT_CEILING then
					reach = Config.VENT_REACH
				end
			end
			if flatDistance <= reach and math.abs(offset.Y) < 4
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

	-- (its path was thrown away - a catch, a climb, a chase - while it still
	-- thought it was on one: pick somewhere new to go)
	if not chasing and #waypoints == 0 and nextWanderAt == math.huge then
		nextWanderAt = now + 0.5
	end

	-- a closed door in the way?
	if Doors and now >= nextDoorCheck then
		nextDoorCheck = now + 0.15
		local dir = humanoid.MoveDirection
		if dir.Magnitude < 0.1 then
			dir = root.CFrame.LookVector
		end
		dir = Vector3.new(dir.X, 0, dir.Z)
		local model = dir.Magnitude > 0.01 and Doors.ahead(root.Position, dir.Unit * 3.4, bodies()) or nil
		if model then
			if chasing then
				if (model:GetAttribute("BarricadedBy") or 0) ~= 0 then
					doorFight(model)
				else
					smashDoor(model)
				end
				continue
			else
				Doors.open(model, root.Position, "creep")
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
			if not computePath(goal) then
				-- (somewhere a path can't reach - a duct: make for its mouth;
				-- from there it's a straight line in after you)
				local mouth = ductMouth(goal)
				if mouth then
					computePath(mouth)
				end
			end
		end

		-- reached the last place it saw you and you're gone: look around
		if not seen and Vector3.new(offset.X, 0, offset.Z).Magnitude < 4 then
			target = nil
			nextWanderAt = now + 2
		end
	elseif now >= nextWanderAt and #waypoints == 0 then
		-- about half the time it takes to the walls and the ceiling instead
		if now >= nextClimbAt then
			nextClimbAt = now + 3
			if math.random() < Config.CEILING_CHANCE and tryClimb() then
				nextWanderAt = 0
				continue
			end
		end
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
				nextWanderAt = now + 2 + math.random()               -- a 2-3 second pause, then on
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
