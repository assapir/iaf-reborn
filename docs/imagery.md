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
| `mapi2015` | Israel | Survey of Israel 2015 aerial photo, 2 m (data.gov.il), written at level 1 (2.5 m/px), colour-matched to the 1998 imagery | done (§8) |
| `mapi2015_modern` | Israel | the same, the photo's own colours (haze removed) | done (§8) |
| SPOT 5 | outside Israel (maybe Israel) | CNES SPOT World Heritage, 5 m | not started (free CNES account, orthorectification) |

## 2. Pipeline (`iaf-imagery`, crates/iaf-tools/src/bin/iaf-imagery.rs + src/imagery.rs)

1. **Work units**: level-5 nodes (40 km of game frame; `mapi2015`: level-4 nodes, 20 km, see §8) that contain at
   least one pixel the layer may replace (§3). The tool prints the count, the download estimate (WorldCover tile
   bytes × overlap) and the output size first.
2. **Fetch** per unit: the lon/lat box of the unit (through the georef warp, plus a margin) is cut out of the
   WorldCover 1°×1° Cloud-Optimised GeoTIFFs on the public S3 bucket by **HTTP range reads**
   (`gdalbuildvrt` + `gdal_translate` over `/vsicurl/`) — only the needed overviews / blocks are read, nothing is
   mirrored. Tiles are listed with the S3 listing API (`curl`).
3. **Warp**: for each layer node (level 3: 1024², 9.9 m/px; `mapi2015`: level 1, 2.5 m/px) the spline
   `iaf_tools::georef` gives (lon, lat) every 32 px, then the source's pixel position (lon/lat directly, or the
   Israeli TM Grid for the Survey of Israel, `iaf_tools::itm`), bilinear between; the source is sampled bilinearly.
4. **Compose** (§3): layer where allowed, original elsewhere, feathered borders. The original's own nodes finer
   than the layer level (the site insets' level 0–2 nodes) in a unit are composed too: near the jet the runtime
   draws them instead of the layer's coarser node, so without a layer version of them the layer would stop at their
   node-grid edge with a hard straight line. Those wholly inside a kept inset compose to nothing and stay the
   original's.
5. **Two looks** (§4), written as JPEG (quality 88) into `assets/converted/imagery/sentinel2/` and `…_modern/`.
6. **Coarser levels up to 11**: each parent from its four children (the layer's child where written, else the
   original's rendition), so a layer node exists at every level above a written node. They are all rebuilt on
   every run (minutes), so they take in units converted later.
7. **manifest.json** per layer: name, title, region, source, licence, attribution, levels, node list.
   Finished units are remembered in `assets/converted/imagery/.work/` (`.work/mapi2015/` for the sheets, with the
   sheets each unit used) — a run resumes where it stopped.

## 3. Where a layer replaces the original

- **Region**: map.ptt's largest inset record is "Israel"; an outside-Israel layer writes only outside it, an Israel
  layer only inside.
- **Water stays the original's**: open water in the source (Sentinel-2: NIR below green, NDWI > 0; the photo:
  blue-green clearly above red and not bright) and sea in terraintype.dat keep the 1998 sea; the coastline is the
  real one (feather ≈ 20 m). Source water counts only within ≈ 500 m of terraintype.dat's water (it moves the
  coast, the Kinneret's and the Dead Sea's shores to the real ones); ponds, reservoirs and rivers elsewhere stay the
  layer's (else a blurred 1998 blob shows inside a modern pond), and water patches narrower than ≈ 100 m are
  ignored.
- **No data stays the original's**: outside the source (no tile, no sheet; a sheet's white fill beyond the
  photographed area, e.g. the sea and across the border), feathered like the region border; no-data patches
  narrower than ≈ 100 m (a saturated white roof) are ignored.
- **Airbases and fine insets stay the original's**: terraintype.dat runway cells and every original site inset
  (airbases, targets: map.ptt inset records of level ≤ 2; every site has level 0–2 records). The game's airbases are
  not at their real positions (docs/georef.md §4), so a modern layer there would put the mission's base in empty
  desert. map.ptt's four large level-3 inset records are not sites but the original's regional 9.9 m cover of
  Israel (the whole country); an Israel layer replaces them (with "level ≤ 3" it could replace nothing).
- Region / airbase / inset / coverage borders are feathered over ≈ 240 m (two box passes), computed with a margin
  (64 px at level 3) so neighbouring nodes match at their seams. Radii are ground sizes: at level 1 every pixel
  radius is ×4.

## 4. Looks

- **1998 colours** (`sentinel2`, `mapi2015`): the modern pixel × the per-channel ratio of the local means (≈ 500 m, land pixels
  only) of the original and the modern image, clamped to 0.33–3. Keeps the modern detail with the original's
  palette, so the layer blends into the untouched original around it.
- **Modern colours** (`sentinel2_modern`): surface reflectance to display values — linear (0.42 reflectance =
  white), display gamma, a little extra saturation.
