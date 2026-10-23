//! Pure turn-based simulation: 31x31 grid, one hero, enemies,
//! floors, talents, XP and a deterministic RNG. No SDL, renderer or ECS.
const std = @import("std");
const dungeon_mod = @import("dungeon.zig");
const attributes = @import("attributes.zig");
const combat = @import("combat.zig");
const intent_mod = @import("intent.zig");

pub const grid_w = dungeon_mod.size;
pub const grid_h = dungeon_mod.size;
pub const max_enemies = 12;

pub const Class = attributes.Class;
pub const class_count = attributes.class_count;
pub const classFromIndex = attributes.classFromIndex;

pub const class_names = attributes.class_names;
pub const resource_names = attributes.resource_names;
/// One-line positioning hints for the class-selection cards.
pub const class_roles = attributes.class_roles;

/// One-line Chinese effect text for every class talent (hotbar hint strip,
/// class cards and the character panel). Keep each line short enough for the
/// 92 px columns used by the HUD.
pub const class_talent_descs = [class_count][3][]const u8{
    .{ "近战2.2倍伤害", "4格内1.5倍", "3回合攻击+30%" },
    .{ "5格2.5倍+范围", "1.8倍+减速", "传送3-5格" },
    .{ "2.0倍+减速", "1.2倍+停2回合", "回到上一格" },
};

