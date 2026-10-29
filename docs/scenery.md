# Scenery: buildings, trees and roads

This doc describes the optional scenery: 3D buildings and trees that stand on the terrain over the Survey of Israel
2 m photo (`mapi2015`, docs/imagery.md §8), and the road layer of the whole theatre (§6). Key facts:

- It is opt-in. The original has no generic buildings or trees; its stationary models are mission units only.
- Setup makes it from open data downloaded at setup time. The repo holds none of it.
- One cell file per level-1 node of the `mapi2015` layer, the layer's own keys. Scenery stands only where the photo
  shows.
- Nothing stands at an original place: the sea, the airbases, the kept target insets, the missions' units and their
  routes, World scale Real's base sites. No tree stands on a road, a railway, a runway, a taxiway or an apron.
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
| OpenStreetMap, Geofabrik's `israel-and-palestine` extract of 2026-01-01[^geofabrik] | buildings with their tags; forests, orchards, fields and settlements; single trees; tree rows; Israel's and Palestine's roads (§6) | 1 PBF file (119 MB) | ODbL 1.0[^osm] |
| OpenStreetMap, Geofabrik's extracts of 2026-01-01 for `lebanon`, `syria`, `jordan`, `egypt` and `cyprus`[^geofabrik-all] | the other countries' roads (§6), each optional | 5 PBF files (366 MB: Lebanon 51, Syria 75, Jordan 31, Egypt 174, Cyprus 35), in `assets/source/roads/` | ODbL 1.0[^osm] |
| Microsoft Global ML Building Footprints, release 2026-02-03[^ms] | building outlines where OSM has none (Israel, the West Bank, Gaza) | 24 quadkey files (238 MB) | CDLA Permissive 2.0[^ms] |
| JRC GHS-BUILT-H R2023A, average net building height (ANBH), 100 m[^ghsl] | the height of a building without a height tag | 2 tiles, R5_C22 and R6_C22 (16 MB) | free re-use with the source acknowledged[^ghsl-terms] |
| ETH Zürich Global Canopy Height 2020, 10 m[^chm] | where trees stand and how tall they are | 3 tiles of 3° × 3°, N27E033, N30E033, N33E033 (148 MB) | CC BY 4.0[^chm] |

Geofabrik keeps the extract of 1 January of each year for good, so the pinned file stays downloadable[^geofabrik].
The road extracts are `ROADS` in `thirdparty.rs`. The theatre (lon 29.65°–38.29° E, lat 27.04°–36.62° N through the
georeference) also reaches into Turkey's Hatay strip and Saudi Arabia's north-west corner; their extracts (Turkey
618 MB, the GCC states 245 MB, 2026-01-01) are left out for a thin strip of sparse roads. Iraq starts east of the
theatre.
`iaf-scenery tiles assets` lists the quadkeys the Survey 2 m layer touches; the Microsoft list holds every Israel,
West Bank and Gaza file of its `dataset-links.csv`. Setup downloads four files at once and logs every 15 s how
much is down, the speed and the time left ("downloaded 170 of 520 MB, 4.2 MB/s, about 1 min 23 s left").

### 1.2 How a cell is made

`iaf-scenery build` (crates/iaf-tools/src/scenery.rs) works in four stages:

1. **Coverage**: the level-1 nodes of the `mapi2015` layer (`assets/converted/imagery/mapi2015/L1/c_<i>_<j>.jpg`)
   and their box in longitude and latitude.
2. **Sources**: OSM cut to the box with ogr2ogr (three GeoJSON-sequence layers: areas and aprons; tree points; tree
   rows, roads, railways, runways and taxiways); the Microsoft files read through gzip; GHS-BUILT-H warped to a 0.001° grid with gdalwarp; each canopy tile reduced to
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
     6 m, height tag or 10 m), then one tree per canopy cell (0.0001°, about 10 m) of 4 m or more (lower is mostly scrub; inferred), or of 2 m
     or more in a mapped orchard, vineyard or field (citrus, avocado and olive groves are 2–4 m), placed at the cell
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
- **Roads, railways, runways, taxiways and aprons** from OSM. A tunnel or a covered way does not count. A tree is
  dropped within the half-width + 1 m of the centre line, and on an apron or a runway or taxiway area. A Microsoft
  footprint is dropped when it crosses a road's or a railway's centre line, or reaches onto a runway, a taxiway or an
  apron (the outlines are machine-traced; one across a road is a misreading). OSM buildings stay: they are mapped.

| Line (OSM tag) | Half-width (m) |
|---|---|
| `highway=motorway` | 12 |
| `highway=trunk` | 10 |
| `highway=primary` | 8 |
| `highway=secondary` | 6 |
| `highway=tertiary`, `unclassified` | 5 |
| `highway=residential` | 4 |
| `highway=service` | 3 |
| `railway=rail`, `light_rail`, `subway`, `tram` | 3 |
| `aeroway=runway` | half its `width` tag (5–60), else 30 |
| `aeroway=taxiway` | half its `width` tag (5–60), else 12 |

Each `_link` road counts as its class.
- **World scale Real's base sites** (docs/world-scale.md §3.3, `base_move.rs`): each base's old zone and its new zone
  with the flattening ring (1200 m).
- **The missions' units on the ground** (every mission and base mission of missionlist.json, `airbases::mission_units`),
  by the unit's model: its type → the bdb object's Present record (`0x53c`) → `objects/objects.json`, and the model's
  horizontal radius from its glTF bounds. Ground forces and stationary models count wherever they stand (a radar on a
  hill is far above the nearest base); planes and markers only at a base's height (parked):

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
| `assets/converted/scenery/lights/L1/s_<i>_<j>.bin` | the city lights' buildings where the scenery stops (the kept target insets, nodes the Survey layer lacks; same format, buildings only, rendering.md §5.1); `lights/manifest.json` its `made_from` |
| `assets/converted/scenery/manifest.json` | `name`, `release`, `generator`, `kinds` (`both`, `buildings`, `trees`), `made_from`, `attribution` (the used sources), `licence`, `cells`, `buildings`, `trees`, `downloaded` |
| `assets/converted/scenery/.work/` | kept between runs: the OSM extract and the reduced canopy tiles (about 350 MB) |
| `assets/source/roads/` | the other countries' OSM extracts (§1.1) and their `.ok` marks |
| `assets/converted/roads/` | the road layer (§6): `main.bin`, `L3/r_<i>_<j>.bin`, `manifest.json` |

