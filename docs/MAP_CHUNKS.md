# 地图边界邻接 / Chunk 设计

## 现状

- 单张 31×31 固定地图，相机跟随并夹边。
- 31×31 已大于 640×360 视口；本轮先把相机拉远范围从 7–18 扩到 10–28。
- 地图边缘仍是墙，没有邻接区块。

## 目标

做出 ToME/Elona 式“走到边缘进入相邻区块”，但分阶段，不一次性重构。

## 阶段 A：视野（已完成）

- 鼠标滚轮 10–28 拉近/拉远。
- 帮助页显示 WHEEL ZOOM。
- 截图：docs/screenshots/zoom_out.png。
- 不改存档/地图结构。

## 阶段 B/C：3×3 垂直切片（实验实现）

目标：验证“边缘门 → 邻接图 → 返回”是否好玩，先不做 3×3。

当前状态：F2 第9项或 --chunks 启用 3×3 九宫格；关闭时冻结当前 Arena；首次进入未访问 chunk 恢复 20% HP/资源，visited 随 v3 存档；中心 chunk 起始，Arena 快照 + 四向边缘门 + 往返状态保留已实现并有单测；边界门只朝存在的邻居开；minimap 四向金点标记存在的邻居（截图 docs/screenshots/chunk_hud.png）。限制：默认关闭；v3 存档已包含 9 个 Arena 与当前 chunk（v2 单图仍可读）；存档体积上限 1 MiB；qa2 新增 20 seed × 四向 chunk 往返 + v3 存读测试，以及 10 seed × 200 步跨图长局不变量测试。

1. Sim 增加 chunk: GridPos（先支持 0/1 两张）。
2. 当前地图/敌人/宝箱/陷阱打包成 Arena 值类型（已完成）：
   - map
   - blocked
   - stairs
   - chests / chest_alive/free
   - traps
   - enemies / enemy_count
3. Sim 保留 hero、背包、RNG、floor、timer 等跨 chunk 状态。
4. enterChunk(dir)：
   - 保存当前 Arena（值拷贝）
   - 从 seed+chunk 确定性生成/恢复目标 Arena
   - 英雄放在对应入口
5. 边缘门：去掉边界中点 1–2 格墙，放 gate 标记；踩上触发。
6. 存档先只支持单 Arena；跨 chunk 时提示“原型版暂不存档”或 bump v3。

验收：

- 两张图来回走，敌人/宝箱状态不重置。
- 走上/下/左/右门位置正确。
- 相机、minimap、QA 不崩。
- 单测：enterChunk 往返后 hero 位置/Arena 状态一致。

## 阶段 C：3×3 + 持久化（已完成）

- chunk: GridPos 支持 -1..1；visited bitmask。
- 存档 v3：Arena 数组 + chunk 坐标；旧档拒绝并提示。
- Minimap 显示当前 chunk 与已访问邻接。
- 边缘门在小地图上有方向标记。
- QA：跨 chunk 100 seed 不变量；存档往返。

## 不做

- 无缝滚动加载（world streaming）。
- 无限地图。
- 跨 chunk 敌人寻路（先限制在各自 Arena）。

## 任务拆分

| 任务 | 文件 | 验收 |
| --- | --- | --- |
| Arena 聚合 | run_sim.zig | 单测保存/恢复 |
| 边缘门生成 | dungeon.zig | 四向门坐标稳定 |
| enterChunk | run_sim.zig | 往返一致 |
| 相机/minimap | run_game.zig/run_hud.zig | 不裁切 |
| 存档 v3 | save.zig | 旧档拒绝、往返 |
| QA | qa2/qa3 | 跨 chunk 不变量 |

## 为什么不在本轮直接做

当前 Sim 的 map/enemies/chests 都是平铺字段，直接加 chunk 会同时改生成、存档、渲染、QA。先做垂直切片，避免一次改爆。


## A/B（20 seed，战士，900 步上限）

| 模式 | 通关 |
| --- | --- |
| 单图 | 8/20 |
| 3×3，每 60 步进入一个邻接 chunk，新 chunk 回 20% | 3/20 |

这是**强制跨图**的机器人策略，不等于玩家自然探索；但它说明当前平衡下，频繁跨图会明显增加难度（更多敌人/资源分散）。因此默认保持 OFF，F2 第9项供想探索的玩家开启。
