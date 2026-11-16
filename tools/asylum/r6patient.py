# The asylum patient as a classic blocky R6 character: a Shirt template, a Pants
# template (Roblox's 585 x 559 layout) and a face decal.
#   python3 r6patient.py OUT_DIR
# The clothing is baked from the same skin / gown / blood materials as the furniture,
# onto R6-sized boxes whose UVs are laid out exactly like the template, then the
# whole character is rendered with them to check every face lands where it should.
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy, bmesh
from mathutils import Vector as V
import kit
from kit import *  # noqa
from patient import skin  # noqa  (also registers the skin material)

OUT = os.path.abspath(sys.argv[1])
os.makedirs(OUT, exist_ok=True)
kit.WORK = OUT
S = 1 / 3                     # studs -> metres
TW, TH = 585, 559             # the template

# the template's rectangles: x, y, w, h (pixels, from the top left)
TORSO = {"F": (231, 74, 128, 128), "B": (427, 74, 128, 128), "R": (165, 74, 64, 128), "L": (361, 74, 64, 128),
         "U": (231, 8, 128, 64), "D": (231, 204, 128, 64)}
RIGHT = {"U": (217, 289, 64, 64), "D": (217, 485, 64, 64), "L": (19, 355, 64, 128), "B": (85, 355, 64, 128),
         "R": (151, 355, 64, 128), "F": (217, 355, 64, 128)}
LEFT = {"U": (308, 289, 64, 64), "D": (308, 485, 64, 64), "F": (308, 355, 64, 128), "L": (374, 355, 64, 128),
        "B": (440, 355, 64, 128), "R": (506, 355, 64, 128)}
# the character faces -Y here; its right is -X, up is +Z
NORMALS = {"F": V((0, -1, 0)), "B": V((0, 1, 0)), "R": V((-1, 0, 0)), "L": V((1, 0, 0)), "U": V((0, 0, 1)),
           "D": V((0, 0, -1))}
BODY = {  # name: (centre, size) in studs, rects
    "Torso": ((0, 0, 3), (2, 1, 2), TORSO),
    "RightArm": ((-1.5, 0, 3), (1, 1, 2), RIGHT),
    "LeftArm": ((1.5, 0, 3), (1, 1, 2), LEFT),
    "RightLeg": ((-0.5, 0, 1), (1, 1, 2), RIGHT),
    "LeftLeg": ((0.5, 0, 1), (1, 1, 2), LEFT),
}


def face_axes(n):
    """which way the template's x (right) and y (down) run across a face"""
    if abs(n.z) > 0.5:
        return V((1, 0, 0)), (V((0, -1, 0)) if n.z > 0 else V((0, 1, 0)))
    # round the sides the template unwraps anticlockwise seen from above
    return V((0, 0, 1)).cross(n), V((0, 0, -1))


def r6_box(name, centre, size, rects, material_key):
    c, sz = V(centre), V(size)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    for key, n in NORMALS.items():
        u, v = face_axes(n)
        eu, ev = abs(sz.dot(u)), abs(sz.dot(v))
        fc = c + V((n.x * sz.x, n.y * sz.y, n.z * sz.z)) / 2
        corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
        if u.cross(v).dot(n) < 0:
            corners = [(0, 0), (0, 1), (1, 1), (1, 0)]
        verts = [bm.verts.new((fc + u * (a - 0.5) * eu + v * (b - 0.5) * ev) * S) for a, b in corners]
        f = bm.faces.new(verts)
        rx, ry, rw, rh = rects[key]
        for loop, (a, b) in zip(f.loops, corners):
            loop[uv].uv = ((rx + a * rw) / TW, 1 - (ry + b * rh) / TH)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    me.materials.append(mat(material_key))
    return ob


# ---------------------------------------------------------------- the clothing material

