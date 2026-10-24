//! Pure turn-based simulation: 31x31 grid, one hero, enemies,
//! floors, talents, XP and a deterministic RNG. No SDL, renderer or ECS.
const std = @import("std");
const dungeon_mod = @import("dungeon.zig");
const attributes = @import("attributes.zig");
const status_def = @import("status_def.zig");
const combat = @import("combat.zig");
const content_mod = @import("content.zig");
const numeric = @import("numeric.zig");
const intent_mod = @import("intent.zig");

pub const grid_w = dungeon_mod.size;
pub const grid_h = dungeon_mod.size;
pub const max_enemies = 12;

pub const Class = attributes.Class;

pub const ShrineChoice = enum(u8) { main_stat, constitution, will, risk };

pub const ShopChoice = enum(u8) { heal, power, vitality, cleanse };
pub const shop_heal_cost: u32 = 25;
pub const shop_power_cost: u32 = 60;
pub const shop_vitality_cost: u32 = 60;
pub const shop_cleanse_cost: u32 = 20;
pub const shop_loot_cost: u32 = 80;

pub const Affix = enum(u8) { none, swift, armored, vampiric, explosive, split };

pub const FloorMod = enum(u8) {
    none,
    ember,
    frost,
    miasma,

    pub fn label(self: FloorMod) []const u8 {
        return switch (self) {
            .none => "",
            .ember => "EMBER",
            .frost => "FROST",
            .miasma => "MIASMA",
        };
    }

    pub fn burnScale(self: FloorMod) f32 {
        return if (self == .ember) 1.5 else 1.0;
    }

    pub fn enemySpeedScale(self: FloorMod) f32 {
        return if (self == .frost) 0.90 else 1.0;
    }

    pub fn resourceScale(self: FloorMod) f32 {
        return if (self == .miasma) 0.5 else 1.0;
    }
};

pub const Difficulty = enum(u8) {
    normal,
    hard,
    easy,

    pub fn label(self: Difficulty) []const u8 {
        return switch (self) {
            .normal => "普通",
            .hard => "困难",
            .easy => "简单",
        };
    }

    pub fn hpScale(self: Difficulty) f32 {
        return switch (self) {
            .normal => 1.0,
            .hard => 1.15,
            .easy => 0.80,
        };
    }

    pub fn damageScale(self: Difficulty) f32 {
        return switch (self) {
            .normal => 1.0,
            .hard => 1.08,
            .easy => 0.90,
        };
    }

    pub fn next(self: Difficulty) Difficulty {
        return switch (self) {
            .normal => .hard,
            .hard => .easy,
            .easy => .normal,
        };
    }
};
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
    .{ "2.0倍+减速", "1.2倍+停2减速", "REWIND 3" },
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

pub const GridPos = struct {
    x: i32,
    y: i32,

    pub fn eql(self: GridPos, other: GridPos) bool {
        return self.x == other.x and self.y == other.y;
    }
};

fn statsFromAttributes(st: attributes.Stats) numeric.PrimarySheet {
    return numeric.PrimarySheet.fromArray(.{ st.get(.strength), st.get(.agility), st.get(.constitution), st.get(.perception), st.get(.magic), st.get(.will) });
}

pub const State = enum(u8) { playing, dead, victory };

pub const HeroCombat = struct {
    attack: numeric.Attack = .{},
    armor: numeric.Armor = .{},
    crit: numeric.Crit = .{},
    speed: numeric.Speed = .{},
};

pub const HeroProgression = struct {
    level: u16 = 1,
    xp: u32 = 0,
    pending_points: u8 = 0,
};

pub const TalentState = struct {
    cooldowns: [3]u16 = .{ 0, 0, 0 },
};

pub const HeroSheet = struct {
    stats: numeric.PrimarySheet = .{},
    eff_stats: [6]f32 = .{ 0, 0, 0, 0, 0, 0 },
};

/// Player actor as a composition of small components. Position and class stay
/// identity-level; mutable numbers live in their own components.
pub const Hero = struct {
    class: Class = .warrior,
    difficulty: Difficulty = .normal,
    pos: GridPos = .{ .x = 6, .y = 11 },
    last_pos: GridPos = .{ .x = 6, .y = 11 },
    /// Recent positions, oldest first; used by the chronomancer rewind.
    history: [4]GridPos = .{ .{ .x = 6, .y = 11 }, .{ .x = 6, .y = 11 }, .{ .x = 6, .y = 11 }, .{ .x = 6, .y = 11 } },
    history_len: u8 = 0,
    sheet: HeroSheet = .{},
    vitals: numeric.Health = .{},
    resource: numeric.Resource = .{},
    resource_regen: numeric.Regen = .{},
    combat: HeroCombat = .{},
    progression: HeroProgression = .{},
    status: StatusSet = .{},
    talents: TalentState = .{},
};

pub const EnemyIdentity = struct {
    kind: u8 = 0,
    name: []const u8 = "骷髅兵",
};

pub const EnemyCombat = struct {
    attack: numeric.Attack = .{},
    armor: numeric.Armor = .{},
    speed: numeric.Speed = .{},
    range: u16 = 1,
};

/// Shared per-actor status component. Durations are counted in actor turns;
/// methods are the only place that interpret the fields, so Hero and Enemy
/// cannot drift on can-act / damage-scale semantics.
pub const StatusSet = struct {
    /// Bosses ignore hard control (stun); slow and damage-over-time still work.
    stun_immune: bool = false,
    stun_turns: u16 = 0,
    slow_turns: u16 = 0,
    buff_turns: u16 = 0,
    buff_pct: f32 = 0,
    burn_turns: u16 = 0,
    burn_damage: f32 = 0,
    burn_stacks: u8 = 0,
    vulnerable_turns: u16 = 0,
    vulnerable_pct: f32 = 0.20,
    guard_turns: u16 = 0,

    pub fn canAct(self: StatusSet) bool {
        return self.stun_turns == 0;
    }

    /// Returns true if this actor lost its turn; consumes one stun turn.
    pub fn consumeStun(self: *StatusSet) bool {
        if (self.stun_turns == 0) return false;
        self.stun_turns -= 1;
        return true;
    }

    pub fn consumeSlow(self: *StatusSet) void {
        if (self.slow_turns > 0) self.slow_turns -= 1;
    }

    pub fn attackScale(self: StatusSet) f32 {
        return if (self.buff_turns > 0) 1.0 + self.buff_pct else 1.0;
    }

    pub fn slowDamageScale(self: StatusSet) f32 {
        return if (self.slow_turns > 0) 0.55 else 1.0;
    }

    /// Returns the percentage that just expired, or 0.
    pub fn tickBuff(self: *StatusSet) f32 {
        if (self.buff_turns == 0) return 0;
        self.buff_turns -= 1;
        if (self.buff_turns != 0) return 0;
        const expired = self.buff_pct;
        self.buff_pct = 0;
        return expired;
    }

    pub fn applyVulnerable(self: *StatusSet, turns: u16) bool {
        if (turns == 0) return false;
        self.vulnerable_turns = @max(self.vulnerable_turns, turns);
        return true;
    }

    pub fn damageTakenScale(self: StatusSet) f32 {
        var scale: f32 = if (self.vulnerable_turns > 0) 1.0 + self.vulnerable_pct else 1.0;
        if (self.guard_turns > 0) scale *= 0.5;
        return scale;
    }

    pub fn tickVulnerable(self: *StatusSet) void {
        if (self.vulnerable_turns > 0) self.vulnerable_turns -= 1;
        if (self.guard_turns > 0) self.guard_turns -= 1;
    }

    pub fn applyStun(self: *StatusSet, turns: u16) bool {
        if (self.stun_immune or turns == 0) return false;
        self.stun_turns = @max(self.stun_turns, turns);
        return true;
    }

    pub fn applySlow(self: *StatusSet, turns: u16) bool {
        if (turns == 0) return false;
        self.slow_turns = @max(self.slow_turns, turns);
        return true;
    }

    pub fn applyBurn(self: *StatusSet, turns: u16, damage: f32) void {
        if (turns == 0 or damage <= 0) return;
        self.burn_turns = @max(self.burn_turns, turns);
        self.burn_damage = @max(self.burn_damage, damage);
        self.burn_stacks = @min(status_def.max_burn_stacks, if (self.burn_stacks == 0) 1 else self.burn_stacks + 1);
    }

    /// Clear all debuffs. Guard/buff are positive and survive a cleanse.
    pub fn cleanseDebuffs(self: *StatusSet) void {
        self.stun_turns = 0;
        self.slow_turns = 0;
        self.burn_turns = 0;
        self.burn_damage = 0;
        self.burn_stacks = 0;
        self.vulnerable_turns = 0;
    }

    /// Refresh duration without adding a stack. Used for enemy-applied burn on
    /// the hero so the player does not get a stacking attrition spiral.
    pub fn applyBurnFresh(self: *StatusSet, turns: u16, damage: f32) void {
        if (turns == 0 or damage <= 0) return;
        self.burn_turns = @max(self.burn_turns, turns);
        self.burn_damage = @max(self.burn_damage, damage);
        self.burn_stacks = 1;
    }

    /// Returns this tick's burn damage (damage × stacks) and consumes one turn.
    pub fn tickBurn(self: *StatusSet) f32 {
        if (self.burn_turns == 0) {
            self.burn_stacks = 0;
            return 0;
        }
        const stacks: f32 = @floatFromInt(@max(self.burn_stacks, 1));
        const dmg = self.burn_damage * (1.0 + (stacks - 1.0) * 0.5);
        self.burn_turns -= 1;
        if (self.burn_turns == 0) {
            self.burn_damage = 0;
            self.burn_stacks = 0;
        }
        return dmg;
    }
};

