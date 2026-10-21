# Better terrain imagery / elevation — research

This doc is the research for better satellite imagery: an optional modern imagery layer (and maybe elevation) that
the user downloads, drawn over the 1998 map.ptt photos behind an opt-in switch, with the original as the default. Key facts:

- Checked 2026-09-30; licences quoted from the providers' own pages / capabilities.
- Built from it: the georeference (docs/georef.md) and the Sentinel-2 and Survey of Israel layers (docs/imagery.md).
  §4 says, per part, what was built and where it is described.
- Open: the elevation part (§4.5; docs/roadmap.md "Modern DEM").
- Recommendation: ESA WorldCover Sentinel-2 2021 as the imagery base, Copernicus DEM GLO-30 for elevation, the
  original always on top (§4). The follow-up licence survey for sharper sources is docs/imagery-sources.md.

Terms used below:

- **ESA**: the European Space Agency. **DEM**: digital elevation model. **DSM**: digital surface model (a DEM that
  includes buildings and trees).
- **COG**: Cloud-Optimised GeoTIFF, a GeoTIFF a client can read in parts over HTTP. **WMTS**: Web Map Tile Service, a
  standard tile server protocol. **XYZ tiles**: slippy-map tiles addressed by zoom / x / y.
- **GCP**: ground control point. **TPS**: thin-plate spline. **OSM**: OpenStreetMap.
- **UTM**: Universal Transverse Mercator; **ITM**: the Israeli Transverse Mercator grid.
- **Ln**: quadtree level n of the terrain (L0 finest, §3 lists the pixel sizes).

## 1. The theatre in geographic terms (prerequisite)

Every modern source is in lat/lon (EPSG:4326) or Web Mercator (EPSG:3857), so the game frame needs a lat/lon
georeference first. The frame is the original's planar one: terrain units `tx, ty` (docs/formats/ptt.md), engine
metres `X = tx·1.2411389 − 166850`, `Y = 1043780 − ty·1.2411389`.

**First cut.** A least-squares fit to 5 hand-picked control points on the L8/L10 nodes (±1–2 km picking error): Eilat
gulf head, Suez gulf head, Ramat David runway from takeoff.mis, Cape Andreas, Cape Arnauti.

| model | rms | max |
|---|---|---|
| affine in (lon, lat) — plate carrée | **3.2 km** | 4.8 km |
| similarity on UTM 36N / any transverse Mercator (lon0 33..36) | 4.9 km | 8.5 km |

What the fit shows:

- The affine fit has 96.10 km per degree of longitude (= plate carrée at ~30.3° N) and 110.0 km per degree of
  latitude. So **the 1998 mosaic looks like a geographic (lat/lon) raster**, rather than UTM / ITM.
- Theatre corners under that fit: NW 36.62 N 29.77 E, NE 36.70 N 38.24 E, SW 27.01 N 29.79 E, SE 27.09 N 38.26 E
  (813 × 1057 km; includes NW Saudi Arabia in the south-east corner). docs/georef.md §2 starts its first pass from
  this fit.
- The kilometre residuals are partly picking error and partly the old mosaic's own local distortion. So the real
  georeference must be a **dense control-point warp**; a single formula is too coarse.

**Built** (docs/georef.md): a smoothed thin-plate spline fitted to 610 control points found automatically (patch
correlation against EOxCloudless 2017). The direction is the one planned here: **the modern imagery is warped into
the game's frame**, never the game into the real world, so missions, insets, terraintype.dat (water = crash, runway
polygons) and the heights stay where the 1998 data put them. The airbases turned out unfit as control points
(georef.md §4).

## 2. The friend's projects (github.com/ziv, github.com/opentiles)

Summary: godotiles is a full real-world terrain streamer, too different from our frame to be our terrain, but its
fetch + cache code, Terrarium decoding and normal-map lighting are worth reusing.

Relevant repos (the rest of github.com/ziv is web / Angular / Node tooling):

| repo | what | licence |
|---|---|---|
| **ziv/godotiles** (Rust GDExtension, Godot 4.4+, dev on 4.7) | streams real-world terrain: slippy-map XYZ tiles, quadtree LOD z9–22, Terrarium heightmaps (vertex displacement) + normal maps, worker-thread HTTP with a resumable on-disk cache `cache/{texture,heightmap,normals}/z/x/y.png`, heightmap synthesis above the provider's zoom, `ground_height()` queries, large-world rebasing, pre-warm script `scripts/tiles-cache.mjs` | MIT OR Apache-2.0 |
| ziv/raytiles (C++/raylib), ziv/bevytiles (Bevy), ziv/threetiles (three.js) | the same engine in other hosts (shared LOD policy, cache layout, tests) | MIT / Apache-2.0 |
| **opentiles/opentiles-server** (Rust) | on-demand 3D terrain tiles as GLB (`/z/x/y.glb` + JSON metadata: height range, measured geometric error), built from the same providers, cached (disk / S3), spec in `specs.md` | MIT OR Apache-2.0 |
| opentiles/opentiles-threejs | three.js client for the server (screen-space-error quadtree) | MIT OR Apache-2.0 |
| ziv/hot-tail, airborne, airborne-rs | jet games (web arcade; MicroProse remake): no terrain data pipeline to reuse | — |

