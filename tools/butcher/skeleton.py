# The Butcher's skeleton: joint positions (Blender units = Roblox studs, Z up,
# facing -Y, its left = +X), the bones (about 170) and the body radii the skin
# is grown from. A huge, heavy man: thick neck, gut, beefy arms, big hands.
import math
from mathutils import Vector as V, Matrix

J = {}      # joint name -> position
R = {}      # joint name -> (radius x, radius y) of the body there
BONES = []  # (bone, head point, tail point, parent bone)
HANDS = {}  # side -> the hand's frame and, for the right, the grip
CHAINS = {}  # chain name -> [bone names, top to bottom]


def j(name, p, rx=None, ry=None):
    J[name] = V(p)
    if rx is not None:
        R[name] = (rx, ry if ry is not None else rx)


def b(name, head, tail, parent):
    BONES.append((name, V(head), V(tail), parent))


def chain(name, points, parent):
    """bones <name>1, <name>2... through the points (name ends in "_")"""
    names = []
    for i in range(len(points) - 1):
        bn = "%s%d" % (name, i + 1)
        b(bn, points[i], points[i + 1], parent if i == 0 else names[-1])
        names.append(bn)
    CHAINS[name] = names
    return names


# ---------------------------------------------------------------- legs (in baggy work trousers)
for s, side in ((1, "L"), (-1, "R")):
    j("Toe." + side, (s * 0.45, -0.66, 0.09), 0.07, 0.05)
    j("Ball." + side, (s * 0.44, -0.42, 0.11), 0.09, 0.06)
    j("Heel." + side, (s * 0.42, 0.12, 0.13), 0.08, 0.08)
    j("Ankle." + side, (s * 0.42, 0.02, 0.42), 0.1, 0.1)
    j("Cuff." + side, (s * 0.42, 0.0, 0.66), 0.125, 0.125)      # (tucked into the boots)
    j("ShinMid." + side, (s * 0.42, -0.01, 1.4), 0.235, 0.245)
    j("Knee." + side, (s * 0.43, -0.05, 2.2), 0.25, 0.26)
    j("ThighMid." + side, (s * 0.44, 0.0, 3.1), 0.31, 0.32)
    j("Hip." + side, (s * 0.45, 0.02, 3.85), 0.34, 0.34)

# ---------------------------------------------------------------- the trunk: a gut, a barrel chest
j("Pelvis", (0, 0.05, 4.08), 0.6, 0.42)
j("Spine1", (0, 0.0, 4.55), 0.62, 0.5)
j("Spine2", (0, 0.0, 5.0), 0.64, 0.52)
j("Spine3", (0, 0.04, 5.45), 0.65, 0.47)
j("Spine4", (0, 0.06, 5.9), 0.69, 0.43)
j("Spine5", (0, 0.06, 6.28), 0.66, 0.38)
j("Neck1", (0, 0.05, 6.62), 0.21, 0.21)
j("Neck2", (0, 0.01, 6.82), 0.185, 0.19)
j("Neck3", (0, -0.04, 6.98), 0.17, 0.175)
j("HeadBase", (0, -0.07, 7.1), 0.15, 0.15)
# The head is designed in its own space (head.py's numbers, round HC) and then
# scaled up a little on the neck by HEAD_M.
HC = V((0, -0.14, 7.55))         # middle of the head (design space)
HEAD_PIVOT = V((0, -0.07, 7.1))
HEAD_SCALE = 1.1
HEAD_M = Matrix.Translation(HEAD_PIVOT) @ Matrix.Scale(HEAD_SCALE, 4) @ Matrix.Translation(-HEAD_PIVOT)


def head_xf(p):
    return HEAD_PIVOT + (V(p) - HEAD_PIVOT) * HEAD_SCALE


J["HC"] = head_xf(HC)
J["HeadTop"] = head_xf(HC + V((0, 0.02, 0.6)))

