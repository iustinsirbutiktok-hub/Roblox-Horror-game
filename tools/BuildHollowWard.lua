-- BuildHollowWard
-- Run once in Studio's Command Bar (View > Command Bar), then save the place.
-- Builds "HollowWard" (the Hollowmere asylum floor for the sedation blitz) at ORIGIN:
--   lift lobby -> the long ward gallery (where the round starts) -> north wing
--   (nurses' station, pharmacy, surgery, flooded showers, padded cells) and
--   ward B, the morgue store, and two crouch-only shortcuts (pipe duct, laundry chute).
-- Walls: tiled to shoulder height, cream paint peeling off the plaster to the
-- brick, damp stains; pipes, cable runs and cold fluorescent fittings overhead.
--
-- Furniture: every spot is marked (HollowWard.PropSpots). If a model with the
-- same name is in ServerStorage.AsylumProps (import the FBX files there), it's
-- placed there and set down on the floor by raycast; otherwise a grey stand-in
-- box is placed. After importing the FBX files later, run PlaceHollowProps.lua.
--
-- Running it again replaces the old HollowWard.

local ORIGIN = CFrame.new(1500, 200, 0)   -- where the lift lobby's floor is (far from your other maps)
local SEED = 1961

-- (optional) the ward's own surfaces: upload the PNGs from assets/AsylumFurniture/Textures
-- (Asset Manager > Images) and paste the IDs. Left empty, plain Roblox materials are used.
local TEXTURES = {
	WardPeelingPaint = { base = "Plaster", color = "", normal = "", roughness = "", studs = 12 },
	WardStainedPlaster = { base = "Plaster", color = "", normal = "", roughness = "", studs = 8 },
	WardFloor = { base = "Concrete", color = "", normal = "", roughness = "", studs = 14 },
}

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local rnd = Random.new(SEED)

local old = Workspace:FindFirstChild("HollowWard")
if old then
	old:Destroy()
end
local ward = Instance.new("Model")
ward.Name = "HollowWard"
ward:SetAttribute("HollowWard", true)
local folders = {}
local function folder(name)
	if not folders[name] then
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = ward
		folders[name] = f
	end
	return folders[name]
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local PALETTE = {
	paint = rgb(196, 190, 164),       -- old cream gloss
	paintGreen = rgb(128, 150, 132),  -- the coat under it
	plaster = rgb(150, 138, 118),
	brick = rgb(104, 62, 48),
	tile = rgb(150, 172, 156),        -- pale hospital green
	tileWhite = rgb(196, 198, 188),
	grout = rgb(70, 72, 64),
	floor = rgb(92, 88, 78),
	ceiling = rgb(150, 146, 132),
	stain = rgb(70, 58, 40),
	pipe = rgb(84, 70, 58),
	metal = rgb(96, 98, 96),
	padding = rgb(178, 172, 150),
}

-- every part: anchored, sensible defaults
local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CastShadow = true
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- local (x along the gallery, y up, z across) -> world
local function at(x, y, z, ry)
	return ORIGIN * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(ry or 0), 0)
end

