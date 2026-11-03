# IAF 2026: the plan

**Terms:** AB = afterburner; BiDi = bidirectional text; CC0 / CC BY = open licences for free reuse (public domain /
with credit); DEM = digital elevation model (terrain heights); FM = flight model; 6-DoF = six degrees of freedom; MFD =
multi-function display; OSM = OpenStreetMap; PCD = panoramic cockpit display (the F-35I's screen); RTL = right to
left; TTS = text to speech; MVP = the first playable version; "leash" = the done rules below.

2 November 2026. IAF 2026 is a modern-day Israeli Air Force sim that uses only our own or openly licensed data. It is
built on this repo's engine and runs beside the original game. An inventory of 2026-11-02 found that nothing runs
without the original ISO yet: every own piece so far (Sufa, F-15I, F-35I, own imagery, 3D cockpits, Real HUDs, modern
weapons) is an overlay on a 1998 type code, record or height field, with a silent fallback to the original data. This
document holds the decisions, the MVP, the architecture, the work items and the checks. Every later decision is added
here, dated.

## Decisions (the user, 2026-11-02)
| topic | decision |
|---|---|
| name | **IAF 2026**: folder `iaf-2026/`, window title and wizard "IAF 2026" |
| launchers | all at the repo root, beside today's `./iafjets`, `./setup`, `./mission-editor`: `./iaf2026` and `./iaf2026-setup` (+ `.ps1` twins); same build step (`cargo build --release -p iaf-godot`). Named without the dash because a file cannot share the `iaf-2026/` folder's name (2026-11-02) |
| assets | **one `assets/` root, fully mixed**: the sim's built data lives in the same `converted/` tree beside the original's under its own names (e.g. `converted/terrain/israel/`, `converted/missions/iaf-2026/`, `converted/own/` for the mirrored `resource/` layout); the models, imagery, scenery, roads and textures already there are used by both; downloads shared in `assets/source/` and `assets/thirdparty/`. The sim never reads `assets/install/` |
| home | this repo, **three folders**: `shared/` (the engine GDScript, scenes, shaders, own models), `iaf-reborn/` (today's `game/`: the original game's front end, 2D cockpits, setup wizard, editor, viewer) and `iaf-2026/` (the sim); the Rust crates stay in `crates/` shared by both; no new repo |
| progress | a new artifact page **"IAF 2026 Progress"**: every item's pictures (the real-render shots, cockpit and external, all settings on) go there in the item's section before the item counts as done |
| jets | Sufa (Ramon), F-16D Barak (Ramat David), F-35I (Nevatim); F-15I (Hatzerim) when it has a 3D cockpit |
| cockpits | **3D only, no 2D cockpit at all**: no panel bitmaps, no pan strip, no cockpit-view model; the 3D cockpit with free head look is the only cockpit view. The per-jet "cockpit dir" below holds only the displays' data (MFD formats, RWR symbol set, TSD map, ADI texture) that the 3D screens render; the F-35I's 2D panel renders stay in `game/` for the original game |
| flight model | own 6-DoF from NASA TP-1538, JSBSim F-16 as cross-check |
| era | 2026: modern threats and weapons only; a research doc decides the set; all sim research in its own folder |
| MVP gameplay | training missions: 1 "starting the plane", 2 "take off, talking to the tower"; later 3 go-around and landing, 4 navigation… |
| start-up | MVP: one "start engine" command with real timings; after MVP: the real checklist by keys with a checklist card |
| radio | radio menu (request start-up / taxi / takeoff), tower by Piper TTS with a radio filter |
| scoring | pass / fail with a debrief page; a pilot log if easy (copy the game's own pilot JSON) |
| front end | plan the full set, build only what the MVP uses, the rest visible but disabled |
| setup | a **new** GUI wizard (no Jane's mentions, its own options), reusing the `iaf-setup` pipeline engine |
| terrain | Israel at full detail (Survey of Israel 2 m), neighbours coarse (Sentinel-2); open DEM heights |
| airbases | Ramon, Hatzerim, Nevatim, Ramat David, real layouts from OSM at real coordinates |
| sound | core set (engine, AB, gear, gun, missiles, explosions) from CC0 / CC BY + TTS voices (Betty, tower, AWACS) |
| conditions | MVP: day, clear, calm; night / weather later |
| scale | **1:1 from day one**: real sizes, real distances, every base at its real place (the World scale Real code becomes the only scale; no 1998 scale exists in the sim) |
| data | **real airplane data only**: every figure sourced (manuals, NASA, published performance), "inferred" labelled, nothing from the exe or the ISO |
| physics | **real by default**; a toggle exists only where we have an own alternative (e.g. an easy-flight aid of our own, unlimited fuel, no damage). **No off switch for anything that replaced original data or logic** (6-DoF, real weapon data, Real HUD, real MFDs, spool, 3D cockpit, 1:1): "off" would mean the 1998 version, which does not exist in the sim |
| options | **all the toggles the game gained** carry over where relevant: Graphics → MORE (clouds Volumetric, rain, night vision, shadows, water, scenery, roads, ground textures, city lights, upscaling / FSR 2 / MetalFX), Physics, Devices, Extras that still apply; the 1998-only ones (Jet versions, original cockpit, world scale) do not exist |
| platforms | Linux, macOS, Windows from day one |
| languages | **Hebrew and English from day one, RTL / BiDi done right**: every screen of the sim (front end, wizard, radio menu, debrief, subtitles, checklist card, preferences) has both; Godot's TextServer Advanced for BiDi shaping, mirrored layouts in Hebrew, an OFL font with Hebrew glyphs (e.g. Noto Sans Hebrew), strings in one table per language as `game/menu/strings_he.json` does today; the pilot guides in both languages |
| done | the leash (memory `leash-other-sessions`): code + tests + docs + guide text and pictures + the item's pictures on the "IAF 2026 Progress" page + credits + the session's own quality checks (code review pass, screenshot critique against the real reference, one real run) + queue line rewritten |

## MVP: what "done" means
`./iaf2026` (repo root) starts from the shared `assets/` root, reads nothing under `assets/install/` and no
file converted from the ISO, on all three platforms, and:
1. The wizard has built the data: DEM, imagery, four airbases, models, sounds, voices; progress and attributions shown.
2. The front end offers the three jets, each with its home base, and the two training missions; the other screens
   are there but disabled.
3. Mission 1 (start): the jet sits parked at its base, cold; the player starts the engine (one command, real
   timings), the 3D cockpit comes alive (lamps, gauges, MFDs / PCD, Real HUD); pass when the engine is at idle
   with the avionics up.
4. Mission 2 (take off): the radio menu asks for start-up, taxi and takeoff; the tower answers by TTS; the player
   taxis on the real taxiways and takes off from the real runway; pass when airborne with gear up on the runway
   heading; a debrief page with the numbers; the pilot log updated.
5. The probe `iaf-2026/tests/test_mvp.gd` does 2–4 headless for every jet and prints `RESULT PASS`, and passes
   again with `IAF_ASSETS_DIR` pointing at a temporary root that holds only the sim's own files (the proof that
   nothing from the ISO is read).
6. Every data file the sim reads is ours or openly licensed and credited; `docs/credits.md`, the wizard's
   Attributions page and the credits roll agree.
7. Every screen reads right in Hebrew (RTL layout, BiDi text with mixed numbers and Latin names, Hebrew font)
   and in English; the language is a preference and the probe runs the front end in both.
8. The world is 1:1 (true-size jets, real distances, each base at its real coordinates), every aircraft figure is
   sourced real data, the realism options are on by default with an off switch each, and the game's Graphics /
   Physics / Devices toggles that still apply are in Preferences.

## Architecture (from the design agent, revised to the three folders)
- **Three folders, one symlink each.** Godot has one `res://` root per project, so `shared/` cannot be a second
  root: each project carries one link, `iaf-reborn/shared -> ../shared` and `iaf-2026/shared -> ../shared` (one
  directory junction each on Windows, `tools/windows/links.ps1`), and every shared script lives at
  `res://shared/...`. What moves to `shared/`: `aircraft ai audio cockpit controls extra mission terrain util
  weapons`, the shaders, `settings.gd` as the base class, `default_bus_layout.tres`. What stays in `iaf-reborn/`:
  `menu` (the original front end, TSD, pilots), `setup`, `editor`, `viewer`, `project.godot`, `iaf.gdextension`
  (its `res://../target/release/libiaf_godot.*` paths resolve the same from both projects; one
  `cargo build --release -p iaf-godot` serves both). Couplings to cut first (measured: 6 references in 4 scripts):
  `cockpit.gd`, `mission_runtime.gd`, `player_weapons.gd`, `terrain_view.gd` preload `res://menu/front_end`,
  `res://menu/tsd`, `res://menu/pilots`; the TSD and pilot-log pieces they need move to `shared/`, the front-end
  references become a `Settings` call. **The move is one mechanical commit** (a script rewrites every `res://`
  path, the `--path game` in 8 tool files and `game/` in 40 docs), done in a quiet window so the parallel sessions
  rebase once; the `game/` suite must be green before and after.
- **New in `iaf-2026/`:** `project.godot` (own `user://`, autoload `Settings="*res://sim_settings.gd"`, `Joystick`),
  `sim_settings.gd` (`extends "res://shared/settings.gd"`: `assets_dir()` stays the shared `res://../assets`;
  `install_dir()` returns a sentinel path that does not exist, so any shared reader that still reaches for original
  data fails loudly; the sim's own `resource/` layout lives at `converted/own/` and the readers that need it get the
  path from `Settings` (`own_dir()`); the
  1998-only switches (`cockpit_3d`, `models`, `world_scale`, the jet versions, flight / weapon data) are constants
  with no preferences row; the Graphics → MORE, Physics and Devices options that still apply get their own
  preferences page; `airframe_def(id)` merged with `res://data/planes/<id>.json`), `main.tscn` (front end),
  `setup/` (the wizard), `data/**` (authored data), `tests/**`, `docs/**` (all sim research and docs), a crate bin
  `iaf-sim` in `crates/iaf-tools/src/bin/` (the sim's setup steps, run by the wizard through `iaf-setup`'s graph).
- **The only behaviour change in the shared code for M0:** `Settings.install_dir()` (= `assets_dir()/install`) replacing the ~14
  `assets_dir().path_join("install/...")` sites (`terrain.gd:166,189`, `terrain_view.gd:837,1629,1777`,
  `mission_runtime.gd:1195`, `radio.gd:107,110`, `sound_table.gd:26`, `weapon_db.gd:22`, `player_aircraft.gd:109`,
  `front_end.gd:1232`, `tests/godot/base.gd`). In the original game `install_dir()` is `assets/install`; in the
  sim it is the sentinel and the same readers take `converted/own/`, which mirrors the original sub-layout
  (`own/resource/md/bd.ibx`, `own/resource/soundfiles/`, `own/resource/weaponsmotion/weapons.ibx`, `own/iaf.ibx`,
  `own/terraintype.dat`), so the Rust bridges (`IafFlight.start(install,…)`, `flight.rs:49`) need no change.
  Gating: a missing own file fails loudly (no fallback path exists in the sim's Settings); the probe turns the
  quiet readers (empty sound table, empty motion table, `{}` bdb, `IafSurface.load` false) into FAIL lines, and
  the temp-root run proves no ISO-derived file is read.
- **Own data, compiled by `iaf-sim`** into the shapes the shared readers already consume (zero reader changes):
  - units / weapons: readable `iaf-2026/data/db/{units,weapons}/<id>.json` → `converted/missions/sim.bdb.json`
    (hex-keyed as `default6_1.bdb.json`) + `converted/objects/objects.json`; weapon records keep the names
    `modern_weapons.gd` bases on (`"AIM-9M"`, `"MK-84"`) with own numbers from `real_weapons.gd` / real-weapons.md;
  - missions: readable `iaf-2026/data/missions/<id>.json` → `converted/missions/<id>.json` via the
    `iaf_tools::mission_edit` builders (`blank`, `add_entity`, `set_flight`, `set_route`); briefing on the sim's own screen;
  - terrain: `iaf-sim terrain` writes the theatre tree `terrain.rs:212` produces (`L6–L11` colour + 16-bit heights,
    `meta.json`) from Copernicus GLO-30 (GeoTIFF range reads as `imagery_run.rs:102–134`) and the existing
    Sentinel-2 / Survey of Israel layer code; UTM frame, `units_to_metres = 1` (1:1 is the only scale: the
    World scale Real base move `bases.rs` and the true-size models are the sim's normal path, the 1998 scale
    code is never reached);
  - airbases: `real_runways.csv` + OSM polygons → `airbases.json`, own `iaf.ibx` (tower / lineup / taxi), paved
    masks rasterised from OSM; `terraintype.dat` first as a one-node all-land tree, runway / water planes next;
  - cockpit displays (no 2D cockpit): own dirs `iaf-2026/data/planes/{f16i,f16d,f35i}/cockpit/` without `"Shared"`
    holding only what the 3D screens draw (own RWR glyph sheet, TSD map polygons from OSM in the EMF-JSON shape,
    own ADI); `cockpit.gd` must run with no panel bitmap and no pan strip when the 3D cockpit is on (today it
    loads the 2D panel first and draws the 3D one over it; E1 makes the panel optional, a `game/` change kept
    behind the existing `cockpit_3d` switch so the original game is unchanged); the F-key side / back views are
    the 3D cockpit's head look; an OFL HUD font through one `Settings.hud_font_path()` hook;
  - sounds: own `soundprop.trx` rows for the ~23 codes `flight_sounds.gd` plays + `radio.gd` templates, CC0 clips,
    TTS clips as `game/extra/tower_numbers` does; keys: own `keys.json` from docs/controls.md.
- **Flight model:** FM-0 (unblocks M0): own `bd.ibx` sections + envelope files generated by `tools/iaf-2026/fm0.py`
  from TP-1538 and the public figures in `data_set.rs` `REAL`, loaded by `iaf_flight::load` unchanged. Then the
  6-DoF: `crates/iaf-flight/src/sixdof/` (TP-1538 tables, quaternion body, F100 engine, gear) behind
  `enum Fm { Original, SixDof }` in `IafFlight`, same `State` / `Controls` / `ApView`; `Model=6dof` in the own section.
- **Avionics:** nothing replaced for the MVP; the modern rows (`radar.rs` F16I / F35I, `real_hud/`, `f16_mfd.rs`,
  `pcd`, `gps.rs`) are already ours. Later own modules sit behind the same `Iaf*` classes by the same enum dispatch.
- **Docs:** `iaf-2026/docs/` (README, threats.md, data-formats.md, flight-model.md, status.md); `tools/doclint.py`
  gets `iaf-2026/docs/**` and the path root.

## Phases and work items
| # | item | size | blocks on |
|---|---|---|---|
| A0 | **the split**: `game/` → `iaf-reborn/` + `shared/`, the 6 menu couplings cut, every `res://` path, tool and doc rewritten by a script, the suite green before and after; one squash commit in a quiet window | M | the two sessions' leashed items merged |
| A1 | `iaf-2026/` skeleton: the `shared` link + junction script, `sim_settings.gd`, `install_dir()` in `shared/settings.gd`, the root launchers `./iaf2026` and `./iaf2026-setup` (+ .ps1), `tools/test.sh` loop over `iaf-2026/tests`, `gdparse` on both, the M0 probe (NEEDS DATA today). **Done (2026-11-02, branch wt/iaf-2026-core):** as listed, plus `own_dir()` and `keys_file()` in `shared/settings.gd` and the sim's `set_jet()` (the F-16 switch from the unit's `"airframe"`); the two leftovers closed (2026-11-03, branch wt/iaf-2026-own): the player's flight-model type from the sim's table (`Settings.fm_section`), `IafBases` on `own_dir()`'s `iaf.ibx` (no bases until B2b); until E2 `./iaf2026` runs the M0 probe and until A3 `./iaf2026-setup` runs `iaf-sim all` ([status.md](status.md)) | M | A0 |
| A2 | `iaf-sim` bin: step graph on `iaf_setup::run`, `own` assembly, `db` and `missions` compilers. **Shipped (2026-11-02):** the readable formats ([data-formats.md](data-formats.md)), `iaf-sim db` (`sim.bdb.json`, the `"sim.bdb"` key of `objects.json`, own `weapons.ibx`, read by the game once A1's `install_dir()` hook lands; the jets' `"airframe"` key, from which A1 sets the F-16 switch) and `iaf-sim missions` (`converted/iaf-2026/missions/`, not `converted/missions/`: data-formats.md §7, accepted 2026-11-02), the Sufa / Barak / F-35I units, the gun / chaff / flare and the AIM-9M / MK-84 bases, the start-up and take-off missions at Ramon, Ramat David and Nevatim (Nevatim added to real_runways.csv), `test_sim_data.gd`. **Open:** the step graph and wizard wiring (after A1), red flights and threat units (after the user's yes, D2), the units' own models, real parking spots (B2) | M | A1 |
| A3 | **IAF 2026 setup wizard** (`iaf-2026/setup/`): new pages and options, no Jane's mentions, reuse the `IafSetup` bridge and progress / cancel pattern of `game/setup`; Attributions page; Hebrew and English | L | A2 |
| B1 | `iaf-sim terrain`: GLO-30 heights, Sentinel-2 + Survey of Israel colour, UTM frame. **Done (2026-11-03, branch wt/iaf-2026-terrain):** `iaf-sim terrain` writes `converted/terrain/israel/` (UTM 36N at 1:1, 347 × 511 km around the four bases, 2 m Survey / 8 m Sentinel-2 over Israel, 32 m beyond, GLO-30 heights at 64 m; [terrain.md](terrain.md)), `Settings.theatre_dir()` (the sim's theatre; `IAF_THEATRE` in the original game), the M0 probe's in-flight height check. **Open:** surface types (B2b), the other censored sites in the Survey photo | L | — |
| B2 | airbases Ramon, Hatzerim, Nevatim, Ramat David from OSM: layouts, masks, `iaf.ibx`, `terraintype.dat` runway / water planes; scenery step freed from original missions. **B2a data done (2026-11-02), compile waits for B1:** the four layouts in lat / lon (`iaf-2026/data/airbases/`, [airbases.md](airbases.md), `tools/iaf-2026/osm_airbase.py`), the parking spots and Nevatim's tower placed by eye (for approval), the 2026 squadrons. **B2b done (2026-11-03):** `iaf-sim airbases` compiles the four bases into the UTM theatre: `airbases.json` + paved masks from the OSM polygons (Detailed airbases draws them), an own `iaf.ibx` (tower, lineup, taxi paths on the OSM taxiway graph, parking spots), an own `terraintype.dat` (runways, the sea), the missions on the parking spots at the terrain's height; the M0 probe parks each jet ([airbases.md](airbases.md) §9). **Open:** the towers of Ramon, Hatzerim and Ramat David, inland water, the scenery step freed from the original missions | L | B1 |
| C1 | FM-0 data for Sufa, Barak, F-35I (and the F-15I row). **Done (branch wt/iaf-2026-fm0, 2026-11-02):** `tools/iaf-2026/fm0.py` writes the own `bd.ibx` (`[F-16]` the Barak and the base of the Sufa and F-35I, `[F-15]` the F-15I) and envelopes from NASA TP-1538 (thrust table fitted to the model's 2 × 2 table, bounded at zero at 20 km; joint idle / military fit) and the REAL rows' public figures, every key sourced ([flight-model.md](flight-model.md)); the F-16 REAL row's thrust written as an absolute value (same on the 1998 data); validation on the own data: weights, static thrust, fuel flow, stall, ceiling, roll, turn, climb in range or close; top speed at 40,000 ft OFF for every jet (Sufa, F-35I, F-15I low; Barak high); a real Sufa flight on the own data through `IAF_ASSETS_DIR`. **Open:** the sim's own install path (A1), the thrust table and the REAL rows' 1998-shaped fits (C2), `[Autopilot]`, LimitAlphaVisual and the 1998 handling gains (the user) | M | — |
| C2 | 6-DoF module + TP-1538 trim tests + validation rows. **Stage (a) done (branch wt/iaf-2026-sixdof, 2026-11-03):** `crates/iaf-flight/src/sixdof/`: all of TP-1538 Table III transcribed from the scan (every value checked against the page), appendix B's coefficient build-up, a quaternion rigid body with RK4 at ≤ 1/120 s; `tests/sixdof.rs`: the report's trims (66° at full nose up, the deep stall at 60°, static margin −4 %) and Stevens & Lewis's 502 ft/s trim within their tolerances ([flight-model.md](flight-model.md) §9). **Stage (b) done (branch wt/iaf-2026-sixdof-b, 2026-11-03):** TP-1538's engine model scaled per engine, the gear, the four jets' data, tests against the ratings, spool times, a take-off roll (26 % short of the F-16A SAC: open) and a stop (§9.7–9.10). **Stage (c) done (branch wt/iaf-2026-sixdof-c, 2026-11-03):** TP-1538's control system, `Fm { Original, SixDof }` behind `IafFlight` by `Model = 6dof` (the original game never reaches it, tested), fuel, Mach effects (inferred), Table V's roll times within 11 %, the validation rows on the 6-DoF, the frame cost, a real Sufa flight (§9.11–9.14). **Decided 2026-11-03 (the orchestrator):** the wave drag fit to each jet's published top speeds, labelled, pinned within 5 % (§9.15); the frame cost a budget, not parity: at most 20 µs per jet per frame on this laptop, enforced by `frame_cost_within_budget` (4.1 µs measured). **Open:** a sourced drag rise, the high-speed g onset, the take-off roll (−24 % against the SAC), flaps (§9.6) | XL | C1 |
| D1 | `iaf-2026/docs/threats.md`: the 2026 threat and weapon set, sources, model sources and licences | M | — |
| D2 | unit / weapon DB, own `weapons.ibx`, models for the DB's units (after the MVP: combat missions). **Drafts (branch wt/iaf-2026-threats, 2026-11-03), pending the user's decision:** threats.md §6's set as 12 unit and 10 weapon records in `iaf-2026/data/db/drafts/`, which `iaf-sim db` skips; approval = move the file and drop its `status` (data-formats.md §11); the compiler's SAM / AAA / radar classes and missile kinds ([threat-records.md](threat-records.md)). **Open:** the user's decision, the open figures, the damage scale for ground units, own flight-model rows for the MiG-29 and F-14A, the models, the missions | L | D1, A2 |
| E1 | own cockpit dirs, HUD font hook, keys, sound table + CC0 clips, TTS Betty / tower / AWACS with radio filter. **Sounds, voices and keys (E1b, branch wt/iaf-2026-sounds, 2026-11-02):** the CC0 sound set, the English Betty and tower voices through the radio filter, the radio phrase files and the own key table, compiled by `iaf-sim own` ([sound.md](sound.md)). **Open:** the Hebrew voice (the user decides on its licence), AWACS and wingman phrases, the run-time squelch, a human listening pass (the reader hooks: done in A1) | L | A1 |
| E2 | front end `main.tscn`: jets with home bases, mission list, preferences (the carried-over Graphics / Physics / Devices toggles), debrief page, pilot log; disabled screens; **Hebrew and English with RTL / BiDi layouts from the first screen** (the string table, the font, the mirrored containers, a screenshot pair per screen) | M | A1 |
| E3 | training mission 1 (start engine, real timings, cockpit alive) and 2 (radio menu, tower TTS, taxi, takeoff), pass / fail rules, debrief numbers. **E3a scoring done (2026-11-02):** the rules as data in the missions' `training`, the scorer `iaf-training score` over a flight recording with the debrief record in English and Hebrew ([training.md](training.md)). **E3b core done (2026-11-03, branch wt/iaf-2026-training2):** the jet parked cold, one start command running the real start sequence's timings on the 6-DoF (the F-16's JFS, the F-35I's IPP and 90 s self test; sources and the inferred steps in [training.md](training.md) §7) with the screens, the HUD and the lamps coming alive; the numbered radio menu (Ctrl+T, English and Hebrew labels) with the English TTS tower of every own base; the recorder's version 2 (`rpm`, `avionics`, `radio` events); `IafTraining` scoring at the mission's end, the debrief record in `user://debriefs/`, the pilot log; `./iaf2026 -- --mission <id>`; `test_mvp.gd` flies both missions for the Sufa, the Barak and the F-35I to a Pass. **Open:** the debrief page and the front end (E2), the Hebrew voice (the user), the pilot's own request voice, the starter's sound, the checklist card (after the MVP) | L | A2, B2, C1, E1, E2 |
| F | the probe `test_mvp.gd` passes for Sufa, Barak, F-35I on Linux / macOS / Windows | — | all above except C2, D2 |

## How the work runs
Every item is executed by a subagent or another session; the orchestrator writes the briefs, reviews the merges
against the "done" table, keeps the queue, the plan page and the progress page, and answers the sessions'
questions. Model per kind of work:
- **Opus subagents:** design and research docs (D1 threats, the data-format docs), code review of every merge
  (`/code-review` run by the orchestrator through an agent, not by hand), the screenshot critiques.
- **Sonnet subagents:** mechanical work with a clear spec: the A0 path rewrite script, the junction / launcher
  scripts, authoring data files from a decided source (DB JSON, sound table, keys), the probe tests, picture retakes.
- **Other sessions** (each in its own worktree, briefed with the done table): the large multi-day items (A1–A3,
  B1–B2, C1–C2, D2, E1–E3).
- **The orchestrator itself:** only the briefs, the reviews' verdicts, the merges' acceptance, the lists and the
  pages. If a step is "a handful of tool calls" it still goes to a subagent when it edits the repo.

Sessions (each in its own worktree via `tools/worktree.sh`), once their current leashed items pass:
- **sufa** (after the F-35I nose fix + pictures): E1 then E2 / E3 cockpit side.
- **mission-editor-fly-mode** (after the F-15I guide + its 4 decisions): A2 then E3 missions, later D2.
- **new session "iaf-2026-core"**: A1 → A3 (wizard).
- **new session "iaf-2026-terrain"**: B1 → B2.
- **new session "iaf-2026-fm"**: C1 → C2.
- **D1** research: an Opus subagent of the orchestrator (read-only research, a doc).
- **A0** the split: a Sonnet subagent in a worktree (script-driven move), reviewed by an Opus agent, merged by the orchestrator.
Start at once: B1, C1, D1 (they touch no `game/` script); A0 as soon as the two leashed items merge, then A1.
The orchestrator reviews each merge against the "done" table before the next assignment.

## Verification
- A1: `tools/test.sh` stays green after the `install_dir()` refactor; `IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 -s ../iaf-2026/tests/test_m0_boot.gd --log-file <tmp>` prints `NEEDS DATA` (no own data yet); clippy / gdlint / gdparse clean on both projects.
- B1 / B2: `iaf-sim terrain` on a 60 km box around Ramon; the probe's terrain checks; one real-render shot over each base via `tools/godot_window.sh`, compared with the satellite picture.
- C1: `IAF_INSTALL=assets/converted/own cargo test -p iaf-flight --test validation` within the public ranges for the three jets. C2: `tests/sixdof.rs` trim points from TP-1538; `_flight_bench.gd` no slower than FM-0.
- A3: the wizard from an `assets/` root without the sim's files to a flyable sim on the Linux laptop and the Mac, and again on a root that also holds the original game (nothing of the original's touched); Windows by the user.
- E3 / F: `test_mvp.gd` headless per jet; one real flight of each mission by the user; the debrief page's numbers checked against the flight recorder.
- Always: the `game/` suite green after every merge; `docs/deviations.md` untouched (nothing in `game/` behaves differently).
