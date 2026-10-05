-- MainMenu
-- Before the lobby: the foyer of the old mansion on a stormy night, seen
-- through the journalist's camcorder. Four old plaques hang on chains under
-- a swinging bulb - PLAY, HOW TO PLAY, SETTINGS, CREDITS - and the pages
-- show on the canvas on the easel. Lightning blazes through the windows
-- (the portraits' eyes catch it), thunder rolls, the clock ticks.
-- PLAY: a strike, the camera rushes up the stairs through the open doors
-- into the dark... and you open your eyes in the lobby.
--
-- (Skipped when you come back from a match - you go straight to the lobby.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
if TeleportService:GetArrivingTeleportGui() ~= nil then
	return    -- back from a match: straight into the lobby
end
local scene = workspace:WaitForChild("MainMenuScene", 30)
if not scene then
	return
end
local O = scene:GetAttribute("Origin")
local menuParts = scene:WaitForChild("Menu")
local camera = workspace.CurrentCamera

local BONE = Color3.fromRGB(222, 212, 192)
local DIM = Color3.fromRGB(140, 130, 116)
local RED = Color3.fromRGB(190, 40, 30)
local TYPE = Enum.Font.SpecialElite
local HAND = Enum.Font.Kalam

local SND = {
	storm = "rbxassetid://9120018695", rain = "rbxassetid://112226054662295", thunder = "rbxassetid://4961240438",
	tick = "rbxassetid://9119727134", creak = "rbxassetid://9116522890", buzz = "rbxassetid://9116272374",
	thud = "rbxassetid://9116673944", paper = "rbxassetid://9117233449", whoosh = "rbxassetid://9116892712",
}

local function tween(o, t, goal, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function noise(t, s) return math.noise(t, s, 0.41) end
local function smooth(a) a = math.clamp(a, 0, 1) return a * a * (3 - 2 * a) end
local function ambience() return player:GetAttribute("Ambience") or 0.8 end
local sounds = {}
local function sound(id, volume, speed, looped, keep)
	local s = new("Sound", { SoundId = id, Volume = volume * ambience(), PlaybackSpeed = speed or 1, Looped = looped or false }, SoundService)
	s:SetAttribute("BaseVolume", volume)
	s:Play()
	if looped or keep then table.insert(sounds, s) end
	if not looped then
		s.Ended:Once(function() s:Destroy() end)
		task.delay(15, function() if s.Parent then s:Destroy() end end)
	end
	return s
end

--------------------------------------------------
-- TAKE OVER: your body waits in the lobby, the screen is ours
--------------------------------------------------

local open = true
local hidden = {}
local function hideOthers()
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "MainMenuGui" and not g.Name:find("Holder") then
			hidden[g] = true
			g.Enabled = false
		end
	end
end
hideOthers()
local guiWatch = player.PlayerGui.ChildAdded:Connect(function(g)
	task.defer(function()
		if open and g:IsA("ScreenGui") and g.Enabled and g.Name ~= "MainMenuGui" and not g.Name:find("Holder") and g.Name ~= "RoleSelectionGui" then
			hidden[g] = true
			g.Enabled = false
		end
	end)
end)
local function holdBody(hold)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then root.Anchored = hold end
end
task.spawn(function()
	local c = player.Character or player.CharacterAdded:Wait()
	c:WaitForChild("HumanoidRootPart", 10)
	if open then holdBody(true) end
end)
local charConn = player.CharacterAdded:Connect(function(c)
	if open then c:WaitForChild("HumanoidRootPart", 10) holdBody(true) end
end)

-- the foyer is lit by its own lamps; while the menu's up the night outside
-- the lobby lets a bit more of it through
local Lighting = game:GetService("Lighting")
local lightWas = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, ExposureCompensation = Lighting.ExposureCompensation }
Lighting.Ambient = Color3.fromRGB(58, 54, 52)
Lighting.OutdoorAmbient = Color3.fromRGB(48, 50, 60)
Lighting.ExposureCompensation = 0.45

local gui = new("ScreenGui", { Name = "MainMenuGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60, ZIndexBehavior = Enum.ZIndexBehavior.Sibling },
	player:WaitForChild("PlayerGui"))
local curtain = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 50 }, gui)
local flashFrame = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(225, 232, 255), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 49 }, gui)

-- the camcorder: REC, timecode, battery, a little tape noise
local hud = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local recDot = new("Frame", { Position = UDim2.new(0, 34, 0, 30), Size = UDim2.fromOffset(13, 13), BackgroundColor3 = RED, BorderSizePixel = 0 }, hud)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, recDot)
local function hudText(props)
	local d = { BackgroundTransparency = 1, Font = TYPE, TextColor3 = BONE, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in pairs(props) do d[k] = v end
	return new("TextLabel", d, hud)
end
hudText({ Position = UDim2.new(0, 54, 0, 26), Size = UDim2.fromOffset(60, 22), Text = "REC", TextColor3 = RED })
local timecode = hudText({ Position = UDim2.new(0, 104, 0, 26), Size = UDim2.fromOffset(200, 22), Text = "" })
hudText({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -96, 0, 26), Size = UDim2.fromOffset(60, 22), Text = "SP", TextXAlignment = Enum.TextXAlignment.Right })
local battery = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -38, 0, 29), Size = UDim2.fromOffset(46, 18), BackgroundTransparency = 1 }, hud)
new("UIStroke", { Color = BONE, Thickness = 2 }, battery)
new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, 2, 0.5, 0), Size = UDim2.fromOffset(4, 8), BackgroundColor3 = BONE, BorderSizePixel = 0 }, battery)
for i = 0, 2 do
	new("Frame", { Position = UDim2.fromOffset(3 + i * 14, 3), Size = UDim2.fromOffset(11, 12), BackgroundColor3 = BONE, BorderSizePixel = 0 }, battery)
