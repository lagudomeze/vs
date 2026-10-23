//! QA3: game-level probes for aim, save/load, help and combat mechanics.
//! Test/tooling only; it does not change game behavior.
//!
//! Run with zig build test-qa3. The suite prints [qa3] lines for the report
//! (including known P1 findings) and asserts the invariants that the game
//! does satisfy.
const std = @import("std");
const run = @import("../game/run_sim.zig");
const RunGame = @import("../game/run_game.zig").RunGame;
const save_mod = @import("../game/save.zig");
const gear_save = @import("../game/gear_save.zig");

const dt = 1.0 / 60.0;
const dirs4 = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };

fn setEnemy(g: *RunGame, x: i32, y: i32, name: []const u8, hp: f32, speed: u16) usize {
    const idx = g.sim.enemy_count;
    g.sim.enemies[idx] = run.enemyFromParts(.{
        .kind = 0,
        .name = name,
        .pos = .{ .x = x, .y = y },
        .hp = hp,
        .hp_max = hp,
        .attack = 8,
        .armor = 4,
        .speed = speed,
        .range = 1,
        .xp = 20,
    });
    g.sim.enemy_count += 1;
    return idx;
}

fn digestSim(gpa: std.mem.Allocator, g: *const RunGame) ![]u8 {
    var copy = g.sim;
    copy.log_head = 0;
    copy.log_total = 0;
    return save_mod.saveAlloc(gpa, &copy);
}

fn sameDigest(gpa: std.mem.Allocator, a: *const RunGame, b: *const RunGame) !bool {
    const ab = try digestSim(gpa, a);
    defer gpa.free(ab);
    const bb = try digestSim(gpa, b);
    defer gpa.free(bb);
    return std.mem.eql(u8, ab, bb);
}

fn gearBytes(gpa: std.mem.Allocator, g: *const RunGame) ![]u8 {
    return gear_save.toAlloc(gpa, &g.inventory);
}

fn resetAimBoard(g: *RunGame) void {
    g.sim.hero.pos = .{ .x = 6, .y = 6 };
    g.sim.hero.last_pos = .{ .x = 6, .y = 6 };
    g.sim.hero.vitals.hp = g.sim.hero.vitals.hp_max;
    g.sim.hero.resource.current = g.sim.hero.resource.max;
    g.sim.hero.resource.per_turn = 0;
    g.sim.turn = 1;
    g.sim.state = .playing;
    g.sim.enemy_count = 0;
    g.sim.enemies = @splat(.{});
    g.sim.aoe_armed = false;
    g.sim.blocked = @splat(false);
}

const Approach = struct {
    hero: run.GridPos,
    step_x: i32,
    step_y: i32,
    chest: run.GridPos,
};

fn chestApproach(g: *const RunGame) ?Approach {
    for (g.sim.chests, g.sim.chest_alive) |c, alive| {
        if (!alive) continue;
        for (dirs4) |d| {
            const px = c.x + d[0];
            const py = c.y + d[1];
            if (g.sim.isBlocked(px, py)) continue;
            if (g.sim.enemyAt(px, py) != null) continue;
            return .{
                .hero = .{ .x = px, .y = py },
                .step_x = -d[0],
                .step_y = -d[1],
                .chest = c,
            };
        }
    }
    return null;
}

fn openChestScenario(g: *RunGame) bool {
    const a = chestApproach(g) orelse return false;
    g.sim.enemy_count = 0;
    g.sim.enemies = @splat(.{});
    g.sim.hero.pos = a.hero;
    g.sim.hero.last_pos = a.hero;
    g.sim.turn = 1;
    g.sim.state = .playing;
    g.sim.aoe_armed = false;
    g.sim.chest_loot_events = 0;
    g.sim.kill_loot_events = 0;
    g.chest_loot_seen = 0;
    g.kill_loot_seen = 0;
    return true;
}

fn makeTmpPath(alloc: std.mem.Allocator, tmp: *std.testing.TmpDir, name: []const u8) ![]u8 {
    return std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], name });
}

// ---------------------------------------------------------------- aiming

