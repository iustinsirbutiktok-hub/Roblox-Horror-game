-- HudClient
-- Lives inside HudSystem; the server gives each player a copy.
--
-- Bottom centre of the screen:
--   ADRENALINE  a thin glowing orange line while a shot is working, draining
--               to nothing (blinks for the last 3 seconds)
--   HEALTH      dark red bar; a pale "damage chip" trails behind when you're
--               hit; pulses under 25%; flashes DOWN when you're downed
--   STAMINA     sprinting drains it, resting brings it back; run it dry and
--               you can only walk until you catch your breath. Fades out
--               when full. (Adrenaline: no drain while it lasts.)
--   3 SLOTS     1/2/3 or the mouse wheel to switch, Q drops one of the
--               selected item. Each slot shows the item turning slowly.
--
-- Also switches off Roblox's own health bar and backpack.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local folder = ReplicatedStorage:WaitForChild("Inventory")
local event = folder:WaitForChild("InventoryEvent")
local MAX_SLOTS = folder:GetAttribute("MaxSlots") or 3

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local STAMINA_MAX = 100
local STAMINA_DRAIN = 16          -- per second while sprinting (about 6 seconds from full)
local STAMINA_REGEN = 22          -- per second while resting
local REGEN_DELAY = 0.9           -- seconds after you stop sprinting before it comes back
local RECOVER_AT = 35             -- out of breath until stamina climbs back to this
local WALK_SPEED = 8              -- your camera script's walking speed

local DROP_KEY = Enum.KeyCode.Q
local SLOT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }

local FONT = Enum.Font.SpecialElite
local BONE = Color3.fromRGB(214, 204, 186)
local BLOOD = Color3.fromRGB(150, 16, 14)
local ORANGE = Color3.fromRGB(255, 142, 32)

-- how each item is named and used
local ITEMS = {
	Bandage = { name = "Bandage", use = "[F] wrap" },
	Adrenaline = { name = "Adrenaline", use = "[G] inject" },
	Battery = { name = "Camcorder batteries", use = "[R] swap" },
	Keycard = { name = "Keycard", use = "swipe at a reader" },
}
local COUNT_ATTRIBUTE = { Bandage = "Bandages", Adrenaline = "Adrenaline", Battery = "Batteries", Keycard = "KeycardLevel" }

-- Roblox's own health bar and hotbar give way to this one
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

--------------------------------------------------
-- BUILDING THE HUD
--------------------------------------------------

local function new(class, props, parent)
	local obj = Instance.new(class)
	for k, v in pairs(props) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

local function corner(parent, r)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

-- (above the camcorder's viewfinder, so it shows through it)
local gui = new("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 45 },
	player:WaitForChild("PlayerGui"))

-- the item slots (and the item name above them) sit at the bottom centre
local root = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(320, 82),
	BackgroundTransparency = 1,
}, gui)

-- health, stamina and the adrenaline line sit in the bottom-left corner
local vitals = new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 14, 1, -22),
	Size = UDim2.fromOffset(320, 72),
	BackgroundTransparency = 1,
}, gui)

local function smallLabel(text, y, colour)
	return new("TextLabel", {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(160, 12),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = colour,
		TextTransparency = 0.35,
		Text = text,
	}, vitals)
end

local function bar(y, height)
	local back = new("Frame", {
		Position = UDim2.fromOffset(10, y),
		Size = UDim2.fromOffset(300, height),
		BackgroundColor3 = Color3.fromRGB(8, 7, 7),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, vitals)
	corner(back, 2)
	new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1, Transparency = 0.3 }, back)
	return back
end

-- ADRENALINE: a thin orange line
local adrLabel = smallLabel("ADRENALINE", 0, ORANGE)
adrLabel.Position = UDim2.fromOffset(12, 0)
local adrBack = bar(13, 3)
local adrFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = ORANGE, BorderSizePixel = 0 }, adrBack)
local adrGlow = new("UIStroke", { Color = ORANGE, Thickness = 2, Transparency = 0.5 }, adrFill)
adrLabel.TextTransparency = 1
adrBack.Visible = false

