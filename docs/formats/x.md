# 3D models — DirectX .X (binary)

Every 3D object in the game is a Microsoft DirectX `.X` file in binary form, with 32-bit floats. The header is
`xof 0302bin 0032` or `xof 0303bin 0032`. The models were exported from 3D Studio with the "x3ds" exporter, so their
names start with `x3ds_` or `x3ds_mat_`. This page lists the files per aircraft, the frame names, and what the
converter to glTF (the GL Transmission Format, which Godot loads) must do. Parser: `crates/iaf-formats/src/xfile.rs` / `model.rs`;
converter: `crates/iaf-tools/src/gltf.rs` (`iaf-convert model`).

Each aircraft has a folder `resource/3dobjects/controllableplanes/<plane>/` with these files (LOD = level of
detail):

| file | contents |
|------|----------|
| `<p>_h.xfr` | "frame file": materials plus the frame hierarchy, each part with its own mesh (high detail). Used for animation. |
| `<p>_h.x`, `_m.x`, `_l.x` | one merged mesh with inline materials: high / medium / low LOD |
| `<p>_bc.x` | the jet's exterior as seen from its own cockpit, shown in the cockpit views (`bc<p>.bmp` = seat back; bdb Objects `0x546`). It is a cockpit-view model; an old guess that it is a damaged model was wrong (docs/damage.md §2.2) |
| `*.bmp` | 8-bit paletted textures; palette colour **(0,255,255) cyan = transparent** |
| `*.tga` | 32-bit RGBA textures (cockpit glass) |
| `<p>_h.rtf` | reference card (dimensions, weights, performance) |
| `error.c` | leftover developer log: `F16_h.xfr: Scale=5.000 ActualDiameter=75.069` |

## Frame names (F-16)
The F-16's frame file names its parts as follows.

- **Moving parts:** `AilerL/R`, `ElevaL/R`, `RuddeL`, `SpdbrU/D`, `LdgF/L/R`, `LdgDr`, `Canopy`, `Hook`, `EngineL`,
  `pilot`, `pilotB`.
- **Hinge helpers:** each moving part `X` has helper frames `X1` and `X2`. Each holds one tiny triangle; they are
  likely the end points of the hinge axis.
- **Other helpers:** `Camera` (the pilot's eye), `height`, `EndWingL/R`, `StationA..I`, `StationGun`, `StationFla`
  (weapon and flare stations).

## Conversion notes
Direct3D is left-handed and glTF is right-handed. The converter does three things:

1. It mirrors Z and reverses the triangle winding. A check against the stored normals agrees on >99% of faces.
2. It conjugates each `FrameTransformMatrix` by diag(1,1,-1). The matrix's memory layout (row-major, row vectors)
   equals glTF's column-major layout, so no transpose is needed.
3. It splits vertices per (position, normal). Normals are stored per face corner: `MeshNormals` has its own face
   index list.

## Texture coordinates and textures
- **UV origin.** `MeshTextureCoords` holds one (u, v) per **vertex**; the count equals the vertex count in every
  shipped model. The origin is top left, the same convention as glTF, so the converter copies the values unchanged
  (no V flip).
- **Values outside 0..1.** These occur in the Lavi `lavi_h.x`/`.xfr` (u −0.883..1.0, v −0.864..1.002) and in
  `ElevaR` and `Rudde`. The game loads the models through Direct3D Retained Mode (meshbuilder `Load`,
  `ClumpsLoad.cpp`, texture callback `FUN_0040dc70`). Its texture address mode is the D3D default, WRAP. To match,
  the glTF sampler uses REPEAT (10497).
- **`.xfr` files.** An `.xfr` holds the same `_h` mesh split into the part frames (`FUN_00588ea0`,
  [part-animation.md](../part-animation.md)). Its UVs equal those of the merged `_h.x`.
- **Texture formats.** Textures are 8-bit BMPs with cyan as the transparent key. The canopy glass is the one
  exception: a 32-bit `.tga` (e.g. `laviipit.tga`: white, alpha ≈ 0.25). `FUN_0040de10` loads the TGA when the
  device has an alpha texture format. Otherwise it swaps the extension to `.bmp` and loads the opaque 8-bit
  sky-reflection version ("Can't use alpha channel"). We use the hardware path (the TGA).
- **Verification (2026-10).** We rendered in software every model the bdbs reference, straight from the `.x`/`.xfr`
  (nearest, WRAP). It matches the converted glTF texel for texel, apart from the `--smooth` silhouettes and the 4×
  texture upscale. The Lavi's desert camouflage (plain brown nose top, side strip with the red line, grey-white
  glass) is the original's own `lavi_h.bmp` as the model maps it. The reference photos `ref/lavi/*.bmp` show the
  real prototype, which is white.
