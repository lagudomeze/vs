//! Headless 13x13 dungeon grid: tiles, deterministic generation, occupancy,
//! line of sight and A* pathfinding.
//!
//! The module only depends on std. The renderer, ECS and turn system are
//! expected to consume these plain values, which keeps layout logic testable
//! with 'zig build test' and free of SDL/GPU requirements.
//!
//! Coordinates
//! -----------
//! * x grows east, y grows south (towards +Z in world space).
//! * the board is 13x13; cell (6, 6) is the board origin.
//! * a cell centre maps to ((x - 6) * 1.0, (y - 6) * 1.0) on the world
//!   (X, Z) plane, matching engine/arena_mesh.zig (tile_half = 6,
//!   tile_size = 1.0).
//!
//! Tile conventions
//! ----------------
//! * wall and obstacle block movement and line of sight.
//! * floor, stairs, chest and trap are walkable. Chests and traps are
//!   interactable floor features; they do not block an actor.
//! * the outer ring of the board is always wall; the entrance is the
//!   interior cell next to the bottom (or side) wall.
const std = @import("std");

/// Board width/height in cells.
pub const size: usize = 13;
pub const width: usize = size;
pub const height: usize = size;
pub const cell_count: usize = size * size;

const span: i32 = @intCast(size);
const interior_min: i32 = 1;
const interior_max: i32 = span - 2;

/// World distance between cell centres. Mirrors arena_mesh.tile_size.
pub const tile_size: f32 = 1.0;
/// World-space offset of cell (0, 0). Mirrors arena_mesh.tile_half.
pub const world_center: f32 = 6.0;

pub const min_chests: usize = 2;
pub const max_chests: usize = 4;
pub const min_spawns: usize = 4;
pub const max_spawns: usize = 8;
pub const max_traps: usize = 4;

/// Minimum Manhattan distance kept between entrance and stairs.
pub const min_entrance_stairs_distance: u32 = 8;

/// A cell on the 13x13 board. Out-of-board coordinates are representable and
/// are treated as solid by every Dungeon query.
pub const GridPos = struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn init(x: i32, y: i32) GridPos {
        return .{ .x = x, .y = y };
    }

    pub fn eql(self: GridPos, other: GridPos) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn inBounds(self: GridPos) bool {
        return self.x >= 0 and self.y >= 0 and self.x < span and self.y < span;
    }

    /// Row-major index: y * 13 + x.
    pub fn index(self: GridPos) usize {
        return @as(usize, @intCast(self.y)) * size + @as(usize, @intCast(self.x));
    }

    pub fn fromIndex(i: usize) GridPos {
        return .{ .x = @intCast(i % size), .y = @intCast(i / size) };
    }

    pub fn manhattan(a: GridPos, b: GridPos) u32 {
        const dx = if (a.x > b.x) a.x - b.x else b.x - a.x;
        const dy = if (a.y > b.y) a.y - b.y else b.y - a.y;
        return @intCast(dx + dy);
    }

    pub fn chebyshev(a: GridPos, b: GridPos) u32 {
        const dx = if (a.x > b.x) a.x - b.x else b.x - a.x;
        const dy = if (a.y > b.y) a.y - b.y else b.y - a.y;
        return @intCast(@max(dx, dy));
    }

    /// Convert a cell to the world-space centre used by renderer/ECS actors.
    pub fn toWorld(self: GridPos) WorldPos {
        return .{
            .x = (@as(f32, @floatFromInt(self.x)) - world_center) * tile_size,
            .z = (@as(f32, @floatFromInt(self.y)) - world_center) * tile_size,
        };
    }

    /// Nearest cell for a world-space position, or null when outside the board.
    pub fn fromWorld(wx: f32, wz: f32) ?GridPos {
        const fx = wx / tile_size + world_center;
        const fz = wz / tile_size + world_center;
        const limit = @as(f32, @floatFromInt(size)) - 0.5;
        if (!(fx >= -0.5 and fx < limit and fz >= -0.5 and fz < limit)) return null;
        const p = GridPos{
            .x = @intFromFloat(@floor(fx + 0.5)),
            .y = @intFromFloat(@floor(fz + 0.5)),
        };
        if (!p.inBounds()) return null;
        return p;
    }
};

pub const WorldPos = struct {
    x: f32 = 0,
    z: f32 = 0,

    pub fn toGrid(self: WorldPos) ?GridPos {
        return GridPos.fromWorld(self.x, self.z);
    }
};

/// Terrain of one cell.
///
/// wall and obstacle block; floor, stairs, chest and trap are walkable.
/// obstacle covers pillars, rubble, water and braziers; the visual flavour
/// lives in Prop.
pub const Tile = enum(u8) {
    floor,
    wall,
    stairs,
    chest,
    trap,
    obstacle,

    pub fn isWalkable(self: Tile) bool {
        return switch (self) {
            .wall, .obstacle => false,
            .floor, .stairs, .chest, .trap => true,
        };
    }

    /// Single-character map glyph used by Dungeon.renderAscii and debug HUDs.
    pub fn ascii(self: Tile) u8 {
        return switch (self) {
            .floor => '.',
            .wall => '#',
            .stairs => '<',
            .chest => 'C',
            .trap => '^',
            .obstacle => 'X',
        };
    }
};

pub fn walkable(tile: Tile) bool {
    return tile.isWalkable();
}

/// Visual flavour for Tile.obstacle cells. none means "not an obstacle".
pub const Prop = enum(u8) {
    none,
    column,
    rubble,
    water,
    brazier,

    pub fn blocksMovement(self: Prop) bool {
        return self != .none;
    }

    /// Asset name under assets/baked/<name>.vxm, or null when the renderer
    /// should draw the feature itself (currently only water).
    pub fn modelName(self: Prop) ?[]const u8 {
        return switch (self) {
            .none, .water => null,
            .column => "column",
            .rubble => "rocks",
            .brazier => "brazier",
        };
    }
};

const CellSet = std.StaticBitSet(cell_count);

/// Occupancy bitmap supplied by the caller (player + enemies + summons).
/// Terrain blocking is handled by Dungeon; this layer is only dynamic actors.
pub const Occupancy = struct {
    bits: CellSet = CellSet.empty,

    pub fn clearAll(self: *Occupancy) void {
        self.bits = CellSet.empty;
    }

    pub fn set(self: *Occupancy, p: GridPos) void {
        if (p.inBounds()) self.bits.set(p.index());
    }

    pub fn unset(self: *Occupancy, p: GridPos) void {
        if (p.inBounds()) self.bits.unset(p.index());
    }

    pub fn isSet(self: *const Occupancy, p: GridPos) bool {
        return p.inBounds() and self.bits.isSet(p.index());
    }

    pub fn count(self: *const Occupancy) usize {
        return self.bits.count();
    }

    /// Convenience for rebuilding the bitmap from actor positions.
    pub fn rebuild(self: *Occupancy, positions: []const GridPos) void {
        self.clearAll();
        for (positions) |p| self.set(p);
    }
};

/// Duck-typed pathfinding context: anything with isBlocked(GridPos) bool
/// works with astar / lineOfSight.
pub const BlockCtx = struct {
    dungeon: *const Dungeon,
    occupancy: ?*const Occupancy = null,

    pub fn isBlocked(self: BlockCtx, p: GridPos) bool {
        return self.dungeon.isBlocked(p, self.occupancy);
    }
};

pub const max_path: usize = cell_count;

