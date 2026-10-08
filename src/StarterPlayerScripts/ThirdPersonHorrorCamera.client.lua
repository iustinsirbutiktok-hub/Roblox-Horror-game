-- ThirdPersonHorrorCamera.lua
-- Place in: StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--------------------------------------------------
-- CONFIG
--------------------------------------------------

local SENSITIVITY = 0.0022
local MAX_PITCH = math.rad(85)

-- FOV
local NORMAL_FOV = 70
local SPRINT_FOV = 88
local FOV_LERP_SPEED = 8

local SPEEDS = {
	Walk = 8,
	Sprint = 20,
	Crouch = 7,
	Crawl = 5,
}

local ACCELERATION = {
	Walk = 40,
	Sprint = 7,
	Crouch = 30,
	Crawl = 20,
}

local DECELERATION = 50

-- Third person settings
local THIRD_PERSON_DISTANCE = 5
local THIRD_PERSON_HEIGHT = 1.5
-- the bear trap uses the close camera above; the lobby a wider one
local TRAP_CAMERA = { distance = 5, height = 1.5 }
local LOBBY_CAMERA = { distance = 11, height = 3.2 }
local THIRD_PERSON_LERP_SPEED = 10
local THIRD_PERSON_PITCH_LIMIT = math.rad(45)
local THIRD_PERSON_MIN_HEIGHT_OFFSET = 0.5
local THIRD_PERSON_MIN_DISTANCE = 2.5

--------------------------------------------------
-- CAMERA SHAKE SETTINGS
--------------------------------------------------

local SHAKE = {
	Idle   = { amp = 0.0025, freq = 0.55, rotAmp = math.rad(0.04) },
	Walk   = { amp = 0.006,  freq = 1.6,  rotAmp = math.rad(0.08) },
	Sprint = { amp = 0.045,  freq = 4.6,  rotAmp = math.rad(0.65) },
	Crouch = { amp = 0.010,  freq = 1.9,  rotAmp = math.rad(0.15) },
	Crawl  = { amp = 0.007,  freq = 2.3,  rotAmp = math.rad(0.22) },
}

local TRAUMA_DECAY = 0.8
local TRAUMA_JOLT_FREQ = 25
local TRAUMA_POS_AMOUNT = 0.10
local TRAUMA_ROT_AMOUNT = math.rad(5)

local HORROR_JOLT_MIN_INTERVAL = 6
local HORROR_JOLT_MAX_INTERVAL = 16
local HORROR_JOLT_TRAUMA = 0.35

local SPRINT_JOLT_MIN_INTERVAL = 2.5
local SPRINT_JOLT_MAX_INTERVAL = 5.5
local SPRINT_JOLT_TRAUMA = 0.18

--------------------------------------------------
-- REALISTIC CAMERA BOB
--------------------------------------------------

local BOB = {
	Idle = {
		vertical = 0.004,
		horizontal = 0.002,
		forward = 0.001,
		roll = math.rad(0.02),
		frequency = 1.2,
	},

	Walk = {
		vertical = 0.040,
		horizontal = 0.018,
		forward = 0.010,
		roll = math.rad(0.20),
		frequency = 7.0,
	},

	Sprint = {
		vertical = 0.075,
		horizontal = 0.030,
		forward = 0.018,
		roll = math.rad(0.45),
		frequency = 10.5,
	},

	Crouch = {
		vertical = 0.022,
		horizontal = 0.012,
		forward = 0.006,
		roll = math.rad(0.14),
		frequency = 6.0,
	},

	Crawl = {
		vertical = 0.015,
		horizontal = 0.010,
		forward = 0.005,
		roll = math.rad(0.12),
		frequency = 5.0,
	},
}

local bobTime = 0
local bobIntensity = 0

--------------------------------------------------
-- CLIMB CAMERA SETTINGS
--------------------------------------------------

local CLIMB_CAM_BACK = 6
local CLIMB_CAM_UP = 5
local CLIMB_CAM_SIDE = 0.5

local CLIMB_CAM_LOOK_HEIGHT = 4

local CLIMB_CAM_ENTER_SPEED = 6

local CLIMB_EXIT_BLEND_TIME = 0.8

--------------------------------------------------
-- ANIMATION IDS
--------------------------------------------------

local ANIMATION_IDS = {

	-- NORMAL WALK ANIMATION
	Walk = "rbxassetid://103384558824413",

	-- LOOPING MOVEMENT ANIMATIONS
	Sprint = "rbxassetid://82219891063668",
	Crawl  = "rbxassetid://120341809907353",
	Crouch = "rbxassetid://99723290210220",

	-- START ANIMATIONS
	CrouchStart = "rbxassetid://83040982292864",
	CrawlStart = "rbxassetid://94285423391710",
}

--------------------------------------------------
-- STATE
--------------------------------------------------

local currentState = "Walk"

-- Walk speed while carrying the fuel can
local CARRY_FUEL_SPEED = 4.5

-- Injuries and adrenaline (see MedicalSystem / MedicalClient / LimpClient)
local LIMP_HEALTH = 0.25        -- below this fraction of health you limp
local LIMP_WALK_FACTOR = 0.72   -- walking speed while limping
local LIMP_RUN_FACTOR = 1.0     -- a desperate limp-run: about normal walk speed
local ADRENALINE_FOV_BONUS = 6


local isSprinting = false
local isCrouching = false
local isCrawling = false
local sentStance = nil           -- last stance told to the server

-- stamina (see STAMINA further down)
local STAMINA_MAX = 100
local stamina = STAMINA_MAX
local exhausted = false          -- ran it dry: no sprinting until you've got your breath back

local yaw = 0
local pitch = 0

local currentSpeed = SPEEDS.Walk

-- Climb camera transition state
local wasClimbing = false
local climbCamActive = false
local blendTimeLeft = 0
local blendFromCFrame = nil

-- Shake state
local trauma = 0

local shakeRng = Random.new()

local shakeSeed = {
	x  = shakeRng:NextNumber(0, 1000),
	y  = shakeRng:NextNumber(0, 1000),
	z  = shakeRng:NextNumber(0, 1000),
	rx = shakeRng:NextNumber(0, 1000),
	ry = shakeRng:NextNumber(0, 1000),
	rz = shakeRng:NextNumber(0, 1000),
}

local horrorJoltClock = 0

local nextHorrorJolt = shakeRng:NextNumber(
	HORROR_JOLT_MIN_INTERVAL,
	HORROR_JOLT_MAX_INTERVAL
)

local sprintJoltClock = 0

local nextSprintJolt = shakeRng:NextNumber(
	SPRINT_JOLT_MIN_INTERVAL,
	SPRINT_JOLT_MAX_INTERVAL
)

--------------------------------------------------
-- CHARACTER
--------------------------------------------------

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local function hasAdrenaline()
	local untilTime = character and character:GetAttribute("AdrenalineUntil")
	return untilTime ~= nil and workspace:GetServerTimeNow() < untilTime
end

local function adrenalineMultiplier()
	local medical = game:GetService("ReplicatedStorage"):FindFirstChild("Medical")
	return medical and medical:GetAttribute("AdrenalineSpeed") or 1.35
