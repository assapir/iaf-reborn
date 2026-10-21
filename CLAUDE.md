# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native re-implementation of the engine for Jane's IAF (1998): Rust crates (format parsers, converters, flight
model) plus a Godot 4.7 project that renders and runs the game. All game data comes from the user's own ISO and is
generated into the git-ignored `assets/`; the repo must never contain original game data.

## Commands

Run from the repo root.

```sh
./setup                                                       # the setup wizard (docs/setup.md); re-run to add / redo
tools/setup-cli.sh [--patch v1.1.exe] "/path/to/Jane's IAF.iso"   # one-time: extract + convert everything into assets/
./iafjets [-- --mission 311]                                  # builds the iaf-godot extension (release) and starts the game
cargo test -q --workspace                                     # Rust tests (data/python3-dependent ones skip with a message)
cargo test -q -p iaf-flight --test validation <name>          # one Rust test
tools/test.sh                                                 # everything: cargo tests + every tests/godot/test_*.gd headless
cargo build --release -p iaf-godot                            # needed before Godot tests: game loads target/release/libiaf_godot.*
IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path game -s ../tests/godot/test_radar.gd   # one Godot test
tools/ghidra/fn.sh 5643a0 | --grep PATTERN                    # decompiled original exe function (assets/ghidra_v11/iafjets.c)
tools/worktree.sh <name>                                      # parallel worktree sharing assets/ via symlink
tools/doclint.py                                              # lint the docs (links, paths, § refs, tables)
tools/mission_sweep.sh OUT [ids…]                             # headless run of every playable mission, one log each
tools/guide_shots.sh [jet] && python3 -I tools/guide_pdf.py   # pilot guides' pictures (hidden window) and PDFs
python3 -I tools/flight_timeline.py <flight.jsonl> [--html f.html] # a recorded flight (blackbox) as a timeline + summary
```

- Run every scripted Godot test or capture with `IAF_DEFAULT_SETTINGS=1`. This keeps the user's `settings.cfg`
  untouched (never read, never written).
- Pass `--log-file <a temp path>` to the same runs. This keeps the user's own game logs from being rotated away.
  `tools/test.sh`, `guide_shots.sh` and `mission_sweep.sh` already do both; the project keeps 30 logs as a safety net.
- A Godot test passes only if it prints `RESULT PASS` and prints zero `SCRIPT ERROR` lines.
- Godot tests need the converted assets, so they run locally only (no hosted CI).
- On a fresh clone Godot's import folder (`.godot` in `game/`) is missing. Run `godot --headless --path game --import` once, or the extension won't
  load (`./iafjets` does this for you).
- `tests/godot/_*_shot.gd` are real-render screenshot helpers (usage in each header). `tools/test.sh` skips them.
- Run every real-render Godot process (screenshots, benches) through `tools/godot_window.sh VAR=value … -- <godot args>`:
  on macOS it renders as a hidden app that never takes the user's focus. Plain `godot` without `--headless` opens a
  window over the user's work.

## Architecture

- `crates/iaf-formats` — parsers for the original file formats (ISO9660, PTT terrain, terraintype.dat, X models, ESA, EMF, menu, RTF,
  LZO, PE resources, the CD launcher's .rgn, the Mission Creator's .mcr…). Format notes in `docs/formats/`.
- `crates/iaf-tools` — CLIs used by `tools/setup-cli.sh`: `iaf-extract` (ISO → `assets/install`), `iaf-patch` (v1.1 RTPatch
  without Windows), `iaf-convert` (cockpits, menus, keys, missions, aircraft → `assets/converted`, plus
  `plane-describe` / `plane-checklist`), `iaf-terrain`, `iaf-imagery`, `iaf-import-pack`, `iaf-mission-report`;
  the library also builds the Mission Creator's mission 0x29a (`mission_creator.rs`).
  The setup-path bins are argument parsers over library modules (`convert`, `extract`, `patch`, `pack`, `terrain`,
  `imagery_run`): each entry point takes a `progress::Progress` and a cancel flag.
- `crates/iaf-setup` — the setup pipeline in-process (docs/setup.md): `plan` (setup-cli.sh's steps with their
  dependencies), `run` (a dependency graph, stamps skip unchanged steps), the input checks; CLI `iaf-setup` for testing.
- `crates/iaf-flight` — the original flight model and AI autopilot, pure Rust, re-implemented from
  `docs/flight-model.md` / `docs/autopilot.md`; also the engine spool (`spool.rs`) and World scale Real's base move
  (`base_move.rs`, docs/world-scale.md). Tests in `crates/iaf-flight/tests/` (validation against the envelope
  reference `tools/envelope_ref.py`).
- `crates/iaf-avionics` — the player's avionics, pure Rust: the radar (`radar.rs`), the gun / rounds / LCOS
  (`gun.rs`), the homing / guided missiles (`missile.rs`, `guided.rs`), the IR seeker and MRM sight (`sight.rs`),
  the radio controller (`fctrl.rs`: AWACS contact calls, kill / airborne / landed reports), the stores (`stores.rs`), bombs / CCIP (`bombs.rs`), the master / HUD modes (`master.rs`), the RWR (`rwr.rs`), I-mode (`imode.rs`), the terrain height field (`heights.rs`),
  the EO (`eo.rs`) and HARM (`harm.rs`) sensors, the release rules (`release.rs`), the HUD's weapon values and range
  scale (`hud.rs`), the per-jet Real HUD symbology (`real_hud/`) and the F-16's ground-avoidance cues (`gaaf.rs`). Their GDScript fronts in `game/weapons/` (`radar.gd`,
  `gun_rounds.gd`, `missile.gd`, `guided.gd`, `ir_seeker.gd`, `mrm_sight.gd`, `stores.gd`, `bombs.gd`, `rwr.gd`,
  `eo_sensor.gd`, `harm_sensor.gd`; the modes in `player_weapons.gd`) keep the old interface and mirror the state.