/// Fixed-size path result. Cell centres are listed from start to goal.
pub const Path = struct {
    cells: [max_path]GridPos = @splat(.{}),
    len: usize = 0,

    pub fn slice(self: *const Path) []const GridPos {
        return self.cells[0..self.len];
    }

    pub fn first(self: *const Path) ?GridPos {
        if (self.len == 0) return null;
        return self.cells[0];
    }

    pub fn last(self: *const Path) ?GridPos {
        if (self.len == 0) return null;
        return self.cells[self.len - 1];
    }
};

/// One generated floor.
pub const Dungeon = struct {
    seed: u64 = 0,
    floor: u8 = 1,

    tiles: [size][size]Tile = undefined,
    props: [size][size]Prop = undefined,

    entrance: GridPos = .{},
    stairs: GridPos = .{},

    chests: [max_chests]GridPos = @splat(.{}),
    chest_count: u8 = 0,
    enemy_spawns: [max_spawns]GridPos = @splat(.{}),
    spawn_count: u8 = 0,
    traps: [max_traps]GridPos = @splat(.{}),
    trap_count: u8 = 0,

    // ------------------------------------------------------------- queries

    pub fn tileAt(self: *const Dungeon, p: GridPos) Tile {
        if (!p.inBounds()) return .wall;
        return self.tiles[@intCast(p.y)][@intCast(p.x)];
    }

    pub fn setTile(self: *Dungeon, p: GridPos, tile: Tile) void {
        if (!p.inBounds()) return;
        self.tiles[@intCast(p.y)][@intCast(p.x)] = tile;
    }

    pub fn propAt(self: *const Dungeon, p: GridPos) Prop {
        if (!p.inBounds()) return .none;
        return self.props[@intCast(p.y)][@intCast(p.x)];
    }

    pub fn setProp(self: *Dungeon, p: GridPos, prop: Prop) void {
        if (!p.inBounds()) return;
        self.props[@intCast(p.y)][@intCast(p.x)] = prop;
    }

    /// Terrain-only walkability; out-of-bounds is solid.
    pub fn isWalkable(self: *const Dungeon, p: GridPos) bool {
        return self.tileAt(p).isWalkable();
    }

    /// Terrain + optional dynamic occupancy. This is the predicate to use for
    /// movement and pathfinding.
    pub fn isBlocked(self: *const Dungeon, p: GridPos, occupancy: ?*const Occupancy) bool {
        if (!p.inBounds()) return true;
        if (!self.isWalkable(p)) return true;
        if (occupancy) |occ| {
            if (occ.isSet(p)) return true;
        }
        return false;
    }

    pub fn blockCtx(self: *const Dungeon, occupancy: ?*const Occupancy) BlockCtx {
        return .{ .dungeon = self, .occupancy = occupancy };
    }

    pub fn astarTo(self: *const Dungeon, start: GridPos, goal: GridPos, occupancy: ?*const Occupancy) ?Path {
        return astar(start, goal, self.blockCtx(occupancy));
    }

    /// Like astarTo, but the goal cell may be occupied by an actor (for
    /// example the player). Terrain at the goal must still be walkable.
    pub fn astarToOccupiedGoal(self: *const Dungeon, start: GridPos, goal: GridPos, occupancy: ?*const Occupancy) ?Path {
        const Ctx = struct {
            dungeon: *const Dungeon,
            occupancy: ?*const Occupancy,
            goal: GridPos,

            pub fn isBlocked(ctx: @This(), p: GridPos) bool {
                if (p.eql(ctx.goal)) return !ctx.dungeon.isWalkable(p);
                return ctx.dungeon.isBlocked(p, ctx.occupancy);
            }
        };
        return astar(start, goal, Ctx{ .dungeon = self, .occupancy = occupancy, .goal = goal });
    }

    pub fn lineOfSightTo(self: *const Dungeon, from: GridPos, to: GridPos, occupancy: ?*const Occupancy) bool {
        return lineOfSight(from, to, self.blockCtx(occupancy));
    }

    pub fn chestSlice(self: *const Dungeon) []const GridPos {
        return self.chests[0..@as(usize, self.chest_count)];
    }

    pub fn spawnSlice(self: *const Dungeon) []const GridPos {
        return self.enemy_spawns[0..@as(usize, self.spawn_count)];
    }

    pub fn trapSlice(self: *const Dungeon) []const GridPos {
        return self.traps[0..@as(usize, self.trap_count)];
    }

    pub fn countTile(self: *const Dungeon, tile: Tile) usize {
        var n: usize = 0;
        var y: usize = 0;
        while (y < size) : (y += 1) {
            var x: usize = 0;
            while (x < size) : (x += 1) {
                if (self.tiles[y][x] == tile) n += 1;
            }
        }
        return n;
    }

    /// Debug/QA map dump. Each row is 13 glyphs + '\n' (182 bytes total).
    pub fn renderAscii(self: *const Dungeon, buf: []u8) []const u8 {
        const needed = cell_count + size;
        if (buf.len < needed) return buf[0..0];
        var n: usize = 0;
        var y: usize = 0;
        while (y < size) : (y += 1) {
            var x: usize = 0;
            while (x < size) : (x += 1) {
                buf[n] = self.glyphAt(.{ .x = @intCast(x), .y = @intCast(y) });
                n += 1;
            }
            buf[n] = '\n';
            n += 1;
        }
        return buf[0..n];
    }

    pub fn glyphAt(self: *const Dungeon, p: GridPos) u8 {
        if (!p.inBounds()) return '#';
        if (self.entrance.eql(p)) return '>';
        const tile = self.tileAt(p);
        if (tile == .floor) {
            for (self.spawnSlice()) |spawn| {
                if (spawn.eql(p)) return 'e';
            }
        }
        if (tile == .obstacle) {
            return switch (self.propAt(p)) {
                .column => 'I',
                .rubble => ',',
                .water => '~',
                .brazier => '*',
                .none => 'X',
            };
        }
        return tile.ascii();
    }

    // ---------------------------------------------------------- generation

    /// Create a dungeon where every cell is tile (used by tests and tools).
    pub fn filled(tile: Tile) Dungeon {
        var d = Dungeon{};
        var y: usize = 0;
        while (y < size) : (y += 1) {
            var x: usize = 0;
            while (x < size) : (x += 1) {
                d.tiles[y][x] = tile;
                d.props[y][x] = .none;
            }
        }
        return d;
    }

    /// Deterministic ToME-style floor: bordered room complex, guaranteed
    /// entrance -> stairs route, floor-scaled chests / spawns / traps.
    pub fn generate(seed: u64, floor_in: u8) Dungeon {
        const floor = @max(1, floor_in);
        var d = Dungeon.filled(.wall);
        d.seed = seed;
        d.floor = floor;

        var prng = std.Random.DefaultPrng.init(mixSeed(seed, floor));
        var builder = Builder{ .d = &d, .rng = prng.random() };

        const side = builder.chooseSide();
        builder.placeEntranceAndStairs(side);
        const bend = builder.carveSpine();
        builder.addEdgeRoom(entranceEdge(side), d.entrance);
        builder.addEdgeRoom(stairsEdge(side), d.stairs);
        builder.addMidRoom(bend);
        builder.addCenterRoom(bend);
        builder.addVault(bend);

        builder.decorate();
        builder.computeDistances();
        builder.placeTraps();
        builder.placeChests();
        builder.placeSpawns();

        return d;
    }

    // ---------------------------------------------------------- validation

    pub const ValidateError = error{
        BorderOpen,
        InvalidEntrance,
        InvalidStairs,
        EntranceTooClose,
        BadChestCount,
        BadSpawnCount,
        BadTrapCount,
        MarkerOutOfBounds,
        MarkerTerrain,
        MarkerOverlap,
        DuplicateChest,
        DuplicateSpawn,
        DuplicateTrap,
        UnreachableStairs,
        UnreachableMarker,
        UnreachableFloor,
    };

    /// Check all invariants relied upon by the turn system: closed border,
    /// walkable entrance/stairs, distant stairs, floor-scaled marker counts,
    /// unique/non-overlapping markers, and a fully connected walkable map
    /// (every walkable cell reachable from the entrance).
    pub fn validate(self: *const Dungeon) ValidateError!void {
        var i: usize = 0;
        while (i < size) : (i += 1) {
            const k: i32 = @intCast(i);
            if (self.tileAt(.{ .x = k, .y = 0 }) != .wall) return error.BorderOpen;
            if (self.tileAt(.{ .x = k, .y = span - 1 }) != .wall) return error.BorderOpen;
            if (self.tileAt(.{ .x = 0, .y = k }) != .wall) return error.BorderOpen;
            if (self.tileAt(.{ .x = span - 1, .y = k }) != .wall) return error.BorderOpen;
        }

        if (!isInterior(self.entrance)) return error.InvalidEntrance;
        if (self.tileAt(self.entrance) != .floor) return error.InvalidEntrance;
        if (!isInterior(self.stairs)) return error.InvalidStairs;
        if (self.tileAt(self.stairs) != .stairs) return error.InvalidStairs;
        if (self.entrance.manhattan(self.stairs) < min_entrance_stairs_distance) return error.EntranceTooClose;

        const chest_count: usize = self.chest_count;
        const spawn_count: usize = self.spawn_count;
        const trap_count: usize = self.trap_count;
        if (chest_count < min_chests or chest_count > max_chests) return error.BadChestCount;
        if (spawn_count < min_spawns or spawn_count > max_spawns) return error.BadSpawnCount;
        if (trap_count > max_traps) return error.BadTrapCount;

        const chests = self.chestSlice();
        const spawns = self.spawnSlice();
        const traps = self.trapSlice();

        for (chests, 0..) |p, idx| {
            if (!isInterior(p)) return error.MarkerOutOfBounds;
            if (self.tileAt(p) != .chest) return error.MarkerTerrain;
            if (p.eql(self.entrance) or p.eql(self.stairs)) return error.MarkerOverlap;
            for (chests[0..idx]) |q| {
                if (p.eql(q)) return error.DuplicateChest;
            }
            for (spawns) |q| {
                if (p.eql(q)) return error.MarkerOverlap;
            }
            for (traps) |q| {
                if (p.eql(q)) return error.MarkerOverlap;
            }
        }

        for (spawns, 0..) |p, idx| {
            if (!isInterior(p)) return error.MarkerOutOfBounds;
            if (self.tileAt(p) != .floor) return error.MarkerTerrain;
            if (p.eql(self.entrance) or p.eql(self.stairs)) return error.MarkerOverlap;
            for (spawns[0..idx]) |q| {
                if (p.eql(q)) return error.DuplicateSpawn;
            }
            for (traps) |q| {
                if (p.eql(q)) return error.MarkerOverlap;
            }
        }

        for (traps, 0..) |p, idx| {
            if (!isInterior(p)) return error.MarkerOutOfBounds;
            if (self.tileAt(p) != .trap) return error.MarkerTerrain;
            if (p.eql(self.entrance) or p.eql(self.stairs)) return error.MarkerOverlap;
            for (traps[0..idx]) |q| {
                if (p.eql(q)) return error.DuplicateTrap;
            }
        }

        const reach = floodFill(self, null);
        if (!reach.mask.isSet(self.stairs.index())) return error.UnreachableStairs;
        for (chests) |p| {
            if (!reach.mask.isSet(p.index())) return error.UnreachableMarker;
        }
        for (spawns) |p| {
            if (!reach.mask.isSet(p.index())) return error.UnreachableMarker;
        }
        for (traps) |p| {
            if (!reach.mask.isSet(p.index())) return error.UnreachableMarker;
        }

        var y: usize = 0;
        while (y < size) : (y += 1) {
            var x: usize = 0;
            while (x < size) : (x += 1) {
                const p = GridPos{ .x = @intCast(x), .y = @intCast(y) };
                if (self.tileAt(p).isWalkable() and !reach.mask.isSet(p.index())) {
                    return error.UnreachableFloor;
                }
            }
        }
    }
};

