//! Numeric components shared by Sim actors. Storage follows mech.zig:
//! gauges for current/max resources, Value for derived numeric sheets.
//! Formulas stay in attributes.zig; this module only owns component types.
const mech = @import("../core/mech.zig");
const attributes = @import("attributes.zig");

pub const HealthTag = struct {};
pub const Health = mech.SimpleGauge(HealthTag, .{ .default = 1, .clamp = true });

pub const ResourceTag = struct {};
pub const Resource = mech.SimpleGauge(ResourceTag, .{ .default = 1, .clamp = true });

pub const RegenTag = struct {};
pub const Regen = mech.Value(RegenTag, 8);

pub const StrengthTag = struct {};
pub const AgilityTag = struct {};
pub const ConstitutionTag = struct {};
pub const PerceptionTag = struct {};
pub const MagicTag = struct {};
pub const WillTag = struct {};

pub const Strength = mech.Value(StrengthTag, 0);
pub const Agility = mech.Value(AgilityTag, 0);
pub const Constitution = mech.Value(ConstitutionTag, 0);
pub const Perception = mech.Value(PerceptionTag, 0);
pub const Magic = mech.Value(MagicTag, 0);
pub const Will = mech.Value(WillTag, 0);

/// Six independent Value components. Equipment mods still go through
/// attributes.recompute; this sheet stores the unmodified base/current points.
pub const PrimarySheet = struct {
    strength: Strength = .{},
    agility: Agility = .{},
    constitution: Constitution = .{},
    perception: Perception = .{},
    magic: Magic = .{},
    will: Will = .{},

    pub fn fromArray(v: [6]f32) PrimarySheet {
        var sheet = PrimarySheet{};
        inline for (0..6) |i| sheet.set(@fromBackingInt(@intCast(i)), v[i]);
        return sheet;
    }

    pub fn toArray(self: PrimarySheet) [6]f32 {
        return .{ self.strength.val, self.agility.val, self.constitution.val, self.perception.val, self.magic.val, self.will.val };
    }

    pub fn get(self: PrimarySheet, kind: attributes.StatKind) f32 {
        return switch (kind) {
            .strength => self.strength.val,
            .agility => self.agility.val,
            .constitution => self.constitution.val,
            .perception => self.perception.val,
            .magic => self.magic.val,
            .will => self.will.val,
        };
    }

    pub fn set(self: *PrimarySheet, kind: attributes.StatKind, value: f32) void {
        switch (kind) {
            .strength => self.strength = .{ .base = value, .val = value },
            .agility => self.agility = .{ .base = value, .val = value },
            .constitution => self.constitution = .{ .base = value, .val = value },
            .perception => self.perception = .{ .base = value, .val = value },
            .magic => self.magic = .{ .base = value, .val = value },
            .will => self.will = .{ .base = value, .val = value },
        }
    }

    pub fn add(self: *PrimarySheet, kind: attributes.StatKind, delta: f32) void {
        self.set(kind, self.get(kind) + delta);
    }
};

pub const LifeState = struct {
    alive: bool = true,
};

/// Start a gauge at a concrete full/current value (spawn, load, tests).
pub fn gaugeFull(comptime G: type, value: f32) G {
    var gauge = G{};
    gauge.setFull(value);
    gauge.val = gauge.full;
    return gauge;
}

pub fn gaugeAt(comptime G: type, full: f32, current: f32) G {
    var gauge = gaugeFull(G, full);
    gauge.set(current);
    return gauge;
}
