-- RoleSelectionClient
-- Lives inside RoleSelection; the server gives each player a copy.
--
-- Choosing who you were, in the lobby itself: your camera leaves your body and
-- glides along the five role lockers. The one you're looking at stutters its
-- light on and the person inside slowly lifts their head to look at you; the
-- others hang their heads in the dark. Their personnel file slides in beside
-- them - polaroid, typed assessment, a note in red. CHOOSE: the old camera
-- whines, the flash goes off, the polaroid develops, ASSIGNED is stamped on
-- the file, the locker light dies... and you open your eyes as them.
--
-- Arrows / A-D / swipe / tap a locker to look; CHOOSE (or Enter) to pick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
if player:GetAttribute("Role") then
	script:Destroy()
	return
end

local folder = ReplicatedStorage:WaitForChild("RoleSelection")
local event = folder:WaitForChild("RoleEvent")
local previews = folder:WaitForChild("Previews")

-- In the lobby, this waits until voting is over and the lobby opens it.
if folder:GetAttribute("WaitForLobby") and not folder:GetAttribute("SelectionOpen") then
	local opened = false
	local listen = event.OnClientEvent:Connect(function(action)
		if action == "Open" then
			opened = true
		end
	end)
	while not opened and not folder:GetAttribute("SelectionOpen") do
		task.wait(0.1)
	end
	listen:Disconnect()
	if player:GetAttribute("Role") then
		script:Destroy()
		return
	end
end

--------------------------------------------------
-- ROLES (left to right along the lockers)
--------------------------------------------------

local ROLES = {
	{
		name = "Acrobat", no = "07-114",
		tagline = "Light on their feet. First over every wall.",
		plus = { "Runs faster and sprints for longer", "Slides - crouch while sprinting", "Hardest survivor to catch" },
		minus = "Fragile. Won't take many hits.",
	},
	{
		name = "Mechanic", no = "07-118",
		tagline = "If it's broken, they'll get it running.",
		plus = { "Repairs and minigames are easier", "Turns valves faster", "Headlamp batteries last much longer" },
		minus = "Heavy tools. Their footsteps carry.",
	},
	{
		name = "Medic", no = "07-121",
		tagline = "Keeps the rest of you breathing.",
		plus = { "Revives the fallen almost twice as fast", "Starts with 3 adrenaline shots, 2 bandages", "Patches up faster than anyone" },
		minus = "Can't carry the heavy things.",
	},
	{
		name = "Scout", no = "07-126",
		tagline = "Hears them coming before anyone else.",
		plus = { "Hears monsters through walls", "V: mark a monster for the whole team", "Quiet - heard from half as far" },
		minus = "Nothing to fight back with.",
	},
	{
		name = "Brute", no = "07-130",
		tagline = "The one thing in here that pushes back.",
		plus = { "150 health - takes hits no one else can", "Heavy objects don't slow him down", "V: carry a downed teammate" },
		minus = "Slow when carrying someone.",
	},
}

local INK = Color3.fromRGB(38, 30, 24)
local PAPER = Color3.fromRGB(204, 190, 158)
local BONE = Color3.fromRGB(214, 206, 190)
local RED = Color3.fromRGB(150, 26, 22)
local TYPE = Enum.Font.SpecialElite
local HAND = Enum.Font.Kalam
local STAMP = Enum.Font.PermanentMarker

