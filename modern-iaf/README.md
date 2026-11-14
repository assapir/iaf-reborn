# Modern IAF

Modern IAF (in Hebrew: הזרוע הארוכה) is a modern-day Israeli Air Force flight sim. It runs on this repo's engine, beside the original game, and
reads only our own or openly licensed data: nothing from the original game's CDs. It needs no original game data: setup downloads open data once (the table under "Run it on a Mac") and builds the sim's data
into `assets/`. What it needs installed (Rust, Godot, GDAL): [docs/setup.md](docs/setup.md). The plan, the decisions and the
work items are in [plan.md](docs/plan.md); what the sim gives the original game is in [shared.md](docs/shared.md); what works today is in [status.md](docs/status.md).
The order of the work is in [plan.md, Priorities](docs/plan.md#priorities-the-user-8-november-2026).

## Run it
From the repo root:

```sh
./modern-iaf-setup     # the setup wizard: builds the sim's data into assets/ (docs/setup.md)
./start-modern-iaf     # builds the extension and starts the sim: its front end, Home (docs/front-end.md)
IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf -s ../modern-iaf/tests/test_m0_boot.gd --log-file <temp>
```

Developers: `./start-modern-iaf -- --mission <id>` flies one mission at once, then shows its debrief (2011 / 2012 Ramon,
2021 / 2022 Ramat David, 2031 / 2032 Nevatim; [training.md](docs/training.md) §10).

On Windows: `.\modern-iaf-setup.ps1` and `.\start-modern-iaf.ps1`.

After a pull from before 10 November 2026 (when the folder `iaf-2026/` became `modern-iaf/`), the sim's built data in
`assets/converted/iaf-2026` moves to `assets/converted/modern-iaf` by itself: `./start-modern-iaf`, the setup wizard
and `iaf-sim` rename it on their first run, with no rebuild and no download.

## Run it on a Mac
1. Get the code: `git pull` in your clone (or `git clone` the repo).
2. Install the tools with Homebrew, once:

   ```sh
   brew install rustup godot gdal
   "$(brew --prefix rustup)/bin/rustup" default stable
   ```

3. From the repo root:

   ```sh
   ./modern-iaf-setup               # the setup wizard: builds the sim's data into assets/
   ./start-modern-iaf               # Modern IAF
   ```

   The wizard's window opens after the build. Choose the language, then Next, Next, Install, and wait for Done.

   On a monitor beside a MacBook's Retina screen, the game restarts once at its first start there and then renders
   the monitor's own pixels (Godot otherwise renders twice the pixels across there). To undo it, delete the line
   `window/dpi/allow_hidpi=false` from `modern-iaf/override.cfg` while the game is closed
   ([docs/macos.md](../docs/macos.md) "A monitor beside a Retina screen").

What setup downloads, once (a later run reuses the files):

| what | size | kept in |
|---|---|---|
| the Copernicus GLO-30 heights | 0.6 GB | `assets/source/dem/` |
| ESA WorldCover's Sentinel-2 colour tiles | 11.4 GB | `assets/source/imagery/sentinel2/` |

To skip both downloads, copy `assets/source/dem/` and `assets/source/imagery/sentinel2/` from a computer that ran
`./modern-iaf-setup` into the same places in your clone. With every tile there, setup uses no network. The original
game's setup writes no `dem/` folder, and its `sentinel2/` may hold only some of the 21 tiles; setup downloads the
missing ones.

How long each step takes on the developer's Linux laptop (8 threads), measured 8 November 2026 ([setup.md](docs/setup.md)
§7); the Install's times with the tile cache are inferred until measured:

| step | time |
|---|---|
| the first build of the extension (inside `./modern-iaf-setup`) | 6.5 min |
| Godot's first import | 12 s |
| the wizard's Install, the first time | about 17 min: the downloads about 14 min (at 14 MB/s), the building about 3 min (inferred) |
| the wizard's Install again | a few minutes, no download (inferred) |
| a later `./start-modern-iaf` (build up to date) | seconds |