/// Deterministic reseed used after the player picks a class: the menu preview
/// seed is consumed, the run gets a fresh (but reproducible) dungeon.
pub fn nextSeed(seed: u64) u64 {
    var z = seed +% 0x9e3779b97f4a7c15;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

pub fn classHpMax(class: Class) u16 {
    return @intFromFloat(attributes.recompute(attributes.baseStats(class), &.{}, class).derived.hp_max);
}

pub fn classResourceMax(class: Class) u16 {
    return @intFromFloat(attributes.recompute(attributes.baseStats(class), &.{}, class).derived.resource_max);
}

pub fn talentNameFor(class: Class, i: usize) []const u8 {
    return switch (class) {
        .warrior => switch (i) {
            0 => "重击",
            1 => "冲锋",
            else => "战吼",
        },
        .mage => switch (i) {
            0 => "火球",
            1 => "冰锥",
            else => "闪现",
        },
        .chronomancer => switch (i) {
            0 => "时光箭",
            1 => "时间停滞",
            else => "回溯",
        },
    };
}

pub fn talentDescFor(class: Class, i: usize) []const u8 {
    return class_talent_descs[@backingInt(class)][@min(i, 2)];
}

pub const GridPos = struct { x: i32, y: i32 };

pub const Stats = struct {
    strength: f32 = 0,
    agility: f32 = 0,
    constitution: f32 = 0,
    perception: f32 = 0,
    magic: f32 = 0,
    will: f32 = 0,

    pub fn fromArray(v: [6]f32) Stats {
        return .{
            .strength = v[0],
            .agility = v[1],
            .constitution = v[2],
            .perception = v[3],
            .magic = v[4],
            .will = v[5],
        };
    }
};

fn statsFromAttributes(st: attributes.Stats) Stats {
    return Stats.fromArray(.{ st.get(.strength), st.get(.agility), st.get(.constitution), st.get(.perception), st.get(.magic), st.get(.will) });
}

pub const State = enum(u8) { playing, dead, victory };

pub const Hero = struct {
    class: Class = .warrior,
    pos: GridPos = .{ .x = 6, .y = 11 },
    last_pos: GridPos = .{ .x = 6, .y = 11 },
    stats: Stats = .{},
    hp: f32 = 1,
    hp_max: f32 = 1,
    resource: f32 = 0,
    resource_max: f32 = 1,
    attack: f32 = 10,
    armor: f32 = 0,
    crit: f32 = 0.05,
    speed: u16 = 100,
    res_per_turn: f32 = 8,
    level: u16 = 1,
    xp: u32 = 0,
    pending_points: u8 = 0,
    cooldowns: [3]u16 = .{ 0, 0, 0 },
    buff_turns: u16 = 0,
    buff_pct: f32 = 0,
    eff_stats: [6]f32 = .{ 0, 0, 0, 0, 0, 0 },
};

pub const Enemy = struct {
    kind: u8 = 0,
    name: []const u8 = "骷髅兵",
    pos: GridPos = .{ .x = 0, .y = 0 },
    hp: f32 = 1,
    hp_max: f32 = 1,
    attack: f32 = 5,
    armor: f32 = 0,
    speed: u16 = 100,
    range: u16 = 1,
    xp: u32 = 20,
    stun_turns: u16 = 0,
    slow_turns: u16 = 0,
    alive: bool = true,
};

pub const EnemyDef = struct {
    name: []const u8,
    hp: f32,
    attack: f32,
    armor: f32,
    speed: u16,
    range: u16,
    xp: u32,
};

const enemy_defs = [_]EnemyDef{
    .{ .name = "骷髅兵", .hp = 70, .attack = 8, .armor = 4, .speed = 100, .range = 1, .xp = 20 },
    .{ .name = "幽魂", .hp = 55, .attack = 7, .armor = 1, .speed = 110, .range = 3, .xp = 25 },
    .{ .name = "石魔像", .hp = 150, .attack = 12, .armor = 12, .speed = 70, .range = 1, .xp = 40 },
    .{ .name = "精英骷髅", .hp = 100, .attack = 11, .armor = 7, .speed = 110, .range = 1, .xp = 50 },
    .{ .name = "精英幽魂", .hp = 85, .attack = 10, .armor = 2, .speed = 150, .range = 4, .xp = 50 },
    .{ .name = "深渊守卫", .hp = 420, .attack = 16, .armor = 15, .speed = 90, .range = 1, .xp = 200 },
};

pub const LogLine = struct { text: [64]u8 = undefined, len: usize = 0 };

pub const Sim = struct {
    seed: u64,
    rng: std.Random.DefaultPrng,
    class: Class,
    hero: Hero,
    enemies: [max_enemies]Enemy = undefined,
    enemy_count: usize = 0,
    blocked: [grid_w * grid_h]bool = @splat(false),
    stairs: GridPos = .{ .x = 10, .y = 2 },
    chests: [4]GridPos = .{ .{ .x = 2, .y = 2 }, .{ .x = 10, .y = 10 }, .{ .x = 2, .y = 10 }, .{ .x = 10, .y = 2 } },
    chest_alive: [4]bool = .{ false, false, false, false },
    chest_count: usize = 0,
    traps: [4]GridPos = .{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 } },
    trap_alive: [4]bool = .{ false, false, false, false },
    trap_count: usize = 0,
    map: dungeon_mod.Dungeon = .{},
    floor: u8 = 1,
    floors: u8 = 3,
    turn: u32 = 1,
    state: State = .playing,
    /// Bots set this for the duration of one action so level-ups keep the
    /// historical automatic main-stat growth. Human play leaves it false and
    /// allocates via Sim.spendPoint.
    auto_allocate: bool = false,
    /// Interactive presentation defers enemy actions to a short animation
    /// phase; bots leave this false for immediate resolution.
    defer_enemies: bool = false,
    enemy_phase_pending: bool = false,
    kills: u32 = 0,
    chest_loot_events: u32 = 0,
    kill_loot_events: u32 = 0,
    aoe_target: GridPos = .{ .x = 0, .y = 0 },
    aoe_armed: bool = false,
    log_buf: [6]LogLine = .{ .{}, .{}, .{}, .{}, .{}, .{} },
    log_head: usize = 0,
    log_total: usize = 0,

    pub fn init(seed: u64, class: Class) Sim {
        var s = Sim{
            .seed = seed,
            .rng = std.Random.DefaultPrng.init(seed),
            .class = class,
            .hero = Hero{ .class = class },
        };
        s.reset(seed, class);
        return s;
    }

    pub fn reset(self: *Sim, seed: u64, class: Class) void {
        self.seed = seed;
        self.rng = std.Random.DefaultPrng.init(seed);
        self.class = class;
        self.hero = Hero{ .class = class, .stats = statsFromAttributes(attributes.baseStats(class)) };
        self.floor = 1;
        self.turn = 1;
        self.kills = 0;
        self.chest_loot_events = 0;
        self.kill_loot_events = 0;
        self.aoe_armed = false;
        self.state = .playing;
        self.enemy_phase_pending = false;
        self.defer_enemies = false;
        self.log_head = 0;
        self.log_total = 0;
        self.recomputeHero();
        self.hero.hp = self.hero.hp_max;
        self.hero.resource = self.hero.resource_max;
        self.generateFloor();
        self.pushLog("进入第 1 层", .{});
    }

    /// Spend one pending level-up point. The caller must re-apply equipment
    /// modifiers (RunGame.rebuildMods) after this base-stat change.
    pub fn spendPoint(self: *Sim, stat: usize) bool {
        if (self.hero.pending_points == 0 or stat >= 6) return false;
        switch (stat) {
            0 => self.hero.stats.strength += 1,
            1 => self.hero.stats.agility += 1,
            2 => self.hero.stats.constitution += 1,
            3 => self.hero.stats.perception += 1,
            4 => self.hero.stats.magic += 1,
            else => self.hero.stats.will += 1,
        }
        self.hero.pending_points -= 1;
        self.recomputeHero();
        return true;
    }

    pub fn mainStatIndex(self: *const Sim) usize {
        return @backingInt(attributes.profile(self.class).main_stat);
    }

    pub fn recomputeHero(self: *Sim) void {
        self.applyModifiers(&.{});
    }

    pub fn applyModifiers(self: *Sim, mods: []const attributes.Modifier) void {
        const base = attributes.Stats.fromArray(.{
            self.hero.stats.strength,
            self.hero.stats.agility,
            self.hero.stats.constitution,
            self.hero.stats.perception,
            self.hero.stats.magic,
            self.hero.stats.will,
        });
        const sheet = attributes.recompute(base, mods, self.class);
        self.hero.eff_stats = sheet.stats;
        self.hero.hp_max = sheet.derived.hp_max;
        self.hero.resource_max = sheet.derived.resource_max;
        self.hero.attack = sheet.derived.attack;
        self.hero.armor = sheet.derived.armor;
        self.hero.crit = sheet.derived.crit;
        self.hero.speed = @intFromFloat(sheet.derived.speed);
        self.hero.res_per_turn = sheet.derived.resource_per_turn;
        self.hero.hp = @min(self.hero.hp, self.hero.hp_max);
        self.hero.resource = @min(self.hero.resource, self.hero.resource_max);
    }

    pub fn pushLog(self: *Sim, comptime f: []const u8, args: anytype) void {
        const slot = self.log_head;
        const text = std.fmt.bufPrint(&self.log_buf[slot].text, f, args) catch return;
        self.log_buf[slot].len = text.len;
        self.log_head = (slot + 1) % self.log_buf.len;
        if (self.log_total < self.log_buf.len) self.log_total += 1;
    }

    pub fn logAt(self: *const Sim, index: usize) []const u8 {
        const start = (self.log_head + self.log_buf.len - self.log_total) % self.log_buf.len;
        const slot = (start + index) % self.log_buf.len;
        return self.log_buf[slot].text[0..self.log_buf[slot].len];
    }

    pub fn enemyAt(self: *const Sim, x: i32, y: i32) ?usize {
        var i: usize = 0;
        while (i < self.enemy_count) : (i += 1) {
            const e = self.enemies[i];
            if (e.alive and e.pos.x == x and e.pos.y == y) return i;
        }
        return null;
    }

    /// Read-only preview of what `enemies[index]` will attempt on the next
    /// enemy phase. Does not mutate the sim and does not roll damage.
    pub fn intentFor(self: *const Sim, index: usize) ?intent_mod.EnemyIntent {
        if (index >= self.enemy_count) return null;
        const e = self.enemies[index];
        if (!e.alive) return null;
        var intent = intent_mod.preview(
            .{
                .width = grid_w,
                .height = grid_h,
                .blocked = self.blocked[0..],
            },
            .{
                .kind = e.kind,
                .pos = .{ .x = e.pos.x, .y = e.pos.y },
                .range = e.range,
                .attack = e.attack,
                .stun_turns = e.stun_turns,
                .slow_turns = e.slow_turns,
                .alive = e.alive,
            },
            .{ .x = self.hero.pos.x, .y = self.hero.pos.y },
            self.turn +| 1,
        );
        if (intent.kind == .aoe and self.aoe_armed) {
            intent.target = .{ .x = self.aoe_target.x, .y = self.aoe_target.y };
        }
        if (intent.damage_preview > 0) {
            intent.damage_preview = combat.preview(.{ .raw = intent.damage_preview }, .{ .armor = self.hero.armor });
        }
        return intent;
    }

    /// Fill `out` with one intent per living enemy, in enemy-array order.
    /// Returns the number written. Read-only.
    pub fn previewIntents(self: *const Sim, out: *[max_enemies]intent_mod.EnemyIntent) usize {
        var n: usize = 0;
        var i: usize = 0;
        while (i < self.enemy_count) : (i += 1) {
            if (!self.enemies[i].alive) continue;
            out[n] = self.intentFor(i).?;
            n += 1;
        }
        return n;
    }

    pub fn isBlocked(self: *const Sim, x: i32, y: i32) bool {
        if (x < 0 or y < 0 or x >= grid_w or y >= grid_h) return true;
        return self.blocked[@as(usize, @intCast(y)) * grid_w + @as(usize, @intCast(x))];
    }

    fn isFree(self: *const Sim, x: i32, y: i32) bool {
        return !self.isBlocked(x, y) and self.enemyAt(x, y) == null;
    }

    fn dist(a: GridPos, b: GridPos) i32 {
        return @intCast(@abs(a.x - b.x) + @abs(a.y - b.y));
    }

    pub fn generateFloor(self: *Sim) void {
        self.enemy_count = 0;
        self.aoe_armed = false;
        self.map = dungeon_mod.Dungeon.generate(self.seed, self.floor);
        self.map.validate() catch {};

        var y: i32 = 0;
        while (y < grid_h) : (y += 1) {
            var x: i32 = 0;
            while (x < grid_w) : (x += 1) {
                const p = dungeon_mod.GridPos{ .x = x, .y = y };
                self.blocked[@as(usize, @intCast(y)) * grid_w + @as(usize, @intCast(x))] = !self.map.isWalkable(p);
            }
        }

        self.hero.pos = .{ .x = self.map.entrance.x, .y = self.map.entrance.y };
        self.hero.last_pos = self.hero.pos;
        self.stairs = .{ .x = self.map.stairs.x, .y = self.map.stairs.y };

        self.chest_alive = .{ false, false, false, false };
        self.chest_count = 0;
        const cs = self.map.chestSlice();
        for (cs, 0..) |p, i| {
            if (i >= self.chests.len) break;
            self.chests[i] = .{ .x = p.x, .y = p.y };
            self.chest_alive[i] = true;
            self.chest_count += 1;
        }
        self.trap_alive = .{ false, false, false, false };
        self.trap_count = 0;
        const ts = self.map.trapSlice();
        for (ts, 0..) |p, i| {
            if (i >= self.traps.len) break;
            self.traps[i] = .{ .x = p.x, .y = p.y };
            self.trap_alive[i] = true;
            self.trap_count += 1;
        }

        const kinds: []const u8 = switch (self.floor) {
            1 => &.{ 0, 1, 0, 0, 1, 0, 0, 1 },
            2 => &.{ 3, 0, 1, 2, 4, 1, 0, 3 },
            else => &.{ 5, 3, 4, 0, 1, 2, 3, 4 },
        };
        const max_spawns: usize = dungeon_mod.spawnsForFloor(self.floor);
        for (self.map.spawnSlice(), 0..) |p, i| {
            if (i >= max_spawns) break;
            self.spawnEnemyAt(kinds[i % kinds.len], .{ .x = p.x, .y = p.y });
        }
        self.pushLog("第 {d} 层：{d} 个敌人", .{ self.floor, self.enemy_count });
    }

    fn spawnEnemyAt(self: *Sim, kind: u8, pos: GridPos) void {
        if (self.enemy_count >= max_enemies) return;
        if (self.isBlocked(pos.x, pos.y)) return;
        if (self.enemyAt(pos.x, pos.y) != null) return;
        if (pos.x == self.hero.pos.x and pos.y == self.hero.pos.y) return;
        const def = enemy_defs[@min(kind, enemy_defs.len - 1)];
        const idx = self.enemy_count;
        self.enemies[idx] = .{
            .kind = kind,
            .name = def.name,
            .pos = pos,
            .hp = def.hp,
            .hp_max = def.hp,
            .attack = def.attack,
            .armor = def.armor,
            .speed = def.speed,
            .range = def.range,
            .xp = def.xp,
        };
        self.enemy_count += 1;
    }

    pub fn canMove(self: *const Sim, dx: i32, dy: i32) bool {
        const nx = self.hero.pos.x + dx;
        const ny = self.hero.pos.y + dy;
        if (self.isBlocked(nx, ny)) return false;
        return true;
    }

    pub fn hasLivingBoss(self: *const Sim) bool {
        for (self.enemies[0..self.enemy_count]) |e| {
            if (e.alive and e.kind == intent_mod.boss_kind) return true;
        }
        return false;
    }

    pub fn move(self: *Sim, dx: i32, dy: i32) bool {
        if (self.state != .playing) return false;
        if (dx == 0 and dy == 0) return false;
        const nx = self.hero.pos.x + dx;
        const ny = self.hero.pos.y + dy;
        if (self.isBlocked(nx, ny)) return false;
        if (nx == self.stairs.x and ny == self.stairs.y and self.hasLivingBoss()) {
            self.pushLog("深渊守卫封印了楼梯", .{});
            return false;
        }
        if (self.enemyAt(nx, ny)) |idx| {
            self.playerAttack(idx, 1.0);
            self.endTurn();
            return true;
        }
        self.hero.last_pos = self.hero.pos;
        self.hero.pos = .{ .x = nx, .y = ny };
        self.pickupAt(nx, ny);
        self.triggerTrapAt(nx, ny);
        if (self.hero.pos.x == self.stairs.x and self.hero.pos.y == self.stairs.y) {
            self.nextFloor();
            return true;
        }
        self.endTurn();
        return true;
    }

    pub fn wait(self: *Sim) bool {
        if (self.state != .playing) return false;
        var danger = false;
        for (self.enemies[0..self.enemy_count]) |e| {
            if (e.alive and dist(e.pos, self.hero.pos) <= 6) danger = true;
        }
        if (!danger) {
            self.hero.hp = @min(self.hero.hp_max, self.hero.hp + self.hero.hp_max * 0.08);
            self.hero.resource = @min(self.hero.resource_max, self.hero.resource + self.hero.resource_max * 0.15);
            self.pushLog("休息：恢复生命与资源", .{});
        }
        self.hero.last_pos = self.hero.pos;
        self.endTurn();
        return true;
    }

    fn pickupAt(self: *Sim, x: i32, y: i32) void {
        for (self.chests, 0..) |c, i| {
            if (!self.chest_alive[i] or c.x != x or c.y != y) continue;
            self.chest_alive[i] = false;
            self.chest_count -= 1;
            const heal = @min(self.hero.hp_max - self.hero.hp, 25);
            self.hero.hp += heal;
            self.chest_loot_events += 1;
            self.pushLog("打开宝箱：恢复 {d:.0} 生命", .{heal});
            return;
        }
    }

    fn triggerTrapAt(self: *Sim, x: i32, y: i32) void {
        for (self.traps, 0..) |p, i| {
            if (!self.trap_alive[i] or p.x != x or p.y != y) continue;
            self.trap_alive[i] = false;
            self.trap_count -= 1;
            const dmg: f32 = 8.0 + @as(f32, @floatFromInt(self.floor)) * 4.0;
            self.hero.hp = @max(0, self.hero.hp - dmg);
            self.pushLog("触发陷阱 -{d:.0} 生命", .{dmg});
            if (self.hero.hp <= 0) self.state = .dead;
            return;
        }
    }

    pub fn nextFloor(self: *Sim) void {
        self.floor += 1;
        if (self.floor > self.floors) {
            self.state = .victory;
            self.pushLog("击败深渊守卫，胜利", .{});
            return;
        }
        self.hero.hp = @min(self.hero.hp_max, self.hero.hp + self.hero.hp_max * 0.25);
        self.hero.resource = @min(self.hero.resource_max, self.hero.resource + self.hero.resource_max * 0.5);
        self.turn += 1;
        self.generateFloor();
        if (self.floor == self.floors and self.hasLivingBoss()) self.pushLog("深渊守卫封印了楼梯", .{});
        self.armBossAoe();
    }

    fn armBossAoe(self: *Sim) void {
        if (self.aoe_armed) return;
        if (!intent_mod.bossAoeDue(self.turn +| 1)) return;
        for (self.enemies[0..self.enemy_count]) |e| {
            if (e.alive and e.kind == intent_mod.boss_kind) {
                self.aoe_target = self.hero.pos;
                self.aoe_armed = true;
                return;
            }
        }
    }

    fn endTurn(self: *Sim) void {
        if (self.state != .playing) return;
        // start of the next player turn
        self.turn += 1;
        for (&self.hero.cooldowns) |*cd| {
            if (cd.* > 0) cd.* -= 1;
        }
        if (self.hero.buff_turns > 0) {
            self.hero.buff_turns -= 1;
            if (self.hero.buff_turns == 0) self.hero.buff_pct = 0;
        }
        self.hero.resource = @min(self.hero.resource_max, self.hero.resource + self.hero.res_per_turn);
        if (self.hero.hp <= 0) {
            self.state = .dead;
            return;
        }
        if (self.defer_enemies) {
            self.enemy_phase_pending = true;
            return;
        }
        self.enemyPhase();
        self.armBossAoe();
        if (self.hero.hp <= 0) self.state = .dead;
        if (self.enemy_count == 0 and self.floor >= self.floors) {
            self.state = .victory;
            self.pushLog("深渊守卫倒下，胜利", .{});
        }
    }

    /// Finish a deferred enemy phase. Safe to call when nothing is pending.
    pub fn resolvePendingEnemyPhase(self: *Sim) void {
        if (!self.enemy_phase_pending) return;
        self.enemy_phase_pending = false;
        self.enemyPhase();
        self.armBossAoe();
        if (self.hero.hp <= 0) self.state = .dead;
        if (self.enemy_count == 0 and self.floor >= self.floors and self.state == .playing) {
            self.state = .victory;
            self.pushLog("深渊守卫倒下，胜利", .{});
        }
    }

    fn enemyPhase(self: *Sim) void {
        var order: [max_enemies]usize = undefined;
        var n: usize = 0;
        var i: usize = 0;
        while (i < self.enemy_count) : (i += 1) {
            if (!self.enemies[i].alive) continue;
            order[n] = i;
            n += 1;
        }
        // insertion sort: fast first, stable
        var a: usize = 1;
        while (a < n) : (a += 1) {
            const key = order[a];
            var b = a;
            while (b > 0 and self.enemies[order[b - 1]].speed < self.enemies[key].speed) : (b -= 1) {
                order[b] = order[b - 1];
            }
            order[b] = key;
        }
        for (order[0..n]) |idx| {
            var actions: u8 = 1;
            const sp = self.enemies[idx].speed;
            if (sp >= 150 and self.turn % 2 == 0) actions = 2;
            if (sp <= 75 and self.turn % 2 == 0) actions = 0;
            var act: u8 = 0;
            while (act < actions) : (act += 1) {
                if (!self.enemies[idx].alive) break;
                if (self.hero.hp <= 0) break;
                self.enemyAct(idx);
            }
        }
    }

    fn enemyAct(self: *Sim, idx: usize) void {
        const e = &self.enemies[idx];
        if (!e.alive) return;
        if (e.stun_turns > 0) {
            e.stun_turns -= 1;
            return;
        }
        if (e.slow_turns > 0) e.slow_turns -= 1;
        if (e.kind == intent_mod.boss_kind and self.aoe_armed and intent_mod.bossAoeDue(self.turn)) {
            self.aoe_armed = false;
            if (@as(f32, @floatFromInt(dist(self.hero.pos, self.aoe_target))) <= intent_mod.boss_aoe_radius) {
                const raw = e.attack * intent_mod.boss_aoe_damage_scale * (if (e.slow_turns > 0) intent_mod.slow_damage_scale else 1.0);
                const dmg = combat.resolve(.{ .raw = raw }, .{ .armor = self.hero.armor }).amount;
                self.hero.hp = @max(0, self.hero.hp - dmg);
                self.pushLog("深渊守卫 深渊斩 -{d:.0}", .{dmg});
            } else {
                self.pushLog("躲开深渊斩", .{});
            }
            return;
        }
        const d = dist(e.pos, self.hero.pos);
        const los = self.map.lineOfSightTo(
            .{ .x = e.pos.x, .y = e.pos.y },
            .{ .x = self.hero.pos.x, .y = self.hero.pos.y },
            null,
        );
        if (d <= 1 or (d <= e.range and los)) {
            self.enemyAttack(idx);
            return;
        }
        // roguelike chase: A* around walls, then a greedy fallback.
        if (self.map.astarToOccupiedGoal(
            .{ .x = e.pos.x, .y = e.pos.y },
            .{ .x = self.hero.pos.x, .y = self.hero.pos.y },
            null,
        )) |path| {
            if (path.len > 1) {
                const next = path.slice()[1];
                if (self.canEnemyStep(next.x, next.y)) {
                    e.pos = .{ .x = next.x, .y = next.y };
                    return;
                }
            }
        }
        const dx: i32 = if (self.hero.pos.x > e.pos.x) 1 else if (self.hero.pos.x < e.pos.x) -1 else 0;
        const dy: i32 = if (self.hero.pos.y > e.pos.y) 1 else if (self.hero.pos.y < e.pos.y) -1 else 0;
        if (dx != 0 and self.canEnemyStep(e.pos.x + dx, e.pos.y)) {
            e.pos.x += dx;
        } else if (dy != 0 and self.canEnemyStep(e.pos.x, e.pos.y + dy)) {
            e.pos.y += dy;
        }
    }

    fn canEnemyStep(self: *const Sim, x: i32, y: i32) bool {
        if (self.isBlocked(x, y)) return false;
        if (self.enemyAt(x, y) != null) return false;
        if (self.hero.pos.x == x and self.hero.pos.y == y) return false;
        return true;
    }

    /// Terrain-only line of sight over the same `blocked` grid used for
    /// movement. Read-only, used by the aim preview before confirming a
    /// ranged talent. The target cell itself may be occupied.
    pub fn hasLineOfSight(self: *const Sim, a: GridPos, b: GridPos) bool {
        return self.lineClear(a, b);
    }

    fn lineClear(self: *const Sim, a: GridPos, b: GridPos) bool {
        var x = a.x;
        var y = a.y;
        const dx: i32 = @intCast(@abs(b.x - a.x));
        const dy: i32 = -@as(i32, @intCast(@abs(b.y - a.y)));
        const sx: i32 = if (a.x < b.x) 1 else -1;
        const sy: i32 = if (a.y < b.y) 1 else -1;
        var err = dx + dy;
        var guard: usize = 0;
        while (guard < 32) : (guard += 1) {
            if (x == b.x and y == b.y) return true;
            if (!(x == a.x and y == a.y) and self.isBlocked(x, y)) return false;
            const e2 = err * 2;
            if (e2 >= dy) {
                err += dy;
                x += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y += sy;
            }
        }
        return false;
    }

    fn enemyAttack(self: *Sim, idx: usize) void {
        const e = self.enemies[idx];
        var raw = e.attack * 0.72;
        if (e.slow_turns > 0) raw *= 0.55;
        const dmg = combat.resolve(.{ .raw = raw }, .{ .armor = self.hero.armor }).amount;
        self.hero.hp = @max(0, self.hero.hp - dmg);
        self.pushLog("{s} 造成 {d:.0} 伤害", .{ e.name, dmg });
    }

    pub fn playerAttack(self: *Sim, idx: usize, mult: f32) void {
        const e = &self.enemies[idx];
        if (!e.alive) return;
        var raw = self.hero.attack * mult;
        if (self.hero.buff_turns > 0) raw *= 1.0 + self.hero.buff_pct;
        const crit = self.rng.random().float(f32) < self.hero.crit;
        const result = combat.resolve(.{ .raw = raw, .crit = crit }, .{ .armor = e.armor });
        e.hp -= result.amount;
        self.pushLog("命中 {s} {d:.0}{s}", .{ e.name, result.amount, if (result.crit) " 暴击" else "" });
        if (e.hp <= 0) self.killEnemy(idx);
    }

    fn killEnemy(self: *Sim, idx: usize) void {
        const e = &self.enemies[idx];
        if (!e.alive) return;
        e.alive = false;
        e.hp = 0;
        if (e.kind == intent_mod.boss_kind) self.aoe_armed = false;
        self.kills += 1;
        self.kill_loot_events += 1;
        self.pushLog("击杀 {s} +{d}XP", .{ e.name, e.xp });
        self.hero.xp += e.xp;
        while (self.hero.xp >= 100 * self.hero.level and self.hero.level < 50) {
            self.hero.xp -= 100 * self.hero.level;
            self.hero.level += 1;
            if (self.auto_allocate) {
                switch (self.class) {
                    .warrior => self.hero.stats.strength += 1,
                    .mage, .chronomancer => self.hero.stats.magic += 1,
                }
            } else {
                self.hero.pending_points +|= 1;
            }
            self.recomputeHero();
            self.hero.hp = self.hero.hp_max;
            self.hero.resource = self.hero.resource_max;
            if (self.hero.pending_points > 0) {
                self.pushLog("升级到 {d} 级 +1 属性点", .{self.hero.level});
            } else {
                self.pushLog("升级到 {d} 级", .{self.hero.level});
            }
        }
        var any = false;
        for (self.enemies[0..self.enemy_count]) |en| {
            if (en.alive) any = true;
        }
        if (!any and self.floor >= self.floors) self.state = .victory;
    }

    pub fn nearestEnemy(self: *const Sim, max_range: i32) ?usize {
        var best: ?usize = null;
        var best_d: i32 = 999;
        var i: usize = 0;
        while (i < self.enemy_count) : (i += 1) {
            const e = self.enemies[i];
            if (!e.alive) continue;
            const d = dist(e.pos, self.hero.pos);
            if (d > max_range) continue;
            if (d < best_d) {
                best_d = d;
                best = i;
            }
        }
        return best;
    }

    pub fn talentName(self: *const Sim, i: usize) []const u8 {
        return talentNameFor(self.class, i);
    }

    pub fn talentDesc(self: *const Sim, i: usize) []const u8 {
        return talentDescFor(self.class, i);
    }

    pub fn talentCost(self: *const Sim, i: usize) u16 {
        _ = self;
        return switch (i) {
            0 => 25,
            1 => 30,
            else => 20,
        };
    }

    pub fn talentCooldown(self: *const Sim, i: usize) u16 {
        _ = self;
        return switch (i) {
            0 => 4,
            1 => 6,
            else => 8,
        };
    }

    pub fn useTalent(self: *Sim, i: usize) bool {
        return self.useTalentOn(i, null);
    }

    fn pickTarget(self: *const Sim, max_range: i32, preferred: ?usize) ?usize {
        if (preferred) |p| {
            if (p < self.enemy_count) {
                const e = self.enemies[p];
                if (e.alive and dist(e.pos, self.hero.pos) <= max_range) return p;
            }
        }
        return self.nearestEnemy(max_range);
    }

    pub fn useTalentOn(self: *Sim, i: usize, target: ?usize) bool {
        if (self.state != .playing or i >= 3) return false;
        if (self.hero.cooldowns[i] > 0) return false;
        const cost = self.talentCost(i);
        if (self.hero.resource < @as(f32, @floatFromInt(cost))) return false;
        switch (self.class) {
            .warrior => {
                if (i == 2) {
                    self.hero.resource -= @floatFromInt(cost);
                    self.hero.cooldowns[i] = self.talentCooldown(i);
                    self.hero.buff_turns = 3;
                    self.hero.buff_pct = 0.30;
                    self.pushLog("战吼：攻击 +30%", .{});
                    self.endTurn();
                    return true;
                }
                const idx = self.pickTarget(if (i == 0) 1 else 4, target) orelse return false;
                self.hero.resource -= @floatFromInt(cost);
                self.hero.cooldowns[i] = self.talentCooldown(i);
                if (i == 0) {
                    self.playerAttack(idx, 2.2);
                } else {
                    self.playerAttack(idx, 1.5);
                }
                self.endTurn();
                return true;
            },
            .mage => {
                if (i == 2) {
                    // blink to a free cell 3..5 away
                    var tries: usize = 0;
                    while (tries < 60) : (tries += 1) {
                        const x = self.hero.pos.x + self.rng.random().intRangeLessThan(i32, -5, 6);
                        const y = self.hero.pos.y + self.rng.random().intRangeLessThan(i32, -5, 6);
                        if (self.isFree(x, y) and dist(.{ .x = x, .y = y }, self.hero.pos) >= 3) {
                            self.hero.last_pos = self.hero.pos;
                            self.hero.pos = .{ .x = x, .y = y };
                            self.hero.resource -= @floatFromInt(cost);
                            self.hero.cooldowns[i] = self.talentCooldown(i);
                            self.pushLog("闪现", .{});
                            self.endTurn();
                            return true;
                        }
                    }
                    return false;
                }
                const idx = self.pickTarget(if (i == 0) 5 else 4, target) orelse return false;
                self.hero.resource -= @floatFromInt(cost);
                self.hero.cooldowns[i] = self.talentCooldown(i);
                if (i == 0) {
                    self.aoeAttack(idx, 2.5, 1.5);
                } else {
                    self.playerAttack(idx, 1.8);
                    self.enemies[idx].slow_turns = 2;
                }
                self.endTurn();
                return true;
            },
            .chronomancer => {
                if (i == 2) {
                    self.hero.pos = self.hero.last_pos;
                    self.hero.resource -= @floatFromInt(cost);
                    self.hero.cooldowns[i] = self.talentCooldown(i);
                    self.pushLog("回溯到上一格", .{});
                    self.endTurn();
                    return true;
                }
                const idx = self.pickTarget(if (i == 0) 5 else 4, target) orelse return false;
                self.hero.resource -= @floatFromInt(cost);
                self.hero.cooldowns[i] = self.talentCooldown(i);
                if (i == 0) {
                    self.playerAttack(idx, 2.0);
                    if (self.enemies[idx].alive) self.enemies[idx].slow_turns = 2;
                } else {
                    self.playerAttack(idx, 1.2);
                    self.enemies[idx].stun_turns = 2;
                }
                self.endTurn();
                return true;
            },
        }
    }

    fn aoeAttack(self: *Sim, primary: usize, mult: f32, radius: f32) void {
        self.aoeAttackAt(self.enemies[primary].pos, mult, radius);
    }

    /// Ground-centred area attack. The centre itself takes full damage; every
    /// other enemy within the radius takes 60%. Used by mouse/ground-targeted
    /// fireball and by the enemy-centred helper above.
    fn aoeAttackAt(self: *Sim, center: GridPos, mult: f32, radius: f32) void {
        var i: usize = 0;
        while (i < self.enemy_count) : (i += 1) {
            const e = &self.enemies[i];
            if (!e.alive) continue;
            const d = dist(e.pos, center);
            if (d > @as(i32, @intFromFloat(radius))) continue;
            self.playerAttack(i, if (d == 0) mult else mult * 0.6);
            if (!e.alive) continue;
        }
    }

    /// Cast a talent at a grid cell. Fireball (mage slot 0) is the only v1
    /// talent with a ground target; everything else resolves to the enemy on
    /// that cell and falls back to the normal single-target path.
    pub fn useTalentAt(self: *Sim, i: usize, cell: GridPos) bool {
        if (self.state != .playing or i >= 3) return false;
        if (!(self.class == .mage and i == 0)) {
            return self.useTalentOn(i, self.enemyAt(cell.x, cell.y));
        }
        if (self.hero.cooldowns[i] > 0) return false;
        const cost = self.talentCost(i);
        if (self.hero.resource < @as(f32, @floatFromInt(cost))) return false;
        if (self.isBlocked(cell.x, cell.y)) return false;
        if (dist(self.hero.pos, cell) > 5) return false;
        if (!self.map.lineOfSightTo(
            .{ .x = self.hero.pos.x, .y = self.hero.pos.y },
            .{ .x = cell.x, .y = cell.y },
            null,
        )) return false;
        self.hero.resource -= @floatFromInt(cost);
        self.hero.cooldowns[i] = self.talentCooldown(i);
        self.aoeAttackAt(cell, 2.5, 1.5);
        self.pushLog("火球轰击地面", .{});
        self.endTurn();
        return true;
    }

    pub fn stairsHint(self: *const Sim) []const u8 {
        const dx = self.stairs.x - self.hero.pos.x;
        const dy = self.stairs.y - self.hero.pos.y;
        if (@abs(dx) + @abs(dy) <= 1) return "楼梯就在脚下";
        if (@abs(dx) > @abs(dy)) return if (dx > 0) "楼梯 东" else "楼梯 西";
        return if (dy > 0) "楼梯 南" else "楼梯 北";
    }
};

