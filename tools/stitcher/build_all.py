# Builds THE STITCHER: body (with the ribs showing through its chest), head
# (the sewn grin, teeth, eyes, cap, hair, mask), clothes (gown, sleeves, ties,
# boots, bandages) and the scissors; rigs it (about 160 bones), skins every
# part, paints and bakes one texture per mesh, and exports a Roblox-ready FBX.
#
#   python3 build_all.py -- ./out
#
# writes out/TheStitcher.fbx, out/TheStitcher_<Part>.png (the four textures),
# out/TheStitcher.blend
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
import numpy as np
from mathutils import Vector as V, Matrix
from common import reset, link, apply_modifiers, select_only, decimate, tri_count, shade_smooth, join, seg_dist, smoothstep

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(os.path.dirname(__file__), "out")
OUT = os.path.abspath(OUT)
os.makedirs(OUT, exist_ok=True)
BAKE, TEX = 2048, 1024          # baked at 2048, saved at 1024 (Roblox's limit)

reset()
scene = bpy.context.scene
import skeleton as S, body, ribs, head, clothes, scissors, paint
from body import wound_e

# ------------------------------------------------------------------ the parts
P = {}
body_obj, plain = body.build()
plain.hide_render = True


def hidden_weight(p):
    """1 where the body is hidden under clothes (decimate it hard), 0 where it shows"""
    if p.z < 0.42:
        return 1.0                                         # in the boots
    if wound_e(p) < 1.5 or p.z > 6.7:
        return 0.0
    if abs(p.x) < 0.14 and p.y > 0.05 and 5.0 < p.z < 6.9:
        return 0.0                                         # the gap down its back
    for side in ("L", "R"):
        el, wr = S.J["Elbow." + side], S.J["Wrist." + side]
        d, t = seg_dist(p, el, wr + (wr - el).normalized() * 2)
        if d < 0.3 and (p - el).dot((wr - el).normalized()) > 0.2:
            return 0.0                                     # forearms and hands
    if p.z < 2.0:
        return 0.0                                         # shins below the hem
    return 1.0


for v in body_obj.data.vertices:
    p = v.co
    if 4.3 < p.z < 6.75 and hidden_weight(p) > 0 and wound_e(p) > 1.6:
        armpit = 0.0
        for side in ("L", "R"):
            d, t = seg_dist(p, S.J["Shoulder." + side], S.J["Elbow." + side])
            armpit = max(armpit, smoothstep(0.35, 0.15, d) * smoothstep(0.0, 0.2, t))
        v.co = p - v.normal * (0.03 + 0.03 * armpit) * smoothstep(4.3, 4.6, p.z)
g = body_obj.vertex_groups.new(name="hidden")
for v in body_obj.data.vertices:
    w = hidden_weight(v.co)
    if w > 0:
        g.add([v.index], w, "REPLACE")
m = body_obj.modifiers.new("Dec", "DECIMATE")
m.ratio = 0.45
m.vertex_group = "hidden"
m.vertex_group_factor = 1.0
apply_modifiers(body_obj)
decimate(body_obj, 13000)
body_obj.vertex_groups.remove(body_obj.vertex_groups["hidden"])
P["Body"] = body_obj
for o in ribs.build(plain):
    P[o.name] = o
P.update(head.build())
decimate(P["Cap"], 2200)
clothes.skirt_bones()
P["Gown"] = clothes.gown(body_obj)
P["Flap"] = clothes.flap(plain)
for o in clothes.sleeves():
    P[o.name] = o
ties, band = clothes.ties(plain)
P["WaistBand"] = band
for o in ties:
    P[o.name] = o
for o in clothes.shoes():
    P[o.name] = o
for o in clothes.bandages(plain):
    P[o.name] = o
for o in scissors.build():
    P[o.name] = o
bpy.data.objects.remove(plain)