// ---------------------------------------------------------------- helpers

pub fn isInterior(p: GridPos) bool {
    return p.x >= interior_min and p.y >= interior_min and p.x <= interior_max and p.y <= interior_max;
}

/// Floor-scaled content budgets. Floors above 3 saturate at the v1 limits.
pub fn chestsForFloor(floor: u8) usize {
    const f: usize = @max(1, @as(usize, floor));
    return @min(max_chests, min_chests + (f - 1));
}

pub fn spawnsForFloor(floor: u8) usize {
    const f: usize = @max(1, @as(usize, floor));
    return @min(max_spawns, min_spawns + 2 * (f - 1));
}

pub fn trapsForFloor(floor: u8) usize {
    const f: usize = @max(1, @as(usize, floor));
    return @min(max_traps, f);
}

fn mixSeed(seed: u64, floor: u8) u64 {
    var z = seed +% (@as(u64, floor) *% 0x9e3779b97f4a7c15);
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

fn shuffle(rng: std.Random, items: []GridPos) void {
    var i: usize = items.len;
    while (i > 1) {
        i -= 1;
        const j = rng.uintLessThan(usize, i + 1);
        const tmp = items[i];
        items[i] = items[j];
        items[j] = tmp;
    }
}

fn farEnough(p: GridPos, others: []const GridPos, min_distance: u32) bool {
    for (others) |q| {
        if (p.manhattan(q) < min_distance) return false;
    }
    return true;
}

const dirs4 = [_]GridPos{
    .{ .x = 0, .y = -1 },
    .{ .x = 1, .y = 0 },
    .{ .x = 0, .y = 1 },
    .{ .x = -1, .y = 0 },
};

const dirs8 = [_]GridPos{
    .{ .x = -1, .y = -1 },
    .{ .x = 0, .y = -1 },
    .{ .x = 1, .y = -1 },
    .{ .x = 1, .y = 0 },
    .{ .x = 1, .y = 1 },
    .{ .x = 0, .y = 1 },
    .{ .x = -1, .y = 1 },
    .{ .x = -1, .y = 0 },
};

/// Four orthogonal in-bounds neighbours. Returns how many were written.
pub fn neighbors4(p: GridPos, out: *[4]GridPos) usize {
    var n: usize = 0;
    for (dirs4) |delta| {
        const q = GridPos{ .x = p.x + delta.x, .y = p.y + delta.y };
        if (!q.inBounds()) continue;
        out[n] = q;
        n += 1;
    }
    return n;
}

/// Eight in-bounds neighbours (including diagonals), clockwise.
pub fn neighbors8(p: GridPos, out: *[8]GridPos) usize {
    var n: usize = 0;
    for (dirs8) |delta| {
        const q = GridPos{ .x = p.x + delta.x, .y = p.y + delta.y };
        if (!q.inBounds()) continue;
        out[n] = q;
        n += 1;
    }
    return n;
}

/// Bresenham line of sight. The two endpoints are never treated as blocking
/// (a wall cell can be targeted); every cell in between must be clear.
pub fn lineOfSight(from: GridPos, to: GridPos, ctx: anytype) bool {
    if (!from.inBounds() or !to.inBounds()) return false;

    var x = from.x;
    var y = from.y;
    const dx = if (to.x > x) to.x - x else x - to.x;
    const sx: i32 = if (x < to.x) 1 else -1;
    const dy = -@as(i32, if (to.y > y) to.y - y else y - to.y);
    const sy: i32 = if (y < to.y) 1 else -1;
    var err = dx + dy;

    while (true) {
        if (!(x == from.x and y == from.y) and !(x == to.x and y == to.y)) {
            if (ctx.isBlocked(GridPos{ .x = x, .y = y })) return false;
        }
        if (x == to.x and y == to.y) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }
    }
    return true;
}

