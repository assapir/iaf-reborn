# Modern IAF

Modern IAF (in Hebrew: הזרוע הארוכה) is a modern-day Israeli Air Force flight sim. It runs on this repo's engine, beside the original game, and
reads only our own or openly licensed data: nothing from the original game's CDs. The plan, the decisions and the
work items are in [plan.md](docs/plan.md); what the sim gives the original game is in [shared.md](docs/shared.md); what works today is in [status.md](docs/status.md).

## Run it
From the repo root:

```sh
./iaf2026-setup     # the setup wizard: builds the sim's data into assets/ (docs/setup.md)
./iaf2026           # builds the extension and starts the sim: its front end, Home (docs/front-end.md)
./iaf2026 -- --mission 2012   # flies one mission at once, then shows its debrief (2011 / 2012 Ramon, 2021 / 2022 Ramat David, 2031 / 2032 Nevatim; training.md §10)
IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path iaf-2026 -s ../iaf-2026/tests/test_m0_boot.gd --log-file <temp>
```

On Windows: `.\iaf2026-setup.ps1` and `.\iaf2026.ps1`. The launchers are named without the dash because a file
cannot share the `iaf-2026/` folder's name.

The M0 probe (`iaf-2026/tests/test_m0_boot.gd`) prints a `PASS`, `FAIL` or `NEEDS DATA` line per check:

- the sim reads no install (`Settings.install_dir()` does not exist) and reads its own data from
  `assets/converted/own`;
- the 1998-only switches hold the sim's values (`PROFILE` in `iaf-2026/sim_settings.gd`);
- the key table and the sound table hold rows;
- for the Sufa (Ramon), the Barak (Ramat David) and the F-35I (Nevatim): the start-up mission's object database,
  the jet's aircraft definition, the weapons' motion table, the 3D cockpit model and the flight model started from
  `converted/own/resource/md`;
- the terrain `converted/terrain/israel/meta.json` at 1:1 ([terrain.md](docs/terrain.md)), then a free flight of 5 s over
  it: the heights at the jet are readable and below it; the 3D-only cockpit in flight (item E1).
- no reader asked for the original game's converted data during the probe's flights (`Settings.converted()`, item A4).

It prints `RESULT PASS` only when every check passes. A check whose data is not built yet prints `NEEDS DATA` with the
work item that builds it, and the probe then ends with `NEEDS DATA` (exit code 2); `tools/test.sh` does not count
that as a failure.

## Folders
| folder | holds |
|---|---|
| `iaf-2026/` | the sim's Godot project: `project.godot` ("Modern IAF", its own `user://`), `iaf.gdextension` (the same Rust extension as the original game) |
| `iaf-2026/shared` | a link to the repo's `shared/` (the engine code both projects use; on Windows a junction made by `tools/windows/links.ps1`) |
| `iaf-2026/main.tscn`, `iaf-2026/menu/` | the front end: the main scene, its screens, strings and look ([front-end.md](docs/front-end.md)) |
| `iaf-2026/sim_settings.gd` | the `Settings` autoload: the shared settings with the sim's data roots and profile |
| `iaf-2026/data/` | the authored data: units, weapons, missions, airbases, sounds, keys ([data-formats.md](docs/data-formats.md), [sound.md](docs/sound.md), [airbases.md](docs/airbases.md)) |
| `iaf-2026/tests/` | the sim's headless tests (they extend `tests/godot/base.gd`) |
| `iaf-2026/docs/` | the sim's docs and research |
| `assets/converted/own/` | the sim's compiled data in the original's resource layout: `resource/md`, `resource/soundfiles`, `resource/weaponsmotion`, `keys.json`, `iaf.ibx`, `terraintype.dat` (`iaf-sim airbases`) |
| `assets/converted/iaf-2026/missions/` | the compiled training missions |

## How the sim reads its data
The shared code reads its files through the `Settings` calls below. The sim's `sim_settings.gd` answers them with its
own paths; the original game's `shared/settings.gd` answers with the install's.

| call | original game | Modern IAF |
|---|---|---|
| `install_dir()` | `assets/install` | `assets/iaf-2026-reads-no-install` (does not exist) |
| `own_dir()`: flight model, sounds, radio phrases, weapons' motion, `iaf.ibx`, `terraintype.dat` | `assets/install` | `assets/converted/own` |
| `keys_file()` | `assets/converted/keys.json` | `assets/converted/own/keys.json` |
| `fm_section(type)`: the player's flight-model type (`PlayerAircraft.profile`) | "": the converted aircraft descriptor's `fm_section` | by type code on the own `bd.ibx` (`IafFlight.fm_type`, `iaf_flight::fm_name_in`): 100 `F-16`, 110 `F-15`, 1000 `F-35I`; a code whose section the own `bd.ibx` lacks flies as the `F-16` (a warning) |
| `theatre_dir()`: the terrain `terrain.gd` streams | `converted/terrain/theatre` (`IAF_THEATRE=<name>`: `converted/terrain/<name>`) | `converted/terrain/israel` |
| `airbases_file()`: the runways, taxi lines and masks (Detailed airbases, the tower's wind turn) | `converted/terrain/airbases.json` | the theatre's own: `converted/terrain/israel/airbases.json` |
| `converted(rel)`: every path under `assets/converted` a shared script reads | `assets/converted/<rel>` | the same for `own/`, `terrain/israel/`, `iaf-2026/`, `missions/sim.bdb.json` and `objects/objects.json`; any other path is refused: a path that does not exist, an error naming the caller, counted in `rejected` |
| `planes_folder()`: the aircraft descriptors | `converted/planes` | `converted/own/planes` (the F-16's from our model, `iaf-sim own`) |
| `missions_folder()`: the menu missions and `missionlist.json` | `converted/missions` | `converted/iaf-2026/missions` |
| `default_bdb()`: the object database a jet's default load falls back on | `default6_1.bdb` | `sim.bdb` |
| `loading_screen_scene()`: the flight's loading screen | `shared/terrain/loading_screen.gd` (the menu art) | `flight/loading_screen.gd` ([front-end.md](docs/front-end.md)) |
| `original_art()`: the effects' sprites (flares, chaff, trails, afterburner) | true | false: a soft dot (`Img.soft_dot()`) |

The bases are `own_dir()`'s `iaf.ibx` (`iaf-sim airbases`, [airbases.md](docs/airbases.md) §9) at their real places,
so the sim never moves them: its `sync_bases()` sets up no World scale Real move. The tower's wind turn
(`IafBases.set_wind`) takes their runways from `Settings.airbases_file()`, the theatre's own `airbases.json`
(`converted/terrain/israel/airbases.json`; the original game's `converted/terrain/airbases.json`).

The gate is checked twice: `iaf-2026/tests/test_converted_gate.gd` fails on a `"converted/"` string in a shared script
outside its short list, and the M0 probe's line "no original converted data read" fails when any reader asked for a
refused path during its flights. The sim shows no in-flight message texts (`msgs()`: the original's `msgs.trx` is
not the sim's) until its own message table.

The sim's settings also fix the switches that pick between the 1998 game and our replacements (3D cockpit, detailed
models, world scale Real, flight and weapon data Real, the F-15I, no textured sky): the sim has no preferences row for
them.
`Settings.set_jet(airframe)` sets the F-16 switch from the jet flown: `f16i` flies as the Sufa, `f16` as the Barak.
`airframe_def(id)` merges the sim's own `res://data/planes/<id>.json` over the shared aircraft definition, where one
exists.
