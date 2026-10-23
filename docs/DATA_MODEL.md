# 数据模型审计：定义、组件、聚合

> 结论先说：**ItemDef 不是 ECS 组件**，它是不可变的内容定义（registry/resource）。
> 但你的直觉是对的：现在的数据结构大量使用“大平铺结构 + 可选字段”，没有按变体拆成 Tagged Union，也没有把 Actor 拆成组件。ECS 只做了一半。

> 2026-10-23：Phase 1 的 ItemDef 与 SkillDef 已落地 —— 运行时分别是 ItemKind/SkillEffect union，JSON 仍用扁平 wire DTO 并转换。

## 1. 四种数据要分开

| 类别 | 生命周期 | 例子 | 是否 ECS 组件 |
| --- | --- | --- | --- |
| Definition | 启动加载，只读 | ItemDef、SkillDef、EnemyDef、ClassDef | 否；是 registry/resource |
| Component | 每实体可变 | Position、Vitals、PrimaryStats、StatusSet | 是 |
| Resource | 全局单例 | RNG、TurnClock、FloorState、Content | 是（ECS resource） |
| Aggregate/View | 临时组合 | Inventory、CharacterPanel、HUD State | 否；是 view |

所以“ItemDef 字段多”本身不是 ECS 问题。真正的问题是：

1. 一个 ItemDef 同时表达装备/消耗品/任务物品，靠 null 字段区分。
2. SkillDef 同时表达伤害/增益/闪现/眩晕/回溯，17 个字段里大部分只对一种效果有意义。
3. EnemyDef 混合身份、战斗、AI、掉落、生成规则。
4. Hero/Enemy 是 20/13 个字段的聚合，不是组件。
5. zflecs 的 Hero/Enemy 组件同样是 20/12 个字段的聚合，只是把聚合放进了 ECS。

## 2. 逐项审计

### ItemDef（9 字段，已改为 union）

~~~zig
id, name,
slot: ?Slot, quality, classes, weight,
mods: []Modifier,
use: ?Use,
description
~~~

问题：

- equipment 需要 slot/mods；
- consumable 需要 use；
- quest 两者都不需要。
- 现在允许以下非法状态：
  - slot=null, use=null（既不能装备也不能用）
  - slot=body, use=heal（又是装备又是药）
  - consumable 带 mods
  - quest item 带 weight/classes

这不是字段数量问题，是**变体没有建模**。

目标：

~~~zig
pub const ItemKind = union(enum) {
    equipment: struct {
        slot: Slot,
        mods: []const Modifier,
    },
    consumable: struct {
        use: Use,
    },
    quest,
};

pub const ItemDef = struct {
    id: []const u8,
    name: []const u8,
    quality: Quality,
    description: []const u8,
    drop: DropRule,       // classes + weight，只对可掉落物有意义
    kind: ItemKind,
};
~~~

好处：

- 不可能出现 equipment+use；
- 装备逻辑只处理 equipment 分支；
- 消耗品逻辑只处理 consumable；
- JSON 校验可以按 kind 校验字段，而不是“有就用，没有就默认”。

注意：这仍然不是 ECS 组件，而是**静态定义的 sum type**。ECS 不解决变体建模。

### SkillDef（17 字段，已改为 union）

~~~text
id, name, kind, class, effect,
cost, cooldown_turns,
damage_mult, flat_damage,
range_cells, aoe_cells,
knockback_cells, teleport_cells,
buff_pct, duration_turns, slow_pct,
description
~~~

问题：

- effect=blink 仍可带 damage_mult/aoe/knockback；
- effect=stun 仍可带 teleport_cells/buff_pct；
- kind=enemy 仍可带 class；
- 系统必须用 switch(effect) 读取少量字段，其余字段是噪音；
- 运行态又有一份 run_target.specFor 和 Sim.talentCost/Cooldown，第三份规格。

目标：

