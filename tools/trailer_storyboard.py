#!/usr/bin/env python3
"""Render a 1920x1080 trailer storyboard contact sheet (6 shots)."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "docs" / "store"
SHOTS = STORE / "screenshots"
OUT = STORE / "trailer_storyboard.png"
FONT_BOLD = Path("C:/Windows/Fonts/bahnschrift.ttf")
FONT_SUB = Path("C:/Windows/Fonts/consola.ttf")
GOLD = (232, 196, 106)
CREAM = (244, 238, 220)
DARK = (10, 11, 18)


def font(path: Path, size: int):
    try:
        return ImageFont.truetype(str(path), size)
    except OSError:
        return ImageFont.load_default()


def fit(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    w, h = size
    scale = max(w / img.width, h / img.height)
    img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    x = (img.width - w) // 2
    y = (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def main() -> None:
    cells = [
        ("0:00", "LOGO", "logo_920x430.png", "5x7 pixel wordmark"),
        ("0:04", "COMBAT", "screenshots/01_combat.png", "one hero, visible intents"),
        ("0:09", "AIM", "screenshots/03_aim.png", "distance + damage preview"),
        ("0:14", "SHOP", "screenshots/04_shop.png", "spend gold, refill bomb"),
        ("0:18", "CHUNKS", "screenshots/05_chunks.png", "edge gates + minimap"),
        ("0:23", "BOSS / END", "key_art_1920x1080.png", "cut to logo at 0:27"),
    ]
    W, H = 1920, 1080
    sheet = Image.new("RGB", (W, H), DARK)
    draw = ImageDraw.Draw(sheet)
    draw.text((48, 30), "VX: AETHER KEEP — 30s TRAILER STORYBOARD", font=font(FONT_BOLD, 42), fill=CREAM)
    draw.text((48, 84), "6 shots / 1920x1080 / 30fps / gameplay capture + logo end card", font=font(FONT_SUB, 20), fill=GOLD)

    cw, ch = 600, 338
    gap = 24
    x0, y0 = 48, 130
    for i, (t, label, rel, note) in enumerate(cells):
        col = i % 3
        row = i // 3
        x = x0 + col * (cw + gap)
        y = y0 + row * (ch + 78)
        src = Image.open(STORE / rel).convert("RGB")
        tile = fit(src, (cw, ch))
        sheet.paste(tile, (x, y))
        draw.rectangle((x, y, x + cw, y + ch), outline=GOLD, width=3)
        draw.rectangle((x, y + ch - 30, x + cw, y + ch), fill=DARK)
        draw.text((x + 10, y + ch - 27), f"{t}  {label}", font=font(FONT_SUB, 18), fill=GOLD)
        draw.text((x, y + ch + 10), note, font=font(FONT_SUB, 16), fill=(170, 176, 190))

    draw.text((48, H - 38), "Cut on the beat. End card: logo + wishlist line. No fake gameplay.", font=font(FONT_SUB, 18), fill=(160, 168, 184))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT, optimize=True)
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