The M0 probe (`modern-iaf/tests/test_m0_boot.gd`) prints a `PASS`, `FAIL` or `NEEDS DATA` line per check:

- the sim reads no install (`Settings.install_dir()` does not exist) and reads its own data from
  `assets/converted/own`;
- the 1998-only switches and the look switches hold the sim's values (`PROFILE` in `modern-iaf/sim_settings.gd`);
- the key table and the sound table hold rows;
- for the Sufa (Ramon), the Barak (Ramat David) and the F-35I (Nevatim): the start-up mission's object database,
  the jet's aircraft definition, the weapons' motion table, the 3D cockpit model and the flight model started from
  `converted/own/resource/md`;
- the terrain `converted/terrain/israel/meta.json` at 1:1 ([terrain.md](docs/terrain.md)), then a free flight of 5 s over
  it: the heights at the jet are readable and below it; the 3D-only cockpit in flight (item E1).
- no reader asked for the original game's converted data or its install during the probe's flights
  (`Settings.converted()`, `Settings.install()`, item A4).

It prints `RESULT PASS` only when every check passes. A check whose data is not built yet prints `NEEDS DATA` with the
work item that builds it, and the probe then ends with `NEEDS DATA` (exit code 2); `tools/test.sh` does not count
that as a failure.

## Folders
| folder | holds |
|---|---|
| `modern-iaf/` | the sim's Godot project: `project.godot` ("Modern IAF", its own `user://`), `iaf.gdextension` (the same Rust extension as the original game) |
| `modern-iaf/shared` | a link to the repo's `shared/` (the engine code both projects use; on Windows a junction made by `tools/windows/links.ps1`) |
| `modern-iaf/main.tscn`, `modern-iaf/menu/` | the front end: the main scene, its screens, strings and look ([front-end.md](docs/front-end.md)) |
| `modern-iaf/sim_settings.gd` | the `Settings` autoload: the shared settings with the sim's data roots and profile |
| `modern-iaf/data/` | the authored data: units, weapons, missions, airbases, sounds, keys ([data-formats.md](docs/data-formats.md), [sound.md](docs/sound.md), [airbases.md](docs/airbases.md)) |
| `modern-iaf/tests/` | the sim's headless tests (they extend `tests/godot/base.gd`) |
| `modern-iaf/docs/` | the sim's docs and research |
| `assets/converted/own/` | the sim's compiled data in the original's resource layout: `resource/md`, `resource/soundfiles`, `resource/weaponsmotion`, `keys.json`, `iaf.ibx`, `terraintype.dat` (`iaf-sim airbases`) |
| `assets/converted/modern-iaf/missions/` | the compiled training missions |
| `assets/converted/terrain/israel/` | the theatre ([terrain.md](docs/terrain.md)), its airbases, its scenery and road layer (`scenery/`, `roads/`, [scenery.md](docs/scenery.md)) |

## How the sim reads its data
The shared code reads its files through the `Settings` calls below. The sim's `sim_settings.gd` answers them with its
own paths; the original game's `shared/settings.gd` answers with the install's.