end

local function isLimping()
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.MaxHealth <= 0 then
		return false
	end
	return hum.Health / hum.MaxHealth < LIMP_HEALTH and not hasAdrenaline()
end
local hrp = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")

-- no jumping in this game (this also hides the jump button on phones)
local function noJumping(hum)
	hum.UseJumpPower = true
	hum.JumpPower = 0
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

humanoid.AutoRotate = true
noJumping(humanoid)

--------------------------------------------------
-- HELPER: is some OTHER system currently controlling
-- the character?
--------------------------------------------------

local function isExternallyControlled()
	return character:GetAttribute("IsClimbing")
		or character:GetAttribute("IsCrawlingThrough")
		or character:GetAttribute("IsHanging")
		or character:GetAttribute("IsTurningValve")
		or character:GetAttribute("IsFuelAction")
		or character:GetAttribute("IsLeverPush")
		or character:GetAttribute("IsFuseRepair")
		or character:GetAttribute("IsTightSqueeze")
		or character:GetAttribute("IsAxeInspect")
		or character:GetAttribute("IsAxeChop")
		or character:GetAttribute("IsHiding")
		or character:GetAttribute("IsCoopClimbing")
		or character:GetAttribute("IsFusePickup")
		or character:GetAttribute("IsFuseInstall")
		or character:GetAttribute("IsBearTrapped")
		or character:GetAttribute("IsGeneratorStarting")
		or character:GetAttribute("BeingKilled")
		or character:GetAttribute("IsBarricading")      -- leaning on a door, holding it shut (DoorClient)
end

--------------------------------------------------
-- HELPER: movement input
--------------------------------------------------

local function isMoving()
	return UserInputService:IsKeyDown(Enum.KeyCode.W)
		or UserInputService:IsKeyDown(Enum.KeyCode.A)
		or UserInputService:IsKeyDown(Enum.KeyCode.S)
		or UserInputService:IsKeyDown(Enum.KeyCode.D)
		or UserInputService:IsKeyDown(Enum.KeyCode.Up)
		or UserInputService:IsKeyDown(Enum.KeyCode.Down)
		or UserInputService:IsKeyDown(Enum.KeyCode.Left)
		or UserInputService:IsKeyDown(Enum.KeyCode.Right)
end

--------------------------------------------------
-- HELPER: forward movement specifically
--------------------------------------------------

local function isMovingForward()
	return UserInputService:IsKeyDown(Enum.KeyCode.W)
		or UserInputService:IsKeyDown(Enum.KeyCode.Up)
end

--------------------------------------------------
-- LOAD ANIMATIONS
--------------------------------------------------

local tracks = {}

-- with BodyMotion in StarterPlayerScripts, walking, sprinting and crawling
-- are done by it (worked out live, not played from these); without it,
-- these animations play like they always did. Crouching always uses its own.
local PROCEDURAL = { Walk = true, Sprint = true, Crawl = true, CrawlStart = true }

local function bodyMotionOn()
	local scripts = player:FindFirstChild("PlayerScripts")
	local bodyMotion = scripts and scripts:FindFirstChild("BodyMotion")
	return bodyMotion ~= nil and bodyMotion.Enabled
end

local function loadTracks()

	table.clear(tracks)
	local skip = bodyMotionOn()

	for stateName, assetId in pairs(ANIMATION_IDS) do

		if skip and PROCEDURAL[stateName] then
			continue
		end

		local anim = Instance.new("Animation")
		anim.AnimationId = assetId

		local track = animator:LoadAnimation(anim)

		track.Priority = Enum.AnimationPriority.Action

		-- Start animations only play once.
		if stateName == "CrouchStart"
			or stateName == "CrawlStart" then

			track.Looped = false

		else

			track.Looped = true
		end

		tracks[stateName] = track
	end
end

loadTracks()

local activeTrack = nil
local activeStartTrack = nil

--------------------------------------------------
-- STOP LOOPING MOVEMENT ANIMATION ONLY
--------------------------------------------------

local function stopLoopAnimation()

	if activeTrack then
		activeTrack:Stop(0.15)
		activeTrack = nil
	end

end

--------------------------------------------------
-- STOP ALL MOVEMENT + POSE ANIMATIONS
--------------------------------------------------

local function stopMovementAnimations()

	if activeTrack then
		activeTrack:Stop(0.15)
		activeTrack = nil
	end

	if activeStartTrack then
		activeStartTrack:Stop(0.1)
		activeStartTrack = nil
	end

end

--------------------------------------------------
-- DETERMINE WHETHER A HELD POSE IS VALID
--------------------------------------------------

local function isPoseStillValid(stateName)

	if stateName == "CrouchStart" then
		return isCrouching and not isCrawling
	end

	if stateName == "CrawlStart" then
		return isCrawling and not isCrouching
	end

	return false
end

--------------------------------------------------
-- HOLD THE FINAL FRAME OF A START ANIMATION
--------------------------------------------------

local function holdPoseAtEnd(stateName)

	local track = tracks[stateName]

	if not track then
		return
	end

	if activeStartTrack then
		activeStartTrack:Stop(0.1)
	end

	activeStartTrack = track

	track.Looped = false
	track:Play(0.1)
	track:AdjustSpeed(0)

	task.spawn(function()

		local timeout = 0

		while track.Length <= 0 and timeout < 3 do
			timeout += RunService.RenderStepped:Wait()
		end

		if activeStartTrack ~= track then
			return
		end

		if track.Length > 0 then

			track.TimePosition = math.max(
				track.Length - 0.03,
				0
			)

			track:AdjustSpeed(0)

		end
	end)
end

--------------------------------------------------
-- PLAY START ANIMATION
-- THEN FREEZE ON ITS FINAL CROUCH/CRAWL POSE
--------------------------------------------------

local function playStartAnimation(stateName)

	local startTrack = tracks[stateName]

	if not startTrack then
		-- (BodyMotion does this one: just clear what was playing)
		stopMovementAnimations()
		return
	end

	if activeTrack then
		activeTrack:Stop(0.1)
		activeTrack = nil
	end

	if activeStartTrack then
		activeStartTrack:Stop(0.1)
	end

	activeStartTrack = startTrack

	startTrack.Looped = false
	startTrack.TimePosition = 0
	startTrack:Play(0.1)
	startTrack:AdjustSpeed(1)

	task.spawn(function()

		local timeout = 0

		-- Wait until Roblox knows the animation length.
		while startTrack.Length <= 0 and timeout < 3 do
			timeout += RunService.RenderStepped:Wait()
		end

		if activeStartTrack ~= startTrack then
			return
		end

		-- Watch the animation until it is almost at the end.
		while activeStartTrack == startTrack do

			if not isPoseStillValid(stateName) then
				return
			end

			if startTrack.Length > 0
				and startTrack.TimePosition >= startTrack.Length - 0.03 then

				startTrack.TimePosition = math.max(
					startTrack.Length - 0.03,
					0
				)

				startTrack:AdjustSpeed(0)

				break
			end

			RunService.RenderStepped:Wait()
		end
	end)
end

