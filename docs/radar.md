# The player's radar

This doc describes the radar manager of the player's controller (`ctl+0x84`, `FUN_004acc20`, v1.1 addresses) and
how ours follows it.

- **Code:** `crates/iaf-avionics/src/radar.rs` (unit tests there). `IafRadar` runs it for `game/weapons/radar.gd`,
  which `player_weapons.gd` owns. `cockpit/mfd.gd` and `cockpit/hud.gd` draw it.
- **MFD page geometry:** docs/mfd.md §"Radar (2)". MFD is the multi-function display; HUD is the head-up display.
- **Frame and units:** world frame X east, Y north, Z up; metres; sim seconds.
- **Key facts:** 9 modes (§1); a full scan every 2.0 s (§3); at most 15 contacts, nearest first (§4); the lock is read
  at the target's live position every frame (§6).

## 1. Modes and tables
Modes (`+0x30`):

| value | mode | meaning |
|---|---|---|
| 0 | OFF | off |
| 1 | STBY | standby: on, not radiating |
| 2 | STT | single-target track |
| 3 | BORE | boresight: a narrow cone straight ahead |
| 4 | LRS | long-range search |
| 5 | TWS | track while scan |
| 6 | ACM | air combat mode: short range |
| 7 | GMT | ground moving target |
| 8 | MAP | ground map |

A-A is air-to-air; A-G is air-to-ground.

Other state:
- last A-A mode `+0x34` (starts LRS);
- last A-G mode `+0x38` (starts GMT);
- mode saved under BORE `+0x3c`;
- A-A flag `+0x40`;
- not-radiating flag `+0x44` (OFF / STBY);
- damaged `+0x48`;
- boresight key held `+0x54`;
- the selected / locked record `+0x58`.

The radar is created OFF in A-A (`FUN_004ace60`).

**Range scales** (`FUN_004b0020`, `0x603358..`): index 1..6 = 5 · 2^(i−1) NM at 1851.87 m/NM (5, 10, 20, 40, 80,
160 NM). A mode starts at min(max index, 4); BORE starts at its max.

**Detection range:** the table's NM × 1854 m (`0x603390`).

Per cockpit index (`FUN_00447e70`: bdb type code 110 F-15 → 0, 100 F-16 → 1, 200 F-4-2000 → 2, 140 Lavi → 3, 130 Kfir →
4, 120 F-4E → 5, 190 Mirage → 6, 180 MiG-29 → 7, 160 MiG-23 → 8): A-A table `0x640a74` [LRS, TWS, ACM, BORE] and A-G
table `0x640bbc` [MAP, GMT]. Each entry is (max range index, detection NM); (0, 0) means the jet lacks that mode
(– in the table).

| jet | LRS | TWS | ACM | BORE | MAP | GMT |
|---|---|---|---|---|---|---|
| F-15 | 6, 90 | 4, 40 | 2, 10 | 2, 10 | 4, 40 | 4, 20 |
| F-16 | 5, 45 | 4, 35 | 2, 10 | 2, 10 | 4, 40 | 4, 30 |
| F-4 2000 | 5, 55 | 4, 40 | 2, 10 | 2, 10 | 5, 60 | 5, 40 |
| Lavi | 6, 90 | 4, 40 | 2, 10 | 2, 10 | 5, 60 | 5, 40 |
| Kfir | 2, 8 | – | 1, 5 | 1, 5 | 2, 10 | 2, 10 |
| F-4E | 4, 25 | – | 2, 10 | 2, 10 | 2, 10 | 2, 10 |
| Mirage | 2, 8 | – | 1, 5 | 1, 5 | 2, 10 | 2, 10 |
| MiG-29 | 5, 45 | 4, 35 | 2, 10 | 2, 10 | 2, 10 | 2, 10 |
| MiG-23 | 4, 25 | – | 2, 10 | 2, 10 | 4, 40 | 4, 25 |

STT takes LRS's (max index, NM). A jet without LRS uses ACM's.

Ours: with Extras "F-16 version" on Sufa, an F-16 takes a tenth row, index 9, for the F-16I's AN/APG-68(V)9 (30 %
more air-to-air range; docs/f16i.md §2):

| jet | LRS | TWS | ACM | BORE | MAP | GMT |
|---|---|---|---|---|---|---|
| F-16I | 5, 58 | 4, 45 | 2, 10 | 2, 10 | 4, 40 | 4, 30 |

