//! turn-based HUD: one hero, hotbar, floor info, log and modal panels.
const std = @import("std");
const color = @import("../core/color.zig");
const palette = @import("../core/palette.zig");
const renderer = @import("../engine/renderer.zig");
const settings_mod = @import("settings.zig");
const i18n = @import("i18n.zig");

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
    potions: u8 = 0,
    bombs: u8 = 0,
    floor_mod_label: []const u8 = "",
    record_wins: u32 = 0,
    record_best_floor: u8 = 1,
    record_best_turn: u32 = 0,
    record_best_kills: u32 = 0,
    record_best_gold: u32 = 0,
    record_wins_warrior: u32 = 0,
    record_wins_mage: u32 = 0,
    record_wins_chronomancer: u32 = 0,
    record_chunk_clears: u32 = 0,
    record_flawless: u32 = 0,
    gold: u32 = 0,
    shop_open: bool = false,
    settings_open: bool = false,
    settings_fullscreen: bool = false,
    settings_vsync: bool = true,
    settings_scale: u8 = 3,
    settings_volume: f32 = 0.55,
    settings_ambient: bool = true,
    settings_pad_swap: bool = false,
    settings_esdf: bool = false,
    keys_mode: bool = false,
    keys_index: u8 = 0,
    keys_error: bool = false,
    settings_chunks: bool = false,
    settings_shake: bool = true,
    chunk_map_open: bool = false,
    chunk: u8 = 4,
    chunk_visited: [9]bool = @splat(false),
    chunk_cleared: [9]bool = @splat(false),
    demo_end: bool = false,
    demo: bool = false,
    language: u8 = 0,
    pause_open: bool = false,
    pause_confirm_quit: bool = false,
    badges_open: bool = false,
    daily: bool = false,
    daily_best_floor: u8 = 0,
    victory_hold: bool = false,
    boss_active: bool = false,
    boss_hp: f32 = 0,
    boss_hp_max: f32 = 1,
    boss_enraged: bool = false,
    toast: []const u8 = "",
    seed: u64 = 0,
    buff_turns: u16 = 0,
    buff_pct: f32 = 0,
    burn_turns: u16 = 0,
    burn_damage: f32 = 0,
    burn_stacks: u8 = 0,
    vulnerable_turns: u16 = 0,
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
    stairs_dir: u8 = 0,
    stairs_dist: u16 = 0,
    hotbar: [3]HotbarSlot = .{ .{}, .{}, .{} },
    talent_descs: [3][]const u8 = .{ "", "", "" },
    target_name: []const u8 = "",
    target_hp: f32 = 0,
    target_hp_max: f32 = 1,
    target_range: u16 = 0,
    aim: AimInfo = .{},
    log_lines: [4][]const u8 = .{ "", "", "", "" },
    log_translated: [4][96]u8 = undefined,
    log_count: usize = 0,
    minimap: [169]u8 = @splat(0),
    has_minimap: bool = false,
    chunks_enabled: bool = false,
    chunk_x: i8 = 1,
    chunk_y: i8 = 1,
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
    item_deltas: [12]i16 = @splat(0),
    item_delta_valid: [12]bool = @splat(false),
    item_delta_new: [12]bool = @splat(false),
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
const menu_footer = "1/2/3 选择  D 切换  F6 DAILY  F8 SEED  F9 读档  R 重开";
const talent_label = "天赋";
const help_title = "操作说明";
const help_footer = "H CLOSE   PAD A OK  B BACK";

/// Single source of truth for the in-game controls panel. A test asserts that
/// the new core verbs (potion / shop / shrine / BUFF) are present, so README
/// and HUD cannot silently drift again.
const help_lines = [_][]const u8{
    "移动  WASD / 方向键 / 小键盘",
    "天赋  1/2/3 瞄准，空格/同键确认",
    "等待  5 / .     背包 I     角色 C",
    "P POTION  anytime, no cost at full",
    "SHOP/SHRINE  1-6 select",
    "Esc 取消/暂停   Q 暂停菜单退出",
    "存档 F5  读档 F9 槽  自动档 F10",
    "相机 Q/E/右键   滚轮 WHEEL ZOOM   M CHUNK MAP",
    "升级 C 面板 1-6 加点  R 重开",
    "目标  击杀第 3 层深渊守卫",
    "楼梯在 Boss 存活时被封印",
    "战利品自动装备，背包内 1/2/3 换装",
    "状态 STUN/SLOW/BURN/VULN/GUARD/BUFF",
    "BURN max 3 stacks; VULN +20% dmg",
    "ENEMY: GOLEM QUAKE / WRAITH DRAIN / SKEL GUARD",
    "F2 SETTINGS  F3 FEEDBACK+DIAG  F11 FULL  F12 SHOT",
};
const help_lines_en = [_][]const u8{
    "MOVE  WASD / ARROWS / NUMPAD",
    "TALENTS  1/2/3 AIM, SPACE/SAME KEY CONFIRM",
    "WAIT  5 / .      INVENTORY I      CHARACTER C",
    "P POTION  anytime, no cost at full",
    "SHOP/SHRINE  1-6 select",
    "ESC CANCEL/PAUSE   Q QUIT FROM PAUSE",
    "SAVE F5  LOAD F9 SLOTS  AUTOSAVE F10",
    "CAMERA Q/E/RIGHT-DRAG  WHEEL ZOOM  M CHUNK MAP",
    "LEVEL C PANEL 1-6 SPEND  R RESTART",
    "GOAL  KILL THE FLOOR-3 ABYSS WARDEN",
    "STAIRS ARE SEALED WHILE THE BOSS LIVES",
    "LOOT AUTO-EQUIPS; 1/2/3 IN INVENTORY",
    "STATUS STUN/SLOW/BURN/VULN/GUARD/BUFF",
    "BURN max 3 stacks; VULN +20% dmg",
    "ENEMY: GOLEM QUAKE / WRAITH DRAIN / SKEL GUARD",
    "F2 SETTINGS  F3 FEEDBACK+DIAG  F11 FULL  F12 SHOT",
};
const aim_hint = "空格/同键/左键确认  Esc取消  Tab换目标";

