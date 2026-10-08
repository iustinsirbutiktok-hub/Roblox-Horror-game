# The Medic's clothes: a shredded hospital gown hanging off its ribs (open at
# the back over its spine), and IV lines taped into its arms, trailing loose.
import bpy, bmesh, math, random
from mathutils import Vector as V, noise
from common import link, apply_modifiers, select_only, shade_smooth
import skeleton as S

rnd = random.Random(31)


def gown(body):
    seg, rows = 30, 26
    top, bottom = 6.36, 2.3
    mesh = bpy.data.meshes.new("Gown")
    bm = bmesh.new()
    grid = []
    for r in range(rows + 1):
        z = top - (top - bottom) * r / rows
        row = []
        for i in range(seg):
            a = 2 * math.pi * i / seg                         # 0 = front
            # skirt: an oval round both legs, flaring out at the bottom
            flare = 1 + 0.06 * max(0, (4.0 - z) / 1.6)
            x = math.sin(a) * 0.56 * flare
            y = -math.cos(a) * 0.4 * flare + 0.03
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for r in range(rows):
        for i in range(seg):
            a = 2 * math.pi * (i + 0.5) / seg
            z = top - (top - bottom) * (r + 0.5) / rows
            side = abs(math.sin(a))
            if 5.4 < z < 6.02 and side > 0.8:
                continue                                     # armholes (it still hangs over the shoulders)
            if z > 4.6 and z < 6.15 and math.cos(a) < -0.94:
                continue                                     # open at the back
            bm.faces.new((grid[r][i], grid[r][(i + 1) % seg], grid[r + 1][(i + 1) % seg], grid[r + 1][i]))
    # shredded hem: each column torn off at a different height
    for i in range(seg):
        cut = rnd.choice((0, 0, 1, 1, 2, 3, 4))
        for r in range(rows - cut, rows):
            for f in list(grid[r][i].link_faces):
                if f.is_valid and all(v in (grid[r][i], grid[r][(i + 1) % seg], grid[r + 1][(i + 1) % seg], grid[r + 1][i]) for v in f.verts):
                    bm.faces.remove(f)
    # a few rips and holes
    for _ in range(5):
        r, i = rnd.randint(6, rows - 6), rnd.randrange(seg)
        for dr in range(rnd.randint(1, 3)):
            for f in list(grid[r + dr][i].link_faces):
                if f.is_valid and rnd.random() < 0.7:
                    bm.faces.remove(f)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Gown", mesh))

    # hug the body above the waist, hang free below the hips
    vg = obj.vertex_groups.new(name="wrap")
    for v in mesh.vertices:
        w = min(1.0, max(0.0, (v.co.z - 3.85) / 0.6))
        vg.add([v.index], w, "REPLACE")
    sw = obj.modifiers.new("Wrap", "SHRINKWRAP")
    sw.target = body
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.offset = 0.045
    sw.vertex_group = "wrap"
    apply_modifiers(obj)
    if obj.vertex_groups.get("wrap"):
        obj.vertex_groups.remove(obj.vertex_groups["wrap"])
    mesh = obj.data

    # wrinkles, sagging folds in the skirt, the hem ragged
    for v in mesh.vertices:
        p = v.co
        n = noise.noise(p * 3.1) * 0.02 + noise.noise(p * 9.0) * 0.006
        a = math.atan2(p.x, -p.y)
        folds = 0.04 * math.sin(a * 7 + noise.noise(p * 0.8) * 2) * min(1, max(0, (4.6 - p.z)) / 1.2)
        out = V((p.x, p.y - 0.03, 0))
        out = out.normalized() if out.length > 1e-4 else V((0, 0, 0))
        # (and nudged about so the weave and the rips aren't a neat grid)
        jitter = V((noise.noise(p * 7 + V((3, 0, 0))), noise.noise(p * 7 + V((0, 5, 0))), noise.noise(p * 7 + V((0, 0, 9))))) * 0.03
        v.co = p + out * (n + folds) + jitter
        if p.z < 3.0:
            v.co.z += rnd.uniform(-0.05, 0.08)
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.014
    sol.offset = 1
    apply_modifiers(obj)
    shade_smooth(obj, 70)
    return obj


def tube(points, radius, name):
    cd = bpy.data.curves.new(name, "CURVE")
    cd.dimensions = "3D"
    sp = cd.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for i, p in enumerate(points):
        bp = sp.bezier_points[i]
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    cd.bevel_depth = radius
    cd.bevel_resolution = 1
    cd.resolution_u = 5
    obj = link(bpy.data.objects.new(name, cd))
    select_only(obj)
    bpy.ops.object.convert(target="MESH")
    return obj


def tape(at, along, around, name):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    r = bmesh.ops.create_cube(bm, size=1)
    m = bmesh.ops.scale(bm, vec=V((0.16, 0.012, 0.09)), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    z = along.normalized()
    x = around.normalized()
    y = z.cross(x)
    from mathutils import Matrix
    obj.matrix_world = Matrix.Translation(at) @ Matrix((x, y, z)).transposed().to_4x4()
    return obj


def iv_lines():
    J = S.J
    objs = []
    # left arm: taped into the inside of the first forearm, the line hangs to the knee, cut
    a, b = J["Elbow1.L"], J["Elbow2.L"]
    d = (b - a).normalized()
    inner = V((-1, -0.3, 0)).normalized()
    start = a + d * 0.45 + inner * 0.075
    objs.append(tape(start, d, inner.cross(d), "TapeL"))
    pts = [start, start + V((-0.05, -0.12, -0.25)), start + V((-0.12, -0.2, -0.75)), start + V((-0.05, -0.15, -1.25)),
           start + V((0.06, -0.08, -1.55))]
    objs.append(tube(pts, 0.016, "LineL"))
    # right arm: two lines into the second forearm, one torn out and dangling
    a, b = J["Elbow2.R"], J["Wrist.R"]
    d = (b - a).normalized()
    inner = V((1, -0.3, 0)).normalized()
    start = a + d * 0.3 + inner * 0.065
    objs.append(tape(start, d, inner.cross(d), "TapeR"))
    pts = [start, start + V((0.08, -0.1, -0.3)), start + V((0.15, -0.05, -0.8)), start + V((0.1, 0.05, -1.1))]
    objs.append(tube(pts, 0.014, "LineR"))
    start2 = a + d * 0.55 + inner * 0.06
    pts = [start2, start2 + V((0.05, -0.15, -0.15)), start2 + V((0.02, -0.22, -0.5))]
    objs.append(tube(pts, 0.012, "LineR2"))
    select_only(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "IV"
    # (joined into the tape's space: bake that in so its coordinates are the world's)
    select_only(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    shade_smooth(obj, 50)
    return obj
