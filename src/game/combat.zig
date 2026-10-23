//! M6 damage pipeline: the only place that turns a raw hit into HP loss.
//!
//! Every action (talent, basic attack, boss AOE) constructs a DamagePacket and
//! calls resolve(). Preview uses the same function with no RNG, so HUD numbers
//! cannot drift from combat math.
const std = @import("std");
const attributes = @import("attributes.zig");

/// Damage tags. The table below decides which defenses apply; adding a tag is
/// one enum member + one table row.
pub const DamageType = enum(u8) {
    physical,
    fire,
    cold,
    arcane,
    temporal,
};

pub const type_count = @typeInfo(DamageType).@"enum".field_names.len;

pub const DamageTypeDef = struct {
    armor_applies: bool = false,
    /// 0.25 = take 25% less; 0 = no resistance.
    default_resist: f32 = 0,
};

pub const type_defs = [type_count]DamageTypeDef{
    .{ .armor_applies = true },
    .{},
    .{},
    .{},
    .{},
};

pub fn typeDef(kind: DamageType) DamageTypeDef {
    return type_defs[@backingInt(kind)];
}

pub const Defense = struct {
    armor: f32 = 0,
    resist: [type_count]f32 = @splat(0),
};

pub const DamagePacket = struct {
    raw: f32 = 0,
    kind: DamageType = .physical,
    /// Already rolled by the caller; previews pass false.
    crit: bool = false,
};

pub const DamageResult = struct {
    amount: f32 = 0,
    crit: bool = false,
};

fn finite(value: f32) f32 {
    return if (std.math.isFinite(value)) value else 0;
}

/// Resolve one packet. This is deterministic: the caller owns the crit roll.
pub fn resolve(packet: DamagePacket, defense: Defense) DamageResult {
    const raw = @max(0, finite(packet.raw));
    if (raw == 0) return .{};

    var amount = raw;
    if (packet.crit) amount *= attributes.formulas.crit_multiplier;

    const def = typeDef(packet.kind);
    if (def.armor_applies) amount = attributes.damageAfterArmor(amount, defense.armor);

    const resist = std.math.clamp(finite(defense.resist[@backingInt(packet.kind)]) + def.default_resist, -0.90, 0.90);
    amount *= 1.0 - resist;

    return .{ .amount = @max(0, amount), .crit = packet.crit };
}

/// Expected damage for the HUD. Same pipeline, no crit roll.
pub fn preview(packet: DamagePacket, defense: Defense) f32 {
    return resolve(packet, defense).amount;
}

test "combat: physical armor and other damage types" {
    const defense = Defense{ .armor = 50 };
    try std.testing.expectApproxEqAbs(@as(f32, 57.5), preview(.{ .raw = 100 }, defense), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), preview(.{ .raw = 100, .kind = .fire }, defense), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 75), preview(.{ .raw = 100, .kind = .cold }, .{ .resist = .{ 0, 0, 0.25, 0, 0 } }), 0.001);
}

test "combat: crit is applied once and previews never roll" {
    try std.testing.expectApproxEqAbs(@as(f32, 150), preview(.{ .raw = 100, .crit = true }, .{}), 0.001);
    const r = resolve(.{ .raw = 100, .crit = true }, .{ .armor = 50 });
    try std.testing.expect(r.crit);
    try std.testing.expectApproxEqAbs(@as(f32, 86.25), r.amount, 0.001);
}

test "combat: invalid input cannot heal" {
    try std.testing.expectEqual(@as(f32, 0), preview(.{ .raw = -10 }, .{}));
    try std.testing.expectEqual(@as(f32, 0), preview(.{ .raw = std.math.nan(f32) }, .{}));
}
