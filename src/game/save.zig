//! Save / load for the pure turn-based run state (`run_sim.Sim`).
//!
//! The module has no SDL, renderer or HUD dependency. It only needs an
//! allocator for the JSON buffer and a `std.Io` for the optional file
//! helpers, so the windowed game, headless QA and unit tests all use the same
//! code path.
//!
//! Format v2
//! ---------
//! One minified `std.json` document:
//!
//!   {"format":"vx-run-save","version":2,"seed":12345,"class":"warrior",
//!    "floor":1,"floors":3,"turn":42,"state":"playing","kills":2,
//!    "chest_loot":1,"kill_loot":2,"rng":[u64,u64,u64,u64],
//!    "hero":{...},"enemies":[...],"map":{...},"log":["...",...]}
//!
//! * `version` is checked exactly; v1 (13x13) saves are rejected as UnsupportedVersion; the 31x31 map cannot be migrated by re-seeding.
//! * Coordinates are the simulation's 31x31 grid coordinates and are checked to
//!   be in bounds and walkable where the run state requires it.
//! * Enemy names are derived from the enemy kind in `run_sim`, so they
//!   are validated against that kind instead of being trusted as free text.
//! * `log` is written oldest -> newest (display order); on load the ring
//!   buffer is rebuilt so `logAt` and the HUD keep the same order.
//! * `rng` stores the complete xoshiro256 state, so a loaded run keeps
//!   rolling the same crits and damage rolls as the original run.
//!
//! The `dungeon.Dungeon` inside `Sim` is not stored tile-by-tile. It is
//! rebuilt from `blocked` plus stairs/chests/traps after a load, which is all
//! the simulation reads (line of sight and A*). Props and generation-time spawn
//! markers are presentation / next-floor data and are not part of the run state;
//! the next floor regenerates them from seed + floor.
//!
//! API
//! ---
//!   saveAlloc(alloc, *const Sim) ![]u8
//!   loadAlloc(alloc, []const u8) LoadError!Sim
//!   saveFile(io, alloc, path, *const Sim) !void
//!   loadFile(io, alloc, path) !Sim
//!
//! `loadAlloc` never panics on bad input and never writes to the input
//! buffer. `loadFile` opens the file read-only, so a corrupt save stays on
//! disk untouched for inspection.
const std = @import("std");
const sim_mod = @import("run_sim.zig");
const dungeon_mod = @import("dungeon.zig");

const Sim = sim_mod.Sim;
const Enemy = sim_mod.Enemy;

/// Current on-disk format. Bump whenever a field changes meaning or the RNG
/// representation changes.
pub const save_version: u16 = 2;
pub const format_name = "vx-run-save";

/// Hard cap for `loadAlloc` / `loadFile`. A real v2 save is a few
/// kilobytes; anything larger is treated as a bad file instead of being parsed.
pub const max_save_bytes: usize = 256 * 1024;

const grid_w = sim_mod.grid_w;
const grid_h = sim_mod.grid_h;
const cell_count = grid_w * grid_h;
const max_enemies = sim_mod.max_enemies;
const log_lines_max = 6;
const log_line_bytes_max = 64;
const chest_slots = 4;
const trap_slots = 4;
const cooldown_slots = 3;
const stat_count = 6;

pub const SaveError = error{
    /// The in-memory sim cannot be represented (non-finite numbers, too many
    /// enemies or a corrupt log ring).
    InvalidState,
    /// Empty input or an empty file.
    EmptySave,
    /// Input exceeds `max_save_bytes`.
    SaveTooLarge,
    /// `format` is not `vx-run-save`.
    NotSaveFormat,
    /// `version` is not `save_version`.
    UnsupportedVersion,
    /// JSON value is followed by another token or trailing garbage.
    TrailingData,
    /// A grid coordinate is outside 0..30.
    InvalidCoordinate,
    /// Enemy kind has no entry in the name table.
    InvalidEnemyKind,
    /// Stored enemy name does not belong to the stored kind.
    InvalidEnemyName,
    /// More than `max_enemies` entries.
    TooManyEnemies,
    /// Log has too many lines or a line longer than 64 bytes / invalid UTF-8.
    InvalidLog,
    /// RNG state is all zeroes.
    InvalidRng,
    /// Finite float / range check failed.
    InvalidValue,
    /// Map invariants (closed border, marker on wall, duplicate actors, ...).
    InconsistentMap,
};

pub const LoadError = SaveError || std.json.ParseError(std.json.Scanner);

const GridPosSave = struct { x: i32, y: i32 };

const StatsSave = struct {
    strength: f32,
    agility: f32,
    constitution: f32,
    perception: f32,
    magic: f32,
    will: f32,
};

const HeroSave = struct {
    pos: GridPosSave,
    last_pos: GridPosSave,
    stats: StatsSave,
    hp: f32,
    hp_max: f32,
    resource: f32,
    resource_max: f32,
    attack: f32,
    armor: f32,
    crit: f32,
    speed: u16,
    res_per_turn: f32,
    level: u16,
    xp: u32,
    pending_points: u8 = 0,
    cooldowns: [cooldown_slots]u16,
    buff_turns: u16,
    buff_pct: f32,
    eff_stats: [stat_count]f32,
};

