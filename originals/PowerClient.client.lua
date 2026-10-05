-- PowerClient
-- Place in: StarterPlayer > StarterPlayerScripts
--
-- The first quest, on your screen (server: PowerSystem):
--   * the round starts (the crash cutscene hands over): the last of the light
--     dies, "BASEMENT" fades in, then "The power needs to be turned back on"
--   * the power's out: it's dark down here
--   * TAB: the objective fades in - Turn on the power, Wire panels 0/3,
--     Fuse cabinets 0/1 - things get checked off as they're done (and it
--     shows itself for a moment whenever one is)
--   * all done: the basement's ceiling lights stutter on... and every 10-15
--     seconds they flicker for about a second, with a faint buzz. A few of
--     them ("Faulty" attribute) never quite work right.
--   * down there: fog, dust drifting in the air (you see it in your
--     headlamp, and hanging in the light under the lamps), the hum of the
--     tubes near you, the building's low drone, drips and creaks
--
-- Lights on the power: give a light's part or model a "PowerLight"
-- attribute = true (Workspace.BasementLights are). Their lights and glowing
-- tubes are dead while the power is out and flicker with everything else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local power = ReplicatedStorage:WaitForChild("Power")

local FONT = Enum.Font.SpecialElite
local BONE = Color3.fromRGB(214, 206, 190)
local DIM = Color3.fromRGB(150, 143, 130)
local DARK = Color3.fromRGB(12, 11, 10)

local SOUND = {
	buzz = "rbxassetid://9116272374",      -- electrical buzz
	zap = "rbxassetid://9116279560",       -- small electrical snap
	clunk = "rbxassetid://9116673944",     -- heavy relay / breaker
	hum = "rbxassetid://9116279339",       -- power surging up
	tick = "rbxassetid://9119727134",      -- soft click
}

--------------------------------------------------
-- THE LOOK DOWN HERE
--------------------------------------------------
-- (tune these: "outage" is the power out, "powered" the lights back on)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local LOOK = {
	-- dark and hard: almost nothing bounces about, your lamp and the odd
	-- glow are the light; wet metal still catches a glint
	outage = {
		Ambient = rgb(42, 44, 55), OutdoorAmbient = rgb(38, 40, 50), ExposureCompensation = -0.05,
		EnvironmentDiffuseScale = 0, EnvironmentSpecularScale = 0.3,
		saturation = -0.32, contrast = 0.22, brightness = -0.015, tint = rgb(190, 202, 232),
		fogColor = rgb(12, 12, 16), fogDecay = rgb(6, 6, 9), fogDensity = 0.3,
	},
	-- (the ceiling lights do the real lighting; this is only what bounces about)
	-- between the lamps it stays about as dark as the outage: the light comes
	-- in pools, the gaps between them stay black
	-- high contrast: hard pools of light under the lamps, the gaps between
	-- them stay black, and every wet surface shines
	powered = {
		Ambient = rgb(40, 40, 43), OutdoorAmbient = rgb(34, 34, 37), ExposureCompensation = 0.28,
		EnvironmentDiffuseScale = 0.06, EnvironmentSpecularScale = 0.45,
		saturation = -0.2, contrast = 0.28, brightness = 0, tint = rgb(236, 240, 226),
		fogColor = rgb(40, 41, 38), fogDecay = rgb(18, 19, 18), fogDensity = 0.24,
	},
}

local function clamp01(a)
	return math.clamp(a, 0, 1)
end
local function smooth(a)
	a = clamp01(a)
	return a * a * (3 - 2 * a)
end
local function lerp(a, b, t)
	return a + (b - a) * t
end
local function now()
	return workspace:GetServerTimeNow()
end

local function playSound(id, volume, speed)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	task.delay(8, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	return s
end

-- straight lines between keys (light switching is sharp, not eased)
local function steps(keys, t)
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t < b[1] then
			return lerp(a[2], b[2], (t - a[1]) / (b[1] - a[1]))
		end
	end
	return keys[#keys][2]
end

-- what the place looked like before we touched it (the lobby keeps this)
local original = {
	ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness,
	Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
	ExposureCompensation = Lighting.ExposureCompensation,
	EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
	EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
}
local sky = Lighting:FindFirstChildOfClass("Sky")
local SKY_FACES = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }
local skyWas = sky and { StarCount = sky.StarCount, CelestialBodiesShown = sky.CelestialBodiesShown }
if sky then
	for _, face in ipairs(SKY_FACES) do
		skyWas[face] = sky[face]
	end
end
-- down here the "sky" is a dim basement ceiling with a few lamp glows:
-- it's what wet floors, puddles and metal reflect (Roblox reflects the
-- skybox), so they catch lamp-like glints instead of a blue daytime sky
local BASEMENT_SKY = {
	SkyboxUp = "rbxassetid://100702963518053", SkyboxDn = "rbxassetid://126411236297356",
	SkyboxBk = "rbxassetid://127986033594492", SkyboxFt = "rbxassetid://88462998266067",
	SkyboxLf = "rbxassetid://92552440243185", SkyboxRt = "rbxassetid://79695046953413",
}
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local atmosphereWas = atmosphere and { Color = atmosphere.Color, Decay = atmosphere.Decay, Density = atmosphere.Density,
	Glare = atmosphere.Glare, Haze = atmosphere.Haze }

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "PowerGrade"
grade.Enabled = false
grade.Parent = Lighting

