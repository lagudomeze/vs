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
    combat_active: bool = true,
    models: *const model_mod.ModelDb = undefined,
};

pub var context: ?*Context = null;

// ---------------------------------------------------------------------------
// combat events (consumed by the game layer after ecs.progress)
// ---------------------------------------------------------------------------

pub const EventKind = enum { enemy_hit, hero_hit, enemy_died, hero_down };

pub const Event = struct {
    kind: EventKind,
    pos: math.Vec3 = math.Vec3.zero,
    amount: f32 = 0,
    crit: bool = false,
};

pub var events: [128]Event = undefined;
pub var event_count: usize = 0;

pub fn clearEvents() void {
    event_count = 0;
}

pub fn pushEvent(ev: Event) void {
    if (event_count < events.len) {
        events[event_count] = ev;
        event_count += 1;
    }
}

fn dist2xz(a: math.Vec3, b: math.Vec3) f32 {
    const dx = a.x - b.x;
    const dz = a.z - b.z;
    return dx * dx + dz * dz;
}

fn critRoll(time: f32, pos: math.Vec3) bool {
    const v = @sin(time * 93.13 + pos.x * 17.7 + pos.z * 31.1) * 43758.5453;
    return (v - @floor(v)) > 0.86;
}

pub fn nearestEnemy(world: *ecs.world_t, pos: math.Vec3, max_range: f32) ?ecs.entity_t {
    var best: ?ecs.entity_t = null;
    var best_d = max_range * max_range;
    var it = ecs.each(world, comp.Enemy);
    while (ecs.each_next(&it)) {
        const enemies = ecs.field(&it, comp.Enemy, 0).?;
        for (enemies, it.entities()) |enemy, e| {
            if (enemy.hp <= 0) continue;
            const tr = ecs.get(world, e, comp.Transform) orelse continue;
            const d = dist2xz(tr.pos, pos);
            if (d < best_d) {
                best_d = d;
                best = e;
            }
        }
    }
    return best;
}

fn nearestHero(world: *ecs.world_t, pos: math.Vec3) ?ecs.entity_t {
    var best: ?ecs.entity_t = null;
    var best_d: f32 = 1e9;
    var it = ecs.each(world, comp.Hero);
    while (ecs.each_next(&it)) {
        const heroes = ecs.field(&it, comp.Hero, 0).?;
        for (heroes, it.entities()) |hero, e| {
            if (hero.downed) continue;
            const tr = ecs.get(world, e, comp.Transform) orelse continue;
            const d = dist2xz(tr.pos, pos);
            if (d < best_d) {
                best_d = d;
                best = e;
            }
        }
    }
    return best;
}

pub fn damageEnemy(world: *ecs.world_t, target: ecs.entity_t, damage: f32, time: f32) f32 {
    const enemy = ecs.get_mut(world, target, comp.Enemy) orelse return 0;
    if (enemy.hp <= 0) return 0;
    const crit = critRoll(time, combatPosition(world, target));
    const mult: f32 = if (crit) 1.5 else 1.0;
    const amount = damage * mult;
    enemy.hp -= amount;
    enemy.hit_flash = 0.15;
    const pos = combatPosition(world, target).add(math.Vec3.init(0, 0.8, 0));
    pushEvent(.{ .kind = .enemy_hit, .pos = pos, .amount = amount, .crit = crit });
    if (enemy.hp <= 0) {
        pushEvent(.{ .kind = .enemy_died, .pos = pos });
    }
    return amount;
}

fn combatPosition(world: *ecs.world_t, e: ecs.entity_t) math.Vec3 {
    const tr = ecs.get(world, e, comp.Transform) orelse return math.Vec3.zero;
    return tr.pos;
}

fn damageHero(world: *ecs.world_t, target: ecs.entity_t, damage: f32, time: f32) void {
    const hero = ecs.get_mut(world, target, comp.Hero) orelse return;
    if (hero.downed) return;
    const tr = ecs.get(world, target, comp.Transform) orelse return;
    const mult: f32 = if (critRoll(time, tr.pos)) 1.35 else 1.0;
    const amount = damage * mult;
    hero.hp -= amount;
    pushEvent(.{ .kind = .hero_hit, .pos = tr.pos.add(math.Vec3.init(0, 1.0, 0)), .amount = amount });
    if (hero.hp <= 0) {
        hero.hp = 0;
        hero.downed = true;
        hero.revive_timer = 7.0;
        pushEvent(.{ .kind = .hero_down, .pos = tr.pos.add(math.Vec3.init(0, 0.9, 0)) });
    }
}

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