def group_of(name):
    if name == "Body" or name.startswith(("Rib", "Splinter", "Bandage")):
        return "Body"
    if name.startswith("Scissors"):
        return "Scissors"
    if name in ("Head", "UpperTeeth", "LowerTeeth", "Stitches", "Eye.L", "Eye.R", "Cap", "Mask") or \
            name.startswith(("Hair", "CapTie")):
        return "Head"
    return "Clothes"


GROUPS = ("Body", "Head", "Clothes", "Scissors")
for k, o in P.items():
    print("%-16s %-8s %6d tris" % (k, group_of(k), tri_count(o)))

# ------------------------------------------------------------------ the rig
arm_data = bpy.data.armatures.new("StitcherRig")
arm = link(bpy.data.objects.new("StitcherRig", arm_data))
select_only(arm)
bpy.ops.object.mode_set(mode="EDIT")
seen = set()
for name, h, t, parent in S.BONES:
    assert name not in seen, name
    seen.add(name)
    eb = arm_data.edit_bones.new(name)
    eb.head, eb.tail = h, t
    if (t - h).length < 1e-4:
        eb.tail = h + V((0, 0, 0.05))
    if parent:
        eb.parent = arm_data.edit_bones[parent]
        eb.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
arm["scissor_n"] = list(S.SCISSORS["normal"])
SEG = {name: (h, t) for name, h, t, _ in S.BONES}
PARENT = {name: parent for name, _, _, parent in S.BONES}
print("BONES", len(S.BONES))


def side_of(bone):
    return 1 if bone.endswith(".L") or "L_" in bone[-4:] else (-1 if bone.endswith(".R") or "R_" in bone[-4:] else 0)


def finger_of(bone):
    for f in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        if bone.startswith(f):
            return f + bone[-2:]
    return None


def groups_for(obj):
    cache = {}

    def get(b):
        if b not in cache:
            cache[b] = obj.vertex_groups.get(b) or obj.vertex_groups.new(name=b)
        return cache[b]
    return get


def put(obj, get, vi, weights):
    total = sum(weights.values())
    if total <= 0:
        return
    for b, w in weights.items():
        if w / total > 0.01:
            get(b).add([vi], w / total, "REPLACE")


def distance_weights(p, bones, power=6, keep=3, sided=True, one_finger=True):
    ds = []
    for b in bones:
        s = side_of(b)
        if sided and s and p.x * s < -0.04:
            continue
        d, _ = seg_dist(p, *SEG[b])
        ds.append((d, b))
    ds.sort()
    if one_finger:
        best = None
        out = []
        for d, b in ds:
            f = finger_of(b)
            if f:
                if best is None:
                    best = f
                elif f != best:
                    continue
            out.append((d, b))
        ds = out
    ds = ds[:keep]
    return {b: 1.0 / (d ** power + 1e-7) for d, b in ds}


def weigh_distance(obj, bones, **kw):
    get = groups_for(obj)
    for v in obj.data.vertices:
        put(obj, get, v.index, distance_weights(obj.matrix_world @ v.co, bones, **kw))


def weigh_all(obj, bone):
    obj.vertex_groups.new(name=bone).add([v.index for v in obj.data.vertices], 1.0, "REPLACE")


def weigh_chain(obj, chain, parent, root_radius=0.05):
    bones = S.CHAINS[chain]
    root = SEG[bones[0]][0]
    get = groups_for(obj)
    for v in obj.data.vertices:
        p = obj.matrix_world @ v.co
        w = distance_weights(p, bones, power=4, keep=2, sided=False, one_finger=False)
        total = sum(w.values())
        w = {b: x / total for b, x in w.items()}
        k = smoothstep(root_radius, 0.0, (p - root).length)
        if k > 0:
            w = {b: x * (1 - k) for b, x in w.items()}
            w[parent] = w.get(parent, 0) + k
        put(obj, get, v.index, w)


BODY_BONES = [b for b, *_ in S.BONES if b in ("Root",) or b.startswith((
    "Spine", "Neck", "Thigh", "Shin", "Foot", "Toe", "Clavicle", "UpperArm", "Forearm", "Hand", "Thumb", "Index",
    "Middle", "Ring", "Pinky"))]