end
hudText({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 34, 1, -24), Size = UDim2.fromOffset(300, 20), Text = "NOV. 13 1987   HOLLOWAY EST.", TextSize = 15, TextColor3 = DIM })
for _, c in ipairs({ { 0, 0, 0, 0 }, { 1, 0, -1, 0 }, { 0, 1, 0, -1 }, { 1, 1, -1, -1 } }) do
	local f = new("Frame", { AnchorPoint = Vector2.new(c[1], c[2]), Position = UDim2.new(c[1], c[3] * 18 + (c[1] == 0 and 18 or 0), c[2], c[4] * 18 + (c[2] == 0 and 18 or 0)),
		Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1 }, hud)
	new("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, c[2]), AnchorPoint = Vector2.new(0, c[2]), BackgroundColor3 = BONE, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, f)
	new("Frame", { Size = UDim2.new(0, 2, 1, 0), Position = UDim2.fromScale(c[1], 0), AnchorPoint = Vector2.new(c[1], 0), BackgroundColor3 = BONE, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, f)
end
for _, side in ipairs({ { 0, 0, 0 }, { 1, 0, 180 }, { 0, 0, 90 }, { 0, 1, -90 } }) do
	local vertical = side[3] == 90 or side[3] == -90
	local f = new("Frame", { AnchorPoint = Vector2.new(side[1], side[2]), Position = UDim2.fromScale(side[1], side[2]), ZIndex = 0,
		Size = vertical and UDim2.fromScale(1, 0.28) or UDim2.fromScale(0.22, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, hud)
	new("UIGradient", { Rotation = side[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }) }, f)
end
local scan = {}
for i = 1, 3 do
	scan[i] = new("Frame", { Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(220, 220, 230), BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 2 }, hud)
end

-- the title
-- (the title is the neon sign in the room now; this one stays hidden)
local title = new("TextLabel", { Visible = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.06, 0), Size = UDim2.fromScale(0.62, 0.11), BackgroundTransparency = 1,
	Font = TYPE, Text = "J O U R N A L I S T", TextScaled = true, TextColor3 = BONE, TextTransparency = 1 }, hud)
new("UITextSizeConstraint", { MaxTextSize = 72 }, title)
new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.2 }, title)
local subtitle = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.045, 0), Size = UDim2.fromScale(0.5, 0.035), BackgroundTransparency = 1,
	Font = HAND, Text = "what happened in the Holloway house?", TextScaled = true, TextColor3 = Color3.fromRGB(200, 90, 76), TextTransparency = 1 }, hud)
new("UITextSizeConstraint", { MaxTextSize = 26 }, subtitle)

--------------------------------------------------
-- THE PLAQUES (buttons hung on chains)
--------------------------------------------------

local plaques = {}
local LABELS = { Play = "PLAY", HowTo = "HOW TO PLAY", Settings = "SETTINGS", Credits = "CREDITS" }
local hovered = nil
local busy = false
local showPage
local play

for key, text in pairs(LABELS) do
	local part = menuParts:FindFirstChild("Plaque_" .. key)
	if part then
		local pl = { key = key, part = part, rest = part:GetAttribute("Rest") or part.CFrame, swing = 0, swingV = 0, glow = 0, extras = {} }
		for _, d in ipairs(menuParts:GetChildren()) do
			if d:GetAttribute("Plaque") == key then
				table.insert(pl.extras, { part = d, rel = pl.rest:ToObjectSpace(d.CFrame) })
			end
		end
		local sg = new("SurfaceGui", { Name = "Plaque_" .. key, Adornee = part, Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 70, LightInfluence = 1, MaxDistance = 200, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, gui)
		sg.Parent = player.PlayerGui
		local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = TYPE, Text = text, TextScaled = true,
			TextColor3 = Color3.fromRGB(205, 192, 168), AutoButtonColor = false }, sg)
		new("UIPadding", { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.18, 0), PaddingLeft = UDim.new(0.1, 0), PaddingRight = UDim.new(0.1, 0) }, b)
		pl.stroke = new("UIStroke", { Color = Color3.fromRGB(20, 12, 8), Thickness = 2, Transparency = 0.15 }, b)
		pl.button = b
		pl.gui = sg
		b.MouseEnter:Connect(function()
			if busy then return end
			hovered = pl
			pl.swingV -= 2.2
			sound(SND.tick, 0.18, 0.55)
		end)
		b.MouseLeave:Connect(function()
			if hovered == pl then hovered = nil end
		end)
		b.Activated:Connect(function()
			if busy then return end
			pl.swingV -= 6
			sound(SND.thud, 0.35, 1.6)
			sound(SND.creak, 0.12, 0.5)
			if key == "Play" then
				play()
			else
				showPage(key)
			end
		end)
		plaques[key] = pl
	end
end

--------------------------------------------------
-- THE CANVAS (pages)
--------------------------------------------------

local canvasPart = menuParts:WaitForChild("MenuCanvas")
local canvasGui = new("SurfaceGui", { Name = "MenuCanvas", Adornee = canvasPart, Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
	PixelsPerStud = 90, LightInfluence = 0.75, MaxDistance = 200, ResetOnSpawn = false }, player.PlayerGui)
