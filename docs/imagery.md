# Modern terrain imagery layers

This doc describes the optional modern imagery for the terrain: how the converter builds it and how the game draws
it. Key facts:

- It is opt-in; the game shows the original imagery by default (docs/deviations.md §2).
- Each modern source becomes its own **layer**: a node set on the game's terrain quadtree with the same keys as the
  converted map.ptt (`L<level>/c_<i>_<j>.jpg`).
- A layer replaces only a node's colour texture. Heights, terrain types, missions and insets stay the original's.
- Related docs: sources, licences and why in docs/imagery-sources.md; the warp into the game frame in docs/georef.md;
  the user-facing summary in the README, "Terrain imagery data".

Terms used below:

- **ESA**: the European Space Agency.
- **COG**: Cloud-Optimised GeoTIFF, a GeoTIFF laid out so that a client can read parts of it over HTTP.
- **NIR**: the near-infrared band.
- **NDWI**: normalised difference water index, (green − NIR) / (green + NIR); above 0 means water.
- **TM**: transverse Mercator, a map projection. The **Israeli TM Grid** is Israel's national grid (EPSG:2039).
- **Inset**: a map.ptt record that holds finer imagery for one area (docs/formats/ptt.md).
- **Feather**: a soft blend from one image to the other across a border.

## 1. Sources and layers

Four layers are converted today; SPOT 5 is a candidate.

| layer id | region | source | state |
|---|---|---|---|
| `sentinel2` | outside Israel | ESA WorldCover 2021 Sentinel-2 RGB(NIR) composite, 10 m, CC BY 4.0, colour-matched to the 1998 imagery | done |
| `sentinel2_modern` | outside Israel | the same, modern colours | done |
| `mapi2015` | Israel | Survey of Israel 2015 aerial photo, 2 m (data.gov.il), written at level 1 (2.5 m/px), colour-matched to the 1998 imagery | done (§8) |
| `mapi2015_modern` | Israel | the same, the photo's own colours (haze removed) | done (§8) |
| SPOT 5 | outside Israel (maybe Israel) | CNES (the French space agency) SPOT World Heritage, 5 m | not started (free CNES account, orthorectification) |

## 2. Pipeline (`iaf-imagery`, crates/iaf-tools/src/imagery_run.rs + src/imagery.rs)

The tool converts a source in seven steps:

1. **Work units**: the tool works on level-5 nodes (40 km of game frame; `mapi2015`: level-4 nodes, 20 km, see §8)
   that contain at least one pixel the layer may replace (§3). It first prints the number of units, the download
   estimate (WorldCover tile bytes × overlap) and the output size.
2. **Fetch** per unit: the tool takes the unit's lon/lat box (through the georef warp, plus a margin) and cuts it out
   of the WorldCover 1°×1° COGs on the public S3 bucket by **HTTP range reads** (`gdalbuildvrt` + `gdal_translate`
   over `/vsicurl/`). It reads only the needed overviews / blocks and keeps no mirror. It lists the tiles with the S3
   listing API (`curl`).
3. **Warp**: for each layer node (level 3: 1024², 9.9 m/px; `mapi2015`: level 1, 2.5 m/px):
   - the spline `iaf_tools::georef` gives (lon, lat) every 32 px;
   - from that, the source's pixel position (lon/lat directly, or the Israeli TM Grid for the Survey of Israel,
     `iaf_tools::itm`), bilinear between;
   - the tool samples the source bilinearly.
4. **Compose** (§3): the layer where it is allowed, the original elsewhere, feathered borders. The tool also composes
   the original's own nodes in the unit that are finer than the layer level (the site insets' level 0–2 nodes). Near
   the jet the runtime draws those nodes in place of the layer's coarser node; without a layer version of them, the
   layer would end at their node-grid edge with a hard straight line. Those wholly inside a kept inset compose to
   nothing and stay the original's.
5. **Two looks** (§4): the tool writes both as JPEG (quality 88) into `assets/converted/imagery/sentinel2/` and
   `…_modern/`.
