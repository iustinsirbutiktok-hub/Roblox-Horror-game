-- CamcorderClient
-- Place in: StarterPlayer > StarterPlayerScripts
--
-- The Outlast camcorder:
--   RIGHT MOUSE  raise / lower. It swings up from the bottom-right in your
--                right hand, the flip-out screen (already showing the green
--                night vision) rushes to your eye, and you're looking through
--                it. Lowering is the same in reverse.
--   R            swap the battery: the camcorder comes up and turns round,
--                your left hand pops the latch, the old pack slides out and
--                drops, a fresh one slides in - click - beep.
--   V            (while it's up) night vision on / off. Off: the plain, dark
--                picture - and the battery doesn't drain.
--                (F uses the item in your right hand - MedicalClient: the
--                camcorder comes down for it and goes back up after.)
--   LEFT CLICK   (while it's up) the flash. It needs 20s to charge, blinds a
--                monster in front of you (PhotoServer) and, for the blink it
--                lasts, shows what your eyes can't (ReplicatedStorage.FlashReveal).
--
-- Night vision drains the battery (only while it's up). Spares are the
-- "Batteries" you pick up; they sit in your item slots.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local event = ReplicatedStorage:WaitForChild("CamcorderState")
local photoEvent = ReplicatedStorage:WaitForChild("PhotoEvent", 30)
local Reveal = require(ReplicatedStorage:WaitForChild("FlashReveal"))
local assets = ReplicatedStorage:WaitForChild("CamcorderAssets")
local template = assets:WaitForChild("CamcorderViewmodel")

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local RAISE_KEY = Enum.UserInputType.MouseButton2
local RELOAD_KEY = Enum.KeyCode.R
local NIGHT_KEY = Enum.KeyCode.V

local RAISE_TIME = 0.26          -- up to your eye (the clip: about a quarter second)
local LOWER_TIME = 0.32
local RELOAD_TIME = assets:GetAttribute("ReloadTime") or 2.6
local LOW_BATTERY = 15           -- percent: the picture starts to fail

local FONT = Enum.Font.SpecialElite
local BONE = Color3.fromRGB(214, 206, 190)
local NV_TEXT = Color3.fromRGB(210, 238, 210)

local SOUND = {
	raise = "rbxassetid://9113677274",       -- camera motor and mechanical handling
	click = "rbxassetid://9114213314",       -- soft mechanical latch click
	static = "rbxassetid://9116279560",      -- keep the existing night-vision static burst
	whine = "rbxassetid://111151736519936",  -- quiet electrical hum
	recordTick = "rbxassetid://103219244632028", -- short recorder beep
	reload = "rbxassetid://9113669127",      -- camera door and mechanism handling
}
local FLASH_COOLDOWN = 20

-- where the camcorder sits in front of the camera (camera space)
local OFF_SCREEN = CFrame.new(0.95, -1.75, -1.05) * CFrame.Angles(math.rad(38), math.rad(-28), math.rad(32))
local HELD = CFrame.new(0.42, -0.52, -1.08) * CFrame.Angles(math.rad(8), math.rad(-14), math.rad(-6))
-- (EYE is worked out below: the screen dead centre, right in front of you)
-- battery swap: held out in front, tipped so its back and underside (where the
-- battery pack sits) face you. (Held normally the back already faces you.)
local INSPECT = CFrame.new(0.18, -0.46, -1.45) * CFrame.Angles(math.rad(-28), math.rad(-32), math.rad(8))

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function smooth(a)
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function easeOut(a)
	a = math.clamp(a, 0, 1)
	return 1 - (1 - a) ^ 3
end

local function easeIn(a)
	a = math.clamp(a, 0, 1)
	return a ^ 3
end

local function new(class, props, parent)
	local obj = Instance.new(class)
	for k, v in pairs(props) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function sound(id, volume, speed)
	local s = new("Sound", { SoundId = id, Volume = volume, PlaybackSpeed = speed or 1 }, workspace.CurrentCamera)
	s:Play()
	Debris:AddItem(s, 4)
	return s
end

local function charNow()
	return player.Character
end

-- when you can't use it
local HANDS_BUSY = { "HoldingAxe", "CarryingFuel", "HoldingFuse", "UsingMedical", "IsClimbing", "IsHanging",
	"IsCrawlingThrough", "IsTurningValve", "IsFuelAction", "IsLeverPush", "IsFuseRepair", "IsTightSqueeze",
	"IsAxeChop", "IsAxeInspect", "Downed", "BeingKilled", "InCutscene", "UiFocus", "CarryingPlayer", "BackpackOpen", "IsUnlocking", "IsMinigame" }

local function inMatch()
	local lobby = ReplicatedStorage:FindFirstChild("Lobby")
	return not lobby or lobby:GetAttribute("InMatch") == true
end

local function blocked()
	-- the crash cutscene raises it for you (waking up in the wreck)
	if player:GetAttribute("IntroCamcorder") then
		return false
	end
	local c = charNow()
	if not c or not inMatch() then
		return true
	end
	local h = c:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then
		return true
	end
	for _, name in ipairs(HANDS_BUSY) do
		if c:GetAttribute(name) then
			return true
		end
	end
	return false
end

--------------------------------------------------
-- THE CAMCORDER IN YOUR HANDS (only on your screen)
--------------------------------------------------

local camera = workspace.CurrentCamera
local vm = template:Clone()
vm.Name = "CamcorderInHand"
local pivotPart = vm.PrimaryPart or vm:FindFirstChild("main_body_chassis", true)
local parts, rest = {}, {}
local lcdParts = {}
local battery, latch, lcdPanel, tally
for _, d in ipairs(vm:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		table.insert(parts, d)
		-- hand-held: no tripod feet
		if d.Name:find("^foot_") or d.Name == "tripod_mount_plate" then
			d.Transparency = 1
		end
		if d.Name:find("^lcd_screen") or d.Name == "lcd_display_panel" or d.Name:find("^lcd_articulation") then
			lcdParts[d] = true
		end
		if d.Name == "battery_pack" then battery = d end
		if d.Name == "battery_release_latch" then latch = d end
		if d.Name == "lcd_display_panel" then lcdPanel = d end
		if d.Name == "tally_recording_led" then tally = d end
	elseif d:IsA("Light") or d:IsA("LuaSourceContainer") then
		d:Destroy()
	end
end
local pivot = pivotPart.CFrame
for _, p in ipairs(parts) do
	rest[p] = pivot:ToObjectSpace(p.CFrame)
end

-- Swing the flip-out screen open so it faces you (it hinges on the body's
-- front-left edge).
local HINGE = CFrame.new(-0.3, 0, -0.2)
local OPEN = HINGE * CFrame.Angles(0, math.rad(-90), 0) * HINGE:Inverse()
for p in pairs(lcdParts) do
	rest[p] = OPEN * rest[p]
end

-- The screen itself: a live-looking green picture with the recording overlay.
local screenGui, screenNoise
if lcdPanel then
	screenGui = new("SurfaceGui", { Face = Enum.NormalId.Right, LightInfluence = 0, CanvasSize = Vector2.new(240, 160),
		Brightness = 1.3 }, lcdPanel)
	local pic = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, screenGui)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 70, 48)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(120, 175, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 55, 38)),
	}) }, pic)
	screenNoise = {}
	for i = 1, 24 do
		screenNoise[i] = new("Frame", { Size = UDim2.fromOffset(math.random(3, 9), 2), BackgroundColor3 = Color3.fromRGB(200, 240, 205),
			BackgroundTransparency = 0.5, BorderSizePixel = 0 }, pic)
	end
	new("TextLabel", { Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(60, 18), BackgroundTransparency = 1,
		Font = FONT, TextSize = 16, TextColor3 = Color3.fromRGB(255, 70, 60), Text = "REC", TextXAlignment = Enum.TextXAlignment.Left }, pic)
