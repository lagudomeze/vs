# DUNGEON — 13×13 网格与楼层生成

> 模块：程序 C（网格与关卡生成）交付，分支 `feat/dungeon-ai`。
> 源文件：`src/game/dungeon.zig`；单元测试 14 个，全部无渲染、无 SDL/GPU。
> 依赖：仅 Zig 标准库，不 import Game / ECS / renderer / assets。

## 1. 目标与边界

提供 reference roguelike 风格回合制地牢所需的全部网格逻辑：

- 13×13 网格、边界墙、入口与远端 stairs；
- 确定性楼层生成（房间、柱子、碎石、水域、火盆、宝箱、陷阱、敌人出生点）；
- 可走性 / 占位位图（occupancy）、4/8 邻接、Bresenham 视线、4 方向 A*；
- 生成结果自检 `validate()`。

**不负责**：3D 网格与渲染、模型/资产加载、敌人种类与数值、回合调度、Game 状态机、宝箱/陷阱结算、Boss 特殊房。这些由 Game / HUD / 内容层接。

所有对象都是值类型、无 allocator、无全局状态：`Dungeon` 约 0.5 KB，`Path` 约 1.4 KB，可直接放在 Game 结构体里。

## 2. 坐标与方向

| 项目 | 约定 |
| --- | --- |
| 尺寸 | 13×13，`size = 13`，`cell_count = 169` |
| x 轴 | 向东（+X） |
| y 轴 | 向南（+Z，屏幕俯视时的下方） |
| 原点 | 格 (6, 6) 对应世界 (0, 0) |
| 世界换算 | `x_world = (x - 6) * 1.0`，`z_world = (y - 6) * 1.0` |
| 格尺寸 | `tile_size = 1.0`，与 `arena_mesh.tile_half = 6` 对齐 |

- `GridPos.toWorld()` 返回 `WorldPos{ x, z }`，直接用于 `math.Vec3.init(w.x, 0, w.z)`。
- `GridPos.fromWorld(wx, wz)` 返回最近格；棋盘外返回 `null`。
- 入口只会出现在内部边缘：bottom = y 11（约 60%）、left = x 1（约 20%）、right = x 11（约 20%）。
- stairs 在对侧内部边缘，入口到 stairs 的 Manhattan 距离 ≥ 8（正常为 10 以上）。
- 四周最外圈在数据上永远是 `wall`；入口/stairs 是紧贴内壁的格子，不是墙上的开口。
- ASCII 行序为 y = 0..12、列序为 x = 0..12。

## 3. Tile 与 Prop 约定

### 3.1 Tile

| Tile | 可走 | glyph | 含义 | 渲染建议 |
| --- | --- | --- | --- | --- |
| `floor` | 是 | `.` | 普通地板 | 地砖 |
| `wall` | 否 | `#` | 边界墙 / 内部隔墙 | wall、wall_gate |
| `stairs` | 是 | `<` | 下一层入口 | stairs |
| `chest` | 是 | `C` | 宝箱（可交互） | chest |
| `trap` | 是 | `^` | 陷阱（踩上触发） | trap |
| `obstacle` | 否 | `X` | 柱子/碎石/水/火盆 | 由 Prop 决定 |

要点：

- `wall` 与 `obstacle` 同时阻挡移动和视线；`floor` / `stairs` / `chest` / `trap` 可走。
- 宝箱和陷阱是“地板上的可交互物”，不阻挡移动；是否已开启/触发由 Game 记录，不要靠占位位图挡。
- 占位（角色）与地形是两层：地形由 `Dungeon` 判断，动态角色由调用方传入 `Occupancy`。
- 如果以后想让水可走，只改 `Tile.isWalkable` 或把水变成独立 Tile；A*/LOS/validate 会自动跟随。

### 3.2 Prop（只用于 `obstacle`）

| Prop | glyph | modelName | 阻挡 | 说明 |
| --- | --- | --- | --- | --- |
| `none` | — | null | 否 | 非障碍 |
| `column` | `I` | `column` | 是 | 房间柱子 |
| `rubble` | `,` | `rocks` | 是 | 碎石 |
| `water` | `~` | null | 是 | 渲染器自绘水面（暂用阻挡语义） |
| `brazier` | `*` | `brazier` | 是 | 火盆，建议额外加点光源 |

`Prop.modelName()` 返回 `assets/baked/<name>.vxm` 的模型名（water 返回 null）。
`Dungeon.propAt(p)` 查询；非障碍格返回 `none`。

