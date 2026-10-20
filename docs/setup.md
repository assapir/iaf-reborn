# Setup pipeline

Setup turns your own copy of Jane's IAF into everything the game reads under `assets/`. Three front ends run it:

- `./setup`: the setup wizard, a window that asks for the inputs and shows each step (below).

- `tools/setup-cli.sh`: the scripted way (README "Quick start").
- `crates/iaf-setup`: the same steps in-process, for the setup wizard. Its small CLI is for testing:
  ```sh
  cargo run --release -p iaf-setup -- [--assets DIR] [--patch P] [--hebrew-iso ISO] [--imagery sentinel2,mapi2015] \
      [--guides] [--redo-all] ["/path/to/Jane's IAF.iso" [Brief.zip] [Menu.zip]]
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
| Pilot guides | no | the guides' pictures and PDFs (python3 and Firefox; the renders open game windows briefly) |

The Hebrew CD alone cannot set up the game: its `iafjets.exe` is the copy-protected build, and the English v1.1
patch does not apply to it. So the English CD is always the base; the Hebrew CD adds the translations.

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
| `arm` | menu, menu_he | the extra planes' arming art |
| `aircraft`, `objects` | missions | `assets/converted/planes`, `objects` |
| `airbases` | theatre | `assets/converted/terrain/airbases.json`, `airbases/` |
| `launcher` | icon | the desktop launcher (`tools/install-launcher.sh`) |
| `sentinel2`, `mapi2015-fetch`, `mapi2015` | airbases | `assets/converted/imagery` |
| `guides` | the conversions and imagery | the pilot guides |

"The install" is `patch` when a patch is given, else `extract`. A failed required step stops the setup; the steps
that wait for it do not run. `launcher`, the imagery and the guides are optional: their failure stops only what waits
for them.

## Running only what changed

Each step writes a stamp next to its output (`<output>.stamp`). The stamp lists:

- the converters' code (a fingerprint of the iaf-tools, iaf-formats and iaf-setup sources and `Cargo.lock`);
- every outside file the step reads (the CD image, the patch, the packs, the extra planes), with its size and CRC-32;
- the stamps of the steps it waits for.

When a step's stamp is the same as last time and its output is still there, the step is "up to date" and does not
run. A changed input therefore redoes its step and the steps after it, and nothing else. `--redo-all` runs every
step anyway.

Running setup again is how you add or redo things. The last run's inputs are kept in `assets/setup.json` (the wizard
fills its pages from them; the CLI uses them when no ISO is given, plus the options given). Add an extra, for example
`--imagery sentinel2`, and only its steps and the steps that wait for them run.

The imagery steps keep their own marks per work unit instead: a run converts only the units that are missing or
were made under older rules, and is up to date when there are none. The guides decide per picture.

## Uninstall
The CD launcher's UNINSTALL button (Extras → CD launcher, docs/front-end.md §18.1) asks first, then removes what the
setup wrote under `assets/` (`iaf_setup::OUTPUTS`): `install`, `v1.0`, `v1.1`, `patch`, `converted`, `packs`,
`packs-none`, `hebrew-cd`, `hebrew-cd-pick`, `source/imagery`, the stamps and `setup.json`. Everything else under
`assets/` stays, and so do the pilots, settings and logs in the user folder, the repo and the built extension. The
game then quits; `./setup` installs again. The launcher's INSTALL button opens the setup wizard.

## Outside programs

- GDAL (`gdal_translate`, `gdalbuildvrt`): the imagery steps. Without it they are skipped.
- `tools/imagery/fetch-mapi2015-curl.sh` (curl, python3, Firefox's data.gov.il token): the Survey sheets.
- `tools/install-launcher.sh`: the desktop launcher (its `XDG_DATA_HOME` can be set).
- The guides: the wizard renders them in-process; the CLI runs `tools/guide_shots.sh` and `tools/guide_pdf.py`.

Their output goes to the step's log.

## The wizard

`./setup` checks for Rust (cargo) and Godot 4.7 first. A missing one opens a dialog (zenity or kdialog on Linux,
osascript on macOS, else the terminal) with the install command. Then it builds the game's extension and opens the
wizard (`game/setup/wizard.tscn`). `./iafjets` starts `./setup` when there is no game data, and so does the game's
start-up when `assets/converted` is missing. The desktop launcher "Jane's IAF (reborn) — Setup" runs it too.

Pages:

The wizard uses the original menus' colours.

1. **Welcome**: the game's name, what is needed and what is optional, the next pages, where the data goes, the
   repository link, the licence and the attributions (the models and the imagery, as in the credits roll).
2. **Requirements**: a table of the parts, why each is needed, and whether it is required: the graphics driver and
   the disk space for the game (required); the disk space for imagery, GDAL, curl, python3 and Firefox (optional).
   A missing part shows its install command. "Check again", next to Next, looks once more.
3. **Your CD**: the English CD image, picked with Browse and checked at once. Given the Hebrew CD here, the wizard
   says so and keeps it for the next page. "Find in a folder…" looks in a folder and its subfolders (3 levels) for
   the CD images, the v1.1 patch and the Hebrew packs (`iaf_setup::scan`, in the background), and fills the empty
   fields.
4. **Optional**: the v1.1 patch, the Hebrew CD, or without it the Hebrew packs; each with a link to where to get it.
5. **Extras**: the Survey of Israel imagery (all of Israel or around the airbases), the Sentinel-2 imagery,
   "Bring the imagery up to date" (only with imagery on disk; it shows how many units older rules made) and the
   pilot guides. Each shows its downloads and disk use (no download times: they depend on the network), and is
   greyed with the reason when a program it needs is missing:
   - Survey of Israel, all of Israel: 79 sheets, about 17 GB of downloads (kept in `assets/source`), about 5 GB
     converted. Around the airbases: 9 sheets, about 2 GB of downloads. Sheets already downloaded are not
     downloaded again.
   - Sentinel-2: about 28 GB read over the network, about 2.5 GB on disk. Units already converted are not read
     again.
6. **Summary**: the inputs and the number of steps.
7. **Install**: one row per step. Before Install each row says whether it is "up to date" or "will run"
   (`iaf_setup::preview`, checked in the background: it reads the CD images). Then its state and progress (a long step adds the time left at its pace so
   far, once it has run 30 s), the log, Cancel, "Redo everything", and a "redo" tick
   per step: a ticked step runs again although it is up to date. The steps after it stay up to date; tick them too
   to redo them.
8. **Done**: "Start the game".

The pages start from the last run's inputs (`assets/setup.json`). The log names files relative to the assets
folder. The pilot guides render through `tools/guide_shots.sh` for now: the renders open game windows briefly.
