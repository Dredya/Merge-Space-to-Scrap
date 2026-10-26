# Scrap to Space — build report

Environment: Godot **4.7.2.stable** (`godot.windows.opt.tools.64`), Windows, project
`D:/ai proj/godot proj/my first game/my-first-game-`.

`headless` is used for all automated checks. No Android device or APK was available, so
device-specific behaviour is explicitly listed as unverified at the end.

## What was implemented

### Core loop
- 5x6 merge board (30 slots) with drag-and-drop merge, move, tap-to-select and sell.
- Merge validates type **and** tier; invalid drops return the item to its slot; failed
  merges and moves are asserted to never duplicate or lose items.
- Merge feedback: pop-in tween, CPU particle burst, procedural sound, haptic pulse.
- Three merge families: Electronics (8 tiers, matching the brief), Mechanic (5), Quantum (5).
- Selling awards the exact catalog value; workshop orders request a specific item and
  quantity and pay ~1.9x its sell value.
- Three production machines (collector, sorter, salvage arm) with levels 0–12, per-level
  intervals/capacities, accumulation buffers, a COLLECT button, and a board-full guard.
- Board expansion (30 → 35 → 40 slots) with escalating prices.
- Spaceship: five components (hull, engine, power core, navigation, cargo), four paid
  levels each, costing credits **and** merged components consumed from the board.
- Procedural ship illustration that visibly grows: plating, pods, engine flames, core
  glow, navigation dish.
- Three destinations with requirement gating, timers, seeded rewards, rare drops and a
  result panel.
- Six-step interactive tutorial banner; skippable in settings.
- Merge-board pointer handling is an explicit `IDLE → PRESSED → DRAGGING` state machine
owned by the board. Tiles are passive visuals, so reparenting them mid-gesture cannot
swallow a release; taps only reparent after crossing a 14 px threshold, and every exit
path (drop, invalid drop, outside drop, cancel, focus loss, missed release, board change,
resize) rebuilds the grid from state to guarantee no stuck or duplicated items.

### Systems
- **Save:** versioned JSON at `user://scrap_to_space_save.json`, atomic write, `.bak`
  rotation, quarantine of unreadable/newer saves (never deleted), load validation,
  debounced autosave, save on pause/focus loss, 2-hour capped offline production.
- **Audio:** every sound synthesised at startup (tone generator + 8-second music loop).
  No audio assets; safe when muted and skipped entirely in headless runs.
- **Monetization:** provider interfaces for rewarded ads and purchases; shipped ad
  provider is explicitly simulated and labelled "simulated" in the UI; purchase provider
  reports unconfigured instead of faking a transaction; nothing gates progression.
- **UI:** shared theme/palette/widget kit, animated starfield, persistent credit bar,
  four-screen bottom navigation, settings overlay with volume sliders, haptics toggle,
  save-now, skip-tutorial and confirmed progress reset.

## Verification performed

Commands and results (run after the final edits):

```bash
# 1. Startup smoke: boots the real main scene, 240 frames, no errors
godot --headless --path . --quit-after 240 -- --test-mode
# -> clean run, exit 0

# 2. Real GPU boot (no --headless): confirms the mobile renderer path
# -> "D3D12 12_0 - Forward Mobile" on an RTX 3050 Ti, exit 0

# 3. Rules / state / persistence suite
godot --headless --path . tests/test_runner.tscn -- --test-mode
# -> 144 passed, 0 failed (exit 0)

# 4. UI smoke: boots main scene inside a SubViewport and drives real screen actions
godot --headless --path . tests/ui_smoke_test.tscn -- --test-mode
# -> 49 passed, 0 failed (exit 0)

# 5. Board input: injects real mouse/touch press, motion and release events
#    through Viewport.push_input() into Godot's GUI routing
godot --headless --path . tests/board_input_test.tscn -- --test-mode
# -> 171 passed, 0 failed (exit 0)
```

### Rule suite (144 assertions)
Covers: catalog/merge-chain integrity, merge compatibility and max-tier refusal, new-game
state, move/merge/invalid-drop invariants (no duplication or loss), selling values,
upgrade pricing and affordability blocks, board expansion, order delivery and replacement,
ship component costs/material consumption/max level, destination gating, deterministic
expedition rewards, claim timing, tutorial ordering, production collection with a full and
partially-full board, save round trip (credits, board, size, parts, stats, tutorial),
active-expedition persistence across a reload, corrupt-save recovery, newer-version
rejection, offline accrual at the machine rate, offline capacity cap, invalid (future)
timestamps, muted-audio safety, unconfigured purchases, and the mocked rewarded-ad flow.

