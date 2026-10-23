# VX 架构说明

本文补充 README，面向想继续改渲染器、ECS 或资源管线的开发者。

## 1. 坐标与相机

- 右手系，Y 向上；角色在建模时面向 **+Z**。
- 相机是轨道相机：`target` 平滑跟随当前英雄；`yaw` 绕 Y 旋转；`pitch` 固定（默认约 0.70 rad ≈ 40°）；`distance` 控制缩放。
- 相机位置：
  ```
  dir = (sin(yaw)·cos(pitch), sin(pitch), cos(yaw)·cos(pitch))
  eye = target + dir · distance
  ```
- `Mat4` 是列主序（`m[col*4+row]`）；`lookAt` 使用右手系，相机看向 -Z。
- 投影为右手透视，裁剪空间 z ∈ [-w, w]；光栅器自己使用视图空间 `-z` 作为正深度，存 `1/z` 到 z-buffer。
- 移动方向相对相机：`forward = (-sin(yaw), 0, -cos(yaw))`，`right = (cos(yaw), 0, -sin(yaw))`。

## 2. 软件渲染器（src/engine/renderer.zig）

每帧流程：

```
begin(camera,time)
  ├─ 背景渐变 + 星点 → color buffer
  ├─ z-buffer = 0, id-buffer = 0, stats = 0
  └─ 设置 view / focal / light 列表
drawMesh / drawModel × N        （不透明）
drawShadow × N                  （深度测试 + 变暗混合）
drawModel × N                   （加色：符文、浮游物）
drawEffects                     （火焰、光晕、粒子、选择环）
resolve
  ├─ 调色板量化 + Bayer 抖动 + 暗角
  └─ 深度/ID 描边
HUD / 姓名牌
```

### 三角形路径

1. 世界坐标三角形 → 视图空间。
2. 近平面裁剪：对三条边做 Sutherland–Hodgman，最多得到 4 个视图顶点。
3. 投影到屏幕：
   `sx = (x·f/aspect / (-z) · 0.5 + 0.5)·W`，
   `sy = (0.5 - y·f / (-z)·0.5)·H`，
   `iz = 1/(-z)`。
4. 屏幕空间边函数求重心坐标；`iz` 线性插值，比较 `iz > depth`（越大越近）。
5. 不透明写入 color/depth/id；加色与阴影只读 depth。
6. 背面剔除：屏幕 y 翻转后，前向面在屏幕空间为负面积，因此 `area > 0` 剔除。

### 平面光照

每个三角形用世界空间叉积求面法线，在三角形重心求光照：

- 环境光（冷色）；
- 月光方向光；
- 暖色 key light（来自镜头右前方）；
- 相机边缘光：`(1 - dot(N, viewDir))^3`，提升暗部轮廓；
- 最多 18 个点光源，按 `(1 - d/r)^2 · max(dot(N, L), 0) · intensity` 衰减；
- 自发光材质额外加成（法杖宝珠、符文、眼睛等）；
- 距离雾，向深蓝黑混合；
- 曝光曲线 `1 - exp(-x·1.75)`，再转回 sRGB。

### 像素化

- 内部缓冲默认 640×360；窗口用 SDL 整数缩放（默认 3×）。
- 64 色手工调色板（`src/core/palette.zig`），最近邻色使用 5-bit/通道缓存。
- 4×4 Bayer 抖动只加在量化前，强度 5.0（避免大面积噪点）。
- 描边：扫描 id-buffer，若 4 邻域 id 不同且（邻域为背景或深度差 > 0.12 世界单位），写调色板最深的描边色。
- 贴图不使用运行时纹理采样：颜色在烘焙时逐三角形烘焙，保证低分辨率下稳定、无 mipmap 噪点。

### 加色/阴影

- 加色：`dst = saturate(dst + src·alpha)`，不写 depth/id。
- 阴影：半径 12 段的圆盘，绘制在 y=0.014，直接乘 0.62 变暗；不写 depth/id。
- 光晕/火焰：屏幕空间程序化绘制，逐像素用中心深度做遮挡测试，颜色按径向/火焰高度衰减。

## 3. 模型与骨架

源模型：

- 角色：`tools/characters.py` 生成 `assets/models/<name>.obj`、`.mtl`、`.rig.json`。
- 道具：Kenney OBJ + colormap 贴图，或 `tools/bake_assets.py` 里的程序化道具（火盆、晶塔、占位碎片、符文圈）。

烘焙后 VXM：

```text
magic "VXM1"
u32 version, u32 flags(bit0=additive)
u8 name_len, name
f32 bounds_min[3], bounds_max[3]
u16 joint_count
  per joint: u8 name_len, name, i32 parent, f32 rest[3]（相对父关节）
u16 part_count
  per part: u16 joint, u32 vertex_count, u32 tri_count
            f32 vertex[3] × N
            u32 index[3] × tri_count
            u8 rgba × tri_count（rgb 颜色 + a=emissive 标记）
```

运行时：

- 顶点已转换到关节局部空间（减去该关节的 rest 世界位置）。
- `Model.rest_world` 提供无动画时的关节世界矩阵（道具使用）。
- 英雄每帧由 `rig.compute` 生成 `Pose.joints[]`；绘制时部件矩阵 = `entity × pose[joint]`。
- 刚性部件蒙皮对低模像素风足够；如果需要软蒙皮，可在 VXM 里加权重，扩展 `model.zig` 与 `rig.zig`。

关节命名约定（动画系统按名字查找，缺省关节会被跳过）：

`root, hips, torso, head, arm_l, arm_r, leg_l, leg_r, cape, weapon, offhand, focus, aura`