const EnemySave = struct {
    kind: u8,
    name: []const u8,
    pos: GridPosSave,
    hp: f32,
    hp_max: f32,
    attack: f32,
    armor: f32,
    speed: u16,
    range: u16,
    xp: u32,
    stun_turns: u16,
    slow_turns: u16,
    alive: bool,
    /// Action points; absent in older v2 files means 0.
    energy: i16 = 0,
};

const MapSave = struct {
    blocked: [cell_count]bool,
    entrance: GridPosSave,
    stairs: GridPosSave,
    chests: [chest_slots]GridPosSave,
    chest_alive: [chest_slots]bool,
    traps: [trap_slots]GridPosSave,
    trap_alive: [trap_slots]bool,
    aoe_target: GridPosSave,
    aoe_armed: bool,
};

const SaveRoot = struct {
    format: []const u8,
    version: u16,
    seed: u64,
    class: sim_mod.Class,
    floor: u8,
    floors: u8,
    turn: u32,
    state: sim_mod.State,
    kills: u32,
    chest_loot: u32,
    kill_loot: u32,
    rng: [4]u64,
    hero: HeroSave,
    enemies: []EnemySave,
    map: MapSave,
    log: []const []const u8,
};

/// Enemy kind -> display name, mirroring `run_sim.enemy_defs`. The table
/// lives here so the save format can validate `kind` and `name` as a pair
/// without exposing the simulation's private definitions. The
/// "enemy names match the simulation" test keeps the two in sync.
const enemy_names = [_][]const u8{
    "骷髅兵",
    "幽魂",
    "石魔像",
    "精英骷髅",
    "精英幽魂",
    "深渊守卫",
};

fn savePos(p: anytype) GridPosSave {
    return .{ .x = p.x, .y = p.y };
}

fn loadPos(p: GridPosSave) sim_mod.GridPos {
    return .{ .x = p.x, .y = p.y };
}

fn inBounds(p: GridPosSave) bool {
    return p.x >= 0 and p.y >= 0 and
        p.x < @as(i32, @intCast(grid_w)) and
        p.y < @as(i32, @intCast(grid_h));
}

fn posIndex(p: GridPosSave) usize {
    return @as(usize, @intCast(p.y)) * grid_w + @as(usize, @intCast(p.x));
}

fn samePos(a: GridPosSave, b: GridPosSave) bool {
    return a.x == b.x and a.y == b.y;
}

fn mapBlocked(map: *const MapSave, p: GridPosSave) bool {
    return map.blocked[posIndex(p)];
}

fn allFinite(values: []const f32) bool {
    for (values) |v| {
        if (!std.math.isFinite(v)) return false;
    }
    return true;
}

fn statsFinite(stats: StatsSave) bool {
    inline for (@typeInfo(StatsSave).@"struct".field_names) |name| {
        if (!std.math.isFinite(@field(stats, name))) return false;
    }
    return true;
}

fn rngNonZero(state: [4]u64) bool {
    for (state) |word| {
        if (word != 0) return true;
    }
    return false;
}

// ------------------------------------------------------------------ writing

