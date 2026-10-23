//! Embedded content data: assets/data/{items,enemies,skills}.json.
//!
//! The JSON is embedded at compile time (assets/data/data.zig, registered as
//! the anonymous "data" import in build.zig) and parsed with std.json at
//! startup. Every file is validated independently; a parse or validation
//! failure is reported and that file falls back to the built-in defaults below
//! so a bad data edit can never crash the game (CT-05/06 simplified).
//!
//! Turn-based v1 content, docs/RUN_V1.md: 8 items (第 8 节), 6 enemies
//! (第 7 节, includes elites and the boss), 9 player talents (第 6 节) plus the
//! boss AOE skill. Cooldowns, resources and statuses are all counted in turns.

const std = @import("std");
const attributes = @import("attributes.zig");
const items = @import("items.zig");
const embedded = @import("data");

pub const file_items = "items.json";
pub const file_enemies = "enemies.json";
pub const file_skills = "skills.json";

pub const SkillKind = enum(u8) { player, enemy };

/// 天赋效果类型（docs/RUN_V1.md 第 6 节）。
pub const SkillEffect = enum(u8) {
    damage,
    damage_knockback,
    attack_buff,
    blink,
    damage_slow,
    stun,
    recall,
};

pub const SkillDef = struct {
    id: []const u8,
    name: []const u8,
    kind: SkillKind = .player,
    /// 玩家天赋的职业；敌人技能必须为 null。
    class: ?attributes.Class = null,
    effect: SkillEffect = .damage,
    /// 资源消耗（回合制，整数）。
    cost: u16 = 0,
    /// 冷却回合数。
    cooldown_turns: u16 = 0,
    /// 玩家技能伤害 = 攻击 x damage_mult。
    damage_mult: f32 = 0,
    /// 敌人技能的固定伤害。
    flat_damage: f32 = 0,
    /// 施法距离（格）；1 = 相邻近战。
    range_cells: u16 = 1,
    /// 范围半径（格）。
    aoe_cells: f32 = 0,
    /// 冲锋击退格数。
    knockback_cells: u16 = 0,
    /// 闪现最大传送格数。
    teleport_cells: u16 = 0,
    /// 战吼攻击加成（0.30 = +30%）。
    buff_pct: f32 = 0,
    /// 增益 / 减速 / 停滞 / 回溯持续的回合数。
    duration_turns: u16 = 0,
    /// 减速比例。
    slow_pct: f32 = 0,
    description: []const u8 = "",
};

pub const EnemyDef = struct {
    id: []const u8,
    name: []const u8,
    /// 模型名，对应 assets/baked 里的模型。
    model: []const u8,
    /// game.zig 的动画/模型序号（0 骷髅, 1 幽魂, 2 石魔像, 3 Boss, 4-5 精英）。
    kind: u8,
    hp: f32,
    damage: f32,
    armor: f32 = 0,
    /// 回合速度（100 基准，docs/RUN_V1.md 第 4 节）。
    speed: u16 = 100,
    /// 普攻距离（格）。
    attack_range: u16 = 1,
    /// 普攻冷却回合数。
    attack_cooldown_turns: u16 = 1,
    scale: f32 = 1.0,
    xp: u32 = 0,
    drop_chance: f32 = 0.3,
    /// 出现层数（1..3），供关卡生成筛选。
    min_layer: u8 = 1,
    max_layer: u8 = 3,
    elite: bool = false,
    boss: bool = false,
    /// 特殊技能 id（skills.json 里 kind == enemy 的条目），Boss AOE 用。
    skill: ?[]const u8 = null,
};

/// Per-file origin after loading.
pub const Source = enum(u8) { embedded, fallback };

pub const Report = struct {
    pub const max_issues = 12;

    pub const Issue = struct {
        file: []const u8,
        message: []const u8,
        subject: []const u8 = "",
    };

    items: Source = .embedded,
    enemies: Source = .embedded,
    skills: Source = .embedded,
    issues: [max_issues]Issue = undefined,
    issue_count: usize = 0,

    pub fn add(self: *Report, file: []const u8, message: []const u8, subject: []const u8) void {
        if (self.issue_count >= max_issues) return;
        self.issues[self.issue_count] = .{
            .file = file,
            .message = message,
            .subject = subject,
        };
        self.issue_count += 1;
    }

    pub fn issueSlice(self: *const Report) []const Issue {
        return self.issues[0..self.issue_count];
    }

    pub fn ok(self: *const Report) bool {
        return self.issue_count == 0;
    }

    pub fn anyFallback(self: *const Report) bool {
        return self.items == .fallback or self.enemies == .fallback or self.skills == .fallback;
    }

    /// Startup diagnostics: print every issue to stderr / a log writer.
    pub fn write(self: *const Report, writer: anytype) !void {
        for (self.issueSlice()) |issue| {
            if (issue.subject.len > 0) {
                try writer.print("[content] {s}: {s} ({s})\n", .{ issue.file, issue.message, issue.subject });
            } else {
                try writer.print("[content] {s}: {s}\n", .{ issue.file, issue.message });
            }
        }
    }
};

