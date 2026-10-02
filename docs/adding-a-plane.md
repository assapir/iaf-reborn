# Adding a new plane

How to add a flyable aircraft that the original game does not have (model, flight data, cockpit, weapons, Jet list).
The worked example is the F-35I Adir: [f35i.md](f35i.md) has its real data, sources and the choices per section.
Adding an *original-format* model (an `.xfr` in the install) is [aircraft.md §4](aircraft.md#4-adding-a-new-aircraft).

Everything under `assets/` is generated from the user's ISO and git-ignored, so a new plane's content (model,
descriptor, cockpit art) has to be **tracked in the repo** and copied or merged in at run time. It must be our own
work or licensed for redistribution (CC BY / CC BY-SA / public domain; CC BY-NC only for local use). A new plane is
a deviation from the original: make it an opt-in on the Extras page (§8).

**Automated:**
- `iaf-convert plane-describe <model.gltf> <out-dir> [--type N] [--section NAME] [--label L]` writes the descriptor
  (§2.2) and reports what the game will miss.
- `iaf-convert plane-checklist <type> [repo-dir]` lists every code table of §1 with file:line and whether the type
  is already in it.

Both are in `crates/iaf-tools/src/plane.rs`.

## 1. The type code

Every per-type behaviour is keyed by the aircraft type code (bdb object field `0x5b4`). Every object class
shares this code space:
- the shipped bdbs use 100–220 for aircraft, 230/240 for the transports, and up to 450 for other units (radars,
  SAMs);
- `cockpit.gd` `RWR_GLYPH` keys 290–390;
- weapon types run 500–660 (`stores.gd`);
- `game/weapons/rwr.gd` `IGNORED_TYPES` (220, 250, 270) is skipped by the RWR; `plane-describe` refuses these.

Take a code **≥ 1000** (e.g. 1000) and check it is in no table:
`iaf-convert plane-checklist 1000` marks every list `--` (the `..` rows are conditions to read).

Then add it to the tables. `iaf-convert plane-checklist <code>` prints this list from the live sources:

| where | table | what it decides | needed? |
|---|---|---|---|
| `game/aircraft/player_aircraft.gd` | `FLYABLE` | flyable (any other type flies as the F-16) | yes |
| | `COCKPIT` | cockpit index into `cockpits.ibx`, also `radar.gd`'s mode-table row | or a cockpit dir (§4) |
| | `TWIN` | two engines (gauges, logic+0x24) | if twin |
| | `JET_TYPES` | Jet list id → type | yes (§6) |
| `crates/iaf-flight/src/data_set.rs` | `TYPES` | name, model folder, bd.ibx section, code | yes (§3) |
| | `REAL` | Real flight data (by name) | yes (§3) |
| `crates/iaf-flight/src/params.rs` | `type_code()` | original sections → code | no (`TYPES` overrides it) |
| `crates/iaf-tools/src/aircraft.rs` | `fm_section()` | type → section in converted descriptors | no (hand-written descriptor) |
| `crates/iaf-flight/src/aircraft.rs` | `type_code == 100` (flaps) | F-16 flaps at one third | review |
| | `fbw_departure && matches!(…, 100 \| 140)` | fly-by-wire deep stall | if fly-by-wire |
| | `p.type_code == 100 \|\| … == 140` | fly-by-wire: no spin | if fly-by-wire |
| `game/aircraft/aircraft_model.gd` | `delta_wing`, pitch mixer, `part_pose()` | per-type part signs (§2.3) | review |
| `game/audio/flight_sounds.gd` | `BETTY_TYPES` | voice warnings (also the RWR's and the damage voice) | if it has them |
| `game/weapons/real_weapons.gd` | `RADAR_KM`, `GUN_ROUNDS` | Real weapon data | yes (§5) |
| `game/weapons/mission_weapons.gd` | `JET_ART` | Arming screen art and station boxes | yes (§5) |
| `game/menu/pilots.gd` | `TYPE_CATEGORY` | pilot records kill category | yes |
| `game/menu/tsd.gd` | `FLYABLE_TYPES` | TSD flight selection (missions that place the type) | if missions place it |
| `game/cockpit/cockpit.gd` | `RWR_GLYPH` | RWR symbol when others see this type | if AI flies it |
| `crates/iaf-tools/src/bin/iaf-mission-report.rs` | `FLYABLE_NOW` | mission coverage report | yes |
| `tests/godot/test_jet_list.gd` | `JETS` | Jet list test row | yes (§9) |

Until these tables become data (one per-type record read from a file), each new plane is a code change in all of
them. That refactor is the real fix for "add a plane without code".

## 2. The 3D model

### 2.1 What the game loads
- `game/aircraft/aircraft_model.gd` `create(plane, type)` reads `<planes>/aircraft.json` (the index, `index()`) and
  `<planes>/<plane>/aircraft.json` (the descriptor, `load_descriptor()`).
- It opens the glTF at run time with `res://util/gltf.gd` and finds the node named `root`.
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

**Glass:** a canopy material with partial alpha is blended (`alphaMode` BLEND). A cut-out or opaque canopy draws
as a solid blob or bare frame bars.

**Moving surfaces** need the mesh split per part. Renaming, re-pivoting and splitting a downloaded model is manual
work in Blender. Nothing here automates it.

### 2.3 The descriptor (automated)
`iaf-convert plane-describe model.gltf out/<plane> --type N --section NAME --label L`:
- runs the converter's own `aircraft::describe()` on the glTF's node tree (`plane::to_model`);
- writes `out/<plane>/aircraft.json` (format 1: parts with ids and axes, engines, gun, stations, height, eye);
- prints findings: several roots, missing gear / canopy / pilot / `Height`, turning parts without hinge helpers, no
  engine pair, no gun or stations, no eye or eye behind the origin, root children that will be hidden, and canopy
  glass that does not blend.

The converted F-16, Lavi and F-15 round-trip to their converted descriptors with no findings.

Edit afterwards if needed:
- `scale` (5.0, the clump scale);
- `part_rules` `{part: {sign, visible}}` when a surface moves the wrong way. A new type gets the default rules of
  aircraft.md §2.1: not a delta, pitch
  mixer f = 1, default gear signs.

### 2.4 Where it lives
`iaf-convert aircraft` rewrites `assets/converted/planes/aircraft.json` from the install on every run, so an extra
plane must not be added to it by hand. Keep the model and descriptor in a tracked folder (e.g.
`game/extra/<plane>/`) and have `aircraft_model.gd` `index()` merge that folder's entries into the converted index
(not built yet).

### 2.5 Check it
- `godot --path game -s tools/aircraft_sheet.gd -- /tmp/sheet <plane>` renders gear, flaps, speed brakes and the
  flame.
- `tests/godot/test_aircraft_parts.gd` loads every descriptor.

## 3. Flight model

- Parameters come from the install's `resource/md` (docs/flight-model.md §1): a section per aircraft plus its
  envelope `<n>.dat`.
- **Pitfall:** v1.1 installs carry the XOR-encoded `bdgen.dat`, and `iaf_flight` `read_md()` reads it **instead
  of** `bd.ibx`. A section appended to `bd.ibx` is silently ignored.
- Envelopes are tried as `<n>gen.skp`, then `<n>.dat`.

A new type needs no install file:
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
   max unless `mil_ratio` is set. Fuel flow does not vary with altitude.
4. **Fly-by-wire:** add the code to the no-spin and deep-stall cases of `crates/iaf-flight/src/aircraft.rs` (§1).
5. **Test:** a reference row in `crates/iaf-flight/tests/validation.rs` (top speeds, ceiling, g).

A non-original jet has no Original numbers of its own. Either accept that it flies its base section with Flight data
= Original, or force its Real row in `data_set::section()` / `load_in()` (a small rule for types without an
original section).

The player's type reaches the flight model as the descriptor's `fm_section`:
- `player_aircraft.gd` `profile()` → `terrain_view.gd` `flight.start(install, fm_section, …)` → `IafFlight`
  (`crates/iaf-godot/src/flight.rs`) → `iaf_flight::load_in`;
- AI aircraft pass the model folder (`ai_flights.gd`).

## 4. Cockpit

`game/cockpit/cockpit.gd` `load_cockpit(dir)` reads `<assets>/<dir>/cockpit.json`. That file is the original
`cockpit.ibx` as JSON (`iaf-convert cockpit`, docs/cockpit.md), with `image_scale` 4. It loads:
- the textures named by `PANEL`, `HUD`, `LENHORIZON`, `PANELVARIO`, `PANELAOA`, `LIGHTSON` `FileName`;
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
- **No HUD glass (helmet only):** keep a `HUD` section (`hud.gd` `_layout()` reads its borders, `CenterY`,
  `BorePositionY`) but give it no `FileName`, and set **`Dash` 1**.
  - The loader skips sections without a file, and the glass draw is guarded (`cockpit.gd` `tex.has("HUD")`), so
    this needs no code.
  - Looking forward, the HUD symbology then floats with no glass: a helmet "virtual HUD".
  - Head turned ≥ 250 px aside or ≥ 200 px down, it becomes the DASH helmet display at (320, 220) (`cockpit.gd`
    `dash()`, docs/cockpit.md "HUD dash repeater").
  - In free look and padlock, the IR seeker locks off-boresight (docs/weapons.md §5.4).
- **More than three displays** (e.g. one panoramic screen) needs `_create_mfds()` to take a list of display windows
  instead of the three fixed MFD indices (not built).

## 5. Weapons

- **Jet object:** all missions share one object database, `default6_1.bdb.json`. The player's stores come from the
  class 0x1c object whose `0x5b4` equals the player's type (`terrain_view.gd` `_player_object()`, mission bdb
  first, then default6_1).
- A new type has no object, so the jet flies with no stores and drawn at scale 1.0. Fix: at load time, clone a
  similar jet's object with the new `0x5b4` (the bdb is git-ignored, so the clone lives in code or in a tracked
  patch file).
  - `armament.hardpoints`: 12 `[weapon id, count]` pairs (9 pylons, gun, chaff, flares).
  - `loads.items`: `CDMEWeaponLoadItem` with `0x910` weapon id, `0x906` max, `raw` = 9 per-station allow flags.
  - `0x53c` Present id gives the model scale.
  - Weapon ids are the same in every mission (docs/weapons.md §1–2).
