//! Small right-handed 3D math library (Y up, -Z forward for the camera).
const std = @import("std");

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }
    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub fn scale(a: Vec2, s: f32) Vec2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }
    pub fn length(a: Vec2) f32 {
        return @sqrt(a.x * a.x + a.y * a.y);
    }
};

pub const Vec3 = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub const zero = Vec3{};
    pub const up = Vec3{ .y = 1 };

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }
    pub fn splat(v: f32) Vec3 {
        return .{ .x = v, .y = v, .z = v };
    }
    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    pub fn mul(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
    }
    pub fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    pub fn neg(a: Vec3) Vec3 {
        return .{ .x = -a.x, .y = -a.y, .z = -a.z };
    }
    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }
    pub fn lengthSquared(a: Vec3) f32 {
        return a.dot(a);
    }
    pub fn length(a: Vec3) f32 {
        return @sqrt(a.dot(a));
    }
    pub fn normalize(a: Vec3) Vec3 {
        const l = a.length();
        if (l < 1e-8) return Vec3.zero;
        return a.scale(1.0 / l);
    }
    pub fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
        return a.add(b.sub(a).scale(t));
    }
    pub fn distance(a: Vec3, b: Vec3) f32 {
        return a.sub(b).length();
    }
    pub fn min(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = @min(a.x, b.x), .y = @min(a.y, b.y), .z = @min(a.z, b.z) };
    }
    pub fn max(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = @max(a.x, b.x), .y = @max(a.y, b.y), .z = @max(a.z, b.z) };
    }
};

pub const Vec4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn init(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }
};