test "run sim: wall bump costs no turn" {
    var s = Sim.init(7, .warrior);
    const turn = s.turn;
    // find any blocked neighbour; the border guarantees one somewhere
    var dx: i32 = 0;
    var dy: i32 = 0;
    var found = false;
    const dirs = [_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };
    for (dirs) |d| {
        if (!s.canMove(d[0], d[1])) {
            dx = d[0];
            dy = d[1];
            found = true;
            break;
        }
    }
    if (found) {
        try std.testing.expect(!s.move(dx, dy));
        try std.testing.expectEqual(turn, s.turn);
    }
}

test "run sim: adjacent enemy acts on wait" {
    var s = Sim.init(11, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 70,
        .hp_max = 70,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
    };
    const hp = s.hero.hp;
    _ = s.wait();
    try std.testing.expect(s.hero.hp < hp);
    try std.testing.expect(s.turn > 1);
}

test "run sim: warrior talent spends resource and starts cooldown" {
    var s = Sim.init(13, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 70,
        .hp_max = 70,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
    };
    const res = s.hero.resource;
    try std.testing.expect(s.useTalent(0));
    try std.testing.expect(s.hero.resource < res);
    try std.testing.expect(s.hero.cooldowns[0] > 0);
}

test "run sim: stepping on stairs advances the floor" {
    var s = Sim.init(17, .mage);
    s.hero.pos = .{ .x = s.stairs.x, .y = s.stairs.y - 1 };
    if (s.canMove(0, 1)) {
        _ = s.move(0, 1);
        try std.testing.expect(s.floor >= 2);
    }
}

