-- DoorServer
-- Place in: ServerScriptService (a ModuleScript named exactly "DoorServer").
-- The DoorSystem script starts it; CrawlerAI uses it too.
--
-- Every door built with BuildDoor:
--   * opens away from whoever opens it, closes again (left click; DoorClient
--     asks, this decides). The leaf really moves here, so the Crawler and the
--     Gaunt One bump into closed doors; every screen animates the swing itself.
--   * can be held shut (E) while the Crawler is hunting nearby: you lean your
--     shoulder into it and wait. When it hits the door the fight starts: your
--     screen runs the dial, every push or miss comes back here, and everyone
--     sees and hears each slam. Hold out for 7-8 good pushes and it gives up;
--     miss 3 and the door bursts open and throws you to the floor.
--   * smashes apart with real physics: planks splinter off a wooden door, a
--     steel door is torn off its hinges, a cell gate is ripped out of its frame.
-- The Gaunt One just shoves doors open when it walks into them.

local Doors = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("DoorConfig"))

local UP = Vector3.new(0, 1, 0)

local folder = ReplicatedStorage:FindFirstChild("Doors") or Instance.new("Folder")
folder.Name = "Doors"
folder.Parent = ReplicatedStorage
local remote = folder:FindFirstChild("DoorRemote") or Instance.new("RemoteEvent")
remote.Name = "DoorRemote"
remote.Parent = folder

local function now()
	return workspace:GetServerTimeNow()
end

--------------------------------------------------
-- KNOWING THE DOORS
--------------------------------------------------

local doors = {}          -- model -> door
local byPart = {}         -- any leaf part -> model

local function register(model)
	if doors[model] or not model:IsA("Model") or not model:GetAttribute("DoorType") then
		return
	end
	local kind = model:GetAttribute("DoorType")
	local leaf = model:FindFirstChild("Leaf")
	local hinge, centre = model:GetAttribute("Hinge"), model:GetAttribute("Centre")
	if not (Config.TYPES[kind] and leaf and typeof(hinge) == "CFrame" and typeof(centre) == "CFrame") then
		warn("DoorServer: " .. model:GetFullName() .. " isn't a finished door (build it with BuildDoor)")
		return
	end
	local door = {
		model = model, leaf = leaf, kind = kind, cfg = Config.TYPES[kind],
		hinge = hinge, centre = centre,
		width = model:GetAttribute("Width") or 4, height = model:GetAttribute("Height") or 7,
		lastUse = 0, holder = nil, fight = nil,
	}
	doors[model] = door
	for _, p in ipairs(leaf:GetDescendants()) do
		if p:IsA("BasePart") then
			byPart[p] = model
		end
	end
	model:SetAttribute("Angle", 0)
	model:SetAttribute("Broken", false)
	model:SetAttribute("BarricadedBy", 0)
	model:SetAttribute("Fighting", false)
end

for _, d in ipairs(workspace:GetDescendants()) do
	register(d)
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and d:GetAttribute("DoorType") then
		task.defer(register, d)
	end
end)

-- which side of the door a point is on: 1 = its back, -1 = its front
local function side(door, position)
	return door.centre:PointToObjectSpace(position).Z >= 0 and 1 or -1
end

local function setAngle(door, angle, style)
	door.leaf:PivotTo(door.hinge * CFrame.Angles(0, math.rad(angle), 0))
	door.model:SetAttribute("MoveStyle", style or "normal")
	door.model:SetAttribute("Angle", angle)
end

function Doors.get(model)
	return doors[model]
end

-- the door a part belongs to (or nil)
function Doors.fromPart(part)
	local model = part and byPart[part]
	return model and doors[model] and model or nil
end

function Doors.isClosed(model)
	local door = doors[model]
	return door ~= nil and not model:GetAttribute("Broken") and model:GetAttribute("Angle") == 0
end

-- open it away from `from` (style: "normal", "creep" = slowly, "shove" = hard)
function Doors.open(model, from, style)
	local door = doors[model]
	if not door or model:GetAttribute("Broken") or door.holder or model:GetAttribute("Angle") ~= 0 then
		return false
	end
	setAngle(door, side(door, from) * door.cfg.openAngle, style)
	return true
end

function Doors.close(model, style)
	local door = doors[model]
	if not door or model:GetAttribute("Broken") or model:GetAttribute("Angle") == 0 then
		return false
	end
	setAngle(door, 0, style)
	return true
