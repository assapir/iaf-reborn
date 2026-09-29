# linux-iaf

A native (Linux, and later macOS) re-implementation of the engine for **Jane's IAF: Israeli Air Force** (1998).

The engine loads the game data from **your own copy** of the original game (ISO + v1.1 patch) and renders it with
modern graphics. No original game assets are stored in this repository.

## Layout
- `crates/` – Rust workspace: file-format parsers, extraction/conversion tools, flight model, Godot extension
- `game/` – Godot 4 project
- `docs/formats/` – reverse-engineered file format notes
- `assets/` – generated from your ISO (git-ignored)

## Requirements

### What you need from the original game
- `Jane's IAF.iso` — the original CD image (English, v1.0).
- *(later)* the v1.1 patch `iafp1_1.exe` — not used yet.

### Arch Linux packages
| package | source | needed for |
|---------|--------|------------|
| `rustup` (then `rustup default stable`) | extra | building the tools (`crates/`) |
| `godot` (4.7+) | extra | running the viewer / game (`game/`) |
| `vulkan-intel` / `vulkan-radeon` / `nvidia-utils` (match your GPU) | extra | Vulkan rendering + GPU upscaling |
| `realesrgan-ncnn-vulkan` (or `-bin`) | AUR | *optional, experimental*: `--upscale-ai` (not recommended — redraws text) |

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
# 1. unpack the original game from the CD image
cargo run --release -p iaf-tools --bin iaf-extract -- "/path/to/Jane's IAF.iso" assets/install
# 2. convert the aircraft models to glTF (+ PNG textures)
cargo run --release -p iaf-tools --bin iaf-convert -- planes assets/install assets/converted/planes
#    options (before "planes"): --upscale  4× Lanczos-resampled textures (faithful to the original art)
#                               --smooth   round the low-poly geometry (smooth normals + Phong tessellation)
# 3. export the terrain around Israel (colour: level 4 inset, heights from level 6)
cargo run --release -p iaf-tools --bin iaf-terrain -- export assets/install/resource/terrain/map.ptt 7 assets/converted/terrain/israel_l4
# 4. cockpit art
cargo run --release -p iaf-tools --bin iaf-convert -- --upscale cockpit assets/install f16 assets/converted/cockpits/f16
# 5. front-end menus (screens, strings, art, fonts)
cargo run --release -p iaf-tools --bin iaf-convert -- --upscale menu assets/install assets/converted/menu
# 6. build the Godot extension (flight model etc.)
cargo build -p iaf-godot
# 7. play: front end (Training → course → mission → FLY; Preferences → Gameplay for flight data / language)
godot --path game
#    or jump straight into the air / the model viewer
godot --path game res://terrain/terrain_view.tscn
godot --path game res://viewer/viewer.tscn
```
The conversion is a one-time step; re-run it only after updating the converter or adding packs.

## Getting the game data
```sh
cargo run --release -p iaf-tools --bin iaf-extract -- "/path/to/Jane's IAF.iso" assets/install
```
This reproduces the original "Full Install" (lower-cased paths) without Windows.

## Optional packs
Community mods (e.g. Hebrew briefings) can be imported as overlay packs — see [docs/packs.md](docs/packs.md).

## Flying (current controls, provisional until the original key table is decoded)
| key | action |
|-----|--------|
| arrows | stick (↑ forward = nose down, ↓ pull), sprung |
| Z / X | rudder |
| W / S, 1–8 | throttle; presets idle, 65, 70, 80, 90 %, military, AB1, AB2 |
| G / F / B | gear / flaps / speed brake |
| F1 / F2 / C | cockpit / external / toggle |
| Esc | back to the menus |
| V, PgUp / PgDn | panel down / slide panel |
| + / −, wheel | cockpit zoom (external: orbit distance); RMB drag orbits in external view |
