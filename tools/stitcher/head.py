# The Stitcher's head: a gaunt, starved face with deep black eye sockets and
# small pale eyes sunk in them, and a grin carved from ear to ear - no lips
# left, two long crooked rows of teeth, the ends of the cut sewn up with
# thick black stitches. A stained surgical cap, wet black hair hanging out from
# under it in strings, and a bloody mask pulled down round its chin.
import bpy, bmesh, math, random
from mathutils import Vector as V, Matrix, noise
from common import (link, apply_modifiers, select_only, decimate, shade_smooth, blob, voxel, smooth, join, tube,
                    bvh, smoothstep, bezier_points)
import skeleton as S

rnd = random.Random(1313)
HC = S.HC
AXIS_Y = HC.y - 0.02            # the head's vertical axis (for angles round the face)

# ---------------------------------------------------------------- the grin, as a curve round the face
GRIN_MAX = math.radians(70)     # where the open mouth ends...
SLIT_MAX = math.radians(96)     # ...and the sewn-up cut runs on to
Z0 = HC.z - 0.27


def phi_of(p):
    return math.atan2(p.x, -(p.y - AXIS_Y))


def grin_z(phi):
    a = min(abs(phi) / GRIN_MAX, 1.4)
    return Z0 + 0.15 * a ** 1.7


def grin_h(phi):
    """half the height of the open mouth at phi"""
    a = abs(phi) / GRIN_MAX
    if a <= 1:
        return 0.011 + 0.042 * (1 - a ** 1.6)
    return max(0.0, 0.011 * (1 - (abs(phi) - GRIN_MAX) / (SLIT_MAX - GRIN_MAX)))


def grin_depth(phi):
    a = abs(phi) / GRIN_MAX
    if a <= 1:
        return 0.035 + 0.085 * (1 - a ** 2)
    return 0.025


def cap_z(phi):
    a = abs(phi) / math.pi
    return 8.27 - 0.06 * min(a * 2, 1) ** 1.5 - 0.22 * max(0.0, a * 2 - 1) ** 1.3


def radial(p):
    r = V((p.x, p.y - AXIS_Y, 0))
    return r.normalized() if r.length > 1e-5 else V((0, -1, 0))


# ---------------------------------------------------------------- the skull and face
def meta(mb, centre, semi, rot=None, negative=False, stiffness=2.0):
    """an ellipsoid metaball element whose surface (on its own) has these semi-axes"""
    e = mb.elements.new()
    e.type = "ELLIPSOID"
    e.co = centre
    r = max(semi) / 0.573
    e.radius = r
    e.size_x, e.size_y, e.size_z = (x / (0.573 * r) for x in semi)
    e.stiffness = stiffness
    e.use_negative = negative
    if rot is not None:
        e.rotation = rot.to_quaternion()
    return e


