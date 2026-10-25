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
    daily_streak: u32 = 0,
    daily_last_win_day: i64 = -1,
};

pub const default_path = "saves/records.json";
const max_bytes = 4096;

fn parseBytes(alloc: std.mem.Allocator, bytes: []const u8) !Records {
    var parsed = try std.json.parseFromSlice(Records, alloc, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    return parsed.value;
}

fn loadBackup(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ?Records {
    const bak = std.fmt.allocPrint(alloc, "{s}.bak", .{path}) catch return null;
    defer alloc.free(bak);
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, bak, alloc, .limited(max_bytes)) catch return null;
    defer alloc.free(bytes);
    return parseBytes(alloc, bytes) catch null;
}

fn preserveCorrupt(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !void {
    const dst = try std.fmt.allocPrint(alloc, "{s}.corrupt-{d}.json", .{ path, std.Io.Clock.real.now(io).toSeconds() });
    defer alloc.free(dst);
    std.Io.Dir.cwd().rename(path, std.Io.Dir.cwd(), dst, io) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    std.log.warn("records: corrupt file preserved at {s}", .{dst});
}

fn writeAtomic(io: std.Io, path: []const u8, bytes: []const u8) !void {
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writeStreamingAll(io, bytes);
    try atomic.replace(io);
}

pub fn load(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !Records {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return loadBackup(io, alloc, path) orelse .{},
        else => return err,
    };
    defer alloc.free(bytes);
    return parseBytes(alloc, bytes) catch |err| {
        std.log.warn("records: {s} is corrupt ({s}); trying backup", .{ path, @errorName(err) });
        preserveCorrupt(io, alloc, path) catch |preserve_err| {
            std.log.warn("records: could not preserve corrupt file: {s}", .{@errorName(preserve_err)});
        };
        return loadBackup(io, alloc, path) orelse .{};
    };
}

pub fn save(io: std.Io, alloc: std.mem.Allocator, path: []const u8, records: Records) !void {
    const bytes = try std.json.Stringify.valueAlloc(alloc, records, .{});
    defer alloc.free(bytes);
    if (std.mem.indexOfScalar(u8, path, '/')) |slash| {
        std.Io.Dir.cwd().createDirPath(io, path[0..slash]) catch {};
    }
    // Keep the previous valid copy before replacing the primary file.
    if (std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(max_bytes))) |old| {
        defer alloc.free(old);
        if (parseBytes(alloc, old)) |_| {
            const bak = try std.fmt.allocPrint(alloc, "{s}.bak", .{path});
            defer alloc.free(bak);
            writeAtomic(io, bak, old) catch {};
        } else |_| {}
    } else |_| {}
    try writeAtomic(io, path, bytes);
}

test "records: old json without daily fields still loads" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "records-old.json" });
    defer alloc.free(path);
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, "{\"wins\":2,\"deaths\":3}");

    const got = try load(io, alloc, path);
    try std.testing.expectEqual(@as(u32, 2), got.wins);
    try std.testing.expectEqual(@as(u32, 0), got.daily_streak);
    try std.testing.expectEqual(@as(i64, -1), got.daily_last_win_day);
}

test "records: corrupt file restores from backup" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "records-corrupt.json" });
    defer alloc.free(path);
    const bak = try std.fmt.allocPrint(alloc, "{s}.bak", .{path});
    defer alloc.free(bak);

    const bak_file = try std.Io.Dir.cwd().createFile(io, bak, .{});
    try bak_file.writeStreamingAll(io, "{\"wins\":7,\"best_floor\":3}");
    bak_file.close(io);
    const main_file = try std.Io.Dir.cwd().createFile(io, path, .{});
    try main_file.writeStreamingAll(io, "{broken");
    main_file.close(io);

    const got = try load(io, alloc, path);
    try std.testing.expectEqual(@as(u32, 7), got.wins);
    try std.testing.expectEqual(@as(u8, 3), got.best_floor);
}

test "records round-trip and missing file is empty" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    try std.testing.expectEqual(Records{}, try load(io, alloc, "saves/definitely-missing-records.json"));

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "records.json" });
    defer alloc.free(path);
    const want = Records{ .wins = 3, .deaths = 5, .best_floor = 3, .best_turn = 180, .best_kills = 24, .best_gold = 210, .wins_warrior = 2, .wins_mage = 1, .wins_chronomancer = 0, .chunk_clears = 4, .flawless_wins = 1, .daily_day = 20_000, .daily_best_floor = 2, .daily_best_kills = 9, .daily_streak = 3, .daily_last_win_day = 20_000 };
    try save(io, alloc, path, want);
    try std.testing.expectEqual(want, try load(io, alloc, path));
}
