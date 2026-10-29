# Credits

The credits roll when you quit from the menus, as in the original. The code is in game/menu/credits_roll.gd.

* **Trigger**: QUIT → "Are you sure you want to quit the game?" → Yes. The roll runs only when the game was started
  without arguments (`./iafjets`).
* **Content**: our credits first, in the original's fonts and colour; then the original's `credits.trx` over the
  `cr0..cr8` screens with `credits.wav`. How the original's roll works: docs/front-end.md §4.1.
* **End**: a key or a mouse button ends the roll, and then the game exits.

## Adding a credit

Our lines are in **game/menu/credits_ours.json**. Keep them out of the script. Each entry is one line:

```json
{"style": "role", "text": "Created by", "he": "יוצר"},
{"style": "name", "text": "Assaf Sapir", "he": "אסף ספיר"},
```

* `text`: the English line.
* `he`: the Hebrew line (optional; without it the Hebrew roll shows `text`). Hebrew is drawn with Arial as the
  fallback font, because Gill Sans has no Hebrew letters.
* `style`: one of the original's line styles:

| style | looks like (credits.trx) | font |
|---|---|---|
| `heading` | "PIXEL TEAM", "EA TEAM" | Gill Sans (cr4.ttf) 20 pt (`\f0\fs40`) |
| `role` | "Creative Director" | Gill Sans Condensed (cr1.ttf) 20 pt (`\f1\fs40`) |
| `name` | "Ramy Weitz" | Gill Sans 20 pt (`\f0\fs40`) |
| `small` | "ROHR PRODUCTIONS LTD. & C.N.E.S" | Gill Sans 16 pt (`\fs32`) |
| `gap` | the empty line between groups | empty 12 pt line (`\fs24\par`) |
| `blank` | an empty full-size line | empty 20 pt line (`\fs40\par`) |
| `imagery` | the terrain imagery section (below) | its `text` as a `role` line, then `small` lines |

The original's own pattern is `gap`, a `role`, then one or more `name`s. A long line wraps inside the original's
margins: 70 px on both sides of the 640 px screen.

## Model credits

Each third-party model or picture carries its full credit next to it; the roll (`credits_ours.json`) shows a line
for each.

| Model | Based on | Licence | Full credit |
|---|---|---|---|
| Detailed F-16D and F-16I Sufa (docs/aircraft-models.md, docs/f16i.md §8.1) | the FlightGear F-16, https://github.com/NikolaiVChr/f16, by Erik Hofman, Nikolai V. Chr., J Maverick 16, Pensacola and the other authors in its `authors.txt`; its centreline pylon and IAF livery, and the Sufa's conformal fuel tanks and P&W nozzle, come from the same project | GPL 2.0 or later | `game/extra/models/f16/SOURCES.md` (commit, authors, changes, the photo references) |
| Detailed stores (docs/aircraft-models.md §5) | the FlightGear F-16's weapons and external stores (`Models/Armament/`), https://github.com/NikolaiVChr/f16, 3D work by J Maverick 16, with Nikolai V. Chr., Erik Hofman and the other authors in its `authors.txt`; the tanks' paint from its IAF livery | GPL 2.0 or later | `game/extra/models/stores/SOURCES.md` (commit, authors, files, changes) |
| Detailed F-15 (docs/aircraft-models.md §6) | the FlightGear F-15C/D, https://github.com/Zaretto/fg-aircraft (`aircraft/F-15`, commit 062cb58), 3D model by Enrique Laso, rig and systems by Richard Harrison (Zaretto), cockpit textures by GeneB; its grey livery and IAF pilot patch | GPL 2.0 only (the author, fg-aircraft issue #211); setup downloads and converts it on the player's machine, so the repo and the game's distribution hold none of it | `crates/iaf-tools/src/f15.rs` (files, checksums, changes) |
| F-35I Adir (docs/f35i.md) | "Lockheed Martin F35 Lightning II" by andertan, https://sketchfab.com/3d-models/lockheed-martin-f35-lightning-ii-db911de503c74285a8d506951df786d6 | CC BY 4.0, https://creativecommons.org/licenses/by/4.0/ | `game/extra/planes/f35i/CREDITS.md` |
| F-35I 116 Squadron badge | "IAF Squadron 116 Adir.png" by the IDF Spokesperson's Unit, https://commons.wikimedia.org/wiki/File:IAF_Squadron_116_Adir.png | CC BY-SA 3.0, https://creativecommons.org/licenses/by-sa/3.0/ | `game/extra/planes/f35i/CREDITS.md` |
| The setup wizard's icon (docs/setup.md) | "Roundel of Israel.svg" by Zscout370, https://commons.wikimedia.org/wiki/File:Roundel_of_Israel.svg, with our "REBORN" banner | CC BY-SA 4.0, https://creativecommons.org/licenses/by-sa/4.0/ | `game/setup/icon.svg` |