### 1.5 Release and ids

`release` is the SHA-256 of the checksums of the pinned inputs the kinds need, the generator's version
(`scenery::GENERATOR`) and the kinds when not both (`scenery::release`; both keeps the release of before the kinds). A
building's id is `<i>_<j>:<index>`, its place in the sorted cell; it is valid for one release. `made_from` adds the
coverage, the converted missions, airbases, theatre and objects stamps: when it matches, the step is up to date.

### 1.6 Setup

| Step | Waits for | Does |
|---|---|---|
| `scenery-fetch` | | downloads the sources the kinds need and the other countries' road extracts (`iaf-scenery fetch`; a country that fails is logged and has no roads); skipped when download.geofabrik.de cannot be reached |
| `scenery` | mapi2015, scenery-fetch, missions, objects, airbases | makes the road layer (§6; needs only the OSM extracts), then the cells of the kinds (`iaf-scenery build`), then the city lights' cells where the scenery stops (rendering.md §5.1; with buildings only); skipped without GDAL or the sources; the cells also without the `mapi2015` layer |

Both are optional (setup's `--scenery`, `tools/setup-cli.sh --scenery`). Setup makes one of three kinds:

| Kinds | Wizard choice, setup.json `scenery_kinds`, CLI | Downloads |
|---|---|---|
| buildings and trees (the default) | "buildings and trees", `both`, `--scenery` | all 30 files, 520 MB |
| buildings only | "buildings only", `buildings`, `--scenery=buildings` | OpenStreetMap, Microsoft, GHS-BUILT-H: 27 files, 373 MB |
| trees only | "trees only", `trees`, `--scenery=trees` | OpenStreetMap, ETH canopy: 4 files, 267 MB |

A setup.json without `scenery_kinds` means both. The build makes only the chosen kind; the roads, runways and
clearances (§1.3) apply as with both. With trees only, OpenStreetMap's buildings still keep the trees off and set
their kind (§1.2), so the trees are those of both, plus the few that the Microsoft footprints would have dropped.
The manifest's `kinds` names the kinds; the `release` and `made_from` hold them, so a switch of kinds builds again.
Files already downloaded are kept on a switch, and only the missing ones are downloaded. A cell file holds no
buildings or no trees then: the game draws what it has, and the editor's "Set as target" finds no building.

By hand:

```sh
cargo build --release -p iaf-tools
./target/release/iaf-scenery fetch assets [--kinds buildings|trees]
./target/release/iaf-scenery build assets --near 340250,612940,10   # the nodes within 10 km of an engine point
./target/release/iaf-scenery build assets [--kinds buildings|trees] # everything
```

Measured on this machine (Intel laptop, 2026-10-22), the whole layer (4664 nodes):

| | |
|---|---|
| Downloads | 520 MB in 30 files (OSM 119 MB, Microsoft 238 MB, GHSL 16 MB, canopy 148 MB); 40 s on this line |
| Build | 3 min 30 s, peak memory 1.6 GB |
| Output | 4008 cells, 2 076 357 buildings (668 605 from OSM), 28 565 866 trees, 578 MB |
| One kind | the cells of one kind computed from the cell format (a tree is 16 bytes): trees 457 MB, buildings 121 MB. With the work files (the OSM extract 446 MB, the reduced canopy 40 MB for trees): buildings 0.57 GB, trees 0.94 GB, both 1.06 GB |

Two runs give the same bytes (the SHA-256 of every cell file compared).

## 2. Runtime

- Loaded cells live in one process-wide store (`iaf_avionics::scenery::Scenery`, exposed to Godot as `IafScenery`,
  `crates/iaf-godot/src/scenery.rs`). Each cell is indexed in 16 m buckets.
- `top(x, y)` is the scenery's height above ground at a point:
  - inside a building's footprint: its roof. The building stands on the lowest terrain under its corners, as drawn,
    so the roof stays level on a slope. A damaged building counts at 25 % of its height;
  - inside a tree's crown (radius 0.3 × its height): the tree's top;
  - elsewhere: 0.
- `world.rs terrain()` and `terrain_view.gd mission_ground` add `top` to the terrain height. Guns, bombs, missiles,
  the radar's line of sight and the RWR all meet roofs and trees. With no cell loaded the ground is unchanged.
- `ray` returns the distance to the first building prism or tree cylinder along a line.
- Meshes are built in Rust:
  - near: walls, a flat roof 0.8 m below the top behind a parapet, gabled roofs (four-cornered footprints, 30°
    pitch) or domes where tagged. With Scenery = Detailed (`Model::Detailed`) each outer wall carries the street in
    front of it (`street`): the first other footprint straight out from the wall's middle within 40 m, its height
    and distance;
  - far: bare prisms;
  - with Scenery = Detailed, the roof clutter (`roof_rows`): MultiMesh rows on the near flat roofs (§3.3).
- Damage is kept by building id `<i>_<j>:<index>` across cell loads. The data itself never changes.
- Night lights = Detailed reads the cells' buildings too, whatever the Scenery switch, and the light cells where the
  scenery stops: the towns' street lamps, lit windows and haze at night are placed from them (`Cell::read_buildings`,
  rendering.md §5.1).

## 3. Rendering and the switch

- **The switch:** Graphics → MORE → Scenery (Off / On / Detailed, default Off), under Imagery Israel.
  - On: the buildings and trees as below. Detailed: the same, with the facades, occlusion, roof clutter and distance
    fade of §3.3, at a higher cost.
  - On and Detailed are greyed until setup has made the scenery; Detailed's place reads "Not downloaded".
  - They are greyed while the Israel imagery picked on the page is not a Survey 2 m layer; Detailed's place reads
    "Needs Survey 2 m".
  - Picking another Israel imagery turns Scenery off. A saved On or Detailed without both loads as Off; an unknown
    saved value loads as Off.
