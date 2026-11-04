-- SnapToFloor
-- Run in Studio's Command Bar (View > Command Bar) with the furniture selected
-- (benches, desks, chairs, cabinets: Models or single parts, as many as you like).
--
-- Each selected thing is:
--   * stood upright: tilt removed, it keeps the way it faces
--   * dropped (or lifted) so its lowest point rests exactly on whatever is under it
--     (it looks straight down from several points under its footprint and sits on
--     the highest one, so nothing sinks into the floor or hovers above it)
-- Ctrl+Z undoes it.
--
-- KEEP_TILT = true leaves the tilt alone (only moves it up or down).

local KEEP_TILT = false
local GAP = 0.0          -- studs left between the object and the floor

local Selection = game:GetService("Selection")
local History = game:GetService("ChangeHistoryService")

local function boxOf(obj)
	if obj:IsA("Model") then
		return obj:GetBoundingBox()
	end
	return obj.CFrame, obj.Size
end

local function lowestY(cf, size)
	local low = math.huge
	for _, x in ipairs({ -1, 1 }) do
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				low = math.min(low, (cf * Vector3.new(x * size.X / 2, y * size.Y / 2, z * size.Z / 2)).Y)
			end
		end
	end
	return low
end

local function upright(obj)
	local cf = boxOf(obj)
	-- the box axis that points most nearly up becomes straight up
	local axes = { cf.RightVector, cf.UpVector, cf.LookVector }
	local best, bestDot = 2, -1
	for i, a in ipairs(axes) do
		if math.abs(a.Y) > bestDot then
			best, bestDot = i, math.abs(a.Y)
		end
	end
	local up = axes[best].Y >= 0 and axes[best] or -axes[best]
	-- and the way it faces stays the way it faces, just made level
	local front = best == 3 and cf.UpVector or cf.LookVector
	front = (front - up * front:Dot(up)).Unit
	local level = Vector3.new(front.X, 0, front.Z)
	if level.Magnitude < 1e-3 then
		return
	end
	local now = CFrame.lookAt(Vector3.zero, front, up)
	local want = CFrame.lookAt(Vector3.zero, level.Unit, Vector3.yAxis)
	local fix = CFrame.new(cf.Position) * (want * now:Inverse()) * CFrame.new(-cf.Position)
	if obj:IsA("Model") then
		obj:PivotTo(fix * obj:GetPivot())
	else
		obj.CFrame = fix * obj.CFrame
	end
end

local function floorUnder(obj, cf, size, skip)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.IgnoreWater = true
	local bottom = lowestY(cf, size)
	local startY = bottom + math.max(size.Y * 0.5, 0.5)
	local best
	for _, u in ipairs({ -0.4, 0, 0.4 }) do
		for _, v in ipairs({ -0.4, 0, 0.4 }) do
			local p = cf * Vector3.new(u * size.X, 0, v * size.Z)
			-- (looks past invisible or walk-through parts to the real floor)
			local ignore = table.clone(skip)
			for _ = 1, 8 do
				local hit = workspace:Raycast(Vector3.new(p.X, startY, p.Z), Vector3.new(0, -(startY - bottom) - 60, 0), params)
				if not hit then
					break
				end
				if hit.Instance.CanCollide and hit.Instance.Transparency < 0.95 then
					best = math.max(best or -math.huge, hit.Position.Y)
					break
				end
				table.insert(ignore, hit.Instance)
				params.FilterDescendantsInstances = ignore
			end
			params.FilterDescendantsInstances = skip
		end
	end
	return best, bottom
end

local chosen = Selection:Get()
local recording = History:TryBeginRecording("SnapToFloor")
local moved = 0
for _, obj in ipairs(chosen) do
	if obj:IsA("Model") or obj:IsA("BasePart") then
		if not KEEP_TILT then
			upright(obj)
		end
		local cf, size = boxOf(obj)
		local floorY, bottom = floorUnder(obj, cf, size, chosen)
		if floorY then
			local dy = floorY + GAP - bottom
			if obj:IsA("Model") then
				obj:PivotTo(obj:GetPivot() + Vector3.new(0, dy, 0))
			else
				obj.CFrame = obj.CFrame + Vector3.new(0, dy, 0)
			end
			moved += 1
			print(("SnapToFloor: %s moved %.2f studs"):format(obj:GetFullName(), dy))
		else
			warn("SnapToFloor: nothing under " .. obj:GetFullName())
		end
	end
end
if recording then
	History:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(("SnapToFloor: %d of %d placed"):format(moved, #chosen))
