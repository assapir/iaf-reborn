# Credits

The credits roll when you quit from the menus, as in the original. The code is in iaf-reborn/menu/credits_roll.gd.

* **Trigger**: QUIT → "Are you sure you want to quit the game?" → Yes. The roll runs only when the game was started
  without arguments (`./iafjets`).
* **Content**: our credits first, in the original's fonts and colour; then the original's `credits.trx` over the
  `cr0..cr8` screens with `credits.wav`. How the original's roll works: docs/front-end.md §4.1.
* **End**: a key or a mouse button ends the roll, and then the game exits.

## Adding a credit

Our lines are in **iaf-reborn/menu/credits_ours.json**. Keep them out of the script. Each entry is one line:

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
| Detailed F-16D and F-16I Sufa (docs/aircraft-models.md, docs/f16i.md §8.1) | the FlightGear F-16, https://github.com/NikolaiVChr/f16, by Erik Hofman, Nikolai V. Chr., J Maverick 16, Pensacola and the other authors in its `authors.txt`; its centreline pylon and IAF livery, and the Sufa's conformal fuel tanks and P&W nozzle, come from the same project | GPL 2.0 or later | `shared/extra/models/f16/SOURCES.md` (commit, authors, changes, the photo references) |
| 3D F-16 cockpit (docs/cockpit.md "3D cockpit") | the FlightGear F-16's cockpit (`Models/Cockpit/`), https://github.com/NikolaiVChr/f16, 3D work by J Maverick 16, textures and layout by Martin "Pegasus" Schmitt and Prohm "Rama" Snitwong, MFD / HUD / cockpit changes by Nikolai V. Chr., with Jonathan Redpath, Erik Hofman and the other authors in its `authors.txt` | GPL 2.0 or later | `shared/extra/models/cockpit3d/SOURCES.md` (commit, authors, files, changes) |
| Detailed stores (docs/aircraft-models.md §5) | the FlightGear F-16's weapons and external stores (`Models/Armament/`), https://github.com/NikolaiVChr/f16, 3D work by J Maverick 16, with Nikolai V. Chr., Erik Hofman and the other authors in its `authors.txt`; the tanks' paint from its IAF livery | GPL 2.0 or later | `shared/extra/models/stores/SOURCES.md` (commit, authors, files, changes) |
| Detailed Soviet stores (docs/aircraft-models.md §5) | the FlightGear MiG-21bis's R-3S (AA-2), https://github.com/l0k1/MiG-21bis, by the OPRF MiG-21bis team (Petar Jedvaj, JMav-16, NikolaiVChr, pinto and the other authors in its `MiG-21bis-set.xml`); the FlightGear MiG-29 9-12's R-60M (AA-8), R-27R (AA-10), R-73 (AA-11) and PTB-1500 tank, https://github.com/Mercenary-Mercury/MiG-29_9-12, by Sergey "Mercenary_Mercury" Salov | GPL 3.0 | `shared/extra/models/stores/SOURCES.md` |
| Detailed MiG-29 (docs/aircraft-models.md §7) | the FlightGear MiG-29 9-12, https://github.com/Mercenary-Mercury/MiG-29_9-12 (commit d4a299b), external model by Enrique Laso Leon, FDM, cockpit and submodels by Sergey "Mercenary_Mercury" Salov; its pilot, K-36DM seat and default livery | GPL 3.0 | `shared/extra/models/mig29/SOURCES.md` |
| Detailed F-15 (docs/aircraft-models.md §6) | the FlightGear F-15C/D, https://github.com/Zaretto/fg-aircraft (`aircraft/F-15`, commit 062cb58), 3D model by Enrique Laso, rig and systems by Richard Harrison (Zaretto), cockpit textures by GeneB; its grey livery, its IAF F-15I livery (69 Squadron, tail 269; the F-15I Ra'am, §6.7), its rear cockpit and IAF pilot patch | GPL 2.0 only (the author, fg-aircraft issue #211); setup downloads and converts it on the player's machine, so the repo and the game's distribution hold none of it | `crates/iaf-tools/src/f15.rs` (files, checksums, changes) |
| F-35I Adir (docs/f35i.md) | "Lockheed Martin F35 Lightning II" by andertan, https://sketchfab.com/3d-models/lockheed-martin-f35-lightning-ii-db911de503c74285a8d506951df786d6 | CC BY 4.0, https://creativecommons.org/licenses/by/4.0/ | `shared/extra/planes/f35i/CREDITS.md` |
| F-35I 116 Squadron badge | "IAF Squadron 116 Adir.png" by the IDF Spokesperson's Unit, https://commons.wikimedia.org/wiki/File:IAF_Squadron_116_Adir.png | CC BY-SA 3.0, https://creativecommons.org/licenses/by-sa/3.0/ | `shared/extra/planes/f35i/CREDITS.md` |
| The setup wizard's icon (docs/setup.md) | "Roundel of Israel.svg" by Zscout370, https://commons.wikimedia.org/wiki/File:Roundel_of_Israel.svg, with our "REBORN" banner | CC BY-SA 4.0, https://creativecommons.org/licenses/by-sa/4.0/ | `iaf-reborn/setup/icon.svg` |

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

