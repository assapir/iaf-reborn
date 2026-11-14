# Adding a new plane

This guide is for developers who add a flyable aircraft beyond the original game's set: its model, flight data,
cockpit, weapons and Jet list entry. The worked example is the F-35I Adir ([f35i.md](f35i.md): its real data, sources
and the choice per section). An *original-format* model (an `.xfr` in the install) is
[aircraft.md §4](aircraft.md#4-adding-a-new-aircraft).

**Terms**
- **Type code**: the number that identifies an aircraft type in every per-type table (§1).
- **bdb**: an object database file (`*.bdb`, converted to `*.bdb.json`); it defines the object classes (§1).
- **Descriptor**: a plane's `aircraft.json`, which lists its moving parts, engines, stations and eye point.
- **FM**: flight model. **AI**: computer-flown aircraft. **SAM**: surface-to-air missile.
- **RWR**: radar warning receiver. **TSD**: tactical situation display. **HUD**: head-up display.
  **MFD**: multi-function display. **IR**: infrared. **A-A / A-G**: air-to-air / air-to-ground.
- **Original** / **Real**: the two Flight data (and Weapon data) settings: the 1998 game's numbers, or published
  real-world numbers.

Everything under `assets/` is generated from the user's ISO and git-ignored, so a new plane's content (model,
descriptor, cockpit art) is **tracked in the repo** and merged in at run time. It must be our own work or licensed for
redistribution (CC BY / CC BY-SA / public domain; CC BY-NC only for local use). A new plane is a deviation from the
original: an opt-in on the Extras page (§8).

**Steps in order**
1. Write its aircraft definition ("Modern planes" below); pick a type code for the missions and the flight model
   (§1).
2. Build the 3D model, write its descriptor and place it in the repo (§2).
3. Add the flight data (§3).
4. Map or build a cockpit (§4).
5. Give the jet stores, stations and an Arming screen (§5).
6. Add it to the Jet list (§6), and check sounds, radar and RWR (§7).
7. Put it behind an Extras switch (§8) and add the tests (§9).

**Automated:**
- `iaf-convert plane-describe <model.gltf> <out-dir> [--type N] [--section NAME] [--label L]` writes the descriptor
  (§2.2) and reports what the game will miss.
- `iaf-convert plane-checklist <type> [repo-dir]` lists every code table of §1 with file:line and whether the type
  is already in it; for a type with an aircraft definition it names the file and marks `df` the tables the
  definition stands for.

Both are in `crates/iaf-tools/src/plane.rs`.

## Modern planes: the aircraft definition

A modern plane (ours, not in the 1998 game) keeps its behaviour in one file, its **aircraft definition**
`shared/extra/planes/<id>/airframe.json`, next to its model and cockpit. Adding a modern plane means writing that file;
the §1 type-code tables stay for the 1998 jets.

**The definitions today**

| id | plane | base | holds |
|---|---|---|---|
| `f16` | F-16D Barak, the 1998 F-16 (type 100) | — | the F-16 family's base: `original_model`, `cockpit_3d`, `hud_3d` |
| `f16i` | F-16I Sufa | `f16` | Jet list name, flight-model type, model, radar, stations, Arming art, guide, TSD label, 3D HUD, MFD colours |
| `f15` | F-15C Baz, the 1998 F-15 (type 110) | — | the F-15 family's base: `original_model` |
| `f15i` | F-15I Ra'am | `f15` | Jet list name, flight-model type, model, radar range, gun rounds, stations, Arming art, guide, TSD label, info tag |
| `f35i` | F-35I Adir | — | Jet list name, cockpit, 3D cockpit, HUD, voice, radar, gun, built-in FLIR, stations, Arming art, `flyable` |

**How the game reads a definition**
- `crates/iaf-flight/src/airframe.rs` builds the files into the crate (the `FILES` list) and resolves the bases.
- It then reads each resolved definition into the struct `Airframe` (same file). The struct is the list of fields:
  an unknown field, a misspelt one or a wrong type fails `cargo test` (test `every_file_parses_and_its_base_exists`),
  with the file, the error and the offending line of the resolved definition.
- A definition with a `base` holds only what differs from it. It is a JSON Merge Patch (RFC 7386) on the base: an
  object merges key by key, `null` removes a key, any other value replaces the base's.
- The adapter `airframe::id_for(type code, switches)` gives the definition a 1998 jet flies as:
  - 100 → `f16`, or `f16i` with Extras "F-16 version" on Sufa;
  - 110 → `f15`, or `f15i` with Extras "F-15 version" on Ra'am;
  - 1000 → `f35i` (the Extras "F-35I replaces" slot flies type 1000);
  - every other type → none: its tables decide.
- Rust reads the struct's typed fields (`airframe::get(id)?.radar`). GDScript asks `Settings.airframe(type_code)`
  (through `IafAirframe`): a Dictionary of the struct, with only the fields the definition holds. Each reader takes
  the definition's value and falls back to its type-code table, so a base without the field gives exactly the 1998
  value. With every switch off the bases hold no table value (Rust test `switches_off_give_the_1998_values`).

**The fields** (the struct `Airframe` and its nested structs; all optional except `jet_list`'s `title` and `desc`;
`notes` holds each value's source, by field name, and no code reads it)

| field | read by | what it decides |
|---|---|---|
| `base` | `airframe.rs` | the definition this one patches |
| `name`, `doc` | — | the plane's name and its doc |
| `jet_list` {`title`, `title_he`, `row_he`, `desc`} (strings) | `front_end.gd` `_jet_swap` | the Jet list button, row and description (Hebrew `desc` in `strings_he.json`) |
| `flyable` (bool) | `player_aircraft.gd` `flyable` | flyable without a `FLYABLE` entry |
| `cockpit` | `player_aircraft.gd` `profile`, `real_hud` `Jet::of_cockpit` | a cockpit dir in the repo instead of `cockpits.ibx`'s |
| `hud` | `real_hud` `Jet::of_cockpit` | the Real HUD symbology of that cockpit (`f35`: the helmet-only display, `IafRealHud.helmet_only`) |
| `fm` | `data_set::variant` | the flight-model type (`data_set.rs` `TYPES` / `REAL` row) |
| `original_model`, `model` | `airframe::model_for`, `gltf.gd` `detailed` | `model` is drawn in place of the family's 1998 model file `original_model`, with Models on Original too |
| `voice` {`betty` (bool), `real`, `real_betty`} | `flight_sounds.gd` `has_betty`, `real_voice`, `betty_set` | the voice warnings, the Real HUD's calls, Extras "Real Betty"'s voice set (`vms`, `f15`, `tones`) |
| `radar` {`row` (int), `km`, `ai_nm` (numbers)} | `radar.gd`, `real_weapons.gd` `radar_nm`, `combat.gd` `sensor_nm` | the radar table row, the Real range, the AI's sensor range |
| `gun_rounds` (int) | `real_weapons.gd` `gun_rounds` | the Real gun rounds |
| `gun` ({rpm, muzzle, guns}) | `real_weapons.gd` `jet_gun` | the jet's own gun's rate and muzzle velocity, where the record it fires stands in |
| `flir` (bool) | `player_weapons.gd` | a built-in FLIR |
| `weapons` {`arm_art`, `modern`, `loads`} | `mission_weapons.gd` `jet`, `modern_weapons.gd` `loads` | Arming art (`x_<id>`: `shared/extra/planes/<id>/arm`), the modern weapons `"always"`, and their stations (`{"<record id>": [count, "stations"]}`, the id a whole number) |
| `cockpit_3d` (string) | `cockpit3d.gd` `model_for` | the 3D cockpit's model (Extras "Cockpit": 3D; cockpit.md "3D cockpit") |
| `hud_3d` | `cockpit3d.gd` | the 3D cockpit's HUD (`HUD_std` / `HUD_wide`) |
| `hud_tint` (number) | `cockpit3d.gd` | Modern IAF's combiner tint, a fraction of the full one (`SIM_TINT` 0 when absent) |
| `fly_by_wire` (bool) | `aircraft.rs` `fly_by_wire` | the F-16's roll-rate command, and the deep stall in place of the spin |
| `drag_chute` (bool) | `terrain_view.gd` | `false`: the jet has no drag chute, so the flight never asks the flight model for one (every F-16 and F-35) |
| `sixdof` (bool) | `data_set.rs` `sixdof` | Physics "Flight model" on 6-DoF flies it on Modern IAF's 6-DoF from the sim's data (deviations.md §2) |
| `engine_spool` [4 numbers] | `spool.rs` `of_type` (via `lib.rs` `load_section`) | Better physics engine spool, before the type code's row: idle → military, military → idle, afterburner light-off, light-off → full (s) |
| `goggles` | `terrain_view.gd` `goggles_tube`, `goggles_lit` | the night goggles' tube whatever the year (`TUBES`), the cockpit lit for them |
| `mfd` | `settings.gd` `real_mfd` | the F-16's real MFD formats |
| `guide` | `reference.gd` `guide_name` | the pilot guide (`docs/guides/<guide>.md`) |
| `label` | `tsd.gd` `unit_label` | the TSD's selected-unit label |
| `info_tag` | `terrain_view.gd` | the flight info line's tag |

**To add a modern plane**
1. Write `shared/extra/planes/<id>/airframe.json` (a variant: a `base` and what differs).
2. Add it to `FILES` in `crates/iaf-flight/src/airframe.rs`, and to `id_for` when a 1998 type code or switch picks it.
3. A new field: add it to `Airframe` (or its nested struct) and to the table above, then read it where the game
   decides it, with the type-code table as the fallback. GDScript only sees the struct's fields.

Still keyed by type code for the F-35I (type 1000), and why:
- `data_set.rs` `TYPES` / `REAL`: the flight-model catalogue the definition's `fm` names;
- `player_aircraft.gd` `f35i_object()`: the F-16's bdb object, which missions need.

## 1. The type code

Every per-type behaviour is keyed by the aircraft type code (bdb object field `0x5b4`). All object classes
share this code space:
- the shipped bdbs use 100–220 for aircraft, 230/240 for the transports, and up to 450 for other units (radars,
  SAMs);
- `cockpit.gd` `RWR_GLYPH` keys 290–390 (radars) and 100–200 (aircraft);
- weapon types run 500–660 (`crates/iaf-avionics/src/stores.rs`);
- `crates/iaf-avionics/src/rwr.rs` `IGNORED_TYPES` (220, 250, 270) is skipped by the RWR; `plane-describe` refuses these.

1. Take a code **≥ 1000** (the F-35I has 1000).
2. Check that it is in no table: `iaf-convert plane-checklist <code>` marks every list `--` (the `..` rows are
   conditions to read).
3. Add it to the tables below (`plane-checklist` prints this list from the live sources):

| where | table | what it decides | needed? |
|---|---|---|---|
| `shared/aircraft/player_aircraft.gd` | `FLYABLE` | flyable (any other type flies as the F-16) | yes |
| | `COCKPIT` | cockpit index into `cockpits.ibx`, also the row of `TABLES` in `crates/iaf-avionics/src/radar.rs` | or a cockpit dir (§4) |
| | `TWIN` | two engines (gauges, logic+0x24) | if twin |
| | `JET_TYPES` | Jet list id → type | yes (§6) |
| `crates/iaf-flight/src/data_set.rs` | `TYPES` | name, model folder, bd.ibx section, code | yes (§3) |
| | `REAL` | Real flight data (by name) | yes (§3) |
| `crates/iaf-flight/src/spool.rs` | `ENGINES` | engine spool-up times (better physics `engine_spool`) | yes (§3) |
| `crates/iaf-flight/src/params.rs` | `SECTIONS` | original code ↔ section | no (`TYPES` overrides it) |
| `crates/iaf-tools/src/aircraft.rs` | `fm_section()` | type → section in converted descriptors | no (hand-written descriptor) |
| `crates/iaf-flight/src/aircraft.rs` | `type_code == 100` (flaps) | F-16 flaps at one third | review |
| | `fbw_departure && matches!(…, 100 \| 140)` | fly-by-wire deep stall | if fly-by-wire |
| | `matches!(p.type_code, 100 \| 140 …)` | fly-by-wire: no spin | if fly-by-wire |
| `shared/aircraft/aircraft_model.gd` | `delta_wing`, pitch mixer, `part_pose()` | per-type part signs (§2.3) | review |
| `shared/audio/flight_sounds.gd` | `BETTY_TYPES` | voice warnings (also the RWR's and the damage voice) | if it has them |
| `shared/weapons/real_weapons.gd` | `RADAR_KM`, `GUN_ROUNDS` | Real weapon data | yes (§5) |
| `shared/weapons/mission_weapons.gd` | `JET_ART` | Arming screen art and station boxes | yes (§5) |
| `iaf-reborn/menu/pilots.gd` | `TYPE_CATEGORY` | pilot records kill category | yes |
| `iaf-reborn/menu/tsd.gd` | `FLYABLE_TYPES` | TSD flight selection (missions that place the type) | if missions place it |
| `shared/cockpit/cockpit.gd` | `RWR_GLYPH` | RWR symbol when others see this type | if AI flies it |
| `crates/iaf-tools/src/bin/iaf-mission-report.rs` | `FLYABLE_NOW` | mission coverage report | yes |
| `tests/godot/test_jet_list.gd` | `JETS` | Jet list test row | yes (§9) |

A 1998 jet keeps these tables. A modern plane puts the same values in its aircraft definition ("Modern planes"
above); `plane-checklist` lists the definitions too.

## 2. The 3D model

### 2.1 What the game loads
- `shared/aircraft/aircraft_model.gd` `create(plane, type)` reads `<planes>/aircraft.json` (the index, `index()`) and
  `<planes>/<plane>/aircraft.json` (the descriptor, `load_descriptor()`).
- It opens the glTF at run time with `res://shared/util/gltf.gd` and finds the node named `root`.
- Each **direct child** of the root is a part when the descriptor's `parts` lists it, and hidden otherwise.
- A part turns about its own node origin, around the descriptor's `axis` (the `pivot` field is informational).
- The jet is drawn at the bdb Present scale (`0x65e`, `terrain_view.gd` `_player_model_scale()`): 2.0 for every
  flyable jet, 1.0 when there is no bdb object.

The glTF must be in the converted models' frame:
- metres, +Y up, nose toward **−Z**;
- the size of `planes/f16/f16_h.gltf` for an F-16-sized jet, since it is drawn ×2;
- one scene with **one root node**.

### 2.2 Node names (`PART_NAMES`, `crates/iaf-tools/src/aircraft.rs`; case-insensitive)

| node | role |
|---|---|
| `AilerL/R`, `FlapL/R`, `ElevaL/R` (stabilators), `ElevoL/R` (elevons), `RuddeL`, `Rudde`, `SpdbrU/D`, `CanarL/R`, `Hook` | control surfaces: origin on the hinge |
| `<part>1`, `<part>2` | hinge helpers: the axis runs from the one nearer the origin to the farther; no `<part>1` = never turns |
| `LdgL/R/F`, `LdgDr` | gear legs (turn with the gear ramp), doors (static, hidden when up) |
| `canopy`, `canopyB`, `pilot`, `pilotB` | crew parts: one ejection seat per pilot part; canopy thrown on ejection |
| `EngineL` + `EngineL1` (`EngineR` + `EngineR1`) | afterburner nozzle; the Y difference of the pair is the flame radius |
| `StationA`…`StationI`, `StationGun`, `StationCha`, `StationFla` | store stations, gun muzzle, chaff, flares |
| `Height` | wheel level (gear clearance: `terrain_view.gd`, `ai_flights.gd`) |
| `Camera` / `Pilon` | cockpit eye |
| `EndWingL/R` | wing tips |
| `Parach` | drag chute |
| `WheelsA`…`WheelsF` | wheels on the legs: turn with Rolling wheels (part-animation.md §2.2) |
| `BayLi/Lo/Ri/Ro` (ours) | weapon bay doors, inboard / outboard per side: origin on the hinge, open with the bay ramp |

**Glass:** a canopy material with partial alpha is blended (`alphaMode` BLEND). A cut-out or opaque canopy draws
as a solid blob or bare frame bars.

**Moving surfaces** need the mesh split per part. `tools/plane/kit.py` (Blender, headless) has the reusable steps:
`normalise` (size, frame), `bisect` / `extract` (cut a surface out by region along a hinge line), `Rig` (root, parts
on their hinges, `<part>1/2` helpers, points, glTF export), `bake_skin` (our own textures with baked ambient
occlusion), `decal` / `text_decal` (markings that follow the surface), `pilot`; and for a cockpit panel `box` /
`cyl` / `arch` / `sweep` / `rounded_rect`, `material` (`wear`, `coat`, `emission`), `cockpit_camera` / `panel_px`
(the game's projection), `panel_world` (day / night light), `render_panel` (Cycles on the GPU; `crop` for lamp frames,
WebP for the strip), `portals`, `lamp_sections` (the F-16's lamps borrowed with `"Shared"`; an optional per-lamp
`Scale` draws them larger), `update_cockpit_json`. The plane's own script holds only its data:
which meshes make which part, the hinge lines, the marking and cockpit positions (`tools/f35i/rig.py`,
`tools/f35i/cockpit3d.py`).

### 2.3 The descriptor (automated)
`iaf-convert plane-describe model.gltf out/<plane> --type N --section NAME --label L`:
- runs the converter's own `aircraft::describe()` on the glTF's node tree (`plane::to_model`);
- writes `out/<plane>/aircraft.json` (format 1: parts with ids and axes, engines, gun, stations, height, eye);
- prints findings: several roots, missing gear / canopy / pilot / `Height`, turning parts without hinge helpers, no
  engine pair, no gun or stations, no eye or eye behind the origin, root children that will be hidden, and canopy
  glass that does not blend.

The converted F-16, Lavi and F-15 round-trip to their converted descriptors with no findings.

Hand-set after the run:
- `"name"`: the plane's folder name (the tool writes the out dir's).
- `"borrow"` (optional): `{"<part>": {"plane": "f16", "part": "pilot", "offset": [x, y, z]}}` replaces our part's
  mesh with an original plane's part at run time (`aircraft_model.gd` `_borrow_parts`). The part is placed by the
  source's eye-to-part offset applied to our `eye`, plus `offset` (m). Use it for the pilot rather than modelling one.
- `"internal_stations"` (optional, letters A..I, e.g. `"CDFG"`): bay stations. Their stores are drawn only while
  the `Bay*` doors are half open; a release from one first opens the doors (0.5 s), then keeps them open 2 s (`player_weapons.gd` `_bay_wait`).

Edit afterwards if needed:
- `scale` (5.0, the clump scale);
- `part_rules` `{part: {sign, visible}}` when a surface moves the wrong way. A new type gets the default rules of
  aircraft.md §2.1: tailed (delta = false), pitch mixer f = 1, default gear signs.

### 2.4 Where it lives
`iaf-convert aircraft` rewrites `assets/converted/planes/aircraft.json` from the install on every run, so that file
holds only the install's planes. Extra planes live in the repo:
- `shared/extra/planes/<plane>/` holds the glTF, `.bin`, textures, `aircraft.json` and a `CREDITS.md` for third-party
  sources.
- `aircraft_model.gd` `index()` merges every folder there into the converted index, and `load_descriptor()` /
  `create()` read from it.
- `shared/extra/.gdignore` keeps Godot's importer off the raw glTF.

Example: `shared/extra/planes/f35i/`, built by `tools/f35i/rig.py` (Blender, headless).

### 2.5 Check it
- The contact sheet (aircraft.md §3, `<out-dir> <plane>`) renders gear, flaps, speed brakes and the flame.
- `tests/godot/test_aircraft_parts.gd` loads every descriptor.
- Against real photos of the exact variant (Wikimedia Commons first; note each file's licence; study only, never
  copy pixels): render the same views (side, front quarter, head-on, from above, loaded) and compare shape, antennas
  and sensor fairings, the camouflage pattern and colours on every surface (blisters and conformal tanks included),
  the markings (tail number size and place, squadron art) and real loadouts. Write what was checked, with the photos,
  in the jet's doc (example: docs/f16i.md §8.1, 2026-10-29: the nose AIFF array and the CFTs' camouflage were found
  this way).

## 3. Flight model

- A variant of an existing type (a newer block, another engine) gets its own sourced row, not the older variant's
  values: research the variant's own public figures (engine thrust and lapse, weights, top speeds, turn, climb, g
  limits) and its own validation reference row, and list what stays inherited and why (example: real-aircraft.md
  §8.1, the F-16I's Block 50/52 research).
- Parameters come from the install's `resource/md` (docs/flight-model.md §1): a section per aircraft plus its
  envelope `<n>.dat`.
- **Pitfall:** v1.1 installs carry the XOR-encoded `bdgen.dat`, and `iaf_flight` `read_md()` reads it and skips
  `bd.ibx`. A section appended to `bd.ibx` is silently ignored.
- Envelopes are tried as `<n>gen.skp`, then `<n>.dat`.

A new type is defined in code; it needs no install file:
1. **`TYPES` row** (`data_set.rs`): `ty("NAME", "<plane folder>", "<existing section>", CODE)`. The section is the
   original block the type flies with **Flight data = Original** (e.g. `"F-16"`).
2. **`REAL` row**: `Real { aircraft: "NAME", base: Some("<section>"), … }`. It overrides the base section with
   published numbers when Flight data = Real. Write it as `Real { aircraft, base, empty_lb, …, ..NONE }`: set
   `empty_lb`, `thrust` and `wave_drag`, plus whatever is published:
   - masses: `empty_lb`, `fuel_lb`, `max_lb`;
   - thrust: `thrust` (scale, or the sea-level static afterburner value), `alt_thrust` (20 km factor), `mil_ratio`;
   - aero: `wing_ft2`, `cd0`, `wave_drag`, `stall_kt`;
   - roll: `roll_deg_s`, `roll_accel`;
   - fuel flow: `ff_ab_lb_s`, `ff_mil_lb_h`;
   - limits and systems: `g`, `ceiling_ft`, `chute`, `nose_wheel`, `afterburner`.
3. **Fit** CD0, wave drag and `alt_thrust` to the published top speeds (sea level and at altitude), the method of
   [real-aircraft.md](real-aircraft.md). The model has a 2×2 Mach/altitude thrust table. Military power is 60% of
   max unless `mil_ratio` is set. Fuel flow is the same at every altitude.
4. **Engine spool-up:** a row in `crates/iaf-flight/src/spool.rs` `ENGINES` (idle → military, military → idle,
   afterburner light-off and fill, seconds; better physics `engine_spool`, flight-model.md §10.2). Without a row
   the type keeps the original's instant thrust.
5. **Fly-by-wire:** add the code to the no-spin and deep-stall cases of `crates/iaf-flight/src/aircraft.rs` (§1).
6. **Test:** a reference row in `crates/iaf-flight/tests/validation.rs` (top speeds, ceiling, g).

A jet new to the game has only Real numbers of its own. List it in `data_set.rs` `NO_ORIGINAL` and it flies its Real
row with either Flight data (`data_set::effective()`), as the F-35I does. If it is left out of that list, it flies its
base section with Flight data = Original.

The player's type reaches the flight model as its `fm_section`:
- `player_aircraft.gd` `profile()` asks `Settings.fm_section(type)`. The original game answers "", so `profile()`
  takes the converted descriptor's `fm_section` (written by `iaf-convert` from `iaf_flight::params::code_section`,
  the original's type → section table). Modern IAF answers from its own bd.ibx (`IafFlight.fm_type`,
  `iaf_flight::fm_name_in`: the code's section, or the F-35I for 1000, when the own bd.ibx holds the section it
  loads; else the F-16).
