# The operating theatre: the exam chair and the operating table from the
# photos, the two surgical lamps, the anaesthesia cart, the instrument trolley.
from kit import *  # noqa


def trough(at, rot, length=0.22, r=0.07, shell="chrome", pad="vinyl"):
    """a padded half-pipe cradle (knee crutch, arm board)"""
    with place(T(at, rot)):
        lathe([(r, -length / 2), (r, length / 2)], m=shell, n=12, arc=(180, 360))
        lathe([(r - 0.008, length / 2), (r - 0.008, -length / 2)], m=pad, n=12, arc=(180, 360))


@piece("ExamChair", close=((1.7, -2.6, 3.4), (0, 0.2, 2.3), 50))
def exam_chair():
    """the examination chair from the photo: cast pedestal, hydraulic ram, a
    reclined cracked backrest and headrest, leg cradles, a basin under the seat"""
    material("chair_paint", "paint", base="#c9c1a2", chip=0.6, rust=0.7, under="#8fa592", peel=0.5, streaks=0.7)
    material("chair_vinyl", "vinyl", base="#1d2520", crack=0.75, wear=0.55, tear=0.45, stain=0.5, bloodied=0.25)
    material("basin", "porcelain", base="#d4d2c8", stain=0.7, rusty=0.6, chips=0.6, bloodied=0.4)
    # the base and pedestal
    slab(rounded_rect(0.62, 0.5, 0.14, 4), 0.045, (0, 0.02, 0.0225), m="chair_paint", bevel=0.012)
    lathe([(0.21, 0.044), (0.2, 0.07), (0.15, 0.1), (0.125, 0.12), (0.12, 0.16), (0.095, 0.34), (0.09, 0.4), (0.1, 0.4),
           (0.1, 0.43), (0.065, 0.43), (0, 0.43)], (0, 0.02, 0), m="chair_paint", n=20)
    cyl(0.058, 0.13, (0, 0.02, 0.495), m="chrome", n=18)
    torus(0.062, 0.008, (0, 0.02, 0.437), m="rubber", n=18, k=5)
    for x in (-0.26, 0.26):
        for y in (-0.17, 0.21):
            cyl(0.022, 0.02, (x, y, 0.01), m="rubber", n=8)
    # the pump pedal
    ribbon([(0, -0.08, 0.17), (0, -0.2, 0.15), (0, -0.31, 0.11)], 0.03, 0.016, "iron", bend=0.05, up=(1, 0, 0))
    box((0.1, 0.07, 0.02), (0, -0.33, 0.105), (-10, 0, 0), m="rubber", bevel=0.005)
    # under the seat: the mechanism housing, a hand wheel, and the basin on its runners
    box((0.26, 0.24, 0.09), (0, 0.06, 0.6), m="chair_paint", bevel=0.012)
    with place(T((0.14, 0.06, 0.6), (0, 90, 0))):
        torus(0.06, 0.007, m="chrome", n=16, k=5)
        cyl(0.014, 0.03, m="chrome", n=8)
        for a in (0, 120, 240):
            r = math.radians(a)
            sweep([(0, 0, 0), (math.cos(r) * 0.058, math.sin(r) * 0.058, 0)], 0.004, "chrome", 5)
        cyl(0.008, 0.05, (0.058, 0, 0.025), m="bakelite", n=6)
    for x in (-0.14, 0.14):
        cyl(0.006, 0.32, (x, -0.16, 0.625), (90, 0, 0), m="chrome", n=6)
    lathe([(0, 0), (0.08, 0), (0.12, 0.05), (0.135, 0.07), (0.14, 0.075), (0.128, 0.075), (0.11, 0.055), (0.07, 0.01),
           (0, 0.01)], (0, -0.18, 0.55), m="basin", n=18)
    # the seat: a plate and a cushion with the cut-out at the front
    box((0.5, 0.46, 0.02), (0, 0, 0.655), m="chair_paint", bevel=0.005)
    seat = [(-0.24, -0.21), (-0.08, -0.21), (-0.08, -0.14), (-0.05, -0.115), (0, -0.105), (0.05, -0.115), (0.08, -0.14),
            (0.08, -0.21), (0.24, -0.21), (0.24, 0.21), (-0.24, 0.21)]
    slab(seat, 0.075, (0, 0, 0.7025), m="chair_vinyl", bevel=0.022)
    for x in (-0.255, 0.255):
        box((0.012, 0.44, 0.035), (x, 0, 0.65), m="chrome", bevel=0.003)
    # the step at the front
    for x in (-0.15, 0.15):
        sweep([(x, -0.2, 0.645), (x, -0.27, 0.31)], 0.01, "chrome", 8)
    box((0.36, 0.16, 0.02), (0, -0.34, 0.3), m="chair_paint", bevel=0.005)
    box((0.32, 0.12, 0.006), (0, -0.34, 0.313), m="rubber")
    # leg cradles on bent rods
    for s in (-1, 1):
        box((0.04, 0.05, 0.05), (s * 0.265, -0.16, 0.65), m="chrome", bevel=0.006)
        sweep([(s * 0.27, -0.16, 0.65), (s * 0.27, -0.17, 0.95), (s * 0.34, -0.22, 1.1)], 0.012, "chrome", 8, bend=0.08)
        trough((s * 0.36, -0.24, 1.15), (90, 0, s * 15), pad="chair_vinyl")
        ribbon([(s * 0.29, -0.24, 1.17), (s * 0.3, -0.24, 1.24), (s * 0.43, -0.24, 1.24), (s * 0.44, -0.25, 1.1)],
               0.045, 0.006, "leather", bend=0.02, up=(0, 1, 0))
    # armrests
    for s in (-1, 1):
        sweep([(s * 0.26, 0.15, 0.66), (s * 0.29, 0.15, 0.86), (s * 0.29, -0.15, 0.86)], 0.012, "chrome", 8, bend=0.04)
        box((0.075, 0.34, 0.045), (s * 0.29, -0.02, 0.885), m="chair_vinyl", bevel=0.015, seg=2)
        ribbon([(s * 0.25, -0.05, 0.86), (s * 0.25, -0.05, 0.91), (s * 0.33, -0.05, 0.912), (s * 0.335, -0.06, 0.8)],
               0.045, 0.006, "leather", bend=0.015, up=(0, 1, 0))
    # the backrest, reclined, with its headrest and ratchet quadrants
    with place(T((0, 0.21, 0.7), (-38, 0, 0))):
        box((0.48, 0.022, 0.72), (0, 0.045, 0.38), m="chair_paint", bevel=0.006)
        box((0.46, 0.07, 0.68), (0, 0.0, 0.38), m="chair_vinyl", bevel=0.022, seg=2)
        for x in (-0.245, 0.245):
            box((0.012, 0.03, 0.72), (x, 0.05, 0.38), m="chrome", bevel=0.003)
        for x in (-0.1, 0.1):
            sweep([(x, 0.045, 0.7), (x, 0.03, 0.86)], 0.01, "chrome", 8)
        box((0.3, 0.02, 0.15), (0, 0.04, 0.88), m="chair_paint", bevel=0.005)
        box((0.3, 0.07, 0.15), (0, 0.0, 0.88), m="chair_vinyl", bevel=0.025, seg=2)
        teeth = [(0.0, 0.0), (0.0, 0.12)]
        for i in range(10):
            a = math.radians(90 - 7 * i)
            rr = 0.12 if i % 2 == 0 else 0.135
            teeth.append((math.cos(a) * rr, math.sin(a) * rr))
        for x in (-0.26, 0.26):
            slab([(-z, y) for y, z in teeth], 0.008, (x, 0.04, 0.0), (0, 90, 0), m="iron")
        # the head strap
        ribbon([(-0.17, -0.03, 0.83), (-0.16, -0.045, 0.88), (0.16, -0.045, 0.88), (0.17, -0.03, 0.93)], 0.05, 0.006,
               "leather", bend=0.02, up=(0, 0, 1))


