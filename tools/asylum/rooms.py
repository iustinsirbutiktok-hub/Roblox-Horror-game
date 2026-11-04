# Treatment rooms and storage: wall sink, medicine cabinet, filing cabinet,
# the electroshock machine, the restraint chair, the hydrotherapy tub.
from kit import *  # noqa


def bottle(at, h=0.14, r=0.032, m="amber", rot=(0, 0, 0)):
    lathe([(0, 0), (r, 0), (r, h * 0.68), (r * 0.42, h * 0.86), (r * 0.42, h), (0, h)], at, rot, m=m, n=10)
    if rot == (0, 0, 0):
        cyl(r * 0.5, h * 0.08, (at[0], at[1], at[2] + h + h * 0.03), m="bakelite", n=8)


@piece("MedicineCabinet", close=((1.6, -2.4, 4.4), (0, 0, 3.8), 50))
def medicine_cabinet():
    """a tall pharmacy cabinet: glass doors over shelves of bottles (one pane
    smashed, shards left in the frame), drawers and a cupboard below, POISON on the door"""
    material("med_paint", "paint", base="#d2cdb8", chip=0.55, rust=0.6, under="#86998b", peel=0.5)
    material("med_glass", "glass", base="#5a6458", frost=0.45, dirt=0.8)
    W, D, H = 0.9, 0.42, 1.85
    for x in (-W / 2 + 0.01, W / 2 - 0.01):
        box((0.02, D, H - 0.08), (x, 0, 0.08 + (H - 0.08) / 2), m="med_paint", bevel=0.004)
    box((W, 0.015, H - 0.08), (0, D / 2 - 0.008, 0.08 + (H - 0.08) / 2), m="med_paint")
    box((W + 0.03, D + 0.03, 0.03), (0, -0.005, H), m="med_paint", bevel=0.008)
    for x in (-W / 2 + 0.04, W / 2 - 0.04):
        for y in (-D / 2 + 0.04, D / 2 - 0.04):
            cyl(0.018, 0.08, (x, y, 0.04), m="iron", n=8)
    for z in (0.09, 0.62, 0.92, 1.22, 1.5):
        box((W - 0.04, D - 0.03, 0.016), (0, 0.0, z), m="med_paint", bevel=0.002)
    # bottles, jars, a toppled one, a box
    rows = ((0.928, [(-0.33, "amber"), (-0.25, "amber"), (-0.15, "green_glass"), (0.02, "glass"), (0.12, "amber"),
                     (0.3, "green_glass")]),
            (1.228, [(-0.3, "glass"), (-0.2, "green_glass"), (-0.05, "amber"), (0.05, "amber"), (0.25, "glass")]),
            (1.508, [(-0.32, "amber"), (-0.1, "amber"), (0.18, "green_glass"), (0.3, "amber")]))
    for z, items in rows:
        for i, (x, mm) in enumerate(items):
            bottle((x, 0.02 + 0.05 * (i % 2), z), 0.12 + 0.05 * ((i * 7) % 3) / 2, 0.028 + 0.008 * (i % 2), mm)
    bottle((0.2, -0.05, 0.96), 0.13, 0.03, "amber", rot=(0, 90, 30))
    box((0.12, 0.08, 0.1), (-0.05, 0.08, 1.58), (0, 0, 12), m="paper", bevel=0.004)
    # the glass doors (right one open, its pane smashed)
    for side in (-1, 1):
        ang = 0 if side < 0 else 62
        with place(T((side * (W / 2 - 0.015), -D / 2, 0), (0, 0, -ang if side > 0 else 0))):
            cx = -side * (W / 4 - 0.01)
            fr = [(-W / 4 + 0.02, 0.68), (W / 4 - 0.02, 0.68)]
            for zz in (0.66, 1.8):
                box((W / 2 - 0.02, 0.02, 0.04), (cx, -0.01, zz), m="med_paint", bevel=0.004)
            for xx in (cx - W / 4 + 0.03, cx + W / 4 - 0.03):
                box((0.04, 0.02, 1.14), (xx, -0.01, 1.23), m="med_paint", bevel=0.004)
            if side < 0:
                box((W / 2 - 0.08, 0.006, 1.1), (cx, -0.008, 1.23), m="med_glass")
            else:
                for k, (zz, hh) in enumerate(((0.72, 0.09), (1.72, 0.12))):
                    poly = [(-W / 4 + 0.05, 0), (W / 4 - 0.05, 0), (W / 4 - 0.05, hh * 0.4), (0.05, hh), (-0.04, hh * 0.3),
                            (-W / 4 + 0.05, hh * 0.8)]
                    if k == 1:
                        poly = [(x, -y) for x, y in poly]
                    slab(poly, 0.006, (cx, -0.008, zz), (90, 0, 0), m="med_glass")
                sphere(0.016, (cx - side * 0.17, -0.03, 1.2), m="chrome", n=8, rings=5)
            _ = fr
    # shards on the floor
    for i, (x, y) in enumerate(((0.3, -0.45), (0.45, -0.38), (0.2, -0.6), (0.52, -0.55))):
        slab([(0, 0), (0.06, 0.01), (0.03, 0.05)], 0.004, (x, y, 0.003), (0, 0, i * 47), m="med_glass")
    poison = label_png("poison", [("POISON", 1.0), ("SCHEDULE I", 0.5)], 320, 150, bg=(170, 40, 30), fg=(240, 226, 200),
                       font="serif")
    material("poison_label", "paper", base="#a83a2c")
    decal("poison_label", poison, here((-W / 4, -D / 2 - 0.022, 1.42), (90, 0, 0)), (0.17, 0.08))
    box((0.17, 0.003, 0.08), (-W / 4, -D / 2 - 0.021, 1.42), m="poison_label")
    # drawers and cupboard below
    for i, z in enumerate((0.55, 0.43)):
        box((W - 0.05, 0.02, 0.1), (0, -D / 2 - (0.06 if i == 1 else 0.01), z), m="med_paint", bevel=0.004)
        sweep([(-0.06, -D / 2 - 0.02 - (0.05 if i == 1 else 0), z), (-0.06, -D / 2 - 0.045 - (0.05 if i == 1 else 0), z),
               (0.06, -D / 2 - 0.045 - (0.05 if i == 1 else 0), z), (0.06, -D / 2 - 0.02 - (0.05 if i == 1 else 0), z)],
              0.005, "chrome", 6, bend=0.01)
    for side in (-1, 1):
        box((W / 2 - 0.03, 0.02, 0.26), (side * W / 4, -D / 2 - 0.01, 0.22), m="med_paint", bevel=0.004)
        cyl(0.01, 0.02, (side * 0.06, -D / 2 - 0.03, 0.25), (90, 0, 0), m="chrome", n=8)


