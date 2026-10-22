//! Pixel HUD: party sheet, controls, camera readout and projected nameplates.
const std = @import("std");
const math = @import("../core/math.zig");
const palette = @import("../core/palette.zig");
const renderer = @import("../engine/renderer.zig");

pub const Row = struct {
    name: []const u8,
    level: u16,
    hp: f32,
    hp_max: f32,
    ap: f32,
    ap_max: f32,
    active: bool,
};

pub const Plate = struct {
    pos: math.Vec3 = math.Vec3.zero,
    name: []const u8 = "",
    level: u16 = 1,
    active: bool = false,
};

pub const State = struct {
    rows: [3]Row,
    plates: [3]Plate,
    camera_yaw: f32,
    camera_distance: f32,
    fps: f32,
    frame_ms: f32,
    tris: u32,
    drawn: u32,
    entities: u32,
    debug: bool,
};

fn backPanel(r: *renderer.Renderer, x: i32, y: i32, w: i32, h: i32) void {
    r.fillRect(x, y, w, h, palette.panel);
    r.fillRect(x + 1, y + 1, w - 2, 1, palette.deep);
    r.strokeRect(x, y, w, h, palette.border);
    r.fillRect(x + 2, y + h - 2, 18, 1, palette.gold);
}

fn bar(r: *renderer.Renderer, x: i32, y: i32, w: i32, h: i32, frac: f32, fg: u32) void {
    r.fillRect(x, y, w, h, palette.deep);
    const fill = @as(i32, @intFromFloat(@as(f32, @floatFromInt(w - 2)) * std.math.clamp(frac, 0, 1)));
    if (fill > 0) r.fillRect(x + 1, y + 1, fill, h - 2, fg);
    r.strokeRect(x, y, w, h, palette.muted);
}

pub fn draw(r: *renderer.Renderer, cam: math.OrbitCamera, state: State) void {
    const w: i32 = @intCast(r.width);
    const h: i32 = @intCast(r.height);
    const right_x = w - 134;
    const bottom_y = h - 64;
    // world-space nameplates first, so the panels can cover them at the edges
    for (state.plates, 0..) |plate, i| {
        if (i >= state.rows.len) break;
        if (!plate.active) continue;
        const p = cam.project(plate.pos, r.width, r.height) orelse continue;
        var buf: [40]u8 = undefined;
        const label = if (plate.level > 0)
            std.fmt.bufPrint(&buf, "{s} {d}", .{ plate.name, plate.level }) catch plate.name
        else
            plate.name;
        if (p.x < 0 or p.x > @as(f32, @floatFromInt(r.width)) or p.depth <= 0.1) continue;
        const x: i32 = @intFromFloat(p.x);
        const y: i32 = @intFromFloat(p.y);
        const color = if (plate.active) palette.gold_light else palette.cream;
        r.textCentered(x, y, label, color, 1, true);
    }

    // title
    backPanel(r, 6, 5, 176, 40);
    r.drawText(10, 9, "VX // AETHER KEEP", palette.gold, 1, false);
    r.drawText(10, 19, "REAL 3D / PIXEL PALETTE", palette.muted, 1, false);
    r.drawText(10, 29, "SDL3 + ZFLECS DIORAMA", palette.muted, 1, false);

    // controls
    backPanel(r, right_x, 5, 128, 64);
    r.drawText(right_x + 4, 8, "CONTROLS", palette.gold, 1, false);
    const controls = [_][]const u8{
        "WASD MOVE",
        "Q/E ORBIT",
        "WHEEL ZOOM",
        "TAB SWITCH",
        "SPACE CAST",
        "F1 DEBUG / ESC",
    };
    for (controls, 0..) |line, i| {
        r.drawText(right_x + 4, 18 + @as(i32, @intCast(i)) * 8, line, palette.cream, 1, false);
    }

    // party
    backPanel(r, 6, bottom_y, 202, 58);
    for (state.rows, 0..) |row, i| {
        const y: i32 = bottom_y + 5 + @as(i32, @intCast(i)) * 16;
        const name_color = if (row.active) palette.gold_light else palette.cream;
        if (row.active) r.drawText(9, y + 3, ">", palette.gold, 1, false);
        r.drawText(15, y + 3, row.name, name_color, 1, false);
        var lv: [16]u8 = undefined;
        const lv_text = std.fmt.bufPrint(&lv, "LV{d}", .{row.level}) catch "";
        r.drawText(84, y + 3, lv_text, palette.muted, 1, false);

        bar(r, 118, y + 1, 82, 5, if (row.hp_max > 0) row.hp / row.hp_max else 0, palette.health_light);
        bar(r, 118, y + 7, 82, 5, if (row.ap_max > 0) row.ap / row.ap_max else 0, palette.cyan);
        if (row.active) r.fillRect(118, y + 13, 82, 1, palette.gold);
    }

    // camera / render stats
    backPanel(r, right_x, bottom_y, 128, 58);
    var buf: [48]u8 = undefined;
    r.drawText(right_x + 4, bottom_y + 4, "CAMERA", palette.gold, 1, false);
    const yaw_deg = state.camera_yaw * 180.0 / std.math.pi;
    const line1 = std.fmt.bufPrint(&buf, "YAW {d:3.0} DIST {d:.1}", .{ yaw_deg, state.camera_distance }) catch "";
    r.drawText(right_x + 4, bottom_y + 14, line1, palette.cream, 1, false);
    const line2 = std.fmt.bufPrint(&buf, "FPS {d:2.0} TRIS {d}K", .{ state.fps, state.tris / 1000 }) catch "";
    r.drawText(right_x + 4, bottom_y + 24, line2, palette.muted, 1, false);
    if (state.debug) {
        const line3 = std.fmt.bufPrint(&buf, "ENT {d} DRAWN {d}K", .{ state.entities, state.drawn / 1000 }) catch "";
        r.drawText(right_x + 4, bottom_y + 34, line3, palette.muted, 1, false);
        const line4 = std.fmt.bufPrint(&buf, "MS {d:.1}  {d}x{d}", .{ state.frame_ms, r.width, r.height }) catch "";
        r.drawText(right_x + 4, bottom_y + 44, line4, palette.muted, 1, false);
    }
}