local page = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(24, 21, 18), BorderSizePixel = 0 }, canvasGui)
new("UIPadding", { PaddingTop = UDim.new(0.06, 0), PaddingLeft = UDim.new(0.07, 0), PaddingRight = UDim.new(0.07, 0), PaddingBottom = UDim.new(0.05, 0) }, page)
local pageTitle = new("TextLabel", { Size = UDim2.fromScale(1, 0.13), BackgroundTransparency = 1, Font = TYPE, TextScaled = true, TextColor3 = BONE, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, page)
new("Frame", { Position = UDim2.fromScale(0, 0.145), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = Color3.fromRGB(120, 96, 60), BorderSizePixel = 0 }, page)
local body = new("Frame", { Position = UDim2.fromScale(0, 0.19), Size = UDim2.fromScale(1, 0.81), BackgroundTransparency = 1 }, page)

local function bodyText(text, y, h, props)
	local d = { Position = UDim2.fromScale(0, y), Size = UDim2.fromScale(1, h), BackgroundTransparency = 1, Font = TYPE, TextScaled = true,
		TextColor3 = Color3.fromRGB(196, 186, 166), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = text }
	for k, v in pairs(props or {}) do d[k] = v end
	local l = new("TextLabel", d, body)
	return l
end

local settingsData = {}
local saveRemote = ReplicatedStorage:WaitForChild("Menu", 10) and ReplicatedStorage.Menu:FindFirstChild("SaveSettings")
local function readSettings()
	settingsData = { Sensitivity = player:GetAttribute("Sensitivity") or 1, CameraShake = player:GetAttribute("CameraShake") ~= false,
		LowGraphics = player:GetAttribute("LowGraphics") == true, Ambience = player:GetAttribute("Ambience") or 0.8 }
end
local function pushSettings()
	for k, v in pairs(settingsData) do player:SetAttribute(k, v) end
	if saveRemote then saveRemote:FireServer(settingsData) end
	for _, s in ipairs(sounds) do
		if s.Parent then s.Volume = (s:GetAttribute("BaseVolume") or 0.3) * settingsData.Ambience end
	end
end

local PAGES = {}
PAGES.About = function()
	pageTitle.Text = "THE TAPE"
	bodyText("November 1987. The Holloway family vanished from their house on the hill. Nobody who went down into the cellars came back.", 0, 0.34)
	bodyText("You are five people with one camcorder and one night to find out why.", 0.4, 0.2, { TextColor3 = BONE })
	bodyText("stay together. keep the light on. don't let it hear you.", 0.72, 0.13, { Font = HAND, TextColor3 = Color3.fromRGB(200, 80, 66) })
end
PAGES.HowTo = function()
	pageTitle.Text = "HOW TO SURVIVE"
	local lines = {
		"WASD  move     SHIFT  sprint     C  crouch",
		"X  crawl  (under gaps, through vents)",
		"E  use / hide / squeeze     Q  peek",
		"RIGHT MOUSE  raise the camcorder     TAB  objectives",
	}
	for i, l in ipairs(lines) do bodyText(l, (i - 1) * 0.105, 0.09) end
	bodyText("THE SURVIVORS", 0.46, 0.08, { TextColor3 = BONE })
	local roles = { "ACROBAT  fast, slides, hard to catch", "MECHANIC  repairs, valves, long battery", "MEDIC  revives fast, starts with medicine",
		"SCOUT  hears them coming, marks monsters", "BRUTE  150 health, carries the fallen" }
	for i, r in ipairs(roles) do bodyText(r, 0.56 + (i - 1) * 0.088, 0.075, { TextColor3 = Color3.fromRGB(176, 166, 146) }) end
end
PAGES.Credits = function()
	pageTitle.Text = "CREDITS"
	bodyText("A game by", 0, 0.08)
	bodyText("ju27100000", 0.09, 0.14, { TextColor3 = BONE })
	bodyText("Sound: Pro Sound Effects and the Roblox Creator Store", 0.32, 0.16)
	bodyText("Thank you for playing. Don't watch the tape alone.", 0.62, 0.18, { Font = HAND, TextColor3 = Color3.fromRGB(200, 80, 66) })
end
PAGES.Settings = function()
	pageTitle.Text = "SETTINGS"
	readSettings()
	local rows = {
		{ "Look sensitivity", function() return string.format("%.1fx", settingsData.Sensitivity) end,
			function(d) settingsData.Sensitivity = math.clamp(math.floor((settingsData.Sensitivity + d * 0.1) * 10 + 0.5) / 10, 0.4, 2) end },
		{ "Camera shake", function() return settingsData.CameraShake and "ON" or "OFF" end, function() settingsData.CameraShake = not settingsData.CameraShake end },
		{ "Low graphics (phones)", function() return settingsData.LowGraphics and "ON" or "OFF" end, function() settingsData.LowGraphics = not settingsData.LowGraphics end },
		{ "Ambience volume", function() return math.floor(settingsData.Ambience * 100 + 0.5) .. "%" end,
			function(d) settingsData.Ambience = math.clamp(settingsData.Ambience + d * 0.1, 0, 1) end },
	}
	for i, row in ipairs(rows) do
		local y = (i - 1) * 0.2
		bodyText(row[1], y + 0.02, 0.1, { Size = UDim2.fromScale(0.52, 0.1) })
		local value = new("TextLabel", { Position = UDim2.fromScale(0.68, y), Size = UDim2.fromScale(0.18, 0.13), BackgroundTransparency = 1, Font = TYPE, TextScaled = true,
			TextColor3 = BONE, Text = row[2]() }, body)
		local function btn(txt, x, d)
			local b = new("TextButton", { Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(0.11, 0.13), BackgroundColor3 = Color3.fromRGB(46, 38, 30), BorderSizePixel = 0,
				Font = TYPE, TextScaled = true, TextColor3 = BONE, Text = txt }, body)
			new("UIStroke", { Color = Color3.fromRGB(120, 96, 60), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
			b.Activated:Connect(function()
				row[3](d)
				value.Text = row[2]()
				sound(SND.tick, 0.25, 1.2)
				pushSettings()
			end)
		end
		btn("–", 0.56, -1)
		btn("+", 0.88, 1)
	end
	bodyText("saved automatically", 0.86, 0.08, { Font = HAND, TextColor3 = DIM })
end

local currentPage
showPage = function(key)
	if currentPage == key then return end
	currentPage = key
	sound(SND.paper, 0.3, 1.1)
	-- the canvas flickers dark, then the new page
	tween(page, 0.12, { BackgroundTransparency = 0 })
	for _, c in ipairs(body:GetChildren()) do c:Destroy() end
	PAGES[key]()
	for _, d in ipairs(page:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			local goal = d.TextTransparency
			d.TextTransparency = 1
			tween(d, 0.5, { TextTransparency = goal })
		end
	end
end
showPage("About")

--------------------------------------------------
-- THE ROOM
--------------------------------------------------

local bulb = menuParts:FindFirstChild("Bulb")
local bulbLight = bulb and bulb:FindFirstChild("BulbLight")
local swingParts = {}
local pivot = bulb and Vector3.new(bulb.Position.X, O.Y + 36, bulb.Position.Z) or (O + Vector3.new(0, 36, -27.5))
for _, n in ipairs({ "Bulb", "BulbSocket", "BulbCord" }) do
	local p = menuParts:FindFirstChild(n)
	if p then table.insert(swingParts, { part = p, rel = CFrame.new(pivot):ToObjectSpace(p.CFrame) }) end
end
local chandelier = scene:FindFirstChild("Decor") and scene.Decor:FindFirstChild("Chandelier")
local chPivot, chRest
if chandelier then
	local cf, size = chandelier:GetBoundingBox()
	chPivot = cf.Position + Vector3.new(0, size.Y / 2, 0)
	chRest = chandelier:GetPivot()
end
-- the portraits' eyes (only ever seen in the lightning)
local eyes = {}
for _, c in ipairs(scene.Decor:GetChildren()) do
	if c.Name == "PortraitCanvas" then
		for _, s in ipairs({ -1, 1 }) do
			local e = new("Part", { Name = "PortraitEye", Anchored = true, CanCollide = false, CastShadow = false, Size = Vector3.new(0.18, 0.1, 0.05),
				Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 236, 200), Transparency = 1,
				CFrame = c.CFrame * CFrame.new(s * (c.Size.X > 6 and 0.9 or 0.45), c.Size.Y * 0.22, -0.08) }, camera)
			table.insert(eyes, e)
		end
	end
end
local strikes = {}
for _, w in ipairs(scene.Windows:GetChildren()) do
	if w.Name == "WindowNight" then
		table.insert(strikes, { part = w, light = w:FindFirstChild("Lightning"), color = w.Color })
	end
end

local shake = 0
local onLightning     -- (the sign and the camcorder react; set further down)
local function lightning(big)
	if onLightning then onLightning(big) end
	task.spawn(function()
		local pattern = big and { 1, 0.1, 0.8, 0, 1, 0.3 } or { 0.9, 0.05, 0.6 }
		local showEyes = big or math.random() < 0.35
		for _, v in ipairs(pattern) do
			for _, s in ipairs(strikes) do
				if s.light then s.light.Brightness = 9 * v end
				s.part.Color = s.color:Lerp(Color3.fromRGB(230, 236, 255), v)
				s.part.Material = v > 0.3 and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
			for _, e in ipairs(eyes) do e.Transparency = (showEyes and v > 0.5) and 0.1 or 1 end
			flashFrame.BackgroundTransparency = 1 - 0.18 * v
			task.wait(0.04 + math.random() * 0.07)
		end
		for _, s in ipairs(strikes) do
			if s.light then s.light.Brightness = 0 end
			s.part.Color = s.color
			s.part.Material = Enum.Material.SmoothPlastic
		end
		for _, e in ipairs(eyes) do e.Transparency = 1 end
		flashFrame.BackgroundTransparency = 1
		task.wait(big and 0.25 or (0.5 + math.random() * 1.2))
		sound(SND.thunder, big and 0.9 or 0.55, 0.9 + math.random() * 0.2)
		shake = math.max(shake, big and 0.8 or 0.35)
	end)
end

-- ambience
sound(SND.storm, 0.42, 1, true)
sound(SND.rain, 0.3, 1, true)
task.spawn(function()
	local tock = false
	while open do
		task.wait(1)
		tock = not tock
		sound(SND.tick, 0.05, tock and 0.35 or 0.42)
	end
end)
task.spawn(function()
	task.wait(5)
	while open do
		lightning(false)
		task.wait(8 + math.random() * 12)
	end
end)
task.spawn(function()
	while open do
		task.wait(4 + math.random() * 7)
		if not open or not bulbLight then break end
		sound(SND.buzz, 0.1, 1.3)
		for _ = 1, math.random(2, 5) do
			bulbLight.Enabled = false
			if bulb then bulb.Material = Enum.Material.SmoothPlastic end
			task.wait(0.03 + math.random() * 0.08)
			bulbLight.Enabled = true
			if bulb then bulb.Material = Enum.Material.Neon end
			task.wait(0.03 + math.random() * 0.12)
		end
	end
end)
task.spawn(function()
	while open do
		task.wait(6 + math.random() * 9)
		if open then sound(SND.creak, 0.08, 0.32 + math.random() * 0.1) end
	end
end)

--------------------------------------------------
-- THE NEON SIGN, THE CAMCORDER ON ITS STRAP, THE FIRE, THE PIANO
--------------------------------------------------

local SND2 = {
	whisper = "rbxassetid://133571705093198", piano = "rbxassetid://9045773794", fire = "rbxassetid://77688442375055",
}
local signFolder = scene:FindFirstChild("NeonSign")
local letters = {}
local glows = {}
local NEON_ON, NEON_CORE, NEON_DEAD = Color3.fromRGB(255, 40, 34), Color3.fromRGB(255, 214, 205), Color3.fromRGB(70, 22, 20)
if signFolder then
	for _, p in ipairs(signFolder:GetChildren()) do
		if p.Name:match("^Letter_") then
			local i = p:GetAttribute("Index")
			local sg = new("SurfaceGui", { Name = "Neon_" .. i, Adornee = p, Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
				PixelsPerStud = 60, LightInfluence = 0, Brightness = 2.4, MaxDistance = 250, ResetOnSpawn = false }, player.PlayerGui)
			local halo = new("TextLabel", { Size = UDim2.fromScale(1.15, 1.15), Position = UDim2.fromScale(-0.075, -0.075), BackgroundTransparency = 1, Font = Enum.Font.Michroma,
				Text = p:GetAttribute("Char"), TextScaled = true, TextColor3 = NEON_ON, TextTransparency = 0.6 }, sg)
			new("UIStroke", { Color = NEON_ON, Thickness = 9, Transparency = 0.8 }, halo)
			local core = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.Michroma,
				Text = p:GetAttribute("Char"), TextScaled = true, TextColor3 = NEON_CORE }, sg)
			local stroke = new("UIStroke", { Color = NEON_ON, Thickness = 3.5, Transparency = 0.1 }, core)
			letters[i] = { gui = sg, halo = halo, core = core, stroke = stroke, on = true, dead = (i == 5), wild = (i == 7) }
		end
		if p.Name:match("^SignGlow") then table.insert(glows, p:FindFirstChild("Glow")) end
	end
end
local function setLetter(L, on)
	L.on = on
	L.core.TextColor3 = on and NEON_CORE or NEON_DEAD
	L.core.TextTransparency = on and 0 or 0.25
	L.stroke.Transparency = on and 0.1 or 0.9
	L.halo.Visible = on
	L.gui.Brightness = on and 2.4 or 1
end
local function refreshGlow()
	local lit = 0
	for _, L in pairs(letters) do if L.on then lit += 1 end end
	for _, g in ipairs(glows) do if g then g.Brightness = 1.1 * lit / 10 end end
end
for _, L in pairs(letters) do if L.dead then setLetter(L, false) end end
refreshGlow()
local signBuzzPart = signFolder and signFolder:FindFirstChild("SignGlow2")
if signBuzzPart then
	local b = new("Sound", { SoundId = SND.buzz, Volume = 0.1 * ambience(), PlaybackSpeed = 0.7, Looped = true, RollOffMaxDistance = 80 }, signBuzzPart)
	b:SetAttribute("BaseVolume", 0.1)
	b:Play()
	table.insert(sounds, b)
end
local function flickerLetter(L, times)
	task.spawn(function()
		for _ = 1, times do
			if not open then return end
			setLetter(L, false) refreshGlow()
			task.wait(0.03 + math.random() * 0.09)
			if not L.dead then setLetter(L, true) refreshGlow() end
			task.wait(0.02 + math.random() * 0.1)
		end
	end)
end
task.spawn(function()
	while open do
		task.wait(0.25)
		for _, L in pairs(letters) do
			if L.wild and math.random() < 0.18 then flickerLetter(L, math.random(1, 4))
			elseif L.dead and math.random() < 0.02 then
				-- the dead one sputters, almost catches... and doesn't
				task.spawn(function()
					for _ = 1, math.random(2, 5) do
						setLetter(L, true) refreshGlow() task.wait(0.02 + math.random() * 0.05)
						setLetter(L, false) refreshGlow() task.wait(0.04 + math.random() * 0.1)
					end
				end)
			elseif math.random() < 0.006 then flickerLetter(L, math.random(1, 2)) end
		end
	end
end)

-- the camcorder hangs by its strap from the T
local hanging = signFolder and signFolder:FindFirstChild("HangingCamcorder")
local strapAnchor = signFolder and signFolder:FindFirstChild("StrapAnchor")
local pend = { x = 0, z = 0, vx = 0, vz = 0, spin = 0, vspin = 0.15 }
local camRel, strapLen, strapPart, recLed
if hanging and strapAnchor then
	local shoe = hanging:FindFirstChild("hot_shoe_bracket", true)
	local hangPoint = shoe and (shoe.Position + Vector3.new(0, shoe.Size.Y, 0)) or hanging:GetPivot().Position
	local A = strapAnchor.Position
	strapLen = (A - hangPoint).Magnitude
	camRel = CFrame.new(hangPoint):ToObjectSpace(hanging:GetPivot())
	strapPart = new("Part", { Name = "Strap", Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false, Size = Vector3.new(0.14, strapLen, 0.05),
		Material = Enum.Material.Fabric, Color = Color3.fromRGB(20, 20, 22) }, camera)
	recLed = hanging:FindFirstChild("tally_recording_led", true)
	-- hover nudges it, a click makes the tape glitch
	local body = hanging:FindFirstChild("main_body_chassis", true) or hanging:FindFirstChildWhichIsA("BasePart", true)
	local cd = new("ClickDetector", { MaxActivationDistance = 200 }, body)
	cd.MouseHoverEnter:Connect(function()
		if busy then return end
		pend.vx += 0.5 pend.vspin += 0.8
		sound(SND.creak, 0.08, 1.4)
	end)
	cd.MouseClick:Connect(function()
		if busy then return end
		pend.vx += 1.4 pend.vz -= 0.8 pend.vspin += 2.5
		sound(SND2.whisper, 0.7, 1)
		shake = math.max(shake, 0.5)
		-- the tape glitches: static, a tear, a line that shouldn't be there
		task.spawn(function()
			local bits = {}
			for k = 1, 26 do
				table.insert(bits, new("Frame", { Position = UDim2.fromScale(math.random(), math.random()), Size = UDim2.new(math.random() * 0.5, 0, 0, math.random(2, 14)),
					BackgroundColor3 = Color3.fromRGB(230, 230, 235), BackgroundTransparency = math.random() * 0.5, BorderSizePixel = 0, ZIndex = 45 }, gui))
			end
			local msg = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.08), BackgroundTransparency = 1,
				Font = TYPE, TextScaled = true, Text = "DON'T WATCH THE TAPE", TextColor3 = RED, ZIndex = 46 }, gui)
			for _ = 1, 8 do
				for _, b in ipairs(bits) do
					b.Position = UDim2.fromScale(math.random(), math.random())
					b.Size = UDim2.new(math.random() * 0.6, 0, 0, math.random(2, 16))
				end
				msg.Visible = math.random() < 0.5
				msg.Position = UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.04, 0.5)
				flashFrame.BackgroundTransparency = 0.85 + math.random() * 0.15
				task.wait(0.05)
			end
			for _, b in ipairs(bits) do b:Destroy() end
			msg:Destroy()
			flashFrame.BackgroundTransparency = 1
		end)
	end)
