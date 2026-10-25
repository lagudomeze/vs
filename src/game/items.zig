//! Item definitions, equipment slots, inventory and equipment modifiers.
//!
//! v1 uses three slots (主手 / 身 / 饰品) out of a six-slot data model, so
//! unlocking 头/手/脚 later does not change the save/inventory layout.
//! The eight shipped items live in assets/data/items.json and are parsed by
//! content.zig; this file stays data-agnostic and pure.

const std = @import("std");
const attributes = @import("attributes.zig");
const color = @import("../core/color.zig");

/// Six equipment slots. v1 only enables main_hand / body / trinket.
pub const Slot = enum(u8) { main_hand, body, trinket, head, hands, feet };

pub const slot_count = @typeInfo(Slot).@"enum".field_names.len;

/// Slots wired up in v1 (docs/TACTICAL_V1.md 第 6 节).
pub const v1_slots = [_]Slot{ .main_hand, .body, .trinket };

pub fn label(slot: Slot) []const u8 {
    return switch (slot) {
        .main_hand => "主手",
        .body => "身",
        .trinket => "饰品",
        .head => "头",
        .hands => "手",
        .feet => "脚",
    };
}

/// 品质：普通灰白、稀有蓝、史诗紫、首领金（docs/BALANCE_V1.md 第 7 节）。
pub const Quality = enum(u8) { common, rare, epic, boss };

pub fn qualityLabel(quality: Quality) []const u8 {
    return switch (quality) {
        .common => "普通",
        .rare => "稀有",
        .epic => "史诗",
        .boss => "首领",
    };
}

/// Packed tint for the HUD / combat log.
pub fn qualityTint(quality: Quality) u32 {
    return switch (quality) {
        .common => color.pack(200, 204, 212),
        .rare => color.pack(91, 155, 213),
        .epic => color.pack(155, 89, 182),
        .boss => color.pack(234, 166, 46),
    };
}

/// Index into a loaded ItemDef table (content.zig owns the table).
pub const ItemId = u16;

/// Consumable effect; v1 only has the healing potion.
pub const Use = struct {
    heal: f32 = 0,
    /// 资源回复（精力 / 法力 / 悖论）。
    resource: f32 = 0,
    /// 对英雄周围敌人造成的范围伤害；0 表示不是炸弹。
    bomb: f32 = 0,
    /// 炸弹半径（曼哈顿格）。
    bomb_radius: f32 = 0,
};

/// Loot-only metadata. Kept out of the kind union because every droppable
/// item shares it.
pub const DropRule = struct {
    /// Classes this item may drop for; empty means all classes.
    classes: []const attributes.Class = &.{},
    /// Loot weight inside the class pool.
    weight: f32 = 1.0,
};

pub const Equipment = struct {
    slot: Slot,
    /// flat / pct 修正，见 attributes.Modifier。
    mods: []const attributes.Modifier = &.{},
};

pub const Consumable = struct {
    use: Use,
};

/// Items are one of three shapes; illegal combinations (equipment with a
/// potion effect etc.) are unrepresentable instead of being null-checked.
pub const ItemKind = union(enum) {
    equipment: Equipment,
    consumable: Consumable,
    quest,
};

pub const ItemDef = struct {
    id: []const u8,
    name: []const u8,
    quality: Quality = .common,
    drop: DropRule = .{},
    kind: ItemKind = .quest,
    description: []const u8 = "",

    pub fn isEquippable(self: ItemDef) bool {
        return self.kind == .equipment;
    }

    pub fn slot(self: ItemDef) ?Slot {
        return switch (self.kind) {
            .equipment => |equipment| equipment.slot,
            else => null,
        };
    }

    pub fn mods(self: ItemDef) []const attributes.Modifier {
        return switch (self.kind) {
            .equipment => |equipment| equipment.mods,
            else => &.{},
        };
    }

    pub fn use(self: ItemDef) ?Use {
        return switch (self.kind) {
            .consumable => |consumable| consumable.use,
            else => null,
        };
    }

    /// Empty class list == 全职业.
    pub fn allowsClass(self: ItemDef, class: attributes.Class) bool {
        if (self.drop.classes.len == 0) return true;
        for (self.drop.classes) |allowed| {
            if (allowed == class) return true;
        }
        return false;
    }
};

