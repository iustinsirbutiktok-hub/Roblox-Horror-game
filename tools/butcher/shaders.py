# The Butcher's materials. Each part gets one material with three outputs that
# the build bakes, one after another, from the high-res parts onto the game
# meshes: the colour (through an Emission), the surface detail (a Bump into a
# BSDF, baked as a normal map) and the roughness (wet blood shines, canvas
# doesn't). Colours here are the final texture colours.
import bpy, math
from mathutils import Vector as V


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




# ---------------------------------------------------------------- more helpers
def mixf(nt, a, b, fac):
    """mix two floats (sockets or numbers)"""
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "FLOAT"
    for i, x in ((0, fac), (2, a), (3, b)):
        if isinstance(x, (int, float)):
            m.inputs[i].default_value = x
        else:
            nt.links.new(x, m.inputs[i])
    return m.outputs[0]


def addf(nt, a, b, k=1.0):
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = "MULTIPLY_ADD"
    nt.links.new(b, m.inputs[0]) if not isinstance(b, (int, float)) else None
    if isinstance(b, (int, float)):
        m.inputs[0].default_value = b
    m.inputs[1].default_value = k
    if isinstance(a, (int, float)):
        m.inputs[2].default_value = a
    else:
        nt.links.new(a, m.inputs[2])
    return m.outputs[0]


def attr(nt, name):
    a = n(nt, "ShaderNodeAttribute", _attribute_name=name)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(a.outputs["Color"], sep.inputs[0])
    return sep.outputs[0], sep.outputs[1], sep.outputs[2], a.outputs["Alpha"]


def voronoi(nt, scale, feature="F1", vec=None, out="Distance"):
    v = n(nt, "ShaderNodeTexVoronoi", Scale=scale, _feature=feature)
    nt.links.new(vec if vec is not None else position(nt), v.inputs["Vector"])
    return v.outputs[out]


def wave(nt, scale, direction="X", distortion=2.0, vec=None):
    w = n(nt, "ShaderNodeTexWave", Scale=scale, Distortion=distortion, _wave_type="BANDS", _bands_direction=direction)
    nt.links.new(vec if vec is not None else position(nt), w.inputs["Vector"])
    return w.outputs["Fac"]


def weave(nt, scale):
    """a woven cloth pattern (two sets of bands crossed)"""
    return mixf(nt, wave(nt, scale, "X", 1.0), wave(nt, scale, "Z", 1.0), 0.5)


def blood_layer(nt, c, amount, scale=5.0, fresh=(0.3, 0.02, 0.015), dried=(0.13, 0.025, 0.018), streak=True):
    """blood over colour c: soaked-in stains with a brown halo, runs, splatter. returns (colour, cover)"""
    splash = noise_tex(nt, scale, 6, 0.7)
    vec = position(nt, (scale * 1.6, scale * 1.6, scale * 0.25)) if streak else None
    runs = noise_tex(nt, 1.0, 4, 0.6, vec)
    pattern = maxf(nt, splash, runs)
    add = addf(nt, pattern, amount, 0.42)
    halo = fac_ramp(nt, add, 0.6, 0.84)
    cover = fac_ramp(nt, add, 0.8, 0.87)
    c = mix(nt, c, (0.36, 0.24, 0.18), mul(nt, halo, 0.22))
    col = mix(nt, dried, fresh, noise_tex(nt, scale * 2.5, 4, 0.6))
    c = mix(nt, c, col, mul(nt, cover, 0.93))
    dots = fac_ramp(nt, voronoi(nt, scale * 9), 0.14, 0.08)
    near = fac_ramp(nt, add, 0.7, 0.78)
    speck = mul(nt, dots, near)
    c = mix(nt, c, fresh, speck)
    return c, maxf(nt, cover, speck)


def material(name, build, bump=0.5, dist=0.004):
    """build(nt) -> dict(color=, height=, rough=); one material with the three outputs"""
    mat = bpy.data.materials.new(name)
    nt = mat.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.name = "Out"
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.name = "Emit"
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.name = "BSDF"
    res = build(nt)
    nt.links.new(res["color"], emit.inputs[0])
    if res.get("height") is not None:
        bn = n(nt, "ShaderNodeBump", Strength=bump, Distance=dist)
        nt.links.new(res["height"], bn.inputs["Height"])
        nt.links.new(bn.outputs["Normal"], bsdf.inputs["Normal"])
    r = res.get("rough", 0.7)
    if isinstance(r, (int, float)):
        bsdf.inputs["Roughness"].default_value = r
    else:
        nt.links.new(r, bsdf.inputs["Roughness"])
    nt.links.new(emit.outputs[0], out.inputs[0])
    return mat


