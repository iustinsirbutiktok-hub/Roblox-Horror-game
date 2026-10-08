# Builds THE MEDIC: body, skull, jaw, eyes, mask, gown, IV lines; rigs it
# (60 bones, every finger), skins it, paints and bakes one texture, exports FBX.
import sys, os, math, random
sys.path.insert(0, os.path.dirname(__file__))
import bpy, bmesh
import numpy as np
from mathutils import Vector as V
from common import reset, link, apply_modifiers, select_only, decimate, tri_count, shade_smooth
import skeleton as S

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)
TEX = 2048

reset()
scene = bpy.context.scene
import body, head, clothes

parts = {}
parts["Body"] = body.build()
decimate(parts["Body"], 9800)
parts.update(head.build())
parts["Gown"] = clothes.gown(parts["Body"])
parts["IV"] = clothes.iv_lines()
for k, o in parts.items():
    print("%-11s %6d tris" % (k, tri_count(o)))

# ------------------------------------------------------------------ rig
arm_data = bpy.data.armatures.new("MedicRig")
arm = link(bpy.data.objects.new("MedicRig", arm_data))
select_only(arm)
bpy.ops.object.mode_set(mode="EDIT")
for name, h, t, parent in S.BONES:
    eb = arm_data.edit_bones.new(name)
    eb.head = S.J[h]
    eb.tail = S.J[t]
    if parent:
        eb.parent = arm_data.edit_bones[parent]
        eb.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
BONE_SEG = {name: (S.J[h], S.J[t]) for name, h, t, _ in S.BONES}


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def weigh_by_distance(obj, bones, power=6, keep=3, falloff=None):
    groups = {b: obj.vertex_groups.get(b) or obj.vertex_groups.new(name=b) for b in bones}
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        ds = sorted(((seg_dist(p, *BONE_SEG[b]), b) for b in bones))[:keep]
        ws = [(1.0 / (d ** power + 1e-7), b) for d, b in ds]
        total = sum(w for w, _ in ws)
        for w, b in ws:
            if w / total > 0.02:
                groups[b].add([v.index], w / total, "REPLACE")


def weigh_all(obj, bone):
    g = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    g.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")


# body: Blender's heat weighting, then anything it missed by distance
body_obj = parts["Body"]
select_only(body_obj)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
body_obj.parent = None
for m in list(body_obj.modifiers):
    body_obj.modifiers.remove(m)
deform = [b for b, *_ in S.BONES]
missing = [v.index for v in body_obj.data.vertices if sum(g.weight for g in v.groups) < 0.5]
print("heat weighting left", len(missing), "vertices unweighted")
if len(missing) > len(body_obj.data.vertices) * 0.02:
    for g in list(body_obj.vertex_groups):
        body_obj.vertex_groups.remove(g)
    weigh_by_distance(body_obj, deform)
elif missing:
    tmp = set(missing)
    groups = {b: body_obj.vertex_groups.get(b) or body_obj.vertex_groups.new(name=b) for b in deform}
    for v in body_obj.data.vertices:
        if v.index in tmp:
            p = v.co
            ds = sorted(((seg_dist(p, *BONE_SEG[b]), b) for b in deform))[:3]
            ws = [(1.0 / (d ** 6 + 1e-7), b) for d, b in ds]
            total = sum(w for w, _ in ws)
            for w, b in ws:
                groups[b].add([v.index], w / total, "REPLACE")

for k in ("Skull", "UpperTeeth", "Eyes"):
    weigh_all(parts[k], "Head")
for k in ("Jaw", "LowerTeeth"):
    weigh_all(parts[k], "Jaw")
# the mask hangs off the throat; its one good ear loop goes up to the jaw
mask = parts["Mask"]
gj, g3, g2 = (mask.vertex_groups.new(name=n) for n in ("Jaw", "Neck3", "Neck2"))
for v in mask.data.vertices:
    if v.co.z > 6.95:
        gj.add([v.index], 1.0, "REPLACE")
    else:
        g3.add([v.index], 0.5, "REPLACE")
        g2.add([v.index], 0.5, "REPLACE")
weigh_by_distance(parts["Gown"], ["Root", "Spine1", "Spine2", "Spine3", "Spine4", "Spine5", "Neck1",
                                  "Thigh.L", "Thigh.R", "Clavicle.L", "Clavicle.R", "UpperArm.L", "UpperArm.R"],
                  power=4, keep=3)
