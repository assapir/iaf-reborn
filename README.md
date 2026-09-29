# linux-iaf

A native (Linux, and later macOS) re-implementation of the engine for **Jane's IAF: Israeli Air Force** (1998).

The engine loads the game data from **your own copy** of the original game (ISO + v1.1 patch) and renders it with
modern graphics. No original game assets are stored in this repository.

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
- _(later)_ the v1.1 patch `iafp1_1.exe` — not used yet.

### Arch Linux packages

| package                                                            | source | needed for                                                                |
| ------------------------------------------------------------------ | ------ | ------------------------------------------------------------------------- |
| `rustup` (then `rustup default stable`)                            | extra  | building the tools (`crates/`)                                            |
| `godot` (4.7+)                                                     | extra  | running the viewer / game (`game/`)                                       |
| `vulkan-intel` / `vulkan-radeon` / `nvidia-utils` (match your GPU) | extra  | Vulkan rendering + GPU upscaling                                          |
| `ttf-liberation` (or `ttf-ms-fonts` from AUR for real Arial)         | extra  | menu text (the original uses Arial; Liberation Sans is metric-compatible) |
| `realesrgan-ncnn-vulkan` (or `-bin`)                               | AUR    | _optional, experimental_: `--upscale-ai` (not recommended — redraws text) |

```sh
sudo pacman -S --needed rustup godot vulkan-intel
rustup default stable
paru -S realesrgan-ncnn-vulkan   # optional, experimental AI upscaling only
```

Handy for development (not required): `ffmpeg` (image/video inspection), `python` (quick format probes).

### macOS (planned, untested)

`brew install rustup godot` (Godot as a cask), then `rustup default stable`. Real-ESRGAN ships a macOS build on its
[GitHub releases](https://github.com/xinntao/Real-ESRGAN/releases) page.

## Quick start

```sh
tools/setup.sh "/path/to/Jane's IAF.iso" [/path/to/Brief.zip]   # everything, from your own ISO (~2 min)
godot --path game                                                 # front end → Training → mission → Continue
```

`tools/setup.sh` runs the whole pipeline (extract → aircraft → cockpit → menus → terrain → optional Hebrew pack →
Godot extension); the individual commands are listed in it. Conversion is a one-time step; re-run after updating the
converters. Other entry points: `godot --path game res://terrain/terrain_view.tscn` (straight into the air),
`godot --path game res://viewer/viewer.tscn` (model viewer with hot reload).

## Getting the game data

```sh
cargo run --release -p iaf-tools --bin iaf-extract -- "/path/to/Jane's IAF.iso" assets/install
```

This reproduces the original "Full Install" (lower-cased paths) without Windows.

Use google to find the original game ISO if you do not have them. I trust you. Same for the optional Hebrew packs.

## Optional packs

Community mods (e.g. Hebrew briefings) can be imported as overlay packs — see [docs/packs.md](docs/packs.md).

## Flying (current controls, provisional until the original key table is decoded)

| key            | action                                                                    |
| -------------- | ------------------------------------------------------------------------- |
| arrows         | stick (↑ forward = nose down, ↓ pull), sprung                             |
| Z / X          | rudder                                                                    |
| W / S, 1–8     | throttle; presets idle, 65, 70, 80, 90 %, military, AB1, AB2              |
| G / F / B      | gear / flaps / speed brake                                                |
| F1 / F2 / C    | cockpit / external / toggle                                               |
| Esc            | back to the menus                                                         |
| V, PgUp / PgDn | panel down / slide panel                                                  |
| + / −, wheel   | cockpit zoom (external: orbit distance); RMB drag orbits in external view |