pub const Reward = struct {
    xp: u32 = 20,
};

pub const ActionState = struct {
    /// Action points; 100 points buys one turn. Accumulates speed each enemy
    /// phase and is never negative after subtraction.
    energy: i16 = 0,
    special_cd: u8 = 0,
};

/// Enemy actor as a composition of small components. Systems should take the
/// component they need rather than the whole aggregate.
pub const Enemy = struct {
    identity: EnemyIdentity = .{},
    affix: Affix = .none,
    pos: GridPos = .{ .x = 0, .y = 0 },
    vitals: numeric.Health = .{},
    life: numeric.LifeState = .{},
    combat: EnemyCombat = .{},
    status: StatusSet = .{},
    reward: Reward = .{},
    action: ActionState = .{},
};

/// Test/authoring helper: one flat literal -> component aggregate.
pub fn enemyFromParts(parts: anytype) Enemy {
    const T = @TypeOf(parts);
    return .{
        .identity = .{ .kind = parts.kind, .name = parts.name },
        .affix = if (@hasField(T, "affix")) parts.affix else .none,
        .pos = .{ .x = parts.pos.x, .y = parts.pos.y },
        .vitals = numeric.gaugeAt(numeric.Health, parts.hp_max, parts.hp),
        .life = .{ .alive = if (@hasField(T, "alive")) parts.alive else true },
        .combat = .{
            .attack = numeric.valueOf(numeric.Attack, parts.attack),
            .armor = numeric.valueOf(numeric.Armor, if (@hasField(T, "armor")) parts.armor else 0),
            .speed = numeric.valueOf(numeric.Speed, if (@hasField(T, "speed")) parts.speed else 100),
            .range = if (@hasField(T, "range")) parts.range else 1,
        },
        .status = .{
            .stun_immune = if (@hasField(T, "kind")) parts.kind == intent_mod.boss_kind else false,
            .stun_turns = if (@hasField(T, "stun_turns")) parts.stun_turns else 0,
            .slow_turns = if (@hasField(T, "slow_turns")) parts.slow_turns else 0,
        },
        .reward = .{ .xp = if (@hasField(T, "xp")) parts.xp else 0 },
        .action = .{ .energy = if (@hasField(T, "energy")) parts.energy else 0 },
    };
}

pub const LogLine = struct { text: [64]u8 = undefined, len: usize = 0 };

