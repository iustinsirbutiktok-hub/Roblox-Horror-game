# Asylum furniture kit.
#
# Low-poly modelling helpers (boxes, cylinders, lathed shapes, bent tubes,
# cloth), a library of decayed materials (chipped enamel, rust, pitted
# chrome, cracked vinyl, stained mattress ticking, crazed porcelain, old
# wood...) that is baked into textures, and the FBX export for Roblox.
#
# Everything is modelled in metres. On export it's scaled to studs
# (STUDS_PER_M): an R6 character is 5 studs = 1.67 m, so a 0.55 m high bed
# comes in at 1.65 studs - just under the hips.
import bpy, bmesh, math, os, random
import numpy as np
from mathutils import Vector as V, Matrix, Euler

STUDS_PER_M = 3.0
TEX = 1024

PARTS = []
WORK = "/tmp/asylum_work"      # (build.py points this at the output folder: decal pictures go here)
STACK = [Matrix.Identity(4)]
EMPTIES = []


# ---------------------------------------------------------------- placing things

def T(at=(0, 0, 0), rot=(0, 0, 0), s=None):
    """a transform: move to `at`, turned by `rot` (degrees, XYZ)"""
    m = Matrix.Translation(V(at)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    if s is not None:
        s = (s, s, s) if isinstance(s, (int, float)) else s
        m = m @ Matrix.Diagonal((*s, 1))
    return m


class place:
    """with place(T(...)): everything made inside is moved by it (nests)"""

    def __init__(self, m):
        self.m = m

    def __enter__(self):
        STACK.append(STACK[-1] @ self.m)

    def __exit__(self, *a):
        STACK.pop()


def here(at=(0, 0, 0), rot=(0, 0, 0), s=None):
    return STACK[-1] @ T(at, rot, s)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def select_only(obj):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifiers(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    obj.modifiers.clear()
    old = obj.data
    obj.data = mesh
    bpy.data.meshes.remove(old)


def part(bm, material, m, smooth=40, name="part"):
    """bmesh -> an object in the piece (moved by m, sharp edges over `smooth` degrees)"""
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(smooth):
            e.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    me.materials.append(mat(material))
    PARTS.append(ob)
    return ob


# ---------------------------------------------------------------- shapes

def box(size, at=(0, 0, 0), rot=(0, 0, 0), m="paint", bevel=0.0, smooth=30):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=V(size), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=1, affect="EDGES",
                        profile=0.5, clamp_overlap=True)
    return part(bm, m, here(at, rot), smooth)


def cyl(r, h, at=(0, 0, 0), rot=(0, 0, 0), m="chrome", n=12, r2=None, caps=True, smooth=40):
    """along Z, centred"""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=n, radius1=r, radius2=r if r2 is None else r2,
                          depth=h)
    return part(bm, m, here(at, rot), smooth)


def lathe(profile, at=(0, 0, 0), rot=(0, 0, 0), m="paint", n=16, smooth=40, arc=None, stretch=(1, 1)):
    """spun round Z: profile = [(radius, z), ...] going up the outside (r=0 closes it).
    arc=(a0, a1) degrees spins only part of the way round."""
    bm = bmesh.new()
    rings = []
    full = arc is None
    a0, a1 = (0, 360) if full else arc
    steps = n if full else max(2, int(n * (a1 - a0) / 360))
    for r, z in profile:
        if r < 1e-7:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        ring = []
        for i in range(steps if full else steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            ring.append(bm.verts.new((math.cos(a) * r * stretch[0], math.sin(a) * r * stretch[1], z)))
        rings.append(ring)
    count = steps if full else steps
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(count):
            j = (i + 1) % len(a if len(a) > 1 else b) if full else i + 1
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[i]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    return part(bm, m, here(at, rot), smooth)


def sphere(r, at=(0, 0, 0), rot=(0, 0, 0), m="chrome", n=12, rings=7, squash=(1, 1, 1)):
    prof = [(math.sin(math.pi * i / rings) * r, -math.cos(math.pi * i / rings) * r) for i in range(rings + 1)]
    prof[0] = (0, -r)
    prof[-1] = (0, r)
    return lathe(prof, at, rot, m, n, 50, stretch=squash[:2])


def fillet(points, bend):
    """round off the corners of a polyline (radius about `bend`)"""
    if bend <= 0 or len(points) < 3:
        return [V(p) for p in points]
    pts = [V(p) for p in points]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        p0, p1, p2 = pts[i - 1], pts[i], pts[i + 1]
        d0, d1 = (p1 - p0), (p2 - p1)
        l0, l1 = d0.length, d1.length
        if l0 < 1e-6 or l1 < 1e-6:
            continue
        d0.normalize()
        d1.normalize()
        ang = math.acos(max(-1, min(1, d0.dot(d1))))
        if ang < math.radians(4):
            out.append(p1)
            continue
        t = min(bend * math.tan(ang / 2), l0 * 0.48, l1 * 0.48)
        a, b = p1 - d0 * t, p1 + d1 * t
        k = max(2, int(math.degrees(ang) / 18))
        for s in range(k + 1):
            u = s / k
            out.append(a * (1 - u) ** 2 + p1 * 2 * (1 - u) * u + b * u * u)
    out.append(pts[-1])
    return out


def sweep(points, r, m="chrome", n=8, bend=0.0, caps=True, closed=False, radii=None, smooth=50, up=None):
    """a tube along a path (points in the current place), corners rounded by `bend`"""
    pts = fillet(points, bend) if not closed else [V(p) for p in points]
    if radii is not None and bend > 0:
        radii = None
    count = len(pts)
    tangents = []
    for i in range(count):
        if closed:
            a, b = pts[i - 1], pts[(i + 1) % count]
        else:
            a, b = pts[max(i - 1, 0)], pts[min(i + 1, count - 1)]
        t = (b - a)
        tangents.append(t.normalized() if t.length > 1e-9 else V((0, 0, 1)))
    t0 = tangents[0]
    ref = V(up) if up else (V((0, 0, 1)) if abs(t0.z) < 0.9 else V((1, 0, 0)))
    nrm = (ref - t0 * ref.dot(t0)).normalized()
    bm = bmesh.new()
    rings = []
    prev_t = t0
    for i, (p, t) in enumerate(zip(pts, tangents)):
        q = prev_t.rotation_difference(t)
        nrm = (q @ nrm)
        nrm = (nrm - t * nrm.dot(t)).normalized()
        prev_t = t
        b = t.cross(nrm)
        rr = radii[i] if radii else r
        ring = [bm.verts.new(p + (nrm * math.cos(2 * math.pi * k / n) + b * math.sin(2 * math.pi * k / n)) * rr)
                for k in range(n)]
        rings.append(ring)
    segs = count if closed else count - 1
    for i in range(segs):
        a, c = rings[i], rings[(i + 1) % count]
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], c[(k + 1) % n], c[k]))
    if caps and not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    return part(bm, m, STACK[-1], smooth)


def torus(R, r, at=(0, 0, 0), rot=(0, 0, 0), m="chrome", n=16, k=6):
    with place(T(at, rot)):
        pts = [(math.cos(2 * math.pi * i / n) * R, math.sin(2 * math.pi * i / n) * R, 0) for i in range(n)]
        return sweep(pts, r, m, k, closed=True)


