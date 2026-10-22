# ART PASS — 战术精英 / 威胁环 / ToME 地牢套件

> 分支：`feat/art-pass`（基于 `feat/tactical-v1`，未 push）
> 约束：480×270、64 色像素风、真 3D 网格；所有颜色为逐三角形平面色，无贴图/外部素材。
> 本文记录模型名、tris、颜色、制作与集成方式，以及已知限制。

## 0. 交付一览

| 类别 | 模型 | tris | 状态 |
| --- | --- | ---: | --- |
| 战术精英 | `elite_skeleton` | 1664 | 已烘焙，待 Lead 接敌人生成 |
| 战术精英 | `elite_wraith` | 2228 | 已烘焙，待 Lead 接敌人生成 |
| 威胁预警 | `threat_ring` | 490 | 已烘焙（additive）；ToME v1 主线暂不集成，保留备用 |
| 地牢地砖 | `dungeon_floor` | 84 | 已烘焙 |
| 地牢地砖 | `dungeon_floor_cracked` | 96 | 已烘焙 |
| 地牢墙体 | `wall_segment` | 360 | 已烘焙 |
| 地牢楼梯 | `stairs_down` | 349 | 已烘焙 |
| 地牢宝箱 | `dungeon_chest` | 200 | 已烘焙 |
| 地牢陷阱 | `trap_spikes` | 188 | 已烘焙 |
| 地牢陷阱 | `trap_rune` | 388 | 已烘焙 |

所有模型都由 `tools/characters.py` / `tools/bake_assets.py` 生成，经 `assets/baked/*.vxm` 内嵌；不要手改二进制。地牢套件单模型均 < 1500 tris；精英 < 2500 tris。

截图（全部 480×270，headless 渲染）：

- [art_elites.png](screenshots/art_elites.png)：骷髅兵 / 精英骷髅 / 幽魂 / 精英幽魂 并排对比。
- [art_threat.png](screenshots/art_threat.png)：威胁环三阶段（大而暗 → 小而亮），石地面。
- [art_threat_detail.png](screenshots/art_threat_detail.png)：精英幽魂 + 威胁环近景。
- [art_combat.png](screenshots/art_combat.png)：竞技场实战构图（精英 + 威胁环）。
- [art_dungeon.png](screenshots/art_dungeon.png)：7×7 地牢展示房（墙 / 地砖 / 楼梯 / 宝箱 / 地刺 / 符文陷阱）。

## 1. 管线

### 1.1 重新生成

```powershell
# 角色（含精英）与清单
python tools/characters.py
# 所有道具、墙、地砖、地牢件 + assets/assets.zig + CREDITS
python tools/bake_assets.py
# 游戏本体
zig build
# 美术展示截图（独立可执行，不改 game/hud/systems）
zig build art -- --scene dungeon --out docs/screenshots/art_dungeon.png
```

`zig build art` 的入口是 `src/art_preview.zig`，它复用 `Game.create` 的渲染器/模型库/竞技场，把展示用实体直接塞进 ECS，然后调 `saveScreenshot`。场景：`elites` / `threat` / `threat-detail` / `combat` / `dungeon`。

### 1.2 文件归属

| 文件 | 说明 |
| --- | --- |
| `tools/characters.py` | 新增材料、`build_elite_skeleton`、`build_elite_wraith` |
| `tools/bake_assets.py` | 新增地牢材料与 7 个程序化道具；导出 `assets/baked/*.vxm` / `assets/assets.zig` / `assets/CREDITS.md` |
| `assets/models/elite_*.obj/.mtl/.rig.json` | 精英源文件 |
| `src/art_preview.zig` + `build.zig` 的 `art` step | 文档截图工具（不参与游戏循环） |

**没有修改** `src/game/hud.zig`、`src/game/systems.zig`、`src/game/game.zig`、`src/main.zig`。

## 2. 精英敌人

### 2.1 精英骷髅 `elite_skeleton`

黑金配色：焦黑甲片 + 金冠/金肋/金边，余烬色眼睛与剑盾宝石。