def r6_clothes(g, part="torso", cx=0.0):
    """gown over starved skin, worked out from where on the body each pixel is (studs)"""
    X, Y, Z = g.mul(g.x, 3.0), g.mul(g.y, 3.0), g.mul(g.z, 3.0)
    ax = g.math("ABSOLUTE", g.sub(X, cx))           # across the limb / torso from its middle
    ay = g.math("ABSOLUTE", Y)
    is_leg = part == "leg"
    sk, _, _, _ = skin(g, base="#cbb9a4", bruise=0.5 if part != "torso" else 0.4, veins=0.6, dirt=0.45 if is_leg else 0.35,
                       bloodied=0.25 if part == "arm" else 0.12, scratches=0.5 if part == "arm" else 0.0)
    gown, _, _, _ = fabric(g, base="#a3b4ae", stain=0.45, bloodied=0.3, moldy=0.1, dirt=0.5, sc=1.4)
    # folds in the cloth: soft vertical shading
    folds = g.ms(g.noise(1.0, 3, 0.5, vec=g.vec((9, 9, 0.6), (0, 0, 0))), 0.3, 0.75)
    gown = g.mix(gown, shade(rgb("#a3b4ae"), 0.62), g.mul(folds, 0.3))
    edge = g.ms(g.noise(14, 4), 0.3, 0.7)          # ragged hems
    if part == "torso":
        front = g.ms(g.mul(Y, -1.0), 0.44, 0.49)
        back = g.ms(Y, 0.44, 0.49)
        lside = g.ms(X, 0.94, 0.99)
        # skin: the V of the neckline, the open back, a torn hole in the left flank
        v_neck = g.mul(front, g.ms(g.sub(Z, g.add(3.45, g.mul(ax, 1.05))), -0.02, 0.02))
        open_back = g.mul(g.mul(back, g.ms(ax, 0.2, 0.15)), g.ms(Z, 2.3, 2.4))
        hole_r = g.add(g.mul(g.sub(Z, 2.95), g.sub(Z, 2.95)), g.mul(Y, Y))
        hole = g.mul(lside, g.ms(g.add(hole_r, g.mul(edge, 0.03)), 0.075, 0.06))
        top_neck = g.mul(g.ms(Z, 3.97, 3.99), g.ms(g.add(g.mul(ax, ax), g.mul(Y, Y)), 0.16, 0.12))
        bare = g.clamp(g.add(g.add(v_neck, open_back), g.add(hole, top_neck)))
        # ribs and the spine where the skin shows
        ribs = g.mul(g.ms(g.math("SINE", g.mul(Z, 2 * math.pi / 0.17)), 0.55, 0.95), g.ms(Z, 2.55, 2.7))
        ribs = g.mul(ribs, g.ms(Z, 3.62, 3.5))
        sk = g.mix(sk, rgb("#6e5a4c"), g.mul(ribs, 0.55))
        spine = g.mul(g.mul(back, g.ms(ax, 0.05, 0.0)), g.ms(g.math("SINE", g.mul(Z, 2 * math.pi / 0.2)), 0.2, 0.9))
        sk = g.mix(sk, rgb("#5e4a3e"), g.mul(spine, 0.5))
        collar = g.mul(front, g.mul(g.ms(g.math("ABSOLUTE", g.sub(Z, 3.84)), 0.03, 0.0), g.ms(ax, 0.05, 0.12)))
        sk = g.mix(sk, rgb("#6e5a4c"), g.mul(collar, 0.6))
        # the gown's ties down the open back, and its dark edges
        rim = g.sub(g.clamp(g.add(bare, 0.0)), bare)
        c = g.mix(gown, sk, bare)
        tie = g.mul(g.mul(back, g.ms(g.math("ABSOLUTE", g.sub(ax, 0.22)), 0.05, 0.02)),
                    g.ms(g.math("SINE", g.mul(Z, 2 * math.pi / 0.5)), 0.85, 0.95))
        c = g.mix(c, rgb("#7d8e88"), tie)
        _ = rim
        return c, 0.9, 0.0, 0.0
    # limbs: thin - darker toward the box's edges, so it reads round and narrow
    across = g.mx(ax, ay)
    thin = g.ms(across, 0.28, 0.5)
    sk = g.mix(sk, rgb("#6e5a4c"), g.mul(thin, 0.28))
    if part == "arm":
        hem = g.add(3.3, g.mul(edge, 0.09))
        sleeve = g.ms(g.sub(Z, hem), 0.0, 0.02)
        # elbow, the wrist (bandage on the left, the ID band on the right), the hand
        sk = g.mix(sk, rgb("#7c5a4e"), g.mul(g.ms(g.math("ABSOLUTE", g.sub(Z, 2.95)), 0.1, 0.0), 0.4))
        hand = g.ms(Z, 2.3, 2.26)
        sk = g.mix(sk, rgb("#5a3a2c"), g.mul(hand, 0.35))
        fingers = g.mul(g.ms(Z, 2.16, 2.12), g.ms(g.math("SINE", g.mul(g.add(X, Y), 2 * math.pi / 0.22)), 0.85, 0.97))
        sk = g.mix(sk, rgb("#3a2620"), g.mul(fingers, 0.7))
        tips = g.ms(Z, 2.05, 2.01)
        sk = g.mix(sk, rgb("#2e1c16"), g.mul(tips, 0.6))
        if cx > 0:
            band = g.mul(g.ms(Z, 2.27, 2.29), g.ms(Z, 2.52, 2.5))
            gauze, _, _, _ = fabric(g, base="#d6cdb4", stain=0.6, bloodied=0.95, moldy=0.1, dirt=0.4, sc=3)
            sk = g.mix(sk, gauze, band)
        else:
            band = g.mul(g.ms(Z, 2.37, 2.38), g.ms(Z, 2.44, 2.43))
            sk = g.mix(sk, rgb("#dcd8cc"), band)
        c = g.mix(sk, gown, sleeve)
        c = g.mix(c, shade(rgb("#a3b4ae"), 0.55), g.mul(g.ms(g.math("ABSOLUTE", g.sub(Z, hem)), 0.03, 0.0), 0.6))
        return c, 0.8, 0.0, 0.0
    # legs: the gown torn short above the knee, bony knees, filthy bare feet with toes
    hem = g.add(1.42, g.mul(edge, 0.12))
    skirt = g.ms(g.sub(Z, hem), 0.0, 0.02)
    sk = g.mix(sk, rgb("#6a4a44"), g.mul(g.ms(g.math("ABSOLUTE", g.sub(Z, 1.0)), 0.12, 0.0), 0.45))
    sk = g.mix(sk, rgb("#3c2e24"), g.mul(g.ms(Z, 0.35, 0.05), 0.75))
    toes = g.mul(g.mul(g.ms(Z, 0.2, 0.16), g.ms(g.mul(Y, -1.0), 0.45, 0.49)),
                 g.ms(g.math("SINE", g.mul(X, 2 * math.pi / 0.2)), 0.85, 0.97))
    sk = g.mix(sk, rgb("#1e1510"), g.mul(toes, 0.8))
    c = g.mix(sk, gown, skirt)
    c = g.mix(c, shade(rgb("#a3b4ae"), 0.55), g.mul(g.ms(g.math("ABSOLUTE", g.sub(Z, hem)), 0.03, 0.0), 0.6))
    return c, 0.85, 0.0, 0.0


