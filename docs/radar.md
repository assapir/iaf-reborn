# The player's radar

This doc describes the radar manager of the player's controller (`ctl+0x84`, `FUN_004acc20`, v1.1 addresses) and
how ours follows it.

- **Code:** `crates/iaf-avionics/src/radar.rs` (unit tests there). `IafRadar` runs it for `shared/weapons/radar.gd`,
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
| F-35I | 5, 80 | 5, 60 | 2, 10 | 2, 10 | 5, 60 | 4, 40 |

The F-35I's AN/APG-81 (row 10, `F35I`; docs/f35i.md) is used with either Weapon data, as the Sufa's: the 1998 game
has no F-35I row to fall back on (its numbers are inferred; public figures give only "beyond 80 NM"). Both our rows
start every mode at its largest scale, 80 NM, as their search reaches past the original's 40 NM start (the user,
2026-10-30); the original jets start at min(max, 4).

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
- **Radar cross-section (ours):** a unit that carries an `rcs` (Modern IAF's one-way attack drones,
  `shared/ai/drones.gd`) is found and tracked inside the mode's detection range × (σ / 5 m²)^¼, σ its cross-section
  from the jet's side (`radar.rs` `sigma` / `reach`, docs/ai.md §15.2, §16). Every other unit, the 1998 game's all, is
  found at the table's range, as in the original.
- **Weapon data Real:** the LRS / STT detection range of each Jet list jet is its real radar's (F-16 APG-68 80 km,
  F-15 APG-63 135 km, …; docs/real-weapons.md §1.3). The MiGs keep the table. The F-16I's is the F-16's × 1.3,
  104 km.

## 9. Ours: the real F-16 FCR (the Sufa, the Barak, the Adir)

A jet whose aircraft definition has `radar.fcr` flies the real F-16 fire-control radar's controls on top of the
game's modes (`crates/iaf-avionics/src/radar.rs` `Fcr`, `Real`; avionics-plan.md slice 2). Today that is the F-16I
Sufa (`shared/extra/planes/f16i/airframe.json`: `{"sam_tracks": 4}`) and Modern IAF's Barak, the same code with
`{"sam_tracks": 1}` on the F-16's row (`modern-iaf/data/planes/f16.json`; avionics-plan.md B1), and Modern IAF's
F-35I Adir, the same code on the APG-81's row with `{"sam_tracks": 4}` (`shared/extra/planes/f35i/airframe.json`; the
count inferred, the APG-81 does "multiple target track"; avionics-plan.md A2–A5): the same modes, keys, A-G ground map
and picture, drawn on the PCD's SRCH and ASR ([f35i.md](f35i.md) §4.3; the ASR's picture grey, the SAR map of LM's
slide). The FCR format's legends follow the dash-34 ([real-mfd.md](real-mfd.md) "FCR"); the
jets without `radar.fcr` keep the original's radar unchanged. Only Modern IAF applies `radar.fcr`
(`Settings.modern_radar()`): the 1998 game's Sufa (Extras "F-16 version") keeps the original's radar, whose keys it
has.

