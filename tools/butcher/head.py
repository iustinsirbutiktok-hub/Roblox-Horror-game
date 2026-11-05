# The Butcher's head: big and brutish (heavy brow, fat jowls, a thick jaw and
# a double chin), rotting: the lips are gone and the gums and crooked teeth
# show through a ragged hole that's eaten into the left cheek; the nose is
# half rotted away; the eyes are black and sunk deep. Greasy hair hangs from a
# receding hairline down to its shoulders and over its face in strings.
import bpy, bmesh, math, random
import numpy as np
from mathutils import Vector as V, Matrix, noise
from common import (link, apply_modifiers, select_only, decimate, shade_smooth, blob, voxel, smooth, join, tube,
                    bvh, smoothstep, bezier_points, metaball_mesh, meta)
import skeleton as S
import vec as N

rnd = random.Random(2024)
HC = S.HC
AX_Y = HC.y + 0.0
MOUTH_Z = HC.z - 0.26
HAIRLINE = HC.z + 0.24


def phi_of(x, y):
    return np.arctan2(x, -(y - AX_Y))


def mouth_h(phi):
    """half the height of the rotted hole at angle phi (radians); it runs further on its left"""
    phi = np.asarray(phi, dtype=float)
    reach = np.where(phi > 0, math.radians(64), math.radians(46))
    a = np.abs(phi) / reach
    h = 0.014 + 0.058 * np.clip(1 - a ** 2.2, 0, 1)
    rag = 0.012 * np.sin(phi * 37) + 0.008 * np.sin(phi * 71 + 1.3)
    return np.where(a < 1, np.maximum(h + rag * (a > 0.3), 0.006), 0.0)


def mouth_z(phi):
    phi = np.asarray(phi, dtype=float)
    return MOUTH_Z + 0.03 * (np.abs(phi) / math.radians(45)) ** 2 + 0.015 * np.maximum(phi, 0) / math.radians(45)


def mouth_depth(phi):
    a = np.abs(np.asarray(phi, dtype=float)) / math.radians(50)
    return 0.035 + 0.075 * np.clip(1 - a * a, 0, 1)


def head_masses(mb):
    c = HC
    rx = lambda deg: Matrix.Rotation(math.radians(deg), 3, "X")
    meta(mb, c + V((0, 0.04, 0.18)), (0.3, 0.35, 0.3))           # cranium
    meta(mb, c + V((0, 0.17, 0.02)), (0.27, 0.2, 0.27))          # back of the skull
    meta(mb, c + V((0, -0.12, -0.06)), (0.27, 0.24, 0.32))       # face
    meta(mb, c + V((0, -0.29, 0.15)), (0.25, 0.08, 0.065))       # heavy brow
    for s in (1, -1):
        meta(mb, c + V((s * 0.18, -0.24, 0.0)), (0.08, 0.1, 0.06))       # cheekbones
        meta(mb, c + V((s * 0.19, -0.12, -0.28)), (0.11, 0.16, 0.14))    # fat jowls
        meta(mb, c + V((s * 0.3, 0.0, 0.0)), (0.035, 0.075, 0.105))      # ears
        meta(mb, c + V((s * 0.13, -0.37, 0.055)), (0.07, 0.08, 0.055), negative=True)   # eye sockets
    meta(mb, c + V((0, -0.24, -0.42)), (0.17, 0.12, 0.1))         # heavy jaw
    meta(mb, c + V((0, -0.14, -0.5)), (0.19, 0.15, 0.085))        # double chin
    meta(mb, c + V((0, -0.26, -0.25)), (0.17, 0.12, 0.13))        # muzzle
    meta(mb, c + V((0, -0.37, 0.0)), (0.04, 0.06, 0.09), rot=rx(-14))     # nose bridge
    meta(mb, c + V((0, -0.41, -0.1)), (0.052, 0.045, 0.04))      # nose
    meta(mb, c + V((0, 0.04, -0.47)), (0.235, 0.245, 0.32))       # bull neck


