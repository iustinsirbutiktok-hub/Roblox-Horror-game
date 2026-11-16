# Two single doors for the ward, each exported as two meshes: "Frame" (frame,
# architraves, hinge knuckles on the frame side) and "Door" (the leaf with all
# its fittings). The Door mesh's origin is on its hinge line, at floor height,
# so a script can swing it by rotating round that point.
# Opening 0.92 x 2.1 m (2.76 x 6.3 studs); frame 0.24 m deep (0.72 studs).
from kit import *  # noqa

OW, OH = 0.92, 2.10           # the clear opening
LW, LH, LT = 0.89, 2.085, 0.048  # the leaf
FD = 0.24                     # frame depth (through the wall)
HX = -OW / 2 + 0.006          # hinge line: the left edge of the leaf, seen from the front (-y)


def frame(paint_key):
    """jambs, head, stop beads and architraves both faces"""
    j = 0.07
    for s in (-1, 1):
        box((j, FD, OH + j), (s * (OW / 2 + j / 2), 0, (OH + j) / 2), m=paint_key, bevel=0.004)
        for y in (-1, 1):
            box((0.09, 0.022, OH + 0.09), (s * (OW / 2 + j + 0.035), y * (FD / 2 + 0.011), (OH + 0.09) / 2),
                m=paint_key, bevel=0.006)
        box((0.016, 0.03, OH), (s * (OW / 2 - 0.008), 0.045, OH / 2), m=paint_key, bevel=0.003)   # stop bead
    box((OW + 2 * j, FD, j), (0, 0, OH + j / 2), m=paint_key, bevel=0.004)
    for y in (-1, 1):
        box((OW + 2 * j + 0.25, 0.022, 0.09), (0, y * (FD / 2 + 0.011), OH + j + 0.045 - 0.025), m=paint_key, bevel=0.006)
    box((OW, 0.03, 0.016), (0, 0.045, OH - 0.008), m=paint_key, bevel=0.003)
    box((OW + 2 * j, FD + 0.02, 0.02), (0, 0, 0.01), m="steel", bevel=0.004)        # worn threshold
    # the frame-side hinge knuckles
    for z in (0.25, 1.05, 1.85):
        cyl(0.011, 0.07, (HX - 0.012, -0.03, z + 0.04), m="brass", n=8)


def hinge_leaves():
    for z in (0.25, 1.05, 1.85):
        cyl(0.011, 0.07, (HX - 0.012, -0.03, z - 0.035), m="brass", n=8)
        box((0.05, 0.004, 0.13), (HX + 0.02, -LT / 2 - 0.002, z), m="brass", bevel=0.001)


def lever(x, z, plate_key="chrome"):
    """a back plate, a lever handle on both faces, a keyhole"""
    for y in (-1, 1):
        box((0.05, 0.008, 0.2), (x, y * (LT / 2 + 0.004), z - 0.03), m=plate_key, bevel=0.003)
        with place(T((x, y * (LT / 2 + 0.01), z))):
            cyl(0.012, 0.05, (0, y * 0.02, 0), (90, 0, 0), m=plate_key, n=10)
            sweep([(0, y * 0.045, 0), (-0.11, y * 0.05, -0.01)], 0.009, plate_key, 8)
        box((0.008, 0.01, 0.022), (x, y * (LT / 2 + 0.009), z - 0.09), m="bakelite")