kit.KINDS["r6_clothes"] = r6_clothes


# ---------------------------------------------------------------- the face

def face_png(path, size=512):
    """a terrified face: stretched-open bloodshot eyes with pinprick pupils, sunken sockets,
    brows dragged up, a screaming mouth, blood from the nose and one eye"""
    from PIL import Image, ImageDraw, ImageFilter
    c = size / 2

    def layer():
        return Image.new("RGBA", (size, size), (0, 0, 0, 0))

    def soft(im, r):
        return im.filter(ImageFilter.GaussianBlur(r))

    out = layer()
    # shading: hollow sockets, gaunt cheeks, the brow furrowed with fear lines
    sh = layer()
    d = ImageDraw.Draw(sh)
    for s in (-1, 1):
        ex = c + s * 100
        d.ellipse((ex - 82, 168, ex + 82, 300), fill=(48, 26, 32, 195))
        d.ellipse((ex - 58, 300, ex + 48, 330), fill=(70, 40, 46, 110))          # bags
        d.ellipse((c + s * 150 - 50, 320, c + s * 150 + 40, 430), fill=(60, 40, 34, 70))   # hollow cheeks
    for k in range(3):
        d.arc((c - 120, 70 + k * 18, c + 120, 190 + k * 18), 200, 340, fill=(70, 50, 44, 90), width=4)
    out = Image.alpha_composite(out, soft(sh, 14))
    # the eyes
    ey = layer()
    d = ImageDraw.Draw(ey)
    rng = np.random.default_rng(7)
    for s in (-1, 1):
        ex, eyy = c + s * 100, 232
        d.ellipse((ex - 54, eyy - 46, ex + 54, eyy + 46), fill=(206, 196, 180, 255))
        for _ in range(16):
            a = rng.uniform(0, 2 * math.pi)
            r0 = rng.uniform(30, 52)
            pts = [(ex + math.cos(a) * r0, eyy + math.sin(a) * r0 * 0.85)]
            for _ in range(4):
                a += rng.uniform(-0.5, 0.5)
                r0 -= rng.uniform(4, 9)
                pts.append((ex + math.cos(a) * r0, eyy + math.sin(a) * r0 * 0.85))
            d.line(pts, fill=(170, 40, 34, 200), width=2)
        px = ex + s * 10 + (6 if s < 0 else -2)
        d.ellipse((px - 19, eyy - 19, px + 19, eyy + 19), fill=(96, 112, 104, 255))
        d.ellipse((px - 6, eyy - 6, px + 6, eyy + 6), fill=(8, 8, 8, 255))
        d.ellipse((px + 6, eyy - 12, px + 12, eyy - 6), fill=(240, 240, 236, 220))
        d.ellipse((ex - 54, eyy - 46, ex + 54, eyy + 46), outline=(120, 50, 50, 255), width=5)
    out = Image.alpha_composite(out, ey)
    # brows, raised and dragged up in the middle
    br = layer()
    d = ImageDraw.Draw(br)
    for s in (-1, 1):
        d.line([(c + s * 40, 158), (c + s * 95, 150), (c + s * 150, 170)], fill=(46, 34, 28, 230), width=11, joint="curve")
    out = Image.alpha_composite(out, soft(br, 1.2))
    # nose: shadow and nostrils
    ns = layer()
    d = ImageDraw.Draw(ns)
    d.polygon([(c - 6, 250), (c + 18, 330), (c - 22, 336)], fill=(80, 56, 48, 90))
    for s in (-1, 1):
        d.ellipse((c + s * 18 - 8, 334, c + s * 18 + 8, 344), fill=(40, 22, 20, 220))
    out = Image.alpha_composite(out, soft(ns, 3))
    # the mouth: open in a scream, teeth, cracked pale lips
    mo = layer()
    d = ImageDraw.Draw(mo)
    d.ellipse((c - 62, 372, c + 62, 470), fill=(160, 120, 110, 255))
    d.ellipse((c - 54, 380, c + 54, 462), fill=(36, 10, 10, 255))
    for i in range(-3, 4):
        x0 = c + i * 14
        d.rounded_rectangle((x0 - 6, 381, x0 + 6, 398 - abs(i) * 2), 3, fill=(204, 186, 140, 255))
    for i in (-2, -1, 0, 1, 2):
        x0 = c + i * 14
        d.rounded_rectangle((x0 - 6, 446 + abs(i) * 2, x0 + 6, 460), 3, fill=(186, 168, 124, 255))
    d.ellipse((c - 30, 425, c + 30, 455), fill=(90, 24, 26, 255))                    # the tongue
    out = Image.alpha_composite(out, mo)
    # blood: from the nose over the lip, a tear of it from the left eye, spatter
    bl = layer()
    d = ImageDraw.Draw(bl)
    for x0, y0, y1, w in ((c - 14, 342, 390, 7), (c + 18, 344, 378, 5), (c - 100 + 24, 276, 380, 6)):
        pts = [(x0 + math.sin(t / 9) * 3, t) for t in range(int(y0), int(y1), 3)]
        d.line(pts, fill=(96, 14, 10, 235), width=w)
        d.ellipse((pts[-1][0] - w, pts[-1][1] - w * 0.6, pts[-1][0] + w, pts[-1][1] + w * 1.4), fill=(96, 14, 10, 235))
    for _ in range(26):
        x0, y0 = rng.uniform(80, 440), rng.uniform(100, 480)
        if abs(x0 - c) < 70 and 370 < y0 < 470:
            continue
        r = rng.uniform(1.5, 5)
        d.ellipse((x0 - r, y0 - r, x0 + r, y0 + r), fill=(90, 16, 12, 200))
    out = Image.alpha_composite(out, soft(bl, 0.6))
    out.save(path)
    return path


