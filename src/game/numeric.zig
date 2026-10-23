//! Numeric components shared by Sim actors. Storage follows mech.zig:
//! gauges for current/max resources, Value for derived numeric sheets.
//! Formulas stay in attributes.zig; this module only owns component types.
const mech = @import("../core/mech.zig");

pub const HealthTag = struct {};
pub const Health = mech.SimpleGauge(HealthTag, .{ .default = 1, .clamp = true });

pub const ResourceTag = struct {};
pub const Resource = mech.SimpleGauge(ResourceTag, .{ .default = 1, .clamp = true });

pub const RegenTag = struct {};
pub const Regen = mech.Value(RegenTag, 8);

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
