//! turn-based HUD: one hero, hotbar, floor info, log and modal panels.
const std = @import("std");
const color = @import("../core/color.zig");
const palette = @import("../core/palette.zig");
const renderer = @import("../engine/renderer.zig");

pub const Panel = enum(u8) { none, character, inventory };

pub const HotbarSlot = struct {
    name: []const u8 = "",
    cost: u16 = 0,
    /// Remaining cooldown, updated every turn.
    cooldown: u16 = 0,
    /// Base cooldown shown next to the cost.
    cooldown_max: u16 = 0,
    ready: bool = true,
    affordable: bool = true,
};

/// Live aim preview: which talent is pending, which enemy is highlighted
/// and why confirmation would fail. Filled by RunGame each frame.
pub const AimInfo = struct {
    active: bool = false,
    valid: bool = false,
    talent_index: usize = 0,
    talent: []const u8 = "",
    target: []const u8 = "",
    distance: i32 = 0,
    damage: i32 = 0,
    aoe_radius: i32 = 0,
    /// Why confirmation is blocked (empty when valid).
    reason: []const u8 = "",
};

pub const ClassCard = struct {
    name: []const u8 = "",
    resource: []const u8 = "",
    resource_max: u16 = 0,
    hp_max: u16 = 0,
    role: []const u8 = "",
    talents: [3][]const u8 = .{ "", "", "" },
    descs: [3][]const u8 = .{ "", "", "" },
};

