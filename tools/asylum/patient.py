# The patient: a starved, terrified asylum inmate built as an R6 character.
# Six meshes - Head, Torso, LeftArm, RightArm, LeftLeg, RightLeg - laid out on
# the standard R6 frame (feet on the floor, torso 2..4 studs, head on top), all
# on one baked texture. tools/RigAsylumPatient.lua joins them with the standard
# R6 Motor6Ds in Studio. Built in studs (scaled to metres here and back on export),
# facing +Y, which comes out facing -Z in Roblox like every character.
import bpy, bmesh, math, random
from mathutils import Vector as V
from mathutils.bvhtree import BVHTree
from kit import *  # noqa
import kit

S = 1 / 3          # studs -> metres


# ---------------------------------------------------------------- materials

def skin(g, base="#bdab98", bruise=0.5, veins=0.5, dirt=0.6, bloodied=0.25, scratches=0.0, stubble_z=None):
    """starved skin: sallow and blotchy, blue veins showing, bruises going yellow at the edges,
    scratches, grime, dried blood; a shaved scalp with dark stubble"""
    b = rgb(base)
    c = g.mix(shade(b, 0.85), shade(b, 1.06), g.ms(g.noise(4.0, 5, 0.6), 0.3, 0.75))
    c = g.mix(c, rgb("#b27c6c"), g.mul(g.ms(g.noise(2.2, 4), 0.62, 0.9), 0.2))        # blotchy redness
    c = g.mix(c, rgb("#9d9a7e"), g.mul(g.ms(g.noise(1.2, 3), 0.4, 0.75), 0.3))          # sallow
    vn = g.ms(g.vor(9.0, "DISTANCE_TO_EDGE", vec=g.warp(0.03, 6)), 0.022, 0.0)
    c = g.mix(c, rgb("#5c6c86"), g.mul(vn, 0.4 * veins))
    bn = g.noise(3.0, 4, 0.6)
    t = 0.86 - bruise * 0.08
    c = g.mix(c, rgb("#8c8a50"), g.mul(g.ms(bn, t - 0.04, t), 0.35))
    c = g.mix(c, rgb("#55304a"), g.mul(g.ms(bn, t, t + 0.04), 0.7))
    h = g.mul(g.noise(90, 3), 0.12)
    if scratches:
        sc = g.ms(g.noise(1.0, 2, 0.5, vec=g.vec((5, 5, 140), g._seed())), 0.8, 0.84)
        sc = g.mul(sc, g.mul(g.ms(g.noise(3.5, 3), 0.5, 0.7), scratches))
        c = g.mix(c, rgb("#5e1610"), g.mul(sc, 0.85))
        h = g.add(h, g.mul(sc, -0.5))
    if stubble_z is not None:
        top = g.ms(g.z, stubble_z, stubble_z + 0.035)
        speck = g.ms(g.noise(70, 2), 0.4, 0.65)
        patch = g.ms(g.noise(6, 3), 0.25, 0.4)            # bald patches where it was torn out
        c = g.mix(c, rgb("#3a322b"), g.mul(top, g.mul(patch, g.add(0.3, g.mul(speck, 0.6)))))
    c, _ = grime(g, c, dirt, "#3a3026", low=0.2)
    if bloodied:
        c, _ = blood(g, c, bloodied, 6)
    return c, 0.62, 0.0, h


def eyeball(g):
    c = g.mix(rgb("#d6cdbd"), rgb("#c9b9a6"), g.ms(g.noise(20, 3), 0.3, 0.7))
    vein = g.ms(g.vor(60, "DISTANCE_TO_EDGE", vec=g.warp(0.004, 80)), 0.04, 0.0)
    c = g.mix(c, rgb("#a2342b"), g.mul(vein, 0.75))
    return c, 0.12, 0.0, 0.0


kit.KINDS["skin"] = skin
kit.KINDS["eyeball"] = eyeball


# ---------------------------------------------------------------- shapes