| call | original game | Modern IAF |
|---|---|---|
| `install_dir()` | `assets/install` | `assets/iaf-2026-reads-no-install` (does not exist) |
| `install(rel)`: every path under the install a shared script reads (the cockpit bitmaps, `cockpits.ibx`, the full-screen MFD, the arming screen's jets, the gun's muzzle flash, the effects' original sprites) | `assets/install/<rel>` | refused: a path under `install_dir()` (does not exist), an error naming the caller the first time, counted in `rejected` as `install/<rel>`; each reader takes its no-file case |
| `own_dir()`: flight model, sounds, radio phrases, weapons' motion, `iaf.ibx`, `terraintype.dat`, the time of day's colours `defcolorset.tcs`, the missions' score file `resource/missions/scores.ibx` (the sim has neither yet: the flight's sky and light without the table, a bonus of 0) | `assets/install` | `assets/converted/own` |
| `keys_file()` | `assets/converted/keys.json` | `assets/converted/own/keys.json` |
| `joy_maps_dir()`: the joystick maps | the install's `resource/menu/joy` (the `.joy` files) | `modern-iaf/data/devices` (the sim's JSON maps; the `.joy` reader finds none there) |
| `joystick_connected(name)`: a joystick connected | nothing | the device map's buttons into `Joystick.default_buttons`; `apply_devices()`: the device map's and the store's axes, invert and dead zones into `joy_axes` and `Joystick.tune` |
| `fm_section(type)`: the player's flight-model type (`PlayerAircraft.profile`) | "": the converted aircraft descriptor's `fm_section` | by type code on the own `bd.ibx` (`IafFlight.fm_type`, `iaf_flight::fm_name_in`): 100 `F-16`, 110 `F-15`, 1000 `F-35I`; a code whose section the own `bd.ibx` lacks flies as the `F-16` (a warning) |
| `theatre_dir()`: the terrain `terrain.gd` streams | `converted/terrain/theatre` (`IAF_THEATRE=<name>`: `converted/terrain/<name>`) | `converted/terrain/israel` |
| `airbases_file()`: the runways, taxi lines and masks (Detailed airbases, the tower's wind turn) | `converted/terrain/airbases.json` | the theatre's own: `converted/terrain/israel/airbases.json` |
| `converted(rel)`: every path under `assets/converted` a shared script reads | `assets/converted/<rel>` | the same for `own/`, `terrain/israel/`, `modern-iaf/`, `missions/sim.bdb.json` and `objects/objects.json`; any other path is refused: a path that does not exist, an error naming the caller the first time, counted in `rejected` as `converted/<rel>` |
| `planes_folder()`: the aircraft descriptors | `converted/planes` | `converted/own/planes` (the F-16's from our model, `iaf-sim own`) |
| `missions_folder()`: the menu missions and `missionlist.json` | `converted/missions` | `converted/modern-iaf/missions` |
| `default_bdb()`: the object database a jet's default load falls back on | `default6_1.bdb` | `sim.bdb` |
| `loading_screen_scene()`: the flight's loading screen | `shared/terrain/loading_screen.gd` (the menu art) | `flight/loading_screen.gd` ([front-end.md](docs/front-end.md)) |
| `original_art()`, `effect_art(rel)`: the effects' sprites (flares, chaff, trails, afterburner, water splash) | true: the converted original's | false: its own, drawn by `iaf-sim own` ([weapons.md](docs/weapons.md) §2) |
| `scenery_dir()`, `roads_dir()`: the buildings and trees, the road layer ([scenery.md](docs/scenery.md)) | `scenery`, `roads` (under `assets/converted`, read through `converted()`) | the theatre's own: `terrain/israel/scenery`, `terrain/israel/roads` |
| `scenery_everywhere()`: the scenery stands whatever the imagery | false: over a Survey 2 m layer only | true: the theatre's ground is its own photo |

The bases are `own_dir()`'s `iaf.ibx` (`iaf-sim airbases`, [airbases.md](docs/airbases.md) §9) at their real places,
so the sim never moves them: its `sync_bases()` sets up no World scale Real move. The tower's wind turn
(`IafBases.set_wind`) takes their runways from `Settings.airbases_file()`, the theatre's own `airbases.json`
(`converted/terrain/israel/airbases.json`; the original game's `converted/terrain/airbases.json`).

The gates are checked twice: `modern-iaf/tests/test_converted_gate.gd` fails on a `"converted/"` string or an
`install_dir()` call in a shared script outside its short lists, and the M0 probe's line "no original game data read,
converted or install" fails when any reader asked for a refused path during its flights. The sim shows no in-flight message texts (`msgs()`: the original's `msgs.trx` is
not the sim's) until its own message table.

The sim's settings also fix the switches that pick between the 1998 game and our replacements (3D cockpit, detailed
models, world scale Real, flight and weapon data Real, the F-15I, no textured sky): the sim has no preferences row for
them.
`Settings.set_jet(airframe)` sets the F-16 switch from the jet flown: `f16i` flies as the Sufa, `f16` as the Barak.
`airframe_def(id)` merges the sim's own `res://data/planes/<id>.json` over the shared aircraft definition, where one
exists.