pub const Sim = struct {
    seed: u64,
    rng: std.Random.DefaultPrng,
    class: Class,
    difficulty: Difficulty = .normal,
    floor_mod: FloorMod = .none,
    hero: Hero,
    enemies: [max_enemies]Enemy = undefined,
    enemy_count: usize = 0,
    /// Content-owned definitions; index order is not kind order, so lookups
    /// match ai.kind. Tests default to the embedded table.
    enemy_table: []const content_mod.EnemyDef = &content_mod.builtin_enemies,
    blocked: [grid_w * grid_h]bool = @splat(false),
    stairs: GridPos = .{ .x = 10, .y = 2 },
    chests: [4]GridPos = .{ .{ .x = 2, .y = 2 }, .{ .x = 10, .y = 10 }, .{ .x = 2, .y = 10 }, .{ .x = 10, .y = 2 } },
    chest_alive: [4]bool = .{ false, false, false, false },
    chest_cursed: [4]bool = .{ false, false, false, false },
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
    boss_enraged: bool = false,
    boss_summoned: bool = false,
    shrine: GridPos = .{ .x = 0, .y = 0 },
    shrine_active: bool = false,
    shrine_used: bool = false,
    gold: u32 = 0,
    shop: GridPos = .{ .x = 0, .y = 0 },
    shop_active: bool = false,
    shop_used: bool = false,
    log_buf: [6]LogLine = .{ .{}, .{}, .{}, .{}, .{}, .{} },
    log_head: usize = 0,
    log_total: usize = 0,

    pub fn init(seed: u64, class: Class) Sim {
        return initWithDifficulty(seed, class, .normal);
    }

    pub fn initWithDifficulty(seed: u64, class: Class, difficulty: Difficulty) Sim {
        var s = Sim{
            .seed = seed,
            .rng = std.Random.DefaultPrng.init(seed),
            .class = class,
            .difficulty = difficulty,
            .hero = Hero{ .class = class },
        };
        s.reset(seed, class);
        return s;
    }

    pub fn reset(self: *Sim, seed: u64, class: Class) void {
        self.seed = seed;
        self.rng = std.Random.DefaultPrng.init(seed);
        self.class = class;
        self.hero = Hero{ .class = class, .sheet = .{ .stats = statsFromAttributes(attributes.baseStats(class)) } };
        self.floor = 1;
        self.turn = 1;
        self.kills = 0;
        self.chest_loot_events = 0;
        self.kill_loot_events = 0;
        self.aoe_armed = false;
        self.boss_enraged = false;
        self.boss_summoned = false;
        self.shrine_active = false;
        self.shrine_used = false;
        self.gold = 0;
        self.shop_active = false;
        self.shop_used = false;
        self.state = .playing;
        self.enemy_phase_pending = false;
        self.defer_enemies = false;
        self.log_head = 0;
        self.log_total = 0;
        self.recomputeHero();
        self.hero.vitals.val = self.hero.vitals.full;
        self.hero.resource.val = self.hero.resource.full;
        self.generateFloor();
        self.pushLog("进入第 1 层", .{});
    }

    /// Spend one pending level-up point. The caller must re-apply equipment
    /// modifiers (RunGame.rebuildMods) after this base-stat change.
    pub fn spendPoint(self: *Sim, stat: usize) bool {
        if (self.hero.progression.pending_points == 0 or stat >= 6) return false;
        if (stat >= 6) return false;
        self.hero.sheet.stats.add(@fromBackingInt(@intCast(stat)), 1);
        self.hero.progression.pending_points -= 1;
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
        const base = attributes.Stats.fromArray(self.hero.sheet.stats.toArray());
        const sheet = attributes.recompute(base, mods, self.class);
        self.hero.sheet.eff_stats = sheet.stats;
        self.hero.vitals.setFull(sheet.derived.hp_max);
        self.hero.resource.setFull(sheet.derived.resource_max);
        self.hero.combat.attack = numeric.valueOf(numeric.Attack, sheet.derived.attack);
        self.hero.combat.armor = numeric.valueOf(numeric.Armor, sheet.derived.armor);
        self.hero.combat.crit = numeric.valueOf(numeric.Crit, sheet.derived.crit);
        self.hero.combat.speed = numeric.valueOf(numeric.Speed, sheet.derived.speed);
        self.hero.resource_regen.val = sheet.derived.resource_per_turn;
        self.hero.resource_regen.base = sheet.derived.resource_per_turn;
        self.hero.vitals.set(self.hero.vitals.val);
        self.hero.resource.set(self.hero.resource.val);
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
            if (e.life.alive and e.pos.x == x and e.pos.y == y) return i;
        }
        return null;
    }

    /// Read-only preview of what `enemies[index]` will attempt on the next
    /// enemy phase. Does not mutate the sim and does not roll damage.
    pub fn intentFor(self: *const Sim, index: usize) ?intent_mod.EnemyIntent {
        if (index >= self.enemy_count) return null;
        const e = self.enemies[index];
        if (!e.life.alive) return null;
        var intent = intent_mod.previewWithAoePeriod(
            .{
                .width = grid_w,
                .height = grid_h,
                .blocked = self.blocked[0..],
            },
            .{
                .kind = e.identity.kind,
                .pos = .{ .x = e.pos.x, .y = e.pos.y },
                .range = e.combat.range,
                .attack = e.combat.attack.val,
                .stun_turns = e.status.stun_turns,
                .slow_turns = e.status.slow_turns,
                .alive = e.life.alive,
            },
            .{ .x = self.hero.pos.x, .y = self.hero.pos.y },
            self.turn +| 1,
            self.bossAoePeriod(),
        );
        if (intent.kind == .aoe and self.aoe_armed) {
            intent.target = .{ .x = self.aoe_target.x, .y = self.aoe_target.y };
        }
        if (intent.damage_preview > 0) {
            intent.damage_preview = combat.preview(.{ .raw = intent.damage_preview }, .{ .armor = self.hero.combat.armor.val });
        }
        return intent;
    }

    /// Fill `out` with one intent per living enemy, in enemy-array order.
    /// Returns the number written. Read-only.
    pub fn previewIntents(self: *const Sim, out: *[max_enemies]intent_mod.EnemyIntent) usize {
        var n: usize = 0;
        var i: usize = 0;
        while (i < self.enemy_count) : (i += 1) {
            if (!self.enemies[i].life.alive) continue;
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

    fn rollFloorMod(seed: u64, floor: u8) FloorMod {
        if (floor < 2) return .none;
        const h = seed ^ (@as(u64, floor) *% 0x94d049bb133111eb) ^ 0x9e3779b97f4a7c15;
        var rng = std.Random.DefaultPrng.init(h);
        const roll = rng.random().float(f32);
        if (roll < 0.34) return .ember;
        if (roll < 0.67) return .frost;
        return .miasma;
    }

    fn chooseShrine(self: *Sim) void {
        self.shrine_active = false;
        self.shrine_used = false;
        const entry = GridPos{ .x = self.map.entrance.x, .y = self.map.entrance.y };
        const stairs = GridPos{ .x = self.map.stairs.x, .y = self.map.stairs.y };
        var candidates: [grid_w * grid_h]GridPos = undefined;
        var n: usize = 0;
        var y: i32 = 0;
        while (y < grid_h) : (y += 1) {
            var x: i32 = 0;
            while (x < grid_w) : (x += 1) {
                const p = GridPos{ .x = x, .y = y };
                if (self.isBlocked(x, y)) continue;
                if (p.eql(entry) or p.eql(stairs)) continue;
                if (dist(p, entry) < 6) continue;
                if (self.featureAt(p)) continue;
                candidates[n] = p;
                n += 1;
            }
        }
        if (n == 0) return;
        var srng = std.Random.DefaultPrng.init(self.seed ^ (@as(u64, self.floor) *% 0x9e3779b97f4a7c15));
        self.shrine = candidates[srng.random().intRangeLessThan(usize, 0, n)];
        self.shrine_active = true;
    }

    fn featureAt(self: *const Sim, p: GridPos) bool {
        for (self.chests[0..self.chest_count]) |c| {
            if (c.eql(p)) return true;
        }
        for (self.traps[0..self.trap_count]) |t| {
            if (t.eql(p)) return true;
        }
        for (self.enemies[0..self.enemy_count]) |e| {
            if (e.pos.eql(p)) return true;
        }
        return false;
    }

    pub fn atShrine(self: *const Sim) bool {
        return self.shrine_active and !self.shrine_used and self.hero.pos.eql(self.shrine);
    }

    pub fn shrineMainLabel(self: *const Sim) []const u8 {
        return switch (attributes.profile(self.class).main_stat) {
            .strength => "力量",
            .magic => "魔力",
            else => "属性",
        };
    }

    pub fn useShrine(self: *Sim, choice: ShrineChoice) bool {
        if (!self.atShrine()) return false;
        const stat: attributes.StatKind = switch (choice) {
            .main_stat, .risk => attributes.profile(self.class).main_stat,
            .constitution => .constitution,
            .will => .will,
        };
        if (choice == .risk) {
            self.hero.sheet.stats.add(stat, 4);
            const con = self.hero.sheet.stats.get(.constitution);
            self.hero.sheet.stats.set(.constitution, @max(1, con - 2));
            self.recomputeHero();
            self.shrine_used = true;
            self.pushLog("SHRINE RISK", .{});
            return true;
        }
        self.hero.sheet.stats.add(stat, 2);
        self.recomputeHero();
        self.shrine_used = true;
        self.pushLog("SHRINE {s} +2", .{self.shrineMainLabel()});
        return true;
    }

    fn chooseShop(self: *Sim) void {
        self.shop_active = false;
        const entry = GridPos{ .x = self.map.entrance.x, .y = self.map.entrance.y };
        const stairs = GridPos{ .x = self.map.stairs.x, .y = self.map.stairs.y };
        self.shop_used = false;
        var candidates: [grid_w * grid_h]GridPos = undefined;
        var n: usize = 0;
        var y: i32 = 0;
        while (y < grid_h) : (y += 1) {
            var x: i32 = 0;
            while (x < grid_w) : (x += 1) {
                const p = GridPos{ .x = x, .y = y };
                if (self.isBlocked(x, y)) continue;
                if (p.eql(entry) or p.eql(stairs)) continue;
                if (self.shrine_active and p.eql(self.shrine)) continue;
                if (dist(p, self.hero.pos) < 4) continue;
                if (self.featureAt(p)) continue;
                candidates[n] = p;
                n += 1;
            }
        }
        if (n == 0) return;
        var srng = std.Random.DefaultPrng.init(self.seed ^ (@as(u64, self.floor) *% 0xbf58476d1ce4e5b9) ^ 0x517cc1b727220a95);
        self.shop = candidates[srng.random().intRangeLessThan(usize, 0, n)];
        self.shop_active = true;
    }

    pub fn atShop(self: *const Sim) bool {
        return self.shop_active and !self.shop_used and self.hero.pos.eql(self.shop);
    }

    pub fn useShop(self: *Sim, choice: ShopChoice) bool {
        if (!self.atShop()) return false;
        const cost: u32 = switch (choice) {
            .heal => shop_heal_cost,
            .power => shop_power_cost,
            .vitality => shop_vitality_cost,
            .cleanse => shop_cleanse_cost,
        };
        if (self.gold < cost) return false;
        switch (choice) {
            .heal => {
                self.hero.vitals.val = @min(self.hero.vitals.full, self.hero.vitals.val + 40);
                self.hero.resource.val = @min(self.hero.resource.full, self.hero.resource.val + 30);
                self.pushLog("SHOP 治疗", .{});
            },
            .power => {
                self.hero.sheet.stats.add(attributes.profile(self.class).main_stat, 2);
                self.recomputeHero();
                self.pushLog("SHOP 主属性 +2", .{});
            },
            .vitality => {
                self.hero.sheet.stats.add(.constitution, 2);
                self.recomputeHero();
                self.pushLog("SHOP 体质 +2", .{});
            },
            .cleanse => {
                self.hero.status.cleanseDebuffs();
                self.pushLog("SHOP 净化", .{});
            },
        }
        self.gold -= cost;
        self.shop_used = true;
        return true;
    }

    /// Deduct the blind-loot price. The Game owns the item roll so content
    /// stays out of Sim.
    pub fn buyShopLoot(self: *Sim) bool {
        if (!self.atShop() or self.gold < shop_loot_cost) return false;
        self.gold -= shop_loot_cost;
        self.shop_used = true;
        return true;
    }

    fn cursedChest(seed: u64, floor: u8, index: usize) bool {
        var rng = std.Random.DefaultPrng.init(seed ^ (@as(u64, floor) *% 0xa24baed4963ee407) ^ (@as(u64, index) *% 0x9fb21c651e98df25));
        return rng.random().float(f32) < 0.22;
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
        self.hero.history_len = 0;
        self.stairs = .{ .x = self.map.stairs.x, .y = self.map.stairs.y };

        self.chest_alive = .{ false, false, false, false };
        self.chest_cursed = .{ false, false, false, false };
        self.chest_count = 0;
        const cs = self.map.chestSlice();
        for (cs, 0..) |p, i| {
            if (i >= self.chests.len) break;
            self.chests[i] = .{ .x = p.x, .y = p.y };
            self.chest_alive[i] = true;
            self.chest_count += 1;
        }
        for (self.chests, 0..) |_, i| {
            self.chest_cursed[i] = cursedChest(self.seed, self.floor, i);
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

        self.floor_mod = rollFloorMod(self.seed, self.floor);
        const kinds: []const u8 = switch (self.floor) {
            1 => &.{ 0, 1, 0, 0, 1, 0, 0, 1 },
            2 => &.{ 3, 0, 6, 2, 4, 1, 6, 3 },
            else => &.{ 5, 3, 6, 0, 1, 2, 6, 4 },
        };
        const max_spawns: usize = dungeon_mod.spawnsForFloor(self.floor);
        for (self.map.spawnSlice(), 0..) |p, i| {
            if (i >= max_spawns) break;
            self.spawnEnemyAt(kinds[i % kinds.len], .{ .x = p.x, .y = p.y });
        }
        self.chooseShrine();
        self.chooseShop();
        self.pushLog("第 {d} 层：{d} 个敌人", .{ self.floor, self.enemy_count });
        if (self.floor_mod != .none) self.pushLog("MOD {s}", .{self.floor_mod.label()});
    }

    pub fn setEnemyDefs(self: *Sim, defs: []const content_mod.EnemyDef) void {
        if (defs.len > 0) self.enemy_table = defs;
    }

    /// Deterministic affix roll; does not consume the run RNG, so loot order
    /// and enemy turns stay stable when content changes.
    fn rollAffix(seed: u64, floor: u8, kind: u8, pos: GridPos) Affix {
        const h = seed ^
            (@as(u64, floor) *% 0x9e3779b97f4a7c15) ^
            (@as(u64, kind) *% 0xbf58476d1ce4e5b9) ^
            (@as(u64, @intCast(@max(0, pos.x))) *% 0x94d049bb133111eb) ^
            (@as(u64, @intCast(@max(0, pos.y))) *% 0xd6e8feb86659fd93);
        var rng = std.Random.DefaultPrng.init(h);
        const roll = rng.random().float(f32);
        if (roll < 0.05) return .swift;
        if (roll < 0.10) return .armored;
        if (roll < 0.15) return .vampiric;
        if (roll < 0.19) return .explosive;
        if (roll < 0.21 and floor >= 3) return .split;
        return .none;
    }

    fn enemyDefForKind(self: *const Sim, kind: u8) content_mod.EnemyDef {
        for (self.enemy_table) |*def| {
            if (def.ai.kind == kind) return def.*;
        }
        return self.enemy_table[0];
    }

    fn spawnEnemyAt(self: *Sim, kind: u8, pos: GridPos) void {
        if (self.enemy_count >= max_enemies) return;
        if (self.isBlocked(pos.x, pos.y)) return;
        if (self.enemyAt(pos.x, pos.y) != null) return;
        if (pos.x == self.hero.pos.x and pos.y == self.hero.pos.y) return;
        const def = self.enemyDefForKind(kind);
        const idx = self.enemy_count;
        const hp = def.combat.hp * self.difficulty.hpScale();
        const dmg = def.combat.damage * self.difficulty.damageScale();
        const affix: Affix = if (def.ai.kind == intent_mod.boss_kind or self.floor < 2) .none else rollAffix(self.seed, self.floor, def.ai.kind, pos);
        const speed = (@as(f32, @floatFromInt(def.combat.speed)) + (if (affix == .swift) @as(f32, 15) else 0)) * self.floor_mod.enemySpeedScale();
        const armor = def.combat.armor + (if (affix == .armored) @as(f32, 3) else 0);
        self.enemies[idx] = .{
            .identity = .{ .kind = def.ai.kind, .name = def.name },
            .affix = affix,
            .pos = pos,
            .vitals = numeric.gaugeFull(numeric.Health, hp),
            .combat = .{
                .attack = numeric.valueOf(numeric.Attack, dmg),
                .armor = numeric.valueOf(numeric.Armor, armor),
                .speed = numeric.valueOf(numeric.Speed, speed),
                .range = def.combat.attack_range,
            },
            .reward = .{ .xp = def.loot.xp },
            .status = .{ .stun_immune = def.ai.kind == intent_mod.boss_kind },
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
            if (e.life.alive and e.identity.kind == intent_mod.boss_kind) return true;
        }
        return false;
    }

    pub fn isFinalFloor(self: *const Sim) bool {
        return self.floor >= self.floors;
    }

    /// The final-floor boss keeps the stairs closed until it dies.
    pub fn stairsSealed(self: *const Sim) bool {
        return self.isFinalFloor() and self.hasLivingBoss();
    }

    fn pushHistory(self: *Sim) void {
        if (self.hero.history_len < self.hero.history.len) {
            self.hero.history[self.hero.history_len] = self.hero.pos;
            self.hero.history_len += 1;
            return;
        }
        var i: usize = 1;
        while (i < self.hero.history.len) : (i += 1) {
            self.hero.history[i - 1] = self.hero.history[i];
        }
        self.hero.history[self.hero.history.len - 1] = self.hero.pos;
    }

    fn rewindTarget(self: *const Sim) ?GridPos {
        if (self.hero.history_len == 0) return null;
        var i: usize = 0;
        while (i < self.hero.history_len) : (i += 1) {
            const p = self.hero.history[i];
            if (self.isFree(p.x, p.y)) return p;
        }
        return null;
    }

    pub fn move(self: *Sim, dx: i32, dy: i32) bool {
        if (self.state != .playing) return false;
        if (dx == 0 and dy == 0) return false;
        const nx = self.hero.pos.x + dx;
        const ny = self.hero.pos.y + dy;
        if (self.isBlocked(nx, ny)) return false;
        if (nx == self.stairs.x and ny == self.stairs.y and self.stairsSealed()) {
            self.pushLog("深渊守卫封印了楼梯", .{});
            return false;
        }
        if (self.enemyAt(nx, ny)) |idx| {
            self.playerAttack(idx, 1.0);
            self.endTurn();
            return true;
        }
        self.pushHistory();
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
            if (e.life.alive and dist(e.pos, self.hero.pos) <= 6) danger = true;
        }
        if (!danger) {
            self.hero.vitals.val = @min(self.hero.vitals.full, self.hero.vitals.val + self.hero.vitals.full * 0.08);
            self.hero.resource.val = @min(self.hero.resource.full, self.hero.resource.val + self.hero.resource.full * 0.15);
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
            if (self.chest_cursed[i]) {
                const dmg = self.hero.vitals.full * 0.10;
                self.hero.vitals.val = @max(0, self.hero.vitals.val - dmg);
                _ = self.hero.status.applyVulnerable(1);
                self.gold +|= 25;
                self.chest_loot_events += 1;
                self.pushLog("诅咒宝箱 -{d:.0}", .{dmg});
                return;
            }
            const heal = @min(self.hero.vitals.full - self.hero.vitals.val, 25);
            self.hero.vitals.val += heal;
            self.chest_loot_events += 1;
            self.gold +|= 10;
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
            self.hero.vitals.val = @max(0, self.hero.vitals.val - dmg);
            self.pushLog("触发陷阱 -{d:.0} 生命", .{dmg});
            if (self.hero.vitals.val <= 0) self.state = .dead;
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
        self.hero.vitals.val = @min(self.hero.vitals.full, self.hero.vitals.val + self.hero.vitals.full * 0.25);
        self.hero.resource.val = @min(self.hero.resource.full, self.hero.resource.val + self.hero.resource.full * 0.5);
        self.turn += 1;
        self.generateFloor();
        if (self.stairsSealed()) self.pushLog("深渊守卫封印了楼梯", .{});
        self.armBossAoe();
    }

    fn bossAoePeriod(_: *const Sim) u32 {
        return intent_mod.boss_aoe_period;
    }

    fn bossAoeDue(self: *const Sim, turn: u32) bool {
        const period = self.bossAoePeriod();
        return turn != 0 and period != 0 and turn % period == 0;
    }

    fn armBossAoe(self: *Sim) void {
        if (self.aoe_armed) return;
        if (!self.bossAoeDue(self.turn +| 1)) return;
        for (self.enemies[0..self.enemy_count]) |e| {
            if (e.life.alive and e.identity.kind == intent_mod.boss_kind) {
                self.aoe_target = self.hero.pos;
                self.aoe_armed = true;
                return;
            }
        }
    }

    /// Damage-over-time tick after the enemy phase. Burn ignores armor and
    /// can kill either side; enemy deaths reuse the normal kill/reward path.
    fn tickStatusDamage(self: *Sim) void {
        if (self.state != .playing) return;
        const hero_dmg = self.hero.status.tickBurn();
        if (hero_dmg > 0) {
            self.hero.vitals.val = @max(0, self.hero.vitals.val - hero_dmg);
            self.pushLog("灼烧 -{d:.0}", .{hero_dmg});
            if (self.hero.vitals.val <= 0) {
                self.state = .dead;
                return;
            }
        }
        var i: usize = 0;
        while (i < self.enemy_count) : (i += 1) {
            const e = &self.enemies[i];
            if (!e.life.alive) continue;
            const dmg = e.status.tickBurn();
            if (dmg <= 0) continue;
            e.vitals.val -= dmg;
            self.checkBossEnrage(i);
            self.checkBossSummon(i);
            if (e.vitals.val <= 0) self.killEnemy(i);
        }
    }

    fn endTurn(self: *Sim) void {
        if (self.state != .playing) return;
        // start of the next player turn
        self.turn += 1;
        for (&self.hero.talents.cooldowns) |*cd| {
            if (cd.* > 0) cd.* -= 1;
        }
        _ = self.hero.status.tickBuff();
        var vi: usize = 0;
        while (vi < self.enemy_count) : (vi += 1) {
            self.enemies[vi].status.tickVulnerable();
        }
        self.hero.status.tickVulnerable();
        self.hero.resource.val = @min(self.hero.resource.full, self.hero.resource.val + self.hero.resource_regen.val * self.floor_mod.resourceScale());
        if (self.hero.vitals.val <= 0) {
            self.state = .dead;
            return;
        }
        if (self.defer_enemies) {
            self.enemy_phase_pending = true;
            return;
        }
        self.enemyPhase();
        self.tickStatusDamage();
        self.armBossAoe();
        if (self.hero.vitals.val <= 0) self.state = .dead;
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
        self.tickStatusDamage();
        self.armBossAoe();
        if (self.hero.vitals.val <= 0) self.state = .dead;
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
            if (!self.enemies[i].life.alive) continue;
            order[n] = i;
            n += 1;
        }
        // insertion sort: fast first, stable
        var a: usize = 1;
        while (a < n) : (a += 1) {
            const key = order[a];
            var b = a;
            while (b > 0 and self.enemies[order[b - 1]].combat.speed.val < self.enemies[key].combat.speed.val) : (b -= 1) {
                order[b] = order[b - 1];
            }
            order[b] = key;
        }
        for (order[0..n]) |idx| {
            const e = &self.enemies[idx];
            if (!e.life.alive) continue;
            // 100 action points = one action. Cap the bank at 200 so a long
            // stun cannot save up more than two actions.
            e.action.energy = @min(@as(i16, 200), e.action.energy + @as(i16, @intFromFloat(e.combat.speed.val)));
            var acted: u8 = 0;
            while (e.action.energy >= 100 and acted < 2) {
                e.action.energy -= 100;
                if (!e.life.alive) break;
                if (self.hero.vitals.val <= 0) break;
                self.enemyAct(idx);
                acted += 1;
            }
        }
    }

    fn enemyAct(self: *Sim, idx: usize) void {
        const e = &self.enemies[idx];
        if (!e.life.alive) return;
        if (e.status.consumeStun()) return;
        e.status.consumeSlow();
        if (e.action.special_cd > 0) e.action.special_cd -= 1;
        if (e.identity.kind == intent_mod.boss_kind and self.aoe_armed and self.bossAoeDue(self.turn)) {
            self.aoe_armed = false;
            if (@as(f32, @floatFromInt(dist(self.hero.pos, self.aoe_target))) <= intent_mod.boss_aoe_radius) {
                const raw = e.combat.attack.val * intent_mod.boss_aoe_damage_scale * e.status.slowDamageScale();
                const dmg = combat.resolve(.{ .raw = raw }, .{ .armor = self.hero.combat.armor.val }).amount * self.hero.status.damageTakenScale();
                self.hero.vitals.val = @max(0, self.hero.vitals.val - dmg);
                self.hero.status.applyBurnFresh(2, e.combat.attack.val * 0.20 * self.floor_mod.burnScale());
                _ = self.hero.status.applyVulnerable(2);
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
        if (e.identity.kind == 2 and d == 2 and los and e.action.special_cd == 0) {
            e.action.special_cd = 2;
            const raw = e.combat.attack.val * 0.4;
            const dmg = combat.resolve(.{ .raw = raw }, .{ .armor = self.hero.combat.armor.val }).amount;
            self.hero.vitals.val = @max(0, self.hero.vitals.val - dmg);
            self.pushLog("石魔像 震地 -{d:.0}", .{dmg});
            return;
        }
        if ((e.identity.kind == 0 or e.identity.kind == 3) and e.vitals.val < e.vitals.full * 0.5 and e.action.special_cd == 0) {
            e.status.guard_turns = 1;
            e.action.special_cd = 4;
            self.pushLog("{s} 举盾", .{e.identity.name});
            return;
        }
        if ((e.identity.kind == 1 or e.identity.kind == 4) and d <= e.combat.range and los and e.action.special_cd == 0) {
            const raw = e.combat.attack.val * 0.7;
            const dmg = combat.resolve(.{ .raw = raw }, .{ .armor = self.hero.combat.armor.val }).amount;
            self.hero.vitals.val = @max(0, self.hero.vitals.val - dmg);
            e.vitals.set(@min(e.vitals.full, e.vitals.val + dmg * 0.5));
            e.action.special_cd = 3;
            self.pushLog("幽魂 汲取 -{d:.0}", .{dmg});
            return;
        }
        if (d <= 1 or (d <= e.combat.range and los)) {
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
        const e = &self.enemies[idx];
        var raw = e.combat.attack.val * 0.72;
        raw *= e.status.slowDamageScale();
        const dmg = combat.resolve(.{ .raw = raw }, .{ .armor = self.hero.combat.armor.val }).amount * self.hero.status.damageTakenScale();
        self.hero.vitals.val = @max(0, self.hero.vitals.val - dmg);
        if (e.affix == .vampiric and dmg > 0) e.vitals.set(e.vitals.val + dmg * 0.20);
        if (e.identity.kind == 6 and dmg > 0) {
            self.hero.status.applyBurnFresh(2, e.combat.attack.val * 0.10 * self.floor_mod.burnScale());
        }
        if (e.identity.kind == 2 and dmg > 0) {
            _ = self.hero.status.applyVulnerable(1);
        }
        self.pushLog("{s} 造成 {d:.0} 伤害", .{ e.identity.name, dmg });
    }

    pub fn playerAttack(self: *Sim, idx: usize, mult: f32) void {
        const e = &self.enemies[idx];
        if (!e.life.alive) return;
        var raw = self.hero.combat.attack.val * mult;
        raw *= self.hero.status.attackScale();
        const crit = self.rng.random().float(f32) < self.hero.combat.crit.val;
        const result = combat.resolve(.{ .raw = raw, .crit = crit }, .{ .armor = e.combat.armor.val });
        const dealt = result.amount * e.status.damageTakenScale();
        e.vitals.val -= dealt;
        self.pushLog("命中 {s} {d:.0}{s}", .{ e.identity.name, dealt, if (result.crit) " 暴击" else "" });
        self.checkBossEnrage(idx);
        self.checkBossSummon(idx);
        if (e.vitals.val <= 0) self.killEnemy(idx);
    }

    /// Boss phase: at half HP it calls one skeleton once. Uses the same
    /// spawn path as floor generation so difficulty/affixes apply.
    fn checkBossSummon(self: *Sim, idx: usize) void {
        if (self.boss_summoned) return;
        const e = &self.enemies[idx];
        if (!e.life.alive or e.identity.kind != intent_mod.boss_kind) return;
        if (e.vitals.val <= 0 or e.vitals.val > e.vitals.full * 0.5) return;
        self.boss_summoned = true;
        var summoned: usize = 0;
        var oy: i32 = -2;
        while (oy <= 2 and summoned < 1) : (oy += 1) {
            var ox: i32 = -2;
            while (ox <= 2 and summoned < 1) : (ox += 1) {
                if (ox == 0 and oy == 0) continue;
                const p = GridPos{ .x = e.pos.x + ox, .y = e.pos.y + oy };
                if (self.isBlocked(p.x, p.y) or self.enemyAt(p.x, p.y) != null) continue;
                const before = self.enemy_count;
                self.spawnEnemyAt(0, p);
                if (self.enemy_count > before) {
                    self.enemies[before].vitals.val *= 0.6;
                    // Enter stunned so the player gets one turn to react.
                    _ = self.enemies[before].status.applyStun(1);
                    summoned += 1;
                }
            }
        }
        self.pushLog("深渊守卫 召唤骷髅", .{});
    }

    /// Boss phase 2: once below 35% HP it gains 15% attack and 10 speed.
    /// The AOE cadence stays unchanged so the phase is a damage check, not a wipe.
    fn checkBossEnrage(self: *Sim, idx: usize) void {
        if (self.boss_enraged) return;
        const e = &self.enemies[idx];
        if (!e.life.alive or e.identity.kind != intent_mod.boss_kind) return;
        if (e.vitals.val <= 0 or e.vitals.val > e.vitals.full * 0.35) return;
        self.boss_enraged = true;
        e.combat.attack = numeric.valueOf(numeric.Attack, e.combat.attack.val * 1.15);
        e.combat.speed = numeric.valueOf(numeric.Speed, e.combat.speed.val + 10);
        self.pushLog("深渊守卫 狂暴", .{});
    }

    fn killEnemy(self: *Sim, idx: usize) void {
        const e = &self.enemies[idx];
        if (!e.life.alive) return;
        e.life.alive = false;
        e.vitals.val = 0;
        if (e.identity.kind == intent_mod.boss_kind) self.aoe_armed = false;
        self.kills += 1;
        self.gold +|= 5 + @as(u32, e.identity.kind) * 2 + @as(u32, self.floor) * 3;
        self.kill_loot_events += 1;
        if (e.affix == .split and self.enemy_count < max_enemies and self.state == .playing) {
            const dirs = [_]GridPos{
                .{ .x = 1, .y = 0 },
                .{ .x = -1, .y = 0 },
                .{ .x = 0, .y = 1 },
                .{ .x = 0, .y = -1 },
            };
            for (dirs) |d| {
                const p = GridPos{ .x = e.pos.x + d.x, .y = e.pos.y + d.y };
                if (!self.isFree(p.x, p.y)) continue;
                if (p.x == self.hero.pos.x and p.y == self.hero.pos.y) continue;
                if (self.enemyAt(p.x, p.y) != null) continue;
                const child = &self.enemies[self.enemy_count];
                child.* = e.*;
                child.pos = p;
                child.affix = .none;
                child.vitals = numeric.gaugeAt(numeric.Health, e.vitals.full, e.vitals.full * 0.20);
                child.life.alive = true;
                child.action.energy = 0;
                child.status = .{ .stun_turns = 1 };
                self.enemy_count += 1;
                self.pushLog("SPLIT ECHO", .{});
                break;
            }
        }
        if (e.affix == .explosive and self.state == .playing) {
            const dx = @abs(e.pos.x - self.hero.pos.x);
            const dy = @abs(e.pos.y - self.hero.pos.y);
            if (dx <= 1 and dy <= 1) {
                const raw = e.combat.attack.val * 0.60;
                const blast = combat.resolve(.{ .raw = raw }, .{ .armor = self.hero.combat.armor.val }).amount * self.hero.status.damageTakenScale();
                self.hero.vitals.val = @max(0, self.hero.vitals.val - blast);
                self.pushLog("VOLATILE -{d:.0}", .{blast});
                if (self.hero.vitals.val <= 0) self.state = .dead;
            }
        }
        self.pushLog("击杀 {s} +{d}XP", .{ e.identity.name, e.reward.xp });
        self.hero.progression.xp += e.reward.xp;
        while (self.hero.progression.xp >= 100 * self.hero.progression.level and self.hero.progression.level < 50) {
            self.hero.progression.xp -= 100 * self.hero.progression.level;
            self.hero.progression.level += 1;
            if (self.auto_allocate) {
                switch (self.class) {
                    .warrior => self.hero.sheet.stats.add(.strength, 1),
                    .mage, .chronomancer => self.hero.sheet.stats.add(.magic, 1),
                }
            } else {
                self.hero.progression.pending_points +|= 1;
            }
            self.recomputeHero();
            self.hero.vitals.val = self.hero.vitals.full;
            self.hero.resource.val = self.hero.resource.full;
            if (self.hero.progression.pending_points > 0) {
                self.pushLog("升级到 {d} 级 +1 属性点", .{self.hero.progression.level});
            } else {
                self.pushLog("升级到 {d} 级", .{self.hero.progression.level});
            }
        }
        var any = false;
        for (self.enemies[0..self.enemy_count]) |en| {
            if (en.life.alive) any = true;
        }
        if (!any and self.isFinalFloor()) self.state = .victory;
    }

    pub fn nearestEnemy(self: *const Sim, max_range: i32) ?usize {
        var best: ?usize = null;
        var best_d: i32 = 999;
        var i: usize = 0;
        while (i < self.enemy_count) : (i += 1) {
            const e = self.enemies[i];
            if (!e.life.alive) continue;
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
                if (e.life.alive and dist(e.pos, self.hero.pos) <= max_range) return p;
            }
        }
        return self.nearestEnemy(max_range);
    }

    pub fn useTalentOn(self: *Sim, i: usize, target: ?usize) bool {
        if (self.state != .playing or i >= 3) return false;
        if (self.hero.talents.cooldowns[i] > 0) return false;
        const cost = self.talentCost(i);
        if (self.hero.resource.val < @as(f32, @floatFromInt(cost))) return false;
        switch (self.class) {
            .warrior => {
                if (i == 2) {
                    self.hero.resource.val -= @floatFromInt(cost);
                    self.hero.talents.cooldowns[i] = self.talentCooldown(i);
                    self.hero.status.buff_turns = 3;
                    self.hero.status.buff_pct = 0.30;
                    self.pushLog("战吼：攻击 +30%", .{});
                    self.endTurn();
                    return true;
                }
                const idx = self.pickTarget(if (i == 0) 1 else 4, target) orelse return false;
                self.hero.resource.val -= @floatFromInt(cost);
                self.hero.talents.cooldowns[i] = self.talentCooldown(i);
                if (i == 0) {
                    self.playerAttack(idx, 2.2);
                } else {
                    self.playerAttack(idx, 1.5);
                    if (self.enemies[idx].life.alive) _ = self.enemies[idx].status.applyVulnerable(2);
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
                            self.pushHistory();
                            self.hero.last_pos = self.hero.pos;
                            self.hero.pos = .{ .x = x, .y = y };
                            self.hero.resource.val -= @floatFromInt(cost);
                            self.hero.talents.cooldowns[i] = self.talentCooldown(i);
                            self.pushLog("闪现", .{});
                            self.endTurn();
                            return true;
                        }
                    }
                    return false;
                }
                const idx = self.pickTarget(if (i == 0) 5 else 4, target) orelse return false;
                self.hero.resource.val -= @floatFromInt(cost);
                self.hero.talents.cooldowns[i] = self.talentCooldown(i);
                if (i == 0) {
                    self.aoeAttack(idx, 2.35, 1.5);
                } else {
                    self.playerAttack(idx, 1.8);
                    if (!self.enemies[idx].status.applySlow(2)) self.pushLog("Boss 免疫减速", .{});
                }
                self.endTurn();
                return true;
            },
            .chronomancer => {
                if (i == 2) {
                    const back = self.rewindTarget() orelse return false;
                    self.hero.resource.val -= @floatFromInt(cost);
                    self.hero.talents.cooldowns[i] = self.talentCooldown(i);
                    self.pushHistory();
                    self.hero.last_pos = self.hero.pos;
                    self.hero.pos = back;
                    self.hero.status.cleanseDebuffs();
                    self.hero.vitals.val = @min(self.hero.vitals.full, self.hero.vitals.val + self.hero.vitals.full * 0.08);
                    self.hero.history_len = 0;
                    self.pushLog("时间回溯", .{});
                    self.endTurn();
                    return true;
                }
                const idx = self.pickTarget(if (i == 0) 5 else 4, target) orelse return false;
                self.hero.resource.val -= @floatFromInt(cost);
                self.hero.talents.cooldowns[i] = self.talentCooldown(i);
                if (i == 0) {
                    self.playerAttack(idx, 2.0);
                    if (self.enemies[idx].life.alive and !self.enemies[idx].status.applySlow(2)) self.pushLog("Boss 免疫减速", .{});
                } else {
                    self.playerAttack(idx, 1.2);
                    if (self.enemies[idx].life.alive) _ = self.enemies[idx].status.applySlow(2);
                    if (!self.enemies[idx].status.applyStun(2)) {
                        if (self.enemies[idx].life.alive) {
                            self.playerAttack(idx, 0.5);
                            self.pushLog("Boss 抗眩晕 减速+反噬", .{});
                        }
                    }
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
            if (!e.life.alive) continue;
            const d = dist(e.pos, center);
            if (d > @as(i32, @intFromFloat(radius))) continue;
            self.playerAttack(i, if (d == 0) mult else mult * 0.6);
            if (!e.life.alive) continue;
            const burn = self.hero.combat.attack.val * 0.10 * self.floor_mod.burnScale();
            e.status.applyBurn(5, burn);
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
        if (self.hero.talents.cooldowns[i] > 0) return false;
        const cost = self.talentCost(i);
        if (self.hero.resource.val < @as(f32, @floatFromInt(cost))) return false;
        if (self.isBlocked(cell.x, cell.y)) return false;
        if (dist(self.hero.pos, cell) > 5) return false;
        if (!self.map.lineOfSightTo(
            .{ .x = self.hero.pos.x, .y = self.hero.pos.y },
            .{ .x = cell.x, .y = cell.y },
            null,
        )) return false;
        self.hero.resource.val -= @floatFromInt(cost);
        self.hero.talents.cooldowns[i] = self.talentCooldown(i);
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

test "run sim: status set interprets stun/slow/buff consistently" {
    var st = StatusSet{};
    try std.testing.expect(st.canAct());
    st.stun_turns = 1;
    try std.testing.expect(!st.canAct());
    try std.testing.expect(st.consumeStun());
    try std.testing.expect(st.canAct());
    try std.testing.expect(!st.consumeStun());

    st.slow_turns = 1;
    try std.testing.expectApproxEqAbs(@as(f32, 0.55), st.slowDamageScale(), 0.0001);
    st.consumeSlow();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), st.slowDamageScale(), 0.0001);

    st.buff_turns = 2;
    st.buff_pct = 0.30;
    try std.testing.expectApproxEqAbs(@as(f32, 1.3), st.attackScale(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), st.tickBuff(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.30), st.tickBuff(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), st.attackScale(), 0.0001);

    st.applyBurn(2, 5);
    try std.testing.expectApproxEqAbs(@as(f32, 5), st.tickBurn(), 0.0001);
    st.applyBurn(2, 5);
    st.applyBurn(2, 5);
    try std.testing.expectEqual(@as(u8, 3), st.burn_stacks);
    try std.testing.expectApproxEqAbs(@as(f32, 10), st.tickBurn(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), st.tickBurn(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), st.tickBurn(), 0.0001);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), st.damageTakenScale(), 0.0001);
    try std.testing.expect(st.applyVulnerable(2));
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), st.damageTakenScale(), 0.0001);
    st.tickVulnerable();
    st.tickVulnerable();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), st.damageTakenScale(), 0.0001);

    var boss = StatusSet{ .stun_immune = true };
    try std.testing.expect(!boss.applyStun(2));
    try std.testing.expect(boss.applySlow(2));
    try std.testing.expectEqual(@as(u16, 2), boss.slow_turns);
    boss.applyBurn(3, 9);
    try std.testing.expectEqual(@as(u16, 3), boss.burn_turns);
    try std.testing.expectApproxEqAbs(@as(f32, 9), boss.tickBurn(), 0.0001);
}

