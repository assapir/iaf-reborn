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
returns at once when mode / arg / pose are unchanged (`5c8a70`), so **a running manoeuvre keeps running.**

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
  closest approach is 100 m; below 150 m over the ground never down, and not once the landing's ground watch is off. Without it two wingmen in fingertip came within 4.5 m in the lead's 80° bank break.
  A pull that stopped at 60 m (until 2026-11-19) left two AI jets 37 m apart. A prediction in straight lines (until
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

### 8.8 Ours: elements, the split, the reactions and the AWACS calls

Modern IAF's flight AI (`crates/iaf-ai/src/flight.rs`, [../modern-iaf/docs/ai-plan.md](../modern-iaf/docs/ai-plan.md)
F12–F14). The 1998 game sets none of it. Every figure is inferred, tuned on the 6-DoF Sufa (tests
`crates/iaf-ai/tests/four_ship.rs`, `modern-iaf/tests/test_four_ship.gd`, 19 November 2026).

- **Mode 0x21, the steer loop** (`MODE_STEER`, every 0.1 s): flies toward `Autopilot::steer.to` at that point's height.
  The heading error is flown as a turn rate of 0.3 per radian, at most the order's load factor; the height through a
  spring and a damper (0.15 rad/s, 0.8); both as a bank and a load factor (the slot loop's `lift_stick`, at most 75°
  and 7 g). The throttle is the speed law's, at most the order's (0.74, military: the afterburner stays out). The ground
  watch stays on. A far point is a heading; a near one is circled.
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
    260 m/s. Against infrared it stays at military power: the decoy rule's flares fail with the afterburner lit and
    work better above 4 g.
  - Each decision it asks for a decoy: chaff against a radar, flares against infrared. `ai_flights.gd` releases it
    through `combat.gd`'s path (the jet's stores, one each 4 s, `player_weapons.gd`'s decoy rule); nothing new about
    countermeasure or missile performance.
  - Its element mate (1 and 2, 3 and 4), an AI jet in the air and itself clear, sees a missile launched at its partner
    (the smoke) and calls `break_left` or `break_right`, the partner's turn. That covers the player as #1 too. A lock
    is heard only on the jet's own RWR, so it gets no mate's call.
  - Clear for 5 s, it goes back: a wingman rejoins its slot ("in position"), a lead its route.
  - Measured: the lock called and the beam flown 1.2 s after the lock; against an infrared missile behind it, the break
    left at up to 5.8 g with the throttle at most 0.74, flares, #4's `break_left` 1.4 s after the launch.