The F-35I's skin, roundels, numbers, cockpit panel, 3D cockpit and displays are our own, as is the F-16D's dorsal spine, and the
detailed F-15's markings (F-15C 802: roundels, name, kill marks, numbers, the Baz bird, 133 Squadron's band; drawn
from photos, `crates/iaf-tools/data/f15-livery/`).

## Imagery credits (automatic)

The `imagery` entry expands to "Terrain Imagery", followed by the `attribution` of every converted imagery layer
(`assets/converted/imagery/<id>/manifest.json`, written by `iaf-imagery`).

* Identical attributions are listed once (`shared/terrain/imagery_layers.gd attributions()`).
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
| OpenStreetMap (Geofabrik extracts: Israel and Palestine, Lebanon, Syria, Jordan, Egypt, Cyprus) | © OpenStreetMap contributors | ODbL 1.0[^osm] |
| Microsoft Global ML Building Footprints (Israel, the West Bank, Gaza, Lebanon, Syria, Jordan, Egypt, Cyprus) | Microsoft Global ML Building Footprints | CDLA Permissive 2.0[^ms] |
| GHS-BUILT-H R2023A | European Commission, Joint Research Centre (JRC) | free re-use with the source acknowledged[^ghsl] |
| Global Canopy Height 2020 (10 m) | Lang, Jetz, Schindler, Wegner; ETH Zürich EcoVision Lab | CC BY 4.0[^chm] |

The road layer (docs/scenery.md §6) and the rest of the theatre's scenery (§1.7) have their own manifests
(`assets/converted/roads/manifest.json`, `assets/converted/scenery/theatre.json`); the credits roll shows their
`attribution` too: OpenStreetMap with the extracts used. ODbL and CC BY ask for the credit. The files and their
checksums are `SCENERY`, `SCENERY_THEATRE` and `ROADS` in `crates/iaf-tools/src/thirdparty.rs`.

## Modern IAF data

The sim's data compiler (`iaf-sim`, iaf-2026/docs/data-formats.md) uses open data kept in the repo: OpenStreetMap
runway and apron ways (© OpenStreetMap contributors, ODbL 1.0[^osm]) in `crates/iaf-flight/data/real_runways.csv` and
the mission files, the four airbases' layouts in `iaf-2026/data/airbases/` (runways, taxiways, aprons, hangars and
shelters; iaf-2026/docs/airbases.md), and OurAirports' runway widths, lengths and field elevations (public domain).
The attribution the sim shows for them: "Airbase and runway data © OpenStreetMap contributors, available under the
Open Database Licence (ODbL) 1.0: openstreetmap.org/copyright". The sim's own setup wizard
(item A3) lists them on its Attributions page. Every other figure of the data files is a cited fact with its source in
the file.