def skin_part(nodes, edges, m, root=0, displace=None, ratio=0.38, k=1.5):
    """a smooth organic tube body over a little skeleton graph (studs, the current place).
    nodes: [((x, y, z), (rx, ry)), ...]; displace(p, n) -> how far to push a vertex along its normal"""
    me = bpy.data.meshes.new("skin")
    me.from_pydata([p for p, r in nodes], edges, [])
    ob = link(bpy.data.objects.new("skin", me))
    sk = ob.modifiers.new("Skin", "SKIN")
    sk.use_smooth_shade = True
    sk.branch_smoothing = 0.55
    data = me.skin_vertices[0].data
    for i, (p, r) in enumerate(nodes):
        data[i].radius = (r[0] * k, r[1] * k)
    data[root].use_root = True
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = 2
    kit.apply_modifiers(ob)
    if ratio:
        dec = ob.modifiers.new("Dec", "DECIMATE")
        dec.ratio = ratio
        kit.apply_modifiers(ob)
    if displace:
        for v in ob.data.vertices:
            v.co = v.co + v.normal * displace(V(v.co), V(v.normal))
    return ob


def as_part(ob, m, smooth=60):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bpy.data.objects.remove(ob)
    return part(bm, m, STACK[-1], smooth)


def gauss(p, c, r):
    return math.exp(-((p - V(c)).length_squared) / (r * r))


def fitted_cloth(body, z0, z1, nu, nv, offset, m, keep=None, flare=0.0, seed=1, thick=0.03, cx=0.0, cy=0.0, wobble=0.02,
                 fallback=0.18):
    """a garment shell: rays from outside onto the body, pushed out by `offset`, wrinkled"""
    dg = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(body, dg)
    rnd = random.Random(seed)

    def shape(u, v):
        a = 2 * math.pi * u
        z = z1 - (z1 - z0) * v
        d = V((math.sin(a), math.cos(a), 0))
        o = V((cx, cy, z))
        hit = tree.ray_cast(o + d * 3, -d)
        r = (hit[0] - o).length if hit[0] is not None else fallback
        r += offset + flare * v * v
        wob = wobble * (math.sin(a * 7 + v * 5 + seed) * 0.6 + math.sin(a * 13 - v * 9) * 0.4)
        return tuple(o + d * (r + wob))

    return grid(1.0, 1.0, nu, nv, shape, m, keep=keep, thick=thick, rough_edge=0.02, seed=seed)


# ---------------------------------------------------------------- the body parts

def torso():
    nodes = [((0, 0, 2.2), (0.42, 0.27)), ((-0.43, 0, 2.1), (0.29, 0.25)), ((0.43, 0, 2.1), (0.29, 0.25)),
             ((0, 0, 2.62), (0.33, 0.22)), ((0, 0, 3.2), (0.5, 0.29)), ((0, -0.02, 3.62), (0.52, 0.27)),
             ((-0.7, -0.02, 3.78), (0.16, 0.16)), ((0.7, -0.02, 3.78), (0.16, 0.16)), ((0, -0.01, 3.92), (0.17, 0.16)),
             ((0, 0.01, 4.22), (0.13, 0.13))]
    edges = [(0, 1), (0, 2), (0, 3), (3, 4), (4, 5), (5, 6), (5, 7), (5, 8), (8, 9)]

    def sculpt(p, n):
        x, y, z = p
        push = 0.0
        ang = math.atan2(x, y)                # 0 = front (+y)
        front = max(0.0, math.cos(ang))
        if 2.85 < z < 3.62 and abs(ang) < 2.3:
            slope = 0.2 * front
            band = math.cos((z + slope - 2.85) / 0.125 * 2 * math.pi)
            push += 0.028 * max(0.0, band) * (1 - 0.5 * front * (abs(x) < 0.07))
        push -= 0.06 * front * gauss(p, (0, 0.2, 2.62), 0.3)                         # sunken belly
        push += 0.03 * front * math.exp(-((z - 3.73) / 0.03) ** 2) * (0.1 < abs(x) < 0.6)   # collarbones
        push -= 0.03 * front * math.exp(-((z - 3.83) / 0.05) ** 2) * (abs(x) < 0.5)    # hollows above them
        for s in (-1, 1):
            push += 0.03 * gauss(p, (s * 0.3, 0.17, 2.32), 0.08)                       # hip bones
        if y < -0.1 and abs(x) < 0.07:
            push += 0.02 * max(0.0, math.cos((z - 2.3) / 0.14 * 2 * math.pi))           # spine
        return push

    body = skin_part(nodes, edges, "skin_body", root=0, displace=sculpt)
    # the gown: open down the back, a torn hole in the left flank, low at the neck
    def keep(u, v):
        a = 2 * math.pi * u
        z = 3.8 - 1.8 * v
        back = abs(a - math.pi) < 0.22 and z > 2.4
        neck = (a < 0.55 or a > 2 * math.pi - 0.55) and z > 3.58
        hole = abs(a - 4.9) < 0.22 and 2.85 < z < 3.15
        return not (back or neck or hole)

    fitted_cloth(body, 2.0, 3.8, 32, 14, 0.045, "gown", keep=keep, flare=0.08, seed=3)
    as_part(body, "skin_body")