--------------------------------------------------
-- PLAY LOOPING MOVEMENT ANIMATION
--------------------------------------------------

local function playStateAnimation(stateName)

	local newTrack = tracks[stateName]

	if activeTrack == newTrack then
		return
	end

	-- Moving means the held crouch/crawl pose must stop.
	if activeStartTrack then
		activeStartTrack:Stop(0.12)
		activeStartTrack = nil
	end

	if activeTrack then
		activeTrack:Stop(0.15)
	end

	if newTrack then
		newTrack.Looped = true
		newTrack:Play(0.15)
	end

	activeTrack = newTrack
end

--------------------------------------------------
-- HELPER: watch for external systems
--------------------------------------------------

local function connectExternalControlWatcher(char)

	char:GetAttributeChangedSignal("IsHanging"):Connect(function()

		if char:GetAttribute("IsHanging") then
			stopMovementAnimations()
		end
	end)

	char:GetAttributeChangedSignal("IsClimbing"):Connect(function()

		if char:GetAttribute("IsClimbing") then
			stopMovementAnimations()
		end
	end)

	char:GetAttributeChangedSignal("IsCrawlingThrough"):Connect(function()

		if char:GetAttribute("IsCrawlingThrough") then
			stopMovementAnimations()
		end
	end)

	char:GetAttributeChangedSignal("IsCoopClimbing"):Connect(function()

		if char:GetAttribute("IsCoopClimbing") then
			stopMovementAnimations()
		end
	end)

	char:GetAttributeChangedSignal("IsTurningValve"):Connect(function()

		if char:GetAttribute("IsTurningValve") then
			stopMovementAnimations()
		end
	end)

	char:GetAttributeChangedSignal("IsFuelAction"):Connect(function()

		if char:GetAttribute("IsFuelAction") then

			isSprinting = false
			isCrouching = false
			isCrawling = false

			currentState = "Walk"

			stopMovementAnimations()
		end
	end)

	-- holding a door shut: DoorClient poses your whole body against it
	char:GetAttributeChangedSignal("IsBarricading"):Connect(function()

		if char:GetAttribute("IsBarricading") then

			isSprinting = false
			isCrouching = false
			isCrawling = false

			currentState = "Walk"

			stopMovementAnimations()
		end
	end)
end

connectExternalControlWatcher(character)

--------------------------------------------------
-- CHARACTER RESPAWN HANDLING
--------------------------------------------------

local function onCharacterAdded(newCharacter)

	character = newCharacter

	humanoid = character:WaitForChild("Humanoid")
	hrp = character:WaitForChild("HumanoidRootPart")
	animator = humanoid:WaitForChild("Animator")

	humanoid.AutoRotate = true
	noJumping(humanoid)

	loadTracks()

	activeTrack = nil
	activeStartTrack = nil

	yaw = 0
	pitch = 0

	currentSpeed = SPEEDS.Walk

	isSprinting = false
	isCrouching = false
	isCrawling = false

	currentState = "Walk"

	stamina = STAMINA_MAX
	exhausted = false
	sentStance = nil

	wasClimbing = false
	climbCamActive = false
	blendTimeLeft = 0
	blendFromCFrame = nil

	trauma = 0

	horrorJoltClock = 0

	nextHorrorJolt = shakeRng:NextNumber(
		HORROR_JOLT_MIN_INTERVAL,
		HORROR_JOLT_MAX_INTERVAL
	)

	sprintJoltClock = 0

	nextSprintJolt = shakeRng:NextNumber(
		SPRINT_JOLT_MIN_INTERVAL,
		SPRINT_JOLT_MAX_INTERVAL
	)

	bobTime = 0
	bobIntensity = 0

	connectExternalControlWatcher(character)
end

player.CharacterAdded:Connect(onCharacterAdded)

--------------------------------------------------
-- MOUSE LOOK SETUP (first person)
--   T = toggle the mouse cursor free / locked
--------------------------------------------------

local cursorFree = false

UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
UserInputService.MouseIconEnabled = false

camera.CameraType = Enum.CameraType.Scriptable

-- Black cinematic bars top and bottom + a small dot in the center.
-- The bars are hidden during normal play; they slide in smoothly only for
-- cinematic moments (the character's "Cinematic" attribute, or being grabbed).
local hud = Instance.new("ScreenGui")
hud.Name = "FirstPersonHUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = 0
hud.Parent = player:WaitForChild("PlayerGui")

local LETTERBOX_HEIGHT = 0.1 -- fraction of the screen per bar, when they're in
local letterboxBars = {}
local letterboxNow = 0

for _, isTop in ipairs({ true, false }) do
	local bar = Instance.new("Frame")
	bar.Name = isTop and "TopBar" or "BottomBar"
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0, isTop and 0 or 1)
	bar.Position = UDim2.new(0, 0, isTop and 0 or 1, 0)
	bar.Size = UDim2.new(1, 0, 0, 0)
	bar.Parent = hud
	table.insert(letterboxBars, bar)
end

local crosshair = Instance.new("Frame")
crosshair.Name = "CenterDot"
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshair.Size = UDim2.new(0, 4, 0, 4)
crosshair.BackgroundColor3 = Color3.fromRGB(235, 230, 220)
crosshair.BackgroundTransparency = 0.2
crosshair.BorderSizePixel = 0
crosshair.Parent = hud

local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = crosshair

local dotStroke = Instance.new("UIStroke")
dotStroke.Color = Color3.new(0, 0, 0)
dotStroke.Transparency = 0.6
dotStroke.Thickness = 1
dotStroke.Parent = crosshair

local function setCursorFree(free)
	cursorFree = free
	crosshair.Visible = not free
	UserInputService.MouseIconEnabled = free
	UserInputService.MouseBehavior = free
		and Enum.MouseBehavior.Default
		or Enum.MouseBehavior.LockCenter
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		setCursorFree(not cursorFree)
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)

	if input.UserInputType == Enum.UserInputType.MouseMovement then

		-- Frozen while the cursor is free or a minigame UI has the mouse.
		local char = player.Character
		if cursorFree or (char and char:GetAttribute("UiFocus")) then
			return
		end

		-- (the menu's look-sensitivity setting scales it)
		local lookScale = player:GetAttribute("Sensitivity") or 1
		yaw = yaw - input.Delta.X * SENSITIVITY * lookScale

		pitch = math.clamp(
			pitch - input.Delta.Y * SENSITIVITY * lookScale,
			-MAX_PITCH,
			MAX_PITCH
		)
	end
end)

--------------------------------------------------
-- MOVEMENT STATE HANDLING
--------------------------------------------------

