-- DoorConfig
-- Place in: ReplicatedStorage (a ModuleScript named exactly "DoorConfig")
--
-- Settings for the doors (built with BuildDoor), shared by DoorServer and
-- DoorClient. Three kinds:
--   Wood   a rotten plank cellar door: light, quick, creaky, splinters apart
--   Steel  a rusted boiler-room door: slow and heavy, rips off its hinges
--   Cell   a barred iron gate: you can see through it, squeals on its hinges

local DoorConfig = {}

--------------------------------------------------
-- USING DOORS
--------------------------------------------------

DoorConfig.USE_RANGE = 7.5           -- how close you have to be to open/close (left click)
DoorConfig.HOLD_RANGE = 6            -- how close to lean on it and hold it shut (E)
DoorConfig.HOLD_KEY = Enum.KeyCode.E
DoorConfig.CHASE_NEAR = 70           -- you can only hold a door while the Crawler is hunting within this far of it

--------------------------------------------------
-- HOLDING IT SHUT AGAINST THE CRAWLER
--------------------------------------------------

DoorConfig.WINS_TO_HOLD = { 7, 8 }   -- good pushes it takes before it gives up (picked at random)
DoorConfig.MISSES_TO_BREACH = 3      -- misses before the door bursts open
DoorConfig.ROUND_TIMEOUT = 7         -- no answer for this long counts as a miss
DoorConfig.GIVE_UP_TIME = 18         -- after it gives up, it ignores everyone this long

--------------------------------------------------
-- THE KINDS OF DOOR
--------------------------------------------------
-- openAngle  how far it swings open (degrees)
-- speed/bounce  how it moves: speed = how snappy, bounce = 0 wobbly .. 1 dead heavy
-- zone       how wide the light on the dial starts (degrees) - sturdier doors are easier
-- spin       how fast the blade goes round (degrees per second, at the start)

DoorConfig.TYPES = {
	Wood = {
		label = "CELLAR DOOR",
		openAngle = 96, speed = 7.5, bounce = 0.45,
		zone = 36, spin = 215,
		sounds = { open = "WoodOpen", close = "WoodClose", slam = "WoodSlam", hit = "WoodHit", breaks = "WoodBreak" },
	},
	Steel = {
		label = "BOILER ROOM",
		openAngle = 100, speed = 3.2, bounce = 0.9,
		zone = 46, spin = 195,
		sounds = { open = "SteelOpen", close = "SteelClose", slam = "SteelSlam", hit = "SteelHit", breaks = "SteelBreak" },
	},
	Cell = {
		label = "CELL GATE",
		openAngle = 108, speed = 5, bounce = 0.35,
		zone = 40, spin = 225,
		sounds = { open = "CellOpen", close = "CellClose", slam = "CellSlam", hit = "CellHit", breaks = "CellBreak" },
	},
}

--------------------------------------------------
-- SOUNDS
--------------------------------------------------
-- Same idea as CrawlerConfig: the filled ones are sounds your game already
-- uses, re-pitched; swap in better ones from Toolbox > Audio when you find them
-- (search the "find" words). A blank Id doesn't play.

DoorConfig.Sounds = {
	WoodOpen = { Id = "rbxassetid://9116522890", Volume = 0.6, Speed = 0.95, Range = 60, find = "old wooden door creak open" },
	WoodClose = { Id = "rbxassetid://9116673944", Volume = 0.55, Speed = 1.45, Range = 60, find = "wooden door close thud" },
	WoodSlam = { Id = "rbxassetid://9116673944", Volume = 1.4, Speed = 0.8, Range = 110, find = "heavy body slamming into wooden door" },
	WoodHit = { Id = "rbxassetid://9120805690", Volume = 0.7, Speed = 1.2, Range = 90, find = "wood creak strain crack" },
	WoodBreak = { Id = "rbxassetid://9120805690", Volume = 1.6, Speed = 0.8, Range = 160, find = "wooden door smashed splinter" },

	SteelOpen = { Id = "rbxassetid://9116522890", Volume = 0.8, Speed = 0.42, Range = 80, find = "heavy metal door groan open" },
	SteelClose = { Id = "rbxassetid://9116673944", Volume = 1.0, Speed = 0.55, Range = 90, find = "heavy steel door shut clang" },
	SteelSlam = { Id = "rbxassetid://9116673944", Volume = 1.6, Speed = 0.5, Range = 140, find = "loud metal door bang" },
	SteelHit = { Id = "rbxassetid://9116673944", Volume = 0.9, Speed = 0.42, Range = 110, find = "metal dent impact" },
	SteelBreak = { Id = "rbxassetid://9120805690", Volume = 1.8, Speed = 0.45, Range = 180, find = "metal door torn off hinges crash" },

	CellOpen = { Id = "rbxassetid://9116522890", Volume = 0.65, Speed = 1.6, Range = 70, find = "rusty iron gate squeal" },
	CellClose = { Id = "rbxassetid://9119727134", Volume = 0.8, Speed = 0.45, Range = 80, find = "iron gate clang shut" },
	CellSlam = { Id = "rbxassetid://9116673944", Volume = 1.4, Speed = 0.9, Range = 130, find = "body hitting metal bars rattle" },
	CellHit = { Id = "rbxassetid://9119727134", Volume = 0.8, Speed = 0.35, Range = 100, find = "metal bars rattle" },
	CellBreak = { Id = "rbxassetid://9120805690", Volume = 1.6, Speed = 0.6, Range = 170, find = "iron gate ripped off crash" },

	-- the holder
	Brace = { Id = "rbxassetid://9114555699", Volume = 0.5, Speed = 1.1, Range = 30, find = "short gasp / grunt pushing" },
	Bolt = { Id = "rbxassetid://9119727134", Volume = 0.6, Speed = 0.55, Range = 0, find = "heavy bolt slide clunk (only the holder hears this)" },
	Shoved = { Id = "rbxassetid://9114555699", Volume = 0.8, Speed = 0.9, Range = 40, find = "pained grunt" },
	Heartbeat = { Id = "rbxassetid://3012160995", Volume = 0.7, Speed = 1.5, Range = 0, find = "fast heartbeat (only the holder hears this)" },
}

return DoorConfig