# ---------------------------------------------------------------- build, bake, check

kit.reset()
kit.WORK = OUT
for name in ("AO", "EDGE"):
    im = bpy.data.images.new(name + "_t", TW, TH, alpha=False, float_buffer=True)
    im.colorspace_settings.name = "Non-Color"
    im.generated_color = (1, 1, 1, 1) if name == "AO" else (0, 0, 0, 1)
    kit.IMAGES[name] = im
material("torso_c", "r6_clothes", part="torso")
material("rarm_c", "r6_clothes", part="arm", cx=-1.5)
material("larm_c", "r6_clothes", part="arm", cx=1.5)
material("rleg_c", "r6_clothes", part="leg", cx=-0.5)
material("lleg_c", "r6_clothes", part="leg", cx=0.5)
keys = {"Torso": "torso_c", "RightArm": "rarm_c", "LeftArm": "larm_c", "RightLeg": "rleg_c", "LeftLeg": "lleg_c"}
obs = {n: r6_box(n, c, s, r, keys[n]) for n, (c, s, r) in BODY.items()}

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.render.bake.margin = 1
scene.world = bpy.data.worlds.new("W")


def bake(names, path, rects_list):
    img = bpy.data.images.new("t", TW, TH, alpha=False, float_buffer=True)
    for n in names:
        mt = obs[n].data.materials[0]
        kit._route(obs[n], "COLOR", img)
    for o in scene.objects:
        o.select_set(o.name in names)
    bpy.context.view_layer.objects.active = obs[names[0]]
    bpy.ops.object.bake(type="EMIT", margin=1, use_clear=True)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(TH, TW, 4)
    rgb_ = np.clip(px[..., :3], 0, 1)
    rgb_ = np.where(rgb_ <= 0.0031308, rgb_ * 12.92, 1.055 * np.power(rgb_, 1 / 2.4) - 0.055)
    rgb_ = np.flipud(rgb_)
    alpha = np.zeros((TH, TW), np.float32)
    for rects in rects_list:
        for (x, y, w, h) in rects.values():
            alpha[y:y + h, x:x + w] = 1
            for _ in range(2):
                rgb_[y, x:x + w] = rgb_[y + 1, x:x + w] if _ == 0 else rgb_[y, x:x + w]
                rgb_[y + h - 1, x:x + w] = rgb_[y + h - 2, x:x + w]
                rgb_[y:y + h, x] = rgb_[y:y + h, x + 1]
                rgb_[y:y + h, x + w - 1] = rgb_[y:y + h, x + w - 2]
    from PIL import Image
    a = np.dstack([rgb_, alpha])
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA").save(path)
    return path