/// Column-major 4x4 matrix. m[col * 4 + row].
pub const Mat4 = struct {
    m: [16]f32,

    pub const identity = Mat4{
        .m = .{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        },
    };

    pub fn translation(v: Vec3) Mat4 {
        var r = Mat4.identity;
        r.m[12] = v.x;
        r.m[13] = v.y;
        r.m[14] = v.z;
        return r;
    }

    pub fn scale(v: Vec3) Mat4 {
        var r = Mat4.identity;
        r.m[0] = v.x;
        r.m[5] = v.y;
        r.m[10] = v.z;
        return r;
    }

    pub fn rotationX(a: f32) Mat4 {
        const c = @cos(a);
        const s = @sin(a);
        var r = Mat4.identity;
        r.m[5] = c;
        r.m[6] = s;
        r.m[9] = -s;
        r.m[10] = c;
        return r;
    }

    pub fn rotationY(a: f32) Mat4 {
        const c = @cos(a);
        const s = @sin(a);
        var r = Mat4.identity;
        r.m[0] = c;
        r.m[2] = -s;
        r.m[8] = s;
        r.m[10] = c;
        return r;
    }

    pub fn rotationZ(a: f32) Mat4 {
        const c = @cos(a);
        const s = @sin(a);
        var r = Mat4.identity;
        r.m[0] = c;
        r.m[1] = s;
        r.m[4] = -s;
        r.m[5] = c;
        return r;
    }

    /// Translation * RotationY * RotationX * RotationZ * Scale.
    pub fn compose(pos: Vec3, yaw: f32, pitch: f32, roll: f32, s: f32) Mat4 {
        const t = Mat4.translation(pos);
        const ry = Mat4.rotationY(yaw);
        const rx = Mat4.rotationX(pitch);
        const rz = Mat4.rotationZ(roll);
        const sc = Mat4.scale(Vec3.splat(s));
        return t.mul(ry).mul(rx).mul(rz).mul(sc);
    }

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = undefined;
        var col: usize = 0;
        while (col < 4) : (col += 1) {
            var row: usize = 0;
            while (row < 4) : (row += 1) {
                var sum: f32 = 0;
                var k: usize = 0;
                while (k < 4) : (k += 1) {
                    sum += a.m[k * 4 + row] * b.m[col * 4 + k];
                }
                r.m[col * 4 + row] = sum;
            }
        }
        return r;
    }

    pub fn transformVec4(a: Mat4, v: Vec4) Vec4 {
        return .{
            .x = a.m[0] * v.x + a.m[4] * v.y + a.m[8] * v.z + a.m[12] * v.w,
            .y = a.m[1] * v.x + a.m[5] * v.y + a.m[9] * v.z + a.m[13] * v.w,
            .z = a.m[2] * v.x + a.m[6] * v.y + a.m[10] * v.z + a.m[14] * v.w,
            .w = a.m[3] * v.x + a.m[7] * v.y + a.m[11] * v.z + a.m[15] * v.w,
        };
    }

    pub fn transformPoint(a: Mat4, p: Vec3) Vec4 {
        return a.transformVec4(.{ .x = p.x, .y = p.y, .z = p.z, .w = 1 });
    }

    pub fn transformDirection(a: Mat4, d: Vec3) Vec3 {
        const r = a.transformVec4(.{ .x = d.x, .y = d.y, .z = d.z, .w = 0 });
        return .{ .x = r.x, .y = r.y, .z = r.z };
    }

    pub fn mulPoint(a: Mat4, p: Vec3) Vec3 {
        const r = a.transformPoint(p);
        return .{ .x = r.x, .y = r.y, .z = r.z };
    }

    /// Right-handed look-at view matrix.
    pub fn lookAt(eye: Vec3, target: Vec3, up: Vec3) Mat4 {
        const f = target.sub(eye).normalize();
        const s = f.cross(up).normalize();
        const u = s.cross(f);
        var r = Mat4.identity;
        r.m[0] = s.x;
        r.m[4] = s.y;
        r.m[8] = s.z;
        r.m[12] = -s.dot(eye);
        r.m[1] = u.x;
        r.m[5] = u.y;
        r.m[9] = u.z;
        r.m[13] = -u.dot(eye);
        r.m[2] = -f.x;
        r.m[6] = -f.y;
        r.m[10] = -f.z;
        r.m[14] = f.dot(eye);
        return r;
    }

    /// Right-handed perspective projection with clip-space z in [-w, w].
    pub fn perspective(fov_y: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1.0 / @tan(fov_y * 0.5);
        var r = Mat4.identity;
        r.m[0] = f / aspect;
        r.m[5] = f;
        r.m[10] = (far + near) / (near - far);
        r.m[11] = -1.0;
        r.m[14] = (2.0 * far * near) / (near - far);
        r.m[15] = 0.0;
        return r;
    }
};