test "run sim: killing the last boss wins" {
    var s = Sim.init(21, .mage);
    s.floor = s.floors;
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 5,
        .name = "深渊守卫",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 1,
        .hp_max = 420,
        .attack = 16,
        .armor = 15,
        .speed = 90,
        .range = 1,
        .xp = 200,
    };
    s.hero.attack = 100;
    s.playerAttack(0, 1.0);
    try std.testing.expect(s.enemies[0].hp <= 0);
    try std.testing.expectEqual(State.victory, s.state);
}

test "run sim: level-up banks a point and auto allocate spends it" {
    var s = Sim.init(22, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 1,
        .hp_max = 70,
        .attack = 8,
        .armor = 0,
        .speed = 100,
        .range = 1,
        .xp = 200,
    };
    const str = s.hero.stats.strength;
    s.hero.attack = 100;
    s.playerAttack(0, 1.0);
    try std.testing.expectEqual(@as(u16, 2), s.hero.level);
    try std.testing.expectEqual(@as(u8, 1), s.hero.pending_points);
    try std.testing.expectEqual(str, s.hero.stats.strength);
    try std.testing.expect(s.spendPoint(0));
    try std.testing.expectEqual(str + 1, s.hero.stats.strength);
    try std.testing.expectEqual(@as(u8, 0), s.hero.pending_points);

    var auto = Sim.init(23, .warrior);
    auto.auto_allocate = true;
    auto.enemy_count = 1;
    auto.enemies[0] = s.enemies[0];
    auto.enemies[0].hp = 1;
    auto.enemies[0].alive = true;
    auto.enemies[0].xp = 200;
    const base = auto.hero.stats.strength;
    auto.hero.attack = 100;
    auto.playerAttack(0, 1.0);
    try std.testing.expectEqual(base + 1, auto.hero.stats.strength);
    try std.testing.expectEqual(@as(u8, 0), auto.hero.pending_points);
}