## 4. 生成算法与保证

`Dungeon.generate(seed: u64, floor: u8)` 的执行顺序：

1. 整张图填 `wall`。
2. 用 `mixSeed(seed, floor)` + Xoshiro256++ 选入口侧，放置入口与 stairs。
3. 从入口到 stairs 挖一条 L 形主脊（1 格宽），并标记为“不可装饰”。
4. 入口房：沿入口边 4–6 格宽、向内 3–4 格深。
5. stairs 房：同样的尺寸在对侧。
6. 主脊拐点房：3–5 × 3–5 的中间房。
7. 地图中心房：以 (6, 6) 为心的 3–5 × 3–5 房间，用 L 形走廊接入主脊。
8. 70% 概率在空闲角落加一个 3×3 小室（vault），用 L 形走廊接入主脊拐点。
9. 装饰：房间内缩角柱子（2 或 4 根）、2–4 个火盆、1–2 处 2–4 格水域、2–4 处碎石；若障碍不足 4 个，追加碎石。
10. 每个障碍落点都先做一次 flood fill：**放下去后仍保持全图连通才允许放**；主脊格永远不放。
11. 从入口做 BFS 距离场，再依次放陷阱（1/2/3 个）、宝箱（2/3/4 个）、敌人出生点（4/6/8 个）。
    - 陷阱优先距入口 ≥ 3 格（空间不足时回退）；
    - 宝箱优先放在远离入口的格子（4 级筛选 + 间距要求）；
    - 出生点优先距入口 ≥ 3 格，第一个出生点优先 ≥ 6 格，后续用最远点采样尽量分散；计数不足时回退到任意空格，保证达到楼层预算。

不变量（`validate()` 检查）：

- 最外圈全部 `wall`；
- 入口/stairs 在内部且 terrain 正确，二者 Manhattan 距离 ≥ 8；
- 宝箱 2–4、敌人出生点 4–8、陷阱 ≤ 4；
- 所有标记在界内、terrain 匹配、同类不重复、彼此不重叠、不压入口/stairs；
- 从入口 4 邻接 flood fill 能到达 stairs、所有宝箱/出生点/陷阱，以及**全部可走格**（无孤岛）。

确定性：

- 同一 `seed` + 同一 `floor` 必定生成完全相同的 `Dungeon`（测试用 `std.meta.eql` 验证）。
- 不同 seed 布局不同；同一 seed 的不同 floor 也不同。
- floor = 0 会被归一化为 1；floor > 3 时内容数量饱和。
- 确定性依赖固定的绘制顺序与 `std.Random.DefaultPrng`；同一 Zig 版本内稳定，升级 Zig 标准库后不保证跨版本完全一致（若要跨版本复现，请把生成结果存种子表或自实现 PRNG）。

## 5. API

### 5.1 常量

| 名称 | 值 | 说明 |
| --- | --- | --- |
| `size` / `width` / `height` | 13 | 棋盘尺寸 |
| `cell_count` | 169 | 总格数 |
| `tile_size` | 1.0 | 世界格宽 |
| `world_center` | 6.0 | 格心偏移 |
| `min_chests` / `max_chests` | 2 / 4 | 宝箱数量范围 |
| `min_spawns` / `max_spawns` | 4 / 8 | 敌人出生点范围 |
| `max_traps` | 4 | 陷阱上限 |
| `min_entrance_stairs_distance` | 8 | 入口-楼梯最小距离 |
| `max_path` | 169 | Path 固定容量 |

### 5.2 GridPos / WorldPos

```zig
pub const GridPos = struct { x: i32 = 0, y: i32 = 0 };

GridPos.init(x, y)                 // 构造
p.eql(other)                       // 相等
p.inBounds()                       // 0..12
p.index()                          // y * 13 + x
GridPos.fromIndex(i)               // 反解
a.manhattan(b) / a.chebyshev(b)    // 距离
p.toWorld() -> WorldPos{ x, z }
GridPos.fromWorld(wx, wz) -> ?GridPos
w.toGrid() -> ?GridPos
```

### 5.3 Tile / Prop 辅助

```zig
walkable(tile) -> bool             // 等价于 tile.isWalkable()
tile.isWalkable() / tile.ascii()
prop.blocksMovement() / prop.modelName()
```

### 5.4 Dungeon 查询

