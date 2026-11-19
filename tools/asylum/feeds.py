# CCTV feed pictures for the surveillance monitors: little night-vision camera views drawn
# with PIL (corridors, the tank room, a padded cell, the gate...), with noise, scanlines,
# a vignette and the camera's caption. All twelve also go into one 4 x 3 atlas
# (SurveillanceFeeds.png) for Studio, where SetupLabGlow can show them glowing.
import math, os, random
import kit

TW, TH = 256, 192                  # one feed in the atlas
S = 2                              # drawn at twice the size, then shrunk (softer lines)

FEEDS = [
    ("corridor", "CAM 01", "SECTOR C - EAST CORRIDOR"),
    ("tanks", "CAM 02", "CONTAINMENT LAB 1"),
    ("figure", "CAM 03", "SECTOR C - WEST CORRIDOR"),
    ("cell", "CAM 04", "ISOLATION 6"),
    ("static", "CAM 05", "SUBLEVEL 2 - SERVICE"),
    ("lab", "CAM 06", "RESEARCH LAB B"),
    ("gate", "CAM 07", "NORTH GATE"),
    ("nosignal", "CAM 08", ""),
    ("stairs", "CAM 09", "STAIRWELL B"),
    ("alarm", "", ""),
    ("blastdoor", "CAM 11", "BLAST DOOR 2"),
    ("dark", "CAM 12", "LOWER LEVEL - CORRIDOR"),
]


def _persp(W, H, vp, scale):
    def P(x, y, d):
        return (vp[0] + x * scale / d, vp[1] + y * scale / d)
    return P


def _corridor(d, W, H, rnd, lights=(1, 1, 1, 1), far=6.0, vpx=0.0, doors=True, figure=False, dark=False):
    vp = (W * (0.5 + vpx), H * 0.47)
    P = _persp(W, H, vp, W * 0.55)
    wall, floor, ceil = (70, 52, 34) if not dark else (22, 16, 10)
    # floor, ceiling, walls as big quads from the near plane to the far end
    near, fr = 0.9, far
    for poly, col in (([P(-1, .75, near), P(1, .75, near), P(1, .75, fr), P(-1, .75, fr)], floor + 25),
                      ([P(-1, -.75, near), P(1, -.75, near), P(1, -.75, fr), P(-1, -.75, fr)], ceil),
                      ([P(-1, -.75, near), P(-1, .75, near), P(-1, .75, fr), P(-1, -.75, fr)], wall),
                      ([P(1, -.75, near), P(1, .75, near), P(1, .75, fr), P(1, -.75, fr)], wall + 6)):
        d.polygon(poly, fill=col)
    # the far end, lit or black
    d.polygon([P(-1, -.75, fr), P(1, -.75, fr), P(1, .75, fr), P(-1, .75, fr)], fill=(wall + 40) if not dark else 8)
    # floor tile lines and the skirting
    for k in range(1, 12):
        z = near + (fr - near) * (k / 12) ** 1.4
        d.line([P(-1, .75, z), P(1, .75, z)], fill=floor + 10, width=S)
    for x in (-1, 1):
        d.line([P(x, .7, near), P(x, .7, fr)], fill=wall - 25, width=S)
    # doors along the walls
    if doors:
        for x, z in ((-1, 1.8), (1, 2.6), (-1, 3.8), (1, 4.6)):
            d.polygon([P(x, .75, z), P(x, -.2, z), P(x, -.2, z + 0.45), P(x, .75, z + 0.45)], fill=wall - 30)
            d.line([P(x, .2, z + 0.38), P(x, .2, z + 0.42)], fill=wall + 50, width=S)
    # ceiling lights (some dead)
    for i, z in enumerate((1.4, 2.6, 3.8, 5.0)):
        if lights[i % len(lights)]:
            d.polygon([P(-.18, -.74, z), P(.18, -.74, z), P(.18, -.74, z + .35), P(-.18, -.74, z + .35)], fill=235)
            # light pooled on the floor under it
            d.polygon([P(-.5, .74, z - .1), P(.5, .74, z - .1), P(.5, .74, z + .5), P(-.5, .74, z + .5)],
                      fill=floor + 55)
        else:
            d.polygon([P(-.18, -.74, z), P(.18, -.74, z), P(.18, -.74, z + .35), P(-.18, -.74, z + .35)], fill=ceil + 15)
    if figure:
        # something standing at the far end: too tall, too thin, arms too long
        z = fr - 1.6
        fx, top, bot = 0.12, -.38, .75
        cx, cy = P(fx, 0, z)
        h = P(fx, bot, z)[1] - P(fx, top, z)[1]
        w = h * 0.16
        hy = P(fx, top, z)[1]
        d.ellipse((cx - w * 0.36, hy - w * 0.1, cx + w * 0.36, hy + w * 0.75), fill=6)
        d.polygon([(cx - w * 0.5, hy + w * 0.8), (cx + w * 0.5, hy + w * 0.8), (cx + w * 0.3, hy + h * 0.62),
                   (cx + w * 0.2, P(fx, bot, z)[1]), (cx + w * 0.05, P(fx, bot, z)[1]), (cx, hy + h * 0.62),
                   (cx - w * 0.05, P(fx, bot, z)[1]), (cx - w * 0.2, P(fx, bot, z)[1]), (cx - w * 0.3, hy + h * 0.62)],
                  fill=6)
        for s in (-1, 1):
            d.line([(cx + s * w * 0.48, hy + w * 0.9), (cx + s * w * 0.62, hy + h * 0.55),
                    (cx + s * w * 0.6, hy + h * 0.78)], fill=6, width=max(S, int(w * 0.18)))
    return vp


