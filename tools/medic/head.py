# The Medic's head: a big cracked skull (huge hollow eye sockets, long rows of
# teeth), a separate hanging jaw, tiny eyes deep in the sockets, and a torn
# surgical mask pulled down round its throat.
import bpy, bmesh, math, random
from mathutils import Vector as V, Matrix
from common import link, apply_modifiers, select_only, decimate, shade_smooth

rnd = random.Random(1987)

SKULL_C = V((0, -0.2, 7.62))


def blob(name, loc, scale, segs=32):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=1.0)
    bmesh.ops.scale(bm, vec=V(scale), verts=bm.verts)
    bmesh.ops.translate(bm, vec=V(loc), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    return link(bpy.data.objects.new(name, mesh))


def union(objs, name):
    select_only(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = objs[0]
    obj.name = name
    return obj


def voxel(obj, size):
    m = obj.modifiers.new("Remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = size
    m.adaptivity = 0
    apply_modifiers(obj)


def cut(obj, cutter):
    m = obj.modifiers.new("Cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = cutter
    m.solver = "EXACT"
    apply_modifiers(obj)
    bpy.data.objects.remove(cutter)


def smooth(obj, factor=0.5, repeat=4):
    m = obj.modifiers.new("Smooth", "SMOOTH")
    m.factor = factor
    m.iterations = repeat
    apply_modifiers(obj)


def skull():
    c = SKULL_C
    parts = [
        blob("cranium", c + V((0, 0.06, 0.1)), (0.31, 0.37, 0.36)),
        blob("brow", c + V((0, -0.24, 0.02)), (0.28, 0.08, 0.06)),
        blob("face", c + V((0, -0.2, -0.2)), (0.22, 0.15, 0.24)),
        blob("maxilla", c + V((0, -0.24, -0.4)), (0.15, 0.1, 0.13)),
        blob("cheekL", c + V((0.19, -0.17, -0.18)), (0.08, 0.12, 0.06)),
        blob("cheekR", c + V((-0.19, -0.17, -0.18)), (0.08, 0.12, 0.06)),
        blob("archL", c + V((0.25, 0.0, -0.18)), (0.04, 0.16, 0.04)),
        blob("archR", c + V((-0.25, 0.0, -0.18)), (0.04, 0.16, 0.04)),
        blob("back", c + V((0, 0.26, -0.12)), (0.2, 0.14, 0.18)),
    ]
    sk = union(parts, "Skull")
    voxel(sk, 0.014)
    # huge, deep, slightly uneven eye sockets
    for s, lift in ((1, 0.0), (-1, 0.012)):
        cutter = blob("socket", c + V((s * 0.115, -0.37, -0.06 + lift)), (0.11, 0.17, 0.125), 24)
        cut(sk, cutter)
    # the nose hole: an upside-down heart
    for s in (1, -1):
        cutter = blob("nose", c + V((s * 0.022, -0.33, -0.25)), (0.03, 0.12, 0.065), 16)
        cut(sk, cutter)
    # temples sunken in
    smooth(sk, 0.4, 3)
    decimate(sk, 2600)
    shade_smooth(sk, 50)
    return sk


def teeth(name, arc_y, z, count, length, upper):
    """a row of long teeth along the front of the jaw"""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for i in range(count):
        a = (i / (count - 1) - 0.5) * math.radians(150)
        x = math.sin(a) * 0.16
        y = arc_y - math.cos(a) * 0.12
        if rnd.random() < 0.12:
            continue                                   # one missing here and there
        w = 0.016 + 0.006 * rnd.random()
        ln = length * (0.75 + 0.5 * rnd.random()) * (1 - 0.3 * abs(math.sin(a)))
        r = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=w, radius2=w * 0.45,
                                  depth=ln)
        verts = r["verts"]
        # pointing down (upper row) or up (lower row), splayed a little, rotted
        tilt = Matrix.Rotation(rnd.uniform(-0.12, 0.12), 4, "Y") @ Matrix.Rotation(rnd.uniform(-0.1, 0.15), 4, "X")
        if upper:
            tilt = Matrix.Rotation(math.pi, 4, "X") @ tilt
        bmesh.ops.transform(bm, matrix=tilt, verts=verts)
        bmesh.ops.scale(bm, vec=V((1, 0.7, 1)), verts=verts)
        bmesh.ops.rotate(bm, cent=V((0, 0, 0)), matrix=Matrix.Rotation(-a, 3, "Z"), verts=verts)
        bmesh.ops.translate(bm, vec=V((x, y, z + (-ln / 2 if upper else ln / 2))), verts=verts)
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new(name, mesh))
    shade_smooth(obj, 40)
    return obj


def jaw():
    """the mandible: a bony U from hinge to hinge, hanging long"""
    c = SKULL_C
    pts = []
    for s in (1, -1):
        pts.append([V((s * 0.25, -0.1, c.z - 0.22)), V((s * 0.23, -0.2, c.z - 0.6)),
                    V((s * 0.17, -0.38, c.z - 0.74)), V((s * 0.07, -0.48, c.z - 0.79))])
    chin = V((0, -0.51, c.z - 0.8))
    verts = pts[0] + [chin] + list(reversed(pts[1]))
    mesh = bpy.data.meshes.new("Jaw")
    mesh.from_pydata(verts, [(i, i + 1) for i in range(len(verts) - 1)], [])
    obj = link(bpy.data.objects.new("Jaw", mesh))
    sk = obj.modifiers.new("Skin", "SKIN")
    data = mesh.skin_vertices[0].data
    radii = [0.05, 0.05, 0.05, 0.055, 0.06, 0.055, 0.05, 0.05, 0.05]
    for i, r in enumerate(radii):
        data[i].radius = (r, r * 1.6)
    data[4].use_root = True
    obj.modifiers.new("Sub", "SUBSURF").levels = 2
    apply_modifiers(obj)
    decimate(obj, 900)
    shade_smooth(obj, 50)
    return obj


def eyes():
    c = SKULL_C
    objs = []
    for s in (1, -1):
        e = blob("Eye", c + V((s * 0.11, -0.21, -0.07)), (0.022, 0.022, 0.022), 10)
        objs.append(e)
    obj = union(objs, "Eyes")
    shade_smooth(obj, 80)
    return obj


def mask():
    """a surgical mask pulled down off the jaw, torn, hanging off one ear loop"""
    c = SKULL_C
    mesh = bpy.data.meshes.new("Mask")
    bm = bmesh.new()
    nx, nz = 12, 9
    grid = []
    for iz in range(nz + 1):
        row = []
        for ix in range(nx + 1):
            u = ix / nx - 0.5                         # -0.5 .. 0.5 across
            v = iz / nz                               # 0 top .. 1 bottom
            ang = u * math.radians(130)
            rad = 0.2 + 0.05 * v
            x = math.sin(ang) * rad
            y = -math.cos(ang) * rad - 0.24
            # tilted: the left loop still holds, the right side has dropped
            z = c.z - 0.86 - v * 0.3 - 0.16 * (u + 0.5) ** 1.6
            # three pleats, crumpled
            z += 0.02 * math.sin(v * math.pi * 3)
            y -= 0.02 * math.cos(v * math.pi * 3) + 0.012 * math.sin(u * 13 + v * 7)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for iz in range(nz):
        for ix in range(nx):
            # a ragged tear up from the bottom
            if iz >= nz - 1 - ix // 3 and 3 <= ix <= 5:
                continue
            bm.faces.new((grid[iz][ix], grid[iz][ix + 1], grid[iz + 1][ix + 1], grid[iz + 1][ix]))
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Mask", mesh))
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 0.012
    apply_modifiers(obj)
    # ear loops: one still round the jaw hinge, one snapped and dangling
    loops = []
    left = grid[0][0].co if False else None
    for pts in (
        [V((-0.23, -0.27, c.z - 0.86)), V((-0.27, -0.12, c.z - 0.6)), V((-0.26, -0.08, c.z - 0.3))],
        [V((0.24, -0.28, c.z - 1.12)), V((0.27, -0.22, c.z - 1.3)), V((0.25, -0.2, c.z - 1.45))],
    ):
        cd = bpy.data.curves.new("Loop", "CURVE")
        cd.dimensions = "3D"
        sp = cd.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, p in enumerate(pts):
            sp.points[i].co = (*p, 1)
        cd.bevel_depth = 0.008
        cd.bevel_resolution = 1
        lo = link(bpy.data.objects.new("Loop", cd))
        select_only(lo)
        bpy.ops.object.convert(target="MESH")
        loops.append(lo)
    obj = union([obj] + loops, "Mask")
    shade_smooth(obj, 60)
    return obj


def build():
    return {
        "Skull": skull(),
        "UpperTeeth": teeth("UpperTeeth", SKULL_C.y - 0.2, SKULL_C.z - 0.48, 14, 0.15, True),
        "Jaw": jaw(),
        "LowerTeeth": teeth("LowerTeeth", SKULL_C.y - 0.22, SKULL_C.z - 0.76, 14, 0.15, False),
        "Eyes": eyes(),
        "Mask": mask(),
    }
