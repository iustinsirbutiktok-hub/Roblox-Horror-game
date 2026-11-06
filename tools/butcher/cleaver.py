# The Butcher's cleaver: a big, heavy meat cleaver, its broad blade nicked
# and pitted, a hole through the far corner, a riveted wooden handle, all of
# it caked in old blood. Clenched in the right fist, hanging out and down from
# the little-finger side with its flat to the front.
import bpy, bmesh, math
from mathutils import Vector as V, Matrix, noise
from common import link, tube, join, shade_smooth, apply_modifiers, select_only
import skeleton as S

LENGTH, HEIGHT = 0.86, 0.44


def frame():
    h = S.HANDS["R"]
    g = h["grip_axis"].normalized()                                 # along the spine, away from the fist
    w = (V((0, 0, -1)) - g * g.z)
    w = w.normalized() if w.length > 1e-4 else h["fwd"]
    w = (w - g * w.dot(g)).normalized()                             # across the blade, to the edge
    n = g.cross(w).normalized()                                     # the flat's normal
    return h["grip"], g, w, n


def blade(o, g, w, n):
    """a wedge: thick along the spine, thinning to the edge, the edge bellied and nicked"""
    bm = bmesh.new()
    nu, nv = 30, 14
    front, back = [], []
    for i in range(nu + 1):
        u = i / nu
        rf, rb = [], []
        for j in range(nv + 1):
            v = j / nv
            belly = 0.03 * math.sin(u * math.pi) + 0.015 * u
            depth = HEIGHT * v + belly * v
            nick = 0.012 * max(0, noise.noise(V((u * 25, 1.5, 0.3)))) * (v > 0.97)
            p = o + g * (0.27 + LENGTH * u) + w * (depth - nick)
            half = 0.017 * (1 - v) ** 0.8 + 0.0015
            rf.append(bm.verts.new(p + n * half))
            rb.append(bm.verts.new(p - n * half))
        front.append(rf)
        back.append(rb)
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((front[i][j], front[i + 1][j], front[i + 1][j + 1], front[i][j + 1]))
            bm.faces.new((back[i][j], back[i][j + 1], back[i + 1][j + 1], back[i + 1][j]))
    for i in range(nu):           # the spine and the edge
        bm.faces.new((front[i][0], back[i][0], back[i + 1][0], front[i + 1][0]))
        bm.faces.new((front[i][nv], front[i + 1][nv], back[i + 1][nv], back[i][nv]))
    for j in range(nv):           # the heel and the toe
        bm.faces.new((front[0][j], front[0][j + 1], back[0][j + 1], back[0][j]))
        bm.faces.new((front[nu][j], back[nu][j], back[nu][j + 1], front[nu][j + 1]))
    mesh = bpy.data.meshes.new("Blade")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("Blade", mesh))
    # the hole through the far top corner
    hole_c = o + g * (0.27 + LENGTH * 0.88) + w * (HEIGHT * 0.16)
    cut = tube("Hole", [hole_c + n * 0.08, hole_c - n * 0.08], [0.034, 0.034], sides=20)
    m = obj.modifiers.new("Hole", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = cut
    m.solver = "EXACT"
    apply_modifiers(obj)
    bpy.data.objects.remove(cut)
    return obj


def build():
    o, g, w, n = frame()
    parts = [blade(o, g, w, n)]
    # the bolster, a steel collar between the handle and the blade
    parts.append(tube("Bolster", [o + g * 0.22 + w * 0.02, o + g * 0.28 + w * 0.02],
                      [(0.052, 0.04), (0.052, 0.04)], sides=12))
    # the handle: worn wood, slightly bellied, three brass rivets through it
    pts = [o + g * t + w * 0.02 for t in (0.23, 0.1, -0.05, -0.2, -0.27)]
    parts.append(tube("Handle", pts, [(0.048, 0.034), (0.052, 0.036), (0.054, 0.037), (0.05, 0.035), (0.04, 0.03)],
                      sides=12))
    for t in (0.12, -0.02, -0.16):
        c = o + g * t + w * 0.02
        parts.append(tube("Rivet", [c + n * 0.042, c - n * 0.042], [0.011, 0.011], sides=8))
    obj = join(parts, "Cleaver")
    shade_smooth(obj, sharp_angle=35)
    obj["bone"] = "Cleaver"
    S.b("Cleaver", o - g * 0.27, o + g * 0.27, "Hand.R")
    return obj
