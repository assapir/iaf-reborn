# Georeference: the original world frame ↔ WGS84

This page describes the warp between the 1998 game frame and WGS84 (World Geodetic System 1984, the lat/lon datum
of GPS and of every modern map). Modern imagery uses it to land on the right game ground.

Key facts:

- **The game frame.** The 1998 theatre is a planar frame. It uses map.ptt terrain units `tx` (east) and `ty`
  (south). Engine metres are `X = tx·1.2411389 − 166850`, `Y = 1043780 − ty·1.2411389` (docs/formats/ptt.md).
- **Real size, irregular shape.** The frame shows real geography at real size: engine metres ≈ real metres. Over the
  control-point pairs more than 50 km apart the ratio is ×0.99–1.01 (5th–95th percentile), median 1.00. The frame
  matches no map projection, and its shape distortion varies from place to place.
- **The warp.** Every modern source is in lat/lon, so modern imagery needs a **warp**: `iaf_tools::georef` (Rust,
  `crates/iaf-tools/src/georef.rs`). It is fitted to the control points in
  `crates/iaf-tools/data/georef_points.json` (coordinates only, our own measurements).
- **Direction.** Modern imagery is warped **into** the game frame. The game frame (missions, insets,
  terraintype.dat, heights) stays fixed.

## 1. Model

The warp is a smoothed thin-plate spline with an exact numerical inverse.

- **Forward:** a **thin-plate spline** maps terrain units → (lon, lat), with smoothing λ = 0.1. Inputs are in
  level-6 node units (65536 terrain units = 81 km); outputs are in degrees. A 5-fold hold-out (§3) picked λ: 0.03 /
  0.1 / 0.3 give hold-out 95th percentiles of 152 / 108 / 138 m on the level-6 points.
- **Inverse:** (lon, lat) → terrain units by Newton iteration on the spline, starting from the inverse of the
  spline's affine part. The round trip is exact (< 1 mm; test `committed_points_fit_and_round_trip`).
- **Use in converters:** they evaluate the spline on a coarse grid per node and interpolate bilinearly. The spline
  is smooth at that scale.

## 2. Control points (automatic)

A developer tool measures the control points once; its output is committed:

`iaf-terrain georef-points <theatre-dir> <eox-z9-dir> <eox-z10-dir> <out.json> <lambda>`

**Reference imagery.** The reference is **EOxCloudless 2017** (CC BY 4.0, "EOxCloudless https://cloudless.eox.at
by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2017)"). The tiles come from the WMTS (Web Map
Tile Service) `WGS84` tile matrix set over lon 29.5–38.6, lat 26.8–37.0:

| level | resolution | tiles | size |
|---|---|---|---|
| 9 | 150 m/px | 808 | 9.4 MB |
| 10 | 76 m/px | 3128 | 35 MB |

They are fetched once into the developer's scratch directory. They are not committed and setup does not need them:
`https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2017/default/WGS84/{z}/{row}/{col}.jpg`.

**Method** (`crates/iaf-tools/src/georef_measure.rs`):

1. Build luminance mosaics of the original theatre level (converted nodes) and of the reference. High-pass both:
   subtract a box mean of 6 original pixels. This keeps edges and texture and drops the colour difference between
   1998 and 2017.
2. On a regular grid, compare a 64² patch of the original with the reference by **normalised cross-correlation**
   (NCC). The reference is resampled into the original's pixel grid through the current warp (local affine). The
   search covers shifts of ± margin pixels; a parabola gives the sub-pixel peak. A match needs all three of:
   - NCC ≥ 0.35;
   - the peak inside the search window;
   - every score more than 2 px away (wide high-pass: radius/3) at least 0.08 lower. This rejects a straight coast
     or a repetitive texture.
3. Run passes from coarse to fine. Each starts from the previous fit:
   1. level 7 vs z9, 40 km grid, ±40 px. The start is a bilinear fit of the theatre corners
      (docs/imagery-research.md §1);
   2. level 7, 16 km grid, ±8 px;
   3. level 6 vs z10, 12 km grid, ±6 px, then ±3 px;
   4. a **level-8 pass** (318 m/px, 20 km patches, high-pass radius 16 so that the land / sea contrast counts). It
      fills the areas the original paints coarsely (Cyprus, the southern Sinai / Red Sea coasts). Its matches with
      NCC ≥ 0.5 are added where no level-6 match lies within 16 km.
4. After each pass, fit a smoothed spline. Drop points whose residual exceeds 3× the median (at least 300 / 150 /
   80 / 60 m per pass; 4× that for level-8 matches). Repeat until no point exceeds it.

**Result: 610 points** (577 level-6, 33 level-8):

| region | points |
|---|---|
| Israel | 138 |
| Sinai | 46 |
| Nile delta / Suez | 44 |
| Jordan | 148 |
| Syria | 147 |
| Lebanon | 22 |
| Cyprus | 4 |
| NW Saudi Arabia | 16 |