```zig
tileAt(p) / setTile(p, tile)
propAt(p) / setProp(p, prop)
isWalkable(p)                                  // 只看地形，界外=false
isBlocked(p, occupancy: ?*const Occupancy)     // 地形 + 占位，界外=true
blockCtx(occupancy) -> BlockCtx                // 给泛型算法用
astarTo(start, goal, occupancy) -> ?Path
astarToOccupiedGoal(start, goal, occupancy) -> ?Path
lineOfSightTo(from, to, occupancy) -> bool
chestSlice() / spawnSlice() / trapSlice()      // []const GridPos
countTile(tile) -> usize
glyphAt(p) -> u8
renderAscii(buf) -> []const u8                 // buf 至少 182 字节
```

`Dungeon` 的字段（`seed`、`floor`、`entrance`、`stairs`、`chests`、`chest_count`、`enemy_spawns`、`spawn_count`、`traps`、`trap_count`、`tiles`、`props`）是公开的，方便渲染/序列化；正常逻辑请优先用上面的方法。

### 5.5 生成与数量预算

```zig
Dungeon.generate(seed: u64, floor: u8) -> Dungeon
Dungeon.filled(tile: Tile) -> Dungeon          // 全图同一种 tile，测试/工具用
chestsForFloor(floor: u8) -> usize             // 1:2  2:3  3+:4
spawnsForFloor(floor: u8) -> usize             // 1:4  2:6  3+:8
trapsForFloor(floor: u8)  -> usize             // 1:1  2:2  3:3  4+:4
d.validate() -> ValidateError!void
```

`validate()` 错误：`BorderOpen`、`InvalidEntrance`、`InvalidStairs`、`EntranceTooClose`、`BadChestCount`、`BadSpawnCount`、`BadTrapCount`、`MarkerOutOfBounds`、`MarkerTerrain`、`MarkerOverlap`、`DuplicateChest`、`DuplicateSpawn`、`DuplicateTrap`、`UnreachableStairs`、`UnreachableMarker`、`UnreachableFloor`。

### 5.6 算法

`neighbors4(p, &out4)` / `neighbors8(p, &out8)`：只返回界内邻居，返回写入数量；顺序固定（4 邻为 上/右/下/左，8 邻顺时针）。

`lineOfSight(from, to, ctx)`：Bresenham；两个端点不参与阻挡判断（可以瞄准墙格），中间格必须能通过 `ctx.isBlocked`；界外返回 false。`ctx` 只需要有 `isBlocked(GridPos) bool` 方法；`Dungeon.blockCtx(occ)` 是现成适配器。

`astar(start, goal, ctx) -> ?Path`：

- 4 方向移动（和 WASD 一致），Manhattan 启发；
- 返回的 `Path` 包含起点与终点，`path.slice()[0]` 是当前格，`path.slice()[1]` 是下一步；
- 起点允许被占（角色从自己的格子出发），终点必须可走/不被 `ctx` 阻挡；
- 无路返回 `null`；固定数组，无分配，无异常。

`astarToOccupiedGoal`：目标格允许被角色占用（典型用法：敌人寻路到玩家脚下），但目标地形仍必须可走；配合 `path.slice()[1]` 走一步，或判断“下一步 == 目标”时攻击。

`Occupancy`：169 位 `StaticBitSet`。`set` / `unset` / `isSet` / `count` / `clearAll` / `rebuild(positions)`。每回合角色移动后重建一次即可。

`Path`：`slice()`、`first()`、`last()`，容量 `max_path = 169`。

## 6. 楼层难度

| floor | chests | spawns | traps | 说明 |
| --- | --- | --- | --- | --- |
| 1 | 2 | 4 | 1 | 新手层，骷髅/幽魂 |
| 2 | 3 | 6 | 2 | 石魔像/精英开始出现 |
| 3 | 4 | 8 | 3 | Boss 层，敌人最多 |
| >3 | 4 | 8 | 4 | 饱和（v1 只有 3 层） |

- 使用 `chestsForFloor` / `spawnsForFloor` / `trapsForFloor` 生成内容，不要在 Game 里再写一份数字。
- 敌人种类按 `docs/RUN_V1.md` §7 的楼层表由内容层决定；本模块只给位置。
- Boss 建议：在 `spawnSlice()` 里挑离入口 Manhattan 最远的点作为 Boss 位，其余作为普通怪；或把 stairs 房中心改造成 Boss 房（需要额外内容层逻辑）。
- 生成器保证同一格不会同时是宝箱/出生点/陷阱/入口/stairs；敌人通常不会在距入口 3 格内开局（极窄地图会回退）。

