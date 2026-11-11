# Modern IAF: JSON or SQLite for the sim's data

**Terms:** compiled data = the files `iaf-sim` writes under `assets/converted/` from the authored files in
`modern-iaf/data/`; records = the files the game writes while it runs, under `user://`; "inferred" = our own
reasoning.

This page weighs moving the sim's data from JSON files to SQLite. Sections 1 to 4 are the design note; §5 is what
was built from it (2026-11-09): the records are in SQLite, the compiled data stays JSON. The user's rule (plan.md, 3 November 2026) sets the frame: authored data stays JSON; data that changes in the game
(the pilot log, the debriefs) is the candidate for SQLite through a Rust crate.

## 1. What the sim stores today

Measured 2026-11-09 on the development machine's `assets/` after `iaf-sim db` and `iaf-sim airbases`.

| data | file | size | written by | read by |
|---|---|---|---|---|
| unit and weapon database | `converted/missions/sim.bdb.json` | 4.5 KB | `iaf-sim db` | `shared/mission/mission_runtime.gd` (`load_bdb`) |
| model index | `converted/objects/objects.json` (the `"sim.bdb"` key) | 10 KB (whole file, shared with the original game) | `iaf-sim db`, `iaf-convert objects` | `weapon_db.gd` |
| missions | `converted/modern-iaf/missions/*.json` | 30 KB in 7 files | `iaf-sim missions` | `mission_runtime.gd`, the front end |
| keys | `converted/own/keys.json`, `keys_laptop.json` | 25 KB each | `iaf-sim own` | `Settings.keys_file()` readers |
| airbases | `converted/terrain/israel/airbases.json` | 132 KB | `iaf-sim airbases` | `shared/terrain/airbases.gd` |
| theatre | `converted/terrain/israel/meta.json`, `water.json`, `scenery/theatre.json` | 99 KB, 821 KB, 177 KB | `iaf-sim terrain`, `airbases`, `scenery` | the terrain and scenery readers |
| cockpit data | `converted/own/cockpits/` | 479 KB (JSON and pictures) | `iaf-sim own` | the cockpit code |
| debriefs | `user://debriefs/debrief-<date>-<mission>.json` (before §5) | one file per flight | `flight/sim_flight.gd` | the front end's Debrief sheet |
| pilot log | `user://pilots/<id>.json` (before §5) | one file, grows by one attempt per flight | `flight/sim_flight.gd` | the front end's Home and Pilot log |
| devices | `user://devices.json` | one small file, the user's overrides only | `iaf_tools::devices` (`IafDevices`) | the key table and the joystick reader |

Every one of these is read whole, once, when its screen or the flight starts (`Settings.load_json`: open, parse,
done). None is queried by a key or a range. The compiled data is rewritten only by a setup step. The records grow
by one file (debrief) and one entry (pilot log) per flight.

## 2. SQLite through Rust

- **The crate.** `rusqlite` with the `bundled` feature compiles SQLite's C source into the binary, so nothing is
  needed on the player's machine on Linux, macOS or Windows. The workspace already depends on it:
  `crates/iaf-tools/Cargo.toml` (`rusqlite` 0.41, `bundled`), used by `mapi2015_fetch.rs`. The game's extension
  `libiaf_godot` links `iaf-tools`, and its release build already holds SQLite (measured: 297 `sqlite3_` symbols in
  the 21 MB library). Using it for records adds no dependency and no measurable size (inferred).
- **Godot's side.** GDScript has no SQLite reader of its own. The records would go through a gdext class (as
  `IafDevices` does for `devices.json`): for example `log_attempt(debrief)` and `attempts(mission)`, with the
  database at `user://modern-iaf.sqlite` (inferred design).
- **The setup pipeline.** The compiled data would need a new writer per step and a schema per file; each step's
  stamp and the scenery's fingerprint (which hashes `objects.json`) would follow the new files. The shared readers
  (`mission_runtime.gd`, `airbases.gd`, the key table) read JSON for the original game too, so each would need a
  second path or a converter back to JSON (inferred: several days of work for no new behaviour).

## 3. What each side gains

| | JSON files | SQLite |
|---|---|---|
| compiled data | the shared readers take it as it is; a person can open a file; `git diff`-able test fixtures | one file to ship; typed columns; nothing the game needs today |
| records | one write per flight; a broken write loses one file; the original game's pilot-log shape is kept | atomic writes and queries (best time, attempts per mission) without reading every debrief; one file to back up |
| cost | the front end lists `user://debriefs/` and parses each file it shows; this grows with the number of flights | a schema, a migration rule when it changes, and a gdext API |

At today's sizes (a few kilobytes per record, a few hundred kilobytes for the largest compiled file) parsing JSON
is not a measurable part of a start (inferred: the seven compiled mission files are 30 KB).

## 4. Recommendation

- **Compiled data: stay with compact JSON.** It is written once by setup, read whole, and shared with the original
  game's readers. SQLite would add a second format to every shared reader and gain nothing.
