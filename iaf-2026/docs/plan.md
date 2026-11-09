# Modern IAF: the plan

**Terms:** AB = afterburner; BiDi = bidirectional text; CC0 / CC BY = open licences for free reuse (public domain /
with credit); DEM = digital elevation model (terrain heights); FM = flight model; 6-DoF = six degrees of freedom; MFD =
multi-function display; OSM = OpenStreetMap; PCD = panoramic cockpit display (the F-35I's screen); RTL = right to
left; TTS = text to speech; MVP = the first playable version; "leash" = the done rules below.

2 November 2026. Modern IAF is a modern-day Israeli Air Force sim that uses only our own or openly licensed data. It is
built on this repo's engine and runs beside the original game. An inventory of 2026-11-02 found that nothing runs
without the original ISO yet: every own piece so far (Sufa, F-15I, F-35I, own imagery, 3D cockpits, Real HUDs, modern
weapons) is an overlay on a 1998 type code, record or height field, with a silent fallback to the original data. This
document holds the decisions, the MVP, the architecture, the work items and the checks. Every later decision is added
here, dated.

## Priorities (the user, 8 November 2026)

8 November 2026. The work runs in this order.

**P1. The sim plays well on the user's Mac.** His play test sets the order. The findings of the first Mac run
(8 November 2026), in order:

1. The airbase is visible and paved: runways, taxiways and aprons are drawn (the profile forced Detailed airbases off)
   and flagged as paved.
2. The pilot knows what to do: a mission card with the objective and the keys, key hints, a Keys screen, and
   "Mission complete" on screen before the debrief. **Keys and Joystick screens done (2026-11-08, branch
   wt/iaf-2026-devices):** Preferences → Devices → Keys and Joystick, the store and its merge in Rust
   ([front-end.md](front-end.md) §8).
3. A real first mission: the start-up checklist by keys, with its checklist card (F-16 and F-35I).
4. Honest scoring and a short debrief: a crash or leaving the pavement fails the mission; the debrief shows only the
   mission's goals.
5. Clean screens: Preferences as a list of sections, each its own screen, with no aids anywhere; the default view at
   the design eye point; the pause overlay laid out right on the first frame; F1–F4 only for views; the sim's own log
   lines and settings; the wizard's Done page and the README pointing at `./modern-iaf`; the roads probe ([F](#f-the-probe)) not tripping the
   gate.

Then the look, one step at a time, each with before / after pictures. The reference is the user's screenshot of Epic
Fury IAF: an F-16 3D cockpit over Shoham, with dense varied buildings and trees, olive / tan ground, a gradient sky
with soft clouds and horizon haze, a crisp stroke-font HUD, bright displays and town labels. The steps:

1. The city, roads and trees (the scenery branch, B3).
2. The ground's colours and textures ([B4](#b4-ground-look-parity)).
3. The sky, haze and exposure (a new item).
4. The HUD stroke font (A9, built: Hershey Simplex) and the display brightness ([E1a](#e1-cockpit-data-sounds-and-voices)).
5. Town labels over the view (built 2026-11-09: [../../docs/scenery.md](../../docs/scenery.md) §3.5).

**P2. Sound.** Betty like the real one; fluent American tower voices (Kokoro); audio as ogg.

**P3. The shared rows and the housekeeping.** The rows for reborn in [shared.md](shared.md); compact JSON; the F-15C
data ([D3](#d3-f-15c-baz-at-tel-nof)); the sqlite design ([storage.md](storage.md), 2026-11-09: compiled data stays JSON, the pilot log and debriefs move to SQLite with the E2 logic move; the user decides); CI ([ci.md](ci.md), 2026-11-09: research, no workflow change yet).

**P4. Combat.** The records and models of the approved threat set; the first strike mission.

Rules that hold:

- P1 comes before anything else.
- One merge at a time, each shown to the user.
- Nothing visible ships without the user's approval.
- Opus agents build and review.
- The orchestrator only reads reports, merges and keeps the list.

## Decisions (the user, 2026-11-02)
| topic | decision |
|---|---|
| name | **IAF 2026**: folder `iaf-2026/`, window title and wizard "IAF 2026" (renamed on 8 November 2026, below) |
| launchers | all at the repo root, beside today's `./iafjets`, `./setup`, `./mission-editor`: `./iaf2026` and `./iaf2026-setup` (+ `.ps1` twins); same build step (`cargo build --release -p iaf-godot`). Named without the dash because a file cannot share the `iaf-2026/` folder's name (2026-11-02). Renamed `./modern-iaf` and `./modern-iaf-setup` on 8 November 2026 (below) |
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
| languages | **Hebrew and English from day one, RTL / BiDi done right**: every screen of the sim (front end, wizard, radio menu, debrief, subtitles, checklist card, preferences) has both; Godot's TextServer Advanced for BiDi shaping, mirrored layouts in Hebrew, an OFL font with Hebrew glyphs (e.g. Noto Sans Hebrew), strings in one table per language as `game/menu/strings_he.json` does today; the pilot guides in both languages; gender-neutral forms always |
| done | the leash (memory `leash-other-sessions`): code + tests + docs + guide text and pictures + the item's pictures on the "IAF 2026 Progress" page + credits + the session's own quality checks (code review pass, screenshot critique against the real reference, one real run) + queue line rewritten |

## Decisions of 3 November 2026 (the user's approvals)

| topic | decision |
|---|---|
| name | "IAF 2026" stays; it may be renamed later. Superseded by the decision of 8 November 2026 (below). |
| fonts | UI: Heebo. HUD: as close to the real jet's HUD font as a licence allows (search in progress). |
| Hebrew wording | Formal register, always gender-neutral forms; the infinitive "לטוס" for Fly. Bases as "כנף N" (Hebrew Wikipedia's wing numbers): Ramon כנף 25, Hatzerim כנף 6, Nevatim כנף 28, Ramat David כנף 1. Attributions קרדיט; Install התקנה; Preferences הגדרות; Pilot log יומן טיסות. CPU threads are תרדים, never תהליכונים (the user, 2026-11-08). |
| look | Less futuristic: friendly but military. Colours from the IAF: the jets' schemes, the uniforms and the flag. Backgrounds never pure black. The language is a Settings option, never a menu toggle. Hebrew screens are mirrored for every control kind: dropdown, toggle, slider, list. |
| debrief | Reads like a real debrief: "Plane flown", "From", "Time", "Mission", "Result", then the numbers, then remarks. |
| voices | English only for now; the Hebrew voice is rethought later because Piper's only Hebrew voice (SASPEECH) is non-commercial. Betty sounds like the real one: intense and clipped. The TTS flows between words: whole phrases are rendered in one pass, not concatenated particles. |
| parking spots | A7 approved. |
| review pages | Pictures on the review pages enlarge on click. |

## Decisions of 8 November 2026

| topic | decision |
|---|---|
| name | **Modern IAF** in English, **הזרוע הארוכה** in Hebrew: two titles, neither a translation of the other (as the original was Jane's IAF / כוכב כחול); no tagline. The window title, the wizard, the setup's texts and log, the launchers' messages and the docs carry it. The launchers are `./modern-iaf` and `./modern-iaf-setup` (+ `.ps1` twins); the old names `./iaf2026` and `./iaf2026-setup` (+ `.ps1`) forwarded to them until 9 November 2026, when they were removed. Every source comment and string a human reads says "Modern IAF" (the terrain download's User-Agent too), and the setup log is `assets/logs/modern-iaf-setup-<stamp>.log`. The folder `iaf-2026/`, the crate and bin names (`iaf-sim`), the test file names, `converted/iaf-2026/`, `tools/iaf-2026/` and the item codes stay unchanged: code identifiers the player never sees, and renaming them would move the user's built data and every link in the docs. Dated history lines (the Done notes, the decisions of 2 November) keep the names of their day. The `user://` folder follows `config/name` ("Modern IAF"); no records existed under the old name, so nothing moves. |
| aids | **No aids in Preferences** (unlimited fuel, no damage, any cheat): the physics row's toggles are dropped; aids, if ever, belong to a training mission's own options. Preferences has one screen per section (Graphics, Sound, Devices, Language), so each can grow. |

## Rules (the user, 3 November 2026)

- Every enhancement is shared by both games, never sim-only.
- Technical docs follow the ISO plain-language rule, KISS and doclint, and never say what does not exist.
- UI text and docs never state the obvious or describe what is not a choice; a page says only what the user decides or must know (the user, 8 November 2026).
- Pictures go into the md docs; the artifact pages are not the record.
- Whatever can be done in Rust is done in Rust.
- JSON the game reads is compact (no pretty-printing); authored data may be readable.
- Data that changes in the game (pilot log, debriefs) goes to SQLite through Rust: done 2026-11-09 (`iaf_tools::pilot_log`, [storage.md](storage.md) §5).
- Audio ships compressed (ogg), not WAV.
- Agents and sessions remove their worktree and its `target/` as soon as the branch is merged.
- The F-15C Baz joins the sim's jets at Tel Nof (data to add; not urgent; item [D3](#d3-f-15c-baz-at-tel-nof)).
- Status pages link item codes to their definitions.
- Voices use a neutral American English.
- A sim item is done only when its row in [shared.md](shared.md) says built in reborn or carries a dated reason; the orchestrator checks it in every review.
- Learn from the reborn game's solved problems before building new; the ground look is the first case (item [B4](#b4-ground-look-parity)).

## MVP: what "done" means
`./modern-iaf` (repo root) starts from the shared `assets/` root, reads nothing under `assets/install/` and no
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
- **Flight model:** FM-0 (unblocks M0): own `bd.ibx` sections + envelope files generated by `iaf-sim fm` (`sim_fm0.rs`)
  from TP-1538 and the public figures in `data_set.rs` `REAL`, loaded by `iaf_flight::load` unchanged. Then the
  6-DoF: `crates/iaf-flight/src/sixdof/` (TP-1538 tables, quaternion body, F100 engine, gear) behind
  `enum Fm { Original, SixDof }` in `IafFlight`, same `State` / `Controls` / `ApView`; `Model=6dof` in the own section.
- **Avionics:** nothing replaced for the MVP; the modern rows (`radar.rs` F16I / F35I, `real_hud/`, `f16_mfd.rs`,
  `pcd`, `gps.rs`) are already ours. Later own modules sit behind the same `Iaf*` classes by the same enum dispatch.
- **Docs:** `iaf-2026/README.md` and `iaf-2026/docs/` (threats.md, data-formats.md, flight-model.md, status.md); `tools/doclint.py`
  gets `iaf-2026/docs/**` and the path root.

## Phases and work items
Each item has a heading, so status pages and docs can link to its code (`#a0-the-split`).

### A0 the split

**the split**: `game/` → `iaf-reborn/` + `shared/`, the 6 menu couplings cut, every `res://` path, tool and doc rewritten by a script, the suite green before and after; one squash commit in a quiet window

Size: M. Blocks on: the two sessions' leashed items merged.

### A1 the project skeleton

`iaf-2026/` skeleton: the `shared` link + junction script, `sim_settings.gd`, `install_dir()` in `shared/settings.gd`, the root launchers (today `./modern-iaf` and `./modern-iaf-setup` + .ps1, renamed 2026-11-08), `tools/test.sh` loop over `iaf-2026/tests`, `gdparse` on both, the M0 probe (NEEDS DATA today). **Done (2026-11-02, branch wt/iaf-2026-core):** as listed, plus `own_dir()` and `keys_file()` in `shared/settings.gd` and the sim's `set_jet()` (the F-16 switch from the unit's `"airframe"`); the two leftovers closed (2026-11-03, branch wt/iaf-2026-own): the player's flight-model type from the sim's table (`Settings.fm_section`), `IafBases` on `own_dir()`'s `iaf.ibx` (no bases until B2b); until E2 `./iaf2026` runs the M0 probe and until A3 `./iaf2026-setup` runs `iaf-sim all` ([status.md](status.md))

Size: M. Blocks on: A0.

### A2 the iaf-sim compilers

`iaf-sim` bin: step graph on `iaf_setup::run`, `own` assembly, `db` and `missions` compilers. **Shipped (2026-11-02):** the readable formats ([data-formats.md](data-formats.md)), `iaf-sim db` (`sim.bdb.json`, the `"sim.bdb"` key of `objects.json`, own `weapons.ibx`, read by the game once A1's `install_dir()` hook lands; the jets' `"airframe"` key, from which A1 sets the F-16 switch) and `iaf-sim missions` (`converted/iaf-2026/missions/`, not `converted/missions/`: data-formats.md §7, accepted 2026-11-02), the Sufa / Barak / F-35I units, the gun / chaff / flare and the AIM-9M / MK-84 bases, the start-up and take-off missions at Ramon, Ramat David and Nevatim (Nevatim added to real_runways.csv), `test_sim_data.gd`. **Open:** the step graph and wizard wiring (after A1), red flights and threat units (after the user's yes, D2), the units' own models, real parking spots (B2)

Size: M. Blocks on: A1.

### A3 the setup wizard

**Modern IAF setup wizard** (`iaf-2026/setup/`): new pages and options, no Jane's mentions, reuse the `IafSetup` bridge and progress / cancel pattern of `game/setup`; Attributions page; Hebrew and English. **Done (2026-11-03, branch wt/iaf-2026-wizard):** `./iaf2026-setup` (and `./iaf2026` without the sim's data) opens the wizard: Welcome (language, what it builds, sizes and times, the GDAL / curl / disk check, the Attributions button: a modal with the Copernicus lines word for word, since 2026-11-08), Imagery (Sentinel-2, or with the Survey of Israel when its sheets are there), Install (progress per step, cancel, resume), Done; English and mirrored Hebrew in Heebo; the look in one file (Godot's default theme until the user's round 3); the steps `iaf_setup::sim_plan` / `sim_run` with stamps; `test_setup_wizard.gd`; a real run ([setup.md](setup.md)). **Open:** the look (round 3)

Size: L. Blocks on: A2.

### A4 the gate

One `Settings` call for every path under `assets/converted` a shared script reads, `converted(rel)`: the original game answers `assets/converted/<rel>` as before; the sim lets through only its own data (`own/`, `terrain/israel/`, `iaf-2026/`, `missions/sim.bdb.json`, `objects/objects.json`) and refuses the rest loudly (a path that does not exist, an error naming the caller, a count). **Done (2026-11-08, branch wt/iaf-2026-gate):** every `"converted/..."` path in `shared/` goes through it; `test_converted_gate.gd` scans `shared/**/*.gd` for the string outside its short list; the M0 probe's line "no original converted data read" (0 refused). The leaks the probe found, each fixed: the loading screen's menu art (the sim's own screen, [front-end.md](front-end.md)), the F-16's cockpit, HUD font and display fonts (the E1a hooks `cockpit_folder`, `Cockpit.default_dir`, `hud_font_path`, `display_font` from wt/iaf-2026-cockpit b06b379b and wt/e1a-font 5611028d), the aircraft descriptors and their index (`planes_folder()`: the F-16's from our model, `iaf-sim own`), the menu missions' list (`missions_folder()`), the default object database (`default_bdb()`), the effects' sprites (`original_art()`: a soft dot), the cloud layer's art (no textured sky in the sim), the F-35I's cockpit-view model looked up in the install first, the original's in-flight messages (`msgs()`). **Open:** the sim's own effects art and message table; `converted/roads` in the front end's Preferences (the scenery branch's own roads); the original store models once a sim jet carries stores. **Done (2026-11-08, branch wt/iaf-2026-install-gate):** the install's gate, `install(rel)`: the original game answers `assets/install/<rel>` as before; the sim refuses every install path into the same count (`install/<rel>`). Every install read in `shared/` goes through it (`mfd.gd`, `fs_mfd.gd`, `player_aircraft.gd`, `mission_weapons.gd`, `joystick.gd`, `player_weapons.gd`, `decoy_fx.gd`); `test_converted_gate.gd` scans for `install_dir()` outside its short list; the probe's line is "no original game data read, converted or install" (0 refused). The install reads the probe's and the front end's flights made, each fixed: `cockpits.ibx` (the player's cockpit looked up only for a jet whose definition names none), the gun's `gunfire.tga` (`original_art()`: a soft dot), the time of day's `defcolorset.tcs` and the debrief's `scores.ibx` (read from `own_dir()`, as `iaf.ibx`; the sim has neither yet). **Follow-ups (listed 2026-11-08, from the review):** the sim's object keys in its own `own/objects.json` in place of `objects/objects.json`'s `"sim.bdb"` key; the TSD map's one transform per frame in `f16_mfd.gd:400` and `mfd.gd:1175` as in `pcd_formats.gd` (done 2026-11-08, branch wt/iaf-2026-cockpit: 21 → 9 ms per TSD page, 27 → 17 ms per colour HSD; docs/mfd.md §9)

Size: S. Blocks on: A1.

### B1 the terrain

`iaf-sim terrain`: GLO-30 heights, Sentinel-2 + Survey of Israel colour, UTM frame. **Done (2026-11-03, branch wt/iaf-2026-terrain):** `iaf-sim terrain` writes `converted/terrain/israel/` (UTM 36N at 1:1, 347 × 511 km around the four bases, 2 m Survey / 8 m Sentinel-2 over Israel, 32 m beyond, GLO-30 heights at 64 m; [terrain.md](terrain.md)), `Settings.theatre_dir()` (the sim's theatre; `IAF_THEATRE` in the original game), the M0 probe's in-flight height check. **Open:** surface types (B2b), the other censored sites in the Survey photo

Size: L. Blocks on: —.

### B2 the airbases

airbases Ramon, Hatzerim, Nevatim, Ramat David from OSM: layouts, masks, `iaf.ibx`, `terraintype.dat` runway / water planes; scenery step freed from original missions. **B2a data done (2026-11-02), compile waits for B1:** the four layouts in lat / lon (`iaf-2026/data/airbases/`, [airbases.md](airbases.md), `tools/iaf-2026/osm_airbase.py`), the parking spots and Nevatim's tower placed by eye (for approval), the 2026 squadrons. **B2b done (2026-11-03):** `iaf-sim airbases` compiles the four bases into the UTM theatre: `airbases.json` + paved masks from the OSM polygons (Detailed airbases draws them), an own `iaf.ibx` (tower, lineup, taxi paths on the OSM taxiway graph, parking spots), an own `terraintype.dat` (runways, the sea), the missions on the parking spots at the terrain's height; the M0 probe parks each jet ([airbases.md](airbases.md) §9). **2026-11-08:** the taxiways, aprons and shelters' pads paved in `terraintype.dat` (a taxiing jet crashed on "rough ground"), the taxiway signs (holding and direction boards, ICAO colours, the sim's font). **Open:** the taxiways' names (no location signs); the towers of Ramon, Hatzerim and Ramat David; inland water and the scenery step: [B3](#b3-scenery-roads-and-inland-water)

Size: L. Blocks on: B1.

### B3 scenery, roads and inland water

Scenery, roads, city lights and inland water in the sim's theatre. **Done (2026-11-03, branch wt/iaf-2026-scenery):** `iaf-sim scenery` makes the original's buildings, trees, road layer and city lights' stand-ins in the UTM frame over the whole theatre, by the original's code with the frame as a parameter (`iaf_avionics::frame::Frame`), into `converted/terrain/israel/scenery` and `roads`; the download cache shared; exclusion zones from the sim's `terraintype.dat`, the inland water's polygons and the bases' OSM outlines; `iaf-sim all` runs it with no original data; inland water in the sim's `terraintype.dat` from OSM, the lakes' levels cited; the Far towns switch (Light: a dense town's far ring keeps its tall and large buildings), shared with the original game ([shared.md](shared.md)). Details and costs: [scenery.md](scenery.md), [terrain.md](terrain.md) §11. **2026-11-08:** the setup wizard's optional `sim-scenery` step; the OpenStreetMap extracts downloaded by the airbases step (a fresh root had no inland water); the coastline as the sea's boundary for the Survey photo and `terraintype.dat` ([terrain.md](terrain.md) §12). **Open:** [scenery.md](scenery.md) §9

Size: M. Blocks on: B1, B2.

### B4 ground look parity

the sim's terrain takes the reborn game's modern-colour Survey layer, ground textures and scenery. **Open.**

Size: M. Blocks on: B1.

### C1 FM-0 data

FM-0 data for Sufa, Barak, F-35I (and the F-15I row). **Done (branch wt/iaf-2026-fm0, 2026-11-02):** `tools/iaf-2026/fm0.py` (since 2026-11-09 its Rust port `iaf-sim fm`, `crates/iaf-tools/src/sim_fm0.rs`, the same bytes, a setup step and part of `iaf-sim all`; branch wt/fm0-rust) writes the own `bd.ibx` (`[F-16]` the Barak and the base of the Sufa and F-35I, `[F-15]` the F-15I) and envelopes from NASA TP-1538 (thrust table fitted to the model's 2 × 2 table, bounded at zero at 20 km; joint idle / military fit) and the REAL rows' public figures, every key sourced ([flight-model.md](flight-model.md)); the F-16 REAL row's thrust written as an absolute value (same on the 1998 data); validation on the own data: weights, static thrust, fuel flow, stall, ceiling, roll, turn, climb in range or close; top speed at 40,000 ft OFF for every jet (Sufa, F-35I, F-15I low; Barak high); a real Sufa flight on the own data through `IAF_ASSETS_DIR`. **Open:** the sim's own install path (A1), the thrust table and the REAL rows' 1998-shaped fits (C2), `[Autopilot]`, LimitAlphaVisual and the 1998 handling gains (the user)

Size: M. Blocks on: —.

### C2 the 6-DoF

6-DoF module + TP-1538 trim tests + validation rows. **Stage (a) done (branch wt/iaf-2026-sixdof, 2026-11-03):** `crates/iaf-flight/src/sixdof/`: all of TP-1538 Table III transcribed from the scan (every value checked against the page), appendix B's coefficient build-up, a quaternion rigid body with RK4 at ≤ 1/120 s; `tests/sixdof.rs`: the report's trims (66° at full nose up, the deep stall at 60°, static margin −4 %) and Stevens & Lewis's 502 ft/s trim within their tolerances ([flight-model.md](flight-model.md) §9). **Stage (b) done (branch wt/iaf-2026-sixdof-b, 2026-11-03):** TP-1538's engine model scaled per engine, the gear, the four jets' data, tests against the ratings, spool times, a take-off roll (26 % short of the F-16A SAC: open) and a stop (§9.7–9.10). **Stage (c) done (branch wt/iaf-2026-sixdof-c, 2026-11-03):** TP-1538's control system, `Fm { Original, SixDof }` behind `IafFlight` by `Model = 6dof` (the original game never reaches it, tested), fuel, Mach effects (inferred), Table V's roll times within 11 %, the validation rows on the 6-DoF, the frame cost, a real Sufa flight (§9.11–9.14). **Decided 2026-11-03 (the orchestrator):** the wave drag fit to each jet's published top speeds, labelled, pinned within 5 % (§9.15); the frame cost a budget, not parity: at most 20 µs per jet per frame on this laptop, enforced by `frame_cost_within_budget` (4.1 µs measured). **Open:** a sourced drag rise, the high-speed g onset, the take-off roll (−24 % against the SAC), flaps (§9.6)

Size: XL. Blocks on: C1.

### D1 the threats research

`iaf-2026/docs/threats.md`: the 2026 threat and weapon set, sources, model sources and licences

Size: M. Blocks on: —.

### D2 units and weapons

unit / weapon DB, own `weapons.ibx`, models for the DB's units (after the MVP: combat missions). **Drafts (branch wt/iaf-2026-threats, 2026-11-03), pending the user's decision:** threats.md §6's set as 12 unit and 10 weapon records in `iaf-2026/data/db/drafts/`, which `iaf-sim db` skips; approval = move the file and drop its `status` (data-formats.md §11); the compiler's SAM / AAA / radar classes and missile kinds ([threat-records.md](threat-records.md)). **Open:** the user's decision, the open figures, the damage scale for ground units, own flight-model rows for the MiG-29 and F-14A, the models, the missions

Size: L. Blocks on: D1, A2.

### D3 F-15C Baz at Tel Nof

the F-15C Baz joins the sim's jets at Tel Nof. **Data (2026-11-09, branch wt/iaf-2026-rules):** the unit record `data/db/units/f15c.json` (type 110, the shared `f15` definition, the M61A1's 940 rounds, sourced) and Tel Nof's airbase file `data/airbases/llek.json` (OpenStreetMap, OurAirports; the apron and the Baz's spot placed by eye), compiled by `iaf-sim db` / `airbases` ([airbases.md](airbases.md)). **Not flyable yet:** no 3D cockpit and no model of its own, so the front end does not offer it and no mission flies it; type 110 flies the F-15I's flight-model row. **Open:** the cockpit, the model, the Baz's own flight-model row, the Tel Nof missions

Size: S. Blocks on: C1, B2.

### E1 cockpit data, sounds and voices

own cockpit dirs, HUD font hook, keys, sound table + CC0 clips, TTS Betty / tower / AWACS with radio filter. **Sounds, voices and keys (E1b, branch wt/iaf-2026-sounds, 2026-11-02):** the CC0 sound set, the English Betty and tower voices through the radio filter, the radio phrase files and the own key table, compiled by `iaf-sim own` ([sound.md](sound.md)). **Cockpit code (E1a, 2026-11-02):** the 3D cockpit runs from a cockpit dir with no panel art (no panel bitmap, lamps or original cockpit-view model; the F-key views are head poses), the `Settings.hud_font_path()` and `Settings.cockpit_folder()` hooks, the cockpit profile in `iaf-2026/sim_settings.gd` (Real HUD, real MFDs; the cockpit dirs `converted/own/cockpits/<jet>`), `test_cockpit_no_panel.gd` ([cockpit.md](cockpit.md)). **Open:** the Hebrew voice (the user decides on its licence), AWACS and wingman phrases, the run-time squelch, a human listening pass (the reader hooks: done in A1); the F-35I's own threat symbols and each IAF jet's own RWR symbol set (not public; every jet draws the ALR-56M-style sheet). **Display data (E1a, 2026-11-03):** each jet's own `cockpit.json` (written for the 3D cockpit), RWR symbols, TSD map, GM picture, ADI ball and MFD atlas, nothing of the ISO's ([cockpit.md](cockpit.md) §4, §8; data-formats.md §14). **HUD and display font (E1a, 2026-11-08, branch wt/iaf-2026-cockpit):** Hershey's Roman Simplex stroke font as `data/fonts/HersheySimplex.ttf` (Approvals A9), through `hud_font_path` and `display_font`; the day and night pictures of each jet's cockpit ([cockpit.md](cockpit.md) §5, §6)

Size: L. Blocks on: A1.

### E2 the front end

front end `main.tscn`: jets with home bases, mission list, preferences (the carried-over Graphics / Physics / Devices toggles), debrief page, pilot log; disabled screens; **Hebrew and English with RTL / BiDi layouts from the first screen** (the string table, the font, the mirrored containers, a screenshot pair per screen). **Done (2026-11-08, branch wt/iaf-2026-frontend):** the round-3 design as the sim's main scene ([front-end.md](front-end.md)): Home, Pick a plane (Sufa, Barak, Adir with their wings and bases), Training, Pick a mission with its briefing, Preferences as real controls (Graphics, Language, Sound, Devices, Physics aids; no realism switch), the Debrief sheet from `user://debriefs/`, the Pilot log, Attributions (the wizard's list); Esc's pause menu over a flight; the flight's end opens its debrief; Hebrew mirrored with the approved wording, switched live; four CC BY photos from Wikimedia Commons (a CC BY 2.0 Barak in place of round 3's CC BY-SA one); `test_front_end.gd` in both languages (`-- --fly` flies a mission through it). Only what exists is shown, so no screen is disabled. **Open:** a pilot list (the name is the computer's user name), the debrief sheet and pilot log in reborn ([shared.md](shared.md)). **P1 records done (2026-11-09, branch wt/pilot-log-sqlite):** the records, the attempts, a mission's status and best time and the debrief's number are in `iaf_tools::pilot_log` (SQLite, `IafPilotLog`, [storage.md](storage.md) §5); the front end only displays them; the number grouping stays in `menu/front_end.gd` (display). **P1 to do (2026-11-08, Rust first), as it was:** the pilot log and debrief logic now in `menu/front_end.gd` (the attempts, a mission's status and best time, the debrief's number, the number grouping, the log append in `flight/sim_flight.gd`) into one crate function beside `training.rs`, exposed through gdext

Size: M. Blocks on: A1.

### Floating origin / camera-relative cockpit

**Open (listed 2026-11-08).** The world's coordinates are 32-bit floats about the flight's start (`terrain_view.gd`
`world_origin`), so the 3D cockpit, which flies with the jet, loses precision as the jet goes away from that point:
its vertices round to 2 mm steps 17 km out and 7.8 mm steps 100 km out (docs/cockpit.md "3D cockpit", the F-35I's
screens). The sim's flights cross the whole theatre (347 × 511 km, [terrain.md](terrain.md) §2). The item: keep the
cockpit near the coordinates' origin, either by moving the origin with the jet (a floating origin: the terrain, the
objects and the rig shifted together when the jet passes a set distance) or by drawing the cockpit relative to the
camera.

The patch today, `cockpit3d_screen.gdshader` (`cockpit3d.gd` `SCREEN_PULL`, 2026-11-03), draws the F-35I's panoramic
display and standby display 2.5 % of their distance nearer the eye: the same pixels, a nearer depth. Its limits:
- It covers those two screens only. Every other part of the 3D cockpit (the panel, the gauges, the lamps, the canopy
  frame, the F-16s' screens) keeps the rounding, and parts close together can swap places in the depth test.
- It holds out to 100 km from the flight's start (the 9.6 mm pull at the standby display against the 7.8 mm step,
  `test_cockpit3d.gd`). Past that the screens' cases can win the depth test again, and every cockpit vertex rounds to
  centimetres.
- The pulled screens cast no shadow (the pull would move it in the light's view).
- Anything nearer the eye than a screen by less than 2.5 % of its distance (about 1 cm at the standby display) draws
  behind the screen (inferred).

**Measured (2026-11-09, branch wt/iaf-2026-ils): this is the user's "the entire cockpit shakes"** (the Mac, 60 Hz).
`iaf-2026/tests/_cockpit_shake_probe.gd` (real render, mission 2012, the flight model stopped, the rig moved 0.5 mm a
frame at D m from the flight's start):

| D | camera ↔ cockpit transform moved | cockpit pixel change per frame, median / max |
|---|---|---|
| 0 | 0.25 mm | 0.24 / 0.93 |
| 4 km | 0.32 mm | 0.48 / 1.09 |
| 15 km | 1.1 mm | 0.58 / 3.4 |
| 30 km | 3.1 mm | 0 / 5.5 |
| 60 km | 4.4 mm | 0 / 8.1 |

From 30 km the cockpit stands still for frames, then jumps a few mm against the eye as one piece (median 0, max
5.5–8.1 grey levels averaged over the lower half of the view). The same rounding already shows on the CPU side: the
camera and the cockpit hang under the same rig, in the same `_process`, yet their relative transform moves by the f32
step of the rig's position. Ruled out by measurement: the frame pacing (the flight model steps in `_process` by the
frame's delta, no physics tick, the rig and camera set the same frame: at a fixed 60 fps the camera's per-frame step
is smooth to 0.5 mm on the take-off roll and a steady series in the climb, no stale frame), the 6-DoF's noise on the gear (0.15 mm, 0.005°),
the UTM numbers (the scene is already about the start: at the Ramon spot the camera is at (0, 645.67, 0), 0.0 m step
over 300 frames), the ILS (smooth, 1.4e-5° localizer steps on the final; `airbase.rs`
`ils_is_smooth_on_a_straight_approach`). The terrain and far objects show no shake: their f32 step is tiny against
their distance from the eye.

**Done for the sim (2026-11-09, branch wt/iaf-2026-cockpit-origin):** the cockpit-view model drawn in its own world
about the origin and laid over the flight's 3D view before its tonemap ([cockpit.md](cockpit.md) §6.2,
`shared/cockpit/cockpit_origin.gd`, `Settings.cockpit_at_origin()`). The probe after: the camera ↔ cockpit transform
does not move (0 at every distance), the panel's pixel change per frame 0.004 at 30 km and 0.011 at 60 km (from 10.5
and 15.5). Cost on the Iris Xe: about +4 to +5 ms GPU a frame (the second viewport). The original game is unchanged
(its jet stays within the 1998 theatre). **Open:** a floating origin for the rest of the world (nothing else measured
shakes: the terrain and far objects' step is tiny against their distance), the F-35I's screen pull
(`cockpit3d_screen.gdshader`) which the sim no longer needs, FXAA in place of MSAA in the cockpit's viewport (3.2 ms). With TAA or a temporal upscaler the cockpit's picture gives the flight's view no motion vectors: its edges may smear in a turn (not yet seen in a real render).

Size: M.

### E3 the training missions

training mission 1 (start engine, real timings, cockpit alive) and 2 (radio menu, tower TTS, taxi, takeoff), pass / fail rules, debrief numbers. **E3a scoring done (2026-11-02):** the rules as data in the missions' `training`, the scorer `iaf-training score` over a flight recording with the debrief record in English and Hebrew ([training.md](training.md)). **E3b core done (2026-11-03, branch wt/iaf-2026-training2):** the jet parked cold, one start command running the real start sequence's timings on the 6-DoF (the F-16's JFS, the F-35I's IPP and 90 s self test; sources and the inferred steps in [training.md](training.md) §7) with the screens, the HUD and the lamps coming alive; the numbered radio menu (Ctrl+T, English and Hebrew labels) with the English TTS tower of every own base; the recorder's version 2 (`rpm`, `avionics`, `radio` events); `IafTraining` scoring at the mission's end, the debrief record in `user://debriefs/`, the pilot log; `./iaf2026 -- --mission <id>`; `test_mvp.gd` flies both missions for the Sufa, the Barak and the F-35I to a Pass. **Open:** the debrief page and the front end (E2), the Hebrew voice (the user), the pilot's own request voice, the starter's sound, the checklist card (after the MVP)

Size: L. Blocks on: A2, B2, C1, E1, E2.

### F the probe

the probe `test_mvp.gd` passes for Sufa, Barak, F-35I on Linux / macOS / Windows. Part of the proof: the M0 probe's "no original game data read, converted or install" (item [A4](#a4-the-gate)) passes on the same machine, so the flights use the sim's own data only

**The first Mac play test (the user, 2026-11-08, mission 2011 on an M4 Pro, 1920 × 1080 window on a 2560 × 1440
screen), branch wt/iaf-2026-mac1:**
- No taxiway or apron: the sim's `PROFILE` left Detailed airbases at the 1998 value, which draws nothing in the sim.
  Fixed, with every look switch whose 1998 value draws art the sim lacks ([airbases.md](airbases.md) §9).
- "No idea how to do anything": the mission card at the start, a key hint line, the radio lines in the sim's own
  band in the game's language ([front-end.md](front-end.md) §8).
- The pause menu off the right edge with its labels outside the screen: the Hebrew overlay mirrored its position by
  its unscaled width; fixed and tested at three sizes in both languages. F1–F4 only switch views (checked).
- Preferences: one screen per section; no Physics / aids, no Rain row; the aids off in `PROFILE` (`easy_landing` was
  on); the Roads row and the probes no longer trip the A4 gate; the logs name only the sim's settings and drop the AI
  lines a training flight has no use for.
- Home opens on every start (Choose a plane before the first pick); the breadcrumbs open their screens; the wizard's
  Done page says only `./modern-iaf`.
- The point of view (too close to the HUD): measured the same as the original game's 3D cockpit (75° across, 5.5°
  down, the eye 0.475 m behind the Sufa's combiner); the default view's change went to its own session.

Size: —. Blocks on: all above except C2, D2.

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
- A4: `test_converted_gate.gd`; the M0 probe's "no original game data read, converted or install" line; the original game's suite unchanged (the same paths).
- E3 / F: `test_mvp.gd` headless per jet; one real flight of each mission by the user; the debrief page's numbers checked against the flight recorder.
- Always: the `game/` suite green after every merge; `docs/deviations.md` untouched (nothing in `game/` behaves differently).
