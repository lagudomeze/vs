# 真实引擎内录屏（auto bot）

文件：docs/store/gameplay_capture_30s.mp4

## 规格

- 29.5 秒
- 1920x1080（640x360 最近邻 3x）
- 30 fps
- H.264 High / yuv420p
- AAC-LC 44.1kHz stereo
- 约 12 MB

## 怎么来的

不是外部录屏软件。游戏自身的 headless auto bot 在真实模拟/渲染循环里跑 1800 帧，每 2 帧保存一次 640x360 PNG，再用 ffmpeg 放大编码：

    vx.exe --headless --auto --lang en --hero 0 --difficulty easy --seed 12345 \
      --frames 1800 --record docs/store/capture \
      --out docs/store/capture_last.png

    python tools/encode_capture.py docs/store/capture docs/store/gameplay_capture_30s.mp4

- --record 在 chdir 到存档目录前解析为绝对路径
- 产物为 900 帧 → 跳过开头 15 帧 → 885 帧 @30fps
- 音轨复用 trailer_30s.mp4 的合成氛围垫，不是正式配乐

## 内容限制

- **auto bot 自动游玩**，不是人手实机操作
- 没有解说、字幕、转场、正式 VFX
- 仍可能有屏幕震动时的黑边帧
- 不是最终上架预告片；最终版需要人手 capture + 正式音频

## 检查

    ffprobe -hide_banner docs/store/gameplay_capture_30s.mp4
    # 29.50s / 1920x1080 / 30fps / h264 / aac

## 重新生成

需要 imageio-ffmpeg、Pillow：

    python -m pip install imageio-ffmpeg pillow
    python tools/encode_capture.py <frames-dir> <out.mp4>