--------------------------------------------------
-- THE PLAN
--------------------------------------------------
-- rect: x0, x1, z0 (north), z1 (south); h = ceiling height
-- doors: { side = "N"/"S"/"W"/"E", at = offset from the side's middle, w, h }
-- finish: "ward" | "clinical" | "cell" | "duct" | "lobby" | "wet"

local ROOMS = {
	{ name = "Lobby", x0 = 0, x1 = 14, z0 = -9, z1 = 9, h = 12, finish = "lobby",
		doors = { { side = "W", at = 0, w = 9, h = 9, lift = true }, { side = "E", at = 0, w = 10, h = 10 } } },
	{ name = "Gallery", x0 = 14, x1 = 74, z0 = -11, z1 = 11, h = 13, finish = "ward",
		doors = { { side = "W", at = 0, w = 10, h = 10 }, { side = "E", at = 0, w = 5, h = 8 },
			{ side = "N", at = 0, w = 6, h = 8.5 }, { side = "S", at = 2, w = 6, h = 8.5 } } },
	{ name = "NorthCorridor", x0 = 40, x1 = 48, z0 = -58, z1 = -11, h = 11, finish = "ward",
		doors = { { side = "S", at = 0, w = 6, h = 8.5 }, { side = "W", at = 13.5, w = 5, h = 8 },
			{ side = "E", at = 11.5, w = 5, h = 8 }, { side = "W", at = -6.5, w = 5, h = 8 },
			{ side = "E", at = -9.5, w = 5, h = 8 }, { side = "N", at = 0, w = 5, h = 8 } },
		windows = { { side = "W", at = 19, w = 4, y0 = 3.6, y1 = 7 } } },
	{ name = "NursesStation", x0 = 26, x1 = 40, z0 = -27, z1 = -13, h = 11, finish = "clinical",
		doors = { { side = "E", at = -1, w = 5, h = 8 } }, windows = { { side = "E", at = 4.5, w = 4, y0 = 3.6, y1 = 7 } } },
	{ name = "Pharmacy", x0 = 48, x1 = 62, z0 = -28, z1 = -14, h = 11, finish = "clinical",
		doors = { { side = "W", at = -2, w = 5, h = 8 }, { side = "E", at = -1, w = 4, h = 3.6, duct = true } } },
	{ name = "Surgery", x0 = 24, x1 = 40, z0 = -45, z1 = -29, h = 12, finish = "clinical",
		doors = { { side = "E", at = -4, w = 5, h = 8 } } },
	{ name = "Showers", x0 = 48, x1 = 62, z0 = -46, z1 = -30, h = 11, finish = "wet",
		doors = { { side = "W", at = -6, w = 5, h = 8 }, { side = "E", at = 4, w = 4, h = 3.6, duct = true } } },
	{ name = "Cells", x0 = 32, x1 = 56, z0 = -70, z1 = -58, h = 10, finish = "cell",
		doors = { { side = "S", at = 0, w = 5, h = 8 } } },
	{ name = "WardB", x0 = 30, x1 = 62, z0 = 11, z1 = 29, h = 12, finish = "ward",
		doors = { { side = "N", at = 0, w = 6, h = 8.5 }, { side = "E", at = -3, w = 4, h = 3.6, duct = true } } },
	{ name = "EastHall", x0 = 74, x1 = 86, z0 = -4, z1 = 4, h = 10, finish = "ward",
		doors = { { side = "W", at = 0, w = 5, h = 8 }, { side = "E", at = 0, w = 5, h = 8 } } },
	{ name = "MorgueStore", x0 = 86, x1 = 102, z0 = -10, z1 = 10, h = 10, finish = "clinical",
		doors = { { side = "W", at = 0, w = 5, h = 8 }, { side = "S", at = -2, w = 4, h = 3.6, duct = true } } },
	-- crouch-only: ward B -> the morgue store, behind the gallery's east end
	{ name = "PipeDuct", x0 = 62, x1 = 98, z0 = 14, z1 = 20, h = 3.6, finish = "duct",
		doors = { { side = "W", at = 0, w = 4, h = 3.6, duct = true }, { side = "N", at = 12, w = 4, h = 3.6, duct = true } } },
	{ name = "PipeDuctUp", x0 = 89, x1 = 95, z0 = 10, z1 = 14, h = 3.6, finish = "duct",
		doors = { { side = "N", at = 0, w = 4, h = 3.6, duct = true }, { side = "S", at = 0, w = 4, h = 3.6, duct = true } } },
	-- crouch-only: the laundry chute, pharmacy -> showers
	{ name = "LaundryChute", x0 = 62, x1 = 68, z0 = -38, z1 = -18, h = 3.6, finish = "duct",
		doors = { { side = "W", at = 6, w = 4, h = 3.6, duct = true }, { side = "W", at = -6, w = 4, h = 3.6, duct = true } } },
}
-- (every doorway's offset is worked out so it lines up with the room on the other
-- side: rooms are built inside their own rectangles, so neighbours' walls stand
-- back to back)

--------------------------------------------------
-- WALLS
--------------------------------------------------

local WALL = 1

local function sideInfo(r, side)
	-- start point, direction along the side, length, inward normal (local)
	if side == "N" then
		return Vector3.new(r.x0, 0, r.z0 + WALL / 2), Vector3.new(1, 0, 0), r.x1 - r.x0, Vector3.new(0, 0, 1)
	elseif side == "S" then
		return Vector3.new(r.x0, 0, r.z1 - WALL / 2), Vector3.new(1, 0, 0), r.x1 - r.x0, Vector3.new(0, 0, -1)
	elseif side == "W" then
		return Vector3.new(r.x0 + WALL / 2, 0, r.z0), Vector3.new(0, 0, 1), r.z1 - r.z0, Vector3.new(1, 0, 0)
	else
		return Vector3.new(r.x1 - WALL / 2, 0, r.z0), Vector3.new(0, 0, 1), r.z1 - r.z0, Vector3.new(-1, 0, 0)
	end
end

-- a block between two points along a wall, from y0 to y1 (local), thickness t, pushed in by `inset`
local function wallBlock(r, side, a, b, y0, y1, props, t, inset, parent)
	if b - a < 0.05 or y1 - y0 < 0.05 then
		return
	end
	local start, dir, _, normal = sideInfo(r, side)
	t = t or WALL
	local mid = start + dir * ((a + b) / 2) + normal * (inset or 0)
	local size = dir.X ~= 0 and Vector3.new(b - a, y1 - y0, t) or Vector3.new(t, y1 - y0, b - a)
	local p = part({ Size = size, CFrame = ORIGIN * CFrame.new(mid.X, (y0 + y1) / 2, mid.Z) }, parent)
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- the spans of a side that aren't doorways (for a given height band)
local function openSpans(r, side, len, y0, y1)
	local cuts = {}
	for _, d in ipairs(r.doors or {}) do
		if d.side == side and d.h > y0 then
			local mid = len / 2 + d.at
			table.insert(cuts, { mid - d.w / 2, mid + d.w / 2 })
		end
	end
	for _, wdw in ipairs(r.windows or {}) do
		if wdw.side == side and wdw.y1 > y0 and wdw.y0 < y1 then
			local mid = len / 2 + wdw.at
			table.insert(cuts, { mid - wdw.w / 2, mid + wdw.w / 2 })
		end
	end
	table.sort(cuts, function(p, q)
		return p[1] < q[1]
	end)
	local spans, pos = {}, 0
	for _, c in ipairs(cuts) do
		if c[1] > pos then
			table.insert(spans, { pos, c[1] })
		end
		pos = math.max(pos, c[2])
	end
	if pos < len then
		table.insert(spans, { pos, len })
	end
	return spans
end

local FINISH = {
	lobby = { wall = "paint", tileTo = 4.2, tile = "tile" },
	ward = { wall = "paint", tileTo = 4.5, tile = "tile" },
	clinical = { wall = "paint", tileTo = 7, tile = "tileWhite" },
	wet = { wall = "tileWhite", tileTo = 99, tile = "tileWhite" },
	cell = { wall = "padding", tileTo = 0 },
	duct = { wall = "metal", tileTo = 0 },
}

local function buildWalls(r, model)
	local f = FINISH[r.finish]
	for _, side in ipairs({ "N", "S", "W", "E" }) do
		local start, dir, len, normal = sideInfo(r, side)
		-- the wall itself, in bands so doorways cut it cleanly
		local bands = { 0 }
		for _, d in ipairs(r.doors or {}) do
			if d.side == side then
				table.insert(bands, d.h)
			end
		end
		for _, wdw in ipairs(r.windows or {}) do
			if wdw.side == side then
				table.insert(bands, wdw.y0)
				table.insert(bands, wdw.y1)
			end
		end
		table.insert(bands, r.h)
		table.sort(bands)
		for i = 1, #bands - 1 do
			local y0, y1 = bands[i], bands[i + 1]
			if y1 > y0 then
				for _, s in ipairs(openSpans(r, side, len, y0 + 0.01, y1)) do
					local mat = f.wall == "metal" and Enum.Material.DiamondPlate or Enum.Material.Plaster
					local col = PALETTE[f.wall] or PALETTE.paint
					wallBlock(r, side, s[1], s[2], y0, y1, { Material = mat, Color = col, Name = "Wall" }, WALL, 0, model)
				end
			end
		end
		-- tiled lower wall (green or white), its cap, and missing tiles showing grout and plaster
		if f.tileTo > 0 then
			local top = math.min(f.tileTo, r.h)
			for _, s in ipairs(openSpans(r, side, len, 0, top)) do
				wallBlock(r, side, s[1], s[2], 0, top, { Material = Enum.Material.CeramicTiles, Color = PALETTE[f.tile],
					Name = "Tiles" }, 0.12, WALL / 2 + 0.06, model)
				if top < r.h then
					wallBlock(r, side, s[1], s[2], top, top + 0.22, { Material = Enum.Material.SmoothPlastic,
						Color = PALETTE.tile:Lerp(PALETTE.grout, 0.45), Name = "TileCap" }, 0.22, WALL / 2 + 0.11, model)
				end
				local n = math.floor((s[2] - s[1]) / 3)
				for _ = 1, n do
					local a = rnd:NextNumber(s[1] + 0.5, s[2] - 0.8)
					local y = rnd:NextNumber(0.4, top - 0.6)
					local w, hh = 0.5 * rnd:NextInteger(1, 3), 0.5 * rnd:NextInteger(1, 2)
					if a + w < s[2] and y + hh < top then
						wallBlock(r, side, a, a + w, y, y + hh, { Material = Enum.Material.Concrete, Color = PALETTE.grout,
							Name = "MissingTile" }, 0.05, WALL / 2 + 0.135, model)
					end
				end
			end
		end
		-- peeling paint: patches of bare plaster and brick above the tiles
		if f.wall == "paint" then
			for _, s in ipairs(openSpans(r, side, len, f.tileTo, r.h)) do
				local n = math.floor((s[2] - s[1]) / 5)
				for _ = 1, n do
					local cx = rnd:NextNumber(s[1] + 1, s[2] - 1)
					local cy = rnd:NextNumber(f.tileTo + 0.8, r.h - 1)
					for k = 1, rnd:NextInteger(3, 6) do
						local w = rnd:NextNumber(0.6, 2.6)
						local hh = rnd:NextNumber(0.4, 1.8)
						local a = math.clamp(cx + rnd:NextNumber(-1.2, 1.2), s[1] + 0.1, s[2] - w - 0.1)
						local y = math.clamp(cy + rnd:NextNumber(-0.8, 0.8), f.tileTo + 0.1, r.h - hh - 0.1)
						local brick = k == 1 and rnd:NextNumber() < 0.5
						wallBlock(r, side, a, a + w, y, y + hh, {
							Material = brick and Enum.Material.Brick or Enum.Material.Plaster,
							Color = brick and PALETTE.brick or (rnd:NextNumber() < 0.5 and PALETTE.plaster or PALETTE.paintGreen),
							Name = "Peel" }, 0.04, WALL / 2 + 0.02 + (brick and 0.005 or 0.012) * k, model)
					end
				end
				-- damp: dark runs down from the ceiling
				for _ = 1, math.floor((s[2] - s[1]) / 7) do
					local a = rnd:NextNumber(s[1] + 0.5, s[2] - 1.5)
					local hh = rnd:NextNumber(2, r.h - f.tileTo - 0.5)
					local p = wallBlock(r, side, a, a + rnd:NextNumber(0.3, 1.4), r.h - hh, r.h, { Material = Enum.Material.Plaster,
						Color = PALETTE.stain, Transparency = 0.55, CastShadow = false, Name = "Damp" }, 0.03, WALL / 2 + 0.09, model)
					if p then
						p.CanCollide = false
						p.CanQuery = false
					end
				end
			end
		end
		-- padded cells: quilted squares
		if r.finish == "cell" then
			for _, s in ipairs(openSpans(r, side, len, 0, r.h)) do
				local a = s[1] + 0.2
				while a + 1.6 < s[2] do
					local y = 0.2
					while y + 1.6 < r.h - 0.2 do
						wallBlock(r, side, a, a + 1.5, y, y + 1.5, { Material = Enum.Material.Fabric,
							Color = PALETTE.padding:Lerp(PALETTE.stain, rnd:NextNumber(0, 0.45)), Name = "Pad" }, 0.35,
							WALL / 2 + 0.18, model)
						y += 1.6
					end
					a += 1.6
				end
			end
		end
		-- grime at the skirting
		for _, s in ipairs(openSpans(r, side, len, 0, 0.6)) do
			local p = wallBlock(r, side, s[1], s[2], 0, 0.55, { Material = Enum.Material.Concrete, Color = PALETTE.stain,
				Transparency = 0.35, CastShadow = false, Name = "Grime" }, 0.02, WALL / 2 + 0.16, model)
			if p then
				p.CanCollide = false
			end
		end
		-- door frames
		for _, d in ipairs(r.doors or {}) do
			if d.side == side and not d.duct and not d.lift then
				local mid = len / 2 + d.at
				for _, e in ipairs({ mid - d.w / 2, mid + d.w / 2 }) do
					wallBlock(r, side, e - 0.2, e + 0.2, 0, d.h, { Material = Enum.Material.Wood, Color = rgb(74, 62, 48),
						Name = "Frame" }, WALL + 0.3, 0, model)
				end
				wallBlock(r, side, mid - d.w / 2 - 0.2, mid + d.w / 2 + 0.2, d.h, d.h + 0.35, { Material = Enum.Material.Wood,
					Color = rgb(74, 62, 48), Name = "Frame" }, WALL + 0.3, 0, model)
			elseif d.side == side and d.duct then
				-- a duct opening: a torn-off grille hanging from one screw
				local mid = len / 2 + d.at
				local g = wallBlock(r, side, mid - d.w / 2, mid + d.w / 2, 0, 0.2, { Material = Enum.Material.CorrodedMetal,
					Color = PALETTE.metal, Name = "DuctSill" }, WALL + 0.2, 0, model)
				local sx = start + dir * (mid + d.w / 2 - 0.3) + normal * (WALL / 2 + 0.15)
				part({ Name = "Grille", Size = Vector3.new(0.08, d.h - 0.4, d.w - 0.3), Material = Enum.Material.DiamondPlate,
					Color = PALETTE.metal, CFrame = ORIGIN * CFrame.new(sx.X, (d.h) / 2, sx.Z)
						* CFrame.Angles(0, dir.X ~= 0 and math.rad(90) or 0, math.rad(28)) * CFrame.new(0, 0, (d.w - 0.3) / 2) },
					model)
				_ = g
			end
		end
		_ = normal
	end
end

local function buildFloorCeiling(r, model)
	local w, d = r.x1 - r.x0, r.z1 - r.z0
	local cx, cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
	local floorMat = (r.finish == "wet" or r.finish == "clinical") and Enum.Material.CeramicTiles
		or (r.finish == "duct" and Enum.Material.DiamondPlate or Enum.Material.Concrete)
	local floorCol = r.finish == "wet" and rgb(120, 126, 118) or (r.finish == "duct" and PALETTE.metal or PALETTE.floor)
	part({ Name = "Floor", Size = Vector3.new(w, 1, d), CFrame = ORIGIN * CFrame.new(cx, -0.5, cz), Material = floorMat,
		Color = floorCol }, model)
	part({ Name = "Ceiling", Size = Vector3.new(w, 1, d), CFrame = ORIGIN * CFrame.new(cx, r.h + 0.5, cz),
		Material = Enum.Material.Plaster, Color = r.finish == "duct" and PALETTE.metal or PALETTE.ceiling }, model)
	-- floor muck: dark patches and pools
	for _ = 1, math.floor(w * d / 60) do
		local s = rnd:NextNumber(1.5, 5)
		local p = part({ Name = "Muck", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, s, s * rnd:NextNumber(0.6, 1.2)),
			CFrame = ORIGIN * CFrame.new(rnd:NextNumber(r.x0 + 1, r.x1 - 1), 0.012, rnd:NextNumber(r.z0 + 1, r.z1 - 1))
				* CFrame.Angles(0, rnd:NextNumber(0, math.pi), math.rad(90)),
			Material = Enum.Material.Concrete, Color = PALETTE.stain, Transparency = 0.45, CastShadow = false,
			CanCollide = false, CanQuery = false }, model)
		_ = p
	end
	-- the shower room's standing water
	if r.finish == "wet" then
		part({ Name = "Water", Size = Vector3.new(w - 2.4, 0.25, d - 2.4), CFrame = ORIGIN * CFrame.new(cx, 0.08, cz),
			Material = Enum.Material.Glass, Color = rgb(40, 52, 46), Transparency = 0.35, Reflectance = 0.15,
			CanCollide = false, CastShadow = false }, model)
	end
	-- damp patches on the ceiling
	for _ = 1, math.floor(w * d / 90) do
		local s = rnd:NextNumber(2, 6)
		part({ Name = "CeilingDamp", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, s, s),
			CFrame = ORIGIN * CFrame.new(rnd:NextNumber(r.x0 + 2, r.x1 - 2), r.h - 0.012, rnd:NextNumber(r.z0 + 2, r.z1 - 2))
				* CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Plaster, Color = PALETTE.stain, Transparency = 0.5, CastShadow = false,
			CanCollide = false, CanQuery = false }, model)
	end
