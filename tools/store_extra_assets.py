#!/usr/bin/env python3
"""Generate the remaining Steam library/store asset sizes from existing key art."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "docs" / "store"


def fit(im: Image.Image, box: tuple[int, int]) -> Image.Image:
    scale = min(box[0] / im.width, box[1] / im.height)
    return im.resize((round(im.width * scale), round(im.height * scale)), Image.Resampling.NEAREST)


def main() -> None:
    key = Image.open(STORE / "key_art_1920x1080.png").convert("RGB")
    logo = Image.open(STORE / "logo_920x430.png").convert("RGBA")

    # Library hero: 3840x1240, center crop from 16:9 key art.
    crop_h = round(key.width * 1240 / 3840)
    top = max(0, (key.height - crop_h) // 2)
    hero = key.crop((0, top, key.width, top + crop_h)).resize((3840, 1240), Image.Resampling.NEAREST)
    hero.save(STORE / "library_hero_3840x1240.png", optimize=True)

    # Library logo: transparent 1280x720, logo fitted and centered.
    canvas = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    scaled = fit(logo, (1120, 600))
    canvas.alpha_composite(scaled, ((1280 - scaled.width) // 2, (720 - scaled.height) // 2))
    canvas.save(STORE / "library_logo_1280x720.png", optimize=True)

    # Store page background.
    key.resize((1438, 810), Image.Resampling.NEAREST).save(STORE / "page_background_1438x810.png", optimize=True)

    # Community icon: square center crop of the logo, 184x184.
    side = min(logo.width, logo.height)
    left = (logo.width - side) // 2
    icon = logo.crop((left, 0, left + side, side)).resize((184, 184), Image.Resampling.NEAREST)
    icon.save(STORE / "community_icon_184x184.png", optimize=True)

    for name in (
        "library_hero_3840x1240.png",
        "library_logo_1280x720.png",
        "page_background_1438x810.png",
        "community_icon_184x184.png",
    ):
        p = STORE / name
        print(f"{p.relative_to(ROOT)} {Image.open(p).size}")


if __name__ == "__main__":
    main()
