# 机制抽象 v0.1

> 目的：先定义机制边界，再谈 ECS 实现。
> 结论：机制不是 ECS system；一个机制可以横跨多个组件、多个系统、多个 ECS world（Sim / 渲染 / QA）。机制之间只通过只读查询、命令和事件交互。

## 1. 设计目标

1. 每个机制有唯一的状态所有者。
2. 一个公式只有一个实现。
3. 机制之间没有循环依赖。
4. 新增职业/技能/伤害类型/状态时，改动集中在一张表或一个 Tag。
5. 同一机制可以在无窗口 Sim、zflecs 渲染世界、QA harness 中复用，不依赖具体 ECS 容器。
6. 机制可以独立测试；不需要启动完整游戏。

非目标：

- 现在就把整个 Sim 迁到 zflecs。
- 把所有公式放进 JSON 解释器。
- 为每个机制建一个独立 ECS world。

数据结构层面的逐项审计（ItemDef/SkillDef/EnemyDef/Hero/Enemy）见 [DATA_MODEL.md](DATA_MODEL.md)。

## 2. 机制总表

| ID | 机制 | 拥有的状态 | 主要输出 | 不能拥有 |
| --- | --- | --- | --- | --- |
| M0 | 确定性/RNG | RNG 流、seed、roll 顺序 | 随机数/roll 结果 | 战斗公式 |
| M12 | 定义/内容 | ClassDef/SkillDef/EnemyDef/ItemDef/StatusDef/DamageTypeDef | 只读定义 | 运行时角色状态 |
| M1 | 空间 | 地形、格子、占用、LOS、A*、范围形状 | walkable/los/path/shape | 回合、伤害、职业 |
| M2 | 时间 | 回合、能量、行动预算、冷却/持续时间时钟 | Actor 行动顺序/时间事件 | 具体动作效果 |
| M3 | 角色 | ActorId、阵营、职业 Tag、位置、生死 | Actor 生命周期事件 | 数值公式 |
| M4 | 属性 | 主属性、修正、派生面板、资源池 | Sheet/资源上限/修正 | 伤害扣血、回合 |
| M5 | 行动/目标 | ActionSpec、ActionRequest、合法性、效果列表 | 行动命令/效果 | 伤害减免、状态 tick |
| M6 | 伤害/生命 | Vitals、防御、抗性、伤害队列 | DamageEvent/DeathEvent | 回合推进、掉落 |
| M7 | 状态/效果 | StatusSet、持续时间、叠层、tick | 状态事件/修正/伤害包 | 直接修改 HP |
| M8 | 成长/经济 | XP、等级、背包、装备、掉落 | 等级/装备/掉落事件 | 楼层胜负 |
| M9 | 运行/遭遇 | RunState、楼层、Boss 封印、胜负条件 | 楼层/胜负事件 | 技能公式 |
| M10 | 感知/表现 | FOV、意图、瞄准预览、HUD/相机/日志 | 只读投影 | 修改 Sim |
| M11 | 持久化 | 快照/恢复、版本、原子写 | 文件/字节 | 玩法规则 |

## 3. 每个机制的契约

### M0 确定性/RNG

拥有：一条或多条命名 RNG 流，例如 combat、loot、generation。

规则：

- 所有随机必须来自 M0；禁止直接使用时间/系统随机。
- 预览（命中率、伤害范围）不能消耗 RNG。
- 保存必须保存 RNG 状态；读档后 roll 顺序一致。

当前债：Sim 只有一个 rng，crit/loot/generation 共用；短期可接受，长期拆流。

### M1 空间

拥有：

- Tile/Prop、静态 blocked；
- 占用查询（由调用方提供 actor 位置快照）；
- Manhattan/Chebyshev 距离；
- LOS；
- A*；
- 目标形状展开：single/line/cone/burst/ground。

API：

