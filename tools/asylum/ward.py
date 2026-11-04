# The ward: iron bed with restraints, wheelchair, gurney, drip stand,
# privacy screen, bedside locker.
from kit import *  # noqa


@piece("BedsideCabinet", close=((1.6, -2.3, 2.2), (0, -0.3, 1.5), 50))
def bedside_cabinet():
    """a steel bedside locker: drawer, open niche, a door left ajar, on castors"""
    material("locker", "paint", base="#cfc6aa", chip=0.6, rust=0.6, under="#7f9a86", peel=0.55)
    material("locker_in", "paint", base="#b9b096", chip=0.3, rust=0.4, dirt=0.9)
    W, D, z0, z1 = 0.46, 0.40, 0.12, 0.80
    H = z1 - z0
    # the shell
    for s in (-1, 1):
        box((0.014, D, H), (s * (W / 2 - 0.007), 0, z0 + H / 2), m="locker", bevel=0.003)
    box((W, 0.012, H), (0, D / 2 - 0.006, z0 + H / 2), m="locker", bevel=0.002)
    box((W, D, 0.014), (0, 0, z0 + 0.007), m="locker_in")
    box((W + 0.03, D + 0.03, 0.022), (0, -0.005, z1 + 0.011), m="locker", bevel=0.006)
    box((W - 0.03, 0.014, 0.05), (0, -D / 2 + 0.03, z0 + 0.025), m="locker", bevel=0.002)      # kick plate
    # shelves: under the niche, over it, inside the cupboard
    for z in (0.505, 0.645, 0.31):
        box((W - 0.028, D - 0.02, 0.012), (0, 0.005, z), m="locker_in", bevel=0.002)
    # the drawer, pulled out a little
    with place(T((0, -0.035, 0))):
        box((W - 0.03, 0.02, 0.125), (0, -D / 2 + 0.01, 0.722), m="locker", bevel=0.004)
        for s in (-1, 1):
            box((0.01, D - 0.06, 0.09), (s * (W / 2 - 0.03), -0.01, 0.715), m="locker_in")
        sweep([(-0.07, -D / 2 - 0.001, 0.73), (-0.07, -D / 2 - 0.03, 0.73), (0.07, -D / 2 - 0.03, 0.73),
               (0.07, -D / 2 - 0.001, 0.73)], 0.006, "chrome", 6, bend=0.012)
        box((0.07, 0.004, 0.035), (0, -D / 2 - 0.001, 0.69), m="chrome", bevel=0.001)     # card holder
        box((0.06, 0.002, 0.026), (0, -D / 2 - 0.003, 0.69), m="paper")
    # the door, hanging open on its left hinge
    with place(T((-W / 2 + 0.012, -D / 2, 0), (0, 0, -28))):
        box((W - 0.03, 0.018, 0.37), ((W - 0.03) / 2, -0.009, 0.315), m="locker", bevel=0.004)
        box((W - 0.07, 0.006, 0.31), ((W - 0.03) / 2, 0.003, 0.315), m="locker_in")
        cyl(0.012, 0.022, (W - 0.075, -0.03, 0.40), (90, 0, 0), m="chrome", n=10)
        sphere(0.016, (W - 0.075, -0.045, 0.40), m="chrome", n=10, rings=5)
        for z in (0.17, 0.46):
            cyl(0.007, 0.05, (0, -0.012, z), m="chrome", n=6)
    # the niche: an enamel mug, a pill bottle on its side
    lathe([(0, 0.0), (0.04, 0.0), (0.042, 0.004), (0.04, 0.09), (0.036, 0.09), (0.034, 0.008), (0, 0.008)],
          (-0.09, -0.02, 0.511), m="porcelain", n=14)
    sweep([(-0.05, -0.02, 0.585), (-0.03, -0.02, 0.585), (-0.03, -0.02, 0.535), (-0.05, -0.02, 0.535)], 0.005,
          "porcelain", 6, bend=0.015)
    lathe([(0, 0), (0.022, 0), (0.022, 0.06), (0.012, 0.07), (0.012, 0.08), (0, 0.08)],
          (0.08, 0.0, 0.533), (0, 90, 30), m="amber", n=10)
    # inside the cupboard: an old bottle
    lathe([(0, 0), (0.035, 0), (0.035, 0.12), (0.014, 0.15), (0.014, 0.18), (0, 0.18)], (0.09, 0.05, 0.316),
          m="green_glass", n=12)
    # the towel rail down the side
    sweep([(W / 2, -0.12, 0.70), (W / 2 + 0.05, -0.12, 0.70), (W / 2 + 0.05, 0.12, 0.70), (W / 2, 0.12, 0.70)],
          0.008, "chrome", 8, bend=0.02)
    # castors
    for x in (-1, 1):
        for y in (-1, 1):
            caster((x * (W / 2 - 0.05), y * (D / 2 - 0.05), 0), 0.03, swivel=x * 15 + y * 40, stem=0.04)