pub const Content = struct {
    arena: std.heap.ArenaAllocator,
    items: []const items.ItemDef,
    enemies: []const EnemyDef,
    skills: []const SkillDef,
    report: Report,

    pub fn deinit(self: *Content) void {
        self.arena.deinit();
    }

    pub fn usingFallback(self: *const Content) bool {
        return self.report.anyFallback();
    }

    /// Index into the item table; this is the ItemId used by items.zig.
    pub fn itemIndex(self: *const Content, id: []const u8) ?items.ItemId {
        for (self.items, 0..) |def, i| {
            if (std.mem.eql(u8, def.id, id)) return @intCast(i);
        }
        return null;
    }

    pub fn item(self: *const Content, id: []const u8) ?*const items.ItemDef {
        const index = self.itemIndex(id) orelse return null;
        return &self.items[index];
    }

    pub fn enemy(self: *const Content, id: []const u8) ?*const EnemyDef {
        for (self.enemies) |*def| {
            if (std.mem.eql(u8, def.id, id)) return def;
        }
        return null;
    }

    pub fn skill(self: *const Content, id: []const u8) ?*const SkillDef {
        return findSkill(self.skills, id);
    }

    /// The class hotbar talents, in data order (1/2/3 in docs/RUN_V1.md).
    pub fn talentsFor(
        self: *const Content,
        class: attributes.Class,
        out: []*const SkillDef,
    ) []const *const SkillDef {
        var n: usize = 0;
        for (self.skills) |*def| {
            if (def.kind != .player) continue;
            const def_class = def.class orelse continue;
            if (def_class != class) continue;
            if (n >= out.len) break;
            out[n] = def;
            n += 1;
        }
        return out[0..n];
    }

    /// v1 loot: drop_chance (default 30%) then a class-weighted pick.
    /// chance_roll / pick_roll are caller-supplied uniforms in [0,1) so the
    /// function stays pure and testable.
    pub fn rollDrop(
        self: *const Content,
        class: attributes.Class,
        chance_roll: f32,
        pick_roll: f32,
        enemy_def: *const EnemyDef,
    ) ?items.ItemId {
        if (self.items.len == 0) return null;
        if (chance_roll > enemy_def.drop_chance) return null;

        var total: f32 = 0;
        for (self.items) |def| {
            if (!def.allowsClass(class)) continue;
            total += @max(0.0, def.drop.weight);
        }
        if (total <= 0) return null;

        var pick = std.math.clamp(pick_roll, 0.0, 1.0) * total;
        var last: ?items.ItemId = null;
        for (self.items, 0..) |def, i| {
            if (!def.allowsClass(class)) continue;
            last = @intCast(i);
            pick -= @max(0.0, def.drop.weight);
            if (pick <= 0) return @intCast(i);
        }
        return last;
    }
};

pub fn findSkill(skills: []const SkillDef, id: []const u8) ?*const SkillDef {
    for (skills) |*def| {
        if (std.mem.eql(u8, def.id, id)) return def;
    }
    return null;
}
// ------------------------------------------------------- built-in fallbacks