def sculpt(obj):
    me = obj.data
    P = N.get_co(me)
    Nn = N.get_normals(me)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    c = np.array(HC)
    rad = np.stack([x, y - AX_Y, np.zeros_like(x)], axis=1)
    rad /= np.maximum(np.linalg.norm(rad, axis=1), 1e-6)[:, None]
    phi = phi_of(x, y)
    frontal = y < c[1] - 0.12
    push = np.zeros((len(P), 3))

    # eye sockets: deep pits; puffy bags under them; a heavy lid fold over them
    for s in (1, -1):
        dx, dz = (x - s * 0.13) / 0.085, (z - (c[2] + 0.05)) / 0.065
        r2 = dx * dx + dz * dz
        push[:, 1] += frontal * (r2 < 1) * 0.06 * np.clip(1 - r2, 0, 1) ** 0.7
        bag = np.clip(1 - np.hypot((x - s * 0.13) / 0.09, (z - (c[2] - 0.035)) / 0.03), 0, 1)
        push -= (frontal * 0.014 * bag)[:, None] * rad
        lid = np.clip(1 - np.hypot((x - s * 0.13) / 0.1, (z - (c[2] + 0.115)) / 0.028), 0, 1)
        push -= (frontal * 0.01 * lid)[:, None] * rad
    # the rotted mouth: a ragged hole round the teeth
    h = mouth_h(phi)
    dz = np.abs(z - mouth_z(phi))
    inside = (h > 0) & (dz < h) & (y < c[1] + 0.1)
    u = np.where(h > 0, dz / np.maximum(h, 1e-6), 1)
    push -= (inside * mouth_depth(phi) * np.sqrt(np.clip(1 - u * u, 0, 1)))[:, None] * rad
    rim = (h > 0) & (dz >= h) & (dz < h + 0.03) & (y < c[1] + 0.1)
    push += (rim * 0.01 * (1 - (dz - h) / 0.03) * (0.5 + 0.5 * N.noise(P * 40, 3)))[:, None] * rad
    # the nose eaten away on its left: a ragged pit; nostrils
    d = np.linalg.norm(P - (c + np.array([0.035, -0.43, -0.11])), axis=1)
    push[:, 1] += 0.035 * np.clip(1 - d / 0.045, 0, 1) ** 0.8
    d = np.linalg.norm(P - (c + np.array([-0.025, -0.44, -0.125])), axis=1)
    push[:, 1] += 0.015 * np.clip(1 - d / 0.02, 0, 1)
    # creases: a furrowed brow, crow's feet, deep lines from nose to mouth, sagging jowls
    fur = frontal * (z > c[2] + 0.13) * (z < HAIRLINE + 0.02)
    push -= (fur * 0.006 * np.sin(z * 120 + N.noise(P * 8, 4) * 2))[:, None] * rad
    for s in (1, -1):
        dd, t = N.segdist(P, c + np.array([s * 0.07, -0.42, -0.08]), c + np.array([s * 0.15, -0.36, -0.3]))
        push -= (frontal * 0.014 * np.clip(1 - dd / 0.025, 0, 1))[:, None] * rad
        dd, t = N.segdist(P, c + np.array([s * 0.22, -0.3, 0.05]), c + np.array([s * 0.27, -0.23, 0.02]))
        push -= (0.004 * np.sin(z * 260) * np.clip(1 - dd / 0.05, 0, 1))[:, None] * rad
    # rotting skin: lumps, pits, peeling patches, a torn flap on the right cheek
    rot = N.sstep(0.15, 0.55, N.fbm(P * 4, 3, 11))          # where it's rotting
    mouthrot = np.exp(-((phi / 0.9) ** 2 + ((z - MOUTH_Z) / 0.16) ** 2))
    rot = np.maximum(rot, mouthrot)
    push += (0.0015 * N.noise(P * 45, 6) + rot * (0.006 * N.fbm(P * 22, 3, 5)))[:, None] * Nn
    pits = N.noise(P * 18, 8)
    push -= (rot * (pits > 0.45) * 0.008 * (pits - 0.45) / 0.55)[:, None] * Nn
    d = np.linalg.norm(P - (c + np.array([-0.2, -0.27, -0.12])), axis=1)
    push += (0.012 * np.clip(1 - d / 0.05, 0, 1) * (N.noise(P * 60, 9) > 0))[:, None] * Nn
    # the neck: thick folds round the front
    neckf = (z < c[2] - 0.45) & (y < c[1] + 0.05)
    push += (neckf * 0.008 * np.sin(z * 55 + N.noise(P * 6, 2) * 2))[:, None] * Nn
    N.set_co(me, P + push)


