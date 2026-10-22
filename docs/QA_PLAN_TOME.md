# QA 计划 — ToME4 风格回合制（TOME v1）

> 设计基线：docs/TOME_V1.md。当前状态：**骨架就绪，真实一局待 API 合并**。
> 实时战斗基线（遗留）见 [QA_PLAN.md](QA_PLAN.md) 与 [QA_REPORT.md](QA_REPORT.md)，在回合制 API 落地前继续保留。

## 1. 目标与边界

- 覆盖：回合经济、格子占位、撞墙/撞敌、敌人回合与速度、冷却/资源按回合、地牢确定性/连通性/楼梯、死亡与 R 重开。
- 不覆盖：实时系统（Formation/Movement/EnemyAI/HeroCombat）——按 TOME_V1 第 10 节它们不再用于战斗。
- 不改核心玩法：QA 只写测试/骨架/文档；回合制实现属于 Lead / 程序 A（turn.zig）、程序 C（dungeon.zig）。

## 2. 当前可运行内容

~~~powershell
# 骨架自检（不依赖未合并的 turn/dungeon API）
zig build test -Dturn-qa=true

# 默认 CI 不受影响（骨架默认不编译）
zig build test
~~~

src/qa/turn_regression.zig 目前包含：

1. 一份实现 TOME v1 规则的确定性参考模型 RefModel（13x13、墙、敌人、速度、冷却、stairs、3 层）。
2. 通用不变量检查函数（assertWallBumpRejectsWithoutTurn、assertNoOverlapOrWallOccupancy、assertDungeonConnected、assertEnemyOrderRespectsSpeed 等），签名只依赖 probe 方法，合并后可直接指向真实 Game。
3. 9 个骨架用例：撞墙不消耗回合、一次合法行动一回合、撞敌=普攻、300 回合占位不重叠/不穿墙、stairs 进层与第 3 层胜利、死亡结束 + R 重开、同 seed 同布局、20 个 seed 连通性/楼梯可达、冷却与资源按回合结算、敌人按速度行动。

> 注意：这些用例当前验证的是“检查器 + 参考模型”，不是真实游戏。合并后必须新增 GameProbe 并让同一批 assert 跑在真实状态上，报告才能引用为真实回归结果。

## 3. 测试矩阵（真实 API 合并后执行）

| ID | 不变量 | 方法 | 现状 |
| --- | --- | --- | --- |
| T-01 | 玩家一次行动只推进一个回合 | 记录 turn 计数，分别 move/wait/talent/attack | 骨架已写 |
| T-02 | 撞墙/越界/非法天赋/无目标攻击不消耗回合 | 对比行动前后 turn | 骨架已写 |
| T-03 | 撞敌 = 普攻：敌人掉血、玩家不位移、回合消耗 | 相邻敌人 + move 输入 | 骨架已写 |
| T-04 | 敌人每回合按速度行动；速度 >=150 有额外行动 | 记录 actor 顺序与行动次数 | 骨架已写（参考模型） |
| T-05 | cooldown/资源按回合结算，不按秒 | 连续 wait，检查 cooldown/资源差值 | 骨架已写 |
| T-06 | 无实时自动攻击：玩家不输入时回合数不变 | 空转 N 帧后 turn 不变 | 待 API |
| T-07 | 玩家/敌人不可重叠、不可穿墙 | 随机走 500 回合后逐格校验 | 骨架已写 |
| T-08 | stairs 进入下一层；第 3 层 Boss 后胜利 | 走到 stairs，校验 floor/victory | 骨架已写 |
| T-09 | 死亡 = 结束；R 重开恢复初始状态 | 强制死亡 + reset | 骨架已写 |
| T-10 | 同 seed 同布局；不同 seed 布局不同 | layout hash 对比 | 骨架已写 |
| T-11 | 每层连通，stairs 与所有敌人可达 | BFS from spawn | 骨架已写 |
| T-12 | 回合驱动不改变渲染/相机（旋转不消耗回合） | Q/E 输入后 turn 不变 | 待 API |

## 4. 合并后的真实跑局入口（待实现）

计划新增 src/qa_tome_main.zig + build.zig 的 qa-tome step，参数与指标：

~~~powershell
zig build qa-tome -- --seed 1234 --class warrior --max-turns 2000 --out-dir qa-results/tome
~~~

输出 JSON/CSV 指标：seed、class、turns、floor、kills、deaths、outcome(victory|dead|timeout)、turns_per_floor、enemies_left、stairs_found、talents_used、layout_hash、tris、violations。
自动策略（v1）：BFS 到 stairs；相邻敌人则普攻；否则按天赋可用性使用 1/2/3；无路可走则 wait。
验收：同 seed 跑两次 JSON 除耗时外逐位一致；violations == 0；能自动通关 3 层（至少 1 个职业）。

## 5. 期望 API 对接面（给 Lead / 程序 A、C）

QA 的 probe 适配器只需要以下只读观测 + 行动入口；命名可协商，但建议固定：

- Game：turn（u32）、floor（u8）、player（entity）、dead/victory（bool）、kills（u32）。
- turn.zig：玩家行动入口（返回 消耗回合/非法/结束）、last actor order、每 actor 行动次数。
- grid.zig：isWall(x,y)、actorAt(x,y)、宽高、stairs 坐标。
- dungeon.zig：generate(alloc, seed, depth) 返回可复现布局；level hash 或等价的可比较摘要。
- InputFrame：move、wait、attack、talent1..3、reset（旋转/相机不消耗回合）。

合并后 QA 的工作：实现 GameProbe（约 100 行适配器）-> 把第 3 节矩阵的 assert 指向真实状态 -> 跑真实一局 -> 在 QA_REPORT_TOME.md 记录 turn/floor/kills/deaths 与违规项。

## 6. 确定性验收细节

- 生成：同 seed + 同 depth 的墙/敌人/stairs/宝箱布局必须逐格一致；QA 用 layout hash 对比。
- 连通：从出生点 BFS 必须能到 stairs；所有敌人初始格可达；不允许出现被墙完全封死的房间。
- 占位：任意 tick 边界，玩家与存活敌人两两不同格，且都在非墙格。
- 回合：非法行动（撞墙、冷却中天赋、资源不足、无目标）不得改变 turn、冷却、资源、敌人位置。
- 存档/重开：R 之后 turn=0、floor=1、HP/资源满、敌人重生成且与首次开局一致。

## 7. 平衡指标（待 Lead 给出 TOME 目标后填表）

TOME_V1 未定义数值目标；建议首轮采集：每层回合数、每层受伤、击杀/掉落数、Boss 回合数、三职业通关率、自动策略通关率。回合制报告模板与实时版一致：目标值 / 实测 / 判定 / 复现命令。

## 8. 风险

- API 命名/结构可能与第 5 节不同；QA 的适配器是唯一改动点，测试矩阵不随之重写。
- 骨架参考模型不等于游戏实现，禁止把骨架结果当作真实回归结论。
- 回合制合并后，实时 harness（src/qa_main.zig）是否保留由 Lead 决定；当前两套互不干扰。
