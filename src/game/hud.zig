//! Pixel HUD: Chinese party sheet, controls, status and projected nameplates.
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
    downed: bool = false,
    revive: f32 = 0,
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
    wave: u8 = 0,
    max_waves: u8 = 5,
    enemies: u8 = 0,
    kills: u32 = 0,
    skill: []const u8 = "",
    banner: []const u8 = "",
    banner_time: f32 = 0,
    mode: u8 = 1, // 0 frozen, 1 flowing, 2 threat
    threat: []const u8 = "",
    threat_time: f32 = 0,
    log_lines: [4][]const u8 = .{ "", "", "", "" },
    log_count: usize = 0,
    inventory_open: bool = false,
    attr_values: [6]i32 = .{ 0, 0, 0, 0, 0, 0 },
    equip_names: [3][]const u8 = .{ "", "", "" },
    item_names: [8][]const u8 = .{ "", "", "", "", "", "", "", "" },
    item_count: usize = 0,
    victory: bool = false,
    defeat: bool = false,
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

fn fmt(buf: []u8, comptime f: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, f, args) catch "";
}

pub fn draw(r: *renderer.Renderer, cam: math.OrbitCamera, state: State) void {
    const w: i32 = @intCast(r.width);
    const h: i32 = @intCast(r.height);
    const bottom_y = h - 86;

    // world-space nameplates first, so panels can cover them at the edges
    for (state.plates) |plate| {
        if (!plate.active) continue;
        const p = cam.project(plate.pos, r.width, r.height) orelse continue;
        var buf: [48]u8 = undefined;
        const label = if (plate.level > 0)
            fmt(&buf, "{s} {d}", .{ plate.name, plate.level })
        else
            plate.name;
        if (p.x < 0 or p.x > @as(f32, @floatFromInt(r.width)) or p.depth <= 0.1) continue;
        const x: i32 = @intFromFloat(p.x);
        const y: i32 = @intFromFloat(p.y);
        const color = if (plate.active) palette.gold_light else palette.cream;
        const tw = renderer.Renderer.textWidth(label, 1);
        r.fillRect(x - @divTrunc(tw, 2) - 4, y - 4, tw + 8, 15, palette.panel);
        r.strokeRect(x - @divTrunc(tw, 2) - 4, y - 4, tw + 8, 15, palette.border);
        r.textCentered(x, y - 2, label, color, 1, true);
    }

    // title + tactical time state
    backPanel(r, 6, 5, 178, 66);
    r.drawText(10, 8, "VX / 以太堡", palette.gold, 1, false);
    r.drawText(10, 22, "真3D 像素渲染", palette.cream, 1, false);
    r.drawText(10, 36, "SDL3 + ZFLECS", palette.muted, 1, false);
    const mode_text = switch (state.mode) {
        0 => "时间 冻结",
        2 => "时间 威胁",
        else => "时间 流动",
    };
    const mode_color = switch (state.mode) {
        0 => palette.cyan_light,
        2 => palette.red,
        else => palette.gold_light,
    };
    r.drawText(10, 50, mode_text, mode_color, 1, false);

    // combat log
    if (state.log_count > 0) {
        backPanel(r, 6, 74, 178, 50);
        for (state.log_lines, 0..) |line, i| {
            if (i >= state.log_count) break;
            r.drawText(10, 78 + @as(i32, @intCast(i)) * 11, line, if (i == state.log_count - 1) palette.cream else palette.muted, 1, false);
        }
    }

    // controls (two columns)
    const controls_x = w - 212;
    backPanel(r, controls_x, 5, 206, 94);
    r.drawText(controls_x + 5, 8, "操作", palette.gold, 1, false);
    const c1 = [_][]const u8{ "WASD 移动", "Q/E 转动", "WHEEL 缩放", "TAB 切换" };
    const c2 = [_][]const u8{ "空格 技能", "F 反制", "I 背包", "R 重开" };
    for (c1, 0..) |line, i| {
        r.drawText(controls_x + 5, 23 + @as(i32, @intCast(i)) * 15, line, palette.cream, 1, false);
    }
    for (c2, 0..) |line, i| {
        r.drawText(controls_x + 112, 23 + @as(i32, @intCast(i)) * 15, line, palette.cream, 1, false);
    }
    r.drawText(controls_x + 5, 82, "F1 调试   ESC 退出", palette.muted, 1, false);

    // party
    backPanel(r, 6, bottom_y, 234, 82);
    r.drawText(10, bottom_y + 4, "队伍", palette.gold, 1, false);
    var buf: [48]u8 = undefined;
    const kills = fmt(&buf, "击杀 {d}", .{state.kills});
    r.drawText(238 - renderer.Renderer.textWidth(kills, 1), bottom_y + 4, kills, palette.muted, 1, false);
    for (state.rows, 0..) |row, i| {
        const y: i32 = bottom_y + 22 + @as(i32, @intCast(i)) * 19;
        const name_color = if (row.downed) palette.muted else if (row.active) palette.gold_light else palette.cream;
        if (row.active) r.drawText(9, y, ">", palette.gold, 1, false);
        r.drawText(18, y, row.name, name_color, 1, false);
        var lv: [24]u8 = undefined;
        const lv_text = fmt(&lv, "{d}级", .{row.level});
        r.drawText(76, y, lv_text, palette.muted, 1, false);
        if (row.downed) {
            var dt: [16]u8 = undefined;
            const down = fmt(&dt, "倒下 {d}", .{@as(i32, @intFromFloat(row.revive))});
            r.drawText(112, y, down, palette.red, 1, false);
        } else {
            bar(r, 112, y + 1, 112, 5, if (row.hp_max > 0) row.hp / row.hp_max else 0, palette.health_light);
            bar(r, 112, y + 8, 92, 4, if (row.ap_max > 0) row.ap / row.ap_max else 0, palette.cyan);
        }
    }

    // status / camera / wave
    const stats_x = w - 176;
    backPanel(r, stats_x, bottom_y, 170, 82);
    r.drawText(stats_x + 4, bottom_y + 4, "状态", palette.gold, 1, false);
    const wave = fmt(&buf, "波次 {d}/{d}  余敌 {d}", .{ state.wave, state.max_waves, state.enemies });
    r.drawText(stats_x + 4, bottom_y + 21, wave, palette.cream, 1, false);
    const yaw_deg = state.camera_yaw * 180.0 / std.math.pi;
    const cam_line = fmt(&buf, "视角 {d:3.0}  距离 {d:.1}", .{ yaw_deg, state.camera_distance });
    r.drawText(stats_x + 4, bottom_y + 36, cam_line, palette.muted, 1, false);
    const perf = fmt(&buf, "帧率 {d:2.0}  三角 {d}k", .{ state.fps, state.tris / 1000 });
    r.drawText(stats_x + 4, bottom_y + 51, perf, palette.muted, 1, false);
    if (state.skill.len > 0) {
        const skill = fmt(&buf, "技能 {s} 35", .{state.skill});
        r.drawText(stats_x + 4, bottom_y + 66, skill, palette.cyan_light, 1, false);
    }

    // threat prompt takes over the centre of the screen
    if (state.threat_time > 0 and state.threat.len > 0) {
        const tw = renderer.Renderer.textWidth(state.threat, 1);
        const center = @divTrunc(w, 2);
        const bx = center - @divTrunc(tw, 2) - 9;
        const by = 92;
        r.fillRect(bx, by, tw + 18, 22, palette.panel);
        r.fillRect(bx, by, tw + 18, 2, palette.red);
        r.strokeRect(bx, by, tw + 18, 22, palette.red);
        r.textCentered(center, by + 5, state.threat, palette.gold_light, 1, true);
    }

    // transient wave banner, in the gap between the title and controls panels
    if (state.threat_time <= 0 and state.banner_time > 0 and state.banner.len > 0) {
        const tw = renderer.Renderer.textWidth(state.banner, 1);
        const center = @divTrunc(184 + (w - 212), 2) - 4;
        const bx = center - @divTrunc(tw, 2) - 9;
        const by = 7;
        backPanel(r, bx, by, tw + 18, 22);
        r.textCentered(center, by + 5, state.banner, palette.gold_light, 1, true);
    }

    // character / inventory panel
    if (state.inventory_open) {
        r.fillRect(0, 0, w, h, palette.deep);
        const ix: i32 = 16;
        const iy: i32 = 12;
        const iw: i32 = w - 32;
        const ih: i32 = h - 24;
        r.fillRect(ix, iy, iw, ih, palette.panel);
        r.strokeRect(ix, iy, iw, ih, palette.border);
        r.fillRect(ix + 2, iy + 2, 54, 2, palette.gold);
        r.drawText(ix + 12, iy + 10, "角色 / 背包", palette.gold, 1, false);
        r.drawText(ix + iw - 62, iy + 10, "I 关闭", palette.muted, 1, false);

        const attr_labels = [_][]const u8{ "力量", "敏捷", "体质", "感知", "魔力", "意志" };
        var abuf: [24]u8 = undefined;
        for (attr_labels, 0..) |label, i| {
            const col = @as(i32, @intCast(i % 2));
            const row = @as(i32, @intCast(i / 2));
            const ax = ix + 16 + col * 150;
            const ay = iy + 42 + row * 22;
            r.drawText(ax, ay, label, palette.cream, 1, false);
            const val = fmt(&abuf, "{d}", .{state.attr_values[i]});
            r.drawText(ax + 48, ay, val, palette.gold_light, 1, false);
        }

        r.drawText(ix + 16, iy + 126, "装备", palette.gold, 1, false);
        const slot_labels = [_][]const u8{ "主手", "身体", "饰品" };
        var ebuf: [40]u8 = undefined;
        for (slot_labels, 0..) |label, i| {
            const ey = iy + 148 + @as(i32, @intCast(i)) * 20;
            const name = if (state.equip_names[i].len > 0) state.equip_names[i] else "-";
            const line = fmt(&ebuf, "{s}  {s}", .{ label, name });
            r.drawText(ix + 16, ey, line, palette.cream, 1, false);
        }

        r.drawText(ix + 260, iy + 42, "物品", palette.gold, 1, false);
        if (state.item_count == 0) {
            r.drawText(ix + 260, iy + 64, "空", palette.muted, 1, false);
        } else {
            const n = @min(state.item_count, state.item_names.len);
            for (state.item_names[0..n], 0..) |name, i| {
                r.drawText(ix + 260, iy + 64 + @as(i32, @intCast(i)) * 18, name, palette.cream, 1, false);
            }
        }
        r.drawText(ix + 16, iy + ih - 18, "数字键 1/2/3 装备或替换；掉落自动进入背包", palette.muted, 1, false);
    }

    // victory / defeat overlay
    if (state.victory or state.defeat) {
        const title = if (state.victory) "胜利" else "全灭";
        const sub = "按 R 重开";
        r.fillRect(0, @divTrunc(h, 2) - 28, w, 62, palette.panel);
        r.fillRect(0, @divTrunc(h, 2) - 29, w, 1, palette.gold);
        r.fillRect(0, @divTrunc(h, 2) + 33, w, 1, palette.gold);
        const tw = renderer.Renderer.textWidth(title, 2);
        r.drawText(@divTrunc(w, 2) - @divTrunc(tw, 2), @divTrunc(h, 2) - 22, title, if (state.victory) palette.gold_light else palette.red, 2, true);
        const sw = renderer.Renderer.textWidth(sub, 1);
        r.drawText(@divTrunc(w, 2) - @divTrunc(sw, 2), @divTrunc(h, 2) + 12, sub, palette.cream, 1, true);
    }
}