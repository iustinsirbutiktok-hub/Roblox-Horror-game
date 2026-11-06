-- A small stand-in for the bits of Roblox's Luau API that StitcherPose uses
-- (Vector3, CFrame, Random, math.noise, math.clamp), for running it outside Studio.
local sqrt, sin, cos, abs = math.sqrt, math.sin, math.cos, math.abs

Vector3 = {}
local VM = {}
local function vec(x, y, z)
	return setmetatable({ x, y, z }, VM)
end
Vector3.new = function(x, y, z) return vec(x or 0, y or 0, z or 0) end
Vector3.zero = vec(0, 0, 0)
local Vmethods = {
	Dot = function(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end,
	Cross = function(a, b) return vec(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]) end,
	Lerp = function(a, b, t) return vec(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t) end,
}
VM.__index = function(v, k)
	if k == "X" then return v[1] elseif k == "Y" then return v[2] elseif k == "Z" then return v[3]
	elseif k == "Magnitude" then return sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
	elseif k == "Unit" then
		local m = sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
		if m == 0 then return vec(0 / 0, 0 / 0, 0 / 0) end
		return vec(v[1] / m, v[2] / m, v[3] / m)
	end
	local f = Vmethods[k]
	if f then return f end
	error("Vector3 has no member " .. tostring(k), 2)
end
VM.__add = function(a, b) assert(getmetatable(b) == VM and getmetatable(a) == VM, "Vector3 + non-Vector3"); return vec(a[1] + b[1], a[2] + b[2], a[3] + b[3]) end
VM.__sub = function(a, b) assert(getmetatable(b) == VM and getmetatable(a) == VM, "Vector3 - non-Vector3"); return vec(a[1] - b[1], a[2] - b[2], a[3] - b[3]) end
VM.__unm = function(a) return vec(-a[1], -a[2], -a[3]) end
VM.__mul = function(a, b)
	if type(a) == "number" then return vec(a * b[1], a * b[2], a * b[3]) end
	if type(b) == "number" then return vec(a[1] * b, a[2] * b, a[3] * b) end
	return vec(a[1] * b[1], a[2] * b[2], a[3] * b[3])
end
VM.__div = function(a, b)
	assert(type(b) == "number", "Vector3 / non-number")
	return vec(a[1] / b, a[2] / b, a[3] / b)
