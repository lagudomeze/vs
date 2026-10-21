const std = @import("std");
const ecs = @import("zflecs");

// ==========================================
// 1. 定义组件 (Data)
// ==========================================
const ActionGauge = struct {
    current_ap: f32 = 0.0,
    speed: f32 = 10.0,
};

const DeltaTime = struct {
    value: f32 = 0.0,
};

// 全局变量：为了在系统内部能访问 world 和单例实体
var global_world: ?*ecs.world_t = null;
var global_time_entity: ecs.entity_t = 0;

// ==========================================
// 2. 定义系统 (Logic)
// ==========================================
fn updateGaugeSystem(gauges: []ActionGauge) void {
    // 使用全局变量获取时间单例
    const dt_ptr = ecs.get(global_world.?, global_time_entity, DeltaTime).?;
    const dt = dt_ptr.value;

    for (gauges) |*gauge| {
        gauge.current_ap += gauge.speed * dt;
    }
}

// ==========================================
// 3. 主函数
// ==========================================
pub fn main() !void {
    // 1. 初始化 Flecs 世界
    const world = ecs.init();
    defer _ = ecs.fini(world);

    // 保存到全局变量供系统使用
    global_world = world;

    // 2. 注册组件
    ecs.COMPONENT(world, ActionGauge);
    ecs.COMPONENT(world, DeltaTime);

    // 3. 注册系统 (必须用 _ = 接收 u64 返回值)
    _ = ecs.ADD_SYSTEM(world, "UpdateGaugeSystem", ecs.OnUpdate, updateGaugeSystem);

    // 4. 创建全局时间实体 (单例)
    global_time_entity = ecs.new_entity(world, "TimeSingleton");
    _ = ecs.set(world, global_time_entity, DeltaTime, .{ .value = 0.0 });

    // 5. 创建玩家实体
    const player = ecs.new_entity(world, "Player");
    _ = ecs.set(world, player, ActionGauge, .{ .current_ap = 0.0, .speed = 10.0 });

    // ==========================================
    // 6. 纯逻辑模拟循环 (固定步长 60Hz)
    // ==========================================
    const dt_step: f32 = 1.0 / 60.0;
    var frame: u32 = 0;

    while (frame < 120) : (frame += 1) {
        // 更新单例时间
        _ = ecs.set(world, global_time_entity, DeltaTime, .{ .value = dt_step });

        // 推进世界
        _ = ecs.progress(world, 0);

        // 每过 1 秒打印一次状态
        if (frame % 60 == 0) {
            const gauge_ptr = ecs.get(world, player, ActionGauge).?;
            const current_seconds = @as(f32, @floatFromInt(frame)) * dt_step;
            std.debug.print("t={d:.1}s | Player AP = {d:.2}\n", .{
                current_seconds,
                gauge_ptr.current_ap,
            });
        }
    }
}
