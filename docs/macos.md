# Running on macOS (untested)

Nothing in the code is Linux-only, but macOS has not been tried yet. Reports welcome.

## Install
```sh
brew install rustup coreutils      # coreutils: `timeout` for tools/test.sh
brew install --cask godot          # needs Godot 4.7 or newer (game/iaf.gdextension requires it)
brew install gdal                  # optional: modern terrain imagery (tools/setup.sh --imagery)
rustup default stable
```
The cask does not put `godot` on the PATH. `./iafjets` finds /Applications/Godot.app itself (or set `GODOT=`);
`tools/test.sh` calls `godot`, so link it onto the PATH:
```sh
ln -s /Applications/Godot.app/Contents/MacOS/Godot /usr/local/bin/godot
```

## Build and run
```sh
git clone https://github.com/assapir/iaf-reborn && cd iaf-reborn
tools/setup.sh "/path/to/Jane's IAF.iso"     # options (v1.1 patch, Hebrew packs) as in the README
./iafjets                                # builds the extension (target/release/libiaf_godot.dylib) and starts the game
```
`setup.sh` runs the same Rust tools as on Linux, so extraction, the v1.1 patch, the Hebrew packs and conversion
behave identically (see README).

## Tests
`tools/test.sh` calls `timeout`: with coreutils installed either put GNU tools first
(`PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"`); an alias is not seen by the script.

## Known differences
- Godot renders with Metal on macOS; terrain shaders may look slightly different.
- Launcher: setup installs `~/Applications/Jane's IAF (reborn).app` (Linux gets a `.desktop` file instead).
- Fonts: Arial exists on macOS and is used directly (Linux uses Liberation Sans as the fallback).
- User data (settings, key bindings, pilots, the blackbox's `flights/`) lives in `~/Library/Application Support/Godot/app_userdata/iaf-reborn/`
  (Godot's `user://`; Linux: `~/.local/share/godot/app_userdata/iaf-reborn/`).