local function updateState()

	-- Carrying heavy fuel can:
	-- no sprinting, crouching or crawling.
	if character:GetAttribute("CarryingFuel") then

		isSprinting = false
		isCrouching = false
		isCrawling = false
	end

	-- No sprinting in the lobby (until the match starts).
	local lobbyFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Lobby")
	if lobbyFolder and lobbyFolder:GetAttribute("InMatch") ~= true then
		isSprinting = false
	end

	-- Determine state.

	if isCrawling then

		currentState = "Crawl"
		isSprinting = false

	elseif isCrouching then

		currentState = "Crouch"
		isSprinting = false

	elseif isSprinting and isMovingForward() and not exhausted then

		currentState = "Sprint"

	else

		currentState = "Walk"
		isSprinting = false
	end

	--------------------------------------------------
	-- LOOPING ANIMATIONS
	--------------------------------------------------

	-- Other scripts (e.g. the axe) read this to match your stance.
	character:SetAttribute("MoveState", currentState)

	-- and the server hears it too: the Crawler sees you less crouched or crawling
	if currentState ~= sentStance then
		sentStance = currentState
		local relay = game:GetService("ReplicatedStorage"):FindFirstChild("BodyMotion")
		if relay then
			relay:FireServer(currentState)
		end
	end

	if currentState == "Sprint" then

		if isMovingForward() then
			playStateAnimation("Sprint")
		else
			stopLoopAnimation()
		end

	elseif currentState == "Crawl" then

		if isMoving() then

			playStateAnimation("Crawl")

		else

			-- Stop crawling animation and hold
			-- the final crawl-start pose.
			stopLoopAnimation()

			if not activeStartTrack then
				holdPoseAtEnd("CrawlStart")
			end
		end

	elseif currentState == "Crouch" then

		if isMoving() then

			playStateAnimation("Crouch")

		else

			-- Stop crouching animation and hold
			-- the final crouch-start pose.
			stopLoopAnimation()

			if not activeStartTrack then
				holdPoseAtEnd("CrouchStart")
			end
		end

	elseif currentState == "Walk" then

		if isMoving() then

			playStateAnimation("Walk")

		else

			stopLoopAnimation()

		end
	end
end

--------------------------------------------------
-- INPUT BEGAN
--------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)

	if gameProcessed then
		return
	end

	if isExternallyControlled() then
		return
	end

	-- Hands are full with fuel can.
	if character:GetAttribute("CarryingFuel")
		and (
			input.KeyCode == Enum.KeyCode.C
				or input.KeyCode == Enum.KeyCode.X
		) then

		return
	end

	--------------------------------------------------
	-- SHIFT = SPRINT
	-- ONLY WORKS WITH W
	--------------------------------------------------

	if input.KeyCode == Enum.KeyCode.LeftShift then

		if not isCrouching
			and not isCrawling
			and isMovingForward() then

			isSprinting = true

		else

			isSprinting = false
		end

		updateState()

		--------------------------------------------------
		-- W
		--------------------------------------------------

	elseif input.KeyCode == Enum.KeyCode.W then

		if not isCrouching
			and not isCrawling
			and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then

			isSprinting = true
		end

		updateState()

		--------------------------------------------------
		-- CROUCH
		--------------------------------------------------

	elseif input.KeyCode == Enum.KeyCode.C then

		-- (no getting up inside a vent or under a low gap - CrawlFit)
		if isCrawling and character:GetAttribute("CrawlBlocked") then
			return
		end

		isCrouching = not isCrouching

		if isCrouching then

			isCrawling = false
			isSprinting = false

			-- Play crouch transition and freeze
			-- at the final crouched position.
			playStartAnimation("CrouchStart")

		else

			stopMovementAnimations()

		end

		updateState()

		--------------------------------------------------
		-- CRAWL
		--------------------------------------------------

	elseif input.KeyCode == Enum.KeyCode.X then

		if isCrawling and character:GetAttribute("CrawlBlocked") then
			return
		end

		isCrawling = not isCrawling

		if isCrawling then

			isCrouching = false
			isSprinting = false

			-- Play crawl transition and freeze
			-- at the final crawling position.
			playStartAnimation("CrawlStart")

		else

			stopMovementAnimations()

		end

		updateState()
	end
end)

--------------------------------------------------
-- INPUT ENDED
--------------------------------------------------

UserInputService.InputEnded:Connect(function(input, gameProcessed)

	if isExternallyControlled() then
		return
	end

	--------------------------------------------------
	-- SHIFT RELEASE
	--------------------------------------------------

	if input.KeyCode == Enum.KeyCode.LeftShift then

		isSprinting = false

		updateState()

		--------------------------------------------------
		-- W RELEASE
		--------------------------------------------------

	elseif input.KeyCode == Enum.KeyCode.W then

		-- Releasing W immediately stops sprint.
		isSprinting = false

		updateState()

		--------------------------------------------------
		-- MOVEMENT KEYS RELEASE
		--------------------------------------------------

	elseif input.KeyCode == Enum.KeyCode.A
		or input.KeyCode == Enum.KeyCode.S
		or input.KeyCode == Enum.KeyCode.D
		or input.KeyCode == Enum.KeyCode.Up
		or input.KeyCode == Enum.KeyCode.Down
		or input.KeyCode == Enum.KeyCode.Left
		or input.KeyCode == Enum.KeyCode.Right then

		updateState()
	end
end)

--------------------------------------------------
-- SPEED RAMPING
--------------------------------------------------

RunService.Heartbeat:Connect(function(dt)

	if isExternallyControlled() then
		return
	end

	local targetSpeed = SPEEDS[currentState]

	-- Heavy fuel can slows you down.
	if character:GetAttribute("CarryingFuel") then

		targetSpeed = math.min(
			targetSpeed,
			CARRY_FUEL_SPEED
		)
	end

	-- Badly hurt: limping slows you right down (adrenaline masks it).
	if isLimping() then
		if currentState == "Sprint" then
			targetSpeed = math.min(targetSpeed, SPEEDS.Walk * LIMP_RUN_FACTOR)
		else
			targetSpeed = targetSpeed * LIMP_WALK_FACTOR
		end
	end

	-- Adrenaline: faster walking and sprinting.
	if hasAdrenaline() then
		targetSpeed = targetSpeed * adrenalineMultiplier()
	end

	local rate =
		(targetSpeed > currentSpeed)
		and ACCELERATION[currentState]
		or DECELERATION

	if currentSpeed < targetSpeed then

		currentSpeed = math.min(
			currentSpeed + rate * dt,
			targetSpeed
		)

	elseif currentSpeed > targetSpeed then

		currentSpeed = math.max(
			currentSpeed - rate * dt,
			targetSpeed
		)
	end

	humanoid.WalkSpeed = currentSpeed
end)

--------------------------------------------------
-- SHAKE / TRAUMA SCHEDULING
--------------------------------------------------

local function addTrauma(amount)

	trauma = math.clamp(
		trauma + amount,
		0,
		1
	)
end

RunService.Heartbeat:Connect(function(dt)

	if isExternallyControlled() then
		return
	end

	-- Rare unsettling jolts.
	horrorJoltClock += dt

	if horrorJoltClock >= nextHorrorJolt then

		horrorJoltClock = 0

		nextHorrorJolt = shakeRng:NextNumber(
			HORROR_JOLT_MIN_INTERVAL,
			HORROR_JOLT_MAX_INTERVAL
		)

		addTrauma(HORROR_JOLT_TRAUMA)
	end

	-- Sprint jolts.
	if currentState == "Sprint" then

		sprintJoltClock += dt

		if sprintJoltClock >= nextSprintJolt then

			sprintJoltClock = 0

			nextSprintJolt = shakeRng:NextNumber(
				SPRINT_JOLT_MIN_INTERVAL,
				SPRINT_JOLT_MAX_INTERVAL
			)

			addTrauma(SPRINT_JOLT_TRAUMA)
		end

	else

		sprintJoltClock = 0
	end
end)

