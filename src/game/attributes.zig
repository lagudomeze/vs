//! Six-stat attributes, modifiers and derived-stat recomputation.
//!
//! Turn-based roguelike numbers, see docs/RUN_V1.md + docs/BALANCE_V1.md:
//!
//!     HP       = 40 + 体质*8 + flat HP
//!     RESOURCE = 60 + 意志*4 + flat          (精力 / 法力 / 悖论)
//!     ATK      = 职业基础 + 主属性*1.2 + 武器 flat
//!     ARMOR    = 体质*0.5 + flat
//!     CRIT     = 5% + 感知*0.4%       (cap 50%)
//!     SPEED    = 100 + (敏捷-10)*2    (cap 50..200，回合速度)
//!     RES/TURN = 8 + 意志*0.35 + flat (每回合资源回复)
//!     伤害     = 原始 * (0.85 * 50/(50+护甲) + 0.15)，暴击 x1.5
//!
//! Cooldowns, statuses and resources settle per turn; nothing in this file
//! depends on dt or on real-time windup. Percent modifiers always scale the
//! base value: value = base*(1+pct)+flat.
//!
//! Everything in this file is pure: Stats (base) + []const Modifier -> Sheet.
//! game.zig only has to keep one Stats per character and call recompute again
//! after equipment or level changes; no allocation, no ECS coupling.

const std = @import("std");

/// The six primary attributes (力量 / 敏捷 / 体质 / 感知 / 魔力 / 意志).
pub const StatKind = enum(u8) {
    strength,
    agility,
    constitution,
    perception,
    magic,
    will,

    /// Chinese label for the HUD / combat log.
    pub fn label(self: StatKind) []const u8 {
        return switch (self) {
            .strength => "力量",
            .agility => "敏捷",
            .constitution => "体质",
            .perception => "感知",
            .magic => "魔力",
            .will => "意志",
        };
    }
};

pub const stat_count = @typeInfo(StatKind).@"enum".field_names.len;

/// Anything a Modifier can target: the six primaries plus the derived stats.
pub const StatRef = enum(u8) {
    strength,
    agility,
    constitution,
    perception,
    magic,
    will,
    hp_max,
    resource_max,
    attack,
    armor,
    crit,
    speed,
    resource_per_turn,

    pub fn fromStat(stat: StatKind) StatRef {
        return switch (stat) {
            .strength => .strength,
            .agility => .agility,
            .constitution => .constitution,
            .perception => .perception,
            .magic => .magic,
            .will => .will,
        };
    }

    /// Returns the primary attribute this ref maps to, or null for a derived stat.
    pub fn primary(self: StatRef) ?StatKind {
        return switch (self) {
            .strength => .strength,
            .agility => .agility,
            .constitution => .constitution,
            .perception => .perception,
            .magic => .magic,
            .will => .will,
            else => null,
        };
    }

    pub fn label(self: StatRef) []const u8 {
        return switch (self) {
            .hp_max => "生命上限",
            .resource_max => "资源上限",
            .attack => "攻击",
            .armor => "护甲",
            .crit => "暴击",
            .speed => "速度",
            .resource_per_turn => "资源回复",
            else => @as(StatKind, @fromBackingInt(@intCast(@backingInt(self)))).label(),
        };
    }
};

pub const ref_count = @typeInfo(StatRef).@"enum".field_names.len;

/// Where a modifier came from; used by the panel / log for traceability.
pub const ModifierSource = enum(u8) { base, level, equipment, buff, debuff };

pub const Modifier = struct {
    stat: StatRef,
    flat: f32 = 0,
    /// Fraction of the base value: 0.15 == +15%.
    pct: f32 = 0,
    source: ModifierSource = .base,
};

/// Base (unbuffed) primary attributes of one actor.
pub const Stats = struct {
    base: [stat_count]f32 = @splat(0),

    pub fn fromArray(values: [stat_count]f32) Stats {
        return .{ .base = values };
    }

    pub fn get(self: Stats, stat: StatKind) f32 {
        return self.base[@backingInt(stat)];
    }

    pub fn set(self: *Stats, stat: StatKind, value: f32) void {
        self.base[@backingInt(stat)] = clampStat(value);
    }

    pub fn add(self: *Stats, stat: StatKind, delta: f32) void {
        self.set(stat, self.get(stat) + delta);
    }
};

