//! ToME4-style single-hero turn-based 3D pixel roguelike.
//! Owns the pure simulation (tome_sim), renders the 13x13 dungeon and HUD.
const std = @import("std");
const math = @import("../core/math.zig");
const color = @import("../core/color.zig");
const palette = @import("../core/palette.zig");
const png = @import("../core/png.zig");
const model_mod = @import("../engine/model.zig");
const rig = @import("../engine/rig.zig");
const arena_mesh = @import("../engine/arena_mesh.zig");
const renderer = @import("../engine/renderer.zig");
const assets = @import("assets");
const sim_mod = @import("tome_sim.zig");
const target_mod = @import("tome_target.zig");
const intent_mod = @import("intent.zig");
const hud = @import("tome_hud.zig");
const content_mod = @import("content.zig");
const items_mod = @import("items.zig");
const attributes = @import("attributes.zig");
const save_mod = @import("save.zig");
const gear_save = @import("gear_save.zig");

const FloatText = struct {
    pos: math.Vec3 = math.Vec3.zero,
    value: i32 = 0,
    life: f32 = 0,
    color: u32 = 0xffffff,
};

const Visual = struct {
    pos: math.Vec3 = math.Vec3.zero,
    target: math.Vec3 = math.Vec3.zero,
    yaw: f32 = 0,
    target_yaw: f32 = 0,
    moving: f32 = 0,
    flash: f32 = 0,
    anim: rig.AnimState = .{},
};

pub const Input = struct {
    step_x: i32 = 0,
    step_y: i32 = 0,
    talent: i8 = -1,
    /// Space while aiming confirms the pending talent.
    confirm: bool = false,
    wait: bool = false,
    inventory: bool = false,
    character: bool = false,
    target_next: bool = false,
    restart: bool = false,
    help: bool = false,
    yaw_delta: f32 = 0,
    zoom_delta: f32 = 0,
};

