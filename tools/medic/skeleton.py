# The Medic's skeleton: joint positions (Blender units = Roblox studs, Z up,
# facing -Y), bone chain, and body radii for the skin.
import math
from mathutils import Vector as V

H = 1.0  # global scale knob

def lerp(a, b, t):
    return a + (b - a) * t

J = {}      # joint name -> position
R = {}      # joint name -> (radius x, radius y) of the body there
BONES = []  # (bone, head joint, tail joint, parent bone)

def j(name, x, y, z, rx=None, ry=None):
    J[name] = V((x, y, z)) * H
    if rx is not None:
        R[name] = (rx * H, (ry if ry is not None else rx) * H)

# ---------------- legs (left = +X) ----------------
for s, side in ((1, "L"), (-1, "R")):
    j("Toe." + side, s * 0.40, -0.62, 0.06, 0.075, 0.05)
    j("Ball." + side, s * 0.38, -0.38, 0.09, 0.10, 0.06)
    j("Ankle." + side, s * 0.35, 0.02, 0.32, 0.06, 0.065)
    j("Heel." + side, s * 0.35, 0.16, 0.10, 0.07, 0.07)
    j("Knee." + side, s * 0.32, -0.06, 2.15, 0.11, 0.115)
    j("Shin." + side, s * 0.335, -0.02, 1.25, 0.072, 0.085)
    j("Thigh." + side, s * 0.35, 0.0, 3.15, 0.11, 0.12)
    j("Hip." + side, s * 0.34, 0.02, 3.92, 0.15, 0.16)

# ---------------- spine ----------------
j("Pelvis", 0, 0.02, 4.10, 0.30, 0.19)
j("Spine1", 0, 0.03, 4.55, 0.17, 0.13)    # pinched waist
j("Spine2", 0, 0.05, 5.00, 0.22, 0.17)
j("Spine3", 0, 0.06, 5.45, 0.34, 0.25)    # ribcage
j("Spine4", 0, 0.05, 5.85, 0.37, 0.25)
j("Spine5", 0, 0.03, 6.18, 0.36, 0.22)    # top of chest
j("Neck1", 0, 0.00, 6.50, 0.12, 0.12)
j("Neck2", 0, -0.04, 6.76, 0.095, 0.10)
j("Neck3", 0, -0.08, 6.98, 0.09, 0.095)
j("HeadBase", 0, -0.11, 7.12, 0.10, 0.10)
j("HeadTop", 0, -0.13, 7.95)
j("JawTip", 0, -0.66, 6.86)
j("JawHinge", 0, -0.1, 7.40)

# ---------------- arms: shoulder, upper arm, TWO forearms, hand ----------------
ARM_DOWN = math.radians(36)  # from vertical
HANDS = {}
for s, side in ((1, "L"), (-1, "R")):
    j("Clav." + side, s * 0.24, 0.0, 6.24, 0.11, 0.09)
    sh = V((s * 0.66, -0.02, 6.05))
    J["Shoulder." + side] = sh * H
    R["Shoulder." + side] = (0.12 * H, 0.12 * H)
    d = V((s * math.sin(ARM_DOWN), -0.06, -math.cos(ARM_DOWN))).normalized()
    e1 = sh + d * 1.45
    e2 = e1 + d * 1.0
    wr = e2 + d * 0.92
    J["Elbow1." + side], R["Elbow1." + side] = e1 * H, (0.095 * H, 0.10 * H)
    J["Elbow2." + side], R["Elbow2." + side] = e2 * H, (0.085 * H, 0.09 * H)
    J["Wrist." + side], R["Wrist." + side] = wr * H, (0.06 * H, 0.05 * H)
    J["UpperMid." + side], R["UpperMid." + side] = (sh + d * 0.7) * H, (0.095 * H, 0.10 * H)
    J["Fore1Mid." + side], R["Fore1Mid." + side] = (e1 + d * 0.5) * H, (0.075 * H, 0.075 * H)
    J["Fore2Mid." + side], R["Fore2Mid." + side] = (e2 + d * 0.46) * H, (0.07 * H, 0.06 * H)
    # hand: palm along the arm, flat, palm facing the thigh (+/-X inward)
    side_axis = V((0, 1, 0)).cross(d).normalized() * s   # across the palm (front/back)
    side_axis = V((0, -1, 0))                               # fingers spread front-to-back
    palm_end = wr + d * 0.55
    J["Palm." + side], R["Palm." + side] = palm_end * H, (0.035 * H, 0.11 * H)
    fingers = {}
    # index..pinky spread across the palm (front to back), long and thin
    names = ["Index", "Middle", "Ring", "Pinky"]
    offsets = [-0.105, -0.035, 0.035, 0.10]
    lengths = [(0.36, 0.29, 0.22), (0.40, 0.32, 0.24), (0.37, 0.30, 0.22), (0.30, 0.24, 0.19)]
    for name, off, ln in zip(names, offsets, lengths):
        base = palm_end + V((0, off, 0)) + d * 0.02
        fd = (d + V((0, off * 0.9, 0))).normalized()
        p1 = base + fd * ln[0]
        fd2 = (fd + V((0, 0, -0.08))).normalized()
        p2 = p1 + fd2 * ln[1]
        p3 = p2 + (fd2 + V((0, 0, -0.08))).normalized() * ln[2]
        fingers[name] = [base, p1, p2, p3]
    # thumb: from the side of the palm, pointing forward-down
    tb = wr + d * 0.18 + V((0, -0.09, 0))
    td = (d * 0.6 + V((0, -0.8, 0))).normalized()
    t1 = tb + td * 0.24
    t2 = t1 + (td + d * 0.5).normalized() * 0.22
    t3 = t2 + (td + d * 0.9).normalized() * 0.17
    fingers["Thumb"] = [tb, t1, t2, t3]
    for name, pts in fingers.items():
        for i, p in enumerate(pts):
            J["%s%d.%s" % (name, i, side)] = p * H
    HANDS[side] = fingers