def build_head():
    obj = metaball_mesh("Head", head_masses, 0.011)
    voxel(obj, 0.0085)
    smooth(obj, 0.5, 3)
    sculpt(obj)
    shade_smooth(obj)
    return obj


# ---------------------------------------------------------------- teeth, gums, eyes
def teeth(tree, upper):
    mesh = bpy.data.meshes.new("Teeth")
    bm = bmesh.new()
    count = 15
    for i in range(count):
        a = -math.radians(44) + i / (count - 1) * math.radians(44 + 58)
        if rnd.random() < 0.12:
            continue
        hh = float(mouth_h(a))
        zc = float(mouth_z(a))
        z = zc + (hh * 0.85 if upper else -hh * 0.85)
        o = V((0, AX_Y, z))
        d = V((math.sin(a), -math.cos(a), 0))
        hit, nrm, _, _ = tree.ray_cast(o, d, 1.0)
        if hit is None:
            continue
        base = hit - d * (float(mouth_depth(a)) * 0.55)
        ln = (0.05 + hh * 0.9) * rnd.uniform(0.85, 1.2)
        w = rnd.uniform(0.026, 0.032) * (1.2 if abs(a) < 0.18 else 1.0)
        r = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=w, radius2=w * 0.7, depth=ln)
        verts = r["verts"]
        bmesh.ops.scale(bm, vec=V((1, 0.6, 1)), verts=verts)
        tilt = Matrix.Rotation(rnd.uniform(-0.25, 0.25), 4, "Y") @ Matrix.Rotation(rnd.uniform(-0.2, 0.3), 4, "X")
        bmesh.ops.transform(bm, matrix=tilt, verts=verts)
        bmesh.ops.translate(bm, vec=V((0, 0, ln / 2)), verts=verts)
        if upper:
            bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.pi, 4, "X"), verts=verts)
        bmesh.ops.transform(bm, matrix=Matrix.Rotation(a, 4, "Z"), verts=verts)
        bmesh.ops.translate(bm, vec=base, verts=verts)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("UpperTeeth" if upper else "LowerTeeth", mesh))
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = 1
    apply_modifiers(obj)
    shade_smooth(obj)
    return obj


def gums(tree):
    """a ridge of rotten gum along each row, the teeth set in it"""
    objs = []
    for upper in (True, False):
        pts = []
        for i in range(25):
            a = -math.radians(46) + i / 24 * math.radians(46 + 60)
            hh = float(mouth_h(a))
            z = float(mouth_z(a)) + (hh * 0.85 if upper else -hh * 0.85)
            o = V((0, AX_Y, z))
            d = V((math.sin(a), -math.cos(a), 0))
            hit, _, _, _ = tree.ray_cast(o, d, 1.0)
            if hit is not None:
                pts.append(hit - d * (float(mouth_depth(a)) * 0.6) + V((0, 0, 0.012 if upper else -0.012)))
        objs.append(tube("Gum", pts, [(0.02, 0.03)] * len(pts), sides=8))
    o = join(objs, "Gums")
    shade_smooth(o)
    return o


def eyes():
    objs = []
    for side in ("L", "R"):
        e = blob("Eye." + side, S.EYE[side], (0.05, 0.05, 0.05), 16)
        e["bone"] = "Eye." + side
        objs.append(e)
    return objs


# ---------------------------------------------------------------- greasy hair
HAIR_CLUMPS = [  # (angle round the head, length, strands)
    (-34, 0.62, 4), (31, 0.66, 3), (-55, 0.72, 6), (56, 0.74, 6), (-78, 0.82, 7), (80, 0.84, 7),
    (-102, 0.86, 7), (104, 0.86, 7), (-126, 0.82, 7), (128, 0.84, 7), (-150, 0.78, 7), (152, 0.8, 7),
    (-170, 0.74, 6), (172, 0.72, 6), (-16, 0.5, 2), (44, 0.56, 3),
]


