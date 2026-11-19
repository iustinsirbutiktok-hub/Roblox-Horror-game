# Pictures for the mansion's decals, drawn with PIL: an oil portrait with its eyes scratched
# out, the manor at night, a worn Persian rug, a long-case clock dial, sheet music, mirror cracks.
import math, random
import kit


def _crackle(im, rnd, n=260, col=(30, 22, 14), alpha=70):
    """old varnish: craquelure lines over a painting"""
    from PIL import ImageDraw
    d = ImageDraw.Draw(im, "RGBA")
    W, H = im.size
    for _ in range(n):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        a = rnd.uniform(0, 2 * math.pi)
        pts = [(x, y)]
        for _ in range(rnd.randint(2, 5)):
            a += rnd.uniform(-1.0, 1.0)
            x += math.cos(a) * rnd.uniform(6, 22)
            y += math.sin(a) * rnd.uniform(6, 22)
            pts.append((x, y))
        d.line(pts, fill=col + (alpha,), width=1)


def _varnish(im, rnd, yellow=0.35, dark_edges=0.5):
    """yellowed varnish and darkened edges"""
    from PIL import Image
    W, H = im.size
    px = im.load()
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y][:3]
            dx, dy = (x / W - 0.5) * 2, (y / H - 0.5) * 2
            k = 1 - dark_edges * 0.5 * (dx * dx + dy * dy)
            r, g, b = r * k, g * k, b * k
            r, g, b = r + (200 - r) * yellow * 0.25, g + (160 - g) * yellow * 0.2, b * (1 - yellow * 0.35)
            n = rnd.gauss(0, 4)
            px[x, y] = (int(max(0, min(255, r + n))), int(max(0, min(255, g + n))), int(max(0, min(255, b + n))), 255)
    return im


def portrait_png(name="portrait", W=384, H=512, seed=3):
    """a Victorian lady in black, high collar and cameo, hair pulled back - her eyes scratched out"""
    from PIL import Image, ImageDraw, ImageFilter
    rnd = random.Random(seed)
    im = Image.new("RGBA", (W, H), (38, 34, 24, 255))
    d = ImageDraw.Draw(im)
    for r in range(260, 0, -6):                                       # a lighter glow behind the head
        c = int(38 + (260 - r) * 0.12)
        d.ellipse((W / 2 - r, H * 0.36 - r, W / 2 + r, H * 0.36 + r), fill=(c, c - 4, c - 14, 255))
    cx = W / 2
    # shoulders and dress
    d.polygon([(cx - 165, H), (cx - 150, H * 0.72), (cx - 70, H * 0.6), (cx + 70, H * 0.6), (cx + 150, H * 0.72),
               (cx + 165, H)], fill=(18, 16, 15, 255))
    d.polygon([(cx - 40, H * 0.6), (cx + 40, H * 0.6), (cx + 30, H * 0.5), (cx - 30, H * 0.5)], fill=(22, 20, 19, 255))
    for k in range(6):                                                # the buttons down the bodice
        d.ellipse((cx - 4, H * 0.66 + k * 26, cx + 4, H * 0.66 + k * 26 + 8), fill=(60, 56, 50, 255))
    d.ellipse((cx - 16, H * 0.55, cx + 16, H * 0.59), fill=(170, 140, 110, 255))          # cameo brooch
    # neck, face, hair
    d.rectangle((cx - 20, H * 0.42, cx + 20, H * 0.52), fill=(196, 168, 140, 255))
    d.polygon([(cx - 62, H * 0.24), (cx - 64, H * 0.4), (cx - 46, H * 0.44), (cx + 46, H * 0.44), (cx + 64, H * 0.4),
               (cx + 62, H * 0.24)], fill=(34, 26, 20, 255))             # hair falling behind
    d.ellipse((cx - 50, H * 0.19, cx + 50, H * 0.47), fill=(206, 178, 150, 255))
    d.chord((cx - 56, H * 0.15, cx + 56, H * 0.31), 180, 360, fill=(34, 26, 20, 255))    # parted, pulled back
    d.line([(cx, H * 0.15), (cx, H * 0.23)], fill=(70, 56, 44, 255), width=2)
    d.ellipse((cx - 30, H * 0.09, cx + 30, H * 0.17), fill=(34, 26, 20, 255))               # the bun
    for ex in (cx - 22, cx + 22):                                     # brows and dark sockets
        d.line([(ex - 14, H * 0.275), (ex + 12, H * 0.27)], fill=(60, 44, 34, 255), width=3)
        d.ellipse((ex - 12, H * 0.29, ex + 12, H * 0.315), fill=(120, 92, 76, 255))
    # shading on the face, nose and the thin unsmiling mouth
    d.ellipse((cx + 10, H * 0.24, cx + 58, H * 0.46), fill=(176, 146, 120, 255))
    d.line([(cx + 2, H * 0.31), (cx - 3, H * 0.37), (cx + 5, H * 0.375)], fill=(150, 118, 96, 255), width=3)
    d.line([(cx - 16, H * 0.415), (cx + 16, H * 0.413)], fill=(120, 70, 62, 255), width=3)
    im = im.filter(ImageFilter.GaussianBlur(2.2))
    d = ImageDraw.Draw(im)
    # the eyes - gouged out: pale scratches through the paint, right down to the canvas
    for ex in (cx - 24, cx + 24):
        for _ in range(26):
            x0 = ex + rnd.uniform(-16, 16)
            y0 = H * 0.3 + rnd.uniform(-12, 6)
            d.line([(x0, y0), (x0 + rnd.uniform(-14, 14), y0 + rnd.uniform(4, 22))],
                   fill=(rnd.randint(200, 235), rnd.randint(190, 220), rnd.randint(160, 190), 255), width=rnd.randint(1, 3))
    _crackle(im, rnd)
    im = _varnish(im, rnd, 0.4, 0.7)
    return kit._save(im, name)