-- HEALTH
local hpLabel = smallLabel("HEALTH", 22, BONE)
hpLabel.Position = UDim2.fromOffset(12, 22)
local hpBack = bar(35, 12)
local hpChip = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(210, 190, 170), BorderSizePixel = 0 }, hpBack)
local hpFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2 }, hpBack)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(196, 34, 28)),
		ColorSequenceKeypoint.new(0.5, BLOOD),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 6, 6)),
	}),
}, hpFill)
-- quarter marks, like notches on a gauge
for _, x in ipairs({ 0.25, 0.5, 0.75 }) do
	new("Frame", {
		Position = UDim2.new(x, 0, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, hpBack)
end
local downText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 70, 50),
	TextStrokeTransparency = 0.4,
	Text = "DOWN",
	Visible = false,
	ZIndex = 4,
}, hpBack)

-- STAMINA
local stLabel = smallLabel("STAMINA", 50, BONE)
stLabel.Position = UDim2.fromOffset(12, 50)
local stBack = bar(63, 5)
local stStroke = stBack:FindFirstChildOfClass("UIStroke")
local stFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BONE, BorderSizePixel = 0 }, stBack)

-- item name that shows when you switch or pick something up
local itemName = new("TextLabel", {
	Position = UDim2.fromOffset(0, 2),
	Size = UDim2.fromOffset(320, 16),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 15,
	TextColor3 = BONE,
	TextStrokeTransparency = 0.5,
	TextTransparency = 1,
	TextStrokeColor3 = Color3.new(0, 0, 0),
	Text = "",
}, root)

--------------------------------------------------
-- THE THREE SLOTS
--------------------------------------------------

local SLOT = 60
local GAP = 10
local slots = {}
local rowWidth = MAX_SLOTS * SLOT + (MAX_SLOTS - 1) * GAP
for i = 1, MAX_SLOTS do
	local x = (320 - rowWidth) / 2 + (i - 1) * (SLOT + GAP)
	local frame = new("Frame", {
		Position = UDim2.fromOffset(x, 20),
		Size = UDim2.fromOffset(SLOT, SLOT),
		BackgroundColor3 = Color3.fromRGB(14, 13, 12),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, root)
	corner(frame, 4)
	local rim = new("UIStroke", { Color = Color3.fromRGB(60, 58, 54), Thickness = 1.5, Transparency = 0.2 }, frame)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150)),
	}, frame)
	local view = new("ViewportFrame", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 146, 140),
		LightColor = Color3.fromRGB(255, 240, 220),
		LightDirection = Vector3.new(-1, -1.5, -1),
	}, frame)
	local camera = new("Camera", { FieldOfView = 28 }, view)
	view.CurrentCamera = camera
	local number = new("TextLabel", {
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 13,
		TextColor3 = BONE,
		TextTransparency = 0.45,
		Text = tostring(i),
		ZIndex = 3,
	}, frame)
	local count = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -2),
		Size = UDim2.fromOffset(30, 14),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = BONE,
		TextStrokeTransparency = 0.5,
		Text = "",
		ZIndex = 3,
	}, frame)
	local fallback = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 12,
		TextWrapped = true,
		TextColor3 = BONE,
		TextTransparency = 0.3,
		Text = "",
		ZIndex = 2,
	}, frame)
	slots[i] = { frame = frame, rim = rim, view = view, camera = camera, count = count, number = number,
		fallback = fallback, kind = "", model = nil, spin = math.random() * 6, baseY = 20 }
end

--------------------------------------------------
-- ITEM MODELS IN THE SLOTS
--------------------------------------------------

local LEVEL_COLOURS = { Color3.fromRGB(40, 110, 220), Color3.fromRGB(230, 188, 36), Color3.fromRGB(200, 40, 36) }

local function itemTemplate(kind)
	if kind == "Bandage" or kind == "Adrenaline" then
		local medical = ReplicatedStorage:FindFirstChild("Medical")
		local templates = medical and medical:FindFirstChild("Templates")
		return templates and templates:FindFirstChild(kind == "Bandage" and "itemBandage" or "adrenaline_shot")
	elseif kind == "Battery" then
		-- the camcorder's battery pack (the old headlamp one as a fallback)
		local camcorder = ReplicatedStorage:FindFirstChild("CamcorderAssets")
		local headlamp = ReplicatedStorage:FindFirstChild("Headlamp")
		return (camcorder and camcorder:FindFirstChild("Battery")) or (headlamp and headlamp:FindFirstChild("HandBattery"))
	elseif kind == "Keycard" then
		local keycard = ReplicatedStorage:FindFirstChild("Keycard")
		return keycard and keycard:FindFirstChild("CardTemplate")
	end
	return nil
end