- **Stations** in 3D come from the descriptor's `StationA..I` / `StationGun` (`stores.gd`, `player_weapons.gd`).
  A missing frame hangs the store at the origin.
- **Arming screen:** `game/weapons/mission_weapons.gd` `JET_ART` → `menu/bmp/arm/jets/<art>.bmp/.trx`. The `.trx`
  holds the base weight, max take-off weight and the 9 station boxes. Reuse a similar jet's art or draw new.
  Arming shows the mission's formations, so a jet swapped in from the Jet list uses its default load (as for the
  seven originals).
- **Real data:** `game/weapons/real_weapons.gd` `RADAR_KM` (km) and `GUN_ROUNDS`. Weapons the game lacks map to the
  nearest original (docs/real-weapons.md).

## 6. Front end (Jet list)

- The Jet list is the original `sjet.trx` screen: 7 buttons in panel `pJet`, art
  `menu/img/palettes/pjet_0..3.png` with the labels **baked in**.
- `front_end.gd` `JET_IDS` maps label → id. `PlayerAircraft.JET_TYPES` maps id → type. The press sets
  `Settings.jet_id`, and `terrain_view.gd` `_choose_player()` swaps the mission's jet for `JET_TYPES[jet_id]`.
  `JETS_DISABLED` greys jets per mission.

