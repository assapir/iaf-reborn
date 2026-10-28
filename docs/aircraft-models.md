# Detailed aircraft models

The switch **Preferences → Graphics → MORE → Models** (also on the Extras page) picks the look of the
aircraft:

| choice | what you see |
|---|---|
| **Original** (default) | the 1998 models from your install |
| **Detailed** | our detailed model where one exists, on the jets and on their stores; everything else keeps its original model |

The switch changes the look only (docs/deviations.md §2 "Models"). Stores, the gun, the flight model, damage and the
cockpit view work as with the original models.

Today the detailed models are the **F-16D** (`game/extra/models/f16/f16d.glb`), used for the player's F-16, the AI's
F-16s, parked F-16s and the Reference viewer; the **F-15C** (§6), which setup makes on your machine from the
FlightGear F-15 and which stands in for every F-15 the same way; and 16 **stores** (§5) on every jet that carries
them. Plans for more jets and stores: [graphics-research.md](graphics-research.md) §3.7 and §3.13.

## 1. The F-16D model

| item | value |
|---|---|
| source | FlightGear F-16 (`github.com/NikolaiVChr/f16`), GPL-2.0-or-later; credits and changes in `game/extra/models/f16/SOURCES.md` |
| triangles | 51 400 (original: 7 200); runtime LODs cut far jets to a fraction |
| textures | livery, occlusion / roughness / metallic and normal maps at 2048²; the nozzle, cockpit, seat and pilot textures at 512 px or less; KTX2 inside the glb (about 110 MB in video memory as RGBA8) |
| file size | 3.8 MB |
| livery | IAF desert camouflage, 101 Squadron, tail 547 (FlightGear's own livery); IAF wing roundels: one above each wing, one under each wing |
| crew | two pilots on two ACES II seats under a two-seat canopy |
| IAF features | the dorsal spine of Israel's F-16D Block 30 / 40 ("Brakeet"): the avionics hump from the back of the canopy to a box under the fin that ends just aft of the nozzle |

### 1.1 How it fits the game

The game reads positions from the aircraft model. The detailed model keeps them all:

- **Helpers at the original's positions** (within 1 cm): the `Station*` pylon points, `StationGun`, `StationFla`,
  `Camera` (the eye), `EndWingL/R` and `height` (where the wheels touch). The pylon meshes were moved so each touches
  its station: stores hang where they hang on the original. Station E has FlightGear's centreline pylon (grey, as
  the original's). The wingtip missiles (stations A and I) bring their own launcher, which meets FlightGear's tip
  rail 0.10 m off.
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
- **Wheels** are part of the gear legs' meshes, so they stay fixed, as on the original, also with Rolling wheels on
  (docs/part-animation.md §2.2).

### 1.2 Loading

`util/gltf.gd` maps the original file `f16_h.gltf` to the detailed glb (`DETAILED`) while the switch is on.
`Gltf.model()` parses the glb once and shares it between all jets, so the textures are in video memory once.
The parse also builds LODs for every mesh (`ImporterMesh.generate_lods`) and the meshes themselves. The mission
screens parse it ahead on a worker thread, as the mission's other models (rendering.md §1.5).

KTX2: Godot 4.7.2's runtime glTF loader reads `KHR_texture_basisu` and decodes it to RGBA8 with the mipmaps stored
in the file. KTX2 keeps the glb small; in video memory the textures are uncompressed (§1).

## 2. Rebuilding the F-16D

You need Blender 4 or 5, `basisu` (`brew install basis_universal`), a FlightGear F-16 checkout and your converted
install (`tools/setup-cli.sh`):

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
   canopy ends 0.95 m further aft; a second tub, seat and pilot go 0.98 m behind the first; adds the centreline
   pylon;
3. moves it 1.05 m aft so its wing lies on the original's wing;
4. moves each pylon onto the original's station and compresses the oleos so the wheels touch at `height`;
5. opens the main gear doors for LdgDr and closes the nose door for LdgDrUp;
6. builds the IAF dorsal spine (`dorsal_spine`, constants `SP_*`): rounded-box sections every 0.1 m, lofted over
   the fuselage and flared into it. Its top runs straight from the back of the canopy (0.93 m) to the foot of the
   fin and rudder (1.148 m) and stays there under the fin; it is 0.68 m wide to the wing's trailing edge, 0.40 m
   under the fin, and ends square 0.08 m aft of the nozzle's exit with a dark floor over the nozzle. Its UVs are the
   fuselage's under it, spread over the section, so the camouflage runs on at its foot. The fuselage faces it
   covers are removed (they would bake black into the occlusion map they share with it); FlightGear's tail root
   fairing and aft light inside it are dropped; the blade antenna and the formation light are raised onto it;
7. joins the parts, puts each origin on its hinge, adds the helpers;
8. sets the wing roundels (`wing_roundels`, constants `ROUNDEL_ART` and `ROUNDELS`): the livery's roundel above the
   left wing near the tip is painted over with the colours round it, and its art is drawn as a circle at each IAF
   position. Above each wing it sits on the fixed panel forward of the flaperon, mid-chord, 43 % of the way from the
   fuselage side to the tip rail, 0.53 m across. Under the left wing it mirrors the livery's own roundel under the
   right wing. A ray cast onto the skin finds each position's texels. Photographs: SOURCES.md, change 8;
9. makes the maps: occlusion baked in Cycles, a normal map from the livery's thin dark lines (panel lines, rivets),
   roughness from the lines and the occlusion;
10. exports the glb and re-encodes its textures as KTX2.

## 3. Checks

- `tests/godot/test_detailed_models.gd` (run by `tools/test.sh`): with the switch off the F-16 is the original
  model; with it on the detailed model loads once, has LODs and its textures, has every node of the original,
  keeps the helpers within 1 cm, has pylon or rail geometry at every store station (5 cm; tip rails 12 cm), has the
  IAF dorsal spine (its top within 5 cm of the original's from the canopy to the fin, after the original's 0.12 m
  higher placement is taken out), has every mesh inside the original's bounds + 1 m, has every part touching the body,
  has the afterburner ring on the nozzle's exit, animates (gear, doors, speed brakes, flaperons), and flies as the
  player's and the AI's jets in mission 231.
- `tests/godot/_model_shot.gd` (needs a window): real renders from outside, Original and Detailed, airborne with
  stores or on the ground. Pictures go to `assets/converted/research/f16d/` (`spine_close`, `spine_side` and `centre_pylon` for the dorsal
  spine and the centreline pylon). Run it through `tools/godot_window.sh`.

## 4. Open

- The cockpit view's own-jet model (`own_bc`, the original's `f16_bc`) stays the original's with the switch on.
- The livery's fuselage sides are stretched (FlightGear's UVs project from above and below); on the dorsal spine's
  sides the panel lines of the fuselage top are stretched too. The spine's three small vents and its aft sensor
  are not modelled.
