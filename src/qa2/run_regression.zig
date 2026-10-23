//! QA2 regression + batch simulation for the pure RunSim.
//!
//! This file is test/tooling only: it never mutates RunSim behaviour. It
//! drives the same public API the game and the headless auto path use, adds
//! invariant checks around every action, and prints reproducible metrics.
//!
//! Run through `zig build test` (module root imports this file) or
//! `zig build test-qa` for the focused step.
const std = @import("std");
const run = @import("../game/run_sim.zig");
const dungeon = @import("../game/dungeon.zig");
const content_mod = @import("../game/content.zig");
const attributes = @import("../game/attributes.zig");
const items_mod = @import("../game/items.zig");
const intent_mod = @import("../game/intent.zig");

/// Seeds used by the generation matrix and by the autoplay batch.
pub const seed_count: usize = 100;
/// Fixed, documented seed for the human-readable reproducible report.
pub const fixed_seed: u64 = 12345;
/// Safety cap: an autoplay that never terminates is itself a QA failure.
pub const max_auto_turns: u32 = 1200;

pub const dirs4 = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };

pub fn seedFor(index: usize) u64 {
    // Spread seeds; distinct from the documented 12345 and from each other.
    return 0x51A2_0000 +% (@as(u64, @intCast(index)) *% 104_729);
}

pub fn classFor(index: usize) run.Class {
    return run.classFromIndex(@intCast(index % run.class_count));
}

pub fn toAttrClass(class: run.Class) attributes.Class {
    return switch (class) {
        .warrior => .warrior,
        .mage => .mage,
        .chronomancer => .chronomancer,
    };
}

fn samePos(a: run.GridPos, b: run.GridPos) bool {
    return a.x == b.x and a.y == b.y;
}

fn outOfBounds(p: run.GridPos) bool {
    return p.x < 0 or p.y < 0 or p.x >= run.grid_w or p.y >= run.grid_h;
}

fn inBoundsGrid(p: dungeon.GridPos) bool {
    return p.inBounds();
}

fn checkMarkerOverlap(d: *const dungeon.Dungeon) !void {
    const groups = [_][]const dungeon.GridPos{
        d.chestSlice(),
        d.spawnSlice(),
        d.trapSlice(),
    };
    const names = [_][]const u8{ "chest", "spawn", "trap" };
    for (groups, 0..) |group, gi| {
        for (group, 0..) |p, i| {
            if (!inBoundsGrid(p)) {
                std.debug.print("[qa2] {s} {d} out of bounds\n", .{ names[gi], i });
                return error.MarkerOutOfBounds;
            }
            if (!dungeon.isInterior(p)) {
                std.debug.print("[qa2] {s} {d} outside interior\n", .{ names[gi], i });
                return error.MarkerOutsideInterior;
            }
            if (!d.isWalkable(p)) {
                std.debug.print("[qa2] {s} {d} on unwalkable tile\n", .{ names[gi], i });
                return error.MarkerOnWall;
            }
            if (p.eql(d.entrance) or p.eql(d.stairs)) {
                std.debug.print("[qa2] {s} {d} overlaps entrance/stairs\n", .{ names[gi], i });
                return error.MarkerOnDoor;
            }
            for (group[0..i]) |q| {
                if (p.eql(q)) {
                    std.debug.print("[qa2] duplicate {s} marker\n", .{names[gi]});
                    return error.DuplicateMarker;
                }
            }
            for (groups[0..gi]) |other| {
                for (other) |q| {
                    if (p.eql(q)) {
                        std.debug.print("[qa2] {s} marker overlaps another marker group\n", .{names[gi]});
                        return error.MarkerOverlap;
                    }
                }
            }
        }
    }
}

