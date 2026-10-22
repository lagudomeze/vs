//! Game controller: ECS world setup, diorama layout, input, simulation, render.
const std = @import("std");
const ecs = @import("zflecs");
const math = @import("../core/math.zig");
const color = @import("../core/color.zig");
const palette = @import("../core/palette.zig");
const png = @import("../core/png.zig");
const model_mod = @import("../engine/model.zig");
const rig = @import("../engine/rig.zig");
const arena_mesh = @import("../engine/arena_mesh.zig");
const renderer = @import("../engine/renderer.zig");
const assets = @import("assets");
const comp = @import("components.zig");
const systems = @import("systems.zig");
const hud = @import("hud.zig");

pub const class_names = [_][]const u8{ "狂战士", "元素法师", "时空法师" };
pub const party_size = 3;
pub const max_dust = 84;
pub const max_embers = 56;
pub const max_sparks = 128;
pub const max_enemies = 24;
pub const max_floats = 32;

pub const InputFrame = struct {
    move_x: f32 = 0,
    move_z: f32 = 0,
    yaw_delta: f32 = 0,
    zoom_delta: f32 = 0,
    toggle_hero: bool = false,
    cast: bool = false,
    interrupt: bool = false,
    inventory: bool = false,
    reset: bool = false,
};

const Dust = struct { base: math.Vec3, phase: f32, speed: f32, size: f32 };
const Ember = struct { brazier: u8, phase: f32, speed: f32 };
const Spark = struct {
    pos: math.Vec3,
    vel: math.Vec3,
    life: f32 = 0,
    max_life: f32 = 1,
    size: f32 = 1,
    color: u32 = 0xffffff,
    active: bool = false,
};

const HeroGlow = struct {
    pos: math.Vec3,
    color: u32,
    intensity: f32,
    size: f32,
};

const FloatText = struct {
    pos: math.Vec3,
    value: i32,
    crit: bool,
    signed: bool,
    life: f32,
    max_life: f32,
    color: u32,
    active: bool = false,
};

const SpawnSpec = struct {
    kind: u8,
    pos: math.Vec3,
};

