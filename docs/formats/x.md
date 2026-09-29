# 3D models — DirectX .X (binary)

All 3D objects are Microsoft DirectX `.X` files in binary form (`xof 0302bin 0032` / `xof 0303bin 0032`, 32-bit floats),
exported from 3D Studio with the "x3ds" exporter (names prefixed `x3ds_` / `x3ds_mat_`).

Per aircraft folder (`resource/3dobjects/controllableplanes/<plane>/`):

| file | contents |
|------|----------|
| `<p>_h.xfr` | "frame file": materials + frame hierarchy with per-part meshes (high detail). Used for animation. |
| `<p>_h.x`, `_m.x`, `_l.x` | single merged mesh, high / medium / low LOD, inline materials |
| `<p>_bc.x` | alternative mesh with `bc<p>.bmp` texture (likely damaged/burnt) |
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
