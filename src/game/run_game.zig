//! Turn-based single-hero 3D pixel roguelike.
//! Owns the pure simulation (run_sim), renders the 31x31 dungeon and HUD.
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
const sim_mod = @import("run_sim.zig");
const target_mod = @import("run_target.zig");
const intent_mod = @import("intent.zig");
const hud = @import("run_hud.zig");
const content_mod = @import("content.zig");
const items_mod = @import("items.zig");
const attributes = @import("attributes.zig");
const save_mod = @import("save.zig");
const status_def = @import("status_def.zig");
const gear_save = @import("gear_save.zig");
const slot_bundle = @import("slot_bundle.zig");
const records_mod = @import("records.zig");

fn detailAppend(buf: []u8, off: *usize, comptime f: []const u8, args: anytype) void {
    const written = std.fmt.bufPrint(buf[off.*..], f, args) catch return;
    off.* += written.len;
}

/// Compact one-line item summary for the bag: quality + up to two modifiers,
/// or the consumable's heal/resource effect.
fn writeItemDetail(buf: []u8, def: *const items_mod.ItemDef) []const u8 {
    var off: usize = 0;
    detailAppend(buf, &off, "{s}", .{items_mod.qualityLabel(def.quality)});
    var shown: usize = 0;
    for (def.mods()) |m| {
        if (shown >= 2) break;
        if (m.flat != 0) {
            const sign: []const u8 = if (m.flat > 0) "+" else "";
            if (m.stat == .crit) {
                detailAppend(buf, &off, " {s}{s}{d:.0}%", .{ m.stat.label(), sign, m.flat * 100.0 });
            } else {
                detailAppend(buf, &off, " {s}{s}{d:.0}", .{ m.stat.label(), sign, m.flat });
            }
            shown += 1;
        }
        if (m.pct != 0) {
            const sign: []const u8 = if (m.pct > 0) "+" else "";
            detailAppend(buf, &off, " {s}{s}{d:.0}%", .{ m.stat.label(), sign, m.pct * 100.0 });
            shown += 1;
        }
    }
    if (def.use()) |u| {
        if (u.heal > 0) detailAppend(buf, &off, " 回复{d:.0}", .{u.heal});
        if (u.resource > 0) detailAppend(buf, &off, " 资源{d:.0}", .{u.resource});
    }
    return buf[0..off];
}

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

pub const SlotMenu = enum(u8) { none, save, load, auto_load };

pub const Input = struct {
    step_x: i32 = 0,
    step_y: i32 = 0,
    talent: i8 = -1,
    /// Menu only: D toggles normal/hard before starting.
    difficulty: bool = false,
    /// Inventory panel: consume a healing item.
    use_item: bool = false,
    /// Space while aiming confirms the pending talent.
    confirm: bool = false,
    wait: bool = false,
    inventory: bool = false,
    character: bool = false,
    target_next: bool = false,
    restart: bool = false,
    help: bool = false,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    click: bool = false,
    /// 0..5 while the character panel is open (keys 1..6).
    stat: i8 = -1,
    yaw_delta: f32 = 0,
    zoom_delta: f32 = 0,
};

var seed_state: u64 = 0;

