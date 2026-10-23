const std = @import("std");

pub const HasModifier = struct {};

// ═══════════════════════════════════════════════════════════════
// 通用 Modifier
// ═══════════════════════════════════════════════════════════════
pub fn _Modifier(comptime Target: type) type {
    return struct {
        const Self = @This();
        _mark: Target = undefined,
        add: f32 = 0.0,
        /// 增量语义：实际乘数 = 1 + mul
        mul: f32 = 0.0,
    };
}

pub fn Value(comptime T: type, default: f32) type {
    return struct {
        const Self = @This();
        const Modifier = _Modifier(Self);

        _mark: T = undefined,
        val: f32 = default,
        base: f32 = default,

        pub fn newModifier(add: f32, mul: f32) Modifier {
            return .{ .add = add, .mul = mul };
        }

        /// Backwards-compatible alias for the original typo.
        pub const new_modifiter = newModifier;

        pub fn recompute(self: *Self, list: anytype) void {
            const Elem = std.meta.Elem(@TypeOf(list));
            comptime {
                if (Elem != Modifier)
                    @compileError("recompute: list 元素必须是 " ++ @typeName(Modifier) ++
                        "，实际是 " ++ @typeName(Elem));
            }

            var sum_add: f64 = 0;
            var prod_mul: f64 = 1;
            for (list) |mod| {
                sum_add += mod.add;
                prod_mul *= (1.0 + mod.mul);
            }
            self.val = self.base * @as(f32, @floatCast(prod_mul)) + @as(f32, @floatCast(sum_add));
        }
    };
}

// ═══════════════════════════════════════════════════════════════
// 包装类型：让 _Modifier 为 full / base 生成不同组件类型
// ═══════════════════════════════════════════════════════════════
fn FullOf(comptime G: type) type {
    return struct { gauge: G = undefined };
}
fn BaseOf(comptime G: type) type {
    return struct { gauge: G = undefined };
}

/// 边界规格：full 和 base 共用。
/// - default：未修正的原始边界值
/// - clamp  ：
///     - 用于 full 时：true → val 被截断到 full；false → full 仅作比例基准
///     - 用于 base 时：true → val 被约束为 ≥ base；false → base 仅存储
// ═══════════════════════════════════════════════════════════════
// 边界规格（Full 和 Base 都复用这个基础结构）
// ═══════════════════════════════════════════════════════════════
pub const BoundSpec = struct {
    default: f32 = 0,
    /// true 时对 val 进行截断（对于 Full 是上限，对于 Base 是下限）
    /// false 时 val 可以无限延伸（对于 Full 是无限大，对于 Base 是回退到 0）
    clamp: bool = true,
};

// ═══════════════════════════════════════════════════════════════
// 核心：通用的 Gauge Mixin
// 包含了 SimpleGauge 和 BoundedGauge 共享的字段操作逻辑
// ═══════════════════════════════════════════════════════════════
fn GaugeCommonMixin(comptime Self: type, comptime full_spec: BoundSpec) type {
    return struct {
        pub fn newFullModifier(add: f32, mul: f32) Self.FullModifier {
            return .{ .add = add, .mul = mul };
        }

        pub fn upperBound(self: Self) f32 {
            return if (full_spec.clamp) self.full else std.math.inf(f32);
        }

        pub fn recomputeFull(self: *Self, full_mods: []const Self.FullModifier) void {
            var f_add: f64 = 0;
            var f_mul: f64 = 1;
            for (full_mods) |m| {
                f_add += m.add;
                f_mul *= (1.0 + m.mul);
            }
            self.full = @max(0, self.raw_full * @as(f32, @floatCast(f_mul)) + @as(f32, @floatCast(f_add)));

            // 编译期检查 Self 是否有 base 字段（如果是 BoundedGauge）
            if (comptime @hasField(Self, "base")) {
                if (self.full < self.base) self.base = self.full; // 防止上限低于下限
            }

            self.clampVal();
        }

        pub fn modify(self: *Self, delta: f32) void {
            self.val += delta;
            self.clampVal();
        }

        pub fn set(self: *Self, value: f32) void {
            self.val = value;
            self.clampVal();
        }

        /// Set the raw/final full value directly, for formula-driven recompute.
        /// Current value is preserved and clamped.
        pub fn setFull(self: *Self, value: f32) void {
            self.raw_full = @max(0, value);
            self.full = self.raw_full;
            if (comptime @hasField(Self, "base")) {
                if (self.full < self.base) self.base = self.full;
            }
            self.clampVal();
        }

        pub fn spend(self: *Self, amount: f32) bool {
            comptime {
                if (!full_spec.clamp) {
                    @compileError("spend() 只能在 clamp = true 的 Gauge 上调用");
                }
            }
            if (amount < 0 or self.val < amount) return false;
            self.modify(-amount);
            return true;
        }
    };
}

