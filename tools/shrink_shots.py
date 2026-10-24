#!/usr/bin/env python3
"""Quantize game screenshots to the 64-colour palette and optimize the PNG.

The renderer only emits 64 colours, but the raw screenshot writer stores RGB
without deflate compression. Re-saving through Pillow as an adaptive 64-colour
palette keeps the image visually identical and cuts each shot from ~690 KB to
~10 KB.

Usage:
    python tools/shrink_shots.py docs/screenshots/*.png
    python tools/shrink_shots.py --check docs/screenshots
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

THRESHOLD = 100_000  # bytes; anything above is suspicious for 640x360


def shrink(path: Path) -> tuple[int, int]:
    before = path.stat().st_size
    with Image.open(path) as im:
        im = im.convert("RGB")
        out = im.quantize(colors=64, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        out.save(path, format="PNG", optimize=True)
    return before, path.stat().st_size


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--check", action="store_true", help="fail if any file is still large")
    args = ap.parse_args()
    bad = 0
    for raw in args.paths:
        path = Path(raw)
        files = sorted(path.glob("*.png")) if path.is_dir() else [path]
        for f in files:
            if not f.exists():
                print(f"missing: {f}", file=sys.stderr)
                bad += 1
                continue
            if f.stat().st_size <= THRESHOLD:
                continue
            if args.check:
                print(f"large: {f} {f.stat().st_size} bytes")
                bad += 1
                continue
            before, after = shrink(f)
            print(f"{f}: {before} -> {after} bytes")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
