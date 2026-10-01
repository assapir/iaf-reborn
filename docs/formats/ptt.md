# map.ptt — "Sonic" streaming terrain

Addresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](../v1.1.md) maps them to v1.0 and lists what the patch changed.

`resource/terrain/map.ptt` (394 MB, read straight from the CD by the original game; `tgen.ini [Sonic] FileName`).
Loader in `iafjets.exe` (`ObjectsLayer\Terrain\*.cpp`), header check `FUN_00427360`, level setup `FUN_00429a10` /
`FUN_004296b0`, tile lookup `FUN_00422490`. All integers little-endian.

```
0x0000  "STRTH"
0x0005  header struct (0x1020 bytes)
          +0x00 u32  version = 4
          +0x04 u32  log2(tile pixels) = 7  → 128×128 tiles
          +0x1c u32  length of the JPEG tables stream (0x23e)
          +0x20      JPEG "tables-only" stream (SOI, 2×DQT, 4×DHT, EOI) shared by all tiles
0x1025  u32  level record count (57)
0x1029  records, 0x2c bytes each (11 × u32):
          x0, y0, x1, y1   extent in world units (1 unit = 1/1024 of the engine's position units)
          level            tile side = 2^(level + 7) units
          offset           absolute offset of this record's tile index
          flag             1 = whole-theatre level, 0 = high-detail inset
          (4 × u32 unused)
```

Levels: 11..6 cover the theatre (0,0)-(655360, 851968) (levels 11/10 slightly larger); 51 inset records at levels
5..0 cover smaller areas (airbases / target areas) at up to 2^7 = 128 units per tile.

## Tile index (at `offset`)
`columns = ceil((x1-x0) / span)`, `rows = ceil((y1-y0) / span)`; `columns × rows` entries of 8 bytes, **row-major**
(`index = row * columns + column`, row 0 = north / top of the image):

```
u32  tile data offset, relative to the record's `offset`
u16  JPEG size
u16  elevation block size (follows the JPEG)
```

## Tile data
- **Colour**: abbreviated baseline JPEG (SOI, SOF0 128×128 YCbCr 4:2:0, SOS…EOI) without tables — splice the shared
  tables in to decode.
- **Elevation**: LZO1X-compressed (`FUN_0042b8f0` → `FUN_0042c7e0` = `lzo1x_decompress`) to 128×128 **u16**, row-major;
  each row is **delta-coded along x** (prefix-sum to decode, wrapping u16). Every theatre tile has one.
  Only the whole-theatre levels (11..6) have elevation; inset levels are colour only and the engine derives
  their heights from level 6 (`FUN_004281e0`, below). Raw range (level 7): 12593..59038.
  **Metres** (ground height `FUN_004047a0`): `((int)(raw / HeightStretchFactorPR) − 2197) × PlaneScalePR` with
  `HeightStretchFactorPR = 9.2575`, `2197 = (int)(SeaLevelPR 20342 / 9.2575)`, `PlaneScalePR = 1.2411389`, i.e.
  1.24 m steps. We use the continuous `(raw − 20342) / 9.2575 × 1.2411389` (within −0.8..+0.4 m; checked: Ramat
  David runway 63.7 m vs 63 m in takeoff.mis). Seas carry bathymetry. **No elevation west of Suez**: Egypt's
  Nile delta / Western desert and the sea north of it are a flat plane at raw 16191 = −557 m, and the missions
  put their objects there at Z = −557 (against_all_odds, Suez) — kept as the original.
  Other defaults: `DataXShiftPR = -166850`, `DataYShiftPR = 1043780`.

### Level records in the file
| records | level | area (terrain units) | what |
|---|---|---|---|
| 0–5 | 11..6 | whole theatre 655360 × 851968 (11/10 larger) | colour + elevation |
| 6, 7 | 5, 4 | 327680,262144–524288,630784 | Israel |
| 8, 9 | 5, 4 | 491520,172032–569344,229376 | southern Syria / Damascus |
| 10, 11 | 5, 4 | 524288,270336–552960,331776 | northern Jordan |
| 12, 13 | 5, 4 | 438272,172032–491520,229376 | Lebanon |
| 14, 15 | 5, 4 | 98304,442368–286720,589824 | Nile delta – Suez canal |
| 16–19 | 3 | four bands over Israel | |
| 37, 53 | 3 | Sinai airbase, Syrian airbase | |
| 20–36, 38–52, 54–56 | 2..0 | 13 small areas | airbases (Israel, Jordan, Sinai, Syria) |

