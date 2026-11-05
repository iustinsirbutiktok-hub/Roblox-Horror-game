# The Stitcher's skeleton: joint positions (Blender units = Roblox studs, Z up,
# facing -Y, its left = +X), the bones (about 160 of them) and the body radii
# the skin is grown from.
import math
from mathutils import Vector as V, Matrix

J = {}      # joint name -> position
R = {}      # joint name -> (radius x, radius y) of the body there
BONES = []  # (bone, head point, tail point, parent bone)
HANDS = {}  # side -> {"fwd", "lat", "palm", "grip"...}


def j(name, p, rx=None, ry=None):
    J[name] = V(p)
    if rx is not None:
        R[name] = (rx, ry if ry is not None else rx)


def b(name, head, tail, parent):
    BONES.append((name, V(head), V(tail), parent))


# ---------------------------------------------------------------- legs (in loose trousers)
for s, side in ((1, "L"), (-1, "R")):
    j("Toe." + side, (s * 0.35, -0.62, 0.08), 0.06, 0.04)
    j("Ball." + side, (s * 0.335, -0.38, 0.1), 0.075, 0.05)
    j("Heel." + side, (s * 0.31, 0.12, 0.11), 0.06, 0.06)
    j("Ankle." + side, (s * 0.31, 0.02, 0.36), 0.075, 0.075)
    j("Cuff." + side, (s * 0.31, 0.0, 0.62), 0.1, 0.1)          # (tucked into the boots)
    j("ShinMid." + side, (s * 0.305, -0.01, 1.55), 0.16, 0.165)
    j("Knee." + side, (s * 0.30, -0.06, 2.55), 0.16, 0.165)
    j("ThighMid." + side, (s * 0.32, 0.0, 3.5), 0.18, 0.19)
    j("Hip." + side, (s * 0.33, 0.02, 4.3), 0.19, 0.2)

# ---------------------------------------------------------------- spine
j("Pelvis", (0, 0.03, 4.5), 0.33, 0.21)
j("Spine1", (0, 0.04, 4.95), 0.19, 0.14)      # pinched, starved waist
j("Spine2", (0, 0.06, 5.38), 0.22, 0.16)
j("Spine3", (0, 0.07, 5.8), 0.3, 0.22)        # ribcage
j("Spine4", (0, 0.06, 6.2), 0.33, 0.23)
j("Spine5", (0, 0.04, 6.55), 0.33, 0.2)       # top of the chest
j("Neck1", (0, 0.01, 6.86), 0.1, 0.1)
j("Neck2", (0, -0.02, 6.98), 0.09, 0.094)
j("Neck3", (0, -0.05, 7.1), 0.087, 0.092)
j("Neck4", (0, -0.08, 7.23), 0.087, 0.092)
j("HeadBase", (0, -0.1, 7.38), 0.08, 0.08)

# The head is designed in its own space (head.py's numbers, around HC) and
# then scaled up and set on the neck by HEAD_M.
HC = V((0, -0.14, 8.12))        # middle of the head (design space)
HEAD_OLD = V((0, -0.1, 7.7))
HEAD_NEW = V((0, -0.1, 7.38))
HEAD_SCALE = 1.3
HEAD_M = Matrix.Translation(HEAD_NEW) @ Matrix.Scale(HEAD_SCALE, 4) @ Matrix.Translation(-HEAD_OLD)


def head_xf(p):
    return HEAD_NEW + (V(p) - HEAD_OLD) * HEAD_SCALE


J["HC"] = head_xf(HC)
J["HeadTop"] = head_xf((0, -0.12, 8.72))

