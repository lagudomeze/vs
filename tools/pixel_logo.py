#!/usr/bin/env python3
"""Render a blocky VX pixel logo for store/key-art drafts."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "store" / "logo_920x430.png"
FONT_SUB = Path("C:/Windows/Fonts/consola.ttf")

GOLD = (232, 196, 106)
GOLD_HI = (247, 226, 164)
DARK = (8, 9, 14)
CREAM = (244, 238, 220)

GLYPHS = {
    "V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
}


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(path), size)
    except OSError:
        return ImageFont.load_default()


def block(draw: ImageDraw.ImageDraw, x: int, y: int, size: int, color) -> None:
    draw.rectangle((x, y, x + size - 1, y + size - 1), fill=color)


def main() -> None:
    scale = 30
    gap = 24
    logo_w = 5 * scale * 2 + gap
    logo_h = 7 * scale
    canvas = Image.new("RGBA", (920, 430), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    x0 = (920 - logo_w) // 2
    y0 = 70
    for glyph_i, ch in enumerate("VX"):
        gx = x0 + glyph_i * (5 * scale + gap)
        for row, line in enumerate(GLYPHS[ch]):
            for col, bit in enumerate(line):
                if bit != "1":
                    continue
                x = gx + col * scale
                y = y0 + row * scale
                block(draw, x + 5, y + 7, scale, DARK)
                block(draw, x, y, scale, GOLD)
                draw.rectangle((x, y, x + scale - 1, y + 5), fill=GOLD_HI)

    sub = "AETHER KEEP"
    f = font(FONT_SUB, 46)
    w = draw.textlength(sub, font=f)
    draw.text(((920 - w) / 2, y0 + logo_h + 30), sub, font=f, fill=CREAM)
    tag = "PIXEL-ART DUNGEON CRAWL"
    ft = font(FONT_SUB, 18)
    tw = draw.textlength(tag, font=ft)
    draw.text(((920 - tw) / 2, y0 + logo_h + 92), tag, font=ft, fill=GOLD)

    canvas.save(OUT, optimize=True)
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
