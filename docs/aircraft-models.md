# Detailed aircraft models

The switch **Preferences → Graphics → MORE → Models** (also on the Extras page) picks the look of the
aircraft:

| choice | what you see |
|---|---|
| **Original** (default) | the 1998 models from your install |
| **Detailed** | our detailed model where one exists; every other aircraft keeps its original model |

The switch changes the look only. Stores, the gun, the flight model, damage and the cockpit view work as with the
original models. docs/deviations.md lists it.

Today one detailed model exists: the **F-16D** (`game/extra/models/f16/f16d.glb`). It is used for the player's F-16,
the AI's F-16s, parked F-16s and the Reference viewer. Plans for more jets and for detailed stores:
[graphics-research.md](graphics-research.md) §3.7 and §3.13.

## 1. The F-16D model

| item | value |
|---|---|
| source | FlightGear F-16 (`github.com/NikolaiVChr/f16`), GPL-2.0-or-later; credits and changes in `game/extra/models/f16/SOURCES.md` |
| triangles | 46 700 (original: 7 200); runtime LODs cut far jets to a fraction |
| textures | livery, occlusion / roughness / metallic and normal maps at 2048²; the nozzle, cockpit, seat and pilot textures at 512 px or less; KTX2 inside the glb (about 110 MB in video memory as RGBA8) |
| file size | 3.7 MB |
| livery | IAF desert camouflage, 101 Squadron, tail 547 (FlightGear's own livery) |
| crew | two pilots on two ACES II seats under a two-seat canopy |

### 1.1 How it fits the game

The game reads positions from the aircraft model. The detailed model keeps them all:

- **Helpers at the original's positions** (within 1 cm): the `Station*` pylon points, `StationGun`, `StationFla`,
  `Camera` (the eye), `EndWingL/R` and `height` (where the wheels touch). The pylon meshes were moved so stores hang
  where they hang on the original.
- **The descriptor stays the original's** (`aircraft.json` from your install). `AircraftModel.detailed_descriptor()`
  takes three things from the detailed model:
  1. each moving part's hinge axis, from its own `<part>1/2` helpers;
  2. the afterburner position and radius, from its `EngineL` / `EngineL1` helpers at the nozzle's exit (the
     original's nozzle ends 0.26 m further aft);
  3. the closed gear doors `LdgDrUp` (part id 0x94, ours), shown only while the gear is fully up.
- **Moving parts** keep the original's names: AilerL/R (flaperons), ElevaL/R, RuddeL, SpdbrU/D, Hook, LdgF, LdgL/R,
  LdgDr, Canopy, pilot, pilotB. Each turns about FlightGear's own hinge line, so the surface moves where it is. The
  hinge lines differ from the original's by up to 0.8 m (the hook) and 11° (the stabilators' anhedral);
  `tests/godot/test_detailed_models.gd` prints the offsets.
- **Wheels** stay fixed, as on the original (docs/part-animation.md).

### 1.2 Loading

`util/gltf.gd` maps the original file `f16_h.gltf` to the detailed glb (`DETAILED`) while the switch is on.
`open_detailed()` parses the glb once and shares it between all jets, so the textures are in video memory once.
It also builds LODs for every mesh (`ImporterMesh.generate_lods`).

KTX2: Godot 4.7.2's runtime glTF loader reads `KHR_texture_basisu` and decodes it to RGBA8 with the mipmaps stored
in the file. The KTX2 files keep the glb small; in video memory the textures are uncompressed RGBA8 (about 110 MB for the
model's set).

## 2. Rebuilding the F-16D

You need Blender 4 or 5, `basisu` (`brew install basis_universal`), a FlightGear F-16 checkout and your converted
install (`tools/setup.sh`):

```sh
git clone --depth 1 https://github.com/NikolaiVChr/f16.git /tmp/f16
blender -b --python tools/f16d/rig.py -- /tmp/f16 assets/converted/planes/f16/f16_h.gltf game/extra/models/f16/f16d.glb
```

`F16D_FAST=1` skips the occlusion bake (about 1 minute) for quick geometry tries. `F16D_DEBUG=1` prints every
object's bounds. The script uses `tools/plane/kit.py` (`import_ac` reads FlightGear's AC3D files) and
`tools/plane/glb_ktx2.py` (the KTX2 pass).

The script:

1. imports `f16.ac` (FlightGear's single-seat F-16C) and the GE nozzle, and drops the parts the game draws itself
   (flames, lights, USAF markings);
2. makes it two-seat: everything above the canopy sill between the front seat and the fin root is stretched so the
   canopy ends 0.95 m further aft; a second tub, seat and pilot go 0.98 m behind the first;
3. moves it 1.05 m aft so its wing lies on the original's wing;
4. moves each pylon onto the original's station and compresses the oleos so the wheels touch at `height`;
5. opens the main gear doors for LdgDr and closes the nose door for LdgDrUp;
6. joins the parts, puts each origin on its hinge, adds the helpers;
7. makes the maps: occlusion baked in Cycles, a normal map from the livery's thin dark lines (panel lines, rivets),
   roughness from the lines and the occlusion;
8. exports the glb and re-encodes its textures as KTX2.

## 3. Checks

- `tests/godot/test_detailed_models.gd` (run by `tools/test.sh`): with the switch off the F-16 is the original
  model; with it on the detailed model loads once, has LODs and its textures, has every node of the original,
  keeps the helpers within 1 cm, has every mesh inside the original's bounds + 1 m, has every part touching the body,
  has the afterburner ring on the nozzle's exit, animates (gear, doors, speed brakes, flaperons), and flies as the
  player's and the AI's jets in mission 231.
- `tests/godot/_model_shot.gd` (needs a window): real renders from outside, Original and Detailed, airborne with
  stores or on the ground. Pictures go to `assets/converted/research/f16d/`.

## 4. Open

- The cockpit view's own-jet model (`own_bc`, the original's `f16_bc`) stays the original's with the switch on.
- The livery's fuselage sides are stretched (FlightGear's UVs project from above and below).
- The canopy glass is plain tinted glass; the stores are the 1998 models (graphics-research.md §3.13).