end

--------------------------------------------------
-- LIGHTS: cold fluorescent fittings (some dead, some flickering)
--------------------------------------------------

local lights = folder("Lights")
local bankCount = 0

local function tubeFitting(x, y, z, ry, props)
	props = props or {}
	local m = Instance.new("Model")
	m.Name = "Fitting"
	local cf = at(x, y, z, ry)
	part({ Name = "Housing", Size = Vector3.new(4.4, 0.35, 1.1), CFrame = cf * CFrame.new(0, -0.6, 0),
		Material = Enum.Material.Metal, Color = rgb(170, 172, 166) }, m)
	for _, s in ipairs({ -1, 1 }) do
		part({ Name = "Chain", Size = Vector3.new(0.06, 0.45, 0.06), CFrame = cf * CFrame.new(s * 1.8, -0.22, 0),
			Material = Enum.Material.Metal, Color = PALETTE.metal, CastShadow = false }, m)
	end
	local dead = props.dead
	local tubes = {}
	for _, s in ipairs({ -0.25, 0.25 }) do
		local t = part({ Name = "Tube", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.1, 0.2, 0.2),
			CFrame = cf * CFrame.new(0, -0.85, s), Material = dead and Enum.Material.Glass or Enum.Material.Neon,
			Color = dead and rgb(120, 124, 120) or rgb(196, 222, 236), CastShadow = false }, m)
		table.insert(tubes, t)
	end
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 120
	light.Range = props.range or 20
	light.Brightness = props.brightness or 1.25
	light.Color = rgb(180, 208, 232)
	light.Shadows = true
	light.Enabled = not dead
	light.Parent = m.Housing
	-- (a little glow round the tubes too)
	local glow = Instance.new("PointLight")
	glow.Range = 7
	glow.Brightness = 0.35
	glow.Color = rgb(170, 200, 228)
	glow.Shadows = false
	glow.Enabled = not dead
	glow.Parent = tubes[1]
	m:SetAttribute("Dead", dead == true)
	m:SetAttribute("Flicker", props.flicker == true)
	if props.bank then
		m:SetAttribute("Bank", props.bank)
		bankCount = math.max(bankCount, props.bank)
	end
	m.Parent = lights
	return m