~~~zig
isWalkable(cell) bool
distance(a, b, metric) i32
lineOfSight(a, b, occupancy) bool
path(start, goal, occupancy) ?Path
cells(shape, origin, dir) []Cell
~~~

不做：

- 不决定谁能行动；
- 不计算伤害；
- 不知道职业。

当前债：

- Sim.hasLineOfSight 与 Dungeon.lineOfSightTo 重复；
- 远程/近战距离判定散落在 Sim/Target/Intent；
- AOE 形状只有圆形，且半径规则同时存在于 Target 和 Sim。

### M2 时间

拥有：

- TurnClock；
- Enemy.action.energy（100 点行动一次，上限 200）；玩家仍是一行动/回合；
- 行动预算；
- 冷却与持续时间的时钟推进；
- 时间事件：TurnStarted、ActorTurnStarted、ActorTurnEnded、RoundEnded。

推荐模型：turn-based 式能量。

~~~text
每个 tick: energy += speed
当 energy >= 100: 该 Actor 行动，energy -= 100
行动消耗 cost；不足则等待
~~~

这样速度 150 自然每 2 回合多一次行动，速度 70 自然少行动；不需要 turn % 2 特判。

不做：

- 不知道动作内容；
- 不直接扣血/加状态。

当前债：

- 敌人 energy 已替换 turn%2 特判；玩家速度仍不参与行动数。
- 能量/冷却/状态持续时间仍在 endTurn/enemyAct 各自推进，没有统一 TurnClock 事件。
- 冷却/状态持续时间在 endTurn/enemyAct 各自减，时钟不统一。

### M3 角色

拥有：

- ActorId、Faction、ClassTag、SpeciesTag；
- GridPosition；
- LifeState（alive/dead/despawned）；
- RenderRef（表现层弱引用）。

不做：属性、伤害、AI。

当前债：

- Sim 的 Hero/Enemy 已拆为组件聚合；渲染 zflecs 的 Hero/Enemy 仍是场景聚合，待投影拆分。
- 敌人 kind 同时承担模型、AI、Boss 判定、掉落表，多个机制读同一个裸 u8；精英词缀已作为 Enemy.affix 独立枚举。

### M4 属性

拥有：

- PrimaryStats；
- ModifierSet（source、stacking、duration）；
- DerivedSheet；
- ResourcePool（当前/上限/回复）。

系统：recomputeSheet；只读派生查询。

不做：扣血、行动、状态 tick。

当前状态：

- attributes.recompute 是唯一公式入口；六维存储为 PrimarySheet 的 6 个 Value；
- 攻击/护甲/暴击/速度存储为 4 个 Value；
- Sim.recomputeHero 已改为调用它；
- ClassDef / DerivedDef 已表单化。

仍缺：

- Modifier 的 stacking/source 规则未统一；
- 资源回复在 endTurn 中直接写，未经过资源系统；
- HP 已进入 Hero.vitals / Enemy.vitals（numeric.Health gauge）；Hero/Enemy 状态已统一为 StatusSet。

### M5 行动/目标

拥有：

- ActionSpec：id、cost、cooldown、range、shape、requires_los、effects；
- ActionRequest：actor、action、target/cell；
- 合法性校验与预览；
- 效果列表：Damage/Heal/Status/Move/Summon。

规则：

- validate/preview/resolve 必须使用同一个 ActionSpec。
- 目标形状由 M1 展开，不在这里写距离特判。
- 行动只产生效果；伤害由 M6 结算，状态由 M7 结算。

当前债：

- 玩家天赋规格在 run_target.specFor；
- 消耗/冷却在 Sim.talentCost/talentCooldown；
- 执行 switch 在 Sim.useTalentOn；
- skills.json 已有 SkillDef，但玩家天赋实际没走它；
- Boss 深渊斩是 Sim.enemyAct 的特判，不是 ActionSpec；骷髅/精英骷髅半血以下举盾 1 回合（受伤减半）；幽魂/精英幽魂每 3 次行动汲取（0.7×，回复 50% 伤害）；石魔像在距离 2 且有视线时每 3 次行动震地（0.4×，无破绽）；Boss 50% 血量召唤 1 只半血骷髅（入场眩晕 1 回合），35% 血量进入狂暴（攻击/速度提升，深渊斩周期不变）；
- 普攻、冲锋、火球、闪现、回溯各自一套校验。

