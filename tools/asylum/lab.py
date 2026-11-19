# The facility: containment tanks and laboratory equipment. Lightly aged - worn
# paint, grime, scuffs, no rust. Wherever something should glow or be see-through
# it is its own mesh: "Glass", "Liquid", "Glow", "Screen" (tools/SetupLabGlow.lua turns
# them into real glass and Neon in Studio); everything else is "Frame".
from kit import *  # noqa
import kit
import patient


# ---------------------------------------------------------------- materials

def hazard(g, a="#c9a227", b="#1c1c1c", scale=3.2):
    """yellow and black warning stripes, scuffed"""
    w = g.wave(scale, "DIAGONAL", "BANDS")
    c = g.mix(rgb(b), rgb(a), g.ms(w, 0.47, 0.53))
    scuff = g.ms(g.add(g.noise(9, 6), g.mul(g.edge, 0.4)), 0.72, 0.8)
    c = g.mix(c, rgb("#5a5a56"), g.mul(scuff, 0.7))
    c, dirt_m = grime(g, c, 0.5)
    c, _ = dust(g, c, 0.3)
    return c, g.lerp(0.5, 0.85, scuff), 0.0, g.mul(scuff, -0.4)


def glowpaint(g, base="#4fd8ff"):
    """the colour of whatever glows (set to Neon in Studio)"""
    c = g.mix(shade(rgb(base), 0.9), rgb(base), g.ms(g.noise(6, 3), 0.3, 0.7))
    return c, 0.3, 0.0, 0.0


kit.KINDS["hazard"] = hazard
kit.KINDS["glowpaint"] = glowpaint

# glowing bits are split by colour, so SetupLabGlow can give each mesh its Neon colour
GLOW = {"glow_blue": "GlowBlue", "glow_green": "GlowGreen", "glow_red": "GlowRed", "glow_amber": "GlowAmber"}


