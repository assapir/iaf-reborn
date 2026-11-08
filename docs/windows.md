# Running on Windows

The code builds and runs on Windows 10 / 11 (x64), with the same Rust tools and setup steps as on Linux. The scripts
are PowerShell; no bash is needed. Checked on Windows 11 with Intel Iris Xe graphics (Vulkan).

## Install

1. Install the tools and allow your own scripts (Windows runs none by default):
   ```powershell
   winget install Git.Git Rustlang.Rustup GodotEngine.GodotEngine
   winget install Microsoft.VisualStudio.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
   The Build Tools' C++ workload holds the linker (`link.exe`) Rust's MSVC toolchain needs; without it every build
   ends in "linker `link.exe` not found".
2. Open a new terminal: it picks up the new PATH. winget without admin rights adds no `godot` command; the scripts
   find Godot in winget's packages folder (or read `$env:GODOT`).

## Build and run

```powershell
git clone https://github.com/assapir/iaf-reborn; cd iaf-reborn
.\setup.ps1       # the setup wizard (or tools\windows\setup-cli.ps1, below)
.\iafjets.ps1     # builds the extension (target\release\iaf_godot.dll) and starts the game
```

The Godot projects `iaf-reborn/` and `iaf-2026/` reach the engine folders in `shared/` through the links
`iaf-reborn/shared` and `iaf-2026/shared`, committed as symlinks. Git for Windows checks a symlink out as a small text file unless symlinks are enabled, so
`tools/windows/links.ps1` replaces each with a directory junction (no admin rights needed) and tells git to keep the
committed link. `launch.ps1` runs it before every start; after a clone, run it by hand before starting Godot directly.

`.\iafjets.ps1 --mission 311` passes its arguments to the game, as `./iafjets -- --mission 311` does;
`.\mission-editor.ps1` starts the mission editor. `.\iaf2026.ps1` and `.\iaf2026-setup.ps1` start IAF 2026 and its
setup wizard (iaf-2026/docs/setup.md). All five run `tools/windows/launch.ps1`.

`tools\windows\setup-cli.ps1` is the scripted setup. It runs the wizard's pipeline through `iaf-setup`, so it takes
`iaf-setup`'s options (`crates/iaf-setup/src/bin/iaf-setup.rs`), not `tools/setup-cli.sh`'s:

```powershell
tools\windows\setup-cli.ps1 --patch "C:\path\to\v1.1.exe" "C:\path\to\Jane's IAF.iso"
```

## Optional extras

| tool | install | needed for |
|---|---|---|
| GDAL | `winget install GISInternals.GDAL` | modern terrain imagery, scenery (not yet tested on Windows) |
| curl | ships with Windows (`C:\Windows\System32\curl.exe`) | the downloads |
| Firefox | `winget install Mozilla.Firefox` | the Survey of Israel sheets' fast download: setup reads the data.gov.il token from its profile (imagery.md §8); without it the sheets download through the default browser's tabs |

The GDAL installer puts it on no PATH and sets no data folders; without `PROJ_LIB` every reprojection fails with
"Cannot find proj.db". The scripts (`tools/windows/gdal.ps1`) find it in `C:\Program Files\GDAL` and give their run,
and the setup steps it starts, its folder on PATH, `GDAL_DATA` and `PROJ_LIB`, unless these are set already. GDAL
installed elsewhere: set the three yourself.

Not on Windows yet (it runs a bash script): the pilot guides (`tools/guide_shots.sh`); setup's guides step fails
with a message saying so.

## Tests

`cargo test --workspace` runs as everywhere. `tools/test.sh` is bash: run the Godot tests one by one with the
console build of Godot, which prints to the terminal and waits:

```powershell
$godot = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine*\Godot_v*_console.exe").FullName
$env:IAF_DEFAULT_SETTINGS = '1'
& $godot --headless --audio-driver Dummy --path iaf-reborn -s ../tests/godot/test_radar.gd --log-file "$env:TEMP\test_radar.log"
```

A test passes when it prints `RESULT PASS` and no `SCRIPT ERROR` (CLAUDE.md).

## Contributing from Windows

The repository is LF. Git for Windows checks text files out as CRLF by default (`core.autocrlf=true`), and
`gdformat` writes CRLF; under WSL every file then shows as changed. Before working in a clone:

```powershell
git config core.autocrlf false; git config core.eol lf
```

A PowerShell script stays ASCII: Windows PowerShell 5.1 reads a script without a byte-order mark as ANSI, and an
em dash in one breaks its parsing.

## Platform differences

| area | Windows | Linux |
|---|---|---|
| scripts | `.\setup.ps1`, `.\iafjets.ps1`, `.\mission-editor.ps1`, `.\iaf2026.ps1`, `.\iaf2026-setup.ps1` | `./setup`, `./iafjets`, `./mission-editor`, `./iaf2026`, `./iaf2026-setup` |
| launcher | setup adds "Jane's IAF (reborn)" and its Setup to the Start Menu (`tools/windows/install-launcher.ps1`) | setup installs a `.desktop` file |
| fonts | Arial ships with Windows | Liberation Sans is the fallback for Arial |
| user data | `%APPDATA%\Godot\app_userdata\iaf-reborn\` | `~/.local/share/godot/app_userdata/iaf-reborn/` |

The original HUD's numbers round as the exe did on every platform (cockpit.md, the HUD port): Godot's own `%`
formatting goes through the platform's C library, which rounds a halfway value differently on Windows and Linux.

User data is Godot's `user://` folder. It holds the settings, key bindings, pilots, screenshots and the blackbox's
`flights/`. The game's logs are in its `logs/` folder: [logs.md](logs.md).
