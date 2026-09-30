# Better terrain imagery / elevation — research (Extras option)

Research for the roadmap item "Better satellite imagery" (docs/roadmap.md): an optional, user-downloaded modern
imagery (and maybe elevation) layer over the 1998 map.ptt photos, behind an Extras switch, original by default.
Nothing here is implemented yet. Checked 2026-09-30; licences quoted from the providers' own pages / capabilities.

## 1. The theatre in geographic terms (prerequisite)

Our world is the original's planar frame: terrain units `tx, ty` (docs/formats/ptt.md), engine metres
`X = tx·1.2411389 − 166850`, `Y = 1043780 − ty·1.2411389`. **There is no lat/lon georeference yet**, and every
modern source is in lat/lon (EPSG:4326) or Web Mercator (EPSG:3857), so this is step 0.

First cut (5 hand-picked control points on the L8/L10 nodes, ±1–2 km picking error: Eilat gulf head, Suez gulf
head, Ramat David runway from takeoff.mis, Cape Andreas, Cape Arnauti), least squares:

| model | rms | max |
|---|---|---|
| affine in (lon, lat) — plate carrée | **3.2 km** | 4.8 km |
| similarity on UTM 36N / any transverse Mercator (lon0 33..36) | 4.9 km | 8.5 km |

The affine fit has 96.10 km per degree of longitude (= plate carrée at ~30.3° N) and 110.0 km per degree of
latitude, i.e. **the 1998 mosaic looks like a geographic (lat/lon) raster**, not UTM / ITM. Theatre corners
under that fit: NW 36.62 N 29.77 E, NE 36.70 N 38.24 E, SW 27.01 N 29.79 E, SE 27.09 N 38.26 E
(813 × 1057 km; includes NW Saudi Arabia in the south-east corner). The kilometre residuals are partly picking error
and partly the old mosaic's own local distortion, so the real georeference must be a **dense control-point warp**,
not a formula:

- Control points: runway ends (OSM `aeroway=runway`) against the runway ends already surveyed in the insets
  (ptt.md runway table) and the airbase objects in the missions; coastline / lake / canal features against the
  L6..L4 nodes; plus automatic ones (phase correlation of the downsampled modern image against the 1998 nodes per
  ~20 km cell).
- Model: thin-plate spline (or a piecewise-affine mesh) from (lon, lat) to terrain units; target residual below a
  pixel of the level it feeds (L3 = 9.9 m near airbases, a few tens of m elsewhere).
- Direction: **warp the modern imagery into the game's frame**, never the game into the real world. Missions,
  airbase insets, terraintype.dat (water = crash, runway polygons) and the heights all stay where the 1998 data
  put them; the new pixels are rubber-sheeted onto them.
- Output: `georef.json` next to meta.json (GCP list + residuals), and a small `iaf_tools::georef` module; also
  useful for a lat/lon readout, the TSD, and the roadmap's modern-map option.

## 2. The friend's projects (github.com/ziv, github.com/opentiles)

Relevant repos (the rest of github.com/ziv is web / Angular / Node tooling):

| repo | what | licence |
|---|---|---|
| **ziv/godotiles** (Rust GDExtension, Godot 4.4+, dev on 4.7) | streams real-world terrain: slippy-map XYZ tiles, quadtree LOD z9–22, Terrarium heightmaps (vertex displacement) + normal maps, worker-thread HTTP with a resumable on-disk cache `cache/{texture,heightmap,normals}/z/x/y.png`, heightmap synthesis above the provider's zoom, `ground_height()` queries, large-world rebasing, pre-warm script `scripts/tiles-cache.mjs` | MIT OR Apache-2.0 |
| ziv/raytiles (C++/raylib), ziv/bevytiles (Bevy), ziv/threetiles (three.js) | the same engine in other hosts (shared LOD policy, cache layout, tests) | MIT / Apache-2.0 |
| **opentiles/opentiles-server** (Rust) | on-demand 3D terrain tiles as GLB (`/z/x/y.glb` + JSON metadata: height range, measured geometric error), built from the same providers, cached (disk / S3), spec in `specs.md` | MIT OR Apache-2.0 |
| opentiles/opentiles-threejs | three.js client for the server (screen-space-error quadtree) | MIT OR Apache-2.0 |
| ziv/hot-tail, airborne, airborne-rs | jet games (web arcade; MicroProse remake) — no terrain data pipeline to reuse | — |

**Can we use godotiles directly as the terrain?** No, not as a drop-in:
- It lives in Web Mercator anchored at one lat/lon with a single metres-per-tile scale. Over our 27°–37° N
  theatre the Mercator scale changes by ~12 %, so airbase distances would drift by tens of km against the
  original frame; our missions, insets, terraintype polygons and physics heights are all in the 1998 planar frame.