end

-- Your hands: a gloved right hand round the grip, and a left hand for the
-- battery. Coloured from your own character.
local hands = {}
local function handPart(name, size, colour)
	local p = new("Part", { Name = name, Size = size, Color = colour, Material = Enum.Material.Fabric, Anchored = true,
		CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }, vm)
	hands[p] = true
	return p
end
local skin = Color3.fromRGB(196, 150, 118)
local sleeve = Color3.fromRGB(40, 42, 46)
local rightPalm = handPart("RightPalm", Vector3.new(0.13, 0.42, 0.36), skin)
local rightFingers = handPart("RightFingers", Vector3.new(0.3, 0.1, 0.34), skin)
local rightThumb = handPart("RightThumb", Vector3.new(0.08, 0.08, 0.22), skin)
local rightSleeve = handPart("RightSleeve", Vector3.new(0.36, 0.36, 1.6), sleeve)
local leftPalm = handPart("LeftPalm", Vector3.new(0.34, 0.12, 0.3), skin)
local leftFingers = handPart("LeftFingers", Vector3.new(0.3, 0.09, 0.22), skin)
local leftSleeve = handPart("LeftSleeve", Vector3.new(0.34, 0.34, 1.5), sleeve)
local function colourHands()
	local c = charNow()
	local arm = c and c:FindFirstChild("Right Arm")
	local torso = c and c:FindFirstChild("Torso")
	local s = arm and arm.Color or skin
	local shirt = torso and torso.Color or sleeve
	for _, p in ipairs({ rightPalm, rightFingers, rightThumb, leftPalm, leftFingers }) do
		p.Color = s
	end
	rightSleeve.Color = shirt:Lerp(Color3.new(0, 0, 0), 0.25)
	leftSleeve.Color = rightSleeve.Color
end

-- the right hand sits on the grip, in the camcorder's own space
local RIGHT_HAND = {
	[rightPalm] = CFrame.new(0.43, -0.02, 0.03),
	[rightFingers] = CFrame.new(0.3, 0.24, 0.03),
	[rightThumb] = CFrame.new(0.3, -0.16, -0.2),
	[rightSleeve] = CFrame.new(0.62, -0.35, 0.95) * CFrame.Angles(math.rad(22), math.rad(-18), 0),
}