- Where the livery's old roundel was, near the left wing tip, the paint is a smooth blend of the colours round it:
  its panel lines and rivets are gone over 0.5 m.
- The canopy glass is plain tinted glass.

## 5. Detailed stores

With Models Detailed the stores below are FlightGear F-16 models (`game/extra/models/stores/<name>.glb`; sources,
authors and changes in `SOURCES.md` there). They show on every jet that carries them, on the pylons and in flight
(a missile flying, a bomb falling), and in the Reference viewer. The other stores keep their original models.

| game store (bdb name) | detailed model | triangles (original) |
|---|---|---|
| AIM-9D, AIM-9L, AIM-9M; the SA-13's missile | AIM-9M | 3 158 (≈ 300) |
| AIM-7B, AIM-7F, AIM-7M; Shrike | AIM-7F | 951 |
| AMRAAM | AIM-120B | 1 344 |
| AGM-65 | AGM-65D | 2 767 |
| AGM88 | AGM-88 | 1 631 |
| MK-82, MK-83, MK-84 | MK-82, MK-83, MK-84 | 4 319, 4 377, 4 409 |
| MK-82L | GBU-12 | 5 699 |
| MK-83L, MK-84L | MK-83 / MK-84 with the GBU-12's Paveway II kits (a GBU-16 / GBU-10 look; inferred) | 6 002, 6 050 |
| CBU-87, CBU-97 | CBU-87 (simplified from 23 500) | 4 890 |
| 2700LB, 2100LB (the F-16's tanks) | 370 gal, 300 gal tanks in the IAF livery's paint | 2 102, 2 014 |
| ECM | AN/ALQ-131 | 1 284 |
| FLIR | AN/AAQ-13 (LANTIRN) | 938 |

Kept original: the Hawk SAM's missile (it shares the AGM-88's model; `weapon_db.gd` marks it `detailed: false`),
the rocket pod (FlightGear's LAU-68 has 7 tubes, the game's box 19), the SA-8's Shafrir and every store FlightGear has
no model of (Python, Shafrir, Popeye, Walleye, GBU-15, M117, RBK-500, the Soviet missiles, the other jets' tanks).
The SA-13 and the Shrike show the detailed AIM-9 / AIM-7, as they showed the original AIM-9 / AIM-7.

### 5.1 How they fit the game

The game reads no geometry from a store's model: its rack slots come from the original's `pilon` helper
(`player_weapons.gd` `_pilon_of` reads the original file), its station from the jet, its trail from its length. The
detailed model is built onto the original's frame (`tools/stores/build.gd`):

- scaled uniformly to the original's length, its middle on the original's middle;
- its axis (the mean of its nose's and its tail's centroids) on the original's axis; the tanks and pods (whose
  FlightGear mounts stand above the body) with their top on the original's top, where the pylon meets them;