-- the camera effects get a basement setting too: tubes that bloom, no sun
-- rays, a little softness far off
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local bloomWas = bloom and { Intensity = bloom.Intensity, Size = bloom.Size, Threshold = bloom.Threshold }
local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
local sunRaysWas = sunRays and sunRays.Enabled
local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
local dofWas = dof and { Enabled = dof.Enabled, FarIntensity = dof.FarIntensity, FocusDistance = dof.FocusDistance,
	InFocusRadius = dof.InFocusRadius, NearIntensity = dof.NearIntensity }

local looking = false     -- is the basement look on

-- the edges of your sight closing in (soft, always there down here)
local vignetteGui = Instance.new("ScreenGui")
vignetteGui.Name = "BasementVignette"
vignetteGui.ResetOnSpawn = false
vignetteGui.IgnoreGuiInset = true
vignetteGui.DisplayOrder = 2
vignetteGui.Enabled = false
vignetteGui.Parent = player:WaitForChild("PlayerGui")
for _, spec in ipairs({ { 0, 0, 90, false, 0.3 }, { 0, 0.7, -90, false, 0.3 }, { 0, 0, 0, true, 0.22 }, { 0.78, 0, 180, true, 0.22 } }) do
	local f = Instance.new("Frame")
	f.Position = UDim2.fromScale(spec[1], spec[2])
	f.Size = spec[4] and UDim2.fromScale(spec[5], 1) or UDim2.fromScale(1, spec[5])
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 0.35
	f.BorderSizePixel = 0
	f.Parent = vignetteGui
	local g = Instance.new("UIGradient")
	g.Rotation = spec[3]
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
end

local function setBasementLook(on)
	if looking == on then
		return
	end
	looking = on
	if on then
		-- no sun, no moon, no stars down here
		Lighting.ClockTime = 0
		Lighting.Brightness = 0
		if sky then
			sky.StarCount = 0
			sky.CelestialBodiesShown = false
			for _, face in ipairs(SKY_FACES) do
				sky[face] = BASEMENT_SKY[face]
			end
		end
		if atmosphere then
			atmosphere.Density = 0.38
			atmosphere.Glare = 0
			atmosphere.Haze = 2
		end
		if bloom then
			bloom.Intensity, bloom.Size, bloom.Threshold = 0.85, 30, 1.3
		end
		if sunRays then
			sunRays.Enabled = false
		end
		if dof then
			dof.Enabled, dof.FarIntensity, dof.FocusDistance, dof.InFocusRadius, dof.NearIntensity = true, 0.14, 16, 24, 0
		end
		grade.Enabled = true
		vignetteGui.Enabled = true
	else
		vignetteGui.Enabled = false
		if bloom then
			for k, v in pairs(bloomWas) do
				bloom[k] = v
			end
		end
		if sunRays then
			sunRays.Enabled = sunRaysWas
		end
		if dof then
			for k, v in pairs(dofWas) do
				dof[k] = v
			end
		end
		for k, v in pairs(original) do
			Lighting[k] = v
		end
		if sky then
			for k, v in pairs(skyWas) do
				sky[k] = v
			end
		end
		if atmosphere then
			for k, v in pairs(atmosphereWas) do
				atmosphere[k] = v
			end
		end
		grade.Enabled = false
	end
end

-- 0 = power out, 1 = lights on
local function applyLit(lit)
	local a, b = LOOK.outage, LOOK.powered
	Lighting.Ambient = a.Ambient:Lerp(b.Ambient, lit)
	Lighting.OutdoorAmbient = a.OutdoorAmbient:Lerp(b.OutdoorAmbient, lit)
	-- (ExposureBoost on your player: a jumpscare lighting itself up so you see it)
	Lighting.ExposureCompensation = lerp(a.ExposureCompensation, b.ExposureCompensation, lit)
		+ (player:GetAttribute("ExposureBoost") or 0)
	Lighting.EnvironmentDiffuseScale = lerp(a.EnvironmentDiffuseScale, b.EnvironmentDiffuseScale, lit)
	Lighting.EnvironmentSpecularScale = lerp(a.EnvironmentSpecularScale, b.EnvironmentSpecularScale, lit)
	grade.Saturation = lerp(a.saturation, b.saturation, lit)
	grade.Contrast = lerp(a.contrast, b.contrast, lit)
	grade.Brightness = lerp(a.brightness, b.brightness, lit)
	grade.TintColor = a.tint:Lerp(b.tint, lit)
	if atmosphere then
		atmosphere.Color = a.fogColor:Lerp(b.fogColor, lit)
		atmosphere.Decay = a.fogDecay:Lerp(b.fogDecay, lit)
		atmosphere.Density = lerp(a.fogDensity, b.fogDensity, lit)
	end