test "run sim: deferred enemy phase waits for resolution" {
    var s = Sim.init(51, .warrior);
    s.defer_enemies = true;
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 70,
        .hp_max = 70,
        .attack = 99,
        .armor = 0,
        .speed = 100,
        .range = 1,
        .xp = 20,
        .alive = true,
    };
    const hp = s.hero.hp;
    try std.testing.expect(s.wait());
    try std.testing.expect(s.enemy_phase_pending);
    try std.testing.expectEqual(hp, s.hero.hp);
    s.resolvePendingEnemyPhase();
    try std.testing.expect(!s.enemy_phase_pending);
    try std.testing.expect(s.hero.hp < hp or s.state == .dead);
}

test "run sim: boss AOE resolves on the telegraphed turn" {
    var s = Sim.init(31, .warrior);
    s.turn = 2;
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 5,
        .name = "深渊守卫",
        .pos = .{ .x = 10, .y = 2 },
        .hp = 420,
        .hp_max = 420,
        .attack = 16,
        .armor = 15,
        .speed = 90,
        .range = 1,
        .xp = 200,
    };
    s.aoe_armed = true;
    s.aoe_target = s.hero.pos;
    const hp = s.hero.hp;
    _ = s.wait();
    try std.testing.expect(s.hero.hp < hp);
}

