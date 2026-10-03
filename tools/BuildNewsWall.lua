-- BuildNewsWall
-- Run ONCE in Studio:
--   1. Click the wall you want the TVs against (so it's selected).
--   2. Move the camera so you're looking at that wall from inside the room.
--   3. View > Command Bar, paste all of this, press Enter.
-- It builds a stack of old CRT TVs on a cabinet against the side of the wall
-- facing you, at the spot nearest your camera. Save the place to keep it.
-- Ctrl+Z removes it. Run it again with another wall selected for another stack.
--
-- The screens are blank in Studio. In the game, LobbyAtmosphere switches them
-- on: static, colour bars, Channel 8 news about the Holloways, and worse.

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local wall = Selection:Get()[1]
assert(wall and wall:IsA("BasePart"), "Select a wall (a Part) first, then run this again.")

--------------------------------------------------
-- WHERE: the face of the wall that faces the camera
--------------------------------------------------

local camPos = workspace.CurrentCamera.CFrame.Position
local half = wall.Size / 2
local best, bestScore, bestAxis, bestSign
for _, axis in ipairs({ "X", "Z" }) do
	for _, sign in ipairs({ 1, -1 }) do
		local normal = wall.CFrame:VectorToWorldSpace(axis == "X" and Vector3.new(sign, 0, 0) or Vector3.new(0, 0, sign))
		local score = normal:Dot((camPos - wall.Position).Unit)
		if not bestScore or score > bestScore then
			best, bestScore, bestAxis, bestSign = normal, score, axis, sign
		end
	end
end
local out = Vector3.new(best.X, 0, best.Z).Unit       -- out of the wall, into the room

-- the point on that face nearest the camera
local localCam = wall.CFrame:PointToObjectSpace(camPos)
local along = bestAxis == "X" and "Z" or "X"
local alongHalf = half[along]
local margin = math.min(5.5, alongHalf)
local alongPos = math.clamp(localCam[along], -alongHalf + margin, alongHalf - margin)
local onFace = wall.CFrame:PointToWorldSpace(bestAxis == "X"
	and Vector3.new(bestSign * half.X, 0, alongPos)
	or Vector3.new(alongPos, 0, bestSign * half.Z))

-- the floor in front of it
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { wall }
local probe = onFace + out * 2 + Vector3.new(0, 4, 0)
local hit = workspace:Raycast(probe, Vector3.new(0, -60, 0), params)
local floorY = hit and hit.Position.Y or (wall.Position.Y - half.Y)

local base = Vector3.new(onFace.X, floorY, onFace.Z)
local frame = CFrame.lookAt(base, base + out)            -- LookVector = into the room

--------------------------------------------------
-- BUILDING BLOCKS
--------------------------------------------------

local model = Instance.new("Model")
model.Name = "ChannelEightTVs"

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = model
	return p
end

-- x = sideways along the wall, y = up from the floor, z = out from the wall
local function at(x, y, z, yaw)
	return frame * CFrame.new(-x, y, -z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

-- one TV: bottom centre at (x, y, z) from the wall, size w x h x d
local function tv(name, x, y, z, w, h, d, yaw, look)
	local c = at(x, y, z, yaw)
	local body = part({ Name = name .. "Body", Size = Vector3.new(w, h, d), CFrame = c * CFrame.new(0, h / 2, 0),
		Color = look.color, Material = look.material })
	local screenW, screenH = w * 0.66, h * 0.7
	local screenX = look.knobs and -w * 0.1 or 0
	-- the dark bezel around the glass
	part({ Name = name .. "Bezel", Size = Vector3.new(screenW + 0.24, screenH + 0.24, 0.12),
		CFrame = c * CFrame.new(screenX, h / 2, -d / 2 - 0.04), Color = Color3.fromRGB(18, 17, 16), Material = Enum.Material.SmoothPlastic })
	local screen = part({ Name = "Screen", Size = Vector3.new(screenW, screenH, 0.1),
		CFrame = c * CFrame.new(screenX, h / 2, -d / 2 - 0.09), Color = Color3.fromRGB(22, 26, 24), Material = Enum.Material.Glass,
		Reflectance = 0.08, CastShadow = false })
	screen:SetAttribute("CRTScreen", true)
	local glow = Instance.new("SurfaceLight")
	glow.Name = "ScreenGlow"
	glow.Face = Enum.NormalId.Front
	glow.Range = 12
	glow.Angle = 100
	glow.Brightness = 0
	glow.Shadows = true
	glow.Parent = screen
	-- the knob panel
	if look.knobs then
		for i, ky in ipairs({ 0.62, 0.38 }) do
			part({ Name = name .. "Knob" .. i, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, 0.34, 0.34),
				CFrame = c * CFrame.new(w * 0.36, h * ky, -d / 2 - 0.09) * CFrame.Angles(0, math.rad(90), 0),
				Color = Color3.fromRGB(40, 36, 32), Material = Enum.Material.SmoothPlastic })
		end
		part({ Name = name .. "Speaker", Size = Vector3.new(w * 0.18, h * 0.18, 0.06),
			CFrame = c * CFrame.new(w * 0.36, h * 0.17, -d / 2 - 0.03), Color = Color3.fromRGB(28, 26, 24), Material = Enum.Material.Fabric })
	end
	-- rabbit ears
	if look.antenna then
		for _, s in ipairs({ -1, 1 }) do
			part({ Name = name .. "Antenna", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 0.07, 0.07),
				CFrame = c * CFrame.new(s * 0.45, h + 1.05, 0.2) * CFrame.Angles(0, 0, math.rad(90 - s * 28)) * CFrame.Angles(math.rad(s * 8), 0, 0),
				Color = Color3.fromRGB(150, 150, 152), Material = Enum.Material.Metal })
		end
		part({ Name = name .. "AntennaBase", Size = Vector3.new(0.7, 0.18, 0.5), CFrame = c * CFrame.new(0, h + 0.09, 0.2),
			Color = Color3.fromRGB(30, 30, 30), Material = Enum.Material.SmoothPlastic })
	end
	-- the cable trailing off the back and down
	part({ Name = name .. "Cable", Size = Vector3.new(0.09, math.max(y + h * 0.3, 0.2), 0.09),
		CFrame = c * CFrame.new(w * 0.3, (h * 0.3 - y) / 2, d / 2 + 0.06), Color = Color3.fromRGB(14, 14, 14),
		Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false })
	return body
