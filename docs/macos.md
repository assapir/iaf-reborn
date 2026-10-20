# Running on macOS

The code builds and runs on macOS (Apple silicon). It is less tested there than on Linux. Reports welcome.

## Install

1. Install the tools:
   ```sh
   brew install rustup coreutils      # coreutils: `timeout` for tools/test.sh
   brew install --cask godot          # needs Godot 4.7 or newer (game/iaf.gdextension requires it)
   brew install gdal                  # optional: modern terrain imagery (tools/setup-cli.sh --imagery)
   rustup default stable
   ```
2. Put `godot` on the PATH. The cask installs Godot to /Applications/Godot.app only. `./iafjets` finds the app
   itself (or reads `GODOT=`), but `tools/test.sh` calls `godot`, so link it:
   ```sh
   ln -s /Applications/Godot.app/Contents/MacOS/Godot /usr/local/bin/godot
   ```

## Build and run

```sh
git clone https://github.com/assapir/iaf-reborn && cd iaf-reborn
tools/setup-cli.sh "/path/to/Jane's IAF.iso"     # options (v1.1 patch, Hebrew packs) as in the README
./iafjets                                # builds the extension (target/release/libiaf_godot.dylib) and starts the game
```

`setup-cli.sh` runs the same Rust tools on macOS and Linux. Extraction, the v1.1 patch, the Hebrew packs and
conversion therefore behave identically (see README).

## Tests

`tools/test.sh` calls `timeout`. With coreutils installed, put the GNU tools first on the PATH:
`PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"`. The script does not see a shell alias.

## Platform differences

Godot renders with Metal on macOS, so terrain shaders may look slightly different.

| area      | macOS                                                          | Linux                                           |
|-----------|----------------------------------------------------------------|-------------------------------------------------|
| launcher  | setup installs `~/Applications/Jane's IAF (reborn).app`        | setup installs a `.desktop` file                |
| fonts     | Arial is installed and used directly                           | Liberation Sans is the fallback for Arial       |
| user data | `~/Library/Application Support/Godot/app_userdata/iaf-reborn/` | `~/.local/share/godot/app_userdata/iaf-reborn/` |

With Liberation Sans the in-flight menu and boxes keep the exe's font sizes but use Godot's widths and heights:
GDI's exact pixels come from Arial's `hdmx` and `VDMX` tables (docs/front-end.md §16.2), which Liberation Sans lacks.
Install Arial (Arch: `ttf-ms-fonts`) for the exact layout; `test_views` skips its pixel checks without it.

User data is Godot's `user://` folder. It holds the settings, key bindings, pilots and the blackbox's `flights/`.
