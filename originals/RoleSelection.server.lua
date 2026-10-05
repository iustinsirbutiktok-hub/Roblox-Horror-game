-- RoleSelection
-- Place in: ServerScriptService (the script moves itself there if dropped
-- anywhere else). The client screen is inside this script.
--
-- When a player joins they don't spawn straight away: they get the role
-- selection screen, pick one of the five survivors, and spawn as that
-- character. A role can only be held by one player at a time; everyone's
-- screen updates the moment someone takes one.
--
-- Role characters: put the five role models (Acrobat, Mechanic, Medic,
-- Scout, Brute) in ServerStorage > RoleCharacters. If they're still
-- lying in Workspace this script moves them there for you.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

if script.Parent ~= ServerScriptService then
	script.Parent = ServerScriptService
end

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local ROLE_ORDER = { "Acrobat", "Mechanic", "Medic", "Scout", "Brute" }
local RESPAWN_TIME = 5

--------------------------------------------------
-- ROLE ABILITIES
--------------------------------------------------
-- Each role's numbers go onto the character as attributes every time it
-- spawns. The game's systems read them:
--   SpeedMultiplier    walking and sprinting speed      (RoleMovementClient)
--   CanSlide           sprint + crouch = slide          (RoleMovementClient)
--   StaminaMultiplier  how long you can sprint          (your sprint/stamina system)
--   ReviveSpeed        how fast you revive teammates    (DownedSystem)
--   MedicalSpeed       how fast you use bandages/shots  (MedicalClient)
--   ValveSpeed         how fast you turn valves         (ValveClient)
--   MinigameEase       more time, fewer trips           (FuseClient)
--   HeadlampLife       how long a battery lasts         (HeadlampSystem)
--   HeartbeatSense     hears monsters through walls     (RoleSenseClient)
--   CanMark            V: outline a monster for the team (RoleSenseClient + here)
--   NoiseMultiplier    how far monsters hear you        (monster AI)
--   HeavyCarry         heavy objects at full speed      (RoleMovementClient)
--   CanCarryDowned     V: sling a downed teammate over the shoulder (DownedSystem)
--   CarrySpeed         speed while carrying a teammate  (RoleMovementClient)
--   MaxHealth          set on spawn (here)
-- Anything not listed for a role is 1 (normal) / false.

local ABILITIES = {
	Acrobat = { SpeedMultiplier = 1.12, StaminaMultiplier = 1.6, CanSlide = true },
	Mechanic = { ValveSpeed = 1.6, MinigameEase = 1.5, HeadlampLife = 1.75 },
	Medic = { ReviveSpeed = 1.8, MedicalSpeed = 1.6 },
	Scout = { HeartbeatSense = true, CanMark = true, NoiseMultiplier = 0.5 },
	Brute = { MaxHealth = 150, HeavyCarry = true, CanCarryDowned = true, CarrySpeed = 0.78 },
}

local DEFAULTS = {
	SpeedMultiplier = 1, StaminaMultiplier = 1, CanSlide = false, ReviveSpeed = 1,
	MedicalSpeed = 1, ValveSpeed = 1, MinigameEase = 1, HeadlampLife = 1,
	HeartbeatSense = false, CanMark = false, NoiseMultiplier = 1,
	HeavyCarry = false, CanCarryDowned = false, CarrySpeed = 1,
}

-- Scout's mark
local MARK_DURATION = 8
local MARK_COOLDOWN = 30
local MARK_RANGE = 120