end

--------------------------------------------------
-- THE LIGHTS COMING BACK, AND FLICKERING
--------------------------------------------------

-- the stutter as they first come on (seconds after RestoredAt, how lit)
local STUTTER = {
	{ 0, 0 }, { 0.04, 0.75 }, { 0.1, 0.04 }, { 0.32, 0.04 }, { 0.35, 0.9 }, { 0.41, 0.25 }, { 0.48, 0.85 },
	{ 0.55, 0.08 }, { 0.95, 0.08 }, { 0.99, 1 }, { 1.07, 0.5 }, { 1.15, 1 }, { 1.3, 0.78 }, { 1.45, 1 },
}
local STUTTER_END = 1.45
local STUTTER_SPARKS = { 0.04, 0.35, 0.48, 0.99 }

-- the flickers after that: the same on every screen (seeded from the
-- moment the power came back)
local flickers = { seed = nil, list = {} }

local function flickerList(restoredAt)
	local seed = math.floor(restoredAt * 10) % 2147483647
	if flickers.seed ~= seed then
		flickers.seed = seed
		flickers.rng = Random.new(seed)
		flickers.list = {}
		flickers.nextAt = restoredAt + STUTTER_END + flickers.rng:NextNumber(10, 15)
	end
	return flickers
end

local function flickerAt(restoredAt, T)
	local f = flickerList(restoredAt)
	-- make sure the schedule reaches past now
	while f.nextAt <= T + 1 do
		local rng = f.rng
		local duration = rng:NextNumber(0.8, 1.2)
		local keys = { { 0, 1 } }
		local t = 0
		while t < duration - 0.15 do
			t += rng:NextNumber(0.05, 0.16)
			table.insert(keys, { t, rng:NextNumber() < 0.6 and rng:NextNumber(0.02, 0.35) or rng:NextNumber(0.55, 0.95) })
		end
		table.insert(keys, { duration, 1 })
		table.insert(f.list, { start = f.nextAt, duration = duration, keys = keys })
		f.nextAt += duration + rng:NextNumber(10, 15)
	end
	for i = #f.list, 1, -1 do
		local fl = f.list[i]
		if T >= fl.start then
			if T < fl.start + fl.duration then
				return steps(fl.keys, T - fl.start), fl
			end
			break
		end
	end
	return 1, nil
end

-- how lit it is right now, and the flicker we're in (if any)
local function litNow(T)
	if power:GetAttribute("On") ~= true then
		return 0
	end
	local at = power:GetAttribute("RestoredAt") or 0
	local t = T - at
	if t < 0 then
		return 0
	end
	if t < STUTTER_END then
		return steps(STUTTER, t)
	end
	return flickerAt(at, T)
end

--------------------------------------------------
-- THE LAMPS ON THE POWER
--------------------------------------------------

local DEAD_TUBE = rgb(64, 67, 70)
local fixtures = {}          -- the PowerLight model/part -> what we switch

local function scanFixtures()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:GetAttribute("PowerLight") == true and not fixtures[d] then
			local fx = { lights = {}, tubes = {}, dust = {}, shown = -1, faulty = d:GetAttribute("Faulty") == true,
				dead = d:GetAttribute("Dead") == true }
			local pos = d:IsA("Model") and d:GetPivot().Position or d.Position
			fx.pos = pos
			fx.seed = (pos.X * 0.731 + pos.Z * 1.379) % 97
			for _, x in ipairs(d:GetDescendants()) do
				if x:IsA("Light") then
					fx.lights[x] = x.Brightness
				elseif x:IsA("BasePart") and x.Material == Enum.Material.Neon then
					fx.tubes[x] = x.Color
				elseif x:IsA("ParticleEmitter") then
					table.insert(fx.dust, x)
				end
			end
			fx.emitter = d:FindFirstChild("LightEmitter", true) or (d:IsA("BasePart") and d) or d:FindFirstChildWhichIsA("BasePart", true)
			fixtures[d] = fx
		end
	end
end

