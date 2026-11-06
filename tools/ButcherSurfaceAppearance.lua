-- ButcherSurfaceAppearance (Studio command bar, run once)
--
-- Gives every mesh of an imported TheButcher its full detail: a
-- SurfaceAppearance with the colour, normal and roughness maps from
-- assets/TheButcher. The importer only uses the colour texture, so the bump
-- detail (pores, cloth weave, wrinkles, crusted blood) and the wet shine of the
-- blood come from these.
--
-- 1. Upload the 18 PNGs in assets/TheButcher (Asset Manager > Images) and
--    paste their ids below (just the numbers).
-- 2. Select the imported model (or have it named TheButcher in Workspace).
-- 3. Paste this whole file into the command bar and press Enter.

local IDS = {
	ButcherBody = { Color = 0, Normal = 0, Roughness = 0 },
	ButcherHead = { Color = 0, Normal = 0, Roughness = 0 },
	ButcherHair = { Color = 0, Normal = 0, Roughness = 0 },
	ButcherApron = { Color = 0, Normal = 0, Roughness = 0 },
	ButcherBoots = { Color = 0, Normal = 0, Roughness = 0 },
	ButcherCleaver = { Color = 0, Normal = 0, Roughness = 0 },
}

local model = game:GetService("Selection"):Get()[1] or workspace:FindFirstChild("TheButcher")
assert(model, "select the imported Butcher first")
local done = 0
for _, part in ipairs(model:GetDescendants()) do
	if part:IsA("MeshPart") then
		local key
		for name in pairs(IDS) do
			if string.find(part.Name, name, 1, true) then
				key = name
			end
		end
		local ids = key and IDS[key]
		if ids and ids.Color ~= 0 then
			local old = part:FindFirstChildOfClass("SurfaceAppearance")
			if old then
				old:Destroy()
			end
			local sa = Instance.new("SurfaceAppearance")
			sa.ColorMap = "rbxassetid://" .. ids.Color
			if ids.Normal ~= 0 then
				sa.NormalMap = "rbxassetid://" .. ids.Normal
			end
			if ids.Roughness ~= 0 then
				sa.RoughnessMap = "rbxassetid://" .. ids.Roughness
			end
			sa.Parent = part
			done = done + 1
		end
	end
end
print(("ButcherSurfaceAppearance: %d meshes done"):format(done))