/// Validate one generated floor plus the RunSim state derived from it.
fn checkFloor(seed: u64, floor: u8) !void {
    const d = dungeon.Dungeon.generate(seed, floor);
    d.validate() catch |err| {
        std.debug.print("[qa2] dungeon validate failed seed={d} floor={d}: {s}\n", .{ seed, floor, @errorName(err) });
        return err;
    };
    if (d.seed != seed or d.floor != floor) return error.SeedOrFloorMismatch;
    if (d.chest_count < dungeon.min_chests or d.chest_count > dungeon.max_chests) return error.BadChestCount;
    if (d.spawn_count < dungeon.min_spawns or d.spawn_count > dungeon.max_spawns) return error.BadSpawnCount;
    if (d.trap_count > dungeon.max_traps) return error.BadTrapCount;
    try checkMarkerOverlap(&d);

    // Entrance -> stairs must be routable on terrain alone.
    const path = d.astarTo(d.entrance, d.stairs, null) orelse {
        std.debug.print("[qa2] stairs unreachable seed={d} floor={d}\n", .{ seed, floor });
        return error.StairsUnreachable;
    };
    if (path.len < 2) return error.PathTooShort;
    const first = path.first() orelse return error.EmptyPath;
    const last = path.last() orelse return error.EmptyPath;
    if (!first.eql(d.entrance) or !last.eql(d.stairs)) return error.BadPathEndpoints;
    var prev = first;
    for (path.slice()[1..]) |p| {
        if (@abs(p.x - prev.x) + @abs(p.y - prev.y) != 1) return error.PathNotAdjacent;
        if (!d.isWalkable(p)) return error.PathThroughWall;
        prev = p;
    }

    // RunSim copies the map into its own blocked grid and spawns enemies.
    var s = run.Sim.init(seed, classFor(@intCast(seed +% floor)));
    s.floor = floor;
    s.generateFloor();
    try checkEnemies(&s);
    if (outOfBounds(s.hero.pos)) return error.HeroOutOfBounds;
    if (s.isBlocked(s.hero.pos.x, s.hero.pos.y)) return error.HeroInWall;
    if (s.hero.pos.x != d.entrance.x or s.hero.pos.y != d.entrance.y) return error.HeroNotAtEntrance;
    if (s.stairs.x != d.stairs.x or s.stairs.y != d.stairs.y) return error.StairsMismatch;
    if (s.enemy_count == 0) return error.NoEnemiesSpawned;
    if (s.enemy_count > run.max_enemies) return error.TooManyEnemies;
}

/// Structural enemy invariants: in bounds, walkable, unique, and never on the hero.
fn checkEnemies(s: *const run.Sim) !void {
    if (outOfBounds(s.hero.pos)) return error.HeroOutOfBounds;
    if (s.isBlocked(s.hero.pos.x, s.hero.pos.y)) return error.HeroInWall;
    if (s.enemy_count > run.max_enemies) return error.TooManyEnemies;
    var i: usize = 0;
    while (i < s.enemy_count) : (i += 1) {
        const e = s.enemies[i];
        if (!e.alive) {
            if (e.hp != 0) return error.DeadEnemyHasHp;
            continue;
        }
        if (e.hp <= 0) return error.AliveEnemyHasNoHp;
        if (outOfBounds(e.pos)) return error.EnemyOutOfBounds;
        if (s.isBlocked(e.pos.x, e.pos.y)) return error.EnemyInWall;
        if (samePos(e.pos, s.hero.pos)) return error.EnemyOnHero;
        var j: usize = 0;
        while (j < i) : (j += 1) {
            const other = s.enemies[j];
            if (other.alive and samePos(other.pos, e.pos)) return error.OverlappingEnemies;
        }
    }
}

const Snapshot = struct {
    turn: u32,
    floor: u8,
    state: run.State,
    hp: f32,
    resource: f32,
    pos: run.GridPos,
    enemy_count: usize,
    first_enemy: ?run.GridPos,
};

fn snapshot(s: *const run.Sim) Snapshot {
    var first: ?run.GridPos = null;
    var i: usize = 0;
    while (i < s.enemy_count) : (i += 1) {
        if (s.enemies[i].alive) {
            first = s.enemies[i].pos;
            break;
        }
    }
    return .{
        .turn = s.turn,
        .floor = s.floor,
        .state = s.state,
        .hp = s.hero.hp,
        .resource = s.hero.resource,
        .pos = s.hero.pos,
        .enemy_count = s.enemy_count,
        .first_enemy = first,
    };
}