def _draw(scene, rnd):
    from PIL import Image, ImageDraw
    W, H = TW * S, TH * S
    im = Image.new("L", (W, H), 20)
    d = ImageDraw.Draw(im)
    if scene == "corridor":
        _corridor(d, W, H, rnd, (1, 1, 0, 1), vpx=-0.06)
    elif scene == "figure":
        _corridor(d, W, H, rnd, (1, 0, 1, 0), vpx=0.05, figure=True)
    elif scene == "dark":
        _corridor(d, W, H, rnd, (0, 0, 1, 0), dark=True, doors=False)
    elif scene == "tanks":
        vp = (W * 0.42, H * 0.42)
        P = _persp(W, H, vp, W * 0.5)
        d.rectangle((0, 0, W, H), fill=40)
        d.polygon([P(-3, .8, 1), P(3, .8, 1), P(3, .8, 7), P(-3, .8, 7)], fill=62)
        d.polygon([P(-3, -1, 7), P(3, -1, 7), P(3, .8, 7), P(-3, .8, 7)], fill=50)
        for x, z, occupied in ((-1.6, 4.5, False), (-0.2, 5.0, True), (1.2, 4.2, False), (2.4, 3.2, False)):
            (x0, y0), (x1, y1) = P(x - .35, -.6, z), P(x + .35, .8, z)
            d.rectangle((x0, y0 - (x1 - x0) * 0.25, x1, y0), fill=30)
            d.rectangle((x0, y0, x1, y1 - (x1 - x0) * 0.2), fill=200)
            d.rectangle((x0, y1 - (x1 - x0) * 0.2, x1, y1), fill=35)
            if occupied:
                cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
                r = (x1 - x0) * 0.22
                d.ellipse((cx - r, cy - r * 2.2, cx + r, cy - r * 0.4), fill=70)
                d.ellipse((cx - r * 1.4, cy - r * 0.6, cx + r * 1.3, cy + r * 1.8), fill=70)
    elif scene == "lab":
        vp = (W * 0.55, H * 0.4)
        P = _persp(W, H, vp, W * 0.5)
        d.rectangle((0, 0, W, H), fill=48)
        d.polygon([P(-3, .8, 1), P(3, .8, 1), P(3, .8, 7), P(-3, .8, 7)], fill=70)
        d.polygon([P(-3, -1, 7), P(3, -1, 7), P(3, .8, 7), P(-3, .8, 7)], fill=58)
        for x in (-1.6, 0.4):
            for z in (2.0, 3.6, 5.2):
                d.polygon([P(x, .25, z), P(x + 1.2, .25, z), P(x + 1.2, .25, z + .6), P(x, .25, z + .6)], fill=120)
                d.polygon([P(x, .25, z), P(x + 1.2, .25, z), P(x + 1.2, .8, z), P(x, .8, z)], fill=36)
        # a chair knocked over, papers on the floor
        for i in range(14):
            x, z = rnd.uniform(-2, 2), rnd.uniform(1.4, 5)
            d.polygon([P(x, .79, z), P(x + .2, .79, z), P(x + .2, .79, z + .25), P(x, .79, z + .25)], fill=170)
    elif scene == "cell":
        # from the camera high in the corner: padded walls, a figure crouched in the far corner
        d.rectangle((0, 0, W, H), fill=95)
        d.polygon([(0, H * 0.55), (W * 0.62, H * 0.3), (W, H * 0.55), (W, H), (0, H)], fill=120)
        d.polygon([(W * 0.62, 0), (W * 0.62, H * 0.3), (0, H * 0.55), (0, 0)], fill=105)
        d.polygon([(W * 0.62, 0), (W * 0.62, H * 0.3), (W, H * 0.55), (W, 0)], fill=88)
        for k in range(1, 9):
            d.line([(W * 0.62 * k / 9, 0), (W * 0.62 * k / 9, H * (0.55 - 0.25 * k / 9))], fill=80, width=S)
            d.line([(W * (0.62 + 0.38 * k / 9), 0), (W * (0.62 + 0.38 * k / 9), H * (0.3 + 0.25 * k / 9))], fill=70,
                   width=S)
        cx, cy = W * 0.6, H * 0.36
        d.ellipse((cx - 14 * S, cy - 4 * S, cx + 12 * S, cy + 26 * S), fill=30)
        d.ellipse((cx - 7 * S, cy - 14 * S, cx + 5 * S, cy - 2 * S), fill=24)
    elif scene == "gate":
        d.rectangle((0, 0, W, H), fill=14)
        for x in range(0, W, 9 * S):                                   # trees beyond
            h = rnd.uniform(0.15, 0.3) * H
            d.polygon([(x, H * 0.4), (x + 5 * S, H * 0.4 - h), (x + 10 * S, H * 0.4)], fill=8)
        d.polygon([(0, H * 0.62), (W, H * 0.55), (W, H), (0, H)], fill=34)
        # floodlight on its pole, and its cone
        d.polygon([(W * 0.78, H * 0.14), (W * 0.45, H), (W, H)], fill=60)
        d.line([(W * 0.79, H * 0.14), (W * 0.79, H * 0.62)], fill=40, width=2 * S)
        d.ellipse((W * 0.76, H * 0.1, W * 0.81, H * 0.15), fill=250)
        for k in range(0, 40):
            x = k * W / 40
            d.line([(x, H * 0.36 + k * 0.4), (x, H * 0.62 - k * 0.15)], fill=110, width=S)
        d.line([(0, H * 0.36), (W, H * 0.52)], fill=150, width=2 * S)
        d.line([(0, H * 0.62), (W, H * 0.56)], fill=90, width=2 * S)
    elif scene == "stairs":
        d.rectangle((0, 0, W, H), fill=50)
        for k in range(12):
            y0 = H * (0.95 - k * 0.07)
            x0 = W * (0.1 + k * 0.05)
            d.rectangle((x0, y0 - H * 0.07, W * 0.85, y0), fill=80 + (k % 2) * 25)
        d.line([(W * 0.08, H * 0.75), (W * 0.65, H * 0.0)], fill=170, width=3 * S)
        d.rectangle((W * 0.86, 0, W, H), fill=35)
    elif scene == "blastdoor":
        d.rectangle((0, 0, W, H), fill=56)
        d.rectangle((W * 0.18, H * 0.12, W * 0.82, H * 0.95), fill=96)
        d.rectangle((W * 0.18, H * 0.12, W * 0.43, H * 0.95), fill=16)               # opened a crack: black
        for k in range(9):
            y = H * (0.15 + k * 0.09)
            d.polygon([(W * 0.43, y), (W * 0.82, y), (W * 0.82, y + H * 0.03), (W * 0.43, y + H * 0.03)], fill=70)
        d.rectangle((W * 0.0, H * 0.9, W, H), fill=40)
        d.polygon([(W * 0.2, H * 0.95), (W * 0.42, H * 0.95), (W * 0.48, H), (W * 0.1, H)], fill=30)   # a smear out of it
    elif scene == "static":
        px = im.load()
        for y in range(H):
            off = rnd.randint(0, 60)
            for x in range(W):
                px[x, y] = min(255, rnd.randint(0, 200) + off)
    elif scene == "nosignal":
        return None
    elif scene == "alarm":
        return None
    return im