/// assets/data/items.json 的镜像；JSON 坏掉时用它。
pub const builtin_items = [_]items.ItemDef{
    .{
        .id = "iron_sword",
        .name = "铁剑",
        .quality = .common,
        .drop = .{ .classes = &.{.warrior} },
        .kind = .{ .equipment = .{
            .slot = .main_hand,
            .mods = &.{
                .{ .stat = .attack, .flat = 6 },
                .{ .stat = .strength, .flat = 2 },
            },
        } },
        .description = "狂战士的制式铁剑：+6 攻击，+2 力量。",
    },
    .{
        .id = "staff",
        .name = "法杖",
        .quality = .common,
        .drop = .{ .classes = &.{.mage} },
        .kind = .{ .equipment = .{
            .slot = .main_hand,
            .mods = &.{
                .{ .stat = .attack, .flat = 5 },
                .{ .stat = .magic, .flat = 3 },
            },
        } },
        .description = "元素法师的橡木法杖：+5 攻击，+3 魔力。",
    },
    .{
        .id = "leather_armor",
        .name = "皮甲",
        .quality = .common,
        .kind = .{ .equipment = .{
            .slot = .body,
            .mods = &.{
                .{ .stat = .hp_max, .flat = 20 },
                .{ .stat = .armor, .flat = 3 },
            },
        } },
        .description = "轻便的皮质护甲：+20 生命上限，+3 护甲。",
    },
    .{
        .id = "mithril_armor",
        .name = "秘银甲",
        .quality = .rare,
        .kind = .{ .equipment = .{
            .slot = .body,
            .mods = &.{
                .{ .stat = .hp_max, .flat = 35 },
                .{ .stat = .armor, .flat = 6 },
                .{ .stat = .will, .flat = 2 },
            },
        } },
        .description = "秘银环甲：+35 生命上限，+6 护甲，+2 意志。",
    },
    .{
        .id = "tiger_charm",
        .name = "猛虎护符",
        .quality = .rare,
        .drop = .{ .classes = &.{.warrior} },
        .kind = .{ .equipment = .{
            .slot = .trinket,
            .mods = &.{
                .{ .stat = .strength, .flat = 4 },
                .{ .stat = .crit, .flat = 0.03 },
            },
        } },
        .description = "虎牙护符：+4 力量，+3% 暴击。",
    },
    .{
        .id = "hourglass",
        .name = "时光沙漏",
        .quality = .rare,
        .drop = .{ .classes = &.{.mage} },
        .kind = .{ .equipment = .{
            .slot = .trinket,
            .mods = &.{
                .{ .stat = .will, .flat = 5 },
                .{ .stat = .resource_max, .flat = 10 },
            },
        } },
        .description = "封存时间的沙漏：+5 意志，+10 法力上限。",
    },
    .{
        .id = "healing_potion",
        .name = "生命瓶",
        .quality = .common,
        .drop = .{ .weight = 0.8 },
        .kind = .{ .consumable = .{ .use = .{ .heal = 40 } } },
        .description = "恢复 40 生命；v1 暂不做使用 UI。",
    },
    .{
        .id = "gear_sigil",
        .name = "齿轮印记",
        .quality = .epic,
        .drop = .{ .classes = &.{.chronomancer} },
        .kind = .{ .equipment = .{
            .slot = .trinket,
            .mods = &.{
                .{ .stat = .perception, .flat = 3 },
                .{ .stat = .magic, .flat = 2 },
                .{ .stat = .crit, .flat = 0.05 },
            },
        } },
        .description = "时空法师的齿轮印记：+3 感知，+2 魔力，+5% 暴击。",
    },
};

/// assets/data/enemies.json 的镜像。
pub const builtin_enemies = [_]EnemyDef{
    .{
        .id = "skeleton",
        .name = "骷髅兵",
        .model = "skeleton",
        .kind = 0,
        .hp = 70,
        .damage = 8,
        .armor = 4,
        .speed = 90,
        .attack_range = 1,
        .attack_cooldown_turns = 1,
        .scale = 1.18,
        .xp = 20,
        .min_layer = 1,
        .max_layer = 3,
    },
    .{
        .id = "wraith",
        .name = "幽魂",
        .model = "wraith",
        .kind = 1,
        .hp = 55,
        .damage = 7,
        .armor = 1,
        .speed = 100,
        .attack_range = 4,
        .attack_cooldown_turns = 2,
        .scale = 1.32,
        .xp = 25,
        .min_layer = 1,
        .max_layer = 3,
    },
    .{
        .id = "golem",
        .name = "石魔像",
        .model = "golem",
        .kind = 2,
        .hp = 150,
        .damage = 12,
        .armor = 12,
        .speed = 70,
        .attack_range = 1,
        .attack_cooldown_turns = 2,
        .scale = 1.55,
        .xp = 40,
        .min_layer = 2,
        .max_layer = 3,
    },
    .{
        .id = "abyss_guard",
        .name = "深渊守卫",
        .model = "abyss_guard",
        .kind = 3,
        .hp = 420,
        .damage = 16,
        .armor = 15,
        .speed = 80,
        .attack_range = 1,
        .attack_cooldown_turns = 2,
        .scale = 1.95,
        .xp = 200,
        .min_layer = 3,
        .max_layer = 3,
        .boss = true,
        .skill = "abyss_cleave",
    },
    .{
        .id = "elite_skeleton",
        .name = "精英骷髅",
        .model = "skeleton",
        .kind = 4,
        .hp = 100,
        .damage = 11,
        .armor = 7,
        .speed = 100,
        .attack_range = 1,
        .attack_cooldown_turns = 1,
        .scale = 1.28,
        .xp = 50,
        .min_layer = 2,
        .max_layer = 3,
        .elite = true,
    },
    .{
        .id = "elite_wraith",
        .name = "精英幽魂",
        .model = "wraith",
        .kind = 5,
        .hp = 85,
        .damage = 10,
        .armor = 2,
        .speed = 110,
        .attack_range = 4,
        .attack_cooldown_turns = 2,
        .scale = 1.42,
        .xp = 50,
        .min_layer = 2,
        .max_layer = 3,
        .elite = true,
    },
};

