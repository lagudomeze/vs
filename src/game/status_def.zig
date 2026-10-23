//! Status registry: one place for tags, labels, colours and debuff metadata.
//! Behaviour still lives on StatusSet; this table keeps UI/help/cleanse in sync.
const std = @import("std");
const palette = @import("../core/palette.zig");

pub const Kind = enum(u8) { stun, slow, buff, burn, vulnerable, guard };

pub const max_burn_stacks: u8 = 3;

pub const Def = struct {
    kind: Kind,
    tag: []const u8,
    label: []const u8,
    color: u32,
    debuff: bool = false,
};

pub const defs = [_]Def{
    .{ .kind = .stun, .tag = "STUN", .label = "眩晕", .color = palette.red, .debuff = true },
    .{ .kind = .slow, .tag = "SLOW", .label = "减速", .color = palette.cyan_light, .debuff = true },
    .{ .kind = .buff, .tag = "BUFF", .label = "增益", .color = palette.gold },
    .{ .kind = .burn, .tag = "BURN", .label = "灼烧", .color = palette.red, .debuff = true },
    .{ .kind = .vulnerable, .tag = "VULN", .label = "破绽", .color = palette.red, .debuff = true },
    .{ .kind = .guard, .tag = "GUARD", .label = "举盾", .color = palette.cyan_light },
};

pub fn get(kind: Kind) Def {
    for (defs) |d| {
        if (d.kind == kind) return d;
    }
    unreachable;
}

pub fn tag(kind: Kind) []const u8 {
    return get(kind).tag;
}

pub fn label(kind: Kind) []const u8 {
    return get(kind).label;
}

test "status defs are unique and tag-sized" {
    var seen: [defs.len]bool = @splat(false);
    for (defs) |d| {
        const i = @backingInt(d.kind);
        try std.testing.expect(!seen[i]);
        seen[i] = true;
        try std.testing.expect(d.tag.len > 0 and d.tag.len <= 6);
        try std.testing.expect(d.label.len > 0);
    }
}
