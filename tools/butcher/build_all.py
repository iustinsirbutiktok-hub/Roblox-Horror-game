# Builds THE BUTCHER: body (shirt and trousers painted on, with collar, rolled
# cuffs, belt, buttons), head (rotting face, teeth, gums, black eyes), greasy
# hair, the long apron with its straps and ties, work boots and the cleaver.
# Rigs it (about 200 bones), skins the game-resolution parts, bakes colour,
# normal and roughness maps from the high-resolution parts onto six meshes,
# and exports a Roblox-ready FBX. No animation: the rig is for you to pose.
#
#   python3 build_all.py -- ./out
#
# writes out/TheButcher.fbx, out/TheButcher_<Mesh>_{Color,Normal,Roughness}.png,
# out/TheButcher.blend
import sys, os, math, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
import numpy as np
from mathutils import Vector as V, Matrix
from common import reset, link, apply_modifiers, select_only, decimate, tri_count, join, bvh, seg_dist, smoothstep

OUT = os.path.abspath(sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(os.path.dirname(__file__), "out"))
os.makedirs(OUT, exist_ok=True)
BAKE, TEX = 2048, 1024          # baked at 2048, saved at 1024 (Roblox's limit)
T0 = time.time()


def log(*a):
    print("[%5.0fs]" % (time.time() - T0), *a, flush=True)


reset()
scene = bpy.context.scene
import skeleton as S, body, head, clothes, cleaver, paint, shaders as Sh
import vec as N

# ------------------------------------------------------------------ the high-resolution parts
H = {}
H["Body"] = body.build()
tree = bvh(H["Body"])
drape = body.drape_proxy()
dtree = bvh(drape)
hp, hair = head.build()
H.update(hp)
H.update(hair)
H["Apron"], _ = clothes.apron(dtree)
for o in clothes.straps(tree) + clothes.ties(dtree) + clothes.collar(tree) + clothes.cuffs(tree):
    H[o.name] = o
H["Belt"] = clothes.belt(dtree)
H["Buttons"] = clothes.buttons(tree)
for o in clothes.boots():
    H[o.name] = o
H["Cleaver"] = cleaver.build()
bpy.data.objects.remove(drape)
log("high-res parts:", len(H), "bones:", len(S.BONES))


def group_of(k):
    if k in ("Body", "Collar", "Belt", "Buttons") or k.startswith("Cuff."):
        return "Body"
    if k in ("Head", "UpperTeeth", "LowerTeeth", "Gums", "Eye.L", "Eye.R"):
        return "Head"
    if k.startswith(("Hair", "Scalp")):
        return "Hair"
    if k.startswith("Boot"):
        return "Boots"
    if k == "Cleaver":
        return "Cleaver"
    return "Apron"


GROUPS = ("Body", "Head", "Hair", "Apron", "Boots", "Cleaver")
BUDGET = {"Body": 15500, "Head": 8600, "Scalp": 2600, "Apron": 10500, "Boot.L": 2300, "Boot.R": 2300,
          "Cuff.L": 700, "Cuff.R": 700}
for k, o in H.items():
    log("  %-14s %-7s %7d tris" % (k, group_of(k), tri_count(o)))

# ------------------------------------------------------------------ the game-resolution parts
L = {}
for k, o in H.items():
    lo = o.copy()
    lo.data = o.data.copy()
    lo.name = k + "_lo"
    link(lo)
    if k in BUDGET:
        decimate(lo, BUDGET[k])
    for key in o.keys():
        lo[key] = o[key]
    L[k] = lo

# ------------------------------------------------------------------ the rig
arm_data = bpy.data.armatures.new("ButcherRig")
arm = link(bpy.data.objects.new("ButcherRig", arm_data))
select_only(arm)
bpy.ops.object.mode_set(mode="EDIT")
seen = set()
for name, hd, tl, parent in S.BONES:
    assert name not in seen, name
    seen.add(name)
    eb = arm_data.edit_bones.new(name)
    eb.head, eb.tail = hd, tl
    if (tl - hd).length < 1e-4:
        eb.tail = hd + V((0, 0, 0.05))
    if parent:
        eb.parent = arm_data.edit_bones[parent]
        eb.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
SEG = {name: (np.array(hd), np.array(tl)) for name, hd, tl, _ in S.BONES}
PARENT = {name: parent for name, _, _, parent in S.BONES}
log("rig:", len(S.BONES), "bones")


