# AI aircraft: brain, control loops, formations, take-off and landing

This document describes how the original game's computer-controlled (AI) units decide, fly and fight, decoded from
the exe, and where our port of each part lives.

- **Addresses** are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](v1.1.md) maps them to v1.0.
- **Source:** the decompile `assets/ghidra_v11/iafjets.c`. Argument orders were checked in the disassembly.
- **`UNCERTAIN`** marks what the code did not settle.
- **Related docs:** [mission-runtime.md](mission-runtime.md) (control modes, scripts), [flight-model.md](flight-model.md)
  (the FM's "ai" cases, §14/§15), [weapons.md](weapons.md) (AI fire cones), [formats/mis.md](formats/mis.md) (bdb).

## Terms

| term | meaning |
|---|---|
| AA / AG | air-to-air / air-to-ground |
| AAA | anti-aircraft artillery (guns) |
| AB | afterburner |
| AGL | height above ground level |
| ATC | air traffic control (the tower's calls to the player) |
| AWACS | the airborne early-warning aircraft whose radio calls report contacts |
| B, brain | the unit's MBrain object (§1); `B+0x70` is a field of it |
| bdb | the mission database file (`*.bdb`); it holds the brains (rule lists), objects and weapons |
| CL | control loop: one autopilot behaviour, such as "fly to a waypoint" (§8) |
| CTL, ctl | the controller: the object that turns inputs into the jet's controls; only the player has one |
| DLZ | dynamic launch zone: the range band in which a missile can reach its target |
| ECM | electronic countermeasures (radar jamming) |
| ETA | the planned arrival time at a waypoint |
| FM | flight model |
| IR | infrared |
| GEV | the event code a control loop posts to the controller (`44a240`) |
| LOS | line of sight |
| NAV | the navigate mode: fly the route's waypoints |
| P | the unit's own position |
| RPM | engine revolutions (%) |
| RWR | radar warning receiver |
| SAM | surface-to-air missile |
| STT | single-target track (a radar lock) |
| T | the brain's current target (`B+0x70`) |
| W | the unit's weapon handler |

## How the original AI thinks (summary)

- **Two layers.** A *brain* decides what to do. An *autopilot* ("control loops") flies the jet through the same
  flight model as the player: it moves the stick, throttle, gear, flaps and brakes. This flight model is the AI
  jet's only physics.
- **The brain is a rule list from the mission database** (bdb Brains, 67 of them, e.g. "AA leader", "AA wing
  command").
  - Every 2 s it walks its rules from top to bottom. Enemy jets think slower: ×1.5 at Normal, ×2 at Rookie.
  - A rule is an AND of conditions (`speed < 200 kt`, `current waypoint is a take-off`, `target closer than 9 km`,
    `leader dead`, `wingman command = close formation`…) plus a list of actions.
  - Per action *type*, the first rule that fires wins that tick. A rule marked "stop" ends the walk.
  - A rule can switch to a *sub-brain* (e.g. "attack air target" under 9 km) and back.
- **Actions:**
  - manoeuvres: navigate the route, take off, go home and land, close / tactical formation, hold, straight,
    Immelmann, split-S, dog chase, run away, break, bomb runs…;
  - weapon choice and launch, flares / chaff, target selection;
  - radio replies, combat on / off.

  A manoeuvre that is already running keeps running; the brain does not restart it.
- **States / modes** are the autopilot's modes:

  | mode | behaviour |
  |---|---|
  | 7 | navigate the waypoints |
  | 9 | take-off sequence: taxi from the hangar, roll, climb to the first waypoint |
  | 8 | go home: fly to the last waypoint, a fixed left-hand pattern, 6° glide path, roll-out, taxi to a free hangar, engine off |
  | 1 / 3 | close / tactical formation on the leader |
  | 10 | hold |
  | 0x11 | dog chase |
  | others | the combat manoeuvres |

- **What it reacts to:** its own speed / altitude / fuel ("bingo"); the current waypoint's type; its target's range,
  altitude and heading; whether the target is the player or destroyed; a missile launched at it; its leader being
  dead / on the ground; the player's wingman commands; a random number. It ignores terrain ahead (the autopilot
  has its own ground rules), threats other than its lock / missile warning, and the mission's scripts.
- **Skill** (Preferences AI level):
  - Rookie / Normal enemies think 2× / 1.5× slower.
  - The fire cone is narrower for a Rookie (×0.5) and wider for an Expert (×1.5).
  - A Rookie enemy pulls softer above 4.3 g.
  - An Expert enemy cannot stall.
  - The damage scaling makes Rookie enemies *tougher*: a known original bug (docs/damage.md).
- **Known weaknesses / exploits (original):**
  - It thinks only every 2–4 s.
  - Routes are timed (each waypoint has an arrival time) and flown at 180–300 m/s whatever the fuel.
  - There is no go-around, and a landed AI never takes off again.
  - The take-off is flown without afterburner.
  - A "go back" rule fired in the base brain makes the brain loop 10 times and switch itself off (e.g. "popup",
    "divebomb" once the target is dead).
  - Crash immunity: an AI jet with fuel and < 10 % damage cannot crash on the ground or water after 3.5 s of
    autopilot, and never during take-off.
  - When a leader dies, the wingman is not promoted; it only inherits the leader's waypoint.

## 1. Objects

The AI uses these runtime objects:

| object | where | notes |
|---|---|---|
| MBrain (0xe8 bytes) | entity+0x2c, ctor `FUN_0043eda0` | every entity built by `FUN_0059bb00` has one |
| autopilot / control-loop manager | vehicle+0xc50 (`FUN_005c6be0`, vtable 0x611e54) | `FUN_005c89f0` returns its mode (+0x24): the FM's "ai" test |
| formation manager | `DAT_00699340` (frmtnMngrPtr), hash map by formation **id** (0x1e) | built by `FUN_004b3573` → `FUN_004b3604` |
| TowersManager | `DAT_00699344`, ctor `54eb30` | airbase data (§8), player ATC |
| FlightController | `DAT_00699348` (0x3a0 bytes, ctor `FUN_0054acc0`) | the radio reports and AWACS calls only (§10) |

MBrain fields (b = brain):

| offset | field |
|---|---|
| +0 | owner |
| +4 | active rule list (base or sub-brain) |
| +8 | base list |
| +0x0c..+0x2c | "action type already run this tick", 9 ints (types 0..8) |
| +0x30 | scheduler event (vtbl 0x6007b0) |
| +0x38 | period (f64) |
| +0x40 | target selector |
| **+0x44** | **leader** (partner) |
| **+0x48** | **wingman command** |
| +0x4c / +0x58 | flare busy / expiry |
| +0x50 / +0x60 | chaff busy / expiry |
| **+0x68** | **engaged** |
| **+0x6c** | **combat disabled** |
| +0x70 | current target |
| +0x74 | primary target (`FUN_005bccb0`, the formation member's target 0x424) |
| +0x78 | period code |
| +0x7c | attacker (UNCERTAIN) |
| +0x80 | last hitter (cleared 5 s later; no reader, docs/damage.md §4.2) |
| **+0x88** | **current waypoint index** |
| +0xd8 | in a sub-brain |
| +0xdc | list switched |
| **+0xe0** | **landed** (the controller's landed flag) |

## 2. Loading (bdb → runtime)

The loader turns a bdb brain into rule nodes. Fields marked editor-only are used only by the Mission Creator.

- A brain item uses **one** list: `rules = item.0x208 ? rules0 : rules1` (`FUN_00595060`).
- Rule node (0x14 bytes, `FUN_004bbd50`): key (file order), next, condition tree, **stop flag = 0x1ae**, actions.
  0x190 / 0x19a / 0x1a4 are editor-only.
- Conditions:
  - `list16 = [a, code, op, value]` → `{code, op, value}` (`FUN_00594c50`). **`a` is editor-only**, so the runtime has
    only AND (no OR / NOT).
  - All conditions of a rule form a left-deep **AND** (`FUN_004b3e8f`, eval `FUN_004bbf40`, short-circuit).
  - A rule never fires when it has no condition, an unknown code (> 39) or an unknown op (∉ 0..5) (e.g. brain 3
    "popup" rule 0, op −1).
  - The constant is `ftol(value)`, except for codes 9, 13 and 24 (float).
- Actions:
  - `list20 = [flags, edType, id, f4, f5]` → `(id, f4 = audio id, f5 = delay s)` (`FUN_004b6088`, `FUN_00594ca0`).
    **flags and edType are editor-only.**
  - id −1 is skipped. id 1000 = sub-brain `f4` (audio forced 0).
  - Any other id: the bdb action's **code 0xbe** picks the runtime class. The class copies 0xc8, 0x82, 0x96, 0x8c;
    it ignores 0x78, 0xa0 and 0xb4. Each class has a fixed type 0..8.

## 3. Creation, scheduling, tick

A brain is attached at spawn, reset at activation and then ticked on a fixed period.

- **Spawn** (`FUN_004b815f`): the brain with id 0x2da is looked up in the map and its rules are attached
  (`FUN_00440790`: +4 = +8). Brain −1 means no brain, never scheduled (the loader copies 0x2da to the spawn
  descriptor as is, `FUN_0058f110` @58f1e6; §14).
- **Activation** (`FUN_004a9100`):
  - BRAIN control (0x320 bit 0 = 0): the FM mover is installed, the FM type loaded (`FUN_005a8980`), the start pose
    set (`FUN_005a5820`, §7), then **reset**.
  - MISSION control (bit 0 = 1): the scenario starts and the brain is reset too, but every non-FM mover's `setMode`
    is empty (`FUN_0046a430`). So **a mission-controlled unit's brain runs, but its manoeuvres do nothing**;
    targeting, weapons, voice and sub-brains still work.
  - Only a unit that gets a brain gets a mover. An unarmed ground unit gets no brain, so a BRAIN-controlled unarmed
    vehicle (116's, 324's) just stands (UNCERTAIN, from the research of `FUN_004a9100`'s callers).
  - The control mode picks the mover, whatever the class: the transports (class 3: C-130, IL-76) fly too
    (`ai_flights.gd`).
- **Reset `FUN_0043eef0`:**
  - clears the tick flags, +0x48..+0x50, +0x58..+0x64, +0x68, +0x70, +0x7c..+0x84 (it keeps +0x6c and +0x88);
  - +0x78 = 480;
  - leader +0x44 = `getWingman(e)` (`FUN_005bcb90`), else the formation leader unless that is e;
  - +0x74 = the member target; the target selector per class; +0x38 = period;
  - if the brain is not yet scheduled, schedules the tick **now** and then every period.
- **Period** `FUN_004404d0(code)`:
  - codes 450, 460 … 540 → 1 … 10 s; default 480 = 4 s; ground / SAM / boats 500 = 6 s;
  - **controlled aircraft (class 0x1c) 0x1cc = 2 s**;
  - single player, enemies of the player only: ×2 Rookie, ×1.5 Normal (0x6007a0), ×1 Expert.
- **Tick** (`FUN_00442120`, event slot 1):
```
expire flare / chaff busy flags
for rule n in list +4 (file order):
  if n.cond(entity):
     for action a in n.actions:
        if gate(a.type): a.exec(entity)          // type T runs if b+0xc[T]==0, then marks it
        if a.audio ∉ {0,−1}: play now, or ActionTimer at now + a.delay (always, even when gated)
     if b+0xdc (list switched): b+0xdc=0; clear flags; restart at the new list's head; after 10 restarts:
        "Brain is in loop forever" (brnloop.log), transferControl(), stop
     elif n.stop (0x1ae) == 0: stop
clear flags
```
  Types 5 and 6 are never marked. The sub-brain action is never gated. 390 skips the gate. **Original bug:** a "go
  back" (1000, −1) fired in the base brain still sets +0xdc: after 10 restarts transferControl runs and the brain
  stops.

## 4. Conditions (`FUN_004b3fa9`; measure vtbl +0x20)

Each condition compares one measure with a constant. T = current target (+0x70).

Operators (`FUN_004b5e6a`): 0 `==` (bool measures compare as bools, floats exactly), 1 `>`, 2 `<`, 3 `>=`, 4 `<=`,
5 `!=`. Operators 1–5 are false when the measure is invalid.

| code | fn | measure |
|---|---|---|
| 0 | 5c14d0 | always 1 |
| 1 | 5c0490 | T is an aircraft (class 2, 3, 0x1c) |
| 2 | 5c04d0 | T == primary target |
| 3 | 5c0530 | +0x78 |
| 4 | 5c0550 | own altitude z (m) |
| 5 | 5c05f0 | own heading, deg (−180, 180] |
| 6 | 5c07b0 | **own speed, kt** (m/s × 1.9427955, 0x612690) |
| 7 | 5c0800 | own load factor (g) |
| 8 | 5c0850 | no external tanks attached (§13.2) |
| 9 | 5c0890 | T altitude (m) |
| 10 | 5c0940 | relative bearing to T, deg (§13.2) |
| 11 | 5c0980 | T heading, deg |
| 12 | 5c0b60 | T speed, kt |
| 13 | 5c0bc0 | 3-D range to T (m); invalid if T destroyed |
| 14 | 5c0d30 | closure on T, m/s (`FUN_0044ea60`, §13.2) |
| 15 | 5c0d60 | random 0..100 |
| 16 | 5c0db0 | own z − T z |
| 17 | 5c0ee0 | T load factor |
| 18 | 5c0f40 | own z < T z |
| 19 | 5c14e0 | I am locked (§13.2) |
| 20 | 5c1740 | T within the current weapon's range (§13.2) |
| 21 | 5c1a30 | the selected store's round count (§13.2) |
| 22 | 5c1080 | **leader destroyed**; invalid without a leader |
| 23 | 5c1aa0 | **leader on the ground** (z − terrain − model height < 3) |
| 24 | 5c10c0 | range to the primary target (m) |
| 25 | 5c1210 | primary target destroyed |
| 26 | 5c1530 | T attacking or locked (§13.2) |
| 27 | 5c15a0 | leader locked (§13.2) |
| 28 | 5c15f0 | T's target == my leader |
| 29 | 5c1250 | **wingman command** +0x48 (1 ProtectMe, 2 BugOut, 3 EngageDesignated, 4 EngageAny, 5 Tactical, 6 Close) |
| 30 | 5c1270 | **action of the current waypoint** `route[+0x88].action` (0 without a formation) |
| 31 | 5c12e0 | T engaged |
| 32 | 5c1320 | T destroyed |
| 33 | 5c1360 | current waypoint index |
| 34 | 5c1380 | T is the player |
| 35 | 5c1a60 → 453540 | **fuel ratio**: 100 without a route; `r = endurance / (3-D distance to the last waypoint / 220)`; ≤ 1.1 latches 1.0; returns r × 10 (bingo rule `35 <= 11`) |
| 36 | 5c13e0 | own damage % |
| 37 | 5c16a0 | leader's target == my target (§13.2) |
| 38 | 5c1410 | T == my threat (§13.2) |
| 39 | 5c1490 | a missile is launched at me (§13.2) |

§13.2 details the combat measures.

## 5. Actions

Manoeuvres (type 0) call `mover.setMode(mode, arg, pose)`. The FM's `setMode` (`5a8410`, FM vtbl 0x611dc8 slot 11)
returns at once when mode / arg / pose are unchanged (`5c8a70`), so **a running manoeuvre keeps running.** The port
compares the mode and the argument (the target, the leader or the unit itself, by its unit id;
`Autopilot::set_mode_arg`, called by `ai_flights.gd` `Pilot.set_mode`): the same mode with a new argument starts the
loop again (`Autopilot::start_mode`, its 0.5 s hold). The port passes no
pose to the manoeuvres, so there is none to compare.

| code | name | mode | arg | control loop (manager offset) |
|---|---|---|---|---|
| 100 | Straight | 0xb | self | FlyStraightCL (+0x4350) |
| 110 | Shandel | 0xd | T | ShandelCL |
| 120 | Himmelman | 0xe | T | Himmelman |
| 130 | Split S | 0xf | T | SplitSCL |
| 140 | Dog chase | 0x11 | T | Dogchase |
| 150 | Horizontal | 0x10 | T | HorizontalCL |
| 160 | Run away | 0x12 | T | RunAwayCL |
| 170 | 90° | 0x13 | T | Break90DegreesCL |
| 180 | Tail clear | 0x14 | T | TailClearCL |
| 190 | Close formation | 1 | leader | CloseFormationCL (+0x60d8) |
| 200 | Tactical formation | 3 | leader | TacticalFormationCL (+0x62c0) |
| 210 | Pop up | 0x18 | self, pose = T's | PopupRelease |
| 220 | Level bomb | 0x16 | T | LevelBombCL |
| 230 | Hold | 10 | self | HoldPositionCL |
| 240 | Navigate | 7 | self | WayPtSet (+0xac0), §7.2 |
| 250 | Go home | 8 | self, only if +0xe0 == 0 | GoHomeCL (+0x1ed0), §8.3 |
| 260 | Use waypoint | — | — | +0x88 = 1 (and the NAV's current waypoint); the mode stays |
| 270 | Land | 8 | self | GoHomeCL, then if a leader exists `440f90` |
| 280 | Takeoff | 9 | self, only if +0xe0 == 0 | TakeOffSequenceCL (+0x3e70), §8.2 |
| 290 | Dive bomb | 0x17 | T | DiveBombCL |

The other action types belong to the combat job (built in `shared/ai/combat.gd`, §13):

| type | codes | effect |
|---|---|---|
| 1 Launch | 300 (`4440d0`) | needs T, a ready weapon, a range in [min, max] and nose-to-LOS ≤ 30° (0x6008f8; 5° for weapon 0x235); single-player enemy cone ×0.5 Rookie / ×1.5 Expert; weapon 0x244 also needs `|44e770| ≤ 60°`; fires `FUN_00452680(T)` |
| 2 / 3 flares / chaff | 310 / 320 | busy 4.0 s (0x600920; a second reading gives 2.25 s: UNCERTAIN), `FUN_004545e0(0x226 / 0x21c, 0, 1)` |
| 4 change weapon | 330–390 | §13.1 |
| 5 target | 400 / 410 / 420 | → +0x70: the best of the air scan / the ground scan / the primary target (§13) |
| 6 radar | 430, 440 | 430: T = my nearest RWR emitter (`CTL.451f70()`, within 370 800 m; without a controller B+0x7c); 440 runs the same exec as 400 |
| 7 response | 450–540 | only the node's audio, e.g. 250 "Roger, closing formation" |
| 8 scenario | 550, 560 | 550 start combat (needs +0x68 == 0, +0x6c == 0, T alive: +0x68 = 1, weapons free); 560 stop combat |
| sub-brain | **1000** | `setRules(list(f4), 1)` `440790`: +0xd8 = 1, +0xdc = 1, **+0x48 = 0**. f4 0 / −1 / unknown → back to the base list: +0xd8 = 0, +0xdc = 1, **+0x48 kept**, so the base list then sees the wingman command (docs/radio.md §3) |

## 6. Combat on / off and control modes (v1.1)

Trigger ops and control-mode changes start and stop a brain:

- **Trigger op 22 Disable combat (`4407e0`)**: +0x6c = 1. Only if engaged (+0x68): +0x68 = 0, weapons SAFE
  (`FUN_004aa900(1)` sets the weapon handler's safe flag; it is a separate thing from a control mode), the selector
  is told, then `transferControl()`. A brain that is not engaged keeps flying; only 550 is blocked.
- **transferControl `4401d0`**: cancels the brain's event, so **the brain stops ticking** until the next reset;
  weapons safe; an aircraft's autopilot off (`setMode(0)`); back to the base list.
- **Trigger op 21 Enable combat (`440830`)**: +0x6c = 0, then reset (this reschedules a stopped brain).
- **Trigger op 20 (`5c4470`)**: new base brain `setRules(list(arg), 0)` + switchControlStatus(1).
- **switchControlStatus `FUN_004a8e70`**: leaving 1 or 2 → transferControl (leaving 2 also kills the scenario);
  entering 0 → transferControl; 1 → reset; 2 → scenario start + reset; 3 → player takeover.

## 7. Spawn, start and route

### 7.1 Spawn and start
- `FUN_004b7634`: class 0x1c (aircraft) → entity `FUN_0059c740`. unitinfo+0x24 = the bdb type code (0x5b4); the FM
  loader `FUN_005a8980` reads it (the same type → bd.ibx section table as the player, `data_set.rs`). status+0x14 =
  0x320 bit 0 ? 2 MISSION : 1 BRAIN.
- Activation (case 1 and case 3 alike): FM start `FUN_005a5820` with velocity **(200, 200, 0)**, i.e. 282.84 m/s along
  the heading. It uses the player's start rule:
  - Airborne ⇔ z > 800 and not (within 5000 m horizontally and 15 m vertically of the nearest base's **Tower**
    point). The nearest base is the one with the nearest **Lineup** point (`551280`).
  - Airborne: throttle 0.74, gear up, RPM 70.
  - On the ground: throttle 0, gear down, full flaps, brakes on; the engine runs only within 100 m of the Lineup.
- vehicle+0xc50's mode is 0 at spawn, so the FM treats an AI jet as "ai" only once the brain sets a mode.

### 7.2 Formations and routes
- Formation object (0x50 bytes): +0 leader (member 0), +0x18 wingman (member 1), +0x30 id, +0x38 kind (1 Alpha …
  4 Delta, 5 Echo, 6 Foxtrot, 7 Enemy, 8 Other, 9 Hotel, 10 India), +0x3c count, +0x40 waypoints in **file order**.
- Runtime waypoint (0x30 bytes): x, y, alt; **+0x10 f64 T = the file's "speed" field, which holds the planned
  arrival time in sim seconds** (0 = none); +0x1c action.
- Queries: `FUN_005bcb40(id)` leader, `FUN_005bcb90(e)` wingman of e's formation, `FUN_005bcc20(e)` leader of e,
  `FUN_005bcd70(e)` the formation (leader and wingman share it).
- Waypoint actions: **2 take off** (always wp0), **3 navigate**, **7 land** (the last waypoint), **8 alert / hold**;
  0 none. No AI code reads 1, 4, 5 or 6 (5 is the player's NAV 10 nm hold).
- Every aircraft keeps its **own** index (brain +0x88, 0 at the start, never reset).
  - Leader death (`FUN_004a86b0` → `FUN_00440eb0` → `FUN_00440ed0`, every unit with a brain at its final status):
    the wingman's index := the leader's, through `FUN_00440e90` (brain +0x88, then `FUN_00453450` selects it on the
    wingman's NAV). `FUN_005bcb90` gives a wingman only for a formation's leader, so a dead wingman passes nothing.
    The player's index is its NAV selection. With the player in the wingman's seat, the player's NAV moves (inferred:
    the player's jet has the same brain object). `FUN_00440840` first tells the dead unit's target selector
    (brain +0x40) its current target; ours has nothing to do there.
    Port: `mission_runtime.gd` `_destroyed` → `ai_flights.gd` `leader_died` (test `test_landed.gd`).
  - Leader landing (`FUN_00440f90`, once, brain+0xe0): the wingman's index := count − 1.
  - The wingman is never promoted.
- **WayPtSet (mode 7)**: `init 5d7650`: index := brain+0x88; child Fly2WayPt. `next 5d7450`: while index < count:
  Fly2WayPt to (x, y, alt) with ETA T; if index ≠ brain+0x88, post the radio WayptReport; brain+0x88 := index;
  index++. After the last waypoint the loop ends (stick neutral).
- **Fly2WayPt speed** (`5d6dc0`): d = 3-D distance; dt = T − now.
  - dt > 0: v = clamp(d/dt, 180, 300) m/s (0x6134f0/f4; C-130 type 225: [60, 215]).
  - Else 275 (C-130 215).
  - Within 6000 m (0x613504) of a slow-down point, v ≤ its slow-down speed.
  - Throttle: the speed law (§8.0).

### 7.3 Wingmen
- The wingman's leader is brain+0x44: its formation leader (the player when the player leads).
- Actions 190 / 200 fly CloseFormationCL (mode 1) / TacticalFormationCL (mode 3) on it (§8.5).

## 8. Autopilot (control loops, atp.ControlLoop.h)

The autopilot is a tree of control loops. The brain picks a mode; the mode's root loop runs its children in order.

### 8.0 Framework
- `setMode` cases: `5c8800` (cancel the old root timer, +0x18 = 1), the loop's `Init`, `5c9a90` (start child 0, arm
  the root timer). +0x10 = the time the mode went 0 → non-zero ("aiOld" base).
- CL base (ctor `5c9630`, vtable 0x612f58): slots [0 Run, 1 Init, 2 Init2, 3 FirstRun, 4 GetName, 5 Next].
  - Init `5c93f0(now, fm, pt[6], parent, cond)`.
  - Run `5cc0f0`: FirstRun once, then the current child's Run.
  - Next `5cc540`: next child; after the last, Done `5c99e0`: stick neutral, parent Next.
  - Leaf loops test `cond` first (`5cc590`) and end when it holds.
  - Root timer period: 0.5 s by default (0.2 / 0.1 s in some loops).
- Outputs go through the controller `44a240(gev, v, forced)` and are posted only on change:

  | output | channel |
  |---|---|
  | brakes (speed brake in the air, wheel brake on the ground) | GEV 0x11 (`5cc440`) |
  | flaps | GEV 0xc (`5cc490`) |
  | gear | GEV 0xe (`5cc4e0`) |
  | throttle | motion 2 (`5ca420`) |
  | stick | motion 1 (`5c9920(a, b)`: pitch a (sY = −a), roll b) |
  | rudder | motion 5 (`5c9980`) |
  | scripted heading pivot (taxi turns) | motion 0x16 (`5a8d40`, ±30 m offset) |
  | engine off | motion 0x19 |
  | drag chute (no aero effect) | GEV 0x13 |

- **Speed law** `5ca360(vt)`: `thr = clamp(0.7 + 0.005·SpeedK·(vt − V) − 0.02·SpeedBeta·a_fwd, 0, 1)` (0x612f0c,
  0x612f08, 0x612f10; SpeedK 6, SpeedBeta 0.5 from bd.ibx `[Autopilot]`; a_fwd = forward acceleration, UNCERTAIN).
  Taxi variant `5cc9d0` with SpeedTaxiK / SpeedTaxiBeta (defaults = SpeedK / SpeedBeta).
- **Roll law** `5c9bc0(φt)`: `x = clamp(wrap(φt − φ)/π · RollK/MaxRollRate − RollBeta·p·MaxRollRate·(|p| ≤ π ? 1 :
  0.5), ±1)` (RollK 4, RollBeta 0.02).
- **Pitch law** `5ca010(θt)`: first, if V > 150 and mode ∉ {0, 8} → gear up, flaps up, brakes off. Then
  `s = wrap(θt − θ)/π · PitchK · 0.5 − q · PitchBeta` plus the 1 g term `n = clamp(5aaa90(V, 1/cos φ), ±1)`, clamped
  ±1 (PitchK 16, PitchBeta 0.75; the tail is UNCERTAIN: an uninitialised local @5ca1a7).

### 8.1 Mode table

| mode | loop | brain code | AB (FM) |
|---|---|---|---|
| 1 | CloseFormationCL | 190 | no |
| 3 | TacticalFormationCL | 200 | no |
| 7 | WayPtSet → Fly2WayPt | 240 | **yes** |
| 8 | GoHomeCL | 250, 270 | **yes** |
| 9 | TakeOffSequenceCL | 280 | no |
| 10 | HoldPositionCL | 230 | no |
| 0xb | FlyStraightCL | 100 | no |
| 0xc | LevelFlightCL | player autopilot only | — |
| 0xd–0x18 | combat manoeuvres (§5) | | no |
| 0x20 | ours: the slot (§8.7), Modern IAF's flight AI | — | no |

The player's autopilot (FM motion 0xf, `5a1e40`) runs LevelFlightCL / GoHomeCL and leaves the mode unset, so it flies
with the player's FM rules.

### 8.2 Take-off (mode 9, TakeOffSequenceCL, Init `5ce0e0`)
Children: on the ground **TaxiCL (departure)** and **TakeoffCL**; then **KeepAttitude2PtAtSpeed** to wp0 at 205.889 m/s
(400 kt) until within 500 m (2-D) of it. Without a route it flies to the point at 180.153 m/s and never ends.

**TaxiCL** (ctor `5d6430`, vtable 0x6134b0; FirstRun `5d5cb0`, Run `5d5400`):
```
FirstRun: base B = 551280(pos); L = B.Lineup; leader = the route's member 0
  departure: atLineup = |pos − L| < 100;  start = leader ? wp0.T : wp0.T + (atLineup ? 0 : 10);  waiting = 1
  if atLineup: return
  departure: h = hangar near pos (5521c0), marked occupied
     path = [FromHangarTurn[h], FromTaxi[0..]] minus the points before the one nearest in 2-D
       (ours: a hangar with its own path in Modern IAF's iaf.ibx, FromHangar<h>Pt…, takes that instead;
        `Airbase::departure`, modern-iaf/docs/data-formats.md §12)
     not within 100 m of Hangar[h]: re-placed 60 m before path[0] on its heading, at rest (5a4d40) (UNCERTAIN sign)
     path[0] within 100 m of L: atLineup = 1
  to park: h = first free hangar (552190; C-130: the last), occupied; path = [ToTaxi[0..], ToHangarTurn[h], Hangar[h]]
     (ours: a hangar's own ToHangar<h>Pt… path, ending at its turn point, takes the place of ToTaxi and the turn point;
      `Airbase::arrival`)
  timer 0.2 s
Run:
  free = leader dead or leader control mode 0;  leaderMoving = leader V > 1.0
  d = me − leader in my heading frame: near = |dx| < 50 && |dy| < 200; tight = |dx| < 50 && |dy| < 100
  wingman && !free && leaderMoving: start = now
  if waiting:
     if now < start:
        wingman && !free && tight: start = now + 3
        wingman && atLineup: rudder 0, throttle 0, brakes off, DONE
        else brakes on, throttle 0, return
     waiting = 0; brakes off; atLineup: DONE; free the hangar
  thr = taxi speed law(15.4417 m/s = 30 kt)
  departure && wingman && !free && tight: waiting = 1; start = now + 3; brakes on; throttle 0; return
  departure && wingman && !free && near && leaderMoving: thr = taxi law(leader V)
  dist = along-track distance to path[i]; brakes off
  !turning && dist ≤ 30: pivot to path[i].hdg (motion 0x16 start); turning = 1
  turning && |hdg error| < 0.5°: pivot stop; i++; turning = 0; stick 0; rudder 0
     i == n: rudder 0, throttle 0, timer 0.5, brakes off, DONE
  throttle min(thr, 0.7) (not the C-130)
```
**TakeoffCL** (vtable 0x612e28; FirstRun `5ce050`: flaps down, throttle 1.0; Run `5cda10`):
```
wingman && !free && !(leader V ≥ 25.7361 (50 kt) && leader flag (UNCERTAIN)): brakes on; throttle 0.6; return
brakes off; throttle 1.0
AGL > 100: timer 0.5; AirborneReport radio at +3 s; gear up; flaps up; DONE
87.5028 < V ≤ 97.7972 (170–190 kt): θt = 3°
V > 97.7972: θt = 6°; V > 108.092 (210 kt): gear up, flaps up
else return (the roll)
stick(pitch law(θt), roll law(0))
```
Mode 9 flies without afterburner. Wingmen start 10 s after the leader, hold 3 s whenever they are closer than
50 × 100 m, and wait on the runway until the leader rolls at ≥ 50 kt.

### 8.3 Landing (mode 8, GoHomeCL, Init `5cd390`)
- Target G = the route's **last** waypoint (without a route: the given point). Children: **Fly2WayPt(G)** with ETA =
  now + 60 (the constant −60 at 0x612ff0 is subtracted; UNCERTAIN, another reading gives now − 60), slow-down
  180.15 m/s (C-130 128.68) within 6000 m, ends within 100 m (2-D); then **LandingCL(G)**.
- **LandingCL** (`5d2b30`): base B nearest G, RN = RunwayNumber, L = Lineup, hT = terrain(L). Local frame: x right,
  y along RN, `world = L + (x·cos RN + y·sin RN, −x·sin RN + y·cos RN)`. The pattern is **left-hand** (k = 2 for the
  C-130).
  - All maths is in **f32**: θ = rad(fmod(−RN, 360)) (`459bd0` / `459c90`), the matrix `43ecd0` rotated by θ,
    `43dd70`, and L + offset stored as floats.
  - For RN 270 the cos θ residue (~1e-8) is lost, so the legs are exactly axis-parallel and ChangeHeading2PtAcu's
    search takes its `x == x` / `y == y` branches. An f64 port breaks this.

| point | position | z | heading |
|---|---|---|---|
| P1 | **G** + (−5562 (C-130 −9270), 0) | hT + 700 | RN + 270 |
| P2 | L + (−5562 / −9270, −7416) | hT + 500 (C-130 600) | RN + 180 |
| P3 | L + (0, −7416) | hT + 300 (C-130 350) | RN + 90 |
| P4 | L + (0, −3708 (C-130 −1854)) | hT + 250 | RN |
| P5 | L | hT | RN |

  Children (ctor `5c6370`), in order (CH = ChangeHeading2PtAcu, CA = ChangeAlt, LW = level-wings loop, KA =
  keep-attitude loop):
  1. CH1(P1), CA1 (|Δz| < 50; C-130: within k·Pt2 or |Δz| < 250), LW1 128.681 m/s (C-130 113.239), KA1(P1, same
     speed, < k·AllowedErrPt2);
  2. CH2(P2), CA2 (50 m), LW2 102.944, KA2(P2, < k·AllowedErrPt3);
  3. CH3(P3), CA3 (**250 m**), KA3 87.503 (P3, < 1852);
  4. CH4(P4); [CA4 (50 m), C-130 only]; CH5(P5);
  5. FinalApproach(P5, < k·AllowedErrPt6); StopPlane; TaxiCL(to park); ParkInHangar (the last two in mode 8 only).

  Next `5d43e0`: at step 7 flaps and gear down; at step 13 speed brake on and the ground watch off. ChangeAlt sends
  no throttle.
- **ChangeHeading2PtAcu** (vtable 0x6138a0, Run `5dbe70`, FirstRun `5dd1f0`, period 0.2 s):
  - Target = bearing to the point. CH2–CH5 add a "line capture" `e −= ±acos(cos α)` (α between the line prev → point
    and the bearing; the sign from sgn(e) and sgn(cos α), as coded).
  - Tolerance: CH1 1° / others 0.5° (C-130 2 / 1 / 0.5°).
  - Bank limit 80° (CH3 / CH4 60°, CH5 20°; C-130 always 40°);
    `bank = clamp(e/(π/6)·Lim·ChangeHeadK − turnRate·ChangeHeadBeta, ±Lim)`.
  - The "Acu" search (|e| > 2°) iterates the bank (≤ 100 times, `bank += gap·1.745e-4`) until the turn circle
    (`R = V²/(|tan bank|·9.806)`) is tangent to the line. Original bug: it uses the perpendicular with slope −m,
    truncated to integers.
  - Pitch law(0); throttle `min(speed law(vt), 0.7)`, vt = the entry speed (CH4 / CH5 72.0611 m/s); mode 8 has no
    ground watch; rudder 0.
  - Done on two consecutive ticks with |e| ≤ tol or roll ≤ 0.2° (signed, as coded): wings level, throttle **0.1**
    (kept through the following ChangeAlt).
  - DelicateYawLim (the rudder branch) is 0 in bd.ibx, so that branch is dead.
- **FinalApproachCL** (`5d4c50`): ends within k·AllowedErrPt6 (50 m) of P5.
  - Glide frame pitched −6° along RN: (cross, along, above) of pos − P5.
  - `vt = max(Vmin(z, n) + 10.29, 72.06 m/s)`; throttle min(speed law(vt), 0.5).
  - `bank = clamp(−0.0013963·cross + e·ChangeHeadK/3 − ChangeHeadBeta·turn rate, ±80°)`, e = RN − heading.
  - `pitch° = −Kz·above − 0.5·q° − (along < −1000 ? 6 : 4)`, Kz = above < 0 ? 0.03 : 0.3 (C-130 0.05).
- **StopPlaneCL** (`5d44d0`):
  - V ≤ 50 kt: rudder 0; chute released; the landed handler `440f90` once; brain+0xe0 = 1; LandedReport radio at
    +3 s; DONE.
  - Rolling (|pitch| ≤ 0.2°, on the wheels): rudder 0, throttle 0, chute; heading error > 0.1°: nose-wheel steering
    via the roll stick.
  - Else (flare): throttle 0, wings level, pitch 0.
- **ParkInHangarCL** (`5d66b0`): creeps at 2 kt to Hangar[h]; when the distance grows: stop, brakes, re-placed at
  rest, **engine off**. The jet stays there (no despawn), and the **AI has no go-around**.

### 8.4 Navigation leaves (Fly2WayPt's children, `5d6ad0`)
The loops read `s = (x, y, z, pitch, roll, heading)` from `5a68f0`: the position and the **flight-path attitude**
(velocity direction and roll; `5a68f0` passes α = β = 0 to the attitude slot). They read the rates from `5a6b10`
(flight-path pitch rate, roll rate, turn rate).

Each Fly2WayPt tick:
1. tests its condition (PassWaypoint `5d70a0`: passed once the 2-D distance was ≤ R and then grows; R = 1852 m, or at
   the first step 9265 / 6485.5 / 3983.95 m for MaxG ≤ 4 / < 6.5 / else when starting inside it);
2. turns the ETA speed into a throttle;
3. runs the current child. A finished child centres the stick, and the next one starts on the next tick.

The children, in order:
1. **LevelWingsPitch0Accel** `5d2400` (180 m/s; C-130 90, type 220 135): pitch target 0, or FpmPitchReqAtLowVels
   (−5°) below Vmin(z, 1.2 g) until Vmin + 15; done when |pitch − target| ≤ 0.02π, |roll| ≤ 0.01π and the speed is
   reached (±3 m/s); throttle from the speed law.
2. **ChangeHeading2Pt** `5ddef0`: bearing to the point; `bank = clamp(e/(π/6)·ChangeHeadK·80° − turnRate·ChangeHeadBeta,
   ±80°)` (C-130 ±30°), pitch 0; done within 0.02π; sends no throttle.
3. **ChangeAlt** `5cf320` until |Δz| < 250 m or the point is passed (a second PassWaypoint, 1852 m): wings level,
   `pitch = clamp(Δz·ChangeAltK·(π/12)·0.001 − vz·ChangeAltBeta, −π/6, π/12)` (C-130 ×0.002, [−π/12, π/18]).
4. **KeepAttitude2Pt** `5db510` until passed: bank ±45° on the bearing error, pitch = the elevation of the point; ring
   period 0.5 s (near / manoeuvring), 1.5 s (< 3708 m, clear ahead 1.9 s), 3 s (clear ahead 3.4 s).
5. LevelWingsPitch0 (normally never reached).

**Watch-ground** `5ca480` runs in every leaf (it is switched off only from the landing's final approach): the point
`pos + vel·t`, `t = max(−vz/15, 0) + WatchGroundDeltaTime`. If that point is below terrain + hAboveGround (200 m), or
has no line of sight: wings level, climb `max(π/24 + atan2(h − z, d), 0)`, throttle ≥ the 250 m/s law.

At the route's end the stick stays centred and the throttle frozen. The brain decides what comes next (in the data:
the "Land" / "go home" rules on waypoint action 7).

### 8.5 Formation loops (modes 1 / 3, vtables 0x613220 / 0x613238, step `5cfb50`)
- Slot: Close lateral 100 m, Tactical 200 m (150 m when the leader is below 1524 m), longitudinal −20 m. The leader is
  the formation's member 0. The loop runs every 0.25 s.
- Below Vmin(z, 1.25 g): LevelWingsAccel (wings level, −11°, 300 m/s) until above Vmin(z, 2.5 g).
- Geometry: A = the leader's horizontal nose, C = its left; `k = 2000 − min(|Δz|, 200)·8.5`; steering point
  `Q = L + k·A − d·C` at `max(2·Lz − z, terrain + 91.44)`; the slot `S = L − 20·A − d·C`. Only network play sets the
  side flag, so in single player **every wingman takes the right slot** (UNCERTAIN).
- Steering: LookAt `5ca7d0` case 1 on Q. Outside a 10° cone it rolls the target into the lift plane. Inside it, wings
  level while Q is ≥ 1854 m away, else the leader's bank ± a blend to SlowConeRollK. Stick law `5cb4d0`
  (DogChaseRollK, LookAtK / LookAtBeta).
- Speed `5d0870`: `x = (angle(pos − S, leader velocity) − π/2)·min(|pos − S|, 5562)/4500`,
  `spd = VL + 2·VL·(x − x²/2 + x³/6 − x⁴/24) − 30`, clamped [103, 515] m/s; then the speed law.
- Consequence (as decoded): Q is 300–2000 m ahead, so the loop leaves a lateral error of less than ~10° of that
  uncorrected. The result is a loose formation that wanders a few hundred metres (test:
  `crates/iaf-flight/tests/autopilot.rs`).

### 8.6 Other modes
- HoldPositionCL (10): KeepAttitude2PtAtSpeed at 180 m/s around the entry point (z ≥ terrain + 300), never ends.
- FlyStraightCL (0xb): LevelWingsPitch0Accel at 180 m/s.
- The combat modes (0xd–0x18): see the combat job (§13.3).

### 8.7 Ours: the slot loop, the home hangar and the AI jets on the 6-DoF

Modern IAF's flight AI (`crates/iaf-ai`, [../modern-iaf/docs/ai-plan.md](../modern-iaf/docs/ai-plan.md) §6) flies its
jets with the loops below. The 1998 game never sets mode 0x20 or a home hangar, and its jets fly the original flight
model, where none of the 6-DoF cases applies. Every figure here is inferred, tuned on the 6-DoF Sufa (test
`crates/iaf-ai/tests/four_ship.rs`, 19 November 2026).

- **Mode 0x20, the slot** (`MODE_SLOT`, every 0.1 s): keeps `Autopilot::slot` = (forward, right, up) m in the
  leader's horizontal frame (its track).
  - Across the flight path it asks the acceleration a = a_S + ω²·e + 2ζω·ė (ω 0.3 rad/s, ζ 0.8): a_S is the slot's
    own acceleration (the leader's, from its velocity a tick before, and the turn of its frame); e is the position
    error, its horizontal and its vertical part each at most 150 m; ė the velocity error. The lift that gives a, with
    gravity's share, is flown as a bank (at most 75°) and a load factor on the wing's present lift axis (at most 7 g
    and the lift at 15° α; never a push).
  - Along the flight path it flies the slot's speed, plus 0.08 m/s per m of along-track error (−30 to +60 m/s), plus
    the slot's acceleration × 1.5 s, never below the jet's level speed at the circuit's second α, through a PI
    throttle (0.03 per m/s, 0.01 per m/s·s); the speed brake opens when 10 m/s fast. The ground watch stays on. A
    leader 20 m off where its last tick's position and velocity put it (a new leader after a promotion) gives no
    acceleration that tick.
  - A wingman in the air more than 6 km from its slot flies at the slot point instead (the flight layer's steer, 3 g,
    its leader's speed plus 60 m/s, at least 260 m/s; `REJOIN` in `flight.rs`) until within 3 km, each jet at its own
    slot (#4 does not fly on a rejoining #3). Far out, the slot loop's capped spring
    only matches the leader's velocity: on a lead circling at 30° of bank, wingmen 17 km off after a SAM defence flew a
    parallel circle for ten minutes (test_four_ship, 20 Nov 2026).
  - A nearer slot is the same law (the rejoin): it closes sideways at about 28 m/s and along the track at up to 60 m/s.
    While a far slot flies more than 60° off the jet's path, the jet flies no slower than the slot's speed less 30
    m/s: without that floor a slot flying the other way asked a speed below zero along the path, and the jet climbed
    to it at idle with the speed brake out into a stall.
  - The shapes (`SHAPES` in `flight.rs`) are the seven of Hebrew Wikipedia's "טיסת מבנה" gallery, the missing man
    left out (the user, 20 November 2026; the names in modern-iaf/docs/research/radio-terms.md). The slots of #2,
    #3, #4, forward / right of #1 in m, are inferred: fingertip (−60 / −60, −60 / 60, −120 / 120), line abreast
    (0 / −1500, 0 / 1500, 0 / 3000), trail (600 m apart), echelon right and left (60 m steps back and out), diamond
    (#2 and #3 as in fingertip, #4 at −120 / 0, behind #1), vic (−90 / −45, −90 / 45, −180 / 90: deeper than the
    fingertip, as in the gallery's picture) and delta (#2, #4, #3 abreast 120 m apart, 120 m behind #1). Any two
    jets are at least 84 m apart: 60 m is where a wingman steps down and where it pulls away. The wedge, without a
    Hebrew term, was dropped. Tested and changed (20 November 2026): the delta's three abreast 90 m apart made #4,
    climbing back into the middle of the row, set off the pull-away on #2, which went 354 m off in a 45° bank turn;
    120 m apart, none pulls away. A transit step of 70 m in place of 35 m (deeper than the 60 m of the pull-away) was
    also tried and dropped: the level crossings no longer pulled away, but in the turn the longer climbs back did.
  - **Close up / spread out** (the user, 20 November 2026: "we should allow ask for "get closer", which will even
    lead to 10m apart"): the lead's radio command to the flight (the radio menu's Formation → Spacing page) takes the
    close shapes one step in or out (`CLOSE_STEPS` in `flight.rs`): standard (the slots above), close (half: 30 m),
    tight (a fifth: 12 m between the slots). Tight is the parade position: an F-16's 9.96 m span[^w-f16-span] 12 m from
    the next jet's centreline leaves 2 m (7 ft) between the wingtips, inside parade's 4 to 10 ft[^cnatra-parade]; close
    is inferred. Line abreast and trail keep their spacing, and a close up there, past the tight step or to one jet or
    the element is "unable"; a spread out at the standard too. A
    new shape keeps the step; the landing sequence's trail is at the standard. Each wingman answers with its callsign
    and calls "in position" at the new spacing (no transit step: the slots move along their own lines from #1).
    Every distance the flight keeps between its jets in the close shapes takes the same share: the step down (50 /
    60 m), "in position" (50 m), the pull-away (60 m, on until 100 m or 70 m in its slot) and the pull-away's
    look-ahead (4 s, sampled every 0.25 s). At the close and tight steps the slot loop (`Autopilot::close`) rolls the
    leader's lift on by the leader's roll rate over 0.5 s (the wingman rolls with the lead's wings, as in a "welded
    wing" turn), rolls by its own law (`SLOT_ROLL`: 4 / rad of bank error, 0.3 per rad/s, over the jet's highest roll
    rate) and triples its throttle's gain (`SLOT_CLOSE_KP`); all inferred. At the standard the loop is as before.
    Tested and changed (24 November 2026, `close_up_and_spread_out`): with the standard laws and the pull-away's full
    look-ahead, the tight four-ship in the lead's roll into a 45° bank turn tripped the pull-away and went 129–193 m
    off its slots, two jets 10.7 m apart; with the look-ahead alone scaled, 160 m; a stiffer spring (0.6 and 1.0
    rad/s in place of 0.3) oscillated, even at the standard (511 m and 748 m); the quick roll law at every spacing
    moved the landings' spacing out of its 15–60 s (ground_run_at_ramon). Measured at 400 kt and 3,000 m: close
    within 3.5 m level, tight within 2.1 m level and 0.1 m in a diamond, no two jets nearer than 16.8 m; each step in
    position in 8–24 s. A break or a fight takes a jet out of its slot by its own tree, as at any spacing.
  - **The lead past the parade's limits** (`PARADE_LOOSE`, `PARADE_LIMITS`, `PARADE_SETTLE_S` in `flight.rs`): the
    parade's lead rolls into 30° of bank at the parade rate of roll[^p1213-parade] (about 10°/s, second-hand: a
    search engine's quote); a lead that manoeuvres harder has the section in cruise, a looser
    position[^p1213-cruise]. At the tight step the flight holds the close step (30 m) while the lead banks past 35°,
    rolls faster than 20°/s or pulls more than 1.5 g, and closes back up once the lead has flown within those for
    5 s; the margins and the 5 s are inferred. The wingmen move without a call. Until the flight closes back up, the
    step down and the pull-away keep the tight step's distances.
    `IafAi.state` gives the step held as `held`. Measured at 400 kt and 3,000 m (`tight_flight_loosens_in_a_sharp_roll`,
    `close_up_and_spread_out`): in the lead's 45° bank turn, the close step held within 7.3 m, no two jets nearer than
    16.8 m; in a sharp roll to 40° of bank and a 2.6 g pull (the player's break), F-16I and F-35I, each wingman at most
    21 m past where its slot moved, no two jets nearer than 15.1 m, the tight slots held again within 2 m 16 s after
    the lead rolled out. Tested and changed (25 November 2026): the tight slots held through that break left each
    wingman up to 38 m off its slot and two jets 13.1 m apart (F-35I), and about 100 m off in the game's
    _close_up_shot.gd; loosening with the step down and the pull-away at the close step's distances set both off with
    the jets still 17 m apart and threw the flight 213 m off its slots.
  - Measured at 400 kt and 3,000 m: fingertip held within 9.3 m in level flight, every shape of the flight within
    10.7 m, 23.6 m in the lead's 45° bank turn; a rejoin from 5 km behind in 104 s (20 November 2026). Each close
    shape ordered in the lead's continuous 45° bank turn: all "in position" in 12–25 s and held within 60 m for 20 s
    from then on, except echelon left from delta, where #3 crossing to the left under the others set off the pull-away
    (one jet 236 m off) and the flight held 11 s later (`close_shapes_changed_in_a_turn`).
- **The home hangar** (`Autopilot::home_hangar`): the landing's TaxiCL parks the jet there when it is free; without
  one, the original's first free hangar. The flight sets it for every jet that starts at a shelter, the player's
  autopilot too, so no jet takes another's shelter.
- **One instant for every jet**: the host steps every jet of a frame first, the player's and the AI's at any cadence
  (the player's time compression steps), then the flight senses them all (`Flight::sense`) and reads each one as
  sensed. The flight models' clocks are never compared: each starts at 0 when its flight model starts, so a
  restarted flight model (test_four_ship restarts the player's: the clocks 44 s apart) or a late spawn puts them on
  other epochs. Until
  2026-11-19 the flight moved each jet to the reader's clock (at most 0.25 s): with the clocks 44 s apart, the
  wingmen saw the lead 50 m ahead of where it flew, and test_four_ship failed 4 runs of 4 (slots 2.5–19.7 m apart,
  a slot never reached). Test `one_time_base_for_every_jet`: the lead's flight model 40 s behind and stepped 4
  times a frame, its wingmen once: #2 is fed the lead where it flies.
- **Collision avoidance** (`Autopilot::avoid`): every frame the flight (`crates/iaf-ai`) checks each of its AI jets in
  the air against every other jet of the flight: each jet goes on with its present acceleration (its turn and its
  speeding up, from its velocity over the last 0.3 s; held while it pulls away, or its own pull would clear the
  prediction early), sampled every 0.25 s and at the straight lines' closest approach; when the closest approach within 4 s
  comes nearer than 60 m, the
  jet pulls away from it at 3 g (straight at it: the higher number goes down), in any loop, every 0.1 s, until the
  closest approach is 100 m, or, a jet in its slot (within 50 m of it), 70 m with the jets no longer closing (the
  closest approach is now);
  below 150 m over the ground never down, and not once the landing's ground watch is off. Without it two wingmen in fingertip came within 4.5 m in the lead's 80° bank break.
  A pull that stopped at 60 m (until 2026-11-19) left two AI jets 37 m apart. A pull that went on to 100 m in
  every case (until 2026-11-22), more than the slots' 84 m, never stopped in a slot: in the lead's 30° bank turn #3
  and #4, 69 m apart at the join-up, pulled on and scattered the flight 500 m (test_four_ship). Also tried and
  dropped (2026-11-22): that release at 60 m for every jet (in the dogfight two of our jets on one MiG-29 pair let go
  of each other sooner and neither got a gun burst in three minutes, wing_battle), and at 60 m for a jet in its slot
  (the diamond ordered in a 45° bank turn went 446 m off, close_shapes_changed_in_a_turn). A prediction in straight lines (until
  2026-11-19) saw a wingman released from echelon right on afterburner, just behind the player's jet in its 30° bank
  turn, about 1.5 s late: it passed 13–29 m from the player's jet in the game (34–36 m in the Rust case
  `rtb_from_a_turn_round_ramon`, now 50–55 m).
- **An AI jet on Modern IAF's 6-DoF** (`ApView::circuit`, `ApView::sixdof`; the player's autopilot keeps its laws):
  - Its route, take-off, go-home, hold and slot loops (modes 7, 8, 9, 10, 0x20) fly the landing circuit's path law
    and bank limit (`REAL_CIRCUIT`). The original pitch law pushed the jet to −3.5 g rolling out of an 80° bank, a structural
    failure. The other modes keep the original laws (not yet flown on the 6-DoF).
  - Going home (mode 8) it opens the speed brake while its speed law is at idle and still 15 m/s fast (it entered the
    circuit at 235 m/s and lowered the gear at 390 kt); the final's speed sum runs only while the lever is inside its
    travel; it lands with the player's flare (`Landing::flares`).
  - On the ground the taxi's speed law is a PI from idle (0.02 per m/s, 0.01 per m/s·s, at most 0.4): the original's
    0.7 lever is near the 6-DoF's military power. The wheel brakes hold the jet within 3 m/s of its taxi speed (its
    idle thrust ran it to 36 m/s); it idles through a pivot (thrust in the 30 m wheel turn tipped it onto its tail);
    between the pivots the nose wheel steers at most 3° toward the next point. TakeoffCL's hold on the runway idles
    (the original's 0.6 lever against the brakes). The taxi to park leaves out the turn about at the hangar point;
    ParkInHangar steers at the point and sets the jet on it facing out (the ground crew's push into the shelter).
  - TakeoffCL's rotation: from the original's 170 kt the pitch law aims at a 10° climb angle (the 6-DoF view's pitch is
    the flight path's, so on the runway it pulls until lift-off; at most 9.4° on the wheels), the gear and flaps up
    past 210 kt once off the runway. At the original's 3° / 6° (until 2026-11-19) a Sufa with 2 t of stores was still
    on its wheels past the tyres' 225 kt and burst both main tyres; on its rims it stopped for good in its first
    taxi turn after landing (test_four_ship: 2 of 5 runs).
  - Measured at Ramon from the four Sufa shelters, each with 2 t of stores: airborne at 174, 212, 238 and 303 s;
    landed at 966, 1101, 1127 and 1234 s; each parked at its shelter with the engine off, no tyre burst; at the least
    142 m between jets on the ground and 46 m in the air. Once the landing sequence starts, the wingmen not yet sent home wait in trail, stepped down: in
    fingertip through the lead's circuit (80° banks) #3 had come within 18.8 m of the lead.
  - The landing sequence also starts when the lead is low (under 300 m above the ground) with the gear down, or on
    the ground again, anywhere: a wingman whose turn has not come then holds where it is (mode 10) until it is sent
    home. Measured with the lead landing at Ramon and the flight's home at Nevatim: all four landed at Ramon in order,
    #3 and #4 held first, at the least 41 m between jets in the air.
- **The recovery, end to end** (2026-11-22, the user: "Finish landing"). The flight's home is the base nearest its
  route's last waypoint. Its landing order is the release order: the lead (the player) lands when he chooses, and
  once its gear is down again within 20 km of home, or low anywhere, the wingmen go home one every 20 s, #2, #3, #4,
  each on the original's left-hand circuit. On the way in each keeps at least 30 s behind the jet sent home just before
  it (an AI lead first; behind the player, whose own landing has no track, the 20 s alone), by the way left to the lineup along its track (`Autopilot::to_go`: to the route's last
  waypoint, then the pattern's points): short of that, or ahead of it, it flies that jet's speed less 0.02 m/s per m
  short, at least 85 m/s, until the turn to final (`Autopilot::pace`: the throttle held under it, the speed brake out
  15 m/s above it; `flight::SPACING`) (§8.3; the flight flies no overhead break: the 1998 game has none and no
  source gives the IAF's; Modern IAF's instructor flies one, [../modern-iaf/docs/training.md](../modern-iaf/docs/training.md) §14). Every figure in this list is inferred. Measured at Ramon (F-16I, 2 t of stores): landed
  136, 57 and 36 s apart (the first is the lead's own way in before #2 is sent); at Nevatim (MiG-29A) 131, 55 and 28 s;
  the lead landing away from home 239, 42 and 26 s. Jets in a circuit land some 15-40 s apart (inferred; no source
  found for the IAF's). With the 20 s alone (until 2026-11-23) they landed 136, 23 and 21 s apart, and on the
  laptop's build #4, sent 20 s after #3 and flying the circuit faster, landed first (1148 s against 1171 s). Tried and
  dropped (2026-11-23): sending the next only once the one before was on its circuit's second leg (in order, but
  109-137 s apart, a whole circuit), or once it had begun its circuit (#4 still landed first); spacing on whichever
  jet was nearer the lineup (at the last waypoint #4, on a better line, came out ahead and #3 was spaced behind it).
  - **The tower's landing calls** to each AI jet of our flight (not an enemy flight's; `Flight::tower_calls`,
    `radio.gd flight_call`): "Kidon 1-2, cleared to land runway 25 right" (`ACFT_CLEAR_TO_LAND`, its runway and wind as
    the player's) on its turn to final (LandingCL's CH4, autopilot `phase` 11), and "Kidon 1-2, welcome back, taxi to
    parking" (`ACFT_TAXI_TO_PARK`) once its roll has stopped (StopPlane). The tower is the talking tower in range of
    the jet. Each is answered with the callsign alone ("Kidon 1-2."), the acknowledgement of
    [../modern-iaf/docs/research/radio-terms.md](../modern-iaf/docs/research/radio-terms.md), in the wingman's voice.
    The words are the tower's lines the player hears; the tower addresses the wingman by its kidon-style callsign. The
    player asks for his own clearance on the radio menu.
  - **The taxi's pivots** (an AI jet on the 6-DoF): a pivot begins at its turn's own lead, 40 m × tan(half the turn),
    within 5–40 m, where the original began every pivot 30 m before its point; before a turn of more than 10° the jet
    slows to 8 m/s, braking at most 1.5 m/s² from the taxi speed (the 30 m wheel turn's speed on the tyres' side grip
    is 9 m/s), with the brakes within 0.5 m/s of that speed; it reaches the departure's last point, the lineup, at a
    walk (2 m/s). At the 30 kt taxi speed the jet braked straight on into a 90° turn and swung 40 m wide: at Nevatim,
    whose four spots turn off one taxi line 25 m apart, #4 swung into #2's spot and came within 1 m of it (found by
    the ground run 2026-11-22). A 97° turn onto the runway at Ramon swung 15 m past the centreline; the last 2° pivot
    onto the lineup stopped the jet 30 m short of it.
    The leg to the lineup (2026-11-23) steers at the runway's line through the lineup 25 m ahead of the jet, with up to
    0.3 of the wheel (elsewhere 0.1), and its pivot onto the lineup ends within 0.1° of the runway's heading (elsewhere
    0.5°). A pairs wingman's turn onto the runway at Nevatim swung it 13 m past its line; steering at the point with a
    3° wheel, it came to the lineup 21° off, and the pivot, still near full lock at 0.5°, swung on 1.5° past: #2 rolled
    9.6 m beside #1, not 15. A look-ahead that runs on past the lineup (10, 15 or 25 m) and the wider wheel alone were
    tried and dropped: #2 ended 4 to 51 m beside #1.
  - **The taxi in, spaced** (`Flight::taxi_hold`, `Autopilot::hold`): an AI jet taxiing in (to park, or creeping into
    its shelter) stops on its brakes while another jet of the flight with its engine running is on the ground in its
    way: within 150 m along its heading and 25 m across, or nearer than 60 m and not behind it. Two jets taxiing in
    that are each in the other's way: the higher number holds. The player's jet counts, and holds for nobody. At 80 m
    along a jet stopped 21 m behind the one ahead; turning toward a jet stopped beside its turn point it came within
    31 m.
  - **The take-off roll** (an AI jet on the 6-DoF): the nose wheel turns onto the runway's heading (a pedal of 1 per
    radian of error less 0.5 per rad/s of turn, at most 0.1) below 30 kt; above, the 6-DoF's nose wheel castors unless
    a pedal of 0.02 engages it and then turns the jet hard, so the pedal falls with the speed squared and only an error
    of a degree or more engages it. Left alone the jet rolled on the heading its taxi left: 3° off (60 m across a 1.2
    km roll) after its last pivot ended in a turn and it coasted on turning. A wheel held on a line at speed swung a
    wingman 4° off and was dropped. In a pairs take-off each jet steers onto its own line, the runway's through the
    lineup point (the wingman's 15 m beside it): the heading aimed at turns back by atan(off / 100 m), and above 30 kt
    an error of 0.3° or more (heading and turn) engages the nose wheel with the least pedal, 0.02, a frame at a time
    (2026-11-24, inferred). On the heading alone each jet kept whatever error under a degree its lineup pivot left: at
    Nevatim Kidon 1-1 and 1-2 closed from 15 m to 10 m by the lift-off, 1-3 and 1-4 opened to 26 m with a line but no
    nudge; with both, all four lift off 15 m from their mates at Ramon and Nevatim.
  - **A runway turned into the wind** (24 November 2026; [autopilot.md](autopilot.md) §2.4): the departure runs to
    the main end's lineup and backtracks down the runway to the other end (`Airbase::reversed`). A jet ahead turns
    round there and rolls back toward the jets behind it, so an AI jet taxiing out holds short within 150 m of the
    runway's entry (`Airbase::backtrack`, `Flight::backtrack_hold`, `Autopilot::hold_short`; inferred: the holding
    point is 86–101 m before it) while a jet ahead of it in order is still on the ground with its engine running; a
    pairs wingman goes with its element lead. Measured at Ramon (F-16I, 2 t of stores, `ground_run_at_ramon_into_the_wind`):
    each lifted off on 07L's heading, the least distance between two jets on the ground 43.8 m (17.2 m, #3 on the
    runway as the lead rolled toward it, without the hold), the wingmen landing 65 and 41 s apart, all parked.
  - **Pairs** (`Flight::pairs`, `IafAi.pairs`, the dev hook `ai_flights.gd flight_pairs`; no mission sets it yet;
    the default is the stream): #2 lines up beside #1 and #4 beside #3, 15 m apart, on the side of its slot in the
    shape (#2 left and #4 right in fingertip); its runway entry and lineup points move with it, so its last leg runs
    beside its lead's. An AI element lead waits on the runway until its wingman is lined up, at most 90 s
    (`Autopilot::hold`); the wingman rolls when its lead starts to roll (1 m/s, where the stream waits for 50 kt). The
    lead rolls at military power and the wingman keeps beside it on the throttle (military, plus 0.03 per m the lead is
    ahead and 0.1 per m/s it is faster, at least 0.3) while the lead is within 200 m; a lead already gone, as the
    player who rolled first, leaves it at full power. The lead keeps military power until its own lift-off. The
    player as #1 does the same by hand: he waits for #2 and rolls at military power. The mates fly free of each other's collision avoidance from the roll until they are 60 m
    apart in the air, or 120 s after the lift-off, and do not step down for each other. The second pair lines up once
    the first rolls. Measured (F-16I, 2 t of stores; #1 as the player): at Ramon the pairs rolled 0.8 and 0.7 s apart,
    lifted off within 0.1 s, 15.0 and 15.6 m abreast and less than 1 m ahead or behind at the lead's lift-off, at the
    least 14.8 m apart (the F-16's span is 9.45 m); at Nevatim 15.3 and 14.7 m abreast, at the least 14.0 m apart
    (2026-11-23; before the lineup's line steering 9.6 m at Nevatim, the wings 0.2 m apart).
    The 15 m is inferred: the lineup runways are 44–46 m wide, Hatzerim's 28L 34 m, where the wingman's wheels run
    0.8 m inside the edge (the F-16's track is 2.4 m).
  - **An AI lead with the player in its flight** (ours, Modern IAF's formation lessons; a mission's `start.seat`,
    [../modern-iaf/docs/training.md](../modern-iaf/docs/training.md) §16.8): the lead starts on the flight's
    clearance, taxis once every other jet has run its engine `TAXI_AFTER_S` (120 s), waits on the runway in a pairs
    take-off for the player beside it (no time limit) and takes no avoiding action from the player. Its plan
    (`Flight::set_plan`) gives an order once it has passed each waypoint (`Flight::lead_order`: a shape, the rejoin,
    close up, spread out, a tactical turn), said as `lead_*` calls. The tactical turns (`LeadStep::Turn`, CNATRA
    P-1221): the tac turn of 90°, the jet on the outside of the turn first at 70° of bank (`TAC_G` 2.9 g), the inside
    jet once the outside jet has flown the distance across between them (P-1221's "nose on"; inferred); the in-place turn of 180°, every jet at once; each mirrors the
    slots (the sides swap). `cargo test -p iaf-ai --test lead`.
  - **Tests:** `cargo test -p iaf-ai --test four_ship ground_run` (the ground runs at Ramon and Nevatim: at the least
    30 m between jets on the ground, the tower's calls to #2–#4 in order and none to the player),
    `--test four_ship taxi_in_behind_a_stopped_lead` (the lead stops 240 s on its way in: the wingmen hold behind it,
    at the least 53 m), `--test four_ship pairs_take_off` (Ramon and Nevatim); `modern-iaf/tests/test_four_ship.gd`
    (sent home: the tower's calls said, at the least 30 m between the wingmen taxiing in) and
    `modern-iaf/tests/test_pairs_takeoff.gd` (Kidon 1-3 waits for 1-4 and they take off together).

### 8.8 Ours: elements, the split, the reactions and the AWACS calls

Modern IAF's flight AI (`crates/iaf-ai/src/flight.rs`, [../modern-iaf/docs/ai-plan.md](../modern-iaf/docs/ai-plan.md)
F12–F14). The 1998 game sets none of it. Every figure is inferred, tuned on the 6-DoF Sufa (tests
`crates/iaf-ai/tests/four_ship.rs`, `modern-iaf/tests/test_four_ship.gd`, 19 November 2026).

- **Mode 0x21, the steer loop** (`MODE_STEER`, every 0.1 s): flies toward `Autopilot::steer.to` at that point's height.
  The heading error is flown as a turn rate of 0.3 per radian, at most the order's load factor; the height through a
  spring and a damper (0.15 rad/s, 0.8); both as a bank and a load factor (the slot loop's `lift_stick`, at most 75° and
  7 g). The wingmen's turn so flown climbs: the load factor is the wanted lift projected on the wing's present lift
  axis, so a jet still rolling in pulls lift upward, and at the 75° limit a 6.5 g turn's lift upward is 1.7 g (a 6.5 g
  turn to a level point 90° off climbs 252 m in 8 s; per-frame bank, g and vertical speed, 22 November 2026).
- **The enemy fighter's turn laws** (`Steer::fighter`, set only by the enemy trees, §18; the 1998 game never flies the
  steer loop and the wingmen never set it): the bank up to 85°, so a level turn holds its height up to 11 g; the
  fighter's roll law, the roll rate 4 per radian of bank error within the jet's MaxRollRate (the 1998 roll law `5c9bc0`
  rolls in with a time constant near 1.3 s on the 6-DoF: a 6.5 g turn was still rolling in after 4 s); never more lift
  upward than the height law asks (the load factor at most that lift / cos bank, so it grows as the bank comes in); the
  turn what the load factor leaves once that lift upward is held, up to the jet's own g limit (not the slot loop's 7);
  the height law at 0.5 rad/s (a bank a degree past the target sinks a 9 g turn at 0.16 g: at the wingmen's 0.15 rad/s
  the level break lost 46 m in 8 s, at 0.5 rad/s 9 m; 0.3: 17 m, 0.8: 7 m; a damping term on the roll rate changed
  nothing); the loop's tick 1/30 s. For a point more than 200 m below the lift upward is at most 1 g, so a hard turn
  goes down while it turns (at 75° with the full load factor a 6.5 g notch climbed at up to 39 m/s, the flaky
  `modern-iaf/tests/test_intercept.gd`, 22 November 2026). A level hard turn holds its height within 30 m, the band of
  the FAA's steep-turn standard (±100 ft)[^faa-acs] applied to a hard turn (inferred): the 6.5 g turn above −11 / +3 m
  in 8 s, the beam +6 m and −1 m after 40 s, the plain tactics' 9 g level break −9 m in 8 s. The same laws on the
  wingmen starved their break (2.3 g) and their join-up in a turn (228 m off) when tried with the slow roll law (22
  November 2026); they stay the enemy's. Check: `cargo test -p iaf-ai --test intercept fighter_laws_only_when_asked`
  (without the laws the turns climb to the metre as before the change), `--test intercept defence_by_the_tactics`,
  `--test dogfight defensive_break`.
- The steer loop's throttle is the speed law's, at most the order's (0.74, military: the
  afterburner stays out). The ground watch stays on. A far point is a heading; a near one is circled.
- **The elements:** #2 flies on #1 and #4 on #3. In the shape each wingman keeps its slot in the lead's frame, so #4's
  slot is relative to #3's slot. When #3 flies on its own (the split's task, a defence, any loop but the slot), #4 flies
  on #3 itself, with its slot relative to #3. #4 was first flown on #3 itself in the shape too. It amplified #3's
  corrections: it ended 385 m off in a change of shape and 632 m off in a join-up in a turn. That was tested and
  dropped on 19 November 2026. A lost #3 or #1 leaves its mate on the flight lead (promotion as before: 1 → 3 → 2 → 4).
- **The split** (`Flight::split(now, at)`, `IafAi.split`): element 2 takes its own target in the same area. #3 flies
  to the target at its present height and the lead's speed (at least 200 m/s). It circles the target at 1.5 g (about
  a 4 km circle) with #4 on it, until a regroup. The flight stays one flight: one route and landing sequence, the
  threats and the calls. The target must be within 40 km of the flight lead, or #3 and #4 answer "unable". The split
  ends when #3 is lost, is sent home, becomes the flight lead, or the landing sequence starts.
- **The regroup** (command `regroup`, to anyone): element 2 rejoins its slots ("in position" each), from beyond 6 km
  by the far rejoin (§8.7): from 20–30 km in about 7 minutes.
- **The reactions** (each AI jet in the air with the gear up, the flight lead after a promotion too). The host feeds
  each jet's threat every frame (`Flight::threat`, `IafAi.set_threat`). `ai_flights.gd` gives the nearest missile
  flying at the jet (the MAW sees every missile, whatever its seeker), else the nearest radar locked on it
  (`combat.gd on_lock`, kept on the entity as `locked_by`).
  - The call comes at once, heard after the reaction time (1 s): `spike` for a lock from the air, `mud` from the
    ground, `defending` for a missile. A missile after a lock is called again.
  - After the reaction time the jet defends (the steer loop, every decision). Against a radar (a lock or a radar
    missile) it beams: it turns the threat 90° off its nose, on the side nearer its track (the Doppler notch). Against
    an infrared missile it breaks into the missile. It pulls 4 g against a lock and 6.5 g against a missile, at
    260 m/s. Against infrared it stays at military power: a flare beside a lit afterburner has a quarter of its chance
    (§15.6), and above 4 g every decoy has more.
  - It asks for a decoy (chaff against a radar missile, flares against an infrared one) once at the launch's cue,
    the first decision after its reaction (the CMDS's automatic program starts on the RWR's launch or the MAW's warning,
    `cmds.rs` AUTO), then each decision while the missile is within 6 s of reaching it (its time to go at the closure,
    `ecm::WINDOW_S`; a decoy released earlier has less chance and burns out). A lock alone takes none (a decoy acts on
    missiles only). Before 22 November 2026 the window alone set it: a jet beaming a long SAM shot (test_four_ship's
    S-300 at 15 km) often had none, the missile still more than 6 s out when it flew out of energy or when the test's 30 s limit ran out. `ai_flights.gd` releases it through `combat.gd`'s path
    (the jet's stores, one each 4 s); what it does to the missile is §15.7's seeker rule.
  - Its element mate (1 and 2, 3 and 4), an AI jet in the air and itself clear, sees a missile launched at its partner
    (the smoke) and calls `break_left` or `break_right`, the partner's turn. That covers the player as #1 too. A lock
    is heard only on the jet's own RWR, so it gets no mate's call.
  - Clear for 5 s, it goes back: a wingman rejoins its slot ("in position"), a lead its route.
  - Measured: the lock called and the beam flown 1.2 s after the lock; against an infrared missile behind it, the break
    left at up to 5.8 g with the throttle at most 0.74, flares, #4's `break_left` 1.4 s after the launch; against the
    lock no chaff (2026-11-22).
- **The AWACS calls** (`Flight::awacs`, `IafAi.awacs`; `radio.gd` passes each call of `IafFlightController.scan`,
  which now also returns {bearing, miles, code}). For a hostile or unidentified contact, the first AI jet by number
  that holds the called point within 74 km and ±60° of its nose (a fighter radar's 40 NM) reports `contact` after its
  reaction time.

- **Engage my target** (`Flight::engage(now, to, id)`, `IafAi.engage`; the radio menu's command): each AI jet
  addressed (the flight, the element or one wingman) that can fight fights the bandit the player's radar has locked
  (`ai_flights.gd engage_target`, `engage`) with the enemy fighters' leaves (§8.9); #4 stays on #3 when #3 engages too.
  Since each command names one bandit for the jets it addresses, the lead names a bandit per jet or element in turn
  (§8.11). Without a locked enemy aircraft, or with nothing left to shoot, each answers "unable", and a jet already
  engaging keeps its bandit. When the bandit is gone (destroyed, or out of the world: a drone at its end point) the
  engaging jets rejoin ("in position"); a rejoin or an RTB ends the engage too. On a ground target the command is an attack
  (§8.10). Until 22 November 2026 an engaging jet flew the steer loop at
  the target at 4 g and 280 m/s and fired whenever combat.gd's launch allowed (the next air-to-air station, its
  envelope, cone and fire gate), with no shot window, crank, dogfight or gun.

The calls' words (slice 3: said in the wingmen's voice, Kokoro `am_eric`, with Hebrew subtitles; every call with its
source in [../modern-iaf/docs/research/radio-terms.md](../modern-iaf/docs/research/radio-terms.md)). The IAF's own
radio words are not public. The Hebrew
writing on the subject uses נעילה for a lock[^hamichlol-rwr] and the verb מתחמק for evading SAMs[^mako-102]. The
English is NATO brevity[^brevity]:

| id | English | Hebrew subtitle | source |
|---|---|---|---|
| `spike` | "Kidon 1-2, spike" | "כידון 1-2, נעילה" | NATO SPIKE, "RWR indication of an air interceptor threat in track or launch"; Hebrew: נעילה[^hamichlol-rwr] |
| `mud` | "Kidon 1-2, mud" | "כידון 1-2, נעילה מהקרקע" (ours around נעילה) | NATO MUD, "RWR ground threat displayed with no launch indication" |
| `defending` | "Kidon 1-2, defending" | "כידון 1-2, בהתחמקות" (ours around מתחמק) | NATO DEFENDING, "in a defensive position and maneuvering with reference to a radar threat"; Hebrew: מתחמק[^mako-102] |
| `break_left` / `break_right` | "Kidon 1-3, break left!" | none found. Ours: "כידון 1-3, שבירה שמאלה" | NATO BREAK (direction), "an immediate maximum performance turn"; Hebrew open |
| `contact` | "Kidon 1-2, contact." | "כידון 1-2, מגע" (the user's pick, A113, 25 Nov 2026) | NATO CONTACT, "sensor information at the stated position"; Hebrew: no IAF source found |
| split | "Kidon 1, element 3–4, split." | none found. Ours: "כידון 1, זוג 3–4, פיצול" (the pair: זוג) | NATO SPLIT, "flight member is leaving formation to pursue a separate attack"; Hebrew open |
| regroup | "Kidon 1, element 3–4, rejoin." | "כידון 1, זוג 3–4, הצטרפות" | the four-ship's rejoin term (slice 3's research) |
| engage | "Kidon 1-2, engage my target." | none found. Ours: "כידון 1-2, תקיפת המטרה שלי" | NATO ENGAGE, "a fire control order used to direct or authorize units to fire on a designated target"; Hebrew open |
| cover | "Kidon 1-4, cover me." | none found. Ours around the press's חיפוי (fighters "שחיפו על החילוץ")[^mako-cover]: "כידון 1-4, חיפוי" | NATO COVER (to take a defensive, supporting posture; paraphrased)[^brevity]; Hebrew: חיפוי, second-hand |
| sort | "Kidon 1, sort." | none found. Ours around the sourced מטרה: "כידון 1, חלוקת מטרות" | NATO SORT, "assignment of responsibility within a GROUP"[^brevity]; Hebrew open |
| weapons free | "Kidon 1, weapons free." | "כידון 1, אש חופשית" (an F-15 crew's clearance on the radio, "רשאי אש חופשית": [radio-terms.md](../modern-iaf/docs/research/radio-terms.md)) | NATO WEAPONS FREE, "at targets not identified as FRIENDLY"[^brevity] |
| `targeted` | "Kidon 1-3, targeted." | none found. Ours around the sourced מטרה: "כידון 1-3, יש מטרה" | NATO TARGETED, "fighter has acquired assigned GROUP and has assumed responsibility for it"[^brevity]; Hebrew open |
| `engaged` | "Kidon 1-2, engaged!" | "כידון 1-2, בתקיפה" (the user's pick, A113, 25 Nov 2026, the root of תקיפה) | NATO ENGAGED (attacking the stated group; paraphrased)[^brevity]; Hebrew: no IAF source found |
| `fox_1` / `fox_2` / `fox_3` | "Kidon 1-2, Fox two!" | "כידון 1-2, שיגור" for all three (the launch verb **שיגור** an IAF base commander used on the F-35I's kill; no IAF word for the seeker type found: [radio-terms.md](../modern-iaf/docs/research/radio-terms.md)) | NATO FOX ONE / TWO / THREE (the launch of a semi-active radar, an infrared, an active radar missile)[^brevity] |
| `guns` | "Kidon 1-2, guns!" | none found. Ours: "כידון 1-2, תותח" | NATO GUNS (a gun engagement; paraphrased)[^brevity]; Hebrew open |
| `splash` | "Kidon 1-2, splash!" | "כידון 1-2, המטרה נפלה" (an F-35I pilot's words on his kill: [radio-terms.md](../modern-iaf/docs/research/radio-terms.md)) | NATO SPLASH (the target destroyed, air to air; paraphrased)[^brevity] |
| `winchester` | "Kidon 1-2, winchester." | none found. Ours: "כידון 1-2, אין חימוש" | NATO WINCHESTER (no ordnance left; paraphrased)[^brevity]; Hebrew open |

Later (outside this slice): a commit on the AWACS's call (the element turns to the contact); a memory of contacts already reported (each call is
answered once today); a mate's call of a lock it sees on its own RWR; the break's direction in the defender's own call.

### 8.9 Ours: the wingmen in the fight

The user, 22 Nov 2026: "Finish wingman in battle" (modern-iaf/docs/ai-plan.md F5, F13, K4). Our AI wingmen fight on
the enemy fighters' rules (§18): the same leaves, the same skill struct (`Skill::WINGMAN`, the Medium figures, §17),
the same host path in `ai_flights.gd`. The 1998 game sets none of it. Every figure is inferred. Whom they fight is the
lead's to say (§8.11).

- **The foe** (`Member::bandit`, `IafAi.state` "foe": the bandit's id), chosen each decision for a wingman in the air
  with the gear up, not sent home and with something left to shoot, from the hostile jets the host gives
  (`Flight::bandits`, `ai_flights.gd _bandits`: every live jet of the other side, each with an id that is never
  reused):
  - the bandit of the lead's order (engage, sort, weapons free: §8.11), once a sorted wingman is cleared to shoot; it
    knows it by the data link (the flight's picture), so it flies at it before its own radar or eyes have it;
  - else a bandit that attacks it: in its pilot's sight and in the dogfight's defensive geometry against it (behind
    its beam, its nose within 60° of the wingman, inside 5 km, `bfm::defensive`); a fight so begun goes on while the
    attacker stays within 1.5 times the dogfight's range (9 km). It knows that one only by its own radar and eyes;
  - else, told to cover the lead (the radio menu's "cover me", `command` "cover": defend the lead), a bandit that
    attacks the lead: its radar locked on the lead (the lead's RWR shows the lock within 1 km of the bandit) or on the
    lead's six (the same geometry), kept while it stays within 37 km (20 NM) of the lead.
  A foe it takes by itself (an attacker, the lead's attacker, a bandit it hunts) is called `engaged`. A rejoin or an
  RTB ends the order and the cover; the foe gone, it rejoins its slot ("in position"). With no order (§8.11 level a)
  it keeps its slot and fights only a bandit that attacks it. Until 23 November 2026 "cover me" fought the hostile jet
  nearest the flight once it came within 37 km of the lead, whether it attacked or not.
- **The fight:** the enemy fighters' leaves on the foe, in the enemy wingman's order: the shot (§18.1: its own radar
  holding the foe, inside the skill's share of the envelope for its reaction time), the dogfight inside 6 km of a foe
  in sight (§18.2: the BFM leaf, the gun with the skill's laying error), else the intercept (the collision course at
  300 m/s, the crank while its missile flies). Its station is the flight lead's position, so the intercept ends past
  150 km from the lead.
- **The defence in the fight** is the enemy fighters' (`fighter::evade`): a lock is called (`spike`, `mud`) and the
  attack goes on; a missile is defended by the tactics (Medium: the notch, the break against an infrared one) with
  chaff or flares at the launch's cue and within 6 s of its arrival (§8.8). Out of the fight a wingman defends as before (§8.8: the beam against a
  lock too).
- **Winchester:** with no missile or round left and none of its missiles flying, it calls `winchester`, the lead's
  order and the cover end and it rejoins; a later order is answered "unable".
- **The host** (`ai_flights.gd _step_flight_ai`, the enemy's path shared: `_bandits`, `_weapons_of`, `_fire`,
  `_radar_lock`, `_splash`): each frame the bandits with their velocity and jammer share, each wingman's
  weapons against its foe (`_pick_aa`: the missile whose envelope holds it), then its shot (combat.gd 300) or gun burst
  (370, then 300), called `fox_1`, `fox_2` or `fox_3` by the missile's guidance (combat.gd types 610, 570 / 580, 600)
  or `guns`; its radar's lock on the foe while it holds it (the foe's RWR). A foe shot down while a wingman's missile
  flew at it, or within 3 s of its burst, is that wingman's `splash` (`IafAi.splash(id)`, `ai_flights.gd _splash`); a
  kill by another is not called.
- **The jammer:** a Sufa wingman's jammer is on while its RWR shows a threat (a lock, a missile) or it defends
  (§15.6, `Flight::jams`).
- **The dev hook:** `ai_flights.gd flight_in_air(heading)` puts the player's flight's AI jets in the air behind the
  player's jet (put there first) and makes the flight's IafAi again; no mission starts a flight in the air.
- **Tests:** `cargo test -p iaf-ai --test wing_battle` (the four-ship of Sufas on the 6-DoF against MiG-29As:
  `engage_a_mig29_pair` the engage against a pair flying the enemy trees: the shots inside 36.2 km, the crank, a BFM
  move and the gun, splash and the rejoin; `no_order_holds_calls_contacts_and_fights_back` the break against a MiG
  behind #3; `cover_defends_the_lead`; `lock_called_winchester_and_rejoin`; the orders of §8.11), `--test four_ship
  engage_my_target_and_rejoin`; `modern-iaf/tests/test_wing_battle.gd` (headless: the four-ship in the air by the dev
  hook against a MiG-29A pair: engage, cover through the radio menu, a Fox call, both MiGs down, splash, the rejoin).

### 8.10 Ours: the air-to-ground attack

The user, 22 Nov 2026: "We don't have bomb release yet? So this is missing in ai, no?", then "Both for enemies and
wingman" (modern-iaf/docs/ai-plan.md F15, K15). Our wingmen and the enemy fighters attack a ground target
(`crates/iaf-ai/src/strike.rs`); the 1998 game sets none of it. Every figure is inferred unless it says otherwise.

- **The orders.** The lead's "engage my target" (the radio menu, record 47; record 99, Alt + E, to Kidon 1-2) on a
  ground target: `ai_flights.gd engage_target` engages the radar's locked aircraft, else attacks the player's ground
  target, picked by `strike::pick` (`IafAi.pick_ground`) among the hostile ground units alive the host lists: the
  radar's locked one, else the one nearest the SPI within 500 m, else the SPI itself (a point). The SPI
  (`player_weapons.gd spi`) is the radar's designated point, else the current steerpoint, else the EO camera's point
  on the ground; with none of them there is no SPI and each jet answers "unable" (the split too). `Flight::attack`
  (`IafAi.attack`): each AI jet addressed in the air with an air-to-ground weapon answers "ack" and takes it (the order on
  targets it had ends, §8.11); the others "unable". The flight has one ground target: a new one is every attacking
  jet's. An AI-led flight's own
  order is `Flight::strike` (`IafAi.strike`; the dev hook `ai_flights.gd enemy_strike(flight, target)`, the target an
  entity or a world point such as a base's runway): its lead takes it at once, then orders its wingmen.
- **A new order wins** (inferred: the lead's word is the order; no source found for a wingman finishing its
  release against it). Engage my target (an aircraft or a ground target, the same one too), cover me, sort, weapons
  free (§8.11), rejoin, RTB and the split end a jet's attack at once, its run too, and the jet answers "ack" and obeys: a ground target again
  starts its run over in its turn. A run broken off in its dive is pulled out by the autopilot's ground watch and the
  fly-up (§20). A release already started finishes (the host's ripple). A formation change
  leaves the attack on: the jet takes its new slot when it rejoins.
- **The turns.** The jets run in number order, each at least 20 s after the one before and never while another jet
  of the flight flies its run. Before its turn a jet keeps its slot (an AI lead its route or station); while the
  flight lead flies its own run its wingmen hold where they are (HoldPositionCL, mode 10), since their slot would take
  them down the lead's dive. #4 keeps its slot in the shape while #3 runs.
- **The low attack:** with the flight low (§20) a bomb or rocket run comes in on the terrain following and pops up
  into the dive (profile `pop`); a level run comes in low and climbs to its height; the egress goes out low.
- **The run, by the weapon** (`strike::pylon` on the pylons the host gives, `IafAi.set_ground_pylons`: the first
  pylon with stores left of a guided bomb, GPS or laser, or of a bomb or rockets, types 500, 510, 560):
  - a guided bomb (GPS, laser): a level run on the steer loop at the target at its height, at least 1,500 m above the
    target, released once the vacuum impact passes the target (at most 500 m beyond it, within 300 m of the track);
  - a bomb or rockets: on the steer loop at the target at least 2,500 m above it (climbing there at 20° on the BFM
    loop when lower); rolled in once the target lies 30° below the horizon within 30° of the nose (steeper than 35°,
    or not ahead: out on its track until the target is less than 20° below it, then back); the dive on the BFM loop
    at 4 g and 250 m/s (its speed brake), its flight path on the aim-off point (the target moved on by the drop of a
    store released along the line to it); released below 2,500 m with the vacuum impact within 400 m of the target
    (DiveBomb's own figure, `5d8590`); below 900 m without a release it pulls out and runs again.
  - The vacuum impact is the CCIP's fall (`iaf_avionics::bombs::fall_time`), the release within the release
    permission (`iaf_avionics::release::release_allowed`: load factor ≥ 0, bank ≤ 90°). A run with no release in
    300 s is given up ("unable"). A moving target (a convoy's vehicle) is led: the run and the release take it where
    it will be after the store's fall (§19.3).
- **The release** (`Order::release`, `IafAi.release`): the host selects the pylon `IafAi.ground_release` names
  (`strike::pylon`) and releases every store of that weapon (`strike::ripple`, at most 14) in one AI ripple 30 m apart (`combat.gd release` with the target given, then
  `_ripple_tick`: the target led by its velocity, the steered fall `player_weapons.gd drop_bomb`, a GPS bomb's or laser
  bomb's own guidance); a release started is reported (`IafAi.released`). The bursts damage what is near through the
  existing area damage.
- **The egress:** on along its track, pulling out and climbing at 20° on the BFM loop while it is below 1,500 m above
  the target or going down faster than 10 m/s, then level on the steer loop, until 8 km from the target; then back to
  its slot ("in position"), an enemy pair to its CAP, a based one home. The target destroyed or gone ends every attack.
- **The calls** (IAF Hebrew from the radio-terms research; voices.json): "in" / "נכנס" at the run-in, "release" /
  "חימוש שוחרר" ("bombs away" in English) at the release, "alpha" / "אלפא" ("shack", NATO's hit) when the target is
  destroyed, by the live jet that released last on it, also after its "done", once per target (`Flight::ground_hit`,
  the host's; inferred: that release is the one that hit), "done" / "ביצעתי" once 8 km clear, "unable" / "שלילי"
  for a run given up. The user, 25 Nov 2026 (A113): "Alpha is for exact hit, not for bomb release. bomb release, if
  can't find it, is "חימוש שוחרר"" (no IAF release call was found).
  The enemy's calls are not heard.
- **The MiG-29A's strike load:** the MiG-29 (9.12) carries "4 × FAB-500-M62 500kg general purpose bomb" (Wikipedia,
  "Mikoyan MiG-29", Specifications, read 23 Nov 2026); the sim has no FAB record, so the generic MK-83 (447 kg)
  stands in, on pylons B, C, G and H with the R-73s kept outboard (the pylons inferred). The dev hook `spawn(unit,
  at, heading, route, side, arm)` replaces pylons of the record's load.
- **Tried and dropped (23 Nov 2026):** the original's own bombing manoeuvres (§13.3) as the run: on the 6-DoF
  DiveBomb ran in at 357 m/s, overshot its dive and flew into the ground without a release; LevelBomb's release (the
  vacuum impact within twice its height of the target) let go 7 km short at 4,000 m, beyond what the AI stores'
  steered fall corrects. The original's pop-up (PopupRelease) runs in at 300 m above the terrain; the low attack is
  ours (§20).
- **Tests:** `cargo test -p iaf-ai --test strike` (on the 6-DoF: `four_ship_attacks_my_target` two dives and a level
  run in turn, each store within 50 m of the target, the calls, the rejoin; `mig29_pair_strikes_on_its_leads_order`
  the lead first, the wingman holding, both back on the CAP; `unable_target_gone_and_rejoin`;
  `a_new_order_ends_the_run`: in the dive a second attack, then cover me, safe throughout); `strike.rs`'s unit test
  `target_and_weapon` (the target and the pylon picked, the ripple's count); `modern-iaf/tests/test_ground_attack.gd`
  (headless: the four-ship with MK-82s through the radio menu on an enemy 64N6E2, destroyed; a second order to Kidon
  1-2 in its run, "ack" and the run flown again; a MiG-29A pair with MK-83s on its lead's order against a 64N6E2 of
  our side, destroyed).

### 8.11 Ours: the lead assigns targets

The user, 22 Nov 2026: "The leader (on our side) should assign targets to the other pair and to their wingman (no.
2). I am not sure how proactive they should be unless was commanded something like search and destroy or something,
wdyt?". He accepted four levels by the lead's command (`Tactic`, `crates/iaf-ai/src/flight.rs`; the sort's rule in
`crates/iaf-ai/src/sort.rs`). The 1998 game sets none of it. Every figure is inferred unless a footnote gives its
source.

- **The picture.** The host gives every live hostile jet as a bandit with its id (`Flight::bandits`). The flight's
  picture is the bandits any of its jets sees, the player's included: in its radar's reach and cone (74 km, ±60°;
  inside a jammer's burn-through, §15.6) or in its pilot's sight (§18.2). The jets share it by the data link.

| level | the lead's command | what the wingmen do |
|---|---|---|
| a | none | each keeps its slot, calls `contact` for a bandit its own radar finds first (once a bandit, for the flight), and fights only a bandit that attacks it (§8.9) |
| b | engage my target, to the flight, the element or one wingman | the jets addressed fight the bandit the lead's radar has locked (§8.8); #4 stays on #3. The lead names a bandit per jet: lock one, engage to Kidon 1-2; lock another, engage to the element |
| c | sort, to the flight | the picture shared out by the sort's rule (below): each element lead commits on its share and calls `targeted`; #2 and #4 answer `ack`, support their leads and hold their fire |
| d | weapons free, to the flight, the element or one wingman | the jets addressed hunt any bandit in an area round the SPI until a rejoin or joker fuel (below) |
| — | cover me, to the flight, the element or one wingman | defend the lead: fight a bandit that attacks the lead (§8.9) |

The latest order replaces the one before and ends a ground attack (§8.10); a rejoin or an RTB ends any. A jet that cannot fight (on the ground, sent
home, nothing left to shoot) answers "unable".

- **The sort's rule** (`sort::groups`, `sort::deal`). The bandits fall into groups: any contacts within 3 NM of each
  other (NATO GROUP)[^brevity]. The groups go to the elements (#1 and #2, #3 and #4), then each group's jets to its
  element's jets, by one rule seen along the line from the units to the groups: groups spread wider across that line
  than along it (the picture label AZIMUTH, "two GROUPS separated laterally"[^brevity]) are dealt by side, the left
  unit the left one, as a lead on the left of the formation takes the bandit on its side[^crenshaw]; groups one
  behind the other (RANGE, "separated in distance along the same line of bearing"[^brevity]) by range, the lead's
  element the near one (inferred: the sources name lead and trail groups, not who takes which). The flight lead sorts
  (sorting "should always be done by the flight leader"[^barton]). With one group both elements are on it, each on
  one of its jets, the wingman on its lead's; with more groups than elements the outer ones are taken (inferred).
- **The wingman's hold.** A wingman whose element lead is in the sort keeps its slot on that lead with its radar on its
  share (the bandit's RWR shows the lock) and holds its fire until its element lead shoots (#3's own shot; the
  player's missile launched at a bandit, `IafAi.fired`) or a threat is on it (a lock or a missile on its RWR, a bandit
  attacking it). Then it fights its share.
- **A share gone** (shot down, out of the world): the jet takes the nearest bandit of the picture that no other jet
  has, else the nearest; with none left it rejoins.
- **Weapons free** (`Flight::free(now, to, at)`, `IafAi.weapons_free`): the area is 37 km (20 NM) round the SPI (the radar's
  designated point, else the steerpoint, as the split's), which must be within 40 km of the lead or each answers
  "unable"; with no SPI the area is round the lead itself. Each jet addressed hunts the bandits of the picture inside it: the nearest one that no other jet has
  first, else the nearest; it drops a bandit gone or more than 46 km (1.25 times the radius) from the point; with
  none it circles the point at 1.5 g (the split's turn). A wingman whose element lead hunts too supports it: it takes
  the other jet of its lead's group by the sort's rule (its lead's own with a group of one) and fights it, weapons
  free. The hunt ends at joker fuel (bingo + 1,000 kg, the `joker` call) or on a rejoin. "Weapons free" is NATO's
  WEAPONS FREE ("at targets not identified as FRIENDLY")[^brevity]; "search and destroy" is not a brevity word.
- **AI-led flights** (`Flight::share`): an enemy pair, or any flight `enemy_flight` makes (either side). Its lead takes
  the jet of the network's vector (§18.1), else the bandit nearest the pair, and keeps it once committed while it
  lives. Once committed, each wingman takes its share of the lead's bandit's group by the same rule, never the lead's
  own while the group has another jet: two jets do not take one bandit while another flies free. Before the commit
  the wingman's bandit is the lead's. A pair vectored onto one raid sorts that raid; several pairs against several
  raids each take the track nearest their station (§18.1, open).
- **Keys and the menu.** The radio menu's flight pages carry Sort (to the flight) and Weapons free (to anyone) beside
  Engage my target and Cover me. Command 108 (the 1998 game's wingman commands) gives four of them keys in Modern
  IAF: record 99 (Alt + E) engage my target to Kidon 1-2 (§8.10), record 98 (Alt + W) sort, record 101 (Alt + P) cover
  me to Kidon 1-2, record 256 (`Alt + \`) weapons free to the flight (`radio.gd FLIGHT_KEYS`,
  [controls.md](controls.md)). Without an IafAi flight (the 1998 game) records 98, 99 and 101 reach the wingman's
  brain as before.
- **Calls:** `targeted` (an element lead on its share; NATO TARGETED), `ack`, `unable`, `contact`, `engaged` (a bandit
  it hunts or takes by itself). Their words: the table of §8.8.
- **Open:** the cover sees the lead's attacker by its lock or its place on the lead's six; a missile at the lead
  hides the lock behind it (the host's RWR gives the nearest threat), so a bandit that locks and fires at once is
  taken only when it sits on the lead's six. An enemy pair sorts the lead's group only: against two groups more than
  3 NM apart its wingman stays on the lead's bandit. A player's gun burst does not clear a holding #2 (only a missile
  launch does).
- **Measured** (`wing_battle.rs`, Medium): sorted against two MiG pairs 60 km ahead and 20 km apart, #3 shot at its
  share at 35.6 km 43 s later and #4 was cleared at once; a MiG pair committed on the four-ship took #1 and #4.
- **Tests:** `cargo test -p iaf-ai --lib sort` (the groups; the azimuth and range deals), `--test wing_battle`
  (`no_order_holds_calls_contacts_and_fights_back`, `engage_named_bandits`, `sort_by_azimuth_and_by_range`,
  `free_hunts_in_its_area_until_joker`, `cover_defends_the_lead`, `an_enemy_pair_sorts`);
  `modern-iaf/tests/test_target_assign.gd` (headless: the four-ship in the air by the dev hook against two MiG-29A
  pairs under each command: no order, each enemy pair's sort, engage per bandit, sort by the menu and by its key,
  weapons free by its key, the rejoin).

## 9. Airbase data (`iaf.ibx`, TowersManager `54eda0`)
`iaf.ibx` holds the geometry the AI uses to take off, land and taxi. It has ten sections, in record order: Ramon,
David, TelNof, Refidim, Inshas, Damescuss, Kuzeir, Bley, Ryak, Aman.

- Keys: `TowerLoc{X,Y,Z}`, `LineupLoc{X,Y,Z}`, `RunwayNumber` (degrees), `TaxiWayPtsTo` + `ToTaxiPt{X,Y,Hdg}i`
  (runway → hangars), `TaxiWayPtsFrom` + `FromTaxiPt…` (hangars → runway), `HangarsNum` + `HangarPt…`,
  `ToHangarTurnPt…`, `FromHangarTurnPt…`.
- Headings: `fmod(deg, 360)`, > 180 → −360; each is the direction of the leg leaving the point.
- Accessors: `551280` nearest base by Lineup (3-D), `5521c0` nearest hangar within 1000 m (−1 unchecked), `552190`
  first free hangar (0 when all are taken), `552240` / `552260` occupy / free.
- Port: `crates/iaf-flight/src/airbase.rs`.
- Data quirks (kept): Inshas `romHangarTurnPtHdg7` typo (→ 0), Kuzeir hangars 2 / 3 look swapped, Ryak's hangar order.

The TowersManager's ATC (`ACFT_*` calls, runway occupancy) serves the **player** only. AI aircraft use only the
geometry and the hangar flags; they also occupy the runway zones for the player's tower.

## 10. Radio reports (FlightController, `DAT_00699348`)
The FlightController posts one-shot radio / subtitle reports for friendly units with a callsign: waypoint passed
(WayPtSet, §7.2), airborne (TakeoffCL, §8.2), landed (StopPlaneCL, §8.3), crashed, ejected, kill calls, and the AWACS
contact calls. They change no AI behaviour. Trace and port: docs/radio.md §4, §5 (all built).

## 11. Flight model: AI cases
`ai = FUN_005c89f0() != 0` (the mode of §8.1). Ported in `crates/iaf-flight/src/aircraft.rs` (fields `ai_mode`,
`ai_since`, `ai_team`, `ai_level`, `ai_low_damage`). The rules are in flight-model.md §14.2, §14.3, §15.2, §15.6.3,
§15.8:

- AB: noAB = !HasAB || (ai && mode ∉ {7, 8}) in the air, = ai on the ground.
- No gear drag; wheel brake ×4 (v1.1); lift gate bypass, no belly friction.
- Stall unless Expert enemy; Rookie enemy g > 4.3 → 4 + 0.02 g²; no buffet.
- Throttle: every change counts, the afterburner lights at once, the engine starts only on a change.
- Crash immunity: `(mode 9 && fuel) || (mode active > 3.5 s && fuel && damage ≤ 0.1 && !(enemy && mode 0x11))`.

## 12. Port
Where each part of this document lives in our code:

- `crates/iaf-ai`: Modern IAF's flight AI over these loops (§8.7); `crates/iaf-godot/src/ai.rs`: `IafAi`.
- `crates/iaf-flight/src/autopilot.rs`: the control loops of §7–§8 (modes 1, 3, 7, 8, 9, 10, 0xb; ours 0x20) on an `Aircraft`,
  one tick per ring period. Outputs go through `set_controls` (stick y = −pull), `set_pivot` (motion 0x16),
  `replace_on_ground` (`5a4d40`) and `engine_off` (motion 0x19). `airbase.rs`: iaf.ibx. Tests:
  `crates/iaf-flight/tests/autopilot.rs`.
- `crates/iaf-flight/src/aircraft.rs`: the AI cases (§11), `ap_view` (the loops' inputs), the pivot turn.
- `crates/iaf-godot/src/flight.rs`: `set_ai`, `ap_setup` / `ap_set_route` / `ap_set_mode` / `ap_step` / `ap_set_leader`
  / `ap_waypoint_index`, `start_rule` (§7.1, also used for the player's start).
- `shared/ai/brain.gd`: the rule engine (§2–§6); combat measures and actions are hooks (`combat_hook`).
- `shared/ai/ai_flights.gd`: every brain-controlled aircraft (class 0x1c, transports class 3) with an FM type flies (one
  IafFlight, the aircraft model at the Present scale); `contacts()` for radar / RWR; ops 21 / 22 via
  `mission_runtime.gd`.
- Wingman commands (docs/radio.md §3): `radio.gd` sets the wingman brain's command / target; its bdb rules answer.
- MISSION-controlled flyers (every helicopter, the transports and jets of 113, 215, 216, 321): their scripts fly them
  (Path at the points' height above the ground, facing along the leg; Hover at their altitude; docs/mission-runtime.md
  §4).
  - Every fixed-wing one has brain −1 (no brain, §14).
  - The helicopters' brains 2 / 24 open with "select air target" (400), but class 2 gets no target sensor
    (`FUN_0043eef0`), so their "start combat" never has a target: they fire only by script (op 2, §14).
  - Ours attaches no brain to them, which gives the same outcome.
- Open: the combat parts listed as open in §13.3, network paths.
- Tests: `test_ai_flight.gd` (mission 221: 13 AI jets navigate, wingmen in formation, a take-off from Ramon).

## 13. Combat (partly built)

This section covers the AI jets' combat: sensors, target choice, weapons and the combat manoeuvres. The port lives
in `shared/ai/combat.gd` (AI jets) and `crates/iaf-flight/src/autopilot.rs` (manoeuvres).

**Built:**
- **The sensor** (kind 4: 10 slots, a scan every 2 s; the range by type, else 40 nm) and the selectors: **400 / 440**
  the best of the air-mode scan, **410** of the ground-mode scan (`FUN_004ac820` / `FUN_004ac900`), **420** the
  primary target (`FUN_004ac9e0`: brain+0x74, the formation slot's target, unless it is the jet itself; else none).
- **The stations:**
  - Loads: the mission's or the object's load; the Arming screen's load goes on both member slots of its flight
    (`FUN_004f0140`).
  - Their weight / drag act on the jet's flight model, and their models sit on its pylons (`stores.gd`, as the
    player's).
  - 330 / 340 make one cycle step to the next AA / AG station with rounds; 350 / 360 / 380 pick the wanted type; 370
    the gun (gate 5.0 s). Each sets the fire gate's interval (its action +0x8c).
  - Each one also sets the release quantity / interval from its action's 0x82 / 0x96 (W+0xe8 / ec / f0, clamped by
    `FUN_004562f0`; 330 / 340 `FUN_00452690`, the others `FUN_00452710`). Each is refused while a ripple or gun burst
    runs (W+0xac, set by `FUN_00454270`).
  - 310 / 320 release a flare / chaff through the player's release (busy 4 s first; the count drops only when a
    decoy left; the decoy rule acts on the missiles at the jet, docs/weapons.md §10).
- **300 Launch** as below: a missile through `launch_homing` (q 1.0: UNCERTAIN, the AI's q not traced); the gun fires
  a burst (`FUN_004579f0`) of W+0xe8 ticks: one round at once, then one every 0.2 s (`FUN_0045a540` →
  `FUN_00456d40`). Each tick uses one count, also when no round is free. The burst ends at 0 or when the gun is
  empty (`FUN_00457b40`). The bdb's 370 has 0x82 = 80, clamped to 14: about 2.6 s. No new burst starts while one
  runs (W+0xb0). A Launch that does not fire leaves its type
  gate free (brain.gd).
- **Conditions** 8, 10, 12, 14, 17, 20, 21, 26, 37 (§13.2); 27 invalid.
- **Locks** (`combat.gd` `on_lock`, shared with the player's radar):
  - A selector's pick unlocks the old target and locks the new one.
  - The AI sensor's override (`FUN_004aca60` / `FUN_004aca80`) passes only aircraft (class 0x1c) on to
    `FUN_004b0510` / `FUN_004b04d0`, and the player's RWR hears it.
  - An AI jet's brain+0x7c = the jet itself when free (original bug; Physics "fix_lock_threat": the owner); the
    unlock clears it.
  - The player's radar locks any class (its locks set a ground unit's brain+0x7c too).
- **430** (`FUN_00444a60`): with a sensor, B+0x70 = the nearest RWR emitter (`FUN_00451f70`) when the unit has a
  controller, else brain+0x7c. An AI unit has no controller, so it gets its "threat". Written directly (no on-lock).
- **ECM:**
  - Only a unit with a controller can jam (ctl+0x1b8), so only the player jams.
  - The sensor scan (`FUN_004af300`) sees a jamming target at any range (after the quiet-radar 0.7 R rule).
  - The owner's own jamming (0.8 R vs a jammer, else 0.5 R) applies only to the player's sensors (the HARM scan,
    harm.rs).
  - An AI jet's homing launch (`FUN_00454b70` with a shooter, 570 / 580 / 590 / 600 / 610) has q 1.0. Against a
    jamming target, a roll r = rand/32767 above 0.5 (0x600f04) makes q = max(1 − r, 0.1) (release.rs `ai_launch_q`).
- **Dogchase** (mode 0x11, below) with the target fed every frame (`ap_set_target`) and the nose-on flag.
- **All the combat manoeuvres** (autopilot.rs): Dogchase, Shandel / SplitS / Horizontal, Himmelman, TailClear,
  RunAway, Break90, LevelBomb, DiveBomb, PopupRelease, with the leaves Fly2TargetXyzSt, Fly2ImpactPt,
  PullGFullThrottle, Fly2PtXYZ.
- **Bombs, rockets and laser bombs from AI jets:** the AI ripple (docs/weapons.md §9.9; `player_weapons.release_store`
  per store).

Tests: tests/godot/test_ai_sensors.gd (ECM in the scan, condition 26, the locks, 430),
crates/iaf-flight/tests/autopilot.rs (Dogchase), tests/godot/test_ai_air_combat.gd.

Argument orders of `4440d0` were checked in the disassembly. The type gate is marked only when an action really
fires (a Launch that does not fire leaves type 1 free).

### 13.1 Actions (class by bdb 0xbe in `4b62b6`; exec = vtable +4 with the entity E; act+8 = 0xc8, +0xc = 0x82,
+0x10 = 0x96, +0x14 = 0x8c)
| code | exec | effect |
|---|---|---|
| 300 | 4440d0 | below |
| 310 / 320 | 444640 / 4446d0 | free gate and B+0x4c (B+0x50) == 0: busy 1, expiry now + 4.0; `4545e0(0x226 / 0x21c, 0, 1)` = one flare (station 11) / chaff (station 10), released like a store (`454b70`), count −1 |
| 330 / 340 | 444760 / 4447c0 | `W.452690(1 / 2, act+0xc, act+0x10)` (one `53b8b0` cycle step, rounds > 0); success: fire gate interval := act+0x14, mark |
| 350 / 360 / 380 | 444820 / 444880 / 444950 | `W.452710(code, act+0xc, act+0x10)`: refused while W+0xac; `4562f0` clamps the action's quantity (bdb 0x82) / interval (0x96) into W+0xe8 / 0xec and the period W+0xf0 (the AI ripple, docs/weapons.md §9.9); then wants 600 / 570 (580 also, v1.1) / 500, up to 10 `53b8b0` steps until that type with rounds |
| 370 | 4448e0 | gun: station 9 (`53bfb0(9)`), fire gate interval 5.0 s |
| 390 | 4449b0 | tank jettison: with a controller and tanks attached, `458760` (once); never gated (the code range suggests a weapon change, but it changes no weapon) |
| 400 / 410 / 420 | 444ac0 / 4449e0 / 444a20 | B+0x70 = selector `4ac820` / `4ac900` / `4ac9e0` (selectors not traced) |

**Fire gate** B+0x98 (`4d4100`, init `4d3fa0(0, 1.0, 0)` in `43eda0`): passes when now < last or now > next, then sets
next = now + interval. The default interval is 1.0 s; the weapon-change actions set act.0x8c: 330 → 15, 350 → 30,
360 → 20, 380 → 45, 370 → 5 s in default6_1.bdb.

**300 Launch** (`4440d0`):
```
gate(type 1) taken or no controller: return
S = the current station's weapon; T = B+0x70
inRange = S, T and min ≤ |Tp − P| ≤ max  (S motion vt+0x74 → out[2] min, out[0] max; 3-D distance)
ang = acos(clamp(nose · unit(Tp − P))) ; cone = 30° (0x6008f8), gun 565: 5° (0x6008fc)
single player, hostile to the player (network: level Normal): cone ×0.5 Rookie (0x600918), ×1.5 Expert (0x600914)
ang > cone: return; 580 and |relative bearing 44e770(T)| > 60° (0x60091c): return
if fire gate passes: W.452680(T) = 454270(T, 1); mark type 1
```
**Envelopes** (motion vt+0x74; condition 20 uses them too):
- IR chase class (`5624f0`): dist(v, t) = v·t + 0.5·absAcc·(1 − 4β)·t² (0x60ce90, 0x60ce94); s = |own V|.
  - No T: max = dist(s, burn), min = dist(s, 1).
  - With T: x = s − d̂·V_T, max = dist(x, burn − 2) (0x60ce78); off-boresight ≥ 90° → both 0; min = dist(s, tCO + 2);
    min > max → both 0.
  - Example: AIM-9L at 250 m/s: ≈ 1.5–6.7 km.
- Fixed weapons (`561700`, gun / rockets): max = _limitDist × 3.281 (0x60cdd8), min = 328.1 m (0x60ce10).
- Bombs (`5641c0`): ballistic throw, min 0 (partly read).
- Radar 600 / 610 on the chase envelope: UNCERTAIN.
- weapons.ibx AI fields: `_fireReleaseInterval` +0x48, `_maxNumInAir` +0x4c, `_reactionTime` +0x50 (callers not
  traced).

### 13.2 Conditions (resolved)
RWR = CTL+0x5b0 (10 entries × 0x24 from +0xc; +0 emitter, +0x14 launch flag; +0x174 locked; names UNCERTAIN).

| code | measure |
|---|---|
| 8 | no external tanks attached (`4593e0`: !(W+0xb8 == 0 && W+0xc0 != 0)) |
| 10 | relative bearing to T (deg, `44e770`) |
| 14 | closure d̂·(V_own − V_T) m/s |
| 19 | I am locked (RWR+0x174, invalid without a controller) |
| 20 | gun: distance ≤ _limitDist (4500) and, for an aircraft, its loop is Dogchase with the nose within NoseOnTargetAng 7° (0x67bad0); other weapons: the envelope with max ≠ 0 (bug: no station → max = vx, min = vz) |
| 21 | the selected store's round count (`456cd0`) |
| 26 | no T → invalid; T's brain+0x7c set (a sensor locked it) → 1; else T with a controller (the player) → its RWR list non-empty (`FUN_00452110`, RWR+0x174), else 0 |
| 27 | leader locked |
| 37 | leader's target == mine (no leader target: 1 but invalid) |
| 38 | T == threat (nearest RWR emitter, else B+0x7c) |
| 39 | any RWR entry's launch flag |

### 13.3 Combat manoeuvres (setMode at 5b155c: cancel, Init2(now, fm, T, 0, no end condition), start, root timer
0.5 s; full military throttle = `5ca420(100)`, no afterburner)
| mode | mgr | vtable | Run / Init2 |
|---|---|---|---|
| 0xd Shandel / 0xf SplitS / 0x10 Horizontal | +0x5b18 / +0x5838 / +0x5df8 | 0x6132d0 / 0x6132b8 / 0x6132e8 | 5d1100 / 5d0eb0 (kinds 0x17 / 0x16 / 0x18) |
| 0xe Himmelman | +0x48 | 0x612cc8 | 5ce8c0 / 5ce5a0 |
| 0x11 Dogchase | +0x1de8 | 0x612c90 | 5cea30 / 5c91d0 |
| 0x12 RunAway | +0x5078 | 0x612e40 | 5dd4a0 / 5dd330 |
| 0x13 Break90 | +0x5268 | 0x612d48 | 5da7a0 / 5da210 |
| 0x14 TailClear | +0x64a8 | 0x612d90 | 5dac30 / 5daa80 |
| 0x16 LevelBomb / 0x17 DiveBomb | +0x49d0 / +0x4ca8 | 0x612cf8 / 0x612d30 | 5d9290 / 5d90b0, 5d8590 / 5d83c0 |
| 0x18 PopupRelease | +0x1180 | 0x612ca8 | 5cc0f0 / 5ccbd0 |

- **Dogchase** (5cea30, 0.5 s, never ends):
  - Aim = T (dist < 1000 m, 0x6130f8), else T − DistanceBehindTarget·F̂_T. LookAt `5ca7d0` case 1 (sets the nose-on
    flag).
  - Speed: dist > 1000: |V_T| + 0.027762795·dist (0x61310c); V_T·d ≤ 0: 0; else a = −51.472221/(D − 1854),
    b = −D·a, vt = (|V_T| + a·dist + b)·(V_T·V)/(|V|·|V_T|). max(vt, 0) → speed law; watch-ground.
  - D = bd.ibx [Autopilot] DistanceBehindTarget (exe 500, v1.1 bdgen.dat 300). The v1.1 data also has DogChaseRollK
    4, LookAtBeta 1.0, ChangeHeadBeta 2.5, ChangeRollCone 10, NoChangeRollCone 1.75.
- **Fly2TargetXyzSt** (0x612d10, 5d9740): LookAt(case +0xf0) on its point; throttle = speed law(+0xe8) or +0xec or
  0.75; watch-ground unless case 4.
- **RunAway** (5dd330 / 5dd4a0). It picks a state by the horizontal distance:
  - \> 18540 m → state 1: run directly away (P − 1854 km·N.xy, z ≥ T.z + 914.4). Its speed 800 is dead, because the
    throttle is overridden.
  - \> 9270 m, after 60 s, or the target's nose more than 60° off me → state 2: fly to −1854000·F_T (absolute: quirk).
  - Else state 3: ATTACK the target + 30 m each axis (throttle 1.0).
  - The throttle, posted last, overrides all: 1.0 for 30 s, then 0.75.
  - It never ends. The states flip every tick at the borders (1 ↔ 2 beyond 18540 m, 2 ↔ 3 inside 9270 m: quirk).
- **Break90** (5da210 / 5da7a0), in order:
  1. Fly2TargetXyzSt(B = P + 185400·sgn·(−F_T.y, F_T.x), my height) until within 10° (the angle includes the pitch);
  2. LevelWingsPitch0Accel 180 until |roll| < 10°;
  3. PullGFullThrottle (`5da080`: the stick for 7 g, wings level, throttle 1.0, no ground watch) until pitch > 45°;
  4. KeepOrientation until z > +0x5b0 + 1066.8 (+0x5b0 is never written, so this is an absolute 1066.8 m: quirk);
  5. Fly2TargetXyzSt(A = 1854 km along the entry nose) until within 10°;
  6. LevelWingsPitch0Accel 180 forever.

  sgn = sign(Fh.x·R_T.x + Fh.y·F_T.x): a local→world transform applied to a world vector (original bug, kept).
- **LevelBomb** (5d9290): Fly2TargetXyzSt at 257.5 m/s to (T.x, T.y, max(z, T.z + 609.6)); release `440440` (fire
  gate, then the selected weapon as 300) when the vacuum impact `45ed10` is within 2·(z − T.z) of T; then
  LevelWingsPitch0Accel 180 m/s.
- **PopupRelease** (5ccbd0, base Run 5cc0f0), in order:
  1. Fly2WayPt to Q = me + 3708 m right of the line to T + (D − 4635) along it, at terrain + 300 (ETA D/308.4 used as
     an absolute time: quirk);
  2. PullGFullThrottle until |pitch − 45°| starts growing (`5da190`; its stored value is never reset between popups:
     quirk);
  3. KeepOrientation to T.z + 1828.8;
  4. Fly2PtXYZ (`5d9580`: LookAt case 0, throttle only from the ground watch) to U = T + 500 up until within 15° (cos
     0.966, 3-D);
  5. KeepAttitude2Pt on U with the release (`440440`) when the impact is within 600 m of U (3-D: only ~332 m
     horizontally of T) or I am within 1000 m of U (both can fire in one tick);
  6. ChangeAlt T.z + 1000, which never ends (no condition), so LevelWingsPitch0Accel is never reached.
- Not traced: Shandel / SplitS / Horizontal / Himmelman / TailClear / DiveBomb steps, LookAt cases 2 and 4, the AI's
  fire per weapon (`454270(T, 1)`: gun burst / aim, missile q, bomb ripple), the target selectors, the decoy logic,
  B+0x7c writers, the RWR internals, the hit reactions `44d590` / `43ff50`.

## 14. Ground defences, RWR, script ops 1 / 2

This section covers how ground units (guns, SAM sites, armed vehicles) find targets and fire, the RWR, and the
script fire ops. All of it is traced and built: the ground units' fire in `shared/ai/combat.gd`, the player's RWR in
docs/rwr.md, the decoys and their effect on missiles in docs/weapons.md §10.

**Port** (`shared/ai/combat.gd`):
- Every armed unit other than the aircraft has a weapon handler (its first valid station), which script op 2 fires
  (below).
- A unit of a sensor class with a brain, brain or mission controlled (a mission-controlled unit's brain runs, §3),
  also gets:
  - its brain (no manoeuvres);
  - the sensor: both modes' classes scanned every 6 s; the selector filters (400 / 440 air, 410 ground, 420 either)
    and takes the best score (UNCERTAIN while the selectors are untraced).
    Its reach is the type code's (`sensor_nm`, below); a unit of Modern IAF with its own `radar_km` (the bdb row's
    unhexed key, modern-iaf/docs/data-formats.md §3) takes that instead. The original's units have no such key.
  - start / stop combat. The RWR lock comes with the selector's pick: 400 / 440 / 420 lock the player's RWR when they
    pick the player and unlock it when they leave it (FUN_004aca60 / FUN_004aca80). 550 only starts the fire timer.
    A unit with no weapon logs "Entity with no weapon handler" and does not engage;
  - the fire tick:
    - **Class 0x17**: 565 AAA (above) and 560 rockets (the player's rocket motion: no hit sphere, they burst at the
      lead point or the ground; range the full `_limitDist`).
    - **Class 0x18** (SAMs 620 / 630, and 570 / 580 / 610 on some vehicles): fire only inside the missile's DLZ
      (`FUN_005624f0`), taken from the unit's pose with zero speed. The nose is the unit's heading, so **a site never
      fires at a target 90° or more off its heading** (original quirk). One missile in the air (`_maxNumInAir` 1),
      q 1.0.
    - The launch attitude (`FUN_004ab810`) reads the part angles and leaves them as they are (their only writer is
      script motion op 11, `FUN_005c3ee0`): types 290–340 use the launcher's heading (hull + part +0x14) pitched
      toward the target; tanks (250) the turret's heading (part +0xc; UNCERTAIN: hull + turret, Ghidra's stack
      aliasing hides the hull term); others the hull's level heading.
    - A missile leaves at 100.1 m/s (_debugParam000, the launcher being slower than 5 m/s). The flight, RWR launch flag, blast and look are the
      player's homing weapons' (`player_weapons.gd` `launch_homing`).
- **Release order** (`FUN_004ab810`):
  1. the truce (taken even when the shot is then skipped);
  2. a busy pool object;
  3. the terrain line of sight (both ends +3 m: −1.5 subtracted twice).

  Every round and missile starts at (0, 4, 1) in the launch attitude (`FUN_004ab7b0`: 4 m ahead, 1 m up), with the
  launcher's velocity (`FUN_004d5d10`). Every release of a non-aircraft unit first clears its part record's +8 (@4aba06), so the Missile
  part (the Scud's) disappears.
- **Script op 2** (`script_fire`): the weapon at the target's position now (no lead, no range, no DLZ), q 1.0, then the
  release.
  - A unit not in combat skips the truce (the handler's SAFE flag +0x28, "Fired a weapon by the Scenario";
    UNCERTAIN: its initial value).
  - The entry's **0x852** (script +0x3c) picks the release flag (the weapon's +0x100, `FUN_004d5d10`):
    - ≠ 0 → 2, a **kill shot**: the blast, then the target (alive or going down) explodes, level 5; the player is
      spared when shielded (`FUN_004d6130` @4d673a, `FUN_0058a350`);
    - 0 → flag 0, the editor's **"Miss …"** shot: it flies and bursts, but `FUN_004d6130` applies no blast (@4d6597).
  - The brain's fire and op 1 use flag 1 (the blast).
  - The missions name them so: "Miss Merkava 1" / "Kill Merkava 1" (112), "Miss Hermon Post" (231), "miss satil1" /
    "hit satil 2" (233). So 112's and 231's opening barrages spare the units the player must protect.
  - **Helicopters** (class 2) have no sensor (`FUN_0043eef0`: classes 5 / 9, 8, 10 / 0x10, 0x1c only), so they fire
    only this way (MI-24s: 580, aimed first by motion op 11).
- **Brain −1**: no brain (§3), so an armed unit fires only by script (op 1 / 2).
  - Traced: the loader keeps 0x2da as is, and `FUN_004b815f` attaches only a brain found by that id. The bdb Objects
    default brain `0x532` is used only by the Mission Creator (`FUN_0058e530`).
  - So 112's T-55s (brain −1) do not engage the Merkavas on their own.
  - 322's SA-2 launchers and radar (brain −1) stay silent and never lock, so the player's RWR never lists them (its
    "Shade hawk" launchers have brain 11 and lock the player). The HARM's own scan lists the "RADARSA2 radar"; Extras
    "HARM targets: Real" lists it too (docs/weapons.md §11.5).

**Second station**: the handler loads up to two (`FUN_004b7ea3` / `FUN_004aa830`) but fires the one at its index +0x34.
Start combat sets that index to 0 (`FUN_004ac120`; the previous value is kept in +0x38 and put back by stop combat),
and nothing else writes it (the ctor's 0). So in the original too, the second station never fires. Turrets / launchers
turn only by script motion op 11 (mission_runtime.gd `_yaw_to_target`, drawn: the vehicle models keep their `.xfr`
frames, docs/part-animation.md §2.1).

Not reproduced: the ring pool's 3–4 steps per gun shot. Tests: tests/godot/test_ground_fire.gd (313 AAA and SA-3
incl. the launch along the launcher's heading, 322 rockets), test_yaw_to_target.gd (parts), test_ai_sensors.gd (ECM,
locks, 430, condition 26).

**The original's code, step by step:**

- **Spawn** (`FUN_004b7634` → `FUN_004b7ad6`): an entity with record +0x3c ≠ 0 → vehicle `FUN_0059bb00` with a
  MWeaponHandler `FUN_004aa650` (entity[9], vtable 0x603200). Non-aircraft units get only their first 2 valid weapon
  stations (`FUN_004b7ea3`), each a ring pool of `_maxNumInAir` objects (`FUN_004d8570` / `FUN_004d8760`). Weapon
  class by sub type (`FUN_004bb5d4`): 0x16 500 / 510; 0x17 fixed 540 / 550 / 560 / 565; 0x18 homing 570–635; 0x19
  640 / 650; 0x1a 660.
- **Target sensor** (brain+0x40, selector `FUN_004ac5f0`, vtable 0x603298) by class:
  - 5 / 9 kind 1, 8 kind 3, 10 / 0x10 kind 2 (5 slots, period 6 s), 0x1c kind 4 (10 slots, 2 s). Other classes (6,
    11 ground radar, 15 boat) have none: they never target or fire.
  - Scan `FUN_004af300`: R = nm(type) × 1854 (0x603390; `FUN_004acae0`: 250–280 → 3, 290 / 310 / 330 / 340 → 20,
    300 / 320 / 370–390 → 10, 350 / 360 AAA → 5, else 40).
  - Air mode (400, `FUN_004ac820`) classes {0x1c, 3, 2, 1}; ground mode (410, `FUN_004ac900`) {10, 8, 9, 0xb, 0xd,
    0x1d, 0x1e, 5, 6, 0xf, 0x10}.
  - The player is seen only within 0.7·R while its radar is OFF / STBY (ctl+0xb4 ∈ {0, 1}). A target jamming (its
    controller's ctl+0x1b8: only the player) is seen at any range. A sensing unit jamming (only the player's own
    sensors): 0.8R vs a jamming target, else 0.5R.
  - Accept (`FUN_004ac740`): hostile (`FUN_004a4cf0`) and terrain line of sight (`FUN_004020d0`, both ends +1.5 m).
    Score 100 / dist, best 5 kept (`FUN_004b08e0`), full rescan at most every 5.0 s.
- **Start combat** 550 (`FUN_00444b20`): engaged, `FUN_004aa900(0)` → `FUN_004ac120(1)`: fire timer, first shot at
  now + `_reactionTime`, then every `_fireReleaseInterval`, slot 0; the target locked on its RWR. 560: timer off.
- **Fire tick** (`FUN_004ab110`): T = brain+0x70 dead → timer stops.
  - Class 0x17 (gun / rockets): range = `_limitDist` (×0.5 for 565 → 2250 m), t = |T − P| / `_limitVel`,
    aim = T + V_T·t + ½A_T·t² (lead).
  - Class 0x18 (missiles / SAMs): fire within the chase envelope (§13.1).
  - Release `FUN_004ab810`: the launch attitude from the turret / launcher part angles (above). A **global truce**
    covers all handlers (DAT_008321d0..d8): after each shot no other ground shot for 0.1 + rand·0.9 s ("Entities in
    truce"). Busy pool object → skipped; terrain LOS +1.5 m; fire `FUN_004d7630` → `FUN_005604a0(T)` (single
    candidate).
  - 565 / 660 play SFX_ENTITY_FIRED_WEAPON (SFX = sound effect). It is a cyclic row: ours keeps one loop per unit
    while it fires again within two fire intervals (`combat.gd` `fire_sound`; UNCERTAIN: the original's stop).
  - Pool quirk: the ring advances 3–4 times per shot.
- **AAA round**: bdb 50 "AAA" (565, power 15, radius 30), the player's gun round model aimed at the lead point.
  - Hit sphere 25 m against T only (50 m with Easy aiming, original quirk: the option also helps the enemy).
  - At the end time it bursts in the air (flak, area blast).
  - Mission 313's ZSUs: brain 'mission' / 'zsu' start within 4000 m, shots only inside 2250 m, first 10 s later, then
    every 0.5 s (truce permitting).
- **SAMs**: class 8 launchers carry SA2 / 3 / 5 / 6 / 8 / Hawk (630), class 9 SA13 (620). No link between a site's
  radar and its launchers was found: each launcher fires on its own sensor.

  | weapon | absAcc | burn | tCO | in the air | interval | reaction |
  |---|---|---|---|---|---|---|
  | 000630 | 70 | 20 + 15 + 10 | 3 | 1 | 30 s | 20 s |
  | 000620 | 100 | 5 + 10 + 5 | | | 10 s | 1 s |

  Both: spiral 1000 / β 0.08, chase 2, highAngleTurn (an overshoot ends the flight only within 1000 m). Ground launch
  at 100.1 m/s along the nose, q = 1.0, the IR missile engine (docs/weapons.md §5.3): no illumination needed.
- **Decoys** (`FUN_00454b70` at the release, the releasing jet's RWR missile list): see docs/weapons.md §10.
- **RWR** (ctl+0x5b0, ctor `FUN_004515d0`): full trace and the port in docs/rwr.md.
  - 10 slots × 0x24 (+0 unit, +4 threat type = bdb type code, +8 position, +0x14 launch flag, +0x18 missiles in
    flight, +0x1c drop pending, +0x20 active), count +0x174, missile list +0x178.
  - Emitter test `FUN_004521c0`: ≤ 37080 m (0x600d14); classes 8, 9, 10, 5, 16 always; others only > 120° off the
    nose or after a launch.
  - Add `FUN_0044deb0` when a sensor locks (start combat, 420, retargets, a radar in STT). Damage flag 14 blocks it;
    types 220 / 250 / 270 are ignored; a full list refuses.
  - A new active entry lights lamp 4 'sam' (classes 8, 9, 10, 5, 16) or 3 'ai' (this corrects docs/cockpit.md: any
    active entry lights it, a guiding missile included) and plays WRN_NEW_GUY 0x18002000 (≤ once per 1.0 s,
    ctl+0x860).
  - Launch `FUN_0044e160` (every class-0x18 missile): launch flag; WRN_MISSILE_LAUNCH 0x18003000 loops until no flag
    is left (`FUN_00451e30`); Betty "Missile" 0x2c002000 on every launch (ctl+0x964).
  - Every 2.0 s positions are refreshed; active = emitter test or launch flag.
  - Display `FUN_00531470`: active entries; launch-flag ones blink (300 ms); distance clamped 37060 m. Original bug:
    slots are not compacted and only the first `count` are copied (`FUN_00446200`).
  - There is no separate lock tone. Damage 14 / 19 / 21 clear the list. brain+0x7c is written with the target itself
    (original bug).
- **Script op 2** (0x5c42f0 → `FUN_004aae40(handler, key, p3)`): ignored when handler+0x48 == 2. The target comes from
  the key (`FUN_00439b40`); {target pose, target, q 1.0} → `FUN_004ab810(…, p3 ? 2 : 0)` (turret / truce / LOS /
  fire). With handler+0x28 == 1 the truce is skipped ("Fired a weapon by the Scenario"). It uses the current slot, with
  no range check.
- **Op 1** (0x5c4160 → `FUN_004aad10`): `FUN_004ab810(pose, 1)` at a point. UNCERTAIN: the trigger fields → args.

## 15. Modern IAF's air-defence sites (ours)

Modern IAF's sites run on the Rust site (`crates/iaf-ai/src/site.rs`, gdext `IafSite`), not on the 1998 brain; the 1998
game keeps §14 as it is. No mission places a site yet. `shared/ai/air_defence.gd` is the dev and test hook:
`AirDefence.of(host).spawn(kind, pos, heading, alternates)` (kind `s300`, `tor`, `zsu`, or a shoulder-fired team
`strela` or `igla`, §15.8) adds each part as a mission entity (`ad:N`) with its model or stand-in shape (§15.4) and arms
each firing part as a combat.gd unit without a brain (`add_ground_unit`). The test is
`modern-iaf/tests/test_enemy_sites.gd`; the Rust tests are `crates/iaf-ai/tests/sites.rs`. The procedure and its
sources: [modern-iaf/docs/research/enemies.md](../modern-iaf/docs/research/enemies.md) §2.3–§2.6, §3.1 and §5.2. Timings
no source gives are inferred, each with a comment in `site.rs`.

### 15.1 The procedure

| | S-300PMU-2 | Tor-M1 | ZSU-23-4 |
|---|---|---|---|
| parts | 96L6E search radar, 30N6E2 track radar, four 5P85TE2 launchers of four rounds | one vehicle: search and track radars, eight rounds | one vehicle: the RPK-2 radar, an optical sight, 2,000 rounds |
| radar reach against 5 m² | search 300 km[^mis-96l6e], track 200 km (the record's, held) | search 25 km, track 20 km | 20 km; the sight 5 km (inferred) |
| targets at once | 6 | 2 | 1 (stays on one target) |
| per target | 2 missiles, 3 s apart across the battery | 2 missiles, 4 s apart | bursts of 10 rounds (2–3 per barrel × 4), 3 s apart (inferred) |
| acquisition (inferred) | 5 s | 3 s | 2 s |
| moving | searches and fires only in place; march order 5 min (inferred), set-up 5 min after the halt | searches and tracks on the move; stops 5 s (inferred) to fire | searches and fires on the move |
| RWR type code | 310 | 330 | 360 |

The state machine (one fixed procedure needs no behaviour tree): the site is Ready, silent or searching by its EMCON.
Each channel takes one target through Acquire (the track radar on, no lock yet), Track (a lock on the RWR, combat.gd
`on_lock` from the track radar), the launches inside the envelope, and Guide (the track held while its missiles fly).
When they have ended, the crew assesses: a target still alive is engaged again (shoot-look-shoot). A track lost (the
target gone, out of reach or masked) frees its channel.
- **The pick:** the most dangerous target first, measured by its time to arrive at the site (inferred).
- **EMCON** (§5.2, the caller's choice per site): `radiate` searches all the time; `silent` never radiates (the ZSU
  lays optically); `cue` keeps the radars off until a cued target (the caller's `cued`, the network's track) is
  seconds from the envelope (its edge plus the acquisition time at its closing speed), then the track radar comes on
  to acquire it and fire (§11-134). By the crew's skill (§17): a High crew's search radar, autonomous under
  `radiate` and engaging nothing, radiates 20 s in each minute (the Serbian SAM crews of 1999 "would periodically
  emit with their radars for 20 seconds and then shut down the radars"[^lambeth-sead]; the minute, each site's starting at its own time, is inferred); its
  tracks keep their radar on.
- **Relocation** (§11-121): after an engagement, 20 s without a track at Medium (60 s Low, 5 s High: shoot and scoot,
  a capable system moving "as often as every 10 minutes", §11-121, the Serbian crews "dispersed and
  mobile"[^lambeth-sead]; the times inferred), the site takes its march order
  (radars off), drives to its next position (the placed one and its alternates in turn), sets up and searches
  again. Its route is a convoy's (§19.2, `convoy::Route`): `IafSite.tick` asks the road layer for the road route
  between the road points nearest the two positions and takes it as a convoy does, else straight across country; it
  drives at its road speed on the road and 0.6 of it across country (inferred). `IafSite.relocate(now)` gives the
  march order at once (a dev hook). A single site moves whole (inferred from §11-119's one third), its layout kept, each vehicle facing its course;
  a destroyed part stays where it is.
- **Parts destroyed** (a part hit fatally, state 3 or more): no search radar, no search; no track radar, no
  engagement; a launcher's rounds go with it. With no rounds left the site drops its tracks once its missiles have
  ended, and moves on after the quiet time.
- **The Tor's duty limits:** 10 min radiating forces 10 min off; after three engagements (salvos fired, whatever
  became of the target) an hour off, in which a cued target in reach switches it on once for one minute (its salvos
  there count toward no further break).
- **The fire** goes through combat.gd: a missile through `_release` (the launcher turned to the target, no truce, the
  site counting its own missiles in the air instead of the 1998 one per unit; a launch the release refuses gives its
  round back and counts neither toward the relocation nor toward the Tor's break), the gun's rounds through `fire_at`
  (the fire tick's lead) one per `GUN_PERIOD`. The launch envelope is `Missile.dlz` from the first launcher toward
  the target, inside its missile's published envelope; the gun's is its range. Each SAM site fires its own missile
  (2026-11-25, `iaf_ai::site` `SiteMissile`, `IafSite.missile`): the S-300 the 48N6E2, the Tor the 9M331, as the
  shoulder-fired teams (§15.8), on the physical missile (docs/real-weapons.md §2.1: motor, body, g limit, seeker's
  rejection; the 48N6E2 lofts, §2.4), drawn with the AIM-120's model as a radar SAM (type 630: the RWR hears its
  launch, chaff and the jammer act on it, docs/real-weapons.md §2.3, §2.6); its proximity fuze its warhead's blast
  (§2.5). The ZSU's rounds stand in as the 20 mm's. Until 25 November the SAMs fired the AIM-120's record. The
  draft records of modern-iaf/docs/threat-records.md stay drafts: the sites' missiles are defined with the sites.
- **The RWR and the HARM:** each track is a lock. A site's radar is on the RWR's search list (docs/rwr.md §7) and in
  the HARM sensor's scan only while it radiates (the part's `radiating`), heard to the radar's reach (`radar_km`).
  Modern IAF has the search list on.

### 15.2 Radar cross-section

A radar's range against a jet: R = reach × (σ / 5 m²)^¼ (the radar equation; each reach is taken against a 5 m²
fighter, inferred). The jet's σ (m²) from its definition's `rcs` (docs/adding-a-plane.md):
σ = front · max(cos θ, 0)² + side · sin² θ + rear · max(−cos θ, 0)², θ the angle between its nose and the line to the
radar (the blend inferred; an aircraft's largest returns come from the side[^aerospaceweb]), plus `bays_open_m2` while
the player's bay doors are open (`player_weapons.gd bay_open`) and `store_m2` for each loaded external station
(`stores.gd external`; bay stations add none).

| jet | front | side | rear | bays open | per store | source |
|---|---|---|---|---|---|---|
| F-16 (the Barak; the Sufa by its base) | 1.2 | 6 | 3 | — | 0.5 | front: the F-16's average with Have Glass[^ni-f16]; the rest inferred |
| F-35I Adir | 0.0015 | 0.05 | 0.01 | 1.0 | 0.5 | front: the low end of 0.0015–0.005[^migflug]; the rest inferred (external stores "drastically increase" it[^ni-beast]) |
| any other (1998 types, drones) | 5 | 25 | 12.5 | — | 0.5 | inferred (`site::FIGHTER`) |

The AI fighters' radar takes the same σ (§18.1). Public figures are rough and disputed. Head on, the 96L6E's 300 km gives about 210 km against an F-16, 39 km against
a clean Adir and 200 km against an Adir with its bays open.

### 15.3 Terrain and the radar horizon

A radar sees a jet only over the terrain and the earth's curvature: the radar's `line_of_sight` (§14) with the ground
lifted by the bulge s · (L − s) / (2 · k · R) at each sample, k = 4/3 (the standard refraction, inferred), R = 6,371
km; sea level where the terrain has none. The terrain is the mission ground (roofs and trees included). The antennas
(inferred): the 96L6E 6 m, the 30N6E2 8 m (25 m on its 40V6M tower, `set_mast`), the Tor 5 m, the ZSU 3.5 m. The
site tests sight only at its decision tick (0.5 s) and only for jets inside the range for their σ.

Ground clutter (`site.rs` `Spec::reject`, `Spec::floor`):

| site | rule | source |
|---|---|---|
| Tor-M1 | both radars are pulse-Doppler[^w-tor-pd]: they lose a jet slower than 30 m/s along the line of sight (one on the beam, a hovering one) | a pulse-Doppler radar detects nothing below its rejection speed, set from 20 to 160 km/h[^w-pd]; the Tor's 30 m/s inferred |
| ZSU-23-4 | its radar loses a jet lower than 60 m above the ground; the optical sight still lays on it within 5 km | "many false returns (ground clutter) under 60 m (200 ft) of altitude"[^w-zsu] |
| S-300PMU-2 | both radars lose a jet slower than 30 m/s along the line of sight (one on the beam) | the 96L6E's Doppler speeds in its all-altitude and low-altitude modes are "between ±30 and ±1200 m/s"[^mis-96l6e]; the 30N6E2's processing is not published: taken as the 96L6E's (inferred) |

The wingmen's beam (§8.8, the reactions) turns the threat 90° off the nose: against the Tor it breaks the track.

### 15.4 Models and stand-in shapes

Each part is drawn with its model when `Gltf.UNITS` (`shared/util/gltf.gd`) lists its placed name, else with a
stand-in shape of ours (`air_defence.gd _shape`). The models are CC BY 4.0 Sketchfab models made true size, nose
along −Z, by `tools/enemy_models/convert.py` (docs/credits.md § Model credits):

| part | model | real size it is scaled to |
|---|---|---|
| 5P85TE2 launcher | `s300_5p85`: a self-propelled 5P85 on the MAZ-543 with 9M83 canisters lowered, standing in for the towed TE2 (inferred) | the MAZ-543's width, 3.05 m[^ru-maz543] |
| 30N6E2 track radar on its tower (`spawn(…, mast = true)`) | `radar_30n6e`: the 30N6E on the 40V6M tower | 25 m high, the site's `MAST` (inferred from the 40V6M's 24 m[^apa-s300]) |
| 9A331 Tor | `tor_m1`: the Tor-M1 in its rest pose | 7.5 m long[^w-tor-pd] |
| ZSU-23-4 | `zsu23_4`: a low-poly ZSU-23-4 | 6.535 m long[^w-zsu]; its width and height come out about 8 % over the real ones |
| 54K6E2 command post (§15.5) | `ural4320`: a Ural-4320 with its canvas cover, standing in for the post's container on a Ural-532361 (inferred) | 7.366 m long[^w-ural] |

The two search radars and the 30N6E2 on its truck are our own low-poly radars (no openly licensed model exists: the
64N6E2 models found are taken from War Thunder, excluded) on a Sketchfab MAZ-543 chassis, built by
`tools/enemy_models/radars.py` (Blender, run once by hand, committed). The radars are boxes and prisms in plain
colours, the olive of the other enemy models. The chassis is "MAZ-543 Uragan 9P117" (CC BY 4.0, docs/credits.md
§ Model credits), the user's pick of 24 November 2026: the script keeps its cabs, wheels, frame and side lockers and
cuts off the R-17 missile, its erector and cradle, the blast deflector and the rear jacks (each a loose part of the
source, picked by its place: `_maz_launcher`); it scales it to the MAZ-543's 11.66 m[^ru-maz543] (its width comes out
2.9 m) and repaints its three-tone camouflage the same olive (`_olive`: the texture's brightness kept within 0.97–1.03,
so its panel lines and rivets stay faintly). An olive cover fills the cradle's place behind the cabs (`engine_cover`,
inferred). The radar's cabins and decks sit on the lockers, 2.6 m up (`DECK`). The 96L6E's real chassis is the
MZKT-7930[^w-mzkt7930] and the 64N6E2's tractor the MAZ-7910; the MAZ-543 stands in for both (the MAZ-7910 is its
successor, inferred). Each was matched by eye to the reference
photographs[^c-64n6e2-maks05][^c-64n6e2-maks03][^c-favorit-maks05][^c-96l6e-maks11][^c-30n6e2-maks09]; the sizes no
source gives are read off them (inferred). The wheels have 16 sides, a flat side down; every model stands 0.08 m into
the ground, so its tyres meet the drawn terrain (inferred).

| part | model | sizes |
|---|---|---|
| 64N6E2 search radar (§15.5) | `radar_64n6e2`: the MAZ-543 chassis as the tractor (the real one the MAZ-7910[^w-maz7310]) and the semi-trailer with the radar's cabin, the two-faced array on its turntable over the gooseneck, the IFF strip under it, the boom over it; 15,912 triangles | the tractor the MAZ-543's 11.66 m[^ru-maz543]; the semi-trailer 13.2 m (the length Army Recognition gives[^ar-64n6], taken as the trailer's, inferred); the array 6.0 m wide and 4.0 m high, its top 9.5 m up (inferred; 0.9 m higher on the MAZ-543's lockers) |
| 96L6E search radar | `radar_96l6e`: the MAZ-543 chassis (the real one the MZKT-7930 8×8[^w-mzkt7930]), the antenna on its post and the rear cabin with the levelling jacks; the array leaned back 10° over the lattice IFF array; 15,236 triangles | the chassis 11.66 m[^ru-maz543]; the array 3.4 m × 4.0 m, its top 8.75 m up (inferred; 0.75 m higher on the MAZ-543's lockers) |
| 30N6E2 track radar on its truck (the default site) | `radar_30n6e2`: the MAZ-543 chassis (the real one the MAZ-7910[^apa-s300]), the antenna's turntable amidships and the control cabin behind; the flat array leaned back 20° with the mast beside it; 15,088 triangles | the MAZ-543's 11.66 m[^ru-maz543]; the array 3.5 m × 3.8 m, its top 8.25 m up (inferred; 0.85 m higher on the MAZ-543's lockers) |

Each antenna (the array, its IFF array, the pedestal above the turntable) is the model's node `antenna`, its origin on
the turning axis. It turns clockwise seen from above while its radar radiates (`air_defence.gd` `_turn`,
`ANTENNA_TURN`): the 64N6E2's while the network's radar stands (§15.5), the 96L6E's while its site searches (so it
stands still while the network cues the site, EMCON `cue`). The 30N6E2's lays on the site's first track at 60°/s
(`LAY_RATE`, inferred, as the Tor's turret) and turns back to the nose without one. A radar out of action stops where
it is.

| radar | one turn | source |
|---|---|---|
| 64N6E2 | 12 s | "a scan once every twelve seconds"[^w-s300]; "full 360-degree mechanical rotation every 12 seconds"[^ar-64n6] (`iaf_ai::net::SCAN`) |
| 96L6E | 6 s | its update every 6 s in the lowest beams (0–1.5°), 12 s above[^mis-96l6e]; one turn per 6 s update inferred |

A stand-in shape (boxes in vertex colours, as the bases' furniture, `base_furniture.gd`) is drawn for any part whose
model fails to load. The S-300's canisters stay down (rest
pose).

The Tor's moving parts follow the site's state (`air_defence.gd` `_rig`, `_animate`, each frame). The converter keeps
five of the source's nodes as their own nodes with the source's pivots (`tools/enemy_models/convert.py` `PARTS`):
`turret`, and hung on it `search_radar`, `tracking_radar`, `cover_l` and `cover_r`. The source's own animations
(`Raise` / `Scan` / `Launch`) are left out; the code turns the nodes:

| part | what turns it | figures |
|---|---|---|
| search radar | turns about up while the site searches (`IafSite`'s `search`) | 120°/s: the source's `Scan`, a turn in 3 s (the real rate open) |
| turret | turns onto the site's first track, back to the nose without one | 60°/s (inferred) |
| tracking radar | elevates onto the first track, 0–80° | 60°/s (inferred) |
| cell covers | open about their hinge at a launch, held open 4 s, over 2 s each way | 146.1°: the source's `Launch` |

A part out of action stops where it is.

A site's models load on the main thread when it spawns (a parse, LODs and texture compression; the S-300's about
65,000 triangles): today only the dev hook spawns sites and drones. Once missions place them, the flight's preload
(`terrain_preload.gd` `mission_models`) takes their `Gltf.UNITS` paths ahead (open).

### 15.5 The network (K6)

An S-300PMU-2 regiment's 83M6E2: the 54K6E2 command post and the 64N6E2 search radar, which designate targets to up to
six batteries[^apa-s300]. The Rust network (`crates/iaf-ai/src/net.rs`, gdext `IafNet`) runs before the sites at the
same 0.5 s tick; the dev hook is `AirDefence.spawn_net(radar_pos, post_pos, members)`, members being site records
(`site_of`), any kind. The test is `modern-iaf/tests/test_sam_net.gd`; the Rust tests are
`crates/iaf-ai/tests/net.rs`.

| | the 64N6E2 | the 54K6E2 |
|---|---|---|
| does | searches for the network: 300 km against 5 m²[^w-s300], a sweep every 12 s[^w-s300], the antenna 8 m up (inferred) | fuses the picture, assigns and cues |
| on the RWR | a search radar of the S-300's type (310) while it stands | nothing (it does not radiate) |
| drawn as | our model, its antenna turning while it radiates (§15.4) | the Ural-4320 model (§15.4) |

- **The picture:** each sweep adds the jets the radar sees (the sites' rule: the jet's cross-section, the terrain and
  the earth's curvature); every site's radar track adds its jet at each tick; so does every radar contact of the
  enemy fighters flying on the network (`Net::shared`, from `ai_flights.gd _step_enemy` through
  `air_defence.gd _net_tick`): the IADS passes "early warning, acquisition, tracking and firing data up, sideways and
  down" (§11-15[^tc7100]). A jet under the 64N6E2's horizon that a MiG holds is cued to a site, which fires on it with
  its own search off. A jet no radar of the network has seen
  for two sweeps (25 s, inferred) drops out. A jet flying below the 64N6E2's horizon stays in the picture while a
  site tracks it.
- **The cue** (§11-35, §11-36[^tc7100]): a networked site runs EMCON `cue` whatever its own: its search radar stays
  off, and its track radar comes on for its cued jet seconds before the envelope (§15.1). The cue is the jet itself;
  the site's acquisition time stands for finding it from the cue's data (inferred).
- **The assignment:** one site per jet, so two sites never fire at one jet. The jets go most dangerous first (the
  soonest to arrive at any site), each to the site that could fire at it first (`Site::eta`): 0 inside its envelope
  with its track radar able to hold the jet; else the time to the envelope's edge at the closing speed, the edge the
  nearer of the launch envelope and the track radar's reach for the jet's cross-section. A site cannot take it with no
  rounds, no track radar, while not set up, in the Tor's break with its window spent, or with the jet masked or too
  close inside the envelope or opening outside it. A site takes no more jets than its channels.
- **The hand-over:** a site keeps its jet while its salvo flies, and while it holds the jet and can still fire. A jet
  leaving the envelope (opening past its edge), masked, or at a site out of rounds goes to the next site. A cue taken
  away ends that site's radar track unless its salvo flies. A gun laying optically on a jet near it (§15.1) takes one
  of its channels but does not keep the jet: the jet goes to the site that can fire at it first, so a ZSU beside an
  S-300 does not hold the S-300's fire on a jet outside the gun's reach.
- **Lost:** with the 64N6E2 or the 54K6E2 out of action (state 3 or more), every member is autonomous at once: its own
  EMCON again (`radiate` by default: the 96L6E searches), the K5 procedure. The picture is cleared; restored, the
  network sweeps at once.

### 15.6 Countermeasures and jamming (K8, K9)

The user, 22 Nov 2026: "Yes start whatever you didn't finished" (countermeasure effectiveness and electronic attack,
unparked 19 Nov). Modern IAF only (`Settings.modern_ew`); the 1998 game keeps its decoy rule, its jammer and its
sensors' beacon (docs/weapons.md §10, §13 here). The rules are `crates/iaf-avionics/src/ecm.rs`.

- **Decoys against seekers** (K8): flares against infrared seekers, chaff against radar seekers, for every jet that
  releases one (the player's keys and CMDS, an AI jet's tree, both through `player_weapons.gd release_decoy`). Each
  missile flying at the releasing jet rolls on its own seeker's chance: the kind, its record's rejection, the beam,
  the time to go, the afterburner and the load factor (docs/real-weapons.md §2.3). A missile taken chases the decoy;
  the seeker does not come back to the jet (as the 1998 rule).
- **The AI's decoys:** every AI jet (the wingmen, the enemy fighters) releases them by its tree against a missile within
  6 s of reaching it, and once at the launch's cue (§8.8).
- **Jamming** (K9): a self-protection jammer holds a radar to its burn-through: the range inside which the echo
  beats the jamming. The echo falls with the range's fourth power, the jamming with its square, so the burn-through
  goes with the root of the cross-section[^w-jam]: R_bt = reach · share · √(σ / 5 m²), the share the jammer's
  (its definition's `jammer.burn_through`, docs/adding-a-plane.md). A radar sees a jamming jet within the nearer of
  its range (§15.2) and the burn-through (`ecm::jammed_reach`); the shares are inferred (no jammer's power is
  published).

| jammer | share | against |
|---|---|---|
| the Sufa's internal SPS-3000 / ASPS (dorsal spine; the J key, the CMDS's JMR switch; docs/f16i.md §8) | 0.3 | the sites' search and track radars (§15.1), the network's 64N6E2 (§15.5, so the GCI's picture too), the enemy fighters' radar (§18.1) |
| an AI jet whose definition has one (our Sufa wingmen; on the enemy's side none today: the MiG-29A (9.12) has none, its jammer came with the 9.13[^w-mig29-jam]), on while its RWR shows a threat or it defends (`Flight::jams`) | its own | an enemy's: the player's radar; a wingman's: the sites, the network and the enemy fighters' radar |
| the Adir's (the AN/ASQ-239's jamming with Israel's Elbit EW; the J key; docs/f35i.md §7.1) | 0.3 (the Sufa's; its power is open) | as the Sufa's; against its small cross-section a short burn-through (the 30N6E2 about 1 km head on) |
| the Barak's | open ([../modern-iaf/docs/ai-plan.md](../modern-iaf/docs/ai-plan.md) §1 item 10) | — |

In Modern IAF the J key's jammer works through the burn-through only; the 0.6 chance of breaking each radar
missile's lock as it comes on is the 1998 game's (docs/weapons.md §10). The player's radar takes a jammer's share only
from a hostile jet; a friendly's (a defending wingman's) jams the enemy, not the own radar.

- **What it gives:** the Sufa head on and level (1.2 m²) is found by the 96L6E at 44 km in place of 210 km and held by the
  30N6E2 inside 29 km in place of 140 km; an enemy fighter's radar (74 km, no cross-section model: the reference 5 m²)
  holds it inside 22 km. Inside the burn-through the jammer changes nothing. A jammed track radar loses its lock
  past the burn-through, and the site's channel frees (§15.1).
- **The cues:** the player's own jammer on, the threat display shows the jamming chevrons either side of every named
  radar (">6<", modern-iaf/docs/ews.md §2); a jammer beyond its burn-through shows on the F-16's FCR as an
  angle-only strobe at its azimuth (docs/radar.md §8).
- **The AI's jammer policy** (`Flight::jams`): on while the jet's RWR shows a radar locked on it or a missile at it,
  or while it defends; off on the commit alone. A self-protection jammer "essentially broadcasts its position"[^w-jam],
  so it answers the radar that tracks it (inferred). Until 22 November 2026 it came on with the commit too: the
  Sufas jammed from 50 km, the MiGs' radar had no contact beyond 22 km and no strobe, and without a ground network
  they kept their orbit (test_wing_battle's first shot took up to 300 s).
- **Home on jam** (`flight.rs know`): an AI fighter's radar that holds a jamming jet inside its cone and its reach
  but beyond the burn-through sees its strobe, the jammer's bearing (as the F-16's FCR, docs/radar.md §8). The pilot
  flies at it as at the ground's vector: it commits and closes, and its radar keeps the angle track, still a lock on
  the target's RWR (`ai_flights.gd _radar_lock`, IafAi state `strobe`). It shoots only once its radar holds the jet
  inside the burn-through (no range from a strobe). The ground's vector, where there is one, comes first. Our
  covering wingmen take a jamming bogey by its strobe the same way (§8.9). Inferred:
  the strobe's position is the jet's own (the range taken as known while it steers).
- **No beacon:** the 1998 rule that the AI's sensors see a jamming player at any range (§13, `combat.gd _scan`) is
  off in Modern IAF; the burn-through takes its place.
- **Tests:** `cargo test -p iaf-avionics ecm` (each rule), `radar a_jammer_shows_as_a_strobe`, `ews
  symbols_priority_and_limits` (the chevrons); `-p iaf-ai --test sites a_jammer_holds_the_radars`, `--test intercept
  a_jamming_bogey` (no ground's vector: the commit on the strobe, the contact inside the burn-through, its jammer off
  on the commit alone and on under a lock), `--test four_ship reactions` (no chaff against a lock, one at a radar
  missile's cue, flares against a near missile); `modern-iaf/tests/test_countermeasures.gd` (headless: decoys against an
  AIM-9M and an AIM-9X, a beaming and a fleeing jet against chaff; the Sufa's jammer against an S-300's track radar,
  the chevrons and the FCR's strobe); `modern-iaf/tests/test_sim_pcd.gd` (the Adir's J: its share, ECM ON, off).
- **The seeker** (2026-11-25, docs/real-weapons.md §2.6): the jammer also acts on each radar-guided missile flying at
  the jet, whoever fired it: outside the seeker's burn-through the missile rolls once on 0.6 · (1 − its rejection),
  and taken, its guidance goes off. The AI jets' jammer is on under a missile, so it works for them too.
- **Not started** (outside the K8 and K9 rows): stand-off and escort jamming; towed decoys.

### 15.7 Later

- The network's other parts (§15.5): the 15Ya6ME relay's 90 km reach, several search radars per network, a
  hand-over delay for a siloed network ([enemies.md](../modern-iaf/docs/research/enemies.md) §5.2), the Tor battery's
  own command post.
- The gun's record (the 23 mm, a draft, threat-records.md) and the site's guidance of its missiles: the missile homes
  by itself and flies on when the track radar dies.
- Roads for the move; §11-121's other moves (after a reconnaissance overflight, after 4–6 hours in place); a battery
  of several sites moving a third at a time.

### 15.8 Shoulder-fired teams

The user, 22 Nov 2026: "Ok follow your suggested order" (the list that named shoulder-fired missiles as a missing
low-altitude threat; modern-iaf/docs/ai-plan.md K16). A team runs on the same Rust site (`Kind::Strela`,
`Kind::Igla`) and the same dev hook, `spawn("strela" | "igla", pos, heading, alternates)`. Two types stand for the two
seeker generations the threat set holds (modern-iaf/docs/threats.md: the Strela-2 with Hezbollah and in Gaza, the
Misagh-2 in Iran). The tests: `cargo test -p iaf-ai --test sites` (`manpads_…`, `a_team_…`,
`the_strela_…`, `skill_sets_the_team_s_reaction`), `modern-iaf/tests/test_manpads.gd`.

| | 9K32M Strela-2M | 9K38 Igla |
|---|---|---|
| seeker | uncooled PbS, a jet's tail only[^w-strela] (generation 1) | cooled InSb and PbS, IR and UV; head on "under favourable circumstances"[^w-igla] (generation 3) |
| the seeker's lock (`sight::RealLock`) | rear 8.4 km with the afterburner, 4.2 km at military power; no front lock | rear 10.4 km / 5.2 km; front 2.5 km, 4 km with the afterburner (inferred) |
| range | 0.8–4.2 km[^w-strela] | 0.5 (inferred)–5.2 km[^w-igla] |
| height above the team | 50–2,300 m[^w-strela] | 10 (inferred)–3,500 m[^w-igla] |
| fastest target | receding 260 m/s; no approaching jet[^w-strela] | approaching 320 m/s, receding 360 m/s[^w-igla] |
| missile | 9.8 kg, 72 mm, 500 m/s[^w-strela] | 10.8 kg, 72 mm, 570 m/s[^w-igla] |
| decoy rejection (`_decoyReject`) | 0: "flares proved to be a highly effective countermeasure"[^w-strela] | 0.6 (inferred): two bands, "much improved resistance against flares"[^w-igla] |

- **The team:** two men (the gunner and one with the second round; inferred), class 9 (an infrared SAM), no radar, so no
  RWR symbol (type −1, [threat-records.md](../modern-iaf/docs/threat-records.md) §3), strength 100 (one 20 mm hit).
  Drawn as a stand-in figure of ours (`air_defence.gd _shape`: the gunner kneeling with the launcher, the second man
  standing); no openly licensed model of a team is on disk.
- **The sight:** the gunner sees a jet within 10 km ("a target detection range of about 10 km"[^w-manpads]) over the
  terrain from 1.7 m (the sites' `visible`); the team holds it by eye (the ZSU's optical rule, §15.1) on one channel.
  A team takes no network cue (`Site::eta`: no track radar).
- **The drill:** from the jet seen to ready, the crew's reaction, then 8 s ("6–10 seconds" from the shoulder with the
  covers off and the sights up[^w-strela]) times its drills' share (§17).
- **The launch:** when the jet is inside the envelope (the caller's `Missile.dlz` from rest inside the published
  range, the crew's share of it as every site's), inside the height band, no faster than the fastest target, and the
  seeker locks it (`RealLock::holds`, the player's IR seeker's rule: in the rear sector beyond half the rear range only
  with the afterburner). One missile, then the next after the first has ended (shoot-look-shoot), 20 s apart at the
  least (the spent tube off, a new one on; inferred). The release aims the missile at the jet (`combat.gd _release`,
  gated to a team's entity, `shoulder`).
- **The missile:** its own record built from the AIM-9M's (its model and drag): the warhead 1.15 and 1.17
  kg[^w-strela][^w-igla], power 250 (one hit damages a fighter, two destroy it) and a 5.7 m blast radius
  ([threat-records.md](../modern-iaf/docs/threat-records.md) §3's rules for the Misagh-2 and the blast scaling;
  inferred), so the proximity fuze (docs/real-weapons.md §2.5) bursts within 5.7 m; type 620, a heat SAM, so the RWR
  does not hear its launch (`rwr.rs ir_guided`) and the MAW warns "SAM" (`ews.rs launch_class`, the class from the
  ground); the physical missile of `missile.rs` with the team's motor and body (`IafSite.missile`); the seeker's cone in
  flight by its generation (15°, 35°). The motor's thrust and propellant are fitted to the top speed and the flight's
  end (the self-destruct's 14–17 s[^w-strela]) to the range: from rest at sea level 495 m/s and 4.3 km, 574 m/s and 5.0
  km. A flare within the missile's last 6 s takes a Strela one time in two, an Igla one in five (§15.6).
- **Moving:** on foot at 1.5 m/s to its alternates after an engagement (§15.1's relocation), a 10 s march order, 5 s
  set-up and a 3 s halt before a shot (all inferred).
- **The drafts:** the Misagh-2 team and missile drafts ([threat-records.md](../modern-iaf/docs/threat-records.md),
  pending the user's decision) are not read: the teams' figures live in `site.rs`; the power and blast follow the
  drafts' rules.
- **Open:** the real seekers' lock ranges, the teams' reload time, the missiles' g limits (12 and 16 g held).

## 16. Modern IAF's one-way attack drones (ours)

The user, 19 November 2026: "we need to have the code for ai enemies. Just isn't reachable by mission yet"; the air
threats of the later Epic Fury work are one-way attack drones of the Shahed-136 class. Each salvo runs on the Rust
salvo (`crates/iaf-ai/src/drone.rs`, gdext `IafSalvo`). No mission launches one yet. `shared/ai/drones.gd` is the dev
and test hook: `load("res://shared/ai/drones.gd").of(host).spawn(route, count, agl, interval)` launches `count` drones
along `route` (world points; the last is the end point on the ground), `agl` m above the terrain (0: the type's),
`interval` s apart (−1: the type's).
Each drone is a mission entity (`drone:N`, class 3: a fixed-wing mover) with the type's radar cross-section, so the
player's radar, data link, AIFF, gun and missiles take it as any air contact, and the existing damage path brings it
down. In look-down the player's radar finds it only where its 97 kt along the line of sight passes the gate (MTR LO:
within about 50° of its nose or tail; MTR HI: never; docs/radar.md §9.8). It does not shoot. The test is
`modern-iaf/tests/test_enemy_drones.gd`; the Rust tests are `crates/iaf-ai/tests/drones.rs`.

### 16.1 The figures

| figure | value | source |
|---|---|---|
| length, span, mass | 3.5 m, 2.5 m, 200 kg | Wikipedia[^w-shahed] |
| cruise speed | 180 km/h (50 m/s); the most 185 km/h | CSIS[^csis-shahed]; Wikipedia[^w-shahed] |
| height band | 60–4,000 m | Army Recognition[^ar-shahed]; "low and slow", "virtual nap-of-the-earth profiles" (RUSI[^rusi-shahed]) |
| its height in the band | 500 m above the terrain unless told | inferred (low, and above the 175 m under which the AWACS's picture and the data link leave a contact out, `fctrl.rs`) |
| radar cross-section | 0.01 m², every aspect | an estimate of the average, one outlet (19FortyFive[^nf-shahed]); the aspects alike: inferred |
| salvo | launched one after another, 10 s apart | fired in multiples from a launch rack (Wikipedia[^w-shahed]), five to a truck's container (RUSI[^rusi-shahed]); the interval inferred |
| turns | 30° of bank: 6.5°/s at cruise, a 440 m radius | inferred |
| climb, sink | 5 m/s, 10 m/s | inferred |
| the terminal dive | 40° below the horizon | inferred |
| strength | 100: one 20 mm hit | our damage scale (modern-iaf/docs/data-formats.md §6), inferred |

The 6-DoF has no data for the type (the AI plan wants sourced 6-DoF data per enemy type): the drone is a point mass
until such data is found (open).

### 16.2 The flight

- **Route.** It turns for its waypoint at the turn rate and passes a waypoint inside its turn's radius (a fly-by),
  waypoint by waypoint in order. Its speed stays at the cruise speed.
- **Height.** It holds its height over the highest terrain under it and every 100 m up to 20 s ahead (1 km), closing
  the error in 5 s within its climb and sink (inferred). The terrain is the mission ground (roofs and trees included),
  as the sites' sight takes it. Away from the player the ground may not be loaded: there it keeps the last ground it
  knew, and a route point's own height stands for the ground under it.
- **The dive.** On the last leg it dives once the end point lies 40° below it, or inside its turn's radius (a low
  drone would circle it otherwise), straight at the point, and ends there: `drones.gd` sets off the explosion and
  removes it (state 5, for whoever still holds it). Its warhead's damage there is not modelled yet. A drone that meets
  the terrain on the way ends there the same way.
- **Salvo.** The drones leave the route's first point at its height one interval apart, heading for the second point:
  the launch from the rack and the climb are not flown.
- **Shot down.** A drone the damage path hits fatally leaves the salvo's flight; the runtime's destruction motion
  takes it (docs/damage.md).

### 16.3 Our sensors

- **Radar.** The player's radar finds it inside the mode's range × (0.01 / 5)^¼ = 0.21: the Sufa's TWS (45 NM) at
  about 9.5 NM, LRS (58 NM) at about 12 NM (docs/radar.md; the 1998 game's units keep the tables). Its terrain line of
  sight is the radar's own `line_of_sight`, the same test the sites' sight (`site::visible`, §15.3) lifts by the
  earth's bulge; at these ranges the bulge is under 10 m. At 97 kt, a drone flying more than about 50° across the
  line of sight falls under the real FCR's 60 kt MTR and drops off the scope, as the real radar's rule does.
- **Data link and AIFF.** The AWACS's tracks on the data link list it as hostile while it flies above 175 m over the
  terrain; the AIFF gets no reply from it.
- **Weapons.** The gun's hit test takes its half span (1.25 m); the missiles fly their existing models (no missile
  performance changed). Its heat is a non-afterburning jet's in the IR seekers' rule (no IR signature research).

### 16.4 Model

The Shahed-136 model of `Gltf.UNITS` ("Shahed 136" by faintastic, CC BY 4.0; docs/credits.md), 3.5 m long and 2.56 m
in span (Wikipedia's 3.5 and 2.5). Without it, the stand-in shape of ours (`drones.gd _shape`, built like the bases'
furniture): the fuselage, the delta wing, the fins and the pusher propeller's disc. The propeller does not turn. No
engine sound: no sound on disk fits a small piston engine.

### 16.5 Later

- The warhead's damage at the end point, the launch from the rack and the climb (the mission work).
- The 6-DoF data for the type (open).
- The integrated network (ai-plan K6, §15.5) and the enemy fighters (K3, K4, §18) are built since.

## 17. Modern IAF's skill levels (ours)

The user, 19 Nov 2026: "wingman are always the same, it only effect enemeis, choosen from 3 options per player". A unit's
skill (`iaf_ai::Skill`, `crates/iaf-ai/src/skill.rs`; modern-iaf/docs/ai-plan.md X4) changes what the crew or pilot
does, never the physics: the radars' reach, the missiles, the guns' rounds and the airframes stay the same at every
level. The pilot picks the enemy's level on the Pilot screen (modern-iaf/docs/front-end.md §3); it is stored with the
pilot (`pilots.skill`, modern-iaf/docs/storage.md), Medium for a pilot who never picked. The wingmen and every
friendly flight keep `Skill::WINGMAN`, the Medium figures, whatever the pilot picks. The enemy fighters (§18) read
the same struct.

| | Low | Medium | High |
|---|---|---|---|
| reaction, from a cue to the answer (s) | 3.0 | 1.0 | 0.5 |
| the crew's drills, share of the type's nominal times | 1.5 | 1.0 | 0.75 |
| the gun's laying error, each way (mrad, one standard deviation) | 8 | 4 | 2 |
| the missile launch range, share of the envelope from its minimum range out | 1.0 | 0.9 | 0.8 |
| a fighter's tactics (§18) | the plain ones | the crank, the notch | the crank, the notch, the drag |
| a fighter's dogfight moves (§18.2) | pure pursuit, a level turn, the break | also the lag, the low yo-yo, the rate or radius fight, the break down, the reversal, the flat scissors, the extension | also the high yo-yo, the vertical, the rolling scissors, the guns jink |
| a site's emission control and move (§15.1) | moves 60 s after its last track | moves after 20 s | moves after 5 s; its search on 20 s a minute while autonomous and idle |

Every figure is inferred: no source grades crews in numbers. The names are the front end's words for the same scale,
"נמוכה / בינונית / גבוהה" (Low / Medium / High, as the Settings' cost column); "מיומנות" is the IDF's word for a
skill[^maarachot].

What each level changes in the enemy we have:

- **The air-defence sites** (§15; `site.skill`, set by `air_defence.gd` from `Settings.enemy_skill()`): a target its
  radar or sight finds is designated after the reaction, then acquired in the type's acquisition time times the
  drills' share (the S-300's 5 s: 7.5 s Low, 3.75 s High). The march order, the set-up and the Tor's halt before a shot
  take the drills' share of their times too; the Tor's duty limits are equipment and stay. The crew launches a missile once the
  target is inside its share of the envelope, counted from the minimum range out (so every level has a window): Low
  fires at the edge, High holds until the target is deeper. With EMCON Cue the track radar comes on that much earlier before this range. The detection is the same at
  every level.
- **The shoulder-fired teams** (§15.8): the reaction and the drill from the shoulder (8 s: 15 s Low, 6.5 s High, with
  the reaction); the launch inside the level's share of the envelope. A jet that comes into sight close and going away
  may leave the missile's reach before a Low crew is ready (`modern-iaf/tests/test_manpads.gd`).
- **The guns** (the ZSU-23-4): each burst is laid off by an error across the line of sight and up, a normal spread of
  the level's mrad (`Skill::lay`: a seeded hash per site and burst, so a run repeats). `air_defence.gd` passes it to
  `combat.gd fire_at`, which moves the aim point by it (straight overhead, about the east axis); the rounds then fly
  the existing round model. A gun fires in its whole range at every level.
- **The fighters** (§18; `IafAi.enemy`, from `Settings.enemy_skill()`): the lead commits after its reaction; each jet
  shoots once the bogey has been inside its share of the missile's envelope for its reaction time, so the launch comes
  deeper than the window's edge by the closure in that time (head-on at 500–550 m/s closing in `--test intercept shot`:
  about 2 km Low, 0.5 km High, with the 0.5 s decision tick); its tactics pick the turns after its shot and against a
  missile. A missile takes no laying error: it guides itself from the launch. In the dogfight (§18.2) its moves are its
  tactics' and its gun's lead point is laid off by the level's error. Our wingmen
  fight on the same rules at the Medium figures (§8.9).
- **The drones** (§16): none. A Shahed-136 flies a programmed route; it has no crew, no reaction and no shot.

Check: `cargo test -p iaf-ai --test sites skill` (each level's track, first launch and march order against the same
detection; the laying errors the same draws scaled by each level's aim, the bursts' rounds and spacing the same) and
`skill::tests` (the three levels, the wingmen's).

## 18. Modern IAF's enemy fighters (ours)

The user, 21 Nov 2026: "Ok finish all enemies things you can", on the plan to build the enemy fighter generically, the
MiG-29 first (modern-iaf/docs/ai-plan.md K2–K4). Step 1 (K2, 2026-11-22): the MiG-29A flies.

- **An AI type of its own definition.** Type 1020 (ours) reaches `shared/extra/planes/mig29a/airframe.json` through
  `airframe::id_for`, as 1000 reaches the F-35I. The definition names its flight-model type (`fm` "MiG-29A", the
  `data_set.rs` row on the `[F-16]` section) and the 6-DoF (`sixdof`); `sixdof::jets::by_type` gives its jet data
  (modern-iaf/docs/flight-model.md §9.21). The 1998 MiG-29 (type 180) keeps its tables.
- **Its record and model.** `modern-iaf/data/db/units/mig29a.json` (with its 30 mm, R-73 and R-27R records) names the
  original MiG-29's model file; the sim's own plane `mig29a` (`iaf-sim own`, from our `mig29.glb`) has that file, so
  `ai_flights.gd` finds the plane as for any mission aircraft and Models: Detailed draws our model.
- **The flight.** It flies under the shared autopilot's loops (§7–§8): start-up, taxi, take-off, the route, the
  landing, the taxi in and parking, on the 6-DoF. Its final approach flies its own α (`Jet::final_alpha`, 10°).
- **The dev hook.** No mission places one (the user, 19 Nov: "we need to have the code for ai enemies. Just isn't
  reachable by mission yet"): `ai_flights.gd` `spawn(unit, at, heading, route)` puts a jet of a bdb unit in the world
  with its plane, flight model and model (a flyable unit, such as the Sufa, its plane from its aircraft
  definition, as a mission's wingman), its route under its autopilot, on the player's enemy side; the caller sets
  its modes (take-off 9, the waypoints 7, the landing 8), as a brain's rules would.
- **Its damage.** A hit breaks one engine of two: the definition's `engines` 2 makes it a twin (`ai_flights.gd`
  `_twin`; the 1998 jets keep the type-code table `PlayerAircraft.TWIN`).
- **On the scopes.** Type 1020 shows as the MiG-29 on the threat warning display ("29", `ews.rs`) and in the radio's
  calls ("MIG29", `fctrl.rs`).

### 18.1 The intercept (K3)

Step 2 (2026-11-22). A pair starts on station: a CAP orbit, or where it was spawned in the air; or parked at a base
(§18.3). The dev hook is `ai_flights.gd` `enemy_flight(ents, station, net)`: the jets from
`spawn`, the station (world), and the network (an `air_defence.gd` network, {} for none). It makes an `IafAi` an enemy
pair (`IafAi.enemy`, `Flight::enemy`) with the enemy trees (`crates/iaf-ai/src/fighter.rs`); the flight's slots, far
rejoin, collision avoidance and threat reactions are the wingmen's (§8.7, §8.8). The pair holds line abreast.

The opposing force relies on its vectoring posts to "redirect fighters in flight to the proper location at the most
opportune time"; Iran's fighter control sits in the KADHQ's radar network
(modern-iaf/docs/research/enemies.md §5.1). So the network's 64N6E2 and 54K6E2 (§15.5) vector the pair: `IafGci`
(`net::Gci`) keeps a picture of the jets the radar's sweeps see (every 12 s, the sites' radar rule) and of the jets the
network's sites track and its fighters hold in their radars (`Gci::shared`, refreshed each tick; §15.5), reckons each
track on at its last velocity between sweeps, and gives the pair the track nearest its station inside the commit range. With
the radar or the post out of action, or with no network, the pair has only its own radar: the host gives the nearest
hostile jet, which the pair knows only while its radar holds it.

| leaf | what it does | figures (all inferred) |
|---|---|---|
| CAP | the lead orbits its station clockwise at the station's height, steering at the point 30° ahead on the circle; the wingman keeps its slot | radius 15 km, 2 g, 220 m/s |
| commit | a bogey inside the commit range of the station, with a missile left: the pair commits after the lead's reaction time | 90 km |
| intercept | the collision course at the bogey (the point where the two meet flying straight, at the bogey's present height; pure pursuit when it cannot be caught). Led in height too, two jets on each other's collision course fed each other's climb or descent: the MiG-29A pair and the Sufas ran away to 15,000 m or down to 800 m (the behaviour until 2026-11-25, dropped) | 4 g, 300 m/s, at most 120 s ahead |
| shot | committed, its own radar holding the bogey (an infrared missile: or its pilot seeing it, §18.2), a missile left and none of its own flying at it, the bogey inside its share of the envelope (§17) for its reaction time (the launch's timing: Low 3 s, Medium 1 s, High 0.5 s): `Order::shoot`; the host fires through `combat.gd`'s launch (the envelope, the cone, the fire gate) | the radar: 74 km against 5 m², ±60° (the wingmen's; "The radar" below) |
| crank | its missile flying, the radar holding the bogey: the bogey 50° off the nose on the side it is on (tactics 1 and up) | 250 m/s |
| defence | a missile at it, after its reaction (a lock alone does not stop the attack): an infrared one the break into it; a radar one the beam at its height (tactics 0), the notch down into the look-down, the missile beamed (1), the drag, a 4 g turn away then full power going down, while the missile is farther than 20 km, inside that the notch (2); chaff or flares each decision while the missile is within 6 s, the 5 s clear (§8.8) | the descent: the steer point 500 m below, near 10°, down to 500 m above the ground; drag 400 m/s |
| back | the bogey lost, past 150 km from the station, or nothing left to shoot with none flying: back to the CAP | 150 km |

- **The host** (`ai_flights.gd` `_step_enemy`, each frame after every jet's step): the bogey (`IafAi.set_bogey`: the
  vector, the jet as it is), each jet's threat (its RWR's locks and the missiles at it, as the wingmen's, now by side),
  its weapons (`set_weapons`: `_pick_aa` selects, of the missiles left, the one with the shortest reach whose envelope
  holds the bogey, else the farthest reaching, and gives its DLZ), then the shots (`combat.gd` action 300), the decoys
  (310 / 320) and its radar's lock on the bogey while it holds it (`combat.gd on_lock`: the target's RWR). A jet from
  `spawn` gets its `combat.gd` unit with the stores of its record (`combat.adopt`).
- **The missiles** are the records the MiG-29A carries (the R-27R, a semi-active radar missile, type 610; the R-73,
  infrared) on the existing physical missile; no support by the shooter's radar is modelled (the 1998 model's).
- **Tests:** `cargo test -p iaf-ai --test intercept` (a MiG-29A pair on the 6-DoF against a scripted bogey: one test per
  leaf, each skill's commit time, shot range, crank and defence), `--test net gci` (the picture), `fighter::tests` (the
  collision course, the orbit, the crank, the window), `--test intercept defence` also the notch and the drag going down
  while they turn and the beam and the break within 30 m of their height, `fighter_laws_only_when_asked` the steer loop
  unchanged without the fighter's laws (§8.8);
  `modern-iaf/tests/test_intercept.gd` (headless: a pair on a CAP vectored onto a scripted jet, commits, locks, shoots,
  notches a radar missile).
- **The radar** (`flight.rs` `radar_holds`, each decision for every AI jet in the air, the wingmen's too): the sites'
  rule (`site::in_reach`, §15.2, §15.3): inside the cone (±60°) and the reach of 74 km against 5 m², scaled by the
  bogey's cross-section seen from the radar (its definition's `rcs`, its bays, its stores; an untreated fighter's
  without one), inside its burn-through when it jams (§15.6), and in sight over the terrain (the mission ground) and
  the earth's curvature. In look-down (`radar::look_down`, docs/radar.md §9.8) it loses a bogey slower than 30 m/s
  along the line of sight (the ground's Doppler band; the real FCR's MTR LO taken for every AI radar, inferred).
  Head on, the clean Adir is held inside 9.7 km (its bays open 50 km), the clean Sufa inside 52 km, a MiG-29A inside
  74 km; from the side a fighter's 25 m² is held to 110 km. A jammer's strobe shows only in sight. Tests:
  `cargo test -p iaf-ai --test intercept its_radar_sees`.
- **Open:** the pairing of several pairs to several raids (each pair takes the track nearest its station).

### 18.2 The dogfight (K4)

Step 3 (2026-11-22). Inside the fight's range of a bogey it sees, a committed fighter with something to shoot flies the
BFM leaf (`crates/iaf-ai/src/bfm.rs`) in place of the intercept, in both trees after the missile shot; past 1.5 times
the range it goes back to the intercept. Each decision (0.5 s) the leaf reads:

- **the geometry:** the range, its nose's angle to the bogey (the antenna train angle) and its angle off the bogey's
  tail (the aspect angle), the closure;
- **the energy:** both jets' energy heights (height plus V²/2g);
- **the turn:** its own from the 6-DoF's real limits: the corner speed at its weight and height (`SixDof::corner_speed`:
  the level speed at its α limit times √ its g limit, from the same trim as the landing circuit's speeds), the most it
  pulls at a speed ((V / corner)² of the g limit) and its turn rate at the corner; the bogey's turn as seen (its
  velocity's swing between two decisions).

The moves are the basic fighter manoeuvres as Shaw names them[^shaw] (the reference the plan names); their thresholds
are ours (inferred). The skill's tactics (§17) pick the branches:

| situation | tactics 0 | tactics 1 adds | tactics 2 adds |
|---|---|---|---|
| offensive: the bogey within 90° of its nose, itself within 90° of the bogey's tail | pure pursuit (the lead point inside the gun's range) at full g, its closure controlled | the lag (1.5 s behind the bogey) when closing faster than 60 m/s inside 2.5 km or when its turn circle is wider; the low yo-yo (the point 0.4 of the range below) when out of the gun's range and falling back, or slow | the high yo-yo (the lag point 0.4 of the range above) when closing at 120 m/s from more than 45° off the tail |
| defensive: the bogey behind its beam, its nose within 60° of it, inside 5 km | the break: full g into the bogey, level | the break in any plane; the break down (the point 0.4 of the range below) when 600 m of energy height behind; the reversal before both when the bogey closes faster than 60 m/s inside the gun's range (full g into it at 0.6 of the corner speed, the speed brake out: it overshoots) | the guns jink inside 1.35 km: the point a range above or below, flipped every 2 s |
| neutral | a level turn at full g toward the bogey | the flat scissors inside 1.5 km with the bogey off its wing (45–135° off the nose), both flying within 45° of one way and the bogey below the corner speed (full g into it at 0.6 of the corner speed: the slower one ends behind); the extension when 600 m of energy height behind, farther than 3 km and in the bogey's rear quarter (its nose more than 120° off: unloaded to 2 g at full power, straight away and 0.1 of the range down, until past the fight's 9 km, then the intercept back); else the rate fight (pure pursuit, the speed held near the corner) when it out-turns the bogey, else the radius fight (full g at 0.75 of the corner speed) | the rolling scissors in place of the flat (the point 0.4 of the range above); the vertical (the point 0.4 of the range above) when 600 m of energy height ahead and faster than the corner speed |

- **Energy.** No move asks more than the wing gives at the speed (no pull into the α limit's drag). From tactics 1 the
  fighter holds its speed near the corner: in the rate fight, the lag, the high yo-yo and the vertical it unloads to
  3 g below 0.85 of the corner speed, the rate fight flies the corner speed (the throttle and the speed brake from
  above), and when slow out of the gun's range it flies the low yo-yo (down for speed, full g). The vertical, the
  yo-yos down, the defensive moves and the level turn fly full power; the radius fight its slower speed.
- **The closure** (every offensive move: pursuit, lead, lag, high yo-yo; Shaw's closure control[^shaw], here by the
  throttle and the speed brake): the closure wanted is 0.1 per second of the range past 600 m (inside the
  gun's), at most 100 m/s either way; the move's speed is its own speed plus the closure wanted less the closure, never
  below the corner speed (a slower chase bled to 130 m/s at full g behind a turning jet). The BFM loop opens the speed
  brake 25 m/s above the move's speed (the speed law is at idle 23 m/s fast; the radius fight's slower speed too), and
  the fighter's steer loop closes it. Between the steer and the BFM loop the autopilot's 0.5 s hold of the old stick
  on a change of mode is skipped (the level moves switch loops each decision; the 1998 loops keep it). Behind a jet flying straight at 280 m/s
  each level closes on afterburner, throttles back from about 1.3 km and settles 480 m behind (the speed law's offset
  from 600), firing; with full power it passed the jet at 400 m/s and lost it (`dogfight.rs`
  `closure_control_settles_behind`). All figures inferred.
- **The level moves** (the plain tactics' break and turn) fly the steer loop with the fighter's turn laws (§8.8) at the
  height the move began at: the BFM loop's turn toward a point behind took the path's own pitch for its plane (the
  shortest rotation onto a line behind is undefined in the plane, so the trim's and the climb's pitch picked it), and
  the point was set at the jet's own height each decision: the neutral level turn climbed 1.6 km in 12 s, pitched to
  70° and rolled over the top (per-frame bank, g and vertical speed, 22 November 2026). Now the 9 g level turn holds
  within 32 m.
- **The BFM loop** (`autopilot.rs` `MODE_BFM`, ours): it flies the move's point in any plane, the lift rolled onto it
  with no bank limit; the turn asked is 0.5 per radian of the angle to the point plus the swing of the line to it (as
  a proportional navigation's: a moving point is tracked with no standing error), inside the load factor left once
  gravity's share is held; the line to the point is kept within 60° of the horizon (no loops: the bank about the
  horizon stays defined); the ground watch stays on. Its tick is 1/30 s. The gain and the tick are the least tracking
  error behind a jet in a 5 g turn (2.9° mean, `dogfight.rs`). The flight moves the point onto the bogey as it is every
  frame while the fighter sees it (`Flight::feed`), and never below 500 m above the ground (the fight's floor, the
  notch's).
- **Sight.** A pilot sees a jet within 8 km except in the 30° cone behind its own tail (the MiG-29's "poor view to the
  rear", modern-iaf/docs/research/enemies.md §4.2); once seen, it keeps sight inside the 8 km (checking six). The
  bogey's truth is then known without the radar; the radar's lock and the missile shot still need the radar's
  contact.
- **The R-73 on the helmet sight.** Its missile shot (§18.1) wants its radar's contact, or, with an infrared missile
  selected (the R-73: `_pick_aa` takes the shortest reach whose envelope holds the bogey, so close in the R-73), its
  pilot seeing the bogey: the MiG-29's helmet sight gave "a lock on any target the pilot could see ... almost 45
  degrees off boresight"[^w-mig29]. The host's launch keeps combat.gd's cone (30° times the skill's factor). The
  shot is checked before the dogfight's move each decision, so a fighter in the BFM leaf fires its R-73 when the
  bogey is inside its window, on the physical missile (docs/real-weapons.md §2.1). `IafAi.set_ir`; Rust test
  `dogfight.rs r73_on_the_helmet_sight` (a bogey jamming its radar, seen: the R-73 shot, not the R-27R).
- **The gun.** Inside 330–900 m (the 30 mm's, inferred) with the lead point (the round's flight time at 860 m/s plus its
  own speed) within 2° of the nose in any move (a lag behind a bogey flying straight included) and the bogey itself
  within combat.gd's 5° gun cone, the fighter orders a burst (`Order::gun`); the lead point is laid off by the skill's
  error (`Skill::lay`, a seeded hash per jet and burst). The host (`ai_flights.gd` `_step_enemy`) selects the gun
  (combat.gd 370), sets a 1 s burst (5 ticks; inferred) and launches it (300: the cone, the gun's envelope, the fire
  gate at 370's 5 s); the gate's interval is the missiles' again after the burst. A brain-less jet's rounds fly at the
  target of its launch (`combat.gd` `gun_target`). A fighter with no missile but rounds left counts as armed: it commits
  and closes to the gun.
- **The MiG-29's tuning** (modern-iaf/docs/research/enemies.md §4.2): its "nose-pointing" below 200 kt and the F-16's acceleration above come
  from the 6-DoF itself (its corner speed and thrust); its poor rear view is the blind cone. No figure is specific to
  the type: another fighter flies the same leaf from its own definition.
- **Tests:** `cargo test -p iaf-ai --test dogfight` (MiG-29As on the 6-DoF: offensive behind a jet in a 5 g turn,
  each level reaches a gun solution and from Medium stays behind its 3-9 line, the plain tactics' tracking under 4°;
  defensive with a High fighter behind, each level breaks or jinks (the level break within 30 m of its height); behind
  a jet flying straight each level settles in the gun's range without passing it; neutral head-on passes 0.5, 1 and 2 km apart,
  High against Low both ways, 120 s each: High offensive longer, 36 s against 0 in sum, its rate fight at the corner
  speed out-turning Low's fast level turn), `scissors_reversal_and_extension` (two Medium fighters line abreast and
  slow fly the flat scissors; a jet closing fast behind a Medium one overshoots it after the reversal; a Medium fighter
  low and slow in the rear quarter of a jet extends and comes back by the intercept), `bfm::tests` (the moves by
  geometry, energy and tactics; the points); `modern-iaf/tests/test_bfm_iads.gd` (headless: a MiG-29A with R-73s on
  an S-300 network whose search radar is out of reach, behind a scripted jet: its contact shared, the GCI's vector
  on the jet from that contact alone, an R-73 fired in the fight;
  an autonomous Medium battery searching on); `modern-iaf/tests/test_dogfight.gd` (headless: a MiG-29A behind a scripted jet sees it, commits, flies a
  BFM move and fires its gun through combat.gd). The tests repeat: the Rust ones are deterministic (the laying
  error is a seeded hash).
- **CPU:** 4.1–7.8 µs per jet per frame on the build Mac for the Rust part (two fighters in the BFM leaf; the 6-DoF,
  the autopilot, the trees), against the intercept's 3.9.
- **Each fighter fights its own bandit**: committed, the pair sorts the bogey's group (§8.11), so against two jets
  each takes one; against one both fly the leaf on it (the flight's collision avoidance keeps them apart). The bogey's turn is the one it shows, not its type's limits: a pilot sees the turn, not
  the other jet's corner speed.
- **Our wingmen** fly the same leaf on their foe (§8.9, 22 November 2026).

### 18.3 The scramble from a base (K3)

2026-11-22. A pair can start parked at an airbase and scramble from there. The sim has no enemy airbase in its data
(the user, 22 Nov: no enemy airbases yet), so any base in `iaf.ibx` stands in, named by the dev hook's argument. No
mission places one.

- **The dev hook.** `ai_flights.gd` `enemy_base(unit, base, count, station, net)` spawns up to `count` jets of the
  bdb unit in the base's shelters (`HangarPt*`), engines off, and makes them an enemy pair by `enemy_flight`. Their
  route: the take-off point 15 km along the runway and the landing waypoint 15 km out on the approach (action 7), both
  1,500 m up (the Rust ground run's).
- **Based.** `Flight::enemy` marks every jet added on the ground as based (`Enemy::based`).
- **The scramble.** On the ground its radar is off and its pilot looks for nothing: only the network's vector (§18.1)
  counts. A vectored bogey inside the commit range (90 km) of the station for the lead's reaction time (§17) starts
  the lead's engine. The wingman starts once the lead's engine runs (the flight's clearance, the wingmen's tree).
  Both taxi and take off under the autopilot's ground loops (TaxiCL, TakeoffCL), then fly the intercept's trees.
- **Home.** The sortie ends when the intercept ends (the bogey lost or out of range), when nothing is left to shoot
  with none of its missiles flying, or at bingo fuel. The lead flies GoHomeCL (mode 8) to the landing waypoint and
  lands; the flight's landing sequence sends the wingman after it; both taxi in and park in their shelters. A bogey
  shot down drops out of the vector at once (`_step_enemy`), though the network's track runs on a while. A bogey
  lost before the lead commits in the air leaves the pair on its CAP until bingo. A pair scrambles once: parked
  again, it stays parked.
- **Tests:** `cargo test -p iaf-ai --test scramble` (two MiG-29As on the 6-DoF in Ramon's shelters: no start on a bogey
  without the vector, the start after the lead's reaction, the take-off in order, the commit within 30 s of the
  take-off, home, landing and parking within 40 m of the shelters); `modern-iaf/tests/test_enemy_scramble.gd`
  (headless on the range mission: the pair in Ramon's shelters, the player's jet moved to Nevatim and parked there).
- The ground, the flare and the arrival home of every AI jet: §18.4.

### 18.4 Every AI jet's ground, flare and arrival home

2026-11-22. The faults found with the scramble held for every AI jet on Modern IAF's 6-DoF, not only a based one.

- **The ground wherever the player is.** The terrain loads its full-detail heights only for the nodes its camera's tree
  wants (within the view range, `camera.far`), and an AI jet beyond them, or before its node arrived, had none (`terrain_view.gd` `feed_ground` gives −1e9): one landing far from the player fell through the
  ground. Now `ai_flights.gd` lists each AI jet's position in `terrain.gd` `extra_heights` every frame; the terrain
  keeps the height node under each loaded (not drawn, not waited for). Until it is there, the jet keeps the last ground
  it had (`_feed_ground`), a parked one its spawn's height. The autopilot's ground probe falls back the same way.
  Modern IAF only (`Settings.new_ai()`); the 1998 game's AI jets keep the ground as before.
- **The flare over the runway.** The 6-DoF AI's flare (autopilot `Landing::flare`, and the final's end at the flare
  height) measured the wheels' height over the ground under the jet. At Nevatim the ground under the final stands up
  to 12 m above the runway, so the flare began 20 m up over the rise. Now it measures the height over the runway
  (`Landing::wheels_height`): short of the lineup the lineup's height, past it the ground. The player's flare keeps
  the ground's.
- **The flare's lead.** The MiG-29A's vertical acceleration follows the flare's command about 2 s late. On the sink of
  the moment the flare pushed while the jet still rose (0.5 m/s at 13° of pitch, 3 m up), and the push came on as it
  neared the runway: 2.3 m/s at the touch on level ground, and at Nevatim, where the runway falls about 2 m in its
  first 240 m, a crash on the sink rate. The AI's flare now flies the sink 1 s ahead (`FLARE_LEAD_AI`: the vertical
  acceleration × 1 s added; swept 0.5–2 s, 1.3 m/s at the touch at 1 s). The player's flare is unchanged.
- **The arrival home.** GoHome's Fly2WayPt ends on passing its waypoint (KeepAttitude, PassWaypoint within 1,852 m).
  A wingman sent home abeam of the waypoint and near it circled it at KeepAttitude's 45° bank, 4 km off at 197 m/s,
  until its fuel ran out. On the 6-DoF the pass now counts within 1.5 × the 45° turn's radius (5.9 km at 197 m/s); the
  landing's pattern starts from where the jet is.
- **Nevatim's taxi in** (fixed the same day): its four spots turn off one taxi line 25 m apart, and #4, braking
  straight on into its 90° turn at the taxi speed, swung 40 m wide into #2's spot (1 m from it). The taxi now slows
  before a pivot and the flight spaces the jets taxiing in (§8.7, "The recovery, end to end"): 44 m at the least.
- Tried and dropped (2026-11-22): KeepAttitude flying wings level while the waypoint lies inside its turn. Flying
  away the jet sped up (the route's speed cap holds only inside 6 km), its turn widened with it, and it ran on for
  minutes. The flare's sum held at zero once the jet stopped sinking: the touch was the same, as the sum was already
  negative when the jet rose.
- **Tests:** `cargo test -p iaf-ai --test landing` (a MiG-29A home from 15 km out over a 12 m rise under the final onto
  a runway falling 0.8 %: no crash, a touchdown under 3 m/s); `cargo test -p iaf-ai --test four_ship
  mig29_ground_run_at_nevatim` (the four-ship ground run at Nevatim: all four land and park, at the least 30 m apart
  on the ground);
  `modern-iaf/tests/test_ai_far_landing.gd` (headless: a MiG-29A lands at Nevatim with the player parked there, then
  with the player at Tel Nof, 70 km off, and the view range cut to 10 km, so no terrain is loaded at Nevatim).

## 19. Modern IAF's moving ground vehicles (ours)

The user, 22 November 2026, on the order of the last enemy jobs: "Ok follow your suggested order", which named
"ground units that move: convoys on roads; ground attack needs moving targets". A convoy is a column of T-72 tanks
and Ural-4320 trucks (their unit records `target_t72`, `target_ural` and models, §15.4) run by the Rust convoy
(`crates/iaf-ai/src/convoy.rs`, gdext `IafConvoy`). No mission places one yet. `shared/ai/convoys.gd` is the dev and
test hook: `load("res://shared/ai/convoys.gd").of(host).spawn(ids, from, to, side)` makes a column of the records
`ids` (head first) whose tail stands at `from` (world) and which drives to `to`. Each vehicle is a mission entity
(`convoy:N`, class 6, a vehicle) with its record's model, strength and size, so the player's sensors and weapons and
the AI jets' attack (§8.10) take it as any ground unit. The test is `modern-iaf/tests/test_convoy.gd`; the Rust tests
are `crates/iaf-ai/tests/convoy.rs`.

### 19.1 The figures

| figure | value | source |
|---|---|---|
| T-72 top speed | 60 km/h on roads; 35 km/h across country | Wikipedia[^w-t72-speed]; across country inferred |
| Ural-4320 top speed | 82 km/h on roads (the V8); 30 km/h across country | Wikipedia[^w-ural]; across country inferred |
| march speed | 0.7 of the slowest vehicle's top speed for the ground under the head: 42 km/h on a road with a T-72 in the column | inferred |
| spacing | 100 m between two vehicles | an open column's "intervals of 300 feet or more" (FHWA[^fhwa-convoy]) |
| alarm | a blast within 500 m of a vehicle | inferred |
| scatter | off the road square to its course (a little ahead), even places right, odd places left, 60–141 m out, then stopped | inferred |
| quiet | 60 s after the last blast they drive on | inferred |
| turning off the road | on the spot at 45°/s, driving once within 30° of the goal | inferred |

### 19.2 The drive

- **Route.** `IafConvoy.create` asks the road layer (`iaf_avionics::roads::Roads::route`, OpenStreetMap's roads down
  to tertiary; the route's cost per class prefers the big roads) for the road route between the road points nearest
  `from` and `to`. The route takes it, with the legs from `from` to the road and from the road to `to` across country,
  when those two legs add up to less than half the straight line; else the column drives straight across country.
  Without the road layer (an older setup) every route is across country.
- **Column.** Each vehicle keeps its place along the route, 100 m behind the one ahead, so the column follows the road
  through every bend. It drives at the march speed for the ground under its head; at the route's end the head stops
  there and each other vehicle 100 m behind the one ahead.
- **Ground.** Each vehicle stands on the mission ground under it (roofs and trees included, as the sites take it) and
  pitches with the terrain read at its two ends. Away from the player the ground may not be loaded: each convoy's first
  vehicle alive joins the AI jets' height nodes (terrain.gd `extra_heights`, §18.4), and until they arrive a vehicle keeps the last
  ground it had.
- **Attacked.** Every `area_damage` (a bomb, a missile, a rocket, a gun's round, a hit) tells the convoys through the
  runtime's `blast` signal. A blast within 500 m of a vehicle alive scatters the convoy: each vehicle turns off the
  road to its side and stops there. Each further blast restarts the 60 s of quiet. After them the survivors drive back
  onto the route, closed up behind the head in their order, and the column drives on.
- **Destroyed.** A vehicle hit fatally stays where it was; the runtime's destruction takes it (docs/damage.md). The
  column goes on without it.
- **Models.** The T-72's and the Ural's models are one mesh each, with no wheel or track nodes: the hull moves and
  pitches; nothing turns.

### 19.3 The attack on a moving vehicle

The AI jets' run (§8.10) follows the target's position each decision. The release leads it: the impact is compared
with where the target will be after the store's fall from here (its velocity times the fall time), so a dive's or a
level run's release falls on the vehicle where it will be. The AI ripple's stores lead a target by their own rule
(combat.gd, FUN_00454b70: the velocity over the distance / own speed), which aims a guided bomb (type 650) where the
target is now. Ours: `ai_flights.gd _release` gives the ripple a moving target as the point that rule leads it to, so
bombs and rockets aim as before and a guided bomb aims there too.

### 19.4 Later

- Mission content (convoys placed by a mission). The front end's Scramble places one (§23).

## 20. Modern IAF's low level and ground collision avoidance (ours)

The user, 22 November 2026, on the order of the last enemy jobs: "Ok follow your suggested order", which named the AI
jets' terrain following for attack runs (modern-iaf/docs/ai-plan.md K17). Every AI jet of IafAi, ours and the enemy's,
has it; the 1998 game and the player's autopilot set none of it (`Autopilot::floor` None). Figures are inferred unless
they say otherwise.

| figure | value | source |
|---|---|---|
| floor | 30 m (100 ft) above the terrain, every AI jet | inferred |
| fly-up | a roll to wings level, then 5 g, to a 20° climb | the F-16's Auto GCAS: "roll to wings-level and 5-g pull"[^gcas]; the climb inferred |
| fly-up prediction | 1 s of delay, the roll at the jet's roll rate, the pull, the climb 3 s on, every 0.1 s | inferred (the 6-DoF's load factor builds over about a second) |
| low level | 150 to 500 ft (46 to 152 m) above the terrain ahead, by order; the lead's radio order 300 ft (91 m) | inferred |
| terrain following | the terrain 10 s ahead along the track, cleared when climbed to at 10° from 1.5 s before it; a path 15° down to 30° up; 0.2 to 3 g | inferred |
| pop-up | pulled up 4 nm (7.4 km) from the target to 30° into the 30° dive; the roll-in 1,500 m above the target | the US Navy's pop-up attack[^popup]; the roll-in height inferred |

- **Ground collision avoidance** (`iaf_flight::autopilot`, `Autopilot::floor`, set for every AI jet by `iaf_ai::apply`).
  In every loop but the take-off and the landing, every 0.1 s the autopilot predicts a fly-up started now
  (`fly_up_clearance`): the delay and the roll with the climb rate changing as the jet's acceleration has it now, then
  the 5 g pull to a 20° climb along its track, over the terrain the host gives (the per-jet height node of §18.4). When
  the least clearance of that fly-up is under the floor, the fly-up takes the stick over the loop (BFM, the dive, the
  formation, the defence), at least military power, until its prediction clears the floor by half again and the jet
  climbs. It runs beside the original's watch-ground (§8.0: wings level and climb when the point 4 s ahead, plus the
  descent / 15, is less than 200 m over the terrain); a jet flying low has the fly-up alone, since the watch-ground's
  200 m would hold it up.
- **Low level** (`Flight::low`, `IafAi.set_low`; the dev hook `ai_flights.gd flight_low(agl_m)`; no mission sets it
  yet). The lead orders it: the radio menu's flight page "Low level" / "Back to altitude" (`Flight::command` "low" /
  "high" to the flight, 300 ft, `LOW_ORDER_M`, inferred), or record 257 (`Ctrl + \`), which gives the one of the two not
  in force (`sim_flight.gd flight_command`). Every flying wingman acknowledges; one on the ground answers "unable", and
  with no jet taking it the order changes nothing. Addressed to one wingman or the element, it is "unable". The flight's
  AI jets fly their steered legs (the split's task, the rejoin, the defence turn outside a fight)
  at the set height above the terrain ahead (`Autopilot::follow`, `follow_height`): the height that clears the terrain
  10 s ahead when climbed to at 10° from 1.5 s before it (the climb starts early by the jet's answer), and its rate a
  second on, flown as a climb rate of 0.3 per m of error within the path's limits. An air fight (the CAP, the intercept,
  the dogfight, the defence in a fight: `fighter::steer`, `bfm::fight`) flies its own heights: the level break holds its
  height with the flight low too (`dogfight.rs defensive_break`). The wingmen on their slots keep the lead's height; the
  fly-up guards them.
- **The low attack** (§8.10, profile `pop`): with the flight low, a bomb or rocket run comes in on the terrain
  following, pops up 7.4 km from the target at 30°, rolls in from 1,500 m above the target into the 30° dive and
  releases as the dive does; the egress pulls out and goes out low on the terrain following. A guided bomb's level run
  comes in low and climbs to its 1,500 m at 14.8 km (twice the distance: its release lies 4 km or more short of the
  target).
- **Tried and dropped (23 November 2026):** the fly-up in place of the watch-ground for every AI jet. Over open
  ground the watch-ground also acts in a steep dive at 5,000 m (its look-ahead grows with the descent) and gives
  full power; without it a High MiG-29A in the neutral merges bled to 140 m/s in its yo-yos and was offensive 0 s
  instead of 36 s (`dogfight.rs neutral_merge_skill_decides`). It now runs in place of the watch-ground only while
  the jet flies low. A climb law on the height error alone (no rate) overshot each valley and came within 19 m of a
  rise; a 1 s extrapolation of the climb rate was added to the fly-up after a MiG-29A pulling 7 g inverted toward the
  ground was predicted too late. The climb profile without the 1.5 s lead began each climb just in time: over a
  knoll 50 m high and 300 m across the jet came within 44 m, the fly-up took over and the jet ballooned to 380 m for
  2 km (over the Negev in test_low_level.gd, and in `lowlevel.rs` follows_over_a_knoll_without_a_balloon); with the
  lead it rides 46 to 120 m over the same knolls.
- **Tests:** `cargo test -p iaf-ai --test lowlevel` (over hills with 6° slopes: a Sufa and a MiG-29A at 200 ft for
  40 km, the least 56 m, the mean 66 m; a Sufa over 50 m knolls, 46 to 120 m; a MiG-29A's BFM dive at the ground, upright and inverted, with and without the
  low level, pulled out 76 m or more over the hills; the four-ship's low pop-up attack: the run-in at 55 to 66 m, the
  apex 2,517 m, the store 2 m from the target, never under the floor); `modern-iaf/tests/test_low_level.gd`
  (headless over the Negev: Kidon 1-2's low pop-up attack on a 64N6E2, and an S-300's march on the roads).

[^gcas]: NASA / AFRL, "Automatic Ground Collision Avoidance System" (ntrs.nasa.gov, 20090035618): the maneuver
    phase, a roll to wings level and a 5 g pull. <https://ntrs.nasa.gov/api/citations/20090035618/downloads/20090035618.pdf>
[^popup]: CNATRA P-1217, Operational Navigation Flight Training Instruction, "The Pop-Up Attack": "The pop-up and
    cut should be executed at four miles from the target", "30 degrees nose up", "30-degree dive cone".
    <https://navyflightmanuals.tpub.com/P-1217/The-Pop-Up-Attack-46.htm>

## 21. Modern IAF's target drones (ours)

The weapons range's drones and the intercept lesson's drone (modern-iaf/docs/ai-plan.md C4: "the lesson's drone flies
a route under the new core, non-manoeuvring as decided; the range's drones move over too") are the sim's own jets on
the flight model, flown by the autopilot's loops. In Modern IAF their decisions are Rust (`crates/iaf-ai/src/target.rs`,
gdext `IafTargetDrone`); `shared/ai/ai_flights.gd` (`_setup_drones`, `_step_drone`) gives one to every AI jet outside
the player's flight whose brain record is a target drone's. The 1998 game's jets keep their brain (§2–§6).

- **Kind.** Read from the brain record's actions (modern-iaf/docs/data-formats.md §5.1): `navigate` alone is the
  route drone (`drone`, non-manoeuvring: the lesson's), with `select_air_target` the radar drone (`drone_radar`), with
  `break_90` or `run_away` the evading drone (`drone_evade`). A record with any other action is not a target drone's.
  The records' conditions are not read: the 9 km and the roll under 50 are `target.rs`'s figures, the same as
  `drone_evade`'s. The brain's other parts (sub-brains, combat on and off) are not used: no drone record has them.
- **Decision.** At once, then every 3 s: the 1998 brain's 2 s for an enemy aircraft, × 1.5 at the Normal AI level,
  which Modern IAF keeps (it has no AI level preference). The radar and evading drones first pick the best air contact of
  their sensor (combat.gd's air mode pick, whose lock the target's RWR hears). The evading drone, with that contact
  alive inside 9 km, breaks 90° (Break90, mode 0x13) on a roll of 0..100 under 50, else runs away from it (RunAway,
  0x12); every other decision flies the route (WayPtSet, mode 7). A loop already running is kept.
- **Never shoots.** No drone kind has a weapon.

The tests: `crates/iaf-ai/tests/target_drones.rs` (the kinds, the period, each kind's loops) and
`modern-iaf/tests/test_sim_range.gd` (every range drone flies under its brain's kind; Drone 3 breaks or runs from a jet
5 km behind it), `modern-iaf/tests/test_sim_ews.gd` (Drones 4's lock on the player's RWR).

## 22. Modern IAF's big fight: everything at once (ours)

The user, 22 November 2026: "Ok follow your suggested order. If possible create a video of your multiplabes multi sam
etc dogfight?" (modern-iaf/docs/ai-plan.md K12, X5). One scenario puts the AI of §8.9–§20 in the same sky, built
from the dev hooks alone (`modern-iaf/tests/big_fight.gd`). No mission places it.

- **The scenario.** Mission `ramon_four_ship` with MK-82s on the Arming load. The four-ship flies over Ramon at
  6,000 m heading north (`flight_in_air`). The lead flies on ALT HOLD and HDG SEL and is invulnerable; the wingmen can
  be shot down. The enemy flies at the pilot's skill (Medium by default):
  - a convoy of two T-72s and two Ural-4320s on the roads 25 to 35 km north (§19), with a Tor-M1 and a ZSU-23-4
    beside it;
  - an S-300PMU-2 battery 65 km north (96L6E, 30N6E2 and four 5P85TE2) under an 83M6E2 network (64N6E2, 54K6E2).
    All three sites join the network (§15.5);
  - a MiG-29A pair on CAP 85 km north;
  - a second pair parked at Nevatim, which scrambles on the network's vector (§18.3; Nevatim stands in for an enemy
    base);
  - four Shahed-136s flying from the north at Ramon (§16).
- **The lead's orders** go through the radio menu's path (`sim_flight.gd flight_command`):
  - "low level" to the flight at once (§20);
  - "sort" once a MiG is within 60 km;
  - "weapons free" to the element round the MiGs, 8 s after the sort (§8.11);
  - "engage my target" to Kidon 1-2 with the radar's point on the convoy's first vehicle alive, 12 s after the sort (§8.10: the low
    pop-up attack on a moving vehicle).
- **What happens** (headless runs of 420 s, 23 November 2026):
  - Kidon 1-3 and 1-4 shoot down both CAP MiGs, and Kidon 1-2 bombs the convoy (one or two vehicles).
  - The S-300's launchers, the Tor and the MiGs fire 30 to 32 missiles, most of them at the invulnerable lead.
  - One wingman of three is shot down in most runs.
  - The based pair takes off. No AI jet hits the ground and none is stuck.
- **CPU cost** on the Iris Xe laptop: headless, at time scale 1, 20 s after the sort, with a quiet machine. The fight
  has 7 AI jets, 3 sites and a network, 4 drones and 4 vehicles. Figures of 23 November 2026, before and after the
  profiling fixes below (the same machine, one run each):

  | Part | Before | After |
  |---|---|---|
  | The AI jets, a frame | 3.33 ms (0.48 ms each) | 2.67 ms (0.38 ms each) |
  | The sites with their network | 0.12 ms | 0.07 ms |
  | The drones; the convoy | 0.06 ms; 0.07 ms | 0.06 ms; 0.06 ms |
  | The frame's whole process time | 24.3 ms | 15.2 ms |
  | The same with our flight alone | 11.9 ms | 10.8 ms |

  The whole fight now fits the 16.7 ms of a 60 fps frame on the CPU. Jets fighting still cost more than those in the
  calmer tests (0.15–0.21 ms, ai-plan X5).
- **Where the time went** (Godot's script profiler with native calls, `modern-iaf/tests/_big_fight_profile.gd` and
  `tools/gd_profile.py`; the profiler's own overhead inflates every figure by about a third):
  - **The 3D cockpit's DED: 3.9 ms a frame.** It draws each character on its own, centred by
    `Font.get_string_size`. The font's string cache misses each time the font's glyph cache changes, which the fight's
    many labels make happen every frame: 50 µs a character against 1 µs with our flight alone. A single character is
    now measured and drawn as a glyph (`get_char_size`, `draw_char`), which needs no shaping. The same glyphs land in
    the same places (`cockpit3d_display.gd _text`).
  - **The aircraft definitions read from disk: about 0.5 ms.** Modern IAF's `airframe_def` read and parsed the jet's
    JSON file on every call, before it looked in its cache: 16 reads a frame from the air-defence and AI loops. The
    cache is now looked at first (`sim_settings.gd`).
  - **The moving map clipped off screen: about 0.4 ms.** The HSD's colour map (and the 2D MFD's TSD and the F-35I's
    TSD) clipped every map polygon against its window each frame: 187 clips a frame, now 82. Each polygon keeps its bounds
    (`cockpit.gd tsd_map` "box"), and a polygon whose bounds miss the window is skipped. The picture is the same.
  - **What is left** is spread thin: the per-frame flight states (`IafFlight.state`, 34 calls), the Rust missile
    envelopes (`dlz`) and the jets' lists the sites, the AI and the radar each build. None costs more than about
    0.3 ms.
- **GPU cost**: a real render at 1,920 × 1,080 with the default settings, the camera chasing Kidon 1-3 from 30 m. Each
  part is compared shown against hidden, by turns, because the fight keeps moving:
  - the whole scene: 19.5 ms GPU, 31.7 ms a frame, measured before the CPU fixes above, when the CPU limited the frame;
  - the chased jet, which fills much of the screen: 1.38 ms;
  - each other AI jet: 0.037 ms;
  - each ground unit or drone: 0.014 ms (18 of them).

  Distant units cost little to draw, so a far-distance model cut would gain almost nothing.
- **Tests:** `modern-iaf/tests/test_big_fight.gd` (headless, 420 s of sim time). It checks that the four orders are
  taken, at least one missile flies each way, a kill happens, no AI jet hits the ground, none is stuck and the based
  pair gets airborne. It prints the CPU figures and the missiles by shooter and target.
  The video comes from `modern-iaf/tests/_big_fight_movie.gd`: the same scenario under Godot's movie writer, with a
  scripted camera director. Each shot lasts 5 to 9 s (a missile's up to 12 s, Kidon 1-2's run up to 14 s); it picks, in this order:
  1. a missile just launched: its launcher, then its target with the missile coming in;
  2. Kidon 1-2's attack run;
  3. the based pair's start;
  4. in turn: a jet with its nearest enemy ahead, the convoy, a drone, the S-300.

  `BIGFIGHT_BENCH=1` gives the GPU figures. The site, drone and convoy nodes count their own CPU time (`cost_us`),
  as `ai_flights.gd` does.

## 23. Modern IAF's Scramble: the player's quick fight (ours)

Scramble (Hebrew הזנקה) is the front end's quick fight: the player's flight takes off, or starts in the air, against
an enemy drawn at random, and the AWACS gives the task by radio. It is the player's own scramble; an enemy pair's
alert launch from its base is the enemy's scramble of §18.3, a separate thing that Scramble's roll may include.

The user, 22 November 2026, approving the order of the AI jobs ("Ok follow your suggested order"), whose last item was
free combat: a small front-end setup, then fly; not a mission (modern-iaf/docs/plan.md: no missions or campaign yet).
On its first version (A81, 24 November 2026): "1. call it "Scramble" and הזנקה in hebrew. 2. where is based on the
plane they choose, right? 3. by default, start in-air, with awacs calling or giving orders what to bomb. 3. too much
enemy options, should be some random selection." On the second (24 November): "why we choose area if in all other
places the area is tied to the airplane? why we choose a enemies skill if that already by pilot?", then "allow it to
start in cold, runway or in air". The Scramble screen (modern-iaf/docs/front-end.md §2.1) picks the flight and the
start; the area is drawn, the skill is the Pilot screen's. Every distance and time here is ours (inferred).

- **The start.** Each jet has one Scramble start (modern-iaf/data/missions/`<base>_free.json`, category `fly_now`):
  a flight of four parked cold at the jet's home base, the base of the jet picked in the Hangar. Fly cuts it to the
  flight picked (alone, a pair, a four-ship; `flight/fly.gd prepare_free`): the jets after it leave the formation and
  the mission. The default start is in the air (`air_start`, below; `IafMissionEdit.set_flight` moves the flight
  there, the start rule of §7.1 makes it airborne with its engines running). The runway start (`runway_start`, below)
  lines the flight up on the home base's runway with the engines running, and the flight takes off in pairs
  (`ai_flights.gd flight_pairs`, §8.7). The cold start stays at the parking spots.
- **The rules** (`iaf_ai::free_combat`, `IafFreeCombat`):
  - `roll(seed, skill)`: the task first, each of the four alike: intercept the MiG-29 pair on CAP, intercept the
    drones, attack the convoy, attack the S-300 battery; then the task's target; then one more threat per enemy skill
    level (§17: low one, medium two, high three), each drawn alike from those with room: a MiG-29 pair on CAP (two at
    most), a pair on alert in the area's shelters (two at most; it brings the S-300 network, whose vector scrambles it,
    §18.3), the network, the short-range sites, the drones, the convoy. Fly draws a new seed (`Settings.free_combat`
    `seed`); the same seed and skill draw the same enemy.
  - `area(seed, home, bases)`: the fight's base A, drawn at Fly from the same seed, alike among the theatre's bases
    other than the home base within 180 km of it (a short sortie; every base has at least two in reach), the nearest
    other base when none is.
  - `plan`, round the area's base A, the player's base H, u the direction from A towards H: the S-300PMU-2 battery 12 km
    beyond A with its own point defence, a Tor-M1 1 km from its centre towards H (a long-range battery has a short-range
    missile system at its site: modern-iaf/docs/research/enemies.md §2.7), its 83M6E2 network's 64N6E2 8 km beyond and 3
    km aside, the 54K6E2 beside it; the short-range sites (a Tor-M1, a pair of ZSU-23-4s 200 m apart, an Igla team) at
    the convoy's middle, else 4 km aside of A, all in the network when there is one; each MiG-29A pair on CAP 25 km from
    A towards H, 12 km to either side, 6,000 m above A (the second pair 1,000 m higher), facing H; each pair on alert in
    A's shelters (the first pair in the first two, the second in the next two: `enemy_base`'s `first`), its station 15
    km from A towards H; a convoy of two T-72s and two Ural-4320s 12 to 4 km from A towards H, 6 km aside, on the roads
    nearest its ends; a salvo of four Shahed-136s from 80 km beyond A over A to H, 10 s apart.
  - `air_start(home, area, bases, count)`: the lead 60 km from A on the line towards H (beyond H when H is nearer),
    moved out in 2 km steps until 8 km clear of every base (the start rule takes a start within 5 km of a base for a
    ground start), 6,000 m up, heading for A; each wingman 150 m further back per place and 150 m to alternate sides
    (as `ai_flights.gd flight_in_air`). The flight's route is one point over A.
  - `runway_start(lineup, heading, count)`: the lead on the home base's lineup point facing down the runway
    (iaf.ibx `RunwayNumber`), Kidon 1-2 15 m to its left (the pairs take-off's `PAIR_M`, fingertip's side), the
    second element 60 m behind, Kidon 1-4 15 m to the right of Kidon 1-3: every jet within the start rule's 100 m of
    the lineup point, so every engine runs (§7.1).
  - `task_call(task, callsign, player, target)` and `task_due(airborne_s, since_s)`: the AWACS's task call, template
    `AWX_TASK` ("Kidon 1, attack the convoy, bearing 040, 25 miles, free to engage"): the callsign, the task, the
    bearing (in tens, as the contact calls of docs/radio.md §4), the distance in nautical miles (1 to 10, then fives
    to 50, tens to 90), then "free to engage". It comes 5 s after the player's jet first leaves the ground (so an air
    start hears it at once, a ground start after take-off) and every 60 s after, about the task's target nearest the
    jet, until every one of them is down. The AWACS's contact calls (docs/radio.md §4) go on beside it. The words of
    the four tasks and the Hebrew lines are ours (modern-iaf/docs/research/radio-terms.md).
  - The start time (the user, 25 November 2026: "do a specific military time to choose", "And random"): minutes
    after local midnight on the five-minute grid (`time_valid`, `time_step`: an hour or five minutes, round the
    clock), shown HHMM (`clock`); `start_time(seed, random, min)` flies the set time, or with Random one drawn from
    the Scramble's seed, alike over the day's 288 five-minute steps (its own draw, apart from the area's and the
    roll's). The flight starts at it on the date (`day_of_year`) with Israel's clock of the day (`utc_offset`: 3
    hours ahead of UTC from the Friday before March's last Sunday to October's last Sunday, Israel's Time
    Determination Law of 2013, else 2): modern-iaf/docs/front-end.md §2.1.
  - The date (the user, 25 November 2026: "Maybe we should add season, or date also?"): a day of the current year
    (`year_days`, `month_day`), stepped by a day round the year or a month with the day cut to the month's last
    (`date_step`); `start_day(seed, random, year, doy)` flies the set day, or with Random one drawn from the seed
    alike over the year's days (its own draw). Neither the time nor the date is stored ("No need to remember last
    choice", the same day): each opening of the screen starts with both on Random ("by default both should be
    random"), 0800 today under them.
- **In flight** (`modern-iaf/flight/free_combat.gd`, a child of `sim_flight.gd` on a Scramble start): once the ground
  under the jet is loaded it rolls the enemy at the pilot's enemy skill and places the plan in order (the sites, the
  network, the fighters vectored by it, the convoy, the drones), all at that skill (§17). A based pair stands in the
  area's base, as `enemy_base` allows (the sim has no enemy base). Then it says the task calls through the radio
  (`radio.gd say`, subtitled). On the air start the flight's own calls (contact, spike: `radio.gd flight_call`) wait
  until the first task call is said (`radio.gd hold_calls`), then follow it in order, so the AWACS speaks first
  (2026-11-24: the wingman's contact calls came before it and its subtitle waited behind theirs, about 15 s in).
  Nothing is scored; the flight ends from the pause menu.
- **Not started** (outside the user's words of 24 November): a call when the task is done, the task's choice by the
  player. The full AWACS (the requests, the Eitam in the sky) is §24.
- **Tests:** `cargo test -p iaf-ai --lib free_combat` (the area: never home, in reach, every base in reach drawn; the
  runway start's places; the start time: HHMM, the steps round the clock, Random by seed over every hour, the day of the
  year, Israel's summer time; the date: month and day, the steps round the year, the month's last day, Random by seed
  over every month; the roll: a seed draws the same enemy, the task's target always there, alert pairs with the network,
  the threats by skill, every task drawn; the air start clear of the bases, the wingmen's places; the call's words and
  timing; the layout faces the player, the order, the battery's Tor at its site, the ZSU pair, the second alert pair's
  shelters); `modern-iaf/tests/test_free_combat.gd` (the screen en + he; Ramon's start in the air round Hatzerim with
  the roll placed and the task call said before the flight's calls; the area drawn from Ramon; the runway start lined up
  with both engines running; the same start on the ground, cold at Ramon; the Time and Date rows en + he: 0800 today
  first, the steps, Random, 0800 today again on the next opening, nothing stored; a 2200 start at night on 21 December,
  the notebook's time and date; 0630 dark in December, day in June).

## 24. Modern IAF's AWACS: the controller and the Eitam (ours)

The user, 25 November 2026, picking "Full AWACS" from the features never started; his earlier words: the AI plan's
Q12, 19 November 2026 ("a controller that answers requests (picture, bogey dope, declare, vectors) PLUS an Eitam
flying in the sky that the enemy can target, from the start", "Plus Eitam in the sky now"); the radio menu, 19
November ("3 will be AWACS"); the wingmen and other flights "response to AWACS" (§8.8). On the Eitam's place, 25
November 2026: "The eitam should be in the sky in makes sense place - where it not directly in the middle of the
flight. It's ai should know to run away if needed or call for help". The 1998 game is unchanged: its AWACS calls stay
`fctrl.rs`'s (docs/radio.md §4). Every figure not footnoted is ours (inferred).

The rules are Rust: the controller `crates/iaf-ai/src/awacs.rs`, the Eitam `crates/iaf-ai/src/eitam.rs`, both behind
gdext `IafAwacs` (`crates/iaf-godot/src/awacs.rs`). `shared/audio/radio.gd` asks and says; the radio menu
(`modern-iaf/flight/sim_flight.gd`) offers the requests.

### 24.1 The controller's sensor

- **The Eitam's radar** where the flight has an Eitam (§24.3): the EL/W-2085 tracks "to a range of 243 nmi (450
  km)"[^w-elw2085], in sight over the earth's curvature (the sites' radar horizon on the 4/3 earth, `site::visible`,
  at sea level: the terrain under a far contact is not loaded). From 41,000 ft its own horizon is about 460 km, so at
  its height every contact inside its range is in sight; lower, a low contact far out is under it.
- **The virtual AWACS** where the flight has none (the training missions, the range): the 1998 game's sphere round
  the player, 96.3 km (`fctrl.rs`).
- **Neither** once the Eitam is shot down: the service ends. The radio menu's AWACS page (§24.5) shows every request off
  (dimmed), the contact calls stop and the data link loses the
  AWACS's tracks (§24.4).
- Both see an aircraft only above the terrain + 175 m, the floor of the 1998 contact calls and of the data link
  (`fctrl::CONTACT_AGL`), so the picture, the calls and the HSD agree.
- **Identity**: an enemy the player's side knows (the contact calls' `known`) is hostile, another enemy a bogey, our
  own friendly (NATO HOSTILE, BOGEY, FRIENDLY[^brevity]).

### 24.2 The requests and the answers

The radio menu's third line (AWACS) opens the controller's page (§24.5). Each request is the pilot's call, the radio's
gap, then the controller's answer in the AWACS voice with its subtitle. The words are NATO brevity[^brevity]; the
controller answers in the BRAA form, the bearing, range, altitude and aspect from the requester ("Provides target
BRAA relative to the specified FRIENDLY aircraft"[^brevity]), since the sim has no bullseye.

| request | NATO meaning[^brevity] | the answer |
|---|---|---|
| Picture | "A request to provide information pertinent to the mission" | "Kidon 1, two groups." then each group, the nearest three: "Group bearing 040, 30 miles, 20 thousand, hot, hostile." Nothing seen: "Kidon 1, clean." |
| Bogey dope | "Request for information on indicated or closest GROUP in bearing, range, altitude, and aspect (BRAA) format" | the nearest group: "Kidon 1, group bearing 040, 30 miles, 20 thousand, hot, hostile.", else "Kidon 1, clean." |
| Declare | "Inquiry as to the ID of specified track(s)"; CLEAN among its answers | the player's radar's locked track: "Kidon 1, hostile." / "bogey." / "friendly."; a track the sensor does not see: "Kidon 1, clean." Off without a lock: "Lock a target to ask for its identity" |
| Vector to target | VECTOR: "Alter heading to indicated" | "Kidon 1, vector 040, 25 miles, target.": Scramble's task target (its nearest, as the task call), else the nearest hostile group; none: clean |
| Vector home | HOME PLATE: "Home airfield or ship" | "Kidon 1, vector 220, 60 miles, home plate.": the flight's home base |
| Vector to tanker | | "Kidon 1, vector 130, 40 miles, tanker.": the nearest friendly tanker (§25: an entity marked `tanker`); with none on the flight the line is off: "No tanker in the air" |
| Check in | a plain-language call: the pilot joins the controller's net | "Kidon 1, radar contact.": the pilot joins the controller's net (a training lesson grades it first of the requests, modern-iaf/docs/training.md §16.9) |
| Judy | JUDY: "Aircrew has taken control of the intercept and only requires situation awareness information"[^brevity] | "Kidon 1, copy.": the hand-off of the intercept to the pilot; never refused but with the Eitam lost |

- **The words.** A group is any contacts within 3 NM of each other ("Any number of air CONTACTS within 3 nautical
  miles in azimuth and range of each other"[^brevity]; `sort::groups`, as the sort's); hostile when any of its
  contacts is, else a bogey; its height the highest contact's. The bearing in tens as the contact calls'
  (`fctrl::tens`). The range in nautical miles, truncated: 1 to 10, fives to 50, tens to 150, fifties to 250. The
  height in thousands of feet, rounded: 1 to 10, fives to 50. The aspect by the angle off the group's nose of the line
  to the requester, the brevity's "from nose" bands: HOT 0–30°, FLANK 31–70°, BEAM 71–120°, DRAG 121–180°[^brevity].
  A picture says the number of groups (up to nine) and describes the nearest three (inferred: the call stays short).
- **The flight hears it.** Each group the answer names goes to the flight AI as a contact call does (`Flight::awacs`,
  §8.8): the first AI jet holding it reports "contact".

The Hebrew lines (every line has one; IAF radio words are not public, so most are ours, around the words the Hebrew
writing on the subject uses):

| English | Hebrew | source |
|---|---|---|
| the Eitam; its crew | עיטם; בקר מוטס | sourced: "\"עיטם\" (גאלפסטרים G-550) שמו", "במטוס ה"עיטם" יושבים הבקרים המוטסים"[^jdn-eitam] |
| picture | תמונת מצב | the user, 25 Nov 2026: "תמונה אווירית shuld be תמונת מצב" (before: תמונה אווירית, after "אחראי על יצירת התמונה האווירית"[^hamichlol-control]) |
| group; two groups | מבנה; שני מבנים | the pilots' word for a formation ("חזרתי למבנה"[^walla-dogfight]) applied to the enemy's: ours |
| hostile | עוין | sourced: "כלי-טיס עוינים ומטוסי אויב"[^jdn-uav] |
| bogey | לא מזוהה | second-hand: "כלי טיס בלתי מזוהה" (a search engine's quote); the contact calls' "מגעים לא מזוהים" |
| friendly | ידידותי | second-hand: "לזהות כלי טיס ידידותי" (Hamichlol on IFF) |
| clean | אין מגעים | ours around the sourced מגע ("יצרנו מגע מכ"מי ראשוני"[^ynet-uav]) |
| hot; flank; beam; drag | מתקרב; באלכסון; בניצב; מתרחק | ours |
| bogey dope | המגע הקרוב | ours around מגע |
| declare | זיהוי | sourced as the word: "היכולת לזהות ולסווג מטרות"[^jdn-eitam] |
| vector 040 | כיוון אפס ארבע אפס | the user, 25 Nov 2026: "הכוונה shuold be כיוון, in all places" (before: הכוונה, after "בוצע היירוט הראשון בהכוונת בקר"[^hamichlol-control]); the call's form ours |
| target; home plate; tanker | מטרה; בסיס האם; מטוס התדלוק | מטרה sourced (§8.8); the others ours (the IAF's 707 tanker is "ראם", second-hand, a name not a word) |
| threat; Eitam retrograding; commit | איום; עיטם בנסיגה; יירוט | יירוט sourced ("במטרה ליירט אותם מוקדם ככל האפשר"[^jdn-eitam]); the others ours |
| 20 thousand | גובה עשרים אלף | ours (רגל left out, as the English "feet") |

### 24.3 The Eitam in the sky

The IAF's Eitam is the Gulfstream G550 with the EL/W-2085 (the CAEW)[^w-elw2085][^w-g550]. It flies as the other AI
aircraft do (since 25 November 2026, the coordinator's "close that too: build its flight from the public G550
figures"): its 6-DoF (`sixdof::jets::g550`, modern-iaf/docs/flight-model.md §9.22: TP-1538's tables on the G550's
wing, its weights, two BR710s and its limits; type 1021, the aircraft definition `shared/extra/planes/eitam`) under the
autopilot's steer loop (`MODE_STEER`), to a point 20 km along the heading it wants at 41,000 ft. Its turns, climbs and
speed changes are the G550's; before, it was a point mass turned and sped up at fixed rates.

| figure | value | source |
|---|---|---|
| height | 41,000 ft | the G550's cruise altitude: "Long Range Cruise: M0.80 at 41,000 ft"[^w-g550] |
| speed on station; retreating | Mach 0.80 (236 m/s); Mach 0.85 (251 m/s) | the long-range and the high-speed cruise[^w-g550] |
| span, length | 28.50 m, 29.39 m | [^w-g550] |
| turns | 25° of bank (the steer loop's load factor 1 / cos 25°): 1.1°/s at Mach 0.80 | inferred |
| speed | the steer loop's speed law at military power at most, its error summed into the asked speed (0.15 /s, while the lever is inside its travel): the loop's own law alone held it 12–15 m/s fast | inferred |
| fuel on station | 12,000 kg | inferred |

- **The station** (`eitam::station`): the user's "not directly in the middle of the flight". Along the line from the
  fight's area to the flight's home base, the rearmost of the base and the flight's start (an air start beyond the
  base), then 40 km further back and 30 km to the left of that line, at 41,000 ft. So it never flies on the flight's
  way to the fight nor over it, and the fight stays well inside its radar (Scramble's area is within 180 km of the
  base: at most about 230 km). The orbit is a racetrack of 50 km legs across the axis to the fight, flown out and
  back, the turns at 25° of bank (about a 12 km radius).
- **The threat** (NATO THREAT, "Untargeted HOSTILE, BANDIT, or BOGEY is within a briefed range of a FRIENDLY
  aircraft"[^brevity]): a hostile group its own radar sees within 100 km pointing at it (hot or flank), or within 50
  km whatever it does.
- **The retreat** (RETROGRADE, "Withdraw(ing) while executing defensive procedures in response to a threat"
  [^brevity]): it turns away from the threat at Mach 0.85; the threat's start moves its station to 60 km from the
  planned one, away from the threat (always from the planned one, so two threats never add up). 30 s clear, it goes
  back on that station at Mach 0.80.
- **The call for help**, at the threat's start and every 60 s while it lasts, to the player's flight with the threat
  as BRAA from the player: "Kidon 1, threat, group bearing 040, 30 miles, 25 thousand, Eitam retrograding, commit."
  (COMMIT: "Intercept the GROUP(S) of interest"[^brevity]). The player sends the flight with the Wingmen page
  (engage, weapons free); the AI jets holding the group report "contact" (§24.2).
- **A target.** It is a friendly aircraft in the world: the enemy fighters, the network and the sites see and attack
  it as any of ours; shot down, the controller's service ends (§24.1).
- **Where it flies**: on Scramble (§23), placed with the flight (`free_combat.gd place`, `shared/ai/eitam.gd`).
  Other flights (the training missions) have none: the virtual AWACS serves them.
- **In the game** (`shared/ai/eitam.gd`): a mission entity `eitam` of the player's side, class 3 (a fixed-wing
  mover), strength 300 (our damage scale's fighter: one missile brings it down; inferred), its half span 14.25 m for
  the gun's hit test, its radar cross-section 10 m² from the front, 40 m² from the side, 15 m² from behind (a
  business jet's, larger than a fighter's: inferred, no public figure; `eitam::RCS`). The enemy's radars, sites and
  fighters take it as any of ours (`air_defence.gd jets`, which now reads an entity's own `rcs` first: the Eitam's and the drones', so our
  side's AI picture now sees a drone with its 0.01 m² rather than none). Its call for
  help is said by the radio, and the group it names goes to the flight AI as a contact call does. Its entity
  destroyed, `IafAwacs.eitam_down` ends the service.
- **Model** (`Gltf.UNITS` "EITAM", `shared/extra/models/eitam/eitam.glb`): our own low-poly model
  (`tools/eitam/eitam.py`, Blender, 2,384 triangles), true length and span (29.39 m, 28.50 m[^w-g550]); the rest matched
  side by side to public photographs of the IAF's CAEW from the same angles (inferred; 25 November 2026, the user:
  "The eitam looks strange, only white. look online for pics, look for a better model"): 537 at Le Bourget
  2008[^c-537], 569 at Aero India 2009[^c-569] and 537 in flight in 2015[^c-537-2015]. The CAEW's long drooped nose
  radome, the bulbous tail radome under the fin, the flat side cheeks of the L-band arrays from behind the cockpit to
  over the wing, the belly blister; the G550's swept wing with winglets, its T-tail with the satcom bullet on top and
  the two engines high on the rear fuselage. The photographs show it white, not grey: white with the radomes a shade
  greyer, the blue cheatline from the cheek's lower aft corner up to the fin, the IAF roundel on the fin, the nacelles
  and the wings, the serial 537 on the fin and ISRAEL AIR FORCE on the cheeks (`tools/eitam/markings.png`, ours).
  The flight deck (the user, 25 November 2026: "just the cockpit window is a but strange"): the G550's six windows,
  two windshield panes and two side windows a side, dark glass in a thin grey frame with the white posts between
  them, their corners read off the Le Bourget photograph overlaid from the same camera; the nose's upper sections
  squared off there (a flat windshield on rounded shoulders) and its crown falling steeply to the radome's low tip, as
  the photograph's profile shows. No cabin windows: the cheeks cover them on the CAEW. The cheeks start 2 m behind
  the flight deck and ISRAEL AIR FORCE sits forward on them (the user, the same day: "in the real jet the things added
  to the fuselage go further forward"), matched to the Le Bourget photograph through a camera fitted to it.
  The skin's white and radome grey are one material coloured per face corner (a colour attribute): Godot stores each
  surface's vertex positions compressed to that surface's own bounds, so two materials meeting on one edge opened a
  hairline crack where the radome met the white under the windshield (fixed 25 November 2026). Drawn without its gear
  (it never lands in the sim). No free G550 CAEW model was found (Sketchfab, FlightGear, CGTrader, 25 November 2026): only plain Gulfstreams, which would need the same radomes.

### 24.4 The data link and the contact calls

The data link's AWACS tracks (`datalink.rs`, the HSD and the FCR) and the contact calls (`fctrl.rs` scan) take the
controller's sensor: the Eitam's radar where it flies (the contact calls still call contacts within 35 NM of the
player, the 1998 rule), nothing once it is lost; the virtual sphere where the flight has none, as before
(`radio.gd _awacs` and `ews.gd link_update` ask `IafAwacs.sees`; `datalink::Unit::seen` carries its word).

### 24.5 The radio menu's AWACS page

The first page's third line, AWACS (the same in Hebrew, the game manual's term), opens the page
(`sim_flight.gd` `AWACS_ITEMS`): 1 Picture, 2 Bogey dope, 3 Declare, 4 Vector to target, 5 Vector home, 6 Vector to
tanker, 7 Check in, 8 Judy (Hebrew: תמונת מצב, המגע הקרוב, זיהוי, כיוון למטרה, כיוון לבסיס, כיוון למטוס התדלוק,
כניסה לרשת, Judy: no Hebrew word for JUDY was found, searched 28 November 2026, so it stays in Latin letters). A request that
cannot be made now is dimmed and takes no click (`radio.gd awacs_refusal`, `IafAwacs.refusal`: the Eitam lost, no
radar lock for Declare, no tanker, no home base); no line says why (the user, 25 Nov 2026: "no need to write why
something is disabled, this goes in game manual"), the game manual's AWACS section does. A pick is the pilot's call, printed in both languages and said by the pilot's voice ("Eitam, Kidon 1,
picture": `PILOT_CALL` with `EITAM_P` and `REQ_AWX_*`; Kidon 1's whole call one English clip), the radio's gap, then
the answer (`radio.gd awacs_request`), recorded as a `radio` event `awacs:<request>`. Scramble's task target comes from
`free_combat.gd task_target` (`radio.gd awacs_task`); the home base is the mission's base (its lineup point).

**The voices** (`voices.json`; [../modern-iaf/docs/sound.md](../modern-iaf/docs/sound.md) §3): the answers in the AWACS
voice, a man or a woman by the flight's cast (Kokoro `am_fenrir` or `af_bella`; Hebrew `jonathan` or `yael`), each word a particle: `AWX_GROUP_W`, `AWX_CLEAN`,
`AWX_GROUPS1`–`9`, `AWX_ALT01`–`10` and fives to `AWX_ALT50`, the aspects, the identities, `AWX_VECTOR010`–`360`,
`MILES100`–`150` by tens with `MILES200` and `MILES250`, `AWX_HOME_PLATE`, `AWX_TANKER`, `AWX_THREAT`,
`AWX_RETROGRADE`, `AWX_COMMIT`, `AWX_RADAR_CONTACT`, `AWX_COPY`; the templates `AWX_PICTURE`, `AWX_GROUP`, `AWX_BRAA`,
`AWX_CLEAN`, `AWX_DECLARE`, `AWX_VECTOR`, `AWX_HELP`, `AWX_CHECKIN`, `AWX_COPY`. The pilot's `EITAM_P` and the eight
`REQ_AWX_*` in the pilot's voice (Hebrew `ariel` or
`shira`).

### 24.6 Tests and status

`cargo test -p iaf-ai --lib -- awacs` (the words: miles, thousands, aspect; the picture and the bogey dope from
the virtual sphere and from the Eitam; the Eitam's reach and horizon; declare with and without a lock, the vectors,
the refusals, a lost Eitam); `cargo test -p iaf-ai --test eitam` (on its 6-DoF, with the sim's own data: the station
off the flight's way with the fight in reach for an hour, its 25° turns, its height within 5 m and its speed within
1 m/s; the threat, the call for help, the retreat at Mach 0.85, the call again after a minute, the return to the
long-range cruise; a downed Eitam silent);
`modern-iaf/tests/test_awacs.gd` (Ramon's Scramble start in the air with a known MiG-29A 20 km ahead: the AWACS page en
+ he, Declare and the tanker off with their reasons; picture, bogey dope, the vectors to the target and home said
after the pilot's call; the wingman's "contact"; the Eitam at 41,000 ft and Mach 0.80 off the flight's way with the
fight in its radar, an entity of our side; a known MiG 40 km from it: one call for help and the retreat at Mach 0.85;
the MiGs on the data link; shot down: every request off, no answer, no AWACS track, no
contact call); `cargo test -p iaf-avionics --lib -- datalink` (the controller's word over the link's own query).

Status (25 November 2026): built whole: the controller and its page with the voices, the Eitam in Scramble with its
model, as the enemy's target, the data link and the contact calls on its radar; its G550's 6-DoF (25 November 2026,
modern-iaf/docs/flight-model.md §9.22). Open: an AI-led flight's commit on the call for help (no friendly AI-led flight flies: an AI lead never fights, §8.8).

## 25. Modern IAF's tanker and the wingmen's air refuelling (ours)

The tanker, its boom operator and the receivers are designed in
[modern-iaf/docs/research/air-refuelling.md](../modern-iaf/docs/research/air-refuelling.md) §8 (sources there). The AI's
part (`crates/iaf-ai/src/tanker.rs`, `flight.rs`; `shared/ai/tanker.gd`):

- **The tanker** flies its racetrack as a path (`Track::at`: 480 kt true at 30,000 ft, 50 NM legs 20 NM apart, left
  turns at 18.6° of bank eased in and out at 5° a second). It is a friendly entity of the mission runtime (key
  `tanker`): the radar's units see it.
- **The boom operator** (`Tanker::work`) serves the first receiver of its queue: cleared to contact after 2 s held at
  pre-contact with its receptacle ready; the boom flies to a receptacle within 1.5 m of the contact position closing at
  under 0.5 m/s, at 6° a second and 1.5 m a second, and latches within 0.15 m; disconnect on the envelope's limits,
  the receiver's button or door, or the receiver full (under 5 kg of room: its last valve closed); breakaway inside the
  telescope's inner limit by 1.5 m or 5° above the upper elevation. After a disconnect the receiver goes back to
  pre-contact to be cleared again. The PDLs: one lamp a row, a step each 2.5° of elevation and 0.9 m of telescope.
- **The wingmen:** the lead's "refuel" (`Flight::command`) marks each AI jet addressed; the host asks the tanker for
  each in its number's order and hands it its station every frame (`Flight::set_refuel`, `Tanker::slot`): the left
  wing while it waits (observation), pre-contact, the contact position (moving there from pre-contact at 2.5 kt, research §4), the right
  wing once done. The jet flies the slot loop on the tanker as its leader, close, with the station's gains
  (`Autopilot::precise`: the along-track gain 0.3 in place of 0.08, the throttle's gain ×6, the spring 0.4 in place
  of 0.3; inferred: the formation's let a receiver lag 5 m and slide 2.4 m in the tanker's roll, out of the envelope).
  Once every wingman sent is done, all are let go together and rejoin the flight. A jet that has come within 20 NM of the
  tanker and flies 20 NM away again leaves its queue. Test: `crates/iaf-ai/tests/refuel.rs` (a 6-DoF Sufa from 2 km
  behind to full, the contact
  held into the tanker's turn), `modern-iaf/tests/test_air_refuel.gd` (the four-ship).
- **The recording** (`tanker.gd _record`): the boom operator's calls to the player's jet go into the flight's recording
  as `tanker` events (`call`: `cleared_precontact`, `cleared_contact`, `contact` with the tanks' room `room_kg`,
  `disconnect` with its reason `why` and the fuel given so far `kg`, `breakaway`, `complete`), with `joined` the first
  time the jet comes within 1 NM of the tanker (inferred); a training lesson grades them (modern-iaf/docs/training.md
  §16.9).
- **Its lights:** the navigation lights and the strobe of every Modern IAF jet (`NightLights.add_lights_on` on the
  model's outermost points), for the night tanker lesson.

## 26. Modern IAF's training fight against an aggressor (ours)

The training plan's air-to-air phase ([../modern-iaf/docs/training-plan.md](../modern-iaf/docs/training-plan.md) §3,
phase 7): "Drones are shot down for real. Against a jet, shots are simulated as in real training: the shot's call ("Fox
3"), the "kill" call, the killed jet leaves the fight, and "knock it off" ends the round" (the user, 28 November 2026),
and the BFM lessons' engagements each start from a set-up in the air. This section is the capability; no lesson places
it yet. The rules are Rust (`crates/iaf-ai/src/aggressor.rs`, gdext `IafAggressor`); the host is
`shared/ai/aggressor.gd`. Every figure is inferred unless a source is named.

- **The aggressor** is a Sufa of the enemy side (`ai_flights.gd spawn`, record `f16i`) flown by the enemy fighter's
  trees of §18 (the intercept, the shot, the dogfight's BFM leaf, the defence) at the High skill's tactics, the
  adversary tactics (`enemy_flight`'s `skill` 2, §17). Its flight's `vector` gives it the player's jet while the
  engagement runs, as a ground controller's vector: the pilots of a training fight know where the other jet starts.
- **The set-ups** (`aggressor::place`, round a centre and the player's heading):

  | set-up | the player | the aggressor | height, speed |
  |---|---|---|---|
  | offensive | 3,000 ft behind the aggressor (the user's example: "you at his six o'clock, 3,000 ft") | ahead, the same heading | 15,000 ft, 230 m/s |
  | defensive | ahead | 3,000 ft behind the player | 15,000 ft, 230 m/s |
  | high aspect | head-on 6 km apart, 450 m to one side | head-on, 450 m to the other side | 15,000 ft, 230 m/s |
  | BVR | head-on 40 NM apart | head-on | 20,000 ft, 250 m/s |

  A round flies its set-ups in turn (by default the three BFM ones), round again after the last. At each set-up both
  jets start again in the air there (the player's flight model and the aggressor's, `ai_flights.gd restart_in_air`, its
  IafAi made again round its new flight model) with their stores full.
- **Simulated shots.** Both jets are shielded (`ent.shield`: nothing hurts them). An air-to-air missile of either jet at
  the other (or at nothing), and every air-to-air missile of the player's with MASTER ARM at SIMULATE, is simulated:
  `player_weapons.gd launch_homing` flies it on the existing physical missile (its seeker, the decoys, the jammer) with
  no model, no sound, no launch warning and no damage; the defender knows of it by the radio's call, and the aggressor's
  tree defends against it as against a live one. At its burst, `aggressor::missile_kill`: a kill when it bursts within
  its blast radius of the other jet and is no dud. The gun's rounds fly against the shielded jets; three hits on the
  other jet are a kill (`GUN_HITS`: the 20 mm's power 100 against a fighter's strength 300 on the sim's damage scale). A
  shot at another unit, a drone, is live at ARM. With MASTER ARM at SIMULATE the player's air-to-air missiles and gun
  fire in a training fight (`player_weapons.gd _may_fire`; the gun's rounds then hurt nothing; bombs and jettisons stay
  safe); a missile of an engagement already knocked off kills nothing; the store's count goes down as for a live shot
  and comes back at the next set-up.
- **The calls** (`aggressor::Round`), NATO brevity[^brevity] with Hebrew subtitles
  ([../modern-iaf/docs/research/radio-terms.md](../modern-iaf/docs/research/radio-terms.md), eighth search): the
  shooter's "Fox one / two / three" at the launch (by the missile's guidance, as the wingmen's, §8.9) or "guns" at a
  burst's first round; "kill" 1 s after the killing burst (the burst stands for the brevity KILL's missile time-out);
  the aggressor's "knock it off" 3 s after the kill. The player's calls are said in the pilot's voice ("Kidon 1, Fox
  two", "כידון 1, שיגור"), the aggressor's in the wingmen's ("Red 1, kill", "אדום 1, הפלה"; the Hebrew voice of the
  cast's first wingman). New clips: `plt_fox1` … `plt_kio`, `flt_agr_red1`, `flt_wng_kill`, `flt_wng_kio`
  (modern-iaf/data/sounds/voices.json).
- **The killed jet leaves the fight:** its entity is `out`; `ai_flights.gd _bandits` leaves it out of every bandit list,
  and an aggressor out has no bogey: it flies back to its station's orbit.
- **Knock it off** ends the engagement: called by the aggressor after a kill, when the jets are more than 20 km apart
  (BVR 150 km), after 180 s (BVR 300 s) or when either jet is below the training floor (5,000 ft above the ground); or
  by the player, the key Shift + F4 (command 304; [controls.md](controls.md)). Both jets are out of the fight until the
  next set-up starts, 6 s later.
- **The dev hook:** `Aggressor.start(host, setups, at, heading)`; freeing the node unshields both jets
  (`shared/ai/aggressor.gd`): the round of `setups` (offensive, defensive, high_aspect, bvr) round `at` (world), the
  player heading `heading`.
- **Tests:** `cargo test -p iaf-ai --lib aggressor` (the set-ups' places, the missile's kill rule, the calls and their
  order after a kill, "guns" once a burst and the third hit, every way to knock it off and the next set-up);
  `modern-iaf/tests/test_aggressor.gd` (headless on the range: the defensive set-up, the aggressor's shot simulated and
  its kill called, the player out and the next set-up; the player's simulated missile from the offensive set-up and its
  kill; the player's knock it off; which shots are simulated).

## UNCERTAIN
Open questions in this document:
- The RWR field names behind conditions 19, 26, 27, 38, 39 (§13.2); what else writes brain+0x7c.
- The pitch law's tail (`5ca010`), the speed law's acceleration term, the formation loops' details (§8.5).
- Waypoint actions 1, 4, 5, 6; the sim clock origin of the waypoint times (mission start taken).
- The leader flag gating the wingman's take-off roll; the taxi re-placement's 60 m sign; what happens after parking
  (the root timer keeps running ParkInHangar).

[^faa-acs]: FAA, "Private Pilot – Airplane Airman Certification Standards" (FAA-S-ACS-6), Area of Operation V, Task A, steep turns, https://www.faasafety.gov/files/events/GL/GL03/2016/GL0369764/private_airplane_acs.pdf (the entry altitude held within ±100 ft; read as quoted by a search engine on 2026-11-22, second-hand).
[^apa-s300]: Carlo Kopp, Air Power Australia, "S-300PMU2 Favorit / SA-20 Gargoyle", updated to April 2012, https://www.ausairpower.net/APA-S-300PMU2-Favorit.html (the 83M6E2: the 54K6E2 command post and the 64N6E2 search radar, up to six batteries; the 40V6M "Semi-Mobile Mast System 24 Metre"; the 30N6E2 on a MAZ-79100 chassis; read 2026-11-19, 2026-11-22 and 2026-11-23).
[^w-s300]: Wikipedia, "S-300 missile system", https://en.wikipedia.org/wiki/S-300_missile_system (the 64N6 Big Bird: "a maximum detection range of 300 km", "a scan once every twelve seconds"; read 2026-11-21).
[^tc7100]: US Army, TC 7-100.2 "Opposing Force Tactics", 9 December 2011, chapter 11, https://www.govinfo.gov/content/pkg/GOVPUB-D101-PURL-gpo122554/pdf/GOVPUB-D101-PURL-gpo122554.pdf (§11-35 the cue's data, §11-36 units fighting with their radars off on the higher radars' data; read 2026-11-19).
[^mis-96l6e]: Missilery.info, "All Altitude Detector (VO) 96L6E", https://en.missilery.info/node/13476 (target detection range 5–300 km; read as quoted by a search engine on 2026-11-19, second-hand; the update in the all-altitude mode every 6 s at 0–1.5° and 12 s at 1.5–20°, read directly on 2026-11-23; the Doppler speeds "between ±30 and ±1200 m/s" in the all-altitude and low-altitude modes, read directly on 2026-11-25).
[^aerospaceweb]: Jeff Scott, Aerospaceweb.org, "Radar Cross Section", 21 March 2004, https://aerospaceweb.org/question/electronics/q0168.shtml (the head-on view most important; the largest returns from the sides; read 2026-11-19).
[^ni-f16]: The National Interest, on the F-16's Have Glass V paint, https://nationalinterest.org/node/112436 and https://nationalinterest.org/node/168141 ("the F-16 on average has a 1.2-square-meter radar cross-section, according to Globalsecurity"; second-hand: as quoted by a search engine on 2026-11-19; the site refuses automated reading).
[^migflug]: Max Grünwald, MiGFlug Afterburner, "F-22 Marble, F-35 Golf Ball: Where RCS Figures Come From", 8 November 2026, https://migflug.com/afterburner/?p=31823215 (GlobalSecurity's table: the F-35 at 0.0015–0.005 m²; GlobalSecurity itself refuses automated reading; read 2026-11-19).
[^ni-beast]: The National Interest, "The F-35 Has a 'Beast Mode' (But There's a Catch)", https://nationalinterest.org/node/180849 (external hardpoints "drastically increase" the radar cross-section; second-hand: as quoted by a search engine on 2026-11-19).
[^hamichlol-rwr]: Hamichlol, "מקלט התרעת מכ"ם", https://www.hamichlol.org.il/%D7%9E%D7%A7%D7%9C%D7%98_%D7%94%D7%9E%D7%96%D7%94%D7%99%D7%A8_%D7%91%D7%A4%D7%A0%D7%99_%D7%9E%D7%9B%22%D7%9D (a search radar's warning "ואחריה נעילה ומעקב"; read as quoted by a search engine on 2026-11-19, second-hand).
[^mako-102]: Mako, "pzm-magazine", on the 102 Squadron's air-combat training, https://www.mako.co.il/pzm-magazine/Article-1c3f6f796402d61027.htm (a good pilot "תוקף ומתחמק מטילי נ"מ"; read as quoted by a search engine on 2026-11-19, second-hand).
[^brevity]: Wikipedia, "Multiservice tactical brevity code", https://en.wikipedia.org/wiki/Multiservice_tactical_brevity_code (SPIKE, MUD, DEFENDING, BREAK, CONTACT, SPLIT, read 2026-11-19; GROUP, AZIMUTH, RANGE, SORT, TARGETED, WEAPONS FREE, read 2026-11-23; PICTURE, BOGEY DOPE, DECLARE, BRAA, BOGEY, HOSTILE, FRIENDLY, CLEAN, HOT, FLANK, BEAM, DRAG, VECTOR, HOME PLATE, THREAT, RETROGRADE, COMMIT, read 2026-11-25; KILL "In training, shooters are TALLY at assessed missile timeout", KNOCK-IT-OFF "Cease all air combat maneuvers, attacks, activities, or exercises (training use only)", FOX "Simulated or actual launch of air-to-air weapon", JUDY, read 2026-11-28).
[^w-shahed]: Wikipedia, "HESA Shahed 136", https://en.wikipedia.org/wiki/HESA_Shahed_136 (length 3.5 m, span 2.5 m, mass 200 kg, about 185 km/h; "typically fired in multiples from a launch rack"; "extra-low" altitude flight; read 2026-11-19).
[^csis-shahed]: CSIS Missile Defense Project, "Shahed-131 and 136", https://missilethreat.csis.org/missile/shahed-131-and-136/ ("approximately 180 km per hour"; read 2026-11-19).
[^ar-shahed]: Army Recognition, "Shahed-136 loitering munition kamikaze suicide drone technical data", https://armyrecognition.com/military-products/army/unmanned-systems/unmanned-aerial-vehicles/shahed-136-loitering-munition-kamikaze-suicide-drone-technical-data ("It can fly at an altitude from 60 to 4,000 m"; read 2026-11-19).
[^rusi-shahed]: Uzi Rubin, RUSI Commentary, "Russia's Iranian-Made UAVs: A Technical Profile", 13 January 2023, https://rusi.org/explore-our-research/publications/commentary/russias-iranian-made-uavs-technical-profile ("fly low and slow", "virtual nap-of-the-earth profiles", "a tilting truck-mounted container holding five UAVs", "low radar and thermal signatures"; read 2026-11-19).
[^nf-shahed]: 19FortyFive, October 2022, https://www.19fortyfive.com/2022/10/irans-shahed-136-kamikaze-drone-everything-you-need-to-know/ (radar cross-section "estimated here to average .01 square meters"; second-hand: as quoted by a search engine on 2026-11-19).
[^maarachot]: "מהפכת האימון האווירי המבצעי", Maarachot (the IDF's journal), https://www.maarachot.idf.il/media/0rbdlk3j/מהפכת-האימון-האווירי-המבצעי.pdf ("המיומנויות הנדרשות", "מצעיר למנוסה"; read 2026-11-21).
[^w-pd]: Wikipedia, "Pulse-Doppler radar", https://en.wikipedia.org/wiki/Pulse-Doppler_radar ("Rejection speed is selectable on pulse-Doppler aircraft-detection systems so nothing below that speed will be detected"; "usually set just above the prevailing wind speed (10 to 100 mph or 20 to 160 km/h)"; read 2026-11-21).
[^w-tor-pd]: Wikipedia, "Tor missile system", https://en.wikipedia.org/wiki/Tor_missile_system ("The target acquisition radar is an F band pulse doppler 3D radar"; "The target engagement radar is a G band/H band (later K band) pulse doppler radar"; read 2026-11-21; the Tor-M1 7,500 mm long, 3,300 mm wide, 5,100 mm high with the radar up, read 2026-11-22).
[^w-strela]: Wikipedia, "9K32 Strela-2", https://en.wikipedia.org/wiki/9K32_Strela-2 (the 2M: 9.8 kg, 72 mm, 500 m/s, 800–4,200 m, 50–2,300 m, receding 260 m/s, jets only from the rear, uncooled PbS seeker; "6–10 seconds" from the shoulder; the booster 0.5 s and the sustainer about 2.0 s; self-destruct 14–17 s; "flares proved to be a highly effective countermeasure against both versions"; read 2026-11-23).
[^w-igla]: Wikipedia, "9K38 Igla", https://en.wikipedia.org/wiki/9K38_Igla (10.8 kg, 72 mm, 570 m/s peak, 5.2 km, ceiling 3.5 km, approaching 320 m/s, receding 360 m/s; the 9E410 seeker in IR and UV; "much improved resistance against flares and jamming"; "capability to engage straight-approaching fighters (all-aspect capability) under favourable circumstances"; read 2026-11-23).
[^w-manpads]: Wikipedia, "Man-portable air-defense system", https://en.wikipedia.org/wiki/Man-portable_air-defense_system ("a target detection range of about 10 km (6 mi) and an engagement range of about 6 km (4 mi)"; read 2026-11-23).
[^w-zsu]: Wikipedia, "ZSU-23-4 Shilka", https://en.wikipedia.org/wiki/ZSU-23-4_Shilka ("the radar picks up many false returns (ground clutter) under 60 m (200 ft) of altitude"; read 2026-11-21; 6.535 m long, 3.125 m wide, 2.576 m high, 3.572 m with the radar up, read 2026-11-22).
[^ru-maz543]: Wikipedia (Russian), "МАЗ-543", https://ru.wikipedia.org/wiki/МАЗ-543 (the MAZ-543 / MAZ-7310: 11,657 mm long, 3,050 mm wide; read 2026-11-22).
[^c-64n6e2-maks05]: Wikimedia Commons, "S-300PMU2 64N6E2.jpg", by .:Ajvol:., MAKS 2005, public domain, https://commons.wikimedia.org/wiki/File:S-300PMU2_64N6E2.jpg (the 64N6E2 from its front left; read 2026-11-23).
[^c-64n6e2-maks03]: Wikimedia Commons, "S-300PMU2 64N6E2 radar, MAKS 2003.JPG", by Panther, CC BY-SA 3.0, https://commons.wikimedia.org/wiki/File:S-300PMU2_64N6E2_radar,_MAKS_2003.JPG (the MAZ-7910's front, its split cabs; read 2026-11-23).
[^c-favorit-maks05]: Wikimedia Commons, "S-300PMU2 complex.jpg", by .:Ajvol:., MAKS 2005, public domain, https://commons.wikimedia.org/wiki/File:S-300PMU2_complex.jpg (the 64N6E2 from its side, its array face on; read 2026-11-23).
[^c-96l6e-maks11]: Wikimedia Commons, "96L6E at the MAKS-2011 (01).jpg", by Doomych, public domain, https://commons.wikimedia.org/wiki/File:96L6E_at_the_MAKS-2011_(01).jpg (the 96L6E from its front right; read 2026-11-23).
[^c-30n6e2-maks09]: Wikimedia Commons, "30N6E2 MAKS 2009 -01.jpg", by Vitaly V. Kuzmin, CC BY-SA 4.0, https://commons.wikimedia.org/wiki/File:30N6E2_MAKS_2009_-01.jpg (the 30N6E2 on its truck from its front right; read 2026-11-23).
[^w-maz7310]: Wikipedia, "MAZ-7310", https://en.wikipedia.org/wiki/MAZ-7310 (the MAZ-7910 carries the S-300PMU-2; the MAZ-74106 the 64N6; read 2026-11-23).
[^ar-64n6]: Army Recognition, "64N6 Tombstone 64N6E 64N6E2", https://armyrecognition.com/military-products/army/radars/air-defense-radars/64n6-tombstone-64n6e-64n6e2 (a double-sided phased array, hydraulically raised, on a semi-trailer; "full 360-degree mechanical rotation every 12 seconds"; length 13.2 m; read 2026-11-23).
[^w-mzkt7930]: Wikipedia, "MZKT-7930", https://en.wikipedia.org/wiki/MZKT-7930 (12.7 m long, 3 m wide, 3.29 m high; read 2026-11-23).
[^w-ural]: Wikipedia, "Ural-4320", https://en.wikipedia.org/wiki/Ural-4320 (7,366 mm long, 2,500 mm wide, 2,715 mm high; top speed 82 km/h with the V8, 75 km/h with the V6; read 2026-11-22 and 2026-11-23).
[^shaw]: Robert L. Shaw, "Fighter Combat: Tactics and Maneuvering", Naval Institute Press, 1985, ISBN 0-87021-059-9 (pursuit: lead, pure, lag; the high and low yo-yo; the break and the guns jink; one-circle and two-circle fights; the flat and rolling scissors; the reversal and the overshoot; the extension (separation); energy height; closure control; the terms only, no figure taken).
[^lambeth-sead]: Benjamin S. Lambeth, "Kosovo and the Continuing SEAD Challenge", Aerospace Power Journal, Summer 2002, mirrored at https://ausairpower.net/APJ-Lambeth-Mirror.html ("the Serbs kept their SAMs defensively dispersed and operating in an emission-control mode"; "would periodically emit with their radars for 20 seconds and then shut down the radars"; "by remaining dispersed and mobile, and by activating their radars only selectively"; read 2026-11-25).
[^w-mig29]: Wikipedia, "Mikoyan MiG-29", https://en.wikipedia.org/wiki/Mikoyan_MiG-29 (the Shchel-3UM helmet-mounted sight; the German evaluation: "a lock on any target the pilot could see ... within the missile field of view, including those almost 45 degrees off boresight"; read 2026-11-25).
[^w-mig29-jam]: Wikipedia, "Mikoyan MiG-29" (the 9.13: "the installation of the L-203BE Gardenyia-1 jammer that was
  lacking on the initial 9.12 version"; read 2026-11-22): https://en.wikipedia.org/wiki/Mikoyan_MiG-29
[^w-jam]: Wikipedia, "Radar jamming and deception" ("The burn-through range is the distance from the radar at which the jamming is ineffective"; a self-protection jammer "essentially broadcasts its position") (read 2026-11-22): https://en.wikipedia.org/wiki/Radar_jamming_and_deception
[^crenshaw]: Dan "Crash" Crenshaw, "A2A Wingman Tactics", COMBATSIM.COM (the bracket: the lead on the left side of the formation "has the East man", the wingman on the right takes the west man; read 2026-11-23): https://combatsim.com/archive/htm/htm_arc5/wingman1.htm
[^barton]: Peter "Faust" Barton, "Simulation Tactics and Communications III", COMBATSIM.COM, 1998 ("Sorting should always be done by the flight leader"; the bandits numbered "from nearest to farthest and left to right"; read 2026-11-23): https://combatsim.com/memb123/archive/htm/htm_arc5/voicecom5.htm
[^mako-cover]: Israeli press on the IAF's rescues, fighters "שחיפו על החילוץ" (read as a search engine's summary on 2026-11-22, second-hand: the summary tied the quote to no single page).
[^w-t72-speed]: Wikipedia, "T-72" (infobox: 60 km/h; read 2026-11-23): https://en.wikipedia.org/wiki/T-72
[^fhwa-convoy]: FHWA Office of Operations, "Coordinating Military Deployments on Roads and Highways", Appendix B. Military Convoy Movement Facts ("vehicle intervals of 300 feet or more and speeds in excess of 25 mph"; read 2026-11-23): https://ops.fhwa.dot.gov/publications/fhwahop05029/appendix_b.htm
[^cnatra-parade]: CNATRAINST 1542.154 (2003) and CNATRAINST 1542.61L (2006), Parade / Fingertip: "wingtip separation of 4 feet to 10 feet" (second-hand: a search engine's quote, read 2026-11-24): https://navyflightmanuals.tpub.com/1542.61L_wch1/Parade-Fingertip-1542-61L_Wch10166-166.htm
[^p1213-parade]: CNATRA P-1213 (draft), Flight Training Instruction T-45 advanced, Parade Turns: "rolling into 30 degrees AOB at the parade rate of roll" (read 2026-11-25): https://navyflightmanuals.tpub.com/Draft_P-1213/Parade-Turns-Draft_P-12130041-41.htm
[^p1213-cruise]: CNATRA P-1213 (draft), Cruise Position: the cruise position gives the section more maneuverability than parade, the lead not held to 30° of bank (second-hand: a search engine's quote, read 2026-11-25): https://navyflightmanuals.tpub.com/Draft_P-1213/Cruise-Position-Draft_P-12130050-50.htm
[^w-f16-span]: Wikipedia, "General Dynamics F-16 Fighting Falcon", specifications (span 32 ft 8 in, 9.96 m): https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon
[^w-elw2085]: Wikipedia, "IAI EL/W-2085" ("Up to 1000 targets can be tracked simultaneously to a range of 243 nmi (450 km)"; Israel's G550-based "Eitam"; read 2026-11-25): https://en.wikipedia.org/wiki/IAI_EL/W-2085
[^c-537]: Aeroprints.com, "537 Gulfstream G.550 CAEW Israel Airforce", Paris Le Bourget, 15 June 2008, Wikimedia
    Commons, CC BY-SA 3.0: https://commons.wikimedia.org/wiki/File:537_Gulfstream_G.550_CAEW_Israel_Airforce_(7337159024).jpg
[^c-569]: Sean D'Silva, "Gulfstream G550 Nachshon, Israel - Air Force", Aero India, 10 February 2009, Wikimedia
    Commons, GFDL 1.2: https://commons.wikimedia.org/wiki/File:Gulfstream_G550_Nachshon,_Israel_-_Air_Force_JP7469108.jpg
[^c-537-2015]: Zigi, "2015-04-23 IAF Israel Independence Day flyover - G550 AEW Aitam", Wikimedia Commons, CC BY-SA
    4.0: https://commons.wikimedia.org/wiki/File:2015-04-23_IAF_Israel_Independence_Day_flyover_-_G550_AEW_Aitam.jpg
[^w-g550]: Wikipedia, "Gulfstream G550", specifications (length 29.39 m, span 28.50 m; "Long Range Cruise: M0.80 at 41,000 ft"; "High Speed Cruise: M0.85 at 41,000 ft"; Israel's G550s "fitted with the EL/W-2085 sensor package"; read 2026-11-25): https://en.wikipedia.org/wiki/Gulfstream_G550
[^jdn-eitam]: JDN (from IAF material), "הכירו: האנשים שמזהים ומתריעים מפני איומים אוויריים הרחק מגבולות המדינה", 16 January 2024 (read 2026-11-25): https://www.jdn.co.il/news/2121657/
[^jdn-uav]: JDN, "חרבות ברזל: כיצד מיירטים כטב"ם אויב", 17 October 2023 (read 2026-11-25): https://www.jdn.co.il/news/2056122/
[^hamichlol-control]: Hamichlol, "מערך הבקרה האווירית" (read 2026-11-25): https://www.hamichlol.org.il/%D7%98%D7%99%D7%99%D7%A1%D7%AA_505
[^walla-dogfight]: Walla, "בלדה לקרבות אויר", 14 May 2010 (read 2026-11-25): https://www.walla.co.il/news/israel/1674210
[^ynet-uav]: ynet, Yoav Zitun, "הפלה בגיחה הראשונה: 'רשאי אש חופשית – המטרה הופלה'" (two F-15 pilots on downing a drone, with the radio audio: "יצרנו מגע מכ"מי ראשוני"; read 2026-11-25): https://www.ynet.co.il/news/article/ryZCtM5rD
