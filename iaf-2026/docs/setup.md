# Modern IAF: the setup wizard

The setup wizard builds the sim's data into `assets/`: the terrain, the airbases, the units and weapons, the jets'
flight data, the sounds and voices and the training missions. It is item [A3](plan.md#a3-the-setup-wizard). Start it from the repo root:

```sh
./iaf2026-setup        # Windows: .\iaf2026-setup.ps1
```

`./iaf2026` starts it too while the sim's data is missing (no `assets/converted/iaf-2026/missions/`, the last step's
output). Run it again at any time: a step whose inputs did not change is "up to date" and is skipped, and a run
that stopped resumes where it stopped.

## 1. What it needs

| need | why | Linux | macOS | Windows |
|---|---|---|---|---|
| Rust (cargo) | builds the extension the wizard runs in | rustup.rs (Arch: `sudo pacman -S rustup`) | `brew install rustup` | `winget install Rustlang.Rustup` |
| Godot 4.7 | runs the wizard | godotengine.org (Arch: `sudo pacman -S godot`) | `brew install godot` | `winget install GodotEngine.GodotEngine` |
| GDAL | reads and reprojects the heights and the imagery | `sudo apt install gdal-bin` (Arch: `sudo pacman -S gdal`) | `brew install gdal` | the GISInternals installer (`winget install GISInternals.GDAL`) |
| curl | downloads the height tiles | `sudo apt install curl` | `brew install curl` | in Windows 10 and later |
| Python 3 | writes the jets' flight data (`tools/iaf-2026/fm0.py`) | `sudo apt install python3` | `brew install python` | `winget install Python.Python.3.14` |
| disk | the data (§4) | | | |