vm.Parent = nil      -- only in the world while you're using it

-- the spare battery the left hand brings in, and the old one it drops
local newBattery = battery and battery:Clone()
if newBattery then
	newBattery.Name = "FreshBattery"
	newBattery.Parent = nil
end

-- EYE: the camcorder placed so its (opened) screen sits dead centre, right in
-- front of your eye, facing you. The screen already faces back at you once
-- it's swung open, so only the position needs working out.
local EYE
do
	local panelAt = (rest[lcdPanel] or CFrame.new(-0.6, 0, -0.4)).Position
	EYE = CFrame.new(-panelAt.X, -panelAt.Y, -0.34 - panelAt.Z)
end

local function place(camRel, extras)
	local base = camera.CFrame * camRel
	for _, p in ipairs(parts) do
		p.CFrame = base * rest[p]
	end
	for p, rel in pairs(RIGHT_HAND) do
		p.CFrame = base * rel
	end
	if extras then
		extras(base)
	end
	return base
end

local function showModel(on)
	vm.Parent = on and camera or nil
	if on then
		colourHands()
		leftPalm.Transparency, leftFingers.Transparency, leftSleeve.Transparency = 1, 1, 1
	end
end

--------------------------------------------------
-- THE VIEWFINDER (full screen while it's up)
--------------------------------------------------

local grade = new("ColorCorrectionEffect", { Name = "CamcorderNightVision", Enabled = false,
	TintColor = Color3.fromRGB(150, 255, 165), Brightness = 0.14, Contrast = 0.28, Saturation = -0.75 }, Lighting)
local bloom = new("BloomEffect", { Name = "CamcorderBloom", Enabled = false, Intensity = 0.7, Size = 30, Threshold = 0.82 }, Lighting)
-- night vision off: just the camcorder's own picture - dark, a bit flat
local plain = new("ColorCorrectionEffect", { Name = "CamcorderPlain", Enabled = false,
	TintColor = Color3.fromRGB(236, 238, 242), Brightness = -0.02, Contrast = 0.14, Saturation = -0.4 }, Lighting)
local nvOn = true

-- infrared: the night vision sees what your eyes can't (only on your screen)
local irPart = new("Part", { Name = "CamcorderIR", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Anchored = true,
	CanCollide = false, CanQuery = false, CanTouch = false }, nil)
local irBeam = new("SpotLight", { Brightness = 3.2, Range = 60, Angle = 75, Color = Color3.fromRGB(200, 255, 210),
	Shadows = true, Enabled = false }, irPart)
local irFill = new("PointLight", { Brightness = 0.55, Range = 24, Color = Color3.fromRGB(180, 255, 190), Enabled = false }, irPart)

local gui = new("ScreenGui", { Name = "CamcorderHUD", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 40,
	Enabled = false }, player:WaitForChild("PlayerGui"))

-- vignette: dark corners of a lens
for _, spec in ipairs({ { 0, 0, 90 }, { 0, 0.75, -90 }, { 0, 0, 0, true }, { 0.82, 0, 180, true } }) do
	local side = spec[4]
	local f = new("Frame", { Position = UDim2.fromScale(spec[1], spec[2]),
		Size = side and UDim2.fromScale(0.18, 1) or UDim2.fromScale(1, 0.25),
		BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, gui)
	new("UIGradient", { Rotation = spec[3], Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }) }, f)
end
-- scanlines and grain
for i = 0, 60 do
	new("Frame", { Position = UDim2.fromScale(0, i / 60), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.82, BorderSizePixel = 0 }, gui)
end
local grain = {}
for i = 1, 90 do
	grain[i] = new("Frame", { Size = UDim2.fromOffset(2, 2), BackgroundColor3 = Color3.fromRGB(220, 255, 225),
		BackgroundTransparency = 0.6, BorderSizePixel = 0 }, gui)
end
local staticFlash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(190, 230, 195),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, gui)

local function osd(text, pos, size, colour, anchorX)
	return new("TextLabel", { AnchorPoint = Vector2.new(anchorX or 0, 0), Position = pos, Size = size, BackgroundTransparency = 1,
		Font = FONT, TextScaled = true, TextColor3 = colour or NV_TEXT, TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Color3.fromRGB(5, 15, 8), Text = text,
		TextXAlignment = anchorX == 1 and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left, ZIndex = 3 }, gui)
end
local recDot = new("Frame", { Position = UDim2.new(0, 34, 0, 36), Size = UDim2.fromOffset(15, 15),
	BackgroundColor3 = Color3.fromRGB(235, 40, 32), BorderSizePixel = 0, ZIndex = 3 }, gui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, recDot)
osd("REC", UDim2.new(0, 56, 0, 30), UDim2.fromOffset(60, 26), Color3.fromRGB(235, 60, 50))
local timecode = osd("00:00:00:00", UDim2.new(0, 124, 0, 32), UDim2.fromOffset(150, 22), Color3.fromRGB(235, 60, 50))
-- zoom W - T at the top centre
osd("W", UDim2.new(0.5, -110, 0, 32), UDim2.fromOffset(18, 20))
osd("T", UDim2.new(0.5, 98, 0, 32), UDim2.fromOffset(18, 20))
new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, -4, 0, 40), Size = UDim2.fromOffset(170, 5),
	BackgroundColor3 = NV_TEXT, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 3 }, gui)
