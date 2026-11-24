# Release bundles: the nightly

Each game has a download per system that runs without Rust, Godot or Python: unpack it, start the game, its setup
wizard builds the data, play. The bundles are built by [the Nightly workflow](../.github/workflows/nightly.yml) and
published as one pre-release, `nightly`, on the repository's Releases page. The plan is the user's (23 November 2026):
nightly builds only, both games, the Mac build unsigned.

## 1. The downloads

| game | Linux | macOS (Apple silicon) | Windows |
|---|---|---|---|
| Modern IAF | `modern-iaf-nightly-linux-x86_64.tar.gz` | `modern-iaf-nightly-macos-arm64.dmg` | `modern-iaf-nightly-windows-x86_64.zip` |
| Jane's IAF reborn | `iaf-reborn-nightly-linux-x86_64.tar.gz` | `iaf-reborn-nightly-macos-arm64.dmg` | `iaf-reborn-nightly-windows-x86_64.zip` |

A bundle holds its game only: the exported Godot game (program and `.pck`), the shared library (`libiaf_godot`), the
project files that setup and the Rust side read by path, `LICENSE` and `credits.md`. The setup steps run inside the
game (`IafSetup`), so no separate setup program ships.

- **Linux**: a folder with `Modern IAF.x86_64` (or `IAF Reborn.x86_64`) and `setup`, which starts the game's wizard
  again.
- **Windows**: a folder with `Modern IAF.exe` (or `IAF Reborn.exe`) and `Setup.cmd`. The program is unsigned: on
  SmartScreen's "Windows protected your PC", choose More info, then Run anyway.
- **macOS**: a disk image with the app (Godot's universal program, our library for Apple silicon only), a link to
  Applications and "Read me first.txt". The app has an ad-hoc signature only (Apple silicon runs no code without one)
  and is not notarised, so macOS stops its first start. Right-click the app, choose Open, then Open again; or run once
  `xattr -dr com.apple.quarantine "/Applications/Modern IAF.app"`. Intel Macs are not built for.

Both games' bundles also hold setup's outside programs in `tools/` (below), so a player installs nothing for Modern
IAF. Jane's IAF reborn: nothing for the game and the CD. The optional imagery of the Survey of Israel needs python3 and
  Firefox, as from the checkout. The pilot guides are built from the checkout only (`tools/guide_shots.sh`): the
  wizard shows their row disabled.

### The setup tools

Setup runs GDAL's command-line programs (`gdalwarp`, `gdal_translate`, `gdalbuildvrt`, `gdalinfo`, `ogr2ogr` with its
OSM driver) and curl ([setup.md](setup.md) "Outside programs"). A bundle carries them: `tools/release/tools_env.sh`
installs conda-forge's builds (`libgdal-core` 3.13.3, the checkout's GDAL, with `curl` and `ca-certificates`) through
micromamba (its release pinned and its checksum checked) into one layout on every system: `bin/` (on Windows with
the DLLs, the MSVC runtime too), `lib/`, `share/gdal`, `share/proj`, `ssl/cacert.pem`, `licenses/<package>/`, each
package's own licence files (GDAL and PROJ MIT, curl's licence; GEOS LGPL-2.1, librttopo and lzo GPL-2.0, readline GPL-3.0, all compatible
with the project's GPL-3.0), and `SOURCES.txt`:
every package's exact version, build, licence and download, where its source and recipe are, and the offer of the
source. The workflow passes that folder to
`bundle.sh` in `$IAF_TOOLS`; it is copied in as `tools/` (in the macOS app under `Contents/Resources`). A bundle
built by hand without `$IAF_TOOLS` has none, and setup needs GDAL and curl installed, as the checkout does.