test "qa3: aim entry and cancel spend nothing" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    resetAimBoard(g);
    _ = setEnemy(g, 6, 5, "骷髅兵", 70, 70);

    const turn = g.sim.turn;
    const res = g.sim.hero.resource.current;
    g.update(.{ .talent = 0 }, dt);
    try std.testing.expect(g.isAiming());
    try std.testing.expect(g.hud_state.aim.active);
    try std.testing.expect(g.hud_state.aim.valid);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource.current);
    try std.testing.expectEqual(@as(u16, 0), g.sim.hero.talents.cooldowns[0]);

    try std.testing.expect(g.cancelAim());
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource.current);
    try std.testing.expect(!g.cancelAim());
    try std.testing.expectEqual(run.State.playing, g.sim.state);
    std.debug.print("[qa3] aim entry/cancel: turn and resource unchanged (t={d}, r={d:.0})\n", .{ turn, res });
}

test "qa3: valid aim confirms once, one turn and one resource payment" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    resetAimBoard(g);
    _ = setEnemy(g, 6, 5, "骷髅兵", 70, 70);

    const turn = g.sim.turn;
    const res = g.sim.hero.resource.current;
    g.update(.{ .talent = 0 }, dt);
    g.update(.{ .confirm = true }, dt);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn + 1, g.sim.turn);
    try std.testing.expectEqual(res - 25.0, g.sim.hero.resource.current);
    try std.testing.expectEqual(@as(u16, 3), g.sim.hero.talents.cooldowns[0]); // 4 set, endTurn ticks once
    try std.testing.expect(g.sim.enemies[0].vitals.hp < 70);
    std.debug.print("[qa3] valid confirm: turn {d}->{d}, resource {d:.0}->{d:.0}, cooldown={d}\n", .{
        turn, g.sim.turn, res, g.sim.hero.resource.current, g.sim.hero.talents.cooldowns[0],
    });
}

test "qa3: same key currently confirms (spec text says cancel)" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    resetAimBoard(g);
    _ = setEnemy(g, 6, 5, "骷髅兵", 70, 70);
    const turn = g.sim.turn;
    const res = g.sim.hero.resource.current;
    g.update(.{ .talent = 0 }, dt);
    g.update(.{ .talent = 0 }, dt);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn + 1, g.sim.turn);
    try std.testing.expectEqual(res - 25.0, g.sim.hero.resource.current);
    std.debug.print("[qa3] FINDING P1: same-key aim release = confirm (turn+1, res-25), not cancel; README documents confirm, acceptance text asks cancel\n", .{});
}

test "qa3: range/LOS confirm stays; missing resource refuses aim" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();

    // Out of range.
    resetAimBoard(g);
    _ = setEnemy(g, 6, 0, "骷髅兵", 70, 70);
    g.update(.{ .talent = 0 }, dt);
    try std.testing.expect(!g.hud_state.aim.valid);
    try std.testing.expectEqualStrings("超出范围", g.hud_state.aim.reason);
    var turn = g.sim.turn;
    var res = g.sim.hero.resource.current;
    g.update(.{ .confirm = true }, dt);
    try std.testing.expect(g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource.current);
    _ = g.cancelAim();

    // No line of sight: wall between hero (6,6) and target (6,4).
    resetAimBoard(g);
    _ = setEnemy(g, 6, 4, "骷髅兵", 70, 70);
    g.sim.blocked[5 * run.grid_w + 6] = true;
    g.update(.{ .talent = 1 }, dt);
    try std.testing.expect(!g.hud_state.aim.valid);
    try std.testing.expectEqualStrings("视线受阻", g.hud_state.aim.reason);
    turn = g.sim.turn;
    res = g.sim.hero.resource.current;
    g.update(.{ .confirm = true }, dt);
    try std.testing.expect(g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource.current);
    _ = g.cancelAim();

    // No resource: refuse to enter aim at all.
    resetAimBoard(g);
    _ = setEnemy(g, 6, 5, "骷髅兵", 70, 70);
    g.sim.hero.resource.current = 0;
    g.update(.{ .talent = 0 }, dt);
    try std.testing.expect(!g.isAiming());
    turn = g.sim.turn;
    res = g.sim.hero.resource.current;
    g.update(.{ .talent = 0 }, dt);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource.current);
    std.debug.print("[qa3] range/LOS confirms stay in aim; missing resource refuses aim, 0 turn/resource\n", .{});
}

