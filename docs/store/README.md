# Steam 商店素材（占位）

这些图是**尺寸/命名可上传的占位**，不是最终 key art。上架前用正式美术替换同名文件。

生成：

~~~powershell
python tools/store_assets.py
~~~

源图：

- docs/screenshots/icons_hud.png：带 HUD 的游戏截图，用于 1920×1080 商店截图
- docs/screenshots/store_clean.png：--hide-hud --hide-labels 的干净场景，用于 Capsule 底图

## 文件

| 文件 | 尺寸 | 用途 |
| --- | --- | --- |
| screenshot_1920x1080.png | 1920×1080 | 商店截图（≥5 张，16:9） |
| header_capsule_920x430.png | 920×430 | Header Capsule |
| small_capsule_462x174.png | 462×174 | Small Capsule |
| main_capsule_1232x706.png | 1232×706 | Main Capsule |
| vertical_capsule_748x1084.png | 748×1084 | Vertical Capsule |
| vertical_capsule_374x542.png | 374×542 | Vertical Capsule 半尺寸 |
| library_capsule_600x900.png | 600×900 | Library Capsule |
| library_capsule_300x450.png | 300×450 | Library Capsule 半尺寸 |

## 上架前替换

- 标题字体/Logo 换成正式 logo；当前用 bahnschrift 占位。
- Capsule 底图换成专门构图，不再直接使用游戏截图。
- 截图补 5 张：战斗、Boss、商店/祭坛、背包、死亡/胜利。
- 预告片 30–60 秒。
- 检查中文在 920×430 下仍可读；小尺寸只保留标题。

## 许可

截图来自本项目；字体仅用于生成占位图，不随游戏分发。发布素材的字体/图标需确认商用许可。
