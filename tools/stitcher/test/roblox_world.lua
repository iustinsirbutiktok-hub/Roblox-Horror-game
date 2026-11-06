-- Just enough of Roblox's instance tree and services to run StitcherAnimator
-- outside Studio (on top of roblox_mock.lua): Models, parts, Bones (with
-- CFrame / Transform / WorldCFrame), attributes, Players, RunService,
-- task.defer/delay, require.

local Instance = {}
Instance.__index = Instance
local CLASSES = {
	Model = { "Model", "PVInstance", "Instance" },
	MeshPart = { "MeshPart", "BasePart", "PVInstance", "Instance" },
	Part = { "Part", "BasePart", "PVInstance", "Instance" },
	Bone = { "Bone", "Attachment", "Instance" },
	Humanoid = { "Humanoid", "Instance" },
	Sound = { "Sound", "Instance" },
	ModuleScript = { "ModuleScript", "Instance" },
	Folder = { "Folder", "Instance" },
}

local function signal()
	local s = { fns = {} }
	function s:Connect(fn)
		table.insert(self.fns, fn)
		return { Disconnect = function() end }
	end
	function s:Fire(...)
		for _, fn in ipairs(self.fns) do fn(...) end
	end
	return s
end

function NewInstance(class, name, parent)
	local self = setmetatable({ ClassName = class, Name = name or class, children = {}, attrs = {},
		AncestryChanged = signal() }, Instance)
	if class == "Bone" then
		self.CFrame = CFrame.new()
		self.Transform = CFrame.new()
	elseif CLASSES[class][2] == "BasePart" then
		self.CFrame = CFrame.new()
	end
	if parent then
		self:SetParent(parent)
	end
	return self
end

function Instance:SetParent(p)
	self.Parent = p
	table.insert(p.children, self)
end
function Instance:IsA(c)
	for _, k in ipairs(CLASSES[self.ClassName]) do
		if k == c then return true end
	end
	return false
end
function Instance:GetChildren() return self.children end
function Instance:GetDescendants()
	local out = {}
	local function walk(n)
		for _, c in ipairs(n.children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Instance:FindFirstChild(name, recursive)
	local list = recursive and self:GetDescendants() or self.children
	for _, c in ipairs(list) do
		if c.Name == name then return c end
	end
	return nil
end
function Instance:FindFirstChildWhichIsA(class, recursive)
	local list = recursive and self:GetDescendants() or self.children
	for _, c in ipairs(list) do
		if c:IsA(class) then return c end
	end
	return nil
end
function Instance:FindFirstChildOfClass(class)
	for _, c in ipairs(self.children) do
		if c.ClassName == class then return c end
	end
	return nil
end
function Instance:WaitForChild(name) return assert(self:FindFirstChild(name), "WaitForChild: no " .. name) end
function Instance:GetFullName()
	local n, s = self, self.Name
	while n.Parent and n.Parent.Name ~= "game" do
		n = n.Parent
		s = n.Name .. "." .. s
	end
	return s
end
function Instance:GetAttribute(k) return self.attrs[k] end
function Instance:SetAttribute(k, v) self.attrs[k] = v end

-- world placement: a bone hangs off its parent bone (or the part it's in)
local function parentWorld(inst, transformed)
	local p = inst.Parent
	if p.ClassName == "Bone" then
		return BoneWorld(p, transformed)
	end
	return p.CFrame
end
function BoneWorld(b, transformed)
	local w = parentWorld(b, transformed) * b.CFrame
	if transformed then
		w = w * b.Transform
	end
	return w
end
local oldIndex = Instance.__index
Instance.__index = function(self, k)
	if self.ClassName == "Bone" then
		if k == "WorldCFrame" then return BoneWorld(self, false) end
		if k == "WorldPosition" then return BoneWorld(self, false).Position end
		if k == "TransformedWorldCFrame" then return BoneWorld(self, true) end
	end
	if k == "Position" and rawget(self, "CFrame") then
		return rawget(self, "CFrame").Position
	end
	if k == "PrimaryPart" then return nil end
	return oldIndex[k]
end

-- models: the bounding box and pivot come from the parts in them
function Instance:GetBoundingBox()
	return self.box, self.boxSize
end
function Instance:GetPivot()
	local part = self:FindFirstChildWhichIsA("BasePart", true)
	return part.CFrame
end
function Instance:PivotTo(cf)
	local part = self:FindFirstChildWhichIsA("BasePart", true)
	local delta = cf * part.CFrame:Inverse()
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	self.box = delta * self.box
end
function Instance:Play() self.played = (self.played or 0) + 1 end

game = NewInstance("Folder", "game")
workspace = NewInstance("Folder", "Workspace", game)
workspace.DescendantAdded = signal()
workspace.CurrentCamera = { CFrame = CFrame.new(0, 5, -15) }
local ReplicatedStorage = NewInstance("Folder", "ReplicatedStorage", game)
local RunService = { RenderStepped = signal(), Heartbeat = signal() }
local Players = { list = {} }
function Players:GetPlayers() return self.list end
function Players:GetPlayerByUserId(id)
	for _, p in ipairs(self.list) do
		if p.UserId == id then return p end
	end
	return nil
end
local SERVICES = { Players = Players, ReplicatedStorage = ReplicatedStorage, RunService = RunService }
function game:GetService(name) return assert(SERVICES[name], "no service " .. name) end

MODULES = {}
function require(m)
	return assert(MODULES[m], "require: unknown module")
end

local queue = {}
task = {
	defer = function(fn, ...) table.insert(queue, { fn, { ... } }) end,
	delay = function(_, fn, ...) table.insert(queue, { fn, { ... } }) end,
	wait = function() end,
}
function RunQueue()
	while #queue > 0 do
		local job = table.remove(queue, 1)
		job[1](unpack(job[2]))
	end
end
function warn(...) print("WARN", ...) end
local clock = 0
os.clock = function() return clock end
function Advance(dt) clock = clock + dt; RunService.RenderStepped:Fire(dt) end

function AddPlayer(userId, headPos)
	local character = NewInstance("Model", "Character")
	local head = NewInstance("Part", "Head", character)
	head.CFrame = CFrame.new(headPos[1], headPos[2], headPos[3])
	local hum = NewInstance("Humanoid", "Humanoid", character)
	hum.Health = 100
	table.insert(Players.list, { UserId = userId, Character = character })
	return head
end