end

local WOOD = { color = Color3.fromRGB(92, 62, 40), material = Enum.Material.Wood, knobs = true }
local BEIGE = { color = Color3.fromRGB(164, 152, 128), material = Enum.Material.Plastic, knobs = true }
local BLACK = { color = Color3.fromRGB(34, 32, 30), material = Enum.Material.Plastic, knobs = false }
local GREY = { color = Color3.fromRGB(96, 94, 90), material = Enum.Material.Plastic, knobs = true }

--------------------------------------------------
-- THE STACK
--------------------------------------------------

-- the low cabinet
local cabW, cabH, cabD = 10.5, 2.1, 2.9
part({ Name = "Cabinet", Size = Vector3.new(cabW, cabH, cabD), CFrame = at(0, cabH / 2, cabD / 2 + 0.05),
	Color = Color3.fromRGB(58, 40, 28), Material = Enum.Material.Wood })
part({ Name = "CabinetTop", Size = Vector3.new(cabW + 0.2, 0.16, cabD + 0.2), CFrame = at(0, cabH + 0.08, cabD / 2 + 0.05),
	Color = Color3.fromRGB(70, 48, 32), Material = Enum.Material.WoodPlanks })
for i = -1, 1 do
	part({ Name = "CabinetDoor", Size = Vector3.new(cabW / 3 - 0.3, cabH - 0.5, 0.08), CFrame = at(i * cabW / 3, cabH / 2, cabD + 0.07),
		Color = Color3.fromRGB(48, 32, 22), Material = Enum.Material.Wood })
end

local top = cabH + 0.16
-- bottom row
tv("Big", -2.9, top, 1.65, 4.4, 3.5, 3.1, 3, WOOD)
tv("Mid", 1.1, top, 1.5, 3.3, 2.8, 2.7, -4, BEIGE)
tv("Small", 3.9, top, 1.35, 2.4, 2.1, 2.2, -10, BLACK)
-- top row, stacked and a little crooked
local upTop1 = top + 3.5
tv("TopLeft", -2.6, upTop1, 1.6, 3.2, 2.6, 2.6, -6, GREY)
local upTop2 = top + 2.8
tv("TopRight", 1.0, upTop2, 1.45, 2.8, 2.3, 2.3, 7, { color = Color3.fromRGB(40, 38, 36), material = Enum.Material.Plastic, knobs = true, antenna = true })
-- a portable one on the floor beside the cabinet, tipped back against the wall
tv("Floor", 6.6, 0, 1.0, 2.2, 1.9, 1.8, -24, BEIGE)

-- a VCR set into the cabinet under the big TV, its clock blinking 12:00 in the game
part({ Name = "VCR", Size = Vector3.new(3.2, 0.5, 0.4), CFrame = at(-2.9, cabH - 0.45, cabD + 0.02),
	Color = Color3.fromRGB(28, 28, 30), Material = Enum.Material.SmoothPlastic })
local clock = part({ Name = "VCRClock", Size = Vector3.new(0.8, 0.22, 0.05), CFrame = at(-2.3, cabH - 0.45, cabD + 0.24),
	Color = Color3.fromRGB(60, 255, 120), Material = Enum.Material.Neon, CastShadow = false })
clock:SetAttribute("VCRClock", true)

-- a stack of tapes
for i = 0, 3 do
	part({ Name = "Tape", Size = Vector3.new(1.9, 0.26, 1.05), CFrame = at(5.0, top + 0.13 + i * 0.27, 2.2, (i * 23) % 17 - 8),
		Color = Color3.fromRGB(20, 20, 22), Material = Enum.Material.SmoothPlastic })
	part({ Name = "TapeLabel", Size = Vector3.new(1.3, 0.27, 0.02), CFrame = at(5.0, top + 0.13 + i * 0.27, 2.2, (i * 23) % 17 - 8) * CFrame.new(0, 0, -0.53),
		Color = Color3.fromRGB(224, 214, 190), Material = Enum.Material.SmoothPlastic, CastShadow = false })
end

local parent = workspace:FindFirstChild("Hideout") or wall.Parent or workspace
model.Parent = parent
model:SetAttribute("NewsWall", true)

ChangeHistoryService:SetWaypoint("Built the Channel 8 TV wall")
Selection:Set({ model })
print("Built the Channel 8 TV wall in " .. parent:GetFullName() .. ". Move or rotate it like any model, then save.")
