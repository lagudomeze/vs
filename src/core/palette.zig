//! A curated 64-colour palette plus ordered-dither quantisation. This is what
//! gives the renderer its pixel-art identity.
const std = @import("std");
const color = @import("color.zig");

pub const Rgb = [3]u8;

pub const colors: [64]Rgb = .{
    // deep neutrals
    .{ 11, 12, 18 }, // 0 outline / void
    .{ 20, 24, 36 }, // 1 panel
    .{ 31, 37, 51 }, // 2 stone shadow
    .{ 45, 52, 68 }, // 3
    .{ 62, 71, 89 }, // 4 border
    .{ 83, 93, 112 }, // 5
    .{ 107, 116, 136 }, // 6 muted
    .{ 139, 147, 165 }, // 7
    .{ 184, 191, 204 }, // 8
    .{ 230, 235, 242 }, // 9 cream
    // browns / wood / leather
    .{ 42, 31, 26 }, // 10
    .{ 62, 45, 35 }, // 11
    .{ 90, 64, 48 }, // 12
    .{ 122, 90, 63 }, // 13
    .{ 156, 118, 84 }, // 14
    .{ 191, 151, 112 }, // 15
    .{ 224, 188, 147 }, // 16
    // reds
    .{ 58, 17, 22 }, // 17
    .{ 94, 26, 34 }, // 18
    .{ 140, 39, 51 }, // 19
    .{ 184, 58, 69 }, // 20
    .{ 224, 90, 90 }, // 21
    .{ 240, 138, 122 }, // 22
    // orange / gold
    .{ 92, 47, 17 }, // 23
    .{ 143, 74, 20 }, // 24
    .{ 201, 121, 31 }, // 25
    .{ 234, 166, 46 }, // 26
    .{ 255, 212, 94 }, // 27
    .{ 255, 242, 168 }, // 28
    // greens
    .{ 22, 48, 29 }, // 29
    .{ 36, 81, 44 }, // 30
    .{ 58, 122, 63 }, // 31
    .{ 90, 168, 75 }, // 32
    .{ 143, 209, 102 }, // 33
    // teal / cyan
    .{ 15, 47, 51 }, // 34
    .{ 23, 82, 89 }, // 35
    .{ 34, 131, 138 }, // 36
    .{ 53, 184, 176 }, // 37
    .{ 111, 224, 208 }, // 38
    // blues
    .{ 16, 26, 51 }, // 39
    .{ 27, 44, 90 }, // 40
    .{ 43, 74, 140 }, // 41
    .{ 74, 122, 196 }, // 42
    .{ 127, 179, 239 }, // 43
    // purples
    .{ 36, 20, 48 }, // 44
    .{ 61, 32, 88 }, // 45
    .{ 93, 52, 136 }, // 46
    .{ 138, 84, 189 }, // 47
    .{ 185, 128, 230 }, // 48
    // pink / magenta
    .{ 122, 31, 85 }, // 49
    .{ 195, 58, 138 }, // 50
    .{ 239, 127, 192 }, // 51
    // accents
    .{ 217, 199, 163 }, // 52 bone
    .{ 74, 79, 92 }, // 53 iron
    .{ 47, 107, 90 }, // 54 moss
    .{ 122, 62, 42 }, // 55 rust
    .{ 240, 163, 94 }, // 56 skin light
    .{ 201, 139, 107 }, // 57 skin
    .{ 255, 248, 231 }, // 58 highlight
    .{ 15, 18, 24 }, // 59 deep
    .{ 26, 18, 32 }, // 60 plum shadow
    .{ 43, 58, 85 }, // 61 cold shadow
    .{ 70, 96, 127 }, // 62
    .{ 154, 209, 255 }, // 63 ice
};

pub const outline = color.pack(colors[0][0], colors[0][1], colors[0][2]);
pub const panel = color.pack(colors[1][0], colors[1][1], colors[1][2]);
pub const border = color.pack(colors[4][0], colors[4][1], colors[4][2]);
pub const muted = color.pack(colors[7][0], colors[7][1], colors[7][2]);
pub const cream = color.pack(colors[9][0], colors[9][1], colors[9][2]);
pub const gold = color.pack(colors[26][0], colors[26][1], colors[26][2]);
pub const gold_light = color.pack(colors[27][0], colors[27][1], colors[27][2]);
pub const red = color.pack(colors[20][0], colors[20][1], colors[20][2]);
pub const cyan = color.pack(colors[37][0], colors[37][1], colors[37][2]);
pub const cyan_light = color.pack(colors[38][0], colors[38][1], colors[38][2]);
pub const deep = color.pack(colors[59][0], colors[59][1], colors[59][2]);
pub const health = color.pack(colors[19][0], colors[19][1], colors[19][2]);
pub const health_light = color.pack(colors[21][0], colors[21][1], colors[21][2]);

pub fn bayer(x: u32, y: u32) u8 {
    return bayer4[y & 3][x & 3];
}

const bayer4 = [4][4]u8{
    .{ 0, 8, 2, 10 },
    .{ 12, 4, 14, 6 },
    .{ 3, 11, 1, 9 },
    .{ 15, 7, 13, 5 },
};

pub const Palette = struct {
    cache: [32768]u8 = @splat(255),
    dither_strength: f32 = 5.0,

    pub fn nearest(self: *Palette, r: u8, g: u8, b: u8) u8 {
        const key: u16 = (@as(u16, r >> 3) << 10) | (@as(u16, g >> 3) << 5) | @as(u16, b >> 3);
        const idx = self.cache[key];
        if (idx != 255) return idx;

        var best: u8 = 0;
        var best_dist: i32 = std.math.maxInt(i32);
        for (colors, 0..) |c, i| {
            const dr = @as(i32, r) - @as(i32, c[0]);
            const dg = @as(i32, g) - @as(i32, c[1]);
            const db = @as(i32, b) - @as(i32, c[2]);
            const dist = dr * dr * 2 + dg * dg * 4 + db * db * 3;
            if (dist < best_dist) {
                best_dist = dist;
                best = @intCast(i);
            }
        }
        self.cache[key] = best;
        return best;
    }

    pub fn ditherOffset(self: *const Palette, x: u32, y: u32) f32 {
        const v = @as(f32, @floatFromInt(bayer(x, y)));
        return (v / 16.0 - 0.46875) * self.dither_strength;
    }

    pub fn quantize(self: *Palette, rgb: u32, x: u32, y: u32) u32 {
        const off = self.ditherOffset(x, y);
        const c = color.unpack(rgb);
        const r = @as(f32, @floatFromInt(c.r)) + off;
        const g = @as(f32, @floatFromInt(c.g)) + off;
        const b = @as(f32, @floatFromInt(c.b)) + off;
        const ri: u8 = @intFromFloat(std.math.clamp(r, 0, 255));
        const gi: u8 = @intFromFloat(std.math.clamp(g, 0, 255));
        const bi: u8 = @intFromFloat(std.math.clamp(b, 0, 255));
        const idx = self.nearest(ri, gi, bi);
        return color.pack(colors[idx][0], colors[idx][1], colors[idx][2]);
    }

    pub fn exact(self: *Palette, idx: usize) u32 {
        _ = self;
        return color.pack(colors[idx][0], colors[idx][1], colors[idx][2]);
    }
};

test "palette nearest exact" {
    var p = Palette{};
    const r = colors[26][0];
    const g = colors[26][1];
    const b = colors[26][2];
    const idx = p.nearest(r, g, b);
    try std.testing.expectEqual(@as(Rgb, colors[26]), colors[idx]);
}
