# Scenery: buildings and trees

This doc describes the optional scenery: 3D buildings and trees that stand on the terrain over the Survey of Israel
2 m photo (`mapi2015`, docs/imagery.md §8). Key facts:

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
| OpenStreetMap, Geofabrik's `israel-and-palestine` extract of 2026-01-01[^geofabrik] | buildings with their tags; forests, orchards, fields and settlements; single trees; tree rows | 1 PBF file (119 MB) | ODbL 1.0[^osm] |
| Microsoft Global ML Building Footprints, release 2026-02-03[^ms] | building outlines where OSM has none (Israel, the West Bank, Gaza) | 24 quadkey files (238 MB) | CDLA Permissive 2.0[^ms] |
| JRC GHS-BUILT-H R2023A, average net building height (ANBH), 100 m[^ghsl] | the height of a building without a height tag | 2 tiles, R5_C22 and R6_C22 (16 MB) | free re-use with the source acknowledged[^ghsl-terms] |
| ETH Zürich Global Canopy Height 2020, 10 m[^chm] | where trees stand and how tall they are | 3 tiles of 3° × 3°, N27E033, N30E033, N33E033 (148 MB) | CC BY 4.0[^chm] |

Geofabrik keeps the extract of 1 January of each year for good, so the pinned file stays downloadable[^geofabrik].
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
| `assets/converted/scenery/manifest.json` | `name`, `release`, `generator`, `kinds` (`both`, `buildings`, `trees`), `made_from`, `attribution` (the used sources), `licence`, `cells`, `buildings`, `trees`, `downloaded` |
| `assets/converted/scenery/.work/` | kept between runs: the OSM extract and the reduced canopy tiles (about 350 MB) |

### 1.5 Release and ids

`release` is the SHA-256 of the checksums of the pinned inputs the kinds need, the generator's version
(`scenery::GENERATOR`) and the kinds when not both (`scenery::release`; both keeps the release of before the kinds). A
building's id is `<i>_<j>:<index>`, its place in the sorted cell; it is valid for one release. `made_from` adds the
coverage, the converted missions, airbases, theatre and objects stamps: when it matches, the step is up to date.

### 1.6 Setup

| Step | Waits for | Does |
|---|---|---|
| `scenery-fetch` | | downloads the sources the kinds need (`iaf-scenery fetch`); skipped when download.geofabrik.de cannot be reached |
| `scenery` | mapi2015, scenery-fetch, missions, objects, airbases | makes the cells of the kinds (`iaf-scenery build`); skipped without GDAL, the sources or the `mapi2015` layer |

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
    pitch) or domes where tagged;
  - far: bare prisms.
- Damage is kept by building id `<i>_<j>:<index>` across cell loads. The data itself never changes.

## 3. Rendering and the switch

- **The switch:** Graphics → MORE → Scenery (Off / On, default Off), under Imagery Israel.
  - On is greyed with "Not downloaded" until setup has made the scenery.
  - On is greyed with "Needs Survey 2 m" while the Israel imagery picked on the page is not a Survey 2 m layer.
  - Picking another Israel imagery turns Scenery off. A saved On without both loads as Off.
- **Streaming:** `game/terrain/scenery.gd` keeps the cells within 4.5 km of the camera's focus, and only the Survey
  layer's level-1 nodes; each re-selection looks only at the cells around the focus.
  1. Worker threads read the files into `IafScenery`.
  2. `IafScenery.prepare` makes a cell's meshes and trees on a Rust thread of its own, from a copy of the cell, so the
     main thread never waits on it.
  3. The main thread takes one piece per frame (`take_next`): a chunk of at most 60 000 vertices, or the cell's
     trees. A dense Tel Aviv cell reaches the GPU over several frames.

  The front end's preload (briefing, TSD, arming) already has the near cells made.
- **Per cell:**
  - a near mesh to 2.5 km: walls with windows, and roofs. It fades out over 300 m;
  - a far mesh from 2.5 to 4.5 km: bare prisms of every building. Its far end has no fade: fading draws a whole mesh
    as transparent while in the margin, and a building that far covers a few pixels;
  - our own low-poly trees to 2 km.

  None of them casts a shadow: the photo under them already holds the buildings' shadows.
- **Shading:** `scenery.gdshader` colours roofs from the photo. The photo's colour already holds the sun's light and
  the scene lights it again, so roofs take 0.6 of it and walls 0.5, both at most 0.45 (linear albedo): a town is as
  bright as the photo under it. Walls get the ambientCG plaster, stone, concrete or
  corrugated-steel detail, a window grid (3 m levels, 3.2 m bays) and darker feet. Damaged buildings are sooted. With
  Night lights = Detailed, some windows are lit at night.
- The flight starts once the near cells are drawn.

### 3.1 Cost

Intel Iris Xe (TigerLake GT2) laptop, 2560 × 1440, 2026-10-22: `tests/godot/_flight_bench.gd` with `BENCH_BEST=1`
(mission 311, Ramat David), the Survey 2 m layer on, two runs each, Scenery Off then On:

| leg | Off | On | lost |
|---|---|---|---|
| 150 m, 250 m/s | 77 fps | 70 fps | 9 % |
| 1500 m, 250 m/s | 56 fps | 52 fps | 6 % |
| 6000 m, 300 m/s | 51 fps | 51 fps | 0 % |

Frames over 50 ms: one per run either way (the take-off).

What got it there, from 20 % lost and a 246 ms stall:

- the meshes made on Rust threads instead of the main thread, then uploaded in chunks;
- the far ring cut from 8 km to 4.5 km, its fade removed, and no scenery shadows;
- a re-selection that looks at ≈ 80 nearby cells instead of all ≈ 4 000 (8–19 ms each 0.8 s);
- the mesh threads working on a copy of the cell, so the main thread's drop of a cell does not wait for them.

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

[^geofabrik]: Geofabrik, "Israel and Palestine" downloads (dated extracts):
    https://download.geofabrik.de/asia/israel-and-palestine.html
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
