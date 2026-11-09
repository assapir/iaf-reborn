# Setup pipeline

Setup turns your own copy of Jane's IAF into everything the game reads under `assets/`. Three front ends run it:

- `./setup`: the setup wizard, a window that asks for the inputs and shows each step ([below](#the-wizard)).
- `tools/setup-cli.sh [--patch P] [--hebrew-iso ISO] [--imagery …] ISO [Brief.zip Menu.zip]`: the scripted way.
  `--patch` also reads the `IAF_PATCH` environment variable, `--hebrew-iso` `IAF_HEBREW_ISO`. Without the ISO only the
  imagery steps run, on an install set up before.
- `crates/iaf-setup`: the same steps in-process, for the setup wizard. Its small CLI is for testing:
  ```sh
  cargo run --release -p iaf-setup -- [--assets DIR] [--patch P] [--hebrew-iso ISO] [--imagery sentinel2,mapi2015] \
      [--guides] [--scenery] [--scenery-kinds both|buildings|trees] [--redo-all] ["/path/to/Jane's IAF.iso" [Brief.zip] [Menu.zip]]
  cargo run --release -p iaf-setup -- check <file>      # what a CD image, patch or pack is
  ```

## What you give it

| Input | Needed | What it adds |
|---|---|---|
| The English CD image | yes | the install and every conversion |
| The v1.1 patch | no | the v1.1 files (docs/v1.1.md); the v1.0 originals stay in `assets/v1.0` |
| The Hebrew CD image | no | every translated briefing and menu file, the Hebrew startup splash and Graphics page |
| `Brief.zip`, `Menu.zip` | no, only without the Hebrew CD | the Hebrew briefings and menus (docs/packs.md) |
| Imagery sources | no | modern terrain imagery (docs/imagery.md) |
| Pilot guides | no | the guides' pictures and PDFs (python3 and Firefox, or Chrome / Chromium; the renders open game windows briefly; a Firefox print that fails is tried again, then printed with Chrome / Chromium when there is one) |

The English CD is always the base: the Hebrew CD's `iafjets.exe` is the copy-protected build, and the English v1.1
patch does not apply to it (packs.md). The Hebrew CD adds the translations.

`check_cd` tells the CDs apart: the install script and archive make it a Jane's IAF CD, Hebrew menu strings make it
the Hebrew CD, and the English CD's `iafjets.exe` is a release the tools know.

## Steps

Each step waits only for the steps whose output it reads. Steps that wait for nothing in common run at the same time,
and each step uses every core inside.

| Step | Waits for | Writes |
|---|---|---|
| `extract` | | `assets/install` |
| `patch` | extract | `assets/v1.1`, `assets/v1.0`, the patched files in `assets/install` |
| `fonts`, `cockpits`, `reference`, `menu`, `missions`, `theatre`, `icon` | the install | `assets/converted/…` |
| `hebrew` | the install | `assets/packs/he` |
| `briefings`, `keys` | the install, hebrew | `assets/converted/briefings`, `keys.json` |
| `menu_he` | the install, hebrew | `assets/converted/menu_he` |
| `arm` | menu, menu_he, models | each menu set's `arm/jets/x_<plane>.png`: every extra plane's arming art, the F-15I's once `models` has made its front view |
| `aircraft`, `objects` | missions | `assets/converted/planes`, `objects` |
| `airbases` | theatre | `assets/converted/terrain/airbases.json`, `airbases/` |
| `launcher` | icon | the desktop launcher (`tools/install-launcher.sh`) |
| `extras` | the install | `assets/converted/extras/cockpit`: Modern IAF's TSD map and ground-map picture compiled into the 1998 frame (the picture's terrain from the install's `isr.bmp`), its RWR symbols and ADI ball, for the Extras options (docs/deviations.md §2: Briefing map Modern, MFDs (F-16) Real); no stamp, it runs each time (about a second) |
| `textures` | | `assets/source/ambientcg`: the zips; `assets/thirdparty/ambientcg`: the CC0 textures of Ground textures and Model detail (≈ 250 MB download; docs/rendering.md §1.4, §9) |
| `models` | aircraft | `assets/source/f15` (the FlightGear F-15's files, ≈ 20 MB download, GPL-2.0-only), `assets/converted/models/f15/f15c.glb`, the detailed F-15, and `f15i.glb`, the F-15I Ra'am, with its front view `f15i_arm.png`, which `arm` composes (docs/aircraft-models.md §6, §6.7) |
| `sentinel2`, `mapi2015-fetch`, `mapi2015` | airbases | `assets/converted/imagery` |
| `scenery-fetch` | | `assets/source/scenery`: the sources the chosen kinds need (both 520 MB, buildings 373 MB, trees 267 MB); `assets/source/roads`: the other countries' road extracts (366 MB, each optional; docs/scenery.md §1.1) |
| `scenery` | mapi2015, scenery-fetch, missions, objects, airbases | `assets/converted/roads`: the theatre's road layer (docs/scenery.md §6); `assets/converted/scenery`: the chosen kinds, buildings and trees, buildings only or trees only (docs/scenery.md §1.6) |
| `bc1` | theatre, the imagery steps | a BC1 `.dds` beside each colour tile (docs/rendering.md §1.5) |
| `guides` | the conversions and imagery | the pilot guides |

"The install" is `patch` when a patch is given, else `extract`. A failed required step stops the setup; the steps
that wait for it do not run. `launcher`, `textures`, `models`, the imagery, `bc1`, the scenery and the guides are optional: their failure stops only
the optional steps that wait for them. A required step waits for an optional one to end, not to succeed: `arm` runs
after a failed or offline `models` and leaves only the F-15I's art out.

`textures` (`iaf_tools::thirdparty`, CLI `iaf-textures`) fetches each material of `thirdparty::LISTS` with curl
into `assets/source/ambientcg` (kept under the zip's own name), checks the zip against the pinned SHA-256 and packs
its maps. A material done before is kept, so the step is up to date without the network; new packing code packs
again from the kept zips. When ambientcg.com cannot be reached the step is skipped with a note, and Graphics → MORE →
Ground textures and Model detail stay Original. A checksum mismatch (the file on ambientCG changed) fails the step and leaves nothing
behind.

`models` (`iaf_tools::f15`, CLI `iaf-convert f15-detailed <assets>`) downloads the files of `f15::SOURCE` from
raw.githubusercontent.com at a pinned fg-aircraft commit, checks each against its SHA-256 (files done before are
kept), then converts them with the original F-15 into the detailed F-15C and the F-15I. When GitHub cannot be reached the step is
skipped with a note, and the F-15 stays Original with Models Detailed. The wizard's step line names the model's authors
and licence.

`bc1` (`iaf_tools::bc1`, CLI `iaf-terrain bc1 <tile-dir>…`) pre-compresses the terrain's colour tiles: for each
`L*/c_*.jpg` of the theatre and of the imagery layers the game is set to show (Graphics → imagery: the
`imagery_israel` and `imagery_outside` values in the game's `settings.cfg`; every converted layer when there is no
settings file) it writes `c_*.dds` beside it, BC1 with every mipmap
down to 1 × 1 (a 128-byte DDS header, FourCC DXT1; a 2 × 2 box filter per mip, texpresso's range fit). The game then
loads a tile without decoding or compressing it. A tile whose `.dds` is missing or older than its JPEG is written
again, so a run after new imagery picks up only the new tiles; the step is up to date when there are none. Measured on
the 8-thread i7-1185G7: 9007 tiles (the theatre and `mapi2015_modern`) in 351 s, ≈ 39 ms a tile.

A layer chosen later in the game loads through the run-time fallback (the JPEG compressed on the CPU) until the
next setup run writes its `.dds`. Each 1024-pixel tile takes 699 KB (the JPEGs ≈ 200–400 KB), so the step adds about
1.8–3.4 times the tiles' size, and only for the chosen layers: Survey of Israel and Sentinel-2, one variant each,
come to about 10.7 GB with the theatre, against about 20 GB for every variant.

| tiles | count | JPEG | `.dds` |
|---|---|---|---|
| `terrain/theatre` | 2342 | 0.59 GB | 1.64 GB (measured) |
| `imagery/mapi2015_modern` | 6665 | 2.53 GB | 4.66 GB (measured) |
| `imagery/mapi2015` | 6665 | 2.63 GB | 4.66 GB |
| `imagery/sentinel2`, `sentinel2_modern` | 6247 each | 1.27 GB, 1.37 GB | 4.37 GB each |

## Running only what changed

Each step writes a stamp next to its output (`<output>.stamp`). The stamp lists:

- the step's code: one fingerprint of the source files that decide its output (the first line, `iaf-setup <hash>`;
  see "A step's sources" below);
- every outside file the step reads (the CD image, the patch, the packs, the extra planes), with its size and CRC-32;
- the stamps of the steps it waits for.

When a step's stamp is the same as last time and its output is still there, the step is "up to date" and does not
run. A changed input therefore redoes its step and the steps after it, and nothing else. `--redo-all` runs every
step anyway.

Downloads are kept by their source file name under `assets/source` and are never fetched again because the code
changed. A stamp holds code, inputs and the stamps before it, never a download: a fetch is up to date when its file is there under that name and its size or pinned hash matches. New code
runs the conversion again from the kept files (`crates/iaf-setup/tests/no_refetch.rs` checks this for both games'
fetchers with a `curl` and a `gdal_translate` that fail on any call).

Running setup again is how you add or redo things. The last run's inputs are kept in `assets/setup.json` (the wizard
fills its pages from them; the CLI uses them when no ISO is given, plus the options given). Add an extra, for example
`--imagery sentinel2`, and only its steps and the steps that wait for them run.

### A step's sources

New code redoes only the steps whose sources changed, and the steps that wait for them. Each stamped step lists its
sources in `STEP_SOURCES` (`crates/iaf-setup/src/stamp.rs`). A source is a file, a folder (every file in it) or
`Cargo.lock:<crate>` (the crate's locked version, for a library that decides the output, such as `image` for the
pictures). `crates/iaf-setup/build.rs` fingerprints each file. A Rust file's comment lines and `mod x;` lines are
left out of its fingerprint, because they change no output.

| Steps | Sources (besides iaf-tools' `lib.rs`, iaf-formats' `lib.rs`, `bytes.rs`, `terrain_types.rs`) |
|---|---|
| `extract` | `extract.rs`; iso9660, esa, ssf; `explode`; `crates/iaf-setup/src/bodies.rs` |
| `patch` | `patch.rs`, `rtpatch.rs`, `exe.rs`; `bodies.rs` |
| `hebrew` | `pack.rs` and extract's sources (the Hebrew CD); `bodies.rs` |
| `fonts`, `cockpits`, `briefings`, `reference`, `menu`, `menu_he`, `keys`, `missions`, `aircraft`, `objects`, `icon` | `convert.rs` and what it reaches (`aircraft.rs`, `exe.rs`, `gltf.rs`, `mis.rs`, `plane.rs`, `smooth.rs`, `upscale.rs`; emf, ini, menu, model, refs, rtf, winfnt, xfile); `image` |
| `arm` | as `cockpits`, and `bodies.rs` |
| `theatre`, `airbases` | `terrain.rs`, `airbases.rs`, `georef.rs`, `imagery.rs`, `runway_fix.rs`, their two data files; ini, lzo, ptt; `image` |
| `models` | `f15.rs`, `thirdparty.rs`, `data/f15-livery`; ac3d; `image` |
| `launcher` | `tools/install-launcher.sh`, `tools/windows/install-launcher.ps1` |

`progress.rs` (the log, the threads) is in no step's sources. The steps whose work is in iaf-setup itself (extract,
patch, hebrew, arm) have their bodies in `crates/iaf-setup/src/bodies.rs` and list that file.
`crates/iaf-setup/src/steps.rs` (each step's call, and the steps without a stamp) is in no step's sources, so a
change to a stamped step's call there needs its step redone by hand (`--redo-all`, or the step's stamp deleted). A new step whose work is more than a
call into iaf-tools puts that work in `bodies.rs`.

To add a stamped step, give it a row in `STEP_SOURCES`: the module its run function calls and every module and data
file that module reaches. `cargo test -p iaf-setup` checks that every stamped step has a row, that every listed source
exists, and that a row holds everything its files name (`crate::…`, `iaf_formats::…`, `include_str!` /
`include_bytes!`).

Before 2026-11-01 every step's stamp held one fingerprint of all of iaf-tools, iaf-formats, iaf-setup and
`Cargo.lock`, so any code change redid every step. The first run after that change redoes every step once, because
the old stamps hold the old fingerprint. After that, only the changed steps run. A setup run between that change
and the move of the step bodies into `bodies.rs` (the same day) sees one more full redo.

The imagery steps keep their own marks per work unit instead: a run converts only the units that are missing or
were made under older rules, and is up to date when there are none. `scenery-fetch` is up to date when every file has
its `.ok` mark, `scenery` when its manifest's `made_from` matches (docs/scenery.md §1.5). The guides decide per
picture.

The downloads (`scenery-fetch`, `textures`, the Survey sheets) treat a transfer under 1 kB/s for 60 s as a stall and
try a failed transfer (a stall, a reset connection) 5 more times (`CURL_PATIENCE` in
`crates/iaf-tools/src/thirdparty.rs`). `scenery-fetch` and the Survey sheets keep a failed file's `.part`, so the
next run resumes it; a server that cannot resume starts the file again. A file that fails does not stop the others
downloading beside it: they finish, the failure is logged with the file's name, and the rest of the theatre's
scenery then tries only the failed files once more. Before 2026-11-01 one failure stopped the others and deleted their
parts, so they started from zero again (a user's log: 124 MB at 0.1 MB/s).

## Uninstall

The CD launcher's UNINSTALL button (Extras → CD launcher, docs/front-end.md §18.1) asks first, then removes what the
setup wrote under `assets/` (`iaf_setup::OUTPUTS`): `install`, `v1.0`, `v1.1`, `patch`, `converted`,
`packs-none`, `hebrew-cd`, `hebrew-cd-pick`, the stamps and `setup.json`. The imported packs (`packs`), the imagery
downloads (`source/imagery`), the scenery's, the roads' and the F-15's sources (`source/scenery`, `source/roads`, `source/f15`; `iaf_setup::KEPT`) and the ambientCG zips and textures
(`source/ambientcg`, `thirdparty`) stay unless the box "Also remove the imported Hebrew packs and the
downloaded imagery" is ticked: getting them back needs the pack zips and hours of downloads. Everything else under
`assets/` stays, and so do the pilots, settings and logs in the user folder, the repo and the built extension. The
game then quits; `./setup` installs again. The launcher's INSTALL button opens the setup wizard.

## Outside programs

- curl: `textures` (ambientCG), `models` (GitHub), the Survey sheets and `scenery-fetch`.
- GDAL (`gdal_translate`, `gdalbuildvrt`, `gdalwarp`, `ogr2ogr` with its OSM driver): the imagery and `scenery` steps.
  Without it they are skipped. Windows: the scripts give winget's install (`C:\Program Files\GDAL`) its PATH,
  `GDAL_DATA` and `PROJ_LIB` (`tools/windows/gdal.ps1`, windows.md).
- gzip: `scenery` (the Microsoft footprints).
- Firefox's data.gov.il token (optional; without it the sheets download through the browser's tabs): the Survey
  sheets (imagery.md §8).
- `tools/install-launcher.sh`: the desktop launcher (its `XDG_DATA_HOME` can be set). Windows:
  `tools/windows/install-launcher.ps1`, two Start Menu shortcuts (`-Menu` puts them under another folder; setup gives
  `<XDG_DATA_HOME>/Start Menu` when it has one).
- The guides: `tools/guide_shots.sh` and `tools/guide_pdf.py` (both front ends; not on Windows yet: the step fails
  with a message).

Their output goes to the step's log.

## The wizard

`./setup` (through `tools/launch-wizard.sh`, which Modern IAF's `./modern-iaf-setup` shares) checks for Rust (cargo) and
Godot 4.7 first. A missing one opens a dialog (zenity or kdialog on Linux,
osascript on macOS, else the terminal) with the install command. Then it builds the game's extension and opens the
wizard (`iaf-reborn/setup/wizard.tscn`). `./iafjets` starts `./setup` when there is no game data, and so does the game's
start-up when `assets/converted` is missing. The desktop launcher "Jane's IAF (reborn) — Setup" runs it too.
Windows: `.\setup.ps1`, `.\iafjets.ps1` and `.\mission-editor.ps1` (`tools/windows/launch.ps1`) do the same; a
missing tool opens a message box. `tools\windows\setup-cli.ps1` runs the steps from a terminal through `iaf-setup`.

The wizard uses the original menus' colours. Pages:

1. **Welcome**: the game's name, what is needed and what is optional, the next pages, where the data goes, the
   repository link and the licence. An **Attributions…** button opens the third-party credits in a window (the
   models, the imagery and the ambientCG textures, as in the credits roll).
2. **Requirements**: a table of the parts, why each is needed, and whether it is required: the graphics driver and
   the disk space for the game (required); the disk space for imagery, GDAL, curl, python3 (the pilot guides) and
   Firefox (the Survey's download token, the pilot guides) (optional).
   A missing part shows its install command. "Check again", next to Next, looks once more.
3. **Your CD**: the English CD image, picked with Browse and checked at once. Given the Hebrew CD here, the wizard
   says so and keeps it for the next page. "Find in a folder…" looks in a folder and its subfolders (3 levels) for
   the CD images, the v1.1 patch and the Hebrew packs (`iaf_setup::scan`, in the background), and fills the empty
   fields.
4. **Optional**: the v1.1 patch, the Hebrew CD, or without it the Hebrew packs; each with a link to where to get it.
5. **Extras**: the Survey of Israel imagery (all of Israel or around the airbases), the Scenery (buildings and
   trees, buildings only or trees only; only with the Survey imagery ticked or on disk), the Sentinel-2 imagery,
   "Bring the imagery up to date" (only with imagery on disk; it shows how many units older rules made) and the
   pilot guides. Each shows its downloads and disk use (no download times: they depend on the network), and is
   greyed with the reason when a program it needs is missing:
   - Survey of Israel, all of Israel: 79 sheets, about 17 GB of downloads (kept in `assets/source`), about 5 GB
     converted. Around the airbases: 9 sheets, about 2 GB of downloads. Sheets already downloaded are not
     downloaded again. Under the scope: how to give setup Firefox's data.gov.il pass before Install (paste a sheet's
     link into Firefox, cancel the download), what happens without it (the sheets open in the web browser, four at
     a time), and a "Copy a sheet's link" button (imagery.md §8).
   - Scenery: the download of the chosen kinds, from the pinned files' sizes, with the rest of the theatre's and the
     other countries' OpenStreetMap extracts (both 2.7 GB, buildings only 2.3 GB, trees only 0.9 GB; scenery.md §1.6,
     §1.7). Files already downloaded are kept.
   - Sentinel-2: about 28 GB read over the network, about 11 GB on disk (the tiles 2.6 GB, their pre-compressed
     copies 8.7 GB). Units already converted are not read again.

   Under the extras one line gives the expected size of `assets/` for the choices, updated as they change:
   "Expected size of assets: about 24 GB (19 GB of it downloads); 6.2 GB of it is new; 120 GB free". The total is
   what is on disk now plus the new part. Each chosen part (the game, each extra) counts only what it lacks on disk
   as new; a part with 85 % or more of its size on disk counts as there ("nothing of it is new"). The part sizes are constants in `iaf-reborn/setup/wizard.gd`, measured on the developer's laptop. The line
   turns orange when the new part is larger than the free space.
6. **Summary**: the inputs, the expected size line (orange when it does not fit) and the number of steps.
7. **Install**: one row per step. Before Install each row says whether it is "up to date" or "will run"
   (`iaf_setup::preview`, checked in the background: it reads the CD images). Then its state and progress (a long
   step adds the time left at its pace so far, once it has run 30 s), the log, Cancel, "Redo everything", and a
   "redo" tick per step: a ticked step runs again although it is up to date. The steps after it stay up to date; tick them too
   to redo them. When a step fails, the page names the error and the log file, and says to do what the error says,
   then Back and Install again (the steps that finished are kept). An error naming a data.gov.il link (the Survey's
   pass expired) adds "Copy the data.gov.il link above".
8. **Done**: "Start the game".

The pages start from the last run's inputs (`assets/setup.json`). The log names files relative to the assets
folder. Each run also writes its whole log, with full paths and every step's state, to
`assets/logs/setup-<date>-<time>.log`. The log's first line names that file, and so does the message when a step
fails. Uninstall keeps `assets/logs`.
