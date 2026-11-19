# Running on macOS

The code builds and runs on macOS (Apple silicon), with the same Rust tools and setup steps as on Linux.

## Install

1. Install the tools:
   ```sh
   brew install rustup coreutils      # coreutils: `timeout` for tools/test.sh
   brew install --cask godot          # Godot 4.7 (iaf-reborn/iaf.gdextension and ./setup require it)
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

## A monitor beside a Retina screen

Godot 4.7 on macOS renders every window at the largest screen scale. With a MacBook's Retina screen attached, a
game window on a plain (1×) monitor beside it rendered at twice the monitor's pixels across, and macOS halved the
picture: four times the work, and every thin line halved. The game leaves it so: the halving acts as 2×
supersampling, and the user preferred that cockpit (2026-11-15: "I think just revert this change"). From 14 to 15 Nov
2026 the game turned hiDPI off on such a monitor, writing `display/window/dpi/allow_hidpi=false` into the project's
`override.cfg` (`iaf-reborn/override.cfg`, `modern-iaf/override.cfg`; not in git) and restarting once; the 3D view
then rendered at the upscaler's 0.77 of the monitor's 2,560 pixels across, and the cockpit came out soft. A start-up
that finds that line removes it (the rest of the file kept) and restarts once. Details: [real-hud.md](real-hud.md) "A
1× monitor beside a Retina screen".

## Tests

`tools/test.sh` calls `timeout`. Put the GNU tools first on the PATH:
`PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"`. The script does not see a shell alias.

## Platform differences

Godot renders with Metal on macOS, so terrain shaders may look slightly different.

| area | macOS | Linux |
|---|---|---|
| launcher | setup installs `~/Applications/Jane's IAF (reborn).app`; Modern IAF's setup installs `~/Applications/Modern IAF.app` and its Setup, with `modern-iaf/branding/icon.icns` (its Done page's tick, modern-iaf/docs/setup.md "Applications menu") | setup installs `.desktop` files |
| fonts | Arial is installed and used directly | Liberation Sans is the fallback for Arial |
| joystick | `./iafjets` sets `SDL_JOYSTICK_MFI=0` (controls.md §5.2) | — |
| keys | Cmd stands for Ctrl (macOS takes Ctrl + arrows for its desktops); the key names say Cmd (controls.md §2) | Ctrl |
| user data | `~/Library/Application Support/Godot/app_userdata/iaf-reborn/` | `~/.local/share/godot/app_userdata/iaf-reborn/` |

With Liberation Sans the in-flight menu and boxes keep the exe's font sizes but use Godot's widths and heights:
GDI's exact pixels come from Arial's `hdmx` and `VDMX` tables (front-end.md §16.2), which Liberation Sans lacks.
Install Arial (Arch: `ttf-ms-fonts`) for the exact layout; `test_views` skips its pixel checks without it.

User data is Godot's `user://` folder. It holds the settings, key bindings, pilots, screenshots and the blackbox's
`flights/`. The game's logs are in its `logs/` folder: [logs.md](logs.md).
