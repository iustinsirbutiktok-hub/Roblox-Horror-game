# Tileable surface textures for the ward's walls and floor (MaterialVariants in Roblox):
#   python3 textures.py OUT_DIR
# Each is baked from the same decay materials as the furniture, on a flat 4 m
# square, then made to tile by blending it with a half-shifted copy of itself.
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy
import kit

OUT = os.path.abspath(sys.argv[1])
SIZE = 1024
SURFACES = {
    # name: (material kind, settings)
    "WardPeelingPaint": ("paint", dict(base="#c4bea4", chip=0.3, rust=-0.4, dirt=0.75, peel=0.85, under="#86a08c",
                                      primer="#8f826c", streaks=0.9, sc=1.0, dusty=0.0)),
    "WardFloor": ("paint", dict(base="#5c584e", chip=0.2, rust=-1.5, dirt=0.95, peel=0.5, under="#3e3a32",
                               primer="#6e6656", streaks=0.0, sc=1.6, gloss=0.2, dusty=0.6)),
    "WardStainedPlaster": ("paint", dict(base="#958a74", chip=0.1, rust=-0.8, dirt=0.9, peel=0.4, under="#6b4a3a",
                                        primer="#7a6450", streaks=1.0, sc=0.8, dusty=0.0)),
}


def tileable(a):
    n = a.shape[0]
    b = np.roll(np.roll(a, n // 2, 0), n // 2, 1)
    t = np.linspace(0, 1, n)
    w1 = 1 - np.abs(t - 0.5) * 2               # 1 in the middle, 0 at the edges
    w = np.clip(np.minimum.outer(w1, w1) * 3, 0, 1)[..., None]
    return a * w + b * (1 - w)


os.makedirs(OUT, exist_ok=True)
for name, (kind, kw) in SURFACES.items():
    kit.reset()
    kit.TEX = SIZE
    bpy.ops.mesh.primitive_plane_add(size=4, location=(0, 0, 10.0), rotation=(1.5708, 0, 0))   # an upright wall (high up: no near-the-floor grime band)
    ob = bpy.context.active_object
    kit.material(name, kind, **kw)
    ob.data.materials.append(kit.mat(name))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    world = bpy.data.worlds.new("W")
    scene.world = world
    col = kit._bake(ob, "EMIT", kit.new_image("c", SIZE, False), 8, "COLOR")
    rough = kit._bake(ob, "EMIT", kit.new_image("r", SIZE, True), 4, "ROUGH")
    scene.render.bake.normal_space = "TANGENT"
    nrm = kit._bake(ob, "NORMAL", kit.new_image("n", SIZE, True), 4, "NORMAL")
    kit._png(tileable(col[..., :3]), os.path.join(OUT, name + "_color.png"), True)
    n = tileable(nrm[..., :3])
    v = n * 2 - 1
    v /= np.linalg.norm(v, axis=2, keepdims=True) + 1e-6
    kit._png(v * 0.5 + 0.5, os.path.join(OUT, name + "_normal.png"), False)
    kit._png(np.repeat(tileable(rough[..., :1]), 3, 2), os.path.join(OUT, name + "_roughness.png"), False)
    print("TEXTURE", name)