pub const RunGame = struct {
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
    item_detail_bufs: [items_mod.max_inventory][96]u8 = undefined,
    mods: items_mod.ModifierSet = .{},
    loot_rng: std.Random.DefaultPrng = undefined,
    chest_loot_seen: u32 = 0,
    kill_loot_seen: u32 = 0,
    last_level: u16 = 1,
    selected: ?usize = null,
    /// Talent index while the player is aiming; null when not aiming. Aiming
    /// itself never spends a turn, only a successful confirmation does.
    aim_talent: ?usize = null,
    /// Ground cell for mouse-cast fireball; null means enemy-centric aim.
    aim_cell: ?sim_mod.GridPos = null,
    reset_armed: f32 = 0,
    /// Throttles OS key-repeat so holding a direction does not burn a turn
    /// for every repeat event (critic P0).
    step_cooldown: f32 = 0,
    seed: u64,
    /// True when --seed pinned the run; restart keeps it. Otherwise R rolls
    /// a fresh seed so a new run gets a new dungeon and loot sequence.
    seed_locked: bool = false,
    class: sim_mod.Class,
    difficulty: sim_mod.Difficulty = .normal,
    records: records_mod.Records = .{},
    records_dirty: bool = false,
    last_state: sim_mod.State = .playing,
    slot_menu: SlotMenu = .none,
    slot_labels: [3][]const u8 = .{ "空", "空", "空" },
    slot_bufs: [3][96]u8 = undefined,
    slot_runs: [3][]const u8 = .{
        "saves/run.json",
        "saves/slot2-run.json",
        "saves/slot3-run.json",
    },
    slot_gears: [3][]const u8 = .{
        "saves/gear.json",
        "saves/slot2-gear.json",
        "saves/slot3-gear.json",
    },
    slot_files: [3][]const u8 = .{
        "saves/slot1.save",
        "saves/slot2.save",
        "saves/slot3.save",
    },
    auto_files: [3][]const u8 = .{
        "saves/autosave1.save",
        "saves/autosave2.save",
        "saves/autosave3.save",
    },
    auto_tmp_file: []const u8 = "saves/autosave-new.save",
    autosave_pending: bool = false,
    save_ok: bool = true,
    /// Window play presents a short "敌人行动" phase; tests/bots leave this
    /// false so their turns resolve synchronously.
    presentation: bool = false,
    enemy_phase_timer: f32 = 0,
    /// False while the class-selection menu is up; the sim is already
    /// generated so the menu can preview the 3D dungeon behind the cards.
    started: bool = true,
    shrine_open: bool = false,
    shop_open: bool = false,
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

    pub fn create(gpa: std.mem.Allocator, width: u32, height: u32, class: sim_mod.Class, seed: u64) !*RunGame {
        const self = try gpa.create(RunGame);
        errdefer gpa.destroy(self);
        const resolved = if (seed == 0) freshSeed() else seed;
        self.* = .{
            .gpa = gpa,
            .arena_alloc = std.heap.ArenaAllocator.init(gpa),
            .models = undefined,
            .mesh = .{ .verts = &.{}, .tris = &.{} },
            .renderer = undefined,
            .sim = undefined,
            .seed = resolved,
            .seed_locked = seed != 0,
            .class = class,
        };
        try self.setup(width, height);
        return self;
    }

    fn setup(self: *RunGame, width: u32, height: u32) !void {
        const alloc = self.arena_alloc.allocator();
        self.models = try model_mod.ModelDb.init(alloc, assets.all);
        self.renderer = try renderer.Renderer.init(self.gpa, width, height);
        self.content = try content_mod.load(self.gpa);
        self.loot_rng = std.Random.DefaultPrng.init(self.seed ^ 0x9e3779b97f4a7c15);
        self.sim = sim_mod.Sim.initWithDifficulty(self.seed, self.class, self.difficulty);
        self.sim.setEnemyDefs(self.content.enemies);
        self.sim.reset(self.seed, self.class);
        self.last_state = .playing;
        self.camera = .{
            .target = math.Vec3.init(0, 0.55, 0),
            .yaw = -0.35,
            .pitch = 0.72,
            .distance = 15.2,
            .fov = 0.76,
        };
        self.camera_target = self.camera.target;
        self.rebuildMesh();
        self.resetVisuals();
        self.fillHudState();
    }

    pub fn destroy(self: *RunGame) void {
        if (self.mesh.verts.len > 0) self.gpa.free(self.mesh.verts);
        if (self.mesh.tris.len > 0) self.gpa.free(self.mesh.tris);
        self.content.deinit();
        self.renderer.deinit();
        self.arena_alloc.deinit();
        const gpa = self.gpa;
        gpa.destroy(self);
    }

    fn rebuildMesh(self: *RunGame) void {
        if (self.mesh.verts.len > 0) self.gpa.free(self.mesh.verts);
        if (self.mesh.tris.len > 0) self.gpa.free(self.mesh.tris);
        self.mesh = arena_mesh.buildDungeon(self.gpa, &self.sim.blocked, sim_mod.grid_w, sim_mod.grid_h, .{ self.sim.stairs.x, self.sim.stairs.y }) catch .{ .verts = &.{}, .tris = &.{} };
        self.mesh_floor = self.sim.floor;
    }

    fn tilePos(x: i32, y: i32) math.Vec3 {
        const center = @as(f32, @floatFromInt(sim_mod.grid_w - 1)) * 0.5;
        return math.Vec3.init(@as(f32, @floatFromInt(x)) - center, 0, @as(f32, @floatFromInt(y)) - center);
    }

    fn resetVisuals(self: *RunGame) void {
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
                .anim = .{ .kind = enemyAnimKind(e.identity.kind) },
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
            6 => 1.34,
            else => 1.95,
        };
    }

    fn heroScale(_: *const RunGame) f32 {
        return 1.55;
    }

    /// Rebuild every run-scoped system from (seed, class). Shared by restart,
    /// class selection and the menu, so R never loses the chosen class.
    fn resetRun(self: *RunGame) void {
        self.sim.reset(self.seed, self.class);
        self.inventory = items_mod.Inventory.init();
        self.mods.clear();
        self.loot_rng = std.Random.DefaultPrng.init(self.seed ^ 0x9e3779b97f4a7c15);
        self.chest_loot_seen = 0;
        self.kill_loot_seen = 0;
        self.last_level = 1;
        self.selected = null;
        self.aim_talent = null;
        self.aim_cell = null;
        self.enemy_phase_timer = 0;
        self.autosave_pending = false;
        self.reset_armed = 0;
        self.step_cooldown = 0;
        self.show_help = false;
        self.panel = .none;
        self.rebuildMesh();
        self.resetVisuals();
        self.fillHudState();
    }

    fn freshSeed() u64 {
        // No std.crypto.random in Zig 0.17; mix the process address (ASLR)
        // with a counter so each run gets a different, non-zero seed.
        if (seed_state == 0) seed_state = @intFromPtr(&seed_state) ^ 0x9e3779b97f4a7c15;
        seed_state = seed_state *% 6364136223846793005 +% 1442695040888963407;
        return if (seed_state == 0) 1 else seed_state;
    }

    pub fn restart(self: *RunGame) void {
        if (!self.seed_locked) self.seed = freshSeed();
        self.started = true;
        self.resetRun();
    }

    /// Show the pre-run class cards. The same seed is used for the preview;
    /// picking a class keeps it and regenerates the dungeon for that class.
    pub fn openMenu(self: *RunGame) void {
        self.started = false;
        self.resetRun();
    }

    pub fn selectClass(self: *RunGame, class: sim_mod.Class) void {
        self.class = class;
        self.restart();
        self.sim.pushLog("开始：{s}", .{sim_mod.class_names[@backingInt(self.class)]});
        self.fillHudState();
    }

    pub fn setRecords(self: *RunGame, records: records_mod.Records) void {
        self.records = records;
        self.records_dirty = false;
    }

    pub fn saveRecords(self: *RunGame, io: std.Io) bool {
        records_mod.save(io, self.gpa, records_mod.default_path, self.records) catch return false;
        self.records_dirty = false;
        return true;
    }

    fn trackRunEnd(self: *RunGame) void {
        if (!self.started) {
            self.last_state = self.sim.state;
            return;
        }
        if (self.last_state == .playing and self.sim.state != .playing) {
            if (self.sim.state == .victory) {
                self.records.wins +|= 1;
                if (self.records.best_turn == 0 or self.sim.turn < self.records.best_turn) self.records.best_turn = self.sim.turn;
            } else {
                self.records.deaths +|= 1;
            }
            self.records.best_floor = @max(self.records.best_floor, self.sim.floor);
            self.records.best_kills = @max(self.records.best_kills, self.sim.kills);
            self.records_dirty = true;
        }
        self.last_state = self.sim.state;
    }

    pub fn debugShop(self: *RunGame) void {
        self.started = true;
        self.shop_open = true;
        self.sim.shop_active = true;
        self.sim.shop_used = false;
        self.sim.gold = 120;
        self.fillHudState();
    }

    pub fn debugShrine(self: *RunGame) void {
        self.started = true;
        self.shrine_open = true;
        self.sim.shrine_active = true;
        self.sim.shrine_used = false;
        self.fillHudState();
    }

    pub fn closeShop(self: *RunGame) void {
        self.shop_open = false;
        self.fillHudState();
    }

    fn buyShopLoot(self: *RunGame) void {
        if (!self.sim.buyShopLoot()) {
            self.sim.pushLog("金币不足", .{});
            return;
        }
        self.shop_open = false;
        self.grantDrop(true);
        self.fillHudState();
    }

    fn buyShop(self: *RunGame, index: usize) void {
        if (index >= 4) return;
        const choice: sim_mod.ShopChoice = @fromBackingInt(@intCast(index));
        if (self.sim.useShop(choice)) {
            self.shop_open = false;
            self.fillHudState();
        }
    }

    pub fn closeShrine(self: *RunGame) void {
        self.shrine_open = false;
        self.fillHudState();
    }

    fn chooseShrine(self: *RunGame, index: usize) void {
        if (index >= 4) return;
        const choice: sim_mod.ShrineChoice = @fromBackingInt(@intCast(index));
        if (self.sim.useShrine(choice)) {
            self.shrine_open = false;
            self.fillHudState();
        }
    }

    pub fn setDifficulty(self: *RunGame, difficulty: sim_mod.Difficulty) void {
        if (self.difficulty == difficulty) return;
        self.difficulty = difficulty;
        self.sim.difficulty = difficulty;
        self.sim.reset(self.seed, self.class);
        self.resetVisuals();
        self.fillHudState();
    }

    pub fn toggleDifficulty(self: *RunGame) void {
        self.setDifficulty(self.difficulty.next());
    }

    fn classOf(self: *const RunGame) attributes.Class {
        return switch (self.class) {
            .warrior => .warrior,
            .mage => .mage,
            .chronomancer => .chronomancer,
        };
    }

    /// F5: write the pure run snapshot and the bag/equipment sidecar.
    /// The parent directory is created on demand; a failure leaves the
    /// currently running game untouched and is reported in the log.
    pub fn openSlotMenu(self: *RunGame, io: std.Io, mode: SlotMenu) void {
        self.slot_menu = mode;
        self.clearAim();
        self.show_help = false;
        self.panel = .none;
        self.refreshSlotLabels(io);
        self.fillHudState();
    }

    pub fn closeSlotMenu(self: *RunGame) void {
        self.slot_menu = .none;
        self.fillHudState();
    }

    fn refreshSlotLabels(self: *RunGame, io: std.Io) void {
        var i: usize = 0;
        while (i < self.slot_files.len) : (i += 1) {
            self.slot_labels[i] = "空";
            const loaded = slot_bundle.loadFile(io, self.gpa, self.slot_files[i]) catch |err| {
                if (err == error.FileNotFound) {
                    const legacy = save_mod.loadFile(io, self.gpa, self.slot_runs[i]) catch |old_err| {
                        if (old_err != error.FileNotFound) self.slot_labels[i] = "坏档";
                        continue;
                    };
                    self.slot_labels[i] = self.formatSlotLabel(i, &legacy);
                } else {
                    self.slot_labels[i] = "坏档";
                }
                continue;
            };
            self.slot_labels[i] = self.formatSlotLabel(i, &loaded.sim);
        }
    }

    fn formatSlotLabel(self: *RunGame, i: usize, loaded: *const sim_mod.Sim) []const u8 {
        return std.fmt.bufPrint(
            &self.slot_bufs[i],
            "{s} 第{d}层 {d}级 回合{d}",
            .{ sim_mod.class_names[@backingInt(loaded.class)], loaded.floor, loaded.hero.progression.level, loaded.turn },
        ) catch "有效存档";
    }

    pub fn saveSlot(self: *RunGame, io: std.Io, slot: usize) void {
        if (slot >= self.slot_files.len) return;
        if (self.sim.enemy_phase_pending) {
            self.sim.resolvePendingEnemyPhase();
            self.syncVisuals(false);
        }
        if (std.fs.path.dirname(self.slot_files[slot])) |dir| {
            std.Io.Dir.cwd().createDirPath(io, dir) catch {};
        }
        slot_bundle.saveFileAtomic(io, self.gpa, self.slot_files[slot], &self.sim, &self.inventory, &self.loot_rng) catch |err| {
            self.sim.pushLog("存档失败 {s}", .{@errorName(err)});
            self.save_ok = false;
            self.slot_menu = .none;
            self.fillHudState();
            return;
        };
        self.save_ok = true;
        self.slot_menu = .none;
        self.refreshSlotLabels(io);
        self.sim.pushLog("已保存到槽 {d}", .{slot + 1});
        self.fillHudState();
    }

    pub fn loadSlot(self: *RunGame, io: std.Io, slot: usize) void {
        if (slot >= self.slot_files.len) return;
        const loaded = slot_bundle.loadFile(io, self.gpa, self.slot_files[slot]) catch |err| {
            if (err == error.FileNotFound) {
                self.loadRun(io, self.slot_runs[slot], self.slot_gears[slot]);
            } else {
                self.sim.pushLog("读档失败：{s}", .{loadErrorText(err)});
            }
            self.slot_menu = .none;
            self.refreshSlotLabels(io);
            self.fillHudState();
            return;
        };
        self.applyLoaded(loaded.sim, loaded.gear);
        self.slot_menu = .none;
        self.refreshSlotLabels(io);
        self.fillHudState();
    }

    pub fn flushAutosave(self: *RunGame, io: std.Io) void {
        if (!self.autosave_pending) return;
        self.autosave_pending = false;
        if (self.sim.enemy_phase_pending) {
            self.sim.resolvePendingEnemyPhase();
            self.syncVisuals(false);
        }
        if (std.fs.path.dirname(self.auto_files[0])) |dir| {
            std.Io.Dir.cwd().createDirPath(io, dir) catch {};
        }
        slot_bundle.saveFileAtomic(io, self.gpa, self.auto_tmp_file, &self.sim, &self.inventory, &self.loot_rng) catch |err| {
            self.sim.pushLog("自动存档失败 {s}", .{@errorName(err)});
            self.fillHudState();
            return;
        };
        // Rotate newest backups, then promote the new file to slot 1.
        std.Io.Dir.cwd().deleteFile(io, self.auto_files[2]) catch {};
        std.Io.Dir.cwd().rename(self.auto_files[1], std.Io.Dir.cwd(), self.auto_files[2], io) catch {};
        std.Io.Dir.cwd().rename(self.auto_files[0], std.Io.Dir.cwd(), self.auto_files[1], io) catch {};
        std.Io.Dir.cwd().rename(self.auto_tmp_file, std.Io.Dir.cwd(), self.auto_files[0], io) catch |err| {
            self.sim.pushLog("自动存档轮换失败 {s}", .{@errorName(err)});
            self.fillHudState();
            return;
        };
        self.sim.pushLog("自动存档：第 {d} 层", .{self.sim.floor});
        self.fillHudState();
    }

    pub fn openAutoMenu(self: *RunGame, io: std.Io) void {
        self.slot_menu = .auto_load;
        self.clearAim();
        self.show_help = false;
        self.panel = .none;
        self.refreshAutoLabels(io);
        self.fillHudState();
    }

    fn refreshAutoLabels(self: *RunGame, io: std.Io) void {
        var i: usize = 0;
        while (i < self.auto_files.len) : (i += 1) {
            self.slot_labels[i] = "空";
            const loaded = slot_bundle.loadFile(io, self.gpa, self.auto_files[i]) catch |err| {
                if (err != error.FileNotFound) self.slot_labels[i] = "坏档";
                continue;
            };
            self.slot_labels[i] = self.formatSlotLabel(i, &loaded.sim);
        }
    }

    pub fn loadAutoSlot(self: *RunGame, io: std.Io, slot: usize) void {
        if (slot >= self.auto_files.len) return;
        const loaded = slot_bundle.loadFile(io, self.gpa, self.auto_files[slot]) catch |err| {
            self.sim.pushLog("读档失败：{s}", .{loadErrorText(err)});
            self.slot_menu = .none;
            self.fillHudState();
            return;
        };
        self.applyLoaded(loaded.sim, loaded.gear);
        self.autosave_pending = false;
        self.slot_menu = .none;
        self.fillHudState();
    }

    pub fn saveRun(self: *RunGame, io: std.Io, sim_path: []const u8, gear_path: []const u8) void {
        if (self.sim.enemy_phase_pending) {
            self.sim.resolvePendingEnemyPhase();
            self.syncVisuals(false);
            self.fillHudState();
        }
        if (std.fs.path.dirname(sim_path)) |dir| {
            std.Io.Dir.cwd().createDirPath(io, dir) catch {};
        }
        save_mod.saveFile(io, self.gpa, sim_path, &self.sim) catch |err| {
            self.save_ok = false;
            self.sim.pushLog("存档失败 {s}", .{@errorName(err)});
            return;
        };
        gear_save.saveFileWithRng(io, self.gpa, gear_path, &self.inventory, &self.loot_rng) catch |err| {
            self.save_ok = false;
            self.sim.pushLog("装备存档失败 {s}", .{@errorName(err)});
            return;
        };
        self.save_ok = true;
        self.sim.pushLog("已存档", .{});
    }

    /// F9: load both halves. A missing/corrupt gear file leaves the current
    /// run alone; a fresh save still loads with an empty bag.
    /// Map save/load errors to a player-facing Chinese reason. The switch is
    /// exhaustive for SaveError; JSON and IO errors fall back to a generic line.
    fn loadErrorText(err: anyerror) []const u8 {
        return switch (err) {
            error.FileNotFound => "没有存档",
            error.AccessDenied => "没有权限读取存档",
            error.UnsupportedVersion => "v1 旧档不兼容，请开新局",
            error.NotSaveFormat => "不是 VX 存档文件",
            error.EmptySave => "存档为空",
            error.SaveTooLarge => "存档文件异常大",
            error.InvalidCoordinate => "存档坐标越界，可能来自旧地图版本",
            error.InvalidEnemyKind, error.InvalidEnemyName => "存档包含未知敌人",
            error.InvalidLog, error.InvalidRng, error.InvalidValue, error.InvalidState => "存档内容损坏",
            error.InconsistentMap => "存档地图不一致",
            error.TooManyEnemies => "存档敌人数量异常",
            error.OutOfMemory => "内存不足，无法读档",
            else => "存档损坏或无法读取",
        };
    }

    pub fn loadRun(self: *RunGame, io: std.Io, sim_path: []const u8, gear_path: []const u8) void {
        const loaded = save_mod.loadFile(io, self.gpa, sim_path) catch |err| {
            self.sim.pushLog("读档失败：{s}", .{loadErrorText(err)});
            return;
        };
        const gear = gear_save.loadFile(io, self.gpa, gear_path) catch |err| blk: {
            if (err == error.FileNotFound) break :blk gear_save.GearSave{};
            self.sim.pushLog("装备读档失败：{s}", .{loadErrorText(err)});
            return;
        };
        self.applyLoaded(loaded, gear);
    }

    fn applyLoaded(self: *RunGame, loaded: sim_mod.Sim, gear: gear_save.GearSave) void {
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
        self.sim.setEnemyDefs(self.content.enemies);
        self.seed = loaded.seed;
        self.class = loaded.class;
        self.difficulty = loaded.difficulty;
        self.last_state = loaded.state;
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
        self.last_level = loaded.hero.progression.level;
        self.selected = null;
        self.aim_talent = null;
        self.aim_cell = null;
        self.enemy_phase_timer = 0;
        self.autosave_pending = false;
        self.reset_armed = 0;
        self.step_cooldown = 0;
        self.show_help = false;
        self.panel = .none;
        self.started = true;
        self.shrine_open = self.sim.atShrine();
        self.shop_open = self.sim.atShop();
        self.rebuildMesh();
        self.resetVisuals();
        self.fillHudState();
        self.sim.pushLog("读档", .{});
    }

    fn rebuildMods(self: *RunGame) void {
        self.mods.rebuild(self.content.items, &self.inventory.equipped);
        self.sim.applyModifiers(self.mods.slice());
    }

    fn processLoot(self: *RunGame) void {
        while (self.chest_loot_seen < self.sim.chest_loot_events) {
            self.chest_loot_seen += 1;
            self.grantDrop(true);
        }
        while (self.kill_loot_seen < self.sim.kill_loot_events) {
            self.kill_loot_seen += 1;
            self.grantDrop(false);
        }
    }

    fn spendPendingPoint(self: *RunGame, stat: usize) void {
        if (!self.sim.spendPoint(stat)) return;
        self.rebuildMods();
        self.sim.pushLog("属性点已分配", .{});
        self.fillHudState();
    }

    pub fn autoPlayStep(self: *RunGame) void {
        if (!self.started or self.sim.state != .playing or self.panel != .none) return;
        self.sim.defer_enemies = false;
        self.sim.resolvePendingEnemyPhase();
        self.sim.auto_allocate = true;
        defer self.sim.auto_allocate = false;
        while (self.sim.hero.progression.pending_points > 0) {
            if (!self.sim.spendPoint(self.sim.mainStatIndex())) break;
        }
        self.rebuildMods();
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
        if (self.sim.hero.vitals.val < self.sim.hero.vitals.full * 0.35 and self.sim.nearestEnemy(4) == null) {
            _ = self.sim.wait();
            return;
        }

        // a nearby enemy is a good talent target; use the whole kit
        if (self.sim.nearestEnemy(5) != null) {
            if (self.class == .warrior and self.sim.hero.status.buff_turns == 0 and self.sim.hero.talents.cooldowns[2] == 0 and self.sim.hero.resource.val >= 20) {
                if (self.sim.useTalent(2)) return;
            }
            if (self.sim.useTalent(0)) return;
            if (self.sim.useTalent(1)) return;
            if (self.sim.hero.vitals.val < self.sim.hero.vitals.full * 0.4 and self.sim.useTalent(2)) return;
        }

        // Boss floor: stairs are sealed, so walk/fight toward the boss.
        if (self.sim.floor >= self.sim.floors) {
            var bi: ?usize = null;
            var ei: usize = 0;
            while (ei < self.sim.enemy_count) : (ei += 1) {
                const e = self.sim.enemies[ei];
                if (e.life.alive and e.identity.kind == 5) {
                    bi = ei;
                    break;
                }
            }
            if (bi) |idx| {
                const bp = self.sim.enemies[idx].pos;
                const bd: i32 = @intCast(@abs(bp.x - hero.x) + @abs(bp.y - hero.y));
                if (bd <= 5) {
                    if (self.sim.useTalentOn(0, idx)) return;
                    if (self.sim.useTalentOn(1, idx)) return;
                }
                if (self.sim.map.astarToOccupiedGoal(
                    .{ .x = hero.x, .y = hero.y },
                    .{ .x = bp.x, .y = bp.y },
                    null,
                )) |path| {
                    if (path.len > 1) {
                        const n = path.slice()[1];
                        if (self.sim.move(n.x - hero.x, n.y - hero.y)) return;
                    }
                }
            }
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

    fn equipBag(self: *RunGame, index: usize) void {
        if (index >= self.inventory.count()) return;
        const item = self.inventory.at(index);
        if (item >= self.content.items.len) return;
        const def = &self.content.items[item];
        if (def.slot() == null) {
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
        for (def.mods()) |m| {
            score += m.flat;
            score += m.pct * 20.0;
        }
        return score;
    }

    fn usePotion(self: *RunGame, allow_resource: bool) bool {
        for (self.inventory.slice()) |id| {
            if (id >= self.content.items.len) continue;
            const def = &self.content.items[id];
            const use = def.use() orelse continue;
            const need_hp = use.heal > 0 and self.sim.hero.vitals.val < self.sim.hero.vitals.full;
            const need_res = allow_resource and use.resource > 0 and self.sim.hero.resource.val < self.sim.hero.resource.full;
            if (!need_hp and !need_res) continue;
            if (!self.inventory.remove(id)) continue;
            self.clearAim();

            var hp_gain: f32 = 0;
            var res_gain: f32 = 0;
            if (need_hp) {
                const before = self.sim.hero.vitals.val;
                self.sim.hero.vitals.set(before + use.heal);
                hp_gain = self.sim.hero.vitals.val - before;
            }
            if (need_res) {
                const before = self.sim.hero.resource.val;
                self.sim.hero.resource.set(before + use.resource);
                res_gain = self.sim.hero.resource.val - before;
            }
            if (hp_gain > 0 and res_gain > 0) {
                self.sim.pushLog("{s} +{d:.0} HP +{d:.0} RES", .{ def.name, hp_gain, res_gain });
            } else if (hp_gain > 0) {
                self.sim.pushLog("{s} +{d:.0}", .{ def.name, hp_gain });
            } else {
                self.sim.pushLog("{s} +{d:.0} RES", .{ def.name, res_gain });
            }
            _ = self.sim.wait();
            return true;
        }
        return false;
    }

    pub fn debugGrantLoot(self: *RunGame, n: u32) void {
        var i: u32 = 0;
        while (i < n) : (i += 1) self.grantDrop(true);
        self.rebuildMods();
    }

    fn grantDrop(self: *RunGame, guaranteed: bool) void {
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
        if (def.slot()) |slot| {
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

    pub fn update(self: *RunGame, input: Input, dt_raw: f32) void {
        const dt = @min(0.05, dt_raw);
        self.dt = dt;
        self.time += dt;
        self.frame += 1;
        self.frame_ms = dt * 1000.0;
        self.fps = if (dt > 0) 1.0 / dt else 60.0;

        self.camera.yaw += input.yaw_delta;
        self.camera.distance = std.math.clamp(self.camera.distance - input.zoom_delta * 0.35, 7.0, 18.0);
        self.step_cooldown = @max(0, self.step_cooldown - dt);

        if (!self.started) {
            if (input.difficulty) self.toggleDifficulty();
            if (input.talent >= 0) self.selectClass(sim_mod.classFromIndex(@intCast(input.talent)));
            self.syncVisuals(false);
            self.updateVisuals(dt);
            self.followCamera();
            self.fillHudState();
            return;
        }

        if (self.shrine_open) {
            if (input.talent >= 0) {
                self.chooseShrine(@intCast(input.talent));
            } else if (input.stat == 3) {
                self.chooseShrine(3);
            }
            self.syncVisuals(false);
            self.updateVisuals(dt);
            self.followCamera();
            self.fillHudState();
            return;
        }

        if (self.shop_open) {
            if (input.talent >= 0) {
                self.buyShop(@intCast(input.talent));
            } else if (input.stat == 3) {
                self.buyShop(3);
            } else if (input.stat == 4) {
                self.buyShopLoot();
            }
            self.syncVisuals(false);
            self.updateVisuals(dt);
            self.followCamera();
            self.fillHudState();
            return;
        }

        if (self.slot_menu != .none) {
            self.fillHudState();
            return;
        }
        if (self.presentation) self.sim.defer_enemies = true;
        if (self.sim.enemy_phase_pending) {
            if (self.enemy_phase_timer <= 0) self.enemy_phase_timer = 0.30;
            self.enemy_phase_timer -= dt;
            if (self.enemy_phase_timer <= 0) {
                self.enemy_phase_timer = 0;
                self.sim.resolvePendingEnemyPhase();
                self.syncVisuals(false);
                self.updateVisuals(dt);
                self.followCamera();
                self.fillHudState();
            }
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
        if (input.target_next) {
            self.cycleTarget();
            if (self.aim_talent != null) self.aim_cell = null;
        }

        // Mouse: hover highlights the enemy under the cursor, left click
        // confirms an active aim (or selects when idle). HUD strips are not
        // pickable; this only maps the 3D ground plane.
        const over_log = input.mouse_x < 156 and input.mouse_y > @as(f32, @floatFromInt(self.renderer.height - 106)) and input.mouse_y < @as(f32, @floatFromInt(self.renderer.height - 66));
        if ((input.mouse_x > 0 or input.mouse_y > 0) and input.mouse_y >= 70 and input.mouse_y <= @as(f32, @floatFromInt(self.renderer.height - 60)) and !over_log) {
            if (self.pickCell(input.mouse_x, input.mouse_y)) |cell| {
                const maybe_enemy = self.sim.enemyAt(cell.x, cell.y);
                if (maybe_enemy) |idx| {
                    self.aim_cell = null;
                    if (self.aim_talent != null or input.click) self.selected = idx;
                    if (input.click and self.aim_talent != null) _ = self.confirmAim();
                } else if (self.aim_talent) |talent| {
                    if (self.class == .mage and talent == 0) {
                        self.aim_cell = cell;
                        if (input.click) {
                            const verdict = self.groundAimVerdict(talent, cell);
                            if (verdict == .ok) {
                                _ = self.confirmAim();
                            } else {
                                self.sim.pushLog("瞄准：{s}", .{target_mod.verdictText(verdict)});
                            }
                        }
                    } else if (input.click) {
                        self.sim.pushLog("无效目标", .{});
                    }
                }
            }
        }

        if (input.inventory) {
            self.clearAim();
            self.panel = if (self.panel == .inventory) .none else .inventory;
        }
        if (input.character) {
            self.clearAim();
            self.panel = if (self.panel == .character) .none else .character;
        }
        if (self.panel == .character and input.stat >= 0) {
            self.spendPendingPoint(@intCast(input.stat));
        }
        if (self.panel == .inventory and input.talent >= 0) {
            self.equipBag(@intCast(input.talent));
        }
        if (self.panel == .inventory and input.use_item) {
            _ = self.usePotion(true);
        }

        var used_potion = false;
        if (self.panel == .none and self.sim.state == .playing and input.use_item) {
            used_potion = self.usePotion(true);
        }
        if (!used_potion and self.panel == .none and self.sim.state == .playing and self.sim.hero.vitals.val < self.sim.hero.vitals.full * 0.35) {
            used_potion = self.usePotion(false);
        }

        if (!used_potion and self.panel == .none and self.sim.state == .playing) {
            if ((input.step_x != 0 or input.step_y != 0) and self.step_cooldown <= 0) {
                // Walking away abandons the pending aim (no turn spent on the
                // cancel itself; the step below costs its usual turn).
                self.clearAim();
                self.step_cooldown = 0.30;
                const before_hero = self.sim.hero.vitals.val;
                var before: [sim_mod.max_enemies]f32 = undefined;
                var bi: usize = 0;
                while (bi < self.sim.enemy_count) : (bi += 1) before[bi] = self.sim.enemies[bi].vitals.val;
                const moved = self.sim.move(input.step_x, input.step_y);
                if (!moved) {
                    self.sim.pushLog("前方被挡住", .{});
                } else if (self.sim.state == .playing and self.sim.atShrine()) {
                    self.shrine_open = true;
                    self.clearAim();
                } else if (self.sim.state == .playing and self.sim.atShop()) {
                    self.shop_open = true;
                    self.clearAim();
                }
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
        if (self.sim.hero.progression.level != self.last_level) {
            self.last_level = self.sim.hero.progression.level;
            self.rebuildMods();
        }

        if (self.sim.state != .playing) self.clearAim();

        if (self.sim.floor != self.mesh_floor) {
            self.clearAim();
            self.rebuildMesh();
            self.syncVisuals(true);
            self.autosave_pending = true;
        }

        self.syncVisuals(false);
        self.updateVisuals(dt);
        self.followCamera();
        self.fillHudState();
    }

    /// Keep the whole room on screen while still following the hero: clamp the
    /// look-at point to the middle band and bias it toward the hero.
    fn followCamera(self: *RunGame) void {
        const half_extent = @as(f32, @floatFromInt(sim_mod.grid_w - 1)) * 0.5;
        const margin = 3.0;
        self.camera.target.x = std.math.clamp(self.hero_vis.pos.x, -half_extent + margin, half_extent - margin);
        self.camera.target.z = std.math.clamp(self.hero_vis.pos.z, -half_extent + margin, half_extent - margin);
        self.camera.target.y = 0.35;
        self.camera_target = self.camera.target;
    }

    fn spawnFloat(self: *RunGame, pos: math.Vec3, value: i32, color_value: u32) void {
        if (value == 0) return;
        const i = self.float_cursor;
        self.float_cursor = (i + 1) % self.floats.len;
        self.floats[i] = .{ .pos = pos.add(math.Vec3.init(0, 1.4, 0)), .value = value, .life = 0.75, .color = color_value };
    }

    fn drawFloats(self: *RunGame) void {
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

    /// Screen pixel -> simulation cell, clamped by the camera's ground-plane
    /// intersection. Used by mouse aiming.
    fn pickCell(self: *const RunGame, sx: f32, sy: f32) ?sim_mod.GridPos {
        const p = self.camera.pickGround(sx, sy, self.renderer.width, self.renderer.height) orelse return null;
        const center = @as(f32, @floatFromInt(sim_mod.grid_w - 1)) * 0.5;
        const gx: i32 = @intFromFloat(@round(p.x + center));
        const gy: i32 = @intFromFloat(@round(p.z + center));
        if (gx < 0 or gy < 0 or gx >= sim_mod.grid_w or gy >= sim_mod.grid_h) return null;
        return .{ .x = gx, .y = gy };
    }

    fn currentTarget(self: *const RunGame) ?usize {
        if (self.selected) |s| {
            if (s < self.sim.enemy_count and self.sim.enemies[s].life.alive) return s;
        }
        return self.sim.nearestEnemy(20);
    }

    fn cycleTarget(self: *RunGame) void {
        if (self.sim.enemy_count == 0) {
            self.selected = null;
            return;
        }
        var start: usize = 0;
        if (self.selected) |s| start = (s + 1) % self.sim.enemy_count;
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            const idx = (start + i) % self.sim.enemy_count;
            if (self.sim.enemies[idx].life.alive) {
                self.selected = idx;
                return;
            }
        }
        self.selected = null;
    }

    pub fn isAiming(self: *const RunGame) bool {
        return self.aim_talent != null;
    }

    /// Escape path: aim is consumed first, so Esc never drops the run while
    /// the player is only cancelling a target. Returns true when consumed.
    pub fn cancelAim(self: *RunGame) bool {
        if (self.aim_talent == null) return false;
        self.aim_talent = null;
        self.aim_cell = null;
        self.sim.pushLog("取消瞄准", .{});
        return true;
    }

    fn clearAim(self: *RunGame) void {
        self.aim_talent = null;
        self.aim_cell = null;
    }

    /// Currently highlighted enemy. Falls back to the nearest living enemy at
    /// any distance so an out-of-range target can still be previewed in red.
    fn aimTarget(self: *const RunGame) ?usize {
        return self.currentTarget();
    }

    /// Prefer the current target when it is already legal; otherwise snap to
    /// the nearest legal enemy so pressing 1/2/3 does not open on a red
    /// out-of-range preview when a valid target is available.
    fn bestAimTarget(self: *const RunGame, talent: usize) ?usize {
        if (self.aimTarget()) |cur| {
            if (target_mod.preview(&self.sim, talent, cur).valid()) return cur;
        }
        var best: ?usize = null;
        var best_d: i32 = 0;
        for (self.sim.enemies[0..self.sim.enemy_count], 0..) |e, i| {
            if (!e.life.alive) continue;
            const p = target_mod.preview(&self.sim, talent, i);
            if (!p.valid()) continue;
            if (best == null or p.distance < best_d) {
                best = i;
                best_d = p.distance;
            }
        }
        return best orelse self.aimTarget();
    }

    /// Fireball is the only ground-targeted v1 talent. Returns the same
    /// verdict vocabulary as enemy aim so the HUD can reuse its strings.
    fn groundAimVerdict(self: *const RunGame, talent: usize, cell: sim_mod.GridPos) target_mod.Verdict {
        if (!(self.class == .mage and talent == 0)) return .not_targetable;
        if (self.sim.state != .playing) return .not_playing;
        if (self.sim.hero.talents.cooldowns[talent] > 0) return .cooldown;
        if (self.sim.hero.resource.val < @as(f32, @floatFromInt(self.sim.talentCost(talent)))) return .no_resource;
        if (self.sim.isBlocked(cell.x, cell.y)) return .blocked_cell;
        if (target_mod.distance(self.sim.hero.pos, cell) > 5) return .out_of_range;
        if (!self.sim.map.lineOfSightTo(
            .{ .x = self.sim.hero.pos.x, .y = self.sim.hero.pos.y },
            .{ .x = cell.x, .y = cell.y },
            null,
        )) return .no_line_of_sight;
        return .ok;
    }

    fn beginAim(self: *RunGame, talent: usize) void {
        const name = self.sim.talentName(talent);
        if (self.sim.hero.talents.cooldowns[talent] > 0) {
            self.sim.pushLog("{s} 冷却中", .{name});
            return;
        }
        if (self.sim.hero.resource.val < @as(f32, @floatFromInt(self.sim.talentCost(talent)))) {
            self.sim.pushLog("{s} 缺资源", .{name});
            return;
        }
        self.aim_talent = talent;
        self.aim_cell = null;
        self.selected = self.bestAimTarget(talent);
        self.sim.pushLog("瞄准 {s}：空格确认", .{name});
    }

    fn switchAim(self: *RunGame, talent: usize) void {
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
    fn talentKey(self: *RunGame, talent: usize) void {
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

    fn castTalentAt(self: *RunGame, talent: usize, target: ?usize) bool {
        const before_hero = self.sim.hero.vitals.val;
        var before: [sim_mod.max_enemies]f32 = undefined;
        var bi: usize = 0;
        while (bi < self.sim.enemy_count) : (bi += 1) before[bi] = self.sim.enemies[bi].vitals.val;
        const used = self.sim.useTalentOn(talent, target);
        if (used) {
            self.hero_vis.anim.cast = 1.0;
            self.flashAfter(before_hero, before[0..bi]);
        }
        return used;
    }

    fn castTalentAtCell(self: *RunGame, talent: usize, cell: sim_mod.GridPos) bool {
        const before_hero = self.sim.hero.vitals.val;
        var before: [sim_mod.max_enemies]f32 = undefined;
        var bi: usize = 0;
        while (bi < self.sim.enemy_count) : (bi += 1) before[bi] = self.sim.enemies[bi].vitals.val;
        const used = self.sim.useTalentAt(talent, cell);
        if (used) {
            self.hero_vis.anim.cast = 1.0;
            self.flashAfter(before_hero, before[0..bi]);
        }
        return used;
    }

    fn releaseTalent(self: *RunGame, talent: usize) bool {
        if (self.castTalentAt(talent, self.selected)) return true;
        self.sim.pushLog("技能不可用", .{});
        return false;
    }

    /// Confirm the pending aim. Validation failure logs a reason and leaves
    /// the turn and resource untouched; success spends exactly one turn.
    fn confirmAim(self: *RunGame) bool {
        const talent = self.aim_talent orelse return false;
        if (self.aim_cell) |cell| {
            const verdict = self.groundAimVerdict(talent, cell);
            if (verdict != .ok) {
                self.sim.pushLog("瞄准：{s}", .{target_mod.verdictText(verdict)});
                return false;
            }
            const turn_before = self.sim.turn;
            if (!self.castTalentAtCell(talent, cell)) {
                self.sim.pushLog("技能不可用", .{});
                return false;
            }
            self.aim_talent = null;
            self.aim_cell = null;
            if (self.sim.turn == turn_before) {
                self.sim.pushLog("技能未生效", .{});
                return false;
            }
            return true;
        }
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

    fn flashAfter(self: *RunGame, hero_before: f32, enemies_before: []const f32) void {
        const hero_loss = hero_before - self.sim.hero.vitals.val;
        if (hero_loss > 0.5) {
            self.hero_vis.flash = 0.22;
            self.spawnFloat(self.hero_vis.pos, -@as(i32, @intFromFloat(hero_loss)), palette.red);
        }
        var i: usize = 0;
        while (i < enemies_before.len and i < self.sim.enemy_count) : (i += 1) {
            const loss = enemies_before[i] - self.sim.enemies[i].vitals.val;
            if (loss > 0.5) {
                self.enemy_vis[i].flash = 0.22;
                self.spawnFloat(self.enemy_vis[i].pos, -@as(i32, @intFromFloat(loss)), palette.gold_light);
            }
        }
    }

    fn syncVisuals(self: *RunGame, full: bool) void {
        const hp = tilePos(self.sim.hero.pos.x, self.sim.hero.pos.y);
        self.hero_vis.target = hp;
        if (full) self.hero_vis.pos = hp;
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            const e = self.sim.enemies[i];
            const p = tilePos(e.pos.x, e.pos.y);
            self.enemy_vis[i].target = p;
            if (full) self.enemy_vis[i].pos = p;
            self.enemy_vis[i].anim.kind = enemyAnimKind(e.identity.kind);
            const dx = p.x - self.enemy_vis[i].pos.x;
            const dz = p.z - self.enemy_vis[i].pos.z;
            if (@abs(dx) + @abs(dz) > 0.02) self.enemy_vis[i].target_yaw = std.math.atan2(dx, dz);
        }
    }

    fn updateVisuals(self: *RunGame, dt: f32) void {
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

    fn heroModel(self: *RunGame) *const model_mod.Model {
        const names = [_][]const u8{ "warrior", "archmage", "chronomancer" };
        return self.models.at(self.models.indexOf(names[@backingInt(self.class)]) orelse 0);
    }

    fn enemyModel(self: *RunGame, kind: u8) *const model_mod.Model {
        const names = [_][]const u8{ "skeleton", "wraith", "golem", "elite_skeleton", "elite_wraith", "abyss_guard", "wraith" };
        const fallback = [_][]const u8{ "skeleton", "wraith", "golem", "skeleton", "wraith", "abyss_guard", "wraith" };
        const name = names[@min(kind, names.len - 1)];
        if (self.models.indexOf(name)) |i| return self.models.at(i);
        return self.models.at(self.models.indexOf(fallback[@min(kind, fallback.len - 1)]) orelse 0);
    }

    pub fn render(self: *RunGame) void {
        self.renderer.begin(self.camera, self.time);
        self.addLights();

        self.renderer.drawMesh(&self.mesh, math.Mat4.identity, .{ .id = 1 });

        // shadows and feet rings
        self.renderer.drawShadow(self.hero_vis.pos.add(math.Vec3.init(0.06, 0, -0.04)), 0.30);
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            if (!self.sim.enemies[i].life.alive) continue;
            self.renderer.drawShadow(self.enemy_vis[i].pos.add(math.Vec3.init(0.06, 0, -0.04)), 0.32 * enemyScale(self.sim.enemies[i].identity.kind));
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
            if (!e.life.alive) continue;
            var ep: rig.Pose = .{};
            rig.compute(self.enemyModel(e.identity.kind), self.enemy_vis[i].anim, &ep);
            const affix_tint: u32 = switch (e.affix) {
                .swift => color.pack(170, 235, 255),
                .armored => color.pack(220, 210, 185),
                .vampiric => color.pack(255, 150, 165),
                else => 0xffffff,
            };
            const tint = if (self.enemy_vis[i].flash > 0) color.pack(255, 110, 90) else affix_tint;
            self.renderer.drawModel(self.enemyModel(e.identity.kind), ep.joints[0..ep.count], math.Mat4.compose(self.enemy_vis[i].pos, self.enemy_vis[i].yaw, 0, 0, enemyScale(e.identity.kind)), .{
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

    fn drawWorldBars(self: *RunGame) void {
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
            if (!e.life.alive) continue;
            const p = self.camera.project(self.enemy_vis[i].pos.add(math.Vec3.init(0, 2.0, 0)), self.renderer.width, self.renderer.height) orelse continue;
            if (p.depth <= 0.1) continue;
            const x: i32 = @intFromFloat(p.x);
            const y: i32 = @intFromFloat(p.y);
            if (x < -30 or x > w + 30 or y < -20 or y > h + 20) continue;
            const bw: i32 = 18 + @as(i32, @intFromFloat(@min(18.0, e.vitals.full / 22.0)));
            self.renderer.fillRect(x - @divTrunc(bw, 2), y, bw, 3, palette.deep);
            const frac = if (e.vitals.full > 0) std.math.clamp(e.vitals.val / e.vitals.full, 0, 1) else 0;
            const fill: i32 = @intFromFloat(@as(f32, @floatFromInt(bw - 2)) * frac);
            if (fill > 0) self.renderer.fillRect(x - @divTrunc(bw, 2) + 1, y + 1, fill, 1, palette.red);
            self.renderer.strokeRect(x - @divTrunc(bw, 2), y, bw, 3, palette.muted);
            if (self.sim.intentFor(i)) |intent| {
                var ibuf: [24]u8 = undefined;
                const label = switch (intent.kind) {
                    .aoe => std.fmt.bufPrint(&ibuf, "深渊斩 -{d:.0}", .{intent.damage_preview}) catch "",
                    .melee => std.fmt.bufPrint(&ibuf, "攻击 -{d:.0}", .{intent.damage_preview}) catch "",
                    .ranged => std.fmt.bufPrint(&ibuf, "远程 -{d:.0}", .{intent.damage_preview}) catch "",
                    .chase => "追击",
                    .wait => "晕",
                };
                if (label.len > 0) {
                    var aim_buf: [48]u8 = undefined;
                    var shown: []const u8 = label;
                    var label_col: u32 = if (intent.kind == .aoe) palette.red else palette.gold_light;
                    if (self.aim_talent) |talent| {
                        const verdict = target_mod.preview(&self.sim, talent, i).verdict;
                        const tag = if (verdict == .ok) "OK" else "OUT";
                        shown = std.fmt.bufPrint(&aim_buf, "{s} {s}", .{ tag, label }) catch label;
                        label_col = if (verdict == .ok) color.pack(80, 235, 150) else color.pack(255, 64, 64);
                    }
                    const ix = std.math.clamp(x - @divTrunc(renderer.Renderer.textWidth(shown, 1), 2), 2, w - 2);
                    self.renderer.drawText(ix, y + 5, shown, label_col, 1, true);
                }
                const affix_label: []const u8 = switch (self.sim.enemies[i].affix) {
                    .swift => "SWIFT",
                    .armored => "ARM",
                    .vampiric => "VAMP",
                    else => "",
                };
                if (affix_label.len > 0) {
                    const ax = std.math.clamp(x - renderer.Renderer.textWidth(affix_label, 1), 2, w - 2);
                    self.renderer.drawText(ax, y + 15, affix_label, palette.cyan_light, 1, true);
                }
                if (self.sim.enemies[i].status.burn_turns > 0) {
                    var burn_buf: [24]u8 = undefined;
                    const burn_label = if (self.sim.enemies[i].status.burn_stacks > 1)
                        std.fmt.bufPrint(&burn_buf, "灼x{d}", .{self.sim.enemies[i].status.burn_stacks}) catch "灼"
                    else
                        "灼";
                    const bx = std.math.clamp(x - renderer.Renderer.textWidth(burn_label, 1), 2, w - 2);
                    self.renderer.drawText(bx, y + 24, burn_label, palette.red, 1, true);
                }
                const cc_label: []const u8 = if (self.sim.enemies[i].status.stun_turns > 0)
                    status_def.tag(.stun)
                else if (self.sim.enemies[i].status.slow_turns > 0)
                    status_def.tag(.slow)
                else
                    "";
                if (cc_label.len > 0) {
                    const cx = std.math.clamp(x - renderer.Renderer.textWidth(cc_label, 1), 2, w - 2);
                    self.renderer.drawText(cx, y + 33, cc_label, if (std.mem.eql(u8, cc_label, status_def.tag(.stun))) status_def.get(.stun).color else status_def.get(.slow).color, 1, true);
                }
                if (self.sim.enemies[i].status.vulnerable_turns > 0) {
                    const vtag = status_def.tag(.vulnerable);
                    const vx = std.math.clamp(x - renderer.Renderer.textWidth(vtag, 1), 2, w - 2);
                    self.renderer.drawText(vx, y + 42, vtag, status_def.get(.vulnerable).color, 1, true);
                }
                if (self.sim.enemies[i].status.guard_turns > 0) {
                    const gtag = status_def.tag(.guard);
                    const gx = std.math.clamp(x - renderer.Renderer.textWidth(gtag, 1), 2, w - 2);
                    self.renderer.drawText(gx, y + 51, gtag, status_def.get(.guard).color, 1, true);
                }
                if (self.sim.enemies[i].status.stun_immune) {
                    const bx = std.math.clamp(x - renderer.Renderer.textWidth("BOSS", 1), 2, w - 2);
                    self.renderer.drawText(bx, y + 15, "BOSS", palette.red, 1, true);
                    if (self.sim.boss_enraged) {
                        self.renderer.drawText(bx, y + 24, "RAGE", palette.gold, 1, true);
                    }
                }
            }
            if (target != null and target.? == i) {
                const aiming = self.aim_talent != null;
                const aim_ok = if (self.aim_talent) |talent|
                    target_mod.preview(&self.sim, talent, i).valid()
                else
                    true;
                const aim_col: u32 = if (aim_ok) color.pack(80, 235, 150) else color.pack(255, 64, 64);
                var tbuf: [64]u8 = undefined;
                const speed_mark = if (e.combat.speed.val >= 150) " x2" else if (e.combat.speed.val <= 75) " 慢" else "";
                const tname = std.fmt.bufPrint(&tbuf, "{s} {d:.0}/{d:.0}{s}", .{ e.identity.name, e.vitals.val, e.vitals.full, speed_mark }) catch e.identity.name;
                const tw = renderer.Renderer.textWidth(tname, 1);
                const lx = std.math.clamp(x - @divTrunc(tw, 2), 2, w - tw - 2);
                const ly = @max(68, y - 13);
                self.renderer.fillRect(lx - 3, ly, tw + 6, 11, palette.panel);
                self.renderer.strokeRect(lx - 3, ly, tw + 6, 11, if (aiming) aim_col else palette.border);
                self.renderer.drawText(lx, ly + 1, tname, if (aiming) aim_col else palette.red, 1, true);
            }
        }
    }

    fn addLights(self: *RunGame) void {
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
            if (!self.sim.enemies[i].life.alive) continue;
            if (self.sim.enemies[i].identity.kind == 5) {
                self.renderer.addLight(.{
                    .pos = self.enemy_vis[i].pos.add(math.Vec3.init(0, 1.2, 0)),
                    .color = .{ .x = 1.0, .y = 0.16, .z = 0.12 },
                    .intensity = 1.4,
                    .radius = 3.8,
                });
            }
        }
    }

    fn drawRings(self: *RunGame) void {
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
            if (!self.sim.enemies[i].life.alive) continue;
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
    fn drawAimMarkers(self: *RunGame) void {
        const talent = self.aim_talent orelse return;
        const ring_index = self.models.indexOf("rune_circle") orelse return;
        const ring_model = self.models.at(ring_index);
        if (self.aim_cell) |cell| {
            const verdict = self.groundAimVerdict(talent, cell);
            const accent: u32 = if (verdict == .ok) color.pack(255, 168, 74) else color.pack(220, 70, 50);
            self.renderer.drawModel(ring_model, null, math.Mat4.compose(tilePos(cell.x, cell.y).add(math.Vec3.init(0, 0.06, 0)), self.time * 0.9, 0, 0, 0.62), .{
                .tint = accent,
                .boost = 1.1,
                .additive = false,
                .alpha = 0.96,
            });
            var dy: i32 = -1;
            while (dy <= 1) : (dy += 1) {
                var dx: i32 = -1;
                while (dx <= 1) : (dx += 1) {
                    if (@abs(dx) + @abs(dy) > 1) continue;
                    const x = cell.x + dx;
                    const y = cell.y + dy;
                    if (x < 0 or y < 0 or x >= sim_mod.grid_w or y >= sim_mod.grid_h) continue;
                    const pos = tilePos(x, y).add(math.Vec3.init(0, 0.045, 0));
                    self.renderer.drawModel(ring_model, null, math.Mat4.compose(pos, -self.time * 0.35, 0, 0, 0.40), .{
                        .tint = accent,
                        .boost = 0.8,
                        .additive = true,
                        .alpha = 0.55,
                    });
                }
            }
            return;
        }
        // Range readability: every living enemy gets a green/red ground ring
        // while aiming, so the player can pick a legal target without reading
        // the hint line. The selected target is drawn larger below.
        var ri: usize = 0;
        while (ri < self.sim.enemy_count) : (ri += 1) {
            const e = self.sim.enemies[ri];
            if (!e.life.alive) continue;
            const verdict = target_mod.preview(&self.sim, talent, ri).verdict;
            const ring_tint: u32 = if (verdict == .ok) color.pack(80, 235, 150) else color.pack(255, 64, 64);
            const pos = tilePos(e.pos.x, e.pos.y).add(math.Vec3.init(0, 0.07, 0));
            self.renderer.drawGlow(pos, 0.46, ring_tint, 0.45);
            self.renderer.drawModel(ring_model, null, math.Mat4.compose(pos, self.time * 0.7, 0, 0, 0.52), .{
                .tint = ring_tint,
                .boost = 1.1,
                .additive = false,
                .alpha = 0.92,
            });
        }
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

    fn drawProps(self: *RunGame) void {
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
                const tint: u32 = if (self.sim.chest_cursed[i]) 0xe05a5a else 0xffffff;
                self.renderer.drawModel(self.models.at(ci), null, math.Mat4.compose(tilePos(self.sim.chests[i].x, self.sim.chests[i].y), 0, 0, 0, 0.72), .{ .tint = tint, .id = @intCast(60 + i) });
            } else {
                self.renderer.drawGlow(tilePos(self.sim.chests[i].x, self.sim.chests[i].y).add(math.Vec3.init(0, 0.2, 0)), 0.25, palette.gold_light, 0.8);
            }
            if (self.sim.chest_cursed[i]) {
                self.renderer.drawGlow(tilePos(self.sim.chests[i].x, self.sim.chests[i].y).add(math.Vec3.init(0, 0.25, 0)), 0.35, palette.red, 0.55);
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

        if (self.sim.shrine_active and !self.sim.shrine_used) {
            const shrine_pos = tilePos(self.sim.shrine.x, self.sim.shrine.y);
            self.renderer.drawGlow(shrine_pos.add(math.Vec3.init(0, 0.55, 0)), 0.75, palette.cyan_light, 0.75);
            if (self.models.indexOf("brazier")) |bi| {
                self.renderer.drawModel(self.models.at(bi), null, math.Mat4.compose(shrine_pos, 0, 0, 0, 1.0), .{ .tint = palette.cyan_light, .id = 90 });
            }
            if (self.models.indexOf("rune_circle")) |ri| {
                self.renderer.drawModel(self.models.at(ri), null, math.Mat4.compose(shrine_pos.add(math.Vec3.init(0, 0.04, 0)), self.time * 0.6, 0, 0, 0.7), .{ .tint = palette.cyan_light, .id = 91 });
            }
        }

        if (self.sim.shop_active and !self.sim.shop_used) {
            const shop_pos = tilePos(self.sim.shop.x, self.sim.shop.y);
            self.renderer.drawGlow(shop_pos.add(math.Vec3.init(0, 0.45, 0)), 0.55, palette.gold_light, 0.65);
            if (self.models.indexOf("dungeon_chest")) |ci| {
                self.renderer.drawModel(self.models.at(ci), null, math.Mat4.compose(shop_pos, 0, 0, 0, 0.78), .{ .tint = palette.gold_light, .id = 92 });
            }
        }
    }

    fn shortEnemyName(name: []const u8) []const u8 {
        if (name.len >= 6) return name[0..6];
        return name;
    }

    fn initiativeNames(self: *const RunGame) [3][]const u8 {
        var names = [3][]const u8{ "玩家", "", "" };
        var first: ?usize = null;
        var second: ?usize = null;
        var i: usize = 0;
        while (i < self.sim.enemy_count) : (i += 1) {
            const e = self.sim.enemies[i];
            if (!e.life.alive) continue;
            if (first == null or e.combat.speed.val > self.sim.enemies[first.?].combat.speed.val) {
                second = first;
                first = i;
            } else if (second == null or e.combat.speed.val > self.sim.enemies[second.?].combat.speed.val) {
                second = i;
            }
        }
        if (first) |idx| names[1] = shortEnemyName(self.sim.enemies[idx].identity.name);
        if (second) |idx| names[2] = shortEnemyName(self.sim.enemies[idx].identity.name);
        return names;
    }

    fn plotMinimap(self: *RunGame, gx: i32, gy: i32, value: u8) void {
        const mm: i32 = 13;
        if (gx < 0 or gy < 0 or gx >= sim_mod.grid_w or gy >= sim_mod.grid_h) return;
        const mx = @min(mm - 1, @divTrunc(gx * mm, @as(i32, @intCast(sim_mod.grid_w))));
        const my = @min(mm - 1, @divTrunc(gy * mm, @as(i32, @intCast(sim_mod.grid_h))));
        self.hud_state.minimap[@as(usize, @intCast(my)) * 13 + @as(usize, @intCast(mx))] = value;
    }

    fn itemPower(def: items_mod.ItemDef) f32 {
        var score: f32 = 0;
        for (def.mods()) |m| {
            const weight: f32 = switch (m.stat) {
                .strength, .agility, .constitution, .perception, .magic, .will => 8,
                .hp_max => 1,
                .resource_max => 0.5,
                .attack => 5,
                .armor => 4,
                .crit => 150,
                .speed => 1,
                .resource_per_turn => 2,
            };
            score += m.flat * weight + m.pct * 300;
        }
        return score;
    }

    fn fillHudState(self: *RunGame) void {
        self.trackRunEnd();
        const initiative = self.initiativeNames();
        var potion_count: u8 = 0;
        for (self.inventory.slice()) |id| {
            if (id >= self.content.items.len) continue;
            if (self.content.items[id].use() != null) potion_count +|= 1;
        }
        self.hud_state = .{
            .menu = !self.started,
            .help = self.show_help,
            .menu_seed = self.seed,
            .difficulty = @backingInt(self.difficulty),
            .shrine_open = self.shrine_open,
            .shrine_main_label = self.sim.shrineMainLabel(),
            .record_wins = self.records.wins,
            .gold = self.sim.gold,
            .shop_open = self.shop_open,
            .record_best_floor = self.records.best_floor,
            .record_best_turn = self.records.best_turn,
            .potions = potion_count,
            .floor_mod_label = self.sim.floor_mod.label(),
            .seed = self.sim.seed,
            .buff_turns = self.sim.hero.status.buff_turns,
            .buff_pct = self.sim.hero.status.buff_pct,
            .burn_turns = self.sim.hero.status.burn_turns,
            .burn_damage = self.sim.hero.status.burn_damage,
            .burn_stacks = self.sim.hero.status.burn_stacks,
            .vulnerable_turns = self.sim.hero.status.vulnerable_turns,
            .class_name = sim_mod.class_names[@backingInt(self.class)],
            .level = self.sim.hero.progression.level,
            .xp = self.sim.hero.progression.xp,
            .xp_next = 100 * self.sim.hero.progression.level,
            .hp = self.sim.hero.vitals.val,
            .hp_max = self.sim.hero.vitals.full,
            .resource = self.sim.hero.resource.val,
            .resource_max = self.sim.hero.resource.full,
            .resource_label = sim_mod.resource_names[@backingInt(self.class)],
            .turn = self.sim.turn,
            .floor = self.sim.floor,
            .floors = self.sim.floors,
            .enemy_phase = self.sim.enemy_phase_pending,
            .slot_mode = @backingInt(self.slot_menu),
            .slot_labels = self.slot_labels,
            .initiative = initiative,
            .initiative_count = if (initiative[2].len > 0) 3 else if (initiative[1].len > 0) 2 else 1,
            .kills = self.sim.kills,
            .enemies_left = @intCast(self.sim.enemy_count - blk: {
                var n: u32 = 0;
                for (self.sim.enemies[0..self.sim.enemy_count]) |e| {
                    if (!e.life.alive) n += 1;
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
            const affordable = self.sim.hero.resource.val >= @as(f32, @floatFromInt(cost));
            self.hud_state.hotbar[i] = .{
                .name = self.sim.talentName(i),
                .cost = cost,
                .cooldown = self.sim.hero.talents.cooldowns[i],
                .cooldown_max = self.sim.talentCooldown(i),
                .ready = self.sim.state == .playing and self.sim.hero.talents.cooldowns[i] == 0 and affordable,
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
            self.hud_state.target_name = e.identity.name;
            self.hud_state.target_hp = e.vitals.val;
            self.hud_state.target_hp_max = e.vitals.full;
            const dx = e.pos.x - self.sim.hero.pos.x;
            const dy = e.pos.y - self.sim.hero.pos.y;
            self.hud_state.target_range = @intCast(@abs(dx) + @abs(dy));
        }
        self.hud_state.aim = .{};
        if (self.aim_talent) |talent| {
            if (self.aim_cell) |cell| {
                const verdict = self.groundAimVerdict(talent, cell);
                self.hud_state.aim = .{
                    .active = true,
                    .valid = verdict == .ok,
                    .talent_index = talent,
                    .talent = self.sim.talentName(talent),
                    .target = "地面",
                    .distance = target_mod.distance(self.sim.hero.pos, cell),
                    .damage = 0,
                    .aoe_radius = 1,
                    .reason = if (verdict == .ok) "" else target_mod.verdictText(verdict),
                };
            } else {
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
                if (p.target) |ti| aim.target = self.sim.enemies[ti].identity.name;
                self.hud_state.aim = aim;
            }
        }
        const attrs = [_]i32{
            @intFromFloat(self.sim.hero.sheet.eff_stats[0]),
            @intFromFloat(self.sim.hero.sheet.eff_stats[1]),
            @intFromFloat(self.sim.hero.sheet.eff_stats[2]),
            @intFromFloat(self.sim.hero.sheet.eff_stats[3]),
            @intFromFloat(self.sim.hero.sheet.eff_stats[4]),
            @intFromFloat(self.sim.hero.sheet.eff_stats[5]),
        };
        self.hud_state.attrs = attrs;
        self.hud_state.pending_points = self.sim.hero.progression.pending_points;
        self.hud_state.attack = self.sim.hero.combat.attack.val;
        self.hud_state.armor = self.sim.hero.combat.armor.val;
        self.hud_state.crit = self.sim.hero.combat.crit.val;
        self.hud_state.speed = self.sim.hero.combat.speed.val;
        self.hud_state.res_per_turn = self.sim.hero.resource_regen.val;
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
            if (item < self.content.items.len) {
                const def = &self.content.items[item];
                self.hud_state.items[ii] = def.name;
                self.hud_state.item_details[ii] = writeItemDetail(&self.item_detail_bufs[ii], def);
            } else {
                self.hud_state.items[ii] = "";
                self.hud_state.item_details[ii] = "";
            }
        }
        self.hud_state.item_deltas = @splat(0);
        self.hud_state.item_delta_valid = @splat(false);
        self.hud_state.item_delta_new = @splat(false);
        var di: usize = 0;
        while (di < self.hud_state.item_count) : (di += 1) {
            const item = self.inventory.at(di);
            if (item >= self.content.items.len) continue;
            const def = &self.content.items[item];
            const slot = def.slot() orelse continue;
            const equipped = self.inventory.equipped.get(slot);
            self.hud_state.item_delta_valid[di] = true;
            if (equipped) |eq| {
                if (eq >= self.content.items.len) continue;
                const delta = itemPower(def.*) - itemPower(self.content.items[eq]);
                self.hud_state.item_deltas[di] = @intFromFloat(@round(delta));
            } else {
                self.hud_state.item_delta_new[di] = true;
            }
        }

        self.hud_state.has_minimap = true;
        self.hud_state.minimap = @splat(0);
        const mm = 13;
        var my: usize = 0;
        while (my < mm) : (my += 1) {
            var mx: usize = 0;
            while (mx < mm) : (mx += 1) {
                const gx = @min(sim_mod.grid_w - 1, mx * sim_mod.grid_w / mm);
                const gy = @min(sim_mod.grid_h - 1, my * sim_mod.grid_h / mm);
                self.hud_state.minimap[my * mm + mx] = if (self.sim.blocked[gy * sim_mod.grid_w + gx]) 1 else 0;
            }
        }
        self.plotMinimap(self.sim.stairs.x, self.sim.stairs.y, 2);
        if (self.sim.shrine_active and !self.sim.shrine_used) self.plotMinimap(self.sim.shrine.x, self.sim.shrine.y, 6);
        var ci: usize = 0;
        while (ci < self.sim.chests.len) : (ci += 1) {
            if (!self.sim.chest_alive[ci]) continue;
            const cp = self.sim.chests[ci];
            self.plotMinimap(cp.x, cp.y, if (self.sim.chest_cursed[ci]) 7 else 3);
        }
        var ei: usize = 0;
        while (ei < self.sim.enemy_count) : (ei += 1) {
            const e = self.sim.enemies[ei];
            if (!e.life.alive) continue;
            self.plotMinimap(e.pos.x, e.pos.y, 5);
        }
        self.plotMinimap(self.sim.hero.pos.x, self.sim.hero.pos.y, 4);
        self.hud_state.log_count = @min(self.sim.log_total, 4);
        i = 0;
        while (i < self.hud_state.log_count) : (i += 1) {
            const start = (self.sim.log_head + self.sim.log_buf.len - self.hud_state.log_count) % self.sim.log_buf.len;
            self.hud_state.log_lines[i] = self.sim.log_buf[(start + i) % self.sim.log_buf.len].text[0..self.sim.log_buf[(start + i) % self.sim.log_buf.len].len];
        }
    }

    pub fn saveScreenshot(self: *RunGame, io: std.Io, path: []const u8) !void {
        try png.writePng(io, self.gpa, path, self.renderer.width, self.renderer.height, self.renderer.color_buf);
    }
};

test "run game: unlocked run rolls a new seed on restart" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 0);
    defer g.destroy();
    const first = g.seed;
    try std.testing.expect(first != 0);
    try std.testing.expect(!g.seed_locked);
    g.restart();
    try std.testing.expect(g.seed != first);
    try std.testing.expectEqual(sim_mod.Class.warrior, g.class);
    try std.testing.expectEqual(g.seed, g.sim.seed);
}

test "run game: menu toggles difficulty and restarts the preview" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();

    g.openMenu();
    try std.testing.expectEqual(sim_mod.Difficulty.normal, g.difficulty);
    g.update(.{ .difficulty = true }, 1.0 / 60.0);
    try std.testing.expectEqual(sim_mod.Difficulty.hard, g.difficulty);
    try std.testing.expectEqual(@as(u8, 1), g.hud_state.difficulty);
    try std.testing.expectEqual(sim_mod.Difficulty.hard, g.sim.difficulty);
    g.update(.{ .difficulty = true }, 1.0 / 60.0);
    try std.testing.expectEqual(sim_mod.Difficulty.easy, g.difficulty);
    try std.testing.expectEqual(@as(u8, 2), g.hud_state.difficulty);
}

test "run game: P quaffs a potion outside the inventory" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();

    var potion: ?u16 = null;
    for (g.content.items, 0..) |def, i| {
        if (def.use()) |use| {
            if (use.heal > 0) {
                potion = @intCast(i);
                break;
            }
        }
    }
    try std.testing.expect(g.inventory.pickup(potion orelse return error.MissingPotion));
    g.sim.hero.vitals.val = 10;
    g.fillHudState();
    try std.testing.expect(g.hud_state.potions > 0);
    const before = g.inventory.count();

    g.update(.{ .use_item = true }, 1.0 / 60.0);
    try std.testing.expect(g.sim.hero.vitals.val > 10);
    try std.testing.expectEqual(before - 1, g.inventory.count());
}

test "run game: inventory comparison marks equippable items" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    g.debugGrantLoot(8);
    g.panel = .inventory;
    g.fillHudState();
    var any = false;
    var i: usize = 0;
    while (i < g.hud_state.item_count) : (i += 1) {
        if (g.hud_state.item_delta_valid[i]) any = true;
    }
    try std.testing.expect(any);
}

test "run game: inventory P consumes a resource potion" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .mage, 12345);
    defer g.destroy();

    var tonic: ?u16 = null;
    for (g.content.items, 0..) |def, i| {
        if (def.use()) |use| {
            if (use.resource > 0 and use.heal == 0) {
                tonic = @intCast(i);
                break;
            }
        }
    }
    const id = tonic orelse return error.MissingManaTonic;
    try std.testing.expect(g.inventory.pickup(id));
    g.sim.hero.resource.val = 5;
    g.panel = .inventory;
    const before = g.inventory.count();

    g.update(.{ .use_item = true }, 1.0 / 60.0);
    try std.testing.expect(g.sim.hero.resource.val > 5);
    try std.testing.expectEqual(before - 1, g.inventory.count());
}

test "run game: death updates lifetime records once" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();

    g.sim.state = .dead;
    g.fillHudState();
    try std.testing.expectEqual(@as(u32, 1), g.records.deaths);
    try std.testing.expect(g.records_dirty);
    g.fillHudState();
    try std.testing.expectEqual(@as(u32, 1), g.records.deaths);
}

test "run game: shop panel buys a heal once" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();

    g.sim.shop = g.sim.hero.pos;
    g.sim.shop_active = true;
    g.debugShop();
    g.sim.gold = 100;
    g.sim.hero.vitals.val = 20;
    try std.testing.expect(g.hud_state.shop_open);
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(g.sim.hero.vitals.val > 20);
    try std.testing.expect(!g.shop_open);
    try std.testing.expectEqual(@as(u32, 75), g.sim.gold);
}

test "run game: shop loot purchase adds an item and spends gold" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();

    g.sim.shop = g.sim.hero.pos;
    g.sim.shop_active = true;
    g.debugShop();
    g.sim.gold = 100;
    const before = g.inventory.count();
    g.update(.{ .stat = 4 }, 1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 20), g.sim.gold);
    try std.testing.expect(!g.shop_open);
    try std.testing.expect(g.sim.shop_used);
    // The drop may auto-equip, so total items can stay flat; gold and shop prove the purchase.
    _ = before;
}

test "run game: shrine panel consumes a choice once" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .mage, 12345);
    defer g.destroy();

    g.sim.shrine = g.sim.hero.pos;
    g.sim.shrine_active = true;
    g.debugShrine();
    try std.testing.expect(g.hud_state.shrine_open);
    const magic = g.sim.hero.sheet.stats.magic.val;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(magic + 2, g.sim.hero.sheet.stats.magic.val, 0.001);
    try std.testing.expect(!g.shrine_open);
    try std.testing.expect(g.sim.shrine_used);
}

test "run game: inventory P consumes a healing item" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();

    var potion: ?u16 = null;
    for (g.content.items, 0..) |def, i| {
        if (def.use()) |use| {
            if (use.heal > 0) {
                potion = @intCast(i);
                break;
            }
        }
    }
    const id = potion orelse return error.MissingPotion;
    try std.testing.expect(g.inventory.pickup(id));
    g.sim.hero.vitals.val = 10;
    g.panel = .inventory;
    const before = g.inventory.count();

    g.update(.{ .use_item = true }, 1.0 / 60.0);
    try std.testing.expect(g.sim.hero.vitals.val > 10);
    try std.testing.expectEqual(before - 1, g.inventory.count());
}

test "run game: class menu selects and keeps the class on restart" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
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

fn setGameEnemy(g: *RunGame, index: usize, pos: sim_mod.GridPos, name: []const u8, hp: f32) void {
    g.sim.enemies[index] = sim_mod.enemyFromParts(.{
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
    });
}

fn placeGameEnemyAt(g: *RunGame, p: sim_mod.GridPos, name: []const u8) bool {
    if (g.sim.isBlocked(p.x, p.y) or g.sim.enemyAt(p.x, p.y) != null) return false;
    setGameEnemy(g, g.sim.enemy_count, p, name, 999);
    g.sim.enemy_count += 1;
    return true;
}

fn addGameEnemy(g: *RunGame, dx: i32, dy: i32, name: []const u8) void {
    const p = g.sim.hero.pos;
    setGameEnemy(g, g.sim.enemy_count, .{ .x = p.x + dx, .y = p.y + dy }, name, 999);
    g.sim.enemy_count += 1;
}

test "run game: aiming waits for confirmation and spends one turn" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    addGameEnemy(g, 1, 0, "骷髅兵");

    const turn = g.sim.turn;
    const res = g.sim.hero.resource.val;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource.val);
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
    try std.testing.expect(g.sim.hero.resource.val < res);
    try std.testing.expect(g.sim.hero.talents.cooldowns[0] > 0);
    try std.testing.expect(!g.hud_state.aim.active);

    // Re-aiming during cooldown is refused up front; no aim, turn or resource.
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    const turn_after = g.sim.turn;
    const res_after = g.sim.hero.resource.val;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expectEqual(turn_after, g.sim.turn);
    try std.testing.expectEqual(res_after, g.sim.hero.resource.val);
    try std.testing.expect(!g.isAiming());
}