--------------------------------------------------
-- HELPER: CAMERA SHAKE OFFSET
--------------------------------------------------

local function getShakeCFrame(dt, stateName, scale)

	scale = scale or 1

	local settings = SHAKE[stateName] or SHAKE.Idle

	local t = os.clock() * settings.freq

	local nx = math.noise(
		t + shakeSeed.x,
		0,
		0
	)

	local ny = math.noise(
		t + shakeSeed.y,
		0,
		0
	)

	local nz = math.noise(
		t + shakeSeed.z,
		0,
		0
	)

	local nrx = math.noise(
		t + shakeSeed.rx,
		5,
		0
	)

	local nry = math.noise(
		t + shakeSeed.ry,
		5,
		0
	)

	local nrz = math.noise(
		t + shakeSeed.rz,
		5,
		0
	)

	local posX = nx * settings.amp
	local posY = ny * settings.amp
	local posZ = nz * settings.amp * 0.5

	local rotX = nrx * settings.rotAmp
	local rotY = nry * settings.rotAmp
	local rotZ = nrz * settings.rotAmp

	if trauma > 0 then

		local strength = trauma * trauma

		local jt = os.clock() * TRAUMA_JOLT_FREQ

		posX +=
			math.noise(jt, 11, 0)
			* strength
			* TRAUMA_POS_AMOUNT

		posY +=
			math.noise(jt, 22, 0)
			* strength
			* TRAUMA_POS_AMOUNT

		rotZ +=
			math.noise(jt, 33, 0)
			* strength
			* TRAUMA_ROT_AMOUNT

		rotX +=
			math.noise(jt, 44, 0)
			* strength
			* TRAUMA_ROT_AMOUNT
			* 0.5

		trauma = math.max(
			trauma - TRAUMA_DECAY * dt,
			0
		)
	end

	return CFrame.new(
		posX * scale,
		posY * scale,
		posZ * scale
	)
		* CFrame.Angles(
			rotX * scale,
			rotY * scale,
			rotZ * scale
		)
end

--------------------------------------------------
-- REALISTIC HEAD BOB
--------------------------------------------------

local function getCameraBobCFrame(dt)

	local settings = BOB[currentState] or BOB.Idle

	local movementAmount = humanoid.MoveDirection.Magnitude

	local isActuallyMoving =
		movementAmount > 0.05
		and not isExternallyControlled()

	local targetIntensity = isActuallyMoving
		and math.clamp(movementAmount, 0, 1)
		or 0

	-- Smoothly fade bob in/out.
	bobIntensity +=
		(targetIntensity - bobIntensity)
		* math.min(10 * dt, 1)

	-- Slightly change bob speed based on actual movement speed.
	local speedFactor = math.clamp(
		currentSpeed / math.max(SPEEDS[currentState], 1),
		0.65,
		1.2
	)

	bobTime +=
		dt
		* settings.frequency
		* speedFactor

	if bobIntensity < 0.001 then
		return CFrame.new()
	end

	--------------------------------------------------
	-- MAIN UP/DOWN BOB
	--------------------------------------------------

	local vertical =
		math.sin(bobTime * 2)
		* settings.vertical

	--------------------------------------------------
	-- SIDE TO SIDE
	--------------------------------------------------

	local horizontal =
		math.sin(bobTime)
		* settings.horizontal

	--------------------------------------------------
	-- SLIGHT FORWARD/BACK MOVEMENT
	--------------------------------------------------

	local forward =
		math.cos(bobTime * 2)
		* settings.forward

	--------------------------------------------------
	-- NATURAL ROLL
	--------------------------------------------------

	local roll =
		math.sin(bobTime)
		* settings.roll

	--------------------------------------------------
	-- SLIGHTLY REDUCE THE BOB WHEN SPRINT SHAKE
	-- IS ALREADY STRONG
	--------------------------------------------------

	local bobScale = bobIntensity

	return CFrame.new(
		horizontal * bobScale,
		vertical * bobScale,
		forward * bobScale
	)
		* CFrame.Angles(
			0,
			0,
			roll * bobScale
		)
end

--------------------------------------------------
-- HELPER: THIRD-PERSON CAMERA CFRAME
--------------------------------------------------

local function getThirdPersonCFrame(dt)

	local clampedPitch = math.clamp(
		pitch,
		-THIRD_PERSON_PITCH_LIMIT,
		THIRD_PERSON_PITCH_LIMIT
	)

	local focus =
		hrp.Position
		+ Vector3.new(
			0,
			THIRD_PERSON_HEIGHT,
			0
		)

	local orbitCFrame =
		CFrame.new(focus)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(clampedPitch, 0, 0)

	local desiredPosition =
		(
			orbitCFrame
			* CFrame.new(
				0,
				0,
				THIRD_PERSON_DISTANCE
			)
		).Position

	local toCamera =
		desiredPosition - focus

	local cameraDirection =
		toCamera.Unit

	local cameraDistance =
		toCamera.Magnitude

	local rayParams =
		RaycastParams.new()

	rayParams.FilterType =
		Enum.RaycastFilterType.Exclude

	rayParams.FilterDescendantsInstances =
		{ character }

	local rayStart =
		focus
		+ (
			cameraDirection
			* THIRD_PERSON_MIN_DISTANCE
		)

	local rayLength =
		math.max(
			cameraDistance
			- THIRD_PERSON_MIN_DISTANCE,
			0
		)

	local finalPosition =
		desiredPosition

	if rayLength > 0 then

		local result =
			workspace:Raycast(
				rayStart,
				cameraDirection * rayLength,
				rayParams
			)

		if result then

			local hitDistance =
				(result.Position - focus).Magnitude

			local safeDistance =
				math.max(
					hitDistance - 0.3,
					THIRD_PERSON_MIN_DISTANCE
				)

			finalPosition =
				focus
				+ (
					cameraDirection
					* safeDistance
				)
		end
	end

	local minY =
		hrp.Position.Y
		+ THIRD_PERSON_MIN_HEIGHT_OFFSET

	if finalPosition.Y < minY then

		finalPosition =
			Vector3.new(
				finalPosition.X,
				minY,
				finalPosition.Z
			)
	end

	local currentPos =
		camera.CFrame.Position

	local smoothPosition =
		currentPos:Lerp(
			finalPosition,
			math.min(
				THIRD_PERSON_LERP_SPEED * dt,
				1
			)
		)

	--------------------------------------------------
	-- CAMERA BOB
	--------------------------------------------------

	local bobCFrame =
		getCameraBobCFrame(dt)

	--------------------------------------------------
	-- CAMERA SHAKE
	--------------------------------------------------

	local shakeCFrame =
		getShakeCFrame(
			dt,
			currentState,
			0.5
		)

	return CFrame.new(
		smoothPosition,
		focus
	)
		* bobCFrame
		* ((player:GetAttribute("CameraShake") == false) and CFrame.identity or shakeCFrame)