- the laser bombs at their plain bomb's scale, so they keep its girth and are 41–47 % longer than the original's
  (which has the plain bomb's length), as the real ones.

So loadouts, release points, arming screens (2D icons) and CCIP stay as they are. Across the axis the detailed
models keep FlightGear's proportions: their fins differ in span from the original's by up to ± 13 cm.

### 5.2 Loading and drawing

- `Gltf.STORES` maps the original's file to the detailed one; `Gltf.object(path, allow_detailed)` opens it with the
  switch on. With the switch on, every detailed store is in the mission's model list
  (`TerrainPreload.mission_models`): worker threads parse them with their LODs on the mission screens, and the
  flight waits for them as for the mission's other models. Their materials draw both sides of each face (one more
  shader variant than the original stores'); the jets and their stores enter the scene at the spawn behind the
  loading screen, where Godot compiles the pipelines (rendering.md §1.6).
- LODs: Godot's runtime LODs (`ImporterMesh.generate_lods`, 2–7 levels down to a few percent); beyond
  `PlayerWeapons.STORE_LOD_M` (800 m, past the F11 weapon view's 700 m fly-by) the original model draws instead
  (`visibility_range`).
- Textures: one 512 px JPEG per store in the glb, compressed to BC1 at the parse (`Image.compress`, the CPU encoder,
  ≈ 3 ms each): ≈ 3 MB of video memory for all 16, against ≈ 23 MB uncompressed.
- Cost (estimated, not measured): an F-16 with nine detailed stores draws ≈ 20–35 k more triangles close up, a few
  thousand at a distance (the LODs) and the original's few hundred beyond 800 m; one draw per store and texture as
  before. Files: 2.4 MB in the repo.

### 5.3 Rebuilding the stores

```sh
git clone https://github.com/NikolaiVChr/f16.git /tmp/f16 && git -C /tmp/f16 checkout ef4f192
IAF_DEFAULT_SETTINGS=1 godot --headless --path game -s ../tools/stores/build.gd -- /tmp/f16 "$PWD/assets" [name …]
```

`STORES_STATS=1` prints each model's and each original's measurements and writes nothing.

### 5.4 Checks

- `tests/godot/test_detailed_models.gd`: every detailed store has its original's length (± 3 %; the laser bombs
  longer), its axis within 6 cm of the original's or its top within 2 cm, LODs, BC1 textures and the original as its
  far LOD; the Hawk keeps the original.
- `tests/godot/_stores_shot.gd` (needs a window): Original / Detailed pictures of loadouts on the F-16, F-15 and F-4
  on the ground, a Mk-84 falling and an AMRAAM in flight.

### 5.5 Open

- The weapon's roll is not tracked: a near-vertical bomb turns 90° in roll (`_orient`'s up vector), as the original.
- The stores keep FlightGear's single 512 px colour texture (no normal or roughness maps); the AIM-9D and AIM-9L show
  as the AIM-9M.

