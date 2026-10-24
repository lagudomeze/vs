//! Window/display preferences. Kept out of the run save so a corrupt run
//! never resets video settings (and vice versa).
const std = @import("std");

/// SDL scancode values. Defaults match SDL3's stable key codes.
pub const Keys = struct {
    confirm: u32 = 44, // SPACE
    potion: u32 = 19, // P
    bomb: u32 = 5, // B
    inventory: u32 = 12, // I
    character: u32 = 6, // C
    talent1: u32 = 30, // 1
    talent2: u32 = 31, // 2
    talent3: u32 = 32, // 3
};

pub const Settings = struct {
    fullscreen: bool = false,
    scale: u8 = 3,
    vsync: bool = true,
    volume: f32 = 0.55,
    ambient: bool = true,
    pad_swap: bool = false,
    esdf: bool = false,
    keys: Keys = .{},

    pub fn sanitized(self: Settings) Settings {
        var s = self;
        s.scale = @min(@max(s.scale, 2), 4);
        s.volume = std.math.clamp(s.volume, 0, 1);
        s.keys.confirm = keyCode(s.keys.confirm, 44);
        s.keys.potion = keyCode(s.keys.potion, 19);
        s.keys.bomb = keyCode(s.keys.bomb, 5);
        s.keys.inventory = keyCode(s.keys.inventory, 12);
        s.keys.character = keyCode(s.keys.character, 6);
        s.keys.talent1 = keyCode(s.keys.talent1, 30);
        s.keys.talent2 = keyCode(s.keys.talent2, 31);
        s.keys.talent3 = keyCode(s.keys.talent3, 32);
        return s;
    }
};

fn keyCode(value: u32, fallback: u32) u32 {
    if (value < 1 or value > 300 or value == 41) return fallback; // 41 = ESC
    return value;
}

pub const default_path = "saves/settings.json";
const max_bytes = 2048;

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
    const want = Settings{ .fullscreen = true, .scale = 4, .vsync = false, .volume = 0.8, .ambient = false, .pad_swap = true, .esdf = true, .keys = .{ .confirm = 57 } };
    try save(io, alloc, path, want);
    try std.testing.expectEqual(want, try load(io, alloc, path));
    try std.testing.expectEqual(@as(u8, 4), (Settings{ .scale = 99 }).sanitized().scale);
    try std.testing.expectEqual(@as(u32, 44), (Settings{ .keys = .{ .confirm = 41 } }).sanitized().keys.confirm);
}