At start, a bundled game whose tools folder holds bin puts that first on the PATH and sets `GDAL_DATA`, `PROJ_DATA` /
`PROJ_LIB` and `CURL_CA_BUNDLE` / `SSL_CERT_FILE` to its CA file (`Settings._use_bundled_tools`, in `Settings._init`,
before any setup thread). The programs setup starts inherit them; the wizard's GDAL and curl checks
find them. On Windows a program started by name is looked up in `System32` before the PATH, so setup runs Windows'
own curl there (it takes the same CA file); GDAL's programs come from the bundle. On macOS the game also clears
the download's quarantine flag on its tools folder (`xattr -dr com.apple.quarantine`), so Gatekeeper does not stop
the programs that the player's right-click, Open did not cover. The checkout is unchanged: it uses the installed GDAL and curl. The Microsoft footprints' `.csv.gz` are read
in-process (flate2), so no gzip either.

Tried and dropped (23 November 2026): GDAL's work in Rust (GeoTIFF and Cloud Optimized GeoTIFF reads over HTTP,
reprojection with GDAL's resampling kernels, OpenStreetMap's multipolygons as OGR builds them). It is weeks of work, and
its terrain and scenery would differ from the approved builds; the bundled programs give the same output as the checkout.

The launcher step (desktop entries) is skipped in a bundle: the game's folder or app is its launcher. Modern IAF's
Done page shows no menu tick there.

## 2. The data folder

In the checkout the data is `assets/` beside the projects, as before. A bundle never writes its own folder, so an
update replaces the game and keeps the data. Its data folder is per user, shared by both games (as `assets/` is):

| system | the data folder |
|---|---|
| Linux | `~/.local/share/IAF/assets` (or `$XDG_DATA_HOME/IAF/assets`) |
| macOS | `~/Library/Application Support/IAF/assets` |
| Windows | `%LOCALAPPDATA%\IAF\assets` |

The wizard's first page shows it with a Change… button (bundles only): the folder picked is written to `IAF/data-folder.txt`
in the same per-user folder, and the wizard opens again on it. Data already built stays where it was.

`$IAF_ASSETS_DIR` overrides both, as before (tests). The settings, pilot records, flights and logs stay in Godot's
user folder (`user://`, per game), in the checkout and in a bundle alike.

### One place

`Settings` (shared/settings.gd) answers every path:

| function | the checkout | a bundle |
|---|---|---|
| `bundled()` | false | true (`OS.has_feature("template")`) |
| `app_root()` | the repo root | the game's folder; `Contents/Resources` in the macOS app |
| `assets_dir()` | `<repo>/assets` | `data_folder()` |
| `disk_path("res://…")` | `globalize_path` | the copy under `app_root()/<project folder>/` (`res://shared/…`: `app_root()/shared/…`) |
| `readable("res://…")` | the path itself | for the folders the `.pck` leaves out, the copy on disk |
| `version()` | `dev` | the nightly's version |

A file that Rust or a font reader opens by path goes through `disk_path`: in an exported game the project's files are
in the `.pck`, which `globalize_path` does not reach. The folders with a `.gdignore` (`modern-iaf/data`, `branding`,
`manuals`, `shared/extra`) are never in the `.pck`, so every GDScript reader of them (`Settings.load_json`, the image
decoder, the glTF reader, the folder listings) opens `readable(path)`; `tools/release/bundle.sh` copies those folders
beside the game. In an exported game a `res://` file outside the `.pck` would otherwise be looked up from the working
folder.

Godot's export templates have no texture encoder behind `Image.compress`. The terrain and the detailed models
compress their images to S3TC through `Img.compress_s3tc` (shared/util/img.gd): Godot's encoder in the checkout,
`IafImage.bc1` in a bundle (BC1 by texpresso's range fit, the encoder of setup's `.dds` tiles). The extension is
callable from the main thread only, so an image decoded on a worker is compressed when the main thread takes it
(`terrain.gd` `_finish_jobs`, `gltf.gd` `open`). An image with alpha stays uncompressed there. Most terrain tiles
come as setup's `.dds` and need none.

The setup wizard gives `app_root()` to `IafSetup` as the repo (`modern-iaf/data`, `shared/extra`). In a bundle the game starts its own wizard: Modern IAF while its data is
missing (no `converted/modern-iaf/missions`), Jane's IAF reborn without `converted/`, and both with `--setup`
(`--setup --install`: unattended, §5).

