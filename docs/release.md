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
  `xattr -dr com.apple.quarantine "/Applications/Modern IAF.app"`. It needs macOS 13 or later (the baked shaders,
  "Baked shaders" below). Intel Macs are not built for.

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
pre-release, on `main` only. Its "tag" field (default `nightly`) names the release to replace: another tag, a test
channel such as `nightly-test`, is published from any branch and leaves the public `nightly` as it is (the update's
end-to-end test, §7.3: `gh workflow run nightly.yml --ref <branch> -f publish=true -f tag=nightly-test`).

The exports are each project's `export_presets.cfg` (Linux, Windows, macOS): every resource and `*.json`, without
`tests/` and `tools/`. Jane's IAF reborn's boot splash is the CD's art in the checkout; in a bundle it shows none
(`boot_splash/show_image.template=false`).

### Baked shaders

Every preset has Godot's shader baker on (`shader_baker/enabled`): the export compiles the shaders of the exported
resources into the `.pck` for the system's graphics driver (Vulkan on Linux and Windows, Metal on macOS), so a
bundle's first start does not compile them: Godot's own shaders and the project's `.gdshader` files (333 bake steps
for Modern IAF). The pipelines (a shader with its draw state) are the driver's and still compile on the player's
machine.

The bake includes the flight's material list that the front end warms up ([rendering.md](rendering.md) §1.6 "The
first start", `shared/util/flight_materials.tres`), so the built-in materials' shaders the flight draws are baked
too (1646 bake steps for Modern IAF).

The macOS presets set the minimum macOS to 13 (`application/min_macos_version_arm64`). The baker picks its Metal profile
from that version, and only from macOS 13 does it compile with argument buffers, as Godot does at run time on Apple
silicon. With Godot's default 11.00 it baked the shaders with one Metal slot per texture and sampler; a material's
sampler then got slot 17 (Metal allows 0–15), its shader failed ("'sampler' attribute parameter is out of bounds"), and
the bundle stopped at the flight's start (found 2026-11-25 in Godot 4.7.2's
`shader_baker_export_plugin_platform_metal.cpp` and `metal_device_profile.cpp`). The earlier bake without the list
worked only because Godot's own shaders use few samplers (inferred). So the macOS bundles need macOS 13 or later.

A baked macOS bundle prints three `ERROR` lines at launch ("Not enough bytes for uniform in shader container"): Godot
then compiles that one shader itself, and the game runs on.

The baker needs a rendering device, so `bundle.sh` exports without `--headless` (stopped after 30 minutes): on Linux
under `xvfb-run` (the workflow installs Mesa's software Vulkan, `mesa-vulkan-drivers`, and Xvfb), on macOS with the
runner's Metal, on Windows with Direct3D 12's software adapter when Vulkan has no device (the project's
`fallback_to_d3d12`). It checks the `.pck` for baked shaders (`shader_cache/….vulkan.cache`, `.metal.cache` or
`.d3d12.cache`); when there are none it exports again headless, unbaked, with a `::warning::` in the run's log, so the
nightly still ships. `IAF_BAKE=0` skips the baker. Baking makes the `.pck` larger (Modern IAF: 2.1 to 4.2 MB on Linux,
2.1 to 39 MB on macOS) and adds a few seconds to an export.

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

## 7. Updates on start

On each start, both games look for two things and, when they find one, show a dialog in the middle of the screen
with **Update**, **Later** and a **Don't ask me again** box (en / he, `shared/util/update_strings_*.json`). A click
outside the dialog is Later. The user's requests: "we need to add auto update on startup for released assests", then
"same for setup" (24 November 2026); "a pop-up, not like that? Clicking outside dismiss it, have don't ask me again
option. In setting, add option to always download and never ask or download" (25 November 2026).

The setting "Updates on start" (`Settings.update_mode`; Modern IAF: Settings → Updates, Jane's IAF reborn: Extras)
has three choices:

| Choice | On start |
| --- | --- |
| Ask (the default) | the dialog |
| Always download | no question: a newer nightly downloads and installs at once (its progress shows in the dialog); setup's steps run in the wizard, whose Back goes on to the game after a failed run |
| Never | no check |

With **Don't ask me again** ticked, the button pressed becomes the setting: **Update** sets Always download,
**Later** (or a click outside) sets Never. A line under the box says so. A settings file from before the three
choices keeps its choice: the old switch's Off reads as Never. Scripted runs (`IAF_DEFAULT_SETTINGS=1`) and
`--mission` runs check nothing.
The logic is Rust's (`crates/iaf-setup/src/update.rs`, through `IafSetup`); `shared/util/updater.gd` shows it.
Each game's first screen calls `Updater.start` (Modern IAF `menu/front_end.gd`, Jane's IAF reborn `menu/startup.gd`).

### 7.1 A newer nightly (a bundle only)

1. The game reads the release's `nightly.json` (`<release>/nightly.json`, one HTTPS request with the User-Agent
   `IAF-update` and an 8 s timeout). Offline, or without the file: no dialog, the game goes on. The checkout's
   version is `dev` and checks no release.
2. `update::pick` takes this game's download for this system from the manifest; `update::newer` compares its version
   with the game's own: a later base, then a later day; on the same base and day a different build (the nightly is
   the latest one). Never from or to a version that is not a nightly's. A second run of the workflow on the same day
   is newer by this rule; so is an older commit published again that day (a re-run of an old ref): the release then
   holds that build, and the game takes it, as the release is what the nightly is.