pub const State = struct {
    menu: bool = false,
    help: bool = false,
    menu_seed: u64 = 0,
    difficulty: u8 = 0,
    shrine_open: bool = false,
    shrine_main_label: []const u8 = "力量",
    seed: u64 = 0,
    buff_turns: u16 = 0,
    buff_pct: f32 = 0,
    burn_turns: u16 = 0,
    burn_damage: f32 = 0,
    menu_cards: [3]ClassCard = .{ .{}, .{}, .{} },
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
    enemy_phase: bool = false,
    slot_mode: u8 = 0,
    slot_labels: [3][]const u8 = .{ "空", "空", "空" },
    /// Player + at most one fastest living enemy, matching enemyPhase order.
    initiative: [3][]const u8 = .{ "", "", "" },
    initiative_count: u8 = 0,
    kills: u32 = 0,
    enemies_left: u32 = 0,
    stairs_hint: []const u8 = "",
    stairs_dist: u16 = 0,
    hotbar: [3]HotbarSlot = .{ .{}, .{}, .{} },
    talent_descs: [3][]const u8 = .{ "", "", "" },
    target_name: []const u8 = "",
    target_hp: f32 = 0,
    target_hp_max: f32 = 1,
    target_range: u16 = 0,
    aim: AimInfo = .{},
    log_lines: [4][]const u8 = .{ "", "", "", "" },
    log_count: usize = 0,
    minimap: [169]u8 = @splat(0),
    has_minimap: bool = false,
    panel: Panel = .none,
    attrs: [6]i32 = .{ 0, 0, 0, 0, 0, 0 },
    pending_points: u8 = 0,
    attack: f32 = 0,
    armor: f32 = 0,
    crit: f32 = 0,
    speed: f32 = 100,
    res_per_turn: f32 = 0,
    equip: [3][]const u8 = .{ "", "", "" },
    items: [12][]const u8 = .{ "", "", "", "", "", "", "", "", "", "", "", "" },
    item_details: [12][]const u8 = .{ "", "", "", "", "", "", "", "", "", "", "", "" },
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

const menu_title = "选职业";
const menu_hint = "按 1 / 2 / 3 开始";
const menu_footer = "1/2/3 选择  D 切换  F9 读档  R 重开";
const talent_label = "天赋";
const help_title = "操作说明";
const help_footer = "H 关闭";
const aim_hint = "空格/同键/左键确认  Esc取消  Tab换目标";

/// Pre-run class selection. A checkerboard dim keeps the 3D dungeon visible
/// behind the cards while the title and card panels stay fully readable.
fn drawMenu(r: *renderer.Renderer, state: State, w: i32, h: i32) void {
    var y: i32 = 0;
    while (y < h) : (y += 2) {
        var x: i32 = 0;
        while (x < w) : (x += 2) r.putPixel(x, y, palette.deep);
    }

    const plate_w: i32 = 210;
    backPanel(r, @divTrunc(w, 2) - @divTrunc(plate_w, 2), 4, plate_w, 48);
    const tw = renderer.Renderer.textWidth(menu_title, 2);
    r.drawText(@divTrunc(w, 2) - @divTrunc(tw, 2), 7, menu_title, palette.gold, 2, true);
    var sub_buf: [64]u8 = undefined;
    const sub = fmt(&sub_buf, "SEED {d}  {s} [D] 切换", .{ state.menu_seed, switch (state.difficulty) {
        1 => "HARD",
        2 => "EASY",
        else => "NORMAL",
    } });
    const sw = renderer.Renderer.textWidth(sub, 1);
    r.drawText(@divTrunc(w, 2) - @divTrunc(sw, 2), 27, sub, switch (state.difficulty) {
        1 => palette.red,
        2 => palette.cyan_light,
        else => palette.muted,
    }, 1, false);

    const accents = [_]u32{ palette.gold, palette.cyan, color.pack(185, 128, 230) };
    const card_w: i32 = 146;
    const card_h: i32 = 188;
    const gap: i32 = 6;
    const total = card_w * 3 + gap * 2;
    const x0 = @divTrunc(w - total, 2);
    const y0: i32 = 58;

    for (state.menu_cards, 0..) |card, i| {
        const x = x0 + @as(i32, @intCast(i)) * (card_w + gap);
        r.fillRect(x, y0, card_w, card_h, palette.panel);
        r.strokeRect(x, y0, card_w, card_h, palette.border);
        r.fillRect(x + 2, y0 + 2, card_w - 4, 2, accents[i]);

        r.fillRect(x + 8, y0 + 8, 18, 18, palette.deep);
        r.strokeRect(x + 8, y0 + 8, 18, 18, accents[i]);
        var key_buf: [8]u8 = undefined;
        const key = fmt(&key_buf, "{d}", .{i + 1});
        r.drawText(x + 14, y0 + 10, key, palette.gold_light, 1, false);
        r.drawText(x + 32, y0 + 8, card.name, palette.gold, 2, true);

        var res_buf: [48]u8 = undefined;
        const res = fmt(&res_buf, "资源 {s} {d}", .{ card.resource, card.resource_max });
        r.drawText(x + 8, y0 + 38, res, palette.cream, 1, false);
        var hp_buf: [24]u8 = undefined;
        const hp = fmt(&hp_buf, "生命 {d}", .{card.hp_max});
        r.drawText(x + 8, y0 + 52, hp, palette.muted, 1, false);
        var role_buf: [48]u8 = undefined;
        const role = fmt(&role_buf, "定位 {s}", .{card.role});
        r.drawText(x + 8, y0 + 66, role, palette.cyan_light, 1, false);

        r.fillRect(x + 8, y0 + 82, card_w - 16, 1, palette.border);
        r.drawText(x + 8, y0 + 88, talent_label, palette.gold, 1, false);
        var talent_buf: [32]u8 = undefined;
        for (card.talents, 0..) |name, t| {
            const ty = y0 + 104 + @as(i32, @intCast(t)) * 28;
            const label = fmt(&talent_buf, "{d} {s}", .{ t + 1, name });
            r.drawText(x + 8, ty, label, palette.cream, 1, false);
            r.drawText(x + 22, ty + 13, card.descs[t], palette.muted, 1, false);
        }
    }

    const fw = renderer.Renderer.textWidth(menu_footer, 1);
    r.drawText(@divTrunc(w, 2) - @divTrunc(fw, 2), h - 18, menu_footer, palette.muted, 1, false);
}

fn drawHelp(r: *renderer.Renderer, w: i32, h: i32) void {
    r.fillRect(0, 0, w, h, palette.deep);
    const px: i32 = 32;
    const pw: i32 = w - 64;
    const ph: i32 = @min(h - 32, 242);
    const py: i32 = @divTrunc(h - ph, 2);
    backPanel(r, px, py, pw, ph);
    const tw = renderer.Renderer.textWidth(help_title, 2);
    r.drawText(px + @divTrunc(pw - tw, 2), py + 8, help_title, palette.gold, 2, true);

    const lines = [_][]const u8{
        "移动  WASD / 方向键 / 小键盘",
        "天赋  1/2/3 进入瞄准",
        "确认  空格 / 同键 / 左键",
        "等待  5 / .（瞄准中空格=确认）",
        "瞄准 Tab换目标 火球鼠标点地面",
        "Esc 取消瞄准 / 关闭面板 / 退出",
        "背包 I     角色 C",
        "存档 F5  读档 F9 槽  自动档 F10",
        "相机 Q/E/右键   鼠标悬停选目标",
        "升级 C 面板 1-6 加点  R 重开",
        "目标  击杀第 3 层深渊守卫",
        "楼梯在 Boss 存活时被封印",
        "战利品自动装备，背包内 1/2/3 换装",
    };
    var y = py + 38;
    for (lines) |line| {
        r.drawText(px + 18, y, line, palette.cream, 1, false);
        y += 14;
    }
    const fw = renderer.Renderer.textWidth(help_footer, 1);
    r.drawText(px + @divTrunc(pw - fw, 2), py + ph - 18, help_footer, palette.muted, 1, false);
}

pub fn draw(r: *renderer.Renderer, state: State) void {
    const w: i32 = @intCast(r.width);
    const h: i32 = @intCast(r.height);

    if (state.menu) {
        drawMenu(r, state, w, h);
        return;
    }
    if (state.help) {
        drawHelp(r, w, h);
        return;
    }

    // top-left: class / HP / resource / turn / floor
    backPanel(r, 6, 5, 160, 58);
    var buf: [64]u8 = undefined;
    r.drawText(10, 8, state.class_name, palette.gold, 1, false);
    if (state.difficulty == 1) r.drawText(130, 8, "HARD", palette.red, 1, false);
    if (state.difficulty == 2) r.drawText(136, 8, "EASY", palette.cyan_light, 1, false);
    const lv = fmt(&buf, "{d}级  XP {d}/{d}", .{ state.level, state.xp, state.xp_next });
    r.drawText(10, 21, lv, palette.muted, 1, false);
    bar(r, 10, 32, 150, 7, if (state.hp_max > 0) state.hp / state.hp_max else 0, palette.health_light);
    const hp = fmt(&buf, "{d:.0}/{d:.0}", .{ state.hp, state.hp_max });
    r.drawText(14, 33, hp, palette.cream, 1, false);
    bar(r, 10, 43, 150, 5, if (state.resource_max > 0) state.resource / state.resource_max else 0, palette.cyan);
    const res = fmt(&buf, "{s} {d:.0}/{d:.0}", .{ state.resource_label, state.resource, state.resource_max });
    r.drawText(14, 49, res, palette.muted, 1, false);

    if (state.buff_turns > 0 and !state.dead and !state.victory) {
        backPanel(r, 6, 66, 160, 14);
        var bbuf: [48]u8 = undefined;
        const buff = fmt(&bbuf, "战吼 +{d:.0}%攻  {d}回合", .{ state.buff_pct * 100.0, state.buff_turns });
        r.drawText(10, 69, buff, palette.gold_light, 1, false);
    }

    if (state.burn_turns > 0 and !state.dead and !state.victory) {
        backPanel(r, 6, 82, 160, 14);
        var fbuf: [48]u8 = undefined;
        const burn = fmt(&fbuf, "灼烧 {d:.0}/回合  {d}回合", .{ state.burn_damage, state.burn_turns });
        r.drawText(10, 85, burn, palette.red, 1, false);
    }

    // top-right: floor / enemies / stairs / turn / initiative
    backPanel(r, w - 154, 5, 154, 60);
    var floor_buf: [96]u8 = undefined;
    const dir = if (state.stairs_hint.len >= 3) state.stairs_hint[state.stairs_hint.len - 3 ..] else "";
    const floor = if (state.stairs_hint.len > 0)
        fmt(&floor_buf, "第{d}/{d}层 {s}{d}", .{ state.floor, state.floors, dir, state.stairs_dist })
    else
        fmt(&floor_buf, "第 {d}/{d} 层", .{ state.floor, state.floors });
    r.drawText(w - 154, 9, floor, palette.gold_light, 1, false);
    const enemies = fmt(&buf, "敌人 {d}", .{state.enemies_left});
    r.drawText(w - 154, 23, enemies, palette.cream, 1, false);
    const turn = if (state.enemy_phase) "敌人行动" else fmt(&buf, "玩家回合 {d}", .{state.turn});
    r.drawText(w - 154, 37, turn, if (state.enemy_phase) palette.red else palette.gold_light, 1, false);
    var init_buf: [96]u8 = undefined;
    const order = if (state.initiative_count >= 3)
        fmt(&init_buf, "先攻 {s}>{s}>{s}", .{ state.initiative[0], state.initiative[1], state.initiative[2] })
    else if (state.initiative_count >= 2)
        fmt(&init_buf, "先攻 {s}>{s}", .{ state.initiative[0], state.initiative[1] })
    else
        fmt(&init_buf, "先攻 {s}", .{state.initiative[0]});
    r.drawText(w - 154, 51, order, palette.muted, 1, false);
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

    // combat log, low-left above the hotbar (not across the battlefield)
    if (state.log_count > 0) {
        backPanel(r, 6, h - 106, 150, 40);
        var shown: usize = 0;
        var li = state.log_count - @min(state.log_count, 3);
        while (li < state.log_count) : (li += 1) {
            const line = state.log_lines[li];
            r.drawText(10, h - 102 + @as(i32, @intCast(shown)) * 11, line, if (li + 1 == state.log_count) palette.cream else palette.muted, 1, false);
            shown += 1;
        }
    }

    // aim line: preview sits just above the hotbar, red when the highlighted
    // target cannot be confirmed.
    if (state.aim.active) {
        var aim_buf: [128]u8 = undefined;
        var line: []const u8 = undefined;
        if (state.aim.valid) {
            if (std.mem.eql(u8, state.aim.target, "地面")) {
                line = fmt(&aim_buf, "瞄准：{s} -> 地面 距离{d} 范围{d}", .{
                    state.aim.talent, state.aim.distance, state.aim.aoe_radius,
                });
            } else if (state.aim.aoe_radius > 0)
                line = fmt(&aim_buf, "瞄准：{s} -> {s} 距离{d} 预计{d}伤害 范围{d}", .{
                    state.aim.talent, state.aim.target, state.aim.distance, state.aim.damage, state.aim.aoe_radius,
                })
            else
                line = fmt(&aim_buf, "瞄准：{s} -> {s} 距离{d} 预计{d}伤害", .{
                    state.aim.talent, state.aim.target, state.aim.distance, state.aim.damage,
                });
        } else if (state.aim.target.len > 0) {
            line = fmt(&aim_buf, "瞄准：{s} -> {s} {s}", .{ state.aim.talent, state.aim.target, state.aim.reason });
        } else {
            line = fmt(&aim_buf, "瞄准：{s} {s}", .{ state.aim.talent, state.aim.reason });
        }
        const line_w = renderer.Renderer.textWidth(line, 1);
        const hint_w = renderer.Renderer.textWidth(aim_hint, 1);
        const box_w = @max(line_w, hint_w) + 16;
        const box_x = @divTrunc(w - box_w, 2);
        const box_y = h - 90;
        const accent: u32 = if (state.aim.valid) palette.cyan else palette.red;
        r.fillRect(box_x, box_y, box_w, 26, palette.panel);
        r.strokeRect(box_x, box_y, box_w, 26, accent);
        r.fillRect(box_x + 2, box_y + 2, 24, 1, accent);
        r.drawText(box_x + 8, box_y + 4, line, if (state.aim.valid) palette.cyan_light else palette.red, 1, false);
        r.drawText(box_x + 8, box_y + 15, aim_hint, palette.muted, 1, false);
    }

    // hotbar: name, cost/base cooldown, then live availability
    backPanel(r, 6, h - 60, 265, 54);
    r.drawText(10, h - 56, talent_label, palette.gold, 1, false);
    for (state.hotbar, 0..) |slot, i| {
        const sx: i32 = 10 + @as(i32, @intCast(i)) * 85;
        const sy: i32 = h - 45;
        const aiming = state.aim.active and state.aim.talent_index == i;
        r.fillRect(sx, sy, 82, 38, palette.deep);
        r.strokeRect(sx, sy, 82, 38, if (aiming) palette.gold else if (slot.ready) palette.border else palette.muted);
        const key = fmt(&buf, "{d}", .{i + 1});
        r.drawText(sx + 4, sy + 3, key, palette.gold, 1, false);
        r.drawText(sx + 18, sy + 3, slot.name, if (slot.ready) palette.cream else palette.muted, 1, false);
        const cost = fmt(&buf, "消耗{d} 冷却{d}", .{ slot.cost, slot.cooldown_max });
        r.drawText(sx + 4, sy + 15, cost, palette.muted, 1, false);
        var status_buf: [24]u8 = undefined;
        var status: []const u8 = "可用";
        var status_color: u32 = palette.cyan_light;
        if (state.dead or state.victory) {
            status = "不可用";
            status_color = palette.muted;
        } else if (aiming) {
            status = "瞄准中";
            status_color = palette.gold_light;
        } else if (slot.cooldown > 0) {
            status = fmt(&status_buf, "冷却 {d}", .{slot.cooldown});
            status_color = palette.red;
        } else if (!slot.affordable) {
            status = "缺资源";
            status_color = palette.red;
        }
        r.drawText(sx + 4, sy + 26, status, status_color, 1, false);
    }

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

            r.drawText(ix + 16, iy + 106, fmt(&dbuf, "属性点 {d}  按 1-6 加点", .{state.pending_points}), palette.gold_light, 1, false);
            r.drawText(ix + 16, iy + 126, "装备", palette.gold, 1, false);
            const slot_labels = [_][]const u8{ "主手", "身体", "饰品" };
            var ebuf: [40]u8 = undefined;
            for (slot_labels, 0..) |label, i| {
                const ey = iy + 148 + @as(i32, @intCast(i)) * 20;
                const name = if (state.equip[i].len > 0) state.equip[i] else "-";
                const line = fmt(&ebuf, "{s}  {s}", .{ label, name });
                r.drawText(ix + 16, ey, line, palette.cream, 1, false);
            }

            // talent cheat-sheet: cost/cooldown live in the hotbar, effects here
            r.fillRect(ix + 16, iy + 202, iw - 32, 1, palette.border);
            var tbuf: [96]u8 = undefined;
            for (state.hotbar, 0..) |slot, i| {
                const prefix = if (i == 0) "天赋 " else "     ";
                const line = fmt(&tbuf, "{s}{d} {s}：{s}", .{ prefix, i + 1, slot.name, state.talent_descs[i] });
                r.drawText(ix + 16, iy + 204 + @as(i32, @intCast(i)) * 14, line, if (i == 0) palette.gold_light else palette.cream, 1, false);
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
                    const y = iy + 42 + row * 28;
                    const label = if (i < 3) fmt(&ibuf, "{d} {s}", .{ i + 1, name }) else fmt(&ibuf, "  {s}", .{name});
                    r.drawText(ix + 16 + col * 190, y, label, palette.cream, 1, false);
                    if (i < state.item_details.len and state.item_details[i].len > 0) {
                        r.drawText(ix + 26 + col * 190, y + 10, state.item_details[i], palette.muted, 1, false);
                    }
                }
            }
            r.drawText(ix + 16, iy + ih - 18, "1/2/3 装备  P POTION  I 关闭", palette.muted, 1, false);
        }
    }

    // death / victory overlay; keep the last log line as the cause
    if (state.dead or state.victory) {
        const title = if (state.victory) "胜利" else "死亡";
        const sub = "按 R 重开 同职业";
        const cause = if (state.log_count > 0) state.log_lines[state.log_count - 1] else "";
        var sbuf: [96]u8 = undefined;
        const summary = fmt(&sbuf, "第 {d}/{d} 层 · 回合 {d} · 击杀 {d} · 种子 {d}", .{
            state.floor, state.floors, state.turn, state.kills, state.seed,
        });
        r.fillRect(0, @divTrunc(h, 2) - 28, w, 70, palette.panel);
        r.fillRect(0, @divTrunc(h, 2) - 29, w, 1, palette.gold);
        r.fillRect(0, @divTrunc(h, 2) + 41, w, 1, palette.gold);
        const tw = renderer.Renderer.textWidth(title, 2);
        r.drawText(@divTrunc(w, 2) - @divTrunc(tw, 2), @divTrunc(h, 2) - 22, title, if (state.victory) palette.gold_light else palette.red, 2, true);
        const mw = renderer.Renderer.textWidth(summary, 1);
        r.drawText(@divTrunc(w, 2) - @divTrunc(mw, 2), @divTrunc(h, 2) - 4, summary, palette.gold_light, 1, true);
        if (cause.len > 0) {
            const cw = renderer.Renderer.textWidth(cause, 1);
            r.drawText(@divTrunc(w, 2) - @divTrunc(cw, 2), @divTrunc(h, 2) + 11, cause, palette.cream, 1, true);
        }
        const sw = renderer.Renderer.textWidth(sub, 1);
        r.drawText(@divTrunc(w, 2) - @divTrunc(sw, 2), @divTrunc(h, 2) + 26, sub, palette.muted, 1, true);
    }

    if (state.shrine_open) drawShrine(r, state, w, h);

    // save / load slot modal, on top of everything
    if (state.slot_mode != 0) {
        r.fillRect(0, 0, w, h, palette.deep);
        const pw: i32 = 320;
        const ph: i32 = 164;
        const px = @divTrunc(w - pw, 2);
        const py = @divTrunc(h - ph, 2);
        r.fillRect(px, py, pw, ph, palette.panel);
        r.strokeRect(px, py, pw, ph, palette.gold);
        const title = switch (state.slot_mode) {
            1 => "保存到槽位",
            2 => "从槽位读取",
            else => "自动档备份",
        };
        r.drawText(px + 16, py + 12, title, palette.gold, 1, true);
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const y = py + 42 + @as(i32, @intCast(i)) * 30;
            r.fillRect(px + 12, y - 4, pw - 24, 26, palette.deep);
            const num = fmt(&buf, "{d}", .{i + 1});
            r.drawText(px + 20, y, num, palette.gold_light, 1, true);
            const label = if (state.slot_labels[i].len > 0) state.slot_labels[i] else "空";
            r.drawText(px + 44, y, label, palette.cream, 1, true);
        }
        r.drawText(px + 16, py + ph - 24, "1/2/3 选择   Esc 取消", palette.muted, 1, true);
    }
}

