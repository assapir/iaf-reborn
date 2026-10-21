# Running on macOS

The code builds and runs on macOS (Apple silicon), with the same Rust tools and setup steps as on Linux.

## Install

1. Install the tools:
   ```sh
   brew install rustup coreutils      # coreutils: `timeout` for tools/test.sh
   brew install --cask godot          # Godot 4.7 (game/iaf.gdextension and ./setup require it)
   brew install gdal                  # optional: modern terrain imagery
   rustup default stable
   ```
2. Put `godot` on the PATH. The cask installs Godot to /Applications/Godot.app only. `./setup` and `./iafjets` find
   the app themselves (or read `GODOT=`), but `tools/test.sh` calls `godot`, so link it:
   ```sh
   ln -s /Applications/Godot.app/Contents/MacOS/Godot /usr/local/bin/godot
   ```

## Build and run

```sh
git clone https://github.com/assapir/iaf-reborn && cd iaf-reborn
./setup        # the setup wizard (or tools/setup-cli.sh, docs/setup.md)
./iafjets      # builds the extension (target/release/libiaf_godot.dylib) and starts the game
```

## Tests

`tools/test.sh` calls `timeout`. Put the GNU tools first on the PATH:
`PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"`. The script does not see a shell alias.

## Platform differences

Godot renders with Metal on macOS, so terrain shaders may look slightly different.

| area | macOS | Linux |
|---|---|---|
| launcher | setup installs `~/Applications/Jane's IAF (reborn).app` | setup installs a `.desktop` file |
| fonts | Arial is installed and used directly | Liberation Sans is the fallback for Arial |
| joystick | `./iafjets` sets `SDL_JOYSTICK_MFI=0` (controls.md §5.2) | — |
| user data | `~/Library/Application Support/Godot/app_userdata/iaf-reborn/` | `~/.local/share/godot/app_userdata/iaf-reborn/` |

With Liberation Sans the in-flight menu and boxes keep the exe's font sizes but use Godot's widths and heights:
GDI's exact pixels come from Arial's `hdmx` and `VDMX` tables (front-end.md §16.2), which Liberation Sans lacks.
Install Arial (Arch: `ttf-ms-fonts`) for the exact layout; `test_views` skips its pixel checks without it.

User data is Godot's `user://` folder. It holds the settings, key bindings, pilots, screenshots and the blackbox's
`flights/`.
