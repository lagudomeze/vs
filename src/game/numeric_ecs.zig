//! zflecs adapter for numeric components. Kept separate so mech/numeric stay
//! pure and can be tested without linking zflecs.
const std = @import("std");
const ecs = @import("zflecs");
const numeric = @import("numeric.zig");

pub fn register(world: *ecs.world_t) void {
    ecs.COMPONENT(world, numeric.Health);
    ecs.COMPONENT(world, numeric.Resource);
    ecs.COMPONENT(world, numeric.Regen);
    ecs.COMPONENT(world, numeric.LifeState);
}

test "numeric: health gauge can be stored on an ECS entity" {
    const world = ecs.init();
    defer _ = ecs.fini(world);
    register(world);

    const entity = ecs.new_id(world);
    const hp = numeric.gaugeAt(numeric.Health, 100, 70);
    _ = ecs.set(world, entity, numeric.Health, hp);
    const got = ecs.get(world, entity, numeric.Health) orelse return error.MissingHealth;
    try std.testing.expectEqual(@as(f32, 70), got.val);
    try std.testing.expectEqual(@as(f32, 100), got.full);
}