pub const TomeGame = struct {
    gpa: std.mem.Allocator,
    arena_alloc: std.heap.ArenaAllocator,
    models: model_mod.ModelDb,
    mesh: arena_mesh.Mesh,
    renderer: renderer.Renderer,
    camera: math.OrbitCamera = .{},
    camera_target: math.Vec3 = math.Vec3.init(0, 0.55, 0),
    sim: sim_mod.Sim,
    content: content_mod.Content = undefined,
    inventory: items_mod.Inventory = .{},
    mods: items_mod.ModifierSet = .{},
    loot_rng: std.Random.DefaultPrng = undefined,
    chest_loot_seen: u32 = 0,
    kill_loot_seen: u32 = 0,
    last_level: u16 = 1,
    selected: ?usize = null,
    /// Talent index while the player is aiming; null when not aiming. Aiming
    /// itself never spends a turn, only a successful confirmation does.
    aim_talent: ?usize = null,
    reset_armed: f32 = 0,
    /// Throttles OS key-repeat so holding a direction does not burn a turn
    /// for every repeat event (critic P0).
    step_cooldown: f32 = 0,
    seed: u64,
    class: sim_mod.Class,
    /// False while the class-selection menu is up; the sim is already
    /// generated so the menu can preview the 3D dungeon behind the cards.
    started: bool = true,
    hero_vis: Visual = .{},
    enemy_vis: [sim_mod.max_enemies]Visual = undefined,
    floats: [24]FloatText = .{ .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{} },
    float_cursor: usize = 0,
    mesh_floor: u8 = 0,
    panel: hud.Panel = .none,
    hud_state: hud.State = .{},
    time: f32 = 0,
    dt: f32 = 0,
    frame: u32 = 0,
    fps: f32 = 60,
    frame_ms: f32 = 16.6,
    show_hud: bool = true,
    show_help: bool = false,
    debug: bool = false,

    pub fn create(gpa: std.mem.Allocator, width: u32, height: u32, class: sim_mod.Class, seed: u64) !*TomeGame {
        const self = try gpa.create(TomeGame);
        errdefer gpa.destroy(self);
        self.* = .{
            .gpa = gpa,
            .arena_alloc = std.heap.ArenaAllocator.init(gpa),
            .models = undefined,
            .mesh = .{ .verts = &.{}, .tris = &.{} },
            .renderer = undefined,
            .sim = undefined,
            .seed = seed,
            .class = class,
        };
        try self.setup(width, height);
        return self;
    }

    fn setup(self: *TomeGame, width: u32, height: u32) !void {
        const alloc = self.arena_alloc.allocator();
        self.models = try model_mod.ModelDb.init(alloc, assets.all);
        self.renderer = try renderer.Renderer.init(self.gpa, width, height);
        self.content = try content_mod.load(self.gpa);
        self.loot_rng = std.Random.DefaultPrng.init(self.seed ^ 0x9e3779b97f4a7c15);
        self.sim = sim_mod.Sim.init(self.seed, self.class);
        self.camera = .{
            .target = math.Vec3.init(0, 0.55, 0),
            .yaw = -0.35,
            .pitch = 0.78,
            .distance = 12.3,
            .fov = 0.76,
        };
        self.camera_target = self.camera.target;
        self.rebuildMesh();
        self.resetVisuals();
        self.fillHudState();
    }

    pub fn destroy(self: *TomeGame) void {
        if (self.mesh.verts.len > 0) self.gpa.free(self.mesh.verts);
        if (self.mesh.tris.len > 0) self.gpa.free(self.mesh.tris);
        self.content.deinit();
        self.renderer.deinit();
        self.arena_alloc.deinit();
        const gpa = self.gpa;
        gpa.destroy(self);
    }

    fn rebuildMesh(self: *TomeGame) void {
        if (self.mesh.verts.len > 0) self.gpa.free(self.mesh.verts);
        if (self.mesh.tris.len > 0) self.gpa.free(self.mesh.tris);
        self.mesh = arena_mesh.buildDungeon(self.gpa, &self.sim.blocked, sim_mod.grid_w, sim_mod.grid_h, .{ self.sim.stairs.x, self.sim.stairs.y }) catch .{ .verts = &.{}, .tris = &.{} };
        self.mesh_floor = self.sim.floor;
    }

    fn tilePos(x: i32, y: i32) math.Vec3 {
        return math.Vec3.init(@as(f32, @floatFromInt(x)) - 6.0, 0, @as(f32, @floatFromInt(y)) - 6.0);
    }

    fn resetVisuals(self: *TomeGame) void {
        const hp = tilePos(self.sim.hero.pos.x, self.sim.hero.pos.y);
        self.hero_vis = .{ .pos = hp, .target = hp, .yaw = 0, .target_yaw = 0, .anim = .{ .kind = @intCast(@backingInt(self.class)) } };
        var i: usize = 0;
        while (i < sim_mod.max_enemies) : (i += 1) {
            if (i >= self.sim.enemy_count) {
                self.enemy_vis[i] = .{};
                continue;
            }
            const e = self.sim.enemies[i];
            const p = tilePos(e.pos.x, e.pos.y);
            self.enemy_vis[i] = .{
                .pos = p,
                .target = p,
                .yaw = std.math.atan2(-p.x, -p.z),
                .target_yaw = std.math.atan2(-p.x, -p.z),
                .anim = .{ .kind = enemyAnimKind(e.kind) },
            };
        }
    }

    fn enemyAnimKind(kind: u8) u8 {
        return switch (kind) {
            0 => 3,
            1 => 4,
            2 => 5,
            3 => 3,
            4 => 4,
            else => 6,
        };
    }

    fn enemyScale(kind: u8) f32 {
        return switch (kind) {
            0 => 1.18,
            1 => 1.32,
            2 => 1.55,
            3 => 1.25,
            4 => 1.38,
            else => 1.95,
        };
    }

    fn heroScale(_: *const TomeGame) f32 {
        return 1.55;
    }

    /// Rebuild every run-scoped system from (seed, class). Shared by restart,
    /// class selection and the menu, so R never loses the chosen class.
    fn resetRun(self: *TomeGame) void {
        self.sim.reset(self.seed, self.class);
        self.inventory = items_mod.Inventory.init();
        self.mods.clear();
        self.loot_rng = std.Random.DefaultPrng.init(self.seed ^ 0x9e3779b97f4a7c15);
        self.chest_loot_seen = 0;
        self.kill_loot_seen = 0;
        self.last_level = 1;
        self.selected = null;
        self.aim_talent = null;
        self.reset_armed = 0;
        self.step_cooldown = 0;
        self.show_help = false;
        self.panel = .none;
        self.rebuildMesh();
        self.resetVisuals();
        self.fillHudState();
    }

    pub fn restart(self: *TomeGame) void {
        self.started = true;
        self.resetRun();
    }

    /// Show the pre-run class cards. The same seed is used for the preview;
    /// picking a class keeps it and regenerates the dungeon for that class.
    pub fn openMenu(self: *TomeGame) void {
        self.started = false;
        self.resetRun();
    }

    pub fn selectClass(self: *TomeGame, class: sim_mod.Class) void {
        self.class = class;
        self.restart();
        self.sim.pushLog("开始：{s}", .{sim_mod.class_names[@backingInt(self.class)]});
        self.fillHudState();
    }

    fn classOf(self: *const TomeGame) attributes.Class {
        return switch (self.class) {
            .warrior => .warrior,
            .mage => .mage,
            .chronomancer => .chronomancer,
        };
    }

    /// F5: write the pure run snapshot and the bag/equipment sidecar.
    /// The parent directory is created on demand; a failure leaves the
    /// currently running game untouched and is reported in the log.
    pub fn saveRun(self: *TomeGame, io: std.Io, sim_path: []const u8, gear_path: []const u8) void {
        if (std.fs.path.dirname(sim_path)) |dir| {
            std.Io.Dir.cwd().createDirPath(io, dir) catch {};
        }
        save_mod.saveFile(io, self.gpa, sim_path, &self.sim) catch |err| {
            self.sim.pushLog("存档失败 {s}", .{@errorName(err)});
            return;
        };
        gear_save.saveFileWithRng(io, self.gpa, gear_path, &self.inventory, &self.loot_rng) catch |err| {
            self.sim.pushLog("装备存档失败 {s}", .{@errorName(err)});
            return;
        };
        self.sim.pushLog("已存档", .{});
    }

    /// F9: load both halves. A missing/corrupt gear file leaves the current
    /// run alone; a fresh save still loads with an empty bag.
    pub fn loadRun(self: *TomeGame, io: std.Io, sim_path: []const u8, gear_path: []const u8) void {
        const loaded = save_mod.loadFile(io, self.gpa, sim_path) catch |err| {
            const msg = if (err == error.FileNotFound) "没有存档" else @errorName(err);
            self.sim.pushLog("读档失败：{s}", .{msg});
            return;
        };
        var gear = gear_save.loadFile(io, self.gpa, gear_path) catch |err| blk: {
            if (err == error.FileNotFound) break :blk gear_save.GearSave{};
            self.sim.pushLog("装备读档失败：{s}", .{@errorName(err)});
            return;
        };
        for (gear.items[0..@as(usize, gear.len)]) |id| {
            if (id >= self.content.items.len) {
                self.sim.pushLog("读档失败：未知物品", .{});
                return;
            }
        }
        for (gear.equipped) |maybe| {
            if (maybe) |id| {
                if (id >= self.content.items.len) {
                    self.sim.pushLog("读档失败：未知装备", .{});
                    return;
                }
            }
        }

        var loaded_inv = items_mod.Inventory.init();
        gear_save.restore(&gear, &loaded_inv) catch {
            self.sim.pushLog("读档失败：背包损坏", .{});
            return;
        };
        self.sim = loaded;
        self.seed = loaded.seed;
        self.class = loaded.class;
        self.inventory = loaded_inv;
        self.mods.clear();
        self.rebuildMods();
        if (gear_save.rngNonZero(gear.loot_rng)) {
            self.loot_rng.s = gear.loot_rng;
        } else {
            self.loot_rng = std.Random.DefaultPrng.init(loaded.seed ^ 0x9e3779b97f4a7c15 ^ @as(u64, loaded.turn));
        }
        self.chest_loot_seen = loaded.chest_loot_events;
        self.kill_loot_seen = loaded.kill_loot_events;
        self.last_level = loaded.hero.level;
        self.selected = null;
        self.aim_talent = null;
        self.reset_armed = 0;
        self.step_cooldown = 0;
        self.show_help = false;
        self.panel = .none;
        self.started = true;
        self.rebuildMesh();
        self.resetVisuals();
        self.fillHudState();
        self.sim.pushLog("读档", .{});
    }

    fn rebuildMods(self: *TomeGame) void {
        self.mods.rebuild(self.content.items, &self.inventory.equipped);
        self.sim.applyModifiers(self.mods.slice());
    }

    fn processLoot(self: *TomeGame) void {
        while (self.chest_loot_seen < self.sim.chest_loot_events) {
            self.chest_loot_seen += 1;
            self.grantDrop(true);
        }
        while (self.kill_loot_seen < self.sim.kill_loot_events) {
            self.kill_loot_seen += 1;
            self.grantDrop(false);
        }
    }

    pub fn autoPlayStep(self: *TomeGame) void {
        if (!self.started or self.sim.state != .playing or self.panel != .none) return;
        // The headless bot releases talents directly; never leave it aiming.
        self.clearAim();
        const hero = self.sim.hero.pos;
        const dirs = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };

        // Step out of a telegraphed boss AOE before doing anything else.
        if (self.sim.aoe_armed and intent_mod.bossAoeDue(self.sim.turn +| 1)) {
            var best: ?[2]i32 = null;
            var best_d: i32 = -1;
            for (dirs) |d| {
                const nx = hero.x + d[0];
                const ny = hero.y + d[1];
                if (!self.sim.canMove(d[0], d[1])) continue;
                if (self.sim.enemyAt(nx, ny) != null) continue;
                const dd: i32 = @intCast(@abs(nx - self.sim.aoe_target.x) + @abs(ny - self.sim.aoe_target.y));
                if (dd > best_d) {
                    best_d = dd;
                    best = d;
                }
            }
            if (best) |d| {
                _ = self.sim.move(d[0], d[1]);
                return;
            }
        }

        // adjacent enemy: bump attack
        for (dirs) |d| {
            if (self.sim.enemyAt(hero.x + d[0], hero.y + d[1]) != null) {
                _ = self.sim.move(d[0], d[1]);
                return;
            }
        }

        // low health and no immediate threat: rest a turn
        if (self.sim.hero.hp < self.sim.hero.hp_max * 0.35 and self.sim.nearestEnemy(4) == null) {
            _ = self.sim.wait();
            return;
        }

        // a nearby enemy is a good talent target; use the whole kit
        if (self.sim.nearestEnemy(5) != null) {
            if (self.class == .warrior and self.sim.hero.buff_turns == 0 and self.sim.hero.cooldowns[2] == 0 and self.sim.hero.resource >= 20) {
                if (self.sim.useTalent(2)) return;
            }
            if (self.sim.useTalent(0)) return;
            if (self.sim.useTalent(1)) return;
            if (self.sim.hero.hp < self.sim.hero.hp_max * 0.4 and self.sim.useTalent(2)) return;
        }

        // otherwise walk the A* path toward the stairs
        if (self.sim.map.astarToOccupiedGoal(
            .{ .x = hero.x, .y = hero.y },
            .{ .x = self.sim.stairs.x, .y = self.sim.stairs.y },
            null,
        )) |path| {
            if (path.len > 1) {
                const n = path.slice()[1];
                if (self.sim.move(n.x - hero.x, n.y - hero.y)) return;
            }
        }
        _ = self.sim.wait();
    }

    fn equipBag(self: *TomeGame, index: usize) void {
        if (index >= self.inventory.count()) return;
        const item = self.inventory.at(index);
        if (item >= self.content.items.len) return;
        const def = &self.content.items[item];
        if (def.slot == null) {
            self.sim.pushLog("{s} 不能装备", .{def.name});
            return;
        }
        self.inventory.equip(self.content.items, item) catch {
            self.sim.pushLog("无法装备 {s}", .{def.name});
            return;
        };
        self.rebuildMods();
        self.sim.pushLog("装备 {s}", .{def.name});
    }

    fn itemScore(def: *const items_mod.ItemDef) f32 {
        var score: f32 = 0;
        for (def.mods) |m| {
            score += m.flat;
            score += m.pct * 20.0;
        }
        return score;
    }

    fn usePotion(self: *TomeGame) bool {
        for (self.inventory.slice()) |id| {
            if (id >= self.content.items.len) continue;
            const def = &self.content.items[id];
            const use = def.use orelse continue;
            if (use.heal <= 0) continue;
            if (!self.inventory.remove(id)) continue;
            self.sim.hero.hp = @min(self.sim.hero.hp_max, self.sim.hero.hp + use.heal);
            self.sim.pushLog("使用 {s}：恢复 {d:.0} 生命", .{ def.name, use.heal });
            _ = self.sim.wait();
            return true;
        }
        return false;
    }

    pub fn debugGrantLoot(self: *TomeGame, n: u32) void {
        var i: u32 = 0;
        while (i < n) : (i += 1) self.grantDrop(true);
        self.rebuildMods();
    }

    fn grantDrop(self: *TomeGame, guaranteed: bool) void {
        if (self.content.items.len == 0 or self.content.enemies.len == 0) return;
        const chance = if (guaranteed) 0.0 else self.loot_rng.random().float(f32);
        const pick = self.loot_rng.random().float(f32);
        const item = self.content.rollDrop(self.classOf(), chance, pick, &self.content.enemies[0]) orelse return;
        if (!self.inventory.pickup(item)) {
            self.sim.pushLog("背包已满", .{});
            return;
        }
        const def = &self.content.items[item];
        self.sim.pushLog("获得 {s}", .{def.name});
        if (def.slot) |slot| {
            if (def.allowsClass(self.classOf())) {
                var better = self.inventory.equipped.get(slot) == null;
                if (self.inventory.equipped.get(slot)) |current| {
                    if (current < self.content.items.len) {
                        better = itemScore(def) > itemScore(&self.content.items[current]);
                    }
                }
                if (better) {
                    self.inventory.equip(self.content.items, item) catch {};
                    self.rebuildMods();
                }
            }
        }
    }

    pub fn update(self: *TomeGame, input: Input, dt_raw: f32) void {
        const dt = @min(0.05, dt_raw);
        self.dt = dt;
        self.time += dt;
        self.frame += 1;
        self.frame_ms = dt * 1000.0;
        self.fps = if (dt > 0) 1.0 / dt else 60.0;

        self.camera.yaw += input.yaw_delta;
        self.camera.distance = std.math.clamp(self.camera.distance - input.zoom_delta * 0.35, 6.0, 13.0);
        self.step_cooldown = @max(0, self.step_cooldown - dt);

        if (!self.started) {
            if (input.talent >= 0) self.selectClass(sim_mod.classFromIndex(@intCast(input.talent)));
            self.syncVisuals(false);
            self.updateVisuals(dt);
            self.followCamera();
            self.fillHudState();
            return;
        }

        if (input.help) {
            self.show_help = !self.show_help;
            self.clearAim();
            self.fillHudState();
            return;
        }
        if (self.show_help) {
            self.fillHudState();
            return;
        }

        self.reset_armed = @max(0, self.reset_armed - dt);
        if (input.restart) {
            self.clearAim();
            if (self.sim.state != .playing or self.reset_armed > 0) {
                self.restart();
            } else {
                self.reset_armed = 2.0;
                self.sim.pushLog("再按 R 确认重开", .{});
            }
        }
        if (input.target_next) self.cycleTarget();

        if (input.inventory) {
            self.clearAim();
            self.panel = if (self.panel == .inventory) .none else .inventory;
        }
        if (input.character) {
            self.clearAim();
            self.panel = if (self.panel == .character) .none else .character;
        }
        if (self.panel == .inventory and input.talent >= 0) {
            self.equipBag(@intCast(input.talent));
        }

        var used_potion = false;
        if (self.panel == .none and self.sim.state == .playing and self.sim.hero.hp < self.sim.hero.hp_max * 0.35) {
            used_potion = self.usePotion();
        }

        if (!used_potion and self.panel == .none and self.sim.state == .playing) {
            if ((input.step_x != 0 or input.step_y != 0) and self.step_cooldown <= 0) {
                // Walking away abandons the pending aim (no turn spent on the
                // cancel itself; the step below costs its usual turn).
                self.clearAim();
                self.step_cooldown = 0.30;
                const before_hero = self.sim.hero.hp;
                var before: [sim_mod.max_enemies]f32 = undefined;
                var bi: usize = 0;
                while (bi < self.sim.enemy_count) : (bi += 1) before[bi] = self.sim.enemies[bi].hp;
                if (!self.sim.move(input.step_x, input.step_y)) self.sim.pushLog("前方被挡住", .{});
                self.flashAfter(before_hero, before[0..self.sim.enemy_count]);
                if (input.step_x != 0 or input.step_y != 0) {
                    self.hero_vis.target_yaw = std.math.atan2(@as(f32, @floatFromInt(input.step_x)), @as(f32, @floatFromInt(input.step_y)));
                }
            } else if (self.aim_talent != null) {
                if (input.confirm) {
                    _ = self.confirmAim();
                } else if (input.wait) {
                    // 5/. is a wait, not a confirm; leave aim and spend the turn
                    // on resting instead of trapping the player in a red box.
                    self.clearAim();
                    _ = self.sim.wait();
                } else if (input.talent >= 0) {
                    self.talentKey(@intCast(input.talent));
                }
            } else if (input.talent >= 0) {
                self.talentKey(@intCast(input.talent));
            } else if (input.wait) {
                _ = self.sim.wait();
            }
        }

        self.processLoot();
        if (self.sim.hero.level != self.last_level) {
            self.last_level = self.sim.hero.level;
            self.rebuildMods();
        }

        if (self.sim.state != .playing) self.clearAim();

        if (self.sim.floor != self.mesh_floor) {
            self.clearAim();
            self.rebuildMesh();
            self.syncVisuals(true);
        }

        self.syncVisuals(false);
        self.updateVisuals(dt);
        self.followCamera();
        self.fillHudState();
    }

    /// Keep the whole room on screen while still following the hero: clamp the
    /// look-at point to the middle band and bias it toward the hero.
    fn followCamera(self: *TomeGame) void {
        self.camera.target.x = std.math.clamp(self.hero_vis.pos.x * 0.65, -2.8, 2.8);
        self.camera.target.z = std.math.clamp(self.hero_vis.pos.z * 0.65, -2.8, 2.8);
        self.camera.target.y = 0.35;
        self.camera_target = self.camera.target;
    }

    fn spawnFloat(self: *TomeGame, pos: math.Vec3, value: i32, color_value: u32) void {
        if (value == 0) return;
        const i = self.float_cursor;
        self.float_cursor = (i + 1) % self.floats.len;
        self.floats[i] = .{ .pos = pos.add(math.Vec3.init(0, 1.4, 0)), .value = value, .life = 0.75, .color = color_value };
    }

    fn drawFloats(self: *TomeGame) void {
        for (self.floats) |f| {
            if (f.life <= 0) continue;
            const p = self.camera.project(f.pos, self.renderer.width, self.renderer.height) orelse continue;
            if (p.depth <= 0.1) continue;
            const x: i32 = @intFromFloat(p.x);
            const y: i32 = @intFromFloat(p.y);
            var buf: [16]u8 = undefined;
            const txt = std.fmt.bufPrint(&buf, "{d}", .{f.value}) catch continue;
            const tw = renderer.Renderer.textWidth(txt, 1);
            self.renderer.fillRect(x - @divTrunc(tw, 2) - 2, y - 1, tw + 4, 11, palette.panel);
            self.renderer.drawText(x - @divTrunc(tw, 2), y, txt, f.color, 1, true);
        }
    }

    fn currentTarget(self: *const TomeGame) ?usize {
        if (self.selected) |s| {
            if (s < self.sim.enemy_count and self.sim.enemies[s].alive) return s;
        }
        return self.sim.nearestEnemy(20);
    }

    fn cycleTarget(self: *TomeGame) void {
        if (self.sim.enemy_count == 0) {
            self.selected = null;
            return;
        }
        var start: usize = 0;
        if (self.selected) |s| start = (s + 1) % self.sim.enemy_count;
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            const idx = (start + i) % self.sim.enemy_count;
            if (self.sim.enemies[idx].alive) {
                self.selected = idx;
                return;
            }
        }
        self.selected = null;
    }

    pub fn isAiming(self: *const TomeGame) bool {
        return self.aim_talent != null;
    }

    /// Escape path: aim is consumed first, so Esc never drops the run while
    /// the player is only cancelling a target. Returns true when consumed.
    pub fn cancelAim(self: *TomeGame) bool {
        if (self.aim_talent == null) return false;
        self.aim_talent = null;
        self.sim.pushLog("取消瞄准", .{});
        return true;
    }

    fn clearAim(self: *TomeGame) void {
        self.aim_talent = null;
    }

    /// Currently highlighted enemy. Falls back to the nearest living enemy at
    /// any distance so an out-of-range target can still be previewed in red.
    fn aimTarget(self: *const TomeGame) ?usize {
        return self.currentTarget();
    }

    /// Prefer the current target when it is already legal; otherwise snap to
    /// the nearest legal enemy so pressing 1/2/3 does not open on a red
    /// out-of-range preview when a valid target is available.
    fn bestAimTarget(self: *const TomeGame, talent: usize) ?usize {
        if (self.aimTarget()) |cur| {
            if (target_mod.preview(&self.sim, talent, cur).valid()) return cur;
        }
        var best: ?usize = null;
        var best_d: i32 = 0;
        for (self.sim.enemies[0..self.sim.enemy_count], 0..) |e, i| {
            if (!e.alive) continue;
            const p = target_mod.preview(&self.sim, talent, i);
            if (!p.valid()) continue;
            if (best == null or p.distance < best_d) {
                best = i;
                best_d = p.distance;
            }
        }
        return best orelse self.aimTarget();
    }

    fn beginAim(self: *TomeGame, talent: usize) void {
        const name = self.sim.talentName(talent);
        if (self.sim.hero.cooldowns[talent] > 0) {
            self.sim.pushLog("{s} 冷却中", .{name});
            return;
        }
        if (self.sim.hero.resource < @as(f32, @floatFromInt(self.sim.talentCost(talent)))) {
            self.sim.pushLog("{s} 缺资源", .{name});
            return;
        }
        self.aim_talent = talent;
        self.selected = self.bestAimTarget(talent);
        self.sim.pushLog("瞄准 {s}：空格确认", .{name});
    }

    fn switchAim(self: *TomeGame, talent: usize) void {
        if (target_mod.needsTarget(self.class, talent)) {
            self.beginAim(talent);
            return;
        }
        // Non-targeted talent: leave aim and release it right away.
        self.clearAim();
        _ = self.releaseTalent(talent);
    }

    /// One number key. While aiming the same key confirms and another key
    /// switches; while idle a target talent starts aim and a self talent is
    /// released immediately (the old hotbar behaviour).
    fn talentKey(self: *TomeGame, talent: usize) void {
        if (self.aim_talent) |aim| {
            if (aim == talent) {
                _ = self.confirmAim();
            } else {
                self.switchAim(talent);
            }
            return;
        }
        if (target_mod.needsTarget(self.class, talent)) {
            self.beginAim(talent);
        } else {
            _ = self.releaseTalent(talent);
        }
    }

    fn castTalentAt(self: *TomeGame, talent: usize, target: ?usize) bool {
        const before_hero = self.sim.hero.hp;
        var before: [sim_mod.max_enemies]f32 = undefined;
        var bi: usize = 0;
        while (bi < self.sim.enemy_count) : (bi += 1) before[bi] = self.sim.enemies[bi].hp;
        const used = self.sim.useTalentOn(talent, target);
        if (used) {
            self.hero_vis.anim.cast = 1.0;
            self.flashAfter(before_hero, before[0..bi]);
        }
        return used;
    }

    fn releaseTalent(self: *TomeGame, talent: usize) bool {
        if (self.castTalentAt(talent, self.selected)) return true;
        self.sim.pushLog("技能不可用", .{});
        return false;
    }

    /// Confirm the pending aim. Validation failure logs a reason and leaves
    /// the turn and resource untouched; success spends exactly one turn.
    fn confirmAim(self: *TomeGame) bool {
        const talent = self.aim_talent orelse return false;
        const p = target_mod.preview(&self.sim, talent, self.aimTarget());
        if (!p.valid()) {
            self.sim.pushLog("瞄准：{s}", .{p.reason()});
            return false;
        }
        const turn_before = self.sim.turn;
        if (!self.castTalentAt(talent, p.target)) {
            self.sim.pushLog("技能不可用", .{});
            return false;
        }
        self.aim_talent = null;
        if (self.sim.turn == turn_before) {
            // Defensive: a confirmed talent must always spend a turn.
            self.sim.pushLog("技能未生效", .{});
            return false;
        }
        return true;
    }

    fn flashAfter(self: *TomeGame, hero_before: f32, enemies_before: []const f32) void {
        const hero_loss = hero_before - self.sim.hero.hp;
        if (hero_loss > 0.5) {
            self.hero_vis.flash = 0.22;
            self.spawnFloat(self.hero_vis.pos, -@as(i32, @intFromFloat(hero_loss)), palette.red);
        }
        var i: usize = 0;
        while (i < enemies_before.len and i < self.sim.enemy_count) : (i += 1) {
            const loss = enemies_before[i] - self.sim.enemies[i].hp;
            if (loss > 0.5) {
                self.enemy_vis[i].flash = 0.22;
                self.spawnFloat(self.enemy_vis[i].pos, -@as(i32, @intFromFloat(loss)), palette.gold_light);
            }
        }
    }

    fn syncVisuals(self: *TomeGame, full: bool) void {
        const hp = tilePos(self.sim.hero.pos.x, self.sim.hero.pos.y);
        self.hero_vis.target = hp;
        if (full) self.hero_vis.pos = hp;
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            const e = self.sim.enemies[i];
            const p = tilePos(e.pos.x, e.pos.y);
            self.enemy_vis[i].target = p;
            if (full) self.enemy_vis[i].pos = p;
            self.enemy_vis[i].anim.kind = enemyAnimKind(e.kind);
            const dx = p.x - self.enemy_vis[i].pos.x;
            const dz = p.z - self.enemy_vis[i].pos.z;
            if (@abs(dx) + @abs(dz) > 0.02) self.enemy_vis[i].target_yaw = std.math.atan2(dx, dz);
        }
    }

    fn updateVisuals(self: *TomeGame, dt: f32) void {
        const lerp = @min(1.0, dt * 12.0);
        self.hero_vis.pos = math.Vec3.init(
            self.hero_vis.pos.x + (self.hero_vis.target.x - self.hero_vis.pos.x) * lerp,
            self.hero_vis.pos.y + (self.hero_vis.target.y - self.hero_vis.pos.y) * lerp,
            self.hero_vis.pos.z + (self.hero_vis.target.z - self.hero_vis.pos.z) * lerp,
        );
        const hdx = self.hero_vis.target.x - self.hero_vis.pos.x;
        const hdz = self.hero_vis.target.z - self.hero_vis.pos.z;
        self.hero_vis.moving = if (@abs(hdx) + @abs(hdz) > 0.02) 1.0 else 0.0;
        self.hero_vis.yaw = approachAngle(self.hero_vis.yaw, self.hero_vis.target_yaw, dt * 12.0);
        self.hero_vis.anim.time += dt;
        self.hero_vis.anim.phase += dt * (5.0 + self.hero_vis.moving * 5.0);
        self.hero_vis.anim.moving = self.hero_vis.moving;
        self.hero_vis.anim.cast = @max(0, self.hero_vis.anim.cast - dt * 3.0);
        self.hero_vis.flash = @max(0, self.hero_vis.flash - dt);
        for (&self.floats) |*f| {
            if (f.life > 0) {
                f.life -= dt;
                f.pos.y += dt * 0.55;
            }
        }

        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            const v = &self.enemy_vis[i];
            v.pos = math.Vec3.init(
                v.pos.x + (v.target.x - v.pos.x) * lerp,
                v.pos.y + (v.target.y - v.pos.y) * lerp,
                v.pos.z + (v.target.z - v.pos.z) * lerp,
            );
            const dx = v.target.x - v.pos.x;
            const dz = v.target.z - v.pos.z;
            v.moving = if (@abs(dx) + @abs(dz) > 0.02) 1.0 else 0.0;
            v.yaw = approachAngle(v.yaw, v.target_yaw, dt * 8.0);
            v.anim.time += dt;
            v.anim.phase += dt * (4.0 + v.moving * 4.0);
            v.anim.moving = v.moving;
            v.flash = @max(0, v.flash - dt);
        }
    }

    fn approachAngle(from: f32, to: f32, amount: f32) f32 {
        var d = to - from;
        while (d > std.math.pi) d -= 2.0 * std.math.pi;
        while (d < -std.math.pi) d += 2.0 * std.math.pi;
        return from + d * @min(1.0, amount);
    }

    fn heroModel(self: *TomeGame) *const model_mod.Model {
        const names = [_][]const u8{ "warrior", "archmage", "chronomancer" };
        return self.models.at(self.models.indexOf(names[@backingInt(self.class)]) orelse 0);
    }

    fn enemyModel(self: *TomeGame, kind: u8) *const model_mod.Model {
        const names = [_][]const u8{ "skeleton", "wraith", "golem", "elite_skeleton", "elite_wraith", "abyss_guard" };
        const fallback = [_][]const u8{ "skeleton", "wraith", "golem", "skeleton", "wraith", "abyss_guard" };
        const name = names[@min(kind, names.len - 1)];
        if (self.models.indexOf(name)) |i| return self.models.at(i);
        return self.models.at(self.models.indexOf(fallback[@min(kind, fallback.len - 1)]) orelse 0);
    }

    pub fn render(self: *TomeGame) void {
        self.renderer.begin(self.camera, self.time);
        self.addLights();

        self.renderer.drawMesh(&self.mesh, math.Mat4.identity, .{ .id = 1 });

        // shadows and feet rings
        self.renderer.drawShadow(self.hero_vis.pos.add(math.Vec3.init(0.06, 0, -0.04)), 0.30);
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            if (!self.sim.enemies[i].alive) continue;
            self.renderer.drawShadow(self.enemy_vis[i].pos.add(math.Vec3.init(0.06, 0, -0.04)), 0.32 * enemyScale(self.sim.enemies[i].kind));
        }
        self.drawRings();
        self.drawAimMarkers();

        // hero
        var pose: rig.Pose = .{};
        rig.compute(self.heroModel(), self.hero_vis.anim, &pose);
        self.renderer.drawModel(self.heroModel(), pose.joints[0..pose.count], math.Mat4.compose(self.hero_vis.pos, self.hero_vis.yaw, 0, 0, self.heroScale()), .{
            .tint = if (self.hero_vis.flash > 0) color.pack(255, 120, 96) else 0xffffff,
            .id = 200,
        });

        // enemies
        i = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            const e = self.sim.enemies[i];
            if (!e.alive) continue;
            var ep: rig.Pose = .{};
            rig.compute(self.enemyModel(e.kind), self.enemy_vis[i].anim, &ep);
            const tint = if (self.enemy_vis[i].flash > 0) color.pack(255, 110, 90) else 0xffffff;
            self.renderer.drawModel(self.enemyModel(e.kind), ep.joints[0..ep.count], math.Mat4.compose(self.enemy_vis[i].pos, self.enemy_vis[i].yaw, 0, 0, enemyScale(e.kind)), .{
                .tint = tint,
                .id = @intCast(300 + i),
            });
        }

        self.drawProps();
        self.renderer.resolve();
        self.drawFloats();
        if (self.started) self.drawWorldBars();
        if (self.show_hud) hud.draw(&self.renderer, self.hud_state);
    }

    fn drawWorldBars(self: *TomeGame) void {
        const w: i32 = @intCast(self.renderer.width);
        const h: i32 = @intCast(self.renderer.height);
        if (self.camera.project(tilePos(self.sim.stairs.x, self.sim.stairs.y).add(math.Vec3.init(0, 1.0, 0)), self.renderer.width, self.renderer.height)) |sp| {
            if (sp.depth > 0.1) {
                const sx: i32 = @intFromFloat(sp.x);
                const sy: i32 = @intFromFloat(sp.y);
                const sealed = self.sim.floor >= self.sim.floors and self.sim.hasLivingBoss();
                const label = if (sealed) "楼梯 封印" else "楼梯";
                const tw = renderer.Renderer.textWidth(label, 1);
                const lx = std.math.clamp(sx - @divTrunc(tw, 2), 3, w - tw - 3);
                const ly = @max(68, sy - 12);
                self.renderer.fillRect(lx - 3, ly, tw + 6, 12, palette.panel);
                self.renderer.strokeRect(lx - 3, ly, tw + 6, 12, if (sealed) palette.red else palette.cyan);
                self.renderer.drawText(lx, ly + 1, label, if (sealed) palette.red else palette.cyan_light, 1, true);
            }
        }
        const target = self.currentTarget();
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            const e = self.sim.enemies[i];
            if (!e.alive) continue;
            const p = self.camera.project(self.enemy_vis[i].pos.add(math.Vec3.init(0, 2.0, 0)), self.renderer.width, self.renderer.height) orelse continue;
            if (p.depth <= 0.1) continue;
            const x: i32 = @intFromFloat(p.x);
            const y: i32 = @intFromFloat(p.y);
            if (x < -30 or x > w + 30 or y < -20 or y > h + 20) continue;
            const bw: i32 = 18 + @as(i32, @intFromFloat(@min(18.0, e.hp_max / 22.0)));
            self.renderer.fillRect(x - @divTrunc(bw, 2), y, bw, 3, palette.deep);
            const frac = if (e.hp_max > 0) std.math.clamp(e.hp / e.hp_max, 0, 1) else 0;
            const fill: i32 = @intFromFloat(@as(f32, @floatFromInt(bw - 2)) * frac);
            if (fill > 0) self.renderer.fillRect(x - @divTrunc(bw, 2) + 1, y + 1, fill, 1, palette.red);
            self.renderer.strokeRect(x - @divTrunc(bw, 2), y, bw, 3, palette.muted);
            if (self.sim.intentFor(i)) |intent| {
                var ibuf: [24]u8 = undefined;
                const label = switch (intent.kind) {
                    .aoe => std.fmt.bufPrint(&ibuf, "深渊斩 -{d:.0}", .{intent.damage_preview}) catch "",
                    .melee, .ranged => std.fmt.bufPrint(&ibuf, "-{d:.0}", .{intent.damage_preview}) catch "",
                    .chase => "!",
                    .wait => "晕",
                };
                if (label.len > 0) {
                    const ix = std.math.clamp(x - @divTrunc(renderer.Renderer.textWidth(label, 1), 2), 2, w - 2);
                    self.renderer.drawText(ix, y + 5, label, if (intent.kind == .aoe) palette.red else palette.gold_light, 1, true);
                }
            }
            if (target != null and target.? == i) {
                const aiming = self.aim_talent != null;
                var tbuf: [64]u8 = undefined;
                const speed_mark = if (e.speed >= 150) " x2" else if (e.speed <= 75) " 慢" else "";
                const tname = std.fmt.bufPrint(&tbuf, "{s} {d:.0}/{d:.0}{s}", .{ e.name, e.hp, e.hp_max, speed_mark }) catch e.name;
                const tw = renderer.Renderer.textWidth(tname, 1);
                const lx = std.math.clamp(x - @divTrunc(tw, 2), 2, w - tw - 2);
                const ly = @max(68, y - 13);
                self.renderer.fillRect(lx - 3, ly, tw + 6, 11, palette.panel);
                self.renderer.strokeRect(lx - 3, ly, tw + 6, 11, if (aiming) palette.gold else palette.border);
                self.renderer.drawText(lx, ly + 1, tname, if (aiming) palette.gold_light else palette.red, 1, true);
            }
        }
    }

    fn addLights(self: *TomeGame) void {
        const corners = [_]math.Vec3{
            math.Vec3.init(-5.2, 1.55, -5.2),
            math.Vec3.init(5.2, 1.55, -5.2),
            math.Vec3.init(-5.2, 1.55, 5.2),
            math.Vec3.init(5.2, 1.55, 5.2),
        };
        for (corners, 0..) |p, i| {
            const flick = 1.0 + @sin(self.time * 8.0 + @as(f32, @floatFromInt(i)) * 1.7) * 0.12;
            self.renderer.addLight(.{
                .pos = p,
                .color = .{ .x = 1.0, .y = 0.46, .z = 0.15 },
                .intensity = 2.0 * flick,
                .radius = 5.6,
            });
        }
        const hero_light = if (self.class == .warrior) color.pack(255, 176, 110) else color.pack(90, 220, 205);
        _ = hero_light;
        self.renderer.addLight(.{
            .pos = self.hero_vis.pos.add(math.Vec3.init(0, 1.6, 0.4)),
            .color = if (self.class == .warrior) .{ .x = 1.0, .y = 0.82, .z = 0.62 } else .{ .x = 0.42, .y = 0.95, .z = 0.88 },
            .intensity = 1.65,
            .radius = 3.4,
        });
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            if (!self.sim.enemies[i].alive) continue;
            if (self.sim.enemies[i].kind == 5) {
                self.renderer.addLight(.{
                    .pos = self.enemy_vis[i].pos.add(math.Vec3.init(0, 1.2, 0)),
                    .color = .{ .x = 1.0, .y = 0.16, .z = 0.12 },
                    .intensity = 1.4,
                    .radius = 3.8,
                });
            }
        }
    }

    fn drawRings(self: *TomeGame) void {
        const ring = self.models.indexOf("rune_circle") orelse return;
        const ring_model = self.models.at(ring);
        self.renderer.drawModel(ring_model, null, math.Mat4.compose(self.hero_vis.pos.add(math.Vec3.init(0, 0.035, 0)), -self.time * 0.5, 0, 0, 0.40), .{
            .tint = palette.gold_light,
            .boost = 0.9,
            .additive = true,
            .alpha = 0.9,
        });
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            if (!self.sim.enemies[i].alive) continue;
            self.renderer.drawModel(ring_model, null, math.Mat4.compose(self.enemy_vis[i].pos.add(math.Vec3.init(0, 0.035, 0)), self.time * 0.35, 0, 0, 0.34), .{
                .tint = color.pack(255, 92, 74),
                .boost = 0.7,
                .additive = true,
                .alpha = 0.8,
            });
            if (self.sim.intentFor(i)) |intent| {
                if (intent.kind == .aoe) {
                    self.renderer.drawModel(ring_model, null, math.Mat4.compose(tilePos(intent.target.x, intent.target.y).add(math.Vec3.init(0, 0.04, 0)), -self.time * 0.6, 0, 0, 0.9), .{
                        .tint = color.pack(255, 54, 42),
                        .boost = 1.0,
                        .additive = true,
                        .alpha = 0.75,
                    });
                }
            }
        }
    }

    /// World-space aim preview: a pulsing ring on the highlighted enemy and
    /// one ring per cell covered by an area talent. Valid targets glow cyan,
    /// blocked ones red; nothing is drawn when the player is not aiming.
    fn drawAimMarkers(self: *TomeGame) void {
        const talent = self.aim_talent orelse return;
        const ring_index = self.models.indexOf("rune_circle") orelse return;
        const ring_model = self.models.at(ring_index);
        const p = target_mod.preview(&self.sim, talent, self.aimTarget());
        const accent: u32 = if (p.valid()) color.pack(110, 235, 200) else color.pack(255, 84, 66);
        if (p.target) |ti| {
            const e = self.sim.enemies[ti];
            const pos = tilePos(e.pos.x, e.pos.y).add(math.Vec3.init(0, 0.055, 0));
            self.renderer.drawModel(ring_model, null, math.Mat4.compose(pos, self.time * 0.9, 0, 0, 0.54), .{
                .tint = accent,
                .boost = 1.0,
                .additive = true,
                .alpha = 0.95,
            });
        }
        if (p.target != null and p.spec.aoe_radius > 0) {
            const aoe_tint: u32 = if (p.valid()) color.pack(255, 168, 74) else color.pack(220, 70, 50);
            for (p.aoeSlice()) |cell| {
                const pos = tilePos(cell.x, cell.y).add(math.Vec3.init(0, 0.045, 0));
                self.renderer.drawModel(ring_model, null, math.Mat4.compose(pos, -self.time * 0.35, 0, 0, 0.40), .{
                    .tint = aoe_tint,
                    .boost = 0.8,
                    .additive = true,
                    .alpha = 0.55,
                });
            }
        }
    }

    fn drawProps(self: *TomeGame) void {
        // stairs marker: a cool beacon so it never gets lost behind a wall
        const sp = tilePos(self.sim.stairs.x, self.sim.stairs.y);
        self.renderer.drawGlow(sp.add(math.Vec3.init(0, 0.45, 0)), 0.55, palette.cyan_light, 0.85);
        if (self.models.indexOf("stairs_down")) |si| {
            self.renderer.drawModel(self.models.at(si), null, math.Mat4.compose(sp, 0, 0, 0, 0.8), .{ .tint = 0xffffff, .id = 50 });
        }
        // chests
        var i: usize = 0;
        while (i < self.sim.chests.len) : (i += 1) {
            if (!self.sim.chest_alive[i]) continue;
            const name = if (self.models.indexOf("dungeon_chest")) |_| "dungeon_chest" else "chest";
            if (self.models.indexOf(name)) |ci| {
                self.renderer.drawModel(self.models.at(ci), null, math.Mat4.compose(tilePos(self.sim.chests[i].x, self.sim.chests[i].y), 0, 0, 0, 0.72), .{ .tint = 0xffffff, .id = @intCast(60 + i) });
            } else {
                self.renderer.drawGlow(tilePos(self.sim.chests[i].x, self.sim.chests[i].y).add(math.Vec3.init(0, 0.2, 0)), 0.25, palette.gold_light, 0.8);
            }
        }
        // traps
        i = 0;
        while (i < self.sim.traps.len) : (i += 1) {
            if (!self.sim.trap_alive[i]) continue;
            const name = if (i % 2 == 0) "trap_spikes" else "trap_rune";
            const tp = tilePos(self.sim.traps[i].x, self.sim.traps[i].y);
            if (self.models.indexOf(name)) |ti| {
                self.renderer.drawModel(self.models.at(ti), null, math.Mat4.compose(tp, 0, 0, 0, 0.9), .{ .tint = 0xffffff, .id = @intCast(70 + i) });
            } else {
                self.renderer.drawGlow(tp.add(math.Vec3.init(0, 0.1, 0)), 0.22, palette.red, 0.5);
            }
        }
    }

    fn fillHudState(self: *TomeGame) void {
        self.hud_state = .{
            .menu = !self.started,
            .help = self.show_help,
            .menu_seed = self.seed,
            .class_name = sim_mod.class_names[@backingInt(self.class)],
            .level = self.sim.hero.level,
            .xp = self.sim.hero.xp,
            .xp_next = 100 * self.sim.hero.level,
            .hp = self.sim.hero.hp,
            .hp_max = self.sim.hero.hp_max,
            .resource = self.sim.hero.resource,
            .resource_max = self.sim.hero.resource_max,
            .resource_label = sim_mod.resource_names[@backingInt(self.class)],
            .turn = self.sim.turn,
            .floor = self.sim.floor,
            .floors = self.sim.floors,
            .kills = self.sim.kills,
            .enemies_left = @intCast(self.sim.enemy_count - blk: {
                var n: u32 = 0;
                for (self.sim.enemies[0..self.sim.enemy_count]) |e| {
                    if (!e.alive) n += 1;
                }
                break :blk n;
            }),
            .stairs_hint = self.sim.stairsHint(),
            .stairs_dist = @intCast(@abs(self.sim.stairs.x - self.sim.hero.pos.x) + @abs(self.sim.stairs.y - self.sim.hero.pos.y)),
            .panel = self.panel,
            .dead = self.sim.state == .dead,
            .victory = self.sim.state == .victory,
        };
        var card_i: usize = 0;
        while (card_i < sim_mod.class_count) : (card_i += 1) {
            const class: sim_mod.Class = @fromBackingInt(@intCast(card_i));
            self.hud_state.menu_cards[card_i] = .{
                .name = sim_mod.class_names[card_i],
                .resource = sim_mod.resource_names[card_i],
                .resource_max = sim_mod.classResourceMax(class),
                .hp_max = sim_mod.classHpMax(class),
                .role = sim_mod.class_roles[card_i],
                .talents = .{
                    sim_mod.talentNameFor(class, 0),
                    sim_mod.talentNameFor(class, 1),
                    sim_mod.talentNameFor(class, 2),
                },
                .descs = sim_mod.class_talent_descs[card_i],
            };
        }
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const cost = self.sim.talentCost(i);
            const affordable = self.sim.hero.resource >= @as(f32, @floatFromInt(cost));
            self.hud_state.hotbar[i] = .{
                .name = self.sim.talentName(i),
                .cost = cost,
                .cooldown = self.sim.hero.cooldowns[i],
                .cooldown_max = self.sim.talentCooldown(i),
                .ready = self.sim.state == .playing and self.sim.hero.cooldowns[i] == 0 and affordable,
                .affordable = affordable,
            };
            self.hud_state.talent_descs[i] = self.sim.talentDesc(i);
        }
        const target = self.currentTarget();
        self.hud_state.target_name = "";
        self.hud_state.target_hp = 0;
        self.hud_state.target_hp_max = 1;
        self.hud_state.target_range = 0;
        if (target) |ti| {
            const e = self.sim.enemies[ti];
            self.hud_state.target_name = e.name;
            self.hud_state.target_hp = e.hp;
            self.hud_state.target_hp_max = e.hp_max;
            const dx = e.pos.x - self.sim.hero.pos.x;
            const dy = e.pos.y - self.sim.hero.pos.y;
            self.hud_state.target_range = @intCast(@abs(dx) + @abs(dy));
        }
        self.hud_state.aim = .{};
        if (self.aim_talent) |talent| {
            const p = target_mod.preview(&self.sim, talent, target);
            var aim = hud.AimInfo{
                .active = true,
                .valid = p.valid(),
                .talent_index = talent,
                .talent = self.sim.talentName(talent),
                .distance = p.distance,
                .damage = p.damageInt(),
                .aoe_radius = p.spec.aoe_radius,
                .reason = if (p.valid()) "" else p.reason(),
            };
            if (p.target) |ti| aim.target = self.sim.enemies[ti].name;
            self.hud_state.aim = aim;
        }
        const attrs = [_]i32{
            @intFromFloat(self.sim.hero.eff_stats[0]),
            @intFromFloat(self.sim.hero.eff_stats[1]),
            @intFromFloat(self.sim.hero.eff_stats[2]),
            @intFromFloat(self.sim.hero.eff_stats[3]),
            @intFromFloat(self.sim.hero.eff_stats[4]),
            @intFromFloat(self.sim.hero.eff_stats[5]),
        };
        self.hud_state.attrs = attrs;
        self.hud_state.attack = self.sim.hero.attack;
        self.hud_state.armor = self.sim.hero.armor;
        self.hud_state.crit = self.sim.hero.crit;
        self.hud_state.speed = @floatFromInt(self.sim.hero.speed);
        self.hud_state.res_per_turn = self.sim.hero.res_per_turn;
        const slots = [_]items_mod.Slot{ .main_hand, .body, .trinket };
        for (slots, 0..) |slot, si| {
            self.hud_state.equip[si] = "";
            if (self.inventory.equipped.get(slot)) |item| {
                if (item < self.content.items.len) self.hud_state.equip[si] = self.content.items[item].name;
            }
        }
        self.hud_state.item_count = @min(self.inventory.count(), self.hud_state.items.len);
        var ii: usize = 0;
        while (ii < self.hud_state.item_count) : (ii += 1) {
            const item = self.inventory.at(ii);
            self.hud_state.items[ii] = if (item < self.content.items.len) self.content.items[item].name else "";
        }
        self.hud_state.has_minimap = true;
        self.hud_state.minimap = @splat(0);
        var my: usize = 0;
        while (my < sim_mod.grid_h) : (my += 1) {
            var mx: usize = 0;
            while (mx < sim_mod.grid_w) : (mx += 1) {
                self.hud_state.minimap[my * sim_mod.grid_w + mx] = if (self.sim.blocked[my * sim_mod.grid_w + mx]) 1 else 0;
            }
        }
        self.hud_state.minimap[@as(usize, @intCast(self.sim.stairs.y)) * sim_mod.grid_w + @as(usize, @intCast(self.sim.stairs.x))] = 2;
        var ci: usize = 0;
        while (ci < self.sim.chests.len) : (ci += 1) {
            if (!self.sim.chest_alive[ci]) continue;
            const cp = self.sim.chests[ci];
            self.hud_state.minimap[@as(usize, @intCast(cp.y)) * sim_mod.grid_w + @as(usize, @intCast(cp.x))] = 3;
        }
        var ei: usize = 0;
        while (ei < self.sim.enemy_count) : (ei += 1) {
            const e = self.sim.enemies[ei];
            if (!e.alive) continue;
            self.hud_state.minimap[@as(usize, @intCast(e.pos.y)) * sim_mod.grid_w + @as(usize, @intCast(e.pos.x))] = 5;
        }
        self.hud_state.minimap[@as(usize, @intCast(self.sim.hero.pos.y)) * sim_mod.grid_w + @as(usize, @intCast(self.sim.hero.pos.x))] = 4;
        self.hud_state.log_count = @min(self.sim.log_total, 4);
        i = 0;
        while (i < self.hud_state.log_count) : (i += 1) {
            const start = (self.sim.log_head + self.sim.log_buf.len - self.hud_state.log_count) % self.sim.log_buf.len;
            self.hud_state.log_lines[i] = self.sim.log_buf[(start + i) % self.sim.log_buf.len].text[0..self.sim.log_buf[(start + i) % self.sim.log_buf.len].len];
        }
    }

    pub fn saveScreenshot(self: *TomeGame, io: std.Io, path: []const u8) !void {
        try png.writePng(io, self.gpa, path, self.renderer.width, self.renderer.height, self.renderer.color_buf);
    }
};

