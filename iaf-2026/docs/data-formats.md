# IAF 2026 data formats

**Terms:** bdb = the object database the missions name (a converted `.bdb`, docs/formats/mis.md §4); hex key = a
field name of the converted JSON (`"0x514"`); Present record = a model entry of the bdb; engine frame = the game's
world metres (X east, Y north, docs/georef.md); "inferred" = our own reasoning; "open" = no source found.

IAF 2026 keeps its units, weapons and missions as readable JSON under `iaf-2026/data/`. The compiler `iaf-sim`
(`crates/iaf-tools/src/sim.rs`, bin `iaf-sim`) turns them into the files the shared readers already read, so no
reader changes. This document gives each format, one full example and the compiled output.

```sh
cargo run -p iaf-tools --bin iaf-sim -- all [iaf-2026/data] [assets]   # or db / missions / own alone
```

| step | reads | writes (under `assets/`) |
|---|---|---|
| `iaf-sim db` | `data/db/units/*.json`, `data/db/weapons/*.json` | `converted/missions/sim.bdb.json`; the key `"sim.bdb"` of `converted/objects/objects.json` (the other keys stay); `converted/own/resource/weaponsmotion/weapons.ibx` |
| `iaf-sim missions` | `data/missions/*.json`, the units | `converted/iaf-2026/missions/<id>.json`, `converted/iaf-2026/missions/missionlist.json` (menu id → `[<id>]`) |
| `iaf-sim own` | `data/sounds/soundprop.json`, `data/sounds/voices.json`, `data/sounds/*.wav`, `data/keys.json` | `converted/own/resource/soundfiles/` (`soundprop.trx`, `phrasetemplates.trx`, `phraseparticalsdata.trx`, the clips; other files there are removed), `converted/own/keys.json` ([sound.md](sound.md)) |

Nothing is read from `assets/install` or the exe. The base positions come from
`crates/iaf-flight/data/real_runways.csv` (OpenStreetMap runways) and the georeference's control points
(`crates/iaf-tools/data/georef_points.json`), both in the repo.

## 1. Rules every file follows
- **Sources.** Every figure has an entry in `sources`, by field name (a nested one by a dotted name:
  `"motion._limitVel"`, `"loadout.20mm"`, `"start.lat"`). The entry is a footnote name of the file's `footnotes`,
  `"inferred"` or `"open"`, or several of them joined by commas. The compiler refuses a figure without one.
  In a mission the figures are the time, the wind, the start's place, heading and elevation, and the route (one
  source for a whole route); each flight (`start.*`, `route`) and each target or SAM site (`lat`, `lon`, `heading`,
  `alt_m`, `route`, `speed_kmh`) holds its own `sources`, naming the mission's footnotes.
- **Open values.** A field the format needs but no source gives holds a value marked `"open"`, and `notes` says
  what holds it until a source is found.
- **Notes.** `notes` explains a value by field name. No compiler reads it.
- **Numbers.** `number` is the record's id in the compiled bdb (1–999, unique per kind). Missions and loadouts
  name units and weapons by `id`, never by number.

## 2. The readable → hex mapping
One table in `sim.rs`, `FIELDS`, maps every readable field to its hex key; `CLASSES`, `KINDS` and `SIDES` map the
named values to codes. The Objects fields whose meaning is open (`OBJECT_REST`) get the format's usual values; no
reader takes them.