# ---------------------------------------------------------------- arms: thick, hanging heavy
ARM_DOWN = math.radians(17)
for s, side in ((1, "L"), (-1, "R")):
    j("Clav." + side, (s * 0.3, 0.02, 6.5), 0.24, 0.2)
    sh = V((s * 0.88, 0.0, 6.32))
    d = V((s * math.sin(ARM_DOWN), -0.07, -math.cos(ARM_DOWN))).normalized()
    el = sh + d * 1.38
    wr = el + d * 1.26
    j("Shoulder." + side, sh, 0.27, 0.27)
    j("UpperMid." + side, sh + d * 0.66, 0.205, 0.215)
    j("Elbow." + side, el, 0.19, 0.2)
    j("ForeUpper." + side, el + d * 0.36, 0.205, 0.19)
    j("ForeMid." + side, el + d * 0.72, 0.175, 0.16)
    j("Wrist." + side, wr, 0.13, 0.105)

    fwd = d.copy()
    palm = V((-s, 0, 0))
    palm = (palm - fwd * palm.dot(fwd)).normalized()
    lat = palm.cross(fwd).normalized()
    if lat.y < 0:
        lat = -lat
    gripping = side == "R"
    if gripping:
        # the cleaver hand: turned palm-back (pronated), the fist cocked down
        # on its little-finger side (ulnar deviation) so the cleaver hangs out
        # and down from it, its flat towards the front
        pro = Matrix.Rotation(math.radians(80), 3, fwd)
        if (pro @ palm).y < 0:
            pro = Matrix.Rotation(math.radians(-80), 3, fwd)
        palm, lat = pro @ palm, pro @ lat
        dev = Matrix.Rotation(math.radians(38), 3, palm)
        if (dev @ lat).z > lat.z:
            dev = Matrix.Rotation(math.radians(-38), 3, palm)
        fwd, lat = dev @ fwd, dev @ lat
    curl_axis = fwd.cross(palm).normalized()
    palm_end = wr + fwd * 0.48
    j("Palm." + side, palm_end, 0.06, 0.17)
    HANDS[side] = {"fwd": fwd, "palm": palm, "lat": lat, "wrist": wr, "palm_end": palm_end}

    names = ["Index", "Middle", "Ring", "Pinky"]
    offsets = [-0.15, -0.05, 0.05, 0.14]
    lengths = [(0.25, 0.17, 0.14), (0.28, 0.19, 0.15), (0.26, 0.18, 0.14), (0.21, 0.15, 0.12)]
    curls = [(84, 98, 72), (86, 98, 72), (88, 96, 70), (90, 94, 68)] if gripping else \
        [(16, 26, 18), (20, 30, 22), (24, 32, 24), (28, 34, 26)]
    for name, off, ln, cu in zip(names, offsets, lengths, curls):
        J["%s0.%s" % (name, side)] = wr + fwd * 0.07 + lat * off * 0.45 + palm * 0.01
        base = palm_end + lat * off + fwd * 0.02
        J["%s1.%s" % (name, side)] = base
        spread = Matrix.Rotation(math.radians(off * 45) * (0.2 if gripping else 1), 3, palm)
        dirn = spread @ fwd
        p = base
        total = 0
        for i in range(3):
            total += cu[i]
            p = p + (Matrix.Rotation(math.radians(total), 3, curl_axis) @ dirn) * ln[i]
            J["%s%d.%s" % (name, i + 2, side)] = p
    tb = wr + fwd * 0.12 - lat * 0.15 + palm * 0.07
    td = (fwd * 0.5 - lat * 0.6 + palm * 0.55).normalized()
    tl = (0.22, 0.17, 0.14)
    tcurl = (30, 45, 35) if gripping else (8, 14, 12)
    taxis = td.cross(lat).normalized()
    J["Thumb1." + side] = tb
    p = tb
    total = 0
    for i in range(3):
        total += tcurl[i]
        p = p + (Matrix.Rotation(math.radians(total), 3, taxis) @ td) * tl[i]
        J["Thumb%d.%s" % (i + 2, side)] = p
    if gripping:
        loop = [J["%s%d.%s" % (n, i, side)] for n in ("Middle", "Ring") for i in (1, 2, 3, 4)]
        HANDS[side]["grip"] = sum(loop, V()) / len(loop)
        HANDS[side]["grip_axis"] = lat.normalized()          # the handle runs out of the little-finger side

for side in ("L", "R"):
    for name in ("Index", "Middle", "Ring", "Pinky"):
        rr = [0.05, 0.058, 0.052, 0.046, 0.034]
        for i in range(5):
            R["%s%d.%s" % (name, i, side)] = (rr[i], rr[i])
    rr = [0.07, 0.062, 0.054, 0.04]
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
b("Neck3", J["Neck3"], J["HeadBase"], "Neck2")
b("Head", J["HeadBase"], J["HeadTop"], "Neck3")
# soft tissue you can push about: the gut, the chest, the fat at the back of the neck
b("Belly", V((0, -0.2, 4.75)), V((0, -0.55, 4.6)), "Spine1")
b("BellyLow", V((0, -0.25, 4.35)), V((0, -0.55, 4.2)), "Belly")
for s, side in ((1, "L"), (-1, "R")):
    b("Pec." + side, V((s * 0.3, -0.1, 6.0)), V((s * 0.35, -0.45, 5.85)), "Spine4")
    b("LoveHandle." + side, V((s * 0.45, 0.05, 4.6)), V((s * 0.65, 0.05, 4.55)), "Spine1")
b("NeckFat", V((0, 0.15, 6.7)), V((0, 0.35, 6.65)), "Spine5")

