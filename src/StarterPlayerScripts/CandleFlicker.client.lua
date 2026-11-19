-- CandleFlicker
-- Makes every light tagged "CandleLight" (tools/SetupMansion.lua tags the mansion's candle and lamp
-- lights) flicker like a flame: brightness and range wander on smooth noise, each light on its own.
-- Only lights near the camera are touched. A light that's switched off (Enabled = false) is left
-- alone, and BaseBrightness / BaseRange on the light set what it flickers around - so a script
-- can dim the candles or blow them out without fighting this one.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local NEAR = 160          -- studs: further away than this nobody sees the flicker
local DEPTH = 0.35        -- how deep the flicker goes (0 = steady)

local lights = {}

local function add(light)
	if light:IsA("Light") then
		lights[light] = math.random() * 1000
	end
end

for _, light in ipairs(CollectionService:GetTagged("CandleLight")) do
	add(light)
end
CollectionService:GetInstanceAddedSignal("CandleLight"):Connect(add)
CollectionService:GetInstanceRemovedSignal("CandleLight"):Connect(function(light)
	lights[light] = nil
end)

RunService.Heartbeat:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local t = os.clock()
	for light, seed in pairs(lights) do
		local part = light.Parent
		if part and part:IsA("BasePart") and light.Enabled and (part.Position - eye).Magnitude < NEAR then
			local base = light:GetAttribute("BaseBrightness") or 1
			local range = light:GetAttribute("BaseRange") or light.Range
			local n = math.noise(t * 5.5, seed) * 0.6 + math.noise(t * 17, seed + 31) * 0.4
			light.Brightness = base * (1 + n * DEPTH)
			light.Range = range * (1 + n * DEPTH * 0.25)
		end
	end
end)