| record | readable | hex | named values |
|---|---|---|---|
| unit | `id`, `category` (from `class`), `label`, `brain`, `radius_m`, `strength`, `collider`, `class`, `type` | `0x514`, `0x51e`, `0x528`, `0x532`, `0x564`, `0x56e`, `0x58c`, `0x5aa`, `0x5b4` | class `fighter` = 0x1c, "Controlled aircraft" |
| unit (model) | `id`, `model`, `scale` | Present `0x640`, `0x64a`, `0x65e`; the unit's `0x53c` = its number | — |
| weapon | `name`, `kind`, `model`, `drag`, `power`, `blast_m`, `kg` (→ pounds), `generation`, type (from `kind`) | `0x708`, `0x712`, `0x730`, `0x73a`, `0x744`, `0x74e`, `0x758`, `0x762`, `0x780` | `gun` 565, `chaff` 540, `flare` 550, `ir_missile` 570, `bomb` 500 |
| mission | `title.en`, `time`, `wind_kt`, `wind_from`, `win.en`, `lose.en`, `category` | misc `0x44c`, `0x460`, `0x46a`, `0x474`, `0x47e`, `0x492`, `0x4d8` | — |
| placed unit | name, unit, side, x, y, `alt_m`, `heading` | `0x2bc`, `0x2c6`, `0x2d0`, `0x2e4`, `0x2ee`, `0x2f8`, `0x302` | side `blue` 1, `red` 2 |

## 3. Units: `data/db/units/<id>.json`
A unit record holds what a mission needs of a unit. A flyable jet's behaviour stays in its aircraft definition
(`game/extra/planes/<id>/airframe.json`); the record names it in `airframe`.

| field | meaning |
|---|---|
| `id`, `number`, `name`, `label` | the unit's id, bdb number, full name and short label |
| `class` | the bdb class by name (§2) |
| `type` | the type code the shared code keys on; codes from 1000 are ours (docs/adding-a-plane.md §1) |
| `airframe` | the aircraft definition of a flyable jet; the compiler checks it exists and writes it unhexed as `"airframe"` in the Objects row |
| `model`, `scale` | the model under `assets/converted/objects/` (empty: none) and its drawn scale (1 = true size) |
| `radius_m` | the unit's radius; the blast rules take half of it (docs/damage.md §2.1) |
| `strength` | hit points on our damage scale (§6) |
| `loadout` | weapon id → count for the gun, chaff and flare stations (9–11) |
| `pylons` | station `A`..`I` → `{"weapon", "count"}` (none on the MVP jets) |
| `range_km`, `min_range_km`, `ceiling_m`, `floor_m`, `speed_ms`, `mach`, `radar_km`, `g_limit` | the threat set's figures (threats.md §6), checked for sources; no shared reader takes them yet |

The three MVP jets: the Sufa (`f16i`, number 1, type 100), the Barak (`f16d`, 2, type 100) and the F-35I (`f35i`,
3, type 1000). The Sufa and the Barak share the F-16's type code, which the shared code keys the F-16 family on;
their aircraft definitions tell them apart. `airframe::id_for(100, …)` picks `f16` or `f16i` by the F-16 switch alone, so the sim's settings (item A1) set that switch from the player's Objects row's `"airframe"` (2026-11-02). They carry the gun, chaff and flare and no pylon stores. Their `model`
is empty: the player's jet is drawn from its aircraft definition, and the sim's own model index comes later.

Example, `iaf-2026/data/db/units/f16i.json`:
```json
{
  "id": "f16i",
  "number": 1,
  "name": "F-16I Sufa",
  "label": "F-16I",
  "class": "fighter",
  "type": 100,
  "airframe": "f16i",
  "model": "",
  "scale": 1.0,
  "radius_m": 4.98,
  "strength": 300,
  "loadout": { "20mm": 511, "chaff": 60, "flare": 60 },
  "pylons": {},
  "sources": {
    "type": "inferred",
    "scale": "inferred",
    "radius_m": "w-f16",
    "strength": "inferred",
    "loadout.20mm": "gdots-f16",
    "loadout.chaff": "open",
    "loadout.flare": "open"
  },
  "notes": {
    "type": "the F-16's type code, the one the shared code keys the F-16 family on; the airframe definition f16i makes it the Sufa",
    "model": "none: the player's jet is drawn from its airframe definition (game/extra/planes/f16i/airframe.json)",
    "scale": "1: our models are built true size",
    "radius_m": "half the span over the wingtip rails, 9.96 m",
    "strength": "our damage scale's fighter (iaf-2026/docs/data-formats.md, damage scale)",
    "loadout.20mm": "M61A1, 511 rounds (the F-16's; the two-seat Sufa's count is not published, inferred the same)",
    "loadout.chaff": "no public count found; 60 held until one is",
    "loadout.flare": "no public count found; 60 held until one is"
  },
  "footnotes": {
    "w-f16": "Wikipedia, \"General Dynamics F-16 Fighting Falcon\" (span 32 ft 8 in, 9.96 m), https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon",
    "gdots-f16": "General Dynamics OTS, \"F-16 20mm Gatling gun system\" (511 rounds), https://www.gd-ots.com/wp-content/uploads/2017/11/F-16.pdf"
  }
}
```

