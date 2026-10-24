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

/// Single source of truth for the rebindable actions. Adding an action here
/// also updates sanitizing, conflict checks, assignment, the HUD list and the
/// remap cursor limit.
pub const BindingDef = struct {
    label: []const u8,
    default: u32,
    get: *const fn (*const Keys) u32,
    set: *const fn (*Keys, u32) void,
};

fn getConfirm(k: *const Keys) u32 {
    return k.confirm;
}
fn setConfirm(k: *Keys, v: u32) void {
    k.confirm = v;
}
fn getPotion(k: *const Keys) u32 {
    return k.potion;
}
fn setPotion(k: *Keys, v: u32) void {
    k.potion = v;
}
fn getBomb(k: *const Keys) u32 {
    return k.bomb;
}
fn setBomb(k: *Keys, v: u32) void {
    k.bomb = v;
}
fn getInventory(k: *const Keys) u32 {
    return k.inventory;
}
fn setInventory(k: *Keys, v: u32) void {
    k.inventory = v;
}
fn getCharacter(k: *const Keys) u32 {
    return k.character;
}
fn setCharacter(k: *Keys, v: u32) void {
    k.character = v;
}
fn getTalent1(k: *const Keys) u32 {
    return k.talent1;
}
fn setTalent1(k: *Keys, v: u32) void {
    k.talent1 = v;
}
fn getTalent2(k: *const Keys) u32 {
    return k.talent2;
}
fn setTalent2(k: *Keys, v: u32) void {
    k.talent2 = v;
}
fn getTalent3(k: *const Keys) u32 {
    return k.talent3;
}
fn setTalent3(k: *Keys, v: u32) void {
    k.talent3 = v;
}

pub const binding_defs = [_]BindingDef{
    .{ .label = "CONFIRM", .default = 44, .get = getConfirm, .set = setConfirm },
    .{ .label = "POTION", .default = 19, .get = getPotion, .set = setPotion },
    .{ .label = "BOMB", .default = 5, .get = getBomb, .set = setBomb },
    .{ .label = "INVENTORY", .default = 12, .get = getInventory, .set = setInventory },
    .{ .label = "CHARACTER", .default = 6, .get = getCharacter, .set = setCharacter },
    .{ .label = "TALENT 1", .default = 30, .get = getTalent1, .set = setTalent1 },
    .{ .label = "TALENT 2", .default = 31, .get = getTalent2, .set = setTalent2 },
    .{ .label = "TALENT 3", .default = 32, .get = getTalent3, .set = setTalent3 },
};

/// Fixed keys read by SDL outside Bindings. Rebinding onto these would make
/// one press do two unrelated things (#195), so they are rejected.
const reserved_keys = [_]u32{
    41, 42, 43, // Esc, Backspace, Tab
    4, 7, 8, 9, 11, 16, 20, 21, 22, 26, // A D E F H M Q R S W
    33, 34, 35, 36, 37, 38, 39, // 4..9, 0 (shop/wait/selection)
    55, // period
    58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, // F1..F12
    79, 80, 81, 82, // arrows
    89, 90, 91, 92, 93, 94, 95, 96, 97, // keypad 1..9
};

pub fn isReserved(code: u32) bool {
    for (reserved_keys) |r| {
        if (code == r) return true;
    }
    return false;
}

pub const Settings = struct {
    fullscreen: bool = false,
    scale: u8 = 3,
    vsync: bool = true,
    volume: f32 = 0.55,
    ambient: bool = true,
    pad_swap: bool = false,
    esdf: bool = false,
    keys: Keys = .{},
    chunks: bool = false,

    pub fn sanitized(self: Settings) Settings {
        var s = self;
        s.scale = @min(@max(s.scale, 2), 4);
        s.volume = std.math.clamp(s.volume, 0, 1);
        for (binding_defs) |def| {
            var v = keyCode(def.get(&s.keys), def.default);
            if (isReserved(v)) v = def.default;
            def.set(&s.keys, v);
        }
        // Hand-edited/Steam-Cloud files must not keep two actions on one key.
        // Reset a duplicate to a default that an earlier action does not use.
        var guard: usize = 0;
        while (guard < binding_defs.len) : (guard += 1) {
            var changed = false;
            for (binding_defs, 0..) |a, i| {
                const v = a.get(&s.keys);
                if (!usedBefore(&s.keys, i, v)) continue;
                var candidate = a.default;
                if (usedBefore(&s.keys, i, candidate)) {
                    for (binding_defs) |other| {
                        if (!usedBefore(&s.keys, i, other.default)) {
                            candidate = other.default;
                            break;
                        }
                    }
                }
                a.set(&s.keys, candidate);
                changed = true;
            }
            if (!changed) break;
        }
        return s;
    }
};

fn usedBefore(keys: *const Keys, index: usize, code: u32) bool {
    var i: usize = 0;
    while (i < index) : (i += 1) {
        if (binding_defs[i].get(keys) == code) return true;
    }
    return false;
}

pub fn keyConflicts(keys: Keys, index: u8, code: u32) bool {
    if (index >= binding_defs.len or isReserved(code)) return true;
    for (binding_defs, 0..) |def, i| {
        if (i != index and def.get(&keys) == code) return true;
    }
    return false;
}

pub fn assignKey(keys: *Keys, index: u8, code: u32) bool {
    if (index >= binding_defs.len) return false;
    binding_defs[index].set(keys, code);
    return true;
}

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

test "settings: key assignment and conflict" {
    var keys = Keys{};
    try std.testing.expect(keyConflicts(keys, 0, 19));
    try std.testing.expect(!keyConflicts(keys, 0, 44));
    try std.testing.expect(assignKey(&keys, 0, 57));
    try std.testing.expectEqual(@as(u32, 57), keys.confirm);
    try std.testing.expect(keyConflicts(keys, 1, 57));
    try std.testing.expect(assignKey(&keys, 0, 44));
    for ([_]u32{ 21, 16, 64, 26 }) |code| {
        try std.testing.expect(keyConflicts(keys, 0, code));
    }
    try std.testing.expect(!assignKey(&keys, 8, 44));
    const deduped = (Settings{ .keys = .{ .potion = 44 } }).sanitized();
    try std.testing.expectEqual(@as(u32, 19), deduped.keys.potion);
    try std.testing.expectEqual(@as(u32, 44), deduped.keys.confirm);
    const reserved = (Settings{ .keys = .{ .confirm = 21 } }).sanitized();
    try std.testing.expectEqual(@as(u32, 44), reserved.keys.confirm);
    const both = (Settings{ .keys = .{ .confirm = 19, .potion = 19 } }).sanitized();
    try std.testing.expect(both.keys.potion != both.keys.confirm);
}

test "settings round-trip, defaults and clamp" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    try std.testing.expectEqual(Settings{}, try load(io, alloc, "saves/definitely-missing-settings.json"));

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "settings.json" });
    defer alloc.free(path);
    const want = Settings{ .fullscreen = true, .scale = 4, .vsync = false, .volume = 0.8, .ambient = false, .pad_swap = true, .esdf = true, .keys = .{ .confirm = 57 }, .chunks = true };
    try save(io, alloc, path, want);
    try std.testing.expectEqual(want, try load(io, alloc, path));
    try std.testing.expectEqual(@as(u8, 4), (Settings{ .scale = 99 }).sanitized().scale);
    try std.testing.expectEqual(@as(u32, 44), (Settings{ .keys = .{ .confirm = 41 } }).sanitized().keys.confirm);
}