- **Survey of Israel photo** (`mapi2015_modern`, and the input of `mapi2015`): the sheets differ a lot in haze and
  exposure (0.5th percentile RSH 32 / 45 / 50 against HEF 4 / 5 / 8; 99.5th percentile MZR, a Negev sheet, 156
  against HEF 250), and as they come they look washed out (Rishon) or dull grey (the Negev). So each sheet gets
  **auto-levels**: each band from the sheet's **dark-object level** (its 0.5th percentile; haze removal) to 0, and
  the sheet's white level (the brightest band's 99.5th percentile, one for all bands so the colour balance stays)
  to 235, then a display gamma of 1.1. The levels come from a 40 m copy of the sheet (photo pixels only, not the
  white fill), cached in `.work/mapi2015/sheets.tsv`, and are blended over 4 km across sheet borders so the
  correction adds no seam. Nothing else: the photo's own colours.

## 5. In the game

- `game/terrain/imagery_layers.gd`: the options per region (`REGIONS`), `available(id)` (= its manifest exists;
  "original" always), `selected()` (the picked, converted layers, Israel first), `attributions()`.
- **Preferences → Extras** (ours): one row per region ("Imagery Israel": Original / Survey 2 m / Survey 2 m modern;
  "Imagery outside Israel": Original / Sentinel-2 / Sentinel-2 modern; three choices in narrower columns), after the other Extras rows (the page scrolls like Physics, 8 rows shown); options whose layer is not converted are
  shown in grey and cannot be picked (user decision: greyed, not hidden). Default "Original"; Extras DEFAULT
  resets them. Hebrew labels in game/menu/strings_he.json. Settings `imagery_israel` / `imagery_outside`
  ([gameplay] section, with the other Extras). (First on the Graphics page; moved so that page stays the original.)
- `terrain.gd`: at `_ready` each picked layer's nodes are added to the colour-node set with their directory
  (`colour_dir(node)`); `_path()` reads those nodes from the layer, everything else (and every height) from the
  original. The preload's textures are not adopted when they were loaded with other layers. A level-1 layer needs
  nothing more: a node of level ≤ 2 splits near the focus when finer imagery exists below it (`_finest`), so a
  level-2 node splits into the layer's level-1 nodes within ≈ 7.6 km (1.5 × its 5 km side at the default terrain
  detail; a 2.5 m texel is one screen pixel at ≈ 2 km), as it always did for the airbase insets.

## 6. Attribution and checks