@piece("OperatingTable", close=((2.4, -3.4, 3.6), (0, -0.4, 2.5), 50))
def operating_table():
    """the operating table from the photo: a heavy plinth, a rubber-booted column,
    four padded sections, side rails, an arm board, straps hanging off it"""
    material("ot_paint", "paint", base="#bdb8a6", chip=0.55, rust=0.65, under="#6f7f74", peel=0.45)
    material("ot_base", "paint", base="#a9a493", chip=0.6, rust=0.75, dirt=0.85)
    material("ot_vinyl", "vinyl", base="#161716", crack=0.7, wear=0.45, tear=0.35, stain=0.45, bloodied=0.45)
    slab(rounded_rect(0.5, 1.0, 0.06, 2), 0.11, (0, 0, 0.055), m="ot_base", bevel=0.02)
    slab(rounded_rect(0.53, 1.03, 0.07, 2), 0.02, (0, 0, 0.01), m="chrome", bevel=0.004)
    for x in (-0.2, 0.2):
        for y in (-0.42, 0.42):
            cyl(0.03, 0.03, (x, y, 0.125), m="iron", n=8)
    # the column in its ribbed rubber boot
    for i in range(11):
        z = 0.13 + i * 0.045
        big = i % 2 == 0
        box((0.30 if big else 0.25, 0.26 if big else 0.21, 0.03), (0, 0.05, z), m="rubber", bevel=0.01)
    box((0.4, 0.66, 0.14), (0, 0.05, 0.68), m="ot_paint", bevel=0.015)
    box((0.46, 1.84, 0.05), (0, 0, 0.775), m="ot_paint", bevel=0.01)
    # foot pedal
    ribbon([(0.15, 0.4, 0.12), (0.25, 0.55, 0.06)], 0.035, 0.014, "iron", up=(0, 0, 1))
    box((0.09, 0.07, 0.02), (0.27, 0.58, 0.055), m="rubber", bevel=0.005)
    # cranks at the head end
    for x in (-0.1, 0.1):
        cyl(0.009, 0.3, (x, 0.52, 0.7), (90, 0, 0), m="chrome", n=8)
        with place(T((x, 0.68, 0.7))):
            box((0.012, 0.012, 0.11), (0, 0, -0.05), m="chrome")
            cyl(0.014, 0.05, (0, 0.025, -0.1), (90, 0, 0), m="bakelite", n=8)
    # the four sections: head (tipped down), back, seat, legs (sagging)
    for y0, y1, tilt in ((0.74, 0.95, -7), (0.1, 0.73, 0), (-0.31, 0.09, 0), (-0.95, -0.32, 4)):
        L = y1 - y0
        hinge = y0 if tilt < 0 else y1
        with place(T((0, hinge, 0.8), (tilt, 0, 0))):
            c = (y0 + y1) / 2 - hinge
            box((0.5, L, 0.02), (0, c, 0.01), m="ot_paint", bevel=0.004)
            box((0.5, L - 0.01, 0.06), (0, c, 0.05), m="ot_vinyl", bevel=0.02, seg=2)
            if L > 0.5:
                for x in (-0.265, 0.265):
                    box((0.008, L * 0.8, 0.03), (x, c, 0.03), m="chrome", bevel=0.002)
                    for e in (-1, 1):
                        cyl(0.007, 0.02, (x - 0.01 * (1 if x > 0 else -1), c + e * L * 0.38, 0.03), (0, 90, 0), m="chrome", n=6)
    # the arm board swung out
    with place(T((0.27, 0.32, 0.84), (0, 0, -22))):
        box((0.6, 0.14, 0.02), (0.3, 0, 0), m="ot_paint", bevel=0.004)
        box((0.58, 0.13, 0.04), (0.3, 0, 0.03), m="ot_vinyl", bevel=0.012, seg=2)
        sweep([(0.05, 0, -0.01), (0.25, 0, -0.12), (0.5, 0, -0.01)], 0.008, "chrome", 6, bend=0.06)
        ribbon([(0.4, -0.07, 0.0), (0.4, -0.075, 0.055), (0.4, 0.075, 0.055), (0.4, 0.08, -0.08)], 0.045, 0.006,
               "leather", bend=0.01, up=(1, 0, 0))
    # straps hanging off the rails
    for x, y in ((-0.27, 0.45), (0.27, -0.55), (-0.27, -0.6)):
        s = 1 if x > 0 else -1
        ribbon([(x, y, 0.83), (x + s * 0.02, y, 0.8), (x + s * 0.03, y + 0.01, 0.6), (x + s * 0.025, y - 0.02, 0.45)],
               0.05, 0.006, "leather", bend=0.03, up=(0, 1, 0))
        buckle((x + s * 0.034, y + 0.008, 0.55), (0, 90, 0), 0.05, 0.04, "steel")
    ribbon([(-0.29, -0.62, 0.7), (-0.275, -0.62, 0.88), (0.275, -0.62, 0.885), (0.29, -0.62, 0.7)], 0.07, 0.007,
           "leather", bend=0.02, up=(0, 1, 0))


