# map.ptt — "Sonic" streaming terrain

`resource/terrain/map.ptt` (394 MB, read straight from the CD by the original game; `tgen.ini [Sonic] FileName`).
Loader in `iafjets.exe` (`ObjectsLayer\Terrain\*.cpp`), header check `FUN_00427220`, level setup `FUN_00429940` /
`FUN_004295e0`, tile lookup `FUN_00422450`. All integers little-endian.

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
- **Elevation**: LZO1X-compressed (`FUN_0042b860` → `FUN_0042c750` = `lzo1x_decompress`) to 128×128 **u16**, row-major;
  each row is **delta-coded along x** (prefix-sum to decode, wrapping u16). Every theatre tile has one.
  Only the whole-theatre levels (11..6) have elevation; inset levels are colour only and the engine derives
  their heights from the level above (`FUN_004280a0`). Raw range (level 7): 12593..59038. Game constants: `SeaLevelPR = 20342`, `HeightStretchFactorPR = 9.2575`
  → probably `metres = (raw - 20342) / 9.2575` (gives −837..+4180 m; seas include bathymetry) — to be verified
  against real peaks once the map is georeferenced. Other defaults: `DataXShiftPR = -166850`, `DataYShiftPR = 1043780`.

## Airbase detail tiles
`iaf-terrain details <map.ptt> 7 <out>` (run by `tools/setup.sh`) writes `d_<gx>_<gy>.jpg`, 2048×2048 px at 1 unit
per pixel (x east, y south), for every 2048-unit cell of the level-4 grid touched by a level 0–2 inset (149 tiles),
plus `details.json` (`base_rect`, tile list). Each tile is painted coarse to fine: level 4, then every inset of level
3..0 covering it, Lanczos-resampled to 1 unit/px. Cell (gx, gy) covers world units
`base_rect[0] + gx·2048 … +2048`, `base_rect[1] + gy·2048 … +2048`.

## Runway number fix (rendering improvement)
**Deliberate improvement over the 1998 data.** Rule: a runway-end number N must read upright to a pilot landing on
that end (facing heading N×10°). The terrain itself is correctly oriented (coastline, match with the coarse levels,
roads continuous across the inset edges); only some painted digits are wrong. Every runway end in the 149 detail
tiles was surveyed (crop, rotate so the landing direction points up, read the digits at 1 px resolution). The
artist's layout puts each number on the light concrete between the runway end and the threshold stripes (before
the stripes as seen by the landing pilot).

Airbases with runways in the detail tiles (world units = detail pixel + `base_rect` origin (327680, 262144)):

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
plain runway surface), and the operation. After a tile is composed and before JPEG encoding, every fix whose
rectangle touches the tile is applied: the unmodified imagery around the patch is composed separately (so a patch
straddling a tile border — the NE-end "33" crosses d_44_45/d_45_45 — is identical on both sides), each pixel in the
rectangle is bilinearly re-sampled at its mirror point, and blended with a 2-unit linear feather at the rectangle
edge. The two tyre-mark tracks along the centreline map onto themselves, so no seam is visible. All other tiles are
byte-identical to the unfixed output.