for side in ("L", "R"):
    b("Thigh1." + side, J["Hip." + side], J["ThighMid." + side], "Root")
    b("Thigh2." + side, J["ThighMid." + side], J["Knee." + side], "Thigh1." + side)
    b("Shin1." + side, J["Knee." + side], J["ShinMid." + side], "Thigh2." + side)
    b("Shin2." + side, J["ShinMid." + side], J["Ankle." + side], "Shin1." + side)
    b("Foot." + side, J["Ankle." + side], J["Ball." + side], "Shin2." + side)
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

# ---------------------------------------------------------------- face
C = HC
EYE = {"L": C + V((0.13, -0.29, 0.05)), "R": C + V((-0.13, -0.29, 0.05))}     # (design space)
_b = b


def b(name, head, tail, parent):         # face bones: given in design space
    _b(name, head_xf(head), head_xf(tail), parent)


b("Jaw", C + V((0, 0.02, -0.12)), C + V((0, -0.36, -0.46)), "Head")
for side, s in (("L", 1), ("R", -1)):
    e = EYE[side]
    b("Eye." + side, e, e + V((0, -0.08, 0)), "Head")
    b("LidUpper." + side, e + V((0, 0.0, 0.0)), e + V((0, -0.07, 0.035)), "Head")
    b("LidLower." + side, e + V((0, 0.0, 0.0)), e + V((0, -0.07, -0.035)), "Head")
    b("Brow." + side, C + V((s * 0.16, -0.26, 0.15)), C + V((s * 0.18, -0.38, 0.15)), "Head")
    b("BrowInner." + side, C + V((s * 0.06, -0.28, 0.13)), C + V((s * 0.06, -0.4, 0.13)), "Head")
    b("Cheek." + side, C + V((s * 0.17, -0.22, -0.1)), C + V((s * 0.21, -0.34, -0.12)), "Head")
    b("MouthCorner." + side, C + V((s * 0.1, -0.24, -0.25)), C + V((s * 0.16, -0.3, -0.25)), "Head")
    b("LipUpper." + side, C + V((s * 0.05, -0.26, -0.2)), C + V((s * 0.05, -0.38, -0.21)), "Head")
    b("LipLower." + side, C + V((s * 0.05, -0.24, -0.31)), C + V((s * 0.05, -0.37, -0.32)), "Jaw")
    b("Ear." + side, C + V((s * 0.3, 0.0, 0.0)), C + V((s * 0.34, 0.06, 0.0)), "Head")
b("Nose", C + V((0, -0.33, -0.02)), C + V((0, -0.43, -0.1)), "Head")
b = _b

# dangling things (hair, the apron, its straps and ties, the rolled cuffs) are
# added by the modules that build them, through chain() and b()

# ---------------------------------------------------------------- the skin graph
SKIN_EDGES = [("Pelvis", "Spine1"), ("Spine1", "Spine2"), ("Spine2", "Spine3"), ("Spine3", "Spine4"),
              ("Spine4", "Spine5"), ("Spine5", "Neck1"), ("Neck1", "Neck2"), ("Neck2", "Neck3"),
              ("Neck3", "HeadBase")]
for side in ("L", "R"):
    SKIN_EDGES += [
        ("Pelvis", "Hip." + side), ("Hip." + side, "ThighMid." + side), ("ThighMid." + side, "Knee." + side),
        ("Knee." + side, "ShinMid." + side), ("ShinMid." + side, "Cuff." + side), ("Cuff." + side, "Ankle." + side),
        ("Ankle." + side, "Heel." + side), ("Ankle." + side, "Ball." + side), ("Ball." + side, "Toe." + side),
        ("Spine5", "Clav." + side), ("Clav." + side, "Shoulder." + side),
        ("Shoulder." + side, "UpperMid." + side), ("UpperMid." + side, "Elbow." + side),
        ("Elbow." + side, "ForeUpper." + side), ("ForeUpper." + side, "ForeMid." + side),
        ("ForeMid." + side, "Wrist." + side), ("Wrist." + side, "Palm." + side),
    ]
    for name in ("Index", "Middle", "Ring", "Pinky"):
        SKIN_EDGES += [("Palm." + side, "%s1.%s" % (name, side))]
        SKIN_EDGES += [("%s%d.%s" % (name, i, side), "%s%d.%s" % (name, i + 1, side)) for i in range(1, 4)]
    SKIN_EDGES += [("Wrist." + side, "Thumb1." + side)]
    SKIN_EDGES += [("Thumb%d.%s" % (i, side), "Thumb%d.%s" % (i + 1, side)) for i in range(1, 4)]

TORSO_EDGES = [e for e in SKIN_EDGES if all(not any(n.startswith(p) for p in (
    "Knee", "Shin", "Cuff", "Ankle", "Heel", "Ball", "Toe", "UpperMid", "Elbow", "Fore", "Wrist", "Palm",
    "Thumb", "Index", "Middle", "Ring", "Pinky")) for n in e)]