test "tome game: class menu selects and keeps the class on restart" {
    const gpa = std.testing.allocator;
    const g = try TomeGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();

    g.openMenu();
    try std.testing.expect(!g.started);
    try std.testing.expect(g.hud_state.menu);
    try std.testing.expect(g.hud_state.menu_cards[1].talents[0].len > 0);
    try std.testing.expect(g.hud_state.talent_descs[0].len > 0);
    const preview_seed = g.seed;

    g.update(.{ .talent = 1 }, 1.0 / 60.0);
    try std.testing.expect(g.started);
    try std.testing.expectEqual(sim_mod.Class.mage, g.class);
    try std.testing.expectEqual(sim_mod.Class.mage, g.sim.class);
    try std.testing.expectEqual(preview_seed, g.seed);
    try std.testing.expectEqual(g.seed, g.sim.seed);
    try std.testing.expect(!g.hud_state.menu);
    try std.testing.expectEqualStrings("火球", g.hud_state.hotbar[0].name);
    try std.testing.expect(g.hud_state.hotbar[0].cooldown_max > 0);

    const chosen_seed = g.seed;
    g.sim.state = .dead;
    g.update(.{ .restart = true }, 1.0 / 60.0);
    try std.testing.expect(g.started);
    try std.testing.expectEqual(sim_mod.Class.mage, g.class);
    try std.testing.expectEqual(chosen_seed, g.seed);
    try std.testing.expectEqual(sim_mod.State.playing, g.sim.state);
}

