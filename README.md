# VX / 以太堡：深层

**ToME4 风格回合制 Roguelike + 真 3D 模型 + 像素画风 + 固定俯视可旋转相机**

选一个职业，在 13×13 的 3D 像素地牢里一格一格推进。玩家行动一次，敌人行动一次；用天赋、装备、等级和地形击败楼层守卫。画面保留真实 3D 网格、480×270 软件光栅化、64 色量化和 Bayer 抖动；玩法转向 ToME4 的回合制、格子、职业/天赋、掉落/装备和楼层推进。

![to-me](docs/screenshots/tome_start.png)

## 现在能跑什么

- **回合制**：玩家移动/普攻/天赋/等待后，敌人按速度依次行动；冷却、资源、状态按回合结算，不按秒。
- **单角色 + 3 职业**：狂战士（精力）、元素法师（法力）、时空法师（悖论），每职业 3 个天赋。
- **格子与地牢**：13×13 网格；墙/柱子/水域阻挡；撞墙不消耗回合，撞敌人 = 普攻；3 层，楼梯下一层，第 3 层 Boss。
- **确定性关卡**：同一 seed 生成同一层；入口、楼梯、宝箱、陷阱、敌人出生点由连通性校验；敌人用 A* 绕墙追击，远程用 LOS。
- **属性/装备/掉落**：六属性、HP/资源、攻击/护甲/暴击/速度；宝箱和击杀产出版本内物品，空槽自动装备，装备即时改变面板数值。
- **中文 HUD**：角色卡、楼层卡、目标卡、战斗日志、天赋栏、角色/背包面板；Ark Pixel 12px 子集。
- **3D 像素场景**：地牢地砖、墙、楼梯、宝箱、陷阱、精英和 Boss 模型；脚底环、目标血条、危险标记、楼梯光柱。
- **无窗口验证**：headless 截图；自动跑局用于 QA。

![fight](docs/screenshots/tome_fight.png)

## 快速开始

### 环境

- Zig **0.17.0**
- Windows / macOS / Linux；首次构建 SDL3 需要几分钟
- 运行不需要 Python / Blender；改资源/字体时才需要 Python 3 + Pillow

### 构建与运行

~~~powershell
zig build run                  # 默认 ToME 回合制
zig build test                 # 单元 + 集成测试
zig build run -- --headless --frames 2 --out shots/tome.png
zig build run -- --headless --auto --frames 5000 --out shots/tome-auto.png
zig build run -- --arena       # 旧版实时 5 波竞技场（保留作对照）
~~~

默认内部 **480×270**，窗口 3× 最近邻放大到 **1440×810**。

### 操作

| 输入 | 行为 |
| --- | --- |
| WASD | 走一格；撞敌人 = 普攻；撞墙不消耗回合 |
| 1 / 2 / 3 | 天赋 1/2/3（自动选最近目标；范围/冷却/资源校验） |
| 空格 | 等待一回合；附近无敌人时休息回复 |
| I | 背包 |
| C | 角色面板（六属性、装备、生命/资源、攻击/护甲/暴击/速度） |
| Q/E、方向键、右键拖拽 | 旋转相机；滚轮缩放 |
| R | 死亡/任意时候重开本 seed |
| F1 / F12 / ESC | 调试 / 截图 / 退出 |

![character](docs/screenshots/tome_character.png)

## 参数

| 参数 | 说明 |
| --- | --- |
| --headless | 不创建窗口，渲染 PNG |
| --out PATH | 截图路径 |
| --frames N | 模拟 N 帧后截图/退出 |
| --run-seconds S | 窗口运行 S 秒后截图退出 |
| --hero N | 0 狂战士 / 1 元素法师 / 2 时空法师 |
| --seed N | 地牢种子（默认 12345） |
| --auto | headless 自动向楼梯推进、打怪、放天赋 |
| --inventory / --character | 启动时打开对应面板（截图/审查用） |
| --loot N | 调试：直接获得 N 件掉落（截图/QA 用） |
| --res WxH / --scale N | 分辨率 / 窗口倍率 |
| --arena | 切回旧版实时竞技场 |

