//! Pure mapping from platform frame input to a RunGame input frame.
//! Kept separate so the forwarding layer (bomb, pause-resume, restart) is testable.
const std = @import("std");
const platform = @import("../platform/sdl.zig");
const run_game = @import("run_game.zig");

pub const Input = run_game.Input;
pub const RunGame = run_game.RunGame;

pub fn build(
    pin: platform.FrameInput,
    game: *const RunGame,
    bomb_ok: bool,
    pause_resumed: bool,
    modal_consumed: bool,
) Input {
    var input = Input{};
    input.step_x = @as(i32, @intFromBool(pin.step_e)) - @as(i32, @intFromBool(pin.step_w));
    input.step_y = @as(i32, @intFromBool(pin.step_s)) - @as(i32, @intFromBool(pin.step_n));
    if (pin.talent_1) input.talent = 0;
    if (pin.talent_2) input.talent = 1;
    if (pin.talent_3) input.talent = 2;
    input.confirm = pin.cast and !pause_resumed;
    input.wait = pin.wait and !pause_resumed;
    input.target_next = pin.toggle_hero;
    input.inventory = pin.inventory;
    input.character = pin.character;
    input.restart = pin.reset or
        (pin.pause and !modal_consumed and game.started and
            (game.sim.state == .dead or game.sim.state == .victory));
    input.help = pin.help;
    input.difficulty = pin.difficulty;
    input.use_item = pin.use_item;
    input.use_bomb = pin.use_bomb and bomb_ok;
    input.mouse_x = pin.mouse_x;
    input.mouse_y = pin.mouse_y;
    input.click = pin.click;
    input.stat = pin.stat;
    input.yaw_delta = pin.yaw_delta;
    input.zoom_delta = pin.zoom_delta;
    return input;
}

test "input map: forwards bomb only in a bomb-safe frame" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    g.sim.state = .playing;

    const pin = platform.FrameInput{ .use_bomb = true };
    try std.testing.expect(build(pin, g, true, false, false).use_bomb);
    try std.testing.expect(!build(pin, g, false, false, false).use_bomb);
}

test "input map: pause resume does not repeat the action" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    g.sim.state = .playing;

    const pin = platform.FrameInput{ .cast = true, .wait = true };
    const resumed = build(pin, g, true, true, true);
    try std.testing.expect(!resumed.confirm);
    try std.testing.expect(!resumed.wait);
    const normal = build(pin, g, true, false, false);
    try std.testing.expect(normal.confirm);
}

test "input map: start restarts end screen unless a modal consumed it" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    g.sim.state = .dead;

    const pin = platform.FrameInput{ .pause = true };
    try std.testing.expect(build(pin, g, false, false, false).restart);
    try std.testing.expect(!build(pin, g, false, false, true).restart);
    const r = platform.FrameInput{ .reset = true, .pause = true };
    try std.testing.expect(build(r, g, false, false, true).restart);
}