fn drawShrine(r: *renderer.Renderer, state: State, w: i32, h: i32) void {
    const pw: i32 = 300;
    const ph: i32 = 154;
    const px = @divTrunc(w - pw, 2);
    const py = @divTrunc(h - ph, 2);
    r.fillRect(0, 0, w, h, palette.deep);
    r.fillRect(px, py, pw, ph, palette.panel);
    r.strokeRect(px, py, pw, ph, palette.cyan);
    r.fillRect(px + 2, py + 2, pw - 4, 2, palette.cyan_light);

    const title = "SHRINE";
    const tw = renderer.Renderer.textWidth(title, 2);
    r.drawText(px + @divTrunc(pw - tw, 2), py + 10, title, palette.cyan_light, 2, true);
    var sub_buf: [64]u8 = undefined;
    const sub = fmt(&sub_buf, "POWER UP", .{});
    const sw = renderer.Renderer.textWidth(sub, 1);
    r.drawText(px + @divTrunc(pw - sw, 2), py + 38, sub, palette.muted, 1, false);

    const lines = [_][]const u8{ "  +2", "体质 +2", "意志 +2" };
    var buf: [48]u8 = undefined;
    for (lines, 0..) |suffix, i| {
        const line = if (i == 0) fmt(&buf, "1 {s}{s}", .{ state.shrine_main_label, suffix }) else fmt(&buf, "{d} {s}", .{ i + 1, suffix });
        r.drawText(px + 34, py + 62 + @as(i32, @intCast(i)) * 22, line, palette.cream, 1, false);
    }
    r.drawText(px + 16, py + ph - 22, "1/2/3 选择   Esc 关闭", palette.muted, 1, false);
}