fn enemyAiSystem(
    it: *ecs.iter_t,
    transforms: []comp.Transform,
    intents: []comp.MoveIntent,
    enemies: []comp.Enemy,
    anims: []comp.Animation,
) void {
    const ctx = context orelse return;
    if (!ctx.combat_active or ctx.dt <= 0) return;
    for (enemies, transforms, intents, anims, it.entities()) |*enemy, tr, *intent, *anim, e| {
        if (enemy.hp <= 0) {
            intent.speed = 0;
            continue;
        }
        enemy.attack_timer = @max(0, enemy.attack_timer - ctx.dt);
        enemy.slow_timer = @max(0, enemy.slow_timer - ctx.dt);
        enemy.hit_flash = @max(0, enemy.hit_flash - ctx.dt);

        const target = nearestHero(it.world, tr.pos) orelse {
            intent.speed = 0;
            continue;
        };
        enemy.target = target;
        const target_tr = ecs.get(it.world, target, comp.Transform) orelse continue;
        const dx = target_tr.pos.x - tr.pos.x;
        const dz = target_tr.pos.z - tr.pos.z;
        const d = @sqrt(dx * dx + dz * dz);
        const slow: f32 = if (enemy.slow_timer > 0) 0.55 else 1.0;
        if (d > enemy.attack_range) {
            const inv = if (d > 0.001) 1.0 / d else 0;
            intent.dir = math.Vec3.init(dx * inv, 0, dz * inv);
            intent.speed = enemy.move_speed * slow;

            // keep a little personal space so a pack does not collapse into one pixel
            var others = ecs.each(it.world, comp.Enemy);
            while (ecs.each_next(&others)) {
                const other_enemies = ecs.field(&others, comp.Enemy, 0).?;
                for (other_enemies, others.entities()) |other, oe| {
                    if (oe == e or other.hp <= 0) continue;
                    const otr = ecs.get(it.world, oe, comp.Transform) orelse continue;
                    const sx = tr.pos.x - otr.pos.x;
                    const sz = tr.pos.z - otr.pos.z;
                    const dd = sx * sx + sz * sz;
                    if (dd > 0.0001 and dd < 0.72 * 0.72) {
                        const oi = 1.0 / @sqrt(dd);
                        intent.dir = intent.dir.add(math.Vec3.init(sx * oi, 0, sz * oi).scale(0.55));
                    }
                }
            }
            const dl = intent.dir.length();
            if (dl > 0.001) intent.dir = intent.dir.scale(1.0 / dl);
        } else {
            intent.dir = math.Vec3.zero;
            intent.speed = 0;
            if (enemy.attack_timer <= 0) {
                enemy.attack_timer = enemy.attack_cooldown;
                anim.state.cast = 1.0;
                damageHero(it.world, target, enemy.damage, ctx.time);
            }
        }
    }
}

fn heroCombatSystem(
    it: *ecs.iter_t,
    transforms: []comp.Transform,
    heroes: []comp.Hero,
    anims: []comp.Animation,
) void {
    const ctx = context orelse return;
    if (!ctx.combat_active or ctx.dt <= 0) return;
    for (heroes, transforms, anims, it.entities()) |*hero, tr, *anim, e| {
        _ = e;
        if (hero.downed) continue;
        hero.attack_timer = @max(0, hero.attack_timer - ctx.dt);
        if (hero.attack_timer > 0) continue;
        const target = nearestEnemy(it.world, tr.pos, hero.attack_range) orelse continue;
        hero.attack_timer = hero.attack_cooldown;
        anim.state.cast = 1.0;
        _ = damageEnemy(it.world, target, hero.attack_damage, ctx.time);
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
    _ = ecs.ADD_SYSTEM(world, "VX.EnemyAI", ecs.OnUpdate, enemyAiSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.HeroCombat", ecs.OnUpdate, heroCombatSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.Animation", ecs.OnUpdate, animSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.Gauges", ecs.OnUpdate, gaugeSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.Motes", ecs.OnUpdate, moteSystem);
    _ = ecs.ADD_SYSTEM(world, "VX.Spins", ecs.OnUpdate, spinSystem);
}
