# QA 报告 — 实时战斗基线

- 分支：feat/qa-harness（基于 feat/tactical-v1；基线代码点 5d58567 + 本次 QA 提交）
- 环境：Windows、Zig 0.17.0、ReleaseFast、内部分辨率 480x270、固定步长 1/60、无窗口。
- 证据：qa-results/baseline/（3 场景 JSON+CSV）、qa-results/baseline/auto5/（5 连跑）、qa-results/baseline/hero1、hero2。

> 结论：当前实时原型在硬性不变量上全部通过（0 violations），5 波可通关；平衡指标只部分达标；发现 1 个低危代码缺陷（P3）与若干平衡/未实现项。团队已转向回合制（docs/TOME_V1.md），本报告作为遗留基线保留。

## 1. 运行命令

~~~powershell
zig build test                                   # 单元 + 集成 + QA 回归，通过
zig build qa                                     # 3 场景 x 9000 帧 -> qa-results/latest
zig build qa -- --scenario all --out-dir qa-results/baseline
zig build qa -- --scenario auto --runs 5 --out-dir qa-results/baseline/auto5
zig build qa -- --scenario auto --hero 1 --out-dir qa-results/baseline/hero1
zig build qa -- --scenario auto --hero 2 --out-dir qa-results/baseline/hero2
~~~

## 2. 基线结果（9000 帧 = 150s）

| 场景 | 结果 | 通关时刻 | wave | kills | deaths | 存活 | 终局 HP 合计 | Boss 时长 | tris | violations |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| no-auto（无输入） | victory | 86.92s | 5 | 21 | 2 | 3 | 164.1 | 24.62s | 19898 | 0 |
| auto（每 1.5s 施法） | victory | 75.05s | 5 | 21 | 1 | 3 | 180.3 | 24.62s | 19898 | 0 |
| walk（持续前进） | victory | 86.10s | 5 | 21 | 3 | 3 | 148.0 | 23.75s | 19898 | 0 |

三场景都是先到第 5 波、清完 21 个敌人后胜利；没有出现 defeat，也没有 victory+defeat 同时为真。

## 3. 每波时长（清空时刻，不含 2s 休整）

| 波 | auto | no-auto | walk | 目标 15–30s |
| ---: | ---: | ---: | ---: | --- |
| 1 | 4.90s | 4.90s | 6.37s | 偏短 |
| 2 | 13.45s | 13.45s | 14.95s | 略短/达标 |
| 3 | 12.18s | 23.45s | 15.83s | 达标（auto 偏短） |
| 4 | 11.75s | 12.35s | 17.05s | 偏短 |
| 5（Boss） | 24.62s | 24.62s | 23.75s | 达标 |

## 4. BALANCE_V1 场景 6：auto 5 连跑

qa-results/baseline/auto5/auto-runs.json：

| 指标 | 值 | v1 目标 | 判定 |
| --- | ---: | --- | --- |
| 通关率 | 5/5 = 100% | 70–90% | 超出上限（且 5 次逐位相同，实际样本量 1） |
| 平均通关时长 | 75.05s | 90–140s | 偏短 |
| 总死亡 | 5（每次 1） | 0–2 / 局 | 达标 |
| Boss 时长 | 24.62s | 20–35s | 达标 |
| violations | 0 | 0 | 通过 |

确定性说明：critRoll 是 time/pos 的确定性函数，没有 RNG，因此 5 连跑完全相同；要评估 70–90% 通关率必须先引入种子/随机（或按不同英雄/天赋组合分层）。

## 5. 起始英雄敏感性（auto，9000 帧）

| 起始英雄 | 结果 | 通关时刻 | deaths | 终局 HP | Boss 时长 | 每波时长 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 0 狂战士 | victory | 75.05s | 1 | 180.3 | 24.62s | 4.9 / 13.4 / 12.2 / 11.7 / 24.6 |
| 1 元素法师 | victory | 38.27s | 0 | 312.5 | 7.32s | 3.0 / 5.5 / 7.0 / 7.3 / 7.3 |
| 2 时空法师 | victory | 45.42s | 0 | 308.3 | 7.35s | 3.0 / 10.3 / 10.3 / 6.3 / 7.3 |