@piece("WardDoorGreen", close=((1.6, -3.4, 3.8), (0, 0, 3.4), 50))
def ward_door_green():
    """the ward door: hospital green gloss peeling to cream and grey primer, a wired
    glass window, push and kick plates, a lever handle, WARD C stencilled on"""
    material("door_green", "paint", base="#4f735e", chip=0.6, rust=-0.2, under="#cdc5a8", primer="#8a8270",
             peel=0.65, dirt=0.75, gloss=0.6, streaks=0.5)
    material("frame_cream", "paint", base="#cbc3a6", chip=0.55, rust=-0.3, under="#6f8574", peel=0.5, dirt=0.8)
    material("wired_glass", "glass", base="#56604f", frost=0.6, dirt=0.85)
    stencil = label_png("ward_c", [("WARD C", 1.0)], 420, 120, bg=None, fg=(232, 226, 204), font="cond", border=False)
    decal("door_green", stencil, here((0, -LT / 2 - 0.002, 1.12), (90, 0, 0)), (0.3, 0.085))
    frame("frame_cream")
    with group("Door", pivot=(HX, 0, 0)):
        x0 = HX
        cx = x0 + LW / 2
        # the leaf round its window (window 0.36 x 0.56, centred, its sill at 1.25 m)
        wx0, wx1, wz0, wz1 = cx - 0.18, cx + 0.18, 1.25, 1.81
        box((LW, LT, wz0 - 0.01), (cx, 0, (wz0 - 0.01) / 2 + 0.01), m="door_green", bevel=0.004)
        box((LW, LT, LH - wz1), (cx, 0, (wz1 + LH) / 2), m="door_green", bevel=0.004)
        box((wx0 - x0, LT, wz1 - wz0), ((x0 + wx0) / 2, 0, (wz0 + wz1) / 2), m="door_green", bevel=0.003)
        box((x0 + LW - wx1, LT, wz1 - wz0), ((wx1 + x0 + LW) / 2, 0, (wz0 + wz1) / 2), m="door_green", bevel=0.003)
        box((wx1 - wx0, 0.008, wz1 - wz0), (cx, 0, (wz0 + wz1) / 2), m="wired_glass")
        for y in (-1, 1):
            # glazing beads, and the raised panel mouldings below the window
            for zz in (wz0, wz1):
                box((wx1 - wx0 + 0.04, 0.014, 0.02), (cx, y * (LT / 2 + 0.005), zz), m="door_green", bevel=0.003)
            for xx in (wx0, wx1):
                box((0.02, 0.014, wz1 - wz0 + 0.04), (xx, y * (LT / 2 + 0.005), (wz0 + wz1) / 2), m="door_green", bevel=0.003)
            for (pz0, pz1) in ((0.32, 1.12),):
                for xx in (cx - 0.3, cx + 0.3):
                    box((0.018, 0.012, pz1 - pz0), (xx, y * (LT / 2 + 0.004), (pz0 + pz1) / 2), m="door_green", bevel=0.003)
                for zz in (pz0, pz1):
                    box((0.618, 0.012, 0.018), (cx, y * (LT / 2 + 0.004), zz), m="door_green", bevel=0.003)
            # kick plate (aluminium, scuffed) and push plate
            box((LW - 0.06, 0.003, 0.26), (cx, y * (LT / 2 + 0.0016), 0.15), m="steel", bevel=0.001)
        box((0.09, 0.003, 0.3), (x0 + LW - 0.11, LT / 2 + 0.0016, 1.3), m="steel", bevel=0.001)
        lever(x0 + LW - 0.075, 1.02)
        hinge_leaves()
        # a door closer arm on the push face, its body hanging off
        box((0.22, 0.05, 0.06), (x0 + 0.2, LT / 2 + 0.03, LH - 0.07), m="iron", bevel=0.008)
        sweep([(x0 + 0.3, LT / 2 + 0.06, LH - 0.05), (x0 + 0.45, LT / 2 + 0.12, LH - 0.02)], 0.008, "iron", 6)


