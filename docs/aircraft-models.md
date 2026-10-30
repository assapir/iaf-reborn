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
F-16s, parked F-16s and the Reference viewer; the **F-16I Sufa** (§1.3, `f16i.glb`), which stands in for every F-16
with the Extras switch "F-16 version" on Sufa, whatever Models says; the **F-15C** (§6), which setup makes on your machine from the
FlightGear F-15 and which stands in for every F-15 the same way; and 16 **stores** (§5) on every jet that carries
them. Plans for more jets and stores: [graphics-research.md](graphics-research.md) §3.7 and §3.13.

## 1. The F-16D model

| item | value |
|---|---|
| source | FlightGear F-16 (`github.com/NikolaiVChr/f16`), GPL-2.0-or-later; credits and changes in `game/extra/models/f16/SOURCES.md` |
| triangles | 51 400 (original: 7 200); runtime LODs cut far jets to a fraction |
| textures | livery, occlusion / roughness / metallic and normal maps at 2048²; the nozzle, cockpit, seat and pilot textures at 512 px or less; KTX2 inside the glb (about 110 MB in video memory as RGBA8) |
| file size | 3.8 MB |
| livery | IAF desert camouflage, 101 Squadron, tail 547 (FlightGear's own livery and pattern) in the Barak's colours measured on photographs: faded tan, sand and grey-green down to the strakes, light grey below, camouflaged stabilator tops; IAF wing roundels: one above each wing, one under each wing |
| crew | two pilots on two ACES II seats under a two-seat canopy: two transparencies on one narrow near-black bow just behind the front seat's headrest, both cockpits open under the glass |
| IAF features | the dorsal spine of Israel's F-16D Block 30 / 40 ("Brakeet"): the avionics hump, level from the canopy's rear edge to a box under the fin that ends round just aft of the nozzle, 0.25 m under the canopy's top, with its three vents; the fin and rudder stand on it |

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
- **Sitting nose up** (ours): the nose oleo is built at its static compression (`NOSE_STATIC`, 0.041 m from
  FlightGear's JSBSim gear spring), so its wheel reaches 0.186 m under the main wheels' line, as on the real jet,
  whose strut shows between the intake and the wheel (F-16D 027). The helpers `Sit1` (where the main wheels touch)
  and `Sit2` (the nose wheel) give the angle, 3.0°. The game holds the jet level on the ground (flight-model.md
  §14.5a) with the wheels at `height`, so `AircraftModel` turns only the drawn model nose up about `Sit1` while the
  jet is on its wheels with the gear down (`sit`), easing in and out over `SIT_TIME` (0.6 s). The cockpit view has
  its own model and the flight model's attitude, so it stays level.

### 1.2 Loading

`util/gltf.gd` maps the original file `f16_h.gltf` to the detailed glb (`DETAILED`) while the switch is on.
`Gltf.model()` parses the glb once and shares it between all jets, so the textures are in video memory once.
The parse also builds LODs for every mesh (`ImporterMesh.generate_lods`) and the meshes themselves. The mission
screens parse it ahead on a worker thread, as the mission's other models (rendering.md §1.5).

KTX2: Godot 4.7.2's runtime glTF loader reads `KHR_texture_basisu` and decodes it to RGBA8 with the mipmaps stored
in the file. KTX2 keeps the glb small; in video memory the textures are uncompressed (§1).

#### The dorsal spine against photographs (2026-10-29)

Our renders were set beside IAF photographs (game/extra/models/f16/SOURCES.md, change 2), above all F-16D 027
parked side on. Measured on 027 with the canopy's length as the scale: the canopy's top stands 0.25 m above the
spine, the spine's top is level from the canopy's rear frame to the fin, and the fin rises from it. The earlier spine
climbed from 0.93 m behind the canopy to 1.148 m at the fin, level with the canopy's top (0.303 m and 0.304 m above
the eye). It grew out of FlightGear's single-seat fairing behind the glass, so its narrow, rounded front stood on
the fairing with a notch between it and the glass. Both came from following the original model's spine and
FlightGear's fin root, which also stand level with the canopy's top. The spine now starts at the glass's rear edge
and runs level 0.25 m under the canopy's top, and the fin reaches 0.27 m lower, down to it (§2, step 6).

Tried and dropped:

- **The spine 0.60 m wide from 0.4 m inside the glass's tail.** It followed the photo of an F-16I from above, where
  the spine looks as wide as the canopy's rear. Result: FlightGear's glass narrows to a 0.34 m arch at its rear, so
  the spine's shoulders stood out beside the glass. Dropped for a front that is the glass's arch and widens behind
  it. Making FlightGear's glass wider at the rear was left alone: it is the moving canopy.
- **The fin moved down 0.27 m as a whole** (2026-10-29, first build). It met the spine, but its tip came to 4.63 m
  above the ground, under the F-16's published 4.88 m. Measured again on 027: the intake's bottom stands 0.30 of
  the canopy's top above the ground, FlightGear's geometry 0.29, so the body and gear are right and the fin is too
  short at its root. Dropped for the stretch down to the spine, the tip kept.
- **"The jet sits 0.3 m low on its gear"** (an estimate from the strakes' height in a photo). JSBSim's springs settle
  the main wheels within 2 cm of where they are; the intake / canopy ratio above agrees. Dropped.

#### The canopy between the seats against photographs (2026-10-29)

The F-16B / D canopy is two transparencies, a forward one about the single seater's size and an aft one, held in one
frame; the strip between them is part of that frame and carries the canopy's actuator yoke[^f16net]. On IAF F-16Is
side on (Blue Flag 2015[^blueflag], Hatzerim[^hatzerim], tail 432 in its shelter[^bayit432]) that strip is one
narrow, near-black, upright bow with a row of rivets, just behind the front seat's headrest, halfway along the
canopy. Measured on the Blue Flag photo with the canopy's length as the scale: about 0.07 m wide, upright within a
few degrees. Through the glass behind it show the rear seat's instrument coaming and the rear pilot, the rear
cockpit as open as the front one. Its colour on the photos is the frame's dark (near black, inferred: the paint or
the sealant over it), never the camouflage.

FlightGear's single-seat F-16C has its aft hoop there instead (0.18 m deep at the top, leaning 24° aft, mapped into
the livery) and, under it, a bulkhead and a deck from the bulkhead's foot to the canopy's rear end. The two-seat
stretch left the hoop as a thick camouflaged arch between the pilots, and the deck covered the rear cockpit up to
the rear pilot's chest. `canopy_bow` (§2, step 2) rebuilds the hoop as the bow (`BOW_*`: 0.07 m, upright, 50 % of
the way along the canopy, `canopy_bow` material near black), meets the forward glass's rear edge and the aft glass's
front edge on its two faces, takes the bulkhead out and moves the deck's front edge back behind the rear seat
(`DECK_Y`). The same code builds both jets.