/// assets/data/skills.json 的镜像：9 个玩家天赋（每职业 3 个）+ Boss AOE。
pub const builtin_skills = [_]SkillDef{
    .{
        .id = "heavy_strike",
        .name = "重击",
        .kind = .player,
        .class = .warrior,
        .effect = .damage,
        .cost = 25,
        .cooldown_turns = 4,
        .damage_mult = 2.0,
        .range_cells = 1,
        .description = "狂战士：近战 2.0 倍伤害，冷却 4 回合。",
    },
    .{
        .id = "charge",
        .name = "冲锋",
        .kind = .player,
        .class = .warrior,
        .effect = .damage_knockback,
        .cost = 20,
        .cooldown_turns = 6,
        .damage_mult = 1.5,
        .range_cells = 2,
        .knockback_cells = 2,
        .description = "狂战士：直线 2 格冲锋并击退 2 格，冷却 6 回合。",
    },
    .{
        .id = "war_cry",
        .name = "战吼",
        .kind = .player,
        .class = .warrior,
        .effect = .attack_buff,
        .cost = 15,
        .cooldown_turns = 8,
        .buff_pct = 0.30,
        .duration_turns = 3,
        .description = "狂战士：3 回合内攻击 +30%，冷却 8 回合。",
    },
    .{
        .id = "fireball",
        .name = "火球",
        .kind = .player,
        .class = .mage,
        .effect = .damage,
        .cost = 30,
        .cooldown_turns = 5,
        .damage_mult = 2.5,
        .range_cells = 5,
        .aoe_cells = 1.5,
        .description = "元素法师：范围 1.5 格，2.5 倍伤害，冷却 5 回合。",
    },
    .{
        .id = "ice_cone",
        .name = "冰锥",
        .kind = .player,
        .class = .mage,
        .effect = .damage_slow,
        .cost = 25,
        .cooldown_turns = 6,
        .damage_mult = 1.5,
        .range_cells = 3,
        .duration_turns = 2,
        .slow_pct = 0.50,
        .description = "元素法师：锥形 3 格，减速 2 回合（50%），冷却 6 回合。",
    },
    .{
        .id = "blink",
        .name = "闪现",
        .kind = .player,
        .class = .mage,
        .effect = .blink,
        .cost = 20,
        .cooldown_turns = 10,
        .range_cells = 5,
        .teleport_cells = 5,
        .description = "元素法师：传送到 5 格内空地，冷却 10 回合。",
    },
    .{
        .id = "time_arrow",
        .name = "时光箭",
        .kind = .player,
        .class = .chronomancer,
        .effect = .damage_slow,
        .cost = 25,
        .cooldown_turns = 4,
        .damage_mult = 2.0,
        .range_cells = 5,
        .duration_turns = 2,
        .slow_pct = 0.50,
        .description = "时空法师：2.0 倍伤害并减速 2 回合，冷却 4 回合。",
    },
    .{
        .id = "time_stop",
        .name = "时间停滞",
        .kind = .player,
        .class = .chronomancer,
        .effect = .stun,
        .cost = 30,
        .cooldown_turns = 8,
        .range_cells = 5,
        .duration_turns = 1,
        .description = "时空法师：目标跳过 1 回合，冷却 8 回合。",
    },
    .{
        .id = "recall",
        .name = "回溯",
        .kind = .player,
        .class = .chronomancer,
        .effect = .recall,
        .cost = 35,
        .cooldown_turns = 12,
        .range_cells = 0,
        .duration_turns = 2,
        .description = "时空法师：回到 2 回合前的位置，冷却 12 回合。",
    },
    .{
        .id = "abyss_cleave",
        .name = "深渊斩",
        .kind = .enemy,
        .effect = .damage,
        .cooldown_turns = 3,
        .flat_damage = 45,
        .range_cells = 1,
        .aoe_cells = 2.2,
        .description = "深渊守卫：近战 AOE，伤害 45，2.2 格范围。",
    },
};
// ------------------------------------------------------------- load / parse

/// Wire format stays flat for JSON ergonomics; the runtime converts it to
/// the ItemKind union so invalid combinations never reach gameplay.
const RawItemDef = struct {
    id: []const u8,
    name: []const u8,
    quality: items.Quality = .common,
    slot: ?items.Slot = null,
    classes: []const attributes.Class = &.{},
    weight: f32 = 1.0,
    mods: []const attributes.Modifier = &.{},
    use: ?items.Use = null,
    description: []const u8 = "",
};

const ItemsFile = struct { version: u32 = 1, items: []const RawItemDef = &.{} };

fn convertItems(alloc: std.mem.Allocator, raw: []const RawItemDef) ![]const items.ItemDef {
    const out = try alloc.alloc(items.ItemDef, raw.len);
    for (raw, out) |src, *dst| {
        if (src.slot != null and src.use != null) return error.ItemKindConflict;
        if (src.slot == null and src.use == null) return error.ItemKindMissing;
        const kind: items.ItemKind = if (src.slot) |slot|
            .{ .equipment = .{ .slot = slot, .mods = src.mods } }
        else if (src.use) |use|
            .{ .consumable = .{ .use = use } }
        else
            .quest;
        dst.* = .{
            .id = src.id,
            .name = src.name,
            .quality = src.quality,
            .drop = .{ .classes = src.classes, .weight = src.weight },
            .kind = kind,
            .description = src.description,
        };
    }
    return out;
}
const EnemiesFile = struct { version: u32 = 1, enemies: []const EnemyDef = &.{} };
const SkillsFile = struct { version: u32 = 1, skills: []const SkillDef = &.{} };