@piece("SurgicalLamp", close=((1.5, -3.0, 2.5), (0, -1.4, 2.0), 50))
def surgical_lamp():
    """the big round theatre lamp from the photo, hanging from the ceiling on its arm:
    a ring of dark lenses in chrome bezels, a centre handle, a dome back"""
    material("lamp_paint", "paint", base="#c8c6b9", chip=0.45, rust=0.5, dirt=0.55, under="#7e8a84")
    material("lamp_face", "paint", base="#b9b6a6", chip=0.3, rust=0.4, dirt=0.75)
    material("lamp_lens", "glass", base="#3a3b35", frost=0.55)
    H = 1.55
    lathe([(0, H - 0.07), (0.04, H - 0.07), (0.12, H - 0.05), (0.16, H - 0.02), (0.16, H), (0, H)], m="lamp_paint", n=18)
    cyl(0.028, H - 0.07 - 1.05, (0, 0, (H - 0.07 + 1.05) / 2), m="lamp_paint", n=10)
    sphere(0.045, (0, 0, 1.05), m="chrome", n=10, rings=6)
    sweep([(0, 0, 1.05), (0, -0.3, 1.05), (0, -0.48, 0.95), (0, -0.48, 0.9)], 0.024, "lamp_paint", 10, bend=0.08)
    sweep([(-0.42, -0.48, 0.62), (-0.42, -0.48, 0.9), (0.42, -0.48, 0.9), (0.42, -0.48, 0.62)], 0.018, "lamp_paint", 8,
          bend=0.06)
    with place(T((0, -0.48, 0.62), (-40, 0, 0))):
        lathe([(0.385, -0.03), (0.385, 0.0), (0.36, 0.06), (0.30, 0.12), (0.18, 0.16), (0, 0.175)], m="lamp_paint", n=28)
        lathe([(0, -0.03), (0.385, -0.03)], m="lamp_face", n=28)
        torus(0.385, 0.014, (0, 0, -0.03), m="chrome", n=28, k=6)
        lathe([(0.07, 0.175), (0.07, 0.21), (0.05, 0.23), (0, 0.235)], m="lamp_paint", n=12)
        for i in range(8):
            a = 2 * math.pi * i / 8
            with place(T((math.cos(a) * 0.235, math.sin(a) * 0.235, 0))):
                torus(0.075, 0.009, (0, 0, -0.035), m="chrome", n=14, k=5)
                lathe([(0, -0.05), (0.04, -0.045), (0.07, -0.032)], m="lamp_lens", n=14)
        for i in range(4):
            a = 2 * math.pi * (i + 0.5) / 4
            with place(T((math.cos(a) * 0.115, math.sin(a) * 0.115, 0))):
                torus(0.052, 0.007, (0, 0, -0.034), m="chrome", n=12, k=5)
                lathe([(0, -0.045), (0.03, -0.04), (0.048, -0.032)], m="lamp_lens", n=12)
        cyl(0.022, 0.14, (0, 0, -0.1), m="chrome", n=10)
        cyl(0.028, 0.09, (0, 0, -0.13), m="bakelite", n=10)
        sphere(0.03, (0, 0, -0.18), m="chrome", n=10, rings=5)
        for x in (-0.405, 0.405):
            cyl(0.03, 0.03, (x, 0, 0), (0, 90, 0), m="bakelite", n=10)
        cable_from = here((0.0, 0.12, 0.17)).translation
    sweep([cable_from, cable_from + V((0, 0.1, 0.12)), (0, -0.3, 1.0)], 0.007, "rubber", 6, bend=0.1)