local SND = {
	hover = "rbxassetid://9119727134",
	paper = "rbxassetid://9117233449",
	locked = "rbxassetid://9116522890",
	thud = "rbxassetid://9116673944",
	heart = "rbxassetid://3012160995",
	buzz = "rbxassetid://9116272374",
	whine = "rbxassetid://118206070547709",
	flash = "rbxassetid://135432517383409",
}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function tween(o, time, goal, style, dir)
	local t = TweenService:Create(o, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local function text(props, parent)
	local d = { BackgroundTransparency = 1, Font = TYPE, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextScaled = false }
	for k, v in pairs(props) do
		d[k] = v
	end
	return new("TextLabel", d, parent)
end
local function sound(id, volume, speed, looped)
	local s = new("Sound", { SoundId = id, Volume = volume, PlaybackSpeed = speed or 1, Looped = looped or false }, SoundService)
	s:Play()
	if not looped then
		s.Ended:Once(function() s:Destroy() end)
		task.delay(10, function() if s.Parent then s:Destroy() end end)
	end
	return s
end
local function noise(t, seed)
	return math.noise(t, seed, 0.37)
end
local function smooth(a)
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

--------------------------------------------------
-- THE LOCKERS
--------------------------------------------------

local displays = workspace:WaitForChild("RoleDisplays", 15)
local lockers = {}
for i, role in ipairs(ROLES) do
	local stand = workspace:FindFirstChild("RoleStand_" .. role.name, true)
	if stand then
		local L = { role = role, index = i, stand = stand, at = stand.Position + Vector3.new(0, 3.4, 0) }
		-- its light: the nearest locker lamp
		local best, bestD
		for _, p in ipairs(workspace:GetChildren()) do
			if p:IsA("BasePart") and p.Name == "RoleLockerLight" then
				local d = (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(stand.Position.X, 0, stand.Position.Z)).Magnitude
				if not bestD or d < bestD then
					best, bestD = p, d
				end
			end
		end
		L.lampPart = best
		L.lamp = best and best:FindFirstChildOfClass("SurfaceLight")
		if L.lamp then
			L.lampWas = { Brightness = L.lamp.Brightness, Color = L.lamp.Color, Enabled = L.lamp.Enabled }
			L.lampPartWas = { Color = best.Color, Material = best.Material }
		end
		-- the person inside, and their head (plus whatever's on it) so it can turn
		local figure = displays and displays:WaitForChild(role.name .. "Display", 5)
		if figure then
			local head, torso = figure:FindFirstChild("Head"), figure:FindFirstChild("Torso")
			if head and torso then
				local group = { head }
				for _, d in ipairs(figure:GetDescendants()) do
					if d:IsA("BasePart") and d ~= head then
						local acc = d:FindFirstAncestorOfClass("Accessory")
						local onHead = false
						for _, w in ipairs(d:GetChildren()) do
							if (w:IsA("Weld") or w:IsA("WeldConstraint") or w:IsA("Motor6D")) and (w.Part0 == head or w.Part1 == head) then
								onHead = true
							end
						end
						if acc and (acc:FindFirstChild("Handle") == d) and (d.Position - head.Position).Magnitude < 2.5 then
							onHead = true
						end
						if onHead or (d.Position - head.Position).Magnitude < 0.9 and d.Size.Magnitude < 2.5 then
							table.insert(group, d)
						end
					end
				end
				local neck = torso.CFrame * CFrame.new(0, 1, 0)
				L.neck = neck
				L.headGroup = {}
				for _, p in ipairs(group) do
					table.insert(L.headGroup, { part = p, rel = neck:ToObjectSpace(p.CFrame), rest = p.CFrame })
				end
				L.pitch, L.yaw = -24, 0     -- heads hang (negative pitch = looking down)
			end
		end
		lockers[i] = L
	end
end

local function takenBy(roleName)
	local id = folder:GetAttribute("Taken_" .. roleName) or 0
	if id == 0 then
		return nil
	end
	local p = Players:GetPlayerByUserId(id)
	return p and p.DisplayName or "someone"
end

--------------------------------------------------
-- SCREEN
--------------------------------------------------

local gui = new("ScreenGui", { Name = "RoleSelectionGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
-- everything else on screen steps aside
local hidden = {}
for _, g in ipairs(player.PlayerGui:GetChildren()) do
	if g:IsA("ScreenGui") and g ~= gui and g.Enabled and not g.Name:find("Holder") then
		hidden[g] = true
		g.Enabled = false
	end
end

local curtain = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 50 }, gui)
local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 252, 244), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 49 }, gui)
local shakeRoot = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)

-- the lens: dark corners, a breath of film grain
for _, side in ipairs({ { 0, 0, 0 }, { 1, 0, 180 }, { 0, 0, 90 }, { 0, 1, -90 } }) do
	local vertical = side[3] == 90 or side[3] == -90
	local f = new("Frame", { AnchorPoint = Vector2.new(side[1], side[2]), Position = UDim2.fromScale(side[1], side[2]),
		Size = vertical and UDim2.fromScale(1, 0.3) or UDim2.fromScale(0.26, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, shakeRoot)
	new("UIGradient", { Rotation = side[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) }) }, f)