Tried and dropped (2026-10-29):

- **Only the hoop made thin and dark.** Result: the single-seat bulkhead under it showed as a camouflaged band
  leaning aft, where the hoop had hidden it. Dropped: the bulkhead goes too.
- **FlightGear's hoop section as it is.** Result: the bow stood 2 cm proud of the glass, a post over the canopy's
  top side on. Its section is now scaled 0.985 about the canopy's axis (`BOW_SINK`), nearly flush as on the photos.
- **The bow colour on the faces wholly in the hoop only.** Result: its foot, the faces down to the sill rail, kept
  the livery. The faces touching the hoop take the bow's colour.

#### The colours against photographs (2026-10-29)

FlightGear's livery has an IAF pattern, but its pale green renders light blue (it is nearly its grey) and its
brown reads dark. The colours were measured on photographs of IAF F-16Ds (SOURCES.md, change 10): each tone over
the sand in the same light, on 027 in sun and 601 under cloud. Tan over sand: (0.87, 0.70, 0.50) and (0.76, 0.70,
0.66). Green over sand: (0.93, 1.00, 0.98) and (0.87, 0.94, 0.92). The green is a warm grey-green barely darker than
the sand. `BARAK` keeps the sand as bright as FlightGear's and sets the tan and green so that on screen they stand to
the sand as in the photos' mean.

Tried and dropped:

- **The Sufa's FS colours** (`FS`, set against fresh F-16I paint). Result: the Barak dark and green, unlike the
  faded, warm jets in the photos.
- **The photos' ratios as albedo.** Result: on screen the tan stood to the sand at 0.61 where the photos show
  0.82: the tone curve darkens the middle tones. Dropped for values set against our own renders.
- **The green only on faces looking up.** Result: the sides under the canopy rail stayed blue-grey; on 601 they
  are camouflaged down to the strakes. Dropped for the height test (`BARAK_Z_CAMO`), which keeps the intakes' sides
  grey.

### 1.3 The F-16I Sufa model

`game/extra/models/f16/f16i.glb` is the same build with the `sufa` argument (docs/f16i.md §8.1 lists what it adds:
FlightGear's conformal fuel tanks and P&W nozzle, our nose fairings, and the paint and markings of one real jet,
F-16I 846 of 201 Squadron: its camouflage, colours, fin art and tail number).
It keeps every part, hinge, helper and station of the F-16D, so arming, animation and the afterburner work
unchanged. `util/gltf.gd` `detailed()` returns it for `f16_h.gltf` whenever the F-16 switch is on Sufa
(`Settings.sufa(100)`), with Models on Original too: the 1998 game has no Sufa.

| item | value |
|---|---|
| triangles | 52 950: the F-16D's plus the CFTs (352 faces), the nozzle (16 × 13 faces), the seven nose fairings and the four tail-box fairings |
| textures | as the F-16D's; the livery repainted by the script (`sufa_livery`) |
| file size | 4.0 MB (KTX2) |

The camouflage: on every texel within `SUFA_BODY_X` (1 m) of the centre line (fuselage, CFTs, spine, tail box) the
colour of the `SUFA_BLOTCHES` polygon its (y, z) lies in, sand outside them (`side_weights`, soft over 2 cm), both
sides alike; the fin all tan under its art (`fin_art`: polygons, swooshes as centre lines with a width per point,
the badge's rings and the number's strokes). Elsewhere (wings, stabilators) `camo_weights`: three smooth noise fields
over the airframe's world frame (blotches about `BLOTCH_M` = 1.5 m, 1.3 × longer fore-aft, ragged edges from a warp
of the coordinates), each texel the colour of the strongest, soft over about 2 cm at an edge, the fields shifted
until each colour covers a third. `texels` finds each texel's place on the jet (where faces share texels, the face
whose texel size is nearest the livery's usual wins, not a sliver mapped over a large area), so the pattern runs on
across parts and UV seams. Before it, `sufa_livery` updates the scene, so the moving parts (rudder, flaperons,
stabilators) are where the rig put them. It covers the texels of the livery's camouflage colours on faces looking up
or sideways, the CFTs' and the spine's own UV islands (`CFT_UV`, `SP_ISLAND`) and the fin's old markings; texels
between UV islands take the colour round them. The livery's panel lines and rivets stay (each texel times its
brightness over the local brightest, as `panel_maps` finds the lines). The paint's roughness is `SUFA_MATTE` (0.25)
above the F-16D's.

Checks: `tests/godot/test_sufa_model.gd`: with Barak the F-16 is the original or the F-16D as before; with Sufa
`f16i.glb` loads under both Models settings, keeps every helper of the original within 1 cm, and the player's and
the AI's F-16s in mission 221 use it; the Arming screen shows the Sufa's art, weights and the F-16's nine boxes.