## 7. 集成清单（Lead 需要改的部分）

1. **导入**：`src/root.zig` 已加 `pub const dungeon = @import("game/dungeon.zig");`，Game 里可直接 `const dungeon = @import("dungeon.zig");` 或从 `vx.dungeon` 取。
2. **Game 状态**：增加 `run_seed: u64`、`floor: u8`、`map: dungeon.Dungeon`、`occupancy: dungeon.Occupancy`。`Dungeon` 是值类型，放在 Game 字段里即可。
3. **开局/下层**：
   ```zig
   self.map = dungeon.Dungeon.generate(self.run_seed, self.floor);
   self.map.validate() catch @panic("bad dungeon");
   const start = self.map.entrance.toWorld();
   // hero Transform.pos = .{ .x = start.x, .y = 0, .z = start.z }
   ```
   玩家出生在 `entrance`，面朝 stairs 或地图中心；相机跟随逻辑不用改（它跟着 Transform）。
4. **场景网格**：`arena_mesh.buildArena` 现在还是固定竞技场。需要为 dungeon 模式新增一个 “按 tile 生成” 的网格函数（或扩展 arena_mesh）：
   - 每个可走格放地砖；每个 `wall` 格放墙块（内部隔墙也要）；
   - `obstacle` 按 `propAt` 映射到 `column` / `rocks` / `brazier`；水需要自绘水面；
   - `chest` / `trap` / `stairs` 放对应资产；
   - 火盆格额外加一个 `LightSource`（世界位置用 `toWorld()`，高度约 0.5）。
   当前 13×13 的世界坐标换算与旧的 `arena_mesh` 完全一致（tile_half=6、tile_size=1），不需要改相机。
5. **角色占位**：每回合玩家/敌人行动后重建：
   ```zig
   var cells: [max_actors]GridPos = undefined;
   var n: usize = 0;
   // 填入玩家 + 所有存活敌人的 GridPos.fromWorld(transform.pos.x, transform.pos.z)
   self.occupancy.rebuild(cells[0..n]);
   ```
6. **玩家移动**：把输入方向换算成 4 邻目标格；若 `map.isBlocked(target, &occ)`：
   - 目标被占 → 撞敌人 = 普攻（消耗回合）；
   - 地形阻挡 → 不消耗回合；
   - 否则移动一格（Transform 继续做 0.12s 插值），然后：
     - `target.eql(map.stairs)` → 下一层（或第 3 层胜利）；
     - `target.eql(map.chests[i])` → 开箱（建议 Game 维护 opened 位图，不要改 `chest_count`），可把 tile 设成 `floor` 做视觉开启；
     - `target.eql(map.traps[i])` → 触发陷阱结算。
7. **敌人 AI**：
   ```zig
   const path = self.map.astarToOccupiedGoal(enemy_cell, player_cell, &self.occupancy) orelse ...;
   const step = path.slice()[1]; // 0 是敌人自身
   // step == player_cell -> 近战；否则移动；远程用 lineOfSightTo 判断
   const can_shoot = self.map.lineOfSightTo(enemy_cell, player_cell, &self.occupancy);
   ```
   注意 A* 是 4 方向；远程保持距离时用 Manhattan/Chebyshev 或世界距离均可。
8. **HUD**：stairs 方向可用 `map.stairs` 与玩家格比较；小地图可用 `glyphAt` 或 `renderAscii`；楼层信息用 `map.floor`。
9. **清理旧逻辑**：dungeon 模式下不要再用 `spawnArena` 的固定火盆/雕像/战利品，也不要再让 wave/Formation 系统驱动敌人；保留 title/lineup 的旧竞技场路径。
10. **测试**：在 Game/QA 里加一个 headless smoke：三层 `generate + validate + astar(entrance, stairs)`，以及“玩家从入口走 5 步后占用/回合”的测试；不要引入渲染依赖。

**不需要改**：`src/game/turn.zig`（程序 A）只要在行动结算后调用本模块的查询/寻路；`attributes/items/content` 只需读 `chestSlice/spawnSlice`。

## 8. 集成示例