@piece("InstrumentTrolley", close=((1.2, -1.6, 3.2), (0, 0, 2.5), 50))
def instrument_trolley():
    """a two-tier instrument trolley left mid-operation: kidney dish, scalpel,
    scissors, clamps, a bone saw, a syringe, bloody gauze; a basin below"""
    material("tray_steel", "chrome", rust=0.55, dull=0.9, base="#8f908c")
    material("gauze", "fabric", base="#d8d2c0", stain=0.5, bloodied=0.85, moldy=0.1)
    material("dish", "porcelain", base="#d6d4ca", stain=0.6, chips=0.7, bloodied=0.7)
    material("syringe", "glass", base="#a8a690", frost=0.3)
    W, D = 0.62, 0.42
    for x in (-W / 2 + 0.02, W / 2 - 0.02):
        for y in (-D / 2 + 0.02, D / 2 - 0.02):
            cyl(0.012, 0.75, (x, y, 0.475), m="chrome", n=8)
            caster((x, y, 0), 0.035, swivel=40 * x * y * 30, stem=0.0)
    for z in (0.85, 0.32):
        box((W, D, 0.008), (0, 0, z), m="tray_steel")
        for x in (-W / 2, W / 2):
            box((0.006, D, 0.035), (x, 0, z + 0.017), m="tray_steel")
        for y in (-D / 2, D / 2):
            box((W, 0.006, 0.035), (0, y, z + 0.017), m="tray_steel")
    sweep([(-W / 2, -0.12, 0.84), (-W / 2 - 0.08, -0.12, 0.9), (-W / 2 - 0.08, 0.12, 0.9), (-W / 2, 0.12, 0.84)],
          0.009, "chrome", 8, bend=0.03)
    top = 0.855
    # kidney dish with a stained swab in it
    lathe([(0, 0), (0.05, 0), (0.07, 0.02), (0.075, 0.03), (0.068, 0.03), (0.06, 0.012), (0, 0.006)],
          (0.15, 0.07, top), m="dish", n=16, stretch=(1.6, 1.0))
    lump(0.03, (0.14, 0.07, top + 0.022), m="gauze", seed=2, squash=(1.2, 1, 0.5))
    # scalpel
    with place(T((-0.05, -0.1, top + 0.005), (0, 0, 20))):
        box((0.11, 0.009, 0.005), (0, 0, 0), m="chrome", bevel=0.001)
        slab([(0.055, -0.004), (0.095, -0.002), (0.085, 0.006), (0.055, 0.004)], 0.002, (0, 0, 0.001), m="chrome")
    # scissors and a clamp
    for (x, y, a, open_) in ((0.02, -0.12, -30, 18), (-0.2, 0.08, 75, 6)):
        with place(T((x, y, top + 0.004), (0, 0, a))):
            for s in (-1, 1):
                with place(T((0, 0, 0.002 * s), (0, 0, s * open_ / 2))):
                    slab([(0.0, -0.004), (0.11, -0.001), (0.11, 0.002), (0.0, 0.004)], 0.003, m="chrome")
                    box((0.06, 0.005, 0.003), (-0.03, s * 0.012, 0), m="chrome")
                    torus(0.014, 0.003, (-0.07, s * 0.02, 0), m="chrome", n=10, k=4)
    # forceps
    with place(T((-0.12, -0.05, top + 0.004), (0, 0, -60))):
        for s in (-1, 1):
            box((0.13, 0.006, 0.003), (0, s * 0.008, 0), (0, 0, -s * 4), m="chrome")
    # the bone saw
    with place(T((-0.1, 0.12, top + 0.012), (0, 0, 8))):
        sweep([(-0.14, 0, 0), (-0.14, 0.07, 0), (0.12, 0.07, 0), (0.12, 0.0, 0)], 0.004, "steel", 6, bend=0.015)
        tooth = [(-0.135, 0.0)]
        for i in range(26):
            tooth.append((-0.135 + 0.01 * i + 0.005, -0.006 if i % 2 else 0.0))
        tooth += [(0.12, 0.0), (0.12, 0.02), (-0.135, 0.02)]
        slab(tooth, 0.0015, m="steel")
        cyl(0.012, 0.09, (-0.19, 0.0, 0), (0, 90, 0), m="wood", n=8)
    # syringe
    with place(T((0.16, -0.12, top + 0.012), (0, 90, -10))):
        cyl(0.009, 0.08, m="syringe", n=8)
        cyl(0.003, 0.05, (0, 0, -0.06), m="chrome", n=5)
        cyl(0.0008, 0.035, (0, 0, -0.1), m="chrome", n=3)
        box((0.004, 0.035, 0.006), (0, 0, 0.042), m="chrome")
    # bloody gauze, a specimen jar
    for i, (x, y) in enumerate(((0.24, -0.02), (0.22, 0.14), (-0.25, -0.13))):
        lump(0.035, (x, y, top + 0.02), m="gauze", seed=i + 7, squash=(1.3, 1.0, 0.45), rough=0.3)
    lathe([(0, 0), (0.045, 0), (0.045, 0.12), (0.03, 0.13), (0.03, 0.14), (0, 0.14)], (-0.24, 0.1, top), m="glass", n=12)
    cyl(0.034, 0.02, (-0.24, 0.1, top + 0.15), m="bakelite", n=12)
    # below: an enamel basin, folded towels, brown bottles, a coil of rubber tube
    low = 0.325
    lathe([(0, 0), (0.08, 0), (0.12, 0.06), (0.13, 0.065), (0.12, 0.065), (0.105, 0.055), (0.07, 0.008), (0, 0.008)],
          (-0.14, 0, low), m="dish", n=18)
    for k in range(3):
        box((0.18, 0.16, 0.025), (0.12, 0.05, low + 0.013 + k * 0.026), (0, 0, k * 4), m="gauze", bevel=0.01, seg=2)
    for x, y in ((0.24, -0.13), (0.17, -0.15)):
        lathe([(0, 0), (0.03, 0), (0.03, 0.1), (0.012, 0.125), (0.012, 0.14), (0, 0.14)], (x, y, low), m="amber", n=10)
    torus(0.06, 0.006, (-0.16, -0.1, low + 0.01), m="rubber", n=14, k=5)
    torus(0.05, 0.006, (-0.155, -0.1, low + 0.02), m="rubber", n=14, k=5)


