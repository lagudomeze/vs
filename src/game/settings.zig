//! Window/display preferences. Kept out of the run save so a corrupt run
//! never resets video settings (and vice versa).
const std = @import("std");

pub const Settings = struct {
    fullscreen: bool = false,
    scale: u8 = 3,
    vsync: bool = true,

    pub fn sanitized(self: Settings) Settings {
        var s = self;
        s.scale = @min(@max(s.scale, 2), 4);
        return s;
    }
};

pub const default_path = "saves/settings.json";
const max_bytes = 1024;

pub fn load(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !Settings {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer alloc.free(bytes);
    var parsed = std.json.parseFromSlice(Settings, alloc, bytes, .{ .ignore_unknown_fields = true }) catch return .{};
    defer parsed.deinit();
    return parsed.value.sanitized();
}

pub fn save(io: std.Io, alloc: std.mem.Allocator, path: []const u8, settings: Settings) !void {
    const bytes = try std.json.Stringify.valueAlloc(alloc, settings.sanitized(), .{});
    defer alloc.free(bytes);
    if (std.mem.indexOfScalar(u8, path, '/')) |slash| {
        std.Io.Dir.cwd().createDirPath(io, path[0..slash]) catch {};
    }
    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writeStreamingAll(io, bytes);
    try atomic.replace(io);
}

test "settings round-trip, defaults and clamp" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    try std.testing.expectEqual(Settings{}, try load(io, alloc, "saves/definitely-missing-settings.json"));

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "settings.json" });
    defer alloc.free(path);
    const want = Settings{ .fullscreen = true, .scale = 4, .vsync = false };
    try save(io, alloc, path, want);
    try std.testing.expectEqual(want, try load(io, alloc, path));
    try std.testing.expectEqual(@as(u8, 4), (Settings{ .scale = 99 }).sanitized().scale);
}
