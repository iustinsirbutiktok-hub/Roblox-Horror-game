# The Butcher's clothes: a long, heavy apron (bib over the chest, wrapped
# round the hips, hanging straight down off the gut to the shins, the hem
# torn), its straps over the shoulders with buckles, the waist ties knotted in
# a bow at the back; the shirt's collar, the rolled-up sleeves, a belt and a
# couple of buttons (the shirt and trousers themselves are painted on the
# body); and big laced work boots.
import bpy, bmesh, math, random
import numpy as np
from mathutils import Vector as V, Matrix, noise
from common import (link, apply_modifiers, select_only, shade_smooth, tube, join, bvh, smoothstep, bezier_points,
                    voxel, smooth, metaball_mesh, meta, ray_out, decimate, blob)
import skeleton as S
import vec as N
from body import BELT_Z, sleeve_end

rnd = random.Random(77)
AXIS = V((0, 0.03, 0))
BIB_TOP, WAIST, HEM = 6.16, 4.72, 1.32
APRON_COLS = 7
APRON_Z = [4.62, 3.8, 3.0, 2.2, 1.35]


def ribbon(name, pts, normals, width, thick=0.012):
    """a flat band through pts, lying on the surface whose normals are given"""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    prev = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        w = width[i] if isinstance(width, (list, tuple)) else width
        side = t.cross(normals[i]).normalized() * (w / 2)
        pair = (bm.verts.new(p + side), bm.verts.new(p - side))
        if prev:
            bm.faces.new((prev[0], prev[1], pair[1], pair[0]))
        prev = pair
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = thick
    sol.offset = 1
    apply_modifiers(obj)
    shade_smooth(obj)
    return obj


def on_surface(tree, pts, lift):
    """pts pressed onto the surface (outside it by lift); returns points and normals"""
    out, nrms = [], []
    for p in pts:
        loc, nn, _, _ = tree.find_nearest(p)
        out.append(loc + nn * lift)
        nrms.append(nn)
    return out, nrms


# ---------------------------------------------------------------- the apron
def apron_span(z):
    """how far round the body the apron reaches at height z (radians either side of the front)"""
    if z >= WAIST:
        # the bib: a front panel, a little wider under the chest
        return math.radians(40 + 10 * smoothstep(BIB_TOP, 5.2, z))
    return math.radians(50 + 105 * smoothstep(WAIST, WAIST - 0.25, z))


