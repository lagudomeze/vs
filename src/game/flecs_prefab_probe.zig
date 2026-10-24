//! Phase 0b probe: prefab inheritance + per-instance override.
//! Best practice for content: author a prefab once, instantiate via IsA, and
//! only override the fields that differ. This is the composable path to try
//! before deleting ItemDef/SkillDef; reflection is still the blocker for
//! FlecsScript value assignment.
const std = @import("std");
const ecs = @import("zflecs");

const Stats = struct {
    hp: f32 = 0,
    speed: f32 = 0,
};

test "flecs prefab probe: instance inherits then overrides a component" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    ecs.COMPONENT(world, Stats);

    const prefab = ecs.new_prefab(world, "EnemyPrefab");
    _ = ecs.set(world, prefab, Stats, .{ .hp = 10, .speed = 100 });

    const instance = ecs.new_w_pair(world, ecs.IsA, prefab);
    const inherited = ecs.get(world, instance, Stats) orelse return error.MissingStats;
    try std.testing.expectApproxEqAbs(@as(f32, 10), inherited.hp, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), inherited.speed, 0.001);

    _ = ecs.set(world, instance, Stats, .{ .hp = 25, .speed = 100 });
    const overridden = ecs.get(world, instance, Stats) orelse return error.MissingStats;
    try std.testing.expectApproxEqAbs(@as(f32, 25), overridden.hp, 0.001);

    const prefab_stats = ecs.get(world, prefab, Stats) orelse return error.MissingStats;
    try std.testing.expectApproxEqAbs(@as(f32, 10), prefab_stats.hp, 0.001);
}
