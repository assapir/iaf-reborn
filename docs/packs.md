# Content packs

A pack is a folder that overrides or adds files of the base install. It mirrors the base install layout, with
lower-cased paths:

```
assets/install/            base game (iaf-extract)
assets/packs/<name>/...    overlay, same layout as assets/install
```

Packs apply **at convert time**. Three converter commands read `assets/packs` and let a pack's files win:
`iaf-convert menu --pack`, `briefings` and `keys`. Everything else reads only `assets/install` /
`assets/converted`: the cockpits, aircraft, objects, missions, the flight model (`resource/md`) and the game itself.
New planes follow docs/adding-a-plane.md.

## Importing a mod

1. Run the importer:
   ```sh
   cargo run --release -p iaf-tools --bin iaf-import-pack -- <mod.zip|dir> <name> assets/install assets/packs [--into resource]
   ```
   `--into` is the folder the mod's readme says to extract into, relative to the install root.
2. The importer copies only the files that differ from the base install, and new files whose extension is already
   used in that folder.

`tools/setup.sh` imports the packs after the v1.1 patch, so a pack overlays the patched English files. Both Hebrew
packs replace two v1.1-patched files: `brief/txt/112.rtf` and `menu/txt/msgs.trx`. The pack's `msgs.trx` already
has the v1.1 line 56. A shorter `msgs.trx` would get the install's missing lines (docs/front-end.md §3.3).

## Known packs

All three known packs are named `he` (Hebrew). preflight.us is an Israeli flight-sim community site.

### `he` — Hebrew briefings (preflight.us, "הפיכת התדריכים לעברית", v1.0, 2005)

* Download: https://www.preflight.us/HE/downloadview-details-104.html (site login required) → `Brief.zip`.
* Extract target per its readme: `\I.A.F\Resource` → `--into resource` (the default).

It overrides 193 files in `resource/brief`:
- `txt/*.rtf`, `text/*.rtf`: briefings and lesson text in Hebrew RTF (Rich Text Format), Windows-1255
  (`\ansicpg1255`, `\'xx` escapes, `\rtlch` runs).
- `txt/*.brl`, `text/*.brl`: binary briefing records with fixed-width display names (Windows-1255) and model paths.
- `bmp/*.bmp`: 32 briefing diagrams relabelled in Hebrew.

The menus, HUD, radio messages and speech stay English.

### `he` — Hebrew menus (preflight.us, `Menu.zip`, 2005, by רועי "106thE~LOL")

* Extract target per its readme: `I.A.F\Resource` → `--into resource` (the default). The zip's `Menu/` folder
  overlays `resource/menu`.
* It overrides 400 files: button strips (`bmp/palettes`), title tabs, bottom-bar buttons, debrief / log / prefs / arm
  art, and all mission and course strings (`txt/mis/*.trx`, Windows-1255).
* It keeps the screen layouts (`dat/`) and fonts. Hebrew glyphs come from the system font; the original game relied
  on Windows' font fallback.
* Convert it with `iaf-convert menu … assets/converted/menu_he --pack assets/packs/he`. The front end uses it when the
  language is Hebrew.
* Its `txt/msgs.trx` is still all English (message boxes, the On-The-Fly menu items). Ours: in Hebrew, every msgs
  line the pack leaves in English takes our Hebrew from `game/menu/strings_he.json` "msgs" (`Settings.msgs()`, used
  by the message boxes and the On-The-Fly menu). A pack line in Hebrew wins.

### `he` — Hebrew retail CD (Hed Arzi, v1.0, copy-protected)

* Setup: `tools/setup.sh --hebrew-iso IAF.Iso` (archive.org item `iaf_20230527`, `IAF.Iso`).
* The CD's 591 translated files are byte-identical to `Brief.zip` + `Menu.zip`. Only the CD has
  `menu/bmp/back0.bmp` (the startup splash, "איתחול...") and the Graphics page `menu/bmp/pref/graph_0/1.bmp`.
* The official Hebrew v1.1 patch (`IAFheb1_1.EXE`) replaces those three files with the English v1.1 ones, so setup
  takes them from the CD into the `he` pack.
* The Graphics page is v1.0 art: it lacks v1.1's 32MB / 48MB labels under the terrain slider.
* In Hebrew the boot splash is the Hebrew one (`game/override.cfg`, written by `settings.gd`).
* The CD's `iafjets.exe` is the protected build. Setup takes nothing from it. `IAFheb1_1.EXE` does not apply to it:
  the patch wants the 2,623,488-byte exe of preflight.us's `IAF_Hebrew_Fix.zip`, now offline.

## In-flight subtitles

The instructor and radio subtitles come from the object database (`default6_1.bdb` Audio records). They exist only
in English; the Hebrew packs translate menus and briefings only. Decided (user): keep the original English subtitles
in Hebrew mode.

## Debrief texts

The debrief headline and notes come from each mission file (`resource/missions/*.mis`: misc `0x47e` passed /
`0x492` failed, and the debrief records). The Hebrew packs cover `resource/menu` and `resource/brief`, so the
debrief text is English in both languages. In Hebrew mode the debrief screen right-aligns that English text.