### Board-input suite (171 assertions)
Injects genuine pointer events (never calling gameplay methods) and covers: tap select,
tap on empty, drag to empty slot, merge, incompatible drop, drop outside the board,
release back on the origin, programmatic cancel, focus loss, missed release (watchdog),
rapid taps on several items, consecutive merges, immediate interaction after a merge,
duplicate release, native touch tap/drag/merge/outside, OS-cancelled touch, second-finger
interference, and save/reload after moving and merging. Every scenario also asserts there
is no floating tile, no stale drag reference and that visible tiles exactly match board
data. Verified to fail when the original bug is reintroduced (it produced 13 failures:
stuck `DRAGGING` state, lost item, unresponsive board).

### UI suite (49 assertions)
Covers: four screens created, navigation shows exactly one screen at a time, settings
overlay separate from nav, real button-press handlers for collect/sell/merge/upgrade/expand/
build/depart/claim/close-result, tutorial banner hiding, maxed-component button state,
locked-destination refusal, settings sliders writing through to state, reset requiring
dialog confirmation before wiping progress, plus a recursive
layout audit (no visible control outside the viewport; no enabled button under 44 px tall)
at **720x1280, 720x960, 900x1600 and 1080x2400**.

### Bugs found and fixed during verification
1. **Upgrade pricing off by one level** — the first collector upgrade charged 80 instead of
   the configured 50. Formula now uses `base * growth^(level-1)`.
2. **Save-quarantine filename collision** — two unreadable saves in the same second
   overwrote each other's recovery copy. Names now include microseconds.
3. **Undersized touch targets** — two order DELIVER buttons measured 36 px and the sell
   button 42 px. Both raised to ≥44 px; the layout audit now enforces this.
4. **Console noise on damaged saves** — `JSON.parse_string` printed an engine error when a
   player's file was corrupt. Switched to `JSON.new().parse()` with the same recovery path.
5. **Audio leak warnings on forced quit** — playback streams were still held at shutdown;
   released in `_exit_tree` and audio work now short-circuits under headless.
6. **Tiles getting stuck after a tap/drag** — the dragged tile switched its own
   `Control.mouse_filter` to `IGNORE` at press time, so Godot never delivered the matching
   release to it. The gesture stayed active forever: the tile floated under the pointer,
   the slot looked empty, and `_drag_index` blocked all further input on the board.
   Input now belongs to the board (which never changes filters), tiles are passive
   (`IGNORE`), reparenting happens only after the tap threshold, and every exit path
   funnels through one cleanup + rebuild. A `Viewport.push_input()` regression suite
   (171 assertions) pins the behaviour; reintroducing the old filter swap makes 13 of
   them fail.

## Known limitations

- **Android is unverified.** `export_presets.cfg` is configured (portrait, arm64, vibrate),
  but the export fails in this environment because Godot's editor settings have no Java or
  Android SDK paths. No APK/AAB was produced. Safe areas, real haptics, and
  background/foreground behaviour must be checked on a device — see
  [ANDROID_EXPORT.md](ANDROID_EXPORT.md).
- **Monetization is simulated.** No ad SDK is integrated; the mock provider waits ~1 s and
  returns success, and the UI labels it as simulated. There are no cosmetic skins or
  purchase flows.
- **Layout was verified programmatically, not visually.** The audit proves elements stay
  on-screen and touch targets are large enough, but it cannot judge aesthetics. A manual
  play-through on a phone is still worthwhile.
- **Balance is a first pass.** Credits, prices and reward ranges are centralised in
  `game_catalog.gd` and easy to retune, but no long-term economy playtest was done.
- **No localisation.** All strings are English and inline.
- **Merge board rebuilds its tiles** on each board change (≤40 lightweight Controls). Fine
  at gameplay frequencies; if profiling on a low-end device shows hitches, pool the tiles.
- **No flight simulation.** Expeditions are timer + result, as scoped by the brief.
- The bundled Funplay MCP editor plugin is untouched and unrelated to gameplay.

## Suggested next steps

1. Run the post-export checklist on a real Android device and capture safe-area issues.
2. Playtest the first 15 minutes and retune generator intervals / order rewards.
3. Integrate a real rewarded-ad SDK behind the existing provider interface.
4. Add cosmetic ship skins and a purchase flow only after a store is configured.