test "run sim: adjacent enemy acts on wait" {
    var s = Sim.init(11, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
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
    });
    const hp = s.hero.vitals.val;
    _ = s.wait();
    try std.testing.expect(s.hero.vitals.val < hp);
    try std.testing.expect(s.turn > 1);
}

test "run sim: warrior talent spends resource and starts cooldown" {
    var s = Sim.init(13, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
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
    });
    const res = s.hero.resource.val;
    try std.testing.expect(s.useTalent(0));
    try std.testing.expect(s.hero.resource.val < res);
    try std.testing.expect(s.hero.talents.cooldowns[0] > 0);
}

test "run sim: stepping on stairs advances the floor" {
    var s = Sim.init(17, .mage);
    s.hero.pos = .{ .x = s.stairs.x, .y = s.stairs.y - 1 };
    if (s.canMove(0, 1)) {
        _ = s.move(0, 1);
        try std.testing.expect(s.floor >= 2);
    }
}

test "run sim: floor modifiers are deterministic and scale the right knobs" {
    var a = Sim.init(88, .warrior);
    a.floor = 2;
    a.generateFloor();
    var b = Sim.init(88, .warrior);
    b.floor = 2;
    b.generateFloor();
    try std.testing.expectEqual(a.floor_mod, b.floor_mod);
    try std.testing.expect(a.floor_mod != .none);

    try std.testing.expectApproxEqAbs(@as(f32, 1.5), FloorMod.ember.burnScale(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.90), FloorMod.frost.enemySpeedScale(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), FloorMod.miasma.resourceScale(), 0.001);
}