There is no free button. Two ways in:
- **Replace a slot (simplest):** an Extras row "<plane> replaces: Off / Mirage / … / Lavi". The chosen button's
  band is relabelled by cutting it out of the art and drawing the new label in the baked-label style, as
  `_extras_tab_tex()` / `_draw_extras_tab()` do for our Extras and Physics tabs. `JET_TYPES` resolves that id to
  the new type.
- **An 8th button:** the art has room under LAVI (y ≈ 377, the 44 px step). Append a button to the panel and draw
  its band the same way. This needs hit testing and `menus.json` handling.

Hebrew labels go in `game/menu/strings_he.json` (our strings only).

## 7. Sounds, radar, RWR
- **Engine sounds** are the same for every jet (`flight_sounds.gd`). Only `BETTY_TYPES` is per type (voice
  warnings; also `rwr.betty` and `player_damage.betty`).
- **Radar:** `radar.gd` `TABLES` has one A-A / A-G mode row per cockpit index (`COCKPIT`). A new type gets the
  F-16 row unless mapped. `RADAR_KM` overrides the long-range-search range with Weapon data = Real.
- **RWR:** nothing per own type. `RWR_GLYPH` only matters when other aircraft of this type appear.

## 8. Opt-in
The original stays the default (docs/deviations.md): a new plane is an Extras row, off by default, plus one line
in deviations §2. With it off, the Jet list and every table behave as before.

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
| the bdb object clone and the §1 tables | code tables keyed by type; automatable once they are data |