iv = parts["IV"]
gl, gr = iv.vertex_groups.new(name="Forearm1.L"), iv.vertex_groups.new(name="Forearm2.R")
for v in iv.data.vertices:
    (gl if v.co.x > 0 else gr).add([v.index], 1.0, "REPLACE")

# ------------------------------------------------------------------ painting
# per-vertex masks the shader reads: R = rubber glove, G = blood, B = veins
J = S.J


def paint_body(obj):
    me = obj.data
    attr = me.color_attributes.new("mask", "FLOAT_COLOR", "POINT")
    rnd = random.Random(7)
    torn = {("Index", "L"), ("Middle", "L"), ("Thumb", "R"), ("Ring", "R")}
    for v in me.vertices:
        p = v.co
        glove = 0.0
        blood = 0.0
        for side in ("L", "R"):
            wr, e2 = J["Wrist." + side], J["Elbow2." + side]
            d = (wr - e2).normalized()
            along = (p - wr).dot(d)
            if along > -0.12 and (p - wr).length < 1.6:
                glove = max(glove, min(1.0, (along + 0.12) / 0.04))
                # bloodiest at the fingertips and palms
                blood = max(blood, min(1.0, max(0.0, along) / 1.0) * 0.9)
                # torn fingertips: bare grey skin pokes through
                for f, s2 in torn:
                    if s2 == side:
                        tip = J["%s2.%s" % (f, side)]
                        if (p - tip).length < 0.13:
                            glove = 0.0
        # dried blood run down from the mouth over the throat and chest
        if p.z > 5.2 and abs(p.x) < 0.25 and p.y < 0.0:
            blood = max(blood, max(0.0, (p.z - 5.2) / 1.6) * (1 - abs(p.x) / 0.25))
        veins = 0.55 + 0.45 * math.sin(p.z * 3.1 + p.x * 2.2)
        attr.data[v.index].color = (glove, blood, veins, 1.0)


paint_body(body_obj)

img = bpy.data.images.new("MedicAlbedo", TEX, TEX, alpha=False)
img.generated_color = (0.3, 0.3, 0.3, 1)


def node_mat(name, build):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs[0], out.inputs[0])
    color = build(nt)
    nt.links.new(color, emit.inputs[0])
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


def mix(nt, a, b, fac, blend="MIX"):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = blend
    if isinstance(fac, float):
        m.inputs[0].default_value = fac
    else:
        nt.links.new(fac, m.inputs[0])
    for i, x in ((6, a), (7, b)):
        if isinstance(x, tuple):
            m.inputs[i].default_value = (*x, 1)
        else:
            nt.links.new(x, m.inputs[i])
    return m.outputs[2]


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


def noise_tex(nt, scale, detail=4, rough=0.55, coord=None):
    t = n(nt, "ShaderNodeTexNoise", Scale=scale, Detail=detail, Roughness=rough)
    geo = coord or nt.nodes.new("ShaderNodeNewGeometry")
    nt.links.new(geo.outputs["Position"] if coord is None else coord.outputs[0], t.inputs["Vector"])
    return t


def skin_shader(nt):
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    attr = n(nt, "ShaderNodeAttribute", _attribute_name="mask")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(attr.outputs["Color"], sep.inputs[0])
    mott = noise_tex(nt, 3.5, 6, 0.6)
    base = ramp(nt, mott.outputs["Fac"], [(0.3, (0.24, 0.235, 0.23)), (0.5, (0.36, 0.35, 0.335)), (0.7, (0.43, 0.41, 0.39))])
    # bruises
    br = noise_tex(nt, 1.3, 3, 0.5)
    brm = ramp(nt, br.outputs["Fac"], [(0.58, (0, 0, 0)), (0.72, (1, 1, 1))])
    c = mix(nt, base, (0.26, 0.17, 0.22), n(nt, "ShaderNodeSeparateColor").outputs[0] if False else brm)
    # veins: dark branching lines
    vor = n(nt, "ShaderNodeTexVoronoi", Scale=9.0, _feature="DISTANCE_TO_EDGE")
    nt.links.new(geo.outputs["Position"], vor.inputs["Vector"])
    vm = ramp(nt, vor.outputs["Distance"], [(0.0, (1, 1, 1)), (0.035, (0, 0, 0))])
    vmask = mix(nt, (0, 0, 0), vm, sep.outputs[2])
    c = mix(nt, c, (0.17, 0.19, 0.27), vmask)
    # rubber gloves: dirty yellow-white latex
    gl = noise_tex(nt, 6, 3, 0.5)
    glove = ramp(nt, gl.outputs["Fac"], [(0.35, (0.62, 0.58, 0.45)), (0.65, (0.78, 0.74, 0.6))])
    c = mix(nt, c, glove, sep.outputs[0])
    # blood: splattered, dried dark at the edges
    bl = noise_tex(nt, 5.5, 5, 0.7)
    blm = ramp(nt, bl.outputs["Fac"], [(0.38, (0, 0, 0)), (0.52, (1, 1, 1))])
    bmask = mix(nt, (0, 0, 0), blm, sep.outputs[1])
    c = mix(nt, c, (0.23, 0.02, 0.015), bmask)
    return c


