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

pub fn statShort(zh: []const u8) []const u8 {
    if (current != .en) return zh;
    if (std.mem.eql(u8, zh, "力量")) return "STR";
    if (std.mem.eql(u8, zh, "魔力")) return "MAG";
    if (std.mem.eql(u8, zh, "意志")) return "WILL";
    if (std.mem.eql(u8, zh, "体质")) return "CON";
    if (std.mem.eql(u8, zh, "敏捷")) return "AGI";
    if (std.mem.eql(u8, zh, "感知")) return "PER";
    if (std.mem.eql(u8, zh, "攻击")) return "ATK";
    if (std.mem.eql(u8, zh, "护甲")) return "ARMOR";
    if (std.mem.eql(u8, zh, "暴击")) return "CRIT";
    if (std.mem.eql(u8, zh, "速度")) return "SPD";
    if (std.mem.eql(u8, zh, "生命")) return "HP";
    if (std.mem.eql(u8, zh, "回复")) return "REGEN";
    return zh;
}

pub fn quality(zh: []const u8) []const u8 {
    if (current != .en) return zh;
    if (std.mem.eql(u8, zh, "普通")) return "COMMON";
    if (std.mem.eql(u8, zh, "稀有")) return "RARE";
    if (std.mem.eql(u8, zh, "史诗")) return "EPIC";
    if (std.mem.eql(u8, zh, "首领")) return "BOSS";
    return zh;
}

pub fn aimReason(zh: []const u8) []const u8 {
    if (current != .en) return zh;
    if (std.mem.eql(u8, zh, "无效目标")) return "INVALID TARGET";
    if (std.mem.eql(u8, zh, "超出范围")) return "OUT OF RANGE";
    if (std.mem.eql(u8, zh, "视线受阻")) return "LINE BLOCKED";
    if (std.mem.eql(u8, zh, "取消瞄准")) return "AIM CANCELLED";
    return zh;
}