end
onLightning = function(big)
	pend.vx += (big and 1.6 or 0.7) * (math.random() < 0.5 and -1 or 1)
	pend.vz += (big and 1.0 or 0.4) * (math.random() < 0.5 and -1 or 1)
	pend.vspin += big and 3 or 1.2
	for _, L in pairs(letters) do
		if math.random() < (big and 0.7 or 0.3) then flickerLetter(L, math.random(1, 3)) end
	end
end

-- the fire, the piano, the dying flashlight
local extra = scene:FindFirstChild("Extra")
local embers = extra and extra:FindFirstChild("Embers")
local fireGlow = embers and embers:FindFirstChild("FireGlow")
if embers then
	local s = new("Sound", { SoundId = SND2.fire, Volume = 0.35 * ambience(), Looped = true, RollOffMaxDistance = 60 }, embers)
	s:SetAttribute("BaseVolume", 0.35)
	s:Play()
	table.insert(sounds, s)
end
local piano = extra and extra:FindFirstChild("GrandPiano")
local pianoPart = piano and piano:FindFirstChildWhichIsA("BasePart", true)
task.spawn(function()
	task.wait(12)
	while open do
		if pianoPart then
			local s = new("Sound", { SoundId = SND2.piano, Volume = 0.45 * ambience(), PlaybackSpeed = 0.5 + math.random() * 0.18, RollOffMaxDistance = 90 }, pianoPart)
			s:Play()
			task.delay(1.2 + math.random() * 1.6, function() if s.Parent then tween(s, 1.2, { Volume = 0 }).Completed:Once(function() s:Destroy() end) end end)
		end
		task.wait(20 + math.random() * 25)
	end
end)
local torchBeam = extra and extra:FindFirstChild("FlashlightLens", true)
torchBeam = torchBeam and torchBeam:FindFirstChild("Beam")
task.spawn(function()
	while open and torchBeam do
		task.wait(5 + math.random() * 9)
		for _ = 1, math.random(2, 6) do
			torchBeam.Brightness = math.random() * 0.6
			task.wait(0.03 + math.random() * 0.1)
			torchBeam.Brightness = 2.2
			task.wait(0.03 + math.random() * 0.12)
		end
	end
end)