def feed_png(i, seed=1):
    """the i-th feed (0..11) as RGB: tinted, noisy, scanlined, vignetted, captioned"""
    from PIL import Image, ImageDraw, ImageFilter
    scene, cam, place = FEEDS[i]
    rnd = random.Random(seed * 31 + i)
    W, H = TW * S, TH * S
    im = _draw(scene, rnd)
    if scene == "nosignal":
        rgb = Image.new("RGB", (W, H), (24, 40, 150))
        d = ImageDraw.Draw(rgb)
        f = kit._font("mono", 26 * S)
        d.text((W / 2, H / 2), "NO SIGNAL", font=f, fill=(225, 230, 245), anchor="mm")
        d.text((14 * S, 12 * S), cam, font=kit._font("mono", 12 * S), fill=(225, 230, 245))
    elif scene == "alarm":
        rgb = Image.new("RGB", (W, H), (120, 8, 6))
        d = ImageDraw.Draw(rgb)
        d.rectangle((6 * S, 6 * S, W - 6 * S, H - 6 * S), outline=(255, 210, 200), width=3 * S)
        f = kit._font("cond", 25 * S)
        d.text((W / 2, H * 0.36), "CONTAINMENT", font=f, fill=(255, 225, 215), anchor="mm")
        d.text((W / 2, H * 0.6), "BREACH", font=f, fill=(255, 225, 215), anchor="mm")
        d.text((W / 2, H * 0.84), "SECTOR C  -  LAB 1", font=kit._font("mono", 11 * S), fill=(255, 200, 190), anchor="mm")
    else:
        im = im.filter(ImageFilter.GaussianBlur(S * 0.7))
        px = im.load()
        for y in range(H):
            line = 0.82 if (y // S) % 2 else 1.0                       # scanlines
            for x in range(W):
                dx, dy = (x / W - 0.5) * 2, (y / H - 0.5) * 2
                v = px[x, y] * line * (1 - 0.38 * (dx * dx + dy * dy))  # vignette
                v += rnd.gauss(0, 9)
                px[x, y] = max(0, min(255, int(v)))
        tint = (0.78, 1.0, 0.84)
        rgb = Image.merge("RGB", [im.point(lambda v, t=t: int(v * t)) for t in tint])
        d = ImageDraw.Draw(rgb)
        fm = kit._font("mono", 11 * S)
        d.text((8 * S, 6 * S), cam, font=fm, fill=(230, 240, 230))
        d.text((W - 8 * S, 6 * S), "REC", font=fm, fill=(230, 240, 230), anchor="ra")
        d.ellipse((W - 44 * S, 8 * S, W - 36 * S, 16 * S), fill=(220, 30, 20))
        t = "11/19/87  03:%02d:%02d" % (14 + i % 3, (17 * i + 9) % 60)
        d.text((8 * S, H - 22 * S), place, font=kit._font("mono", 10 * S), fill=(220, 232, 220))
        d.text((8 * S, H - 11 * S), t, font=kit._font("mono", 10 * S), fill=(220, 232, 220))
    return rgb.resize((TW, TH), Image.LANCZOS)


def build_feeds():
    """writes each feed (for the decals) and the atlas; returns the decal paths"""
    from PIL import Image
    atlas = Image.new("RGB", (TW * 4, TH * 3))
    paths = []
    for i in range(len(FEEDS)):
        im = feed_png(i)
        atlas.paste(im, ((i % 4) * TW, (i // 4) * TH))
        paths.append(kit._save(im.convert("RGBA"), "feed_%02d" % (i + 1)))
    atlas_path = os.path.join(kit.WORK, "SurveillanceFeeds.png")
    atlas.save(atlas_path)
    return paths
