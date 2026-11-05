# The Stitcher's paint: per-vertex masks (where the blood, the trousers, the
# wound, the sockets are) and one shader per part, all baked down later into
# one texture per mesh. Colours here are the final texture colours.
import bpy, math
from mathutils import Vector as V, noise
from common import smoothstep, seg_dist
import skeleton as S
from body import wound_e
import head as Hd


# ---------------------------------------------------------------- masks
def set_mask(obj, fn, name="mask"):
    me = obj.data
    attr = me.color_attributes.get(name) or me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    for v in me.vertices:
        attr.data[v.index].color = fn(v.co.copy(), v.normal.copy())


def body_mask(p, n):
    J = S.J
    trousers = smoothstep(4.5, 4.3, p.z)
    blood = 0.0
    nail = 0.0
    for side in ("L", "R"):
        h = S.HANDS[side]
        along = (p - h["wrist"]).dot(h["fwd"])
        near = (p - h["wrist"]).length < 1.4
        if near and along > -0.6:
            # bloodiest at the fingertips, soaked up the forearm in runs
            blood = max(blood, smoothstep(-0.6, 0.6, along) * (1.0 if side == "R" else 0.75))
        for f in ("Index", "Middle", "Ring", "Pinky"):
            a, b = J["%s3.%s" % (f, side)], J["%s4.%s" % (f, side)]
            d, t = seg_dist(p, a, b)
            if t > 0.45 and d < 0.05 and (p - a).dot(h["palm"]) < 0.0:
                nail = 1.0
        a, b = J["Thumb3." + side], J["Thumb4." + side]
        d, t = seg_dist(p, a, b)
        if t > 0.45 and d < 0.05:
            nail = max(nail, 0.7)
    e = wound_e(p)
    flesh = smoothstep(1.05, 0.7, e) if e < 2 else 0.0
    # blood round the hole, run down the belly
    if e < 2.2:
        blood = max(blood, smoothstep(1.6, 1.0, e))
    # drool and blood down the throat from the mouth
    if 6.75 < p.z < 7.5 and p.y < -0.0:
        blood = max(blood, 0.6 * smoothstep(6.75, 7.4, p.z) * max(0, 1 - abs(p.x) / 0.12))
    # trouser hems soaked and filthy
    if p.z < 0.9:
        blood = max(blood, 0.4 * smoothstep(0.9, 0.3, p.z))
    return (trousers, blood, flesh, nail)


def head_mask(p, n):
    q = S.HEAD_M.inverted() @ p                 # back to design space
    HC = S.HC
    socket = 0.0
    for s in (1, -1):
        dx, dz = (q.x - s * 0.1) / 0.1, (q.z - HC.z) / 0.085
        r2 = dx * dx + dz * dz
        if q.y < HC.y - 0.1:
            socket = max(socket, smoothstep(1.4, 0.45, r2))
    phi = Hd.phi_of(q)
    zc = Hd.grin_z(phi)
    h = Hd.grin_h(phi)
    mouth = 0.0
    lip = 0.0
    blood = 0.0
    if abs(phi) < Hd.SLIT_MAX and q.y < HC.y + 0.15:
        dz = abs(q.z - zc)
        if h > 0:
            mouth = smoothstep(h + 0.004, h * 0.5, dz)
            lip = smoothstep(h + 0.035, h + 0.008, dz) * (1 - mouth)
        else:
            mouth = 0.0
        # blood run down from the mouth and the corners of the cut, over the chin
        if q.z < zc and abs(phi) < Hd.SLIT_MAX:
            run = 0.5 + 0.5 * noise.noise(V((phi * 9.0, 0.3, 0.7)))
            blood = max(blood, smoothstep(zc - 0.28 * run, zc, q.z) * 0.9)
        if Hd.GRIN_MAX * 0.8 < abs(phi) < Hd.SLIT_MAX:
            blood = max(blood, smoothstep(0.1, 0.0, abs(q.z - zc)))
    return (socket, blood, mouth, lip)


