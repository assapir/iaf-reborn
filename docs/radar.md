# The player's radar

The radar manager of the player's controller (`ctl+0x84`, `FUN_004acc20`, v1.1 addresses) and how ours follows it
(`crates/iaf-avionics/src/radar.rs`, unit tests there; run through `IafRadar` by `game/weapons/radar.gd`, owned by `player_weapons.gd`; drawn by `cockpit/mfd.gd` and `cockpit/hud.gd`). The MFD page
geometry is in docs/mfd.md §"Radar (2)". World frame X east, Y north, Z up, metres, sim seconds.

## 1. Modes and tables
Modes (`+0x30`): 0 OFF, 1 STBY, 2 STT, 3 BORE, 4 LRS, 5 TWS, 6 ACM, 7 GMT, 8 MAP. Other state: last A-A mode `+0x34`
(starts LRS), last A-G mode `+0x38` (starts GMT), mode saved under BORE `+0x3c`, A-A flag `+0x40`, not-radiating flag
`+0x44` (OFF / STBY), damaged `+0x48`, boresight key held `+0x54`, the selected / locked record `+0x58`. The radar is
created OFF in A-A (`FUN_004ace60`).

Range scales (`FUN_004b0020`, `0x603358..`): index 1..6 = 5 · 2^(i−1) NM at 1851.87 m/NM (5, 10, 20, 40, 80, 160 NM). A
mode starts at min(max index, 4); BORE at its max. Detection range: the table's NM × 1854 m (`0x603390`).

Per cockpit index (`FUN_00447e70`: bdb type code 110 F-15 → 0, 100 F-16 → 1, 200 F-4-2000 → 2, 140 Lavi → 3, 130 Kfir →
4, 120 F-4E → 5, 190 Mirage → 6, 180 MiG-29 → 7, 160 MiG-23 → 8): A-A table `0x640a74` [LRS, TWS, ACM, BORE] and A-G
table `0x640bbc` [MAP, GMT], each (max range index, detection NM); (0, 0) = no such mode.

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

STT takes LRS's (max index, NM), else ACM's.

## 2. Keys (`FUN_0044a240`)
| key | event | rule |
|---|---|---|
| Q | 0x24 (`FUN_004ad6f0`) | A-A: LRS → TWS → ACM → LRS (missing modes skipped; leaving STT unlocks); A-G: GMT ↔ MAP; an off radar starts |
| R | 0x2b (`FUN_004ad8f0`) | A-G or off → the last A-A mode, else the last A-G mode (the lock is dropped). If no MFD shows the radar, R first puts the page up |
| S | 0x2c (`FUN_004ad9c0`) | STBY (an on radar is turned off first: lists cleared) |
| . / , | 0x21 / 0x22 (`FUN_004adb70`) | range index ±1 in [1, max] (not in STT), then a scan |
| \ down / up | 0x2d / 0x2e | BORE while held (A-A only), back to the saved mode |
| Return / Shift+Return | 0x26 / 0x27 (`FUN_004aefd0`) | the cursor to the next / previous contact (wraps, needs ≥ 2); in LRS it also locks (→ STT); in STT it unlocks |
| click on a blip (LRS) | 0x2a (`FUN_004adca0`) | lock that contact; from TWS straight to STT |
| Backspace | 0x31 (`FUN_004add60`) | drop the lock (STT → the last A-A mode); without a lock: clear the designated point (+0x50 / +0x58 / +0x5c = 0; the EXP flag stays) |
| MAP click off the contacts | 0x2f (`FUN_004ade90`) | a lock is dropped, then the point is designated: +0x58 / +0x5c = X / Y, +0x60 = the terrain height there (`FUN_00402080`), +0x50 = 1 |
| MAP OSB 3 | 0x30 (`FUN_004ade70`) | only with a designated point: the EXP flag +0x4c toggles (state+0xa18; +0x50 → state+0xa1c) |

Radar events first put the radar page on an MFD if none shows it (docs/mfd.md).

## 3. Per frame (`FUN_004ad300`)
- Heading shift (state+0xa14): the own heading change since the last push to the cockpit, so the B-scope blips
  turn with the jet between scans.
- Antenna sweep (`FUN_004b0340`, cosmetic): azimuth caret 0 → 1 → 0 over 4.0 s (BORE 1.0 s, `0x6033b8` / `0x6035e8`),
  the elevation bar steps 0.25 per sweep and reverses at 0 / 1. STT: carets centred.
- `FUN_004adde0`: an A-A lock outside TWS goes to STT; STT without a lock goes to BORE (key held) or the last A-A mode
  and scans.
- A full scan every 2.0 s (`DAT_0082f4a8`) and on mode / range / key events.
- STT: the track (§5) every frame.

## 4. The scan (`FUN_004af300`) and the hit test (`FUN_004aeb90`)
1. Candidates: the units with |c − C|² < 3 · (r + R/2)² (`0x604e6c`), C = own + antenna · R/2, R = the range scale,
   r = the unit's collision radius; destroyed / dying units (state 4 / 5) skipped.
