//! ECS component definitions.
const ecs = @import("zflecs");
const math = @import("../core/math.zig");
const rig = @import("../engine/rig.zig");

pub const Transform = struct {
    pos: math.Vec3 = math.Vec3.zero,
    yaw: f32 = 0,
    scale: f32 = 1.0,
};

pub const Velocity = struct {
    v: math.Vec3 = math.Vec3.zero,
};

pub const MoveIntent = struct {
    dir: math.Vec3 = math.Vec3.zero,
    speed: f32 = 0,
};

pub const Animation = struct {
    state: rig.AnimState = .{},
};

pub const Pose = struct {
    pose: rig.Pose = .{},
};

pub const Renderable = struct {
    model: u16 = 0,
    tint: u32 = 0xffffff,
    boost: f32 = 1.0,
    additive: bool = false,
    id: u16 = 0,
    emits_light: bool = false,
};

pub const Hero = struct {
    class: u8 = 0,
    level: u16 = 1,
    hp: f32 = 100,
    hp_max: f32 = 100,
    ap: f32 = 100,
    ap_max: f32 = 100,
    ap_speed: f32 = 18,
    active: bool = false,
    move_speed: f32 = 3.1,
    attack_damage: f32 = 12,
    attack_range: f32 = 1.4,
    attack_cooldown: f32 = 1.2,
    attack_timer: f32 = 0,
    skill_name: []const u8 = "",
    skill_mult: f32 = 2.0,
    skill_range: f32 = 1.8,
    skill_aoe: f32 = 0,
    skill_slow: f32 = 0,
    downed: bool = false,
    revive_timer: f32 = 0,
};

pub const Enemy = struct {
    kind: u8 = 0, // 0 skeleton, 1 wraith, 2 golem, 3 boss
    hp: f32 = 40,
    hp_max: f32 = 40,
    damage: f32 = 6,
    move_speed: f32 = 1.8,
    attack_range: f32 = 1.1,
    attack_cooldown: f32 = 1.4,
    attack_timer: f32 = 0,
    target: ecs.entity_t = 0,
    slow_timer: f32 = 0,
    hit_flash: f32 = 0,
    boss: bool = false,
};

pub const Follow = struct {
    leader: ecs.entity_t = 0,
    offset: math.Vec2 = .{},
};

pub const LightSource = struct {
    color: math.Vec3 = .{ .x = 1, .y = 0.5, .z = 0.2 },
    intensity: f32 = 1.5,
    radius: f32 = 3.0,
    height: f32 = 0.5,
    flicker: f32 = 0.25,
    phase: f32 = 0,
};

pub const Shadow = struct {
    radius: f32 = 0.3,
};

pub const Spin = struct {
    speed: f32 = 0,
};

pub const Mote = struct {
    center: ecs.entity_t = 0,
    radius: f32 = 0.35,
    speed: f32 = 1.2,
    phase: f32 = 0,
    height: f32 = 0.8,
    spin: f32 = 0.8,
};

pub const all = [_]type{
    Transform,
    Velocity,
    MoveIntent,
    Animation,
    Pose,
    Renderable,
    Hero,
    Enemy,
    Follow,
    LightSource,
    Shadow,
    Mote,
    Spin,
};