/// Fixed equipment array; ?ItemId == empty.
pub const EquipmentSlots = struct {
    slots: [slot_count]?ItemId = @splat(null),

    pub fn get(self: *const EquipmentSlots, slot: Slot) ?ItemId {
        return self.slots[@backingInt(slot)];
    }

    pub fn set(self: *EquipmentSlots, slot: Slot, item: ?ItemId) void {
        self.slots[@backingInt(slot)] = item;
    }

    pub fn equippedCount(self: *const EquipmentSlots) usize {
        var n: usize = 0;
        for (self.slots) |maybe| {
            if (maybe != null) n += 1;
        }
        return n;
    }

    pub fn clear(self: *EquipmentSlots) void {
        self.slots = @splat(null);
    }
};

/// Fixed bag size; loot is auto-picked up until full.
pub const max_inventory: usize = 12;
/// Capacity for a full six-slot v1 loadout (24 modifier slots is plenty).
pub const max_equipment_mods: usize = 24;

pub const EquipError = error{ UnknownItem, NotEquippable, NotInInventory };
pub const UnequipError = error{ SlotEmpty, InventoryFull };

pub const Inventory = struct {
    items: [max_inventory]ItemId = @splat(0),
    len: usize = 0,
    equipped: EquipmentSlots = .{},

    pub fn init() Inventory {
        return .{};
    }

    pub fn isFull(self: *const Inventory) bool {
        return self.len >= max_inventory;
    }

    pub fn count(self: *const Inventory) usize {
        return self.len;
    }

    pub fn at(self: *const Inventory, index: usize) ItemId {
        return self.items[index];
    }

    pub fn slice(self: *const Inventory) []const ItemId {
        return self.items[0..self.len];
    }

    pub fn has(self: *const Inventory, item: ItemId) bool {
        for (self.slice()) |it| {
            if (it == item) return true;
        }
        return false;
    }

    /// Adds one item; returns false when the bag is full.
    pub fn pickup(self: *Inventory, item: ItemId) bool {
        if (self.isFull()) return false;
        self.items[self.len] = item;
        self.len += 1;
        return true;
    }

    /// Removes the first matching item; returns false when absent.
    pub fn remove(self: *Inventory, item: ItemId) bool {
        var i: usize = 0;
        while (i < self.len) : (i += 1) {
            if (self.items[i] != item) continue;
            self.len -= 1;
            self.items[i] = self.items[self.len];
            return true;
        }
        return false;
    }

    /// Moves an item from the bag into its slot; a replaced item goes back to
    /// the bag. The caller must recompute stats afterwards (see ModifierSet).
    pub fn equip(self: *Inventory, defs: []const ItemDef, item: ItemId) EquipError!void {
        if (item >= defs.len) return error.UnknownItem;
        const def = defs[item];
        const slot = def.slot() orelse return error.NotEquippable;
        if (!self.remove(item)) return error.NotInInventory;
        if (self.equipped.get(slot)) |replaced| {
            // remove() just freed a bag slot, so this always fits.
            _ = self.pickup(replaced);
        }
        self.equipped.set(slot, item);
    }

    /// Moves the equipped item back into the bag; fails when the bag is full.
    pub fn unequip(self: *Inventory, slot: Slot) UnequipError!ItemId {
        const item = self.equipped.get(slot) orelse return error.SlotEmpty;
        if (self.isFull()) return error.InventoryFull;
        _ = self.pickup(item);
        self.equipped.set(slot, null);
        return item;
    }
};

/// Fixed-capacity modifier list assembled from equipped items. Either call
/// rebuild() after any equipment change, or applyItem()/removeItem() around a
/// single equip/unequip; both produce the same list.
pub const ModifierSet = struct {
    mods: [max_equipment_mods]attributes.Modifier = undefined,
    owners: [max_equipment_mods]ItemId = undefined,
    len: usize = 0,

    pub fn slice(self: *const ModifierSet) []const attributes.Modifier {
        return self.mods[0..self.len];
    }

    pub fn clear(self: *ModifierSet) void {
        self.len = 0;
    }

    /// Appends every modifier of def, tagged as equipment. Modifiers beyond
    /// capacity are dropped (capacity covers a full v1 loadout).
    pub fn applyItem(self: *ModifierSet, item: ItemId, def: *const ItemDef) void {
        for (def.mods()) |mod| {
            if (self.len >= max_equipment_mods) return;
            self.mods[self.len] = .{
                .stat = mod.stat,
                .flat = mod.flat,
                .pct = mod.pct,
                .source = .equipment,
            };
            self.owners[self.len] = item;
            self.len += 1;
        }
    }

    /// Removes every modifier owned by item; the remaining order is kept.
    pub fn removeItem(self: *ModifierSet, item: ItemId) void {
        var i: usize = 0;
        while (i < self.len) {
            if (self.owners[i] != item) {
                i += 1;
                continue;
            }
            var j = i;
            while (j + 1 < self.len) : (j += 1) {
                self.mods[j] = self.mods[j + 1];
                self.owners[j] = self.owners[j + 1];
            }
            self.len -= 1;
        }
    }

    /// Rebuilds the whole set from the current equipment (idempotent).
    pub fn rebuild(self: *ModifierSet, defs: []const ItemDef, equipped: *const EquipmentSlots) void {
        self.clear();
        for (equipped.slots) |maybe| {
            const item = maybe orelse continue;
            if (item < defs.len) self.applyItem(item, &defs[item]);
        }
    }
};