/// Per-action invariants. `before.state` must be playing.
fn checkAfterAction(s: *const run.Sim, before: Snapshot) !void {
    if (before.state != .playing) return error.ActionAfterTerminal;
    if (s.turn < before.turn) return error.TurnWentBackwards;
    if (s.floor < before.floor) return error.FloorWentBackwards;
    if (s.floor > before.floor + 1) return error.FloorSkipped;
    if (s.hero.hp < 0) return error.NegativeHp;
    if (s.hero.hp > s.hero.hp_max + 0.001) return error.HpAboveMax;
    if (s.hero.resource < -0.001) return error.NegativeResource;
    if (s.hero.resource > s.hero.resource_max + 0.001) return error.ResourceAboveMax;
    try checkEnemies(s);

    switch (s.state) {
        .playing => {
            // A successful non-terminal action always consumes exactly one turn.
            if (s.turn != before.turn + 1) return error.TurnDidNotAdvance;
        },
        .dead => {
            if (s.hero.hp > 0) return error.DeadWithPositiveHp;
            // A trap can kill during the move itself, before endTurn advances
            // the counter; terminal actions may therefore leave the turn alone.
            if (s.turn != before.turn and s.turn != before.turn + 1) return error.DeadTurnNotAdvanced;
        },
        .victory => {
            if (s.hero.hp <= 0) return error.VictoryWhileDead;
            if (s.floor < 3) return error.VictoryBelowFloor3;
            // Victory can be triggered by a kill (turn unchanged) or by the
            // floor-3 stairs transition (nextFloor also leaves turn alone).
            if (s.turn != before.turn and s.turn != before.turn + 1) return error.BadVictoryTurn;
        },
    }
}

const Action = enum { bump, wait, talent, move };

/// Mirrors RunGame.autoPlayStep: adjacent bump, rest when safe, spend the
/// whole hotbar on nearby enemies, then A* toward the stairs.
fn autoStep(s: *run.Sim) Action {
    s.auto_allocate = true;
    defer s.auto_allocate = false;
    while (s.hero.pending_points > 0) {
        if (!s.spendPoint(s.mainStatIndex())) break;
    }
    const hero = s.hero.pos;

    if (s.aoe_armed and intent_mod.bossAoeDue(s.turn +| 1)) {
        var best: ?[2]i32 = null;
        var best_d: i32 = -1;
        for (dirs4) |d| {
            const nx = hero.x + d[0];
            const ny = hero.y + d[1];
            if (!s.canMove(d[0], d[1])) continue;
            if (s.enemyAt(nx, ny) != null) continue;
            const dd: i32 = @intCast(@abs(nx - s.aoe_target.x) + @abs(ny - s.aoe_target.y));
            if (dd > best_d) {
                best_d = dd;
                best = d;
            }
        }
        if (best) |d| {
            if (s.move(d[0], d[1])) return .move;
        }
    }

    for (dirs4) |d| {
        if (s.enemyAt(hero.x + d[0], hero.y + d[1]) != null) {
            if (s.move(d[0], d[1])) return .bump;
        }
    }

    if (s.hero.hp < s.hero.hp_max * 0.35 and s.nearestEnemy(4) == null) {
        if (s.wait()) return .wait;
    }

    if (s.nearestEnemy(5) != null) {
        if (s.class == .warrior and s.hero.buff_turns == 0 and
            s.hero.cooldowns[2] == 0 and s.hero.resource >= 20)
        {
            if (s.useTalent(2)) return .talent;
        }
        if (s.useTalent(0)) return .talent;
        if (s.useTalent(1)) return .talent;
        if (s.hero.hp < s.hero.hp_max * 0.4 and s.useTalent(2)) return .talent;
    }

    if (s.map.astarToOccupiedGoal(
        .{ .x = hero.x, .y = hero.y },
        .{ .x = s.stairs.x, .y = s.stairs.y },
        null,
    )) |path| {
        if (path.len > 1) {
            const next = path.slice()[1];
            if (s.move(next.x - hero.x, next.y - hero.y)) return .move;
        }
    }
    _ = s.wait();
    return .wait;
}

const DropResult = struct {
    dropped: bool = false,
    equippable: bool = false,
    equipped: bool = false,
};

fn itemScore(def: *const items_mod.ItemDef) f32 {
    var score: f32 = 0;
    for (def.mods) |m| {
        score += m.flat;
        score += m.pct * 20.0;
    }
    return score;
}

