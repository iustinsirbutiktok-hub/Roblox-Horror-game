# The ribs that show through the hole in its chest: six a side, laid along the
# body's original surface, snapped off short of the cracked breastbone. Each
# rib gets its own bone (Rib1.L ... Rib6.R), so the chest can heave, flare
# open, or split apart.
import math, random
from mathutils import Vector as V, noise
from common import tube, join, bvh, smoothstep, shade_smooth
import skeleton as S
from body import wound_e

rnd = random.Random(66)


def surface_point(tree, z, ang):
    """where a ray out from the spine's axis at height z, angle ang (0 = front, + = its left) meets the skin"""
    o = V((0, 0.06, z))
    d = V((math.sin(ang), -math.cos(ang), 0))
    hit, normal, _, _ = tree.ray_cast(o, d, 2.0)
    return hit, normal


def build(plain):
    tree = bvh(plain)
    objs = []
    bone_of = {}
    for side, s in (("L", 1), ("R", -1)):
        for i, z0 in enumerate(S.RIB_Z):
            pts, radii = [], []
            # from round the side (hidden) to a jagged broken end near the middle
            end = math.radians(9 + rnd.uniform(0, 8))
            if i == 2 and side == "L":
                end = math.radians(26)              # one snapped off short
            steps = 22
            for k in range(steps + 1):
                t = k / steps
                ang = s * (math.radians(95) * (1 - t) + end * t)
                # ribs slope down towards the front
                z = z0 - 0.13 * t ** 1.3 + 0.008 * math.sin(t * 9 + i)
                hit, nrm = surface_point(tree, z, ang)
                if hit is None:
                    continue
                e = wound_e(hit)
                if e > 1.35:
                    continue                          # buried, not worth building
                inset = 0.014 + 0.05 * smoothstep(0.85, 1.2, e)
                pts.append(hit - nrm * inset)
                w = 0.034 * (1 - 0.3 * t)
                radii.append((w * 0.6, w))            # flat bands, taller than thick, like real ribs
            if len(pts) < 3:
                continue
            # the broken end: a splintered taper
            last = pts[-1]
            direction = (pts[-1] - pts[-2]).normalized()
            pts.append(last + direction * 0.03 + V((0, 0, 0.006)))
            radii.append((0.012, 0.008))
            pts.append(last + direction * 0.05 + V((0, -0.005, -0.004)))
            radii.append((0.003, 0.003))
            o = tube("Rib%d.%s" % (i + 1, side), pts, radii, sides=7)
            bone_of[o.name] = "Rib%d.%s" % (i + 1, side)
            objs.append(o)
    # cartilage stubs and splinters of the breastbone, stuck to the flesh
    for k in range(5):
        z = 5.75 + k * 0.12 + rnd.uniform(-0.03, 0.03)
        hit, nrm = surface_point(tree, z, math.radians(rnd.uniform(-6, 2)))
        if hit is None:
            continue
        a = hit - nrm * 0.07
        b = a + nrm * 0.03 + V((rnd.uniform(-0.02, 0.02), 0, rnd.uniform(0.02, 0.05)))
        o = tube("Splinter", [a, (a + b) / 2, b], [0.012, 0.009, 0.002], sides=5)
        bone_of[o.name] = "Spine4" if z > 6.0 else "Spine3"
        objs.append(o)
    for o in objs:
        o["bone"] = bone_of[o.name]
        shade_smooth(o)
    return objs