/// Convenience: compute the full sheet for a loadout without keeping a
/// ModifierSet around (used by tests, HUD panels and one-shot tooltips).
pub fn sheetFor(
    defs: []const ItemDef,
    equipped: *const EquipmentSlots,
    base: attributes.Stats,
    class: attributes.Class,
) attributes.Sheet {
    var set = ModifierSet{};
    set.rebuild(defs, equipped);
    return attributes.recompute(base, set.slice(), class);
}

/// Convenience: copy the equipment modifier list into a caller buffer.
pub fn collectModifiers(
    defs: []const ItemDef,
    equipped: *const EquipmentSlots,
    out: []attributes.Modifier,
) []attributes.Modifier {
    var set = ModifierSet{};
    set.rebuild(defs, equipped);
    const n = @min(out.len, set.len);
    for (set.mods[0..n], 0..) |mod, i| out[i] = mod;
    return out[0..n];
}

// ---------------------------------------------------------- character panel

/// One equipment slot as the character panel needs it.
pub const PanelSlot = struct {
    slot: Slot,
    item: ?ItemId = null,
    def: ?*const ItemDef = null,
};

/// Everything the character panel / HUD needs in one value: 六属性, HP/资源,
/// 装备槽, 背包物品, 等级/XP. bag and slots[].def borrow from the caller's
/// Inventory and ItemDef table, so keep both alive while the panel is used.
pub const CharacterPanel = struct {
    class: attributes.Class,
    level: u16,
    xp: u32,
    xp_to_next: u32,
    hp: f32,
    hp_max: f32,
    resource: f32,
    resource_max: f32,
    speed: f32,
    stats: [attributes.stat_count]f32,
    derived: attributes.Derived,
    slots: [slot_count]PanelSlot,
    bag: []const ItemId,

    pub fn stat(self: CharacterPanel, kind: attributes.StatKind) f32 {
        return self.stats[@backingInt(kind)];
    }

    pub fn equipped(self: CharacterPanel, slot: Slot) ?ItemId {
        return self.slots[@backingInt(slot)].item;
    }

    pub fn bagCount(self: CharacterPanel) usize {
        return self.bag.len;
    }

    pub fn resourceLabel(self: CharacterPanel) []const u8 {
        return attributes.resourceLabel(self.class);
    }
};

/// Builds the UI-facing panel for one character. hp/resource are the current
/// values the game keeps outside this module.
pub fn panelFor(
    defs: []const ItemDef,
    inv: *const Inventory,
    base: attributes.Stats,
    class: attributes.Class,
    progress: attributes.Progression,
    hp: f32,
    resource: f32,
) CharacterPanel {
    const sheet = sheetFor(defs, &inv.equipped, base, class);
    var panel = CharacterPanel{
        .class = class,
        .level = progress.level,
        .xp = progress.xp,
        .xp_to_next = progress.xpToNext(),
        .hp = hp,
        .hp_max = sheet.derived.hp_max,
        .resource = resource,
        .resource_max = sheet.derived.resource_max,
        .speed = sheet.derived.speed,
        .stats = sheet.stats,
        .derived = sheet.derived,
        .slots = undefined,
        .bag = inv.slice(),
    };
    for (&panel.slots, 0..) |*entry, i| {
        const slot: Slot = @fromBackingInt(@intCast(i));
        const item = inv.equipped.get(slot);
        var def: ?*const ItemDef = null;
        if (item) |id| {
            if (id < defs.len) def = &defs[id];
        }
        entry.* = .{ .slot = slot, .item = item, .def = def };
    }
    return panel;
}

// ------------------------------------------------------------------- tests

