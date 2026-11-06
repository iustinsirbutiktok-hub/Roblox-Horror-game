# The Butcher: generator

These Blender scripts build `assets/TheButcher/TheButcher.fbx`:
- `skeleton.py`: the joints and the ~200 bones (proportions, the cleaver fist, the face, the soft tissue)
- `body.py`: the body. The limbs are grown over the skeleton and the trunk (gut, chest, back) is made of metaballs. They're fused into one high-res surface and sculpted: belt crease, back rolls, muscle, veins, and the shirt and trouser folds
- `head.py`: the rotting face (the hole where the lips were, teeth, gums, black eyes), the greasy hair, and the face's skinning rules
- `clothes.py`: the apron (draped off the gut), its straps, buckles and ties, the collar, rolled cuffs, belt, buttons and boots
- `cleaver.py`: the cleaver
- `paint.py`: per-vertex masks (shirt, trousers, rot, blood, the handprints on the apron)
- `shaders.py`: one material per surface, giving colour, bump and roughness
- `build_all.py`: puts it together. It makes a game-resolution copy of every part, rigs and skins the copies, bakes colour, normal, roughness and AO from the high-res parts onto them, and exports the FBX
- `render_previews.py`, `preview.py`: the preview renders, including test poses that bend the rig
- `vec.py`, `common.py`: numpy and Blender helpers

To rebuild it (needs Python 3.13 with `pip install bpy==5.2.3`):

```sh
cd tools/butcher
python3 build_all.py -- ./out          # out/TheButcher.fbx, out/TheButcher_*.png, out/TheButcher.blend (about 20 minutes)
python3 render_previews.py -- ./out    # turnaround, close-ups, test poses
```

There are six meshes, each under Roblox's 20,000-triangle limit, each with its own 1024 colour,
normal and roughness maps: `ButcherBody`, `ButcherHead`, `ButcherHair`, `ButcherApron`,
`ButcherBoots` and `ButcherCleaver`. They all share one skeleton.

Bones that hang are named `<chain>_1`, `<chain>_2`... (for example `Hair05_1..3`, `Apron4_1..4`,
`TieL_1..3`).