end
local grain = {}
for i = 1, 60 do
	grain[i] = new("Frame", { Size = UDim2.fromOffset(2, 2), BackgroundColor3 = Color3.fromRGB(230, 225, 215), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 40 }, shakeRoot)
end

local title = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.045, 0), Size = UDim2.new(0.8, 0, 0, 46), Text = "WHO WERE YOU?",
	TextSize = 40, TextColor3 = BONE, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 }, shakeRoot)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.3 }, title)
local hint = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.045, 48), Size = UDim2.new(0.8, 0, 0, 20), Text = "",
	TextSize = 15, TextColor3 = Color3.fromRGB(150, 142, 128), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 }, shakeRoot)

-- the team so far (top left)
local roster = new("Frame", { Position = UDim2.new(0, 26, 0, 22), Size = UDim2.new(0, 240, 0, 150), BackgroundTransparency = 1 }, shakeRoot)
new("UIListLayout", { Padding = UDim.new(0, 2) }, roster)

-- arrows (big, for thumbs)
local function arrow(textChar, x, anchor)
	-- either side of CHOOSE, at the bottom (thumb height)
	local b = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, x, 1, -34), Size = UDim2.fromOffset(74, 62),
		BackgroundColor3 = Color3.fromRGB(10, 9, 8), BackgroundTransparency = 0.45, Text = textChar, Font = TYPE, TextSize = 46, TextColor3 = BONE,
		AutoButtonColor = true, BorderSizePixel = 0 }, shakeRoot)
	new("UIStroke", { Color = Color3.fromRGB(70, 62, 52), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	return b
end
local prevButton = arrow("‹", -178, 0)
local nextButton = arrow("›", 178, 1)

-- CHOOSE
local choose = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34), Size = UDim2.fromOffset(260, 62),
	BackgroundColor3 = Color3.fromRGB(60, 12, 10), Text = "CHOOSE", Font = TYPE, TextSize = 30, TextColor3 = BONE, AutoButtonColor = true, BorderSizePixel = 0 }, shakeRoot)
new("UIStroke", { Color = Color3.fromRGB(150, 40, 32), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, choose)
local notice = text({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -104), Size = UDim2.new(0.6, 0, 0, 24), Text = "",
	TextSize = 18, TextColor3 = Color3.fromRGB(220, 120, 100), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 }, shakeRoot)

-- THE FILE (right side)
local fileHome = UDim2.new(0.965, 0, 0.5, 0)
local file = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1.6, 0, 0.5, 0), Size = UDim2.fromScale(0.31, 0.74),
	BackgroundColor3 = PAPER, BorderSizePixel = 0, Rotation = -1.6 }, shakeRoot)
new("UISizeConstraint", { MinSize = Vector2.new(290, 420), MaxSize = Vector2.new(430, 640) }, file)
new("UIGradient", { Rotation = 35, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 240)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(235, 228, 210)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 150, 118)) }) }, file)
new("UIPadding", { PaddingLeft = UDim.new(0.07, 0), PaddingRight = UDim.new(0.07, 0), PaddingTop = UDim.new(0.04, 0) }, file)
-- a coffee ring, a corner fold
local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.86, 0.86), Size = UDim2.fromScale(0.3, 0.3), SizeConstraint = Enum.SizeConstraint.RelativeXX,
	BackgroundTransparency = 1 }, file)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
new("UIStroke", { Color = Color3.fromRGB(120, 86, 52), Thickness = 3, Transparency = 0.7 }, ring)

local header = text({ Size = UDim2.new(1, 0, 0, 18), Text = "PERSONNEL FILE  —  HOLLOWAY ESTATE", TextSize = 13, TextColor3 = Color3.fromRGB(90, 70, 52) }, file)
local fileNo = text({ Position = UDim2.new(0, 0, 0, 18), Size = UDim2.new(1, 0, 0, 16), Text = "", TextSize = 13, TextColor3 = Color3.fromRGB(110, 90, 70) }, file)
new("Frame", { Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(110, 90, 70), BorderSizePixel = 0 }, file)