## 4. ECS 与帧更新

`Game.update`：

1. 处理切换/施法/重置。
2. 相机 yaw/zoom 输入。
3. 由相机方向计算当前英雄的 `MoveIntent`。
4. `ecs.progress(world, dt)`，按注册顺序执行：
   - `VX.Formation`：队友目标位置 → `MoveIntent`
   - `VX.Movement`：加速度/阻尼、积分、边界、朝向、步态相位
   - `VX.Animation`：根据 `Animation` + 职业生成 `Pose`
   - `VX.Gauges`：AP 回复
   - `VX.Motes`：浮游物绕中心
   - `VX.Spins`：装饰碎片自转
5. 相机目标平滑、粒子更新。

`systems.zig` 通过全局 `context` 指针访问 `dt/time/models/arena_limit`，避免在 system 签名里塞入世界上下文；这是单线程游戏的简化设计。

## 5. 资源内嵌

- `assets/assets.zig` 由烘焙脚本生成，列出所有 `@embedFile("baked/*.vxm")`。
- 资源模块 root 在 `assets/`，因此 `@embedFile` 路径合法，且二进制可以脱离工作目录运行。
- 增加模型：在 `bake_assets.py` 的 `KENNEY_PROPS` 或 `bake_extra` 中登记，重新烘焙，清单自动更新；代码里用 `models.indexOf("name")` 获取模型索引。

## 6. 无窗口模式

`--headless` 不初始化 SDL，直接：

- `Game.create`（ECS 世界、模型、程序化网格、渲染器）
- 固定步长 `1/60` 模拟
- `Game.render`
- `Game.saveScreenshot` → `core/png.zig` 的零依赖 PNG 编码器

这让渲染/动画/相机逻辑可以在无桌面环境、CI 或远程会话里验证；文档中的截图均由该模式生成。

## 7. 性能与扩展建议

- 当前约 36k 三角形/帧、640×360 在 ReleaseFast 下可实时运行。
- 可优化点：按实体 AABB 视锥裁剪、把静态道具合并成一个 mesh、按材质/颜色批处理、用固定点光栅化、减少每帧 `ecs.get`。
- 若加入大量敌人，建议把 `Pose` 只算可见实体，或按距离降频更新动画。
- 俯仰角固定是设计需求；`lineup` 模式只用于展示，不影响游戏相机。
## 8. 战斗层（feat/combat-prototype）

战斗是叠加在 ECS/渲染切片上的一层，不改变相机与光栅器。

### 组件

- `Hero`：生命/AP/移速 + 普攻伤害/距离/冷却 + 技能名/倍率/范围/AOE/减速 + 倒下/复活计时。
- `Enemy`：类型、生命、伤害、移速、攻击距离/冷却、目标、减速计时、受击闪白。
- `Animation.state.kind`：0/1/2 英雄，3 骷髅，4 幽魂，5 石魔像，6 深渊守卫；`rig.zig` 按 kind 切换腿摆、手臂、悬浮和武器姿态。

### System 顺序

```text
VX.Formation    队友目标位置 -> MoveIntent
VX.Movement     积分/阻尼/边界/朝向/步态
VX.EnemyAI      最近英雄、追击、攻击、分离力
VX.HeroCombat   最近敌人、自动普攻
VX.Animation    AnimState -> Pose 关节矩阵
VX.Gauges       AP 回复
VX.Motes        浮游物
VX.Spins        装饰自转
```

战斗 system 只修改 ECS 数据，并通过 `systems.events` 固定数组发出事件（敌人受击/英雄受击/敌人死亡/英雄倒下）。`Game.update` 在 `ecs.progress` 后消费事件：伤害数字、火花、击杀计数；然后删除 hp≤0 的敌人、处理复活/换人/胜负。这样避免在 system 迭代中删除实体。

### 波次

`Game` 里的队列（`queueWave`/`beginWave`/`updateWave`）在场地边缘逐个刷怪；清空后进入休整，第 5 波结束判胜，全队倒下判负。`resetRun` 清怪、满血、回到第 1 波。

### 目标与 HUD

- `Game.target` 是当前英雄 7 单位内最近的敌人；目标脚下画红色符文环，头顶显示名字/血条。
- 非目标敌人只画细血条，避免 5 个名字叠在一起。
- 伤害数字是 Game 层的`FloatText`数组，投影到屏幕后绘制，不参与 3D 深度。
- 战斗 HUD 与中文文案在 `hud.zig`；波次横幅画在标题与操作面板之间的顶部空隙。

## 9. 中文像素字体

- 资源：Ark Pixel Font 12px monospaced BDF（SIL OFL 1.1）。
- `tools/gen_cjk_font.py` 扫描 `src/**/*.zig` 中所有非 ASCII 码点，加上内置的敌人/技能字符表，从 BDF 取 12×12 位图，生成 `src/core/cjk_font.zig`（112 个字形）。
- BDF 的 `BBX` 按 `FONT_ASCENT` 映射到 12×12 单元；每行位图压成 `u16`。
- `font.zig` 提供手写 UTF-8 解码、混合宽度 `textWidth`；`renderer.drawTextRaw` 对 ASCII 用 5×7 并垂直居中（+3px），对 CJK 用 12×12，缺字画提示框。
- 只嵌入用到的字形，源 BDF 不需要随构建分发；许可证在 `assets/fonts/OFL.txt`。

## 10. 数值调参

所有占位数值集中在 `game.zig`（英雄/敌人/波次）与 `systems.zig`（伤害/暴击/事件），HUD 文案在 `hud.zig`。具体表格和下一步见 `docs/COMBAT.md`。
