# Hollowmere House: a Victorian mansion, abandoned and dusty. Dark carved mahogany and walnut,
# faded velvet, tarnished gilt and brass, foxed mirrors - everything under a layer of dust.
# Meshes kept apart for Studio (tools/SetupMansion.lua): "Glass..." and "Crystal..." become glass,
# "Flame..." become candle flames with flickering lights; doors that open are their own meshes
# ("DoorLeft"/"DoorRight") with their pivots on the hinges; a few loose things (a stool) too.
from kit import *  # noqa
import kit
import mansion_art as art


# ---------------------------------------------------------------- materials

def vwood(g, dusty=0.5, **kw):
    """the kit's old varnished wood, with the dust of years settled on everything facing up"""
    c, rough, metal, h = kit.wood(g, **kw)
    c, dm = dust(g, c, dusty, "#8b857a")
    return c, g.clamp(g.add(rough, g.mul(dm, 0.5))), metal, h


def _hexshade(hexs, f):
    r, gg, b = (int(hexs[i:i + 2], 16) for i in (1, 3, 5))
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(v * f))) for v in (r, gg, b))


def cloth(g, base="#5c1a1c", stain=0.12, moldy=0.05, dirt=0.35, dusty=0.25, fade=0.15):
    """velvet, linen, damask: sun-faded on top, old water marks in a darker shade of itself, dusty"""
    c, rough, metal, h = kit.fabric(g, base, stain=-2.0, moldy=moldy, dirt=dirt)
    if stain > 0:
        c, _ = stains(g, c, stain * 2.5, _hexshade(base, 0.68), _hexshade(base, 0.5), 2.4)
    c = g.mix(c, shade(rgb(base), 1.45), g.mul(g.ms(g.up, 0.3, 0.9), fade))
    c, dm = dust(g, c, dusty, "#9a948a")
    return c, rough, metal, h


def gilt(g, dusty=0.5):
    """tarnished gilding: dark in the recesses, worn through to the pale gesso on the edges"""
    c = g.mix(rgb("#6e5020"), rgb("#b8913f"), g.ms(g.noise(5, 5), 0.3, 0.75))
    c = g.mix(c, rgb("#3a2a14"), g.mul(g.ms(g.cav, 0.1, 0.5), 0.8))
    c = g.mix(c, rgb("#b0a080"), g.mul(g.ms(g.add(g.edge, g.mul(g.noise(9), 0.3)), 0.78, 0.95), 0.5))
    c, dm = grime(g, c, 0.4)
    c, du = dust(g, c, dusty)
    worn = g.clamp(g.add(dm, du))
    return c, g.lerp(0.35, 0.85, worn), g.sub(0.8, worn), 0.0


def mirror(g):
    """old silvered glass: grey, the silver lifting in black spots, worse round the edges"""
    c = g.mix(rgb("#2f3638"), rgb("#58625f"), g.ms(g.noise(2, 4), 0.3, 0.7))
    fox = g.ms(g.add(g.noise(5, 6, 0.6), g.mul(g.edge, 0.5)), 0.7, 0.8)
    c = g.mix(c, rgb("#151613"), g.mul(fox, 0.8))
    c, du = dust(g, c, 0.35)
    return c, g.lerp(0.08, 0.7, g.clamp(g.add(fox, du))), 0.6, 0.0


def flamepaint(g, base="#ffb347"):
    return rgb(base), 0.5, 0.0, 0.0


for _k, _f in (("vwood", vwood), ("cloth", cloth), ("gilt", gilt), ("mirror", mirror), ("flamepaint", flamepaint)):
    kit.KINDS[_k] = _f


def mansion_materials():
    for key, base, dark, axis in (("mahogany_v", "#4a2818", "#1e0e06", "Z"), ("mahogany_h", "#4a2818", "#1e0e06", "X"),
                                  ("mahogany_y", "#4a2818", "#1e0e06", "Y"), ("walnut_v", "#5c3c22", "#2a170b", "Z"),
                                  ("walnut_h", "#5c3c22", "#2a170b", "X"), ("walnut_y", "#5c3c22", "#2a170b", "Y")):
        material(key, "vwood", base=base, dark=dark, axis=axis, grain=6.0, wear=0.45, water=0.25, varnish=0.8,
                 dusty=0.38)
    material("velvet_red", "cloth", base="#5c1a1c")
    material("velvet_green", "cloth", base="#24402e")
    material("drape", "cloth", base="#3e1214", moldy=0.08, fade=0.25)
    material("coverlet", "cloth", base="#3a4632", stain=0.15, dusty=0.35)
    material("linen", "cloth", base="#d2cab4", stain=0.3, dusty=0.35, fade=0.0)
    material("ticking", "cloth", base="#b8ad94", stain=0.35, fade=0.0)
    material("dustsheet", "cloth", base="#cdc6b2", stain=0.14, dusty=0.45, fade=0.0)
    material("gilt", "gilt")
    material("ivory", "porcelain", base="#d9cfb2", craze=0.4, stain=0.5, chips=0.2, rusty=0.0)
    material("ebony", "bakelite", base="#0f0d0c")
    material("wax", "porcelain", base="#ddd5c0", craze=0.0, stain=0.35, chips=0.0, rusty=0.0)
    material("china", "porcelain", base="#e2ddd0", craze=0.5, stain=0.4, chips=0.3, rusty=0.0)
    material("china_blue", "paint", base="#2c4a7a", chip=0.1, rust=-3.0, peel=-1.0, dirt=0.3)
    material("silver", "chrome", base="#8c8a84", rust=-1.5, dull=0.85)
    material("mirror", "mirror")
    material("crystal", "glass", base="#c8d0d0", frost=0.1, dirt=0.4)
    material("old_glass", "glass", base="#8a9490", frost=0.15, dirt=0.6)
    material("flame", "flamepaint")
    material("wick", "bakelite", base="#141210")
    for name, col in (("book_red", "#5a1e18"), ("book_green", "#24382a"), ("book_brown", "#4a3020"),
                      ("book_blue", "#202c44"), ("book_black", "#1a1716")):
        material(name, "leather", base=col, wear=0.6)


BOOKS = ("book_red", "book_green", "book_brown", "book_blue", "book_black")


# ---------------------------------------------------------------- shapes

def smooth_path(pts, n=6):
    """a Catmull-Rom curve through the points"""
    P = [V(p) for p in pts]
    out = []
    for i in range(len(P) - 1):
        p0 = P[i - 1] if i > 0 else P[i]
        p1, p2 = P[i], P[i + 1]
        p3 = P[i + 2] if i + 2 < len(P) else P[i + 1]
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    out.append(P[-1])
    return out


def tapered(pts, radii, m, n=8, k=6):
    """a smooth tube through the points, its thickness going through `radii` (one per point)"""
    P = smooth_path(pts, k)
    R = []
    for i in range(len(radii) - 1):
        for j in range(k):
            R.append(radii[i] + (radii[i + 1] - radii[i]) * j / k)
    R.append(radii[-1])
    return sweep(P, radii[0], m, n, radii=R)


def cabriole(top, h, out, r, m, toward=(0, -1)):
    """a cabriole leg: out at the knee, in at the ankle, a little club foot; `toward` is the way it kicks"""
    tx, ty = toward
    x, y, z = top
    pts = [(x, y, z), (x + tx * out * 0.55, y + ty * out * 0.55, z - h * 0.22), (x - tx * out * 0.1, y - ty * out * 0.1, z - h * 0.75),
           (x + tx * out * 0.25, y + ty * out * 0.25, z - h + 0.02)]
    tapered(pts, (r, r * 1.15, r * 0.55, r * 0.8), m, 8, 5)
    cyl(r * 1.05, 0.02, (x + tx * out * 0.28, y + ty * out * 0.28, z - h + 0.01), m=m, n=8)


def leg_profile(h, r):
    """a turned Victorian leg, bottom to top: bun, taper, vase, rings, square-ish top"""
    return [(0, 0), (r * 0.75, 0), (r * 1.05, 0.015), (r * 0.9, 0.035), (r * 0.6, 0.07), (r * 0.7, h * 0.3), (r * 1.0, h * 0.42),
            (r * 1.06, h * 0.47), (r * 0.72, h * 0.56), (r * 0.6, h * 0.64), (r * 0.95, h * 0.7), (r * 0.7, h * 0.74),
            (r * 0.85, h * 0.8), (r * 0.9, h), (0, h)]


def run_x(profile, length, at, m):
    """a moulding along X: profile = [(y, z), ...] (y < 0 sticks out to the front)"""
    slab(profile, length, at, (90, 0, 90), m=m)


def run_y(profile, length, at, m):
    """a moulding along Y: profile = [(x, z), ...]"""
    slab(profile, length, at, (90, 0, 0), m=m)


CORNICE = [(0, 0), (-0.01, 0), (-0.015, 0.012), (-0.03, 0.022), (-0.042, 0.045), (-0.06, 0.06), (-0.07, 0.075),
           (-0.07, 0.09), (0, 0.09)]


def cornice(W, D, z, m, prof=CORNICE, back=True):
    """a moulded cornice round the front and both sides of a W x D case (front at -D/2)"""
    out = -min(y for y, _ in prof)
    run_x(prof, W + 2 * out, (0, -D / 2, z), m)
    for s in (-1, 1):
        run_y([(-y * s, zz) for y, zz in prof], D + out, (s * W / 2, -out / 2, z), m)


def raised_panel(w, h, at, m, t=0.012, rot=(0, 0, 0)):
    """a fielded panel facing -y: the flat frame and the bevelled raised field"""
    with place(T(at, rot)):
        box((w, t, h), m=m)
        box((w * 0.8, t * 1.8, h * 0.82), (0, -t * 0.4, 0), m=m, bevel=min(w, h) * 0.07)


def knob(at, r=0.016, m="brass", rot=(90, 0, 0)):
    with place(T(at, rot)):
        lathe([(0, 0), (r * 0.5, 0), (r * 0.4, r * 0.8), (r, r * 1.4), (r * 0.8, r * 2.1), (0, r * 2.2)], m=m, n=8)


def bail(at, w=0.09, m="brass"):
    """a drawer's brass bail pull: back plate and the hanging loop"""
    x, y, z = at
    box((w * 1.3, 0.004, 0.035), (x, y, z), m=m, bevel=0.002)
    sweep([(x - w / 2, y - 0.006, z + 0.008), (x - w / 2, y - 0.016, z - 0.012), (x + w / 2, y - 0.016, z - 0.012),
           (x + w / 2, y - 0.006, z + 0.008)], 0.004, m, 5, bend=0.01)