/// Pre-run class selection. A checkerboard dim keeps the 3D dungeon visible
/// behind the cards while the title and card panels stay fully readable.
fn drawBadges(r: *renderer.Renderer, state: State, w: i32, h: i32) void {
    r.fillRect(0, 0, w, h, palette.deep);
    const pw: i32 = 360;
    const ph: i32 = 270;
    const px = @divTrunc(w - pw, 2);
    const py = @divTrunc(h - ph, 2);
    backPanel(r, px, py, pw, ph);
    const title = "BADGES";
    const tw = renderer.Renderer.textWidth(title, 2);
    r.drawText(px + @divTrunc(pw - tw, 2), py + 18, title, palette.gold_light, 2, true);
    const all_classes = state.record_wins_warrior > 0 and state.record_wins_mage > 0 and state.record_wins_chronomancer > 0;
    const rows = [_]struct { ok: bool, name: []const u8, desc: []const u8 }{
        .{ .ok = state.record_wins > 0, .name = "FIRST WIN", .desc = "Win any run" },
        .{ .ok = all_classes, .name = "ALL CLASSES", .desc = "Win with all three classes" },
        .{ .ok = state.record_flawless > 0, .name = "FLAWLESS", .desc = "Win at full HP" },
        .{ .ok = state.record_chunk_clears >= 9, .name = "CHUNK HUNTER", .desc = "Clear 9 chunks" },
        .{ .ok = state.daily_best_floor >= 3, .name = "DAILY DELVER", .desc = "Reach floor 3 in a daily" },
    };
    for (rows, 0..) |row, i| {
        const y = py + 58 + @as(i32, @intCast(i)) * 34;
        r.drawText(px + 24, y, if (row.ok) "[X]" else "[ ]", if (row.ok) palette.gold else palette.muted, 1, false);
        r.drawText(px + 58, y, row.name, if (row.ok) palette.cream else palette.muted, 1, false);
        r.drawText(px + 58, y + 14, row.desc, palette.muted, 1, false);
    }
    r.drawText(px + 24, py + ph - 22, "F7 / ESC CLOSE", palette.gold, 1, false);
}

fn drawPause(r: *renderer.Renderer, state: State, w: i32, h: i32) void {
    r.fillRect(0, 0, w, h, palette.deep);
    const pw: i32 = 260;
    const ph: i32 = 150;
    const px = @divTrunc(w - pw, 2);
    const py = @divTrunc(h - ph, 2);
    backPanel(r, px, py, pw, ph);
    const title = "PAUSED";
    const tw = renderer.Renderer.textWidth(title, 2);
    r.drawText(px + @divTrunc(pw - tw, 2), py + 20, title, palette.gold_light, 2, true);
    r.drawText(px + 30, py + 64, "ESC  RESUME", palette.cream, 1, false);
    r.drawText(px + 30, py + 84, "F2   SETTINGS", palette.cream, 1, false);
    if (state.pause_confirm_quit) {
        r.drawText(px + 30, py + 104, "Q/START AGAIN TO QUIT", palette.red, 1, false);
    } else {
        r.drawText(px + 30, py + 104, "Q/START  QUIT", palette.muted, 1, false);
    }
    r.drawText(px + 30, py + ph - 22, "F4 COPY DIAGNOSTICS", palette.gold, 1, false);
}

fn drawVictoryBanner(r: *renderer.Renderer, w: i32, h: i32) void {
    r.fillRect(0, 0, w, h, palette.deep);
    const title = "BOSS DEFEATED";
    const tw = renderer.Renderer.textWidth(title, 3);
    r.drawText(@divTrunc(w, 2) - @divTrunc(tw, 2), @divTrunc(h, 2) - 34, title, palette.gold_light, 3, true);
    const sub = "ABYSS WARDEN FALLS";
    const sw = renderer.Renderer.textWidth(sub, 1);
    r.drawText(@divTrunc(w, 2) - @divTrunc(sw, 2), @divTrunc(h, 2) + 10, sub, palette.cream, 1, false);
    const hint = "PRESS CONFIRM TO CONTINUE";
    const hw = renderer.Renderer.textWidth(hint, 1);
    r.drawText(@divTrunc(w, 2) - @divTrunc(hw, 2), @divTrunc(h, 2) + 32, hint, palette.muted, 1, false);
}

fn drawChunkMap(r: *renderer.Renderer, state: State, w: i32, h: i32) void {
    const pw: i32 = 340;
    const ph: i32 = 286;
    const px = @divTrunc(w - pw, 2);
    const py = @divTrunc(h - ph, 2);
    r.fillRect(0, 0, w, h, palette.deep);
    r.fillRect(px, py, pw, ph, palette.panel);
    r.strokeRect(px, py, pw, ph, palette.gold);
    const title = "CHUNK MAP";
    const tw = renderer.Renderer.textWidth(title, 2);
    r.drawText(px + @divTrunc(pw - tw, 2), py + 12, title, palette.gold_light, 2, true);

    const cell_w: i32 = 88;
    const cell_h: i32 = 62;
    const gap: i32 = 8;
    const ox = px + @divTrunc(pw - (cell_w * 3 + gap * 2), 2);
    const oy = py + 48;
    var buf: [32]u8 = undefined;
    var visited: u8 = 0;
    for (0..9) |i| {
        if (state.chunk_visited[i]) visited += 1;
        const cx = ox + @as(i32, @intCast(i % 3)) * (cell_w + gap);
        const cy = oy + @as(i32, @intCast(i / 3)) * (cell_h + gap);
        const is_now = i == state.chunk;
        const seen = state.chunk_visited[i];
        r.fillRect(cx, cy, cell_w, cell_h, if (is_now) palette.gold else if (seen) palette.border else palette.deep);
        r.strokeRect(cx, cy, cell_w, cell_h, if (is_now) palette.gold_light else palette.muted);
        const label = fmt(&buf, "{d}", .{i + 1});
        r.drawText(cx + 6, cy + 5, label, if (is_now or seen) palette.deep else palette.muted, 1, false);
        if (is_now) {
            r.drawText(cx + 14, cy + 30, "YOU", palette.deep, 1, false);
        } else if (state.chunk_cleared[i]) {
            r.drawText(cx + 14, cy + 30, "CLEAR", palette.cyan_light, 1, false);
        } else if (seen) {
            r.drawText(cx + 14, cy + 30, "VISITED", palette.deep, 1, false);
        } else {
            r.drawText(cx + 14, cy + 30, "???", palette.muted, 1, false);
        }
    }
    const foot = fmt(&buf, "VISITED {d}/9   M CLOSE", .{visited});
    r.drawText(px + 16, py + ph - 20, foot, palette.cream, 1, false);
}