- `profile()` → `terrain_view.gd` `flight.start(install, fm_section, …)` → `IafFlight`
  (`crates/iaf-godot/src/flight.rs`) → `iaf_flight::load_in`;
- AI aircraft pass the model folder (`ai_flights.gd`).

## 4. Cockpit

`shared/cockpit/cockpit.gd` `load_cockpit(dir)` reads `<assets>/<dir>/cockpit.json`. That file is the original
`cockpit.ibx` as JSON (`iaf-convert cockpit`, docs/cockpit.md), with `image_scale` 4. It loads:
- the textures named by `PANEL`, `HUD`, `LENHORIZON`, `PANELVARIO`, `PANELAOA`, `LIGHTSON` `FileName` (ours: a
  `.webp` name loads that file; `PANEL` / `LIGHTSON` `NightFileName` is the art shown at night instead of the
  darkened day art);
- always `mfds.png`, `rwrsymb.png` and `map.json`.

Coordinates are in the original 1920-px-wide panel space. The art is 4× that: the panel strip is 7680×1408 and
`mfds.png` is 1056×3696. `hud.gd` and `mfd.gd` are data-driven; the only per-cockpit code is `hud.gd`
`GUN_RET_V10`. The `[MFD]` section (`Left/Right/MiddleActive` + offsets) places the up-to-three MFDs (docs/mfd.md
§7).

