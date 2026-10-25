#!/usr/bin/env python3
"""Build a 20s demo trailer storyboard contact sheet from real captures."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "docs" / "screenshots"
STORE = ROOT / "docs" / "store"
OUT = STORE / "demo" / "demo_storyboard.png"
GOLD = (232, 196, 106)
CREAM = (244, 238, 220)
MUTED = (150, 158, 176)
DARK = (8, 9, 14)

SHOTS_LIST = [
    ("demo_menu.png", "01  ONE WARRIOR  /  2s", "Only the Warrior in the demo"),
    ("combat_bomb_hud.png", "02  TURN-BASED GRID  /  5s", "Plan, aim, detonate"),
    ("boss_enraged.png", "03  THE WARDEN  /  4s", "A boss that enrages"),
    ("chunk_map.png", "04  EXPLORE  /  3s", "Full game opens 3x3"),
    ("death_summary.png", "05  PERMADEATH  /  3s", "Death is permanent"),
    ("demo_end.png", "06  DEMO END  /  3s", "Wishlist on Steam"),
]


def font(size: int):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/bahnschrift.ttf", size)
    except OSError:
        return ImageFont.load_default()


def cover(img: Image.Image, w: int, h: int) -> Image.Image:
    scale = max(w / img.width, h / img.height)
    img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    x = (img.width - w) // 2
    y = (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def main() -> None:
    W, H = 1920, 1080
    canvas = Image.new("RGB", (W, H), DARK)
    d = ImageDraw.Draw(canvas)
    d.text((60, 34), "VX: AETHER KEEP - DEMO TRAILER BOARD", font=font(42), fill=GOLD)
    d.text((60, 86), "20 seconds / 6 shots / real captures - not a final video", font=font(22), fill=MUTED)

    tile_w, tile_h = 560, 300
    gap_x, gap_y = 45, 52
    x0, y0 = 60, 145
    for i, (name, cap, sub) in enumerate(SHOTS_LIST):
        col = i % 3
        row = i // 3
        x = x0 + col * (tile_w + gap_x)
        y = y0 + row * (tile_h + gap_y + 62)
        path = SHOTS / name
        if not path.exists():
            path = STORE / "demo" / name
        if not path.exists():
            img = Image.new("RGB", (tile_w, tile_h), (24, 26, 34))
            d.text((x + 20, y + 20), "MISSING " + name, font=font(20), fill=MUTED)
        else:
            img = cover(Image.open(path).convert("RGB"), tile_w, tile_h)
        canvas.paste(img, (x, y))
        d.rectangle((x, y, x + tile_w, y + tile_h), outline=GOLD, width=2)
        d.text((x, y + tile_h + 10), cap, font=font(24), fill=CREAM)
        d.text((x, y + tile_h + 38), sub, font=font(18), fill=MUTED)

    d.text((60, H - 56), "CUT: menu hook -> combat -> boss -> explore -> death -> demo end card", font=font(20), fill=MUTED)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT, optimize=True)
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
