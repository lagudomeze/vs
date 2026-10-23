# 数值架构：Tag + 表驱动，而不是“把公式 ECS 化”

> 状态：2026-10-23，重构第一刀已合入前的工作分支。
> 目标：新增一个职业/派生属性/伤害类型时，只改一行数据或一个 Tag，不改第二份公式。

## 1. 为什么之前越改越慢

不是 ECS 不够，而是同一个规则存在多个实现：

- `attributes.recompute()` 里有一套 HP/资源/攻击/护甲/暴击/速度公式。
- `run_sim.Sim.recomputeHero()` 里又抄了一套，职业基础属性/攻击也复制了一份。
- `class_profiles`、`class_base_stats`、`sim.base_stats`、`sim.class_base_attack` 四张表描述同一批职业。
- HUD、存档、QA 各自有 enum/字符串映射。

结果：改一个数值要同步 3-4 处，测试只覆盖其中一条路径，漂移后 QA 才发现。这不是“代码量变大”本身，是**变更放大**。

## 2. reference roguelike 的数值结构（抽象后）

reference roguelike 的 Lua 数据本质上也是表 + 处理器，不是把公式塞进 ECS：

| 层 | reference roguelike 对应 | 本项目对应 |
| --- | --- | --- |
| 主属性 | str/dex/con/mag/wil/cun | `StatKind` |
| 派生战斗值 | combat attack/defense/armor/crit/speed | `Derived` + `derived_defs` |
| 职业 | class 表：资源、主属性、初始属性 | `ClassDef` 单表 |
| 资源 | stamina/mana/paradox/vim... | `ResourceKind` |
| 伤害管线 | DamageType -> projector -> resistance/armor/crit | 目前只有物理 + 暴击，待泛化 |
| 天赋 | cost/cooldown/range/target/effect 表 | `skills.json` + `SkillDef` |
| 状态 | effect 表：duration/stack/tick | 目前只有 stun/slow/buff 字段 |
| 成长 | level/xp 曲线 | `Progression` |

共同点：

1. **数据行描述“是什么”**（职业、伤害类型、天赋参数）。
2. **系统描述“怎么算”**（recompute、damage pipeline、status tick）。
3. 系统是少量、稳定的；数据行是大量、易变的。

所以正确方向是：**稳定的行为用泛型系统，变化的部分用表/Tag**。不是把每个公式拆成一个 ECS entity。

## 3. Zig 的做法：comptime 表 + Tag

### 3.1 派生属性表

`attributes.zig` 现在有：

```zig
pub const StatTerm = struct { stat: StatKind, per: f32 };

pub const DerivedDef = struct {
    base: f32 = 0,
    terms: []const StatTerm = &.{},
    min: f32,
    max: f32 = std.math.floatMax(f32),
    main_scale: f32 = 0,
    class_base_attack: bool = false,
};

pub const derived_defs = .{
    .hp_max = .{ .base = 40, .terms = &.{.{ .stat = .constitution, .per = 8 }}, .min = 1 },
    .attack = .{ .min = 0, .main_scale = 1.2, .class_base_attack = true },
    .crit = .{ .base = 0.05, .terms = &.{.{ .stat = .perception, .per = 0.004 }}, .min = 0, .max = 0.50 },
    // ...
};
```

`recompute()` 不再逐个写公式，而是：

```zig
inline for (@typeInfo(Derived).@"struct".field_names) |field_name| {
    const def = @field(derived_defs, field_name);
    var base_value = def.base;
    if (def.class_base_attack) base_value += profile.base_attack;
    for (def.terms) |term| base_value += stats[term.stat] * term.per;
    if (def.main_scale != 0) base_value += main * def.main_scale;
    @field(derived, field_name) = acc.apply(...);
}
```

新增 `hp_regen` 时：

1. `StatRef` 加一个 tag；
2. `Derived` 加一个字段；
3. `derived_defs` 加一行；
4. HUD 决定是否显示。

不需要再写第 4 个公式块。编译期检查会保证 `Derived` 和 `derived_defs` 一一对应。

### 3.2 职业表

```zig
pub const ClassDef = struct {
    name: []const u8,
    role: []const u8,
    base_attack: f32,
    main_stat: StatKind,
    resource: ResourceKind,
    base_stats: [stat_count]f32,
};
```

一个职业一行。`profile()`、`baseStats()`、`class_names`、`class_roles`、`resource_names` 全部从这张表派生。
新增职业 = 一行 + 3 个天赋数据；不是复制数组、enum、HUD 名称。

