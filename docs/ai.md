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

- Spawn (`FUN_004b815f`): brain id 0x2da in the map → rules attached (`FUN_00440790`: +4 = +8). Brain −1: no brain,
  never scheduled (the loader copies 0x2da to the spawn descriptor as is, `FUN_0058f110` @58f1e6; §14).
- Activation (`FUN_004a9100`): BRAIN (0x320 bit 0 = 0): the FM mover is installed, the FM type loaded
  (`FUN_005a8980`), the start pose set (`FUN_005a5820`, §7), then **reset**. MISSION (bit 0 = 1): the scenario starts
  and the brain is reset too, but every non-FM mover's `setMode` is empty (`FUN_0046a430`): **a mission-controlled
  unit's brain runs, its manoeuvres do nothing** (targeting, weapons, voice, sub-brains still work). The mover is
  installed only for a unit that gets a brain: an unarmed ground unit gets none, so a BRAIN-controlled unarmed vehicle
  (116's, 324's) just stands (UNCERTAIN, from the research of `FUN_004a9100`'s callers).
  The mover goes by control mode, not class: the transports (class 3: C-130, IL-76) fly too (`ai_flights.gd`; before,
  only class 0x1c did, and 237's C-130 hung in the air in the player's path).
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
(`setRules(list(f4), 1)` `440790`: +0xd8 = 1, +0xdc = 1, **+0x48 = 0**; f4 0 / −1 / unknown → back to the base list:
+0xd8 = 0, +0xdc = 1, **+0x48 kept**, so the base list then sees the wingman command, docs/radio.md §3).

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
- Target G = the route's **last** waypoint (no route: the given point). Children: **Fly2WayPt(G)** with ETA = now + 60
  (the constant −60 at 0x612ff0 is subtracted; UNCERTAIN, another reading gives now − 60), slow-down 180.15 m/s (C-130 128.68) within 6000 m, ends within 100 m (2-D); then **LandingCL(G)**.
- **LandingCL** (`5d2b30`): base B nearest G, RN = RunwayNumber, L = Lineup, hT = terrain(L); local frame x right,
  y along RN, `world = L + (x·cos RN + y·sin RN, −x·sin RN + y·cos RN)`; **left-hand** pattern (k = 2 for the C-130).
  All in **f32**: θ = rad(fmod(−RN, 360)) (`459bd0` / `459c90`), the matrix `43ecd0` rotated by θ, `43dd70`, and
  L + offset stored as floats. For RN 270 the cos θ residue (~1e-8) is lost, so the legs are exactly axis-parallel and
  ChangeHeading2PtAcu's search takes its `x == x` / `y == y` branches (an f64 port breaks this):

| point | position | z | heading |
|---|---|---|---|
| P1 | **G** + (−5562 (C-130 −9270), 0) | hT + 700 | RN + 270 |
| P2 | L + (−5562 / −9270, −7416) | hT + 500 (C-130 600) | RN + 180 |
| P3 | L + (0, −7416) | hT + 300 (C-130 350) | RN + 90 |
| P4 | L + (0, −3708 (C-130 −1854)) | hT + 250 | RN |
| P5 | L | hT | RN |

  Children (ctor `5c6370`): CH1(P1), CA1 (|Δz| < 50; C-130: within k·Pt2 or |Δz| < 250), LW1 128.681 m/s (C-130
  113.239), KA1(P1, same speed, < k·AllowedErrPt2); CH2(P2), CA2 (50 m), LW2 102.944, KA2(P2, < k·AllowedErrPt3);
  CH3(P3), CA3 (**250 m**), KA3 87.503 (P3, < 1852); CH4(P4); [CA4 (50 m), C-130 only]; CH5(P5);
  FinalApproach(P5, < k·AllowedErrPt6); StopPlane; TaxiCL(to park); ParkInHangar (the last two in mode 8 only). Next
  `5d43e0`: at step 7 flaps and gear down; at step 13 speed brake on and the ground watch off. ChangeAlt sends no
  throttle.
- **ChangeHeading2PtAcu** (vtable 0x6138a0, Run `5dbe70`, FirstRun `5dd1f0`, period 0.2 s): target = bearing to the
  point; CH2–CH5 add a "line capture" `e −= ±acos(cos α)` (α between the line prev → point and the bearing; the sign from
  sgn(e) and sgn(cos α), as coded); tolerance CH1 1° / others 0.5° (C-130 2 / 1 / 0.5°); bank limit 80° (CH3 / CH4
  60°, CH5 20°; C-130 always 40°); `bank = clamp(e/(π/6)·Lim·ChangeHeadK − turnRate·ChangeHeadBeta, ±Lim)`; the
  "Acu" search (|e| > 2°): iterate the bank (≤ 100 times, `bank += gap·1.745e-4`) until the turn circle
  (`R = V²/(|tan bank|·9.806)`) is tangent to the line (original bug: the perpendicular with slope −m, truncated to
  integers); pitch law(0); throttle `min(speed law(vt), 0.7)`, vt = the entry speed (CH4 / CH5 72.0611 m/s); no ground
  watch in mode 8; rudder 0. Done on two consecutive ticks with |e| ≤ tol or roll ≤ 0.2° (signed, as coded): wings
  level, throttle **0.1** (kept through the following ChangeAlt). DelicateYawLim (rudder branch) is 0 in bd.ibx:
  dead.
- **FinalApproachCL** (`5d4c50`): ends within k·AllowedErrPt6 (50 m) of P5. Glide frame pitched −6° along RN:
  (cross, along, above) of pos − P5; `vt = max(Vmin(z, n) + 10.29, 72.06 m/s)`; throttle min(speed law(vt), 0.5);
  `bank = clamp(−0.0013963·cross + e·ChangeHeadK/3 − ChangeHeadBeta·turn rate, ±80°)`, e = RN − heading;
  `pitch° = −Kz·above − 0.5·q° − (along < −1000 ? 6 : 4)`, Kz = above < 0 ? 0.03 : 0.3 (C-130 0.05).
- **StopPlaneCL** (`5d44d0`): V ≤ 50 kt: rudder 0; chute released; the landed handler `440f90` once; brain+0xe0 = 1;
  LandedReport radio at +3 s; DONE. Rolling (|pitch| ≤ 0.2°, on the wheels): rudder 0, throttle 0, chute; heading
  error > 0.1°: nose-wheel steering via the roll stick. Else (flare): throttle 0, wings level, pitch 0.
- **ParkInHangarCL** (`5d66b0`): creeps at 2 kt to Hangar[h]; when the distance grows: stop, brakes, re-placed at rest,
  **engine off**. No despawn, **no AI go-around**.

### 8.4 Navigation leaves (Fly2WayPt's children, `5d6ad0`)
The loops read `s = (x, y, z, pitch, roll, heading)` from `5a68f0`: the position and the **flight-path attitude**
(velocity direction and roll; `5a68f0` passes α = β = 0 to the attitude slot), and the rates `5a6b10` (flight-path
pitch rate, roll rate, turn rate). Fly2WayPt: its condition first (PassWaypoint `5d70a0`: passed once the 2-D
distance was ≤ R and then grows; R = 1852 m, or at the first step 9265 / 6485.5 / 3983.95 m for MaxG ≤ 4 / < 6.5 /
else when starting inside it), then the ETA speed → throttle, then the current child; a finished child centres the
stick and the next one starts on the next tick:
1. **LevelWingsPitch0Accel** `5d2400` (180 m/s; C-130 90, type 220 135): pitch target 0, or FpmPitchReqAtLowVels
   (−5°) below Vmin(z, 1.2 g) until Vmin + 15; done when |pitch − target| ≤ 0.02π, |roll| ≤ 0.01π and the speed is
   reached (±3 m/s); throttle from the speed law.
2. **ChangeHeading2Pt** `5ddef0`: bearing to the point; `bank = clamp(e/(π/6)·ChangeHeadK·80° − turnRate·ChangeHeadBeta,
   ±80°)` (C-130 ±30°), pitch 0; done within 0.02π; no throttle.
3. **ChangeAlt** `5cf320` until |Δz| < 250 m or the point is passed (a second PassWaypoint, 1852 m): wings level,
   `pitch = clamp(Δz·ChangeAltK·(π/12)·0.001 − vz·ChangeAltBeta, −π/6, π/12)` (C-130 ×0.002, [−π/12, π/18]).
4. **KeepAttitude2Pt** `5db510` until passed: bank ±45° on the bearing error, pitch = the elevation of the point; ring
   period 0.5 s (near / manoeuvring), 1.5 s (< 3708 m, clear ahead 1.9 s), 3 s (clear ahead 3.4 s).
5. LevelWingsPitch0 (normally never reached).
**Watch-ground** `5ca480` in every leaf (off only from the landing's final approach): the point `pos + vel·t`,
`t = max(−vz/15, 0) + WatchGroundDeltaTime`; below terrain + hAboveGround (200 m) or no line of sight → wings level,
climb `max(π/24 + atan2(h − z, d), 0)`, throttle ≥ the 250 m/s law.
At the route's end the stick stays centred and the throttle frozen; the brain decides what comes next (the data:
"Land" / "go home" rules on waypoint action 7).

### 8.5 Formation loops (modes 1 / 3, vtables 0x613220 / 0x613238, step `5cfb50`)
- Slot: Close lateral 100 m, Tactical 200 m (150 m when the leader is below 1524 m), longitudinal −20 m; the leader is
  the formation's member 0. Every 0.25 s.
- Below Vmin(z, 1.25 g): LevelWingsAccel (wings level, −11°, 300 m/s) until above Vmin(z, 2.5 g).
- A = the leader's horizontal nose, C = its left; `k = 2000 − min(|Δz|, 200)·8.5`; steering point
  `Q = L + k·A − d·C` at `max(2·Lz − z, terrain + 91.44)`; the slot `S = L − 20·A − d·C`. The side flag is set only in
  network play, so in single player **every wingman takes the right slot** (UNCERTAIN).
- Steering: LookAt `5ca7d0` case 1 on Q: outside a 10° cone roll the target into the lift plane; inside it, wings
  level while Q is ≥ 1854 m away, else the leader's bank ± a blend to SlowConeRollK; stick law `5cb4d0` (DogChaseRollK,
  LookAtK / LookAtBeta).
