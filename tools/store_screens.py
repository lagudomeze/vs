#!/usr/bin/env python3
"""Generate five 1920x1080 Steam screenshots from real gameplay captures.

Prereq:
  zig build -Doptimize=ReleaseFast

Run:
  python tools/store_screens.py
"""
from pathlib import Path
import subprocess

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
EXE = ROOT / "zig-out" / "bin" / "vx.exe"
OUT = ROOT / "docs" / "store" / "screenshots"
TMP = ROOT / "docs" / "store" / ".tmp_shots"

SCENES = [
    ("01_combat", ["--seed", "81", "--hero", "0", "--frames", "2", "--yaw", "30", "--pitch", "45"]),
    ("02_character", ["--seed", "81", "--hero", "0", "--frames", "1", "--character"]),
    ("03_aim", ["--seed", "81", "--hero", "0", "--frames", "1", "--aim", "1", "--yaw", "30", "--pitch", "45"]),
    ("04_shop", ["--seed", "81", "--hero", "0", "--frames", "1", "--shop"]),
    ("05_chunks", ["--seed", "81", "--hero", "0", "--frames", "1", "--chunks", "--yaw", "30", "--pitch", "45"]),
]


def main() -> None:
    if not EXE.exists():
        raise SystemExit(f"missing {EXE}; run: zig build -Doptimize=ReleaseFast")
    OUT.mkdir(parents=True, exist_ok=True)
    TMP.mkdir(parents=True, exist_ok=True)
    for name, args in SCENES:
        raw = TMP / f"{name}_640.png"
        cmd = [str(EXE), "--headless", *args, "--out", str(raw)]
        subprocess.run(cmd, cwd=ROOT, check=True, stdout=subprocess.PIPE, text=True)
        image = Image.open(raw).convert("RGB")
        if image.size != (640, 360):
            raise SystemExit(f"{name}: expected 640x360, got {image.size}")
        image = image.resize((1920, 1080), Image.NEAREST)
        path = OUT / f"{name}.png"
        image.save(path, optimize=True)
        print(f"{path.relative_to(ROOT)}: {path.stat().st_size // 1024} KB")
        raw.unlink(missing_ok=True)
    TMP.rmdir()


if __name__ == "__main__":
    main()