const parse_options: std.json.ParseOptions = .{
    .ignore_unknown_fields = true,
    .allocate = .alloc_always,
};

fn parseFile(
    comptime T: type,
    arena: std.mem.Allocator,
    file: []const u8,
    bytes: []const u8,
    report: *Report,
) ?T {
    const value = std.json.parseFromSliceLeaky(T, arena, bytes, parse_options) catch |err| {
        report.add(file, "JSON 解析失败", @errorName(err));
        return null;
    };
    return value;
}

pub fn load(allocator: std.mem.Allocator) !Content {
    return loadFrom(allocator, embedded.items_json, embedded.enemies_json, embedded.skills_json);
}

/// Same as load() but with explicit byte slices; used by tests to prove that
/// broken data falls back instead of crashing.
pub fn loadFrom(
    allocator: std.mem.Allocator,
    items_bytes: []const u8,
    enemies_bytes: []const u8,
    skills_bytes: []const u8,
) !Content {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const arena_alloc = arena.allocator();

    var report = Report{};

    var item_list: []const items.ItemDef = &builtin_items;
    var items_ok = false;
    if (parseFile(ItemsFile, arena_alloc, file_items, items_bytes, &report)) |file| {
        if (convertItems(arena_alloc, file.items)) |converted| {
            if (validateItems(converted, &report)) {
                item_list = converted;
                items_ok = true;
            }
        } else |err| {
            report.add(file_items, "物品 kind 冲突（slot 与 use 同时存在）", @errorName(err));
        }
    }
    if (!items_ok) report.items = .fallback;

    var skill_list: []const SkillDef = &builtin_skills;
    if (parseFile(SkillsFile, arena_alloc, file_skills, skills_bytes, &report)) |file| {
        if (validateSkills(file.skills, &report)) {
            skill_list = file.skills;
        } else {
            report.skills = .fallback;
        }
    } else {
        report.skills = .fallback;
    }

    var enemy_list: []const EnemyDef = &builtin_enemies;
    if (parseFile(EnemiesFile, arena_alloc, file_enemies, enemies_bytes, &report)) |file| {
        if (validateEnemies(file.enemies, &report) and
            validateEnemySkills(file.enemies, skill_list, &report))
        {
            enemy_list = file.enemies;
        } else {
            report.enemies = .fallback;
        }
    } else {
        report.enemies = .fallback;
    }

    return .{
        .arena = arena,
        .items = item_list,
        .enemies = enemy_list,
        .skills = skill_list,
        .report = report,
    };
}

// -------------------------------------------------------------- validation

fn finiteInRange(value: f32, lo: f32, hi: f32) bool {
    return std.math.isFinite(value) and value >= lo and value <= hi;
}

fn validateItems(list: []const items.ItemDef, report: *Report) bool {
    var ok = true;
    for (list, 0..) |def, i| {
        if (def.id.len == 0) {
            report.add(file_items, "物品缺少 id", "");
            ok = false;
        }
        if (def.name.len == 0) {
            report.add(file_items, "物品缺少名称", def.id);
            ok = false;
        }
        for (list[0..i]) |prev| {
            if (def.id.len > 0 and std.mem.eql(u8, prev.id, def.id)) {
                report.add(file_items, "物品 id 重复", def.id);
                ok = false;
            }
        }
        if (!finiteInRange(def.drop.weight, 0, 100)) {
            report.add(file_items, "掉落权重超出范围", def.id);
            ok = false;
        }
        switch (def.kind) {
            .equipment => |equipment| {
                for (equipment.mods) |mod| {
                    if (!finiteInRange(mod.flat, -1000, 1000)) {
                        report.add(file_items, "flat 修正超出范围", def.id);
                        ok = false;
                    }
                    if (!finiteInRange(mod.pct, attributes.caps.pct_min, attributes.caps.pct_max)) {
                        report.add(file_items, "pct 修正超出范围", def.id);
                        ok = false;
                    }
                }
            },
            .consumable => |consumable| {
                if (!finiteInRange(consumable.use.heal, 0, 10000) or !finiteInRange(consumable.use.resource, 0, 10000)) {
                    report.add(file_items, "消耗品效果超出范围", def.id);
                    ok = false;
                }
            },
            .quest => {},
        }
    }
    return ok;
}

