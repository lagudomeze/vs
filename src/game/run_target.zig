//! Pure talent-targeting rules for the turn-based aim step.
//!
//! The game needs one source of truth for three questions:
//!   1. does talent N take a target at all (aim) or fire immediately?
//!   2. is enemy E a legal target right now (range / line of sight / resource /
//!      cooldown) and what damage would it take?
//!   3. which cells does an area talent cover (for the preview rings)?
//!
//! Everything here is read-only over `Sim` and allocates nothing, so the aim
//! state machine in `run_game.zig`, the HUD preview line and the unit tests
//! all share exactly the same rules.
const std = @import("std");
const run = @import("run_sim.zig");
const combat = @import("combat.zig");

pub const TalentKind = enum(u8) {
    /// Single enemy hit (重击/冲锋/冰锥/时光箭/时间停滞).
    strike,
    /// Enemy-centred area hit (火球).
    aoe,
    /// Self buff, released immediately (战吼).
    buff,
    /// Random free-cell teleport (闪现).
    blink,
    /// Step back to the previous cell (回溯).
    rewind,

    /// Only enemy-facing talents go through the aim -> confirm step.
    pub fn needsTarget(self: TalentKind) bool {
        return self == .strike or self == .aoe;
    }
};

/// Static description of one talent slot. Ranges mirror `Sim.useTalentOn`
/// (Manhattan distance; the game's `dist()` helper).
pub const TalentSpec = struct {
    kind: TalentKind = .strike,
    range: i32 = 1,
    /// Area radius in cells for .aoe (0 for single-target).
    aoe_radius: i32 = 0,
    /// Multiplier applied to the hero's attack before armor mitigation.
    damage_mult: f32 = 0,
    /// Ranged talents need a clear line of fire.
    needs_los: bool = true,

    pub fn needsTarget(self: TalentSpec) bool {
        return self.kind.needsTarget();
    }
};

pub fn specFor(class: run.Class, index: usize) TalentSpec {
    const i = @min(index, 2);
    return switch (class) {
        .warrior => switch (i) {
            0 => .{ .range = 1, .damage_mult = 2.2 },
            1 => .{ .range = 4, .damage_mult = 1.5 },
            else => .{ .kind = .buff, .range = 0, .needs_los = false },
        },
        .mage => switch (i) {
            0 => .{ .kind = .aoe, .range = 5, .aoe_radius = 1, .damage_mult = 2.5 },
            1 => .{ .range = 4, .damage_mult = 1.8 },
            else => .{ .kind = .blink, .range = 0, .needs_los = false },
        },
        .chronomancer => switch (i) {
            0 => .{ .range = 5, .damage_mult = 2.0 },
            1 => .{ .range = 4, .damage_mult = 1.2 },
            else => .{ .kind = .rewind, .range = 0, .needs_los = false },
        },
    };
}

pub fn needsTarget(class: run.Class, index: usize) bool {
    return specFor(class, index).needsTarget();
}

/// Why a target cannot be confirmed. `.ok` is the only confirmable verdict.
pub const Verdict = enum(u8) {
    ok,
    not_playing,
    not_targetable,
    no_target,
    out_of_range,
    no_line_of_sight,
    cooldown,
    no_resource,
    blocked_cell,

    pub fn valid(self: Verdict) bool {
        return self == .ok;
    }
};

/// Short Chinese reason for the HUD line / log. Empty for .ok.
pub fn verdictText(verdict: Verdict) []const u8 {
    return switch (verdict) {
        .ok => "",
        .not_playing => "战斗已结束",
        .not_targetable => "无需目标",
        .no_target => "无效目标",
        .out_of_range => "超出范围",
        .no_line_of_sight => "视线受阻",
        .cooldown => "冷却中",
        .no_resource => "缺资源",
        .blocked_cell => "无法落点",
    };
}

pub const max_aoe_cells = 9;