- **Records: move the pilot log and the debriefs to SQLite when the logic moves to Rust.** plan.md's E2 row already
  moves the pilot log and debrief logic (attempts, a mission's status and best time, the log append) from
  `menu/front_end.gd` and `flight/sim_flight.gd` into one crate function beside `training.rs`. That function is the
  place for one `rusqlite` database in `user://`, with two tables (attempts, debriefs) and the same fields as
  [data-formats.md](data-formats.md) §13. The flight recording (`user://flights/*.jsonl`) stays a file: it is
  streamed while flying and read by `tools/flight_timeline.py`.
- **Keep the original game's pilot files as they are.** reborn's `iaf-reborn/menu/pilots.gd` reads the original's
  shape; the sim's records are its own and need not match it.
- **`devices.json` stays JSON.** It is one small file of overrides, read once.

## 5. What is built (2026-11-09)

The records follow §4: one SQLite database, `user://modern-iaf.sqlite` (tests: `<temp>/modern-iaf-records/`, or
the folder a test gives `sim_flight.gd`'s `out_dir`), owned by `crates/iaf-tools/src/pilot_log.rs`
(`iaf_tools::pilot_log`) and reached from GDScript through one class, `IafPilotLog`
(`crates/iaf-godot/src/pilot_log.rs`). It is a module of `iaf-tools` beside `training.rs` and `devices.rs`, not a
crate of its own: it is one file, and `iaf-tools` already links `rusqlite`.

| table | columns |
|---|---|
| `pilots` | `id` (14, the default pilot; a new pilot from the front end's pilot list takes the next free id); since version 2 the profile of the Pilot screen: `name`, `nickname` (the one every screen shows), `picture` (the picture file's path relative to the database's folder, `pictures/pilot-<id>.<ext>`; `''` = none) |
| `sorties` | `id` (autoincrement: the debrief's number), `pilot`, `mission_id` (the menu id), `mission` (the readable name), `date`, `result` (1 pass, 0 fail), `elapsed_s`, `debrief` (the whole record as JSON text, NULL when it was lost); since version 3 `plane` (the jet's unit id, `f16i`; `''` for a sortie stored before) |
| `loadouts` | since version 4: `pilot`, `plane` (the jet's unit id), `stations` (the loadout as JSON text, real station number → the store and how many, `{"3": {"id": "mk-82", "count": 3}}`; a plain id, the first build's form, reads as one); one row per pilot and jet, none while the loadout is the record's default |

- **Schema version.** SQLite's `user_version`; `pilot_log::open` runs the missing migrations (`MIGRATIONS`, one SQL
  batch per version) in one immediate transaction, so a second process waits and finds the schema made; a file at this build's
  version is opened without a write. Each call opens the file and closes it when it returns (SQLite's busy timeout,
  5 s, lets the game and a test share it). A file from a
  newer build is refused (an error in the log; the screens show no flights).
- **Import.** The step from version 0 (a new file) also reads the JSON records from before the database once: every
  `pilots/<id>.json` in the database's folder and the debrief each attempt names, by file name in `debriefs/`. The
  sorties go in oldest first; an attempt whose debrief file is gone keeps its result and date (its Pilot log row
  cannot open). The import is part of the migration's transaction, so it runs once and never half. The JSON files
  stay as they are: nothing is renamed or deleted, so a failed write cannot lose a record, and an older build still
  reads its own files (inferred: the safer of the two choices).
- **The calls.** `log_sortie(db, pilot, mission_id, debrief)` stores a flight (`sim_flight.gd` after
  `IafTraining.score`) and answers its id (`Settings.flown_sortie`); `sorties(db, pilot)` answers the Pilot log's
  rows; `summary(db, pilot)` answers the flights, flight time and last result and Training's status and best time
  per mission; `logbook(db, pilot, units)` answers the Pilot screen's logbook (per plane: `time_s`, `flights`,
  `passes`, `fails` and its `missions` with the same counts; `units`, {menu id: unit id}, places a sortie without its
  plane); `reset(db, pilot)` deletes the pilot's sorties (the profile stays); `delete_pilot(db, pilot)`
  deletes the pilot: its sorties, its `loadouts` rows, its row and its picture file;
  `pilots(db)` lists the pilots with a
  name; `add_pilot(db, name, nickname)` makes one and answers its id; `debrief(db, id)` answers one record; `pilot(db, pilot)` answers the profile ({name, nickname,
  picture} with the picture's absolute path), `set_pilot(db, pilot, name, nickname)` stores the name and nickname, and
  `set_picture(db, pilot, src)` copies the picture file into `pictures/` beside the database (the pilot's earlier
  one removed; an empty `src` removes it) and stores its path. The front end only displays what they answer.
- **Version 2** (2026-11-09) adds the profile's three columns to `pilots` (`ALTER TABLE … ADD COLUMN`, empty by
  default): a version-1 file keeps its pilots and sorties.
- **Version 3** (2026-11-10) adds `sorties.plane`, filled from the debrief's `plane` where it has one;
  `sim_flight.gd` writes the mission's unit as the debrief's `plane`.
- **Version 4** (2026-11-10) adds `loadouts`, the briefing's loadout editor's ([front-end.md](front-end.md) §10):
  `loadout(db, pilot, plane)` answers the stored loadout (none: the record's default), `set_loadout(db, pilot, plane,
  stations)` stores it, `set_loadout(…, none)` (`""` from GDScript) deletes it (Reset). Loading checks it against the
  unit record (`loadout::parse` keeps only what a station takes), so a record that changes its rules never flies a
  store a station no longer takes.
- **Reading a record outside the game.** `sqlite3 modern-iaf.sqlite "SELECT debrief FROM sorties WHERE id = 3" >
  debrief.json` gives the file `tools/flight_timeline.py --debrief` takes.
- **Check.** `cargo test -p iaf-tools --lib pilot_log` (the schema at its version, a newer one refused, a sortie round
  trip with the summary, the JSON import run twice, the profile and its picture round trip, a version-1 file migrated, the logbook per plane and Reset, the pilot list and
  a new pilot, a version-2 file migrated, the loadouts per pilot per jet and a version-3 file migrated); `modern-iaf/tests/test_front_end.gd` (imported records on the
  Debrief, Home, Training and Pilot log screens, then a flown sortie's debrief) and `test_mvp.gd` (each flight's
  sortie and its pass in the summary).