# finger radii
for side in ("L", "R"):
    for name in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        rr = [0.042, 0.036, 0.031, 0.022] if name != "Thumb" else [0.05, 0.042, 0.034, 0.024]
        for i in range(4):
            R["%s%d.%s" % (name, i, side)] = (rr[i] * H, rr[i] * H)

# ---------------- bones ----------------
def b(name, head, tail, parent):
    BONES.append((name, head, tail, parent))

b("Root", "Pelvis", "Spine1", None)
b("Spine1", "Spine1", "Spine2", "Root")
b("Spine2", "Spine2", "Spine3", "Spine1")
b("Spine3", "Spine3", "Spine4", "Spine2")
b("Spine4", "Spine4", "Spine5", "Spine3")
b("Spine5", "Spine5", "Neck1", "Spine4")
b("Neck1", "Neck1", "Neck2", "Spine5")
b("Neck2", "Neck2", "Neck3", "Neck1")
b("Neck3", "Neck3", "HeadBase", "Neck2")
b("Head", "HeadBase", "HeadTop", "Neck3")
b("Jaw", "JawHinge", "JawTip", "Head")
for side in ("L", "R"):
    b("Thigh." + side, "Hip." + side, "Knee." + side, "Root")
    b("Shin." + side, "Knee." + side, "Ankle." + side, "Thigh." + side)
    b("Foot." + side, "Ankle." + side, "Ball." + side, "Shin." + side)
    b("Toe." + side, "Ball." + side, "Toe." + side, "Foot." + side)
    b("Clavicle." + side, "Clav." + side, "Shoulder." + side, "Spine5")
    b("UpperArm." + side, "Shoulder." + side, "Elbow1." + side, "Clavicle." + side)
    b("Forearm1." + side, "Elbow1." + side, "Elbow2." + side, "UpperArm." + side)
    b("Forearm2." + side, "Elbow2." + side, "Wrist." + side, "Forearm1." + side)
    b("Hand." + side, "Wrist." + side, "Palm." + side, "Forearm2." + side)
    for name in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        for i in range(3):
            b("%s%d.%s" % (name, i + 1, side), "%s%d.%s" % (name, i, side), "%s%d.%s" % (name, i + 1, side),
              "Hand." + side if i == 0 else "%s%d.%s" % (name, i, side))

# ---------------- the body's skin graph (edges between joints) ----------------
SKIN_EDGES = [
    ("Pelvis", "Spine1"), ("Spine1", "Spine2"), ("Spine2", "Spine3"), ("Spine3", "Spine4"), ("Spine4", "Spine5"),
    ("Spine5", "Neck1"), ("Neck1", "Neck2"), ("Neck2", "Neck3"), ("Neck3", "HeadBase"),
]
for side in ("L", "R"):
    SKIN_EDGES += [
        ("Pelvis", "Hip." + side), ("Hip." + side, "Thigh." + side), ("Thigh." + side, "Knee." + side),
        ("Knee." + side, "Shin." + side), ("Shin." + side, "Ankle." + side),
        ("Ankle." + side, "Heel." + side), ("Ankle." + side, "Ball." + side), ("Ball." + side, "Toe." + side),
        ("Spine5", "Clav." + side), ("Clav." + side, "Shoulder." + side),
        ("Shoulder." + side, "UpperMid." + side), ("UpperMid." + side, "Elbow1." + side),
        ("Elbow1." + side, "Fore1Mid." + side), ("Fore1Mid." + side, "Elbow2." + side),
        ("Elbow2." + side, "Fore2Mid." + side), ("Fore2Mid." + side, "Wrist." + side),
        ("Wrist." + side, "Palm." + side),
    ]
    for name in ("Index", "Middle", "Ring", "Pinky"):
        SKIN_EDGES += [("Palm." + side, "%s0.%s" % (name, side))]
        SKIN_EDGES += [("%s%d.%s" % (name, i, side), "%s%d.%s" % (name, i + 1, side)) for i in range(3)]
    SKIN_EDGES += [("Wrist." + side, "Thumb0." + side)]
    SKIN_EDGES += [("Thumb%d.%s" % (i, side), "Thumb%d.%s" % (i + 1, side)) for i in range(3)]
