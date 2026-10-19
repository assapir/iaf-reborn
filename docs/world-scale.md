# World scale: Original / Real 1:1 (research and plan)

This page is the research and the plan for the roadmap item "Real world scale — 1:1 mode" ([roadmap.md](roadmap.md)).
It lists what is not drawn at real size today, what depends on those sizes, a design for the switch, and a step
plan. Nothing here is built yet. Research date: 2026-10-20.

**The switch:** Extras → World scale: **Original** (the default, the 1998 game unchanged) / **Real 1:1**.

**Terms**
- **Present scale:** the uniform scale of a model, field `0x65e` of the bdb Present record (docs/formats/mis.md).
- **Raw mesh:** a converted model as stored, before the Present scale.
- **Base factor k:** a base's real runway length over the game's runway length.
- **Sources:** a footnote names each outside source. "Inferred" marks our own reasoning; "open" marks a gap.

**Key facts**
- **The ground is already real size** (×0.99–1.01, [georef.md](georef.md)). So mission coordinates, routes, route
  timing and weapon / sensor ranges need no change: they are real metres today.
- **The models are enlarged.** The raw meshes are real size; the Present scale enlarges them: ×2 aircraft and
  buildings, ×3–3.2 vehicles and SAMs, ×4 some radars and trucks (§1.1).
- **The airbases are enlarged, and some are moved.** The game's runways are ×1.13–1.45 the real ones (Aman ×0.75).
  Damascus, Kuzeir, Bley and Aman lie within 0.5–2.8 km of the real base; the other six lie 7–29 km away (§1.2).
- **The design:** Real 1:1 draws every model at its true size (scale 1) and shrinks each airbase about its own
  centre to its real runway length (a runtime "base warp", §3). The bases stay where the missions put them.
  Moving bases to their real places is a separate, later choice (§3.4, open question 1).

## 1. What is not 1:1 today

### 1.1 Models (Present scale)

All the playable missions use one object database, `default6_1.bdb` (221 Present records): 179 at 2.0, 29 at 3.0,
5 at 4.0, 3 at 1.0, 2 at 3.2, 1 each at 0.5, 7.0 and 8.0.

The raw meshes are about real size. Measured: the bounding box of each converted model's visible parts (the
ejection parachute and the gear doors left out), against the real aircraft:

| model | raw mesh (span × length, m) | real (span × length, m) | Present scale | drawn today |
|---|---|---|---|---|
| F-16 | 9.4 × 15.0 | 9.96 × 15.06[^f16] | 2.0 | 18.9 × 30.0 |
| F-15 | 13.3 × 19.5 | 13.05 × 19.43[^f15] | 2.0 | 26.5 × 38.9 |
| F-4E | 12.3 × 19.6 | 11.7 × 19.2[^f4] | 2.0 | 24.6 × 39.2 |
| Mirage | 8.6 × 15.5 | 8.22 × 15.03[^mirage] | 2.0 | 17.2 × 31.1 |
| C-130 | 40.6 × 29.9 | 40.4 × 29.8[^c130] | 2.0 | 81.2 × 59.8 |
| T-72 (with gun) | 3.4 × 9.1 | 3.6 × 9.53[^t72] | 3.0 | 10.2 × 27.3 |

The stores are real size too: Mk-84 3.93 vs 3.84 m, AIM-9 2.85 vs 2.87 m ([graphics-research.md](graphics-research.md)).
So the Present scale is a pure enlargement, and Real 1:1 means scale 1 (inferred).

Present scale per class (bdb object `0x5aa`):

| class | what | Present scale |
|---|---|---|
| 0x1c, 2, 3 | jets, helicopters, transports | 2.0 |
| 5 | tanks | 3.0 (T-55, T-62: 3.2) |
| 6 | vehicles | 3.0 (the `rio` truck: 4.0) |
| 8, 9, 10 | SAM launchers / radars, SA-13, ZSU-23-4 | 3.0 (SA-5 site: 4.0) |
| 11 | radar antennas (P-14, P-35, P-40) | 3.0; masts and radomes 2.0 |
| 12, 13 | buildings, shelters, bridges, targets | 2.0; watchtower 4.0; stadium and its poles 1.0; `ul_dipuns` 3.0 |
| 14 | crater 7.0, cloud 8.0, signs / light sets / parachute 2.0 | as listed |
| 15, 16 | ships | 2.0; speed boat 0.5 |
| weapons | stores, missiles, bombs, rounds | 2.0 |