- Its default providers can't be used by us: **Esri World Imagery** does not allow bulk download / offline caching
  without an ArcGIS licence (and Mapbox needs a token with similar terms). The Terrarium elevation default (AWS
  Open Data) is fine.
- It would be a second terrain renderer next to ours (ptt quadtree, FUN_004281e0 heights, skirts, inset
  precedence, runway fixes, surface types).

**What is worth reusing (licences are GPL-3-compatible; keep their notices):**
- The **fetch + cache pattern** (`rust/src/core/source/native.rs`): worker threads, blocking `ureq`, `:zoom:/:x:/:y:`
  URL templates, atomic write-through cache, resumable. Exactly what a setup-time downloader in `iaf-tools`
  needs (for XYZ/WMTS sources; the COG sources below want HTTP range reads instead).
- **Terrarium decode / carry-safe re-encode / quadrant upsampling** (`synth.rs`, `height.rs`) if we take the AWS
  Terrarium DEM (§3), and the rule "never interpolate Terrarium RGB per channel".
- The **normal-map lighting** idea from `terrain.gdshader` (sun · normal from a DEM-derived normal texture) for
  relief shading on top of our heights (§4.5).
- opentiles-server's **measured geometric error** per tile is a nice idea for our split rule later; not needed now.
- Conversely, useful feedback for ziv: a `file://` / local-mosaic provider would let godotiles use offline data,
  and the Esri default deserves a licence note.

Plug-in point on our side: the downloader/converter produces our own node layout (`L<L>/c_<i>_<j>.jpg`, 1024²,
`2^L` units per pixel) in the game frame, using the georeference of §1 to map each node pixel to lat/lon. The
runtime then only chooses a directory (§4.6). No Web Mercator anywhere in the game.

## 3. Sources

Theatre ≈ 860 000 km², of which roughly 30 % sea (kept from the original anyway). Our levels: L0 1.24 m, L1 2.5 m,
L2 5.0 m, L3 9.9 m, L4 19.9 m, L5 39.7 m, L6 79.4 m per pixel. The original has L6 everywhere, L5/L4 over
Israel, Lebanon, southern Syria, northern Jordan and the Nile delta–Suez, L3 bands over Israel, L2..L0 at ~20
airbases/targets.

### Imagery

| source | res. | coverage / date | licence | access | theatre size | verdict |
|---|---|---|---|---|---|---|
| **ESA WorldCover S2 RGBNIR composite 2021** (VITO) | 10 m (0.3″), 4 bands u16 | global land, yearly median 2020/2021, seamless | **CC BY 4.0** | AWS `s3://esa-worldcover-s2/rgbnir/2021/` (no account, HTTPS), 1°×1° COGs in EPSG:4326 with overviews (12000² → 750²) | **83 tiles, 43.5 GB** for 10 m; the 20 m overview ≈ ¼ by range reads | **recommended base** |
| EOxCloudless (Sentinel-2 cloudless) **2016, 2017** | 10 m | global, colour-balanced, very clean | **CC BY 4.0** (per the WMTS capabilities) | WMTS `tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2017_3857/default/g/{z}/{y}/{x}.jpg` (also EPSG:4326 layers) | z14 ≈ 200 k JPEG tiles ≈ 4 GB | good alternative; bulk harvesting a free WMTS should be agreed with EOX / throttled |
| EOxCloudless **2018–2025** | 10 m | global | **CC BY-NC-SA 4.0** (commercial licence from EOX) | same WMTS | same | only as "user's own personal download"; can't become part of a GPL distribution; skip |
| Copernicus Sentinel-2 L2A (scenes) | 10 m | 5-day revisit, 2017– | Copernicus free, full and open ("Contains modified Copernicus Sentinel data YYYY") | AWS Element84 COGs / STAC (no account), CDSE (account) | ~100 MGRS tiles × TCI 100–200 MB ≈ 15 GB for one pass | more work: scene choice, seams between dates; the WorldCover composite already did it |
| CDSE Sentinel-2 quarterly cloudless mosaics | 10 m (global product 20 m) | 2023+ | Copernicus open | CDSE STAC/OData/Sentinel Hub (account) | similar | possible later (newer year) |
| Landsat 5/7/8/9 (USGS Collection 2) | 30 m (15 m pan) | 1984– | **public domain** | EarthExplorer (free account), Microsoft Planetary Computer (free), AWS (requester pays) | ~10 GB per pass | fun **period-correct "1998" option** (Landsat 5 TM 1997–98: no post-1998 towns), coarser, needs scene mosaicking |
| NASA Blue Marble NG / GIBS (MODIS/VIIRS) | 500 m / 250 m | global | NASA open, no restrictions | GIBS WMTS, direct files | tens of MB | only for a horizon ring outside the theatre |
| Esri World Imagery, Google, Bing, Mapbox | sub-metre | — | no offline / bulk use | — | — | **not usable** |
| Survey of Israel / govmap orthophoto | ~0.25–0.5 m | Israel | © State of Israel, use needs the Survey director's permission | govmap viewer | — | not usable without written permission (could ask) |