fn drawMenu(r: *renderer.Renderer, state: State, w: i32, h: i32) void {
    var y: i32 = 0;
    while (y < h) : (y += 2) {
        var x: i32 = 0;
        while (x < w) : (x += 2) r.putPixel(x, y, palette.deep);
    }

    const plate_w: i32 = 210;
    backPanel(r, @divTrunc(w, 2) - @divTrunc(plate_w, 2), 4, plate_w, 48);
    const title = i18n.t(menu_title, "CHOOSE CLASS");
    const tw = renderer.Renderer.textWidth(title, 2);
    r.drawText(@divTrunc(w, 2) - @divTrunc(tw, 2), 7, title, palette.gold, 2, true);
    var sub_buf: [64]u8 = undefined;
    const sub = if (state.daily)
        if (state.daily_best_floor > 0)
            fmt(&sub_buf, "SEED {d}  {s}  DAILY F{d}", .{ state.menu_seed, switch (state.difficulty) {
                1 => "HARD",
                2 => "EASY",
                else => "NORMAL",
            }, state.daily_best_floor })
        else
            fmt(&sub_buf, "SEED {d}  {s}  DAILY", .{ state.menu_seed, switch (state.difficulty) {
                1 => "HARD",
                2 => "EASY",
                else => "NORMAL",
            } })
    else
        fmt(&sub_buf, "SEED {d}  {s} [D] {s}", .{ state.menu_seed, switch (state.difficulty) {
            1 => "HARD",
            2 => "EASY",
            else => "NORMAL",
        }, i18n.t("切换", "TOGGLE") });
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
        const res = fmt(&res_buf, "{s} {s} {d}", .{ i18n.t("资源", "RES"), card.resource, card.resource_max });
        r.drawText(x + 8, y0 + 38, res, palette.cream, 1, false);
        var hp_buf: [24]u8 = undefined;
        const hp = fmt(&hp_buf, "{s} {d}", .{ i18n.t("生命", "HP"), card.hp_max });
        r.drawText(x + 8, y0 + 52, hp, palette.muted, 1, false);
        var role_buf: [48]u8 = undefined;
        const role = fmt(&role_buf, "{s} {s}", .{ i18n.t("定位", "ROLE"), card.role });
        r.drawText(x + 8, y0 + 66, role, palette.cyan_light, 1, false);

        r.fillRect(x + 8, y0 + 82, card_w - 16, 1, palette.border);
        r.drawText(x + 8, y0 + 88, i18n.t(talent_label, "TALENTS"), palette.gold, 1, false);
        var talent_buf: [32]u8 = undefined;
        for (card.talents, 0..) |name, t| {
            const ty = y0 + 104 + @as(i32, @intCast(t)) * 28;
            const label = fmt(&talent_buf, "{d} {s}", .{ t + 1, name });
            r.drawText(x + 8, ty, label, palette.cream, 1, false);
            r.drawText(x + 22, ty + 13, card.descs[t], palette.muted, 1, false);
        }
        if (state.demo and i != 0) {
            r.fillRect(x + 1, y0 + 1, card_w - 2, card_h - 2, palette.deep);
            const lock = "DEMO LOCKED";
            const lw = renderer.Renderer.textWidth(lock, 1);
            r.drawText(x + @divTrunc(card_w - lw, 2), y0 + @divTrunc(card_h, 2), lock, palette.muted, 1, false);
        }
    }

    if (h >= 300) {
        var rbuf: [128]u8 = undefined;
        const rec = if (state.record_wins > 0)
            fmt(&rbuf, "BEST F{d} T{d} K{d} G{d} | WINS {d}/{d}/{d} CH {d}", .{ state.record_best_floor, state.record_best_turn, state.record_best_kills, state.record_best_gold, state.record_wins_warrior, state.record_wins_mage, state.record_wins_chronomancer, state.record_chunk_clears })
        else
            fmt(&rbuf, "BEST --", .{});
        const rw = renderer.Renderer.textWidth(rec, 1);
        r.drawText(@divTrunc(w, 2) - @divTrunc(rw, 2), h - 32, rec, palette.gold_light, 1, false);

        var bbuf: [96]u8 = undefined;
        const all_classes = state.record_wins_warrior > 0 and state.record_wins_mage > 0 and state.record_wins_chronomancer > 0;
        const badges = if (state.record_wins == 0)
            "BADGES --"
        else
            fmt(&bbuf, "BADGES {s}{s}{s}", .{
                if (state.record_wins > 0) "FIRST-WIN " else "",
                if (all_classes) "ALL-CLASS " else "",
                if (state.record_flawless > 0) "FLAWLESS" else "",
            });
        const bw = renderer.Renderer.textWidth(badges, 1);
        r.drawText(@divTrunc(w, 2) - @divTrunc(bw, 2), h - 45, badges, palette.cyan_light, 1, false);
    }

    const footer_text = if (state.demo)
        i18n.t("1 选择  2/3 DEMO LOCKED  F6 DAILY  F8 SEED  F9 读档  R 重开", "1 SELECT  2/3 DEMO LOCKED  F6 DAILY  F8 NEW SEED  F9 LOAD  R RESTART")
    else
        i18n.t(menu_footer, "1/2/3 SELECT  D SWITCH  F6 DAILY  F8 NEW SEED  F9 LOAD  R RESTART");
    const fw = renderer.Renderer.textWidth(footer_text, 1);
    r.drawText(@divTrunc(w, 2) - @divTrunc(fw, 2), h - 18, footer_text, palette.muted, 1, false);
}