## 3. Versions

| game | a nightly's version | in the checkout |
|---|---|---|
| Modern IAF | `0.2.0-nightly.<YYYYMMDD>+<short hash>` | `dev` |
| Jane's IAF reborn | `1.1.0-nightly.<YYYYMMDD>+<short hash>` | `dev` |

The base numbers are [tools/release/versions.txt](../tools/release/versions.txt). `tools/release/bundle.sh` writes the
version into the exported project's `application/config/version` (the checkout's stays `dev`). Modern IAF shows it
under the title of its Attributions screen, Jane's IAF reborn in its credits roll under "IAF-REBORN", and both print
it in the game log's first line.

## 4. The workflow

The Nightly workflow runs every day at 02:41 UTC:

1. **changed**: compares `main` with the commit of the `nightly` tag; when they are the same, nothing else runs.
2. **bundle**, on Linux, macOS (arm64) and Windows: builds the extension, installs Godot 4.7.2 and this system's
   export templates (`tools/ci_install_godot.sh templates`, the templates file cached), imports both projects, runs
   `tools/release/bundle.sh` for each game and starts each bundle headless (`tools/release/smoke.sh`). The bundles
   stay as the run's artifacts for 7 days.
3. **publish**, on `main` only: deletes the `nightly` pre-release and its tag, then creates them again at this commit
   with the six bundles. The notes list the commits since the last nightly and the two unsigned-program notes.

Run workflow (by hand) builds the bundles from any branch as artifacts; its "publish" box also replaces the
pre-release, on `main` only.

The exports are each project's `export_presets.cfg` (Linux, Windows, macOS): every resource and `*.json`, without
`tests/` and `tools/`. Jane's IAF reborn's boot splash is the CD's art in the checkout; in a bundle it shows none
(`boot_splash/show_image.template=false`).

## 5. Building a bundle by hand

From a checkout with the extension built and the project imported, and Godot with its export templates:

```sh
tools/release/tools_env.sh /some/tools              # setup's GDAL and curl (optional; needs curl, jq, a network)
IAF_TOOLS=/some/tools tools/release/bundle.sh modern-iaf /some/out   # or iaf-reborn; prints the bundle's path
tools/release/smoke.sh /some/out/modern-iaf-nightly-linux-x86_64.tar.gz
```

`smoke.sh` unpacks the bundle and runs it headless for 900 frames on an empty data folder: the game opens its setup
wizard. It fails on a `SCRIPT ERROR`, the game's crash page (a `crash:` line), a missing version line or a non-zero exit.
With `tools/`, it then runs the bundled programs in the environment that `Settings._use_bundled_tools` sets (the script
sets the same variables): `ogr2ogr` has the OSM driver, PROJ knows
EPSG:2039, curl fetches over https and `gdalinfo` reads a GLO-30 tile's header through `/vsicurl/`.
Arguments after the bundle go to the game, and then the game runs until it quits. An exported game runs no test script (`-s` is the editor's), so the
checks of a bundle go through the game's own arguments:

```sh
# setup, unattended: the run on the saved choices; exit 0 when it finished (the wizard's --install)
IAF_ASSETS_DIR=<data folder> tools/release/smoke.sh <bundle> -- --setup --install
# a mission flown from the front end (Modern IAF)
IAF_ASSETS_DIR=<built data> tools/release/smoke.sh <bundle> --quit-after 3000 -- --mission <id>
```

`--setup --install` is also the scripted setup for players: the wizard starts the run at once on the last run's choices
(the defaults the first time), prints each step's end state and quits, 0 when the run finished and 1 when it failed.

## 6. Checks

- Linux and macOS: each bundle built by the workflow, then run here (§5): `smoke.sh`; Modern IAF's setup unattended
  into a data folder that holds only the built terrain (so the offline steps run: units and weapons, flight data,
  sounds and voices, airbases, missions; scenery and textures left out); a mission flown on the laptop's data.
- Windows: the workflow's smoke run.
