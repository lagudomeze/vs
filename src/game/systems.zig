//! ECS systems: movement, companion formation, animation/pose and light motes.
const std = @import("std");
const ecs = @import("zflecs");
const math = @import("../core/math.zig");
const comp = @import("components.zig");
const rig = @import("../engine/rig.zig");
const model_mod = @import("../engine/model.zig");

pub const Context = struct {
    dt: f32 = 0,
    time: f32 = 0,
    active: ecs.entity_t = 0,
    arena_limit: f32 = 5.6,
    models: *const model_mod.ModelDb = undefined,
};

pub var context: ?*Context = null;

pub fn setContext(ctx: *Context) void {
    context = ctx;
}

fn moveSystem(
    transforms: []comp.Transform,
    velocities: []comp.Velocity,
    intents: []const comp.MoveIntent,
    anims: []comp.Animation,
) void {
    const ctx = context orelse return;
    const dt = ctx.dt;
    if (dt <= 0) return;
    const blend = @min(1.0, 18.0 * dt);
    for (transforms, velocities, intents, anims) |*tr, *vel, intent, *anim| {
        const desired = intent.dir.scale(intent.speed);
        vel.v = vel.v.add(desired.sub(vel.v).scale(blend));
        tr.pos = tr.pos.add(vel.v.scale(dt));

        const horiz = math.Vec2.init(tr.pos.x, tr.pos.z);
        const dist = horiz.length();
        if (dist > ctx.arena_limit) {
            const factor = ctx.arena_limit / dist;
            tr.pos.x *= factor;
            tr.pos.z *= factor;
            vel.v.x *= 0.2;
            vel.v.z *= 0.2;
        }
        tr.pos.y = 0;

        const speed = math.Vec2.init(vel.v.x, vel.v.z).length();
        if (speed > 0.12 and intent.speed > 0.01) {
            const target = std.math.atan2(intent.dir.x, intent.dir.z);
            tr.yaw = math.lerpAngle(tr.yaw, target, @min(1.0, (1.0 - @exp(-11.0 * dt))));
        }

        const target_moving = std.math.clamp(speed / 3.2, 0.0, 1.0);
        anim.state.moving += (target_moving - anim.state.moving) * @min(1.0, 9.0 * dt);
        anim.state.phase += speed * 3.7 * dt;
    }
}

fn followSystem(
    it: *ecs.iter_t,
    transforms: []comp.Transform,
    follows: []const comp.Follow,
    intents: []comp.MoveIntent,
    heroes: []const comp.Hero,
) void {
    const dt = if (context) |c| c.dt else 0;
    _ = dt;
    for (transforms, follows, intents, heroes) |tr, follow, *intent, hero| {
        intent.speed = 0;
        intent.dir = math.Vec3.zero;
        const leader = ecs.get(it.world, follow.leader, comp.Transform) orelse continue;
        const s = @sin(leader.yaw);
        const c = @cos(leader.yaw);
        const ox = follow.offset.x * c + follow.offset.y * s;
        const oz = -follow.offset.x * s + follow.offset.y * c;
        const desired = math.Vec3.init(leader.pos.x + ox, 0, leader.pos.z + oz);
        const delta = desired.sub(tr.pos);
        const d = delta.length();
        if (d > 0.30) {
            intent.dir = delta.scale(1.0 / d);
            intent.speed = hero.move_speed * std.math.clamp(d / 1.1, 0.55, 1.35);
        }
    }
}

fn animSystem(
    anims: []comp.Animation,
    poses: []comp.Pose,
    renders: []const comp.Renderable,
) void {
    const ctx = context orelse return;
    for (anims, poses, renders) |*anim, *pose, render| {
        anim.state.time = ctx.time;
        anim.state.cast = @max(0.0, anim.state.cast - ctx.dt * 2.4);
        const m = ctx.models.at(render.model);
        rig.compute(m, anim.state, &pose.pose);
    }
}

fn gaugeSystem(heroes: []comp.Hero) void {
    const ctx = context orelse return;
    for (heroes) |*hero| {
        hero.ap = @min(hero.ap_max, hero.ap + hero.ap_speed * ctx.dt);
    }
}

fn moteSystem(
    it: *ecs.iter_t,
    transforms: []comp.Transform,
    motes: []const comp.Mote,
) void {
    const ctx = context orelse return;
    for (transforms, motes) |*tr, mote| {
        const center = ecs.get(it.world, mote.center, comp.Transform) orelse continue;
        const angle = mote.phase + ctx.time * mote.speed;
        tr.pos = math.Vec3.init(
            center.pos.x + @sin(angle) * mote.radius,
            mote.height + @sin(ctx.time * 1.7 + mote.phase) * 0.07,
            center.pos.z + @cos(angle) * mote.radius,
        );
        tr.yaw = ctx.time * mote.spin;
    }
}

fn spinSystem(transforms: []comp.Transform, spins: []const comp.Spin) void {
    const ctx = context orelse return;
    for (transforms, spins) |*tr, spin| {
        tr.yaw += spin.speed * ctx.dt;
    }
}

pub fn register(world: *ecs.world_t) void {
    _ = ecs.ADD_SYSTEM(world, "VX.Formation", ecs.OnUpdate, followSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.Movement", ecs.OnUpdate, moveSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.Animation", ecs.OnUpdate, animSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.Gauges", ecs.OnUpdate, gaugeSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.Motes", ecs.OnUpdate, moteSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.Spins", ecs.OnUpdate, spinSystem);
}