test "run sim: enemy speeds cover the extra/skip bands" {
    var fast = false;
    var slow = false;
    for (enemy_defs) |def| {
        if (def.speed >= 150) fast = true;
        if (def.speed <= 75) slow = true;
    }
    try std.testing.expect(fast);
    try std.testing.expect(slow);
}

test "run sim: mage fireball can be cast on a ground cell" {
    var s = Sim.init(41, .mage);
    var center: ?GridPos = null;
    var y: i32 = 0;
    while (y < grid_h and center == null) : (y += 1) {
        var x: i32 = 0;
        while (x < grid_w) : (x += 1) {
            const p = GridPos{ .x = x, .y = y };
            if (s.isBlocked(x, y)) continue;
            const d = @abs(s.hero.pos.x - p.x) + @abs(s.hero.pos.y - p.y);
            if (d > 5 or d == 0) continue;
            if (!s.map.lineOfSightTo(.{ .x = s.hero.pos.x, .y = s.hero.pos.y }, .{ .x = x, .y = y }, null)) continue;
            center = p;
            break;
        }
    }
    const c = center orelse return error.SkipZigTest;
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 0,
        .name = "骷髅兵",
        .pos = c,
        .hp = 70,
        .hp_max = 70,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
    };
    const turn = s.turn;
    try std.testing.expect(s.useTalentAt(0, c));
    try std.testing.expect(s.enemies[0].hp < 70);
    try std.testing.expectEqual(turn + 1, s.turn);
    try std.testing.expect(s.hero.cooldowns[0] > 0);
}

