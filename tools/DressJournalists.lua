-- DressJournalists
-- Run ONCE in Studio: View > Command Bar, paste all of this, press Enter, then save.
-- (Run it again any time: it replaces the kit it added before. Ctrl+Z undoes it.)
--
-- Gives the five crew members the gear of their job, built from parts:
--   Ines (Photographer)  a camera with a flash on a strap round her neck
--   Danny (Cameraman)    a shoulder camcorder with a red tally light
--   Claire (Reporter)    a Channel 8 microphone in her hand
--   Marcus (Sound)       headphones and a tape recorder on his hip
--   Tommy (Intern)       a big gear backpack and a flashlight
-- and everyone gets a PRESS badge clipped to their chest.
--
-- It dresses both the characters you play as (ServerStorage > RoleCharacters)
-- and the figures standing in the lobby lockers (Workspace > RoleDisplays),
-- using the new names or the old ones (Acrobat, Mechanic, Medic, Scout, Brute).

local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local OLD_NAMES = { Photographer = "Acrobat", Cameraman = "Mechanic", Reporter = "Medic", Sound = "Scout", Intern = "Brute" }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

--------------------------------------------------
-- BUILDING
--------------------------------------------------

-- a prop part stuck to one of the body's parts, `offset` from it
local function prop(kit, bodyPart, offset, props)
	local p = Instance.new("Part")
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Anchored = bodyPart.Anchored
	p.CFrame = bodyPart.CFrame * offset
	p.Parent = kit
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bodyPart
	weld.Part1 = p
	weld.Parent = p
	return p
end

local function label(part, face, text, colour, font)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 100
	sg.LightInfluence = 1
	sg.Parent = part
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.SourceSansBold
	l.TextScaled = true
	l.TextColor3 = colour
	l.Text = text
	l.Parent = sg
end

local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local DARK = rgb(28, 28, 30)

local function badge(kit, body)
	local card = prop(kit, body.Torso, CFrame.new(0.55, 0.3, -0.53), { Name = "PressBadge", Size = Vector3.new(0.5, 0.62, 0.04), Color = rgb(236, 232, 220) })
	label(card, Enum.NormalId.Front, "PRESS\n8", rgb(170, 20, 20))
	prop(kit, body.Torso, CFrame.new(0.55, 0.64, -0.53), { Name = "BadgeClip", Size = Vector3.new(0.2, 0.08, 0.06), Color = rgb(160, 160, 165), Material = Enum.Material.Metal })
end

local KITS = {}

KITS.Photographer = function(kit, body)
	-- the camera on her chest, hanging off a strap round her neck
	local t = body.Torso
	prop(kit, t, CFrame.new(0, -0.2, -0.82), { Name = "CameraBody", Size = Vector3.new(0.95, 0.6, 0.5), Color = DARK })
	prop(kit, t, CFrame.new(0, -0.24, -1.2) * CFrame.Angles(0, math.rad(90), 0), { Name = "CameraLens", Shape = CYL, Size = Vector3.new(0.45, 0.42, 0.42), Color = rgb(18, 18, 20) })
	prop(kit, t, CFrame.new(0, -0.24, -1.43) * CFrame.Angles(0, math.rad(90), 0), { Name = "LensGlass", Shape = CYL, Size = Vector3.new(0.03, 0.3, 0.3),
		Color = rgb(70, 90, 120), Material = Enum.Material.Glass, Reflectance = 0.3 })
	prop(kit, t, CFrame.new(-0.18, 0.2, -0.82), { Name = "Flash", Size = Vector3.new(0.42, 0.26, 0.32), Color = rgb(40, 40, 42) })
	prop(kit, t, CFrame.new(-0.18, 0.21, -0.99), { Name = "FlashWindow", Size = Vector3.new(0.34, 0.18, 0.03), Color = rgb(235, 235, 225), Material = Enum.Material.Glass })
	for _, s in ipairs({ -1, 1 }) do
		prop(kit, t, CFrame.new(s * 0.42, 0.45, -0.56) * CFrame.Angles(math.rad(-12), 0, math.rad(s * 14)), { Name = "Strap", Size = Vector3.new(0.12, 1.15, 0.04), Color = rgb(20, 20, 22),
			Material = Enum.Material.Fabric })
	end
end