fn validateEnemies(list: []const EnemyDef, report: *Report) bool {
    var ok = true;
    for (list, 0..) |def, i| {
        if (def.id.len == 0) {
            report.add(file_enemies, "敌人缺少 id", "");
            ok = false;
        }
        if (def.name.len == 0) {
            report.add(file_enemies, "敌人缺少名称", def.id);
            ok = false;
        }
        if (def.model.len == 0) {
            report.add(file_enemies, "敌人缺少模型", def.id);
            ok = false;
        }
        for (list[0..i]) |prev| {
            if (def.id.len > 0 and std.mem.eql(u8, prev.id, def.id)) {
                report.add(file_enemies, "敌人 id 重复", def.id);
                ok = false;
            }
            if (prev.kind == def.kind) {
                report.add(file_enemies, "敌人 kind 重复", def.id);
                ok = false;
            }
        }
        if (!finiteInRange(def.hp, 1, 100000)) {
            report.add(file_enemies, "敌人 HP 非法", def.id);
            ok = false;
        }
        if (!finiteInRange(def.damage, 0, 10000)) {
            report.add(file_enemies, "敌人攻击非法", def.id);
            ok = false;
        }
        if (!finiteInRange(def.armor, 0, 10000)) {
            report.add(file_enemies, "敌人护甲非法", def.id);
            ok = false;
        }
        if (def.speed < 1 or def.speed > 999) {
            report.add(file_enemies, "敌人速度非法", def.id);
            ok = false;
        }
        if (def.attack_range < 1 or def.attack_range > 20) {
            report.add(file_enemies, "敌人攻击距离非法", def.id);
            ok = false;
        }
        if (def.attack_cooldown_turns < 1 or def.attack_cooldown_turns > 100) {
            report.add(file_enemies, "敌人攻击冷却回合非法", def.id);
            ok = false;
        }
        if (!finiteInRange(def.scale, 0.01, 100)) {
            report.add(file_enemies, "敌人缩放非法", def.id);
            ok = false;
        }
        if (!finiteInRange(def.drop_chance, 0, 1)) {
            report.add(file_enemies, "掉落概率必须在 0..1", def.id);
            ok = false;
        }
        if (def.elite and def.boss) {
            report.add(file_enemies, "敌人不能同时是精英和 Boss", def.id);
            ok = false;
        }
        if (def.min_layer < 1 or def.min_layer > 3 or def.max_layer < def.min_layer or def.max_layer > 3) {
            report.add(file_enemies, "敌人层数范围非法", def.id);
            ok = false;
        }
    }
    return ok;
}

fn validateSkills(list: []const SkillDef, report: *Report) bool {
    var ok = true;
    for (list, 0..) |def, i| {
        if (def.id.len == 0) {
            report.add(file_skills, "技能缺少 id", "");
            ok = false;
        }
        if (def.name.len == 0) {
            report.add(file_skills, "技能缺少名称", def.id);
            ok = false;
        }
        for (list[0..i]) |prev| {
            if (def.id.len > 0 and std.mem.eql(u8, prev.id, def.id)) {
                report.add(file_skills, "技能 id 重复", def.id);
                ok = false;
            }
        }
        switch (def.kind) {
            .player => if (def.class == null) {
                report.add(file_skills, "玩家技能缺少职业", def.id);
                ok = false;
            },
            .enemy => if (def.class != null) {
                report.add(file_skills, "敌人技能不应带职业", def.id);
                ok = false;
            },
        }
        if (def.cost > 1000) {
            report.add(file_skills, "技能资源消耗过大", def.id);
            ok = false;
        }
        if (def.cooldown_turns > 100) {
            report.add(file_skills, "技能冷却回合过大", def.id);
            ok = false;
        }
        if (def.range_cells > 50 or def.teleport_cells > 50 or def.knockback_cells > 50) {
            report.add(file_skills, "技能距离非法", def.id);
            ok = false;
        }
        if (!finiteInRange(def.damage_mult, 0, 1000) or !finiteInRange(def.flat_damage, 0, 100000)) {
            report.add(file_skills, "技能伤害非法", def.id);
            ok = false;
        }
        if (!finiteInRange(def.aoe_cells, 0, 100)) {
            report.add(file_skills, "技能范围非法", def.id);
            ok = false;
        }
        if (!finiteInRange(def.buff_pct, 0, 10)) {
            report.add(file_skills, "技能增益比例非法", def.id);
            ok = false;
        }
        if (!finiteInRange(def.slow_pct, 0, 1)) {
            report.add(file_skills, "技能减速比例必须在 0..1", def.id);
            ok = false;
        }
        if (!validateSkillEffect(def, report)) ok = false;
    }
    return ok;
}

/// Effect-specific sanity: a charge needs knockback, a blink needs a range,
/// a buff/stun/recall needs a duration, and damage talents need damage.
fn validateSkillEffect(def: SkillDef, report: *Report) bool {
    var ok = true;
    const damaging = switch (def.effect) {
        .damage, .damage_knockback, .damage_slow => true,
        else => false,
    };
    if (damaging and def.damage_mult <= 0 and def.flat_damage <= 0) {
        report.add(file_skills, "伤害类天赋没有任何伤害", def.id);
        ok = false;
    }
    switch (def.effect) {
        .damage => {},
        .damage_knockback => if (def.knockback_cells == 0) {
            report.add(file_skills, "冲锋缺少击退格数", def.id);
            ok = false;
        },
        .attack_buff => if (def.buff_pct <= 0 or def.duration_turns == 0) {
            report.add(file_skills, "战吼缺少攻击加成或持续回合", def.id);
            ok = false;
        },
        .blink => if (def.teleport_cells == 0) {
            report.add(file_skills, "闪现缺少传送格数", def.id);
            ok = false;
        },
        .damage_slow => if (def.slow_pct <= 0 or def.duration_turns == 0) {
            report.add(file_skills, "减速天赋缺少减速比例或持续回合", def.id);
            ok = false;
        },
        .stun => if (def.duration_turns == 0) {
            report.add(file_skills, "时间停滞缺少持续回合", def.id);
            ok = false;
        },
        .recall => if (def.duration_turns == 0) {
            report.add(file_skills, "回溯缺少回溯回合数", def.id);
            ok = false;
        },
    }
    return ok;
}

