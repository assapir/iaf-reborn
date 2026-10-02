# Content packs

A pack is a folder that mirrors the base install layout (lower-cased paths) and overrides or adds files.
Packs are applied **at convert time**, not at run time: `iaf-convert menu --pack`, `briefings` and `keys` read
`assets/packs` and let a pack's files win. Nothing else reads packs: the cockpits, aircraft, objects, missions, the
flight model (`resource/md`) and the game itself read `assets/install` / `assets/converted` only (new planes:
docs/adding-a-plane.md).

```
assets/install/            base game (iaf-extract)
assets/packs/<name>/...    overlay, same layout as assets/install
```

Import a community mod with:
```sh
cargo run --release -p iaf-tools --bin iaf-import-pack -- <mod.zip|dir> <name> assets/install assets/packs [--into resource]
```
`--into` is the folder the mod's readme says to extract into (relative to the install root). Only files that differ
from the base install, or new files with an extension already used in that folder, are copied. `tools/setup.sh` imports
the packs after the v1.1 patch, so a pack overlays the patched English files (both Hebrew packs replace v1.1-patched
files: `brief/txt/112.rtf` and `menu/txt/msgs.trx`). The pack's `msgs.trx` already has the v1.1 line 56; a shorter
one would get the install's missing lines (docs/front-end.md §3.3).

## Known packs

### `he` — Hebrew briefings (preflight.us, "הפיכת התדריכים לעברית", v1.0, 2005)
Download: https://www.preflight.us/HE/downloadview-details-104.html (site login required) → `Brief.zip`.
Extract target per its readme: `\I.A.F\Resource` → `--into resource` (the default).

Overrides 193 files in `resource/brief`:
- `txt/*.rtf`, `text/*.rtf` — briefings / lesson text in Hebrew RTF, Windows-1255 (`\ansicpg1255`, `\'xx` escapes,
  `\rtlch` runs).
- `txt/*.brl`, `text/*.brl` — binary briefing records with fixed-width display names (Windows-1255) and model paths.
- `bmp/*.bmp` — 32 briefing diagrams relabelled in Hebrew.

Menus, HUD, radio messages and speech remain English.

### `he` — Hebrew menus (preflight.us, `Menu.zip`, 2005, by רועי "106thE~LOL")
Extract target per its readme: `I.A.F\Resource` → `--into resource` (the default); the zip's `Menu/` folder
overlays `resource/menu`. Overrides 400 files: button strips (`bmp/palettes`), title tabs, bottom-bar buttons,
debrief/log/prefs/arm art, and all mission/course strings (`txt/mis/*.trx`, Windows-1255). Screen layouts (`dat/`)
and fonts are unchanged; Hebrew glyphs come from the system font (the original game relied on Windows' font fallback).
Converted with `iaf-convert menu … assets/converted/menu_he --pack assets/packs/he`; the front end uses it when the
language is Hebrew.

## In-flight subtitles
The instructor / radio subtitles come from the object database (`default6_1.bdb` Audio records) and exist only in English; the Hebrew packs translate menus and briefings only. Decided (user): keep the original English subtitles in Hebrew mode.

### `he` — Hebrew retail CD (Hed Arzi, v1.0, copy-protected)
`tools/setup.sh --hebrew-iso IAF.Iso` (archive.org item `iaf_20230527`, `IAF.Iso`). The CD's 591 translated files are
byte-identical to `Brief.zip` + `Menu.zip`; what only the CD has is `menu/bmp/back0.bmp` (the startup splash,
"איתחול...") and the Graphics page `menu/bmp/pref/graph_0/1.bmp`. The official Hebrew v1.1 patch (`IAFheb1_1.EXE`)
replaces those three with the English v1.1 ones, so setup takes them from the CD into the `he` pack. The Graphics
page is v1.0 art: it lacks v1.1's 32MB / 48MB labels under the terrain slider. In Hebrew the boot splash is the
Hebrew one (`game/override.cfg`, written by `settings.gd`). The CD's `iafjets.exe` is the protected build; nothing
is taken from it, and `IAFheb1_1.EXE` does not apply to it (it wants the 2,623,488-byte exe of preflight.us's
`IAF_Hebrew_Fix.zip`, now offline).
