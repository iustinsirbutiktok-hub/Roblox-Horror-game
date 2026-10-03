-- PaintCrawler
-- Run ONCE in Studio: View > Command Bar, paste all of this, press Enter.
-- Then save your place. (Ctrl+Z undoes it if you don't like it.)
--
-- Gives Workspace.TheCrawler a dead, diseased skin using Roblox's built-in
-- materials (no uploads needed): grey corpse skin that darkens towards rotting
-- fingers and toes, bruised purple joints, bone pushing out along its spine,
-- ribs and hips, raw red sinew and muscle, black claws, yellowed teeth, wet
-- red gums and strings of drool. Every part gets a slightly different shade
-- so it doesn't look like flat plastic.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local monster = workspace:FindFirstChild("TheCrawler", true)
assert(monster, "Couldn't find TheCrawler in Workspace")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- first match wins, so the specific names come before the general ones
local RULES = {
	-- the mouth
	{ "MouthVoid", rgb(8, 3, 3), Enum.Material.SmoothPlastic, 0 },
	{ "UpperGum", rgb(104, 16, 22), Enum.Material.Glass, 0.05 },
	{ "LowerGum", rgb(96, 14, 20), Enum.Material.Glass, 0.05 },
	{ "Tongue", rgb(88, 28, 42), Enum.Material.Glass, 0.05 },
	{ "LowerFang", rgb(196, 178, 128), Enum.Material.Marble, 0.05 },
	{ "Fang", rgb(214, 198, 152), Enum.Material.Marble, 0.05 },
	{ "Strand", rgb(226, 214, 176), Enum.Material.Glass, 0.1, 0.35 },   -- drool
	{ "Chin", rgb(118, 62, 56), Enum.Material.Leather, 0 },             -- blood down its chin
	{ "Cheek", rgb(124, 66, 68), Enum.Material.Rubber, 0.02 },          -- skin split at the corners
	{ "Crease", rgb(92, 72, 70), Enum.Material.Leather, 0 },
	{ "Fold", rgb(104, 88, 84), Enum.Material.Leather, 0 },
	{ "Snout", rgb(146, 122, 116), Enum.Material.Leather, 0 },
	{ "Skull", rgb(162, 156, 146), Enum.Material.Leather, 0 },
	{ "Jaw", rgb(148, 132, 124), Enum.Material.Leather, 0 },
	{ "Head", rgb(156, 148, 138), Enum.Material.Leather, 0 },

	-- raw meat showing through
	{ "NeckSinew", rgb(112, 26, 28), Enum.Material.Fabric, 0.02 },
	{ "ForearmSinew", rgb(118, 30, 30), Enum.Material.Fabric, 0.02 },
	{ "Tendon", rgb(126, 40, 38), Enum.Material.Fabric, 0.02 },
	{ "Hamstring", rgb(132, 52, 50), Enum.Material.Fabric, 0.02 },

	-- bone pushing out
	{ "Spike", rgb(158, 144, 112), Enum.Material.Limestone, 0 },
	{ "Rib", rgb(196, 184, 154), Enum.Material.Limestone, 0 },
	{ "Pelvis", rgb(182, 168, 138), Enum.Material.Limestone, 0 },
	{ "Scapula", rgb(176, 162, 134), Enum.Material.Limestone, 0 },

	-- claws
	{ "ToeClaw", rgb(34, 26, 22), Enum.Material.SmoothPlastic, 0.12 },
	{ "Claw", rgb(46, 22, 20), Enum.Material.SmoothPlastic, 0.12 },     -- dark, crusted red

	-- rotting hands and feet: darker towards the tips
	{ "FingerTip", rgb(66, 52, 48), Enum.Material.Leather, 0 },
	{ "FingerJoint", rgb(92, 70, 72), Enum.Material.Rubber, 0 },
	{ "Finger", rgb(98, 84, 76), Enum.Material.Leather, 0 },
	{ "Thumb", rgb(98, 84, 76), Enum.Material.Leather, 0 },
	{ "Palm", rgb(112, 96, 88), Enum.Material.Leather, 0 },
	{ "Toe", rgb(90, 76, 68), Enum.Material.Leather, 0 },
	{ "Sole", rgb(84, 72, 64), Enum.Material.Leather, 0 },
	{ "Heel", rgb(96, 82, 74), Enum.Material.Leather, 0 },

	-- bruised, swollen joints
	{ "ShoulderKnob", rgb(126, 98, 104), Enum.Material.Rubber, 0.02 },
	{ "Elbow", rgb(120, 90, 98), Enum.Material.Rubber, 0.02 },
	{ "Knee", rgb(122, 92, 100), Enum.Material.Rubber, 0.02 },
	{ "Wrist", rgb(116, 90, 94), Enum.Material.Rubber, 0.02 },
	{ "Ankle", rgb(112, 88, 90), Enum.Material.Rubber, 0.02 },

	-- the long grey limbs
	{ "UpperArm", rgb(160, 152, 142), Enum.Material.Leather, 0 },
	{ "Bicep", rgb(150, 140, 132), Enum.Material.Leather, 0 },
	{ "Forearm", rgb(146, 136, 128), Enum.Material.Leather, 0 },
	{ "Thigh", rgb(156, 148, 138), Enum.Material.Leather, 0 },
	{ "Shin", rgb(140, 130, 122), Enum.Material.Leather, 0 },
	{ "Neck", rgb(152, 142, 134), Enum.Material.Leather, 0 },

	-- the body: paler belly, darker mottled back
	{ "Belly", rgb(176, 156, 146), Enum.Material.Leather, 0 },
	{ "Chest", rgb(168, 158, 148), Enum.Material.Leather, 0 },
	{ "Hump", rgb(128, 124, 118), Enum.Material.Leather, 0 },
	{ "Haunch", rgb(138, 132, 124), Enum.Material.Leather, 0 },
	{ "Body", rgb(150, 144, 136), Enum.Material.Leather, 0 },
}
local SKIN = { "", rgb(150, 142, 134), Enum.Material.Leather, 0 }

local function ruleFor(name)
	for _, rule in ipairs(RULES) do
		if name:sub(1, #rule[1]) == rule[1] then
			return rule
		end
	end
	return SKIN
end

-- the same small shade change every time for the same part
local function jitter(name)
	local h = 0
	for i = 1, #name do
		h = (h * 31 + name:byte(i)) % 1000003
	end
	return (h % 1000) / 1000 * 2 - 1
end

ChangeHistoryService:SetWaypoint("Before painting TheCrawler")
local painted = 0
for _, part in ipairs(monster:GetDescendants()) do
	if part:IsA("BasePart") and part.Transparency < 1 and part.Name ~= "HumanoidRootPart" then
		local rule = ruleFor(part.Name)
		local h, s, v = rule[2]:ToHSV()
		local j = jitter(part.Name)
		part.Color = Color3.fromHSV((h + j * 0.012) % 1, math.clamp(s * (1 + j * 0.15), 0, 1), math.clamp(v * (1 + j * 0.07), 0, 1))
		part.Material = rule[3]
		part.Reflectance = rule[4]
		if rule[5] then
			part.Transparency = rule[5]
		end
		painted += 1
	end
end
ChangeHistoryService:SetWaypoint("Painted TheCrawler")
print("Painted " .. painted .. " parts of TheCrawler. Save your place to keep it.")