end

local function cageLamp(x, y, z)
	local m = Instance.new("Model")
	m.Name = "CageLamp"
	local cf = at(x, y, z)
	part({ Name = "Mount", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 0.7, 0.7), CFrame = cf * CFrame.new(0, -0.1, 0)
		* CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Metal, Color = PALETTE.metal }, m)
	local bulb = part({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45),
		CFrame = cf * CFrame.new(0, -0.45, 0), Material = Enum.Material.Neon, Color = rgb(206, 220, 226), CastShadow = false }, m)
	for i = 0, 3 do
		local a = i * math.pi / 2
		part({ Name = "Cage", Size = Vector3.new(0.05, 0.6, 0.05), CFrame = cf * CFrame.new(math.cos(a) * 0.32, -0.45, math.sin(a) * 0.32),
			Material = Enum.Material.Metal, Color = PALETTE.metal, CastShadow = true }, m)
	end
	local l = Instance.new("PointLight")
	l.Range = 14
	l.Brightness = 1.1
	l.Color = rgb(184, 210, 228)
	l.Shadows = true
	l.Parent = bulb
	m:SetAttribute("Flicker", rnd:NextNumber() < 0.5)
	m.Parent = lights
	return m
end

--------------------------------------------------
-- PIPES AND CABLES
--------------------------------------------------

