-- BuildDoor
-- Run in Studio's Command Bar to put a door in a doorway:
--   1. Put a plain block (Part) in the doorway that fills the gap exactly:
--      as wide and tall as the opening, as thick as the wall. Keep it upright.
--   2. Select it (you can select several blocks to build several doors at once).
--   3. Change KIND below to "Wood", "Steel" or "Cell" (and HINGE if you want).
--   4. View > Command Bar, paste all of this, press Enter. Save your place.
-- The block is replaced by the door. Ctrl+Z undoes it.
--
--   Wood   a rotten plank cellar door: iron straps, a ring pull, a Z brace,
--          claw marks gouged into one side and a bloody hand smear on the other
--   Steel  a rusted boiler-room door: rivets, a wired window, a lever handle,
--          rust running down from every rivet, BOILER ROOM stencilled on it
--   Cell   a barred iron gate: round bars (one bent), a padlock box, spikes

local KIND = "Wood"        -- "Wood", "Steel" or "Cell"
local HINGE = "Left"       -- "Left" or "Right" (as you look at the block's front face)

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local rng = Random.new(1987)

--------------------------------------------------
-- PARTS
--------------------------------------------------

-- props: Name, Size, CF (in door space: X across, Y up, Z through the wall),
-- Color, Material, Collide (default true), Shape, Transparency, Reflectance
local function makePart(parent, frame, p)
	local part = Instance.new("Part")
	part.Name = p.Name
	part.Size = p.Size
	part.CFrame = frame * p.CF
	part.Color = p.Color
	part.Material = p.Material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = p.Collide ~= false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if p.Shape then
		part.Shape = p.Shape
	end
	part.Transparency = p.Transparency or 0
	part.Reflectance = p.Reflectance or 0
	part.CastShadow = p.Shadow ~= false
	part.Parent = parent
	return part
end

local function vary(c, amount)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, math.clamp(s * (1 + rng:NextNumber(-amount, amount)), 0, 1), math.clamp(v * (1 + rng:NextNumber(-amount, amount)), 0, 1))
end

local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))      -- turns a cylinder to stand up

--------------------------------------------------
-- THE THREE LEAVES (W x H, hinge at x = -W/2)
--------------------------------------------------

local LEAVES = {}

