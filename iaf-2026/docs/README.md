# IAF 2026

IAF 2026 is a modern-day Israeli Air Force flight sim. It runs on this repo's engine, beside the original game, and
reads only our own or openly licensed data: nothing from the original game's CDs. The plan, the decisions and the
work items are in [plan.md](plan.md); what works today is in [status.md](status.md).

## Run it
From the repo root:

```sh
./iaf2026-setup     # builds the sim's data into assets/ (iaf-sim all); its setup wizard comes with item A3
./iaf2026           # builds the extension and starts the sim; until its front end (item E2): the M0 probe
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
- the terrain `converted/terrain/israel/meta.json` at 1:1, then the heights and the 3D-only cockpit in flight.

It prints `RESULT PASS` only when every check passes. A check whose data is not built yet prints `NEEDS DATA` with the
work item that builds it, and the probe then ends with `NEEDS DATA` (exit code 2); `tools/test.sh` does not count
that as a failure.

## Folders
| folder | holds |
|---|---|
| `iaf-2026/` | the sim's Godot project: `project.godot` ("IAF 2026", its own `user://`), `iaf.gdextension` (the same Rust extension as the original game) |
| `iaf-2026/shared` | a link to the repo's `shared/` (the engine code both projects use; on Windows a junction made by `tools/windows/links.ps1`) |
| `iaf-2026/sim_settings.gd` | the `Settings` autoload: the shared settings with the sim's data roots and profile |
| `iaf-2026/data/` | the authored data: units, weapons, missions, airbases, sounds, keys ([data-formats.md](data-formats.md), [sound.md](sound.md), [airbases.md](airbases.md)) |
| `iaf-2026/tests/` | the sim's headless tests (they extend `tests/godot/base.gd`) |
| `iaf-2026/docs/` | the sim's docs and research |
| `assets/converted/own/` | the sim's compiled data in the original's resource layout: `resource/md`, `resource/soundfiles`, `resource/weaponsmotion`, `keys.json` (later `iaf.ibx`, `terraintype.dat`) |
| `assets/converted/iaf-2026/missions/` | the compiled training missions |

## How the sim reads its data
The shared code reads its files through three `Settings` calls. The sim's `sim_settings.gd` answers them with its own
paths; the original game's `shared/settings.gd` answers with the install's.

| call | original game | IAF 2026 |
|---|---|---|
| `install_dir()` | `assets/install` | `assets/iaf-2026-reads-no-install` (does not exist) |
| `own_dir()`: flight model, sounds, radio phrases, weapons' motion, `iaf.ibx`, `terraintype.dat` | `assets/install` | `assets/converted/own` |
| `keys_file()` | `assets/converted/keys.json` | `assets/converted/own/keys.json` |

The sim's settings also fix the switches that pick between the 1998 game and our replacements (3D cockpit, detailed
models, world scale Real, flight and weapon data Real, the F-15I): the sim has no preferences row for them.
`Settings.set_jet(airframe)` sets the F-16 switch from the jet flown: `f16i` flies as the Sufa, `f16` as the Barak.
`airframe_def(id)` merges the sim's own `res://data/planes/<id>.json` over the shared aircraft definition, where one
exists.