test "run sim: abyss wraith ranged hit applies burn" {
    var s = Sim.init(79, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 6,
        .name = "深渊幽魂",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 65,
        .hp_max = 65,
        .attack = 9,
        .armor = 2,
        .speed = 100,
        .range = 4,
        .xp = 45,
        .energy = 100,
    });
    _ = s.wait();
    try std.testing.expect(s.hero.status.burn_turns > 0);
}

test "run sim: split spawns a 40% echo once" {
    var s = Sim.init(80, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 1,
        .hp_max = 100,
        .attack = 10,
        .armor = 0,
        .speed = 100,
        .range = 1,
        .xp = 10,
        .affix = .split,
        .energy = 0,
    });
    s.playerAttack(0, 3.0);
    try std.testing.expect(!s.enemies[0].life.alive);
    try std.testing.expectEqual(@as(usize, 2), s.enemy_count);
    try std.testing.expect(s.enemies[1].life.alive);
    try std.testing.expectApproxEqAbs(@as(f32, 20), s.enemies[1].vitals.val, 0.01);
}

test "run sim: volatile explodes when killed next to the hero" {
    var s = Sim.init(79, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 1,
        .hp_max = 1,
        .attack = 20,
        .armor = 0,
        .speed = 100,
        .range = 1,
        .xp = 10,
        .affix = .explosive,
        .energy = 0,
    });
    const hp = s.hero.vitals.val;
    s.playerAttack(0, 3.0);
    try std.testing.expect(!s.enemies[0].life.alive);
    try std.testing.expect(s.hero.vitals.val < hp);
}

