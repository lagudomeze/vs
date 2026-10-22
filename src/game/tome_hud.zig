//! ToME4-style turn-based HUD: one hero, hotbar, floor info, log and modal panels.
const std = @import("std");
const palette = @import("../core/palette.zig");
const renderer = @import("../engine/renderer.zig");

pub const Panel = enum(u8) { none, character, inventory };

pub const HotbarSlot = struct {
    name: []const u8 = "",
    cost: u16 = 0,
    cooldown: u16 = 0,
    ready: bool = true,
};

pub const State = struct {
    class_name: []const u8 = "",
    level: u16 = 1,
    xp: u32 = 0,
    xp_next: u32 = 100,
    hp: f32 = 1,
    hp_max: f32 = 1,
    resource: f32 = 0,
    resource_max: f32 = 1,
    resource_label: []const u8 = "精力",
    turn: u32 = 1,
    floor: u8 = 1,
    floors: u8 = 3,
    kills: u32 = 0,
    enemies_left: u32 = 0,
    stairs_hint: []const u8 = "",
    hotbar: [3]HotbarSlot = .{ .{}, .{}, .{} },
    target_name: []const u8 = "",
    target_hp: f32 = 0,
    target_hp_max: f32 = 1,
    target_range: u16 = 0,
    log_lines: [4][]const u8 = .{ "", "", "", "" },
    log_count: usize = 0,
    minimap: [169]u8 = @splat(0),
    has_minimap: bool = false,
    panel: Panel = .none,
    attrs: [6]i32 = .{ 0, 0, 0, 0, 0, 0 },
    attack: f32 = 0,
    armor: f32 = 0,
    crit: f32 = 0,
    speed: f32 = 100,
    res_per_turn: f32 = 0,
    equip: [3][]const u8 = .{ "", "", "" },
    items: [12][]const u8 = .{ "", "", "", "", "", "", "", "", "", "", "", "" },
    item_count: usize = 0,
    dead: bool = false,
    victory: bool = false,
};

