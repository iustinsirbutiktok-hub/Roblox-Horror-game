-- HudSystem
-- Place in: ServerScriptService (it moves itself there if dropped anywhere
-- else). The HUD client script is inside it.
--
-- The 3-slot inventory. Each slot holds one KIND of item; items of the same
-- kind stack in their slot (up to the limits your pickup systems already
-- use). The counts themselves stay where they always were (the player's
-- Bandages / Adrenaline / Batteries / KeycardLevel attributes) - this script
-- just keeps track of which slot each kind sits in:
--   player attributes Slot1, Slot2, Slot3 = "Bandage" / "Adrenaline" / "Battery" / "Keycard" / ""
--
-- Pickup scripts ask before handing something over:
--   ReplicatedStorage > Inventory > CanCarry  (BindableFunction, server only)
--   CanCarry:Invoke(player, "Battery") -> true / false
--
-- Q (on the client) drops one of the selected item on the floor, as a pickup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

if script.Parent ~= ServerScriptService then
	script.Parent = ServerScriptService
end

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local MAX_SLOTS = 3

-- item kind -> the attribute that holds how many you carry
local KINDS = {
	Bandage = { attribute = "Bandages" },
	Adrenaline = { attribute = "Adrenaline" },
	Battery = { attribute = "Batteries" },
	Keycard = { attribute = "KeycardLevel" },   -- a level, not a count: one card
}
local ORDER = { "Bandage", "Adrenaline", "Battery", "Keycard" }

--------------------------------------------------
-- SHARED
--------------------------------------------------

local folder = ReplicatedStorage:FindFirstChild("Inventory") or Instance.new("Folder")
folder.Name = "Inventory"
folder.Parent = ReplicatedStorage
folder:SetAttribute("MaxSlots", MAX_SLOTS)

local event = folder:FindFirstChild("InventoryEvent") or Instance.new("RemoteEvent")
event.Name = "InventoryEvent"
event.Parent = folder

local canCarry = folder:FindFirstChild("CanCarry") or Instance.new("BindableFunction")
canCarry.Name = "CanCarry"
canCarry.Parent = folder

local clientTemplate = script:WaitForChild("HudClient")

--------------------------------------------------
-- SLOTS
--------------------------------------------------

local function amount(player, kind)
	local value = player:GetAttribute(KINDS[kind].attribute) or 0
	if kind == "Keycard" then
		return value > 0 and 1 or 0
	end
	return value
end

local function slotOf(player, kind)
	for i = 1, MAX_SLOTS do
		if player:GetAttribute("Slot" .. i) == kind then
			return i
		end
	end
	return nil
end

local function emptySlot(player)
	for i = 1, MAX_SLOTS do
		if (player:GetAttribute("Slot" .. i) or "") == "" then
			return i
		end
	end
	return nil
end

-- keep the slots in step with what the player actually carries
local function sync(player, kind)
	local has = amount(player, kind) > 0
	local slot = slotOf(player, kind)
	if has and not slot then
		local free = emptySlot(player)
		if free then
			player:SetAttribute("Slot" .. free, kind)
		end
	elseif not has and slot then
		player:SetAttribute("Slot" .. slot, "")
	end
end

canCarry.OnInvoke = function(player, kind)
	if not KINDS[kind] then
		return true
	end
	if slotOf(player, kind) then
		return true             -- stacks onto the slot it already has
	end
	if emptySlot(player) then
		return true
	end
	event:FireClient(player, "Full")
	return false
end

--------------------------------------------------
-- DROPPING (Q)
--------------------------------------------------

-- the world model each kind drops as (the pickup scripts recognise them by name)
local function dropModel(kind, player)
	if kind == "Bandage" or kind == "Adrenaline" then
		local medical = ReplicatedStorage:FindFirstChild("Medical")
		local templates = medical and medical:FindFirstChild("Templates")
		local name = kind == "Bandage" and "itemBandage" or "adrenaline_shot"
		local template = templates and templates:FindFirstChild(name)
		return template and template:Clone()
	elseif kind == "Battery" then
		-- dropped as a camcorder battery you can pick back up
		local camcorder = ReplicatedStorage:FindFirstChild("CamcorderAssets")
		local headlamp = ReplicatedStorage:FindFirstChild("Headlamp")
		local template = (camcorder and camcorder:FindFirstChild("Battery")) or (headlamp and headlamp:FindFirstChild("HandBattery"))
		if template then
			local model = template:Clone()
			model.Name = "CamcorderBattery"
			return model
		end
	elseif kind == "Keycard" then
		local keycard = ReplicatedStorage:FindFirstChild("Keycard")
		local template = keycard and keycard:FindFirstChild("CardTemplate")
		if template then
			local model = template:Clone()
			model.Name = "Keycard"
			model:SetAttribute("Level", player:GetAttribute("KeycardLevel") or 1)
			-- lying flat
			model:PivotTo(model:GetPivot() * CFrame.Angles(math.rad(-90), 0, 0))
			return model
		end
	end
	return nil
end

event.OnServerEvent:Connect(function(player, action, slot)
	if action ~= "Drop" or type(slot) ~= "number" then
		return
	end
	local kind = player:GetAttribute("Slot" .. math.floor(slot))
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not kind or kind == "" or not KINDS[kind] or not root then
		return
	end
	if character:GetAttribute("UsingMedical") or character:GetAttribute("UsingHeadlamp") or character:GetAttribute("Downed") then
		return
	end

	local model = dropModel(kind, player)
	local attribute = KINDS[kind].attribute
	if kind == "Keycard" then
		player:SetAttribute(attribute, 0)
	else
		player:SetAttribute(attribute, math.max(0, (player:GetAttribute(attribute) or 0) - 1))
	end

	if model then
		-- on the floor just in front of you
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
		local spot = root.Position + look * 2
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(spot + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
		local floorY = hit and hit.Position.Y or (root.Position.Y - 3)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		local _, size = model:GetBoundingBox()
		model:PivotTo(CFrame.new(spot.X, floorY + size.Y / 2 + 0.02, spot.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
			* model:GetPivot().Rotation)
		model.Parent = workspace
	end
	event:FireClient(player, "Dropped", kind)
end)

--------------------------------------------------
-- PLAYERS
--------------------------------------------------

local function setup(player)
	for i = 1, MAX_SLOTS do
		if player:GetAttribute("Slot" .. i) == nil then
			player:SetAttribute("Slot" .. i, "")
		end
	end
	for _, kind in ipairs(ORDER) do
		sync(player, kind)
		player:GetAttributeChangedSignal(KINDS[kind].attribute):Connect(function()
			sync(player, kind)
		end)
	end

	local playerGui = player:WaitForChild("PlayerGui", 20)
	if playerGui and not playerGui:FindFirstChild("HudHolder") then
		local holder = Instance.new("ScreenGui")
		holder.Name = "HudHolder"
		holder.ResetOnSpawn = false
		holder.Parent = playerGui
		local client = clientTemplate:Clone()
		client.Disabled = false
		client.Parent = holder
	end
end

Players.PlayerAdded:Connect(setup)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setup, player)
end