/// Build the RunState document. The caller owns the returned slice and frees
/// it with `alloc`.
pub fn saveAlloc(alloc: std.mem.Allocator, sim: *const Sim) ![]u8 {
    if (sim.enemy_count > max_enemies) return error.InvalidState;
    if (sim.log_total > log_lines_max) return error.InvalidState;

    var enemy_buf: [max_enemies]EnemySave = undefined;
    for (sim.enemies[0..sim.enemy_count], 0..) |e, i| {
        if (!std.math.isFinite(e.vitals.hp) or !std.math.isFinite(e.vitals.hp_max) or
            !std.math.isFinite(e.combat.attack) or !std.math.isFinite(e.combat.armor))
        {
            return error.InvalidState;
        }
        enemy_buf[i] = .{
            .kind = e.identity.kind,
            .name = e.identity.name,
            .pos = savePos(e.pos),
            .hp = e.vitals.hp,
            .hp_max = e.vitals.hp_max,
            .attack = e.combat.attack,
            .armor = e.combat.armor,
            .speed = e.combat.speed,
            .range = e.combat.range,
            .xp = e.reward.xp,
            .stun_turns = e.status.stun_turns,
            .slow_turns = e.status.slow_turns,
            .alive = e.vitals.alive,
            .energy = e.action.energy,
        };
    }

    const hero = sim.hero;
    if (!std.math.isFinite(hero.vitals.hp) or !std.math.isFinite(hero.vitals.hp_max) or
        !std.math.isFinite(hero.resource.current) or !std.math.isFinite(hero.resource.max) or
        !std.math.isFinite(hero.combat.attack) or !std.math.isFinite(hero.combat.armor) or
        !std.math.isFinite(hero.combat.crit) or !std.math.isFinite(hero.resource.per_turn) or
        !std.math.isFinite(hero.status.buff_pct) or !allFinite(&hero.sheet.eff_stats) or
        !statsFinite(.{
            .strength = hero.sheet.stats.strength,
            .agility = hero.sheet.stats.agility,
            .constitution = hero.sheet.stats.constitution,
            .perception = hero.sheet.stats.perception,
            .magic = hero.sheet.stats.magic,
            .will = hero.sheet.stats.will,
        }))
    {
        return error.InvalidState;
    }

    var log_buf: [log_lines_max][]const u8 = undefined;
    var log_i: usize = 0;
    while (log_i < sim.log_total) : (log_i += 1) {
        if (sim.log_buf[(sim.log_head + log_buf.len - sim.log_total + log_i) % log_buf.len].len > log_line_bytes_max) {
            return error.InvalidState;
        }
        log_buf[log_i] = sim.logAt(log_i);
    }

    var chests: [chest_slots]GridPosSave = undefined;
    var chest_alive: [chest_slots]bool = undefined;
    for (sim.chests, sim.chest_alive, 0..) |p, alive, i| {
        chests[i] = savePos(p);
        chest_alive[i] = alive;
    }
    var traps: [trap_slots]GridPosSave = undefined;
    var trap_alive: [trap_slots]bool = undefined;
    for (sim.traps, sim.trap_alive, 0..) |p, alive, i| {
        traps[i] = savePos(p);
        trap_alive[i] = alive;
    }

    const root = SaveRoot{
        .format = format_name,
        .version = save_version,
        .seed = sim.seed,
        .class = sim.class,
        .floor = sim.floor,
        .floors = sim.floors,
        .turn = sim.turn,
        .state = sim.state,
        .kills = sim.kills,
        .chest_loot = sim.chest_loot_events,
        .kill_loot = sim.kill_loot_events,
        .rng = sim.rng.s,
        .hero = .{
            .pos = savePos(hero.pos),
            .last_pos = savePos(hero.last_pos),
            .stats = .{
                .strength = hero.sheet.stats.strength,
                .agility = hero.sheet.stats.agility,
                .constitution = hero.sheet.stats.constitution,
                .perception = hero.sheet.stats.perception,
                .magic = hero.sheet.stats.magic,
                .will = hero.sheet.stats.will,
            },
            .hp = hero.vitals.hp,
            .hp_max = hero.vitals.hp_max,
            .resource = hero.resource.current,
            .resource_max = hero.resource.max,
            .attack = hero.combat.attack,
            .armor = hero.combat.armor,
            .crit = hero.combat.crit,
            .speed = hero.combat.speed,
            .res_per_turn = hero.resource.per_turn,
            .level = hero.progression.level,
            .xp = hero.progression.xp,
            .pending_points = hero.progression.pending_points,
            .cooldowns = hero.talents.cooldowns,
            .buff_turns = hero.status.buff_turns,
            .buff_pct = hero.status.buff_pct,
            .eff_stats = hero.sheet.eff_stats,
        },
        .enemies = enemy_buf[0..sim.enemy_count],
        .map = .{
            .blocked = sim.blocked,
            .entrance = savePos(sim.map.entrance),
            .stairs = savePos(sim.stairs),
            .chests = chests,
            .chest_alive = chest_alive,
            .traps = traps,
            .trap_alive = trap_alive,
            .aoe_target = savePos(sim.aoe_target),
            .aoe_armed = sim.aoe_armed,
        },
        .log = log_buf[0..sim.log_total],
    };

    return std.json.Stringify.valueAlloc(alloc, root, .{});
}

// ------------------------------------------------------------------ reading

/// Parse and validate a RunState document. All allocations are released before
/// returning; a failed parse/validation returns an error and no `Sim`.
pub fn loadAlloc(alloc: std.mem.Allocator, bytes: []const u8) LoadError!Sim {
    if (bytes.len == 0) return error.EmptySave;
    if (bytes.len > max_save_bytes) return error.SaveTooLarge;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var scanner = std.json.Scanner.initCompleteInput(arena.allocator(), bytes);
    defer scanner.deinit();

    const options: std.json.ParseOptions = .{
        .max_value_len = bytes.len,
        .allocate = .alloc_if_needed,
    };
    const root = std.json.innerParse(SaveRoot, arena.allocator(), &scanner, options) catch |err| return err;

    // `parseFromSlice` would only check this behind a debug assertion;
    // do it explicitly so trailing garbage is always an error, release or not.
    // After a complete root value the scanner reports depth-0 trailing content
    // as SyntaxError, so normalise both cases to TrailingData.
    const end = scanner.next() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.TrailingData,
    };
    if (end != .end_of_document) return error.TrailingData;

    return buildSim(&root);
}

fn buildSim(root: *const SaveRoot) SaveError!Sim {
    if (!std.mem.eql(u8, root.format, format_name)) return error.NotSaveFormat;
    if (root.version != save_version) return error.UnsupportedVersion;
    if (root.floors == 0) return error.InvalidValue;
    if (root.floor == 0 or root.floor > root.floors) return error.InvalidValue;
    if (root.turn == 0) return error.InvalidValue;
    if (root.enemies.len > max_enemies) return error.TooManyEnemies;
    if (root.log.len > log_lines_max) return error.InvalidLog;

    const h = &root.hero;
    if (!inBounds(h.pos) or !inBounds(h.last_pos)) return error.InvalidCoordinate;
    if (!statsFinite(h.stats)) return error.InvalidValue;
    if (!allFinite(&h.eff_stats)) return error.InvalidValue;
    if (!std.math.isFinite(h.hp) or !std.math.isFinite(h.hp_max) or
        !std.math.isFinite(h.resource) or !std.math.isFinite(h.resource_max) or
        !std.math.isFinite(h.attack) or !std.math.isFinite(h.armor) or
        !std.math.isFinite(h.crit) or !std.math.isFinite(h.res_per_turn) or
        !std.math.isFinite(h.buff_pct)) return error.InvalidValue;
    if (h.hp_max <= 0 or h.hp < 0 or h.hp > h.hp_max) return error.InvalidValue;
    if (h.resource_max <= 0 or h.resource < 0 or h.resource > h.resource_max) return error.InvalidValue;
    if (h.attack < 0 or h.armor < 0 or h.res_per_turn < 0) return error.InvalidValue;
    if (h.crit < 0 or h.crit > 1) return error.InvalidValue;
    if (h.buff_pct < 0 or h.buff_pct > 1) return error.InvalidValue;
    if (h.speed == 0 or h.speed > 1000) return error.InvalidValue;
    if (h.level == 0 or h.level > 50) return error.InvalidValue;

    const map = &root.map;
    if (!inBounds(map.entrance) or !inBounds(map.stairs) or !inBounds(map.aoe_target)) {
        return error.InvalidCoordinate;
    }
    if (!rngNonZero(root.rng)) return error.InvalidRng;

    // Closed outer border: the dungeon generator guarantees it and the renderer
    // / pathfinding assume it.
    var edge: usize = 0;
    while (edge < grid_w) : (edge += 1) {
        if (!map.blocked[edge] or
            !map.blocked[cell_count - grid_w + edge] or
            !map.blocked[edge * grid_w] or
            !map.blocked[edge * grid_w + grid_w - 1])
        {
            return error.InconsistentMap;
        }
    }
    if (mapBlocked(map, map.entrance)) return error.InconsistentMap;
    if (mapBlocked(map, map.stairs)) return error.InconsistentMap;
    if (samePos(map.entrance, map.stairs)) return error.InconsistentMap;
    if (mapBlocked(map, h.pos)) return error.InconsistentMap;

    var chest_alive_count: usize = 0;
    var alive_chests: [chest_slots]GridPosSave = undefined;
    for (map.chests, map.chest_alive) |p, alive| {
        if (!inBounds(p)) return error.InvalidCoordinate;
        if (!alive) continue;
        if (mapBlocked(map, p)) return error.InconsistentMap;
        if (samePos(p, map.entrance) or samePos(p, map.stairs)) return error.InconsistentMap;
        for (alive_chests[0..chest_alive_count]) |q| {
            if (samePos(p, q)) return error.InconsistentMap;
        }
        alive_chests[chest_alive_count] = p;
        chest_alive_count += 1;
    }
    var trap_alive_count: usize = 0;
    var alive_traps: [trap_slots]GridPosSave = undefined;
    for (map.traps, map.trap_alive) |p, alive| {
        if (!inBounds(p)) return error.InvalidCoordinate;
        if (!alive) continue;
        if (mapBlocked(map, p)) return error.InconsistentMap;
        if (samePos(p, map.entrance) or samePos(p, map.stairs)) return error.InconsistentMap;
        for (alive_traps[0..trap_alive_count]) |q| {
            if (samePos(p, q)) return error.InconsistentMap;
        }
        alive_traps[trap_alive_count] = p;
        trap_alive_count += 1;
    }
    for (alive_chests[0..chest_alive_count]) |c| {
        for (alive_traps[0..trap_alive_count]) |t| {
            if (samePos(c, t)) return error.InconsistentMap;
        }
    }

    for (root.enemies, 0..) |e, i| {
        if (@as(usize, e.kind) >= enemy_names.len) return error.InvalidEnemyKind;
        if (!std.mem.eql(u8, e.name, enemy_names[e.kind])) return error.InvalidEnemyName;
        if (!inBounds(e.pos)) return error.InvalidCoordinate;
        if (mapBlocked(map, e.pos)) return error.InconsistentMap;
        if (!std.math.isFinite(e.hp) or !std.math.isFinite(e.hp_max) or
            !std.math.isFinite(e.attack) or !std.math.isFinite(e.armor)) return error.InvalidValue;
        if (e.hp_max <= 0 or e.hp < 0 or e.hp > e.hp_max) return error.InvalidValue;
        if (e.attack < 0 or e.armor < 0) return error.InvalidValue;
        if (e.speed == 0 or e.speed > 1000) return error.InvalidValue;
        if (e.range > grid_w) return error.InvalidValue;
        if (e.energy < -100 or e.energy > 200) return error.InvalidValue;
        if (e.alive) {
            if (samePos(e.pos, h.pos)) return error.InconsistentMap;
            for (root.enemies[0..i]) |other| {
                if (other.alive and samePos(other.pos, e.pos)) return error.InconsistentMap;
            }
        }
    }

    for (root.log) |line| {
        if (line.len > log_line_bytes_max) return error.InvalidLog;
        if (!std.unicode.utf8ValidateSlice(line)) return error.InvalidLog;
    }

    var sim = Sim{
        .seed = root.seed,
        .rng = .{ .s = root.rng },
        .class = root.class,
        .hero = .{
            .class = root.class,
            .pos = loadPos(h.pos),
            .last_pos = loadPos(h.last_pos),
            .sheet = .{
                .stats = .{
                    .strength = h.stats.strength,
                    .agility = h.stats.agility,
                    .constitution = h.stats.constitution,
                    .perception = h.stats.perception,
                    .magic = h.stats.magic,
                    .will = h.stats.will,
                },
                .eff_stats = h.eff_stats,
            },
            .vitals = .{ .hp = h.hp, .hp_max = h.hp_max },
            .resource = .{ .current = h.resource, .max = h.resource_max, .per_turn = h.res_per_turn },
            .combat = .{ .attack = h.attack, .armor = h.armor, .crit = h.crit, .speed = h.speed },
            .progression = .{ .level = h.level, .xp = h.xp, .pending_points = h.pending_points },
            .status = .{ .buff_turns = h.buff_turns, .buff_pct = h.buff_pct },
            .talents = .{ .cooldowns = h.cooldowns },
        },
    };
    sim.floor = root.floor;
    sim.floors = root.floors;
    sim.turn = root.turn;
    sim.state = root.state;
    sim.kills = root.kills;
    sim.chest_loot_events = root.chest_loot;
    sim.kill_loot_events = root.kill_loot;
    sim.aoe_target = loadPos(map.aoe_target);
    sim.aoe_armed = map.aoe_armed;
    sim.blocked = map.blocked;
    sim.stairs = loadPos(map.stairs);
    for (map.chests, 0..) |p, i| sim.chests[i] = loadPos(p);
    sim.chest_alive = map.chest_alive;
    sim.chest_count = chest_alive_count;
    for (map.traps, 0..) |p, i| sim.traps[i] = loadPos(p);
    sim.trap_alive = map.trap_alive;
    sim.trap_count = trap_alive_count;

    sim.enemies = @splat(.{});
    for (root.enemies, 0..) |e, i| {
        sim.enemies[i] = .{
            .identity = .{ .kind = e.kind, .name = enemy_names[e.kind] },
            .pos = loadPos(e.pos),
            .vitals = .{ .hp = e.hp, .hp_max = e.hp_max, .alive = e.alive },
            .combat = .{ .attack = e.attack, .armor = e.armor, .speed = e.speed, .range = e.range },
            .status = .{ .stun_turns = e.stun_turns, .slow_turns = e.slow_turns },
            .reward = .{ .xp = e.xp },
            .action = .{ .energy = e.energy },
        };
    }
    sim.enemy_count = root.enemies.len;

    sim.log_buf = @splat(.{ .text = @splat(0), .len = 0 });
    for (root.log, 0..) |line, i| {
        @memcpy(sim.log_buf[i].text[0..line.len], line);
        sim.log_buf[i].len = line.len;
    }
    sim.log_total = root.log.len;
    sim.log_head = root.log.len % log_lines_max;

    sim.map = rebuildDungeon(&sim, loadPos(map.entrance));
    return sim;
}