# ------------------------------------------------------------------ skinning helpers
def side_of(bone):
    if bone.endswith(".L") or bone.startswith(("StrapL", "TieL")):
        return 1
    if bone.endswith(".R") or bone.startswith(("StrapR", "TieR")):
        return -1
    return 0


def finger_of(bone):
    for f in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        if bone.startswith(f):
            return f + bone[-2:]
    return None


def set_weights(obj, names, W):
    """W: (verts, bones) array of weights; normalised, tiny ones dropped"""
    W = np.where(W < 0.01, 0, W)
    W = W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    for j, b in enumerate(names):
        idx = np.nonzero(W[:, j] > 0)[0]
        if len(idx) == 0:
            continue
        g = obj.vertex_groups.get(b) or obj.vertex_groups.new(name=b)
        for i in idx:
            g.add([int(i)], float(W[i, j]), "REPLACE")


def distance_W(P, bones, power=6, keep=3, sided=True):
    D = np.stack([N.segdist(P, *SEG[b])[0] for b in bones], axis=1)
    if sided:
        for j, b in enumerate(bones):
            s = side_of(b)
            if s:
                D[P[:, 0] * s < -0.05, j] = 1e3
    W = 1.0 / (D ** power + 1e-9)
    if keep < len(bones):
        cut = np.sort(W, axis=1)[:, -keep][:, None]
        W = np.where(W >= cut, W, 0)
    return W


def weigh_distance(obj, bones, **kw):
    set_weights(obj, bones, distance_W(N.get_co(obj.data), bones, **kw))


def weigh_all(obj, bone):
    obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")


def weigh_chain(obj, chain, parent, root_radius=0.06):
    bones = S.CHAINS[chain]
    P = N.get_co(obj.data)
    W = distance_W(P, bones, power=4, keep=2, sided=False)
    W = W / W.sum(axis=1, keepdims=True)
    k = N.sstep(root_radius, 0.0, np.linalg.norm(P - SEG[bones[0]][0], axis=1))
    W = np.concatenate([W * (1 - k)[:, None], k[:, None]], axis=1)
    set_weights(obj, bones + [parent], W)


def take(obj, bone, amount):
    """move a share of each vertex's weight onto a soft-tissue bone"""
    g = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    for v in obj.data.vertices:
        a = float(amount[v.index])
        if a <= 0.01:
            continue
        for gg in v.groups:
            gg.weight *= (1 - a)
        g.add([v.index], a, "ADD")


BODY_BONES = [b for b, *_ in S.BONES if b == "Root" or b.startswith((
    "Spine", "Neck1", "Neck2", "Neck3", "Thigh", "Shin", "Foot", "Toe", "Clavicle", "UpperArm", "Forearm", "Hand.",
    "Thumb", "IndexMeta", "MiddleMeta", "RingMeta", "PinkyMeta", "Index1", "Index2", "Index3", "Middle1", "Middle2",
    "Middle3", "Ring1", "Ring2", "Ring3", "Pinky1", "Pinky2", "Pinky3"))]

# ---- the body: bone heat (body bones only), then the soft tissue on top
lo = L["Body"]
for bone in arm_data.bones:
    bone.use_deform = bone.name in BODY_BONES
select_only(lo)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
lo.parent = None
for mo in list(lo.modifiers):
    lo.modifiers.remove(mo)
for bone in arm_data.bones:
    bone.use_deform = True
missing = [v.index for v in lo.data.vertices if sum(g.weight for g in v.groups) < 0.5]
log("bone heat left", len(missing), "of", len(lo.data.vertices), "body vertices unweighted")
if missing:
    P = N.get_co(lo.data)[missing]
    W = distance_W(P, BODY_BONES)
    W = W / W.sum(axis=1, keepdims=True)
    for row, vi in enumerate(missing):
        for gg in list(lo.data.vertices[vi].groups):
            lo.vertex_groups[gg.group].remove([vi])
        for j in np.nonzero(W[row] > 0.01)[0]:
            g = lo.vertex_groups.get(BODY_BONES[j]) or lo.vertex_groups.new(name=BODY_BONES[j])
            g.add([vi], float(W[row, j]), "REPLACE")
P = N.get_co(lo.data)


def blobw(c, r, k=0.85, p=1.5):
    return k * np.clip(1 - np.linalg.norm(P - np.array(c), axis=1) / r, 0, 1) ** p


take(lo, "Belly", blobw((0, -0.6, 4.85), 0.6))
take(lo, "BellyLow", blobw((0, -0.72, 4.45), 0.35))
for s, side in ((1, "L"), (-1, "R")):
    take(lo, "Pec." + side, blobw((s * 0.3, -0.5, 5.95), 0.3, 0.8))
    take(lo, "LoveHandle." + side, blobw((s * 0.68, 0.0, 4.65), 0.3, 0.75))