## Texture credits

Setup downloads these materials from ambientCG into `assets/thirdparty/ambientcg/<id>/` (the repo holds none). They
are CC0 1.0 (public domain): "All ambientCG assets are provided under the Creative Commons CC0 1.0 Universal
License"[^acg-licence]. CC0 asks for no credit; we give it anyway. One line names ambientCG in the setup wizard's Attributions and in the
roll (`credits_ours.json`, "Ground Textures and Model Detail"). The list lives in one place:
`crates/iaf-tools/src/thirdparty.rs` (`GROUND_TEXTURES`, `MODEL_DETAIL`, `SCENERY_WALLS` and `TREE_TEXTURES`, with each
zip's pinned SHA-256). Setup composes the scenery trees' foliage from the leaf sets' colour and opacity maps
(`crates/iaf-tools/src/foliage.rs`).

| Material | Used for (docs/rendering.md) | Source |
|---|---|---|
| Asphalt027C | Ground textures (§1.4): runways and taxiways | https://ambientcg.com/a/Asphalt027C |
| Concrete040 | Ground textures: aprons | https://ambientcg.com/a/Concrete040 |
| Ground054 | Ground textures: sand | https://ambientcg.com/a/Ground054 |
| Ground062L | Ground textures: gravel desert | https://ambientcg.com/a/Ground062L |
| Ground037 | Ground textures: grass and fields | https://ambientcg.com/a/Ground037 |
| Ground109 | Ground textures: dry soil and scrub | https://ambientcg.com/a/Ground109 |
| Rock045 | Ground textures: steep slopes | https://ambientcg.com/a/Rock045 |
| PaintedMetal002 | Model detail (§9): stores and jets | https://ambientcg.com/a/PaintedMetal002 |
| Metal016 | Model detail: vehicles, ships, hangar shells, metal structures | https://ambientcg.com/a/Metal016 |
| Concrete029 | Model detail: shelters and buildings | https://ambientcg.com/a/Concrete029 |
| Rubber004 | Model detail: tyres | https://ambientcg.com/a/Rubber004 |
| Plaster003 | Scenery (docs/scenery.md §3): plaster walls | https://ambientcg.com/a/Plaster003 |
| Bricks084 | Scenery: stone-clad walls | https://ambientcg.com/a/Bricks084 |
| Concrete034 | Scenery: concrete walls | https://ambientcg.com/a/Concrete034 |
| CorrugatedSteel005 | Scenery: sheds | https://ambientcg.com/a/CorrugatedSteel005 |
| LeafSet001 | Scenery trees (docs/scenery.md §3.2): broadleaf crowns | https://ambientcg.com/a/LeafSet001 |
| LeafSet019 | Scenery trees: pine and cypress crowns | https://ambientcg.com/a/LeafSet019 |
| Foliage001 | Scenery trees: palm fronds' leaflets | https://ambientcg.com/a/Foliage001 |
| Bark012 | Scenery trees: trunks | https://ambientcg.com/a/Bark012 |

The F-35I's skin, roundels, numbers, cockpit panel and displays are our own, as is the F-16D's dorsal spine, and the
detailed F-15's markings (F-15C 802: roundels, name, kill marks, numbers, the Baz bird, 133 Squadron's band; drawn
from photos, `crates/iaf-tools/data/f15-livery/`).