## 6. The detailed F-15C

The F-15 has a detailed model only on machines where setup made it: the step `models` (docs/setup.md) downloads the
FlightGear F-15 and converts it into `assets/converted/models/f15/f15c.glb`. Its licence (GPL-2.0-only) keeps it out
of our GPL-3.0-or-later repo, but anyone may use and change it, so it is handled like the game's own data: fetched
and converted on the player's machine, never committed or distributed (graphics-research.md §3.7). Without the file
(setup offline, or not run since) every F-15 keeps the original model with Models Detailed.

| item | value |
|---|---|
| source | Richard Harrison's (Zaretto) F-15C, `github.com/Zaretto/fg-aircraft` `aircraft/F-15` at commit 062cb58 (2020-01-03): 3D model by Enrique Laso, rig by Richard Harrison, cockpit textures by GeneB; GPL-2.0-only (docs/credits.md) |
| download | 10 files, about 18 MB, into `assets/source/f15/` (kept; each checked against its pinned SHA-256): `f15c.ac`, the nozzles, the pilot, the front cockpit, the grey and IAF liveries, `common.png`, the seat and the IAF patch |
| triangles | 42 400 (original: 7 100); runtime LODs as the F-16D |
| textures | the livery 2048² (JPEG), the gear / nozzle / intake atlas 1024², seat 512², pilot patch 512 × 256; compressed to BC1 / BC3 at the parse, about 5 MB of video memory (24 MB as RGBA8) |
| file size | 3.3 MB |
| livery | FlightGear's grey F-15C (USAF 80-0007) with its US markings painted out (tail codes, fin-tip bands, fin flash, the USAF crests) and the IAF roundels of FlightGear's IAF F-15I livery (69 Squadron) at their places: above and under each wing and on each intake side; the Hebrew radio call plate of the same livery |
| crew | one pilot (FlightGear's, with the IAF patch) on an ACES II seat in the front cockpit tub |

### 6.1 The conversion

The converter is Rust, in setup itself (`crates/iaf-tools/src/f15.rs`, `iaf_formats::ac3d`; CLI `iaf-convert
f15-detailed <assets>`): it needs no Blender or other outside program, and takes about 2 s. A Godot-side script
(as tools/stores/build.gd) would need a Godot run inside setup; the Rust step runs in the setup wizard's own
pipeline and in tools/setup-cli.sh alike. It:

1. reads `f15c.ac` and keeps the single-seat F-15C: the stores and their rails, the two-seat canopy, the conformal
   tanks, the ladder, the collision hull and the canopy's rivet heads, inner glass, mirrors and lamps are left out
   (the rivet heads alone are 60 000 triangles); the nozzles' 16 petals are ringed as `nozzle-L/R.xml` turns them;
   the cockpit tub, glare shields and ACES II seat come from `f15c-interior-front.ac`, the pilot from `pilot.ac`;
2. turns it into the game's frame (FlightGear: x aft, y right, z up; AC3D files: x aft, y up, z left) and scales it
   by 0.982 to the original's length, its middle on the original's, its main wheels on the original's `height`;
3. moves FlightGear's wing and centreline pylons (SUU-59) so each foot meets StationB / StationH / StationE;
4. splits the moving parts under the original's names — AilerL/R, FlapL/R, ElevaL/R (the stabilators), RuddeL /
   Rudde, SpdbrU (the speed brake), Hook, LdgF/L/R (each leg with its wheel and lights), canopy (frame and glass),
   pilot — each with its origin and `<part>1/2` helpers on f15c.xml's hinge line, the axis turned the original's way.
   The doors that stand open with the gear down (the nose door on the strut, the outer main doors) go to LdgDr opened
   by f15c.xml's angles (110°, 90°) and to LdgDrUp shut; the other doors shut with the gear both up and down and stay
   in the body. FlightGear's other moving extras (wing bend, intake ramps, engine fans, refuelling door) stay still;
5. copies the original's helpers (stations, gun, eye, wingtips, height) and puts EngineL/R at each nozzle's exit,
   EngineL1/R1 above it by the exit's radius;
6. paints the livery (above; `ROUNDELS`, `ERASE`, `CRESTS` hold the places in the 2048² skin): a painted-out
   marking is filled with the mean of its neighbours until it settles, so the grey runs on smoothly; a roundel is the
   IAF livery's, cut as the ellipse round its white and blue pixels with a one-pixel blended rim;
7. writes the glb: smooth normals from AC3D's crease angles, one material per texture or colour (canopy glass tinted
   and blended), the textures as JPEG / PNG inside.

