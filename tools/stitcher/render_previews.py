# Renders the preview sheets from out/TheStitcher.blend: the turnaround, close
# ups, and a few poses (to check the skinning holds up when it moves).
#   python3 render_previews.py -- ./out
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector as V, Matrix, Quaternion

OUT = os.path.abspath(sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "out")
ONLY = sys.argv[sys.argv.index("--") + 2] if "--" in sys.argv and len(sys.argv) > sys.argv.index("--") + 2 else None
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, "TheStitcher.blend"))
import preview

arm = bpy.data.objects["StitcherRig"]


def rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, V(axis))


def pose(rots, lift=V((0, 0, 0))):
    """rots: bone -> 3x3 turn in the MODEL's frame, taken at the joint and carried by its parents
    (the same convention as StitcherPose.lua)"""
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = V()
    for name, r in rots.items():
        pb = arm.pose.bones.get(name)
        if not pb:
            print("no bone", name)
            continue
        q = pb.bone.matrix_local.to_3x3()
        pb.rotation_quaternion = (q.inverted() @ r @ q).to_quaternion()
    rootb = arm.pose.bones["Root"]
    rootb.location = rootb.bone.matrix_local.to_3x3().inverted() @ lift
    bpy.context.view_layer.update()


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)      # Blender: X = its left, Y = behind it, Z = up


# signs (Blender model frame): +X tips a spine/neck forward, swings a leg or arm BACK
# (so -X swings it forward), bends a knee, opens the jaw; +Z flares the left ribs out


def hunched():
    r = {}
    for i, a in enumerate((4, 6, 8, 7, 6)):
        r["Spine%d" % (i + 1)] = rot(X, a)
    r["Neck1"] = rot(X, 16)
    r["Neck2"] = rot(X, 8)
    r["Neck3"] = rot(X, -6) @ rot(Y, -10)
    r["Neck4"] = rot(X, -10) @ rot(Y, -14)
    r["Head"] = rot(X, -8) @ rot(Y, -20)
    for s, sg in (("L", 1), ("R", -1)):
        r["Clavicle." + s] = rot(Y, sg * 6)
        r["UpperArm1." + s] = rot(Y, sg * -16) @ rot(X, -6)
        r["Forearm1." + s] = rot(X, -14)
        r["Thigh." + s] = rot(X, -6)
        r["Shin." + s] = rot(X, 12)
        r["Foot." + s] = rot(X, -6)
    r["Hand.R"] = rot(X, -20)
    return r


def attack():
    r = hunched()
    r["Jaw"] = rot(X, 30)
    r["MouthCorner.L"] = rot(Z, -10)
    r["MouthCorner.R"] = rot(Z, 10)
    r["Head"] = rot(X, -12) @ rot(Y, 26)
    for i in range(1, 7):
        r["Rib%d.L" % i] = rot(Z, 40 - i * 3)
        r["Rib%d.R" % i] = rot(Z, -40 + i * 3)
    r["ScissorBlade"] = Matrix.Rotation(math.radians(-40), 3, V(SN))
    r["UpperArm1.R"] = rot(X, -75) @ rot(Y, 10)
    r["Forearm1.R"] = rot(X, -25)
    r["UpperArm1.L"] = rot(X, -60) @ rot(Y, -10)
    for f in ("Index", "Middle", "Ring", "Pinky"):
        r[f + "1.L"] = rot(X, -10)
    for i in range(1, 4):
        r["Hair%02d_1" % (5 + i)] = rot(Y, 20)
    return r


def walking():
    r = hunched()
    r["Thigh.L"] = rot(X, -30)
    r["Shin.L"] = rot(X, 12)
    r["Thigh.R"] = rot(X, 20)
    r["Shin.R"] = rot(X, 45)
    r["Foot.R"] = rot(X, -15)
    for c in ("F", "FL"):
        r["Skirt%s_1" % c] = rot(X, -18)
    for c in ("B", "BR"):
        r["Skirt%s_1" % c] = rot(X, 10)
    r["UpperArm1.L"] = rot(Y, -16) @ rot(X, 14)
    r["UpperArm1.R"] = rot(Y, 16) @ rot(X, -16)
    return r


SN = tuple(arm["scissor_n"])

sheets = []
if ONLY in (None, "rest"):
    pose({})
    outs = preview.render(os.path.join(OUT, "pv_rest.png"), preview.FULL, size=(480, 720), engine="CYCLES", samples=48)
    sheets.append(preview.stitch(outs, os.path.join(OUT, "preview_turnaround.png")))
if ONLY in (None, "close"):
    pose({})
    views = [((0, -2.7, 7.95), (0, -0.25, 7.95), 50), ((-1.8, -2.0, 8.05), (0, -0.25, 7.9), 50),
             ((0.5, -2.9, 6.0), (0, 0, 5.9), 50), ((-1.3, -3.3, 3.9), (-1.95, -0.4, 3.45), 45)]
    outs = preview.render(os.path.join(OUT, "pv_close.png"), views, size=(560, 640), engine="CYCLES", samples=48)
    sheets.append(preview.stitch(outs, os.path.join(OUT, "preview_closeups.png")))
if ONLY in (None, "poses"):
    outs = []
    for name, fn in (("hunched", hunched), ("attack", attack), ("walking", walking)):
        pose(fn())
        outs += preview.render(os.path.join(OUT, "pv_%s.png" % name), [((-7, -10, 4.8), (0, 0, 4.3), 50)],
                               size=(480, 720), engine="CYCLES", samples=32)
    sheets.append(preview.stitch(outs, os.path.join(OUT, "preview_poses.png")))
print("SHEETS", sheets)
