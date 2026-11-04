-- PlaceHollowProps
-- Run in Studio's Command Bar after importing the asylum FBX furniture into
-- ServerStorage.AsylumProps (each Model / MeshPart named like its file:
-- HospitalBed, Wheelchair, Gurney, ...). It puts every piece on its spot in
-- HollowWard, turned the right way and resting exactly on the floor (or hung
-- from the ceiling), replacing the grey stand-ins. Safe to run again.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ward = Workspace:FindFirstChild("HollowWard")
assert(ward, "Build the ward first (BuildHollowWard)")
local spots = ward:FindFirstChild("PropSpots")

local function folder(name)
	local f = ward:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = ward
	end
	return f
end

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function placeProps()
	local source = ServerStorage:FindFirstChild("AsylumProps")
	local props = ward:FindFirstChild("Props") or folder("Props")
	props:ClearAllChildren()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ward:FindFirstChild("Rooms") }
	local missing = {}
	for _, s in ipairs(spots:GetChildren()) do
		local name = s:GetAttribute("Prop")
		local template = source and source:FindFirstChild(name)
		local obj
		if template then
			obj = template:Clone()
		else
			missing[name] = true
			obj = Instance.new("Model")
			part({ Name = "StandIn", Size = Vector3.new(2, 2, 2), Color = rgb(120, 120, 120), Transparency = 0.4, CFrame = CFrame.new() }, obj)
		end
		obj.Name = name
		if obj:IsA("BasePart") then
			local m = Instance.new("Model")
			obj.Parent = m
			m.Name = name
			obj = m
		end
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		obj:SetAttribute("Spot", s:GetFullName())
		obj:SetAttribute("Patient", s:GetAttribute("Patient"))
		obj:SetAttribute("Room", s:GetAttribute("Room"))
		obj.Parent = props
		local _, size = obj:GetBoundingBox()
		obj:PivotTo(s.CFrame * CFrame.new(0, 5, 0))
		local cf2, size2 = obj:GetBoundingBox()
		if s:GetAttribute("Ceiling") then
			-- hangs from the ceiling: its top against it
			local hit = Workspace:Raycast(s.Position + Vector3.new(0, 2, 0), Vector3.new(0, 30, 0), params)
			if hit then
				obj:PivotTo(obj:GetPivot() + Vector3.new(0, hit.Position.Y - (cf2.Position.Y + size2.Y / 2), 0))
			end
		else
			-- stands on the floor: its lowest point exactly on it
			local hit = Workspace:Raycast(s.Position + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
			local floorY = hit and hit.Position.Y or s.Position.Y - 0.1
			obj:PivotTo(obj:GetPivot() + Vector3.new(0, floorY - (cf2.Position.Y - size2.Y / 2), 0))
		end
		_ = size
	end
	local list = {}
	for n in pairs(missing) do
		table.insert(list, n)
	end
	if #list > 0 then
		warn("HollowWard: stand-ins for " .. table.concat(list, ", ") .. " (import those FBX into ServerStorage.AsylumProps, then run PlaceHollowProps)")
	end
end
placeProps()
print("PlaceHollowProps: done")