-- battery, top right
local batteryBox = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 32), Size = UDim2.fromOffset(56, 22),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, gui)
new("UIStroke", { Color = NV_TEXT, Thickness = 1.5 }, batteryBox)
new("Frame", { Position = UDim2.new(1, 1, 0.5, -4), Size = UDim2.fromOffset(4, 8), BackgroundColor3 = NV_TEXT, BorderSizePixel = 0, ZIndex = 3 }, batteryBox)
local cells = {}
for i = 1, 4 do
	cells[i] = new("Frame", { Position = UDim2.fromOffset(3 + (i - 1) * 13, 3), Size = UDim2.fromOffset(11, 16),
		BackgroundColor3 = NV_TEXT, BorderSizePixel = 0, ZIndex = 3 }, batteryBox)
end
-- (up out of the way of your health bar)
osd("HD", UDim2.new(0, 34, 1, -178), UDim2.fromOffset(40, 22))
osd("AUTO", UDim2.new(0, 34, 1, -154), UDim2.fromOffset(60, 22))
osd("F2.4", UDim2.new(0, 34, 1, -130), UDim2.fromOffset(60, 22))
local nightLabel = osd("NIGHT  [V]", UDim2.new(1, -40, 1, -56), UDim2.fromOffset(130, 22), NV_TEXT, 1)
-- the flash: charged or charging
local flashLabel = osd("FLASH", UDim2.new(1, -96, 1, -84), UDim2.fromOffset(70, 20), NV_TEXT, 1)
local flashBar = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 1, -78), Size = UDim2.fromOffset(50, 7),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, gui)
new("UIStroke", { Color = NV_TEXT, Thickness = 1 }, flashBar)
local flashFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = NV_TEXT, BorderSizePixel = 0, ZIndex = 3 }, flashBar)
local flashWasReady = true
local flashDudAt = 0
-- the flash going off (a white wash over everything)
local flashWash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(250, 252, 255), BackgroundTransparency = 1,
	BorderSizePixel = 0, ZIndex = 50 }, nil)
local washGui = new("ScreenGui", { Name = "CamcorderFlashWash", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 60 }, player.PlayerGui)
flashWash.Parent = washGui

--------------------------------------------------
-- THE LITTLE PANEL WHEN IT'S DOWN (top-left, where the headlamp one was)
--------------------------------------------------

local panelGui = new("ScreenGui", { Name = "CamcorderPanel", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 6 },
	player.PlayerGui)
local panel = new("Frame", { Position = UDim2.new(0, 24, 0, 22), Size = UDim2.fromOffset(200, 30), BackgroundColor3 = Color3.fromRGB(12, 11, 10),
	BackgroundTransparency = 0.35 }, panelGui)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, panel)
local shell = new("Frame", { Position = UDim2.new(0, 10, 0.5, -7), Size = UDim2.fromOffset(36, 14), BackgroundTransparency = 1 }, panel)
new("UIStroke", { Color = BONE, Thickness = 1.2 }, shell)
local panelFill = new("Frame", { Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = Color3.fromRGB(120, 200, 120),
	BorderSizePixel = 0 }, shell)