def gown_mask(p, n):
    e = wound_e(p, 0.04)
    blood = smoothstep(1.7, 1.0, e) if e < 3 else 0.0
    # soaked down the front under the hole
    drip = 0.0
    if p.y < 0.05 and -0.3 < p.x < 0.25 and p.z < 5.6:
        drip = smoothstep(2.0, 5.4, p.z) * (1 - abs(p.x + 0.03) / 0.28)
    grime = smoothstep(2.4, 1.3, p.z)
    return (grime, blood, drip, 0.0)


# ---------------------------------------------------------------- shader helpers
def node_mat(name, build, img):
    mat = bpy.data.materials.new(name)
    nt = mat.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs[0], out.inputs[0])
    nt.links.new(build(nt), emit.inputs[0])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    return mat


def n(nt, kind, **inputs):
    node = nt.nodes.new(kind)
    for k, v in inputs.items():
        if k.startswith("_"):
            setattr(node, k[1:], v)
        else:
            node.inputs[k].default_value = v
    return node


def mix(nt, a, b, fac):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = "MIX"
    if isinstance(fac, (int, float)):
        m.inputs[0].default_value = fac
    else:
        nt.links.new(fac, m.inputs[0])
    for i, x in ((6, a), (7, b)):
        if isinstance(x, tuple):
            m.inputs[i].default_value = (*x, 1)
        else:
            nt.links.new(x, m.inputs[i])
    return m.outputs[2]


def mul(nt, a, b):
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = "MULTIPLY"
    for i, x in ((0, a), (1, b)):
        if isinstance(x, (int, float)):
            m.inputs[i].default_value = x
        else:
            nt.links.new(x, m.inputs[i])
    m.use_clamp = True
    return m.outputs[0]


def maxf(nt, a, b):
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = "MAXIMUM"
    nt.links.new(a, m.inputs[0])
    nt.links.new(b, m.inputs[1])
    return m.outputs[0]


def ramp(nt, src, stops):
    r = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(src, r.inputs[0])
    els = r.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
    els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1)
    for pos, col in stops[1:-1]:
        e = els.new(pos)
        e.color = (*col, 1)
    return r.outputs[0]


def fac_ramp(nt, src, lo, hi):
    """0 below lo, 1 above hi (as a float)"""
    r = ramp(nt, src, [(lo, (0, 0, 0)), (hi, (1, 1, 1))])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(r, sep.inputs[0])
    return sep.outputs[0]


def position(nt, scale=(1, 1, 1)):
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    if scale == (1, 1, 1):
        return geo.outputs["Position"]
    vm = nt.nodes.new("ShaderNodeVectorMath")
    vm.operation = "MULTIPLY"
    nt.links.new(geo.outputs["Position"], vm.inputs[0])
    vm.inputs[1].default_value = scale
    return vm.outputs[0]


def noise_tex(nt, scale, detail=4, rough=0.55, vec=None):
    t = n(nt, "ShaderNodeTexNoise", Scale=scale, Detail=detail, Roughness=rough)
    nt.links.new(vec if vec is not None else position(nt), t.inputs["Vector"])
    return t.outputs["Fac"]


def veins(nt, scale, width=0.03):
    vor = n(nt, "ShaderNodeTexVoronoi", Scale=scale, _feature="DISTANCE_TO_EDGE")
    nt.links.new(position(nt), vor.inputs["Vector"])
    return fac_ramp(nt, vor.outputs["Distance"], width, 0.0)


def mask_channels(nt, name="mask"):
    attr = n(nt, "ShaderNodeAttribute", _attribute_name=name)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(attr.outputs["Color"], sep.inputs[0])
    return sep.outputs[0], sep.outputs[1], sep.outputs[2], attr.outputs["Alpha"]


