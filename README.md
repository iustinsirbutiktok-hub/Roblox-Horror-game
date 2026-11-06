# Mansion: The Crawler

A fully procedural crawler monster for Roblox. There are no uploaded animations: every hand and
foot is planted on the real floor and only lifts when it has to. The body rides on springs, so it
sways, overshoots and settles, and the head locks onto you while the body moves under it. It
twitches, cracks its joints and flattens itself into vents.

## What it does

- **Prowling**: creeps in fits and starts (creep, freeze, sudden scurry, freeze), one limb at a
  time with its hands lifted high. Its head searches with sudden jerks, slow curious tilts, jaw
  chattering, and shudders.
- **Spotting you**: freezes, snaps its head at you and shrieks, then bursts into a sprint.
- **Chasing**: a low, bounding, spider-like gallop with its jaw hanging open. Its head stays locked
  on you while the body heaves under it.
- **Vents**: flattens itself under the ceiling, splays its limbs out like a frog, turns its head
  sideways, cracks its joints, and scrapes along the metal.
- **First catch** (you have more than 50 health): one of two at random, 50 damage, then it hovers
  over you twitching while you scramble up, then comes again.
  - **Slam**: grabs you, lifts you up to its face shrieking, and slams you onto your back.
  - **Swipe**: rears up and backhands you across the room. You land face-down and get up facing
    away, ready to run.
- **Second catch** (this one would take you to 0): the **Finisher**. It slams you on your back,
  hauls you up and spins you round, slams you face-down, pins you, and screams into your face.
  You go to 0 health, which hands you over to your DownedSystem revive.
- **Caught in a vent**: it drags you back by your legs, pounds you into the duct floor and bites
  at your back (**VentMaul**). The vent finisher ends with it crawling up your back to scream in
  your face (**VentFinisher**).
- **What the caught player sees**: their camera is dragged onto its face and shakes with every
  hit, with red flashes, drained colour, a heartbeat and a stinger that only they hear. Anyone
  standing close feels the slams through their camera too.

## Install (copy-paste into Studio)

Create these and paste in the matching file from `src/`. **The names must match exactly.**

| In Studio | Type | File |
|---|---|---|
| ReplicatedStorage > `CrawlerConfig` | ModuleScript | `src/ReplicatedStorage/CrawlerConfig.lua` |
| ReplicatedStorage > `CrawlerShared` | ModuleScript | `src/ReplicatedStorage/CrawlerShared.lua` |
| ReplicatedStorage > `CrawlerBody` | ModuleScript | `src/ReplicatedStorage/CrawlerBody.lua` |
| ServerScriptService > `CrawlerAI` | Script | `src/ServerScriptService/CrawlerAI.server.lua` |
| StarterPlayer > StarterPlayerScripts > `CrawlerAnimator` | LocalScript | `src/StarterPlayerScripts/CrawlerAnimator.client.lua` |

To copy a file from GitHub, open it, press the **Raw** button, then press Ctrl+A and Ctrl+C.

Your model stays as it is: `Workspace.TheCrawler`. When the game starts, the server re-rigs it
once so it walks level. Its old root part becomes a small, flat, invisible box that fits through
vents.

If your game has **StreamingEnabled** on, select `TheCrawler` and set **ModelStreamingMode** to
**Persistent** (the script also tries to set this itself).

## Testing

- **Test > Clients and Servers** with 2 players lets you test getting caught, getting downed and
  being revived.
- Walk around in front of it to see it spot you. Crouch into a vent with X and let it follow you.
- If it won't follow you into a vent, open **Model > Pathfinding**. The vent needs to show as
  walkable. If it doesn't, tell Claude and we'll add pathfinding links at the vent entrances.

## Sounds

