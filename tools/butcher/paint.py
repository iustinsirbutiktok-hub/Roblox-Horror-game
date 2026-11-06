# The Butcher's paint masks: per-vertex colours the shaders read to know
# where things are (the shirt, the trousers, the rot, the blood, the
# handprints on the apron...). Computed with numpy on the high-res parts.
import math
import numpy as np
import skeleton as S
import vec as N
import body as B
import head as Hd
import clothes as C
import cleaver as Cl


def write(obj, name, rgba):
    me = obj.data
    a = me.color_attributes.get(name) or me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    a.data.foreach_set("color", np.clip(rgba, 0, 1).astype(np.float32).ravel())


def body(obj):
    P = N.get_co(obj.data)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    reg = B.regions(P)
    shirt, trousers, bare = (reg == 0) * 1.0, (reg == 1) * 1.0, (reg == 2) * 1.0
    blood = np.zeros(len(P))
    for side, k in (("L", 0.75), ("R", 1.0)):
        h = S.HANDS[side]
        along = (P - N.V3(h["wrist"])) @ N.V3(h["fwd"])
        near = np.linalg.norm(P - N.V3(h["wrist"]), axis=1) < 1.5
        blood = np.maximum(blood, near * N.sstep(-0.9, 0.5, along) * k)
    # up the sleeves, down the front of the neck, spattered on the shins
    blood = np.maximum(blood, 0.45 * shirt * N.sstep(5.2, 3.8, z) * (np.abs(x) > 0.75))
    blood = np.maximum(blood, 0.5 * bare * N.sstep(6.7, 7.0, z) * (y < 0))
    blood = np.maximum(blood, 0.5 * trousers * N.sstep(2.0, 0.6, z))
    write(obj, "mask", np.stack([shirt, trousers, blood, bare], axis=1))


def head(obj):
    P = N.get_co(obj.data)
    inv = np.array(S.HEAD_M.inverted())
    Q = P @ inv[:3, :3].T + inv[:3, 3]                       # back to design space
    x, y, z = Q[:, 0], Q[:, 1], Q[:, 2]
    c = np.array(Hd.HC)
    phi = Hd.phi_of(x, y)
    front = (y < c[1] - 0.1) * 1.0
    rot = N.sstep(0.15, 0.55, N.fbm(Q * 4, 3, 11))
    mouthrot = np.exp(-((phi / 0.9) ** 2 + ((z - Hd.MOUTH_Z) / 0.16) ** 2))
    rot = np.maximum(rot, mouthrot)
    h = Hd.mouth_h(phi)
    zc = Hd.mouth_z(phi)
    dz = np.abs(z - zc)
    mouth = (h > 0) * N.sstep(h + 0.004, h * 0.4, dz) * (y < c[1] + 0.1)
    raw = (h > 0) * N.sstep(h + 0.045, h + 0.008, dz) * (1 - mouth) * (y < c[1] + 0.1)
    socket = np.zeros(len(Q))
    for s in (1, -1):
        r2 = ((x - s * 0.13) / 0.12) ** 2 + ((z - (c[2] + 0.05)) / 0.095) ** 2
        socket = np.maximum(socket, front * N.sstep(1.5, 0.4, r2))
    # blood: run down from the mouth over the chin and the neck, from the rotted nose, tears of it
    run = 0.5 + 0.5 * np.sin(phi * 9 + 1.3)
    blood = (np.abs(phi) < 1.1) * (z < zc) * N.sstep(zc - 0.4 * run, zc, z) * 0.9
    # (from the rotted side of the nose: a dark trickle down to the mouth, not a red ball)
    blood = np.maximum(blood, 0.55 * front * np.exp(-((x - 0.04) / 0.018) ** 2) * N.sstep(c[2] - 0.08, c[2] - 0.2, z) *
                       (z > zc))
    for s in (1, -1):
        tear = front * np.exp(-((x - s * 0.13) / 0.02) ** 2) * N.sstep(c[2] + 0.02, c[2] - 0.2, z) * (z < c[2])
        blood = np.maximum(blood, tear * 0.9)
    stubble = front * N.sstep(c[2] - 0.02, c[2] - 0.12, z) * N.sstep(c[2] - 0.75, c[2] - 0.55, z) * \
        (np.abs(phi) < 1.6) * (1 - mouth) * (1 - raw)
    write(obj, "mask", np.stack([rot, blood, mouth, socket], axis=1))
    write(obj, "mask2", np.stack([stubble, raw, np.zeros(len(Q)), np.ones(len(Q))], axis=1))