@piece("FilingCabinet", close=((1.4, -2.6, 3.4), (0, -0.6, 2.4), 50))
def filing_cabinet():
    """a four-drawer patient-records cabinet; one drawer hanging open, files spilling"""
    material("file_paint", "paint", base="#6f7563", chip=0.5, rust=0.6, gloss=0.35, under="#7a6a4a")
    material("folder", "paper", base="#c4ab72")
    W, D, H = 0.46, 0.66, 1.32
    box((W, D, H), (0, 0, H / 2), m="file_paint", bevel=0.01)
    for i in range(4):
        z = 0.17 + i * 0.32
        out = 0.42 if i == 1 else (0.04 if i == 3 else 0.0)
        with place(T((0, -out, 0))):
            box((W - 0.03, 0.025, 0.29), (0, -D / 2 - 0.01, z), m="file_paint", bevel=0.006)
            box((0.1, 0.012, 0.035), (0, -D / 2 - 0.025, z + 0.07), m="chrome", bevel=0.002)
            card = label_png("card_%d" % i, [("PATIENTS", 0.7), (("A - F", "G - L", "M - R", "S - Z")[3 - i], 1.0)], 200, 80,
                             bg=(218, 204, 168), font="type")
            material("card_%d" % i, "paper")
            decal("card_%d" % i, card, here((0, -D / 2 - 0.0325, z + 0.07), (90, 0, 0)), (0.085, 0.03))
            box((0.085, 0.002, 0.03), (0, -D / 2 - 0.0315, z + 0.07), m="card_%d" % i)
            sweep([(-0.05, -D / 2 - 0.02, z), (-0.05, -D / 2 - 0.045, z), (0.05, -D / 2 - 0.045, z), (0.05, -D / 2 - 0.02, z)],
                  0.006, "chrome", 6, bend=0.01)
            if out > 0.1:
                for s in (-1, 1):
                    box((0.012, 0.42, 0.25), (s * (W / 2 - 0.03), -D / 2 + 0.2, z), m="file_paint")
                box((W - 0.06, 0.42, 0.01), (0, -D / 2 + 0.2, z - 0.12), m="file_paint")
                for k in range(9):
                    yy = -D / 2 + 0.05 + k * 0.04
                    tilt = (k * 13 % 7 - 3) * 3
                    box((W - 0.09, 0.006, 0.22), (0, yy, z - 0.01), (tilt, 0, 0), m="folder")
                    box((0.07, 0.006, 0.025), (-0.12 + (k % 3) * 0.12, yy, z + 0.11), (tilt, 0, 0), m="folder")
    # spilled folders and loose pages on the floor
    for i, (x, y, a) in enumerate(((0.15, -0.95, 20), (-0.2, -1.05, -35), (0.3, -1.25, 70), (-0.05, -1.3, 5))):
        box((0.24, 0.32, 0.006 + 0.004 * (i % 2)), (x, y, 0.005 + 0.003 * i), (0, 0, a), m="folder" if i % 2 else "paper")


