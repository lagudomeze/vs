# 数值层：mech.zig 评估与迁移边界

> 结论：mech.zig 适合做**数值存储与修正运算**层，不适合替代属性公式表。
> 推荐分阶段迁移；不要一次把 attributes/run_sim 全替换。

## 1. 它解决了什么

mech.zig 的核心是：

- Value(Tag, default)：base + val，修正 = base * prod(1+mul) + sum(add)。
- SimpleGauge：val / full，clamp 到 [0, full]；spend 只能在上限有限的 Gauge 上用。
- BoundedGauge：额外 base 下界，适合 Equilibrium 这类动态下界资源。
- modifier 类型由 Target 参数化：每个数值是独立组件类型，不靠字符串或 enum 擦除。
- 组件可注册到 zflecs，适合作为纯 ECS 数值组件。

这正好覆盖我们目前的：

- 六维：base + 装备/buff 修正。
- HP/资源：当前值、上限、回复。
- 攻击/护甲/暴击/速度：派生值 + modifier。

## 2. 它不解决什么

- 公式：攻击 = 职业基础 + 主属性*1.2 + 武器 flat，这类规则仍应留在 attributes.zig 的表中。
- 定义/注册表：ClassDef、ItemDef、SkillDef 不是数值组件。
- 修正来源/持续时间/叠层：mech 的 Modifier 只有 add/mul，没有 source/duration/stack。
- 多个同类修正：ECS 一个实体只能有一个 Modifier(Target) 组件；要多个 modifier，需要子实体或固定数组。
- 序列化：字段是 f32，save DTO 仍要显式映射。
- 纯 ECS 不等于 Sim 必须上 zflecs：我们的 Sim 仍可用这些 POD 组件数组，保持确定性和存档。

## 3. 推荐结构

### 3.1 六维

每个属性是独立 Value 类型：

~~~zig
pub const StrengthTag = struct {};
pub const Strength = mech.Value(StrengthTag, 10);
// Agility, Constitution, Perception, Magic, Will...
~~~

Actor 上的组合：

~~~zig
pub const PrimarySheet = struct {
    strength: Strength,
    agility: Agility,
    constitution: Constitution,
    perception: Perception,
    magic: Magic,
    will: Will,
};
~~~

UI 通过 comptime 表遍历字段，不再用 stats[6] 下标。

### 3.2 HP / 资源

~~~zig
pub const HpTag = struct {};
pub const Health = mech.SimpleGauge(HpTag, .{ .default = 1, .clamp = true });

pub const ResourceTag = struct {};
pub const Resource = mech.SimpleGauge(ResourceTag, .{ .default = 1, .clamp = true });
~~~

current = val，max = full。
资源回复仍是单独的 Value 或公式，不塞进 Gauge。

### 3.3 派生战斗值

攻击、护甲、暴击、速度用 Value，因为它们是“没有当前值”的数值：

~~~zig
pub const Attack = mech.Value(AttackTag, 0);
pub const Armor = mech.Value(ArmorTag, 0);
pub const Crit = mech.Value(CritTag, 0);
pub const Speed = mech.Value(SpeedTag, 0);
~~~

### 3.4 修正

装备/Buff 产生的 modifier 作为**子实体**挂到 actor：

~~~text
actor
  modifier_strength { Modifier(Strength): { add: 2 } }
  modifier_attack   { Modifier(Attack): { add: 6 } }
~~~

recompute 时收集子实体列表，调用：

~~~zig
strength.recompute(mods);
health.recomputeFull(full_mods);
~~~

不要把所有 modifier 又塞回一个 []Modifier 聚合，否则只是把胖结构换个名字。

## 4. 与现有 attributes.zig 的关系

保留：

- ClassDef / DerivedDef / formulas / caps。
- recompute 作为唯一公式入口。
- damage/armor 结算。

替换：

- Stats[6] -> PrimarySheet 的 6 个 Value。
- HeroVitals { hp, hp_max } -> Health gauge。
- ResourcePool { current, max, per_turn } -> Resource gauge + per_turn Value。
- HeroCombat { attack, armor, crit, speed } -> 4 个 Value。
- Enemy.vitals -> Health gauge；Enemy.combat -> 4 个 Value。

不变：

- Save DTO（version 2）字段名和语义不变，读写时映射 val/full。
- Sim 的数组/确定性；mech 组件是 POD，不需要 zflecs。
- QA 数值基线；迁移本身不应改平衡。

## 5. 迁移阶段

### Phase A：基础层（已完成）

- 引入 mech.zig。
- 修 register：SimpleGauge / BoundedGauge 也能注册。
- 加 ECS 存储测试。
- 不改游戏数值。

### Phase B：HP / 资源（已完成）

- ✅ Hero/Enemy 的 hp/hp_max 改成 numeric.Health（SimpleGauge）。
- ✅ Hero resource current/max 改成 numeric.Resource；回复用 numeric.Regen。
- ✅ Enemy 生死拆成 numeric.LifeState；zflecs 注册拆到 numeric_ecs.zig。
- 死亡判断读 val <= 0。
- 存档映射不变。
- 测试/QA 行为等价。

### Phase C：六维（已完成）

- ✅ Hero.sheet.stats 改成 PrimarySheet（6 个独立 mech.Value）。
- 加点/装备/UI 用字段表遍历。
- ✅ Save DTO 的 stats 仍是六个 f32，加载时重建 PrimarySheet。

### Phase D：派生值（已完成）

- ✅ Hero/Enemy 的 attack/armor/crit/speed 改成 4 个独立 Value。
- ✅ attributes.recompute 写 base/val；装备 modifier 仍由 attributes 聚合处理。
- 公式仍集中。

### Phase E：装备修正

- 装备词条从 attributes.Modifier 改为子实体 Modifier(Target)。
- 保持词条显示和排序。

## 6. mech.zig 还需要补的

- Modifier 的 source/duration/stack 元数据。
- 一个实体多个 modifier 的官方模式（子实体/关系）。
- Gauge 的原始上限/下限调试视图。
- 存档/加载适配器。
- UI 需要的 label/format 元数据。

## 7. 决策

- **用**：作为数值组件的存储/修正运算层。
- **不用**：替代 ClassDef/公式表/内容定义。
- **先做**：Phase B（HP/资源），因为影响面清晰、存档字段不变。
- **后做**：六维/派生值/装备 modifier，逐阶段锁 QA。

这样既吸收 mech.zig 的纯 ECS 组合优点，又不会把已经很脆的数值公式和存档再打散。
