-- LobbyAtmosphere
-- Place in: StarterPlayer > StarterPlayerScripts (a LocalScript)
--
-- Brings the hideout to life while you wait there:
--   * the old TVs (built with BuildNewsWall) switch on: static, colour bars,
--     WKRT Channel 8 news about the Holloway family, and now and then a tape
--     that shouldn't be playing. They light the room with their glow, and the
--     VCR blinks 12:00.
--   * some of the fluorescent tubes are going: they buzz, stutter and die for a
--     moment; one is almost dead
--   * a storm overhead you hear through the ceiling. When the thunder hits
--     the power surges: every light stutters and the TVs tear
--   * rarely, the power goes out completely for a few seconds... and
--     something whispers right behind you
--   * the colours go cold and a little sickly, like old fluorescent light
-- It all only happens on your own screen and only while you're in the hideout.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local FAULTY_TUBES = 0.3          -- this share of the fluorescent tubes misbehave
local THUNDER_EVERY = { 35, 70 }  -- seconds between thunder (and power surges)
local BLACKOUT_EVERY = { 200, 380 }
local TV_CHANNEL_TIME = { 4, 10 } -- seconds on a channel before it flips

local SND = {
	hum = "rbxassetid://9116272374",
	storm = "rbxassetid://9120018695",
	rain = "rbxassetid://112226054662295",
	thunder = "rbxassetid://4961240438",
	thud = "rbxassetid://9116673944",
	whisper = "rbxassetid://133571705093198",
	tick = "rbxassetid://9119727134",
}

local NEWS = {
	{ "BREAKING", "HOLLOWAY FAMILY STILL MISSING", "DAY 14 - POLICE CALL OFF THE SEARCH" },
	{ "WKRT 8 NEWS", "\"NOBODY WHO WENT DOWN CAME BACK\"", "NEIGHBOURS REPORT LIGHTS IN THE EMPTY HOUSE" },
	{ "LIVE", "CHANNEL 8 CREW TO ENTER HOLLOWAY HOUSE", "TONIGHT AT 11" },
	{ "SPECIAL REPORT", "WHAT IS UNDER THE HILL?", "THE CELLARS WERE SEALED IN 1961" },
	{ "WEATHER", "SEVERE STORM WARNING", "STAY INDOORS. STAY TOGETHER." },
}
local TICKER = "WKRT CHANNEL 8  •  HOLLOWAY FAMILY: DAY 14  •  SEARCH CALLED OFF  •  "
	.. "\"WE HEARD SCRATCHING UNDER THE FLOOR\" - NEIGHBOUR  •  CREW ENTERS THE HOUSE TONIGHT  •  NOV 13 1987  •  "
local TAPE_LINES = { "DON'T WATCH THE TAPE", "IT KNOWS YOUR NAME", "WE WENT DOWN", "STAY TOGETHER", "KEEP THE LIGHT ON",
	"IT HEARS YOU", "NOV 13 1987  03:12 AM", "WHY DID YOU COME BACK" }

local function sound(id, parent, volume, speed, looped)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.Looped = looped or false
	s.Parent = parent
	s:Play()
	if not looped then
		Debris:AddItem(s, 12)
	end
	return s
end

--------------------------------------------------
-- WHERE THE HIDEOUT IS
--------------------------------------------------

local hideout = workspace:WaitForChild("Hideout", 30)
if not hideout then
	return
end
local boxCF, boxSize = hideout:GetBoundingBox()

local function inHideout()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local p = boxCF:PointToObjectSpace(root.Position)
	local h = boxSize / 2 + Vector3.new(4, 6, 4)
	return math.abs(p.X) < h.X and math.abs(p.Y) < h.Y and math.abs(p.Z) < h.Z
end

local function menuOpen()
	return playerGui:FindFirstChild("MainMenuGui") ~= nil
end

--------------------------------------------------
-- THE FLUORESCENT TUBES
--------------------------------------------------

-- a tube: a long glowing (Neon) part with a light in it
local tubes = {}
local allLights = {}
for _, light in ipairs(hideout:GetDescendants()) do
	if light:IsA("Light") then
		local part = light.Parent
		local entry = { light = light, brightness = light.Brightness, part = part:IsA("BasePart") and part or nil }
		entry.neon = entry.part ~= nil and entry.part.Material == Enum.Material.Neon
		table.insert(allLights, entry)
		if entry.part and entry.part.Material == Enum.Material.Neon then
			local s = { entry.part.Size.X, entry.part.Size.Y, entry.part.Size.Z }
			table.sort(s)
			if s[3] >= s[2] * 2.5 then
				entry.colour = entry.part.Color
				table.insert(tubes, entry)
			end
		end
	end