Where ours applies it (every place reads `0x65e`):
- mission models: `_spawn_mission_objects` in `game/terrain/terrain_view.gd`;
- the player's jet and its cockpit model (`_player_model_scale()`, `own_bc`);
- the AI jets (`game/ai/ai_flights.gd` `_attach`);
- weapons and rounds (`game/weapons/weapon_db.gd`, `STORE_PRESENT_SCALE` in `game/weapons/player_weapons.gd`,
  `game/ai/combat.gd`);
- the briefing's target view (`game/menu/tsd.gd`).

The front-end model viewer uses a fixed 10.0, as the exe (`FUN_0050f9e6`).

**Ships are open.** The Osa model's raw box is 29 × 126 m (the real Osa is 38.6 m long[^osa]), the Israeli boat's
17 × 135 m. Their boxes probably hold more than the hull (a wake?): to be measured part by part.

**What the exe scales.** `FUN_0041bb00` calls the mesh builder's `Scale(s, s, s)` and then `GetBox`. So the extents
at object +0x268..+0x270 are the scaled ones, and the collision, LOD and view code reads those. The `.xfr` loader
(`FUN_0041c270`) scales the frame and helper positions by the same factor: the eye, gun, stations, `height` and
engine helpers all scale with the model. Nothing else in the exe reads `0x65e` (only `FUN_00593b60`, the parser).

### 1.2 Airbases

The ten iaf.ibx bases against the real ones. "Game" = the runways the setup measures in the 1998 art
(`assets/converted/terrain/airbases.json`, [rendering.md](rendering.md) §7). "Real" = OpenStreetMap runway ways
(Overpass query 2026-10-20)[^osm], put into engine metres with the georeference. Headings are in the game frame
(they agree with true north within 1°). The offset is between the middles of the runway sets.

