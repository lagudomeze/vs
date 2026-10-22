//! Pure turn-based ToME4-style simulation: 13x13 grid, one hero, enemies,
//! floors, talents, XP and a deterministic RNG. No SDL, renderer or ECS.
const std = @import("std");
const dungeon_mod = @import("dungeon.zig");
const attributes = @import("attributes.zig");
const intent_mod = @import("intent.zig");

pub const grid_w = 13;
pub const grid_h = 13;
pub const max_enemies = 12;

pub const Class = enum(u8) { warrior, mage, chronomancer };
pub const class_count = 3;

pub fn classFromIndex(i: u8) Class {
    return @fromBackingInt(@intCast(@min(i, class_count - 1)));
}

pub const class_names = [_][]const u8{ "狂战士", "元素法师", "时空法师" };
pub const resource_names = [_][]const u8{ "精力", "法力", "悖论" };

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

    pub fn mainStat(self: Stats, class: Class) f32 {
        return switch (class) {
            .warrior => self.strength,
            .mage, .chronomancer => self.magic,
        };
    }
};

const base_stats = [_]Stats{
    Stats.fromArray(.{ 14, 10, 16, 8, 4, 10 }),
    Stats.fromArray(.{ 6, 8, 8, 12, 18, 12 }),
    Stats.fromArray(.{ 7, 10, 9, 14, 14, 13 }),
};