def arch(x0, x1, y, z_side, z_top, n=8):
    """points along a gentle arch from (x0, z_side) up to z_top in the middle and down to (x1, z_side)"""
    return [(x0 + (x1 - x0) * i / n, y, z_side + (z_top - z_side) * math.sin(math.pi * i / n)) for i in range(n + 1)]


@piece("HospitalBed", close=((2.4, -3.2, 3.6), (0, 0.6, 1.8), 50))
def hospital_bed():
    """an iron ward bed: arched head and foot ends, a sagging stained mattress,
    leather restraints at the wrists, ankles and chest, a chart on the foot"""
    material("bed_iron", "paint", base="#dcd7c6", chip=0.65, rust=0.75, under="#5d6b62", peel=0.5, streaks=0.7)
    material("mattress", "fabric", base="#c2b99c", stripe="#56687a", axis="X", stripe_scale=7.0, stain=0.85,
             bloodied=0.35, moldy=0.55, dirt=0.7)
    material("pillow", "fabric", base="#c9c2aa", stain=0.75, moldy=0.4, bloodied=0.15)
    material("strap", "leather", base="#4a2f1d", wear=0.7, bloodied=0.25)
    W, L = 0.92, 1.98
    hx = W / 2
    # head end (+y) and foot end (-y): posts and arched top in one bent tube, bars between
    for y, top, side, bars in ((L / 2, 1.18, 1.0, 9), (-L / 2, 0.98, 0.84, 7)):
        sweep([(-hx, y, 0.12)] + arch(-hx, hx, y, side, top) + [(hx, y, 0.12)], 0.02, "bed_iron", 10, bend=0.06)
        for z in (0.40, 0.68):
            cyl(0.012, W, (0, y, z), (0, 90, 0), m="bed_iron", n=8)
        for i in range(1, bars + 1):
            x = -hx + W * i / (bars + 1)
            ztop = side + (top - side) * math.sin(math.pi * (x + hx) / W)
            cyl(0.008, ztop - 0.40, (x, y, (ztop + 0.40) / 2), m="bed_iron", n=6)
        for x in (-hx, hx):
            sphere(0.028, (x, y, 0.12), m="bed_iron", n=8, rings=5)
            caster((x, y, 0), 0.05, swivel=30 if x > 0 else -20, stem=0.0)
    # side rails (angle iron) and the spring base
    for x in (-hx + 0.01, hx - 0.01):
        box((0.035, L, 0.035), (x, 0, 0.45), m="bed_iron", bevel=0.004)
    for i in range(11):
        y = -L / 2 + 0.12 + (L - 0.24) * i / 10
        box((W - 0.06, 0.025, 0.004), (0, y, 0.462), m="steel")
    for i in range(6):
        x = -hx + 0.1 + (W - 0.2) * i / 5
        box((0.01, L - 0.1, 0.003), (x, 0, 0.466), m="steel")
    # the mattress, sagging, and a pillow pushed to one side
    box((W - 0.05, L - 0.08, 0.15), (0, 0, 0.545), m="mattress", bevel=0.045, seg=3)
    lump(0.24, (-0.1, L / 2 - 0.26, 0.66), m="pillow", seed=3, squash=(1.35, 0.7, 0.28), rough=0.12, n=14, rings=8)
    # restraints: wrist and ankle cuffs lying open at the edges, the chest strap across
    for x in (-1, 1):
        for y, w in ((0.15, 0.06), (-0.72, 0.06)):
            ribbon([(x * (hx - 0.01), y, 0.43), (x * (hx + 0.02), y, 0.5), (x * (hx - 0.02), y, 0.63),
                    (x * (hx - 0.22), y + 0.02, 0.625), (x * (hx - 0.3), y + 0.06, 0.62)], w, 0.007, "strap",
                   bend=0.03, up=(0, 1, 0))
            buckle((x * (hx - 0.12), y + 0.01, 0.632), (0, 0, 90), 0.06, 0.045, "steel")
            ribbon([(x * (hx + 0.012), y, 0.43), (x * (hx + 0.03), y, 0.3), (x * (hx + 0.02), y + 0.01, 0.16)],
                   w * 0.8, 0.006, "strap", bend=0.04, up=(0, 1, 0))
    ribbon([(-hx - 0.02, 0.45, 0.2), (-hx - 0.01, 0.45, 0.6), (-hx + 0.05, 0.45, 0.625), (hx - 0.05, 0.45, 0.625),
            (hx + 0.01, 0.45, 0.6), (hx + 0.03, 0.47, 0.35)], 0.08, 0.008, "strap", bend=0.03, up=(0, 1, 0))
    buckle((hx - 0.15, 0.45, 0.632), (0, 0, 90), 0.085, 0.06, "steel")
    # the chart on the foot end
    chart = label_png("bed_chart", [("HOLLOWMERE", 0.9), ("WARD C  -  BED 14", 0.8), ("SEDATE 4-HOURLY", 0.8),
                                    ("DO NOT REMOVE", 0.7), ("RESTRAINTS", 0.7)], 360, 480, font="type")
    with place(T((0.18, -L / 2 - 0.03, 0.66), (8, 0, 0))):
        decal("bed_chart_paper", chart, here((0, -0.006, 0), (90, 0, 0)), (0.2, 0.27))
        material("bed_chart_paper", "paper")
        box((0.23, 0.008, 0.31), (0, 0, 0), m="wood", bevel=0.003)
        box((0.2, 0.004, 0.27), (0, -0.005, -0.01), m="bed_chart_paper")
        box((0.08, 0.012, 0.03), (0, -0.006, 0.14), m="chrome", bevel=0.004)
    sweep([(0.18, -L / 2 - 0.02, 0.83), (0.18, -L / 2 - 0.035, 0.81)], 0.004, "steel", 5)