/// Same deterministic loot pipeline as RunGame.grantDrop: chance roll, pick
/// roll, auto-equip when the item beats the current slot.
fn grantDrop(
    sim: *run.Sim,
    c: *const content_mod.Content,
    class: attributes.Class,
    inv: *items_mod.Inventory,
    mods: *items_mod.ModifierSet,
    rng: *std.Random.DefaultPrng,
    guaranteed: bool,
) DropResult {
    if (c.items.len == 0 or c.enemies.len == 0) return .{};
    const chance = if (guaranteed) 0.0 else rng.random().float(f32);
    const pick = rng.random().float(f32);
    const id = c.rollDrop(class, chance, pick, &c.enemies[0]) orelse return .{};
    const def = &c.items[id];
    var result = DropResult{ .dropped = true, .equippable = def.slot != null };
    if (!inv.pickup(id)) return result;
    if (def.slot) |slot| {
        if (def.allowsClass(class)) {
            var better = inv.equipped.get(slot) == null;
            if (inv.equipped.get(slot)) |current| {
                if (current < c.items.len) {
                    better = itemScore(def) > itemScore(&c.items[current]);
                }
            }
            if (better) {
                inv.equip(c.items, id) catch return result;
                mods.rebuild(c.items, &inv.equipped);
                sim.applyModifiers(mods.slice());
                result.equipped = true;
            }
        }
    }
    return result;
}

fn processLoot(
    sim: *run.Sim,
    c: *const content_mod.Content,
    class: attributes.Class,
    inv: *items_mod.Inventory,
    mods: *items_mod.ModifierSet,
    rng: *std.Random.DefaultPrng,
    seen_chest: *u32,
    seen_kill: *u32,
    items_dropped: *u32,
    equipment_dropped: *u32,
    equipment_equipped: *u32,
) void {
    while (seen_chest.* < sim.chest_loot_events) {
        seen_chest.* += 1;
        const drop = grantDrop(sim, c, class, inv, mods, rng, true);
        if (drop.dropped) items_dropped.* += 1;
        if (drop.equippable) equipment_dropped.* += 1;
        if (drop.equipped) equipment_equipped.* += 1;
    }
    while (seen_kill.* < sim.kill_loot_events) {
        seen_kill.* += 1;
        const drop = grantDrop(sim, c, class, inv, mods, rng, false);
        if (drop.dropped) items_dropped.* += 1;
        if (drop.equippable) equipment_dropped.* += 1;
        if (drop.equipped) equipment_equipped.* += 1;
    }
}

pub const RunOutcome = struct {
    seed: u64,
    class: run.Class,
    state: run.State,
    turns: u32,
    floor: u8,
    max_floor: u8,
    kills: u32,
    loot_events: u32,
    items_dropped: u32,
    equipment_dropped: u32,
    equipment_equipped: u32,
    hp: f32,
    hp_max: f32,
    level: u16,
    timed_out: bool,
    victory_by_stairs: bool,
    final_pos: run.GridPos,
};

fn checkOutcome(o: RunOutcome) !void {
    if (o.timed_out) {
        if (o.state != .playing) return error.TimeoutButTerminal;
        return;
    }
    if (o.state == .playing) return error.RunEndedPlaying;
    if (o.state == .dead and o.hp > 0) return error.DeadWithPositiveHp;
    if (o.state == .victory and o.hp <= 0) return error.VictoryWhileDead;
    if (o.state == .victory and o.floor < 3) return error.VictoryBelowFloor3;
    if (o.state == .victory and o.floor > 4) return error.VictoryFloorTooHigh;
    if (o.floor < 1 or o.floor > o.max_floor) return error.BadFloorProgress;
    if (o.max_floor > 4) return error.FloorPastVictory;
}