@piece("WallSink", close=((1.3, -2.0, 3.6), (0, 0.4, 3.2), 50))
def wall_sink():
    """a wall-hung porcelain basin on iron brackets: old cross-head taps with rust
    trails into the bowl, the trap into the wall, a cracked mirror above"""
    material("sink", "porcelain", base="#dcd9ce", craze=0.6, stain=0.75, rusty=0.85, chips=0.5)
    material("mirror", "glass", base="#3e4440", frost=0.2, dirt=0.9)
    y0 = 0.22          # the wall is at +y
    # the bowl: one spun shape, outside up to the rolled rim and down inside to the drain
    with place(T((0, 0, 0.82))):
        lathe([(0, -0.2), (0.17, -0.2), (0.24, -0.12), (0.28, -0.02), (0.29, 0.02), (0.285, 0.04), (0.265, 0.04),
               (0.25, 0.0), (0.21, -0.1), (0.14, -0.165), (0, -0.17)], m="sink", n=22, stretch=(1.0, 0.72))
        box((0.6, 0.06, 0.16), (0, 0.19, 0.08), m="sink", bevel=0.02, seg=2)        # splashback
        cyl(0.025, 0.01, (0, 0, -0.165), m="chrome", n=12)
        for s in (-1, 1):
            with place(T((s * 0.13, 0.15, 0.13))):
                cyl(0.016, 0.05, m="chrome", n=10)
                for a in (0, 90):
                    box((0.07, 0.012, 0.012), (0, 0, 0.035), (0, 0, a + 20 * s), m="chrome", bevel=0.003)
                sphere(0.012, (0, 0, 0.04), m="porcelain", n=8, rings=4)
                sweep([(0, 0, 0.0), (0, -0.04, 0.01), (0, -0.08, -0.02)], 0.009, "chrome", 8, bend=0.02)
    # two chrome legs down to the floor at the front
    for s in (-1, 1):
        cyl(0.016, 0.66, (s * 0.2, -0.08, 0.33), m="chrome", n=10)
        cyl(0.024, 0.02, (s * 0.2, -0.08, 0.01), m="chrome", n=10)
    # brackets and the trap
    for s in (-1, 1):
        slab([(0, 0), (0.0, 0.3), (0.05, 0.3), (0.26, 0.04), (0.26, 0.0)], 0.02, (s * 0.2, y0, 0.58), (90, 0, -90),
             m="iron")
    sweep([(0, 0.02, 0.62), (0, 0.02, 0.5), (0, 0.06, 0.44), (0, 0.12, 0.48), (0, 0.24, 0.48)], 0.022, "steel", 8,
          bend=0.04)
    sweep([(0.13, 0.24, 0.78), (0.13, 0.2, 0.78), (0.13, 0.2, 0.95)], 0.012, "steel", 6, bend=0.03)
    sweep([(-0.13, 0.24, 0.73), (-0.13, 0.2, 0.73), (-0.13, 0.2, 0.95)], 0.012, "steel", 6, bend=0.03)
    # the mirror, cracked in a star (the cracks are separate shards slightly tilted)
    with place(T((0, y0 - 0.02, 1.42))):
        box((0.52, 0.03, 0.62), m="iron", bevel=0.008)
        cx, cz = 0.06, 0.08
        corners = [(-0.24, -0.29), (0.0, -0.29), (0.24, -0.29), (0.24, 0.0), (0.24, 0.29), (0.0, 0.29), (-0.24, 0.29),
                   (-0.24, 0.0)]
        for i in range(8):
            a, b = corners[i], corners[(i + 1) % 8]
            tilt = ((i * 37) % 5 - 2) * 0.8
            slab([(cx, cz), a, b], 0.006, (0, -0.02, 0), (90 + tilt, 0, tilt * 0.6), m="mirror")
        box((0.05, 0.12, 0.012), (0, -0.07, -0.33), m="steel", bevel=0.003)