fn drawHelp(r: *renderer.Renderer, w: i32, h: i32) void {
    r.fillRect(0, 0, w, h, palette.deep);
    const px: i32 = 32;
    const pw: i32 = w - 64;
    const ph: i32 = @min(h - 32, 256);
    const py: i32 = @divTrunc(h - ph, 2);
    backPanel(r, px, py, pw, ph);
    const title = i18n.t(help_title, "CONTROLS");
    const tw = renderer.Renderer.textWidth(title, 2);
    r.drawText(px + @divTrunc(pw - tw, 2), py + 8, title, palette.gold, 2, true);

    const lines = if (i18n.current == .en) &help_lines_en else &help_lines;
    var y = py + 30;
    for (lines) |line| {
        r.drawText(px + 18, y, line, palette.cream, 1, false);
        y += 12;
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
    if (state.chunk_map_open and !state.settings_open and !state.shop_open and !state.shrine_open) {
        drawChunkMap(r, state, w, h);
        return;
    }
    if (state.pause_open and !state.settings_open and !state.shop_open and !state.shrine_open) {
        drawPause(r, state, w, h);
        return;
    }
    if (state.badges_open and !state.settings_open) {
        drawBadges(r, state, w, h);
        return;
    }

    // top-left: class / HP / resource / turn / floor
    backPanel(r, 6, 5, 160, 58);
    var buf: [64]u8 = undefined;
    r.drawIcon(.hero, 10, 7, palette.gold, 1);
    r.drawText(26, 8, state.class_name, palette.gold, 1, false);
    if (state.difficulty == 1) r.drawText(130, 8, "HARD", palette.red, 1, false);
    if (state.difficulty == 2) r.drawText(136, 8, "EASY", palette.cyan_light, 1, false);
    const lv = if (i18n.current == .en)
        fmt(&buf, "LV {d}  XP {d}/{d}", .{ state.level, state.xp, state.xp_next })
    else
        fmt(&buf, "{d}级  XP {d}/{d}", .{ state.level, state.xp, state.xp_next });
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
        const buff = if (i18n.current == .en)
            fmt(&bbuf, "WAR CRY +{d:.0}% ATK  {d}T", .{ state.buff_pct * 100.0, state.buff_turns })
        else
            fmt(&bbuf, "战吼 +{d:.0}%攻  {d}回合", .{ state.buff_pct * 100.0, state.buff_turns });
        r.drawText(10, 69, buff, palette.gold_light, 1, false);
    }

    if (state.burn_turns > 0 and !state.dead and !state.victory) {
        backPanel(r, 6, 82, 160, 14);
        var fbuf: [48]u8 = undefined;
        const burn = if (i18n.current == .en)
            fmt(&fbuf, "BURN {d:.0}x{d}/T  {d}T", .{ state.burn_damage, state.burn_stacks, state.burn_turns })
        else
            fmt(&fbuf, "灼烧 {d:.0}x{d}/回合  {d}回合", .{ state.burn_damage, state.burn_stacks, state.burn_turns });
        r.drawText(10, 85, burn, palette.red, 1, false);
    }

    if (state.vulnerable_turns > 0 and !state.dead and !state.victory) {
        backPanel(r, 6, 98, 160, 14);
        var vbuf: [48]u8 = undefined;
        const vuln = fmt(&vbuf, "VULN +20% dmg  {d}T", .{state.vulnerable_turns});
        r.drawText(10, 101, vuln, color.pack(220, 120, 255), 1, false);
    }

    // top-right: floor / enemies / stairs / turn / initiative
    backPanel(r, w - 154, 5, 154, 60);
    var floor_buf: [96]u8 = undefined;
    const dir = if (i18n.current == .en)
        switch (state.stairs_dir) {
            'N' => "N",
            'E' => "E",
            'S' => "S",
            'W' => "W",
            else => "",
        }
    else if (state.stairs_hint.len >= 3) state.stairs_hint[state.stairs_hint.len - 3 ..] else "";
    const floor = if (i18n.current == .en)
        if (state.stairs_hint.len > 0)
            fmt(&floor_buf, "F{d}/{d} {s}{d}", .{ state.floor, state.floors, dir, state.stairs_dist })
        else
            fmt(&floor_buf, "F{d}/{d}", .{ state.floor, state.floors })
    else if (state.stairs_hint.len > 0)
        fmt(&floor_buf, "第{d}/{d}层 {s}{d}", .{ state.floor, state.floors, dir, state.stairs_dist })
    else
        fmt(&floor_buf, "第 {d}/{d} 层", .{ state.floor, state.floors });
    r.drawIcon(.stairs, w - 168, 8, palette.gold_light, 1);
    r.drawText(w - 154, 9, floor, palette.gold_light, 1, false);
    const enemies = if (i18n.current == .en)
        if (state.floor_mod_label.len > 0)
            fmt(&buf, "ENEMIES {d}  {s}  G{d}", .{ state.enemies_left, state.floor_mod_label, state.gold })
        else
            fmt(&buf, "ENEMIES {d}  G{d}", .{ state.enemies_left, state.gold })
    else if (state.floor_mod_label.len > 0)
        fmt(&buf, "敌人 {d}  {s}  G{d}", .{ state.enemies_left, state.floor_mod_label, state.gold })
    else
        fmt(&buf, "敌人 {d}  G{d}", .{ state.enemies_left, state.gold });
    r.drawIcon(.coin, w - 168, 22, palette.gold, 1);
    r.drawText(w - 154, 23, enemies, palette.cream, 1, false);
    const turn = if (i18n.current == .en)
        if (state.enemy_phase) "ENEMY TURN" else fmt(&buf, "PLAYER TURN {d}", .{state.turn})
    else if (state.enemy_phase) "敌人行动" else fmt(&buf, "玩家回合 {d}", .{state.turn});
    r.drawText(w - 154, 37, turn, if (state.enemy_phase) palette.red else palette.gold_light, 1, false);
    var init_buf: [96]u8 = undefined;
    const init_label = i18n.t("先攻", "INIT");
    const order = if (state.initiative_count >= 3)
        fmt(&init_buf, "{s} {s}>{s}>{s}", .{ init_label, state.initiative[0], state.initiative[1], state.initiative[2] })
    else if (state.initiative_count >= 2)
        fmt(&init_buf, "{s} {s}>{s}", .{ init_label, state.initiative[0], state.initiative[1] })
    else
        fmt(&init_buf, "{s} {s}", .{ init_label, state.initiative[0] });
    r.drawText(w - 154, 51, order, palette.muted, 1, false);
    if (state.floor_mod_label.len > 0) {
        const mod_color: u32 = if (std.mem.eql(u8, state.floor_mod_label, "EMBER"))
            palette.red
        else if (std.mem.eql(u8, state.floor_mod_label, "FROST"))
            palette.cyan_light
        else if (std.mem.eql(u8, state.floor_mod_label, "MIASMA"))
            color.pack(185, 128, 230)
        else if (std.mem.eql(u8, state.floor_mod_label, "GILDED"))
            palette.gold
        else
            color.pack(220, 80, 80);
        const mod_desc: []const u8 = if (std.mem.eql(u8, state.floor_mod_label, "EMBER"))
            "BURN +50%"
        else if (std.mem.eql(u8, state.floor_mod_label, "FROST"))
            "ENEMY SPD -10%"
        else if (std.mem.eql(u8, state.floor_mod_label, "MIASMA"))
            "RES REGEN -50%"
        else if (std.mem.eql(u8, state.floor_mod_label, "GILDED"))
            "GOLD +50%"
        else
            "XP +50%";
        var mod_buf: [48]u8 = undefined;
        const mod = fmt(&mod_buf, "MOD {s} {s}", .{ state.floor_mod_label, mod_desc });
        const mw = renderer.Renderer.textWidth(mod, 1);
        backPanel(r, w - 168, 64, mw + 10, 13);
        r.drawText(w - 163, 67, mod, mod_color, 1, false);
    }
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
                    6 => palette.cyan_light,
                    7 => palette.red,
                    else => palette.deep,
                };
                r.fillRect(mx0 + @as(i32, @intCast(mx)) * 2, my0 + @as(i32, @intCast(my)) * 2, 2, 2, c);
            }
        }
        if (state.chunks_enabled) {
            const cx = mx0 + 6;
            const cy = my0 + 6;
            if (state.chunk_y > -1) r.fillRect(cx - 2, my0 - 3, 4, 2, palette.gold_light);
            if (state.chunk_y < 1) r.fillRect(cx - 2, my0 + 28, 4, 2, palette.gold_light);
            if (state.chunk_x > -1) r.fillRect(mx0 - 3, cy - 2, 2, 4, palette.gold_light);
            if (state.chunk_x < 1) r.fillRect(mx0 + 27, cy - 2, 2, 4, palette.gold_light);
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
        const en = i18n.current == .en;
        if (state.aim.valid) {
            if (std.mem.eql(u8, state.aim.target, "地面")) {
                line = if (en)
                    fmt(&aim_buf, "AIM: {s} -> GROUND  DIST {d}  AOE {d}", .{
                        state.aim.talent, state.aim.distance, state.aim.aoe_radius,
                    })
                else
                    fmt(&aim_buf, "瞄准：{s} -> 地面 距离{d} 范围{d}", .{
                        state.aim.talent, state.aim.distance, state.aim.aoe_radius,
                    });
            } else if (state.aim.aoe_radius > 0)
                line = if (en)
                    fmt(&aim_buf, "AIM: {s} -> {s}  DIST {d}  DMG {d}  AOE {d}", .{
                        state.aim.talent, state.aim.target, state.aim.distance, state.aim.damage, state.aim.aoe_radius,
                    })
                else
                    fmt(&aim_buf, "瞄准：{s} -> {s} 距离{d} 预计{d}伤害 范围{d}", .{
                        state.aim.talent, state.aim.target, state.aim.distance, state.aim.damage, state.aim.aoe_radius,
                    })
            else
                line = if (en)
                    fmt(&aim_buf, "AIM: {s} -> {s}  DIST {d}  DMG {d}", .{
                        state.aim.talent, state.aim.target, state.aim.distance, state.aim.damage,
                    })
                else
                    fmt(&aim_buf, "瞄准：{s} -> {s} 距离{d} 预计{d}伤害", .{
                        state.aim.talent, state.aim.target, state.aim.distance, state.aim.damage,
                    });
        } else if (state.aim.target.len > 0) {
            line = if (en)
                fmt(&aim_buf, "AIM: {s} -> {s} {s}", .{ state.aim.talent, state.aim.target, i18n.aimReason(state.aim.reason) })
            else
                fmt(&aim_buf, "瞄准：{s} -> {s} {s}", .{ state.aim.talent, state.aim.target, state.aim.reason });
        } else {
            line = if (en)
                fmt(&aim_buf, "AIM: {s} {s}", .{ state.aim.talent, i18n.aimReason(state.aim.reason) })
            else
                fmt(&aim_buf, "瞄准：{s} {s}", .{ state.aim.talent, state.aim.reason });
        }
        const line_w = renderer.Renderer.textWidth(line, 1);
        const hint_text = i18n.t(aim_hint, "SPACE/SAME KEY/LMB CONFIRM  ESC CANCEL  TAB TARGET");
        const hint_w = renderer.Renderer.textWidth(hint_text, 1);
        const box_w = @max(line_w, hint_w) + 16;
        const box_x = @divTrunc(w - box_w, 2);
        const box_y = h - 90;
        const accent: u32 = if (state.aim.valid) palette.cyan else palette.red;
        r.fillRect(box_x, box_y, box_w, 26, palette.panel);
        r.strokeRect(box_x, box_y, box_w, 26, accent);
        r.fillRect(box_x + 2, box_y + 2, 24, 1, accent);
        r.drawText(box_x + 8, box_y + 4, line, if (state.aim.valid) palette.cyan_light else palette.red, 1, false);
        r.drawText(box_x + 8, box_y + 15, hint_text, palette.muted, 1, false);
    }

    // hotbar: name, cost/base cooldown, then live availability
    backPanel(r, 6, h - 60, 265, 54);
    r.drawText(10, h - 56, i18n.t(talent_label, "TALENTS"), palette.gold, 1, false);
    for (state.hotbar, 0..) |slot, i| {
        const sx: i32 = 10 + @as(i32, @intCast(i)) * 85;
        const sy: i32 = h - 45;
        const aiming = state.aim.active and state.aim.talent_index == i;
        r.fillRect(sx, sy, 82, 38, palette.deep);
        r.strokeRect(sx, sy, 82, 38, if (aiming) palette.gold else if (slot.ready) palette.border else palette.muted);
        const talent_icon: renderer.icons.Icon = switch (i) {
            0 => .sword,
            1 => .fire,
            else => .time,
        };
        r.drawIcon(talent_icon, sx + 66, sy + 2, if (slot.ready) palette.cream else palette.muted, 1);
        const key = fmt(&buf, "{d}", .{i + 1});
        r.drawText(sx + 4, sy + 3, key, palette.gold, 1, false);
        r.drawText(sx + 18, sy + 3, slot.name, if (slot.ready) palette.cream else palette.muted, 1, false);
        const cost = if (i18n.current == .en)
            fmt(&buf, "COST {d} CD {d}", .{ slot.cost, slot.cooldown_max })
        else
            fmt(&buf, "消耗{d} 冷却{d}", .{ slot.cost, slot.cooldown_max });
        r.drawText(sx + 4, sy + 15, cost, palette.muted, 1, false);
        var status_buf: [24]u8 = undefined;
        var status: []const u8 = i18n.t("可用", "READY");
        var status_color: u32 = palette.cyan_light;
        if (state.dead or state.victory) {
            status = i18n.t("不可用", "LOCKED");
            status_color = palette.muted;
        } else if (aiming) {
            status = i18n.t("瞄准中", "AIMING");
            status_color = palette.gold_light;
        } else if (slot.cooldown > 0) {
            status = if (i18n.current == .en)
                fmt(&status_buf, "CD {d}", .{slot.cooldown})
            else
                fmt(&status_buf, "冷却 {d}", .{slot.cooldown});
            status_color = palette.red;
        } else if (!slot.affordable) {
            status = i18n.t("缺资源", "NO RES");
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
        const title = if (state.panel == .inventory) i18n.t("背包", "BAG") else i18n.t("角色", "CHARACTER");
        r.drawIcon(if (state.panel == .inventory) .bag else .hero, ix + 12, iy + 5, palette.gold, 2);
        r.drawText(ix + 42, iy + 10, title, palette.gold, 1, false);
        r.drawText(ix + iw - 62, iy + 10, i18n.t("关闭", "CLOSE"), palette.muted, 1, false);

        if (state.panel == .character) {
            const labels = [_][]const u8{ "力量", "敏捷", "体质", "感知", "魔力", "意志" };
            var abuf: [24]u8 = undefined;
            for (labels, 0..) |label, i| {
                const col = @as(i32, @intCast(i % 2));
                const row = @as(i32, @intCast(i / 2));
                const ax = ix + 16 + col * 150;
                const ay = iy + 42 + row * 22;
                r.drawText(ax, ay, i18n.statShort(label), palette.cream, 1, false);
                const val = fmt(&abuf, "{d}", .{state.attrs[i]});
                r.drawText(ax + 48, ay, val, palette.gold_light, 1, false);
            }
            var dbuf: [40]u8 = undefined;
            r.drawText(ix + 278, iy + 42, i18n.t("战斗", "COMBAT"), palette.gold, 1, false);
            r.drawText(ix + 278, iy + 64, fmt(&dbuf, "{s} {d:.0}/{d:.0}", .{ i18n.t("生命", "HP"), state.hp, state.hp_max }), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 84, fmt(&dbuf, "{s} {d:.0}/{d:.0}", .{ state.resource_label, state.resource, state.resource_max }), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 104, fmt(&dbuf, "{s} {d:.0}", .{ i18n.t("攻击", "ATK"), state.attack }), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 124, fmt(&dbuf, "{s} {d:.0}", .{ i18n.t("护甲", "ARMOR"), state.armor }), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 144, fmt(&dbuf, "{s} {d:.0}%", .{ i18n.t("暴击", "CRIT"), state.crit * 100.0 }), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 164, fmt(&dbuf, "{s} {d:.0}", .{ i18n.t("速度", "SPD"), state.speed }), palette.cream, 1, false);
            r.drawText(ix + 278, iy + 184, fmt(&dbuf, "{s} {d:.1}", .{ i18n.t("回复", "REGEN"), state.res_per_turn }), palette.cream, 1, false);

            r.drawText(ix + 16, iy + 106, fmt(&dbuf, "{s} {d}  1-6", .{ i18n.t("属性点", "POINTS"), state.pending_points }), palette.gold_light, 1, false);
            r.drawText(ix + 16, iy + 126, i18n.t("装备", "EQUIPMENT"), palette.gold, 1, false);
            const slot_labels = [_][]const u8{ i18n.t("主手", "MAIN"), i18n.t("身体", "BODY"), i18n.t("饰品", "TRINKET") };
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
                const prefix = if (i == 0) i18n.t("天赋 ", "TALENT ") else "       ";
                const line = fmt(&tbuf, "{s}{d} {s}{s}{s}", .{ prefix, i + 1, slot.name, i18n.t("：", ": "), state.talent_descs[i] });
                r.drawText(ix + 16, iy + 204 + @as(i32, @intCast(i)) * 14, line, if (i == 0) palette.gold_light else palette.cream, 1, false);
            }
        } else {
            if (state.item_count == 0) {
                r.drawText(ix + 16, iy + 42, i18n.t("背包是空的", "BAG IS EMPTY"), palette.muted, 1, false);
            } else {
                const n = @min(state.item_count, state.items.len);
                var ibuf: [48]u8 = undefined;
                for (state.items[0..n], 0..) |name, i| {
                    const col = @as(i32, @intCast(i % 2));
                    const row = @as(i32, @intCast(i / 2));
                    const y = iy + 42 + row * 28;
                    const label = if (i < 3) fmt(&ibuf, "{d} {s}", .{ i + 1, name }) else fmt(&ibuf, "  {s}", .{name});
                    r.drawText(ix + 16 + col * 190, y, label, palette.cream, 1, false);
                    if (i < state.item_delta_valid.len and state.item_delta_valid[i]) {
                        var dbuf: [16]u8 = undefined;
                        const dtext = if (state.item_delta_new[i])
                            "NEW"
                        else if (state.item_deltas[i] > 0)
                            fmt(&dbuf, "+{d}", .{state.item_deltas[i]})
                        else if (state.item_deltas[i] < 0)
                            fmt(&dbuf, "{d}", .{state.item_deltas[i]})
                        else
                            "=";
                        const dcol = if (state.item_delta_new[i] or state.item_deltas[i] > 0) color.pack(143, 209, 102) else if (state.item_deltas[i] < 0) palette.red else palette.muted;
                        r.drawText(ix + 16 + col * 190 + 150, y, dtext, dcol, 1, false);
                    }
                    if (i < state.item_details.len and state.item_details[i].len > 0) {
                        r.drawText(ix + 26 + col * 190, y + 10, state.item_details[i], palette.muted, 1, false);
                    }
                }
            }
            r.fillRect(ix + 16, iy + ih - 104, iw - 32, 1, palette.border);
            r.drawText(ix + 16, iy + ih - 96, i18n.t("装备", "EQUIPMENT"), palette.gold, 1, false);
            const slot_labels = [_][]const u8{ i18n.t("主手", "MAIN"), i18n.t("身体", "BODY"), i18n.t("饰品", "TRINKET") };
            var ebuf: [40]u8 = undefined;
            for (slot_labels, 0..) |label, i| {
                const name = if (state.equip[i].len > 0) state.equip[i] else "-";
                r.drawText(ix + 16, iy + ih - 78 + @as(i32, @intCast(i)) * 16, fmt(&ebuf, "{s}  {s}", .{ label, name }), palette.muted, 1, false);
            }
            var pbuf: [48]u8 = undefined;
            r.drawText(ix + 16, iy + ih - 18, fmt(&pbuf, "1/2/3 EQ  P POT x{d}  B BOMB x{d}", .{ state.potions, state.bombs }), palette.muted, 1, false);
        }
    }

    if (state.bombs > 0) {
        var bbuf: [32]u8 = undefined;
        r.drawText(w - 92, h - 18, fmt(&bbuf, "B BOMB x{d}", .{state.bombs}), palette.gold_light, 1, false);
    }

    if (state.boss_active and !state.dead and !state.victory) {
        const bw: i32 = 220;
        const bx = @divTrunc(w - bw, 2);
        const by: i32 = 70;
        backPanel(r, bx - 4, by - 4, bw + 8, 27);
        const label = if (state.boss_enraged) "ABYSS WARDEN [ENRAGED]" else "ABYSS WARDEN";
        const lw = renderer.Renderer.textWidth(label, 1);
        r.drawText(@divTrunc(w, 2) - @divTrunc(lw, 2), by, label, if (state.boss_enraged) palette.gold_light else palette.red, 1, false);
        bar(r, bx, by + 11, bw, 7, if (state.boss_hp_max > 0) state.boss_hp / state.boss_hp_max else 0, if (state.boss_enraged) palette.red else palette.health);
    }

    if (state.toast.len > 0) {
        const tw = renderer.Renderer.textWidth(state.toast, 1);
        const bw = tw + 16;
        backPanel(r, @divTrunc(w - bw, 2), 72, bw, 18);
        r.drawText(@divTrunc(w - tw, 2), 77, state.toast, palette.gold_light, 1, false);
    }

    // death / victory overlay; keep the last log line as the cause
    if (state.dead or state.victory) {
        if (state.victory and state.victory_hold) {
            drawVictoryBanner(r, w, h);
            return;
        }
        const title = if (state.demo_end) "DEMO END" else if (state.victory) i18n.t("胜利", "VICTORY") else i18n.t("死亡", "DEFEAT");
        var best_buf: [96]u8 = undefined;
        const sub = if (state.record_wins > 0)
            if (i18n.current == .en)
                fmt(&best_buf, "BEST F{d} T{d} K{d} G{d}   R RESTART", .{ state.record_best_floor, state.record_best_turn, state.record_best_kills, state.record_best_gold })
            else
                fmt(&best_buf, "BEST F{d} T{d} K{d} G{d}   R 重开", .{ state.record_best_floor, state.record_best_turn, state.record_best_kills, state.record_best_gold })
        else
            i18n.t("按 R 重开 同职业", "R RESTART SAME CLASS");
        const cause = if (state.log_count > 0) state.log_lines[state.log_count - 1] else "";
        var sbuf: [96]u8 = undefined;
        const summary = if (state.demo_end)
            "WISHLIST ON STEAM"
        else
            fmt(&sbuf, "F{d}/{d}  T{d}  KILL {d}  GOLD {d}  SEED {d}", .{
                state.floor, state.floors, state.turn, state.kills, state.gold, state.seed,
            });
        r.fillRect(0, @divTrunc(h, 2) - 28, w, 76, palette.panel);
        r.fillRect(0, @divTrunc(h, 2) - 29, w, 1, palette.gold);
        r.fillRect(0, @divTrunc(h, 2) + 47, w, 1, palette.gold);
        const tw = renderer.Renderer.textWidth(title, 2);
        const tx = @divTrunc(w, 2) - @divTrunc(tw, 2);
        r.drawIcon(if (state.victory) .hero else .skull, tx - 18, @divTrunc(h, 2) - 22, if (state.victory) palette.gold_light else palette.red, 1);
        r.drawText(tx, @divTrunc(h, 2) - 22, title, if (state.victory) palette.gold_light else palette.red, 2, true);
        const mw = renderer.Renderer.textWidth(summary, 1);
        r.drawText(@divTrunc(w, 2) - @divTrunc(mw, 2), @divTrunc(h, 2) - 4, summary, palette.gold_light, 1, true);
        if (cause.len > 0) {
            const cw = renderer.Renderer.textWidth(cause, 1);
            r.drawText(@divTrunc(w, 2) - @divTrunc(cw, 2), @divTrunc(h, 2) + 11, cause, palette.cream, 1, true);
        }
        const sw = renderer.Renderer.textWidth(sub, 1);
        r.drawText(@divTrunc(w, 2) - @divTrunc(sw, 2), @divTrunc(h, 2) + 26, sub, palette.muted, 1, true);
        if (state.daily and state.daily_best_floor > 0) {
            var dbuf: [40]u8 = undefined;
            const daily = fmt(&dbuf, "DAILY BEST F{d}", .{state.daily_best_floor});
            const dw = renderer.Renderer.textWidth(daily, 1);
            r.drawText(@divTrunc(w, 2) - @divTrunc(dw, 2), @divTrunc(h, 2) + 36, daily, palette.cyan_light, 1, true);
        }
        const hint = "F4 COPY DIAGNOSTICS";
        const hw = renderer.Renderer.textWidth(hint, 1);
        r.drawText(@divTrunc(w, 2) - @divTrunc(hw, 2), @divTrunc(h, 2) + 35, hint, palette.gold, 1, true);
    }

    if (state.shrine_open) drawShrine(r, state, w, h);
    if (state.shop_open) drawShop(r, state, w, h);
    if (state.settings_open) drawSettings(r, state, w, h);

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
            1 => i18n.t("保存到槽位", "SAVE TO SLOT"),
            2 => i18n.t("从槽位读取", "LOAD FROM SLOT"),
            else => i18n.t("自动档备份", "AUTOSAVE BACKUP"),
        };
        r.drawIcon(.save, px + 14, py + 6, palette.gold, 1);
        r.drawText(px + 32, py + 12, title, palette.gold, 1, true);
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const y = py + 42 + @as(i32, @intCast(i)) * 30;
            r.fillRect(px + 12, y - 4, pw - 24, 26, palette.deep);
            const num = fmt(&buf, "{d}", .{i + 1});
            r.drawText(px + 20, y, num, palette.gold_light, 1, true);
            const label = if (state.slot_labels[i].len > 0) state.slot_labels[i] else i18n.t("空", "EMPTY");
            r.drawText(px + 44, y, label, palette.cream, 1, true);
        }
        r.drawText(px + 16, py + ph - 24, i18n.t("1/2/3 选择   Esc 取消", "1/2/3 SELECT   ESC CANCEL"), palette.muted, 1, true);
    }
}

