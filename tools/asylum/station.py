# Ashcombe Cross: an abandoned railway station. Dusty, faded, grimy - but no rust:
# painted cast iron, old timber, concrete, worn steel.
# Track: standard gauge (1.435 m), 4.8 m sections that butt end to end.
from kit import *  # noqa
import kit

GAUGE = 1.435
RAIL_H = 0.15
TRACK_L = 4.8


def clean_paint(key, base, **kw):
    """old paint that has faded and filmed over but not rusted"""
    opts = dict(chip=0.2, rust=-2.0, peel=-0.3, dirt=0.65, streaks=0.35, under="#6b6a62", primer="#7c7a72", gloss=0.4)
    opts.update(kw)
    return material(key, "paint", base=base, **opts)


def rail_profile():
    """a flat-bottom rail's cross-section (x across, y up), 0.15 m tall"""
    return [(-0.07, 0.0), (0.07, 0.0), (0.07, 0.012), (0.012, 0.03), (0.009, 0.105), (0.035, 0.115), (0.036, 0.148),
            (0.03, 0.152), (-0.03, 0.152), (-0.036, 0.148), (-0.035, 0.115), (-0.009, 0.105), (-0.012, 0.03), (-0.07, 0.012)]


def rails(length, z0, y0=0.0):
    material("rail_steel", "chrome", base="#5d5a55", rust=-1.5, dull=1.0)
    for x in (-GAUGE / 2 - 0.035, GAUGE / 2 + 0.035):
        # extruded along y: the profile is drawn in local XY, rot (90,0,0) turns local Y up and the depth along -y
        slab(rail_profile(), length, (x, y0, z0), (90, 0, 0), m="rail_steel", smooth=40)


def sleepers(length, z_top, step=0.65):
    material("sleeper", "wood", base="#4a3c2e", dark="#221a12", axis="Y", grain=4.0, wear=0.3, water=0.6, varnish=0.0)
    material("chair", "chrome", base="#4c4a46", rust=-1.5, dull=1.0)
    n = int(length / step)
    for i in range(n):
        y = -length / 2 + step / 2 + i * step
        box((2.6, 0.25, 0.15), (0, y, z_top - 0.075), (0, 0, ((i * 37) % 7 - 3) * 0.4), m="sleeper", bevel=0.012)
        for x in (-GAUGE / 2 - 0.035, GAUGE / 2 + 0.035):
            box((0.32, 0.17, 0.016), (x, y, z_top + 0.008), m="chair", bevel=0.003)
            for s in (-1, 1):
                box((0.03, 0.05, 0.03), (x + s * 0.11, y, z_top + 0.03), m="chair", bevel=0.004)
                cyl(0.012, 0.03, (x + s * 0.14, y + 0.05 * s, z_top + 0.025), m="chair", n=6)


def ballast(length, top):
    """the stone bed: a trapezoid the sleepers sit down into"""
    material("ballast", "stone")
    prof = [(-2.0, 0.0), (2.0, 0.0), (1.55, top), (-1.55, top)]
    slab(prof, length, (0, length / 2 - length / 2, 0), (90, 0, 0), m="ballast")


@piece("RailTrack", close=((3.0, -5.0, 2.6), (0, 0, 0.5), 45))
def rail_track():
    """a straight 4.8 m section: ballast, timber sleepers, chairs and clips, two rails"""
    top = 0.22
    ballast(TRACK_L, top)
    sleepers(TRACK_L, top + 0.07)
    rails(TRACK_L, top + 0.07 + 0.016)


