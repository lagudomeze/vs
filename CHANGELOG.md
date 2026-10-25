# Changelog

## v0.1.0 - playtest build (2026-10-25)

Single-hero, turn-based, grid roguelike. Windows x64, software renderer, 640x360 logical / integer scaling.

### Content

- 3 classes: Warrior, Mage, Chronomancer; 3 floors; Abyss Warden boss.
- 17 items, 7 elite affixes, 6 floor modifiers (EMBER / FROST / MIASMA / GILDED / BLOODMOON / SURGE).
- Daily challenge: one UTC seed per day, win streak, 6 badges.
- Shrines, shops, cursed chests, traps, chunks/minimap, visible enemy intents.
- Turn-based combat with telegraphed attacks; B fire bomb; talents 1/2/3.

### Input / UI

- Keyboard and Xbox-style gamepad defaults, A/B swap.
- Mouse: class cards, pause rows, shop, shrine, character stats, bag equip/drink/bomb, aim.
- Help overlay, first-run 8-second hint (once, persisted).
- Chinese HUD default; English beta.
- F2 settings: fullscreen, vsync, scale, volume, ambient, pad swap, ESDF, remap, chunks, screen shake, language.
- F3 feedback form + diagnostics; F4 diagnostics; F5/F9 save slots; F10 autosaves.

### Systems

- Save v3, reads v2, rejects v1; 1 MiB cap, 3 backups, 3 autosaves.
- Records/daily streak persistence; Steam Auto-Cloud paths *.save + records.json.
- Deterministic sim + QA3; 266 unit tests, 145 QA2, 250 QA3.
- Demo build: Warrior only, floor 1, separate saves.

### Tooling

- tools/preflight.ps1, tools/release_gate.ps1, package.ps1, demo_pack.ps1, playtest_pack.ps1, press_kit.ps1.
- SteamPipe templates in steam/; AppID/DepotID still placeholders.

### Known limitations

- English is beta; some dynamic text falls back to Chinese.
- No cloud conflict UI, achievements, Steam overlay, or Steam Input official mapping yet.
- Steam Deck/Proton not hardware-verified.
- Marketing capture/trailer uses an auto-bot, not human gameplay.
- Art/audio are prototype-level; no final key art or licensed soundtrack.

This is not a release commitment. AppID/DepotID and playtest data are not fabricated.