/// Rebuild the parts of `dungeon.Dungeon` that the simulation reads. The
/// walkability grid is authoritative; marker cells keep their tile type so
/// line of sight / A* / debug glyphs stay consistent.
fn rebuildDungeon(sim: *const Sim, entrance: sim_mod.GridPos) dungeon_mod.Dungeon {
    var map = dungeon_mod.Dungeon.filled(.wall);
    map.seed = sim.seed;
    map.floor = sim.floor;
    map.entrance = .{ .x = entrance.x, .y = entrance.y };

    var y: usize = 0;
    while (y < grid_h) : (y += 1) {
        var x: usize = 0;
        while (x < grid_w) : (x += 1) {
            const p = dungeon_mod.GridPos{ .x = @intCast(x), .y = @intCast(y) };
            map.setTile(p, if (sim.blocked[y * grid_w + x]) .wall else .floor);
            map.setProp(p, .none);
        }
    }

    map.setTile(.{ .x = entrance.x, .y = entrance.y }, .floor);
    map.setTile(.{ .x = sim.stairs.x, .y = sim.stairs.y }, .stairs);

    var chest_at: usize = 0;
    for (sim.chests, sim.chest_alive) |p, alive| {
        if (!alive) continue;
        const gp = dungeon_mod.GridPos{ .x = p.x, .y = p.y };
        map.setTile(gp, .chest);
        map.chests[chest_at] = gp;
        chest_at += 1;
    }
    map.chest_count = @intCast(chest_at);

    var trap_at: usize = 0;
    for (sim.traps, sim.trap_alive) |p, alive| {
        if (!alive) continue;
        const gp = dungeon_mod.GridPos{ .x = p.x, .y = p.y };
        map.setTile(gp, .trap);
        map.traps[trap_at] = gp;
        trap_at += 1;
    }
    map.trap_count = @intCast(trap_at);

    return map;
}

// -------------------------------------------------------------- files

/// Write a save file. The path may be relative to the process cwd or absolute;
/// parent directories must already exist.
pub fn saveFile(io: std.Io, alloc: std.mem.Allocator, path: []const u8, sim: *const Sim) !void {
    const bytes = try saveAlloc(alloc, sim);
    defer alloc.free(bytes);

    var atomic = if (std.fs.path.isAbsolute(path))
        try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true })
    else
        try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writeStreamingAll(io, bytes);
    try atomic.replace(io);
}

/// Read and validate a save file. The file is opened read-only; a bad save is
/// left on disk exactly as it was.
pub fn loadFile(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !Sim {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(max_save_bytes));
    defer alloc.free(bytes);
    return loadAlloc(alloc, bytes);
}

// ------------------------------------------------------------------ tests

const testing = std.testing;

/// One byte over the per-line budget, used by the validation test.
const too_long_log_line: [log_line_bytes_max + 1]u8 = @splat('a');

/// Storage for the "more enemies than the format allows" mutation. It lives at
/// file scope so the slice stays valid after the patch callback returns.
var too_many_enemies_buf: [max_enemies + 1]EnemySave = undefined;