### 9.1 Power, STBY and weight on wheels
Ours, in Modern IAF (`Settings.modern_radar()`; every sim jet: the Sufa, the Barak, the Adir), and for the F-35I in
both games: it has no radar switch (the mission systems run the radar; its definition's `radar.auto`), so the 1998
game's F-35I follows these rules too instead of starting OFF:
- The radar comes up in STBY: at its creation, and each time the FCR switch powers it again (`set_damaged(false)`).
  The FCR format shows `STBY`.
- With weight on wheels it does not radiate (no scan, no contacts). A mode chosen on the ground shows, and the radar
  radiates from the first frame in the air. While a mode is chosen and nothing radiates (weight on wheels, OVRD) the
  FCR reads `NO RAD` low on the scope (forums disagree on whether the real one shows it; inferred from simulators).
- Q or R out of STBY gives the last A-A mode (CRM) without stepping on.
- Airborne in STBY after power-on, the radar goes to CRM by itself (inferred), unless the pilot pressed S, Q, R or a
  TMS key first.

### 9.2 Scan volumes
The original's 60° horizontal cone with no elevation limit becomes the real FCR's volume (the hit test also needs
the target inside it):

| mode | azimuth | elevation | about |
|---|---|---|---|
| CRM RWS / VSR | A6 ±60°, A3 ±30°, A1 ±10° (OSB 18) | B4, B1, B2 bars (OSB 17) of 3° each about the antenna elevation | the horizon and the heading; A3 / A1 centred on the cursor's azimuth |
| CRM TWS | ±25° / 3 bars (first), ±10° / 4, ±60° / 2 (OSB 18 or 17 steps the pair) | as RWS | as RWS |
| ACM 20 | ±15° | −5°..+15° | the jet's axes |
| ACM 60 | ±5° | −5°..+55° | the jet's axes |
| ACM SLEW | ±30° about the cursor's azimuth | ±10° about the antenna elevation | the horizon |
| ACM BORE | ±2° | ±2° | the jet's axes |

- The scan widths, bar counts and TWS pairs are the dash-34's (p. 1-122, p. 1-139). The bar height (3°), the scan
  rate (60°/s: an A6 B4 frame takes 8 s, an A1 B1 frame 0.5 s at the least) and the ACM volumes are inferred. The ACM
  shapes follow simulator forums[^bms-slew][^dcs-acm]: 30 × 20 about the HUD's field, 10 × 60 scanning up, a 60° ×
  20° stabilised SLEW patch.
- The ACM patterns scan once a second (inferred). ACM and BORE stay at 10 NM.
- The antenna elevation moves 10°/s while its key is held, to ±60° (inferred). The carets on the FCR show the beam
  sweeping the volume bar by bar.
- The FCR draws the scan limits as two vertical lines, and beside the cursor the highest and lowest altitudes (kft)
  the scan covers at the cursor's range (fig. 1-85).

### 9.3 Submodes
- **RWS:** the game's LRS. The real FCR's search bugs nothing by itself: the 1998 game's nearest-contact selection
  (and its lock notice to the target's RWR) applies in ACM, BORE, GMT and MAP only.
- **SAM (situation awareness):** in RWS, the first press on a target (TMS up, a click) bugs it; Return / Shift +
  Return bug the next / previous contact in turn. The radar
  keeps searching and revisits each bugged target every frame, inside the ±60° cone and the STT range, as STT's
  track does. The Sufa keeps four bugs (the APG-68(V)9's four tracked targets, Lockheed Martin 2002); the oldest goes
  when a fifth is bugged. The newest is the primary: it is the weapons' target, as TWS's bug is. A press on the
  primary locks it (STT). TMS down, or Backspace, drops the bugs.
- **TWS:** the track files stay 13 s without a return, moved on along their last velocity, and flash for their last
  8 s; at most 10 (p. 1-140). TWS bugs nothing by itself.
- **VSR:** a CRM submode on RWS's scan. It shows only closing targets, placed up the scope by closure, 0 to 1,200 kt
  (the scale inferred), with velocity marks every 400 kt on the right edge.
- **ACM:** OSB 2 shows the pattern (`20`, `60`, `SLEW`, `BORE`). No targets show until the lock; the first target
  inside the pattern locks (STT), as the original's ACM.
- **OVRD (OSB 4):** the radar stops radiating; the lock and the contacts go. TMS down on a lock taken in ACM goes back
  to the 30 × 20, so the same target is not locked again at once.
- **STT:** the mode row reads the mode the lock came from (`CRM RWS`, `CRM TWS`, `ACM 60` …; fig. 1-84).
- **The bug centres the scan:** with a target bugged (SAM's primary, TWS's bug) the RWS / TWS scan is centred on it in
  azimuth and elevation; without one, on the cursor's azimuth and the antenna elevation (p. 1-139; the elevation
  centring inferred).
- **EXP (OSB 3, the pinky switch):** in RWS and TWS a 4:1 expansion of the scope (p. 1-140) about the bugged target,
  else about the cursor's place when EXP was pressed; that place sits mid-scope. OSB 3 reads `EXP`; the scan limits
  and the steerpoint are not drawn over it; the cursor moves at its NORM speed over the expanded picture
  (`radar.rs` `exp_centre`, inferred).
- **CNTL page (OSB 5):** the dash-34's options by their OSBs (fig. 1-76, p. 1-116): CHAN 1–4 (6), MK INT 1–4 (7), BAND
  WIDE / NARO (8), PM ON / OFF (10), MTR LO / HI (20), ALT TRK OFF / ON (19), TGT HIS 1–4 (18), LVL 1–4 (17); a press
  steps the value, OSB 5 returns. TGT HIS n shows RWS's last n frames, the earlier returns as dimmer squares (p. 1-134;
  default 3). MTR sets the ground's band in look-down: a target slower than 60 kt (LO) or 100 kt (HI) along the line of
  sight is lost (§9.8; thresholds inferred). The sim has no radar channels, marker intervals, band, pulse modes, altitude-line
  tracker or levels to act on, so those options step and change nothing; BCN DLY (OSB 9) is left off: there is no BCN
  mode (`radar.rs` `CNTL`).
- **Range:** 10 to 160 NM in RWS / VSR, 10 to 80 NM in TWS (from 40 NM). The cursor bumps the scale: above 95 % up
  one, below 5 % down one. STT steps down below 40 % and up above 95 %; TWS and SAM step up when the bug passes 90 %,
  TWS down closer than 45 % (p. 1-131).

### 9.4 Keys and the cursor
The keyboard is the first-class input (the user, 17 November 2026: "I don't have hotas"). Modern IAF's key table
(`modern-iaf/data/keys.json` records 132–142, commands 221–227; the Keys screen's Sensors group):

| key | function (real switch) |
|---|---|
| `/` | TMS up: bug the target under the cursor, then lock it; ACM: BORE; A-G: track the return under the ground cursor, else designate its point (§9.7) |
| Shift + `/` | TMS down: drop the lock or the bugs; ACM, and a lock taken in ACM: back to the 30 × 20; A-G: drop the track or the designation, the cursor back on the steerpoint |
| `;` | TMS right: CRM's submode RWS → TWS → VSR (inferred: the real switch toggles RWS / TWS, VSR is on OSB 2); ACM: 10 × 60 |
| Shift + `;` | TMS left: ACM SLEW (inferred); in CRM the AIFF later (avionics-plan.md G13) |
| `'` | OSB 2: CRM's submode; ACM's pattern 20 → 60 → SLEW → BORE |
| Shift + `'` | OSB 18: the azimuth scan |
| Ctrl + `'` | OSB 17: the bars |
| Alt + Up / Alt + Down (held) | the antenna elevation thumbwheel |
| Ctrl + `/` | OSB 4: OVRD |
| Ctrl + `;` | OSB 3 / the pinky switch: EXP; A-G: NORM → EXP → DBS1 → DBS2 |
| Ctrl + arrows | the cursor control: it moves the sensor of interest (records 48–51; [mfd.md](mfd.md) §9 "Modern MFDs"): with the FCR the SOI the acquisition cursor (A-G: the ground cursor); with the HUD the SOI the cursor while no EO picture runs, else the EO sensor |
| Alt + `;` | A-G OSB 7: FZ (record 143, command 228) |
| Alt + `'` | A-G OSB 8: SP (record 144) |
| Alt + `/` | A-G OSB 9: CZ (record 145) |
| Alt + `.` | A-G OSB 10: STP / TGT (record 146) |

The mouse over the FCR puts the cursor, and a click on a blip presses TMS up there (A-G: the mouse puts the ground
cursor on the ground point under it, a double-click presses TMS up). Q, R, S, the range keys, `\`,
Return and Backspace keep their 1998 meaning. The TMS keys act on the radar while the FCR or the HUD is the sensor of interest; with the TGP or the HSD the SOI they act on that format ([mfd.md](mfd.md) §9 "Modern MFDs"). The FCR's OSBs 2, 3, 4, 17 and 18 do the same as their keys; the CNTL page's options are pressed on the MFD
(a click), as the real jet's are.

### 9.5 The HUD's ACM cues
While nothing is locked the F-16's Real HUD draws the pattern (`real_hud/f16.rs` `acm_cue`; the shapes inferred from
simulator forums[^bms-slew][^dcs-acm]): the 10 × 60 as a vertical line through the boresight from 5° below it up
(two lines 5° out would sit on the airspeed and altitude scales);
SLEW as a cross at its patch's centre, stabilised on the horizon; BORE as a cross on the boresight, larger than the
boresight cross. The 30 × 20 draws nothing: it fills the HUD's field.

### 9.6 Later slices
AIFF on TMS left (G13, slice 5); the SOI and DMS (G8's rest, slice 4). BCN and TF (avionics-plan.md G12) stay parked:
the plan builds them only on the user's word, and the sim has no radar beacons.

### 9.7 Air to ground: GM, GMT, SEA and AGR
The real FCR's ground modes on the game's MAP (GM, SEA) and GMT (`radar.rs` "the real FCR's air-to-ground modes";
avionics-plan.md slice 3; the layout from the dash-34's GM, figs. 1-97 / 1-100, [real-mfd.md](real-mfd.md) "A-G
modes"). Only the jets with `radar.fcr`; the original's MAP / GMT stay as §1–§8 describe.
- **Modes (OSB 1):** OSB 2 reads `MAN`, the manual range option, and changes nothing (the range keys and OSBs 20 /
  19 set the scale). R from A-A gives GM first; Q steps GM → GMT → SEA → GM. GM to 80 NM (10, 20, 40, 80; it starts
  at 40), GMT to 40 NM (p. 1-150). SEA lists ships only (classes 15 and 16); GMT movers only; GM every ground return.
  The ground modes bug nothing by themselves (the original's nearest selection stays off); Return and Shift + Return
  still walk and lock as in §2.
- **The display:** NORM is the PPI fan from (66, 109), 94 px = the range scale, heading-up about the jet. EXP, DBS1
  and DBS2 show a patch about the ground cursor, mid-display, at 4, 8 and 64 times the scale (a simulator guide[^chuck];
  the A-A EXP's 4:1 is the dash-34's), with the 1500 ft yardstick top left where it fits. GMT and SEA have EXP but no
  DBS (pp. 1-150, 1-151). DBS needs the patch off the ground track: within 10° of it OSB 3 skips DBS1 / DBS2 and a DBS
  patch falls back to EXP (inferred; the real limit is open). A manual range step returns to NORM (inferred from a
  simulator).
- **The picture** (`radar.rs` `render`, one per radar frame, 108 × 106 px over the window (12, 12)–(120, 118); inferred
  shading): the ground's return grows with its slope toward the radar, with a fixed speckle; water (the sea level) and
  the runways (`shared/terrain/airbases.gd`) return nothing; the terrain's shadow is dark (one march per 0.25° of
  azimuth from the jet, the steepest rise so far; the bare ground's heights, no roofs or trees); outside the NORM fan black;
  the listed returns bright, as large as their units. `mfd.gd` draws it at a display gain of 2.2 (the GM format's
  gain; inferred). GMT dims the map to 35 % under its movers (p. 1-150). Where the
  terrain's heights are not streamed the picture is clear and the theatre's land / water map (`isr.png`) shows under
  it. `mfd.gd` `_draw_ag_picture` draws the last picture through its own frame, so it stays on the ground as the jet
  moves between frames. One frame with its picture costs about 11 ms on the Linux laptop (GM at 40 NM, every 2 s;
  `test_sim_fcr_ag.gd` holds it under 40 ms).
- **The ground cursor:** a world point, ground-stabilised: the X-Y cursor lines cross on it. It starts on the
  steerpoint (when within the range scale), else half the scale ahead; the cursor keys and the mouse move it; slewed
  beyond 95 % or inside 5 % of the scale in NORM it bumps the scale (p. 1-122). Bottom right: the time to it at the
  ground speed (fig. 1-97 `00:29`).
- **OSB 7 FZ:** the picture, its returns and the frame held (a ground track keeps following its unit, so the weapons'
  point stays live); the jet's symbol moves over the frozen map; FZ again, a
  mode or range change ends it. **OSB 8 SP:** the cursor held half the scale ahead of the jet until SP again, a slew or
  a TMS up. **OSB 9 CZ:** the slews removed: the cursor back on the steerpoint (STP) or the designated point (TGT).
  **OSB 10:** `STP` / `TGT`, CZ's point; TMS up sets TGT, TMS down STP.
- **TMS up:** a return within 4 px of the cursor is tracked (GM / SEA: FTT, GMT: the mover): the solid diamond, the
  cursor riding it; else the cursor's point is designated (the diamond, the HUD's TD box). **TMS down:** the track or
  the designation dropped, the cursor back on the steerpoint.
- **The weapons' point** (`target_point`, `IafRadar` state `spi`): the ground track's unit, else the designated point.
  The GPS bombs and the SPICE in VIS aim at it (`player_weapons.gd` `gps_aim`); the HUD's TD box sits on it, and the
  F-16 Real HUD's slant range window reads its range (`hud.gd`: a designated point is the Real HUD's target too). The
  original's radar hands over the designated point only, as before.
- **AGR:** with a visual A-G delivery selected (a CCIP bomb, the A-G gun) the FCR ranges along the pipper's line to
  the ground (to 20 NM, inferred): OSB 1 reads `AGR`, the slant range in NM mid-scope (layout inferred), and the Real
  HUD's slant range window shows it as `F` when no target is locked (`real_hud/f16.rs`; the letter inferred).
- **Targets on the weapons range** for these modes (modern-iaf/docs/data-formats.md): each range's Target 5, the
  MiG-29 hulk towed on a loop (GMT), and Target 6, a barge off the coast (SEA).

### 9.8 Ground clutter: look-down, the beam notch and slow targets
The Sufa's APG-68(V)9 and the Adir's APG-81 are pulse-Doppler radars. They tell a target from the ground by its
Doppler shift, so the ground's return limits what they see in look-down (`radar.rs` `notched`, `look_down`). The
1998 game's radar has no such rule: this one applies only to the real FCR (Modern IAF).

- **Look-down:** the line of sight, carried on past the target, meets the ground within the mode's detection range.
  The ground is taken level at the height under the target, sea level where there is none, on a flat earth
  (inferred). A target above the jet, or level with it, is in look-up and is found as before.
- **The ground's band:** in look-down the main lobe's ground return sits at the Doppler of the jet's own speed
  along the beam; a target whose own speed along the line of sight is close to zero sits in the same band and is
  filtered out with it[^odonnell][^w-pd]. A target nose-on or tail-on stands clear of it[^odonnell].
  Only the main lobe's clutter is modelled; the sidelobes' and the altitude line's clutter are left out (inferred
  simplification).
- **The gate:** the band's half-width is CNTL's MTR, 60 kt (LO, the default) or 100 kt (HI). A pulse-Doppler
  radar's rejection speed is selectable, and nothing slower than it is detected[^w-pd]; the APG-68's own values
  are not published (the two values inferred). In look-down every air mode (RWS / VSR, TWS, ACM, SAM's tracks, STT)
  loses a target under the gate (inferred: the APG-68's rules per mode are not published). A lock in STT breaks when the target turns into the band, and its semi-active
  missile loses its illumination.
- **What follows:**
  - A jet crossing at about 90° (the beam, the notch) in look-down drops off the scope; TWS keeps its file for 13 s
    without a return.
  - A slow target is found only where its speed along the line of sight passes the gate. A drone at 180 km/h
    (97 kt) in look-down is found at MTR LO within about 50° of its nose or tail. At MTR HI it is not found at all.
- **On the scope:** contacts appear or drop by these rules; no clutter is drawn. A ground-clutter picture on the
  FCR page is not started.

## 10. Validation
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

The real FCR: `crates/iaf-avionics/src/radar.rs` tests (power and weight on wheels, scan width / bars / elevation,
VSR, SAM, the TMS and the cursor, the ACM patterns, TWS's files, EXP's 4:1, the ground clutter (look-down and
look-up, the beam and nose-on, the STT lock in the notch, a slow drone at MTR LO and HI), and A-G: the PPI places, the EXP / DBS
scales and the notch, FZ, SP, CZ, GMT's movers, SEA's ships, the designation and FTT, the picture's slopes, shadow and
runways, AGR) and `modern-iaf/tests/test_sim_fcr.gd` / `test_sim_fcr_ag.gd` against the weapons range's drones and
ground targets; `modern-iaf/tests/test_enemy_drones.gd` flies a drone 60 m over the terrain: on the beam in
look-down it is not found, from behind it is found at MTR LO and lost at MTR HI.

[^odonnell]: R. M. O'Donnell, "Radar Systems Engineering, Lecture 14: Airborne Pulse Doppler Radar", IEEE New
    Hampshire Section, 2010 (the main-lobe clutter at the Doppler of the platform's speed along the beam; nose-on
    detection clutter free; "Short range sidelobe clutter often masks low radial velocity targets"):
    https://gmoein.github.io/files/MIT%20Graduate%20Radar%20Course/Radar%202009%20A_14%20Airborne%20Pulse%20Doppler%20Radar.pdf
[^w-pd]: Wikipedia, "Pulse-Doppler radar" ("Rejection speed is selectable on pulse-Doppler aircraft-detection
    systems so nothing below that speed will be detected"; the target signal is "rejected by the Doppler filter when
    radial velocity approaches zero"): https://en.wikipedia.org/wiki/Pulse-Doppler_radar
[^chuck]: Chuck's Guides, "DCS Guide - F-16CM Viper" (EXP, DBS1 8:1, DBS2 64:1), a simulator guide:
    https://chucksguides.com/aircraft/dcs/f-16cm/
[^bms-slew]: Falcon BMS forum, "How does ACM slew work?" (the slewable pattern about 60° wide and 20° high, the only
    stabilised ACM pattern): https://forum.falcon-bms.com/post/336643
[^dcs-acm]: DCS forum, "Questions about ACM modes" (the 30 × 20 about the HUD's field, the 10 × 60 scanning up):
    https://forum.dcs.world/topic/302060-questions-about-acm-modes
