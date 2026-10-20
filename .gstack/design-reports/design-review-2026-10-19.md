# Tabletop UI review — 19 October 2026

Status: DONE_WITH_CONCERNS. Desktop playtest quality improved; not a claim of release readiness.

Checkpoint before changes: 6c7cd64 on Matt. No remote upload.

## Benchmark and scope

Reference points: Connections (https://www.nytimes.com/games/connections) and Waffle (https://wafflegame.net/). Their concise rules, clear board choices, limited attempts, and immediate feedback inform this pass. The NYT live board was inaccessible to the research tool; this is not a side-by-side visual audit of its current release. Official Connections help and Waffle's own page were consulted. Scope: the Godot desktop selection and clue interface, with result and narrow-window checks.

## Before and after judgment

These are qualitative design judgments, not player-study results.

- Overall desktop design: C → B. The original had personality, but repeated images and tiny captions weakened usability. The revision has accurate identity, readable descriptions, clearer selection, and a smaller instruction footprint.
- Generic/AI-template appearance: C → B. Repeated invented covers are gone. Warm paper and Jev remain as the game's consistent identity.
- Mobile/narrow-window design: C. Controls are reachable by scrolling, but horizontal candidate navigation is less polished than a purpose-built small-screen board.

## Findings and verification

### FINDING-001 — Repeated and misleading game images (high, content)

Before: three of four titles share unrelated fantasy artwork. After: 56 of 70 bundled titles have exact-name-matched Steam covers. Unknown titles use explicit typographic game-file cards, with no unrelated invented game scene. Credits/source URLs: assets/game-covers.json.

Status: verified. Commit: 54ca47b.
Evidence: screenshots/before-select.png → screenshots/art-select.png.

### FINDING-002 — Oversized board, duplicate instructions, separated Jev (medium, layout)

Before: cards expand vertically to consume the full workspace, a large panel repeats next-step instructions, and Jev's speech and portrait drift apart. After: bounded card region, one concise next-step line, larger descriptions and controls, and one grouped Jev composition. Clue phase explicitly says “Write your clue.”

Status: verified. Commit: d8401ab.
Evidence: screenshots/art-select.png → screenshots/layout-select.png; screenshots/layout-hint.png.

### FINDING-003 — Cropped logos, weak contrast, uneven card text, subtle interaction states (medium, readability)

The first revised screenshot revealed cropped cover logos. Full-image fitting now preserves titles; fixed text slots align the cards. A checked “YOUR SECRET” label supplements the selected outline. Hover outlines and existing keyboard focus rings identify actionable cards/buttons. Main muted text contrast is 6.05:1; primary button text is 4.61:1; success text is 5.86:1, calculated from source colors. These figures do not certify the whole UI's accessibility.

Status: verified visually and with layout checks. Commit: 7d5148a.
Evidence: screenshots/layout-select.png → screenshots/final-select.png; screenshots/final-hint.png.

## Re-evaluation after final screenshot

- All four choices in the user's example now have correct, distinct covers.
- Logos remain visible, descriptions align, and the next action is concise.
- Selected state has both a color and a text/check cue.
- Jev's dialogue and portrait form one secondary element.
- Selection, hint entry, and result screenshots render without script errors.
- Five-size layout checks pass. The isolated seven-level gameplay smoke check passes. Eight Python tests pass.
- No changes to the existing tests in this review pass. Player saves were not written by the review harness.

## Remaining work before an A-level release

1. Purpose-built narrow-window layout rather than horizontal card scrolling.
2. Real player observation for comprehension, timing, and keyboard-only flow.
3. More complete live-pool cover coverage and refined fallback designs.
4. Existing daily-board generation test failure remains outside this UI pass; the smoke check excludes that generator assertion. Live-board startup performance is not validated by curated-board screenshots.
5. Motion is restrained/static; no animation or reduced-motion audit was performed.

Quick wins delivered: distinct cover identities; readable descriptions; reduced instruction copy; joined Jev composition; stronger selected/action contrast.