def jagged_ring(R, t, z0, heights, m, down=False):
    """a glass tube broken off: solid along z0, reaching heights[i] up (or down) at each angle"""
    n = len(heights)
    bm = bmesh.new()
    ol, oh, il, ih = [], [], [], []
    for i, h in enumerate(heights):
        a = 2 * math.pi * i / n
        c, sn = math.cos(a), math.sin(a)
        zt = z0 - h if down else z0 + h
        ol.append(bm.verts.new((c * R, sn * R, z0)))
        oh.append(bm.verts.new((c * R, sn * R, zt)))
        il.append(bm.verts.new((c * (R - t), sn * (R - t), z0)))
        ih.append(bm.verts.new((c * (R - t), sn * (R - t), zt)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((ol[i], ol[j], oh[j], oh[i]))
        bm.faces.new((il[j], il[i], ih[i], ih[j]))
        bm.faces.new((oh[i], oh[j], ih[j], ih[i]))
        bm.faces.new((il[i], il[j], ol[j], ol[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return part(bm, m, STACK[-1], 30)


def shard(at, size, seed, m="tank_glass", tilt=8):
    rnd = random.Random(seed)
    pts = [(math.cos(a) * size * rnd.uniform(0.4, 1.0), math.sin(a) * size * rnd.uniform(0.4, 1.0))
           for a in sorted(rnd.uniform(0, 2 * math.pi) for _ in range(3 + seed % 2))]
    slab(pts, 0.006, at, (rnd.uniform(-tilt, tilt), rnd.uniform(-tilt, tilt), rnd.uniform(0, 360)), m=m)


def lab_materials():
    material("lab_white", "paint", base="#c8cbc7", chip=0.25, rust=-3.0, peel=-0.4, dirt=0.45, gloss=0.55, streaks=0.25,
             primer="#8a8e90")
    material("lab_grey", "paint", base="#5d6368", chip=0.25, rust=-3.0, peel=-0.5, dirt=0.5, gloss=0.4, streaks=0.2,
             primer="#9a9ea2")
    material("lab_dark", "paint", base="#2b2f33", chip=0.3, rust=-3.0, peel=-0.5, dirt=0.1, dusty=0.12, gloss=0.45, streaks=0.1,
             primer="#7a7e82")
    material("lab_blue", "paint", base="#2f4f6e", chip=0.25, rust=-3.0, peel=-0.4, dirt=0.4, gloss=0.5)
    material("lab_steel", "chrome", base="#a3a8ab", rust=-1.5, dull=0.55)
    material("lab_copper", "chrome", base="#b06c40", rust=-1.5, dull=0.6)
    material("hazard", "hazard")
    material("glow_blue", "glowpaint", base="#4fd8ff")
    material("glow_green", "glowpaint", base="#5cff8a")
    material("glow_red", "glowpaint", base="#ff3b2e")
    material("glow_amber", "glowpaint", base="#ffb23b")
    material("glow_white", "glowpaint", base="#eef6ff")
    material("screen", "glowpaint", base="#1e6a8a")
    material("tank_glass", "glass", base="#b8d8e4", frost=0.15, dirt=0.35)
    material("tank_liquid", "glowpaint", base="#2a8cff")
    for name, col in (("cable_black", "#1c1c1c"), ("cable_red", "#6e1a16"), ("cable_blue", "#1c3456"),
                      ("cable_yellow", "#8c7420"), ("cable_green", "#1f4a2a"), ("cable_grey", "#55585a")):
        material(name, "rubber", base=col)


def sag(a, b, droop, n=8):
    """points of a cable hanging between a and b"""
    a, b = V(a), V(b)
    return [a.lerp(b, i / n) - V((0, 0, droop * 4 * (i / n) * (1 - i / n))) for i in range(n + 1)]


def cable(points, r=0.012, m="cable_black", bend=0.08, n=6):
    sweep(points, r, m, n, bend=bend)


def screw_ring(R, z, count, r=0.012, m="lab_steel"):
    for i in range(count):
        a = 2 * math.pi * (i + 0.5) / count
        cyl(r, 0.012, (math.cos(a) * R, math.sin(a) * R, z), m=m, n=6)


def button(at, r=0.012, m="glow_red", rot=(0, 0, 0)):
    with place(T(at, rot)):
        cyl(r * 1.5, 0.006, (0, 0, 0.003), m="lab_dark", n=8)
        cyl(r, 0.012, (0, 0, 0.01), m=m, n=8)


def toggle(at, rot=(0, 0, 0)):
    with place(T(at, rot)):
        cyl(0.01, 0.006, (0, 0, 0.003), m="lab_steel", n=6)
        cyl(0.003, 0.025, (0, 0.004, 0.015), (15, 0, 0), m="lab_steel", n=5)


# ---------------------------------------------------------------- the pieces

def specimen(at, scale=1.45):
    """a pale thing curled up in the fluid, knees to its chest, its head bowed, tubes in its back"""
    material("specimen_skin", "skin", base="#a3aa9e", bruise=0.7, veins=1.0, dirt=0.15, bloodied=0.05)
    nodes = [((0, 0.04, -0.15), (0.11, 0.09)), ((0, 0.08, 0.0), (0.1, 0.085)), ((0, 0.05, 0.15), (0.12, 0.09)),
             ((0, -0.03, 0.25), (0.045, 0.045)), ((0, -0.11, 0.25), (0.08, 0.09))]
    edges = [(0, 1), (1, 2), (2, 3), (3, 4)]
    for s in (-1, 1):
        b = len(nodes)
        nodes += [((s * 0.08, 0.0, -0.17), (0.06, 0.06)), ((s * 0.08, -0.22, 0.04), (0.048, 0.048)),
                  ((s * 0.06, -0.07, -0.17), (0.034, 0.034)), ((s * 0.06, -0.14, -0.23), (0.026, 0.03)),
                  ((s * 0.13, 0.02, 0.17), (0.04, 0.04)), ((s * 0.16, -0.14, 0.03), (0.032, 0.032)),
                  ((s * 0.06, -0.27, 0.05), (0.024, 0.024)), ((s * 0.01, -0.29, 0.07), (0.02, 0.026))]
        edges += [(0, b), (b, b + 1), (b + 1, b + 2), (b + 2, b + 3), (2, b + 4), (b + 4, b + 5), (b + 5, b + 6),
                  (b + 6, b + 7)]
    nodes = [(tuple(c * scale for c in p), (r[0] * scale, r[1] * scale)) for p, r in nodes]
    with place(T(at)):
        patient.as_part(patient.skin_part(nodes, edges, "specimen_skin", root=1, ratio=0.45, k=1.0), "specimen_skin")
    return V(at)


@piece("ContainmentTank", close=((4.6, -7.6, 4.6), (0.6, -1.6, 3.6), 35))
def containment_tank():
    """the specimen tank from the photo: a heavy base with vents and a ring of light, a glass
    cylinder of glowing fluid with something curled up in it, guide rails, the capped top with
    its pipes and cables to the ceiling"""
    _tank(False)


@piece("ContainmentTankBroken", close=((3.4, -8.4, 3.6), (0.0, -2.2, 1.6), 35))
def containment_tank_broken():
    """the same tank smashed open from the inside: jagged glass, shards and glowing fluid
    across the floor, the feeding tubes torn off and dangling - and nothing in it any more"""
    _tank(True)


def _tank(broken):
    lab_materials()
    plate = label_png("unit04", [("CONTAINMENT UNIT 04", 0.8), ("BIOLOGICAL - DO NOT OPEN", 0.6)], 520, 140,
                      bg=(32, 36, 40), fg=(220, 214, 196), font="cond")
    material("unit_plate", "paint", base="#2b2f33", chip=0.1, rust=-2, peel=-1, dirt=0.3)
    decal("unit_plate", plate, here((0, -0.835, 0.17), (90, 0, 0)), (0.36, 0.1))
    # the base
    lathe([(0, 0), (0.84, 0), (0.84, 0.06), (0.8, 0.08), (0.8, 0.27), (0.76, 0.3), (0.7, 0.3), (0.7, 0.36), (0, 0.36)],
          m="lab_dark", n=36)
    lathe([(0.845, 0.0), (0.845, 0.05), (0, 0.05)], m="hazard", n=36)
    for i in range(18):
        a = 360 * i / 18
        if abs(((a + 90) % 360) - 180) < 15:
            continue                                   # (the nameplate)
        with place(T((0, 0, 0.17), (0, 0, a))):
            box((0.11, 0.02, 0.12), (0, -0.795, 0), m="lab_grey", bevel=0.004)
            for k in range(4):
                box((0.09, 0.012, 0.008), (0, -0.802, -0.04 + k * 0.027), m="cable_black")
    box((0.37, 0.006, 0.11), (0, -0.83, 0.17), m="unit_plate", bevel=0.002)
    screw_ring(0.74, 0.36, 12)
    with group("GlowBlue"):
        torus(0.66, 0.022, (0, 0, 0.37), m="glow_blue", n=36, k=6)
    with group("Main" if broken else "GlowBlue"):                  # (the top ring died with it)
        torus(0.66, 0.022, (0, 0, 2.53), m="lab_dark" if broken else "glow_blue", n=36, k=6)
    with group("GlowBlue"):
        for i in range(8):
            a = 2 * math.pi * i / 8
            box((0.03, 0.01, 0.02), (math.cos(a) * 0.805, math.sin(a) * 0.805, 0.285), (0, 0, math.degrees(a) + 90),
                m="glow_blue")
    # the glass and the fluid
    if not broken:
        with group("Glass"):
            lathe([(0.62, 0.36), (0.62, 2.55)], m="tank_glass", n=36)
            lathe([(0.605, 2.55), (0.605, 0.36)], m="tank_glass", n=36)
        with group("Liquid"):
            lathe([(0, 0.37), (0.598, 0.37), (0.598, 2.28), (0, 2.28)], m="tank_liquid", n=32)
        with group("Specimen", (0, 0, 1.35)):
            c = specimen((0, 0, 1.35))
            for k, x in enumerate((-0.05, 0.05, 0.0)):
                cable([(x, 0.06, 2.55), (x * 2, 0.14, 2.1), (x, 0.24 + 0.02 * k, 1.7), c + V((x, 0.17, 0.12 - 0.08 * k))],
                      0.014, "cable_black", bend=0.12)
    else:
        rnd = random.Random(7)
        n = 48
        back = [max(0.0, math.sin(2 * math.pi * i / n)) for i in range(n)]          # (the back held, +y)
        low = [0.06 + 0.25 * rnd.random() + (0.12 if i % 3 == 0 else 0) + 1.0 * back[i] ** 2 * rnd.uniform(0.5, 1.0)
               for i in range(n)]
        high = [0.05 + 0.18 * rnd.random() + (0.1 if i % 4 == 1 else 0) + 0.5 * back[i] ** 2 * rnd.uniform(0.3, 1.0)
                for i in range(n)]
        with group("Glass"):
            jagged_ring(0.62, 0.015, 0.36, low, "tank_glass")
            jagged_ring(0.62, 0.015, 2.55, high, "tank_glass", down=True)
            for k in range(30):                                # shards thrown out the front
                a = math.radians(rnd.uniform(200, 340))
                r = rnd.uniform(0.9, 2.1)
                shard((math.cos(a) * r, math.sin(a) * r, 0.004), rnd.uniform(0.04, 0.16), 20 + k)
            for k in range(8):                                 # and a few left on the base's ledge
                a = rnd.uniform(0, 2 * math.pi)
                shard((math.cos(a) * 0.69, math.sin(a) * 0.69, 0.364), rnd.uniform(0.03, 0.06), 60 + k, tilt=3)
        with group("LiquidBlue"):
            lathe([(0, 0.37), (0.598, 0.37), (0.598, 0.4), (0, 0.4)], m="tank_liquid", n=32)
            pts = []
            for i in range(28):
                a = 2 * math.pi * i / 28
                r = 0.75 + 0.35 * math.sin(3 * a + 1) * 0.5 + rnd.uniform(-0.12, 0.12)
                pts.append((math.cos(a) * r * 1.3, math.sin(a) * r))
            slab(pts, 0.004, (0, -1.25, 0.002), m="tank_liquid")
            for k in range(6):                                 # drips running down the base
                a = math.radians(rnd.uniform(230, 310))
                box((0.03, 0.006, rnd.uniform(0.1, 0.28)), (math.cos(a) * 0.805, math.sin(a) * 0.805, 0.2),
                    (0, 0, math.degrees(a) + 90), m="tank_liquid")
        for k, x in enumerate((-0.05, 0.05, 0.0)):             # its feeding tubes, torn off
            end = V((x * 3 + 0.08 * k, -0.1 - 0.12 * k, 1.25 + 0.25 * k))
            cable([(x, 0.06, 2.55), (x * 2, 0.0, 2.1), (x * 3, -0.05 * k, 1.7), end], 0.014, "cable_black", bend=0.12)
            for w in range(3):
                cable([end, end + V(((w - 1) * 0.012, -0.01, -0.05 - 0.02 * w))], 0.0025, "lab_copper", n=4)
    # guide rails inside, struts outside
    for i in range(3):
        a = 2 * math.pi * i / 3 + 0.5
        cyl(0.012, 2.19, (math.cos(a) * 0.56, math.sin(a) * 0.56, 1.455), m="lab_steel", n=6)
        a2 = 2 * math.pi * i / 3 + 1.55
        box((0.05, 0.05, 2.26), (math.cos(a2) * 0.7, math.sin(a2) * 0.7, 1.45), (0, 0, math.degrees(a2)), m="lab_steel",
            bevel=0.008)
    # the top: a heavy ring and cap, bolts, pipes and a cable bundle up to the ceiling
    lathe([(0.6, 2.55), (0.72, 2.55), (0.74, 2.6), (0.74, 2.78), (0.7, 2.82), (0.52, 2.87), (0.32, 2.92), (0.3, 3.0),
           (0, 3.0)], m="lab_dark", n=36)
    lathe([(0.745, 2.62), (0.745, 2.7), (0.0, 2.7)], m="hazard", n=36)
    screw_ring(0.66, 2.86, 10)
    for i in range(3):
        a = 2 * math.pi * i / 3
        p = V((math.cos(a) * 0.42, math.sin(a) * 0.42, 2.9))
        sweep([p, p + V((0, 0, 0.25)), p + V((math.cos(a) * 0.25, math.sin(a) * 0.25, 0.45)),
               p + V((math.cos(a) * 0.3, math.sin(a) * 0.3, 0.75))], 0.045, "lab_grey", 10, bend=0.12)
        cyl(0.065, 0.04, tuple(p + V((0, 0, 0.12))), m="lab_steel", n=12)
    for k, m_ in enumerate(("cable_black", "cable_black", "cable_red", "cable_blue", "cable_yellow")):
        a = k * 1.3
        cable([(math.cos(a) * 0.08, math.sin(a) * 0.08, 3.0), (math.cos(a) * 0.1, math.sin(a) * 0.1, 3.3),
               (0.05 + math.cos(a) * 0.06, math.sin(a) * 0.06, 3.65)], 0.016, m_)
    cyl(0.16, 0.08, (0, 0, 3.02), m="lab_steel", n=14)
    # the control box on its post at the front
    with place(T((0.55, -0.95, 0))):
        box((0.08, 0.08, 0.9), (0, 0, 0.45), m="lab_grey", bevel=0.01)
        with place(T((0, 0, 0.98), (35, 0, 0))):
            box((0.34, 0.08, 0.24), m="lab_white", bevel=0.012)
            with group("ScreenRed" if broken else "Screen"):
                box((0.16, 0.006, 0.1), (-0.06, -0.042, 0.04), m="glow_red" if broken else "screen")
            for i, mm in enumerate(("glow_green", "glow_amber", "glow_red")):
                button((0.1, -0.04, 0.07 - i * 0.05), 0.011, mm, (90, 0, 0))
            for i in range(4):
                toggle((-0.12 + i * 0.04, -0.04, -0.07), (90, 0, 0))
        cable(sag((0, 0.03, 0.88), (-0.3, 0.2, 0.25), 0.1) + [V((-0.4, 0.25, 0.04))], 0.012, "cable_grey")
    # thick cables out of the back of the base, snaking along the floor
    for k, (m_, off) in enumerate((("cable_black", 0.0), ("cable_black", 0.12), ("cable_blue", -0.12))):
        cable([(off, 0.82, 0.12), (off, 0.95, 0.05), (off + 0.15, 1.3, 0.035), (off - 0.1, 1.8, 0.035),
               (off + 0.05, 2.3, 0.035)], 0.03, m_, bend=0.2, n=8)


def frozen_body():
    """a body lying along the pod (local z = feet to head), face up towards the glass (-y)"""
    material("frozen_skin", "skin", base="#a8b6bc", bruise=0.9, veins=1.0, dirt=0.1, bloodied=0.0)
    nodes = [((0, 0.14, -0.05), (0.15, 0.1)), ((0, 0.13, 0.12), (0.13, 0.09)), ((0, 0.12, 0.32), (0.16, 0.1)),
             ((0, 0.13, 0.5), (0.05, 0.05)), ((0, 0.1, 0.62), (0.085, 0.1))]
    edges = [(0, 1), (1, 2), (2, 3), (3, 4)]
    for s in (-1, 1):
        b = len(nodes)
        nodes += [((s * 0.09, 0.14, -0.08), (0.075, 0.07)), ((s * 0.1, 0.13, -0.48), (0.055, 0.055)),
                  ((s * 0.1, 0.14, -0.84), (0.04, 0.04)), ((s * 0.11, 0.07, -0.89), (0.035, 0.03)),
                  ((s * 0.19, 0.13, 0.38), (0.05, 0.05)), ((s * 0.22, 0.14, 0.1), (0.04, 0.04)),
                  ((s * 0.21, 0.13, -0.12), (0.032, 0.032)), ((s * 0.19, 0.12, -0.21), (0.03, 0.02))]
        edges += [(0, b), (b, b + 1), (b + 1, b + 2), (b + 2, b + 3), (2, b + 4), (b + 4, b + 5), (b + 5, b + 6),
                  (b + 6, b + 7)]
    patient.as_part(patient.skin_part(nodes, edges, "frozen_skin", root=1, ratio=0.45, k=1.0), "frozen_skin")


@piece("CryoPod", close=((2.4, -3.6, 4.0), (0, 0, 2.6), 45))
def cryo_pod():
    """a cryo pod tilted back on its frame: steel shell, a frosted glass canopy, a frozen shape
    inside, glowing rims, a side panel and hoses"""
    lab_materials()
    material("frost", "fabric", base="#d4e2e8", stain=0.2, moldy=0.0, dirt=0.2)
    box((1.1, 2.3, 0.14), (0, 0, 0.07), m="lab_dark", bevel=0.02)
    box((1.12, 2.32, 0.02), (0, 0, 0.012), m="hazard", bevel=0.004)
    for s in (-1, 1):
        slab([(-1.0, 0.14), (0.9, 0.14), (0.9, 0.5), (0.4, 1.2), (-1.0, 0.6)], 0.06, (s * 0.5, 0, 0), (90, 0, 90),
             m="lab_grey", bevel=0.01)
    with place(T((0, -0.05, 0.95), (-62, 0, 0))):
        L, R = 1.0, 0.42
        lathe([(R, -L), (R + 0.02, -L + 0.05), (R + 0.02, L - 0.05), (R, L)], m="lab_white", n=28, arc=(0, 180))
        lathe([(R - 0.01, L), (R - 0.01, -L)], m="lab_dark", n=28, arc=(0, 180))
        for z in (-L, L):
            lathe([(0, z), (R + 0.03, z), (R + 0.03, z + (0.06 if z < 0 else -0.06)), (0, z + (0.06 if z < 0 else -0.06))],
                  m="lab_grey", n=28)
        with group("Glass"):
            lathe([(R + 0.005, -L + 0.06), (R + 0.005, L - 0.06)], m="tank_glass", n=28, arc=(180, 360))
            lathe([(R - 0.005, L - 0.06), (R - 0.005, -L + 0.06)], m="tank_glass", n=28, arc=(180, 360))
        with group("GlowBlue"):
            for x in (-1, 1):
                box((0.025, 0.02, 2 * L - 0.1), (x * (R + 0.025), 0.0, 0), m="glow_blue")
        # someone frozen inside, lying back, arms at their sides; frost crusted round them
        frozen_body()
        for i, (x, z, r) in enumerate(((-0.3, -0.7, 0.07), (0.3, -0.4, 0.06), (-0.32, 0.1, 0.06), (0.3, 0.5, 0.07),
                                       (-0.28, 0.7, 0.05), (0.0, -0.82, 0.07), (0.25, -0.8, 0.05))):
            lump(r, (x, 0.3, z), m="frost", seed=10 + i, squash=(1.4, 1.0, 1.6), rough=0.2)
        hose_from = here((0.2, 0.3, -L)).translation
        hose_from2 = here((-0.2, 0.3, -L)).translation
    # side panel
    with place(T((0.62, -0.4, 0.75), (0, 0, 0))):
        box((0.12, 0.3, 0.45), m="lab_white", bevel=0.012)
        with group("Screen"):
            box((0.006, 0.18, 0.12), (0.062, 0, 0.1), m="screen")
        for i, mm in enumerate(("glow_green", "glow_amber")):
            button((0.062, -0.08 + i * 0.06, -0.09), 0.012, mm, (0, 90, 0))
    for p, m_ in ((hose_from, "cable_black"), (hose_from2, "cable_blue")):
        pts = [p, p + V((0, 0.0, -0.15)), V((p.x, 1.3, 0.05)), V((p.x + 0.2, 1.7, 0.04))]
        dense = []
        smooth_pts = fillet(pts, 0.15)
        for a, b in zip(smooth_pts, smooth_pts[1:]):
            k = max(1, int((b - a).length / 0.025))
            for i in range(k):
                dense.append(a.lerp(b, i / k))
        dense.append(smooth_pts[-1])
        sweep(dense, 0.04, m_, 8, radii=[0.042 if i % 2 else 0.034 for i in range(len(dense))])


@piece("ControlConsole", close=((2.4, -4.2, 4.6), (0.2, -0.4, 2.8), 40))
def control_console():
    """the main console: a sloped desk of switches, knobs, meters and lamps under three old
    monitors, a keyboard on its pull-out tray, a covered emergency button, cable bundles"""
    lab_materials()
    m1 = gauge_png("cons_volt", "VOLTS", 500, "D.C.", 50, red_from=400, needle=0.35, face=(222, 220, 208))
    m2 = gauge_png("cons_amp", "AMPERES", 100, "", 10, red_from=80, needle=0.62, face=(222, 220, 208))
    m3 = gauge_png("cons_temp", "CORE TEMP", 300, "K", 25, red_from=250, needle=0.2, face=(222, 220, 208))
    material("meter_face", "paint", base="#dedcd0", chip=0.05, rust=-2, peel=-1, dirt=0.3)
    plate = label_png("cons_plate", [("CONTAINMENT CONTROL", 0.8), ("SECTOR C  -  AUTHORISED STAFF ONLY", 0.55)], 600, 120,
                      bg=(30, 34, 38), fg=(214, 210, 196), font="cond")
    material("cons_plate", "paint", base="#1e2226", chip=0.1, rust=-2, peel=-1, dirt=0.3)
    W = 2.4
    # the body: one side profile (sloped desk at the front, riser for the monitors at the back)
    slab([(-0.36, 0.0), (0.55, 0.0), (0.55, 1.04), (0.12, 1.04), (-0.36, 0.76)], W, (0, 0, 0), (90, 0, 90), m="lab_grey",
         bevel=0.012)
    box((W - 0.06, 0.02, 0.08), (0, -0.365, 0.045), m="cable_black")                  # kick strip
    for x in (-0.6, 0.6):                                                              # front access panels
        box((1.0, 0.012, 0.5), (x, -0.365, 0.38), m="lab_grey", bevel=0.004)
        for k in range(7):
            box((0.6, 0.008, 0.014), (x, -0.373, 0.2 + k * 0.035), m="cable_black")
        for sx in (-0.46, 0.46):
            for sz in (0.16, 0.6):
                cyl(0.008, 0.008, (x + sx, -0.373, sz), (90, 0, 0), m="lab_steel", n=6)
    decal("cons_plate", plate, here((0, -0.372, 0.68), (90, 0, 0)), (0.5, 0.1))
    box((0.52, 0.004, 0.11), (0, -0.369, 0.68), m="cons_plate")
    # the sloped control face
    with place(T((0, -0.12, 0.9), (30.3, 0, 0))):
        box((W - 0.04, 0.55, 0.02), (0, 0, 0.01), m="lab_dark", bevel=0.004)
        meters = ((-0.95, m1), (-0.72, m2), (0.78, m3))
        for x, img in meters:                                  # (decals first: the material reads them once)
            decal("meter_face", img, here((x, 0.08, 0.0375)), (0.17, 0.17))
        for x, img in meters:
            cyl(0.095, 0.015, (x, 0.08, 0.027), m="lab_steel", n=16)
            cyl(0.085, 0.003, (x, 0.08, 0.036), m="meter_face", n=16)
        for r in range(2):
            for i in range(12):
                toggle((-0.45 + i * 0.07, -0.14 + r * 0.09, 0.02))
        for i in range(6):
            with place(T((-0.42 + i * 0.13, 0.16, 0.02))):
                cyl(0.025, 0.025, (0, 0, 0.012), m="bakelite", n=10)
                box((0.004, 0.02, 0.004), (0, 0.01, 0.026), m="lab_white")
        for i, mm in enumerate(("glow_green", "glow_green", "glow_amber", "glow_red", "glow_green", "glow_amber")):
            button((0.42 + i * 0.07, -0.12, 0.02), 0.01, mm)
        for i in range(8):
            button((0.4 + i * 0.07, -0.2, 0.02), 0.008, "glow_green" if i % 3 else "glow_red")
        # the emergency button under its flip-up cover
        with place(T((1.02, -0.12, 0.02))):
            cyl(0.05, 0.02, (0, 0, 0.01), m="hazard", n=12)
            cyl(0.03, 0.025, (0, 0, 0.03), m="glow_red", n=12)
            with place(T((0, 0.05, 0.05), (-70, 0, 0))):
                box((0.1, 0.1, 0.004), (0, -0.05, 0), m="tank_glass")
    # keyboard on a pull-out tray
    for x in (-0.3, 0.3):
        box((0.02, 0.3, 0.02), (x, -0.42, 0.69), m="lab_steel")
    box((0.68, 0.3, 0.02), (0, -0.5, 0.71), m="lab_dark", bevel=0.004)
    with place(T((0, -0.52, 0.735), (-4, 0, 0))):
        box((0.5, 0.18, 0.03), m="lab_white", bevel=0.008)
        for r in range(4):
            for i in range(13):
                box((0.03, 0.03, 0.012), (-0.21 + i * 0.035, -0.055 + r * 0.037, 0.02), m="lab_grey", bevel=0.003)
    cable(sag((0.2, -0.43, 0.75), (0.25, -0.36, 0.66), 0.06, 5), 0.004, "cable_grey", 0.02, 5)
    # three old monitors on the riser
    for i, x in enumerate((-0.75, 0.0, 0.75)):
        with place(T((x, 0.3, 1.04), (0, 0, (-1 + i) * -10))):
            box((0.46, 0.42, 0.38), (0, 0.05, 0.2), m="lab_white", bevel=0.03, seg=2)
            box((0.3, 0.2, 0.28), (0, 0.3, 0.19), m="lab_white", bevel=0.04)
            box((0.4, 0.02, 0.32), (0, -0.165, 0.21), m="lab_dark", bevel=0.01)
            with group("Screen"):
                box((0.36, 0.01, 0.28), (0, -0.172, 0.21), m="screen")
            button((0.17, -0.18, 0.04), 0.008, "glow_green", (90, 0, 0))
            cable([(0.05, 0.4, 0.1), (0.08, 0.45, 0.02), (0.1, 0.5, -0.2)], 0.012, "cable_black", 0.05, 6)
    # cable bundles out of the back, down to the floor and away
    for k, m_ in enumerate(("cable_black", "cable_grey", "cable_black", "cable_red", "cable_blue", "cable_black")):
        x = -0.9 + k * 0.35
        cable([(x, 0.55, 0.9), (x + 0.02, 0.6, 0.7), (x, 0.64, 0.3), (x + 0.1, 0.7, 0.03), (x + 0.2 * (k % 2), 1.2, 0.03)],
              0.016, m_, bend=0.12)


@piece("ServerRack", close=((1.6, -2.6, 4.6), (0, 0, 3.6), 45))
def server_rack():
    """an equipment rack: six units of panels, vents and blinking lights, patch cables looping
    between them, a cable bundle out of the top"""
    lab_materials()
    W, D, H = 0.62, 0.9, 2.0
    for x in (-W / 2, W / 2):
        for y in (-D / 2, D / 2):
            box((0.04, 0.04, H), (x, y, H / 2), m="lab_dark", bevel=0.006)
    for z in (0.02, H - 0.02):
        box((W, D, 0.04), (0, 0, z), m="lab_dark", bevel=0.006)
    box((W, 0.02, H), (0, D / 2, H / 2), m="lab_grey")
    for sx in (-1, 1):                                       # louvred side panels
        x = sx * (W / 2 + 0.012)
        box((0.012, D - 0.03, H - 0.05), (x, 0, H / 2), m="lab_dark", bevel=0.003)
        for zb in (0.25, H - 0.45):
            for k in range(6):
                box((0.006, D - 0.3, 0.012), (x + sx * 0.007, 0, zb + k * 0.035), m="cable_black")
    box((W + 0.04, D + 0.02, 0.06), (0, 0, 0.03), m="cable_black", bevel=0.006)          # plinth
    for x in (-W / 2 + 0.03, W / 2 - 0.03):
        box((0.02, 0.02, H - 0.1), (x, -D / 2 + 0.02, H / 2), m="lab_steel")
        for i in range(40):
            box((0.008, 0.004, 0.008), (x, -D / 2 + 0.008, 0.08 + i * 0.045), m="cable_black")
    units = [(0.12, 0.3, "drive"), (0.42, 0.26, "vent"), (0.72, 0.22, "panel"), (1.0, 0.26, "drive"), (1.32, 0.22, "panel"),
             (1.62, 0.26, "vent")]
    leds = []
    for i, (z, h, kind) in enumerate(units):
        box((W - 0.07, D - 0.1, h - 0.02), (0, 0.02, z + h / 2), m="lab_grey" if i % 2 else "lab_dark", bevel=0.006)
        face_y = -D / 2 + 0.03
        box((W - 0.06, 0.012, h - 0.02), (0, face_y, z + h / 2), m="lab_white" if kind == "panel" else "lab_dark", bevel=0.004)
        if kind == "drive":
            for k in range(6):
                box((0.07, 0.008, h - 0.07), (-0.2 + k * 0.08, face_y - 0.008, z + h / 2), m="lab_grey", bevel=0.003)
                leds.append((-0.2 + k * 0.08, face_y - 0.012, z + h - 0.03, "glow_green" if k != 3 else "glow_amber"))
        elif kind == "vent":
            for k in range(8):
                box((W - 0.12, 0.006, 0.012), (0, face_y - 0.006, z + 0.04 + k * 0.025), m="cable_black")
            leds.append((0.24, face_y - 0.012, z + h - 0.03, "glow_blue"))
        else:
            for k in range(10):
                leds.append((-0.24 + k * 0.05, face_y - 0.012, z + h * 0.7, "glow_green" if k % 4 else "glow_red"))
            for k in range(8):
                box((0.022, 0.01, 0.02), (-0.18 + k * 0.05, face_y - 0.01, z + h * 0.35), m="cable_black", bevel=0.003)
    for x, y, z, mm in leds:
        with group(GLOW[mm]):
            box((0.012, 0.006, 0.008), (x, y, z), m=mm)
    # patch cables looping between the units
    colours = ("cable_yellow", "cable_blue", "cable_red", "cable_green", "cable_grey", "cable_blue")
    for k in range(8):
        a = units[k % 5]
        b = units[(k % 5) + 1]
        x0 = -0.2 + (k % 6) * 0.08
        x1 = -0.2 + ((k * 3) % 8) * 0.05
        cable(sag((x0, -D / 2 - 0.02, a[0] + a[1] * 0.35), (x1, -D / 2 - 0.02, b[0] + b[1] * 0.35), 0.12 + 0.03 * (k % 3), 6),
              0.006, colours[k % 6], bend=0.03, n=5)
    for k in range(6):
        cable([(-0.15 + k * 0.06, 0.2, H), (-0.15 + k * 0.06, 0.25, H + 0.3), (0.0 + k * 0.03, 0.3, H + 0.7)], 0.014,
              "cable_black" if k % 3 else "cable_grey", bend=0.1)


@piece("BreakerPanel", close=((1.8, -2.8, 4.0), (0, 0, 3.4), 45))
def breaker_panel():
    """a wall distribution board, door hanging open: rows of breakers (one tripped), copper bus
    bars, bundled wiring up into conduits, indicator lamps, DANGER 415 V"""
    lab_materials()
    danger = label_png("danger415", [("DANGER", 1.0), ("415 VOLTS", 0.7)], 360, 200, bg=(196, 40, 30), fg=(244, 238, 226),
                       font="sans")
    material("danger_plate", "paint", base="#c42a1e", chip=0.2, rust=-2, peel=-0.6, dirt=0.4)
    W, D, H, z0 = 0.9, 0.25, 1.2, 0.9
    zc = z0 + H / 2
    decal("danger_plate", danger, here((W / 2 + 0.014, 0, zc + 0.2), (90, 0, 90)), (0.18, 0.1))     # (side)
    box((W, 0.02, H), (0, D / 2, zc), m="lab_grey")
    for x in (-W / 2, W / 2):
        box((0.02, D, H), (x, 0, zc), m="lab_grey", bevel=0.004)
    for z in (z0, z0 + H):
        box((W, D, 0.02), (0, 0, z), m="lab_grey", bevel=0.004)
    box((W - 0.1, 0.015, H - 0.15), (0, D / 2 - 0.02, zc), m="lab_white")
    # copper bus bars and three rows of breakers
    for k in range(3):
        box((W - 0.2, 0.01, 0.025), (0, 0.05, z0 + 0.25 + k * 0.33), m="lab_copper", bevel=0.002)
        for i in range(14):
            x = -0.36 + i * 0.055
            tripped = (k == 1 and i == 6)
            with place(T((x, 0.02, z0 + 0.3 + k * 0.33))):
                box((0.05, 0.07, 0.11), m="lab_white" if i % 4 else "lab_dark", bevel=0.004)
                box((0.014, 0.02, 0.03), (0, -0.04, -0.012 if tripped else 0.012), (25 if tripped else -25, 0, 0),
                    m="cable_black", bevel=0.003)
                box((0.03, 0.002, 0.012), (0, -0.036, -0.04), m="lab_white")
    # wiring: bundles up into the conduits
    colours = ("cable_red", "cable_black", "cable_blue", "cable_yellow", "cable_grey", "cable_green")
    for i in range(14):
        x = -0.36 + i * 0.055
        cable([(x, 0.03, z0 + 0.98), (x * 0.6, 0.05, z0 + 1.08), (-0.2 + (i % 3) * 0.2, 0.06, z0 + H - 0.01)], 0.005,
              colours[i % 6], bend=0.04, n=5)
    for x in (-0.2, 0.0, 0.2):
        cyl(0.03, 0.9, (x, 0.06, z0 + H + 0.45), m="lab_steel", n=10)
        cyl(0.04, 0.05, (x, 0.06, z0 + H + 0.02), m="lab_steel", n=10)
    cyl(0.03, z0 - 0.05, (0.3, 0.06, (z0 - 0.05) / 2), m="lab_steel", n=10)
    # the door, swung open (its own mesh, hinged on its left edge - script it)
    with group("Door", (-W / 2, -D / 2, zc)), place(T((-W / 2, -D / 2, 0), (0, 0, -100))):
        box((W, 0.02, H), (W / 2, -0.01, zc), m="lab_grey", bevel=0.006)
        decal("danger_plate", danger, here((W / 2, -0.023, zc + 0.25), (90, 0, 0)), (0.18, 0.1))
        box((0.18, 0.003, 0.1), (W / 2, -0.022, zc + 0.25), m="danger_plate")
        for k in range(4):
            box((W - 0.16, 0.003, 0.012), (W / 2, -0.021, zc - 0.25 + k * 0.03), m="lab_dark")
        box((0.03, 0.03, 0.12), (W - 0.06, -0.035, zc), m="bakelite", bevel=0.008)
    box((0.003, 0.18, 0.1), (W / 2 + 0.012, 0, zc + 0.2), m="danger_plate")
    tag = label_png("tag_dnso", [("DANGER", 0.9), ("DO NOT", 0.8), ("SWITCH ON", 0.8), ("men at work", 0.5)], 200, 300,
                    bg=(214, 60, 40), fg=(250, 244, 230), font="cond")
    material("tag_card", "paper", base="#c9452e")
    with place(T((-0.36 + 6 * 0.055, -0.06, z0 + 0.3 + 0.33 - 0.12), (8, 0, 6))):     # hung on the tripped breaker
        cable([(0, 0.0, 0.07), (0.0, -0.01, 0.1), (0, 0.02, 0.12)], 0.0015, "cable_black", n=4)
        decal("tag_card", tag, here((0, -0.0015, 0.02), (90, 0, 0)), (0.058, 0.087))
        box((0.06, 0.002, 0.09), (0, 0, 0.02), m="tag_card")
    for i, mm in enumerate(("glow_green", "glow_green", "glow_red")):
        with group(GLOW[mm]):
            sphere(0.016, (0.25 + i * 0.05, -0.03, z0 + H - 0.08), m=mm, n=8, rings=5)


@piece("Transformer", close=((3.0, -4.2, 4.6), (0, 0, 3.2), 45))
def transformer():
    """a big oil transformer on a concrete plinth: cooling fins down both sides, three ceramic
    bushings on top with cables away, hazard stripes, its rating plate"""
    lab_materials()
    material("plinth", "concrete", base="#8a877e")
    material("ceramic", "porcelain", base="#7a3a26", craze=0.1, stain=0.3, chips=0.2, rusty=0.0)
    rating = label_png("rating", [("TRANSFORMER  T-2", 0.8), ("11 kV / 415 V   500 kVA", 0.6), ("HOLLOWMERE FACILITY", 0.5)],
                       480, 200, bg=(200, 196, 184), fg=(28, 28, 26), font="cond")
    material("rating_plate", "paint", base="#c8c4b8", chip=0.1, rust=-2, peel=-1, dirt=0.4)
    box((1.9, 1.4, 0.15), (0, 0, 0.075), m="plinth", bevel=0.02)
    box((1.92, 1.42, 0.05), (0, 0, 0.17), m="hazard", bevel=0.004)
    box((1.2, 0.8, 1.4), (0, 0, 0.9), m="lab_grey", bevel=0.03)
    box((1.26, 0.86, 0.06), (0, 0, 1.62), m="lab_grey", bevel=0.01)
    for s in (-1, 1):
        for i in range(12):
            box((0.3, 0.012, 1.1), (s * 0.75, -0.33 + i * 0.06, 0.82), m="lab_grey", bevel=0.003)
        for z in (0.3, 1.35):
            cyl(0.035, 0.32, (s * 0.75, 0, z), (90, 0, 0), m="lab_grey", n=10)
    decal("rating_plate", rating, here((0, -0.405, 1.1), (90, 0, 0)), (0.36, 0.15))
    box((0.37, 0.004, 0.16), (0, -0.402, 1.1), m="rating_plate")
    for i in range(3):
        x = -0.35 + i * 0.35
        with place(T((x, 0.1, 1.65))):
            prof = [(0, 0), (0.07, 0)]
            for k in range(5):
                z = 0.05 + k * 0.08
                prof += [(0.07, z), (0.11, z + 0.02), (0.06, z + 0.05)]
            prof += [(0.05, 0.46), (0.03, 0.5), (0, 0.5)]
            lathe(prof, m="ceramic", n=14)
            cyl(0.02, 0.08, (0, 0, 0.53), m="lab_copper", n=8)
            cable([(0, 0, 0.56), (0, 0.1, 0.75), (x * 0.3, 0.5, 1.1), (x * 0.3, 0.9, 1.5)], 0.025, "cable_black", bend=0.15)
    cyl(0.08, 0.3, (0.45, -0.25, 1.8), m="lab_grey", n=12)                         # the conservator vent
    with place(T((-0.3, -0.42, 0.6))):
        gauge = gauge_png("oil_temp", "OIL TEMP", 120, "deg C", 10, red_from=95, needle=0.4)
        material("gauge_face2", "paint", base="#e0dcd0", chip=0.05, rust=-2, peel=-1, dirt=0.3)
        decal("gauge_face2", gauge, here((0, -0.03, 0), (90, 0, 0)), (0.13, 0.13))
        cyl(0.075, 0.04, (0, -0.0, 0), (90, 0, 0), m="lab_steel", n=14)
        cyl(0.068, 0.003, (0, -0.022, 0), (90, 0, 0), m="gauge_face2", n=14)


@piece("LabBench", close=((2.4, -3.4, 4.2), (0, 0, 3.0), 45))
def lab_bench():
    """a steel lab bench: an oscilloscope, a microscope, a rack of flasks, a centrifuge, papers,
    a power strip with plugs, a lamp; boxes and a toolbox underneath"""
    lab_materials()
    material("flask_glass", "glass", base="#9cb4b8", frost=0.2, dirt=0.4)
    material("fluid_green", "glowpaint", base="#5cff8a")
    material("box_card", "paper", base="#a88f62")
    W, D, Ht = 2.0, 0.8, 0.9
    box((W, D, 0.04), (0, 0, Ht), m="lab_dark", bevel=0.008)
    for x in (-W / 2 + 0.05, W / 2 - 0.05):
        for y in (-D / 2 + 0.05, D / 2 - 0.05):
            box((0.05, 0.05, Ht - 0.02), (x, y, (Ht - 0.02) / 2), m="lab_steel", bevel=0.006)
    box((W - 0.1, D - 0.1, 0.02), (0, 0, 0.25), m="lab_steel", bevel=0.004)
    box((W, 0.03, 0.4), (0, D / 2 - 0.015, Ht + 0.2), m="lab_grey", bevel=0.006)        # back upstand
    top = Ht + 0.02
    # oscilloscope
    with place(T((-0.6, 0.05, top))):
        box((0.42, 0.38, 0.26), (0, 0, 0.13), m="lab_blue", bevel=0.02)
        with group("ScreenGreen"):
            box((0.16, 0.01, 0.13), (-0.08, -0.19, 0.15), m="glow_green")
        for r in range(2):
            for i in range(3):
                with place(T((0.06 + i * 0.05, -0.195, 0.1 + r * 0.08), (90, 0, 0))):
                    cyl(0.016, 0.02, m="bakelite", n=8)
        for i, mm in enumerate(("cable_red", "cable_black")):
            cable([(0.1 + i * 0.05, -0.19, 0.05), (0.15 + i * 0.05, -0.3, 0.02), (0.3 + i * 0.08, -0.3, 0.0)], 0.005, mm,
                  bend=0.04, n=5)
    # microscope: heavy foot, C-arm, stage, the nosepiece of objectives, angled eyepieces
    with place(T((0.05, 0.12, top))):
        box((0.16, 0.22, 0.035), (0, 0, 0.0175), m="lab_dark", bevel=0.01)
        slab([(0.07, 0.035), (0.11, 0.035), (0.11, 0.24), (0.08, 0.34), (-0.02, 0.38), (-0.04, 0.33), (0.04, 0.29),
              (0.06, 0.22)], 0.05, (0, 0, 0), (90, 0, 90), m="lab_white", bevel=0.006)
        box((0.12, 0.11, 0.012), (0, -0.02, 0.14), m="lab_dark", bevel=0.003)          # stage
        box((0.03, 0.06, 0.003), (0.0, -0.02, 0.148), m="tank_glass")                   # a slide
        for sx in (-1, 1):
            cyl(0.028, 0.02, (sx * 0.04, 0.09, 0.17), (0, 90, 0), m="lab_steel", n=10)   # focus knobs
        with place(T((0, -0.02, 0.27))):
            cyl(0.03, 0.03, (0, 0, 0.0), m="lab_white", n=10)                          # nosepiece
            for k in range(3):
                a2 = math.radians(120 * k)
                cyl(0.008, 0.05 - 0.008 * k, (math.cos(a2) * 0.016, math.sin(a2) * 0.016, -0.035), m="lab_steel", n=6)
            box((0.07, 0.08, 0.05), (0, 0.03, 0.04), m="lab_white", bevel=0.01)          # head
            for sx in (-1, 1):
                with place(T((sx * 0.018, -0.0, 0.07), (-35, 0, 0))):
                    cyl(0.011, 0.08, (0, 0, 0.04), m="lab_dark", n=8)
                    cyl(0.013, 0.012, (0, 0, 0.085), m="cable_black", n=8)
    # flasks in a rack, one tipped over
    with place(T((0.55, 0.15, top))):
        box((0.36, 0.12, 0.012), (0, 0, 0.08), m="lab_steel")
        for i in range(5):
            x = -0.14 + i * 0.07
            lathe([(0, 0), (0.016, 0), (0.016, 0.16), (0.02, 0.17), (0, 0.17)], (x, 0, 0.0), m="flask_glass", n=8)
            if i in (1, 3):
                with group("LiquidGreen"):
                    lathe([(0, 0.002), (0.014, 0.002), (0.014, 0.09), (0, 0.09)], (x, 0, 0.0), m="fluid_green", n=8)
        lathe([(0, 0), (0.08, 0), (0.07, 0.08), (0.025, 0.16), (0.025, 0.2), (0, 0.2)], (0.0, -0.22, 0.0), m="flask_glass", n=12)
        with group("LiquidGreen"):
            lathe([(0, 0.002), (0.075, 0.002), (0.068, 0.06), (0, 0.06)], (0.0, -0.22, 0.0), m="fluid_green", n=12)
        lathe([(0, 0), (0.05, 0), (0.05, 0.14), (0.02, 0.17), (0, 0.17)], (0.25, -0.15, 0.05), (0, 90, 20), m="flask_glass", n=10)
    # centrifuge
    lathe([(0, 0), (0.17, 0), (0.18, 0.02), (0.18, 0.2), (0.16, 0.22), (0, 0.22)], (-0.15, -0.15, top), m="lab_white", n=18)
    cyl(0.12, 0.012, (-0.15, -0.15, top + 0.225), m="tank_glass", n=16)
    # papers, a power strip with plugs, a lamp
    for i, (x, y, a) in enumerate(((0.3, -0.25, 12), (0.42, -0.22, -18), (-0.9, -0.2, 30))):
        box((0.21, 0.297, 0.002), (x, y, top + 0.002 + 0.002 * i), (0, 0, a), m="paper")
    with place(T((-0.2, 0.33, top))):
        box((0.4, 0.06, 0.04), (0, 0, 0.02), m="lab_white", bevel=0.008)
        for i in range(4):
            box((0.04, 0.04, 0.05), (-0.13 + i * 0.09, 0, 0.06), m="cable_black", bevel=0.006)
            cable(sag((-0.13 + i * 0.09, 0, 0.08), (-0.6 + i * 0.25, -0.1, 0.06), 0.03, 5), 0.005, "cable_black", 0.03, 5)
        cable([(0.2, 0, 0.02), (0.25, 0.05, 0.0), (0.4, 0.1, -0.3), (0.5, 0.2, -0.9)], 0.007, "cable_grey", 0.1)
    with place(T((0.85, 0.3, top))):
        cyl(0.07, 0.02, (0, 0, 0.01), m="lab_dark", n=12)
        sweep([(0, 0, 0.02), (0, 0, 0.3), (0.05, -0.15, 0.45)], 0.01, "lab_dark", 6, bend=0.06)
        with place(T((0.05, -0.16, 0.43), (-35, 0, 0))):
            lathe([(0.0, 0.0), (0.07, -0.05), (0.07, -0.07), (0.0, -0.02)], m="lab_dark", n=12)
    # under the bench
    for i, (x, h) in enumerate(((-0.6, 0.25), (-0.3, 0.2), (0.4, 0.3))):
        box((0.3, 0.35, h), (x, 0.0, 0.26 + h / 2), (0, 0, i * 7), m="box_card", bevel=0.005)
    box((0.4, 0.2, 0.18), (0.75, -0.05, 0.35), m="lab_blue", bevel=0.01)          # toolbox


@piece("CableTray", close=((4.2, -9.8, 6.4), (0, -4.8, 4.2), 35))
def cable_tray():
    """a 3 m run of ladder cable tray on hanger rods, loaded with bundles, a few cables
    drooping out of it, a junction box on the far end; at the open end the cables spill out and
    run down the wall to the floor. Tray at 2.5 m, rods up to a 3.1 m ceiling."""
    lab_materials()
    L, W = 3.0, 0.45
    z = 2.5
    for x in (-W / 2, W / 2):
        box((0.02, L, 0.08), (x, 0, z + 0.04), m="lab_steel", bevel=0.003)
    for i in range(11):
        box((W, 0.03, 0.015), (0, -L / 2 + 0.1 + i * 0.28, z + 0.008), m="lab_steel")
    for y in (-L / 2 + 0.3, L / 2 - 0.3):
        for x in (-W / 2 - 0.03, W / 2 + 0.03):
            cyl(0.008, 0.6, (x, y, z + 0.3), m="lab_steel", n=6)
        box((W + 0.1, 0.04, 0.03), (0, y, z - 0.015), m="lab_steel", bevel=0.004)
    colours = ("cable_black", "cable_grey", "cable_black", "cable_red", "cable_blue", "cable_black", "cable_yellow",
               "cable_black", "cable_green")
    for k, m_ in enumerate(colours):
        x = -W / 2 + 0.05 + (k % 5) * 0.085
        zz = z + 0.03 + (k // 5) * 0.04
        r = 0.018 if k % 3 else 0.026
        if k < 6:              # these leave the open end and drop down the wall
            xw, yw = x * 0.7 + 0.01 * k, -L / 2 - 0.16 - 0.03 * (k % 3)
            cable([(x, L / 2, zz), (x + 0.01 * (k % 2), 0, zz + 0.005), (x, -L / 2 + 0.05, zz),
                   (x * 0.8, -L / 2 - 0.12, zz - 0.06), (xw, yw, zz - 0.4), (xw, yw, 0.3), (xw, yw + 0.04, 0.06),
                   (xw + 0.05 * (k % 2 - 0.5), yw + 0.3 + 0.05 * k, r)], r, m_, bend=0.1, n=6)
        else:
            cable([(x, -L / 2, zz), (x + 0.01 * (k % 2), 0, zz + 0.005), (x, L / 2, zz)], r, m_, n=6)
    # a few drooping out between the rungs
    for k, (y, m_) in enumerate(((-0.6, "cable_black"), (0.2, "cable_red"), (0.9, "cable_grey"))):
        x = -0.1 + k * 0.1
        cable([(x, y - 0.3, z + 0.03), (x, y, z - 0.02)] + sag((x, y, z - 0.02), (x + 0.05, y + 0.6, z - 0.02), 0.55, 8)[1:]
              + [(x + 0.05, y + 0.7, z + 0.03)], 0.012, m_, bend=0.06)
    with place(T((0, L / 2 + 0.15, z + 0.05))):
        box((0.35, 0.25, 0.3), m="lab_grey", bevel=0.01)
        box((0.36, 0.02, 0.31), (0, -0.13, 0.0), (0, 0, 0), m="lab_dark", bevel=0.006)
        for x in (-0.12, 0.12):
            box((0.03, 0.03, 0.03), (x, -0.145, 0.12), m="lab_steel", bevel=0.005)
        box((0.12, 0.004, 0.08), (0, -0.142, 0.0), m="hazard")


@piece("PipeManifold", close=((2.6, -3.6, 3.8), (0, 0, 3.0), 45))
def pipe_manifold():
    """a wall pipe manifold: three insulated and painted lines with flanges, red and blue valve
    wheels, pressure gauges, drops to the floor, colour bands and flow labels"""
    lab_materials()
    material("pipe_red", "paint", base="#7a2a22", chip=0.25, rust=-3.0, peel=-0.4, dirt=0.5)
    material("pipe_green", "paint", base="#3d5a3e", chip=0.25, rust=-3.0, peel=-0.4, dirt=0.5)
    material("lagging", "canvas", base="#c2bca8", stain=0.4, moldy=0.1)
    gauges = [gauge_png("pm_g%d" % i, lbl, top, "bar", top / 10, red_from=top * 0.8, needle=n_)
              for i, (lbl, top, n_) in enumerate((("COOLANT", 10, 0.42), ("STEAM", 16, 0.7), ("RETURN", 10, 0.2)))]
    material("pm_face", "paint", base="#e0dcd0", chip=0.05, rust=-2, peel=-1, dirt=0.3)
    L = 2.6
    lines = ((1.9, "pipe_green", 0.06), (1.55, "lagging", 0.085), (1.2, "pipe_red", 0.06))
    for i, (z, m_, r) in enumerate(lines):                    # (decals first: the material reads them once)
        decal("pm_face", gauges[i], here((-0.6 + i * 0.6 + 0.3, -0.15 - r - 0.142, z), (90, 0, 0)), (0.1, 0.1))
    for i, (z, m_, r) in enumerate(lines):
        cyl(r, L, (0, -0.15, z), (0, 90, 0), m=m_, n=14)
        for x in (-1.0, 0.0, 1.0):
            cyl(r + 0.025, 0.04, (x, -0.15, z), (0, 90, 0), m="lab_steel", n=14)
        # a valve with its wheel, a gauge on a stub, the drop down to the floor
        x = -0.6 + i * 0.6
        cyl(r + 0.02, 0.18, (x, -0.15, z), (0, 90, 0), m="lab_grey", n=12)
        cyl(0.015, 0.16, (x, -0.15, z + r + 0.08), m="lab_steel", n=6)
        with place(T((x, -0.15, z + r + 0.17))):
            torus(0.1, 0.012, m="pipe_red" if i != 1 else "lab_blue", n=16, k=5)
            for a in (0, 60, 120):
                box((0.19, 0.012, 0.01), (0, 0, 0), (0, 0, a), m="lab_steel")
        gx = x + 0.3
        cyl(0.01, 0.12, (gx, -0.15 - r - 0.05, z), (90, 0, 0), m="lab_steel", n=6)
        cyl(0.06, 0.03, (gx, -0.15 - r - 0.12, z), (90, 0, 0), m="lab_steel", n=14)
        cyl(0.054, 0.003, (gx, -0.15 - r - 0.137, z), (90, 0, 0), m="pm_face", n=14)
        sweep([(L / 2 - 0.2 - i * 0.12, -0.15, z), (L / 2 - 0.05 - i * 0.12, -0.15 - 0.0, z),
               (L / 2 - 0.05 - i * 0.12, -0.15 - 0.05 * i, 0.02)], r * 0.8, m_ if m_ != "lagging" else "lab_grey", 12, bend=0.15)
    for x in (-1.1, 0.0, 1.1):
        box((0.06, 0.16, 1.0), (x, -0.02, 1.55), m="lab_dark", bevel=0.006)
        for z, _, r in lines:
            torus(r + 0.01, 0.008, (x, -0.15, z), (0, 90, 0), m="lab_steel", n=14, k=4)
    cyl(0.07, 0.4, (L / 2 + 0.1, -0.15, 1.55), (0, 90, 0), m="lab_grey", n=12)


@piece("PowerSwitch", close=((1.6, -3.0, 4.6), (0, 0, 3.8), 40))
def power_switch():
    """the main power switch on the wall: a slate board, three copper knife blades thrown
    down on their bakelite bar and red handle (the "Lever" mesh, hinged along X at the
    bottom clips - script it up to restore the power), red and green lamps, cables to conduits"""
    lab_materials()
    material("slate", "paint", base="#2e3235", chip=0.1, rust=-3.0, peel=-1.0, dirt=0.45, gloss=0.25, streaks=0.1)
    material("lever_red", "paint", base="#8c2018", chip=0.3, rust=-3.0, peel=-0.6, dirt=0.4, gloss=0.6)
    sign = label_png("mainpower", [("MAIN POWER", 0.9), ("SECTOR C", 0.6)], 420, 150, bg=(196, 160, 40), fg=(24, 22, 20),
                     font="cond")
    material("power_sign", "paint", base="#c4a028", chip=0.15, rust=-3, peel=-1, dirt=0.4)
    decal("power_sign", sign, here((0, -0.032, 1.78), (90, 0, 0)), (0.36, 0.13))
    zh, zj, yb = 1.15, 1.57, -0.06            # hinge clips, jaws, blade line in front of the board
    # the board on its steel frame
    box((0.62, 0.03, 0.86), (0, 0.0, 1.36), m="lab_dark", bevel=0.006)
    box((0.54, 0.03, 0.76), (0, -0.02, 1.36), m="slate", bevel=0.004)
    for x in (-0.28, 0.28):
        for z in (0.98, 1.74):
            cyl(0.012, 0.012, (x, -0.04, z), (90, 0, 0), m="lab_steel", n=6)
    box((0.38, 0.006, 0.14), (0, -0.018, 1.78), m="power_sign", bevel=0.002)
    # clips: hinges at the bottom, jaws at the top
    for x in (-0.13, 0.0, 0.13):
        for z in (zh, zj):
            box((0.05, 0.03, 0.04), (x, -0.045, z), m="lab_dark", bevel=0.004)
            for sx in (-1, 1):
                box((0.006, 0.05, 0.05), (x + sx * 0.012, yb + 0.01, z), m="lab_copper", bevel=0.002)
        # wiring: out of the jaws and hinges, through the board (the conduits run behind it)
        cable([(x, -0.045, zj + 0.02), (x, -0.045, zj + 0.08), (x, -0.03, zj + 0.1)], 0.014,
              ("cable_red", "cable_black", "cable_blue")[int(x * 10 + 1.3) % 3], bend=0.03, n=6)
        cable([(x, -0.045, zh - 0.02), (x, -0.045, zh - 0.08), (x, -0.03, zh - 0.1)], 0.014, "cable_black", bend=0.03,
              n=6)
    cyl(0.04, 0.5, (0, 0.04, 2.05), m="lab_steel", n=10)
    cyl(0.04, 0.93, (0, 0.04, 0.465), m="lab_steel", n=10)
    # the lever: blades, bar and handle, thrown down and out (OFF)
    with group("Lever", (0, yb, zh)), place(T((0, yb, zh), (115, 0, 0))):
        for x in (-0.13, 0.0, 0.13):
            box((0.008, 0.04, zj - zh), (x, 0, (zj - zh) / 2), m="lab_copper", bevel=0.002)
            cyl(0.008, 0.035, (x, 0, 0), (0, 90, 0), m="lab_steel", n=6)
        cyl(0.022, 0.34, (0, -0.0, zj - zh - 0.08), (0, 90, 0), m="bakelite", n=10)
        sweep([(0, 0, zj - zh - 0.08), (0, -0.1, zj - zh - 0.08), (0, -0.28, zj - zh - 0.04)], 0.02, "lever_red", 8,
              bend=0.04)
        cyl(0.026, 0.02, (0, -0.285, zj - zh - 0.04), (90, 0, 0), m="bakelite", n=10)
    # the lamps: red (off) and green (on) - the green one is dead until you script it
    with place(T((0.2, -0.04, 1.66))):
        for i, (mm, live) in enumerate((("glow_red", True), ("glow_green", False))):
            cyl(0.03, 0.02, (i * -0.08, 0, 0), (90, 0, 0), m="lab_steel", n=10)
            with group(GLOW[mm] if live else "Main"):
                sphere(0.02, (i * -0.08, -0.015, 0), m=mm if live else "cable_green", n=10, rings=5)


@piece("LabLamp", close=((1.5, -2.4, 0.12), (0, 0, 0.75), 35))
def lab_lamp():
    """a hanging industrial lamp: ceiling rose, cable, an enamel shade, a wire cage round the
    bulb (the "LampWhite" mesh - SetupLabGlow turns it on). Top at the ceiling: 1.2 m drop."""
    lab_materials()
    material("enamel", "paint", base="#3e4a44", chip=0.4, rust=-3.0, peel=-0.5, dirt=0.5, gloss=0.7)
    H = 1.2
    cyl(0.07, 0.03, (0, 0, H - 0.015), m="lab_white", n=14)
    cable([(0, 0, H - 0.03), (0.01, 0, H - 0.5), (0, 0, 0.36)], 0.006, "cable_black", n=5)
    cyl(0.02, 0.05, (0, 0, 0.35), m="lab_steel", n=8)
    lathe([(0.27, 0.11), (0.26, 0.12), (0.18, 0.2), (0.06, 0.32), (0.03, 0.33)], m="enamel", n=24)     # outside
    lathe([(0.03, 0.315), (0.055, 0.305), (0.172, 0.195), (0.252, 0.118), (0.262, 0.11)], m="lab_white", n=24)
    torus(0.266, 0.006, (0, 0, 0.11), m="enamel", n=24, k=5)                                             # rolled rim
    cyl(0.035, 0.11, (0, 0, 0.255), m="bakelite", n=10)
    with group("LampWhite"):
        sphere(0.05, (0, 0, 0.13), m="glow_white", n=12, rings=6, squash=(1, 1, 1.3))
    for k in range(6):                          # the cage
        a = 2 * math.pi * k / 6
        sweep([(math.cos(a) * 0.12, math.sin(a) * 0.12, 0.12), (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.05),
               (0, 0, 0.0)], 0.004, "lab_steel", 5, bend=0.03)
    torus(0.115, 0.004, (0, 0, 0.08), m="lab_steel", n=16, k=4)