~~~zig
pub const SkillEffect = union(enum) {
    damage: struct {
        mult: f32,
        damage_type: DamageType = .physical,
        shape: TargetShape,
    },
    buff: struct {
        pct: f32,
        duration: u16,
    },
    blink: struct {
        min_cells: u8,
        max_cells: u8,
    },
    stun: struct {
        duration: u16,
        damage_mult: f32,
    },
    recall,
};

pub const SkillDef = struct {
    id: []const u8,
    name: []const u8,
    kind: SkillKind,
    class: ?Class,        // enemy 必须 null，由校验/类型保证
    cost: u16,
    cooldown: u16,
    target: TargetSpec,   // shape/range/los
    effect: SkillEffect,
    description: []const u8,
};
~~~

这样“伤害技能”只声明伤害字段，“闪现”只声明距离；执行器按 union tag 分派。

### EnemyDef（18 字段）

~~~text
id, name, model, kind,
hp, damage, armor, speed, attack_range, attack_cooldown,
scale, xp, drop_chance,
min_layer, max_layer, elite, boss, skill
~~~

它其实是 5 张表：

- Identity：id/name/model/scale
- Combat：hp/damage/armor/speed/range/cooldown
- AI：kind/skill
- Loot：xp/drop_chance
- Spawn：min/max layer/elite/boss

目标：

~~~zig
pub const EnemyDef = struct {
    id: []const u8,
    name: []const u8,
    model: []const u8,
    scale: f32,
    tags: EnemyTags,       // elite/boss 用 tag/bit set，不用两个 bool
    combat: CombatProfile,
    ai: AIProfile,
    loot: LootProfile,
    spawn: SpawnProfile,
};
~~~

同时删除 run_sim.EnemyDef 这份重复定义；Sim 只引用 content registry 的 EnemyDef。

### Hero / Enemy（运行态）

run_sim.Hero 有 20 个字段：

~~~text
class, pos, last_pos, stats,
hp, hp_max, resource, resource_max,
attack, armor, crit, speed, res_per_turn,
level, xp, pending_points,
cooldowns, buff_turns, buff_pct, eff_stats
~~~

run_sim.Enemy 有 13 个字段：

~~~text
kind, name, pos, hp, hp_max, attack, armor,
speed, range, xp, stun_turns, slow_turns, alive
~~~

这些不是组件，是**聚合**。至少应拆：

~~~zig
Identity       { def_id, faction }
GridPosition   { x, y }
PrimaryStats   { base[6] }
ModifierSet    { mods[] }
Vitals         { hp, hp_max, shield }
ResourcePool   { current, max, per_turn }
CombatStats    { attack, armor, crit, speed, range }
Progression    { level, xp, pending_points }
Cooldowns      { values[3] }
StatusSet      { instances[] }
AIState        { behavior, target, last_seen }
Reward         { xp, drop }
~~~

Hero = Identity + Position + PrimaryStats + ModifierSet + Vitals + ResourcePool + Progression + Cooldowns + StatusSet。
Enemy = Identity + Position + Vitals + CombatStats + StatusSet + AIState + Reward。

系统按组件工作：

- recompute 只读写 PrimaryStats/ModifierSet/CombatStats；
- damage 只读写 Vitals/Defense；
- status 只读写 StatusSet；
- AI 只读写 AIState/Position；
- UI 只读投影。

### components.zig（zflecs）

当前 ECS 的 Hero 组件有 20 字段，Enemy 有 12 字段，同样混合：

- identity、vitals、movement、attack、skill、revive、render。

这说明 **zflecs 被当作 scene graph，而不是数据组件模型**。它负责渲染实体的 Transform/Renderable/Light 是合理的；但把整个角色数据塞进一个 Hero component，只是把聚合换个地方，ECS 的“组合”优势没有发生。

## 3. ECS 到底做好了吗

分三层看：

| 层 | 状态 | 判断 |
| --- | --- | --- |
| 渲染 ECS | Transform/Renderable/Light/Shadow 已拆 | 基本合理 |
| 渲染 Actor | Hero/Enemy 大聚合 | 没做好 |
| 回合 Sim | 无 ECS，Sim/Hero/Enemy 大聚合 | 没做 |