# ---------------------------------------------------------------- arms (too long, stick thin)
ARM_DOWN = math.radians(25)
for s, side in ((1, "L"), (-1, "R")):
    j("Clav." + side, (s * 0.2, 0.0, 6.66), 0.1, 0.085)
    sh = V((s * 0.58, -0.02, 6.44))
    d = V((s * math.sin(ARM_DOWN), -0.1, -math.cos(ARM_DOWN))).normalized()
    el = sh + d * 1.5
    wr = el + d * 1.42
    j("Shoulder." + side, sh, 0.115, 0.115)
    j("UpperMid." + side, sh + d * 0.75, 0.08, 0.085)
    j("Elbow." + side, el, 0.08, 0.085)
    j("ForeMid." + side, el + d * 0.68, 0.068, 0.062)
    j("Wrist." + side, wr, 0.055, 0.045)

    # the hand's frame: fwd = along the fingers, palm = out of the palm
    # (towards the thigh), lat = across the knuckles from index to pinky
    fwd = d.copy()
    palm = V((-s, 0, 0))
    palm = (palm - fwd * palm.dot(fwd)).normalized()
    lat = palm.cross(fwd).normalized()
    if lat.y < 0:
        lat = -lat
    gripping = side == "R"          # the right hand is clenched round the scissors
    if gripping:
        # the fist turned (ulnar deviation) so the blades poke out forward and down
        turn = Matrix.Rotation(math.radians(28), 3, palm)
        if (turn @ -lat).z > 0:
            turn = Matrix.Rotation(math.radians(-28), 3, palm)
        fwd, lat = turn @ fwd, turn @ lat
    curl_axis = fwd.cross(palm).normalized()          # turning fwd towards the palm
    palm_end = wr + fwd * 0.5
    j("Palm." + side, palm_end, 0.03, 0.1)
    HANDS[side] = {"fwd": fwd, "palm": palm, "lat": lat, "wrist": wr, "palm_end": palm_end}

    names = ["Index", "Middle", "Ring", "Pinky"]
    offsets = [-0.1, -0.034, 0.032, 0.094]
    lengths = [(0.32, 0.25, 0.2), (0.36, 0.28, 0.22), (0.33, 0.26, 0.2), (0.26, 0.21, 0.17)]
    if gripping:
        curls = [(84, 100, 78), (86, 100, 80), (88, 100, 78), (90, 98, 76)]
    else:
        curls = [(14, 26, 18), (18, 30, 22), (22, 32, 24), (26, 34, 26)]
    for name, off, ln, cu in zip(names, offsets, lengths, curls):
        meta = wr + fwd * 0.06 + lat * off * 0.45 + palm * 0.005
        base = palm_end + lat * off + fwd * 0.02
        J["%s0.%s" % (name, side)] = meta
        J["%s1.%s" % (name, side)] = base
        spread = Matrix.Rotation(math.radians(off * 60) * (1 if not gripping else 0.2), 3, palm)
        dirn = spread @ fwd
        p = base
        total = 0
        for i in range(3):
            total += cu[i]
            dd = Matrix.Rotation(math.radians(total), 3, curl_axis) @ dirn
            p = p + dd * ln[i]
            J["%s%d.%s" % (name, i + 2, side)] = p
    # thumb: from the side of the palm by the index finger, across the palm
    tb = wr + fwd * 0.1 - lat * 0.08 + palm * 0.04
    td = (fwd * 0.55 - lat * 0.55 + palm * 0.5).normalized()
    tl = (0.2, 0.18, 0.15)
    tcurl = (25, 40, 30) if gripping else (8, 14, 12)
    taxis = td.cross(lat).normalized()
    J["Thumb1." + side] = tb
    p = tb
    total = 0
    for i in range(3):
        total += tcurl[i]
        dd = Matrix.Rotation(math.radians(total), 3, taxis) @ td
        p = p + dd * tl[i]
        J["Thumb%d.%s" % (i + 2, side)] = p
    if gripping:
        # where the scissors sit: in the middle of the loop the clenched fingers make
        loop = [J["%s%d.%s" % (n, i, side)] for n in ("Middle", "Ring") for i in (1, 2, 3, 4)]
        HANDS[side]["grip"] = sum(loop, V()) / len(loop)
        HANDS[side]["grip_axis"] = (-lat).normalized()      # blades out of the index side

for side in ("L", "R"):
    for name in ("Index", "Middle", "Ring", "Pinky"):
        rr = [0.03, 0.034, 0.03, 0.026, 0.017]
        for i in range(5):
            R["%s%d.%s" % (name, i, side)] = (rr[i], rr[i])
    rr = [0.042, 0.038, 0.032, 0.022]
    for i in range(4):
        R["Thumb%d.%s" % (i + 1, side)] = (rr[i], rr[i])

