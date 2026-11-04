# Builds the asylum furniture: python3 build.py OUT_DIR [Name ...]   (no names = all)
# Each piece is built in its own Blender session: OUT_DIR/Name.fbx plus its maps
# (Name_color/normal/roughness/metalness.png) and preview renders.
import sys, os, subprocess, time, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import kit
import surgery, ward, rooms  # noqa: F401  (they register their pieces)


def build_one(name, out):
    fn, close = kit.PIECES[name]
    kit.reset()
    kit.WORK = out
    fn()
    t = time.time()
    ob_info = kit.finish(name, out, previews=None)
    import bpy
    ob = bpy.data.objects[name]
    views = kit.auto_views(ob, close)
    kit.render_previews(ob, out, views)
    ob_info["seconds"] = round(time.time() - t)
    with open(os.path.join(out, name + ".json"), "w") as f:
        json.dump(ob_info, f)


if __name__ == "__main__":
    args = sys.argv[1:]
    out = os.path.abspath(args[0])
    names = args[1:] or list(kit.PIECES)
    if len(names) == 1:
        build_one(names[0], out)
    else:
        for n in names:
            print("==", n, flush=True)
            subprocess.run([sys.executable, __file__, out, n], check=False)