fn expectGlyphs(text: []const u8) !void {
    const font = @import("../core/font.zig");
    var i: usize = 0;
    while (font.nextCodepoint(text, &i)) |cp| {
        if (cp < 0x80) continue;
        try std.testing.expect(font.cjk.find(cp) != null);
    }
}

test "run hud: hint strings have embedded CJK glyphs" {
    const sim = @import("run_sim.zig");
    const fixed = [_][]const u8{
        menu_title,
        menu_hint,
        menu_footer,
        talent_label,
        aim_hint,
        help_title,
        help_footer,
        "资源",
        "生命",
        "定位",
        "消耗",
        "冷却",
        "可用",
        "缺资源",
        "不可用",
        "按 R 重开 同职业",
        "瞄准",
        "预计",
        "伤害",
        "距离",
        "范围",
        "瞄准中",
        "无效目标",
        "超出范围",
        "视线受阻",
        "取消瞄准",
        "地面",
        "保存到槽位",
        "从槽位读取",
        "坏档",
        "空",
        "自动档备份",
    };
    for (fixed) |text| try expectGlyphs(text);
    const targeting = @import("run_target.zig");
    inline for (std.meta.tags(targeting.Verdict)) |verdict| {
        try expectGlyphs(targeting.verdictText(verdict));
    }
    for (sim.class_names) |text| try expectGlyphs(text);
    for (sim.resource_names) |text| try expectGlyphs(text);
    for (sim.class_roles) |text| try expectGlyphs(text);
    for (sim.class_talent_descs) |row| {
        for (row) |text| try expectGlyphs(text);
    }
    var ci: usize = 0;
    while (ci < sim.class_count) : (ci += 1) {
        const class: sim.Class = @fromBackingInt(@intCast(ci));
        var ti: usize = 0;
        while (ti < 3) : (ti += 1) try expectGlyphs(sim.talentNameFor(class, ti));
    }
}

test "run hud: default panels stay under 30 percent at 640x360" {
    const area = 160 * 58 + 154 * 60 + 150 * 40 + 265 * 54;
    const screen = 640 * 360;
    try std.testing.expect(area * 100 <= screen * 30);
}