def blood(nt, c, amount, scale=5.0, fresh=(0.3, 0.02, 0.015), dried=(0.15, 0.025, 0.018), streak=True):
    """blood over colour c where amount (a socket) is high: soaked-in stains with a brown halo,
    darker crusted patches, runs, splatter"""
    splash = noise_tex(nt, scale, 6, 0.7)
    vec = position(nt, (scale * 1.6, scale * 1.6, scale * 0.25)) if streak else None
    runs = noise_tex(nt, 1.0, 4, 0.6, vec)
    pattern = maxf(nt, splash, runs)
    th = nt.nodes.new("ShaderNodeMath")
    th.operation = "MULTIPLY_ADD"
    nt.links.new(amount, th.inputs[0])
    th.inputs[1].default_value = 0.42
    th.inputs[2].default_value = 0.0
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(pattern, add.inputs[0])
    nt.links.new(th.outputs[0], add.inputs[1])
    halo = fac_ramp(nt, add.outputs[0], 0.75, 0.81)
    cover = fac_ramp(nt, add.outputs[0], 0.8, 0.87)
    # the brown, diluted edge of the stain
    c = mix(nt, c, (0.36, 0.22, 0.16), mul(nt, halo, 0.55))
    shade = noise_tex(nt, scale * 2.5, 4, 0.6)
    col = mix(nt, dried, fresh, shade)
    # (not a flat coat: some of what's underneath still shows through)
    film = mul(nt, cover, 0.92)
    c = mix(nt, c, col, film)
    # splatter: specks flung across everything near it
    spk = n(nt, "ShaderNodeTexVoronoi", Scale=scale * 9, _feature="F1")
    nt.links.new(position(nt), spk.inputs["Vector"])
    dots = fac_ramp(nt, spk.outputs["Distance"], 0.14, 0.08)
    near = fac_ramp(nt, add.outputs[0], 0.7, 0.78)
    return mix(nt, c, fresh, mul(nt, dots, near))


# ---------------------------------------------------------------- the shaders
def skin_base(nt):
    """sickly, waxy grey skin: blotchy, bruised, grimy, a few thin dark veins"""
    mott = noise_tex(nt, 3.2, 6, 0.6)
    c = ramp(nt, mott, [(0.3, (0.5, 0.48, 0.42)), (0.5, (0.6, 0.58, 0.51)), (0.72, (0.68, 0.65, 0.57))])
    br = noise_tex(nt, 1.4, 3, 0.5)
    c = mix(nt, c, (0.42, 0.33, 0.35), mul(nt, fac_ramp(nt, br, 0.56, 0.74), 0.8))
    # veins: thin wandering lines (a band of a stretched noise), only here and there
    vn = noise_tex(nt, 1.0, 3, 0.5, position(nt, (7, 7, 2.5)))
    band = nt.nodes.new("ShaderNodeMath")
    band.operation = "PINGPONG"
    nt.links.new(vn, band.inputs[0])
    band.inputs[1].default_value = 0.5
    line = fac_ramp(nt, band.outputs[0], 0.47, 0.495)
    where = fac_ramp(nt, noise_tex(nt, 1.2, 2, 0.5), 0.5, 0.62)
    c = mix(nt, c, (0.36, 0.38, 0.42), mul(nt, mul(nt, line, where), 0.55))
    dirt = noise_tex(nt, 9, 4, 0.6)
    c = mix(nt, c, (0.34, 0.3, 0.24), mul(nt, fac_ramp(nt, dirt, 0.58, 0.75), 0.55))
    return c