def apron(tree):
    cols, rows = 46, 64
    grid = []
    for r in range(rows + 1):
        z = BIB_TOP - (BIB_TOP - HEM) * r / rows
        A = apron_span(z)
        row = []
        for c in range(cols + 1):
            u = c / cols * 2 - 1
            a = u * A
            d = V((math.sin(a), -math.cos(a), 0))
            hit, nrm = ray_out(tree, AXIS + V((0, 0, z)), d)
            rr = (hit - (AXIS + V((0, 0, z)))).length if hit else 0.6
            row.append([a, z, rr, u])
        grid.append(row)
    # drape: below the gut it hangs straight down instead of following the body in
    for c in range(cols + 1):
        best = 0.0
        for r in range(rows + 1):
            a, z, rr, u = grid[r][c]
            off = 0.035 + 0.03 * smoothstep(WAIST, 2.5, z)
            if z < WAIST + 0.1:
                best = max(best * 0.997, rr + off)
                grid[r][c][2] = best + 0.05 * smoothstep(3.0, HEM, z)       # (and flares a little at the hem)
            else:
                grid[r][c][2] = rr + off
    mesh = bpy.data.meshes.new("Apron")
    bm = bmesh.new()
    vgrid = []
    for r in range(rows + 1):
        vr = []
        for c in range(cols + 1):
            a, z, rr, u = grid[r][c]
            p = AXIS + V((math.sin(a) * rr, -math.cos(a) * rr, z))
            # heavy vertical folds hanging from the waist, creases, the canvas buckled
            hang = smoothstep(WAIST, 2.6, z)
            outw = V((math.sin(a), -math.cos(a), 0))
            fold = 0.035 * math.sin(u * 17 + noise.noise(p * 0.8) * 3) * hang
            p += outw * (fold + 0.012 * noise.noise(p * 3) + 0.004 * noise.noise(p * 11))
            vr.append(bm.verts.new(p))
        vgrid.append(vr)
    torn = [rnd.choice((0, 0, 1, 1, 2, 3, 4, 6)) for _ in range(cols)]
    for r in range(rows):
        for c in range(cols):
            if r >= rows - torn[c]:
                continue
            bm.faces.new((vgrid[r][c], vgrid[r][c + 1], vgrid[r + 1][c + 1], vgrid[r + 1][c]))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # the torn hem: ragged, hanging uneven
    for v in bm.verts:
        if v.co.z < HEM + 0.45:
            v.co.z += rnd.uniform(-0.05, 0.05) * smoothstep(HEM + 0.45, HEM, v.co.z)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Apron", mesh))
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    apply_modifiers(obj)
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.022
    sol.offset = 1
    apply_modifiers(obj)
    shade_smooth(obj)

    # bones: seven columns of four hanging from the waist, and the bib
    for ci in range(APRON_COLS):
        u = ci / (APRON_COLS - 1) * 2 - 1
        pts = []
        for z in APRON_Z:
            a = u * apron_span(z) * 0.92
            c = int(round((u * 0.92 + 1) / 2 * cols))
            r = int(round((BIB_TOP - z) / (BIB_TOP - HEM) * rows))
            rr = grid[min(r, rows)][c][2]
            pts.append(AXIS + V((math.sin(a) * rr, -math.cos(a) * rr, z)))
        S.chain("Apron%d_" % (ci + 1), pts, "Root")
    bib = []
    for z in (BIB_TOP - 0.05, 5.5, WAIST + 0.1):
        r = int(round((BIB_TOP - z) / (BIB_TOP - HEM) * rows))
        bib.append(AXIS + V((0, -grid[r][cols // 2][2], z)))
    S.chain("ApronBib_", bib, "Spine4")
    return obj, grid


def straps(tree):
    """over the shoulders from the bib's corners, down the back to the waist ties; buckles at the front"""
    objs = []
    for s, side in ((1, "L"), (-1, "R")):
        ctrl = [V((s * 0.34, -0.5, BIB_TOP - 0.02)), V((s * 0.4, -0.35, 6.48)), V((s * 0.43, -0.05, 6.72)),
                V((s * 0.42, 0.3, 6.5)), V((s * 0.35, 0.55, 5.8)), V((s * 0.3, 0.62, 5.1)),
                V((s * 0.28, 0.62, WAIST + 0.02))]
        pts = bezier_points(ctrl, 6)
        pts, nrms = on_surface(tree, pts, 0.03)
        objs.append(ribbon("Strap" + side, pts, nrms, 0.075, 0.012))
        # a buckle where it meets the bib
        bc = pts[3]
        bn = nrms[3]
        t = (pts[4] - pts[2]).normalized()
        sd = t.cross(bn).normalized()
        ring = [bc + t * (0.055 * math.cos(a)) + sd * (0.06 * math.sin(a)) + bn * 0.012 for a in
                np.linspace(0, 2 * math.pi, 17)]
        objs.append(tube("Buckle", ring, [(0.01, 0.007)] * 17, sides=6, cap=False))
        S.chain("Strap%s_" % side, [pts[0], pts[len(pts) // 3], pts[2 * len(pts) // 3]], "Spine5")
    return objs


def ties(tree):
    """the waist band round the back and a bow at the base of the spine, its ends hanging"""
    objs = []
    pts = []
    for i in range(41):
        a = math.radians(-150 + 300 * i / 40) + math.pi            # round the back
        hit, nrm = ray_out(tree, AXIS + V((0, 0, WAIST)), V((math.sin(a), -math.cos(a), 0)))
        pts.append(hit + nrm * 0.035 if hit else V((math.sin(a) * 0.7, -math.cos(a) * 0.6, WAIST)))
    nrms = [(p - AXIS - V((0, 0, p.z))).normalized() for p in pts]
    objs.append(ribbon("WaistTie", pts, nrms, 0.06, 0.01))
    hit, nrm = ray_out(tree, AXIS + V((0, 0, WAIST)), V((0, 1, 0)))
    knot = hit + nrm * 0.06
    objs.append(blob("Knot", knot, (0.05, 0.035, 0.04), 12))
    for s in (1, -1):
        loop = [knot + V((s * (0.02 + 0.11 * math.sin(a / 2)), 0.02 + 0.02 * math.sin(a), 0.06 * math.sin(a)))
                for a in np.linspace(0, 2 * math.pi, 15)]
        objs.append(tube("BowLoop", loop, [(0.026, 0.008)] * 15, sides=6, cap=False))
    for s, side in ((1, "L"), (-1, "R")):
        tail = [knot, knot + V((s * 0.05, 0.05, -0.18)), knot + V((s * 0.08, 0.06, -0.4)),
                knot + V((s * 0.06, 0.05, -0.62))]
        tail = bezier_points(tail, 4)
        objs.append(tube("TieEnd" + side, tail, [(0.028, 0.007)] * (len(tail) - 1) + [(0.02, 0.005)], sides=6))
        S.chain("Tie%s_" % side, [tail[0], tail[len(tail) // 3], tail[2 * len(tail) // 3], tail[-1]], "Spine1")
        objs[-1]["chain"] = "Tie%s_" % side
    S.b("Bow", knot, knot + V((0, 0.12, 0)), "Spine1")
    return objs


# ---------------------------------------------------------------- the shirt's collar, cuffs, buttons; the belt
def collar(tree):
    objs = []
    pts, nrms = [], []
    for i in range(49):
        a = math.radians(-165 + 330 * i / 48)
        z = 6.66 + 0.05 * (1 - math.cos(a)) / 2
        hit, nrm = ray_out(tree, V((0, 0.03, z)), V((math.sin(a), -math.cos(a), 0)), far=0.6)
        if hit is None:
            continue
        pts.append(hit + nrm * 0.018)
        nrms.append(nrm)
    # a stand of collar round the neck, folding down and out, its points on the chest
    mesh = bpy.data.meshes.new("Collar")
    bm = bmesh.new()
    rows = []
    for k, (h, out) in enumerate(((0.0, 0.0), (0.07, 0.01), (0.075, 0.035), (0.02, 0.07), (-0.05, 0.09))):
        row = []
        for i, (p, nn) in enumerate(zip(pts, nrms)):
            front = max(0, 1 - abs(i - (len(pts) - 1) / 2) / ((len(pts) - 1) / 2))
            tip = 0.06 * front ** 6 if k == 4 else 0
            row.append(bm.verts.new(p + V((0, 0, h - tip)) + nn * out))
        rows.append(row)
    for k in range(len(rows) - 1):
        for i in range(len(pts) - 1):
            bm.faces.new((rows[k][i], rows[k][i + 1], rows[k + 1][i + 1], rows[k + 1][i]))
    bm.to_mesh(mesh)
    bm.free()
    o = link(bpy.data.objects.new("Collar", mesh))
    sol = o.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.01
    apply_modifiers(o)
    shade_smooth(o)
    objs.append(o)
    for s, side in ((1, "L"), (-1, "R")):
        S.b("Collar." + side, V((s * 0.12, -0.22, 6.72)), V((s * 0.16, -0.32, 6.64)), "Spine5")
    return objs


def cuffs(tree):
    objs = []
    for side in ("L", "R"):
        el, fm = S.J["Elbow." + side], S.J["ForeMid." + side]
        axis = (fm - el).normalized()
        x, y = (axis.cross(V((0, 0, 1)))).normalized(), None
        y = axis.cross(x).normalized()
        end = sleeve_end(side)
        rolls = []
        for k, (back, fat) in enumerate(((0.0, 0.05), (0.075, 0.046), (0.14, 0.038))):
            ring = []
            radii = []
            for i in range(33):
                a = 2 * math.pi * i / 32
                d = x * math.cos(a) + y * math.sin(a)
                c = end - axis * back
                hit, nrm, _, _ = tree.ray_cast(c, d, 0.6)
                rr = (hit - c).length if hit else 0.2
                ring.append(c + d * (rr + fat * 0.7 + 0.006 * noise.noise(c * 9 + d * 4)))
                radii.append((fat * 0.55, fat * (0.85 + 0.15 * noise.noise(d * 3 + V((k, 0, 0))))))
            rolls.append(tube("Roll", ring, radii, sides=8, cap=False))
        o = join(rolls, "Cuff." + side)
        shade_smooth(o)
        o["bone"] = "CuffRoll." + side
        S.b("CuffRoll." + side, end - axis * 0.07, end + axis * 0.05, "Forearm1." + side)
        objs.append(o)
    return objs


def belt(tree):
    pts, nrms = [], []
    for i in range(65):
        a = 2 * math.pi * i / 64
        hit, nrm = ray_out(tree, V((0, 0.0, BELT_Z)), V((math.sin(a), -math.cos(a), 0)))
        if hit is None:
            continue
        pts.append(hit + nrm * 0.012)
        nrms.append(nrm)
    o = ribbon("Belt", pts, nrms, 0.1, 0.02)
    # the buckle, under the gut
    p = pts[0]
    buckle = [p + V((0.07 * math.cos(a), -0.02, 0.06 * math.sin(a))) for a in np.linspace(0, 2 * math.pi, 17)]
    b = tube("BeltBuckle", buckle, [(0.012, 0.008)] * 17, sides=6, cap=False)
    S.b("Belt", V((0, -0.3, BELT_Z)), V((0, -0.55, BELT_Z)), "Root")
    o = join([o, b], "Belt")
    o["bone"] = "Belt"
    return o


def buttons(tree):
    objs = []
    for z in (6.3, 6.5):
        hit, nrm = ray_out(tree, V((0, 0.03, z)), V((0, -1, 0)))
        if hit:
            objs.append(tube("Button", [hit + nrm * 0.006, hit + nrm * 0.02], [0.024, 0.022], sides=10))
    return join(objs, "Buttons")


# ---------------------------------------------------------------- boots
def boot_masses(s):
    def build(mb):
        x = s * 0.43
        meta(mb, (x, 0.12, 0.15), (0.18, 0.19, 0.16))                  # heel
        meta(mb, (x + s * 0.01, -0.16, 0.14), (0.19, 0.27, 0.14))      # arch
        meta(mb, (x + s * 0.02, -0.5, 0.13), (0.2, 0.23, 0.13))        # ball
        meta(mb, (x + s * 0.025, -0.75, 0.11), (0.17, 0.14, 0.11))     # round steel toe cap
        meta(mb, (x, 0.02, 0.52), (0.2, 0.21, 0.36))                   # the shaft, up over the trousers
    return build


def boots():
    objs = []
    for s, side in ((1, "L"), (-1, "R")):
        o = metaball_mesh("Boot." + side, boot_masses(s), 0.016)
        voxel(o, 0.012)
        smooth(o, 0.5, 2)
        me = o.data
        P = N.get_co(me)
        Nn = N.get_normals(me)
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        # a thick, flat sole sticking out a little all round; the welt; creases over the toes;
        # the shaft's top opening rolled; scuffed leather
        sole = z < 0.075
        P[:, 2] = np.where(z < 0.012, 0.0, z)
        out = Nn.copy()
        out[:, 2] = 0
        out /= np.maximum(np.linalg.norm(out, axis=1), 1e-6)[:, None]
        push = sole * 0.022
        push += 0.008 * np.exp(-((z - 0.085) / 0.01) ** 2)                      # the welt
        cre = (y < -0.25) & (y > -0.6) & (z > 0.12)
        push += cre * 0.006 * np.sin(y * 70 + N.noise(P * 6, 2) * 3)
        push += 0.003 * N.fbm(P * 20, 3, 4)
        P += out * push[:, None] * (1 - 0.0 * sole[:, None])
        P += Nn * (0.003 * N.noise(P * 50, 5))[:, None]
        N.set_co(me, P)
        # laces criss-crossing up the front of the shaft
        tree = bvh(o)
        laces = []
        for k in range(6):
            zz = 0.22 + k * 0.09
            yy = -0.13 - 0.12 * (1 - k / 5)
            for flip in (1, -1):
                a = V((s * 0.43 + 0.06 * flip, yy - 0.1, zz))
                b = V((s * 0.43 - 0.06 * flip, yy - 0.1, zz + 0.07))
                pa, _ = ray_out(tree, a + V((0, 0.2, 0)), V((0, -1, 0)), far=0.6)
                pb, _ = ray_out(tree, b + V((0, 0.2, 0)), V((0, -1, 0)), far=0.6)
                if pa and pb:
                    laces.append(tube("Lace", [pa + V((0, -0.008, 0)), (pa + pb) / 2 + V((0, -0.016, 0)),
                                               pb + V((0, -0.008, 0))], [0.008, 0.008, 0.008], sides=5))
        o = join([o] + laces, "Boot." + side)
        shade_smooth(o)
        o["side"] = side
        S.b("BootTop." + side, V((s * 0.43, 0.02, 0.45)), V((s * 0.43, 0.02, 0.7)), "Shin2." + side)
        objs.append(o)
    return objs
