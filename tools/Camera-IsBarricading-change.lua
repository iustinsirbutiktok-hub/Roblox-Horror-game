-- ThirdPersonHorrorCamera: one line so leaning on a door locks your body
-- (you can still look around ±80°, like when you're climbing or hiding).
--
-- In your ThirdPersonHorrorCamera LocalScript find the function
-- isExternallyControlled and add the IsBarricading line, so it reads:

local function isExternallyControlled()
	return character:GetAttribute("IsClimbing")
		or character:GetAttribute("IsCrawlingThrough")
		or character:GetAttribute("IsHanging")
		or character:GetAttribute("IsTurningValve")
		or character:GetAttribute("IsFuelAction")
		or character:GetAttribute("IsLeverPush")
		or character:GetAttribute("IsFuseRepair")
		or character:GetAttribute("IsTightSqueeze")
		or character:GetAttribute("IsAxeInspect")
		or character:GetAttribute("IsAxeChop")
		or character:GetAttribute("IsHiding")
		or character:GetAttribute("IsCoopClimbing")
		or character:GetAttribute("IsFusePickup")
		or character:GetAttribute("IsFuseInstall")
		or character:GetAttribute("IsBearTrapped")
		or character:GetAttribute("IsGeneratorStarting")
		or character:GetAttribute("BeingKilled")
		or character:GetAttribute("IsBarricading")      -- NEW: holding a door shut
end

-- (Keep any other lines your version has - just add the IsBarricading one.)