test "qa3: wait key while aiming cancels and waits" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    resetAimBoard(g);
    _ = setEnemy(g, 6, 5, "骷髅兵", 70, 70);
    const turn = g.sim.turn;
    const res = g.sim.hero.resource.current;
    g.update(.{ .talent = 0 }, dt);
    g.update(.{ .wait = true }, dt); // 5 / . cancels aim and waits
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn + 1, g.sim.turn);
    try std.testing.expect(g.sim.hero.resource.current >= res);
    std.debug.print("[qa3] 5/. while aiming: aim cancelled, wait consumed one turn, no talent cost\n", .{});
}

test "qa3: tab cycles aim target without a turn" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    resetAimBoard(g);
    _ = setEnemy(g, 5, 6, "骷髅兵", 70, 70);
    _ = setEnemy(g, 7, 6, "幽魂", 55, 70);
    g.update(.{ .talent = 0 }, dt);
    try std.testing.expect(g.isAiming());
    const turn = g.sim.turn;
    try std.testing.expectEqualStrings("骷髅兵", g.hud_state.aim.target);
    g.update(.{ .target_next = true }, dt);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqualStrings("幽魂", g.hud_state.aim.target);
    std.debug.print("[qa3] Tab: 骷髅兵 -> 幽魂 at turn {d} (no turn spent)\n", .{turn});
}

test "qa3: self talents fire immediately without entering aim" {
    const gpa = std.testing.allocator;

    const w = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer w.destroy();
    resetAimBoard(w);
    const wt = w.sim.turn;
    w.update(.{ .talent = 2 }, dt);
    try std.testing.expect(!w.isAiming());
    try std.testing.expectEqual(wt + 1, w.sim.turn);
    try std.testing.expect(w.sim.hero.status.buff_turns > 0);

    const m = try RunGame.create(gpa, 640, 360, .mage, 12345);
    defer m.destroy();
    resetAimBoard(m);
    const mt = m.sim.turn;
    m.update(.{ .talent = 2 }, dt);
    // Blink is immediate even if this particular seed finds no free cell; the
    // key invariant is that it never enters aim mode.
    try std.testing.expect(!m.isAiming());
    try std.testing.expect(m.sim.turn == mt or m.sim.turn == mt + 1);

    const c = try RunGame.create(gpa, 640, 360, .chronomancer, 12345);
    defer c.destroy();
    resetAimBoard(c);
    c.sim.hero.last_pos = .{ .x = 6, .y = 5 };
    const ct = c.sim.turn;
    c.update(.{ .talent = 2 }, dt);
    try std.testing.expect(!c.isAiming());
    try std.testing.expectEqual(ct + 1, c.sim.turn);
    try std.testing.expectEqual(@as(i32, 6), c.sim.hero.pos.x);
    try std.testing.expectEqual(@as(i32, 5), c.sim.hero.pos.y);
    std.debug.print("[qa3] self talents: war cry/blink/rewind never enter aim (turn +1 when cast)\n", .{});
}

test "qa3: autoPlayStep never leaves the bot aiming" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    resetAimBoard(g);
    _ = setEnemy(g, 6, 5, "骷髅兵", 70, 70);
    g.update(.{ .talent = 0 }, dt);
    try std.testing.expect(g.isAiming());
    var i: usize = 0;
    while (i < 120 and g.sim.state == .playing) : (i += 1) {
        g.autoPlayStep();
        try std.testing.expect(!g.isAiming());
    }
    std.debug.print("[qa3] --auto/autoPlayStep: {d} steps, aim cleared every step, final turn={d}\n", .{ i, g.sim.turn });
}

// ---------------------------------------------------------------- save/load