### 3.3 为什么是 comptime 表，不是运行时 JSON

- 公式/字段映射是**类型行为**：错字段应该编译失败。
- 数量/系数是**配置**：可以来自 JSON。
- 运行时 JSON 适合 items/enemies/skills 这种内容；如果把公式也塞 JSON，会变成解释器，失去 Zig 的类型检查，调试更难。

因此建议分层：

| 内容 | 放哪 | 原因 |
| --- | --- | --- |
| 公式结构、字段映射、tag | Zig comptime | 编译期校验，零运行时开销 |
| 职业/属性/成长系数 | Zig 表，后续可 JSON 覆盖 | 需要类型 + 可调 |
| 物品/敌人/技能/掉落 | JSON | 内容量增长快，非程序员可改 |
| 存档 | JSON | 兼容/调试 |

## 4. ECS 的边界

ECS 擅长：**大量实体 × 少量独立系统**（渲染、粒子、AI 查询）。
不擅长：**一个角色的确定性数值管线**（公式、存档、回合结算）。

当前项目：

- `game.zig` 的竞技场已经是 zflecs：Transform/Renderable/Shadow/Light 等组件，系统查询合理。
- `run_sim.zig` 是单英雄 + ≤12 敌人的确定性回合模拟，存档逐字段序列化；强行 zflecs 会增加：
  - 实体 id 与存档映射；
  - 系统调度顺序；
  - 测试/QA 的确定性成本；
  - 组件生命周期。

这不代表 Sim 不能数据化。正确做法是**纯组件结构**：

```zig
pub const PrimaryStats = struct { base: [6]f32 };
pub const ModifierSet = struct { mods: []const Modifier };
pub const DerivedSheet = struct { ... };
pub const Progression = struct { level, xp };
pub const ResourcePool = struct { current, max, per_turn };
```

系统：

- `recomputeSheet(primary, mods, class)`
- `gainXp(progression, amount)`
- `applyDamage(packet, defenses)`
- `tickStatuses(...)`

这些结构可以被 zflecs 挂到 entity 上，也可以被 Sim 直接持有；**组件不依赖 ECS**。等 Sim 真需要多系统查询时再迁移，不提前付成本。

## 5. 已落地的改动

1. `Sim.recomputeHero()` 不再抄公式，直接调用 `attributes.recompute`。
2. 删除 `Sim` 的 `base_stats`、`class_base_attack`、重复 `Stats.mainStat`。
3. `Sim.Class` 直接 alias `attributes.Class`，删掉第二套 enum/classFromIndex。
4. `class_defs` 单表派生职业 profile/base stats/名称/定位/资源名。
5. `derived_defs` 表 + inline comptime 循环驱动 7 个派生属性。
6. 新增回归测试：三职业的 Sim 面板必须与 `attributes.recompute` 完全一致，防止再次漂移。

## 6. 下一刀（按收益排序）

1. **DamageType Tag + DamagePacket**
   - `enum(u8) { physical, fire, cold, arcane, temporal }`
   - `DamagePacket { raw, type, crit, source }`
   - `ResistanceTable` 按 tag 查表；armor 只对 physical。
   - 天赋只声明 `damage_type`，不再各写一套减伤。
2. **Effect/Status 表**
   - `StatusDef { id, duration, stack, tick_damage, modifiers }`
   - 现有 stun/slow/buff 三个字段收敛成 `StatusSet`。
3. **TalentDef 数据化**
   - skills.json 已有 cost/cooldown/range/effect；把 target shape（single/beam/cone/aoe）变成 tag，执行器按 tag 分派。
4. **Progression 曲线表**
   - `xp_base * level` 变成 `xp_curve: enum { linear, quadratic }` + 系数，方便平衡。
5. **运行时 balance overlay**
   - 只覆盖系数/初始属性，不覆盖公式；坏配置拒绝并回退默认。

## 7. 验收标准

未来新增内容时，改动量应满足：

| 需求 | 期望改动 |
| --- | --- |
| 新职业 | 1 行 ClassDef + 3 行技能数据 + HUD 卡片 |
| 新派生属性 | 1 个 tag + 1 行 DerivedDef + HUD 显示 |
| 新伤害类型 | 1 个 tag + 1 行抗性表 + 天赋数据引用 |
| 新状态 | 1 行 StatusDef + 执行器分支（若语义新） |
| 数值平衡 | 只改表/JSON，不改系统代码 |

如果做不到，说明抽象边界错了，而不是“功能不够多”。