@piece("Wheelchair", close=((1.7, -2.4, 2.4), (0, 0, 1.6), 50))
def wheelchair():
    """a 1950s steel wheelchair: big spoked wheels, cracked sling seat, restraint straps on the arms"""
    material("wc_frame", "chrome", rust=0.6, dull=0.85)
    material("wc_sling", "vinyl", base="#2b2620", crack=0.8, wear=0.7, tear=0.4, stain=0.5)
    material("strap", "leather", base="#4a2f1d", wear=0.7, bloodied=0.2)
    sx = 0.25
    for s in (-1, 1):
        x = s * sx
        # side frame: from the front castor up to the seat, back along it, up the back post to the handle
        sweep([(x, -0.30, 0.20), (x, -0.27, 0.50), (x, 0.15, 0.50), (x, 0.17, 0.95), (x, 0.29, 0.98)], 0.012,
              "wc_frame", 8, bend=0.04)
        sweep([(x, -0.30, 0.20), (x, 0.12, 0.24), (x, 0.15, 0.50)], 0.011, "wc_frame", 8, bend=0.03)
        cyl(0.017, 0.1, (x, 0.34, 0.98), (90, 0, 0), m="rubber", n=8)          # hand grip
        # armrest loop with its pad and a restraint strap
        sweep([(s * 0.27, -0.12, 0.5), (s * 0.27, -0.12, 0.70), (s * 0.27, 0.13, 0.70), (s * 0.27, 0.13, 0.5)],
              0.01, "wc_frame", 8, bend=0.03)
        box((0.055, 0.28, 0.03), (s * 0.27, 0.0, 0.715), m="wc_sling", bevel=0.01, seg=2)
        ribbon([(s * 0.29, 0.02, 0.62), (s * 0.30, 0.02, 0.733), (s * 0.24, 0.02, 0.735), (s * 0.235, 0.02, 0.69),
                (s * 0.23, 0.04, 0.6)], 0.05, 0.006, "strap", bend=0.012, up=(0, 1, 0))
        buckle((s * 0.30, 0.02, 0.68), (0, 90, 0), 0.05, 0.04, "steel")
        # big rear wheel: tyre, rim, push rim, spokes
        with place(T((s * (sx + 0.05), 0.12, 0.31), (0, 90, 0))):
            torus(0.29, 0.018, m="rubber", n=24, k=6)
            torus(0.272, 0.009, m="wc_frame", n=24, k=5)
            with place(T((0, 0, s * -0.035))):
                torus(0.25, 0.007, m="wc_frame", n=24, k=5)
                for i in range(5):
                    a = 2 * math.pi * i / 5
                    cyl(0.004, 0.035, (math.cos(a) * 0.25, math.sin(a) * 0.25, s * 0.0175), m="wc_frame", n=5)
            cyl(0.03, 0.07, m="wc_frame", n=10)
            for i in range(16):
                a = 2 * math.pi * i / 16
                sweep([(math.cos(a) * 0.02, math.sin(a) * 0.02, 0.02 * (1 if i % 2 else -1)),
                       (math.cos(a + 0.3) * 0.268, math.sin(a + 0.3) * 0.268, 0)], 0.002, "steel", 3)
        # front castor
        caster((x * 0.95, -0.31, 0), 0.075, "wc_frame", swivel=10 * s, stem=0.06)
        # footrest: hanger and plate (the left one folded up)
        sweep([(x * 0.9, -0.27, 0.45), (x * 0.85, -0.42, 0.18)], 0.01, "wc_frame", 8)
        if s > 0:
            box((0.13, 0.11, 0.008), (x * 0.65, -0.46, 0.17), (0, 0, 0), m="iron", bevel=0.003)
        else:
            box((0.13, 0.008, 0.11), (x * 0.65, -0.43, 0.23), (8, 0, 0), m="iron", bevel=0.003)
    # the folding X brace under the seat
    for s in (-1, 1):
        sweep([(s * sx, 0.0, 0.48), (-s * sx, 0.0, 0.22)], 0.01, "wc_frame", 8)
    cyl(0.014, 0.03, (0, 0.0, 0.35), (0, 90, 0), m="wc_frame", n=8)
    # sling seat and back, sagging
    grid(sx * 2, 0.42, 6, 6, lambda u, v: ((u - 0.5) * sx * 2, -0.25 + 0.4 * v,
                                             0.505 - 0.05 * math.sin(math.pi * u) * (0.6 + 0.4 * math.sin(math.pi * v))),
         m="wc_sling", thick=0.008)
    grid(sx * 2, 0.36, 6, 5, lambda u, v: ((u - 0.5) * sx * 2, 0.155 + 0.04 * v + 0.04 * math.sin(math.pi * u),
                                             0.58 + 0.33 * v), m="wc_sling", thick=0.008)


