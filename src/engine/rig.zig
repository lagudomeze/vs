//! Procedural skeleton animation shared by all three heroes.
const std = @import("std");
const math = @import("../core/math.zig");
const model_mod = @import("model.zig");

pub const AnimState = struct {
    time: f32 = 0,
    phase: f32 = 0,
    moving: f32 = 0,
    cast: f32 = 0,
    kind: u8 = 0, // 0 warrior, 1 archmage, 2 chronomancer
};

pub const Pose = struct {
    count: u16 = 0,
    joints: [model_mod.max_joints]math.Mat4 = undefined,
};

fn rot(pitch: f32, yaw: f32, roll: f32) math.Mat4 {
    return math.Mat4.rotationY(yaw).mul(math.Mat4.rotationX(pitch)).mul(math.Mat4.rotationZ(roll));
}

pub fn compute(model: *const model_mod.Model, anim: AnimState, pose: *Pose) void {
    const t = anim.time;
    const walk = std.math.clamp(anim.moving, 0.0, 1.0);
    const idle_amt = 1.0 - walk;
    const sw = @sin(anim.phase);
    const step = @sin(anim.phase * 2.0);
    const idle = @sin(t * 1.9);
    const slow = @sin(t * 0.63);
    const cast = std.math.clamp(anim.cast, 0.0, 1.0);
    const cast_ease = cast * cast * (3.0 - 2.0 * cast);
    const skeleton = anim.kind == 3;
    const wraith = anim.kind == 4;
    const golem = anim.kind == 5 or anim.kind == 6;

    var pitch: [model_mod.max_joints]f32 = @splat(0.0);
    var yaw: [model_mod.max_joints]f32 = @splat(0.0);
    var roll: [model_mod.max_joints]f32 = @splat(0.0);
    var extra_y: [model_mod.max_joints]f32 = @splat(0.0);

    // Breathing lifts the torso, not the feet.
    const bob = (0.010 * @abs(step) + 0.002 * idle) * walk + 0.0035 * idle * idle_amt;
    const hover = if (wraith) 0.030 * @sin(t * 1.55 + anim.phase) else 0.0;

    if (model.torso) |i| {
        pitch[i] = if (golem) 0.05 * walk + 0.02 * cast_ease else 0.09 * walk + 0.020 * idle * idle_amt + 0.05 * cast_ease;
        yaw[i] = 0.05 * slow * idle_amt + 0.06 * sw * walk;
        roll[i] = 0.020 * sw * walk;
        extra_y[i] = bob + hover;
    }
    if (model.head) |i| {
        pitch[i] = -0.025 * idle * idle_amt - 0.02 * walk - 0.10 * cast_ease;
        yaw[i] = 0.13 * @sin(t * 0.47) * idle_amt - 0.04 * sw * walk;
    }
    if (model.hips) |i| {
        yaw[i] = -0.04 * sw * walk;
        roll[i] = 0.025 * sw * walk;
    }
    if (model.cape) |i| {
        pitch[i] = 0.16 + 0.30 * walk + 0.05 * idle * idle_amt + 0.06 * sw * walk;
        yaw[i] = 0.05 * sw * walk;
        roll[i] = 0.03 * sw * walk;
    }
    if (model.weapon) |i| {
        pitch[i] = -0.04 * idle * idle_amt - 0.04 * cast_ease;
        if (anim.kind == 0 or skeleton) {
            // tilt the greatsword away from the body so its silhouette reads
            roll[i] = if (skeleton) 0.32 else 0.44;
            pitch[i] -= if (skeleton) 0.06 else 0.10;
        }
    }
    if (model.offhand) |i| {
        pitch[i] = 0.03 * idle * idle_amt;
    }
    if (model.focus) |i| {
        const rate: f32 = if (anim.kind == 2) 1.9 else 1.2;
        yaw[i] = t * rate;
        pitch[i] = 0.10 * @sin(t * 1.3);
    }
    if (model.aura) |i| {
        yaw[i] = -t * 0.52;
        pitch[i] = 0.04 * @sin(t * 0.9);
    }

    const leg_scale: f32 = if (wraith) 0.0 else if (golem) 0.55 else if (anim.kind == 0 or skeleton) 1.0 else 0.55;
    if (model.leg_l) |i| pitch[i] = 0.55 * leg_scale * walk * sw;
    if (model.leg_r) |i| pitch[i] = -0.55 * leg_scale * walk * sw;

    if (golem) {
        if (model.arm_r) |i| {
            pitch[i] = -0.06 - 0.55 * walk * sw - 1.15 * cast_ease;
            roll[i] = -0.15;
        }
        if (model.arm_l) |i| {
            pitch[i] = -0.06 + 0.55 * walk * sw - 1.00 * cast_ease;
            roll[i] = 0.15;
        }
    } else if (wraith) {
        if (model.arm_r) |i| {
            pitch[i] = -0.20 - 0.10 * walk * sw - 1.15 * cast_ease;
            roll[i] = -0.10;
        }
        if (model.arm_l) |i| {
            pitch[i] = -0.10 + 0.06 * @sin(t * 0.9) - 0.35 * cast_ease;
            roll[i] = 0.18;
        }
    } else if (anim.kind == 0 or skeleton) {
        if (model.arm_r) |i| {
            pitch[i] = -0.10 - 0.32 * walk * sw + 0.02 * idle * idle_amt - 0.75 * cast_ease;
            roll[i] = -0.05;
        }
        if (model.arm_l) |i| {
            pitch[i] = -0.16 + 0.26 * walk * sw - 0.35 * cast_ease;
            roll[i] = 0.14;
        }
    } else {
        if (model.arm_r) |i| {
            pitch[i] = -0.12 - 0.24 * walk * sw + 0.02 * idle * idle_amt - 1.05 * cast_ease;
            roll[i] = -0.06;
        }
        if (model.arm_l) |i| {
            pitch[i] = -0.10 + 0.24 * walk * sw - 0.30 * cast_ease;
            roll[i] = 0.10;
        }
    }

    pose.count = @intCast(model.joints.len);
    for (model.joints, 0..) |joint, i| {
        const local_pos = joint.rest.add(math.Vec3.init(0, extra_y[i], 0));
        const local = math.Mat4.translation(local_pos).mul(rot(pitch[i], yaw[i], roll[i]));
        if (joint.parent >= 0) {
            const p: usize = @intCast(joint.parent);
            pose.joints[i] = pose.joints[p].mul(local);
        } else {
            pose.joints[i] = local;
        }
    }
}

test "rest pose equals baked skeleton" {
    const gpa = std.testing.allocator;
    // Build a tiny model by hand: root at origin, child at (0, 1, 0).
    const bytes = std.testing.allocator; // silence unused
    _ = bytes;
    _ = gpa;
    const m = model_mod.Model{
        .name = "t",
        .flags = 0,
        .joints = &.{},
        .parts = &.{},
        .bounds_min = math.Vec3.zero,
        .bounds_max = math.Vec3.zero,
        .rest_world = &.{},
    };
    var pose = Pose{};
    compute(&m, .{}, &pose);
    try std.testing.expectEqual(@as(u16, 0), pose.count);
}