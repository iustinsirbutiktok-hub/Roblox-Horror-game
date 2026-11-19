-- SetupLabGlow
-- Turns the lab models' see-through and glowing parts into real glass and Neon.
-- 1. Import the lab FBX files (assets/Lab) with the 3D Importer.
-- 2. Select the imported models (or nothing: then every lab piece in the Workspace).
-- 3. Paste this into the Command Bar (View > Command Bar), press Enter.
--
-- Parts are recognised by name (the mesh names in the FBX):
--   Glass...   -> Glass, see-through
--   Liquid...  -> Neon, half see-through, with a light (the tank fluid, flask fluid)
--   Glow...    -> Neon (rings, LEDs, lamps) with a small light
--   Screen...  -> dim Neon (monitors, panels) with a faint light
--   Lamp...    -> Neon bulb with a strong light that casts shadows (LabLamp)
-- A colour word at the end picks the colour: GlowBlue, GlowGreen, GlowRed, GlowAmber,
-- LiquidGreen, ScreenGreen ... Everything else (Frame, Specimen) is left alone.
-- Lab_All.fbx imports every piece side by side with names like "ContainmentTank_Frame";
-- those get gathered into one Model per piece.
-- Each part keeps attribute LabGlow = true, and lights are named "LabLight", so
-- your own scripts can flicker or kill them.
-- The moving parts (PowerSwitch.Lever, BreakerPanel.Door) get their pivot put on the hinge,
-- so opening one is a single PivotTo (see assets/Lab/README.md).

local LIGHTS = true            -- add PointLights
local SHADOWS = true           -- the tank and pod lights cast shadows (looks great, costs a little)

local COLOURS = {
	Blue = Color3.fromRGB(64, 170, 255),
	Green = Color3.fromRGB(80, 255, 130),
	Red = Color3.fromRGB(255, 60, 45),
	Amber = Color3.fromRGB(255, 170, 60),
	White = Color3.fromRGB(235, 245, 255),
}
local KINDS = {
	Glass = {colour = Color3.fromRGB(190, 215, 225)},
	Liquid = {colour = COLOURS.Blue, transparency = 0.35, range = 18, brightness = 1.6, shadows = true},
	Glow = {colour = COLOURS.Blue, transparency = 0, range = 7, brightness = 0.9, shadows = false},
	Screen = {colour = Color3.fromRGB(40, 120, 150), transparency = 0.15, range = 5, brightness = 0.5, shadows = false,
		dim = 0.55},
	Lamp = {colour = COLOURS.White, transparency = 0, range = 60, brightness = 1.4, shadows = true},
}

-- each hinge from its mesh's box centre, in studs (written by the build - don't edit)
local PIVOTS = {
	PowerSwitch = {Lever = Vector3.new(0, 0.632, -0.57)},
	BreakerPanel = {Door = Vector3.new(0.296, 0, -1.324)},
}

local Selection = game:GetService("Selection")
local History = game:GetService("ChangeHistoryService")

local LAB = {}
for _, n in ipairs({"ContainmentTank", "ContainmentTankBroken", "CryoPod", "ControlConsole", "ServerRack", "BreakerPanel",
	"Transformer", "LabBench", "CableTray", "PipeManifold", "PowerSwitch", "LabLamp"}) do
	LAB[n] = true
end

local targets = Selection:Get()
local everywhere = #targets == 0
if everywhere then
	targets = {workspace}
end
local recording = History:TryBeginRecording("SetupLabGlow")

-- "ContainmentTank_GlowBlue" -> "ContainmentTank", "GlowBlue";  "GlowBlue" -> nil, "GlowBlue"
local function split(name)
	local piece, part = name:match("^(.-)_([%a]+)$")
	if piece and piece ~= "" then
		return piece, part
	end
	return nil, name
end

local function kindOf(partName)
	for kind in pairs(KINDS) do
		if partName:sub(1, #kind) == kind then
			return kind, partName:sub(#kind + 1)
		end
	end
	return nil
end

-- 1. gather "Piece_Part" meshes into one Model per piece
local gathered = 0
for _, root in ipairs(targets) do
	local byPiece = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("MeshPart") then
			local piece = split(d.Name)
			if piece and LAB[piece] and not (d.Parent:IsA("Model") and d.Parent.Name == piece) then
				byPiece[piece] = byPiece[piece] or {}
				table.insert(byPiece[piece], d)
			end
		end
	end
	for piece, parts in pairs(byPiece) do
		local model = Instance.new("Model")
		model.Name = piece
		model.Parent = parts[1].Parent
		for _, p in ipairs(parts) do
			p.Parent = model
			local _, partName = split(p.Name)
			p.Name = partName
			if partName == "Frame" then
				model.PrimaryPart = p
			end
		end
		gathered = gathered + 1
	end
end

-- 2. hinges
local hinged = 0
local function pieceOf(p)
	local a = p.Parent
	while a and a ~= game do
		if LAB[a.Name] then
			return a.Name
		end
		a = a.Parent
	end
	return nil
end
for _, root in ipairs(targets) do
	for _, p in ipairs(root:GetDescendants()) do
		if p:IsA("MeshPart") then
			local piece = pieceOf(p)
			local offset = piece and PIVOTS[piece] and PIVOTS[piece][p.Name]
			if offset then
				p.PivotOffset = CFrame.new(offset)
				p.Anchored = true
				hinged = hinged + 1
			end
		end
	end
end

-- 3. glass and glow
local function isLab(p)
	if not everywhere then
		return true
	end
	local a = p.Parent
	while a and a ~= workspace do
		if LAB[a.Name] then
			return true
		end
		a = a.Parent
	end
	return false
end

local done = 0
for _, root in ipairs(targets) do
	local list = root:GetDescendants()
	if root:IsA("MeshPart") then
		table.insert(list, root)
	end
	for _, p in ipairs(list) do
		if p:IsA("MeshPart") then
			local _, partName = split(p.Name)
			local kind, colourWord = kindOf(partName)
			if kind and isLab(p) then
				local k = KINDS[kind]
				for _, c in ipairs(p:GetChildren()) do
					if c:IsA("SurfaceAppearance") or (c:IsA("PointLight") and c.Name == "LabLight") then
						c:Destroy()
					end
				end
				p.TextureID = ""
				p.CastShadow = false
				p:SetAttribute("LabGlow", true)
				local colour = COLOURS[colourWord] or k.colour
				if k.dim then
					colour = colour:Lerp(Color3.new(0, 0, 0), 1 - k.dim)
				end
				p.Color = colour
				if kind == "Glass" then
					p.Material = Enum.Material.Glass
					p.Transparency = 0.6
					p.Reflectance = 0.08
				else
					p.Material = Enum.Material.Neon
					p.Transparency = k.transparency
					if LIGHTS then
						local light = Instance.new("PointLight")
						light.Name = "LabLight"
						light.Color = COLOURS[colourWord] or k.colour
						local size = math.max(p.Size.X, p.Size.Y, p.Size.Z)
						light.Range = math.clamp(k.range * math.max(size / 4, 0.6), 4, 26)
						light.Brightness = k.brightness
						light.Shadows = SHADOWS and k.shadows
						light.Parent = p
					end
				end
				done = done + 1
			end
		end
	end
end

if recording then
	History:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(("SetupLabGlow: %d glass/glow parts set up, %d pieces gathered into models, %d hinges set"):format(done, gathered,
	hinged))