take(lo, "NeckFat", blobw((0, 0.32, 6.72), 0.26, 0.7))

# ---- everything else, by rule
NECKS = ["Neck2", "Neck3"]
inv_head = np.array(S.HEAD_M.inverted())
TORSO = ["Root", "Spine1", "Spine2", "Spine3", "Spine4", "Spine5", "Belly", "Pec.L", "Pec.R"]
for k, o in L.items():
    if k == "Body":
        continue
    if "bone" in o.keys():
        weigh_all(o, o["bone"])
    elif "chain" in o.keys():
        chain = o["chain"]
        weigh_chain(o, chain, PARENT[S.CHAINS[chain][0]], 0.05 if k.startswith("Hair") else 0.08)
    elif k == "Head":
        Pd = N.get_co(o.data) @ inv_head[:3, :3].T + inv_head[:3, 3]
        set_weights(o, head.FACE_BONES, head.face_weights(Pd))
    elif k in ("UpperTeeth", "Scalp", "HairTop"):
        weigh_all(o, "Head")
    elif k in ("LowerTeeth",):
        weigh_all(o, "Jaw")
    elif k == "Gums":
        Pd = N.get_co(o.data) @ inv_head[:3, :3].T + inv_head[:3, 3]
        jaw = (Pd[:, 2] < head.mouth_z(head.phi_of(Pd[:, 0], Pd[:, 1]))) * 1.0
        set_weights(o, ["Head", "Jaw"], np.stack([1 - jaw, jaw], axis=1))
    elif k == "Apron":
        Pa = N.get_co(o.data)
        x, y, z = Pa[:, 0], Pa[:, 1], Pa[:, 2]
        span = np.array([clothes.apron_span(zz) for zz in z])
        u = np.clip(np.arctan2(x, -(y - 0.03)) / span, -1, 1)
        names = TORSO + ["ApronBib_1", "ApronBib_2"] + [b for ci in range(clothes.APRON_COLS)
                                                          for b in S.CHAINS["Apron%d_" % (ci + 1)]]
        W = np.zeros((len(Pa), len(names)))
        top = N.sstep(clothes.WAIST - 0.3, clothes.WAIST + 0.05, z)          # 1 on the bib, 0 on the skirt
        Wt = distance_W(Pa, TORSO, power=4, keep=3)
        Wt = Wt / Wt.sum(axis=1, keepdims=True)
        bib = np.clip(1 - np.abs(u) / 0.7, 0, 1) * N.sstep(clothes.WAIST, 5.3, z) * 0.6
        Wb = distance_W(Pa, ["ApronBib_1", "ApronBib_2"], power=4, keep=2, sided=False)
        Wb = Wb / Wb.sum(axis=1, keepdims=True)
        W[:, :len(TORSO)] = Wt * (top * (1 - bib))[:, None]
        W[:, len(TORSO):len(TORSO) + 2] = Wb * (top * bib)[:, None]
        cf = (u + 1) / 2 * (clothes.APRON_COLS - 1)
        c0 = np.clip(np.floor(cf).astype(int), 0, clothes.APRON_COLS - 2)
        fc = cf - c0
        zs = clothes.APRON_Z
        base = len(TORSO) + 2
        for bi in range(4):
            z0, z1 = zs[bi], zs[bi + 1]
            mid = (z0 + z1) / 2
            bw = np.clip(1 - np.abs(z - mid) / (z0 - z1), 0, 1)
            if bi == 0:
                bw = np.where(z > mid, 1.0, bw)
            if bi == 3:
                bw = np.where(z < mid, 1.0, bw)
            for which, cw in ((c0, 1 - fc), (c0 + 1, fc)):
                col = base + which * 4 + bi
                np.add.at(W, (np.arange(len(Pa)), col), cw * bw * (1 - top))
        set_weights(o, names, W)
    elif k.startswith("Strap"):
        sd = k[-1]
        weigh_distance(o, ["Spine3", "Spine4", "Spine5", "Clavicle.L", "Clavicle.R", "Strap%s_1" % sd,
                           "Strap%s_2" % sd], power=5)
    elif k.startswith("Buckle"):
        sd = "L" if N.get_co(o.data)[:, 0].mean() > 0 else "R"
        weigh_all(o, "Strap%s_1" % sd)
    elif k == "WaistTie":
        weigh_distance(o, ["Root", "Spine1", "Spine2", "LoveHandle.L", "LoveHandle.R"], power=4)
    elif k.startswith(("Knot", "BowLoop")):
        weigh_all(o, "Bow")
    elif k == "Collar":
        weigh_distance(o, ["Spine5", "Neck1", "Collar.L", "Collar.R"], power=5)
    elif k == "Buttons":
        weigh_all(o, "Spine5")
    elif k.startswith("Boot."):
        sd = k[-1]
        Pb = N.get_co(o.data)
        toe = N.sstep(-0.32, -0.52, Pb[:, 1])
        shin = N.sstep(0.42, 0.62, Pb[:, 2])
        top = N.sstep(0.62, 0.8, Pb[:, 2])
        W = np.stack([toe * (1 - shin), (1 - toe) * (1 - shin), shin * (1 - top), top], axis=1)
        set_weights(o, ["Toe." + sd, "Foot." + sd, "Shin2." + sd, "BootTop." + sd], W)
    else:
        raise RuntimeError("no skinning rule for " + k)