| 项 | 值 |
| --- | --- |
| tris / verts | 1664 / 1012 |
| VXM 大小 | 39,164 B |
| 包围盒 | x −0.306..0.368，y 0..1.048，z −0.173..0.16 |
| 关节 | 与 `skeleton` 完全一致（`BASE_JOINTS`，11 个） |
| 动画 | 复用 `rig.zig` 的 kind 3（骷髅走路/举剑） |
| 建议缩放 | 1.30–1.40（普通骷髅约 1.18，形成体型差） |

烤进 VXM 的颜色（sRGB，逐三角形）：

`#eaa62e` 金、`#ffd45e` 金/余烬（自发光）、`#1a1822` 黑曜石、`#4a525e` 铁灰、`#e2d6bc` 骨、`#b47826` 暗金、`#18161e` 眼窝、`#b08465` 皮肤阴影。

可读性设计：

- 金冠 5 根不等高尖刺，顶部低于 1.05，正面轮廓与普通骷髅明显不同；
- 自发光金冠/剑格/盾徽在 480×270 下仍能读成“精英”；
- 黑甲与金边对比大，站在灰色地砖或红毯上都不会糊；
- 剑更大、盾更厚，剪影比普通骷髅宽约 15%。

### 2.2 精英幽魂 `elite_wraith`

红紫配色：紫袍 + 血红前襟 + 洋红角/眼/法杖/胸针，兜帽尖角。

| 项 | 值 |
| --- | --- |
| tris / verts | 2228 / 1314 |
| VXM 大小 | 51,863 B |
| 包围盒 | x/z −0.326..0.326，y 0..1.168 |
| 关节 | `wraith` 关节 + `focus`（法杖浮游碎片）与 `aura`（胸口法环），共 13 个 |
| 动画 | 复用 `rig.zig` 的 kind 4（悬浮、法杖手、focus/aura 自转） |
| 建议缩放 | 1.35–1.42 |

烤进 VXM 的颜色：

`#c33a8a` 洋红、`#3d2058` 深紫、`#8a54bd` 亮紫、`#8c2733` 深红、`#7a1f55` 血紫、`#ef7fc0` 洋红自发光、`#fff4e2` 白光核心、`#b8bfcc` 银（法杖箍）、`#5d3488` 紫、`#1a1220` 虚空、`#b83a45` 亮红、`#4e3828` 暗木。

可读性设计：

- 兜帽两侧外翻尖角 + 洋红尖端，远看是“角”，与普通幽魂的圆兜帽区分；
- 洋红眼、胸针、法杖火焰、胸口法环四个自发光点，在暗处也能定位；
- 紫袍主色比普通幽魂的黑袍亮一档，但前襟仍是血红，保持“红紫”；
- 总 tris 2228，距 2500 上限只剩 272，后续加装饰需要先删旧件。

### 2.3 敌人集成清单（Lead）

当前 `game.zig` 的 `spawnEnemy` 使用：

```zig
const names = [_][]const u8{ "skeleton", "wraith", "golem", "abyss_guard" };
```

接精英时建议：

1. 在 `names` 追加 `"elite_skeleton"`、`"elite_wraith"`，并给 `Stats` 追加分支（数值按 BALANCE_V1：精英骷髅 100 HP / 11 攻 / 7 甲 / 1.8 速 / 1.2 距 / 1.2 CD；精英幽魂 85 / 10 / 2 / 1.7 / 3.8 / 1.9）；
2. **注意动画 kind**：当前写法是 `anim.kind = 3 + kind`。如果精英用 kind 4/5，会得到 7/8，`rig.compute` 不认识。请显式映射（kind 编号按 Lead 的分配调整）：
   ```zig
   const anim_kind: u8 = switch (kind) {
       4 => 3, // elite_skeleton -> 骷髅动画
       5 => 4, // elite_wraith -> 幽魂动画
       else => 3 + kind,
   };
   ```
   设置 `Animation.state.kind = anim_kind`，模型仍然按 `kind` 选择。
3. 名称/颜色：`enemyLabel` 加 `"精英骷髅"`、`"精英幽魂"`；`enemyColor` 建议金/洋红，与模型主色一致。
4. 可选：给精英加一个小的 `LightSource`（金怪暖光、幽魂洋红光），能让它们在灰地砖上更跳；注意 `game.zig` 的 `drawEffects` 会把 `color.y >= 0.6` 的 LightSource 当成晶塔画青色光晕——要么把颜色的 y 压到 0.6 以下，要么接受青色光晕。
5. `Renderable.id` 保持唯一（描边用）；`boss` 仅深渊守卫为 true。