## 4. Weapons: `data/db/weapons/<id>.json`

| field | meaning |
|---|---|
| `id`, `number`, `name` | the weapon's id, bdb number and the name the shared code finds it by |
| `kind` | the weapon kind by name (§2), which gives its type code and station |
| `generation` | the missile generation (weapons.ibx's: 3 = 1983–1995, 4 = from 1995); 0 otherwise |
| `model` | the model under `assets/converted/objects/` (empty: none) |
| `kg` | the weight (compiled to whole pounds, as the bdb holds it) |
| `power`, `blast_m` | the warhead on our damage scale (§6) and the blast's zero-damage edge |
| `drag` | the carriage drag on the jet |
| `motion` | the weapons.ibx fields of its section (`_velocityJump`, `_absAcceleration`…, docs/weapons.md); a field left out takes the reader's default |

Names and numbers the shared code relies on:
- `"20 MM"` (number 25), `"Chaff"` (33) and `"Flare"` (34): `player_aircraft.gd` `f35i_object` loads these numbers,
  and `real_weapons.gd` keys the M61A1 on the name.
- `"AIM-9M"` and `"MK-84"`: `modern_weapons.gd` builds the AIM-9X on the first and the GBU-31, BLU109, GBU-39 and
  GBU-28 on the second, by name. The Python 5 (on `"PYTH-4"`), GBU-32 (`"MK-83"`) and GBU-38 (`"MK-82"`) wait for
  their base records (item D2).

weapons.ibx gets one `[WEAPONnnn]` section per weapon with `type = generation · 1000 + type code`, and the first
weapon of each type code also as that code's default section (`weapon_db.gd motion_for` falls back to it), unless a
generation-0 weapon of that code has its own; two weapons on one section are refused. The game does not read this
file yet: `weapon_db.gd` reads the install's weapons.ibx, and the reader hook (`Settings.install_dir()` pointing at
`converted/own/`) comes with item A1. `test_sim_data.gd` reads it through `weapon_db.gd`'s own parser meanwhile.