test "run game: space confirms, switch key changes aim, self talent releases" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    addGameEnemy(g, 1, 0, "骷髅兵");

    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    const turn = g.sim.turn;
    g.update(.{ .talent = 1 }, 1.0 / 60.0); // switch to 冲锋, no cast
    try std.testing.expect(g.isAiming());
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqualStrings("冲锋", g.hud_state.aim.talent);
    try std.testing.expectEqual(@as(u16, 0), g.sim.hero.talents.cooldowns[1]);

    g.update(.{ .confirm = true }, 1.0 / 60.0); // SPACE confirms
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn + 1, g.sim.turn);
    try std.testing.expect(g.sim.hero.talents.cooldowns[1] > 0);
    try std.testing.expectEqual(@as(u16, 0), g.sim.hero.talents.cooldowns[0]);

    // 战吼 is not targeted: pressed while aiming it releases immediately.
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(g.isAiming());
    const turn2 = g.sim.turn;
    g.update(.{ .talent = 2 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn2 + 1, g.sim.turn);
    try std.testing.expect(g.sim.hero.talents.cooldowns[2] > 0);
}

test "run game: tab cycles the aim target without spending a turn" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
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

test "run game: cancel and invalid confirms never spend a turn or resource" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();

    // No living enemy at all.
    g.sim.enemy_count = 0;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(g.isAiming());
    try std.testing.expect(!g.hud_state.aim.valid);
    try std.testing.expectEqualStrings("无效目标", g.hud_state.aim.reason);
    const t0 = g.sim.turn;
    const r0 = g.sim.hero.resource.val;
    g.update(.{ .confirm = true }, 1.0 / 60.0);
    try std.testing.expectEqual(t0, g.sim.turn);
    try std.testing.expectEqual(r0, g.sim.hero.resource.val);
    try std.testing.expect(g.isAiming());

    // Esc path: consume the aim, spend nothing, stay in the run.
    try std.testing.expect(g.cancelAim());
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(t0, g.sim.turn);
    try std.testing.expectEqual(r0, g.sim.hero.resource.val);
    try std.testing.expect(!g.cancelAim());
    try std.testing.expectEqual(sim_mod.State.playing, g.sim.state);
    g.update(.{}, 1.0 / 60.0);
    try std.testing.expect(!g.hud_state.aim.active);

    // Out of range (5 cells for 重击); pick a free ray so map holes do not
    // turn this into a no-target test.
    g.restart();
    g.sim.enemy_count = 0;
    const dirs = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
    var placed = false;
    for (dirs) |d| {
        const p = sim_mod.GridPos{ .x = g.sim.hero.pos.x + d[0] * 5, .y = g.sim.hero.pos.y + d[1] * 5 };
        if (g.sim.isBlocked(p.x, p.y)) continue;
        if (placeGameEnemyAt(g, p, "骷髅兵")) {
            placed = true;
            break;
        }
    }
    if (!placed) return error.SkipZigTest;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.hud_state.aim.valid);
    try std.testing.expectEqualStrings("超出范围", g.hud_state.aim.reason);
    var turn = g.sim.turn;
    var res = g.sim.hero.resource.val;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource.val);
    try std.testing.expect(g.isAiming());

    // Wall between hero and target: LOS blocks confirmation.
    g.restart();
    g.sim.enemy_count = 0;
    placed = false;
    for (dirs) |d| {
        const mid = sim_mod.GridPos{ .x = g.sim.hero.pos.x + d[0], .y = g.sim.hero.pos.y + d[1] };
        const p = sim_mod.GridPos{ .x = g.sim.hero.pos.x + d[0] * 2, .y = g.sim.hero.pos.y + d[1] * 2 };
        if (g.sim.isBlocked(mid.x, mid.y) or g.sim.isBlocked(p.x, p.y)) continue;
        if (placeGameEnemyAt(g, p, "骷髅兵")) {
            g.sim.blocked[@as(usize, @intCast(mid.y)) * sim_mod.grid_w + @as(usize, @intCast(mid.x))] = true;
            placed = true;
            break;
        }
    }
    if (!placed) return error.SkipZigTest;
    g.update(.{ .talent = 1 }, 1.0 / 60.0);
    try std.testing.expect(!g.hud_state.aim.valid);
    try std.testing.expectEqualStrings("视线受阻", g.hud_state.aim.reason);
    turn = g.sim.turn;
    res = g.sim.hero.resource.val;
    g.update(.{ .talent = 1 }, 1.0 / 60.0);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource.val);

    // Insufficient resource: refuse to enter aim at all.
    g.restart();
    g.sim.enemy_count = 0;
    for (dirs) |d| {
        const p = sim_mod.GridPos{ .x = g.sim.hero.pos.x + d[0], .y = g.sim.hero.pos.y + d[1] };
        if (g.sim.isBlocked(p.x, p.y)) continue;
        if (placeGameEnemyAt(g, p, "骷髅兵")) break;
    }
    g.sim.hero.resource.val = 0;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    turn = g.sim.turn;
    res = g.sim.hero.resource.val;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(res, g.sim.hero.resource.val);
}