### M6 伤害/生命

拥有：

- Vitals：hp/hp_max/shield；
- Defense：armor、resist table、damage reduction；
- DamagePacket：raw、type、crit、penetration、source、tags；
- DamageEvent/DeathEvent。

唯一管线：

~~~text
raw
 -> 类型增伤/减伤
 -> 暴击
 -> 抗性
 -> 护甲（仅 armor_applies 类型）
 -> 护盾
 -> HP
~~~

预览使用同一管线，但不 roll、不写状态。

不做：决定谁行动、掉落什么。

当前债（最高优先）：

- 已修：护甲公式统一走 combat.resolve，Sim 三处内联公式已删除；
- 已修：attributes.damageAfterArmor 由 combat 调用；
- 已修：Sim.intentFor 对预览应用同一减伤，HUD 不再高估；
- 暴击在 playerAttack 内联，intent 无法复用；
- 没有 DamageType/Resistance，所有伤害都是物理。

### M7 状态/效果

拥有：

- StatusDef：id、duration、stack、modifier payload、tick effect、tags；
- StatusSet：每个 Actor 的实例；
- 应用/移除/叠层规则；
- tick 时机（ActorTurnStart/End）。

不做：直接改 HP；tick 伤害走 M6。

当前债：

- StatusSet 已统一到 Hero.status / Enemy.status，方法集中 canAct / attackScale / slowDamageScale / tickBuff / applyStun / applySlow / applyBurn；火球附加 5 回合灼烧并最多叠 3 层（1/1.5/2 倍），Boss AOE 也点燃英雄；Boss 通过 stun_immune 免疫眩晕（减速/灼烧仍有效）；时空时间停止命中 Boss 时改为减速 2 + 0.5× 反噬；战士冲锋、石魔像命中、Boss 深渊斩都可附加 VULN（受伤 +20%）；
- 状态应用仍散落在 endTurn/enemyAct/useTalent（warcry、冰锥、冲锋、火球、Boss AOE）；
- 没有通用 StatusDef、叠层、驱散；只有 Boss 的 stun_immune 特判，无法用数据扩展新状态。

### M8 成长/经济

拥有：

- Progression：level/xp/curve；
- LootTable：drop 规则；
- Inventory/Equipment；
- 装备修正 -> M4 ModifierSet。

不做：决定楼层胜负。

当前债：

- XP/升级循环在 Sim.killEnemy；
- 掉落/装备在 RunGame；
- 装备修正通过 items.rebuild 再调 Sim.applyModifiers；
- 升级曲线硬编码 100*level；
- 自动加点与手动加点在 Sim/RunGame 分叉。

### M9 运行/遭遇

拥有：

- RunState：seed/floor/floors/state/floor_mod；
- FloorPlan：生成参数、Boss、楼梯、宝箱/陷阱预算；
- 胜负条件：Boss 死亡、楼梯封印、全灭；
- 存档边界。

不做：技能伤害、状态 tick。

当前债：

- hasLivingBoss / isFinalFloor / stairsSealed 已集中在 Sim；
- 胜负写入仍散落在 killEnemy/endTurn/nextFloor；
- Boss AOE 在 Sim；
- 楼层生成直接改 Sim 全体状态。

### M10 感知/表现

拥有：

- FOV/已探索；
- 敌人意图；
- 瞄准预览；
- HUD/相机/日志；
- 只读投影。

规则：

- 所有显示数值必须来自 M5/M6 的 preview API。
- 不允许自己复制伤害公式。

当前债：