-- a faulty lamp: now and then it sputters, sometimes it gives up for a bit
-- (math.noise on the server's clock: the same on every screen)
local function faultAt(fx, T)
	if fx.dead then
		-- a dead one: once in a long while it tries, and fails
		local try = math.noise(T * 0.21, fx.seed, 5.3)
		if try > 0.55 and math.noise(T * 11, fx.seed, 7.9) > 0.2 then
			return 0.35
		end
		return 0
	end
	if not fx.faulty then
		return 1
	end
	local burst = math.noise(T * 0.32, fx.seed, 1.7)
	if burst < 0.05 then
		return 1
	end
	if burst > 0.42 then
		return 0          -- given up for now
	end
	local v = math.noise(T * 9, fx.seed, 3.1)
	if v > 0.12 then
		return 0.04
	elseif v < -0.32 then
		return 0.5
	end
	return 1
end

local function setFixture(fx, f)
	if math.abs(f - fx.shown) < 0.01 then
		return
	end
	fx.shown = f
	for light, base in pairs(fx.lights) do
		if light.Parent then
			light.Enabled = f > 0.03
			light.Brightness = base * f
		end
	end
	for tube, color in pairs(fx.tubes) do
		if tube.Parent then
			if f > 0.05 then
				tube.Material = Enum.Material.Neon
				tube.Color = DEAD_TUBE:Lerp(color, math.clamp(f, 0, 1))
			else
				tube.Material = Enum.Material.Glass
				tube.Color = DEAD_TUBE
			end
		end
	end
	for _, pe in ipairs(fx.dust) do
		pe.Enabled = f > 0.05
	end
end

local function resetFixtures()
	for _, fx in pairs(fixtures) do
		setFixture(fx, 1)
	end
end

--------------------------------------------------
-- THE AIR DOWN THERE: dust, hum, drone, drips, creaks
--------------------------------------------------

local AMBIENT = {
	hum = "rbxassetid://4227579935",          -- fluorescent tube hum (loop)
	drone = "rbxassetid://9119643885",        -- a storm drain's low rush, slowed: the building breathing
	drips = { "rbxassetid://9126181980", "rbxassetid://9126179016" },
	creaks = { "rbxassetid://9126147889", "rbxassetid://9126148128" },
}

-- dust hanging in the air around you: barely there in the dark, bright in
-- a beam of light
local air = Instance.new("Part")
air.Name = "AirDust"
air.Size = Vector3.new(30, 12, 30)
air.Transparency = 1
air.Anchored = true
air.CanCollide, air.CanQuery, air.CanTouch = false, false, false
air.CastShadow = false
local airDust = Instance.new("ParticleEmitter")
airDust.Name = "Motes"
airDust.Shape = Enum.ParticleEmitterShape.Box
airDust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
airDust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
airDust.Rate = 26
airDust.Lifetime = NumberRange.new(7, 12)
airDust.Speed = NumberRange.new(0.02, 0.12)
airDust.SpreadAngle = Vector2.new(180, 180)
airDust.Acceleration = Vector3.new(0, -0.01, 0)
airDust.Drag = 0.5
airDust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.045), NumberSequenceKeypoint.new(1, 0.03) })
airDust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.5),
	NumberSequenceKeypoint.new(0.85, 0.6), NumberSequenceKeypoint.new(1, 1) })
airDust.Color = ColorSequence.new(rgb(210, 206, 196))
airDust.LightInfluence = 0.88
airDust.LightEmission = 0
airDust.Rotation = NumberRange.new(0, 360)
airDust.RotSpeed = NumberRange.new(-25, 25)
airDust.Enabled = false
airDust.Parent = air

-- the menu's low-graphics setting (phones): no motes, and the lamps stop
-- casting shadows (the expensive part of all those lights)
local function applyLowGraphics()
	local low = game:GetService("Players").LocalPlayer:GetAttribute("LowGraphics") == true
	airDust.Rate = low and 0 or 26
	local lights = workspace:FindFirstChild("Basement") and workspace.Basement:FindFirstChild("Lights")
	if lights then
		for _, l in ipairs(lights:GetDescendants()) do
			if l:IsA("Light") then
				if l:GetAttribute("ShadowsWas") == nil then l:SetAttribute("ShadowsWas", l.Shadows) end
				l.Shadows = (not low) and l:GetAttribute("ShadowsWas") or false
			end
		end
	end
end
game:GetService("Players").LocalPlayer:GetAttributeChangedSignal("LowGraphics"):Connect(applyLowGraphics)
task.defer(applyLowGraphics)

local drone = Instance.new("Sound")
drone.Name = "BasementDrone"
drone.SoundId = AMBIENT.drone
drone.Looped = true
drone.Volume = 0
drone.PlaybackSpeed = 0.62
drone.Parent = SoundService

local hums = {}
for i = 1, 2 do
	local s = Instance.new("Sound")
	s.Name = "TubeHum"
	s.SoundId = AMBIENT.hum
	s.Looped = true
	s.Volume = 0
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 3
	s.RollOffMaxDistance = 20
	hums[i] = { sound = s, fx = nil }
end

local function spot(at)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = workspace.Terrain
	task.delay(8, function()
		holder:Destroy()
	end)
	return holder
end

local function playAt(id, volume, speed, at, minD, maxD)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = minD or 6
	s.RollOffMaxDistance = maxD or 60
	s.Parent = spot(at)
	s:Play()
end

local nextNoise = os.clock() + 6

--------------------------------------------------
-- THE OBJECTIVE (TAB)
--------------------------------------------------