def arm(side):
    x = side * 1.04
    nodes = [((x - side * 0.03, 0, 3.75), (0.19, 0.19)), ((x, 0, 3.3), (0.12, 0.13)), ((x + side * 0.01, 0.02, 2.92), (0.115, 0.125)),
             ((x + side * 0.01, 0.03, 2.6), (0.1, 0.095)), ((x + side * 0.01, 0.04, 2.33), (0.07, 0.058)),
             ((x + side * 0.01, 0.05, 2.17), (0.034, 0.085))]
    edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)]
    # fingers spread and tense, the thumb out to the front
    for i, yy in enumerate((-0.025, 0.025, 0.075, 0.12)):
        b = len(nodes)
        spread = (yy - 0.05) * 0.6
        nodes += [((x + side * 0.01, yy, 2.07), (0.022, 0.022)), ((x + side * 0.03, yy + spread * 0.5, 1.97), (0.02, 0.02)),
                  ((x + side * 0.06, yy + spread, 1.88 + 0.01 * i % 2), (0.017, 0.017))]
        edges += [(5, b), (b, b + 1), (b + 1, b + 2)]
    b = len(nodes)
    nodes += [((x - side * 0.01, 0.12, 2.2), (0.026, 0.026)), ((x - side * 0.03, 0.19, 2.12), (0.022, 0.022)),
              ((x - side * 0.03, 0.23, 2.04), (0.018, 0.018))]
    edges += [(5, b), (b, b + 1), (b + 1, b + 2)]

    def sculpt(p, n):
        push = 0.02 * gauss(p, (x + side * 0.02, -0.08, 2.93), 0.07)                   # the elbow's point
        push += 0.012 * gauss(p, (x + side * 0.07, 0.04, 2.33), 0.04)                  # wrist bone
        return push

    ob = skin_part(nodes, edges, "skin_arm", root=0, displace=sculpt, k=1.45)
    # a short torn sleeve, fitted to the arm
    fitted_cloth(ob, 3.4, 3.76, 16, 3, 0.025, "gown", flare=0.02, seed=5 + side, cx=x - side * 0.01, wobble=0.01,
                 fallback=0.2)
    if side < 0:
        # the left wrist bandaged, bled through
        lathe([(0.085, 2.27), (0.095, 2.36), (0.09, 2.47), (0, 2.47)], (x + side * 0.01, 0.04, 0), m="gauze_p", n=12,
              stretch=(1.0, 0.85))
    else:
        lathe([(0.082, 2.36), (0.082, 2.4), (0, 2.4)], (x + side * 0.01, 0.04, 0), m="id_band", n=12, stretch=(1.0, 0.85))
    p = as_part(ob, "skin_arm")
    # the hands and fingers: bloodier
    p.data.materials.append(mat("skin_hand"))
    for poly in p.data.polygons:
        if poly.center.z < 2.3 * S:
            poly.material_index = 1


