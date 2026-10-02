# 3D models — DirectX .X (binary)

All 3D objects are Microsoft DirectX `.X` files in binary form (`xof 0302bin 0032` / `xof 0303bin 0032`, 32-bit floats),
exported from 3D Studio with the "x3ds" exporter (names prefixed `x3ds_` / `x3ds_mat_`).

Per aircraft folder (`resource/3dobjects/controllableplanes/<plane>/`):

| file | contents |
|------|----------|
| `<p>_h.xfr` | "frame file": materials + frame hierarchy with per-part meshes (high detail). Used for animation. |
| `<p>_h.x`, `_m.x`, `_l.x` | single merged mesh, high / medium / low LOD, inline materials |
| `<p>_bc.x` | the jet's exterior as seen from its own cockpit (`bc<p>.bmp` = seat back; bdb Objects `0x546`, shown in the cockpit views) — not a damaged model (docs/damage.md §2.2) |
| `*.bmp` | 8-bit paletted textures; palette colour **(0,255,255) cyan = transparent** |
| `*.tga` | 32-bit RGBA textures (cockpit glass) |
| `<p>_h.rtf` | reference card (dimensions, weights, performance) |
| `error.c` | leftover dev log: `F16_h.xfr: Scale=5.000 ActualDiameter=75.069` |

## Frame names (F-16)
Moving parts: `AilerL/R`, `ElevaL/R`, `RuddeL`, `SpdbrU/D`, `LdgF/L/R`, `LdgDr`, `Canopy`, `Hook`, `EngineL`, `pilot`, `pilotB`.
Each moving part `X` has helper frames `X1`, `X2` with a single tiny triangle — likely the hinge axis end points.
Other helpers: `Camera` (pilot eye), `height`, `EndWingL/R`, `StationA..I`, `StationGun`, `StationFla` (weapon/flare stations).

## Conversion notes
- Direct3D is left-handed: mirror Z and reverse triangle winding for glTF (checked against stored normals: >99% agree).
- `FrameTransformMatrix` memory layout (row-major, row vectors) equals glTF's column-major layout; conjugate by diag(1,1,-1).
- Face normals are per-corner (`MeshNormals` has its own face index list) — vertices are split per (position, normal).

## Texture coordinates and textures
- `MeshTextureCoords` holds one (u, v) per **vertex** (count = vertex count in every shipped model), origin top left —
  the same convention as glTF, so the converter copies them unchanged (no V flip).
- Values outside 0..1 occur (Lavi `lavi_h.x`/`.xfr`: u −0.883..1.0, v −0.864..1.002; also `ElevaR`, `Rudde`). The
  models are loaded through Direct3D Retained Mode (meshbuilder `Load`, `ClumpsLoad.cpp`, texture callback
  `FUN_0040dc70`), whose texture address mode is the D3D default WRAP; the glTF sampler uses REPEAT (10497) to match.
- `.xfr` = the same `_h` mesh split into the part frames (`FUN_00588ea0`, [part-animation.md](../part-animation.md));
  its UVs equal the merged `_h.x`'s. Textures are 8-bit BMPs keyed on cyan, except the canopy glass: a 32-bit `.tga`
  (e.g. `laviipit.tga`: white, alpha ≈ 0.25). `FUN_0040de10` loads the TGA when the device has an alpha texture
  format and otherwise swaps the extension to `.bmp` (the opaque 8-bit sky-reflection version; "Can't use alpha
  channel"). We use the hardware path (the TGA).
- Checked 2026-10: a software render of every model the bdbs reference straight from the `.x`/`.xfr` (nearest, WRAP)
  matches the converted glTF texel for texel apart from `--smooth` silhouettes and the 4× texture upscale.
  The Lavi's desert camouflage (plain brown nose top, side strip with the red line, grey-white glass) is the
  original's own `lavi_h.bmp` as the model maps it (the ref photos `ref/lavi/*.bmp` show the real white prototype).