/// A* over 4-neighbour movement. ctx needs isBlocked(GridPos) bool.
///
/// The start cell is always expanded even if it is currently occupied (an
/// actor looking for a way out), the goal must be free. Returns null when no
/// path exists. Result is a fixed-size Path, no allocator involved.
pub fn astar(start: GridPos, goal: GridPos, ctx: anytype) ?Path {
    if (!start.inBounds() or !goal.inBounds()) return null;

    var result = Path{};
    if (start.eql(goal)) {
        result.cells[0] = start;
        result.len = 1;
        return result;
    }
    if (ctx.isBlocked(goal)) return null;

    var g: [cell_count]u16 = @splat(std.math.maxInt(u16));
    var came_from: [cell_count]i16 = @splat(-1);
    var open: CellSet = CellSet.empty;
    var closed: CellSet = CellSet.empty;

    const start_index = start.index();
    g[start_index] = 0;
    open.set(start_index);

    while (true) {
        var current: ?usize = null;
        var current_f: u32 = std.math.maxInt(u32);
        var i: usize = 0;
        while (i < cell_count) : (i += 1) {
            if (!open.isSet(i)) continue;
            const pos = GridPos.fromIndex(i);
            const f = @as(u32, g[i]) + pos.manhattan(goal);
            if (f < current_f) {
                current_f = f;
                current = i;
            }
        }
        const current_index = current orelse return null;
        const current_pos = GridPos.fromIndex(current_index);

        if (current_pos.eql(goal)) {
            var len: usize = 0;
            var walk: usize = current_index;
            while (true) {
                result.cells[len] = GridPos.fromIndex(walk);
                len += 1;
                if (walk == start_index) break;
                const prev = came_from[walk];
                if (prev < 0) return null;
                walk = @intCast(prev);
            }
            std.mem.reverse(GridPos, result.cells[0..len]);
            result.len = len;
            return result;
        }

        open.unset(current_index);
        closed.set(current_index);

        var nb: [4]GridPos = undefined;
        const count = neighbors4(current_pos, &nb);
        for (nb[0..count]) |next| {
            const next_index = next.index();
            if (closed.isSet(next_index)) continue;
            if (ctx.isBlocked(next)) continue;
            const tentative = g[current_index] + 1;
            if (tentative < g[next_index]) {
                g[next_index] = tentative;
                came_from[next_index] = @intCast(current_index);
                open.set(next_index);
            }
        }
    }
}

const Flood = struct {
    mask: CellSet = CellSet.empty,
    count: usize = 0,
};

/// 4-neighbour flood fill from the entrance; optionally treats ignore as
/// solid (used to test whether an obstacle would disconnect the map).
fn floodFill(d: *const Dungeon, ignore: ?GridPos) Flood {
    var flood = Flood{};
    if (!d.entrance.inBounds()) return flood;
    if (ignore) |skip| {
        if (skip.eql(d.entrance)) return flood;
    }
    if (!d.tileAt(d.entrance).isWalkable()) return flood;

    var queue: [cell_count]GridPos = undefined;
    var head: usize = 0;
    var tail: usize = 0;
    queue[tail] = d.entrance;
    tail += 1;
    flood.mask.set(d.entrance.index());
    flood.count = 1;

    while (head < tail) {
        const cur = queue[head];
        head += 1;
        var nb: [4]GridPos = undefined;
        const count = neighbors4(cur, &nb);
        for (nb[0..count]) |next| {
            if (ignore) |skip| {
                if (skip.eql(next)) continue;
            }
            if (!d.tileAt(next).isWalkable()) continue;
            const idx = next.index();
            if (flood.mask.isSet(idx)) continue;
            flood.mask.set(idx);
            flood.count += 1;
            queue[tail] = next;
            tail += 1;
        }
    }
    return flood;
}

/// Would turning p into an obstacle keep the reachable floor connected?
fn canBlock(d: *const Dungeon, p: GridPos) bool {
    if (!d.tileAt(p).isWalkable()) return false;
    const before = floodFill(d, null).count;
    if (before == 0) return false;
    const after = floodFill(d, p).count;
    return after + 1 == before;
}

// ------------------------------------------------------------ generation

const Side = enum { bottom, left, right };
const Edge = enum { top, bottom, left, right };

fn entranceEdge(side: Side) Edge {
    return switch (side) {
        .bottom => .bottom,
        .left => .left,
        .right => .right,
    };
}

fn stairsEdge(side: Side) Edge {
    return switch (side) {
        .bottom => .top,
        .left => .right,
        .right => .left,
    };
}

const Rect = struct {
    x0: i32 = 0,
    y0: i32 = 0,
    x1: i32 = 0,
    y1: i32 = 0,

    fn width(self: Rect) i32 {
        return self.x1 - self.x0 + 1;
    }

    fn height(self: Rect) i32 {
        return self.y1 - self.y0 + 1;
    }

    fn center(self: Rect) GridPos {
        return .{ .x = @divTrunc(self.x0 + self.x1, 2), .y = @divTrunc(self.y0 + self.y1, 2) };
    }

    fn contains(self: Rect, p: GridPos) bool {
        return p.x >= self.x0 and p.x <= self.x1 and p.y >= self.y0 and p.y <= self.y1;
    }
};

fn roomAround(cx: i32, cy: i32, w: i32, h: i32) Rect {
    const x0 = std.math.clamp(cx - @divTrunc(w, 2), interior_min, interior_max - w + 1);
    const y0 = std.math.clamp(cy - @divTrunc(h, 2), interior_min, interior_max - h + 1);
    return .{ .x0 = x0, .y0 = y0, .x1 = x0 + w - 1, .y1 = y0 + h - 1 };
}

fn anchoredRoom(edge: Edge, anchor: GridPos, w: i32, h: i32) Rect {
    var r = roomAround(anchor.x, anchor.y, w, h);
    switch (edge) {
        .top => {
            r.y0 = interior_min;
            r.y1 = interior_min + h - 1;
        },
        .bottom => {
            r.y1 = interior_max;
            r.y0 = interior_max - h + 1;
        },
        .left => {
            r.x0 = interior_min;
            r.x1 = interior_min + w - 1;
        },
        .right => {
            r.x1 = interior_max;
            r.x0 = interior_max - w + 1;
        },
    }
    return r;
}

fn rectCorner(r: Rect, idx: u8) GridPos {
    return switch (idx % 4) {
        0 => .{ .x = r.x0, .y = r.y0 },
        1 => .{ .x = r.x1, .y = r.y0 },
        2 => .{ .x = r.x1, .y = r.y1 },
        else => .{ .x = r.x0, .y = r.y1 },
    };
}

fn insetCorner(r: Rect, idx: u8) GridPos {
    return switch (idx % 4) {
        0 => .{ .x = r.x0 + 1, .y = r.y0 + 1 },
        1 => .{ .x = r.x1 - 1, .y = r.y0 + 1 },
        2 => .{ .x = r.x1 - 1, .y = r.y1 - 1 },
        else => .{ .x = r.x0 + 1, .y = r.y1 - 1 },
    };
}

