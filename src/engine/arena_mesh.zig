//! Procedural diorama geometry: tiled floor, floating island base and rim.
const std = @import("std");
const math = @import("../core/math.zig");
const color = @import("../core/color.zig");

pub const Tri = struct {
    a: u32,
    b: u32,
    c: u32,
    color: u32,
    emissive: bool,
};

pub const Mesh = struct {
    verts: []math.Vec3,
    tris: []Tri,
};

pub const tile_half = 6; // 13x13 tiles
pub const tile_size = 1.0;
pub const arena_radius = 5.65;

pub fn heightAt(x: f32, z: f32) f32 {
    _ = x;
    _ = z;
    return 0.0;
}

const Builder = struct {
    gpa: std.mem.Allocator,
    verts: std.ArrayList(math.Vec3) = .empty,
    tris: std.ArrayList(Tri) = .empty,

    fn deinit(self: *Builder) void {
        self.verts.deinit(self.gpa);
        self.tris.deinit(self.gpa);
    }

    fn addVertex(self: *Builder, p: math.Vec3) !u32 {
        const idx: u32 = @intCast(self.verts.items.len);
        try self.verts.append(self.gpa, p);
        return idx;
    }

    fn tri(self: *Builder, p0: math.Vec3, p1: math.Vec3, p2: math.Vec3, c: u32, emissive: bool, hint: math.Vec3) !void {
        const va = p0;
        var vb = p1;
        var vc = p2;
        const n = vb.sub(va).cross(vc.sub(va));
        if (n.lengthSquared() < 1e-12) return;
        if (n.dot(hint) < 0) {
            const tmp = vb;
            vb = vc;
            vc = tmp;
        }
        const a = try self.addVertex(va);
        const b = try self.addVertex(vb);
        const cc = try self.addVertex(vc);
        try self.tris.append(self.gpa, .{ .a = a, .b = b, .c = cc, .color = c, .emissive = emissive });
    }

    fn quad(self: *Builder, p0: math.Vec3, p1: math.Vec3, p2: math.Vec3, p3: math.Vec3, c: u32, hint: math.Vec3) !void {
        try self.tri(p0, p1, p2, c, false, hint);
        try self.tri(p0, p2, p3, c, false, hint);
    }

    fn box(self: *Builder, center: math.Vec3, half: math.Vec3, top: u32, side: u32, bottom: u32) !void {
        const x = half.x;
        const y = half.y;
        const z = half.z;
        const p = center;
        const v000 = math.Vec3.init(p.x - x, p.y - y, p.z - z);
        const v100 = math.Vec3.init(p.x + x, p.y - y, p.z - z);
        const v110 = math.Vec3.init(p.x + x, p.y - y, p.z + z);
        const v010 = math.Vec3.init(p.x - x, p.y - y, p.z + z);
        const v001 = math.Vec3.init(p.x - x, p.y + y, p.z - z);
        const v101 = math.Vec3.init(p.x + x, p.y + y, p.z - z);
        const v111 = math.Vec3.init(p.x + x, p.y + y, p.z + z);
        const v011 = math.Vec3.init(p.x - x, p.y + y, p.z + z);
        try self.quad(v001, v011, v111, v101, top, math.Vec3.init(0, 1, 0));
        try self.quad(v000, v100, v110, v010, bottom, math.Vec3.init(0, -1, 0));
        try self.quad(v000, v001, v101, v100, side, math.Vec3.init(0, 0, -1));
        try self.quad(v010, v110, v111, v011, side, math.Vec3.init(0, 0, 1));
        try self.quad(v000, v010, v011, v001, side, math.Vec3.init(-1, 0, 0));
        try self.quad(v100, v101, v111, v110, side, math.Vec3.init(1, 0, 0));
    }

    fn finish(self: *Builder) !Mesh {
        const verts = try self.verts.toOwnedSlice(self.gpa);
        errdefer self.gpa.free(verts);
        const tris = try self.tris.toOwnedSlice(self.gpa);
        return .{ .verts = verts, .tris = tris };
    }
};