# body: Blender's bone heat (with only the body's own bones deforming), then
# anything it missed by distance
for bone in arm_data.bones:
    bone.use_deform = bone.name in BODY_BONES
select_only(body_obj)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
body_obj.parent = None
for mo in list(body_obj.modifiers):
    body_obj.modifiers.remove(mo)
for bone in arm_data.bones:
    bone.use_deform = True
missing = [v for v in body_obj.data.vertices if sum(g.weight for g in v.groups) < 0.5]
print("bone heat left", len(missing), "of", len(body_obj.data.vertices), "vertices unweighted")
if len(missing) > len(body_obj.data.vertices) * 0.03:
    for gr in list(body_obj.vertex_groups):
        body_obj.vertex_groups.remove(gr)
    weigh_distance(body_obj, BODY_BONES)
else:
    get = groups_for(body_obj)
    for v in missing:
        for gg in list(v.groups):
            body_obj.vertex_groups[gg.group].remove([v.index])
        put(body_obj, get, v.index, distance_weights(v.co, BODY_BONES))

NECK = ["Spine5", "Neck1", "Neck2", "Neck3", "Neck4", "Head"]
ARM = lambda s: ["Clavicle." + s, "UpperArm1." + s, "UpperArm2." + s, "Forearm1." + s, "Forearm2." + s, "Hand." + s]
TORSO = ["Root", "Spine1", "Spine2", "Spine3", "Spine4", "Spine5", "Neck1", "Clavicle.L", "Clavicle.R"]

for k, o in P.items():
    if k == "Body":
        continue
    if "bone" in o.keys():
        weigh_all(o, o["bone"])
    elif "chain" in o.keys():
        chain = o["chain"]
        parent = PARENT[S.CHAINS[chain][0]]
        weigh_chain(o, chain, parent, root_radius=0.04 if k.startswith("Hair") else 0.06)
    elif k in ("Head", "Stitches"):
        get = groups_for(o)
        inv = S.HEAD_M.inverted()
        for v in o.data.vertices:
            w = head.face_weights(inv @ v.co)
            nk = w.pop("Neck4", 0)
            if nk > 0:
                # the throat matches the body's neck under it
                dw = distance_weights(v.co, NECK[1:5], power=6, keep=2, sided=False, one_finger=False)
                t = sum(dw.values())
                for b, x in dw.items():
                    w[b] = w.get(b, 0) + nk * x / t
            put(o, get, v.index, w)
    elif k == "UpperTeeth":
        weigh_all(o, "Head")
    elif k == "LowerTeeth":
        weigh_all(o, "Jaw")
    elif k == "Cap":
        weigh_all(o, "Cap")
    elif k == "Mask":
        get = groups_for(o)
        top = S.head_xf(V((0, 0, 7.745))).z
        for v in o.data.vertices:
            p = v.co
            if p.z > top + 0.08 and abs(p.x) > 0.2:
                put(o, get, v.index, {"Head": 1})                # the ear loops
                continue
            hang = smoothstep(top - 0.05, top - 0.3, p.z)
            put(o, get, v.index, {"Jaw": 1 - hang * 0.75, "Mask": hang * 0.75})
    elif k == "Gown":
        get = groups_for(o)
        cols = clothes.SKIRT_COLS
        for v in o.data.vertices:
            p = v.co
            skirt = smoothstep(4.75, 4.25, p.z)
            w = {}
            if skirt < 1:
                for b, x in distance_weights(p, TORSO, power=4, keep=3).items():
                    w[b] = x
                t = sum(w.values())
                w = {b: x / t * (1 - skirt) for b, x in w.items()}
            if skirt > 0:
                a = math.degrees(math.atan2(p.x, -(p.y - 0.03)))
                # the two columns either side of this angle
                angs = [c[1] for c in cols]
                best = sorted(range(len(cols)), key=lambda i: abs((a - angs[i] + 180) % 360 - 180))[:2]
                da = [abs((a - angs[i] + 180) % 360 - 180) for i in best]
                fa = da[0] / max(da[0] + da[1], 1e-6)
                for ci, cw in ((best[0], 1 - fa), (best[1], fa)):
                    chain = S.CHAINS["Skirt%s_" % cols[ci][0]]
                    zs = clothes.SKIRT_Z
                    # which bone along the chain, blended over the joints
                    for bi in range(3):
                        z0, z1 = zs[bi], zs[bi + 1]
                        mid = (z0 + z1) / 2
                        span = (z0 - z1)
                        bw = max(0.0, 1 - abs(p.z - mid) / span)
                        if bi == 0 and p.z > mid:
                            bw = 1.0
                        if bi == 2 and p.z < mid:
                            bw = 1.0
                        if bw > 0:
                            w[chain[bi]] = w.get(chain[bi], 0) + cw * bw * skirt
            put(o, get, v.index, w)
    elif k.startswith("Sleeve"):
        weigh_distance(o, ARM(k[-1])[:5], power=5)
    elif k == "WaistBand" or k.startswith("Knot"):
        weigh_distance(o, ["Spine1", "Spine2", "Spine5", "Neck1"], power=4)
    elif k.startswith("Shoe"):
        s = k[-1]
        get = groups_for(o)
        for v in o.data.vertices:
            p = v.co
            toe = smoothstep(-0.3, -0.48, p.y)
            shin = smoothstep(0.42, 0.6, p.z)
            put(o, get, v.index, {"Toe." + s: toe * (1 - shin), "Foot." + s: (1 - toe) * (1 - shin), "Shin." + s: shin})
    elif k.startswith("Bandage."):
        weigh_distance(o, ["Forearm1." + k[-1], "Forearm2." + k[-1], "Hand." + k[-1]], power=5)
    else:
        raise RuntimeError("no skinning rule for " + k)

