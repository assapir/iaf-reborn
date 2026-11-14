# Jane's IAF reborn and Modern IAF

Two flight sims on one open-source engine (Godot 4 and Rust), for Linux, macOS and Windows. Each has its own folder,
its own README and its own setup.

## Jane's IAF reborn: the 1998 game

A re-implementation of **Jane's IAF: Israeli Air Force** (1998). It loads the game data from **your own copy** of
the original game and renders it with modern graphics.

**You need your own copy of the original game (the CD / ISO).** This repository holds no original game assets or
data. Setup extracts and converts everything the engine uses on your machine, from your ISO.

```sh
./setup        # the setup wizard: pick your CD, it does the rest
./iafjets      # builds what changed and starts the game
```

Requirements, setup, controls and the rest: [iaf-reborn/README.md](iaf-reborn/README.md). What works and what is
open: [docs/status.md](docs/status.md).

## Modern IAF: the present-day sim

Modern IAF (in Hebrew: הזרוע הארוכה) is a flight sim of today's Israeli Air Force: three jets (F-16I Sufa, F-16D
Barak, F-35I Adir), 3D cockpits, Israel at full scale, training missions, in Hebrew and English.

**It needs no data from the original game.** Setup downloads open data once (0.6 GB of heights and 11.4 GB of
satellite colour tiles) and builds the sim's data into `assets/`.

```sh
./modern-iaf-setup     # the setup wizard: downloads the open data and builds the sim's data
./start-modern-iaf     # builds what changed and starts the sim
```

Setup, running it on a Mac, folders: [modern-iaf/README.md](modern-iaf/README.md). What works and what is open:
[modern-iaf/docs/status.md](modern-iaf/docs/status.md).

## The shared engine

Both games run on the same engine: the Rust crates in `crates/` and the Godot scripts, scenes and shaders in
`shared/`. Commands, architecture and conventions: [CLAUDE.md](CLAUDE.md).

## Layout

- `crates/`: Rust workspace: file-format parsers, extraction / conversion tools, setup, flight model, avionics,
  Godot extension (both games)
- `shared/`: the engine's GDScript, scenes and shaders (both games)
- `iaf-reborn/`: the Godot 4.7 project of the 1998 game, and its README
- `modern-iaf/`: the Godot project, data and README of Modern IAF
- `docs/`: notes per system for the 1998 game and the shared engine; `docs/formats/`: file formats
- `modern-iaf/docs/`: Modern IAF's plan, status and design notes
- `assets/`: generated on your machine (git-ignored): from your ISO for the 1998 game, from open data for Modern IAF

## License and trademarks

The code in this repository is licensed under the GNU General Public License v3.0 or later: see [LICENSE](LICENSE).
It contains no data from the original game; the 1998 game needs your own copy. Third-party models, pictures and
sounds in `shared/extra/` keep their own licences ([docs/credits.md](docs/credits.md)).

"Jane's" and "Jane's IAF" are trademarks of their respective owners. This project is an independent, non-commercial
re-implementation and is not affiliated with, endorsed by or sponsored by them or by the original publisher
(Electronic Arts) or developer.