def leg(side):
    x = side * 0.43
    nodes = [((x, 0, 2.0), (0.27, 0.24)), ((x, 0, 1.55), (0.185, 0.19)), ((x, 0.03, 1.07), (0.16, 0.16)),
             ((x, 0.0, 0.62), (0.115, 0.125)), ((x, -0.02, 0.17), (0.08, 0.09)), ((x, -0.08, 0.06), (0.07, 0.06)),
             ((x, 0.13, 0.05), (0.1, 0.045)), ((x + side * 0.01, 0.3, 0.035), (0.095, 0.03))]
    edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (4, 6), (6, 7)]

    def sculpt(p, n):
        push = 0.03 * gauss(p, (x, 0.18, 1.07), 0.08)                     # kneecap
        push += 0.015 * gauss(p, (x, 0.11, 0.85), 0.12) * 0               # (shin stays sharp)
        for s in (-1, 1):
            push += 0.012 * gauss(p, (x + s * 0.09, -0.02, 0.15), 0.04)   # ankle bones
        return push

    ob = skin_part(nodes, edges, "skin_leg", root=0, displace=sculpt, k=1.45)
    # the gown's skirt round the thigh, torn short
    fitted_cloth(ob, 1.52, 1.98, 18, 4, 0.02, "gown", flare=0.015, seed=7 + side, cx=x, wobble=0.01, fallback=0.24)
    as_part(ob, "skin_leg")


def head():
    c = V((0, 0.02, 4.6))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=44, v_segments=28, radius=0.5)
    feats = []
    for v in bm.verts:
        p = V((v.co.x * 0.84, v.co.y * 0.98, v.co.z * 1.12))
        n = p.normalized()
        x, y, z = p
        front = max(0.0, y / max(p.length, 1e-6))
        d = 0.0
        for s in (-1, 1):
            d -= 0.1 * gauss(p, (s * 0.165, 0.43, 0.08), 0.1)            # deep eye sockets
            d += 0.03 * gauss(p, (s * 0.17, 0.47, 0.18), 0.09)           # brow
            d += 0.045 * gauss(p, (s * 0.29, 0.37, -0.02), 0.09)         # cheekbones
            d -= 0.075 * gauss(p, (s * 0.26, 0.35, -0.21), 0.12)         # hollow cheeks
            d -= 0.045 * gauss(p, (s * 0.4, 0.2, 0.14), 0.12)            # temples
        for zz in (0.1, 0.03, -0.04):
            d += 0.06 * gauss(p, (0, 0.5, zz), 0.055)                    # the nose's ridge
        d += 0.075 * gauss(p, (0, 0.52, -0.09), 0.055)                   # its tip
        mouth = math.exp(-((x / 0.1) ** 2 + ((z + 0.3) / 0.068) ** 2) ** 2) * front
        d -= 0.19 * mouth                                                # open, screaming
        d += 0.025 * math.exp(-((x / 0.15) ** 2 + ((z + 0.3) / 0.11) ** 2)) * front * (1 - mouth)   # lips
        d += 0.045 * gauss(p, (0, 0.4, -0.5), 0.09)                      # chin
        for s in (-1, 1):
            d += 0.03 * gauss(p, (s * 0.3, 0.12, -0.38), 0.1)               # the jaw's corners
        if z < -0.15:
            p = V((x * (1 - 0.12 * min(1.0, (-0.15 - z) / 0.4)), y, z))  # a narrow starved jaw
        v.co = c + p + n * d
    with place(T()):
        hd = part(bm, "skin_head", STACK[-1], 60)
    # ears
    for s in (-1, 1):
        lump(0.09, (s * 0.44, -0.0, 4.6), m="skin_head", seed=11 + s, squash=(0.35, 0.7, 1.25), rough=0.1, n=10, rings=6)
    # eyes: bloodshot, sunk in their sockets but stretched wide open, pinprick pupils staring apart
    for side in (-1, 1):
        ec = V((side * 0.16, 0.385, 4.69))
        sphere(0.068, tuple(ec), m="eye_white", n=14, rings=9)
        look = V((side * 0.07, 1.0, 0.02)).normalized()
        rot = tuple(math.degrees(a) for a in look.to_track_quat("Z", "Y").to_euler())
        cyl(0.03, 0.005, tuple(ec + look * 0.066), rot, m="iris", n=14)
        cyl(0.009, 0.005, tuple(ec + look * 0.069), rot, m="bakelite", n=8)
        # the lids pulled back: a heavy upper lid and a red-rimmed lower one
        lump(0.075, tuple(ec + V((0, 0.025, 0.06))), m="skin_head", seed=20 + side, squash=(1.05, 0.55, 0.4),
             rough=0.04, n=12, rings=6)
        lump(0.07, tuple(ec + V((0, 0.03, -0.062))), m="lid_rim", seed=24 + side, squash=(1.0, 0.5, 0.3),
             rough=0.04, n=12, rings=6)
    # teeth, inside the open mouth
    for row, zz in ((1, 4.335), (-1, 4.245)):
        for i in range(-3, 4):
            box((0.026, 0.03, 0.036), (i * 0.029, 0.37 - abs(i) * 0.014, zz + row * 0.004), (0, 0, i * 9), m="teeth",
                bevel=0.006)
    box((0.2, 0.02, 0.12), (0, 0.33, 4.29), m="mouth_dark", bevel=0.01)
    _ = hd