test "run game: untargeted talents still release immediately without aim" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    addGameEnemy(g, 1, 0, "骷髅兵");

    const turn = g.sim.turn;
    g.update(.{ .talent = 2 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn + 1, g.sim.turn);
    try std.testing.expect(g.sim.hero.talents.cooldowns[2] > 0);
    try std.testing.expect(g.sim.hero.status.buff_turns > 0);
}

test "run game: save/load round-trips the sim and gear" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const sim_path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "run.json" });
    defer alloc.free(sim_path);
    const gear_path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "gear.json" });
    defer alloc.free(gear_path);

    const g = try RunGame.create(alloc, 320, 180, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    _ = g.sim.wait();
    g.sim.hero.vitals.val = 77;
    if (g.content.items.len == 0) return error.SkipZigTest;
    if (!g.inventory.pickup(0)) return error.SkipZigTest;
    const turn = g.sim.turn;
    const rng_state = g.loot_rng.s;
    g.saveRun(io, sim_path, gear_path);

    g.sim.hero.vitals.val = 1;
    g.inventory = items_mod.Inventory.init();
    g.loadRun(io, sim_path, gear_path);
    try std.testing.expectEqual(@as(f32, 77), g.sim.hero.vitals.val);
    try std.testing.expectEqual(turn, g.sim.turn);
    try std.testing.expectEqual(@as(usize, 1), g.inventory.len);
    try std.testing.expect(std.meta.eql(rng_state, g.loot_rng.s));
}

