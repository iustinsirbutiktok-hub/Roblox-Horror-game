# The Medic: generator

These Blender scripts build `assets/TheMedic/TheMedic.fbx`:
- the body (a skin modifier over the skeleton, sculpted ribs and joints)
- the skull, jaw, teeth, eyes and torn surgical mask
- the gown and the IV lines
- the 59-bone rig and the skinning
- one baked 2048 texture

To rebuild it (needs Blender 4.5, or `pip install bpy==4.5.4`):

```sh
cd tools/medic
python3 build_all.py -- ./out    # writes out/TheMedic.fbx, out/TheMedic_texture.png, out/TheMedic.blend
```

Edit `skeleton.py` for proportions and joints, `head.py` for the skull, mask and teeth, `clothes.py` for the gown and IV lines, and the shader functions in `build_all.py` for the colours.