- intent.zig 有自己的 damage scale，和 Sim 的 scale 重复；
- 瞄准预览与执行各自校验；
- HUD 直接读 Sim 的裸字段。

### M11 持久化

拥有：

- 每个机制的 snapshot/restore；
- 版本迁移；
- 原子写。

规则：

- 存档不包含 UI/相机瞬时状态；
- 读档不重算随机；
- 机制内部字段变更需要版本号。

当前债：

- save.zig 手写每个字段；
- 新机制加字段要同时改 save/load/test；
- 建议每个机制提供 snapshot，再由 RunState 聚合。

### M12 定义/内容

拥有：

- ClassDef、SkillDef、EnemyDef、ItemDef、StatusDef、DamageTypeDef；
- ID/Tag 注册表；
- 加载/校验/回退。

规则：

- 运行时只引用 DefId；
- 系统不硬编码名称/范围/消耗/冷却；
- 数据错误回退默认，不崩溃。

当前债：

- 玩家技能规格不在 skills.json 生效；
- 敌人 kind 是裸 u8，同时充当 AI/模型/Boss/掉落键；
- 职业表在 Zig，技能表在 JSON，两套配置协议。

## 4. 依赖矩阵

只允许向下依赖；向上通过事件。

| 机制 | 依赖 |
| --- | --- |
| M0 RNG | 无 |
| M12 定义 | 无 |
| M1 空间 | M12（地形/形状定义可选） |
| M3 角色 | M1 |
| M2 时间 | M0, M3 |
| M4 属性 | M0, M3, M12 |
| M5 行动 | M1, M2, M3, M4, M12 |
| M6 伤害 | M0, M3, M4 |
| M7 状态 | M2, M3, M4, M6 |
| M8 成长 | M3, M4, M12 |
| M9 运行 | M1, M3, M5, M8, M12 |
| M10 表现 | M1, M3, M4, M5, M6, M7, M9（只读） |
| M11 持久化 | 所有机制的快照接口（只读） |

事件方向：

~~~text
M5 ActionResolved
  -> M6 DamageEvent
  -> M7 StatusApplied / StatusTick
  -> M8 XpGained / LootDropped
  -> M9 EncounterEnded
  -> M10 presentation refresh
~~~

注意：M6 不直接调用 M7；它发出 HitEvent，M7 订阅。M7 的 tick 伤害再发 DamagePacket 给 M6，不形成调用环。

## 5. 正交性规则

新增/修改机制必须满足：

1. **单一写者**：一个字段只有一个机制能写；其他机制只能读或发命令。
2. **公式单一实现**：护甲、暴击、速度、XP 曲线各只有一个函数。
3. **查询/命令分离**：validate/preview 只读；resolve 产生事件。
4. **不跨机制改字段**：不允许在 Sim.useTalentOn 里直接改 enemy.hp；应发 DamagePacket。
5. **Tag 优先**：ClassTag、DamageType、TargetShape、StatusTag，不用 bool + switch 堆叠。
6. **时间统一**：冷却/持续时间只由 M2 时钟推进。
7. **随机统一**：所有 roll 走 M0，预览不 roll。
8. **ECS 容器无关**：机制数据结构不依赖 zflecs entity id；需要时用 ActorId 映射。
9. **可序列化**：每个机制有 snapshot/restore。
10. **可独立测试**：给一个最小 fixture 就能测机制，不启动 SDL。

## 6. 多个 ECS world 怎么覆盖

这里的 ECS 指执行容器，不是机制本身。

| World | 用途 | 机制如何存在 |
| --- | --- | --- |
| sim world | 确定性回合、存档、QA | 纯组件数组/SoA；M1-M9 的系统按阶段跑 |
| render world | zflecs：Transform/Renderable/Light/Shadow | M10 从 sim 投影；不反向写 sim |
| HUD/immediate | 面板/输入/瞄准 | M10 只读查询 sim |
| QA world | headless 批量 | 复用 sim world，不加载渲染 |

