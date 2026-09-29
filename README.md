# linux-iaf

A native (Linux, and later macOS) re-implementation of the engine for **Jane's IAF: Israeli Air Force** (1998).

The engine loads the game data from **your own copy** of the original game (ISO + v1.1 patch) and renders it with
modern graphics. No original game assets are stored in this repository.

## Layout
- `crates/` – Rust workspace: file-format parsers, extraction/conversion tools, flight model, Godot extension
- `game/` – Godot 4 project
- `docs/formats/` – reverse-engineered file format notes
- `assets/` – generated from your ISO (git-ignored)

## Getting the game data
```sh
cargo run --release -p iaf-tools --bin iaf-extract -- "/path/to/Jane's IAF.iso" assets/install
```
This reproduces the original "Full Install" (lower-cased paths) without Windows.