-- (the name has "Objective" in it: HudRules only lets it show in a match)
local objectiveGui = Instance.new("ScreenGui")
objectiveGui.Name = "PowerObjectiveGui"
objectiveGui.ResetOnSpawn = false
objectiveGui.IgnoreGuiInset = true
objectiveGui.DisplayOrder = 45       -- above the camcorder's viewfinder (40)
objectiveGui.Parent = playerGui

local panel = Instance.new("CanvasGroup")
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 26, 0.38, 0)
panel.Size = UDim2.fromOffset(380, 150)
panel.BackgroundTransparency = 1
panel.GroupTransparency = 1
panel.Parent = objectiveGui

local function text(parent, str, size, color, x, y, w, h)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextStrokeTransparency = 0.55
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = str
	l.Parent = parent
	return l
end

local header = text(panel, "Turn on the power", 23, BONE, 0, 0, 380, 28)
local underline = Instance.new("Frame")
underline.Position = UDim2.fromOffset(0, 32)
underline.Size = UDim2.fromOffset(0, 1)
underline.BorderSizePixel = 0
underline.BackgroundColor3 = BONE
underline.BackgroundTransparency = 0.55
underline.Parent = panel
local headerStrike = Instance.new("Frame")
headerStrike.AnchorPoint = Vector2.new(0, 0.5)
headerStrike.Position = UDim2.fromOffset(0, 15)
headerStrike.Size = UDim2.fromOffset(0, 2)
headerStrike.BorderSizePixel = 0
headerStrike.BackgroundColor3 = BONE
headerStrike.Parent = panel

local items = {}
local function item(key, name, y)
	local box = Instance.new("Frame")
	box.Position = UDim2.fromOffset(2, y + 5)
	box.Size = UDim2.fromOffset(15, 15)
	box.BackgroundTransparency = 1
	box.Parent = panel
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
	local rim = Instance.new("UIStroke")
	rim.Color = BONE
	rim.Thickness = 1.3
	rim.Transparency = 0.2
	rim.Parent = box
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(0, 0)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = BONE
	fill.Parent = box
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 2)
	local label = text(panel, name, 20, BONE, 28, y, 220, 25)
	local count = text(panel, "0/0", 20, BONE, 250, y, 80, 25)
	local strike = Instance.new("Frame")
	strike.AnchorPoint = Vector2.new(0, 0.5)
	strike.Position = UDim2.fromOffset(26, y + 13)
	strike.Size = UDim2.fromOffset(0, 1.5)
	strike.BorderSizePixel = 0
	strike.BackgroundColor3 = BONE
	strike.Parent = panel
	items[key] = { box = box, fill = fill, label = label, count = count, strike = strike, done = false, shown = nil }
end
item("Wires", "Wire panels", 44)
item("Fuses", "Fuse cabinets", 74)

local footer = text(panel, "The lights are back on.", 18, DIM, 0, 110, 380, 24)
footer.TextTransparency = 1
footer.TextStrokeTransparency = 1

local function textWidth(label)
	return math.max(label.TextBounds.X, 40)
end

local function checkOff(it, instant)
	it.done = true
	local info = instant and TweenInfo.new(0) or TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(it.fill, info, { Size = UDim2.fromScale(0.62, 0.62) }):Play()
	local width = 230 + 30
	TweenService:Create(it.strike, instant and TweenInfo.new(0) or TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(width, 1.5) }):Play()
	local dim = instant and TweenInfo.new(0) or TweenInfo.new(0.6)
	TweenService:Create(it.label, dim, { TextColor3 = DIM, TextTransparency = 0.3 }):Play()
	TweenService:Create(it.count, dim, { TextColor3 = DIM, TextTransparency = 0.3 }):Play()
	if not instant then
		playSound(SOUND.tick, 0.25, 1.7)
	end
end

local function uncheck(it)
	it.done = false
	it.fill.Size = UDim2.fromScale(0, 0)
	it.strike.Size = UDim2.fromOffset(0, 1.5)
	it.label.TextColor3, it.label.TextTransparency = BONE, 0
	it.count.TextColor3, it.count.TextTransparency = BONE, 0
end

local panelShown = false
local hideAt = 0
local tabHeld = false

local function showPanel(on)
	if panelShown == on then
		return
	end
	panelShown = on
	if on then
		panel.Position = UDim2.new(0, 16, 0.38, 0)
		TweenService:Create(panel, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ GroupTransparency = 0, Position = UDim2.new(0, 26, 0.38, 0) }):Play()
		underline.Size = UDim2.fromOffset(0, 1)
		TweenService:Create(underline, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(250, 1) }):Play()
	else
		TweenService:Create(panel, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { GroupTransparency = 1, Position = UDim2.new(0, 20, 0.38, 0) }):Play()
	end
end

-- show it for a while on its own (round start, something checked off)
local function peekPanel(seconds)
	showPanel(true)
	hideAt = math.max(hideAt, os.clock() + seconds)
end