@piece("IsolationDoor", close=((1.6, -3.4, 3.8), (0, 0, 3.4), 50))
def isolation_door():
    """the isolation-room door: heavy, steel-faced, grey-cream, a sliding viewing
    slot, a food hatch, a big barrel bolt, the room number and scratches"""
    material("iso_door", "paint", base="#b8b4a2", chip=0.55, rust=-0.3, under="#6d7f8a", primer="#7a7466",
             peel=0.45, dirt=0.85, gloss=0.35, streaks=0.6, bloodied=0.12)
    material("iso_frame", "paint", base="#8f8b7e", chip=0.5, rust=-0.3, under="#5d6a62", peel=0.35, dirt=0.85)
    number = label_png("room7", [("7", 1.0)], 160, 200, bg=(26, 24, 22), fg=(220, 212, 190), font="serif")
    material("number_plate", "paint", base="#2a2622", chip=0.2, rust=-1, peel=-1, dirt=0.4)
    decal("number_plate", number, here((-0.0, -LT / 2 - 0.016, 1.86), (90, 0, 0)), (0.08, 0.1))
    warn = label_png("iso_warn", [("ISOLATION", 1.0), ("KEEP LOCKED AT ALL TIMES", 0.5)], 480, 150, bg=(196, 182, 140),
                     fg=(110, 24, 18), font="serif")
    material("iso_warn", "paper")
    decal("iso_warn", warn, here((0, -LT / 2 - 0.009, 1.62), (90, 0, 0)), (0.36, 0.11))
    frame("iso_frame")
    with group("Door", pivot=(HX, 0, 0)):
        x0 = HX
        cx = x0 + LW / 2
        T2 = LT + 0.012
        # the slab round the viewing slot (0.2 x 0.06 at 1.5 m) and the food hatch (0.3 x 0.14 at 0.95 m)
        sx0, sx1, sz0, sz1 = cx - 0.1, cx + 0.1, 1.47, 1.53
        box((LW, T2, sz0), (cx, 0, sz0 / 2), m="iso_door", bevel=0.005)
        box((LW, T2, LH - sz1), (cx, 0, (sz1 + LH) / 2), m="iso_door", bevel=0.005)
        box((sx0 - x0, T2, sz1 - sz0), ((x0 + sx0) / 2, 0, (sz0 + sz1) / 2), m="iso_door")
        box((x0 + LW - sx1, T2, sz1 - sz0), ((sx1 + x0 + LW) / 2, 0, (sz0 + sz1) / 2), m="iso_door")
        box((sx1 - sx0, 0.004, sz1 - sz0), (cx, 0.0, (sz0 + sz1) / 2), m="bakelite")      # dark inside the slot
        # the slot's sliding cover, half open, in its runners
        for zz in (sz0 - 0.03, sz1 + 0.03):
            box((0.42, 0.012, 0.014), (cx + 0.06, -T2 / 2 - 0.006, zz), m="iso_frame", bevel=0.002)
        box((0.24, 0.006, 0.1), (cx + 0.17, -T2 / 2 - 0.009, (sz0 + sz1) / 2), m="iso_frame", bevel=0.002)
        cyl(0.01, 0.02, (cx + 0.09, -T2 / 2 - 0.02, (sz0 + sz1) / 2), (90, 0, 0), m="chrome", n=8)
        # food hatch (closed) with its own little bolt
        box((0.32, 0.01, 0.16), (cx, -T2 / 2 - 0.005, 0.95), m="iso_frame", bevel=0.003)
        box((0.06, 0.012, 0.02), (cx + 0.1, -T2 / 2 - 0.012, 0.95), m="chrome", bevel=0.002)
        for xx in (cx - 0.12, cx + 0.12):
            cyl(0.008, 0.03, (xx, -T2 / 2 - 0.01, 0.875), (0, 90, 0), m="brass", n=6)
        # the barrel bolt on the corridor side, and the keeper on the handle side
        box((0.24, 0.025, 0.06), (x0 + LW - 0.2, -T2 / 2 - 0.0125, 1.12), m="iron", bevel=0.004)
        cyl(0.015, 0.3, (x0 + LW - 0.14, -T2 / 2 - 0.028, 1.12), (0, 90, 0), m="chrome", n=10)
        box((0.012, 0.012, 0.05), (x0 + LW - 0.25, -T2 / 2 - 0.045, 1.13), m="chrome", bevel=0.002)
        # a pull handle (no handle on the inside: just the bare plate)
        sweep([(x0 + LW - 0.09, -T2 / 2, 0.92), (x0 + LW - 0.09, -T2 / 2 - 0.06, 0.94), (x0 + LW - 0.09, -T2 / 2 - 0.06, 1.06),
               (x0 + LW - 0.09, -T2 / 2, 1.08)], 0.011, "chrome", 8, bend=0.02)
        box((0.06, 0.006, 0.25), (x0 + LW - 0.09, T2 / 2 + 0.003, 1.0), m="iso_frame", bevel=0.002)
        # rivets round the steel facing, number plate, scratches clawed into the inside face
        for i in range(12):
            xx = x0 + 0.04 + (LW - 0.08) * i / 11
            for zz in (0.04, LH - 0.04):
                sphere(0.006, (xx, -T2 / 2 - 0.002, zz), m="iso_door", n=6, rings=3)
        box((0.09, 0.006, 0.11), (cx, -T2 / 2 - 0.004, 1.86), m="number_plate", bevel=0.002)
        box((0.37, 0.003, 0.115), (cx, -T2 / 2 - 0.0015, 1.62), m="iso_warn")
        hinge_leaves()
        for k in range(5):
            with place(T((cx - 0.12 + k * 0.05, T2 / 2 + 0.001, 0.95 - k * 0.02), (0, 0, 0))):
                box((0.006, 0.002, 0.35), (0, 0, 0), (0, -6 + k * 3, 0), m="bakelite")