The Western Desert and Upper Egypt have no points: there the original is **painted** (smooth synthetic sand and a
schematic Nile, with no real texture to match). The warp extrapolates there.

## 3. Residuals

Where level-6 points are dense (Israel, Jordan, Syria, Lebanon, the delta), the warp is good to about half a
level-6 pixel. Isolated coarse points are much worse. The data file gives each point's residual as
`residuals_m()` = |to_game(lon, lat) − (tx, ty)| · 1.2411389 m. That is how far the warp puts the real ground from
where the original shows it, in game metres. For scale, the level-6 pixel is 79 m.

| set | rms | median | 95 % | max |
|---|---|---|---|---|
| fit residual, all 610 points | 40 m | 20 m | — | 238 m |
| 5-fold hold-out (each point predicted without itself) | 216 m | 37 m | 217 m | 2087 m |

The large hold-out values come from the isolated coarse points: removing one leaves a hole of 50+ km.

| point | hold-out error |
|---|---|
| 27.37 N 34.08 E (Red Sea) | 2087 m |
| 27.38 N 35.66 E | 1728 m |
| 29.04 N 34.71 E (Gulf of Aqaba) | 1640 m |
| 35.09 N 32.43 E (Cyprus, Cape Arnauti) | 1562 m |
| 27.66 N 33.44 E | 1557 m |
| 28.77 N 32.79 E | 1465 m |
| 34.53 N 33.11 E (Cyprus, Akrotiri) | 1390 m |
| 35.36 N 34.06 E (Cyprus, Karpass) | 872 m |

The tool prints the per-point residuals, and the test bounds them (rms < 80 m, 95th percentile
< 150 m).

## 4. Airbases are not at their real positions (validation)

Most game airbases sit kilometres from the real ones, by design. So airbases cannot serve as control points.

The task suggested airbase runways as control points. The table puts the ten iaf.ibx airbases (LineupLoc, engine
metres) through the warp and compares them with the real airbase (OpenStreetMap aerodrome centre, Overpass query
2026-10-01):

| iaf.ibx base | warp of the lineup point | real airbase | distance km |
|---|---|---|---|
| Ramon | 30.887 N 34.821 E | Ramon AB 30.764 N 34.671 E | 19.8 |
| TelNof | 31.691 N 34.769 E | Tel Nof AB 31.836 N 34.823 E | 16.9 |
| David | 32.610 N 35.228 E | Ramat David AB 32.666 N 35.180 E | 7.7 |
| Refidim | 30.552 N 33.094 E | Bir Gifgafa 30.414 N 33.156 E | 16.4 |
| Inshas | 30.431 N 31.228 E | Inshas AB 30.326 N 31.456 E | 24.8 |
| Damescuss | 33.486 N 36.223 E | Mezzeh 33.479 N 36.226 E | 0.8 |
| Kuzeir | 34.572 N 36.598 E | Al Qusayr AB 34.566 N 36.575 E | 2.3 |
| Bley | 32.719 N 36.413 E | Khalkhalah AB 33.081 N 36.562 E (?) | 42.5 |
| Ryak | 34.047 N 36.168 E | Rayak AB 33.850 N 35.989 E | 27.4 |
| Aman | 31.731 N 36.004 E | Queen Alia Intl 31.724 N 35.995 E | 1.2 |

What the table shows:

- **The warp is right.** Mezzeh, Al Qusayr and Queen Alia agree to 1–2 km; the lineup point is at a runway end, the
  OpenStreetMap point at the centre. Other places confirm it too: Ashdod port in the original level 6 maps to
  31.831 N 34.642 E, the real port.
- **The designers placed the other bases by choice.** The game's "Tel Nof" inset is 17 km south of the real base,
  "Ramon" 20 km north-east, and so on. This is consistent with the "base distances 0.75–1.13 of real" in
  docs/roadmap.md.
- **Consequence:** a modern layer must **keep the original imagery at the game's airbases** (docs/imagery.md §3).
  Otherwise the mission's airbase would sit in empty modern desert, with the real base kilometres away.

## 5. Use

API and commands:

- `iaf_tools::georef::Georef::load()` → `to_geo(tx, ty)`, `to_game(lon, lat)`, `residuals_m()`, and in engine
  metres `engine_to_geo(X, Y)` / `geo_to_engine(lon, lat)`.
- `iaf-terrain geo <points.json> <X> <Y>`: engine metres → lat, lon (for checks like §4).
- `iaf-terrain game <points.json> <lat> <lon>`: the inverse, lat, lon → engine metres `X Y`. Use it, for example,
  to start a capture over a real place: `--at X Y alt heading pitch`. Example: Mezzeh 33.479 36.226 →
  `451063.7 699129.0`.

To re-measure the control points:

1. Fetch the two EOX levels (a `curl --parallel` over the tile list).
2. Run `georef-points`.
3. Review the printed residuals.
4. Commit the JSON.