def body_shader(nt):
    trousers, bl, flesh, nail = mask_channels(nt)
    c = skin_base(nt)
    # trousers: dark, stained grey-green cloth
    weave = noise_tex(nt, 60, 2, 0.4)
    tc = ramp(nt, noise_tex(nt, 5, 5, 0.6), [(0.35, (0.16, 0.17, 0.15)), (0.65, (0.27, 0.29, 0.25))])
    tc = mix(nt, tc, (0.12, 0.12, 0.11), mul(nt, weave, 0.25))
    c = mix(nt, c, tc, trousers)
    c = mix(nt, c, (0.2, 0.16, 0.1), mul(nt, nail, 1.0))
    # the wound: wet dark meat, black in the depths
    fl = ramp(nt, noise_tex(nt, 14, 6, 0.65), [(0.3, (0.1, 0.01, 0.01)), (0.55, (0.3, 0.05, 0.04)),
                                               (0.75, (0.42, 0.12, 0.1))])
    fl = mix(nt, fl, (0.45, 0.3, 0.26), mul(nt, veins(nt, 22, 0.008), 0.4))     # membrane strands
    c = mix(nt, c, fl, flesh)
    c = blood(nt, c, bl, 5.0)
    return c


def bone_shader(nt):
    g = noise_tex(nt, 9, 6, 0.6)
    c = ramp(nt, g, [(0.3, (0.6, 0.52, 0.38)), (0.62, (0.82, 0.76, 0.62))])
    crack = veins(nt, 5, 0.012)
    c = mix(nt, c, (0.3, 0.24, 0.18), crack)
    amt = noise_tex(nt, 2.0, 3, 0.5)
    return blood(nt, c, mul(nt, amt, 0.75), 7.0)


def head_shader(nt):
    socket, bl, mouth, lip = mask_channels(nt)
    c = skin_base(nt)
    # deathly grey-purple round the eyes, black in the sockets
    c = mix(nt, c, (0.25, 0.2, 0.22), mul(nt, socket, 1.6))
    c = mix(nt, c, (0.025, 0.02, 0.02), fac_ramp(nt, socket, 0.55, 0.85))
    # what's left of the lips: raw, red; inside: gums going black
    raw = ramp(nt, noise_tex(nt, 45, 4, 0.6), [(0.3, (0.2, 0.07, 0.06)), (0.7, (0.36, 0.15, 0.13))])
    c = mix(nt, c, raw, mul(nt, lip, 0.85))
    gums = ramp(nt, noise_tex(nt, 30, 4, 0.6), [(0.35, (0.2, 0.03, 0.03)), (0.65, (0.38, 0.09, 0.08))])
    c = mix(nt, c, gums, mouth)
    c = mix(nt, c, (0.03, 0.01, 0.01), fac_ramp(nt, mouth, 0.8, 1.0))
    c = blood(nt, c, bl, 7.0)
    return c


def teeth_shader(nt):
    g = noise_tex(nt, 40, 3, 0.6)
    c = ramp(nt, g, [(0.3, (0.5, 0.42, 0.27)), (0.65, (0.74, 0.67, 0.5))])
    rot = noise_tex(nt, 6, 2, 0.5)
    c = mix(nt, c, (0.16, 0.1, 0.06), fac_ramp(nt, rot, 0.66, 0.7))         # a few rotten black ones
    return blood(nt, c, mul(nt, noise_tex(nt, 3, 2, 0.5), 0.9), 18.0, streak=False)


def eye_shader_for(centre):
    def build(nt):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sub = nt.nodes.new("ShaderNodeVectorMath")
        sub.operation = "SUBTRACT"
        nt.links.new(geo.outputs["Position"], sub.inputs[0])
        sub.inputs[1].default_value = centre
        nrm = nt.nodes.new("ShaderNodeVectorMath")
        nrm.operation = "NORMALIZE"
        nt.links.new(sub.outputs[0], nrm.inputs[0])
        dot = nt.nodes.new("ShaderNodeVectorMath")
        dot.operation = "DOT_PRODUCT"
        nt.links.new(nrm.outputs[0], dot.inputs[0])
        dot.inputs[1].default_value = (0, -1, 0)
        c = mix(nt, (0.84, 0.82, 0.7), (0.55, 0.16, 0.12), mul(nt, veins(nt, 70, 0.012), 0.45))
        c = mix(nt, c, (0.66, 0.68, 0.64), fac_ramp(nt, dot.outputs["Value"], 0.86, 0.88))     # a pale, filmy iris
        c = mix(nt, c, (0.02, 0.02, 0.02), fac_ramp(nt, dot.outputs["Value"], 0.968, 0.972))   # a pinprick pupil
        return c
    return build


