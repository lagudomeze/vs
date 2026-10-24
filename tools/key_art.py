#!/usr/bin/env python3
"""Compose a placeholder Steam key art from the clean gameplay capture."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "screenshots" / "store_clean.png"
OUT = ROOT / "docs" / "store" / "key_art_1920x1080.png"
FONT_BOLD = Path("C:/Windows/Fonts/bahnschrift.ttf")
FONT_SUB = Path("C:/Windows/Fonts/consola.ttf")

GOLD = (232, 196, 106)
CREAM = (244, 238, 220)
DARK = (8, 9, 14)


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(path), size)
    except OSError:
        return ImageFont.load_default()


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    if src.size != (640, 360):
        raise SystemExit(f"expected 640x360, got {src.size}")
    image = src.resize((1920, 1080), Image.NEAREST).convert("RGB")

    # Left-to-right shade for the title lockup.
    grad = Image.new("L", (1920, 1))
    for x in range(1920):
        t = x / 1919
        grad.putpixel((x, 0), int(235 * max(0.0, 1.0 - t * 1.25) ** 1.4))
    shade = Image.composite(Image.new("RGB", (1920, 1080), DARK), image, grad.resize((1920, 1080)))
    # Vignette top/bottom.
    v = Image.new("L", (1, 1080))
    for y in range(1080):
        t = abs(y / 540 - 1)
        v.putpixel((0, y), int(120 * t ** 2))
    shade = Image.composite(Image.new("RGB", (1920, 1080), DARK), shade, v.resize((1920, 1080)))

    draw = ImageDraw.Draw(shade)
    x, y = 96, 300
    draw.text((x, y), "PIXEL-ART DUNGEON CRAWL", font=font(FONT_SUB, 24), fill=GOLD)
    draw.text((x - 4, y + 42), "VX", font=font(FONT_BOLD, 240), fill=CREAM, stroke_width=6, stroke_fill=DARK)
    draw.text((x + 4, y + 300), "AETHER KEEP", font=font(FONT_BOLD, 58), fill=GOLD)
    draw.rectangle((x + 4, y + 380, x + 520, y + 384), fill=GOLD)
    draw.text((x + 4, y + 406), "DESCEND.  ADAPT.  SURVIVE.", font=font(FONT_SUB, 26), fill=CREAM)
    draw.text((x + 4, y + 452), "TURN-BASED  /  THREE FLOORS  /  ONE HERO", font=font(FONT_SUB, 18), fill=(160, 168, 184))

    # Simple corner runes.
    for cx, cy, dx, dy in [(48, 48, 1, 1), (1872, 48, -1, 1), (48, 1032, 1, -1), (1872, 1032, -1, -1)]:
        draw.line((cx, cy, cx + dx * 96, cy), fill=GOLD, width=3)
        draw.line((cx, cy, cx, cy + dy * 96), fill=GOLD, width=3)

    image = shade
    image.save(OUT, optimize=True)
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