6. **Coarser levels up to 11**: the tool builds each parent from its four children (the layer's child where written,
   else the original's rendition), so a layer node exists at every level above a written node. It rebuilds them all on
   every run (minutes), so they take in units converted later.
7. **manifest.json** per layer: name, title, region, source, licence, attribution, levels, node list. The tool records
   finished units in `assets/converted/imagery/.work/` (`.work/mapi2015/` for the sheets), so a run resumes where it
   stopped. Each unit's mark (`done_<i>_<j>`) is a small text file:
   - `rules v<N> <hash>`: the rules tag. `N` is `RULES_VERSION` (crates/iaf-tools/src/imagery.rs); the hash covers
     what the rules decide in the unit and 1 km around it: the region, the kept target insets and the airbase
     footprint cells (§3).
   - `# <sheets>`: the sheets in the unit's window (`mapi2015` only).
   - one line per node the unit wrote.

   A run converts a unit again when its mark is missing, its sheets changed or its rules tag differs. So a change to
   a footprint redoes only the units near that base. A change to the rules or to the composition elsewhere must bump
   `RULES_VERSION`; that redoes every unit.
   - Marks from before the rules tags (no `rules` line) still count off the airbases. On an airbase the tool converts
     the unit again, because it may hold the base's old inset rectangle (`RULES_VERSION` 1).
   - `--dry-run` lists each unit it would convert again and the reason (`rules changed`, `sheets changed`), and
     counts the units not converted yet.
   - `--stale` converts only units whose mark is out of date, plus unmarked units on an airbase; units never
     converted stay so. `tools/setup-cli.sh` runs it for each layer after restoring imagery from a mirror
     (`IAF_IMAGERY_MIRROR`), once the theatre exists. The restore copies imagery only when
     `assets/converted/imagery` is missing, so it never overwrites newer local units. When the sheets were not
     restored, `mapi2015` cannot be converted again: setup-cli.sh then prints a warning that lists the out-of-date units.
     When `sentinel2` cannot reach WorldCover, it prints a warning and goes on.

## 3. Where a layer replaces the original

A layer replaces the original only on land inside its region, with real data, away from the airbases and site insets.
In detail:

- **Region**: map.ptt's largest inset record is "Israel". An outside-Israel layer writes only outside it; an Israel
  layer only inside.
- **Water stays the original's**: open water in the source and sea in terraintype.dat keep the 1998 sea.
  - Water test: Sentinel-2 water is NIR below green (NDWI > 0); photo water is blue-green clearly above red and not
    bright.
  - The coastline is the real one (feather ≈ 20 m).
  - Source water counts only within ≈ 500 m of terraintype.dat's water. This moves the coast and the Kinneret's and
    the Dead Sea's shores to the real ones.
  - Ponds, reservoirs and rivers elsewhere stay the layer's (else a blurred 1998 blob shows inside a modern pond).
  - The tool ignores water patches narrower than ≈ 100 m.
- **No data stays the original's**: areas outside the source (no tile, no sheet; a sheet's white fill beyond the
  photographed area, e.g. the sea and across the border) keep the original, feathered like the region border. The
  tool ignores no-data patches narrower than ≈ 100 m (a saturated white roof).
