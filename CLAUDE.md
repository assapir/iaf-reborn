# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Two flight sims on one engine: a native re-implementation of Jane's IAF (1998) (`iaf-reborn/`) and Modern IAF
(`modern-iaf/`, a present-day Israeli Air Force sim on our own and openly licensed data). Rust crates (format
parsers, converters, flight model) plus Godot 4.7 projects that render and run the games, sharing `shared/` and
`crates/`. The 1998 game's data comes from the user's own ISO and is generated into the git-ignored `assets/`; the
repo must never contain original game data.

## Commands

Run from the repo root.

```sh
./setup                                                       # the setup wizard (docs/setup.md); re-run to add / redo
tools/setup-cli.sh [--patch v1.1.exe] "/path/to/Jane's IAF.iso"   # one-time: extract + convert everything into assets/
./iafjets [-- --mission 311]                                  # builds the iaf-godot extension (release) and starts the game
./mission-editor                                              # the mission editor (docs/mission-editor.md), same build as ./iafjets
./modern-iaf-setup                                               # Modern IAF's setup wizard (modern-iaf/docs/setup.md): its data into assets/
./start-modern-iaf [-- --mission 2012]                           # Modern IAF: the front end; --mission flies one mission, then its debrief
cargo test -q --workspace                                     # Rust tests (data/python3-dependent ones skip with a message)
cargo test -q -p iaf-flight --test validation <name>          # one Rust test
iaf-sim <terrain|db|missions|own|fm|airbases|scenery|textures|all|adopt|voices>   # one stamped setup step (target/release/iaf-sim)
tools/test.sh                                                 # everything: cargo tests, tests/godot + modern-iaf/tests headless, gdparse
cargo build --release -p iaf-godot                            # needed before Godot tests: game loads target/release/libiaf_godot.*
IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-reborn -s ../tests/godot/test_radar.gd   # one Godot test
IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf -s ../modern-iaf/tests/test_m0_boot.gd   # Modern IAF's M0 probe
tools/ghidra/fn.sh 5643a0 | --grep PATTERN                    # decompiled original exe function (assets/ghidra_v11/iafjets.c)
tools/worktree.sh <name>                                      # parallel worktree sharing assets/ via symlink
tools/doclint.py                                              # lint the docs (links, paths, § refs, tables)
tools/mission_sweep.sh OUT [ids…]                             # headless run of every playable mission, one log each
tools/guide_shots.sh [jet] && python3 -I tools/guide_pdf.py   # pilot guides' pictures (hidden window) and PDFs
python3 -I tools/flight_timeline.py <flight.jsonl> [--html f.html] # a recorded flight (blackbox) as a timeline + summary
python3 -I tools/manuals.py [f16i|f16d|f35i|game]             # Modern IAF's manuals as PDFs, with Typst (modern-iaf/docs/manuals.md §3)
```

- Windows (docs/windows.md): `.\setup.ps1`, `.\iafjets.ps1 [--mission 311]`, `.\mission-editor.ps1`, `.\start-modern-iaf.ps1`, `.\modern-iaf-setup.ps1`,
  `tools\windows\setup-cli.ps1` (iaf-setup's options); no bash, so `tools/*.sh` do not run. Keep the clone LF
  (`git config core.autocrlf false`; gdformat writes CRLF there) and the .ps1 files ASCII.
- Run every scripted Godot test or capture with `IAF_DEFAULT_SETTINGS=1`. This keeps the user's `settings.cfg`
  untouched (never read, never written).
- Pass `--log-file <a temp path>` to the same runs. This keeps the user's own game logs from being rotated away.
  `tools/test.sh`, `guide_shots.sh` and `mission_sweep.sh` already do both; the project keeps 30 logs as a safety net.
- A Godot test passes only if it prints `RESULT PASS` and prints zero `SCRIPT ERROR` lines.
- Godot tests need the converted assets, so they run locally only (no hosted CI).
- On a fresh clone Godot's import folder (`.godot` in `iaf-reborn/`, `modern-iaf/`) is missing. Run `godot --headless --path iaf-reborn --import` (and
  `--path modern-iaf`) once, or the extension won't load (`./iafjets` and `./start-modern-iaf` do this for you).