Options:
- **Reuse** an existing cockpit: map the type in `player_aircraft.gd` `COCKPIT` (e.g. to the Lavi's index 3). The
  original does the same for unflyable types (mfd.md §7).
- **Custom:** a tracked folder with a hand-written `cockpit.json` and our own art at the sizes above, plus copies of
  `mfds.png`, `rwrsymb.png` and `map.json`. `profile()` must then return that dir instead of the `cockpits.ibx`
  lookup (`cockpit_folder()`).
- **Helmet display only (glassless HUD):** keep a `HUD` section (`hud.gd` `_layout()` reads its borders, `CenterY`,
  `BorePositionY`), leave out its `FileName`, and set **`Dash` 1**.
  - The loader skips sections without a file, and the glass draw is guarded (`cockpit.gd` `tex.has("HUD")`), so
    this needs no code.
  - Looking forward, the HUD symbology then floats in free space: a helmet "virtual HUD".
  - Head turned ≥ 250 px aside or ≥ 200 px down, it becomes the DASH helmet display at (320, 220) (`cockpit.gd`
    `dash()`, docs/cockpit.md "HUD dash repeater").
  - In free look and padlock, the IR seeker locks off-boresight (docs/weapons.md §5.4).
- **More than three displays** (e.g. one panoramic screen): `[MFD] Portals` = [[x, y, scale, page], …] (the page's
  top-left in panel px), one MFD node per portal drawn at `scale` (`cockpit.gd` `_create_mfds()`, `mfd.gd` `portal_scale`).
  With a `[PCD]` section (`Rect`, `Bar`, `WindowTop`, `Esis`) `shared/cockpit/pcd.gd` draws the display around them:
  the glass, status bar, lower windows and standby display (docs/f35i.md §4.3).
- **A cockpit in the repo:** a `res://` cockpit dir (the aircraft definition's `cockpit`), and `"Shared": "<converted
  cockpit>"` for the original art it borrows (MFD atlas, RWR symbols, TSD map, ADI ball, the lamps and gear lever;
  `cockpit.gd` `_file()`), since that art cannot be committed. Reuse the original's pieces first; model and render
  only what it lacks. Example: `shared/extra/planes/f35i/cockpit/`, the panel modelled and rendered by
  `tools/f35i/cockpit3d.py` with the game's cockpit camera, with its own lamps rendered from the same scene.
- **Looking aside / back:** `<plane>_bc.gltf` next to the extra plane's glTF is its cockpit-view model
  (`terrain_view.gd` `_spawn_player`; example `tools/f35i/bc.py`). Its object named `<anything>_bc_frame` (a canopy
  frame) is hidden while the 3D cockpit draws its own.
- **A 3D cockpit** (Extras "Cockpit": 3D): a glb in the cockpit-view model's frame, named in the definition's
  `cockpit_3d`, with `<model>.json` beside it; `cockpit3d.gd` reads its named nodes (docs/cockpit.md "3D cockpit").
  Example: `tools/f35i/cockpit3d.py --glb` writes the F-35I's from the same scene as its panel art (docs/f35i.md
  §4.5).