# ------------------------------------------------------------------ paint
paint.set_mask(P["Body"], paint.body_mask)
paint.set_mask(P["Head"], paint.head_mask)
paint.set_mask(P["Stitches"], paint.head_mask)
paint.set_mask(P["Gown"], paint.gown_mask)
IMG = {}
for gname in GROUPS:
    img = bpy.data.images.new("Stitcher" + gname, BAKE, BAKE, alpha=False)
    img.generated_color = (0.3, 0.3, 0.3, 1)
    IMG[gname] = img
GOWN = ((0.38, 0.43, 0.38), (0.5, 0.54, 0.47))


def shader_for(k):
    if k == "Body":
        return paint.body_shader
    if k.startswith(("Rib", "Splinter")):
        return paint.bone_shader
    if k.startswith("Bandage"):
        return paint.bandage_shader
    if k == "Head":
        return paint.head_shader
    if k in ("UpperTeeth", "LowerTeeth"):
        return paint.teeth_shader
    if k.startswith("Eye."):
        return paint.eye_shader_for(tuple(S.head_xf(S.EYE[k[-1]])))
    if k == "Stitches":
        return paint.flat((0.035, 0.028, 0.025))
    if k.startswith("Hair"):
        return paint.hair_shader
    if k == "Cap" or k.startswith("CapTie"):
        return paint.cloth_shader((0.46, 0.49, 0.45), (0.56, 0.59, 0.53), soak=0.1, blood_scale=6)
    if k == "Mask":
        return paint.cloth_shader((0.55, 0.61, 0.63), (0.64, 0.69, 0.7), soak=0.45, blood_scale=9)
    if k == "Gown":
        return paint.cloth_shader(*GOWN, masked=True)
    if k in ("Flap", "WaistBand") or k.startswith(("Sleeve", "Tie", "Knot")):
        return paint.cloth_shader(*GOWN, soak=0.15)
    if k.startswith("Shoe"):
        return paint.leather_shader
    if k == "ScissorsFixed" or k == "ScissorsBlade":
        return paint.steel_shader(1.25)
    raise RuntimeError(k)