@piece("BufferStop", close=((3.0, -5.0, 3.0), (0, 0, 1.6), 45))
def buffer_stop():
    """the end of the line: a timber beam on a steel frame with two round buffers, painted red"""
    clean_paint("buffer_red", "#8e2a22", chip=0.3)
    clean_paint("buffer_frame", "#262624")
    material("beam", "wood", base="#5a4430", dark="#2a1e14", axis="X", wear=0.4, water=0.3)
    top = 0.22
    ballast(3.0, top)
    sleepers(3.0, top + 0.07)
    rails(3.0, top + 0.07 + 0.016)
    rz = top + 0.07 + 0.016 + RAIL_H
    y = 1.0
    # the frame: raking struts from the rails back to the beam posts
    for x in (-GAUGE / 2 - 0.035, GAUGE / 2 + 0.035):
        box((0.12, 0.12, 0.85), (x, y, rz + 0.42), m="buffer_frame", bevel=0.01)
        sweep([(x, y + 0.05, rz + 0.75), (x, y + 1.2, rz)], 0.045, "buffer_frame", 4)
    box((2.3, 0.35, 0.4), (0, y - 0.15, rz + 0.75), m="beam", bevel=0.02)
    box((2.32, 0.02, 0.06), (0, y - 0.33, rz + 0.95), m="buffer_red")
    for x in (-0.87, 0.87):
        with place(T((x, y - 0.33, rz + 0.75), (90, 0, 0))):
            cyl(0.11, 0.06, (0, 0, 0.03), m="buffer_frame", n=14)
            cyl(0.06, 0.28, (0, 0, 0.17), m="chrome", n=12)
            cyl(0.22, 0.04, (0, 0, 0.32), m="buffer_red", n=18)
    box((0.5, 0.02, 0.5), (0, y - 0.335, rz + 1.05), m="buffer_red", bevel=0.01)
    lathe([(0, 0), (0.1, 0), (0.1, 0.02), (0, 0.02)], (0, y - 0.35, rz + 1.05), (90, 0, 0), m="glass", n=12)


@piece("PlatformEdge", close=((3.5, -5.5, 3.5), (0, -1.0, 2.6), 45))
def platform_edge():
    """a 3 m piece of platform: brick-faced concrete wall, overhanging coping stones,
    a faded yellow line and tactile strip, the surface dusty and patched (stands at rail level)"""
    material("plat_concrete", "concrete", base="#8a877e")
    material("coping", "concrete", base="#a19d92", stain=0.35)
    clean_paint("yellow_line", "#b8952e", chip=0.6, peel=0.4, dirt=0.7)
    L, D, H = 3.0, 2.5, 0.915
    box((L, D, H - 0.08), (0, 0.15 + D / 2, (H - 0.08) / 2), m="plat_concrete", bevel=0.01)
    for i in range(5):
        box((0.6 - 0.008, 0.6, 0.08), (-L / 2 + 0.3 + i * 0.6, 0.15 + 0.3 - 0.25, H - 0.04), m="coping", bevel=0.012)
    box((L, 0.1, 0.004), (0, 0.6, H + 0.001), m="yellow_line")
    for i in range(10):
        box((L / 10 - 0.02, 0.4, 0.012), (-L / 2 + L / 20 + i * L / 10, 0.98, H - 0.075), m="coping", bevel=0.004)
    box((L, D - 1.2, 0.003), (0, 0.15 + 1.2 + (D - 1.2) / 2, H - 0.078), m="plat_concrete")


@piece("PlatformBench", close=((1.6, -2.6, 2.0), (0, 0, 1.3), 50))
def platform_bench():
    """a station bench: cast-iron ends painted dark green, timber slats"""
    clean_paint("bench_iron", "#26372d", chip=0.35)
    material("slat", "wood", base="#6a5440", dark="#33261a", axis="X", wear=0.6, water=0.35, varnish=0.3)
    L = 1.8
    for x in (-L / 2 + 0.12, 0.0, L / 2 - 0.12):
        # a cast-iron end: front leg, raked back leg running up into the back support, seat bearer, armrest
        box((0.05, 0.05, 0.46), (x, -0.24, 0.23), (6, 0, 0), m="bench_iron", bevel=0.008)
        sweep([(x, 0.2, 0.0), (x, 0.17, 0.45), (x, 0.27, 0.92)], 0.026, "bench_iron", 6, bend=0.12)
        box((0.045, 0.56, 0.05), (x, -0.02, 0.43), m="bench_iron", bevel=0.008)
        box((0.045, 0.3, 0.03), (x, -0.22, 0.03), m="bench_iron", bevel=0.006)          # the foot
        if x != 0.0:
            sweep([(x, 0.2, 0.66), (x, -0.1, 0.68), (x, -0.27, 0.64), (x, -0.27, 0.46)], 0.022, "bench_iron", 6,
                  bend=0.06)
    for i in range(5):
        y = -0.24 + i * 0.1
        box((L, 0.085, 0.035), (0, y, 0.47 - 0.004 * i), m="slat", bevel=0.008)
    with place(T((0, 0.2, 0.52), (-18, 0, 0))):
        for i in range(3):
            box((L, 0.03, 0.09), (0, 0, 0.08 + i * 0.12), m="slat", bevel=0.008)
    for x in (-0.6, 0.6):
        cyl(0.012, L, (0, x * 0.2, 0.3), (0, 90, 0), m="bench_iron", n=8)