fn stoneColor(seed: u32) u32 {
    const h = color.hashU32(seed *% 2654435761 +% 0x9e3779b9);
    const variant = h % 100;
    if (variant < 6) return color.pack(47, 107, 90); // moss
    if (variant < 12) return color.pack(45, 52, 68); // dark tile
    const base: i32 = 96 + @as(i32, @intCast((h >> 8) % 26));
    return color.pack(
        @intCast(@min(255, base + 12)),
        @intCast(@min(255, base + 2)),
        @intCast(@max(0, base - 10)),
    );
}

pub fn buildArena(gpa: std.mem.Allocator) !Mesh {
    var b = Builder{ .gpa = gpa };
    errdefer b.deinit();

    const half_world: f32 = @as(f32, @floatFromInt(tile_half)) * tile_size + 0.5;

    // ---- floating island underside (inverted stepped pyramid) ----
    try b.box(.{ .x = 0, .y = -0.40, .z = 0 }, math.Vec3.init(half_world + 0.15, 0.35, half_world + 0.15), color.pack(31, 37, 51), color.pack(26, 30, 42), color.pack(20, 23, 32));
    try b.box(.{ .x = 0, .y = -0.95, .z = 0 }, math.Vec3.init(half_world - 0.55, 0.50, half_world - 0.55), color.pack(31, 37, 51), color.pack(22, 26, 36), color.pack(16, 19, 26));
    try b.box(.{ .x = 0, .y = -1.55, .z = 0 }, math.Vec3.init(half_world - 1.7, 0.60, half_world - 1.7), color.pack(24, 28, 38), color.pack(18, 21, 30), color.pack(12, 14, 20));

    // ---- floor tiles ----
    const y: f32 = 0.0;
    var tz: i32 = -tile_half;
    while (tz <= tile_half) : (tz += 1) {
        var tx: i32 = -tile_half;
        while (tx <= tile_half) : (tx += 1) {
            const cx = @as(f32, @floatFromInt(tx)) * tile_size;
            const cz = @as(f32, @floatFromInt(tz)) * tile_size;
            const h = color.hashU32(@as(u32, @bitCast(tx)) ^ (@as(u32, @bitCast(tz)) << 16) ^ 0x51ed270b);
            const inset: f32 = 0.012 + 0.010 * @as(f32, @floatFromInt(h % 5)) / 5.0;
            const c = stoneColor(h);
            const p0 = math.Vec3.init(cx - 0.5 + inset, y, cz - 0.5 + inset);
            const p1 = math.Vec3.init(cx + 0.5 - inset, y, cz - 0.5 + inset);
            const p2 = math.Vec3.init(cx + 0.5 - inset, y, cz + 0.5 - inset);
            const p3 = math.Vec3.init(cx - 0.5 + inset, y, cz + 0.5 - inset);
            try b.quad(p0, p3, p2, p1, c, math.Vec3.init(0, 1, 0));

            // occasional crack
            if (h % 37 == 0) {
                const ox = (@as(f32, @floatFromInt((h >> 8) % 7)) - 3.0) * 0.07;
                const oz = (@as(f32, @floatFromInt((h >> 11) % 7)) - 3.0) * 0.07;
                const a = math.Vec3.init(cx + ox - 0.18, 0.004, cz + oz - 0.04);
                const bb = math.Vec3.init(cx + ox + 0.20, 0.004, cz + oz + 0.03);
                const cc = math.Vec3.init(cx + ox + 0.16, 0.004, cz + oz + 0.08);
                const dd = math.Vec3.init(cx + ox - 0.22, 0.004, cz + oz + 0.01);
                try b.quad(a, dd, cc, bb, color.pack(20, 23, 32), math.Vec3.init(0, 1, 0));
            }
        }
    }

    // dark mortar base, visible in the tile gaps
    try b.quad(
        math.Vec3.init(-half_world, -0.03, -half_world),
        math.Vec3.init(-half_world, -0.03, half_world),
        math.Vec3.init(half_world, -0.03, half_world),
        math.Vec3.init(half_world, -0.03, -half_world),
        color.pack(31, 37, 51),
        math.Vec3.init(0, 1, 0),
    );

    // ---- raised rim ----
    const rim_y: f32 = 0.09;
    const rim_h: f32 = 0.09;
    const rim_w: f32 = 0.34;
    try b.box(.{ .x = 0, .y = rim_y, .z = -half_world + rim_w }, math.Vec3.init(half_world, rim_h, rim_w), color.pack(83, 93, 112), color.pack(62, 71, 89), color.pack(45, 52, 68));
    try b.box(.{ .x = 0, .y = rim_y, .z = half_world - rim_w }, math.Vec3.init(half_world, rim_h, rim_w), color.pack(83, 93, 112), color.pack(62, 71, 89), color.pack(45, 52, 68));
    try b.box(.{ .x = -half_world + rim_w, .y = rim_y, .z = 0 }, math.Vec3.init(rim_w, rim_h, half_world - 2 * rim_w), color.pack(83, 93, 112), color.pack(62, 71, 89), color.pack(45, 52, 68));
    try b.box(.{ .x = half_world - rim_w, .y = rim_y, .z = 0 }, math.Vec3.init(rim_w, rim_h, half_world - 2 * rim_w), color.pack(83, 93, 112), color.pack(62, 71, 89), color.pack(45, 52, 68));

    // corner plinths
    const corners = [_]math.Vec2{
        .{ .x = -half_world + rim_w, .y = -half_world + rim_w },
        .{ .x = half_world - rim_w, .y = -half_world + rim_w },
        .{ .x = -half_world + rim_w, .y = half_world - rim_w },
        .{ .x = half_world - rim_w, .y = half_world - rim_w },
    };
    for (corners) |c| {
        try b.box(.{ .x = c.x, .y = 0.15, .z = c.y }, math.Vec3.init(0.46, 0.15, 0.46), color.pack(107, 116, 136), color.pack(62, 71, 89), color.pack(45, 52, 68));
    }

    // ---- stone plinth framing the ritual carpet ----
    const py: f32 = 0.004;
    try b.quad(
        math.Vec3.init(-3.05, py, -1.85),
        math.Vec3.init(-3.05, py, 2.20),
        math.Vec3.init(3.05, py, 2.20),
        math.Vec3.init(3.05, py, -1.85),
        color.pack(74, 79, 92),
        math.Vec3.init(0, 1, 0),
    );
    const carpet_corners = [_][2]f32{ .{ -2.85, -1.65 }, .{ 2.85, -1.65 }, .{ -2.85, 2.0 }, .{ 2.85, 2.0 } };
    for (carpet_corners) |c| {
        try b.quad(
            math.Vec3.init(c[0] - 0.16, py + 0.001, c[1] - 0.16),
            math.Vec3.init(c[0] - 0.16, py + 0.001, c[1] + 0.16),
            math.Vec3.init(c[0] + 0.16, py + 0.001, c[1] + 0.16),
            math.Vec3.init(c[0] + 0.16, py + 0.001, c[1] - 0.16),
            color.pack(201, 121, 31),
            math.Vec3.init(0, 1, 0),
        );
    }

    // ---- crimson ritual carpet under the party ----
    const cy: f32 = 0.008;
    const rx: f32 = 2.55;
    const z0: f32 = -1.35;
    const z1: f32 = 1.70;
    try b.quad(
        math.Vec3.init(-rx, cy, z0),
        math.Vec3.init(-rx, cy, z1),
        math.Vec3.init(rx, cy, z1),
        math.Vec3.init(rx, cy, z0),
        color.pack(234, 166, 46),
        math.Vec3.init(0, 1, 0),
    );
    try b.quad(
        math.Vec3.init(-rx + 0.16, cy + 0.001, z0 + 0.16),
        math.Vec3.init(-rx + 0.16, cy + 0.001, z1 - 0.16),
        math.Vec3.init(rx - 0.16, cy + 0.001, z1 - 0.16),
        math.Vec3.init(rx - 0.16, cy + 0.001, z0 + 0.16),
        color.pack(94, 26, 34),
        math.Vec3.init(0, 1, 0),
    );
    // inner gold pinstripe
    const line_y = cy + 0.002;
    const inset: f32 = 0.30;
    try b.quad(
        math.Vec3.init(-rx + inset, line_y, z0 + inset),
        math.Vec3.init(-rx + inset, line_y, z1 - inset),
        math.Vec3.init(rx - inset, line_y, z1 - inset),
        math.Vec3.init(rx - inset, line_y, z0 + inset),
        color.pack(201, 121, 31),
        math.Vec3.init(0, 1, 0),
    );
    try b.quad(
        math.Vec3.init(-rx + inset + 0.04, line_y + 0.0005, z0 + inset + 0.04),
        math.Vec3.init(-rx + inset + 0.04, line_y + 0.0005, z1 - inset - 0.04),
        math.Vec3.init(rx - inset - 0.04, line_y + 0.0005, z1 - inset - 0.04),
        math.Vec3.init(rx - inset - 0.04, line_y + 0.0005, z0 + inset + 0.04),
        color.pack(94, 26, 34),
        math.Vec3.init(0, 1, 0),
    );

    // central gold diamond
    const ex: f32 = 0.0;
    const ez: f32 = 0.20;
    const ey = cy + 0.003;
    const d: f32 = 0.62;
    try b.quad(
        math.Vec3.init(ex, ey, ez - d),
        math.Vec3.init(ex - d, ey, ez),
        math.Vec3.init(ex, ey, ez + d),
        math.Vec3.init(ex + d, ey, ez),
        color.pack(234, 166, 46),
        math.Vec3.init(0, 1, 0),
    );
    const d2: f32 = 0.48;
    try b.quad(
        math.Vec3.init(ex, ey + 0.001, ez - d2),
        math.Vec3.init(ex - d2, ey + 0.001, ez),
        math.Vec3.init(ex, ey + 0.001, ez + d2),
        math.Vec3.init(ex + d2, ey + 0.001, ez),
        color.pack(94, 26, 34),
        math.Vec3.init(0, 1, 0),
    );

    return b.finish();
}

