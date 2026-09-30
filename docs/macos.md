# Running on macOS (untested)

Nothing in the code is Linux-only, but macOS has not been tried yet. Reports welcome.

## Install
```sh
brew install rustup coreutils      # coreutils: `timeout` for tools/test.sh
brew install --cask godot          # needs Godot 4.7 or newer (game/iaf.gdextension requires it)
rustup default stable
```
The cask does not put `godot` on the PATH; use the app binary or an alias:
```sh
alias godot=/Applications/Godot.app/Contents/MacOS/Godot
```

## Build and run
```sh
git clone https://github.com/assapir/iaf-reborn && cd iaf-reborn
tools/setup.sh "/path/to/Jane's IAF.iso" [/path/to/Brief.zip /path/to/Menu.zip]
cargo build --release -p iaf-godot       # builds target/release/libiaf_godot.dylib (Intel or Apple Silicon)
godot --path game
```
`setup.sh` runs the same Rust tools as on Linux, so extraction and conversion behave identically. The v1.1 patch
step works the same way (see README).

## Tests
`tools/test.sh` calls `timeout`: with coreutils installed either put GNU tools first
(`PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"`) or `alias timeout=gtimeout`.

## Known differences
- Godot renders with Metal on macOS; terrain shaders may look slightly different.
- Fonts: Arial exists on macOS and is used directly (Linux uses Liberation Sans as the fallback).
- User data (settings, key bindings, blackbox) lives in `~/Library/Application Support/Godot/app_userdata/iaf-reborn/`.
