# How an aircraft is defined

An aircraft in linux-iaf is **data from the original install + one generic piece of code**:

| what | where | produced by |
|---|---|---|
| 3D model with moving parts (`<p>_h.xfr` → glTF) | `assets/converted/planes/<p>/<p>_h.gltf` | `iaf-convert aircraft` |
| descriptor: parts, hinges, nozzles, stations, type codes | `assets/converted/planes/<p>/aircraft.json` | `iaf-convert aircraft` (`crates/iaf-tools/src/aircraft.rs`) |
| index of all aircraft | `assets/converted/planes/aircraft.json` | same |
| afterburner texture (`afterburn.tga`) | `assets/converted/planes/afterburn.png` | same |
| per-type part rules (the original callback `FUN_0059dd70`) | `game/aircraft/aircraft_model.gd` `part_pose()` | code (a port) |
| afterburner flame (`FUN_004121b0`) | `game/aircraft/afterburner.gd` | code (a port) |
| flight model data | `resource/md/bd.ibx` `[<SECTION>]` + `<n>.dat` envelope | `crates/iaf-flight` (docs/flight-model.md) |
| cockpit | `resource/cockpits/<c>` | `iaf-convert cockpit` (docs/cockpit.md) |

Reverse-engineering details of the part system are in docs/part-animation.md; this page is the practical summary.
Coordinates in the descriptor are **glTF** (the X file with Z mirrored: +X right, +Y up, −Z nose), in metres (the
unscaled X-file units; the original scales every clump by 5, `error.c` "Scale= 5.000").

## 1. The descriptor (`aircraft.json`, format 1)

The converter replays what the original loader does with the frame file (`FUN_0041c850` → `FUN_0041c240`,
`FUN_0041c650`, `FUN_0041c7c0`, `FUN_0053c030`):

* `root`: the root frame (its own mesh is the airframe, always drawn).
* `parts`: every direct child of the root whose name is in the original name table (case-insensitive: the AI planes'
  `LdGr` **is** `LdgR`) with a Subpart id (1..0x27, EngineL 0x3a, EngineR 0x3b): `{id, pivot, axis}`.
  `pivot` = the frame origin; `axis` = unit vector from the hinge helper (`<name>1` / `<name>2`) nearer the model
  origin toward the farther one, or `null` (no `<name>1` helper → the part is never rotated). The part turns about
  its pivot by **+θ** about `axis` (glTF space).
* `dropped`: children that match no table name. The original never draws them (e.g. the MiG-23 `WingL1/L2/R1/R2`
  sweep meshes, the `EngineX1` helpers). Registered non-part frames (stations, `Camera`, `Pilon`, `EndWingL/R`,
  `height`) are not drawn either; the game hides every root child that is not in `parts`.
* `engines`: `left` / `right` nozzle centres (the plain `EngineL` / `EngineR` frame), `radius` = |ΔY| of the
  `EngineX` / `EngineX1` pair, `pairs` = complete pairs (clump+0x27c). No pair → no flame. A single-engine jet has
  only `left` (the original draws the unset right flame at 99999, i.e. nowhere).
* `gun` (StationGun, the muzzle-flash point), `stations` (StationA..I, Gun, Cha, Fla: store attach points),
  `end_wing` (EndWingL/R, consumer unknown), `height` (the `height` helper's Y: wheels below the origin; the flight
  model's gear clearance), `eye` (Pilon, else Camera).
* `type` / `types`: aircraft type codes from the object database (`default6_1.bdb`, object field `0x5b4`, via the
  Present record `0x53c` → model path); `type` = the most common. `fm_section`: the `bd.ibx` section that type loads
  (`FUN_005a5bb0`); `null` = the type keeps the F-16 data (230/240 transports) or is a helicopter (−1).
* `label`, `objects`: the database objects that use the model (name, class, label, type).
* optional `part_rules` (not written by the converter): per-part overrides `{ "<part>": {"sign": -1, "visible": false} }`
  for a future model whose helper order does not fit the type's rules.

## 2. The generic component (`game/aircraft/aircraft_model.gd`)

```gdscript
var m = preload("res://aircraft/aircraft_model.gd").create("f16", 100, on_ground_start)
rig.add_child(m)
m.update({"stick_x": sx, "stick_y": sy, "rudder": ru, "flaps": lever, "gear_down": g, "brakes": b,
          "hook": h, "chute": c, "on_ground": og, "gear": fm_gear_ramp, "afterburner": stage, "rpm": rpm}, delta)
```
It keeps the original's ramps (flaps / gear / speed brake / hook 0.5 rad/s, rudder / elevators / ailerons 0.7 rad/s;
limits 16.8°, 89.9°, 49°, 45°, 22.5°, 30°, 45°), retargets a configuration ramp only when its lever changes (the
original's events), starts from the original start state (airborne: gear up, flaps 0, speed brake 0; ground: gear
down, **full** flaps 0.29275 also on the F-16, speed brake open) and evaluates `part_pose(id)` = the callback. When
the flight model's gear ramp (`state().gear`) is passed it is used as is (exact timing). In the flight scene
(`terrain_view.gd`) the stick, rudder, levers come from the player and `gear`, `on_ground`, `afterburner`, `rpm`
from `IafFlight.state()`.

### 2.1 Callback rules per part (θ in rad; `g` gear ramp, `max` = 1.569)

| part (id) | θ | drawn | type-specific |
|---|---|---|---|
| AilerL (1) / AilerR (2) | aileron L / R | yes | 100 (F-16 flaperons): L − flaps, R + flaps |
| CanarL/R (3, 4) | — | no | |
| RuddeL (5), Rudde (6) | rudder | yes | |
| FlapL (7) / FlapR (8) | −flaps / +flaps | yes | |
| SpdbrU (9) / SpdbrD (10) | +sb / −sb | \|θ\| ≥ 1e-5 | 110, 140, 160, 190: signs flipped; 100: always drawn |
| ElevaL (11) / ElevaR (12) | elevator L / R | yes | 140 (Lavi): negated |
| ElevoL (13) / ElevoR (14) | aileron L / R | yes | |
| LdgL (15) | +g | g ≠ max | 110: −g; 180: −g, drawn g < 0.8889·max; 190: +g, drawn g < 0.7778·max |
| LdgR (16) | −g | g ≠ max | 110: +g; 180: +g, drawn g < 0.8889·max; 190: −g, drawn g < 0.7778·max |
| LdgF (17) | −g | g ≠ max | 110, 130, 140, 160: +g; 180: +min(g, 50°) |
| LdgDr (18) | 0 | g ≠ max | |
| Hook (19) | +hook | \|θ\| ≥ 1e-5 | |
| pilot, pilotB, canopy, canopyB (0x14–0x17) | 0 | **no** | see §2.3 |
| RotorA–D (0x1d–0x20) | 0 | no | helicopters (type −1) are not flown by the flight model: shown static (UNCERTAIN) |
| Parach (0x27) | ±5° jitter every 0.1 s | chute state 2 | the jitter object exists for 120, 130, 160, 180, 190, 200 |
| others (turret, radar, wheels, engines) | 0 | no | |

Control ramps: rudder = pedal·22.5° in the air, −stick roll·22.5° on the ground. Ailerons = −45°·stick roll, both
sides, in the air only and not on the deltas (130, 190). Pitch mixer (`FUN_0059da00`): `A` = 45° (130, 190) else
30°; `f` = 0.5 (110, 130, 190), 0.65 (100), else 1; `m = (1−f)·sr·A` for 100, 110, 130, 190 else 0;
`L = sp·f·A − m`, `R = −sp·f·A − m`, ×0.6 for the F-4 (120, 200); deltas write L/R to the elevons (aileron ramps),
the others to the elevators. Flaps target = lever·16.8° (·0.33 on the F-16).

### 2.2 Afterburner flame (`FUN_0041e1f0` → `FUN_004121b0`)
* Level per nozzle (`FUN_005a8d40` left / `FUN_005a8e70` right, render bytes +0x3d / +0x3c):
  `stage > 0` (the flight model's AB stage, `vehicle+0x568`+0x28, set in the 1 Hz aero update) and that side's
  "After burner damage" flag (8 left / 9 right) clear → `75 + 12.5·stage` (87 / 100); otherwise RPM ramp·0.74 ≤ 74.
  **Nothing is drawn at level ≤ 74**, so the flame appears exactly at the AB stages (throttle ≥ 0.75 once the
  light-up delay has passed, flight-model.md §15.8) and both nozzles always show the same level.
* `k = (level − 75)·0.04` (0.5 at stage 1, 1.0 at stage 2); `j = (rand % 21 − 10)·0.01` per nozzle per frame.
* Cones of 12 segments from the nozzle ring (radius `r`) toward the tail to a ring of radius `r·(j + 0.25)` at
  `length = (3.5 + j)·k + 1.5·i / 5` metres. The 3D-card path (`DAT_007ccf90`) draws two: i = 2 with radius 0.7·r
  and i = 3 with radius r; the software path only i = 3. We draw the 3D-card path.
* Texture `afterburn.tga`: u = random offset − s/12 per segment (a fresh offset per cone per frame), v = 1 at the
  nozzle (opaque end) and 0 at the tip. Double-sided, no depth write. Blend: additive glow in our port (the
  original's texture blend state is not decoded, UNCERTAIN).
* F-16 at full AB: ≈ 4.4 m flame (3.5 + 0.9), base radius 0.44 m.

### 2.3 Deviations / open points
* **Canopy and pilot are hidden on flown aircraft** (callback ids 0x14–0x17 → not drawn; the ejection object
  `0x53d180` draws them only after an ejection). The F-16 then shows the flat cockpit cover of the airframe mesh.
  `aircraft_model.gd` `crew_visible = true` shows them (decision pending with the user).
* Hook and drag chute have no key in our game yet (the component supports them).
* No damage model: the AB damage flags are never set.
* Flicker: the flame's random numbers change every rendered frame, as in the original (so faster at high fps).
* The flaps / speed-brake ramps are recomputed in GDScript with the original rule; the flight model's own ramps
  (`S+0x300`, `S+0x340`) are private in `iaf-flight` (the gear ramp is exported).
* Muzzle flash (`FUN_00411d60` at StationGun) and stores on stations: need weapons (not implemented).

## 3. Per-aircraft table (the shipped install)

| folder | type(s) | FM section | parts | nozzles (radius) | stations | gun | height (m) |
|---|---|---|---|---|---|---|---|
| f16 | 100 | F-16 | AilerL/R (flaperons), ElevaL/R, RuddeL, SpdbrU/D, LdgL/R/F, LdgDr, Hook, Canopy, pilot, pilotB, EngineL | 1 (0.44) | A–I, Gun, Fla | yes | −1.69 |
| f15 | 110 | F-15 | AilerL/R, FlapL/R, ElevaL/R, Rudde, RuddeL, SpdbrU, LdgL/R/F, LdgDr, Hook, canopy, pilot, EngineL/R | 2 (0.39) | A–I, Gun, Cha, Fla | yes | −2.28 |
| f42000 | 120 / 200 | F-4 | AilerL/R, FlapL/R, ElevaL/R, RuddeL, SpdbrU/D, LdgL/R/F, LdgDr, Hook, Parach, canopy, canopyB, pilot, pilotB, EngineL/R | 2 (0.40) | A–I, Gun, Cha, Fla | yes | −2.74 |
| cfir | 130 | KFIR | AilerL/R (elevons), FlapL/R, Rudde, SpdbrU, LdgL/R/F, LdgDr, Parach, canopy, pilot, EngineL | 1 (0.45) | B–H, Gun, Cha, Fla | yes | −1.37 |
| lavi | 140 | LAVI | AilerL/R, FlapL/R, ElevaL/R (canards, negated), Rudde, SpdbrU/D, LdgL/R/F, LdgDr, Hook, canopy, pilot, pilotB, EngineL | 1 (0.46) | A–I, Gun, Cha, Fla | yes | −1.45 |
| mirage | 190 | MIRAGE | AilerL/R (elevons), FlapL/R, Rudde, SpdbrU, LdgL/R/F, LdgDr, Parach, canopy, pilot, EngineL | 1 (0.35) | C–G, Gun, Cha, Fla | yes | −1.58 |
| mig23 | 160 | MIG23 | AilerL/R, FlapL/R, ElevaL/R, Rudde, SpdbrU/D, LdgL/R/F, LdgDr, Parach, canopy, pilot, EngineL (WingL1/L2/R1/R2 dropped: no wing sweep) | 1 (0.44) | C–G, Gun, Cha, Fla | yes | −1.83 |
| mig29 | 180 | MIG29 | AilerL/R, FlapL/R, ElevaL/R, Rudde, RuddeL, SpdbrU, LdgL/R/F, LdgDr, Parach, canopy, pilot, EngineL/R | 2 (0.27) | A–I, Gun, Cha, Fla | yes | −1.61 |
| mig21 | 150 | MIG21 | LdGr (= LdgR, no hinge: shown / hidden), EngineL | 1 (0.40) | — | — | −1.70 |
| mig25 | 170 | MIG25 | LdGr, EngineL/R | 2 (0.60) | — | — | −3.26 |
| mig17 | 210 | MIG17 | LdGr | — | — | — | −1.61 |
| su22 | 220 | TU22 | LdGr, EngineL | 1 (0.46) | — | — | −1.65 |
| su24 | 220 | TU22 | LdGr, EngineL/R | 2 (0.42) | — | — | −2.26 |
| tu22 | 220 | TU22 | LdgR, EngineL/R | 2 (0.66) | — | — | −2.04 |
| a4 | 220 | TU22 | LdGr | — | — | — | −1.91 |
| c130 | 230 / 240 | — (F-16 data) | LdGr, RotorA–D (hidden by the flight-model callback) | — | — | — | −2.60 |
| boing (707), il76 | 230 / 240 | — | LdGr | — | — | — | −3.08 / −4.83 |
| ch53, mi8, mi24, uh60a | −1 (helicopter) | — | RotorA/B (static) | — | — | — | — |

The controllable jets are the eight in `controllableplanes`; `bd.ibx` also has `[MIG25] [MIG17] [MIG21] [TU22]
[C130] [SU24]` for the AI planes. Contact sheet of every model (gear / flaps / speed brakes / AB): run
`godot --path game -s tools/aircraft_sheet.gd -- <out-dir>` (needs a window).

## 4. Adding a new aircraft

1. **Model.** Provide `<name>_h.xfr` (DirectX frame file, `x3ds_` frame names) in
   `resource/3dobjects/controllableplanes/<name>/` (or `noncontrollableplanes`) with its textures. Put each moving
   part in its own direct child frame of the root, named from the table (§2.1: `AilerL`, `ElevaR`, `LdgF`, …), with
   the frame origin on the hinge and two tiny helper frames `<part>1` / `<part>2` on the hinge line (the axis points
   from the one nearer the model origin to the farther one; swap them to reverse the sense). Add `EngineL` +
   `EngineL1` (and `EngineR` + `EngineR1`) whose Y difference is the nozzle radius, `height` at wheel level,
   `Camera`, `StationA..I` / `StationGun` as needed. Anything else is dropped.
2. **Convert.** `iaf-convert --upscale --smooth aircraft <install> assets/converted/missions assets/converted/planes`
   writes the glTF and `aircraft.json`. Check the part list, `axis` values and nozzles in the JSON.
3. **Type code.** A new aircraft needs an object in the object database with a type code (`0x5b4`); without one
   the descriptor says `type: -1`. Pass the type to `create(plane, type)`. A new code gets the default rules of
   §2.1; if a part moves the wrong way, add a `part_rules` override (sign / visible) to the descriptor — or, for a
   genuinely new behaviour, a case in `part_pose()` (and a line in the table above).
4. **Look at it.** `godot --path game -s tools/aircraft_sheet.gd -- /tmp/sheet <name>`; fix hinge helpers or
   overrides until gear, flaps, speed brakes and the flame are right. `tests/godot/test_aircraft_parts.gd` loads
   every descriptor.
5. **Flight model data set.** Flying it needs a `bd.ibx` section (parameters, docs/flight-model.md §1) and its
   envelope `<n>.dat` (§3), selected by the type (`FUN_005a5bb0`, `fm_section` in the descriptor); a corrected
   real-world set is added the same way as the F-16's (docs/flight-model.md §11, `crates/iaf-flight/src/data_set.rs`).
6. **Cockpit** (flyable jets): a `resource/cockpits/<c>` folder converted with `iaf-convert cockpit` (docs/cockpit.md).