## 5. Weapons

- **Jet object:** all missions share one object database, `default6_1.bdb.json`. The player's stores come from the
  class 0x1c object whose `0x5b4` equals the player's type (`terrain_view.gd` `_player_object()`, mission bdb
  first, then default6_1).
- A new type starts without an object: the jet then flies clean (no stores) and is drawn at scale 1.0. Fix: at load
  time, clone a similar jet's object with the new `0x5b4` (the bdb is git-ignored, so the clone lives in code or in a tracked
  patch file).
  - `armament.hardpoints`: 12 `[weapon id, count]` pairs (9 pylons, gun, chaff, flares).
  - `loads.items`: `CDMEWeaponLoadItem` with `0x910` weapon id, `0x906` max, `raw` = 9 per-station allow flags.
  - `0x53c` Present id gives the model scale.
  - Weapon ids are the same in every mission (docs/weapons.md §1–2).
- **Stations** in 3D come from the descriptor's `StationA..I` / `StationGun` (`stores.gd`, `player_weapons.gd`).
  A missing frame hangs the store at the origin. A station is the pylon point: the store hangs below it by its
  `pilon`. Bays: cut the doors from the belly skin and close the hole with `kit.cavity` (`tools/f35i/rig.py`
  `cut_bays`), then list the bay stations in `internal_stations`.
