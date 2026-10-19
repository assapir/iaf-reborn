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

Each third-party model carries its full credit next to it; the in-game roll (`credits_ours.json`) shows a line for
each.

| Model | Based on | Licence | Full credit |
|---|---|---|---|
| Detailed F-16D (docs/aircraft-models.md) | the FlightGear F-16, https://github.com/NikolaiVChr/f16, by Erik Hofman, Nikolai V. Chr., J Maverick 16, Pensacola and the other authors in its `authors.txt`; its centreline pylon and IAF livery come from the same project | GPL 2.0 or later | `game/extra/models/f16/SOURCES.md` (commit, authors, changes, the photo references) |
| F-35I Adir (docs/f35i.md) | "Lockheed Martin F35 Lightning II" by andertan, https://sketchfab.com/3d-models/lockheed-martin-f35-lightning-ii-db911de503c74285a8d506951df786d6 | CC BY 4.0, https://creativecommons.org/licenses/by/4.0/ | `game/extra/planes/f35i/CREDITS.md` |
| F-35I 116 Squadron badge | "IAF Squadron 116 Adir.png" by the IDF Spokesperson's Unit, https://commons.wikimedia.org/wiki/File:IAF_Squadron_116_Adir.png | CC BY-SA 3.0, https://creativecommons.org/licenses/by-sa/3.0/ | `game/extra/planes/f35i/CREDITS.md` |
| The setup wizard's icon (docs/setup.md) | "Roundel of Israel.svg" by Zscout370, https://commons.wikimedia.org/wiki/File:Roundel_of_Israel.svg, with our "REBORN" banner | CC BY-SA 4.0, https://creativecommons.org/licenses/by-sa/4.0/ | `game/setup/icon.svg` |

The F-35I's skin, roundels, numbers, cockpit panel and displays are our own, as is the F-16D's dorsal spine.

## Imagery credits (automatic)

The `imagery` entry expands to "Terrain Imagery", followed by the `attribution` of every converted imagery layer
(`assets/converted/imagery/<id>/manifest.json`, written by `iaf-imagery`).

* Identical attributions are listed once (`game/terrain/imagery_layers.gd attributions()`).
* The list builds itself. When a new source is converted, its manifest's `attribution` rolls. Example: the Survey of
  Israel 2015 photo, "© Survey of Israel 2015, via data.gov.il".
* When no layer is converted, the section is left out.

This section gives the CC BY (Creative Commons Attribution) credit (docs/imagery.md §6).

## Testing

* `tests/godot/test_credits.gd` (run by `tools/test.sh`) checks:
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
  CREDITS_SHOT=/tmp/credits.png godot --path game -s ../tests/godot/_credits_shot.gd
  CREDITS_LANG=he CREDITS_SHOT=/tmp/credits_he.png godot --path game -s ../tests/godot/_credits_shot.gd
  ```
* In the game: run `./iafjets`, then QUIT and Yes.