def bone_shader(nt, base=(0.74, 0.69, 0.58), dark=(0.42, 0.36, 0.27)):
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    g = noise_tex(nt, 7, 6, 0.6)
    c = ramp(nt, g.outputs["Fac"], [(0.3, dark), (0.6, base)])
    vor = n(nt, "ShaderNodeTexVoronoi", Scale=4.0, _feature="DISTANCE_TO_EDGE")
    nt.links.new(geo.outputs["Position"], vor.inputs["Vector"])
    crack = ramp(nt, vor.outputs["Distance"], [(0.0, (1, 1, 1)), (0.012, (0, 0, 0))])
    c = mix(nt, c, (0.2, 0.16, 0.12), crack)
    # deep inside the eye sockets and nose: black
    sk = head.SKULL_C
    for x in (0.115, -0.115):
        d = nt.nodes.new("ShaderNodeVectorMath")
        d.operation = "DISTANCE"
        nt.links.new(geo.outputs["Position"], d.inputs[0])
        d.inputs[1].default_value = (sk.x + x, sk.y - 0.3, sk.z - 0.06)
        dm = ramp(nt, d.outputs["Value"], [(0.07, (1, 1, 1)), (0.12, (0, 0, 0))])
        c = mix(nt, c, (0.015, 0.012, 0.01), dm)
    d = nt.nodes.new("ShaderNodeVectorMath")
    d.operation = "DISTANCE"
    nt.links.new(geo.outputs["Position"], d.inputs[0])
    d.inputs[1].default_value = (sk.x, sk.y - 0.32, sk.z - 0.25)
    dm = ramp(nt, d.outputs["Value"], [(0.03, (1, 1, 1)), (0.07, (0, 0, 0))])
    c = mix(nt, c, (0.02, 0.015, 0.012), dm)
    return c


def teeth_shader(nt):
    g = noise_tex(nt, 25, 3, 0.6)
    c = ramp(nt, g.outputs["Fac"], [(0.3, (0.45, 0.38, 0.22)), (0.65, (0.72, 0.64, 0.45))])
    # rotten brown at the gums
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    return c


def eye_shader(nt):
    return mix(nt, (0.8, 0.82, 0.76), (0.8, 0.82, 0.76), 0.0)


def cloth_shader(base, light, stain=(0.33, 0.27, 0.15), blood=(0.24, 0.025, 0.02), print_=True):
    def build(nt):
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        g = noise_tex(nt, 4, 5, 0.55)
        c = ramp(nt, g.outputs["Fac"], [(0.35, base), (0.65, light)])
        if print_:
            # the faded little diamond print of a hospital gown
            ch = n(nt, "ShaderNodeTexChecker", Scale=60.0)
            nt.links.new(geo.outputs["Position"], ch.inputs["Vector"])
            pm = ramp(nt, ch.outputs["Fac"], [(0.4, (0, 0, 0)), (0.6, (0.12, 0.12, 0.12))])
            c = mix(nt, c, (0.33, 0.42, 0.5), pm)
        # yellow grime and old stains
        s = noise_tex(nt, 1.8, 4, 0.6)
        sm = ramp(nt, s.outputs["Fac"], [(0.55, (0, 0, 0)), (0.7, (0.75, 0.75, 0.75))])
        c = mix(nt, c, stain, sm)
        # blood: dripped and smeared, heaviest at the hem and over the chest
        b = noise_tex(nt, 3.2, 6, 0.7)
        bm_ = ramp(nt, b.outputs["Fac"], [(0.56, (0, 0, 0)), (0.66, (1, 1, 1))])
        c = mix(nt, c, blood, bm_)
        return c
    return build