@piece("LampPost", close=((1.2, -2.0, 10.0), (0, 0, 9.5), 50))
def lamp_post():
    """a cast-iron platform lamp: fluted column, a cross-bar, the lantern with its glass and cap"""
    clean_paint("lamp_iron", "#1e2a24", chip=0.3)
    material("lamp_glass", "glass", base="#9a9888", frost=0.6, dirt=0.8)
    lathe([(0.0, 0.0), (0.16, 0.0), (0.16, 0.1), (0.12, 0.16), (0.11, 0.5), (0.085, 0.58), (0.075, 0.62),
           (0.06, 0.65), (0.055, 2.9), (0.07, 2.95), (0.07, 3.0), (0.0, 3.0)], m="lamp_iron", n=12)
    cyl(0.012, 0.6, (0, 0, 2.7), (0, 90, 0), m="lamp_iron", n=6)            # the ladder bar
    with place(T((0, 0, 3.0))):
        lathe([(0.06, 0.0), (0.14, 0.05), (0.15, 0.08), (0.0, 0.08)], m="lamp_iron", n=8)
        for i in range(4):
            a = math.radians(45 + 90 * i)
            cyl(0.008, 0.42, (math.cos(a) * 0.17, math.sin(a) * 0.17, 0.29), m="lamp_iron", n=5)
        lathe([(0.11, 0.08), (0.2, 0.5), (0.0, 0.5)], m="lamp_glass", n=4, stretch=(1, 1))
        lathe([(0.0, 0.48), (0.23, 0.5), (0.25, 0.53), (0.08, 0.66), (0.03, 0.72), (0.035, 0.78), (0.0, 0.8)],
              m="lamp_iron", n=4)
        lathe([(0, 0.15), (0.03, 0.15), (0.035, 0.25), (0, 0.3)], m="lamp_glass", n=8)


@piece("StationSign", close=((2.0, -4.0, 6.0), (0, 0, 5.4), 50))
def station_sign():
    """the station nameboard on two posts: ASHCOMBE CROSS, white on faded blue"""
    clean_paint("sign_post", "#1c2622", chip=0.3)
    board = label_png("ashcombe", [("ASHCOMBE CROSS", 1.0)], 1400, 240, bg=(38, 58, 92), fg=(232, 230, 220), font="sans",
                      border=True)
    clean_paint("sign_board", "#26395a", chip=0.4, peel=0.2, dirt=0.8)
    for y in (-1, 1):
        decal("sign_board", board, here((0, y * 0.03, 2.1), (90, 0, 0 if y < 0 else 180)), (2.5, 0.43))
    box((2.6, 0.04, 0.5), (0, 0, 2.1), m="sign_board", bevel=0.01)
    for x in (-1.15, 1.15):
        cyl(0.04, 2.4, (x, 0, 1.2), m="sign_post", n=10)
        sphere(0.05, (x, 0, 2.42), m="sign_post", n=10, rings=5)
        box((0.12, 0.12, 0.05), (x, 0, 0.025), m="sign_post", bevel=0.01)