def head_shape():
    """the skull and face as blended metaballs (flesh, not lumps), carved sockets"""
    c = HC
    mb = bpy.data.metaballs.new("HeadMeta")
    mb.resolution = mb.render_resolution = 0.011
    mb.threshold = 0.6
    rx = lambda deg: Matrix.Rotation(math.radians(deg), 3, "X")
    meta(mb, c + V((0, 0.05, 0.1)), (0.245, 0.285, 0.275))            # cranium
    meta(mb, c + V((0, 0.17, -0.02)), (0.195, 0.15, 0.2))              # back of the skull
    meta(mb, c + V((0, -0.11, -0.08)), (0.175, 0.2, 0.26))             # face
    meta(mb, c + V((0, -0.245, 0.075)), (0.185, 0.065, 0.04))          # brow ridge
    for s in (1, -1):
        meta(mb, c + V((s * 0.14, -0.22, -0.02)), (0.05, 0.065, 0.032))    # cheekbones
        meta(mb, c + V((s * 0.19, -0.1, -0.03)), (0.03, 0.11, 0.028))      # cheek arches back to the ears
        meta(mb, c + V((s * 0.13, -0.11, -0.31)), (0.04, 0.165, 0.06), rot=rx(-28))   # jawbone
        meta(mb, c + V((s * 0.24, 0.0, -0.03)), (0.022, 0.05, 0.075))      # ears
        meta(mb, c + V((s * 0.1, -0.33, 0.005)), (0.058, 0.07, 0.048), negative=True)  # eye sockets
    meta(mb, c + V((0, -0.2, -0.27)), (0.135, 0.13, 0.11))             # muzzle (round the teeth)
    meta(mb, c + V((0, -0.25, -0.43)), (0.068, 0.055, 0.055))          # chin
    meta(mb, c + V((0, -0.325, -0.03)), (0.02, 0.042, 0.075), rot=rx(-12))   # nose bridge
    meta(mb, c + V((0, -0.35, -0.1)), (0.025, 0.026, 0.024))           # (short, rotted) nose tip
    meta(mb, c + V((0, 0.03, -0.5)), (0.08, 0.084, 0.2))               # neck
    ob = link(bpy.data.objects.new("HeadMeta", mb))
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    obj = link(bpy.data.objects.new("Head", mesh))
    voxel(obj, 0.0095)
    smooth(obj, 0.5, 2)
    return obj


def sculpt_face(obj):
    for v in obj.data.vertices:
        p = v.co.copy()
        push = V((0, 0, 0))
        phi = phi_of(p)
        rd = radial(p)
        front = p.y < HC.y - 0.12
        # --- eye sockets: deep, steep pits; dark rings round them
        for side, s in (("L", 1), ("R", -1)):
            sx, sz = HC.x + s * 0.1, HC.z + 0.0
            dx, dz = (p.x - sx) / 0.074, (p.z - sz) / 0.058
            r2 = dx * dx + dz * dz
            if r2 < 1 and front:
                push += V((0, 1, 0)) * 0.05 * (1 - r2) ** 0.8
        # --- sunken cheeks under the cheekbones, hollow temples
        for s in (1, -1):
            d = (p - (HC + V((s * 0.15, -0.27, -0.16)))).length
            if d < 0.1:
                push -= rd * 0.04 * (1 - d / 0.1) ** 1.5
            d = (p - (HC + V((s * 0.24, -0.12, 0.1)))).length
            if d < 0.09:
                push -= rd * 0.025 * (1 - d / 0.09)
        # --- the grin: a groove carved round the face, ear to ear
        if abs(phi) < SLIT_MAX and p.y < HC.y + 0.15:
            h = grin_h(phi)
            dz = p.z - grin_z(phi)
            if h > 0 and abs(dz) < h:
                u = abs(dz) / h
                push -= rd * grin_depth(phi) * (1 - u * u) ** 0.5
            elif h > 0 and abs(dz) < h + 0.022 and abs(phi) < GRIN_MAX:
                # what's left of the lips: a raw, swollen edge
                push += rd * 0.009 * (1 - (abs(dz) - h) / 0.022)
        # --- nostrils: two pits under a thin, rotted nose
        for s in (1, -1):
            d = (p - (HC + V((s * 0.018, -0.405, -0.125)))).length
            if d < 0.022:
                push += V((0, 0.6, 0.6)) * 0.022 * (1 - d / 0.022)
        # --- skin: lumpy, starved
        push += rd * 0.003 * noise.noise(p * 40)
        v.co = p + push


