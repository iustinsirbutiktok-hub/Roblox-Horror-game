import bpy, bmesh, math
from mathutils import Vector as V, Matrix
from mathutils.bvhtree import BVHTree


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def apply_modifiers(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    mesh = bpy.data.meshes.new_from_object(ev)
    obj.modifiers.clear()
    old = obj.data
    obj.data = mesh
    bpy.data.meshes.remove(old)


def select_only(obj):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def join(objs, name):
    objs = [o for o in objs if o is not None]
    select_only(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    select_only(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def decimate(obj, target_tris):
    t = tri_count(obj)
    if t <= target_tris:
        return
    m = obj.modifiers.new("Dec", "DECIMATE")
    m.ratio = target_tris / t
    m.use_collapse_triangulate = True
    apply_modifiers(obj)


def shade_smooth(obj, sharp_angle=None):
    for p in obj.data.polygons:
        p.use_smooth = True
    if sharp_angle is not None:
        m = obj.modifiers.new("Split", "EDGE_SPLIT")
        m.split_angle = math.radians(sharp_angle)
        m.use_edge_sharp = False
        apply_modifiers(obj)


def bvh(obj):
    return BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())


def blob(name, loc, scale, segs=32, rot=None):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=1.0)
    bmesh.ops.scale(bm, vec=V(scale), verts=bm.verts)
    if rot is not None:
        bmesh.ops.transform(bm, matrix=rot.to_4x4(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=V(loc), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    return link(bpy.data.objects.new(name, mesh))


def voxel(obj, size):
    m = obj.modifiers.new("Remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = size
    m.adaptivity = 0
    apply_modifiers(obj)


def smooth(obj, factor=0.5, repeat=4):
    m = obj.modifiers.new("Smooth", "SMOOTH")
    m.factor = factor
    m.iterations = repeat
    apply_modifiers(obj)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length, t


def frame_from(z):
    """two axes perpendicular to z"""
    z = z.normalized()
    x = z.cross(V((0, 0, 1))) if abs(z.z) < 0.95 else z.cross(V((1, 0, 0)))
    x.normalize()
    y = z.cross(x).normalized()
    return x, y


def tube(name, pts, radii, sides=6, cap=True, twist=0.0):
    """a tube through pts with a radius per point (radii: list or (rx, ry) pairs)"""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    n = len(pts)
    prev_x = None
    for i, p in enumerate(pts):
        if i == 0:
            d = pts[1] - pts[0]
        elif i == n - 1:
            d = pts[-1] - pts[-2]
        else:
            d = pts[i + 1] - pts[i - 1]
        d.normalize()
        if prev_x is None:
            x, y = frame_from(d)
        else:
            # parallel transport so the tube doesn't twist
            x = (prev_x - d * prev_x.dot(d)).normalized()
            y = d.cross(x).normalized()
        prev_x = x
        r = radii[i]
        rx, ry = (r, r) if not isinstance(r, (tuple, list)) else r
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides + twist * i
            ring.append(bm.verts.new(p + x * math.cos(a) * rx + y * math.sin(a) * ry))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
    if cap:
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            if (radii[0] if ring is rings[0] else radii[-1]) not in (0, (0, 0)):
                bm.faces.new(list(reversed(ring)) if rev else ring)
    bm.to_mesh(mesh)
    bm.free()
    return link(bpy.data.objects.new(name, mesh))


def bezier_points(ctrl, steps):
    """catmull-rom through ctrl points, steps samples per span"""
    out = []
    P = [ctrl[0]] + list(ctrl) + [ctrl[-1]]
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                              (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(ctrl[-1].copy())
    return out
