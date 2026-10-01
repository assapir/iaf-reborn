# iaf-reborn

A native (Linux, and later macOS) re-implementation of the engine for **Jane's IAF: Israeli Air Force** (1998).

The engine loads the game data from **your own copy** of the original game (ISO + v1.1 patch) and renders it with
modern graphics. **You need your own copy of the original game (the CD / ISO).** No original game assets or data are
included in this repository; everything the engine uses is extracted and converted locally from your ISO.

Platforms: **Linux** (primary), **macOS** (planned).

## Status

See [docs/status.md](docs/status.md) for what works, known gaps and the plan.

## Layout

- `crates/` – Rust workspace: file-format parsers, extraction/conversion tools, flight model, Godot extension
- `game/` – Godot 4 project
- `docs/formats/` – reverse-engineered file format notes
- `assets/` – generated from your ISO (git-ignored)

## Requirements

### What you need from the original game

- `Jane's IAF.iso` — the original CD image (English, v1.0).
- _(optional, recommended)_ the official v1.1 patch (the WinZip self-extractor holding `iafp1_1.exe`). Setup applies
  it without Windows, so the game runs on v1.1 data. The engine's logic is always v1.1; without the patch it plays
  the v1.0 data ([docs/v1.1.md](docs/v1.1.md#v10-data-compatibility)).

### Arch Linux packages

| package                                                            | source | needed for                                                                |
| ------------------------------------------------------------------ | ------ | ------------------------------------------------------------------------- |
| `rustup` (then `rustup default stable`)                            | extra  | building the tools (`crates/`)                                            |
| `godot` (4.7+)                                                     | extra  | running the viewer / game (`game/`)                                       |
| `vulkan-intel` / `vulkan-radeon` / `nvidia-utils` (match your GPU) | extra  | Vulkan rendering                                                          |
| `ttf-liberation` (or `ttf-ms-fonts` from AUR for real Arial)         | extra  | menu text (the original uses Arial; Liberation Sans is metric-compatible) |

```sh
sudo pacman -S --needed rustup godot vulkan-intel
rustup default stable
```

Handy for development (not required): `ffmpeg` (image/video inspection), `python` (quick format probes).

### macOS (planned, untested)

See [docs/macos.md](docs/macos.md).

## Quick start

```sh
tools/setup.sh [--patch /path/to/v1.1-patch.exe] [--hebrew-iso /path/to/IAF.Iso] "/path/to/Jane's IAF.iso" [/path/to/Brief.zip /path/to/Menu.zip]
./iafjets                                                          # builds what changed and starts the game (front end → Training → mission)
# setup also installs a desktop launcher, "Jane's IAF (reborn)", with the original icon
```

`tools/setup.sh` runs the whole pipeline (extract → v1.1 patch → Hebrew packs → cockpits, briefings, menus, keys,
missions, aircraft, objects → terrain (all of map.ptt, ~730 MB) → Godot extension); the individual commands are listed in it. `--patch` (or the
`IAF_PATCH` environment variable) takes the downloaded v1.1 update, `iafp1_1.exe` or a bare patch file; the patched
files replace the v1.0 ones in `assets/install` (the originals are kept in `assets/v1.0`, the patch output in
`assets/v1.1`) before anything is converted. Without it setup builds everything from the v1.0 files. The Hebrew packs
(optional, docs/packs.md) go on top of the patched English files; `--hebrew-iso` adds the Hebrew CD's startup splash and Graphics page. Conversion is a one-time step; re-run after updating the
converters. Other entry points: `godot --path game res://terrain/terrain_view.tscn` (straight into the air),
`godot --path game res://viewer/viewer.tscn` (model viewer with hot reload).

## Getting the game data

```sh
cargo run --release -p iaf-tools --bin iaf-extract -- "/path/to/Jane's IAF.iso" assets/install
```

This reproduces the original "Full Install" (lower-cased paths) without Windows.

The v1.1 update is applied the same way (`tools/setup.sh --patch` does this, then copies the 41 files over the
install; `apply` itself only reads the install and writes the updated files to the output directory; format notes in
[docs/formats/rtpatch.md](docs/formats/rtpatch.md)):

```sh
cargo run --release -p iaf-tools --bin iaf-patch -- apply /path/to/v1.1-patch.exe assets/install assets/v1.1
```

What v1.1 changes against v1.0, and the v1.0 → v1.1 address map: [docs/v1.1.md](docs/v1.1.md).

Use google to find the original game ISO if you do not have them. I trust you. Same for the optional Hebrew packs.

## Optional packs

Community mods (e.g. Hebrew briefings) can be imported as overlay packs — see [docs/packs.md](docs/packs.md).

## Flying (the original key table)

Every key comes from the original game's own key table (converted from `iafjets.exe`); you can
rebind them on **Preferences → Keyboard** (the original Controls page). The full list of the 117
original commands, and which ones work yet, is in [docs/controls.md](docs/controls.md).

| key (default)  | action                                                                    |
| -------------- | ------------------------------------------------------------------------- |
| arrows         | stick (↑ forward = nose down, ↓ pull), sprung; ←/→ steer the nose wheel on the ground |
| Numpad 0 / Numpad . | rudder (ignored on the ground, as in the original)                   |
| 1–8            | throttle presets idle, 65, 70, 80, 90 %, military, AB1, AB2 (throttle 0 / 0.10 / 0.19 / 0.38 / 0.56 / 0.74 / 0.78 / 1.0); **1 starts the engine** |
| 0 / 9          | throttle +/− 5 % RPM                                                      |
| G / F / B      | gear / flaps / brakes (wheel brakes on the ground, speed brake in the air) |
| E (×3)         | eject: press three times                                                  |
| T / D          | MFD: TSD / damage page                                                    |
| Q / R / S      | radar: cycle mode / A-A ↔ A-G / standby                                   |
| . / ,          | radar range + / −                                                         |
| W, Shift+W     | next / previous waypoint                                                  |
| H              | HUD colour                                                                |
| F1 / F10       | cockpit / external (chase) view                                           |
| = / − (Numpad + / −) | cockpit zoom                                                        |
| Ctrl+Q         | quit mission? (debrief)                                                   |
| Ctrl+P / Ctrl+O | pause / On-The-Fly menu                                                  |
| Esc            | tactical display (FlyTSD) and back; closes the menu                       |
| C / Ctrl+C     | time compression x2 / x4 / x1, normal time                                |
| Ctrl+M         | mute                                                                      |

Our own keys (not in the original — see docs/controls.md): **Ctrl+F1** quit mission?, **Ctrl+F2** cockpit ↔
external, **Ctrl+F12** flight-info line, **V** / **PgUp** / **PgDn** panel, mouse wheel zoom, RMB drag orbits the
external view.

### Joystick, throttle and pedals

One joystick (the first one connected; plug it in any time) works as in the original. No extra packages: Godot
reads it through SDL. Set it up on **Preferences → Devices**:

* **FLIGHT CONTROLS: JOYSTICK** (the default) — the stick flies the jet and the hat is the snap views; the arrow
  keys are ignored while a joystick is connected (as in the original). KEYBOARD = arrows again.
* **THROTTLE: JOYSTICK** — the throttle lever; the 1–8 / 0 / 9 throttle keys are then ignored.
* **RUDDER: PEDALS** — the twist / pedals; the rudder keys are then ignored.
* Buttons: Button 1 fire gun, 2 fire weapon, 3 next target, 4 flare (the original defaults). To rebind, open
  **Preferences → Keyboard**, click a function and press the joystick button.

With no joystick connected these choices change nothing. What to try first when it arrives:

1. Start the game with the stick plugged in and check the log: it prints `joystick: <name> (device 0, …); axes
   x / y / throttle / rudder = [0, 1, 2, 3]`.
2. Fly Training "Engines ON" with FLIGHT CONTROLS JOYSTICK: stick right = roll right, pull = nose up. The
   original has a large dead zone (25 % around the centre), so small movements do nothing.
3. Set THROTTLE JOYSTICK and RUDDER PEDALS, move the lever (forward = full power) and the twist / pedals. If the
   wrong control moves something, swap the numbers in `~/.local/share/godot/app_userdata/iaf-reborn/settings.cfg`,
   `[devices]` → `joy_axes=[x, y, throttle, rudder]` (Godot axis numbers 0–9; SDL names no axes).
4. Press the hat (snap views) and buttons 1–4; rebind on the Keyboard page.

Details: [docs/controls.md](docs/controls.md) §5. A separate throttle / pedals device is not supported yet.

### Tests / captures

`cargo test -q --workspace` runs the Rust tests; tests that need game data or `python3` (the envelope
reference, `tools/envelope_ref.py`) are skipped with a message when those are missing.
`tools/test.sh` runs everything: the Rust tests and the headless Godot tests in `tests/godot`
(mission start, taxi, gear rules, menu flow → TSD → fly). It needs the converted assets, so it runs
locally rather than on a hosted CI. Run scripted tests and captures with `IAF_DEFAULT_SETTINGS=1` so they use default settings and never read or write your saved preferences (`user://settings.cfg`).

## License and trademarks

The code in this repository is licensed under the GNU General Public License v3.0 or later — see [LICENSE](LICENSE).
It contains no data from the original game; you must supply your own copy.

"Jane's" and "Jane's IAF" are trademarks of their respective owners. This project is an independent, non-commercial
re-implementation and is not affiliated with, endorsed by or sponsored by them or by the original publisher
(Electronic Arts) or developer.