- **Streaming:** `game/terrain/scenery.gd` keeps the cells within 6 km of the camera's focus (4.5 km drawn plus 1.5 km
  made ahead, so a cell is uploaded before it comes into view), and only the Survey
  layer's level-1 nodes; each re-selection looks only at the cells around the focus.
  1. Worker threads read the files into `IafScenery`.
  2. `IafScenery.prepare` makes a cell's meshes and trees on a Rust thread of its own, from a copy of the cell, so the
     main thread never waits on it.
  3. The main thread takes one piece per frame (`take_next`): a chunk of at most 60 000 vertices, or the cell's
     trees. A dense Tel Aviv cell reaches the GPU over several frames.

  The front end's preload (briefing, TSD, arming) already has the near cells made.
- **Per cell:**
  - the buildings in 500 m tiles (and at most 60 000 vertices per mesh), a near mesh (walls with windows, roofs) and a
    far one (bare prisms). Godot tests a visibility range against a mesh's centre, so a cell-wide mesh would swap
    models and appear in whole strips; each vertex instead carries its building's centre at its base (CUSTOM0), and
    `scenery.gdshader` swaps each building at 2.5 km by its own distance and raises it from the ground over the last
    400 m before 4.5 km;
  - our own trees to 2 km, in 500 m tiles, one MultiMesh per tile, kind and model (§3.2). Godot tests a visibility
    range against an object's centre, so a whole cell's trees would appear at once; the tree shaders instead pick the
    model by each tree's own distance.

  - with Scenery = Detailed, the roof clutter to 700 m, in 500 m tiles, one MultiMesh per tile and item (§3.3).

  None of them casts a shadow: the photo under them already holds the buildings' shadows.
- **Shading:** `scenery.gdshader` colours roofs from the photo. The photo's colour already holds the sun's light and
  the scene lights it again, so roofs take 0.6 of it, at most 0.45 (linear albedo): a town is as bright as the photo
  under it. On: walls take 0.5 of the photo's colour lightened toward plaster, at most 0.45, with the ambientCG
  plaster, stone, concrete or corrugated-steel detail, a window grid (3 m levels, 3.2 m bays) and darker feet.
  Detailed: the facades of §3.3 (`scenery_detailed.gdshader`). Damaged buildings are sooted. With Night lights =
  Detailed, some windows are lit at night.
- The flight starts once the near cells are drawn.

### 3.1 Cost

Intel Iris Xe (TigerLake GT2) laptop, 2560 × 1440, 2026-10-23, the machine idle: `tests/godot/_flight_bench.gd`
with `BENCH_BEST=1` (mission 311, Ramat David), the Survey 2 m layer on, two runs each, Scenery Off then On; the
scenery as built by generator 7 (2.08 M buildings, 28.6 M trees over the layer), in 500 m tiles:

| leg | Off | On | lost | draw calls Off / On | triangles Off / On |
|---|---|---|---|---|---|
| 150 m, 250 m/s | 63 fps | 67 fps | none (within the noise) | 195 / 255 | 359 k / 552 k |
| 1500 m, 250 m/s | 60 fps | 56 fps | 7 % | 185 / 262 | 352 k / 498 k |
| 6000 m, 300 m/s | 56 fps | 55 fps | 2 % | 178 / 178 | 335 k / 335 k |

Frames over 50 ms: at most one per run either way (the take-off).

What got it there, from 20 % lost and a 246 ms stall:

- the meshes made on Rust threads instead of the main thread, then uploaded in chunks;
- the far ring cut from 8 km to 4.5 km, its fade removed, and no scenery shadows;
- a re-selection that looks at ≈ 80 nearby cells instead of all ≈ 4 000 (8–19 ms each 0.8 s);
- the mesh threads working on a copy of the cell, so the main thread's drop of a cell does not wait for them;
- trees beyond 700 m drawn with a canopy-only model (1.8 M → 0.5 M triangles at 150 m).

Trees with the foliage textures (§3.2), 2026-10-26: the same machine and settings, three tree-heavy views instead of
the take-off (`BENCH_AT=<x>,<y> BENCH_LEGS=150:120:15`: 150 m, 120 m/s for 15 s), 2560 × 1440, two runs each under the
shared GPU lock, the plain trees and the textured ones benched back to back:

| View (`BENCH_AT`) | Scenery Off | plain trees | textured trees | lost |
|---|---|---|---|---|
| dense town, 3 800 palms and 17 000 broadleaf trees in its cell (332520,586500) | 46.3 fps | 36.4 fps | 36.3 fps | none |
| orchard, 52 000 trees in its cell (388541,591900) | | 32.5 fps | 30.7 fps | 6 % |
| Carmel pine forest, 59 000 trees in its cell (335161,617200) | | 35.2 fps | 34.6 fps | 2 % |

In the town: GPU 26.8 ms against 26.7 ms, 300 against 313 draw calls, 1 180 k against 1 390 k triangles.

After the round pine crowns (the far pine 12 → 18 triangles) and the linear tree colours, 2026-10-29, the same views
and settings, one run on a quiet machine (load 0.2): orchard 48.4 fps (GPU 20.5 ms, 1 951 k triangles), Carmel
45.8 fps (GPU 21.6 ms, 1 791 k triangles). A second run once the machine got busy again is left out: with the CPU
loaded the main thread, not the GPU, set the frame (orchard 23–33 fps at the same GPU time).

Tried and dropped (2026-10-26):

- full model to 700 m, far model three crossed upright cards and a flat one (8 triangles): town 28.5 fps (22 %
  lost). The crossed cards overlap two or three deep, and each layer is cut per pixel;
- far model six large cards round a core (48 triangles): darker than the full model (the core), and slower still;
- full model to 450 m, far model one card turned to the camera (2 triangles): town 33.8 fps (8 % lost), but orchard
  26.7 fps (23 %) and Carmel 27.6 fps (24 %). A forest towards the horizon stacks the cut-out cards many deep;
- full model to 450 m, far model the solid plain canopy: town fine, orchard 26.9 fps, Carmel 29.8 fps;
- the far model with the back-light term (sunlight through the leaves): 2.6 fps of the orchard's (33.2 against
  30.6 without it, one run each). The full model keeps it: dropping it there gained nothing;