## 玩法细节

### 回合与速度

- 玩家每轮先行动一次。
- 敌人按 speed 排序；speed ≥ 150 每 2 回合额外行动一次，speed ≤ 75 每 2 回合少行动一次。
- 冷却、资源回复、状态持续时间都按回合数结算。
- 移动/普攻/天赋/等待才消耗回合；非法移动不消耗。

### 天赋

| 职业 | 资源 | 1 | 2 | 3 |
| --- | --- | --- | --- | --- |
| 狂战士 | 精力 | 重击（近战 2.2×） | 冲锋（4 格内 1.5×） | 战吼（3 回合 +30% 攻击） |
| 元素法师 | 法力 | 火球（5 格内 2.5× + 1.5 格溅射） | 冰锥（1.8× + 减速） | 闪现（3–5 格空地） |
| 时空法师 | 悖论 | 时光箭（2.0× + 减速） | 时间停滞（1.2× + 跳过 2 回合） | 回溯（回到上一格） |

### 地牢与成长

- 3 层；每层入口随机在底/左/右，楼梯在对侧，保证连通。
- 宝箱 2–4 个、陷阱 1–4 个、敌人 4–8 个，随层数增加。
- 击杀获得 XP；升级 +1 主属性并回满；第 3 层击败深渊守卫胜利。
- 死亡即结束，R 从同一 seed 重开（ToME4 式 roguelike）。

## 代码结构

~~~text
src/
  core/        math / color / palette / png / font / cjk_font
  engine/      model / rig / arena_mesh / renderer
  game/
    tome_sim.zig     纯回合制模拟（无 SDL/渲染）
    tome_game.zig    3D 场景、输入、相机、动画
    tome_hud.zig     角色/楼层/目标/日志/天赋/面板
    dungeon.zig      13×13 确定性关卡、连通性、A*、LOS
    attributes.zig   六属性/派生/XP
    items.zig        装备/背包/修正
    content.zig      内嵌 JSON 内容加载/校验/掉落
    turn.zig         回合顺序核心（供后续多 actor 扩展）
    game.zig         旧版实时竞技场（--arena）
  platform/sdl.zig
assets/
  data/         items/enemies/skills JSON + data.zig
  baked/        VXM 运行时模型
  models/       OBJ/MTL/rig 源
tools/          characters / bake_assets / gen_cjk_font
docs/           TOME_V1 / ART_PASS / UX_REVIEW_TOME / screenshots
~~~

## 验证

- zig build / zig build test：13/13 steps、74/74 tests。
- headless：可生成开始/战斗/角色/背包/胜利截图。
- 自动跑局（seed 12345）：第 80 回合击败第 3 层守卫，剩 51 HP；可复现。
- 窗口模式：480×270、3× 最近邻、SDL 输入/截图正常。

![victory](docs/screenshots/tome_victory.png)

## 已知限制 / 下一步

- 天赋自动选最近目标，还没有 ToME4 的选格/范围预览/确认取消。
- 背包只能查看；空槽自动装备，手动换装/多套装备待做。
- 敌人技能只有普攻 + Boss 模型，没有完整 Boss AOE/召唤。
- 没有音频、存档、角色选择菜单、天赋树、随机词缀。
- 当前数值是 v1 占位，优先验证循环与可读性。

## 致谢与许可

- **Kenney** Mini Dungeon / Mini Arena，CC0 1.0；见 assets/CREDITS.md。
- **Ark Pixel Font** by TakWolf，SIL OFL 1.1；见 assets/fonts/。
- **SDL3**（castholm/SDL Zig 包）、**flecs / zflecs**（MIT）。
- 角色、敌人、地牢道具和代码由本项目生成/编写。

---

*Built with Zig 0.17 + SDL3 + zflecs. Real meshes, chunky pixels, turn-based depths.*