一个机制可以横跨多个 world：

- M1 空间在 sim 用于寻路，在 render 用于地面网格/相机拾取；
- M4 属性在 sim 算数值，在 HUD 显示；
- M5 行动在 sim 校验，在 HUD 预览。

因此机制的数据结构必须放在不依赖 SDL/zflecs 的模块里。

## 7. reference roguelike 对照

| reference roguelike | 抽象 | 我们的差异 |
| --- | --- | --- |
| Actor energy 1000 | M2 能量 | 敌人已有 ActionState.energy；玩家仍单行动 |
| DamageType + projector | M6 类型/管线 | 只有物理，公式三处重复 |
| Talents 数据 + function | M5 + M12 | 玩家天赋硬编码，skills.json 未生效 |
| Effects 表 | M7 | StatusSet 已统一；仍无 StatusDef/叠层 |
| Actor stats/combat | M4 | 已单表化，仍有 HP 当前值散落 |
| Zone/level generator | M9 | 31x31 单层 + 固定 3 层 |
| FOV | M10 | 暂无战争迷雾 |
| Save | M11 | 手写字段，v2 |

## 8. 当前违规优先级

### P0：先修，不改玩法

1. 护甲公式收敛到 M6：Sim 三处 + attributes。
2. intent 预览调用同一 M6 preview，避免 HUD 高估。
3. 玩家天赋的 cost/cooldown/range 从 M12 读，不写死在 Sim/Target。

### P1：行为重构

4. ✅ M2 敌人能量调度替代 turn%2；玩家行动数仍固定 1。
5. ✅ M7 StatusSet 替代 stun/slow/buff 字段。
6. ✅ M9 楼梯封印/最终层谓词集中；胜负写入仍待事件化。
7. M8 XP/掉落/装备事件化。

### P2：内容扩展

8. DamageType/Resistance 表。
9. M5 目标形状 Tag（line/cone/burst）。
10. M11 每机制 snapshot。

## 9. 改动配方

### 新职业

- M12 ClassDef 一行；
- 3 个 SkillDef；
- HUD 卡片配置；
- 不改 Sim 公式、不改存档字段（除非新资源）。

### 新伤害类型

- DamageType Tag；
- DamageTypeDef 一行（armor_applies/resist default）；
- 技能数据引用；
- M6 管线自动生效；
- 不改每个技能。

### 新状态

- StatusDef 一行；
- 若需要新 tick 语义，加一个 effect handler；
- Actor 不加 bool 字段。

### 新目标形状

- TargetShape Tag；
- M1 cells() 一个分支；
- M5 校验/预览自动复用。

### 新楼层机制

- M9 EncounterRule；
- 不改 Sim.killEnemy/endTurn。

## 10. 迁移顺序

1. **M6 伤害管线**（行为不变，先消灭三份公式）。
2. **M5 ActionSpec + M12 玩家技能**（行为不变，先让 skills.json 生效）。
3. **M2 能量调度**（行为变化，单独 PR + QA 平衡）。
4. **M7 StatusSet**（行为等价迁移）。
5. **M9 RunState/胜负谓词**。
6. **M8 成长/掉落事件**。
7. **M11 snapshot 化**。
8. 最后再评估 Sim 是否值得上 zflecs。

## 11. 需要确认的决策

1. 时间模型：采用 turn-based 式能量（推荐），还是保留现在的偶数回合特判？
2. 伤害类型：第一版做 物理/火焰/冰霜/奥术/时空 五类，还是先只做物理 + 抗性接口？
3. ECS 边界：确认 sim 用纯组件数组、render 用 zflecs 投影，不把 Sim 整体迁 zflecs？
4. 配置边界：职业/公式用 Zig comptime 表，物品/技能用 JSON，是否接受？

在这些决策确认前，不建议继续堆新天赋/新状态；否则会把更多逻辑写进错误的层。
