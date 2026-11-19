-- SetupMansion
-- Finishes the imported mansion models (assets/Mansion) in Studio.
-- 1. Import the mansion FBX files (or Mansion_All.fbx) with the 3D Importer.
-- 2. Select the imported models (or nothing: then every mansion piece in the Workspace).
-- 3. Paste this into the Command Bar (View > Command Bar), press Enter.
--
-- Parts are recognised by their mesh names:
--   Glass...    -> old glass, see-through (clock, bookcase doors, the lamp chimney)
--   Crystal...  -> the chandelier's crystal drops: clear and sparkling
--   Flame...    -> candle flames: warm Neon, with a PointLight that casts shadows. Each light is
--                  tagged "CandleLight" so StarterPlayerScripts/CandleFlicker makes it flicker,
--                  and it remembers its brightness in the attributes BaseBrightness / BaseRange.
--   DoorLeft / DoorRight (Wardrobe) -> pivots put on their hinges: open one with a PivotTo.
-- Mansion_All.fbx imports every piece side by side with names like "Wardrobe_DoorLeft";
-- those get gathered into one Model per piece.

local CANDLE_COLOUR = Color3.fromRGB(255, 168, 82)
local CANDLE_RANGE = 12          -- studs, for one candle; a mesh of several flames gets more
local CANDLE_BRIGHTNESS = 1.1
local CANDLE_SHADOWS = true

-- each hinge from its mesh's box centre, in studs (written by the build - don't edit)
local PIVOTS = {
	Wardrobe = {DoorLeft = Vector3.new(-0.834, 0, -0.459), DoorRight = Vector3.new(0.945, 0, -0.054)},
}

local Selection = game:GetService("Selection")
local History = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")

local MANSION = {}
for _, n in ipairs({"FourPosterBed", "Wardrobe", "WingbackArmchair", "SheetedSofa", "DiningTable", "DiningChair",
	"UprightPiano", "GrandfatherClock", "WritingDesk", "Bookcase", "RockingChair", "VanityDresser", "Candelabra",
	"Chandelier", "PortraitPainting", "ManorPainting", "StandingMirror", "PersianRug", "Gramophone",
	"DeadFlowerVase"}) do
	MANSION[n] = true
end

local targets = Selection:Get()
local everywhere = #targets == 0
if everywhere then
	targets = {workspace}
end
local recording = History:TryBeginRecording("SetupMansion")

local function split(name)
	local piece, part = name:match("^(.-)_([%w]+)$")
	if piece and piece ~= "" then
		return piece, part
	end
	return nil, name
end

local function pieceOf(p)
	local a = p.Parent
	while a and a ~= game do
		if MANSION[a.Name] then
			return a.Name
		end
		a = a.Parent
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
			if piece and MANSION[piece] and not (d.Parent:IsA("Model") and d.Parent.Name == piece) then
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

-- 2. hinges, glass, crystal, flames
local hinged, glass, flames = 0, 0, 0
local function clearLook(p)
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("SurfaceAppearance") or (c:IsA("PointLight") and c.Name == "CandleLight") then
			c:Destroy()
		end
	end
	p.TextureID = ""
end

for _, root in ipairs(targets) do
	local list = root:GetDescendants()
	for _, p in ipairs(list) do
		if p:IsA("MeshPart") then
			local piece = pieceOf(p)
			local _, name = split(p.Name)
			if piece or not everywhere then
				local offset = piece and PIVOTS[piece] and PIVOTS[piece][name]
				if offset then
					p.PivotOffset = CFrame.new(offset)
					p.Anchored = true
					hinged = hinged + 1
				end
				if name:sub(1, 5) == "Glass" then
					clearLook(p)
					p.Material = Enum.Material.Glass
					p.Color = Color3.fromRGB(176, 186, 180)
					p.Transparency = 0.55
					p.Reflectance = 0.1
					p.CastShadow = false
					glass = glass + 1
				elseif name:sub(1, 7) == "Crystal" then
					clearLook(p)
					p.Material = Enum.Material.Glass
					p.Color = Color3.fromRGB(232, 240, 242)
					p.Transparency = 0.3
					p.Reflectance = 0.3
					p.CastShadow = false
					glass = glass + 1
				elseif name:sub(1, 5) == "Flame" then
					clearLook(p)
					p.Material = Enum.Material.Neon
					p.Color = CANDLE_COLOUR
					p.Transparency = 0.1
					p.CastShadow = false
					p.CanCollide = false
					local light = Instance.new("PointLight")
					light.Name = "CandleLight"
					light.Color = CANDLE_COLOUR
					local spread = math.max(p.Size.X, p.Size.Z)
					light.Range = math.clamp(CANDLE_RANGE + spread * 2, 8, 30)
					light.Brightness = CANDLE_BRIGHTNESS
					light.Shadows = CANDLE_SHADOWS
					light:SetAttribute("BaseBrightness", light.Brightness)
					light:SetAttribute("BaseRange", light.Range)
					light.Parent = p
					CollectionService:AddTag(light, "CandleLight")
					flames = flames + 1
				end
			end
		end
	end
end

if recording then
	History:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(("SetupMansion: %d pieces gathered, %d hinges set, %d glass/crystal parts, %d candle flames lit"):format(
	gathered, hinged, glass, flames))
