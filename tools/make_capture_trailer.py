"""Build a 30s trailer from the real engine capture.

2.5s title card + 25s gameplay (5 captions) + 2.5s end card.
The gameplay is the headless auto-bot capture, not human footage.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1920, 1080, 30
SRC = Path("docs/store/gameplay_capture_30s.mp4")
DST = Path("docs/store/trailer_capture_30s.mp4")
LOGO = Path("docs/store/library_logo_1280x720.png")
TITLE_FRAMES = 75
END_FRAMES = 75
PLAY_FRAMES = 750  # 25s
CAPTIONS = [
    "ONE HERO. THREE CLASSES.",
    "TURN-BASED GRID COMBAT.",
    "LOOT. GEAR. CHOOSE.",
    "THREE FLOORS. ONE WARDEN.",
    "DAILY CHALLENGE.",
]
FONT_CANDIDATES = [
    "C:/Windows/Fonts/bahnschrift.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
]


def font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def center_text(d: ImageDraw.ImageDraw, y: int, text: str, f, fill):
    box = d.textbbox((0, 0), text, font=f)
    d.text(((W - (box[2] - box[0])) // 2, y), text, font=f, fill=fill)


def card(title: str, subtitle: str) -> Image.Image:
    im = Image.new("RGB", (W, H), (7, 9, 16))
    d = ImageDraw.Draw(im)
    if LOGO.exists():
        logo = Image.open(LOGO).convert("RGBA")
        lw = 1000
        lh = int(logo.height * lw / logo.width)
        logo = logo.resize((lw, lh), Image.Resampling.NEAREST)
        im.paste(logo, ((W - lw) // 2, 90), logo)
    if title:
        center_text(d, 760, title, font(54), (255, 238, 180))
    center_text(d, 840 if title else 760, subtitle, font(32), (150, 190, 210))
    return im


def main() -> int:
    if not SRC.exists():
        print("missing", SRC)
        return 1
    if not LOGO.exists():
        print("missing", LOGO)
        return 1
    DST.parent.mkdir(parents=True, exist_ok=True)
    silent = DST.with_suffix(".video.mp4")
    writer = imageio_ffmpeg.write_frames(
        str(silent),
        (W, H),
        fps=FPS,
        codec="libx264",
        pix_fmt_in="rgb24",
        pix_fmt_out="yuv420p",
        macro_block_size=1,
        output_params=["-crf", "23", "-preset", "medium"],
    )
    writer.send(None)

    title = card("", "A TURN-BASED GRID ROGUELIKE")
    for _ in range(TITLE_FRAMES):
        writer.send(title.tobytes())

    reader = imageio_ffmpeg.read_frames(str(SRC), pix_fmt="rgb24")
    meta = next(reader)
    if tuple(meta["size"]) != (W, H):
        raise SystemExit(f"unexpected size {meta['size']}")
    for i, raw in enumerate(reader):
        if i < 15:
            continue
        if i - 15 >= PLAY_FRAMES:
            break
        im = Image.frombytes("RGB", (W, H), raw)
        d = ImageDraw.Draw(im, "RGBA")
        d.rectangle((0, 0, W, 110), fill=(5, 7, 12, 190))
        caption = CAPTIONS[min(len(CAPTIONS) - 1, (i - 15) * len(CAPTIONS) // PLAY_FRAMES)]
        center_text(d, 32, caption, font(48), (255, 238, 180))
        writer.send(im.tobytes())

    end = card("WISHLIST ON STEAM", "DEMO COMING SOON")
    for _ in range(END_FRAMES):
        writer.send(end.tobytes())
    writer.close()

    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    audio = Path("docs/store/trailer_30s.mp4")
    if audio.exists():
        subprocess.run(
            [
                ffmpeg, "-y",
                "-i", str(silent),
                "-i", str(audio),
                "-map", "0:v:0", "-map", "1:a:0",
                "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                "-shortest", str(DST),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        silent.unlink(missing_ok=True)
    else:
        silent.replace(DST)
    print(f"wrote {DST} ({DST.stat().st_size / 1e6:.2f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
