# Modern IAF: JSON or SQLite for the sim's data

**Terms:** compiled data = the files `iaf-sim` writes under `assets/converted/` from the authored files in
`iaf-2026/data/`; records = the files the game writes while it runs, under `user://`; "inferred" = our own
reasoning.

This page weighs moving the sim's data from JSON files to SQLite. It is a design note: nothing here is built.
The user's rule (plan.md, 3 November 2026) sets the frame: authored data stays JSON; data that changes in the game
(the pilot log, the debriefs) is the candidate for SQLite through a Rust crate.

## 1. What the sim stores today

Measured 2026-11-09 on the development machine's `assets/` after `iaf-sim db` and `iaf-sim airbases`.

| data | file | size | written by | read by |
|---|---|---|---|---|
| unit and weapon database | `converted/missions/sim.bdb.json` | 4.5 KB | `iaf-sim db` | `shared/mission/mission_runtime.gd` (`load_bdb`) |
| model index | `converted/objects/objects.json` (the `"sim.bdb"` key) | 10 KB (whole file, shared with the original game) | `iaf-sim db`, `iaf-convert objects` | `weapon_db.gd` |
| missions | `converted/iaf-2026/missions/*.json` | 30 KB in 7 files | `iaf-sim missions` | `mission_runtime.gd`, the front end |
| keys | `converted/own/keys.json`, `keys_laptop.json` | 25 KB each | `iaf-sim own` | `Settings.keys_file()` readers |
| airbases | `converted/terrain/israel/airbases.json` | 132 KB | `iaf-sim airbases` | `shared/terrain/airbases.gd` |
| theatre | `converted/terrain/israel/meta.json`, `water.json`, `scenery/theatre.json` | 99 KB, 821 KB, 177 KB | `iaf-sim terrain`, `airbases`, `scenery` | the terrain and scenery readers |
| cockpit data | `converted/own/cockpits/` | 479 KB (JSON and pictures) | `iaf-sim own` | the cockpit code |
| debriefs | `user://debriefs/debrief-<date>-<mission>.json` | one file per flight | `flight/sim_flight.gd` | the front end's Debrief sheet |
| pilot log | `user://pilots/<id>.json` | one file, grows by one attempt per flight | `flight/sim_flight.gd` | the front end's Home and Pilot log |
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