fn setGameEnemy(g: *TomeGame, index: usize, pos: sim_mod.GridPos, name: []const u8, hp: f32) void {
    g.sim.enemies[index] = .{
        .kind = 0,
        .name = name,
        .pos = pos,
        .hp = hp,
        .hp_max = hp,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
    };
}

fn addGameEnemy(g: *TomeGame, dx: i32, dy: i32, name: []const u8) void {
    const p = g.sim.hero.pos;
    setGameEnemy(g, g.sim.enemy_count, .{ .x = p.x + dx, .y = p.y + dy }, name, 999);
    g.sim.enemy_count += 1;
}

test "tome game: aiming waits for confirmation and spends one turn" {
    const gpa = std.testing.allocator;
    const g = try TomeGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    addGameEnemy(g, 1, 0, "骷髅兵");

    const turn = g.sim.turn;
    const res = g.sim.hero.resource;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource);
    try std.testing.expect(g.hud_state.aim.active);
    try std.testing.expect(g.hud_state.aim.valid);
    try std.testing.expectEqualStrings("重击", g.hud_state.aim.talent);
    try std.testing.expectEqualStrings("骷髅兵", g.hud_state.aim.target);
    try std.testing.expectEqual(@as(i32, 1), g.hud_state.aim.distance);
    try std.testing.expect(g.hud_state.aim.damage > 0);

    // Same key confirms: exactly one turn and one resource payment.
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(@as(?usize, null), g.aim_talent);
    try std.testing.expectEqual(turn + 1, g.sim.turn);
    try std.testing.expect(g.sim.hero.resource < res);
    try std.testing.expect(g.sim.hero.cooldowns[0] > 0);
    try std.testing.expect(!g.hud_state.aim.active);

    // Re-aiming during cooldown is refused up front; no aim, turn or resource.
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    const turn_after = g.sim.turn;
    const res_after = g.sim.hero.resource;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expectEqual(turn_after, g.sim.turn);
    try std.testing.expectEqual(res_after, g.sim.hero.resource);
    try std.testing.expect(!g.isAiming());
}