- **Airbases keep their footprint, target sites their inset**: a site is a group of overlapping original insets of
  level ≤ 2 (map.ptt records; every site has level 0–2 records). terraintype.dat's runway cells always stay the
  original's.
  - Reason: the game's airbases are off their real positions (docs/georef.md §4), so a modern layer there would put
    the mission's base in empty desert.
  - The real bases cannot be moved onto the game's bases either (§9).
  - **Airbase sites** (a site with a terraintype.dat runway cell) keep only the base's **footprint**
    (`iaf_tools::airbases::footprint`, rasterised once per site at level 2, ≈ 5 m cells):
    1. Seeds: the runway cells, discs of 40 m around iaf.ibx's base points (tower, lineup, taxi and hangar points).
    2. The base art: paved pixels of the 1998 inset (grey, or the aprons' blue / purple tint), strips narrower than
       ≈ 12 m (roads) dropped, reached from the seeds within 400 m.
    3. The missions' units on the ground (the playable missions, those missionlist.json names; a unit higher than its
       nearest base's lineup + 150 m is in the air): discs of 80 m for units within 700 m of the base, in two rounds, so the base's building
       clusters (hangars, shelters, revetments, factories) stay on 1998 ground.
    4. Gaps closed over 150 m, holes filled, then a margin of 150 m.
  - Footprints (`iaf-imagery footprints <install> <theatre> <out-dir>` prints them and draws each site):

    | site | inset rectangle | footprint |
    |---|---|---|
    | Ramon | 48.9 km² | 8.1 km² |
    | Tel Nof | 169.6 km² | 11.0 km² |
    | Ramat David | 142.1 km² | 13.5 km² |

    The other airbase sites (Refidim, Damascus, Kuzeir, Bley) lie outside the Survey sheets, so their footprint
    changes nothing today.
  - **Target sites** keep their whole inset rectangle.
  - map.ptt's four large level-3 inset records are the original's regional 9.9 m cover of Israel (the whole country),
    not sites. An Israel layer replaces them (with "level ≤ 3" it could replace nothing).
- **Feathering**: region / target-site / coverage borders are feathered over ≈ 240 m, airbase footprints over ≈ 120 m
  (two box passes). The tool computes them with a margin (64 px at level 3), so neighbouring nodes match at their
  seams. Radii are ground sizes: at level 1 every pixel radius is ×4.
- **Colour at the seams**: the colour match (§4) leaves out the airbase footprints, so the base's pavement does not
  tint the ring around it. In the modern look the original's colours move toward the modern image's local means
  across the feather (by the layer's weight), so the 1998 base meets the 2015 fields without a colour step.

## 4. Looks

Each source has two looks: one in the 1998 palette and one in modern colours.

- **1998 colours** (`sentinel2`, `mapi2015`): the modern pixel × the per-channel ratio of the local means (≈ 500 m,
  land pixels only) of the original and the modern image, clamped to 0.33–3. This keeps the modern detail with the
  original's palette, so the layer blends into the untouched original around it.
- **Modern colours** (`sentinel2_modern`): surface reflectance to display values: linear (0.42 reflectance =
  white), display gamma, a little extra saturation.
- **Survey of Israel photo** (`mapi2015_modern`, and the input of `mapi2015`): the photo's own colours after
  auto-levels per sheet.
  - Why: the sheets differ a lot in haze and exposure (0.5th percentile RSH 32 / 45 / 50 against HEF 4 / 5 / 8;
    99.5th percentile MZR, a Negev sheet, 156 against HEF 250). As delivered, they look washed out (Rishon) or dull
    grey (the Negev).
  - **Auto-levels**: each band maps from the sheet's **dark-object level** (its 0.5th percentile; haze removal) to 0,
    and the sheet's white level (the brightest band's 99.5th percentile, one value for all bands so the colour
    balance stays) to 235. Then a display gamma of 1.1.
  - The levels come from a 40 m copy of the sheet (photo pixels only, without the white fill), cached in
    `.work/mapi2015/sheets.tsv`.
  - They are blended over 4 km across sheet borders, so the correction adds no seam.
  - That is the whole correction.

## 5. In the game

The player picks a layer per region in Preferences → Graphics → MORE; the terrain then reads those nodes from the layer.

- `game/terrain/imagery_layers.gd`: the options per region (`REGIONS`), `available(id)` (= its manifest exists;
  "original" always), `selected()` (the picked, converted layers, Israel first), `attributions()`.
- **Preferences → Graphics → MORE** (ours): one row per region, after the other graphics rows (the page scrolls like Physics,
  8 rows shown):
  - "Imagery Israel": Original / Survey 2 m / Survey 2 m modern;
  - "Imagery outside Israel": Original / Sentinel-2 / Sentinel-2 modern;
  - three choices in narrower columns.
  - Options whose layer is not converted are shown in grey and cannot be picked (user decision: greyed, not hidden).
  - Default "Original"; DEFAULT on that view resets them. Hebrew labels in game/menu/strings_he.json.
  - Settings `imagery_israel` / `imagery_outside` ([gameplay] section, with the other Extras).
  - The rows were first on the Graphics page; they moved so that page stays the original.
- `terrain.gd`:
  - At `_ready` it adds each picked layer's nodes to the colour-node set with their directory (`colour_dir(node)`).
  - `_path()` reads those nodes from the layer and everything else (and every height) from the original.
  - It skips the preload's textures when they were loaded with other layers.
  - A level-1 layer needs no extra code: a node of level ≤ 2 splits near the focus when finer imagery exists below it
    (`_finest`). So a level-2 node splits into the layer's level-1 nodes within ≈ 7.6 km (1.5 × its 5 km side at the
    default terrain detail; a 2.5 m texel is one screen pixel at ≈ 2 km), as it always did for the airbase insets.