pub fn itemName(zh: []const u8) []const u8 {
    if (current != .en) return zh;
    if (std.mem.eql(u8, zh, "铁剑")) return "IRON SWORD";
    if (std.mem.eql(u8, zh, "法杖")) return "STAFF";
    if (std.mem.eql(u8, zh, "皮甲")) return "LEATHER ARMOR";
    if (std.mem.eql(u8, zh, "秘银甲")) return "MITHRIL ARMOR";
    if (std.mem.eql(u8, zh, "猛虎护符")) return "TIGER AMULET";
    if (std.mem.eql(u8, zh, "时光沙漏")) return "HOURGLASS";
    if (std.mem.eql(u8, zh, "战斧")) return "BATTLE AXE";
    if (std.mem.eql(u8, zh, "时刃")) return "TIMEBLADE";
    if (std.mem.eql(u8, zh, "霜晶球")) return "FROST ORB";
    if (std.mem.eql(u8, zh, "骨甲")) return "BONE ARMOR";
    if (std.mem.eql(u8, zh, "生命瓶")) return "HEALTH VIAL";
    if (std.mem.eql(u8, zh, "魔力瓶")) return "MANA VIAL";
    if (std.mem.eql(u8, zh, "齿轮印记")) return "GEAR SIGIL";
    return zh;
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

fn parseU32(text: []const u8) ?u32 {
    return std.fmt.parseInt(u32, text, 10) catch null;
}

fn afterPrefix(line: []const u8, prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    return line[prefix.len..];
}

pub fn logLine(line: []const u8, buf: []u8) []const u8 {
    if (current != .en) return line;

    if (std.mem.eql(u8, line, "休息：恢复生命与资源")) return "REST: HP + RESOURCE";
    if (std.mem.eql(u8, line, "深渊守卫封印了楼梯")) return "STAIRS SEALED BY THE WARDEN";
    if (std.mem.eql(u8, line, "深渊守卫倒下，胜利") or std.mem.eql(u8, line, "击败深渊守卫，胜利")) return "ABYSS WARDEN FALLS - VICTORY";
    if (std.mem.eql(u8, line, "深渊守卫 狂暴")) return "ABYSS WARDEN ENRAGES";
    if (std.mem.eql(u8, line, "深渊守卫 召唤骷髅")) return "ABYSS WARDEN SUMMONS";
    if (std.mem.eql(u8, line, "躲开深渊斩")) return "DODGED ABYSS CLEAVE";
    if (std.mem.eql(u8, line, "Boss 免疫减速")) return "BOSS IMMUNE TO SLOW";
    if (std.mem.eql(u8, line, "Boss 抗眩晕 减速+反噬")) return "BOSS RESISTS STUN: SLOW + RETALIATE";
    if (std.mem.eql(u8, line, "火球轰击地面")) return "FIREBALL HITS THE GROUND";
    if (std.mem.eql(u8, line, "深渊守卫攻击")) return "ABYSS WARDEN ATTACK";

    if (afterPrefix(line, "进入第 ")) |rest| {
        if (std.mem.endsWith(u8, rest, " 层")) {
            if (parseU32(rest[0 .. rest.len - 4])) |n| return std.fmt.bufPrint(buf, "ENTER FLOOR {d}", .{n}) catch line;
        }
    }

    if (afterPrefix(line, "第 ")) |rest| {
        if (std.mem.indexOf(u8, rest, " 层：")) |at| {
            if (parseU32(rest[0..at])) |floor| {
                const tail = rest[at + " 层：".len ..];
                if (std.mem.indexOf(u8, tail, " 个敌人")) |e| {
                    if (parseU32(tail[0..e])) |count| return std.fmt.bufPrint(buf, "FLOOR {d}: {d} ENEMIES", .{ floor, count }) catch line;
                }
            }
        }
    }

    if (afterPrefix(line, "触发陷阱 -")) |rest| {
        if (std.mem.endsWith(u8, rest, " 生命")) {
            if (parseU32(rest[0 .. rest.len - 7])) |n| return std.fmt.bufPrint(buf, "TRAP -{d} HP", .{n}) catch line;
        }
    }
    if (afterPrefix(line, "打开宝箱：恢复 ")) |rest| {
        if (std.mem.endsWith(u8, rest, " 生命")) {
            if (parseU32(rest[0 .. rest.len - 7])) |n| return std.fmt.bufPrint(buf, "CHEST: +{d} HP", .{n}) catch line;
        }
    }
    if (afterPrefix(line, "诅咒宝箱 -")) |rest| {
        if (parseU32(rest)) |n| return std.fmt.bufPrint(buf, "CURSED CHEST -{d}", .{n}) catch line;
    }
    if (afterPrefix(line, "灼烧 -")) |rest| {
        if (parseU32(rest)) |n| return std.fmt.bufPrint(buf, "BURN -{d}", .{n}) catch line;
    }
    if (afterPrefix(line, "升级到 ")) |rest| {
        if (std.mem.indexOf(u8, rest, " 级")) |at| {
            if (parseU32(rest[0..at])) |n| {
                if (std.mem.indexOf(u8, rest, "属性点") != null) return std.fmt.bufPrint(buf, "LEVEL {d} +1 POINT", .{n}) catch line;
                return std.fmt.bufPrint(buf, "LEVEL {d}", .{n}) catch line;
            }
        }
    }
    if (afterPrefix(line, "深渊守卫 深渊斩 -")) |rest| {
        if (parseU32(rest)) |n| return std.fmt.bufPrint(buf, "ABYSS CLEAVE -{d}", .{n}) catch line;
    }
    if (afterPrefix(line, "石魔像 震地 -")) |rest| {
        if (parseU32(rest)) |n| return std.fmt.bufPrint(buf, "GOLEM QUAKE -{d}", .{n}) catch line;
    }
    if (afterPrefix(line, "幽魂 汲取 -")) |rest| {
        if (parseU32(rest)) |n| return std.fmt.bufPrint(buf, "WRAITH DRAIN -{d}", .{n}) catch line;
    }
    if (afterPrefix(line, "击杀 ")) |rest| {
        if (std.mem.indexOf(u8, rest, " +")) |at| {
            if (std.mem.endsWith(u8, rest, "XP")) {
                const name = rest[0..at];
                if (parseU32(rest[at + 2 .. rest.len - 2])) |xp| return std.fmt.bufPrint(buf, "KILL {s} +{d} XP", .{ enemyName(name), xp }) catch line;
            }
        }
    }
    if (afterPrefix(line, "命中 ")) |rest| {
        var it = std.mem.splitScalar(u8, rest, ' ');
        const name = it.next() orelse return line;
        const dmg = it.next() orelse return line;
        return std.fmt.bufPrint(buf, "HIT {s} {s}", .{ enemyName(name), dmg }) catch line;
    }
    if (std.mem.indexOf(u8, line, " 造成 ")) |at| {
        if (std.mem.endsWith(u8, line, " 伤害")) {
            const name = line[0..at];
            const dmg = line[at + " 造成 ".len .. line.len - " 伤害".len];
            return std.fmt.bufPrint(buf, "{s} DEALS {s}", .{ enemyName(name), dmg }) catch line;
        }
    }
    return line;
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

test "i18n: battle log lines translate common formats" {
    const saved = current;
    defer current = saved;
    set(1);
    var buf: [96]u8 = undefined;
    try std.testing.expectEqualStrings("ENTER FLOOR 2", logLine("进入第 2 层", &buf));
    try std.testing.expectEqualStrings("FLOOR 3: 8 ENEMIES", logLine("第 3 层：8 个敌人", &buf));
    try std.testing.expectEqualStrings("TRAP -12 HP", logLine("触发陷阱 -12 生命", &buf));
    try std.testing.expectEqualStrings("KILL WRAITH +5 XP", logLine("击杀 幽魂 +5XP", &buf));
    try std.testing.expectEqualStrings("WRAITH DEALS 7", logLine("幽魂 造成 7 伤害", &buf));
    try std.testing.expectEqualStrings("BURN -3", logLine("灼烧 -3", &buf));
}