- `crates/iaf-godot` — gdext bridge: `IafFlight` (`flight.rs`), `IafRadar` (`radar.rs`), `IafRounds` / `IafLcos`
  (`gun.rs`), `IafMissile` / `IafGuided` (`missile.rs`), `IafSeeker` / `IafMrmSight` (`sight.rs`), `IafStores`
  (`stores.rs`), `IafBomb` / `IafModes` (`bombs.rs`), `IafRwr` (`rwr.rs`), `IafEo` / `IafHarm` (`sensors.rs`), `IafRelease` / `IafRipple` (`release.rs`), `IafRealHud` (`real_hud.rs`), `IafFlightController` (`fctrl.rs`, the AWACS and radio reports), `IafSetup` (`setup.rs`, the setup wizard's pipeline), `IafSurface` (`surface.rs`, terraintype.dat rasterised for the terrain shader), `IafHeights` (`heights.rs`), `IafImode` (`imode.rs`), `IafBases` (`bases.rs`, the base move), `IafMcr` (`mcr.rs`, the Mission Creator), `IafAutorun` (`autorun.rs`, the CD launcher);
  `world.rs` converts the weapons' world frame. Handles the frame conversion: FM is ENU (east, north, up); Godot is
  X east, Y up, Z south. Loaded via `game/iaf.gdextension`.
- `game/` — Godot project. Main scene `menu/front_end.tscn`; autoloads `Settings` (`settings.gd`) and `Joystick`.
  Flight scene is `terrain/terrain_view.tscn`. Subdirs by system: `aircraft`, `ai`, `cockpit`, `weapons` (radar, RWR,
  stores), `mission`, `menu`, `audio`, `controls`, `terrain`. Assets are read at run time from
  `res://../assets/converted/...` and `assets/install`.
- `tests/godot/` — headless tests extending `tests/godot/base.gd` (`check()`, `frames()`, `start_mission(id)`).

Rule of placement: game logic belongs in the Rust crates. Godot renders and wires.

## Conventions

- **Original by default.** Logic, layout, timing and colours match the original v1.1 exe. Any improvement or new
  content is an opt-in switch (Preferences → Extras) and is recorded in `docs/deviations.md`.
- The original manual is a reference for what the game intends; the exe wins where they differ. The CDs hold no
  manual file. English (typeset PDF, 124 pages, text searchable): `assets/manual_en/iaf_manual_en.pdf`, merged from the
  chapter PDFs in the Internet Archive's replacementdocs mirror (`p31-replacementdocs`, `ReplacementDocs.zip/Microsoft -
  Windows/Janes - Israeli Air Force (Complete Documentation) [585]/`). Hebrew (72 low-res scans):
  `assets/manual_he/<page>.jpg` from `https://www.old-games.org/guides/pages/iaf/<1..72>.jpg`.
- Derive behaviour from the decompiled exe. Docs and code comments cite functions as `FUN_xxxxxxxx` (v1.1
  addresses; `docs/v1.1.md` maps them to v1.0).
- When behaviour changes, update the relevant `docs/*.md` in the same change, and update `docs/status.md` for what
  works / is open.
- Reuse the install's original art at run time before drawing new art. Anything new that must ship (e.g. the F-35I
  in `tools/f35i/`) has to be tracked in the repo and be our own or redistributable.
- Per-aircraft behaviour is keyed by type code scattered across many tables; adding a plane means following
  `docs/adding-a-plane.md` (`iaf-convert plane-checklist <code>` lists every table).
- Rust is formatted with `cargo fmt --all` (rustfmt.toml: width 120, compact heuristics); run it before committing
  Rust changes.
- Rust passes `cargo clippy --workspace --all-targets` with no warnings; fix what it finds, also outside the files
  you changed. Never silence it: no `#[allow(clippy::…)]` (a long argument list becomes a struct or, for a `#[func]`,
  Godot types; an exe constant is written as its exact stored value).
- GDScript is formatted with gdtoolkit's `gdformat --line-length 120 <files>` (gdtoolkit 4.x: `pip install
  'gdtoolkit==4.*'` in a venv) and linted with `gdlint <files>` (config: `gdlintrc`); run both on the `.gd` files you
  changed before committing. Then parse-check every script (`godot --headless --path game -s ../tools/gdparse.gd
  --log-file <temp path>`, the autoloads loaded; exit 1 on a failure): gdformat can split a multi-line lambda inside
  an array in a way Godot rejects (7d3c78e).
- Docs follow ISO 24495-1 plain language: relevant, findable, understandable, usable. Describe what a thing is or
  does, never what it isn't.
- Research facts from outside sources cite each source as a Markdown footnote (`[^name]` in the text, the source with
  its link at the end of the doc), not as `[S]` / `[R]` tags. Say "inferred" for our own reasoning and "open" where
  no source was found (example: `docs/real-betty.md`).