pub const Class = enum(u8) { warrior, mage, chronomancer };

pub const class_count = @typeInfo(Class).@"enum".field_names.len;

/// game.zig stores the class as u8 (0 狂战士, 1 元素法师, 2 时空法师).
pub fn classFromIndex(index: u8) Class {
    return @fromBackingInt(@intCast(@min(index, class_count - 1)));
}

/// 职业资源（docs/RUN_V1.md 第 6 节）。
pub const ResourceKind = enum(u8) {
    stamina,
    mana,
    paradox,

    pub fn label(self: ResourceKind) []const u8 {
        return switch (self) {
            .stamina => "精力",
            .mana => "法力",
            .paradox => "悖论",
        };
    }

    pub fn labelEn(self: ResourceKind) []const u8 {
        return switch (self) {
            .stamina => "ENERGY",
            .mana => "MANA",
            .paradox => "PARADOX",
        };
    }
};

pub const ClassProfile = struct {
    /// 职业基础攻击；沿用原型 game.zig 的 18/11/14，可调。
    base_attack: f32,
    /// 主属性：攻击按它缩放（元素/时空法师都是魔力）。
    main_stat: StatKind,
    /// 该职业使用的资源池。
    resource: ResourceKind,
};

/// One row per class: identity + numbers. Adding a class is one table row;
/// the profile/base-stat views are derived from the same source.
pub const ClassDef = struct {
    name: []const u8,
    name_en: []const u8,
    role: []const u8,
    role_en: []const u8,
    base_attack: f32,
    main_stat: StatKind,
    resource: ResourceKind,
    base_stats: [stat_count]f32,
};

pub const class_defs = [class_count]ClassDef{
    .{ .name = "狂战士", .name_en = "WARRIOR", .role = "近战 防御", .role_en = "MELEE TANK", .base_attack = 18, .main_stat = .strength, .resource = .stamina, .base_stats = .{ 14, 10, 16, 8, 4, 10 } },
    .{ .name = "元素法师", .name_en = "MAGE", .role = "远程 伤害", .role_en = "RANGED DPS", .base_attack = 11, .main_stat = .magic, .resource = .mana, .base_stats = .{ 6, 8, 8, 12, 18, 12 } },
    .{ .name = "时空法师", .name_en = "CHRONOMANCER", .role = "远程 减速", .role_en = "RANGED SLOW", .base_attack = 14, .main_stat = .magic, .resource = .paradox, .base_stats = .{ 7, 10, 9, 14, 14, 13 } },
};

pub fn profile(class: Class) ClassProfile {
    const def = class_defs[@backingInt(class)];
    return .{ .base_attack = def.base_attack, .main_stat = def.main_stat, .resource = def.resource };
}

pub fn resourceLabel(class: Class) []const u8 {
    return profile(class).resource.label();
}

pub fn baseStats(class: Class) Stats {
    return Stats.fromArray(class_defs[@backingInt(class)].base_stats);
}

fn classField(comptime field: []const u8) [class_count][]const u8 {
    var out: [class_count][]const u8 = undefined;
    for (&out, class_defs) |*slot, def| slot.* = @field(def, field);
    return out;
}

pub const class_names = classField("name");
pub const class_names_en = classField("name_en");
pub const class_roles = classField("role");
pub const class_roles_en = classField("role_en");

pub const resource_names = blk: {
    var out: [class_count][]const u8 = undefined;
    for (&out, class_defs) |*slot, def| slot.* = def.resource.label();
    break :blk out;
};

pub const resource_names_en = blk: {
    var out: [class_count][]const u8 = undefined;
    for (&out, class_defs) |*slot, def| slot.* = def.resource.labelEn();
    break :blk out;
};

pub const formulas = struct {
    /// 15% of every hit always penetrates armor.
    pub const armor_penetration: f32 = 0.15;
    pub const armor_k: f32 = 50;
    pub const crit_multiplier: f32 = 1.5;
};

/// clamp / cap 规则。主属性 0..99，暴击 <=50%，回合速度 50..200。
pub const caps = struct {
    pub const stat_min: f32 = 0;
    pub const stat_max: f32 = 99;
    pub const hp_min: f32 = 1;
    pub const resource_min: f32 = 0;
    pub const attack_min: f32 = 0;
    pub const armor_min: f32 = 0;
    pub const crit_min: f32 = 0;
    pub const crit_max: f32 = 0.50;
    pub const speed_min: f32 = 50;
    pub const speed_max: f32 = 200;
    /// A combined percentage can never invert a value.
    pub const pct_min: f32 = -1.0;
    pub const pct_max: f32 = 5.0;
};

