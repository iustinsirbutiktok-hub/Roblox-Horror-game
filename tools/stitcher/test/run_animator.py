# Runs the real StitcherAnimator.client.lua (and StitcherPose.lua) on a mock of
# Roblox holding the built skeleton: checks it finds the rig, poses every frame
# with sane Transforms, reacts to a player, attacks, patrols, and lets go when
# Procedural is unticked. Then checks the Transform maths itself: a turn given
# in the model's frame, put through q^-1 * R * q, lands the child joints exactly
# where StitcherPose's own forward kinematics says.
#
#   python3 test/run_animator.py -- ./out          (needs: pip install bpy lupa)
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
import bpy
from mathutils import Vector as V, Matrix
from lupa import lua51

OUT = os.path.abspath(sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "out")
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, "TheStitcher.blend"))
arm = bpy.data.objects["StitcherRig"]
M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))          # Blender -> Roblox axes (its own inverse)

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "roblox_mock.lua")).read())
lua.execute(open(os.path.join(HERE, "roblox_world.lua")).read())
G = lua.globals()

# the imported model: a mesh part holding the bone tree, each bone placed at
# its Blender rest pose (turned into Roblox's axes, and turned round a bit so
# nothing depends on which way it faces)
build = lua.eval("""
function(names, parents, data, yaw)
    local model = NewInstance("Model", "TheStitcher", workspace)
    local part = NewInstance("MeshPart", "StitcherBody", model)
    local place = CFrame.new(10, 0, 20) * CFrame.Angles(0, yaw, 0)
    part.CFrame = place
    local made, world = {}, {}
    for i = 1, #names do
        local d = data[i]
        local w = place * CFrame.new(d[1], d[2], d[3]) * CFrame.fromMatrix(Vector3.new(0, 0, 0),
            Vector3.new(d[4], d[7], d[10]), Vector3.new(d[5], d[8], d[11]), Vector3.new(d[6], d[9], d[12]))
        local p = parents[i]
        local b = NewInstance("Bone", names[i], p ~= "" and made[p] or part)
        b.CFrame = (p ~= "" and world[p] or part.CFrame):Inverse() * w
        made[names[i]], world[names[i]] = b, w
    end
    model.box = place * CFrame.new(0, 4.4, 0)
    model.boxSize = Vector3.new(4, 8.8, 2)
    local snip = NewInstance("Sound", "Snip", part)
    return model, made
end""")
order, seen = [], set()


def visit(b):
    if b.name not in seen:
        if b.parent:
            visit(b.parent)
        seen.add(b.name)
        order.append(b.name)


for b in arm.data.bones:
    visit(b)
data = []
for n in order:
    bb = arm.data.bones[n]
    p = M @ bb.head_local
    r = M @ bb.matrix_local.to_3x3() @ M
    data.append(lua.table_from([p.x, p.y, p.z] + [r[i][j] for i in range(3) for j in range(3)]))
model, bones = build(lua.table_from(order), lua.table_from([arm.data.bones[n].parent.name if arm.data.bones[n].parent else ""
                                                             for n in order]), lua.table_from(data), 0.7)
pose_src = open(os.path.join(REPO, "src", "ReplicatedStorage", "StitcherPose.lua")).read()
anim_src = open(os.path.join(REPO, "src", "StarterPlayerScripts", "StitcherAnimator.client.lua")).read()
setup_src = open(os.path.join(REPO, "src", "ServerScriptService", "StitcherSetup.server.lua")).read()
lua.execute("""
local src = ...
""")
load = lua.eval("function(src, name) local f, e = loadstring(src, name); assert(f, e); return f end")
module_script = lua.eval("function() local m = NewInstance('ModuleScript', 'StitcherPose', game:GetService('ReplicatedStorage')); return m end")()
G.MODULES[module_script] = load(pose_src, "StitcherPose")()

load(setup_src, "StitcherSetup")()
lua.eval("RunQueue")()
assert model.attrs["Stitcher"] is True and model.attrs["Patrol"] is True, "setup didn't run"
model.attrs["Patrol"] = False
load(anim_src, "StitcherAnimator")()
lua.eval("RunQueue")()