def set_mode(mat, mode):
    nt = mat.node_tree
    out = nt.nodes["Out"]
    src = nt.nodes["Emit"] if mode == "color" else nt.nodes["BSDF"]
    nt.links.new(src.outputs[0], out.inputs[0])


# ---------------------------------------------------------------- the surfaces
def skin(nt):
    """grey-brown, sickly, blotched with rot and bruising, grimy; pores and creases"""
    mott = noise_tex(nt, 3.0, 6, 0.6)
    c = ramp(nt, mott, [(0.3, (0.42, 0.36, 0.31)), (0.5, (0.52, 0.45, 0.39)), (0.72, (0.58, 0.51, 0.44))])
    rot = fac_ramp(nt, noise_tex(nt, 2.2, 4, 0.6), 0.55, 0.72)
    c = mix(nt, c, (0.36, 0.37, 0.29), mul(nt, rot, 0.6))                       # grey-green rot
    c = mix(nt, c, (0.32, 0.22, 0.25), mul(nt, fac_ramp(nt, noise_tex(nt, 1.3, 3, 0.5), 0.6, 0.75), 0.6))
    vn = noise_tex(nt, 1.0, 3, 0.5, position(nt, (8, 8, 2.5)))
    band = nt.nodes.new("ShaderNodeMath")
    band.operation = "PINGPONG"
    nt.links.new(vn, band.inputs[0])
    band.inputs[1].default_value = 0.5
    c = mix(nt, c, (0.26, 0.25, 0.3), mul(nt, fac_ramp(nt, band.outputs[0], 0.47, 0.495), 0.5))
    c = mix(nt, c, (0.26, 0.22, 0.17), mul(nt, fac_ramp(nt, noise_tex(nt, 8, 4, 0.6), 0.55, 0.75), 0.6))
    pores = voronoi(nt, 110)
    height = addf(nt, mixf(nt, pores, noise_tex(nt, 30, 3, 0.6), 0.6), noise_tex(nt, 6, 3, 0.5), 0.5)
    return c, height


def cloth_base(nt, dark, light, grime=(0.4, 0.36, 0.28), weave_scale=50):
    g = noise_tex(nt, 3, 4, 0.5)
    c = ramp(nt, g, [(0.3, dark), (0.7, light)])
    wv = weave(nt, weave_scale)
    c = mix(nt, c, tuple(x * 0.85 for x in dark), mul(nt, wv, 0.15))
    c = mix(nt, c, grime, mul(nt, fac_ramp(nt, noise_tex(nt, 1.4, 3, 0.5), 0.42, 0.85), 0.5))
    height = addf(nt, mul(nt, wv, 0.5), noise_tex(nt, 9, 3, 0.5), 0.6)
    return c, height


def body_mat(nt):
    shirt, trousers, bl, bare = attr(nt, "mask")
    sk_c, sk_h = skin(nt)
    sh_c, sh_h = cloth_base(nt, (0.5, 0.48, 0.42), (0.6, 0.58, 0.51))
    # sweat and grime: yellow under the arms and round the collar
    sh_c = mix(nt, sh_c, (0.5, 0.43, 0.29), mul(nt, fac_ramp(nt, noise_tex(nt, 2.0, 3, 0.5), 0.5, 0.85), 0.4))
    tr_c, tr_h = cloth_base(nt, (0.15, 0.14, 0.12), (0.23, 0.21, 0.17), (0.28, 0.24, 0.18), 65)
    c = mix(nt, sk_c, sh_c, shirt)
    c = mix(nt, c, tr_c, trousers)
    h = mixf(nt, mixf(nt, sk_h, sh_h, shirt), tr_h, trousers)
    amount = maxf(nt, bl, mul(nt, noise_tex(nt, 0.9, 2, 0.5), 0.6))
    c, cover = blood_layer(nt, c, amount, 4.5)
    h = addf(nt, h, cover, 0.6)
    rough = mixf(nt, mixf(nt, 0.65, 0.88, shirt), 0.88, trousers)
    rough = mixf(nt, rough, 0.5, cover)
    return {"color": c, "height": h, "rough": rough}