/// A linear contribution from one primary stat.
pub const StatTerm = struct {
    stat: StatKind,
    per: f32,
};

/// Data row for one derived stat. The recompute system is generic: it walks
/// this table, so adding a derived stat needs one enum tag + one row, not a
/// new hand-written formula block.
pub const DerivedDef = struct {
    base: f32 = 0,
    terms: []const StatTerm = &.{},
    min: f32,
    max: f32 = std.math.floatMax(f32),
    /// >0 scales the class main stat (attack uses 1.2).
    main_scale: f32 = 0,
    /// Add the class's base attack before scaling.
    class_base_attack: bool = false,
};

pub const derived_defs = .{
    .hp_max = DerivedDef{ .base = 40, .terms = &[_]StatTerm{.{ .stat = .constitution, .per = 8 }}, .min = caps.hp_min },
    .resource_max = DerivedDef{ .base = 60, .terms = &[_]StatTerm{.{ .stat = .will, .per = 4 }}, .min = caps.resource_min },
    .attack = DerivedDef{ .terms = &.{}, .min = caps.attack_min, .main_scale = 1.2, .class_base_attack = true },
    .armor = DerivedDef{ .terms = &[_]StatTerm{.{ .stat = .constitution, .per = 0.5 }}, .min = caps.armor_min },
    .crit = DerivedDef{ .base = 0.05, .terms = &[_]StatTerm{.{ .stat = .perception, .per = 0.004 }}, .min = caps.crit_min, .max = caps.crit_max },
    .speed = DerivedDef{ .base = 80, .terms = &[_]StatTerm{.{ .stat = .agility, .per = 2 }}, .min = caps.speed_min, .max = caps.speed_max },
    .resource_per_turn = DerivedDef{ .base = 8, .terms = &[_]StatTerm{.{ .stat = .will, .per = 0.35 }}, .min = caps.resource_min },
};

comptime {
    for (@typeInfo(Derived).@"struct".field_names) |field_name| {
        if (!@hasField(@TypeOf(derived_defs), field_name)) {
            @compileError("derived stat has no derived_defs row: " ++ field_name);
        }
    }
    for (@typeInfo(@TypeOf(derived_defs)).@"struct".field_names) |field_name| {
        if (!@hasField(Derived, field_name)) {
            @compileError("derived_defs row has no Derived field: " ++ field_name);
        }
    }
}

pub const Derived = struct {
    hp_max: f32 = 0,
    resource_max: f32 = 0,
    attack: f32 = 0,
    armor: f32 = 0,
    /// Fraction, not percent: 0.082 == 8.2%.
    crit: f32 = 0,
    /// 回合速度（100 基准）。
    speed: f32 = 0,
    /// 每回合资源回复。
    resource_per_turn: f32 = 0,

    pub fn value(self: Derived, ref: StatRef) ?f32 {
        inline for (@typeInfo(Derived).@"struct".field_names) |field_name| {
            if (ref == @field(StatRef, field_name)) return @field(self, field_name);
        }
        return null;
    }
};

pub const Sheet = struct {
    /// Effective primary attributes (基础 + 装备/增益修正).
    stats: [stat_count]f32,
    derived: Derived,

    pub fn stat(self: Sheet, kind: StatKind) f32 {
        return self.stats[@backingInt(kind)];
    }

    pub fn derivedValue(self: Sheet, ref: StatRef) f32 {
        if (ref.primary()) |kind| return self.stat(kind);
        return self.derived.value(ref) orelse 0;
    }
};

/// Summed flat/pct contribution of one stat, for the character panel.
pub const Contribution = struct {
    flat: f32 = 0,
    pct: f32 = 0,
};

pub fn contribution(mods: []const Modifier, ref: StatRef) Contribution {
    var out = Contribution{};
    for (mods) |mod| {
        if (mod.stat != ref) continue;
        out.flat += sanitize(mod.flat);
        out.pct += sanitize(mod.pct);
    }
    return out;
}

pub fn clampStat(value: f32) f32 {
    return std.math.clamp(sanitize(value), caps.stat_min, caps.stat_max);
}