#### Tried and dropped (2026-10-29)

- **The photo laid onto the side view with a plain 2D fit** (three points: the radome's tip and the fin's leading
  edge). Result: the fin matched, but the bands on the CFTs and the canopy's side landed up to 0.7 m off, as 846's
  photo looks from ahead and below. Dropped for a camera fitted to nine points in 3D, the photo laid onto the
  model's surfaces through it.
- **846's tan at the photos' luminance ratio to the sand** (albedo (0.66, 0.48, 0.33), then (0.70, 0.50, 0.32), with
  the F-16D's gloss). Result: in the game, in shade, the tan read maroon to brick-red and the sky's reflection
  tinted it violet; the orange swoosh read red. Dropped for (0.76, 0.56, 0.37), the orange (0.90, 0.58, 0.22) and
  the paint 0.25 rougher.
- **The pattern read before the scene was updated** (as the F-16D's build still does). Result: the rudder's texels
  took their places at the origin, so the rudder kept the livery's sand under the fin's tan. Fixed on the Sufa's path
  only; the F-16D's stabilator tops still come from those stale places (open: fixing it there changes f16d.glb).
- **Our noise camouflage in the FS chips' colours, 107 Squadron's markings and tail 457** (the build of
  2026-10-28/29). Result: beside photos of the jets it read too dark and too green, its blotches random where the
  jets have bands across the fuselage, and 457 is not a real number. Replaced by one real jet, 846, on the
  user's decision of 2026-10-29.

- **The CFTs painted from the skin under them** (the 2026-10-28 build: each CFT corner took the livery of the
  fuselage or wing straight below). Result: the tanks' steep sides took one row of texels each, so they read as one
  long smooth dark-brown band. Dropped for the CFTs' own UVs, painted with our camouflage.
- **FlightGear's own camouflage pattern, recoloured.** Result: mostly sand with brown and little green, unlike the
  photos' equal measure. Dropped for our pattern; the colour mapping (`recolour`) stays for the underside's grey and
  the radome.
- **Our pattern without balancing.** The three fields' plain maximum gave 12 % brown, 57 % sand and 31 % green over
  the airframe (too few blotches to average out). Dropped for the shifted fields (a third each).

#### Tried and dropped (2026-10-28)

- **Recolouring by texture regions.** Boxes round the livery's top view and fin, recoloured to the camouflage
  colours. Result: parts of the underside that share those rows (the right wing's lower skin, the ventral fins)
  turned green, and the underside's panel lines took a green tint, as FlightGear's pale green and its underside
  grey are only 0.05 apart. Dropped for the face normals: texels of faces underneath take only the grey.
- **Painting over the fin badge by relaxing it to the colours round it** (as the F-16D's old roundel). Result: a
  blurred brown blob with a pink stain from the stripes, plain on the fin. Dropped: each relaxed texel now takes the
  nearer of the FS tan and sand, which leaves crisp camouflage patches.
- **A free F-16I model online** (Sketchfab, FlightGear, GitHub). Found: FlightGear's F-16 has the CFTs and the P&W
  nozzle but no F-16I or IAF Sufa livery; Sketchfab's downloadable "F-16I Sufa" models (by KojfDiscord, 300 000+
  triangles) are labelled CC BY but are extracted from War Thunder, whose rights are Gaijin's, so their licence is
  not valid; the other CC BY F-16s there (Block 50/52, Block 60, F-16D "Brakeet") have no CFTs or are works in
  progress. Dropped for our own build from the FlightGear F-16 (GPL 2.0 or later).

### 1.4 The cockpit view's own jet

Looking aside or back from the cockpit shows the own jet's cockpit model (docs/views.md §4.3). With the F-16D
(Models: Detailed) or the Sufa, this model is the detailed F-16 itself, so the seat, tub, canopy frame, rear cockpit
and conformal tanks seen from the seat match the jet seen from outside. With Models on Original and the F-16
version on Barak it stays the original's `f16_bc`.

`AircraftModel.detailed_cockpit()` builds it once per flight (about 25 ms) from the shared model:

- **The eye** is the front pilot's eye: the `pilot` frame plus `F16_EYE_IN_PILOT` (0.85 m above the jet's axis, on
  the centre line). It sits 1.47 m aft of the original's eye (`Camera`), because FlightGear's cockpit sits further
  aft on the airframe than the 1998 model's. The model is shifted by −eye, so this eye is at the camera. The cockpit
  camera's near plane is 0.1 m (0.5 m otherwise), as the seat's sides and headrest are 0.2–0.4 m from the eye.
- **Looking back** the head rises 0.1 m and leans 0.1 m forward (`terrain_view.gd` `LOOK_BACK_LEAN`, blended in
  from 90° to 150° of head yaw), as a pilot checking six looks over the headrest. From the seated eye the headrest
  top is 0.05–0.08 m above the eye, so straight back the seat filled the view.
- **The cut**: as the original's cockpit model, it ends at the eye. Every triangle wholly ahead of the eye is left
  out, so the nose, the instrument panel and the front of the canopy never show over the cockpit art.
- **Left out**: the front pilot's body (the crew mesh's surfaces after the first `F16_SEAT_SURFACES`, the ACES II
  seat's; rig.py joins seat then pilot), the canopy glass (from inside it fogs the whole view; the original hides
  the canopy there too), the gear legs and the open gear doors. The closed doors show.
- **Kept**: the front seat with its headrest 0.56 m behind the eye, the canopy frame and rails, the rear tub with its
  seat and pilot, the spine, wings, tail and the stores on their stations.
- **Materials**: FlightGear gives the seat and tub roughness 0.5, which shone with sky-blue glare; the cockpit
  model's copies are matte (roughness 0.9, specular 0.2). FlightGear maps the canopy frame into the livery, so on
  the Sufa it took the camouflage; here it is FS 36118 gunship grey (`F16_FRAME_COLOUR`). The jets seen from
  outside keep their materials.
- **The canopy's centre bow** stands upright between the two seats, about 0.6 m behind the eye, 0.07 m deep, as on
  the real two-seater (§1, the canopy between the seats). Seen from the seat it is frame grey as the rest of the
  frame.

Checks: `tests/godot/test_detailed_cockpit.gd` (the seat surfaces end where the pilot's begin, the eye on the centre
line, nothing ahead of the eye, the seat back 0.4–0.7 m behind it, no gear, the rear crew kept, the frame grey, the
seat matte while the outside jets' seat keeps its material; in mission 231
Original keeps `f16_bc`, Detailed and the Sufa use the cut model). `tests/godot/_cockpit_show_shot.gd` scenes
`cockpit_f16_back`, `cockpit_f16_rback` and `cockpit_f16_lback` take the look-back pictures.

## 2. Rebuilding the F-16D

You need Blender 4 or 5, `basisu` (`brew install basis_universal`), a FlightGear F-16 checkout and your converted
install (`tools/setup-cli.sh`):

```sh
git clone --depth 1 https://github.com/NikolaiVChr/f16.git /tmp/f16
blender -b --python tools/f16d/rig.py -- /tmp/f16 assets/converted/planes/f16/f16_h.gltf game/extra/models/f16/f16d.glb
```

The F-16I Sufa (§1.3): the same command with `game/extra/models/f16/f16i.glb sufa` at the end.

`F16D_FAST=1` skips the occlusion bake (about 1 minute) for quick geometry tries. `F16D_DEBUG=1` prints every
object's bounds. The script uses `tools/plane/kit.py` (`import_ac` reads FlightGear's AC3D files) and
`tools/plane/glb_ktx2.py` (the KTX2 pass).