## FUN_004281e0: inset heights
Source: always the finest theatre level, **level 6** (at load `FUN_00427360` gives every inset the first flag-1
record that contains it). With `d = 6 − L`, sample *i* of an inset of level L lies at world `i·2^L` (corner
aligned; all 51 inset origins are multiples of their tile span). The level-6 samples are spread `2^d` apart and
refined in `d` halving passes, each new sample the `>> 1` average of two coarser ones along x, along y, or along
the **north-west → south-east diagonal** — i.e. linear interpolation over the triangles of each level-6 texel
square split along that diagonal. Edges take the neighbouring tile's first row / column (missing neighbour:
clamped). The sea is not flattened.

## Rendering in the original (v1.1)
- **Renderer**: software, row by row away from the viewer (`FUN_004095b0` / `409b70` / `409810`): row step
  `Δd = (int)(d / (150·k) + 1)`; each row takes `level = FUN_00408e60(row distance)` and samples height and colour at
  the nearest pixel per screen column (`FUN_004245e0`); exponential fog (`423db0`). No mesh, so no cracks or
  skirts (levels pop between rows).
- **Level vs distance** (`FUN_00408ea0(detail)`, metres; the level actually drawn is the finest record covering the
  point at that level or coarser whose tile is decoded — insets and theatre alike, `FUN_00421fd0`):

  | detail | level by distance |
  |---|---|
  | 0 | 8 everywhere |
  | 1 | <390/800/2200/4400 → 4, <8000 → 5, <12000 → 6, <50000 → 7, <80000 → 8, <100000 → 9 |
  | 2 | <420/850/2500 → 3, <5100 → 4, <9500 → 5, <17000 → 6, then 7/8/9 at 50/80/100 km |
  | 3 | <100 → 0, <460 → 1, <930 → 2, <2900 → 3, <5700 → 4, <11000 → 5, <22000 → 6, then 7/8/9 |
  | 4 | <200 → 0, <500 → 1, <1000 → 2, <3200 → 3, <6400 → 4, <12800 → 5, <25600 → 6, <50000 → 7, <100000 → 8, beyond 9 |
  | 5 | <300 → 0, <700 → 1, <1200 → 2, <3300 → 3, <6600 → 4, then as 4 |

  **v1.1** ("two highest settings tuned"): details 4 and 5 end with level 8 from 50 to 100 km (v1.0: 7 to 50 km,
  8 to 80 km, 9 to 100 km). TERRAIN DETAIL slider (Graphics page) = 0.25 steps, capped at
  `(0x779508 − 1)·0.25` where `0x779508` = RAM/10 below 61 MB (32 MB → 3, 48 MB → 4) else 5 (`FUN_00407670`);
  detail = 1 + 4·slider (UNCERTAIN). The "renderer angle 8°→5.5°" of the v1.1 notes (`585270`) is AI code, not
  terrain.
- **View distance** (`FUN_00408070`, per frame): `min(100000, (AGL·1e-4 + 0.7) × base)` terrain units, base =
  26000..31000 m / PlaneScale for detail 1..5 (`405c20`) — about 21 km on the ground, 30 km at 3 km AGL.
  **`tgen.ini [Render] farClipping=25000` is never read** (the string is in no binary); 25000 is only the prefs
  default. Hardware near / far planes 4 / 22000 (60000 above 7000 m, `404580`), probably for objects.
- **Streaming** (`407590` → `421ee0` → `42a2b0`): per level a window of (2R+1)² tiles around the camera, R per
  level and cache sizes from the RAM (`407670`: ≥111 MB: R = 3 for levels 0–7, 2 / 3 / 3 / 2 for 8–11; decoded
  cache 24 MB = 292 tiles of 81920 bytes; decode budget 400000 bytes per frame).