Example, `iaf-2026/data/db/weapons/aim-9m.json`:
```json
{
  "id": "aim-9m",
  "number": 1,
  "name": "AIM-9M",
  "kind": "ir_missile",
  "generation": 3,
  "model": "",
  "kg": 86,
  "power": 400,
  "blast_m": 9,
  "drag": 0,
  "motion": {
    "_chaseType": 2.0,
    "_absAcceleration": 120.0,
    "_spiralAccelBeta": 0.141,
    "_timeAcceleration": 19.7,
    "_timeConstVel": 0.0,
    "_timeDecceleration": 0.0,
    "_timeConstOrientation": 0.5
  },
  "sources": {
    "kg": "ds-aim9",
    "power": "inferred",
    "blast_m": "ds-aim9",
    "drag": "open",
    "motion._chaseType": "inferred",
    "motion._absAcceleration": "inferred",
    "motion._spiralAccelBeta": "inferred, ds-aim9",
    "motion._timeAcceleration": "inferred, f16net",
    "motion._timeConstVel": "inferred",
    "motion._timeDecceleration": "inferred",
    "motion._timeConstOrientation": "inferred"
  },
  "notes": {
    "number": "ours; modern_weapons.gd finds its base by the name",
    "name": "the base of the AIM-9X (modern_weapons.gd RECORDS)",
    "generation": "the third generation (weapons.ibx's generations: 1983-1995)",
    "power": "one hit destroys a fighter of strength 300 (our damage scale)",
    "blast_m": "the AIM-9A / B's effective kill radius, about 9 m (the AIM-9M's is not published)",
    "drag": "carriage drag: none until a source gives one",
    "motion._chaseType": "2 = proportional navigation",
    "motion._absAcceleration": "Mach 0.7 to Mach 2.5 in about 5 s of motor burn (the burn time is open)",
    "motion._spiralAccelBeta": "top speed a / beta = Mach 2.5 (851 m/s): 120 / 851",
    "motion._timeAcceleration": "the burn with which the missile flies 17.7 km from 250 m/s before its flight ends 6 s after the burn (real_weapons.gd's rule)",
    "motion._timeConstOrientation": "flies straight 0.5 s off the rail"
  },
  "footnotes": {
    "ds-aim9": "designation-systems.net, \"Raytheon AIM-9 Sidewinder\" (AIM-9L / M 86 kg, Mach 2.5+; AIM-9A / B effective kill radius about 9 m), https://www.designation-systems.net/dusrm/m-9.html",
    "f16net": "F-16.net, \"AIM-9 Sidewinder\" (AIM-9L / M / P 17.7 km), https://www.f-16.net/f-16_armament_article1.html"
  }
}
```

## 5. Missions: `data/missions/<id>.json`