/// Deterministic bot used by the round-trip tests: bump adjacent enemies, spend
/// talents on nearby targets, otherwise walk the A* path to the stairs. No RNG
/// of its own, so two sims given the same seed and step count stay in lockstep.
fn drive(sim: *Sim, steps: usize) void {
    const dirs = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
    var step: usize = 0;
    while (step < steps and sim.state == .playing) : (step += 1) {
        var acted = false;
        for (dirs) |d| {
            if (sim.enemyAt(sim.hero.pos.x + d[0], sim.hero.pos.y + d[1]) != null) {
                _ = sim.move(d[0], d[1]);
                acted = true;
                break;
            }
        }
        if (acted) continue;

        if (sim.nearestEnemy(5) != null) {
            if (sim.useTalent(0)) continue;
            if (sim.useTalent(1)) continue;
        }

        if (sim.map.astarToOccupiedGoal(
            .{ .x = sim.hero.pos.x, .y = sim.hero.pos.y },
            .{ .x = sim.stairs.x, .y = sim.stairs.y },
            null,
        )) |path| {
            if (path.len > 1) {
                const next = path.slice()[1];
                if (sim.move(next.x - sim.hero.pos.x, next.y - sim.hero.pos.y)) continue;
            }
        }
        _ = sim.wait();
    }
}

fn expectSameEnemy(expected: Enemy, actual: Enemy) !void {
    try testing.expectEqual(expected.identity.kind, actual.identity.kind);
    try testing.expectEqualStrings(expected.identity.name, actual.identity.name);
    try testing.expectEqual(expected.pos.x, actual.pos.x);
    try testing.expectEqual(expected.pos.y, actual.pos.y);
    try testing.expectEqual(expected.vitals.hp, actual.vitals.hp);
    try testing.expectEqual(expected.vitals.hp_max, actual.vitals.hp_max);
    try testing.expectEqual(expected.combat.attack, actual.combat.attack);
    try testing.expectEqual(expected.combat.armor, actual.combat.armor);
    try testing.expectEqual(expected.combat.speed, actual.combat.speed);
    try testing.expectEqual(expected.combat.range, actual.combat.range);
    try testing.expectEqual(expected.reward.xp, actual.reward.xp);
    try testing.expectEqual(expected.status.stun_turns, actual.status.stun_turns);
    try testing.expectEqual(expected.status.slow_turns, actual.status.slow_turns);
    try testing.expectEqual(expected.vitals.alive, actual.vitals.alive);
    try testing.expectEqual(expected.action.energy, actual.action.energy);
}

/// Compare every field the save format promises to restore, plus the rebuilt
/// dungeon's walkability contract.
fn expectSameRun(expected: *const Sim, actual: *const Sim) !void {
    try testing.expectEqual(expected.seed, actual.seed);
    try testing.expectEqual(expected.class, actual.class);
    try testing.expectEqual(expected.floor, actual.floor);
    try testing.expectEqual(expected.floors, actual.floors);
    try testing.expectEqual(expected.turn, actual.turn);
    try testing.expectEqual(expected.state, actual.state);
    try testing.expectEqual(expected.kills, actual.kills);
    try testing.expectEqual(expected.chest_loot_events, actual.chest_loot_events);
    try testing.expectEqual(expected.kill_loot_events, actual.kill_loot_events);
    try testing.expectEqual(expected.chest_count, actual.chest_count);
    try testing.expectEqual(expected.trap_count, actual.trap_count);
    try testing.expectEqual(expected.enemy_count, actual.enemy_count);
    try testing.expectEqual(expected.aoe_armed, actual.aoe_armed);
    try testing.expectEqual(expected.aoe_target.x, actual.aoe_target.x);
    try testing.expectEqual(expected.aoe_target.y, actual.aoe_target.y);
    try testing.expectEqual(expected.stairs.x, actual.stairs.x);
    try testing.expectEqual(expected.stairs.y, actual.stairs.y);
    try testing.expectEqual(expected.map.entrance.x, actual.map.entrance.x);
    try testing.expectEqual(expected.map.entrance.y, actual.map.entrance.y);

    try testing.expect(std.meta.eql(expected.hero, actual.hero));
    try testing.expect(std.meta.eql(expected.rng.s, actual.rng.s));
    try testing.expectEqualSlices(bool, &expected.blocked, &actual.blocked);
    try testing.expect(std.meta.eql(expected.chests, actual.chests));
    try testing.expect(std.meta.eql(expected.chest_alive, actual.chest_alive));
    try testing.expect(std.meta.eql(expected.traps, actual.traps));
    try testing.expect(std.meta.eql(expected.trap_alive, actual.trap_alive));

    for (expected.enemies[0..expected.enemy_count], actual.enemies[0..actual.enemy_count]) |a, b| {
        try expectSameEnemy(a, b);
    }

    try testing.expectEqual(expected.log_total, actual.log_total);
    var i: usize = 0;
    while (i < expected.log_total) : (i += 1) {
        try testing.expectEqualStrings(expected.logAt(i), actual.logAt(i));
    }

    // Both line of sight and A* go through Dungeon.isWalkable, so the rebuilt
    // map must agree with the authoritative blocked grid on every cell.
    var y: i32 = 0;
    while (y < grid_h) : (y += 1) {
        var x: i32 = 0;
        while (x < grid_w) : (x += 1) {
            const p = dungeon_mod.GridPos{ .x = x, .y = y };
            try testing.expectEqual(expected.isBlocked(x, y), !actual.map.isWalkable(p));
        }
    }
}