```zig
const std = @import("std");
const dungeon = @import("game/dungeon.zig");

var map = dungeon.Dungeon.generate(run_seed, 1);
try map.validate();

// 出生点世界坐标
const hero_world = map.entrance.toWorld();

// 每回合重建占位
var occ = dungeon.Occupancy{};
occ.rebuild(actor_cells); // 玩家 + 存活敌人

// 玩家移动
const player_cell = dungeon.GridPos.fromWorld(hero.pos.x, hero.pos.z).?;
const target = dungeon.GridPos{ .x = player_cell.x + 1, .y = player_cell.y };
if (occ.isSet(target)) {
    // 撞敌人 -> 普攻
} else if (!map.isBlocked(target, &occ)) {
    // 移动；之后检查 stairs/chest/trap
}

// 敌人追击（允许目标格被玩家占用）
const path = map.astarToOccupiedGoal(enemy_cell, player_cell, &occ);
if (path) |p| {
    const step = p.slice()[1];
    _ = step;
}

// 远程视线
const can_shoot = map.lineOfSightTo(enemy_cell, player_cell, &occ);
```

## 9. ASCII 示例

图例：`>` 入口、`<` 楼梯、`C` 宝箱、`^` 陷阱、`e` 敌人出生点、`I` 柱子、`,` 碎石、`~` 水域、`*` 火盆、`#` 墙、`.` 地板。

`seed = 2026, floor = 1`（2 宝箱 / 4 出生点 / 1 陷阱）：

```
#############
#.Ce...^.<..#
#.....,I....#
#,....C...Ie#
###.#.......#
###..,~.##.##
###.#.~~##.##
###.#.~*##.##
#.,...*###.##
#.I....##~..#
#e...I.##~~.#
#..>...##~e.#
#############
```

`seed = 42, floor = 3`（4 宝箱 / 8 出生点 / 3 陷阱）：

```
#############
#e..#########
#...#########
#*.*#########
#.C.#e.C#####
#.e.#...*..e#
#<^..C..e.C.#
#.^.#..,...^#
#e..#,e.....#
########.I..#
########,.I>#
########.e..#
#############
```

## 10. 测试与验收

- `zig test src/game/dungeon.zig`：14 个测试全部通过（无渲染）。
- `zig build test`：全项目测试通过（本模块通过 `src/root.zig` 的 `refAllDecls` 自动纳入）。
- 覆盖：
  1. 同 seed + floor 完全复现（`std.meta.eql`），floor 0 归一化；
  2. 不同 seed 布局不同；
  3. 100 次生成全部 `validate()` + A* 入口到 stairs 可达 + 数量预算；
  4. 楼层预算函数；
  5. A* 绕墙、直走、起终点相同、目标封死；
  6. A* 允许目标被占用（`astarToOccupiedGoal`）；
  7. Bresenham LOS 被墙/占位阻挡；
  8. Occupancy 阻挡移动与寻路、`rebuild`/`clearAll`；
  9. 13×13 边界与 4/8 邻接数量、索引往返；
  10. 全部 169 格的世界坐标往返；
  11. `validate` 能报出边界开口、数量错误、重复出生点、标记地形错误、入口-楼梯过近、stairs 被封；
  12. ASCII 输出行数/标记 glyph；
  13. Tile/Prop 可走表、模型名。

QA 可直接用 `renderAscii` 做 headless 快照，用 `validate` 做生成回归。

## 11. 已知限制与后续

- A* 只走 4 邻；没有对角移动/冲锋专用直线寻路。冲锋可在 Game 里做射线 + 阻挡判断。
- LOS 是经典 Bresenham，不是 supercover；对角线擦墙角可能“看到”，需要更严格时在 Game 层加两侧格检查。
- 房间都是矩形，没有门/钥匙/暗门/Boss 专属房；3 层以后内容饱和。
- 水域目前是阻挡语义（`obstacle`），没有游泳/减速。
- 生成器不跟踪已开启宝箱/已触发陷阱；运行时状态请由 Game 维护（例如 169 位 opened/triggered 位图）。
- `validate()` 只适合生成后/QA；运行时修改了 `tiles` 或 `chest_count` 后不要再调用，否则会按生成期不变量报错。
- `Dungeon` 按值拷贝；`BlockCtx` 持有指向 `Dungeon` 的指针，调用期间不要让 Dungeon 移动/重新赋值（放在 Game 字段里没问题）。
- 确定性只在同一 Zig/标准库版本内保证。
- 本次没有拆 `src/game/grid.zig`：为避免与程序 A 的 grid 接口文件冲突，类型和算法都在 `dungeon.zig`。如果后续要独立 grid 模块，可从本文件 re-export 或平移到 `grid.zig`，API 不变。
