"""Low-poly mesh primitives used by the VX character/prop generator.

All primitives are authored in world space (Y up, character faces +Z),
then at export time each triangle is attributed to a joint. Coordinates
are plain tuples of floats to keep the pipeline dependency-free.
"""
from __future__ import annotations

import math
from collections import defaultdict

# --------------------------------------------------------------------------
# tiny vector helpers
# --------------------------------------------------------------------------

def vadd(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def vsub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def vmul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def vdot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def vcross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])
def vlen(a): return math.sqrt(vdot(a, a))
def vnorm(a):
    l = vlen(a)
    return (0.0, 0.0, 0.0) if l < 1e-12 else (a[0] / l, a[1] / l, a[2] / l)


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return ((1, 0, 0), (0, c, -s), (0, s, c))

def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, 0, s), (0, 1, 0), (-s, 0, c))

def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, -s, 0), (s, c, 0), (0, 0, 1))

def mat_mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))

def mat_apply(m, p):
    return (m[0][0] * p[0] + m[0][1] * p[1] + m[0][2] * p[2],
            m[1][0] * p[0] + m[1][1] * p[1] + m[1][2] * p[2],
            m[2][0] * p[0] + m[2][1] * p[1] + m[2][2] * p[2])

def euler_matrix(rot):
    rx, ry, rz = rot
    return mat_mul(rot_z(rz), mat_mul(rot_y(ry), rot_x(rx)))

def transform(p, rot=(0.0, 0.0, 0.0), center=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0)):
    m = euler_matrix(rot)
    q = (p[0] * scale[0], p[1] * scale[1], p[2] * scale[2])
    q = mat_apply(m, q)
    return vadd(q, center)


def basis_from_y(direction):
    """Return a rotation matrix whose +Y maps to the given direction."""
    d = vnorm(direction)
    if vlen(d) < 1e-9:
        return euler_matrix((0, 0, 0))
    up = (0.0, 1.0, 0.0)
    if abs(vdot(d, up)) > 0.9999:
        if vdot(d, up) > 0:
            return euler_matrix((0, 0, 0))
        return euler_matrix((math.pi, 0, 0))
    x = vnorm(vcross(up, d))
    z = vcross(d, x)
    # columns are the images of local x/y/z
    return ((x[0], d[0], z[0]),
            (x[1], d[1], z[1]),
            (x[2], d[2], z[2]))


# --------------------------------------------------------------------------
# builder
# --------------------------------------------------------------------------