def keyhole(at, m="brass"):
    x, y, z = at
    with place(T(at, (90, 0, 0))):
        slab([(0, 0.022), (0.012, 0.012), (0.014, -0.004), (0.008, -0.022), (-0.008, -0.022), (-0.014, -0.004),
              (-0.012, 0.012)], 0.003, m=m)
    box((0.004, 0.003, 0.012), (x, y - 0.002, z - 0.002), m="ebony")


def candle(at, h, r=0.011, flame=True, drips=3, seed=1):
    """a wax candle: melted unevenly, drips down its side, black wick, maybe lit"""
    rnd = random.Random(seed)
    x, y, z = at
    lathe([(0, 0), (r, 0), (r, h - 0.006), (r * 0.8, h), (0, h - 0.003)], (x, y, z), m="wax", n=8)
    for k in range(drips):
        a = rnd.uniform(0, 2 * math.pi)
        dl = rnd.uniform(0.02, min(0.08, h * 0.8))
        sweep([(x + math.cos(a) * r, y + math.sin(a) * r, z + h - 0.004),
               (x + math.cos(a) * r * 1.15, y + math.sin(a) * r * 1.15, z + h - dl * 0.6),
               (x + math.cos(a) * r * 1.1, y + math.sin(a) * r * 1.1, z + h - dl)], r * 0.28, "wax", 5)
    cyl(0.0012, 0.012, (x, y, z + h + 0.004), m="wick", n=4)
    if flame:
        with group("Flame"):
            lathe([(0, 0), (r * 0.45, r * 0.5), (r * 0.5, r * 1.3), (r * 0.25, r * 2.3), (0, r * 3.2)],
                  (x, y, z + h + 0.006), m="flame", n=6)


def cloth_tube(top_z, bottom_z, r_top, r_bottom, at, m, folds=8, seed=1, flat=0.6, nu=16, nv=12):
    """a hanging garment: a tube of cloth widening to its hem, folded"""
    x0, y0 = at

    def shape(u, v):
        a = 2 * math.pi * u
        z = top_z - (top_z - bottom_z) * v
        r = r_top + (r_bottom - r_top) * v ** 0.8
        r += 0.015 * v * math.sin(a * folds + v * 2)
        return (x0 + math.cos(a) * r, y0 + math.sin(a) * r * flat, z)
    grid(1, 1, nu, nv, shape, m=m, thick=0.005, rough_edge=0.006, seed=seed)


def books_row(x0, x1, y, z, depth, rnd, max_h=0.28):
    """a shelf of old books: mixed heights and colours, gilt bands, a gap, one leaning"""
    x = x0
    while x < x1 - 0.03:
        if rnd.random() < 0.07:
            x += rnd.uniform(0.04, 0.12)
            continue
        w = rnd.uniform(0.022, 0.05)
        h = rnd.uniform(0.62, 1.0) * max_h
        if x + w > x1:
            break
        m = rnd.choice(BOOKS)
        d = depth * rnd.uniform(0.75, 0.95)
        box((w - 0.002, d, h), (x + w / 2, y, z + h / 2), m=m)
        for fz in (0.12, 0.86):
            box((w - 0.001, 0.003, 0.007), (x + w / 2, y - d / 2 - 0.001, z + h * fz), m="gilt")
        x += w
    if x1 - x > 0.06:                                                 # the last one fallen against the side
        h = 0.8 * max_h
        with place(T((x + 0.02, y, z), (0, 28, 0))):
            box((0.035, depth * 0.85, h), (0, 0, h / 2), m=rnd.choice(BOOKS))


# ---------------------------------------------------------------- furniture

POST = [(0, 0), (0.05, 0), (0.055, 0.02), (0.045, 0.04), (0.05, 0.06), (0.035, 0.1), (0.04, 0.3), (0.055, 0.45),
        (0.06, 0.5), (0.045, 0.6), (0.032, 0.7), (0.042, 0.76), (0.03, 0.82), (0.027, 0.95), (0.036, 1.01),
        (0.026, 1.07), (0.028, 1.2), (0.042, 1.3), (0.034, 1.36), (0.045, 1.42), (0.03, 1.5), (0.035, 1.6),
        (0.045, 1.64), (0.045, 1.66), (0, 1.66)]
FINIAL = [(0, 0), (0.03, 0), (0.035, 0.02), (0.02, 0.04), (0.035, 0.07), (0.025, 0.11), (0.008, 0.14), (0, 0.15)]


@piece("FourPosterBed", close=((3.4, -6.0, 3.6), (0.2, -1.0, 2.2), 40))
def four_poster_bed():
    """a carved mahogany four-poster: turned posts with finials, an arched panelled headboard with
    a carved shell, the canopy with its valance, rotten drapes tied back to the posts, a dusty green
    coverlet over the ticking mattress, two flattened pillows"""
    mansion_materials()
    W, L = 1.55, 2.15
    px, py = W / 2, L / 2
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * px, sy * py
            box((0.11, 0.11, 0.42), (x, y, 0.21), m="mahogany_v", bevel=0.01)
            box((0.13, 0.13, 0.03), (x, y, 0.015), m="mahogany_v", bevel=0.006)
            lathe(POST, (x, y, 0.42), m="mahogany_v", n=10)
            box((0.1, 0.1, 0.12), (x, y, 2.14), m="mahogany_v", bevel=0.008)
            lathe(FINIAL, (x, y, 2.2), m="mahogany_v", n=10)
    for sx in (-1, 1):
        box((0.045, L - 0.11, 0.2), (sx * px, 0, 0.38), m="mahogany_y", bevel=0.006)
    for sy in (-1, 1):
        box((W - 0.11, 0.045, 0.2), (0, sy * py, 0.38), m="mahogany_h", bevel=0.006)
    box((W - 0.13, L - 0.13, 0.24), (0, 0, 0.6), m="ticking", bevel=0.05)
    for sx in (-1, 1):
        lump(0.3, (sx * 0.33, py - 0.32, 0.8), m="linen", seed=3 + sx, squash=(1.0, 0.55, 0.3), rough=0.08)
    # the coverlet, hanging over the sides
    half = (W - 0.13) / 2

    def cover(u, v):
        x = (u - 0.5) * (W + 0.4)
        y = -py + 0.07 + v * 1.55
        ax = abs(x)
        if ax <= half:
            return (x, y, 0.735 + 0.012 * math.sin(x * 9 + y * 5))
        d = ax - half
        return (math.copysign(half + 0.02 + 0.015 * math.sin(y * 14), x), y, 0.725 - d * 1.9)
    grid(W + 0.4, 1.55, 22, 16, cover, m="coverlet", thick=0.008, rough_edge=0.006, seed=11)
    # headboard: arched, three raised panels, a carved shell on top; the lower footboard
    for yb, ztop, rise, n_p in ((py, 1.3, 0.28, 3), (-py, 0.86, 0.1, 3)):
        pts = [(-px + 0.05, 0.42), (px - 0.05, 0.42)]
        pts += [((px - 0.05) * math.cos(math.pi * i / 12), ztop + rise * math.sin(math.pi * i / 12)) for i in range(13)]
        slab(pts, 0.05, (0, yb, 0), (90, 0, 0), m="mahogany_h", bevel=0.008)
        face = yb - 0.03
        for i in range(n_p):
            x = (i - (n_p - 1) / 2) * 0.44
            raised_panel(0.36, (ztop - 0.55) * 0.75, (x, face, 0.42 + (ztop - 0.42) * 0.52), m="mahogany_h")
    with place(T((0, py - 0.03, 1.5), (90, 0, 0))):
        lathe([(0, 0), (0.17, 0), (0.13, 0.03), (0, 0.035)], m="mahogany_h", n=12, arc=(0, 180))
        for i in range(7):
            a = math.radians(15 + i * 25)
            box((0.012, 0.15, 0.012), (math.cos(a) * 0.075, math.sin(a) * 0.075, 0.03), (0, 0, math.degrees(a) - 90),
                m="mahogany_h")
    # the canopy: rails, a little cornice, the valance
    for sy in (-1, 1):
        box((W + 0.02, 0.05, 0.1), (0, sy * py, 2.12), m="mahogany_h", bevel=0.006)
    for sx in (-1, 1):
        box((0.05, L, 0.1), (sx * px, 0, 2.12), m="mahogany_y", bevel=0.006)
    cornice(W + 0.06, L + 0.06, 2.17, "mahogany_h", [(0, 0), (-0.02, 0), (-0.03, 0.02), (-0.04, 0.035), (0, 0.035)])
    rnd = random.Random(21)
    for side in ("front", "left", "right"):
        def val(u, v, side=side):
            z = 2.14 - v * 0.32
            if side == "front":
                return ((u - 0.5) * (W + 0.06), -py - 0.045 + 0.008 * math.sin(u * 60), z)
            s = -1 if side == "left" else 1
            return (s * (px + 0.045) + s * 0.008 * math.sin(u * 60), (u - 0.5) * (L + 0.06), z)

        def scallop(u, v, side=side):
            return v < 0.72 or (math.sin(u * math.pi * 18) > 0.1 and v < 0.95) or (rnd.random() < 0.0)
        grid(1, 1, 36, 6, val, m="drape", keep=scallop, thick=0.004, rough_edge=0.006, seed=13)
    # the drapes, rotted at the hem and tied back to the posts
    for sx in (-1, 1):
        for sy in (-1, 1):
            def curtain(u, v, sx=sx, sy=sy):
                z = 2.1 - v * 2.06
                tie = math.exp(-((z - 1.0) / 0.35) ** 2)
                spread = 0.55 * (1 - 0.75 * tie) + 0.12 * max(0, (0.3 - z)) / 0.3
                y = sy * (py - 0.02) - sy * u * spread
                x = sx * (px + 0.06) + sx * 0.035 * math.sin(u * math.pi * 7 + v * 2) * (1 - 0.6 * tie)
                return (x, y, z)

            def torn(u, v):
                return not ((v > 0.86 and rnd.random() < 0.3) or rnd.random() < 0.015)
            grid(1, 1, 8, 20, curtain, m="drape", keep=torn, thick=0.004, rough_edge=0.01, seed=17 + sx + 2 * sy)
            sweep([(sx * (px + 0.03), sy * (py - 0.02), 1.0), (sx * (px + 0.1), sy * (py - 0.12), 1.0),
                   (sx * (px + 0.03), sy * (py - 0.2), 0.98)], 0.008, "gilt", 5, bend=0.03)