def hairline_z(phi):
    """front: high and receding; down behind the ears and the nape"""
    a = abs(phi) / math.pi
    ragged = 0.025 * noise.noise(V((phi * 3.0, 0.7, 0.3))) + 0.012 * noise.noise(V((phi * 11.0, 1.7, 0.3)))
    return HAIRLINE - 0.2 * smoothstep(0.22, 0.6, a) - 0.2 * smoothstep(0.6, 1.0, a) + \
        0.05 * math.exp(-((abs(phi) - 0.5) / 0.15) ** 2) + ragged


def top_strands(tree):
    """greasy strings combed back over the top of the head, hanging off the back"""
    objs = []
    for k in range(34):
        phi0 = math.radians(-75 + 150 * (k + rnd.uniform(-0.3, 0.3)) / 33)
        phi1 = math.pi - phi0 * rnd.uniform(0.2, 0.5) if phi0 >= 0 else -math.pi - phi0 * rnd.uniform(0.2, 0.5)
        z0 = hairline_z(phi0) + 0.01
        e0 = math.asin(max(-0.95, min(0.95, (z0 - HC.z) / 0.36)))
        e1 = math.radians(rnd.uniform(-35, -10))
        pts = []
        n = 18
        for i in range(n + 1):
            t = i / n
            ph = phi0 + (phi1 - phi0) * t
            el = e0 + (e1 - e0) * t + math.sin(t * math.pi) * (math.pi / 2 - max(e0, e1)) * 0.92
            d = V((math.sin(ph) * math.cos(el), -math.cos(ph) * math.cos(el), math.sin(el)))
            o = HC + V((0, 0.04, 0.05))
            hit, nrm, _, _ = tree.ray_cast(o, d, 1.0)
            if hit is None:
                continue
            pts.append(hit + nrm * (0.014 + 0.004 * noise.noise(hit * 9 + V((k, 0, 0)))))
        if len(pts) < 4:
            continue
        # then hanging off the back
        last = pts[-1]
        ln = rnd.uniform(0.15, 0.45)
        for i in range(1, 5):
            pts.append(last + V((0, 0.02 * i, -ln * i / 4)))
        pts = bezier_points(pts[::2] + [pts[-1]], 2)
        r0 = rnd.uniform(0.012, 0.018)
        radii = [(r0, r0 * 0.4)] * (len(pts) - 3) + [(r0 * 0.7, r0 * 0.3), (r0 * 0.4, r0 * 0.2), (r0 * 0.15, 0.002)]
        objs.append(tube("TopStrand", pts, radii, sides=4, cap=False, twist=0.2))
    o = join(objs, "HairTop")
    shade_smooth(o)
    return o


def scalp(tree):
    """a thin layer of slicked-back hair over the top of the head"""
    mesh = bpy.data.meshes.new("Scalp")
    bm = bmesh.new()
    segs, rings = 96, 16
    grid = []
    for r in range(rings):
        u = r / (rings - 1) * 0.96
        row = []
        for i in range(segs):
            phi = -math.pi + 2 * math.pi * i / segs
            ze = hairline_z(phi)
            el0 = math.asin(max(-0.95, min(0.95, (ze - HC.z) / 0.36)))
            el = el0 + (math.pi / 2 - el0) * u
            d = V((math.sin(phi) * math.cos(el), -math.cos(phi) * math.cos(el), math.sin(el)))
            o = HC + V((0, 0.04, 0.05))
            hit, nrm, _, _ = tree.ray_cast(o, d, 1.0)
            if hit is None:
                hit, nrm = o + d * 0.36, d
            thick = 0.002 + 0.007 * smoothstep(0.0, 0.25, u)
            # combed back in greasy clumps
            clump = 0.006 * abs(math.sin(phi * 34 + 2.0 * noise.noise(hit * 3))) + 0.003 * noise.noise(hit * 15)
            row.append(bm.verts.new(hit + nrm * (thick + clump)))
        grid.append(row)
    for r in range(rings - 1):
        for i in range(segs):
            bm.faces.new((grid[r][i], grid[r][(i + 1) % segs], grid[r + 1][(i + 1) % segs], grid[r + 1][i]))
    top = bm.verts.new(sum((v.co for v in grid[-1]), V()) / segs + V((0, 0, 0.005)))
    for i in range(segs):
        bm.faces.new((grid[-1][i], grid[-1][(i + 1) % segs], top))
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Scalp", mesh))
    shade_smooth(obj)
    return obj