local services = folder("Services")

local function pipeRun(a, b, radius, colour)
	-- a straight pipe between two local points, with flanges and wall brackets
	local pa, pb = ORIGIN * a, ORIGIN * b
	local len = (pb - pa).Magnitude
	local cf = CFrame.lookAt((pa + pb) / 2, pb) * CFrame.Angles(0, math.rad(90), 0)
	part({ Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, radius * 2, radius * 2), CFrame = cf,
		Material = Enum.Material.CorrodedMetal, Color = colour or PALETTE.pipe }, services)
	local step = 6
	for d = step / 2, len, step do
		local p = pa:Lerp(pb, d / len)
		local fcf = CFrame.lookAt(p, pb) * CFrame.Angles(0, math.rad(90), 0)
		part({ Name = "Flange", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, radius * 2.6, radius * 2.6),
			CFrame = fcf, Material = Enum.Material.CorrodedMetal, Color = (colour or PALETTE.pipe):Lerp(Color3.new(), 0.25) }, services)
	end
end

local function cableRun(a, b, sag, count)
	-- a bundle of cables sagging between two points (local)
	for c = 1, count do
		local off = Vector3.new(0, -0.12 * c, 0.1 * (c - count / 2))
		local prev
		for i = 0, 8 do
			local u = i / 8
			local p = a:Lerp(b, u) + off - Vector3.new(0, sag * 4 * u * (1 - u) * (1 + 0.15 * c), 0)
			local wp = ORIGIN * p
			if prev then
				local len = (wp - prev).Magnitude
				part({ Name = "Cable", Shape = Enum.PartType.Cylinder, Size = Vector3.new(len + 0.05, 0.11, 0.11),
					CFrame = CFrame.lookAt((wp + prev) / 2, wp) * CFrame.Angles(0, math.rad(90), 0),
					Material = Enum.Material.Rubber, Color = rgb(22, 21, 20), CanCollide = false, CastShadow = true }, services)
			end
			prev = wp
		end
	end