The launcher (`tools/launch-wizard.sh`, which the original game's `./setup` uses too) checks Rust and Godot and says
how to install a missing one. The wizard's first page checks GDAL, curl, Python 3 and the free disk space for the
imagery chosen at the start (the Survey's when its sheets are there); Next waits until they are there, and the page
names the install command for the system it runs on. Python 3 is the first of `python3`, `python` and `py -3` (on
Windows `python` first) whose `--version` answers "Python 3." (`iaf_setup::python`): Windows' `python3` without Python
installed is the Store's alias, which only fails.

## 2. The pages

Each page in English and in Hebrew. The language is the sim's `Settings.language`, chosen on the first page and
saved; a Hebrew page is mirrored, every control included (`layout_direction` right to left). The window fills a
large screen by its UI scale (the containers stretch; nothing has a fixed page size).

1. **Welcome**: the language; what setup downloads and builds; the download, the disk use and the time (§4); the
   requirements; the **Attributions** button ("קרדיט").
2. **Imagery**: Sentinel-2 everywhere, or Sentinel-2 plus the Survey of Israel 2 m photo over Israel, each with its
   disk use and time. The Survey choice needs the 79 sheet ZIPs (data.gov.il, 17 GB) in
   `assets/source/imagery/mapi2015/`; without them the page says so and keeps Sentinel-2.
3. **Install**: one row per step with its progress bar and state. Before a run the rows say which steps are up to
   date (a background check); during a run a long step shows the time left. Back becomes Cancel: the running steps
   stop at their next item. "Show the log" opens the log; the whole run is also in `assets/logs/iaf2026-setup-<date>-<time>.log`.
   "Redo every step" runs the steps that are up to date too; for the terrain that is a full rebuild (its finished
   units' marks are dropped). Back from Install forgets the finished run, so other choices can be installed; a
   language change keeps it.
4. **Done**: how to start the sim, the commands for one training mission (start-up, take-off) from Ramon, Ramat
   David and Nevatim, and how to run setup again.

The **Attributions** open from Welcome as a modal dialog over the page (Close or Esc closes it; it scrolls): every
source with its licence line: the Copernicus DEM's two lines word for word ([terrain.md](terrain.md) §5), ESA
WorldCover's Sentinel-2 line, the Survey of Israel, OpenStreetMap (ODbL), OurAirports, the freesound authors
([sound.md](sound.md) §6), Piper and its voices, the FlightGear F-16 (GPL), the F-35I model (CC BY 4.0), NASA
TP-1538, the Heebo font (OFL), the front end's jet photos (Wikimedia Commons, CC BY). The licence lines stay in
English in the Hebrew dialog.

The pages say only what the user decides or must know ([plan.md](plan.md) Rules).

| page | English | Hebrew |
|---|---|---|
| Welcome | ![Welcome](pictures/setup/welcome_en.webp) | ![Welcome, Hebrew](pictures/setup/welcome_he.webp) |
| Attributions (over Welcome) | ![Attributions](pictures/setup/attributions_en.webp) | ![Attributions, Hebrew](pictures/setup/attributions_he.webp) |
| Imagery | ![Imagery](pictures/setup/imagery_en.webp) | ![Imagery, Hebrew](pictures/setup/imagery_he.webp) |
| Install | ![Install](pictures/setup/install_en.webp) | ![Install, Hebrew](pictures/setup/install_he.webp) |
| Done | ![Done](pictures/setup/done_en.webp) | ![Done, Hebrew](pictures/setup/done_he.webp) |

### Look
The look is one file, `iaf-2026/setup/wizard_theme.gd`: Godot's default dark theme with Heebo
(`iaf-2026/data/fonts/`, SIL OFL 1.1) and the text kinds the pages ask for by name ("Heading", "Muted", "Note",
"Readout", "Code", "Card"). A new look replaces that file only. The strings are `iaf-2026/setup/strings_en.json` and
`strings_he.json` (formal, gender-neutral Hebrew).

## 3. The steps

The wizard runs `iaf_setup::sim_plan` through `iaf_setup::sim_run` (`crates/iaf-setup/src/sim.rs`), the same
dependency graph as the original game's setup: independent steps run at once, a failed step blocks what waits for it.

| step | does | waits for |
|---|---|---|
| `sim-terrain` | `iaf-sim terrain`: GLO-30 heights, Sentinel-2 colour, the Survey 2 m photo when chosen ([terrain.md](terrain.md)) | — |
| `sim-db` | `iaf-sim db`: the units and weapons ([data-formats.md](data-formats.md)) | — |
| `sim-fm` | `tools/iaf-2026/fm0.py`: the jets' `bd.ibx` and envelopes ([flight-model.md](flight-model.md)) | — |
| `sim-own` | `iaf-sim own`: the sounds, the voices and the keys ([sound.md](sound.md)) | — |
| `sim-airbases` | `iaf-sim airbases`: the four bases on the terrain ([airbases.md](airbases.md) §9) | `sim-terrain` |
| `sim-missions` | `iaf-sim missions`: the training missions on the bases ([training.md](training.md)) | `sim-airbases`, `sim-db` |

Each step keeps a stamp, `assets/converted/iaf-2026/<step>.stamp`: the fingerprint of the code that makes its output
(`stamp::STEP_SOURCES`), the authored data or script it reads (each file's size and CRC-32) and the
stamps of the steps it waits for; paths are relative to the repo, so a stamp is the same in every checkout and on every
system. The terrain's stamp holds what `iaf-sim terrain` itself compares (the box, the detail area, the Survey sheets'
names and sizes, the airbases' layouts, whose outlines mask the Survey photo), so a choice of the other imagery or a
changed base outline runs the terrain and what stands on it again. A theatre built before the airbases were part of
its `built_from` (3 November 2026) runs once more: its finished units' marks make that a matter of minutes. Inside a step the terrain resumes by its own marks (`.work/`): a cancelled or failed run keeps its finished
units and DEM tiles.

## 4. Sizes and times

Measured on the developer's Linux laptop (Intel i7-1185G7, 8 threads), 3 November 2026 ([terrain.md](terrain.md) §7).

| | Sentinel-2 everywhere | plus the Survey of Israel |
|---|---|---|
| download | GLO-30: 627 MB, kept in `assets/source/dem/`; Sentinel-2 is read over the network, not kept | the same; the Survey's sheets must be there already (17 GB) |
| theatre on disk | about 450 MB (levels 3–11) | 3.57 GB |
| the other steps | about 20 MB | about 20 MB |
| disk use in all | about 1.1 GB | about 4.2 GB |
| time | about 26 min (DEM 2 min, Sentinel-2 21 min, the coarser levels 3 min; inferred from the parts of the full run) | 1 h 42 min |

The other five steps take seconds together. The first page shows these figures.

## 5. Checks

- `cargo test -p iaf-setup`: the plan's order, the stamps (a second run is all up to date, the Survey choice runs the
  terrain, the airbases and the missions again, a changed airbase outline the terrain), a terrain redo drops its
  marks, inputs relative to the repo, only a real Python 3 counts; every sim step's source row holds every module its
  code reaches.
- `iaf-2026/tests/test_setup_wizard.gd` (headless, `IAF_ASSETS_DIR` at an empty folder): the four pages in order in
  both languages, the mirrored layout, the approved Hebrew words, the Attributions dialog (opens from Welcome,
  mirrored, the Copernicus lines word for word, every attribution, closes with Esc and with Close),
  no other game named, the Survey choice off without sheets, the Install rows and their preview, abandoned preview
  checks fetched, a finished run kept through a language change and forgotten by Back. `tools/test.sh` gives it a
  scratch folder.
- The pictures: `tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 SHOT_DIR=<dir> -- --log-file <log> --path iaf-2026
  --resolution 1100x720 -s ../iaf-2026/tests/_setup_wizard_shot.gd`.
- A real run, 3 November 2026: §6.

## 6. A real run

On this laptop, 3 November 2026, from an assets root with none of the sim's files but the downloads and the built
theatre's tiles (`source/dem/` and the Survey sheets linked in, the theatre's levels hard-linked: what a machine that
built the terrain before keeps), the Survey choice:

| run | what ran | time |
|---|---|---|
| first | all six steps: `sim-terrain` found its `built_from` unchanged and ended at once; the units and weapons, the flight data, the sounds and keys, the airbases and the missions were built | 16 s |
| second | none: all six up to date | 0.5 s |

The M0 probe on that root: 41 PASS, 0 FAIL, the one NEEDS DATA it also prints on the full root (item E1's cockpit
check). A terrain built from nothing takes the times of §4.

## 7. Open

- Switching from the Survey choice back to Sentinel-2 everywhere leaves the Survey's 2 m tiles in the theatre (the
  terrain step writes the tiles it makes and does not delete others).
- The Survey sheets are those `iaf-imagery fetch-mapi2015` downloads; the wizard uses them when they are there.