test "run game: v1 save reports a Chinese incompatibility reason" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const sim_path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "run.json" });
    defer alloc.free(sim_path);
    const gear_path = try std.fs.path.join(alloc, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "gear.json" });
    defer alloc.free(gear_path);

    const g = try RunGame.create(alloc, 320, 180, .warrior, 12345);
    defer g.destroy();
    const bytes = try save_mod.saveAlloc(alloc, &g.sim);
    defer alloc.free(bytes);
    const old = try std.mem.replaceOwned(u8, alloc, bytes, "\"version\":2", "\"version\":1");
    defer alloc.free(old);
    try tmp.dir.writeFile(io, .{ .sub_path = "run.json", .data = old });

    g.loadRun(io, sim_path, gear_path);
    const last = g.sim.logAt(g.sim.log_total - 1);
    try std.testing.expect(std.mem.indexOf(u8, last, "旧档不兼容") != null);
    try std.testing.expect(std.mem.indexOf(u8, last, "UnsupportedVersion") == null);
}

test "run game: H toggles help without spending a turn" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    const turn = g.sim.turn;
    g.update(.{ .help = true }, 1.0 / 60.0);
    try std.testing.expect(g.show_help);
    try std.testing.expectEqual(turn, g.sim.turn);
    g.update(.{ .help = true }, 1.0 / 60.0);
    try std.testing.expect(!g.show_help);
    try std.testing.expectEqual(turn, g.sim.turn);
}