test "run sim: affixes are deterministic and vampiric heals on hit" {
    var a = Sim.init(77, .warrior);
    var b = Sim.init(77, .warrior);
    for (a.enemies[0..a.enemy_count], b.enemies[0..b.enemy_count]) |ea, eb| {
        try std.testing.expectEqual(ea.affix, eb.affix);
    }

    var s = Sim.init(78, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 40,
        .hp_max = 70,
        .attack = 10,
        .armor = 0,
        .speed = 100,
        .range = 1,
        .xp = 20,
        .affix = .vampiric,
        .energy = 100,
    });
    _ = s.wait();
    try std.testing.expect(s.enemies[0].vitals.val > 40);
}

test "run sim: low-hp skeleton guards and takes half damage" {
    var s = Sim.init(85, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 20,
        .hp_max = 56,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
        .energy = 100,
    });
    s.enemyAct(0);
    try std.testing.expect(s.enemies[0].status.guard_turns > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), s.enemies[0].status.damageTakenScale(), 0.001);
}

test "run sim: wraith drain damages and heals itself" {
    var s = Sim.init(84, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 1,
        .name = "幽魂",
        .pos = .{ .x = s.hero.pos.x + 2, .y = s.hero.pos.y },
        .hp = 10,
        .hp_max = 44,
        .attack = 10,
        .armor = 1,
        .speed = 110,
        .range = 3,
        .xp = 25,
        .energy = 100,
    });
    const hp = s.hero.vitals.val;
    s.enemyAct(0);
    try std.testing.expect(s.hero.vitals.val < hp);
    try std.testing.expect(s.enemies[0].vitals.val > 10);
    try std.testing.expectEqual(@as(u8, 3), s.enemies[0].action.special_cd);
}