**Can godotiles be the terrain?** Not as a drop-in:

- **Frame**: it lives in Web Mercator, anchored at one lat/lon with a single metres-per-tile scale. Over our 27°–37° N
  theatre the Mercator scale changes by ~12 %, so airbase distances would drift by tens of km against the original
  frame, where our missions, insets, terraintype polygons and physics heights live.
- **Providers**: its default imagery providers are closed to us: Esri World Imagery and Mapbox forbid bulk download
  and offline caching (docs/imagery-sources.md §3). The Terrarium elevation default (AWS Open Data) is fine.
- **Duplication**: it would be a second terrain renderer next to ours (ptt quadtree, FUN_004281e0 heights, skirts,
  inset precedence, runway fixes, surface types).

**Worth reusing (licences are GPL-3-compatible; keep their notices):**

- The **fetch + cache pattern** (`rust/src/core/source/native.rs`): worker threads, blocking `ureq`, `:zoom:/:x:/:y:`
  URL templates, atomic write-through cache, resumable. It fits a setup-time downloader for XYZ / WMTS sources; the
  COG sources below want HTTP range reads.
- **Terrarium decode / carry-safe re-encode / quadrant upsampling** (`synth.rs`, `height.rs`) if we take the AWS
  Terrarium DEM (§3), and the rule "never interpolate Terrarium RGB per channel".
- The **normal-map lighting** idea from `terrain.gdshader` (sun · normal from a DEM-derived normal texture) for
  relief shading on top of our heights (§4.5).
- Maybe later: opentiles-server's **measured geometric error** per tile, for our split rule.
- Feedback for ziv: a `file://` / local-mosaic provider would let godotiles use offline data, and the Esri default
  deserves a licence note.

**Plug-in point on our side** (built this way): the converter writes our own node layout (`L<L>/c_<i>_<j>.jpg`,
1024², `2^L` units per pixel) in the game frame, using the georeference to map each node pixel to lat/lon. The runtime
only chooses a directory per node. Web Mercator stays out of the game.

## 3. Sources

The theatre is ≈ 860 000 km², of which roughly 30 % is sea (kept from the original anyway).

Our levels, in metres per pixel: L0 1.24 m, L1 2.5 m, L2 5.0 m, L3 9.9 m, L4 19.9 m, L5 39.7 m, L6 79.4 m.

What the original covers at each level:

- L6 everywhere;
- L5/L4 over Israel, Lebanon, southern Syria, northern Jordan and the Nile delta–Suez;
- L3 bands over Israel;
- L2..L0 at ~20 airbases/targets.

### Imagery

Recommended base: the ESA WorldCover Sentinel-2 2021 composite. Abbreviations in the table: S2 = Sentinel-2; STAC =
SpatioTemporal Asset Catalog; CDSE = Copernicus Data Space Ecosystem; MGRS = Military Grid Reference System; TCI =
true-colour image; GIBS = NASA's Global Imagery Browse Services.