/// v1 physical mitigation: 15% always penetrates, armor splits the rest.
pub fn damageAfterArmor(raw: f32, armor: f32) f32 {
    const a = @max(0.0, sanitize(armor));
    const scaled = formulas.armor_penetration +
        (1.0 - formulas.armor_penetration) * formulas.armor_k / (formulas.armor_k + a);
    return @max(0.0, sanitize(raw)) * scaled;
}

pub fn resolveDamage(raw: f32, armor: f32, crit: bool) f32 {
    const hit = damageAfterArmor(raw, armor);
    return if (crit) hit * formulas.crit_multiplier else hit;
}

/// v1 growth (docs/RUN_V1.md 第 8 节): +1 attribute point per level, auto
/// allocated to the class main stat. The game refills HP/resource on level up.
pub fn applyLevels(stats: *Stats, class: Class, levels: u32) void {
    const main = profile(class).main_stat;
    var i: u32 = 0;
    while (i < levels) : (i += 1) stats.add(main, 1.0);
}

pub const progression = struct {
    /// 升到下一级所需 XP = 100 × 当前等级。
    pub const xp_base: u32 = 100;
    pub const max_level: u16 = 50;
};

/// Turn-based XP/level bookkeeping. xp is the progress inside the current
/// level; the panel reads level / xp / xpToNext().
pub const Progression = struct {
    level: u16 = 1,
    xp: u32 = 0,

    pub fn xpToNext(self: Progression) u32 {
        return progression.xp_base * @as(u32, self.level);
    }

    /// Adds XP and returns how many levels were gained (0 or more). Callers
    /// then call applyLevels() once per gained level.
    pub fn addXp(self: *Progression, amount: u32) u16 {
        self.xp += amount;
        var gained: u16 = 0;
        while (self.level < progression.max_level and self.xp >= self.xpToNext()) {
            self.xp -= self.xpToNext();
            self.level += 1;
            gained += 1;
        }
        return gained;
    }

    /// 0..1 progress towards the next level, for the HUD bar.
    pub fn progress01(self: Progression) f32 {
        const next = self.xpToNext();
        if (next == 0) return 1.0;
        return @min(1.0, @as(f32, @floatFromInt(self.xp)) / @as(f32, @floatFromInt(next)));
    }
};

const Accumulator = struct {
    flat: [ref_count]f32 = @splat(0),
    pct: [ref_count]f32 = @splat(0),

    fn add(self: *Accumulator, mod: Modifier) void {
        const i = @backingInt(mod.stat);
        self.flat[i] += sanitize(mod.flat);
        self.pct[i] += sanitize(mod.pct);
    }

    /// base*(1+pct) + flat, clamped. Percentages scale the base value only.
    fn apply(self: *const Accumulator, ref: StatRef, base: f32, lo: f32, hi: f32) f32 {
        const i = @backingInt(ref);
        const factor = 1.0 + std.math.clamp(self.pct[i], caps.pct_min, caps.pct_max);
        const value = sanitize(base) * factor + self.flat[i];
        if (!std.math.isFinite(value)) return lo;
        return std.math.clamp(value, lo, hi);
    }
};

fn sanitize(value: f32) f32 {
    return if (std.math.isFinite(value)) value else 0;
}

/// Pure recompute: base stats + modifier list + class -> full sheet.
pub fn recompute(base: Stats, mods: []const Modifier, class: Class) Sheet {
    var acc = Accumulator{};
    for (mods) |mod| acc.add(mod);

    var stats: [stat_count]f32 = undefined;
    inline for (@typeInfo(StatKind).@"enum".field_names) |field_name| {
        const kind: StatKind = @field(StatKind, field_name);
        stats[@backingInt(kind)] = acc.apply(
            StatRef.fromStat(kind),
            base.base[@backingInt(kind)],
            caps.stat_min,
            caps.stat_max,
        );
    }

    const p = profile(class);
    const main = stats[@backingInt(p.main_stat)];

    var derived = Derived{};
    inline for (@typeInfo(Derived).@"struct".field_names) |field_name| {
        const def = @field(derived_defs, field_name);
        const ref = @field(StatRef, field_name);
        var base_value = def.base;
        if (def.class_base_attack) base_value += p.base_attack;
        for (def.terms) |term| base_value += stats[@backingInt(term.stat)] * term.per;
        if (def.main_scale != 0) base_value += main * def.main_scale;
        @field(derived, field_name) = acc.apply(ref, base_value, def.min, def.max);
    }

    return .{ .stats = stats, .derived = derived };
}