@piece("AnesthesiaCart", close=((1.4, -2.2, 3.4), (0, -0.1, 2.9), 50))
def anesthesia_cart():
    """an old anaesthesia machine on its trolley: flowmeter tubes, gauges,
    an ether jar, gas cylinders, the breathing bag and corrugated hose with its mask"""
    material("cart_paint", "paint", base="#c6c0a6", chip=0.6, rust=0.65, under="#7a9282", peel=0.45)
    material("o2", "paint", base="#3f6e4c", chip=0.5, rust=0.6, gloss=0.6)
    material("n2o", "paint", base="#3c5a7a", chip=0.5, rust=0.6, gloss=0.6)
    material("bag", "rubber", base="#151413")
    W, D = 0.6, 0.42
    for x in (-W / 2, W / 2):
        for y in (-D / 2, D / 2):
            box((0.025, 0.025, 0.86), (x, y, 0.53), m="cart_paint", bevel=0.003)
            caster((x, y, 0), 0.045, swivel=20 * x * 10, stem=0.0)
    for z in (0.18, 0.5, 0.95):
        box((W + 0.02, D + 0.02, 0.012), (0, 0, z), m="cart_paint", bevel=0.003)
        for y in (-D / 2, D / 2):
            box((W, 0.008, 0.03), (0, y, z + 0.02), m="cart_paint")
    # two cylinders lying on the lower shelf, one on the middle
    for (z, y, mm) in ((0.25, -0.08, "o2"), (0.25, 0.1, "n2o"), (0.57, 0.08, "o2")):
        with place(T((0.0, y, z), (0, 90, 0))):
            lathe([(0, -0.25), (0.055, -0.25), (0.058, -0.24), (0.058, 0.17), (0.05, 0.21), (0.022, 0.235), (0, 0.24)],
                  m=mm, n=14)
            cyl(0.016, 0.05, (0, 0, 0.26), m="brass", n=8)
            cyl(0.008, 0.04, (0.02, 0, 0.27), (0, 90, 0), m="brass", n=6)
    # the machine on top
    top = 0.956
    box((0.42, 0.24, 0.12), (0, 0.04, top + 0.06), m="cart_paint", bevel=0.01)
    box((0.3, 0.06, 0.26), (0, 0.13, top + 0.25), m="cart_paint", bevel=0.008)
    material("flow_glass", "glass", base="#8a8e80", frost=0.25)
    for i, x in enumerate((-0.09, 0, 0.09)):
        cyl(0.013, 0.18, (x, 0.095, top + 0.27), m="flow_glass", n=8)
        cyl(0.02, 0.02, (x, 0.095, top + 0.17), m="chrome", n=8)
        cyl(0.02, 0.02, (x, 0.095, top + 0.37), m="chrome", n=8)
        sphere(0.006, (x, 0.095, top + 0.2 + i * 0.05), m="chrome", n=6, rings=4)
        cyl(0.016, 0.03, (x, -0.085, top + 0.07), (90, 0, 0), m="bakelite", n=10)
    # two gauges on the front, their faces printed
    g1 = gauge_png("gauge_o2", "OXYGEN", 2000, "lb/sq in", 250, red_from=1800, needle=0.12)
    g2 = gauge_png("gauge_n2o", "NITROUS\nOXIDE", 1000, "lb/sq in", 100, needle=0.04)
    material("gauge_face", "paint", base="#e2dac4", chip=0.15, rust=0.2, dirt=0.7, peel=0.1)
    for gx, img in ((-0.12, g1), (0.12, g2)):
        decal("gauge_face", img, here((gx, -0.093, top + 0.075), (90, 0, 0)), (0.075, 0.075))
    for gx in (-0.12, 0.12):
        cyl(0.04, 0.02, (gx, -0.085, top + 0.075), (90, 0, 0), m="chrome", n=16)
        cyl(0.036, 0.004, (gx, -0.094, top + 0.075), (90, 0, 0), m="gauge_face", n=16)
    # the ether jar on the side
    lathe([(0, 0), (0.055, 0), (0.055, 0.14), (0.05, 0.15), (0, 0.15)], (0.25, -0.05, top), m="glass", n=14)
    cyl(0.06, 0.03, (0.25, -0.05, top + 0.165), m="chrome", n=14)
    ether = label_png("ether", [("ETHER", 1.0), ("FOR ANAESTHESIA", 0.5)], 300, 160, bg=(212, 196, 150), font="serif")
    material("ether_label", "paper")
    decal("ether_label", ether, here((0.25, -0.106, top + 0.07), (90, 0, 0)), (0.08, 0.045))
    box((0.08, 0.004, 0.045), (0.25, -0.104, top + 0.07), m="ether_label")
    # breathing bag hanging off the side, the corrugated hose looping down to the mask
    with place(T((-0.33, 0.0, 0.82))):
        lathe([(0, -0.17), (0.04, -0.16), (0.07, -0.1), (0.075, -0.03), (0.05, 0.03), (0.02, 0.06), (0.015, 0.09),
               (0, 0.09)], m="bag", n=12, stretch=(0.8, 1.0))
    pts = [(-0.15, 0.0, top + 0.07), (-0.3, -0.05, top + 0.02), (-0.36, -0.15, 0.8), (-0.3, -0.25, 0.65),
           (-0.1, -0.24, 0.6), (0.05, -0.15, 0.56)]
    smooth_pts = fillet(pts, 0.08)
    dense = []
    for a, b in zip(smooth_pts, smooth_pts[1:]):
        k = max(1, int((b - a).length / 0.012))
        for i in range(k):
            dense.append(a.lerp(b, i / k))
    dense.append(smooth_pts[-1])
    radii = [0.018 if i % 2 else 0.014 for i in range(len(dense))]
    sweep(dense, 0.016, "bag", 8, radii=radii)
    lathe([(0, 0), (0.02, 0), (0.05, 0.03), (0.055, 0.05), (0.045, 0.06), (0, 0.04)], (0.08, -0.12, 0.505),
          (0, -40, 0), m="bag", n=12)
