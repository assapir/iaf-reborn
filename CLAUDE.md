# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native re-implementation of the engine for Jane's IAF (1998): Rust crates (format parsers, converters, flight
model) plus a Godot 4.7 project that renders and runs the game. All game data comes from the user's own ISO and is
generated into the git-ignored `assets/`; the repo must never contain original game data.

## Commands

```sh
tools/setup.sh [--patch v1.1.exe] "/path/to/Jane's IAF.iso"   # one-time: extract + convert everything into assets/
./iafjets [-- --mission 311]                                  # builds the iaf-godot extension (release) and starts the game
cargo test -q --workspace                                     # Rust tests (data/python3-dependent ones skip with a message)
cargo test -q -p iaf-flight --test validation <name>          # one Rust test
tools/test.sh                                                 # everything: cargo tests + every tests/godot/test_*.gd headless
cargo build --release -p iaf-godot                            # needed before Godot tests: game loads target/release/libiaf_godot.*
IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path game -s ../tests/godot/test_radar.gd   # one Godot test
tools/ghidra/fn.sh 5643a0 | --grep PATTERN                    # decompiled original exe function (assets/ghidra_v11/iafjets.c)
tools/worktree.sh <name>                                      # parallel worktree sharing assets/ via symlink
```

- Always run scripted Godot tests / captures with `IAF_DEFAULT_SETTINGS=1` so the user's `settings.cfg` is never read
  or written. A Godot test passes only if it prints `RESULT PASS` and no `SCRIPT ERROR`.
- Godot tests need the converted assets, so there is no hosted CI; they run locally.
- On a fresh clone `game/.godot` is missing; `godot --headless --path game --import` once, or the extension won't load
  (`./iafjets` does this).
- `tests/godot/_*_shot.gd` are real-render screenshot helpers (usage in each header), not tests.

## Architecture

- `crates/iaf-formats` — parsers for the original file formats (ISO9660, PTT terrain, X models, ESA, EMF, menu, RTF,
  LZO…). Format notes in `docs/formats/`.
- `crates/iaf-tools` — CLIs used by `tools/setup.sh`: `iaf-extract` (ISO → `assets/install`), `iaf-patch` (v1.1 RTPatch
  without Windows), `iaf-convert` (cockpits, menus, keys, missions, aircraft → `assets/converted`, plus
  `plane-describe` / `plane-checklist`), `iaf-terrain`, `iaf-imagery`, `iaf-import-pack`, `iaf-mission-report`.
- `crates/iaf-flight` — the original flight model and AI autopilot, pure Rust, re-implemented from
  `docs/flight-model.md` / `docs/autopilot.md`. Tests in `crates/iaf-flight/tests/` (validation against the envelope
  reference `tools/envelope_ref.py`).
- `crates/iaf-godot` — gdext bridge exposing `IafFlight` to GDScript (`flight.rs`). Handles the frame conversion:
  FM is ENU (east, north, up); Godot is X east, Y up, Z south. Loaded via `game/iaf.gdextension`.
- `game/` — Godot project. Main scene `menu/front_end.tscn`; autoloads `Settings` (`settings.gd`) and `Joystick`.
  Flight scene is `terrain/terrain_view.tscn`. Subdirs by system: `aircraft`, `ai`, `cockpit`, `weapons` (radar, RWR,
  stores), `mission`, `menu`, `audio`, `controls`, `terrain`. Assets are read at run time from
  `res://../assets/converted/...` and `assets/install`.
- `tests/godot/` — headless tests extending `tests/godot/base.gd` (`check()`, `frames()`, `start_mission(id)`).

Rule of placement: game logic belongs in the Rust crates; Godot renders and wires.

## Conventions

- **Original by default.** Logic, layout, timing and colours match the original v1.1 exe; any improvement or new
  content is an opt-in switch (Preferences → Extras) and is recorded in `docs/deviations.md`.
- Behaviour is derived from the decompiled exe; docs and code comments cite functions as `FUN_xxxxxxxx` (v1.1
  addresses; `docs/v1.1.md` maps them to v1.0). Keep the relevant `docs/*.md` in sync when behaviour changes, and
  update `docs/status.md` for what works / is open.
- Reuse the install's original art at run time before drawing new art. Anything new that must ship (e.g. the F-35I
  in `tools/f35i/`) has to be tracked in the repo and be our own or redistributable.
- Per-aircraft behaviour is keyed by type code scattered across many tables; adding a plane means following
  `docs/adding-a-plane.md` (`iaf-convert plane-checklist <code>` lists every table).
