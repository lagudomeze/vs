//! Pocket-sized save for the parts of a run that live outside TomeSim:
//! bag contents and equipped slots. TomeGame writes this next to save.zig's
//! Sim snapshot so a loaded run keeps its loot as well as its combat state.
const std = @import("std");
const items = @import("items.zig");

pub const format_name = "vx-tome-gear";
pub const gear_version: u8 = 1;
pub const max_bytes: usize = 16 * 1024;

pub const GearSave = struct {
    format: []const u8 = format_name,
    version: u8 = gear_version,
    len: u8 = 0,
    items: [items.max_inventory]items.ItemId = @splat(0),
    equipped: [items.slot_count]?items.ItemId = @splat(null),
};

pub const GearError = error{
    Empty,
    TooLarge,
    NotGearFormat,
    UnsupportedVersion,
    InvalidLength,
    TrailingData,
};

pub fn capture(inv: *const items.Inventory) GearSave {
    var save = GearSave{};
    save.len = @intCast(inv.len);
    for (inv.items, 0..) |id, i| save.items[i] = id;
    for (inv.equipped.slots, 0..) |maybe, i| save.equipped[i] = maybe;
    return save;
}

pub fn restore(save: *const GearSave, inv: *items.Inventory) GearError!void {
    if (save.len > items.max_inventory) return error.InvalidLength;
    inv.* = items.Inventory.init();
    inv.len = save.len;
    for (save.items, 0..) |id, i| inv.items[i] = id;
    for (save.equipped, 0..) |maybe, i| inv.equipped.slots[i] = maybe;
}

pub fn toAlloc(alloc: std.mem.Allocator, inv: *const items.Inventory) ![]u8 {
    const save = capture(inv);
    return std.json.Stringify.valueAlloc(alloc, save, .{});
}

pub fn fromSlice(alloc: std.mem.Allocator, bytes: []const u8) (GearError || std.json.ParseError(std.json.Scanner))!GearSave {
    if (bytes.len == 0) return error.Empty;
    if (bytes.len > max_bytes) return error.TooLarge;
    const parsed = try std.json.parseFromSlice(GearSave, alloc, bytes, .{ .ignore_unknown_fields = false });
    defer parsed.deinit();
    const save = parsed.value;
    if (!std.mem.eql(u8, save.format, format_name)) return error.NotGearFormat;
    if (save.version != gear_version) return error.UnsupportedVersion;
    if (save.len > items.max_inventory) return error.InvalidLength;
    var owned = save;
    owned.format = format_name; // the parsed slice points into the input buffer
    return owned;
}

/// Write the gear half of a run save. Parent directories must exist.
pub fn saveFile(io: std.Io, alloc: std.mem.Allocator, path: []const u8, inv: *const items.Inventory) !void {
    const bytes = try toAlloc(alloc, inv);
    defer alloc.free(bytes);
    const file = if (std.fs.path.isAbsolute(path))
        try std.Io.Dir.createFileAbsolute(io, path, .{})
    else
        try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}

/// Read and validate the gear half. Bad files are left untouched on disk.
pub fn loadFile(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !GearSave {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(max_bytes));
    defer alloc.free(bytes);
    return fromSlice(alloc, bytes);
}

test "gear save: capture/restore keeps bag and equipment" {
    var inv = items.Inventory.init();
    _ = inv.pickup(1);
    _ = inv.pickup(2);
    try inv.equip(&test_defs, 1);
    var copy = GearSave{};
    copy = capture(&inv);
    var out = items.Inventory.init();
    try restore(&copy, &out);
    try std.testing.expectEqual(inv.len, out.len);
    try std.testing.expectEqualSlices(items.ItemId, &inv.items, &out.items);
    try std.testing.expectEqualDeep(inv.equipped, out.equipped);
}

test "gear save: JSON roundtrip and bad inputs" {
    var inv = items.Inventory.init();
    _ = inv.pickup(2);
    const bytes = try toAlloc(std.testing.allocator, &inv);
    defer std.testing.allocator.free(bytes);
    const save = try fromSlice(std.testing.allocator, bytes);
    try std.testing.expectEqual(@as(u8, 1), save.len);
    try std.testing.expectEqual(@as(items.ItemId, 2), save.items[0]);

    try std.testing.expectError(error.Empty, fromSlice(std.testing.allocator, ""));
    try std.testing.expectError(error.NotGearFormat, fromSlice(std.testing.allocator, "{\"format\":\"x\",\"version\":1}"));
    try std.testing.expectError(error.UnsupportedVersion, fromSlice(std.testing.allocator, "{\"format\":\"vx-tome-gear\",\"version\":9}"));
}

const test_defs = [_]items.ItemDef{
    .{ .id = "test_sword", .name = "测试剑", .slot = .main_hand, .quality = .common, .description = "" },
    .{ .id = "test_body", .name = "测试甲", .slot = .body, .quality = .common, .description = "" },
    .{ .id = "test_trinket", .name = "测试饰品", .slot = .trinket, .quality = .common, .description = "" },
};
