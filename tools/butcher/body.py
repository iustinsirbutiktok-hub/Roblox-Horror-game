# The Butcher's body: limbs grown over the skeleton, the bulk of the trunk
# (gut, barrel chest, back, traps, love handles) as blended metaballs, fused
# into one high-resolution surface, then sculpted: the belt digging in under
# the gut, back rolls, muscle on the arms, ropey veins, knuckles. The shirt and
# trousers are painted on (nothing to clip through when it moves), so their
# folds, the button placket and the seams are sculpted in too. The high-res
# body is kept for baking the normal map; the game mesh is a decimated copy.
import bpy, bmesh, math
import numpy as np
from mathutils import Vector as V
from common import link, apply_modifiers, shade_smooth, seg_dist, smoothstep, metaball_mesh, meta, join, voxel, smooth
import skeleton as S
import vec as N

BELT_Z = 4.42


def build_skin(edges=None, name="Frame", levels=2):
    edges = edges or S.SKIN_EDGES
    names = []
    for a, c in edges:
        for n in (a, c):
            if n not in names:
                names.append(n)
    index = {n: i for i, n in enumerate(names)}
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([S.J[n] for n in names], [(index[a], index[c]) for a, c in edges], [])
    obj = link(bpy.data.objects.new(name, mesh))
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    skin.branch_smoothing = 0.7
    data = mesh.skin_vertices[0].data
    for n, i in index.items():
        rx, ry = S.R.get(n, (0.05, 0.05))
        k = 1.3 if any(n.startswith(f) for f in ("Thumb", "Index", "Middle", "Ring", "Pinky")) else 1.5
        data[i].radius = (rx * k, ry * k)
    data[index.get("Pelvis", 0)].use_root = True
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = sub.render_levels = levels
    apply_modifiers(obj)
    return obj


def masses(mb):
    """the bulk of the trunk, as blended metaballs"""
    meta(mb, (0, -0.3, 4.8), (0.6, 0.6, 0.62))              # the gut
    meta(mb, (0, -0.42, 4.52), (0.5, 0.42, 0.3))              # hanging low over the belt
    meta(mb, (0, -0.02, 5.85), (0.72, 0.46, 0.55))            # barrel chest
    for s in (1, -1):
        meta(mb, (s * 0.3, -0.3, 5.92), (0.27, 0.19, 0.21))   # heavy pecs
        meta(mb, (s * 0.5, 0.02, 4.68), (0.22, 0.3, 0.2))     # love handles
        meta(mb, (s * 0.26, 0.24, 4.0), (0.3, 0.26, 0.3))     # backside
        meta(mb, (s * 0.38, 0.12, 6.42), (0.34, 0.24, 0.17))  # traps
    meta(mb, (0, 0.17, 5.5), (0.6, 0.36, 0.85))               # broad back
    meta(mb, (0, 0.22, 6.4), (0.4, 0.28, 0.24))               # the hump between the shoulders
    meta(mb, (0, 0.03, 4.15), (0.58, 0.42, 0.32))             # hips


def sleeve_end(side):
    el, fm = S.J["Elbow." + side], S.J["ForeMid." + side]
    return el + (fm - el).normalized() * 0.2


def regions(P):
    """per point: 0 = shirt, 1 = trousers, 2 = bare skin"""
    reg = np.zeros(len(P), dtype=np.int8)
    for side in ("L", "R"):
        el, wr = S.J["Elbow." + side], S.J["Wrist." + side]
        axis = (wr - el).normalized()
        d, t = N.segdist(P, N.V3(el - axis * 0.1), N.V3(wr + axis * 1.5))
        past = (P - N.V3(sleeve_end(side))) @ N.V3(axis) > 0
        reg[(d < 0.45) & past] = 2
    reg[(P[:, 2] > 6.62) & (np.abs(P[:, 0]) < 0.42)] = 2          # the neck above the collar
    reg[P[:, 2] < BELT_Z] = 1
    return reg