- **Ground height** (`FUN_004047a0`, physics): within 7000 units of the stream centre, the finest decoded tile at
  the point, nearest pixel, `(3·C + W + E + N + S) / 7` of the metre values at ±2 pixels; elsewhere level 3,
  one sample. Height + normal (`4045e0`): offsets 5 px, `normal = normalize(W−E, N−S, 10·2^L)`.

## Converted layout (`iaf-terrain theatre`)
`iaf-terrain theatre <map.ptt> <out> [threads]` (run by `tools/setup.sh`, output
`assets/converted/terrain/theatre`) converts **every level and every inset**: a quadtree of nodes on a grid
aligned to the theatre origin. A node of level L covers `1024·2^L` units with a 1024² colour JPEG (q 90) at
`2^L` units per pixel, the resolution of map.ptt level L: `L<L>/c_<i>_<j>.jpg` covers units
`[i, i+1) × [j, j+1) · 1024·2^L`.
- **Theatre levels 6..11**: every node inside the theatre (130 / 35 / 12 / 4 / 1 / 1), mosaicked from that
  level's own tiles, plus `L<L>/h_<i>_<j>.png`: that level's raw u16 heights, 1025² (the extra row / column from
  the neighbour, the theatre's east / south edge repeated), packed R = high byte, G = low byte.
- **Inset levels 5..0**: every node an inset record of exactly that level touches (L5 115, L4 430, L3 845,
  L2 64, L1 173, L0 532). Painted coarse to fine: level 6, then the insets of levels 5..L over it (starting at
  the finest record that covers the whole node), each mosaicked at its own resolution with 4 source pixels of
  margin and Lanczos-resampled to 2^L units per pixel, so neighbouring nodes match exactly. No heights: the
  runtime uses level 6 (FUN_004281e0).
- The runway-number fixes are applied to the nodes of levels 0..2 at their own resolution.
- `meta.json`: theatre rect, `node_pixels`, `height_level` 6, `root_level` 11, the node list per level,
  georeference (below).

2342 nodes, **732 MB**, **30 s** on 8 threads (the file itself: 394 MB). Engine world metres from terrain
units (`FUN_004053f0`): `X = tx·1.2411389 − 166850`, `Y = 1043780 − ty·1.2411389`.

## Rendering here (game/terrain/terrain.gd, terrain.gdshader)
- A node splits into its four children while the focus is nearer than `split_factor` (1.5) × its side, scaled
  by the TERRAIN DETAIL slider with the ratios of the original's tables (0.69 / 0.78 / 0.91 / 1 / 1.03 for detail
  1..5); geometry splits down to level 2 everywhere, finer only where finer imagery exists. Distance =
  horizontal distance to the node square combined with the height above the ground. Up to 200 km (the camera's
  far plane; fog) — ground to the horizon everywhere in the theatre. A node without its own imagery shows its
  nearest ancestor's texture (sub-rectangle).
- **Heights**: every node of level ≤ 6 samples the level-6 heights of its level-6 ancestor with the
  FUN_004281e0 triangle interpolation (vertex shader); levels 7+ their own. Nodes of levels 0..2 have one vertex
  per level-6 texel or finer (16 / 32 / 64 quads) and the same diagonal, so they draw exactly the surface of
  `height_at()` (the physics); coarser nodes 32 quads. **Skirts** (10 m + half a quad deep) hide the cracks
  between levels. The sea is drawn at the data height like the original (ships are placed on it), only shaded
  flat.