fn validateEnemySkills(enemies: []const EnemyDef, skills: []const SkillDef, report: *Report) bool {
    var ok = true;
    for (enemies) |def| {
        const id = def.skill orelse continue;
        const found = findSkill(skills, id) orelse {
            report.add(file_enemies, "敌人引用了不存在的技能", id);
            ok = false;
            continue;
        };
        if (found.kind != .enemy) {
            report.add(file_enemies, "敌人重击必须引用 enemy 技能", id);
            ok = false;
        }
    }
    return ok;
}

// ------------------------------------------------------------------- tests

test "embedded content parses, validates and matches builtin defaults" {
    var content = try load(std.testing.allocator);
    defer content.deinit();

    try std.testing.expect(content.report.ok());
    try std.testing.expect(!content.usingFallback());
    try std.testing.expectEqual(Source.embedded, content.report.items);
    try std.testing.expectEqual(Source.embedded, content.report.enemies);
    try std.testing.expectEqual(Source.embedded, content.report.skills);

    try std.testing.expectEqual(builtin_items.len, content.items.len);
    try std.testing.expectEqual(builtin_enemies.len, content.enemies.len);
    try std.testing.expectEqual(builtin_skills.len, content.skills.len);
    for (builtin_items, 0..) |expected, i| {
        try std.testing.expectEqualDeep(expected, content.items[i]);
    }
    for (builtin_enemies, 0..) |expected, i| {
        try std.testing.expectEqualDeep(expected, content.enemies[i]);
    }
    for (builtin_skills, 0..) |expected, i| {
        try std.testing.expectEqualDeep(expected, content.skills[i]);
    }
}

test "embedded tables match the RUN v1 content plan" {
    var content = try load(std.testing.allocator);
    defer content.deinit();

    try std.testing.expectEqual(@as(usize, 8), content.items.len);
    try std.testing.expectEqual(@as(usize, 6), content.enemies.len);
    try std.testing.expectEqual(@as(usize, 10), content.skills.len);

    const sword = content.item("iron_sword") orelse return error.MissingItem;
    try std.testing.expectEqual(items.Slot.main_hand, sword.slot().?);
    try std.testing.expectEqual(items.Quality.common, sword.quality);
    try std.testing.expectEqual(attributes.StatRef.attack, sword.mods()[0].stat);
    try std.testing.expectEqual(@as(f32, 6), sword.mods()[0].flat);

    const potion = content.item("healing_potion") orelse return error.MissingItem;
    try std.testing.expect(!potion.isEquippable());
    try std.testing.expectEqual(@as(f32, 40), potion.use().?.heal);

    const sigil = content.item("gear_sigil") orelse return error.MissingItem;
    try std.testing.expectEqual(items.Quality.epic, sigil.quality);
    try std.testing.expect(sigil.allowsClass(.chronomancer));

    const boss = content.enemy("abyss_guard") orelse return error.MissingEnemy;
    try std.testing.expect(boss.boss);
    try std.testing.expectEqual(@as(f32, 420), boss.hp);

    const heavy = content.skill("heavy_strike") orelse return error.MissingSkill;
    try std.testing.expectEqual(SkillKind.player, heavy.kind);
    try std.testing.expectEqual(attributes.Class.warrior, heavy.class.?);
    try std.testing.expectEqual(@as(u16, 4), heavy.cooldown_turns);
    try std.testing.expectEqual(@as(f32, 2.0), heavy.damage_mult);

    // 每个职业 3 个天赋，顺序就是热键 1/2/3。
    var hotbar: [4]*const SkillDef = undefined;
    const warrior_talents = content.talentsFor(.warrior, &hotbar);
    try std.testing.expectEqual(@as(usize, 3), warrior_talents.len);
    try std.testing.expectEqualStrings("heavy_strike", warrior_talents[0].id);
    try std.testing.expectEqualStrings("charge", warrior_talents[1].id);
    try std.testing.expectEqualStrings("war_cry", warrior_talents[2].id);

    const mage_talents = content.talentsFor(.mage, &hotbar);
    try std.testing.expectEqual(@as(usize, 3), mage_talents.len);
    try std.testing.expectEqual(SkillEffect.blink, mage_talents[2].effect);

    // 敌人技能引用必须解析到 enemy 技能。
    for (content.enemies) |def| {
        const id = def.skill orelse continue;
        const skill = content.skill(id) orelse return error.MissingSkill;
        try std.testing.expectEqual(SkillKind.enemy, skill.kind);
        try std.testing.expect(skill.flat_damage > 0);
    }
}