test "run game: aim refuses cooldown/resource-blocked talents" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
    defer g.destroy();
    g.sim.hero.talents.cooldowns[0] = 2;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    g.sim.hero.talents.cooldowns[0] = 0;
    g.sim.hero.resource.val = 0;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
}

test "run game: held repeat is throttled to one step per 0.3s" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 320, 180, .warrior, 12345);
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

test "run game: autosave history rotates and loads" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    const auto1 = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "auto1.save" });
    defer gpa.free(auto1);
    const auto2 = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "auto2.save" });
    defer gpa.free(auto2);
    const auto3 = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "auto3.save" });
    defer gpa.free(auto3);
    const auto_tmp = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "auto-new.save" });
    defer gpa.free(auto_tmp);
    g.auto_files = .{ auto1, auto2, auto3 };
    g.auto_tmp_file = auto_tmp;
    const hp0 = g.sim.hero.vitals.val;
    g.autosave_pending = true;
    g.flushAutosave(io);
    g.sim.hero.vitals.val = hp0 - 10;
    g.autosave_pending = true;
    g.flushAutosave(io);
    g.sim.hero.vitals.val = hp0 - 20;
    g.autosave_pending = true;
    g.flushAutosave(io);
    g.sim.hero.vitals.val = 1;
    g.loadAutoSlot(io, 0);
    try std.testing.expectApproxEqAbs(hp0 - 20, g.sim.hero.vitals.val, 0.01);
    g.loadAutoSlot(io, 2);
    try std.testing.expectApproxEqAbs(hp0, g.sim.hero.vitals.val, 0.01);
    g.openAutoMenu(io);
    try std.testing.expect(!std.mem.eql(u8, g.slot_labels[0], "空"));
    try std.testing.expect(!std.mem.eql(u8, g.slot_labels[2], "空"));
}