- **Arming screen:** `shared/weapons/mission_weapons.gd` `JET_ART` → `menu/bmp/arm/jets/<art>.bmp/.trx`. The `.trx`
  holds the base weight, max take-off weight and the 9 station boxes. An extra plane (`JET_ART` "x_<plane>"):
  - `shared/extra/planes/<plane>/arm/front.png`: its front view in the arming greens (`tools/plane/kit.py`
    `arm_front_view`, mirrored like the originals: station A on the image's left) and `arm.json` (base / max lb,
    `boxes` = a base jet's station boxes, `points` = the stations on the front view, `title`, `base_art`);
  - a front view setup must make on the user's machine (a model that may not ship: the F-15I's, aircraft-models.md
    §6.7) is `arm.json`'s `front`, a path under `converted/` with its `points` in the `.json` beside it;
  - `iaf-convert arm-extra <converted menu>/img <arm dir> <out png>` (run by `tools/setup-cli.sh`) composes the screen
    on the user's machine: the background from the original jets' images (per pixel the darkest colour two of them
    agree on, which drops each jet and its lines; where fewer than four agree, the wings' height most jets share,
    painted over from the background round it: a low percentile there left a ghost of the wings, changed
    2026-11-02), the base jet's boxes and bottom band, our front view and leader lines;
  - the game draws the title (`arming.gd`), reads `arm.json` (`mission_weapons.gd` `_extra_jet`); a jet picked on
    the Jet list arms as itself (art, stations, default load; the allowed counts stay the mission jet's, as the
    original's `FUN_0058f110` / `FUN_004ef8a0`; the F-35I keeps its own) with its chosen load used in flight
    (`player_weapons.gd` `_arm`).
- **Real data:** `shared/weapons/real_weapons.gd` `RADAR_KM` (km) and `GUN_ROUNDS`. Weapons the game lacks map to the
  nearest original (docs/real-weapons.md).

## 6. Front end (Jet list)

- The Jet list is the original `sjet.trx` screen: 7 buttons in panel `pJet`, art
  `menu/img/palettes/pjet_0..3.png` with the labels **baked in**.
- `front_end.gd` `JET_IDS` maps label → id. `PlayerAircraft.JET_TYPES` maps id → type. The press sets
  `Settings.jet_id`, and `terrain_view.gd` `_choose_player()` swaps the mission's jet for `JET_TYPES[jet_id]`.
  `JETS_DISABLED` greys jets per mission.

All 7 buttons are taken. Two ways in:
- **Replace a slot (simplest):** an Extras row "<plane> replaces: Off / Mirage / … / Lavi". The chosen button's
  band is relabelled by cutting it out of the art and drawing the new label in the baked-label style, as
  `_extras_tab_tex()` / `_draw_extras_tab()` do for our Extras and Physics tabs. `JET_TYPES` resolves that id to
  the new type.
- **An 8th button:** the art has room under LAVI (y ≈ 377, the 44 px step). Append a button to the panel and draw
  its band the same way. This needs hit testing and `menus.json` handling.

Hebrew labels go in `iaf-reborn/menu/strings_he.json` (our strings only).

## 7. Sounds, radar, RWR
- **Engine sounds** are the same for every jet (`flight_sounds.gd`). Only `BETTY_TYPES` is per type (voice
  warnings; also `rwr.betty` and `player_damage.betty`).
- **Radar:** `TABLES` in `crates/iaf-avionics/src/radar.rs` has one A-A / A-G mode row per cockpit index (`COCKPIT`). A new type gets the
  F-16 row unless mapped. `RADAR_KM` overrides the long-range-search range with Weapon data = Real.
- **RWR:** the own type needs no entry. `RWR_GLYPH` matters only when other aircraft of this type appear.

## 8. Opt-in
The original stays the default (docs/deviations.md):
1. Add an Extras row for the plane, off by default.
2. Add one line to [deviations.md §2](deviations.md#2-opt-in-switches-original-by-default).

With the row off, the Jet list and every table behave as in the original.

## 9. Tests
- `cargo test -p iaf-flight`: the `validation.rs` row.
- `tests/godot/test_jet_list.gd` `JETS` row: flies 311 (roll-out) and 312 (gear, flaps, speed brake, afterburner,
  ejection by crew parts).
- `tests/godot/test_player_aircraft.gd`: profile, cockpit, model, weapons, Real data.
- `tests/godot/test_aircraft_parts.gd`: the descriptor loads; parts move.
- `tests/godot/test_helmet.gd` / `test_hud.gd`: for a glassless `Dash` 1 cockpit.

## 10. Not automated, and why
| step | why |
|---|---|
| splitting, renaming and pivoting a downloaded model | needs a 3D editor (Blender) |
| cockpit and Jet list art | art |
| fitting the flight data | judgement against published numbers; the method is in real-aircraft.md |
| the bdb object clone and the flight model's §1 tables | missions need the bdb object; the flight model reads its type code, not a definition |
