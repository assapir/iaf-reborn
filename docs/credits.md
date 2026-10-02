# Credits

The credits roll when you quit from the menus (QUIT → "Are you sure you want to quit the game?" → Yes), as in
the original: its `credits.trx` over the `cr0..cr8` screens with `credits.wav`. A key or a mouse button ends
it, and then the game exits. It only rolls when the game was started without arguments (`./iafjets`). How the
original's roll works: docs/front-end.md §4.1. The code is in game/menu/credits_roll.gd.

Our credits roll before the original's, in the same fonts and colour.

## Adding a credit

Our lines are in **game/menu/credits_ours.json**. Do not hard-code them in the script. Each entry is one line:

```json
{"style": "role", "text": "Created by", "he": "יוצר"},
{"style": "name", "text": "Assaf Sapir", "he": "אסף ספיר"},
```

* `text`: the English line. `he`: the Hebrew line (optional; without it the Hebrew roll shows `text`).
  Hebrew is drawn with Arial as the fallback font, because Gill Sans has no Hebrew letters.
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

The original's own pattern is: `gap`, a `role`, one or more `name`s. A long line wraps inside the original's
margins (70 px on both sides of the 640 px screen).

## Imagery credits (automatic)

The `imagery` entry expands to "Terrain Imagery" followed by the `attribution` of every converted imagery layer
(`assets/converted/imagery/<id>/manifest.json`, written by `iaf-imagery`). Identical attributions are listed
once (`game/terrain/imagery_layers.gd attributions()`). Nothing is added by hand: when a new source is
converted (for example the Survey of Israel 2015 photo, "© Survey of Israel 2015, via data.gov.il"), its
manifest's `attribution` rolls. When no layer is converted, the section is left out. This is where the CC BY
credit is given (docs/imagery.md §6).

## Testing

* `tests/godot/test_credits.gd` (run by `tools/test.sh`) checks the RTF reader, QUIT → msg 7 → Yes → the roll
  → exit, that our lines and the imagery credits follow the original's, that a key or click ends the roll, the
  music fade and the end, and the Hebrew lines. Add a check there when you add a line that must always be
  present.
* To look at it, take a real-render screenshot with our first line `CREDITS_Y` px below the top (default 40):

```sh
CREDITS_SHOT=/tmp/credits.png godot --path game -s ../tests/godot/_credits_shot.gd
CREDITS_LANG=he CREDITS_SHOT=/tmp/credits_he.png godot --path game -s ../tests/godot/_credits_shot.gd
```

* In the game: `./iafjets`, then QUIT and Yes.