fn expectLoadFails(alloc: std.mem.Allocator, bytes: []const u8) !void {
    if (loadAlloc(alloc, bytes)) |_| {
        return error.ExpectedLoadFailure;
    } else |_| {}
}

fn replaceOnce(alloc: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const at = std.mem.indexOf(u8, input, needle) orelse return error.TestPatternNotFound;
    const out = try alloc.alloc(u8, input.len - needle.len + replacement.len);
    @memcpy(out[0..at], input[0..at]);
    @memcpy(out[at..][0..replacement.len], replacement);
    @memcpy(out[at + replacement.len ..], input[at + needle.len ..]);
    return out;
}

fn concatAlloc(alloc: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    const out = try alloc.alloc(u8, a.len + b.len);
    @memcpy(out[0..a.len], a);
    @memcpy(out[a.len..], b);
    return out;
}

/// Re-encode a valid save after mutating the typed document. Used to exercise
/// one validation rule at a time without hand-writing JSON.
fn patchedSave(alloc: std.mem.Allocator, bytes: []const u8, patch: anytype) ![]u8 {
    const parsed = try std.json.parseFromSlice(SaveRoot, alloc, bytes, .{});
    defer parsed.deinit();
    var root = parsed.value;
    patch(&root);
    return std.json.Stringify.valueAlloc(alloc, root, .{});
}

test "save: fresh run round-trips (short log, no events)" {
    const alloc = testing.allocator;
    var sim = Sim.init(4242, .warrior);
    sim.hero.progression.pending_points = 2;
    try testing.expect(sim.log_total < log_lines_max);

    const bytes = try saveAlloc(alloc, &sim);
    defer alloc.free(bytes);
    try testing.expect(std.mem.startsWith(u8, bytes, "{\"format\":\"vx-run-save\",\"version\":2,"));
    try testing.expect(std.mem.indexOfScalar(u8, bytes, '\n') == null);

    var loaded = try loadAlloc(alloc, bytes);
    try expectSameRun(&sim, &loaded);

    const again = try saveAlloc(alloc, &loaded);
    defer alloc.free(again);
    try testing.expectEqualStrings(bytes, again);
}

test "save: played run round-trips and continues identically" {
    const alloc = testing.allocator;
    var sim = Sim.init(12345, .mage);
    drive(&sim, 90);
    try testing.expect(sim.turn > 10);
    try testing.expect(sim.kills > 0);

    const bytes = try saveAlloc(alloc, &sim);
    defer alloc.free(bytes);
    var loaded = try loadAlloc(alloc, bytes);
    try expectSameRun(&sim, &loaded);

    // Saving a loaded run must be canonical: same bytes.
    const again = try saveAlloc(alloc, &loaded);
    defer alloc.free(again);
    try testing.expectEqualStrings(bytes, again);

    // Strongest check: both runs keep simulating from the same RNG state, so
    // crits, damage, enemy movement, loot counters and logs stay identical.
    var original = sim;
    drive(&original, 40);
    drive(&loaded, 40);
    try expectSameRun(&original, &loaded);
}

test "save: same seed and actions produce identical bytes" {
    const alloc = testing.allocator;
    var a = Sim.init(777, .chronomancer);
    var b = Sim.init(777, .chronomancer);
    drive(&a, 60);
    drive(&b, 60);

    const bytes_a = try saveAlloc(alloc, &a);
    defer alloc.free(bytes_a);
    const bytes_b = try saveAlloc(alloc, &b);
    defer alloc.free(bytes_b);
    try testing.expectEqualStrings(bytes_a, bytes_b);
}

test "load: empty, truncated and garbage input returns an error" {
    const alloc = testing.allocator;
    var sim = Sim.init(2024, .warrior);
    drive(&sim, 30);
    const bytes = try saveAlloc(alloc, &sim);
    defer alloc.free(bytes);

    try testing.expectError(error.EmptySave, loadAlloc(alloc, ""));
    const cuts = [_]usize{ 1, 4, bytes.len / 4, bytes.len / 2, bytes.len - 1 };
    for (cuts) |cut| try expectLoadFails(alloc, bytes[0..cut]);

    const garbage = [_][]const u8{
        " ",
        "{",
        "null",
        "[]",
        "not json",
        "{\"format\":\"vx-run-save\"}",
    };
    for (garbage) |text| try expectLoadFails(alloc, text);
}

test "load: strict version, format, trailing data and enum checks" {
    const alloc = testing.allocator;
    var sim = Sim.init(99, .mage);
    drive(&sim, 25);
    const bytes = try saveAlloc(alloc, &sim);
    defer alloc.free(bytes);

    const v_bad = try patchedSave(alloc, bytes, struct {
        fn patch(root: *SaveRoot) void {
            root.version = 1;
        }
    }.patch);
    defer alloc.free(v_bad);
    try testing.expectError(error.UnsupportedVersion, loadAlloc(alloc, v_bad));

    const other_format = try patchedSave(alloc, bytes, struct {
        fn patch(root: *SaveRoot) void {
            root.format = "other-save";
        }
    }.patch);
    defer alloc.free(other_format);
    try testing.expectError(error.NotSaveFormat, loadAlloc(alloc, other_format));

    const trailing = try concatAlloc(alloc, bytes, " true");
    defer alloc.free(trailing);
    try testing.expectError(error.TrailingData, loadAlloc(alloc, trailing));

    const trailing_object = try concatAlloc(alloc, bytes, "{}");
    defer alloc.free(trailing_object);
    try expectLoadFails(alloc, trailing_object);

    const bad_class = try replaceOnce(alloc, bytes, "\"class\":\"mage\"", "\"class\":\"rogue\"");
    defer alloc.free(bad_class);
    try testing.expectError(error.InvalidEnumTag, loadAlloc(alloc, bad_class));
}