shirt = bake(["Torso", "RightArm", "LeftArm"], os.path.join(OUT, "PatientShirt.png"), [TORSO, RIGHT, LEFT])
from PIL import Image as _I
_a = np.array(_I.open(shirt))[355 + 60:355 + 100, 217 + 10:217 + 54, :3].reshape(-1, 3).mean(0)
print("SKIN", "#%02x%02x%02x" % tuple(int(v) for v in _a))
pants = bake(["RightLeg", "LeftLeg"], os.path.join(OUT, "PatientPants.png"), [RIGHT, LEFT])
face = face_png(os.path.join(OUT, "PatientFace.png"))
print("TEMPLATES", shirt, pants, face)

# the check: put the templates back on the boxes, a classic R6 head with the face, and render it
for n, ob in obs.items():
    m = bpy.data.materials.new(n + "_view")
    m.use_nodes = True
    nt = m.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(pants if "Leg" in n else shirt)
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    ob.data.materials.clear()
    ob.data.materials.append(m)
headm = bpy.data.materials.new("head_view")
headm.use_nodes = True
nt = headm.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.8
tc = nt.nodes.new("ShaderNodeTexCoord")
emp = bpy.data.objects.new("FaceProj", None)
emp.location = (0, 0, 4.5 * S)
link(emp)
tc.object = emp
mp = nt.nodes.new("ShaderNodeMapping")
mp.inputs["Scale"].default_value = (1 / (1.2 * S), 1, 1 / (1.2 * S))
mp.inputs["Location"].default_value = (0.5, 0, 0.5)
nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(mp.outputs[0], sep.inputs[0])
cmb = nt.nodes.new("ShaderNodeCombineXYZ")
nt.links.new(sep.outputs["X"], cmb.inputs["X"])
nt.links.new(sep.outputs["Z"], cmb.inputs["Y"])
ft = nt.nodes.new("ShaderNodeTexImage")
ft.image = bpy.data.images.load(face)
ft.extension = "CLIP"
nt.links.new(cmb.outputs[0], ft.inputs["Vector"])
mix = nt.nodes.new("ShaderNodeMix")
mix.data_type = "RGBA"
mix.inputs[6].default_value = (*rgb("#c4b19c"), 1)
nt.links.new(ft.outputs["Color"], mix.inputs[7])
front = nt.nodes.new("ShaderNodeMath")
front.operation = "LESS_THAN"
nt.links.new(sep.outputs["Y"], front.inputs[0])
front.inputs[1].default_value = 0.0
mul = nt.nodes.new("ShaderNodeMath")
mul.operation = "MULTIPLY"
nt.links.new(ft.outputs["Alpha"], mul.inputs[0])
nt.links.new(front.outputs[0], mul.inputs[1])
nt.links.new(mul.outputs[0], mix.inputs[0])
nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
# the R6 head: a rounded cylinder 1.2 studs across
prof = [(0, 3.9), (0.45, 3.9), (0.58, 3.98), (0.6, 4.1), (0.6, 4.9), (0.58, 5.02), (0.45, 5.1), (0, 5.1)]
bm = bmesh.new()
rings = []
for r, z in prof:
    rings.append([bm.verts.new((math.cos(2 * math.pi * i / 24) * r * S, math.sin(2 * math.pi * i / 24) * r * S, z * S))
                  for i in range(24)])