end

--------------------------------------------------
-- BUILD THE ROOMS
--------------------------------------------------

local roomsFolder = folder("Rooms")
for _, r in ipairs(ROOMS) do
	local m = Instance.new("Model")
	m.Name = r.name
	m.Parent = roomsFolder
	buildWalls(r, m)
	buildFloorCeiling(r, m)
	-- the nurses' station window: dirty wired glass
	for _, wdw in ipairs(r.windows or {}) do
		local start, dir, len = sideInfo(r, wdw.side)
		local mid = start + dir * (len / 2 + wdw.at)
		part({ Name = "WiredGlass", Size = dir.X ~= 0 and Vector3.new(wdw.w, wdw.y1 - wdw.y0, 0.15)
			or Vector3.new(0.15, wdw.y1 - wdw.y0, wdw.w),
			CFrame = ORIGIN * CFrame.new(mid.X, (wdw.y0 + wdw.y1) / 2, mid.Z), Material = Enum.Material.Glass,
			Color = rgb(150, 170, 160), Transparency = 0.55 }, m)
	end
end

-- the lift: a car beyond the lobby's west wall, doors jammed half open
do
	local lift = Instance.new("Model")
	lift.Name = "Lift"
	lift.Parent = ward
	part({ Name = "CarFloor", Size = Vector3.new(7, 1, 9), CFrame = at(-3.5, -0.5, 0), Material = Enum.Material.DiamondPlate,
		Color = PALETTE.metal }, lift)
	part({ Name = "CarCeiling", Size = Vector3.new(7, 1, 9), CFrame = at(-3.5, 9.5, 0), Material = Enum.Material.Metal,
		Color = rgb(70, 70, 66) }, lift)
	for _, z in ipairs({ -4.5, 4.5 }) do
		part({ Name = "CarWall", Size = Vector3.new(7, 9, 0.4), CFrame = at(-3.5, 4.5, z), Material = Enum.Material.Metal,
			Color = rgb(110, 100, 84) }, lift)
	end
	part({ Name = "CarBack", Size = Vector3.new(0.4, 9, 9), CFrame = at(-7, 4.5, 0), Material = Enum.Material.Metal,
		Color = rgb(110, 100, 84) }, lift)
	part({ Name = "Rail", Size = Vector3.new(0.2, 0.2, 7), CFrame = at(-6.6, 3.4, 0), Material = Enum.Material.Metal,
		Color = rgb(150, 140, 110) }, lift)
	for _, z in ipairs({ -3.4, 3.4 }) do
		part({ Name = "LiftDoor", Size = Vector3.new(0.3, 9, 2.4), CFrame = at(0.2, 4.5, z), Material = Enum.Material.Metal,
			Color = rgb(96, 92, 80) }, lift)
	end
	local zone = part({ Name = "LiftZone", Size = Vector3.new(6.5, 8, 8.5), CFrame = at(-3.5, 4, 0), Transparency = 1,
		CanCollide = false, CanQuery = false, CanTouch = true }, lift)
	zone:SetAttribute("LiftZone", true)
	local lamp = cageLamp(-3.5, 9, 0)
	lamp.Parent = lift
	for _, z in ipairs({ -1.5, 1.5 }) do
		part({ Name = "Spawn", Size = Vector3.new(1, 0.2, 1), CFrame = at(-3.5, 0.1, z), Transparency = 1, CanCollide = false,
			CanQuery = false }, lift):SetAttribute("Spawn", true)
	end
end

