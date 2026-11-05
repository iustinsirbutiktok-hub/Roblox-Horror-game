# The Stitcher's scissors: huge old tailor's shears, rusted and caked in blood,
# clenched in its right fist. Two halves crossing at a screw: "Scissors" holds
# one half (and the whole tool), "ScissorBlade" swings the other open and shut.
import bpy, bmesh, math
from mathutils import Vector as V, Matrix, noise
from common import link, tube, join, shade_smooth, apply_modifiers
import skeleton as S

BLADE = 1.12


def half(u, w, n, side, layer):
    """one half: a blade on the +side of the line, crossing over to a ring handle on the other side"""
    bm = bmesh.new()
    steps = 18
    # the blade: a long, slightly curved wedge, thick at the back, sharp at the edge
    spine, edge = [], []
    for i in range(steps + 1):
        t = i / steps
        along = 0.02 + (BLADE - 0.02) * t
        width = 0.1 * (1 - t ** 1.5) + 0.007
        bow = 0.015 * math.sin(t * math.pi)
        base = u * along + n * layer
        spine.append(base + w * side * (width + bow))
        edge.append(base + w * side * (bow * 0.3))
    thick = 0.012
    verts = []
    for i in range(steps + 1):
        a = bm.verts.new(spine[i] + n * thick * 0.5 * (1 if layer > 0 else -1))
        b = bm.verts.new(spine[i] - n * thick * 0.5 * (1 if layer > 0 else -1) * 0.2)
        c = bm.verts.new(edge[i])
        verts.append((a, b, c))
    for i in range(steps):
        a0, b0, c0 = verts[i]
        a1, b1, c1 = verts[i + 1]
        for f in ((a0, a1, c1, c0), (b0, c0, c1, b1), (a0, b0, b1, a1)):
            bm.faces.new(f)
    bm.faces.new(verts[0])
    bm.faces.new(tuple(reversed(verts[-1])))
    mesh = bpy.data.meshes.new("Blade")
    bm.to_mesh(mesh)
    bm.free()
    blade = link(bpy.data.objects.new("Blade", mesh))
    # the shank, back past the screw and across to the other side, then the ring
    shank_pts = [n * layer + u * 0.04 + w * side * 0.02, n * layer - u * 0.08,
                 n * layer - u * 0.2 - w * side * 0.035, n * layer - u * 0.3 - w * side * 0.06]
    shank = tube("Shank", shank_pts, [(0.03, 0.012), (0.034, 0.016), (0.03, 0.016), (0.026, 0.014)], sides=6)
    ring_c = n * layer - u * 0.39 - w * side * 0.09
    ring_pts = []
    for i in range(25):
        a = 2 * math.pi * i / 24
        ring_pts.append(ring_c + u * math.cos(a) * 0.085 + w * math.sin(a) * 0.065)
    ring = tube("Ring", ring_pts, [(0.021, 0.014)] * 25, sides=6, cap=False)
    return join([blade, shank, ring], "Half")


def build():
    h = S.HANDS["R"]
    g = h["grip_axis"]
    n = h["palm"].copy()
    n = (n - g * n.dot(g)).normalized()
    w = n.cross(g).normalized()
    pivot = h["grip"] + g * 0.2
    S.scissor_bones(pivot, g, n)
    fixed = half(g, w, n, 1, 0.009)
    moving = half(g, w, n, -1, -0.009)
    moving.name = "ScissorsBlade"
    screw = tube("Screw", [n * 0.028, n * -0.028], [0.022, 0.022], sides=10)
    fixed = join([fixed, screw], "ScissorsFixed")
    for o in (fixed, moving):
        o.location = pivot
        from common import select_only
        select_only(o)
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        shade_smooth(o, sharp_angle=40)
    fixed["bone"] = "Scissors"
    moving["bone"] = "ScissorBlade"
    return [fixed, moving]