test "qa3: save/load preserves state and gear" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const sim_path = try makeTmpPath(alloc, &tmp, "round-run.json");
    defer alloc.free(sim_path);
    const gear_path = try makeTmpPath(alloc, &tmp, "round-gear.json");
    defer alloc.free(gear_path);

    const g1 = try RunGame.create(alloc, 640, 360, .warrior, 12345);
    defer g1.destroy();
    var steps: usize = 0;
    while (steps < 80 and g1.sim.turn < 25 and g1.sim.state == .playing) : (steps += 1) g1.autoPlayStep();
    g1.saveRun(io, sim_path, gear_path);

    const g2 = try RunGame.create(alloc, 640, 360, .warrior, 12345);
    defer g2.destroy();
    g2.loadRun(io, sim_path, gear_path);

    try std.testing.expect(try sameDigest(alloc, g1, g2));
    const ga = try gearBytes(alloc, g1);
    defer alloc.free(ga);
    const gb = try gearBytes(alloc, g2);
    defer alloc.free(gb);
    try std.testing.expectEqualStrings(ga, gb);

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        g1.autoPlayStep();
        g2.autoPlayStep();
        try std.testing.expect(try sameDigest(alloc, g1, g2));
    }
    std.debug.print("[qa3] save/load: state+gear equal after load; 20 further turns equal (turn={d}, floor={d}, inv={d})\n", .{
        g1.sim.turn, g1.sim.floor, g1.inventory.len,
    });
}

test "qa3: loot rng survives save/load" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const sim_path = try makeTmpPath(alloc, &tmp, "loot-run.json");
    defer alloc.free(sim_path);
    const gear_path = try makeTmpPath(alloc, &tmp, "loot-gear.json");
    defer alloc.free(gear_path);

    const g1 = try RunGame.create(alloc, 640, 360, .warrior, 12345);
    defer g1.destroy();
    try std.testing.expect(openChestScenario(g1));
    const a = chestApproach(g1).?;
    g1.saveRun(io, sim_path, gear_path);

    const g2 = try RunGame.create(alloc, 640, 360, .warrior, 12345);
    defer g2.destroy();
    g2.loadRun(io, sim_path, gear_path);

    try std.testing.expect(std.meta.eql(g1.loot_rng.s, g2.loot_rng.s));
    g1.update(.{ .step_x = a.step_x, .step_y = a.step_y }, dt);
    g2.update(.{ .step_x = a.step_x, .step_y = a.step_y }, dt);
    const ga = try gearBytes(alloc, g1);
    defer alloc.free(ga);
    const gb = try gearBytes(alloc, g2);
    defer alloc.free(gb);
    try std.testing.expectEqual(g1.sim.turn, g2.sim.turn);
    try std.testing.expectEqualStrings(ga, gb);
    std.debug.print("[qa3] loot_rng restored; same chest -> identical gear\n", .{});
}

test "qa3: corrupt save and missing gear leave the current run alone" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const sim_path = try makeTmpPath(alloc, &tmp, "bad-run.json");
    defer alloc.free(sim_path);
    const gear_path = try makeTmpPath(alloc, &tmp, "bad-gear.json");
    defer alloc.free(gear_path);

    const g = try RunGame.create(alloc, 640, 360, .warrior, 12345);
    defer g.destroy();
    _ = g.sim.wait();
    try std.testing.expect(g.inventory.pickup(0));
    g.saveRun(io, sim_path, gear_path);

    const state_before = try digestSim(alloc, g);
    defer alloc.free(state_before);
    const gear_before = try gearBytes(alloc, g);
    defer alloc.free(gear_before);
    // Corrupt the sim half; current run and the corrupt file must stay.
    const bad = "{\"format\":\"vx-run-save\",\"version\":1,";
    try tmp.dir.writeFile(io, .{ .sub_path = "bad-run.json", .data = bad });
    g.loadRun(io, sim_path, gear_path);
    const after_bad = try digestSim(alloc, g);
    defer alloc.free(after_bad);
    try std.testing.expectEqualStrings(state_before, after_bad);
    const still_bad = try tmp.dir.readFileAlloc(io, "bad-run.json", alloc, .limited(1024));
    defer alloc.free(still_bad);
    try std.testing.expectEqualStrings(bad, still_bad);

    // Restore a valid sim, corrupt only the gear half with malformed JSON.
    g.saveRun(io, sim_path, gear_path);
    const state2 = try digestSim(alloc, g);
    defer alloc.free(state2);
    try tmp.dir.writeFile(io, .{ .sub_path = "bad-gear.json", .data = "not-json" });
    g.loadRun(io, sim_path, gear_path);
    const after_gear = try digestSim(alloc, g);
    defer alloc.free(after_gear);
    try std.testing.expectEqualStrings(state2, after_gear);
    const gear_after = try gearBytes(alloc, g);
    defer alloc.free(gear_after);
    try std.testing.expectEqualStrings(gear_before, gear_after);

    // Missing gear -> empty bag; sim loads.
    const missing_path = try makeTmpPath(alloc, &tmp, "missing-gear.json");
    defer alloc.free(missing_path);
    try save_mod.saveFile(io, alloc, sim_path, &g.sim);
    g.loadRun(io, sim_path, missing_path);
    try std.testing.expectEqual(@as(usize, 0), g.inventory.len);
    std.debug.print("[qa3] corrupt sim/gear: current run untouched; missing gear: loaded with empty bag\n", .{});
}