fn farIndex(rng: std.Random, lo: i32, hi: i32, base: i32, min_gap: i32) i32 {
    var best = lo;
    var best_gap: i32 = -1;
    var tries: usize = 0;
    while (tries < 8) : (tries += 1) {
        const v = rng.intRangeAtMost(i32, lo, hi);
        const gap = if (v > base) v - base else base - v;
        if (gap >= min_gap) return v;
        if (gap > best_gap) {
            best_gap = gap;
            best = v;
        }
    }
    return best;
}

const Builder = struct {
    d: *Dungeon,
    rng: std.Random,
    spine: [cell_count]bool = @splat(false),
    rooms: [5]Rect = @splat(.{}),
    room_count: usize = 0,
    dist: [cell_count]u16 = @splat(std.math.maxInt(u16)),

    fn chooseSide(b: *Builder) Side {
        const roll = b.rng.uintLessThan(u8, 100);
        if (roll < 60) return .bottom;
        if (roll < 80) return .left;
        return .right;
    }

    fn placeEntranceAndStairs(b: *Builder, side: Side) void {
        switch (side) {
            .bottom => {
                const ex = b.rng.intRangeAtMost(i32, 2, 10);
                const sx = farIndex(b.rng, 2, 10, ex, 4);
                b.d.entrance = .{ .x = ex, .y = interior_max };
                b.d.stairs = .{ .x = sx, .y = interior_min };
            },
            .left => {
                const ey = b.rng.intRangeAtMost(i32, 2, 10);
                const sy = farIndex(b.rng, 2, 10, ey, 4);
                b.d.entrance = .{ .x = interior_min, .y = ey };
                b.d.stairs = .{ .x = interior_max, .y = sy };
            },
            .right => {
                const ey = b.rng.intRangeAtMost(i32, 2, 10);
                const sy = farIndex(b.rng, 2, 10, ey, 4);
                b.d.entrance = .{ .x = interior_max, .y = ey };
                b.d.stairs = .{ .x = interior_min, .y = sy };
            },
        }
        b.d.setTile(b.d.entrance, .floor);
        b.d.setTile(b.d.stairs, .stairs);
    }

    fn carve(b: *Builder, p: GridPos) void {
        if (!isInterior(p)) return;
        if (b.d.tileAt(p) == .wall) b.d.setTile(p, .floor);
    }

    fn carveRect(b: *Builder, r: Rect) void {
        var y = r.y0;
        while (y <= r.y1) : (y += 1) {
            var x = r.x0;
            while (x <= r.x1) : (x += 1) b.carve(.{ .x = x, .y = y });
        }
    }

    fn addRoom(b: *Builder, r: Rect) void {
        std.debug.assert(b.room_count < b.rooms.len);
        b.carveRect(r);
        b.rooms[b.room_count] = r;
        b.room_count += 1;
    }

    fn addEdgeRoom(b: *Builder, edge: Edge, anchor: GridPos) void {
        const w = switch (edge) {
            .top, .bottom => b.rng.intRangeAtMost(i32, 4, 6),
            .left, .right => b.rng.intRangeAtMost(i32, 3, 4),
        };
        const h = switch (edge) {
            .left, .right => b.rng.intRangeAtMost(i32, 4, 6),
            .top, .bottom => b.rng.intRangeAtMost(i32, 3, 4),
        };
        b.addRoom(anchoredRoom(edge, anchor, w, h));
    }

    fn addMidRoom(b: *Builder, bend: GridPos) void {
        const w = b.rng.intRangeAtMost(i32, 3, 5);
        const h = b.rng.intRangeAtMost(i32, 3, 5);
        b.addRoom(roomAround(bend.x, bend.y, w, h));
    }

    fn addCenterRoom(b: *Builder, bend: GridPos) void {
        if (b.room_count >= b.rooms.len) return;
        const w = b.rng.intRangeAtMost(i32, 3, 5);
        const h = b.rng.intRangeAtMost(i32, 3, 5);
        const r = roomAround(6, 6, w, h);
        b.addRoom(r);
        b.carveLine(r.center(), bend);
    }

    fn addVault(b: *Builder, bend: GridPos) void {
        if (b.room_count >= b.rooms.len) return;
        if (b.rng.uintLessThan(u8, 100) >= 70) return;
        const candidates = [_]GridPos{
            .{ .x = 2, .y = 2 },
            .{ .x = 10, .y = 2 },
            .{ .x = 2, .y = 10 },
            .{ .x = 10, .y = 10 },
        };
        var eligible: [4]GridPos = undefined;
        var n: usize = 0;
        for (candidates) |c| {
            const r = roomAround(c.x, c.y, 3, 3);
            if (r.contains(b.d.entrance) or r.contains(b.d.stairs)) continue;
            eligible[n] = c;
            n += 1;
        }
        if (n == 0) return;
        const pick = eligible[b.rng.uintLessThan(usize, n)];
        const r = roomAround(pick.x, pick.y, 3, 3);
        b.addRoom(r);
        b.carveLine(bend, r.center());
    }

    fn carveLine(b: *Builder, from: GridPos, to: GridPos) void {
        var p = from;
        b.carve(p);
        while (p.x != to.x) {
            p.x += if (to.x > p.x) 1 else -1;
            b.carve(p);
        }
        while (p.y != to.y) {
            p.y += if (to.y > p.y) 1 else -1;
            b.carve(p);
        }
    }

    fn markSpine(b: *Builder, p: GridPos) void {
        if (!isInterior(p)) return;
        b.spine[p.index()] = true;
        b.carve(p);
    }

    fn spineLine(b: *Builder, from: GridPos, to: GridPos) void {
        var p = from;
        b.markSpine(p);
        while (p.x != to.x) {
            p.x += if (to.x > p.x) 1 else -1;
            b.markSpine(p);
        }
        while (p.y != to.y) {
            p.y += if (to.y > p.y) 1 else -1;
            b.markSpine(p);
        }
    }

    fn carveSpine(b: *Builder) GridPos {
        const a = b.d.entrance;
        const s = b.d.stairs;
        const bend = if (b.rng.boolean())
            GridPos{ .x = s.x, .y = a.y }
        else
            GridPos{ .x = a.x, .y = s.y };
        b.spineLine(a, bend);
        b.spineLine(bend, s);
        return bend;
    }

    fn decorate(b: *Builder) void {
        b.placePillars();
        b.placeBraziers();
        b.placeWater();
        b.placeRubble();
        b.ensureObstacles(4);
    }

    fn tryObstacle(b: *Builder, p: GridPos, prop: Prop) bool {
        if (!isInterior(p)) return false;
        if (p.eql(b.d.entrance) or p.eql(b.d.stairs)) return false;
        if (b.d.tileAt(p) != .floor) return false;
        if (b.d.propAt(p) != .none) return false;
        if (b.spine[p.index()]) return false;
        if (!canBlock(b.d, p)) return false;
        b.d.setTile(p, .obstacle);
        b.d.setProp(p, prop);
        return true;
    }

    fn collectFloor(d: *const Dungeon, buf: []GridPos) usize {
        var n: usize = 0;
        var y: usize = 0;
        while (y < size) : (y += 1) {
            var x: usize = 0;
            while (x < size) : (x += 1) {
                if (d.tiles[y][x] == .floor) {
                    buf[n] = .{ .x = @intCast(x), .y = @intCast(y) };
                    n += 1;
                }
            }
        }
        return n;
    }

    fn randomFloor(b: *Builder) ?GridPos {
        var pool: [cell_count]GridPos = undefined;
        const n = collectFloor(b.d, &pool);
        if (n == 0) return null;
        return pool[b.rng.uintLessThan(usize, n)];
    }

    fn placePillars(b: *Builder) void {
        for (b.rooms[0..b.room_count]) |r| {
            if (r.width() < 4 or r.height() < 4) continue;
            if (b.rng.uintLessThan(u8, 100) < 30) continue;
            const all = b.rng.boolean();
            var i: usize = 0;
            while (i < 4) : (i += 1) {
                if (!all and (i % 2) == 1) continue;
                _ = b.tryObstacle(insetCorner(r, @intCast(i)), .column);
            }
        }
    }

    fn placeBraziers(b: *Builder) void {
        const target = b.rng.intRangeAtMost(usize, 2, 4);
        var placed: usize = 0;
        var attempts: usize = 0;
        while (placed < target and attempts < 24) : (attempts += 1) {
            const r = b.rooms[b.rng.uintLessThan(usize, b.room_count)];
            const p = rectCorner(r, b.rng.uintLessThan(u8, 4));
            if (b.tryObstacle(p, .brazier)) placed += 1;
        }
        if (placed != 0) return;
        attempts = 0;
        while (placed < 2 and attempts < 24) : (attempts += 1) {
            const p = b.randomFloor() orelse return;
            if (b.tryObstacle(p, .brazier)) placed += 1;
        }
    }

    fn placeWater(b: *Builder) void {
        const pools = b.rng.intRangeAtMost(usize, 1, 2);
        var pool_index: usize = 0;
        while (pool_index < pools) : (pool_index += 1) {
            const start = b.randomFloor() orelse return;
            if (start.eql(b.d.entrance) or start.eql(b.d.stairs)) continue;
            if (!b.tryObstacle(start, .water)) continue;

            const target = b.rng.intRangeAtMost(usize, 2, 4);
            var nb: [4]GridPos = undefined;
            const count = neighbors4(start, &nb);
            if (count == 0) continue;

            var placed: usize = 1;
            var attempts: usize = 0;
            while (placed < target and attempts < 8) : (attempts += 1) {
                const p = nb[b.rng.uintLessThan(usize, count)];
                if (b.tryObstacle(p, .water)) placed += 1;
            }
        }
    }

    fn placeRubble(b: *Builder) void {
        const target = b.rng.intRangeAtMost(usize, 2, 4);
        var placed: usize = 0;
        var attempts: usize = 0;
        while (placed < target and attempts < 24) : (attempts += 1) {
            const p = b.randomFloor() orelse return;
            if (b.tryObstacle(p, .rubble)) placed += 1;
        }
    }

    fn ensureObstacles(b: *Builder, minimum: usize) void {
        if (b.d.countTile(.obstacle) >= minimum) return;
        var pool: [cell_count]GridPos = undefined;
        const n = collectFloor(b.d, &pool);
        shuffle(b.rng, pool[0..n]);
        for (pool[0..n]) |p| {
            if (b.d.countTile(.obstacle) >= minimum) break;
            _ = b.tryObstacle(p, .rubble);
        }
    }

    fn computeDistances(b: *Builder) void {
        @memset(b.dist[0..], std.math.maxInt(u16));
        var queue: [cell_count]GridPos = undefined;
        var head: usize = 0;
        var tail: usize = 0;
        const start = b.d.entrance;
        if (!start.inBounds()) return;
        b.dist[start.index()] = 0;
        queue[tail] = start;
        tail += 1;
        while (head < tail) {
            const cur = queue[head];
            head += 1;
            var nb: [4]GridPos = undefined;
            const count = neighbors4(cur, &nb);
            for (nb[0..count]) |next| {
                if (!b.d.tileAt(next).isWalkable()) continue;
                const idx = next.index();
                if (b.dist[idx] != std.math.maxInt(u16)) continue;
                b.dist[idx] = b.dist[cur.index()] + 1;
                queue[tail] = next;
                tail += 1;
            }
        }
    }

    fn placeTraps(b: *Builder) void {
        const target = trapsForFloor(b.d.floor);
        var pool: [cell_count]GridPos = undefined;
        const n = collectFloor(b.d, &pool);
        shuffle(b.rng, pool[0..n]);

        var placed: usize = 0;
        for (pool[0..n]) |p| {
            if (placed >= target) break;
            if (b.d.tileAt(p) != .floor) continue;
            if (p.eql(b.d.entrance) or p.eql(b.d.stairs)) continue;
            if (b.dist[p.index()] < 3) continue;
            b.d.setTile(p, .trap);
            b.d.traps[placed] = p;
            placed += 1;
        }
        if (placed < target) {
            for (pool[0..n]) |p| {
                if (placed >= target) break;
                if (b.d.tileAt(p) != .floor) continue;
                if (p.eql(b.d.entrance) or p.eql(b.d.stairs)) continue;
                b.d.setTile(p, .trap);
                b.d.traps[placed] = p;
                placed += 1;
            }
        }
        b.d.trap_count = @intCast(placed);
    }

    fn placeChests(b: *Builder) void {
        const target = chestsForFloor(b.d.floor);
        var pool: [cell_count]GridPos = undefined;
        const n = collectFloor(b.d, &pool);
        shuffle(b.rng, pool[0..n]);

        const passes = [_]struct { min_dist: u16, spacing: u32 }{
            .{ .min_dist = 5, .spacing = 3 },
            .{ .min_dist = 4, .spacing = 2 },
            .{ .min_dist = 3, .spacing = 1 },
            .{ .min_dist = 0, .spacing = 0 },
        };

        var placed: usize = 0;
        for (passes) |pass| {
            if (placed >= target) break;
            for (pool[0..n]) |p| {
                if (placed >= target) break;
                if (b.d.tileAt(p) != .floor) continue;
                if (p.eql(b.d.entrance) or p.eql(b.d.stairs)) continue;
                if (b.dist[p.index()] < pass.min_dist) continue;
                if (pass.spacing > 0 and !farEnough(p, b.d.chests[0..placed], pass.spacing)) continue;
                b.d.setTile(p, .chest);
                b.d.chests[placed] = p;
                placed += 1;
            }
        }
        b.d.chest_count = @intCast(placed);
    }

    fn placeSpawns(b: *Builder) void {
        const target = spawnsForFloor(b.d.floor);
        var pool: [cell_count]GridPos = undefined;
        const n = collectFloor(b.d, &pool);
        if (n == 0) return;
        shuffle(b.rng, pool[0..n]);

        var chosen: [max_spawns]GridPos = @splat(.{});
        var count: usize = 0;

        for (pool[0..n]) |p| {
            if (b.dist[p.index()] < 6) continue;
            chosen[0] = p;
            count = 1;
            break;
        }
        if (count == 0) {
            for (pool[0..n]) |p| {
                if (b.dist[p.index()] < 3) continue;
                chosen[0] = p;
                count = 1;
                break;
            }
        }
        if (count == 0) {
            for (pool[0..n]) |p| {
                if (b.d.tileAt(p) != .floor) continue;
                if (p.eql(b.d.entrance) or p.eql(b.d.stairs)) continue;
                chosen[0] = p;
                count = 1;
                break;
            }
        }
        if (count == 0) return;

        while (count < target) {
            var best: GridPos = .{};
            var best_score: i64 = -1;
            var found = false;

            for (pool[0..n]) |p| {
                if (b.d.tileAt(p) != .floor) continue;
                if (p.eql(b.d.entrance) or p.eql(b.d.stairs)) continue;
                if (b.dist[p.index()] < 3) continue;

                var duplicate = false;
                for (chosen[0..count]) |q| {
                    if (q.eql(p)) duplicate = true;
                }
                if (duplicate) continue;

                var min_distance: i64 = 64;
                for (chosen[0..count]) |q| {
                    const d = @as(i64, p.manhattan(q));
                    if (d < min_distance) min_distance = d;
                }
                const score = min_distance * 1024 + @as(i64, b.dist[p.index()]);
                if (score > best_score) {
                    best_score = score;
                    best = p;
                    found = true;
                }
            }
            if (!found) break;
            chosen[count] = best;
            count += 1;
        }

        // Guarantee the floor-scaled count even on a cramped layout.
        if (count < target) {
            for (pool[0..n]) |p| {
                if (count >= target) break;
                if (b.d.tileAt(p) != .floor) continue;
                if (p.eql(b.d.entrance) or p.eql(b.d.stairs)) continue;
                var duplicate = false;
                for (chosen[0..count]) |q| {
                    if (q.eql(p)) duplicate = true;
                }
                if (duplicate) continue;
                chosen[count] = p;
                count += 1;
            }
        }

        var i: usize = 0;
        while (i < count) : (i += 1) b.d.enemy_spawns[i] = chosen[i];
        b.d.spawn_count = @intCast(count);
    }
};

