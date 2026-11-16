-- RigAsylumPatient
-- 1. Drag AsylumPatient.fbx into Studio and import it.
-- 2. Select the imported model, paste this into the Command Bar (View > Command Bar), press Enter.
-- It becomes a real R6 character: HumanoidRootPart, Humanoid (R6), and the six
-- standard joints (RootJoint, Neck, Right/Left Shoulder, Right/Left Hip) with
-- the standard R6 orientations, so default R6 animations and the Hollow Ward
-- scripts move it. The parts are renamed to R6 names (Torso, Head, Right Arm, ...).
-- The finished rig goes to ServerStorage as "AsylumPatient" (the HollowWardBlitz
-- uses it for the patients when it's there). Ctrl+Z undoes it.

local MOVE_TO_SERVERSTORAGE = true

local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local History = game:GetService("ChangeHistoryService")

local model = Selection:Get()[1]
assert(model and model:IsA("Model"), "Select the imported AsylumPatient model first")

-- where everything sits on the R6 frame (studs; Roblox axes: Y up, the character faces -Z)
local R6 = {
	Root = Vector3.new(0, 3, 0),
	Neck = Vector3.new(0, 4.05, 0),
	RightShoulder = Vector3.new(1.04, 3.62, 0),
	LeftShoulder = Vector3.new(-1.04, 3.62, 0),
	RightHip = Vector3.new(0.43, 2.0, 0),
	LeftHip = Vector3.new(-0.43, 2.0, 0),
}
-- the torso mesh, as exported: the middle of its bounds, its origin, and its height
local TORSO_BOUNDS_CENTRE = Vector3.new(0.002, 3.021, 0.006)
local TORSO_ORIGIN = Vector3.new(0, 3, 0)
local TORSO_HEIGHT = 2.352
local HEAD_BOUNDS_CENTRE = Vector3.new(0, 4.6, -0.064)
local HEAD_ORIGIN = Vector3.new(0, 4.5, 0)

local function key(s)
	return (string.gsub(string.lower(s), "%W", ""))
end

local function find(name)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and key(d.Name) == key(name) then
			return d
		end
	end
end

local recording = History:TryBeginRecording("RigAsylumPatient")

local parts = {
	Torso = find("Torso"), Head = find("Head"),
	["Right Arm"] = find("RightArm"), ["Left Arm"] = find("LeftArm"),
	["Right Leg"] = find("RightLeg"), ["Left Leg"] = find("LeftLeg"),
}
for name, p in pairs(parts) do
	assert(p, "Couldn't find the " .. name .. " part in the selected model")
end
local torso, head = parts.Torso, parts.Head

-- Studio places an imported MeshPart either at the middle of its mesh or at its
-- origin: tell which from where the head sits above the torso, and the scale from the torso's height
local k = torso.Size.Y / TORSO_HEIGHT
local rel = torso.CFrame:PointToObjectSpace(head.Position) / k
local byBounds = (rel - (HEAD_BOUNDS_CENTRE - TORSO_BOUNDS_CENTRE)).Magnitude
local byOrigin = (rel - (HEAD_ORIGIN - TORSO_ORIGIN)).Magnitude
local TC = byBounds <= byOrigin and TORSO_BOUNDS_CENTRE or TORSO_ORIGIN

local function at(p)
	return torso.CFrame * CFrame.new((p - TC) * k)
end

-- tidy: every part straight in the model, R6 names, nothing anchored or stuck
for name, p in pairs(parts) do
	p.Name = name
	p.Parent = model
	p.Anchored = false
	p.CanCollide = (name == "Torso" or name == "Head")
	p.Massless = false
end
for _, d in ipairs(model:GetChildren()) do
	if d:IsA("Model") and #d:GetChildren() == 0 then
		d:Destroy()
	end
end
for _, d in ipairs(model:GetDescendants()) do
	if d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("Humanoid") or d.Name == "HumanoidRootPart" then
		d:Destroy()
	end
end

local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1) * k
root.Transparency = 1
root.CanCollide = false
root.CFrame = at(R6.Root)
root.Parent = model
model.PrimaryPart = root

local function joint(name, p0, p1, where, rot)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	local cf = at(where) * rot
	m.C0 = p0.CFrame:ToObjectSpace(cf)
	m.C1 = p1.CFrame:ToObjectSpace(cf)
	m.Parent = p0
	return m
end

local ROOT_ROT = CFrame.Angles(-math.pi / 2, 0, math.pi)
joint("RootJoint", root, torso, R6.Root, ROOT_ROT)
joint("Neck", torso, head, R6.Neck, ROOT_ROT)
joint("Right Shoulder", torso, parts["Right Arm"], R6.RightShoulder, CFrame.Angles(0, math.pi / 2, 0))
joint("Left Shoulder", torso, parts["Left Arm"], R6.LeftShoulder, CFrame.Angles(0, -math.pi / 2, 0))
joint("Right Hip", torso, parts["Right Leg"], R6.RightHip, CFrame.Angles(0, math.pi / 2, 0))
joint("Left Hip", torso, parts["Left Leg"], R6.LeftHip, CFrame.Angles(0, -math.pi / 2, 0))

local humanoid = Instance.new("Humanoid")
humanoid.RigType = Enum.HumanoidRigType.R6
humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
humanoid.Parent = model
Instance.new("Animator").Parent = humanoid

model.Name = "AsylumPatient"
model:SetAttribute("AsylumPatient", true)
if MOVE_TO_SERVERSTORAGE then
	model.Parent = ServerStorage
end
if recording then
	History:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(("RigAsylumPatient: done (%s, scale %.2f) -> %s"):format(TC == TORSO_ORIGIN and "origin" or "bounds", k,
	model:GetFullName()))