# ---------------------------------------------------------------- teeth
def teeth(tree, upper):
    """a long row of crooked teeth along one edge of the grin"""
    mesh = bpy.data.meshes.new("Teeth")
    bm = bmesh.new()
    count = 30
    for i in range(count):
        a = (i / (count - 1) - 0.5) * 2 * GRIN_MAX * 0.98
        if rnd.random() < 0.08:
            continue                                         # gaps where teeth are gone
        h = grin_h(a)
        z = grin_z(a) + (h * 0.92 if upper else -h * 0.92)
        o = V((0, AXIS_Y, z))
        d = V((math.sin(a), -math.cos(a), 0))
        hit, nrm, _, _ = tree.ray_cast(o, d, 1.0)
        if hit is None:
            continue
        base = hit - d * (grin_depth(a) * 0.42)
        ln = (0.03 + h * 1.25) * rnd.uniform(0.8, 1.25)
        if rnd.random() < 0.12:
            ln *= 1.45                                       # a few long, fang-like ones
        w = rnd.uniform(0.014, 0.02) * (1 - 0.3 * abs(a) / GRIN_MAX)
        r = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=7, radius1=w, radius2=w * 0.42,
                                  depth=ln)
        verts = r["verts"]
        # crooked: tilted every which way, flattened front to back
        bmesh.ops.scale(bm, vec=V((1, 0.62, 1)), verts=verts)
        tilt = Matrix.Rotation(rnd.uniform(-0.2, 0.2), 4, "Y") @ Matrix.Rotation(rnd.uniform(-0.15, 0.25), 4, "X")
        bmesh.ops.transform(bm, matrix=tilt, verts=verts)
        bmesh.ops.translate(bm, vec=V((0, 0, ln / 2)), verts=verts)
        if upper:
            bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.pi, 4, "X"), verts=verts)
        bmesh.ops.transform(bm, matrix=Matrix.Rotation(a, 4, "Z"), verts=verts)
        bmesh.ops.translate(bm, vec=base, verts=verts)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("UpperTeeth" if upper else "LowerTeeth", mesh))
    shade_smooth(obj)
    return obj


def stitches(tree):
    """thick black thread sewn in crosses over the ends of the cut"""
    objs = []
    for s in (1, -1):
        k = 0
        a = GRIN_MAX - math.radians(8)
        while a < SLIT_MAX - math.radians(3):
            phi = s * a
            zc = grin_z(phi)
            gap = 0.03
            for dz0, dz1, da in ((gap, -gap, math.radians(4)), (gap, -gap, -math.radians(4))):
                pts = []
                for t in (0.0, 0.5, 1.0):
                    ph = phi + s * da * (t - 0.5) * 2
                    z = zc + dz0 + (dz1 - dz0) * t
                    o = V((0, AXIS_Y, z))
                    d = V((math.sin(ph), -math.cos(ph), 0))
                    hit, nrm, _, _ = tree.ray_cast(o, d, 1.0)
                    if hit is None:
                        break
                    # dug into the skin at the ends, standing proud over the cut
                    lift = 0.006 if t == 0.5 else -0.002
                    pts.append(hit + nrm * lift)
                if len(pts) == 3:
                    objs.append(tube("Stitch", pts, [0.0045, 0.005, 0.0045], sides=4))
            a += math.radians(5.5)
            k += 1
    return join(objs, "Stitches")


def eyes():
    objs = []
    for side in ("L", "R"):
        e = blob("Eye." + side, S.EYE[side], (0.04, 0.04, 0.04), 14)
        e["bone"] = "Eye." + side
        objs.append(e)
    return objs