test "run game: slots fall back to legacy run+gear pair" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    const run_path = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "legacy-run.json" });
    defer gpa.free(run_path);
    const gear_path = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "legacy-gear.json" });
    defer gpa.free(gear_path);
    const missing = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "missing.save" });
    defer gpa.free(missing);
    g.slot_runs[0] = run_path;
    g.slot_gears[0] = gear_path;
    g.slot_files[0] = missing;
    const hp = g.sim.hero.vitals.val;
    g.saveRun(io, run_path, gear_path);
    g.sim.hero.vitals.val = 1;
    g.loadSlot(io, 0);
    try std.testing.expectApproxEqAbs(hp, g.sim.hero.vitals.val, 0.01);
}

test "run game: slots save metadata and load" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    const run_path = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "slot-run.json" });
    defer gpa.free(run_path);
    const gear_path = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "slot-gear.json" });
    defer gpa.free(gear_path);
    const bundle_path = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", tmp.sub_path[0..], "slot.save" });
    defer gpa.free(bundle_path);
    g.slot_runs[0] = run_path;
    g.slot_gears[0] = gear_path;
    g.slot_files[0] = bundle_path;
    const hp = g.sim.hero.vitals.val;
    g.saveSlot(io, 0);
    try std.testing.expect(!std.mem.eql(u8, g.slot_labels[0], "空"));
    g.sim.hero.vitals.val = 1;
    g.loadSlot(io, 0);
    try std.testing.expectApproxEqAbs(hp, g.sim.hero.vitals.val, 0.01);
}

