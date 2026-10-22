# QA2 — TomeSim 回归与批量模拟报告

> 工作树 `D:\code\zig\vx-qa2`，分支 `feat/tome-qa2`，已合并 `origin/main`（c2251e5）。
> 本轮只新增测试/工具与本文档，**未改 TomeSim 行为**，未合并任何 PR。
> 运行日期：2026-10-22；Zig 0.17.0（Windows x86_64）。

## 1. 结论摘要

- **生成矩阵**：100 个 seed × 3 层，全部通过 `dungeon.validate()`；入口→楼梯 A* 路径逐步相邻且可走；宝箱/出生/陷阱标记唯一、在界内、不在墙与门上；TomeSim 的 blocked 映射、英雄入口位置、敌人生成全部一致。
- **非法行动**：100 个 seed 的越界移动、零位移、撞墙、终局状态下的 move/wait/talent 全部返回 `false`，回合数、HP、敌人位置均不变（没有偷偷跑敌人回合）。
- **自动策略批量**：100 个 seed × 3 职业 = **300 局**，0 超时、0 不变量违规；**通关 0 局（0.0%）**，300 局全部死亡（F2 = 3，F3 = 297）。
- **重大回归信号**：合并 main 的 Boss 深渊斩（AOE）后，自动策略从 20.0% 通关跌到 0.0%；固定 seed 12345 三职业全部在第 3 层阵亡。详见第 6.1 节。
- **可复现报告**：固定 seed 12345 连跑两次，state/turn/floor/kills/掉落/装备/HP/坐标逐项相等。

## 2. 测试矩阵

| ID | 不变量 / 目标 | 方法 | 结果 |
| --- | --- | --- | --- |
| QA2-G1 | 100 seed × 3 层可生成且合法 | `Dungeon.generate` + `validate`；预算计数（宝箱 2–4、出生 4–8、陷阱 ≤4） | 通过 |
| QA2-G2 | 入口→楼梯地形可达 | `astarTo(entrance, stairs, null)`，校验端点、逐步 4 邻接、路径格可走 | 通过 |
| QA2-G3 | 标记无重叠、无越界 | 宝箱/出生/陷阱三组两两比较 + 与入口/楼梯比较 + `isInterior` | 通过 |
| QA2-G4 | 出生不重叠、不越界 | TomeSim `generateFloor` 后校验敌人两两不同格、不在英雄格、在界内且非墙；英雄在入口 | 通过 |
| QA2-M1 | 非法移动不消耗回合 | 100 seed：越界 4 方向、`(0,0)`、撞墙、victory/dead 下的 move/wait/talent；对比 turn/HP/state/首个敌人位置 | 通过 |
| QA2-A1 | 一次合法行动 = 一个回合 | 每个自动动作后断言 `turn == before+1`（victory 终局允许 +0/+1） | 通过 |
| QA2-A2 | floor 只增、最多 +1 | 每动作后对比 floor；victory 时 floor ∈ {3,4} | 通过 |
| QA2-A3 | HP / 资源不为负且不超上限 | 每动作后断言 `0 ≤ hp ≤ hp_max`、`0 ≤ resource ≤ resource_max`（含装备重算与 Boss AOE 之后） | 通过 |
| QA2-A4 | 死亡/胜利互斥 | state 单枚举；dead ⇒ hp ≤ 0；victory ⇒ hp > 0 且 floor ≥ 3；batch 断言 wins + deaths + timeouts = runs | 通过 |
| QA2-A5 | 敌人占位不变量 | 每动作后：存活敌人 hp > 0、死亡敌人 hp = 0、两两不同格、不穿墙、不与英雄重叠 | 通过 |
| QA2-R1 | 固定 seed 逐位可复现 | seed 12345 × 3 职业各跑两次，比较 15 个字段 + 最终坐标 | 通过 |
| QA2-R2 | 指标采集 | 通关率、平均回合、平均到达层、死亡楼层分布、击杀、掉落事件、物品/装备掉落与生效数 | 见第 4 节 |

## 3. 命令与结果

~~~powershell
zig build --summary all          # 11/11 steps succeeded
zig build test --summary all     # 13/13 steps succeeded; 93/93 tests passed
zig build test-qa --summary all  # 3/3 steps succeeded; 71/71 tests passed
~~~

- `zig build test` 在既有用例之外跑本文件 4 个 QA 用例（合并 main 后 93 = 合并前 74 + main 的 intent/tome_sim 用例 + QA2 的 4 个）。
- `zig build test-qa` 是聚焦入口（`src/qa2_test.zig` → `src/qa2/tome_regression.zig`）；71 个用例 = 4 个 QA 用例 + 该入口直接 import 到的 dungeon/tome_sim/intent/content/attributes/items 既有测试。它不影响默认 `test` step。
- **工具链备注**：Zig 0.17 在测试向 stderr 打印时，`--summary all` 会多打一行 `failed command:`；退出码与 `N/N tests passed` 才是判定依据（本仓库与一个最小复现工程都能复现该现象，与测试失败无关）。

