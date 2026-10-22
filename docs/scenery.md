# Scenery: buildings and trees

This doc describes the optional scenery: 3D buildings and trees that stand on the terrain over the Survey of Israel
2 m photo (`mapi2015`, docs/imagery.md §8). Key facts:

- It is opt-in. The original has no generic buildings or trees; its stationary models are mission units only.
- Setup makes it from open data downloaded at setup time. The repo holds none of it.
- One cell file per level-1 node of the `mapi2015` layer, the layer's own keys. Scenery stands only where the photo
  shows.
- Nothing stands at an original place: the sea, the airbases, the kept target insets, the missions' units and their
  routes, World scale Real's base sites.
- Related docs: the photo layer in docs/imagery.md §8; the warp into the game frame in docs/georef.md; the cell
  format in `crates/iaf-avionics/src/scenery.rs`.

Terms used below:

- **OSM**: OpenStreetMap.
- **Footprint**: a building's outline on the ground, a polygon.
- **Canopy height**: the height of the tree tops above the ground, per pixel.
- **Quadkey**: the name of a square web-map tile; the Microsoft footprints and the canopy heights come in zoom-9
  tiles (about 70 km).
- **Node**: a square of the game's terrain quadtree. A level-1 node is 2048 terrain units, about 2.5 km.

## 1. Data and setup

### 1.1 Sources

Setup downloads every source into `assets/source/scenery/` and checks it against the SHA-256 pinned in
`crates/iaf-tools/src/thirdparty.rs` (`SCENERY`). The same files give the same scenery on every install.

| Source | What it gives | Files (download) | Licence |
|---|---|---|---|
| OpenStreetMap, Geofabrik's `israel-and-palestine` extract of 2026-01-01[^geofabrik] | buildings with their tags; forests, orchards, fields and settlements; single trees; tree rows | 1 PBF file (119 MB) | ODbL 1.0[^osm] |
| Microsoft Global ML Building Footprints, release 2026-02-03[^ms] | building outlines where OSM has none (Israel, the West Bank, Gaza) | 24 quadkey files (about 300 MB) | CDLA Permissive 2.0[^ms] |
| JRC GHS-BUILT-H R2023A, average net building height (ANBH), 100 m[^ghsl] | the height of a building without a height tag | 2 tiles, R5_C22 and R6_C22 (16 MB) | free re-use with the source acknowledged[^ghsl-terms] |
| Meta and WRI High Resolution Canopy Height Maps, v1, 1 m[^chm] | where trees stand and how tall they are | 17 quadkey tiles (1.2 GB) | CC BY 4.0[^chm] |

Geofabrik keeps the extract of 1 January of each year for good, so the pinned file stays downloadable[^geofabrik].
`iaf-scenery tiles assets` lists the quadkeys the Survey 2 m layer touches: the canopy list holds all of them, the
Microsoft list every Israel, West Bank and Gaza file of its `dataset-links.csv`.

### 1.2 How a cell is made

`iaf-scenery build` (crates/iaf-tools/src/scenery.rs) works in four stages:

1. **Coverage**: the level-1 nodes of the `mapi2015` layer (`assets/converted/imagery/mapi2015/L1/c_<i>_<j>.jpg`)
   and their box in longitude and latitude.
2. **Sources**: OSM cut to the box with ogr2ogr (three GeoJSON-sequence layers: areas, tree points, tree rows); the
   Microsoft files read through gzip; GHS-BUILT-H warped to a 0.001° grid with gdalwarp; each canopy tile reduced to
   about 10 m (the tallest metre of each 8 × 8 block). Every point goes through the georeference (`Georef`, evaluated
   on a 0.005° grid and interpolated), so roofs stand on the photo's buildings. Each footprint goes to the node that
   holds its centre.
3. **Per node**, on every core:
   - Buildings: OSM's first, then Microsoft's whose centre lies in no OSM footprint. A footprint is kept when it is
     6 m² to 200 000 m² and every corner and its centre are open ground (§1.3).
   - Height: OSM `height`; else `building:levels` × 3 m; else the GHS-BUILT-H cell at its centre; else by its area
     (under 40 m²: 3 m, under 150 m²: 6 m, under 600 m²: 9 m, larger: 12 m; inferred).
   - Roof shape: OSM `roof:shape` gabled, hipped, pyramidal and similar → gabled; dome or onion → dome; else flat.
   - Wall material (0 plaster, 1 stone, 2 concrete, 3 corrugated metal): OSM `building:material` when given; sheds,
     warehouses, hangars, barns, greenhouses and industrial buildings → metal; places of worship, castles, ruins,
     historic buildings and everything within 10 km of Jerusalem's centre → stone (the city's bylaw since 1918 makes
     buildings face in stone[^stone]); flats, offices, shops, public buildings, 5 levels or more, or 2000 m² or more →
     concrete; else plaster. A Microsoft footprint: stone in Jerusalem, metal from 1500 m² (sheds and halls,
     inferred), else plaster.
   - Roof colour: the median of the photo's pixels inside the footprint, once from `mapi2015` (the 1998 look) and
     once from `mapi2015_modern`.
   - Trees: OSM's single trees (`natural=tree`, height tag or 8 m), its tree rows (`natural=tree_row`, one tree every
     6 m, height tag or 10 m), then one tree per canopy cell (0.0001°, about 10 m) of 3 m or more, placed at the cell
     centre moved by up to a third of a cell. A canopy tree within 6 m of an OSM tree is left out.
   - Tree kind: the OSM tags first (genus, species, taxon, leaf type: palm, cypress, pine). Else the land use under
     it on a 10 m grid: pine in a forest or wood; broadleaf (olive-like) in an orchard, vineyard or field; in a
     settlement (OSM residential land, or within 30 m of a building) a palm one time in four, else broadleaf. Tree
     rows are cypresses unless tagged.