- Speed `5d0870`: `x = (angle(pos − S, leader velocity) − π/2)·min(|pos − S|, 5562)/4500`,
  `spd = VL + 2·VL·(x − x²/2 + x³/6 − x⁴/24) − 30`, clamped [103, 515] m/s; then the speed law.
- Consequence (as decoded): Q is 300–2000 m ahead, so a lateral error of less than ~10° of that is not corrected: a
  loose formation that wanders a few hundred metres (test: `crates/iaf-flight/tests/autopilot.rs`).

### 8.6 Other modes
HoldPositionCL (10): KeepAttitude2PtAtSpeed at 180 m/s around the entry point (z ≥ terrain + 300), never ends.
FlyStraightCL (0xb): LevelWingsPitch0Accel at 180 m/s. The combat modes (0xd–0x18): combat job.

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
around the player). Traced in docs/radio.md §4; the waypoint report is built (`ai_flights.gd` posts it when the
autopilot's waypoint index moves on), the others are not yet.

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
- `crates/iaf-flight/src/autopilot.rs`: the control loops of §7–§8 (modes 1, 3, 7, 8, 9, 10, 0xb) on an `Aircraft`,
  one tick per ring period; outputs through `set_controls` (stick y = −pull), `set_pivot` (motion 0x16),
  `replace_on_ground` (`5a4d40`), `engine_off` (motion 0x19). `airbase.rs`: iaf.ibx. Tests: `tests/autopilot.rs`.
- `crates/iaf-flight/src/aircraft.rs`: the AI cases (§11), `ap_view` (the loops' inputs), the pivot turn.
- `crates/iaf-godot/src/flight.rs`: `set_ai`, `ap_setup` / `ap_set_route` / `ap_set_mode` / `ap_step` / `ap_set_leader`
  / `ap_waypoint_index`, `start_rule` (§7.1, also used for the player's start).
- `game/ai/brain.gd`: the rule engine (§2–§6); combat measures and actions are hooks (`combat_hook`).
- `game/ai/ai_flights.gd`: every brain-controlled aircraft (class 0x1c) with an FM type flies (one IafFlight, the
  aircraft model at the Present scale); `contacts()` for radar / RWR; ops 21 / 22 via `mission_runtime.gd`.
- Wingman commands (docs/radio.md §3): `radio.gd` sets the wingman brain's command / target; its bdb rules answer.
- Not yet: combat (targets, weapons, the combat manoeuvres), the radio reports other than the waypoint (§10), helicopters,
  AI on MISSION-controlled units (their brain runs without manoeuvres: not started), network paths.
- Tests: `test_ai_flight.gd` (mission 221: 13 AI jets navigate, wingmen in formation, a take-off from Ramon).

## 13. Combat (partly built)

**Port** (`game/ai/combat.gd` for the AI jets, `crates/iaf-flight/src/autopilot.rs` for the manoeuvres). Built:
- The sensor (kind 4: 10 slots, a scan every 2 s; the range by type, else 40 nm) and the selectors: **400 / 440** the
  best of the air-mode scan, **410** of the ground-mode scan (`FUN_004ac820` / `FUN_004ac900`), **420** the primary
  target (`FUN_004ac9e0`: brain+0x74, the formation slot's target, unless it is the jet itself; else none).
- The stations (the mission's or the object's load); 330 / 340 one cycle step to the next AA / AG station with
  rounds, 350 / 360 / 380 the wanted type, 370 the gun (gate 5.0 s), each setting the fire gate's interval (its
  action +0x8c); 310 / 320 a flare / chaff through the player's release (busy 4 s first; the count drops only when a
  decoy left; the decoy rule acts on the missiles at the jet, docs/weapons.md §10).
- **300 Launch** as below: a missile through `launch_homing` (q 1.0: UNCERTAIN, the AI's q not traced), the gun a
  1 s burst of rounds every 0.2 s (UNCERTAIN: what ends an AI burst). A Launch that does not fire leaves its type
  gate free (brain.gd).
- Conditions 8, 10, 12, 14, 17, 20, 21, 26 (the target's brain+0x7c; locks of AI jets not built), 37; 27 invalid.
- **Dogchase** (mode 0x11, below) with the target fed every frame (`ap_set_target`) and the nose-on flag.

All the combat manoeuvres are built (autopilot.rs): Dogchase, Shandel / SplitS / Horizontal, Himmelman, TailClear,
RunAway, Break90, LevelBomb, DiveBomb, PopupRelease, with the leaves Fly2TargetXyzSt, Fly2ImpactPt, PullGFullThrottle,
Fly2PtXYZ. Bombs from AI jets: one store per release (`player_weapons.drop_bomb`). Not built: the AI's bomb ripple,
AI radar locks in STT (the selector locks are built). Tests: crates/iaf-flight/tests/autopilot.rs (Dogchase), tests/godot/test_ai_air_combat.gd.

Partial decode for the AI combat job (scratch work; argument orders of `4440d0` checked in the disassembly).
Corrections to §4 / §5: action **430 is "target = my nearest RWR emitter"** (`CTL.451f70()`, within 370 800 m;
without a controller B+0x7c), **440 runs the same exec as 400**; **condition 8 = no external tanks attached**
(`4593e0`: !(W+0xb8 == 0 && W+0xc0 != 0)); **condition 21 = the selected store's round count** (`456cd0`); flares
(310) set the busy flag for **4.0 s** (0x600920 = −4.0; a second reading gives 2.25 s: UNCERTAIN), chaff likewise; the type
gate is marked only when an action really fires (a Launch that does not fire leaves type 1 free).

### 13.1 Actions (class by bdb 0xbe in `4b62b6`; exec = vtable +4 with the entity E; act+8 = 0xc8, +0xc = 0x82,
+0x10 = 0x96, +0x14 = 0x8c)
| code | exec | effect |
|---|---|---|
| 300 | 4440d0 | below |
| 310 / 320 | 444640 / 4446d0 | free gate and B+0x4c (B+0x50) == 0: busy 1, expiry now + 4.0; `4545e0(0x226 / 0x21c, 0, 1)` = one flare (station 11) / chaff (station 10), released like a store (`454b70`), count −1 |
| 330 / 340 | 444760 / 4447c0 | `W.452690(1 / 2, act+0xc, act+0x10)` (one `53b8b0` cycle step, rounds > 0); success: fire gate interval := act+0x14, mark |
| 350 / 360 / 380 | 444820 / 444880 / 444950 | `W.452710(code)`: wants 600 / 570 (580 also, v1.1) / 500; up to 10 `53b8b0` steps until that type with rounds; refused while W+0xac; `4562f0` stores W+0xe8 / 0xec / 0xf0 |
| 370 | 4448e0 | gun: station 9 (`53bfb0(9)`), fire gate interval 5.0 s |
| 390 | 4449b0 | not a weapon change: with a controller and tanks attached, the tank jettison `458760` (once); never gated |
| 400 / 410 / 420 | 444ac0 / 4449e0 / 444a20 | B+0x70 = selector `4ac820` / `4ac900` / `4ac9e0` (selectors not traced) |

**Fire gate** B+0x98 (`4d4100`, init `4d3fa0(0, 1.0, 0)` in `43eda0`): passes when now < last or now > next, then
next = now + interval (default 1.0 s; the weapon-change actions set act.0x8c: 330 → 15, 350 → 30, 360 → 20, 380 → 45,
370 → 5 s in default6_1.bdb).

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
**Envelopes** (motion vt+0x74; also condition 20): IR chase class (`5624f0`): dist(v, t) = v·t + 0.5·absAcc·(1 −
4β)·t² (0x60ce90, 0x60ce94); s = |own V|; no T: max = dist(s, burn), min = dist(s, 1); with T: x = s − d̂·V_T, max =
dist(x, burn − 2) (0x60ce78); off-boresight ≥ 90° → both 0; min = dist(s, tCO + 2), min > max → both 0 (AIM-9L at 250
m/s: ≈ 1.5–6.7 km). Fixed weapons (`561700`, gun / rockets): max = _limitDist × 3.281 (0x60cdd8), min = 328.1 m
(0x60ce10). Bombs (`5641c0`): ballistic throw, min 0 (partly read). Radar 600 / 610 on the chase envelope: UNCERTAIN.
weapons.ibx AI fields: `_fireReleaseInterval` +0x48, `_maxNumInAir` +0x4c, `_reactionTime` +0x50 (callers not traced).

### 13.2 Conditions (resolved)
RWR = CTL+0x5b0 (10 entries × 0x24 from +0xc; +0 emitter, +0x14 launch flag; +0x174 locked; names UNCERTAIN).
3 B+0x78 period code; 10 relative bearing to T (deg, `44e770`); 12 T speed kt; 14 closure d̂·(V_own − V_T) m/s;
17 T load factor; 19 I am locked (RWR+0x174, invalid without a controller); 20 gun: distance ≤ _limitDist (4500)
and, for an aircraft, its loop is Dogchase with the nose within NoseOnTargetAng 7° (0x67bad0); other weapons: the
envelope with max ≠ 0 (bug: no station → max = vx, min = vz); 26 T attacking (T.brain+0x7c) or T locked; 27 leader
locked; 37 leader's target == mine (no leader target: 1 but invalid); 38 T == threat (nearest RWR emitter, else
B+0x7c); 39 any RWR entry's launch flag.

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

- **Dogchase** (5cea30, 0.5 s, never ends): aim = T (dist < 1000 m, 0x6130f8) else T − DistanceBehindTarget·F̂_T,
  LookAt `5ca7d0` case 1 (sets the nose-on flag); speed: dist > 1000: |V_T| + 0.027762795·dist (0x61310c); V_T·d ≤ 0:
  0; else a = −51.472221/(D − 1854), b = −D·a, vt = (|V_T| + a·dist + b)·(V_T·V)/(|V|·|V_T|); max(vt, 0) → speed
  law; watch-ground. D = bd.ibx [Autopilot] DistanceBehindTarget (exe 500, v1.1 bdgen.dat 300); the v1.1 data also
  has DogChaseRollK 4, LookAtBeta 1.0, ChangeHeadBeta 2.5, ChangeRollCone 10, NoChangeRollCone 1.75.
- **Fly2TargetXyzSt** (0x612d10, 5d9740): LookAt(case +0xf0) on its point; throttle = speed law(+0xe8) or +0xec or
  0.75; watch-ground unless case 4.
- **RunAway** (5dd330 / 5dd4a0): horizontal distance > 18540 m → state 1, run directly away (P − 1854 km·N.xy, z ≥
  T.z + 914.4; the speed 800 is dead: the throttle is overridden); > 9270 m, after 60 s, or the target's nose more than
  60° off me → state 2, fly to −1854000·F_T (absolute: quirk); else state 3, ATTACK the target + 30 m each axis
  (throttle 1.0). The throttle, posted last, overrides all: 1.0 for 30 s, then 0.75. Never ends; the states flip every
  tick at the borders (1 ↔ 2 beyond 18540 m, 2 ↔ 3 inside 9270 m: quirk).
- **Break90** (5da210 / 5da7a0): Fly2TargetXyzSt(B = P + 185400·sgn·(−F_T.y, F_T.x), my height) until within 10°
  (the angle includes the pitch) → LevelWingsPitch0Accel 180 until |roll| < 10° → PullGFullThrottle (`5da080`: the
  stick for 7 g, wings level, throttle 1.0, no ground watch) until pitch > 45° → KeepOrientation until z > +0x5b0 +
  1066.8 (+0x5b0 is never written: an absolute 1066.8 m, quirk) → Fly2TargetXyzSt(A = 1854 km along the entry nose)
  until within 10° → LevelWingsPitch0Accel 180 forever. sgn = sign(Fh.x·R_T.x + Fh.y·F_T.x): a local→world transform
  applied to a world vector (original bug, kept).
- **LevelBomb** (5d9290): Fly2TargetXyzSt at 257.5 m/s to (T.x, T.y, max(z, T.z + 609.6)); release `440440` (fire
  gate, then the selected weapon as 300) when the vacuum impact `45ed10` is within 2·(z − T.z) of T; then
  LevelWingsPitch0Accel 180 m/s.
- **PopupRelease** (5ccbd0, base Run 5cc0f0): Fly2WayPt to Q = me + 3708 m right of the line to T + (D − 4635) along
  it, at terrain + 300 (ETA D/308.4 used as an absolute time: quirk); PullGFullThrottle until |pitch − 45°| starts
  growing (`5da190`; its stored value is never reset between popups: quirk); KeepOrientation to T.z + 1828.8;
  Fly2PtXYZ (`5d9580`: LookAt case 0, throttle only from the ground watch) to U = T + 500 up until within 15° (cos
  0.966, 3-D); KeepAttitude2Pt on U with the release (`440440`) when the impact is within 600 m of U (3-D: only
  ~332 m horizontally of T) or I am within 1000 m of U (both can fire in one tick); ChangeAlt T.z + 1000, which never
  ends (no condition), so LevelWingsPitch0Accel is never reached.
- Not traced: Shandel / SplitS / Horizontal / Himmelman / TailClear / DiveBomb steps, LookAt cases 2 and 4, the AI's
  fire per weapon (`454270(T, 1)`: gun burst / aim, missile q, bomb ripple), the target selectors, the decoy logic,
  B+0x7c writers, the RWR internals, the hit reactions `44d590` / `43ff50`.

## 14. Ground defences, RWR, script ops 1 / 2 (traced; built: the player's RWR and the decoys, docs/rwr.md, docs/weapons.md §10, and the ground units' fire, game/ai/combat.gd; the decoys' effect on missiles, docs/weapons.md §10)

Port (`game/ai/combat.gd`): every armed unit other than the aircraft (its first valid station) has a weapon
handler, which script op 2 fires (below). A unit of a sensor class with a brain, brain or mission controlled (a
mission-controlled unit's brain runs, §2), also gets its brain (no manoeuvres),
the sensor (both modes' classes scanned every 6 s, the selector filters: 400 / 440 air, 410 ground, 420 either, the
best score; UNCERTAIN while the selectors are untraced), start / stop combat (the RWR lock comes with the selector's pick:
400 / 440 / 420 lock the player's RWR when they pick the player and unlock it when they leave it, FUN_004aca60 /
FUN_004aca80; 550 only starts the fire timer;
no weapon = "Entity with no weapon handler", no engagement) and the fire tick:
- **Class 0x17**: 565 AAA (above) and 560 rockets (the player's rocket motion: no hit sphere, they burst at the lead
  point or the ground; range the full `_limitDist`).
- **Class 0x18** (SAMs 620 / 630, and 570 / 580 / 610 on some vehicles): fire only inside the missile's DLZ
  (`FUN_005624f0`) taken from the unit's pose with zero speed. The nose is the unit's heading, so **a site never fires
  at a target 90° or more off its heading** (original quirk). One in the air (`_maxNumInAir` 1), q 1.0. The launch
  attitude (`FUN_004ab810`): types 290–340 turn the launcher to the target (heading and pitch), others keep their level
  heading. The launch point is (0, 4, 1) in that attitude (`FUN_004ab7b0`: 4 m ahead, 1 m up), at 100.1 m/s
  (_debugParam000, the launcher being slower than 5 m/s). The flight, RWR launch flag, blast and look are the player's
  homing weapons' (`player_weapons.gd` `launch_homing`).
- Release order (`FUN_004ab810`): the truce first (taken even when the shot is then skipped), then a busy pool
  object, then the terrain line of sight (both ends +3 m: −1.5 subtracted twice). Every round and missile starts
  at (0, 4, 1) in the launch attitude (`FUN_004ab7b0`; tanks, type 250: the turret's heading, which turns to the
  target), with the launcher's velocity (`FUN_004d5d10`).
- **Script op 2** (`script_fire`): the weapon at the target's position now (no lead, no range, no DLZ), q 1.0, then the
  release; a unit not in combat skips the truce (the handler's SAFE flag +0x28, "Fired a weapon by the Scenario";
  UNCERTAIN: its initial value). The entry's **0x852** (script +0x3c) picks the release flag (the weapon's +0x100,
  `FUN_004d5d10`): ≠ 0 → 2, a **kill shot**: the blast, then the target (alive or going down) explodes, level 5, the
  player not when shielded (`FUN_004d6130` @4d673a, `FUN_0058a350`); 0 → flag 0, the editor's **"Miss …"** shot: it
  flies and bursts but `FUN_004d6130` applies no blast (@4d6597). The brain's fire and op 1 use flag 1 (the blast).
  The missions name them so: "Miss Merkava 1" / "Kill Merkava 1" (112), "Miss Hermon Post" (231), "miss satil1" /
  "hit satil 2" (233). Before, every op 2 shot hit for real: 112's and 231's opening barrages killed the units the
  player must protect within seconds. **Helicopters** (class 2) have no sensor (`FUN_0043eef0`: classes 5 / 9, 8, 10 / 0x10,
  0x1c only), so they fire only this way (MI-24s: 580, aimed first by motion op 11).
- **Brain −1**: no brain (§3), so an armed unit fires only by script (op 1 / 2). Traced: the loader keeps 0x2da as
  is and `FUN_004b815f` attaches only a brain found by that id; the bdb Objects default brain `0x532` is used only
  by the Mission Creator (`FUN_0058e530`). Before, ours gave such units the object's default brain (untraced), so
  112's T-55s (brain −1) killed a Merkava 11 s in and the mission failed, which the original does not; 322's SA-2
  launchers (brain −1) stay silent (its "Shade hawk" launchers have brain 11).

Not reproduced: the ring pool's 3–4 steps per gun shot, the turret parts' drawn turning, ECM in the sensor, the
second weapon station. Test: tests/godot/test_ground_fire.gd (313 AAA and SA-3, 322 rockets).


- **Spawn** (`FUN_004b7634` → `FUN_004b7ad6`): an entity with record +0x3c ≠ 0 → vehicle `FUN_0059bb00` with a
  MWeaponHandler `FUN_004aa650` (entity[9], vtable 0x603200); non-aircraft units get only their first 2 valid weapon
  stations (`FUN_004b7ea3`), each a ring pool of `_maxNumInAir` objects (`FUN_004d8570` / `FUN_004d8760`). Weapon
  class by sub type (`FUN_004bb5d4`): 0x16 500 / 510; 0x17 fixed 540 / 550 / 560 / 565; 0x18 homing 570–635; 0x19
  640 / 650; 0x1a 660.
- **Target sensor** (brain+0x40, selector `FUN_004ac5f0`, vtable 0x603298) by class: 5 / 9 kind 1, 8 kind 3, 10 /
  0x10 kind 2 (5 slots, period 6 s), 0x1c kind 4 (10 slots, 2 s); other classes (6, 11 ground radar, 15 boat) none:
  they never target or fire. Scan `FUN_004af300`: R = nm(type) × 1854 (0x603390; `FUN_004acae0`: 250–280 → 3, 290 /
  310 / 330 / 340 → 20, 300 / 320 / 370–390 → 10, 350 / 360 AAA → 5, else 40). Air mode (400, `FUN_004ac820`)
  classes {0x1c, 3, 2, 1}; ground mode (410, `FUN_004ac900`) {10, 8, 9, 0xb, 0xd, 0x1d, 0x1e, 5, 6, 0xf, 0x10}. The
  player is seen only within 0.7·R while its radar is OFF / STBY (ctl+0xb4 ∈ {0, 1}); an emitter with ECM on is seen
  at any range; a sensing unit with ECM on: 0.8R vs a jamming target, else 0.5R. Accept (`FUN_004ac740`): hostile
  (`FUN_004a4cf0`) and terrain line of sight (`FUN_004020d0`, both ends +1.5 m). Score 100 / dist, best 5 kept
  (`FUN_004b08e0`), full rescan at most every 5.0 s.
- **Start combat** 550 (`FUN_00444b20`): engaged, `FUN_004aa900(0)` → `FUN_004ac120(1)`: fire timer, first shot at
  now + `_reactionTime`, then every `_fireReleaseInterval`, slot 0; the target locked on its RWR. 560: timer off.
- **Fire tick** (`FUN_004ab110`): T = brain+0x70 dead → timer stops. Class 0x17 (gun / rockets): range =
  `_limitDist` (×0.5 for 565 → 2250 m), t = |T − P| / `_limitVel`, aim = T + V_T·t + ½A_T·t² (lead). Class 0x18
  (missiles / SAMs): fire within the chase envelope (§13.1). Release `FUN_004ab810`: turret parts of types 250 and
  290–340 turn to the target; a **global truce** for all handlers (DAT_008321d0..d8): after each shot no other ground
  shot for 0.1 + rand·0.9 s ("Entities in truce"); busy pool object → skipped; terrain LOS +1.5 m; fire
  `FUN_004d7630` → `FUN_005604a0(T)` (single candidate); 565 / 660 play SFX_ENTITY_FIRED_WEAPON. Pool quirk: the ring
  advances 3–4 times per shot.
- **AAA round**: bdb 50 "AAA" (565, power 15, radius 30), the player's gun round model aimed at the lead point; hit
  sphere 25 m against T only (50 m with Easy aiming, original quirk: the option also helps the enemy); at the end time
  it bursts in the air (flak, area blast). Mission 313's ZSUs: brain 'mission' / 'zsu' start within 4000 m, shots
  only inside 2250 m, first 10 s later, then every 0.5 s (truce permitting).
- **SAMs**: class 8 launchers carry SA2 / 3 / 5 / 6 / 8 / Hawk (630), class 9 SA13 (620); no link between a site's
  radar and its launchers was found (each launcher fires on its own sensor). 000630: absAcc 70, burn 20 + 15 + 10, tCO
  3, 1 in the air, interval 30 s, reaction 20 s; 000620: absAcc 100, burn 5 + 10 + 5, interval 10 s, reaction 1 s;
  both spiral 1000 / β 0.08, chase 2, highAngleTurn (overshoot ends the flight only within 1000 m). Ground launch at
  100.1 m/s along the nose, q = 1.0, the IR missile engine (docs/weapons.md §5.3): no illumination needed.
- **Decoys** (`FUN_00454b70` at the release, the releasing jet's RWR missile list): see docs/weapons.md §10.
- **RWR** (ctl+0x5b0, ctor `FUN_004515d0`): 10 slots × 0x24 (+0 unit, +4 threat type = bdb type code, +8 position,
  +0x14 launch flag, +0x18 missiles in flight, +0x1c drop pending, +0x20 active), count +0x174, missile list +0x178.
  Emitter test `FUN_004521c0`: ≤ 37080 m (0x600d14); classes 8, 9, 10, 5, 16 always; others only > 120° off the
  nose or after a launch. Add `FUN_0044deb0` when a sensor locks (start combat, 420, retargets, a radar in STT);
  blocked by damage flag 14; types 220 / 250 / 270 ignored; list full refuses. A new active entry lights lamp 4 'sam'
  (classes 8, 9, 10, 5, 16) or 3 'ai' (corrects docs/cockpit.md: any active entry, not only a guiding missile) and
  plays WRN_NEW_GUY 0x18002000 (≤ once per 1.0 s, ctl+0x860). Launch `FUN_0044e160` (every class-0x18 missile): launch
  flag, WRN_MISSILE_LAUNCH 0x18003000 loop until no flag is left (`FUN_00451e30`), Betty "Missile" 0x2c002000 on
  every launch (ctl+0x964). Every 2.0 s positions refreshed, active = emitter test or launch flag (full trace and
  the port: docs/rwr.md). Display
  `FUN_00531470`: active entries, launch-flag ones blink (300 ms), distance clamped 37060 m; original bug: slots are
  not compacted and only the first `count` are copied (`FUN_00446200`). No separate lock tone. Damage 14 / 19 / 21
  clear the list. brain+0x7c is written with the target itself (original bug).
- **Script op 2** (0x5c42f0 → `FUN_004aae40(handler, key, p3)`): ignored when handler+0x48 == 2; the target from the
  key (`FUN_00439b40`), {target pose, target, q 1.0} → `FUN_004ab810(…, p3 ? 2 : 0)` (turret / truce / LOS / fire);
  with handler+0x28 == 1 the truce is skipped ("Fired a weapon by the Scenario"); the current slot, no range check.
  **Op 1** (0x5c4160 → `FUN_004aad10`): `FUN_004ab810(pose, 1)` at a point. UNCERTAIN: the trigger fields → args.

## UNCERTAIN
- Avionics sensors behind conditions 8, 10, 14, 19, 21, 26, 27, 38, 39; what writes brain+0x7c.
- The pitch law's tail (`5ca010`), the speed law's acceleration term, the formation loops' details (§8.4).
- Waypoint actions 1, 4, 5, 6; the sim clock origin of the waypoint times (mission start taken).
- The leader flag gating the wingman's take-off roll; the taxi re-placement's 60 m sign; what happens after parking
  (the root timer keeps running ParkInHangar).
- (Resolved) Kfir and Mirage share one FM parameter block (`0x8442d4`), read once per game session: ported with
  Flight data = Original (docs/flight-model.md §1, `iaf_flight::data_set::Blocks`).