## Imagery credits (automatic)

The `imagery` entry expands to "Terrain Imagery", followed by the `attribution` of every converted imagery layer
(`assets/converted/imagery/<id>/manifest.json`, written by `iaf-imagery`).

* Identical attributions are listed once (`game/terrain/imagery_layers.gd attributions()`).
* The list builds itself. When a new source is converted, its manifest's `attribution` rolls. Example: the Survey of
  Israel 2015 photo, "© Survey of Israel 2015, via data.gov.il".
* When no layer is converted, the section is left out.

This section gives the CC BY (Creative Commons Attribution) credit (docs/imagery.md §6).

## Scenery credits

Setup makes the scenery (docs/scenery.md) from open data it downloads into `assets/source/scenery/` (the repo holds
none). The scenery manifest (`assets/converted/scenery/manifest.json`, written by `iaf-scenery build`) holds the
lines to roll in its `attribution`, and the licences in `licence`:

| Source | Credit line | Licence |
|---|---|---|
| OpenStreetMap (Geofabrik extracts: Israel and Palestine; for the roads also Lebanon, Syria, Jordan, Egypt, Cyprus) | © OpenStreetMap contributors | ODbL 1.0[^osm] |
| Microsoft Global ML Building Footprints | Microsoft Global ML Building Footprints | CDLA Permissive 2.0[^ms] |
| GHS-BUILT-H R2023A | European Commission, Joint Research Centre (JRC) | free re-use with the source acknowledged[^ghsl] |
| Global Canopy Height 2020 (10 m) | Lang, Jetz, Schindler, Wegner; ETH Zürich EcoVision Lab | CC BY 4.0[^chm] |

The road layer (docs/scenery.md §6) has its own manifest (`assets/converted/roads/manifest.json`); the credits roll
shows its `attribution` too: OpenStreetMap with the extracts used. ODbL and CC BY ask for the credit. The files and
their checksums are `SCENERY` and `ROADS` in `crates/iaf-tools/src/thirdparty.rs`.

## Testing

* `tests/godot/test_credits.gd` checks:
  - the RTF (Rich Text Format) reader;
  - QUIT → msg 7 → Yes → the roll → exit;
  - that our lines and the imagery credits come before the original's;
  - that a key or click ends the roll;
  - the music fade and the end;
  - the Hebrew lines.

  Add a check there when you add a line that must always be present.
* To look at the roll, take a real-render screenshot. `CREDITS_Y` sets our first line's distance from the top in px
  (default 40):
  ```sh
  tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 CREDITS_SHOT=/tmp/credits.png -- \
      --log-file /tmp/credits.log --path game -s ../tests/godot/_credits_shot.gd
  ```
  `CREDITS_LANG=he` takes the Hebrew roll.
* In the game: run `./iafjets`, then QUIT and Yes.

[^acg-licence]: ambientCG licence, https://docs.ambientcg.com/license/ (read 2026-10-22).
[^osm]: OpenStreetMap, "Copyright and License": https://www.openstreetmap.org/copyright
[^ms]: Microsoft, Global ML Building Footprints, "License": https://github.com/microsoft/GlobalMLBuildingFootprints
[^ghsl]: European Commission, GHSL Data Package 2023, "Terms of Use" (in each GHS-BUILT-H tile's zip).
[^chm]: Lang et al. (2023), "A high-resolution canopy height model of the Earth", Nature Ecology & Evolution; data
    and licence: https://langnico.github.io/globalcanopyheight/
