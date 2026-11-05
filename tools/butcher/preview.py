# Quick and final preview renders (Workbench for shape checks, Cycles for the look).
import bpy, math
from mathutils import Vector as V
from common import link


def camera(loc, at, lens):
    cd = bpy.data.cameras.new("PreviewCam")
    cd.lens = lens
    cd.clip_start = 0.05
    co = bpy.data.objects.new("PreviewCam", cd)
    co.location = loc
    co.rotation_euler = (V(at) - V(loc)).to_track_quat("-Z", "Y").to_euler()
    link(co)
    return co


def lights(target=(0, 0, 5)):
    if bpy.data.objects.get("KeyLight"):
        return
    for name, loc, energy, size in (("KeyLight", (6, -7, 9), 1400, 2.0), ("RimLight", (-5, 6, 9), 1100, 2.5),
                                    ("FillLight", (-7, -6, 3), 160, 6), ("Under", (0, -4, 0.3), 60, 3)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = size
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        lo.rotation_euler = (V(target) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        link(lo)


def render(path, views, size=(600, 900), engine="WORKBENCH", samples=32, bg=(0.035, 0.035, 0.04)):
    """views: list of (location, look_at, lens); writes path_0.png, path_1.png..."""
    scene = bpy.context.scene
    # (no OpenGL here, so even the quick checks go through Cycles, just with few samples)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 6 if engine == "WORKBENCH" else samples
    scene.cycles.use_denoising = True
    try:
        scene.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    scene.cycles.device = "CPU"
    scene.cycles.max_bounces = 3
    lights()
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    world = bpy.data.worlds.get("W") or bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (*bg, 1)
    scene.world = world
    scene.view_settings.view_transform = "Standard"
    outs = []
    for i, (loc, at, lens) in enumerate(views):
        co = camera(loc, at, lens)
        scene.camera = co
        out = path.replace(".png", "_%d.png" % i)
        scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        outs.append(out)
        bpy.data.objects.remove(co)
    return outs


FULL = [((0, -13, 4.6), (0, 0, 4.4), 50), ((-9, -9, 4.8), (0, 0, 4.4), 50), ((13, 0, 4.6), (0, 0, 4.4), 50),
        ((0, 13, 4.6), (0, 0, 4.4), 50)]
FACE = [((0, -2.2, 8.1), (0, -0.2, 8.0), 50), ((-1.5, -1.6, 8.2), (0, -0.2, 8.0), 50),
        ((1.9, -0.4, 8.0), (0, -0.2, 8.0), 50)]
CHEST = [((0.4, -2.8, 6.0), (0, 0, 5.95), 50)]
HANDS = [((-1.3, -3.2, 3.9), (-1.95, -0.4, 3.5), 50), ((-4.2, -1.2, 3.8), (-1.95, -0.4, 3.4), 50),
         ((1.6, -3.0, 3.9), (1.95, -0.4, 3.5), 50)]


def stitch(paths, out, cols=None):
    """lay several renders side by side into one image (numpy, no PIL)"""
    import numpy as np
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        w, h = im.size
        a = np.array(im.pixels[:]).reshape(h, w, 4)
        imgs.append(a)
        bpy.data.images.remove(im)
    cols = cols or len(imgs)
    rows = (len(imgs) + cols - 1) // cols
    h = max(a.shape[0] for a in imgs)
    w = max(a.shape[1] for a in imgs)
    sheet = np.zeros((h * rows, w * cols, 4))
    sheet[..., 3] = 1
    for i, a in enumerate(imgs):
        r, c = divmod(i, cols)
        r = rows - 1 - r                      # (Blender images are stored bottom-up)
        sheet[r * h:r * h + a.shape[0], c * w:c * w + a.shape[1]] = a
    img = bpy.data.images.new("sheet", w * cols, h * rows, alpha=True)
    img.pixels[:] = sheet.ravel()
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return out
