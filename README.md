# iaf-reborn

A native (Linux and macOS) re-implementation of the engine for **Jane's IAF: Israeli Air Force** (1998). It loads the
game data from **your own copy** of the original game and renders it with modern graphics.

**You need your own copy of the original game (the CD / ISO).** This repository holds no original game assets or
data. Setup extracts and converts everything the engine uses on your machine, from your ISO.

The game plays as the original v1.1 by default; every improvement is an opt-in switch
([docs/deviations.md](docs/deviations.md)). What works and what is open: [docs/status.md](docs/status.md).

## Layout

- `crates/` – Rust workspace: file-format parsers, extraction / conversion tools, setup, flight model, avionics,
  Godot extension
- `game/` – Godot 4.7 project
- `docs/` – reverse-engineering notes per system; `docs/formats/` – file formats
- `assets/` – generated from your ISO (git-ignored)

## Requirements

### From the original game

- `Jane's IAF.iso` — the original English CD image (v1.0).
- _(optional, recommended)_ the official v1.1 patch (the WinZip self-extractor holding `iafp1_1.exe`). Setup applies
  it without Windows. The engine's logic is always v1.1; without the patch it plays the v1.0 data
  ([docs/v1.1.md](docs/v1.1.md#v10-data-compatibility)).
- _(optional)_ the Hebrew CD, or the Hebrew packs `Brief.zip` / `Menu.zip` ([docs/packs.md](docs/packs.md)).

If you do not have them, search the web for the ISO and the Hebrew packs. I trust you.

### Arch Linux packages

| package | source | needed for |
|---|---|---|
| `rustup` (then `rustup default stable`) | extra | building the tools (`crates/`) |
| `godot` (4.7) | extra | running the game (`game/`) |
| `vulkan-intel` / `vulkan-radeon` / `nvidia-utils` (match your GPU) | extra | Vulkan rendering |
| `ttf-liberation` (or `ttf-ms-fonts` from AUR for real Arial) | extra | menu text (the original uses Arial; Liberation Sans is metric-compatible, [docs/macos.md](docs/macos.md#platform-differences)) |
| `gdal` _(optional)_ | extra | modern terrain imagery |

```sh
sudo pacman -S --needed rustup godot vulkan-intel
sudo pacman -S --needed gdal          # optional: modern terrain imagery
rustup default stable
```

macOS: [docs/macos.md](docs/macos.md).

## Quick start

```sh
./setup        # the setup wizard: pick your CD, it does the rest
./iafjets      # builds what changed and starts the game (without game data: the wizard)
```

The wizard checks what the computer has, asks for the English CD image and the optional extras, and shows each
step's progress. Run it again to add an extra or redo a step: only what changed runs. Setup also installs a desktop
launcher, "Jane's IAF (reborn)", with the original icon.

The same steps from a terminal, for scripting:

```sh
tools/setup-cli.sh [--patch v1.1.exe] [--hebrew-iso IAF.Iso] [--imagery sentinel2,mapi2015] "/path/to/Jane's IAF.iso" [Brief.zip Menu.zip]
```

Inputs, steps, stamps and uninstall: [docs/setup.md](docs/setup.md). The tools also run by hand, for example
`cargo run --release -p iaf-tools --bin iaf-extract -- "/path/to/Jane's IAF.iso" assets/install` (the original "Full
Install", lower-cased paths) and `… --bin iaf-patch -- apply v1.1.exe assets/install assets/v1.1` (the 41 patched
files; [docs/formats/rtpatch.md](docs/formats/rtpatch.md)).

Other entry points:

- `./iafjets -- --mission 311`: straight into a mission.
- `godot --path game res://terrain/terrain_view.tscn`: straight into the air.
- `godot --path game res://viewer/viewer.tscn`: the model viewer, with hot reload.

## Intro videos

The original plays `janes.avi` (the Jane's logo) and `intro.avi` (the opening movie) at start-up. Ours goes straight
to the main menu. After setup both files are in `assets/install/resource/avi/`, in the Indeo 5 format. VLC and
ffmpeg's `ffplay` play them (QuickTime does not):

```sh
ffplay -autoexit assets/install/resource/avi/intro.avi
```

## Terrain imagery data (optional)

The 1998 imagery stays the default. Modern imagery is an opt-in layer per region, picked on Preferences → Graphics →
MORE ("Imagery Israel", "Imagery outside Israel"); a choice whose data is not converted is greyed out. Nothing is
downloaded unless you ask (the wizard's Extras page, or):

```sh
tools/setup-cli.sh --imagery sentinel2          # alone: only the imagery steps, on an install set up before
tools/setup-cli.sh --imagery mapi2015-bases     # or several: --imagery sentinel2,mapi2015
```

Each source comes in two looks: 1998 colours and modern colours.

| source | region | where from | licence / credit | size | how |
|---|---|---|---|---|---|
| **Sentinel-2** (ESA WorldCover 2021 S2 RGB composite, 10 m) — `sentinel2` | outside Israel | `https://esa-worldcover-s2.s3.eu-central-1.amazonaws.com/rgbnir/2021/` (public S3, HTTP range reads through GDAL) | CC BY 4.0 — "Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium" | ≈ 28 GB of range reads (setup prints the estimate and asks first), ≈ 2.5 GB on disk, ≈ 1 h 40 min | automatic, resumable (needs `gdal`) |
| **Survey of Israel 2015 aerial photo, 2 m** — `mapi2015` (all 79 sheets), `mapi2015-bases` (the sheets around the airbases) | Israel, West Bank, Golan (at 2.5 m per pixel) | data.gov.il, one ZIP per 1:50 000 sheet ([tools/imagery/mapi2015_sheets.tsv](tools/imagery/mapi2015_sheets.tsv)) | data.gov.il open licence — "© Survey of Israel 2015, via data.gov.il" | ≈ 250 MB per sheet: ≈ 20 GB all, ≈ 2 GB bases; ≈ 4.7 GB on disk; ≈ 1 h to convert all on 6 threads | manual-assisted: [fetch-mapi2015-curl.sh](tools/imagery/fetch-mapi2015-curl.sh) downloads with curl and the bot-challenge token Firefox earned on data.gov.il (open one sheet link in Firefox first); without one, [fetch-mapi2015.sh](tools/imagery/fetch-mapi2015.sh) opens the links in your browser and moves the finished ZIPs; then converts (needs `gdal`; after adding sheets only what they touch is redone) |
| _coming:_ **SPOT 5** (CNES SPOT World Heritage, 5 m pan + 10 m colour) | outside Israel (maybe Israel too) | GEODES (`https://geodes-portal.cnes.fr/api/stac/search`), free CNES account | Etalab Open Licence 2.0 — "© CNES, distribution SWH / Airbus DS" | ≈ 20–40 GB | not yet (needs a free CNES account and orthorectification) |

The credits roll on Quit shows the converted layers' credits. Pipeline, folders and running by hand:
[docs/imagery.md](docs/imagery.md); the warp to the game frame: [docs/georef.md](docs/georef.md); every source checked
and why: [docs/imagery-sources.md](docs/imagery-sources.md).

## Flying

Every key comes from the original game's key table (converted from `iafjets.exe`). Rebind them on **Preferences →
Keyboard**. All 117 original commands and our own keys: [docs/controls.md](docs/controls.md).

| key (default) | action |
|---|---|
| arrows | stick (↑ forward = nose down, ↓ pull), sprung; ←/→ steer the nose wheel on the ground |
| Numpad 0 / Numpad . | rudder (ignored on the ground, as in the original) |
| 1–8 | throttle presets idle, 65, 70, 80, 90 %, military, AB1, AB2; **1 starts the engine** |
| 0 / 9 | throttle +/− 5 % RPM |
| G / F / B | gear / flaps / brakes (wheel brakes on the ground, speed brake in the air) |
| A | autopilot |
| E (×3) | eject: press three times |
| T / D | MFD: TSD / damage page |
| Q / R / S | radar: cycle mode / A-A ↔ A-G / standby |
| . / , | radar range + / − |
| W, Shift+W | next / previous waypoint |
| H | HUD colour |
| F1 / F10 | cockpit / external (chase) view |
| = / − (Numpad + / −) | cockpit zoom |
| Ctrl+Q | quit mission? (debrief) |
| Ctrl+P / Ctrl+O | pause / On-The-Fly menu |
| Esc | tactical display (FlyTSD) and back; closes the menu |
| C / Ctrl+C | time compression x2 / x4 / x1, normal time |
| Ctrl+M | mute |

Our own keys: **Ctrl+F1** quit mission?, **Ctrl+F2** cockpit ↔ external, **Ctrl+F12** flight-info line, **V** /
**PgUp** / **PgDn** panel, mouse wheel zoom, right-drag orbits the external view.

**Joystick, throttle and pedals.** One device (the first connected; hot-plug works) works as in the original, read
through Godot's SDL with no extra packages. Set it up on **Preferences → Devices** (FLIGHT CONTROLS, THROTTLE,
RUDDER); bind its buttons on the Keyboard page. The log prints the device and its axis numbers when it connects; if
the wrong control moves, edit `[devices] joy_axes` in the settings file. Details: [docs/controls.md](docs/controls.md)
§5.

## Contributing

- Commands, architecture and conventions: [CLAUDE.md](CLAUDE.md). Plans: [docs/roadmap.md](docs/roadmap.md).
- Tests: `cargo test -q --workspace` (tests that need game data or `python3` skip with a message);
  `tools/test.sh` runs those and every headless Godot test `tests/godot/test_*.gd`. The Godot tests need the
  converted assets, so they run locally. Run scripted tests with `IAF_DEFAULT_SETTINGS=1`: they then never read or
  write your saved preferences.
- Credits: the roll on Quit shows ours and the imagery credits, then the original's. To add one:
  [docs/credits.md](docs/credits.md).

## License and trademarks

The code in this repository is licensed under the GNU General Public License v3.0 or later — see [LICENSE](LICENSE).
It contains no data from the original game; you must supply your own copy. Third-party models, pictures and sounds
in `game/extra/` keep their own licences; each has its credits beside it (`SOURCES.md`, `CREDITS.md`, `README.md`).

"Jane's" and "Jane's IAF" are trademarks of their respective owners. This project is an independent, non-commercial
re-implementation and is not affiliated with, endorsed by or sponsored by them or by the original publisher
(Electronic Arts) or developer.
