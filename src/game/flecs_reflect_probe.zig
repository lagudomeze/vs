//! Phase 0c probe: register a reflected component from Zig and record the
//! current zflecs limitation. This test intentionally asserts the known
//! blocker so the next migration attempt starts from evidence, not folklore.
//!
//! Result (2026-10-24):
//! - ecs.COMPONENT + struct_init succeeds at the C level.
//! - The component entity is not resolvable by name (lookup = 0).
//! - FlecsScript returns rc=-1 with a null error string.
//! - A C-side registration shim duplicates flecs.lib globals at link time.
const std = @import("std");
const ecs = @import("zflecs");

const ProbeCost = extern struct {
    value: f32 = 0,
};

test "flecs reflection probe: struct_init alone does not expose a script type" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    ecs.COMPONENT(world, ProbeCost);
    const component = ecs.id(ProbeCost);

    var desc = std.mem.zeroes(ecs.struct_desc_t);
    desc.entity = component;
    desc.create_member_entities = true;
    desc.members[0] = .{
        .name = "value",
        .type = ecs.id(f32),
        .count = 1,
        .offset = @offsetOf(ProbeCost, "value"),
        .use_offset = true,
    };
    _ = ecs.struct_init(world, &desc);

    const code =
        \\probe_cost {
        \\    ProbeCost: { value: 25 }
        \\}
    ;
    var result = ecs.script_eval_result_t{ .error_ = null };
    const rc = ecs.script_run(world, "probe_cost", code, null, &result);

    try std.testing.expect(rc != 0);
    try std.testing.expectEqual(@as(ecs.entity_t, 0), ecs.lookup(world, "ProbeCost"));
    std.debug.print("[flecs] struct_init probe still blocked: rc={d}, lookup=0, type={s}\n", .{ rc, ecs.typeName(ProbeCost) });
}