test "tome game: space confirms, switch key changes aim, self talent releases" {
    const gpa = std.testing.allocator;
    const g = try TomeGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    addGameEnemy(g, 1, 0, "骷髅兵");

    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    const turn = g.sim.turn;
    g.update(.{ .talent = 1 }, 1.0 / 60.0); // switch to 冲锋, no cast
    try std.testing.expect(g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqualStrings("冲锋", g.hud_state.aim.talent);
    try std.testing.expectEqual(@as(u16, 0), g.sim.hero.cooldowns[1]);

    g.update(.{ .confirm = true }, 1.0 / 60.0); // SPACE confirms
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn + 1, g.sim.turn);
    try std.testing.expect(g.sim.hero.cooldowns[1] > 0);
    try std.testing.expectEqual(@as(u16, 0), g.sim.hero.cooldowns[0]);

    // 战吼 is not targeted: pressed while aiming it releases immediately.
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(g.isAiming());
    const turn2 = g.sim.turn;
    g.update(.{ .talent = 2 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn2 + 1, g.sim.turn);
    try std.testing.expect(g.sim.hero.cooldowns[2] > 0);
}

test "tome game: tab cycles the aim target without spending a turn" {
    const gpa = std.testing.allocator;
    const g = try TomeGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    addGameEnemy(g, 1, 0, "骷髅兵");
    addGameEnemy(g, -1, 0, "幽魂");

    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    const turn = g.sim.turn;
    try std.testing.expectEqualStrings("骷髅兵", g.hud_state.aim.target);
    g.update(.{ .target_next = true }, 1.0 / 60.0);
    try std.testing.expect(g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqualStrings("幽魂", g.hud_state.aim.target);
}

test "tome game: cancel and invalid confirms never spend a turn or resource" {
    const gpa = std.testing.allocator;
    const g = try TomeGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();

    // No living enemy at all.
    g.sim.enemy_count = 0;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(g.isAiming());
    try std.testing.expect(!g.hud_state.aim.valid);
    try std.testing.expectEqualStrings("无效目标", g.hud_state.aim.reason);
    const t0 = g.sim.turn;
    const r0 = g.sim.hero.resource;
    g.update(.{ .confirm = true }, 1.0 / 60.0);
    try std.testing.expectEqual(t0, g.sim.turn);
    try std.testing.expectEqual(r0, g.sim.hero.resource);
    try std.testing.expect(g.isAiming());

    // Esc path: consume the aim, spend nothing, stay in the run.
    try std.testing.expect(g.cancelAim());
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(t0, g.sim.turn);
    try std.testing.expectEqual(r0, g.sim.hero.resource);
    try std.testing.expect(!g.cancelAim());
    try std.testing.expectEqual(sim_mod.State.playing, g.sim.state);
    g.update(.{}, 1.0 / 60.0);
    try std.testing.expect(!g.hud_state.aim.active);

    // Out of range (5 cells for 重击).
    g.restart();
    const hero = g.sim.hero.pos;
    const far_dx: i32 = if (hero.x + 5 < sim_mod.grid_w) 5 else -5;
    addGameEnemy(g, far_dx, 0, "骷髅兵");
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.hud_state.aim.valid);
    try std.testing.expectEqualStrings("超出范围", g.hud_state.aim.reason);
    var turn = g.sim.turn;
    var res = g.sim.hero.resource;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource);
    try std.testing.expect(g.isAiming());

    // Wall between hero and target: LOS blocks confirmation. 冲锋 has enough
    // range to reach the cell, so line of sight is the failing check.
    g.restart();
    addGameEnemy(g, 2, 0, "骷髅兵");
    const wall_x = g.sim.hero.pos.x + 1;
    g.sim.blocked[@as(usize, @intCast(g.sim.hero.pos.y)) * sim_mod.grid_w + @as(usize, @intCast(wall_x))] = true;
    g.update(.{ .talent = 1 }, 1.0 / 60.0);
    try std.testing.expect(!g.hud_state.aim.valid);
    try std.testing.expectEqualStrings("视线受阻", g.hud_state.aim.reason);
    turn = g.sim.turn;
    res = g.sim.hero.resource;
    g.update(.{ .talent = 1 }, 1.0 / 60.0);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource);

    // Insufficient resource: refuse to enter aim at all.
    g.restart();
    addGameEnemy(g, 1, 0, "骷髅兵");
    g.sim.hero.resource = 0;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    turn = g.sim.turn;
    res = g.sim.hero.resource;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource);
}

