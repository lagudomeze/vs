#!/usr/bin/env python3
"""Build a 30s 1920x1080 placeholder trailer from store stills + synthesized audio."""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

import imageio
import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "docs" / "screenshots"
STORE = ROOT / "docs" / "store"
OUT = STORE / "trailer_30s.mp4"
FPS = 24
W, H = 1920, 1080
GOLD = (232, 196, 106)
CREAM = (244, 238, 220)

SCENES = [
    ("menu_en.png", "THREE CLASSES. ONE HERO."),
    ("gameplay_en.png", "TURN-BASED COMBAT"),
    ("shop_en.png", "LOOT. GEAR. CHOOSE."),
    ("boss_hud.png", "FACE THE ABYSS WARDEN"),
    ("daily_menu.png", "DAILY CHALLENGE"),
    ("victory_badge.png", "WISHLIST ON STEAM"),
]


def font(size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype("C:/Windows/Fonts/bahnschrift.ttf", size)
    except OSError:
        return ImageFont.load_default()


def caption(text: str) -> Image.Image:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # Opaque lower-third band hides the game's own footer.
    d.rectangle((0, H - 132, W, H), fill=(8, 9, 14, 255))
    d.line((0, H - 132, W, H - 132), fill=GOLD, width=2)
    f = font(46)
    tw = d.textlength(text, font=f)
    d.text(((W - tw) / 2, H - 92), text, font=f, fill=CREAM)
    return layer


def still(src: Image.Image) -> Image.Image:
    """Keep the full 16:9 frame so HUD/title text is never cropped."""
    return src.resize((W, H), Image.Resampling.NEAREST)


def make_audio(path: Path, seconds: float = 30.0) -> None:
    sr = 44100
    n = int(sr * seconds)
    t = np.arange(n, dtype=np.float64) / sr
    pad = np.zeros(n)
    for f, amp in ((55.0, 0.30), (82.41, 0.22), (110.0, 0.16), (164.81, 0.10)):
        lfo = 0.75 + 0.25 * np.sin(2 * np.pi * 0.07 * t + f)
        pad += amp * lfo * np.sin(2 * np.pi * f * t)
    pulse = np.zeros(n)
    for start in np.arange(0, seconds, 2.0):
        i = int(start * sr)
        length = min(int(0.18 * sr), n - i)
        if length <= 0:
            continue
        env = np.linspace(1.0, 0.0, length) ** 2
        pulse[i:i + length] += 0.25 * env * np.sin(2 * np.pi * 220.0 * np.arange(length) / sr)
    mix = pad + pulse
    fade = int(2.0 * sr)
    mix[:fade] *= np.linspace(0, 1, fade)
    mix[-fade:] *= np.linspace(1, 0, fade)
    mix *= 0.7 / max(1e-9, np.max(np.abs(mix)))
    stereo = np.repeat(mix.astype(np.float32)[:, None], 2, axis=1)
    import wave

    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((stereo * 32767).astype("<i2").tobytes())


def main() -> None:
    per = 5.0
    frames_per = int(per * FPS)
    with tempfile.TemporaryDirectory() as td:
        video = Path(td) / "video.mp4"
        audio = Path(td) / "audio.wav"
        make_audio(audio)
        writer = imageio.get_writer(
            video,
            fps=FPS,
            codec="libx264",
            quality=8,
            pixelformat="yuv420p",
            macro_block_size=None,
            ffmpeg_params=["-crf", "18", "-preset", "medium"],
        )
        for name, text in SCENES:
            src = Image.open(SHOTS / name).convert("RGB")
            if src.size != (W, H):
                src = src.resize((W, H), Image.Resampling.NEAREST)
            cap = caption(text)
            for i in range(frames_per):
                frame = still(src)
                frame = Image.alpha_composite(frame.convert("RGBA"), cap).convert("RGB")
                writer.append_data(np.asarray(frame))
        writer.close()

        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
        subprocess.run(
            [
                ffmpeg,
                "-y",
                "-i",
                str(video),
                "-i",
                str(audio),
                "-c:v",
                "copy",
                "-c:a",
                "aac",
                "-b:a",
                "192k",
                "-shortest",
                "-movflags",
                "+faststart",
                str(OUT),
            ],
            check=True,
            capture_output=True,
        )
    print(f"{OUT.relative_to(ROOT)} {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