test "run sim: fireball ground target validates range and walls" {
    var s = Sim.init(43, .mage);
    const turn = s.turn;
    try std.testing.expect(!s.useTalentAt(0, .{ .x = 0, .y = 0 })); // border wall
    try std.testing.expectEqual(turn, s.turn);
}

test "run sim: boss seals the stairs until defeated" {
    var s = Sim.init(37, .warrior);
    s.floor = 3;
    s.turn = 1;
    const dirs = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
    var start: ?GridPos = null;
    for (dirs) |d| {
        const p = dungeon_mod.GridPos{ .x = s.stairs.x + d[0], .y = s.stairs.y + d[1] };
        if (s.map.isWalkable(p)) {
            start = .{ .x = p.x, .y = p.y };
            break;
        }
    }
    const from = start orelse return error.SkipZigTest;
    s.hero.pos = from;
    s.enemy_count = 1;
    s.enemies[0] = .{
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
    };
    const dx = s.stairs.x - s.hero.pos.x;
    const dy = s.stairs.y - s.hero.pos.y;
    try std.testing.expect(!s.move(dx, dy));
    try std.testing.expectEqual(@as(u8, 3), s.floor);
    try std.testing.expectEqual(@as(u32, 1), s.turn);
    s.enemies[0].alive = false;
    try std.testing.expect(s.move(dx, dy));
}