-- the polaroid, clipped on
local polaroid = new("Frame", { Position = UDim2.new(0.56, 0, 0, 48), Size = UDim2.fromScale(0.42, 0.42), SizeConstraint = Enum.SizeConstraint.RelativeXX,
	BackgroundColor3 = Color3.fromRGB(232, 228, 216), BorderSizePixel = 0, Rotation = 4 }, file)
local photo = new("ViewportFrame", { Position = UDim2.fromScale(0.07, 0.07), Size = UDim2.fromScale(0.86, 0.72), BackgroundColor3 = Color3.fromRGB(26, 24, 22),
	Ambient = Color3.fromRGB(150, 140, 120), LightColor = Color3.fromRGB(255, 240, 220), LightDirection = Vector3.new(-0.4, -0.6, -1), BorderSizePixel = 0 }, polaroid)
local develop = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 12, 10), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, photo)
local caption = text({ Position = UDim2.fromScale(0.07, 0.8), Size = UDim2.fromScale(0.86, 0.18), Text = "", Font = HAND, TextScaled = true,
	TextColor3 = Color3.fromRGB(40, 40, 70), TextXAlignment = Enum.TextXAlignment.Center }, polaroid)
local clip = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(0.14, 0.22),
	BackgroundTransparency = 1 }, polaroid)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, clip)
new("UIStroke", { Color = Color3.fromRGB(120, 122, 126), Thickness = 2.5 }, clip)

local subject = text({ Position = UDim2.new(0, 0, 0, 50), Size = UDim2.new(0.54, 0, 0, 20), Text = "SUBJECT:", TextSize = 13, TextColor3 = Color3.fromRGB(110, 90, 70) }, file)
local nameLabel = text({ Position = UDim2.new(0, 0, 0, 68), Size = UDim2.new(0.54, 0, 0, 36), Text = "", TextScaled = true, TextWrapped = false }, file)
new("UITextSizeConstraint", { MaxTextSize = 30 }, nameLabel)
local tagline = text({ Position = UDim2.new(0, 0, 0, 112), Size = UDim2.new(0.52, 0, 0, 64), Text = "", Font = HAND, TextSize = 19, TextColor3 = Color3.fromRGB(50, 46, 70) }, file)
local assess = text({ Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 18), Text = "ASSESSMENT", TextSize = 14, TextColor3 = Color3.fromRGB(110, 90, 70) }, file)
new("Frame", { Position = UDim2.new(0, 0, 0.5, 19), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(110, 90, 70), BorderSizePixel = 0 }, file)
local plusLines = {}
for i = 1, 3 do
	plusLines[i] = text({ Position = UDim2.new(0, 0, 0.5, 25 + (i - 1) * 30), Size = UDim2.new(1, 0, 0, 30), Text = "", TextScaled = true }, file)
	new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 9 }, plusLines[i])
end
local noteHead = text({ Position = UDim2.new(0, 0, 0.5, 132), Size = UDim2.new(1, 0, 0, 18), Text = "NOTE:", TextSize = 14, TextColor3 = Color3.fromRGB(110, 90, 70) }, file)
local minus = text({ Position = UDim2.new(0, 0, 0.5, 150), Size = UDim2.new(1, 0, 0, 30), Text = "", Font = HAND, TextSize = 22, TextColor3 = RED, Rotation = -1.5 }, file)
local status = text({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, 0, 0, 20), Text = "", TextSize = 15 }, file)
-- the stamps
local function makeStamp(word)
	local s = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(0.86, 0.15),
		BackgroundTransparency = 1, Text = word, Font = STAMP, TextScaled = true, TextColor3 = RED, TextTransparency = 1, Rotation = -12, ZIndex = 10 }, file)
	local st = new("UIStroke", { Color = RED, Thickness = 4, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, s)
	return s, st
end
local takenStamp, takenStroke = makeStamp("TAKEN")
local assignedStamp, assignedStroke = makeStamp("ASSIGNED")

--------------------------------------------------
-- STATE
--------------------------------------------------

local current = 1
local confirmed = false
local camPos, camLook
local startCF = workspace.CurrentCamera.CFrame
local openedAt = os.clock()
local swapAt = 0

local function showNotice(t)
	notice.Text = t
	notice.TextTransparency = 0
	task.delay(3, function()
		if notice.Text == t then tween(notice, 0.8, { TextTransparency = 1 }) end
	end)
end

-- the polaroid: a close shot of the person, posed like a mugshot
local function setPhoto(roleName)
	photo:ClearAllChildren()
	develop = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 12, 10), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, photo)
	local template = previews:FindFirstChild(roleName)
	if not template then
		return
	end
	local world = new("WorldModel", {}, photo)
	local m = template:Clone()
	m.Parent = world
	local cf, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + (Vector3.new(0, size.Y / 2, 0) - cf.Position))
	local cam = new("Camera", { FieldOfView = 24 }, photo)
	photo.CurrentCamera = cam
	local headY = size.Y * 0.83
	cam.CFrame = CFrame.lookAt(Vector3.new(0.35, headY + 0.1, -size.Y * 1.25), Vector3.new(0, headY - 0.4, 0))
