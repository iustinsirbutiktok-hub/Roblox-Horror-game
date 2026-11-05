# The Stitcher: generator

These Blender scripts build `assets/TheStitcher/TheStitcher.fbx`:
- `skeleton.py`: the joints and the ~180 bones (proportions, the clenched right fist, the face bones, the ribs, the scissors)
- `body.py`: the body, grown over the skeleton, with the starved anatomy and the hole torn in its chest
- `ribs.py`: the ribs that show through the hole (one bone each)
- `head.py`: the face, the ear-to-ear grin and its stitches, teeth, eyes, cap, hair and mask; also the face's skinning rules
- `clothes.py`: the gown (torn over the ribs), sleeves, ties, skirt bones, boots and bandages
- `scissors.py`: the shears (two halves on a screw)
- `paint.py`: the per-vertex masks and the shaders that get baked into the textures
- `build_all.py`: puts it together, rigs and skins it, bakes one 1024 texture per mesh, exports the FBX
- `render_previews.py` and `preview.py`: the preview renders
- `test/run_pose.py`: runs the real `src/ReplicatedStorage/StitcherPose.lua` (in Lua 5.1, with
  `test/roblox_mock.lua` standing in for Roblox) on the built rig: it fuzzes it for errors and bad
  numbers, then poses the model with its output and renders it

To rebuild it (needs Python 3.13 with `pip install bpy==5.2.3 lupa`):

```sh
cd tools/stitcher
python3 build_all.py -- ./out          # out/TheStitcher.fbx, out/TheStitcher_*.png, out/TheStitcher.blend (about 4 minutes)
python3 render_previews.py -- ./out    # turnaround and close-ups
python3 test/run_pose.py -- ./out      # checks and renders the Lua animation
```

The four meshes are `StitcherBody` (skin, ribs, bandages), `StitcherHead` (face, teeth, eyes, cap,
hair, mask), `StitcherClothes` (gown, sleeves, ties, boots) and `StitcherScissors`. Each one stays
under 20,000 triangles and has its own 1024 texture, because Roblox shrinks anything bigger. All four
share one skeleton.

Bones that hang and swing are named `<chain>_1`, `<chain>_2`... (for example `Hair05_1..3`,
`SkirtF_1..3`, `TieWaistL_1..2`). `StitcherPose` finds them by that naming and simulates them.