test "run sim: stepping away dodges the telegraphed boss AOE" {
    var s = Sim.init(33, .warrior);
    s.turn = 2;
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 5,
        .name = "深渊守卫",
        .pos = .{ .x = 10, .y = 2 },
        .hp = 420,
        .hp_max = 420,
        .attack = 16,
        .armor = 15,
        .speed = 90,
        .range = 1,
        .xp = 200,
    };
    s.aoe_armed = true;
    s.aoe_target = .{ .x = s.hero.pos.x, .y = s.hero.pos.y };
    const hp = s.hero.hp;
    // find a legal open neighbour and step out of the marked cell
    const dirs = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
    for (dirs) |d| {
        if (s.canMove(d[0], d[1])) {
            _ = s.move(d[0], d[1]);
            break;
        }
    }
    try std.testing.expect(s.hero.hp >= hp);
}

test "run sim: same seed produces the same floor" {
    const a = Sim.init(99, .warrior);
    const b = Sim.init(99, .warrior);
    try std.testing.expectEqual(a.hero.pos.x, b.hero.pos.x);
    try std.testing.expectEqual(a.hero.pos.y, b.hero.pos.y);
    try std.testing.expectEqual(a.stairs.x, b.stairs.x);
    try std.testing.expectEqual(a.enemy_count, b.enemy_count);
}

test "run sim: intent preview is read-only" {
    var s = Sim.init(23, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 70,
        .hp_max = 70,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
    };
    const hp = s.hero.hp;
    const turn = s.turn;

    const intent = s.intentFor(0) orelse return error.MissingIntent;
    try std.testing.expectEqual(intent_mod.IntentKind.melee, intent.kind);
    try std.testing.expect(intent.target.eql(.{ .x = s.hero.pos.x, .y = s.hero.pos.y }));
    const expected = combat.preview(.{ .raw = 8 * 0.72 }, .{ .armor = s.hero.armor });
    try std.testing.expectApproxEqAbs(expected, intent.damage_preview, 0.001);
    try std.testing.expect(intent.damage_preview < 8 * 0.72);
    try std.testing.expectEqual(turn, s.turn);
    try std.testing.expectEqual(hp, s.hero.hp);
    try std.testing.expect(s.intentFor(1) == null);

    var intents: [max_enemies]intent_mod.EnemyIntent = undefined;
    try std.testing.expectEqual(@as(usize, 1), s.previewIntents(&intents));
    try std.testing.expectEqual(intent_mod.IntentKind.melee, intents[0].kind);
    try std.testing.expectEqual(hp, s.hero.hp);
    try std.testing.expectEqual(turn, s.turn);
}

test "run sim: boss intent telegraphs its AOE on the next enemy phase" {
    var s = Sim.init(29, .warrior);
    s.turn = 2; // the player action below advances to enemy phase 3
    s.enemy_count = 1;
    s.enemies[0] = .{
        .kind = 5,
        .name = "深渊守卫",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 420,
        .hp_max = 420,
        .attack = 16,
        .armor = 15,
        .speed = 90,
        .range = 1,
        .xp = 200,
    };

    const intent = s.intentFor(0) orelse return error.MissingIntent;
    try std.testing.expectEqual(intent_mod.IntentKind.aoe, intent.kind);
    try std.testing.expect(intent.target.eql(.{ .x = s.hero.pos.x, .y = s.hero.pos.y }));
    try std.testing.expectEqual(@as(f32, 0.9), intent.aoe_radius);
    try std.testing.expectEqual(@as(u8, 1), intent.telegraph_turns);

    // The phase after this one is turn 4, back to the normal melee rotation.
    s.turn = 3;
    const next = s.intentFor(0) orelse return error.MissingIntent;
    try std.testing.expectEqual(intent_mod.IntentKind.melee, next.kind);
}

test "run sim: class menu metadata covers all three classes" {
    var ci: usize = 0;
    while (ci < class_count) : (ci += 1) {
        const class: Class = @fromBackingInt(@intCast(ci));
        try std.testing.expect(class_names[ci].len > 0);
        try std.testing.expect(resource_names[ci].len > 0);
        try std.testing.expect(class_roles[ci].len > 0);
        try std.testing.expect(classHpMax(class) > 0);
        try std.testing.expect(classResourceMax(class) > 0);
        var ti: usize = 0;
        while (ti < 3) : (ti += 1) {
            try std.testing.expect(talentNameFor(class, ti).len > 0);
            try std.testing.expect(talentDescFor(class, ti).len > 0);
        }
    }
}

test "run sim: class choice reseeds deterministically" {
    const a = nextSeed(12345);
    const b = nextSeed(12345);
    try std.testing.expectEqual(a, b);
    try std.testing.expect(a != 12345);
    try std.testing.expect(nextSeed(a) != a);

    const s = Sim.init(a, .mage);
    try std.testing.expectEqual(a, s.seed);
    try std.testing.expectEqual(Class.mage, s.class);
    try std.testing.expectEqual(Class.mage, s.hero.class);
}

test "hero sheet is the attributes sheet, not a second formula copy" {
    for ([_]Class{ .warrior, .mage, .chronomancer }) |class| {
        const s = Sim.init(12345, class);
        const base = attributes.Stats.fromArray(.{
            s.hero.stats.strength,
            s.hero.stats.agility,
            s.hero.stats.constitution,
            s.hero.stats.perception,
            s.hero.stats.magic,
            s.hero.stats.will,
        });
        const sheet = attributes.recompute(base, &.{}, class);
        try std.testing.expectApproxEqAbs(sheet.derived.hp_max, s.hero.hp_max, 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.resource_max, s.hero.resource_max, 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.attack, s.hero.attack, 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.armor, s.hero.armor, 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.crit, s.hero.crit, 0.0001);
        try std.testing.expectApproxEqAbs(sheet.derived.speed, @as(f32, @floatFromInt(s.hero.speed)), 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.resource_per_turn, s.hero.res_per_turn, 0.001);
        try std.testing.expectEqual(@as(u16, @intFromFloat(sheet.derived.hp_max)), classHpMax(class));
        try std.testing.expectEqual(@as(u16, @intFromFloat(sheet.derived.resource_max)), classResourceMax(class));
    }
}