@piece("Gurney", close=((2.2, -3.0, 3.0), (0, -0.8, 2.3), 50))
def gurney():
    """a morgue trolley: a shape under a stained sheet, straps over it, a toe tag"""
    material("gur_frame", "chrome", rust=0.6, dull=0.85)
    material("sheet", "fabric", base="#cfcabb", stain=0.7, bloodied=0.45, moldy=0.35)
    material("strap", "leather", base="#4a2f1d", wear=0.7, bloodied=0.2)
    W, L, Z = 0.58, 1.9, 0.80
    for x in (-W / 2, W / 2):
        sweep([(x, -L / 2 - 0.12, Z + 0.12), (x, -L / 2, Z), (x, L / 2, Z), (x, L / 2 + 0.12, Z + 0.12)], 0.016,
              "gur_frame", 8, bend=0.05)
        for y in (-L / 2 + 0.1, L / 2 - 0.1):
            cyl(0.016, Z - 0.17, (x, y, (Z + 0.17) / 2), m="gur_frame", n=8)
            caster((x, y, 0), 0.055, "gur_frame", swivel=25 if y > 0 else -15, stem=0.02)
        cyl(0.012, L - 0.2, (x, 0, 0.2), (90, 0, 0), m="gur_frame", n=8)
    for y in (-L / 2 - 0.12, L / 2 + 0.12):
        cyl(0.016, W, (0, y, Z + 0.12), (0, 90, 0), m="gur_frame", n=8)
    for y in (-L / 2, L / 2):
        cyl(0.014, W, (0, y, Z), (0, 90, 0), m="gur_frame", n=8)
    box((W - 0.04, L - 0.24, 0.01), (0, 0, 0.21), m="steel")
    box((W, L, 0.012), (0, 0, Z + 0.01), m="steel", bevel=0.003)
    box((W - 0.03, L - 0.04, 0.05), (0, 0, Z + 0.04), m="vinyl", bevel=0.015, seg=2)

    # the body under the sheet: head, shoulders, chest, hips, legs, feet
    def body(x, y):
        h = 0.0
        for cx, cy, rx, ry, hh in ((0, 0.72, 0.1, 0.12, 0.16), (0, 0.35, 0.22, 0.25, 0.2), (0, 0.0, 0.19, 0.2, 0.17),
                                   (-0.09, -0.45, 0.08, 0.35, 0.12), (0.09, -0.45, 0.08, 0.35, 0.12),
                                   (-0.09, -0.85, 0.05, 0.05, 0.16), (0.09, -0.85, 0.05, 0.05, 0.16)):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            h = max(h, hh * math.exp(-d * 1.4))
        return h

    top = Z + 0.065
    SW = 1.2

    def sheet(u, v):
        x = (u - 0.5) * SW
        y = (v - 0.5) * (L + 0.1)
        edge = abs(x) - W / 2
        if edge > 0:      # hanging down the side, in folds
            z = top - edge * 1.6 + 0.012 * math.sin(v * 40)
            x = math.copysign(W / 2 + 0.02 + edge * 0.08, x)
        else:
            z = top + body(x, y) + 0.006 * math.sin(u * 23 + v * 17)
        return (x, y, z)

    grid(SW, L + 0.1, 22, 26, sheet, m="sheet", thick=0.006, rough_edge=0.01, seed=5)
    for yy in (0.35, -0.45):
        pts = []
        for i in range(9):
            x = -W / 2 + W * i / 8
            pts.append((x, yy, top + body(x, yy) + 0.012))
        pts = [(-W / 2 - 0.01, yy, Z - 0.06)] + pts + [(W / 2 + 0.01, yy, Z - 0.06)]
        ribbon(pts, 0.07, 0.007, "strap", bend=0.02, up=(0, 1, 0))
        buckle((W / 2 + 0.015, yy, Z), (0, 90, 0), 0.075, 0.05, "steel")
    # a toe tag hanging out from under the sheet
    tag = label_png("toe_tag", [("HOLLOWMERE", 0.8), ("No. 1961-0447", 1.0), ("UNCLAIMED", 0.9)], 300, 160,
                    bg=(214, 200, 160), font="type")
    material("tag_paper", "paper")
    decal("tag_paper", tag, here((0.09, -L / 2 - 0.08, Z - 0.02), (90, 0, 0)), (0.09, 0.05))
    sweep([(0.09, -L / 2 + 0.02, top + 0.05), (0.09, -L / 2 - 0.06, Z + 0.03)], 0.0015, "steel", 3)
    box((0.09, 0.003, 0.05), (0.09, -L / 2 - 0.075, Z - 0.02), m="tag_paper")


