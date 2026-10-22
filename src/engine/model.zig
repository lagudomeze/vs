//! Loader for the compact baked .vxm model format.
const std = @import("std");
const math = @import("../core/math.zig");

pub const max_joints = 24;
pub const max_tris = 20000;

pub const Joint = struct {
    name: []const u8,
    parent: i32,
    rest: math.Vec3,
};

pub const TriColor = struct {
    r: u8,
    g: u8,
    b: u8,
    emissive: u8,
};

pub const Part = struct {
    joint: u16,
    verts: []math.Vec3,
    indices: []u32,
    colors: []TriColor,
};

pub const Model = struct {
    name: []const u8,
    flags: u32,
    joints: []Joint,
    parts: []Part,
    bounds_min: math.Vec3,
    bounds_max: math.Vec3,
    rest_world: []math.Mat4,

    root: ?u16 = null,
    hips: ?u16 = null,
    torso: ?u16 = null,
    head: ?u16 = null,
    arm_l: ?u16 = null,
    arm_r: ?u16 = null,
    leg_l: ?u16 = null,
    leg_r: ?u16 = null,
    cape: ?u16 = null,
    weapon: ?u16 = null,
    offhand: ?u16 = null,
    focus: ?u16 = null,
    aura: ?u16 = null,

    pub fn isAdditive(self: *const Model) bool {
        return (self.flags & 1) != 0;
    }

    pub fn jointIndex(self: *const Model, name: []const u8) ?u16 {
        for (self.joints, 0..) |j, i| {
            if (std.mem.eql(u8, j.name, name)) return @intCast(i);
        }
        return null;
    }
};

const Reader = struct {
    bytes: []const u8,
    pos: usize = 0,

    fn need(self: *Reader, n: usize) !void {
        if (self.pos + n > self.bytes.len) return error.TruncatedModel;
    }
    fn u8v(self: *Reader) !u8 {
        try self.need(1);
        const v = self.bytes[self.pos];
        self.pos += 1;
        return v;
    }
    fn u16v(self: *Reader) !u16 {
        try self.need(2);
        const v = std.mem.readInt(u16, self.bytes[self.pos..][0..2], .little);
        self.pos += 2;
        return v;
    }
    fn u32v(self: *Reader) !u32 {
        try self.need(4);
        const v = std.mem.readInt(u32, self.bytes[self.pos..][0..4], .little);
        self.pos += 4;
        return v;
    }
    fn i32v(self: *Reader) !i32 {
        try self.need(4);
        const v = std.mem.readInt(i32, self.bytes[self.pos..][0..4], .little);
        self.pos += 4;
        return v;
    }
    fn f32v(self: *Reader) !f32 {
        try self.need(4);
        const v = std.mem.bytesToValue(f32, self.bytes[self.pos..][0..4]);
        self.pos += 4;
        return v;
    }
    fn str(self: *Reader) ![]const u8 {
        const n = try self.u8v();
        try self.need(n);
        const s = self.bytes[self.pos .. self.pos + n];
        self.pos += n;
        return s;
    }
    fn vec3(self: *Reader) !math.Vec3 {
        const x = try self.f32v();
        const y = try self.f32v();
        const z = try self.f32v();
        return .{ .x = x, .y = y, .z = z };
    }
};

pub fn load(allocator: std.mem.Allocator, bytes: []const u8) !Model {
    var r = Reader{ .bytes = bytes };
    try r.need(4);
    if (!std.mem.eql(u8, bytes[0..4], "VXM1")) return error.BadMagic;
    r.pos = 4;
    const version = try r.u32v();
    if (version != 1) return error.BadVersion;
    const flags = try r.u32v();
    const name = try r.str();
    const bounds_min = try r.vec3();
    const bounds_max = try r.vec3();

    const joint_count = try r.u16v();
    if (joint_count > max_joints) return error.TooManyJoints;
    const joints = try allocator.alloc(Joint, joint_count);
    for (joints) |*j| {
        const jname = try r.str();
        const parent = try r.i32v();
        const rest = try r.vec3();
        j.* = .{ .name = jname, .parent = parent, .rest = rest };
    }

    const part_count = try r.u16v();
    const parts = try allocator.alloc(Part, part_count);
    for (parts) |*part| {
        const joint = try r.u16v();
        const vertex_count = try r.u32v();
        const tri_count = try r.u32v();
        if (vertex_count > 200000 or tri_count > max_tris) return error.ModelTooLarge;
        if (joint >= joint_count) return error.BadJoint;
        const verts = try allocator.alloc(math.Vec3, vertex_count);
        for (verts) |*v| v.* = try r.vec3();

        const indices = try allocator.alloc(u32, tri_count * 3);
        for (indices) |*idx| {
            const value = try r.u32v();
            if (value >= vertex_count) return error.BadIndex;
            idx.* = value;
        }

        const colors = try allocator.alloc(TriColor, tri_count);
        for (colors) |*c| {
            c.r = try r.u8v();
            c.g = try r.u8v();
            c.b = try r.u8v();
            c.emissive = try r.u8v();
        }

        part.* = .{
            .joint = joint,
            .verts = verts,
            .indices = indices,
            .colors = colors,
        };
    }
    const rest_world = try allocator.alloc(math.Mat4, joint_count);
    for (rest_world, 0..) |*m, i| {
        const local = math.Mat4.translation(joints[i].rest);
        if (joints[i].parent >= 0) {
            const p: usize = @intCast(joints[i].parent);
            if (p >= i) return error.BadHierarchy;
            m.* = rest_world[p].mul(local);
        } else {
            m.* = local;
        }
    }

    var model = Model{
        .name = name,
        .flags = flags,
        .joints = joints,
        .parts = parts,
        .bounds_min = bounds_min,
        .bounds_max = bounds_max,
        .rest_world = rest_world,
    };
    model.root = model.jointIndex("root");
    model.hips = model.jointIndex("hips");
    model.torso = model.jointIndex("torso");
    model.head = model.jointIndex("head");
    model.arm_l = model.jointIndex("arm_l");
    model.arm_r = model.jointIndex("arm_r");
    model.leg_l = model.jointIndex("leg_l");
    model.leg_r = model.jointIndex("leg_r");
    model.cape = model.jointIndex("cape");
    model.weapon = model.jointIndex("weapon");
    model.offhand = model.jointIndex("offhand");
    model.focus = model.jointIndex("focus");
    model.aura = model.jointIndex("aura");
    return model;
}

pub const ModelDb = struct {
    models: []Model,
    names: []const []const u8,

    pub fn init(allocator: std.mem.Allocator, entries: anytype) !ModelDb {
        const models = try allocator.alloc(Model, entries.len);
        const names = try allocator.alloc([]const u8, entries.len);
        for (entries, 0..) |entry, i| {
            models[i] = try load(allocator, entry.bytes);
            names[i] = entry.name;
        }
        return .{ .models = models, .names = names };
    }

    pub fn find(self: *const ModelDb, name: []const u8) ?*const Model {
        for (self.names, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return &self.models[i];
        }
        return null;
    }

    pub fn indexOf(self: *const ModelDb, name: []const u8) ?u16 {
        for (self.names, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast(i);
        }
        return null;
    }

    pub fn at(self: *const ModelDb, index: u16) *const Model {
        return &self.models[index];
    }
};
