# How an aircraft is defined

This doc says how iaf-reborn builds an aircraft: the data it reads, how the moving parts and the afterburner flame
are ported, and how to add or fly a type. It is for developers who add or maintain aircraft. The exe's part system
(ramps, the part callback, the flame) is specified in [part-animation.md](part-animation.md).

Addresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](v1.1.md) maps them to v1.0.

**Terms**
- **FM**: flight model ([flight-model.md](flight-model.md)). **AB**: afterburner. **AI**: the computer-flown aircraft.
- **Type code**: the number the original uses for an aircraft type (for example 100 = F-16), keyed in many tables.
- **Descriptor**: the per-model `aircraft.json` the converter writes (§1).
- **Ramp**: a value that moves toward its target at a fixed rate (flight-model.md §0).
- **RPM**: engine speed, in % of maximum.

An aircraft is **data from the original install + one generic piece of code**:

| what | where | produced by |
|---|---|---|
| 3D model with moving parts (`<p>_h.xfr` → glTF) | `assets/converted/planes/<p>/<p>_h.gltf` | `iaf-convert aircraft` |
| descriptor: parts, hinges, nozzles, stations, type codes | `assets/converted/planes/<p>/aircraft.json` | `iaf-convert aircraft` (`crates/iaf-tools/src/aircraft.rs`) |
| index of all aircraft | `assets/converted/planes/aircraft.json` | same |
| afterburner texture (`afterburn.tga`) | `assets/converted/planes/afterburn.png` | same |
| per-type part rules (the original callback `FUN_005a09c0`) | `game/aircraft/aircraft_model.gd` `part_pose()` | code (a port) |
| afterburner flame (`FUN_004121e0`) | `game/aircraft/afterburner.gd` | code (a port) |
| flight model data | `resource/md/bd.ibx` `[<SECTION>]` + `<n>.dat` envelope | `crates/iaf-flight` (docs/flight-model.md) |
| cockpit | `resource/cockpits/<c>` | `iaf-convert cockpit` (docs/cockpit.md) |

Descriptor coordinates are **glTF** (the X file with Z mirrored: +X right, +Y up, −Z nose), in metres (the unscaled
X-file units; the original scales every clump by 5, `error.c` "Scale= 5.000").

## 1. The descriptor (`aircraft.json`, format 1)

The converter replays what the original loader does with the frame file (`FUN_0041c880` → `FUN_0041c270`,
`FUN_0041c680`, `FUN_0041c7f0`, `FUN_0053da00`):

* `root`: the root frame (its own mesh is the airframe, always drawn).
* `parts`: every direct child of the root whose name is in the original name table (case-insensitive: the AI planes'
  `LdGr` **is** `LdgR`) with a Subpart id (1..0x27, EngineL 0x3a, EngineR 0x3b): `{id, pivot, axis}`.
  `pivot` = the frame origin; `axis` = unit vector from the hinge helper (`<name>1` / `<name>2`) nearer the model
  origin toward the farther one; `null` when `<name>1` is missing (the part stays at rest). The part turns about its
  pivot by **+θ** about `axis` (glTF space).
* `dropped`: children that match no table name (e.g. the MiG-23 `WingL1/L2/R1/R2` sweep meshes, the `EngineX1`
  helpers). The original never draws them, nor the registered helper frames (stations, `Camera`, `Pilon`,
  `EndWingL/R`, `height`). The game draws the root and the `parts` frames and hides every other root child.
* `engines`: `left` / `right` nozzle centres (the plain `EngineL` / `EngineR` frame), `radius` = |ΔY| of the
  `EngineX` / `EngineX1` pair, `pairs` = complete pairs (clump+0x27c). A flame needs a complete pair. A single-engine
  jet has only `left` (the original draws the unset right flame at 99999, out of sight).