LEAVES.Wood = function(leaf, f, W, H)
	local n = math.max(4, math.floor(W / 0.6 + 0.5))
	local pw = W / n
	local woods = { rgb(78, 58, 40), rgb(66, 50, 36), rgb(90, 68, 46), rgb(58, 46, 34), rgb(72, 70, 50) }
	for i = 1, n do
		-- rotten planks: some are short at the bottom, all a little warped
		local short = (i == 2 or i == n - 1) and rng:NextNumber(0.25, 0.6) or rng:NextNumber(0, 0.08)
		local h = H - short
		local x = -W / 2 + pw * (i - 0.5)
		local plank = makePart(leaf, f, { Name = "Plank", Size = Vector3.new(pw - 0.035, h, 0.28),
			CF = CFrame.new(x, short / 2, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-0.5, 0.5))),
			Color = vary(woods[(i % #woods) + 1], 0.1), Material = Enum.Material.Wood })
		plank:SetAttribute("Main", true)
	end
	-- rails and the Z brace on the back face
	local railY = H * 0.3
	for _, y in ipairs({ railY, -railY }) do
		makePart(leaf, f, { Name = "Rail", Size = Vector3.new(W - 0.3, 0.42, 0.16), CF = CFrame.new(0, y, 0.22),
			Color = rgb(60, 44, 30), Material = Enum.Material.Wood })
	end
	local dy, dx = railY * 2 - 0.42, W - 0.7
	makePart(leaf, f, { Name = "Brace", Size = Vector3.new(0.38, math.sqrt(dx * dx + dy * dy), 0.15), CF = CFrame.new(0, 0, 0.22)
		* CFrame.Angles(0, 0, math.atan2(dx, dy)), Color = rgb(56, 42, 30), Material = Enum.Material.Wood })
	-- iron strap hinges and nails on the front
	for _, y in ipairs({ railY, -railY }) do
		makePart(leaf, f, { Name = "Strap", Size = Vector3.new(W * 0.58, 0.22, 0.05), CF = CFrame.new(-W / 2 + W * 0.29, y, -0.165),
			Color = rgb(52, 44, 40), Material = Enum.Material.CorrodedMetal, Collide = false })
		for k = 0, 3 do
			makePart(leaf, f, { Name = "Nail", Shape = BALL, Size = Vector3.new(0.09, 0.09, 0.09),
				CF = CFrame.new(-W / 2 + 0.25 + k * W * 0.16, y, -0.19), Color = rgb(40, 36, 34), Material = Enum.Material.Metal, Collide = false, Shadow = false })
		end
	end
	-- the ring pull and its plate
	local hx = W / 2 - 0.42
	makePart(leaf, f, { Name = "Plate", Size = Vector3.new(0.34, 0.5, 0.04), CF = CFrame.new(hx, 0, -0.16), Color = rgb(44, 38, 34),
		Material = Enum.Material.CorrodedMetal, Collide = false })
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		makePart(leaf, f, { Name = "Ring", Size = Vector3.new(0.06, 0.11, 0.06), CF = CFrame.new(hx + math.sin(a) * 0.22, -0.2 + math.cos(a) * 0.22, -0.21)
			* CFrame.Angles(0, 0, -a), Color = rgb(38, 34, 32), Material = Enum.Material.Metal, Collide = false, Shadow = false })
	end
	-- claw marks gouged into the back, a bloody hand smear on the front
	for k = 0, 3 do
		makePart(leaf, f, { Name = "Gouge", Size = Vector3.new(0.05, 1.05 - k * 0.08, 0.02), CF = CFrame.new(0.1 + k * 0.16, H * 0.08 - k * 0.04, 0.305)
			* CFrame.Angles(0, 0, math.rad(22)), Color = rgb(28, 20, 14), Collide = false, Shadow = false })
	end
	makePart(leaf, f, { Name = "Smear", Size = Vector3.new(0.42, 0.75, 0.02), CF = CFrame.new(hx - 0.35, 0.35, -0.15) * CFrame.Angles(0, 0, math.rad(-14)),
		Color = rgb(62, 10, 10), Material = Enum.Material.SmoothPlastic, Collide = false, Shadow = false, Transparency = 0.15 })
	return "Plank"
end

LEAVES.Steel = function(leaf, f, W, H)
	local slab = makePart(leaf, f, { Name = "Slab", Size = Vector3.new(W, H, 0.26), CF = CFrame.new(), Color = rgb(70, 62, 54),
		Material = Enum.Material.CorrodedMetal })
	slab:SetAttribute("Main", true)
	-- raised frame strips on both faces, with rivets
	for _, z in ipairs({ -0.15, 0.15 }) do
		makePart(leaf, f, { Name = "Strip", Size = Vector3.new(W, 0.28, 0.06), CF = CFrame.new(0, H / 2 - 0.14, z), Color = rgb(56, 48, 42), Material = Enum.Material.Metal })
		makePart(leaf, f, { Name = "Strip", Size = Vector3.new(W, 0.42, 0.06), CF = CFrame.new(0, -H / 2 + 0.21, z), Color = rgb(48, 42, 38), Material = Enum.Material.Metal })
		makePart(leaf, f, { Name = "Strip", Size = Vector3.new(W, 0.22, 0.06), CF = CFrame.new(0, -H * 0.08, z), Color = rgb(56, 48, 42), Material = Enum.Material.Metal })
		for _, x in ipairs({ -W / 2 + 0.14, W / 2 - 0.14 }) do
			makePart(leaf, f, { Name = "Strip", Size = Vector3.new(0.28, H, 0.06), CF = CFrame.new(x, 0, z), Color = rgb(56, 48, 42), Material = Enum.Material.Metal })
		end
		local count = math.floor(W / 0.5)
		for k = 0, count do
			local x = -W / 2 + 0.14 + k * (W - 0.28) / count
			for _, y in ipairs({ H / 2 - 0.14, -H * 0.08 }) do
				makePart(leaf, f, { Name = "Rivet", Shape = BALL, Size = Vector3.new(0.11, 0.11, 0.11), CF = CFrame.new(x, y, z * 1.32),
					Color = rgb(64, 56, 50), Material = Enum.Material.Metal, Collide = false, Shadow = false })
				-- rust bleeding down from some of them
				if z < 0 and rng:NextNumber() < 0.45 then
					local len = rng:NextNumber(0.4, 1.2)
					makePart(leaf, f, { Name = "Rust", Size = Vector3.new(rng:NextNumber(0.05, 0.12), len, 0.01), CF = CFrame.new(x, y - len / 2 - 0.05, -0.135),
						Color = vary(rgb(112, 56, 28), 0.15), Material = Enum.Material.CorrodedMetal, Collide = false, Shadow = false })
				end
			end
		end
	end
	-- the wired window at eye height
	local wy = H * 0.24
	makePart(leaf, f, { Name = "Window", Size = Vector3.new(W * 0.36, 0.5, 0.3), CF = CFrame.new(0.1, wy, 0), Color = rgb(30, 34, 32),
		Material = Enum.Material.Glass, Transparency = 0.3, Reflectance = 0.15 })
	for k = -1, 1 do
		makePart(leaf, f, { Name = "Wire", Size = Vector3.new(0.04, 0.5, 0.32), CF = CFrame.new(0.1 + k * W * 0.1, wy, 0), Color = rgb(50, 46, 42),
			Material = Enum.Material.Metal, Collide = false })
	end
	-- lever handles both sides, barrel hinges
	local hx = W / 2 - 0.42
	for _, s in ipairs({ -1, 1 }) do
		makePart(leaf, f, { Name = "Spindle", Shape = CYL, Size = Vector3.new(0.24, 0.16, 0.16), CF = CFrame.new(hx, -0.2, s * 0.24) * CFrame.Angles(0, math.rad(90), 0),
			Color = rgb(40, 38, 36), Material = Enum.Material.Metal, Collide = false })
		makePart(leaf, f, { Name = "Lever", Size = Vector3.new(0.55, 0.11, 0.11), CF = CFrame.new(hx - 0.22, -0.2, s * 0.34), Color = rgb(36, 34, 32),
			Material = Enum.Material.Metal, Collide = false })
	end
	for _, y in ipairs({ H * 0.35, 0, -H * 0.35 }) do
		makePart(leaf, f, { Name = "Hinge", Shape = CYL, Size = Vector3.new(0.6, 0.2, 0.2), CF = CFrame.new(-W / 2 - 0.02, y, -0.12) * UPRIGHT,
			Color = rgb(44, 40, 38), Material = Enum.Material.Metal, Collide = false })
	end
	-- the stencil (on the front), and deep claw dents on the back
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 1
	sg.Parent = slab
	local function stencil(text, y, h, colour)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.1, y)
		l.Size = UDim2.fromScale(0.8, h)
		l.Font = Enum.Font.SpecialElite
		l.TextScaled = true
		l.TextColor3 = colour
		l.TextTransparency = 0.3
		l.Text = text
		l.Parent = sg
	end
	stencil("BOILER ROOM", 0.5, 0.08, rgb(200, 190, 160))
	stencil("NO ENTRY", 0.6, 0.07, rgb(150, 30, 24))
	for k = 0, 3 do
		makePart(leaf, f, { Name = "Dent", Size = Vector3.new(0.07, 0.9, 0.02), CF = CFrame.new(-0.2 + k * 0.18, -H * 0.2, 0.19) * CFrame.Angles(0, 0, math.rad(-18)),
			Color = rgb(36, 32, 30), Material = Enum.Material.Metal, Collide = false, Shadow = false })
	end
	return "Slab"
end

LEAVES.Cell = function(leaf, f, W, H)
	local iron, dark = rgb(54, 50, 48), rgb(40, 38, 36)
	local top = makePart(leaf, f, { Name = "Rail", Size = Vector3.new(W, 0.2, 0.2), CF = CFrame.new(0, H / 2 - 0.1, 0), Color = iron, Material = Enum.Material.CorrodedMetal })
	top:SetAttribute("Main", true)
	makePart(leaf, f, { Name = "Rail", Size = Vector3.new(W, 0.2, 0.2), CF = CFrame.new(0, -H / 2 + 0.1, 0), Color = iron, Material = Enum.Material.CorrodedMetal })
	for _, x in ipairs({ -W / 2 + 0.1, W / 2 - 0.1 }) do
		makePart(leaf, f, { Name = "Stile", Size = Vector3.new(0.2, H, 0.2), CF = CFrame.new(x, 0, 0), Color = iron, Material = Enum.Material.CorrodedMetal })
	end
	for _, y in ipairs({ H * 0.2, -H * 0.18 }) do
		makePart(leaf, f, { Name = "FlatBar", Size = Vector3.new(W - 0.2, 0.13, 0.07), CF = CFrame.new(0, y, -0.06), Color = dark, Material = Enum.Material.Metal })
	end
	local count = math.max(3, math.floor((W - 0.4) / 0.42))
	for k = 1, count do
		local x = -W / 2 + 0.2 + k * (W - 0.4) / (count + 1)
		-- one bar is bent, as if something pulled at it
		local bend = (k == math.ceil(count / 2) + 1) and math.rad(6) or 0
		makePart(leaf, f, { Name = "Bar", Shape = CYL, Size = Vector3.new(H - 0.3, 0.13, 0.13), CF = CFrame.new(x, 0, 0) * CFrame.Angles(bend, 0, 0) * UPRIGHT,
			Color = vary(iron, 0.08), Material = Enum.Material.CorrodedMetal })
		makePart(leaf, f, { Name = "Spike", Shape = CYL, Size = Vector3.new(0.3, 0.07, 0.07), CF = CFrame.new(x, H / 2 + 0.12, 0) * UPRIGHT,
			Color = dark, Material = Enum.Material.Metal, Collide = false })
	end
	-- the lock box at the free edge, its keyhole, the padlock
	local lx = W / 2 - 0.28
	makePart(leaf, f, { Name = "LockBox", Size = Vector3.new(0.42, 0.6, 0.32), CF = CFrame.new(lx, -0.05, 0), Color = dark, Material = Enum.Material.Metal })
	makePart(leaf, f, { Name = "Keyhole", Size = Vector3.new(0.06, 0.16, 0.02), CF = CFrame.new(lx, -0.05, -0.17), Color = rgb(8, 8, 8), Collide = false, Shadow = false })
	makePart(leaf, f, { Name = "Padlock", Size = Vector3.new(0.3, 0.32, 0.12), CF = CFrame.new(lx + 0.05, -0.45, -0.2), Color = rgb(88, 74, 50),
		Material = Enum.Material.CorrodedMetal, Collide = false })
	for _, y in ipairs({ H * 0.36, -H * 0.36 }) do
		makePart(leaf, f, { Name = "Hinge", Shape = CYL, Size = Vector3.new(0.5, 0.22, 0.22), CF = CFrame.new(-W / 2 - 0.02, y, 0) * UPRIGHT,
			Color = dark, Material = Enum.Material.Metal, Collide = false })
	end
	return "Rail"
end

--------------------------------------------------
-- THE FRAME AROUND IT
--------------------------------------------------

local FRAMES = {
	Wood = { colour = rgb(52, 38, 28), material = Enum.Material.Wood },
	Steel = { colour = rgb(46, 42, 40), material = Enum.Material.CorrodedMetal },
	Cell = { colour = rgb(44, 42, 40), material = Enum.Material.Concrete },
}

local function buildFrame(model, f, W, H, T, kind)
	local look = FRAMES[kind]
	for _, z in ipairs({ T / 2 + 0.06, -T / 2 - 0.06 }) do
		for _, x in ipairs({ -W / 2 - 0.22, W / 2 + 0.22 }) do
			makePart(model, f, { Name = "Casing", Size = Vector3.new(0.44, H + 0.44, 0.12), CF = CFrame.new(x, 0.22, z), Color = look.colour, Material = look.material })
		end
		makePart(model, f, { Name = "Casing", Size = Vector3.new(W + 0.88, 0.44, 0.12), CF = CFrame.new(0, H / 2 + 0.22, z), Color = look.colour, Material = look.material })
	end
	makePart(model, f, { Name = "Sill", Size = Vector3.new(W + 0.2, 0.08, T + 0.25), CF = CFrame.new(0, -H / 2 + 0.04, 0), Color = rgb(34, 30, 28),
		Material = Enum.Material.Concrete })
end

--------------------------------------------------
-- BUILD
--------------------------------------------------

assert(LEAVES[KIND], 'KIND has to be "Wood", "Steel" or "Cell"')
local blocks = {}
for _, s in ipairs(Selection:Get()) do
	if s:IsA("BasePart") then
		table.insert(blocks, s)
	end
end
assert(#blocks > 0, "Select the block(s) filling your doorway(s) first, then run this again.")

ChangeHistoryService:SetWaypoint("Before building doors")
local built = {}
for _, block in ipairs(blocks) do
	local f = block.CFrame
	if HINGE == "Right" then
		f = f * CFrame.Angles(0, math.pi, 0)
	end
	local W, H, T = block.Size.X, block.Size.Y, block.Size.Z

	local model = Instance.new("Model")
	model.Name = KIND .. "Door"
	buildFrame(model, f, W, H, T, KIND)

	local leaf = Instance.new("Model")
	leaf.Name = "Leaf"
	leaf.Parent = model
	local gapW, gapH = W - 0.1, H - 0.1
	local leafF = f * CFrame.new(0, 0.03, 0)
	LEAVES[KIND](leaf, leafF, gapW, gapH)

	-- the hinge: the leaf turns around this (it's what the scripts move)
	local root = makePart(leaf, leafF, { Name = "LeafRoot", Size = Vector3.new(0.2, gapH, 0.2), CF = CFrame.new(-gapW / 2, 0, 0),
		Color = rgb(0, 0, 0), Collide = false, Transparency = 1, Shadow = false })
	root.CanQuery = false
	leaf.PrimaryPart = root

	-- the Crawler's paths go through doors (it deals with them when it gets there)
	for _, p in ipairs(leaf:GetChildren()) do
		if p:IsA("BasePart") and p.CanCollide then
			local m = Instance.new("PathfindingModifier")
			m.Label = "Door"
			m.PassThrough = true
			m.Parent = p
		end
	end

	model:SetAttribute("DoorType", KIND)
	model:SetAttribute("Width", gapW)
	model:SetAttribute("Height", gapH)
	model:SetAttribute("Hinge", root.CFrame)
	model:SetAttribute("Centre", leafF)
	model:SetAttribute("Angle", 0)
	model:SetAttribute("Broken", false)
	model:SetAttribute("BarricadedBy", 0)
	model.PrimaryPart = root
	model.Parent = block.Parent
	block.Parent = nil
	table.insert(built, model)
end
ChangeHistoryService:SetWaypoint("Built doors")
Selection:Set(built)
print("Built " .. #built .. " " .. KIND .. " door(s). Save your place to keep them.")
