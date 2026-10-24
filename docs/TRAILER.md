# 30 秒预告片分镜

状态：分镜与故事板完成；**尚未录制/编码成 MP4**。本机没有 ffmpeg，需要 OBS 或外部剪辑。

故事板：[trailer_storyboard.png](store/trailer_storyboard.png)

## 规格

- 1920×1080，30fps
- H.264 MP4，8–15 Mbps，<500 MB
- 30 秒；Steam 允许更长，但短视频更适合商店页自动播放
- 不加入未实现功能（联机、云存档 API、成就）

## 镜头表

| 时间 | 画面 | 来源 | 字幕/旁白 |
| --- | --- | --- | --- |
| 0:00–0:04 | 像素 VX logo + AETHER KEEP | logo_920x430.png | 无 |
| 0:04–0:09 | 战斗：英雄 + 敌人意图 + 天赋栏 | 01_combat | “Every action costs a turn.” |
| 0:09–0:14 | 冲锋瞄准，距离/伤害预览 | 03_aim | “See the cost before you commit.” |
| 0:14–0:18 | 商店，6 项服务/炸弹补货 | 04_shop | “Spend gold. Refill the bomb.” |
| 0:18–0:23 | 3×3 边缘门 + minimap | 05_chunks | “The dungeon continues at the edge.” |
| 0:23–0:27 | 战斗/Boss 快切 | 01_combat / 03_aim | “Three floors. One hero.” |
| 0:27–0:30 | logo 结束卡 | logo_920x430.png | “WISHLIST NOW” |

## 录制

### 静帧（已可用）

~~~powershell
$vx = ".\zig-out\bin\vx.exe"
& $vx --headless --seed 81 --hero 0 --frames 2 --yaw 30 --pitch 45 --out docs\store\trailer\combat.png
& $vx --headless --seed 81 --hero 0 --frames 1 --aim 1 --yaw 30 --pitch 45 --out docs\store\trailer\aim.png
& $vx --headless --seed 81 --hero 0 --frames 1 --shop --out docs\store\trailer\shop.png
& $vx --headless --seed 81 --hero 0 --frames 1 --chunks --out docs\store\trailer\chunks.png
~~~

### 实拍（OBS）

1. 启动窗口：vx.exe --seed 81 --hero 0 --yaw 30 --pitch 45
2. OBS 1920×1080 输出，游戏窗口 3× 整数缩放
3. 录制：战斗 5 秒 → 瞄准 4 秒 → 商店 4 秒 → 3×3 5 秒
4. 不录菜单/设置/调试 HUD；F1 关闭 debug
5. 结束卡用 logo 静帧叠加

### 剪辑

- 0:04 第一刀落在首次命中
- 转场只用硬切/0.15s 黑场，不用花哨转场
- 商店镜头加速 1.2×
- 结尾 0:27 logo 淡入 0.3s，保留 2 秒

## 音频

- 使用游戏内动态氛围（explore/danger/shop）
- OBS 录桌面音频；避免版权音乐
- 若外部配乐，需确认商用许可
- 保留 -14 LUFS 左右，避免爆音

## 验收

- [ ] 0–4 秒能看清 VX / AETHER KEEP
- [ ] 5 秒内出现第一次攻击/伤害
- [ ] 至少 1 个精英词缀或 Boss 镜头
- [ ] 商店/3×3 各出现 2 秒以上
- [ ] 无加载/菜单/黑屏超过 0.5 秒
- [ ] 结束卡有 Wishlist