@piece("PlatformClock", close=((1.2, -2.0, 7.0), (0, 0, 6.4), 50))
def platform_clock():
    """a double-sided clock on a wall bracket, both faces stopped at 3:17"""
    clean_paint("clock_case", "#1d2622", chip=0.3)
    face = clock = None
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((8, 8, 504, 504), fill=(232, 228, 214, 255))
    f = kit._font("serif", 48)
    for h in range(1, 13):
        a = math.radians(90 - h * 30)
        t = str(h)
        tw = d.textlength(t, font=f)
        d.text((256 + math.cos(a) * 190 - tw / 2, 256 - math.sin(a) * 190 - 28), t, font=f, fill=(20, 20, 20, 255))
    for m_ in range(60):
        a = math.radians(90 - m_ * 6)
        r0 = 228 if m_ % 5 else 214
        d.line((256 + math.cos(a) * r0, 256 - math.sin(a) * r0, 256 + math.cos(a) * 240, 256 - math.sin(a) * 240),
               fill=(20, 20, 20, 255), width=3 if m_ % 5 else 6)
    for ang, ln, w in ((90 - (3 + 17 / 60) * 30, 130, 12), (90 - 17 * 6, 200, 7)):
        a = math.radians(ang)
        d.line((256, 256, 256 + math.cos(a) * ln, 256 - math.sin(a) * ln), fill=(15, 15, 15, 255), width=w)
    d.ellipse((244, 244, 268, 268), fill=(15, 15, 15, 255))
    path = kit._save(im, "clock_face")
    material("clock_face", "paint", base="#e4e0d2", chip=0.05, rust=-2, peel=-1, dirt=0.5, streaks=0.3)
    for y in (-1, 1):
        decal("clock_face", path, here((0.55, y * 0.066, 0.3), (90, 0, 0 if y < 0 else 180)), (0.5, 0.5))
    with place(T((0.55, 0, 0.3))):
        cyl(0.29, 0.12, (0, 0, 0), (90, 0, 0), m="clock_case", n=24)
        for y in (-1, 1):
            cyl(0.255, 0.005, (0, y * 0.062, 0), (90, 0, 0), m="clock_face", n=24)
            torus(0.265, 0.015, (0, y * 0.06, 0), (90, 0, 0), m="brass", n=24, k=5)
        sphere(0.04, (0, 0, 0.33), m="clock_case", n=8, rings=5)
    sweep([(0, 0, 0.65), (0.3, 0, 0.65), (0.55, 0, 0.6)], 0.03, "clock_case", 8, bend=0.05)
    box((0.06, 0.2, 0.5), (0, 0, 0.55), m="clock_case", bevel=0.01)
    _ = (face, clock)


@piece("LitterBin", close=((1.0, -1.6, 2.0), (0, 0, 1.3), 50))
def litter_bin():
    """a painted iron station litter bin with its liner, an old newspaper in it"""
    clean_paint("bin_paint", "#2c3a30", chip=0.35)
    lathe([(0, 0.02), (0.2, 0.02), (0.22, 0.75), (0.24, 0.78), (0.2, 0.78), (0.18, 0.06), (0, 0.06)], m="bin_paint", n=16)
    for i in range(3):
        cyl(0.03, 0.04, (math.cos(i * 2.09) * 0.16, math.sin(i * 2.09) * 0.16, 0.01), m="bin_paint", n=6)
    box((0.3, 0.22, 0.02), (0.03, 0.02, 0.74), (40, 8, 15), m="paper", bevel=0.005)