local propConn = RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 1 / 20)
	local t = os.clock()
	-- pendulum: swings and twists on the strap, settles slowly
	if hanging and camRel and strapAnchor then
		local g = 9.81 / math.max(strapLen, 1)
		pend.vx += (-g * pend.x - 0.35 * pend.vx) * dt
		pend.vz += (-g * pend.z - 0.35 * pend.vz) * dt
		pend.vspin += (-0.9 * pend.spin - 0.25 * pend.vspin) * dt
		pend.x += pend.vx * dt
		pend.z += pend.vz * dt
		pend.spin += pend.vspin * dt
		local A = strapAnchor.Position
		local swing = CFrame.new(A) * CFrame.Angles(pend.x + 0.02 * math.sin(t * 0.7), 0, pend.z + 0.015 * math.sin(t * 0.5))
		local hp = swing * CFrame.new(0, -strapLen, 0)
		hanging:PivotTo(CFrame.new(hp.Position) * (swing - swing.Position) * CFrame.Angles(0, pend.spin + 0.25 * math.sin(t * 0.31), 0) * camRel)
		strapPart.CFrame = CFrame.lookAt((A + hp.Position) / 2, hp.Position) * CFrame.Angles(math.rad(90), 0, 0)
		if recLed then recLed.Transparency = ((t % 1.1) < 0.6) and 0 or 0.85 end
	end
	-- the fire breathes
	if fireGlow then
		fireGlow.Brightness = 1.1 + 0.35 * noise(t * 3, 9) + 0.15 * noise(t * 11, 10)
		embers.Color = Color3.fromRGB(255, 80 + 30 * (0.5 + 0.5 * noise(t * 2, 11)), 30)
	end
end)

--------------------------------------------------
-- EVERY FRAME
--------------------------------------------------