test "qa3: empty gear object is rejected without clearing the bag" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const sim_path = try makeTmpPath(alloc, &tmp, "empty-gear-run.json");
    defer alloc.free(sim_path);
    const gear_path = try makeTmpPath(alloc, &tmp, "empty-gear.json");
    defer alloc.free(gear_path);

    const g = try RunGame.create(alloc, 640, 360, .warrior, 12345);
    defer g.destroy();
    try std.testing.expect(g.inventory.pickup(0));
    g.saveRun(io, sim_path, gear_path);
    const turn = g.sim.turn;

    // A bare {} must be rejected as a corrupt/partial sidecar, not treated as
    // "empty bag"; the current run and its inventory stay untouched.
    try tmp.dir.writeFile(io, .{ .sub_path = "empty-gear.json", .data = "{}" });
    g.loadRun(io, sim_path, gear_path);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(@as(usize, 1), g.inventory.len);
    std.debug.print("[qa3] empty gear object rejected; bag retained (len={d})\n", .{g.inventory.len});
}

// ---------------------------------------------------------------- mechanics

fn setupFighter(s: *run.Sim, speed: u16) void {
    s.turn = 1;
    s.hero.combat.armor = 0;
    s.hero.vitals.hp = s.hero.vitals.hp_max;
    s.enemy_count = 1;
    s.enemies[0] = run.enemyFromParts(.{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 999,
        .hp_max = 999,
        .attack = 10,
        .armor = 0,
        .speed = speed,
        .range = 1,
        .xp = 0,
    });
}

test "qa3: energy ramps 150 to double actions and 70 starts slow" {
    var fast = run.Sim.init(41, .warrior);
    setupFighter(&fast, 150);
    const f0 = fast.hero.vitals.hp;
    _ = fast.wait();
    const a1 = f0 - fast.hero.vitals.hp;
    const f1 = fast.hero.vitals.hp;
    _ = fast.wait();
    const a2 = f1 - fast.hero.vitals.hp;
    try std.testing.expect(a1 > 0);
    try std.testing.expectApproxEqAbs(a1 * 2.0, a2, 0.01);

    var slow = run.Sim.init(43, .warrior);
    setupFighter(&slow, 70);
    const s0 = slow.hero.vitals.hp;
    _ = slow.wait();
    try std.testing.expectEqual(s0, slow.hero.vitals.hp); // 70 < 100: no action
    _ = slow.wait();
    try std.testing.expect(slow.hero.vitals.hp < s0); // banked 140: one action
    std.debug.print("[qa3] energy: 150 dealt {d:.2}/{d:.2} over two turns, 70 waited then hit\n", .{ a1, a2 });
}