// ------------------------------------------------------------------- tests

const testing = std.testing;

fn openRoom() Dungeon {
    var d = Dungeon.filled(.wall);
    var y: i32 = 1;
    while (y <= 11) : (y += 1) {
        var x: i32 = 1;
        while (x <= 11) : (x += 1) d.setTile(.{ .x = x, .y = y }, .floor);
    }
    d.entrance = .{ .x = 1, .y = 11 };
    d.stairs = .{ .x = 11, .y = 1 };
    d.setTile(d.stairs, .stairs);
    return d;
}

fn layoutHash(d: *const Dungeon) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&d.tiles));
    hasher.update(std.mem.asBytes(&d.props));
    hasher.update(std.mem.asBytes(&d.entrance));
    hasher.update(std.mem.asBytes(&d.stairs));
    return hasher.final();
}

test "same seed and floor reproduce exactly" {
    const a = Dungeon.generate(0xdead_beef, 2);
    const b = Dungeon.generate(0xdead_beef, 2);
    try testing.expect(std.meta.eql(a, b));
    try a.validate();

    // A different floor of the same run must not repeat the layout.
    const other_floor = Dungeon.generate(0xdead_beef, 3);
    try testing.expect(!std.meta.eql(a, other_floor));

    // Floor 0 is normalised to floor 1.
    const zero = Dungeon.generate(0xdead_beef, 0);
    const one = Dungeon.generate(0xdead_beef, 1);
    try testing.expectEqual(@as(u8, 1), zero.floor);
    try testing.expect(std.meta.eql(zero, one));
}