end

--------------------------------------------------
-- HELPER: LOCKED CINEMATIC CLIMB CAMERA
--------------------------------------------------

local function getClimbCamCFrame(dt)

	local bodyYaw =
		select(
			2,
			hrp.CFrame:ToOrientation()
		)

	local basis =
		CFrame.new(hrp.Position)
		* CFrame.Angles(
			0,
			bodyYaw,
			0
		)

	local desiredPosition =
		(
			basis
			* CFrame.new(
				CLIMB_CAM_SIDE,
				CLIMB_CAM_UP,
				CLIMB_CAM_BACK
			)
		).Position

	local lookAt =
		hrp.Position
		+ Vector3.new(
			0,
			CLIMB_CAM_LOOK_HEIGHT,
			0
		)

	local rayParams =
		RaycastParams.new()

	rayParams.FilterType =
		Enum.RaycastFilterType.Exclude

	rayParams.FilterDescendantsInstances =
		{ character }

	local toCamera =
		desiredPosition - lookAt

	local direction =
		toCamera.Unit

	local distance =
		toCamera.Magnitude

	local rayStart =
		lookAt
		+ (
			direction
			* THIRD_PERSON_MIN_DISTANCE
		)

	local rayLength =
		math.max(
			distance
			- THIRD_PERSON_MIN_DISTANCE,
			0
		)

	local finalPosition =
		desiredPosition

	if rayLength > 0 then

		local result =
			workspace:Raycast(
				rayStart,
				direction * rayLength,
				rayParams
			)

		if result then

			local hitDistance =
				(result.Position - lookAt).Magnitude

			local safeDistance =
				math.max(
					hitDistance - 0.3,
					THIRD_PERSON_MIN_DISTANCE
				)

			finalPosition =
				lookAt
				+ (
					direction
					* safeDistance
				)
		end
	end

	local currentPos =
		camera.CFrame.Position

	local smoothPosition =
		currentPos:Lerp(
			finalPosition,
			math.min(
				CLIMB_CAM_ENTER_SPEED * dt,
				1
			)
		)

	return CFrame.new(
		smoothPosition,
		lookAt
	)
end

--------------------------------------------------
-- FIRST-PERSON CAMERA
--------------------------------------------------
-- The camera sits at your character's actual (animated) head, so every
-- animation - hanging, climbing, turning valves, carrying/pouring fuel,
-- crouching, crawling - is seen through your own eyes, and looking down
-- shows your real arms and body. Only the head is hidden.

local EYE_UP = 0.15          -- eye height above the head's center
local EYE_FORWARD = 0.15     -- eyes sit at the front of the head
local LOCKED_LOOK_LIMIT = math.rad(80) -- how far you can look sideways while hanging/climbing/etc.

-- Left/right sway
local STRAFE_ROLL_MAX = math.rad(3.2)   -- tilt when walking sideways
local STRAFE_ROLL_SPEED = 6
local TURN_ROLL_AMOUNT = 0.012          -- tilt when turning the mouse fast
local TURN_ROLL_MAX = math.rad(2.2)

local strafeRoll = 0
local turnRoll = 0
local lastYaw = yaw
local lastBodyYaw = nil
local lookDownOffset = 0
local trapThirdPersonBlend = 0
local TRAP_CAMERA_BLEND_SPEED = 4.5

local function angleDiff(a, b)
	local d = (a - b) % (2 * math.pi)
	if d > math.pi then
		d -= 2 * math.pi
	end
	return d
end

-- Head position from the joints (includes whatever animation is playing).
local function getHeadCFrame()
	local torso = character:FindFirstChild("Torso")
	local head = character:FindFirstChild("Head")
	local rootJoint = hrp:FindFirstChild("RootJoint")
	local neck = torso and torso:FindFirstChild("Neck")

	if rootJoint and neck then
		local torsoCF = hrp.CFrame * rootJoint.C0 * rootJoint.Transform * rootJoint.C1:Inverse()
		return torsoCF * neck.C0 * neck.Transform * neck.C1:Inverse()
	end

	return head and head.CFrame or hrp.CFrame * CFrame.new(0, 1.5, 0)
end

local function hideHead(transparency)
	local hidden = transparency == nil and 1 or transparency
	local head = character:FindFirstChild("Head")
	if head then
		head.LocalTransparencyModifier = hidden
	end
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Accessory") then
			local handle = item:FindFirstChild("Handle")
			if handle then
				handle.LocalTransparencyModifier = hidden
			end
		end
	end
end

-- In normal movement your body turns with the camera (FPS style).
RunService.Heartbeat:Connect(function(dt)
	if not hrp or not hrp.Parent or hrp.Anchored then
		return
	end
	if isExternallyControlled() then
		return
	end

	humanoid.AutoRotate = false

	local _, currentYaw, _ = hrp.CFrame:ToOrientation()
	local newYaw = currentYaw + angleDiff(yaw, currentYaw) * math.min(18 * dt, 1)
	hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, newYaw, 0)
end)

--------------------------------------------------
-- STAMINA
--------------------------------------------------
-- Sprinting burns it; anything else gets it back. Run it dry and you're
-- spent: you drop back to a walk and can't sprint again until you've got your
-- breath back (RECOVER_AT). Until then your heart thuds in your ears, your
-- sight tightens on every beat, and small white sparks flicker at the edges
-- of your vision, fading as you recover.
--   * your stamina bar can read the character's "Stamina" (0-100) and
--     "Exhausted" attributes
--   * roles: the "StaminaMultiplier" attribute makes it last longer
--   * adrenaline: you don't tire while it lasts

local STAMINA_DRAIN = 14          -- per second of sprinting (about 7 seconds from full)
local STAMINA_REGEN = 11          -- per second walking, once you've stopped sprinting
local STAMINA_REGEN_STILL = 17    -- standing still you get it back faster
local STAMINA_REGEN_DELAY = 0.9   -- seconds after sprinting before it starts coming back
local RECOVER_AT = 35             -- spent: no sprinting until it's back up to this

local HEARTBEAT_SOUND = "rbxassetid://3012160995"
local GASP_SOUND = "rbxassetid://9114555699"

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

-- (tells the HUD's stamina bar to show this count instead of keeping its own)
player:SetAttribute("StaminaFromCamera", true)

local lastSprintAt = 0
local strain = 0                 -- 0 fine .. 1 just ran dry (eases in and out)
local staminaPulse = 0           -- 0..1 on each heartbeat (the camera's FOV uses it)
local shownStamina, shownExhausted, shownOn = nil, nil, nil

local staminaGui = Instance.new("ScreenGui")
staminaGui.Name = "StaminaFX"
staminaGui.ResetOnSpawn = false
staminaGui.IgnoreGuiInset = true
staminaGui.DisplayOrder = 3
staminaGui.Parent = player:WaitForChild("PlayerGui")

-- the edges: darkening with each beat, and a faint white glow under the sparks
local function edgeSet(color)
	local list = {}
	for _, spec in ipairs({
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90 },
		{ UDim2.fromScale(0, 0.78), UDim2.fromScale(1, 0.22), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.16, 1), 0 },
		{ UDim2.fromScale(0.84, 0), UDim2.fromScale(0.16, 1), 180 },
	}) do
		local f = Instance.new("Frame")
		f.Position = spec[1]
		f.Size = spec[2]
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = staminaGui
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		table.insert(list, f)
	end
	return list