def rounded_rect(w, h, r, k=3, cx=0.0, cy=0.0):
    """2D points of a w x h rectangle with corners rounded by r (k points a corner)"""
    pts = []
    for qx, qy, a0 in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        ccx, ccy = cx + qx * (w / 2 - r), cy + qy * (h / 2 - r)
        for i in range(k + 1):
            a = math.radians(a0 + 90 * i / k)
            pts.append((ccx + math.cos(a) * r, ccy + math.sin(a) * r))
    return pts


def slab(poly, depth, at=(0, 0, 0), rot=(0, 0, 0), m="paint", smooth=30, bevel=0.0):
    """a flat shape (2D points in XY) given thickness along Z, centred"""
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, -depth / 2)) for x, y in poly]
    hi = [bm.verts.new((x, y, depth / 2)) for x, y in poly]
    n = len(poly)
    # (make it counter-clockwise so the faces point out)
    area = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
    if area < 0:
        lo.reverse()
        hi.reverse()
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    if bevel > 0:
        rim = [e for e in bm.edges if (e.verts[0].co.z > 0) == (e.verts[1].co.z > 0)]
        bmesh.ops.bevel(bm, geom=rim, offset=min(bevel, depth * 0.45), segments=1, affect="EDGES", profile=0.5,
                        clamp_overlap=True)
    return part(bm, m, here(at, rot), smooth)