log("skinned")

# ------------------------------------------------------------------ paint and materials (on the high-res parts)
paint.body(H["Body"])
paint.head(H["Head"])
paint.apron(H["Apron"])
paint.cleaver(H["Cleaver"])
MAT = {}


def mat_for(k):
    if k == "Body":
        return "body", Sh.body_mat
    if k in ("Collar",) or k.startswith("Cuff."):
        return "shirt", lambda nt: dict(zip(("color", "height"), Sh.cloth_base(nt, (0.5, 0.48, 0.42), (0.6, 0.58, 0.51)))) | {"rough": 0.85}
    if k == "Buttons":
        return "button", lambda nt: {"color": Sh.mix(nt, (0.55, 0.52, 0.44), (0.55, 0.52, 0.44), 0.0), "height": None, "rough": 0.4}
    if k == "Belt":
        return "belt", Sh.leather_mat(False)
    if k == "Head":
        return "head", Sh.head_mat
    if k in ("UpperTeeth", "LowerTeeth"):
        return "teeth", Sh.teeth_mat
    if k == "Gums":
        return "gums", Sh.gums_mat
    if k.startswith("Eye."):
        return "eye" + k[-1], Sh.eye_mat_for(tuple(S.head_xf(S.EYE[k[-1]])))
    if k in ("Scalp", "HairTop"):
        return "scalp", Sh.hair_mat((40, 4, 40))
    if k.startswith("Hair"):
        return "hair", Sh.hair_mat((40, 40, 3))
    if k == "Apron":
        return "apron", Sh.apron_mat
    if k.startswith(("Strap", "WaistTie", "Knot", "BowLoop", "TieEnd")):
        return "strap", Sh.strap_mat
    if k.startswith("Buckle"):
        return "iron", Sh.iron_mat
    if k.startswith("Boot"):
        return "boots", Sh.leather_mat(True)
    if k == "Cleaver":
        return "cleaver", Sh.cleaver_mat
    raise RuntimeError(k)


for k, o in H.items():
    key, fn = mat_for(k)
    if key not in MAT:
        MAT[key] = Sh.material("M_" + key, fn)
    o.data.materials.clear()
    o.data.materials.append(MAT[key])

# ------------------------------------------------------------------ one mesh per group, unwrapped
MESH = {}
for gname in GROUPS:
    objs = [L[k] for k in L if group_of(k) == gname]
    objs.sort(key=lambda o: 0 if o.name in ("Body_lo", "Head_lo", "Scalp_lo", "Apron_lo", "Boot.L_lo", "Cleaver_lo") else 1)
    for o in objs:
        o.data.materials.clear()
        for a in list(o.data.color_attributes):
            o.data.color_attributes.remove(a)
    me = join(objs, "Butcher" + gname)
    MESH[gname] = me
    select_only(me)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")
    log("%-16s %6d tris" % (me.name, tri_count(me)))

# ------------------------------------------------------------------ bake: high-res parts -> game meshes
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.render.bake.margin = 8
scene.world = bpy.data.worlds.new("W")
scene.world.light_settings.distance = 0.5
bake = scene.render.bake


def target(me, img):
    """the game mesh's one material: just an image node for the bake to write into"""
    mat = bpy.data.materials.new("Bake_" + me.name)
    nt = mat.node_tree
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = img
    nt.nodes.active = tn
    me.data.materials.clear()
    me.data.materials.append(mat)


def pixels(img):
    return np.array(img.pixels[:]).reshape(BAKE, BAKE, 4)