const test_defs = [_]ItemDef{
    .{ .id = "test_sword", .name = "测试铁剑", .drop = .{ .classes = &.{.warrior} }, .kind = .{ .equipment = .{
        .slot = .main_hand,
        .mods = &.{
            .{ .stat = .strength, .flat = 6 },
            .{ .stat = .attack, .flat = 4 },
        },
    } } },
    .{ .id = "test_armor", .name = "测试皮甲", .quality = .rare, .kind = .{ .equipment = .{
        .slot = .body,
        .mods = &.{
            .{ .stat = .hp_max, .flat = 20 },
            .{ .stat = .armor, .flat = 3 },
        },
    } } },
    .{ .id = "test_charm", .name = "测试护符", .kind = .{ .equipment = .{
        .slot = .trinket,
        .mods = &.{
            .{ .stat = .strength, .pct = 0.5 },
        },
    } } },
    .{ .id = "test_potion", .name = "测试瓶", .kind = .{ .consumable = .{ .use = .{ .heal = 40 } } } },
    .{ .id = "test_dagger", .name = "测试短刃", .kind = .{ .equipment = .{
        .slot = .main_hand,
        .mods = &.{
            .{ .stat = .agility, .flat = 3 },
        },
    } } },
};

const expectApprox = std.testing.expectApproxEqAbs;

test "equipping and unequipping changes derived stats immediately" {
    var inv = Inventory.init();
    const base = attributes.baseStats(.warrior);
    const before = sheetFor(&test_defs, &inv.equipped, base, .warrior);

    try std.testing.expect(inv.pickup(0));
    try inv.equip(&test_defs, 0);
    const armed = sheetFor(&test_defs, &inv.equipped, base, .warrior);
    // +6 力量 and +4 攻击: 18 + 22*1.2 + 4 == 48.4
    try expectApprox(@as(f32, 48.4), armed.derived.attack, 0.001);
    try std.testing.expect(armed.derived.attack > before.derived.attack);
    try std.testing.expectEqual(@as(usize, 0), inv.count());

    const removed = try inv.unequip(.main_hand);
    try std.testing.expectEqual(@as(ItemId, 0), removed);
    const after = sheetFor(&test_defs, &inv.equipped, base, .warrior);
    try expectApprox(before.derived.attack, after.derived.attack, 0.001);
    try std.testing.expectEqual(@as(usize, 1), inv.count());
}

test "armor items add flat HP and armor" {
    var inv = Inventory.init();
    _ = inv.pickup(1);
    try inv.equip(&test_defs, 1);
    const sheet = sheetFor(&test_defs, &inv.equipped, attributes.baseStats(.warrior), .warrior);
    try expectApprox(@as(f32, 204), sheet.derived.hp_max, 0.001); // 184 + 20
    try expectApprox(@as(f32, 12), sheet.derived.armor, 0.001); // 9 + 3
}

test "percentage modifiers scale the base stat" {
    var inv = Inventory.init();
    _ = inv.pickup(2);
    try inv.equip(&test_defs, 2);
    const sheet = sheetFor(&test_defs, &inv.equipped, attributes.baseStats(.warrior), .warrior);
    try expectApprox(@as(f32, 24), sheet.stat(.strength), 0.001); // 16 * 1.5
    try expectApprox(@as(f32, 46.8), sheet.derived.attack, 0.001); // 18 + 24*1.2
}

test "inventory capacity is fixed" {
    var inv = Inventory.init();
    var i: usize = 0;
    while (i < max_inventory) : (i += 1) {
        try std.testing.expect(inv.pickup(0));
    }
    try std.testing.expect(inv.isFull());
    try std.testing.expect(!inv.pickup(0));
    try std.testing.expectEqual(max_inventory, inv.count());
    try std.testing.expect(inv.remove(0));
    try std.testing.expect(!inv.isFull());
}

test "equipping the same slot returns the old item to the bag" {
    var inv = Inventory.init();
    _ = inv.pickup(0);
    try inv.equip(&test_defs, 0);
    _ = inv.pickup(4);
    try inv.equip(&test_defs, 4);
    try std.testing.expectEqual(@as(?ItemId, 4), inv.equipped.get(.main_hand));
    try std.testing.expect(inv.has(0));
    try std.testing.expectEqual(@as(usize, 1), inv.count());
}

test "unequip fails when the bag is full" {
    var inv = Inventory.init();
    _ = inv.pickup(0);
    try inv.equip(&test_defs, 0);
    var i: usize = 0;
    while (i < max_inventory) : (i += 1) _ = inv.pickup(1);
    try std.testing.expectError(error.InventoryFull, inv.unequip(.main_hand));
    try std.testing.expectEqual(@as(?ItemId, 0), inv.equipped.get(.main_hand));
}