2. Class filter (vt+0x3c): air modes classes 0x1c, 3, 2, 1 (`FUN_004b1c70`); MAP 10, 8, 9, 0xb, 0xd, 0x1d, 0x1e, 5, 6,
   0xf, 0x10 (`FUN_004b0ce0`); GMT 5, 6, 0xf, 0x10, 8, 9, 10, 0xb, moving only (`FUN_004b0fc0`).
3. Detection range: distance ≤ the mode's NM × 1854 m.
4. Hit test: air modes skip targets lower than 30 m above the terrain (`0x60337c`); the horizontal cone about the
   antenna only, cos 0.5 = ±60° in every mode, cos 0.978 = ±12° in BORE (`0x603440..`, `0x6035d8`; no elevation
   limit); terrain line of sight between the ends raised 1.5 m (`0x603380`, `FUN_004020d0`).
5. The record: position, heading, aspect (target heading − line-of-sight bearing), azimuth / elevation off the nose,
   distance, speed (kt, ×1.9427955 `0x600a70`), type; priority 100 / distance.
6. The list (`FUN_004b08e0`): 15 at most, highest priority (nearest) first; when full a record replaces the last only
   with a strictly higher priority.
7. The old selection is kept when its unit is still a candidate, re-tested without the detection range.
8. The cursor: the old selection if still listed, else the nearest; a new selection tells the target its RWR hears a
   lock (on-lock / on-unlock `4b0510` / `4b04d0`; the AI's reaction waits for AI combat).
9. BORE and ACM lock the selection at once (`FUN_004b19c0` → `FUN_004b06b0`).

## 5. STT (`FUN_004b1300`, every frame)
The locked unit is re-tested (STT's detection range, the 60° cone, terrain, 30 m AGL); a failure unlocks. Auto-range
(`FUN_004b1590`): below 0.33 · R (`0x60355c`) one scale down, above 0.75 · R (`0x603560`) one up.

## 6. What uses the lock
Every user reads the target's position through `FUN_0044e370`: with a lock (TWS: the selection) the locked unit's
position at the current sim time, every frame, not the scan record (the B-scope blips still move only on a scan). Ours:
`locked()` outside STT returns the record with its unit's position and distance of this frame (STT's record is re-made
every frame by the track).
- **HUD** (`FUN_00537330`): the target designator box, 15 px (10 px in GMT / MAP) at the locked unit's projection,
  held at the HUD edge with a line from the centre when outside; an X inside for a friendly unit. The weapon line gets
  "R %2.1f" (NM, ×0.00053937 `0x600f58`) and, in HUD modes 1 / 3, the aspect "%2dL" / "%2dR" (row placement
  UNCERTAIN). In BORE (S+0xa04 = 3, `FUN_0052f690`) a cross on the HUD centre, ±30 px across and ±20 px up / down.
- **IR seeker** (`FUN_00461680`, `FUN_004625f0`): any lock clears the seeker's own target; an A-A lock slaves it to the
  locked unit at once (no 0.5 s gate, no HUD circle), with the per-generation cone in place of the 6° view.
- **Gun**: the rounds' candidate target, the LCOS range (feet = metres × 3.28084 `0x601478`, at most 3148.8;
  without a lock 1476.378) and the pipper's range arc (S+0x388, docs/weapons.md §3.7).
- **MFD**: the page per mode (docs/mfd.md): B-scope blips (BORE / ACM box with diagonal, LRS double box, TWS box /
  disc with aspect stub, STT disc and the speed / aspect / range caret / closure text), GMT / MAP PPI symbols.

## 7. Damage
Cases 0xf / 0x13 / 0x15 (`FUN_004adb20`): the radar goes OFF and every call is a no-op (`set_damaged`, from `player_weapons.gd`
when the player's damage flag 15 is set; generator failures 19 / 21 set it too, docs/damage.md §5.2).

## 8. Not built / ours
- ECM and jammers (both sides): no jammer exists yet.
- What uses the designated point: not the bombs / rockets (docs/weapons.md §9.3); the TV / laser weapons' use is not
  traced yet.
- The STT range scale's envelope ticks are drawn (the selected store's DLZ, docs/weapons.md §11.2, docs/mfd.md).
- Semi-active missiles (610): a launch locks STT; every track drop / change turns their guidance off (`FUN_00458130`,
  docs/weapons.md §11.4); radar damage does not (original quirk kept).
- Terrain line of sight: ours samples every 100 m (the original's sampling is UNCERTAIN).
- Weapon data Real: the LRS / STT detection range of each Jet list jet is its real radar's (F-16 APG-68 80 km, F-15
  APG-63 135 km, …; docs/real-weapons.md §1.3); the MiGs keep the table.

## 9. Validation
`tests/godot/test_radar.gd`: the F-16 table, the detection range and the kept selection, the 60° cone; in mission 221
an AI jet 20 km out at 20° right shows at that range and bearing, a click-lock goes to STT with auto-range to the 20 NM
scale, the IR seeker is slaved to it, the HUD box is held at the right edge with the friendly X, the lock follows the
moving unit every frame (STT and TWS; the TWS blip waits for the scan), Backspace returns to LRS, S to STBY.