test "different seeds produce different layouts" {
    var hashes: [10]u64 = undefined;
    var distinct: usize = 0;
    var i: usize = 0;
    while (i < hashes.len) : (i += 1) {
        const d = Dungeon.generate(1000 + i * 7919, 1);
        const h = layoutHash(&d);
        var seen = false;
        for (hashes[0..i]) |old| {
            if (old == h) seen = true;
        }
        hashes[i] = h;
        if (!seen) distinct += 1;
    }
    try testing.expect(distinct >= hashes.len - 1);
}

test "one hundred generated floors stay connected" {
    var i: u64 = 0;
    while (i < 100) : (i += 1) {
        const floor: u8 = @intCast(i % 3 + 1);
        const d = Dungeon.generate(i *% 0x9e3779b97f4a7c15, floor);
        try d.validate();

        const path = d.astarTo(d.entrance, d.stairs, null) orelse return error.StairsUnreachable;
        try testing.expect(path.len > 0);
        try testing.expect(path.first().?.eql(d.entrance));
        try testing.expect(path.last().?.eql(d.stairs));

        try testing.expectEqual(chestsForFloor(floor), d.chestSlice().len);
        try testing.expectEqual(spawnsForFloor(floor), d.spawnSlice().len);
        try testing.expectEqual(trapsForFloor(floor), d.trapSlice().len);
        try testing.expect(d.countTile(.obstacle) >= 4);
    }
}

test "floor budgets scale with depth" {
    try testing.expectEqual(@as(usize, 2), chestsForFloor(1));
    try testing.expectEqual(@as(usize, 3), chestsForFloor(2));
    try testing.expectEqual(@as(usize, 4), chestsForFloor(3));
    try testing.expectEqual(@as(usize, 4), chestsForFloor(9));

    try testing.expectEqual(@as(usize, 4), spawnsForFloor(1));
    try testing.expectEqual(@as(usize, 6), spawnsForFloor(2));
    try testing.expectEqual(@as(usize, 8), spawnsForFloor(3));
    try testing.expectEqual(@as(usize, 8), spawnsForFloor(9));
}

test "astar routes around a wall" {
    var d = openRoom();
    var y: i32 = 1;
    while (y <= 10) : (y += 1) d.setTile(.{ .x = 6, .y = y }, .wall);

    const start = GridPos{ .x = 2, .y = 6 };
    const goal = GridPos{ .x = 10, .y = 6 };
    const path = astar(start, goal, d.blockCtx(null)) orelse return error.ExpectedPath;
    try testing.expect(path.len > 9);
    try testing.expect(path.first().?.eql(start));
    try testing.expect(path.last().?.eql(goal));

    var prev = start;
    for (path.slice(), 0..) |p, idx| {
        try testing.expect(!d.isBlocked(p, null));
        if (idx > 0) try testing.expectEqual(@as(u32, 1), prev.manhattan(p));
        prev = p;
    }

    // A clear row still gets the direct nine-cell path.
    const direct = astar(.{ .x = 2, .y = 11 }, .{ .x = 10, .y = 11 }, d.blockCtx(null)) orelse return error.ExpectedPath;
    try testing.expectEqual(@as(usize, 9), direct.len);
    try testing.expectEqual(@as(usize, 1), astar(start, start, d.blockCtx(null)).?.len);
}

test "astar returns null when the goal is sealed" {
    var d = openRoom();
    const goal = GridPos{ .x = 6, .y = 6 };
    d.setTile(.{ .x = 6, .y = 5 }, .wall);
    d.setTile(.{ .x = 6, .y = 7 }, .wall);
    d.setTile(.{ .x = 5, .y = 6 }, .wall);
    d.setTile(.{ .x = 7, .y = 6 }, .wall);
    try testing.expect(astar(.{ .x = 1, .y = 6 }, goal, d.blockCtx(null)) == null);
}

test "bresenham line of sight is blocked by walls" {
    var d = openRoom();
    d.setTile(.{ .x = 6, .y = 6 }, .wall);
    try testing.expect(!d.lineOfSightTo(.{ .x = 5, .y = 6 }, .{ .x = 7, .y = 6 }, null));
    try testing.expect(d.lineOfSightTo(.{ .x = 5, .y = 5 }, .{ .x = 7, .y = 5 }, null));
    try testing.expect(d.lineOfSightTo(.{ .x = 2, .y = 2 }, .{ .x = 2, .y = 2 }, null));

    var occ = Occupancy{};
    occ.set(.{ .x = 6, .y = 5 });
    try testing.expect(!d.lineOfSightTo(.{ .x = 5, .y = 5 }, .{ .x = 7, .y = 5 }, &occ));
    try testing.expect(d.lineOfSightTo(.{ .x = 5, .y = 5 }, .{ .x = 7, .y = 5 }, null));
}