HANDPRINTS = [  # (across the apron (studs of arc), height, turn (deg), size)
    (-0.32, 4.15, 18, 1.35), (0.36, 3.35, -22, 1.4), (-0.06, 5.45, 6, 1.25), (0.62, 2.55, -38, 1.35),
    (-0.58, 2.9, 30, 1.3),
]


def _capsule(px, pz, ax, az, bx, bz, r):
    abx, abz = bx - ax, bz - az
    t = np.clip(((px - ax) * abx + (pz - az) * abz) / (abx * abx + abz * abz), 0, 1)
    return np.hypot(px - (ax + abx * t), pz - (az + abz * t)) < r


def handprint(u, z, cu, cz, turn, size):
    """a hand pressed flat (fingers up) and dragged down a little"""
    a = math.radians(turn)
    du, dz = (u - cu) / size, (z - cz) / size
    t = du * math.cos(a) + dz * math.sin(a)               # across the palm
    s = -du * math.sin(a) + dz * math.cos(a)              # along the fingers
    m = ((t / 0.085) ** 2 + (s / 0.1) ** 2) < 1
    for ft, ln in ((-0.06, 0.12), (-0.02, 0.14), (0.02, 0.13), (0.06, 0.1)):
        m |= _capsule(t, s, ft, 0.07, ft * 1.25, 0.07 + ln, 0.021)
    m |= _capsule(t, s, 0.075, -0.02, 0.14, 0.05, 0.024)
    # smeared downwards, fading
    smear = (np.abs(t) < 0.08) & (s < 0) & (s > -0.35) & (np.sin(t * 90) > -0.3)
    return np.maximum(m * 1.0, smear * (1 + s / 0.35) * 0.7)


def apron(obj):
    P = N.get_co(obj.data)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    a = np.arctan2(x, -(y - 0.03))
    rr = np.hypot(x, y - 0.03)
    u = a * rr
    grime = N.sstep(2.4, 1.3, z) * 0.8
    # soaked at the front, where it's wiped its hands and leaned over the block
    blood = np.exp(-(u / 0.55) ** 2) * N.sstep(2.2, 3.4, z) * 0.75 + N.sstep(2.0, 1.3, z) * 0.4
    hands = np.zeros(len(P))
    for cu, cz, turn, size in HANDPRINTS:
        hands = np.maximum(hands, handprint(u, z, cu, cz, turn, size) * (np.abs(a) < 2.4))
    write(obj, "mask", np.stack([grime, blood, hands, np.ones(len(P))], axis=1))


def cleaver(obj):
    P = N.get_co(obj.data)
    o, g, w, n = Cl.frame()
    rel = P - N.V3(o)
    along = rel @ N.V3(g)
    across = rel @ N.V3(w)
    edge = N.sstep(0.1, Cl.HEIGHT, across) * (along > 0.27) * 0.85 + N.sstep(0.6, 1.1, along) * 0.3
    wood = (along < 0.22) * 1.0
    metal = ((along >= 0.2) & (along <= 0.29)) * 1.0
    for t in (0.12, -0.02, -0.16):
        metal = np.maximum(metal, (np.linalg.norm(P - N.V3(o + g * t + w * 0.02), axis=1) < 0.014) * 1.0)
    wood = wood * (1 - metal)
    write(obj, "mask", np.stack([edge, wood, metal, np.ones(len(P))], axis=1))