fn drawSettings(r: *renderer.Renderer, state: State, w: i32, h: i32) void {
    if (state.keys_mode) {
        const kw: i32 = 320;
        const kh: i32 = 270;
        const kx = @divTrunc(w - kw, 2);
        const ky = @divTrunc(h - kh, 2);
        r.fillRect(0, 0, w, h, palette.deep);
        r.fillRect(kx, ky, kw, kh, palette.panel);
        r.strokeRect(kx, ky, kw, kh, palette.gold);
        const title = "REMAP KEYS";
        const tw = renderer.Renderer.textWidth(title, 2);
        r.drawText(kx + @divTrunc(kw - tw, 2), ky + 14, title, palette.gold_light, 2, true);
        for (settings_mod.binding_defs, 0..) |def, i| {
            const selected = i == state.keys_index;
            r.drawText(kx + 48, ky + 52 + @as(i32, @intCast(i)) * 20, def.label, if (selected) palette.gold_light else palette.cream, 1, false);
            if (selected) r.fillRect(kx + 38, ky + 57 + @as(i32, @intCast(i)) * 20, 4, 4, palette.gold);
        }
        if (state.keys_error) {
            r.drawText(kx + 16, ky + kh - 22, "KEY IN USE - TRY AGAIN", palette.red, 1, false);
        } else {
            r.drawText(kx + 16, ky + kh - 22, "PRESS NEW KEY  BACKSPACE RESET  ESC CANCEL", palette.muted, 1, false);
        }
        return;
    }
    const pw: i32 = 320;
    const ph: i32 = 352;
    const px = @divTrunc(w - pw, 2);
    const py = @divTrunc(h - ph, 2);
    r.fillRect(0, 0, w, h, palette.deep);
    r.fillRect(px, py, pw, ph, palette.panel);
    r.strokeRect(px, py, pw, ph, palette.gold);
    r.fillRect(px + 2, py + 2, pw - 4, 2, palette.gold_light);

    r.drawIcon(.gear, px + 14, py + 6, palette.gold, 2);
    const title = i18n.t("设置", "SETTINGS");
    const tw = renderer.Renderer.textWidth(title, 2);
    r.drawText(px + @divTrunc(pw - tw, 2), py + 12, title, palette.gold_light, 2, true);

    const lines_zh = [_][]const u8{
        "1 全屏          ON/OFF",
        "2 垂直同步      ON/OFF",
        "3 窗口缩放      2x/3x/4x",
        "4 音量          0/55/100%",
        "5 环境音        ON/OFF",
        "6 手柄 A/B      交换",
        "7 移动          WASD/ESDF",
        "8 重绑按键",
        "9 3x3 地图      ON/OFF",
        "0 屏幕震动      ON/OFF",
        "L 语言          ZH/EN",
    };
    const lines_en = [_][]const u8{
        "1 FULLSCREEN    ON/OFF",
        "2 VSYNC         ON/OFF",
        "3 WINDOW SCALE  2x/3x/4x",
        "4 VOLUME        0/55/100%",
        "5 AMBIENT       ON/OFF",
        "6 PAD A/B       SWAP",
        "7 MOVE          WASD/ESDF",
        "8 REMAP KEYS",
        "9 CHUNKS 3x3    ON/OFF",
        "0 SCREEN SHAKE  ON/OFF",
        "L LANGUAGE      ZH/EN",
    };
    const lines = if (i18n.current == .en) &lines_en else &lines_zh;
    for (lines, 0..) |line, i| {
        r.drawText(px + 28, py + 52 + @as(i32, @intCast(i)) * 20, line, palette.cream, 1, false);
    }

    var vbuf: [64]u8 = undefined;
    const v1 = fmt(&vbuf, "F {s} VS {s} {d}x {d}% AMB {s}", .{
        if (state.settings_fullscreen) "ON" else "OFF",
        if (state.settings_vsync) "ON" else "OFF",
        state.settings_scale,
        @as(i32, @intFromFloat(state.settings_volume * 100.0)),
        if (state.settings_ambient) "ON" else "OFF",
    });
    var vbuf2: [64]u8 = undefined;
    const v2 = fmt(&vbuf2, "PAD {s} MOVE {s} CH {s} SH {s} LANG {s}", .{
        if (state.settings_pad_swap) "SWAP" else "STD",
        if (state.settings_esdf) "ESDF" else "WASD",
        if (state.settings_chunks) "ON" else "OFF",
        if (state.settings_shake) "ON" else "OFF",
        if (state.language == 1) "EN" else "ZH",
    });
    const vw = renderer.Renderer.textWidth(v1, 1);
    r.drawText(px + @divTrunc(pw - vw, 2), py + 274, v1, palette.cyan_light, 1, false);
    const vw2 = renderer.Renderer.textWidth(v2, 1);
    r.drawText(px + @divTrunc(pw - vw2, 2), py + 292, v2, palette.cyan_light, 1, false);
    r.drawText(px + 16, py + ph - 18, i18n.t("Esc 关闭   F2 切换   L 语言", "Esc CLOSE   F2 TOGGLE   L LANGUAGE"), palette.muted, 1, false);
}