end

local typing = 0
local function typeInto(label, full, delay)
	label.Text = ""
	local my = typing
	task.delay(delay or 0, function()
		for i = 1, #full do
			if typing ~= my then return end
			label.Text = full:sub(1, i)
			task.wait(0.012)
		end
	end)
end

local function fillFile(L)
	typing += 1
	local role = L.role
	fileNo.Text = "FILE No. " .. role.no .. "   •   " .. L.index .. " / " .. #ROLES
	nameLabel.Text = role.name:upper()
	caption.Text = role.name
	typeInto(tagline, '"' .. role.tagline .. '"', 0.15)
	for i = 1, 3 do typeInto(plusLines[i], "+  " .. role.plus[i], 0.25 + i * 0.12) end
	typeInto(minus, role.minus, 0.75)
	setPhoto(role.name)
	local by = takenBy(role.name)
	status.Text = by and ("STATUS:  TAKEN BY " .. by:upper()) or "STATUS:  UNASSIGNED"
	status.TextColor3 = by and RED or INK
	takenStamp.TextTransparency = by and 0.08 or 1
	takenStroke.Transparency = by and 0.08 or 1
	choose.Text = by and "TAKEN" or "CHOOSE"
	choose.AutoButtonColor = not by
	choose.BackgroundColor3 = by and Color3.fromRGB(26, 24, 22) or Color3.fromRGB(60, 12, 10)
	hint.Text = "‹ ›  to look along the lockers     •     CHOOSE to become them"
end

