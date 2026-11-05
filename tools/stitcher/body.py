# The Stitcher's body: a skin grown over the skeleton graph, then the starved
# anatomy pushed into it (stringy neck, collarbones, knobbly elbows, wrists and
# knuckles, sunken belly) and the chest wound: a hole torn through the skin
# where the ribs show (ribs.py lays the rib bones across it).
import bpy, bmesh, math
from mathutils import Vector as V, noise
from common import link, apply_modifiers, shade_smooth, seg_dist, smoothstep
import skeleton as S


def wound_e(p, grow=0.0):
    """< 1 inside the hole torn in its chest (grow > 0 makes it bigger, for the gown)"""
    if p.y > 0.04:
        return 9.0
    cx, cz, ax, az = -0.03, 5.96, 0.25 + grow, 0.43 + grow * 1.4
    jag = noise.noise(V((p.x * 8.0, p.z * 8.0, 0.5))) * 0.2 + noise.noise(V((p.x * 26.0, p.z * 26.0, 1.3))) * 0.07
    e = math.sqrt(((p.x - cx) / ax) ** 2 + ((p.z - cz) / az) ** 2) + jag
    # (round the sides it fades out, so the hole stays on its front)
    e += max(0.0, p.y + 0.02) * 6.0
    return e


def build_skin(edges=None, name="Body", refined=True):
    edges = edges or S.SKIN_EDGES
    names = []
    for a, c in edges:
        for n in (a, c):
            if n not in names:
                names.append(n)
    index = {n: i for i, n in enumerate(names)}
    mesh = bpy.data.meshes.new("BodySkin")
    mesh.from_pydata([S.J[n] for n in names], [(index[a], index[c]) for a, c in edges], [])
    obj = link(bpy.data.objects.new(name, mesh))
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    skin.branch_smoothing = 0.6
    data = mesh.skin_vertices[0].data
    for n, i in index.items():
        rx, ry = S.R.get(n, (0.05, 0.05))
        k = 1.25 if any(n.startswith(f) for f in ("Thumb", "Index", "Middle", "Ring", "Pinky")) else 1.5
        data[i].radius = (rx * k, ry * k)
    data[index["Pelvis"]].use_root = True
    sub = obj.modifiers.new("Sub", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    apply_modifiers(obj)
    if refined:
        refine(obj)
    return obj


def torso_proxy():
    """the torso alone (no arms or legs), for the gown to wrap round"""
    obj = build_skin(S.TORSO_EDGES, "TorsoProxy", refined=False)
    obj.hide_render = True
    return obj


def refine(obj):
    """more geometry round the chest wound, so its torn edge and the flesh can be shaped"""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for _ in range(2):
        edges = [e for e in bm.edges if all(wound_e(v.co, 0.12) < 1.5 for v in e.verts)]
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True, smooth=1.0)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def sculpt(obj):
    J = S.J
    mesh = obj.data
    for v in mesh.vertices:
        p = v.co.copy()
        n = v.normal.copy()
        x, y, z = p
        push = 0.0

        # --- the chest wound: the skin torn away, the flesh sunk in behind the ribs
        # (pushed in towards the spine, not along the normals: the refined
        # triangles there don't all have trustworthy ones)
        e = wound_e(p)
        if e < 1.25:
            radial = V((x, y - 0.06, 0))
            n = radial.normalized() if radial.length > 1e-4 else n
            inside = smoothstep(1.0, 0.72, e)
            push -= 0.085 * inside
            # the cracked-open breastbone: a deep dark split down the middle
            if abs(x + 0.03) < 0.05:
                push -= 0.04 * inside * (1 - abs(x + 0.03) / 0.05)
            # torn, curled skin round the edge
            rim = max(0.0, 1 - abs(e - 1.02) / 0.1)
            push += 0.014 * rim
            # wet, ropey muscle in there
            push += 0.012 * inside * noise.noise(V((x * 30, y * 30, z * 6)))

        # --- sunken belly below the ribs (under the gown, but it shows through the hole's bottom)
        if 4.9 < z < 5.5 and y < 0.05:
            k = math.sin((z - 4.9) / 0.6 * math.pi)
            radial = V((x, y - 0.06, 0)).normalized()
            push -= 0.07 * k * max(0, -radial.y)
            n = radial

        # --- collarbones and the hollows above them
        for s in (1, -1):
            dd, _ = seg_dist(p, V((s * 0.05, -0.14, 6.68)), V((s * 0.58, -0.05, 6.66)))
            if dd < 0.07 and y < 0:
                push += 0.03 * (1 - dd / 0.07) ** 1.5
            dd2, _ = seg_dist(p, V((s * 0.1, -0.09, 6.8)), V((s * 0.45, -0.03, 6.76)))
            if dd2 < 0.07:
                push -= 0.022 * (1 - dd2 / 0.07)

        # --- vertebrae down the back (a strip shows where the gown gapes)
        if 4.6 < z < 6.95 and abs(x) < 0.07 and y > 0.1:
            ph = (z - 4.6) / 0.17
            push += max(math.cos(ph * 2 * math.pi), 0) ** 3 * 0.035 * (1 - abs(x) / 0.07)

        # --- shoulder blades
        for s in (1, -1):
            d = (p - V((s * 0.22, 0.25, 6.3))).length
            if d < 0.2 and y > 0.1:
                push += 0.04 * (1 - d / 0.2) ** 2

        # --- the neck: stringy tendons and a jutting adam's apple
        if 6.8 < z < 7.65:
            ang = math.atan2(x, -(y + 0.04))
            push += 0.012 * max(math.cos(ang * 3), 0) ** 3
            d = (p - V((0, -0.1, 7.2))).length
            if d < 0.07:
                push += 0.025 * (1 - d / 0.07) ** 2

        # --- knobbly joints and knuckles
        for name, amount, radius in (("Elbow", 0.045, 0.12), ("Wrist", 0.022, 0.08), ("Knee", 0.03, 0.17)):
            for side in ("L", "R"):
                d = (p - J[name + "." + side]).length
                if d < radius:
                    push += amount * (1 - d / radius) ** 2
        for side in ("L", "R"):
            for f in ("Index", "Middle", "Ring", "Pinky"):
                for i in (1, 2, 3):
                    d = (p - J["%s%d.%s" % (f, i, side)]).length
                    if d < 0.045:
                        push += 0.012 * (1 - d / 0.045)
            # tendons on the back of the hand
            h = S.HANDS[side]
            for off in (-0.1, -0.034, 0.032, 0.094):
                dd, t = seg_dist(p, h["wrist"] + h["lat"] * off * 0.4, h["palm_end"] + h["lat"] * off)
                if dd < 0.03 and (p - h["wrist"]).dot(h["palm"]) < 0:
                    push += 0.008 * (1 - dd / 0.03)
            # veins up the forearms
            dd, t = seg_dist(p, J["Elbow." + side], J["Wrist." + side])
            if dd < 0.2:
                vein = abs(noise.noise(V((x * 14, y * 14, z * 3))))
                if vein < 0.06:
                    push += 0.008 * (1 - vein / 0.06)

        # --- trousers: baggy folds bunching at the knees and over the shoes
        if z < 4.3:
            bunch = 0.012 * math.sin(z * 18 + noise.noise(p * 3) * 3)
            bunch *= 0.4 + 0.6 * max(smoothstep(1.1, 0.5, z), smoothstep(0.4, 0.0, abs(z - 2.55)))
            push += bunch + 0.006 * noise.noise(p * 9)
        v.co = p + n * push


def build():
    obj = build_skin()
    plain = obj.copy()
    plain.data = obj.data.copy()
    plain.name = "BodyPlain"
    link(plain)                      # the unsculpted surface, for laying the ribs on
    sculpt(obj)
    shade_smooth(obj)
    return obj, plain