@piece("Wardrobe", close=((2.2, -3.6, 4.2), (-0.4, -0.6, 3.6), 40), tex=2048)
def wardrobe():
    """a tall carved wardrobe: moulded cornice with an arched crest, bracket feet, a panelled left door
    standing ajar (a faded white dress hanging inside), the right door with its foxed oval mirror;
    both doors are their own meshes, pivoted on their hinges - a place to hide"""
    mansion_materials()
    material("dress", "cloth", base="#cfc6b2", stain=0.3, moldy=0.1, dusty=0.3, fade=0.0)
    cracks = art.cracks_png()
    W, D, H0, H1 = 1.3, 0.62, 0.12, 2.07
    hc = (H0 + H1) / 2
    box((W + 0.08, D + 0.06, 0.075), (0, 0, 0.0825), m="mahogany_h", bevel=0.01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((0.1, 0.1, 0.05), (sx * (W / 2 - 0.01), sy * (D / 2 - 0.01), 0.025), m="mahogany_v", bevel=0.012)
    for sx in (-1, 1):
        box((0.03, D, H1 - H0), (sx * (W / 2 - 0.015), 0, hc), m="mahogany_v", bevel=0.004)
        raised_panel(0.4, 1.4, (sx * (W / 2 + 0.001), 0, hc), m="mahogany_v", rot=(0, 0, 90 * sx))
    box((W - 0.06, 0.02, H1 - H0), (0, D / 2 - 0.01, hc), m="mahogany_v")
    box((W - 0.06, D, 0.03), (0, 0, H0 + 0.015), m="mahogany_h")
    box((W - 0.06, D, 0.03), (0, 0, H1 - 0.015), m="mahogany_h")
    box((0.04, 0.04, H1 - H0), (0, -D / 2 + 0.02, hc), m="mahogany_v")
    cornice(W, D, H1, "mahogany_h")
    box((W + 0.14, D + 0.07, 0.03), (0, -0.035, H1 + 0.105), m="mahogany_h", bevel=0.005)
    pts = [((W / 2) * math.cos(math.pi * i / 14), 0.16 * math.sin(math.pi * i / 14)) for i in range(15)]
    slab([(x * 0.7, z) for x, z in pts], 0.03, (0, -D / 2 - 0.05, H1 + 0.12), (90, 0, 0), m="mahogany_h", bevel=0.006)
    with place(T((0, -D / 2 - 0.07, H1 + 0.19), (90, 0, 0))):
        lathe([(0, 0), (0.06, 0), (0.05, 0.015), (0.025, 0.03), (0, 0.032)], m="mahogany_h", n=12)
    # inside: the rail, hangers, an old dress
    cyl(0.012, W - 0.06, (0, 0.05, 1.85), (0, 90, 0), m="brass", n=8)
    for x in (-0.38, -0.2, 0.25):
        with place(T((x, 0.05, 1.85))):
            sweep([(0, 0, 0.0), (0, 0, -0.04), (-0.17, 0, -0.1), (0.17, 0, -0.1), (0, 0, -0.04)], 0.004,
                  "walnut_h", 5, bend=0.01)
    cloth_tube(1.76, 0.42, 0.12, 0.32, (-0.32, 0.05), "dress", folds=9, seed=7)
    lump(0.12, (-0.3, 0.05, 1.7), m="dress", seed=8, squash=(1.6, 0.6, 0.6), rough=0.1)
    # the doors (hinged on their outer edges; the left one stands ajar)
    DW = W / 2 - 0.02
    for side, name, ang in ((-1, "DoorLeft", -28), (1, "DoorRight", 0)):
        hx = side * (W / 2 - 0.02)
        with group(name, (hx, -D / 2 - 0.012, hc)), place(T((hx, -D / 2 - 0.012, 0), (0, 0, ang))):
            cx = -side * DW / 2
            box((DW, 0.025, H1 - H0 - 0.04), (cx, 0, hc), m="mahogany_v", bevel=0.005)
            if side < 0:
                for z in (hc + 0.45, hc - 0.45):
                    raised_panel(DW - 0.14, 0.75, (cx, -0.013, z), m="mahogany_v")
            else:
                decal("mirror", cracks, here((cx, -0.0175, hc + 0.25), (90, 0, 0)), (0.42, 0.42))
                pts = [(math.cos(2 * math.pi * i / 28) * 0.21, math.sin(2 * math.pi * i / 28) * 0.36) for i in range(28)]
                slab(pts, 0.006, (cx, -0.014, hc + 0.25), (90, 0, 0), m="mirror")
                sweep([(cx + math.cos(2 * math.pi * i / 28) * 0.215, -0.018,
                        hc + 0.25 + math.sin(2 * math.pi * i / 28) * 0.365) for i in range(28)], 0.012, "gilt", 6,
                      closed=True)
                raised_panel(DW - 0.14, 0.4, (cx, -0.013, hc - 0.6), m="mahogany_v")
            ex = -side * (DW - 0.06)
            keyhole((ex, -0.015, hc), "brass")
            knob((ex, -0.013, hc + 0.12))


@piece("WingbackArmchair", close=((1.6, -2.4, 2.6), (0, -0.2, 1.6), 45))
def wingback_armchair():
    """a wingback armchair in faded red velvet: deep-buttoned back, scrolled arms, the wings,
    a sagging seat cushion, carved cabriole legs in front"""
    mansion_materials()
    W, Dp = 0.8, 0.78
    for sx in (-1, 1):
        cabriole((sx * 0.32, -0.3, 0.3), 0.3, 0.08, 0.028, "mahogany_v", (sx * 0.4, -1))
        tapered([(sx * 0.32, 0.3, 0.3), (sx * 0.34, 0.36, 0.12), (sx * 0.35, 0.42, 0.0)], (0.028, 0.025, 0.022),
                "mahogany_v", 8, 4)
    box((W - 0.04, Dp - 0.12, 0.16), (0, 0.0, 0.36), m="velvet_red", bevel=0.03)
    box((W - 0.06, 0.04, 0.12), (0, -0.33, 0.33), m="mahogany_h", bevel=0.01)          # carved front rail
    box((W - 0.2, Dp - 0.24, 0.1), (0, -0.07, 0.48), (-3, 0, 0), m="velvet_red", bevel=0.045)   # the cushion
    # the back, deep-buttoned
    with place(T((0, 0.3, 0.44), (-8, 0, 0))):
        slab(rounded_rect(W - 0.06, 0.9, 0.18, 4, cy=0.45), 0.18, (0, 0, 0), (90, 0, 0), m="velvet_red", bevel=0.04)
        for r in range(4):
            for c in range(4 - (r % 2)):
                x = (c - (3 - (r % 2)) / 2) * 0.15
                sphere(0.012, (x, -0.092, 0.25 + r * 0.15), m="velvet_red", n=6, rings=4)
    # the wings and the scrolled arms
    for sx in (-1, 1):
        prof = [(-0.3, 0.42), (0.32, 0.42), (0.36, 1.25), (0.2, 1.3), (0.0, 1.15), (-0.1, 0.9), (-0.3, 0.78)]
        slab(prof, 0.08, (sx * (W / 2 - 0.04), 0, 0), (90, 0, 90), m="velvet_red", bevel=0.03)
        cyl(0.075, Dp - 0.12, (sx * (W / 2 - 0.02), -0.06, 0.66), (90, 0, 0), m="velvet_red", n=12)
        with place(T((sx * (W / 2 - 0.02), -Dp / 2 + 0.02, 0.66))):
            cyl(0.085, 0.04, (0, 0, 0), (90, 0, 0), m="velvet_red", n=12)
            torus(0.04, 0.012, (0, -0.02, 0), (90, 0, 0), m="mahogany_h", n=10, k=4)


@piece("SheetedSofa", close=((1.8, -3.0, 2.4), (0, -0.3, 1.4), 45))
def sheeted_sofa():
    """a camelback sofa under a dust sheet - only its carved feet showing - the sheet grey with
    years of dust, sagging between the seat and the back, pooling on the floor at the ends"""
    mansion_materials()
    L = 1.9
    for sx in (-1, 1):
        for y in (-0.32, 0.3):
            lathe([(0, 0), (0.035, 0), (0.04, 0.02), (0.028, 0.05), (0.034, 0.08), (0.03, 0.1), (0, 0.1)],
                  (sx * (L / 2 - 0.06), y, 0), m="mahogany_v", n=8)

    def profile(v):
        """the covered shape across the sofa (y, z) for v 0..1: front floor, seat, back, back floor"""
        pts = [(-0.42, 0.1), (-0.43, 0.38), (-0.36, 0.47), (0.02, 0.45), (0.18, 0.62), (0.22, 0.9), (0.3, 0.99),
               (0.42, 0.88), (0.44, 0.5), (0.43, 0.1)]
        f = v * (len(pts) - 1)
        i = min(int(f), len(pts) - 2)
        t = f - i
        return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)

    def sheet(u, v):
        x = (u - 0.5) * (L + 0.5)
        y, z = profile(v)
        ax = abs(x)
        end = L / 2 - 0.08
        hump = 1.0 + 0.08 * math.cos(x * 2.2)                         # camelback: higher in the middle
        if z > 0.6:
            z = 0.6 + (z - 0.6) * hump
        if ax > end:                                                  # over the arms and down to the floor
            d = ax - end
            arm = 0.68
            z = min(z, arm) if d < 0.07 else max(0.02, min(z, arm) - (d - 0.07) * 4.5)
            x = math.copysign(end + 0.07 + max(0, d - 0.07) * 0.18, x)
        z += 0.015 * math.sin(x * 11 + v * 8) + 0.01 * math.sin(x * 23 - v * 3)
        if z < 0.12:
            z = 0.12 - (0.12 - z) * 0.3
        return (x, y * (1 + 0.03 * math.sin(x * 7)), z)
    grid(1, 1, 34, 26, sheet, m="dustsheet", thick=0.006, rough_edge=0.012, seed=19)