const class_base_attack = [_]f32{ 18, 11, 14 };

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
    .{ .name = "石魔像", .hp = 150, .attack = 12, .armor = 12, .speed = 80, .range = 1, .xp = 40 },
    .{ .name = "精英骷髅", .hp = 100, .attack = 11, .armor = 7, .speed = 110, .range = 1, .xp = 50 },
    .{ .name = "精英幽魂", .hp = 85, .attack = 10, .armor = 2, .speed = 120, .range = 4, .xp = 50 },
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
    kills: u32 = 0,
    chest_loot_events: u32 = 0,
    kill_loot_events: u32 = 0,
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
        self.hero = Hero{ .class = class, .stats = base_stats[@backingInt(class)] };
        self.floor = 1;
        self.turn = 1;
        self.kills = 0;
        self.chest_loot_events = 0;
        self.kill_loot_events = 0;
        self.state = .playing;
        self.log_head = 0;
        self.log_total = 0;
        self.recomputeHero();
        self.hero.hp = self.hero.hp_max;
        self.hero.resource = self.hero.resource_max;
        self.generateFloor();
        self.pushLog("进入第 1 层", .{});
    }

    pub fn recomputeHero(self: *Sim) void {
        const st = self.hero.stats;
        const main = st.mainStat(self.class);
        const base_atk = class_base_attack[@backingInt(self.class)];
        self.hero.hp_max = 40 + st.constitution * 8;
        self.hero.resource_max = 60 + st.will * 4;
        self.hero.attack = base_atk + main * 1.2;
        self.hero.armor = st.constitution * 0.5;
        self.hero.crit = @min(0.50, 0.05 + st.perception * 0.004);
        self.hero.speed = @intFromFloat(std.math.clamp(100 + (st.agility - 10) * 2, 50, 200));
        self.hero.res_per_turn = 8 + st.will * 0.35;
        self.hero.eff_stats = .{ st.strength, st.agility, st.constitution, st.perception, st.magic, st.will };
        self.hero.hp = @min(self.hero.hp, self.hero.hp_max);
        self.hero.resource = @min(self.hero.resource, self.hero.resource_max);
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
        const klass: attributes.Class = switch (self.class) {
            .warrior => .warrior,
            .mage => .mage,
            .chronomancer => .chronomancer,
        };
        const sheet = attributes.recompute(base, mods, klass);
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
        return intent_mod.preview(
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
        return self.blocked[@intCast(y * grid_w + x)];
    }

    fn isFree(self: *const Sim, x: i32, y: i32) bool {
        return !self.isBlocked(x, y) and self.enemyAt(x, y) == null;
    }

    fn dist(a: GridPos, b: GridPos) i32 {
        return @intCast(@abs(a.x - b.x) + @abs(a.y - b.y));
    }

    pub fn generateFloor(self: *Sim) void {
        self.enemy_count = 0;
        self.map = dungeon_mod.Dungeon.generate(self.seed, self.floor);
        self.map.validate() catch {};

        var y: i32 = 0;
        while (y < grid_h) : (y += 1) {
            var x: i32 = 0;
            while (x < grid_w) : (x += 1) {
                const p = dungeon_mod.GridPos{ .x = x, .y = y };
                self.blocked[@intCast(y * grid_w + x)] = !self.map.isWalkable(p);
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
        const max_spawns: usize = switch (self.floor) {
            1 => 4,
            2 => 4,
            else => 4,
        };
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

    pub fn move(self: *Sim, dx: i32, dy: i32) bool {
        if (self.state != .playing) return false;
        if (dx == 0 and dy == 0) return false;
        const nx = self.hero.pos.x + dx;
        const ny = self.hero.pos.y + dy;
        if (self.isBlocked(nx, ny)) return false;
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
        self.enemyPhase();
        if (self.hero.hp <= 0) self.state = .dead;
        if (self.enemy_count == 0 and self.floor >= self.floors) {
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
        // ToME-style chase: A* around walls, then a greedy fallback.
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
        const dmg = raw * (0.15 + 0.85 * 50 / (50 + self.hero.armor));
        self.hero.hp = @max(0, self.hero.hp - dmg);
        self.pushLog("{s} 造成 {d:.0} 伤害", .{ e.name, dmg });
    }

    pub fn playerAttack(self: *Sim, idx: usize, mult: f32) void {
        const e = &self.enemies[idx];
        if (!e.alive) return;
        var raw = self.hero.attack * mult;
        if (self.hero.buff_turns > 0) raw *= 1.0 + self.hero.buff_pct;
        const crit = self.rng.random().float(f32) < self.hero.crit;
        if (crit) raw *= 1.5;
        const dmg = raw * (0.15 + 0.85 * 50 / (50 + e.armor));
        e.hp -= dmg;
        self.pushLog("命中 {s} {d:.0}{s}", .{ e.name, dmg, if (crit) " 暴击" else "" });
        if (e.hp <= 0) self.killEnemy(idx);
    }

    fn killEnemy(self: *Sim, idx: usize) void {
        const e = &self.enemies[idx];
        if (!e.alive) return;
        e.alive = false;
        e.hp = 0;
        self.kills += 1;
        self.kill_loot_events += 1;
        self.pushLog("击杀 {s} +{d}XP", .{ e.name, e.xp });
        self.hero.xp += e.xp;
        while (self.hero.xp >= 100 * self.hero.level and self.hero.level < 50) {
            self.hero.xp -= 100 * self.hero.level;
            self.hero.level += 1;
            const main = self.hero.stats.mainStat(self.class);
            _ = main;
            switch (self.class) {
                .warrior => self.hero.stats.strength += 1,
                .mage, .chronomancer => self.hero.stats.magic += 1,
            }
            self.recomputeHero();
            self.hero.hp = self.hero.hp_max;
            self.hero.resource = self.hero.resource_max;
            self.pushLog("升级到 {d} 级", .{self.hero.level});
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
        return switch (self.class) {
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
        const center = self.enemies[primary].pos;
        var i: usize = 0;
        while (i < self.enemy_count) : (i += 1) {
            const e = &self.enemies[i];
            if (!e.alive) continue;
            if (dist(e.pos, center) > @as(i32, @intFromFloat(radius))) continue;
            self.playerAttack(i, if (i == primary) mult else mult * 0.6);
            if (!e.alive) continue;
        }
    }

    pub fn stairsHint(self: *const Sim) []const u8 {
        const dx = self.stairs.x - self.hero.pos.x;
        const dy = self.stairs.y - self.hero.pos.y;
        if (@abs(dx) + @abs(dy) <= 1) return "楼梯就在脚下";
        if (@abs(dx) > @abs(dy)) return if (dx > 0) "楼梯 东" else "楼梯 西";
        return if (dy > 0) "楼梯 南" else "楼梯 北";
    }
};

test "tome sim: wall bump costs no turn" {
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

test "tome sim: adjacent enemy acts on wait" {
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

test "tome sim: warrior talent spends resource and starts cooldown" {
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

test "tome sim: stepping on stairs advances the floor" {
    var s = Sim.init(17, .mage);
    s.hero.pos = .{ .x = s.stairs.x, .y = s.stairs.y - 1 };
    if (s.canMove(0, 1)) {
        _ = s.move(0, 1);
        try std.testing.expect(s.floor >= 2);
    }
}

test "tome sim: killing the last boss wins" {
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

test "tome sim: same seed produces the same floor" {
    const a = Sim.init(99, .warrior);
    const b = Sim.init(99, .warrior);
    try std.testing.expectEqual(a.hero.pos.x, b.hero.pos.x);
    try std.testing.expectEqual(a.hero.pos.y, b.hero.pos.y);
    try std.testing.expectEqual(a.stairs.x, b.stairs.x);
    try std.testing.expectEqual(a.enemy_count, b.enemy_count);
}

test "tome sim: intent preview is read-only" {
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
    try std.testing.expectEqual(turn, s.turn);
    try std.testing.expectEqual(hp, s.hero.hp);
    try std.testing.expect(s.intentFor(1) == null);

    var intents: [max_enemies]intent_mod.EnemyIntent = undefined;
    try std.testing.expectEqual(@as(usize, 1), s.previewIntents(&intents));
    try std.testing.expectEqual(intent_mod.IntentKind.melee, intents[0].kind);
    try std.testing.expectEqual(hp, s.hero.hp);
    try std.testing.expectEqual(turn, s.turn);
}

test "tome sim: boss intent telegraphs its AOE on the next enemy phase" {
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
    try std.testing.expectEqual(@as(f32, 2.2), intent.aoe_radius);
    try std.testing.expectEqual(@as(u8, 1), intent.telegraph_turns);

    // The phase after this one is turn 4, back to the normal melee rotation.
    s.turn = 3;
    const next = s.intentFor(0) orelse return error.MissingIntent;
    try std.testing.expectEqual(intent_mod.IntentKind.melee, next.kind);
}