def sculpt(obj):
    me = obj.data
    P = N.get_co(me)
    Nn = N.get_normals(me)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    J = S.J
    rad = np.stack([x, y - 0.03, np.zeros_like(x)], axis=1)
    rad /= np.maximum(np.linalg.norm(rad, axis=1), 1e-6)[:, None]
    front = np.maximum(0, -rad[:, 1])
    back = np.maximum(0, rad[:, 1])
    reg = regions(P)
    shirt, trousers, skin = reg == 0, reg == 1, reg == 2
    n1 = N.fbm(P * 3.0, 3, 1)
    push = np.zeros(len(P))

    # the belt digs in under the gut; a crease under the heavy chest
    push -= 0.03 * np.clip(1 - np.abs(z - BELT_Z) / 0.1, 0, 1) ** 1.5
    for s in (1, -1):
        k = np.clip(1 - np.abs(z - 5.66) / 0.1, 0, 1) * np.clip(1 - np.abs(x - s * 0.3) / 0.3, 0, 1) * (y < -0.1)
        push -= 0.018 * k
    # back rolls
    for rz in (4.95, 5.3):
        push += 0.018 * np.sin(np.clip((z - rz + 0.14) / 0.28, 0, 1) * np.pi) * back * (0.6 + 0.4 * n1)
    # a fat neck: a roll at the back, the start of a double chin at the front
    neck = (z > 6.55) & (z < 7.05)
    push += neck * 0.04 * np.sin(np.clip((z - 6.62) / 0.16, 0, 1) * np.pi) * back
    push += neck * (z > 6.85) * 0.03 * front

    # arms: deltoid, biceps, triceps, forearm muscle, elbows, veins, knuckles
    for s, side in ((1, "L"), (-1, "R")):
        sh, el, wr = (N.V3(J[k + "." + side]) for k in ("Shoulder", "Elbow", "Wrist"))
        d = np.linalg.norm(P - (sh + np.array([s * 0.08, 0, 0.02])), axis=1)
        push += 0.035 * np.clip(1 - d / 0.38, 0, 1) ** 1.5
        dd, t = N.segdist(P, sh, el)
        axis = (el - sh) / np.linalg.norm(el - sh)
        outw = P - (sh + t[:, None] * (el - sh))
        outw /= np.maximum(np.linalg.norm(outw, axis=1), 1e-6)[:, None]
        near = dd < 0.4
        push += near * (0.05 * np.maximum(0, -outw[:, 1]) * np.sin(t * np.pi) ** 1.5 +
                        0.035 * np.maximum(0, outw[:, 1]) * np.sin(np.minimum(1, t * 1.3) * np.pi) ** 1.5)
        dd, t = N.segdist(P, el, wr)
        near = dd < 0.36
        push += near * 0.045 * np.sin(np.minimum(1, t * 2.2) * np.pi) * (1 - t)
        vein = np.abs(N.noise(P * np.array([9, 9, 2.2]) + np.array([s * 5, 0, 0]), 7))
        push += near * (t > 0.15) * skin * 0.013 * np.clip(1 - vein / 0.05, 0, 1)
        d = np.linalg.norm(P - el, axis=1)
        push += 0.03 * np.clip(1 - d / 0.17, 0, 1) ** 2
        h = S.HANDS[side]
        for f in ("Index", "Middle", "Ring", "Pinky"):
            for i in (1, 2, 3):
                d = np.linalg.norm(P - N.V3(J["%s%d.%s" % (f, i, side)]), axis=1)
                push += 0.016 * np.clip(1 - d / 0.07, 0, 1)
        dd, t = N.segdist(P, N.V3(h["wrist"]), N.V3(h["palm_end"]))
        backhand = (P - N.V3(h["wrist"])) @ N.V3(h["palm"]) < 0
        vein = np.abs(N.noise(P * 14, 9))
        push += (dd < 0.2) * backhand * 0.008 * np.clip(1 - vein / 0.05, 0, 1)

    # the shirt: rumpled cotton, folds bunched above the belt, pulled from the armpits,
    # rings of folds down the sleeves, the placket, the yoke seam
    ang = np.arctan2(x, -y)
    f_shirt = 0.012 * N.fbm(P * 4.5, 3, 3)
    f_shirt += 0.014 * np.sin(ang * 13 + N.noise(P * 2.5, 4) * 5) * N.sstep(4.75, BELT_Z, z)
    for s in (1, -1):
        dd, t = N.segdist(P, np.array([s * 0.62, -0.1, 5.95]), np.array([s * 0.2, -0.45, 5.0]))
        f_shirt += (dd < 0.25) * 0.012 * np.sin(dd * 45) * np.clip(1 - dd / 0.25, 0, 1)
    for side in ("L", "R"):
        dd, t = N.segdist(P, N.V3(J["Shoulder." + side]), N.V3(sleeve_end(side)))
        f_shirt += (dd < 0.4) * (t > 0.15) * 0.006 * np.sin(t * 24 + N.noise(P * 4, 5) * 9) * t
    f_shirt += (front > 0.85) * (np.abs(x) < 0.07) * (z > 4.5) * 0.012 * np.clip(1 - np.abs(x) / 0.07, 0, 1)
    f_shirt -= (back > 0.6) * (np.abs(z - 6.25) < 0.025) * 0.008
    # the trousers: long creases from the hips, bunched at the knees and over the boots, side seams
    f_tr = 0.01 * N.fbm(P * 4, 3, 6)
    side_x = np.where(x > 0, 0.42, -0.42)
    k = np.maximum(N.sstep(0.35, 0.0, np.abs(z - 2.25)), N.sstep(1.1, 0.6, z)) * (z < 2.6)
    f_tr += 0.016 * np.sin(z * 18 + N.noise(P * 3, 7) * 7 + np.arctan2(x - side_x, y) * 2) * k
    f_tr += 0.007 * np.sin(np.arctan2(x - side_x, y) * 7 + N.noise(P * 1.5, 8) * 4) * N.sstep(4.2, 3.0, z) * \
        N.sstep(0.0, 2.6, z)
    f_tr += 0.006 * (np.abs(np.abs(np.arctan2(x - side_x, -y)) - np.pi / 2) < 0.08)
    f_skin = 0.003 * N.noise(P * 30, 10)
    push += np.where(shirt, f_shirt, np.where(trousers, f_tr, f_skin))

    N.set_co(me, P + Nn * push[:, None])