KITS.Cameraman = function(kit, body)
	-- a shoulder camcorder on his right shoulder
	local t = body.Torso
	local cam = CFrame.new(1.0, 1.42, -0.15)
	prop(kit, t, cam, { Name = "CamcorderBody", Size = Vector3.new(0.7, 0.85, 1.9), Color = rgb(44, 44, 46) })
	prop(kit, t, cam * CFrame.new(0, 0.05, -1.25) * CFrame.Angles(0, math.rad(90), 0), { Name = "CamcorderLens", Shape = CYL, Size = Vector3.new(0.65, 0.6, 0.6), Color = rgb(20, 20, 22) })
	prop(kit, t, cam * CFrame.new(0, 0.05, -1.58) * CFrame.Angles(0, math.rad(90), 0), { Name = "LensHood", Shape = CYL, Size = Vector3.new(0.05, 0.72, 0.72), Color = rgb(14, 14, 16) })
	prop(kit, t, cam * CFrame.new(-0.5, 0.25, -0.55), { Name = "Viewfinder", Size = Vector3.new(0.3, 0.3, 0.6), Color = rgb(30, 30, 32) })
	prop(kit, t, cam * CFrame.new(0, 0.53, 0.1), { Name = "Handle", Size = Vector3.new(0.18, 0.2, 1.1), Color = rgb(24, 24, 26) })
	prop(kit, t, cam * CFrame.new(0.12, 0.3, -0.97), { Name = "TallyLight", Shape = BALL, Size = Vector3.new(0.13, 0.13, 0.13), Color = rgb(255, 30, 30), Material = Enum.Material.Neon })
	local side = prop(kit, t, cam * CFrame.new(0.36, 0, 0.2), { Name = "CamcorderSide", Size = Vector3.new(0.02, 0.5, 1.0), Color = rgb(44, 44, 46) })
	label(side, Enum.NormalId.Right, "WKRT 8", rgb(220, 220, 220))
end

KITS.Reporter = function(kit, body)
	-- the Channel 8 microphone in her right hand
	local arm = body["Right Arm"]
	local mic = CFrame.new(0, -1.1, -0.35) * CFrame.Angles(math.rad(-25), 0, 0)
	prop(kit, arm, mic * CFrame.Angles(0, 0, math.rad(90)), { Name = "MicHandle", Shape = CYL, Size = Vector3.new(0.9, 0.16, 0.16), Color = rgb(30, 30, 32) })
	prop(kit, arm, mic * CFrame.new(0, 0.55, 0), { Name = "MicHead", Shape = BALL, Size = Vector3.new(0.36, 0.36, 0.36), Color = rgb(40, 40, 44), Material = Enum.Material.Fabric })
	local flag = prop(kit, arm, mic * CFrame.new(0, 0.2, 0), { Name = "MicFlag", Size = Vector3.new(0.36, 0.28, 0.36), Color = rgb(190, 24, 24) })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
		label(flag, face, "8", rgb(255, 255, 255))
	end
	-- and a notepad sticking out of her jacket pocket
	prop(kit, body.Torso, CFrame.new(-0.55, -0.35, -0.53) * CFrame.Angles(0, 0, math.rad(-8)), { Name = "Notepad", Size = Vector3.new(0.42, 0.6, 0.06), Color = rgb(238, 230, 170) })
end

KITS.Sound = function(kit, body)
	-- headphones over his head
	local h = body.Head
	for _, s in ipairs({ -1, 1 }) do
		prop(kit, h, CFrame.new(s * 0.66, 0.02, 0), { Name = "EarCup", Shape = CYL, Size = Vector3.new(0.24, 0.62, 0.62), Color = rgb(26, 26, 28) })
		prop(kit, h, CFrame.new(s * 0.79, 0.02, 0), { Name = "EarCupBack", Shape = CYL, Size = Vector3.new(0.06, 0.4, 0.4), Color = rgb(150, 150, 155), Material = Enum.Material.Metal })
		prop(kit, h, CFrame.new(s * 0.62, 0.48, 0) * CFrame.Angles(0, 0, math.rad(s * -24)), { Name = "Band", Size = Vector3.new(0.12, 0.5, 0.2), Color = rgb(30, 30, 32) })
	end
	prop(kit, h, CFrame.new(0, 0.7, 0), { Name = "BandTop", Size = Vector3.new(0.85, 0.12, 0.2), Color = rgb(30, 30, 32) })
	-- the tape recorder on his left hip, on a strap across his chest
	local t = body.Torso
	local rec = prop(kit, t, CFrame.new(-1.12, -0.7, -0.05), { Name = "Recorder", Size = Vector3.new(0.34, 0.7, 0.95), Color = rgb(150, 146, 136), Material = Enum.Material.Metal })
	label(rec, Enum.NormalId.Left, "NAGRA", rgb(30, 30, 30))
	for _, z in ipairs({ -0.22, 0.22 }) do
		prop(kit, t, CFrame.new(-1.3, -0.62, -0.05 + z), { Name = "Reel", Shape = CYL, Size = Vector3.new(0.05, 0.36, 0.36), Color = rgb(20, 20, 22) })
	end
	prop(kit, t, CFrame.new(0, 0.1, -0.53) * CFrame.Angles(0, 0, math.rad(-38)), { Name = "Strap", Size = Vector3.new(0.14, 2.5, 0.04), Color = rgb(60, 44, 30),
		Material = Enum.Material.Fabric })
