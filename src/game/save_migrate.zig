//! Best-effort migration of legacy install-directory saves into the user
//! directory. Never overwrites a newer file.
const std = @import("std");

pub fn migrateAll(io: std.Io, src: std.Io.Dir, dst: std.Io.Dir) !usize {
    var it = src.iterate();
    var copied: usize = 0;
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (dst.access(io, entry.name, .{})) |_| {
            continue;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => continue,
        }
        src.copyFile(entry.name, dst, entry.name, io, .{ .replace = false }) catch continue;
        copied += 1;
    }
    return copied;
}

test "save migration copies missing files and keeps newer ones" {
    const io = std.testing.io;
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "old");
    try tmp.dir.createDirPath(io, "new");
    var old = try tmp.dir.openDir(io, "old", .{ .iterate = true });
    defer old.close(io);
    var new = try tmp.dir.openDir(io, "new", .{});
    defer new.close(io);

    var f = try old.createFile(io, "slot1.save", .{});
    try f.writeStreamingAll(io, "old-save");
    f.close(io);
    f = try old.createFile(io, "records.json", .{});
    try f.writeStreamingAll(io, "{\"wins\":1}");
    f.close(io);

    f = try new.createFile(io, "records.json", .{});
    try f.writeStreamingAll(io, "{\"wins\":9}");
    f.close(io);

    try std.testing.expectEqual(@as(usize, 1), try migrateAll(io, old, new));

    const slot = try new.readFileAlloc(io, "slot1.save", alloc, .limited(64));
    defer alloc.free(slot);
    try std.testing.expectEqualStrings("old-save", slot);
    const rec = try new.readFileAlloc(io, "records.json", alloc, .limited(64));
    defer alloc.free(rec);
    try std.testing.expectEqualStrings("{\"wins\":9}", rec);
}