def hair(tree):
    objs = []
    for ci, (deg, length, count) in enumerate(HAIR_CLUMPS):
        phi0 = math.radians(deg)
        strands = []
        for k in range(count):
            phi = phi0 + math.radians(rnd.uniform(-6, 6))
            z = hairline_z(phi) + 0.03
            o = V((0, AX_Y + 0.03, z))
            d = V((math.sin(phi), -math.cos(phi), 0))
            hit, nrm, _, _ = tree.ray_cast(o, d, 1.0)
            if hit is None:
                continue
            ln = length * rnd.uniform(0.75, 1.15)
            out = V((d.x, d.y, 0)).normalized()
            side = V((-out.y, out.x, 0))
            n = 10
            pts = []
            for i in range(n + 1):
                t = i / n
                p = hit - out * 0.005 + out * (0.05 * smoothstep(0.0, 0.4, t)) + V((0, 0, -ln * t))
                p += side * 0.03 * noise.noise(V((ci * 3.1 + k, t * 3, 0.5))) * t
                p += out * 0.02 * noise.noise(V((ci * 1.7 + k, t * 4, 2.5))) * t
                pts.append(p)

            def push_out(pts):
                for i in range(1, len(pts)):
                    loc, nn, _, dist = tree.find_nearest(pts[i])
                    if loc is not None and ((pts[i] - loc).dot(nn) < 0 or dist < 0.02):
                        pts[i] = loc + nn * 0.02

            for _ in range(3):
                push_out(pts)
                pts = [pts[0]] + [(pts[i - 1] + pts[i] * 2 + pts[i + 1]) / 4 for i in range(1, n)] + [pts[-1]]
            push_out(pts)
            r0 = rnd.uniform(0.01, 0.016)
            radii = [(r0 * (1 - 0.8 * (i / n) ** 1.2), r0 * 0.45 * (1 - 0.8 * (i / n) ** 1.2)) for i in range(n + 1)]
            st = tube("Strand", pts, radii, sides=4, cap=False, twist=0.25)
            strands.append((st, pts))
        if not strands:
            continue
        mean = [sum((s[1][i] for s in strands), V()) / len(strands) for i in range(11)]
        name = "Hair%02d_" % (ci + 1)
        S.chain(name, [S.head_xf(mean[i]) for i in (0, 4, 7, 10)], "Head")
        clump = join([s[0] for s in strands], "Hair%02d" % (ci + 1))
        clump["chain"] = name
        objs.append(clump)
    return objs


def build():
    head = build_head()
    tree_plain = bvh(head)
    parts = {"Head": head}
    parts["UpperTeeth"] = teeth(tree_plain, True)
    parts["LowerTeeth"] = teeth(tree_plain, False)
    parts["Gums"] = gums(tree_plain)
    e = eyes()
    parts["Eye.L"], parts["Eye.R"] = e
    hairparts = {"Scalp": scalp(tree_plain), "HairTop": top_strands(tree_plain)}
    for h in hair(tree_plain):
        hairparts[h.name] = h
    # designed round HC: now scaled up a little on the neck
    for o in list(parts.values()) + list(hairparts.values()):
        o.data.transform(S.HEAD_M)
        o.data.update()
    return parts, hairparts


# ---------------------------------------------------------------- skinning rules for the face (numpy)
FACE_BONES = ["Head", "Jaw", "Neck3", "Neck2", "Brow.L", "Brow.R", "BrowInner.L", "BrowInner.R", "Cheek.L", "Cheek.R",
              "LidUpper.L", "LidUpper.R", "LidLower.L", "LidLower.R", "MouthCorner.L", "MouthCorner.R", "LipUpper.L",
              "LipUpper.R", "LipLower.L", "LipLower.R", "Nose", "Ear.L", "Ear.R"]


