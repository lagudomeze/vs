#!/usr/bin/env python3
"""Generate Steam store placeholder assets from a gameplay screenshot.

These are *layout-valid placeholders*: dimensions and naming are ready for
Steamworks, while final key art should replace them before launch.

Run from the repo root:
  python tools/store_assets.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "store" / "screenshots" / "01_combat.png"
CAPSULE_SRC = ROOT / "docs" / "screenshots" / "store_clean.png"
LOGO = ROOT / "docs" / "store" / "logo_920x430.png"
OUT = ROOT / "docs" / "store"
FONT_BOLD = Path("C:/Windows/Fonts/bahnschrift.ttf")
FONT_SUB = Path("C:/Windows/Fonts/consola.ttf")
TITLE = "VX"
SUB = "AETHER KEEP"
TAG = "PIXEL-ART DUNGEON CRAWL"

GOLD = (232, 196, 106)
CREAM = (244, 238, 220)
DARK = (10, 11, 18)


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(path), size)
    except OSError:
        return ImageFont.load_default()


def cover(image: Image.Image, size: tuple[int, int], focus: tuple[float, float] = (0.5, 0.45)) -> Image.Image:
    w, h = size
    scale = max(w / image.width, h / image.height)
    resized = image.resize((int(image.width * scale) + 1, int(image.height * scale) + 1), Image.LANCZOS)
    x = int((resized.width - w) * focus[0])
    y = int((resized.height - h) * focus[1])
    return resized.crop((x, y, x + w, y + h))


def backdrop(image: Image.Image, size: tuple[int, int], dark: float = 0.50) -> Image.Image:
    bg = cover(image, size).convert("RGB")
    shade = Image.new("RGB", size, DARK)
    bg = Image.blend(bg, shade, dark)
    # Vertical gradient: darker at the bottom for text.
    grad = Image.new("L", (1, size[1]))
    for y in range(size[1]):
        grad.putpixel((0, y), int(180 * (y / max(1, size[1] - 1)) ** 1.6))
    grad = grad.resize(size)
    black = Image.new("RGB", size, DARK)
    bg = Image.composite(black, bg, grad)
    return bg


def draw_mark(draw: ImageDraw.ImageDraw, box: tuple[int, int], title_size: int, sub_size: int, tag_size: int) -> None:
    x, y = box
    draw.text((x, y), TAG, font=font(FONT_SUB, tag_size), fill=GOLD)
    draw.text((x, y + tag_size + 10), TITLE, font=font(FONT_BOLD, title_size), fill=CREAM, stroke_width=2, stroke_fill=DARK)
    draw.text((x, y + tag_size + title_size + 22), SUB, font=font(FONT_BOLD, sub_size), fill=GOLD)
    line_y = y + tag_size + title_size + sub_size + 36
    draw.rectangle((x, line_y, x + title_size * 3, line_y + 4), fill=GOLD)


def capsule(src: Image.Image, name: str, size: tuple[int, int], box: tuple[int, int], title_size: int, sub_size: int, tag_size: int, dark: float = 0.50) -> None:
    image = backdrop(src, size, dark)
    logo = Image.open(LOGO).convert("RGBA")
    w, h = size
    lw = int(w * (0.62 if h > w else 0.55))
    lh = int(lw * logo.height / logo.width)
    logo = logo.resize((lw, lh), Image.LANCZOS)
    x = int((w - lw) * 0.08)
    y = int((h - lh) * (0.70 if h > w else 0.46))
    image.paste(logo, (x, y), logo)
    path = OUT / name
    image.save(path, optimize=True)
    print(f"{name}: {size[0]}x{size[1]} {path.stat().st_size // 1024} KB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    src = Image.open(SRC).convert("RGB")
    shot = src.resize((1920, 1080), Image.NEAREST)
    shot.save(OUT / "screenshot_1920x1080.png", optimize=True)
    print("screenshot_1920x1080.png")

    caps = Image.open(CAPSULE_SRC).convert("RGB")
    capsule(caps, "header_capsule_920x430.png", (920, 430), (56, 86), 120, 34, 18)
    capsule(caps, "small_capsule_462x174.png", (462, 174), (26, 32), 54, 18, 11)
    capsule(caps, "main_capsule_1232x706.png", (1232, 706), (72, 210), 156, 42, 20)
    capsule(caps, "vertical_capsule_748x1084.png", (748, 1084), (54, 690), 108, 30, 16)
    capsule(caps, "vertical_capsule_374x542.png", (374, 542), (28, 345), 54, 15, 9)
    capsule(caps, "library_capsule_600x900.png", (600, 900), (42, 585), 82, 22, 12)
    capsule(caps, "library_capsule_300x450.png", (300, 450), (22, 292), 41, 11, 7)


if __name__ == "__main__":
    main()