test "load: out-of-range run state is rejected field by field" {
    const alloc = testing.allocator;
    var sim = Sim.init(31337, .warrior);
    drive(&sim, 40);
    const bytes = try saveAlloc(alloc, &sim);
    defer alloc.free(bytes);

    const cases = .{
        .{ "bad coordinate", error.InvalidCoordinate, struct {
            fn patch(root: *SaveRoot) void {
                root.hero.pos.x = 99;
            }
        }.patch },
        .{ "open border", error.InconsistentMap, struct {
            fn patch(root: *SaveRoot) void {
                root.map.blocked[0] = false;
            }
        }.patch },
        .{ "hero on wall", error.InconsistentMap, struct {
            fn patch(root: *SaveRoot) void {
                root.map.blocked[@as(usize, @intCast(root.hero.pos.y)) * grid_w + @as(usize, @intCast(root.hero.pos.x))] = true;
            }
        }.patch },
        .{ "hp above max", error.InvalidValue, struct {
            fn patch(root: *SaveRoot) void {
                root.hero.hp = root.hero.hp_max + 1;
            }
        }.patch },
        .{ "zero rng", error.InvalidRng, struct {
            fn patch(root: *SaveRoot) void {
                root.rng = @splat(0);
            }
        }.patch },
        .{ "bad enemy kind", error.InvalidEnemyKind, struct {
            fn patch(root: *SaveRoot) void {
                root.enemies[0].kind = 9;
            }
        }.patch },
        .{ "bad enemy name", error.InvalidEnemyName, struct {
            fn patch(root: *SaveRoot) void {
                root.enemies[0].name = "冒牌敌人";
            }
        }.patch },
        .{ "long log line", error.InvalidLog, struct {
            fn patch(root: *SaveRoot) void {
                root.log = &[_][]const u8{too_long_log_line[0..]};
            }
        }.patch },
        .{ "too many enemies", error.TooManyEnemies, struct {
            fn patch(root: *SaveRoot) void {
                @memset(&too_many_enemies_buf, root.enemies[0]);
                root.enemies = too_many_enemies_buf[0..];
            }
        }.patch },
    };

    inline for (cases) |case| {
        const bad = try patchedSave(alloc, bytes, case[2]);
        defer alloc.free(bad);
        try testing.expectError(case[1], loadAlloc(alloc, bad));
    }
}

test "save file: round-trip and a corrupt file is rejected without overwriting" {
    const alloc = testing.allocator;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const save_path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "run.json" });
    defer alloc.free(save_path);

    var sim = Sim.init(5150, .warrior);
    drive(&sim, 35);
    try saveFile(io, alloc, save_path, &sim);
    var loaded = try loadFile(io, alloc, save_path);
    try expectSameRun(&sim, &loaded);

    const corrupt = "{\"format\":\"vx-run-save\",\"version\":2,";
    try tmp.dir.writeFile(io, .{ .sub_path = "run.json", .data = corrupt });
    const before = try tmp.dir.readFileAlloc(io, "run.json", alloc, .limited(max_save_bytes));
    defer alloc.free(before);

    if (loadFile(io, alloc, save_path)) |_| {
        return error.ExpectedLoadFailure;
    } else |_| {}

    const after = try tmp.dir.readFileAlloc(io, "run.json", alloc, .limited(max_save_bytes));
    defer alloc.free(after);
    try testing.expectEqualStrings(before, after);
}

test "save file: atomic overwrite replaces an existing valid save" {
    const alloc = testing.allocator;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const save_path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "run.json" });
    defer alloc.free(save_path);

    var first = Sim.init(5150, .warrior);
    try saveFile(io, alloc, save_path, &first);

    var second = Sim.init(6161, .mage);
    drive(&second, 20);
    try saveFile(io, alloc, save_path, &second);

    var loaded = try loadFile(io, alloc, save_path);
    try testing.expectEqual(second.seed, loaded.seed);
    try testing.expectEqual(second.class, loaded.class);
    try expectSameRun(&second, &loaded);
}

test "save: enemy name table matches the simulation" {
    var sim = Sim.init(20240607, .warrior);
    var floor: u8 = 1;
    while (floor <= sim.floors) : (floor += 1) {
        sim.floor = floor;
        sim.generateFloor();
        try testing.expect(sim.enemy_count > 0);
        for (sim.enemies[0..sim.enemy_count]) |e| {
            try testing.expect(e.identity.kind < enemy_names.len);
            try testing.expectEqualStrings(enemy_names[e.identity.kind], e.identity.name);
        }
    }
}

test "save: dead run with no enemies round-trips" {
    const alloc = testing.allocator;
    var sim = Sim.init(8080, .chronomancer);
    sim.enemy_count = 0;
    sim.enemies = @splat(.{});
    sim.hero.vitals.hp = 0;
    sim.state = .dead;
    sim.aoe_armed = false;

    const bytes = try saveAlloc(alloc, &sim);
    defer alloc.free(bytes);
    var loaded = try loadAlloc(alloc, bytes);
    try expectSameRun(&sim, &loaded);
    try testing.expectEqual(sim_mod.State.dead, loaded.state);
}