- `tests/godot/_*_shot.gd` are real-render screenshot helpers (usage in each header). `tools/test.sh` skips them.
- Run every real-render Godot process (screenshots, benches) through `tools/godot_window.sh VAR=value … -- <godot args>`:
  on macOS it renders as a hidden app that never takes the user's focus. Plain `godot` without `--headless` opens a
  window over the user's work.

## How work is run

### Roles

- An orchestrator session plans, briefs and relays; it writes no repo code. Agents do the work, each in its own
  worktree (`tools/worktree.sh <name>`), and report once, at the end, in a short report.
- Opus-class agents design, build and review; a smaller model does mechanical chores (page updates, shared builds,
  setup steps).
- A job is retired and re-briefed with a hand-over when its context grows large. A brief quotes the user's words with
  the date.
- Every merge to main has: a review with a formal `VERDICT` line (MERGE / FIX), the findings fixed, the branch
  rebased on main, one squash commit, CI green, and the worktree and branch removed (local and remote).

### What may merge without asking

- Open bugs come before look and design work.
- A change the user ordered directly, and a fix that restores an approved state, merge after review.
- Any other visible change (a new look, layout or text size) waits on its own
  branch with before / after pictures until the user says yes (the approvals page).
- Finish with no known gaps: a job closes every fault it knows about in the thing it was asked to build. An item stays
  open only when truly blocked, with the concrete reason written down. A "still different" list is not a result.
- Scope is the user's own words. Extra rows an inventory adds are listed as
  "not started", not built.
- A cockpit or model look is matched to its reference picture from the same camera (side by side and overlaid), not
  to a list of items.

### Building on the shared laptop

