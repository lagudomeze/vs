//! Language state and translation helper. Content strings are migrated screen by screen.
const std = @import("std");

pub const Lang = enum(u8) { zh = 0, en = 1 };

pub var current: Lang = .zh;

pub fn set(value: u8) void {
    current = if (value == 1) .en else .zh;
}

pub fn code() u8 {
    return @backingInt(current);
}

pub fn t(zh: []const u8, en: []const u8) []const u8 {
    return if (current == .en) en else zh;
}

pub fn enemyName(zh: []const u8) []const u8 {
    if (current != .en) return zh;
    if (std.mem.eql(u8, zh, "骷髅兵")) return "SKELETON";
    if (std.mem.eql(u8, zh, "幽魂")) return "WRAITH";
    if (std.mem.eql(u8, zh, "石魔像")) return "GOLEM";
    if (std.mem.eql(u8, zh, "深渊守卫")) return "ABYSS WARDEN";
    if (std.mem.eql(u8, zh, "精英骷髅")) return "ELITE SKELETON";
    if (std.mem.eql(u8, zh, "精英幽魂")) return "ELITE WRAITH";
    if (std.mem.eql(u8, zh, "深渊幽魂")) return "ABYSS WRAITH";
    return zh;
}

pub fn enemyShort(zh: []const u8) []const u8 {
    if (current != .en) return zh;
    if (std.mem.eql(u8, zh, "骷髅兵")) return "SKEL";
    if (std.mem.eql(u8, zh, "幽魂")) return "WRAITH";
    if (std.mem.eql(u8, zh, "石魔像")) return "GOLEM";
    if (std.mem.eql(u8, zh, "深渊守卫")) return "WARDEN";
    if (std.mem.eql(u8, zh, "精英骷髅")) return "E.SKEL";
    if (std.mem.eql(u8, zh, "精英幽魂")) return "E.WRAITH";
    if (std.mem.eql(u8, zh, "深渊幽魂")) return "A.WRAITH";
    return zh;
}

test "i18n: select language and translate" {
    const saved = current;
    defer current = saved;
    set(0);
    try std.testing.expectEqualStrings("生命", t("生命", "Health"));
    set(1);
    try std.testing.expectEqualStrings("Health", t("生命", "Health"));
    try std.testing.expectEqual(@as(u8, 1), code());
    set(99);
    try std.testing.expectEqual(Lang.zh, current);
}