## 2. Keys (`FUN_0044a240`)
| key | event | rule |
|---|---|---|
| Q | 0x24 (`FUN_004ad6f0`) | A-A: LRS → TWS → ACM → LRS (missing modes skipped; leaving STT unlocks); A-G: GMT ↔ MAP; an off radar starts |
| R | 0x2b (`FUN_004ad8f0`) | A-G or off → the last A-A mode, else the last A-G mode (the lock is dropped). M calls it too (docs/mfd.md §5) |
| S | 0x2c (`FUN_004ad9c0`) | STBY (an on radar is turned off first: lists cleared) |
| . / , | 0x21 / 0x22 (`FUN_004adb70`) | range index ±1 in [1, max], then a scan; ignored in STT |
| \ down / up | 0x2d / 0x2e | BORE while held (A-A only), back to the saved mode |
| Return / Shift+Return | 0x26 / 0x27 (`FUN_004adbc0` → the mode's vt+0x2c, walk `FUN_004aefd0`) | the cursor (record +0x18) to the next / previous contact (wraps, needs ≥ 2); LRS also locks it (→ STT, `FUN_004b21e0`); **GMT / MAP drop the lock, walk and lock the new one** (`FUN_004b0cb0`: `FUN_004b0680`, walk, `FUN_004b06b0`: record +0x14; a single contact gets locked); TWS / BORE / ACM only walk; in STT it unlocks. Then (`FUN_0044a240` @44a923) with the TV camera running, a Maverick (635) selected and the radar on a target, the TV camera restarts on it (`FUN_00450280`) |
| click on a blip (LRS), double-click (TWS, GMT, MAP) | 0x2a (`FUN_004adca0`) | lock that contact; from TWS straight to STT |
| press on a blip (TWS) | 0x32 (`FUN_004add20` → vt+0x38(id, 0) → `FUN_004b05a0`) | select that contact, unlocked (a locked selection of the same unit stays); no illumination loss, the mode stays |
| Backspace | 0x31 (`FUN_004add60`) | drop the lock (STT → the last A-A mode); without a lock: clear the designated point (+0x50 / +0x58 / +0x5c = 0; the EXP flag stays) |
| MAP click off the contacts | 0x2f (`FUN_004ade90`) | a lock is dropped, then the point is designated: +0x58 / +0x5c = X / Y, +0x60 = the terrain height there (`FUN_00402080`), +0x50 = 1 |
| MAP OSB 3 | 0x30 (`FUN_004ade70`) | only with a designated point: the EXP flag +0x4c toggles (state+0xa18; +0x50 → state+0xa1c) |

Radar events first put the radar page on an MFD if none shows it (docs/mfd.md).

## 3. Per frame (`FUN_004ad300`)
- Heading shift (state+0xa14): the own heading change since the last push to the cockpit. It turns the B-scope blips
  with the jet between scans.
- Antenna sweep (`FUN_004b0340`, cosmetic): azimuth caret 0 → 1 → 0 over 4.0 s (BORE 1.0 s, `0x6033b8` / `0x6035e8`),
  the elevation bar steps 0.25 per sweep and reverses at 0 / 1. STT: carets centred.
- `FUN_004adde0`: an A-A lock outside TWS goes to STT. STT without a lock goes to BORE (key held) or to the last A-A
  mode, and scans.
- A full scan every 2.0 s (`DAT_0082f4a8`) and on mode / range / key events.
- STT: the track (§5) every frame.

## 4. The scan (`FUN_004af300`) and the hit test (`FUN_004aeb90`)
Each scan builds the contact list in these steps:

1. Candidates: the units with |c − C|² < 3 · (r + R/2)² (`0x604e6c`), C = own + antenna · R/2, R = the range scale,
   r = the unit's collision radius. Destroyed / dying units (state 4 / 5) are skipped.
2. Class filter (vt+0x3c): air modes classes 0x1c, 3, 2, 1 (`FUN_004b1c70`); MAP 10, 8, 9, 0xb, 0xd, 0x1d, 0x1e, 5, 6,
   0xf, 0x10 (`FUN_004b0ce0`); GMT 5, 6, 0xf, 0x10, 8, 9, 10, 0xb, moving only (`FUN_004b0fc0`).
3. Detection range: distance ≤ the mode's NM × 1854 m.
4. Hit test:
   - Air modes skip targets lower than 30 m above the terrain (`0x60337c`).
   - Cone: horizontal only, about the antenna: cos 0.5 = ±60° in every mode, cos 0.978 = ±12° in BORE (`0x603440..`,
     `0x6035d8`). Elevation is unlimited.
   - Terrain line of sight between the two ends, each raised 1.5 m (`0x603380`, `FUN_004020d0`).
5. The record: position, heading, aspect (target heading − line-of-sight bearing), azimuth / elevation off the nose,
   distance, speed (kt, ×1.9427955 `0x600a70`), type; priority 100 / distance.
6. The list (`FUN_004b08e0`): 15 at most, highest priority (nearest) first. When the list is full, a record replaces
   the last one only with a strictly higher priority.
7. The old selection is kept when its unit is still a candidate, re-tested without the detection range.
8. The cursor: the old selection if it is still listed, else the nearest. A new selection tells the target that its
   RWR (radar warning receiver) hears a lock (on-lock / on-unlock `4b0510` / `4b04d0`; an AI target gets brain+0x7c,
   docs/rwr.md §2).
9. BORE and ACM lock the selection at once (`FUN_004b19c0` → `FUN_004b06b0`).

## 5. STT (`FUN_004b1300`, every frame)
Every frame the locked unit is re-tested: STT's detection range, the 60° cone, terrain, and 30 m AGL (above ground
level). A failure unlocks.

Auto-range (`FUN_004b1590`): below 0.33 · R (`0x60355c`) the scale goes one down; above 0.75 · R (`0x603560`) one up.

