# Ashcombe Cross, part two: luggage left on the platform, the station master's
# desk and chair, and the departures board (every train cancelled but the last).
# Clean materials: worn varnish, faded leather, tarnished brass - no rust.
from kit import *  # noqa
import kit
from station import clean_paint


def brass_corner(at, rot=(0, 0, 0), s=0.026):
    box((s, s, s), at, rot, m="brass", bevel=s * 0.18)


def catch(at, rot=(0, 0, 0)):
    with place(T(at, rot)):
        box((0.035, 0.008, 0.045), m="brass", bevel=0.003)
        box((0.012, 0.012, 0.02), (0, -0.008, 0.008), m="brass", bevel=0.003)


def handle(at, w=0.12, rot=(0, 0, 0), m="leather"):
    with place(T(at, rot)):
        for x in (-w / 2, w / 2):
            box((0.02, 0.025, 0.02), (x, 0, 0.0), m="brass", bevel=0.004)
        sweep([(-w / 2, 0, 0.01), (-w / 2 + 0.01, 0, 0.045), (w / 2 - 0.01, 0, 0.045), (w / 2, 0, 0.01)], 0.011, m, 6,
              bend=0.02)


@piece("SuitcaseLeather", close=((0.9, -1.4, 1.2), (0, 0, 0.7), 50))
def suitcase_leather():
    """a brown leather suitcase standing on end: two straps, brass corners and catches, a worn handle"""
    material("case_leather", "leather", base="#5a3a24", wear=0.75)
    material("strap_dark", "leather", base="#2e1d12", wear=0.5)
    W, D, H = 0.66, 0.2, 0.46
    with place(T((0, 0, H / 2 + 0.01))):
        box((W, D, H), m="case_leather", bevel=0.03, seg=2)
        box((W + 0.004, D + 0.004, 0.012), (0, 0, 0.06), m="strap_dark", bevel=0.004)      # the lid's seam band
        for x in (-W / 2 + 0.002, W / 2 - 0.002):
            for z in (-H / 2 + 0.015, H / 2 - 0.015):
                for y in (-D / 2 + 0.01, D / 2 - 0.01):
                    brass_corner((x, y, z))
        for x in (-0.18, 0.18):
            # a strap right round it, buckled on the front
            box((0.04, D + 0.01, H + 0.01), (x, 0, 0), m="strap_dark", bevel=0.004)
            buckle((x, -D / 2 - 0.008, 0.12), (90, 0, 0), 0.05, 0.04, "brass")
            catch((x * 0.6, -D / 2 - 0.004, 0.06))
        handle((0, 0, H / 2 + 0.004), 0.13, (0, 0, 0))
        tag = label_png("lug_tag", [("PASSENGER'S", 0.6), ("LUGGAGE", 0.8), ("HOLLOWMERE", 1.0)], 260, 170,
                        bg=(214, 200, 160), font="type")
        material("tag_card", "paper")
        decal("tag_card", tag, here((0.1, -D / 2 - 0.022, 0.05), (90, 0, 8)), (0.09, 0.06))
        sweep([(0.055, -D / 2 - 0.01, H / 2 + 0.02), (0.08, -D / 2 - 0.02, 0.14), (0.1, -D / 2 - 0.02, 0.09)], 0.0015,
              "rubber", 3)
        box((0.09, 0.003, 0.06), (0.1, -D / 2 - 0.021, 0.05), (0, 0, 8), m="tag_card")