local function refreshRoster()
	for _, c in ipairs(roster:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	text({ Size = UDim2.new(1, 0, 0, 18), Text = "THE OTHERS", TextSize = 13, TextColor3 = Color3.fromRGB(150, 142, 128) }, roster)
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p:GetAttribute("Role")
		text({ Size = UDim2.new(1, 0, 0, 18), Text = p.DisplayName .. "  —  " .. (r and r:upper() or "..."), TextSize = 14,
			TextColor3 = r and BONE or Color3.fromRGB(110, 104, 94) }, roster)
	end
end

-- light the one you're looking at, dim the rest
local function lampFlickerOn(L)
	if not L.lamp then return end
	task.spawn(function()
		sound(SND.buzz, 0.12, 1.2)
		for _, v in ipairs({ 0.2, 1.5, 0.1, 0.9, 0.3, 1.4 }) do
			if lockers[current] ~= L or confirmed then return end
			L.lamp.Brightness = v
			task.wait(0.04 + math.random() * 0.06)
		end
	end)
end
local function setLamps()
	for i, L in ipairs(lockers) do
		if L.lamp then
			local by = takenBy(L.role.name)
			L.lamp.Color = by and Color3.fromRGB(200, 50, 40) or L.lampWas.Color
			if i ~= current then
				L.lamp.Brightness = by and 0.35 or 0.12
			end
		end
	end
end

local function focus(i, quiet)
	i = ((i - 1) % #lockers) + 1
	if i == current and not quiet then
		return
	end
	current = i
	local L = lockers[i]
	if not L then return end
	setLamps()
	lampFlickerOn(L)
	-- the file slides out and back in
	swapAt = os.clock()
	if not quiet then
		sound(SND.paper, 0.35, 1.15 + math.random() * 0.15)
		sound(SND.hover, 0.18, 0.7)
	end
	tween(file, 0.16, { Position = UDim2.new(1.05, 0, 0.53, 0), Rotation = 3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.17, function()
		if lockers[current] ~= L then return end
		fillFile(L)
		file.Rotation = -6
		tween(file, 0.34, { Position = fileHome, Rotation = -1.6 }, Enum.EasingStyle.Back)
	end)
end

--------------------------------------------------
-- INPUT
--------------------------------------------------

prevButton.Activated:Connect(function() if not confirmed then focus(current - 1) end end)
nextButton.Activated:Connect(function() if not confirmed then focus(current + 1) end end)

local function tryChoose()
	local L = lockers[current]
	if confirmed or not L then return end
	if takenBy(L.role.name) then
		sound(SND.locked, 0.3, 1.5)
		showNotice("Someone else is already the " .. L.role.name:lower() .. ".")
		return
	end
	confirmed = true
	choose.Text = "..."
	event:FireServer("Choose", L.role.name)
end
choose.Activated:Connect(tryChoose)

local inputConn = UserInputService.InputBegan:Connect(function(input, processed)
	if confirmed then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.A or k == Enum.KeyCode.Left then
		focus(current - 1)
	elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
		focus(current + 1)
	elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter then
		tryChoose()
	elseif not processed and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		-- tapping a locker looks at it
		local cam = workspace.CurrentCamera
		local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 60)
		if hit then
			for i, L in ipairs(lockers) do
				local d = hit.Position - L.stand.Position
				if math.abs(d.Z) < 2.4 and d.X > -2.5 and d.X < 2.5 and d.Y > -1 and d.Y < 9 then
					focus(i)
					break
				end
			end
		end
	end
end)
local swipeConn = UserInputService.TouchSwipe:Connect(function(dir)
	if confirmed then return end
	if dir == Enum.SwipeDirection.Left then focus(current + 1) elseif dir == Enum.SwipeDirection.Right then focus(current - 1) end
end)

--------------------------------------------------
-- EVERY FRAME: the camera, the heads, the grain
--------------------------------------------------

local shake = 0
local camera = workspace.CurrentCamera
-- a faint, cold light from where you stand, so the lockers aren't just black
local fill = new("Part", { Name = "RoleSelectFill", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1,
	Size = Vector3.new(0.2, 0.2, 0.2) }, camera)
new("SpotLight", { Brightness = 1.5, Range = 20, Angle = 40, Color = Color3.fromRGB(170, 190, 215), Shadows = true, Face = Enum.NormalId.Front }, fill)
local camTypeWas = camera.CameraType
local fovWas = camera.FieldOfView
local snapHead = 0
RunService:BindToRenderStep("RoleSelectCamera", Enum.RenderPriority.Camera.Value + 60, function(dt)
	dt = math.min(dt, 1 / 20)
	local t = os.clock()
	local L = lockers[current]
	if not L then return end
	camera.CameraType = Enum.CameraType.Scriptable
	-- in front of the locker, a little off to the side, slowly easing closer
	local since = t - swapAt
	-- (framed on the left of the screen: the file takes the right)
	local dist = 10.2 - 1.2 * smooth(since / 3)
	local wantPos = L.at + Vector3.new(-dist, 0.45, 1.4)
	local wantLook = L.at + Vector3.new(0, -0.35, 2.6)
	local intro = smooth((t - openedAt) / 1.8)
	if not camPos then
		camPos, camLook = startCF.Position, startCF.Position + startCF.LookVector * 10
	end
	local k = 1 - math.exp(-(2.2 + 2.5 * intro) * dt)
	camPos = camPos:Lerp(wantPos, k)
	camLook = camLook:Lerp(wantLook, 1 - math.exp(-5 * dt))
	-- handheld, breathing
	local hand = CFrame.Angles(math.rad(0.7 * noise(t * 0.6, 1)), math.rad(0.9 * noise(t * 0.5, 2)), math.rad(0.5 * noise(t * 0.4, 3)))
	local breath = Vector3.new(0, 0.03 * math.sin(t * 1.4), 0)
	shake = math.max(0, shake - dt * 2.5)
	local jolt = CFrame.Angles(math.rad(1.6 * shake * noise(t * 30, 4)), math.rad(1.6 * shake * noise(t * 30, 5)), 0)
	camera.CFrame = CFrame.lookAt(camPos + breath, camLook) * hand * jolt
	camera.FieldOfView = 52
	fill.CFrame = CFrame.lookAt(camPos + Vector3.new(0, 0.6, 0), L.at)
	-- heads: the one you're looking at slowly lifts to look at you; the rest hang
	for i, X in ipairs(lockers) do
		if X.headGroup then
			local wantPitch, wantYaw = -26, 6 * math.sin(t * 0.3 + i)
			if i == current then
				local toCam = X.neck:PointToObjectSpace(camera.CFrame.Position)
				wantYaw = math.deg(math.atan2(-toCam.X, -toCam.Z))
				wantPitch = math.deg(math.atan2(toCam.Y, math.sqrt(toCam.X ^ 2 + toCam.Z ^ 2))) * 0.6
				wantYaw = math.clamp(wantYaw, -40, 40)
			end
			local rate = (i == current) and (snapHead > t and 18 or 1.1) or 2.2
			local a = 1 - math.exp(-rate * dt)
			X.pitch += (wantPitch - X.pitch) * a
			X.yaw += (wantYaw - X.yaw) * a
			local twitch = (i == current) and 0.6 * noise(t * 6, i) or 0
			local rot = CFrame.Angles(0, math.rad(X.yaw + twitch), 0) * CFrame.Angles(math.rad(X.pitch), 0, 0)
			for _, g in ipairs(X.headGroup) do
				if g.part.Parent then g.part.CFrame = X.neck * rot * g.rel end
			end
		end
	end
	-- film grain
	for _, g in ipairs(grain) do
		if math.random() < 0.18 then
			g.Position = UDim2.fromScale(math.random(), math.random())
			g.BackgroundTransparency = 0.55 + math.random() * 0.4
		else
			g.BackgroundTransparency = math.min(1, g.BackgroundTransparency + dt * 4)
		end
	end
	shakeRoot.Position = UDim2.fromOffset(8 * shake * noise(t * 40, 6), 8 * shake * noise(t * 40, 7))
end)

--------------------------------------------------
-- LIVE UPDATES
--------------------------------------------------

for _, role in ipairs(ROLES) do
	folder:GetAttributeChangedSignal("Taken_" .. role.name):Connect(function()
		setLamps()
		refreshRoster()
		local L = lockers[current]
		if L and L.role == role and not confirmed then
			fillFile(L)
			if takenBy(role.name) then
				sound(SND.locked, 0.3, 1.4)
				showNotice(role.name .. " was just taken. Pick someone else.")
			end
		end
	end)
end
local function watchPlayer(p)
	p:GetAttributeChangedSignal("Role"):Connect(refreshRoster)
end
for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
Players.PlayerAdded:Connect(function(p) watchPlayer(p) refreshRoster() end)
Players.PlayerRemoving:Connect(function() task.defer(refreshRoster) end)

--------------------------------------------------
-- OPEN: from your eyes to the lockers
--------------------------------------------------

local ambience = sound(SND.heart, 0, 0.6, true)
tween(ambience, 3, { Volume = 0.22 })
for i, L in ipairs(lockers) do
	if not takenBy(L.role.name) then current = i break end
end
refreshRoster()
focus(current, true)
tween(curtain, 1.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
task.spawn(function()
	task.wait(0.7)
	for _, v in ipairs({ 0.3, 0.9, 0.4, 1, 0.15, 0.7, 0 }) do
		title.TextTransparency = v
		task.wait(0.05 + math.random() * 0.06)
	end
	tween(hint, 0.8, { TextTransparency = 0.1 })
	while gui.Parent and not confirmed do
		task.wait(3 + math.random() * 5)
		for _ = 1, math.random(2, 4) do
			title.TextTransparency = 0.5 + math.random() * 0.5
			task.wait(0.04 + math.random() * 0.05)
			title.TextTransparency = 0
			task.wait(0.03 + math.random() * 0.08)
		end
	end
end)

--------------------------------------------------
-- CONFIRMED: flash, the polaroid develops, ASSIGNED, the light dies
--------------------------------------------------

local function finish(roleName)
	local L
	for _, X in ipairs(lockers) do if X.role.name == roleName then L = X end end
	if L and lockers[current] ~= L then focus(L.index, true) task.wait(0.6) end
	L = L or lockers[current]
	tween(ambience, 1, { PlaybackSpeed = 0.9, Volume = 0.35 })
	-- the old camera charges...
	sound(SND.whine, 0.5, 1)
	tween(develop, 0.4, { BackgroundTransparency = 0 })
	for _, b in ipairs({ prevButton, nextButton, choose }) do
		tween(b, 0.3, { BackgroundTransparency = 1, TextTransparency = 1 })
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then tween(st, 0.3, { Transparency = 1 }) end
	end
	task.wait(0.75)
	-- FLASH
	sound(SND.flash, 0.9, 1)
	flash.BackgroundTransparency = 0
	tween(flash, 0.9, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
	local fl = Instance.new("PointLight")
	fl.Brightness = 14 fl.Range = 22 fl.Color = Color3.fromRGB(255, 250, 240)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = camera.CFrame.Position
	holder.Parent = workspace.Terrain
	fl.Parent = holder
	task.delay(0.09, function() holder:Destroy() end)
	snapHead = os.clock() + 0.6      -- they look straight at you
	shake = 0.5
	-- the photo develops
	task.delay(0.25, function() tween(develop, 1.8, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine) end)
	task.wait(0.75)
	-- ASSIGNED
	assignedStamp.Size = UDim2.fromScale(1.7, 0.3)
	assignedStamp.TextTransparency = 0.6
	assignedStroke.Transparency = 0.6
	tween(assignedStamp, 0.1, { Size = UDim2.fromScale(0.86, 0.15), TextTransparency = 0.05 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(assignedStroke, 0.1, { Transparency = 0.05 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(0.1)
	sound(SND.thud, 0.7, 0.75)
	shake = 1
	status.Text = "STATUS:  ASSIGNED — " .. player.DisplayName:upper()
	status.TextColor3 = RED
	task.wait(0.9)
	-- the locker light gutters and dies
	if L.lamp then
		sound(SND.buzz, 0.25, 0.8)
		for _, v in ipairs({ 0.2, 1.2, 0, 0.8, 0.05, 0.4, 0 }) do
			L.lamp.Brightness = v
			task.wait(0.05 + math.random() * 0.07)
		end
	end
	tween(ambience, 1.2, { Volume = 0 })
	task.wait(0.5)
	tween(curtain, 0.7, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine).Completed:Wait()
end

local function cleanup()
	RunService:UnbindFromRenderStep("RoleSelectCamera")
	inputConn:Disconnect()
	swipeConn:Disconnect()
	for _, L in ipairs(lockers) do
		if L.lamp and L.lampWas then
			L.lamp.Brightness = L.lampWas.Brightness
			L.lamp.Color = L.lampWas.Color
			L.lamp.Enabled = L.lampWas.Enabled
		end
		if L.headGroup then
			for _, g in ipairs(L.headGroup) do
				if g.part.Parent then g.part.CFrame = g.rest end
			end
		end
	end
	camera.FieldOfView = fovWas
	camera.CameraType = camTypeWas
	fill:Destroy()
	for g in pairs(hidden) do
		if g.Parent then g.Enabled = true end
	end
end

event.OnClientEvent:Connect(function(action, roleName)
	if action == "Taken" then
		confirmed = false
		focus(current, true)
		sound(SND.locked, 0.3, 1.4)
		showNotice((roleName or "That role") .. " was just taken. Pick someone else.")
	elseif action == "AutoPicked" then
		showNotice("Out of time. You're the " .. tostring(roleName):lower() .. ".")
	elseif action == "Confirmed" then
		confirmed = true
		local before = player.Character
		finish(roleName)
		-- your NEW body (you already had one in the lobby), then open your eyes
		local waited = os.clock()
		while (not player.Character or player.Character == before) and os.clock() - waited < 6 do
			task.wait(0.05)
		end
		task.wait(0.3)
		cleanup()
		shakeRoot.Visible = false
		local open = tween(curtain, 1.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		open.Completed:Wait()
		ambience:Destroy()
		gui:Destroy()
		script:Destroy()
	end
end)