local camStart = menuParts:WaitForChild("CamStart").CFrame
local camRest = menuParts:WaitForChild("CamRest").CFrame
local openedAt = os.clock()
local flight = nil       -- PLAY: { t0 }
local cine = nil         -- PLAY: a scripted shot, t -> (CFrame, FOV)
local parallax = Vector2.zero
local fovWas = camera.FieldOfView
local typeWas = camera.CameraType
local function bezier(a, b, c, d, t)
	local u = 1 - t
	return a * u * u * u + b * 3 * u * u * t + c * 3 * u * t * t + d * t * t * t
end
RunService:BindToRenderStep("MainMenuCamera", Enum.RenderPriority.Camera.Value + 70, function(dt)
	dt = math.min(dt, 1 / 20)
	local t = os.clock()
	camera.CameraType = Enum.CameraType.Scriptable
	-- a free cursor for the menu (the game's own camera locks it to the middle)
	if not busy then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	local shakeOn = player:GetAttribute("CameraShake") ~= false
	shake = math.max(0, shake - dt * 1.6)
	-- where the mouse is (the view leans that way a touch)
	local vp = camera.ViewportSize
	local m = UserInputService:GetMouseLocation()
	local want = Vector2.new(math.clamp(m.X / vp.X - 0.5, -0.5, 0.5), math.clamp(m.Y / vp.Y - 0.5, -0.5, 0.5))
	parallax = parallax:Lerp(want, 1 - math.exp(-2.5 * dt))
	local cf
	if cine then
		local fov
		cf, fov = cine(t)
		camera.FieldOfView = fov
	elseif flight then
		local u = math.clamp((t - flight.t0) / 2.6, 0, 1)
		local e = u < 0.5 and 2 * u * u or 1 - (-2 * u + 2) ^ 2 / 2
		local p = bezier(flight.a, menuParts.Fly1.Position, menuParts.Fly2.Position, menuParts.Fly3.Position, e)
		local ahead = bezier(flight.a, menuParts.Fly1.Position, menuParts.Fly2.Position, menuParts.Fly3.Position, math.min(1, e + 0.08))
		if (ahead - p).Magnitude < 0.05 then ahead = p + menuParts.Fly3.CFrame.LookVector end
		cf = CFrame.lookAt(p, ahead + Vector3.new(0, 0.6, 0))
		camera.FieldOfView = 58 + 26 * smooth(u * 1.4)
	else
		local a = smooth((t - openedAt) / 5)
		local base = camStart:Lerp(camRest, a)
		local drift = Vector3.new(0.35 * math.sin(t * 0.13), 0.18 * math.sin(t * 0.21), 0.25 * math.sin(t * 0.09))
		cf = (base + drift) * CFrame.Angles(math.rad(-parallax.Y * 4), math.rad(-parallax.X * 6), 0)
		camera.FieldOfView = 58
	end
	local hand = CFrame.Angles(math.rad(0.45 * noise(t * 0.5, 1)), math.rad(0.55 * noise(t * 0.45, 2)), math.rad(0.35 * noise(t * 0.35, 3)))
	local s = shakeOn and shake or 0
	local jolt = CFrame.Angles(math.rad(1.4 * s * noise(t * 28, 4)), math.rad(1.4 * s * noise(t * 28, 5)), math.rad(0.8 * s * noise(t * 24, 6)))
	camera.CFrame = cf * hand * jolt
	-- the bulb swings on its cord
	local ang = math.rad(3.2 * math.sin(t * 0.9) + 1.2 * math.sin(t * 1.7))
	local swing = CFrame.new(pivot) * CFrame.Angles(ang * 0.6, 0, ang)
	for _, sp in ipairs(swingParts) do sp.part.CFrame = swing * sp.rel end
	-- the chandelier, barely
	if chandelier and chPivot then
		local ca = math.rad(0.8 * math.sin(t * 0.37))
		chandelier:PivotTo(CFrame.new(chPivot) * CFrame.Angles(ca, 0, ca * 0.6) * CFrame.new(-chPivot) * chRest)
	end
	-- the plaques hang and sway; the one under your hand swings out and glows
	for _, pl in pairs(plaques) do
		local target = (hovered == pl) and -9 or 0
		pl.swingV += (-(pl.swing - target) * 40 - pl.swingV * 4.5) * dt
		pl.swing += pl.swingV * dt
		pl.glow += (((hovered == pl) and 1 or 0) - pl.glow) * (1 - math.exp(-8 * dt))
		local idle = 1.2 * math.sin(t * 0.8 + pl.rest.Position.Y)
		local top = pl.rest * CFrame.new(0, 0.72, 0)
		local cfp = top * CFrame.Angles(math.rad(pl.swing + idle * 0.4), math.rad(idle * 0.5), 0) * CFrame.new(0, -0.72, 0)
		pl.part.CFrame = cfp
		for _, x in ipairs(pl.extras) do
			if x.part.Name ~= "Chain" then x.part.CFrame = cfp * x.rel end
		end
		pl.button.TextColor3 = Color3.fromRGB(205, 192, 168):Lerp(Color3.fromRGB(255, 226, 170), pl.glow)
		pl.stroke.Color = Color3.fromRGB(20, 12, 8):Lerp(Color3.fromRGB(150, 70, 30), pl.glow)
	end
	-- tape noise
	for _, l in ipairs(scan) do
		if math.random() < 0.04 then l.Position = UDim2.fromScale(0, math.random()) end
		l.Position += UDim2.fromScale(0, dt * 0.12)
		if l.Position.Y.Scale > 1 then l.Position = UDim2.fromScale(0, 0) end
	end
	recDot.Visible = (t % 1.2) < 0.75
	local secs = t - openedAt
	timecode.Text = string.format("%02d:%02d:%02d:%02d", 0, math.floor(secs / 60) % 60, math.floor(secs) % 60, math.floor(secs * 25) % 25)
end)

--------------------------------------------------
-- OPEN
--------------------------------------------------

tween(curtain, 2.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
task.spawn(function()
	task.wait(1.6)
	for _, v in ipairs({ 0.4, 1, 0.2, 0.8, 0.1, 0.6, 0 }) do
		title.TextTransparency = v
		task.wait(0.05 + math.random() * 0.07)
	end
	tween(subtitle, 1.2, { TextTransparency = 0.1 })
	while open do
		task.wait(4 + math.random() * 6)
		for _ = 1, math.random(1, 3) do
			if not open then break end
			title.TextTransparency = 0.4 + math.random() * 0.5
			task.wait(0.04 + math.random() * 0.05)
			title.TextTransparency = 0
			task.wait(0.03 + math.random() * 0.07)
		end
	end
end)

--------------------------------------------------
-- PLAY: up the stairs, through the doors, into the dark
--------------------------------------------------

local keepHidden = false     -- (while you wake up, the HUD stays away)
local function close()
	open = false
	RunService:UnbindFromRenderStep("MainMenuCamera")
	guiWatch:Disconnect()
	charConn:Disconnect()
	for _, s in ipairs(sounds) do
		if s.Parent then
			local tw = tween(s, 1.5, { Volume = 0 })
			tw.Completed:Once(function() s:Destroy() end)
		end
	end
	for _, pl in pairs(plaques) do pl.gui:Destroy() end
	canvasGui:Destroy()
	propConn:Disconnect()
	for _, L in pairs(letters) do L.gui:Destroy() end
	if strapPart then strapPart:Destroy() end
	for _, e in ipairs(eyes) do e:Destroy() end
	camera.FieldOfView = fovWas
	camera.CameraType = typeWas
	holdBody(false)
	for k, v in pairs(lightWas) do Lighting[k] = v end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	if not keepHidden then
		for g in pairs(hidden) do
			if g.Parent then g.Enabled = true end
		end
	end
end

-- PLAY: you walk to the hole in the floor and look down into it. Something
-- whispers right behind you - you start to turn - and you're shoved in. You
-- fall, turning over, the hole getting smaller above you... and you wake up
-- gasping in the hideout.
local hole = scene:FindFirstChild("FallHole")
local holeC = hole and hole:GetAttribute("Centre") or (O + Vector3.new(-10, 0, -10))
local FALL = {
	whisper = "rbxassetid://133571705093198", wind = "rbxassetid://128828483841636", crack = "rbxassetid://9120805690",
	ring = "rbxassetid://71033223432168", gasp = "rbxassetid://9114555699", gasp2 = "rbxassetid://9114554949",
	breath = "rbxassetid://9113586144", heart = "rbxassetid://3012160995",
}
local function easeIO(a)
	a = math.clamp(a, 0, 1)
	return a < 0.5 and 2 * a * a or 1 - (-2 * a + 2) ^ 2 / 2
end
local function lookAlong(from, dir)
	return CFrame.lookAt(from, from + dir)
end

local function fallShot(c0, startCF)
	local edgeEye = holeC + Vector3.new(0.4, 5.2, -7.4)
	local into = holeC + Vector3.new(0, -3, 0)
	local startPos = startCF.Position
	local mid = startPos:Lerp(edgeEye, 0.55) + Vector3.new(0, -0.8, 0)
	local down = (into - edgeEye).Unit
	return function(t)
		local u = t - c0
		if u < 2.4 then
			-- across the foyer to the edge (footsteps in the sway)
			local a = easeIO(u / 2.4)
			local p = bezier(startPos, startPos + startCF.LookVector * 5, mid, edgeEye, a)
			p += Vector3.new(0, -math.abs(math.sin(u * 5.6)) * 0.12 * (1 - a), 0)
			local d = startCF.LookVector:Lerp((into - p).Unit, easeIO(u / 2.1))
			return lookAlong(p, d) * CFrame.Angles(0, 0, math.rad(1.1 * math.sin(u * 2.8))), 58 + 6 * a
		elseif u < 3.75 then
			-- at the edge, staring down into it
			local k = u - 2.4
			local p = edgeEye + Vector3.new(0.05 * math.sin(k * 0.9), 0.05 * math.sin(k * 1.7), 0)
			return lookAlong(p, down) * CFrame.Angles(math.rad(-2 * math.sin(k * 1.3)), 0, 0), 64 - 6 * easeIO(k / 1.35)
		elseif u < 4.15 then
			-- something right behind you: the head starts to turn...
			local a = easeIO((u - 3.75) / 0.4)
			return lookAlong(edgeEye, down) * CFrame.Angles(math.rad(30 * a), math.rad(-40 * a), math.rad(-4 * a)), 58
		elseif u < 4.55 then
			-- SHOVED, out over the hole
			local a = easeIO((u - 4.15) / 0.4)
			local p = edgeEye:Lerp(holeC + Vector3.new(0, 3.4, -1.2), a)
			local d = down:Lerp(Vector3.new(0, -1, 0.06), a).Unit
			return lookAlong(p, d) * CFrame.Angles(math.rad(30 * (1 - a)), math.rad(-40 * (1 - a)), math.rad(-4 + 20 * a)), 58 + 26 * a
		end
		-- falling: you turn over onto your back and the hole shrinks above you
		local f = u - 4.55
		local y = holeC.Y + 3.4 - 6 * f - 0.5 * 40 * f * f
		local p = Vector3.new(holeC.X + 0.7 * math.sin(f * 2.1), y, holeC.Z - 1.2 + 0.6 * math.cos(f * 1.7))
		local over = easeIO(f / 1.15)
		local cf = CFrame.new(p) * CFrame.Angles(0, math.rad(25 * f), 0) * CFrame.Angles(math.rad(-88 + 168 * over), 0, math.rad(16 + 60 * f))
		return cf, 84 + 10 * math.min(f, 1)
	end
end

-- splinters and grit falling in with you
local function debris()
	for i = 1, 9 do
		local p = new("Part", { Size = Vector3.new(0.15 + math.random() * 0.3, 0.12, 0.4 + math.random() * 1.2), Material = Enum.Material.Wood,
			Color = Color3.fromRGB(70 + math.random(30), 50 + math.random(20), 34), CanCollide = false, CanQuery = false, CanTouch = false,
			CFrame = CFrame.new(holeC + Vector3.new(math.random() * 6 - 3, 1 + math.random() * 2, math.random() * 6 - 3)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) }, workspace)
		p.AssemblyLinearVelocity = Vector3.new(math.random() * 4 - 2, -math.random() * 6, math.random() * 4 - 2)
		p.AssemblyAngularVelocity = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5)
		task.delay(4, function() p:Destroy() end)
	end
end

-- you wake up in the hideout: on a mattress, the sofa, the armchair
local function wakeUp(ring)
	local spots = {}
	local hideout = workspace:FindFirstChild("Hideout")
	local interact = hideout and hideout:FindFirstChild("Interact")
	if interact then
		for _, s in ipairs(interact:GetChildren()) do
			if s.Name:find("^WakeSpot") then table.insert(spots, s) end
		end
	end
	table.sort(spots, function(a, b) return a.Name < b.Name end)
	local idx = table.find(Players:GetPlayers(), player) or 1
	local spot = spots[((idx - 1) % math.max(#spots, 1)) + 1]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local function finish()
		keepHidden = false
		for g in pairs(hidden) do
			if g.Parent then g.Enabled = true end
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		gui:Destroy()
		script:Destroy()
	end
	if not spot or not root then
		tween(curtain, 1.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine).Completed:Wait()
		finish()
		return
	end
	local eye = spot.Position
	local feet = spot:GetAttribute("Feet")
	local stand = spot:GetAttribute("Stand")
	local face = spot:GetAttribute("Face")
	local sitting = spot:GetAttribute("Sitting")
	local up = Vector3.new(0, 1, 0)
	local standRoot = CFrame.lookAt(stand + Vector3.new(0, 3, 0), stand + Vector3.new(0, 3, 0) + face)
	root.Anchored = true
	root.CFrame = standRoot
	-- you don't see your own body standing there while you're lying down
	local function own(mod)
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = mod end
		end
	end
	own(1)
	local blur = new("BlurEffect", { Size = 28 }, camera)
	local lidTop = new("Frame", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 48 }, gui)
	local lidBot = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 48 }, gui)
	local function lids(open, time)
		local h = 0.5 * (1 - open)
		tween(lidTop, time, { Size = UDim2.fromScale(1, h) }, Enum.EasingStyle.Sine)
		tween(lidBot, time, { Size = UDim2.fromScale(1, h) }, Enum.EasingStyle.Sine)
	end
	local sitEye = sitting and eye or (eye + feet * 1.0 + Vector3.new(0, 1.9, 0))
	local standEye = stand + Vector3.new(0, 4.6, 0)
	local lyingDir = sitting and (feet + up * 0.15).Unit or (up * 0.93 + feet * 0.36).Unit
	local right = feet:Cross(up).Unit
	local w0 = os.clock()
	RunService:BindToRenderStep("WakeCamera", Enum.RenderPriority.Camera.Value + 80, function()
		camera.CameraType = Enum.CameraType.Scriptable
		local u = os.clock() - w0
		local pos, dir
		if u < 3.0 then
			-- on your back; the head rolls a little to the side, then back
			local roll = math.sin(math.clamp((u - 1.4) / 1.6, 0, 1) * math.pi) * 0.45
			pos = eye
			dir = (lyingDir + right * roll).Unit
		elseif u < 4.2 then
			-- sit up
			local a = easeIO((u - 3.0) / 1.2)
			pos = eye:Lerp(sitEye, a) + Vector3.new(0, 0.25 * math.sin(a * math.pi), 0)
			dir = lyingDir:Lerp(feet, a).Unit
		elseif u < 5.6 then
			-- where am I: look left... then round
			local k = (u - 4.2) / 1.4
			local yaw = math.sin(k * math.pi) * 0.75 - easeIO(k) * 0.0
			pos = sitEye
			local toFace = feet:Lerp(face, easeIO(k)).Unit
			dir = (CFrame.fromAxisAngle(up, yaw) * toFace)
		elseif u < 6.8 then
			-- up onto your feet
			local a = easeIO((u - 5.6) / 1.2)
			pos = sitEye:Lerp(standEye, a) + Vector3.new(0, 0.2 * math.sin(a * math.pi), 0)
			dir = face
		else
			pos, dir = standEye, face
		end
		local breathe = math.sin(u * 2.2) * math.max(0, 1 - u / 8)
		camera.CFrame = lookAlong(pos + Vector3.new(0, 0.04 * breathe, 0), dir) * CFrame.Angles(math.rad(1.2 * breathe), 0, math.rad(0.8 * math.sin(u * 1.3)))
		camera.FieldOfView = 70
	end)
	-- eyes: a crack of light... shut... open
	curtain.BackgroundTransparency = 1
	sound(FALL.gasp2, 0.9, 1.05)
	sound(FALL.heart, 0.45, 1.4)
	task.wait(0.25)
	lids(0.25, 0.5)
	task.wait(0.7)
	lids(0, 0.25)
	task.wait(0.4)
	lids(0.7, 0.6)
	tween(blur, 2.2, { Size = 10 })
	sound(FALL.breath, 0.5, 0.85)
	task.wait(1.0)
	lids(0.35, 0.15)
	task.wait(0.18)
	lids(1, 0.5)
	tween(blur, 3, { Size = 0 })
	sound(FALL.breath, 0.4, 0.95)
	task.wait(5.0)
	-- yours again
	RunService:UnbindFromRenderStep("WakeCamera")
	blur:Destroy()
	lidTop:Destroy()
	lidBot:Destroy()
	own(0)
	root.CFrame = standRoot
	root.Anchored = false
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = fovWas
	finish()
end

play = function()
	if busy then return end
	busy = true
	hovered = nil
	lightning(true)
	task.wait(0.35)
	tween(title, 0.6, { TextTransparency = 1 })
	tween(subtitle, 0.6, { TextTransparency = 1 })
	cine = fallShot(os.clock(), camera.CFrame)
	-- footsteps on the old boards; the draft coming up out of the hole
	task.spawn(function()
		for _ = 1, 4 do
			sound(SND.creak, 0.1, 1.5 + math.random() * 0.3)
			task.wait(0.55)
		end
	end)
	local wind = sound(FALL.wind, 0.0001, 0.7, true)
	tween(wind, 3.5, { Volume = 0.14 * ambience() })
	task.wait(2.6)
	sound(FALL.breath, 0.3, 0.9)
	task.wait(1.0)
	-- the whisper, right behind your head
	local behind = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = camera.CFrame * CFrame.new(0.5, 0.2, 1.4) }, workspace)
	local w = new("Sound", { SoundId = FALL.whisper, Volume = 1.3 * ambience(), PlaybackSpeed = 0.88, RollOffMinDistance = 2, RollOffMaxDistance = 40 }, behind)
	w:Play()
	task.delay(4, function() behind:Destroy() end)
	task.wait(0.55)
	-- the shove
	shake = 2.8
	sound(SND.thud, 0.9, 0.55)
	sound(FALL.crack, 0.75, 1)
	sound(FALL.gasp, 0.85, 1.15)
	debris()
	task.wait(0.4)
	-- falling
	tween(wind, 0.5, { Volume = 0.9 * ambience(), PlaybackSpeed = 1.15 })
	shake = 1.2
	task.wait(1.75)
	-- the bottom
	curtain.BackgroundTransparency = 0
	hud.Visible = false
	sound(SND.thud, 1, 0.4)
	sound(FALL.crack, 0.45, 0.6)
	wind:Stop()
	local ring = sound(FALL.ring, 0.035, 1, false)
	tween(ring, 3.5, { Volume = 0 })
	cine = nil
	keepHidden = true
	close()
	task.wait(1.1)
	wakeUp(ring)
end

-- test hook (Studio command bar, client): game.Players.LocalPlayer:SetAttribute("MenuTestPlay", true)
player:GetAttributeChangedSignal("MenuTestPlay"):Connect(function()
	if player:GetAttribute("MenuTestPlay") and open and not busy then play() end
end)

-- if the lobby moves on without you (the role screen opens), you go with it
local rs = ReplicatedStorage:FindFirstChild("RoleSelection")
if rs then
	rs:GetAttributeChangedSignal("SelectionOpen"):Connect(function()
		if rs:GetAttribute("SelectionOpen") and open and not busy then play() end
	end)
end