The sim's cockpit display data (`iaf-2026/data/planes/_shared/cockpit/`, iaf-2026/docs/cockpit.md "Display data"):
the TSD map and the radar's ground-map picture are made from OpenStreetMap (© OpenStreetMap contributors, ODbL
1.0[^osm]): OSM's simplified land polygons from osmdata.openstreetmap.de, the boundary relations of Israel, the West
Bank's Areas A, B and C and Hebron's H1 (the areas mapped in OSM from geomolg.ps) and the Gaza Strip, and the large
lakes, via `tools/iaf-2026/cockpit_displays.py`. The RWR glyph sheet and the ADI ball are our own drawing (their SVG
sources in `tools/iaf-2026/cockpit/`). The line the sim's wizard and credits roll need: "TSD map © OpenStreetMap
contributors, available under the Open Database Licence (ODbL) 1.0: openstreetmap.org/copyright". The original game
takes the same map with Briefing map on Modern (setup's `extras` step, docs/front-end.md §8 "Modern map"): its setup
wizard's Attributions list "Modern TSD map (Extras: Briefing map Modern): © OpenStreetMap contributors (ODbL 1.0)",
and its credits roll (`iaf-reborn/menu/credits_ours.json`) "Modern TSD Map: Map data © OpenStreetMap contributors
(openstreetmap.org/copyright), ODbL 1.0".

The sim's sound clips (`iaf-2026/data/sounds/`, made by `tools/iaf-2026/sounds.py`) are CC0 recordings from
freesound.org[^freesound] and tones we computed. CC0 asks for no credit; we name every author anyway: ikbenraar,
TiesWijnen, pillwave, 77Pacer, nuckan, qubodup, Seidhepriest, Jetrod, craigsmith (the USC Gold / Red / Sunset
Editorial libraries), LilMati, Rudmer_Rotteveel, pushkin, xkeril, elliott.klein, DeqstersLab, RutgerMuller,
SoundDesignForYou and tranzfusion. Each clip's source page, licence and processing: `iaf-2026/data/sounds/SOURCES.md`.
The sim's voices are Piper text to speech[^piper] (MIT) in the voices kristin, john and norman, trained on LibriVox
recordings (public domain); their texts and voices: `iaf-2026/data/sounds/voices.json`. The Hebrew voice waits for a
licence decision (iaf-2026/docs/sound.md §5). The lines the sim's setup wizard (item A3) and its credits roll need:
iaf-2026/docs/sound.md §6.
The sim's terrain (`iaf-sim terrain`, iaf-2026/docs/terrain.md) is converted from the Copernicus DEM GLO-30
(Copernicus WorldDEM-30 licence[^cop-dem]), the ESA WorldCover 2021 Sentinel-2 composite (CC BY 4.0) and the Survey of
Israel 2015 photo (data.gov.il). The DEM's licence asks for two lines verbatim, which the sim's setup wizard (item A3)
and credits roll show with the imagery's: "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus
Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved" and "The
organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of
the Copernicus WorldDEM-30". They are also in the theatre's `meta.json` (`attribution`, `notice`) and iaf-2026/docs/terrain.md §5.
The sim's scenery, roads and inland water (`iaf-sim scenery`, `iaf-sim airbases`; iaf-2026/docs/scenery.md) come from
the same downloads as the original game's scenery above (OpenStreetMap, Microsoft's footprints, GHS-BUILT-H, ETH's
canopy), with the same credit lines in their manifests' `attribution`.

The sim's flight data (`tools/iaf-2026/fm0.py`, iaf-2026/docs/flight-model.md) comes from NASA TP-1538[^tp1538], a
work of the U.S. Government (public domain; no credit required, named anyway), and from the public figures with their
sources in docs/real-aircraft.md, docs/f16i.md, docs/f15i.md and docs/f35i.md. The sim's 6-DoF (`crates/iaf-flight/src/sixdof/`) holds TP-1538's
aerodynamic tables, transcribed from the report's scan; the University of Minnesota's typed copy of them (its F-16
simulation package) served as the candidate checked against the scan (iaf-2026/docs/flight-model.md §9.1). The
6-DoF's F-35I gear geometry is from W. H. Mason's F-35A data (Virginia Tech), iaf-2026/docs/flight-model.md §9.9.

## Modern IAF's font

