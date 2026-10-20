# World scale: Original / Real 1:1 (research and plan)

This page is the research and the plan for the roadmap item "Real world scale — 1:1 mode" ([roadmap.md](roadmap.md)).
It lists what is not drawn at real size today, what depends on those sizes, a design for the switch, and a step
plan. Steps 1–4 (true-size models on the original bases) are built, behind a dev flag (§4.1); steps 5–9 move every
base to its real place (§3.3). Research date: 2026-10-20.

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
  Damascus, Kuzeir and Aman lie within 0.5–1.6 km of the real base; the other seven lie 7–63 km away (§1.2).
- **The design:** Real 1:1 draws every model at its true size (scale 1) and moves each airbase to its real place:
  one transform per base puts the game's main runway on the real one, at its real length and heading; the base's
  layout, its mission units and markers move with it (the "base move", §3.3).

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
| Bley | Marj Ruhayyil AB (inferred) | 62.8 km | 235° 4058 × 95, 055° 3860 × 96 | 063° 3084, 063° 2884 (parallel) | 0.76 |
| Ryak | Rayak AB | 28.6 km | none in the art (AI's 3000 × 45 at 090°) | 047° 3046 | 1.02 |
| Aman | Queen Alia | 0.7 km | none in the art (AI's 3000 × 45 at 260°) | 080° 4004, 080° 4044 (61 m wide) | 1.33 |

What the table shows:
- **The runways are enlarged by 1.13–1.45** where the art has runways (k = 0.69–0.88). The bases without art
  runways use the AI's default 3000 m, which is close to real or short (Aman).
- **The widths are enlarged more:** 75–97 m in the game against 45–61 m where OpenStreetMap gives a width. The
  Israeli bases' real widths are open.
- **The layouts are not the real ones** ([imagery.md](imagery.md) §9): no move, rotation and single scale puts the
  game's runways on the real ones (residuals 340–890 m at the three Israeli bases). Ramon is also turned 17°.
- **Bley** (checked 2026-10-20). The briefings (237, 511) call it a Syrian MiG base; the game puts it next to
  Tha'lah AB (32.712 N 36.425 E[^thalah], 2.8 km away). OpenStreetMap has no aerodrome or runway named Bley / Ble /
  بلي; its only match is the village Beli (بلي, 33.224 N 36.463 E[^beli]), 6.6 km south of Marj Ruhayyil Air Base
  (33.283 N 36.464 E[^osm]) and 17 km north-west of Khalkhalah Air Base (33.081 N 36.562 E[^khalkhalah]). A report of
  a "Ble (Bley) airport" ≈ 45 km south of Damascus (ynetnews / Intelli Times, 2023) gives no coordinates; open.
  Inferred: Bley is the air base named after the nearest village, Marj Ruhayyil (2 runways at 063°, 3.0 and 2.8 km;
  31 km from Damascus, Khalkhalah 55 km). The base moves 62.8 km north-east.
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

**Airbase-bound** (they move with their base, §3.3):

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
| models | Present scale | scale 1 (true size); the kept ground models (§3.2) follow their base |
| hit volumes, gear clearance, eye, views, LOD | from the Present scale | from scale 1 (follow by themselves) |
| airbases | the 1998 ×2 layout at the game's places | each base moved to its real place, on its real main runway (§3.3) |
| base-bound mission units, markers, routes | the game's | moved with their base (§3.3) |
| ground, routes and missions away from bases | unchanged | unchanged |
| weapon, sensor, blast, sound ranges | unchanged | unchanged (decision 4: real values once sourced) |

**How the modes coexist:** one setting, `Settings.world_scale` = "original" / "real" (settings.cfg, Extras page).
It is read at mission load only: the models get their scale when spawned, the base moves are set up before the
terrain and the mission load. No converted data changes; both modes run from the same `assets/`. In multiplayer the
host's setting must apply to every peer (inferred: positions on bases differ between modes; docs/multiplayer.md).

One helper decides every model scale: `model_scale(present, keep)` (§4.1).

### 3.2 Models

- **Objects** (jets, vehicles, SAMs, buildings, shelters, hangars, the tower, ships aside): scale 1 (decision 2).
- **Kept models** (§4.1: the light sets `LT_*`, the flat underlays, the sign groups, the SA-5 cables): they are laid
  out on the base's ×2 picture, so on a moved base they take the Present scale × k and the base's turn, about their
  own origin at the moved position. The underlays stay hidden as today.
- **Exceptions:** the cloud keeps 8.0 and the crater 7.0 (effects, not real things); the stadium already is 1.0; the
  speed boat's 0.5 and the ships stay until measured (§1.1).

### 3.3 Airbases: each base at its real place (the base move)

Decision 1 (§5) moves all ten bases to their real places. This replaces the in-place "base warp" of the first plan.
The game's base layout (its runways, taxi paths, hangars, shelters, parked jets) moves as one piece; it is not the
real layout (§1.2), but its main runway lies exactly on the real one.

**The real runway table.** `crates/iaf-flight/data/real_runways.csv`: the OpenStreetMap runway ways of the ten real
bases (decision 5; © OpenStreetMap contributors, ODbL 1.0, the attribution in the file's header), their ends in
lat/lon and in engine metres through the georeference ([georef.md](georef.md)). Made by `tools/real_runways.py`
(Overpass API, then `iaf-terrain game` per end). Width: the OSM `width` tag (Mezzeh and Al Qusayr 45 m, Queen Alia
61 m), else 45 m (decided by the agent, to confirm: the Israeli widths are open). Bley = Marj Ruhayyil (inferred,
§1.2). Designator: the OSM `ref` (e.g. "07L/25R", magnetic), else from the magnetic heading with a declination of
5° E (Inshas, Marj Ruhayyil, Rayak, one Bir Gifgafa way; inferred[^wmm]).

**The transform of a base** (`iaf_flight::base_move`, Rust): a similarity (move, turn, one scale k) set by the main
runway.
- **Game side:** the runway through the lineup point (airbases.json's first runway), taken on the line through the
  lineup point at RunwayNumber's heading: P0 = its start end, P1 = its far end, both projected on that line.
- **Real side:** the real runway (and its direction) whose heading is nearest RunwayNumber's; parallel runways within
  1° → the longer. A = its start, B = its far end.
- **The map:** P0 → A, P1 → B. So the lineup point lies on the real centreline, the take-off heading becomes the real
  heading, and k = |AB| / |P0P1|: the runway takes its real length. The real width is drawn and fed to the FM
  separately (below), so the base's other parts keep the uniform k (an axis-wise width scale would squeeze every apron
  across the runway by 0.46–0.6).
- **Zone A, the base:** the box along the game runway around its ends and every iaf.ibx point (tower, lineup, taxi
  paths, hangars), plus 500 m. Points inside take the similarity.
- **Zone B, the base's surroundings** (only for the seven bases moved more than 5 km: Ramon, Tel Nof, Ramat David,
  Refidim, Inshas, Bley, Ryak): up to 6 km beyond zone A. Points there move and turn with the base and keep their distance
  from zone A's edge (per axis: `u' = k·hi + (u − hi)` beyond the box). This carries the base's SAM / AAA rings,
  circuit markers and sensors (§1.2: 2–6 km out) without stretching them. Beyond zone B nothing moves.
- **The three near bases** (Damascus 1.6 km, Kuzeir 0.5, Aman 0.7 km) move only zone A. Their surroundings
  stay with the painted ground (Damascus city's buildings and street lights in "darkness", 2–5 km from the runway;
  Aman's SA-6 sites, 2.8–3.8 km). Decided by the agent, to confirm.
- **Altitudes:** every moved point keeps its height over the base: z + (the new site's elevation − the old lineup's
  z). The new site's elevation is the original terrain's mean height along the real runway.

The moves (test `every_base_sits_on_its_real_runway`, crates/iaf-flight/tests/base_move.rs):

| base | real main runway (take-off heading, length × width) | turn | k | the base's middle moves |
|---|---|---|---|---|
| Ramon | 247° 2990 × 45 m (07R/25L) | +17.1° | 0.85 | 17.6 km |
| Ramat David | 267° 2934 × 45 m (09/27) | −3.4° | 0.69 | 7.3 km |
| Tel Nof | 151° 3198 × 45 m (15L/33R) | +61.1° | 0.72 | 17.0 km |
| Refidim (Bir Gifgafa) | 327° 3066 × 45 m (15L/33R) | +57.4° | 0.78 | 17.2 km |
| Inshas | 271° 2576 × 45 m | +1.0° | 0.86 | 25.0 km |
| Damascus (Mezzeh) | 240° 2834 × 45 m (06/24) | +0.3° | 0.72 | 1.6 km |
| Kuzeir (Al Qusayr) | 280° 3127 × 45 m (10/28) | +0.2° | 0.84 | 0.9 km |
| Bley (Marj Ruhayyil, inferred) | 243° 3084 × 45 m (06/24 from the heading) | +8.1° | 0.76 | 64.8 km |
| Ryak (Rayak) | 047° 3046 × 45 m | −43.3° | 1.02 | 28.8 km |
| Aman (Queen Alia) | 260° 4044 × 61 m (08L/26R) | +0.1° | 1.35 | 0.2 km |

RunwayNumber takes the real heading exactly (a float; the HUD ILS truncates it to whole degrees as the original
reads an integer).

**What uses it** (each in Real only; Original takes none of these paths):

| thing | how |
|---|---|
| iaf.ibx (tower, lineup, taxi points and headings, hangars, turn points) | mapped at load (`IafFlight.ap_setup`, `start_rule`, `radio.gd`); RunwayNumber = the real heading (the AI's take-off and landing, the ILS, the circuit: docs/autopilot.md) |
| mission entities, paths, formation routes | mapped in `mission_files()`: position, heading + turn, altitude; zone A's reached / left radii × k |
| terraintype.dat (the FM's runway bit) | inside the new zone A: the original's flags at the inverse-mapped point; the old base's runway leaves are rough ground |
| terrain heights | the new site flattened to its elevation inside zone A, a smooth 1.2 km ring around it (height images patched as they load: the drawn ground, `height_at`, `IafHeights`) |
| the old painted base | its paved surface painted over with its surroundings' colour (the colour images patched as they load, every level, the original art and the imagery layers) |
| the new base | its paved surface painted grey at the new site (seen from afar), and the Detailed airbases surface there (forced on in Real), from the moved runways at the real width and the base's mask turned and scaled |
| night lights | the light sets as kept models (§3.2); `BASE_LIGHTS` spots mapped |
| TSD icons | the type-450 runway entities are mission entities (mapped) |

**What stays:** units, routes and markers beyond zone B (or zone A at the near bases), LandingCL's pattern sizes and
the radio's zone sizes (fixed metres in the exe), the 1998 imagery and heights away from the two sites.

**Why this design** (inferred): one transform per base, from the original data at run time, switches off completely
in Original. The moved base keeps every mission's logic (its units and markers move with it). It needs no new
imagery: the 2015 photo hides the real Israeli bases (imagery.md §9), and the procedural surface draws the base.

## 4. Step plan

Each step is testable on its own and changes nothing in Original. Sizes: S < 150 lines, M 150–500, L > 500.
Godot tests set `Settings.world_scale = "real"` before `start_mission()` and run with `IAF_DEFAULT_SETTINGS=1`.

| # | step | tests | size |
|---|---|---|---|
| 1 ✓ | The setting: `world_scale` in `settings.gd` / settings.cfg, the Extras row, the `model_scale()` helper (returns the Present scale in Original). docs/deviations.md row | Original: `test_airbase_scale.gd` passes unchanged; a settings round trip | S |
| 2 ✓ | Mission models at true size (objects 1, ground models kept at ×2 for now); the underlay test on the Original height | 311 in Real: an AI F-16's node scale 1, a T-72 1, the Ramat David underlay 2; coll_radius half of Original's; the same units hidden in both modes | S |
| 3 ✓ | The player's and AI jets at true size: model, `own_bc`, gear clearance | 311 ground start in Real: clearance 1.69 m, the jet stays on the runway (no crash, wheels on the ground), eye offset half; Rust `cargo test -p iaf-flight` with a 1.69 m clearance: take-off to 100 m AGL and an autopilot landing at David | M |
| 4 ✓ | Weapons, stores, rounds at true size (`STORE_PRESENT_SCALE`, rocket box, `w.scale`) | a store's drawn position equals its launch point; the stores sit on the pylons (`_stores_shot`-style capture, by eye) | S |
| 5 ✓ | The real runway table (`tools/real_runways.py`, `real_runways.csv`, ODbL) and the base move in Rust (`iaf_flight::base_move`): the transform, zones A / B, the inverse, iaf.ibx mapped, the surface rule, the pad heights | unit tests: each moved main runway on its real one (ends < 1 m, length, heading), zone continuity, identity beyond, inverse round trip; an autopilot take-off and landing at the moved Ramat David and Ramon (flat ground at the new elevation, the surface rule's runway bit under the wheels) | M |
| 6 ✓ | Godot wiring of the base data: `IafBases` (set up from Settings.world_scale: airbases.json, the masks, the elevations), `ap_setup` / `start_rule` / `radio.gd`, `surface_at` and the surface raster, the height pad | headless: in Real the ground is flat at the moved lineup, its surface has the runway bit and the old lineup's has not; a ground start at the moved lineup; Original unchanged | M |
| 7 ✓ | Mission data through the move (`mission_files()`): entities, paths, routes, radii; kept models × k and turned; `BASE_LIGHTS` | 311 in Real: the player on the moved lineup with the engine on, the parked jets on the moved apron (relative positions = Original's × k, turned), the take-off markers fire on the take-off; a SAM site around a moved base kept relative; 312's landing completes with the autopilot | M |
| 8 ✓ | Drawing: the old site painted over, the new site's paved surface (colour images), the Detailed airbases surface at the new site (turned mask, real width), forced on in Real | `test_airbase_scale.gd` (Original) unchanged; Real: the moved base data; real-render shots of Ramat David and Ramon (original terrain and Survey imagery) and of the old site | M–L |
| 9 ✓ | Docs (deviations, status, rendering §7, autopilot, this page) and a sweep | `tools/mission_sweep.sh` over the menu missions in Real: no SCRIPT ERROR, no ground start crash | S |

Steps 1–4 give true-size models on the ×2 bases; steps 5–9 move the bases. The switch stays hidden (a dev flag)
until the user decides to show it.

### 4.1 Steps 1–4: what was built (2026-10-20)

- **The setting:** `Settings.world_scale` ("original" / "real", settings.cfg `[gameplay]`), read at mission load.
  Its Extras row ("World scale": Original / Real 1:1) shows only with the environment variable
  `IAF_DEV_WORLD_SCALE=1` until step 9.
- **The helpers** (`game/settings.gd`): `model_scale(present, keep)` returns the Present scale in Original and in
  Real for a kept model, else 1. `keeps_present(path, raw_box, present, klass, flat)` names the kept models: the
  light sets (`LT_*`), the flat underlays (their Original height under 0.05 m), the multi-part layouts
  `KEPT_LAYOUTS` (the sign groups SIGNTLNF / SIGNRMON / SIGNRFID / SIGNDVID, the SA-5 cables), the effects (Present
  ≥ 7: the cloud, the crater) and the ships (class 15, 16). Following decision 2 (§5), buildings, shelters, hangars,
  the single runway signs (`sign09l` …) and the power plant (`ppchbg_h`, 302 m raw) are objects at 1, not kept by
  their size; the 200 m rule of §3.2 is replaced by this list.
- **Where it applies:** mission models (`terrain_view.gd` `_spawn_mission_objects`; the underlay hide test reads
  the Original height, so the same units hide in both modes), the player's jet and its cockpit model
  (`_spawn_player`), the AI jets (`ai_flights.gd`), the weapon models and rounds (`weapon_db.gd`: `w.scale`; the
  stores on the pylons ride on the jet's scale, the rocket box keeps its ×2 relative to the jet), the briefing's
  target view (`model_view.gd`). The front-end model viewer's fixed ×10 stays.
- **What follows by itself** (derived from the node scale): collision radii, the gear clearance (`height` helper ×
  scale: F-16 3.38 → 1.69 m, set into the FM by `set_gear_clearance`), the eye offset (F-16 8.98 → 4.49 m ahead),
  the gun muzzle, the LOD distances, the orbit views, the EO pick, the missile trail head, the burned copy jitter.
  The flight model needed no change; the clearance is its one size input.
- **Stores:** at 1:1 a store is drawn at its launch point (`body_to_world(attach)`); at ×2 it is drawn 5.3 m off it
  (F-16, mission 311).
- **Hit volumes (decision 4):** with Weapon data Real the gun hit sphere and blast radii are to take real values
  for true-size targets. No sourced values yet, so both modes keep the original's; the switch point is
  `weapon_db.gd` `create` (open).
- **Tests:** `tests/godot/test_world_scale.gd` (the helper and a settings round trip; missions 311 and 214 in both
  modes: every unit at 1 with its radius / Present scale, or kept; 11 AI jets, 15 SAM / AAA units, 71 buildings at 1;
  the same units hidden; the player's jet ×1, its origin 1.69 m over the runway, eye and gun halved, stores at their
  launch points; a take-off from 311 and the autopilot's landing in 312 in Real). Rust:
  `takes_off_from_ramat_david_real_size`, `lands_at_ramat_david_real_size` (crates/iaf-flight/tests/autopilot.rs).

### 4.2 Steps 5–8: what was built (2026-10-20)

- **Rust** (`crates/iaf-flight/src/base_move.rs`): the table, the transform, zones A / B, iaf.ibx mapped
  (`map_airbase`), the surface rule, the flattened sites, and the image patches (`bake_heights`, `bake_colour`).
  The Godot bridge `IafBases` (`crates/iaf-godot/src/bases.rs`) holds the moves for the process; `Settings.sync_bases()`
  sets them up from `world_scale` (once per change) and `Settings.base_moved(x, y)` maps a point.
- **The flight model:** `IafFlight.ap_setup` and `start_rule` map iaf.ibx; `radio.gd` maps its tower, lineup,
  hangars and runway heading; `terrain.gd surface_at` and the `IafSurface` raster go through the surface rule. On a
  new site the original's runway leaf flags apply as they are (0x10); an old site's runway leaves read as land (0x1:
  rough ground off a runway).
- **The terrain images** are patched where `IafBases.bounds()` touches a node: heights (the new site at its
  elevation, the 1.2 km ring) and colours (the old paved surface, its painted edges and the base's grey replaced by
  the colour and texture of the coloured ground ≈ 400 m away; the new site's paved surface painted grey). The
  extension is not callable from the decode workers, so the patch runs on the main thread when the image arrives
  (`terrain.gd _bake`, about 10–40 ms per patched node, only the nodes on the sites).
- **The mission data** moves in `MissionRuntime.mission_files()` (`move_with_bases`): so the flight, the AI, the
  routes, the TSD and the briefing all read the moved positions. A kept layout on a moved base gets × its
  `base_scale`.
- **The Detailed airbases surface** (`airbases.gd`, `terrain.gdshader`): in Real `IafBases.base()` gives each base's
  runways at the new site (the real width, the thresholds × k, the numbers from the new headings) and the mask's
  inverse map; the shader reads the mask through `airbase_mask_xf` (a 2 × 2 matrix; in Original the axis-aligned
  scale) and `airbase_mask_rect.xy` (the offset). On in Real whatever the Graphics setting.
- **Tests:** Rust `crates/iaf-flight/tests/base_move.rs` (every base on its real runway; the moved lineup on runway
  ground, the old one not; the autopilot's take-off and landing at the moved Ramat David and Ramon with the
  player's surface rule on) and the unit tests in `base_move.rs`. Godot `tests/godot/test_base_move.gd` (Original
  unchanged; Real: the moved lineup on runway ground, the old one rough; the radio's base; the site flat at its
  elevation; the start rule; 311's start on the moved base on its wheels; 311's and 122's base units with their
  distances × k and headings turned; 237's SA-3 site at Ryak kept around its radar; the Detailed surface's moved
  runways). `test_world_scale.gd`: kept layouts × k; its Real take-off now from Ramon's lineup (315); the autopilot
  landing of 312 at the moved Ramat David.

**Sweep (2026-10-20):** `SWEEP_WORLD_SCALE=real SWEEP_SECONDS=60 tools/mission_sweep.sh` over 20 missions on bases
(the ground starts 121, 131, 211, 231, 233, 234, 311, 313, 315, 322, 401, 403, 404, 407 and 112, 122, 221, 227, 237,
312): every ground start on runway ground (0x10), every mission passes, no script or engine errors.

**Risks**
- **Shorter runways.** The runways are 0.69–0.86 × the game's, and the AI's touchdown (≈ 1.9 km past the lineup point,
  as in Original) leaves 0.5 km at Ramat David. A take-off from a mission start that is not the lineup can run out
  of runway: 311's start is 0.7 km from the end of the runway it faces.
- **The old site** (after §4.3): a faint smooth patch where the paved surface was; the painted shelters, trees and
  buildings more than ≈ 100 m off the paved surface stay.
- **The new site's ground** close up is the 1998 art's coarse level (≈ 10 m a pixel; §4.3).
- **Seen from the cockpit, the targets halve.** Gun and missile rules are unchanged (25 m hit sphere), so hitting is
  as easy as before, but finding a target by eye is harder (the original chose ×2, maybe for 640 × 480; inferred).
- **The two sites.** The old site keeps the 1998 art's painted shelters and buildings outside the paved surface
  (only the paved surface is painted over). The new site is the game's layout, not the real one; with a modern
  imagery layer the real base's own runways may show beside the drawn ones where the photo shows them (outside
  Israel's 2015 photo).
- **Gear clearance.** Halving it changes the ground effect (φ 0.97 at 3.38 m, 0.88 at 1.69 m) and the take-off
  rotation. Checked (§4.1): the autopilot's take-off and landing at David and the player's take-off and landing
  work at 1.69 m. docs/flight-model.md §10 quoted 1.69 m for Original; corrected to 3.38 m (the helper's 1.69 m × 2).
- **The shatter pieces** use the unscaled local offset for their speed, so their spread already ignores the scale
  (half the exe's at ×2, inferred); unrelated to this switch but visible after it.
- **iaf.ibx parse bug (found here, unrelated to the switch) — fixed 2026-10-20.** Ramon writes `RunwayNumber=230.0`
  and counts `5.0`, Ryak `90.0`, Aman `260.0`; the ini reader's integers now take a written float and truncate it, as
  the exe does (`FUN_0054eda0`), so those bases get their headings and Ramon its taxi points and hangars.

### 4.3 Polish (2026-10-20)

- **The AI's final approach holds the centreline** (`Autopilot::align_final`, set by `IafFlight.ap_setup` when the
  bases are moved; `Landing::align_bank` in `crates/iaf-flight/src/autopilot.rs`). The original's FinalApproach
  lateral law (bank = −0.0014 · cross + heading error, `5d4c50`) is underdamped: from the 100–700 m the base turn
  leaves at some headings it still swings ±80 m at the threshold, and StopPlane's float keeps the wings level, so the
  jet drifts on (at Ramon, 247°: 78 m off at touchdown). In Real the final approach and the float steer the track to
  the centreline at −cross / 8 s (an intercept of at most 30°), the heading at 3× the original's gain, bank at most
  30°. Touchdown at the moved Ramat David and Ramon: 0.0 m off the centreline (was −8 and 78 m). Original keeps the
  exe's law. Tests: `crates/iaf-flight/tests/base_move.rs` (touchdown within 3 m of the centreline),
  `tests/godot/test_world_scale.gd`.
- **The old site's ghost and seams** (`BaseMoves::add_fill_source` / `finish_fill`, `terrain.gd _fill_sources`).
  Each node used to paint the old paved surface from its own pixels: the 400 m blur ran out at the node's edges, so
  neighbouring nodes and levels painted different colours (square seams), and every grey pixel of zone A counted as
  paved, so zone A's rectangle showed over grey fields. Now the terrain hands the level-3 colour nodes (≈ 10 m a
  pixel) under each old site to `IafBases.fill_source` once at load; the fill colour (the surroundings' mean plus the
  texture of unpaved ground 400 m away) is computed on that one world grid and every node and level samples it. The
  grey off the paved surface goes only within ≈ 100 m of it, and the paved surface grows by ≈ 20 m, fading out over
  60 m, so the light dirt shoulders along the runways go too. Pictures (old Ramat David from 2.2 km, old Ramon from
  2.5 km): `david_oldtop_before.png` / `david_oldtop_after.png`, `cmp_ramon_oldtop.jpg` (local captures,
  `tests/godot/_airbase_shot.gd`). Left: a faint smooth patch. Tests: the unit tests in `base_move.rs`,
  `tests/godot/test_base_move.gd`.
- **The new site's ground close up — not fixed.** Low over a moved base the ground around the drawn runways looks
  dark and blurred. The cause is the 1998 art: its fine levels exist only over the painted bases (Ramat David's old
  site has level 0, 1.2 m a pixel; Ramon's level 2, 5 m), and at the real sites the finest is level 3 (≈ 10 m a
  pixel) of plain farmland or desert. The patch paints only the moved paved surface; it does not darken. A fix needs
  new fine nodes at each new site (the old site's inset warped through the move, or an imagery layer's photo), a
  change to the terrain's node lists and the converter: out of this polish's reach. With an imagery layer that has
  fine nodes at the new site (`mapi2015` in Israel, 2.5 m a pixel), the real base's photo shows there.

## 5. Decisions (user, 2026-10-20) and open questions

Decided:
1. **The far bases move to their real places** too: all ten bases at their real positions (§3.3).
2. **Base buildings at true size (1:1)**, not the base's k.
3. **Runways at their real proportions:** real length and real width (45–61 m), not a uniform k; the paint and the
   terraintype polygon get an axis-wise warp. Built as (§3.3): the length by the base's k, the marked width (paint,
   edge lines) the real one; the FM's runway leaves keep k (see "Decided by the agent").
4. **Gun hit sphere and blast radii follow the weapon data:** with Weapon data = Real (docs/real-weapons.md) they
   take real values for true-size targets; with Weapon data = Original they stay the original's.
5. **The real runway table may be committed:** a small table of coordinates derived from OpenStreetMap, with the
   ODbL attribution in the repo[^osm].

Decided by the agent (2026-10-20), to confirm:
- The untagged real runway widths (the Israeli bases, Bir Gifgafa, Inshas, Marj Ruhayyil, Rayak): 45 m.
- The main real runway: the one whose heading is nearest RunwayNumber's (the longer of a parallel pair).
- Zones: zone A = the base's box + 500 m (similarity); zone B (6 km, move and turn without scaling) only at the six
  far-moved bases; the near bases' surroundings stay.
- The FM's runway surface on a moved base is the original's terraintype leaves through the base's transform (they
  also cover the taxiways and aprons, so cutting them to the real runway width would make taxiing rough ground).
  The paved shoulders between the real width and the game's width × k stay paved, unmarked.
- The light sets and sign groups are scaled by k with their base; at the real width the runway edge lights stand on
  the paved shoulder (about 11 m outside the edge line at Ramat David).
- The Detailed airbases surface is on at a moved base whatever the Graphics setting (the new site has no painted base).

Open:
- Ships' true size (§1.1): measure the hull parts.
- Bley's real base: Marj Ruhayyil is inferred (§1.2); a source naming the base "Bley" with a place would settle it.

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
[^beli]: OpenStreetMap node 12248489937, place=village, name بلي, name:en Beli (© OpenStreetMap contributors, ODbL):
    https://www.openstreetmap.org/node/12248489937
[^khalkhalah]: Wikipedia, "Khalkhalah Military Airbase": https://en.wikipedia.org/wiki/Khalkhalah_Military_Airbase
[^wmm]: NOAA NCEI, World Magnetic Model 2025, declination calculator: https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml
