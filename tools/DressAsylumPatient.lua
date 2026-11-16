-- DressAsylumPatient
-- Makes a classic blocky R6 asylum patient.
-- 1. Upload PatientShirt.png, PatientPants.png and PatientFace.png (assets/AsylumPatientR6)
--    in the Asset Manager (Images) and paste their IDs below.
-- 2. Avatar tab > Rig Builder > R6 > Block Rig (or select any R6 character model).
-- 3. Select the rig, paste this into the Command Bar (View > Command Bar), press Enter.
-- It gets the gown (Shirt + Pants), the terrified face, pale starved skin, and goes to
-- ServerStorage as "AsylumPatient" - the HollowWardBlitz uses it for its patients.

local SHIRT = "rbxassetid://0"   -- PatientShirt.png
local PANTS = "rbxassetid://0"   -- PatientPants.png
local FACE = "rbxassetid://0"    -- PatientFace.png
local MOVE_TO_SERVERSTORAGE = true

local SKIN = Color3.fromRGB(180, 164, 145)     -- matches the skin painted on the arms and legs

local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local History = game:GetService("ChangeHistoryService")

local model = Selection:Get()[1]
assert(model and model:IsA("Model") and model:FindFirstChild("Torso") and model:FindFirstChildOfClass("Humanoid"),
	"Select an R6 rig first (Avatar > Rig Builder > R6 > Block Rig)")
local recording = History:TryBeginRecording("DressAsylumPatient")

for _, d in ipairs(model:GetDescendants()) do
	if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("Accessory") or d:IsA("BodyColors")
		or (d:IsA("Decal") and d.Name == "face") then
		d:Destroy()
	end
end
local shirt = Instance.new("Shirt")
shirt.ShirtTemplate = SHIRT
shirt.Parent = model
local pants = Instance.new("Pants")
pants.PantsTemplate = PANTS
pants.Parent = model
local colours = Instance.new("BodyColors")
colours.HeadColor3, colours.TorsoColor3 = SKIN, SKIN
colours.LeftArmColor3, colours.RightArmColor3, colours.LeftLegColor3, colours.RightLegColor3 = SKIN, SKIN, SKIN, SKIN
colours.Parent = model
local face = Instance.new("Decal")
face.Name = "face"
face.Face = Enum.NormalId.Front
face.Texture = FACE
face.Parent = model.Head

local h = model:FindFirstChildOfClass("Humanoid")
h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
model.Name = "AsylumPatient"
model:SetAttribute("AsylumPatient", true)
if MOVE_TO_SERVERSTORAGE then
	model.Parent = ServerStorage
end
if recording then
	History:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print("DressAsylumPatient: done -> " .. model:GetFullName())