end

-- the closed door in front of `origin` within `direction`, if there is one
function Doors.ahead(origin, direction, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	for _, lift in ipairs({ 0, -1.2 }) do
		local hit = workspace:Raycast(origin + UP * lift, direction, params)
		local model = hit and Doors.fromPart(hit.Instance)
		if model and Doors.isClosed(model) then
			return model
		end
	end
	return nil
end

-- where things are, for the Crawler: the door's middle, which way its face
-- points towards `from`, and the edge that swings
function Doors.layout(model, from)
	local door = doors[model]
	local s = side(door, from)
	local floorY = door.centre.Position.Y - door.height / 2
	return {
		centre = door.centre,
		point = door.centre:PointToWorldSpace(Vector3.new(0, -door.height / 2 + 3.4, 0)),
		normal = door.centre:VectorToWorldSpace(Vector3.new(0, 0, s)),     -- out of the door towards `from`
		edge = door.centre:PointToWorldSpace(Vector3.new(door.width / 2 - 0.1, -door.height / 2 + 3.2, 0)),
		floorY = floorY,
		side = s,
	}
end

--------------------------------------------------
-- BREAKING
--------------------------------------------------

function Doors.breakDoor(model, push)
	local door = doors[model]
	if not door or model:GetAttribute("Broken") then
		return
	end
	model:SetAttribute("Broken", true)
	model:SetAttribute("BarricadedBy", 0)
	push = Vector3.new(push.X, 0, push.Z).Unit

	local mains, rest = {}, {}
	for _, p in ipairs(door.leaf:GetDescendants()) do
		if p:IsA("BasePart") then
			if p.Name == "LeafRoot" then
				p:Destroy()
			elseif p:GetAttribute("Main") then
				table.insert(mains, p)
			else
				table.insert(rest, p)
			end
		elseif p:IsA("PathfindingModifier") then
			p:Destroy()
		end
	end
	-- a wooden door comes apart plank by plank; steel and iron stay in one piece
	local function nearest(part)
		local best, bestD = mains[1], math.huge
		for _, m in ipairs(mains) do
			local d = (m.Position - part.Position).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
		return best
	end
	for _, p in ipairs(rest) do
		local anchor = door.kind == "Wood" and nearest(p) or mains[1]
		if anchor then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = anchor, p
			w.Parent = p
		end
	end
	if door.kind ~= "Wood" then
		for i = 2, #mains do
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = mains[1], mains[i]
			w.Parent = mains[i]
		end
	end
	for _, p in ipairs(door.leaf:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = p.Size.Magnitude > 0.6
		end
	end
	local rng = Random.new()
	local pieces = door.kind == "Wood" and mains or { mains[1] }
	for _, p in ipairs(pieces) do
		if p and p.Parent then
			local speed = door.kind == "Wood" and rng:NextNumber(24, 40) or door.kind == "Steel" and 22 or 26
			local up = door.kind == "Wood" and rng:NextNumber(4, 12) or 7
			local sideways = door.centre:VectorToWorldSpace(Vector3.new(rng:NextNumber(-6, 6), 0, 0))
			p.AssemblyLinearVelocity = push * speed + UP * up + sideways
			p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(-8, 8), rng:NextNumber(-14, 14))
				* (door.kind == "Wood" and 1 or 0.4)
			pcall(function()
				p:SetNetworkOwner(nil)
			end)
		end
	end
	remote:FireAllClients("Broken", model, push)
end

--------------------------------------------------
-- HOLDING IT SHUT
--------------------------------------------------

local function crawler()
	return workspace:FindFirstChild("TheCrawler")
end

-- is it hunting close enough to this door that holding it makes sense?
local function threatNear(door)
	local m = crawler()
	local root = m and m:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local hunting = m:GetAttribute("Chasing") == true or (m:GetAttribute("State") or ""):sub(1, 4) == "Door"
	return hunting and (root.Position - door.centre.Position).Magnitude <= Config.CHASE_NEAR
end

local function clearHolder(character, unanchor)
	if not character then
		return
	end
	local link = character:FindFirstChild("BarricadeDoor")
	if link then
		link:Destroy()
	end
	character:SetAttribute("IsBarricading", false)
	character:SetAttribute("BraceAt", 0)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if unanchor and hrp and not character:GetAttribute("BeingKilled") then
		hrp.Anchored = false
	end
end

local function release(door)
	local player = door.holder
	door.holder = nil
	door.model:SetAttribute("BarricadedBy", 0)
	if player and player.Character then
		clearHolder(player.Character, true)
		remote:FireClient(player, "End", door.model)
	end
end

local function startHold(player, model)
	local door = doors[model]
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not (door and hrp and hum) or hum.Health <= 0 then
		return
	end
	if model:GetAttribute("Broken") or door.holder or character:GetAttribute("IsBarricading")
		or character:GetAttribute("Downed") or character:GetAttribute("BeingKilled") then
		return
	end
	local flat = door.centre:PointToObjectSpace(hrp.Position)
	if math.abs(flat.Z) > Config.HOLD_RANGE or math.abs(flat.X) > door.width / 2 + 2.5 then
		return
	end
	if not threatNear(door) then
		remote:FireClient(player, "Denied", model)
		return
	end
	-- slam it shut first if it's open
	if model:GetAttribute("Angle") ~= 0 then
		setAngle(door, 0, "slam")
	end

	local s = side(door, hrp.Position)
	local floorY = door.centre.Position.Y - door.height / 2
	local standY = math.clamp(hrp.Position.Y - floorY, 2.6, 3.4)
	local x = door.width * 0.12
	local spot = door.centre:PointToWorldSpace(Vector3.new(x, floorY + standY - door.centre.Position.Y, s * 1.75))
	local faceAt = door.centre:PointToWorldSpace(Vector3.new(x, floorY + standY - door.centre.Position.Y, 0))
	hrp.Anchored = true
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = CFrame.lookAt(spot, faceAt)

	door.holder = player
	model:SetAttribute("BarricadedBy", player.UserId)
	local link = Instance.new("ObjectValue")
	link.Name = "BarricadeDoor"
	link.Value = model
	link.Parent = character
	character:SetAttribute("BraceSide", s)
	character:SetAttribute("BraceAt", now())
	character:SetAttribute("ThrownAt", 0)
	character:SetAttribute("IsBarricading", true)

	-- let go if they die, go down, get grabbed or leave
	local conns = {}
	local function stop()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		if door.holder == player then
			release(door)
		end
	end
	table.insert(conns, hum.Died:Connect(stop))
	table.insert(conns, character:GetAttributeChangedSignal("Downed"):Connect(function()
		if character:GetAttribute("Downed") then stop() end
	end))
	table.insert(conns, character:GetAttributeChangedSignal("BeingKilled"):Connect(function()
		if character:GetAttribute("BeingKilled") then stop() end
	end))
	table.insert(conns, character.AncestryChanged:Connect(function(_, parent)
		if not parent then stop() end
	end))
	table.insert(conns, model:GetAttributeChangedSignal("BarricadedBy"):Connect(function()
		if model:GetAttribute("BarricadedBy") ~= player.UserId then
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
		end
	end))
end

-- thrown off the door when it bursts: knocked onto your back, then you get up
local THROWN_TIME = 2.5
local function throw(door, player, push)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	door.holder = nil
	door.model:SetAttribute("BarricadedBy", 0)
	if not hrp then
		return
	end
	character:SetAttribute("ThrownAt", now())
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, door.model }
	local hit = workspace:Raycast(hrp.Position, push * 4.5, params)
	local distance = hit and math.max((hit.Position - hrp.Position).Magnitude - 1.2, 0) or 3.8
	local from = hrp.CFrame
	local to = from + push * distance
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.38 do
			local a = (os.clock() - t0) / 0.38
			if hrp.Parent and hrp.Anchored then
				hrp.CFrame = from:Lerp(to, 1 - (1 - a) * (1 - a))
			end
			RunService.Heartbeat:Wait()
		end
		if hrp.Parent and hrp.Anchored then
			hrp.CFrame = to
		end
		task.wait(THROWN_TIME - 0.38)
		if character.Parent and not character:GetAttribute("BeingKilled") then
			clearHolder(character, true)
			remote:FireClient(player, "End", door.model)
		end
	end)