@piece("RestraintChair", close=((1.6, -2.4, 3.6), (0, 0, 2.6), 50))
def restraint_chair():
    """a heavy oak restraint chair bolted to the floor: straps at the wrists,
    ankles, chest and forehead"""
    material("oak", "wood", base="#5e4129", dark="#2c1d12", wear=0.65, water=0.55)
    material("strap", "leather", base="#3e2717", wear=0.7, bloodied=0.3)
    sw, sd, sz = 0.56, 0.5, 0.46
    for x in (-sw / 2 + 0.04, sw / 2 - 0.04):
        for y in (-sd / 2 + 0.04, sd / 2 - 0.04):
            box((0.07, 0.07, sz), (x, y, sz / 2), m="oak", bevel=0.008)
            box((0.14, 0.14, 0.012), (x, y, 0.006), m="iron", bevel=0.003)
            for bx, by in ((-0.05, -0.05), (0.05, 0.05)):
                bolt((x + bx, y + by, 0.016), r=0.008, m="iron")
    for y in (-sd / 2 + 0.04, sd / 2 - 0.04):
        box((sw - 0.1, 0.04, 0.06), (0, y, 0.14), m="oak", bevel=0.006)
    box((sw, sd, 0.05), (0, 0, sz + 0.025), m="oak", bevel=0.01)
    # high back, slatted
    with place(T((0, sd / 2 - 0.03, sz + 0.05), (-8, 0, 0))):
        for x in (-sw / 2 + 0.035, sw / 2 - 0.035):
            box((0.07, 0.06, 0.95), (x, 0, 0.475), m="oak", bevel=0.008)
        for z in (0.32, 0.88):
            box((sw - 0.1, 0.05, 0.12), (0, 0, z), m="oak", bevel=0.008)
        for x in (-0.13, -0.045, 0.045, 0.13):
            box((0.06, 0.03, 0.44), (x, 0.01, 0.6), m="oak", bevel=0.005)
        box((0.24, 0.07, 0.14), (0, -0.04, 1.0), m="oak", bevel=0.02, seg=2)            # head block
        ribbon([(-0.13, -0.06, 0.99), (-0.12, -0.13, 1.0), (0.12, -0.13, 1.0), (0.14, -0.06, 0.98)], 0.045, 0.006,
               "strap", bend=0.03, up=(0, 0, 1))
        ribbon([(-sw / 2 + 0.02, -0.03, 0.55), (-sw / 2 + 0.05, -0.2, 0.52), (-0.05, -0.24, 0.48), (0.12, -0.18, 0.2),
                (0.15, -0.12, 0.0)], 0.07, 0.007, "strap", bend=0.05, up=(0, 0, 1))
        buckle((-0.08, -0.24, 0.49), (90, 0, 0), 0.07, 0.05, "steel")
    # arms with wrist straps
    for s in (-1, 1):
        box((0.06, 0.06, 0.24), (s * (sw / 2 - 0.03), -sd / 2 + 0.05, sz + 0.17), m="oak", bevel=0.006)
        box((0.1, sd + 0.04, 0.04), (s * (sw / 2 - 0.02), 0.0, sz + 0.3), m="oak", bevel=0.008)
        ribbon([(s * (sw / 2 - 0.08), -0.08, sz + 0.25), (s * (sw / 2 - 0.08), -0.08, sz + 0.33),
                (s * (sw / 2 + 0.04), -0.08, sz + 0.33), (s * (sw / 2 + 0.045), -0.1, sz + 0.12)], 0.05, 0.006, "strap",
               bend=0.012, up=(0, 1, 0))
        buckle((s * (sw / 2 + 0.035), -0.08, sz + 0.3), (0, 90, 0), 0.05, 0.04, "steel")
        # ankle cuffs on the front legs
        ribbon([(s * (sw / 2 - 0.04) - 0.04, -sd / 2 + 0.0, 0.14), (s * (sw / 2 - 0.04), -sd / 2 - 0.01, 0.15),
                (s * (sw / 2 - 0.04) + 0.04, -sd / 2 + 0.0, 0.14), (s * (sw / 2 - 0.04) + 0.05 * s, -sd / 2 - 0.1, 0.02)],
               0.05, 0.006, "strap", bend=0.015, up=(0, 0, 1))