pub const Game = struct {
    gpa: std.mem.Allocator,
    arena_alloc: std.heap.ArenaAllocator,
    world: *ecs.world_t,
    models: model_mod.ModelDb,
    mesh: arena_mesh.Mesh,
    renderer: renderer.Renderer,
    ctx: systems.Context,

    camera: math.OrbitCamera = .{},
    camera_target: math.Vec3 = math.Vec3.init(0, 0.58, 0.2),
    party: [party_size]ecs.entity_t = .{ 0, 0, 0 },
    active_index: usize = 0,
    active: ecs.entity_t = 0,

    time: f32 = 0,
    dt: f32 = 0,
    frame: u32 = 0,
    fps: f32 = 60,
    frame_ms: f32 = 16.6,
    debug: bool = false,
    show_hud: bool = true,
    inventory_open: bool = false,
    prop_seq: u16 = 0,
    braziers: [4]math.Vec3 = undefined,

    dust: [max_dust]Dust = undefined,
    embers: [max_embers]Ember = undefined,
    sparks: [max_sparks]Spark = undefined,
    spark_cursor: usize = 0,

    hero_glows: [party_size]HeroGlow = undefined,
    hero_glow_count: usize = 0,
    hud_state: hud.State = undefined,

    // combat / waves
    wave: u8 = 0,
    max_waves: u8 = 5,
    kills: u32 = 0,
    intermission: f32 = 0,
    banner_time: f32 = 0,
    banner_buf: [32]u8 = undefined,
    victory: bool = false,
    defeat: bool = false,
    spawn_queue: [8]SpawnSpec = undefined,
    spawn_count: usize = 0,
    spawn_index: usize = 0,
    spawn_timer: f32 = 0,
    enemy_id_seq: u16 = 0,
    target: ecs.entity_t = 0,
    floats: [max_floats]FloatText = undefined,
    float_cursor: usize = 0,

    // tactical layer (populated by the action/time module)
    tactical_mode: u8 = 1, // 0 frozen, 1 flowing, 2 threat
    threat_text: []const u8 = "",
    threat_time: f32 = 0,
    log_buf: [6][72]u8 = undefined,
    log_len: [6]u16 = .{ 0, 0, 0, 0, 0, 0 },
    log_head: usize = 0,
    log_total: usize = 0,

    pub fn create(gpa: std.mem.Allocator, width: u32, height: u32) !*Game {
        const self = try gpa.create(Game);
        errdefer gpa.destroy(self);
        self.* = .{
            .gpa = gpa,
            .arena_alloc = std.heap.ArenaAllocator.init(gpa),
            .world = undefined,
            .models = undefined,
            .mesh = undefined,
            .renderer = undefined,
            .ctx = .{},
        };
        try self.setup(width, height);
        return self;
    }

    fn setup(self: *Game, width: u32, height: u32) !void {
        const alloc = self.arena_alloc.allocator();
        self.world = ecs.init();
        inline for (comp.all) |T| {
            ecs.COMPONENT(self.world, T);
        }
        self.models = try model_mod.ModelDb.init(alloc, assets.all);
        self.mesh = try arena_mesh.buildArena(alloc);
        self.renderer = try renderer.Renderer.init(self.gpa, width, height);
        self.ctx.models = &self.models;
        systems.setContext(&self.ctx);
        systems.register(self.world);

        self.camera = .{
            .target = math.Vec3.init(0, 0.58, 0.2),
            .yaw = -0.35,
            .pitch = 0.70,
            .distance = 8.2,
            .fov = 0.76,
        };
        self.camera_target = self.camera.target;

        self.initParticles();
        try self.spawnArena();
        try self.spawnParty();
        self.resetRun();
        self.fillHudState();
    }

    pub fn destroy(self: *Game) void {
        const world = self.world;
        self.renderer.deinit();
        self.arena_alloc.deinit();
        _ = ecs.fini(world);
        const gpa = self.gpa;
        gpa.destroy(self);
    }

    // ------------------------------------------------------------- particles
    fn initParticles(self: *Game) void {
        var i: usize = 0;
        while (i < max_dust) : (i += 1) {
            const h1 = color.hashFloat(@as(u32, @intCast(i)) * 7919 + 17);
            const h2 = color.hashFloat(@as(u32, @intCast(i)) * 104729 + 31);
            const h3 = color.hashFloat(@as(u32, @intCast(i)) * 1299709 + 53);
            self.dust[i] = .{
                .base = math.Vec3.init((h1 - 0.5) * 13.0, 0.25 + h2 * 2.2, (h3 - 0.5) * 13.0),
                .phase = h1 * 6.28,
                .speed = 0.15 + h2 * 0.4,
                .size = 0.018 + h3 * 0.018,
            };
        }
        i = 0;
        while (i < max_embers) : (i += 1) {
            const h = color.hashFloat(@as(u32, @intCast(i)) * 31337 + 7);
            self.embers[i] = .{
                .brazier = @intCast(i % 4),
                .phase = h,
                .speed = 0.35 + h * 0.35,
            };
        }
        for (&self.sparks) |*s| s.* = .{ .pos = math.Vec3.zero, .vel = math.Vec3.zero };
        for (&self.floats) |*ft| ft.* = .{ .pos = math.Vec3.zero, .value = 0, .crit = false, .signed = false, .life = 0, .max_life = 1, .color = 0, .active = false };
    }

    // ----------------------------------------------------------------- arena
    fn spawnPropEntity(self: *Game, name: []const u8, pos: math.Vec3, yaw: f32, scale: f32, shadow: f32) ecs.entity_t {
        const idx = self.models.indexOf(name) orelse return 0;
        const e = ecs.new_id(self.world);
        self.prop_seq += 1;
        _ = ecs.set(self.world, e, comp.Transform, .{ .pos = pos, .yaw = yaw, .scale = scale });
        _ = ecs.set(self.world, e, comp.Renderable, .{ .model = idx, .id = 20 + self.prop_seq });
        if (shadow > 0) _ = ecs.set(self.world, e, comp.Shadow, .{ .radius = shadow });
        return e;
    }

    fn spawnBrazier(self: *Game, slot: usize, pos: math.Vec3) !void {
        self.braziers[slot] = pos;
        const e = self.spawnPropEntity("brazier", pos, 0, 1.0, 0.34);
        if (e == 0) return;
        self.prop_seq += 1;
        _ = ecs.set(self.world, e, comp.LightSource, .{
            .color = .{ .x = 1.0, .y = 0.45, .z = 0.13 },
            .intensity = 3.2,
            .radius = 5.8,
            .height = 0.50,
            .flicker = 0.32,
            .phase = color.hashFloat(@as(u32, @intCast(slot)) * 999 + 3) * 6.28,
        });
    }

    fn spawnPylon(self: *Game, slot: usize, pos: math.Vec3) !void {
        const e = self.spawnPropEntity("pylon", pos, color.hashFloat(@as(u32, @intCast(slot)) * 71 + 9) * 6.28, 1.05, 0.42);
        if (e == 0) return;
        _ = ecs.set(self.world, e, comp.LightSource, .{
            .color = .{ .x = 0.26, .y = 0.92, .z = 0.90 },
            .intensity = 1.25,
            .radius = 6.2,
            .height = 1.72,
            .flicker = 0.12,
            .phase = color.hashFloat(@as(u32, @intCast(slot)) * 313 + 11) * 6.28,
        });
    }

    fn spawnArena(self: *Game) !void {
        // four braziers frame the party and cast warm pools of light
        try self.spawnBrazier(0, math.Vec3.init(-2.95, 0, -1.55));
        try self.spawnBrazier(1, math.Vec3.init(2.95, 0, -1.55));
        try self.spawnBrazier(2, math.Vec3.init(-2.95, 0, 1.85));
        try self.spawnBrazier(3, math.Vec3.init(2.95, 0, 1.85));

        // four arcane pylons frame the diorama and light it from above
        try self.spawnPylon(0, math.Vec3.init(-3.65, 0, -2.85));
        try self.spawnPylon(1, math.Vec3.init(3.65, 0, -2.85));
        try self.spawnPylon(2, math.Vec3.init(-4.35, 0, 2.55));
        try self.spawnPylon(3, math.Vec3.init(4.35, 0, 2.55));

        const rim_y: f32 = 0.18;
        // corner columns on the rim
        _ = self.spawnPropEntity("column", math.Vec3.init(-5.85, rim_y, -5.85), 0, 1.0, 0.26);
        _ = self.spawnPropEntity("column", math.Vec3.init(5.85, rim_y, -5.85), 0, 1.0, 0.26);
        _ = self.spawnPropEntity("column_damaged", math.Vec3.init(-5.85, rim_y, 5.85), 0, 1.0, 0.26);
        _ = self.spawnPropEntity("column", math.Vec3.init(5.85, rim_y, 5.85), 0, 1.0, 0.26);

        // statues watch the arena
        _ = self.spawnPropEntity("statue", math.Vec3.init(-5.55, rim_y, -2.85), 2.2, 0.95, 0.34);
        _ = self.spawnPropEntity("statue", math.Vec3.init(5.55, rim_y, 2.85), -0.95, 0.95, 0.34);

        // backdrop shrines behind the party
        _ = self.spawnPropEntity("statue", math.Vec3.init(-2.35, 0, -2.95), 1.9, 0.92, 0.28);
        _ = self.spawnPropEntity("statue", math.Vec3.init(2.35, 0, -2.95), -1.9, 0.92, 0.28);
        _ = self.spawnPropEntity("table", math.Vec3.init(0, 0, -2.85), 0.0, 0.78, 0.28);
        _ = self.spawnPropEntity("trophy", math.Vec3.init(0, 0.246, -2.84), 0.0, 0.72, 0.14);

        // mid-ground set dressing that stays in frame while orbiting
        _ = self.spawnPropEntity("weapon_rack", math.Vec3.init(-4.30, 0, 0.65), 1.1, 0.95, 0.28);
        _ = self.spawnPropEntity("barrel", math.Vec3.init(-4.45, 0, 1.55), 0.2, 0.95, 0.28);
        _ = self.spawnPropEntity("chest", math.Vec3.init(4.20, 0, 1.30), -0.8, 0.95, 0.28);
        _ = self.spawnPropEntity("table", math.Vec3.init(4.35, 0, -0.95), 1.9, 0.85, 0.30);
        _ = self.spawnPropEntity("potion", math.Vec3.init(4.35, 0.267, -0.92), 0.0, 0.8, 0.08);
        _ = self.spawnPropEntity("statue", math.Vec3.init(-4.55, 0, -1.55), 1.4, 0.85, 0.30);
        _ = self.spawnPropEntity("statue", math.Vec3.init(4.55, 0, -2.15), -1.8, 0.85, 0.30);

        // west: storage & weapons
        _ = self.spawnPropEntity("barrel", math.Vec3.init(-4.55, 0, 3.55), 0.4, 1.0, 0.30);
        _ = self.spawnPropEntity("barrel", math.Vec3.init(-3.95, 0, 4.15), 1.1, 0.85, 0.27);
        _ = self.spawnPropEntity("weapon_rack", math.Vec3.init(-4.75, 0, -3.35), 0.85, 1.0, 0.30);
        _ = self.spawnPropEntity("weapon_sword", math.Vec3.init(-4.75, 0.47, -3.34), 0.85, 0.9, 0.0);

        // east: study & loot
        _ = self.spawnPropEntity("table", math.Vec3.init(4.40, 0, 3.45), -0.35, 1.0, 0.36);
        _ = self.spawnPropEntity("chair", math.Vec3.init(3.60, 0, 3.05), -1.0, 1.0, 0.24);
        _ = self.spawnPropEntity("potion", math.Vec3.init(4.40, 0.315, 3.42), 0.2, 0.9, 0.08);
        _ = self.spawnPropEntity("chest", math.Vec3.init(4.10, 0, -3.55), -0.55, 1.0, 0.30);
        _ = self.spawnPropEntity("pot", math.Vec3.init(4.95, 0, -2.75), 0.6, 1.0, 0.27);
        _ = self.spawnPropEntity("trophy", math.Vec3.init(5.20, 0, 1.40), 0.2, 1.0, 0.26);
        _ = self.spawnPropEntity("coin", math.Vec3.init(3.45, 0, -3.95), 0, 1.4, 0.16);
        _ = self.spawnPropEntity("coin", math.Vec3.init(3.65, 0, -3.72), 0, 1.2, 0.14);
        _ = self.spawnPropEntity("coin", math.Vec3.init(3.82, 0, -3.92), 0, 1.2, 0.14);

        // rubble and greenery
        _ = self.spawnPropEntity("rocks", math.Vec3.init(3.65, 0, 4.45), 0.3, 1.0, 0.36);
        _ = self.spawnPropEntity("bricks", math.Vec3.init(2.95, 0, 4.05), 0.9, 1.0, 0.32);
        _ = self.spawnPropEntity("rocks", math.Vec3.init(-3.20, 0, -4.20), 1.7, 0.8, 0.32);
        _ = self.spawnPropEntity("tree", math.Vec3.init(-5.65, rim_y, 4.65), 0.4, 0.95, 0.34);

        // floating debris outside the island
        _ = self.spawnPropEntity("rocks", math.Vec3.init(-7.9, -1.35, 2.4), 0.7, 2.0, 0.0);
        _ = self.spawnPropEntity("rocks", math.Vec3.init(7.7, -2.25, -2.2), 1.9, 1.55, 0.0);
        _ = self.spawnPropEntity("rocks", math.Vec3.init(2.2, -2.75, 8.2), 0.2, 1.2, 0.0);

        // magical floor circle
        const rune = self.models.indexOf("rune_circle") orelse 0;
        const e = ecs.new_id(self.world);
        _ = ecs.set(self.world, e, comp.Transform, .{ .pos = math.Vec3.init(0, 0.020, 0), .scale = 0.92 });
        _ = ecs.set(self.world, e, comp.Renderable, .{
            .model = rune,
            .tint = palette.cyan,
            .boost = 0.30,
            .additive = true,
            .id = 0,
        });
    }

    fn spawnHero(self: *Game, index: usize, pos: math.Vec3, yaw: f32) !ecs.entity_t {
        const model_names = [_][]const u8{ "warrior", "archmage", "chronomancer" };
        const model_idx = self.models.indexOf(model_names[index]) orelse return 0;
        const hero_stats = [_]struct {
            hp: f32,
            speed: f32,
            ap_speed: f32,
            damage: f32,
            range: f32,
            cooldown: f32,
            skill_name: []const u8,
            skill_mult: f32,
            skill_range: f32,
            skill_aoe: f32,
            skill_slow: f32,
        }{
            .{ .hp = 148, .speed = 3.15, .ap_speed = 16, .damage = 18, .range = 1.45, .cooldown = 1.05, .skill_name = "重击", .skill_mult = 2.4, .skill_range = 2.0, .skill_aoe = 0, .skill_slow = 0 },
            .{ .hp = 96, .speed = 2.9, .ap_speed = 24, .damage = 11, .range = 5.2, .cooldown = 1.45, .skill_name = "火球", .skill_mult = 3.4, .skill_range = 5.8, .skill_aoe = 1.6, .skill_slow = 0 },
            .{ .hp = 110, .speed = 3.0, .ap_speed = 20, .damage = 14, .range = 4.2, .cooldown = 1.2, .skill_name = "时光箭", .skill_mult = 2.6, .skill_range = 4.8, .skill_aoe = 0, .skill_slow = 2.5 },
        };
        const e = ecs.new_id(self.world);
        _ = ecs.set(self.world, e, comp.Transform, .{ .pos = pos, .yaw = yaw, .scale = 1.40 });
        _ = ecs.set(self.world, e, comp.Velocity, .{});
        _ = ecs.set(self.world, e, comp.MoveIntent, .{});
        _ = ecs.set(self.world, e, comp.Animation, .{ .state = .{ .kind = @intCast(index) } });
        _ = ecs.set(self.world, e, comp.Pose, .{});
        _ = ecs.set(self.world, e, comp.Renderable, .{
            .model = model_idx,
            .id = @intCast(200 + index),
            .emits_light = index > 0,
        });
        _ = ecs.set(self.world, e, comp.Hero, .{
            .class = @intCast(index),
            .level = 12,
            .hp = hero_stats[index].hp,
            .hp_max = hero_stats[index].hp,
            .ap = 100,
            .ap_max = 100,
            .ap_speed = hero_stats[index].ap_speed,
            .move_speed = hero_stats[index].speed,
            .active = index == 0,
            .attack_damage = hero_stats[index].damage,
            .attack_range = hero_stats[index].range,
            .attack_cooldown = hero_stats[index].cooldown,
            .attack_timer = 0.45 + @as(f32, @floatFromInt(index)) * 0.2,
            .skill_name = hero_stats[index].skill_name,
            .skill_mult = hero_stats[index].skill_mult,
            .skill_range = hero_stats[index].skill_range,
            .skill_aoe = hero_stats[index].skill_aoe,
            .skill_slow = hero_stats[index].skill_slow,
        });
        _ = ecs.set(self.world, e, comp.Shadow, .{ .radius = 0.36 });
        return e;
    }

    fn followOffset(class: u8) math.Vec2 {
        return switch (class) {
            0 => .{ .x = 0.0, .y = -1.35 },
            1 => .{ .x = -1.6, .y = -0.18 },
            else => .{ .x = 1.6, .y = -0.18 },
        };
    }

    fn spawnParty(self: *Game) !void {
        self.party[0] = try self.spawnHero(0, math.Vec3.init(0, 0, 0.45), 0.04);
        self.party[1] = try self.spawnHero(1, math.Vec3.init(-1.6, 0, 0.27), -0.06);
        self.party[2] = try self.spawnHero(2, math.Vec3.init(1.6, 0, 0.27), 0.06);
        self.active_index = 0;
        self.active = self.party[0];
        for (self.party, 0..) |e, i| {
            if (i == 0) continue;
            _ = ecs.set(self.world, e, comp.Follow, .{
                .leader = self.party[0],
                .offset = followOffset(@intCast(i)),
            });
        }
        try self.spawnMotes();
        try self.spawnShards();
    }

    fn spawnShard(self: *Game, pos: math.Vec3, scale: f32, tint: u32, speed: f32, phase: f32) !void {
        const mote_idx = self.models.indexOf("mote") orelse return;
        const e = ecs.new_id(self.world);
        _ = ecs.set(self.world, e, comp.Transform, .{ .pos = pos, .yaw = phase, .scale = scale });
        _ = ecs.set(self.world, e, comp.Renderable, .{
            .model = mote_idx,
            .tint = tint,
            .boost = 1.6,
            .additive = true,
            .id = 0,
        });
        _ = ecs.set(self.world, e, comp.Spin, .{ .speed = speed });
    }

    fn spawnShards(self: *Game) !void {
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            const h1 = color.hashFloat(@as(u32, @intCast(i)) * 71 + 5);
            const h2 = color.hashFloat(@as(u32, @intCast(i)) * 131 + 7);
            const h3 = color.hashFloat(@as(u32, @intCast(i)) * 197 + 11);
            const angle = @as(f32, @floatFromInt(i)) / 16.0 * 6.283 + h1 * 0.4;
            const radius = 7.0 + h2 * 3.0;
            const pos = math.Vec3.init(@sin(angle) * radius, 0.35 + h3 * 3.2, @cos(angle) * radius);
            const tint = switch (i % 3) {
                0 => palette.cyan_light,
                1 => palette.gold_light,
                else => color.pack(127, 179, 239),
            };
            try self.spawnShard(pos, 1.4 + h1 * 1.6, tint, 0.2 + h2 * 0.35, h3 * 6.28);
        }
    }

    fn spawnMote(self: *Game, center: ecs.entity_t, tint: u32, radius: f32, height: f32, speed: f32, phase: f32) !void {
        const mote_idx = self.models.indexOf("mote") orelse return;
        const e = ecs.new_id(self.world);
        _ = ecs.set(self.world, e, comp.Transform, .{ .pos = math.Vec3.init(0, height, 0), .scale = 0.95 });
        _ = ecs.set(self.world, e, comp.Renderable, .{
            .model = mote_idx,
            .tint = tint,
            .boost = 1.7,
            .additive = true,
            .id = 0,
        });
        _ = ecs.set(self.world, e, comp.Mote, .{
            .center = center,
            .radius = radius,
            .speed = speed,
            .phase = phase,
            .height = height,
            .spin = 0.7,
        });
    }

    fn spawnMotes(self: *Game) !void {
        // archmage: elemental shards
        try self.spawnMote(self.party[1], color.pack(255, 159, 28), 0.36, 0.86, 1.35, 0.0);
        try self.spawnMote(self.party[1], color.pack(111, 224, 208), 0.41, 1.02, 1.05, 2.1);
        try self.spawnMote(self.party[1], color.pack(255, 242, 168), 0.33, 0.72, 1.7, 4.2);
        // chronomancer: time motes
        try self.spawnMote(self.party[2], color.pack(111, 224, 208), 0.42, 0.78, 1.15, 1.0);
        try self.spawnMote(self.party[2], color.pack(127, 179, 239), 0.48, 0.95, 0.85, 3.4);
    }

    // ------------------------------------------------------------ combat/waves
    fn pushLog(self: *Game, comptime fmt: []const u8, args: anytype) void {
        const slot = self.log_head;
        const text = std.fmt.bufPrint(&self.log_buf[slot], fmt, args) catch return;
        self.log_len[slot] = @intCast(text.len);
        self.log_head = (slot + 1) % self.log_buf.len;
        if (self.log_total < self.log_buf.len) self.log_total += 1;
    }

    fn resetRun(self: *Game) void {
        self.clearEnemies();
        self.kills = 0;
        self.victory = false;
        self.defeat = false;
        self.banner_time = 0;
        self.intermission = 0;
        self.target = 0;
        self.wave = 0;
        for (&self.sparks) |*s| s.active = false;
        for (&self.floats) |*ft| ft.active = false;

        const starts = [_]math.Vec3{
            math.Vec3.init(0, 0, 0.45),
            math.Vec3.init(-1.6, 0, 0.27),
            math.Vec3.init(1.6, 0, 0.27),
        };
        for (self.party, 0..) |e, i| {
            if (e == 0) continue;
            _ = ecs.set(self.world, e, comp.Transform, .{ .pos = starts[i], .yaw = 0.04, .scale = 1.40 });
            _ = ecs.set(self.world, e, comp.Velocity, .{});
            _ = ecs.set(self.world, e, comp.MoveIntent, .{});
            if (ecs.get_mut(self.world, e, comp.Hero)) |h| {
                h.hp = h.hp_max;
                h.ap = h.ap_max;
                h.downed = false;
                h.revive_timer = 0;
                h.attack_timer = 0.3 + @as(f32, @floatFromInt(i)) * 0.2;
                h.active = i == 0;
            }
            if (ecs.get_mut(self.world, e, comp.Renderable)) |r| r.tint = 0xffffff;
            if (ecs.get_mut(self.world, e, comp.Animation)) |a| {
                a.state.cast = 0;
                a.state.moving = 0;
            }
            if (i == 0) {
                ecs.remove(self.world, e, comp.Follow);
            } else {
                _ = ecs.set(self.world, e, comp.Follow, .{ .leader = self.party[0], .offset = followOffset(@intCast(i)) });
            }
        }
        self.active_index = 0;
        self.active = self.party[0];
        self.camera_target = math.Vec3.init(0, 0.58, 0.2);
        self.camera.target = self.camera_target;
        self.ctx.combat_active = true;
        self.beginWave(1);
    }

    fn beginWave(self: *Game, wave: u8) void {
        self.wave = wave;
        self.pushLog("第{d}波来袭", .{wave});
        self.spawn_index = 0;
        self.spawn_timer = 0;
        self.intermission = 0;
        self.banner_time = 2.6;
        self.queueWave(wave);
    }

    fn queueWave(self: *Game, wave: u8) void {
        const defs: []const u8 = switch (wave) {
            1 => &[_]u8{ 0, 0, 0 },
            2 => &[_]u8{ 0, 0, 0, 1, 1 },
            3 => &[_]u8{ 1, 1, 2, 2 },
            4 => &[_]u8{ 0, 0, 0, 0, 2, 2 },
            else => &[_]u8{ 3, 1, 1 },
        };
        self.spawn_count = defs.len;
        for (defs, 0..) |kind, i| {
            const angle = @as(f32, @floatFromInt(i)) * 2.399 + @as(f32, @floatFromInt(wave)) * 0.77;
            const radius = 3.95 + @as(f32, @floatFromInt(i % 2)) * 0.30;
            self.spawn_queue[i] = .{
                .kind = kind,
                .pos = math.Vec3.init(@sin(angle) * radius, 0, @cos(angle) * radius),
            };
        }
    }

    fn spawnEnemy(self: *Game, kind: u8, pos: math.Vec3) !void {
        const names = [_][]const u8{ "skeleton", "wraith", "golem", "abyss_guard" };
        const model_idx = self.models.indexOf(names[kind]) orelse return;
        const Stats = struct { hp: f32, dmg: f32, speed: f32, range: f32, cd: f32, scale: f32 };
        const s: Stats = switch (kind) {
            0 => .{ .hp = 44, .dmg = 5, .speed = 1.90, .range = 1.10, .cd = 1.40, .scale = 1.18 },
            1 => .{ .hp = 58, .dmg = 7, .speed = 1.60, .range = 3.80, .cd = 2.10, .scale = 1.32 },
            2 => .{ .hp = 92, .dmg = 10, .speed = 1.15, .range = 1.25, .cd = 2.30, .scale = 1.55 },
            else => .{ .hp = 220, .dmg = 13, .speed = 1.00, .range = 1.70, .cd = 2.00, .scale = 1.95 },
        };
        const e = ecs.new_id(self.world);
        const yaw = std.math.atan2(-pos.x, -pos.z);
        _ = ecs.set(self.world, e, comp.Transform, .{ .pos = pos, .yaw = yaw, .scale = s.scale });
        _ = ecs.set(self.world, e, comp.Velocity, .{});
        _ = ecs.set(self.world, e, comp.MoveIntent, .{});
        _ = ecs.set(self.world, e, comp.Animation, .{ .state = .{ .kind = 3 + kind } });
        _ = ecs.set(self.world, e, comp.Pose, .{});
        self.enemy_id_seq +%= 1;
        _ = ecs.set(self.world, e, comp.Renderable, .{
            .model = model_idx,
            .tint = if (kind == 3) color.pack(255, 218, 208) else 0xffffff,
            .id = @intCast(300 + self.enemy_id_seq % 400),
        });
        _ = ecs.set(self.world, e, comp.Enemy, .{
            .kind = kind,
            .hp = s.hp,
            .hp_max = s.hp,
            .damage = s.dmg,
            .move_speed = s.speed,
            .attack_range = s.range,
            .attack_cooldown = s.cd,
            .attack_timer = 0.5 + color.hashFloat(self.frame * 37 + @as(u32, @intCast(self.enemy_id_seq))) * 0.6,
            .boss = kind == 3,
        });
        _ = ecs.set(self.world, e, comp.Shadow, .{ .radius = 0.34 * s.scale });
        if (kind == 3) {
            _ = ecs.set(self.world, e, comp.LightSource, .{
                .color = .{ .x = 1.0, .y = 0.20, .z = 0.16 },
                .intensity = 1.25,
                .radius = 3.4,
                .height = 1.0,
                .flicker = 0.08,
            });
        }
        self.spawnBurst(pos.add(math.Vec3.init(0, 0.6, 0)), color.pack(255, 150, 80), 8, 0.8);
    }

    pub fn enemyCount(self: *Game) u32 {
        var n: u32 = 0;
        var it = ecs.each(self.world, comp.Enemy);
        while (ecs.each_next(&it)) {
            n += @intCast(it.entities().len);
        }
        return n;
    }

    fn clearEnemies(self: *Game) void {
        var dead: [max_enemies]ecs.entity_t = undefined;
        var n: usize = 0;
        var it = ecs.each(self.world, comp.Enemy);
        while (ecs.each_next(&it)) {
            for (it.entities()) |e| {
                if (n < dead.len) {
                    dead[n] = e;
                    n += 1;
                }
            }
        }
        for (dead[0..n]) |e| _ = ecs.delete(self.world, e);
        self.target = 0;
    }

    fn cleanupEnemies(self: *Game) void {
        var dead: [max_enemies]ecs.entity_t = undefined;
        var n: usize = 0;
        var it = ecs.each(self.world, comp.Enemy);
        while (ecs.each_next(&it)) {
            const enemies = ecs.field(&it, comp.Enemy, 0).?;
            for (enemies, it.entities()) |enemy, e| {
                if (enemy.hp <= 0 and n < dead.len) {
                    dead[n] = e;
                    n += 1;
                }
            }
        }
        for (dead[0..n]) |e| {
            if (self.target == e) self.target = 0;
            _ = ecs.delete(self.world, e);
        }
    }

    fn updateWave(self: *Game) void {
        if (self.victory or self.defeat) {
            self.banner_time = @max(0, self.banner_time - self.dt);
            return;
        }
        self.banner_time = @max(0, self.banner_time - self.dt);
        if (self.intermission > 0) {
            self.intermission -= self.dt;
            if (self.intermission <= 0 and self.wave < self.max_waves) {
                self.beginWave(self.wave + 1);
            }
            return;
        }
        if (self.spawn_index < self.spawn_count) {
            self.spawn_timer -= self.dt;
            if (self.spawn_timer <= 0) {
                const spec = self.spawn_queue[self.spawn_index];
                self.spawn_index += 1;
                self.spawn_timer = 0.30;
                self.spawnEnemy(spec.kind, spec.pos) catch {};
            }
            return;
        }
        if (self.enemyCount() == 0) {
            if (self.wave >= self.max_waves) {
                if (!self.victory) self.pushLog("胜利", .{});
                self.victory = true;
                self.ctx.combat_active = false;
                self.banner_time = 0;
            } else {
                self.restParty();
                self.intermission = 2.0;
            }
        }
    }

    fn restParty(self: *Game) void {
        for (self.party) |e| {
            const h = ecs.get_mut(self.world, e, comp.Hero) orelse continue;
            if (h.downed) {
                h.downed = false;
                h.hp = h.hp_max * 0.5;
                h.ap = @max(h.ap, h.ap_max * 0.4);
                h.revive_timer = 0;
            } else {
                h.hp = @min(h.hp_max, h.hp + h.hp_max * 0.25);
            }
            if (ecs.get_mut(self.world, e, comp.Renderable)) |r| r.tint = 0xffffff;
            if (ecs.get(self.world, e, comp.Transform)) |tr| {
                self.spawnBurst(tr.pos.add(math.Vec3.init(0, 0.6, 0)), palette.cyan_light, 10, 0.9);
            }
        }
    }

    fn spawnBurst(self: *Game, pos: math.Vec3, tint: u32, count: usize, speed: f32) void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const h1 = color.hashFloat(self.frame * 37 + @as(u32, @intCast(i)) * 17 + 3);
            const h2 = color.hashFloat(self.frame * 91 + @as(u32, @intCast(i)) * 29 + 7);
            const angle = h1 * 6.283;
            const spark = &self.sparks[self.spark_cursor];
            self.spark_cursor = (self.spark_cursor + 1) % max_sparks;
            spark.* = .{
                .pos = pos.add(math.Vec3.init((h2 - 0.5) * 0.25, (h1 - 0.5) * 0.25, (h2 - 0.5) * 0.25)),
                .vel = math.Vec3.init(@sin(angle) * speed * (0.6 + h1), 0.6 + h2 * speed, @cos(angle) * speed * (0.6 + h2)),
                .life = 0.35 + h1 * 0.45,
                .max_life = 0.8,
                .size = 0.018 + h2 * 0.022,
                .color = tint,
                .active = true,
            };
        }
    }

    fn spawnFloat(self: *Game, pos: math.Vec3, value: f32, crit: bool, signed: bool, tint: u32) void {
        const ft = &self.floats[self.float_cursor];
        self.float_cursor = (self.float_cursor + 1) % max_floats;
        ft.* = .{
            .pos = pos,
            .value = @intFromFloat(@max(1.0, @round(value))),
            .crit = crit,
            .signed = signed,
            .life = 0.95,
            .max_life = 0.95,
            .color = tint,
            .active = true,
        };
    }

    fn handleEvents(self: *Game) void {
        for (systems.events[0..systems.event_count]) |ev| {
            switch (ev.kind) {
                .enemy_hit => {
                    self.spawnFloat(ev.pos, ev.amount, ev.crit, false, if (ev.crit) palette.gold_light else palette.cream);
                    self.spawnBurst(ev.pos, palette.gold_light, 2, 0.7);
                },
                .hero_hit => {
                    self.spawnFloat(ev.pos, ev.amount, false, true, palette.red);
                    self.spawnBurst(ev.pos, color.pack(220, 70, 70), 2, 0.6);
                },
                .enemy_died => {
                    self.kills += 1;
                    self.pushLog("击杀 +1", .{});
                    self.spawnBurst(ev.pos, palette.gold_light, 20, 1.6);
                    self.spawnBurst(ev.pos, palette.red, 8, 1.1);
                    for (self.party) |e| {
                        if (ecs.get_mut(self.world, e, comp.Hero)) |h| {
                            if (!h.downed) h.hp = @min(h.hp_max, h.hp + 4.0);
                        }
                    }
                },
                .hero_down => {
                    self.pushLog("英雄倒下", .{});
                    self.spawnBurst(ev.pos, color.pack(220, 70, 70), 16, 1.2);
                },
            }
        }
        systems.clearEvents();
    }

    fn updateFloats(self: *Game) void {
        for (&self.floats) |*ft| {
            if (!ft.active) continue;
            ft.life -= self.dt;
            if (ft.life <= 0) ft.active = false;
        }
    }

    fn updateHeroes(self: *Game) void {
        var living: usize = 0;
        for (self.party) |e| {
            const h = ecs.get_mut(self.world, e, comp.Hero) orelse continue;
            if (h.downed and !self.defeat) {
                h.revive_timer -= self.dt;
                if (h.revive_timer <= 0) {
                    h.downed = false;
                    h.hp = h.hp_max * 0.5;
                    h.ap = @min(h.ap_max, 60);
                    h.revive_timer = 0;
                    self.pushLog("英雄复活", .{});
                    if (ecs.get(self.world, e, comp.Transform)) |tr| {
                        self.spawnBurst(tr.pos.add(math.Vec3.init(0, 0.6, 0)), palette.cyan_light, 14, 1.0);
                    }
                }
            }
            if (h.downed) {
                if (ecs.get_mut(self.world, e, comp.Animation)) |a| a.state.moving = 0;
                if (ecs.get_mut(self.world, e, comp.Renderable)) |r| r.tint = color.pack(110, 114, 126);
            } else {
                living += 1;
                if (ecs.get_mut(self.world, e, comp.Renderable)) |r| r.tint = 0xffffff;
            }
        }
        if (living == 0) {
            if (!self.defeat) self.pushLog("全灭", .{});
            self.defeat = true;
            self.ctx.combat_active = false;
            return;
        }
        const active_hero = ecs.get(self.world, self.active, comp.Hero);
        if (active_hero) |h| {
            if (h.downed) {
                for (self.party, 0..) |e, i| {
                    const other = ecs.get(self.world, e, comp.Hero) orelse continue;
                    if (!other.downed) {
                        self.selectHero(i);
                        break;
                    }
                }
            }
        }
    }

    // --------------------------------------------------------------- controls
    fn cycleHero(self: *Game) void {
        const old_index = self.active_index;
        const old = self.party[old_index];
        if (old == 0) return;
        var offset: usize = 1;
        while (offset < party_size) : (offset += 1) {
            const new_index = (old_index + offset) % party_size;
            const new = self.party[new_index];
            const new_hero = ecs.get(self.world, new, comp.Hero) orelse continue;
            if (new_hero.downed) continue;

            if (ecs.get_mut(self.world, old, comp.Hero)) |h| h.active = false;
            if (ecs.get_mut(self.world, new, comp.Hero)) |h| h.active = true;
            _ = ecs.set(self.world, new, comp.MoveIntent, .{});
            _ = ecs.set(self.world, new, comp.Velocity, .{});
            _ = ecs.set(self.world, old, comp.Follow, .{
                .leader = new,
                .offset = followOffset(@intCast(old_index)),
            });
            ecs.remove(self.world, new, comp.Follow);

            self.active_index = new_index;
            self.active = new;
            return;
        }
    }

    pub fn selectHero(self: *Game, index: usize) void {
        if (index >= party_size or index == self.active_index) {
            return;
        }
        const target_entity = self.party[index];
        if (target_entity == 0) return;
        const target_hero = ecs.get(self.world, target_entity, comp.Hero) orelse return;
        if (target_hero.downed) return;
        for (self.party, 0..) |e, i| {
            if (e == 0) continue;
            _ = ecs.set(self.world, e, comp.MoveIntent, .{});
            _ = ecs.set(self.world, e, comp.Velocity, .{});
            if (i == index) {
                if (ecs.get_mut(self.world, e, comp.Hero)) |h| h.active = true;
                ecs.remove(self.world, e, comp.Follow);
            } else {
                if (ecs.get_mut(self.world, e, comp.Hero)) |h| h.active = false;
                _ = ecs.set(self.world, e, comp.Follow, .{
                    .leader = target_entity,
                    .offset = followOffset(@intCast(i)),
                });
            }
        }
        self.active_index = index;
        self.active = target_entity;
        if (ecs.get(self.world, target_entity, comp.Transform)) |tr| {
            self.camera_target = tr.pos.add(math.Vec3.init(0, 0.58, 0));
            self.camera.target = self.camera_target;
        }
    }

    fn tryCast(self: *Game) void {
        if (self.victory or self.defeat) return;
        const hero = ecs.get(self.world, self.active, comp.Hero) orelse return;
        if (hero.downed or hero.ap < 35) return;
        const tr = ecs.get(self.world, self.active, comp.Transform) orelse return;
        const target = systems.nearestEnemy(self.world, tr.pos, hero.skill_range) orelse return;
        const target_tr = ecs.get(self.world, target, comp.Transform) orelse return;

        if (ecs.get_mut(self.world, self.active, comp.Hero)) |h| h.ap -= 35;
        if (ecs.get_mut(self.world, self.active, comp.Animation)) |a| a.state.cast = 1.0;

        const base_color = switch (hero.class) {
            0 => color.pack(255, 212, 94),
            1 => color.pack(255, 159, 28),
            else => color.pack(111, 224, 208),
        };
        const damage = hero.attack_damage * hero.skill_mult;
        _ = systems.damageEnemy(self.world, target, damage, self.time);

        if (hero.skill_aoe > 0) {
            var it = ecs.each(self.world, comp.Enemy);
            while (ecs.each_next(&it)) {
                const enemies = ecs.field(&it, comp.Enemy, 0).?;
                for (enemies, it.entities()) |*enemy, e| {
                    if (e == target or enemy.hp <= 0) continue;
                    const etr = ecs.get(self.world, e, comp.Transform) orelse continue;
                    const dx = etr.pos.x - target_tr.pos.x;
                    const dz = etr.pos.z - target_tr.pos.z;
                    if (dx * dx + dz * dz <= hero.skill_aoe * hero.skill_aoe) {
                        _ = systems.damageEnemy(self.world, e, damage * 0.55, self.time);
                    }
                }
            }
        }
        if (hero.skill_slow > 0) {
            if (ecs.get_mut(self.world, target, comp.Enemy)) |enemy| enemy.slow_timer = hero.skill_slow;
        }

        self.spawnBurst(target_tr.pos.add(math.Vec3.init(0, 0.8, 0)), base_color, 22, 1.6);
        self.spawnBurst(tr.pos.add(math.Vec3.init(0, 0.9, 0)), base_color, 12, 0.9);
        self.target = target;
    }

    /// Documentation / class-showcase mode: line the party up and bring the
    /// camera down for a clean look at the three hero meshes.
    pub fn lineup(self: *Game) void {
        self.clearEnemies();
        self.ctx.combat_active = false;
        self.victory = false;
        self.defeat = false;
        self.wave = 0;
        self.kills = 0;
        self.banner_time = 0;
        self.target = 0;
        self.spawn_count = 0;
        self.spawn_index = 0;
        self.intermission = 0;
        const xs = [_]f32{ -1.45, 0.0, 1.45 };
        for (self.party, 0..) |e, i| {
            if (e == 0) continue;
            _ = ecs.set(self.world, e, comp.Transform, .{
                .pos = math.Vec3.init(xs[i], 0, 0.55),
                .yaw = 0.06,
                .scale = 1.40,
            });
            _ = ecs.set(self.world, e, comp.Velocity, .{});
            _ = ecs.set(self.world, e, comp.MoveIntent, .{});
            if (ecs.get_mut(self.world, e, comp.Animation)) |a| a.state.moving = 0;
            ecs.remove(self.world, e, comp.Follow);
            if (ecs.get_mut(self.world, e, comp.Hero)) |h| {
                h.active = i == 1;
                h.downed = false;
                h.hp = h.hp_max;
                h.revive_timer = 0;
            }
            if (ecs.get_mut(self.world, e, comp.Renderable)) |r| r.tint = 0xffffff;
        }
        self.active_index = 1;
        self.active = self.party[1];
        self.camera_target = math.Vec3.init(0, 0.72, 0.55);
        self.camera.target = self.camera_target;
        self.camera.yaw = 0.0;
        self.camera.pitch = 0.34;
        self.camera.distance = 4.35;
        self.camera.fov = 0.72;
    }

    pub fn update(self: *Game, input: InputFrame, dt: f32) void {
        self.dt = std.math.clamp(dt, 0.0, 0.05);
        self.time += self.dt;
        self.frame += 1;
        const inst_ms = self.dt * 1000.0;
        const inst_fps = if (self.dt > 0) 1.0 / self.dt else 60.0;
        self.fps += (inst_fps - self.fps) * 0.08;
        self.frame_ms += (inst_ms - self.frame_ms) * 0.08;
        systems.clearEvents();

        if (input.reset) self.resetRun();
        if (input.toggle_hero) self.cycleHero();
        if (input.inventory) self.inventory_open = !self.inventory_open;
        if (input.cast) self.tryCast();

        self.camera.yaw += input.yaw_delta;
        self.camera.distance = std.math.clamp(self.camera.distance - input.zoom_delta, 4.8, 11.5);

        const hero = ecs.get(self.world, self.active, comp.Hero);
        const can_move = !(self.victory or self.defeat) and hero != null and !hero.?.downed;
        const fwd = math.Vec3.init(-@sin(self.camera.yaw), 0, -@cos(self.camera.yaw));
        const right = math.Vec3.init(@cos(self.camera.yaw), 0, -@sin(self.camera.yaw));
        var dir = fwd.scale(input.move_z).add(right.scale(input.move_x));
        const len = dir.length();
        if (len > 1.0) dir = dir.scale(1.0 / len);
        const speed: f32 = if (len > 0.05 and can_move) hero.?.move_speed else 0;
        _ = ecs.set(self.world, self.active, comp.MoveIntent, .{ .dir = dir, .speed = speed });

        self.ctx.dt = self.dt;
        self.ctx.time = self.time;
        self.ctx.active = self.active;
        self.ctx.combat_active = !(self.victory or self.defeat);
        self.updateWave();
        _ = ecs.progress(self.world, self.dt);
        self.handleEvents();
        self.cleanupEnemies();
        self.updateHeroes();
        self.updateFloats();

        const tr = ecs.get(self.world, self.active, comp.Transform) orelse return;
        self.target = systems.nearestEnemy(self.world, tr.pos, 7.0) orelse 0;
        const desired = tr.pos.add(math.Vec3.init(0, 0.58, 0));
        self.camera_target = self.camera_target.lerp(desired, 1.0 - @exp(-9.0 * self.dt));
        self.camera.target = self.camera_target;

        for (&self.sparks) |*spark| {
            if (!spark.active) continue;
            spark.life -= self.dt;
            if (spark.life <= 0) {
                spark.active = false;
                continue;
            }
            spark.vel.y -= 4.2 * self.dt;
            spark.pos = spark.pos.add(spark.vel.scale(self.dt));
        }
    }

    // ----------------------------------------------------------------- render
    fn collectLights(self: *Game) void {
        var it = ecs.each(self.world, comp.LightSource);
        while (ecs.each_next(&it)) {
            const lights = ecs.field(&it, comp.LightSource, 0).?;
            for (lights, it.entities()) |light, e| {
                const tr = ecs.get(self.world, e, comp.Transform) orelse continue;
                const flicker = 1.0 + @sin(self.time * 8.5 + light.phase) * 0.10 + @sin(self.time * 21.7 + light.phase * 2.0) * 0.05;
                self.renderer.addLight(.{
                    .pos = tr.pos.add(math.Vec3.init(0, light.height, 0)),
                    .color = light.color,
                    .intensity = light.intensity * (1.0 + light.flicker * (flicker - 1.0)),
                    .radius = light.radius,
                });
            }
        }

        // magical circle ambient light
        self.renderer.addLight(.{
            .pos = math.Vec3.init(0, 0.25, 0),
            .color = .{ .x = 0.16, .y = 0.65, .z = 0.62 },
            .intensity = 0.62,
            .radius = 4.2,
        });

        // a soft top light makes the heroes read against the carpet
        var spot = ecs.each(self.world, comp.Hero);
        while (ecs.each_next(&spot)) {
            const heroes = ecs.field(&spot, comp.Hero, 0).?;
            for (heroes, spot.entities()) |_, e| {
                const tr = ecs.get(self.world, e, comp.Transform) orelse continue;
                self.renderer.addLight(.{
                    .pos = tr.pos.add(math.Vec3.init(0, 1.55, 0.95)),
                    .color = .{ .x = 1.0, .y = 0.90, .z = 0.80 },
                    .intensity = 2.10,
                    .radius = 3.1,
                });
            }
        }

        self.hero_glow_count = 0;
        var hits = ecs.each(self.world, comp.Hero);
        while (ecs.each_next(&hits)) {
            const heroes = ecs.field(&hits, comp.Hero, 0).?;
            for (heroes, hits.entities()) |hero, e| {
                if (hero.class == 0) continue;
                const rend = ecs.get(self.world, e, comp.Renderable) orelse continue;
                const pose = ecs.get(self.world, e, comp.Pose) orelse continue;
                const tr = ecs.get(self.world, e, comp.Transform) orelse continue;
                const m = self.models.at(rend.model);
                const joint = m.weapon orelse continue;
                if (joint >= pose.pose.count) continue;
                const entity_mat = math.Mat4.compose(tr.pos, tr.yaw, 0, 0, tr.scale);
                const jm = entity_mat.mul(pose.pose.joints[joint]);
                const is_mage = hero.class == 1;
                const offset = if (is_mage)
                    math.Vec3.init(-0.02, 0.64, 0.04)
                else
                    math.Vec3.init(-0.02, 0.59, 0.04);
                const pos = jm.mulPoint(offset);
                const gl = &self.hero_glows[self.hero_glow_count];
                self.hero_glow_count += 1;
                gl.* = .{
                    .pos = pos,
                    .color = if (is_mage) color.pack(255, 159, 28) else color.pack(111, 224, 208),
                    .intensity = if (is_mage) 1.0 else 0.85,
                    .size = if (is_mage) 0.085 else 0.07,
                };
                if (is_mage) {
                    self.renderer.addLight(.{
                        .pos = pos,
                        .color = .{ .x = 1.0, .y = 0.55, .z = 0.18 },
                        .intensity = 1.55 + @sin(self.time * 6.0) * 0.18,
                        .radius = 3.2,
                    });
                } else {
                    self.renderer.addLight(.{
                        .pos = pos,
                        .color = .{ .x = 0.40, .y = 1.0, .z = 0.88 },
                        .intensity = 1.15 + @sin(self.time * 4.3) * 0.14,
                        .radius = 2.9,
                    });
                }
            }
        }
    }

    fn drawEntities(self: *Game, additive: bool) void {
        var it = ecs.each(self.world, comp.Renderable);
        while (ecs.each_next(&it)) {
            const rends = ecs.field(&it, comp.Renderable, 0).?;
            for (rends, it.entities()) |rend, e| {
                if (rend.additive != additive) continue;
                const tr = ecs.get(self.world, e, comp.Transform) orelse continue;
                const model = self.models.at(rend.model);
                const pose = ecs.get(self.world, e, comp.Pose);
                const entity_mat = math.Mat4.compose(tr.pos, tr.yaw, 0, 0, tr.scale);
                const opts = renderer.RenderOpts{
                    .tint = rend.tint,
                    .boost = rend.boost,
                    .additive = rend.additive,
                    .id = rend.id,
                };
                const slice: ?[]const math.Mat4 = if (pose) |p| p.pose.joints[0..p.pose.count] else null;
                self.renderer.drawModel(model, slice, entity_mat, opts);
            }
        }
    }

    fn drawShadows(self: *Game) void {
        var it = ecs.each(self.world, comp.Shadow);
        while (ecs.each_next(&it)) {
            const shadows = ecs.field(&it, comp.Shadow, 0).?;
            for (shadows, it.entities()) |shadow, e| {
                const tr = ecs.get(self.world, e, comp.Transform) orelse continue;
                const offset = math.Vec3.init(0.10, 0, -0.06).scale(tr.scale);
                self.renderer.drawShadow(tr.pos.add(offset), shadow.radius * tr.scale);
            }
        }
    }

    fn drawEffects(self: *Game) void {
        // active hero selection ring
        if (ecs.get(self.world, self.active, comp.Transform)) |tr| {
            if (self.models.find("rune_circle")) |ring| {
                const pos = math.Vec3.init(tr.pos.x, 0.030, tr.pos.z);
                self.renderer.drawModel(ring, null, math.Mat4.compose(pos, self.time * 0.22, 0, 0, 0.40), .{
                    .tint = palette.gold_light,
                    .boost = 0.85,
                    .additive = true,
                    .alpha = 0.95,
                });
            }
        }

        // locked enemy ring
        if (self.target != 0) {
            if (ecs.get(self.world, self.target, comp.Enemy)) |enemy| {
                if (enemy.hp > 0) {
                    if (ecs.get(self.world, self.target, comp.Transform)) |tr| {
                        self.renderer.drawGlow(tr.pos.add(math.Vec3.init(0, 0.08, 0)), 0.30, color.pack(255, 80, 64), 0.22);
                        if (self.models.find("rune_circle")) |ring| {
                            const pos = math.Vec3.init(tr.pos.x, 0.035, tr.pos.z);
                            self.renderer.drawModel(ring, null, math.Mat4.compose(pos, -self.time * 0.7, 0, 0, 0.34), .{
                                .tint = color.pack(255, 86, 70),
                                .boost = 1.0,
                                .additive = true,
                                .alpha = 0.85,
                            });
                        }
                    }
                }
            }
        }

        // flames & embers
        for (self.braziers, 0..) |pos, i| {
            const flick = 0.9 + @sin(self.time * 9.0 + @as(f32, @floatFromInt(i)) * 1.7) * 0.12;
            self.renderer.drawGlow(pos.add(math.Vec3.init(0, 0.58, 0)), 0.72 * flick, color.pack(255, 120, 40), 0.60);
            self.renderer.drawFlame(pos.add(math.Vec3.init(0, 0.58, 0)), 0.62 * flick, @as(u32, @intCast(i)) * 91 + 7);
        }

        // staff / hourglass glows
        var gi: usize = 0;
        while (gi < self.hero_glow_count) : (gi += 1) {
            const gl = self.hero_glows[gi];
            self.renderer.drawGlow(gl.pos, 0.30, gl.color, 0.85);
            self.renderer.drawGlow(gl.pos, 0.10, color.pack(255, 255, 255), 0.9);
        }

        // rune circle pulse
        self.renderer.drawGlow(math.Vec3.init(0, 0.18, 0), 1.15, palette.cyan, 0.10);

        // pylon crystals
        var pylons = ecs.each(self.world, comp.LightSource);
        while (ecs.each_next(&pylons)) {
            const lights = ecs.field(&pylons, comp.LightSource, 0).?;
            for (lights, pylons.entities()) |light, e| {
                if (light.color.y < 0.6) continue;
                const tr = ecs.get(self.world, e, comp.Transform) orelse continue;
                const top = tr.pos.add(math.Vec3.init(0, light.height, 0));
                self.renderer.drawGlow(top, 0.30, palette.cyan_light, 0.72);
                self.renderer.drawGlow(top, 0.11, color.pack(255, 255, 255), 0.85);
            }
        }

        // dust motes
        for (self.dust) |dust| {
            const t = self.time;
            const p = math.Vec3.init(
                dust.base.x + @sin(t * dust.speed + dust.phase) * 0.55,
                dust.base.y + @sin(t * dust.speed * 0.7 + dust.phase * 1.9) * 0.16,
                dust.base.z + @cos(t * dust.speed * 0.83 + dust.phase) * 0.55,
            );
            self.renderer.drawGlow(p, dust.size, color.pack(139, 160, 200), 0.35);
        }

        // brazier embers
        for (self.embers) |ember| {
            const pos = self.braziers[ember.brazier];
            const t = @mod(self.time * ember.speed + ember.phase, 1.0);
            const epos = math.Vec3.init(
                pos.x + @sin(t * 9.0 + ember.phase * 6.0) * (0.16 * (1.0 - t)),
                0.52 + t * 1.25,
                pos.z + @cos(t * 7.0 + ember.phase * 4.0) * (0.16 * (1.0 - t)),
            );
            self.renderer.drawGlow(epos, 0.016 + 0.008 * (1.0 - t), color.pack(255, 170 + @as(u8, 0), 60), (1.0 - t) * 0.9);
        }

        // floating shards
        var shards = ecs.each(self.world, comp.Spin);
        while (ecs.each_next(&shards)) {
            for (shards.entities()) |e| {
                const tr = ecs.get(self.world, e, comp.Transform) orelse continue;
                self.renderer.drawGlow(tr.pos, 0.14 * tr.scale, palette.cyan_light, 0.55);
            }
        }

        // cast sparks
        for (self.sparks) |spark| {
            if (!spark.active) continue;
            const fade = spark.life / spark.max_life;
            self.renderer.drawGlow(spark.pos, spark.size, spark.color, fade);
        }
    }

    fn enemyLabel(kind: u8) []const u8 {
        return switch (kind) {
            0 => "骷髅兵",
            1 => "幽魂",
            2 => "石魔像",
            else => "深渊守卫",
        };
    }

    fn enemyColor(kind: u8) u32 {
        return switch (kind) {
            0 => palette.cream,
            1 => palette.cyan_light,
            2 => palette.gold_light,
            else => palette.red,
        };
    }

    fn drawCombatHud(self: *Game) void {
        const r = &self.renderer;
        var it = ecs.each(self.world, comp.Enemy);
        while (ecs.each_next(&it)) {
            const enemies = ecs.field(&it, comp.Enemy, 0).?;
            for (enemies, it.entities()) |enemy, e| {
                if (enemy.hp <= 0) continue;
                const tr = ecs.get(self.world, e, comp.Transform) orelse continue;
                const head_pos = tr.pos.add(math.Vec3.init(0, 1.05 * tr.scale, 0));
                const p = self.camera.project(head_pos, r.width, r.height) orelse continue;
                if (p.depth <= 0.1) continue;
                const x: i32 = @intFromFloat(p.x);
                const y: i32 = @intFromFloat(p.y);
                const is_target = e == self.target;
                if (is_target or enemy.boss) {
                    const label = enemyLabel(enemy.kind);
                    const tw = renderer.Renderer.textWidth(label, 1);
                    if (x + tw >= -8 and x - tw <= @as(i32, @intCast(r.width)) + 8) {
                        r.fillRect(x - @divTrunc(tw, 2) - 4, y - 17, tw + 8, 16, palette.panel);
                        r.strokeRect(x - @divTrunc(tw, 2) - 4, y - 17, tw + 8, 16, palette.border);
                        r.textCentered(x, y - 15, label, enemyColor(enemy.kind), 1, false);
                    }
                }
                const bw: i32 = if (enemy.boss) 48 else if (is_target) 38 else 22;
                r.fillRect(x - @divTrunc(bw, 2), y, bw, 4, palette.deep);
                const fill = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bw - 2)) * std.math.clamp(enemy.hp / enemy.hp_max, 0, 1)));
                if (fill > 0) r.fillRect(x - @divTrunc(bw, 2) + 1, y + 1, fill, 2, palette.health_light);
                r.strokeRect(x - @divTrunc(bw, 2), y, bw, 4, palette.muted);
            }
        }

        for (self.floats) |ft| {
            if (!ft.active) continue;
            const t = 1.0 - ft.life / ft.max_life;
            const p = self.camera.project(ft.pos.add(math.Vec3.init(0, t * 0.55, 0)), r.width, r.height) orelse continue;
            if (p.depth <= 0.1) continue;
            var buf: [16]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "{s}{d}", .{ if (ft.signed) "-" else "", ft.value }) catch continue;
            const scale: i32 = if (ft.crit) 2 else 1;
            const x: i32 = @intFromFloat(p.x);
            const y: i32 = @as(i32, @intFromFloat(p.y)) - 10;
            r.textCentered(x, y, text, ft.color, scale, true);
        }
    }

    fn fillHudState(self: *Game) void {
        const plate_heights = [_]f32{ 1.32, 1.48, 1.41 };
        var i: usize = 0;
        while (i < party_size) : (i += 1) {
            const e = self.party[i];
            const hero = ecs.get(self.world, e, comp.Hero);
            const tr = ecs.get(self.world, e, comp.Transform);
            if (hero == null or tr == null) {
                self.hud_state.rows[i] = .{
                    .name = class_names[i],
                    .level = 1,
                    .hp = 0,
                    .hp_max = 1,
                    .ap = 0,
                    .ap_max = 1,
                    .active = false,
                };
                self.hud_state.plates[i] = .{};
                continue;
            }
            const h = hero.?;
            self.hud_state.rows[i] = .{
                .name = class_names[i],
                .level = h.level,
                .hp = h.hp,
                .hp_max = h.hp_max,
                .ap = h.ap,
                .ap_max = h.ap_max,
                .active = h.active,
                .downed = h.downed,
                .revive = @max(0, h.revive_timer),
            };
            self.hud_state.plates[i] = .{
                .pos = math.Vec3.init(tr.?.pos.x, plate_heights[i], tr.?.pos.z),
                .name = class_names[i],
                .level = h.level,
                .active = h.active and !h.downed,
            };
        }
        self.hud_state.camera_yaw = self.camera.yaw;
        self.hud_state.camera_distance = self.camera.distance;
        self.hud_state.fps = self.fps;
        self.hud_state.frame_ms = self.frame_ms;
        self.hud_state.tris = self.renderer.stats.tris;
        self.hud_state.drawn = self.renderer.stats.drawn;
        self.hud_state.entities = @intCast(self.prop_seq + party_size + 8 + self.enemyCount());
        self.hud_state.debug = self.debug;
        self.hud_state.wave = self.wave;
        self.hud_state.max_waves = self.max_waves;
        self.hud_state.enemies = @intCast(self.enemyCount());
        self.hud_state.kills = self.kills;
        self.hud_state.skill = "";
        if (ecs.get(self.world, self.active, comp.Hero)) |h| {
            if (!h.downed) self.hud_state.skill = h.skill_name;
        }
        self.hud_state.banner = "";
        self.hud_state.banner_time = self.banner_time;
        if (self.banner_time > 0 and !self.victory and !self.defeat) {
            self.hud_state.banner = std.fmt.bufPrint(&self.banner_buf, "第{d}波来袭", .{self.wave}) catch "";
        }
        self.hud_state.mode = self.tactical_mode;
        self.hud_state.inventory_open = self.inventory_open;
        self.hud_state.item_count = 0;
        const active_class: u8 = if (ecs.get(self.world, self.active, comp.Hero)) |h| h.class else 0;
        const base_attrs = [_][6]i32{
            .{ 14, 10, 16, 8, 4, 10 },
            .{ 6, 8, 8, 12, 18, 12 },
            .{ 7, 10, 9, 14, 14, 13 },
        };
        self.hud_state.attr_values = base_attrs[@min(active_class, 2)];
        self.hud_state.equip_names = .{ "", "", "" };
        self.hud_state.threat = if (self.threat_time > 0) self.threat_text else "";
        self.hud_state.threat_time = self.threat_time;
        const visible = @min(self.log_total, self.hud_state.log_lines.len);
        self.hud_state.log_count = visible;
        var li: usize = 0;
        while (li < visible) : (li += 1) {
            const slot = (self.log_head + self.log_buf.len - visible + li) % self.log_buf.len;
            self.hud_state.log_lines[li] = self.log_buf[slot][0..@as(usize, self.log_len[slot])];
        }
        self.hud_state.victory = self.victory;
        self.hud_state.defeat = self.defeat;
    }

    pub fn render(self: *Game) void {
        const cam = self.camera;
        self.renderer.begin(cam, self.time);
        self.collectLights();

        self.renderer.drawMesh(&self.mesh, math.Mat4.identity, .{ .id = 1 });
        self.drawEntities(false);
        self.drawShadows();
        self.drawEntities(true);
        self.drawEffects();
        self.renderer.resolve();

        self.drawCombatHud();
        self.fillHudState();
        if (self.show_hud) hud.draw(&self.renderer, cam, self.hud_state);
    }

    pub fn saveScreenshot(self: *Game, io: std.Io, path: []const u8) !void {
        try png.writePng(io, self.gpa, path, self.renderer.width, self.renderer.height, self.renderer.color_buf);
    }
};