| base | real base | offset | game runways (heading, length × width) | real runways (heading, length) | k |
|---|---|---|---|---|---|
| Ramon | Ramon AB | 17.1 km | 230° 3516 × 78, 050° 3374 × 78 | 067° 2990, 067° 2682 (parallel) | 0.85 |
| TelNof | Tel Nof AB | 16.8 km | 090° 4446 × 92, 150° 3918 × 92 | 151° 3198, 151° 3047, 003° 3020 | 0.82 (150° pair) |
| David | Ramat David AB | 6.9 km | 270° 4264 × 97, 150° 4122 × 97, 030° 3264 × 96 | 087° 2934, 145° 2944, 108° 3154 | 0.69 |
| Refidim | Bir Gifgafa | 17.6 km | 270° 3950 × 77 | 147° 3066, 147° 2492, 157° 3345 | 0.78 |
| Inshas | Inshas AB | 24.8 km | none in the art (the AI's 3000 × 45 at 270°) | 091° 2576, 046° 2595, 046° 2062 | 0.86 |
| Damescuss | Mezzeh | 1.6 km | 060° 3946 × 75 | 060° 2834 (45 m wide) | 0.72 |
| Kuzeir | Al Qusayr AB | 0.5 km | 280° 3702 × 84, 100° 3538 × 75 (parallel) | 100° 3127 (45 m wide) | 0.84 |
| Bley | Tha'lah AB (inferred) | 2.8 km | 235° 4058 × 95, 055° 3860 × 96 | two, about 3 km each[^thalah] | ≈ 0.75 |
| Ryak | Rayak AB | 28.6 km | none in the art (AI's 3000 × 45 at 090°) | 047° 3046 | 1.02 |
| Aman | Queen Alia | 0.7 km | none in the art (AI's 3000 × 45 at 260°) | 080° 4004, 080° 4044 (61 m wide) | 1.33 |

What the table shows:
- **The runways are enlarged by 1.13–1.45** where the art has runways (k = 0.69–0.88). The bases without art
  runways use the AI's default 3000 m, which is close to real or short (Aman).
- **The widths are enlarged more:** 75–97 m in the game against 45–61 m where OpenStreetMap gives a width. The
  Israeli bases' real widths are open.
- **The layouts are not the real ones** ([imagery.md](imagery.md) §9): no move, rotation and single scale puts the
  game's runways on the real ones (residuals 340–890 m at the three Israeli bases). Ramon is also turned 17°.
- **Bley.** [georef.md](georef.md) §4 pairs it with Khalkhalah (42.5 km away). Tha'lah AB (32.712 N 36.425 E[^thalah])
  is 2.8 km from the game's runways and fits the game's position. Inferred: Bley is Tha'lah, not Khalkhalah.
- **Base distances** (all 45 pairs, middle to middle): game / real median 1.01, 5th–95th percentile 0.90–1.18,
  extremes 0.71 (Kuzeir–Ryak) and 1.34 (Damascus–Ryak). Ramon–Tel Nof is 90.5 km in the game, 118.7 km real.

**The base is one consistent ×2 picture.** The runway underlays at ×2 register with the painted runways
(`tests/godot/test_airbase_scale.gd`). The shelters, hangars and the `LT_` light sets also register at ×2 (the
Ramat David edge lights lie a median 2.3 m from the painted edges, rendering.md §7). iaf.ibx's taxi and hangar
points are fixed world metres on that picture. So the 1998 designers drew each base, its models and its data as one
×2 layout, then shrank the runways a little against the ×2 models (inferred).

**Other base data that is position-bound:**
- terraintype.dat's 10 runway polygons (the FM's "runway" bit; land outside every polygon is rough ground, which
  destroys a jet above 25.7 m/s, flight-model.md §15.6.2);
- the imagery footprints (Ramon 8.1 km², Tel Nof 11.0, Ramat David 13.5; imagery.md §3);
- the Detailed airbases mask and runway data (rendering.md §7);
- the night base lights `BASE_LIGHTS` (`game/terrain/night_lights.gd`);
- the TSD airport icons (the type-450 runway entities of the base missions).

### 1.3 Other sizes

| thing | today | scaled with the model? |
|---|---|---|
| explosions, smoke, fire, splash, rings | fixed metres × the event's size (docs/damage.md §6) | no |
| sounds | 3-D min / max from soundstbl (default 50 / 500 m, explosion 500 / 1000 m) | no |
| cockpit, HUD projection | the camera sits at the jet's origin; the HUD is screen-based | no |
| visual range, LOD | LOD switch distance ∝ the scaled model's largest extent (`FUN_00412c60`) | yes |
| crater | Present 7.0, but the crater pool is empty, so none appears | — |
| cloud model | Present 8.0 (4.8 km) | yes; it is not a real thing (kept) |

## 2. What depends on the sizes

Most gameplay numbers are fixed metres or come from the bdb, so they stay as they are in both modes. These follow
the model scale (every one is derived from the node's scale today, so it changes by itself when the scale changes):

| thing | where | today (×2) | at 1:1 |
|---|---|---|---|
| collision radius `0.25·(dx+dy+dz)` | `terrain_view.gd`, `ai_flights.gd`; exe `FUN_0043b1c0` | F-16 ≈ 18.8 m, shelter 36 m | half |
| player vs unit and mid-air collisions | `_check_collisions` (centre distance < the target's radius) | — | targets half as wide |
| radio lineup / runway zones `3(r+ro)²` | `game/audio/radio.gd` | ro = the jet's radius | slightly smaller |
| gear clearance (the FM's ground contact height) | `set_gear_clearance(−height.y × scale)` | F-16 3.38 m | 1.69 m |
| radar altimeter, AGL, the AI's rolling test | via the gear clearance | — | follows |
| cockpit model offset | `own_bc.position = −eye × scale` | F-16 eye 8.98 m ahead of the origin | 4.49 m |
| gun muzzle, muzzle flash, afterburner, nav lights, wingtip trails | model-relative | — | follow |
| missile trail head | 1 m + half the scaled length | — | follows |
| external views' orbit distances | `game/terrain/views.gd` (`dmin` from the largest scaled dimension) | — | half |
| LOD switch distances | `terrain_view.gd` | — | half (same pixel size) |
| EO centre-point pick | the drawn model's box | — | follows |
| burned-copy jitter | `max_extent` | — | follows |
| underlay hide test (scaled height < 0.05 m) | `terrain_view.gd` | — | must test the Original height, or flat-ish models flip |

These do **not** depend on size (they stay in Real 1:1, the original's rules):
- gun round hit sphere 25 m (50 m on Easy aiming), missile hit 1.5 m, bomb burst 2 m, blast radii from the bdb
  (MK-82 50 m), AI and AAA guns aim at the target's centre (docs/weapons.md, docs/damage.md);
- radar: no radar cross-section in the game; range = the mode's NM × 1854 m (docs/radar.md §4). The only size term
  is a small pad on the candidate query (negligible);
- IR seeker, DASH, AI sensors and visual detection: positions only;
- AI formation slots (100 / 200 m lateral, −20 m longitudinal), taxi speed, hangar pivots: fixed metres;
- store release and launch points: `body_to_world(attach)` uses the unscaled descriptor metres. At ×2 a store
  leaves from half the distance it is drawn at; at 1:1 the two agree.

**Airbase-bound** (they change only when a base changes, §3.3):

| thing | count / where |
|---|---|
| iaf.ibx: tower, lineup, runway heading, taxi paths, hangars | 10 bases; the start rule (5 km of the tower), TaxiCL, LandingCL (side offset 5562 m, legs at 7416 / 3708 m), FinalApproach, Park, the HUD ILS, the tower radio (18.5 km range) |
| mission units within 5 km of a base | 675 across the menu missions: David 142, Damascus 96, Tel Nof 82, Refidim 70, Inshas 63, Ramon 53, Bley 51, Ryak 44, Kuzeir 42, Aman 32 |
| ground starts | about 35 missions start the player on a base (lineup or hangar area) |
| reached / left markers near bases | 84 (e.g. 311's take-off markers r 70 / 85 / 1300, 312's landing circuit corners, 121's `land11-24` r 50) |
| route waypoints with action 7 (land) | 299 of 379 routes end on one; only the nearest base's choice matters |
| the mission script | has no landing or runway condition; success comes from the role rules ([mission-runtime.md](mission-runtime.md) §5) |

## 3. Design

### 3.1 What the switch does

| | Original (default) | Real 1:1 |
|---|---|---|
| models | Present scale | scale 1 (true size); the "ground" models stay with their base (§3.2) |
| hit volumes, gear clearance, eye, views, LOD | from the Present scale | from scale 1 (follow by themselves) |
| airbases | the 1998 ×2 layout | each base shrunk about its centre by k (§3.3) |
| base positions | the game's | the game's (moving them is §3.4) |
| ground, routes, missions away from bases | unchanged | unchanged |
| weapon, sensor, blast, sound ranges | unchanged | unchanged |

**How the modes coexist:** one setting, `Settings.world_scale` = "original" / "real" (settings.cfg, Extras page).
It is read at mission load only: the models get their scale when spawned, the base warp is built when the terrain
loads. No converted data changes; both modes run from the same `assets/`. In multiplayer the host's setting must
apply to every peer (inferred: positions on bases differ between modes; docs/multiplayer.md).

One helper decides every scale: `model_scale(present, raw_box)` (one function, used by the seven places in §1.1).

### 3.2 Models

- **Objects** (jets, vehicles, SAMs, buildings, shelters, ships, weapons): scale 1.
- **Ground models** stay with the base and get the base's factor k instead of 1: flat models (the runway / taxiway /
  apron underlays `ul_*`, `*_ul_*`), light sets (`LT_*`), and models whose raw extent exceeds 200 m (the sign
  groups `SIGNDVD` / `SIGNTLNF`, the SA-5 cables). Their parts are laid out on the ground's picture, so they must
  shrink with the picture, not about their own origin (inferred; the 200 m line is ours).
- **Base buildings** (shelters, hangars, squadron buildings, the tower) are objects: true size, at their position
  moved by the base warp. They then stand smaller than the painted shelters under them (open question 2).
- **Exceptions:** the cloud keeps 8.0 and the crater 7.0 (effects, not real things); the stadium already is 1.0; the
  speed boat's 0.5 and the ships stay until measured (§1.1).

### 3.3 Airbases: the base warp

The base is shrunk where it is, by a per-base radial warp, at run time, from the original data:

- **The map.** Around the base's centre c (the middle of its runways): a point at distance d maps to distance
  `d·k` for d < R0 (the base, shrunk), and from R0 to R1 linearly onto `k·R0 … R1` (the ring of countryside
  stretched to close the gap). Beyond R1 nothing moves. R0 = the footprint's radius (≈ 2–3 km), R1 = R0 + 2 km
  (inferred values). The map is continuous and has an exact inverse.
- **What uses it:**
  - the terrain shader samples the imagery (and the Detailed airbases mask) at the inverse-mapped point inside R1;
  - the FM's surface lookup (terraintype.dat) and the height query map the jet's position through the inverse;
  - iaf.ibx points: mapped forward at load (tower, lineup, taxi and hangar points); the runway heading stays;
  - mission units within R1 that stand on the ground: positions mapped forward, headings kept;
  - reached / left markers within R1: position mapped, radius × k (inferred);
  - the night base lights, the Detailed airbases runway data, the TSD runway icons: mapped forward.
- **What stays:** airborne units, route waypoints (only the nearest-base choice uses them), LandingCL's pattern
  sizes (fixed metres in the exe), runway headings (so the radio's spoken numbers stay).
- **k** comes from §1.2: our own table of real runway lengths, committed as coordinates and lengths only, with the
  OpenStreetMap attribution (open question 6). Bases without an art runway (Inshas, Ryak, Aman) get only their AI
  runway length changed (k applies to the 3000 m; Aman grows to 4000 m).
- **Widths** shrink by k too (David 97 → 67 m), still wider than real (open question 3).

Why a warp and not new data (inferred): it needs no new imagery (the real Israeli bases are hidden in the 2015
photo, imagery.md §9), keeps the 1998 art, keeps every mission working, and switches off completely in Original.

### 3.4 Moving bases to their real places (not in this plan)

Six bases sit 7–29 km from the real ones. Moving them would need: the base's art cut out and pasted at the real site
(the old site keeps a painted ghost base in the original imagery), flat terrain at the new site, the terraintype
polygons moved, every base-bound mission unit and marker moved, and the SAM / AAA rings and route geometry around
the base re-fitted. The game's layouts do not match the real layouts (§1.2), so the moved base would still be the
game's base at a real place. Inferred: a large cost for a small gain; left out (open question 1).

## 4. Step plan

Each step is testable on its own and changes nothing in Original. Sizes: S < 150 lines, M 150–500, L > 500.
Godot tests set `Settings.world_scale = "real"` before `start_mission()` and run with `IAF_DEFAULT_SETTINGS=1`.

| # | step | tests | size |
|---|---|---|---|
| 1 | The setting: `world_scale` in `settings.gd` / settings.cfg, the Extras row, the `model_scale()` helper (returns the Present scale in Original). docs/deviations.md row | Original: `test_airbase_scale.gd` passes unchanged; a settings round trip | S |
| 2 | Mission models at true size (objects 1, ground models kept at ×2 for now); the underlay test on the Original height | 311 in Real: an AI F-16's node scale 1, a T-72 1, the Ramat David underlay 2; coll_radius half of Original's; the same units hidden in both modes | S |
| 3 | The player's and AI jets at true size: model, `own_bc`, gear clearance | 311 ground start in Real: clearance 1.69 m, the jet stays on the runway (no crash, wheels on the ground), eye offset half; Rust `cargo test -p iaf-flight` with a 1.69 m clearance: take-off to 100 m AGL and an autopilot landing at David | M |
| 4 | Weapons, stores, rounds at true size (`STORE_PRESENT_SCALE`, rocket box, `w.scale`) | a store's drawn position equals its launch point; the stores sit on the pylons (`_stores_shot`-style capture, by eye) | S |
| 5 | The real runway table (our measurements, §1.2) and the warp in Rust (`iaf-flight` or `iaf-formats`): forward / inverse, per base k, R0, R1 | unit tests: continuity at R0 and R1, inverse round trip < 1 mm, identity beyond R1, David's runway 4264 m → 2934 m | M |
| 6 | The warp on the base data: iaf.ibx points, the AI runway length, terraintype and height lookups through the inverse, BASE_LIGHTS, airbases.json | Rust: the warped lineup lies on a runway cell; an autopilot landing at the warped David stops on the runway; Godot: ground start at the warped lineup with the engine on | M |
| 7 | The warp in the terrain shader (imagery, Detailed airbases mask) | 311 in Real: the painted runway numbers at the warped places (`test_airbase_scale.gd` with k); a capture at take-off, final and 1500 m overhead (by eye, no seam at R0 / R1) | M–L |
| 8 | Mission units and markers on bases: positions within R1 mapped, marker radii × k; ground models (step 2) get k instead of 2 | 311 in Real: each parked jet within its shelter (distance to the shelter origin = Original's × k); the take-off markers fire on the take-off; 312's landing script completes with the autopilot | M |
| 9 | Ground models at k, shelters at true size; the TSD icons; docs (deviations, status, rendering §7, this page) | `tools/mission_sweep.sh` over the menu missions in Real: no SCRIPT ERROR, no ground start crash | S |

Steps 1–4 give true-size models on the ×2 bases; steps 5–9 shrink the bases. The switch can stay hidden (a dev
flag) until step 9, so players never see true-size jets on ×2 bases (inferred; open question 2).

**Risks**
- **Seen from the cockpit, the targets halve.** Gun and missile rules are unchanged (25 m hit sphere), so hitting is
  as easy as before, but finding a target by eye is harder (the original chose ×2, maybe for 640 × 480; inferred).
- **The warp ring.** The countryside between R0 and R1 is stretched up to 1/k (×1.45 at David). Roads and fields
  there look stretched; with a modern imagery layer the ring is visibly distorted.
- **Gear clearance.** Halving it changes the ground effect (φ at 1.69 m) and the take-off rotation; the Real flight
  data's take-off and landing tests need a rerun. docs/flight-model.md §10 (ground effect) quotes 1.69 m for the F-16 on its wheels,
  but today's ×2 clearance is 3.38 m: that line is to be checked.
- **The shatter pieces** use the unscaled local offset for their speed, so their spread already ignores the scale
  (half the exe's at ×2, inferred); unrelated to this switch but visible after it.
- **iaf.ibx parse bug (found here, unrelated to the switch) — fixed 2026-10-20.** Ramon writes `RunwayNumber=230.0`
  and counts `5.0`, Ryak `90.0`, Aman `260.0`; the ini reader's integers now take a written float and truncate it, as
  the exe does (`FUN_0054eda0`), so those bases get their headings and Ramon its taxi points and hangars.

## 5. Open questions

1. Moving the six far bases to their real places (§3.4): wanted, or is "real size where the game puts them" enough?
2. Base buildings at true size on the painted ×2 shelters (they look small on their pads), or the base's k for
   them too (the base stays one picture)?
3. Runway widths: uniform k (67–80 m) or a separate width factor to the real 45–61 m (the paint and the terraintype
   polygon then need an axis-wise warp)?
4. Ships' true size (§1.1): measure the hull parts.
5. Gun hit sphere, blast radii: kept as the original's (proposed); a smaller hit sphere for true-size targets would be
   a "Better" option, not part of this switch.
6. The real runway table derives from OpenStreetMap (ODbL). A small table of coordinates with the attribution is
   proposed; the licence terms for a derived table are to be checked.
7. Bley: Tha'lah (2.8 km) rather than Khalkhalah (42.5 km, georef.md §4)? A runway length from imagery would settle k.

[^f16]: Wikipedia, "General Dynamics F-16 Fighting Falcon", specifications: https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon
[^f15]: Wikipedia, "McDonnell Douglas F-15 Eagle", specifications: https://en.wikipedia.org/wiki/McDonnell_Douglas_F-15_Eagle
[^f4]: Wikipedia, "McDonnell Douglas F-4 Phantom II", specifications (F-4E): https://en.wikipedia.org/wiki/McDonnell_Douglas_F-4_Phantom_II
[^mirage]: Wikipedia, "Dassault Mirage III", specifications: https://en.wikipedia.org/wiki/Dassault_Mirage_III
[^c130]: Wikipedia, "Lockheed C-130 Hercules", specifications: https://en.wikipedia.org/wiki/Lockheed_C-130_Hercules
[^t72]: Wikipedia, "T-72": https://en.wikipedia.org/wiki/T-72
[^osa]: Wikipedia, "Osa-class missile boat": https://en.wikipedia.org/wiki/Osa-class_missile_boat
[^osm]: © OpenStreetMap contributors (ODbL), `aeroway=runway` ways via the Overpass API, queried 2026-10-20:
    https://overpass-api.de/
[^thalah]: Wikipedia, "Tha'lah Military Airbase": https://en.wikipedia.org/wiki/Tha%27lah_Military_Airbase
