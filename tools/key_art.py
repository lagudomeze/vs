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
MUTED = (160, 168, 184)
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
        grad.putpixel((x, 0), int(238 * max(0.0, 1.0 - t * 1.12) ** 1.35))
    shade = Image.composite(Image.new("RGB", (1920, 1080), DARK), image, grad.resize((1920, 1080)))
    # Vignette top/bottom.
    v = Image.new("L", (1, 1080))
    for y in range(1080):
        t = abs(y / 540 - 1)
        v.putpixel((0, y), int(150 * t ** 2))
    shade = Image.composite(Image.new("RGB", (1920, 1080), DARK), shade, v.resize((1920, 1080)))

    logo = Image.open(ROOT / "docs" / "store" / "logo_920x430.png").convert("RGBA")
    logo = logo.resize((720, 337), Image.LANCZOS)
    shadow = Image.new("RGBA", logo.size, (0, 0, 0, 0))
    shadow.putalpha(logo.getchannel("A").point(lambda a: int(a * 0.55)))
    shade.paste(Image.new("RGB", logo.size, DARK), (87, 233), shadow)
    shade.paste(logo, (84, 230), logo)

    draw = ImageDraw.Draw(shade)
    draw.text((92, 150), "A TURN-BASED ROGUELIKE", font=font(FONT_SUB, 20), fill=GOLD)
    x, y = 92, 596
    draw.rectangle((x, y, x + 620, y + 4), fill=GOLD)
    draw.text((x, y + 28), "DESCEND.  ADAPT.  SURVIVE.", font=font(FONT_SUB, 32), fill=CREAM)
    draw.text((x, y + 82), "THREE CLASSES  /  THREE FLOORS  /  ONE HERO", font=font(FONT_SUB, 19), fill=MUTED)
    draw.text((x, y + 118), "WISHLIST ON STEAM", font=font(FONT_SUB, 17), fill=GOLD)

    # Corner runes.
    for cx, cy, dx, dy in [(48, 48, 1, 1), (1872, 48, -1, 1), (48, 1032, 1, -1), (1872, 1032, -1, -1)]:
        draw.line((cx, cy, cx + dx * 96, cy), fill=GOLD, width=3)
        draw.line((cx, cy, cx, cy + dy * 96), fill=GOLD, width=3)

    image = shade
    image.save(OUT, optimize=True)
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