## 3. 威胁 / 蓄力环 `threat_ring`

| 项 | 值 |
| --- | --- |
| tris / verts | 490 / 462 |
| VXM 大小 | 13,467 B |
| 尺寸 | 直径 2.0（x/z ±1.0），高 0.17 |
| flags | bit0 = additive（VXM 标记 additive；真正绘制模式仍由 `Renderable.additive` / `RenderOpts.additive` 决定） |
| 颜色 | `#ff5840`、`#b02a26`、`#ffc478`（全部自发光） |

结构：三层断续同心环 + 12 个向内箭头 + 外圈刻度 + 中心菱形 + 8/4 根矮警示尖刺。

建议集成（重击前摇）：

```zig
if (self.models.indexOf("threat_ring")) |idx| {
    const t = windup_progress; // 0..1
    const ring_scale = 1.0 - 0.58 * t;
    const ring_yaw = self.time * 1.8;
    const tint = if (t > 0.7) color.pack(255, 196, 120) else color.pack(255, 96, 72);
    self.renderer.drawModel(self.models.at(idx), null,
        math.Mat4.compose(
            math.Vec3.init(tr.pos.x, 0.020, tr.pos.z),
            ring_yaw, 0.0, 0.0, ring_scale),
        .{ .tint = tint, .boost = 0.8 + 0.9 * t, .additive = true });
}
```

- 环在石地面上是橙红；在红毯上会偏白（additive 加色），所以建议把重击敌人尽量站在石地面，或把 tint 压暗。
- `Renderable` 没有 alpha 字段；透明淡出只能走 `RenderOpts.alpha`（`drawModel` 直接调用）。如果想走实体管线，用 `boost` 调亮度即可。
- 环是纯地面件，不写深度；敌人腿脚处会被深度遮挡，这是预期效果。
- 如果 ToME 主线最终不用，它只在二进制里占 13 KB；从 `bake_assets.py` 的生成列表移除即可。

## 4. ToME v1 地牢套件

### 4.1 模型表

| 模型 | 用途 | tris | verts | 尺寸 / 原点 | 颜色（VXM） |
| --- | --- | ---: | ---: | --- | --- |
| `dungeon_floor` | 1×1 地砖 | 84 | 56 | 1.0×1.0，顶面 y=0，厚 0.118 | `#444c5c` 石、`#5c6474` 亮石、`#2c3242` 深灰、`#2f6b5a` 苔 |
| `dungeon_floor_cracked` | 破损地砖 | 96 | 64 | 同上 | 同上 |
| `wall_segment` | 1×1 可拼墙 | 360 | 240 | 1.08（压顶）×1.45 高 | `#444c5c`、`#2c3242`、`#2f6b5a` |
| `stairs_down` | 下行楼梯 | 349 | 227 | 1.0×1.0；井口 0.80；y −0.42..0.095 | 石色 + `#ffd45e` 金角 + `#c44a20` 自发光箭头 + `#0b0c12` 井底 |
| `dungeon_chest` | 宝箱（关） | 200 | 134 | 0.76×0.52，高 0.628 | `#7a5a3f` 木、`#4e3828` 深木、`#373d48` 铁、`#eaa62e`/`#ffd45e` 金、`#ff9f1c` 自发光宝石 |
| `trap_spikes` | 地刺陷阱 | 188 | 133 | 0.92×0.92，高 0.285 | `#444c5c` 板、`#2c3242` 槽、`#9ea6b6` 刺、`#c44a20` 自发光角钉 |
| `trap_rune` | 符文陷阱 | 388 | 226 | 0.92×0.92，高 0.054 | `#c44a20`/`#e05a5a` 自发光符文、`#444c5c`、`#2c3242` |

### 4.2 做法与可读性

