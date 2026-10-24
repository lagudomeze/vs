#!/usr/bin/env python3
"""Build demo store assets from real demo screens + logo lockup."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "docs" / "screenshots"
STORE = ROOT / "docs" / "store"
OUT = STORE / "demo"
GOLD = (232, 196, 106)
CREAM = (244, 238, 220)
MUTED = (160, 168, 184)
DARK = (8, 9, 14)


def font(size: int):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/bahnschrift.ttf", size)
    except OSError:
        return ImageFont.load_default()


def upscale(src: Path, size=(1920, 1080)) -> Image.Image:
    img = Image.open(src).convert("RGB")
    if img.size == (640, 360):
        return img.resize(size, Image.NEAREST)
    return img.resize(size, Image.LANCZOS)


def badge(img: Image.Image, fsize: int = 28) -> Image.Image:
    draw = ImageDraw.Draw(img)
    label = "DEMO"
    f = font(fsize)
    tw = draw.textlength(label, font=f)
    x = img.width - tw - 38
    y = 24
    draw.rectangle((x - 12, y - 8, x + tw + 12, y + fsize + 6), fill=DARK, outline=GOLD, width=2)
    draw.text((x, y), label, font=f, fill=GOLD)
    return img


def crop_cover(src: Image.Image, size: tuple[int, int]) -> Image.Image:
    w, h = size
    scale = max(w / src.width, h / src.height)
    img = src.resize((int(src.width * scale), int(src.height * scale)), Image.LANCZOS)
    x = (img.width - w) // 2
    y = (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def demo_art(art: Image.Image, size: tuple[int, int]) -> Image.Image:
    w, h = size
    img = crop_cover(art, size)
    panel_w = int(w * 0.58)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, panel_w, h), fill=DARK)

    logo = Image.open(STORE / "logo_920x430.png").convert("RGBA")
    lw = int(panel_w * 0.78)
    lh = int(lw * logo.height / logo.width)
    logo = logo.resize((lw, lh), Image.LANCZOS)
    lx = 48
    ly = max(28, (h - lh) // 2 - 24)
    img.paste(logo, (lx, ly), logo)

    f1 = font(max(20, int(h * 0.072)))
    f2 = font(max(16, int(h * 0.052)))
    ty = ly + lh + 14
    d.text((lx + 6, ty), "WARRIOR / FLOOR 1", font=f1, fill=CREAM)
    d.text((lx + 6, ty + f1.size + 8), "WISHLIST ON STEAM", font=f2, fill=GOLD)
    d.line((lx + 6, ty - 10, lx + lw - 8, ty - 10), fill=GOLD, width=3)
    return badge(img, max(20, int(h * 0.065)))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, src in [("demo_menu.png", "demo_locked.png"), ("demo_end.png", "demo_end.png")]:
        upscale(SHOTS / src).save(OUT / name, optimize=True)

    art = Image.open(STORE / "key_art_1920x1080.png").convert("RGB")
    demo_art(art, (920, 430)).save(OUT / "demo_header_920x430.png", optimize=True)
    demo_art(art, (616, 353)).save(OUT / "demo_capsule_616x353.png", optimize=True)
    for p in sorted(OUT.glob("*.png")):
        print(f"{p.relative_to(ROOT)}: {p.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
