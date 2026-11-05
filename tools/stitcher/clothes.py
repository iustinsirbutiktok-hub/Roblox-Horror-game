# The Stitcher's clothes: a long surgical gown down to its shins (stiff with
# blood, torn open over the ribs, a flap of it hanging off the hole, the hem
# shredded), sleeves to below the elbow, ties at the neck and waist at the
# back, old leather shoes, and filthy bandages wound round both wrists.
import bpy, bmesh, math, random
from mathutils import Vector as V, Matrix, noise
from common import (link, apply_modifiers, select_only, shade_smooth, tube, join, bvh, smoothstep, bezier_points,
                    voxel, smooth)
import skeleton as S
from body import wound_e
from head import meta

rnd = random.Random(404)

TOP, HEM = 6.9, 1.35
SKIRT_COLS = [("F", 0), ("FL", 45), ("L", 90), ("BL", 135), ("B", 180), ("BR", -135), ("R", -90), ("FR", -45)]
SKIRT_Z = [4.45, 3.4, 2.4, 1.25]


def skirt_shape(a, z):
    """the loose oval the skirt hangs in at height z (a: 0 = front, + = its left)"""
    flare = 1 + 0.12 * smoothstep(4.3, 1.3, z)
    rx = 0.6 * flare
    ry = 0.43 * flare
    # (gathered in round the neck at the top, so it wraps up the throat as a collar)
    collar = smoothstep(6.45, 6.85, z)
    rx += (0.14 - rx) * collar
    ry += (0.15 - ry) * collar
    return V((math.sin(a) * rx, -math.cos(a) * ry + 0.03, z))