fn backPanel(r: *renderer.Renderer, x: i32, y: i32, w: i32, h: i32) void {
    r.fillRect(x, y, w, h, palette.panel);
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

pub fn draw(r: *renderer.Renderer, state: State) void {
    const w: i32 = @intCast(r.width);
    const h: i32 = @intCast(r.height);

    // top-left: class / HP / resource / turn / floor
    backPanel(r, 6, 5, 190, 60);
    var buf: [64]u8 = undefined;
    r.drawText(10, 8, state.class_name, palette.gold, 1, false);
    const lv = fmt(&buf, "{d}级  XP {d}/{d}", .{ state.level, state.xp, state.xp_next });
    r.drawText(10, 22, lv, palette.muted, 1, false);
    bar(r, 10, 34, 180, 7, if (state.hp_max > 0) state.hp / state.hp_max else 0, palette.health_light);
    const hp = fmt(&buf, "{d:.0}/{d:.0}", .{ state.hp, state.hp_max });
    r.drawText(14, 35, hp, palette.cream, 1, false);
    bar(r, 10, 45, 180, 5, if (state.resource_max > 0) state.resource / state.resource_max else 0, palette.cyan);
    const res = fmt(&buf, "{s} {d:.0}/{d:.0}", .{ state.resource_label, state.resource, state.resource_max });
    r.drawText(14, 52, res, palette.muted, 1, false);

    // top-right: floor / enemies / stairs
    backPanel(r, w - 160, 5, 154, 48);
    const floor = fmt(&buf, "第 {d}/{d} 层", .{ state.floor, state.floors });
    r.drawText(w - 154, 9, floor, palette.gold_light, 1, false);
    const enemies = fmt(&buf, "敌人 {d}", .{state.enemies_left});
    r.drawText(w - 154, 23, enemies, palette.cream, 1, false);
    if (state.stairs_hint.len > 0) r.drawText(w - 154, 37, state.stairs_hint, palette.muted, 1, false);
    if (state.has_minimap) {
        const mx0 = w - 40;
        const my0 = 8;
        var my: usize = 0;
        while (my < 13) : (my += 1) {
            var mx: usize = 0;
            while (mx < 13) : (mx += 1) {
                const cell = state.minimap[my * 13 + mx];
                const c: u32 = switch (cell) {
                    1 => palette.muted,
                    2 => palette.cyan,
                    3 => palette.gold,
                    4 => palette.cream,
                    5 => palette.red,
                    else => palette.deep,
                };
                r.fillRect(mx0 + @as(i32, @intCast(mx)) * 2, my0 + @as(i32, @intCast(my)) * 2, 2, 2, c);
            }
        }
        r.strokeRect(mx0, my0, 26, 26, palette.border);
    }

    // top-centre target
    if (state.target_name.len > 0) {
        backPanel(r, 200, 5, 114, 48);
        r.drawText(204, 9, state.target_name, palette.red, 1, false);
        bar(r, 204, 23, 106, 5, if (state.target_hp_max > 0) state.target_hp / state.target_hp_max else 0, palette.red);
        const range = fmt(&buf, "距离 {d}", .{state.target_range});
        r.drawText(204, 33, range, palette.muted, 1, false);
    }

    // combat log
    if (state.log_count > 0) {
        backPanel(r, 6, 122, 190, 54);
        for (state.log_lines, 0..) |line, i| {
            if (i >= state.log_count) break;
            r.drawText(10, 126 + @as(i32, @intCast(i)) * 12, line, if (i + 1 == state.log_count) palette.cream else palette.muted, 1, false);
        }
    }

    // hotbar
    backPanel(r, 6, h - 60, 300, 54);
    r.drawText(10, h - 56, "天赋", palette.gold, 1, false);
    for (state.hotbar, 0..) |slot, i| {
        const sx: i32 = 10 + @as(i32, @intCast(i)) * 96;
        const sy: i32 = h - 40;
        r.fillRect(sx, sy, 90, 32, palette.deep);
        r.strokeRect(sx, sy, 90, 32, if (slot.ready) palette.border else palette.muted);
        const key = fmt(&buf, "{d}", .{i + 1});
        r.drawText(sx + 4, sy + 3, key, palette.gold, 1, false);
        r.drawText(sx + 18, sy + 3, slot.name, if (slot.ready) palette.cream else palette.muted, 1, false);
        const cost = fmt(&buf, "{d}  冷却{d}", .{ slot.cost, slot.cooldown });
        r.drawText(sx + 4, sy + 18, cost, if (slot.ready) palette.cyan_light else palette.red, 1, false);
    }

    // bottom-right controls
    backPanel(r, w - 160, h - 60, 154, 54);
    r.drawText(w - 154, h - 56, "I 背包   C 角色", palette.cream, 1, false);
    r.drawText(w - 154, h - 42, "Q/E 视角  TAB 目标", palette.muted, 1, false);
    const turn = fmt(&buf, "R 重开  回合 {d}", .{state.turn});
    r.drawText(w - 154, h - 26, turn, palette.gold_light, 1, false);

    // modal character / inventory
    if (state.panel != .none) {
        r.fillRect(0, 0, w, h, palette.deep);
        const ix: i32 = 16;
        const iy: i32 = 12;
        const iw: i32 = w - 32;
        const ih: i32 = h - 24;
        r.fillRect(ix, iy, iw, ih, palette.panel);
        r.strokeRect(ix, iy, iw, ih, palette.border);
        r.fillRect(ix + 2, iy + 2, 54, 2, palette.gold);
        const title = if (state.panel == .inventory) "背包" else "角色";
        r.drawText(ix + 12, iy + 10, title, palette.gold, 1, false);
        r.drawText(ix + iw - 62, iy + 10, "关闭", palette.muted, 1, false);

        if (state.panel == .character) {
            const labels = [_][]const u8{ "力量", "敏捷", "体质", "感知", "魔力", "意志" };
            var abuf: [24]u8 = undefined;
            for (labels, 0..) |label, i| {
                const col = @as(i32, @intCast(i % 2));
                const row = @as(i32, @intCast(i / 2));
                const ax = ix + 16 + col * 150;
                const ay = iy + 42 + row * 22;
                r.drawText(ax, ay, label, palette.cream, 1, false);
                const val = fmt(&abuf, "{d}", .{state.attrs[i]});
                r.drawText(ax + 48, ay, val, palette.gold_light, 1, false);
            }
            var dbuf: [40]u8 = undefined;
            r.drawText(ix + 278, iy + 42, "战斗", palette.gold, 1, false);
            r.drawText(ix + 278, iy + 64, fmt(&dbuf, "生命 {d:.0}/{d:.0}", .{ state.hp, state.hp_max }), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 84, fmt(&dbuf, "{s} {d:.0}/{d:.0}", .{ state.resource_label, state.resource, state.resource_max }), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 104, fmt(&dbuf, "攻击 {d:.0}", .{state.attack}), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 124, fmt(&dbuf, "护甲 {d:.0}", .{state.armor}), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 144, fmt(&dbuf, "暴击 {d:.0}%", .{state.crit * 100.0}), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 164, fmt(&dbuf, "速度 {d:.0}", .{state.speed}), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 184, fmt(&dbuf, "回复 {d:.1}/回合", .{state.res_per_turn}), palette.cream, 1, false);

            r.drawText(ix + 16, iy + 126, "装备", palette.gold, 1, false);
            const slot_labels = [_][]const u8{ "主手", "身体", "饰品" };
            var ebuf: [40]u8 = undefined;
            for (slot_labels, 0..) |label, i| {
                const ey = iy + 148 + @as(i32, @intCast(i)) * 20;
                const name = if (state.equip[i].len > 0) state.equip[i] else "-";
                const line = fmt(&ebuf, "{s}  {s}", .{ label, name });
                r.drawText(ix + 16, ey, line, palette.cream, 1, false);
            }
        } else {
            if (state.item_count == 0) {
                r.drawText(ix + 16, iy + 42, "背包是空的", palette.muted, 1, false);
            } else {
                const n = @min(state.item_count, state.items.len);
                var ibuf: [48]u8 = undefined;
                for (state.items[0..n], 0..) |name, i| {
                    const col = @as(i32, @intCast(i % 2));
                    const row = @as(i32, @intCast(i / 2));
                    const label = if (i < 3) fmt(&ibuf, "{d} {s}", .{ i + 1, name }) else fmt(&ibuf, "  {s}", .{name});
                    r.drawText(ix + 16 + col * 190, iy + 42 + row * 20, label, palette.cream, 1, false);
                }
            }
            r.drawText(ix + 16, iy + ih - 18, "数字键 1/2/3 装备；I 关闭", palette.muted, 1, false);
        }
    }

    // death / victory overlay
    if (state.dead or state.victory) {
        const title = if (state.victory) "胜利" else "死亡";
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