-- gallery fittings: the banks that die toward you (1 = far end)
do
	local xs = { 70, 63, 56, 49, 42, 35, 28, 21 }
	for i, x in ipairs(xs) do
		tubeFitting(x, 13, -3.5, 0, { bank = i, flicker = i == 3 or i == 6, range = 22 })
		tubeFitting(x, 13, 3.5, 0, { bank = i, dead = i == 5, range = 22 })
	end
	tubeFitting(7, 12, 0, 90, { bank = #xs + 1, range = 18 })
	-- pipes along the gallery's north wall, cables slung along the south
	pipeRun(Vector3.new(14.5, 11.6, -9.45), Vector3.new(73.5, 11.6, -9.45), 0.45)
	pipeRun(Vector3.new(14.5, 10.6, -9.6), Vector3.new(73.5, 10.6, -9.6), 0.3, rgb(60, 66, 60))
	for x = 16, 70, 9 do
		cableRun(Vector3.new(x, 12.3, 9.6), Vector3.new(x + 9, 12.3, 9.6), 0.8, 3)
	end
end

-- fittings everywhere else
local fittingSpots = {
	{ 44, 11, -18, 90 }, { 44, 11, -30, 90, flicker = true }, { 44, 11, -42, 90, dead = true }, { 44, 11, -53, 90 },
	{ 33, 11, -20, 0 }, { 55, 11, -21, 0, flicker = true }, { 28, 12, -33, 0 }, { 56, 11, -38, 0, dead = true },
	{ 46, 12, 20, 0 }, { 38, 12, 20, 0, flicker = true }, { 54, 12, 20, 0 }, { 80, 10, 0, 90 }, { 94, 10, 0, 90, flicker = true },
}
for _, s in ipairs(fittingSpots) do
	tubeFitting(s[1], s[2], s[3], s[4], { dead = s.dead, flicker = s.flicker })
end
for _, x in ipairs({ 36, 44, 52 }) do
	cageLamp(x, 10, -64)
end
for _, s in ipairs({ { 66, 3.6, 17 }, { 80, 3.6, 17 }, { 92, 3.6, 12.5 }, { 65, 3.6, -28 } }) do
	local l = cageLamp(s[1], s[2], s[3])
	l:FindFirstChild("Bulb"):FindFirstChildOfClass("PointLight").Brightness = 0.5
end
-- corridor services
pipeRun(Vector3.new(41.5, 10, -11.5), Vector3.new(41.5, 10, -57.5), 0.4)
cableRun(Vector3.new(46.6, 10.4, -12), Vector3.new(46.6, 10.4, -30), 1, 2)
cableRun(Vector3.new(46.6, 10.4, -30), Vector3.new(46.6, 10.4, -56), 1, 2)
-- the ducts are crammed with pipes
pipeRun(Vector3.new(62, 2.9, 15.5), Vector3.new(98, 2.9, 15.5), 0.3)
pipeRun(Vector3.new(62, 0.5, 18.4), Vector3.new(98, 0.5, 18.4), 0.35, rgb(60, 66, 60))
pipeRun(Vector3.new(63.4, 3, -18.5), Vector3.new(63.4, 3, -37.5), 0.25)

--------------------------------------------------
-- MARKERS: furniture spots, patients, pharmacy, signs, zones
--------------------------------------------------

local spots = folder("PropSpots")
local function spot(prop, x, z, ry, attrs)
	local p = part({ Name = prop, Size = Vector3.new(1, 0.2, 1), CFrame = at(x, 0.1, z, ry), Transparency = 1, CanCollide = false,
		CanQuery = false }, spots)
	p:SetAttribute("Prop", prop)
	for k, v in pairs(attrs or {}) do
		p:SetAttribute(k, v)
	end
	return p
end

-- the gallery: five beds a side, heads to the wall (patients in six of them)
local patientBeds = { [1] = true, [3] = true, [4] = true, [7] = true, [8] = true }
local bedIndex = 0
for _, x in ipairs({ 20, 30, 40, 50, 60 }) do
	for _, side in ipairs({ -1, 1 }) do
		bedIndex += 1
		spot("HospitalBed", x, side * 7.2, side > 0 and 180 or 0,
			{ Patient = patientBeds[bedIndex] == true, Room = "Gallery" })
		if bedIndex % 3 == 0 then
			spot("BedsideCabinet", x + 2.4, side * 9.3, side > 0 and 180 or 0)
		end
	end
end
spot("PrivacyScreen", 46, -6.4, 20)
spot("IVStand", 41.6, 4.5, 0)
spot("IVStand", 22.2, -4.6, 0)
spot("Wheelchair", 66, 2, -110)
-- ward B: four beds, one patient
for i, x in ipairs({ 36, 44, 52, 58 }) do
	spot("HospitalBed", x, 24.6, 180, { Patient = i == 3, Room = "WardB" })
end
spot("IVStand", 46.5, 21, 0)
spot("BedsideCabinet", 40, 27.3, 180)
spot("PrivacyScreen", 33, 16, -15)
-- north wing
spot("Gurney", 44, -36, 90)
spot("Wheelchair", 42, -50, 160)
spot("OperatingTable", 32, -37, 0)
spot("SurgicalLamp", 32, -37, 0, { Ceiling = true })
spot("ExamChair", 27.5, -31.5, 140)
spot("InstrumentTrolley", 35.6, -35.5, 0)
spot("AnesthesiaCart", 28, -41.5, 30)
spot("MedicineCabinet", 55, -27, 180)
spot("MedicineCabinet", 49, -24, 90)
spot("FilingCabinet", 27, -15, 0)
spot("FilingCabinet", 29, -15, 8)
spot("BedsideCabinet", 36, -25.5, 180)
spot("WallSink", 63, -31, 180)
spot("WallSink", 39.3, -40, -90)
spot("Gurney", 96, -6, 0)
spot("Gurney", 92, 3, 15)
spot("Wheelchair", 99, 6, -40)
spot("RestraintChair", 38, -66, 0)
spot("HydrotherapyTub", 56, -42, 90)
spot("ECTMachine", 34, -42.5, 0)

-- the pharmacy shelf the sedative vials come from
do
	local shelf = Instance.new("Model")
	shelf.Name = "VialShelf"
	shelf.Parent = ward
	local base = at(55, 0, -15.6, 180)
	part({ Name = "Shelf", Size = Vector3.new(6, 0.2, 1.4), CFrame = base * CFrame.new(0, 3.2, 0), Material = Enum.Material.Metal,
		Color = rgb(178, 172, 150) }, shelf)
	part({ Name = "ShelfLow", Size = Vector3.new(6, 0.2, 1.4), CFrame = base * CFrame.new(0, 1.4, 0), Material = Enum.Material.Metal,
		Color = rgb(178, 172, 150) }, shelf)
	for _, x in ipairs({ -2.9, 2.9 }) do
		part({ Name = "Upright", Size = Vector3.new(0.2, 4.6, 1.4), CFrame = base * CFrame.new(x, 2.3, 0), Material = Enum.Material.Metal,
			Color = rgb(150, 146, 128) }, shelf)
	end
	local tray = part({ Name = "Tray", Size = Vector3.new(4.8, 0.3, 1), CFrame = base * CFrame.new(0, 3.45, 0),
		Material = Enum.Material.Metal, Color = rgb(120, 122, 118) }, shelf)
	for i = 0, 11 do
		part({ Name = "Vial", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 0.16, 0.16),
			CFrame = base * CFrame.new(-2.1 + (i % 6) * 0.8, 3.82, (i < 6) and -0.2 or 0.2) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Glass, Color = rgb(150, 190, 170), Transparency = 0.2 }, shelf)
	end
	shelf.PrimaryPart = tray
	shelf:SetAttribute("VialShelf", true)
end

-- countdown signs: TIME TO WAKE (the far end of the gallery is the one in the cinematic)
local signs = folder("Signs")
local function sign(x, y, z, ry, scale)
	scale = scale or 1
	local m = Instance.new("Model")
	m.Name = "WakeSign"
	local cf = at(x, y, z, ry)
	local board = part({ Name = "Board", Size = Vector3.new(5 * scale, 2.2 * scale, 0.4), CFrame = cf, Material = Enum.Material.Metal,
		Color = rgb(18, 16, 15) }, m)
	part({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6) * scale,
		CFrame = cf * CFrame.new(-2.9 * scale, 0, 0), Material = Enum.Material.SmoothPlastic, Color = rgb(90, 14, 12) }, m)
	for _, s in ipairs({ -1, 1 }) do
		part({ Name = "Rod", Size = Vector3.new(0.08, 2, 0.08), CFrame = cf * CFrame.new(s * 2 * scale, 1.1 * scale + 1, 0),
			Material = Enum.Material.Metal, Color = PALETTE.metal, CastShadow = false }, m)
	end
	m.PrimaryPart = board
	m.Parent = signs
	return m