@piece("SuitcaseSmall", close=((0.8, -1.2, 0.9), (0, 0, 0.4), 50))
def suitcase_small():
    """a small cream fibreboard case lying flat, covered in faded hotel labels"""
    clean_paint("fibre", "#c9bc98", chip=0.25, gloss=0.3, dirt=0.7, streaks=0.2)
    W, D, H = 0.52, 0.34, 0.16
    labels = [("label_a", [("GRAND", 0.8), ("HOTEL", 1.0), ("ASHCOMBE", 0.7)], (156, 52, 40), (236, 222, 190)),
              ("label_b", [("HOLLOWMERE", 0.9), ("SPA", 1.0)], (40, 72, 100), (230, 220, 190)),
              ("label_c", [("RAILWAY", 0.8), ("HOTEL", 1.0)], (70, 92, 52), (232, 224, 196))]
    for i, (name, lines, bg, fg) in enumerate(labels):
        img = label_png(name, lines, 220, 160, bg=bg, fg=fg, font="serif")
        decal("fibre", img, here((-0.14 + i * 0.14, -0.04 + 0.05 * (i % 2), H + 0.012), (0, 0, -15 + i * 17)), (0.12, 0.09))
    with place(T((0, 0, H / 2 + 0.008))):
        box((W, D, H), m="fibre", bevel=0.02, seg=2)
        box((W + 0.004, D + 0.004, 0.01), (0, 0, 0.02), m="leather", bevel=0.003)
        for x in (-W / 2 + 0.005, W / 2 - 0.005):
            for y in (-D / 2 + 0.005, D / 2 - 0.005):
                for z in (-H / 2 + 0.012, H / 2 - 0.012):
                    brass_corner((x, y, z), s=0.022)
        for x in (-0.15, 0.15):
            catch((x, -D / 2 - 0.004, 0.02))
        handle((0, -D / 2 - 0.004, 0.0), 0.12, (90, 0, 0))


@piece("SteamerTrunk", close=((1.4, -2.0, 1.6), (0, 0, 0.9), 50))
def steamer_trunk():
    """a steamer trunk: canvas over wood, wooden slats, brass corners and lock, leather side handles"""
    material("trunk_canvas", "canvas", base="#5d5442", stain=0.5, moldy=0.15)
    material("trunk_slat", "wood", base="#6e5232", dark="#36261a", axis="X", wear=0.6, water=0.3, varnish=0.4)
    W, D, H = 0.92, 0.52, 0.56
    with place(T((0, 0, H / 2 + 0.01))):
        box((W, D, H), m="trunk_canvas", bevel=0.02, seg=2)
        for z in (-0.18, 0.06, 0.2):
            for y in (-1, 1):
                box((W + 0.01, 0.014, 0.05), (0, y * (D / 2 + 0.005), z), m="trunk_slat", bevel=0.004)
        for x in (-0.3, 0.0, 0.3):
            box((0.05, D + 0.012, 0.014), (x, 0, H / 2 + 0.005), m="trunk_slat", bevel=0.004)
            for y in (-1, 1):
                box((0.05, 0.014, H), (x, y * (D / 2 + 0.006), 0), m="trunk_slat", bevel=0.004)
        for x in (-W / 2, W / 2):
            for y in (-D / 2, D / 2):
                for z in (-H / 2 + 0.02, H / 2 - 0.02):
                    brass_corner((x, y, z), s=0.045)
        box((W + 0.006, D + 0.006, 0.01), (0, 0, 0.13), m="brass", bevel=0.002)      # the lid's edge
        box((0.07, 0.012, 0.09), (0, -D / 2 - 0.012, 0.12), m="brass", bevel=0.006)
        cyl(0.008, 0.014, (0, -D / 2 - 0.02, 0.11), (90, 0, 0), m="bakelite", n=6)
        for x in (-W / 2 - 0.005, W / 2 + 0.005):
            handle((x, 0, 0.05), 0.16, (0, 90, 90))