end
local darkEdges = edgeSet(Color3.fromRGB(6, 4, 4))
local whiteEdges = edgeSet(Color3.fromRGB(255, 255, 255))

-- one little white flash somewhere near the edge of your sight
local staminaRng = Random.new()
local function spark(strength)
	local side = staminaRng:NextInteger(1, 4)
	local along = staminaRng:NextNumber(0.05, 0.95)
	local depth = staminaRng:NextNumber(0.005, 0.07)
	local x, y
	if side == 1 then
		x, y = along, depth
	elseif side == 2 then
		x, y = along, 1 - depth
	elseif side == 3 then
		x, y = depth * 0.7, along
	else
		x, y = 1 - depth * 0.7, along
	end
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = staminaRng:NextNumber(0.05, 0.35)
	if staminaRng:NextNumber() < 0.4 then
		-- a streak, pointing in towards the middle
		f.Size = UDim2.fromOffset(2, staminaRng:NextInteger(8, 20))
		f.Rotation = math.deg(math.atan2(0.5 - y, 0.5 - x)) + 90
	else
		local size = staminaRng:NextInteger(2, 6)
		f.Size = UDim2.fromOffset(size, size)
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = f
	end
	local glow = Instance.new("UIStroke")
	glow.Color = Color3.new(1, 1, 1)
	glow.Thickness = 1
	glow.Transparency = 0.6
	glow.Parent = f
	f.Parent = staminaGui
	local life = staminaRng:NextNumber(0.12, 0.35) * (0.7 + 0.5 * strength)
	TweenService:Create(f, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1, Size = f.Size + UDim2.fromOffset(2, 2) }):Play()
	TweenService:Create(glow, TweenInfo.new(life), { Transparency = 1 }):Play()
	task.delay(life + 0.05, function()
		f:Destroy()
	end)
end

local heartbeatSound = Instance.new("Sound")
heartbeatSound.Name = "ExhaustedHeartbeat"
heartbeatSound.SoundId = HEARTBEAT_SOUND
heartbeatSound.Looped = true
heartbeatSound.Volume = 0
heartbeatSound.Parent = SoundService

local loudPeak = 1
local wasBeat = false
local lastBeatAt = 0
local nextSparkAt = 0

local function runOutOfBreath()
	exhausted = true
	isSprinting = false
	updateState()
	local gasp = Instance.new("Sound")
	gasp.SoundId = GASP_SOUND
	gasp.Volume = 0.45
	gasp.PlaybackSpeed = 0.85
	gasp.Parent = SoundService
	gasp:Play()
	gasp.Ended:Connect(function()
		gasp:Destroy()
	end)
	addTrauma(0.12)
end

RunService.Heartbeat:Connect(function(dt)
	if not character or not hrp or not hrp.Parent then
		return
	end
	local now = os.clock()
	local velocity = hrp.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 2

	-- burn it sprinting, get it back otherwise
	if currentState == "Sprint" and moving and not isExternallyControlled() then
		lastSprintAt = now
		if not hasAdrenaline() then
			local lasts = math.max(character:GetAttribute("StaminaMultiplier") or 1, 0.1)
			stamina = math.max(stamina - STAMINA_DRAIN / lasts * dt, 0)
		end
		if stamina <= 0 and not exhausted then
			runOutOfBreath()
		end
	elseif now - lastSprintAt > STAMINA_REGEN_DELAY then
		stamina = math.min(stamina + (moving and STAMINA_REGEN or STAMINA_REGEN_STILL) * dt, STAMINA_MAX)
	end

	-- got your breath back
	if exhausted and stamina >= RECOVER_AT then
		exhausted = false
		-- (still holding Shift and W: off you go again)
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and isMovingForward()
			and not isCrouching and not isCrawling and not isExternallyControlled() then
			isSprinting = true
			updateState()
		end
	end

	-- for the stamina bar (and again on every new character)
	if shownOn ~= character then
		shownOn = character
		shownStamina, shownExhausted = nil, nil
	end
	local rounded = math.floor(stamina * 10 + 0.5) / 10
	if rounded ~= shownStamina then
		shownStamina = rounded
		character:SetAttribute("Stamina", rounded)
		character:SetAttribute("MaxStamina", STAMINA_MAX)
	end
	if exhausted ~= shownExhausted then
		shownExhausted = exhausted
		character:SetAttribute("Exhausted", exhausted)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	-- how hard it's hitting you: all at once when you run dry, easing off as
	-- your breath comes back
	local want = exhausted and math.clamp(1 - stamina / RECOVER_AT * 0.75, 0.25, 1) or 0
	strain += (want - strain) * math.min(dt * (want > strain and 6 or 0.9), 1)

	-- the heartbeat: louder and faster the worse it is; the screen follows
	-- the sound itself, so every thump lands with what you see
	if strain > 0.01 then
		if not heartbeatSound.IsPlaying then
			heartbeatSound:Play()
		end
		heartbeatSound.Volume = 0.55 * strain
		heartbeatSound.PlaybackSpeed = 1 + 0.4 * strain
	elseif heartbeatSound.IsPlaying then
		heartbeatSound:Stop()
	end
	local loud = heartbeatSound.IsPlaying and heartbeatSound.PlaybackLoudness or 0
	loudPeak = math.max(loudPeak * (1 - dt * 0.3), loud, 1)
	local beat = math.clamp((loud / loudPeak - 0.25) / 0.6, 0, 1) * strain
	staminaPulse += (beat - staminaPulse) * math.min(dt * 25, 1)

	for _, e in ipairs(darkEdges) do
		e.BackgroundTransparency = 1 - (0.25 * strain + 0.4 * staminaPulse)
	end
	for _, e in ipairs(whiteEdges) do
		e.BackgroundTransparency = 1 - 0.1 * staminaPulse
	end

	-- small white flashes at the edges: a burst on each thump, a few between
	local isBeat = beat > 0.5
	if isBeat and not wasBeat and now - lastBeatAt > 0.15 then
		lastBeatAt = now
		for _ = 1, math.floor(2 + 4 * strain) do
			spark(strain)
		end
	end
	wasBeat = isBeat
	if strain > 0.05 and now >= nextSparkAt then
		nextSparkAt = now + staminaRng:NextNumber(0.08, 0.35) / strain
		spark(strain * 0.6)
	end
end)