// ═══════════════════════════════════════════════════════════════
// 1. 只有上限的 Gauge（用于 HP, Mana, Stamina）
// ═══════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════
// 1. SimpleGauge（只有上限）
// ═══════════════════════════════════════════════════════════════
pub fn SimpleGauge(comptime T: type, comptime spec: BoundSpec) type {
    comptime {
        if (spec.default < 0) @compileError("SimpleGauge: default 不能为负");
    }

    return struct {
        const Self = @This();
        const FullModifier = _Modifier(FullOf(Self));

        _mark: T = undefined,
        raw_full: f32 = spec.default,
        full: f32 = spec.default,
        val: f32 = spec.default,

        // ── 自然加入 Mixin 方法 ──
        const Common = GaugeCommonMixin(Self, spec);
        pub const newFullModifier = Common.newFullModifier;
        pub const upperBound = Common.upperBound;
        pub const recomputeFull = Common.recomputeFull;
        pub const modify = Common.modify;
        pub const set = Common.set;
        pub const setFull = Common.setFull;
        pub const spend = Common.spend;

        // 实现 Mixin 依赖的 clampVal
        pub fn clampVal(self: *Self) void {
            self.val = std.math.clamp(self.val, 0, self.upperBound());
        }
    };
}

// ═══════════════════════════════════════════════════════════════
// 2. 有上下界的 Gauge（用于 Equilibrium, 复杂风险条）
// ═══════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════
// 2. BoundedGauge（有上下界）
// ═══════════════════════════════════════════════════════════════
pub fn BoundedGauge(comptime T: type, comptime full_spec: BoundSpec, comptime base_spec: BoundSpec) type {
    comptime {
        if (full_spec.default < 0) @compileError("BoundedGauge: full.default 不能为负");
        if (base_spec.default < 0) @compileError("BoundedGauge: base.default 不能为负");
        if (base_spec.default > full_spec.default) @compileError("BoundedGauge: base.default 不能大于 full.default");
    }

    return struct {
        const Self = @This();
        const FullModifier = _Modifier(FullOf(Self));
        const BaseModifier = _Modifier(BaseOf(Self));

        _mark: T = undefined,
        raw_full: f32 = full_spec.default,
        full: f32 = full_spec.default,
        raw_base: f32 = base_spec.default,
        base: f32 = base_spec.default,
        val: f32 = base_spec.default,

        // ── 自然加入 Mixin 方法 ──
        const Common = GaugeCommonMixin(Self, full_spec);
        pub const newFullModifier = Common.newFullModifier;
        pub const upperBound = Common.upperBound;
        pub const recomputeFull = Common.recomputeFull;
        pub const modify = Common.modify;
        pub const set = Common.set;
        pub const setFull = Common.setFull;
        pub const spend = Common.spend;

        // 实现 Mixin 依赖的 clampVal
        pub fn clampVal(self: *Self) void {
            self.val = std.math.clamp(self.val, self.lowerBound(), self.upperBound());
        }

        // ── 独有方法：下界逻辑 ──
        pub fn lowerBound(self: Self) f32 {
            return if (base_spec.clamp) self.base else 0;
        }

        pub fn newBaseModifier(add: f32, mul: f32) BaseModifier {
            return .{ .add = add, .mul = mul };
        }

        pub fn recomputeBase(self: *Self, base_mods: []const BaseModifier) void {
            var b_add: f64 = 0;
            var b_mul: f64 = 1;
            for (base_mods) |m| {
                b_add += m.add;
                b_mul *= (1.0 + m.mul);
            }
            self.base = @max(0, self.raw_base * @as(f32, @floatCast(b_mul)) + @as(f32, @floatCast(b_add)));
            if (self.base > self.full) self.full = self.base; // 防止下限高于上限
            self.clampVal();
        }
    };
}

// ═══════════════════════════════════════════════════════════════
// 单元测试
// ═══════════════════════════════════════════════════════════════

const Hp = struct {};
const Xp = struct {};
const Equilibrium = struct {};