**地砖**：一整块 1×1 底板（顶面 −0.006）+ 四块 0.452 见方的凸起石砖；砖缝露出深色底板，天然形成 1px 左右的暗缝。凸起砖只比底板高 6 mm，减少 z-fighting。随机裂纹、苔藓、缺角用薄片贴面完成，不依赖贴图。两种变体（完整/破损）配合 90° 旋转即可让 13×13 地面不重复。

**墙**：0.96 核心 + 1.04 基座 + 1.08 压顶，四个面都有水平灰缝与错位石块，90° 旋转后四面都成立。相邻墙的 0.96 核心之间留下 0.04 的凹槽，看起来像分块砌筑；压顶轻微出挑 0.04，转角处会有轻微穿插，属于可接受的像素风细节。高 1.45，比 1.3 倍缩放的角色略高。

**楼梯**：井口 0.80，边框只有 0.08 高，第一级踏面 0.03，每级只下降 0.06——这是为了在 40° 俯视下不被近侧边框挡住。五级踏面 + 亮色鼻线 + 回退的深色侧壁，形成“向下”的明度梯度；近侧边框上有自发光橙色箭头。模型向下延伸到 −0.42；**放置楼梯的格子必须省略地砖**，否则负 Y 部分会被地面遮住。

**宝箱**：木箱体 + 三级阶梯盖 + 两道铁箍 + 金锁/自发光宝石。相比普通 Kenney 箱更宽、更高，在俯视下能看清锁与盖面。

**陷阱**：`trap_spikes` 用 9 根浅钢色四棱锥 + 深色槽圈 + 四角余烬钉；`trap_rune` 用双层自发光符文环 + 四枚向内齿 + 8 个刻度。两者都是 1 格地面件，逻辑（触发/解除/侦测）由游戏层实现。

### 4.3 网格集成建议

一个格子 = 1.0 世界单位，格心 (x, 0, z)；地砖顶面 y=0，角色/道具也放在 y=0。

```zig
// 地砖：完整/破损二选一，90° 旋转制造变化
const floor_name = if (cracked) "dungeon_floor_cracked" else "dungeon_floor";
// 墙：墙体格子
const wall_name = "wall_segment";
// 楼梯：该格不放地砖
const stair_name = "stairs_down";
```

伪代码：

```zig
fn place(self: *Game, name: []const u8, pos: math.Vec3, yaw: f32, id: u16) void {
    const idx = self.models.indexOf(name) orelse return;
    const e = ecs.new_id(self.world);
    _ = ecs.set(self.world, e, comp.Transform, .{ .pos = pos, .yaw = yaw, .scale = 1.0 });
    _ = ecs.set(self.world, e, comp.Renderable, .{ .model = idx, .id = id });
}

// 每格：
//   wall -> place("wall_segment", cell, 0, 601)
//   stairs -> place("stairs_down", cell, 0, 602)   // 不铺地砖
//   chest -> place("dungeon_chest", cell, yaw_to_player, 603)
//   trap -> place("trap_spikes" / "trap_rune", cell, 0, 604)
//   floor -> place(cracked ? "dungeon_floor_cracked" : "dungeon_floor",
//                  cell, 90° * ((x*3+z*5) & 3), 0)
```

要点：

- 墙/宝箱/楼梯/陷阱用独立 `Renderable.id` 可以获得与背景的描边；地砖 id=0 可避免每块砖都描边。相邻同 id 且同深度的面不会互相描边（渲染器只在背景或深度差 > 0.12 时描边）。
- 逻辑层（`grid.zig` / `dungeon.zig`）负责阻挡、楼梯交互、宝箱开启、陷阱触发；VXM 只是视觉件，不带碰撞/UV/动画。
- 静态地砖/墙可以按层合并成一个 mesh 以降低 draw call；当前每格一个实体在 13×13 下约 169 个实体，渲染 3 万 tris 左右，仍在现有预算内。
- 环境光偏冷，地牢会偏灰蓝；需要暖色时加一个 `LightSource`（注意上一节的颜色 y < 0.6 约定）。

### 4.4 展示房

