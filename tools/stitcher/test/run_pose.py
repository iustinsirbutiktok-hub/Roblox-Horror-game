# Runs the real StitcherPose.lua (in Lua 5.1, with roblox_mock.lua standing in
# for Roblox) on the real rig from out/TheStitcher.blend: fuzzes it for errors
# and bad numbers, then poses the model with its output and renders a sheet.
#
#   python3 test/run_pose.py -- ./out            (needs: pip install bpy lupa)
import sys, os, math, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import bpy
from mathutils import Vector as V, Matrix
from lupa import lua51

OUT = os.path.abspath(sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "out")
RENDER = "--norender" not in sys.argv
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, "TheStitcher.blend"))
arm = bpy.data.objects["StitcherRig"]

# Blender (x = its left, y = behind, z = up) -> Roblox model frame (X = its right, Y = up, Z = behind)
M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
root_head = arm.data.bones["Root"].head_local
origin = V((root_head.x, root_head.y, 0.0))


def to_roblox(p):
    return M @ (V(p) - origin)


order, seen = [], set()


def visit(b):
    if b.name in seen:
        return
    if b.parent:
        visit(b.parent)
    seen.add(b.name)
    order.append(b.name)


for b in arm.data.bones:
    visit(b)

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "roblox_mock.lua")).read())
src = open(os.path.join(REPO, "src", "ReplicatedStorage", "StitcherPose.lua")).read()
StitcherPose = lua.eval("function(src) local f, e = loadstring(src, 'StitcherPose'); assert(f, e); return f() end")(src)

make_rig = lua.eval("""
function(names, xs, ys, zs, parents)
    local rig = { pos = {}, parent = {}, order = {} }
    for i = 1, #names do
        local n = names[i]
        rig.pos[n] = Vector3.new(xs[i], ys[i], zs[i])
        if parents[i] ~= "" then rig.parent[n] = parents[i] end
        rig.order[i] = n
    end
    return rig
end""")
pos = {n: to_roblox(arm.data.bones[n].head_local) for n in order}
rig = make_rig(lua.table_from(order), lua.table_from([pos[n].x for n in order]), lua.table_from([pos[n].y for n in order]),
               lua.table_from([pos[n].z for n in order]),
               lua.table_from([(arm.data.bones[n].parent.name if arm.data.bones[n].parent else "") for n in order]))

run_frame = lua.eval("""
function(pose, dt, t, speed, tx, ty, tz, near, aggro, attack, fz)
    local target = nil
    if tx then target = Vector3.new(tx, ty, tz) end
    local out = pose:update({ dt = dt, t = t, speed = speed, target = target, near = near, aggro = aggro,
        attack = attack, frame = CFrame.new(0, 0, fz) })
    local res = {}
    for name, c in pairs(out) do
        assert(IsCFrame(c), name .. " is not a CFrame")
        local comps = { c:GetComponents() }
        for i = 1, 12 do
            local x = comps[i]
            assert(x == x and x > -1e6 and x < 1e6, name .. " has a bad number")
        end
        res[name] = comps
    end
    local ev = {}
    for i, e in ipairs(pose.events) do ev[i] = e end
    return res, ev
end""")


def simulate(seconds, inputs, seed=7.0, fps=60):
    pose = StitcherPose.new(rig, seed)
    t = 0.0
    z = 0.0
    res, events = None, []
    n = int(seconds * fps)
    for i in range(n):
        dt = 1.0 / fps
        inp = inputs(t)
        z -= inp.get("speed", 0) * dt
        tg = inp.get("target")
        res, ev = run_frame(pose, dt, t, inp.get("speed", 0), *(tg if tg else (None, None, None)), inp.get("near", 0),
                            inp.get("aggro", 0), inp.get("attack", 0), z)
        events += list(ev.values())
        t += dt
    return {k: list(v.values()) for k, v in res.items()}, events


# ------------------------------------------------------------------ fuzz: 30 seconds of everything
import random
rnd = random.Random(3)
plan = []
for k in range(30):
    plan.append(dict(speed=rnd.choice((0, 0, 2, 3, 6, 10)), near=rnd.random() if rnd.random() < 0.6 else 0,
                     target=(rnd.uniform(-8, 8), rnd.uniform(1, 9), rnd.uniform(-12, 6)) if rnd.random() < 0.7 else None,
                     aggro=rnd.choice((0, 0, 0.5, 1)), attack=k // 3))
res, events = simulate(30, lambda t: plan[min(int(t), 29)])
from collections import Counter
print("FUZZ ok: 30 s, %d bones posed in the last frame; events: %s" % (len(res), dict(Counter(events))))
missing = [b for b in order if b not in res]
print("bones never posed:", missing)

if not RENDER:
    sys.exit(0)

# ------------------------------------------------------------------ scenarios to look at
FRONT = (0, 5.5, -9)      # a player's head 9 studs in front
CLOSE = (-0.6, 5.5, -3.2)
scen = [
    ("idle", 4.0, lambda t: {}),
    ("sees you", 3.0, lambda t: {"target": FRONT, "near": 0.25}),
    ("close", 4.0, lambda t: {"target": CLOSE, "near": 1.0}),
    ("attack: rear up", 3.0 + 0.3, lambda t: {"target": CLOSE, "near": 1.0, "attack": 1 if t > 3.0 else 0}),
    ("attack: lunge", 3.0 + 0.5, lambda t: {"target": CLOSE, "near": 1.0, "attack": 1 if t > 3.0 else 0}),
    ("walk", 3.3, lambda t: {"speed": 3}),
    ("run", 3.15, lambda t: {"speed": 10, "target": FRONT, "near": 0.4}),
]


def apply(res):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    for name, c in res.items():
        pb = arm.pose.bones.get(name)
        if pb is None:
            continue
        x, y, z, *r = c
        Rr = Matrix((r[0:3], r[3:6], r[6:9]))
        Rb = M @ Rr @ M                     # (M is its own inverse)
        tb = M @ V((x, y, z))
        q = pb.bone.matrix_local.to_3x3()
        pb.rotation_quaternion = (q.inverted() @ Rb @ q).to_quaternion()
        pb.location = q.inverted() @ tb
    bpy.context.view_layer.update()


import preview
outs, faces = [], []
for name, secs, fn in scen:
    res, ev = simulate(secs, fn)
    apply(res)
    print("%-16s events: %s" % (name, ev))
    o = preview.render(os.path.join(OUT, "lua_%s.png" % name.replace(" ", "_").replace(":", "")),
                       [((-6.5, -10, 5.0), (0, 0, 4.4), 48)], size=(400, 640), engine="CYCLES", samples=24)
    outs += o
    if name in ("sees you", "close", "attack: rear up"):
        hb = arm.pose.bones["Head"]
        hp = arm.matrix_world @ (hb.head + (hb.tail - hb.head) * 0.35)
        faces += preview.render(os.path.join(OUT, "luaface_%s.png" % name.split(":")[0].replace(" ", "_")),
                                [(tuple(hp + V((-0.9, -2.3, 0.1))), tuple(hp), 50)], size=(400, 400), engine="CYCLES",
                                samples=32)
print("SHEET", preview.stitch(outs, os.path.join(OUT, "preview_lua_poses.png")))
print("SHEET", preview.stitch(faces, os.path.join(OUT, "preview_lua_faces.png")))
