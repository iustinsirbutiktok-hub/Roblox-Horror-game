# Facility & Lab models

Twelve pieces for the facility: specimen tanks, a cryo pod, consoles, racks, power gear and
services. They're lightly aged: worn paint, grime and scuffs, no rust. Low poly, with baked
colour and normal maps embedded in each FBX.

| Piece | What it is | Size (studs, W x D x H) |
|---|---|---|
| ContainmentTank | Glowing fluid tank with a pale thing curled up inside, hanging from its feeding tubes | 5.1 x 10.1 x 11.0 |
| ContainmentTankBroken | The same tank smashed from the inside: jagged glass, shards and glowing fluid on the floor, tubes torn off, empty | 8.3 x 13.5 x 11.0 |
| CryoPod | Tilted cryo pod with a frosted canopy and someone frozen inside | 3.8 x 8.6 x 5.5 |
| ControlConsole | Sloped desk of switches, meters and lamps, three old monitors, keyboard tray, covered emergency button | 7.2 x 5.6 x 4.3 |
| ServerRack | Equipment rack with blinking LEDs, patch cables, louvred sides | 2.0 x 2.8 x 8.1 |
| BreakerPanel | Wall distribution board, door hanging open, a tripped breaker tagged DO NOT SWITCH ON | 3.3 x 3.4 x 9.0 |
| Transformer | Oil transformer on a hazard-striped plinth, ceramic bushings, cooling fins | 5.8 x 5.2 x 9.5 |
| LabBench | Steel bench: oscilloscope, microscope, flasks of green fluid, centrifuge, lamp, boxes | 6.2 x 2.9 x 4.1 |
| CableTray | 3 m of cable tray at 2.5 m on hanger rods (to a 3.1 m ceiling); cables spill out of one end and run down the wall to the floor | 1.7 x 10.5 x 9.3 |
| PipeManifold | Wall pipework: three painted/lagged lines, valve wheels, gauges, drops to the floor | 8.7 x 1.3 x 6.4 |
| PowerSwitch | Main power knife switch on a slate board; the lever is a separate part you can script | 1.9 x 1.6 x 6.9 |
| LabLamp | Hanging industrial cage lamp (top at the ceiling, 1.2 m drop) | 1.6 x 1.6 x 3.6 |

The front of every piece faces **+Z** in Studio. The previews (`previews/`) show how each
piece looks after `SetupLabGlow`.

## Bringing them in

1. **Import:** File > Import 3D, pick one FBX (or `Lab_All.fbx` for everything side by side).
   If the sizes look 3x too small or big, set the importer's Scale Unit to **Stud**.
2. **Glass and glow:** run `tools/SetupLabGlow.lua` in the Command Bar, with the imported
   models selected (or nothing selected, to do every lab piece in the Workspace). It:
   - turns `Glass...` parts into real see-through glass;
   - turns `Liquid...`, `Glow...`, `Screen...` and `Lamp...` parts into Neon of the right
     colour, each with a PointLight;
   - gathers `Lab_All.fbx`'s `Piece_Part` meshes into one Model per piece;
   - puts the lever's and the breaker door's pivots on their hinges.

Every lit part has the attribute `LabGlow = true`, and its light is named `LabLight`, so a
script can flicker or kill them (blackouts, alarms).

`ContainmentTank` has the curled-up thing as its own part, `Specimen`. Delete it for an
empty tank.

## The moving parts

These work once SetupLabGlow has set the pivots.

```lua
-- PowerSwitch: throw the lever up = power ON (it's modelled thrown down, OFF)
local lever = workspace.PowerSwitch.Lever
lever:PivotTo(lever:GetPivot() * CFrame.Angles(math.rad(-115), 0, 0))

-- BreakerPanel: the door is modelled hanging open; this swings it shut
local door = workspace.BreakerPanel.Door
door:PivotTo(door:GetPivot() * CFrame.Angles(0, math.rad(100), 0))
```

To animate it smoothly, step the angle over a few frames:

```lua
local function swing(part, axis, degrees, seconds)
	local start = part:GetPivot()
	local t = 0
	while t < seconds do
		t += task.wait()
		local a = math.rad(degrees) * math.min(t / seconds, 1)
		part:PivotTo(start * CFrame.fromAxisAngle(axis, a))
	end
end
swing(workspace.PowerSwitch.Lever, Vector3.xAxis, -115, 0.6)
```

The PowerSwitch's green lamp is modelled dead. When the power comes back, set its colour and
material (or add a light) from your script.