/// Read-only preview of confirming `talent` on `target`.
/// `target` is an index into `sim.enemies`; null means "nothing selected".
pub const Preview = struct {
    verdict: Verdict = .no_target,
    spec: TalentSpec = .{},
    target: ?usize = null,
    /// Manhattan distance from the hero to the target (0 when no target).
    distance: i32 = 0,
    /// Expected damage on the primary target, before crit rolls.
    damage: f32 = 0,
    aoe_cells: [max_aoe_cells]run.GridPos = @splat(.{ .x = 0, .y = 0 }),
    aoe_count: usize = 0,

    pub fn valid(self: Preview) bool {
        return self.verdict.valid();
    }

    pub fn reason(self: Preview) []const u8 {
        return verdictText(self.verdict);
    }

    pub fn damageInt(self: Preview) i32 {
        if (self.damage <= 0) return 0;
        return @intFromFloat(@round(self.damage));
    }

    pub fn aoeSlice(self: *const Preview) []const run.GridPos {
        return self.aoe_cells[0..self.aoe_count];
    }
};

pub fn distance(a: run.GridPos, b: run.GridPos) i32 {
    return @intCast(@abs(a.x - b.x) + @abs(a.y - b.y));
}

/// Same formula as `Sim.playerAttack` minus the random crit roll, including
/// the 战吼 buff when it is active.
pub fn estimateDamage(sim: *const run.Sim, spec: TalentSpec, armor: f32) f32 {
    if (spec.damage_mult <= 0) return 0;
    var raw = sim.hero.combat.attack * spec.damage_mult;
    if (sim.hero.status.buff_turns > 0) raw *= 1.0 + sim.hero.status.buff_pct;
    return combat.preview(.{ .raw = raw }, .{ .armor = armor });
}

/// Validate a possible confirmation without touching the simulation.
pub fn preview(sim: *const run.Sim, talent: usize, target: ?usize) Preview {
    var p = Preview{};
    if (talent >= 3) return p;

    const spec = specFor(sim.class, talent);
    p.spec = spec;
    if (!spec.needsTarget()) {
        p.verdict = .not_targetable;
        return p;
    }
    if (sim.state != .playing) {
        p.verdict = .not_playing;
        return p;
    }
    if (sim.hero.talents.cooldowns[talent] > 0) {
        p.verdict = .cooldown;
        return p;
    }
    const cost = sim.talentCost(talent);
    if (sim.hero.resource.current < @as(f32, @floatFromInt(cost))) {
        p.verdict = .no_resource;
        return p;
    }
    const idx = target orelse {
        p.verdict = .no_target;
        return p;
    };
    if (idx >= sim.enemy_count) {
        p.verdict = .no_target;
        return p;
    }
    const enemy = sim.enemies[idx];
    if (!enemy.vitals.alive) {
        p.verdict = .no_target;
        return p;
    }

    p.target = idx;
    p.distance = distance(sim.hero.pos, enemy.pos);
    if (p.distance > spec.range) {
        p.verdict = .out_of_range;
        return p;
    }
    if (spec.needs_los and !sim.hasLineOfSight(sim.hero.pos, enemy.pos)) {
        p.verdict = .no_line_of_sight;
        return p;
    }

    p.damage = estimateDamage(sim, spec, enemy.combat.armor);
    if (spec.kind == .aoe and spec.aoe_radius > 0) fillAoe(&p, enemy.pos, spec.aoe_radius);
    p.verdict = .ok;
    return p;
}

fn fillAoe(p: *Preview, center: run.GridPos, radius: i32) void {
    p.aoe_count = 0;
    var dy: i32 = -radius;
    while (dy <= radius) : (dy += 1) {
        var dx: i32 = -radius;
        while (dx <= radius) : (dx += 1) {
            if (@abs(dx) + @abs(dy) > radius) continue;
            const x = center.x + dx;
            const y = center.y + dy;
            if (x < 0 or y < 0 or x >= run.grid_w or y >= run.grid_h) continue;
            if (p.aoe_count >= p.aoe_cells.len) return;
            p.aoe_cells[p.aoe_count] = .{ .x = x, .y = y };
            p.aoe_count += 1;
        }
    }
}

fn placeEnemy(s: *run.Sim, pos: run.GridPos, hp: f32) void {
    s.enemy_count = 1;
    s.enemies[0] = run.enemyFromParts(.{
        .kind = 0,
        .name = "骷髅兵",
        .pos = pos,
        .hp = hp,
        .hp_max = hp,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
    });
}

test "run target: only enemy-facing talents need an aim step" {
    try std.testing.expect(needsTarget(.warrior, 0)); // 重击
    try std.testing.expect(needsTarget(.warrior, 1)); // 冲锋
    try std.testing.expect(!needsTarget(.warrior, 2)); // 战吼
    try std.testing.expect(needsTarget(.mage, 0)); // 火球
    try std.testing.expect(needsTarget(.mage, 1)); // 冰锥
    try std.testing.expect(!needsTarget(.mage, 2)); // 闪现
    try std.testing.expect(needsTarget(.chronomancer, 0)); // 时光箭
    try std.testing.expect(needsTarget(.chronomancer, 1)); // 时间停滞
    try std.testing.expect(!needsTarget(.chronomancer, 2)); // 回溯
    try std.testing.expectEqual(TalentKind.aoe, specFor(.mage, 0).kind);
    try std.testing.expectEqual(@as(i32, 1), specFor(.mage, 0).aoe_radius);
}

test "run target: adjacent enemy previews as valid with positive damage" {
    var s = run.Sim.init(101, .warrior);
    placeEnemy(&s, .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y }, 70);

    const p = preview(&s, 0, 0);
    try std.testing.expect(p.valid());
    try std.testing.expectEqual(Verdict.ok, p.verdict);
    try std.testing.expectEqual(@as(?usize, 0), p.target);
    try std.testing.expectEqual(@as(i32, 1), p.distance);
    try std.testing.expect(p.damageInt() > 0);
    try std.testing.expectApproxEqAbs(estimateDamage(&s, p.spec, 4), p.damage, 0.001);
    try std.testing.expectEqual(@as(usize, 0), p.aoe_count);

    // Preview is read-only: no turn, no resource, no cooldown.
    try std.testing.expectEqual(@as(u32, 1), s.turn);
    try std.testing.expectEqual(@as(u16, 0), s.hero.talents.cooldowns[0]);
    try std.testing.expectEqual(s.hero.resource.max, s.hero.resource.current);
}

test "run target: missing or dead target is rejected" {
    var s = run.Sim.init(103, .warrior);
    try std.testing.expectEqual(Verdict.no_target, preview(&s, 0, null).verdict);

    placeEnemy(&s, .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y }, 70);
    try std.testing.expectEqual(Verdict.no_target, preview(&s, 0, 9).verdict);

    s.enemies[0].vitals.alive = false;
    try std.testing.expectEqual(Verdict.no_target, preview(&s, 0, 0).verdict);
}

test "run target: range is Manhattan and out-of-range previews are red" {
    var s = run.Sim.init(107, .warrior);
    s.hero.pos = .{ .x = 1, .y = 1 };
    // Open a clean horizontal corridor so only range decides the verdict.
    var x: i32 = 2;
    while (x <= 7) : (x += 1) s.blocked[1 * run.grid_w + @as(usize, @intCast(x))] = false;
    placeEnemy(&s, .{ .x = 3, .y = 1 }, 70);

    const p = preview(&s, 0, 0); // 重击 range 1
    try std.testing.expect(!p.valid());
    try std.testing.expectEqual(Verdict.out_of_range, p.verdict);
    try std.testing.expectEqual(@as(i32, 2), p.distance);

    // 冲锋 reaches 4 cells: distance 2 is legal, distance 5 is not.
    try std.testing.expect(preview(&s, 1, 0).valid());
    s.enemies[0].pos = .{ .x = 5, .y = 1 };
    const charge = preview(&s, 1, 0);
    try std.testing.expect(charge.valid());
    try std.testing.expectEqual(@as(i32, 4), charge.distance);
    s.enemies[0].pos = .{ .x = 6, .y = 1 };
    try std.testing.expectEqual(Verdict.out_of_range, preview(&s, 1, 0).verdict);
}

