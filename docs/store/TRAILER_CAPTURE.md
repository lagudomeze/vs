# 真实引擎内录屏版 30s 预告片

文件：docs/store/trailer_capture_30s.mp4

## 规格

- 30.00 秒
- 1920x1080
- 30 fps
- H.264 High / yuv420p
- AAC-LC 44.1kHz stereo
- 约 10.2 MB

## 时间线

| 时间 | 内容 |
| --- | --- |
| 0.0–2.5s | 标题卡：像素 VX logo + AETHER KEEP + A TURN-BASED GRID ROGUELIKE |
| 2.5–27.5s | 真实引擎 auto-bot gameplay，顶部 5 条字幕 |
| 27.5–30.0s | 结束卡：WISHLIST ON STEAM / DEMO COMING SOON |

字幕：

1. ONE HERO. THREE CLASSES.
2. TURN-BASED GRID COMBAT.
3. LOOT. GEAR. CHOOSE.
4. THREE FLOORS. ONE WARDEN.
5. DAILY CHALLENGE.

## 来源

画面来自 docs/store/gameplay_capture_30s.mp4（headless auto bot 逐帧渲染），再用 tools/make_capture_trailer.py 加标题/字幕/结束卡。音轨复用 trailer_30s.mp4 的合成氛围垫。

    python tools/make_capture_trailer.py

## 限制

- **auto bot 自动游玩**，不是人手实机
- 音轨是合成占位，不是正式配乐
- 字幕条在场景中上部（y150–260），避开左上/右上 HUD
- Demo 尚未在 Steam 上线；“DEMO COMING SOON”是保守表述
- 最终上架版仍需人手 capture、正式音频、人工剪辑