RunService:BindToRenderStep("HorrorFirstPersonCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not hrp or not hrp.Parent then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	-- Cinematic bars: slide in for cinematic moments, out again after.
	local cinematic = character:GetAttribute("Cinematic") == true or character:GetAttribute("BeingKilled") == true
	letterboxNow += ((cinematic and LETTERBOX_HEIGHT or 0) - letterboxNow) * math.min(3 * dt, 1)
	for _, bar in ipairs(letterboxBars) do
		bar.Size = UDim2.new(1, 0, letterboxNow, 0)
	end

	-- Third person in the lobby while voting and choosing (and in a bear trap);
	-- from the blackout on - the elevator, the ride down, the cutscene - it's
	-- first person again. Blended, so it never snaps.
	local lobbyFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Lobby")
	local lobbyPhase = lobbyFolder and lobbyFolder:GetAttribute("Phase")
	local inLobby = lobbyFolder ~= nil and lobbyFolder:GetAttribute("InMatch") ~= true
		and character:GetAttribute("InCutscene") ~= true
		and (lobbyPhase == "Voting" or lobbyPhase == "Roles" or lobbyPhase == "Countdown")
	local targetTrapCameraBlend = (character:GetAttribute("IsBearTrapped") == true or inLobby) and 1 or 0
	local thirdPersonSetup = inLobby and LOBBY_CAMERA or TRAP_CAMERA
	THIRD_PERSON_DISTANCE += (thirdPersonSetup.distance - THIRD_PERSON_DISTANCE) * math.min(4 * dt, 1)
	THIRD_PERSON_HEIGHT += (thirdPersonSetup.height - THIRD_PERSON_HEIGHT) * math.min(4 * dt, 1)
	trapThirdPersonBlend += (targetTrapCameraBlend - trapThirdPersonBlend)
		* math.min(TRAP_CAMERA_BLEND_SPEED * dt, 1)
	hideHead(1 - trapThirdPersonBlend)

	-- Keep the mouse locked (Roblox sometimes releases it, e.g. after menus),
	-- unless the cursor is toggled free with T or a minigame needs it.
	local wantFreeCursor = cursorFree or character:GetAttribute("UiFocus") == true

	if wantFreeCursor then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		UserInputService.MouseIconEnabled = true
		crosshair.Visible = false
	else
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		UserInputService.MouseIconEnabled = false
		crosshair.Visible = trapThirdPersonBlend < 0.5     -- no dot in third person
	end

	--------------------------------------------------
	-- SPRINT FOV
	--------------------------------------------------

	local targetFOV = (currentState == "Sprint") and SPRINT_FOV or NORMAL_FOV
	if hasAdrenaline() then
		targetFOV += ADRENALINE_FOV_BONUS
	end
	-- out of breath: your sight tightens a little with every heartbeat
	targetFOV -= staminaPulse * 3
	camera.FieldOfView += (targetFOV - camera.FieldOfView) * math.min(FOV_LERP_SPEED * dt, 1)

	--------------------------------------------------
	-- LOOK DIRECTION
	--------------------------------------------------

	local locked = isExternallyControlled()
	local _, bodyYaw, _ = hrp.CFrame:ToOrientation()

	-- While another system holds the body (ledge, climb, valve, fuel...)
	-- you can still look around, just not behind yourself.
	if locked then
		-- Measure the look offset against where the body faced LAST frame,
		-- so when the body turns (e.g. going around a ledge corner) the
		-- view turns with it.
		local reference = lastBodyYaw or bodyYaw
		local offset = math.clamp(angleDiff(yaw, reference), -LOCKED_LOOK_LIMIT, LOCKED_LOOK_LIMIT)
		yaw = bodyYaw + offset
		lastYaw = yaw
	end
	lastBodyYaw = bodyYaw

	-- Animations (bandage, adrenaline) can tilt your view down so you see
	-- your own hands. Eased so it never snaps.
	local wantLookDown = math.rad(character:GetAttribute("LookDownDegrees") or 0)
	lookDownOffset += (wantLookDown - lookDownOffset) * math.min(6 * dt, 1)
	local viewPitch = math.clamp(pitch - lookDownOffset, -math.rad(88), math.rad(88))

	local look = CFrame.Angles(0, yaw, 0) * CFrame.Angles(viewPitch, 0, 0)

	--------------------------------------------------
	-- EYE POSITION (the animated head)
	--------------------------------------------------

	local headCF = getHeadCFrame()
	local eye = headCF.Position + headCF.UpVector * EYE_UP + headCF.LookVector * EYE_FORWARD

	--------------------------------------------------
	-- LEFT / RIGHT SWAY
	--------------------------------------------------

	local velocity = hrp.AssemblyLinearVelocity
	local localVelocity = CFrame.Angles(0, yaw, 0):VectorToObjectSpace(velocity)

	local strafeTarget = 0
	if not locked then
		strafeTarget = -math.clamp(localVelocity.X / math.max(SPEEDS[currentState], 1), -1, 1) * STRAFE_ROLL_MAX
	end
	strafeRoll += (strafeTarget - strafeRoll) * math.min(STRAFE_ROLL_SPEED * dt, 1)

	local yawRate = angleDiff(yaw, lastYaw) / math.max(dt, 1 / 240)
	lastYaw = yaw
	local turnTarget = math.clamp(-yawRate * TURN_ROLL_AMOUNT, -TURN_ROLL_MAX, TURN_ROLL_MAX)
	turnRoll += (turnTarget - turnRoll) * math.min(8 * dt, 1)

	--------------------------------------------------
	-- BOB + SHAKE
	--------------------------------------------------

	local bob = getCameraBobCFrame(dt)
	local shake = getShakeCFrame(dt, currentState, locked and 0.3 or 0.8)

	-- Something grabbed you: your view is dragged onto it (LookAtOverride
	-- is an ObjectValue a monster puts on your character).
	local override = character:FindFirstChild("LookAtOverride")
	if override and override:IsA("ObjectValue") and override.Value and override.Value:IsA("BasePart") then
		local toTarget = override.Value.Position - eye
		if toTarget.Magnitude > 0.05 then
			local forced = CFrame.lookAt(Vector3.zero, toTarget.Unit)
			look = look:Lerp(forced, math.min(10 * dt, 1))
			-- keep the mouse angles in step so nothing snaps afterwards
			local rx, ry = look:ToOrientation()
			pitch = math.clamp(rx, -MAX_PITCH, MAX_PITCH)
			yaw = ry
		end
	end

	-- Hard impacts (being slammed into the floor) shake the view.
	local impact = CFrame.identity
	local shakeUntil = character:GetAttribute("ShakeUntil")
	if shakeUntil and os.clock() < shakeUntil then
		local strength = math.rad(character:GetAttribute("ShakeAmount") or 3)
			* math.clamp((shakeUntil - os.clock()) / 0.35, 0, 1)
		impact = CFrame.Angles(
			(math.random() - 0.5) * strength,
			(math.random() - 0.5) * strength,
			(math.random() - 0.5) * strength
		)
	end

	local firstPersonCFrame = CFrame.new(eye)
		* look
		* bob
		* CFrame.Angles(0, 0, strafeRoll + turnRoll)
		* ((player:GetAttribute("CameraShake") == false) and CFrame.identity or shake)
		* impact

	if trapThirdPersonBlend > 0.001 then
		local thirdPersonCFrame = getThirdPersonCFrame(dt)
		camera.CFrame = firstPersonCFrame:Lerp(thirdPersonCFrame, trapThirdPersonBlend)
	else
		camera.CFrame = firstPersonCFrame
	end
end)