@piece("HydrotherapyTub", close=((2.4, -3.2, 3.2), (0, 0.4, 2.0), 50))
def hydrotherapy_tub():
    """a continuous-bath tub: cast iron on feet, a heavy canvas cover laced over it
    with a hole for the head, the taps and a valve wheel at the end"""
    material("tub_iron", "paint", base="#cfcbbd", chip=0.6, rust=0.75, under="#556058", peel=0.35)
    material("tub_inside", "porcelain", base="#cfcbbd", stain=0.85, rusty=0.85, chips=0.6)
    material("tub_canvas", "canvas", base="#a39a7c", stain=0.75, moldy=0.65)
    L, W, H = 1.75, 0.78, 0.62
    lathe([(0, 0.06), (0.25, 0.06), (0.32, 0.2), (0.36, 0.45), (0.38, H - 0.02), (0.39, H), (0.35, H), (0.34, H - 0.04),
           (0.3, 0.25), (0.22, 0.11), (0, 0.11)], (0, 0, 0), m="tub_iron", n=20, stretch=(1.0, L / W * 1.0))
    for x in (-1, 1):
        for y in (-1, 1):
            with place(T((x * 0.24, y * 0.62, 0.0))):
                lathe([(0, 0), (0.05, 0), (0.06, 0.02), (0.035, 0.07), (0.045, 0.12), (0, 0.12)], m="iron", n=8)
    # the canvas cover, laced to the rim, sagging, a hole for the head
    hole_y = -L / 2 + 0.3

    def cover(u, v):
        x = (u - 0.5) * (W - 0.04)
        y = (v - 0.5) * (L - 0.06)
        z = H + 0.02 - 0.09 * math.sin(math.pi * u) * math.sin(math.pi * v)
        return (x, y, z)

    def keep(u, v):
        x = (u - 0.5) * (W - 0.04)
        y = (v - 0.5) * (L - 0.06)
        in_tub = (x / (W / 2 - 0.01)) ** 2 + (y / (L / 2 - 0.01)) ** 2 < 1
        return in_tub and (x / 0.13) ** 2 + ((y - hole_y) / 0.15) ** 2 > 1

    grid(W - 0.04, L - 0.06, 14, 26, cover, m="tub_canvas", keep=keep, thick=0.008)
    for i in range(10):
        y = -L / 2 + 0.15 + (L - 0.3) * i / 9
        for s in (-1, 1):
            torus(0.012, 0.003, (s * (W / 2 - 0.04), y, H + 0.015), m="brass", n=8, k=4)
            sweep([(s * (W / 2 - 0.04), y, H + 0.015), (s * (W / 2 + 0.01), y + 0.03, H - 0.05)], 0.003, "rubber", 4)
    lump(0.11, (0, hole_y, H - 0.05), m="tub_canvas", seed=4, squash=(1.1, 0.8, 0.3))
    # the end with the taps and the valve wheel
    with place(T((0, L / 2 + 0.04, 0))):
        for s in (-1, 1):
            sweep([(s * 0.12, 0.25, 0.1), (s * 0.12, 0.25, H + 0.18), (s * 0.12, 0.0, H + 0.18), (s * 0.12, -0.04, H + 0.1)],
                  0.018, "steel", 8, bend=0.05)
        cyl(0.02, 0.24, (0, 0.25, H + 0.3), (0, 90, 0), m="steel", n=8)
        torus(0.1, 0.01, (0, 0.24, H + 0.3), (90, 0, 0), m="iron", n=16, k=5)
        for a in (0, 60, 120):
            box((0.19, 0.012, 0.012), (0, 0.24, H + 0.3), (0, a, 0), m="iron")
        thermo = gauge_png("tub_thermo", "WATER\nTEMP", 120, "deg F", 20, red_from=100, needle=0.18)
        material("thermo_face", "paint", base="#e0d8c2", chip=0.15, rust=0.2, dirt=0.7, peel=0.1)
        decal("thermo_face", thermo, here((0.0, 0.215, H + 0.06), (90, 0, 0)), (0.11, 0.11))
        cyl(0.06, 0.03, (0, 0.235, H + 0.06), (90, 0, 0), m="brass", n=16)
        cyl(0.054, 0.004, (0, 0.218, H + 0.06), (90, 0, 0), m="thermo_face", n=16)