end

-- (no long glowing tubes? then the panel lights in the ceiling will do)
if #tubes == 0 then
	for _, entry in ipairs(allLights) do
		if entry.light:IsA("SurfaceLight") then
			table.insert(tubes, entry)
		end
	end
end

local function setTube(entry, level)
	entry.light.Brightness = entry.brightness * level
	if entry.part and entry.colour then
		entry.part.Material = level > 0.35 and Enum.Material.Neon or Enum.Material.SmoothPlastic
		entry.part.Color = entry.colour and entry.colour:Lerp(Color3.fromRGB(70, 72, 70), 1 - math.clamp(level, 0, 1))
			or entry.part.Color
	end
end

-- pick the bad ones (the same ones every time, so it feels like a real room)
local faulty = {}
local dying = nil
table.sort(tubes, function(a, b)
	local pa = a.part and a.part.Position or Vector3.zero
	local pb = b.part and b.part.Position or Vector3.zero
	return pa.X + pa.Z * 0.37 < pb.X + pb.Z * 0.37
end)
for i, entry in ipairs(tubes) do
	if (i * 7919) % 100 < FAULTY_TUBES * 100 then
		table.insert(faulty, entry)
	end
end
if #tubes > 2 then
	dying = tubes[math.max(1, math.floor(#tubes * 0.6))]
end
for _, entry in ipairs(faulty) do
	if entry.part then
		local hum = sound(SND.hum, entry.part, 0, 0.55, true)
		hum.RollOffMaxDistance = 30
		hum.RollOffMinDistance = 4
		entry.hum = hum
	end
end

local busyLights = false

local function stutter(entry, times, dead)
	task.spawn(function()
		for _ = 1, times do
			setTube(entry, dead and 0.05 or 0.08)
			task.wait(0.03 + math.random() * 0.09)
			setTube(entry, dead and (math.random() < 0.5 and 0.6 or 0.1) or 1)
			task.wait(0.03 + math.random() * 0.12)
		end
		setTube(entry, dead and 0.06 or 1)
	end)
end

--------------------------------------------------
-- THE TVs
--------------------------------------------------

local tvs = {}
local function addScreen(screen)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CRT"
	gui.Adornee = screen
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.MaxDistance = 120
	gui.ClipsDescendants = true
	gui.Parent = playerGui

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	bg.BackgroundColor3 = Color3.fromRGB(10, 12, 12)
	bg.Parent = gui

	-- static: a grid of grey cells
	local static = Instance.new("Frame")
	static.Size = UDim2.fromScale(1, 1)
	static.BackgroundTransparency = 1
	static.Parent = gui
	local cells = {}
	for y = 0, 6 do
		for x = 0, 9 do
			local c = Instance.new("Frame")
			c.Position = UDim2.fromScale(x / 10, y / 7)
			c.Size = UDim2.fromScale(0.1 + 0.002, 1 / 7 + 0.002)
			c.BorderSizePixel = 0
			c.Parent = static
			table.insert(cells, c)
		end
	end

	-- colour bars
	local bars = Instance.new("Frame")
	bars.Size = UDim2.fromScale(1, 1)
	bars.BackgroundTransparency = 1
	bars.Parent = gui
	local BAR = { { 192, 192, 192 }, { 192, 192, 0 }, { 0, 192, 192 }, { 0, 192, 0 }, { 192, 0, 192 }, { 192, 0, 0 }, { 0, 0, 192 } }
	for i, c in ipairs(BAR) do
		local b = Instance.new("Frame")
		b.Position = UDim2.fromScale((i - 1) / 7, 0)
		b.Size = UDim2.fromScale(1 / 7 + 0.002, 0.72)
		b.BorderSizePixel = 0
		b.BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3])
		b.Parent = bars
	end
	local standBy = Instance.new("TextLabel")
	standBy.Position = UDim2.fromScale(0, 0.74)
	standBy.Size = UDim2.fromScale(1, 0.24)
	standBy.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
	standBy.BorderSizePixel = 0
	standBy.Font = Enum.Font.Arcade
	standBy.TextScaled = true
	standBy.TextColor3 = Color3.fromRGB(230, 230, 230)
	standBy.Text = "PLEASE STAND BY"
	standBy.Parent = bars

	-- the news
	local news = Instance.new("Frame")
	news.Size = UDim2.fromScale(1, 1)
	news.BackgroundColor3 = Color3.fromRGB(14, 30, 92)
	news.BorderSizePixel = 0
	news.Parent = gui
	local logo = Instance.new("TextLabel")
	logo.Position = UDim2.fromScale(0.05, 0.05)
	logo.Size = UDim2.fromScale(0.3, 0.2)
	logo.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
	logo.BorderSizePixel = 0
	logo.Font = Enum.Font.SourceSansBold
	logo.TextScaled = true
	logo.TextColor3 = Color3.new(1, 1, 1)
	logo.Text = "8"
	logo.Parent = news
	local tag = Instance.new("TextLabel")
	tag.Position = UDim2.fromScale(0.38, 0.07)
	tag.Size = UDim2.fromScale(0.58, 0.14)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.SourceSansBold
	tag.TextScaled = true
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.TextColor3 = Color3.fromRGB(255, 220, 90)
	tag.Parent = news
	local headline = Instance.new("TextLabel")
	headline.Position = UDim2.fromScale(0.05, 0.3)
	headline.Size = UDim2.fromScale(0.9, 0.3)
	headline.BackgroundTransparency = 1
	headline.Font = Enum.Font.SourceSansBold
	headline.TextScaled = true
	headline.TextWrapped = true
	headline.TextColor3 = Color3.new(1, 1, 1)
	headline.Parent = news
	local sub = headline:Clone()
	sub.Position = UDim2.fromScale(0.05, 0.6)
	sub.Size = UDim2.fromScale(0.9, 0.16)
	sub.Font = Enum.Font.SourceSans
	sub.TextColor3 = Color3.fromRGB(190, 200, 230)
	sub.Parent = news
	local tickerBar = Instance.new("Frame")
	tickerBar.Position = UDim2.fromScale(0, 0.82)
	tickerBar.Size = UDim2.fromScale(1, 0.14)
	tickerBar.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
	tickerBar.BorderSizePixel = 0
	tickerBar.ClipsDescendants = true
	tickerBar.Parent = news
	local ticker = Instance.new("TextLabel")
	ticker.Size = UDim2.fromScale(6, 1)
	ticker.BackgroundTransparency = 1
	ticker.Font = Enum.Font.SourceSansBold
	ticker.TextScaled = true
	ticker.TextXAlignment = Enum.TextXAlignment.Left
	ticker.TextColor3 = Color3.new(1, 1, 1)
	ticker.Text = TICKER .. TICKER
	ticker.Parent = tickerBar

	-- the tape that shouldn't be playing
	local tape = Instance.new("Frame")
	tape.Size = UDim2.fromScale(1, 1)
	tape.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
	tape.BorderSizePixel = 0
	tape.Parent = gui
	local play = Instance.new("TextLabel")
	play.Position = UDim2.fromScale(0.05, 0.05)
	play.Size = UDim2.fromScale(0.4, 0.14)
	play.BackgroundTransparency = 1
	play.Font = Enum.Font.Code
	play.TextScaled = true
	play.TextXAlignment = Enum.TextXAlignment.Left
	play.TextColor3 = Color3.fromRGB(230, 230, 230)
	play.Text = "PLAY ▶"
	play.Parent = tape
	local line = Instance.new("TextLabel")
	line.Position = UDim2.fromScale(0.05, 0.38)
	line.Size = UDim2.fromScale(0.9, 0.24)
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.SpecialElite
	line.TextScaled = true
	line.TextColor3 = Color3.fromRGB(200, 40, 34)
	line.Parent = tape
	local stamp = play:Clone()
	stamp.Position = UDim2.fromScale(0.05, 0.82)
	stamp.Size = UDim2.fromScale(0.9, 0.12)
	stamp.Text = "NOV. 13 1987   HOLLOWAY EST."
	stamp.Parent = tape

	local tv = {
		screen = screen, gui = gui, bg = bg, static = static, cells = cells, bars = bars, news = news, tape = tape,
		tag = tag, headline = headline, sub = sub, ticker = ticker, line = line,
		glow = screen:FindFirstChild("ScreenGlow"),
		channel = "static", nextFlip = os.clock() + math.random() * 3, burstUntil = 0, seed = math.random() * 100,
	}
	table.insert(tvs, tv)
	return tv
end

local function setChannel(tv, channel)
	tv.channel = channel
	tv.static.Visible = channel == "static"
	tv.bars.Visible = channel == "bars"
	tv.news.Visible = channel == "news"
	tv.tape.Visible = channel == "tape"
	if channel == "news" then
		local story = NEWS[math.random(#NEWS)]
		tv.tag.Text, tv.headline.Text, tv.sub.Text = story[1], story[2], story[3]
	elseif channel == "tape" then
		tv.line.Text = TAPE_LINES[math.random(#TAPE_LINES)]
	end
	tv.burstUntil = os.clock() + 0.15 + math.random() * 0.2       -- a burst of static between channels
end

local function glowColour(tv)
	if os.clock() < tv.burstUntil or tv.channel == "static" then
		return Color3.fromRGB(200, 210, 220), 0.9
	elseif tv.channel == "bars" then
		return Color3.fromRGB(220, 200, 230), 1.1
	elseif tv.channel == "news" then
		return Color3.fromRGB(90, 120, 255), 1.3
	end
	return Color3.fromRGB(255, 60, 50), 0.7
end

for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("CRTScreen") then
		addScreen(d)
	end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("BasePart") and d:GetAttribute("CRTScreen") then
		task.defer(addScreen, d)
	end
end)
for _, tv in ipairs(tvs) do
	setChannel(tv, ({ "static", "news", "bars", "news", "static" })[math.random(5)])
end

local clocks = {}
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("VCRClock") then
		local sg = Instance.new("SurfaceGui")
		sg.Adornee = d
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.Brightness = 2
		sg.Parent = playerGui
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Arcade
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(120, 255, 150)
		l.Text = "12:00"
		l.Parent = sg
		table.insert(clocks, { part = d, label = l })
	end
end

--------------------------------------------------
-- STORM, SURGES, BLACKOUTS
--------------------------------------------------

local ambience = Instance.new("Folder")
ambience.Name = "LobbyAmbience"
ambience.Parent = workspace.CurrentCamera
local storm = sound(SND.storm, ambience, 0, 0.8, true)
local rain = sound(SND.rain, ambience, 0, 0.75, true)
local active = false
local nextThunder = os.clock() + 12
local nextBlackout = os.clock() + BLACKOUT_EVERY[1] * 0.6
local nextFlicker = os.clock() + 2

local grade = nil
local function setActive(on)
	if on == active then
		return
	end
	active = on
	local fade = TweenInfo.new(2)
	TweenService:Create(storm, fade, { Volume = on and 0.22 or 0 }):Play()
	TweenService:Create(rain, fade, { Volume = on and 0.14 or 0 }):Play()
	for _, entry in ipairs(faulty) do
		if entry.hum then
			TweenService:Create(entry.hum, fade, { Volume = on and 0.12 or 0 }):Play()
		end
	end
	if on then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "LobbyGrade"
		grade.Parent = Lighting
		TweenService:Create(grade, fade, { Saturation = -0.22, Contrast = 0.14, TintColor = Color3.fromRGB(222, 236, 228) }):Play()
	elseif grade then
		local g = grade
		grade = nil
		TweenService:Create(g, fade, { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) }):Play()
		Debris:AddItem(g, 2.2)
	end
end

local function surge(strength)
	-- every tube stutters at once, the TVs tear
	for _, entry in ipairs(tubes) do
		if entry ~= dying then
			stutter(entry, math.random(1, 2 + strength), false)
		end
	end
	for _, tv in ipairs(tvs) do
		tv.burstUntil = os.clock() + 0.3 + math.random() * 0.4
	end
end

local function blackout()
	busyLights = true
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	for _, entry in ipairs(allLights) do
		entry.light.Brightness = 0
		if entry.neon then
			entry.part.Material = Enum.Material.SmoothPlastic
		end
	end
	local was = {}
	for _, tv in ipairs(tvs) do
		was[tv] = tv.channel
		tv.gui.Enabled = false
		if tv.glow then
			tv.glow.Brightness = 0
		end
	end
	task.wait(1.2)
	-- something right behind you
	if root and root.Parent then
		local behind = Instance.new("Attachment")
		behind.WorldPosition = (root.CFrame * CFrame.new(0.6, 1.4, 1.6)).Position
		behind.Parent = workspace.Terrain
		local w = sound(SND.whisper, behind, 1.1, 0.85)
		w.RollOffMinDistance = 2
		w.RollOffMaxDistance = 30
		Debris:AddItem(behind, 6)
	end
	task.wait(1.6)
	-- back on, every TV showing the same thing for a second
	for _, tv in ipairs(tvs) do
		tv.gui.Enabled = true
		setChannel(tv, "tape")
		tv.line.Text = "WE CAN SEE YOU"
	end
	for _, entry in ipairs(allLights) do
		entry.light.Brightness = entry.brightness
		if entry.neon then
			entry.part.Material = Enum.Material.Neon
		end
	end
	surge(2)
	task.wait(1.4)
	for _, tv in ipairs(tvs) do
		setChannel(tv, was[tv] == "tape" and "static" or was[tv])
	end
	if dying then
		setTube(dying, 0.06)
	end
	busyLights = false
end

--------------------------------------------------
-- EVERY FRAME
--------------------------------------------------

if dying then
	setTube(dying, 0.06)
end
local lastStatic = 0

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	setActive(inHideout() and not menuOpen())
	if not active then
		return
	end

	-- the tubes
	if not busyLights and now >= nextFlicker then
		nextFlicker = now + 0.8 + math.random() * 3.5
		if #faulty > 0 then
			stutter(faulty[math.random(#faulty)], math.random(1, 5), false)
		end
		if dying and math.random() < 0.35 then
			stutter(dying, math.random(2, 6), true)
		end
	end

	-- thunder overhead: the power surges
	if not busyLights and now >= nextThunder then
		nextThunder = now + THUNDER_EVERY[1] + math.random() * (THUNDER_EVERY[2] - THUNDER_EVERY[1])
		local big = math.random() < 0.4
		sound(SND.thunder, ambience, big and 0.55 or 0.3, 0.75 + math.random() * 0.15)
		task.delay(big and 0.15 or 0.6, function()
			sound(SND.thud, ambience, 0.2, 0.4)
			surge(big and 2 or 1)
		end)
	end

	-- the rare blackout
	if not busyLights and now >= nextBlackout then
		nextBlackout = now + BLACKOUT_EVERY[1] + math.random() * (BLACKOUT_EVERY[2] - BLACKOUT_EVERY[1])
		task.spawn(blackout)
	end

	-- the TVs
	local doStatic = now - lastStatic > 1 / 24
	if doStatic then
		lastStatic = now
	end
	for _, tv in ipairs(tvs) do
		if not tv.screen.Parent then
			continue
		end
		if now >= tv.nextFlip and not busyLights then
			tv.nextFlip = now + TV_CHANNEL_TIME[1] + math.random() * (TV_CHANNEL_TIME[2] - TV_CHANNEL_TIME[1])
			local r = math.random()
			setChannel(tv, r < 0.42 and "news" or r < 0.66 and "static" or r < 0.88 and "bars" or "tape")
		end
		local bursting = now < tv.burstUntil
		tv.static.Visible = bursting or tv.channel == "static"
		if doStatic and tv.static.Visible then
			for _, c in ipairs(tv.cells) do
				local v = math.random(20, 235)
				c.BackgroundColor3 = Color3.fromRGB(v, v, v)
			end
		end
		if tv.channel == "news" then
			local x = -((now * 0.06 + tv.seed) % 3)
			tv.ticker.Position = UDim2.fromScale(x, 0)
		elseif tv.channel == "tape" then
			-- the line jitters and drops out like a worn tape
			tv.line.Position = UDim2.fromScale(0.05 + (math.random() - 0.5) * 0.02, 0.38)
			tv.line.Visible = math.random() > 0.08
		end
		if tv.glow and not busyLights then
			local colour, brightness = glowColour(tv)
			tv.glow.Color = colour
			tv.glow.Brightness = brightness * (0.85 + 0.15 * math.noise(now * 9, tv.seed))
		end
	end

	-- the VCR blinks 12:00
	for _, c in ipairs(clocks) do
		c.label.Visible = (now % 1.2) < 0.7
	end
end)
