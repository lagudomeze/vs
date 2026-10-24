# Steam 商店素材（占位）

这些图是**尺寸/命名可上传的占位**，不是最终 key art。上架前用正式美术替换同名文件。

商店页文案见 [PAGE.md](PAGE.md)；正式美术外包需求见 [ART_BRIEF.md](../ART_BRIEF.md)；测试流程见 [PLAYTEST.md](../PLAYTEST.md)；预告片分镜见 [TRAILER.md](../TRAILER.md)。

生成：

~~~powershell
python tools/store_assets.py
python tools/store_screens.py
python tools/key_art.py
python tools/pixel_logo.py
~~~

源图：

- docs/store/screenshots/*.png：由真实 CLI 场景生成的 5 张 1920×1080 商店截图
- docs/screenshots/store_clean.png：--hide-hud --hide-labels 的干净场景，用于 Capsule 底图与 key art

## Key art

| 文件 | 尺寸 | 说明 |
| --- | --- | --- |
| key_art_1920x1080.png | 1920x1080 | 主视觉 v2：放大像素 VX logo + AETHER KEEP，回合制 Roguelike 文案与 Wishlist |
| trailer_storyboard.png | 1920x1080 | 30 秒预告片故事板（6 镜） |
| logo_920x430.png | 920x430 | 像素 VX / AETHER KEEP 透明 logo |

仍不是正式手绘 key art；上架前替换为专门构图。logo 为 5x7 像素字表生成，可作为正式 logo 的方向稿。

## 商店截图（5 张，16:9）

| 文件 | 场景 |
| --- | --- |
| screenshots/01_combat.png | 战斗 HUD、敌人意图、天赋栏 |
| screenshots/02_character.png | 角色属性/装备/天赋 |
| screenshots/03_aim.png | 冲锋瞄准、距离/伤害预览 |
| screenshots/04_shop.png | 商店面板 |
| screenshots/05_chunks.png | 3×3 边缘邻接 + minimap 标记 |

## Capsule 文件

| 文件 | 尺寸 | 用途 |
| --- | --- | --- |
| screenshot_1920x1080.png | 1920×1080 | 由 01_combat 生成的单图预览 |
| header_capsule_920x430.png | 920×430 | Header Capsule（像素 logo 版） |
| small_capsule_462x174.png | 462×174 | Small Capsule |
| main_capsule_1232x706.png | 1232×706 | Main Capsule |
| vertical_capsule_748x1084.png | 748×1084 | Vertical Capsule |
| vertical_capsule_374x542.png | 374×542 | Vertical Capsule 半尺寸 |
| library_capsule_600x900.png | 600×900 | Library Capsule |
| library_capsule_300x450.png | 300×450 | Library Capsule 半尺寸 |

## 上架前替换

- 标题字体/Logo 换成正式 logo；当前用 bahnschrift 占位。
- Capsule 已统一使用像素 logo；正式版换成专门手绘构图。
- 5 张截图已覆盖战斗/角色/瞄准/商店/地图；正式版可替换为更精细构图。
- 预告片 30–60 秒。
- 检查中文在 920×430 下仍可读；小尺寸只保留标题。

## 许可

截图来自本项目；字体仅用于生成占位图，不随游戏分发。发布素材的字体/图标需确认商用许可。
