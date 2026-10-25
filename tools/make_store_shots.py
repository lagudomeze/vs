#!/usr/bin/env python3
"""Upscale native 640x360 screenshots to Steam's 1920x1080 with nearest neighbor."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "screenshots"
OUT = ROOT / "docs" / "store" / "screenshots_1920"
SHOTS = [
    "combat_bomb_hud.png",
    "gameplay_en.png",
    "shop_en.png",
    "boss_hud.png",
    "victory_badge.png",
    "character_en.png",
    "daily_menu.png",
]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in SHOTS:
        src = SRC / name
        if not src.exists():
            print(f"skip missing {name}")
            continue
        im = Image.open(src).convert("RGB")
        if im.size != (640, 360):
            print(f"skip {name}: {im.size}")
            continue
        out = OUT / name.replace(".png", "_1920.png")
        im.resize((1920, 1080), Image.Resampling.NEAREST).save(out, optimize=True)
        print(f"{out.relative_to(ROOT)} {out.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