@piece("DiningTable", close=((2.4, -3.2, 2.8), (0.2, -0.2, 2.2), 45))
def dining_table():
    """a long mahogany dining table on six turned legs, laid years ago and left: a runner, plates,
    tarnished cutlery, a soup tureen, crystal goblets - one knocked over"""
    mansion_materials()
    L, Wd, H = 2.3, 1.05, 0.76
    box((L, Wd, 0.04), (0, 0, H - 0.02), m="mahogany_h", bevel=0.012)
    run_x([(0, 0), (-0.015, 0), (-0.02, 0.012), (-0.012, 0.025), (0, 0.025)], L, (0, -Wd / 2, H - 0.045), "mahogany_h")
    run_x([(0, 0), (0.015, 0), (0.02, 0.012), (0.012, 0.025), (0, 0.025)], L, (0, Wd / 2, H - 0.045), "mahogany_h")
    for sy in (-1, 1):                                                # aprons with a carved scalloped edge
        La = L - 0.14
        pts = [(-La / 2, H - 0.04), (La / 2, H - 0.04), (La / 2, H - 0.15)]
        n = 14
        for i in range(n * 4 + 1):
            x = La / 2 - La * i / (n * 4)
            ph = (i % 4) / 4
            pts.append((x, H - 0.15 + 0.035 * math.sin(math.pi * ph) * (1 if (i // 4) % 2 else 0.6)))
        slab(pts[:-1] + [(-La / 2, H - 0.15)], 0.025, (0, sy * (Wd / 2 - 0.06), 0), (90, 0, 0), m="mahogany_h",
             bevel=0.004)
    for sx in (-1, 1):
        box((0.025, Wd - 0.12, 0.1), (sx * (L / 2 - 0.07), 0, H - 0.09), m="mahogany_y", bevel=0.004)
    for x in (-(L / 2 - 0.08), 0, L / 2 - 0.08):
        for sy in (-1, 1):
            lathe(leg_profile(H - 0.14, 0.045), (x, sy * (Wd / 2 - 0.08), 0), m="mahogany_v", n=10)
    top = H
    # the runner and the places
    box((L - 0.3, 0.38, 0.004), (0, 0, top + 0.002), m="drape")
    for x in (-0.75, -0.25, 0.25, 0.75):
        for sy in (-1, 1):
            if (x, sy) == (0.25, 1):
                continue                                              # one place never laid
            px, py = x, sy * 0.33
            lathe([(0, 0), (0.1, 0), (0.12, 0.012), (0.12, 0.016), (0.1, 0.006), (0, 0.006)], (px, py, top), m="china",
                  n=14)
            for k, dx in enumerate((-0.15, 0.15, 0.17)):
                box((0.012, 0.18, 0.003), (px + dx, py, top + 0.002), m="silver")
            if (x, sy) == (-0.25, -1):                                # knocked over, rolled
                with place(T((px + 0.12, py + 0.18, top + 0.03), (0, 90, 35))):
                    lathe([(0, 0), (0.035, 0), (0.008, 0.01), (0.006, 0.08), (0.03, 0.1), (0.035, 0.16), (0.033, 0.16)],
                          (0, 0, -0.08), m="crystal", n=8)
            else:
                lathe([(0, 0), (0.035, 0), (0.008, 0.01), (0.006, 0.08), (0.03, 0.1), (0.035, 0.16), (0.033, 0.16)],
                      (px + 0.12, py + sy * -0.12, top), m="crystal", n=8)
    with place(T((0, 0, top))):                                       # the soup tureen
        lathe([(0, 0), (0.09, 0), (0.06, 0.03), (0.14, 0.08), (0.15, 0.14), (0.13, 0.16), (0, 0.16)], m="china", n=16)
        lathe([(0, 0.16), (0.14, 0.16), (0.12, 0.2), (0.05, 0.23), (0.02, 0.26), (0, 0.27)], m="china", n=16)
        for s in (-1, 1):
            torus(0.025, 0.007, (s * 0.15, 0, 0.12), (90, 0, 0), m="china", n=8, k=4)
        lathe([(0.15, 0.13), (0.152, 0.145), (0.0, 0.145)], m="china_blue", n=16)


@piece("DiningChair", close=((1.2, -1.8, 2.2), (0, 0, 1.5), 45))
def dining_chair():
    """a balloon-back dining chair: the carved hoop back, a red velvet drop-in seat, turned front
    legs and sabre back legs"""
    mansion_materials()
    for sx in (-1, 1):
        lathe(leg_profile(0.42, 0.024), (sx * 0.19, -0.18, 0), m="mahogany_v", n=8)
        tapered([(sx * 0.18, 0.24, 0.0), (sx * 0.18, 0.2, 0.2), (sx * 0.18, 0.18, 0.42), (sx * 0.16, 0.21, 0.62),
                 (sx * 0.125, 0.245, 0.81)], (0.016, 0.02, 0.022, 0.02, 0.017), "mahogany_v", 8, 5)
    for y in (-0.18, 0.18):
        box((0.36, 0.03, 0.06), (0, y, 0.39), m="mahogany_h", bevel=0.005)
    for sx in (-1, 1):
        box((0.03, 0.36, 0.06), (sx * 0.18, 0, 0.39), m="mahogany_y", bevel=0.005)
    slab(rounded_rect(0.42, 0.4, 0.06, 3), 0.06, (0, 0, 0.44), m="velvet_red", bevel=0.02)
    # the balloon back: a hoop pinched in at the waist, with a carved cross-rail
    hoop = []                                                         # springing from the uprights, over the top
    for i in range(23):
        a = math.radians(-52 + 284 * i / 22)
        hoop.append((math.cos(a) * 0.17, 0.25 + 0.012 * math.sin(a), 0.94 + math.sin(a) * 0.17))
    sweep(hoop, 0.016, "mahogany_h", 6)
    sweep([(-0.125, 0.245, 0.81), (0, 0.25, 0.78), (0.125, 0.245, 0.81)], 0.013, "mahogany_h", 6, bend=0.05)
    with place(T((0, 0.25, 1.11), (90, 0, 0))):
        lathe([(0, 0), (0.05, 0), (0.035, 0.012), (0, 0.015)], m="mahogany_h", n=10, arc=(0, 180))


@piece("UprightPiano", close=((1.6, -2.6, 3.2), (-0.1, -0.2, 2.6), 40))
def upright_piano():
    """an upright piano in walnut: carved front panel, brass candle sconces still holding their candles,
    yellowed keys (a few sunk, one missing), open music desk with a nocturne on it, brass pedals,
    and its round stool (its own mesh)"""
    mansion_materials()
    music = art.music_png()
    material("music", "paper", base="#d6c8a4")
    W, D, H = 1.48, 0.6, 1.3
    KZ = 0.72
    for sx in (-1, 1):                                                # the cheeks, curving forward under the keys
        slab([(0.3, 0.0), (-0.3, 0.0), (-0.3, 0.06), (-0.12, 0.08), (-0.18, 0.62), (-0.32, 0.66), (-0.32, KZ + 0.04),
              (-0.14, KZ + 0.06), (-0.12, H), (0.3, H)], 0.04, (sx * (W / 2 - 0.02), 0, 0), (90, 0, 90), m="walnut_v",
             bevel=0.006)
    box((W - 0.04, D - 0.28, H - 0.1), (0, 0.14, (H - 0.1) / 2 + 0.06), m="walnut_v")
    box((W + 0.04, D - 0.24, 0.03), (0, 0.12, H + 0.015), m="walnut_h", bevel=0.006)
    raised_panel(W - 0.2, 0.42, (0, -0.026, 0.32), m="walnut_v")
    raised_panel(W - 0.2, 0.38, (0, -0.026, KZ + 0.32), m="walnut_v")
    for x in (-0.42, 0.42):                                           # carved rosettes on the front
        with place(T((x, -0.04, KZ + 0.32), (90, 0, 0))):
            lathe([(0, 0), (0.06, 0), (0.05, 0.012), (0.02, 0.02), (0, 0.022)], m="walnut_h", n=10)
    box((W - 0.08, 0.32, 0.04), (0, -0.14, KZ), m="walnut_h", bevel=0.004)          # key bed
    box((W - 0.08, 0.02, 0.06), (0, -0.3, KZ + 0.01), m="walnut_h", bevel=0.004)    # key slip
    # the keys
    nW = 52
    kw = (W - 0.16) / nW
    x0 = -(W - 0.16) / 2
    rnd = random.Random(9)
    for i in range(nW):
        if i == 31:
            continue                                                  # a missing key
        sunk = 0.007 if i in (12, 13, 40) else 0.0
        box((kw - 0.0015, 0.14, 0.02), (x0 + (i + 0.5) * kw, -0.21, KZ + 0.03 - sunk), m="ivory", bevel=0.0015)
    for i in range(nW - 1):
        if (1, 0, 1, 1, 0, 1, 1)[i % 7]:                              # a black key after A, C, D, F, G
            box((kw * 0.55, 0.085, 0.022), (x0 + (i + 1) * kw, -0.175, KZ + 0.048), m="ebony", bevel=0.002)
    box((W - 0.12, 0.06, 0.03), (0, -0.115, KZ + 0.075), m="walnut_h", bevel=0.004)     # nameboard
    with place(T((0, -0.12, KZ + 0.3), (-12, 0, 0))):                                   # music desk
        box((0.8, 0.02, 0.32), (0, 0, 0.06), m="walnut_h", bevel=0.004)
        box((0.8, 0.05, 0.015), (0, -0.03, -0.1), m="walnut_h")
        decal("music", music, here((0, -0.0135, 0.1), (90, 0, 0)), (0.3, 0.4))
        box((0.3, 0.004, 0.4), (0, -0.0115, 0.1), m="music")
    # candle sconces swinging out from the front
    for sx in (-1, 1):
        with place(T((sx * 0.6, -0.025, KZ + 0.38))):
            cyl(0.03, 0.008, (0, 0, 0), (90, 0, 0), m="brass", n=10)
            sweep([(0, -0.005, 0), (sx * 0.05, -0.08, 0.02), (sx * 0.08, -0.14, 0.04)], 0.006, "brass", 5, bend=0.03)
            lathe([(0, 0), (0.035, 0.005), (0.04, 0.012), (0.012, 0.012), (0.012, 0.03), (0, 0.03)],
                  (sx * 0.08, -0.14, 0.04), m="brass", n=10)
            candle((sx * 0.08, -0.14, 0.07), 0.1 if sx < 0 else 0.05, flame=True, seed=4 + sx)
    # pedals and the toe
    box((W - 0.08, 0.06, 0.06), (0, -0.25, 0.03), m="walnut_h", bevel=0.005)
    for x in (-0.06, 0.06):
        with place(T((x, -0.27, 0.07), (8, 0, 0))):
            box((0.025, 0.12, 0.01), (0, -0.05, 0), m="brass", bevel=0.003)
    # the stool
    with group("Stool", (0.1, -0.75, 0)), place(T((0.1, -0.75, 0))):
        for i in range(3):
            a = math.radians(90 + 120 * i)
            tapered([(0, 0, 0.18), (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.08), (math.cos(a) * 0.17, math.sin(a) * 0.17, 0.02)],
                    (0.025, 0.02, 0.018), "walnut_v", 8, 4)
            sphere(0.02, (math.cos(a) * 0.175, math.sin(a) * 0.175, 0.02), m="brass", n=6, rings=4)
        lathe([(0, 0.15), (0.04, 0.15), (0.03, 0.25), (0.045, 0.3), (0.03, 0.38), (0.12, 0.42), (0, 0.42)], m="walnut_v",
              n=10)
        lathe([(0, 0.42), (0.17, 0.42), (0.18, 0.45), (0.16, 0.5), (0, 0.51)], m="velvet_green", n=16)


@piece("GrandfatherClock", close=((1.0, -2.2, 6.4), (0, 0, 5.8), 35))
def grandfather_clock():
    """a long-case clock: moulded base, the trunk door glazed to show the brass pendulum and weights,
    the hood with turned columns, a broken-arch pediment and three finials; the dial stopped at 3:14"""
    mansion_materials()
    face = art.clock_png()
    material("dial", "paint", base="#d8cdb0", chip=0.05, rust=-3, peel=-1, dirt=0.4)
    decal("dial", face, here((0, -0.1655, 1.83), (90, 0, 0)), (0.34, 0.34))
    box((0.56, 0.32, 0.5), (0, 0, 0.25), m="mahogany_v", bevel=0.01)
    cornice(0.56, 0.32, 0.5, "mahogany_h", [(0, 0), (-0.02, 0), (-0.03, 0.015), (-0.02, 0.03), (0, 0.04)])
    raised_panel(0.36, 0.3, (0, -0.161, 0.25), m="mahogany_v")
    box((0.6, 0.36, 0.04), (0, 0, 0.02), m="mahogany_h", bevel=0.006)
    # the trunk, hollow, its door glazed onto the pendulum and the weights
    box((0.44, 0.12, 1.0), (0, 0.09, 1.04), m="mahogany_v", bevel=0.006)
    for sx in (-1, 1):
        box((0.02, 0.24, 1.0), (sx * 0.21, 0.01, 1.04), m="mahogany_v", bevel=0.004)
        box((0.11, 0.02, 0.62), (sx * 0.165, -0.1, 1.06), m="mahogany_v", bevel=0.004)
    box((0.44, 0.02, 0.21), (0, -0.1, 0.645), m="mahogany_v", bevel=0.004)
    box((0.44, 0.02, 0.17), (0, -0.1, 1.455), m="mahogany_v", bevel=0.004)
    box((0.4, 0.004, 0.96), (0, 0.028, 1.04), m="ebony")                                  # dark inside
    with group("Glass"):
        box((0.22, 0.004, 0.62), (0, -0.104, 1.06), m="old_glass")
    cyl(0.004, 0.5, (0, -0.03, 1.2), m="brass", n=4)                                       # the pendulum
    with place(T((0, -0.03, 0.92), (90, 0, 0))):
        lathe([(0, -0.006), (0.065, -0.006), (0.07, 0.0), (0.065, 0.006), (0, 0.006)], m="brass", n=16)
    for x in (-0.07, 0.07):
        cyl(0.02, 0.2, (x, 0.0, 1.25), m="brass", n=10)
        cyl(0.002, 0.18, (x, 0.0, 1.44), m="brass", n=4)
    cornice(0.44, 0.26, 1.54, "mahogany_h", [(0, 0), (-0.03, 0), (-0.04, 0.02), (-0.06, 0.04), (0, 0.04)])
    # the hood
    box((0.54, 0.32, 0.56), (0, 0.0, 1.88), m="mahogany_v", bevel=0.008)
    kit.UV_BOOST["Dial"] = 3.0
    with group("Dial"):
        box((0.34, 0.004, 0.34), (0, -0.163, 1.83), m="dial")
    for x in (-0.07, 0.07):
        cyl(0.004, 0.006, (x, -0.166, 1.79), (90, 0, 0), m="ebony", n=6)                 # winding holes
    for z in (1.635, 2.035):                                          # the hood door's frame
        box((0.42, 0.02, 0.03), (0, -0.172, z), m="mahogany_h", bevel=0.004)
    for x in (-0.195, 0.195):
        box((0.03, 0.02, 0.43), (x, -0.172, 1.835), m="mahogany_h", bevel=0.004)
    with group("Glass"):
        box((0.36, 0.004, 0.37), (0, -0.176, 1.835), m="old_glass")
    for sx in (-1, 1):
        lathe([(0, 0), (0.025, 0), (0.02, 0.03), (0.016, 0.42), (0.022, 0.45), (0.025, 0.48), (0, 0.48)],
              (sx * 0.245, -0.16, 1.62), m="mahogany_v", n=8)
    cornice(0.54, 0.32, 2.16, "mahogany_h", [(0, 0), (-0.02, 0), (-0.035, 0.02), (-0.045, 0.04), (0, 0.04)])
    for sx in (-1, 1):                                                # broken-arch pediment
        arc = [(sx * (0.03 + 0.25 * math.cos(math.pi / 2 * i / 6)), 0.05 + 0.17 * math.sin(math.pi / 2 * i / 6))
               for i in range(7)]
        slab([(sx * 0.03, 0.0), (sx * 0.28, 0.0)] + arc, 0.04, (0, -0.13, 2.2), (90, 0, 0), m="mahogany_h", bevel=0.005)
    for x, h in ((-0.26, 0.12), (0, 0.15), (0.26, 0.12)):
        lathe([(0, 0), (0.025, 0), (0.025, 0.02), (0.012, 0.03), (0.03, 0.06), (0.02, 0.09), (0.006, h), (0, h)],
              (x, -0.05, 2.2 if x == 0 else 2.2), m="gilt", n=8)


@piece("WritingDesk", close=((1.8, -2.4, 3.6), (0, -0.2, 2.8), 40))
def writing_desk():
    """a mahogany bureau, its fall-front down: pigeonholes stuffed with letters, little drawers,
    an inkwell and quill, a wax seal, spectacles left on an unfinished letter; an oil lamp and books
    on top; long drawers with brass bail pulls below"""
    mansion_materials()
    material("letter", "paper", base="#d8cba6")
    W, D, H = 1.0, 0.5, 1.05
    box((W + 0.04, D + 0.03, 0.06), (0, 0, 0.09), m="mahogany_h", bevel=0.008)
    for sx in (-1, 1):
        for sy in (-1, 1):
            slab([(0, 0), (0.08, 0), (0.08, 0.06), (0.04, 0.06), (0.015, 0.03), (0, 0.03)], 0.03,
                 (sx * (W / 2), sy * (D / 2 - 0.01), 0.0), (90, 0, 90 if sx > 0 else -90), m="mahogany_v")
    box((W, D, 0.62), (0, 0, 0.43), m="mahogany_v", bevel=0.006)
    for k, z in enumerate((0.23, 0.42, 0.61)):                         # long drawers
        raised_panel(W - 0.06, 0.15, (0, -D / 2 - 0.001, z), m="mahogany_h", t=0.008)
        for x in (-0.25, 0.25):
            bail((x, -D / 2 - 0.012, z + 0.01))
        keyhole((0, -D / 2 - 0.011, z + 0.03))
    # the upper case: slanted sides, the pigeonholes, the fall-front lying open on its lopers
    for sx in (-1, 1):
        slab([(-0.25, 0.74), (0.25, 0.74), (0.25, H), (0.0, H), (-0.25, 0.8)], 0.03, (sx * (W / 2 - 0.015), 0, 0),
             (90, 0, 90), m="mahogany_v", bevel=0.004)
    box((W, 0.02, H - 0.74), (0, 0.24, (H + 0.74) / 2), m="mahogany_v")
    box((W + 0.02, D * 0.52, 0.025), (0, 0.12, H), m="mahogany_h", bevel=0.005)
    for i in range(6):
        for r in range(2):
            x = -0.4 + i * 0.16
            z = 0.84 + r * 0.1
            box((0.012, 0.18, 0.09), (x - 0.08, 0.13, z), m="mahogany_v")
            if (i + r) % 3 != 1:
                box((0.13, 0.12, 0.07 if r else 0.05), (x, 0.14, z - 0.01), m="letter", bevel=0.004)
    for z in (0.79, 0.89, 0.99):
        box((W - 0.06, 0.18, 0.012), (0, 0.13, z), m="mahogany_h")
    for x in (-0.3, 0.3):
        raised_panel(0.12, 0.04, (x, 0.035, 0.765), m="mahogany_h", t=0.006)
        knob((x, 0.03, 0.765), 0.008)
    for x in (-0.48, 0.48):
        box((0.04, 0.3, 0.03), (x * 0.92, -D / 2 - 0.13, 0.74), m="mahogany_h")         # lopers
    with place(T((0, -D / 2 - 0.13, 0.755))):
        box((W - 0.04, 0.33, 0.025), m="mahogany_h", bevel=0.004)
        box((W - 0.2, 0.25, 0.003), (0, 0, 0.014), m="velvet_green")
        top = 0.016
        box((0.21, 0.28, 0.002), (-0.05, 0.0, top), (0, 0, -6), m="letter")
        for k in range(10):
            box((0.16, 0.002, 0.0005), (-0.05, -0.1 + k * 0.022, top + 0.0012), (0, 0, -6), m="ebony")
        lathe([(0, 0), (0.03, 0), (0.035, 0.03), (0.012, 0.04), (0.012, 0.05), (0, 0.05)], (0.3, 0.08, top), m="crystal",
              n=8)
        q0, q1 = V((0.3, 0.08, top + 0.05)), V((0.235, -0.07, top + 0.21))           # the quill, standing in the ink
        sweep([q0, q1], 0.003, "linen", 4)
        d = (q1 - q0).normalized()
        e = d.to_track_quat("Y", "Z").to_euler()
        with place(T(tuple(q0.lerp(q1, 0.62)), tuple(math.degrees(a) for a in e))):
            slab([(0.0, -0.07), (0.01, -0.04), (0.014, 0.02), (0.008, 0.07), (0.0, 0.085), (-0.006, 0.05),
                  (-0.008, -0.02), (-0.004, -0.06)], 0.002, m="linen")
        for s in (-1, 1):                                             # spectacles
            torus(0.022, 0.0018, (0.08 + s * 0.026, -0.05, top + 0.004), m="gilt", n=10, k=3)
        sweep([(0.075, -0.05, top + 0.004), (0.08, -0.045, top + 0.008), (0.085, -0.05, top + 0.004)], 0.0015,
              "gilt", 3)
        cyl(0.008, 0.08, (-0.33, 0.08, top + 0.008), (90, 0, 70), m="velvet_red", n=6)   # sealing wax
    # on top: an oil lamp and a few books
    with place(T((0.32, 0.12, H + 0.0125))):
        lathe([(0, 0), (0.07, 0), (0.06, 0.02), (0.03, 0.05), (0.08, 0.1), (0.07, 0.16), (0.03, 0.18), (0, 0.18)],
              m="china", n=14)
        lathe([(0, 0.18), (0.03, 0.18), (0.035, 0.2), (0, 0.2)], m="brass", n=12)
        with group("Glass"):
            lathe([(0.03, 0.2), (0.032, 0.24), (0.05, 0.29), (0.032, 0.34), (0.026, 0.42)], m="old_glass", n=12)
            lathe([(0.022, 0.42), (0.028, 0.34), (0.046, 0.29), (0.028, 0.24), (0.026, 0.2)], m="old_glass", n=12)
        with group("Flame"):
            lathe([(0, 0), (0.008, 0.008), (0.009, 0.02), (0.004, 0.035), (0, 0.045)], (0, 0, 0.21), m="flame", n=6)
    rnd = random.Random(4)
    for k in range(3):
        w, d, h = 0.2 - k * 0.02, 0.28 - k * 0.02, 0.04
        box((w, d, h), (-0.25, 0.12, H + 0.0125 + 0.02 + k * 0.04), (0, 0, rnd.uniform(-12, 12)), m=BOOKS[k],
            bevel=0.004)


@piece("Bookcase", close=((1.6, -2.4, 4.6), (0, -0.2, 3.8), 40), tex=2048)
def bookcase():
    """a tall glazed bookcase: a cupboard below, glass doors above over four shelves of old books
    (a gap here and there, one fallen), a moulded cornice"""
    mansion_materials()
    W, D, H = 1.25, 0.42, 2.25
    box((W + 0.04, D + 0.03, 0.1), (0, 0, 0.05), m="mahogany_h", bevel=0.008)
    for sx in (-1, 1):
        box((0.035, D, H - 0.1), (sx * (W / 2 - 0.0175), 0, (H + 0.1) / 2), m="mahogany_v", bevel=0.004)
    box((W, 0.02, H - 0.1), (0, D / 2 - 0.01, (H + 0.1) / 2), m="mahogany_v")
    box((W + 0.06, D + 0.06, 0.04), (0, 0, 0.9), m="mahogany_h", bevel=0.006)         # the waist
    box((W - 0.07, D - 0.01, 0.8), (0, 0.0, 0.5), m="mahogany_v")
    for sx in (-1, 1):
        raised_panel(W / 2 - 0.08, 0.6, (sx * W / 4, -D / 2 - 0.002, 0.5), m="mahogany_v")
        knob((sx * 0.05, -D / 2 - 0.01, 0.62), 0.012)
    keyhole((0.0, -D / 2 - 0.008, 0.55))
    cornice(W, D, H, "mahogany_h")
    rnd = random.Random(12)
    shelves = (0.94, 1.24, 1.54, 1.84)
    for z in shelves + (2.14,):
        box((W - 0.07, D - 0.06, 0.02), (0, 0.01, z - 0.01), m="mahogany_h")
    for z in shelves:
        books_row(-W / 2 + 0.05, W / 2 - 0.05, 0.02, z, D - 0.1, rnd, 0.27)
    # the glazed doors (frames fixed; the panes are Glass)
    for sx in (-1, 1):
        cx = sx * W / 4
        with place(T((cx, -D / 2 - 0.012, 1.52))):
            for x in (-W / 4 + 0.025, W / 4 - 0.025):
                box((0.04, 0.025, 1.22), (x, 0, 0), m="mahogany_v", bevel=0.004)
            for z in (-0.59, 0.59, 0.0):
                box((W / 2 - 0.02, 0.025, 0.04 if z else 0.025), (0, 0, z), m="mahogany_h", bevel=0.004)
            with group("Glass"):
                box((W / 2 - 0.08, 0.004, 1.12), (0, 0.004, 0), m="old_glass")
        knob((sx * 0.04, -D / 2 - 0.025, 1.52), 0.01)


@piece("RockingChair", close=((1.4, -2.2, 2.8), (0, 0, 1.8), 45))
def rocking_chair():
    """a spindle-back rocking chair on its bow rockers, a crocheted shawl left over the back"""
    mansion_materials()
    material("shawl", "cloth", base="#8a5a52", stain=0.2, dusty=0.35, fade=0.1)
    for sx in (-1, 1):
        x = sx * 0.24
        rock = [(x, -0.48 + 0.96 * i / 12, 0.02 + 0.07 * ((i - 6) / 6) ** 2) for i in range(13)]
        sweep(rock, 0.02, "walnut_y", 6)
        lathe(leg_profile(0.42, 0.022), (x, -0.22, 0.03), m="walnut_v", n=8)
        tapered([(x, 0.22, 0.03), (x, 0.24, 0.42), (x * 0.95, 0.32, 0.8), (x * 0.9, 0.38, 1.08)], (0.022, 0.024, 0.02, 0.018),
                "walnut_v", 8, 5)
        sphere(0.025, (x * 0.9, 0.385, 1.1), m="walnut_v", n=8, rings=5)
        sweep([(x, 0.2, 0.62), (x * 1.08, 0.0, 0.64), (x * 1.1, -0.26, 0.62)], 0.018, "walnut_y", 6, bend=0.06)
        cyl(0.012, 0.18, (x * 1.06, -0.22, 0.53), m="walnut_v", n=6)
        for z in (0.12, 0.2):
            cyl(0.01, 0.42, (x, 0.0, z), (90, 0, 0), m="walnut_y", n=6)
    for y in (-0.22, 0.22):
        cyl(0.01, 0.46, (0, y, 0.15), (0, 90, 0), m="walnut_h", n=6)
    slab([(-0.25, -0.22), (0.25, -0.22), (0.24, 0.22), (-0.24, 0.22)], 0.035, (0, 0, 0.44), m="walnut_h", bevel=0.01)
    crest = [(-0.22, 0.38, 1.04), (0, 0.4, 1.08), (0.22, 0.38, 1.04)]
    sweep(crest, 0.025, "walnut_h", 6, bend=0.1)
    sweep([(-0.22, 0.3, 0.66), (0, 0.32, 0.67), (0.22, 0.3, 0.66)], 0.016, "walnut_h", 6, bend=0.1)
    for i in range(7):
        x = -0.18 + i * 0.06
        sweep([(x, 0.3, 0.66), (x * 1.05, 0.36, 0.86), (x * 1.08, 0.39, 1.04)], 0.009, "walnut_v", 5, bend=0.05)
    # the shawl over the back

    def shawl(u, v):
        x = (u - 0.5) * 0.62
        s = v * 0.95
        if s < 0.25:
            y, z = 0.39 - s * 0.6, 1.08 - s * 0.3
        else:
            y, z = 0.42 + (s - 0.25) * 0.08, 1.0 - (s - 0.25) * 0.65 - 0.05 * (abs(x) * 2) ** 2
        return (x + 0.02 * math.sin(v * 9), y + 0.01 * math.sin(u * 20), z)

    def holes(u, v):                                                  # crochet: a grid of little open squares
        return not (int(u * 33) % 3 == 1 and int(v * 27) % 3 == 1 and v > 0.08)
    grid(1, 1, 33, 27, shawl, m="shawl", keep=holes, thick=0.004, rough_edge=0.005, seed=23)


@piece("VanityDresser", close=((1.6, -2.4, 3.4), (0, -0.1, 2.8), 40))
def vanity_dresser():
    """a dressing table: kneehole between two drawer stacks, a swing oval mirror (cracked) between
    turned supports, little trinket drawers; brushes, perfume bottles, a powder jar, pearls,
    a photograph lying face down"""
    mansion_materials()
    cracks = art.cracks_png()
    W, D, H = 1.1, 0.5, 0.74
    box((W, D, 0.035), (0, 0, H - 0.0175), m="mahogany_h", bevel=0.008)
    for sx in (-1, 1):
        cx = sx * (W / 2 - 0.17)
        box((0.32, D - 0.04, H - 0.12), (cx, 0, (H - 0.12) / 2 + 0.08), m="mahogany_v", bevel=0.004)
        for k, z in enumerate((0.58, 0.4, 0.2)):
            raised_panel(0.28, 0.14, (cx, -D / 2 + 0.018, z), m="mahogany_h", t=0.008)
            knob((cx, -D / 2 + 0.006, z), 0.012)
        for sy in (-1, 1):
            lathe([(0, 0), (0.03, 0), (0.035, 0.02), (0.025, 0.05), (0.03, 0.08), (0, 0.08)],
                  (cx + sx * 0.12, sy * (D / 2 - 0.05), 0), m="mahogany_v", n=8)
    raised_panel(W - 0.7, 0.08, (0, -D / 2 + 0.018, H - 0.08), m="mahogany_h", t=0.008)
    # trinket drawers and the mirror
    top = H
    for sx in (-1, 1):
        box((0.22, 0.2, 0.12), (sx * 0.38, 0.1, top + 0.06), m="mahogany_v", bevel=0.005)
        raised_panel(0.18, 0.08, (sx * 0.38, -0.001, top + 0.06), m="mahogany_h", t=0.006)
        knob((sx * 0.38, -0.012, top + 0.06), 0.008)
        lathe([(0, 0), (0.025, 0), (0.02, 0.05), (0.025, 0.2), (0.018, 0.4), (0.022, 0.6), (0.03, 0.63), (0.012, 0.68),
               (0, 0.7)], (sx * 0.29, 0.1, top + 0.12), m="mahogany_v", n=8)
    with place(T((0, 0.1, top + 0.55), (-10, 0, 0))):
        decal("mirror", cracks, here((0, -0.0045, 0), (90, 0, 0)), (0.5, 0.5))
        pts = [(math.cos(2 * math.pi * i / 28) * 0.21, math.sin(2 * math.pi * i / 28) * 0.28) for i in range(28)]
        slab(pts, 0.008, (0, 0, 0), (90, 0, 0), m="mirror")
        sweep([(math.cos(2 * math.pi * i / 28) * 0.22, 0.0, math.sin(2 * math.pi * i / 28) * 0.29) for i in range(28)], 0.02,
              "mahogany_h", 6, closed=True)
        for sx in (-1, 1):
            cyl(0.012, 0.06, (sx * 0.25, 0, 0), (0, 90, 0), m="brass", n=8)
    # what was left on it
    with place(T((-0.15, -0.12, top))):
        box((0.06, 0.18, 0.025), (0, 0, 0.0125), (0, 0, 20), m="walnut_h", bevel=0.008)       # hairbrush
        box((0.05, 0.12, 0.02), (0.005, 0.02, 0.035), (0, 0, 20), m="ebony")
    with place(T((0.18, -0.1, top))):                                                       # perfume bottles
        lathe([(0, 0), (0.03, 0), (0.035, 0.05), (0.01, 0.07), (0.01, 0.09), (0.018, 0.095), (0.012, 0.11), (0, 0.11)],
              m="crystal", n=10)
        lathe([(0, 0), (0.025, 0), (0.025, 0.08), (0.008, 0.09), (0.008, 0.1), (0, 0.11)], (0.07, 0.03, 0), m="old_glass",
              n=8)
        with place(T((-0.06, 0.05, 0.02), (90, 0, 40))):
            lathe([(0, 0), (0.02, 0), (0.022, 0.06), (0.006, 0.075), (0, 0.08)], (0, 0, -0.04), m="crystal", n=8)
    lathe([(0, 0), (0.05, 0), (0.055, 0.05), (0.045, 0.055), (0.05, 0.07), (0.02, 0.085), (0, 0.09)], (0.36, -0.12, top),
          m="china", n=12)
    pearls = [(-0.02 + 0.08 * math.cos(a) * (1 + 0.2 * math.sin(3 * a)), -0.1 + 0.05 * math.sin(a), top + 0.006)
              for a in [2 * math.pi * i / 40 for i in range(40)]]
    for p in pearls[::2]:
        sphere(0.006, p, m="ivory", n=6, rings=3)
    box((0.12, 0.16, 0.012), (-0.36, -0.08, top + 0.006), (0, 0, -15), m="gilt", bevel=0.003)


# ---------------------------------------------------------------- decor and props

@piece("Candelabra", close=((0.7, -1.2, 1.9), (0, 0, 1.6), 45))
def candelabra():
    """a five-light brass candelabra: domed foot, knopped stem, scrolled arms, candles burnt down
    unevenly and dripping wax - still lit"""
    mansion_materials()
    lathe([(0, 0), (0.1, 0), (0.1, 0.01), (0.08, 0.03), (0.05, 0.05), (0.025, 0.07), (0.02, 0.1), (0.032, 0.13),
           (0.018, 0.16), (0.015, 0.3), (0.03, 0.32), (0.016, 0.35), (0.016, 0.42), (0.035, 0.44), (0, 0.45)], m="brass",
          n=12)
    heights = (0.16, 0.09, 0.13, 0.06, 0.11)
    for i in range(5):
        if i == 2:
            x, y, z = 0, 0, 0.45
        else:
            a = math.radians(i * 90 + 45)
            x, y = math.cos(a) * 0.17, math.sin(a) * 0.17
            z = 0.39
            sweep([(0, 0, 0.38), (x * 0.4, y * 0.4, 0.33), (x * 0.85, y * 0.85, 0.33), (x, y, z - 0.02)], 0.008, "brass",
                  6, bend=0.04)
        lathe([(0, 0), (0.04, 0.008), (0.045, 0.016), (0.014, 0.016), (0.014, 0.04), (0, 0.04)], (x, y, z - 0.02),
              m="brass", n=10)
        candle((x, y, z + 0.02), heights[i], flame=True, drips=4, seed=30 + i)


@piece("Chandelier", close=((1.6, -2.6, 2.4), (0, 0, 2.2), 40), tex=2048)
def chandelier():
    """a brass chandelier: ceiling rose, chain, a knopped stem, eight scrolled arms with candles
    (two broken, the rest lit) and drip pans, swags of crystal drops - hang it by the rose; it's
    1.25 m from the ceiling to the bottom finial"""
    mansion_materials()
    T0 = 1.25
    lathe([(0.0, T0 - 0.04), (0.12, T0 - 0.04), (0.13, T0 - 0.02), (0.1, T0), (0, T0)], m="brass", n=16)
    for k in range(10):                                               # the chain, down to the stem
        z = T0 - 0.07 - k * 0.051
        torus(0.022, 0.005, (0, 0, z), (90, 0, 90 * (k % 2)), m="brass", n=8, k=4)
    lathe([(0, 0.0), (0.025, 0.02), (0.06, 0.08), (0.05, 0.12), (0.03, 0.14), (0.04, 0.2), (0.025, 0.24), (0.06, 0.3),
           (0.12, 0.34), (0.12, 0.36), (0.04, 0.38), (0.025, 0.45), (0.04, 0.5), (0.02, 0.58), (0.035, 0.62),
           (0.02, 0.66), (0, 0.68)], m="brass", n=12)
    broken = (2, 5)
    rnd = random.Random(14)
    tips = []
    for i in range(8):
        a = 2 * math.pi * i / 8
        c, s = math.cos(a), math.sin(a)
        R = 0.42
        pts = [(c * 0.11, s * 0.11, 0.35), (c * 0.25, s * 0.25, 0.28), (c * 0.38, s * 0.38, 0.32), (c * R, s * R, 0.44)]
        sweep(pts, 0.011, "brass", 6, bend=0.06)
        sweep([(c * 0.2, s * 0.2, 0.3), (c * 0.22, s * 0.22, 0.2), (c * 0.15, s * 0.15, 0.16)], 0.006, "brass", 5,
              bend=0.03)
        lathe([(0, 0), (0.05, 0.006), (0.055, 0.014), (0.016, 0.014), (0.016, 0.045), (0, 0.045)], (c * R, s * R, 0.44),
              m="brass", n=10)
        tips.append(V((c * R, s * R, 0.44)))
        if i in broken:
            cyl(0.011, 0.025, (c * R, s * R, 0.495), m="wax", n=8)                       # snapped off
        else:
            candle((c * R, s * R, 0.485), rnd.uniform(0.09, 0.16), flame=True, drips=2, seed=40 + i)
    # crystal: drops under every pan, and swags of beads between the arms
    with group("Crystal"):
        for i, t in enumerate(tips):
            for k in range(3):
                sphere(0.012, (t.x, t.y, t.z - 0.03 - k * 0.028), m="crystal", n=4, rings=2, squash=(1, 1, 1.6))
            sphere(0.02, (t.x, t.y, t.z - 0.12), m="crystal", n=4, rings=3, squash=(1, 1, 2.0))
            n_ = tips[(i + 1) % 8]
            for k in range(1, 8):
                f = k / 8
                p = t.lerp(n_, f) * 0.97 - V((0, 0, 0.09 * math.sin(math.pi * f) + 0.03))
                sphere(0.008, tuple(p), m="crystal", n=4, rings=2)
        sphere(0.04, (0, 0, -0.04), m="crystal", n=6, rings=3, squash=(1, 1, 1.5))
    for i in range(3):                                                # cobweb-grey threads of dust hanging off it
        a = rnd.uniform(0, 2 * math.pi)
        sweep([(math.cos(a) * 0.3, math.sin(a) * 0.3, 0.3), (math.cos(a) * 0.31, math.sin(a) * 0.31, 0.15)], 0.0015,
              "linen", 3)


def _ring(cw, ch, o_out, o_in, depth, zc, m):
    """a rectangular ring round the canvas (cw x ch), from o_out outside it to o_in outside it,
    `depth` thick from the wall: four mitred pieces"""
    Wo, Ho, Wi, Hi = cw + 2 * o_out, ch + 2 * o_out, cw + 2 * o_in, ch + 2 * o_in
    for poly in ([(-Wo / 2, -Ho / 2), (Wo / 2, -Ho / 2), (Wi / 2, -Hi / 2), (-Wi / 2, -Hi / 2)],
                 [(-Wo / 2, Ho / 2), (-Wi / 2, Hi / 2), (Wi / 2, Hi / 2), (Wo / 2, Ho / 2)],
                 [(-Wo / 2, -Ho / 2), (-Wi / 2, -Hi / 2), (-Wi / 2, Hi / 2), (-Wo / 2, Ho / 2)],
                 [(Wo / 2, -Ho / 2), (Wo / 2, Ho / 2), (Wi / 2, Hi / 2), (Wi / 2, -Hi / 2)]):
        slab(poly, depth, (0, -depth / 2, zc), (90, 0, 0), m=m, bevel=0.003)


def _framed(img_path, cw, ch, key):
    """an ornate gilt frame round a canvas cw x ch, hung on the wall (back at y = 0), slightly crooked"""
    material(key, "paint", base="#2a2418", chip=0.04, rust=-3.0, peel=-1.0, dirt=0.25, gloss=0.6, streaks=0.0)
    fw = 0.11
    zc = ch / 2 + fw
    with place(T((0, 0, zc), (0, 3, 0))):
        decal(key, img_path, here((0, -0.0175, 0), (90, 0, 0)), (cw, ch))
        kit.UV_BOOST["Canvas"] = 3.0
        with group("Canvas"):
            box((cw + 0.01, 0.01, ch + 0.01), (0, -0.0105, 0), m=key)
        for o_out, o_in, depth in ((fw, 0.0, 0.022), (fw * 0.96, fw * 0.62, 0.05), (fw * 0.55, fw * 0.3, 0.04),
                                   (fw * 0.24, fw * 0.08, 0.06), (fw * 0.08, 0.0, 0.03)):
            _ring(cw, ch, o_out, o_in, depth, 0.0, "gilt")
        for sx in (-1, 1):                                            # carved corner cartouches
            for sz in (-1, 1):
                lump(0.04, (sx * (cw / 2 + fw * 0.55), -0.055, sz * (ch / 2 + fw * 0.55)), m="gilt",
                     seed=2 + sx + 3 * sz, squash=(1.0, 0.35, 1.0), rough=0.25)
        for sz in (-1, 1):                                            # and a shell at the top and bottom middle
            with place(T((0, -0.05, sz * (ch / 2 + fw * 0.55)), (90, 0, 0 if sz > 0 else 180))):
                lathe([(0, 0), (0.06, 0), (0.045, 0.012), (0, 0.016)], m="gilt", n=10, arc=(0, 180))


@piece("PortraitPainting", close=((0.9, -2.4, 2.2), (0, 0, 1.9), 40))
def portrait_painting():
    """an oil portrait of the lady of the house in an ornate gilt frame, hanging crooked; someone
    has scratched her eyes out"""
    mansion_materials()
    _framed(art.portrait_png(), 0.54, 0.72, "canvas_portrait")


@piece("ManorPainting", close=((1.1, -2.8, 1.8), (0, 0, 1.5), 40))
def manor_painting():
    """the house itself at night, in oils: towers and gables on the hill, dead trees, one window lit"""
    mansion_materials()
    _framed(art.manor_png(), 0.78, 0.55, "canvas_manor")


@piece("StandingMirror", close=((1.2, -2.4, 3.6), (0, 0, 3.0), 40))
def standing_mirror():
    """a cheval mirror: an oval glass, foxed and cracked, swinging between turned uprights on
    splayed feet"""
    mansion_materials()
    cracks = art.cracks_png()
    zc = 1.05
    for sx in (-1, 1):
        x = sx * 0.36
        for sy in (-1, 1):
            tapered([(x, 0, 0.12), (x, sy * 0.12, 0.06), (x, sy * 0.24, 0.0)], (0.025, 0.02, 0.016), "mahogany_y", 8, 4)
        lathe([(0, 0), (0.03, 0), (0.035, 0.05), (0.022, 0.1), (0.02, 0.7), (0.03, 0.75), (0.02, 0.8), (0.018, 1.32),
               (0.03, 1.36), (0.012, 1.42), (0, 1.44)], (x, 0, 0.1), m="mahogany_v", n=8)
    cyl(0.015, 0.7, (0, 0, 0.2), (0, 90, 0), m="mahogany_h", n=8)
    with place(T((0, 0, zc), (-8, 0, 0))):
        decal("mirror", cracks, here((0, -0.0065, 0.15), (90, 0, 0)), (0.6, 0.6))
        pts = [(math.cos(2 * math.pi * i / 32) * 0.27, math.sin(2 * math.pi * i / 32) * 0.55) for i in range(32)]
        slab(pts, 0.012, (0, 0, 0), (90, 0, 0), m="mirror")
        sweep([(math.cos(2 * math.pi * i / 32) * 0.285, 0.0, math.sin(2 * math.pi * i / 32) * 0.565) for i in range(32)],
              0.025, "mahogany_h", 6, closed=True)
        box((0.4, 0.015, 0.6), (0, 0.012, 0), m="mahogany_v")
        for sx in (-1, 1):
            cyl(0.02, 0.06, (sx * 0.32, 0, 0), (0, 90, 0), m="brass", n=8)
            sphere(0.025, (sx * 0.35, 0, 0), m="brass", n=8, rings=5)


@piece("PersianRug", close=((1.6, -3.4, 2.6), (0, -0.6, 0.0), 40), tex=2048)
def persian_rug():
    """a worn Persian rug, 2.4 x 1.6 m: medallion and borders, worn pale down the middle, a stain,
    fringes at the ends, one corner kicked over"""
    mansion_materials()
    img = art.rug_png()
    material("rug", "cloth", base="#7a1c1a", stain=0.2, moldy=0.0, dirt=0.3, dusty=0.35, fade=0.0)
    material("fringe", "cloth", base="#c4b494", stain=0.3, dusty=0.4, fade=0.0)
    RW, RL = 1.6, 2.4
    decal("rug", img, here((0, 0, 0.012)), (RW, RL))

    def flat(u, v):
        t = max(0.0, 1 - (u + v) / 0.24)                              # one corner kicked up, curling
        return ((u - 0.5) * RW + 0.04 * t, (v - 0.5) * RL + 0.04 * t,
                0.006 + 0.002 * math.sin(u * 30) * math.sin(v * 25) + 0.14 * t * t)
    grid(RW, RL, 32, 48, flat, m="rug", thick=0.008, smooth=30)
    for end in (-1, 1):
        for i in range(60):
            x = -RW / 2 + 0.03 + i * (RW - 0.06) / 59
            if end < 0 and x < -RW / 2 + 0.25 * RW:
                continue
            ln = 0.06 + 0.02 * math.sin(i * 1.7)
            sweep([(x, end * RL / 2, 0.006), (x + 0.004 * math.sin(i), end * (RL / 2 + ln), 0.003)], 0.003, "fringe", 3)


@piece("Gramophone", close=((1.2, -1.6, 2.4), (0, 0, 1.6), 45))
def gramophone():
    """a horn gramophone: walnut case with its crank, a shellac record on the turntable, the tone
    arm, the big brass flower horn"""
    mansion_materials()
    material("felt", "cloth", base="#2a3a2a", stain=0.3, dusty=0.6, fade=0.0)
    material("shellac", "bakelite", base="#0d0c0c")
    material("record_label", "paint", base="#8a1e1a", chip=0.1, rust=-3, peel=-1, dirt=0.3)
    box((0.36, 0.36, 0.15), (0, 0, 0.085), m="walnut_v", bevel=0.01)
    cornice(0.36, 0.36, 0.16, "walnut_h", [(0, 0), (-0.012, 0), (-0.016, 0.01), (0, 0.014)])
    box((0.38, 0.38, 0.02), (0, 0, 0.01), m="walnut_h", bevel=0.004)
    for sx in (-1, 1):
        for sy in (-1, 1):
            sphere(0.015, (sx * 0.16, sy * 0.16, 0.0), m="walnut_v", n=6, rings=4)
    raised_panel(0.26, 0.09, (0, -0.181, 0.085), m="walnut_v", t=0.006)
    with place(T((0.181, 0.0, 0.09))):                                # the crank
        cyl(0.012, 0.03, (0.015, 0, 0), (0, 90, 0), m="brass", n=8)
        sweep([(0.03, 0, 0), (0.05, 0, 0), (0.05, 0, -0.07), (0.07, 0, -0.07)], 0.005, "brass", 5, bend=0.01)
        cyl(0.01, 0.04, (0.09, 0, -0.07), (0, 90, 0), m="ebony", n=8)
    top = 0.174
    cyl(0.14, 0.012, (-0.02, -0.02, top + 0.006), m="felt", n=18)
    cyl(0.125, 0.004, (-0.02, -0.02, top + 0.014), m="shellac", n=20)
    cyl(0.042, 0.0045, (-0.02, -0.02, top + 0.0145), m="record_label", n=14)
    cyl(0.004, 0.02, (-0.02, -0.02, top + 0.02), m="brass", n=6)
    # the tone arm and the horn
    with place(T((0.13, 0.13, top))):
        cyl(0.025, 0.05, (0, 0, 0.025), m="brass", n=10)
        sweep([(0, 0, 0.05), (-0.05, -0.06, 0.05), (-0.12, -0.12, 0.04)], 0.008, "brass", 6, bend=0.03)
        with place(T((-0.12, -0.12, 0.035))):
            cyl(0.016, 0.02, m="brass", n=8)
        sweep([(0, 0, 0.05), (0, 0.02, 0.15), (0.0, 0.0, 0.25)], 0.02, "brass", 8, bend=0.05)
        with place(T((0.0, 0.0, 0.25), (62, 0, 0))):
            prof = [(0.02, 0.0), (0.03, 0.12), (0.05, 0.25), (0.1, 0.38), (0.19, 0.48), (0.27, 0.53)]
            lathe(prof, m="brass", n=12)
            lathe([(r - 0.004, z) for r, z in prof[::-1]], m="brass", n=12)


@piece("DeadFlowerVase", close=((0.6, -1.0, 1.2), (0, 0, 0.9), 45))
def dead_flower_vase():
    """a blue-and-white china vase of roses left to die: heads blackened and drooping over the rim,
    dry leaves, petals fallen round it"""
    mansion_materials()
    material("dead_rose", "cloth", base="#3a1414", stain=0.3, dusty=0.4, fade=0.0)
    material("dead_leaf", "paper", base="#5a4a2e")
    prof = [(0, 0), (0.05, 0), (0.06, 0.01), (0.05, 0.03), (0.075, 0.1), (0.08, 0.15), (0.05, 0.24), (0.035, 0.28),
            (0.05, 0.31), (0.048, 0.32), (0.03, 0.3), (0, 0.29)]
    lathe(prof, m="china", n=16)

    def r_at(z):                                                      # the vase's radius at a height (outside)
        for (r0, z0), (r1, z1) in zip(prof[1:8], prof[2:9]):
            if z0 <= z <= z1:
                return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
        return 0.05
    for zc, w in ((0.115, 0.012), (0.135, 0.003), (0.195, 0.01), (0.212, 0.003)):     # painted bands, flush
        zs = [zc - w / 2, zc, zc + w / 2]
        lathe([(r_at(z) + 0.0012, z) for z in zs], m="china_blue", n=16)
    rnd = random.Random(31)
    for i in range(7):
        a = 2 * math.pi * i / 7 + rnd.uniform(-0.3, 0.3)
        lean = rnd.uniform(0.6, 1.0)
        h = rnd.uniform(0.18, 0.3)
        p0 = V((math.cos(a) * 0.015, math.sin(a) * 0.015, 0.28))
        p1 = p0 + V((math.cos(a) * 0.04, math.sin(a) * 0.04, h * 0.6))
        p2 = p1 + V((math.cos(a) * 0.08 * lean, math.sin(a) * 0.08 * lean, h * 0.1))
        p3 = p2 + V((math.cos(a) * 0.04 * lean, math.sin(a) * 0.04 * lean, -h * 0.25 * lean))
        sweep(smooth_path([p0, p1, p2, p3], 4), 0.003, "dead_leaf", 4)
        lump(0.025, tuple(p3), m="dead_rose", seed=50 + i, squash=(1, 1, 0.8), rough=0.3)
        for k in range(2):
            q = p0.lerp(p1, 0.4 + 0.3 * k)
            with place(T(tuple(q), (rnd.uniform(-40, 40), rnd.uniform(30, 70), math.degrees(a) + 90 * k))):
                slab([(0, 0), (0.012, 0.02), (0.006, 0.045), (-0.004, 0.035), (-0.008, 0.015)], 0.002, m="dead_leaf")
    for k in range(9):                                                # fallen petals
        a, r = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.1, 0.22)
        with place(T((math.cos(a) * r, math.sin(a) * r, 0.002), (rnd.uniform(-10, 10), 0, rnd.uniform(0, 360)))):
            slab([(0, 0), (0.012, 0.004), (0.014, 0.014), (0.004, 0.016), (-0.004, 0.008)], 0.002, m="dead_rose")