local lastCounts = {}
local allDoneShown = false
local function updateItems(first)
	local changed = false
	for key, it in pairs(items) do
		local done = power:GetAttribute(key .. "Done") or 0
		local total = power:GetAttribute(key .. "Total") or 0
		local str = done .. "/" .. total
		if it.count.Text ~= str then
			if not first and lastCounts[key] and done > lastCounts[key] then
				changed = true
				-- the number ticks over
				it.count.TextColor3 = Color3.fromRGB(240, 232, 214)
				it.count.Position = UDim2.fromOffset(250, 41 + (key == "Wires" and 0 or 30))
				TweenService:Create(it.count, TweenInfo.new(0.35, Enum.EasingStyle.Back),
					{ Position = UDim2.fromOffset(250, key == "Wires" and 44 or 74) }):Play()
			end
			it.count.Text = str
		end
		lastCounts[key] = done
		local complete = total > 0 and done >= total
		if complete and not it.done then
			if first then
				checkOff(it, true)
			else
				task.delay(0.35, checkOff, it, false)
			end
		elseif not complete and it.done then
			uncheck(it)
		end
	end
	local on = power:GetAttribute("On") == true
	if on and not allDoneShown then
		allDoneShown = true
		local d = first and 0 or 0.9
		task.delay(d, function()
			TweenService:Create(headerStrike, TweenInfo.new(first and 0 or 0.55, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(header.TextBounds.X + 6, 2) }):Play()
			TweenService:Create(header, TweenInfo.new(first and 0 or 0.7), { TextColor3 = DIM, TextTransparency = 0.25 }):Play()
			TweenService:Create(footer, TweenInfo.new(first and 0 or 1.2), { TextTransparency = 0.1, TextStrokeTransparency = 0.6 }):Play()
		end)
	elseif not on and allDoneShown then
		allDoneShown = false
		headerStrike.Size = UDim2.fromOffset(0, 2)
		header.TextColor3, header.TextTransparency = BONE, 0
		footer.TextTransparency, footer.TextStrokeTransparency = 1, 1
	end
	if changed then
		peekPanel(on and 6 or 4)
	end
end

for _, name in ipairs({ "WiresDone", "WiresTotal", "FusesDone", "FusesTotal", "On" }) do
	power:GetAttributeChangedSignal(name):Connect(function()
		updateItems(false)
	end)
end

--------------------------------------------------
-- THE ROUND STARTING: the light dying, "BASEMENT"
--------------------------------------------------

local titleGui = Instance.new("ScreenGui")
titleGui.Name = "RoundTitle"
titleGui.ResetOnSpawn = false
titleGui.IgnoreGuiInset = true
titleGui.DisplayOrder = 30
titleGui.Parent = playerGui

local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 1
black.BorderSizePixel = 0
black.Parent = titleGui

local function centered(str, size, y, color)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.new(0.5, 0, y, 0)
	l.Size = UDim2.fromOffset(700, size + 12)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextStrokeTransparency = 1
	l.TextTransparency = 1
	l.Text = str
	l.Parent = titleGui
	return l
end

local title = centered("B  A  S  E  M  E  N  T", 30, 0.33, BONE)
local titleLine = Instance.new("Frame")
titleLine.AnchorPoint = Vector2.new(0.5, 0.5)
titleLine.Position = UDim2.new(0.5, 0, 0.33, 26)
titleLine.Size = UDim2.fromOffset(0, 1)
titleLine.BorderSizePixel = 0
titleLine.BackgroundColor3 = BONE
titleLine.BackgroundTransparency = 0.5
titleLine.Parent = titleGui
local subtitle = centered("The power needs to be turned back on.", 20, 0.33, DIM)
subtitle.Position = UDim2.new(0.5, 0, 0.33, 50)
local tabHint = centered("[ Tab ]   backpack  -  objectives & photos", 15, 0.33, DIM)
tabHint.Position = UDim2.new(0.5, 0, 0.33, 80)

local titleShowing = 0     -- os.clock() the titles started (0 = not)
local function fadeText(l, to, seconds, strokeTo)
	TweenService:Create(l, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ TextTransparency = to, TextStrokeTransparency = strokeTo or (to < 1 and 0.6 or 1) }):Play()
end

