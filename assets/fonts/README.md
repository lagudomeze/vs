# UI font

The Chinese HUD uses a generated subset of **Ark Pixel Font 12px** by TakWolf.

- Source: https://github.com/TakWolf/ark-pixel-font
- Version used: 2026.10.16
- File used: ark-pixel-font-12px-monospaced-bdf-v2026.10.16.zip → ark-pixel-12px-monospaced-zh_hans.bdf
- License: SIL Open Font License 1.1 (see OFL.txt)

Only the 12x12 glyph bitmaps for characters that appear in the game are
committed (src/core/cjk_font.zig). The BDF source is not needed at runtime.

## Regenerating

```powershell
gh release download 2026.10.16 -R TakWolf/ark-pixel-font -p "*12px-monospaced-bdf*" -D .tmp-font
Expand-Archive .tmp-font/ark-pixel-font-12px-monospaced-bdf-v2026.10.16.zip .tmp-font/bdf
python tools/gen_cjk_font.py
```

The generator scans src/**/*.zig for non-ASCII characters and adds the
characters in its EXTRA list (enemy/skill/UI names). It reports any codepoint
that is missing from the BDF.
