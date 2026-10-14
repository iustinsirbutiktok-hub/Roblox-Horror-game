-- CamcorderStateServer
-- The camcorder's server side (it replaces the headlamp):
--   * raise / lower: relayed so other players see you holding it up
--   * the battery: drains only while night vision is on; at 0 it cuts out
--   * spare batteries: the player's "Batteries" attribute (pick them up from
--     "HeadlampBattery" / "CamcorderBattery" models; they show in the item slots)
--   * swapping batteries (R): takes a spare, fills the camcorder back up
--
-- Player attributes:  CamcorderCharge (0-100), Batteries (spares)
-- Character attributes: CamcorderRaised, CamcorderReloading (server time it started)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local BATTERY_LIFE = 150          -- seconds of night vision from a full battery
local START_SPARES = 1
local MAX_SPARES = 4
local RELOAD_TIME = 2.6           -- the length of the battery-swap animation
local RELOAD_FILLS_AT = 1.9       -- the moment the new battery clicks in
local PICKUP_NAMES = { HeadlampBattery = true, CamcorderBattery = true }
local PICKUP_SOUND = "rbxassetid://9119727134"

--------------------------------------------------
-- SHARED
--------------------------------------------------

local event = ReplicatedStorage:WaitForChild("CamcorderState")
local assets = ReplicatedStorage:WaitForChild("CamcorderAssets")
assets:SetAttribute("BatteryLife", BATTERY_LIFE)
assets:SetAttribute("ReloadTime", RELOAD_TIME)
assets:SetAttribute("ReloadFillsAt", RELOAD_FILLS_AT)

-- A loose battery pack (used for the item slot picture and when dropped):
-- built once from the camcorder's own battery.
if not assets:FindFirstChild("Battery") then
	local source = assets:WaitForChild("CamcorderViewmodel"):FindFirstChild("battery_pack", true)
	if source then
		local model = Instance.new("Model")
		model.Name = "Battery"
		local pack = source:Clone()
		pack.Name = "Body"
		pack.Anchored = true
		pack.CanCollide = false
		pack.CFrame = CFrame.new()
		pack.Parent = model
		local stripe = Instance.new("Part")
		stripe.Name = "Label"
		stripe.Size = Vector3.new(pack.Size.X + 0.01, 0.06, pack.Size.Z + 0.01)
		stripe.CFrame = CFrame.new(0, pack.Size.Y * 0.2, 0)
		stripe.Color = Color3.fromRGB(200, 150, 40)
		stripe.Material = Enum.Material.SmoothPlastic
		stripe.Anchored = true
		stripe.CanCollide = false
		stripe.Parent = model
		model.PrimaryPart = pack
		model.Parent = assets
	end
end

-- The headlamp is gone: the camcorder has taken over its job.
for _, name in ipairs({ "HeadlampSystem" }) do
	local old = workspace:FindFirstChild(name) or game:GetService("ServerScriptService"):FindFirstChild(name)
	if old and old:IsA("Script") then
		old.Enabled = false
	end
end

--------------------------------------------------
-- PER PLAYER
--------------------------------------------------

local lastChange = {}
local raisedByPlayer = {}
local reloading = {}
local nightVisionOff = {}       -- player -> true while they've switched night vision off [F]

local function now()
	return workspace:GetServerTimeNow()
end

local function bindCharacter(player, character)
	raisedByPlayer[player] = false
	reloading[player] = nil
	character:SetAttribute("CamcorderRaised", false)
	character:SetAttribute("CamcorderReloading", 0)
	character:SetAttribute("CamcorderPoseFrom", 0)
	character:SetAttribute("CamcorderPoseTo", 0)
	character:SetAttribute("CamcorderPoseStarted", now())
	character:SetAttribute("CamcorderPoseDuration", 0)
end

local function setup(player)
	raisedByPlayer[player] = false
	if player:GetAttribute("CamcorderCharge") == nil then
		player:SetAttribute("CamcorderCharge", 100)
	end
	if player:GetAttribute("Batteries") == nil then
		player:SetAttribute("Batteries", START_SPARES)
	end
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
	if player.Character then
		bindCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(setup)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setup, player)
end

local function setRaised(player, raised)
	local character = player.Character
	if not character then
		return
	end
	local from = raisedByPlayer[player] and 1 or 0
	local to = raised and 1 or 0
	if from == to then
		return
	end
	raisedByPlayer[player] = raised
	local serverTime = now()
	character:SetAttribute("CamcorderPoseFrom", from)
	character:SetAttribute("CamcorderPoseTo", to)
	character:SetAttribute("CamcorderPoseStarted", serverTime)
	character:SetAttribute("CamcorderPoseDuration", 0.3)
	character:SetAttribute("CamcorderRaised", raised)
	event:FireAllClients(player.UserId, raised, from, serverTime, 0.3)