def gown(body):
    from body import torso_proxy
    proxy = torso_proxy()
    seg, rows = 44, 40
    mesh = bpy.data.meshes.new("Gown")
    bm = bmesh.new()
    grid = []
    for r in range(rows + 1):
        z = TOP - (TOP - HEM) * r / rows
        row = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            row.append(bm.verts.new(skirt_shape(a, z)))
        grid.append(row)
    for r in range(rows):
        for i in range(seg):
            a = 2 * math.pi * (i + 0.5) / seg
            z = TOP - (TOP - HEM) * (r + 0.5) / rows
            side = abs(math.sin(a))
            if 5.15 < z < 6.8 and math.cos(a) < -0.975:
                continue                                       # gaping open down its spine
            bm.faces.new((grid[r][i], grid[r][(i + 1) % seg], grid[r + 1][(i + 1) % seg], grid[r + 1][i]))
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Gown", mesh))

    # hugging the body above the hips, hanging free below them
    vg = obj.vertex_groups.new(name="wrap")
    for v in mesh.vertices:
        vg.add([v.index], smoothstep(4.25, 4.9, v.co.z), "REPLACE")
    sw = obj.modifiers.new("Wrap", "SHRINKWRAP")
    sw.target = proxy
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.offset = 0.04
    sw.vertex_group = "wrap"
    apply_modifiers(obj)
    obj.vertex_groups.remove(obj.vertex_groups["wrap"])
    bpy.data.objects.remove(proxy)

    # the hole torn over its ribs, the shredded hem, a few rips
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    doomed = set()
    for f in bm.faces:
        c = f.calc_center_median()
        if wound_e(c, 0.04) < 1.0:
            doomed.add(f)
    cols = {}
    for f in bm.faces:
        c = f.calc_center_median()
        a = math.atan2(c.x, -(c.y - 0.03))
        k = int((a + math.pi) / (2 * math.pi) * seg) % seg
        cols.setdefault(k, []).append(f)
    for k, fs in cols.items():
        torn = HEM + rnd.choice((0, 0, 0.05, 0.12, 0.2, 0.28, 0.4))
        for f in fs:
            if f.calc_center_median().z < torn:
                doomed.add(f)
    bmesh.ops.delete(bm, geom=list(doomed), context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()

    # folds: sagging verticals in the skirt, creases bunched at the waist tie, all of it rumpled
    mesh = obj.data
    for v in mesh.vertices:
        p = v.co
        a = math.atan2(p.x, -(p.y - 0.03))
        out = V((p.x, p.y - 0.03, 0))
        out = out.normalized() if out.length > 1e-4 else V((0, 0, 0))
        hang = smoothstep(4.7, 3.6, p.z)
        folds = 0.045 * math.sin(a * 9 + noise.noise(p * 0.7) * 2.5) * hang
        waist = 0.02 * math.sin(a * 16) * max(0, 1 - abs(p.z - 5.0) / 0.25)
        rumple = noise.noise(p * 3.0) * 0.022 + noise.noise(p * 8.0) * 0.007
        jitter = V((noise.noise(p * 6 + V((3, 0, 0))), noise.noise(p * 6 + V((0, 5, 0))),
                    noise.noise(p * 6 + V((0, 0, 9))))) * 0.02
        v.co = p + out * (folds + waist + rumple) + jitter
        if p.z < 2.0:
            v.co.z += rnd.uniform(-0.04, 0.06)
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.014
    sol.offset = 1
    apply_modifiers(obj)
    shade_smooth(obj)
    return obj


def flap(body):
    """a torn piece of the gown hanging off the bottom of the hole"""
    tree = bvh(body)
    top = []
    for k in range(7):
        x = -0.2 + k * 0.05
        z = 5.53 + 0.03 * math.sin(k * 1.7)
        hit, nrm, _, _ = tree.ray_cast(V((x, 0.06, z)), V((0, -1, 0)), 2.0)
        top.append(hit + nrm * 0.045 if hit else V((x, -0.25, z)))
    mesh = bpy.data.meshes.new("Flap")
    bm = bmesh.new()
    rows = 6
    grid = []
    for r in range(rows + 1):
        t = r / rows
        row = []
        for k, p in enumerate(top):
            w = 1 - 0.7 * t * abs(k - 3) / 3
            q = p + V((0, -0.06 * t - 0.02 * math.sin(t * 3), -0.32 * t))
            q.x = top[3].x + (p.x - top[3].x) * w
            row.append(bm.verts.new(q + V((0, 0.01 * noise.noise(q * 9), 0))))
        grid.append(row)
    for r in range(rows):
        for k in range(len(top) - 1):
            if r == rows - 1 and k in (0, 5):
                continue
            bm.faces.new((grid[r][k], grid[r][k + 1], grid[r + 1][k + 1], grid[r + 1][k]))
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Flap", mesh))
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.012
    apply_modifiers(obj)
    shade_smooth(obj)
    mid = [top[3], top[3] + V((0, -0.05, -0.16)), top[3] + V((0, -0.08, -0.32))]
    S.chain("GownFlap_", mid, "Spine3")
    obj["chain"] = "GownFlap_"
    return obj


def sleeves():
    objs = []
    for side, s in (("L", 1), ("R", -1)):
        sh, mid, el, fm = (S.J[n + "." + side] for n in ("Shoulder", "UpperMid", "Elbow", "ForeMid"))
        d = (el - sh).normalized()
        start = sh + d * 0.03
        end = el + (fm - el).normalized() * 0.28
        pts = bezier_points([start, sh + d * 0.25, mid, el, end], 4)
        radii = []
        for i, p in enumerate(pts):
            t = i / (len(pts) - 1)
            # (tucked under the gown at the shoulder)
            r = 0.17 - 0.03 * t + 0.035 * smoothstep(0.75, 1.0, t) - 0.035 * smoothstep(0.12, 0.0, t)
            radii.append((r, r * 0.92))
        o = tube("Sleeve." + side, pts, radii, sides=18, cap=False)
        # rumpled, and the cuff rolled up thick
        for v in o.data.vertices:
            p = v.co
            dd = (p - end).dot((end - el).normalized())
            v.co = p + V((noise.noise(p * 7), noise.noise(p * 7 + V((2, 0, 0))), noise.noise(p * 7 + V((0, 4, 0))))) * 0.018
        cuff_pts = [end - (end - el).normalized() * 0.06, end, end + (end - el).normalized() * 0.01]
        cuff = tube("Cuff", cuff_pts, [(0.2, 0.185), (0.205, 0.19), (0.18, 0.17)], sides=18)
        sol = o.modifiers.new("Solid", "SOLIDIFY")
        sol.thickness = 0.013
        sol.offset = 1
        apply_modifiers(o)
        sl = join([o, cuff], "Sleeve." + side)
        shade_smooth(sl)
        objs.append(sl)
    return objs


def ties(body):
    """the gown's ties at the back of the neck and the waist, knotted, the ends hanging"""
    tree = bvh(body)
    objs = []
    for where, z, length in (("Neck", 6.82, 0.32), ("Waist", 5.02, 0.55)):
        hit, nrm, _, _ = tree.ray_cast(V((0, 0, z)), V((0, 1, 0)), 2.0)
        knot_at = (hit if hit else V((0, 0.25, z))) + V((0, 0.06, 0))
        objs.append(blob("Knot" + where, knot_at, (0.04, 0.03, 0.03), 10))
        for s, side in ((1, "L"), (-1, "R")):
            pts = [knot_at + V((s * 0.02, 0.01, 0)), knot_at + V((s * 0.07, 0.04, -length * 0.35)),
                   knot_at + V((s * 0.05, 0.05, -length * 0.7)), knot_at + V((s * 0.08, 0.04, -length))]
            pts = bezier_points(pts, 4)
            t = tube("Tie" + where + side, pts, [(0.018, 0.005)] * len(pts), sides=6)
            name = "Tie%s%s_" % (where, side)
            S.chain(name, [pts[0], pts[len(pts) // 2], pts[-1]], "Spine5" if where == "Neck" else "Spine1")
            t["chain"] = name
            objs.append(t)
        # and the band round the waist they tie
    band_pts = []
    for i in range(37):
        a = 2 * math.pi * i / 36
        hit, nrm, _, _ = tree.ray_cast(V((0, 0.05, 5.02)), V((math.sin(a), -math.cos(a), 0)), 2.0)
        band_pts.append((hit if hit else V((math.sin(a) * 0.3, -math.cos(a) * 0.25, 5.02))) + (nrm if hit else V()) * 0.06)
    band = tube("WaistBand", band_pts, [(0.012, 0.03)] * len(band_pts), sides=6, cap=False)
    return objs, band


def blob(name, loc, scale, segs):
    from common import blob as b
    return b(name, loc, scale, segs)


def shoes():
    objs = []
    for side, s in (("L", 1), ("R", -1)):
        mb = bpy.data.metaballs.new("Shoe")
        mb.resolution = mb.render_resolution = 0.016
        x = s * 0.325
        meta(mb, V((x, 0.1, 0.13)), (0.125, 0.14, 0.13))              # heel
        meta(mb, V((x + s * 0.01, -0.13, 0.12)), (0.135, 0.21, 0.12))   # arch
        meta(mb, V((x + s * 0.02, -0.42, 0.105)), (0.145, 0.19, 0.105))  # ball
        meta(mb, V((x + s * 0.03, -0.66, 0.09)), (0.12, 0.11, 0.085))   # toe cap
        meta(mb, V((x, 0.03, 0.38)), (0.13, 0.135, 0.2))               # ankle (a boot)
        ob = link(bpy.data.objects.new("ShoeMeta", mb))
        dg = bpy.context.evaluated_depsgraph_get()
        mesh = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        bpy.data.objects.remove(ob)
        o = link(bpy.data.objects.new("Shoe." + side, mesh))
        for v in o.data.vertices:
            if v.co.z < 0.02:
                v.co.z = 0.0 + 0.005 * (v.co.z - 0.02)          # a flat sole
            # scuffed and creased leather
            v.co += V((0, 0, 0)) + (v.co - V((x, -0.2, 0.15))).normalized() * 0.004 * noise.noise(v.co * 20)
        voxel(o, 0.014)
        smooth(o, 0.5, 2)
        from common import decimate
        decimate(o, 1100)
        o["side"] = side
        shade_smooth(o)
        objs.append(o)
    return objs


def bandages(body):
    tree = bvh(body)
    objs = []
    for side in ("L", "R"):
        wr, fm = S.J["Wrist." + side], S.J["ForeMid." + side]
        d = (wr - fm).normalized()
        x, y = (d.cross(V((0, 0, 1)))).normalized(), None
        y = d.cross(x).normalized()
        turns = 7.5
        n = int(turns * 16)
        mesh = bpy.data.meshes.new("Bandage")
        bm = bmesh.new()
        prev = None
        pts = []
        for i in range(n + 1):
            t = i / n
            along = 0.08 - 0.44 * t                     # from the wrist up the forearm
            a = turns * 2 * math.pi * t
            centre = wr + d * along
            direction = x * math.cos(a) + y * math.sin(a)
            hit, nrm, _, _ = tree.ray_cast(centre, direction, 0.5)
            r = (hit - centre).length if hit else 0.07
            # (slack, uneven, bunched)
            r += 0.01 + 0.004 * t + 0.005 * noise.noise(V((t * 9, 0.5, 1.5)))
            p = centre + direction * r
            pts.append(p)
            tilt = d * (0.03 + 0.004 * noise.noise(V((t * 7, 2.5, 0.5))))
            pair = (bm.verts.new(p + tilt), bm.verts.new(p - tilt))
            if prev:
                bm.faces.new((prev[0], prev[1], pair[1], pair[0]))
            prev = pair
        bm.to_mesh(mesh)
        bm.free()
        o = link(bpy.data.objects.new("Bandage." + side, mesh))
        sol = o.modifiers.new("Solid", "SOLIDIFY")
        sol.thickness = 0.006
        apply_modifiers(o)
        # the loose end, hanging
        end = pts[-1]
        tail = [end, end + V((0, -0.02, -0.12)), end + V((0.01, -0.03, -0.24)), end + V((0, -0.02, -0.34))]
        tail = bezier_points(tail, 3)
        t = tube("BandageTail." + side, tail, [(0.005, 0.024)] * (len(tail) - 1) + [(0.004, 0.012)], sides=4)
        name = "Bandage%s_" % side
        S.chain(name, [tail[0], tail[len(tail) // 2], tail[-1]], "Forearm2." + side)
        t["chain"] = name
        o["side"] = side
        shade_smooth(o)
        shade_smooth(t)
        objs += [o, t]
    return objs


def skirt_bones():
    """eight chains of three bones hanging round the skirt, so it can swing and drag"""
    for name, deg in SKIRT_COLS:
        a = math.radians(deg)
        S.chain("Skirt%s_" % name, [skirt_shape(a, z) for z in SKIRT_Z], "Root")