end

-- One of your pushes landed (or didn't). Shared by the dial and the timeout.
local function result(door, kind)
	local f = door.fight
	if not f or f.outcome then
		return
	end
	f.last = os.clock()
	if kind == "hit" then
		f.hits += 1
	else
		f.misses += 1
	end
	if f.monster and f.monster.Parent then
		f.monster:SetAttribute("SlamKind", kind)
		f.monster:SetAttribute("SlamAt", now())
	end
	remote:FireAllClients("Slam", door.model, kind, f.hits, f.misses, f.need, f.player.UserId)
	if f.hits >= f.need then
		f.outcome = "won"
		remote:FireAllClients("Held", door.model, f.player.UserId)
		task.delay(2.2, function()
			if door.holder == f.player then
				release(door)
			end
		end)
	elseif f.misses >= Config.MISSES_TO_BREACH then
		f.outcome = "breach"
		local push = door.centre:VectorToWorldSpace(Vector3.new(0, 0, f.side))
		throw(door, f.player, push)
		Doors.breakDoor(door.model, push)
	end
end

-- The Crawler is at the door. If someone's holding it, the fight plays out and
-- this returns "won" (they held), "breach" (it got through) or "abandoned"
-- (they let go). Nobody holding it: "none" straight away.
function Doors.fight(model, monster)
	local door = doors[model]
	if not door or not door.holder then
		return "none"
	end
	local player = door.holder
	local character = player.Character
	local f = {
		need = math.random(Config.WINS_TO_HOLD[1], Config.WINS_TO_HOLD[2]),
		hits = 0, misses = 0, last = os.clock(), lastClient = 0, outcome = nil,
		player = player, monster = monster,
		side = character and character:GetAttribute("BraceSide") or 1,
	}
	door.fight = f
	model:SetAttribute("Fighting", true)
	remote:FireClient(player, "Dial", model, f.need)
	while not f.outcome do
		task.wait(0.1)
		if door.holder ~= player and not f.outcome then
			f.outcome = "abandoned"
		elseif os.clock() - f.last > Config.ROUND_TIMEOUT then
			result(door, "miss")
		end
	end
	door.fight = nil
	model:SetAttribute("Fighting", false)
	return f.outcome
end

--------------------------------------------------
-- WHAT PLAYERS ASK FOR
--------------------------------------------------

remote.OnServerEvent:Connect(function(player, action, model)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if action == "Toggle" then
		local door = typeof(model) == "Instance" and doors[model]
		if not (door and hrp) or door.holder or model:GetAttribute("Broken") or character:GetAttribute("IsBarricading") then
			return
		end
		if (hrp.Position - door.centre.Position).Magnitude > Config.USE_RANGE + 3 or os.clock() - door.lastUse < 0.35 then
			return
		end
		door.lastUse = os.clock()
		if model:GetAttribute("Angle") == 0 then
			Doors.open(model, hrp.Position, "normal")
		else
			Doors.close(model, "normal")
		end
	elseif action == "Hold" then
		if typeof(model) == "Instance" and doors[model] then
			startHold(player, model)
		end
	elseif action == "Release" then
		for _, door in pairs(doors) do
			if door.holder == player and not door.fight then
				release(door)
			elseif door.holder == player and door.fight then
				release(door)          -- letting go mid-fight: it smashes straight through
			end
		end
	elseif action == "Result" then
		local kind = model == "hit" and "hit" or "miss"
		for _, door in pairs(doors) do
			local f = door.fight
			if f and f.player == player and not f.outcome and os.clock() - f.lastClient > 0.28 then
				f.lastClient = os.clock()
				result(door, kind)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, door in pairs(doors) do
		if door.holder == player then
			release(door)
		end
	end
end)

--------------------------------------------------
-- THE GAUNT ONE SHOVES DOORS OPEN
--------------------------------------------------

task.spawn(function()
	while true do
		task.wait(0.2)
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("GauntRig") then
				local root = m:FindFirstChild("HumanoidRootPart")
				if root then
					local vel = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
					for model, door in pairs(doors) do
						if Doors.isClosed(model) and not door.holder then
							local localPos = door.centre:PointToObjectSpace(root.Position)
							if math.abs(localPos.Z) < 4.5 and math.abs(localPos.X) < door.width / 2 + 1 and math.abs(localPos.Y) < door.height then
								local towards = -door.centre:VectorToWorldSpace(Vector3.new(0, 0, localPos.Z >= 0 and 1 or -1))
								if vel.Magnitude > 1 and vel.Unit:Dot(towards) > 0.3 then
									Doors.open(model, root.Position, "shove")
								end
							end
						end
					end
				end
			end
		end
	end
end)

return Doors