The sim's screens (its setup wizard first) use Heebo, `iaf-2026/data/fonts/Heebo-VariableFont_wght.ttf`, "Copyright
2014 The Heebo Project Authors (https://github.com/OdedEzer/heebo)", under the SIL Open Font License 1.1
(`iaf-2026/data/fonts/OFL.txt`), from Google Fonts[^heebo]. The wizard's Attributions page names it.

The sim's HUD, MFDs and panoramic display use Hershey's Roman Simplex stroke font (the user's choice, Approvals A9),
`iaf-2026/data/fonts/HersheySimplex.ttf`, which `tools/iaf-2026/hershey_font.py` strokes into outlines from Kamal
Mostafa's `futural.jhf`[^hershey] (`tools/iaf-2026/fonts/`). Its terms ask for two acknowledgements, kept with the data
(`iaf-2026/data/fonts/HERSHEY.txt`) and on the wizard's Attributions page and the credits: "The Hershey Fonts were
originally created by Dr. A. V. Hershey while working at the U. S. National Bureau of Standards" and "The format of
the Font data in this distribution was originally created by James Hurt, Cognition, Inc."

## Modern IAF's photos

The sim's front end (iaf-2026/docs/front-end.md) shows four Wikimedia Commons photos of the jets, downscaled, in
`iaf-2026/data/photos/` (`SOURCES.md` there lists each page): F-16I Sufa 407 and F-35I Adir in flight by Major Ofer,
Israeli Air Force (CC BY 4.0)[^c-sufa][^c-adir]; F-16I Sufa 851 at Tel Nof by MathKnight and Zachi Evenor (CC BY
4.0)[^c-sufa2]; F-16D Barak 034 by Zachi Evenor and MathKnight (CC BY 2.0)[^c-barak]. Each screen that shows one
credits it in its footer; the front end's Attributions screen and the setup wizard's list name all four.

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
      --log-file /tmp/credits.log --path iaf-reborn -s ../tests/godot/_credits_shot.gd
  ```
  `CREDITS_LANG=he` takes the Hebrew roll.
* In the game: run `./iafjets`, then QUIT and Yes.

[^acg-licence]: ambientCG licence, https://docs.ambientcg.com/license/ (read 2026-10-22).
[^osm]: OpenStreetMap, "Copyright and License": https://www.openstreetmap.org/copyright
[^piper]: Piper voices (rhasspy/piper-voices), each voice's MODEL_CARD names its dataset: https://huggingface.co/rhasspy/piper-voices
[^freesound]: Freesound, the sounds' pages (CC0 1.0, https://creativecommons.org/publicdomain/zero/1.0/): https://freesound.org
[^ms]: Microsoft, Global ML Building Footprints, "License": https://github.com/microsoft/GlobalMLBuildingFootprints
[^ghsl]: European Commission, GHSL Data Package 2023, "Terms of Use" (in each GHS-BUILT-H tile's zip).
[^chm]: Lang et al. (2023), "A high-resolution canopy height model of the Earth", Nature Ecology & Evolution; data
    and licence: https://langnico.github.io/globalcanopyheight/
[^tp1538]: L. T. Nguyen et al., NASA TP-1538 (1979), "Simulator Study of Stall/Post-Stall Characteristics of a Fighter
    Airplane With Relaxed Longitudinal Static Stability": https://ntrs.nasa.gov/citations/19800005879
[^c-sufa]: Wikimedia Commons, "IAF-F-16I-2016-12-13.jpg": https://commons.wikimedia.org/wiki/File:IAF-F-16I-2016-12-13.jpg
[^c-adir]: Wikimedia Commons, "IAF-F-35I-2016-12-13.jpg": https://commons.wikimedia.org/wiki/File:IAF-F-35I-2016-12-13.jpg
[^c-sufa2]: Wikimedia Commons, "IAF-F-16I-Sufa--Independence-Day-2017-Tel-Nof-IZE-182.jpg": https://commons.wikimedia.org/wiki/File:IAF-F-16I-Sufa--Independence-Day-2017-Tel-Nof-IZE-182.jpg
[^c-barak]: Wikimedia Commons, "F-16D--Our-IDF-2018-IZE-239.jpg": https://commons.wikimedia.org/wiki/File:F-16D--Our-IDF-2018-IZE-239.jpg
[^hershey]: hershey-fonts, Kamal Mostafa (`hershey-fonts/futural.jhf` and the Hershey Fonts licence in `COPYING`): https://github.com/kamalmostafa/hershey-fonts
[^heebo]: Google Fonts, Heebo (`ofl/heebo/Heebo[wght].ttf` and `OFL.txt`): https://github.com/google/fonts/tree/main/ofl/heebo
[^cop-dem]: "Licence for the use of the Copernicus WorldDEM-30", Article 6: https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf
