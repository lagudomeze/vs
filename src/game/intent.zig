//! Pure enemy-intent preview for the turn-based ToME simulation.
//!
//! The module only depends on std. It takes a plain blocked-cell map plus an
//! `EnemyView` snapshot and returns what the enemy would attempt on the next
//! enemy phase. It never mutates the simulation or rolls damage, so a HUD can
//! show "melee 8 / ranged 7 / AOE 45 in 1 turn" without changing play.
//!
//! The rules mirror `tome_sim.enemyAct`:
//! * adjacent -> melee
//! * within range and with line of sight -> ranged
//! * otherwise -> chase
//! * stunned -> wait
//!
//! Boss kind 5 (深渊守卫) replaces its melee with a 0.9-cell AOE every third
//! turn; on the other turns it melees when adjacent and chases otherwise. The
//! AOE is telegraphed one turn ahead and targets the hero's current cell. `damage_preview` is a raw, pre-armor estimate: 0.72x attack for a
//! normal hit (matching the sim's enemy attack scale), 0.55x while slowed, and
//! 2.8x attack for the boss AOE (the v1 深渊斩 budget: 16 attack -> ~45).
const std = @import("std");

/// Enemy kind used by `tome_sim.Enemy` for 深渊守卫.
pub const boss_kind: u8 = 5;
/// The boss uses its AOE on turn 3, 6, 9, ...
pub const boss_aoe_period: u32 = 3;
pub const boss_aoe_radius: f32 = 0.9;
pub const boss_aoe_telegraph: u8 = 1;
/// 2.8x attack matches the 45 damage of the v1 abyss cleave at 16 attack.
pub const boss_aoe_damage_scale: f32 = 2.8;
/// Matches `tome_sim.enemyAttack` raw damage before armor mitigation.
pub const melee_damage_scale: f32 = 0.72;
/// Matches `tome_sim.enemyAttack`'s slowed damage multiplier.
pub const slow_damage_scale: f32 = 0.55;

/// Integer grid cell. Kept local so the intent module stays independent of
/// dungeon.zig and of the renderer.
pub const GridPos = struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn eql(a: GridPos, b: GridPos) bool {
        return a.x == b.x and a.y == b.y;
    }

    /// Four-way (Manhattan) distance in cells.
    pub fn manhattan(a: GridPos, b: GridPos) i32 {
        return @intCast(@abs(a.x - b.x) + @abs(a.y - b.y));
    }
};

pub const IntentKind = enum(u8) { melee, ranged, aoe, chase, wait };

pub const EnemyIntent = struct {
    kind: IntentKind = .wait,
    target: GridPos = .{},
    damage_preview: f32 = 0,
    aoe_radius: f32 = 0,
    telegraph_turns: u8 = 0,
    will_act: bool = false,
};

/// Read-only snapshot of the fields intent prediction needs. Keeping it
/// separate from `tome_sim.Enemy` avoids a module cycle and lets tests build
/// enemies without a whole simulation.
pub const EnemyView = struct {
    kind: u8 = 0,
    pos: GridPos = .{},
    /// Attack range in cells; 1 means melee only.
    range: u16 = 1,
    attack: f32 = 5,
    stun_turns: u16 = 0,
    slow_turns: u16 = 0,
    alive: bool = true,
};

/// Minimal terrain view: a row-major blocked-cell bitmap. Cells outside the
/// board are treated as blocked, matching dungeon.Dungeon semantics.
pub const MapView = struct {
    width: i32,
    height: i32,
    blocked: []const bool,

    pub fn inBounds(self: MapView, p: GridPos) bool {
        return p.x >= 0 and p.y >= 0 and p.x < self.width and p.y < self.height;
    }

    pub fn isBlocked(self: MapView, p: GridPos) bool {
        if (!self.inBounds(p)) return true;
        const w: usize = @intCast(self.width);
        const index = @as(usize, @intCast(p.y)) * w + @as(usize, @intCast(p.x));
        if (index >= self.blocked.len) return true;
        return self.blocked[index];
    }

    /// Bresenham LOS. The two endpoints never block (a wall cell can be
    /// targeted); every cell in between must be clear.
    pub fn lineOfSight(self: MapView, from: GridPos, to: GridPos) bool {
        if (!self.inBounds(from) or !self.inBounds(to)) return false;

        var x = from.x;
        var y = from.y;
        const dx: i32 = @intCast(@abs(to.x - from.x));
        const dy: i32 = -@as(i32, @intCast(@abs(to.y - from.y)));
        const sx: i32 = if (from.x < to.x) 1 else -1;
        const sy: i32 = if (from.y < to.y) 1 else -1;
        var err = dx + dy;

        while (true) {
            if (!(x == from.x and y == from.y) and !(x == to.x and y == to.y)) {
                if (self.isBlocked(.{ .x = x, .y = y })) return false;
            }
            if (x == to.x and y == to.y) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                x += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y += sy;
            }
        }
        return true;
    }
};

pub fn isBoss(kind: u8) bool {
    return kind == boss_kind;
}

/// True on the turns (3, 6, 9, ...) where the boss winds up its AOE.
pub fn bossAoeDue(turn: u32) bool {
    return turn != 0 and turn % boss_aoe_period == 0;
}

/// Predict the enemy's next action. Pure and allocation-free: identical inputs
/// always produce an identical intent.
///
/// `turn` is the enemy-phase number being previewed. A HUD that previews while
/// the player is deciding should pass the upcoming phase (for TomeSim, that is
/// `sim.turn + 1`).
pub fn preview(map: MapView, enemy: EnemyView, hero: GridPos, turn: u32) EnemyIntent {
    if (!enemy.alive) return waitIntent(enemy.pos);
    if (enemy.stun_turns > 0) return waitIntent(enemy.pos);

    if (isBoss(enemy.kind) and bossAoeDue(turn)) {
        return .{
            .kind = .aoe,
            .target = hero,
            .damage_preview = scaledDamage(enemy, boss_aoe_damage_scale),
            .aoe_radius = boss_aoe_radius,
            .telegraph_turns = boss_aoe_telegraph,
            .will_act = true,
        };
    }

    const distance = enemy.pos.manhattan(hero);
    if (distance <= 1) {
        return .{
            .kind = .melee,
            .target = hero,
            .damage_preview = scaledDamage(enemy, melee_damage_scale),
            .will_act = true,
        };
    }

    const reach: i32 = @intCast(enemy.range);
    if (distance <= reach and map.lineOfSight(enemy.pos, hero)) {
        return .{
            .kind = .ranged,
            .target = hero,
            .damage_preview = scaledDamage(enemy, melee_damage_scale),
            .will_act = true,
        };
    }

    return .{
        .kind = .chase,
        .target = hero,
        .will_act = true,
    };
}

fn waitIntent(from: GridPos) EnemyIntent {
    return .{
        .kind = .wait,
        .target = from,
        .damage_preview = 0,
        .aoe_radius = 0,
        .telegraph_turns = 0,
        .will_act = false,
    };
}

fn scaledDamage(enemy: EnemyView, scale: f32) f32 {
    const slow: f32 = if (enemy.slow_turns > 0) slow_damage_scale else 1;
    return @max(@as(f32, 0), enemy.attack * scale * slow);
}

// ------------------------------------------------------------------- tests

const test_size = 13;

const TestMap = struct {
    blocked: [test_size * test_size]bool = @splat(false),

    fn wall(self: *TestMap, x: i32, y: i32) void {
        if (x < 0 or y < 0 or x >= test_size or y >= test_size) return;
        self.blocked[@intCast(y * test_size + x)] = true;
    }

    fn view(self: *const TestMap) MapView {
        return .{ .width = test_size, .height = test_size, .blocked = &self.blocked };
    }
};

fn expectApprox(actual: f32, expected: f32) !void {
    try std.testing.expect(std.math.approxEqAbs(f32, actual, expected, 0.001));
}