- CC BY sources need a credit: every converted layer's `attribution` (manifest) rolls in the credits on Quit,
  before the original's credits, under "Terrain Imagery" (`imagery_layers.gd attributions()`, docs/credits.md). It
  is no longer printed on the flight loading screen: CC BY 4.0 §3(a)(1) allows attribution "in any reasonable
  manner based on the medium", and a game's credits roll is the usual place; the roll comes on every quit from the
  menus (QUIT, Esc on Main / Login, the window's close button). A new source only needs its `attribution` in the
  manifest (Survey of Israel: "© Survey of Israel 2015, via data.gov.il").
- `iaf-imagery compare <theatre-dir> <layers-root> <level> <i> <j> <out.png>`: the original node, the 1998-colour and
  the modern-colour layer node side by side (the first layer pair that has the node).
- `tests/godot/_imagery_shot.gd` (dev helper): real-render shots of the Israel layers at a `--at` pose, one per
  layer, with the frame rate.
- Tests: Rust `imagery` unit tests (feather inside only, tone curve, small patches dropped, photo water, sheet
  levels ignore the fill and blend across sheets) and `itm` (WGS84 → Israeli TM Grid equals PROJ),
  `tests/godot/test_imagery.gd` (layer node replaces only its node, a level-1 layer node is drawn near the focus,
  heights stay original, only converted layers count), `test_ui_smoke.gd` (drop-downs
  open, greyed options cannot be picked, close on a click elsewhere, EN + HE).

## 7. How to run

```sh
tools/setup.sh --imagery sentinel2          # estimate, ask, fetch + convert (needs gdal); alone = imagery steps only
tools/setup.sh --imagery mapi2015-bases     # Survey of Israel sheets around the airbases, through the browser, + convert
tools/setup.sh --imagery mapi2015           # all 79 sheets (download what is missing) + convert (incremental)

# by hand: a small sample (lon0,lat0,lon1,lat1), e.g. the head of the Gulf of Suez (a few 40 km units)
cargo build --release -p iaf-tools
./target/release/iaf-imagery sentinel2 assets/install assets/converted/terrain/theatre assets/converted/imagery \
    --area 32.4,29.8,32.7,30.1 [--dry-run] [--threads 4]
```

Full `sentinel2` run: 318 work units, ≈ 28 GB of range reads (an upper bound: the estimate counts all four bands
of the overlapping tiles), ≈ 6 GB written for both looks. Delete `assets/converted/imagery/<id>/` to remove a layer
(the drop-down greys it out again).

## 8. Survey of Israel 2015 (2 m): `mapi2015`

The sheets (one ZIP per 1:50 000 sheet, 79 ZIPs, list in tools/imagery/mapi2015_sheets.tsv) arrive in
`assets/source/imagery/mapi2015/` via `tools/imagery/fetch-mapi2015-curl.sh [--bases]` (what `tools/setup.sh
--imagery mapi2015` runs: curl with the data.gov.il WAF token Firefox earned; when it stops on an expired token it
prints a link to open once in Firefox, then re-run; with no token in Firefox it falls back to
`tools/imagery/fetch-mapi2015.sh`, which opens the links in browser tabs and moves the finished ZIPs); setup then
converts them (by hand: `./target/release/iaf-imagery mapi2015 assets/install assets/converted/terrain/theatre
assets/converted/imagery [--sheets DIR] [--area …] [--dry-run] [--threads N]`).

- **Format** (checked on all 79): each ZIP holds one GeoTIFF (some sheets two or four parts, `_N` / `_S`,
  `_NE` …), 2 m pixels, RGB bytes (HEF: RGBA with an all-opaque alpha), uncompressed or LZW, strips, in the
  **Israeli TM Grid** (EPSG:2039; five sheets carry no CRS, only a .tfw on the same grid). Outside the photographed
  area (the sea, across the border) the fill is pure white. The ZIPs are deflated, so a sheet is read in place
  through GDAL's `/vsizip/` (no unzip); opening one inflates it up to its TIFF directory (1–2 s), so the extents
  and levels (§4) are measured once and cached (`.work/mapi2015/sheets.tsv`, per ZIP name, size and time).
- **Projection**: lon/lat (WGS84, the georef's) → Israeli TM Grid in Rust (`iaf_tools::itm`): the datum shift is
  **not** negligible (≈ 78 m around Tel Aviv: Israel 1993 vs WGS84), so the EPSG 7-parameter Helmert "Israel 1993
  to WGS 84 (2)" (PROJ's default for EPSG:2039) inverted, then the transverse Mercator on GRS80 (Krüger series);
  equal to `gdaltransform -s_srs EPSG:4326 -t_srs EPSG:2039` within 2 cm (test).
- **Work units**: level-4 nodes (20 km, 64 level-1 nodes) in the Israel region that overlap a sheet. A unit's window
  (the unit's TM box + 1 km for the node margins) is cut from its sheets (`gdalbuildvrt` of those sheets +
  `gdal_translate` to an ENVI temp file, ≈ 0.4 GB, deleted after the unit; black where no sheet is). A unit takes
  ≈ 2 min on one thread (≈ 1.5 s per level-1 node: warp, rules, blurs over 1536² px with the margins).
- **Level 1** (2.5 m/px, the source's 2 m): the runtime draws level-1 layer nodes without changes (§5).
- **Incremental**: each unit's mark lists the sheets in its window; a re-run redoes the units whose sheet set
  changed (sheets added) and rebuilds the coarser levels. After downloading more sheets, re-run
  `tools/setup.sh --imagery mapi2015` (or the command above). Incomplete downloads (`*.part`, `*.crdownload`, a
  ZIP that does not open) are skipped.
- **Rules** (§3): the region is map.ptt's Israel rectangle; airbases / site insets (level ≤ 2) stay the
  original's; the original's level-3 regional cover is replaced. The photo's sea and the sheets' white fill stay the
  original's.
- **Credit / licence** (manifest): attribution "© Survey of Israel 2015, via data.gov.il", licence the data.gov.il
  open licence (docs/imagery-sources.md §2.1), `downloaded` = the ZIPs' file dates (the licence in force at download
  time governs), `sheets` = the sheets used.
- **Full run** (79 ZIPs, 102 sheet parts, ≈ 34 900 km² incl. the white fill; 8-core desktop, `--threads 6`): 112
  work units, ≈ 13 min to measure the sheets once (cached), then ≈ 41 min; 4 621 level-1 nodes (+ 74 level-0) and 6 413 nodes per
  layer up to level 11, ≈ 2.4 GB per look (≈ 4.7 GB both); peak temp ≈ 6 × 0.4 GB in `.work/mapi2015/`. In the
  game the frame rate low over Rishon LeZion and Tel Nof is the same with the layer as without (it only swaps
  textures; ≈ 64 level-1 nodes of 0.7 MB BC1 near the jet).
- **Seams**: the 1998-colour look blends into the kept original; the modern look differs from it in colour by
  design. The kept site insets are rectangles, so their border is a 240 m feather between 2015 and 1998 content
  (74 of the original's level-0 inset nodes get a layer version for it, §2 step 4).
- **Known limit**: where both an Israel and an outside-Israel layer are picked, a coarse node (level ≳ 6) that
  straddles the Israel rectangle comes from the Israel layer (Israel first, §5), so its outside part shows the
  original there; only visible from high up, at the region border.
