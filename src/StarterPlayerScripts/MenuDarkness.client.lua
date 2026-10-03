-- MenuDarkness
-- Place in: StarterPlayer > StarterPlayerScripts (a LocalScript, next to MainMenu)
--
-- Makes the main menu foyer properly dark. MainMenu lights the room with a
-- warm, even glow; this takes most of it away, so the room is lit by the
-- swinging bulb, the red neon sign, the fire and the lightning, with deep
-- shadow everywhere else:
--   * every lamp in the scene is turned right down (not the bulb's swing,
--     the sign or the lightning, which become the light you see by)
--   * the night air thickens, colours drain and go cold
--   * the neon sign blooms red into the dark
--   * now and then the tape tracks badly: a band of noise rolls up the screen
-- The menu's buttons and the canvas stay readable in the dark.
-- When you press PLAY and the menu closes, everything goes back exactly as it was.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local LAMP_DIM = 0.3              -- every scene lamp keeps this much of its brightness
local BULB_DIM = 0.65             -- the swinging bulb keeps a bit more: it's what you see by
local FIRE_DIM = 0.55
local AMBIENT = Color3.fromRGB(10, 9, 12)
local OUTDOOR = Color3.fromRGB(8, 9, 14)
local EXPOSURE = -0.35

--------------------------------------------------
-- WAIT FOR THE MENU
--------------------------------------------------

local menuGui = playerGui:WaitForChild("MainMenuGui", 20)
local scene = workspace:FindFirstChild("MainMenuScene")
if not menuGui or not scene then
	return    -- no menu this time (back from a match)
end
task.wait()   -- let MainMenu finish setting the room up

-- names of lights we leave alone: the lightning, the neon sign's glow
local function keepAsIs(light)
	return light.Name == "Lightning" or light.Name == "Glow"
end

--------------------------------------------------
-- DARKEN
--------------------------------------------------

local restore = {}

-- the room's lamps
for _, light in ipairs(scene:GetDescendants()) do
	if light:IsA("Light") and not keepAsIs(light) then
		local factor = light.Name == "BulbLight" and BULB_DIM or LAMP_DIM
		table.insert(restore, { light, "Brightness", light.Brightness })
		light.Brightness *= factor
	end
end

-- the sky outside and the air in the room (MainMenu puts these back itself)
Lighting.Ambient = AMBIENT
Lighting.OutdoorAmbient = OUTDOOR
Lighting.ExposureCompensation = EXPOSURE

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "MenuDarkGrade"
grade.Saturation = -0.38
grade.Contrast = 0.24
grade.Brightness = -0.03
grade.TintColor = Color3.fromRGB(214, 212, 232)
grade.Parent = Lighting

local bloom = Instance.new("BloomEffect")
bloom.Name = "MenuDarkBloom"
bloom.Intensity = 0.8
bloom.Size = 36
bloom.Threshold = 1.1
bloom.Parent = Lighting

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local madeAtmosphere = false
if atmosphere then
	for _, prop in ipairs({ "Density", "Offset", "Color", "Decay", "Glare", "Haze" }) do
		table.insert(restore, { atmosphere, prop, atmosphere[prop] })
	end
else
	atmosphere = Instance.new("Atmosphere")
	madeAtmosphere = true
	atmosphere.Parent = Lighting
end
atmosphere.Density = 0.42
atmosphere.Offset = 0.1
atmosphere.Color = Color3.fromRGB(26, 24, 30)
atmosphere.Decay = Color3.fromRGB(14, 12, 18)
atmosphere.Glare = 0
atmosphere.Haze = 1.8

-- the plaques and the canvas glow a little on their own, so you can still read them
for _, name in ipairs({ "Plaque_Play", "Plaque_HowTo", "Plaque_Settings", "Plaque_Credits", "MenuCanvas" }) do
	local sg = playerGui:WaitForChild(name, 5)
	if sg and sg:IsA("SurfaceGui") then
		table.insert(restore, { sg, "LightInfluence", sg.LightInfluence })
		sg.LightInfluence = name == "MenuCanvas" and 0.3 or 0.45
	end
end

--------------------------------------------------
-- THE TAPE TRACKS BADLY
--------------------------------------------------

local overlay = Instance.new("ScreenGui")
overlay.Name = "MenuDarknessOverlay"
overlay.IgnoreGuiInset = true
overlay.ResetOnSpawn = false
overlay.DisplayOrder = 61
overlay.Parent = playerGui