# ---------------------------------------------------------------- the piece

@piece("AsylumPatient", close=((1.0, 3.2, 5.6), (0, 0, 5.0), 45))
def asylum_patient():
    material("skin_body", "skin", bruise=0.6, veins=0.6, dirt=0.65, bloodied=0.15)
    material("skin_arm", "skin", bruise=0.6, veins=0.5, dirt=0.6, bloodied=0.25, scratches=0.8)
    material("skin_hand", "skin", bruise=0.4, veins=0.4, dirt=0.9, bloodied=0.75, scratches=0.4)
    material("skin_leg", "skin", bruise=0.4, veins=0.6, dirt=0.75, bloodied=0.12, scratches=0.3)
    material("skin_head", "skin", bruise=0.3, veins=0.7, dirt=0.4, bloodied=0.1, stubble_z=4.82 * S)
    material("mouth_dark", "rubber", base="#2a1210")
    material("gown", "fabric", base="#a2b3ad", stain=0.75, bloodied=0.45, moldy=0.25, dirt=0.7)
    material("gauze_p", "fabric", base="#d4ccb6", stain=0.6, bloodied=0.9, moldy=0.1)
    material("id_band", "paint", base="#d8d4c8", chip=0.05, rust=-2, peel=-1, dirt=0.5)
    material("eye_white", "eyeball")
    material("iris", "paint", base="#6c7c72", chip=0.0, rust=-2, peel=-1, dirt=0.0, streaks=0.0)
    material("lid_rim", "skin", base="#9c6a5e", bruise=0.2, veins=0.2, dirt=0.3, bloodied=0.2)
    material("teeth", "porcelain", base="#c4b384", stain=0.8, chips=0.5, rusty=0.6, craze=0.2)
    with place(T(s=S)):
        with group("Head", pivot=(0, 0, 4.5 * S)):
            head()
        with group("Torso", pivot=(0, 0, 3.0 * S)):
            torso()
        with group("RightArm", pivot=(1.04 * S, 0, 3.0 * S)):
            arm(1)
        with group("LeftArm", pivot=(-1.04 * S, 0, 3.0 * S)):
            arm(-1)
        with group("RightLeg", pivot=(0.43 * S, 0, 1.0 * S)):
            leg(1)
        with group("LeftLeg", pivot=(-0.43 * S, 0, 1.0 * S)):
            leg(-1)
