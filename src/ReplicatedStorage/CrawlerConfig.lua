-- CrawlerConfig
-- Place in: ReplicatedStorage (a ModuleScript named exactly "CrawlerConfig")
--
-- Everything about the Crawler you might want to tune lives here: how fast
-- it moves, how far it sees, how hard it hits, and every sound it makes.
-- CrawlerAI (server) and CrawlerAnimator (every player's screen) both read
-- this, so change a number once and both sides agree.

local Config = {}

--------------------------------------------------
-- THE MONSTER
--------------------------------------------------

Config.MODEL_NAME = "TheCrawler"     -- the model in Workspace

-- movement (studs per second). Your sprint is 20.
Config.STALK_SPEED = 7               -- creeping around when it has no one
Config.CHASE_SPEED = 18.5            -- just slower than a sprinting player
Config.BURST_SPEED = 22              -- the first second after it spots you
Config.BURST_TIME = 1.1
Config.VENT_SPEED = 9                -- squeezing through a vent

-- senses
Config.SIGHT_RANGE = 90
Config.NOTICE_RANGE = 11             -- notices you this close even without seeing you
Config.GIVE_UP_AFTER = 7             -- keeps hunting your last known spot this long
Config.SPOT_TIME = 0.75              -- freezes and shrieks this long when it first spots you

-- catching
Config.CATCH_RANGE = 4.4             -- how close it has to get (it's long)
Config.HOLD_DISTANCE = 2.9           -- where you end up in front of it when grabbed
Config.HIT_DAMAGE = 50               -- a catch that doesn't finish you does this much
Config.GRACE_AFTER_HIT = 1.5         -- after you get back up it ignores you this long
Config.VENT_CEILING = 5.5            -- a ceiling lower than this counts as "in a vent"

-- body. The physics box it walks with is small and low so it fits in vents;
-- what you SEE is animated on top of it.
Config.ROOT_SIZE = Vector3.new(1.8, 0.4, 3.2)
Config.ROOT_HEIGHT = 1.8             -- centre of that box above the floor

-- how it holds itself (torso centre above the floor, in studs)
Config.PROWL_HEIGHT = 2.6
Config.CHASE_HEIGHT = 2.45
Config.MIN_SQUEEZE_HEIGHT = 1.15     -- lowest it can flatten itself

--------------------------------------------------
-- LIGHT IN THE DARK
--------------------------------------------------
-- Your mansion is pitch black, so it carries its own light: two glowing eyes
-- you see coming at you down a corridor, and a cold light that floods the
-- spot when it catches someone so the whole attack can be seen.

Config.EYE_COLOR = Color3.fromRGB(255, 70, 40)
Config.EYE_SIZE = 0.17
Config.EYE_OFFSET = Vector3.new(0.27, 0.34, -0.8)  -- on its head (sideways, up, forward); one each side
Config.EYE_LIGHT_BRIGHTNESS = 1.2    -- the red glow the eyes throw on the floor and walls
Config.EYE_LIGHT_RANGE = 6

Config.CATCH_LIGHT_COLOR = Color3.fromRGB(205, 215, 255)
Config.CATCH_LIGHT_BRIGHTNESS = 2.2
Config.CATCH_LIGHT_RANGE = 18

--------------------------------------------------
-- SOUNDS
--------------------------------------------------
-- Id = the sound's asset id. A blank Id just doesn't play, so the game never
-- errors over a missing sound. Volume and Speed are starting points; Speed is
-- randomised a little (by Vary) every time so repeats don't sound copy-pasted.
--
-- The ones already filled in are the sounds your other scripts use, re-pitched.
-- For the blank ones: open the Toolbox in Studio > Audio, search for what's in
-- the "find" note, right-click a sound you like > Copy Asset ID, paste it in.

Config.Sounds = {
	-- body, all the time
	Breath = { Id = "", Volume = 0.55, Speed = 0.9, Vary = 0.05, Range = 45,
		find = "wet raspy breathing loop / monster breathing" },
	HandStep = { Id = "rbxassetid://9116673944", Volume = 0.18, Speed = 2.4, Vary = 0.25, Range = 40,
		find = "claw tap on wood / bony click (short)" },
	FootStep = { Id = "rbxassetid://9116673944", Volume = 0.25, Speed = 1.5, Vary = 0.2, Range = 45,
		find = "heavy bare footstep on wood" },
	VentStep = { Id = "rbxassetid://9116673944", Volume = 0.5, Speed = 2.1, Vary = 0.2, Range = 70,
		find = "metal vent thump / duct bang" },
	VentScrape = { Id = "", Volume = 0.5, Speed = 1, Vary = 0.05, Range = 60,
		find = "metal scraping loop / something crawling in vents" },
	BoneCrack = { Id = "", Volume = 0.7, Speed = 1, Vary = 0.15, Range = 45,
		find = "bone crack / joint crack / neck crack" },
	Chatter = { Id = "", Volume = 0.6, Speed = 1, Vary = 0.1, Range = 40,
		find = "teeth chattering / clicking jaw" },
	Growl = { Id = "", Volume = 0.8, Speed = 0.8, Vary = 0.08, Range = 50,
		find = "low monster growl / guttural croak" },

	-- spotting you
	Screech = { Id = "rbxassetid://85531042691364", Volume = 1.3, Speed = 1.15, Vary = 0.06, Range = 160,
		find = "creature shriek" },

	-- catching you
	Lunge = { Id = "rbxassetid://85531042691364", Volume = 0.9, Speed = 1.45, Vary = 0.05, Range = 90,
		find = "monster snarl / hiss (short)" },
	Grab = { Id = "rbxassetid://9120502198", Volume = 0.7, Speed = 0.8, Vary = 0.1, Range = 50,
		find = "flesh grab / wet impact" },
	Whoosh = { Id = "", Volume = 0.8, Speed = 1, Vary = 0.1, Range = 50,
		find = "fast swing whoosh" },
	Hit = { Id = "rbxassetid://9120502198", Volume = 0.9, Speed = 0.65, Vary = 0.08, Range = 60,
		find = "claw slash flesh hit" },
	Slam = { Id = "rbxassetid://9116673944", Volume = 1.4, Speed = 0.55, Vary = 0.05, Range = 90,
		find = "body slam / heavy body fall on wood" },
	Crunch = { Id = "rbxassetid://9120502198", Volume = 0.8, Speed = 0.55, Vary = 0.1, Range = 60,
		find = "bone break crunch" },
	FaceScream = { Id = "rbxassetid://85531042691364", Volume = 2, Speed = 0.82, Vary = 0.03, Range = 160,
		find = "loud close monster scream" },
	Stinger = { Id = "", Volume = 0.9, Speed = 1, Vary = 0, Range = 0,
		find = "horror jumpscare stinger (only the caught player hears this)" },
	Heartbeat = { Id = "rbxassetid://3012160995", Volume = 0.8, Speed = 1.35, Vary = 0, Range = 0,
		find = "fast heartbeat (only the caught player hears this)" },
}

return Config