@piece("LuggageTrolley", close=((2.4, -3.6, 2.6), (0, 0, 1.4), 45))
def luggage_trolley():
    """a platform barrow: a timber deck on an iron frame, two big wheels, a long handle, two old cases"""
    clean_paint("barrow_iron", "#2b2a27", chip=0.3)
    material("deck", "wood", base="#6b5641", dark="#33261a", axis="Y", wear=0.65, water=0.4, varnish=0.2)
    material("case", "leather", base="#4c3a2a", wear=0.7)
    L, W = 1.9, 0.9
    for i in range(6):
        box((W / 6 - 0.01, L, 0.04), (-W / 2 + W / 12 + i * W / 6, 0, 0.62), m="deck", bevel=0.006)
    for x in (-W / 2 + 0.03, W / 2 - 0.03):
        box((0.05, L, 0.09), (x, 0, 0.56), m="barrow_iron", bevel=0.006)
    for y in (-L / 2 + 0.1, L / 2 - 0.1):
        box((W, 0.05, 0.06), (0, y, 0.56), m="barrow_iron", bevel=0.006)
    for x in (-W / 2 - 0.06, W / 2 + 0.06):
        with place(T((x, 0.2, 0.34), (0, 90, 0))):
            torus(0.32, 0.025, m="barrow_iron", n=20, k=5)
            cyl(0.05, 0.08, m="barrow_iron", n=10)
            for i in range(8):
                a = 2 * math.pi * i / 8
                sweep([(0, 0, 0), (math.cos(a) * 0.31, math.sin(a) * 0.31, 0)], 0.012, "barrow_iron", 4)
    cyl(0.025, W + 0.2, (0, 0.2, 0.34), (0, 90, 0), m="barrow_iron", n=8)
    for x in (-W / 2 + 0.1, W / 2 - 0.1):
        cyl(0.03, 0.5, (x, -L / 2 + 0.15, 0.27), m="barrow_iron", n=8)
    sweep([(-0.35, L / 2, 0.6), (-0.3, L / 2 + 0.7, 0.95), (0.3, L / 2 + 0.7, 0.95), (0.35, L / 2, 0.6)], 0.022,
          "barrow_iron", 8, bend=0.08)
    box((0.66, 0.42, 0.22), (0.05, -0.3, 0.75), (0, 0, 8), m="case", bevel=0.03, seg=2)
    box((0.5, 0.34, 0.18), (-0.05, 0.25, 0.73), (0, 0, -12), m="case", bevel=0.03, seg=2)
    for (x, y, a) in ((0.05, -0.3, 8), (-0.05, 0.25, -12)):
        with place(T((x, y, 0.86 if y < 0 else 0.82), (0, 0, a))):
            sweep([(-0.08, 0, 0), (-0.06, 0, 0.04), (0.06, 0, 0.04), (0.08, 0, 0)], 0.008, "leather", 5, bend=0.01)


@piece("RailSignal", close=((1.6, -2.4, 13.0), (0, 0, 12.0), 50))
def rail_signal():
    """a colour-light signal: post, ladder and cage, a three-aspect head with hooded lenses"""
    clean_paint("signal_post", "#3a3b38", chip=0.3)
    clean_paint("signal_head", "#141414", chip=0.2, dirt=0.5)
    clean_paint("signal_white", "#d8d6cc", chip=0.3)
    material("lens_red", "glass", base="#5a1712", frost=0.25)
    material("lens_amber", "glass", base="#6a4510", frost=0.25)
    material("lens_green", "glass", base="#163a22", frost=0.25)
    concrete_key = material("sig_base", "concrete", base="#8a877e")
    box((0.6, 0.6, 0.3), (0, 0, 0.15), m=concrete_key, bevel=0.03)
    box((0.16, 0.16, 4.2), (0, 0, 2.4), m="signal_post", bevel=0.01)
    # the ladder up the front
    for x in (-0.2, 0.2):
        cyl(0.02, 3.4, (x, -0.25, 1.9), m="signal_post", n=6)
    for i in range(11):
        cyl(0.012, 0.4, (0, -0.25, 0.5 + i * 0.3), (0, 90, 0), m="signal_post", n=5)
    box((0.7, 0.6, 0.04), (0, -0.15, 3.65), m="signal_post", bevel=0.005)
    with place(T((0, -0.1, 4.3))):
        box((0.42, 0.24, 1.1), (0, 0, 0), m="signal_head", bevel=0.03)
        box((0.6, 0.02, 1.3), (0, 0.13, 0), m="signal_head", bevel=0.01)          # the backboard
        box((0.6, 0.004, 1.3), (0, 0.142, 0), m="signal_white")
        for k, (z, lm) in enumerate(((0.33, "lens_red"), (0.0, "lens_amber"), (-0.33, "lens_green"))):
            cyl(0.1, 0.02, (0, -0.125, z), (90, 0, 0), m=lm, n=16)
            lathe([(0.12, 0.0), (0.12, 0.2), (0.115, 0.2), (0.115, 0.0)], (0, -0.12, z), (90, 0, 0), m="signal_head",
                  n=14, arc=(0, 180))
        plate = label_png("signal_no", [("AC 14", 1.0)], 200, 90, bg=(232, 228, 214), fg=(20, 20, 20), font="sans")
        material("sig_plate", "paint", base="#e4e0d2", chip=0.1, rust=-2, peel=-1)
        decal("sig_plate", plate, here((0, -0.123, -0.68), (90, 0, 0)), (0.2, 0.09))
        box((0.2, 0.005, 0.09), (0, -0.12, -0.68), m="sig_plate")
