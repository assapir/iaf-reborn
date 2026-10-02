# Modern terrain imagery layers

Opt-in, original by default (docs/deviations.md §2). A modern source is converted into its own **layer**: a node
set on the game's terrain quadtree with the same keys as the converted map.ptt (`L<level>/c_<i>_<j>.jpg`), so the
runtime takes a node's colour texture from a layer instead of the original and changes nothing else (heights,
terrain types, missions, insets stay the original's). Sources, licences and why: docs/imagery-sources.md;
the warp into the game frame: docs/georef.md; user-facing summary: README "Terrain imagery data".

## 1. Sources and layers

| layer id | region | source | state |
|---|---|---|---|
| `sentinel2` | outside Israel | ESA WorldCover 2021 Sentinel-2 RGB(NIR) composite, 10 m, CC BY 4.0, colour-matched to the 1998 imagery | done |
| `sentinel2_modern` | outside Israel | the same, modern colours | done |
| `mapi2015` | Israel | Survey of Israel 2015 aerial photo, 2 m (data.gov.il) | download only (phase 2: conversion) |
| SPOT 5 | outside Israel (maybe Israel) | CNES SPOT World Heritage, 5 m | not started (free CNES account, orthorectification) |

## 2. Pipeline (`iaf-imagery`, crates/iaf-tools/src/bin/iaf-imagery.rs + src/imagery.rs)

1. **Work units**: level-5 nodes (40 km of game frame) that contain at least one pixel the layer may replace (§3).
   The tool prints the count, the download estimate (WorldCover tile bytes × overlap) and the output size first.
2. **Fetch** per unit: the lon/lat box of the unit (through the georef warp, plus a margin) is cut out of the
   WorldCover 1°×1° Cloud-Optimised GeoTIFFs on the public S3 bucket by **HTTP range reads**
   (`gdalbuildvrt` + `gdal_translate` over `/vsicurl/`) — only the needed overviews / blocks are read, nothing is
   mirrored. Tiles are listed with the S3 listing API (`curl`).
3. **Warp**: for each level-3 node (1024², 9.9 m/px) the spline `iaf_tools::georef` gives (lon, lat) every
   32 px, bilinear between; the source is sampled bilinearly.
4. **Compose** (§3): layer where allowed, original elsewhere, feathered borders.
5. **Two looks** (§4), written as JPEG (quality 88) into `assets/converted/imagery/sentinel2/` and `…_modern/`.
6. **Coarser levels 4..11**: each parent from its four children (the layer's child where written, else the
   original's rendition), so a layer node exists at every level above a written level-3 node.
7. **manifest.json** per layer: name, title, region, source, licence, attribution, levels, node list.
   Finished units are remembered in `assets/converted/imagery/.work/` — a run resumes where it stopped.

## 3. Where a layer replaces the original

- **Region**: map.ptt's largest inset record is "Israel"; an outside-Israel layer writes only outside it, an Israel
  layer only inside.
- **Water stays the original's**: open water in the source (NIR below green, NDWI > 0) and sea in terraintype.dat
  keep the 1998 sea; the coastline is the real one (feather ≈ 20 m).
- **Airbases and fine insets stay the original's**: terraintype.dat runway cells and every original inset of level
  ≤ 3 (airbases, targets). The game's airbases are not at their real positions (docs/georef.md §4), so a modern
  layer there would put the mission's base in empty desert.
- Region / airbase / inset borders are feathered over ≈ 240 m (two box passes), computed with a 64 px margin so
  neighbouring nodes match at their seams.

## 4. Looks

- **1998 colours** (`sentinel2`): the modern pixel × the per-channel ratio of the local means (≈ 500 m, land pixels
  only) of the original and the modern image, clamped to 0.33–3. Keeps the modern detail with the original's
  palette, so the layer blends into the untouched original around it.
- **Modern colours** (`sentinel2_modern`): surface reflectance to display values — linear (0.42 reflectance =
  white), display gamma, a little extra saturation.

## 5. In the game

- `game/terrain/imagery_layers.gd`: the options per region (`REGIONS`), `available(id)` (= its manifest exists;
  "original" always), `selected()` (the picked, converted layers, Israel first), `attributions()`.
- **Preferences → Extras** (ours): one row per region ("Imagery Israel", "Imagery outside Israel"; outside Israel's
  three choices in narrower columns), after the other Extras rows (the page scrolls like Physics, 8 rows shown); options whose layer is not converted are
  shown in grey and cannot be picked (user decision: greyed, not hidden). Default "Original"; Extras DEFAULT
  resets them. Hebrew labels in game/menu/strings_he.json. Settings `imagery_israel` / `imagery_outside`
  ([gameplay] section, with the other Extras). (First on the Graphics page; moved so that page stays the original.)
- `terrain.gd`: at `_ready` each picked layer's nodes are added to the colour-node set with their directory
  (`colour_dir(node)`); `_path()` reads those nodes from the layer, everything else (and every height) from the
  original. The preload's textures are not adopted when they were loaded with other layers.

## 6. Attribution and checks

- CC BY sources need a credit wherever the imagery shows: the picked layers' `attribution` is printed at the
  bottom of the flight loading screen.
- `iaf-imagery compare <theatre-dir> <layers-root> <level> <i> <j> <out.png>`: the original node, the 1998-colour and
  the modern-colour layer node side by side.
- Tests: Rust `imagery` unit tests (feather inside only, tone curve), `tests/godot/test_imagery.gd` (layer node
  replaces only its node, heights stay original, only converted layers count), `test_ui_smoke.gd` (drop-downs
  open, greyed options cannot be picked, close on a click elsewhere, EN + HE).

## 7. How to run

```sh
tools/setup.sh --imagery sentinel2          # estimate, ask, fetch + convert (needs gdal); alone = imagery steps only
tools/setup.sh --imagery mapi2015-bases     # Survey of Israel sheets around the airbases, through the browser

# by hand: a small sample (lon0,lat0,lon1,lat1), e.g. the head of the Gulf of Suez (a few 40 km units)
cargo build --release -p iaf-tools
./target/release/iaf-imagery sentinel2 assets/install assets/converted/terrain/theatre assets/converted/imagery \
    --area 32.4,29.8,32.7,30.1 [--dry-run] [--threads 4]
```

Full `sentinel2` run: 318 work units, ≈ 28 GB of range reads (an upper bound: the estimate counts all four bands
of the overlapping tiles), ≈ 6 GB written for both looks. Delete `assets/converted/imagery/<id>/` to remove a layer
(the drop-down greys it out again).

## 8. Phase 2: Survey of Israel 2015 (2 m)

The sheets (one ZIP per 1:50 000 sheet, list in tools/imagery/mapi2015_sheets.tsv) arrive in
`assets/source/imagery/mapi2015/` via `tools/imagery/fetch-mapi2015.sh`. Needed: confirm the
ZIP's raster format and grid (ITM, EPSG:2039, expected), a `mapi2015` source in `iaf-imagery` that builds a VRT of
the local sheets instead of the S3 tiles, a finer `LAYER_LEVEL` (2 m → level 1, 2.5 m/px) with the same rules
(inside Israel, keep airbases / insets ≤ level 3 — or decide with the user whether the 2 m photo should replace the
original insets too), its own colour match, credit "© Survey of Israel 2015, via data.gov.il", and the download
date recorded in the manifest (the data.gov.il licence in force at download time governs).