| source | res. | coverage / date | licence | access | theatre size | verdict |
|---|---|---|---|---|---|---|
| **ESA WorldCover S2 RGBNIR composite 2021** (VITO) | 10 m (0.3″), 4 bands u16 | global land, yearly median 2020/2021, seamless | **CC BY 4.0** | AWS `s3://esa-worldcover-s2/rgbnir/2021/` (no account, HTTPS), 1°×1° COGs in EPSG:4326 with overviews (12000² → 750²) | **83 tiles, 43.5 GB** for 10 m; the 20 m overview ≈ ¼ by range reads | **recommended base** (built: `sentinel2`) |
| EOxCloudless (Sentinel-2 cloudless) **2016, 2017** | 10 m | global, colour-balanced, very clean | **CC BY 4.0** (per the WMTS capabilities) | WMTS `tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2017_3857/default/g/{z}/{y}/{x}.jpg` (also EPSG:4326 layers) | z14 ≈ 200 k JPEG tiles ≈ 4 GB | good alternative; bulk harvesting a free WMTS should be agreed with EOX / throttled (used at z9 / z10 for the georeference) |
| EOxCloudless **2018–2025** | 10 m | global | **CC BY-NC-SA 4.0** (commercial licence from EOX) | same WMTS | same | the licence keeps it out of a GPL distribution; skip |
| Copernicus Sentinel-2 L2A (scenes) | 10 m | 5-day revisit, 2017– | Copernicus free, full and open ("Contains modified Copernicus Sentinel data YYYY") | AWS Element84 COGs / STAC (no account), CDSE (account) | ~100 MGRS tiles × TCI 100–200 MB ≈ 15 GB for one pass | more work: scene choice, seams between dates; the WorldCover composite already did it |
| CDSE Sentinel-2 quarterly cloudless mosaics | 10 m (global product 20 m) | 2023+ | Copernicus open | CDSE STAC/OData/Sentinel Hub (account) | similar | possible later (newer year) |
| Landsat 5/7/8/9 (USGS Collection 2) | 30 m (15 m pan) | 1984– | **public domain** | EarthExplorer (free account), Microsoft Planetary Computer (free), AWS (requester pays) | ~10 GB per pass | a **period-correct "1998" option** (Landsat 5 TM 1997–98: only the towns that stood by 1998), coarser, needs scene mosaicking |
| NASA Blue Marble NG / GIBS (MODIS/VIIRS) | 500 m / 250 m | global | NASA open, no restrictions | GIBS WMTS, direct files | tens of MB | only for a horizon ring outside the theatre |
| Esri World Imagery, Google, Bing, Mapbox | sub-metre | — | no offline / bulk use | — | — | **not usable** (imagery-sources.md §3) |
| Survey of Israel / govmap orthophoto | ~0.25–0.5 m | Israel | © State of Israel, use needs the Survey director's permission | govmap viewer | — | usable only with written permission (the open 2 m set: imagery-sources.md §2.1) |

**Sample check** (scratchpad, not committed): EOX 2016 and 2025 z13 tiles over Ramat David, and the 750² overview of
the WorldCover N32E034 COG.

- WorldCover is u16 reflectance ×10⁴ (R, G, B, NIR order, nodata 0 over open sea). It needs a tone curve (≈ ×0.07 →
  8 bit plus gamma) and comes out darker / greyer than EOX's balanced mosaic.
- EOX 2016 is bright and hazy, 2025 dark and saturated.
- **The original L4 over Israel (19.9 m) is sharp, aerial-looking and at least as good as 10 m Sentinel-2 at that
  scale.** The big win is outside the insets, where the original has only L6 (79 m): Sinai, Egypt, Jordan, Syria,
  Lebanon's east, Cyprus, the Saudi corner. S2 is 8× finer there.

### Elevation

Recommended: Copernicus DEM GLO-30. SRTM = NASA's Shuttle Radar Topography Mission; JAXA = the Japan Aerospace
Exploration Agency.