Open `CrawlerConfig`. Every sound has a slot with a `find` note describing what to search for in
**Toolbox > Audio**. To fill one, right-click a sound, choose **Copy Asset ID**, and paste it as
`Id = "rbxassetid://123..."`. Slots that are still blank simply don't play. The slots already
filled reuse the sounds your other scripts play (thud, wet hit, scream, heartbeat), re-pitched.

The ones worth filling first: `Breath`, `BoneCrack`, `Chatter`, `Growl`, `VentScrape`, `Whoosh`,
`Stinger`.

## Tuning

Everything is in `CrawlerConfig`: speeds (your sprint is 20, so it chases at 18.5), how far it
sees, `HIT_DAMAGE`, catch range, how low it crouches. The catch choreography (every keyframe and
when each sound plays) lives in `CrawlerShared` under `Shared.CATCHES`.

## Doors

Three basement doors: **Wood** (rotten cellar door), **Steel** (rusted boiler room) and **Cell** (barred gate).

| Script | Type | Goes in |
|---|---|---|
| `src/ReplicatedStorage/DoorConfig.lua` | ModuleScript `DoorConfig` | ReplicatedStorage |
| `src/ServerScriptService/DoorServer.lua` | ModuleScript `DoorServer` | ServerScriptService |
| `src/ServerScriptService/DoorSystem.server.lua` | Script `DoorSystem` | ServerScriptService |
| `src/StarterPlayerScripts/DoorClient.client.lua` | LocalScript `DoorClient` | StarterPlayerScripts |
| `tools/BuildDoor.lua` | Command Bar | select a block filling a doorway, set `KIND`, run |
| `src/StarterPlayerScripts/ThirdPersonHorrorCamera.client.lua` | LocalScript | StarterPlayerScripts (your camera, with `IsBarricading` added) |

- **Left click** a door to open or close it. It swings away from you.
- **E** (HOLD on mobile) while the Crawler is hunting within 70 studs: you slam the door and lean your weight on it.
- When the Crawler hits the door, a dial comes up. Push when the red blade crosses the white window.
  - A good push holds the door. After 7-8 good pushes it rages once and leaves, ignoring everyone for 18 s.
  - A miss smashes the door into you. After 3 misses the door bursts and throws you on your back.
- If nobody is holding the door, a chasing Crawler smashes straight through it, while a prowling one creeps it open.
- CrawlerAI, CrawlerBody and CrawlerAnimator have door support built in. Without the door scripts they behave exactly as before.

## Movement

| Script | Type | Goes in |
|---|---|---|
| `src/StarterPlayerScripts/BodyMotion.client.lua` | LocalScript `BodyMotion` | StarterPlayerScripts |
| `src/ServerScriptService/BodyMotionServer.server.lua` | Script `BodyMotionServer` | ServerScriptService |
| `src/StarterPlayerScripts/ThirdPersonHorrorCamera.client.lua` | LocalScript | StarterPlayerScripts (no longer plays the Walk/Sprint/Crawl/CrawlStart animations) |

BodyMotion works out each R6 body every frame from its real speed, direction, acceleration, turning and health. It covers:
- walking, strafing, walking backwards and sprinting, plus a limp below 25% health
- dropping into a crawl, the forearm crawl itself, and pushing back up

It lets go for tools, other Action animations, jumping and falling, climbing, hiding, doors, catches and being downed. Crouching keeps its own animations.

## Main breaker

| Script | Type | Goes in |
|---|---|---|
| `src/ReplicatedStorage/BreakerLever.lua` | ModuleScript `BreakerLever` | ReplicatedStorage |
| `src/StarterPlayerScripts/LeverClient.client.lua` | LocalScript `LeverClient` | StarterPlayerScripts |
| `src/ServerScriptService/PowerSystem.server.lua` | Script | ServerScriptService (replaces PowerSystem) |
| `src/StarterPlayerScripts/PowerClient.client.lua` | LocalScript | StarterPlayerScripts (replaces PowerClient) |