check = lua.eval("""
function(bones)
    local bad, moved, n = 0, 0, 0
    for name, b in pairs(bones) do
        n = n + 1
        local c = { b.Transform:GetComponents() }
        for i = 1, 12 do
            if not (c[i] == c[i] and c[i] > -1e4 and c[i] < 1e4) then bad = bad + 1 end
        end
        local p = b.Transform.Position
        local r = c[4] + c[8] + c[12]
        if r < 2.9999 or p.Magnitude > 1e-6 then moved = moved + 1 end
    end
    return n, bad, moved
end""")
advance = lua.eval("Advance")
head = lua.eval("AddPlayer")(1, lua.table_from([10 + 0.0, 5.5, 20 - 9.0]))
for i in range(240):
    advance(1 / 60)
n, bad, moved = check(bones)
print("after 4 s with a player 9 studs away: %d bones, %d bad numbers, %d posed" % (n, bad, moved))
assert bad == 0 and moved > 120

head.CFrame = lua.eval("CFrame.new")(10.5, 5.5, 17)          # right up close
model.attrs["Attack"] = 1
for i in range(90):
    advance(1 / 60)
snip = model.FindFirstChild(model, "Snip", True)
print("attack: Snip sound played %s times" % snip.played)
assert snip.played and snip.played >= 1

model.attrs["Patrol"] = True
before = lua.eval("function(m) return m:GetPivot().Position end")(model)
for i in range(300):
    advance(1 / 60)
after = lua.eval("function(m) return m:GetPivot().Position end")(model)
moved_by = lua.eval("function(a, b) return (a - b).Magnitude end")(after, before)
print("patrol moved it %.2f studs" % moved_by)
assert moved_by > 1

model.attrs["Procedural"] = False
advance(1 / 60)
n, bad, moved = check(bones)
print("Procedural off: %d bones still posed" % moved)
assert moved == 0

# ------------------------------------------------------------------ the Transform maths, checked through the bone tree
verify = lua.eval("""
function(bones, poseModule)
    -- the model frame the animator uses
    local first = bones
    local right = first["UpperArm1.R"].WorldPosition - first["UpperArm1.L"].WorldPosition
    right = Vector3.new(right.X, 0, right.Z).Unit
    local hips = first.Root.WorldPosition
    local frame = CFrame.fromMatrix(Vector3.new(hips.X, 0, hips.Z), right, Vector3.new(0, 1, 0))
    local inv = frame:Inverse()
    local pos, parent, order, rest = {}, {}, {}, {}
    for name, b in pairs(bones) do
        b.Transform = CFrame.new()
        pos[name] = (inv * b.WorldCFrame).Position
        rest[name] = (inv * b.WorldCFrame).Rotation
        if b.Parent.ClassName == "Bone" then parent[name] = b.Parent.Name end
    end
    local visited = {}
    local function visit(n) if visited[n] then return end; visited[n] = true; if parent[n] then visit(parent[n]) end; table.insert(order, n) end
    for n in pairs(bones) do visit(n) end
    local pose = poseModule.new({ pos = pos, parent = parent, order = order }, 3)
    local out
    for i = 1, 200 do
        out = pose:update({ dt = 1/60, t = i / 60, speed = 4, target = Vector3.new(-1, 5, -4), near = 0.8,
            aggro = 0.5, attack = i > 150 and 1 or 0, frame = frame })
    end
    for name, cf in pairs(out) do
        local q = rest[name]
        bones[name].Transform = q:Inverse() * cf * q
    end
    local worst, worstName = 0, ""
    for name, b in pairs(bones) do
        -- (the swinging chains are turned after the forward kinematics, so past their first
        -- bone StitcherPose's P is where they'd hang if stiff: those are checked by eye instead)
        local idx = tonumber(string.match(name, "_(%d+)$") or "1")
        if idx >= 2 then
            -- skip
        else
        local want = frame * pose.P[name]
        local got = b.TransformedWorldCFrame.Position
        local e = (want - got).Magnitude
        if e > worst then worst, worstName = e, name end
        end
    end
    return worst, worstName
end""")
fresh = lua.eval("function(m) local t = {}; for _, d in ipairs(m:GetDescendants()) do if d.ClassName == 'Bone' then t[d.Name] = d end end; return t end")(model)
worst, name = verify(fresh, G.MODULES[module_script])
print("Transform maths: worst joint is %.6f studs from where StitcherPose put it (%s)" % (worst, name))
assert worst < 1e-3
print("ANIMATOR OK")