test "adjacent enemy intends melee" {
    const map = TestMap{};
    const hero = GridPos{ .x = 6, .y = 6 };
    const enemy = EnemyView{
        .kind = 0,
        .pos = .{ .x = 5, .y = 6 },
        .range = 5, // adjacency wins over the longer range
        .attack = 10,
    };

    const intent = preview(map.view(), enemy, hero, 1);
    try std.testing.expectEqual(IntentKind.melee, intent.kind);
    try std.testing.expect(intent.target.eql(hero));
    try expectApprox(intent.damage_preview, 7.2);
    try std.testing.expectEqual(@as(f32, 0), intent.aoe_radius);
    try std.testing.expectEqual(@as(u8, 0), intent.telegraph_turns);
    try std.testing.expect(intent.will_act);
}

test "ranged enemy with clear LOS intends ranged" {
    const map = TestMap{};
    const hero = GridPos{ .x = 7, .y = 6 };
    const enemy = EnemyView{
        .kind = 1,
        .pos = .{ .x = 3, .y = 6 },
        .range = 4,
        .attack = 10,
    };

    const intent = preview(map.view(), enemy, hero, 1);
    try std.testing.expectEqual(IntentKind.ranged, intent.kind);
    try std.testing.expect(intent.target.eql(hero));
    try expectApprox(intent.damage_preview, 7.2);
    try std.testing.expect(intent.will_act);
}

test "wall blocks LOS so a ranged enemy chases" {
    var map = TestMap{};
    map.wall(5, 6);
    const hero = GridPos{ .x = 8, .y = 6 };
    const enemy = EnemyView{
        .kind = 1,
        .pos = .{ .x = 2, .y = 6 },
        .range = 8,
        .attack = 7,
    };

    const intent = preview(map.view(), enemy, hero, 1);
    try std.testing.expectEqual(IntentKind.chase, intent.kind);
    try std.testing.expect(intent.target.eql(hero));
    try std.testing.expectEqual(@as(f32, 0), intent.damage_preview);
    try std.testing.expect(intent.will_act);
}

test "out-of-range enemy chases even with clear LOS" {
    const map = TestMap{};
    const hero = GridPos{ .x = 9, .y = 2 };
    const enemy = EnemyView{
        .kind = 1,
        .pos = .{ .x = 1, .y = 2 },
        .range = 3,
        .attack = 7,
    };

    const intent = preview(map.view(), enemy, hero, 1);
    try std.testing.expectEqual(IntentKind.chase, intent.kind);
}

test "stunned enemy waits and will not act" {
    const map = TestMap{};
    const hero = GridPos{ .x = 6, .y = 6 };
    const enemy = EnemyView{
        .kind = 0,
        .pos = .{ .x = 6, .y = 5 },
        .range = 1,
        .attack = 10,
        .stun_turns = 2,
    };

    const intent = preview(map.view(), enemy, hero, 1);
    try std.testing.expectEqual(IntentKind.wait, intent.kind);
    try std.testing.expect(intent.target.eql(enemy.pos));
    try std.testing.expectEqual(@as(f32, 0), intent.damage_preview);
    try std.testing.expectEqual(@as(f32, 0), intent.aoe_radius);
    try std.testing.expectEqual(@as(u8, 0), intent.telegraph_turns);
    try std.testing.expect(!intent.will_act);
}

test "dead enemy waits without acting" {
    const map = TestMap{};
    const enemy = EnemyView{
        .kind = 2,
        .pos = .{ .x = 6, .y = 5 },
        .alive = false,
    };

    const intent = preview(map.view(), enemy, .{ .x = 6, .y = 6 }, 1);
    try std.testing.expectEqual(IntentKind.wait, intent.kind);
    try std.testing.expect(!intent.will_act);
}