for k, o in P.items():
    o.data.materials.clear()
    o.data.materials.append(paint.node_mat("M_" + k, shader_for(k), IMG[group_of(k)]))

# ------------------------------------------------------------------ one mesh and one texture per group
MESHES = {}
for gname in GROUPS:
    objs = [o for k, o in P.items() if group_of(k) == gname]
    # (the body first, so its name and data survive the join)
    objs.sort(key=lambda o: 0 if o.name in ("Body", "Head", "Gown", "ScissorsFixed") else 1)
    me = join(objs, "Stitcher" + gname)
    MESHES[gname] = me
    print("%-18s %6d tris" % (me.name, tri_count(me)))
    select_only(me)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.render.bake.margin = 8
world = bpy.data.worlds.new("W")
scene.world = world
world.light_settings.distance = 0.5


def srgb_decode(x):
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def bake(me, gname):
    select_only(me)
    scene.cycles.samples = 1
    bpy.ops.object.bake(type="EMIT")
    img = IMG[gname]
    emit = np.array(img.pixels[:]).reshape(BAKE, BAKE, 4)
    ao_img = bpy.data.images.new("AO" + gname, BAKE, BAKE, alpha=False)
    for mat in me.data.materials:
        mat.node_tree.nodes.active.image = ao_img
    scene.cycles.samples = 40
    bpy.ops.object.bake(type="AO")
    ao = np.array(ao_img.pixels[:]).reshape(BAKE, BAKE, 4)
    rgb = srgb_decode(emit[..., :3]) * (0.6 + 0.4 * np.clip(ao[..., :3], 0, 1) ** 1.1)
    # down to Roblox's 1024 (a 2x2 box filter)
    small = rgb.reshape(TEX, 2, TEX, 2, 3).mean(axis=(1, 3))
    out = bpy.data.images.new("TheStitcher_" + gname, TEX, TEX, alpha=False)
    px = np.ones((TEX, TEX, 4))
    px[..., :3] = small
    out.pixels[:] = px.ravel()
    path = os.path.join(OUT, "TheStitcher_%s.png" % gname)
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    out.filepath = path
    return out


for gname, me in MESHES.items():
    tex = bake(me, gname)
    mat = bpy.data.materials.new("TheStitcher_" + gname)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.35 if gname == "Scissors" else 0.8
    bsdf.inputs["Metallic"].default_value = 0.6 if gname == "Scissors" else 0.0
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = tex
    nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    me.data.materials.clear()
    me.data.materials.append(mat)
    for attr in list(me.data.color_attributes):
        me.data.color_attributes.remove(attr)

# ------------------------------------------------------------------ at most 4 bones per vertex, then skin it
for gname, me in MESHES.items():
    names = {gg.index: gg.name for gg in me.vertex_groups}
    for v in me.data.vertices:
        gs = sorted(((gg.weight, gg.group) for gg in v.groups), reverse=True)
        keep = gs[:4]
        total = sum(w for w, _ in keep) or 1
        for w, gi in gs[4:]:
            me.vertex_groups[names[gi]].remove([v.index])
        for w, gi in keep:
            me.vertex_groups[names[gi]].add([v.index], w / total, "REPLACE")
    unweighted = sum(1 for v in me.data.vertices if not v.groups)
    print("%-18s unweighted vertices: %d" % (me.name, unweighted))
    me.parent = arm
    mod = me.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

# ------------------------------------------------------------------ export
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "TheStitcher.blend"))
select_only(arm)
for me in MESHES.values():
    me.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "TheStitcher.fbx"), use_selection=True, object_types={"ARMATURE", "MESH"},
    apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", global_scale=1.0,
    axis_forward="-Z", axis_up="Y", add_leaf_bones=False, use_armature_deform_only=False,
    bake_anim=False, path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE",
)
print("TOTAL tris", sum(tri_count(me) for me in MESHES.values()), "bones", len(S.BONES))
print("exported", OUT)
