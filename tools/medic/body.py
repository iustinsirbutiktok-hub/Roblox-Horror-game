# The Medic's body: a skin over the skeleton graph, smoothed, then the
# emaciated anatomy pushed into it (ribs, sunken belly, collarbones, spine,
# knobbly knees and elbows, hip bones).
import bpy, bmesh, math, random
from mathutils import Vector as V
from common import link, apply_modifiers, shade_smooth, tri_count, select_only
import skeleton as S


def build_skin():
    names = []
    for a, b in S.SKIN_EDGES:
        for n in (a, b):
            if n not in names:
                names.append(n)
    index = {n: i for i, n in enumerate(names)}
    mesh = bpy.data.meshes.new("BodySkin")
    mesh.from_pydata([S.J[n] for n in names], [(index[a], index[b]) for a, b in S.SKIN_EDGES], [])
    obj = link(bpy.data.objects.new("Body", mesh))
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    skin.branch_smoothing = 0.6
    data = mesh.skin_vertices[0].data
    for n, i in index.items():
        rx, ry = S.R.get(n, (0.05, 0.05))
        # (smoothing shrinks the skin by about a third: make up for it)
        k = 1.25 if any(n.startswith(f) for f in ("Thumb", "Index", "Middle", "Ring", "Pinky")) else 1.5
        data[i].radius = (rx * k, ry * k)
    data[index["Pelvis"]].use_root = True
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    apply_modifiers(obj)
    return obj


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length, t


def sculpt(obj):
    """push the starved anatomy into the smooth tube body"""
    mesh = obj.data
    mesh.calc_normals_split() if hasattr(mesh, "calc_normals_split") else None
    J = S.J
    spine_x = 0.0
    for v in mesh.vertices:
        p = v.co.copy()
        n = v.normal.copy()
        push = 0.0
        x, y, z = p
        # --- ribcage (z 5.05 .. 6.15): ribs as raised bands sloping down to the front
        if 4.95 < z < 6.2 and abs(x) < 0.5:
            ang = math.atan2(x, -(y - 0.05))          # 0 = front, +-pi = back
            front = math.cos(ang)
            slope = 0.22 * (1 + front) * 0.5          # ribs dip at the front
            ph = (z + slope - 5.0) / 0.16
            band = math.cos(ph * 2 * math.pi)
            fade = min(1, (z - 4.95) / 0.15) * min(1, (6.2 - z) / 0.25)
            breast = 0.0 if abs(x) < 0.05 and front > 0.9 else 1.0      # sternum stays flat
            push += (max(band, 0) ** 2 * 0.05 - max(-band, 0) ** 0.7 * 0.035) * fade * breast
            # sternum ridge
            if front > 0.95 and z > 5.3:
                push += 0.015 * (1 - abs(x) / 0.05) if abs(x) < 0.05 else 0
        # --- sunken belly under the ribs
        if 4.3 < z < 5.0 and y < 0.05:
            k = math.sin((z - 4.3) / 0.7 * math.pi)
            push -= 0.09 * k * max(0, -n.y)
        # --- vertebrae down the back
        if 4.3 < z < 6.5 and abs(x) < 0.07 and y > 0.1:
            ph = (z - 4.3) / 0.19
            push += max(math.cos(ph * 2 * math.pi), 0) ** 3 * 0.035 * (1 - abs(x) / 0.07)
        # --- shoulder blades
        for s in (1, -1):
            c = V((s * 0.24, 0.27, 5.95))
            d = (p - c).length
            if d < 0.2 and y > 0.1:
                push += 0.04 * (1 - d / 0.2) ** 2
        # --- collarbones: a ridge from the sternum out to each shoulder
        for s in (1, -1):
            dd, t = seg_dist(p, V((s * 0.05, -0.18, 6.22)), V((s * 0.62, -0.06, 6.22)))
            if dd < 0.07 and y < 0:
                push += 0.035 * (1 - dd / 0.07) ** 1.5
            # the hollow above it
            dd2, _ = seg_dist(p, V((s * 0.12, -0.12, 6.33)), V((s * 0.5, -0.04, 6.3)))
            if dd2 < 0.07:
                push -= 0.025 * (1 - dd2 / 0.07)
        # --- hip bones jutting at the front
        for s in (1, -1):
            d = (p - V((s * 0.3, -0.18, 4.32))).length
            if d < 0.13:
                push += 0.04 * (1 - d / 0.13) ** 2
        # --- knobbly joints
        for name, amount, radius in (("Knee", 0.05, 0.16), ("Elbow1", 0.04, 0.12), ("Elbow2", 0.035, 0.11),
                                     ("Ankle", 0.025, 0.1), ("Wrist", 0.02, 0.07)):
            for side in ("L", "R"):
                d = (p - J[name + "." + side]).length
                if d < radius:
                    push += amount * (1 - d / radius) ** 2
        # --- knuckles
        for side in ("L", "R"):
            for f in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
                for i in (0, 1, 2):
                    d = (p - J["%s%d.%s" % (f, i, side)]).length
                    if d < 0.05:
                        push += 0.012 * (1 - d / 0.05)
        # --- tendons/stringy neck
        if 6.35 < z < 7.05:
            ang = math.atan2(x, -(y + 0.05))
            push += 0.012 * max(math.cos(ang * 3), 0) ** 3
        v.co = p + n * push


def build():
    obj = build_skin()
    sculpt(obj)
    shade_smooth(obj, 70)
    return obj
