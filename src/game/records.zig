//! Persistent run records shown on the start menu. Kept separate from the run
//! save so a corrupt/old save never wipes lifetime stats.
const std = @import("std");

pub const Records = struct {
    wins: u32 = 0,
    deaths: u32 = 0,
    best_floor: u8 = 1,
    best_turn: u32 = 0,
    best_kills: u32 = 0,
    best_gold: u32 = 0,
    wins_warrior: u32 = 0,
    wins_mage: u32 = 0,
    wins_chronomancer: u32 = 0,
    chunk_clears: u32 = 0,
    flawless_wins: u32 = 0,
    daily_day: i64 = -1,
    daily_best_floor: u8 = 0,
    daily_best_kills: u32 = 0,
};

pub const default_path = "saves/records.json";
const max_bytes = 4096;

pub fn load(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !Records {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer alloc.free(bytes);
    var parsed = std.json.parseFromSlice(Records, alloc, bytes, .{ .ignore_unknown_fields = true }) catch return .{};
    defer parsed.deinit();
    return parsed.value;
}

pub fn save(io: std.Io, alloc: std.mem.Allocator, path: []const u8, records: Records) !void {
    const bytes = try std.json.Stringify.valueAlloc(alloc, records, .{});
    defer alloc.free(bytes);
    if (std.mem.indexOfScalar(u8, path, '/')) |slash| {
        std.Io.Dir.cwd().createDirPath(io, path[0..slash]) catch {};
    }
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writeStreamingAll(io, bytes);
    try atomic.replace(io);
}

test "records round-trip and missing file is empty" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    try std.testing.expectEqual(Records{}, try load(io, alloc, "saves/definitely-missing-records.json"));

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "records.json" });
    defer alloc.free(path);
    const want = Records{ .wins = 3, .deaths = 5, .best_floor = 3, .best_turn = 180, .best_kills = 24, .best_gold = 210, .wins_warrior = 2, .wins_mage = 1, .wins_chronomancer = 0, .chunk_clears = 4, .flawless_wins = 1, .daily_day = 20_000, .daily_best_floor = 2, .daily_best_kills = 9 };
    try save(io, alloc, path, want);
    try std.testing.expectEqual(want, try load(io, alloc, path));
}