@piece("CarpetBag", close=((0.9, -1.3, 1.1), (0, 0, 0.6), 50))
def carpet_bag():
    """a soft carpet bag on a hinged frame, slumped, with two leather handles"""
    material("carpet", "fabric", base="#6a2e2a", stripe="#3c4a3a", axis="X", stripe_scale=11.0, stain=0.25, moldy=0.05)
    with place(T((0, 0, 0))):
        lump(0.25, (0, 0, 0.19), m="carpet", seed=7, squash=(1.35, 0.7, 0.78), rough=0.08, n=16, rings=10)
        for y in (-0.03, 0.03):
            box((0.48, 0.02, 0.025), (0, y, 0.37), m="brass", bevel=0.006)
        sweep([(-0.12, 0, 0.385), (-0.1, 0, 0.5), (0.1, 0, 0.5), (0.12, 0, 0.385)], 0.013, "leather", 6, bend=0.04)
        sweep([(-0.12, 0.04, 0.38), (-0.11, 0.12, 0.45), (0.11, 0.12, 0.45), (0.12, 0.04, 0.38)], 0.013, "leather", 6,
              bend=0.04)
        box((0.4, 0.3, 0.02), (0, 0, 0.01), m="leather", bevel=0.01)


@piece("HatBox", close=((0.8, -1.2, 0.9), (0, 0, 0.45), 50))
def hat_box():
    """a round hat box in faded striped card, lid askew, a leather carrying strap"""
    material("hatbox", "fabric", base="#c7b593", stripe="#8a6a5a", axis="Z", stripe_scale=6.0, stain=0.55, moldy=0.1)
    lathe([(0, 0.005), (0.22, 0.005), (0.22, 0.27), (0, 0.27)], m="hatbox", n=24)
    with place(T((0.015, 0.01, 0.0), (3, -2, 0))):
        lathe([(0, 0.255), (0.228, 0.255), (0.228, 0.31), (0, 0.31)], m="hatbox", n=24)
    sweep([(-0.225, 0, 0.12), (-0.24, 0, 0.36), (-0.1, 0, 0.45), (0.1, 0, 0.45), (0.24, 0, 0.36), (0.225, 0, 0.12)],
          0.008, "leather", 4, bend=0.06)