class Builder:
    """Collects flat-shaded triangles grouped by joint/part name."""

    def __init__(self, materials):
        self.materials = materials          # name -> (r, g, b, emissive)
        self.tris = defaultdict(list)       # part -> [(color_name, p0, p1, p2)]
        self.bounds_min = (1e9, 1e9, 1e9)
        self.bounds_max = (-1e9, -1e9, -1e9)

    # -- low level ---------------------------------------------------------
    def _grow(self, p):
        self.bounds_min = tuple(min(a, b) for a, b in zip(self.bounds_min, p))
        self.bounds_max = tuple(max(a, b) for a, b in zip(self.bounds_max, p))

    def tri(self, part, color, p0, p1, p2, n_hint=None):
        n = vcross(vsub(p1, p0), vsub(p2, p0))
        if vlen(n) < 1e-10:
            return
        if n_hint is not None and vdot(n, n_hint) < 0.0:
            p1, p2 = p2, p1
        self.tris[part].append((color, p0, p1, p2))
        for p in (p0, p1, p2):
            self._grow(p)

    def quad(self, part, color, p0, p1, p2, p3, n_hint=None):
        self.tri(part, color, p0, p1, p2, n_hint)
        self.tri(part, color, p0, p2, p3, n_hint)

    # -- convex primitives -------------------------------------------------
    def taper_box(self, part, color, center, height, bottom, top, rot=(0.0, 0.0, 0.0)):
        """Box with different bottom/top footprints, centered on center."""
        bx, bz = bottom
        tx, tz = top
        hb, ht = -height * 0.5, height * 0.5
        local = [(-bx, hb, -bz), (bx, hb, -bz), (bx, hb, bz), (-bx, hb, bz),
                 (-tx, ht, -tz), (tx, ht, -tz), (tx, ht, tz), (-tx, ht, tz)]
        pts = [transform(p, rot, center) for p in local]
        def hint(a, b, c):
            fc = vmul(vadd(vadd(a, b), c), 1.0 / 3.0)
            return vsub(fc, center)
        for idx in ((0, 1, 2, 3), (4, 5, 6, 7)):
            a, b, c, d = (pts[i] for i in idx)
            self.quad(part, color, a, b, c, d, hint(a, b, c))
        for a, b, c, d in ((0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            pa, pb, pc, pd = (pts[i] for i in (a, b, c, d))
            self.quad(part, color, pa, pb, pc, pd, hint(pa, pb, pc))

    def box(self, part, color, center, size, rot=(0.0, 0.0, 0.0)):
        sx, sy, sz = size
        self.taper_box(part, color, center, sy, (sx * 0.5, sz * 0.5), (sx * 0.5, sz * 0.5), rot)

    def frustum(self, part, color, center, r0, r1, height, sides=8,
                rot=(0.0, 0.0, 0.0), cap_bottom=True, cap_top=True):
        """Cylinder/cone along local Y (r0 at bottom, r1 at top)."""
        hb, ht = -height * 0.5, height * 0.5
        ring0, ring1 = [], []
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            ring0.append(transform((r0 * math.sin(a), hb, r0 * math.cos(a)), rot, center))
            ring1.append(transform((r1 * math.sin(a), ht, r1 * math.cos(a)), rot, center))
        def hint(a, b, c):
            fc = vmul(vadd(vadd(a, b), c), 1.0 / 3.0)
            return vsub(fc, center)
        for i in range(sides):
            j = (i + 1) % sides
            a, b = ring0[i], ring0[j]
            c, d = ring1[j], ring1[i]
            if r1 <= 1e-7:
                self.tri(part, color, a, b, ring1[i], hint(a, b, ring1[i]))
            else:
                self.quad(part, color, a, b, c, d, hint(a, b, c))
        if cap_bottom and r0 > 1e-7:
            c = transform((0, hb, 0), rot, center)
            for i in range(sides):
                j = (i + 1) % sides
                self.tri(part, color, c, ring0[j], ring0[i], (0, -1, 0))
        if cap_top and r1 > 1e-7:
            c = transform((0, ht, 0), rot, center)
            for i in range(sides):
                j = (i + 1) % sides
                self.tri(part, color, c, ring1[i], ring1[j], (0, 1, 0))

    def cone(self, part, color, center, r, height, sides=8, rot=(0.0, 0.0, 0.0), cap=True):
        self.frustum(part, color, center, r, 0.0, height, sides, rot, cap_bottom=cap, cap_top=False)

    def sphere(self, part, color, center, radius, seg=10, rings=5, squash=(1.0, 1.0, 1.0)):
        pts = []
        for r in range(rings + 1):
            phi = math.pi * r / rings
            y = math.cos(phi) * radius * squash[1]
            rr = math.sin(phi) * radius
            row = []
            for i in range(seg):
                a = 2.0 * math.pi * i / seg
                row.append((center[0] + rr * math.sin(a) * squash[0],
                            center[1] + y,
                            center[2] + rr * math.cos(a) * squash[2]))
            pts.append(row)
        def hint(a, b, c):
            fc = vmul(vadd(vadd(a, b), c), 1.0 / 3.0)
            return vsub(fc, center)
        for r in range(rings):
            for i in range(seg):
                j = (i + 1) % seg
                a, b = pts[r][i], pts[r][j]
                c, d = pts[r + 1][j], pts[r + 1][i]
                if r == 0:
                    self.tri(part, color, a, c, d, hint(a, c, d))
                elif r == rings - 1:
                    self.tri(part, color, a, b, c, hint(a, b, c))
                else:
                    self.quad(part, color, a, b, c, d, hint(a, b, c))

    def cylinder_between(self, part, color, p0, p1, r0, r1, sides=6, cap=True):
        d = vsub(p1, p0)
        length = vlen(d)
        if length < 1e-7:
            return
        rot = basis_from_y(d)
        center = vmul(vadd(p0, p1), 0.5)
        hb, ht = -length * 0.5, length * 0.5
        ring0, ring1 = [], []
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            ring0.append(vadd(mat_apply(rot, (r0 * math.sin(a), hb, r0 * math.cos(a))), center))
            ring1.append(vadd(mat_apply(rot, (r1 * math.sin(a), ht, r1 * math.cos(a))), center))
        def hint(a, b, c):
            fc = vmul(vadd(vadd(a, b), c), 1.0 / 3.0)
            return vsub(fc, center)
        for i in range(sides):
            j = (i + 1) % sides
            a, b = ring0[i], ring0[j]
            c, d = ring1[j], ring1[i]
            if r1 <= 1e-7:
                self.tri(part, color, a, b, ring1[i], hint(a, b, ring1[i]))
            else:
                self.quad(part, color, a, b, c, d, hint(a, b, c))
        if cap:
            c0 = vadd(mat_apply(rot, (0, hb, 0)), center)
            c1 = vadd(mat_apply(rot, (0, ht, 0)), center)
            down = vmul(mat_apply(rot, (0, -1, 0)), 1.0)
            up = vmul(down, -1.0)
            for i in range(sides):
                j = (i + 1) % sides
                self.tri(part, color, c0, ring0[j], ring0[i], down)
                if r1 > 1e-7:
                    self.tri(part, color, c1, ring1[i], ring1[j], up)

    def annulus(self, part, color, center, r_in, r_out, height, sides=12, rot=(0.0, 0.0, 0.0)):
        """Flat ring (torus with square cross-section) around local Y."""
        hb, ht = -height * 0.5, height * 0.5
        rows = []
        for radius, y in ((r_in, hb), (r_out, hb), (r_out, ht), (r_in, ht)):
            row = []
            for i in range(sides):
                a = 2.0 * math.pi * i / sides
                row.append(transform((radius * math.sin(a), y, radius * math.cos(a)), rot, center))
            rows.append(row)
        for i in range(sides):
            j = (i + 1) % sides
            a = 2.0 * math.pi * (i + 0.5) / sides
            radial = mat_apply(euler_matrix(rot), (math.sin(a), 0.0, math.cos(a)))
            self.quad(part, color, rows[3][i], rows[2][i], rows[2][j], rows[3][j], (0, 1, 0))
            self.quad(part, color, rows[0][i], rows[1][i], rows[1][j], rows[0][j], (0, -1, 0))
            self.quad(part, color, rows[1][i], rows[1][j], rows[2][j], rows[2][i], radial)
            self.quad(part, color, rows[0][j], rows[0][i], rows[3][i], rows[3][j], vmul(radial, -1.0))

    def octahedron(self, part, color, center, radius, squash=(1.0, 1.0, 1.0)):
        top = (center[0], center[1] + radius * squash[1], center[2])
        bottom = (center[0], center[1] - radius * squash[1], center[2])
        mid = []
        for i in range(4):
            a = 2.0 * math.pi * i / 4
            mid.append((center[0] + radius * math.sin(a) * squash[0],
                        center[1],
                        center[2] + radius * math.cos(a) * squash[2]))
        for i in range(4):
            j = (i + 1) % 4
            self.tri(part, color, top, mid[i], mid[j], (0, 1, 0))
            self.tri(part, color, bottom, mid[j], mid[i], (0, -1, 0))


def compute_joint_world(joints):
    """joints: list of (name, parent|None, rest_offset). Returns name -> world pivot."""
    world = {}
    for name, parent, rest in joints:
        base = world[parent] if parent is not None else (0.0, 0.0, 0.0)
        world[name] = vadd(base, rest)
    return world