pub fn buildDungeon(
    gpa: std.mem.Allocator,
    blocked: []const bool,
    width: usize,
    height: usize,
    stairs_cell: ?[2]i32,
) !Mesh {
    std.debug.assert(blocked.len == width * height);
    var b = Builder{ .gpa = gpa };
    errdefer b.deinit();

    const hw: f32 = @as(f32, @floatFromInt(width)) * 0.5;
    const hh: f32 = @as(f32, @floatFromInt(height)) * 0.5;
    const half_world = @max(hw, hh) + 0.55;

    // floating dungeon slab
    try b.box(.{ .x = 0, .y = -0.38, .z = 0 }, math.Vec3.init(half_world + 0.15, 0.34, half_world + 0.15), color.pack(31, 37, 51), color.pack(26, 30, 42), color.pack(20, 23, 32));
    try b.box(.{ .x = 0, .y = -0.92, .z = 0 }, math.Vec3.init(half_world - 0.55, 0.50, half_world - 0.55), color.pack(31, 37, 51), color.pack(22, 26, 36), color.pack(16, 19, 26));
    try b.box(.{ .x = 0, .y = -1.52, .z = 0 }, math.Vec3.init(half_world - 1.7, 0.60, half_world - 1.7), color.pack(24, 28, 38), color.pack(18, 21, 30), color.pack(12, 14, 20));

    var row: usize = 0;
    while (row < height) : (row += 1) {
        var col: usize = 0;
        while (col < width) : (col += 1) {
            const x: f32 = @as(f32, @floatFromInt(col)) - @as(f32, @floatFromInt(width - 1)) * 0.5;
            const z: f32 = @as(f32, @floatFromInt(row)) - @as(f32, @floatFromInt(height - 1)) * 0.5;
            const idx = row * width + col;
            if (blocked[idx]) {
                const h = color.hashU32(@as(u32, @intCast(idx)) * 97 + 13);
                const top = color.pack(52 + @as(u8, @intCast(h % 7)), 58 + @as(u8, @intCast(h % 5)), 72 + @as(u8, @intCast(h % 6)));
                const side = color.pack(38, 43, 55);
                try b.box(.{ .x = x, .y = 0.55, .z = z }, math.Vec3.init(0.5, 0.55, 0.5), top, side, color.pack(25, 29, 39));
                try b.box(.{ .x = x, .y = 1.13, .z = z }, math.Vec3.init(0.5, 0.03, 0.5), color.pack(78, 88, 108), side, side);
            } else {
                if (stairs_cell) |sc| {
                    if (col == @as(usize, @intCast(sc[0])) and row == @as(usize, @intCast(sc[1]))) continue;
                }
                const c = stoneColor(@as(u32, @intCast(idx)) * 131 + 29);
                try b.quad(
                    math.Vec3.init(x - 0.5, 0.002, z - 0.5),
                    math.Vec3.init(x - 0.5, 0.002, z + 0.5),
                    math.Vec3.init(x + 0.5, 0.002, z + 0.5),
                    math.Vec3.init(x + 0.5, 0.002, z - 0.5),
                    c,
                    math.Vec3.init(0, 1, 0),
                );
                // subtle tile seam
                try b.quad(
                    math.Vec3.init(x - 0.5, 0.004, z - 0.5),
                    math.Vec3.init(x - 0.5, 0.004, z - 0.42),
                    math.Vec3.init(x + 0.5, 0.004, z - 0.42),
                    math.Vec3.init(x + 0.5, 0.004, z - 0.5),
                    color.pack(45, 52, 68),
                    math.Vec3.init(0, 1, 0),
                );
            }
        }
    }
    // grid seams: make the cells readable under the 3D models
    const gx0: f32 = -@as(f32, @floatFromInt(width)) * 0.5;
    const gz0: f32 = -@as(f32, @floatFromInt(height)) * 0.5;
    var gi: usize = 0;
    while (gi <= width) : (gi += 1) {
        const gx = gx0 + @as(f32, @floatFromInt(gi));
        try b.quad(
            math.Vec3.init(gx - 0.009, 0.007, gz0),
            math.Vec3.init(gx - 0.009, 0.007, gz0 + @as(f32, @floatFromInt(height))),
            math.Vec3.init(gx + 0.009, 0.007, gz0 + @as(f32, @floatFromInt(height))),
            math.Vec3.init(gx + 0.009, 0.007, gz0),
            color.pack(43, 50, 66),
            math.Vec3.init(0, 1, 0),
        );
    }
    gi = 0;
    while (gi <= height) : (gi += 1) {
        const gz = gz0 + @as(f32, @floatFromInt(gi));
        try b.quad(
            math.Vec3.init(gx0, 0.007, gz - 0.009),
            math.Vec3.init(gx0, 0.007, gz + 0.009),
            math.Vec3.init(gx0 + @as(f32, @floatFromInt(width)), 0.007, gz + 0.009),
            math.Vec3.init(gx0 + @as(f32, @floatFromInt(width)), 0.007, gz - 0.009),
            color.pack(43, 50, 66),
            math.Vec3.init(0, 1, 0),
        );
    }
    return b.finish();
}

test "dungeon mesh builds" {
    const gpa = std.testing.allocator;
    var blocked: [169]bool = @splat(false);
    for (0..13) |i| {
        blocked[i] = true;
        blocked[12 * 13 + i] = true;
        blocked[i * 13] = true;
        blocked[i * 13 + 12] = true;
    }
    const mesh = try buildDungeon(gpa, &blocked, 13, 13, null);
    defer gpa.free(mesh.verts);
    defer gpa.free(mesh.tris);
    try std.testing.expect(mesh.tris.len > 300);
    try std.testing.expect(mesh.verts.len > 800);
}

test "arena mesh builds" {
    const gpa = std.testing.allocator;
    const mesh = try buildArena(gpa);
    defer gpa.free(mesh.verts);
    defer gpa.free(mesh.tris);
    try std.testing.expect(mesh.tris.len > 450);
    try std.testing.expect(mesh.verts.len > 1200);
}