test "run sim: golem shockwave hits at range two" {
    var s = Sim.init(83, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 2,
        .name = "石魔像",
        .pos = .{ .x = s.hero.pos.x + 2, .y = s.hero.pos.y },
        .hp = 140,
        .hp_max = 140,
        .attack = 12,
        .armor = 9,
        .speed = 70,
        .range = 1,
        .xp = 40,
        .energy = 100,
    });
    const hp = s.hero.vitals.val;
    s.enemyAct(0);
    try std.testing.expect(s.hero.vitals.val < hp);
}

test "run sim: golem hit applies vulnerable to hero" {
    var s = Sim.init(82, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 2,
        .name = "石魔像",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 140,
        .hp_max = 140,
        .attack = 12,
        .armor = 9,
        .speed = 70,
        .range = 1,
        .xp = 40,
        .energy = 100,
    });
    _ = s.wait();
    try std.testing.expect(s.hero.status.vulnerable_turns > 0);
}

test "run sim: warrior charge applies vulnerable" {
    var s = Sim.init(81, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 200,
        .hp_max = 200,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
    });
    s.hero.resource.val = 100;
    try std.testing.expect(s.useTalent(1));
    try std.testing.expect(s.enemies[0].status.vulnerable_turns > 0);
}

test "run sim: cursed chest damages and pays more gold" {
    var s = Sim.init(95, .warrior);
    s.chest_count = 1;
    s.chest_alive[0] = true;
    s.chest_cursed[0] = true;
    s.chests[0] = s.hero.pos;
    s.hero.pos = s.chests[0];
    const hp = s.hero.vitals.val;
    s.pickupAt(s.hero.pos.x, s.hero.pos.y);
    try std.testing.expect(s.hero.vitals.val < hp);
    try std.testing.expect(s.hero.status.vulnerable_turns > 0);
    try std.testing.expectEqual(@as(u32, 25), s.gold);
}

test "run sim: shop buys healing and permanent power" {
    var s = Sim.init(91, .warrior);
    try std.testing.expect(s.shop_active);
    s.hero.pos = s.shop;
    s.gold = 100;
    s.hero.vitals.val = 20;
    try std.testing.expect(s.useShop(.heal));
    try std.testing.expect(s.hero.vitals.val > 20);
    try std.testing.expectEqual(@as(u32, 75), s.gold);
    try std.testing.expect(s.shop_used);
    try std.testing.expect(!s.useShop(.power));

    var p = Sim.init(92, .mage);
    p.hero.pos = p.shop;
    p.gold = 60;
    const magic = p.hero.sheet.stats.magic.val;
    try std.testing.expect(p.useShop(.power));
    try std.testing.expectApproxEqAbs(magic + 2, p.hero.sheet.stats.magic.val, 0.001);
    try std.testing.expectEqual(@as(u32, 0), p.gold);
    try std.testing.expect(!p.useShop(.heal));

    var c = Sim.init(93, .warrior);
    c.hero.pos = c.shop;
    c.gold = 20;
    c.hero.status.burn_turns = 2;
    c.hero.status.slow_turns = 2;
    c.hero.status.vulnerable_turns = 2;
    try std.testing.expect(c.useShop(.cleanse));
    try std.testing.expectEqual(@as(u16, 0), c.hero.status.burn_turns);
    try std.testing.expectEqual(@as(u16, 0), c.hero.status.slow_turns);
    try std.testing.expectEqual(@as(u16, 0), c.hero.status.vulnerable_turns);

    var l = Sim.init(94, .warrior);
    l.hero.pos = l.shop;
    l.gold = 100;
    try std.testing.expect(l.buyShopLoot());
    try std.testing.expectEqual(@as(u32, 20), l.gold);
    try std.testing.expect(l.shop_used);
    try std.testing.expect(!l.buyShopLoot());
}

test "run sim: shrine grants one permanent stat choice" {
    var s = Sim.init(55, .mage);
    try std.testing.expect(s.shrine_active);
    s.hero.pos = s.shrine;
    try std.testing.expect(s.atShrine());
    const magic = s.hero.sheet.stats.magic.val;
    try std.testing.expect(s.useShrine(.main_stat));
    try std.testing.expectApproxEqAbs(magic + 2, s.hero.sheet.stats.magic.val, 0.001);
    try std.testing.expect(s.shrine_used);
    try std.testing.expect(!s.atShrine());
    try std.testing.expect(!s.useShrine(.will));

    var risk = Sim.init(56, .warrior);
    risk.hero.pos = risk.shrine;
    const str = risk.hero.sheet.stats.strength.val;
    const con = risk.hero.sheet.stats.constitution.val;
    try std.testing.expect(risk.useShrine(.risk));
    try std.testing.expectApproxEqAbs(str + 4, risk.hero.sheet.stats.strength.val, 0.001);
    try std.testing.expectApproxEqAbs(@max(1, con - 2), risk.hero.sheet.stats.constitution.val, 0.001);
}

test "run sim: boss summons skeletons at half hp once" {
    var s = Sim.init(21, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 5,
        .name = "深渊守卫",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 250,
        .hp_max = 420,
        .attack = 16,
        .armor = 15,
        .speed = 90,
        .range = 1,
        .xp = 200,
        .energy = 100,
    });
    s.hero.combat.attack.val = 50;
    s.playerAttack(0, 1.0);
    try std.testing.expect(s.boss_summoned);
    try std.testing.expect(s.enemy_count >= 2);
    const after_first = s.enemy_count;
    s.playerAttack(0, 1.0);
    try std.testing.expectEqual(after_first, s.enemy_count);
}

test "run sim: boss enrages below half hp and speeds up its cleave" {
    var s = Sim.init(21, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 5,
        .name = "深渊守卫",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 100,
        .hp_max = 420,
        .attack = 16,
        .armor = 15,
        .speed = 90,
        .range = 1,
        .xp = 200,
        .energy = 100,
    });
    s.hero.combat.attack.val = 50;
    s.playerAttack(0, 1.0);
    try std.testing.expect(s.enemies[0].life.alive);
    try std.testing.expect(s.boss_enraged);
    try std.testing.expect(s.enemies[0].combat.attack.val > 16);
    try std.testing.expect(s.enemies[0].combat.speed.val >= 100);

    // The enraged phase keeps the normal every-third-phase cleave cadence.
    s.turn = 1;
    const enraged_intent = s.intentFor(0) orelse return error.MissingIntent;
    try std.testing.expect(enraged_intent.kind != intent_mod.IntentKind.aoe);
}

test "run sim: boss is immune to stun and slow" {
    var s = Sim.init(21, .chronomancer);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
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
    });
    try std.testing.expect(s.enemies[0].status.stun_immune);
    s.hero.resource.val = 100;
    try std.testing.expect(s.useTalent(1));
    try std.testing.expectEqual(@as(u16, 0), s.enemies[0].status.stun_turns);
    try std.testing.expect(s.enemies[0].status.slow_turns > 0);
}

test "run sim: killing the last boss wins" {
    var s = Sim.init(21, .mage);
    s.floor = s.floors;
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
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
    });
    s.hero.combat.attack.val = 100;
    s.playerAttack(0, 1.0);
    try std.testing.expect(s.enemies[0].vitals.val <= 0);
    try std.testing.expectEqual(State.victory, s.state);
}

