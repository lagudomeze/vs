//! Minimal PNG writer (8-bit RGB, unfiltered scanlines, stored deflate blocks).
//! Keeping this in-tree avoids a dependency on stb_image / libpng.
const std = @import("std");
const color = @import("color.zig");

fn crc32(bytes: []const u8) u32 {
    return std.hash.Crc32.hash(bytes);
}

fn writeU32Be(buf: []u8, offset: usize, v: u32) void {
    buf[offset + 0] = @intCast((v >> 24) & 0xff);
    buf[offset + 1] = @intCast((v >> 16) & 0xff);
    buf[offset + 2] = @intCast((v >> 8) & 0xff);
    buf[offset + 3] = @intCast(v & 0xff);
}

/// Encode an ARGB framebuffer as a PNG. Caller owns the returned bytes.
pub fn encode(gpa: std.mem.Allocator, width: u32, height: u32, pixels: []const u32) ![]u8 {
    std.debug.assert(pixels.len >= @as(usize, width) * @as(usize, height));
    const stride: usize = @as(usize, width) * 3 + 1;
    const raw_len = stride * @as(usize, height);
    const blocks = (raw_len + 65534) / 65535;
    const zlib_len = 2 + blocks * 5 + raw_len + 4;
    const total = 8 + (12 + 13) + (12 + zlib_len) + 12;

    const out = try gpa.alloc(u8, total);
    errdefer gpa.free(out);
    @memset(out, 0);

    var p: usize = 0;
    const sig = [8]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a };
    @memcpy(out[0..8], &sig);
    p = 8;

    // IHDR
    writeU32Be(out, p, 13);
    p += 4;
    @memcpy(out[p .. p + 4], "IHDR");
    p += 4;
    writeU32Be(out, p, width);
    writeU32Be(out, p + 4, height);
    out[p + 8] = 8; // bit depth
    out[p + 9] = 2; // colour type: truecolour
    out[p + 10] = 0; // compression
    out[p + 11] = 0; // filter
    out[p + 12] = 0; // interlace
    p += 13;
    writeU32Be(out, p, crc32(out[p - 17 .. p]));
    p += 4;

    // IDAT: build the zlib stream in place
    const idat_len_at = p;
    p += 4;
    @memcpy(out[p .. p + 4], "IDAT");
    p += 4;
    const zstart = p;

    out[p] = 0x78;
    out[p + 1] = 0x01;
    p += 2;

    var row: usize = 0;
    while (row < height) : (row += 1) {
        out[p] = 0; // filter type: none
        p += 1;
        const y: usize = row * @as(usize, width);
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const c = pixels[y + x];
            out[p + 0] = color.red(c);
            out[p + 1] = color.green(c);
            out[p + 2] = color.blue(c);
            p += 3;
        }
    }

    // Wrap the raw stream into stored deflate blocks. We have to shift bytes to
    // make room for the 5-byte block headers, so walk backwards.
    const raw_start = zstart + 2;
    const raw_end = raw_start + raw_len;
    std.debug.assert(raw_end == p);
    const adler = std.hash.Adler32.hash(out[raw_start..raw_end]);
    // Adler-32 sits at the very end of the zlib stream, right before IDAT's CRC.
    const adler_pos = zstart + zlib_len - 4;

    // Insert the stored-block headers, processing blocks back-to-front so the
    // source bytes are still intact when we copy them.
    var block_index: usize = blocks;
    while (block_index > 0) {
        block_index -= 1;
        const offset = block_index * 65535;
        const n: usize = @min(65535, raw_len - offset);
        const header = raw_start + block_index * (65535 + 5);
        std.mem.copyBackwards(
            u8,
            out[header + 5 .. header + 5 + n],
            out[raw_start + offset .. raw_start + offset + n],
        );
        out[header] = if (block_index + 1 == blocks) 0x01 else 0x00;
        out[header + 1] = @intCast(n & 0xff);
        out[header + 2] = @intCast((n >> 8) & 0xff);
        out[header + 3] = @intCast((~n) & 0xff);
        out[header + 4] = @intCast(((~n) >> 8) & 0xff);
    }
    std.debug.assert(raw_start + blocks * 5 + raw_len == adler_pos);
    writeU32Be(out, adler_pos, adler);
    const idat_data_len = zlib_len;
    writeU32Be(out, idat_len_at, @intCast(idat_data_len));
    writeU32Be(out, idat_len_at + 8 + idat_data_len, crc32(out[idat_len_at + 4 .. idat_len_at + 8 + idat_data_len]));

    // IEND
    const iend = total - 12;
    writeU32Be(out, iend, 0);
    @memcpy(out[iend + 4 .. iend + 8], "IEND");
    writeU32Be(out, iend + 8, crc32(out[iend + 4 .. iend + 8]));

    return out;
}

pub fn writePng(
    io: std.Io,
    gpa: std.mem.Allocator,
    path: []const u8,
    width: u32,
    height: u32,
    pixels: []const u32,
) !void {
    const data = try encode(gpa, width, height, pixels);
    defer gpa.free(data);

    const file = if (std.fs.path.isAbsolute(path))
        try std.Io.Dir.createFileAbsolute(io, path, .{})
    else
        try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, data);
}

test "png header" {
    const gpa = std.testing.allocator;
    const fb = try gpa.alloc(u32, 2 * 2);
    defer gpa.free(fb);
    @memset(fb, 0x000000);
    const data = try encode(gpa, 2, 2, fb);
    defer gpa.free(data);
    try std.testing.expect(data.len > 40);
    try std.testing.expectEqualStrings("\x89PNG\r\n\x1a\n", data[0..8]);
}
