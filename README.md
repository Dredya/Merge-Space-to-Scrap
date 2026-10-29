# Scrap to Space

A complete, offline, portrait-mobile merge game built with **Godot 4.7** and GDScript.
Collect scrap, merge components, sell them for credits, upgrade your salvage line,
rebuild a broken spaceship and fly it to three destinations.

Everything is generated at runtime: there are no imported sprites, fonts, or audio
files, so the project cannot fail on a missing asset.

## Requirements

- **Godot 4.7** (developed and verified with `4.7.2.stable`). Earlier 4.x versions may
  work but are untested.
- No plugins are required. The bundled `addons/funplay_mcp` editor plugin is optional.
- Android export additionally needs the Android SDK, JDK 17+ and export templates
  (see [docs/ANDROID_EXPORT.md](docs/ANDROID_EXPORT.md)).

## Run it

Open the folder in Godot and press **F5**, or from a terminal:

```bash
godot --path .                       # play
godot --path . --editor              # open the editor
godot --headless --path . --quit-after 200   # headless startup smoke check
```

The window opens at a 720x1280 portrait base with `canvas_items` stretch and
`expand` aspect, so the layout scales to phones and tablets.

## How to play

| Action | How |
|---|---|
| Collect scrap | **COLLECT** button under the salvage line |
| Merge | Drag one item onto an identical item (same type *and* tier) |
| Move | Drag an item onto an empty slot |
| Inspect / sell | Tap an item, then **SELL** |
| Fill orders | Keep the requested items on the board, then **DELIVER** |
| Upgrade | **UPGRADES** tab: build/upgrade machines, expand the board |
| Build the ship | **SHIP** tab: install Hull, Engine, Power Core, Navigation, Cargo |
| Travel | **TRAVEL** tab: pick an unlocked destination and **DEPART** |

The first session starts with 100 credits and a board seeded with mergeable circuits,
so the first merge happens within seconds. A six-step banner tutorial teaches collect,
merge, sell, upgrade, ship building and travel.

### Merge chains

- **Electronics** (8 tiers): Broken Circuit → Repaired Circuit → Electronic Module →
  Processing Unit → Advanced Processor → Navigation Computer → Quantum Core →
  Warp Drive Component
- **Mechanic** (5 tiers): Rusted Plate → Scrap Alloy → Reinforced Panel → Hardened
  Hull Plate → Titanium Composite
- **Quantum** (5 tiers): Flickering Shard → Neon Cell → Photon Relay → Prism Matrix →
  Singularity Lens

### Destinations

| Destination | Requires | Trip | Reward focus |
|---|---|---|---|
| Orbital Junkyard | Engine Lv 1 | 30 s | Electronics, low risk |
| Rustfall | Engine Lv 2 + Hull Lv 2 | 90 s | Mechanic scrap, rare alloys |
| Neon Moon | Navigation Lv 3 + Power Core Lv 3 | 180 s | Quantum components |

Expedition rewards are rolled from a seed at departure, so they are deterministic and
survive save/load. Only one trip runs at a time; completion is timestamp-based, so
closing the game mid-flight is safe.

## Project layout

```
project.godot                  # portrait mobile config, autoloads, main scene
scenes/                        # main + workshop/merge board + screens (thin .tscn shells)
scripts/
  data/game_catalog.gd         # ALL tuning: items, generators, parts, planets, tutorial
  logic/                       # pure rules: merge, economy, expeditions (no nodes)
  autoload/game_state.gd       # authoritative state + gameplay API + signals
  autoload/save_manager.gd     # versioned atomic save/load, quarantine recovery
  autoload/audio_manager.gd    # procedural SFX + music
  autoload/monetization_service.gd
  monetization/                # ad/purchase provider interfaces + mock provider
  ui/ui_kit.gd                 # shared palette, theme and widget builders
  workshop/, spaceship/, expedition/, ui/, main/
tests/                         # headless rule + UI smoke test runners
docs/                          # Android export guide and build report
```

Architecture rules used throughout:

- **State owns rules, screens own pixels.** Screens call `GameState` methods and listen
  to its signals; they never mutate gameplay arrays for their own purposes.
- **Pure math is separable.** Merge/economy/expedition formulas live in `scripts/logic`
  and take plain dictionaries, so they are unit tested without scenes.
- **Data-driven.** Adding a merge tier, machine, ship level or destination means editing
  `game_catalog.gd` only.

## Tuning the game

Everything lives in [scripts/data/game_catalog.gd](scripts/data/game_catalog.gd):

- Starting credits, board size, offline cap, boost multiplier and duration
- Merge chains, sell-value curves and rarity colours
- Machine prices, growth rates, intervals and capacities
- Ship component prices, material costs and effect text
- Destination durations, reward ranges, rare chances and requirements
- Tutorial step text

## Save data

- Location: `user://scrap_to_space_save.json` (plus `.bak` and, if a file is ever
  unreadable, `.corrupt-<timestamp>.json`).
- Versioned format (`version` field), validated on load.
- Atomic write (temp file + rename) with the previous file backed up.
- Autosaves ~0.5 s after meaningful changes, and on app pause / window focus loss.
- Offline production accrues on load, capped at 2 hours.
- Reset lives in **Settings → RESET PROGRESS** behind a confirmation dialog.

## Tests

All suites are headless, self-contained, and exit non-zero on failure:

```bash
godot --headless --path . tests/test_runner.tscn -- --test-mode
godot --headless --path . tests/ui_smoke_test.tscn -- --test-mode
godot --headless --path . tests/board_input_test.tscn -- --test-mode
```

`--test-mode` points the save manager at a throwaway `user://` file so your real save is
untouched.

Current result: **144/144** rule assertions, **49/49** UI assertions and **171/171**
board-input assertions pass. The input suite injects real `push_input()` press, motion and
release events (mouse and touch) through Godot's GUI routing.
See [docs/REPORT.md](docs/REPORT.md) for what each suite covers, bugs found, and known
limitations.

## Monetization (optional, off by default in effect)

- Rewarded ads are implemented behind `scripts/monetization/ad_provider.gd`. The shipped
  provider is a **simulated** one, clearly labelled as such in the UI; it grants no real
  ad view. Swap it in `monetization_service.gd` to integrate a real SDK.
- No purchase UI exists because no store is configured; the purchase interface reports
  "not available" instead of pretending a transaction happened.
- The game is fully playable with monetization disabled.

## Privacy & Terms (hosted)

Published for store listings (Google Play requires a public privacy policy URL):

- Privacy Policy: https://dredya.github.io/Merge-Space-to-Scrap/privacy-policy.html
- Terms & Conditions: https://dredya.github.io/Merge-Space-to-Scrap/terms.html

Source files: [docs/privacy-policy.md](docs/privacy-policy.md), [docs/terms.md](docs/terms.md).
Enable GitHub Pages once: repo **Settings → Pages → Source: main branch /docs folder**.

## License / third-party assets

All code in this project is original. `addons/funplay_mcp` is a third-party editor
plugin (FunplayAI) that was already present in the project and is unrelated to gameplay.
