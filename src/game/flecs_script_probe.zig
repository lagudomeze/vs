//! Phase 0 probe: FlecsScript runtime smoke test.
//! Finding: script entities work, but struct/value assignment is blocked in
//! this zflecs build; see docs/FLECS_CONTENT.md.
const std = @import("std");
const ecs = @import("zflecs");

test "flecs script probe: script creates an entity" {
    const world = ecs.init();
    defer _ = ecs.fini(world);

    const code =
        \\probe_entity {}
    ;
    var result = ecs.script_eval_result_t{ .error_ = null };
    const rc = ecs.script_run(world, "probe", code, null, &result);
    if (rc != 0) {
        if (result.error_) |err| std.debug.print("flecs script error: {s}\n", .{std.mem.span(err)});
        return error.ScriptRunFailed;
    }
    try std.testing.expect(ecs.lookup(world, "probe_entity") != 0);
}