- **The AWACS calls** (`Flight::awacs`, `IafAi.awacs`; `radio.gd` passes each call of `IafFlightController.scan`,
  which now also returns {bearing, miles, code}). For a hostile or unidentified contact, the first AI jet by number
  that holds the called point within 74 km and ±60° of its nose (a fighter radar's 40 NM) reports `contact` after its
  reaction time.

- **Engage my target** (`Flight::engage(now, to, at)`, `IafAi.engage`, slice 3; the radio menu's command): each AI jet
  addressed (the flight, the element or one wingman) in the air leaves its slot and flies the steer loop at the
  target at 4 g and 280 m/s; #4 stays on #3 when #3 engages too. The target is the player's radar lock, an enemy
  aircraft alive (`ai_flights.gd engage_target`, `engage`); without one each answers "unable", and a jet already engaging keeps its target. Each jet keeps one missile in the air at the target at a time (inferred). The pursuit is the steer loop (slice 4's, every 0.1 s at the target's point as of the flight's last decision, every 0.5 s), not the 1998 Dogchase (mode 0x11): the 1998 combat loops are not flown on the 6-DoF AI jets yet (§8.7 lists the loops they fly). `ai_flights.gd` keeps its
  position fresh every frame (`IafAi.set_target`) and fires the engaging jets' weapons through `combat.gd`: the next
  air-to-air station with rounds (action 330), then the launch (action 300: its envelope, its 30° cone, its fire gate).
  When the target is gone (destroyed, or out of the world: a drone at its end point) the engaging jets rejoin ("in position"); a rejoin or an RTB ends the
  engage too. Ground targets are not engaged (the AI's air-to-ground deliveries are milestone 3's rows).

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
| `contact` | "Kidon 1-2, contact." | none found. Ours: "כידון 1-2, יש מגע" | NATO CONTACT, "sensor information at the stated position"; Hebrew open |
| split | "Kidon 1, element 3–4, split." | none found. Ours: "כידון 1, זוג 3–4, פיצול" (the pair: זוג) | NATO SPLIT, "flight member is leaving formation to pursue a separate attack"; Hebrew open |
| regroup | "Kidon 1, element 3–4, rejoin." | "כידון 1, זוג 3–4, הצטרפות" | the four-ship's rejoin term (slice 3's research) |
| engage | "Kidon 1-2, engage my target." | none found. Ours: "כידון 1-2, תקיפת המטרה שלי" | NATO ENGAGE, "a fire control order used to direct or authorize units to fire on a designated target"; Hebrew open |

Later (outside this slice): a commit on the AWACS's call (the element turns to the contact); the controller's answers
to requests (picture, bogey dope, declare, vectors: ai-plan Q12); a memory of contacts already reported (each call is
answered once today); a mate's call of a lock it sees on its own RWR; the break's direction in the defender's own call.

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

Modern IAF's sites run on the Rust site (`crates/iaf-ai/src/site.rs`, gdext `IafSite`), not on the 1998 brain; the
1998 game keeps §14 as it is. No mission places a site yet. `shared/ai/air_defence.gd` is the dev and test hook:
`AirDefence.of(host).spawn(kind, pos, heading, alternates)` (kind `s300`, `tor` or `zsu`) adds each part as a
mission entity (`ad:N`) with its stand-in shape and arms each firing part as a combat.gd unit without a brain
(`add_ground_unit`). The test is `modern-iaf/tests/test_enemy_sites.gd`; the Rust tests are
`crates/iaf-ai/tests/sites.rs`. The procedure and its sources: [modern-iaf/docs/research/enemies.md](../modern-iaf/docs/research/enemies.md)
§2.3–§2.6, §3.1 and §5.2. Timings no source gives are inferred, each with a comment in `site.rs`.

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
  to acquire it and fire (§11-134).
- **Relocation** (§11-121): after an engagement, 20 s without a track (inferred), the site takes its march order
  (radars off), drives straight to its next position (the placed one and its alternates in turn), sets up and searches
  again. A single site moves whole (inferred from §11-119's one third), its layout kept, each vehicle facing its course;
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
  the target; the gun's is its range. The weapon records are stand-ins:
  the AIM-120's for the SAMs and the 20 mm's for the ZSU, the existing missile and round models unchanged (the sites'
  own records await the user, modern-iaf/docs/threat-records.md).
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

Public figures are rough and disputed. Head on, the 96L6E's 300 km gives about 210 km against an F-16, 39 km against
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
| S-300PMU-2 | none: the 96L6E's and the 30N6E2's processing is open | open |

The wingmen's beam (§8.8, the reactions) turns the threat 90° off the nose: against the Tor it breaks the track.

### 15.4 Stand-in shapes

Ours (`air_defence.gd _shape`), built like the bases' furniture (`base_furniture.gd`, vertex colours, olive): a radar
cabin on a truck with its flat array on a post, a semi-trailer with four canisters upright, the Tor's tracked hull and
turret with its two antennas, the ZSU's hull and turret with four barrels and its dish. They stand in until a model is
approved.

### 15.5 Later

- Ground clutter for the S-300's radars (their processing is open) and for the AI fighters' sensor (`combat.gd`, the
  1998 game's rule): not started.
- The network (ai-plan K6): an early-warning radar cueing the sites; today the caller marks a jet cued.
- The sites' own missile and gun records (drafts, threat-records.md) and the site's guidance of its missiles: the
  stand-in missile homes by itself and flies on when the track radar dies.
- Roads for the move; §11-121's other moves (after a reconnaissance overflight, after 4–6 hours in place); a battery
  of several sites moving a third at a time.

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

### 16.4 Stand-in shape

Ours (`drones.gd _shape`), built like the bases' furniture (`base_furniture.gd`, vertex colours, grey): the fuselage,
the delta wing, the fins at its tips and the pusher propeller's disc, at the real length and span. It stands in until
a model is approved. No engine sound: no sound on disk fits a small piston engine.

### 16.5 Later

- The warhead's damage at the end point, the launch from the rack and the climb (the mission work).
- The 6-DoF data for the type (open).
- Listed only: the integrated network (ai-plan K6) and enemy-fighter BFM (K3 / K4; the user: lower priority).

## UNCERTAIN
Open questions in this document:
- The RWR field names behind conditions 19, 26, 27, 38, 39 (§13.2); what else writes brain+0x7c.
- The pitch law's tail (`5ca010`), the speed law's acceleration term, the formation loops' details (§8.5).
- Waypoint actions 1, 4, 5, 6; the sim clock origin of the waypoint times (mission start taken).
- The leader flag gating the wingman's take-off roll; the taxi re-placement's 60 m sign; what happens after parking
  (the root timer keeps running ParkInHangar).

[^mis-96l6e]: Missilery.info, "All Altitude Detector (VO) 96L6E", https://en.missilery.info/node/13476 (target detection range 5–300 km; read as quoted by a search engine on 2026-11-19, second-hand).
[^aerospaceweb]: Jeff Scott, Aerospaceweb.org, "Radar Cross Section", 21 March 2004, https://aerospaceweb.org/question/electronics/q0168.shtml (the head-on view most important; the largest returns from the sides; read 2026-11-19).
[^ni-f16]: The National Interest, on the F-16's Have Glass V paint, https://nationalinterest.org/node/112436 and https://nationalinterest.org/node/168141 ("the F-16 on average has a 1.2-square-meter radar cross-section, according to Globalsecurity"; second-hand: as quoted by a search engine on 2026-11-19; the site refuses automated reading).
[^migflug]: Max Grünwald, MiGFlug Afterburner, "F-22 Marble, F-35 Golf Ball: Where RCS Figures Come From", 8 November 2026, https://migflug.com/afterburner/?p=31823215 (GlobalSecurity's table: the F-35 at 0.0015–0.005 m²; GlobalSecurity itself refuses automated reading; read 2026-11-19).
[^ni-beast]: The National Interest, "The F-35 Has a 'Beast Mode' (But There's a Catch)", https://nationalinterest.org/node/180849 (external hardpoints "drastically increase" the radar cross-section; second-hand: as quoted by a search engine on 2026-11-19).
[^hamichlol-rwr]: Hamichlol, "מקלט התרעת מכ"ם", https://www.hamichlol.org.il/%D7%9E%D7%A7%D7%9C%D7%98_%D7%94%D7%9E%D7%96%D7%94%D7%99%D7%A8_%D7%91%D7%A4%D7%A0%D7%99_%D7%9E%D7%9B%22%D7%9D (a search radar's warning "ואחריה נעילה ומעקב"; read as quoted by a search engine on 2026-11-19, second-hand).
[^mako-102]: Mako, "pzm-magazine", on the 102 Squadron's air-combat training, https://www.mako.co.il/pzm-magazine/Article-1c3f6f796402d61027.htm (a good pilot "תוקף ומתחמק מטילי נ"מ"; read as quoted by a search engine on 2026-11-19, second-hand).
[^brevity]: Wikipedia, "Multiservice tactical brevity code", https://en.wikipedia.org/wiki/Multiservice_tactical_brevity_code (SPIKE, MUD, DEFENDING, BREAK, CONTACT, SPLIT; read 2026-11-19).
[^w-shahed]: Wikipedia, "HESA Shahed 136", https://en.wikipedia.org/wiki/HESA_Shahed_136 (length 3.5 m, span 2.5 m, mass 200 kg, about 185 km/h; "typically fired in multiples from a launch rack"; "extra-low" altitude flight; read 2026-11-19).
[^csis-shahed]: CSIS Missile Defense Project, "Shahed-131 and 136", https://missilethreat.csis.org/missile/shahed-131-and-136/ ("approximately 180 km per hour"; read 2026-11-19).
[^ar-shahed]: Army Recognition, "Shahed-136 loitering munition kamikaze suicide drone technical data", https://armyrecognition.com/military-products/army/unmanned-systems/unmanned-aerial-vehicles/shahed-136-loitering-munition-kamikaze-suicide-drone-technical-data ("It can fly at an altitude from 60 to 4,000 m"; read 2026-11-19).
[^rusi-shahed]: Uzi Rubin, RUSI Commentary, "Russia's Iranian-Made UAVs: A Technical Profile", 13 January 2023, https://rusi.org/explore-our-research/publications/commentary/russias-iranian-made-uavs-technical-profile ("fly low and slow", "virtual nap-of-the-earth profiles", "a tilting truck-mounted container holding five UAVs", "low radar and thermal signatures"; read 2026-11-19).
[^nf-shahed]: 19FortyFive, October 2022, https://www.19fortyfive.com/2022/10/irans-shahed-136-kamikaze-drone-everything-you-need-to-know/ (radar cross-section "estimated here to average .01 square meters"; second-hand: as quoted by a search engine on 2026-11-19).
[^w-pd]: Wikipedia, "Pulse-Doppler radar", https://en.wikipedia.org/wiki/Pulse-Doppler_radar ("Rejection speed is selectable on pulse-Doppler aircraft-detection systems so nothing below that speed will be detected"; "usually set just above the prevailing wind speed (10 to 100 mph or 20 to 160 km/h)"; read 2026-11-21).
[^w-tor-pd]: Wikipedia, "Tor missile system", https://en.wikipedia.org/wiki/Tor_missile_system ("The target acquisition radar is an F band pulse doppler 3D radar"; "The target engagement radar is a G band/H band (later K band) pulse doppler radar"; read 2026-11-21).
[^w-zsu]: Wikipedia, "ZSU-23-4 Shilka", https://en.wikipedia.org/wiki/ZSU-23-4_Shilka ("the radar picks up many false returns (ground clutter) under 60 m (200 ft) of altitude"; read 2026-11-21).
