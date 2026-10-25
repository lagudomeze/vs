# Roadmap / 发行顺序

Snapshot: main b56652d (2026-10-26). No dates; order matters more than speed.

## Now: external playtest

- Entry: #441, pre-release v0.1.0-playtest.
- Goal: 5-10 real sessions, not downloads.
- Triage:
  - P0: crash, save loss, cannot start, soft-lock.
  - P1: rules confusion, unfair deaths, unreadable HUD, input failure.
  - P2: polish, content requests.
- Exit: P0 fixed, top 3 P1 fixed, one re-test build.

## Next: Steamworks account

- #121: partner account, 100 USD Direct fee, AppID + DepotID.
- Replace YOUR_APP_ID / YOUR_DEPOT_ID in steam/*.vdf.
- Upload a private build, launch it from the Steam client.
- Then make the Coming Soon page (at least 2 weeks before release).
- Exit: private build launches via Steam; Coming Soon page approved.

## Parallel: Deck / Proton

- #418: install the same build on Deck, test controls/fullscreen/performance.
- Record Proton version and whether Steam Input is needed.
- Exit: 30 minutes stable, controls usable, no hard block.

## Before store review

- #122: final store copy, 6+ screenshots, trailer, demo decision.
- Art/audio: replace placeholder key art and add licensed music.
- Human capture: record one real player session for the trailer.
- Exit: no placeholder assets in store materials; demo builds cleanly.

## Optional / later

- #120 ECS reflection: only if upstream exposes the API; not a release blocker.
- #115 Paradox Mage: only with a distinct gameplay hook; do not rename Chronomancer without it.
- More items/floors only after playtest data, not before.

## Rules

- Do not invent AppID, DepotID, playtest quotes, or Deck verification.
- Do not call English complete, the trailer human gameplay, or the build Steam-final.
- Keep deterministic packaging: tools/verify_repro.ps1.