def build_frame(levels=2):
    """the limbs and trunk, grown as several closed pieces: the body with its arms and
    legs, then every finger on its own (a palm with five branches leaves holes in the
    skin, and the volume fill leaks through them and loses whole limbs)"""
    digits = ("Thumb", "Index", "Middle", "Ring", "Pinky")
    main = [e for e in S.SKIN_EDGES if not any(n.startswith(digits) for n in e)]
    pieces = [build_skin(main, "Frame", levels)]
    for side in ("L", "R"):
        for f in digits:
            first = 1
            edges = [(("Palm." if f != "Thumb" else "Wrist.") + side, "%s%d.%s" % (f, first, side))]
            edges += [("%s%d.%s" % (f, i, side), "%s%d.%s" % (f, i + 1, side)) for i in range(first, 4)]
            pieces.append(build_skin(edges, f + side, levels))
    for p in pieces:
        bm = bmesh.new()
        bm.from_mesh(p.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(p.data)
        bm.free()
    return pieces


def build():
    frame = build_frame()
    bulk = metaball_mesh("Bulk", masses, 0.025)
    obj = join(frame + [bulk], "Body")
    voxel(obj, 0.0135)
    smooth(obj, 0.5, 4)
    sculpt(obj)
    shade_smooth(obj)
    return obj


def drape_proxy():
    """the trunk and legs without the arms: what the apron, its ties and the belt hang on"""
    arms = ("Clav", "Shoulder", "UpperMid", "Elbow", "Fore", "Wrist", "Palm", "Thumb", "Index", "Middle", "Ring", "Pinky")
    edges = [e for e in S.SKIN_EDGES if not any(n.startswith(arms) for n in e)]
    frame = build_skin(edges, "DrapeFrame", 2)
    bm = bmesh.new()
    bm.from_mesh(frame.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(frame.data)
    bm.free()
    bulk = metaball_mesh("DrapeBulk", masses, 0.03)
    obj = join([frame, bulk], "DrapeProxy")
    voxel(obj, 0.02)
    sculpt(obj)
    obj.hide_render = True
    return obj