test "run sim: level-up banks a point and auto allocate spends it" {
    var s = Sim.init(22, .warrior);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
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
    });
    const str = s.hero.sheet.stats.strength.val;
    s.hero.combat.attack.val = 100;
    s.playerAttack(0, 1.0);
    try std.testing.expectEqual(@as(u16, 2), s.hero.progression.level);
    try std.testing.expectEqual(@as(u8, 1), s.hero.progression.pending_points);
    try std.testing.expectEqual(str, s.hero.sheet.stats.strength.val);
    try std.testing.expect(s.spendPoint(0));
    try std.testing.expectEqual(str + 1, s.hero.sheet.stats.strength.val);
    try std.testing.expectEqual(@as(u8, 0), s.hero.progression.pending_points);

    var auto = Sim.init(23, .warrior);
    auto.auto_allocate = true;
    auto.enemy_count = 1;
    auto.enemies[0] = s.enemies[0];
    auto.enemies[0].vitals.val = 1;
    auto.enemies[0].life.alive = true;
    auto.enemies[0].reward.xp = 200;
    const base = auto.hero.sheet.stats.strength.val;
    auto.hero.combat.attack.val = 100;
    auto.playerAttack(0, 1.0);
    try std.testing.expectEqual(base + 1, auto.hero.sheet.stats.strength.val);
    try std.testing.expectEqual(@as(u8, 0), auto.hero.progression.pending_points);
}

test "run sim: deferred enemy phase waits for resolution" {
    var s = Sim.init(51, .warrior);
    s.defer_enemies = true;
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
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
    });
    const hp = s.hero.vitals.val;
    try std.testing.expect(s.wait());
    try std.testing.expect(s.enemy_phase_pending);
    try std.testing.expectEqual(hp, s.hero.vitals.val);
    s.resolvePendingEnemyPhase();
    try std.testing.expect(!s.enemy_phase_pending);
    try std.testing.expect(s.hero.vitals.val < hp or s.state == .dead);
}

test "run sim: chronomancer rewind returns three steps and cleanses" {
    var s = Sim.init(96, .chronomancer);
    var spots: [3]GridPos = undefined;
    var n: usize = 0;
    var y: i32 = 0;
    while (y < grid_h and n < 3) : (y += 1) {
        var x: i32 = 0;
        while (x < grid_w and n < 3) : (x += 1) {
            if (!s.isFree(x, y)) continue;
            if (x == s.hero.pos.x and y == s.hero.pos.y) continue;
            spots[n] = .{ .x = x, .y = y };
            n += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), n);
    for (spots) |p| {
        s.hero.pos = p;
        s.pushHistory();
    }
    s.hero.status.burn_turns = 2;
    s.hero.vitals.val = 40;
    s.hero.resource.val = 100;
    try std.testing.expect(s.useTalent(2));
    try std.testing.expect(s.hero.pos.eql(spots[0]));
    try std.testing.expectEqual(@as(u16, 0), s.hero.status.burn_turns);
    try std.testing.expect(s.hero.vitals.val > 40);
    try std.testing.expectEqual(@as(u8, 0), s.hero.history_len);
}

test "run sim: time stop applies stun and slow" {
    var s = Sim.init(97, .chronomancer);
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
        .kind = 0,
        .name = "骷髅兵",
        .pos = .{ .x = s.hero.pos.x + 1, .y = s.hero.pos.y },
        .hp = 200,
        .hp_max = 200,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
    });
    s.hero.resource.val = 100;
    try std.testing.expect(s.useTalent(1));
    try std.testing.expect(s.enemies[0].status.stun_turns > 0);
    try std.testing.expect(s.enemies[0].status.slow_turns > 0);
}

test "run sim: boss AOE resolves on the telegraphed turn" {
    var s = Sim.init(31, .warrior);
    s.turn = 2;
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
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
        .energy = 100,
    });
    s.aoe_armed = true;
    s.aoe_target = s.hero.pos;
    const hp = s.hero.vitals.val;
    _ = s.wait();
    try std.testing.expect(s.hero.vitals.val < hp);
    try std.testing.expect(s.hero.status.burn_turns > 0);
    try std.testing.expect(s.hero.status.vulnerable_turns > 0);
}

test "run sim: hard difficulty scales enemy hp and damage" {
    var normal = Sim.init(77, .warrior);
    var hard = Sim.initWithDifficulty(77, .warrior, .hard);
    try std.testing.expectEqual(normal.enemy_count, hard.enemy_count);
    for (normal.enemies[0..normal.enemy_count], hard.enemies[0..hard.enemy_count]) |a, b| {
        try std.testing.expectApproxEqAbs(a.vitals.full * 1.15, b.vitals.full, 0.01);
        try std.testing.expectApproxEqAbs(a.combat.attack.val * 1.08, b.combat.attack.val, 0.01);
    }
}

test "run sim: content keeps a fast and a slow speed band" {
    var fast = false;
    var slow = false;
    for (content_mod.builtin_enemies) |def| {
        if (def.combat.speed >= 150) fast = true;
        if (def.combat.speed <= 75) slow = true;
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
    s.enemies[0] = enemyFromParts(.{
        .kind = 0,
        .name = "骷髅兵",
        .pos = c,
        .hp = 300,
        .hp_max = 300,
        .attack = 8,
        .armor = 4,
        .speed = 100,
        .range = 1,
        .xp = 20,
    });
    const turn = s.turn;
    try std.testing.expect(s.useTalentAt(0, c));
    try std.testing.expect(s.enemies[0].vitals.val < 300);
    try std.testing.expect(s.enemies[0].status.burn_turns > 0);
    try std.testing.expectEqual(turn + 1, s.turn);
    try std.testing.expect(s.hero.talents.cooldowns[0] > 0);
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
    s.enemies[0] = enemyFromParts(.{
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
    const dx = s.stairs.x - s.hero.pos.x;
    const dy = s.stairs.y - s.hero.pos.y;
    try std.testing.expect(!s.move(dx, dy));
    try std.testing.expectEqual(@as(u8, 3), s.floor);
    try std.testing.expectEqual(@as(u32, 1), s.turn);
    s.enemies[0].life.alive = false;
    try std.testing.expect(s.move(dx, dy));
}

test "run sim: stepping away dodges the telegraphed boss AOE" {
    var s = Sim.init(33, .warrior);
    s.turn = 2;
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
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
    });
    s.aoe_armed = true;
    s.aoe_target = .{ .x = s.hero.pos.x, .y = s.hero.pos.y };
    const hp = s.hero.vitals.val;
    // find a legal open neighbour and step out of the marked cell
    const dirs = [_][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
    for (dirs) |d| {
        if (s.canMove(d[0], d[1])) {
            _ = s.move(d[0], d[1]);
            break;
        }
    }
    try std.testing.expect(s.hero.vitals.val >= hp);
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
    s.enemies[0] = enemyFromParts(.{
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
    });
    const hp = s.hero.vitals.val;
    const turn = s.turn;

    const intent = s.intentFor(0) orelse return error.MissingIntent;
    try std.testing.expectEqual(intent_mod.IntentKind.melee, intent.kind);
    try std.testing.expect(intent.target.eql(.{ .x = s.hero.pos.x, .y = s.hero.pos.y }));
    const expected = combat.preview(.{ .raw = 8 * 0.72 }, .{ .armor = s.hero.combat.armor.val });
    try std.testing.expectApproxEqAbs(expected, intent.damage_preview, 0.001);
    try std.testing.expect(intent.damage_preview < 8 * 0.72);
    try std.testing.expectEqual(turn, s.turn);
    try std.testing.expectEqual(hp, s.hero.vitals.val);
    try std.testing.expect(s.intentFor(1) == null);

    var intents: [max_enemies]intent_mod.EnemyIntent = undefined;
    try std.testing.expectEqual(@as(usize, 1), s.previewIntents(&intents));
    try std.testing.expectEqual(intent_mod.IntentKind.melee, intents[0].kind);
    try std.testing.expectEqual(hp, s.hero.vitals.val);
    try std.testing.expectEqual(turn, s.turn);
}

test "run sim: boss intent telegraphs its AOE on the next enemy phase" {
    var s = Sim.init(29, .warrior);
    s.turn = 2; // the player action below advances to enemy phase 3
    s.enemy_count = 1;
    s.enemies[0] = enemyFromParts(.{
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
    });

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
            s.hero.sheet.stats.strength.val,
            s.hero.sheet.stats.agility.val,
            s.hero.sheet.stats.constitution.val,
            s.hero.sheet.stats.perception.val,
            s.hero.sheet.stats.magic.val,
            s.hero.sheet.stats.will.val,
        });
        const sheet = attributes.recompute(base, &.{}, class);
        try std.testing.expectApproxEqAbs(sheet.derived.hp_max, s.hero.vitals.full, 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.resource_max, s.hero.resource.full, 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.attack, s.hero.combat.attack.val, 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.armor, s.hero.combat.armor.val, 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.crit, s.hero.combat.crit.val, 0.0001);
        try std.testing.expectApproxEqAbs(sheet.derived.speed, s.hero.combat.speed.val, 0.001);
        try std.testing.expectApproxEqAbs(sheet.derived.resource_per_turn, s.hero.resource_regen.val, 0.001);
        try std.testing.expectEqual(@as(u16, @intFromFloat(sheet.derived.hp_max)), classHpMax(class));
        try std.testing.expectEqual(@as(u16, @intFromFloat(sheet.derived.resource_max)), classResourceMax(class));
    }
}
