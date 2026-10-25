"""Encode headless gameplay frames into a 1920x1080 30s capture.

Usage: python tools/encode_capture.py docs/store/capture docs/store/gameplay_capture_30s.mp4
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import imageio_ffmpeg
from PIL import Image

FPS = 30
OUT_W, OUT_H = 1920, 1080


def main() -> int:
    src = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/store/capture")
    dst = Path(sys.argv[2] if len(sys.argv) > 2 else "docs/store/gameplay_capture_30s.mp4")
    frames = sorted(src.glob("frame_*.png"))
    if not frames:
        print("no frames in", src)
        return 1
    # Skip the opening fade/letterbox frames.
    frames = frames[15:]
    dst.parent.mkdir(parents=True, exist_ok=True)

    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    silent = dst.with_suffix(".video.mp4")
    writer = imageio_ffmpeg.write_frames(
        str(silent),
        (OUT_W, OUT_H),
        fps=FPS,
        codec="libx264",
        pix_fmt_in="rgb24",
        pix_fmt_out="yuv420p",
        macro_block_size=1,
        output_params=["-crf", "23", "-preset", "medium"],
    )
    writer.send(None)
    for i, frame in enumerate(frames):
        with Image.open(frame) as im:
            up = im.convert("RGB").resize((OUT_W, OUT_H), Image.Resampling.NEAREST)
            writer.send(up.tobytes())
        if i % 150 == 0:
            print(f"encoded {i}/{len(frames)}")
    writer.close()

    audio = Path("docs/store/trailer_30s.mp4")
    if audio.exists():
        subprocess.run(
            [
                ffmpeg, "-y",
                "-i", str(silent),
                "-i", str(audio),
                "-map", "0:v:0", "-map", "1:a:0",
                "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                "-shortest", str(dst),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        silent.unlink(missing_ok=True)
    else:
        silent.replace(dst)
    print(f"wrote {dst} ({dst.stat().st_size / 1e6:.2f} MB, {len(frames)} frames @ {FPS}fps)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
