# 存档模块（RunState v2）

纯逻辑的 turn-based 存档/读档，位于 `src/game/save.zig`；窗口已接入 **F5 存档 / F9 读档槽位**（`RunGame.saveSlot/loadSlot`），装备侧车在 `src/game/gear_save.zig`。

## 范围

保存分两部分：

- `saves/run.json`：`run_sim.Sim` 的整局运行状态（RunState，含 xoshiro RNG）。
- `saves/gear.json`：`RunGame.inventory` 的背包与装备槽（`gear_save.zig`，format `vx-run-gear`）。

渲染/相机/当前镜头不保存；掉落 RNG 存在 gear 侧车（loot_rng），读档后从同一位置继续。

| 分类 | 字段 |
| --- | --- |
| 顶层 | format、version、seed、class、floor、floors、turn、state、kills、chest_loot、kill_loot、rng |
| hero | pos、last_pos、stats(6)、hp、hp_max、resource、resource_max、attack、armor、crit、speed、res_per_turn、level、xp、pending_points、cooldowns(3)、buff_turns、buff_pct、burn_turns、burn_damage、eff_stats(6) |
| enemies | kind、affix、name、pos、hp、hp_max、attack、armor、speed、range、xp、stun_turns、slow_turns、burn_turns、burn_damage、alive、energy |
| map | blocked(961)、entrance、stairs、chests(4)/chest_alive(4)、traps(4)/trap_alive(4)、aoe_target、aoe_armed、boss_enraged、shrine、shrine_active、shrine_used、floor_mod |
| 日志 | 最近 6 条，按从旧到新保存 |

JSON 由 `std.json` 生成，**压缩（无空白）**；一局第 2 层约 2.7 KB。

## API

```zig
const save = @import("save.zig");

// 核心：纯内存，测试/QA/headless 用这两个
const bytes = try save.saveAlloc(alloc, &sim);   // 调用方负责 alloc.free
var loaded = try save.loadAlloc(alloc, bytes);   // 严格校验，坏档返回 error

// 文件：Zig 0.17 的 std.Io 风格（和 png.writePng 一致）
try save.saveFile(io, alloc, "saves/run.json", &sim);
var from_disk = try save.loadFile(io, alloc, "saves/run.json");
```

- `saveAlloc` / `loadAlloc` 不碰文件、不依赖 SDL，可在任意测试里用。
- `saveFile` 的父目录需已存在（与截图路径一致，调用方可先 `createDirPath`）。
- `loadFile` 只读打开；解析失败时原文件保持原样，便于排查坏档。

## 严格校验

读取时逐项检查，任一失败返回 `error`（不 panic、不返回半成品）：

- `format` / `version` 必须匹配；JSON 之后不允许再有 token（TrailingData）。
- 枚举（class、state）由 `std.json` 按 tag 名校验；未知 tag = `InvalidEnumTag`。
- 所有坐标必须在 31×31 内；hero、敌人、stairs、entrance、活着的宝箱/陷阱必须落在可行走格。
- 地图外圈必须封闭；活着的宝箱/陷阱不能重叠、不能压楼梯/入口；敌人 kind 与 name 必须成对匹配。
- 数值范围：hp∈[0,hp_max]、resource∈[0,resource_max]、crit∈[0,1]、level∈[1,50]、speed∈[1,1000]；所有浮点必须有限。
- 长度：敌人 ≤ 12、日志 ≤ 6 条且每行 ≤ 64 字节、输入 ≤ 256 KB。
- RNG 状态不能全 0。

错误类型见 `save.SaveError`；`save.LoadError` 另外包含 `std.json` 的解析错误。

## 可复现性

- 存档记录 **xoshiro256 的完整内部状态**（4×u64），读档后 `Sim.rng` 从同一位置继续。
- 测试覆盖：读档后原局与读档局继续跑 40 步，逐字段一致（含暴击/伤害、敌人移动、掉落计数、日志）；pending_points 显式 round-trip。
- 如果未来 Zig 更换 `std.Random.DefaultPrng`，需要同步升级 `save_version`；也可以退化为只存 seed+turn 并在读档时 `init(seed ^ turn)`，但那样无法保证暴击序列可复现。

## 导入后的地图

不逐格保存 `dungeon.Dungeon` 的 tiles/props；读档时用 `blocked` + stairs/chests/traps 重建。
模拟只通过 `Dungeon.isWalkable` 做 LOS/A*，所以行为一致；下一层会从 seed+floor 重新生成。
因此地图装饰（柱子/水/火盆）和敌人出生点标记不跨读档保留（不影响玩法）。

## 破坏性变更

- **v2（当前）**：地图从 13×13 升到 31×31。v1 存档里的坐标和 seed 生成结果不再对应，**不做迁移**，读取时返回 UnsupportedVersion。
- 玩家提示固定为：读档失败：v1 旧档不兼容，请开新局；不再把 UnsupportedVersion 裸英文名写进战斗日志。
- 错误映射：NotSaveFormat / EmptySave / SaveTooLarge / InvalidCoordinate / InvalidEnemyKind / InvalidLog / InconsistentMap 都有中文原因，未知错误回退为“存档损坏或无法读取”。
- **规则**：以后 bump save_version 时必须同时更新本节、loadErrorText 的提示，以及一个 v(N-1) fixture 测试；如果只是新增可忽略字段，优先保持版本并做默认值兼容。
- 日志缓冲区每行只有 64 字节，loadErrorText 的提示必须控制在约 45 字节以内，否则 pushLog 会静默丢弃。

## F5/F9（已接入）

窗口里：

- **F5**：打开存档槽位面板；按 1/2/3 保存到对应槽，Esc 取消。
- **F10**：打开自动档面板，1/2/3 读取最近 3 个楼层备份；下到新楼层时写入 saves/autosave1.save 并轮换 1→2→3，失败只写日志。
- **F9**：打开读档槽位面板；按 1/2/3 读取；Esc 取消。坏档/未知物品/版本不符/空 gear 对象只写日志并保留当前局。读档后重建 mesh、视觉、HUD，清空瞄准。
- 三个槽位：1=saves/slot1.save，2=saves/slot2.save，3=saves/slot3.save；每个文件是 vx-run-slot 容器，内含 run JSON + gear JSON，一次原子 replace。旧 run/gear 双文件仍可回退读取，但 v1（13×13）run 会被版本校验拒绝。
- 职业菜单底部提示 **F9 读档槽**；没有 gear 文件时按空背包读取，装备 sidecar 缺失不会阻断 Sim。

实现入口：RunGame.saveSlot/loadSlot 选槽，内部仍调用 saveRun/loadRun；src/game/gear_save.zig 有 saveFile/loadFile。

要点：

1. **坏档不覆盖**：`loadFile` 只读，校验失败不会改写文件，也不会动 `self.sim`。
2. **背包/装备**由 gear sidecar 保存；旧档缺 gear 时背包为空，但 Sim 状态仍可用。
3. **掉落 RNG**：gear sidecar 的 `loot_rng` 保存 xoshiro256 状态；读档后续接同一掉落序列。旧档没有该字段（全 0）时回退 `init(seed ^ turn)`，并靠 `*_seen = sim.*_loot_events` 防重放。
4. **地图**由 blocked + stairs/chests/traps 重建，装饰不跨档；不影响 LOS/A*。
5. **R/重开**：`restart()` 重新 `Sim.reset`，与读档互不影响。
6. **成对提交**：新槽位使用单文件容器，run/gear 一次写入；只有回退旧双文件档时才是两次写。