@piece("IVStand", close=((1.4, -2.0, 4.6), (0, 0, 4.4), 50))
def iv_stand():
    """a drip stand: five-legged base on castors, a glass bottle hung upside down, the line trailing"""
    material("iv_chrome", "chrome", rust=0.55, dull=0.8)
    material("iv_bottle", "glass", base="#9c9a80", frost=0.4)
    for i in range(5):
        a = 2 * math.pi * i / 5
        sweep([(0, 0, 0.12), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.09)], 0.013, "iv_chrome", 6)
        caster((math.cos(a) * 0.3, math.sin(a) * 0.3, 0), 0.03, "iv_chrome", swivel=math.degrees(a), stem=0.0)
    cyl(0.04, 0.06, (0, 0, 0.12), m="iv_chrome", n=12)
    cyl(0.014, 1.0, (0, 0, 0.62), m="iv_chrome", n=10)
    cyl(0.011, 0.95, (0, 0, 1.55), m="iv_chrome", n=10)
    cyl(0.02, 0.04, (0, 0, 1.11), m="iv_chrome", n=10)
    cyl(0.006, 0.05, (0.025, 0, 1.11), (0, 90, 0), m="bakelite", n=6)
    # hooks at the top
    for a in (0, 180):
        with place(T((0, 0, 2.0), (0, 0, a))):
            sweep([(0, 0, 0), (0.08, 0, 0.03), (0.13, 0, 0.0), (0.12, 0, -0.04)], 0.005, "iv_chrome", 6, bend=0.03)
    # the bottle in its wire hanger
    with place(T((0.12, 0, 1.78))):
        lathe([(0, -0.17), (0.01, -0.17), (0.012, -0.14), (0.045, -0.11), (0.05, -0.08), (0.05, 0.06), (0.045, 0.07),
               (0, 0.072)], m="iv_bottle", n=14)
        cyl(0.014, 0.03, (0, 0, -0.18), m="rubber", n=8)
        for a in (0, 90):
            with place(T((0, 0, 0), (0, 0, a))):
                sweep([(-0.055, 0, -0.06), (-0.055, 0, 0.08), (0, 0, 0.21), (0.055, 0, 0.08), (0.055, 0, -0.06)],
                      0.0018, "iv_chrome", 4, bend=0.02)
        torus(0.055, 0.002, (0, 0, -0.06), m="iv_chrome", n=12, k=4)
    # the line: down, a drip chamber, a roller clamp, coiled, the needle end dangling
    sweep([(0.12, 0, 1.6), (0.13, 0.02, 1.4), (0.18, 0.08, 1.0), (0.2, 0.02, 0.7), (0.12, -0.05, 0.55),
           (0.06, -0.02, 0.62), (0.1, 0.05, 0.5), (0.22, 0.1, 0.35)], 0.0035, "iv_bottle", 5, bend=0.06)
    cyl(0.009, 0.05, (0.12, 0, 1.56), m="iv_bottle", n=8)
    box((0.02, 0.012, 0.035), (0.175, 0.07, 1.05), m="bakelite", bevel=0.002)