但“上 zflecs”不是答案。单英雄 + 12 敌人的确定性模拟，用纯组件数组/SoA 更简单、可存档、可测试。关键是把数据拆成组件，而不是把组件塞进 zflecs。

推荐边界：

- Sim：纯组件结构 + 系统函数（无 zflecs entity id）。
- Render：zflecs，从 Sim 投影 Transform/Renderable/Light。
- QA：复用 Sim 组件，不加载渲染。
- Definition：全局 registry，不属于任何 actor。

## 4. 静态定义为什么不应做成组件

ECS 组件是“每个实体都有一份”的状态。ItemDef/SkillDef/EnemyDef：

- 数量固定；
- 启动加载后只读；
- 被多个实体按 ID 引用；
- 存档只存 ID，不存定义。

所以它们应该是 **Resource/Registry**，items/enemies 实例只存 def_id。把 ItemDef 做成组件会导致每个物品实体复制一份名称/描述/修正，既浪费又难校验。

## 5. 非法状态清单

| 结构 | 现在允许的非法状态 | 目标 |
| --- | --- | --- |
| ItemDef | equipment 无 slot；consumable 有 mods；quest 有 weight | tagged union + loader 校验 |
| SkillDef | blink 带 aoe；stun 带 teleport；enemy 带 class | union effect + 校验 |
| EnemyDef | elite+boss；min_layer>max_layer；kind 与模型不符 | tags + 构造校验 |
| Actor | hp>hp_max；status 字段互斥；cooldowns 固定3但职业可扩展 | 组件不变量 + system |
| Content | 定义表重复（Sim EnemyDef vs content EnemyDef） | 单一 registry |

## 6. 重构顺序（按风险）

### Phase 1：定义 sum type（无玩法变化）

1. ✅ ItemDef -> ItemKind union；JSON loader 按 kind 校验。
2. ✅ SkillDef -> SkillEffect union；现有 9 个玩家技能 + Boss AOE 已映射。
3. EnemyDef -> Combat/AI/Loot/Spawn 子结构；tags 代替 bool。
4. 删除 run_sim.EnemyDef 重复表，Sim 改用 content registry。

### Phase 2：Actor 组件化（行为不变）

5. Hero -> 组件结构；Sim 保留 Hero 聚合作为兼容视图，内部字段转发。
6. Enemy -> 组件结构；AI/Reward 独立。
7. recompute/damage/status/AI 系统改为接收组件指针。

### Phase 3：实例与 ECS

8. 只有需要词缀/耐久/附魔时，才引入 ItemInstance { def_id, affixes, durability }；Inventory 从 ItemId[] 改为 ItemInstance[]。
9. 渲染 ECS 拆分 Hero/Enemy 聚合；Transform/Renderable/Light 由 Sim 投影。
10. 如果 Sim 出现多系统查询需求，再加 zflecs adapter；否则保持纯组件数组。

## 7. 验收标准

- 新增装备类型只改 ItemKind 分支 + loader，不改 equip() 的 if。
- 新增技能效果只改 SkillEffect 分支 + executor，不新增 17 字段中的可选字段。
- 新增敌人只加一行 EnemyDef，不复制 run_sim 表。
- 新增状态不改 Hero/Enemy 字段。
- 非法组合在加载期报错，而不是运行时 switch 默认值。
- 存档只存 def_id + 实例状态，不存 Definition 全文。

## 8. 结论

- **ItemDef 不是组件，是定义**；它的问题是缺少变体建模，不是 ECS 化不足。
- **SkillDef/EnemyDef 同理**，需要用 sum type/子结构，而不是继续加字段。
- **Hero/Enemy 才是组件化不足的地方**；zflecs 的 Hero/Enemy 也只是聚合组件。
- 先做定义 sum type，再做 Actor 组件拆分，最后才考虑 zflecs 适配；不要反过来。