- Agents do not run cargo on the Linux laptop. Rust is built and unit-tested on the build Mac over ssh (headless only:
  cargo and headless Godot, no windows or renders, an own clone, nothing of the user's touched). When the Mac is
  unreachable, an agent may run cargo on the laptop gently: one `nice` cargo at a time, narrow packages, its own small
  target folder deleted after use, never under 5 GB free disk.
- The laptop has one shared game library and tools build, `target/` of the main checkout. Only the orchestrator's
  build chore writes it. An agent commits, pushes and sends `READY_TO_BUILD <hash>` naming the stamped setup steps it
  needs; it aims for one round.
- The build chore checks the free disk and that no cargo runs, and that the branch contains `origin/main`. From the
  branch's worktree it runs `touch crates/iaf-setup/build.rs && find crates -name lib.rs -exec touch {} +
  && CARGO_TARGET_DIR=<main checkout>/target nice cargo build --release -q -p iaf-godot -p iaf-tools -p iaf-setup
  --bins --lib` (the `touch` keeps the stamps' fingerprint honest), runs the named steps with the built `iaf-sim`,
  and tells the agent.
- Only one Rust branch can use the shared library at a time: a second one waits, rebases after the first merges, and
  asks again. Work that needs no Rust fills the second slot.
- After a Rust merge the agent's report says `REBUILD FROM MAIN` when main's Rust differs from the last built hash.

### Assets and downloads

- Assets are built only through the stamped setup pipeline (`iaf-sim <step>`, the wizards). An unstamped build makes
  the wizard redo and re-download everything.
- A code change never triggers a download: sources stay under `assets/source` by file name; only compile steps
  re-run. New converter sources and data files are registered for the stamps (`crates/iaf-setup/build.rs` `SOURCES`,
  the step lists in `stamp.rs`).
- Nothing is downloaded without the user's word. A model or sound already on disk from a credited source may be used;
  otherwise the job stops and names the file, its licence and size.
- The voices step needs `IAF_KOKORO_PYTHON=<the voice venv>/bin/python` and runs offline with `HF_HUB_OFFLINE=1`
  (`modern-iaf/docs/sound.md`).

### Real renders and tests

- Real renders run one at a time under `flock ~/.cache/iaf-gpu-bench.lock`. A locked desktop stops the hidden window
  from drawing, so a black or hanging render is reported as owed, not retried in a loop.
- `IAF_DEFAULT_SETTINGS=1` is also set for `gdparse` runs.
- Run only the tests a diff touches, once; the full suite slows the user's machine.
- A test or picture that fails inside unrelated script code with an argument-count or missing-method error means the
  shared library was built from another branch.

### Modern IAF rules

- Game logic is in Rust; Godot wires and renders. Modern IAF reuses the original game's logic through `shared/` and
  the crates, never its 1998 data formats or looks; the original game's behaviour does not change.
- One jet's avionics are finished before the next; a second jet of the same family is a data difference, not a second
  implementation.
- Every cockpit function has a keyboard key or a clickable control in the 3D cockpit: the keyboard is the first-class
  input, a joystick mapping is optional and never the only way. New keys go in the sim's key table and the controls
  doc, with no conflicts.
- A load, setting or preset that cannot be used in flight is refused where it is made, not only in flight; the screen
  says why in one line. Such a dependency is data on the records, with one rule in Rust that every screen and the
  flight call. It applies everywhere the thing can be stored or started from: the screen, a saved preset (old ones
  too), a mission's default.
- Every screen has Hebrew and English. Hebrew is gender-neutral and formal.
- Before writing a Hebrew term for an aviation or weapon-system thing, search for the term Hebrew speakers in the field
  use (the air force's own publications, Israeli aviation press) and use that, a transliterated loanword included
  where that is what is used; do not coin a translation. One thing has one term across the whole front end.
- A notice on a screen is one short line in the screen's normal text size: it says what is wrong and what to do.
- The plan and its decisions live in `modern-iaf/docs/avionics-plan.md` and `modern-iaf/docs/research/pods.md`; a
  slice updates its rows, `docs/status.md` and the controls doc in the same change. Pilot guides for Modern IAF are
  planned with the user before any is written.

### Research and limits

- A request to an outside site carries no name or email, also not in a User-Agent. A site that refuses automated
  access is left alone and another source is used; evidence taken from a search engine's quote of such a page is
  marked as second-hand.
- Parked, not to be researched, modelled or tuned: real missile performance (motors, range envelopes, guidance and
  seeker behaviour, fuzing), countermeasure effectiveness, electronic attack. Cockpit procedure for these systems
  (switches, pages, counts) is in scope.

## Architecture

- `crates/iaf-formats` — parsers for the original file formats (ISO9660, PTT terrain, terraintype.dat, X models, ESA, EMF, menu, RTF,
  LZO, PE resources, the CD launcher's .rgn, the Mission Creator's .mcr…). Format notes in `docs/formats/`.
- `crates/iaf-tools` — the converters, as CLIs and as the library the setup pipeline calls: `iaf-extract` (ISO → `assets/install`), `iaf-patch` (v1.1 RTPatch
  without Windows), `iaf-convert` (cockpits, menus, keys, missions, aircraft → `assets/converted`, plus
  `plane-describe` / `plane-checklist`), `iaf-terrain`, `iaf-imagery`, `iaf-import-pack`, `iaf-mission-report`;
  the library also builds the Mission Creator's mission 0x29a (`mission_creator.rs`) and holds the mission editor's
  edits and checks (`mission_edit.rs`, docs/mission-editor.md).
  The setup-path bins are argument parsers over library modules (`convert`, `extract`, `patch`, `pack`, `terrain`,
  `imagery_run`): each entry point takes a `progress::Progress` and a cancel flag.
- `crates/iaf-setup` — the setup pipeline in-process (docs/setup.md): `plan` (the steps with their
  dependencies), `run` (a dependency graph, stamps skip unchanged steps), the input checks; CLI `iaf-setup` for testing.
- `crates/iaf-flight` — the original flight model and AI autopilot, pure Rust, re-implemented from
  `docs/flight-model.md` / `docs/autopilot.md`; also the engine spool (`spool.rs`) and World scale Real's base move
  (`base_move.rs`, docs/world-scale.md). Tests in `crates/iaf-flight/tests/` (validation against the envelope
  reference `tools/envelope_ref.py`).
- `crates/iaf-avionics` — the player's avionics, pure Rust: the radar (`radar.rs`), the gun / rounds / LCOS
  (`gun.rs`), the homing / guided missiles (`missile.rs`, `guided.rs`), the IR seeker and MRM sight (`sight.rs`),
  the radio controller (`fctrl.rs`: AWACS contact calls, kill / airborne / landed reports), the stores (`stores.rs`), bombs / CCIP (`bombs.rs`), the master / HUD modes (`master.rs`), the RWR (`rwr.rs`), I-mode (`imode.rs`), the terrain height field (`heights.rs`),
  the EO (`eo.rs`) and HARM (`harm.rs`) sensors, the release rules (`release.rs`), the HUD's weapon values and range
  scale (`hud.rs`), the per-jet Real HUD symbology (`real_hud/`) and the F-16's ground-avoidance cues (`gaaf.rs`). Modern IAF's F-16 systems (ours): the ICP / DED (`ufc.rs`), the MFD formats
  (`f16_mfd.rs`), the threat warning display and MAW (`ews.rs`), the countermeasures dispenser (`cmds.rs`), the AIFF
  interrogator (`aiff.rs`), the data link's picture (`datalink.rs`), GPS / INS guided bombs (`gps.rs`), the real Betty
  calls (`betty.rs`); the world's data: the terrain frame (`frame.rs`), OpenStreetMap roads (`roads.rs`), buildings and
  trees (`scenery.rs`), city lights at night (`city_lights.rs`). Their GDScript fronts in `shared/weapons/` (`radar.gd`,
  `gun_rounds.gd`, `missile.gd`, `guided.gd`, `ir_seeker.gd`, `stores.gd`, `bombs.gd`, `rwr.gd`,
  `eo_sensor.gd`, `harm_sensor.gd`; the modes in `player_weapons.gd`) keep the old interface. Their fields read the
  Iaf object's state through getters; `radar.gd`, `rwr.gd` and `gun_rounds.gd` copy it into plain fields after each
  call (`_sync`), and `stores.gd` its counts into the station records. `bombs.gd` keeps only what adds the wind (`launch`,
  `predict_impact`); the rest of `IafBomb`, and `IafMrmSight`, callers call through `ClassDB.class_call_static`.
- `crates/iaf-godot` — gdext bridge: `IafFlight` (`flight.rs`), `IafRadar` (`radar.rs`), `IafRounds` / `IafLcos`
  (`gun.rs`), `IafMissile` / `IafGuided` (`missile.rs`), `IafSeeker` / `IafMrmSight` (`sight.rs`), `IafStores`
  (`stores.rs`), `IafBomb` / `IafModes` (`bombs.rs`), `IafRwr` (`rwr.rs`), `IafEo` / `IafHarm` (`sensors.rs`), `IafRelease` / `IafRipple` (`release.rs`), `IafRealHud` (`real_hud.rs`), `IafFlightController` (`fctrl.rs`, the AWACS and radio reports), `IafSetup` (`setup.rs`, the setup wizard's pipeline), `IafSurface` (`surface.rs`, terraintype.dat rasterised for the terrain shader), `IafEmf` (`emf.rs`, the TSD map's polygon fill), `IafHeights` (`heights.rs`), `IafImode` (`imode.rs`), `IafBases` (`bases.rs`, the base move), `IafMcr` (`mcr.rs`, the Mission Creator), `IafMissionEdit` (`mission_edit.rs`, the mission editor), `IafAutorun` (`autorun.rs`, the CD launcher), and for Modern IAF `IafUfc`, `IafF16Mfd`, `IafEws`, `IafAirframe` (the aircraft definitions), `IafBriefing` (the briefing map), `IafCockpitSound`, `IafDevices` (joystick axes store), `IafPilotLog` (records store), `IafTraining` (the training scorer), `IafScenery`, `IafRoads`, `IafCityLights`, `IafHid` (joystick axis count);
  `world.rs` converts the weapons' world frame. Handles the frame conversion: FM is ENU (east, north, up); Godot is
  X east, Y up, Z south. Loaded via `iaf-reborn/iaf.gdextension`.
- `iaf-reborn/` — the original game's Godot project (entry page `iaf-reborn/README.md`): `menu` (the front end, TSD, pilots), `setup` (the wizard), `editor`
  (the mission editor, `./mission-editor`), `viewer`, `project.godot`, `iaf.gdextension`. Main scene
  `menu/front_end.tscn`; autoloads `Settings` (`res://shared/settings.gd`) and `Joystick`. Flight scene is
  `res://shared/terrain/terrain_view.tscn`.
- `shared/` — the engine GDScript, scenes and shaders every Godot project uses: `aircraft`, `ai`, `audio`, `cockpit`,
  `controls`, `extra`, `mission`, `terrain`, `util`, `weapons` (radar, RWR, stores), `settings.gd` (the `Settings`
  base class), `default_bus_layout.tres`. A project reaches it through one committed symlink, `iaf-reborn/shared ->
  ../shared` and `modern-iaf/shared -> ../shared` (Windows: a junction, `tools/windows/links.ps1`), so every shared file is `res://shared/...`. A shared
  script reaches the front end only through `Settings` (`front_end_scene()`, `front_end_overlay()`).
  The split was made in A0 (`modern-iaf/docs/plan.md`). Assets are read at run time from
  `res://../assets/converted/...` and `Settings.install_dir()` (`assets/install`); the readers of the install's
  resource layout (flight model, sounds, weapons' motion, iaf.ibx, terraintype.dat) take `Settings.own_dir()` (the
  install in the original game), the key table `Settings.keys_file()`.
- `modern-iaf/` — Modern IAF, the modern sim on own data only (`modern-iaf/README.md`): its Godot project with
  autoload `Settings = res://sim_settings.gd` (`install_dir()` a path that does not exist, `own_dir()` =
  `assets/converted/own`, the 1998-only switches fixed), `data/` (authored data, compiled by `iaf-sim`), `tests/`,
  `docs/`.
- `tests/godot/` — headless tests extending `tests/godot/base.gd` (`check()`, `frames()`, `start_mission(id)`);
  Modern IAF's in `modern-iaf/tests/` extend the same base and run with `--path modern-iaf`.

Rule of placement: game logic belongs in the Rust crates. Godot renders and wires.

## Conventions

- **Squash merges only** (the user, 2026-11-02). A branch or worktree lands on main as one commit with a real
  message: `git merge --squash <branch>` then `git commit`. Never a merge commit ("Merge branch …"); to bring main into
  a branch, rebase the branch instead of merging main into it.

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
- Per-aircraft behaviour of the 1998 jets is keyed by type code scattered across many tables (`iaf-convert
  plane-checklist <code>` lists every table). A modern jet (the Sufa, the Ra'am, the F-35I) is its aircraft definition
  `shared/extra/planes/<id>/airframe.json`, and adding one means writing that file (`docs/adding-a-plane.md` "Modern
  planes"). A new modern-jet check reads the definition (`Settings.airframe`), never a type code or a switch.
- Commit the .uid files Godot writes beside new scripts and shaders (`tools/check_uids.sh`).
- Rust is formatted with `cargo fmt --all` (rustfmt.toml: width 120, compact heuristics); run it before committing
  Rust changes.
- Rust passes `cargo clippy --workspace --all-targets` with no warnings; fix what it finds, also outside the files
  you changed. Never silence it: no `#[allow(clippy::…)]` (a long argument list becomes a struct or, for a `#[func]`,
  Godot types; an exe constant is written as its exact stored value).
- GDScript is formatted with gdtoolkit's `gdformat --line-length 120 <files>` (gdtoolkit 4.x: `pip install
  'gdtoolkit==4.*'` in a venv) and linted with `gdlint <files>` (config: `gdlintrc`); run both on the `.gd` files you
  changed before committing. Then parse-check every script (`godot --headless --path iaf-reborn -s ../tools/gdparse.gd
  --log-file <temp path>`, and the same with `--path modern-iaf` when `shared/` or `modern-iaf/` changed; the autoloads
  loaded; exit 1 on a failure): gdformat can split a multi-line lambda inside
  an array in a way Godot rejects (7d3c78e).
- Docs follow ISO 24495-1 plain language: relevant, findable, understandable, usable. Describe what a thing is or
  does, never what it isn't.
- Research facts from outside sources cite each source as a Markdown footnote (`[^name]` in the text, the source with
  its link at the end of the doc), not as `[S]` / `[R]` tags. Say "inferred" for our own reasoning and "open" where
  no source was found (example: `docs/real-betty.md`).