test "consumables cannot be equipped and unknown ids are rejected" {
    var inv = Inventory.init();
    _ = inv.pickup(3);
    try std.testing.expectError(error.NotEquippable, inv.equip(&test_defs, 3));
    try std.testing.expect(inv.has(3));
    try std.testing.expectError(error.UnknownItem, inv.equip(&test_defs, 99));
    try std.testing.expectError(error.NotInInventory, inv.equip(&test_defs, 0));
    try std.testing.expectError(error.SlotEmpty, inv.unequip(.trinket));
}

test "modifier set applies and removes item modifiers" {
    var set = ModifierSet{};
    set.applyItem(0, &test_defs[0]);
    set.applyItem(1, &test_defs[1]);
    try std.testing.expectEqual(@as(usize, 4), set.len);
    for (set.slice()) |mod| try std.testing.expectEqual(attributes.ModifierSource.equipment, mod.source);

    set.removeItem(0);
    try std.testing.expectEqual(@as(usize, 2), set.len);
    try std.testing.expectEqual(attributes.StatRef.hp_max, set.slice()[0].stat);
    try std.testing.expectEqual(attributes.StatRef.armor, set.slice()[1].stat);

    set.clear();
    try std.testing.expectEqual(@as(usize, 0), set.len);
}

test "modifier set rebuild matches a manual apply" {
    var inv = Inventory.init();
    _ = inv.pickup(0);
    try inv.equip(&test_defs, 0);
    _ = inv.pickup(1);
    try inv.equip(&test_defs, 1);

    var rebuilt = ModifierSet{};
    rebuilt.rebuild(&test_defs, &inv.equipped);
    try std.testing.expectEqual(@as(usize, 4), rebuilt.len);
    try std.testing.expectEqual(attributes.StatRef.strength, rebuilt.slice()[0].stat);
    try std.testing.expectEqual(attributes.StatRef.attack, rebuilt.slice()[1].stat);
    try std.testing.expectEqual(attributes.StatRef.hp_max, rebuilt.slice()[2].stat);

    var buf: [max_equipment_mods]attributes.Modifier = undefined;
    const copied = collectModifiers(&test_defs, &inv.equipped, &buf);
    try std.testing.expectEqual(rebuilt.len, copied.len);
    try std.testing.expectEqual(rebuilt.slice()[2].flat, copied[2].flat);
}

test "class restrictions and quality labels" {
    try std.testing.expect(test_defs[0].allowsClass(.warrior));
    try std.testing.expect(!test_defs[0].allowsClass(.mage));
    try std.testing.expect(test_defs[1].allowsClass(.mage));
    try std.testing.expectEqualStrings("稀有", qualityLabel(.rare));
    try std.testing.expectEqualStrings("主手", label(.main_hand));
    try std.testing.expectEqual(@as(usize, 3), v1_slots.len);
}

test "character panel exposes stats, gear, bag and xp" {
    var inv = Inventory.init();
    _ = inv.pickup(0);
    try inv.equip(&test_defs, 0);
    _ = inv.pickup(1);
    try inv.equip(&test_defs, 1);
    _ = inv.pickup(3); // potion stays in the bag

    const progress = attributes.Progression{ .level = 2, .xp = 40 };
    const panel = panelFor(&test_defs, &inv, attributes.baseStats(.warrior), .warrior, progress, 100, 55);

    try std.testing.expectEqual(@as(u16, 2), panel.level);
    try std.testing.expectEqual(@as(u32, 40), panel.xp);
    try std.testing.expectEqual(@as(u32, 200), panel.xp_to_next);
    try std.testing.expectEqual(@as(f32, 100), panel.hp);
    try std.testing.expectApproxEqAbs(@as(f32, 204), panel.hp_max, 0.001); // 184 + 20
    try std.testing.expectEqual(@as(f32, 55), panel.resource);
    try std.testing.expectApproxEqAbs(@as(f32, 100), panel.resource_max, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), panel.speed, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 22), panel.stat(.strength), 0.001); // 16 + 6
    try std.testing.expectEqual(@as(usize, 1), panel.bagCount());
    try std.testing.expectEqual(@as(?ItemId, 0), panel.equipped(.main_hand));
    try std.testing.expectEqual(@as(?ItemId, 1), panel.equipped(.body));
    try std.testing.expect(panel.slots[2].def == null);
    try std.testing.expectEqualStrings("精力", panel.resourceLabel());
}
