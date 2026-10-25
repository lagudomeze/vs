# Steam 商店截图（1920×1080）

生成器：tools/make_store_shots.py

原生渲染是 640×360；商店要求至少 1920×1080，因此用 3× 最近邻放大，保留像素颗粒，不引入插值模糊/伪造细节。

| 文件 | 内容 | 语言 |
| --- | --- | --- |
| combat_bomb_hud_1920.png | 战斗/炸弹 HUD | 中 |
| gameplay_en_1920.png | 战斗 HUD/敌人意图 | 英 |
| shop_en_1920.png | 商店 | 英 |
| boss_hud_1920.png | Boss 血条 | 英 |
| victory_badge_1920.png | 胜利/徽章 | 英 |
| character_en_1920.png | 角色面板 | 英 |
| daily_menu_1920.png | 每日挑战菜单 | 中 |

## 检查

- 全部 1920×1080
- 无 debug HUD
- 无窗口边框
- 无未完成占位文本
- 中英各半，避免只放英文

## 重新生成

    python tools/make_store_shots.py

## 不能做

- 不要用 AI 放大伪造细节
- 不要拉伸到非 16:9
- 不要把 640 原图直接上传（Steam 会拒/糊）
- 不要在截图里放未实装的 Steam 功能
