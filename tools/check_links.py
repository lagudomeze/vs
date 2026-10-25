#!/usr/bin/env python3
"""Fail on broken local Markdown links in README/CHANGELOG/docs."""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def targets() -> list[Path]:
    files = [ROOT / "README.md", ROOT / "CHANGELOG.md"]
    files.extend((ROOT / "docs").rglob("*.md"))
    return files


def main() -> int:
    broken: list[tuple[str, str]] = []
    for path in targets():
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for match in LINK.finditer(text):
            target = match.group(1).strip().split()[0].strip("<>")
            if not target or target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            rel = unquote(target.split("#", 1)[0])
            if not rel:
                continue
            if not (path.parent / rel).resolve().exists():
                broken.append((str(path.relative_to(ROOT)), target))
    for path, target in broken:
        print(f"{path}: {target}")
    print(f"broken local links: {len(broken)}")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