// ------------------------------------------------------------------- tests

const expectApprox = std.testing.expectApproxEqAbs;

test "class base stats and derived formulas match the v1 table" {
    const warrior = recompute(baseStats(.warrior), &.{}, .warrior);
    try expectApprox(@as(f32, 168), warrior.derived.hp_max, 0.001); // 40 + 16*8
    try expectApprox(@as(f32, 100), warrior.derived.resource_max, 0.001); // 60 + 10*4
    try expectApprox(@as(f32, 34.8), warrior.derived.attack, 0.001); // 18 + 14*1.2
    try expectApprox(@as(f32, 8), warrior.derived.armor, 0.001); // 16*0.5
    try expectApprox(@as(f32, 0.082), warrior.derived.crit, 0.0001); // 5% + 8*0.4%
    try expectApprox(@as(f32, 100), warrior.derived.speed, 0.001); // 100 + (10-10)*2
    try expectApprox(@as(f32, 11.5), warrior.derived.resource_per_turn, 0.001); // 8 + 10*0.35

    const mage = recompute(baseStats(.mage), &.{}, .mage);
    try expectApprox(@as(f32, 104), mage.derived.hp_max, 0.001);
    try expectApprox(@as(f32, 108), mage.derived.resource_max, 0.001);
    try expectApprox(@as(f32, 32.6), mage.derived.attack, 0.001); // 11 + 18*1.2
    try expectApprox(@as(f32, 0.098), mage.derived.crit, 0.0001);
    try expectApprox(@as(f32, 96), mage.derived.speed, 0.001); // 100 + (8-10)*2

    const chrono = recompute(baseStats(.chronomancer), &.{}, .chronomancer);
    try expectApprox(@as(f32, 112), chrono.derived.hp_max, 0.001);
    try expectApprox(@as(f32, 112), chrono.derived.resource_max, 0.001);
    try expectApprox(@as(f32, 30.8), chrono.derived.attack, 0.001); // 14 + 14*1.2
}

test "each class has its own resource pool" {
    try std.testing.expectEqual(ResourceKind.stamina, profile(.warrior).resource);
    try std.testing.expectEqual(ResourceKind.mana, profile(.mage).resource);
    try std.testing.expectEqual(ResourceKind.paradox, profile(.chronomancer).resource);
    try std.testing.expectEqualStrings("精力", resourceLabel(.warrior));
    try std.testing.expectEqualStrings("法力", resourceLabel(.mage));
    try std.testing.expectEqualStrings("悖论", resourceLabel(.chronomancer));
}

test "xp follows 100 x current level and levels auto allocate" {
    var prog = Progression{};
    try std.testing.expectEqual(@as(u32, 100), prog.xpToNext());
    const gained = prog.addXp(350); // 100 -> L2, then 200 -> L3, 50 left
    try std.testing.expectEqual(@as(u16, 2), gained);
    try std.testing.expectEqual(@as(u16, 3), prog.level);
    try std.testing.expectEqual(@as(u32, 50), prog.xp);
    try std.testing.expectEqual(@as(u32, 300), prog.xpToNext());
    try std.testing.expect(prog.progress01() > 0.16 and prog.progress01() < 0.17);

    var stats = baseStats(.warrior);
    applyLevels(&stats, .warrior, gained);
    try expectApprox(@as(f32, 16), stats.get(.strength), 0.001); // 14 + 2 levels
}

test "flat modifiers move derived stats immediately" {
    const base = baseStats(.warrior);
    const before = recompute(base, &.{}, .warrior);
    const mods = [_]Modifier{
        .{ .stat = .strength, .flat = 10, .source = .equipment },
        .{ .stat = .constitution, .flat = 2, .source = .equipment },
        .{ .stat = .hp_max, .flat = 20, .source = .equipment },
    };
    const after = recompute(base, &mods, .warrior);

    try expectApprox(@as(f32, 24), after.stat(.strength), 0.001);
    try expectApprox(@as(f32, 46.8), after.derived.attack, 0.001); // 18 + 24*1.2
    try expectApprox(@as(f32, 204), after.derived.hp_max, 0.001); // 40 + 18*8 + 20
    try std.testing.expect(after.derived.hp_max > before.derived.hp_max);
    try std.testing.expect(after.derived.attack > before.derived.attack);
}