- 10 larger cards a broadleaf crown and 20 a pine's instead of 16 and 30: 31.8 fps in the orchard (1 fps more),
  but the larger cards showed their straight edges up close;
- the full model to 300 m: orchard 31.0 fps; to 250 m it fits;
- anisotropic filtering on the foliage textures: the cards mostly face the camera.

### 3.2 Trees

Each tree is one of four kinds (§1.2), 10 m tall in the model and scaled to its height. Setup's canopy and OSM data
give where and how tall; `tree_rows` (crates/iaf-avionics/src/scenery.rs) adds a seeded look per tree: a yaw, a crown
0.85–1.15 times as wide, and a lean of up to 3° (a palm up to 7°).

**With the foliage textures** (the normal case; setup's `textures` step makes them):

- **Textures:** setup downloads four CC0 ambientCG materials (`TREE_TEXTURES` in crates/iaf-tools/src/thirdparty.rs,
  docs/credits.md) and composes them (`crates/iaf-tools/src/foliage.rs`) into a texture array of 1024² layers with
  every mip level, BC3, in `assets/thirdparty/ambientcg/trees/` (5.6 MB of video memory):

  | Layer | Made from | What |
  |---|---|---|
  | broadleaf | LeafSet001 | about 24 000 small leaves in 100 rounded tufts, the tufts' rims and the back tufts darker |
  | conifer | LeafSet019 | needle sprigs in tufts radiating from the clump's centre (pine, cypress) |
  | palm | Foliage001 | one frond: leaflets on both sides of a rib, longest a third of the way out |
  | bark | Bark012 | the trunks' bark |

  A single leaf is under a pixel from a jet, so the textures hold clumps, not leaves. Each layer stores its colour
  over its mean (the game's tree colour sets the hue) and its coverage. Each mip level's coverage is scaled to keep
  as many texels past the 0.5 cut as the full level, so a distant crown keeps its density instead of thinning out.
- **Models** (`scenery.gd _foliage_tree`), one surface each:

  | Kind | Full model (to 250 m) | Far model (250 m–2 km) |
  |---|---|---|
  | broadleaf | 16 leaf cards round an ellipsoid out to the plain canopy's size, a solid core, the trunk: 80 triangles | the plain ball: 36 |
  | pine | 6 tiers of 5 drooping cards reaching out 1 − f^2.5 of the radius at height fraction f (a round crown, no leader), a solid core, the trunk: 84 | a dome (`_dome`: a ring at the foot, one of 0.6 the radius at 70 % of the height, the apex, with an ellipsoid's normals): 18 |
  | cypress | 7 tiers of 3 upright cards (a cone), a leader, a solid core, the trunk: 70 | the plain cone: 12 |
  | palm | 10 fronds (3 segments each, folded in a V), the trunk: 132 | the plain fronds: 20 |

  The far model is the plain canopy, solid, drawn by `scenery_foliage_far.gdshader` in the full model's leaf colour
  (times 0.9, its mean brightness), with each tree's own shade and hue and the underside darker, so a far crown keeps
  the near one's hue and brightness.

- **Colour:** the leaf and trunk colours (`FOLIAGE` in scenery.gd) are linear albedo, passed to the shaders as a
  Vector3 (`_linear`): a Color reaches a vec3 uniform converted from sRGB to linear, about ten times darker for
  these values. Pine (0.057, 0.09, 0.028) is a mid, slightly olive green, as Aleppo pines read from the air; olive
  and carob a grey-green; cypress darker.
- **Shading** (`scenery_foliage.gdshader`): the cards are cut at the texture's 0.5 coverage (alpha-to-coverage with
  MSAA). The cards carry the crown's round normal bent halfway up (both models, `UP`), so a crown is lit as one
  volume and its side away from the sun reads mid-green, as leaves scatter light, not black. The vertex colour holds the
  occlusion: darker toward the crown's heart and underside, the trunk darker under the crown. Sunlight passes
  through the leaves (Godot's back-light). Each tree gets its own brightness (±18 %) and a little yellower or bluer
  hue. The crowns sway gently (6 cm at the tips). The leaves are matte (specular 0.1, the core 0).
- **Distance:** the full model fades out over 200–300 m (a screen dither) over the far model, which starts at
  200 m; the far model grows in from nothing over the last 300 m before 2 km, as the plain trees do.

**Without the textures** (setup could not reach ambientCG): the plain models as before, a six-sided trunk and a
low-poly canopy in one colour (`scenery_tree.gdshader`, the colour linear as above; the pine a dome): about 80
triangles to 700 m, a canopy-only model (6–24 triangles) beyond, growing in from nothing over the last 300 m before
2 km.

**The hills' look, 2026-10-28** (the Carmel from 80 m, `_showcase_shot.gd` scene `carmel_low`; A/B one switch at a
time). Before, the pines were near black (sRGB ≈ 20, 26, 23) and the ground between them white:

- the leaf colours reached the shaders converted from sRGB (above): about ten times too dark. Passed linear;
- the dark forest filling the view pushed the auto-exposure up (rendering.md §1.2), so the photo's pale ground
  between the trees went white (sRGB ≈ 157 against 140 with Scenery Off). With the trees mid-green it is back to
  the photo's own value;
- the Survey photo's ground there is a neutral grey (≈ 135, 137, 136): warmed in the terrain shader (imagery.md §5);
- the pines' cones read as a fir plantation: a round crown near and far.

Ground textures and Terrain close up changed nothing of it (the same picture with either off). Tried and dropped:
the far pine as a two-apex bicone (12 triangles, as the cone): from 250 m it read as rows of diamonds; as a cone
cut at 45 % of its radius and capped: rows of buckets. Open: the canopy places a pine in every 10 m cell of 4 m or
more, so a forest is an even stand; the real Carmel is a mosaic of pine, oak maquis and open scrub. That needs the
cell data rebuilt (§1.2), not the renderer.

### 3.3 Scenery = Detailed: facades and roofs

With Scenery = Detailed the walls and roofs are drawn to read as an Israeli town (`scenery_detailed.gdshader`,
`scenery_roof.gdshader`). On keeps the plain walls and the cost of §3.1: its shader and meshes are those of On alone
(no streets, no roof clutter). All of it is our own, made in the shader or by Rust from the footprints; no new
texture.

- **Wall colour:** each building picks a colour from its material's palette by a seed from its index: stone =
  Jerusalem-stone creams and golds; plaster = white, off-white, beige, pale pink, light grey; concrete = greys and a
  beige-grey (blocks of flats); corrugated sheds keep the photo's colour. The colour takes 20 % of the photo's, then
  the ambientCG detail of its material.
- **Windows** (not on sheds): each building has its own grid (bays 2.9–4.1 m, levels 2.9–3.3 m) and window size
  (40–62 % of a bay wide, sills at 0.9 m). Each window is recessed 0.22 m by parallax: the eye sees its glass move
  behind the opening and the reveal at the sides, the sill and the soffit. Inside the opening:
  - a 6 cm frame (light aluminium or dark, per building) and a sliding window's meeting rail in the middle;
  - a roller shutter (tris, per window: up, a third, two thirds or all the way down), slats every 6 cm;
  - glass that reflects the sky: smooth (roughness 0.04–0.29) and tilted a little, both by a seed per window, so
    the panes do not mirror the sky as one sheet. A few rooms show a lit-up curtain instead of a dark room.
- **Loggias:** blocks of flats (8.5 m and taller, plaster or concrete) have, on most buildings, recessed balconies
  in every other bay above the ground floor:
  - open (70 %): a 1.4 m deep recess by parallax, the door at the back, the floor's light tiles where the eye looks
    down into it. The recess is out of the sun and most of the sky: its colour and ambient light are halved, darker
    still under the slab above;
  - closed in (sgirat mirpeset, 30 %, per loggia): sliding glass with frames and roller shutters 0.12 m behind the
    facade, above the balustrade;
  - the balustrade to 1.1 m, per building: solid in the wall colour with a lit coping (55 %), glass (the loggia seen
    through, tinted, a dark handrail; 25 %) or bars every 12 cm (20 %);
  - where a level is under about two pixels high, an open loggia keeps a darker cell (60 % of the wall against 80 %)
    until the cell itself is under a pixel, so a block's loggia columns still read from 150 m and beyond.
- **Weathering and AC units:** streaks of dust run down from each sill. About 40 % of the windows above the ground
  floor have an AC unit (0.84 × 0.54 m, its fan grille, a shadow under it) below the sill.
- **Occlusion:** the walls' ambient light (Godot's `AO`, the sun is not touched) is darkened by the street in front:
  the facing building hides the sky up to its top, so the lower floors of a narrow street are darker than the upper
  ones; and by the ground, the lowest 3 m. The lowest 1.2 m is also darker in colour (dirt). The sunlit walls keep
  the full sun, so a shaded wall stands further from a sunlit one than before.
- **Parapets:** the outer wall's top 10 cm is a lit coping; the parapet's inner face (marked by the mesh, CUSTOM0.w
  = −1) is plain wall colour with the coping on top, its foot darker and occluded where it meets the roof.
- **Roofs:** the photo's colour is a hint, not the roof:
  - a flat roof's material follows the photo's brightness (a seed per building moves the line): bitumen (some
    painted silver in patches), grey concrete with joints every 6 m or gravel, or the white reflective coating common
    on Israeli roofs, worn through to concrete in patches. Over that: 1 m membrane strips along the building, sheets
    of 4 × 2 m each its own shade, stains of 1 m and 4 m, darker patches where water stands. The mesh gives a Detailed
    flat roof UVs in metres along and across the building's longest edge, so the strips and sheets follow it;
  - a pitched roof: clay tiles, courses of 0.33 m down the slope, each course's lower lip shaded;
  - the colour takes the photo's hue (half strength) and comes halfway to its brightness, so the near roof keeps the
    far one's tone; a dome keeps the photo's colour. Details under about two pixels fade out.
- **Distance:** a window under about two pixels fades to the wall's average (no shimmer); from 700 m to 2.2 km the
  walls and roofs fade to the photo's colour at the building, so the far town keeps the photo's hues instead of
  turning into uniform pale blocks.
- **Roof clutter** (`roof_rows` in crates/iaf-avionics/src/scenery.rs, the models in `scenery.gd roof_mesh`, drawn
  by `scenery_roof.gdshader`): on the near flat roofs of 30 m² and more, on a 2.4 × 2.8 m grid along the roof's
  longest edge, at least 1.4 m inside the parapet, seeded per building:
  - a stair head (2.6 × 3.0 × 2.5 m, in a wall colour) on buildings 6 m and taller;
  - solar water heaters (dud shemesh: a 2 × 1 m collector tilted to the south and its tank, 26 triangles) on 85 %
    of the roofs, about 60 % of the free spots, facing south within ±9°;
  - water tanks (white or black) and AC units on some of the rest;
  - at most 14 items per roof. They shrink onto the roof over 550–700 m, each by its own distance.

  Their materials (the vertex alpha picks one): the collectors' glass dark blue-black (roughness 0.45, specular
  0.12: a glint at a low angle), the frames galvanised steel, the tanks and stair heads paint with the walls' light
  (roughness 0.9, specular 0.3). The colours are sRGB, so a white tank is as bright as a white wall. Each item has
  flat normals, is darker and occluded over its lowest 0.5 m, and stands on a dark shade 4 cm over the roof, a
  little larger than its footprint (a heater's reaches north, behind its collector).

**Cost** (measured below; measure again with `tests/godot/_flight_bench.gd`, `BENCH_BEST=1` and a town view,
e.g. `BENCH_AT=316009,530807 BENCH_LEGS=150:120:15`, `BENCH_SET=scenery=on` against `=detailed`, as §3.1):

- the wall shader does about three times the work per wall pixel (the parallax, the shutters, the AC units): walls
  fill a large part of the screen only low over a town;
- the roof clutter: within 700 m over a dense town about 3 000 roofs, up to 14 items each (26 triangles for a
  heater): about 0.28 M primitives more at 150 m over Rishon (measured);
- the street per wall adds to the mesh making on the Rust threads (one short ray per wall), not to the main thread.

**Measured** 2026-10-28, Intel Iris Xe, 2560 × 1440, `_flight_bench.gd` with `BENCH_BEST=1
BENCH_AT=316009,530807 BENCH_LEGS=150:120:15` (Rishon LeZion, 150 m, 120 m/s for 15 s), `BENCH_SET=scenery=on` and
`=detailed` interleaved On, Detailed three times under one hold of the GPU lock. Other jobs (builds) still ran on the
CPU: two On runs had 94–128 ms of main-thread process time and are left out of the frame rates; the GPU time holds
across all six.

| | On | Detailed | change |
|---|---|---|---|
| GPU time per frame (all runs) | 17.46 / 17.32 / 19.06 ms | 20.28 / 21.41 / 20.69 ms | +18 % (medians 17.46 → 20.69) |
| frame rate (the clean On run, Detailed's three) | 49.9 fps | 44.6 / 41.9 / 43.4 fps | −11 to −16 % |
| draw calls | 308 | 319–320 | +11 (the roof clutter's tiles) |
| primitives | 697 k | 968–987 k | +40 % (the roof clutter) |

This is over the ≤ 10 % budget for a default look, so Detailed is a choice of its own and On keeps its cost.

The second pass (roof materials, item materials and shade, loggias), 2026-10-28, the same machine, view and
settings, three runs each interleaved On, Detailed before, Detailed after under one hold of the GPU lock:

| | On | Detailed before | Detailed after |
|---|---|---|---|
| GPU time per frame | 14.27 / 16.60 / 14.40 ms | 16.91 / 18.63 / 16.83 ms | 17.42 / 17.06 / 17.25 ms |
| median | 14.40 ms | 16.91 ms (+17 %) | 17.25 ms (+20 %; +2 % on the first pass) |
| primitives | 722–736 k | 1 034–1 042 k | 1 059–1 064 k (the shade quads) |

Measure again the same way after a change to `scenery_detailed.gdshader` (the roof's noise runs on every roof pixel
within 2.2 km: the cost grows with the roofs' share of the screen, most from 1–2 km up over a town).

Tried and dropped (2026-10-28):

- the collectors' glass smooth (roughness 0.15, specular 0.6): from above they mirrored the bright sky and read as
  white blobs; now rough 0.7, specular 0.12. Tanks and frames darker for the same reason;
- glass at roughness 0.04 and specular 0.6 on the windows: at a glancing angle every pane went white.

Tried and dropped (2026-10-28, the second pass):

- the roof's material picked by the photo's brightness with fixed albedos (bitumen 0.07, concrete 0.22, white
  0.45): most Rishon roofs are dark on the photo and turned black; now each material comes halfway to the photo's
  brightness;
- the worn patches as smooth noise blobs only: the roofs looked like camouflage; now with ragged edges and the
  4 × 2 m sheets;
- the roof's noise in world metres: the sin hash loses its precision at the world's coordinates (300 km); the flat
  roofs now use building-local metres, the tiles a sin-free hash over world metres repeating every 4 km;
- the collectors at roughness 0.32, specular 0.35: they mirrored the sky as bright blue panes.

The root of the pale items: SurfaceTool's normals were smoothed (smooth group 0), so a box's sides leaned up to the
sky; and the colours were taken as linear, half again brighter than the walls.

Open: the roof has no darker band along its parapet (the fragment does not know its distance to the edge); the
heaters' shade does not follow the sun; the clay tiles show only on the few roofs the data tags as gabled.

## 4. Solid ground and hits

Roofs and tree tops are ground. With Scenery off no cell is loaded, `top` is 0 everywhere and everything below works
as in the original.

- **What sees them:**
  - every Rust weapon and sensor, through `world.rs terrain()` (§2);
  - GDScript through `mission_ground` (world frame) and `scene_ground` (scene frame) in `terrain_view.gd`;
  - the player's jet, the AI jets and a derelict jet: `feed_ground` gives their flight model the terrain plus `top`;
  - the AI autopilot's terrain watch (`ap_set_ground`, the player's autopilot too), so it climbs over towers;
  - the external cameras and the cockpit eye stay above roofs (`views.gd`, `_apply_view`);
  - the height warnings: the HUD's height and the radar altimeter (from the flight model's ground), Betty's "Pull up"
    and "Altitude", the F-16's GAAF and CARA ALOW calls (`flight_sounds.gd`), and the info line's height above
    ground. A real radar altimeter measures to whatever is under the jet, roofs and trees included.
  - debris, the wreck's explosion, the weapons' explosions and the ejected pilot's parachute land on roofs;
  - the EO centre point: `IafScenery.ray` finds the first wall, roof or crown along the line of sight, so the
    camera's point lands on a building the terrain ray march would step past.
- **Crash rule:** when scenery stands under a jet, its flight model gets `set_ground_obstacle(true)`
  (`Aircraft::ground_obstacle`). A jet whose gear is at or below that roof or tree top is destroyed at once, at any
  speed: reason `scenery`. The check runs at every flight-model step, not only at the 5 Hz ground checks, so a jet
  flying into a building's side between two checks crashes too. It applies to the AI jets as well (their crash
  immunity covers the original terrain only); the player's Invulnerable and No crashes still protect.
- **Damage rule:** every blast of `mission_runtime.gd area_damage` except gun rounds (bombs, missiles, rockets, the
  AI's too) calls `IafScenery.blast`. It marks one building damaged:
  - the building whose footprint holds the blast point, else the one with the nearest centroid within the blast
    radius, at most 15 m;
  - only when the point is at most 10 m above that roof (an air burst leaves it whole).

  The building stays. A damaged building is drawn sooted and counts at 25 % of its height (§2).

## 5. Targets, editor and briefing

A mission can set a building of the scenery as a target. It can never remove scenery: the building stays, and only
its damage shows. Only the mission editor makes scenery targets.

### 5.1 The target in the mission

A scenery target is an ordinary mission entity of bdb object 51 `civilhouse` (class 12, building) at the building's
centroid, red, role 1 (Target), shown on the pilot's TSD (`0x35c` = 1). The win and lose rules count it as any unit
(mission-editor.md §13). Its own fields (formats/mis.md §3):

| Field | What |
|---|---|
| `scenery` | the building's id `<i>_<j>:<index>` (§1.5) |
| `scenery_area` | the footprint's area (m²) |
| `scenery_height` | the building's height (m) |
| `scenery_count` | the other buildings whose centroid is within 1 km, counted when it was set |
| `scenery_outline` | the footprint, world X / Y |

The main mission file holds `scenery_release`, the `release` of the scenery it was made with (§1.5).

### 5.2 In flight

`mission_runtime.gd` and `terrain_view.gd`:

- **The building stands** when Scenery is on over a Survey 2 m layer, the mission's `scenery_release` is the
  installed one, and the building's index is in its cell file (`scenery.gd target_reason`). The marker then draws
  nothing: the building is the scenery's.
- **Otherwise** the marker draws an original model in its place, so the mission stays playable: `ofice1` (an office
  block) under 1500 m² of footprint, else `fctry1` (a factory; inferred). The reason is "Scenery is off", "the mission
  was made with another scenery" or "the building is not in this scenery".
- **Hit box:** the blast test's box (docs/damage.md) gets the larger of half the footprint's side (√area / 2) and half
  the height, centred half the height above the ground.
- **Destroyed:** `IafScenery.set_damaged(id, true)`: the building stays, sooted and lowered (§2). At the mission's
  start the building is set whole again, since the damage store lasts for the whole game session.

### 5.3 Mission editor

Only with the scenery made by setup (its manifest). The editor reads the cells itself, through `IafMissionEdit`, as
the view or a check needs them.

- **Buildings on the map:** from zoom 240 on, every building in view is drawn as a grey outline under the unit icons;
  the editor then zooms in to 1024 (the original TSD stops at 32).
- **Set as target:** a click on a building (within 6 pixels) outlines it in yellow and opens a menu: its height and
  area, then **Set as target** (`mission_edit::scenery_target`). It adds the marker (§5.1), named "Building N", and
  selects it. A building already set selects its marker. The marker cannot be dragged off its building. Deleting the
  marker removes the target, never the building; there is no action that removes scenery.
- **Check:** a site (SAM, AAA, radar, building: bdb classes 8–13) with a building footprint within 10 m, or a
  vehicle (classes 5, 6) within 2 m, gets the warning "on a building: move to clear ground" (inferred limits;
  vehicles may stand among trees and between houses). Its fix is the nearest clear point within 500 m (rings 5 m
  apart, a point every 5 m); the selected unit then shows **Move to clear ground**.
- **Intel preview** and the pilot's TSD outline each scenery target's building in red (`tsd.gd outlines`).

### 5.4 Briefing

The briefing of an edited mission (tsd.gd `_briefing`, through `Settings.briefing_override`) ends with one line per
scenery target, in English or Hebrew: "Building 1: a building 17 m high; 61 buildings within 1 km." When its building
does not stand (§5.2) the line adds "Shown as an original office block (Scenery is off)."

### 5.5 Calibration on the original missions

The Rust test `scenery_check_originals_clean` runs the check over the missions and base missions of
missionlist.json with the installed scenery: no original unit stands on a building.

### 5.6 Tests

- `cargo test -p iaf-tools --lib mission_edit::tests::scenery`: Set as target (the fields, the same building twice, no
  building), the check and its clear point, the originals.
- `cargo test -p iaf-avionics --lib scenery`: `outlines`, `clear`.
- `tests/godot/test_scenery_targets.gd`: on a test cell, the editor's pick, Set as target, Move to clear ground, the
  intel preview's outline; flown with Scenery off the stand-in and the briefing line; with Scenery on no model, and
  the building damaged but still there when the target is destroyed.
- `tests/godot/_mission_editor_shot.gd` with `ED_SCENERY=menu` / `target`: real-render screenshots.

## 6. Roads

Setup makes a road layer of the whole theatre from OpenStreetMap: the briefing map draws its main roads (Extras
"Briefing map" = Modern, docs/front-end.md §8), the mission editor's ground routes follow it (Follow roads,
docs/mission-editor.md §5.2.1), and Graphics → MORE "Roads" Detailed draws it on the ground near the camera with
lamps along the lit roads at night (docs/rendering.md §1.8, §5.1). The game does without it (an older setup): no
road shows, and routes stay straight.

### 6.1 How it is made

`iaf_tools::roads::build` (`iaf-scenery roads assets`; `iaf-scenery build` and setup's `scenery` step make it too):

1. **Extracts**: Israel and Palestine (required), then each other country downloaded (§1.1), in that order. ogr2ogr
   takes each extract's `lines` layer within the theatre's box. A way in two extracts (they overlap at the borders)
   is kept once, the copy with the most points. Points outside the box are dropped.
2. **Ways taken**: `highway` = motorway, trunk, primary, secondary, tertiary (each with its `_link`), unclassified,
   residential, living_street, service, track; and `railway=rail`. Footways, paths, cycleways, steps and trams are
   left out.
3. **Attributes**, per way[^osm-highway]:

| Field | From |
|---|---|
| class | motorway 0, trunk 1, primary 2, secondary 3, tertiary 4, minor 5 (residential, unclassified, living_street), service 6, track 7, rail 8; a `_link` keeps its road's class with the link flag |
| width (m) | `width` (up to 60 m); else `lanes` × 3.5; else by class: 11, 9, 8, 7, 6, 5, 3.5, 3, rail 3; a link 5 (inferred: one mapped carriageway, 3.5 m lanes and shoulders) |
| bridge, tunnel | the tag present and not `no` |
| layer | `layer`, −5 to 5; 0 untagged |
| paved | `surface` unpaved, gravel, dirt, ground, sand, compacted and the like → unpaved; untagged: a track is unpaved (but `tracktype=grade1`), the rest paved |
| oneway | `oneway` yes / true / 1 / −1 / reverse; untagged motorways and roundabouts. `−1` reverses the points, so a oneway runs in its direction of travel |
| lit | `lit` no or disused → unlit; any other value → lit; untagged → unknown |
| osm_id | the way's id |

4. **Junctions**: each longitude / latitude is one vertex, so ways that share an OpenStreetMap node share the vertex
   (across borders too). The georeference warps each vertex into the engine frame (`scenery::Warp`, as the scenery).
5. **Off the ground**: a way is cut where it passes onto an airbase (its footprint or a runway), World scale Real's
   old or new base sites (with their 1200 m ring) or the 1998 sea (terraintype.dat water), tested at each vertex and
   segment middle. That piece is kept with the off-ground flag: the map draws it, the ground does not. The road
   layer has no region limit: the whole theatre wherever OSM has roads.
6. **Files**: `main.bin` holds the motorway to secondary ways of the whole theatre, whole. Each block file
   `L3/r_<i>_<j>.bin` holds every class within block (i, j): a level-3 node of the terrain (8192 units, about
   10.2 km), the 4 × 4 scenery cells `s_<4i..4i+3>_<4j..4j+3>`, the city lights' blocks (rendering.md §5.1). A way
   is cut where it crosses a block's edge, at a point on the edge that both pieces hold, so every segment lies in one
   block. The format is in `crates/iaf-avionics/src/roads.rs`: one table of f32 points (engine metres, X east, Y
   north), then the ways (OSM id, point count, class, flags, layer, width in decimetres), then the ways' point
   indices. A junction is one index in a file; across block files the same point has the same coordinates.

The manifest (`converted/roads/manifest.json`) holds `made_from` (the extracts' checksums, the converter's version
`ROADS_VERSION`, the missions, airbases and theatre stamps; when it matches, the step is up to date), the extracts
used, the counts and the attribution the credits roll shows.

### 6.2 Counts

Measured on this machine (Intel laptop, 2026-10-29), all six extracts:

| | |
|---|---|
| Ways | 2 356 078: motorway 13 303, trunk 26 858, primary 27 575, secondary 48 833, tertiary 98 034, minor 1 616 682, service 299 232, track 218 546, rail 7015 (pieces: a way cut off the ground counts per piece) |
| Points | 20 441 485 |
| Files | `main.bin` 21 MB; 3521 block files, the largest 1.9 MB; 327 MB in all |
| Time | 2 min 13 s; per extract (ogr2ogr and reading): Israel and Palestine 10 s (384 866 ways), Lebanon 5 s (150 628), Syria 6 s (220 135), Jordan 8 s (151 812), Egypt 29–65 s (1 287 406), Cyprus 6 s (156 581); the warp, the cut and writing the rest |

### 6.3 Runtime

`IafRoads` (`crates/iaf-godot/src/roads.rs`) over `iaf_avionics::roads::Roads`. Points are engine metres (X east,
Y north), no height. `max_class` keeps that class and the more important ones; up to secondary the queries read
`main.bin`, a finer class the block files (read when needed, the last 96 kept).

| Call | Answer |
|---|---|
| `open(dir)` | reads `main.bin`; false without it |
| `roads_in_rect(min, max, max_class)` | the ways whose box meets the rect, as dictionaries: `points`, `class`, `link`, `width`, `bridge`, `tunnel`, `layer`, `paved`, `oneway`, `lit` (1, 0, −1 unknown), `off_ground`, `osm_id` |
| `segments(min_class, max_class)` | `main.bin`'s segments as point pairs (the map's line meshes) |
| `nearest(p, max_class)` | the nearest road point within 10 km (railways left out): `point`, `distance`, `class`, `osm_id` |
| `route(a, b, max_class)` | the shortest route (A* over the junctions, oneway ignored) between the road points nearest `a` and `b`; finer than secondary within the ends' box grown by 5 km, at most 64 blocks |
| `request_mask(c)`, `take_mask()` | the ground's road mask around engine point `c` (2048² texels of 2 m, RG8: the signed distance to the nearest road's edge and its paved flag and width), made on a thread of its own; `take_mask` hands it over once made (docs/rendering.md §1.8) |

