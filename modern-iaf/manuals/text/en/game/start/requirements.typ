#import "/modern-iaf/manuals/layout/manual.typ": *

This section lists what the computer needs before you start setup (@setup).

=== The computer <requirements-computer>

#idx("Linux")#idx("macOS")#idx("Windows")The game runs on Linux, on macOS and on Windows 10 or 11 (64-bit). It is started from its folder with a script; the scripts' names are in the table.

#grid-table(
  (auto, 1fr, 1fr),
  ([], [Linux and macOS], [Windows (PowerShell)]),
  [Setup], [`./modern-iaf-setup`], [`.\modern-iaf-setup.ps1`],
  [The game], [`./start-modern-iaf`], [`.\start-modern-iaf.ps1`],
)

The game needs no data from any other game. Setup downloads all its data once, under open licences. The sources and their licences are listed in @attributions.

=== The programs <requirements-programs>

#idx("GDAL")#idx("curl")#idx("Godot")#idx("Rust")The scripts build the game from its source, so the computer needs four programs. The scripts check the first two when they start and say how to install a missing one. The #term("Setup wizard")'s first page checks the other two under #stp("needs"), shows each as #stp("found") or #stp("missing"), and names the command that installs a missing one.

#grid-table(
  (auto, 1fr, 1.4fr),
  ([Program], [What it is for], [How to install it]),
  [Rust (cargo)], [Builds the game's program.], [Linux: rustup.rs. macOS: `brew install rustup`, then `"$(brew --prefix rustup)/bin/rustup" default stable`. Windows: `winget install Rustlang.Rustup`.],
  [Godot 4.7], [Runs the game and the setup wizard.], [Linux: godotengine.org. macOS: `brew install godot`. Windows: `winget install GodotEngine.GodotEngine`.],
  [GDAL], [Reads the terrain heights and the imagery. Cuts the inland water, the buildings and the roads from the map data.], [Linux: `sudo apt install gdal-bin` (Arch: `sudo pacman -S gdal`). macOS: `brew install gdal`. Windows: `winget install GISInternals.GDAL`.],
  [curl], [Downloads the data.], [Linux: `sudo apt install curl`. macOS and Windows 10 or later have it.],
)

On Windows, Rust also needs the C++ workload of Microsoft's Visual Studio Build Tools, and PowerShell must be allowed to run your own scripts:

```
winget install Git.Git Rustlang.Rustup GodotEngine.GodotEngine
winget install Microsoft.VisualStudio.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Open a new terminal after these commands, so that it finds the new programs.

#note[On Windows the setup steps that use GDAL (the imagery and the buildings, trees and roads) are not yet tested.]

=== Disk space and downloads <requirements-disk>

#idx("Disk space")#idx("Download sizes")Setup downloads the data once and keeps the downloaded files, so a later setup run uses them again. The first page of the setup wizard shows the free disk space and what the build needs.

#grid-table(
  (auto, 1fr, 1fr),
  ([], [#stp("s2")], [With the Survey of Israel photo]),
  [Download, once], [Terrain heights: 627 MB. Satellite imagery: 11.4 GB.], [The same. The Survey of Israel's 79 sheets (17 GB) must be on the disk already (@setup-imagery).],
  [Disk use in all], [About 12.5 GB], [About 15.6 GB, and the sheets' 17 GB],
  [Time of the first setup], [About 17 minutes, of which the download is about 14 minutes at 14 MB a second], [About 1 hour 42 minutes],
)

The times were measured on a laptop with 8 processor threads. Before the first setup, the script builds the game's program once; that took about 6.5 minutes on the same laptop.

The optional step #stp("step_sim-textures") downloads about 310 MB more. The wizard shows each optional step's download and disk use under the step's name (@setup-steps).

When the free space is too small for every imagery file, setup reads a part of them online during the build and keeps the rest. The first page then says how much it reads online.

An internet connection is needed for the downloads only. With every downloaded file on the disk, setup and the game use no network.