### 指标口径

| 指标 | 口径 |
| --- | --- |
| seed | `0x51A2_0000 + i * 104729`（i = 0..99） |
| class | 批量：每个 seed 跑 warrior/mage/chronomancer 各一次；固定报告：seed 12345 × 三职业 |
| turns | 终局时的 `Sim.turn` |
| 死亡楼层 | state=dead 时的 `Sim.floor` |
| loot_events | `chest_loot_events + kill_loot_events`（宝箱 + 击杀触发的掉落事件） |
| items / equip_drops | 用与 `TomeGame.grantDrop` 相同的确定性流程掷点：loot RNG = `seed ^ 0x9e3779b97f4a7c15`，宝箱必掉、击杀按 `drop_chance`；equip_drops 为掷出可装备物品数 |
| equip_used | 按 `TomeGame.grantDrop` 的“优于当前槽位才自动装备”规则实际装上并调用 `Sim.applyModifiers` 的次数 |
| timeout | 1200 回合内未终局（本轮 0 次） |

## 4. 批量指标（100 seeds × 3 职业 = 300 局，合并 main 后）

| 指标 | 全部 | 狂战士 | 元素法师 | 时空法师 |
| --- | ---: | ---: | ---: | ---: |
| 局数 | 300 | 100 | 100 | 100 |
| 通关 | 0（0.0%） | 0 | 0 | 0 |
| Boss 击杀通关 | 0 | — | — | — |
| 楼梯绕过通关 | 0 | — | — | — |
| 死亡 | 300 | 100 | 100 | 100 |
| 超时 | 0 | 0 | 0 | 0 |
| 平均回合 | 59.8 | 65.5 | 54.5 | 59.3 |
| 平均到达层 | 2.99 | — | — | — |
| 击杀总数 | 2794 | — | — | — |
| 掉落事件 | 3153 | — | — | — |
| 物品掉落 | 1181 | — | — | — |
| 装备掉落 | 977 | 340 | 341 | 296 |
| 装备生效（自动装上） | 601 | 214 | 214 | 173 |

死亡楼层分布：**F1 = 0，F2 = 3，F3 = 297**。全部 300 局都在 78 回合内结束（最长为 seed 1372608469 狂战士），远低于 1200 回合上限；最高击杀为 seed 1369676057 元素法师（11 杀，F3）。

对照（合并 main 前，同一 harness、同一 300 局）：通关 60（20.0%），平均回合 67.7，击杀 3003，死亡 F1=0/F2=3/F3=237。Boss AOE 合入后通关率归零、平均回合缩短约 8 回合、击杀减少约 200。

### 固定 seed 12345（可复现报告，合并 main 后）

| 职业 | 结果 | 回合 | 楼层 | HP | 等级 | 击杀 | 掉落事件 | 物品 | 装备掉落/生效 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 狂战士 | dead | 68 | 3 | 0/188 | 2 | 10 | 10 | 2 | 2/2 |
| 元素法师 | dead | 54 | 3 | 0/124 | 2 | 9 | 9 | 1 | 1/1 |
| 时空法师 | dead | 60 | 3 | 0/147 | 2 | 9 | 9 | 1 | 1/1 |

同一 seed/职业跑两次，上述字段与最终坐标完全一致。合并 main 前同一 seed 狂战士为 victory（turn 82、剩 26 HP），法师/时空法师 F3 阵亡。

## 5. 失败样本（可复现）

| seed | 职业 | 结果 | 回合 | 楼层 | 等级 | 击杀 | 掉落事件 | 装备掉落/生效 |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1375436152 | 时空法师 | dead | 40 | 2 | 2 | 6 | 8 | 4/2 |
| 1378473293 | 时空法师 | dead | 35 | 2 | 2 | 6 | 6 | 1/1 |
| 1379834770 | 时空法师 | dead | 35 | 2 | 2 | 6 | 6 | 1/1 |
| 1369571328 | 狂战士 | dead | 66 | 3 | 2 | 10 | 10 | 4/4 |
| 1369571328 | 元素法师 | dead | 54 | 3 | 2 | 9 | 9 | 4/4 |
| 1369571328 | 时空法师 | dead | 57 | 3 | 2 | 9 | 9 | 4/3 |
| 12345 | 狂战士 | dead | 68 | 3 | 2 | 10 | 10 | 2/2 |
| 12345 | 元素法师 | dead | 54 | 3 | 2 | 9 | 9 | 1/1 |
| 12345 | 时空法师 | dead | 60 | 3 | 2 | 9 | 9 | 1/1 |

失败形态：

- **F2 阵亡（3/300）**：全部是时空法师，35–40 回合、6 杀、装备尚未成形；不是被墙卡死（0 超时），而是数值/技能交换失败。
- **F3 阵亡（297/300）**：绝大多数局能清到第 3 层并见到 Boss，但在深渊斩 + Boss 近战下被击杀；没有出现回合数打满或来回振荡的局。

## 6. 已知风险与未覆盖

