-- BreakerLever
-- Place in: ReplicatedStorage (a ModuleScript named exactly "BreakerLever")
--
-- The main breaker (Workspace > "LEVER LIGHTS"), shared by PowerSystem
-- (server) and LeverClient (every screen): which parts swing, what they
-- swing around and how far, where the handle is at any moment, and the
-- timing of a pull. Worked out from the model's own parts:
--   moving   handle_grip, handle_ring_*, *_lever_lower_strut, *_lever_upper_strut
--   pivot    the line through the two *_pivot_bolt parts
--   swing    from where the handle is now to the far end of the slot_* it runs in
-- If the swing comes out wrong, give "LEVER LIGHTS" a SwingAngle attribute
-- (degrees, + or -) and that's used instead.

local BreakerLever = {}

BreakerLever.MODEL_NAME = "LEVER LIGHTS"
BreakerLever.USE_RANGE = 7.5

--------------------------------------------------
-- TIMING (seconds after the pull starts)
--------------------------------------------------
-- reach for it, get a grip, haul on it (it sticks, then gives and slams
-- home with a clunk), let go. Pulled with the circuits still broken it
-- moves a third of the way, sparks, and kicks back.

BreakerLever.T = {
	grip = 0.32,          -- hands on the handle
	pull = 0.45,          -- starts to move
	clunk = 0.82,         -- slams home
	release = 1.0,        -- hands come off
	done = 1.45,          -- body back to normal
	fail = 0.7,           -- (broken circuits) it sparks and kicks back here
	failDone = 1.3,
	lightsAfter = 0.35,   -- the lights start coming on this long after the clunk
}

local function smooth(a)
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- how far round the lever is (0 = up/off, 1 = thrown) t seconds into a pull
function BreakerLever.fraction(t, ok)
	local T = BreakerLever.T
	if t <= T.pull then
		return 0
	end
	if ok then
		if t < T.pull + 0.17 then
			return 0.12 * smooth((t - T.pull) / 0.17)                       -- stiff: it barely gives
		elseif t < T.clunk then
			local a = (t - T.pull - 0.17) / (T.clunk - T.pull - 0.17)
			return 0.12 + 0.88 * a * a                                       -- then it goes
		end
		local s = t - T.clunk
		return 1 + 0.06 * math.exp(-s * 9) * math.sin(s * 30)               -- slams home and shudders
	end
	if t < T.fail then
		return 0.33 * smooth((t - T.pull) / (T.fail - T.pull))
	end
	local s = t - T.fail
	return math.max(0.33 * math.exp(-s * 7) * math.cos(s * 16), -0.04)      -- kicks back up, wobbling
end

--------------------------------------------------
-- THE MODEL
--------------------------------------------------

function BreakerLever.find()
	return workspace:FindFirstChild(BreakerLever.MODEL_NAME, true)
end

local function isMoving(name)
	return name:sub(1, 7) == "handle_" or name:find("lever_lower_strut") ~= nil or name:find("lever_upper_strut") ~= nil
end

local function longest(part)
	local s = part.Size
	if s.X >= s.Y and s.X >= s.Z then
		return part.CFrame.RightVector, s.X
	elseif s.Y >= s.Z then
		return part.CFrame.UpVector, s.Y
	end
	return part.CFrame.LookVector, s.Z
end

local function thinnest(part)
	local s = part.Size
	if s.X <= s.Y and s.X <= s.Z then
		return part.CFrame.RightVector
	elseif s.Y <= s.Z then
		return part.CFrame.UpVector
	end
	return part.CFrame.LookVector
end

-- turn point p by angle a (radians) round the line through `at` along `axis`
local function turn(p, at, axis, a)
	return at + CFrame.fromAxisAngle(axis, a):VectorToWorldSpace(p - at)
end

