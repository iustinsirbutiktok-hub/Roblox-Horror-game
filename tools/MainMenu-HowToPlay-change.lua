-- MainMenu: one small change so HOW TO PLAY lists the journalists.
-- Open your MainMenu LocalScript, press Ctrl+F and search for:  THE SURVIVORS
-- Replace these lines:
--
--	bodyText("THE SURVIVORS", 0.46, 0.08, { TextColor3 = BONE })
--	local roles = { "ACROBAT  fast, slides, hard to catch", "MECHANIC  repairs, valves, long battery", "MEDIC  revives fast, starts with medicine",
--		"SCOUT  hears them coming, marks monsters", "BRUTE  150 health, carries the fallen" }
--
-- with these:

	bodyText("THE CREW", 0.46, 0.08, { TextColor3 = BONE })
	local roles = { "INES  photographer - her flash marks monsters", "DANNY  cameraman - long battery, fixes things", "CLAIRE  reporter - revives fast, first aid kit",
		"MARCUS  sound - hears them through walls", "TOMMY  intern - 135 health, carries the fallen" }