local function showItem(slot, kind)
	if slot.model then
		slot.model:Destroy()
		slot.model = nil
	end
	slot.kind = kind
	slot.fallback.Text = ""
	if kind == "" then
		return
	end
	local template = itemTemplate(kind)
	if not template then
		slot.fallback.Text = ITEMS[kind] and ITEMS[kind].name or kind
		return
	end
	local model = template:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("Light") then
			d:Destroy()
		end
	end
	if kind == "Keycard" then
		local level = player:GetAttribute("KeycardLevel") or 1
		local stripe = model:FindFirstChild("Stripe", true)
		if stripe then
			stripe.Color = LEVEL_COLOURS[level] or LEVEL_COLOURS[1]
		end
	end
	-- centre it on the origin so the camera can orbit it
	if model:IsA("Model") then
		local box = model:GetBoundingBox()
		model:PivotTo(box:Inverse() * model:GetPivot())
	elseif model:IsA("BasePart") then
		model.CFrame = model.CFrame.Rotation
	end
	model.Parent = slot.view
	slot.model = model
	local size = model:IsA("Model") and select(2, model:GetBoundingBox()) or model.Size
	slot.distance = size.Magnitude * 1.9 + 0.2
end

--------------------------------------------------
-- SLOTS FOLLOW THE SERVER; SELECTION IS YOURS
--------------------------------------------------

local selected = 1
local nameToken = 0

local function flashName(text)
	nameToken += 1
	local mine = nameToken
	itemName.Text = text
	itemName.TextTransparency = 0.05
	itemName.TextStrokeTransparency = 0.5
	task.delay(2.2, function()
		if nameToken == mine then
			TweenService:Create(itemName, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local function describe(i)
	local kind = slots[i].kind
	if kind == "" then
		return "empty"
	end
	local info = ITEMS[kind]
	return info.name .. "   " .. info.use
end

local function refreshSelection(announce)
	for i, slot in ipairs(slots) do
		local on = i == selected
		TweenService:Create(slot.frame, TweenInfo.new(0.15), {
			Position = UDim2.fromOffset(slot.frame.Position.X.Offset, on and slot.baseY - 5 or slot.baseY),
			BackgroundTransparency = on and 0.1 or 0.25,
		}):Play()
		slot.rim.Color = on and Color3.fromRGB(226, 216, 196) or Color3.fromRGB(60, 58, 54)
		slot.rim.Thickness = on and 2 or 1.5
		slot.number.TextTransparency = on and 0.05 or 0.45
	end
	if announce then
		flashName(describe(selected))
	end
end

local function refreshCounts()
	for _, slot in ipairs(slots) do
		local attribute = COUNT_ATTRIBUTE[slot.kind]
		local n = attribute and (player:GetAttribute(attribute) or 0) or 0
		if slot.kind == "Keycard" then
			slot.count.Text = n > 0 and ("L" .. n) or ""
		else
			slot.count.Text = n > 1 and ("x" .. n) or ""
		end
	end
end

local function refreshSlots()
	for i, slot in ipairs(slots) do
		local kind = player:GetAttribute("Slot" .. i) or ""
		if kind ~= slot.kind then
			local wasEmpty = slot.kind == ""
			showItem(slot, kind)
			if kind ~= "" and wasEmpty then
				flashName("Picked up: " .. (ITEMS[kind] and ITEMS[kind].name or kind))
			end
		end
	end
	refreshCounts()
end

for i = 1, MAX_SLOTS do
	player:GetAttributeChangedSignal("Slot" .. i):Connect(refreshSlots)
end
for _, attribute in pairs(COUNT_ATTRIBUTE) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		refreshCounts()
		-- a keycard upgrade recolours the card in its slot
		if attribute == "KeycardLevel" then
			for _, slot in ipairs(slots) do
				if slot.kind == "Keycard" then
					showItem(slot, "Keycard")
				end
			end
		end
	end)
end
refreshSlots()
refreshSelection(false)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	for i, key in ipairs(SLOT_KEYS) do
		if input.KeyCode == key and i <= MAX_SLOTS then
			selected = i
			refreshSelection(true)
			return
		end
	end
	if input.KeyCode == DROP_KEY then
		local character = player.Character
		if character and not character:GetAttribute("IsHiding") and slots[selected].kind ~= "" then
			event:FireServer("Drop", selected)
		end
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	local step = input.Position.Z > 0 and -1 or 1
	selected = (selected - 1 + step) % MAX_SLOTS + 1
	refreshSelection(true)
end)