def head_mat(nt):
    rot, bl, mouth, socket = attr(nt, "mask")
    stubble, raw, _, _ = attr(nt, "mask2")
    c, h = skin(nt)
    # rot: grey-green going to brown-black, wet and raw in the worst of it
    c = mix(nt, c, (0.3, 0.27, 0.2), mul(nt, rot, 0.7))
    c = mix(nt, c, (0.2, 0.08, 0.06), mul(nt, fac_ramp(nt, rot, 0.6, 0.95), 0.85))
    # stubble on the jowls and chin
    dots = fac_ramp(nt, voronoi(nt, 420), 0.32, 0.18)
    c = mix(nt, c, (0.11, 0.09, 0.08), mul(nt, dots, mul(nt, stubble, 0.85)))
    c = mix(nt, c, (0.3, 0.27, 0.25), mul(nt, stubble, 0.25))
    # sockets: black, the skin round them bruised dark
    c = mix(nt, c, (0.2, 0.13, 0.14), mul(nt, socket, 1.5))
    c = mix(nt, c, (0.02, 0.015, 0.015), fac_ramp(nt, socket, 0.5, 0.85))
    # the edge of the hole raw red, inside gums going black
    c = mix(nt, c, (0.32, 0.07, 0.06), raw)
    c = mix(nt, c, (0.22, 0.04, 0.04), mouth)
    c = mix(nt, c, (0.03, 0.01, 0.01), fac_ramp(nt, mouth, 0.75, 1.0))
    c, cover = blood_layer(nt, c, bl, 6.0)
    h = addf(nt, h, rot, 0.4)
    rough = mixf(nt, mixf(nt, mixf(nt, 0.64, 0.48, rot), 0.45, cover), 0.3, mouth)
    return {"color": c, "height": h, "rough": rough}


def teeth_mat(nt):
    g = noise_tex(nt, 40, 3, 0.6)
    c = ramp(nt, g, [(0.3, (0.45, 0.37, 0.22)), (0.65, (0.66, 0.58, 0.4))])
    c = mix(nt, c, (0.12, 0.08, 0.05), fac_ramp(nt, noise_tex(nt, 6, 2, 0.5), 0.64, 0.68))
    c, cover = blood_layer(nt, c, mul(nt, noise_tex(nt, 3, 2, 0.5), 0.9), 18.0, streak=False)
    return {"color": c, "height": noise_tex(nt, 60, 3, 0.6), "rough": mixf(nt, 0.35, 0.2, cover)}


def gums_mat(nt):
    c = ramp(nt, noise_tex(nt, 30, 4, 0.6), [(0.35, (0.18, 0.03, 0.04)), (0.65, (0.34, 0.08, 0.09))])
    return {"color": c, "height": noise_tex(nt, 50, 3, 0.6), "rough": 0.2}


def eye_mat_for(centre):
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
        # wet black, a bloodshot ring round it, a dull grey film in the middle
        c = mix(nt, (0.3, 0.06, 0.05), (0.015, 0.012, 0.012), fac_ramp(nt, dot.outputs["Value"], 0.55, 0.7))
        c = mix(nt, c, (0.07, 0.07, 0.07), fac_ramp(nt, dot.outputs["Value"], 0.93, 0.97))
        return {"color": c, "height": None, "rough": 0.06}
    return build


def hair_mat(direction):
    def build(nt):
        vec = position(nt, direction)
        streak = noise_tex(nt, 1.0, 3, 0.5, vec)
        c = ramp(nt, streak, [(0.3, (0.03, 0.025, 0.02)), (0.55, (0.07, 0.055, 0.04)), (0.75, (0.12, 0.1, 0.08))])
        c = mix(nt, c, (0.16, 0.14, 0.1), mul(nt, fac_ramp(nt, noise_tex(nt, 3, 3, 0.5), 0.6, 0.75), 0.5))   # grey in it
        c, cover = blood_layer(nt, c, mul(nt, noise_tex(nt, 1.5, 2, 0.5), 0.6), 6.0)
        return {"color": c, "height": noise_tex(nt, 1.0, 4, 0.6, position(nt, tuple(x * 2 for x in direction))),
                "rough": 0.55}
    return build


def apron_mat(nt):
    grime, bl, hands, _ = attr(nt, "mask")
    c, h = cloth_base(nt, (0.52, 0.5, 0.43), (0.64, 0.61, 0.54), (0.42, 0.37, 0.28), 38)
    c = mix(nt, c, (0.3, 0.25, 0.18), mul(nt, grime, 0.75))
    amount = maxf(nt, bl, addf(nt, 0.25, noise_tex(nt, 0.7, 2, 0.5), 0.55))
    c, cover = blood_layer(nt, c, amount, 3.4)
    # bloody handprints, wiped down it
    c = mix(nt, c, (0.2, 0.02, 0.015), mul(nt, hands, 0.95))
    cover = maxf(nt, cover, hands)
    h = addf(nt, h, cover, 0.7)
    return {"color": c, "height": h, "rough": mixf(nt, 0.86, 0.52, cover)}


