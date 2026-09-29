# Content packs

A pack is a folder that mirrors the base install layout (lower-cased paths) and overrides or adds files.
The engine resolves every data file through the active packs first, then the base install.

```
assets/install/            base game (iaf-extract)
assets/packs/<name>/...    overlay, same layout as assets/install
```

Import a community mod with:
```sh
cargo run --release -p iaf-tools --bin iaf-import-pack -- <mod.zip|dir> <name> assets/install assets/packs [--into resource]
```
`--into` is the folder the mod's readme says to extract into (relative to the install root). Only files that differ
from the base install, or new files with an extension already used in that folder, are copied.

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