@piece("StationDesk", close=((2.0, -3.0, 3.4), (0, 0, 2.4), 45))
def station_desk():
    """the station master's pedestal desk: drawers both sides, a green leather top,
    a blotter, an open ledger, an inkwell, a bakelite telephone and a banker's lamp"""
    material("desk_wood", "wood", base="#5b3f26", dark="#2a1b10", axis="X", grain=5.0, wear=0.55, water=0.25, varnish=0.7)
    material("desk_leather", "leather", base="#2f4a34", wear=0.65)
    material("lamp_green", "glass", base="#1e4a2c", frost=0.2, dirt=0.6)
    material("ledger", "paper", base="#d4c7a2")
    W, D, H = 1.45, 0.76, 0.76
    box((W, D, 0.04), (0, 0, H - 0.02), m="desk_wood", bevel=0.01)
    box((W - 0.16, D - 0.16, 0.004), (0, 0, H + 0.0005), m="desk_leather")
    for s in (-1, 1):
        cx = s * (W / 2 - 0.22)
        box((0.42, D - 0.04, H - 0.1), (cx, 0, (H - 0.1) / 2 + 0.06), m="desk_wood", bevel=0.008)
        box((0.44, D - 0.02, 0.06), (cx, 0, 0.03), m="desk_wood", bevel=0.006)          # plinth
        for k, z in enumerate((0.58, 0.4, 0.17)):
            hh = 0.15 if k < 2 else 0.24
            out = 0.06 if (s > 0 and k == 1) else 0.0
            box((0.38, 0.02, hh), (cx, -D / 2 + 0.01 - out, z), m="desk_wood", bevel=0.006)
            handle((cx, -D / 2 - 0.005 - out, z), 0.08, (90, 0, 0), "brass")
    box((W - 0.88, 0.02, 0.2), (0, D / 2 - 0.04, H - 0.14), m="desk_wood", bevel=0.005)   # modesty panel
    box((W - 0.9, D - 0.08, 0.1), (0, 0, H - 0.09), m="desk_wood", bevel=0.005)          # centre drawer
    handle((0, -D / 2 + 0.035, H - 0.09), 0.1, (90, 0, 0), "brass")
    top = H + 0.003
    # blotter and the ledger open on it
    box((0.5, 0.36, 0.008), (-0.1, -0.08, top + 0.004), m="paper", bevel=0.002)
    for s in (-1, 1):
        with place(T((0.2 + s * 0.12, 0.05, top + 0.012), (0, s * -4, 0))):
            box((0.24, 0.32, 0.02), m="ledger", bevel=0.003)
    box((0.01, 0.32, 0.03), (0.2, 0.05, top + 0.015), m="desk_leather", bevel=0.003)
    # inkwell and pen
    lathe([(0, 0), (0.035, 0), (0.035, 0.05), (0.012, 0.06), (0.012, 0.075), (0, 0.075)], (0.45, 0.2, top), m="glass", n=10)
    cyl(0.004, 0.16, (0.38, 0.1, top + 0.006), (90, 0, 60), m="bakelite", n=6)
    # the telephone: a candlestick-free bakelite set with its handset on the cradle
    with place(T((-0.5, 0.15, top))):
        lathe([(0, 0), (0.11, 0), (0.1, 0.04), (0.075, 0.1), (0.05, 0.11), (0, 0.11)], m="bakelite", n=14,
              stretch=(1.0, 0.85))
        cyl(0.045, 0.012, (0, -0.06, 0.07), (60, 0, 0), m="paper", n=14)
        with place(T((0, 0, 0.13))):
            box((0.22, 0.04, 0.025), m="bakelite", bevel=0.01)
            for x in (-0.1, 0.1):
                sphere(0.035, (x, 0, -0.01), m="bakelite", n=8, rings=5)
        sweep([(0.08, 0.06, 0.03), (0.15, 0.15, 0.0), (0.12, 0.25, -0.0)], 0.005, "rubber", 4, bend=0.05)
    # the banker's lamp
    with place(T((0.55, 0.22, top))):
        lathe([(0, 0), (0.08, 0), (0.08, 0.02), (0.02, 0.03), (0, 0.03)], m="brass", n=12)
        cyl(0.01, 0.3, (0, 0, 0.17), m="brass", n=6)
        with place(T((0, -0.06, 0.33), (12, 0, 90))):
            lathe([(0.0, -0.06), (0.06, -0.05), (0.07, 0.0), (0.0, 0.0)], m="lamp_green", n=10, arc=(0, 180),
                  stretch=(1.0, 3.0))
    # papers scattered
    for i, (x, y, a) in enumerate(((-0.35, -0.2, 12), (-0.2, -0.25, -20), (0.55, -0.2, 35))):
        box((0.21, 0.297, 0.002), (x, y, top + 0.002 + i * 0.002), (0, 0, a), m="paper")


@piece("DeskChair", close=((1.2, -1.8, 2.4), (0, 0, 1.6), 50))
def desk_chair():
    """a wooden swivel office chair: saddle seat, curved spindle back and arms, four legs on castors"""
    material("chair_wood", "wood", base="#5b3f26", dark="#2a1b10", axis="Y", grain=5.0, wear=0.6, water=0.2, varnish=0.6)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        sweep([(0, 0, 0.2), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.06)], 0.022, "chair_wood", 6)
        caster((math.cos(a) * 0.3, math.sin(a) * 0.3, 0), 0.025, "brass", swivel=i * 37, stem=0.0)
    cyl(0.03, 0.26, (0, 0, 0.3), m="iron", n=10)
    cyl(0.05, 0.03, (0, 0, 0.44), m="iron", n=12)
    seat = rounded_rect(0.46, 0.44, 0.12, 3)
    slab(seat, 0.045, (0, 0, 0.47), m="chair_wood", bevel=0.012)
    # the back: a bent top rail on spindles, its ends sweeping forward into the arms
    rail = [(math.cos(math.radians(a)) * 0.25, 0.03 + math.sin(math.radians(a)) * 0.22, 0.0) for a in range(-10, 191, 20)]
    with place(T((0, 0, 0.72))):
        sweep(rail, 0.025, "chair_wood", 6)
    for s in (-1, 1):
        sweep([(s * 0.25, 0.0, 0.72), (s * 0.24, -0.15, 0.68), (s * 0.22, -0.2, 0.6)], 0.022, "chair_wood", 6, bend=0.05)
        cyl(0.012, 0.13, (s * 0.21, -0.18, 0.55), m="chair_wood", n=6)
    for a in range(20, 161, 20):
        x = math.cos(math.radians(a)) * 0.23
        y = 0.03 + math.sin(math.radians(a)) * 0.2
        cyl(0.011, 0.24, (x, y, 0.6), m="chair_wood", n=6)


@piece("DeparturesBoard", close=((2.6, -4.6, 6.0), (0, 0, 5.4), 45))
def departures_board():
    """the departures board on its posts: every train cancelled, the last one still 'delayed'"""
    material("board_wood", "wood", base="#3f2c1c", dark="#1e140c", axis="X", wear=0.5, water=0.3, varnish=0.5)
    from PIL import Image, ImageDraw
    w, h = 1600, 1000
    im = Image.new("RGBA", (w, h), (24, 30, 34, 255))
    d = ImageDraw.Draw(im)
    head = kit._font("serif", 92)
    row = kit._font("mono", 50)
    small = kit._font("serif", 40)
    t = "DEPARTURES"
    d.text(((w - d.textlength(t, font=head)) / 2, 30), t, font=head, fill=(232, 222, 190, 255))
    t = "ASHCOMBE CROSS  -  WINTER TIMETABLE 1958"
    d.text(((w - d.textlength(t, font=small)) / 2, 140), t, font=small, fill=(190, 182, 156, 255))
    d.line((60, 205, w - 60, 205), fill=(190, 182, 156, 255), width=4)
    rows = [("TIME", "DESTINATION", "PLAT", "REMARKS"), ("17:52", "MERIDIAN JUNCTION", "1", "CANCELLED"),
            ("18:30", "ASHFORD VALE", "2", "CANCELLED"), ("19:15", "HOLLOWMERE HALT", "1", "CANCELLED"),
            ("20:40", "KINGSBRIDGE", "2", "CANCELLED"), ("22:05", "MERIDIAN JUNCTION", "1", "CANCELLED"),
            ("23:17", "HOLLOWMERE (LAST)", "2", "DELAYED")]
    for i, (a, b, c, e) in enumerate(rows):
        y = 230 + i * 104
        col = (210, 202, 176, 255) if i else (160, 152, 128, 255)
        if i:
            d.rectangle((50, y - 8, w - 50, y + 78), fill=(34, 40, 44, 255))
        d.text((80, y), a, font=row, fill=col)
        d.text((310, y), b, font=row, fill=col)
        d.text((1010, y), c, font=row, fill=col)
        ec = (200, 60, 46, 255) if e == "CANCELLED" else ((226, 186, 70, 255) if e == "DELAYED" else col)
        d.text((1170, y), e, font=row, fill=ec)
    path = kit._save(im, "departures")
    clean_paint("board_face", "#1e2428", chip=0.25, peel=0.15, dirt=0.75)
    decal("board_face", path, here((0, -0.035, 2.25), (90, 0, 0)), (2.0, 1.25))
    box((2.24, 0.05, 1.46), (0, 0, 2.25), m="board_wood", bevel=0.012)
    box((2.04, 0.012, 1.27), (0, -0.026, 2.25), m="board_face")
    box((2.36, 0.12, 0.08), (0, -0.03, 3.02), m="board_wood", bevel=0.02)          # its little roof
    for x in (-1.0, 1.0):
        box((0.1, 0.1, 3.0), (x, 0.06, 1.5), m="board_wood", bevel=0.012)
        box((0.18, 0.18, 0.06), (x, 0.06, 0.03), m="iron", bevel=0.01)