fn drawShop(r: *renderer.Renderer, state: State, w: i32, h: i32) void {
    const pw: i32 = 300;
    const ph: i32 = 224;
    const px = @divTrunc(w - pw, 2);
    const py = @divTrunc(h - ph, 2);
    r.fillRect(0, 0, w, h, palette.deep);
    r.fillRect(px, py, pw, ph, palette.panel);
    r.strokeRect(px, py, pw, ph, palette.gold);
    r.fillRect(px + 2, py + 2, pw - 4, 2, palette.gold_light);

    const title = "SHOP";
    const tw = renderer.Renderer.textWidth(title, 2);
    r.drawText(px + @divTrunc(pw - tw, 2), py + 10, title, palette.gold_light, 2, true);
    var gold_buf: [32]u8 = undefined;
    r.drawIcon(.coin, px + 16, py + 32, palette.gold, 2);
    const gold = fmt(&gold_buf, "GOLD {d}", .{state.gold});
    const gw = renderer.Renderer.textWidth(gold, 1);
    r.drawText(px + @divTrunc(pw - gw, 2), py + 38, gold, palette.gold, 1, false);

    const lines_zh = [_][]const u8{ "1 治疗 25G", "2 主属性 +2 60G", "3 体质 +2 60G", "4 CLEANSE 20G", "5 LOOT 80G", "6 BOMB 40G" };
    const lines_en = [_][]const u8{ "1 HEAL 25G", "2 MAIN +2 60G", "3 CON +2 60G", "4 CLEANSE 20G", "5 LOOT 80G", "6 BOMB 40G" };
    const lines = if (i18n.current == .en) &lines_en else &lines_zh;
    for (lines, 0..) |line, i| {
        r.drawText(px + 40, py + 58 + @as(i32, @intCast(i)) * 20, line, if (i == 3) palette.cyan_light else if (i >= 4) palette.gold_light else palette.cream, 1, false);
    }
    r.drawText(px + 16, py + ph - 20, i18n.t("1/2/3/4/5/6 选择   Esc 关闭", "1/2/3/4/5/6 SELECT   ESC CLOSE"), palette.muted, 1, false);
}