The script:

1. imports `f16.ac` (FlightGear's single-seat F-16C) and the GE nozzle, and drops the parts the game draws itself
   (flames, lights, USAF markings);
2. makes it two-seat: everything above the canopy sill between the front seat and the fin root is stretched so the
   canopy ends 0.95 m further aft; a second tub, seat and pilot go 0.98 m behind the first; rebuilds the canopy's
   centre bow, takes out the single seater's bulkhead and opens the rear cockpit (`canopy_bow`, §1); adds the
   centreline pylon;
3. moves it 1.05 m aft so its wing lies on the original's wing;
4. moves each pylon onto the original's station and compresses the oleos so the wheels touch at `height`;
5. opens the main gear doors for LdgDr and closes the nose door for LdgDrUp;
6. builds the IAF dorsal spine (`dorsal_spine`, constants `SP_*`): rounded-box sections every 0.1 m, lofted over
   the fuselage and flared into it. Its front is the canopy glass's rear edge, an arch 0.38 m wide whose top is
   0.945 m, so the glass runs on into it. It widens to 0.68 m by 1 m aft of the glass, eases down to 0.878 m and runs
   level from there to its end: 0.40 m wide under the fin, ending in a round cap 0.08 m aft of the nozzle's exit,
   with a dark floor over the nozzle. Three dark vents sit on each side ahead of the fin (the F-16I: two taller ones
   and a blister and a fairing on each side of the tail box, docs/f16i.md §8). Before that (`lower_fin`)
   FlightGear's fin and rudder are stretched down 0.27 m (`FIN_DROP`, `fin_z`; the rudder's hinge with them), their
   tip kept, and its tail root fairing is squashed to meet them: FlightGear's fin root is level with the canopy's
   top, where on the real jet the canopy stands 0.25 m above the fin's root and the spine; its fin tip is right
   (4.90 m above the static ground; the F-16's published height is 4.88 m). The spine has its own UV island (`SP_ISLAND`, 78 px per m: a plain grey
   rectangle of the livery that no other face uses, above the inner canopy frame's UVs). `spine_island` paints it
   from the livery of the fuselage round it, unfolded at its true size: each section's arc is laid on the fuselage
   top from foot to foot, going out from each foot and folding back over the top (a mirror fold on each side, at
   a quarter of the arc's excess over the foot-to-foot width), so the panel lines and rivets keep their size and the
   paint runs on unbroken at the foot. Until 2026-10-29 the spine took the UVs of the fuselage under it, spread over
   the section: the section's arc is about twice the width under it, so the panel lines and rivets stood twice as
   tall on its sides. The fuselage faces it covers are removed; FlightGear's aft light inside it is dropped; the blade antenna
   and the formation light are set onto it;
7. joins the parts, puts each origin on its hinge, adds the helpers;
8. sets the wing roundels (`wing_roundels`, constants `ROUNDEL_ART` and `ROUNDELS`): the livery's roundel above the
   left wing near the tip is painted over with the colours round it, and its art is drawn as a circle at each IAF
   position. Above each wing it sits on the fixed panel forward of the flaperon, mid-chord, 43 % of the way from the
   fuselage side to the tip rail, 0.53 m across. Under the left wing it mirrors the livery's own roundel under the
   right wing. A ray cast onto the skin finds each position's texels. Photographs: SOURCES.md, change 8;
9. recolours the livery to the Barak's colours (`barak_livery`, constants `BARAK`, `BARAK_Z_CAMO`; the Sufa has
   its own, `sufa_livery`): FlightGear's brown, sand and pale green become the tan, sand and grey-green measured on
   photographs of IAF F-16Ds (§1.2, "The colours against photographs"); its pale green is nearly its grey, so above the strakes (0.15 m) and on faces
   looking up both become the green, and underneath the grey stays FS 36375. The stabilators' tops, grey in the
   livery, get our camouflage pattern (`camo_weights`) in the same colours;
10. makes the maps: occlusion baked in Cycles, a normal map from the livery's thin dark lines (panel lines, rivets),
   roughness from the lines and the occlusion;
11. exports the glb and re-encodes its textures as KTX2.

## 3. Checks

- `tests/godot/test_detailed_models.gd` (run by `tools/test.sh`): with the switch off the F-16 is the original
  model; with it on the detailed model loads once, has LODs and its textures, has every node of the original,
  keeps the helpers within 1 cm, has pylon or rail geometry at every store station (5 cm; tip rails 12 cm), has the
  IAF dorsal spine (its top level within 4 cm from behind the canopy to the fin, 0.20 to 0.32 m under the canopy's
  top, flat across), has every mesh inside the original's bounds + 1 m, has every part touching the body,
  has the afterburner ring on the nozzle's exit, animates (gear, doors, speed brakes, flaperons), and flies as the
  player's and the AI's jets in mission 231.
- `tests/godot/_model_shot.gd` (needs a window): real renders from outside, Original and Detailed, airborne with
  stores or on the ground. Pictures go to `assets/converted/research/f16d/` (`spine_close`, `spine_side` and `centre_pylon` for the dorsal
  spine and the centreline pylon). Run it through `tools/godot_window.sh`.

## 4. Open

- The Sufa's other antenna changes and 107 Squadron's real badge (docs/f16i.md §10).
- The livery's fuselage sides are stretched (FlightGear's UVs project from above and below). The spine's aft sensor
  is not modelled.