How the breaker works:
- Repairing every wire panel and fuse cabinet sets `Power.Ready`.
- Left-clicking the breaker (Workspace > `LEVER LIGHTS`) throws it. If the power is Ready, the power comes on.
- If you pull it too early, it sparks and kicks back.
- If there's no breaker in the map, the power comes on by itself, like before.

The test command `lever` (on the Power folder's TestCommand) throws the breaker. If the swing goes the wrong way, set a `SwingAngle` attribute (in degrees) on `LEVER LIGHTS`.

## Stamina

Stamina lives in ThirdPersonHorrorCamera.
- **Using it:** sprinting drains it (about 7 s from full, scaled by the role's `StaminaMultiplier`); adrenaline doesn't drain it.
- **Getting it back:** it refills after you stop.
- **Running out:** you drop to walking speed and can't sprint again until it's back to 35. A heartbeat plays, the screen edges pulse with each beat, and small white flashes flicker at the edges.
- **For a stamina bar:** read the character attributes `Stamina` (0-100), `MaxStamina` and `Exhausted`.

The camera script now only hands walk/sprint/crawl to BodyMotion when BodyMotion is in StarterPlayerScripts. Without it, the camera plays its own animations again.

## Crawler sight and no jumping

How the Crawler sees you (CrawlerAI, `SIGHT` table):
- **Range:** 40 studs while the power is out, 70 once it's back on. Your camcorder light on: 1.5×.
- **Stance:** crouching cuts its range to 0.65×, crawling to 0.45×. The stance comes from the camera script through the `BodyMotion` remote, which CrawlerAI creates if it's missing.
- **Where it looks:** a 120° cone in front. Behind it, it only notices you within NOTICE_RANGE (smaller when you're crouched or crawling).
- **Cover:** it checks head, torso and legs. Glass and invisible parts don't block its view.
- **Reaction time:** instant within 35% of its range, building to 0.5 s at the edge of it.
- **The one it's chasing:** no cone and no delay, and 1.3× range.
- **Spotting you:** it shrieks while it's already lunging, with no freeze.

Jumping is off everywhere: the camera sets JumpPower 0 and disables the Jumping state, which also hides the mobile jump button.

## The Medic

`assets/TheMedic/TheMedic.fbx` is a rigged mesh monster:
- **Size:** 18k triangles, about 8 studs tall.
- **Rig:** 59 bones, including 3 joints per finger and double elbows.
- **Texture:** one embedded 2048 texture, also in the folder as `TheMedic_texture.png`.

To use it:
1. Import it with File › Import 3D (Rig type: no humanoid).
2. Make sure the model is named `TheMedic`.
3. Add these scripts: `MedicPose` (ReplicatedStorage), `MedicAnimator` (StarterPlayerScripts), `MedicSetup` (ServerScriptService).

The generator scripts are in `tools/medic`.

## The Stitcher

`assets/TheStitcher/TheStitcher.fbx` is a rigged mesh monster: a towering, starved surgeon in a
blood-soaked gown, built from your concept art. Its grin is carved from ear to ear with the ends sewn
shut, and a hole torn through its chest shows the ribs. It holds a huge pair of shears in its right fist.
- **Size:** about 8.8 studs tall. There are 4 meshes, about 50k triangles in all, each under Roblox's 20k limit.
- **Rig:** 178 bones, all on one skeleton:
  - **Body:** 5 spine, 4 neck, a 2-part upper arm and forearm on each side, metacarpals plus 3 joints in every finger.
  - **Face:** the jaw, both eyes, the brows, the cheeks, the grin's corners and both lips.
  - **Chest:** six ribs a side, each with its own bone, so the chest can heave or flare open.
  - **Scissors:** the moving blade has its own bone.
  - **Hanging parts:** 13 hair clumps, 8 skirt panels, the cap and gown ties, the torn flap, and the bandage tails.
- **Textures:** one 1024 texture per mesh (`TheStitcher_Body/Head/Clothes/Scissors.png`), also embedded in the FBX.

To use it:
1. Import it with File › Import 3D (Rig type: no humanoid).
2. Make sure the model is named `TheStitcher`.
3. Add these scripts:
   - `StitcherPose` (ModuleScript, ReplicatedStorage) from `src/ReplicatedStorage/StitcherPose.lua`
   - `StitcherAnimator` (LocalScript, StarterPlayerScripts) from `src/StarterPlayerScripts/StitcherAnimator.client.lua`
   - `StitcherSetup` (Script, ServerScriptService) from `src/ServerScriptService/StitcherSetup.server.lua`

It animates itself in code, with no uploaded animations:
- **Standing:** it hunches with its head lolling over, breathes with its bare ribs heaving, drums its long fingers, and slowly opens the scissors, then snaps them shut.
- **Twitches:** its head cracks over to the other side, its ribs spasm open one after another, a forearm bends the wrong way, its whole body shudders.
- **When it sees you:** its head snaps round and its eyes lock on. Close up, its head turns further than a neck should, the grin stretches and the jaw chatters. The scissors snip faster and come up, and its left hand reaches for you.
- **Moving:** it limps when it walks. Above about 6 studs/s it breaks into a low, lurching run.
- **Hair and cloth:** they're simulated, so they swing and lag, and its legs kick the skirt.

Your AI drives it with attributes on the model:
- **Aggro** (0 to 1): how worked up it is.
- **Attack:** change it (for example, add 1) and it rears up, ribs flaring and jaw gaping, then lunges and snips.
- **TargetUserId:** the player it stares at.
- **Procedural:** untick it to play your own Animation Editor animations instead.

Move the model and it walks or runs at that speed. Optional Sounds named `Snip`, `Crack` and `Shriek`
inside the model play on those moments. The generator and its tests are in `tools/stitcher`.

## The Butcher

`assets/TheButcher/TheButcher.fbx` is a rigged mesh monster built from your concept sheet: a hulking,
rotting butcher. It has greasy hair, a face with the lips rotted off, gums and teeth showing through,
and black sunken eyes. It wears a shirt with rolled sleeves and a long blood-soaked apron with straps
and back ties, with smeared handprints, plus work boots, and it carries a meat cleaver in its right fist.
It has **no animation**: the rig is for you to pose and animate.
- **Size:** about 8.2 studs tall. There are 6 meshes, about 67k triangles in all, each under Roblox's 20k limit.
- **Rig:** 198 bones, all on one skeleton:
  - **Body:** 5 spine, 3 neck, split thighs, shins, upper arms and forearms, metacarpals plus 3 joints in every finger.
  - **Soft tissue:** the gut (two bones), the chest, the love handles and the fat at the back of the neck.
  - **Face:** the jaw, eyes, upper and lower eyelids, outer and inner brows, cheeks, the nose, the ears, the mouth corners, and each half of both lips.
  - **Hair:** 16 clumps of 3 bones.
  - **Apron:** 7 columns of 4 bones, plus the bib, both straps, the bow and both tie ends.
  - **Clothes:** the collar points, both rolled cuffs, the belt and the boot tops.
  - **Cleaver:** its own bone.
- **Textures:** colour, normal and roughness maps for each mesh, 1024 each (`TheButcher_<Mesh>_Color/Normal/Roughness.png`). The colour maps are embedded in the FBX.

To use it:
1. Import it with File › Import 3D (Rig type: no humanoid), and name the model `TheButcher`.
2. For the full detail, add the normal and roughness maps (pores, cloth weave, crusted blood, and the wet shine on the blood). Upload the PNGs, paste their ids into `tools/ButcherSurfaceAppearance.lua`, select the model, and run the file in the command bar.
3. To animate it, add an `AnimationController` with an `Animator` inside the model, and open it in the Animation Editor.

The generator is in `tools/butcher`.
