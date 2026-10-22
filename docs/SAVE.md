# 存档模块（RunState v1）

纯逻辑的 ToME 存档/读档，位于 `src/game/save.zig`，已通过 `zig build test`。
**尚未接入 UI / main**；本文件同时给出 F5/F9 的接入建议。

## 范围

保存的是 `tome_sim.Sim` 的整局运行状态（RunState），不包含 `TomeGame` 的渲染/背包/掉落 RNG：

| 分类 | 字段 |
| --- | --- |
| 顶层 | format、version、seed、class、floor、floors、turn、state、kills、chest_loot、kill_loot、rng |
| hero | pos、last_pos、stats(6)、hp、hp_max、resource、resource_max、attack、armor、crit、speed、res_per_turn、level、xp、cooldowns(3)、buff_turns、buff_pct、eff_stats(6) |
| enemies | kind、name、pos、hp、hp_max、attack、armor、speed、range、xp、stun_turns、slow_turns、alive |
| map | blocked(169)、entrance、stairs、chests(4)/chest_alive(4)、traps(4)/trap_alive(4)、aoe_target、aoe_armed |
| 日志 | 最近 6 条，按从旧到新保存 |

JSON 由 `std.json` 生成，**压缩（无空白）**；一局第 2 层约 2.7 KB。

## API

```zig
const save = @import("save.zig");

// 核心：纯内存，测试/QA/headless 用这两个
const bytes = try save.saveAlloc(alloc, &sim);   // 调用方负责 alloc.free
var loaded = try save.loadAlloc(alloc, bytes);   // 严格校验，坏档返回 error

// 文件：Zig 0.17 的 std.Io 风格（和 png.writePng 一致）
try save.saveFile(io, alloc, "saves/tome.json", &sim);
var from_disk = try save.loadFile(io, alloc, "saves/tome.json");
```

- `saveAlloc` / `loadAlloc` 不碰文件、不依赖 SDL，可在任意测试里用。
- `saveFile` 的父目录需已存在（与截图路径一致，调用方可先 `createDirPath`）。
- `loadFile` 只读打开；解析失败时原文件保持原样，便于排查坏档。

## 严格校验

读取时逐项检查，任一失败返回 `error`（不 panic、不返回半成品）：

- `format` / `version` 必须匹配；JSON 之后不允许再有 token（TrailingData）。
- 枚举（class、state）由 `std.json` 按 tag 名校验；未知 tag = `InvalidEnumTag`。
- 所有坐标必须在 13×13 内；hero、敌人、stairs、entrance、活着的宝箱/陷阱必须落在可行走格。
- 地图外圈必须封闭；活着的宝箱/陷阱不能重叠、不能压楼梯/入口；敌人 kind 与 name 必须成对匹配。
- 数值范围：hp∈[0,hp_max]、resource∈[0,resource_max]、crit∈[0,1]、level∈[1,50]、speed∈[1,1000]；所有浮点必须有限。
- 长度：敌人 ≤ 12、日志 ≤ 6 条且每行 ≤ 64 字节、输入 ≤ 256 KB。
- RNG 状态不能全 0。

错误类型见 `save.SaveError`；`save.LoadError` 另外包含 `std.json` 的解析错误。

## 可复现性

- 存档记录 **xoshiro256 的完整内部状态**（4×u64），读档后 `Sim.rng` 从同一位置继续。
- 测试覆盖：读档后原局与读档局继续跑 40 步，逐字段一致（含暴击/伤害、敌人移动、掉落计数、日志）。
- 如果未来 Zig 更换 `std.Random.DefaultPrng`，需要同步升级 `save_version`；也可以退化为只存 seed+turn 并在读档时 `init(seed ^ turn)`，但那样无法保证暴击序列可复现。

## 导入后的地图

不逐格保存 `dungeon.Dungeon` 的 tiles/props；读档时用 `blocked` + stairs/chests/traps 重建。
模拟只通过 `Dungeon.isWalkable` 做 LOS/A*，所以行为一致；下一层会从 seed+floor 重新生成。
因此地图装饰（柱子/水/火盆）和敌人出生点标记不跨读档保留（不影响玩法）。

## F5/F9 接入建议（TomeGame 侧）

存档（F5）：

```zig
if (std.fs.path.dirname(path)) |dir| std.Io.Dir.cwd().createDirPath(io, dir) catch {};
save.saveFile(io, self.gpa, path, &self.sim) catch |err| {
    self.sim.pushLog("存档失败 {s}", .{@errorName(err)});
};
```

读档（F9）：

```zig
const loaded = save.loadFile(io, self.gpa, path) catch |err| {
    self.sim.pushLog("读档失败 {s}", .{@errorName(err)});
    return; // 保留当前局
};
self.sim = loaded;
self.seed = loaded.seed;
self.class = loaded.class;
self.inventory = .{};                 // 背包/装备不在 RunState 里
self.mods.clear();
self.last_level = loaded.hero.level;
self.chest_loot_seen = loaded.chest_loot_events;  // 防止掉落重放
self.kill_loot_seen = loaded.kill_loot_events;
self.rebuildMesh();                   // 地图可能来自另一层
self.resetVisuals();
self.fillHudState();
```

要点：

1. **背包/装备不在存档里**：`TomeGame.inventory/mods/content` 属于表现+装备层。F9 要么清空背包，要么后续把装备也做成 RunState 的一部分（并升 version）。
2. **掉落 RNG**：`loot_rng` 是 `TomeGame` 自己的 RNG，未保存。按上面的 `*_seen = sim.*_loot_events` 赋值可避免已结算的掉落重新发放；若要严格复现掉落品质，需要把 `loot_rng` 状态和背包一起加入存档。
3. **floor 变化**：读档后必须 `rebuildMesh()`，否则 3D 场景还是旧层。
4. **坏档不覆盖**：`loadFile` 失败时不要动 `self.sim`；原文件也不会被改写。
5. **R/重开**：`restart()` 会重新 `Sim.reset`，与读档互不影响；F5/F9 建议只在 `state == .playing` 时启用。