local function roundStart(fromCutscene)
	local started = os.clock()
	titleShowing = started
	task.spawn(function()
		-- the last of the light dies
		if fromCutscene then
			TweenService:Create(black, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 0 }):Play()
			playSound(SOUND.zap, 0.18, 0.7)
			task.wait(0.45)
		end
		setBasementLook(true)
		applyLit(0)
		TweenService:Create(black, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 }):Play()
		playSound(SOUND.buzz, 0.07, 0.45)       -- a low dying hum
		task.wait(1.1)
		if titleShowing ~= started then
			return
		end
		-- BASEMENT
		title.Position = UDim2.new(0.5, 0, 0.33, 8)
		TweenService:Create(title, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0.33, 0) }):Play()
		fadeText(title, 0, 1.8)
		titleLine.Size = UDim2.fromOffset(0, 1)
		TweenService:Create(titleLine, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(300, 1) }):Play()
		task.wait(1.5)
		subtitle.Position = UDim2.new(0.5, 0, 0.33, 56)
		TweenService:Create(subtitle, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0.33, 50) }):Play()
		fadeText(subtitle, 0.05, 1.6)
		task.wait(3.6)
		if titleShowing ~= started then
			return
		end
		-- away again, slowly
		fadeText(title, 1, 1.8)
		fadeText(subtitle, 1, 1.8)
		TweenService:Create(titleLine, TweenInfo.new(1.8, Enum.EasingStyle.Sine), { Size = UDim2.fromOffset(0, 1) }):Play()
		TweenService:Create(title, TweenInfo.new(1.8, Enum.EasingStyle.Sine), { Position = UDim2.new(0.5, 0, 0.33, -6) }):Play()
		task.wait(2.1)
		-- the objective comes up on its own once, with the TAB hint
		peekPanel(4.5)
		fadeText(tabHint, 0.2, 0.8)
		task.wait(4.5)
		fadeText(tabHint, 1, 1.2)
		titleShowing = 0
	end)
end

local function clearTitles()
	titleShowing = 0
	for _, l in ipairs({ title, subtitle, tabHint }) do
		l.TextTransparency, l.TextStrokeTransparency = 1, 1
	end
	titleLine.Size = UDim2.fromOffset(0, 1)
	black.BackgroundTransparency = 1
end

--------------------------------------------------
-- IN A MATCH OR NOT
--------------------------------------------------

local lobby = ReplicatedStorage:FindFirstChild("Lobby")
task.spawn(function()
	lobby = lobby or ReplicatedStorage:WaitForChild("Lobby", 30)
end)

local function inMatch()
	return not lobby or lobby:GetAttribute("InMatch") == true
end

-- the round has started for you: the crash cutscene handed over (it sets
-- RoundTitleAt on your player), and you're still in that match
local roundSeen = nil
local function roundActive()
	return inMatch() and player:GetAttribute("RoundTitleAt") ~= nil
end

player:GetAttributeChangedSignal("RoundTitleAt"):Connect(function()
	local at = player:GetAttribute("RoundTitleAt")
	if at and at ~= roundSeen and inMatch() then
		roundSeen = at
		roundStart(true)
	end
end)

local function setPlayerList(on)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, on)
	end)
end

--------------------------------------------------
-- TAB
--------------------------------------------------

-- (TAB opens the backpack now - BackpackClient - and the objectives are in
-- its notebook. The panel here still peeks out on its own when they change.)
local TAB_SHOWS_PANEL = false
local tabDownAt = 0
UserInputService.InputBegan:Connect(function(input)
	if TAB_SHOWS_PANEL and input.KeyCode == Enum.KeyCode.Tab and roundActive()
		and not (UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)) then
		tabHeld = true
		tabDownAt = os.clock()
		showPanel(true)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Tab and tabHeld then
		tabHeld = false
		-- a tap leaves it up a moment; a hold puts it away when you let go
		hideAt = math.max(hideAt, os.clock() + math.max(0, 2.6 - (os.clock() - tabDownAt)))
	end
end)

--------------------------------------------------
-- EVERY FRAME
--------------------------------------------------

-- the crash cutscene: when the cage hits the bottom (the player's
-- "IntroBlackout" attribute = that moment) every lamp down here surges, pops
-- and dies, and stays dead while you come round in the wreck
local blackoutHeard = nil
local function introBlackout(blackoutAt)
	if next(fixtures) == nil then
		scanFixtures()
	end
	local since = workspace:GetServerTimeNow() - blackoutAt
	for _, fx in pairs(fixtures) do
		local s = since - (fx.seed % 1) * 0.3          -- (not all at once)
		local f
		if s < 0 then
			f = 1
		elseif s < 0.07 then
			f = 1.8                                     -- the surge
		elseif s < 0.14 then
			f = 0.05
		elseif s < 0.2 then
			f = 0.5
		else
			f = 0
		end
		setFixture(fx, f)
	end
	if blackoutHeard ~= blackoutAt and since >= 0 then
		blackoutHeard = blackoutAt
		-- the nearest ones pop audibly
		local camPos = workspace.CurrentCamera.CFrame.Position
		for _, fx in pairs(fixtures) do
			if (fx.pos - camPos).Magnitude < 45 then
				local delay = 0.07 + (fx.seed % 1) * 0.3
				task.delay(delay, function()
					playAt(SOUND.zap, 0.16, math.random(110, 160) / 100, fx.emitter and fx.emitter.Position or fx.pos, 3, 40)
				end)
			end
		end
	end
end

local wasActive = false
local lastFlicker = nil
local stutterSparks = {}
local scanClock = 0
updateItems(true)