4. **Output**: each cell sorted (`Cell::sort`) and written; then the manifest.

Every choice that looks random (a tree's offset, a palm) comes from a hash of the node key and the cell, so a run
gives the same bytes every time (tested: `canopy_trees_are_deterministic`).

### 1.3 Where nothing stands

A building is dropped when any corner or its centre is closed ground; a tree when its point is. Closed ground is:

- **Not the photo**: the photo test compares the `mapi2015` node with the 1998 rendition in blocks of 16 pixels
  (40 m). The layer equals the 1998 art outside the photographed area, so a block whose mean difference is 6 (of 255)
  or less is not the photo.
- **The imagery rules** (`imagery::Rules::open`, docs/imagery.md §3): outside the Israel region, the kept target
  insets, the airbase footprints and terraintype.dat's runways, the sea (terraintype.dat water).
- **Inside a building**, for trees.
- **World scale Real's base sites** (docs/world-scale.md §3.3, `base_move.rs`): each base's old zone and its new zone
  with the flattening ring (1200 m).
- **The missions' units on the ground** (every mission and base mission of missionlist.json, `airbases::mission_units`),
  by the unit's model (`objects/objects.json`, the model's horizontal radius from its glTF bounds):

| Unit | Buildings | Trees |
|---|---|---|
| Static: stationary models (buildings, bridges, towers), SAM sites, radars, parked planes | radius + 60 m | radius + 60 m |
| Vehicle or ship | 40 m around it and along each route | its radius; a 6 m half-width lane along each route |

A route is the unit's `Path` scripts' paths and its formation's waypoints, from its own position.

### 1.4 Files

| Path | What |
|---|---|
| `assets/source/scenery/` | the downloads; `<file>.ok` holds the checked SHA-256 and the download day |
| `assets/converted/scenery/L1/s_<i>_<j>.bin` | one cell per node with any building or tree (format: `iaf_avionics::scenery`) |
| `assets/converted/scenery/manifest.json` | `name`, `release`, `generator`, `made_from`, `attribution`, `licence`, `cells`, `buildings`, `trees`, `downloaded` |
| `assets/converted/scenery/.work/` | kept between runs: the OSM extract (about 1 GB), the reduced canopy tiles, a VRT |

### 1.5 Release and ids

`release` is the SHA-256 of the pinned inputs' checksums and the generator's version (`scenery::GENERATOR`). A
building's id is `<i>_<j>:<index>`, its place in the sorted cell; it is valid for one release. `made_from` adds the
coverage, the converted missions, airbases, theatre and objects stamps: when it matches, the step is up to date.

### 1.6 Setup

| Step | Waits for | Does |
|---|---|---|
| `scenery-fetch` | | downloads the sources (`iaf-scenery fetch`); skipped when download.geofabrik.de cannot be reached |
| `scenery` | mapi2015, scenery-fetch, missions, objects, airbases | makes the cells (`iaf-scenery build`); skipped without GDAL, the sources or the `mapi2015` layer |

Both are optional (setup's `--scenery`, `tools/setup-cli.sh --scenery`). By hand:

```sh
cargo build --release -p iaf-tools
./target/release/iaf-scenery fetch assets
./target/release/iaf-scenery build assets --near 182000,633000,10   # the nodes within 10 km of an engine point
./target/release/iaf-scenery build assets                           # everything
```

Measured on this machine (12 threads): MEASURE.

## 2. Runtime

See below.

## 3. Rendering and the switch

See below.

[^geofabrik]: Geofabrik, "Israel and Palestine" downloads (dated extracts):
    https://download.geofabrik.de/asia/israel-and-palestine.html
[^osm]: OpenStreetMap, "Copyright and License": https://www.openstreetmap.org/copyright
[^ms]: Microsoft, Global ML Building Footprints (README, licence; `dataset-links.csv`):
    https://github.com/microsoft/GlobalMLBuildingFootprints
[^ghsl]: Pesaresi, M.; Politis, P. (2023): GHS-BUILT-H R2023A - GHS building height, derived from AW3D30, SRTM30, and
    Sentinel2 composite (2018). European Commission, Joint Research Centre (JRC), doi:10.2905/85005901-3A49-48DD-9D19-6261354F56FE
[^ghsl-terms]: European Commission, GHSL Data Package 2023 (in each tile's zip), "Terms of Use": "Reuse is authorised,
    provided the source is acknowledged" (Decision 2011/833/EU).
[^chm]: Meta and World Resources Institute (WRI), High Resolution Canopy Height Maps, Registry of Open Data on AWS:
    https://registry.opendata.aws/dataforgood-fb-forests/
[^stone]: Wikipedia, "Jerusalem stone" (municipal laws require stone facing; Ronald Storrs' 1918 ordinance):
    https://en.wikipedia.org/wiki/Jerusalem_stone