只有当前英雄会施法，起始英雄决定技能 DPS：法师开局把整局压到 38–45s，Boss 只打 7.3s，远低于 20–35s 目标；狂战士开局则接近目标区间。这是平衡问题，不是崩溃。

## 6. 空闲冻结探测（BALANCE_V1 场景 1 的基线事实）

idle_probe 为第 300 帧快照；max_enemy_travel/damage_taken 为前 300 帧累计：

| 场景 | 第 300 帧 wave/kills | 首次受伤帧 | 累计受伤 | 敌人最大位移 | 判定 |
| --- | --- | ---: | ---: | ---: | --- |
| no-auto | wave 1 / kills 3 | 57（0.95s） | 36.75 | 3.705 | 空闲时敌人移动并造成伤害 → 未冻结 |
| auto | wave 1 / kills 3 | 57 | 27.75 | 3.705 | 同上 |
| walk | wave 1 / kills 2 | 80（1.33s） | 10.00 | 7.881 | 同上 |

因此 BALANCE_V1 场景 1/2（Frozen/Flowing 切换）在当前基线上不成立——属于未实现的时间模型，不是回归。

## 7. 不变量与回归结果

- src/qa/regression.zig 全部通过（zig build test）：波次单调、victory/defeat 互斥、活敌人 hp 不为负且不超上限、target 始终有效、R 重开满血、同一次致命伤害只产生一个死亡事件。
- Harness 逐帧检查 kill 事件与敌人消失数一致：三场景、5 连跑、hero 变体全部 0 mismatch。
- 渲染指标：终局 tris 19898、draw_calls 72–75，与 README 的约 19k 三角形一致。

## 8. Bug 列表

### QA-BUG-01（P3，真实代码缺陷）：致命伤害后敌人 hp 会短暂为负

- 现象：systems.damageEnemy 直接执行 enemy.hp -= amount，没有下限；超额伤害会把 hp 打到负数，直到同一 tick 末尾 cleanupEnemies 删除该实体。
- 复现：zig build test（用例 “QA: lethal damage emits exactly one death event”），或对任意存活敌人连续调用两次 1_000_000 伤害；第一次后 hp 为 -999,9xx，第二次返回 0 且不再发事件。
- 影响：当前无玩家可见影响（tick 边界上活敌人 hp 必为正，harness 0 violations）；但会污染未来的伤害日志/DoT/ActionState 结算，建议在 systems.zig 改为 enemy.hp = @max(0, enemy.hp - amount)。
- 归属：Lead（src/game/systems.zig），QA 不改核心。

### 平衡/设计发现（非崩溃）

1. QA-BAL-01（P2）：确定性战斗无法度量 70–90% 通关率；建议加入种子或分层矩阵。
2. QA-BAL-02（P2）：起始英雄主导整局时长（38s vs 75s）与 Boss 时长（7.3s vs 24.6s），需要让伙伴 AI 也施法或调整主动技能收益。
3. QA-BAL-03（P3）：第 1 波 4.9–6.4s、第 4 波 11.7–12.4s，低于 15–30s 目标；walk 场景 3 次死亡超过 0–2 目标。

## 9. 尚未实现（BALANCE_V1/TACTICAL_V1 目标，不计为 bug）

- 时间冻结/流动/威胁三态；F 反制（输入已接线，无逻辑）。
- 施法前摇/后摇/移动取消；ActionState。
- 六属性派生、装备三槽、掉落、背包（I 面板壳已存在，数据为空）、XP/升级。
- 单次重击占最大生命 <=35% 的校验对象不存在（敌人只有普攻）。
- 上述条目在回合制（docs/TOME_V1.md）里将被重新设计，回合制 QA 见 docs/QA_PLAN_TOME.md。