for a, b in zip(rings, rings[1:]):
    for i in range(24):
        bm.faces.new((a[i], a[(i + 1) % 24], b[(i + 1) % 24], b[i]))
bm.faces.new(list(reversed(rings[0])))
bm.faces.new(rings[-1])
me = bpy.data.meshes.new("Head")
bm.to_mesh(me)
for p in me.polygons:
    p.use_smooth = True
head = link(bpy.data.objects.new("Head", me))
me.materials.append(headm)
for o in scene.objects:
    o.select_set(o.type == "MESH")
bpy.context.view_layer.objects.active = obs["Torso"]
bpy.ops.object.join()
whole = bpy.context.view_layer.objects.active
whole.name = "PatientR6"
whole.scale = (3, 3, 3)
bpy.ops.object.transform_apply(scale=True)
emp.location = (0, 0, 4.5)
emp.scale = (3, 3, 3)
kit.render_previews(whole, OUT, [("front", (0.0, -10.5, 4.0), (0, 0, 2.7), 50), ("back", (3.0, 9.5, 4.0), (0, 0, 2.7), 50),
                                 ("side", (-8.5, -6.0, 3.6), (0, 0, 2.7), 50), ("face", (0.0, -4.0, 4.7), (0, 0, 4.5), 50)])
print("RENDERED")