The city lights' thread reads a block file directly (`roads::block`) for the road lamps (docs/rendering.md §5.1). A
block file is read outside the store's lock, so the threads' reads do not hold up the game's own queries.

Tests: `cargo test -p iaf-avionics --lib roads` (the file, the queries, a route through a junction, blocks merged,
the mask); `cargo test -p iaf-avionics --lib city_lights` (the road lamps); `tests/godot/test_ground_roads.gd`;
`cargo test -p iaf-tools --lib roads` (the tags, a shared node one vertex, the off-ground cut, the block edge cut).

[^geofabrik]: Geofabrik, "Israel and Palestine" downloads (dated extracts):
    https://download.geofabrik.de/asia/israel-and-palestine.html
[^geofabrik-all]: Geofabrik downloads (each country's page lists its dated extracts): https://download.geofabrik.de/
    (asia/lebanon, asia/syria, asia/jordan, africa/egypt, europe/cyprus; sizes of 2026-01-01 as served 2026-10-29)
[^osm-highway]: OpenStreetMap Wiki, "Key:highway", "Key:oneway" (motorways and roundabouts imply oneway), "Key:lit",
    "Key:surface", "Key:lanes", "Key:layer": https://wiki.openstreetmap.org/wiki/Key:highway
[^osm]: OpenStreetMap, "Copyright and License": https://www.openstreetmap.org/copyright
[^ms]: Microsoft, Global ML Building Footprints (README, licence; `dataset-links.csv`):
    https://github.com/microsoft/GlobalMLBuildingFootprints
[^ghsl]: Pesaresi, M.; Politis, P. (2023): GHS-BUILT-H R2023A - GHS building height, derived from AW3D30, SRTM30, and
    Sentinel2 composite (2018). European Commission, Joint Research Centre (JRC), doi:10.2905/85005901-3A49-48DD-9D19-6261354F56FE
[^ghsl-terms]: European Commission, GHSL Data Package 2023 (in each tile's zip), "Terms of Use": "Reuse is authorised,
    provided the source is acknowledged" (Decision 2011/833/EU).
[^chm]: Lang, N., Jetz, W., Schindler, K., Wegner, J. D. (2023): A high-resolution canopy height model of the Earth,
    Nature Ecology & Evolution; data: Global Canopy Height 2020, ETH Zürich, CC BY 4.0:
    https://langnico.github.io/globalcanopyheight/
[^stone]: Wikipedia, "Jerusalem stone" (municipal laws require stone facing; Ronald Storrs' 1918 ordinance):
    https://en.wikipedia.org/wiki/Jerusalem_stone