def face_weights(P):
    """(N, len(FACE_BONES)) weights for points on the head"""
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    c = np.array(HC)
    phi = phi_of(x, y)
    W = {b: np.zeros(len(P)) for b in FACE_BONES}
    zc = mouth_z(phi)
    front = N.sstep(math.radians(115), math.radians(80), np.abs(phi))
    below = N.sstep(zc + 0.012, zc - 0.035, z)
    jaw = front * below
    neck = N.sstep(c[2] - 0.42, c[2] - 0.62, z) * N.sstep(-0.25, -0.05, y)
    neck = np.maximum(neck, N.sstep(c[2] - 0.5, c[2] - 0.7, z))
    jaw *= 1 - neck
    W["Jaw"] = jaw
    low = N.sstep(c[2] - 0.6, c[2] - 0.8, z)
    W["Neck2"] = neck * low
    W["Neck3"] = neck * (1 - low)
    W["Head"] = np.clip(1 - jaw - neck, 0, 1)

    def take(bone, amount, frm):
        amount = np.minimum(amount, W[frm])
        W[frm] = W[frm] - amount
        W[bone] = W[bone] + amount

    for side, s in (("L", 1), ("R", -1)):
        e = c + np.array([s * 0.13, -0.29, 0.05])
        d = np.linalg.norm(P - (c + np.array([s * 0.17, -0.33, 0.15])), axis=1)
        take("Brow." + side, 0.8 * np.clip(1 - d / 0.08, 0, 1) ** 1.5, "Head")
        d = np.linalg.norm(P - (c + np.array([s * 0.06, -0.34, 0.14])), axis=1)
        take("BrowInner." + side, 0.8 * np.clip(1 - d / 0.06, 0, 1) ** 1.5, "Head")
        d = np.linalg.norm(P - (c + np.array([s * 0.19, -0.27, -0.1])), axis=1)
        take("Cheek." + side, 0.7 * np.clip(1 - d / 0.12, 0, 1) ** 1.5, "Head")
        # lids: the skin just above and below each eye
        up = np.clip(1 - np.hypot((x - e[0]) / 0.075, (z - (e[2] + 0.04)) / 0.028), 0, 1) * (y < e[1] + 0.02)
        take("LidUpper." + side, 0.9 * up, "Head")
        lo = np.clip(1 - np.hypot((x - e[0]) / 0.075, (z - (e[2] - 0.04)) / 0.025), 0, 1) * (y < e[1] + 0.02)
        take("LidLower." + side, 0.8 * lo, "Head")
        d = np.linalg.norm(P - (c + np.array([s * 0.3, 0.0, 0.0])), axis=1)
        take("Ear." + side, 1.0 * np.clip(1 - d / 0.09, 0, 1), "Head")
        # the corners of the mouth, and each half of each lip's ragged edge
        corner = np.clip(1 - np.abs(np.abs(phi) - math.radians(38)) / math.radians(22), 0, 1) * \
            np.clip(1 - np.abs(z - zc) / 0.08, 0, 1) * (s * phi > 0)
        hw, jw = W["Head"], W["Jaw"]
        frac = hw / np.maximum(hw + jw, 1e-6)
        take("MouthCorner." + side, 0.75 * corner * frac, "Head")
        take("MouthCorner." + side, 0.75 * corner * (1 - frac), "Jaw")
        hh = mouth_h(phi)
        half = np.clip(s * phi / math.radians(20), 0, 1) * (np.abs(phi) < math.radians(50))
        upl = np.clip(1 - np.abs(z - (zc + hh + 0.012)) / 0.04, 0, 1) * half
        take("LipUpper." + side, 0.8 * upl, "Head")
        lol = np.clip(1 - np.abs(z - (zc - hh - 0.012)) / 0.04, 0, 1) * half
        take("LipLower." + side, 0.8 * lol, "Jaw")
    d = np.linalg.norm(P - (c + np.array([0, -0.41, -0.07])), axis=1)
    take("Nose", 0.9 * np.clip(1 - d / 0.08, 0, 1) ** 1.2, "Head")
    return np.stack([W[b] for b in FACE_BONES], axis=1)