end

KITS.Intern = function(kit, body)
	-- the big gear backpack
	local t = body.Torso
	local pack = prop(kit, t, CFrame.new(0, -0.05, 0.95), { Name = "Backpack", Size = Vector3.new(1.7, 1.9, 0.9), Color = rgb(74, 66, 46), Material = Enum.Material.Fabric })
	label(pack, Enum.NormalId.Back, "WKRT 8", rgb(220, 210, 180))
	prop(kit, t, CFrame.new(0, 1.0, 0.95), { Name = "PackTop", Size = Vector3.new(1.5, 0.2, 0.8), Color = rgb(62, 56, 40), Material = Enum.Material.Fabric })
	prop(kit, t, CFrame.new(0, 1.25, 0.95), { Name = "Coil", Shape = CYL, Size = Vector3.new(1.3, 0.42, 0.42), Color = rgb(20, 20, 22) })
	prop(kit, t, CFrame.new(0.95, -0.3, 0.95), { Name = "SidePocket", Size = Vector3.new(0.25, 0.8, 0.6), Color = rgb(66, 58, 40), Material = Enum.Material.Fabric })
	for _, s in ipairs({ -1, 1 }) do
		prop(kit, t, CFrame.new(s * 0.55, 0.3, -0.53), { Name = "PackStrap", Size = Vector3.new(0.22, 1.5, 0.05), Color = rgb(40, 36, 26), Material = Enum.Material.Fabric })
	end
	-- a flashlight in his left hand
	local arm = body["Left Arm"]
	prop(kit, arm, CFrame.new(0, -1.15, -0.25) * CFrame.Angles(0, math.rad(90), 0), { Name = "Flashlight", Shape = CYL, Size = Vector3.new(0.9, 0.2, 0.2), Color = rgb(30, 30, 32) })
	prop(kit, arm, CFrame.new(0, -1.15, -0.72) * CFrame.Angles(0, math.rad(90), 0), { Name = "FlashlightHead", Shape = CYL, Size = Vector3.new(0.18, 0.3, 0.3), Color = rgb(255, 245, 210),
		Material = Enum.Material.Neon })
end

--------------------------------------------------
-- DRESS EVERYONE
--------------------------------------------------

local function dress(model, role)
	local body = {}
	for _, name in ipairs({ "Head", "Torso", "Right Arm", "Left Arm" }) do
		body[name] = model:FindFirstChild(name)
		if not body[name] then
			warn("Skipped " .. model:GetFullName() .. ": it has no " .. name .. " (it needs to be an R6 character)")
			return false
		end
	end
	local old = model:FindFirstChild("JournalistKit")
	if old then
		old:Destroy()
	end
	local kit = Instance.new("Model")
	kit.Name = "JournalistKit"
	kit.Parent = model
	badge(kit, body)
	KITS[role](kit, body)
	return true
end

ChangeHistoryService:SetWaypoint("Before dressing the journalists")
local dressed = 0
local storage = ServerStorage:FindFirstChild("RoleCharacters")
local displays = workspace:FindFirstChild("RoleDisplays")
for role, oldName in pairs(OLD_NAMES) do
	local character = storage and (storage:FindFirstChild(role) or storage:FindFirstChild(oldName))
	if character and dress(character, role) then
		dressed += 1
	end
	local figure = displays and (displays:FindFirstChild(role .. "Display") or displays:FindFirstChild(oldName .. "Display"))
	if figure and dress(figure, role) then
		dressed += 1
	end
end
ChangeHistoryService:SetWaypoint("Dressed the journalists")
print("Dressed " .. dressed .. " characters (up to 10: five to play as, five in the lockers). Save your place to keep it.")