`zig build art -- --scene dungeon` 在 (24, 3, 0) 悬空搭了一个 7×7 展示房：后墙 + 左右墙，前面开口；25 块地砖（含破损变体）、1 个楼梯井、1 个宝箱、地刺与符文陷阱各 1、木桶/陶罐做尺度参照。楼梯格刻意未铺地砖，方便验证负 Y 台阶。场景停在 `x=24` 是为了避开竞技场灯光/浮游碎片，截图中不会混入旧场景元素。

## 5. 颜色与材质约定

- 新增角色材料：`obsidian`(26,24,34)、`gold_dark`(180,120,38)、`magenta`(195,58,138)、`glow_magenta`(239,127,192, 自发光)、`glow_white`(255,244,226, 自发光)。
- 新增道具材料：`dungeon_stone`(68,76,92)、`dungeon_stone_light`(92,100,116)、`dungeon_stone_dark`(44,50,66)、`dungeon_moss`(47,107,90)、`wood`(122,90,63)、`wood_dark`(78,56,40)、`iron_dark`(55,61,72)、`gold_light`(255,212,94)、`void`(11,12,18)、`spike`(158,166,182)、`rune_red`(224,90,90, 自发光)、`rune_ember`(196,74,32, 自发光)。
- 所有颜色在烘焙后按 64 色调色板量化；上表是 VXM 里的源 sRGB，最终屏幕颜色还会经过平面光照、曝光曲线、Bayer 抖动和调色板最近邻。
- **材质命名坑**：`_material_name` 只用 RGB 生成 `m_rrggbb`。同一个 RGB 如果既有自发光又有非自发光定义，会在 MTL 里互相覆盖——目前 `gold_light` 与 `flame` 都是 (255,212,94)，实际全部按自发光烘。新增颜色时不要让两个语义不同的材料共用 RGB。
- 自发光强度由渲染器的 `1.9 * boost` 叠加；洋红/白色核心在亮处会过曝成白色，这是刻意的“热核心”效果，但大面积的 `glow_*` 面会糊成白块，建议只用小面积点缀。

## 6. 验证

已执行：

```text
zig build              -> OK
zig build test         -> OK
zig-out/bin/vx.exe --headless --out .tmp-art/game_check.png --frames 30
                       -> 480x270, tris=22898, drawn=331031, OK
zig build art -- --scene dungeon --out docs/screenshots/art_dungeon.png
                       -> tris=30803, OK
```

`root.zig` 的 “all embedded models load” 测试会加载全部 42 个模型，覆盖新 VXM 的解析。

## 7. 已知限制

1. **无贴图/UV**：全部靠几何与逐三角形颜色；墙面细节在 480×270 下靠灰缝与明度差，放大看会重复。
2. **无碰撞网格**：墙/楼梯/陷阱的阻挡、交互完全由逻辑层网格决定；模型不带碰撞体。
3. **楼梯必须有洞**：`stairs_down` 的井口以下都是负 Y；不省略地砖就只能看到井框。若暂时无法改地砖，可把楼梯放在房间边缘或先只做“下行标记”。
4. **墙只有一种**：没有内转角/破损墙/门洞变体；1×1 全块在转角会重复。需要时可以基于 `wall_segment` 派生 `wall_corner` / `wall_broken`。
5. **墙高 1.45**：40° 相机下会遮住后方约 1.7 格；如果 Lead 想要更俯视的读图，可做 1.2 高的矮墙变体。
6. **地砖只有两种**：变化靠旋转；裂纹/苔藓是固定图案，近看会看出重复。
7. **精英动画复用现有 kind**：精英幽魂的袍子仍是刚体，没有布料/飘带模拟；精英骷髅的剑是固定握姿。
8. **精英幽魂 2228 tris** 已接近 2500 上限；再加装饰要先砍旧件。
9. **威胁环 additive**：在红毯/亮地面上会发白，建议配石地面或压暗 tint；`Renderable` 无 alpha，淡出要用 `RenderOpts.alpha`。
10. **展示工具不是游戏循环**：`src/art_preview.zig` 只用于文档截图，没有接 HUD/回合/碰撞；它以独立 `Game` 实例运行，截图中的实体不会出现在正式游戏里。
11. **art step 不在 `zig build test` 内**：如果未来改了模型名/组件字段，记得手动跑一次 `zig build art`；否则这个工具可能在 CI 外悄悄失效。