- **Streaming**: JPEG decode, mipmaps and BC1 compression on worker threads (6 at once; each takes the next
  key from the frame's nearest-first queue when it finishes, so loading does not wait for frames); a split
  waits until all four children are loaded (the parent stays drawn), deeper levels are requested at the same
  time; textures unused for 20 s are dropped. The tree is re-chosen after 100 m of movement, 0.5 s, or new data.
- **Loading**: the flight scene shows the front end's mission wait screen and starts the simulation only when
  `ground_ready()`: every node within 8 km at full detail and the heights under the jet loaded (~3 s).
- **Differences from the original** (rendering may be nicer): a mesh with vertex LOD instead of the row renderer,
  finer imagery at distance, 200 km instead of the ~21–124 km view distance, continuous heights instead of 1.24 m
  steps; the physics height is the drawn surface, not the original's 5-tap smoothed sample of the finest decoded
  tile.
- Frame rate (Intel Iris Xe, 1920×1080, vsync off, cockpit view; old = level-4 Israel rectangle + detail
  tiles): on the runway 83 → 111 fps, 1500 m 54 → 73 fps, 6000 m 37 → 60 fps.

## Terrain types (`terraintype.dat`)
784188 bytes, read by `FUN_0040a040("TerrainType.dat")` via `FUN_004261f0` (tree reader `FUN_0042ae50` /
`42ad20`): **12 serialized 2-D BSP trees** (a main tree, then one per layer 0..10), then 58 source polygons the
exe never reads. Node, pre-order: `i32 count, i32 mask, i32 has1, i32 has0`, then `4 × f64 a, b, c, d` if
`has1`, then the child1 subtree, then the child0 subtree. Lookup (`FUN_00426350`, game wrapper
`FUN_004024b0(X, Y)`): `x = trunc(X) + 0x151, y = trunc(Y) − 0x19a` (engine metres), descend
`a·x + b·y < c − d ? child0 : child1` to a leaf, return its mask:

| bit | meaning |
|---|---|
| 0x1 | land outside every polygon |
| 0x2 | inland / southern water: Red Sea, Suez and Aqaba gulfs, Dead Sea, Kinneret, Bardawil, Nile |
| 0x4 | Mediterranean |
| 0x8 | islands inside water polygons (Cyprus 0xC, Red Sea islets 0xA) |
| 0x10 | runways / airbases (10 polygons) |
| 0x40 / 0x80, 0x100 / 0x200 | outer border band, inner map-edge frame |

Users: the flight model `FUN_005bb9f0` (`f & 6` water → destroyed, `f & 0x30` runway, `f & 9` rough → destroyed
above 25.7 m/s, `f & 0x300` map edge (EndWorld.wav), `f & 0xc0` border push-back), craters (`FUN_0054a660`, none
on water) and the explosion effect (`FUN_0059df20`, the water splash). Original quirk: island leaves carry the
water bit, so touching down on Cyprus counts as water. Ported: `terrain.gd` reads the main tree from the install
at start and `surface_at(pos)` returns the mask; the flight gets water / rough every frame
(`set_ground_surface`).

## Runway number fix (rendering improvement)
**Deliberate improvement over the 1998 data** (applied to the converted nodes of levels 0..2). Rule: a runway-end number N must read upright to a pilot landing on
that end (facing heading N×10°). The terrain itself is correctly oriented (coastline, match with the coarse levels,
roads continuous across the inset edges); only some painted digits are wrong. Every runway end in the 149 detail
tiles was surveyed (crop, rotate so the landing direction points up, read the digits at 1 px resolution). The
artist's layout puts each number on the light concrete between the runway end and the threshold stripes (before
the stripes as seen by the landing pilot).

Airbases with runways in the Israel-rectangle insets (world units = old detail-tile pixel + (327680, 262144)):

| Airbase (cluster) | Runway end (landing hdg) | Number, centre (world) | Reads | Status |
|---|---|---|---|---|
| Ramat David (d_43..48_44..47) | E–W, W end (090) | 09 @ (418606, 355638) | 09 | correct |
| | E–W, E end (270) | 27 @ (421704, 355638) | 27 | correct |
| | NW–SE, NW end (150) | 15 @ (420444, 355034) | 15 | correct |
| | NW–SE, SE end (330) | 33 @ (421812, 357394) | ƐƐ | **mirrored → fixed** |
| | SW–NE, SW end (030) | 15 @ (418848, 356435) | 15 upright | wrong number (runway is 03/21), not fixable by re-sampling |
| | SW–NE, NE end (210) | 33 @ (419875, 354652) | ƐƐ | **mirrored → fixed** (number still wrong: 21) |
| Airbase at d_81..83_6..8 (single runway, far north-east) | SW end (060) | 09 @ (495057, 278580) | 09 | orientation correct, number wrong (06) |
| | NE end (240) | 27 @ (497696, 277056) | 27 | orientation correct, number wrong (24) |
| Airbase at d_88..90_40..42 (two parallel runways, east) | NW runway, SW end (055) | 09 @ (510068, 347389) | 09 | orientation correct, number wrong (05/06) |
| | NW runway, NE end (235) | 27 @ (512300, 345833) | 27 | orientation correct, number wrong (23/24) |
| | SE runway, SW end (054) | 09 @ (509752, 348248) | 09 | orientation correct, number wrong |
| | SE runway, NE end (234) | 27 @ (511886, 346756) | 27 | orientation correct, number wrong |
| Airbase at d_28..30_120..122 (two parallel runways, Negev) | NW runway, SW end (050) | 09 @ (388240, 511379) | 09 | orientation correct, number wrong (05) |
| | NW runway, NE end (230) | 27 @ (390312, 509643) | 27 | orientation correct, number wrong (23) |
| | SE runway, SW end (050) | 09 @ (388000, 512258) | 09 | orientation correct, number wrong |
| | SE runway, NE end (230) | 27 @ (389980, 510595) | 27 | orientation correct, number wrong |
| Airbase at d_27..32_84..89 (E–W + NW–SE runways) | E–W and NW–SE runways, 4 ends | — | blurred blobs (~4 units/px source) | illegible, left as is |