### 6.2 How it fits the game

As the F-16D (§1.1): the descriptor stays the original's; `detailed_descriptor` takes the hinge axes, both
afterburners (EngineL / EngineR) and LdgDrUp from the model. Its speed brake and hook are modelled shut in place, so
they show also shut (the original F-15's hide when shut). The hinge axes lie within 8° of the original's (the
rudders' sweep); the gear legs swing about FlightGear's first retraction axis only (FlightGear also turns the main
wheels flat), so a leg in transit takes a simpler path. `util/gltf.gd` maps `f15_h.gltf` to the file under
`assets/` (DETAILED's paths without `res://`), parses it with LODs and compresses its textures (`_made_by_setup`).

### 6.3 Checks

- `tests/godot/test_detailed_models.gd` `_check_f15` (skipped when setup has not made the file): with the switch off
  the original; on, the setup's model with 30–60 k triangles, every node of the original, the helpers within 1 cm,
  pivots on their parts with axes within 20° of the original's, the pylons under StationB / E / H (5 cm), two
  afterburners on the detailed nozzles, the livery compressed, the gear and doors' visibility, and the player's F-15
  in mission 311.
- `cargo test -p iaf-tools f15`: the sources pinned, the frames, and the whole conversion on `assets/source/f15`
  when it is there; `cargo test -p iaf-formats ac3d`; `cargo test -p iaf-setup` (the step skips offline).
- `tests/godot/_model_shot.gd` with `SHOT_JET=0`: the before / after pictures (on the ground from the front-left and
  rear, in flight from the side and above, the gear and surfaces moving mid-roll, a loadout on the pylons).

### 6.4 Tried and dropped

- 2026-10-28: painting the US markings out column by column (from the colour above to the colour below) left vertical
  streaks on the fins, whose paint is lighter at the leading edge; replaced by the settled mean of the neighbours.
- 2026-10-28: FlightGear's IAF F-15I livery (69 Squadron) as it is: real IAF markings, but the F-15I's desert
  camouflage on an F-15C, where the original's F-15 is a grey Baz. Only its roundels and radio call plate are used.

### 6.5 Open

- The livery is the grey of a USAF F-15C with IAF roundels: no IAF tail number, squadron badge or Baz fin art, and
  where a US marking was the panel lines are gone. FlightGear's IAF livery is the desert camouflage of the F-15I.
- The cockpit view's own-jet model (`own_bc`, the original's `f15_bc`) stays the original's, as for the F-16D. The
  front cockpit shows its tub, glare shields and seat, without the instrument panel (its textures are SGI `.rgb`
  files, which the converter does not read).
- No original model as the far LOD (as the F-16D; the stores have it).
- The gear legs retract about one axis (above); the nozzles keep their modelled opening.