| source | res. | licence | access | theatre size | notes |
|---|---|---|---|---|---|
| **Copernicus DEM GLO-30** | 30 m | Copernicus DEM licence: free, redistribution allowed with attribution (Armenia/Azerbaijan excluded, outside our theatre) | AWS `copernicus-dem-30m` COGs, 1° tiles (no account); N32E035 = 44 MB | ~2.5–3.5 GB | DSM (buildings/trees); best quality; **recommended** |
| Copernicus DEM GLO-90 | 90 m | same | `copernicus-dem-90m`; N32E035 = 5.4 MB | ~0.4 GB | ≈ our L6 heights (79 m): little gain |
| SRTM 1″ (NASA) | 30 m | public domain | EarthData (account), OpenTopography | ~3 GB | voids in steep terrain; GLO-30 is better |
| ALOS AW3D30 (JAXA) | 30 m | free with credit | JAXA portal (account) | ~3 GB | alternative to GLO-30 |
| Mapzen/Tilezen Terrarium (AWS Open Data) | z≤15 (~30 m here, SRTM/GMTED/ETOPO mix) | open, attribution list | XYZ PNGs, no account (godotiles' default) | z12 ≈ 1 GB | easiest (godotiles code applies); has bathymetry (we keep the original sea) |

### Detail layers

Two extra open datasets help with masks and control points:

- **ESA WorldCover 2021 land cover** (10 m, CC BY 4.0, same bucket family): water / built-up / cropland masks for
  colour matching per class, and later for a texture-splat detail layer at L0..L2.
- **OpenStreetMap** (ODbL, the Open Database License):
  - Licence: rendered imagery may be any licence with "© OpenStreetMap contributors"; a derived *database* must stay
    ODbL. Fine for a user-side download.
  - Use: `aeroway=runway` ways for runway checks (used in imagery.md §9 and world-scale.md §1.2); roads / rivers as
    an optional low-altitude overlay.
  - Access: Geofabrik extracts (Israel-Palestine, Egypt, Jordan, Lebanon, Syria, Cyprus; clip Saudi Arabia), a few
    hundred MB; or an Overpass query for just runways (small).

## 4. Plan, and what was built

The plan: modern colour nodes on land, in a 1998 palette by default, with the original winning where it has detail;
gameplay heights unchanged.

### 4.1 Levels and precedence

Planned:

- **Base**: ESA WorldCover S2 2021 composite (CC BY 4.0, seamless, open bucket, already EPSG:4326 like the
  original). EOX 2017 (CC BY) as an alternative source if its bulk use is agreed.
- New colour nodes at L3..L6 on land outside the original insets.
- **The original wins**: the L0..L2 airbase insets stay untouched (they are sharper, carry the runway fixes and match
  the mission objects); over the L4–L5 insets the original stays by default (1998 vs 2021 towns differ).
- **Sea**: the original sea wherever terraintype.dat says water (0x2/0x4 bits), so the drawn coast matches the
  gameplay water polygons (water = crash); modern pixels only on land.

Built (imagery.md §3): one layer per region. Outside Israel, Sentinel-2 at L3. In Israel, the Survey of Israel 2 m at
L1, which also replaces the original's L3 regional cover. Airbases keep only their footprint, target sites their
inset. Sea: source water near terraintype.dat's water stays the original's.

### 4.2 Colour matching

Planned: two looks.

- **1998 palette** (detail transfer): `out = S2 · blur(orig) / blur(S2)` with the blur at L8-ish scale
  (~300 m–1 km). It keeps the 1998 overall colour and adds the 10 m detail, and inset borders need little
  feathering. Ratios per land-cover class (WorldCover) would keep fields from tinting towns.
- **Modern colours**: a global tone curve only (reflectance → sRGB, gamma ≈ 2.2, slight saturation), with the insets
  histogram-matched *to it* at their borders.

Built (imagery.md §4): both looks, as separate layers, so the player picks the look; the ratio uses ≈ 500 m local
means over land pixels, without per-class ratios.

### 4.3 Seams

Planned: nodes composed coarse to fine (4-pixel margins, Lanczos to the node lattice), so neighbours match; a 300–500 m feather inside the inset edge;
mipmaps / BC1 per node as today. Built: imagery.md §2 step 4 and §3 (240 m / 120 m feathers).

### 4.4 Airbases, runways, mission objects

Planned: the L0..L2 airbase insets untouched; at the bases only in L3+ (Egypt, Jordan, Syria, Lebanon, Saudi) the
georeference would use the OSM runways as control points so the painted runway sits under the mission's airbase.

Found instead: the game's bases lie kilometres from the real ones by design (georef.md §4), so the layers keep the
original at every game base, and the bases cannot be moved onto real imagery (imagery.md §9).

### 4.5 Elevation (open)

- **Gameplay heights stay the original**: missions place objects at data heights, terraintype and runways, physics
  `height_at` = the drawn surface; "no elevation west of Suez" and the −557 m plane are kept, as in deviations.md.
- Phase 1 (safe, most of the visual gain): a **normal map from Copernicus GLO-30** per L3..L6 node (the godotiles
  lighting idea). Ridges and wadis are shaded at 30 m on top of the 79 m geometry; positions stay the same.
  Estimate: ~3 GB download, ~0.3–0.5 GB of normal nodes; 2–3 days.
- Phase 2 (a separate opt-in switch "Modern relief"): replace L3+ geometry with GLO-30, blended to the original within
  ~2 km of airbases / mission ground objects; snap ground objects to the surface; keep runways flat. Physics follows
  the drawn surface, so this changes gameplay slightly, hence opt-in. Estimate: 3–5 days.
- docs/graphics-research.md §3.3 rates the option against the other graphics work.

### 4.6 Setup step, disk, runtime switch

Built as `tools/setup-cli.sh --imagery <source>` → `iaf-imagery` (GDAL as a setup dependency, COG range reads through
`/vsicurl/`), layers in `assets/converted/imagery/<id>/` with a manifest that carries the attribution (imagery.md §2,
§7). Nothing is committed; the user downloads the data. Disk: imagery.md §7 and §8 (measured).

Runtime (imagery.md §5): Graphics → MORE "Imagery Israel" / "Imagery outside Israel"; terrain.gd takes a node's
colour from the picked layer when the layer has it. Geometry already splits to L2 everywhere (`GEOM_MIN_LEVEL`), and
heights are untouched. The credits roll the attribution: "Contains modified Copernicus Sentinel data 2021; ESA
WorldCover project / VITO (CC BY 4.0)" (+ Copernicus DEM and OSM when used).

### 4.7 Open questions

Answered by the build: both looks are offered (§4.2); the Israel layer replaces the L3 cover but not the site insets
(§4.1); WorldCover 2021 over EOX 2017; GDAL as the setup dependency.

Still open: the period-correct Landsat-1998 variant as a later option (imagery-sources.md §5 also lists SPOT 2/4).