Sample check (scratchpad, not committed): EOX 2016 and 2025 z13 tiles over Ramat David, and the 750² overview of
the WorldCover N32E034 COG. WorldCover is u16 reflectance ×10⁴ (R, G, B, NIR order, nodata 0 over open sea);
it needs a tone curve (≈ ×0.07 → 8 bit plus gamma) and comes out darker / greyer than EOX's balanced mosaic.
EOX 2016 is bright and hazy, 2025 dark and saturated. **The original L4 over Israel (19.9 m) is sharp, aerial-looking
and at least as good as 10 m Sentinel-2 at that scale** — the big win is outside the insets, where the original
has only L6 (79 m): Sinai, Egypt, Jordan, Syria, Lebanon's east, Cyprus, Saudi corner — 8× finer with S2.

### Elevation

| source | res. | licence | access | theatre size | notes |
|---|---|---|---|---|---|
| **Copernicus DEM GLO-30** | 30 m | Copernicus DEM licence: free, redistribution allowed with attribution (Armenia/Azerbaijan excluded, not ours) | AWS `copernicus-dem-30m` COGs, 1° tiles (no account); N32E035 = 44 MB | ~2.5–3.5 GB | DSM (buildings/trees); best quality; **recommended** |
| Copernicus DEM GLO-90 | 90 m | same | `copernicus-dem-90m`; N32E035 = 5.4 MB | ~0.4 GB | ≈ our L6 heights (79 m) — little gain |
| SRTM 1″ (NASA) | 30 m | public domain | EarthData (account), OpenTopography | ~3 GB | voids in steep terrain; GLO-30 is better |
| ALOS AW3D30 (JAXA) | 30 m | free with credit | JAXA portal (account) | ~3 GB | alternative to GLO-30 |
| Mapzen/Tilezen Terrarium (AWS Open Data) | z≤15 (~30 m here, SRTM/GMTED/ETOPO mix) | open, attribution list | XYZ PNGs, no account (godotiles' default) | z12 ≈ 1 GB | easiest (godotiles code applies); has bathymetry (we keep the original sea) |

### Detail layers

- **ESA WorldCover 2021 land cover** (10 m, CC BY 4.0, same bucket family): water / built-up / cropland masks for
  colour matching per class, and for a texture-splat detail layer at L0..L2 later.
- **OpenStreetMap** (ODbL; rendered imagery may be any licence with "© OpenStreetMap contributors", a derived
  *database* must stay ODbL — fine for a user-side download): `aeroway=runway` polygons for the georeference
  control points and runway alignment; roads / rivers as an optional low-altitude overlay. Geofabrik extracts
  (Israel-Palestine, Egypt, Jordan, Lebanon, Syria, Cyprus; clip Saudi Arabia) — a few hundred MB, or an
  Overpass query for just runways (small).

## 4. Recommended plan

### 4.1 Levels and precedence
- **Base**: ESA WorldCover S2 2021 composite (CC BY 4.0, seamless, open bucket, already EPSG:4326 like the
  original). EOX 2017 (CC BY) as an alternative source flag if its bulk use is agreed.
- New colour nodes at **L3..L6 everywhere on land outside the original insets** ("modern" pack), L4 as the
  finest level in the "medium" pack.
- **The original always wins**: L0..L2 airbase insets untouched (they are sharper, carry the runway fixes and
  match the mission objects); over the Israel/Lebanon/Syria/Jordan/delta L4–L5 insets the original stays by
  default (optional "modern everywhere" sub-choice, since 1998 vs 2021 towns differ).
- **Sea**: original sea colour wherever terraintype.dat says water (0x2/0x4 bits), so the drawn coast matches
  the gameplay water polygons (water = crash); modern pixels only on land.

### 4.2 Colour matching
Two looks, picked at conversion time (default "1998 palette"):
- **1998 palette** (detail transfer): `out = S2 · blur(orig) / blur(S2)` with the blur at L8-ish scale
  (~300 m–1 km). Keeps the 1998 overall colour, adds the 10 m detail; switching the option does not change the
  mood, and inset borders need little feathering. Per land-cover class ratios (WorldCover) avoid tinting
  towns from fields.
- **Modern colours**: a global tone curve only (reflectance → sRGB, gamma ≈ 2.2, slight saturation), with the
  insets histogram-matched *to it* at their borders.

### 4.3 Seams
- Converter composes a node the same way as today (coarse to fine, 4-pixel margins, Lanczos to the node lattice)
  so neighbours match exactly.
- Inset borders: 300–500 m linear feather from modern to original inside the inset edge.
- Mipmaps/BC1 already per node; no runtime change.

### 4.4 Airbases, runways, mission objects
- Airbases in the L0..L2 insets: untouched (original imagery = original object positions).
- Airbases only in L3+ (Egypt, Jordan, Syria, Lebanon, Saudi): modern imagery shows the real runways; the
  georeference warp uses those runways (OSM) as control points against the mission objects / terraintype runway
  polygons, so the painted runway sits under the mission's airbase. Where a 1998 base no longer exists (or
  moved), the mission object wins; list mismatches in the converter report.

