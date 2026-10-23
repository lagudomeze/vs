//! One-file save container: run JSON + gear JSON in a single atomic file.
//! This makes the two halves a single commit instead of two independent writes.
const std = @import("std");
const save_mod = @import("save.zig");
const gear_save = @import("gear_save.zig");
const items = @import("items.zig");
const sim_mod = @import("run_sim.zig");

pub const format_name = "vx-run-slot";
pub const version: u32 = 1;
pub const max_bytes: usize = 512 * 1024;

pub const Bundle = struct {
    format: []const u8,
    version: u32,
    run: []const u8,
    gear: []const u8,
};

pub const Decoded = struct {
    sim: sim_mod.Sim,
    gear: gear_save.GearSave,
};

pub fn encodeAlloc(
    alloc: std.mem.Allocator,
    sim: *const sim_mod.Sim,
    inv: *const items.Inventory,
    rng: ?*const std.Random.DefaultPrng,
) ![]u8 {
    const run = try save_mod.saveAlloc(alloc, sim);
    defer alloc.free(run);
    const gear = try gear_save.toAllocWithRng(alloc, inv, rng);
    defer alloc.free(gear);
    return std.json.Stringify.valueAlloc(alloc, Bundle{
        .format = format_name,
        .version = version,
        .run = run,
        .gear = gear,
    }, .{});
}

pub fn decodeAlloc(alloc: std.mem.Allocator, bytes: []const u8) !Decoded {
    if (bytes.len == 0) return error.EmptySlot;
    if (bytes.len > max_bytes) return error.SlotTooLarge;
    const parsed = try std.json.parseFromSlice(Bundle, alloc, bytes, .{ .ignore_unknown_fields = false });
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.format, format_name)) return error.NotSlotFormat;
    if (parsed.value.version != version) return error.UnsupportedSlotVersion;
    const sim = try save_mod.loadAlloc(alloc, parsed.value.run);
    const gear = try gear_save.fromSlice(alloc, parsed.value.gear);
    return .{ .sim = sim, .gear = gear };
}

pub fn saveFileAtomic(
    io: std.Io,
    alloc: std.mem.Allocator,
    path: []const u8,
    sim: *const sim_mod.Sim,
    inv: *const items.Inventory,
    rng: ?*const std.Random.DefaultPrng,
) !void {
    const bytes = try encodeAlloc(alloc, sim, inv, rng);
    defer alloc.free(bytes);
    var atomic = if (std.fs.path.isAbsolute(path))
        try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true })
    else
        try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writeStreamingAll(io, bytes);
    try atomic.replace(io);
}

pub fn loadFile(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !Decoded {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(max_bytes));
    defer alloc.free(bytes);
    return decodeAlloc(alloc, bytes);
}

test "slot bundle round-trips run and gear" {
    const alloc = std.testing.allocator;
    var sim = sim_mod.Sim.init(777, .mage);
    var inv = items.Inventory.init();
    _ = inv.pickup(2);
    const bytes = try encodeAlloc(alloc, &sim, &inv, null);
    defer alloc.free(bytes);
    const decoded = try decodeAlloc(alloc, bytes);
    try std.testing.expectEqual(sim.seed, decoded.sim.seed);
    try std.testing.expectEqual(@as(u8, 1), decoded.gear.len);
    try std.testing.expectEqual(@as(items.ItemId, 2), decoded.gear.items[0]);
}

test "slot bundle rejects a bare object" {
    try std.testing.expectError(error.MissingField, decodeAlloc(std.testing.allocator, "{}"));
}