test "slow reduces the previewed damage but the enemy still acts" {
    const map = TestMap{};
    const hero = GridPos{ .x = 6, .y = 6 };
    const enemy = EnemyView{
        .kind = 0,
        .pos = .{ .x = 6, .y = 5 },
        .attack = 10,
        .slow_turns = 2,
    };

    const intent = preview(map.view(), enemy, hero, 1);
    try std.testing.expectEqual(IntentKind.melee, intent.kind);
    try expectApprox(intent.damage_preview, 3.96); // 10 * 0.72 * 0.55
    try std.testing.expect(intent.will_act);
}

test "boss alternates melee and telegraphed AOE every three turns" {
    const map = TestMap{};
    const hero = GridPos{ .x = 6, .y = 6 };
    const boss = EnemyView{
        .kind = boss_kind,
        .pos = .{ .x = 5, .y = 6 },
        .range = 1,
        .attack = 16,
    };
    const expected = [_]IntentKind{
        .melee, .melee, .aoe,
        .melee, .melee, .aoe,
        .melee,
    };

    for (expected, 0..) |kind, i| {
        const turn: u32 = @intCast(i + 1);
        const intent = preview(map.view(), boss, hero, turn);
        try std.testing.expectEqual(kind, intent.kind);
        try std.testing.expect(intent.target.eql(hero));
        try std.testing.expect(intent.will_act);
        if (kind == .aoe) {
            try std.testing.expectEqual(@as(u8, 1), intent.telegraph_turns);
            try expectApprox(intent.aoe_radius, 0.9);
            try expectApprox(intent.damage_preview, 44.8); // 16 * 2.8
        } else {
            try std.testing.expectEqual(@as(u8, 0), intent.telegraph_turns);
            try std.testing.expectEqual(@as(f32, 0), intent.aoe_radius);
            try expectApprox(intent.damage_preview, 11.52); // 16 * 0.72
        }
    }
}

test "boss AOE is telegraphed even before the boss reaches the hero" {
    const map = TestMap{};
    const hero = GridPos{ .x = 10, .y = 10 };
    const boss = EnemyView{
        .kind = boss_kind,
        .pos = .{ .x = 1, .y = 1 },
        .range = 1,
        .attack = 16,
    };

    const intent = preview(map.view(), boss, hero, 3);
    try std.testing.expectEqual(IntentKind.aoe, intent.kind);
    try std.testing.expect(intent.target.eql(hero));
    try std.testing.expectEqual(@as(u8, 1), intent.telegraph_turns);
    try expectApprox(intent.aoe_radius, 0.9);

    const approach = preview(map.view(), boss, hero, 4);
    try std.testing.expectEqual(IntentKind.chase, approach.kind);
}

test "stunned boss does not telegraph its AOE" {
    const map = TestMap{};
    const hero = GridPos{ .x = 6, .y = 6 };
    const boss = EnemyView{
        .kind = boss_kind,
        .pos = .{ .x = 5, .y = 6 },
        .attack = 16,
        .stun_turns = 1,
    };

    const intent = preview(map.view(), boss, hero, 3);
    try std.testing.expectEqual(IntentKind.wait, intent.kind);
    try std.testing.expect(!intent.will_act);
    try std.testing.expectEqual(@as(f32, 0), intent.aoe_radius);
}

test "boss AOE preview also respects slow" {
    const map = TestMap{};
    const hero = GridPos{ .x = 6, .y = 6 };
    const boss = EnemyView{
        .kind = boss_kind,
        .pos = .{ .x = 5, .y = 6 },
        .attack = 16,
        .slow_turns = 1,
    };

    const intent = preview(map.view(), boss, hero, 3);
    try std.testing.expectEqual(IntentKind.aoe, intent.kind);
    try expectApprox(intent.damage_preview, 24.64); // 16 * 2.8 * 0.55
}

test "identical snapshots always preview the same intent" {
    const map = TestMap{};
    const hero = GridPos{ .x = 6, .y = 6 };
    const enemy = EnemyView{
        .kind = 1,
        .pos = .{ .x = 2, .y = 6 },
        .range = 5,
        .attack = 7,
    };

    const first = preview(map.view(), enemy, hero, 4);
    const second = preview(map.view(), enemy, hero, 4);
    try std.testing.expectEqualDeep(first, second);
}