def manor_png(name="manor", W=512, H=360, seed=4):
    """the house itself at night: towers and gables on the hill, dead trees, one lit window"""
    from PIL import Image, ImageDraw, ImageFilter
    rnd = random.Random(seed)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = ImageDraw.Draw(im)
    for y in range(H):                                                # sky
        t = y / H
        d.line([(0, y), (W, y)], fill=(int(30 + 30 * t), int(36 + 34 * t), int(46 + 20 * t), 255))
    d.ellipse((W * 0.72, H * 0.1, W * 0.82, H * 0.24), fill=(220, 214, 180, 255))         # moon
    for _ in range(9):                                                # clouds across it
        x, y = rnd.uniform(0, W), rnd.uniform(H * 0.05, H * 0.45)
        d.ellipse((x - 60, y - 8, x + 60, y + 8), fill=(70, 74, 82, 160))
    d.polygon([(0, H * 0.72), (W * 0.3, H * 0.6), (W * 0.6, H * 0.62), (W, H * 0.7), (W, H), (0, H)],
              fill=(18, 20, 16, 255))
    # the house
    hx, hy = W * 0.42, H * 0.62
    body = [(hx - 120, hy), (hx - 120, hy - 70), (hx - 90, hy - 110), (hx - 60, hy - 70), (hx - 20, hy - 70),
            (hx - 20, hy - 95), (hx + 30, hy - 140), (hx + 80, hy - 95), (hx + 80, hy - 70), (hx + 110, hy - 70),
            (hx + 110, hy)]
    d.polygon(body, fill=(12, 12, 14, 255))
    d.rectangle((hx - 150, hy - 150, hx - 125, hy), fill=(12, 12, 14, 255))                # the tower
    d.polygon([(hx - 156, hy - 150), (hx - 137, hy - 200), (hx - 119, hy - 150)], fill=(12, 12, 14, 255))
    for wx in range(-105, 100, 26):                                   # dark windows, one lit
        for wy in (-55, -30):
            lit = (wx, wy) == (-1, -55)
            d.rectangle((hx + wx, hy + wy, hx + wx + 9, hy + wy + 14),
                        fill=(230, 180, 90, 255) if lit else (26, 28, 32, 255))
    d.rectangle((hx - 145, hy - 120, hx - 136, hy - 104), fill=(230, 180, 90, 255))       # ... and in the tower
    for tx in (30, 70, 400, 460):                                     # dead trees
        base = H * 0.72 if tx < 200 else H * 0.7
        d.line([(tx, base), (tx + 4, base - 90)], fill=(8, 8, 8, 255), width=5)
        for k in range(6):
            y = base - 40 - k * 9
            s = 1 if k % 2 else -1
            d.line([(tx + 3, y), (tx + 3 + s * rnd.uniform(15, 35), y - rnd.uniform(10, 25))], fill=(8, 8, 8, 255), width=2)
    im = im.filter(ImageFilter.GaussianBlur(1.0))
    _crackle(im, rnd, 220)
    im = _varnish(im, rnd, 0.3, 0.6)
    return kit._save(im, name)