test "tome game: untargeted talents still release immediately without aim" {
    const gpa = std.testing.allocator;
    const g = try TomeGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    addGameEnemy(g, 1, 0, "骷髅兵");

    const turn = g.sim.turn;
    g.update(.{ .talent = 2 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn + 1, g.sim.turn);
    try std.testing.expect(g.sim.hero.cooldowns[2] > 0);
    try std.testing.expect(g.sim.hero.buff_turns > 0);
}

test "tome game: save/load round-trips the sim and gear" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const sim_path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "run.json" });
    defer alloc.free(sim_path);
    const gear_path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "gear.json" });
    defer alloc.free(gear_path);

    const g = try TomeGame.create(alloc, 320, 180, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    _ = g.sim.wait();
    g.sim.hero.hp = 77;
    if (g.content.items.len == 0) return error.SkipZigTest;
    if (!g.inventory.pickup(0)) return error.SkipZigTest;
    const turn = g.sim.turn;
    const rng_state = g.loot_rng.s;
    g.saveRun(io, sim_path, gear_path);

    g.sim.hero.hp = 1;
    g.inventory = items_mod.Inventory.init();
    g.loadRun(io, sim_path, gear_path);
    try std.testing.expectEqual(@as(f32, 77), g.sim.hero.hp);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(@as(usize, 1), g.inventory.len);
    try std.testing.expect(std.meta.eql(rng_state, g.loot_rng.s));
}

