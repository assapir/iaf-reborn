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