* `gun` (StationGun, the muzzle-flash point), `stations` (StationA..I, Gun, Cha, Fla: store attach points),
  `end_wing` (EndWingL/R, consumer unknown), `height` (the `height` helper's Y: wheels below the origin; the flight
  model's gear clearance), `eye` (Pilon, else Camera).
* `type` / `types`: type codes from the object database (`default6_1.bdb`, object field `0x5b4`, via the Present
  record `0x53c` → model path); `type` = the most common. `fm_section`: the `bd.ibx` section that type loads
  (`FUN_005a8980`); `null` = the type keeps the F-16 data (230/240 transports) or is a helicopter (−1).
* `label`, `objects`: the database objects that use the model (name, class, label, type).
* optional `part_rules` (hand-written; the converter leaves it out): per-part overrides
  `{ "<part>": {"sign": -1, "visible": false} }` for a model whose helper order conflicts with the type's rules.

## 2. The generic component (`game/aircraft/aircraft_model.gd`)

```gdscript
var m = preload("res://aircraft/aircraft_model.gd").create("f16", 100, on_ground_start)
rig.add_child(m)
m.update({"stick_x": sx, "stick_y": sy, "rudder": ru, "flaps": lever, "gear_down": g, "brakes": b,
          "hook": h, "chute": c, "on_ground": og, "gear": fm_gear_ramp, "afterburner": stage, "rpm": rpm}, delta)
```
The component:
- keeps the original's ramps, limits and start state (part-animation.md §2 "Ramp sampling");
- retargets a configuration ramp only when its lever changes (the original's events);
- evaluates `part_pose(id)` = the callback;
- uses the flight model's gear ramp (`state().gear`) as is when it is passed (exact timing).

In the flight scene (`terrain_view.gd`) the stick, rudder and levers come from the player, and `gear`, `on_ground`,
`afterburner`, `rpm` from `IafFlight.state()`.

### 2.1 Callback rules per part

`part_pose()` ports the callback table and the pitch mixer `FUN_005a0650` of part-animation.md §2 (per-type signs,
the F-16 flaperons, the deltas' elevons, the gear-leg visibility). Additions of ours: part 0x94 `LdgDrUp` (shut gear
doors, detailed models and the F-35I), 0x90–0x93 `BayLi..BayRo` (the F-35I's weapon bay doors) and the Rolling
wheels' `WheelsA..F` (part-animation.md §2.2). RotorA–D (0x1d–0x20): helicopters (type −1) are not flown by the
flight model, so they are shown static (UNCERTAIN).

### 2.2 Afterburner flame (`FUN_0041e220` → `FUN_004121e0`)

`afterburner.gd` ports the flame of part-animation.md §3 "EngineL/R": the level `75 + 12.5·stage` (87 / 100), drawn
only above 74, so it shows exactly at the AB stages (throttle ≥ 0.75 once the light-up delay has passed,
flight-model.md §15.8) and both nozzles show the same level. Port choices:
* We draw the 3D-card path (`DAT_007d1960`): two cones, i = 2 at 0.7·r and i = 3 at r.
* A fresh texture offset per cone per frame; double-sided, without depth write. Blend: additive glow (the original's
  blend state is undecoded, UNCERTAIN).
* F-16 at full AB: ≈ 4.4 m flame (3.5 + 0.9), base radius 0.44 m.

### 2.3 Port notes
* **Canopy and pilot** (ids 0x14–0x17): drawn by the crew object's callback `0x53eb50` whenever the crew is aboard
  and the cockpit flag `crew+8` is clear (v1.1: 0 from the ctor, set only while the own jet is drawn from the
  cockpit), on every jet, the player's included (part-animation.md "Ejection"). Ours: `crew_visible = true` on every
  aircraft; the ejection takes pilot / seat / canopy off the jet.
* **Hook:** no key lowers it, as in the original (flight-model.md §15.11 item 7); the component supports it. The drag
  chute is Shift+B (`terrain_view.gd` `_chute_key`, controls.md).
* **AB damage:** the player's flags 8 / 9 (`player_damage.gd`, damage.md §5) reach the model as `ab_damage` and put
  that flame out; systems damage applies to the player's jet only.
* **Flicker:** the flame's random numbers change every rendered frame, as in the original (faster at high fps).
* **Ramps:** the flaps / speed-brake ramps are recomputed in GDScript with the original rule; the flight model's own
  ramps (`S+0x300`, `S+0x340`) are private in `iaf-flight` (the gear ramp is exported).
* **Muzzle flash** (`FUN_00411d90`, at StationGun) and the stores on the stations: `player_weapons.gd` / `stores.gd`
  (docs/weapons.md).

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
[C130] [SU24]` for the AI planes. Contact sheet of every model (gear / flaps / speed brakes / AB), a real render:
`tools/godot_window.sh -- --log-file <log> --path game -s tools/aircraft_sheet.gd -- <out-dir> [plane…]`.

## 4. Adding a new aircraft

This section is for a model in the original format (an `.xfr` in the install). A plane the original never had (a
hand-made glTF, its own flight data, cockpit and Jet list slot) is [adding-a-plane.md](adding-a-plane.md), with the
F-35I as the worked example.

1. **Model.** Provide `<name>_h.xfr` (DirectX frame file, `x3ds_` frame names) in
   `resource/3dobjects/controllableplanes/<name>/` (or `noncontrollableplanes`) with its textures. Put each moving
   part in its own direct child frame of the root, named from the table (`AilerL`, `ElevaR`, `LdgF`, …; the node
   names of adding-a-plane.md §2.2), with the frame origin on the hinge and two tiny helper frames `<part>1` /
   `<part>2` on the hinge line (swap them to reverse the sense, §1). Add `EngineL` + `EngineL1` (and `EngineR` +
   `EngineR1`) whose Y difference is the nozzle radius, `height` at wheel level, `Camera`, `StationA..I` /
   `StationGun` as needed. Anything else is dropped.
2. **Convert.** `iaf-convert --upscale --smooth aircraft <install> assets/converted/missions assets/converted/planes`
   writes the glTF and `aircraft.json`. Check the part list, `axis` values and nozzles in the JSON.
3. **Type code.** The aircraft needs an object in the object database with a type code (`0x5b4`); without one the
   descriptor says `type: -1`. Pass the type to `create(plane, type)`. A new code gets the default rules of §2.1; if
   a part moves the wrong way, add a `part_rules` override (sign / visible) to the descriptor, or, for a new
   behaviour, a case in `part_pose()`.
4. **Look at it** with the contact sheet (§3, `<out-dir> <name>`); fix hinge helpers or overrides until gear, flaps,
   speed brakes and the flame are right. `tests/godot/test_aircraft_parts.gd` loads every descriptor.
5. **Flight model data set.** Flying it needs a section (parameters, docs/flight-model.md §1) and its envelope
   `<n>.dat` (§3), selected by the type (`FUN_005a8980`, `fm_section` in the descriptor). A v1.1 install reads
   `bdgen.dat`, not `bd.ibx`, so define the type in code: a `TYPES` + `Real` row in `data_set.rs` and a reference row
   in `crates/iaf-flight/tests/validation.rs` (adding-a-plane.md §3, the data in docs/real-aircraft.md).
6. **Cockpit** (flyable jets): a `resource/cockpits/<c>` folder converted with `iaf-convert cockpit` (docs/cockpit.md).

## 5. Making a type flyable

The flight scene flies any type through `game/aircraft/player_aircraft.gd`: `profile(type)` gives the plane folder
(the descriptor whose `types` list holds the type: `f42000` serves F-4E 120 and F-4 2000 200), the flight-model
section (descriptor `fm_section`), the cockpit (`COCKPIT`, the exe's type → `cockpits.ibx` index table
`FUN_00447e70`, then `Cockpit00k = <dir>`) and the twin-engine flag (`TWIN`, logic+0x24). The Jet list's aircraft id
picks the type (`JET_TYPES`); with no Jet list choice the mission's jet flies. Every type outside `FLYABLE` flies as
the F-16.

To add one:
1. Put its type in `FLYABLE`.
2. Check that its cockpit draws. Each cockpit uses its own gauge sections: `cockpit.gd` draws SPEED / ALTITUDE / RPM /
   THROTTLE / TEMP clocks and their SECONDARY twins, FUELDIGITAL or FUELCLOCK, PANELVARIO or VARIOCLOCK, PANELAOA.
3. Extend `tests/godot/test_player_aircraft.gd` (profile, cockpit, model, weapons, Real data, gear / flaps / speed
   brake / afterburner / chute / ejection).

Its Real rows are per type too: `crates/iaf-flight/src/data_set.rs` (flight data, incl. `ceiling_ft` and `chute`) and
`game/weapons/real_weapons.gd` (`RADAR_KM`, `GUN_ROUNDS`). Ejection throws one seat per crew part of the model
(`pilot`, `pilotB`).

Flyable today: the Jet list's seven (F-15 110, F-16 100, F-4E 120, F-4 2000 200, Lavi 140, Kfir 130, Mirage 190)
and the F-35I (1000) from Extras (docs/f35i.md). `tests/godot/test_jet_list.gd` flies each (roll-out, gear, flaps,
speed brake, afterburner, ejection; the F-16 and the Kurnass 2000 have their own tests). The MiG-23 (160) and MiG-29
(180) fly with their cockpits when a mission makes them the player's jet (the Mission Creator, docs/front-end.md
§19; `tests/godot/test_mission_creator.gd` starts in a MiG-29).

With Flight data = Original the Kfir and the Mirage share one parameter block per game session, as in the
original (`iaf_flight::data_set::Blocks`, docs/flight-model.md §1).