def small(a):
    return a.reshape(TEX, 2, TEX, 2, a.shape[-1]).mean(axis=(1, 3))


def save(name, rgb, colorspace="sRGB"):
    img = bpy.data.images.new(name, TEX, TEX, alpha=False)
    img.colorspace_settings.name = colorspace
    px = np.ones((TEX, TEX, 4))
    px[..., :3] = np.clip(rgb, 0, 1)
    img.pixels[:] = px.ravel()
    path = os.path.join(OUT, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.filepath = path
    return img


def srgb_decode(x):
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


FINAL = {}
for gname, me in MESH.items():
    highs = [H[k] for k in H if group_of(k) == gname]
    imgs = {p: bpy.data.images.new("%s_%s" % (gname, p), BAKE, BAKE, alpha=False, float_buffer=(p == "Normal"))
            for p in ("Color", "Normal", "Roughness", "AO")}
    imgs["Normal"].colorspace_settings.name = "Non-Color"
    imgs["Roughness"].colorspace_settings.name = "Non-Color"

    def sel_high():
        select_only(me)
        for h in highs:
            h.select_set(True)
        bpy.context.view_layer.objects.active = me

    bake.use_selected_to_active = True
    bake.cage_extrusion = 0.03
    bake.max_ray_distance = 0.08
    for pas, btype, mode in (("Color", "EMIT", "color"), ("Normal", "NORMAL", "bsdf"), ("Roughness", "ROUGHNESS", "bsdf")):
        target(me, imgs[pas])
        for m in set(h.data.materials[0] for h in highs):
            Sh.set_mode(m, mode)
        sel_high()
        scene.cycles.samples = 1
        if btype == "NORMAL":
            bake.normal_space = "TANGENT"
        bpy.ops.object.bake(type=btype)
        log("  baked", gname, pas)
    for m in set(h.data.materials[0] for h in highs):
        Sh.set_mode(m, "color")
    bake.use_selected_to_active = False
    target(me, imgs["AO"])
    select_only(me)
    scene.cycles.samples = 16
    # (only the game meshes cast it: the high-res parts sit right on top of them and
    # would shadow them in blotches)
    for h in H.values():
        h.hide_render = True
    bpy.ops.object.bake(type="AO")
    for h in H.values():
        h.hide_render = False
    log("  baked", gname, "AO")
    col = srgb_decode(pixels(imgs["Color"])[..., :3])
    ao = np.clip(pixels(imgs["AO"])[..., :3], 0, 1)
    col = col * (0.62 + 0.38 * ao ** 1.1)
    nrm = pixels(imgs["Normal"])[..., :3]
    rough = pixels(imgs["Roughness"])[..., :1].repeat(3, axis=2)
    out = {}
    out["Color"] = save("TheButcher_%s_Color" % gname, small(col))
    n2 = small(nrm) * 2 - 1
    n2 /= np.maximum(np.linalg.norm(n2, axis=2, keepdims=True), 1e-6)
    out["Normal"] = save("TheButcher_%s_Normal" % gname, n2 * 0.5 + 0.5, "Non-Color")
    out["Roughness"] = save("TheButcher_%s_Roughness" % gname, small(rough), "Non-Color")
    FINAL[gname] = out
    # the real material: the baked pictures
    mat = bpy.data.materials.new("TheButcher_" + gname)
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = out["Color"]
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tr = nt.nodes.new("ShaderNodeTexImage")
    tr.image = out["Roughness"]
    nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = out["Normal"]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = 0.5 if gname == "Cleaver" else 0.0
    me.data.materials.clear()
    me.data.materials.append(mat)
log("baked")

# ------------------------------------------------------------------ at most 4 bones per vertex; skin to the rig
for gname, me in MESH.items():
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
    log("%-16s %6d tris, unweighted vertices: %d" % (me.name, tri_count(me), unweighted))
    me.parent = arm
    mod = me.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

# the high-res parts are done with
for o in list(H.values()):
    bpy.data.objects.remove(o)

# ------------------------------------------------------------------ export
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "TheButcher.blend"))
select_only(arm)
for me in MESH.values():
    me.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "TheButcher.fbx"), use_selection=True, object_types={"ARMATURE", "MESH"},
    apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", global_scale=1.0,
    axis_forward="-Z", axis_up="Y", add_leaf_bones=False, use_armature_deform_only=False,
    bake_anim=False, path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE", use_tspace=True,
)
log("TOTAL tris", sum(tri_count(me) for me in MESH.values()), "bones", len(S.BONES))
log("exported", OUT)