test "run game: initiative shows the player and fastest enemy" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    g.fillHudState();
    try std.testing.expectEqualStrings("玩家", g.hud_state.initiative[0]);
    var alive: usize = 0;
    var i: usize = 0;
    while (i < g.sim.enemy_count) : (i += 1) {
        if (g.sim.enemies[i].life.alive) alive += 1;
    }
    if (alive >= 2) {
        try std.testing.expectEqual(@as(u8, 3), g.hud_state.initiative_count);
        try std.testing.expect(g.hud_state.initiative[1].len > 0);
        try std.testing.expect(g.hud_state.initiative[2].len > 0);
    } else if (alive == 1) {
        try std.testing.expectEqual(@as(u8, 2), g.hud_state.initiative_count);
    } else {
        try std.testing.expectEqual(@as(u8, 1), g.hud_state.initiative_count);
    }
}

test "run game: character panel spends a pending attribute point" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    g.panel = .character;
    g.sim.hero.progression.pending_points = 1;
    const str = g.sim.hero.sheet.stats.strength.val;
    g.update(.{ .stat = 0 }, 1.0 / 60.0);
    try std.testing.expectEqual(str + 1, g.sim.hero.sheet.stats.strength.val);
    try std.testing.expectEqual(@as(u8, 0), g.sim.hero.progression.pending_points);
}

test "run game: presentation locks input during enemy phase" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    g.started = true;
    g.presentation = true;
    g.update(.{ .wait = true }, 1.0 / 60.0);
    try std.testing.expect(g.sim.enemy_phase_pending);
    try std.testing.expect(g.hud_state.enemy_phase);
    const turn = g.sim.turn;
    g.update(.{ .step_x = 1 }, 1.0 / 60.0);
    try std.testing.expectEqual(turn, g.sim.turn);
    var i: usize = 0;
    while (i < 30) : (i += 1) g.update(.{}, 1.0 / 60.0);
    try std.testing.expect(!g.sim.enemy_phase_pending);
    try std.testing.expect(!g.hud_state.enemy_phase);
}

test "run game: mouse click confirms an aimed enemy" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .warrior, 12345);
    defer g.destroy();
    g.sim.enemy_count = 0;
    addGameEnemy(g, 1, 0, "骷髅兵");
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(g.isAiming());
    const e = g.sim.enemies[0];
    const center = @as(f32, @floatFromInt(sim_mod.grid_w - 1)) * 0.5;
    const world = math.Vec3.init(@as(f32, @floatFromInt(e.pos.x)) - center, 0, @as(f32, @floatFromInt(e.pos.y)) - center);
    const p = g.camera.project(world, 640, 360) orelse return error.SkipZigTest;
    const turn = g.sim.turn;
    g.update(.{ .mouse_x = p.x, .mouse_y = p.y, .click = true }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn + 1, g.sim.turn);
}

test "run game: mouse click casts fireball on a ground cell" {
    const gpa = std.testing.allocator;
    const g = try RunGame.create(gpa, 640, 360, .mage, 12345);
    defer g.destroy();
    g.sim.enemy_count = 0;
    var target: ?sim_mod.GridPos = null;
    var y: i32 = 0;
    while (y < sim_mod.grid_h and target == null) : (y += 1) {
        var x: i32 = 0;
        while (x < sim_mod.grid_w) : (x += 1) {
            const cell = sim_mod.GridPos{ .x = x, .y = y };
            const d = @abs(x - g.sim.hero.pos.x) + @abs(y - g.sim.hero.pos.y);
            if (d == 0 or d > 5 or g.sim.isBlocked(x, y)) continue;
            if (!g.sim.map.lineOfSightTo(.{ .x = g.sim.hero.pos.x, .y = g.sim.hero.pos.y }, .{ .x = x, .y = y }, null)) continue;
            target = cell;
            break;
        }
    }
    const cell = target orelse return error.SkipZigTest;
    g.update(.{ .talent = 0 }, 1.0 / 60.0);
    try std.testing.expect(g.isAiming());
    const center = @as(f32, @floatFromInt(sim_mod.grid_w - 1)) * 0.5;
    const world = math.Vec3.init(@as(f32, @floatFromInt(cell.x)) - center, 0, @as(f32, @floatFromInt(cell.y)) - center);
    const p = g.camera.project(world, 640, 360) orelse return error.SkipZigTest;
    const turn = g.sim.turn;
    g.update(.{ .mouse_x = p.x, .mouse_y = p.y, .click = true }, 1.0 / 60.0);
    try std.testing.expect(!g.isAiming());
    try std.testing.expectEqual(turn + 1, g.sim.turn);
    try std.testing.expect(g.sim.hero.talents.cooldowns[0] > 0);
}
