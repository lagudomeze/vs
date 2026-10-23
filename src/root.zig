//! VX: a real-3D pixel-art dungeon diorama built on SDL3 + zflecs.
const std = @import("std");

pub const math = @import("core/math.zig");
pub const color = @import("core/color.zig");
pub const palette = @import("core/palette.zig");
pub const png = @import("core/png.zig");
pub const font = @import("core/font.zig");

pub const model = @import("engine/model.zig");
pub const rig = @import("engine/rig.zig");
pub const arena_mesh = @import("engine/arena_mesh.zig");
pub const renderer = @import("engine/renderer.zig");

pub const components = @import("game/components.zig");
pub const turn = @import("game/turn.zig");
pub const attributes = @import("game/attributes.zig");
pub const items = @import("game/items.zig");
pub const content = @import("game/content.zig");
pub const dungeon = @import("game/dungeon.zig");
pub const run_sim = @import("game/run_sim.zig");
pub const save = @import("game/save.zig");
pub const run_target = @import("game/run_target.zig");
pub const intent = @import("game/intent.zig");
pub const run_regression = @import("qa2/run_regression.zig");
pub const run_hud = @import("game/run_hud.zig");
pub const run_game = @import("game/run_game.zig");
pub const RunGame = @import("game/run_game.zig").RunGame;
pub const systems = @import("game/systems.zig");
pub const hud = @import("game/hud.zig");
pub const game = @import("game/game.zig");
pub const Game = @import("game/game.zig").Game;
pub const platform = @import("platform/sdl.zig");

test {
    std.testing.refAllDecls(@This());
    _ = @import("game/flecs_script_probe.zig");
}

test "all embedded models load" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const db = try model.ModelDb.init(arena.allocator(), @import("assets").all);
    try std.testing.expect(db.models.len >= 20);
    const warrior = db.find("warrior") orelse return error.MissingWarrior;
    try std.testing.expect(warrior.joints.len >= 10);
    try std.testing.expect(warrior.parts.len >= 8);
    try std.testing.expect(warrior.torso != null);
    try std.testing.expect(warrior.weapon != null);
    const archmage = db.find("archmage") orelse return error.MissingArchmage;
    try std.testing.expect(archmage.focus != null);
    const chrono = db.find("chronomancer") orelse return error.MissingChrono;
    try std.testing.expect(chrono.aura != null);
}

test "game boots, simulates and renders offscreen" {
    const gpa = std.testing.allocator;
    const g = try Game.create(gpa, 160, 90);
    defer g.destroy();

    var frame: u32 = 0;
    while (frame < 12) : (frame += 1) {
        g.update(.{ .move_z = 1.0 }, 1.0 / 60.0);
    }
    g.render();
    try std.testing.expect(g.renderer.stats.tris > 1000);
    try std.testing.expect(g.renderer.stats.drawn > 1000);
    try std.testing.expect(g.party[g.active_index] != 0);
    try std.testing.expect(g.camera.target.y > 0.3);
}

test "combat spawns waves and deals damage" {
    const gpa = std.testing.allocator;
    const g = try Game.create(gpa, 160, 90);
    defer g.destroy();

    var frame: u32 = 0;
    while (frame < 420) : (frame += 1) {
        var input = @import("game/game.zig").InputFrame{};
        if (frame % 90 == 0) input.cast = true;
        g.update(input, 1.0 / 60.0);
    }
    try std.testing.expect(g.wave >= 1);
    try std.testing.expect(g.enemyCount() > 0 or g.kills > 0);
    g.show_hud = false;
    g.render();
    try std.testing.expect(g.renderer.stats.tris > 20000);
}