# ---------------------------------------------------------------- the cap
def cap(tree):
    mesh = bpy.data.meshes.new("Cap")
    bm = bmesh.new()
    segs, rings = 44, 11
    grid = []
    for r in range(rings):
        u = r / (rings - 1) * 0.94
        row = []
        for i in range(segs):
            phi = -math.pi + 2 * math.pi * i / segs
            z_edge = cap_z(phi)
            el0 = math.asin(max(-0.9, min(0.9, (z_edge - HC.z) / 0.31)))
            el = el0 + (math.pi / 2 - el0) * u
            d = V((math.sin(phi) * math.cos(el), -math.cos(phi) * math.cos(el), math.sin(el)))
            o = HC + V((0, 0.03, 0.05))
            hit, nrm, _, _ = tree.ray_cast(o, d, 1.0)
            if hit is None:
                hit = o + d * 0.32
                nrm = d
            # baggy: loose over the top and the back, the hem rolled thick
            puff = 0.012 + 0.04 * math.sin(u * math.pi / 0.94 * 0.5) + 0.03 * max(0, -math.cos(phi)) * u
            if r == 0:
                puff = 0.007
            if r == 1:
                puff = 0.02
            # creases: gathered in towards the knot at the back, rumpled on top
            crease = abs(noise.noise(V((phi * 2.2, u * 3.0, 0.3)))) * 0.025 * min(1, u * 3)
            wr = noise.noise(hit * 7) * 0.012 + noise.noise(hit * 19) * 0.004 - crease
            row.append(bm.verts.new(hit + nrm * (puff + wr)))
        grid.append(row)
    for r in range(rings - 1):
        for i in range(segs):
            bm.faces.new((grid[r][i], grid[r][(i + 1) % segs], grid[r + 1][(i + 1) % segs], grid[r + 1][i]))
    top = bm.verts.new(sum((v.co for v in grid[-1]), V()) / segs + V((0, 0, 0.01)))
    for i in range(segs):
        bm.faces.new((grid[-1][i], grid[-1][(i + 1) % segs], top))
    # the hem tucked under
    tuck = [bm.verts.new(v.co + (HC - v.co).normalized() * 0.018 + V((0, 0, 0.012))) for v in grid[0]]
    for i in range(segs):
        bm.faces.new((tuck[i], tuck[(i + 1) % segs], grid[0][(i + 1) % segs], grid[0][i]))
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Cap", mesh))
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    apply_modifiers(obj)
    shade_smooth(obj)

    # the knot at the back and its two tails
    back = HC + V((0, 0.36, -0.07))
    knot = blob("Knot", back, (0.05, 0.035, 0.04), 12)
    tails = []
    for s, side in ((1, "L"), (-1, "R")):
        pts = [back + V((s * 0.02, 0.0, -0.01)), back + V((s * 0.06, 0.03, -0.12)), back + V((s * 0.08, 0.04, -0.25)),
               back + V((s * 0.07, 0.03, -0.37))]
        pts = bezier_points([V(p) for p in pts], 4)
        t = tube("CapTie" + side, pts, [(0.03, 0.006)] * (len(pts) - 1) + [(0.024, 0.005)], sides=6)
        t["chain"] = "CapTie" + side + "_"
        tails.append(t)
        S.chain("CapTie" + side + "_", [S.head_xf(p) for p in (pts[0], pts[len(pts) // 2], pts[-1])], "Cap")
    return obj, knot, tails


# ---------------------------------------------------------------- hair: wet black strings
HAIR_CLUMPS = [  # (angle round the head, how long, how many strands)
    (-40, 0.4, 5), (-50, 0.5, 5), (52, 0.52, 5), (42, 0.46, 5),
    (-62, 0.62, 8), (64, 0.66, 8), (-86, 0.74, 8), (88, 0.7, 8),
    (-114, 0.68, 8), (116, 0.7, 8), (-145, 0.6, 8), (146, 0.62, 8), (180, 0.56, 7),
]


def hair(tree):
    objs = []
    for ci, (deg, length, count) in enumerate(HAIR_CLUMPS):
        phi0 = math.radians(deg)
        strands = []
        for k in range(count):
            phi = phi0 + math.radians(rnd.uniform(-7, 7))
            z = cap_z(phi) + 0.01
            o = V((0, AXIS_Y + 0.02, z))
            d = V((math.sin(phi), -math.cos(phi), 0))
            hit, nrm, _, _ = tree.ray_cast(o, d, 1.0)
            if hit is None:
                continue
            ln = length * rnd.uniform(0.75, 1.15)
            out = V((d.x, d.y, 0)).normalized()
            side = V((-out.y, out.x, 0))
            pts = []
            n = 12
            for i in range(n + 1):
                t = i / n
                # (from under the cap's hem, easing out off the skin as it falls)
                p = hit - out * 0.012 + out * (0.05 * smoothstep(0.0, 0.45, t)) + V((0, 0, -ln * t - 0.02))
                p += side * 0.025 * noise.noise(V((ci * 3.1 + k, t * 3, 0.5))) * t
                p += out * 0.012 * noise.noise(V((ci * 1.7 + k, t * 4, 2.5))) * t
                pts.append(p)

            def push_out(pts):
                for i in range(1, len(pts)):
                    loc, nn, _, dist = tree.find_nearest(pts[i])
                    if loc is not None and ((pts[i] - loc).dot(nn) < 0 or dist < 0.016):
                        pts[i] = loc + nn * 0.016

            # keep it outside the face and skull, and hanging smoothly
            for _ in range(3):
                push_out(pts)
                pts = [pts[0]] + [(pts[i - 1] + pts[i] * 2 + pts[i + 1]) / 4 for i in range(1, n)] + [pts[-1]]
            push_out(pts)
            r0 = rnd.uniform(0.007, 0.011)
            radii = [r0 * (0.55 + 0.45 * smoothstep(0.0, 0.15, i / n)) * (1 - 0.85 * (i / n) ** 1.3) for i in range(n + 1)]
            st = tube("Strand", pts, radii, sides=3, cap=False, twist=0.4)
            strands.append((st, pts))
        if not strands:
            continue
        # a three-bone chain down the middle of the clump
        mean = [sum((s[1][i] for s in strands), V()) / len(strands) for i in range(13)]
        name = "Hair%02d_" % (ci + 1)
        S.chain(name, [S.head_xf(mean[i]) for i in (0, 4, 8, 12)], "Head")
        clump = join([s[0] for s in strands], "Hair%02d" % (ci + 1))
        clump["chain"] = name
        clump["chain_pts"] = [list(mean[0]), list(mean[12])]
        objs.append(clump)
    return objs


# ---------------------------------------------------------------- the mask, pulled down round the chin
def mask(tree):
    mesh = bpy.data.meshes.new("Mask")
    bm = bmesh.new()
    cols, rows = 16, 8
    grid = []
    for r in range(rows + 1):
        v = r / rows
        row = []
        for i in range(cols + 1):
            u = i / cols - 0.5
            phi = u * math.radians(165)
            z_top = 7.745 + 0.06 * (abs(u) * 2) ** 2
            z = z_top - v * 0.3
            o = V((0, AXIS_Y + 0.05, z_top))
            d = V((math.sin(phi), -math.cos(phi), 0))
            hit, nrm, _, _ = tree.ray_cast(o, d, 1.0)
            if hit is None:
                hit = o + d * 0.25
            p = hit + d * 0.014
            # pulled down under the chin, stretched tight back to the throat
            p = p + V((0, 0, z - z_top)) - d * (v * 0.2)
            # pleats and creases
            p += d * (0.007 * math.sin(v * math.pi * 3.2) + 0.004 * noise.noise(V((u * 5, v * 5, 1.0))))
            loc, nn, _, dist = tree.find_nearest(p)
            if loc is not None and ((p - loc).dot(nn) < 0 or dist < 0.013):
                p = loc + nn * 0.013
            row.append(bm.verts.new(p))
        grid.append(row)
    for r in range(rows):
        for i in range(cols):
            # torn: a ragged notch up from the bottom, one corner gone
            if r >= rows - 2 and 9 <= i <= 10:
                continue
            if r >= rows - 1 and i in (2, 3, 13):
                continue
            bm.faces.new((grid[r][i], grid[r][i + 1], grid[r + 1][i + 1], grid[r + 1][i]))
    corners = {1: grid[0][cols].co.copy(), -1: grid[0][0].co.copy()}
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Mask", mesh))
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.01
    apply_modifiers(obj)
    shade_smooth(obj)
    # the ear loops, up round behind the ears
    loops = []
    for s in (1, -1):
        a = corners[s]
        pts = [a, HC + V((s * 0.26, -0.08, -0.2)), HC + V((s * 0.285, 0.03, -0.06)), HC + V((s * 0.25, 0.08, 0.02))]
        pts = bezier_points([V(p) for p in pts], 4)
        loops.append(tube("Loop", pts, [0.006] * len(pts), sides=4))
    return join([obj] + loops, "Mask")


def build():
    head = head_shape()
    plain_tree = bvh(head)
    sculpt_face(head)
    head.data.update()
    tree = bvh(head)
    decimate(head, 7000)
    shade_smooth(head)
    parts = {"Head": head}
    parts["UpperTeeth"] = teeth(plain_tree, True)
    parts["LowerTeeth"] = teeth(plain_tree, False)
    parts["Stitches"] = stitches(tree)
    e = eyes()
    parts["Eye.L"], parts["Eye.R"] = e
    c, knot, tails = cap(tree)
    parts["Cap"] = join([c, knot], "Cap")
    for t in tails:
        parts[t.name] = t
    for h in hair(tree):
        parts[h.name] = h
    parts["Mask"] = mask(tree)
    # designed at its own size round HC: now scaled up and set on the neck
    for o in parts.values():
        o.data.transform(S.HEAD_M)
        o.data.update()
    return parts


# ---------------------------------------------------------------- skinning rules for the face
def face_weights(p):
    """bone -> weight for a point on the head/face"""
    phi = phi_of(p)
    w = {}
    zc = grin_z(phi)
    # the jaw takes everything under the grin, in front of the ears
    front = smoothstep(math.radians(112), math.radians(80), abs(phi))
    below = smoothstep(zc + 0.012, zc - 0.035, p.z)
    jaw = front * below
    # (the throat at the back stays on the neck)
    neck = smoothstep(7.72, 7.55, p.z) * smoothstep(-0.2, -0.05, p.y)
    jaw *= 1 - neck
    w["Jaw"] = jaw
    w["Neck4"] = neck
    w["Head"] = max(0.0, 1 - jaw - neck)

    def take(bone, amount, frm):
        amount = min(amount, w.get(frm, 0))
        if amount > 0:
            w[frm] -= amount
            w[bone] = w.get(bone, 0) + amount

    for side, s in (("L", 1), ("R", -1)):
        # the brow over each socket
        d = (p - (HC + V((s * 0.1, -0.3, 0.085)))).length
        take("Brow." + side, 0.8 * max(0, 1 - d / 0.08) ** 1.5, "Head")
        # the cheek
        d = (p - (HC + V((s * 0.15, -0.26, -0.12)))).length
        take("Cheek." + side, 0.7 * max(0, 1 - d / 0.11) ** 1.5, "Head")
        # the corners of the grin, both lips
        if s * phi > 0:
            amt = 0.75 * max(0, 1 - abs(abs(phi) - GRIN_MAX * 0.85) / math.radians(28)) * max(0, 1 - abs(p.z - zc) / 0.08)
            hw, jw = w.get("Head", 0), w.get("Jaw", 0)
            frac = hw / max(hw + jw, 1e-6)
            take("MouthCorner." + side, amt * frac, "Head")
            take("MouthCorner." + side, amt * (1 - frac), "Jaw")
    # the lips' edges
    if abs(phi) < GRIN_MAX:
        h = grin_h(phi)
        up = max(0, 1 - abs(p.z - (zc + h + 0.01)) / 0.035) * (1 - abs(phi) / GRIN_MAX)
        take("UpperLip", 0.8 * up, "Head")
        lo = max(0, 1 - abs(p.z - (zc - h - 0.01)) / 0.035) * (1 - abs(phi) / GRIN_MAX)
        take("LowerLip", 0.8 * lo, "Jaw")
    return {k: v for k, v in w.items() if v > 0.01}