@piece("PrivacyScreen", close=((2.2, -3.0, 3.2), (0, 0, 2.6), 50))
def privacy_screen():
    """a three-panel ward screen on castors: thin frames, sagging stained curtains, one torn"""
    material("scr_frame", "paint", base="#d3cebe", chip=0.6, rust=0.7, under="#7a8a80", peel=0.4)
    material("curtain", "fabric", base="#a7b5a4", stain=0.8, bloodied=0.12, moldy=0.6, dirt=0.75)
    PW, H = 0.62, 1.75
    # the panels zigzag: centre straight on, the side ones angled back
    for k, (cx, ang) in enumerate(((-0.56, -35), (0.0, 0), (0.56, 35))):
        with place(T((cx, 0.17 if k != 1 else 0, 0), (0, 0, ang))):
            sweep([(-PW / 2, 0, 0.1), (-PW / 2, 0, H), (PW / 2, 0, H), (PW / 2, 0, 0.1)], 0.014, "scr_frame", 8,
                  bend=0.03)
            cyl(0.008, PW, (0, 0, 0.32), (0, 90, 0), m="scr_frame", n=6)
            for x in (-PW / 2, PW / 2):
                caster((x, 0, 0), 0.03, "scr_frame", swivel=20, stem=0.0)
            for i in range(9):
                torus(0.012, 0.0025, (-PW / 2 + 0.03 + (PW - 0.06) * i / 8, 0, H - 0.03), (90, 0, 0), m="steel",
                      n=8, k=4)
            torn = k == 2

            def curtain(u, v, torn=torn, k=k):
                x = (u - 0.5) * (PW - 0.05)
                z = H - 0.05 - v * (H - 0.42)
                y = 0.012 * math.sin(u * 19 + k) * (0.3 + v) + 0.02 * v * math.sin(u * 6)
                if torn and v > 0.45:
                    y += 0.08 * (v - 0.45) * (1 - u)
                return (x, y, z)

            def keep(u, v, torn=torn):
                if not torn:
                    return not (v > 0.93 and (u * 13) % 2 < 0.6)
                return not (0.35 < u < 0.75 and v > 0.4 + 0.25 * abs(u - 0.55)) and not (v > 0.93 and (u * 13) % 2 < 0.8)

            grid(PW - 0.05, H - 0.42, 12, 18, curtain, m="curtain", keep=keep, thick=0.004, rough_edge=0.012,
                 seed=k + 2)