RunService.RenderStepped:Connect(function(dt)
	local active = roundActive()
	if active ~= wasActive then
		wasActive = active
		setPlayerList(not active)
		if active then
			-- (joined mid-round, or the titles are already running)
			if titleShowing == 0 then
				setBasementLook(true)
			end
		else
			setBasementLook(false)
			clearTitles()
			showPanel(false)
			roundSeen = nil
			resetFixtures()
			airDust.Enabled = false
			air.Parent = nil
			drone:Stop()
			for _, h in ipairs(hums) do
				h.sound:Stop()
				h.sound.Parent = nil
				h.fx = nil
			end
		end
	end
	if not active then
		local blackout = player:GetAttribute("IntroBlackout")
		if blackout then
			introBlackout(blackout)
		end
		return
	end

	local T = now()
	local lit, flicker = litNow(T)
	if looking then
		applyLit(lit)
	end

	-- the lights: snaps and buzzes
	local at = power:GetAttribute("RestoredAt") or 0
	if power:GetAttribute("On") == true then
		local t = T - at
		if t >= 0 and t < STUTTER_END + 0.5 then
			if not stutterSparks.at or stutterSparks.at ~= at then
				stutterSparks = { at = at }
			end
			if t < 0.3 and not stutterSparks.clunk then
				stutterSparks.clunk = true
				playSound(SOUND.clunk, 0.45, 0.8)
				playSound(SOUND.hum, 0.22, 0.75)
			end
			for i, s in ipairs(STUTTER_SPARKS) do
				if t >= s and not stutterSparks[i] then
					stutterSparks[i] = true
					playSound(SOUND.zap, 0.08, math.random(110, 150) / 100)
				end
			end
		end
		if flicker and flicker ~= lastFlicker then
			lastFlicker = flicker
			playSound(SOUND.buzz, 0.11, math.random(105, 125) / 100)
			task.delay(flicker.duration * 0.4, function()
				playSound(SOUND.zap, 0.04, math.random(130, 170) / 100)
			end)
		end
	end

	-- the lamps
	scanClock -= dt
	if scanClock <= 0 then
		scanClock = 8        -- (lamps streaming in / added later)
		scanFixtures()
	end
	local camPos = workspace.CurrentCamera.CFrame.Position
	for d, fx in pairs(fixtures) do
		if not d.Parent then
			fixtures[d] = nil
			continue
		end
		local f = lit * faultAt(fx, T)
		-- a faulty one snapping off near you: you hear it
		if (fx.faulty or fx.dead) and fx.shown > 0.5 and f < 0.2 and power:GetAttribute("On") == true
			and (fx.pos - camPos).Magnitude < 35 and os.clock() - (fx.lastSnap or 0) > 0.12 then
			fx.lastSnap = os.clock()
			playAt(SOUND.zap, 0.12, math.random(120, 170) / 100, fx.emitter and fx.emitter.Position or fx.pos, 3, 30)
		end
		setFixture(fx, f)
	end

	-- the hum of the nearest lit tubes
	local near = {}
	for _, fx in pairs(fixtures) do
		if fx.shown > 0.05 and fx.emitter then
			local dist = (fx.pos - camPos).Magnitude
			if dist < 22 then
				table.insert(near, { fx = fx, d = dist })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.d < b.d
	end)
	for i, h in ipairs(hums) do
		local pick = near[i]
		if pick then
			if h.fx ~= pick.fx then
				h.fx = pick.fx
				h.sound.Parent = pick.fx.emitter
				if not h.sound.IsPlaying then
					h.sound.TimePosition = math.random() * 3
					h.sound:Play()
				end
			end
			h.sound.Volume = 0.14 * pick.fx.shown
		elseif h.fx then
			h.fx = nil
			h.sound.Volume = 0
		end
	end

	-- the air: dust round you, the building's drone, drips and creaks
	air.Parent = workspace.CurrentCamera
	air.CFrame = CFrame.new(camPos)
	airDust.Enabled = true
	if not drone.IsPlaying then
		drone:Play()
	end
	drone.Volume += ((lit > 0.5 and 0.16 or 0.26) - drone.Volume) * math.min(dt * 0.8, 1)
	if os.clock() > nextNoise then
		nextNoise = os.clock() + math.random(55, 140) / 10
		local angle = math.random() * math.pi * 2
		local at = camPos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random(10, 26) + Vector3.new(0, math.random(1, 6), 0)
		if math.random() < 0.6 then
			playAt(AMBIENT.drips[math.random(#AMBIENT.drips)], math.random(12, 22) / 100, math.random(85, 110) / 100, at, 8, 70)
		else
			playAt(AMBIENT.creaks[math.random(#AMBIENT.creaks)], math.random(5, 9) / 100, math.random(38, 55) / 100, at, 10, 80)
		end
	end

	-- the objective panel putting itself away
	if panelShown and not tabHeld and os.clock() > hideAt then
		showPanel(false)
	end
end)
