# AI aircraft: brain, control loops, formations, take-off and landing

Addresses are `IAFJets.exe` **v1.1** (the reference version); [v1.1.md](v1.1.md) maps them to v1.0. Decompile:
`assets/ghidra_v11/iafjets.c`; argument orders checked in the disassembly. `UNCERTAIN` marks what the code did not
settle. Related: [mission-runtime.md](mission-runtime.md) (control modes, scripts), [flight-model.md](flight-model.md)
(the FM's "ai" cases, §14/§15), [weapons.md](weapons.md) (AI fire cones), [formats/mis.md](formats/mis.md) (bdb).

## How the original AI thinks (plain language)

- **Two layers.** A *brain* decides what to do; an *autopilot* ("control loops") flies the jet through the same
  flight model as the player, moving the stick, throttle, gear, flaps and brakes. An AI jet has no other physics.
- **The brain is a rule list from the mission database** (bdb Brains, 67 of them, e.g. "AA leader", "AA wing
  command"). Every 2 s (enemy jets: ×1.5 at Normal, ×2 at Rookie) it walks its rules top to bottom. A rule is an
  AND of conditions (`speed < 200 kt`, `current waypoint is a take-off`, `target closer than 9 km`, `leader dead`,
  `wingman command = close formation`…) and a list of actions. The first rule that fires per action *type* wins
  that tick; a rule marked "stop" ends the walk. Rules can switch to a *sub-brain* (e.g. "attack air target" under
  9 km) and back.
- **Actions** are manoeuvres (navigate the route, take off, go home and land, close / tactical formation, hold,
  straight, Immelmann, split-S, dog chase, run away, break, bomb runs…), weapon choice and launch, flares / chaff,
  target selection, radio replies and combat on / off. A manoeuvre that is already running is kept, not restarted.
- **States / modes** are the autopilot's modes: 7 navigate the waypoints, 9 take-off sequence (taxi from the hangar,
  roll, climb to the first waypoint), 8 go home (fly to the last waypoint, a fixed left-hand pattern, 6° glide path,
  roll-out, taxi to a free hangar, engine off), 1 / 3 close / tactical formation on the leader, 10 hold, 0x11 dog
  chase, and the combat manoeuvres.
- **What it reacts to:** its own speed / altitude / fuel ("bingo"), the current waypoint's type, its target's range,
  altitude, heading, whether the target is the player or destroyed, a missile launched at it, its leader being
  dead / on the ground, the player's wingman commands, a random number. It does **not** see terrain ahead (beyond
  the autopilot's own rules), other threats than its lock / missile warning, or the mission's scripts.
- **Skill** (Preferences AI level): Rookie / Normal enemies think 2× / 1.5× slower, fire from a narrower (Rookie
  ×0.5) or wider (Expert ×1.5) cone, a Rookie enemy pulls softer above 4.3 g, an Expert enemy cannot stall. (The
  damage scaling makes Rookie enemies *tougher*, a known original bug, docs/damage.md.)
- **Known weaknesses / exploits (original):** thinks only every 2–4 s; routes are timed (each waypoint has an
  arrival time) and flown at 180–300 m/s whatever the fuel; no go-around; a landed AI never takes off again; the
  take-off is flown without afterburner; a "go back" rule fired in the base brain makes the brain loop 10 times
  and switch itself off (e.g. "popup", "divebomb" once the target is dead); crash immunity: an AI jet with fuel and
  < 10 % damage cannot crash on the ground or water after 3.5 s of autopilot, and never during take-off; no
  promotion when a leader dies (the wingman only inherits its waypoint).

## 1. Objects

| object | where | notes |
|---|---|---|
| MBrain (0xe8 bytes) | entity+0x2c, ctor `FUN_0043eda0` | every entity built by `FUN_0059bb00` has one |
| autopilot / control-loop manager | vehicle+0xc50 (`FUN_005c6be0`, vtable 0x611e54) | `FUN_005c89f0` returns its mode (+0x24): the FM's "ai" test |
| formation manager | `DAT_00699340` (frmtnMngrPtr), hash map by formation **id** (0x1e) | built by `FUN_004b3573` → `FUN_004b3604` |
| TowersManager | `DAT_00699344`, ctor `54eb30` | airbase data (§8), player ATC |
| FlightController | `DAT_00699348` (0x3a0 bytes, ctor `FUN_0054acc0`) | AWACS / tower **radio voice** only (§10) |

MBrain fields (b = brain): +0 owner; +4 active rule list (base or sub-brain); +8 base list; +0x0c..+0x2c "action
type already run this tick", 9 ints (types 0..8); +0x30 scheduler event (vtbl 0x6007b0); +0x38 period (f64);
+0x40 target selector; **+0x44 leader** (partner); **+0x48 wingman command**; +0x4c / +0x58 flare busy / expiry;
+0x50 / +0x60 chaff busy / expiry; **+0x68 engaged**; **+0x6c combat disabled**; +0x70 current target; +0x74 primary
target (`FUN_005bccb0`, the formation member's target 0x424); +0x78 period code; +0x7c attacker (UNCERTAIN); +0x80
last hitter (cleared 5 s later); **+0x88 current waypoint index**; +0xd8 in a sub-brain; +0xdc list switched;
**+0xe0 landed** (the controller's landed flag).

## 2. Loading (bdb → runtime)

- A brain item uses **one** list: `rules = item.0x208 ? rules0 : rules1` (`FUN_00595060`).
- Rule node (0x14 bytes, `FUN_004bbd50`): key (file order), next, condition tree, **stop flag = 0x1ae**, actions.
  0x190 / 0x19a / 0x1a4 are editor-only.
- Condition `list16 = [a, code, op, value]` → `{code, op, value}` (`FUN_00594c50`). **`a` is editor-only** (no OR /
  NOT). All conditions of a rule are a left-deep **AND** (`FUN_004b3e8f`, eval `FUN_004bbf40`, short-circuit). A rule
  with no condition, an unknown code (> 39) or op (∉ 0..5) never fires (e.g. brain 3 "popup" rule 0, op −1). The
  constant is `ftol(value)` except codes 9, 13, 24 (float).
- Action `list20 = [flags, edType, id, f4, f5]` → `(id, f4 = audio id, f5 = delay s)` (`FUN_004b6088`,
  `FUN_00594ca0`). **flags and edType are editor-only.** id −1 is skipped. id 1000 = sub-brain `f4` (audio forced 0).
  Otherwise the runtime class is chosen by the bdb action's **code 0xbe**; it copies 0xc8, 0x82, 0x96, 0x8c. 0x78,
  0xa0 and 0xb4 are not read; the type 0..8 is fixed per class.

## 3. Creation, scheduling, tick

- Spawn (`FUN_004b815f`): brain id 0x2da in the map → rules attached (`FUN_00440790`: +4 = +8). Brain −1: never
  scheduled.
- Activation (`FUN_004a9100`): BRAIN (0x320 bit 0 = 0): the FM mover is installed, the FM type loaded
  (`FUN_005a8980`), the start pose set (`FUN_005a5820`, §7), then **reset**. MISSION (bit 0 = 1): the scenario starts
  and the brain is reset too, but every non-FM mover's `setMode` is empty (`FUN_0046a430`): **a mission-controlled
  unit's brain runs, its manoeuvres do nothing** (targeting, weapons, voice, sub-brains still work).
- **reset `FUN_0043eef0`**: clears the tick flags, +0x48..+0x50, +0x58..+0x64, +0x68, +0x70, +0x7c..+0x84 (not +0x6c,
  not +0x88); +0x78 = 480; leader +0x44 = `getWingman(e)` (`FUN_005bcb90`), else the formation leader unless that is
  e; +0x74 = the member target; the target selector per class; +0x38 = period; if not yet scheduled, schedules the
  tick **now** and then every period.
- **Period** `FUN_004404d0(code)`: 450, 460 … 540 → 1 … 10 s; default 480 = 4 s; ground / SAM / boats 500 = 6 s;
  **controlled aircraft (class 0x1c) 0x1cc = 2 s**. Single player, enemies of the player only: ×2 Rookie, ×1.5 Normal
  (0x6007a0), ×1 Expert.
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
  Types 5 and 6 are never marked; the sub-brain action is never gated; 390 skips the gate. **Original bug:** a "go
  back" (1000, −1) fired in the base brain still sets +0xdc: 10 restarts, then transferControl — the brain stops.

## 4. Conditions (`FUN_004b3fa9`; measure vtbl +0x20)

Operators (`FUN_004b5e6a`): 0 `==` (bool measures compare as bools, float exactly), 1 `>`, 2 `<`, 3 `>=`, 4 `<=`,
5 `!=`; 1–5 are false when the measure is invalid. T = current target (+0x70).

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
| 8 | 5c0850 | weapon available (UNCERTAIN) |
| 9 | 5c0890 | T altitude (m) |
| 10 | 5c0940 | angle to T, deg (UNCERTAIN which) |
| 11 | 5c0980 | T heading, deg |
| 12 | 5c0b60 | T speed, kt |
| 13 | 5c0bc0 | 3-D range to T (m); invalid if T destroyed |
| 14 | 5c0d30 | `FUN_0044ea60(T)` UNCERTAIN |
| 15 | 5c0d60 | random 0..100 |
| 16 | 5c0db0 | own z − T z |
| 17 | 5c0ee0 | T load factor |
| 18 | 5c0f40 | own z < T z |
| 19 | 5c14e0 | I am locked (UNCERTAIN) |
| 20 | 5c1740 | T within the current weapon's range |
| 21 | 5c1a30 | weapon state (UNCERTAIN) |
| 22 | 5c1080 | **leader destroyed**; invalid without a leader |
| 23 | 5c1aa0 | **leader on the ground** (z − terrain − model height < 3) |
| 24 | 5c10c0 | range to the primary target (m) |
| 25 | 5c1210 | primary target destroyed |
| 26 | 5c1530 | T is attacking / locked (UNCERTAIN) |
| 27 | 5c15a0 | leader locked (UNCERTAIN) |
| 28 | 5c15f0 | T's target == my leader |
| 29 | 5c1250 | **wingman command** +0x48 (1 ProtectMe, 2 BugOut, 3 EngageDesignated, 4 EngageAny, 5 Tactical, 6 Close) |
| 30 | 5c1270 | **action of the current waypoint** `route[+0x88].action` (0 without a formation) |
| 31 | 5c12e0 | T engaged |
| 32 | 5c1320 | T destroyed |
| 33 | 5c1360 | current waypoint index |
| 34 | 5c1380 | T is the player |
| 35 | 5c1a60 → 453540 | **fuel ratio**: 100 without a route; `r = endurance / (3-D distance to the last waypoint / 220)`; ≤ 1.1 latches 1.0; returns r × 10 (bingo rule `35 <= 11`) |
| 36 | 5c13e0 | own damage % |
| 37 | 5c16a0 | leader's target == my target |
| 38 | 5c1410 | T == my threat |
| 39 | 5c1490 | a missile is launched at me |

## 5. Actions

Manoeuvres (type 0) call `mover.setMode(mode, arg, pose)`; the FM's `setMode` (`5a8410`, FM vtbl 0x611dc8 slot 11)
does nothing when mode / arg / pose are unchanged (`5c8a70`): **a running manoeuvre is kept.**

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
| 250 | Go home | 8 | self, only if +0xe0 == 0 | GoHomeCL (+0x1ed0), §9 |
| 260 | Use waypoint | — | — | +0x88 = 1 (and the NAV's current waypoint), no mode change |
| 270 | Land | 8 | self | GoHomeCL, then if a leader exists `440f90` |
| 280 | Takeoff | 9 | self, only if +0xe0 == 0 | TakeOffSequenceCL (+0x3e70), §8 |
| 290 | Dive bomb | 0x17 | T | DiveBombCL |

Other types (combat job; hooks only in the port): 1 Launch (300, `4440d0`: needs T, weapon ready, range in
[min, max], nose-to-LOS ≤ 30° (0x6008f8; 5° for weapon 0x235), single-player enemy cone ×0.5 Rookie / ×1.5 Expert,
weapon 0x244 also `|44e770| ≤ 60°`; fires `FUN_00452680(T)`); 2 / 3 flares / chaff (310 / 320: busy 2.25 s,
`FUN_004545e0(0x226 / 0x21c, 0, 1)`); 4 change weapon (330–390); 5 target (400 next, 410, 420 best → +0x70); 6 radar
(430, 440); 7 response (450–540: only the node's audio, e.g. 250 "Roger, closing formation"); 8 scenario: 550 start
combat (needs +0x68 == 0, +0x6c == 0, T alive: +0x68 = 1, weapons free), 560 stop combat, **1000 sub-brain**
(`setRules(list(f4), 1)`: +0xd8 = 1, +0xdc = 1, **+0x48 = 0**; f4 0 / −1 / unknown → back to the base list).

## 6. Combat on / off and control modes (v1.1)

- **Trigger op 22 Disable combat (`4407e0`)**: +0x6c = 1. Only if engaged (+0x68): +0x68 = 0, weapons SAFE
  (`FUN_004aa900(1)` = the weapon handler's safe flag, not a control mode), the selector told, `transferControl()`.
  Not engaged: the brain keeps flying; only 550 is blocked.
- **transferControl `4401d0`**: cancels the brain's event (**the brain stops ticking** until the next reset), weapons
  safe, an aircraft's autopilot off (`setMode(0)`), back to the base list.
- **Trigger op 21 Enable combat (`440830`)**: +0x6c = 0, then reset (reschedules a stopped brain).
- **Trigger op 20 (`5c4470`)**: new base brain `setRules(list(arg), 0)` + switchControlStatus(1).
- **switchControlStatus `FUN_004a8e70`**: leaving 1 or 2 → transferControl (leaving 2 also kills the scenario);
  entering 0 → transferControl; 1 → reset; 2 → scenario start + reset; 3 → player takeover.

Corrections to mission-runtime.md: `FUN_004aa900(v)` is the weapon handler's SAFE flag; "reset unschedules the brain"
is wrong (reset only schedules; transferControl unschedules).

## 7. Spawn, start and route

### 7.1 Spawn and start
- `FUN_004b7634`: class 0x1c (aircraft) → entity `FUN_0059c740`; unitinfo+0x24 = the bdb type code (0x5b4), read by
  the FM loader `FUN_005a8980` (the same type → bd.ibx section table as the player, `data_set.rs`); status+0x14 =
  0x320 bit 0 ? 2 MISSION : 1 BRAIN.
- Activation (case 1 and case 3 alike): FM start `FUN_005a5820` with velocity **(200, 200, 0)**, i.e. 282.84 m/s along
  the heading, and the player's start rule: airborne ⇔ z > 800 and not (within 5000 m horizontally and 15 m vertically
  of the nearest base's **Tower** point; nearest base = nearest **Lineup** point, `551280`). Airborne: throttle 0.74,
  gear up, RPM 70. Ground: throttle 0, gear down, full flaps, brakes on, engine on only within 100 m of the Lineup.
- vehicle+0xc50's mode is 0 at spawn: an AI jet is not "ai" for the FM until the brain sets a mode.

### 7.2 Formations and routes
- Formation object (0x50 bytes): +0 leader (member 0), +0x18 wingman (member 1), +0x30 id, +0x38 kind (1 Alpha …
  4 Delta, 5 Echo, 6 Foxtrot, 7 Enemy, 8 Other, 9 Hotel, 10 India), +0x3c count, +0x40 waypoints in **file order**.
- Runtime waypoint (0x30 bytes): x, y, alt; **+0x10 f64 T = the file's "speed" field: the planned arrival time in
  sim seconds** (0 = none); +0x1c action.
- Queries: `FUN_005bcb40(id)` leader, `FUN_005bcb90(e)` wingman of e's formation, `FUN_005bcc20(e)` leader of e,
  `FUN_005bcd70(e)` the formation (leader and wingman share it).
- Waypoint actions: **2 take off** (always wp0), **3 navigate**, **7 land** (the last waypoint), **8 alert / hold**;
  0 none; 1, 4, 5, 6 have no AI reader (5: the player's NAV 10 nm hold).
- Every aircraft keeps its **own** index (brain +0x88, 0 at the start, not reset). Leader death (`FUN_00440eb0` →
  `FUN_00440ed0`): the wingman's index := the leader's. Leader landing (`FUN_00440f90`, once, brain+0xe0): the
  wingman's index := count − 1. No promotion of the wingman.
- **WayPtSet (mode 7)**: `init 5d7650`: index := brain+0x88; child Fly2WayPt. `next 5d7450`: while index < count:
  Fly2WayPt to (x, y, alt) with ETA T; if index ≠ brain+0x88 post the radio WayptReport; brain+0x88 := index; index++.
  After the last waypoint the loop ends (stick neutral).
- **Fly2WayPt speed** (`5d6dc0`): d = 3-D distance; dt = T − now; dt > 0: v = clamp(d/dt, 180, 300) m/s
  (0x6134f0/f4; C-130 type 225: [60, 215]); else 275 (C-130 215); within 6000 m (0x613504) of a slow-down point, v ≤
  its slow-down speed. Throttle: the speed law (§8.0).

### 7.3 Wingmen
- The wingman's leader is brain+0x44: its formation leader (the player when the player leads).
- Actions 190 / 200 fly CloseFormationCL (mode 1) / TacticalFormationCL (mode 3) on it (§8.4).

## 8. Autopilot (control loops, atp.ControlLoop.h)

### 8.0 Framework
- `setMode` cases: `5c8800` (cancel the old root timer, +0x18 = 1), the loop's `Init`, `5c9a90` (start child 0, arm
  the root timer). +0x10 = the time the mode went 0 → non-zero ("aiOld" base).
- CL base (ctor `5c9630`, vtable 0x612f58): slots [0 Run, 1 Init, 2 Init2, 3 FirstRun, 4 GetName, 5 Next]. Init
  `5c93f0(now, fm, pt[6], parent, cond)`. Run `5cc0f0`: FirstRun once, then the current child's Run. Next `5cc540`:
  next child; after the last, Done `5c99e0`: stick neutral, parent Next. Leaf loops test `cond` first (`5cc590`) and
  end when it holds. Root timer period 0.5 s by default (0.2 / 0.1 s in some loops).
- Outputs (through the controller `44a240(gev, v, forced)`, posted only on change): brakes GEV 0x11 (`5cc440`, speed
  brake in the air, wheel brake on the ground), flaps GEV 0xc (`5cc490`), gear GEV 0xe (`5cc4e0`); throttle motion 2
  (`5ca420`); stick motion 1 (`5c9920(a, b)`: pitch a (sY = −a), roll b); rudder motion 5 (`5c9980`); motion 0x16
  scripted heading pivot (taxi turns, `5a8d40`, ±30 m offset); motion 0x19 engine off; GEV 0x13 drag chute (no aero
  effect).
- **Speed law** `5ca360(vt)`: `thr = clamp(0.7 + 0.005·SpeedK·(vt − V) − 0.02·SpeedBeta·a_fwd, 0, 1)` (0x612f0c,
  0x612f08, 0x612f10; SpeedK 6, SpeedBeta 0.5 from bd.ibx `[Autopilot]`; a_fwd = forward acceleration, UNCERTAIN).
  Taxi variant `5cc9d0` with SpeedTaxiK / SpeedTaxiBeta (defaults = SpeedK / SpeedBeta).
- **Roll law** `5c9bc0(φt)`: `x = clamp(wrap(φt − φ)/π · RollK/MaxRollRate − RollBeta·p·MaxRollRate·(|p| ≤ π ? 1 :
  0.5), ±1)` (RollK 4, RollBeta 0.02).
- **Pitch law** `5ca010(θt)`: first, V > 150 and mode ∉ {0, 8} → gear up, flaps up, brakes off; then
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

The player's autopilot (FM motion 0xf, `5a1e40`) runs LevelFlightCL / GoHomeCL without setting the mode: it flies
with the player's FM rules.

### 8.2 Take-off (mode 9, TakeOffSequenceCL, Init `5ce0e0`)
Children: on the ground **TaxiCL (departure)** and **TakeoffCL**; then **KeepAttitude2PtAtSpeed** to wp0 at 205.889 m/s
(400 kt) until within 500 m (2-D) of it (no route: the point at 180.153 m/s, never ends).

**TaxiCL** (ctor `5d6430`, vtable 0x6134b0; FirstRun `5d5cb0`, Run `5d5400`):
```
FirstRun: base B = 551280(pos); L = B.Lineup; leader = the route's member 0
  departure: atLineup = |pos − L| < 100;  start = leader ? wp0.T : wp0.T + (atLineup ? 0 : 10);  waiting = 1
  if atLineup: return
  departure: h = hangar near pos (5521c0), marked occupied
     path = [FromHangarTurn[h], FromTaxi[0..]] minus the points before the one nearest in 2-D
     not within 100 m of Hangar[h]: re-placed 60 m before path[0] on its heading, at rest (5a4d40) (UNCERTAIN sign)
     path[0] within 100 m of L: atLineup = 1
  to park: h = first free hangar (552190; C-130: the last), occupied; path = [ToTaxi[0..], ToHangarTurn[h], Hangar[h]]
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
No afterburner (mode 9). Wingmen: 10 s after the leader, 3 s holds when closer than 50 × 100 m, hold on the runway
until the leader rolls at ≥ 50 kt.

### 8.3 Landing (mode 8, GoHomeCL, Init `5cd390`)
- Target G = the route's **last** waypoint (no route: the given point). Children: **Fly2WayPt(G)** with ETA now − 60
  (so 275 m/s), slow-down 180.15 m/s (C-130 128.68) within 6000 m, ends within 100 m (2-D); then **LandingCL(G)**.
- **LandingCL** (`5d2b30`): base B nearest G, RN = RunwayNumber, L = Lineup, hT = terrain(L); local frame x right,
  y along RN, `world = L + (x·cos RN + y·sin RN, −x·sin RN + y·cos RN)`; **left-hand** pattern (k = 2 for the C-130):

| point | position | z | heading |
|---|---|---|---|
| P1 | **G** + (−5562 (C-130 −9270), 0) | hT + 700 | RN + 270 |
| P2 | L + (−5562 / −9270, −7416) | hT + 500 (C-130 600) | RN + 180 |
| P3 | L + (0, −7416) | hT + 300 (C-130 350) | RN + 90 |
| P4 | L + (0, −3708 (C-130 −1854)) | hT + 250 | RN |
| P5 | L | hT | RN |

  Children: CH1(P1), ChangeAlt(P1), LevelWings 250 kt, KeepAttitude(P1, < k·AllowedErrPt2); CH2(P2), ChangeAlt,
  LevelWings 200 kt, KeepAttitude(P2, < k·AllowedErrPt3); CH3(P3), ChangeAlt, KeepAttitude 170 kt (P3, < 1852);
  CH4(P4); CH5(P5); FinalApproach(P5, < k·AllowedErrPt6); StopPlane; TaxiCL(to park); ParkInHangar. At step 7
  (downwind): flaps and gear down; at step 13 (final approach): brakes (speed brake) on.
- **FinalApproachCL** (`5d4c50`): ends within k·AllowedErrPt6 (50 m) of P5. Glide frame pitched −6° along RN:
  (cross, along, above) of pos − P5; `vt = max(Vmin(z, n) + 10.29, 72.06 m/s)`; throttle min(speed law(vt), 0.5);
  `bank = clamp(−0.0013963·cross + e·ChangeHeadK/3 − ChangeHeadBeta·turn rate, ±80°)`, e = RN − heading;
  `pitch° = −Kz·above − 0.5·q° − (along < −1000 ? 6 : 4)`, Kz = above < 0 ? 0.03 : 0.3 (C-130 0.05).
- **StopPlaneCL** (`5d44d0`): V ≤ 50 kt: rudder 0; chute released; the landed handler `440f90` once; brain+0xe0 = 1;
  LandedReport radio at +3 s; DONE. Rolling (|pitch| ≤ 0.2°, on the wheels): rudder 0, throttle 0, chute; heading
  error > 0.1°: nose-wheel steering via the roll stick. Else (flare): throttle 0, wings level, pitch 0.
- **ParkInHangarCL** (`5d66b0`): creeps at 2 kt to Hangar[h]; when the distance grows: stop, brakes, re-placed at rest,
  **engine off**. No despawn, **no AI go-around**.

### 8.4 Formation loops
(see §8.5 when decoded)

## 9. Airbase data (`iaf.ibx`, TowersManager `54eda0`)
Ten sections in record order: Ramon, David, TelNof, Refidim, Inshas, Damescuss, Kuzeir, Bley, Ryak, Aman. Keys:
`TowerLoc{X,Y,Z}`, `LineupLoc{X,Y,Z}`, `RunwayNumber` (degrees), `TaxiWayPtsTo` + `ToTaxiPt{X,Y,Hdg}i` (runway →
hangars), `TaxiWayPtsFrom` + `FromTaxiPt…` (hangars → runway), `HangarsNum` + `HangarPt…`, `ToHangarTurnPt…`,
`FromHangarTurnPt…`. Headings: `fmod(deg, 360)`, > 180 → −360, the direction of the leg leaving the point. Accessors:
`551280` nearest base by Lineup (3-D), `5521c0` nearest hangar within 1000 m (−1 unchecked), `552190` first free hangar
(0 when all are taken), `552240` / `552260` occupy / free. Port: `crates/iaf-flight/src/airbase.rs`.
Data quirks (kept): Inshas `romHangarTurnPtHdg7` typo (→ 0), Kuzeir hangars 2 / 3 look swapped, Ryak's hangar order.

The TowersManager's ATC (`ACFT_*` calls, runway occupancy) is for the **player** only; AI aircraft only use the
geometry and the hangar flags, and occupy the runway zones for the player's tower.

## 10. Radio reports (FlightController, `DAT_00699348`)
One-shot scheduler events, radio / subtitle only, friendly units with a callsign: WayptReport (+3 s after WayPtSet
moves on; "X passing waypoint N"), AirborneReport (+3 s, TakeoffCL at 100 m AGL), LandedReport (+3 s, StopPlane),
CrashedReport (+2.5 s), kill reports (+5 s), EjectReport; a 12 s AWACS contact timer (first call ≈ 60 s, 30 nm
around the player). Not ported yet (voices of the AI).

## 11. Flight model: AI cases
`ai = FUN_005c89f0() != 0` (the mode of §8.1). Ported in `crates/iaf-flight/src/aircraft.rs` (fields `ai_mode`,
`ai_since`, `ai_team`, `ai_level`, `ai_low_damage`); the rules are flight-model.md §14.2, §14.3, §15.2, §15.6.3,
§15.8: noAB = !HasAB || (ai && mode ∉ {7, 8}) in the air, = ai on the ground; no gear drag; wheel brake ×4 (v1.1);
lift gate bypass, no belly friction; stall unless Expert enemy; Rookie enemy g > 4.3 → 4 + 0.02 g²; no buffet; the
throttle: every change counts, the afterburner lights at once, the engine starts only on a change; crash immunity
`(mode 9 && fuel) || (mode active > 3.5 s && fuel && damage ≤ 0.1 && !(enemy && mode 0x11))`.

Correction to flight-model.md §15.6.4: the start's "base" is the nearest by the Lineup point; the airborne test uses
its Tower point, the engine test its Lineup point.

## 12. Port

## UNCERTAIN
- Avionics sensors behind conditions 8, 10, 14, 19, 21, 26, 27, 38, 39; what writes brain+0x7c.
- The pitch law's tail (`5ca010`), the speed law's acceleration term, the formation loops' details (§8.4).
- Waypoint actions 1, 4, 5, 6; the sim clock origin of the waypoint times (mission start taken).
- The leader flag gating the wingman's take-off roll; the taxi re-placement's 60 m sign; what happens after parking
  (the root timer keeps running ParkInHangar).
- Kfir and Mirage share one FM parameter block loaded once (`0x8442d4`): in the original the second of the two
  types in a mission flies on the first one's data (original bug, not ported: each jet loads its own section).