- Where the livery's old roundel was, near the left wing tip, the paint is a smooth blend of the colours round it:
  its panel lines and rivets are gone over 0.5 m.
- The canopy glass is plain tinted glass.

## 5. Detailed stores

With Models Detailed the stores below are FlightGear models (the F-16's; the Soviet ones the MiG-21bis's and the
MiG-29 9-12's) (`game/extra/models/stores/<name>.glb`; sources,
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
| AIM-9X (the Sufa's, ours) | AIM-9X | 7 766 |
| GBU-31, GBU-31V3 (the Sufa's) | GBU-31 | 2 944 |
| GBU-38 (the Sufa's) | GBU-54 (the laser JDAM: a GBU-38 with a laser nose) | 3 208 |
| GBU-31V3 (the Sufa's) | GBU-31, slimmer to the BLU-109's 370 mm | 2 944 |
| GBU-32 (the Sufa's, the F-35I's) | GBU-31 at the GBU-32's 3.035 m | 2 944 |
| PYTH-5, GBU-39 (with its BRU-61/A rack), POPEYE | ours (§5.6) | 1 060, 776 (+ 492), 888 |
| AA-2 (and "Rockets", which shares its model) | R-3S (MiG-21bis) | 3 558 |
| AA-8 | R-60M (MiG-29 9-12) | 1 601 |
| AA-10 | R-27R (MiG-29 9-12) | 1 050 |
| AA-11 | R-73 (MiG-29 9-12) | 1 160 |
| 3500LB (the MiG-29's tank) | PTB-1500 (MiG-29 9-12) | 640 |

Kept original: the Hawk SAM's missile (it shares the AGM-88's model; `weapon_db.gd` marks it `detailed: false`),
the rocket pod (FlightGear's LAU-68 has 7 tubes, the game's box 19), the SA-8's Shafrir and every store with no open
model (Python 3 / 4, Shafrir, Walleye, GBU-15, M117, RBK-500, the AA-6, AS-14 and AS-16, the other jets' tanks). The
MiG-23's 2800LB tank shares the F-4's tank model (`f4ftk`), so it keeps the original, as the F-4's tank does.
The SA-13 and the Shrike show the detailed AIM-9 / AIM-7, as they showed the original AIM-9 / AIM-7. The Sufa's
records without an original model of their own (weapons.md §13) name ours (`weapons/sufa/…`); with Models Original
`util/gltf.gd` `STAND_INS` draws the original AIM-9, MK-84L, MK-82L, MK-83L, Python 4 and MK-82 (the GBU-39, at
0.8 scale) in their place.

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
  ≈ 3 ms each): ≈ 3 MB of video memory for the first 16, against ≈ 23 MB uncompressed.
- Cost (estimated, not measured): an F-16 with nine detailed stores draws ≈ 20–35 k more triangles close up, a few
  thousand at a distance (the LODs) and the original's few hundred beyond 800 m; one draw per store and texture as
  before. Files: 4.4 MB in the repo (34 models; the five Soviet ones 0.65 MB, ours of §5.6 0.36 MB).

### 5.3 Rebuilding the stores

```sh
git clone https://github.com/NikolaiVChr/f16.git /tmp/fg/f16 && git -C /tmp/fg/f16 checkout ef4f192
git clone https://github.com/l0k1/MiG-21bis.git /tmp/fg/MiG-21bis && git -C /tmp/fg/MiG-21bis checkout 9ca6f5b
git clone https://github.com/Mercenary-Mercury/MiG-29_9-12.git /tmp/fg/MiG-29_9-12
git -C /tmp/fg/MiG-29_9-12 checkout d4a299b
IAF_DEFAULT_SETTINGS=1 godot --headless --path game -s ../tools/stores/build.gd -- /tmp/fg "$PWD/assets" [name …]
```

`STORES_STATS=1` prints each model's and each original's measurements and writes nothing.

### 5.4 Checks

- `tests/godot/test_detailed_models.gd`: every detailed store has its original's length (± 3 %; the laser bombs
  longer), its axis within 6 cm of the original's or its top within 2 cm, LODs, BC1 textures and the original as its
  far LOD; the Hawk keeps the original.
- `tests/godot/_stores_shot.gd` (needs a window): Original / Detailed pictures of loadouts on the F-16, F-15 and F-4
  on the ground, a Mk-84 falling and an AMRAAM in flight; the Mission Creator's MiG-29 and MiG-23 with the Soviet
  stores and an AA-10 in flight; the Sufa and the F-35I with the Python 5, GBU-39 racks and GBU-32, the F-15 with
  a Popeye and our stores with no record beside it, a Python 5 in flight.
- `test_detailed_models.gd` also checks the GBU-39's rack: centred on the four slots, longer than their spread, its
  bottom on the bombs' tops, drawn to 800 m only.

### 5.5 Open

- The weapon's roll is not tracked: a near-vertical bomb turns 90° in roll (`_orient`'s up vector), as the original.
- The stores keep FlightGear's single 512 px colour texture (no normal or roughness maps); the AIM-9D and AIM-9L show
  as the AIM-9M.
- A released GBU-39 shrinks to 0.8 of its real size: the record's `scale` (`modern_weapons.gd`, for the MK-82 it
  borrows with Models Original) applies to the weapon in flight, not on the pylon.

### 5.6 Our own stores

No open model exists for the Python 5, the GBU-39, its BRU-61/A rack, the Popeye, the SPICE kits or the Spike NLOS
(graphics-research.md §3.13; the FlightGear F-22's GBU-39 is GPL-2.0-only and marked "By FGUK's Davinci F-35", an
unverified source). `tools/stores/build.gd` builds them from shapes in `tools/stores/ours.gd` (`parts()`): bodies of
revolution with colour bands, fins and boxes, flat colours (no texture), each surface its own material. The lengths,
diameters and spans are the published ones (`game/extra/models/stores/SOURCES.md`); the profiles, fin planforms, bands
and colours are measured by eye on photos (inferred). Fitted as the FlightGear stores (§5.1): the Python 5 at the
AIM-9's scale on the Python 4 (3.05 m against its 3.06 m), the GBU-39 at the MK-82's scale on the MK-82, the Popeye to
its original's length (4.69 m, the real one 4.82 m).

| model | what it shows | differs from the real weapon (photos) |
|---|---|---|
| `pyth5` | glass dome, two rows of four canards (X), four long-chord rear wings (X) each with a trailing control surface, rail hangers; grey, darker guidance section, bare motor with red bands | 16 surfaces against the 18 Wikipedia counts (open); no markings or rivets; the dome is dark glass (the real one clear, its seeker inside) |
| `gbu39` | long ogive nose, yellow band, the folded wing pack on top, four tail fins (X) | the body is round (the real one has flat panels along it); no lugs; wings folded only |
| `bru61` | squared beam with a keel below, on the bombs' tops | drawn only with Models Detailed over a station of four GBU-39s (`Gltf.RACKS`, `PlayerWeapons._rack`); stretched along its length to the game's slots, 4 m apart fore and aft (`BOMB_STATION_LENGTH`): about 5.6 m against the real 3.63 m; the bombs sit beside it, not hung from its lower edges |
| `popeye` | glass dome (dark, the real one gold-tinted), small fins (X) behind the nose, long-chord swept tail fins (X), yellow band | no datalink pod or fairings; the original's length |
| `spice1000`, `spice2000`, `spikenlos` | SPICE kits on the Mk 83 / Mk 84 (canards, mid-body strakes on the 2000, folded wings under the 1000, tail fins); Spike NLOS with its dark dome and long pop-out wings | not in the game yet (real-weapons.md §1.8); lengths inferred from photos (open) |

The GBU-32 and GBU-31(V)3 reuse the FlightGear GBU-31 (`build.gd` `k`, `girth`): the GBU-32 scaled to 3.035 m, so
its Mk 83 nose is the Mk 84's rounder one; the GBU-31(V)3 at 3.774 m and 0.804 of its girth, so its tail kit is
slimmer too, and it keeps the Mk 84's ogive and band (the real BLU-109 has a narrower nose).

## 6. The detailed F-15C

The F-15 has a detailed model only on machines where setup made it: the step `models` (docs/setup.md) downloads the
FlightGear F-15 and converts it into `assets/converted/models/f15/f15c.glb`. Its licence (GPL-2.0-only) keeps it out
of our GPL-3.0-or-later repo, but anyone may use and change it, so it is handled like the game's own data: fetched
and converted on the player's machine, never committed or distributed (graphics-research.md §3.7). Without the file
(setup offline, or not run since) every F-15 keeps the original model with Models Detailed.

| item | value |
|---|---|
| source | Richard Harrison's (Zaretto) F-15C, `github.com/Zaretto/fg-aircraft` `aircraft/F-15` at commit 062cb58 (2020-01-03): 3D model by Enrique Laso, rig by Richard Harrison, cockpit textures by GeneB; GPL-2.0-only (docs/credits.md) |
| download | 9 files, about 17 MB, into `assets/source/f15/` (kept; each checked against its pinned SHA-256): `f15c.ac`, the nozzles, the pilot, the front cockpit, the grey livery, `common.png`, the seat and the IAF patch |
| triangles | 42 400 (original: 7 100); runtime LODs as the F-16D |
| textures | the livery 2048² (JPEG), the gear / nozzle / intake atlas 1024², seat 512², pilot patch 512 × 256; compressed to BC1 / BC3 at the parse, about 5 MB of video memory (24 MB as RGBA8) |
| file size | 3.3 MB |
| livery | the IAF F-15C **802 "Panther"** (פנתר) of 133 Squadron (§6.2): FlightGear's grey F-15C (USAF 80-0007) with its US markings painted out (tail codes, fin-tip bands, fin flash, the USAF crests), tinted to the Baz's bluish grey, and our own markings: roundels on the nose and wings, the name, four kill marks, the tail number on the nose and fins, the Baz bird on the outer fins and 133 Squadron's black band with an eagle's head on the inner fins |
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
6. paints the livery (above, §6.2; `ERASE`, `CRESTS` hold the places in the 2048² skin): a painted-out marking is
   filled with the mean of its neighbours until it settles, so the grey runs on smoothly; the skin is tinted
   (`TINT`); each marking (`MARKS`: our PNG, its centre and width in metres on the jet's left, the way the surface
   faces) is projected onto every livery triangle that faces that way within 0.2 m, both sides, each texel sampled
   3 × 3 on its triangles, so it lands by its place on the jet whatever the skin's layout;
7. writes the glb: smooth normals from AC3D's crease angles, one material per texture or colour (canopy glass tinted
   and blended), the textures as JPEG / PNG inside.

### 6.2 The livery: F-15C 802

The detailed F-15 wears the markings of one real jet: **F-15C 802** (USAF serial 80-0122), the first F-15C of the
Israeli Air Force, at Tel Nof since August 1981, named **"Panther"** (פנתר) and in 133 Squadron's markings, with
four Syrian kill marks from June 1982[^airhistory802][^twz]. It is chosen because:

- the original's own F-15 (`f15.png`) has a black fin-tip band with a white emblem over a grey Baz, tail number 808:
  133 Squadron's band, as 802 wears it[^commons802];
- 802 is the best documented Baz with free photos: four CC BY 4.0 photos from 2017 show its nose, name, kills,
  roundel and both fins[^commons802];
- it flew in 1998, the game's year, with the same unit and its 1982 kills.

The photos are from 2017. Whether 802 wore the name, the bird and the band in 1998 is open.

| marking | where (from photos) | size (m) | drawn as |
|---|---|---|---|
| roundel, fuselage | each side under the canopy, centre 4.30 m behind the nose tip and 0.34 m under the canopy sill (its top just under the sill) | 0.57 | white disc, blue Star of David to 0.79 of the radius[^commons802][^commons818] |
| roundel, wings | above and under each wing on the outer panel, 4.9 m from the centre line, mid-chord | 0.60 | the same roundel[^underside][^above] |
| name "פנתר" | each side behind the radome joint, centre 2.49 m behind the nose tip | 0.47 × 0.20 | blue Hebrew script, our strokes traced over the photo[^commons802] |
| kill marks | above the name, centre 3.09 m behind the nose tip | 4 × 0.19 | Syrian roundels: red, white, black, three green stars[^commons802] |
| tail number, nose | below the kill marks, centre 3.27 m behind the nose tip | 0.29 × 0.15 | blue square-cut digits[^commons802] |
| red emblem | outer face of each fin, at the top | 0.13 × 0.24 | a red crowned drop (its meaning open)[^commons802] |
| bird of prey | outer face of each fin, middle | 0.94 × 1.41 | black line drawing, facing forward, our own simplified one[^commons818][^twz] |
| tail number, fins | outer face of each fin, low | 0.68 × 0.35 | black digits[^commons818] |
| squadron band | inner face of each fin, 2.14–3.09 m above the datum, under a grey tip | 0.95 high | black, a white eagle's head facing forward, our own drawing[^commons802][^underside] |

The sizes and places are measured on the photos, scaled by the roundel (0.57 m) and the radome (2.2 m), within
about 10 % (inferred: the camera angles). The nose roundels are about 15 % smaller than the IAF F-15I livery's of FlightGear
(0.66 m) and 0.2 m higher; the wing roundels are 0.6 m instead of 0.8 m, 0.5–0.75 m further inboard and
0.25–0.4 m further forward. The
upper wing roundels are seen on one IAF Baz from above[^above]; that both wings carry them is inferred. That the
name, kills and tail number are on both sides is inferred (the photos show the left side).

The paint: the IAF's air superiority scheme is FS 36320 Dark Ghost Grey and FS 36375 Light Ghost Grey, from the
F-15A/B in 1976[^ak]. FlightGear's grey is neutral; the photos of 802, white-balanced on its roundel's white, show a
bluish grey (red : green : blue about 0.89 : 0.95 : 1). The converter scales the skin's channels by 0.90, 0.95, 1.0
(inferred). 802's radome is the body's grey with a dark tip, as FlightGear's.

The markings are our own drawings, SVG in `crates/iaf-tools/data/f15-livery/` with the PNGs the converter reads
(`render.sh` makes them with rsvg-convert on a developer's machine; setup reads only the PNGs). The photos are
references only and are not in the repo.

### 6.3 How it fits the game

As the F-16D (§1.1): the descriptor stays the original's; `detailed_descriptor` takes the hinge axes, both
afterburners (EngineL / EngineR) and LdgDrUp from the model. Its speed brake and hook are modelled shut in place, so
they show also shut (the original F-15's hide when shut). The hinge axes lie within 8° of the original's (the
rudders' sweep); the gear legs swing about FlightGear's first retraction axis only (FlightGear also turns the main
wheels flat), so a leg in transit takes a simpler path. `util/gltf.gd` maps `f15_h.gltf` to the file under
`assets/` (DETAILED's paths without `res://`), parses it with LODs and compresses its textures (`_made_by_setup`).

### 6.4 Checks

- `tests/godot/test_detailed_models.gd` `_check_f15` (skipped when setup has not made the file): with the switch off
  the original; on, the setup's model with 30–60 k triangles, every node of the original, the helpers within 1 cm,
  pivots on their parts with axes within 20° of the original's, the pylons under StationB / E / H (5 cm), two
  afterburners on the detailed nozzles, the livery compressed, the gear and doors' visibility, and the player's F-15
  in mission 311.
- `cargo test -p iaf-tools f15`: the sources pinned, the frames, and the whole conversion on `assets/source/f15`
  when it is there; `cargo test -p iaf-formats ac3d`; `cargo test -p iaf-setup` (the step skips offline).
- `tests/godot/_model_shot.gd` with `SHOT_JET=0`: the before / after pictures (on the ground from the front-left and
  rear, in flight from the side, above and below, the gear and surfaces moving mid-roll, a loadout on the pylons; the
  livery's nose, left and right sides and both fins' faces).
- `cargo test -p iaf-tools f15` `marks_land_in_place`: a square of skin round the nose roundel's place takes the
  roundel on both sides.

### 6.5 Tried and dropped

- 2026-10-28: painting the US markings out column by column (from the colour above to the colour below) left vertical
  streaks on the fins, whose paint is lighter at the leading edge; replaced by the settled mean of the neighbours.
- 2026-10-28: FlightGear's IAF F-15I livery (69 Squadron) as it is: real IAF markings, but the F-15I's desert
  camouflage on an F-15C, where the original's F-15 is a grey Baz.
- 2026-10-28: FlightGear's F-15I roundels cut out and laid on the grey skin: too large on the nose (0.66 m) and
  wings (0.8 m), the wing ones too far out; replaced by our own roundels at 802's places (§6.2). Its radio call plate
  (tail number 269, an F-15I) is no longer copied: the plate's object is left out of the model anyway.
- 2026-10-28: the nose markings placed by the side photo of 818 on landing: 0.24 m too low, as the jet flew nose up;
  placed again by the canopy sill on 802's photos. The wing roundels at 4.7 m from the centre line sat just
  outboard of the pylons, inboard of the photos' place; moved to 4.9 m.

### 6.6 Open

- Where a US marking was painted out, the panel lines are gone. FlightGear's small USAF stencils stay.
- The markings are as sharp as the 2048² skin allows: about 7.5 mm per texel on the nose, 13 mm on the fins.
- The meaning of 802's red fin emblem, and which markings it wore in 1998, are open (§6.2).
- The cockpit view's own-jet model (`own_bc`, the original's `f15_bc`) stays the original's (the F-16D's is its
  own detailed model, §1.4). The
  front cockpit shows its tub, glare shields and seat, without the instrument panel (its textures are SGI `.rgb`
  files, which the converter does not read).
- No original model as the far LOD (as the F-16D; the stores have it).
- The gear legs retract about one axis (above); the nozzles keep their modelled opening.

## Sources

[^f16net]: F-16.net forum, "F-16 B/D two seater version canopy" (a canopy shop's account: two transparencies in
    one frame, the centre strip part of the frame, the actuator's support yoke on it),
    https://www.f-16.net/forum/viewtopic.php?p=27770
[^blueflag]: U.S. Embassy Tel Aviv, "F-16I at Blue Flag 2015 - pic01.jpg", Wikimedia Commons, CC BY 4.0 (an F-16I
    taxiing, side on), https://commons.wikimedia.org/wiki/File:F-16I_at_Blue_Flag_2015_-_pic01.jpg
[^hatzerim]: Oren Rozen (derivative by Poliocretes), "Hatzerim 270416 Sufa-F-16I v01.jpg", Wikimedia Commons, CC
    BY-SA 4.0 (F-16I 893 parked, the canopy close),
    https://commons.wikimedia.org/wiki/File:Hatzerim_270416_Sufa-F-16I_v01.jpg
[^bayit432]: IDF Spokesperson's Unit, "F-16I (IAF).jpg", Wikimedia Commons, CC BY-SA 3.0 (F-16I 432 in its
    shelter, side on), https://commons.wikimedia.org/wiki/File:F-16I_(IAF).jpg
[^airhistory802]: AirHistory.net, photo 600613 of F-15C 802 (caption: 80-0122, the IAF's first F-15C, at Tel Nof
    in August 1981, "Panther", 133 Squadron markings, four Syrian kill marks of June 1982),
    https://www.airhistory.net/photo/600613/802
[^twz]: The War Zone, "These Are The Best Photos Of Israeli F-15 Baz Eagles We've Ever Seen" (kill roundels on the
    forward fuselage, 802 with four; 106 Squadron's red stripes and badge on the inner faces of the fins; the bird of
    prey across the Baz fleet), https://www.twz.com/these-are-the-best-photos-of-israeli-f-15-baz-eagles-weve-ever-seen
[^commons802]: MathKnight, "IAF-F-15C-Baz--Independence-Day-2017-Tel-Nof-IZE-082 / 084 / 086 / 086-kill-marks.jpg",
    Wikimedia Commons, CC BY 4.0, 2 May 2017, https://commons.wikimedia.org/wiki/Category:F-15C_Baz
[^commons818]: "McDonnell Douglas F-15C-28-MC Eagle (Baz) '818' (48644505872).jpg", Wikimedia Commons, CC BY-SA
    2.0, 28 August 2019 (106 Squadron, right side),
    https://commons.wikimedia.org/wiki/File:McDonnell_Douglas_F-15C-28-MC_Eagle_(Baz)_%E2%80%98818%E2%80%99_(48644505872).jpg
[^underside]: IDF Spokesperson's Unit, "Israel 75th Independence Day - Israeli Air Force Fly By LXVII.jpeg",
    Wikimedia Commons, CC BY-SA 3.0, 26 April 2023 (a 133 Squadron Baz from below: the wing roundels, the band),
    https://commons.wikimedia.org/wiki/File:Israel_75th_Independence_Day_-_Israeli_Air_Force_Fly_By_LXVII.jpeg
[^above]: דוידי ורדי, "95675 air combat falcons PikiWiki Israel.jpg", Wikimedia Commons, CC BY 2.5, 2019 (a Baz
    from above: a roundel on the upper wing),
    https://commons.wikimedia.org/wiki/File:95675_air_combat_falcons_PikiWiki_Israel.jpg
[^ak]: AK Interactive, Israeli Air Force colours (AK11752), product text: the air superiority grey scheme of FS 36320
    Dark Ghost Grey and FS 36375 Light Ghost Grey came with the F-15A/B at the end of 1976,
    https://ak-interactive.com/?p=256303