def iv_shader(nt):
    g = noise_tex(nt, 12, 3, 0.5)
    c = ramp(nt, g.outputs["Fac"], [(0.4, (0.66, 0.66, 0.62)), (0.6, (0.82, 0.82, 0.78))])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    # blood backed up the lines near the arm
    zr = ramp(nt, sep.outputs["Z"], [(2.6, (0, 0, 0)), (3.4, (1, 1, 1))])
    return mix(nt, c, (0.3, 0.03, 0.025), zr)


MATS = {
    "Body": node_mat("Skin", skin_shader),
    "Skull": node_mat("Bone", bone_shader),
    "Jaw": node_mat("JawBone", lambda nt: bone_shader(nt)),
    "UpperTeeth": node_mat("Teeth", teeth_shader),
    "LowerTeeth": node_mat("Teeth2", teeth_shader),
    "Eyes": node_mat("Eyes", eye_shader),
    "Mask": node_mat("MaskCloth", cloth_shader((0.42, 0.56, 0.58), (0.55, 0.68, 0.7), print_=False)),
    "Gown": node_mat("GownCloth", cloth_shader((0.4, 0.49, 0.52), (0.55, 0.62, 0.62))),
    "IV": node_mat("IVPlastic", iv_shader),
}
for k, o in parts.items():
    o.data.materials.clear()
    o.data.materials.append(MATS[k])

# ------------------------------------------------------------------ one mesh, one texture
objs = list(parts.values())
select_only(objs[0])
for o in objs[1:]:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts["Body"]
bpy.ops.object.join()
medic = bpy.context.view_layer.objects.active
medic.name = "TheMedic"
print("TOTAL tris", tri_count(medic))

select_only(medic)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 1
scene.render.bake.margin = 6
bpy.ops.object.bake(type="EMIT")
emit = np.array(img.pixels[:]).reshape(TEX, TEX, 4)

# ambient occlusion, to sink the ribs, sockets and folds into shadow
ao_img = bpy.data.images.new("MedicAO", TEX, TEX, alpha=False)
for mat in medic.data.materials:
    mat.node_tree.nodes.active.image = ao_img
scene.cycles.samples = 48
scene.world = scene.world or bpy.data.worlds.new("W")
scene.world.light_settings.distance = 0.6
bpy.ops.object.bake(type="AO")
ao = np.array(ao_img.pixels[:]).reshape(TEX, TEX, 4)
final = emit.copy()
# (the colours above were picked as screen colours: decode them so they come out as picked)
rgb = emit[..., :3]
rgb = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
final[..., :3] = rgb * (0.45 + 0.55 * np.clip(ao[..., :3], 0, 1) ** 1.2)
img.pixels[:] = final.ravel()
tex_path = os.path.join(OUT, "TheMedic_texture.png")
img.filepath_raw = tex_path
img.file_format = "PNG"
img.save()

# the real material: just the baked picture
final_mat = bpy.data.materials.new("TheMedic")
final_mat.use_nodes = True
nt = final_mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.75
tn = nt.nodes.new("ShaderNodeTexImage")
tn.image = img
nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
medic.data.materials.clear()
medic.data.materials.append(final_mat)

# ------------------------------------------------------------------ at most 4 bones per vertex
names = {g.index: g.name for g in medic.vertex_groups}
for v in medic.data.vertices:
    gs = sorted(((g.weight, g.group) for g in v.groups), reverse=True)
    keep = gs[:4]
    total = sum(w for w, _ in keep) or 1
    for w, gi in gs[4:]:
        medic.vertex_groups[names[gi]].remove([v.index])
    for w, gi in keep:
        medic.vertex_groups[names[gi]].add([v.index], w / total, "REPLACE")

medic.parent = arm
mod = medic.modifiers.new("Armature", "ARMATURE")
mod.object = arm

# ------------------------------------------------------------------ export
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0          # (Roblox: 1 Blender unit = 1 stud with FBX Unit Scale)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "TheMedic.blend"))
select_only(arm)
medic.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "TheMedic.fbx"), use_selection=True, object_types={"ARMATURE", "MESH"},
    apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", global_scale=1.0,
    axis_forward="-Z", axis_up="Y", add_leaf_bones=False, use_armature_deform_only=True,
    bake_anim=False, path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE",
)
print("exported", OUT)