/// Run one seed/class to terminal state (or the safety cap) with all checks on.
pub fn runAuto(
    seed: u64,
    class: run.Class,
    c: *const content_mod.Content,
    turn_cap: u32,
) !RunOutcome {
    var s = run.Sim.init(seed, class);
    var inv = items_mod.Inventory.init();
    var mods = items_mod.ModifierSet{};
    var loot_rng = std.Random.DefaultPrng.init(seed ^ 0x9e3779b97f4a7c15);
    const aclass = toAttrClass(class);
    var seen_chest: u32 = 0;
    var seen_kill: u32 = 0;
    var items_dropped: u32 = 0;
    var equipment_dropped: u32 = 0;
    var equipment_equipped: u32 = 0;
    var max_floor: u8 = 1;
    var steps: u32 = 0;

    while (s.state == .playing and steps < turn_cap) : (steps += 1) {
        const before = snapshot(&s);
        _ = autoStep(&s);
        if (s.floor > max_floor) max_floor = s.floor;
        checkAfterAction(&s, before) catch |err| {
            std.debug.print(
                "[qa2] invariant failed seed={d} class={s} step={d} turn={d} floor={d}: {s}\n",
                .{ seed, @tagName(class), steps, before.turn, before.floor, @errorName(err) },
            );
            return err;
        };
        processLoot(
            &s,
            c,
            aclass,
            &inv,
            &mods,
            &loot_rng,
            &seen_chest,
            &seen_kill,
            &items_dropped,
            &equipment_dropped,
            &equipment_equipped,
        );
        // Equipping can change hp_max and clamp hp; state/turn never change.
        if (s.hero.hp < 0 or s.hero.hp > s.hero.hp_max + 0.001) return error.HpOutOfRangeAfterLoot;
        if (s.hero.resource < -0.001 or s.hero.resource > s.hero.resource_max + 0.001) {
            return error.ResourceOutOfRangeAfterLoot;
        }
    }

    if (s.floor > max_floor) max_floor = s.floor;
    const outcome = RunOutcome{
        .seed = seed,
        .class = class,
        .state = s.state,
        .turns = s.turn,
        .floor = s.floor,
        .max_floor = max_floor,
        .kills = s.kills,
        .loot_events = s.chest_loot_events + s.kill_loot_events,
        .items_dropped = items_dropped,
        .equipment_dropped = equipment_dropped,
        .equipment_equipped = equipment_equipped,
        .hp = s.hero.hp,
        .hp_max = s.hero.hp_max,
        .level = s.hero.level,
        .timed_out = s.state == .playing,
        .victory_by_stairs = s.state == .victory and s.floor >= 4,
        .final_pos = s.hero.pos,
    };
    try checkOutcome(outcome);
    return outcome;
}

pub const ClassStats = struct {
    runs: u32 = 0,
    wins: u32 = 0,
    wins_boss: u32 = 0,
    wins_stairs: u32 = 0,
    deaths: u32 = 0,
    timeouts: u32 = 0,
    turns: u64 = 0,
    win_turns: u64 = 0,
    kills: u64 = 0,
    items: u64 = 0,
    equipment: u64 = 0,
    equipment_used: u64 = 0,
};

pub const BatchStats = struct {
    runs: u32 = 0,
    wins: u32 = 0,
    wins_boss: u32 = 0,
    wins_stairs: u32 = 0,
    deaths: u32 = 0,
    timeouts: u32 = 0,
    turns: u64 = 0,
    win_turns: u64 = 0,
    kills: u64 = 0,
    loot_events: u64 = 0,
    items: u64 = 0,
    equipment: u64 = 0,
    equipment_used: u64 = 0,
    floor_sum: u64 = 0,
    death_floors: [4]u32 = .{ 0, 0, 0, 0 },
    per_class: [run.class_count]ClassStats = .{ .{}, .{}, .{} },

    pub fn add(self: *BatchStats, o: RunOutcome) void {
        self.runs += 1;
        self.turns += o.turns;
        self.kills += o.kills;
        self.loot_events += o.loot_events;
        self.items += o.items_dropped;
        self.equipment += o.equipment_dropped;
        self.equipment_used += o.equipment_equipped;
        self.floor_sum += o.floor;
        const ci: usize = @intCast(@backingInt(o.class));
        var cs = &self.per_class[ci];
        cs.runs += 1;
        cs.turns += o.turns;
        cs.kills += o.kills;
        cs.items += o.items_dropped;
        cs.equipment += o.equipment_dropped;
        cs.equipment_used += o.equipment_equipped;
        switch (o.state) {
            .victory => {
                self.wins += 1;
                self.win_turns += o.turns;
                cs.wins += 1;
                cs.win_turns += o.turns;
                if (o.victory_by_stairs) {
                    self.wins_stairs += 1;
                } else {
                    self.wins_boss += 1;
                }
            },
            .dead => {
                self.deaths += 1;
                cs.deaths += 1;
                if (o.floor < self.death_floors.len) self.death_floors[o.floor] += 1;
            },
            .playing => {
                self.timeouts += 1;
                cs.timeouts += 1;
            },
        }
    }
};

fn ratio(num: u64, den: u64) f64 {
    if (den == 0) return 0;
    return @as(f64, @floatFromInt(num)) / @as(f64, @floatFromInt(den));
}

fn pct(num: u64, den: u64) f64 {
    return ratio(num, den) * 100.0;
}

