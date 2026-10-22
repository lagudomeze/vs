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
const hud = @import("tome_hud.zig");
const content_mod = @import("content.zig");
const items_mod = @import("items.zig");
const attributes = @import("attributes.zig");

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
    wait: bool = false,
    inventory: bool = false,
    character: bool = false,
    target_next: bool = false,
    restart: bool = false,
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
    seed: u64,
    class: sim_mod.Class,
    hero_vis: Visual = .{},
    enemy_vis: [sim_mod.max_enemies]Visual = undefined,
    mesh_floor: u8 = 0,
    panel: hud.Panel = .none,
    hud_state: hud.State = .{},
    time: f32 = 0,
    dt: f32 = 0,
    frame: u32 = 0,
    fps: f32 = 60,
    frame_ms: f32 = 16.6,
    show_hud: bool = true,
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

    pub fn restart(self: *TomeGame) void {
        self.sim.reset(self.seed, self.class);
        self.inventory = items_mod.Inventory.init();
        self.mods.clear();
        self.chest_loot_seen = 0;
        self.kill_loot_seen = 0;
        self.last_level = 1;
        self.selected = null;
        self.panel = .none;
        self.rebuildMesh();
        self.resetVisuals();
        self.fillHudState();
    }

    fn classOf(self: *const TomeGame) attributes.Class {
        return switch (self.class) {
            .warrior => .warrior,
            .mage => .mage,
            .chronomancer => .chronomancer,
        };
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
        if (self.sim.state != .playing or self.panel != .none) return;
        const hero = self.sim.hero.pos;

        // adjacent enemy: bump attack
        const dirs = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
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
            if (def.allowsClass(self.classOf()) and self.inventory.equipped.get(slot) == null) {
                self.inventory.equip(self.content.items, item) catch {};
                self.rebuildMods();
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

        if (input.restart) self.restart();
        if (input.target_next) self.cycleTarget();

        if (input.inventory) {
            self.panel = if (self.panel == .inventory) .none else .inventory;
        }
        if (input.character) {
            self.panel = if (self.panel == .character) .none else .character;
        }

        if (self.panel == .none and self.sim.state == .playing) {
            if (input.step_x != 0 or input.step_y != 0) {
                const before_hero = self.sim.hero.hp;
                var before: [sim_mod.max_enemies]f32 = undefined;
                var bi: usize = 0;
                while (bi < self.sim.enemy_count) : (bi += 1) before[bi] = self.sim.enemies[bi].hp;
                _ = self.sim.move(input.step_x, input.step_y);
                self.flashAfter(before_hero, before[0..self.sim.enemy_count]);
                if (input.step_x != 0 or input.step_y != 0) {
                    self.hero_vis.target_yaw = std.math.atan2(@as(f32, @floatFromInt(input.step_x)), @as(f32, @floatFromInt(input.step_y)));
                }
            } else if (input.wait) {
                _ = self.sim.wait();
            } else if (input.talent >= 0) {
                const idx: usize = @intCast(input.talent);
                const before_hero = self.sim.hero.hp;
                var before: [sim_mod.max_enemies]f32 = undefined;
                var bi: usize = 0;
                while (bi < self.sim.enemy_count) : (bi += 1) before[bi] = self.sim.enemies[bi].hp;
                if (self.sim.useTalentOn(idx, self.selected)) {
                    self.hero_vis.anim.cast = 1.0;
                    self.flashAfter(before_hero, before[0..self.sim.enemy_count]);
                }
            }
        }

        self.processLoot();
        if (self.sim.hero.level != self.last_level) {
            self.last_level = self.sim.hero.level;
            self.rebuildMods();
        }

        if (self.sim.floor != self.mesh_floor) {
            self.rebuildMesh();
            self.syncVisuals(true);
        }

        self.syncVisuals(false);
        self.updateVisuals(dt);
        // Keep the whole room on screen while still following the hero:
        // clamp the look-at point to the middle band and bias it toward the hero.
        self.camera.target.x = std.math.clamp(self.hero_vis.pos.x * 0.65, -2.8, 2.8);
        self.camera.target.z = std.math.clamp(self.hero_vis.pos.z * 0.65, -2.8, 2.8);
        self.camera.target.y = 0.35;
        self.camera_target = self.camera.target;
        self.fillHudState();
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

    fn flashAfter(self: *TomeGame, hero_before: f32, enemies_before: []const f32) void {
        if (self.sim.hero.hp < hero_before - 0.01) self.hero_vis.flash = 0.22;
        var i: usize = 0;
        while (i < enemies_before.len and i < self.sim.enemy_count) : (i += 1) {
            if (self.sim.enemies[i].hp < enemies_before[i] - 0.01) self.enemy_vis[i].flash = 0.22;
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
        self.drawWorldBars();
        if (self.show_hud) hud.draw(&self.renderer, self.hud_state);
    }

    fn drawWorldBars(self: *TomeGame) void {
        const w: i32 = @intCast(self.renderer.width);
        const h: i32 = @intCast(self.renderer.height);
        if (self.camera.project(tilePos(self.sim.stairs.x, self.sim.stairs.y).add(math.Vec3.init(0, 1.0, 0)), self.renderer.width, self.renderer.height)) |sp| {
            if (sp.depth > 0.1) {
                const sx: i32 = @intFromFloat(sp.x);
                const sy: i32 = @intFromFloat(sp.y);
                const label = "楼梯";
                const tw = renderer.Renderer.textWidth(label, 1);
                self.renderer.fillRect(sx - @divTrunc(tw, 2) - 3, sy - 12, tw + 6, 12, palette.panel);
                self.renderer.strokeRect(sx - @divTrunc(tw, 2) - 3, sy - 12, tw + 6, 12, palette.cyan);
                self.renderer.drawText(sx - @divTrunc(tw, 2), sy - 11, label, palette.cyan_light, 1, true);
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
            const bw: i32 = 22;
            self.renderer.fillRect(x - @divTrunc(bw, 2), y, bw, 3, palette.deep);
            const frac = if (e.hp_max > 0) std.math.clamp(e.hp / e.hp_max, 0, 1) else 0;
            const fill: i32 = @intFromFloat(@as(f32, @floatFromInt(bw - 2)) * frac);
            if (fill > 0) self.renderer.fillRect(x - @divTrunc(bw, 2) + 1, y + 1, fill, 1, palette.red);
            self.renderer.strokeRect(x - @divTrunc(bw, 2), y, bw, 3, palette.muted);
            if (target != null and target.? == i) {
                const tw = renderer.Renderer.textWidth(e.name, 1);
                self.renderer.fillRect(x - @divTrunc(tw, 2) - 3, y - 13, tw + 6, 11, palette.panel);
                self.renderer.strokeRect(x - @divTrunc(tw, 2) - 3, y - 13, tw + 6, 11, palette.border);
                self.renderer.drawText(x - @divTrunc(tw, 2), y - 12, e.name, palette.red, 1, true);
            }
            const dx = e.pos.x - self.sim.hero.pos.x;
            const dy = e.pos.y - self.sim.hero.pos.y;
            if (@abs(dx) + @abs(dy) == 1) {
                self.renderer.drawText(x - 2, y + 5, "!", palette.gold_light, 1, true);
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
            .panel = self.panel,
            .dead = self.sim.state == .dead,
            .victory = self.sim.state == .victory,
        };
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            self.hud_state.hotbar[i] = .{
                .name = self.sim.talentName(i),
                .cost = self.sim.talentCost(i),
                .cooldown = self.sim.hero.cooldowns[i],
                .ready = self.sim.hero.cooldowns[i] == 0 and self.sim.hero.resource >= @as(f32, @floatFromInt(self.sim.talentCost(i))),
            };
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