test "tome game: H toggles help without spending a turn" {
    const gpa = std.testing.allocator;
    const g = try TomeGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    const turn = g.sim.turn;
    g.update(.{ .help = true }, 1.0 / 60.0);
    try std.testing.expect(g.show_help);
    try std.testing.expectEqual(turn, g.sim.turn);
    g.update(.{ .help = true }, 1.0 / 60.0);
    try std.testing.expect(!g.show_help);
    try std.testing.expectEqual(turn, g.sim.turn);
}

test "tome game: aim refuses cooldown/resource-blocked talents" {
    const gpa = std.testing.allocator;
    const g = try TomeGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    g.sim.hero.cooldowns[0] = 2;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    g.sim.hero.cooldowns[0] = 0;
    g.sim.hero.resource = 0;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
}

test "tome game: held repeat is throttled to one step per 0.3s" {
    const gpa = std.testing.allocator;
    const g = try TomeGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    var dx: i32 = 0;
    var dy: i32 = 0;
    const dirs = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
    for (dirs) |d| {
        if (g.sim.canMove(d[0], d[1])) {
            dx = d[0];
            dy = d[1];
            break;
        }
    }
    if (dx == 0 and dy == 0) return error.SkipZigTest;
    g.update(.{ .step_x = dx, .step_y = dy }, 1.0 / 60.0);
    const turn = g.sim.turn;
    g.update(.{ .step_x = dx, .step_y = dy }, 1.0 / 60.0);
    try std.testing.expectEqual(turn, g.sim.turn);
    g.update(.{ .step_x = dx, .step_y = dy }, 0.31);
    try std.testing.expect(g.sim.turn >= turn);
}
