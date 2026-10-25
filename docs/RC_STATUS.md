# RC Status / Human-Only Remaining Steps

Snapshot: main 6e83ffe (2026-10-26). This page is the single list of what code can and cannot finish.

## Verified in this repo

- zig build test: 266/266; test-qa: 145/145; test-qa3: 250/250.
- PREFLIGHT PASS; static Deck checks only.
- Deterministic packages: full EBD40A3F..., demo 859001A8..., playtest C98CB0F9..., press 05D53DD9...
- Full and demo run from a clean unzip; no AppID, no local saves shipped.
- Save v3 accepts v2, rejects v1; BLOODMOON/SURGE round-trip covered.
- Demo and playtest consent/feedback templates are static files.

## Human-only blockers

| Area | Blocked on | Exact next action | Issue |
| --- | --- | --- | --- |
| Steam account | No Steamworks partner account / AppID / DepotID | Register, pay 100 USD, create app + depot, replace YOUR_APP_ID/YOUR_DEPOT_ID, upload with steamcmd | #121 |
| Playtest | 0 real testers / 0 feedback records | Recruit 5-10, send playtest zip + CONSENT, collect FEEDBACK.md, triage top 3 | #122 |
| Deck/Proton | No Deck hardware | Install build on Deck, test controls/fullscreen/performance, record Proton version | #123 |
| Marketing art/audio | Prototype key art / auto-bot capture | Commission key art + licensed music, record human gameplay | #122 |
| Steam Input | No official mapping | Add Steam Input template or document keyboard/gamepad fallback | #123 |
| ECS reflection | Upstream zflecs naming/script API | Revisit only if upstream exposes reflection; not a release blocker | #120 |
| Paradox Mage | Design/refactor not scheduled | Keep current Chronomancer; no rename without gameplay | #115 |

## Verdict

- Internal/friends playtest: READY.
- Steam store/release: NOT READY until the first three rows are real.
- Do not describe English as complete, the trailer as human gameplay, or Deck as verified.

## Pointers

- Release gate: docs/BUILD_VERIFY.md
- Signoff: docs/RELEASE_SIGNOFF.md
- Playtest kit: docs/PLAYTEST_KIT.md
- Deck script: docs/DECK_CHECK.md
- Store copy: docs/store/PAGE.md