/// Orbit camera used by the fixed-pitch rotatable third-person view.
pub const OrbitCamera = struct {
    target: Vec3 = Vec3.init(0, 0.55, 0),
    yaw: f32 = -0.30,
    pitch: f32 = 0.98,
    distance: f32 = 7.6,
    fov: f32 = 0.76,
    near: f32 = 0.08,
    far: f32 = 70,

    pub fn eye(self: OrbitCamera) Vec3 {
        const cp = @cos(self.pitch);
        const dir = Vec3.init(@sin(self.yaw) * cp, @sin(self.pitch), @cos(self.yaw) * cp);
        return self.target.add(dir.scale(self.distance));
    }

    pub fn view(self: OrbitCamera) Mat4 {
        return Mat4.lookAt(self.eye(), self.target, Vec3.up);
    }

    pub fn projection(self: OrbitCamera, aspect: f32) Mat4 {
        return Mat4.perspective(self.fov, aspect, self.near, self.far);
    }

    pub const Projected = struct {
        x: f32,
        y: f32,
        inv_z: f32,
        depth: f32,
    };

    pub fn project(self: OrbitCamera, world: Vec3, width: u32, height: u32) ?Projected {
        const view_mat = self.view();
        const p = view_mat.transformPoint(world);
        const w = -p.z;
        if (w <= self.near) return null;
        const f = 1.0 / @tan(self.fov * 0.5);
        const aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
        const ndc_x = (f / aspect) * p.x / w;
        const ndc_y = f * p.y / w;
        return .{
            .x = (ndc_x * 0.5 + 0.5) * @as(f32, @floatFromInt(width)),
            .y = (0.5 - ndc_y * 0.5) * @as(f32, @floatFromInt(height)),
            .inv_z = 1.0 / w,
            .depth = w,
        };
    }

    /// Screen pixel -> point on the ground plane (y=0). Used by mouse aiming.
    /// Returns null when the ray is parallel to the plane or points away.
    pub fn pickGround(self: OrbitCamera, sx: f32, sy: f32, width: u32, height: u32) ?Vec3 {
        if (width == 0 or height == 0) return null;
        const eye_pos = self.eye();
        const forward = self.target.sub(eye_pos).normalize();
        const right = forward.cross(Vec3.up).normalize();
        const up = right.cross(forward);
        const aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
        const ndc_x = (sx / @as(f32, @floatFromInt(width))) * 2.0 - 1.0;
        const ndc_y = 1.0 - (sy / @as(f32, @floatFromInt(height))) * 2.0;
        const tan_half = @tan(self.fov * 0.5);
        const dir = forward
            .add(right.scale(ndc_x * tan_half * aspect))
            .add(up.scale(ndc_y * tan_half))
            .normalize();
        if (@abs(dir.y) < 1e-5) return null;
        const t = -eye_pos.y / dir.y;
        if (t <= 0) return null;
        return eye_pos.add(dir.scale(t));
    }
};

pub fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

pub fn wrapAngle(a: f32) f32 {
    var r = a;
    while (r > std.math.pi) r -= 2.0 * std.math.pi;
    while (r < -std.math.pi) r += 2.0 * std.math.pi;
    return r;
}

pub fn lerpAngle(a: f32, b: f32, t: f32) f32 {
    return wrapAngle(a + wrapAngle(b - a) * t);
}

test "matrix identity" {
    const p = Vec3.init(1, 2, 3);
    const q = Mat4.identity.mulPoint(p);
    try std.testing.expectApproxEqAbs(p.x, q.x, 1e-6);
    try std.testing.expectApproxEqAbs(p.y, q.y, 1e-6);
    try std.testing.expectApproxEqAbs(p.z, q.z, 1e-6);
}

test "translation then rotation" {
    const m = Mat4.translation(Vec3.init(0, 1, 0)).mul(Mat4.rotationY(std.math.pi * 0.5));
    const p = m.mulPoint(Vec3.init(0, 0, -1));
    try std.testing.expectApproxEqAbs(p.x, -1, 1e-5);
    try std.testing.expectApproxEqAbs(p.y, 1, 1e-5);
    try std.testing.expectApproxEqAbs(p.z, 0, 1e-5);
}

test "camera looks at target" {
    const cam = OrbitCamera{ .target = Vec3.init(0, 0.5, 0), .yaw = 0, .pitch = 0.6, .distance = 5 };
    const view = cam.view();
    const p = view.transformPoint(cam.target);
    try std.testing.expectApproxEqAbs(p.x, 0, 1e-5);
    try std.testing.expectApproxEqAbs(p.y, 0, 1e-5);
    try std.testing.expectApproxEqAbs(p.z, -5, 1e-5);
}

test "camera ground pick roundtrips a projected point" {
    const cam = OrbitCamera{ .target = Vec3.init(0, 0.55, 0), .yaw = 0, .pitch = 0.9, .distance = 10 };
    const world = Vec3.init(0.4, 0, -0.7);
    const s = cam.project(world, 480, 270) orelse return error.SkipZigTest;
    const picked = cam.pickGround(s.x, s.y, 480, 270) orelse return error.SkipZigTest;
    try std.testing.expectApproxEqAbs(world.x, picked.x, 0.02);
    try std.testing.expectApproxEqAbs(world.z, picked.z, 0.02);
}