## 6. What uses the lock
Every user reads the target's position through `FUN_0044e370`. With a lock (in TWS: the selection) it returns the
locked unit's position at the current sim time, every frame; the scan record is used only for the B-scope blips, which
still move only on a scan. Ours: `locked()` outside STT returns the record with its unit's position and distance of
this frame. In STT the track re-makes the record every frame.

- **HUD** (`FUN_00537330`): the target designator (TD) box, 15 px (10 px in GMT / MAP), at the locked unit's
  projection. When the unit is off the HUD, the box is held at the HUD edge with a line from the centre. A friendly
  unit gets an X inside the box. The weapon line gets "R %2.1f" (NM, ×0.00053937 `0x600f58`) and, in HUD modes 1 / 3,
  the aspect "%2dL" / "%2dR" (row placement UNCERTAIN). In BORE (S+0xa04 = 3, `FUN_0052f690`) a cross sits on the HUD
  centre, ±30 px across and ±20 px up / down.
- **IR seeker** (`FUN_00461680`, `FUN_004625f0`): any lock clears the seeker's own target. An A-A lock slaves the
  seeker to the locked unit at once: there is no 0.5 s gate and no HUD circle, and the per-generation cone replaces
  the 6° view.
- **Gun:** the rounds' candidate target; the LCOS (lead-computing optical sight) range (feet = metres × 3.28084
  `0x601478`, at most 3148.8; 1476.378 without a lock); the pipper's range arc (S+0x388, docs/weapons.md §3.7).
- **MFD:** the page per mode (docs/mfd.md): B-scope blips (BORE / ACM box with diagonal, LRS double box, TWS box /
  disc with aspect stub, STT disc and the speed / aspect / range caret / closure text), GMT / MAP PPI (plan position
  indicator) symbols.

## 7. Damage
Damage cases 0xf / 0x13 / 0x15 (`FUN_004adb20`) turn the radar OFF, and every later call is a no-op. Ours:
`player_weapons.gd` calls `set_damaged` when the player's damage flag 15 is set. Generator failures 19 / 21 set it too
(docs/damage.md §5.2).

## 8. Ours
- **ECM (electronic countermeasures):** the player's jammer is built (docs/weapons.md §10). AI units carry no ECM,
  so the launch q − rand of `_launch_target` never applies. The AI's scans and launches react to the player's jammer
  (docs/ai.md §13).
- **The designated point** (+0x58 / +0x5c / +0x60, written by `FUN_004ade90`) is read by the MAP page's cross and
  the HUD's TD box, as in the original:
  - the flag +0x50 goes to state+0xa1c (`FUN_00445f10`), which the MFD cross (`FUN_00535ea0`) and the HUD read;
  - `FUN_0052f690` calls the TD box `FUN_00537330` with a lock or a designation. The box sits at S+0xff4, the target
    point of `FUN_0045a810` → `FUN_0044e370`: the lock or, without one, the vector at ctl+0xdc. The radar sits at
    ctl+0x84, so ctl+0xdc..0xe4 is radar+0x58..0x60, the designated point. Ours: `hud.gd` `target_box` draws the box
    at the lock, else at the designated point;
  - no bomb / rocket aim (docs/weapons.md §9.3), EO / FLIR / TV slew or laser reads it. The game has no CCRP
    (continuously computed release point).
- **STT envelope ticks:** the selected store's DLZ (dynamic launch zone) on the STT range scale (docs/weapons.md
  §11.3, docs/mfd.md).
- **Semi-active missiles (610):** a launch locks STT; a track drop or change turns their guidance off (docs/weapons.md
  §11.4).
- **Terrain line of sight** (`line_of_sight`; also used by the HARM sensor and by the ground units' sensors / fire,
  `IafRadar.line_of_sight`): ours steps by the clearance, at least every 20 m, so it never steps over a narrow ridge
  (the original's sampling is UNCERTAIN). The heights come from the Rust height field `IafHeights`
  (crates/iaf-avionics/src/heights.rs: the full-detail nodes terrain.gd streams, the same interpolation as
  `height_at`), with no GDScript call per sample (tests/godot/test_heights.gd).
- **Weapon data Real:** the LRS / STT detection range of each Jet list jet is its real radar's (F-16 APG-68 80 km,
  F-15 APG-63 135 km, …; docs/real-weapons.md §1.3). The MiGs keep the table. The F-16I's is the F-16's × 1.3,
  104 km.

## 9. Validation
`tests/godot/test_radar.gd` checks:
1. the F-16 table, the detection range, the kept selection and the 60° cone;
2. in mission 221, an AI jet 20 km out at 20° right shows at that range and bearing;
3. a click-lock goes to STT, with auto-range to the 20 NM scale;
4. the IR seeker is slaved to the lock;
5. the HUD box is held at the right edge, with the friendly X;
6. beyond R/2 the seeker locks only with the AI jet's afterburner lit;
7. 5 km ahead, the SRM (short-range missile) shoot cue shows and the circle shrinks;
8. the lock follows the moving unit every frame (STT and TWS; the TWS blip waits for the scan);
9. Backspace returns to LRS; S goes to STBY.