end

local function canUse(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.Health > 0 and not character:GetAttribute("Downed") and not character:GetAttribute("BeingKilled")
end

event.OnServerEvent:Connect(function(player, action)
	-- older clients send just true/false
	if typeof(action) == "boolean" then
		action = action and "Raise" or "Lower"
	end
	local t = os.clock()
	-- (the night vision switch isn't rate-limited with the rest)
	if action ~= "NightVisionOn" and action ~= "NightVisionOff" then
		if t - (lastChange[player] or 0) < 0.2 then
			return
		end
		lastChange[player] = t
	end

	if action == "Raise" then
		if canUse(player) and (player:GetAttribute("CamcorderCharge") or 0) > 0 and not reloading[player] then
			setRaised(player, true)
		end
	elseif action == "Lower" then
		setRaised(player, false)
	elseif action == "NightVisionOn" or action == "NightVisionOff" then
		nightVisionOff[player] = action == "NightVisionOff" or nil
		player:SetAttribute("NightVision", action == "NightVisionOn")
	elseif action == "Reload" then
		local character = player.Character
		local spares = player:GetAttribute("Batteries") or 0
		if not canUse(player) or reloading[player] or spares <= 0 or (player:GetAttribute("CamcorderCharge") or 0) >= 99 then
			return
		end
		setRaised(player, false)
		local started = now()
		reloading[player] = started
		character:SetAttribute("CamcorderReloading", started)
		task.delay(RELOAD_FILLS_AT, function()
			if reloading[player] ~= started or not canUse(player) then
				return
			end
			player:SetAttribute("Batteries", math.max(0, (player:GetAttribute("Batteries") or 0) - 1))
			player:SetAttribute("CamcorderCharge", 100)
		end)
		task.delay(RELOAD_TIME, function()
			if reloading[player] == started then
				reloading[player] = nil
				if character.Parent then
					character:SetAttribute("CamcorderReloading", 0)
				end
			end
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	nightVisionOff[player] = nil
	raisedByPlayer[player] = nil
	lastChange[player] = nil
	reloading[player] = nil
end)

--------------------------------------------------
-- DRAIN (only while the night vision is on)
--------------------------------------------------

task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(0.25)
		local dt = os.clock() - last
		last = os.clock()
		for player, raised in pairs(raisedByPlayer) do
			if raised and player.Parent and not nightVisionOff[player] then
				local character = player.Character
				-- the Mechanic's batteries last longer
				local life = BATTERY_LIFE * ((character and character:GetAttribute("HeadlampLife")) or 1)
				local charge = math.max(0, (player:GetAttribute("CamcorderCharge") or 0) - dt * 100 / life)
				player:SetAttribute("CamcorderCharge", charge)
				if charge <= 0 then
					setRaised(player, false)      -- the screen dies; it comes down
				end
			end
		end
	end
end)

--------------------------------------------------
-- BATTERY PICKUPS
--------------------------------------------------

local function roomFor(player)
	local inventory = ReplicatedStorage:FindFirstChild("Inventory")
	local check = inventory and inventory:FindFirstChild("CanCarry")
	if not check then
		return true
	end
	local ok, allowed = pcall(function()
		return check:Invoke(player, "Battery")
	end)
	return not ok or allowed
end

local function setupPickup(model)
	if not model:IsA("Model") or not PICKUP_NAMES[model.Name] or model:FindFirstChild("BatteryPrompt", true) then
		return
	end
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not body then
		return
	end
	-- the old headlamp system may have left its own prompt on it
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BatteryPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = "Camcorder battery"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player)
		if not model.Parent then
			return
		end
		local spares = player:GetAttribute("Batteries") or 0
		if spares >= MAX_SPARES or not roomFor(player) then
			return
		end
		player:SetAttribute("Batteries", spares + 1)
		local s = Instance.new("Sound")
		s.SoundId = PICKUP_SOUND
		s.Volume = 0.4
		s.PlaybackSpeed = 1.6
		s.Parent = body
		s:Play()
		Debris:AddItem(s, 2)
		model:Destroy()
	end)
end

for _, d in ipairs(workspace:GetDescendants()) do
	setupPickup(d)
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and PICKUP_NAMES[d.Name] then
		task.defer(setupPickup, d)
	end
end)