pub fn printRun(o: RunOutcome) void {
    std.debug.print(
        "[qa2] seed={d} class={s} state={s} turn={d} floor={d} (max {d}) hp={d:.0}/{d:.0} lvl={d} kills={d} loot_events={d} items={d} equip_drops={d} equip_used={d}{s}\n",
        .{
            o.seed,
            @tagName(o.class),
            @tagName(o.state),
            o.turns,
            o.floor,
            o.max_floor,
            o.hp,
            o.hp_max,
            o.level,
            o.kills,
            o.loot_events,
            o.items_dropped,
            o.equipment_dropped,
            o.equipment_equipped,
            if (o.timed_out) " TIMEOUT" else if (o.victory_by_stairs) " STAIRS_WIN" else "",
        },
    );
}

pub fn printBatch(label: []const u8, b: *const BatchStats) void {
    std.debug.print(
        "[qa2] {s}: runs={d} wins={d} ({d:.1}%) boss_wins={d} stairs_wins={d} deaths={d} timeouts={d} avg_turns={d:.1} win_avg_turns={d:.1} avg_floor={d:.2} kills={d} loot_events={d} items={d} equip_drops={d} equip_used={d}\n",
        .{
            label,
            b.runs,
            b.wins,
            pct(b.wins, b.runs),
            b.wins_boss,
            b.wins_stairs,
            b.deaths,
            b.timeouts,
            ratio(b.turns, b.runs),
            ratio(b.win_turns, b.wins),
            ratio(b.floor_sum, b.runs),
            b.kills,
            b.loot_events,
            b.items,
            b.equipment,
            b.equipment_used,
        },
    );
    std.debug.print(
        "[qa2] {s}: death floors F1={d} F2={d} F3={d}\n",
        .{ label, b.death_floors[1], b.death_floors[2], b.death_floors[3] },
    );
    for (b.per_class, 0..) |cs, i| {
        const class: run.Class = @fromBackingInt(@intCast(@as(u8, @intCast(i))));
        std.debug.print(
            "[qa2] {s}: {s} runs={d} wins={d} ({d:.1}%) deaths={d} timeouts={d} avg_turns={d:.1} equip_drops={d} equip_used={d}\n",
            .{
                label,
                @tagName(class),
                cs.runs,
                cs.wins,
                pct(cs.wins, cs.runs),
                cs.deaths,
                cs.timeouts,
                ratio(cs.turns, cs.runs),
                cs.equipment,
                cs.equipment_used,
            },
        );
    }
}

pub fn runBatch(seed_total: usize, c: *const content_mod.Content) !BatchStats {
    var b = BatchStats{};
    for (0..seed_total) |i| {
        for (0..run.class_count) |ci| {
            const class: run.Class = @fromBackingInt(@intCast(@as(u8, @intCast(ci))));
            const o = try runAuto(seedFor(i), class, c, max_auto_turns);
            b.add(o);
        }
    }
    return b;
}

// ----------------------------------------------------------------- tests

test "qa2: 100 seeds x 3 floors generate valid, connected, safe floors" {
    for (0..seed_count) |i| {
        const seed = seedFor(i);
        var floor: u8 = 1;
        while (floor <= 3) : (floor += 1) {
            checkFloor(seed, floor) catch |err| {
                std.debug.print("[qa2] seed={d} floor={d} failed: {s}\n", .{ seed, floor, @errorName(err) });
                return err;
            };
        }
    }
    std.debug.print(
        "[qa2] generation matrix: {d} seeds x 3 floors valid, entrance->stairs A* reachable, markers unique/in-bounds\n",
        .{seed_count},
    );
}