def strap_mat(nt):
    c, h = cloth_base(nt, (0.45, 0.43, 0.37), (0.56, 0.53, 0.46), (0.36, 0.3, 0.22), 60)
    c, cover = blood_layer(nt, c, mul(nt, noise_tex(nt, 1.2, 2, 0.5), 0.8), 5.0)
    return {"color": c, "height": addf(nt, h, cover, 0.5), "rough": mixf(nt, 0.82, 0.52, cover)}


def iron_mat(nt):
    c = ramp(nt, noise_tex(nt, 20, 4, 0.6), [(0.35, (0.24, 0.23, 0.22)), (0.65, (0.42, 0.41, 0.4))])
    rust = fac_ramp(nt, noise_tex(nt, 9, 5, 0.65), 0.55, 0.68)
    c = mix(nt, c, (0.36, 0.2, 0.1), rust)
    return {"color": c, "height": addf(nt, rust, noise_tex(nt, 60, 3, 0.5), 0.3), "rough": mixf(nt, 0.45, 0.85, rust)}


def leather_mat(mud=True):
    def build(nt):
        c = ramp(nt, noise_tex(nt, 12, 5, 0.6), [(0.3, (0.08, 0.055, 0.04)), (0.7, (0.17, 0.11, 0.075))])
        scuff = fac_ramp(nt, noise_tex(nt, 26, 3, 0.6), 0.66, 0.74)
        c = mix(nt, c, (0.3, 0.23, 0.17), scuff)
        grain = voronoi(nt, 160, "F1")
        h = addf(nt, grain, noise_tex(nt, 10, 3, 0.5), 0.6)
        if mud:
            geo = nt.nodes.new("ShaderNodeNewGeometry")
            sep = nt.nodes.new("ShaderNodeSeparateXYZ")
            nt.links.new(geo.outputs["Position"], sep.inputs[0])
            sole = fac_ramp(nt, sep.outputs["Z"], 0.06, 0.04)
            c = mix(nt, c, (0.045, 0.04, 0.035), sole)
            mudm = mul(nt, fac_ramp(nt, sep.outputs["Z"], 0.3, 0.05), fac_ramp(nt, noise_tex(nt, 6, 4, 0.6), 0.4, 0.6))
            c = mix(nt, c, (0.24, 0.19, 0.13), mudm)
        c, cover = blood_layer(nt, c, mul(nt, noise_tex(nt, 2, 2, 0.5), 0.75), 8.0, streak=False)
        return {"color": c, "height": addf(nt, h, cover, 0.4), "rough": mixf(nt, mixf(nt, 0.55, 0.78, scuff), 0.48, cover)}
    return build


def cleaver_mat(nt):
    edge, wood, metal, _ = attr(nt, "mask")
    c = ramp(nt, noise_tex(nt, 18, 4, 0.5), [(0.35, (0.36, 0.36, 0.37)), (0.65, (0.6, 0.6, 0.62))])
    brushed = noise_tex(nt, 1.0, 2, 0.4, position(nt, (3, 3, 70)))
    c = mix(nt, c, (0.7, 0.7, 0.72), mul(nt, fac_ramp(nt, brushed, 0.6, 0.75), 0.45))
    rust = fac_ramp(nt, noise_tex(nt, 7, 6, 0.65), 0.58, 0.68)
    c = mix(nt, c, (0.38, 0.2, 0.09), rust)
    pits = fac_ramp(nt, voronoi(nt, 90), 0.06, 0.02)
    # the handle: dark, greasy wood
    wc = ramp(nt, noise_tex(nt, 1.0, 3, 0.5, position(nt, (40, 40, 4))), [(0.3, (0.12, 0.06, 0.03)), (0.7, (0.26, 0.15, 0.08))])
    c = mix(nt, c, wc, wood)
    c = mix(nt, c, (0.5, 0.38, 0.18), mul(nt, metal, 0.6))                   # brass rivets, steel bolster
    amount = maxf(nt, mul(nt, edge, 1.0), mul(nt, noise_tex(nt, 2.2, 3, 0.5), 0.7))
    c, cover = blood_layer(nt, c, amount, 7.0)
    h = addf(nt, addf(nt, rust, pits, -0.5), cover, 0.5)
    rough = mixf(nt, mixf(nt, mixf(nt, 0.32, 0.8, rust), 0.7, wood), 0.25, cover)
    return {"color": c, "height": h, "rough": rough}