test "SimpleGauge: 基础加减与上限截断 (clamp=true)" {
    const HpGauge = SimpleGauge(Hp, .{ .default = 100.0, .clamp = true });
    var hp = HpGauge{};

    try std.testing.expectEqual(@as(f32, 100.0), hp.val);

    // 1. 正常扣除
    hp.modify(-30.0);
    try std.testing.expectEqual(@as(f32, 70.0), hp.val);

    // 2. 回复溢出（截断在 100）
    hp.modify(50.0);
    try std.testing.expectEqual(@as(f32, 100.0), hp.val);

    // 3. set 方法同样受限
    hp.set(150.0);
    try std.testing.expectEqual(@as(f32, 100.0), hp.val);

    // 4. spend 成功
    try std.testing.expect(hp.spend(20.0));
    try std.testing.expectEqual(@as(f32, 80.0), hp.val);

    // 5. spend 余额不足（状态不变）
    try std.testing.expect(!hp.spend(100.0));
    try std.testing.expectEqual(@as(f32, 80.0), hp.val);

    // 6. spend 传负数（防御性失败）
    try std.testing.expect(!hp.spend(-10.0));
    try std.testing.expectEqual(@as(f32, 80.0), hp.val);
}

test "SimpleGauge: 无上限表现 (clamp=false)" {
    const XpGauge = SimpleGauge(Xp, .{ .default = 0.0, .clamp = false });
    var xp = XpGauge{};

    // 1. 无上限，可以无限增长
    xp.modify(10000.0);
    try std.testing.expectEqual(@as(f32, 10000.0), xp.val);

    // 2. 下限依然存在（不能为负）
    xp.modify(-20000.0);
    try std.testing.expectEqual(@as(f32, 0.0), xp.val);

    // 注意：如果你想测试 `xp.spend(10)`，取消下面这行的注释，编译器会直接报错
    // xp.spend(10);
}

test "BoundedGauge: 动态下界联动 (Equilibrium 场景)" {
    // 模拟 Equilibrium：无上限，下限受 Sustain 修正，初始 0
    const EqGauge = BoundedGauge(Equilibrium, .{ .default = 0.0, .clamp = false }, .{ .default = 0.0, .clamp = true });
    var eq = EqGauge{};

    try std.testing.expectEqual(@as(f32, 0.0), eq.val);

    // 1. 激活 Sustain（+30 下界）
    const sustain_30 = EqGauge.newBaseModifier(30.0, 0.0);
    eq.recomputeBase(&[_]EqGauge.BaseModifier{sustain_30});

    try std.testing.expectEqual(@as(f32, 30.0), eq.base);
    try std.testing.expectEqual(@as(f32, 30.0), eq.val); // val 被下界拉高

    // 2. 增加当前值
    eq.modify(50.0);
    try std.testing.expectEqual(@as(f32, 80.0), eq.val);

    // 3. 尝试降低到下限以下（会被 30 拦住）
    eq.modify(-100.0);
    try std.testing.expectEqual(@as(f32, 30.0), eq.val);
}

test "BoundedGauge: 极限防穿模 (下限与上限互顶)" {
    // 上下界都可调的 Gauge
    const TestGauge = BoundedGauge(Equilibrium, .{ .default = 100.0, .clamp = true }, .{ .default = 0.0, .clamp = true });
    var g = TestGauge{};

    // 1. 把下界抬到 120（高于初始上限 100）
    const raise_base = TestGauge.newBaseModifier(120.0, 0.0);
    g.recomputeBase(&[_]TestGauge.BaseModifier{raise_base});

    // 防穿模触发：上限应该被顶到 120，下限也是 120
    try std.testing.expectEqual(@as(f32, 120.0), g.base);
    try std.testing.expectEqual(@as(f32, 120.0), g.full);
    try std.testing.expectEqual(@as(f32, 120.0), g.val);

    // 2. 把上限压到 50（低于当前的 120 下限）
    // 注意：_Modifier 是 add/mul 增量，想让 full 变成 50，我们需要 add 一个负数（假设没有乘数）
    const lower_full = TestGauge.newFullModifier(-70.0, 0.0); // 100 + (-70) = 30
    g.recomputeFull(&[_]TestGauge.FullModifier{lower_full});

    // 防穿模触发：上限被压到 30，下限应该跟着降到 30
    try std.testing.expectEqual(@as(f32, 30.0), g.full);
    try std.testing.expectEqual(@as(f32, 30.0), g.base);
    try std.testing.expectEqual(@as(f32, 30.0), g.val);
}
