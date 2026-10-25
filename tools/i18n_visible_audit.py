#!/usr/bin/env python3
"""Heuristic audit: Chinese literals not referenced by the i18n table."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
I18N = SRC / "game" / "i18n.zig"
OUT = ROOT / "docs" / "I18N_REMAINING.md"
LIT = re.compile(r'"([^"\n]*[\u4e00-\u9fff][^"\n]*)"')


def main() -> None:
    known = set(LIT.findall(I18N.read_text(encoding="utf-8")))
    t_arg = re.compile(r'i18n\.t\(\s*"([^"\n]+)"')
    for path in SRC.rglob("*.zig"):
        known.update(t_arg.findall(path.read_text(encoding="utf-8")))
    per_file: list[tuple[str, int, int]] = []
    remaining: Counter[str] = Counter()
    for path in sorted(SRC.rglob("*.zig")):
        if path == I18N:
            continue
        text = path.read_text(encoding="utf-8")
        lits = LIT.findall(text)
        left = [x for x in lits if x not in known]
        if left:
            per_file.append((path.relative_to(ROOT).as_posix(), len(lits), len(set(left))))
            remaining.update(left)

    lines = [
        "# 英文残留审计（启发式）",
        "",
        "生成器：tools/i18n_visible_audit.py。",
        "",
        "规则：扫描 src 中所有含 CJK 的双引号字符串，减去 i18n.zig 里出现过的字符串。",
        "这不是 AST 分析；被映射的字符串可能仍有别的显示路径，未映射的也可能不显示。",
        "",
        f"- 未在 i18n 表中出现的去重字符串：{len(remaining)}",
        f"- 涉及文件：{len(per_file)}",
        "",
        "## 按文件",
        "",
        "| 文件 | 中文出现 | 未映射去重 |",
        "| --- | --- | --- |",
    ]
    for name, total, left in per_file:
        lines.append(f"| {name} | {total} | {left} |")

    lines += [
        "",
        "## 未映射高频字符串（前 80）",
        "",
        "| 字符串 | 次数 |",
        "| --- | --- |",
    ]
    for lit, n in remaining.most_common(80):
        safe = lit.replace("|", "\\|")
        lines.append(f"| {safe} | {n} |")

    lines += [
        "",
        "## 处理原则",
        "",
        "- 先处理玩家可见的 HUD/日志/商店/结算。",
        "- 错误信息/存档校验可以保留中文，但要在英文模式有英文兜底。",
        "- 内容 description 若 UI 不展示，可后置。",
        "- 每次翻译后重跑本脚本，数字应下降。",
    ]
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(remaining)} unmapped, {len(per_file)} files")


if __name__ == "__main__":
    main()