local panelText = new("TextLabel", { Position = UDim2.new(0, 54, 0, 0), Size = UDim2.new(1, -58, 1, 0), BackgroundTransparency = 1,
	Font = FONT, TextSize = 15, TextColor3 = BONE, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, panel)

local function updatePanel()
	local charge = player:GetAttribute("CamcorderCharge") or 0
	local spares = player:GetAttribute("Batteries") or 0
	panelFill.Size = UDim2.new(math.clamp(charge / 100, 0, 1), -4, 1, -4)
	panelFill.BackgroundColor3 = charge < LOW_BATTERY and Color3.fromRGB(220, 70, 55) or Color3.fromRGB(120, 200, 120)
	panelText.Text = string.format("%d%%   [RMB]   x%d [R]", math.floor(charge + 0.5), spares)
	for i, cell in ipairs(cells) do
		cell.Visible = charge > (i - 1) * 25
	end
end
player:GetAttributeChangedSignal("CamcorderCharge"):Connect(updatePanel)
player:GetAttributeChangedSignal("Batteries"):Connect(updatePanel)
updatePanel()

--------------------------------------------------
-- RAISING, LOWERING, RELOADING
--------------------------------------------------

local state = "down"      -- down / raising / up / lowering / reloading
local stateStart = 0
local stateBeeped = false
local reloadLatchClickPlayed = false
local lastRecordTickSecond = 0
local recStarted = os.clock()
local whine

-- the picture while the viewfinder is up: green night vision, or plain
local function applyMode(on)
	grade.Enabled = on and nvOn
	bloom.Enabled = on and nvOn
	plain.Enabled = on and not nvOn
	irBeam.Enabled = on and nvOn
	irFill.Enabled = on and nvOn
	irPart.Parent = (on and nvOn) and workspace or nil
	nightLabel.Text = nvOn and "NIGHT  [V]" or "STD  [V]"
	local ink = nvOn and NV_TEXT or Color3.fromRGB(226, 226, 220)
	for _, g in ipairs(grain) do
		g.BackgroundColor3 = nvOn and Color3.fromRGB(220, 255, 225) or Color3.fromRGB(200, 200, 200)
	end
	nightLabel.TextColor3 = ink
	flashLabel.TextColor3 = ink
end

local function startWhine()
	whine = whine or new("Sound", { SoundId = SOUND.whine, Volume = 0, PlaybackSpeed = 1, Looped = true }, camera)
	whine.PlaybackSpeed = 1
	whine:Play()
	TweenService:Create(whine, TweenInfo.new(0.4), { Volume = 0.024 }):Play()
end

local function nightVision(on)
	gui.Enabled = on
	applyMode(on)
	if on then
		-- a burst of static as the picture comes up
		staticFlash.BackgroundTransparency = 0.25
		TweenService:Create(staticFlash, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
		sound(SOUND.static, nvOn and 0.18 or 0.08, 1.8)
		if nvOn then
			startWhine()
		elseif whine then
			whine:Stop()
		end
	elseif whine then
		whine:Stop()
	end
end

-- [V]: the night vision on or off (a little relay click, the hum coming or going)
local function toggleNightVision()
	if state ~= "up" then
		return
	end
	nvOn = not nvOn
	event:FireServer(nvOn and "NightVisionOn" or "NightVisionOff")
	sound(SOUND.click, 0.16, nvOn and 1.7 or 1.3)
	if nvOn then
		staticFlash.BackgroundColor3 = Color3.fromRGB(190, 230, 195)
		staticFlash.BackgroundTransparency = 0.35
		TweenService:Create(staticFlash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		sound(SOUND.static, 0.09, 2.4)
		startWhine()
	else
		-- the picture drops out for a blink, the hum winds down
		staticFlash.BackgroundColor3 = Color3.new(0, 0, 0)
		staticFlash.BackgroundTransparency = 0.1
		TweenService:Create(staticFlash, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		if whine then
			local w = whine
			TweenService:Create(w, TweenInfo.new(0.35), { Volume = 0, PlaybackSpeed = 0.55 }):Play()
			task.delay(0.36, function()
				if not nvOn then w:Stop() end
			end)
		end
	end
	applyMode(true)
end

--------------------------------------------------
-- THE FLASH
--------------------------------------------------

local currentPrint = nil      -- (no prints any more - kept for the put-away code)

-- a hard white pop from the lens: it blinds a monster in front of you
-- (PhotoServer, which also plays the flash sound for everyone near - you
-- too), and for the blink it lasts it shows what your eyes can't (FlashReveal)
local function takeFlash()
	if state ~= "up" or blocked() or not photoEvent then
		return
	end
	if workspace:GetServerTimeNow() < (player:GetAttribute("FlashReadyAt") or 0) then
		-- not charged yet: a dead click
		sound(SOUND.click, 0.18, 0.55)
		flashDudAt = os.clock()
		return
	end
	photoEvent:FireServer("Flash", camera.CFrame.LookVector)
	-- the flash on your own screen
	flashWash.BackgroundTransparency = 0.05
	TweenService:Create(flashWash, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	local pop = new("Part", { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CFrame = camera.CFrame * CFrame.new(0, 0, -1) }, workspace)
	new("SpotLight", { Range = 45, Angle = 80, Brightness = 9, Color = Color3.fromRGB(235, 242, 255), Shadows = true }, pop)
	Debris:AddItem(pop, 0.09)
	Reveal.flash(camera.CFrame, camera.FieldOfView, { charNow(), camera })
end

local function raise()
	if state ~= "down" or blocked() or (player:GetAttribute("CamcorderCharge") or 0) <= 0 then
		if (player:GetAttribute("CamcorderCharge") or 0) <= 0 and state == "down" and not blocked() then
			sound(SOUND.click, 0.25, 0.7)      -- dead: just a dull click
		end
		return
	end
	state, stateStart = "raising", os.clock()
	event:FireServer("Raise")
	showModel(true)
	sound(SOUND.raise, 0.14, 2.6)
end

local function lower()
	if state ~= "up" then
		return
	end
	state, stateStart = "lowering", os.clock()
	event:FireServer("Lower")
	nightVision(false)
	showModel(true)
	staticFlash.BackgroundTransparency = 1
	sound(SOUND.raise, 0.12, 2.5)
end

local function reload()
	if (state ~= "down" and state ~= "up") or blocked() then
		return
	end
	if (player:GetAttribute("Batteries") or 0) <= 0 or (player:GetAttribute("CamcorderCharge") or 0) >= 99 then
		sound(SOUND.click, 0.2, 0.6)
		return
	end
	if state == "up" then
		nightVision(false)
	end
	state, stateStart = "reloading", os.clock()
	reloadLatchClickPlayed = false
	event:FireServer("Reload")
	showModel(true)
	sound(SOUND.reload, 0.16, 1)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("IntroCamcorder") then
		return
	end
	if input.UserInputType == RAISE_KEY then
		if state == "down" then
			raise()
		elseif state == "up" then
			lower()
		end
	elseif input.KeyCode == RELOAD_KEY then
		reload()
	elseif input.KeyCode == NIGHT_KEY then
		toggleNightVision()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		takeFlash()
	end
end)

-- the crash cutscene: up to your eye when you come round, down again after a look
player:GetAttributeChangedSignal("IntroCamcorder"):Connect(function()
	if player:GetAttribute("IntroCamcorder") then
		if state == "down" then
			state, stateStart = "raising", os.clock()
			event:FireServer("Raise")
			showModel(true)
			sound(SOUND.raise, 0.18, 2.4)
		end
	else
		if state == "up" then
			lower()
		end
	end
end)

-- the old battery tumbling away (after the latch pops)
local droppedBattery
local function dropOldBattery(base)
	if droppedBattery or not battery then
		return
	end
	droppedBattery = { part = battery:Clone(), cf = base * rest[battery], vel = Vector3.new(-1.5, -2, 1), spin = 0, born = os.clock() }
	droppedBattery.part.Parent = camera
	battery.Transparency = 1
end

-- (drawn after every camera script - including the cutscene camera - so it
-- sits exactly in front of your eye)
RunService:BindToRenderStep("CamcorderViewmodel", Enum.RenderPriority.Camera.Value + 60, function(dt)
	-- (testing: set the player's "CamcorderSlowMo" attribute to e.g. 8 to watch the moves slowly)
	local slowMo = math.max(player:GetAttribute("CamcorderSlowMo") or 1, 1)
	local t = (os.clock() - stateStart) / slowMo

	-- anything that takes your hands or your screen puts it away
	if (state == "up" or state == "raising" or state == "photo") and blocked() then
		if currentPrint then
			currentPrint.part:Destroy()
			currentPrint = nil
		end
		leftPalm.Transparency, leftFingers.Transparency, leftSleeve.Transparency = 1, 1, 1
		state = "lowering"
		stateStart = os.clock()
		event:FireServer("Lower")
		nightVision(false)
	end
	-- the battery died
	if state == "up" and (player:GetAttribute("CamcorderCharge") or 0) <= 0 then
		lower()
	end

	if state == "raising" then
		local p
		if t < RAISE_TIME * 0.5 then
			p = OFF_SCREEN:Lerp(HELD, easeOut(t / (RAISE_TIME * 0.5)))
		else
			p = HELD:Lerp(EYE, easeIn((t - RAISE_TIME * 0.5) / (RAISE_TIME * 0.5)))
		end
		place(p)
		if t >= RAISE_TIME then
			-- the screen fills your eye: cut to the viewfinder
			showModel(false)
			state, stateStart = "up", os.clock()
			recStarted = recStarted or os.clock()
			lastRecordTickSecond = math.floor(os.clock() - recStarted)
			nightVision(true)
		end
	elseif state == "lowering" then
		local p
		if t < LOWER_TIME * 0.38 then
			p = EYE:Lerp(HELD, easeOut(t / (LOWER_TIME * 0.38)))
		else
			p = HELD:Lerp(OFF_SCREEN, easeIn((t - LOWER_TIME * 0.38) / (LOWER_TIME * 0.62)))
		end
		place(p)
		if t >= LOWER_TIME then
			showModel(false)
			state = "down"
		end
	elseif state == "reloading" then
		-- 0.00 bring it up and turn it round  0.40 left hand to the latch
		-- 0.75 old pack out and dropped       1.10 hand away, back with a fresh one
		-- 1.55 slide it in                    1.90 click + beep
		-- 2.20 lower it away
		local p
		if t < 0.4 then
			p = OFF_SCREEN:Lerp(INSPECT, easeOut(t / 0.4))
		elseif t < 2.2 then
			p = INSPECT * CFrame.Angles(math.rad(1.5 * math.sin(t * 5)), 0, 0)
		else
			p = INSPECT:Lerp(OFF_SCREEN, easeIn((t - 2.2) / (RELOAD_TIME - 2.2)))
		end
		place(p, function(base)
			if not battery or not latch then
				return
			end
			local slot = base * rest[battery]
			local handAt, handOn
			if t < 0.4 then
				handOn = false
			elseif t < 0.75 then
				-- thumb on the latch
				handOn = true
				handAt = (base * rest[latch]) * CFrame.new(0, -0.1, 0.12)
				handAt = (base * CFrame.new(-0.9, -1.2, 1.2)):Lerp(handAt, easeOut((t - 0.4) / 0.2))
				if latch then
					latch.CFrame = base * rest[latch] * CFrame.new(0, t > 0.62 and -0.02 or 0, 0)
				end
				if t > 0.6 and not reloadLatchClickPlayed then
					reloadLatchClickPlayed = true
					sound(SOUND.click, 0.15, 1.25)
				end
			elseif t < 1.1 then
				-- pull the old pack out... and let it fall
				handOn = true
				local a = easeOut((t - 0.75) / 0.2)
				handAt = slot * CFrame.new(0, -0.25 * a, 0.25 * a)
				if battery and not droppedBattery then
					battery.CFrame = handAt
				end
				if t > 0.95 then
					dropOldBattery(base)
				end
			elseif t < 1.55 then
				-- away... and back with a fresh one
				handOn = true
				local a = (t - 1.1) / 0.45
				local away = base * CFrame.new(-0.9, -1.3, 1.1)
				local ready = slot * CFrame.new(0, -0.3, 0.3)
				handAt = (a < 0.45) and (slot * CFrame.new(0, -0.25, 0.25)):Lerp(away, easeIn(a / 0.45))
					or away:Lerp(ready, easeOut((a - 0.45) / 0.55))
				if newBattery then
					newBattery.Parent = a >= 0.45 and vm or nil
					newBattery.CFrame = handAt
				end
			elseif t < 2.2 then
				-- slide it home, click, beep
				handOn = true
				local a = easeOut((t - 1.55) / 0.3)
				handAt = (slot * CFrame.new(0, -0.3, 0.3)):Lerp(slot, a)
				if newBattery then
					newBattery.Parent = vm
					newBattery.CFrame = handAt
				end
				if t > 1.9 and tally then
					tally.Color = (math.floor(t * 12) % 2 == 0) and Color3.fromRGB(60, 255, 80) or Color3.fromRGB(20, 40, 20)
					tally.Material = Enum.Material.Neon
				end
			else
				handOn = false
			end
			leftPalm.Transparency = handOn and 0 or 1
			leftFingers.Transparency = handOn and 0 or 1
			leftSleeve.Transparency = handOn and 0 or 1
			if handOn and handAt then
				leftPalm.CFrame = handAt * CFrame.new(0, -0.12, 0.05)
				leftFingers.CFrame = handAt * CFrame.new(0, -0.02, -0.18)
				leftSleeve.CFrame = handAt * CFrame.new(-0.15, -0.55, 0.6) * CFrame.Angles(math.rad(35), math.rad(15), 0)
			end
		end)
		-- the sounds of it
		if t > 1.9 and not stateBeeped then
			stateBeeped = true
			sound(SOUND.click, 0.24, 1.05)      -- battery latch closing
			task.delay(0.15, function()
				sound(SOUND.recordTick, 0.07, 1.0) -- short recorder confirmation beep
			end)
		end
		if t >= RELOAD_TIME then
			stateBeeped = false
			showModel(false)
			if battery then battery.Transparency = 0 end
			if newBattery then newBattery.Parent = nil end
			if tally then tally.Material = Enum.Material.SmoothPlastic end
			state = "down"
		end
	end

	-- the old battery falls out of view
	if droppedBattery then
		local b = droppedBattery
		b.vel += Vector3.new(0, -14, 0) * dt
		b.cf = (b.cf + camera.CFrame:VectorToWorldSpace(b.vel) * dt) * CFrame.Angles(dt * 6, dt * 4, 0)
		b.part.CFrame = b.cf
		if os.clock() - b.born > 1.2 then
			b.part:Destroy()
			droppedBattery = nil
		end
	end

	-- the viewfinder, every frame while it's up
	if state == "up" then
		irPart.CFrame = camera.CFrame
		local charge = player:GetAttribute("CamcorderCharge") or 0
		local seconds = os.clock() - recStarted
		timecode.Text = string.format("%02d:%02d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60, (seconds * 30) % 30)
		local wholeSecond = math.floor(seconds)
		if wholeSecond > lastRecordTickSecond then
			lastRecordTickSecond = wholeSecond
			sound(SOUND.recordTick, 0.055, 1.0)
		end
		recDot.Visible = (seconds % 1) < 0.6
		-- the flash charging
		local left = (player:GetAttribute("FlashReadyAt") or 0) - workspace:GetServerTimeNow()
		local ready = left <= 0
		flashFill.Size = UDim2.fromScale(math.clamp(1 - left / FLASH_COOLDOWN, 0, 1), 1)
		local dud = os.clock() - flashDudAt < 0.5
		flashLabel.TextTransparency = ready and 0 or 0.45
		flashLabel.TextColor3 = dud and Color3.fromRGB(255, 80, 60) or (nvOn and NV_TEXT or Color3.fromRGB(226, 226, 220))
		if ready and not flashWasReady then
			sound(SOUND.recordTick, 0.08, 1.6)       -- charged
		end
		flashWasReady = ready
		for _, g in ipairs(grain) do
			g.Position = UDim2.fromScale(math.random(), math.random())
		end
		-- a dying battery: the picture stutters
		if charge < LOW_BATTERY then
			local failing = math.random() < (LOW_BATTERY - charge) / LOW_BATTERY * 0.12
			grade.Brightness = failing and -0.2 or 0.14
			irBeam.Brightness = failing and 0.4 or 3.2
			batteryBox.Visible = (seconds % 0.6) < 0.35
		else
			grade.Brightness = 0.14
			irBeam.Brightness = 3.2
			batteryBox.Visible = true
		end
	end
	if screenNoise and vm.Parent then
		for _, g in ipairs(screenNoise) do
			g.Position = UDim2.fromScale(math.random(), math.random())
		end
	end
end)

--------------------------------------------------
-- WHAT EVERYONE ELSE SEES: your arm up, the camcorder to your face
--------------------------------------------------

local others = {}      -- character -> { model, parts, rest }

local function aimArm(motor, originalC0, targetTorso)
	local jointPos = originalC0.Position
	local restArm = originalC0 * motor.C1:Inverse()
	local shoulderLocal = motor.C1.Position
	local restDir = restArm:VectorToWorldSpace(Vector3.new(0, -1, 0) - shoulderLocal).Unit
	local toTarget = targetTorso - jointPos
	if toTarget.Magnitude < 0.01 then
		return originalC0
	end
	local wantDir = toTarget.Unit
	local cross = restDir:Cross(wantDir)
	local rotation = CFrame.identity
	if cross.Magnitude > 1e-4 then
		rotation = CFrame.fromAxisAngle(cross.Unit, math.acos(math.clamp(restDir:Dot(wantDir), -1, 1)))
	end
	local armRotation = rotation * restArm.Rotation
	return CFrame.new(jointPos - armRotation:VectorToWorldSpace(shoulderLocal)) * armRotation * motor.C1
end

local function propFor(character)
	local o = others[character]
	if o then
		return o
	end
	local model = template:Clone()
	local ps, rs = {}, {}
	local pv = (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")).CFrame
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
			table.insert(ps, d)
			rs[d] = pv:ToObjectSpace(d.CFrame)
		elseif d:IsA("Light") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	local torso = character:FindFirstChild("Torso")
	o = { model = model, parts = ps, rest = rs, weight = 0,
		shoulder = torso and torso:FindFirstChild("Right Shoulder"), left = torso and torso:FindFirstChild("Left Shoulder") }
	o.shoulderRest = o.shoulder and o.shoulder.C0
	o.leftRest = o.left and o.left.C0
	others[character] = o
	return o
end

local afterAnimation = RunService.PreSimulation or RunService.Stepped
afterAnimation:Connect(function(_, dtMaybe)
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		if p ~= player and c and c.Parent then
			local up = c:GetAttribute("CamcorderRaised") == true
			local swapping = (c:GetAttribute("CamcorderReloading") or 0) > 0
			local o = (up or swapping or others[c]) and propFor(c)
			if o and o.shoulder then
				local want = (up or swapping) and 1 or 0
				o.weight += (want - o.weight) * 0.25
				local torso = c:FindFirstChild("Torso")
				local head = c:FindFirstChild("Head")
				if o.weight > 0.02 and torso and head then
					local torsoCF = torso.CFrame
					-- up at the face (raised) or at the chest (swapping the battery)
					local target = up and (head.CFrame * CFrame.new(0.15, 0, -0.9)).Position
						or (torsoCF * CFrame.new(0.2, 0.3, -1.3)).Position
					o.shoulder.C0 = o.shoulderRest:Lerp(aimArm(o.shoulder, o.shoulderRest, torsoCF:PointToObjectSpace(target)), o.weight)
					o.shoulder.Transform = CFrame.identity
					if o.left then
						local support = (torsoCF * CFrame.new(-0.1, up and 0.9 or 0.3, -1.2)).Position
						o.left.C0 = o.leftRest:Lerp(aimArm(o.left, o.leftRest, torsoCF:PointToObjectSpace(support)), o.weight * 0.8)
						o.left.Transform = CFrame.identity
					end
					local arm = c:FindFirstChild("Right Arm")
					if arm then
						o.model.Parent = camera
						local hand = arm.CFrame * CFrame.new(0, -1.1, 0) * CFrame.Angles(math.rad(-90), 0, 0)
						for _, part in ipairs(o.parts) do
							part.CFrame = hand * o.rest[part]
						end
					end
				else
					o.shoulder.C0 = o.shoulderRest
					if o.left then o.left.C0 = o.leftRest end
					o.model.Parent = nil
				end
			end
		end
	end
	for c, o in pairs(others) do
		if not c.Parent then
			o.model:Destroy()
			others[c] = nil
		end
	end
end)

-- after using an item with it up (MedicalClient lowered it): back to your eye
local function watchItemUse(c)
	c:GetAttributeChangedSignal("UsingMedical"):Connect(function()
		if c:GetAttribute("UsingMedical") or not player:GetAttribute("CamcorderReRaise") then
			return
		end
		player:SetAttribute("CamcorderReRaise", nil)
		task.delay(0.12, function()
			-- (still lowering? wait for it to be down)
			for _ = 1, 20 do
				if state == "down" then
					raise()
					return
				end
				task.wait(0.05)
			end
		end)
	end)
end
if player.Character then
	watchItemUse(player.Character)
end
player.CharacterAdded:Connect(watchItemUse)

-- a fresh life: put everything away
player.CharacterAdded:Connect(function()
	if currentPrint then
		currentPrint.part:Destroy()
		currentPrint = nil
	end
	state = "down"
	showModel(false)
	nightVision(false)
end)