### 6.1 重大：Boss AOE 后自动策略 0/300 通关（合并 main 引入）

- 现象：同一 harness 在合并 main 前 300 局通关 60（20.0%）；合并后 **0/300**，300 局全部死亡，其中 297 局死在 F3。固定 seed 12345 从“狂战士胜利”变成三职业全灭。
- 代码路径：`src/game/tome_sim.zig:522` 的 `enemyAct` 在 Boss（kind 5）且 `intent_mod.bossAoeDue(self.turn)`（`src/game/intent.zig:131`，`turn % 3 == 0`）时，**无条件**结算深渊斩：`attack * 2.8`（16 × 2.8 = 44.8 原始伤害）× 护甲减免（英雄护甲 8–15 时约 0.86–0.87），单次约 39–40 点，然后直接 `return`，不检查距离/LOS，也不进入普通攻击/追击分支。唯一能阻止它的是 stun（在更早的 `stun_turns > 0` 分支 return）。
- 后果：Boss 420 HP，自动策略在 3 次深渊斩（约 9 回合）内就会被打死；纯逻辑层没有药水/治疗手段，装备成型前不可能打完 Boss。
- 判定：这是**平衡/设计回归信号**，不是 QA 不变量错误（0 超时、0 违规）。自动策略本身与 `TomeGame.autoPlayStep` 同款、不含喝药，因此真实玩家表现可能略好，但仍建议在合入 Boss AOE 前确认射程/冷却/伤害或给自动策略加保命手段。
- 建议（本轮未改代码）：给深渊斩加距离/LOS/预警回合的约束，或降低 `boss_aoe_damage_scale`/提高周期，或让自动策略在低血时使用药水；重新跑 `zig build test-qa` 观察通关率。

### 6.2 其它风险

1. **职业平衡差距（合并前基线）**：合并 main 前自动通关率 43% / 13% / 4%，死亡集中在第 3 层；Boss AOE 后差距被“全灭”掩盖。若要用于调数值，需要 Lead 先给目标通关率。
2. **每层敌人数被截断为 4**：`tome_sim.generateFloor` 的 `max_spawns` 对 1/2/3 层都是 4，而 `TOME_V1.md` / README 写“每层 4–8 个敌人”，`dungeon.spawnsForFloor` 在第 2/3 层分别给 6/8 个出生点。当前 F2/F3 的难度曲线比文档预期平，且与“随层数增加”的描述不符。
3. **第 3 层楼梯可绕过 Boss**：`Sim.move` 踩到楼梯即 `nextFloor`，`floor > floors` 直接 `victory`，不要求击杀深渊守卫。本轮自动策略 0 次走这条线（`stairs_wins=0`），但代码路径可达；需要设计确认是否允许。
4. **README 基线漂移**：README 写“seed 12345 第 80 回合击败第 3 层守卫，剩 51 HP”“74/74 tests”；当前为 93/93 tests，且 seed 12345 在 Boss AOE 后三职业全部阵亡。建议更新 README 的验证基线与测试计数。
5. **掉落指标依赖内容表**：QA 断言 `content.load` 未走 fallback（使用嵌入 JSON），但指标仍是“不喝药、自动装备”的纯逻辑基线；背包满、手动换装、药水使用未建模。
6. **自动策略是确定性启发式**：不是最优或随机玩家；只覆盖“走向楼梯、撞敌、放 1/2/3、低血休息”一条路径。渲染、输入、面板、相机不在本轮范围。
7. **种子族固定**：100 个 seed 来自固定公式，不是随机 fuzz；生成矩阵覆盖 300 层、批量覆盖 300 局，但极端布局（如敌人恰好堵住唯一通路）只有理论分析，未做对抗搜索。
8. **动态阻挡未纳入 A* 保证**：入口→楼梯可达性是按地形（无动态占用）验证的；批量 0 超时说明实际未被 4 个敌人永久堵死，但测试没有显式断言“带占用的可达性”。

## 7. 文件与复现入口

| 文件 | 作用 |
| --- | --- |
| `src/qa2/tome_regression.zig` | 回归/批量模拟实现 + 4 个 QA 用例 + 指标打印 |
| `src/qa2_test.zig` | `zig build test-qa` 的独立入口（module root = `src`） |
| `src/root.zig` | 增加一行 `pub const tome_regression = ...`，让 QA 用例随默认 `zig build test` 运行（与 main 的 `intent` 导出并存） |
| `build.zig` | 新增 `test-qa` step；默认 `test` step 不变 |

复现：

~~~powershell
zig build test-qa --summary all
# 期望：Build Summary 3/3 steps succeeded; 71/71 tests passed
# 日志中 [qa2] 开头的行即第 4 节指标
~~~

不变量失败时，harness 会打印 `[qa2] invariant failed seed=... class=... step=... turn=... floor=...: <错误名>`，可直接定位 seed/职业/动作序号。若通关数为 0，harness 额外打印 `[qa2] WARNING: 0/300 autoplay wins...`（不使测试失败，便于 CI 记录平衡回归）。