test "percent modifiers scale the base value only" {
    const base = Stats.fromArray(.{ 10, 0, 0, 0, 0, 0 });
    const mods = [_]Modifier{
        .{ .stat = .strength, .flat = 10, .source = .equipment },
        .{ .stat = .strength, .pct = 0.5, .source = .buff },
    };
    const sheet = recompute(base, &mods, .warrior);
    // 10*1.5 + 10 == 25, not (10+10)*1.5 == 30.
    try expectApprox(@as(f32, 25), sheet.stat(.strength), 0.001);
    try expectApprox(@as(f32, 48), sheet.derived.attack, 0.001); // 18 + 25*1.2
}

test "caps clamp crit and turn speed" {
    const base = Stats.fromArray(.{ 0, 99, 0, 99, 0, 0 });
    const mods = [_]Modifier{
        .{ .stat = .crit, .flat = 0.2, .source = .equipment },
        .{ .stat = .speed, .pct = 5.0, .source = .buff },
    };
    const sheet = recompute(base, &mods, .warrior);
    // 5% + 99*0.4% + 20% == 64.6% -> 50%
    try expectApprox(caps.crit_max, sheet.derived.crit, 0.0001);
    // (100 + (99-10)*2) * 6 -> 200
    try expectApprox(caps.speed_max, sheet.derived.speed, 0.0001);
}

test "negative modifiers never invert a value" {
    const base = Stats.fromArray(.{ 1, 1, 1, 1, 1, 1 });
    const mods = [_]Modifier{
        .{ .stat = .strength, .flat = -50, .source = .debuff },
        .{ .stat = .constitution, .pct = -5.0, .source = .debuff },
        .{ .stat = .hp_max, .flat = -100, .source = .debuff },
    };
    const sheet = recompute(base, &mods, .warrior);
    try expectApprox(caps.stat_min, sheet.stat(.strength), 0.001);
    try expectApprox(caps.stat_min, sheet.stat(.constitution), 0.001);
    try expectApprox(caps.hp_min, sheet.derived.hp_max, 0.001);
    try expectApprox(@as(f32, 0), sheet.derived.armor, 0.001);
}

test "primary stats clamp to the 0..99 band" {
    const base = Stats.fromArray(.{ 200, 0, 0, 0, 0, 0 });
    const mods = [_]Modifier{.{ .stat = .agility, .flat = 500 }};
    const sheet = recompute(base, &mods, .warrior);
    try expectApprox(caps.stat_max, sheet.stat(.strength), 0.001);
    try expectApprox(caps.stat_max, sheet.stat(.agility), 0.001);
}

test "damage mitigation keeps 15% penetration" {
    try expectApprox(@as(f32, 100), damageAfterArmor(100, 0), 0.001);
    try expectApprox(@as(f32, 57.5), damageAfterArmor(100, 50), 0.001);
    try expectApprox(@as(f32, 43.3333), damageAfterArmor(100, 100), 0.01);
    try expectApprox(@as(f32, 150), resolveDamage(100, 0, true), 0.001);
    try expectApprox(@as(f32, 57.5), resolveDamage(100, 50, false), 0.001);
}

test "level ups auto allocate to the class main stat" {
    var warrior = baseStats(.warrior);
    applyLevels(&warrior, .warrior, 3);
    try expectApprox(@as(f32, 17), warrior.get(.strength), 0.001); // 14 + 3

    var mage = baseStats(.mage);
    applyLevels(&mage, .mage, 2);
    try expectApprox(@as(f32, 20), mage.get(.magic), 0.001); // 18 + 2
    try expectApprox(@as(f32, 6), mage.get(.strength), 0.001);
}

test "contribution sums flat and pct per stat" {
    const mods = [_]Modifier{
        .{ .stat = .strength, .flat = 4, .source = .equipment },
        .{ .stat = .strength, .pct = 0.1, .source = .buff },
        .{ .stat = .strength, .flat = 1, .source = .equipment },
        .{ .stat = .armor, .flat = 3, .source = .equipment },
    };
    const c = contribution(&mods, .strength);
    try expectApprox(@as(f32, 5), c.flat, 0.001);
    try expectApprox(@as(f32, 0.1), c.pct, 0.0001);
    try expectApprox(@as(f32, 0), contribution(&mods, .will).flat, 0.001);
}