3. **Update** first refuses, with one line in the dialog, when the data folder is inside the game's folder (it would go with the
   old version), and removes an earlier update's leftovers beside the game's folder (`update::cleanup`). It then
   downloads it into the per-user folder's `updates/` (`Settings.data_home()`), with the percentage on the
   line, while a shade over the screen holds the game. `update::verify` checks its size and SHA-256 against the
   manifest; a mismatch deletes the file and the line says the update failed.
4. `update::unpack` unpacks it beside the game's folder, into `.<folder>.update/` (Linux: `tar`; Windows: the zip,
   in Rust; macOS: the disk image attached read-only and the app copied with `ditto`, which keeps its signature).
   When the game's folder's parent is not writable (an app run from the disk image, or translocated by macOS), the
   line says to move the game to a folder the player can write to.
5. The game starts the unpacked copy with `--update-apply <game folder> --update-pid <its pid>` and quits. Every
   program the update starts runs in the game's folder's parent (`update::launch`), never inside the game's folder:
   on Windows a program's working folder cannot be moved. The copy waits in Rust for the old game's process to end
   (`update::wait_exit`, 60 s at most: `ps` on Linux and macOS, where an ended process not yet reaped counts as
   ended; `tasklist` on Windows); when it still runs, the
   copy starts it again with `--update-failed`. Then `update::swap`: the game's folder becomes `.<folder>.old/`
   (tried again for up to 30 s, as Windows keeps a folder locked a moment after its program quit) and the new
   version is copied into the game's folder; a failed copy puts the old one back. A swap is refused while an
   earlier `.<folder>.old/` is still there. A failed update deletes its download.
6. The copy starts the game again from its folder with `--update-done --update-pid <its pid>` and waits for it to
   write `updates/started-<project>` (one file per game, as both share the per-user folder; `update::start_and_wait`
   keeps the program's handle). A start that is slow but alive (macOS's first-launch check) is waited for up to
   10 minutes, then stopped. When the new version ends or is stopped without writing the file, `update::rollback`
   moves it aside to `.<folder>.failed/`, puts the old one back and starts it with `--update-failed`: its line says
   the update did not install. When the old one cannot be put back (also after a copy whose own rollback failed), the
   copy stays open and its line says which folder to move back where. The swap and the wait run on threads, so the
   copy's window keeps drawing.
7. The new version, once the copy has quit, removes `.<folder>.old/`, `.<folder>.update/` and
   `.<folder>.failed/` (`update::cleanup`, on its own thread; never the folder the program runs from). The data
   folder is never touched.

The manifest is written by `tools/release/manifest.sh` in the workflow's publish job: every bundle's name, version,
size and SHA-256. The workflow's `changed` job sets one `IAF_NIGHTLY=<YYYYMMDD>+<hash>` for all bundles and the
manifest, so their versions agree. `$IAF_UPDATE_URL` replaces the release: a URL, or a folder that holds a
`nightly.json` and the bundles (a local release, as the test uses).

### 7.2 Setup steps to run again (a bundle and the checkout)

After the release check (or without one), `update::setup_stale` (IafSetup job `setup_stale`) finds the steps of
the last run's choices whose stamps no longer hold: their code or inputs changed, or a newer version added a step
([setup.md](setup.md) "Running only what changed"). The check only reads: it moves and adopts nothing (the wizard's run does that). A user's own file (the CD image,
the patch, the Hebrew packs) keeps its stamp's line while its size is the one listed, so no start reads a whole CD
image; a file that moved or changed size is read, and its step then shows when it would run again. Steps that keep
no stamp of their own decide for themselves (imagery, the scenery's
fetch, the guides) and are left out, as is the launcher in a bundle. Before the first setup it finds nothing (the
game opens the wizard anyway). The dialog gives the number of steps and, when one of them would download a source that
is not on the disk yet, its size (Modern IAF's scenery and textures from their pinned sizes, the terrain's tiles as
"new data", the remake's F-15 sources). **Update** opens the setup wizard on its Install page and starts the run at
once (`Settings.setup_update`); a finished run goes on to the front end, a failed one stays on the page with its log.
Nothing on the disk is downloaded again: the steps' sources stay under `assets/source` by name.

### 7.3 Checks

- `cargo test -p iaf-setup update`: the version compare, the manifest's pick, the size and SHA-256 check, the swap
  (refused over an old folder), rollback and cleanup, a process waited for and one started in another folder, a
  Linux bundle unpacked.
- `modern-iaf/tests/test_update.gd` (headless, offline): an older nightly against a local release folder finds the
  newer one, downloads, checks and unpacks it beside a scratch game folder, and the swap puts it in place; Always
  download does it without the dialog; a click outside the dialog is Later, and with Don't ask me again it sets Never; a wrong
  SHA-256 is refused; with no newer one, setup's check on a scratch data folder shows its steps.
- End to end, by hand: two runs of the workflow into the `nightly-test` channel (§4), the older build's bundle
  started with `IAF_UPDATE_URL=https://github.com/assapir/iaf-reborn/releases/download/nightly-test` and a scratch
  per-user folder (Linux: `XDG_DATA_HOME`), then the test release deleted (`gh release delete nightly-test
  --cleanup-tag`).