end
-- (a sign's face is its front: ry 90 faces back down the gallery toward the lift)
sign(73.2, 8.5, 0, 90, 1.4)
sign(44, 8, -56.9, 180)
sign(46, 8.5, 28.2, 0)
sign(1.2, 8.5, 0, -90)

-- zones
local zone = part({ Name = "WardZone", Size = Vector3.new(120, 20, 110), CFrame = at(50, 8, -20), Transparency = 1,
	CanCollide = false, CanQuery = false, CanTouch = false }, ward)
zone:SetAttribute("WardZone", true)
part({ Name = "CinematicLook", Size = Vector3.new(1, 1, 1), CFrame = at(72, 4.5, 0), Transparency = 1, CanCollide = false,
	CanQuery = false }, ward)

-- the light scheme while you're in here (applied on your screen by HollowWardClient)
ward:SetAttribute("Ambient", rgb(18, 22, 28))
ward:SetAttribute("OutdoorAmbient", rgb(10, 12, 16))
ward:SetAttribute("Brightness", 0)
ward:SetAttribute("Exposure", -0.15)
ward:SetAttribute("FogColor", rgb(14, 18, 22))
ward:SetAttribute("FogEnd", 140)
ward:SetAttribute("Banks", bankCount)
ward:SetAttribute("BlitzState", "Idle")

-- the ward's own surfaces (if their textures were given)
do
	local MaterialService = game:GetService("MaterialService")
	local ready = {}
	for name, t in pairs(TEXTURES) do
		if t.color ~= "" then
			local v = MaterialService:FindFirstChild(name) or Instance.new("MaterialVariant")
			v.Name = name
			v.BaseMaterial = Enum.Material[t.base]
			v.ColorMap = t.color
			v.NormalMap = t.normal
			v.RoughnessMap = t.roughness
			v.StudsPerTile = t.studs
			v.Parent = MaterialService
			ready[name] = true
		end
	end
	if next(ready) then
		for _, d in ipairs(ward:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "Wall" and d.Material == Enum.Material.Plaster and ready.WardPeelingPaint then
					d.MaterialVariant = "WardPeelingPaint"
					d.Color = Color3.new(1, 1, 1)
				elseif (d.Name == "Peel" or d.Name == "Ceiling") and d.Material == Enum.Material.Plaster and ready.WardStainedPlaster then
					d.MaterialVariant = "WardStainedPlaster"
				elseif d.Name == "Floor" and d.Material == Enum.Material.Concrete and ready.WardFloor then
					d.MaterialVariant = "WardFloor"
					d.Color = Color3.new(1, 1, 1)
				end
			end
		end
	end
end

ward.WorldPivot = ORIGIN
ward.Parent = Workspace

--------------------------------------------------
-- FURNITURE
--------------------------------------------------

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

print(("HollowWard built at %s: %d parts"):format(tostring(ORIGIN.Position), #ward:GetDescendants()))