-- What counts as a monster (for the Scout's senses)
local MONSTER_NAMES = { TheGauntOne = true, TheCrawler = true, TheSawman = true, TheHollowMan = true }

-- Items each role starts with (given once, when the role is chosen)
local STARTER_ITEMS = {
	Medic = { Adrenaline = 3, Bandages = 2 },
}

--------------------------------------------------
-- ROLE MODELS
--------------------------------------------------

local storage = ServerStorage:FindFirstChild("RoleCharacters") or Instance.new("Folder")
storage.Name = "RoleCharacters"
storage.Parent = ServerStorage

for _, roleName in ipairs(ROLE_ORDER) do
	if not storage:FindFirstChild(roleName) then
		local found = workspace:FindFirstChild(roleName)
		if found and found:IsA("Model") and found:FindFirstChildOfClass("Humanoid") then
			found.Parent = storage
		end
	end
end

--------------------------------------------------
-- SHARED WITH CLIENTS
--------------------------------------------------

local folder = ReplicatedStorage:FindFirstChild("RoleSelection") or Instance.new("Folder")
folder.Name = "RoleSelection"
folder.Parent = ReplicatedStorage

local event = folder:FindFirstChild("RoleEvent") or Instance.new("RemoteEvent")
event.Name = "RoleEvent"
event.Parent = folder

-- Copies for the 3D previews on the selection cards (never simulated).
local previews = folder:FindFirstChild("Previews") or Instance.new("Folder")
previews.Name = "Previews"
previews.Parent = folder
for _, roleName in ipairs(ROLE_ORDER) do
	local template = storage:FindFirstChild(roleName)
	if template and not previews:FindFirstChild(roleName) then
		local copy = template:Clone()
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		copy.Parent = previews
	end
end

-- Who holds what: attribute "Taken_<Role>" = UserId (0 = free)
for _, roleName in ipairs(ROLE_ORDER) do
	folder:SetAttribute("Taken_" .. roleName, 0)
end

--------------------------------------------------
-- SPAWNING AS A ROLE
--------------------------------------------------

Players.CharacterAutoLoads = false   -- you spawn once you've picked a role

-- With the Lobby in the game, players wait there as a normal character,
-- the character screen only opens when the lobby says so (after voting),
-- and after choosing (or dying in the lobby) you spawn back in the lobby.
local function lobbySpawn()
	local lobbyFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Lobby")
	if lobbyFolder and lobbyFolder:GetAttribute("InMatch") then
		return nil
	end
	return workspace:FindFirstChild("LobbySpawnPoint", true)
end
local LOBBY_MODE = lobbySpawn() ~= nil
folder:SetAttribute("WaitForLobby", LOBBY_MODE)

local function spawnPoint()
	local lobbyPoint = lobbySpawn()
	if lobbyPoint then
		-- spread out a little on the lobby spawn, facing the elevator
		return CFrame.new(lobbyPoint.Position + Vector3.new(math.random(-4, 4), 3.2, math.random(-3, 3)))
			* lobbyPoint.CFrame.Rotation
	end
	local spawns = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d.Enabled then
			table.insert(spawns, d)
		end
	end
	local chosen = spawns[math.random(math.max(#spawns, 1))]
	local base = chosen and chosen.CFrame or CFrame.new(0, 5, 0)
	local offset = Vector3.new(math.random(-3, 3), 3.5, math.random(-3, 3))
	return CFrame.new(base.Position + offset)
end

local function spawnAs(player, roleName)
	local template = storage:FindFirstChild(roleName)
	if not template then
		-- no model for this role: fall back to the normal character
		player:LoadCharacter()
		return
	end

	local character = template:Clone()
	character.Name = player.Name

	-- what a normally-spawned character would get
	local characterScripts = StarterPlayer:FindFirstChild("StarterCharacterScripts")
	if characterScripts then
		for _, s in ipairs(characterScripts:GetChildren()) do
			local existing = character:FindFirstChild(s.Name)
			if existing then
				existing:Destroy()
			end
			s:Clone().Parent = character
		end
	end

	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end

	character:PivotTo(spawnPoint())

	-- clear away the previous body (Roblox only does this for its own spawns)
	local previous = player.Character
	if previous and previous ~= character then
		previous:Destroy()
	end

	player.Character = character
	character.Parent = workspace

	-- this role's abilities
	character:SetAttribute("Role", roleName)
	local abilities = ABILITIES[roleName] or {}
	for key, default in pairs(DEFAULTS) do
		local value = abilities[key]
		if value == nil then
			value = default
		end
		character:SetAttribute(key, value)
	end

	-- abilities that run on the player's own screen
	for _, clientName in ipairs({ "RoleMovementClient", "RoleSenseClient" }) do
		local template = script:FindFirstChild(clientName)
		if template then
			local copy = template:Clone()
			copy.Disabled = false
			copy.Parent = character
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and abilities.MaxHealth then
		humanoid.MaxHealth = abilities.MaxHealth
		humanoid.Health = abilities.MaxHealth
	end
	if humanoid then
		humanoid.Died:Connect(function()
			task.wait(RESPAWN_TIME)
			if player.Parent and player:GetAttribute("Role") == roleName then
				spawnAs(player, roleName)
			end
		end)
	end
end

--------------------------------------------------
-- REQUESTS
--------------------------------------------------

local function isRole(name)
	for _, roleName in ipairs(ROLE_ORDER) do
		if roleName == name then
			return true
		end
	end
	return false
end

local function chooseRole(player, roleName)
	if type(roleName) ~= "string" or not isRole(roleName) then
		return
	end
	if player:GetAttribute("Role") then
		return -- already locked in
	end

	local holder = folder:GetAttribute("Taken_" .. roleName)
	if holder ~= 0 and holder ~= player.UserId then
		event:FireClient(player, "Taken", roleName)
		return
	end

	folder:SetAttribute("Taken_" .. roleName, player.UserId)
	player:SetAttribute("Role", roleName)
	event:FireClient(player, "Confirmed", roleName)

	-- starting kit (on top of anything already picked up)
	for attribute, amount in pairs(STARTER_ITEMS[roleName] or {}) do
		player:SetAttribute(attribute, math.max(player:GetAttribute(attribute) or 0, amount))
	end

	task.wait(0.9)   -- let the screen fade to black first
	if player.Parent then
		spawnAs(player, roleName)
	end
end

event.OnServerEvent:Connect(function(player, action, roleName)
	if action == "Choose" then
		chooseRole(player, roleName)
	end
end)

-- the lobby opens the character screen for everyone once voting is done
local openSignal = folder:FindFirstChild("OpenSelection") or Instance.new("BindableEvent")
openSignal.Name = "OpenSelection"
openSignal.Parent = folder
openSignal.Event:Connect(function()
	folder:SetAttribute("SelectionOpen", true)
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("Role") then
			event:FireClient(player, "Open")
		end
	end
end)

-- ...and gives anyone still undecided when time runs out a free role
local autoPick = folder:FindFirstChild("AutoPick") or Instance.new("BindableEvent")
autoPick.Name = "AutoPick"
autoPick.Parent = folder
autoPick.Event:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("Role") then
			for _, roleName in ipairs(ROLE_ORDER) do
				if (folder:GetAttribute("Taken_" .. roleName) or 0) == 0 then
					event:FireClient(player, "AutoPicked", roleName)
					task.spawn(chooseRole, player, roleName)
					break
				end
			end
		end
	end
end)

--------------------------------------------------
-- SCOUT: MARKING A MONSTER FOR THE WHOLE TEAM
--------------------------------------------------

local abilityEvent = folder:FindFirstChild("RoleAbilityEvent") or Instance.new("RemoteEvent")
abilityEvent.Name = "RoleAbilityEvent"
abilityEvent.Parent = folder
folder:SetAttribute("MarkCooldown", MARK_COOLDOWN)
folder:SetAttribute("MarkDuration", MARK_DURATION)

local function isMonster(model)
	return typeof(model) == "Instance" and model:IsA("Model") and model:IsDescendantOf(workspace)
		and (MONSTER_NAMES[model.Name] or model:GetAttribute("IsMonster") or model:GetAttribute("GauntRig")) and true or false
end

abilityEvent.OnServerEvent:Connect(function(player, action, monster)
	if action ~= "Mark" then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not character:GetAttribute("CanMark") or character:GetAttribute("Downed") then
		return
	end
	if workspace:GetServerTimeNow() < (player:GetAttribute("MarkReadyAt") or 0) then
		return
	end
	if not isMonster(monster) then
		return
	end
	local _, size = monster:GetBoundingBox()
	local centre = monster:GetBoundingBox().Position
	if (centre - head.Position).Magnitude > MARK_RANGE + size.Magnitude then
		return
	end

	-- the Scout has to actually be able to see it
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(head.Position, centre - head.Position, params)
	if hit and not hit.Instance:IsDescendantOf(monster) then
		return
	end

	player:SetAttribute("MarkReadyAt", workspace:GetServerTimeNow() + MARK_COOLDOWN)

	local old = monster:FindFirstChild("ScoutMark")
	if old then
		old:Destroy()
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "ScoutMark"
	highlight.Adornee = monster
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(150, 20, 16)
	highlight.OutlineColor = Color3.fromRGB(235, 70, 55)
	highlight.FillTransparency = 1          -- each screen fades it in
	highlight.OutlineTransparency = 1
	highlight:SetAttribute("MarkedBy", player.DisplayName)
	highlight:SetAttribute("Expires", workspace:GetServerTimeNow() + MARK_DURATION)
	highlight.Parent = monster
	task.delay(MARK_DURATION + 0.8, function()
		if highlight.Parent then
			highlight:Destroy()
		end
	end)
end)

--------------------------------------------------
-- JOINING / LEAVING
--------------------------------------------------

local clientTemplate = script:WaitForChild("RoleSelectionClient")

local function spawnInLobby(player)
	player:LoadCharacter()
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(spawnPoint())
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			task.wait(RESPAWN_TIME)
			if player.Parent and not player:GetAttribute("Role") then
				spawnInLobby(player)
			end
		end)
	end
end

local function onPlayerAdded(player)
	local gui = player:WaitForChild("PlayerGui", 20)
	if not gui then
		return
	end
	-- inside a holder that survives respawns (in the lobby you respawn as your
	-- chosen character while this screen is still fading out)
	local holder = gui:FindFirstChild("RoleSelectionHolder") or Instance.new("ScreenGui")
	holder.Name = "RoleSelectionHolder"
	holder.ResetOnSpawn = false
	holder.Parent = gui
	local client = clientTemplate:Clone()
	client.Disabled = false
	client.Parent = holder
	if LOBBY_MODE and not player:GetAttribute("Role") then
		spawnInLobby(player)
		-- joined while everyone was picking characters? open it for them too
		if folder:GetAttribute("SelectionOpen") then
			task.wait(1)
			event:FireClient(player, "Open")
		end
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	for _, roleName in ipairs(ROLE_ORDER) do
		if folder:GetAttribute("Taken_" .. roleName) == player.UserId then
			folder:SetAttribute("Taken_" .. roleName, 0)
		end
	end
end)