-- heavier dark corners
for _, side in ipairs({ { 0, 0, 0 }, { 1, 0, 180 }, { 0, 0, 90 }, { 0, 1, -90 } }) do
	local vertical = side[3] == 90 or side[3] == -90
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(side[1], side[2])
	f.Position = UDim2.fromScale(side[1], side[2])
	f.Size = vertical and UDim2.fromScale(1, 0.34) or UDim2.fromScale(0.3, 1)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Parent = overlay
	local g = Instance.new("UIGradient")
	g.Rotation = side[3]
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
end

-- the rolling band of tape noise
local band = Instance.new("Frame")
band.Size = UDim2.new(1, 0, 0.06, 0)
band.BackgroundTransparency = 1
band.BorderSizePixel = 0
band.Visible = false
band.Parent = overlay
local streaks = {}
for i = 1, 14 do
	local s = Instance.new("Frame")
	s.BorderSizePixel = 0
	s.BackgroundColor3 = Color3.fromRGB(225, 225, 232)
	s.Parent = band
	streaks[i] = s
end

-- film grain
local grain = {}
for i = 1, 70 do
	local g = Instance.new("Frame")
	g.Size = UDim2.fromOffset(2, 2)
	g.BorderSizePixel = 0
	g.BackgroundColor3 = Color3.fromRGB(220, 218, 226)
	g.BackgroundTransparency = 1
	g.Parent = overlay
	grain[i] = g
end

local tracking = nil       -- { start, speed } while a band is rolling
local nextTracking = os.clock() + 4 + math.random() * 6
local fireGlow = nil
local extra = scene:FindFirstChild("Extra")
local embers = extra and extra:FindFirstChild("Embers")
fireGlow = embers and embers:FindFirstChild("FireGlow")

local conn = RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	-- MainMenu sets the fire's brightness every frame; turn it down after it
	if fireGlow and fireGlow.Brightness > 0.8 then
		fireGlow.Brightness *= FIRE_DIM
	end
	-- grain
	for _, g in ipairs(grain) do
		if math.random() < 0.2 then
			g.Position = UDim2.fromScale(math.random(), math.random())
			g.BackgroundTransparency = 0.5 + math.random() * 0.4
		else
			g.BackgroundTransparency = math.min(1, g.BackgroundTransparency + dt * 5)
		end
	end
	-- a band of bad tracking rolls up the screen every so often
	if not tracking and t >= nextTracking then
		tracking = { start = t, speed = 0.5 + math.random() * 0.6 }
		band.Visible = true
	end
	if tracking then
		local y = 1.05 - (t - tracking.start) * tracking.speed
		band.Position = UDim2.fromScale(0, y)
		for _, s in ipairs(streaks) do
			if math.random() < 0.5 then
				s.Position = UDim2.fromScale(math.random() * 0.9, math.random())
				s.Size = UDim2.new(0.05 + math.random() * 0.4, 0, 0, math.random(1, 4))
				s.BackgroundTransparency = 0.35 + math.random() * 0.55
			end
		end
		if y < -0.1 then
			tracking = nil
			band.Visible = false
			nextTracking = t + 5 + math.random() * 9
		end
	end
end)

--------------------------------------------------
-- PUT IT BACK WHEN THE MENU CLOSES
--------------------------------------------------
-- MainMenu removes the canvas the moment you've fallen through the floor.

local function undo()
	conn:Disconnect()
	for _, r in ipairs(restore) do
		local object, prop, value = r[1], r[2], r[3]
		if object.Parent then
			object[prop] = value
		end
	end
	if madeAtmosphere then
		atmosphere:Destroy()
	end
	local fade = TweenInfo.new(1.2)
	TweenService:Create(grade, fade, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	TweenService:Create(bloom, fade, { Intensity = 0 }):Play()
	task.delay(1.3, function()
		grade:Destroy()
		bloom:Destroy()
	end)
	overlay:Destroy()
	script:Destroy()
end

local canvas = playerGui:FindFirstChild("MenuCanvas")
if canvas then
	canvas.AncestryChanged:Connect(function(_, parent)
		if not parent then
			undo()
		end
	end)
else
	menuGui.AncestryChanged:Connect(function(_, parent)
		if not parent then
			undo()
		end
	end)
end