-- everything about the lever, measured once at rest (nil if it isn't built right)
function BreakerLever.layout(model)
	model = model or BreakerLever.find()
	if not model then
		return nil
	end
	local moving, bolts, slots, grip, face, lamps = {}, {}, {}, nil, nil, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if isMoving(d.Name) then
				table.insert(moving, d)
				if d.Name == "handle_grip" then
					grip = d
				end
			elseif d.Name:find("pivot_bolt") then
				table.insert(bolts, d)
			elseif d.Name:sub(1, 5) == "slot_" then
				table.insert(slots, d)
			elseif d.Name == "face_panel" then
				face = d
			elseif d.Parent == model then
				-- the red and green lamps on the panel
				local c = d.Color
				if c.R > 0.55 and c.G < 0.4 and c.B < 0.4 then
					lamps.red = lamps.red or d
				elseif c.G > 0.55 and c.R < 0.5 and c.B < 0.6 then
					lamps.green = lamps.green or d
				end
			end
		end
	end
	if not grip or #moving == 0 then
		warn("BreakerLever: " .. model:GetFullName() .. " has no handle_grip to pull")
		return nil
	end

	-- what it swings round
	local at, axis
	if #bolts >= 2 then
		at = (bolts[1].Position + bolts[2].Position) / 2
		axis = (bolts[2].Position - bolts[1].Position).Unit
	else
		axis = longest(grip)
		local struts = {}
		for _, p in ipairs(moving) do
			if p.Name:find("strut") then
				table.insert(struts, p)
			end
		end
		-- (no bolts: the far end of the struts from the handle)
		at = grip.Position
		for _, p in ipairs(struts) do
			local dir, len = longest(p)
			for _, e in ipairs({ p.Position + dir * len / 2, p.Position - dir * len / 2 }) do
				if (e - grip.Position).Magnitude > (at - grip.Position).Magnitude then
					at = e
				end
			end
		end
		at = at - axis * axis:Dot(at - grip.Position)
	end

	-- which way the panel faces (the handle sits out in front of it)
	local normal = face and thinnest(face) or (grip.Position - at).Unit
	if face and normal:Dot(grip.Position - face.Position) < 0 then
		normal = -normal
	end

	-- how far it swings
	local angle = model:GetAttribute("SwingAngle")
	local g0 = grip.Position
	local function flat(v)
		return v - axis * axis:Dot(v)
	end
	if type(angle) == "number" then
		angle = math.rad(angle)
	else
		local v0 = flat(g0 - at)
		local far = nil
		for _, slot in ipairs(slots) do
			local dir, len = longest(slot)
			for _, e in ipairs({ slot.Position + dir * len / 2, slot.Position - dir * len / 2 }) do
				if not far or (e - g0).Magnitude > (far - g0).Magnitude then
					far = e
				end
			end
		end
		local magnitude = math.rad(80)
		if far then
			local v1 = flat(far - at)
			if v0.Magnitude > 0.05 and v1.Magnitude > 0.05 then
				magnitude = math.acos(math.clamp(v0.Unit:Dot(v1.Unit), -1, 1))
			end
			magnitude = math.clamp(magnitude, math.rad(35), math.rad(175))
			-- turn whichever way lands nearest the far end; if it's right round
			-- the other side, the way that swings the handle out in front
			local best, bestScore = nil, nil
			for _, sign in ipairs({ 1, -1 }) do
				local land = turn(g0, at, axis, sign * magnitude)
				local mid = turn(g0, at, axis, sign * magnitude / 2)
				local score = (land - far).Magnitude
				if magnitude > math.rad(140) then
					score = -(mid - at):Dot(normal)
				end
				if not bestScore or score < bestScore then
					best, bestScore = sign, score
				end
			end
			angle = best * magnitude
		else
			-- no slots to go by: swing it down
			angle = turn(g0, at, axis, magnitude).Y < g0.Y and magnitude or -magnitude
		end
	end

	local rest = {}
	for _, p in ipairs(moving) do
		rest[p] = p.CFrame
	end
	local gripAxis = longest(grip)
	return {
		model = model, moving = moving, rest = rest, grip = grip, gripRest = grip.CFrame,
		gripAxis = gripAxis, gripLength = select(2, longest(grip)),
		at = at, axis = axis, angle = angle, normal = normal, lamps = lamps,
		contacts = (function()
			local list = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name:find("terminal_contact") then
					table.insert(list, d)
				end
			end
			return list
		end)(),
	}
end

-- the lever's turn at fraction f (multiply into a part's rest CFrame)
function BreakerLever.swing(layout, f)
	local a = layout.angle * f
	return CFrame.new(layout.at) * CFrame.fromAxisAngle(layout.axis, a) * CFrame.new(-layout.at)
end

-- where the handle is at fraction f
function BreakerLever.gripAt(layout, f)
	return BreakerLever.swing(layout, f) * layout.gripRest
end

-- where someone stands to pull it: in front of the panel, facing it, close
-- enough that their hands land on the handle. hrpY = their root part height.
function BreakerLever.standSpot(layout, hrpY)
	local g = layout.gripRest.Position
	local n = Vector3.new(layout.normal.X, 0, layout.normal.Z)
	if n.Magnitude < 0.1 then
		n = Vector3.new(0, 0, 1)
	end
	n = n.Unit
	local dv = g.Y - (hrpY + 0.5)                   -- the handle against shoulder height
	-- (each hand is ~0.6 in from its shoulder: what's left of the arm's reach
	-- goes out to the handle)
	local d = math.sqrt(math.max(1.5 ^ 2 - dv * dv - 0.34, 0))
	d = math.max(d, 1.0)
	local pos = Vector3.new(g.X, hrpY, g.Z) + n * d
	return CFrame.lookAt(pos, pos - n)
end

return BreakerLever
