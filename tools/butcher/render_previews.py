# Renders the preview sheets from out/TheButcher.blend: the turnaround, close
# ups, and test poses that bend every part of the rig (to check the skinning).
#   python3 render_previews.py -- ./out [rest|close|poses]
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector as V, Matrix, Quaternion

OUT = os.path.abspath(sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "out")
args = sys.argv[sys.argv.index("--") + 2:] if "--" in sys.argv else []
ONLY = args[0] if args else None
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, "TheButcher.blend"))
import preview

arm = bpy.data.objects["ButcherRig"]
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)      # Blender: X = its left, Y = behind it, Z = up


def rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, V(axis))


def pose(rots, moves=None):
    """rots: bone -> turn in the model's frame, at the joint, carried by its parents.
    signs: +X tips the spine/neck/head forward, swings a leg or arm BACK, bends a knee, opens the jaw"""
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = V()
    for name, r in rots.items():
        pb = arm.pose.bones[name]
        q = pb.bone.matrix_local.to_3x3()
        pb.rotation_quaternion = (q.inverted() @ r @ q).to_quaternion()
    for name, t in (moves or {}).items():
        pb = arm.pose.bones[name]
        pb.location = pb.bone.matrix_local.to_3x3().inverted() @ V(t)
    bpy.context.view_layer.update()


def menace():
    """hunched, head down and turned, the cleaver raised, the free hand reaching"""
    r = {"Spine2": rot(X, 6), "Spine3": rot(X, 8), "Spine4": rot(X, 6), "Neck1": rot(X, 10),
         "Neck3": rot(Y, 12) @ rot(Z, -15), "Head": rot(X, 8) @ rot(Y, 10),
         "Jaw": rot(X, 22), "UpperArm1.R": rot(X, -95) @ rot(Y, 15), "Forearm1.R": rot(X, -60), "Hand.R": rot(X, 20),
         "UpperArm1.L": rot(X, -55) @ rot(Y, -25), "Forearm1.L": rot(X, -25),
         "Thigh1.L": rot(X, -25), "Shin1.L": rot(X, 20), "Thigh1.R": rot(X, 12), "Shin1.R": rot(X, 25),
         "Foot.R": rot(X, -15)}
    for f in ("Index", "Middle", "Ring", "Pinky"):
        r[f + "1.L"] = rot(Y, -25)
        r[f + "2.L"] = rot(Y, -35)
    for c in (3, 4, 5):
        r["Apron%d_1" % c] = rot(X, -14)
    return r, {"Belly": (0, -0.05, 0.03)}


def stride():
    r = {"Thigh1.L": rot(X, -38), "Shin1.L": rot(X, 15), "Thigh1.R": rot(X, 25), "Shin1.R": rot(X, 50),
         "Foot.R": rot(X, -20), "Spine1": rot(Z, 8), "Spine4": rot(Z, -10),
         "UpperArm1.L": rot(X, 25), "UpperArm1.R": rot(X, -30), "Forearm1.R": rot(X, -20),
         "Neck2": rot(Z, 15), "Head": rot(Y, -12)}
    for c in (3, 4, 5):
        r["Apron%d_1" % c] = rot(X, -18)
        r["Apron%d_2" % c] = rot(X, -6)
    for c in (1, 7):
        r["Apron%d_1" % c] = rot(X, 8)
    return r, {}


def face_test():
    r = {"Jaw": rot(X, 28), "Head": rot(Y, -8), "Eye.L": rot(Z, 20), "Eye.R": rot(Z, 20)}
    m = {"LipUpper.L": (0, 0, 0.02), "LipUpper.R": (0, 0, 0.015), "MouthCorner.L": (0.02, 0.01, 0.01),
         "MouthCorner.R": (-0.02, 0.01, 0.01), "Brow.L": (0, 0, -0.02), "Brow.R": (0, 0, -0.02),
         "BrowInner.L": (-0.01, 0, -0.025), "BrowInner.R": (0.01, 0, -0.025), "LidUpper.L": (0, 0, -0.015),
         "Cheek.L": (0, 0, 0.015), "Nose": (0, 0, 0.01)}
    for i in (1, 2, 3, 15, 16):
        r["Hair%02d_1" % i] = rot(X, -20)
    return r, m


def head_of():
    hb = arm.pose.bones["Head"]
    return arm.matrix_world @ (hb.head + (hb.tail - hb.head) * 0.45)


sheets = []
if ONLY in (None, "rest"):
    pose({})
    views = [((0, -15, 4.4), (0, 0, 4.1), 50), ((-10.5, -10.5, 4.8), (0, 0, 4.1), 50), ((15, 0, 4.4), (0, 0, 4.1), 50),
             ((0, 15, 4.4), (0, 0, 4.1), 50)]
    outs = preview.render(os.path.join(OUT, "pv_rest.png"), views, size=(480, 720), engine="CYCLES", samples=48)
    sheets.append(preview.stitch(outs, os.path.join(OUT, "preview_turnaround.png")))
if ONLY in (None, "close"):
    pose({})
    hc = head_of()
    views = [(tuple(hc + V((0, -2.5, 0.05))), tuple(hc + V((0, 0, -0.05))), 50),
             (tuple(hc + V((-1.8, -1.8, 0.1))), tuple(hc + V((0, 0, -0.05))), 50),
             ((0.6, -4.6, 4.6), (0.1, 0, 4.2), 50),
             ((-1.6, -3.4, 3.6), (-1.5, -0.3, 3.2), 45),
             ((1.2, -2.6, 0.7), (0.2, -0.2, 0.4), 45)]
    outs = preview.render(os.path.join(OUT, "pv_close.png"), views, size=(560, 640), engine="CYCLES", samples=48)
    sheets.append(preview.stitch(outs, os.path.join(OUT, "preview_closeups.png")))
if ONLY in (None, "poses"):
    outs = []
    for name, fn in (("menace", menace), ("stride", stride)):
        pose(*fn())
        outs += preview.render(os.path.join(OUT, "pv_%s.png" % name), [((-8, -12, 4.8), (0, 0, 4.2), 50)],
                               size=(480, 720), engine="CYCLES", samples=32)
    pose(*face_test())
    hc = head_of()
    outs += preview.render(os.path.join(OUT, "pv_face.png"), [(tuple(hc + V((-1.0, -2.3, 0.1))), tuple(hc), 50)],
                           size=(480, 720), engine="CYCLES", samples=32)
    sheets.append(preview.stitch(outs, os.path.join(OUT, "preview_poses.png")))
print("SHEETS", sheets)