test "run target: walls block line of sight" {
    var s = run.Sim.init(109, .mage);
    s.hero.pos = .{ .x = 1, .y = 1 };
    // Clean corridor (2,1)..(5,1), then a wall right in the middle.
    var x: i32 = 2;
    while (x <= 5) : (x += 1) s.blocked[1 * run.grid_w + @as(usize, @intCast(x))] = false;
    placeEnemy(&s, .{ .x = 5, .y = 1 }, 70);
    s.blocked[1 * run.grid_w + 3] = true; // wall at (3,1)

    const blocked = preview(&s, 0, 0); // 火球 range 5
    try std.testing.expect(!blocked.valid());
    try std.testing.expectEqual(Verdict.no_line_of_sight, blocked.verdict);
    try std.testing.expectEqualStrings("视线受阻", blocked.reason());

    s.blocked[1 * run.grid_w + 3] = false;
    const clear = preview(&s, 0, 0);
    try std.testing.expect(clear.valid());
}

test "run target: resources and cooldowns are checked before confirming" {
    var s = run.Sim.init(113, .warrior);
    placeEnemy(&s, .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y }, 70);

    s.hero.resource.current = 0;
    try std.testing.expectEqual(Verdict.no_resource, preview(&s, 0, 0).verdict);
    s.hero.resource.current = s.hero.resource.max;

    s.hero.talents.cooldowns[0] = 2;
    try std.testing.expectEqual(Verdict.cooldown, preview(&s, 0, 0).verdict);
    s.hero.talents.cooldowns[0] = 0;

    try std.testing.expect(preview(&s, 0, 0).valid());
    s.state = .victory;
    try std.testing.expectEqual(Verdict.not_playing, preview(&s, 0, 0).verdict);
}

test "run target: self talents are not aimable" {
    const s = run.Sim.init(127, .warrior);
    try std.testing.expectEqual(Verdict.not_targetable, preview(&s, 2, null).verdict);
    const m = run.Sim.init(131, .mage);
    try std.testing.expectEqual(Verdict.not_targetable, preview(&m, 2, null).verdict);
    const c = run.Sim.init(137, .chronomancer);
    try std.testing.expectEqual(Verdict.not_targetable, preview(&c, 2, null).verdict);
}

test "run target: fireball preview covers the cross-shaped blast" {
    var s = run.Sim.init(139, .mage);
    s.hero.pos = .{ .x = 2, .y = 2 };
    placeEnemy(&s, .{ .x = 4, .y = 2 }, 70);

    const p = preview(&s, 0, 0);
    try std.testing.expect(p.valid());
    try std.testing.expectEqual(@as(usize, 5), p.aoe_count);
    var found_center = false;
    for (p.aoeSlice()) |cell| {
        if (cell.x == 4 and cell.y == 2) found_center = true;
        try std.testing.expect(@abs(cell.x - 4) + @abs(cell.y - 2) <= 1);
    }
    try std.testing.expect(found_center);
}

test "run target: verdict texts are non-empty and stable" {
    const verdicts = [_]Verdict{ .not_playing, .not_targetable, .no_target, .out_of_range, .no_line_of_sight, .cooldown, .no_resource };
    for (verdicts) |v| {
        try std.testing.expect(!v.valid());
        try std.testing.expect(verdictText(v).len > 0);
    }
    try std.testing.expectEqualStrings("", verdictText(.ok));
}
