# 30 秒预告片（占位版）

文件：docs/store/trailer_30s.mp4

## 规格

- 30.00 秒
- 1920x1080
- 24 fps
- H.264 High / yuv420p
- AAC-LC 44.1kHz stereo
- 约 2.7 MB

## 内容

6 个 5 秒场景，底部实心字幕条：

1. CHOOSE CLASS - THREE CLASSES. ONE HERO.
2. 战斗 HUD - TURN-BASED COMBAT
3. 商店 - LOOT. GEAR. CHOOSE.
4. Boss - FACE THE ABYSS WARDEN
5. 每日菜单 - DAILY CHALLENGE
6. 胜利徽章 - WISHLIST ON STEAM

音频为 Python 合成的低频氛围垫 + 2 秒脉冲，不是正式配乐。

## 重要限制

- 这是**截图占位版**，不是实机录屏
- 没有角色动画/战斗过程/UI 过渡
- 没有正式配乐/音效设计
- 上架前应替换为 30-60 秒实机 capture + 正式音频

## 重新生成

需要 imageio-ffmpeg：

    python -m pip install imageio imageio-ffmpeg
    python tools/make_trailer.py

脚本会写 docs/store/trailer_30s.mp4。

## 检查

- ffprobe：30.00s / 1920x1080 / h264 / aac
- volumedetect：mean -12.5 dB，max -3.1 dB
- 底部字幕条不遮挡游戏 HUD