test "occupancy blocks movement and pathfinding" {
    var d = openRoom();
    var y: i32 = 1;
    while (y <= 10) : (y += 1) d.setTile(.{ .x = 6, .y = y }, .wall);

    const gap = GridPos{ .x = 6, .y = 11 };
    var occ = Occupancy{};
    try testing.expect(!d.isBlocked(gap, &occ));
    occ.set(gap);
    try testing.expect(d.isBlocked(gap, &occ));
    try testing.expectEqual(@as(usize, 1), occ.count());
    try testing.expect(d.astarTo(.{ .x = 2, .y = 6 }, .{ .x = 10, .y = 6 }, &occ) == null);

    occ.unset(gap);
    try testing.expect(d.astarTo(.{ .x = 2, .y = 6 }, .{ .x = 10, .y = 6 }, &occ) != null);

    occ.rebuild(&[_]GridPos{ gap, .{ .x = 1, .y = 1 } });
    try testing.expectEqual(@as(usize, 2), occ.count());
    try testing.expect(d.isWalkable(gap));
    occ.clearAll();
    try testing.expectEqual(@as(usize, 0), occ.count());
}

test "astar can path onto an occupied goal" {
    var d = openRoom();
    const goal = GridPos{ .x = 10, .y = 6 };
    var occ = Occupancy{};
    occ.set(goal);

    try testing.expect(d.astarTo(.{ .x = 2, .y = 6 }, goal, &occ) == null);
    const path = d.astarToOccupiedGoal(.{ .x = 2, .y = 6 }, goal, &occ) orelse return error.ExpectedPath;
    try testing.expect(path.last().?.eql(goal));

    // Terrain still wins over the goal exception.
    d.setTile(goal, .wall);
    try testing.expect(d.astarToOccupiedGoal(.{ .x = 2, .y = 6 }, goal, &occ) == null);
}

test "13x13 bounds and neighbour counts" {
    try testing.expectEqual(@as(usize, 13), size);
    try testing.expectEqual(@as(usize, 169), cell_count);

    const d = Dungeon.generate(7, 1);
    try testing.expectEqual(Tile.wall, d.tileAt(.{ .x = 0, .y = 0 }));
    try testing.expectEqual(Tile.wall, d.tileAt(.{ .x = 12, .y = 12 }));
    try testing.expect(!d.isWalkable(.{ .x = -1, .y = 6 }));
    try testing.expect(!d.isWalkable(.{ .x = 13, .y = 6 }));
    try testing.expect(d.isBlocked(.{ .x = 13, .y = 6 }, null));

    var out4: [4]GridPos = undefined;
    var out8: [8]GridPos = undefined;
    try testing.expectEqual(@as(usize, 2), neighbors4(.{ .x = 0, .y = 0 }, &out4));
    try testing.expectEqual(@as(usize, 4), neighbors4(.{ .x = 6, .y = 6 }, &out4));
    try testing.expectEqual(@as(usize, 3), neighbors8(.{ .x = 0, .y = 0 }, &out8));
    try testing.expectEqual(@as(usize, 8), neighbors8(.{ .x = 6, .y = 6 }, &out8));

    var i: usize = 0;
    while (i < cell_count) : (i += 1) {
        const p = GridPos.fromIndex(i);
        try testing.expect(p.inBounds());
        try testing.expectEqual(i, p.index());
    }
}

test "grid and world coordinates round-trip" {
    const center = (GridPos{ .x = 6, .y = 6 }).toWorld();
    try testing.expectEqual(@as(f32, 0.0), center.x);
    try testing.expectEqual(@as(f32, 0.0), center.z);

    const corner = (GridPos{ .x = 0, .y = 12 }).toWorld();
    try testing.expectEqual(@as(f32, -6.0), corner.x);
    try testing.expectEqual(@as(f32, 6.0), corner.z);
    try testing.expect(GridPos.fromWorld(-6.4, 6.4).?.eql(.{ .x = 0, .y = 12 }));
    try testing.expect(GridPos.fromWorld(7.0, 0.0) == null);
    try testing.expect(GridPos.fromWorld(0.0, 7.0) == null);

    var y: i32 = 0;
    while (y < 13) : (y += 1) {
        var x: i32 = 0;
        while (x < 13) : (x += 1) {
            const p = GridPos{ .x = x, .y = y };
            const world = p.toWorld();
            const back = GridPos.fromWorld(world.x, world.z) orelse return error.RoundTrip;
            try testing.expect(back.eql(p));
        }
    }
}

test "validate rejects broken maps" {
    const good = Dungeon.generate(123, 1);

    var open_border = good;
    open_border.setTile(.{ .x = 0, .y = 5 }, .floor);
    try testing.expectError(error.BorderOpen, open_border.validate());

    var no_chests = good;
    no_chests.chest_count = 0;
    try testing.expectError(error.BadChestCount, no_chests.validate());

    var overlap = good;
    overlap.enemy_spawns[1] = overlap.enemy_spawns[0];
    try testing.expectError(error.DuplicateSpawn, overlap.validate());

    var wrong_tile = good;
    wrong_tile.setTile(wrong_tile.chests[0], .floor);
    try testing.expectError(error.MarkerTerrain, wrong_tile.validate());

    var too_close = good;
    too_close.stairs = .{ .x = too_close.entrance.x + 1, .y = too_close.entrance.y };
    too_close.setTile(too_close.stairs, .stairs);
    try testing.expectError(error.EntranceTooClose, too_close.validate());

    // Seal the stairs: find a generated floor whose stairs have only plain
    // floor around them, then wall those neighbours.
    var sealed: Dungeon = undefined;
    var found = false;
    var seed: u64 = 0;
    while (seed < 200 and !found) : (seed += 1) {
        var candidate = Dungeon.generate(seed, 1);
        var nb: [4]GridPos = undefined;
        const count = neighbors4(candidate.stairs, &nb);
        var clean = true;
        for (nb[0..count]) |p| {
            const tile = candidate.tileAt(p);
            if (tile == .floor) {
                for (candidate.spawnSlice()) |spawn| {
                    if (spawn.eql(p)) clean = false;
                }
            } else if (tile != .wall) {
                clean = false;
            }
        }
        if (!clean) continue;
        for (nb[0..count]) |p| candidate.setTile(p, .wall);
        sealed = candidate;
        found = true;
    }
    try testing.expect(found);
    try testing.expectError(error.UnreachableStairs, sealed.validate());
}

test "ascii dump reflects markers" {
    const d = Dungeon.generate(2026, 2);
    var buf: [cell_count + size]u8 = undefined;
    const map = d.renderAscii(&buf);
    try testing.expectEqual(cell_count + size, map.len);

    var lines: usize = 0;
    for (map) |ch| {
        if (ch == '\n') lines += 1;
    }
    try testing.expectEqual(size, lines);

    const entrance_idx = @as(usize, @intCast(d.entrance.y)) * (size + 1) + @as(usize, @intCast(d.entrance.x));
    try testing.expectEqual(@as(u8, '>'), map[entrance_idx]);
    const stairs_idx = @as(usize, @intCast(d.stairs.y)) * (size + 1) + @as(usize, @intCast(d.stairs.x));
    try testing.expectEqual(@as(u8, '<'), map[stairs_idx]);
    for (d.chestSlice()) |p| {
        const idx = @as(usize, @intCast(p.y)) * (size + 1) + @as(usize, @intCast(p.x));
        try testing.expectEqual(@as(u8, 'C'), map[idx]);
    }
}

test "tile walkability table" {
    try testing.expect(!walkable(.wall));
    try testing.expect(!walkable(.obstacle));
    try testing.expect(walkable(.floor));
    try testing.expect(walkable(.stairs));
    try testing.expect(walkable(.chest));
    try testing.expect(walkable(.trap));
    try testing.expect(Prop.brazier.blocksMovement());
    try testing.expect(!Prop.none.blocksMovement());
    try testing.expectEqualStrings("column", Prop.column.modelName().?);
    try testing.expect(Prop.water.modelName() == null);
}