The two airbase insets outside the Israel rectangle (new with the full conversion) were surveyed the same way
(level-0 nodes, each end rotated so its landing direction points up):

| Airbase (inset) | Runway end (landing hdg) | Number, centre (world) | Reads | Status |
|---|---|---|---|---|
| Sinai airbase (records 37–40, L0 c_248..254_525..528) | E–W, W end (090) | 09 @ ~(255950, 539620) | 09 | correct |
| | E–W, E end (270) | 27 @ ~(259020, 539620) | 27 | correct |
| Syrian airbase (records 53–56, L0 c_509..515_173..177) | N runway, W end (101) | 09 @ ~(524250, 179320) | 09 | orientation correct, number wrong (10) |
| | N runway, E end (281) | 27 @ ~(526900, 179810) | 27 | orientation correct, number wrong (28) |
| | S runway, W end (100) | 09 @ ~(523410, 179710) | 09 | orientation correct, number wrong (10) |
| | S runway, E end (280) | 27 @ ~(525970, 180160) | 27 | orientation correct, number wrong (28) |

No mirrored or rotated digits there, so the fixes file is unchanged. Airbases that appear only in the level 3+
imagery (Egypt, Jordan, Lebanon, Syria) show runway numbers at ≤ 1 pixel: nothing to read.

The other clusters (Tel Aviv, Ashdod, Haifa, Jerusalem, the small desert site at d_26..27_133) have no runway with
painted numbers inside the insets. The artists evidently re-used one runway-end template (09/27, 15/33) whatever
the real runway heading; the numbers are left as painted (replacing them would mean inventing digits).

**Mirror vs 180° rotation.** "33" looks the same mirrored or rotated, and no asymmetric digit is wrong anywhere
(all 09/27/15 are upright), so the artist pattern cannot decide. The glyph shape does: in the painted "ƐƐ" the
middle stroke sits at ~0.37–0.40 of the glyph height from the far (top) end, i.e. the small bowl is at the top as
in a normal "3" (and close to the artist's "5", 0.46). A 180° rotation would put the small bowl at the bottom, so
both are fixed as **mirror images** (reflection across the runway centreline). `op` can be switched to `rotate180`
in the data file if this turns out wrong.

**How it is applied.** The fixes are data: `crates/iaf-tools/data/runway_number_fixes.json` (embedded in the tool;
`iaf_tools::runway_fix`). Each fix is a rectangle in world units aligned with the runway: centre (the digit pair's
centre, which lies on the runway centreline; heading measured between the digit centres at the two ends of the
runway, ±0.05°), half size 14 across × 10 along (the digits are ~22 × 15 px, the runway ~55 px wide, so the rim is
plain runway surface), and the operation. After a node of level 0..2 is composed and before JPEG encoding, every
fix whose rectangle touches it is applied at the node's resolution: the unmodified imagery around the patch is
composed separately on the node's pixel lattice (so a patch straddling a node border is identical on both
sides), each pixel in the rectangle is bilinearly re-sampled at its mirror point, and blended with a 2-unit
linear feather at the rectangle edge. The two tyre-mark tracks along the centreline map onto themselves, so no seam is visible.
