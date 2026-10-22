//! sRGB helpers used by the software renderer.
const std = @import("std");

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub const linear_from_srgb: [256]f32 = blk: {
    @setEvalBranchQuota(100_000);
    var table: [256]f32 = undefined;
    for (&table, 0..) |*entry, i| {
        const c = @as(f32, @floatFromInt(i)) / 255.0;
        entry.* = if (c <= 0.04045) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
    }
    break :blk table;
};

pub fn srgbToLinear(v: u8) f32 {
    return linear_from_srgb[v];
}

pub fn linearToSrgb(x: f32) u8 {
    const c = std.math.clamp(x, 0.0, 1.0);
    const s = if (c <= 0.0031308) 12.92 * c else 1.055 * std.math.pow(f32, c, 1.0 / 2.4) - 0.055;
    return @intFromFloat(std.math.clamp(s * 255.0, 0.0, 255.0));
}

pub fn pack(r: u8, g: u8, b: u8) u32 {
    return (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
}

pub fn packRgb(c: Rgb) u32 {
    return pack(c.r, c.g, c.b);
}

pub fn red(c: u32) u8 {
    return @intCast((c >> 16) & 0xff);
}

pub fn green(c: u32) u8 {
    return @intCast((c >> 8) & 0xff);
}

pub fn blue(c: u32) u8 {
    return @intCast(c & 0xff);
}

pub fn unpack(c: u32) Rgb {
    return .{ .r = red(c), .g = green(c), .b = blue(c) };
}

pub fn scale(c: u32, s: f32) u32 {
    const rgb = unpack(c);
    return pack(
        @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(rgb.r)) * s, 0, 255)),
        @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(rgb.g)) * s, 0, 255)),
        @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(rgb.b)) * s, 0, 255)),
    );
}

pub fn lerp(a: u32, b: u32, t: f32) u32 {
    const ca = unpack(a);
    const cb = unpack(b);
    const f = std.math.clamp(t, 0, 1);
    return pack(
        @intFromFloat(@as(f32, @floatFromInt(ca.r)) + (@as(f32, @floatFromInt(cb.r)) - @as(f32, @floatFromInt(ca.r))) * f),
        @intFromFloat(@as(f32, @floatFromInt(ca.g)) + (@as(f32, @floatFromInt(cb.g)) - @as(f32, @floatFromInt(ca.g))) * f),
        @intFromFloat(@as(f32, @floatFromInt(ca.b)) + (@as(f32, @floatFromInt(cb.b)) - @as(f32, @floatFromInt(ca.b))) * f),
    );
}

/// Deterministic hash used for tile variation and particles.
pub fn hashU32(x0: u32) u32 {
    var x = x0;
    x ^= x >> 16;
    x *%= 0x7feb352d;
    x ^= x >> 15;
    x *%= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

pub fn hashFloat(seed: u32) f32 {
    return @as(f32, @floatFromInt(hashU32(seed) & 0xffff)) / 65535.0;
}

test "srgb roundtrip" {
    try std.testing.expectEqual(@as(u8, 0), linearToSrgb(srgbToLinear(0)));
    try std.testing.expect(@abs(@as(i32, linearToSrgb(srgbToLinear(255))) - 255) <= 1);
    try std.testing.expect(@abs(@as(i32, linearToSrgb(srgbToLinear(128))) - 128) <= 1);
}
