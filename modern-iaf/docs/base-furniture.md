# What stands on the airbases

This page describes the buildings, shelters, parked jets and vehicles that Modern IAF stands on its airbases: where
each one's place comes from, the data file, and how the game draws it. Ramon (LLRM, the Sufa's home base) is the first
base filled (2026-11-19; the user approved the look the same day: "A64 approved, do it for all air bases"). The other four bases have no furniture file yet.

Terms: HAS = hardened aircraft shelter; S2 = Sentinel-2 (the ESA satellite pictures, 10 m); OSM = OpenStreetMap;
"inferred" = our own reasoning.

The user's words (17 November 2026, [research/models-catalogue.md](research/models-catalogue.md) §7): "fill the base
with hangers and building and other airplanes"; "for bases, look on air photos of the bases and try to put things as in
reality"; parked aircraft use the flying jets' models ("why not just use the same models").

## 1. The sources

- **Imagery.** The Survey of Israel 2015 photo paints Ramon over with desert ([airbases.md](airbases.md) §6), so the
  only picture of the base is Sentinel-2 at 10 m (ESA WorldCover 2021 composite, CC BY 4.0[^wc]), already in
  `assets/source/imagery/sentinel2/`. A shelter is 2 to 5 pixels there. Places hold to about 10 m; kinds, doors and
  heights are inferred. Jets, vehicles and blast walls cannot be seen.
- **OpenStreetMap**[^osm] (the scenery step's extract `israel-and-palestine-260101.osm.pbf` and the airbases step's
  Overpass answer): 25 `building=yes` ways (mostly 21–29 m squares in the north-east dispersal), the 7 "hangars" of a
  fenced compound north of 07L/25R, the base's fence (`barrier=fence` on the aerodrome way), 45 helipads (the Apache
  lines; nothing stands there: the sim has no helicopter model).
- Microsoft's building footprints have none on the base.

## 2. The survey

`tools/iaf-2026/base_survey/` (run with `python3 -I`, with `D` set to the survey's work folder that holds the
extracts): `blobs.py` finds bright objects against the ground within 90 m in S2, `survey.py` crops them with the OSM
layers, `blobplot.py` numbers them, `rows.py OUT` writes the rows and checks them against the taxiways and the AI's
taxi paths. `s2:<n>` in a row is that survey's object number.

What it found at Ramon:
- 10 bright roofs at the ends of the loop taxiways (S1–S10): one shelter per loop, its door toward the loop 22–34 m away;
- 10 more bright roofs off the mapped taxiways (S11–S20), shelters by size (inferred);
- the 13 OSM squares of the north-east dispersal (S21–S33), two with a bright roof: shelters, several earth-covered
  (inferred: not bright);
- the 7 OSM "hangars" of the alert compound (S34–S40), with two fence rings, 3 gates and its own runway link: alert
  shelters (inferred);
- 6 large OSM buildings and 4 large bright roofs in the technical area: hangars (H1–H10);
- a walled compound midfield between 07R/25L and the parallel taxiway with a bright roof: the tower (T1, inferred;
  OSM and the airbase file have no tower);
- 14 smaller buildings (B1–B14), a 370 m roof line beside the helipads (the sunshade U1).

## 3. The data: `modern-iaf/data/furniture/<icao>.json`

One file per base, `{"icao", "survey", "frame", "footnotes", "rows": [...]}`. Each row:

| key | what |
|---|---|
| `ref` | the row's name (S1, H1, J1...) |
| `kind` | `shelter`, `hangar`, `building`, `tower`, `sunshade`, `fence`, a jet (its aircraft definition's id: `f16i`, `f16` the Barak, `f35i`), `gpu`, `fuel_truck`, `extinguisher`, `tug` |
| `lat`, `lon`, `heading` | WGS-84, true heading in degrees: a shelter's door, a hangar's or building's long side, a jet's nose |
| `size_m` | [along the heading, across] in metres |
| `along` | `"boundary"` for the fence: it runs along the airbase file's `boundary` |
| `source`, `osm`, `id`, `note` | `s2`, `osm` or `inferred`; the OSM way; the survey's object; why it stands there |

The folder is its own: `data/furniture` is an input of the `sim-terrain` stamp (the shelters' pads are graded flat
into the bases' ground, `sim_terrain::grade_base`) and of the `sim-airbases` stamp, not of the scenery or the missions
(`crates/iaf-setup/src/stamp.rs` `sim_io`). A changed furniture file re-grades the theatre's height nodes only:
the files' hash is in its `grade.txt` (`sim_terrain::grade_text`).

Ramon's 83 rows: 40 shelters, 12 parked Sufas (10 in the loop-end shelters, 2 in the alert compound, each at its
shelter's middle, nose out), 10 hangars, 14 buildings, the tower, the sunshade, the fence, and beside the player's
parking spot a ground power unit, a fuel truck and a fire extinguisher (inferred, as on a flight line); a tug stands
outside the alert shelter S35.

## 4. Compiled: `iaf-sim airbases`

`sim_bases::files` reads the furniture file beside the airbase file; `base` puts each row in the frame (UTM 36N, the
grid heading) as `sim_bases::Item`. `airbases.json` gets each base's `furniture`: [{`kind`, `at`, `heading`, `size`}]
or for the fence {`kind`, `line`} ([data-formats.md](data-formats.md) §12).

Each shelter's pad and 20 m of concrete before its door join the base's shelters' pads (`SHELTER_APRON_M`): the mask
draws them as apron and `terraintype.dat` flags them paved, so the door's apron meets the loop taxiway.

`sim_bases::tests::the_furniture_stands_clear` checks Ramon: the 40 shelters load, every footprint stands over 40 m
from a runway's edge, over 25 m from the departure from each parking spot (the ramp vehicles 5 m), and every shelter
stands on its pad.

## 5. In the game

`shared/terrain/base_furniture.gd` builds the nearest base's furniture once the ground under it has loaded
(`airbases.gd`, as the taxiway signs). Every shape is our own, in vertex colours with one material:
- a shelter: a concrete arch 0.4 times as high as it is wide (a TAB-VEE is about 22 m wide and 8.5 m high: inferred
  for the IAF's), open at the door, dark inside;
- a hangar: walls to 10 m, a low gable roof to 13 m, a door in the front end; a building: a 6 m flat-roofed block;
- the tower: a low building, a shaft and a glass cab at about 18 m (inferred);
- the sunshade: a 5.5 m roof on posts every 15 m; the fence: 2.4 m of grey mesh on posts every 6 m, see-through;
- the ramp vehicles: a yellow power-unit trailer, an olive fuel truck, a red extinguisher trolley, a yellow tug;
- a parked jet (kind = an aircraft definition's id): the flying jet's model (`jet_model`: the definition's `model`, else its detailed model, else `<id>.gltf` in its folder) standing on its gear, every surface merged
  into one in its material's colour (the texture's average), simplified to about 6,000 triangles, no shadow (§6).

One MultiMesh per kind: the whole base is about a dozen draw calls. The buildings show out to 15 km, the jets and
vehicles to 4 km, the fence to 2.5 km. Nothing collides: the flight model does not know them.

At night (Night lights = Detailed, `airbase_lights.gd`) a sodium lamp shines over each shelter's door and a red
obstruction light stands on the tower and on each hangar's ridge (inferred), with the base's other lights.

## 6. Pictures and cost

Before and after, from the same cameras, day and night, beside the Sentinel-2 picture: the approvals page, section
"Ramon filled".

The cost on the Linux laptop's Intel Iris Xe (default settings, a 1920 × 994 window, GPU time, the median of 12
frames, two runs each, 2026-11-19), against main with the same airbase data:

| camera | before | after |
|---|---|---|
| on the ground before a loop-end shelter | 12.8 ms, 440 draw calls | 10.9–13.6 ms, 462 draw calls |
| 450 m up over the technical area | 23.5–23.9 ms, 289 draw calls | 24.7–24.9 ms, 311 draw calls |

Tried and dropped (2026-11-19): the parked jets as the full model (62k triangles each, with shadows) cost 11 ms more
at both cameras (3.8 million more primitives a frame with the shadow passes). They are now the importer's simplified
copy of about 6,000 triangles and cast no shadow (they stand in the shelters' shade).

## 7. Open

- The start spots stay on the apron row ([airbases.md](airbases.md) §5). The user's rule "if there are shelters then
  start inside one" (2026-11-17) needs each spot's own taxi route: the AI taxis from every spot straight to one hub,
  and Ramon has one shelter per loop taxiway, 200–400 m apart.
- Hatzerim, Nevatim, Ramat David and Tel Nof: their surveys and furniture files.

[^wc]: ESA WorldCover 2021 Sentinel-2 RGBNIR composite, "Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium" (CC BY 4.0), https://esa-worldcover.org
[^osm]: OpenStreetMap contributors, ODbL 1.0, https://www.openstreetmap.org/copyright