end
VM.__tostring = function(v) return string.format("(%.3f, %.3f, %.3f)", v[1], v[2], v[3]) end
VM.__eq = function(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
IsVector3 = function(v) return getmetatable(v) == VM end

-- CFrame: position p (Vector3) and rotation rows r = {r00..r22} (row-major)
CFrame = {}
local CM = {}
local function cf(px, py, pz, r)
	return setmetatable({ px = px, py = py, pz = pz, r = r }, CM)
end
local I = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function matmul(a, b)
	local o = {}
	for i = 0, 2 do
		for j = 0, 2 do
			o[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[j + 4] + a[i * 3 + 3] * b[j + 7]
		end
	end
	return o
end
local function transpose(a)
	return { a[1], a[4], a[7], a[2], a[5], a[8], a[3], a[6], a[9] }
end
local function rotv(r, x, y, z)
	return r[1] * x + r[2] * y + r[3] * z, r[4] * x + r[5] * y + r[6] * z, r[7] * x + r[8] * y + r[9] * z
end
CFrame.new = function(a, b, c)
	if a == nil then return cf(0, 0, 0, I) end
	if type(a) == "table" then return cf(a[1], a[2], a[3], I) end
	return cf(a, b, c, I)
end
CFrame.identity = cf(0, 0, 0, I)
local function rx(a) local c, s = cos(a), sin(a); return { 1, 0, 0, 0, c, -s, 0, s, c } end
local function ry(a) local c, s = cos(a), sin(a); return { c, 0, s, 0, 1, 0, -s, 0, c } end
local function rz(a) local c, s = cos(a), sin(a); return { c, -s, 0, s, c, 0, 0, 0, 1 } end
CFrame.Angles = function(x, y, z)
	return cf(0, 0, 0, matmul(matmul(rx(x), ry(y)), rz(z)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromAxisAngle = function(axis, a)
	local u = axis.Unit
	local x, y, z = u[1], u[2], u[3]
	local c, s = cos(a), sin(a)
	local t = 1 - c
	assert(x == x, "fromAxisAngle: NaN axis")
	return cf(0, 0, 0, { t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c })
end
CFrame.fromMatrix = function(p, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return cf(p[1], p[2], p[3], { vx[1], vy[1], vz[1], vx[2], vy[2], vz[2], vx[3], vy[3], vz[3] })
end
local function toquat(r)
	local tr = r[1] + r[5] + r[9]
	local w, x, y, z
	if tr > 0 then
		local s = sqrt(tr + 1) * 2
		w, x, y, z = 0.25 * s, (r[8] - r[6]) / s, (r[3] - r[7]) / s, (r[4] - r[2]) / s
	elseif r[1] > r[5] and r[1] > r[9] then
		local s = sqrt(1 + r[1] - r[5] - r[9]) * 2
		w, x, y, z = (r[8] - r[6]) / s, 0.25 * s, (r[2] + r[4]) / s, (r[3] + r[7]) / s
	elseif r[5] > r[9] then
		local s = sqrt(1 + r[5] - r[1] - r[9]) * 2
		w, x, y, z = (r[3] - r[7]) / s, (r[2] + r[4]) / s, 0.25 * s, (r[6] + r[8]) / s
	else
		local s = sqrt(1 + r[9] - r[1] - r[5]) * 2
		w, x, y, z = (r[4] - r[2]) / s, (r[3] + r[7]) / s, (r[6] + r[8]) / s, 0.25 * s
	end
	return w, x, y, z
end
local function fromquat(w, x, y, z)
	local n = sqrt(w * w + x * x + y * y + z * z)
	w, x, y, z = w / n, x / n, y / n, z / n
	return { 1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y) }
end
local Cmethods = {
	Inverse = function(c)
		local rt = transpose(c.r)
		local x, y, z = rotv(rt, c.px, c.py, c.pz)
		return cf(-x, -y, -z, rt)
	end,
	Lerp = function(a, b, t)
		local w1, x1, y1, z1 = toquat(a.r)
		local w2, x2, y2, z2 = toquat(b.r)
		local d = w1 * w2 + x1 * x2 + y1 * y2 + z1 * z2
		if d < 0 then w2, x2, y2, z2, d = -w2, -x2, -y2, -z2, -d end
		local k1, k2
		if d > 0.9995 then
			k1, k2 = 1 - t, t
		else
			local th = math.acos(d)
			k1, k2 = sin((1 - t) * th) / sin(th), sin(t * th) / sin(th)
		end
		return cf(a.px + (b.px - a.px) * t, a.py + (b.py - a.py) * t, a.pz + (b.pz - a.pz) * t,
			fromquat(w1 * k1 + w2 * k2, x1 * k1 + x2 * k2, y1 * k1 + y2 * k2, z1 * k1 + z2 * k2))
	end,
	ToObjectSpace = function(a, b) return a:Inverse() * b end,
	PointToObjectSpace = function(a, v) return a:Inverse() * v end,
	VectorToObjectSpace = function(a, v) return vec(rotv(transpose(a.r), v[1], v[2], v[3])) end,
	VectorToWorldSpace = function(a, v) return vec(rotv(a.r, v[1], v[2], v[3])) end,
	PointToWorldSpace = function(a, v) return a * v end,
	GetComponents = function(c)
		local r = c.r
		return c.px, c.py, c.pz, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
	end,
}
CM.__index = function(c, k)
	if k == "Position" then return vec(c.px, c.py, c.pz)
	elseif k == "Rotation" then return cf(0, 0, 0, c.r)
	elseif k == "X" then return c.px elseif k == "Y" then return c.py elseif k == "Z" then return c.pz
	elseif k == "LookVector" then return vec(-c.r[3], -c.r[6], -c.r[9])
	elseif k == "RightVector" then return vec(c.r[1], c.r[4], c.r[7])
	elseif k == "UpVector" then return vec(c.r[2], c.r[5], c.r[8])
	end
	local f = Cmethods[k]
	if f then return f end
	error("CFrame has no member " .. tostring(k), 2)
end
CM.__mul = function(a, b)
	assert(getmetatable(a) == CM, "CFrame * : left side is not a CFrame")
	if getmetatable(b) == CM then
		local x, y, z = rotv(a.r, b.px, b.py, b.pz)
		return cf(a.px + x, a.py + y, a.pz + z, matmul(a.r, b.r))
	elseif getmetatable(b) == VM then
		local x, y, z = rotv(a.r, b[1], b[2], b[3])
		return vec(a.px + x, a.py + y, a.pz + z)
	end
	error("CFrame * " .. type(b), 2)
end
CM.__add = function(a, v) assert(getmetatable(v) == VM, "CFrame + non-Vector3"); return cf(a.px + v[1], a.py + v[2], a.pz + v[3], a.r) end
CM.__sub = function(a, v) assert(getmetatable(v) == VM, "CFrame - non-Vector3"); return cf(a.px - v[1], a.py - v[2], a.pz - v[3], a.r) end
IsCFrame = function(c) return getmetatable(c) == CM end

-- math extras
math.clamp = function(x, a, b)
	assert(a <= b, "math.clamp: min > max")
	if x < a then return a elseif x > b then return b end
	return x
end
local function hash(i, j, k)
	local n = i * 374761393 + j * 668265263 + k * 2147483647
	n = (n % 2147483647 + 2147483647) % 2147483647
	n = (n * 1103515245 + 12345) % 2147483648
	return (n / 2147483648) * 2 - 1
end
math.noise = function(x, y, z)
	-- a smooth value noise in about -0.5..0.5 (stands in for Roblox's Perlin noise)
	x, y, z = x or 0, y or 0, z or 0
	local xi, yi, zi = math.floor(x), math.floor(y), math.floor(z)
	local fx, fy, fz = x - xi, y - yi, z - zi
	local function s(t) return t * t * (3 - 2 * t) end
	local ux, uy, uz = s(fx), s(fy), s(fz)
	local function lerp(a, b, t) return a + (b - a) * t end
	local c = {}
	for dx = 0, 1 do for dy = 0, 1 do for dz = 0, 1 do
		c[dx * 4 + dy * 2 + dz] = hash(xi + dx, yi + dy, zi + dz)
	end end end
	local v = lerp(lerp(lerp(c[0], c[4], ux), lerp(c[2], c[6], ux), uy), lerp(lerp(c[1], c[5], ux), lerp(c[3], c[7], ux), uy), uz)
	return v * 0.5
end
table.clear = function(t) for k in pairs(t) do t[k] = nil end end

Random = {}
Random.new = function(seed)
	local state = (seed or 1) % 2147483647
	if state <= 0 then state = state + 2147483646 end
	local r = {}
	function r:NextNumber(a, b)
		state = (state * 16807) % 2147483647
		local u = state / 2147483647
		if a == nil then return u end
		return a + (b - a) * u
	end
	function r:NextInteger(a, b)
		return math.floor(self:NextNumber(a, b + 1 - 1e-9))
	end
	return r
end
