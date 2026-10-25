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
