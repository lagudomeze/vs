#!/usr/bin/env python3
"""Inventory Chinese string literals for localization planning."""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "docs" / "LOCALIZATION_AUDIT.md"
CJK = re.compile(r"[\u4e00-\u9fff]")
LIT = re.compile(r'"([^"\n]*[\u4e00-\u9fff][^"\n]*)"')

def main() -> None:
    rows = []
    all_lits: Counter[str] = Counter()
    total_chars = 0
    for path in sorted(SRC.rglob("*.zig")):
        text = path.read_text(encoding="utf-8")
        lits = LIT.findall(text)
        chars = len(CJK.findall(text))
        total_chars += chars
        for lit in lits:
            all_lits[lit] += 1
        if lits or chars:
            rows.append((path.relative_to(ROOT).as_posix(), len(lits), len(set(lits)), chars))

    lines = [
        "# 本地化审计",
        "",
        "生成器：tools/i18n_audit.py。范围：src/**/*.zig 的双引号字符串。",
        "",
        "## 总计",
        "",
        f"- 文件：{len(rows)}",
        f"- 字符串出现次数：{sum(r[1] for r in rows)}",
        f"- 去重字符串：{len(all_lits)}",
        f"- CJK 字符数：{total_chars}",
        "",
        "## 按文件",
        "",
        "| 文件 | 出现 | 去重 | CJK 字符 |",
        "| --- | --- | --- | --- |",
    ]
    for name, n, u, chars in rows:
        lines.append(f"| {name} | {n} | {u} | {chars} |")

    lines += [
        "",
        "## 高频字符串（前 40）",
        "",
        "| 字符串 | 次数 |",
        "| --- | --- |",
    ]
    for lit, n in all_lits.most_common(40):
        safe = lit.replace("|", "\\|")
        lines.append(f"| {safe} | {n} |")

    lines += [
        "",
        "## 分批计划",
        "",
        "1. 基础：i18n 模块、语言设置、字体宽度预算。",
        "2. 导航：设置、暂停、主菜单、帮助、死亡/胜利结算。",
        "3. 战斗：HUD 标签、天赋名/描述、状态名、敌人意图。",
        "4. 内容：物品、敌人、楼层、日志、教程。",
        "5. 验收：英文截图、文本溢出、Steam 页面语言声明。",
        "",
        "## 约束",
        "",
        "- 现有 CJK 字体是子集，英文可用同字体 ASCII；新增英文不依赖字形表。",
        "- HUD 面板固定宽，英文更长，需要逐屏截图检查溢出。",
        "- 日志是运行时生成，已产生的历史日志不会因切语言重译。",
        "- 不能只翻菜单留下中文战斗内容；半本地化必须明确标注 beta。",
        "",
        "## 术语表（草稿）",
        "",
        "| 中文 | English |",
        "| --- | --- |",
        "| 深渊守卫 | Abyss Warden |",
        "| 狂战士 | Warrior |",
        "| 元素法师 | Mage |",
        "| 时空法师 | Chronomancer |",
        "| 回合 | Turn |",
        "| 楼层 | Floor |",
        "| 护甲 | Armor |",
        "| 精力 | Energy |",
        "| 生命 | Health |",
        "| 金币 | Gold |",
        "| 祭坛 | Shrine |",
        "| 商店 | Shop |",
        "| 永久死亡 | Permadeath |",
        "",
        "本文件是审计，不是已完成本地化的声明。",
    ]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {len(rows)} files, {len(all_lits)} unique strings")

if __name__ == "__main__":
    main()