# ---------------------------------------------------------------- body bones
b("Root", J["Pelvis"], J["Spine1"], None)
b("Spine1", J["Spine1"], J["Spine2"], "Root")
b("Spine2", J["Spine2"], J["Spine3"], "Spine1")
b("Spine3", J["Spine3"], J["Spine4"], "Spine2")
b("Spine4", J["Spine4"], J["Spine5"], "Spine3")
b("Spine5", J["Spine5"], J["Neck1"], "Spine4")
b("Neck1", J["Neck1"], J["Neck2"], "Spine5")
b("Neck2", J["Neck2"], J["Neck3"], "Neck1")
b("Neck3", J["Neck3"], J["Neck4"], "Neck2")
b("Neck4", J["Neck4"], J["HeadBase"], "Neck3")
b("Head", J["HeadBase"], J["HeadTop"], "Neck4")

for side in ("L", "R"):
    s = 1 if side == "L" else -1
    b("Thigh." + side, J["Hip." + side], J["Knee." + side], "Root")
    b("Shin." + side, J["Knee." + side], J["Ankle." + side], "Thigh." + side)
    b("Foot." + side, J["Ankle." + side], J["Ball." + side], "Shin." + side)
    b("Toe." + side, J["Ball." + side], J["Toe." + side], "Foot." + side)
    b("Clavicle." + side, J["Clav." + side], J["Shoulder." + side], "Spine5")
    b("UpperArm1." + side, J["Shoulder." + side], J["UpperMid." + side], "Clavicle." + side)
    b("UpperArm2." + side, J["UpperMid." + side], J["Elbow." + side], "UpperArm1." + side)
    b("Forearm1." + side, J["Elbow." + side], J["ForeMid." + side], "UpperArm2." + side)
    b("Forearm2." + side, J["ForeMid." + side], J["Wrist." + side], "Forearm1." + side)
    b("Hand." + side, J["Wrist." + side], J["Palm." + side], "Forearm2." + side)
    for name in ("Index", "Middle", "Ring", "Pinky"):
        b("%sMeta.%s" % (name, side), J["%s0.%s" % (name, side)], J["%s1.%s" % (name, side)], "Hand." + side)
        for i in range(1, 4):
            b("%s%d.%s" % (name, i, side), J["%s%d.%s" % (name, i, side)], J["%s%d.%s" % (name, i + 1, side)],
              "%sMeta.%s" % (name, side) if i == 1 else "%s%d.%s" % (name, i - 1, side))
    for i in range(1, 4):
        b("Thumb%d.%s" % (i, side), J["Thumb%d.%s" % (i, side)], J["Thumb%d.%s" % (i + 1, side)],
          "Hand." + side if i == 1 else "Thumb%d.%s" % (i - 1, side))

# ---------------------------------------------------------------- face (set by head.py's numbers)
EYE = {"L": HC + V((0.1, -0.235, 0.0)), "R": HC + V((-0.1, -0.235, 0.0))}
JAW_HINGE = HC + V((0, 0.0, -0.17))
CHIN = HC + V((0, -0.32, -0.5))

def hb(name, head, tail, parent):
    b(name, head_xf(head), head_xf(tail), parent)


hb("Jaw", JAW_HINGE, CHIN, "Head")
for side, s in (("L", 1), ("R", -1)):
    e = EYE[side]
    hb("Eye." + side, e, e + V((0, -0.08, 0)), "Head")
    hb("Brow." + side, HC + V((s * 0.1, -0.2, 0.09)), HC + V((s * 0.11, -0.32, 0.1)), "Head")
    hb("Cheek." + side, HC + V((s * 0.13, -0.16, -0.12)), HC + V((s * 0.17, -0.28, -0.14)), "Head")
    hb("MouthCorner." + side, HC + V((s * 0.14, -0.2, -0.18)), HC + V((s * 0.24, -0.2, -0.17)), "Head")
hb("UpperLip", HC + V((0, -0.2, -0.22)), HC + V((0, -0.33, -0.25)), "Head")
hb("LowerLip", HC + V((0, -0.18, -0.34)), HC + V((0, -0.32, -0.36)), "Jaw")
hb("Mask", HC + V((0, -0.3, -0.48)), HC + V((0, -0.33, -0.78)), "Jaw")
hb("Cap", HC + V((0, 0.0, 0.3)), HC + V((0, 0.0, 0.6)), "Head")