def flat(col):
    return lambda nt: mix(nt, col, col, 0.0)


def hair_shader(nt):
    g = noise_tex(nt, 25, 3, 0.5)
    return ramp(nt, g, [(0.35, (0.02, 0.02, 0.02)), (0.65, (0.08, 0.07, 0.06))])


def cloth_shader(base, light, grime_col=(0.33, 0.3, 0.22), soak=0.0, masked=False, blood_scale=3.2):
    def build(nt):
        g = noise_tex(nt, 4, 5, 0.55)
        c = ramp(nt, g, [(0.35, base), (0.65, light)])
        weave = noise_tex(nt, 80, 2, 0.4)
        c = mix(nt, c, tuple(x * 0.75 for x in base), mul(nt, weave, 0.3))
        s = noise_tex(nt, 1.6, 4, 0.6)
        c = mix(nt, c, grime_col, mul(nt, fac_ramp(nt, s, 0.55, 0.72), 0.75))
        if masked:
            grime, bl, drip, _ = mask_channels(nt)
            c = mix(nt, c, (0.22, 0.2, 0.15), mul(nt, grime, 0.7))
            amount = maxf(nt, maxf(nt, bl, drip), mul(nt, noise_tex(nt, 0.8, 2, 0.5), 0.55 + soak))
        else:
            amount = mul(nt, noise_tex(nt, 0.8, 2, 0.5), 0.55 + soak)
        return blood(nt, c, amount, blood_scale)
    return build


def leather_shader(nt):
    g = noise_tex(nt, 12, 5, 0.6)
    c = ramp(nt, g, [(0.3, (0.1, 0.07, 0.05)), (0.7, (0.22, 0.15, 0.1))])
    scuff = noise_tex(nt, 30, 3, 0.6)
    c = mix(nt, c, (0.3, 0.24, 0.18), fac_ramp(nt, scuff, 0.68, 0.75))
    # the sole
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    c = mix(nt, c, (0.06, 0.05, 0.045), fac_ramp(nt, sep.outputs["Z"], 0.05, 0.035))
    return blood(nt, c, mul(nt, noise_tex(nt, 2, 2, 0.5), 0.8), 9.0, streak=False)


def bandage_shader(nt):
    g = noise_tex(nt, 20, 4, 0.6)
    c = ramp(nt, g, [(0.3, (0.6, 0.55, 0.42)), (0.7, (0.74, 0.7, 0.6))])
    st = noise_tex(nt, 4, 4, 0.6)
    c = mix(nt, c, (0.56, 0.47, 0.27), fac_ramp(nt, st, 0.55, 0.7))          # old yellow stains
    return blood(nt, c, mul(nt, noise_tex(nt, 1.5, 3, 0.5), 1.15), 8.0)


def steel_shader(soak):
    def build(nt):
        g = noise_tex(nt, 18, 4, 0.5)
        c = ramp(nt, g, [(0.35, (0.34, 0.35, 0.36)), (0.65, (0.6, 0.61, 0.63))])
        brush = noise_tex(nt, 1.0, 2, 0.4, position(nt, (2, 2, 60)))
        c = mix(nt, c, (0.7, 0.71, 0.72), mul(nt, fac_ramp(nt, brush, 0.6, 0.75), 0.5))
        rust = noise_tex(nt, 7, 6, 0.65)
        c = mix(nt, c, (0.38, 0.21, 0.1), fac_ramp(nt, rust, 0.6, 0.7))
        return blood(nt, c, mul(nt, noise_tex(nt, 2.2, 3, 0.5), soak), 9.0)
    return build