### 4.5 Elevation
- **Gameplay heights stay the original** (missions place objects at data heights, terraintype and runways,
  physics `height_at` = the drawn surface; "no elevation west of Suez" and the −557 m plane are kept, as in
  deviations.md).
- Phase 1 (safe, most of the visual gain): a **normal map from Copernicus GLO-30** per L3..L6 node (the
  godotiles lighting idea) — ridges and wadis shaded at 30 m on top of the 79 m geometry; no position changes.
- Phase 2 (optional, separate Extras switch "Modern relief"): replace L3+ geometry with GLO-30 blended to the
  original within ~2 km of airbases / mission ground objects, snap ground objects to the surface, keep runways
  flat. Physics follows the drawn surface, so this changes gameplay slightly — hence opt-in.

### 4.6 Setup step, disk, runtime switch
- `tools/setup.sh --modern-imagery [medium|high]` → `iaf-terrain imagery` (new, in iaf-tools): read the
  georeference, fetch the needed COG windows by HTTP range (resumable cache, the godotiles pattern; or GDAL's
  `/vsicurl/` + `gdalwarp -tps` with the GCPs if we accept GDAL as a documented pacman dependency — simpler), tone
  map / colour-transfer, write `assets/converted/terrain/modern/L<L>/c_<i>_<j>.jpg` + `meta.json` +
  `ATTRIBUTION.txt`. Nothing committed; data is downloaded by the user.
- Download / disk (rough): medium (L4, 20 m): ~11 GB transient download (COG overview 1), **~0.8 GB** on disk;
  high (L3, 10 m): ~43 GB transient (processed per 1° tile and deleted), **~2.5–3 GB** on disk; GLO-30 normals
  ~3 GB download, ~0.3–0.5 GB of normal nodes. (Today's theatre: 732 MB.)
- Runtime: Extras "Terrain imagery: Original / Modern" (+ later "Modern relief"). terrain.gd gets a second data
  dir: a colour node is taken from `modern/` when it exists there and the switch is on, else from `theatre/`
  (`_path()`; `_colour_nodes` gets the modern node list so `_colour_source()` picks them). Geometry already
  splits to L2 everywhere (`GEOM_MIN_LEVEL`), so no split-rule change. Heights untouched. Attribution text in the Extras page / credits:
  "Contains modified Copernicus Sentinel data 2021; ESA WorldCover project / VITO (CC BY 4.0)" (+ Copernicus DEM
  and OSM when used).

### 4.7 Effort (rough)

| step | effort |
|---|---|
| Georeference (GCP picking tool, OSM runways, auto phase-correlation points, TPS fit, georef.json, docs) | 2–3 days |
| `iaf-terrain imagery` downloader + converter (COG range reads or GDAL, node composition, sea mask, feathering) | 3–5 days |
| Colour transfer (1998 palette / modern), tuning against the insets | 2–3 days |
| Runtime switch, second data dir, attribution, setup.sh / README | ~1 day |
| **Imagery total** | **~1.5–2 weeks** |
| DEM normal maps (phase 1) | 2–3 days |
| Modern relief geometry (phase 2, object snapping, runway flattening) | 3–5 days |

Open questions for the user: default look (1998 palette vs modern colours); whether modern imagery may replace the
Israel L4/L5 insets; EOX 2017 vs WorldCover 2021 (ask EOX?); GDAL as a setup dependency vs pure Rust COG reading;
the period-correct Landsat-1998 variant as a later "fun" option.