# ---------------------------------------------------------------- the ribs that show (6 a side)
RIB_Z = [6.36, 6.21, 6.06, 5.91, 5.76, 5.61]
for side, s in (("L", 1), ("R", -1)):
    for i, z in enumerate(RIB_Z):
        pivot = V((s * 0.27, 0.13, z))
        tip = V((s * 0.05, -0.22, z - 0.12))
        b("Rib%d.%s" % (i + 1, side), pivot, tip, "Spine4" if z > 6.0 else "Spine3")

# ---------------------------------------------------------------- the scissors
# (positions filled in by scissors.py; the blade pivots at the screw)
SCISSORS = {}


def scissor_bones(pivot, blade_dir, normal):
    SCISSORS.update(pivot=pivot, dir=blade_dir, normal=normal)
    b("Scissors", pivot - blade_dir * 0.45, pivot, "Hand.R")
    b("ScissorBlade", pivot, pivot + blade_dir * 0.9, "Scissors")
    # (no skin: it only marks the screw's axis, so the animator knows which way the blade swings)
    b("ScissorHinge", pivot + normal * 0.12, pivot + normal * 0.2, "Scissors")


# dangling things (hair, skirt, ties, bandages...) are added by the modules
# that build them, through chain()
CHAINS = {}      # chain name -> [bone names, top to bottom]


def chain(name, points, parent):
    names = []
    for i in range(len(points) - 1):
        bn = "%s%d" % (name, i + 1)
        b(bn, points[i], points[i + 1], parent if i == 0 else names[-1])
        names.append(bn)
    CHAINS[name] = names
    return names


# the skin graph: edges between joints
SKIN_EDGES = [("Pelvis", "Spine1"), ("Spine1", "Spine2"), ("Spine2", "Spine3"), ("Spine3", "Spine4"),
              ("Spine4", "Spine5"), ("Spine5", "Neck1"), ("Neck1", "Neck2"), ("Neck2", "Neck3"),
              ("Neck3", "Neck4"), ("Neck4", "HeadBase")]
for side in ("L", "R"):
    SKIN_EDGES += [
        ("Pelvis", "Hip." + side), ("Hip." + side, "ThighMid." + side), ("ThighMid." + side, "Knee." + side),
        ("Knee." + side, "ShinMid." + side), ("ShinMid." + side, "Cuff." + side), ("Cuff." + side, "Ankle." + side),
        ("Ankle." + side, "Heel." + side), ("Ankle." + side, "Ball." + side), ("Ball." + side, "Toe." + side),
        ("Spine5", "Clav." + side), ("Clav." + side, "Shoulder." + side),
        ("Shoulder." + side, "UpperMid." + side), ("UpperMid." + side, "Elbow." + side),
        ("Elbow." + side, "ForeMid." + side), ("ForeMid." + side, "Wrist." + side),
        ("Wrist." + side, "Palm." + side),
    ]
    for name in ("Index", "Middle", "Ring", "Pinky"):
        SKIN_EDGES += [("Palm." + side, "%s1.%s" % (name, side))]
        SKIN_EDGES += [("%s%d.%s" % (name, i, side), "%s%d.%s" % (name, i + 1, side)) for i in range(1, 4)]
    SKIN_EDGES += [("Wrist." + side, "Thumb1." + side)]
    SKIN_EDGES += [("Thumb%d.%s" % (i, side), "Thumb%d.%s" % (i + 1, side)) for i in range(1, 4)]

# just the torso and the stubs of the shoulders and hips: what the gown hangs on
TORSO_EDGES = [e for e in SKIN_EDGES if all(not any(n.startswith(p) for p in (
    "Thigh", "Knee", "Shin", "Cuff", "Ankle", "Heel", "Ball", "Toe", "UpperMid", "Elbow", "ForeMid", "Wrist", "Palm",
    "Thumb", "Index", "Middle", "Ring", "Pinky", "ThighMid")) for n in e)]