event.OnClientEvent:Connect(function(action, kind)
	if action == "Full" then
		flashName("Your hands are full  -  drop something [Q]")
		itemName.TextColor3 = Color3.fromRGB(230, 110, 90)
		task.delay(2.4, function()
			itemName.TextColor3 = BONE
		end)
	elseif action == "Dropped" then
		flashName("Dropped: " .. (ITEMS[kind] and ITEMS[kind].name or tostring(kind)))
	end
end)

--------------------------------------------------
-- HEALTH, STAMINA, ADRENALINE
--------------------------------------------------

local character, humanoid
local shownHealth = 1
local chipHealth = 1
local chipHoldUntil = 0
local stamina = STAMINA_MAX
local exhausted = false
local lastSprint = 0
local staminaShownUntil = 0
local stAlpha = 1
-- health only shows when something happens to it (and while it's low)
local HEALTH_SHOW_FOR = 4
local LOW_HEALTH = 0.3
local healthShownUntil = 0
local hpAlpha = 1
local hpStroke = hpBack:FindFirstChildOfClass("UIStroke")
local hpNotches = {}
for _, f in ipairs(hpBack:GetChildren()) do
	if f:IsA("Frame") and f.ZIndex == 3 then table.insert(hpNotches, f) end
end

local adrenalineEnd, adrenalineTotal, adrenalineClock = nil, nil, nil

-- The medical script stamps AdrenalineUntil on your character. Work out
-- which clock it used (whichever puts the end a sensible few seconds ahead).
local CLOCKS = {
	function() return workspace:GetServerTimeNow() end,
	function() return os.clock() end,
	function() return tick() end,
	function() return os.time() end,
}
local function readAdrenaline()
	local value = character and character:GetAttribute("AdrenalineUntil")
	if type(value) ~= "number" then
		adrenalineEnd = nil
		return
	end
	for _, clock in ipairs(CLOCKS) do
		local left = value - clock()
		if left > 0 and left < 120 then
			adrenalineEnd, adrenalineClock = value, clock
			adrenalineTotal = math.max(left, adrenalineTotal or 0)
			return
		end
	end
	adrenalineEnd = nil
end

local function bind(c)
	character = c
	humanoid = c:WaitForChild("Humanoid")
	shownHealth = humanoid.Health / math.max(humanoid.MaxHealth, 1)
	chipHealth = shownHealth
	stamina = STAMINA_MAX
	exhausted = false
	adrenalineTotal = nil
	readAdrenaline()
	c:GetAttributeChangedSignal("AdrenalineUntil"):Connect(function()
		adrenalineTotal = nil
		readAdrenaline()
	end)
	humanoid.HealthChanged:Connect(function()
		chipHoldUntil = os.clock() + 0.45   -- the chip waits a moment, then slides down
		healthShownUntil = os.clock() + HEALTH_SHOW_FOR
	end)
end
if player.Character then
	bind(player.Character)
end
player.CharacterAdded:Connect(bind)

-- being out of breath: you can't go faster than a walk
local afterAnimation = RunService.PreSimulation or RunService.Stepped
afterAnimation:Connect(function()
	if exhausted and humanoid and humanoid.Parent then
		local cap = WALK_SPEED * (character:GetAttribute("SpeedMultiplier") or 1)
		if humanoid.WalkSpeed > cap then
			humanoid.WalkSpeed = cap
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not humanoid or not humanoid.Parent then
		return
	end
	local now = os.clock()

	------------------------------------------------ adrenaline
	local adrenalineLeft = 0
	if adrenalineEnd and adrenalineClock then
		adrenalineLeft = adrenalineEnd - adrenalineClock()
		if adrenalineLeft <= 0 then
			adrenalineEnd = nil
			adrenalineLeft = 0
		end
	end
	local onAdrenaline = adrenalineLeft > 0
	adrBack.Visible = onAdrenaline
	adrLabel.TextTransparency = onAdrenaline and 0.2 or 1
	if onAdrenaline then
		adrFill.Size = UDim2.fromScale(math.clamp(adrenalineLeft / (adrenalineTotal or 14), 0, 1), 1)
		local lit = true
		if adrenalineLeft < 3 then
			lit = math.sin(now * 14) > 0      -- blinks as it runs out
		end
		adrFill.BackgroundTransparency = lit and 0 or 0.7
		adrGlow.Transparency = 0.35 + 0.25 * math.sin(now * 6)
	end

	------------------------------------------------ health
	local target = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
	shownHealth += (target - shownHealth) * math.min(dt * 12, 1)
	if target > chipHealth or now > chipHoldUntil then
		chipHealth += (target - chipHealth) * math.min(dt * (target > chipHealth and 20 or 3), 1)
	end
	hpFill.Size = UDim2.fromScale(shownHealth, 1)
	hpChip.Size = UDim2.fromScale(math.max(chipHealth, shownHealth), 1)
	local downed = character:GetAttribute("Downed") == true
	downText.Visible = downed and math.sin(now * 5) > -0.2
	if downed then
		hpBack.BackgroundColor3 = Color3.fromRGB(60, 4, 4)
	elseif target < 0.25 then
		-- low: the bar throbs like a pulse
		local beat = (math.sin(now * 7) + 1) / 2
		hpBack.BackgroundColor3 = Color3.fromRGB(8, 7, 7):Lerp(Color3.fromRGB(70, 6, 6), beat)
		hpLabel.TextColor3 = BONE:Lerp(Color3.fromRGB(230, 70, 60), beat)
	else
		hpBack.BackgroundColor3 = Color3.fromRGB(8, 7, 7)
		hpLabel.TextColor3 = BONE
	end

	-- shown after a hit (or a heal), and all the time while you're low or down
	local wantHp = (now < healthShownUntil or target < LOW_HEALTH or downed) and 0 or 1
	hpAlpha += (wantHp - hpAlpha) * math.min(dt * (wantHp < hpAlpha and 10 or 2.5), 1)
	hpBack.BackgroundTransparency = 0.3 + 0.7 * hpAlpha
	hpFill.BackgroundTransparency = hpAlpha
	hpChip.BackgroundTransparency = hpAlpha
	hpLabel.TextTransparency = 0.35 + 0.65 * hpAlpha
	if hpStroke then hpStroke.Transparency = 0.3 + 0.7 * hpAlpha end
	for _, n in ipairs(hpNotches) do n.BackgroundTransparency = 0.4 + 0.6 * hpAlpha end

	------------------------------------------------ stamina
	local maxStamina = STAMINA_MAX * (character:GetAttribute("StaminaMultiplier") or 1)
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local sprinting = character:GetAttribute("MoveState") == "Sprint" and moving and not exhausted and not downed
	if sprinting and not onAdrenaline then
		stamina = math.max(0, stamina - STAMINA_DRAIN * dt)
		lastSprint = now
		if stamina <= 0 then
			exhausted = true
		end
	elseif onAdrenaline then
		stamina = math.min(maxStamina, stamina + STAMINA_REGEN * 2.5 * dt)
	elseif now - lastSprint > REGEN_DELAY then
		stamina = math.min(maxStamina, stamina + STAMINA_REGEN * (moving and 0.6 or 1) * dt)
	end
	if exhausted and stamina >= RECOVER_AT then
		exhausted = false
	end
	character:SetAttribute("Stamina", stamina / maxStamina * 100)
	character:SetAttribute("Exhausted", exhausted)

	local fraction = stamina / maxStamina
	stFill.Size = UDim2.fromScale(fraction, 1)
	if exhausted then
		stFill.BackgroundColor3 = BONE:Lerp(Color3.fromRGB(190, 40, 30), (math.sin(now * 10) + 1) / 2)
		stLabel.Text = "OUT OF BREATH"
	else
		stFill.BackgroundColor3 = onAdrenaline and ORANGE:Lerp(BONE, 0.4) or BONE
		stLabel.Text = "STAMINA"
	end
	-- only there when you're using it
	if fraction < 0.999 or sprinting then
		staminaShownUntil = now + 1.5
	end
	local wantAlpha = now < staminaShownUntil and 0 or 1
	stAlpha += (wantAlpha - stAlpha) * math.min(dt * 5, 1)
	stBack.BackgroundTransparency = 0.3 + 0.7 * stAlpha
	if stStroke then
		stStroke.Transparency = 0.3 + 0.7 * stAlpha      -- the outline fades with it
	end
	stFill.BackgroundTransparency = stAlpha
	stLabel.TextTransparency = 0.35 + 0.65 * stAlpha

	------------------------------------------------ slot models turn slowly
	for _, slot in ipairs(slots) do
		if slot.model then
			slot.spin += dt * 0.8
			local d = slot.distance or 3
			local eye = Vector3.new(math.cos(slot.spin) * d, d * 0.35, math.sin(slot.spin) * d)
			slot.camera.CFrame = CFrame.lookAt(eye, Vector3.zero)
		end
	end
end)