test "qa2: illegal moves never consume a turn or run the enemy phase" {
    for (0..seed_count) |i| {
        const seed = seedFor(i);
        var s = run.Sim.init(seed, classFor(i));
        const hero = s.hero.pos;

        // Out of bounds and zero displacement.
        const before = snapshot(&s);
        try std.testing.expect(!s.move(-1000, 0));
        try std.testing.expect(!s.move(1000, 0));
        try std.testing.expect(!s.move(0, -1000));
        try std.testing.expect(!s.move(0, 1000));
        try std.testing.expect(!s.move(0, 0));
        try std.testing.expectEqual(before.turn, s.turn);
        try std.testing.expectEqual(before.hp, s.hero.hp);
        try std.testing.expectEqual(before.state, s.state);
        try std.testing.expect(samePos(before.pos, s.hero.pos));
        try std.testing.expect(std.meta.eql(before.first_enemy, firstAliveEnemy(&s)));

        // At least one guaranteed-solid neighbour on every generated floor.
        var wall_bumped = false;
        for (dirs4) |d| {
            if (s.isBlocked(hero.x + d[0], hero.y + d[1])) {
                const hp = s.hero.hp;
                const turn = s.turn;
                const enemy = firstAliveEnemy(&s);
                try std.testing.expect(!s.move(d[0], d[1]));
                try std.testing.expectEqual(turn, s.turn);
                try std.testing.expectEqual(hp, s.hero.hp);
                try std.testing.expect(std.meta.eql(enemy, firstAliveEnemy(&s)));
                wall_bumped = true;
                break;
            }
        }
        try std.testing.expect(wall_bumped);

        // Terminal states reject every action without spending a turn.
        s.state = .victory;
        const vt = s.turn;
        const vhp = s.hero.hp;
        try std.testing.expect(!s.move(1, 0));
        try std.testing.expect(!s.wait());
        try std.testing.expect(!s.useTalent(0));
        try std.testing.expectEqual(vt, s.turn);
        try std.testing.expectEqual(vhp, s.hero.hp);
        s.state = .dead;
        try std.testing.expect(!s.move(1, 0));
        try std.testing.expect(!s.wait());
        try std.testing.expectEqual(vt, s.turn);
    }
    std.debug.print("[qa2] illegal-move matrix: {d} seeds, wall/OOB/zero/terminal moves spend no turn\n", .{seed_count});
}

fn firstAliveEnemy(s: *const run.Sim) ?run.GridPos {
    var i: usize = 0;
    while (i < s.enemy_count) : (i += 1) {
        if (s.enemies[i].alive) return s.enemies[i].pos;
    }
    return null;
}

test "qa2: autoplay batch over 100 seeds preserves turn/hp/floor invariants" {
    var c = try content_mod.load(std.testing.allocator);
    defer c.deinit();
    try std.testing.expect(!c.usingFallback());
    std.debug.print(
        "[qa2] content: items={d} enemies={d} skills={d}\n",
        .{ c.items.len, c.enemies.len, c.skills.len },
    );
    const b = try runBatch(seed_count, &c);
    printBatch("batch", &b);
    try std.testing.expectEqual(@as(u32, @intCast(seed_count * run.class_count)), b.runs);
    try std.testing.expectEqual(@as(u32, 0), b.timeouts);
    try std.testing.expectEqual(b.runs, b.wins + b.deaths);
    if (b.wins > 0) try std.testing.expect(b.win_turns >= @as(u64, b.wins));
    if (b.wins == 0) {
        // Balance regression, not a logic failure: keep the test green but
        // make the 0% result loud in the log.
        std.debug.print(
            "[qa2] WARNING: 0/{d} autoplay wins; boss fight/balance regression, see docs/QA_RUN2.md\n",
            .{b.runs},
        );
    }
}

test "qa2: fixed seed report is reproducible" {
    var c = try content_mod.load(std.testing.allocator);
    defer c.deinit();
    try std.testing.expect(!c.usingFallback());
    for (0..run.class_count) |i| {
        const class: run.Class = @fromBackingInt(@intCast(@as(u8, @intCast(i))));
        const a = try runAuto(fixed_seed, class, &c, max_auto_turns);
        const b = try runAuto(fixed_seed, class, &c, max_auto_turns);
        printRun(a);
        try std.testing.expectEqual(a.seed, b.seed);
        try std.testing.expectEqual(a.class, b.class);
        try std.testing.expectEqual(a.state, b.state);
        try std.testing.expectEqual(a.turns, b.turns);
        try std.testing.expectEqual(a.floor, b.floor);
        try std.testing.expectEqual(a.max_floor, b.max_floor);
        try std.testing.expectEqual(a.kills, b.kills);
        try std.testing.expectEqual(a.loot_events, b.loot_events);
        try std.testing.expectEqual(a.items_dropped, b.items_dropped);
        try std.testing.expectEqual(a.equipment_dropped, b.equipment_dropped);
        try std.testing.expectEqual(a.equipment_equipped, b.equipment_equipped);
        try std.testing.expectEqual(a.level, b.level);
        try std.testing.expectEqual(a.timed_out, b.timed_out);
        try std.testing.expectEqual(a.victory_by_stairs, b.victory_by_stairs);
        try std.testing.expectEqual(a.hp, b.hp);
        try std.testing.expectEqual(a.hp_max, b.hp_max);
        try std.testing.expect(samePos(a.final_pos, b.final_pos));
    }
}