test "qa3: boss AOE 0.9 spares adjacent cell and hits marked cell" {
    var s = run.Sim.init(47, .warrior);
    s.turn = 2;
    s.hero.pos = .{ .x = 6, .y = 6 };
    s.hero.combat.armor = 0;
    s.hero.vitals.hp = s.hero.vitals.hp_max;
    s.aoe_armed = true;
    s.aoe_target = .{ .x = 7, .y = 6 };
    s.enemy_count = 1;
    s.enemies[0] = run.enemyFromParts(.{
        .kind = 5,
        .name = "深渊守卫",
        .pos = .{ .x = 0, .y = 0 },
        .hp = 420,
        .hp_max = 420,
        .attack = 16,
        .armor = 15,
        .speed = 90,
        .range = 1,
        .xp = 200,
        .energy = 100,
    });
    const hp = s.hero.vitals.hp;
    _ = s.wait();
    try std.testing.expectEqual(hp, s.hero.vitals.hp); // 1 cell away > 0.9

    var h = run.Sim.init(49, .warrior);
    h.turn = 2;
    h.hero.pos = .{ .x = 6, .y = 6 };
    h.hero.combat.armor = 0;
    h.hero.vitals.hp = h.hero.vitals.hp_max;
    h.aoe_armed = true;
    h.aoe_target = h.hero.pos;
    h.enemy_count = 1;
    h.enemies[0] = run.enemyFromParts(.{
        .kind = 5,
        .name = "深渊守卫",
        .pos = .{ .x = 0, .y = 0 },
        .hp = 420,
        .hp_max = 420,
        .attack = 16,
        .armor = 15,
        .speed = 90,
        .range = 1,
        .xp = 200,
        .energy = 100,
    });
    const hp2 = h.hero.vitals.hp;
    _ = h.wait();
    try std.testing.expect(h.hero.vitals.hp < hp2);
    std.debug.print("[qa3] boss AOE 0.9: adjacent cell safe, marked cell {d:.0} damage\n", .{hp2 - h.hero.vitals.hp});
}

test "qa3: boss seals floor-3 stairs without spending a turn" {
    var s = run.Sim.init(53, .warrior);
    s.floor = 3;
    s.turn = 1;
    var from: ?run.GridPos = null;
    for (dirs4) |d| {
        const p = run.GridPos{ .x = s.stairs.x + d[0], .y = s.stairs.y + d[1] };
        if (s.map.isWalkable(.{ .x = p.x, .y = p.y })) {
            from = p;
            break;
        }
    }
    const start = from orelse return error.SkipZigTest;
    s.hero.pos = start;
    s.hero.last_pos = start;
    s.enemy_count = 1;
    s.enemies[0] = run.enemyFromParts(.{
        .kind = 5,
        .name = "深渊守卫",
        .pos = .{ .x = 0, .y = 0 },
        .hp = 420,
        .hp_max = 420,
        .attack = 16,
        .armor = 15,
        .speed = 90,
        .range = 1,
        .xp = 200,
    });
    const turn = s.turn;
    const res = s.hero.resource.current;
    try std.testing.expect(!s.move(s.stairs.x - start.x, s.stairs.y - start.y));
    try std.testing.expectEqual(@as(u8, 3), s.floor);
    try std.testing.expectEqual(turn, s.turn);
    try std.testing.expectEqual(res, s.hero.resource.current);
    s.enemies[0].vitals.alive = false;
    try std.testing.expect(s.move(s.stairs.x - start.x, s.stairs.y - start.y));
    std.debug.print("[qa3] stairs seal: blocked at floor 3, 0 turn/resource, opens after boss death\n", .{});
}

// ---------------------------------------------------------------- help

test "qa3: H toggles help and freezes turns" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    resetAimBoard(g);
    const turn = g.sim.turn;
    g.update(.{ .help = true }, dt);
    try std.testing.expect(g.show_help);
    try std.testing.expectEqual(turn, g.sim.turn);
    g.update(.{ .talent = 0 }, dt); // swallowed while help is open
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    g.update(.{ .help = true }, dt);
    try std.testing.expect(!g.show_help);
    try std.testing.expectEqual(turn, g.sim.turn);
    std.debug.print("[qa3] H help: on/off, turn frozen at {d}, hotkeys swallowed while open\n", .{turn});
}