test "broken JSON falls back to builtin defaults without crashing" {
    var content = try loadFrom(std.testing.allocator, "{ this is not json", embedded.enemies_json, embedded.skills_json);
    defer content.deinit();

    try std.testing.expectEqual(Source.fallback, content.report.items);
    try std.testing.expectEqual(Source.embedded, content.report.enemies);
    try std.testing.expectEqual(Source.embedded, content.report.skills);
    try std.testing.expect(content.report.issue_count > 0);
    try std.testing.expect(content.usingFallback());
    try std.testing.expectEqual(builtin_items.len, content.items.len);
    try std.testing.expectEqualDeep(builtin_items[0], content.items[0]);
}

test "duplicate ids are rejected and fall back" {
    const bad_items =
        \\{ "version": 1, "items": [
        \\  { "id": "dup", "name": "甲", "slot": "body" },
        \\  { "id": "dup", "name": "乙", "slot": "body" }
        \\] }
    ;
    var content = try loadFrom(std.testing.allocator, bad_items, embedded.enemies_json, embedded.skills_json);
    defer content.deinit();

    try std.testing.expectEqual(Source.fallback, content.report.items);
    try std.testing.expectEqual(Source.embedded, content.report.enemies);
    try std.testing.expectEqual(builtin_items.len, content.items.len);
}

test "item with both slot and use is rejected" {
    const bad_items =
        \\{ "version": 1, "items": [
        \\  { "id": "bad", "name": "坏物品", "slot": "body", "use": { "heal": 10 } }
        \\] }
    ;
    var content = try loadFrom(std.testing.allocator, bad_items, embedded.enemies_json, embedded.skills_json);
    defer content.deinit();

    try std.testing.expectEqual(Source.fallback, content.report.items);
    try std.testing.expect(content.report.issue_count > 0);
    try std.testing.expectEqual(builtin_items.len, content.items.len);
}

test "enemy referencing an unknown skill is rejected" {
    const bad_enemies =
        \\{ "version": 1, "enemies": [
        \\  { "id": "x", "name": "测试怪", "model": "skeleton", "kind": 9, "hp": 10, "damage": 1,
        \\    "speed": 100, "attack_range": 1, "attack_cooldown_turns": 1, "skill": "meteor" }
        \\] }
    ;
    var content = try loadFrom(std.testing.allocator, embedded.items_json, bad_enemies, embedded.skills_json);
    defer content.deinit();

    try std.testing.expectEqual(Source.fallback, content.report.enemies);
    try std.testing.expectEqual(Source.embedded, content.report.items);
    try std.testing.expectEqual(builtin_enemies.len, content.enemies.len);
}

test "enemy skill must be an enemy-kind skill" {
    const bad_enemies =
        \\{ "version": 1, "enemies": [
        \\  { "id": "x", "name": "测试怪", "model": "skeleton", "kind": 9, "hp": 10, "damage": 1,
        \\    "speed": 100, "attack_range": 1, "attack_cooldown_turns": 1, "skill": "fireball" }
        \\] }
    ;
    var content = try loadFrom(std.testing.allocator, embedded.items_json, bad_enemies, embedded.skills_json);
    defer content.deinit();

    try std.testing.expectEqual(Source.fallback, content.report.enemies);
}

test "invalid numbers are rejected" {
    const bad_skills =
        \\{ "version": 1, "skills": [
        \\  { "id": "bad", "name": "坏技能", "kind": "player", "damage_mult": -1 }
        \\] }
    ;
    var content = try loadFrom(std.testing.allocator, embedded.items_json, embedded.enemies_json, bad_skills);
    defer content.deinit();

    try std.testing.expectEqual(Source.fallback, content.report.skills);
    // enemies still load against the built-in skill table.
    try std.testing.expectEqual(Source.embedded, content.report.enemies);
    try std.testing.expectEqual(builtin_skills.len, content.skills.len);
}

test "loot roll honours drop chance and class pools" {
    var content = try load(std.testing.allocator);
    defer content.deinit();

    const skeleton = content.enemy("skeleton") orelse return error.MissingEnemy;
    try std.testing.expect(content.rollDrop(.warrior, 0.9, 0.0, skeleton) == null);

    const drop = content.rollDrop(.warrior, 0.1, 0.0, skeleton) orelse return error.NoDrop;
    try std.testing.expect(content.items[drop].allowsClass(.warrior));

    const mage_drop = content.rollDrop(.mage, 0.1, 0.999, skeleton) orelse return error.NoDrop;
    try std.testing.expect(content.items[mage_drop].allowsClass(.mage));
}

test "report writer prints issues" {
    var report = Report{};
    report.add(file_items, "测试问题", "subject");
    var buf: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try report.write(&writer);
    const text = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, text, "测试问题") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "subject") != null);
}