def grid(w, h, nx, ny, shape, m="fabric", keep=None, thick=0.006, smooth=60, rough_edge=0.0, seed=1):
    """cloth: a w x h sheet, each point moved by shape(u, v) -> (x, y, z) (u, v in 0..1).
    keep(u, v) -> False cuts that square out (tears, holes)."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    vs = [[bm.verts.new(shape(i / nx, j / ny)) for i in range(nx + 1)] for j in range(ny + 1)]
    for j in range(ny):
        for i in range(nx):
            if keep and not keep((i + 0.5) / nx, (j + 0.5) / ny):
                continue
            bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    if rough_edge > 0:
        for v in bm.verts:
            if v.is_boundary:
                v.co += V((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * rough_edge
    ob = part(bm, m, STACK[-1], smooth)
    if thick > 0:
        sol = ob.modifiers.new("S", "SOLIDIFY")
        sol.thickness = thick
        sol.offset = 0
        apply_modifiers(ob)
    return ob


# ---------------------------------------------------------------- common bits

def caster(at, r=0.04, m_fork="chrome", swivel=0, stem=0.05):
    """a hospital castor: stem, swivel fork, rubber wheel (its bottom at at.z)"""
    with place(T(at, (0, 0, swivel))):
        cyl(0.012, stem, (0, 0, 2 * r + 0.02 + stem / 2), m=m_fork, n=8)
        cyl(0.022, 0.012, (0, 0, 2 * r + 0.02), m=m_fork, n=10)
        for s in (-1, 1):
            box((0.006, r * 1.3, r * 1.5), (s * 0.019, -r * 0.35, r + 0.02 - r * 0.45), m=m_fork, bevel=0.002)
        cyl(r, 0.028, (0, -r * 0.55, r), (0, 90, 0), m="rubber", n=12)
        cyl(r * 0.45, 0.034, (0, -r * 0.55, r), (0, 90, 0), m=m_fork, n=8)


def bolt(at, rot=(0, 0, 0), r=0.008, m="chrome"):
    cyl(r, r * 0.8, at, rot, m=m, n=6)


# ---------------------------------------------------------------- colours

def rgb(h):
    """'#rrggbb' screen colour -> linear (what the shader nodes want)"""
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def shade(c, f):
    return tuple(min(1, x * f) for x in c)


# ---------------------------------------------------------------- shader graph helpers

class G:
    """a little language for building the material node trees"""

    def __init__(self, nt):
        self.nt = nt
        geo = self.node("ShaderNodeNewGeometry")
        self.P = geo.outputs["Position"]
        self.N = geo.outputs["Normal"]
        sep = self.node("ShaderNodeSeparateXYZ")
        self.link(self.N, sep.inputs[0])
        self.up = sep.outputs["Z"]
        sp = self.node("ShaderNodeSeparateXYZ")
        self.link(self.P, sp.inputs[0])
        self.x, self.y, self.z = sp.outputs["X"], sp.outputs["Y"], sp.outputs["Z"]
        self.ao = self.image(IMAGES["AO"])
        self.edge = self.image(IMAGES["EDGE"])
        self.cav = self.sub(1.0, self.ao)
        self.seed = 0

    # -- plumbing
    def node(self, kind, **kw):
        n = self.nt.nodes.new(kind)
        for k, v in kw.items():
            if k.startswith("_"):
                setattr(n, k[1:], v)
            else:
                n.inputs[k].default_value = v
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def put(self, sock, x):
        if isinstance(x, (int, float)):
            sock.default_value = x
        elif isinstance(x, tuple):
            sock.default_value = (*x, 1) if len(sock.default_value) == 4 and len(x) == 3 else x
        else:
            self.link(x, sock)

    def image(self, img):
        n = self.node("ShaderNodeTexImage")
        n.image = img
        n.interpolation = "Linear"
        return n.outputs["Color"]

    # -- maths
    def math(self, op, a, b=0.0, clamp=False):
        n = self.node("ShaderNodeMath", _operation=op, _use_clamp=clamp)
        self.put(n.inputs[0], a)
        self.put(n.inputs[1], b)
        return n.outputs[0]

    def add(self, a, b, clamp=False):
        return self.math("ADD", a, b, clamp)

    def sub(self, a, b, clamp=False):
        return self.math("SUBTRACT", a, b, clamp)

    def mul(self, a, b, clamp=False):
        return self.math("MULTIPLY", a, b, clamp)

    def mx(self, a, b):
        return self.math("MAXIMUM", a, b)

    def mn(self, a, b):
        return self.math("MINIMUM", a, b)

    def clamp(self, a):
        return self.math("MULTIPLY", a, 1.0, True)

    def ms(self, x, a, b):
        """smoothstep: 0 below a, 1 above b (b < a flips it)"""
        n = self.node("ShaderNodeMapRange", _interpolation_type="SMOOTHSTEP", _clamp=True)
        self.put(n.inputs["Value"], x)
        lo, hi, flip = (a, b, False) if b >= a else (b, a, True)
        n.inputs["From Min"].default_value = lo
        n.inputs["From Max"].default_value = hi
        n.inputs["To Min"].default_value = 1.0 if flip else 0.0
        n.inputs["To Max"].default_value = 0.0 if flip else 1.0
        return n.outputs["Result"]

    def lerp(self, a, b, t):
        n = self.node("ShaderNodeMix", _data_type="FLOAT", _clamp_factor=True)
        self.put(n.inputs[0], t)
        self.put(n.inputs[2], a)
        self.put(n.inputs[3], b)
        return n.outputs[0]

    def mix(self, a, b, t, blend="MIX"):
        n = self.node("ShaderNodeMix", _data_type="RGBA", _blend_type=blend, _clamp_factor=True)
        self.put(n.inputs[0], t)
        self.put(n.inputs[6], a)
        self.put(n.inputs[7], b)
        return n.outputs[2]

    def vec(self, scale=(1, 1, 1), offset=(0, 0, 0), src=None):
        n = self.node("ShaderNodeVectorMath", _operation="MULTIPLY_ADD")
        self.put(n.inputs[0], src or self.P)
        n.inputs[1].default_value = scale
        n.inputs[2].default_value = offset
        return n.outputs[0]

    def warp(self, amount=0.05, scale=5.0):
        """the position, wobbled by a noise (for organic cracks and grain)"""
        n = self.node("ShaderNodeTexNoise", Scale=scale, Detail=3)
        self.link(self.vec(offset=self._seed()), n.inputs["Vector"])
        s = self.node("ShaderNodeVectorMath", _operation="MULTIPLY_ADD")
        self.link(n.outputs["Color"], s.inputs[0])
        s.inputs[1].default_value = (amount, amount, amount)
        s.inputs[2].default_value = (-amount / 2,) * 3
        a = self.node("ShaderNodeVectorMath", _operation="ADD")
        self.link(self.P, a.inputs[0])
        self.link(s.outputs[0], a.inputs[1])
        return a.outputs[0]

    def _seed(self):
        self.seed += 1
        return (self.seed * 17.31 % 50, self.seed * 7.77 % 50, self.seed * 3.13 % 50)

    # -- textures
    def noise(self, scale, detail=4, rough=0.55, vec=None, dist=0.0, lac=2.0):
        """fractal noise, stretched to 0..1 (Blender's barely leaves 0.43-0.63: about 0.5 +- 0.17 after this,
        so a threshold of 0.72 covers ~10% of the surface, 0.78 ~5%, 0.84 ~2.5%)"""
        n = self.node("ShaderNodeTexNoise", Scale=scale, Detail=detail, Roughness=rough, Distortion=dist, Lacunarity=lac)
        self.link(vec or self.vec(offset=self._seed()), n.inputs["Vector"])
        r = self.node("ShaderNodeMapRange", _clamp=True)
        self.link(n.outputs["Fac"], r.inputs["Value"])
        r.inputs["From Min"].default_value = 1 / 3
        r.inputs["From Max"].default_value = 2 / 3
        return r.outputs["Result"]

    def vor(self, scale, feature="F1", vec=None, out="Distance", rand=1.0):
        n = self.node("ShaderNodeTexVoronoi", Scale=scale, Randomness=rand, _feature=feature)
        self.link(vec or self.vec(offset=self._seed()), n.inputs["Vector"])
        return n.outputs[out]

    def wave(self, scale, axis="X", kind="BANDS", dist=0.0, detail=2.0, vec=None, profile="SIN", phase=0.0):
        n = self.node("ShaderNodeTexWave", Scale=scale, Distortion=dist, Detail=detail, _wave_type=kind,
                      _wave_profile=profile)
        n.inputs["Phase Offset"].default_value = phase
        if kind == "BANDS":
            n.bands_direction = axis
        else:
            n.rings_direction = axis if axis in ("X", "Y", "Z") else "SPHERICAL"
        self.link(vec or self.P, n.inputs["Vector"])
        return n.outputs["Fac"]

    def ramp(self, src, stops):
        r = self.node("ShaderNodeValToRGB")
        self.put(r.inputs[0], src)
        els = r.color_ramp.elements
        els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
        els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1)
        for pos, col in stops[1:-1]:
            e = els.new(pos)
            e.color = (*col, 1)
        return r.outputs[0]

    # -- decals: a picture projected from an empty (its local XY, `size` metres)
    def decal(self, c, path, matrix, size, depth=0.03, opacity=1.0):
        emp = bpy.data.objects.new("Decal", None)
        emp.matrix_world = matrix
        link(emp)
        EMPTIES.append(emp)
        tc = self.node("ShaderNodeTexCoord")
        tc.object = emp
        sx, sy = size
        uv = self.vec((1 / sx, 1 / sy, 1 / depth), (0.5, 0.5, 0), src=tc.outputs["Object"])
        im = bpy.data.images.load(path, check_existing=True)
        tn = self.node("ShaderNodeTexImage", _extension="CLIP")
        tn.image = im
        self.link(uv, tn.inputs["Vector"])
        sep = self.node("ShaderNodeSeparateXYZ")
        self.link(uv, sep.inputs[0])
        inside = self.ms(self.math("ABSOLUTE", sep.outputs["Z"]), 1.0, 0.6)
        a = self.mul(self.mul(tn.outputs["Alpha"], inside), opacity)
        return self.mix(c, tn.outputs["Color"], a)


# ---------------------------------------------------------------- weathering layers (shared)

def grime(g, c, amount=0.6, col="#2b261e", low=0.3):
    """dirt in the corners and creases, and splashed up from the floor"""
    n = g.noise(3.0, 5, 0.6)
    corner = g.mul(g.ms(g.cav, 0.08, 0.55), g.ms(n, 0.25, 0.65))
    floor = g.mul(g.ms(g.z, low, 0.0), g.ms(g.noise(7, 4), 0.3, 0.7))
    m = g.clamp(g.mul(g.add(corner, g.mul(floor, 0.7)), amount))
    return g.mix(c, rgb(col), m), m


def dust(g, c, amount=0.5, col="#8f897d"):
    m = g.mul(g.mul(g.ms(g.up, 0.5, 0.92), g.ms(g.noise(4.5, 5, 0.6), 0.3, 0.75)), g.ms(g.ao, 0.5, 0.9))
    m = g.mul(m, amount)
    return g.mix(c, rgb(col), m), m


def stains(g, c, amount=0.5, col="#8c7244", rim="#5a4224", scale=2.2, edge_dark=0.75):
    """old water / fluid stains: a tinted patch with a darker tide line round it"""
    n = g.noise(scale, 4, 0.55, dist=0.4)
    t = 0.72 - amount * 0.18
    inside = g.ms(n, t, t + 0.012)
    band = g.mul(g.ms(n, t - 0.016, t), g.ms(n, t + 0.03, t + 0.006))
    c = g.mix(c, rgb(col), g.mul(inside, 0.55))
    c = g.mix(c, rgb(rim), g.mul(band, edge_dark))
    return c, inside


def mold(g, c, amount=0.4, col="#1d2219", scale=2.6):
    area = g.mul(g.ms(g.noise(scale, 4, 0.6), 0.62 - amount * 0.15, 0.74 - amount * 0.15),
                 g.add(g.ms(g.cav, 0.05, 0.4), g.ms(g.z, 0.5, 0.0)))
    dots = g.ms(g.vor(140), 0.32, 0.08)
    m = g.clamp(g.mul(area, g.add(0.35, g.mul(dots, 0.65))))
    return g.mix(c, rgb(col), m), m


def blood(g, c, amount=0.4, scale=3.5):
    """dried blood: dark brown-red, splashes and smears with drips running down"""
    n = g.noise(scale, 6, 0.65, dist=0.25)
    t = 0.84 - amount * 0.12
    splash = g.ms(n, t, t + 0.02)
    drip = g.mul(g.ms(g.noise(1, 2, vec=g.vec((40, 40, 1.2), g._seed())), 0.6, 0.72),
                 g.ms(g.noise(scale * 0.7, 3), t - 0.08, t))
    drip = g.mul(drip, g.ms(g.up, 0.5, 0.1))
    m = g.clamp(g.add(splash, g.mul(drip, 0.8)))
    col = g.ramp(g.noise(12, 3), [(0.3, rgb("#2a0806")), (0.7, rgb("#4e120b"))])
    return g.mix(c, col, g.mul(m, 0.92)), m


def rust_colour(g, scale=30):
    return g.ramp(g.noise(scale, 6, 0.65), [(0.25, rgb("#2e1a10")), (0.45, rgb("#6a3518")),
                                            (0.6, rgb("#8f4a1d")), (0.75, rgb("#a8652d")), (0.9, rgb("#4a2a16"))])


# ---------------------------------------------------------------- materials
# each returns (colour, roughness, metalness, height)

def paint(g, base="#d8cfb6", chip=0.5, rust=0.5, dirt=0.6, gloss=0.5, sc=1.0, primer="#6a4a3a", under=None,
          dusty=0.5, bloodied=0.0, streaks=0.5, peel=0.5):
    """old enamel on steel: yellowed, filmed with grime, peeling in flakes (an
    older coat or red primer under it), chipped to bare steel at the edges,
    rust blisters and blooms bleeding down in streaks, damp near the floor"""
    b = rgb(base)
    c = g.mix(shade(b, 0.86), shade(b, 1.04), g.ms(g.noise(1.4 * sc, 5, 0.6), 0.3, 0.72))
    c = g.mix(c, shade(rgb("#b9a674"), sum(b) / 3 / 0.42), g.mul(g.ms(g.noise(0.8 * sc, 3), 0.35, 0.75), 0.4))
    film = g.ms(g.noise(2.4 * sc, 7, 0.68), 0.35, 0.85)
    c = g.mix(c, rgb("#6b604c"), g.mul(film, 0.42 * dirt))
    low = g.ms(g.z, 0.45, 0.0)
    c = g.mix(c, rgb("#4f4636"), g.mul(g.mul(low, g.ms(g.noise(5, 5), 0.2, 0.8)), 0.45 * dirt))
    # peeling: big flakes off the flat parts and the edges
    pf = g.add(g.add(g.noise(3.2 * sc, 8, 0.7, dist=0.25), g.mul(g.edge, 0.3)), g.mul(low, 0.1))
    pt = 0.86 - peel * 0.2
    peel_m = g.ms(pf, pt, pt + 0.008)
    peel_rim = g.sub(g.ms(pf, pt - 0.03, pt), peel_m, True)
    u = rgb(under or primer)
    underc = g.mix(shade(u, 0.8), shade(u, 1.1), g.ms(g.noise(9, 4), 0.3, 0.7))
    # chips: small, knocked off the corners and edges down to bare steel
    exposed = g.mul(g.edge, g.ms(g.ao, 0.55, 0.9))
    chip_field = g.add(g.noise(13 * sc, 8, 0.7), g.mul(exposed, 0.3 + 0.5 * chip))
    ct = 0.86 - chip * 0.12
    chip_m = g.ms(chip_field, ct, ct + 0.01)
    # rust: blooms (worse low down), blisters scattered over the paint, and in the chips
    rt = 0.8 - rust * 0.2
    bloom = g.ms(g.add(g.add(g.noise(2.0 * sc, 7, 0.62, dist=0.35), g.mul(low, 0.22)), g.mul(g.cav, 0.1)), rt, rt + 0.06)
    blister = g.ms(g.noise(24 * sc, 6, 0.72), 0.76 - rust * 0.08, 0.79 - rust * 0.08)
    blister = g.mul(blister, g.ms(g.noise(1.7 * sc, 3), 0.35, 0.6))
    rust_m = g.clamp(g.add(g.add(bloom, g.mul(chip_m, g.ms(g.noise(6, 4), 0.25, 0.5))),
                           g.add(blister, g.mul(peel_m, g.mul(g.ms(g.noise(4, 4), 0.5, 0.68), rust)))))
    rc = rust_colour(g)
    c = g.mix(c, shade(b, 0.5), g.mul(peel_rim, 0.75))
    c = g.mix(c, underc, peel_m)
    c = g.mix(c, rgb("#4a4741"), chip_m)
    c = g.mix(c, rc, rust_m)
    # rust bleeding down in thin lines, and dirty water run-off
    vert = g.ms(g.up, 0.75, 0.3)
    st = g.ms(g.noise(1.0, 3, 0.5, vec=g.vec((30 * sc, 30 * sc, 1.3 * sc), g._seed())), 0.56, 0.7)
    band = g.ms(g.noise(1.0, 3, 0.5, vec=g.vec((3.5 * sc, 3.5 * sc, 0.45 * sc), g._seed())), 0.5, 0.66)
    st_m = g.mul(g.mul(st, band), vert)
    c = g.mix(c, rgb("#7a4e2c"), g.mul(st_m, streaks * (0.35 + 0.5 * rust)))
    run = g.mul(g.mul(g.ms(g.noise(1.0, 3, 0.5, vec=g.vec((16 * sc, 16 * sc, 0.9 * sc), g._seed())), 0.55, 0.7),
                      g.ms(g.noise(1.0, 3, 0.5, vec=g.vec((2.5 * sc, 2.5 * sc, 0.35 * sc), g._seed())), 0.45, 0.62)), vert)
    c = g.mix(c, rgb("#3b3226"), g.mul(run, 0.35 * dirt))
    c, dirt_m = grime(g, c, dirt)
    c, dust_m = dust(g, c, dusty)
    if bloodied:
        c, _ = blood(g, c, bloodied)
    rough = g.lerp(0.6 - gloss * 0.3, 0.88, g.clamp(g.add(g.add(rust_m, film), g.add(dirt_m, dust_m))))
    rough = g.lerp(rough, 0.5, g.mul(chip_m, g.sub(1, rust_m)))
    metal = g.mul(chip_m, g.mul(g.sub(1.0, rust_m), 0.7))
    h = g.add(g.mul(peel_m, -0.5), g.mul(peel_rim, 0.5))
    h = g.add(h, g.add(g.mul(chip_m, -0.6), g.mul(g.mul(rust_m, g.noise(60, 4)), 0.9)))
    h = g.add(h, g.mul(blister, 0.6))
    return c, rough, metal, h


def chrome(g, rust=0.5, dull=0.8, sc=1.0, base="#9c9d99"):
    b = rgb(base)
    c = g.mix(shade(b, 0.72), b, g.ms(g.noise(3 * sc, 5), 0.25, 0.75))
    # dull, cloudy patches where the plating has gone
    c = g.mix(c, rgb("#7d7a70"), g.mul(g.ms(g.noise(1.6 * sc, 4), 0.35, 0.7), dull))
    c = g.mix(c, rgb("#5d5a52"), g.mul(g.ms(g.noise(6 * sc, 6), 0.55, 0.8), dull * 0.6))
    pits = g.ms(g.vor(90 * sc), 0.18, 0.05)
    pit_area = g.ms(g.noise(4 * sc, 4), 0.36, 0.56)
    c = g.mix(c, rgb("#4b3a2a"), g.mul(g.mul(pits, pit_area), 0.8))
    rm = g.ms(g.add(g.noise(3 * sc, 6, 0.6, dist=0.3), g.mul(g.cav, 0.3)), 0.82 - rust * 0.2, 0.86 - rust * 0.2)
    c = g.mix(c, rust_colour(g, 40), rm)
    c, dirt_m = grime(g, c, 0.55)
    c, dust_m = dust(g, c, 0.35)
    rough = g.lerp(0.22 + dull * 0.18, 0.85, g.clamp(g.add(rm, g.add(dirt_m, dust_m))))
    metal = g.mul(g.sub(1, rm), g.sub(1, g.mul(dirt_m, 0.6)))
    h = g.add(g.mul(g.mul(pits, pit_area), -0.4), g.mul(rm, g.mul(g.noise(70, 3), 0.8)))
    return c, rough, metal, h


def vinyl(g, base="#1e2420", crack=0.6, wear=0.5, tear=0.3, stain=0.4, bloodied=0.0, sc=1.0):
    b = rgb(base)
    c = g.mix(shade(b, 0.8), shade(b, 1.25), g.ms(g.noise(2.5 * sc, 5), 0.3, 0.75))
    # worn shiny-dull and faded at the edges and where people sat
    c = g.mix(c, shade(b, 1.9), g.mul(g.ms(g.add(g.edge, g.mul(g.noise(1.5), 0.4)), 0.35, 0.8), wear * 0.6))
    # crazed cracks showing the pale fabric backing
    cr = g.vor(16 * sc, "DISTANCE_TO_EDGE", vec=g.warp(0.06, 6))
    crack_m = g.mul(g.ms(cr, 0.035, 0.0), g.ms(g.noise(1.8 * sc, 4), 0.62 - crack * 0.25, 0.7 - crack * 0.25))
    fine = g.mul(g.ms(g.vor(45 * sc, "DISTANCE_TO_EDGE"), 0.03, 0.0), g.mul(g.ms(g.noise(3), 0.5, 0.7), crack))
    crack_all = g.clamp(g.add(crack_m, g.mul(fine, 0.6)))
    c = g.mix(c, rgb("#6f665a"), g.mul(crack_all, 0.85))
    # torn through: yellow foam with a dark lip
    tf = g.add(g.noise(2.2 * sc, 6, 0.65, dist=0.4), g.mul(g.edge, 0.25))
    tt = 0.82 - tear * 0.12
    tear_m = g.ms(tf, tt, tt + 0.006)
    lip = g.sub(g.ms(tf, tt - 0.02, tt), tear_m, True)
    foam = g.ramp(g.vor(70), [(0.0, rgb("#5e4a26")), (0.25, rgb("#a68a50")), (1.0, rgb("#c4a868"))])
    c = g.mix(c, shade(b, 0.4), lip)
    c = g.mix(c, foam, tear_m)
    c, st_m = stains(g, c, stain, "#4a4030", "#2b2418", 2.5)
    if bloodied:
        c, _ = blood(g, c, bloodied)
    c, dirt_m = grime(g, c, 0.5)
    c, dust_m = dust(g, c, 0.55, "#7d786c")
    rough = g.lerp(0.42, 0.9, g.clamp(g.add(g.add(crack_all, tear_m), g.add(dust_m, dirt_m))))
    h = g.add(g.mul(crack_all, -0.7), g.mul(tear_m, -1.0))
    h = g.add(h, g.mul(g.noise(120, 2), 0.12))
    return c, rough, 0.0, h


def fabric(g, base="#c9c3ae", stripe=None, axis="X", stripe_scale=9.0, stain=0.6, bloodied=0.0, moldy=0.35,
           dirt=0.5, sc=1.0):
    b = rgb(base)
    c = g.mix(shade(b, 0.88), shade(b, 1.04), g.ms(g.noise(3 * sc, 5), 0.3, 0.75))
    if stripe:
        w = g.wave(stripe_scale, axis, "BANDS", 0.0, 0)
        sm = g.mul(g.ms(w, 0.62, 0.68), 1.0)
        thin = g.mul(g.ms(g.wave(stripe_scale * 3, axis, phase=1.1), 0.9, 0.94), 0.6)
        c = g.mix(c, rgb(stripe), g.clamp(g.add(sm, thin)))
    weave = g.mul(g.wave(25 * sc, "X"), g.wave(25 * sc, "Y"))
    c = g.mix(c, shade(b, 0.82), g.mul(weave, 0.18))
    c, st_m = stains(g, c, stain, "#a68a52", "#6b5230", 2.0 * sc)
    c, st2 = stains(g, c, stain * 0.7, "#8a7a50", "#4f3e22", 4.5 * sc)
    if moldy:
        c, _ = mold(g, c, moldy)
    if bloodied:
        c, _ = blood(g, c, bloodied)
    c, dirt_m = grime(g, c, dirt, "#3a3326")
    c, _ = dust(g, c, 0.35, "#8a8476")
    h = g.add(g.mul(weave, 0.25), g.mul(g.noise(40, 3), 0.15))
    return c, 0.95, 0.0, h


def porcelain(g, base="#ddd9cd", craze=0.5, stain=0.6, chips=0.4, rusty=0.5, sc=1.0):
    b = rgb(base)
    c = g.mix(shade(b, 0.9), b, g.ms(g.noise(2 * sc, 4), 0.3, 0.7))
    cz = g.mul(g.ms(g.vor(30 * sc, "DISTANCE_TO_EDGE", vec=g.warp(0.02, 8)), 0.012, 0.0),
               g.ms(g.noise(2, 3), 0.55 - craze * 0.3, 0.65 - craze * 0.3))
    c = g.mix(c, rgb("#8a7a5c"), g.mul(cz, 0.45))
    # rust-brown stains running down from the taps and pooling
    st = g.noise(1.0, 3, 0.5, vec=g.vec((22 * sc, 22 * sc, 2 * sc), g._seed()))
    st_m = g.mul(g.ms(st, 0.55, 0.72), g.mul(g.ms(g.noise(1.7), 0.4, 0.6), rusty))
    c = g.mix(c, rgb("#8a5a2e"), g.mul(st_m, 0.75))
    c, s_m = stains(g, c, stain, "#b3a27c", "#6e5a38", 3.0 * sc)
    # chipped enamel: black iron showing, worst on the edges
    chf = g.add(g.noise(14 * sc, 6, 0.65), g.mul(g.edge, 0.5 * chips))
    chip_m = g.ms(chf, 0.86 - chips * 0.1, 0.87 - chips * 0.1)
    c = g.mix(c, rgb("#2a2420"), chip_m)
    c, dirt_m = grime(g, c, 0.65, "#4a3f2c")
    c, dust_m = dust(g, c, 0.4)
    rough = g.lerp(0.12, 0.7, g.clamp(g.add(g.add(st_m, dirt_m), g.add(dust_m, chip_m))))
    h = g.add(g.mul(cz, -0.35), g.mul(chip_m, -0.8))
    return c, rough, 0.0, h


def wood(g, base="#6b4a2e", dark="#3a2516", axis="Z", grain=6.0, wear=0.5, water=0.5, varnish=0.5, sc=1.0):
    b, d = rgb(base), rgb(dark)
    warp = g.vec((1, 1, 1) if axis != "Z" else (1, 1, 0.15), g._seed())
    w = g.wave(grain * sc, "X" if axis == "Z" else "Z", "BANDS", 6.0, 3.0, vec=warp, profile="SAW")
    c = g.ramp(w, [(0.0, d), (0.55, b), (1.0, shade(b, 1.18))])
    fine_scale = (60, 60, 4) if axis == "Z" else ((4, 60, 60) if axis == "X" else (60, 4, 60))
    fine = g.noise(1.0, 3, 0.5, vec=g.vec(fine_scale, g._seed()))
    c = g.mix(c, d, g.mul(g.ms(fine, 0.5, 0.75), 0.45))
    # varnish rubbed off the edges, raw grey-brown wood showing
    wm = g.mul(g.ms(g.add(g.edge, g.mul(g.noise(6), 0.3)), 0.45, 0.85), wear)
    c = g.mix(c, rgb("#8a7458"), g.mul(wm, 0.75))
    # water damage: black and swollen near the floor
    wd = g.mul(g.add(g.ms(g.z, 0.35, 0.0), g.mul(g.ms(g.noise(1.4), 0.6, 0.75), 0.6)), water)
    c = g.mix(c, rgb("#1e1610"), g.clamp(g.mul(wd, 0.8)))
    scr = g.mul(g.ms(g.noise(1, 2, vec=g.vec((3, 90, 3), g._seed())), 0.68, 0.72), 0.5)
    c = g.mix(c, rgb("#9a8466"), scr)
    c, dirt_m = grime(g, c, 0.55)
    c, dust_m = dust(g, c, 0.5)
    rough = g.lerp(0.45 - varnish * 0.15, 0.9, g.clamp(g.add(wm, g.add(dirt_m, dust_m))))
    h = g.add(g.mul(w, 0.25), g.mul(fine, 0.2))
    return c, rough, 0.0, h


def rubber(g, base="#1b1a19", sc=1.0):
    b = rgb(base)
    c = g.mix(shade(b, 0.8), shade(b, 1.6), g.ms(g.noise(4 * sc, 4), 0.3, 0.8))
    cr = g.mul(g.ms(g.vor(60 * sc, "DISTANCE_TO_EDGE"), 0.03, 0.0), g.ms(g.noise(2), 0.55, 0.7))
    c = g.mix(c, rgb("#5a564e"), g.mul(cr, 0.5))
    c, dirt_m = grime(g, c, 0.4, "#3b352a")
    c, dust_m = dust(g, c, 0.7, "#77736a")
    return c, 0.9, 0.0, g.mul(cr, -0.6)


def leather(g, base="#4b2f1d", wear=0.6, bloodied=0.0, sc=1.0):
    b = rgb(base)
    c = g.mix(shade(b, 0.75), shade(b, 1.2), g.ms(g.noise(5 * sc, 5), 0.3, 0.75))
    cr = g.mul(g.ms(g.vor(70 * sc, "DISTANCE_TO_EDGE"), 0.04, 0.0), 0.6)
    c = g.mix(c, shade(b, 0.5), cr)
    wm = g.mul(g.ms(g.add(g.edge, g.mul(g.noise(3), 0.4)), 0.4, 0.85), wear)
    c = g.mix(c, rgb("#8a6a48"), g.mul(wm, 0.6))
    if bloodied:
        c, _ = blood(g, c, bloodied, 5)
    c, dirt_m = grime(g, c, 0.5)
    return c, g.lerp(0.55, 0.85, wm), 0.0, g.add(g.mul(cr, -0.5), g.mul(g.noise(90, 3), 0.15))


def canvas(g, base="#a8a084", stain=0.6, moldy=0.5, sc=1.0):
    return fabric(g, base, stain=stain, moldy=moldy, dirt=0.6, sc=sc * 0.8)


def glass(g, base="#4a3a20", frost=0.3, dirt=0.6):
    b = rgb(base)
    c = g.mix(shade(b, 0.7), shade(b, 1.3), g.ms(g.noise(3, 4), 0.3, 0.7))
    c = g.mix(c, rgb("#b8b4a4"), g.mul(g.ms(g.noise(2.5, 4), 0.4, 0.75), frost))
    st = g.noise(1.0, 3, 0.5, vec=g.vec((25, 25, 2), g._seed()))
    c = g.mix(c, rgb("#5c5240"), g.mul(g.ms(st, 0.55, 0.7), 0.4 * dirt))
    c, dirt_m = grime(g, c, dirt)
    c, dust_m = dust(g, c, 0.6)
    return c, g.lerp(0.08, 0.8, g.clamp(g.add(dirt_m, dust_m))), 0.0, 0.0


def bakelite(g, base="#1b1512", sc=1.0):
    b = rgb(base)
    c = g.mix(shade(b, 0.8), shade(b, 1.5), g.ms(g.noise(6 * sc, 5), 0.3, 0.8))
    scr = g.mul(g.ms(g.noise(1, 2, vec=g.vec((2, 80, 80), g._seed())), 0.7, 0.74), 0.35)
    c = g.mix(c, rgb("#4a423a"), scr)
    c, dirt_m = grime(g, c, 0.4)
    c, dust_m = dust(g, c, 0.6)
    return c, g.lerp(0.3, 0.8, g.clamp(g.add(dirt_m, dust_m))), 0.0, g.mul(scr, -0.2)


def brass(g, sc=1.0):
    c = g.mix(rgb("#5a4420"), rgb("#9a7a3c"), g.ms(g.noise(4 * sc, 5), 0.3, 0.75))
    c = g.mix(c, rgb("#4f6e58"), g.mul(g.ms(g.cav, 0.1, 0.5), 0.8))
    c, dirt_m = grime(g, c, 0.4)
    return c, g.lerp(0.35, 0.8, dirt_m), g.sub(0.85, dirt_m), 0.0


def paper(g, base="#cdbf9b", sc=1.0):
    b = rgb(base)
    c = g.mix(shade(b, 0.85), b, g.ms(g.noise(4 * sc, 4), 0.3, 0.75))
    fox = g.ms(g.vor(30 * sc), 0.12, 0.02)
    c = g.mix(c, rgb("#8a6a3a"), g.mul(g.mul(fox, g.ms(g.noise(3), 0.5, 0.7)), 0.7))
    c, _ = stains(g, c, 0.5, "#a88f5c", "#6b5232", 3.0)
    c, _ = grime(g, c, 0.5)
    return c, 0.92, 0.0, g.mul(g.noise(50, 3), 0.2)


KINDS = dict(paint=paint, chrome=chrome, vinyl=vinyl, fabric=fabric, porcelain=porcelain, wood=wood, rubber=rubber,
             leather=leather, canvas=canvas, glass=glass, bakelite=bakelite, brass=brass, paper=paper)

# the stock materials (pieces add their own with material(...))
LIB = {
    "paint": ("paint", {}),
    "cream": ("paint", dict(base="#d6cdb2")),
    "mint": ("paint", dict(base="#9db5a2", chip=0.6)),
    "olive": ("paint", dict(base="#5f6650", chip=0.45, gloss=0.3)),
    "iron": ("paint", dict(base="#2c2c2a", chip=0.35, rust=0.65, gloss=0.25, primer="#3b3833")),
    "chrome": ("chrome", {}),
    "steel": ("chrome", dict(base="#8a8c8a", rust=0.55, dull=0.8)),
    "vinyl": ("vinyl", {}),
    "rubber": ("rubber", {}),
    "leather": ("leather", {}),
    "fabric": ("fabric", {}),
    "porcelain": ("porcelain", {}),
    "wood": ("wood", {}),
    "glass": ("glass", {}),
    "amber": ("glass", dict(base="#4a2c0e", frost=0.15)),
    "green_glass": ("glass", dict(base="#1f3a28", frost=0.15)),
    "bakelite": ("bakelite", {}),
    "brass": ("brass", {}),
    "paper": ("paper", {}),
}
MATS = {}
IMAGES = {}
DECALS = {}      # material key -> [(path, matrix, size)]


def material(key, kind, **kw):
    LIB[key] = (kind, kw)
    return key


def decal(key, path, matrix, size, depth=0.03):
    DECALS.setdefault(key, []).append((path, matrix, size, depth))


def mat(key):
    if key in MATS:
        return MATS[key]
    kind, kw = LIB[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    g = G(nt)
    g.seed = sum(ord(ch) * (i + 1) for i, ch in enumerate(key)) % 97
    c, rough, metal, h = KINDS[kind](g, **kw)
    for path, matrix, size, depth in DECALS.get(key, []):
        c = g.decal(c, path, matrix, size, depth)
    out = g.node("ShaderNodeOutputMaterial")
    out.name = "OUT"

    def emit(sock, name):
        e = g.node("ShaderNodeEmission")
        e.name = name
        g.put(e.inputs["Color"], sock if not isinstance(sock, (int, float)) else (sock, sock, sock))
        return e

    emit(c, "COLOR")
    rr = rough if not isinstance(rough, (int, float)) else rough
    emit(rr, "ROUGH")
    emit(metal, "METAL")
    # the edge mask (convex edges, from a bevel shader)
    bev = g.node("ShaderNodeBevel", Radius=0.018, _samples=8)
    dot = g.node("ShaderNodeVectorMath", _operation="DOT_PRODUCT")
    g.link(bev.outputs[0], dot.inputs[0])
    g.link(g.N, dot.inputs[1])
    edge = g.ms(g.sub(1.0, dot.outputs["Value"]), 0.01, 0.2)
    emit(edge, "EDGE")
    bsdf = g.node("ShaderNodeBsdfPrincipled")
    bsdf.name = "NORMAL"
    if not isinstance(h, (int, float)):
        bump = g.node("ShaderNodeBump", Strength=1.0, Distance=0.0015)
        g.link(h, bump.inputs["Height"])
        g.link(bump.outputs[0], bsdf.inputs["Normal"])
    target = g.node("ShaderNodeTexImage")
    target.name = "BAKE"
    nt.nodes.active = target
    MATS[key] = m
    return m


# ---------------------------------------------------------------- bake + export

def new_image(name, size, data):
    im = bpy.data.images.new(name, size, size, alpha=False, float_buffer=True)
    im.colorspace_settings.name = "Non-Color" if data else "Linear Rec.709"
    return im


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PARTS.clear()
    MATS.clear()
    EMPTIES.clear()
    DECALS.clear()
    del STACK[1:]
    IMAGES["AO"] = new_image("AO", TEX, True)
    IMAGES["EDGE"] = new_image("EDGE", TEX, True)
    IMAGES["AO"].generated_color = (1, 1, 1, 1)
    IMAGES["EDGE"].generated_color = (0, 0, 0, 1)


def _route(ob, name, img):
    for m in ob.data.materials:
        nt = m.node_tree
        out = nt.nodes["OUT"]
        src = nt.nodes[name]
        for l in list(out.inputs[0].links):
            nt.links.remove(l)
        nt.links.new(src.outputs[0], out.inputs[0])
        t = nt.nodes["BAKE"]
        t.image = img
        nt.nodes.active = t


def _bake(ob, kind, img, samples, route=None):
    scene = bpy.context.scene
    scene.cycles.samples = samples
    if route:
        _route(ob, route, img)
    else:
        for m in ob.data.materials:
            m.node_tree.nodes["BAKE"].image = img
            m.node_tree.nodes.active = m.node_tree.nodes["BAKE"]
    select_only(ob)
    bpy.ops.object.bake(type=kind, margin=6, margin_type="EXTEND", use_clear=True)
    return np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)


def _png(arr, path, srgb):
    from PIL import Image
    a = np.clip(arr, 0, 1)
    if srgb:
        a = np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1 / 2.4) - 0.055)
    a = (np.flipud(a) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(a).save(path)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def finish(name, out_dir, previews=None):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.bake.margin = 6
    for o in bpy.context.scene.objects:
        o.select_set(o in PARTS)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    # (concave flat shapes cut into triangles here, so Roblox can't get them wrong)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(ob.data)
    bm.free()

    select_only(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.0, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.004, shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")

    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
    world.light_settings.distance = 0.3
    scene.world = world

    # masks first (the materials read them): occlusion and worn edges
    # (into scratch images: a shader can't read the picture it's baking into)
    ao = _bake(ob, "AO", new_image("ao_tmp", TEX, True), 96)
    edge = _bake(ob, "EMIT", new_image("edge_tmp", TEX, True), 24, "EDGE")
    for im, px in ((IMAGES["AO"], ao), (IMAGES["EDGE"], edge)):
        im.pixels.foreach_set(px.ravel())
        im.update()
        im.pack()
    col_img = new_image(name + "_c", TEX, False)
    col = _bake(ob, "EMIT", col_img, 8, "COLOR")
    rough = _bake(ob, "EMIT", new_image(name + "_r", TEX, True), 4, "ROUGH")
    metal = _bake(ob, "EMIT", new_image(name + "_m", TEX, True), 2, "METAL")
    nrm_img = new_image(name + "_n", TEX, True)
    scene.render.bake.normal_space = "TANGENT"
    nrm = _bake(ob, "NORMAL", nrm_img, 4, "NORMAL")

    # occlusion and a touch of edge light baked into the colour (Roblox has neither)
    edge = edge[..., :1]
    a = np.clip(ao[..., :1], 0, 1)
    final = col.copy()
    final[..., :3] = col[..., :3] * (0.38 + 0.62 * a ** 1.25) * (1 + 0.14 * edge * a)
    os.makedirs(out_dir, exist_ok=True)
    paths = {k: os.path.join(out_dir, "%s_%s.png" % (name, k)) for k in ("color", "normal", "roughness", "metalness")}
    _png(final[..., :3], paths["color"], True)
    _png(nrm[..., :3], paths["normal"], False)
    _png(np.repeat(rough[..., :1], 3, 2), paths["roughness"], False)
    _png(np.repeat(metal[..., :1], 3, 2), paths["metalness"], False)
    if os.environ.get("ASYLUM_DEBUG"):
        _png(np.repeat(a, 3, 2), os.path.join(out_dir, name + "_dbg_ao.png"), False)
        _png(np.repeat(edge, 3, 2), os.path.join(out_dir, name + "_dbg_edge.png"), False)

    # the exported material: the baked colour and normal map
    fm = bpy.data.materials.new(name)
    fm.use_nodes = True
    nt = fm.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.8
    ci = bpy.data.images.load(paths["color"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = ci
    nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    ni = bpy.data.images.load(paths["normal"])
    ni.colorspace_settings.name = "Non-Color"
    nn = nt.nodes.new("ShaderNodeTexImage")
    nn.image = ni
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    ob.data.materials.clear()
    ob.data.materials.append(fm)

    # to studs, standing on its origin
    ob.scale = (STUDS_PER_M,) * 3
    select_only(ob)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for e in EMPTIES:
        bpy.data.objects.remove(e)
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0       # (Roblox: 1 Blender unit = 1 stud with FBX Units Scale)
    select_only(ob)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(out_dir, name + ".fbx"), use_selection=True, object_types={"MESH"},
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", global_scale=1.0,
        axis_forward="-Z", axis_up="Y", bake_anim=False, path_mode="COPY", embed_textures=True,
        mesh_smooth_type="FACE",
    )
    dims = ob.dimensions
    info = dict(name=name, tris=tri_count(ob), studs=tuple(round(d, 2) for d in dims))
    print("BUILT", info)
    if previews:
        render_previews(ob, out_dir, previews)
    return info


def render_previews(ob, out_dir, views):
    """views: [(suffix, camera location, look at, lens)] in studs"""
    scene = bpy.context.scene
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 720
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("Wp")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.06, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    scene.world = world
    fm = bpy.data.materials.new("Floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.09, 0.09, 0.085, 1)
    fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.data.materials.append(fm)
    size = max(ob.dimensions)
    for nm_, loc, energy, sz in (("Key", (1.0, -1.2, 1.5), 1800, 0.5), ("Rim", (-1.2, 1.4, 1.2), 900, 0.6),
                                 ("Fill", (-1.4, -1.0, 0.6), 250, 1.5)):
        ld = bpy.data.lights.new(nm_, "AREA")
        ld.energy = energy * (size / 6) ** 2
        ld.size = sz * size
        lo = link(bpy.data.objects.new(nm_, ld))
        lo.location = V(loc) * size
        lo.rotation_euler = (V((0, 0, ob.dimensions.z * 0.4)) - lo.location).to_track_quat("-Z", "Y").to_euler()
    for suffix, loc, at, lens in views:
        cd = bpy.data.cameras.new("C")
        cd.lens = lens
        co = link(bpy.data.objects.new("C", cd))
        co.location = loc
        co.rotation_euler = (V(at) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.camera = co
        scene.render.filepath = os.path.join(out_dir, "preview_%s_%s.png" % (ob.name, suffix))
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(co)


def auto_views(ob, close=None):
    """a three-quarter view from the front-right, and an optional close-up"""
    d = ob.dimensions
    c = V((0, 0, d.z * 0.45))
    r = max(d) * 1.55
    views = [("a", c + V((r * 0.62, -r * 0.78, r * 0.42)), c, 50)]
    if close:
        views.append(("b",) + close)
    return views


# ---------------------------------------------------------------- the pieces

PIECES = {}


def piece(name, close=None):
    """@piece("Name", close=(camera at, look at, lens) in studs) registers a builder"""
    def deco(fn):
        PIECES[name] = (fn, close)
        return fn
    return deco


# ---------------------------------------------------------------- pictures for decals (PIL)

FONTS = {
    "serif": "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
    "sans": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "cond": "/usr/share/fonts/truetype/liberation/LiberationSansNarrow-Bold.ttf",
    "mono": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "type": "/usr/share/fonts/X11/Type1/c0419bt_.pfb",
}


def _font(kind, size):
    from PIL import ImageFont
    for path in (FONTS.get(kind), FONTS["sans"]):
        try:
            return ImageFont.truetype(path, size)
        except Exception:
            continue
    return ImageFont.load_default()


def _save(im, name):
    os.makedirs(os.path.join(WORK, "_decals"), exist_ok=True)
    path = os.path.join(WORK, "_decals", name + ".png")
    im.save(path)
    return path


def gauge_png(name, label, top=100, unit="", step=None, red_from=None, needle=0.3, face=(226, 218, 196),
              size=512):
    """a round instrument dial: ticks, numbers, a red zone, the needle where it stuck"""
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = size / 2
    R = size * 0.48
    d.ellipse((c - R, c - R, c + R, c + R), fill=face + (255,), outline=(20, 18, 16, 255), width=int(size * 0.02))
    a0, a1 = 225, -45                                  # sweep, degrees (clockwise from left-bottom)
    step = step or top / 10
    n = int(round(top / step))
    if red_from is not None:
        for i in range(60):
            v0 = red_from + (top - red_from) * i / 60
            v1 = red_from + (top - red_from) * (i + 1) / 60
            for v in (v0, v1):
                pass
            aa0 = a0 + (a1 - a0) * v0 / top
            aa1 = a0 + (a1 - a0) * v1 / top
            d.arc((c - R * 0.86, c - R * 0.86, c + R * 0.86, c + R * 0.86), -aa0, -aa1 if aa1 < aa0 else -aa1,
                  fill=(170, 30, 24, 255), width=int(size * 0.035))
    f = _font("sans", int(size * 0.075))
    for i in range(n * 5 + 1):
        v = top * i / (n * 5)
        a = math.radians(a0 + (a1 - a0) * v / top)
        major = i % 5 == 0
        r0 = R * (0.74 if major else 0.8)
        d.line((c + math.cos(a) * r0, c - math.sin(a) * r0, c + math.cos(a) * R * 0.88, c - math.sin(a) * R * 0.88),
               fill=(18, 16, 14, 255), width=int(size * (0.012 if major else 0.006)))
        if major:
            t = ("%g" % v)
            tw = d.textlength(t, font=f)
            d.text((c + math.cos(a) * R * 0.6 - tw / 2, c - math.sin(a) * R * 0.6 - size * 0.04), t, font=f,
                   fill=(18, 16, 14, 255))
    lf = _font("serif", int(size * 0.07))
    for k, line in enumerate(label.split("\n")):
        tw = d.textlength(line, font=lf)
        d.text((c - tw / 2, c + R * 0.22 + k * size * 0.08), line, font=lf, fill=(30, 26, 22, 255))
    if unit:
        uf = _font("sans", int(size * 0.05))
        tw = d.textlength(unit, font=uf)
        d.text((c - tw / 2, c - R * 0.42), unit, font=uf, fill=(40, 36, 30, 255))
    a = math.radians(a0 + (a1 - a0) * needle)
    d.line((c - math.cos(a) * R * 0.12, c + math.sin(a) * R * 0.12, c + math.cos(a) * R * 0.8, c - math.sin(a) * R * 0.8),
           fill=(15, 12, 10, 255), width=int(size * 0.02))
    d.ellipse((c - size * 0.04, c - size * 0.04, c + size * 0.04, c + size * 0.04), fill=(25, 22, 20, 255))
    return _save(im, name)


def label_png(name, lines, w=512, h=160, bg=(214, 204, 176), fg=(24, 20, 16), font="sans", border=True, pad=0.12,
              size=None):
    """a plate or card with text on it (lines: list of strings, or (text, scale) pairs)"""
    from PIL import Image, ImageDraw
    im = Image.new("RGBA", (w, h), bg + (255,) if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if border and bg:
        d.rectangle((3, 3, w - 4, h - 4), outline=fg + (255,), width=max(2, h // 40))
    lines = [(l, 1.0) if isinstance(l, str) else l for l in lines]
    total = sum(s for _, s in lines)
    lh = (h * (1 - 2 * pad)) / total
    y = h * pad
    for text, sc in lines:
        fs = int((size or lh * 0.82) * sc)
        f = _font(font, fs)
        while d.textlength(text, font=f) > w * 0.92 and fs > 8:
            fs -= 2
            f = _font(font, fs)
        tw = d.textlength(text, font=f)
        d.text(((w - tw) / 2, y + (lh * sc - fs) / 2), text, font=f, fill=fg + (255,))
        y += lh * sc
    return _save(im, name)