## 6. Attribution and checks

- **Credits**: CC BY (Creative Commons Attribution) sources need a credit. Every converted layer's `attribution`
  (manifest) rolls in the credits on Quit, before the original's credits, under "Terrain Imagery"
  (`imagery_layers.gd attributions()`, docs/credits.md).
  - The flight loading screen no longer prints it. CC BY 4.0 §3(a)(1) allows attribution "in any reasonable manner
    based on the medium", and a game's credits roll is the usual place.
  - The roll comes on every quit from the menus (QUIT, Esc on Main / Login, the window's close button).
  - A new source only needs its `attribution` in the manifest (Survey of Israel: "© Survey of Israel 2015, via
    data.gov.il").
- `iaf-imagery compare <theatre-dir> <layers-root> <level> <i> <j> <out.png>`: shows the original node, the
  1998-colour and the modern-colour layer node side by side (from the first layer pair that has the node).
- `tests/godot/_imagery_shot.gd` (dev helper): real-render shots of the Israel layers at a `--at` pose, one per
  layer, with the frame rate.
- Tests:
  - Rust `imagery` unit tests: feather inside only, tone curve, small patches dropped, photo water, sheet levels
    ignore the fill and blend across sheets.
  - Rust `itm`: WGS84 (World Geodetic System 1984) → Israeli TM Grid equals PROJ.
  - `tests/godot/test_imagery.gd`: a layer node replaces only its node, a level-1 layer node is drawn near the focus,
    heights stay original, only converted layers count.
  - `test_ui_smoke.gd`: drop-downs open, greyed options cannot be picked, they close on a click elsewhere, EN + HE.

## 7. How to run

`tools/setup-cli.sh --imagery` fetches and converts a layer; the `iaf-imagery` binary does the same by hand for an area.

```sh
tools/setup-cli.sh --imagery sentinel2          # estimate, ask, fetch + convert (needs gdal); alone = imagery steps only
tools/setup-cli.sh --imagery mapi2015-bases     # Survey of Israel sheets around the airbases, through the browser, + convert
tools/setup-cli.sh --imagery mapi2015           # all 79 sheets (download what is missing) + convert (incremental)

# by hand: a small sample (lon0,lat0,lon1,lat1), e.g. the head of the Gulf of Suez (a few 40 km units)
cargo build --release -p iaf-tools
./target/release/iaf-imagery sentinel2 assets/install assets/converted/terrain/theatre assets/converted/imagery \
    --area 32.4,29.8,32.7,30.1 [--dry-run] [--threads 4]
```

- A full `sentinel2` run: 318 work units, ≈ 28 GB of range reads (an upper bound: the estimate counts all four bands
  of the overlapping tiles), ≈ 6 GB written for both looks.
- To remove a layer, delete `assets/converted/imagery/<id>/`; the drop-down greys it out again.

## 8. Survey of Israel 2015 (2 m): `mapi2015`

The Israel layers come from the Survey of Israel 2015 aerial photo: 79 ZIPs, one per 1:50 000 sheet, listed in
tools/imagery/mapi2015_sheets.tsv.

**Getting the sheets** (what `tools/setup-cli.sh --imagery mapi2015` runs):

1. `tools/imagery/fetch-mapi2015-curl.sh [--bases]` downloads the sheets into `assets/source/imagery/mapi2015/` with
   curl and the data.gov.il WAF (web application firewall) token that Firefox earned.
2. When it stops on an expired token, it prints a link: open it once in Firefox, then re-run.
3. With no token in Firefox it falls back to `tools/imagery/fetch-mapi2015.sh`, which opens the links in browser tabs
   and moves the finished ZIPs.
4. Setup then converts them. By hand: `./target/release/iaf-imagery mapi2015 assets/install
   assets/converted/terrain/theatre assets/converted/imagery [--sheets DIR] [--area …] [--dry-run] [--threads N]`.

Details:

- **Format** (checked on all 79):
  - Each ZIP holds one GeoTIFF (some sheets two or four parts, `_N` / `_S`, `_NE` …): 2 m pixels, RGB bytes (HEF:
    RGBA with an all-opaque alpha), uncompressed or LZW, strips.
  - Projection: the **Israeli TM Grid** (EPSG:2039). Five sheets carry no CRS (coordinate reference system), only a
    .tfw on the same grid.
  - Outside the photographed area (the sea, across the border) the fill is pure white.
  - The ZIPs are deflated, so the tool reads a sheet in place through GDAL's `/vsizip/` (no unzip). Opening one
    inflates it up to its TIFF directory (1–2 s), so the tool measures the extents and levels (§4) once and caches
    them (`.work/mapi2015/sheets.tsv`, per ZIP name, size and time).
- **Projection**: lon/lat (WGS84, the georef's) → Israeli TM Grid, in Rust (`iaf_tools::itm`).
  - The datum shift is large: ≈ 78 m around Tel Aviv (Israel 1993 vs WGS84). So the code applies the EPSG 7-parameter
    Helmert "Israel 1993 to WGS 84 (2)" (PROJ's default for EPSG:2039) inverted, then the transverse Mercator on GRS80
    (Krüger series).
  - The result equals `gdaltransform -s_srs EPSG:4326 -t_srs EPSG:2039` within 2 cm (test).
- **Work units**: level-4 nodes (20 km, 64 level-1 nodes) in the Israel region that overlap a sheet.
  - A unit's window is the unit's TM box + 1 km for the node margins. The tool cuts it from its sheets
    (`gdalbuildvrt` of those sheets + `gdal_translate` to an ENVI temp file, ≈ 0.4 GB, deleted after the unit; black
    where no sheet is).
  - A unit takes ≈ 2 min on one thread (≈ 1.5 s per level-1 node: warp, rules, blurs over 1536² px with the
    margins).
- **Level 1** (2.5 m/px, the source's 2 m): the runtime draws level-1 layer nodes as they are (§5).
- **Incremental**: each unit's mark lists the sheets in its window and the rules tag (§2, item 7). A re-run redoes
  the units whose sheet set changed (sheets added) or whose rules tag differs, and rebuilds the coarser levels.
  - After downloading more sheets, re-run `tools/setup-cli.sh --imagery mapi2015` (or the command above).
  - The tool skips incomplete downloads (`*.part`, `*.crdownload`, a ZIP that does not open).
- **Rules** (§3): the region is map.ptt's Israel rectangle. Airbase footprints and target site insets (level ≤ 2)
  stay the original's;
  the original's level-3 regional cover is replaced. The photo's sea and the sheets' white fill stay the original's.
- **Credit / licence** (manifest): attribution "© Survey of Israel 2015, via data.gov.il"; licence the data.gov.il
  open licence (docs/imagery-sources.md §2.1); `downloaded` = the ZIPs' file dates (the licence in force at download
  time governs); `sheets` = the sheets used.
- **Full run** (79 ZIPs, 102 sheet parts, ≈ 34 900 km² incl. the white fill; 8-core desktop, `--threads 6`):
  - 112 work units; ≈ 13 min to measure the sheets once (cached), then ≈ 41 min;
  - 4 621 level-1 nodes (+ 74 level-0) and 6 413 nodes per layer up to level 11;
  - ≈ 2.4 GB per look (≈ 4.7 GB both); peak temp ≈ 6 × 0.4 GB in `.work/mapi2015/`.
  - In the game, the frame rate low over Rishon LeZion and Tel Nof is the same with the layer as without. The layer
    only swaps textures: ≈ 64 level-1 nodes of 0.7 MB BC1 (a GPU block-compressed texture format) near the jet.
- **Seams**: the 1998-colour look blends into the kept original; the modern look differs from it in colour by
  design and grades the original's colours toward it across the feather (§3). The kept target insets are
  rectangles (a 240 m feather); the airbases keep their footprint (a 120 m feather). Of the original's level-0
  inset nodes, those around the footprints get a layer version (§2 step 4).
- **Known limit**: when the player picks both an Israel and an outside-Israel layer, a coarse node (level ≳ 6) that
  straddles the Israel rectangle comes from the Israel layer (Israel first, §5). Its outside part then shows the
  original. This is visible only from high up, at the region border.

## 9. Real airbases on the game's bases: checked, kept original

A Survey layer shows the 1998 imagery at the game's three airbases in Israel: Ramon, Tel Nof and Ramat David
(iaf.ibx `David`). This section checks whether the real base, taken from the 2 m photo and moved onto the game's
runways, could replace it. It cannot, for two reasons. So the bases keep the original (§3).

**1. The 2015 photo hides the real bases.** At all three real bases the Survey of Israel photo shows filler terrain:
Tel Nof and Ramat David show fields, Ramon shows desert, with no runway, taxiway or building. The filler areas have
straight edges around each base. So the source has no airbase imagery to move. Crops of the game base (1998) and of the real place
(the `mapi2015_modern` layer), 6 km wide with a 100 m / 500 m grid, are in `assets/converted/research/airbases/`.

**2. The game's runway layouts are not the real ones.** The test is a similarity transform (move, rotate, one scale)
fitted by least squares on the runway ends.
- Game runway ends: the runway digit centres (docs/formats/ptt.md, "Runway number fix"), or the 1998 image for Tel
  Nof, whose digits cannot be read. Real runway ends: OpenStreetMap runway ways (© OpenStreetMap contributors, ODbL;
  Overpass query 2026-10-17), put into engine metres with the georeference.
- Digits sit tens of metres inside the paved ends, so the ends agree only to about ± 50 m. The residuals below are
  far larger than that.

| base | game runways (heading, length) | real runways (heading, length) | best similarity | residuals |
|---|---|---|---|---|
| Ramon | two parallel at 050°: 3355 m and 3209 m, 645 m apart, the south one 930 m further south-west | two parallel at 067°: 2682 m and 2990 m, 351 m apart, the south one 155 m longer at each end | scale 1.16, rotation 15° | 380–635 m (rms 526 m) |
| Tel Nof | 090° 4041 m and 150° 3908 m, crossing (60° apart) | 151° 3047 m, 151° 3198 m and 183° 3020 m (0° and 32° apart) | no pairing keeps the angle; best scale 1.17, rotation 53° | 551–1269 m (rms 885 m) |
| Ramat David | 090° 3845 m, 150° 3386 m, 030° 2554 m | 087° 2934 m, 145° 2944 m, 108° 3154 m | on the two matching runways: scale 1.25, rotation −7° | 153–467 m (rms 344 m) |

- An affine transform (6 parameters) brings Ramon to 120–130 m, but only by stretching the base 3.5 times along one
  axis and shrinking it to 0.6 along the other. Shelters and aprons would land nowhere near the game's shelter and
  apron models. For Ramat David the affine transform still leaves 130–450 m.
- So the game's runways and its airbase models (hangars, shelters, tower) cannot sit on a moved real base.

**What improves the take-off view instead** (both built):
- **The base's footprint** (§3): the layers keep the 1998 imagery only on the base itself (runways, taxiways, aprons,
  shelters, the painted area and the base's building clusters, plus 150 m), no longer on the whole inset rectangle.
  The 2 m photo comes up to the base: Ramon 48.9 → 8.1 km², Tel Nof 169.6 → 11.0 km², Ramat David 142.1 → 13.5 km².
  - The 1998 / 2015 border runs 150–270 m outside the base edge, feathered over ≈ 120 m and colour-graded (§3).
  - Of the playable missions' ground units in the three sites, 9 stand on 2015 ground (`iaf-imagery footprints` lists
    them): route and audio markers and sensors (not drawn) and one jeep (401, 4 km east of Ramat David).
  - Before / after captures (take-off, roll, final, 1500 m overhead, low pass; noon and night; both looks):
    `assets/converted/research/airbases/a_footprint/`.
- **Detailed airbases** (Graphics → MORE → Airbases, docs/rendering.md §6): a procedural runway, taxiway and apron
  surface with markings drawn over the original's paved surface near the ground.

Airbases in the Israel rectangle outside Israel (Damascus / Mezzeh, Bley, the Jordanian bases) lie outside the
Survey sheets' photographed area, so they keep the original in any case.
