# numpy helpers for shaping big meshes fast: read/write vertex positions,
# a smooth 3D value noise, distances to bone segments.
import numpy as np


def get_co(me):
    a = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def set_co(me, a):
    me.vertices.foreach_set("co", np.ascontiguousarray(a, dtype=np.float64).ravel())
    me.update()


def get_normals(me):
    a = np.empty(len(me.vertices) * 3)
    me.vertex_normals.foreach_get("vector", a)
    return a.reshape(-1, 3)


def _hash(ix, iy, iz, seed):
    n = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    n = n & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177
    n = n & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return (n & 0xFFFF) / 32767.5 - 1.0


def noise(P, seed=0):
    """smooth value noise, about -1..1, for points P (N, 3)"""
    P = np.asarray(P, dtype=np.float64)
    Pi = np.floor(P).astype(np.int64)
    f = P - Pi
    u = f * f * (3 - 2 * f)
    x, y, z = Pi[:, 0], Pi[:, 1], Pi[:, 2]
    out = 0.0
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1 - u[:, 2]
                out = out + _hash(x + dx, y + dy, z + dz, seed) * wx * wy * wz
    return out


def fbm(P, octaves=4, seed=0, gain=0.5):
    total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
    for o in range(octaves):
        total = total + noise(P * freq, seed + o * 17) * amp
        norm += amp
        amp *= gain
        freq *= 2.03
    return total / norm


def segdist(P, a, b):
    """distance from each point to the segment a-b, and how far along it (0..1)"""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
    d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
    return d, t


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def V3(v):
    return np.array([v[0], v[1], v[2]], dtype=np.float64)
