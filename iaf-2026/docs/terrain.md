# IAF 2026: the terrain

**Terms:** DEM = digital elevation model (the ground's heights); GLO-30 = the Copernicus DEM at 30 m; S2 =
Sentinel-2 (the ESA satellite pictures); UTM 36N = Universal Transverse Mercator zone 36 north (EPSG:32636); ITM =
Israeli Transverse Mercator (EPSG:2039, the Survey of Israel's grid); node = one 1024² tile of the theatre tree; level
L = a node covers 1024 · 2^L m with a pixel of 2^L m; "inferred" = our own reasoning; "open" = no source found.

The sim's terrain is one theatre at 1:1 built from open data by `iaf-sim terrain` (plan.md item B1): heights from the
Copernicus DEM, colour from Sentinel-2 everywhere and from the Survey of Israel's 2 m photo over Israel. It is written
in the same shape as the original game's converted theatre, so `shared/terrain/terrain.gd` and `IafHeights` read it
with no change of their own.

```sh
cargo build --release -p iaf-tools --bin iaf-sim
target/release/iaf-sim terrain [assets] [--box E0 N0 E1 N1] [--out DIR] [--threads N]   # needs GDAL and curl
```

`./iaf2026-setup` runs it after `iaf-sim all`. A run resumes: finished work units are marked in `<out>/.work/`, and
the DEM tiles stay in `assets/source/dem/`. A finished run is stamped in `meta.json` (`built_from`: the box, the
detail area and the sheet ZIPs' names and sizes); a run with the same inputs ends at once ("up to date"). To build
again, delete `meta.json` (and `.work/done_*` for the units to redo).

## 1. Sources

| what | source | licence | how it is read |
|---|---|---|---|
| heights | Copernicus DEM GLO-30[^dem] | Copernicus WorldDEM-30 licence[^dem-licence]: free use, the notices of §5 | 1° tiles (Cloud-Optimised GeoTIFF) from the public AWS bucket `copernicus-dem-30m`[^dem-aws], downloaded once into `assets/source/dem/` (a `.none` mark for a cell with no tile: open sea) |
| colour, whole box | ESA WorldCover 2021 Sentinel-2 RGBNIR composite, 10 m[^wc] | CC BY 4.0 | GDAL range reads from the WorldCover bucket, as `iaf-imagery sentinel2` (docs/imagery.md); its overviews serve the 32 m nodes |
| colour, Israel | Survey of Israel orthophoto 2015, 2 m[^soi] | data.gov.il open licence | the sheet ZIPs already in `assets/source/imagery/mapi2015/` (`iaf-imagery fetch-mapi2015`); nothing is downloaded for this step |
| airbase outlines | OpenStreetMap, the four bases' `boundary` in `iaf-2026/data/airbases/` ([airbases.md](airbases.md))[^osm] | ODbL 1.0 | §4 |

GLO-30 is a surface model: its heights include buildings and trees, above the EGM2008 geoid (≈ mean sea level)[^dem].
Nothing is read from `assets/install`.

## 2. The frame and the box

The frame is UTM 36N with 1 terrain unit = 1 m. Terrain unit (tx, ty) is easting `E0 + tx`, northing `N1 − ty`, so
the engine's world X / Y (metres east / north) are the UTM easting / northing themselves. B2b places an airbase by
converting its lat / lon to UTM 36N (`gdaltransform -s_srs EPSG:4326 -t_srs EPSG:32636`, or any UTM formula) and
uses the numbers as world X / Y; no other step.

`meta.json` holds the georeference: `units_to_metres` 1, `x_shift` = E0, `y_shift` = N1, `crs` "EPSG:32636", raw
height = 5000 + 10 · metres (`sea_level_raw` 5000, `height_scale` 10: 0.1 m steps from −500 m to 6,053 m; the Dead
Sea shore is −430 m, Mount Hermon 2,814 m).

The box (`sim_terrain::BOX`), UTM 36N metres, corners on multiples of 1024 m:

| | E0 | N0 | E1 | N1 | size |
|---|---|---|---|---|---|
| theatre | 507,904 | 3,255,296 | 855,040 | 3,766,272 | 347 × 511 km |
| detail area (`DETAIL`) | 611,000 | 3,258,000 | 786,500 | 3,694,000 | Israel's bounding box: lon 34.2–35.95° E, lat 29.45–33.35° N |

The theatre is the four bases with at least 150 km around each: Ramon (659,428 E, 3,405,964 N) and Hatzerim (658,381,
3,456,728) set the west edge (−150.5 km), Ramon the south (−150.7 km), Ramat David (704,340, 3,616,248) the east
(+150.7 km) and the north (+150.0 km); Nevatim (691,678, 3,454,398) lies inside all four. In lon / lat it spans about 33.08–36.84°
E and 29.38–34.04° N: the Sinai's north, Jordan to Amman's east, Lebanon to Beirut, Syria to Damascus.

## 3. Detail by area

| level (m per pixel) | where | from |
|---|---|---|
| 1 (2 m) | where a Survey sheet has pixels, off the airbases | the Survey photo over the 8 m node (§4) |
| 2 (4 m) | over the level-1 nodes | their children; a missing child: the 8 m node |
| 3 (8 m) | the detail area, in whole level-5 nodes (32.8 km) | Sentinel-2, bilinear |
| 4 (16 m) | the detail area | the 8 m nodes |
| 5 (32 m) | outside the detail area | Sentinel-2's overviews, averaged |
| 5–11 | everywhere | their children |
| heights 6–11 (64 m … 2 km) | everywhere | GLO-30 averaged to a 64 m grid (the level-6 texel), point-sampled for the coarser levels |

The open sea has no Sentinel-2 pixels away from the coast: it takes one colour (`SEA`, the composite's open-sea tone
near Ashdod, inferred by eye) at the DEM's 0 m.

The renderer draws the ground with one vertex per height texel at levels 0–2, so the drawn surface is GLO-30 at 64 m
(the original's level 6 was 79 m). Finer heights (a level-5 height level, 32 m) are possible later: the shape allows any
`height_level`, but the probe and the weapons' height field would need a check.

## 4. The pipeline

1. **Box**: its lon / lat extent through `gdaltransform`.
2. **Heights**: the GLO-30 tiles over the extent (curl, `-A "iaf-reborn IAF 2026 terrain setup (curl)"`, 4 retries;
   only a missing key, 404 or 403 with `NoSuchKey`, marks a cell as open sea), one VRT,
   one `gdalwarp` to the 64 m UTM grid (average, nodata = 0 m), then the `h_<i>_<j>.png` nodes of levels 6–11 (R = high
   byte, G = low byte, 1025² with the neighbour's first row and column, as `terrain::theatre`).
3. **Sentinel-2**: one VRT over the WorldCover tiles in the extent. Work units: level-7 nodes for the 32 m nodes,
   level-5 nodes for the 8 m nodes; each is one `gdalwarp` to UTM, then `imagery::tone` (the WorldCover layer's
   modern colours) per pixel.
4. **Survey of Israel**: one VRT over the sheets (EPSG:2039, white = no data). Work units: level-4 nodes (16.4 km,
   8192² px at 2 m). Per pixel: the sheet's levels (`imagery::sheet_levels`, haze and exposure, blended across sheet
   borders), then the sheet's colour match to Sentinel-2 (a scale and offset per band from both images' mean and
   spread over the sheet at 40 m, cached in `.work/gains.tsv`), laid over the 8 m node upsampled.
   - **Airbases**: the published Survey photo paints the military bases over with made-up ground (checked at Ramon:
     no runway in sheet SVT). Inside the four bases' OSM outlines and 160 m beyond, with the Survey fading back in
     over the next 160 m, the 8 m Sentinel-2 node shows instead (a 10 m mask: the outline rasterised, grown by 240 m,
     blurred over ± 80 m; a base counts for a unit when its outline's bounding box comes within 340 m).
5. **Coarser levels**: levels 2 and 4–11 from their four children (Triangle filter).
6. **`meta.json`**: the node lists per level, the georeference, `attribution` (§5) and `notice` (the DEM's liability
   sentence).

## 5. Credits the sim must show

The Copernicus WorldDEM-30 licence, Article 6, asks for these lines verbatim with every distribution of modified data
(we ship a converted copy)[^dem-licence]:

- (b) "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018
  provided under COPERNICUS by the European Union and ESA; all rights reserved"
- (c) "The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for
  any use of the Copernicus WorldDEM-30"

With the imagery's lines ("Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium;
ESA WorldCover project 2021 (CC BY 4.0)"; "© Survey of Israel 2015, via data.gov.il") they are `ATTRIBUTION` and
`DEM_LIABILITY` in `crates/iaf-tools/src/sim_terrain.rs` and in the theatre's `meta.json`. The sim's setup wizard
(item A3) lists them on its Attributions page and the credits roll shows them; [docs/credits.md](../../docs/credits.md)
"IAF 2026 data" names them.

## 6. Flying it in the original game

The original game can fly the sim's theatre for a look (screenshots, checks): the environment variable
`IAF_THEATRE=<name>` makes `Settings.theatre_dir()` answer `converted/terrain/<name>`. A theatre whose `meta.json`
has `crs` turns off what belongs to the 1998 frame: the imagery layers, `terraintype.dat` (all ground is land) and
World scale Real's base move. Missions still start at their 1998 positions, so fly free (no mission) with `--at`:

```sh
tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 IAF_THEATRE=israel SHOT_DIR=/tmp/shots SHOT_NAME=ramon \
    SHOT_LAYERS=original SHOT_ORBIT=180,8,45 -- --log-file /tmp/shot.log --path iaf-reborn --resolution 1600x900 \
    -s ../tests/godot/_imagery_shot.gd -- --at 655800 3402500 930 55 -4 --freeze
```

In the sim (`iaf-2026/sim_settings.gd`) `theatre_dir()` is always `converted/terrain/israel`. The M0 probe
(`iaf-2026/tests/test_m0_boot.gd`) flies 5 s over the theatre's centre and checks the heights at the jet and that it
is above them.

## 7. Sizes and times

Measured on this Linux laptop (8 threads, `nice -n 15`, 4 workers), 2026-11-03.

| run | DEM tiles | output | time |
|---|---|---|---|
| 60 km box around Ramon (`--box 628736 3375104 690176 3436544`) | 2 tiles, 72 MB | 302 MB (L1 816 nodes, L2 206, L3 64) | 9 min (heights 14 s, 8 m nodes 1 min, colour match 4 min, Survey 4 min) |
| the theatre (§2) | 21 tiles, 627 MB (the other 3 cells are open sea) | 3.57 GB: L1 7,266 nodes, L2 1,894, L3 1,320, L4 336, L5 176, L6 48 colour + 48 height, L7–L11 19 + 19 | 1 h 42 min: DEM 2 min, Sentinel-2 21 min (32 m 9 units, 8 m 84 units; network-bound), colour match of 102 sheets 7 min, Survey 166 units 68 min, coarser levels and `meta.json` 3 min |

The full build ran in three goes (a reset connection during the DEM download and two colour-match bugs, fixed in
the same change); the times above add up the parts. The disk had 23 GB free before and needs the output plus the DEM
cache (≈ 4.2 GB) and up to 1 GB of temporary rasters in `.work/` while it runs.

## 8. Checks

- `cargo test -p iaf-tools --lib sim_terrain`: the tile writer on a box of two level-6 nodes (height encoding, shared
  node edges, the east edge, level 7, the parents up to level 11, `meta.json`), the DEM reader on a synthetic lon / lat
  grid (the 64 m grid's values against `gdaltransform`), the tile names.
- The M0 probe's terrain checks (§6).
- The pictures over Ramon at 500 m and 5,000 m beside the satellite picture ("IAF 2026 Progress" page).

## 9. Why the desert renders pale

The in-game desert over Ramon is much paler than the satellite picture. Measured 2026-11-03 on a 4 × 4 km square of
open desert south-west of the base (UTM 652–656 km E, 3,398–3,402 km N), mean RGB:

| what | R | G | B |
|---|---|---|---|
| the written tiles: 2 m Survey (L1) / 8 m Sentinel-2 (L3) | 242 / 246 | 209 / 212 | 167 / 171 |
| the Sentinel-2 composite there, cut with GDAL (the same tone without its saturation step) | 243 | 212 | 176 |
| the rendered ground (500 m shot, the lower half of the frame) | 203 | 192 | 183 |
| the same spot in the original game's 1998 theatre, same renderer and settings | 182 | 180 | 186 |
| the same spot with the Survey layer `mapi2015_modern` in the 1998 frame | 93 | 98 | 103 |

The tiles hold the satellite's colours, so the colour match is right. The renderer takes the colour out: the haze and
the light of the shared terrain shader turn bright sand toward the sky's grey-white, and the 1998 art at the same spot
renders even paler. That belongs to the renderer's look (`shared/terrain/terrain.gdshader`, the sky and fog), not to
the terrain data; the pictures (`pale500` in the progress page's B1 section) set the three side by side.

## 10. Open

- **Other censored sites**: the Survey photo also paints over military sites other than the four bases; there the
  made-up ground shows (open: no list of them).
- **Survey and Sentinel-2 look**: the per-sheet colour match leaves the 2 m photo crisper and a little lighter than
  the 8 m nodes around it; the step shows at an airbase outline and at the coverage's edge.
- **Surface types**: the theatre has no `terraintype.dat` yet (water, runways): B2b.
- **Heights at 64 m**: §3.

[^dem]: ESA, "Copernicus DEM: Product Handbook" and the collection description, https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM
[^dem-licence]: "Licence for the use of the Copernicus WorldDEM-30", Article 6, read 2026-11-02, https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf
[^dem-aws]: Registry of Open Data on AWS, "Copernicus Digital Elevation Model (DEM)", https://registry.opendata.aws/copernicus-dem/
[^wc]: ESA WorldCover 2021 Sentinel-2 RGBNIR composite, "Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium" (CC BY 4.0), https://esa-worldcover.org
[^soi]: Survey of Israel, orthophoto 2015, 2 m, via data.gov.il (docs/imagery-sources.md §2.1)
[^osm]: OpenStreetMap contributors, ODbL 1.0, https://www.openstreetmap.org/copyright