def rug_png(name="rug", W=512, H=720, seed=5):
    """a Persian rug: deep red field, navy and ivory borders, a stepped central medallion and
    corner pieces, little rosettes; worn pale through the middle, a dark stain"""
    from PIL import Image, ImageDraw, ImageFilter
    rnd = random.Random(seed)
    red, navy, ivory, gold, dark = (122, 28, 26), (30, 36, 70), (196, 180, 150), (176, 132, 60), (40, 18, 16)
    im = Image.new("RGBA", (W, H), red + (255,))
    d = ImageDraw.Draw(im)
    for k, (col, w) in enumerate(((navy, 40), (ivory, 8), (gold, 22), (ivory, 6), (dark, 4))):
        o = sum(x for _, x in ((navy, 40), (ivory, 8), (gold, 22), (ivory, 6), (dark, 4))[:k])
        d.rectangle((o, o, W - o, H - o), outline=col + (255,), width=w)
    for x in range(48, W - 48, 34):                                   # the border's repeating motif
        for y in (18, H - 18):
            d.polygon([(x, y - 9), (x + 9, y), (x, y + 9), (x - 9, y)], fill=gold + (255,))
    for y in range(48, H - 48, 34):
        for x in (18, W - 18):
            d.polygon([(x, y - 9), (x + 9, y), (x, y + 9), (x - 9, y)], fill=gold + (255,))
    cx, cy = W / 2, H / 2
    for k, (col, r) in enumerate(((navy, 170), (ivory, 140), (red, 118), (gold, 92), (navy, 62), (ivory, 30))):
        pts = []
        for i in range(16):                                           # stepped, many-pointed medallion
            a = 2 * math.pi * i / 16
            rr = r * (1.0 if i % 2 == 0 else 0.78) * (1.35 if i % 8 in (0, 4) else 1.0)
            pts.append((cx + math.cos(a) * rr * 0.8, cy + math.sin(a) * rr * 1.1))
        d.polygon(pts, fill=col + (255,))
    for sx, sy in ((0, 0), (1, 0), (0, 1), (1, 1)):                    # corner spandrels
        x0, y0 = 80 if sx == 0 else W - 80, 80 if sy == 0 else H - 80
        a0 = [0, 90, 270, 180][sx + 2 * sy]                         # (the quarter that points into the field)
        d.pieslice((x0 - 90, y0 - 90, x0 + 90, y0 + 90), a0, a0 + 90, fill=navy + (255,))
        d.pieslice((x0 - 60, y0 - 60, x0 + 60, y0 + 60), a0, a0 + 90, fill=gold + (255,))
    for _ in range(60):                                               # rosettes in the field
        x, y = rnd.uniform(90, W - 90), rnd.uniform(90, H - 90)
        if ((x - cx) / 140) ** 2 + ((y - cy) / 190) ** 2 < 1:
            continue
        r = rnd.uniform(5, 9)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(ivory if rnd.random() < 0.5 else gold) + (255,))
        d.ellipse((x - r / 2.5, y - r / 2.5, x + r / 2.5, y + r / 2.5), fill=navy + (255,))
    im = im.filter(ImageFilter.GaussianBlur(0.8))
    px = im.load()
    for y in range(H):                                                # worn through the middle, knotted texture
        for x in range(W):
            r, g, b, _ = px[x, y]
            wear = max(0.0, 1 - ((x - cx) / 210) ** 2 - ((y - cy * 1.1) / 260) ** 2) * 0.35
            n = rnd.gauss(0, 7) + (6 if (x // 2 + y // 2) % 2 else -6)
            r, g, b = r + (170 - r) * wear + n, g + (140 - g) * wear + n, b + (115 - b) * wear + n
            px[x, y] = (int(max(0, min(255, r))), int(max(0, min(255, g))), int(max(0, min(255, b))), 255)
    stain = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ds = ImageDraw.Draw(stain)
    for _ in range(7):                                                # a dark old stain, soft-edged
        x, y = W * 0.72 + rnd.uniform(-40, 40), H * 0.72 + rnd.uniform(-30, 30)
        r = rnd.uniform(20, 45)
        ds.ellipse((x - r * 1.3, y - r, x + r * 1.3, y + r), fill=(34, 14, 10, 60))
    stain = stain.filter(ImageFilter.GaussianBlur(8))
    im = Image.alpha_composite(im, stain)
    return kit._save(im, name)


def clock_png(name="clockface", S=512, seed=6):
    """a long-case clock dial: aged ivory, black Roman numerals, gilt corner spandrels,
    the hands stopped at 3:14"""
    from PIL import Image, ImageDraw
    rnd = random.Random(seed)
    im = Image.new("RGBA", (S, S), (150, 118, 60, 255))
    d = ImageDraw.Draw(im)
    c = S / 2
    for sx in (0, S):
        for sy in (0, S):
            for r in range(70, 10, -12):
                d.ellipse((sx - r, sy - r, sx + r, sy + r), outline=(110, 82, 36, 255), width=4)
    d.ellipse((c - S * 0.46, c - S * 0.46, c + S * 0.46, c + S * 0.46), fill=(222, 210, 180, 255),
              outline=(40, 34, 26, 255), width=4)
    d.ellipse((c - S * 0.42, c - S * 0.42, c + S * 0.42, c + S * 0.42), outline=(40, 34, 26, 255), width=2)
    for i in range(60):
        a = math.radians(i * 6 - 90)
        r0 = S * (0.39 if i % 5 else 0.37)
        d.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * S * 0.42, c + math.sin(a) * S * 0.42)],
               fill=(40, 34, 26, 255), width=2 if i % 5 else 4)
    f = kit._font("serif", int(S * 0.08))
    for i, t in enumerate(["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]):
        a = math.radians(i * 30 - 90)
        d.text((c + math.cos(a) * S * 0.3, c + math.sin(a) * S * 0.3), t, font=f, fill=(30, 26, 20, 255), anchor="mm")
    d.text((c, c + S * 0.14), "HOLLOWMERE", font=kit._font("serif", int(S * 0.035)), fill=(60, 50, 40, 255), anchor="mm")
    for ang, ln, w in ((-90 + (3 + 14 / 60) * 30, 0.2, 9), (-90 + 14 * 6, 0.33, 5)):           # stopped at 3:14
        a = math.radians(ang)
        d.line([(c, c), (c + math.cos(a) * S * ln, c + math.sin(a) * S * ln)], fill=(20, 18, 16, 255), width=w)
    d.ellipse((c - 9, c - 9, c + 9, c + 9), fill=(20, 18, 16, 255))
    px = im.load()
    for _ in range(4000):                                             # foxing and grime
        x, y = rnd.randrange(S), rnd.randrange(S)
        r, g, b, _ = px[x, y]
        k = rnd.uniform(0.75, 0.95)
        px[x, y] = (int(r * k), int(g * k), int(b * k * 0.9), 255)
    return kit._save(im, name)


def music_png(name="sheetmusic", W=360, H=480, seed=7):
    from PIL import Image, ImageDraw
    rnd = random.Random(seed)
    im = Image.new("RGBA", (W, H), (214, 200, 166, 255))
    d = ImageDraw.Draw(im)
    d.text((W / 2, 28), "Nocturne", font=kit._font("serif", 26), fill=(40, 32, 24, 255), anchor="mm")
    for s in range(8):
        y0 = 70 + s * 50
        for k in range(5):
            d.line([(24, y0 + k * 6), (W - 24, y0 + k * 6)], fill=(60, 50, 40, 255), width=1)
        x = 40
        while x < W - 40:
            y = y0 + rnd.randint(-2, 6) * 3
            d.ellipse((x - 4, y - 3, x + 4, y + 3), fill=(30, 24, 18, 255))
            d.line([(x + 4, y), (x + 4, y - 20)], fill=(30, 24, 18, 255), width=1)
            x += rnd.choice((14, 18, 22))
    return kit._save(im, name)


def cracks_png(name="mirrorcracks", S=512, seed=8):
    """a mirror struck once near the top: radiating cracks with a few rings"""
    from PIL import Image, ImageDraw
    rnd = random.Random(seed)
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = S * 0.58, S * 0.3
    for i in range(14):
        a = 2 * math.pi * i / 14 + rnd.uniform(-0.15, 0.15)
        x, y = cx, cy
        pts = [(x, y)]
        for k in range(8):
            a += rnd.uniform(-0.25, 0.25)
            step = rnd.uniform(20, 50)
            x, y = x + math.cos(a) * step, y + math.sin(a) * step
            pts.append((x, y))
        d.line(pts, fill=(235, 240, 240, 230), width=2)
    for r in (24, 55, 95):
        pts = [(cx + math.cos(2 * math.pi * k / 20) * r * rnd.uniform(0.8, 1.15),
                cy + math.sin(2 * math.pi * k / 20) * r * rnd.uniform(0.8, 1.15)) for k in range(21)]
        d.line(pts, fill=(235, 240, 240, 200), width=1)
    return kit._save(im, name)


def _figure(d, cx, top, h, coat, face=(206, 178, 150), hair=(36, 28, 22), dress=False, beard=False, eyes=(40, 30, 24),
            child=False):
    """a stiff Victorian sitter, front on: head, shoulders, coat or dress down to the frame"""
    hr = h * (0.1 if not child else 0.12)
    hy = top + hr
    sw = h * (0.24 if not child else 0.2)
    if dress:
        d.polygon([(cx - sw, top + h * 0.27), (cx + sw, top + h * 0.27), (cx + sw * 1.8, top + h * 1.2),
                   (cx - sw * 1.8, top + h * 1.2)], fill=coat)
    else:
        d.polygon([(cx - sw, top + h * 0.27), (cx + sw, top + h * 0.27), (cx + sw * 1.05, top + h * 1.2),
                   (cx - sw * 1.05, top + h * 1.2)], fill=coat)
        d.polygon([(cx - sw * 0.25, top + h * 0.27), (cx + sw * 0.25, top + h * 0.27), (cx, top + h * 0.5)],
                  fill=(200, 196, 186))                                     # the white shirt front
    d.rectangle((cx - hr * 0.4, hy + hr * 0.7, cx + hr * 0.4, top + h * 0.3), fill=face)
    d.ellipse((cx - hr * 0.82, hy - hr, cx + hr * 0.82, hy + hr), fill=face)
    d.chord((cx - hr * 0.9, hy - hr * 1.15, cx + hr * 0.9, hy + hr * 0.3), 180, 360, fill=hair)
    if beard:
        d.chord((cx - hr * 0.8, hy - hr * 0.2, cx + hr * 0.8, hy + hr * 1.15), 0, 180, fill=hair)
    for ex in (cx - hr * 0.32, cx + hr * 0.32):
        d.ellipse((ex - hr * 0.13, hy - hr * 0.15, ex + hr * 0.13, hy + hr * 0.05), fill=eyes)
    return hy, hr


def family_png(name="family", W=640, H=440, seed=9):
    """the family: father standing, mother seated, a boy, and the little girl in white with her doll.
    Someone has burnt the father's face out, and the girl's eyes were painted over black - later."""
    from PIL import Image, ImageDraw, ImageFilter
    rnd = random.Random(seed)
    im = Image.new("RGBA", (W, H), (34, 30, 22, 255))
    d = ImageDraw.Draw(im)
    for r in range(320, 0, -8):                                       # a dim drawing-room glow behind them
        c = int(34 + (320 - r) * 0.07)
        d.ellipse((W * 0.45 - r * 1.4, H * 0.42 - r, W * 0.45 + r * 1.4, H * 0.42 + r), fill=(c, c - 3, c - 12, 255))
    d.rectangle((0, H * 0.82, W, H), fill=(40, 28, 20, 255))                              # the carpet
    d.rectangle((W * 0.08, H * 0.1, W * 0.18, H * 0.82), fill=(52, 20, 18, 255))           # a curtain
    fy, fr = _figure(d, W * 0.36, H * 0.1, H * 0.75, (20, 18, 18, 255), beard=True)     # father, standing
    d.rectangle((W * 0.42, H * 0.52, W * 0.62, H * 0.6), fill=(60, 34, 24, 255))         # mother's chair back
    _figure(d, W * 0.52, H * 0.3, H * 0.55, (28, 22, 30, 255), dress=True)              # mother, seated
    _figure(d, W * 0.7, H * 0.4, H * 0.45, (30, 30, 34, 255), child=True)               # the boy
    gy, gr = _figure(d, W * 0.84, H * 0.5, H * 0.38, (214, 208, 196, 255), hair=(150, 110, 60, 255), dress=True,
                     child=True)                                                          # the girl in white
    d.ellipse((W * 0.86, H * 0.74, W * 0.9, H * 0.79), fill=(214, 186, 160, 255))        # her doll's head
    d.polygon([(W * 0.855, H * 0.79), (W * 0.905, H * 0.79), (W * 0.91, H * 0.86), (W * 0.85, H * 0.86)],
              fill=(120, 40, 40, 255))
    im = im.filter(ImageFilter.GaussianBlur(1.6))
    d = ImageDraw.Draw(im, "RGBA")
    # the girl's eyes painted over: thick black, a little drip
    for ex in (W * 0.84 - gr * 0.32, W * 0.84 + gr * 0.32):
        d.ellipse((ex - gr * 0.22, gy - gr * 0.25, ex + gr * 0.22, gy + gr * 0.12), fill=(6, 6, 6, 255))
        d.line([(ex, gy + gr * 0.1), (ex + 1, gy + gr * 0.6)], fill=(6, 6, 6, 255), width=2)
    # the father's face burnt out: a black-edged hole with scorched brown round it
    cx, cy = W * 0.36, fy
    for r, col in ((fr * 1.9, (70, 42, 20, 120)), (fr * 1.5, (40, 24, 12, 200)), (fr * 1.15, (12, 8, 6, 255))):
        pts = [(cx + math.cos(a) * r * rnd.uniform(0.75, 1.15), cy + math.sin(a) * r * rnd.uniform(0.75, 1.15))
               for a in [2 * math.pi * i / 18 for i in range(18)]]
        d.polygon(pts, fill=col)
    _crackle(im, rnd, 300)
    im = _varnish(im, rnd, 0.35, 0.7)
    return kit._save(im, name)


def vanitas_png(name="vanitas", W=420, H=520, seed=10):
    """a vanitas still life: a skull on a book by a guttered candle, an hourglass run out, a wilted
    flower, all in one candle's warm light out of the dark"""
    from PIL import Image, ImageDraw, ImageFilter
    rnd = random.Random(seed)
    im = Image.new("RGBA", (W, H), (14, 11, 8, 255))
    d = ImageDraw.Draw(im)
    lx, ly = W * 0.3, H * 0.36                                         # the candle flame: the only light
    for r in range(300, 0, -6):
        c = int(14 + (300 - r) * 0.13)
        d.ellipse((lx - r, ly - r, lx + r, ly + r), fill=(c, int(c * 0.8), int(c * 0.55), 255))
    d.rectangle((0, H * 0.7, W, H), fill=(52, 30, 18, 255))                               # the table
    d.line([(0, H * 0.7), (W, H * 0.7)], fill=(90, 56, 30, 255), width=3)
    # the book under the skull
    d.polygon([(W * 0.4, H * 0.7), (W * 0.92, H * 0.7), (W * 0.9, H * 0.64), (W * 0.42, H * 0.64)],
              fill=(70, 30, 22, 255))
    d.polygon([(W * 0.42, H * 0.64), (W * 0.9, H * 0.64), (W * 0.88, H * 0.62), (W * 0.44, H * 0.62)],
              fill=(196, 180, 140, 255))
    # the skull: cranium, cheek, jaw, sockets, nose, teeth
    sx, sy, sr = W * 0.64, H * 0.47, W * 0.15
    bone, shade_ = (206, 192, 160, 255), (120, 98, 70, 255)
    d.ellipse((sx - sr, sy - sr, sx + sr, sy + sr * 0.85), fill=bone)
    d.polygon([(sx - sr * 0.75, sy + sr * 0.3), (sx + sr * 0.75, sy + sr * 0.3), (sx + sr * 0.55, sy + sr * 1.05),
               (sx - sr * 0.55, sy + sr * 1.05)], fill=bone)
    d.ellipse((sx + sr * 0.2, sy - sr * 0.7, sx + sr * 0.95, sy + sr * 0.6), fill=shade_)                 # shadow side
    for ex in (sx - sr * 0.38, sx + sr * 0.32):
        d.ellipse((ex - sr * 0.26, sy - sr * 0.05, ex + sr * 0.26, sy + sr * 0.42), fill=(10, 8, 6, 255))
    d.polygon([(sx - sr * 0.04, sy + sr * 0.48), (sx - sr * 0.14, sy + sr * 0.72), (sx + sr * 0.06, sy + sr * 0.72)],
              fill=(10, 8, 6, 255))
    for k in range(7):
        tx = sx - sr * 0.42 + k * sr * 0.14
        d.rectangle((tx, sy + sr * 0.82, tx + sr * 0.1, sy + sr * 0.98), fill=(226, 214, 184, 255))
    d.line([(sx - sr * 0.5, sy + sr * 0.99), (sx + sr * 0.5, sy + sr * 0.99)], fill=(30, 22, 14, 255), width=2)
    # the candle, guttered, in its holder; a thread of smoke
    d.ellipse((lx - 34, H * 0.68, lx + 34, H * 0.72), fill=(150, 116, 50, 255))
    d.rectangle((lx - 12, H * 0.44, lx + 12, H * 0.69), fill=(222, 208, 176, 255))
    for k in range(4):
        x = lx - 12 + k * 7
        d.line([(x, H * 0.44), (x + 1, H * 0.44 + rnd.uniform(20, 60))], fill=(236, 226, 200, 255), width=4)
    d.ellipse((lx - 6, ly - 12, lx + 6, ly + 14), fill=(255, 236, 170, 255))
    d.line([(lx, ly - 14), (lx + 6, ly - 60), (lx - 4, ly - 110), (lx + 10, ly - 170)], fill=(70, 66, 60, 120), width=2)
    # the hourglass, run out
    hx = W * 0.13
    d.rectangle((hx - 30, H * 0.5, hx + 30, H * 0.52), fill=(90, 60, 34, 255))
    d.rectangle((hx - 30, H * 0.68, hx + 30, H * 0.7), fill=(90, 60, 34, 255))
    d.polygon([(hx - 22, H * 0.52), (hx + 22, H * 0.52), (hx + 3, H * 0.6), (hx + 22, H * 0.68), (hx - 22, H * 0.68),
               (hx - 3, H * 0.6)], fill=(110, 118, 110, 180))
    d.polygon([(hx - 20, H * 0.68), (hx + 20, H * 0.68), (hx, H * 0.64)], fill=(190, 160, 110, 255))
    # a wilted flower drooping over the table edge
    d.line([(W * 0.86, H * 0.7), (W * 0.9, H * 0.76), (W * 0.88, H * 0.84)], fill=(70, 66, 30, 255), width=3)
    d.ellipse((W * 0.85, H * 0.83, W * 0.91, H * 0.88), fill=(110, 30, 34, 255))
    im = im.filter(ImageFilter.GaussianBlur(1.3))
    _crackle(im, rnd, 240)
    im = _varnish(im, rnd, 0.3, 0.8)
    return kit._save(im, name)
