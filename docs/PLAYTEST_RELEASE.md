# VX: AETHER KEEP - v0.1.1 playtest (early build)

Windows 10/11 x64. Not a Steam release. No AppID, no installer, no telemetry.

Supersedes v0.1.0-playtest.
Note: the exe still reports vx 0.1.0; v0.1.1-playtest is the packaging revision (records/i18n fixes).


## Fixed in this build

- records.json corruption is preserved as records.corrupt-<timestamp>.json and falls back to records.json.bak; a bad file can no longer silently zero lifetime stats.
- preflight i18n audits run with --check; stale docs fail and the working tree is not rewritten.
- Bag RISK marker; negative HP/armor items are manual only.
- 271 unit / 145 QA2 / 255 QA3.

## Try it

1. Download vx-playtest-0.1.1.zip and unzip.
2. Run vx.exe.
3. Read README_ZH / README and CONSENT first.

## Known limits

- English is beta; some text falls back to Chinese.
- No official Steam Input mapping, cloud conflict UI, achievements or overlay.
- Steam Deck/Proton not hardware-verified.
- Art/audio are prototype-level; trailer/capture are auto-bot, not human gameplay.
- No release date or price promised.

## Feedback

https://github.com/lagudomeze/vs/issues/441 or in-game F3. Include build tag, class, floor, seed, input device.

SHA256SUMS.txt is attached.