@piece("ECTMachine", close=((1.3, -1.9, 3.2), (0, -0.1, 2.6), 50))
def ect_machine():
    """an electroshock machine: a wooden case with its lid up, meters, dials and switches,
    the headband electrodes and a rubber bite block, on a small trolley"""
    material("ect_case", "wood", base="#4f3624", dark="#24170e", wear=0.5, water=0.3, varnish=0.7)
    material("ect_panel", "bakelite", base="#1d1815")
    material("ect_cart", "paint", base="#c3bda4", chip=0.6, rust=0.7, under="#738272")
    # the trolley
    for x in (-0.24, 0.24):
        for y in (-0.17, 0.17):
            cyl(0.012, 0.7, (x, y, 0.42), m="ect_cart", n=8)
            caster((x, y, 0), 0.03, "chrome", swivel=x * y * 400, stem=0.0)
    for z in (0.3, 0.77):
        box((0.52, 0.38, 0.015), (0, 0, z), m="ect_cart", bevel=0.004)
    top = 0.778
    # the case and its sloped panel
    box((0.46, 0.3, 0.16), (0, 0.0, top + 0.08), m="ect_case", bevel=0.008)
    with place(T((0, 0.0, top + 0.16), (-12, 0, 0))):
        box((0.42, 0.26, 0.012), (0, 0, 0.006), m="ect_panel", bevel=0.003)
        dial = gauge_png("ect_volts", "VOLTS", 150, "A.C.", 10, red_from=120, needle=0.62, face=(232, 224, 200))
        timer = gauge_png("ect_time", "SECONDS", 1.0, "", 0.1, needle=0.3, face=(232, 224, 200))
        plate = label_png("ect_plate", [("ELECTRO-CONVULSIVE", 0.8), ("THERAPY APPARATUS", 0.8), ("HOLLOWMERE  No. 3", 0.6)],
                          480, 140, bg=(150, 120, 60), fg=(30, 22, 10), font="serif")
        material("ect_faces", "paint", base="#e8e0c8", chip=0.1, rust=0.15, dirt=0.6, peel=0.05)
        material("ect_brass", "brass")
        decal("ect_faces", dial, here((-0.1, 0.03, 0.0165)), (0.1, 0.1))
        decal("ect_faces", timer, here((0.1, 0.03, 0.0165)), (0.1, 0.1))
        decal("ect_brass", plate, here((0, -0.095, 0.0145)), (0.2, 0.06))
        for gx in (-0.1, 0.1):
            cyl(0.055, 0.012, (gx, 0.03, 0.012), m="chrome", n=16)
            cyl(0.049, 0.002, (gx, 0.03, 0.0175), m="ect_faces", n=16)
        box((0.2, 0.06, 0.003), (0, -0.095, 0.0135), m="ect_brass")
        for i, x in enumerate((-0.16, -0.08, 0.0, 0.08)):
            cyl(0.016, 0.02, (x, -0.04, 0.02), m="bakelite", n=10)
            box((0.004, 0.012, 0.004), (x, -0.05, 0.031), m="chrome")
        for x in (0.13, 0.17):
            box((0.008, 0.008, 0.03), (x, -0.04, 0.026), (20, 0, 0), m="chrome")
        cyl(0.018, 0.016, (0.17, 0.09, 0.016), m="rubber", n=10)
        material("ect_red", "paint", base="#8a1a12", chip=0.2, rust=0.1, peel=0.05)
        sphere(0.016, (0.17, 0.09, 0.03), m="ect_red", n=10, rings=5)
    # the lid, standing open behind
    with place(T((0, 0.15, top + 0.16), (170, 0, 0))):
        box((0.46, 0.02, 0.3), (0, 0, -0.15), m="ect_case", bevel=0.006)
        warn = label_png("ect_warn", [("DANGER", 1.0), ("HIGH VOLTAGE", 0.6), ("DO NOT EXCEED 1 SEC.", 0.45)], 360, 200,
                         bg=(214, 196, 150), fg=(120, 20, 14), font="serif")
        material("ect_warn", "paper")
        decal("ect_warn", warn, here((0, -0.012, -0.15), (90, 0, 0)), (0.18, 0.1))
        box((0.18, 0.003, 0.1), (0, -0.011, -0.15), m="ect_warn")
    # electrodes on their headband, the bite block, the leads
    with place(T((0.12, -0.08, top + 0.02))):
        torus(0.09, 0.008, (0, 0, 0), (0, 0, 0), m="rubber", n=16, k=5)
        for s in (-1, 1):
            cyl(0.025, 0.015, (s * 0.09, 0, 0.0), (0, 90, 0), m="chrome", n=10)
    sweep([(-0.15, -0.12, top + 0.1), (-0.25, -0.15, top + 0.05), (-0.05, -0.2, top + 0.015), (0.03, -0.08, top + 0.015)],
          0.005, "rubber", 6, bend=0.05)
    sweep([(-0.12, -0.12, top + 0.1), (-0.2, -0.22, top + 0.01), (0.2, -0.12, top + 0.012)], 0.005, "rubber", 6, bend=0.05)
    box((0.07, 0.025, 0.02), (-0.12, -0.24, top + 0.01), (0, 0, 25), m="rubber", bevel=0.008, seg=2)