| field | meaning |
|---|---|
| `id` | the compiled file's name (letters, digits, `_`, `-`) |
| `menu_id` | the key in the compiled `missionlist.json`; ours from 2000 |
| `title`, `briefing`, `win`, `lose` | `{"en", "he"}`; the English title and win / lose texts fill the misc header, all four go to the compiled file's own `sim` key |
| `category`, `time`, `wind_kt`, `wind_from` | the misc header: category, start time `HH:MM`, wind |
| `start` | the player's flight (Alpha): `unit`, `count` (1 or 2), `base` (real_runways.csv's real name without " AB"), `elevation_m`, and `at`: `"parking"` with `lat`, `lon`, `heading` (true), or `"runway"` with `runway` (a designator end, "25R") |
| `route` | the player's waypoints: `lat`, `lon`, `alt_m`, and `speed_kmh` or `t_s`. The compiled waypoint holds the planned arrival time in sim seconds (docs/ai.md §7.2): `t_s`, else the time from the flight's start along the legs at each point's speed. No route gives set_flight's one point 20 km ahead |
| `runway` | the runway the mission's tower clears (kept in `sim` for item E3) |
| `note` | a caveat the compiler prints and keeps in `sim` (Nevatim's: no game base yet) |
| `flights` | Bravo..Delta: `unit`, `count`, `start` {`lat`, `lon`, `heading`, `alt_m`}, `route` |
| `targets`, `sam_sites` | placed units: `unit`, `name`, `side` (default red), `lat`, `lon`, `alt_m`, `heading`, optional `route` [{`lat`, `lon`}, at least two] and `speed_kmh`; a target takes role 1, a SAM site role 2 |

How a mission compiles (`sim.rs compile_mission`): an empty mission with the seven parts (`skeleton`), then the
mission editor's builders: `blank`, `set_flight` for Alpha (Player1 at the start, role 0 "must survive") and the
other flights, `add_entity` and `set_role` for the placed units, `set_route` for their routes. A lat / lon becomes
engine metres through the georeference, and a true heading the engine frame's. The compiled file holds `"frame": "real"`: its
units stand at the real bases already, so World scale Real's base move (`mission_runtime.gd move_with_bases`) leaves
it as it is. A runway start stands
100 m in from the threshold (inferred), on the runway's heading.

Red flights (`set_red_flight`) wait for the threat set: that builder starts a flight at one of the 1998 game's bases.

The first six missions, two per MVP base (plan.md, MVP): start-up (`<base>_startup`) and take-off (`<base>_takeoff`)
at Ramon (Sufa, menu 2011 / 2012), Ramat David (Barak, 2021 / 2022) and Nevatim (F-35I, 2031 / 2032). Each jet
stands parked at the centre of an OpenStreetMap apron by the runways until item B2 gives the bases' real parking
spots. The take-off route is one point 10 km beyond the runway's far end, 900 m above the field. Their pass rules
come with item E3. Nevatim is not one of the game's bases (iaf.ibx) until item B2: it has no tower, lineup or
start rule, its jet stands at the real apron's place on the original terrain, and its take-off briefing promises no
tower calls; both Nevatim files say so in `note`.

Example, `iaf-2026/data/missions/ramon_takeoff.json`:
```json
{
  "category": "training",
  "time": "08:00",
  "wind_kt": 0,
  "wind_from": 0,
  "start": {
    "unit": "f16i",
    "base": "Ramon",
    "at": "parking",
    "lat": 30.7699701,
    "lon": 34.6595291,
    "heading": 337,
    "elevation_m": 648
  },
  "flights": [],
  "targets": [],
  "sam_sites": [],
  "sources": {
    "start.lat": "osm-apron",
    "start.lon": "osm-apron",
    "start.heading": "inferred",
    "start.elevation_m": "oa",
    "route": "inferred"
  },
  "notes": {
    "start": "the centre of an apron by the runways until B2 gives the base's real parking spots",
    "start.heading": "facing the nearest runway",
    "route": "the departure point: 10 km beyond runway 25R's far end on its heading, 900 m above the field"
  },
  "footnotes": {
    "osm-apron": "OpenStreetMap contributors, ODbL 1.0, https://www.openstreetmap.org/copyright: aeroway=apron way 1496591869 (its centre, Overpass API, 2026-11-02), https://www.openstreetmap.org/way/1496591869",
    "oa": "OurAirports, airports.csv (public domain; LLRM elevation 2126 ft), https://davidmegginson.github.io/ourairports-data/airports.csv"
  },
  "id": "ramon_takeoff",
  "menu_id": 2012,
  "title": {
    "en": "Take-off from Ramon",
    "he": "המראה מרמון"
  },
  "briefing": {
    "en": "Ask the tower for start-up, taxi and take-off, taxi to runway 25R and take off on its heading.",
    "he": "בקש מהמגדל התנעה, הסעה והמראה, הסע למסלול 25R והמרא בכיוונו."
  },
  "win": {
    "en": "Mission - successful. Airborne with the gear up.",
    "he": "המשימה הצליחה. באוויר עם כן נסע אסוף."
  },
  "lose": {
    "en": "Mission - failed. Better try again.",
    "he": "המשימה נכשלה. נסה שוב."
  },
  "runway": "25R",
  "route": [
    {
      "lat": 30.73737,
      "lon": 34.55702,
      "alt_m": 1548,
      "speed_kmh": 600
    }
  ]
}
```

## 6. Our damage scale
The shared damage model compares a warhead's power with a unit's strength (docs/damage.md §2). No public source gives
either, so the sim sets its own scale (inferred): a fighter has strength 300 (the value `real_weapons.gd`'s blast
rule assumes), a 20 mm hit does 100 (three hits destroy a fighter), an AIM-9M hit 400 (one hit), and a bomb
50 points per kilogram of explosive (the Mk 84: 429 kg → 21,450). Item D2 calibrates the scale against the threat set.

## 7. Where the compiled files go, and why
- `sim.bdb.json` sits beside the original's `default6_1.bdb.json`, as the brief asks: `MissionRuntime.load_bdb` reads
  `converted/missions/<bdb>.json`, and the bdb's `_file` (`"sim.bdb"`) is how `weapon_db.gd` finds its models in
  `objects.json`.
- The missions go to `converted/iaf-2026/missions/`, not `converted/missions/` (accepted by the orchestrator,
  2026-11-02). The Rust tests that read every
  file in `converted/missions` take each mission there as an original (the calibration of `mission_edit.rs` counts
  the missions that can never pass), and a sub-folder there breaks the ones that read every entry as a file. The
  game today reads only `converted/missions/missionlist.json`; the sim's front end (item A1 / E2) hands a compiled
  mission to the flight as the mission editor's Fly does (`Settings.mission_files_override`), which
  `tests/godot/test_sim_data.gd` uses.
- The original's tools leave the sim's output out: `iaf-convert aircraft` / `objects` skip `sim.bdb.json`
  (`aircraft.rs read_bdbs`), and the scenery's and roads' fingerprint (`scenery.rs converted_inputs`) skips it and
  hashes `objects.json` without its `"sim.bdb"` key, so compiling the sim makes no scenery again.
- `iaf-sim db` changes only the `"sim.bdb"` key of `objects.json`; a missing file starts empty, any other read
  error stops the step. `iaf-convert objects` rewrites the original's keys and keeps the ones it did not write
  (`convert.rs keep_others`), so the two steps run in either order.

## 8. Checks
- `cargo test -p iaf-tools --lib sim::`: every data file compiles and loads as the game reads it (each entity's unit
  and each station's weapon exist in the bdb, each weapon type has a weapons.ibx section that the ini parser reads,
  the names the modern weapons base on exist, each mission's player must survive); a runway start takes the end its
  number names; a figure without a source is refused.
- `tests/godot/test_sim_data.gd`: runs `target/release/iaf-sim all` itself (`tools/test.sh` builds it; NEEDS DATA
  without it), which writes only the sim's own output into the shared `assets/`; then every compiled mission and sim.bdb through `MissionRuntime`, `PlayerAircraft.object_for` and
  `weapon_db.gd` (with the AIM-9X and GBU-31 built on our bases), each jet's `"airframe"`, every weapon's motion
  section through `weapon_db.gd`'s ibx reader, and the Ramon start-up flown to the jet standing on the ground.
- Further unit tests in `sim.rs`: only the player's jet must survive, placed units take the engine frame's heading,
  duplicate ids / too many flights / two weapons on one ibx section are refused, the original's converters skip
  `sim.bdb.json`; in `scenery.rs`: the fingerprint is the same with and without the sim's output.

## 9. Sources of the first data
Each data file holds its own footnotes. The ones the first data uses:
- the runways (real_runways.csv) and the parking aprons: OpenStreetMap[^osm]; runway widths and field elevations:
  OurAirports[^oa];
- the jets' spans and the F-35I's gun: Wikipedia[^w-f16][^w-f35]; the F-16's 511 rounds: General Dynamics OTS[^gdots];
- the M61A1's muzzle velocity[^m61], the AIM-9M[^ds-aim9][^f16net] and the Mk 84[^mk84].

[^osm]: OpenStreetMap contributors, ODbL 1.0, https://www.openstreetmap.org/copyright (runway and apron ways via the Overpass API, 2026-10-20 and 2026-11-02).
[^oa]: OurAirports, runways.csv and airports.csv (public domain), https://davidmegginson.github.io/ourairports-data/
[^w-f16]: Wikipedia, "General Dynamics F-16 Fighting Falcon", https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon
[^w-f35]: Wikipedia, "Lockheed Martin F-35 Lightning II", https://en.wikipedia.org/wiki/Lockheed_Martin_F-35_Lightning_II
[^gdots]: General Dynamics OTS, "F-16 20mm Gatling gun system", https://www.gd-ots.com/wp-content/uploads/2017/11/F-16.pdf
[^m61]: Wikipedia, "M61 Vulcan", https://en.wikipedia.org/wiki/M61_Vulcan
[^ds-aim9]: designation-systems.net, "Raytheon AIM-9 Sidewinder", https://www.designation-systems.net/dusrm/m-9.html
[^f16net]: F-16.net, "AIM-9 Sidewinder", https://www.f-16.net/f-16_armament_article1.html
[^mk84]: Wikipedia, "Mark 84 bomb", https://en.wikipedia.org/wiki/Mark_84_bomb