fn drawShrine(r: *renderer.Renderer, state: State, w: i32, h: i32) void {
    const pw: i32 = 300;
    const ph: i32 = 176;
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

    const lines_zh = [_][]const u8{ "  +2", "体质 +2", "意志 +2", "主属性 +4 体质 -2" };
    const lines_en = [_][]const u8{ "  +2", "CON +2", "WILL +2", "MAIN +4 CON -2" };
    const lines = if (i18n.current == .en) &lines_en else &lines_zh;
    var buf: [64]u8 = undefined;
    for (lines, 0..) |suffix, i| {
        const main_label = if (i18n.current == .en) i18n.statShort(state.shrine_main_label) else state.shrine_main_label;
        const line = if (i == 0) fmt(&buf, "1 {s}{s}", .{ main_label, suffix }) else fmt(&buf, "{d} {s}", .{ i + 1, suffix });
        r.drawText(px + 34, py + 58 + @as(i32, @intCast(i)) * 21, line, if (i == 3) palette.red else palette.cream, 1, false);
    }
    r.drawText(px + 16, py + ph - 20, i18n.t("1/2/3/4 选择   Esc 关闭", "1/2/3/4 SELECT   ESC CLOSE"), palette.muted, 1, false);
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

test "help panel covers potion, shop and buff" {
    const blob = help_lines[0..];
    const required = [_][]const u8{ "POTION", "SHOP", "SHRINE", "BUFF", "P" };
    for (required) |needle| {
        var found = false;
        for (blob) |line| {
            if (std.mem.indexOf(u8, line, needle) != null) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}
