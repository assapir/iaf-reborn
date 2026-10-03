# Weapons — the player's gun, IR missiles, stores (v1.1)

How Jane's IAF v1.1 arms the player's jet and how iaf-reborn ports it (`game/weapons/`). All addresses v1.1
(`assets/ghidra_v11/iafjets.c`; docs/v1.1.md maps them to v1.0). World frame X east, Y north, Z up, metres, sim
seconds. `ctl` = the player controller (`this` of the GEV handler `FUN_0044a240`), `W` = its weapon system
`ctl+0xf0`, `C` = the station container `ctl+0xfc` (= `W+0xc`), `S` = the flight-model state.

Built: chaff / flares (§10), the stores (loadout incl. the Arming screen's, pylons, selection, release, weight / drag, fuel tanks and their jettison), the master /
HUD modes, the gun (trigger, rounds, hits, muzzle flash, sounds, LCOS / strafe pippers), the IR seeker and the IR
missiles (types 570 / 580), the bombs (500, 510 incl. the cluster bursts, 650 as a free bomb) and rockets (560) with
the ripple quantity / interval, the mode-5 HUD (CCIP and the delayed release) and the bombs jettison (§9), the weapon
HUD text and symbols, the stores MFD page, the FLIR pod / TV-weapon camera and the FLIR / TV / HARM MFD pages
(docs/mfd.md), the radar missiles (600 AMRAAM-like, 610 Sparrow-like) with the DLZ, the MRM HUD sight and the
semi-active rule, the HARM / Shrike (§11), the TV weapons (635 Maverick, 640 TV missile) with the guided motion, the
camera riding the weapon and the TV page's TRA / TER and time (§12). The radar and its lock (the seeker slaved to it):
docs/radar.md. Not built yet: the laser guidance (FLIR designation), the decoys' effect on missiles, ECM, the HUD
range scale (`FUN_005397a0`, §12.4), the AI's weapons, AAA.

## 1. Data

### 1.1 bdb Weapons table (`CDMEWeaponsItem`, parser `FUN_00593ee0`)
| field | meaning | example (AIM-9L) |
|---|---|---|
| `0x708` | name (matched by the code: "20 MM", "LB", "FLIR") | AIM-9L |
| `0x780` | sub type: 500 bomb, 510 cluster, 540 chaff, 550 flare, 560 rocket, 565 gun, 570 heat, 580 limited heat, 590 HARM, 600 radar, 610 semi-active, 620 / 630 SAM, 635 Maverick, 640 TV, 650 laser bomb, 660 "Shell" (tanks, pods) | 570 |
| `0x762` | generation (float, truncated) | 3 |
| `0x744` / `0x74e` | blast power / radius (m) (docs/damage.md §4.3) | 400 / 15 |
| `0x758` | weight, **pounds** | 192 |
| `0x73a` | drag index (the stores drag) | 23 |
| `0x730` | model (bdb Present id → `objects.json`) | 44 (aim9) |

Weapon object (`FUN_004d5c70`): +0x70 power, +0x74 weight, +0x78 drag, +0x7c generation, +0x80 radius, +0x84 =
radius + 20 (the blast query pad). Category `FUN_004d72a0`: 0 gun (565); 1 AA (540, 550, 570, 580, 600, 610); 2 AG
(500, 510, 560, 590, 635, 640, 650); 3 other (660).

### 1.2 weapons.ibx (motion parameters)
`[Weapons] weaponsPath` (default WeaponsMotion) + `Weapons.ibx` (`FUN_0055fa00` → `FUN_0055f420`): `[WEAPONnnn]`
sections keyed by `type` = generation·1000 + sub type; `[DEBUGDATA]` `_debugParam000..019`. Lookup `FUN_0055f170`:
`_debugParam002` = 1 → every weapon uses type 800; else type + gen·1000, else the sub type alone.

| key | weapons | chase | absAcc | burn (tA+tCV+tD) | tConstOrientation | spiral / β |
|---|---|---|---|---|---|---|
| 003570 | AIM-9L, AIM-9M, PYTH-3 | 2 | 100 | 16 | 2 | 1000 / 0.08 |
| 004570 | PYTH-4, AA-11 | 2 | 140 | 22 | 1 | 1000 / 0.08 |
| 001580 | AIM-9D, SHFR 2, AA-2, AA-6 | 2 | 150 | 10 | 2 | 800 / 0.08 |
| 000565 | gun rounds | — | −10 | — | 0.1 (hit check period) | 50 (hit distance) |

Gun record: `_limitVel` 1200, `_limitDist` 4500 (only the AG lead reads it), `_velocityJump` 1200, `_maxNumInAir` 20
(the round pool). `_fireReleaseInterval` / `_reactionTime` are only read by the AI weapon timer.

## 2. Stores

### 2.1 Loadout (`FUN_0058f110`, stations `FUN_004b7ea3` → `FUN_0053b580` → `FUN_0053c1f0`)
12 slots {weapon id, count}: 0..8 the pylons StationA..I, 9 the gun (StationGun), 10 chaff, 11 flares. Pylons from the
mission entity's `CArmament` when any of its 0..8 ids is set, else from the object type's; 9..11 always from the type.
The Arming screen (docs/front-end.md §15) replaces pylons 0..8 of both aircraft of a flight with its table
(`FUN_004f00f0` → `FUN_004f0140` → `FUN_004541d0`, then `FUN_00459410` redoes the weight / drag): ours puts
`Settings.arm_loadouts[flight]` on the player's pylons before the stores are built (`player_weapons.gd _arm`),
so the models, counts and §2.5 weight / drag follow; the gun, chaff and flares are not Arming stations. Count 0 or an unknown id = no station.
Displayed count (`FUN_0053cfd0`): the gun's count ×4 when its name contains "20 MM" (`W+0xc4`), else ×2 (DEFA); F-16
235 → 940, 5 shots/s → empty after 47 s. Gun counts per jet: F-16 / F-15 / Lavi 235, F-4 160, Mirage DEFA 125, Kfir
DEFA 150, MiG-29 140, MiG-21 550, MiG-23 DEFA 175.

### 2.2 On the model
Types 500, 510, 570, 580, 590, 600, 610, 635, 640, 650, 660 get their store model on pylons 0..8 (rockets 560 get a rocket
box instead, §9.7); gun, chaff and flares are never drawn. Slots (`FUN_0053c990`, once, in the original's E frame
x = −glTF x, y = glTF z (aft), z = up) from the attach point P and the store model's `pilon` helper (px, py, pz)
(default (0, 0, PilonDefaultZ 5)):
- TER (non-bombs, bombs ≤ 3): A = P+(pz,0,0), B = P+(−pz,0,0), C = P+(px,py,−pz); stations with index > 5 swap A / B
  (station 5 is not mirrored: the original's `> 5.0`); a count of 1 at the start → slot 0 = C.
- MER (500 / 510, count ≥ 4): (±pz, ±L, 0), (0, ±L, −pz), L = `[Misc] BombStationLength` 2.0.
Drawn (`FUN_0053e430`, any aircraft with a controller): `count` stores at slot[0..count−1] — a released store
disappears (the highest slot) — only with Preferences > Graphics EXTERNAL STORES on and within 9000 m of the camera.

**Pylons.** The original has no pylon object: `FUN_0053e430` draws only the store models, `FUN_0053c1f0` attaches only
the store (weapon record +0x1c) and the 560 rocket box, and neither the bdb Weapons nor the Objects records have a
pylon / rail field ("Pilon" in the code is the pilot eye or the store's lug helper). The pylons are **part of each
jet's model**: thin vertical double-sided quads (F-16: material `f16_2side1`, alpha mask, UV v 1.07–1.11 with repeat)
under stations B..D / F..H, from the wing to ≈ 0.1 model units below the attach point (the wingtip rails A / I have
none). So they are always drawn, loaded or not, stay after a release, and EXTERNAL STORES does not hide them. The
store's lug (its `pilon` helper) sits at the attach point, inside the pylon's lower edge. Seen from ahead / behind /
below the quads are edge-on and nearly invisible, which makes the stores look detached — as in the original. Ported
as is (the converted models carry the quads; test `test_pylons.gd` checks the geometry under every wing station of
the six models of the seven flyable jets).

### 2.3 Selection (`FUN_0053b8b0`)
']' (event 0x3e) next AA, '[' (0x3c) next AG; **Shift+[ / Shift+] send the same events (forward, not back)**. Only when
not releasing / firing. The cycle walks stations 0..9 by distinct name, restarting after 9 or when the kind changes;
it prefers a store with rounds left; the player may select an empty one when no station of that weapon has any; tanks
/ pods never; **the gun belongs to both cycles**; chaff / flares to none. ']' does not cycle when an AA missile is
already selected in NAV (and '[' likewise for a non-AA store), it only enters the mode. MFD stores page station
buttons (0x4c): select that station (+ button click).

Master mode `ctl+0x78` (`FUN_0044ec80`) → HUD mode `ctl+0x5c` and MFD page (`FUN_00449810`):
| type | master | HUD mode | MFD page |
|---|---|---|---|
| — (M / N to NAV) | 0 | 0 NAV | 0 NAV |
| 500, 510, 560 | 1 | 5 | stores |
| 565 via '[' | 2 | 4 AG gun (strafe) | stores |
| 565 via ']' | 3 | 3 AA gun (LCOS) | radar |
| 570, 580 | 4 | 1 SRM | unchanged |
| 600, 610 | 4 | 2 MRM | radar |
| 590 | 4 | 8 HARM | HARM |
| 650 | 5 | 5 (6 with a FLIR pod: the FLIR starts) | stores / FLIR |
| 635, 640 | 6 | 7 | TV (the TV camera starts) |
M (0x63): NAV → AA → AG → NAV (`ctl+0x7c`), SFX_BUTTON; N (0x62, p 0): NAV. No button click on '[' / ']' / N. There is
no master arm: firing the selected store needs HUD mode 1..8.

### 2.4 Release (Space 0x40 / up 0x41)
Space: HUD mode 1..8; with the gear handle down only with Safety off **and** the gun selected; refused with weapon
systems damage (flag 20). `FUN_00454270`: refused with `W+0xa0` (flags 20 / 21), while releasing, or with no rounds of
the selected store; gun → the trigger (§3); missiles 570–640 → one release `FUN_004545e0`. The station that fires
(`FUN_0053b680`): after a shot from the current station, the station of the same weapon with rounds left farthest
from it (AIM-9 0 → 8 → 0 …). Release point: the store's slot[count−1] (else the pylon) through the attitude, launch
velocity = the jet's. Then count −1 (`FUN_0053c8b0`; not with Unlimited ammo), drag / weight updates (§2.5). No
"out of ammo" message or sound anywhere.

### 2.5 Weight and drag (`FUN_00454010` from the FM init `FUN_005a8980`)
Over pylons 0..8, **one store per station whatever the count**: the weight (pounds) of non-tank stores is summed into
`S+0x424`, **the kg field, as is**; drag: stations 0..3 → left `S+0x42c`, 5..8 → right `S+0x428`, station 4 half to
each, ×1e-4. The flight model: m = EmptyWeight + `S+0x424` + fuel, CD += left + right, β_cmd = (rudder + 10·(right −
left))·MaxBeta (docs/flight-model.md). After each release (`FUN_004583a0`, `FUN_00458510`; skipped with Unlimited
ammo): that side's drag −(drag, half at station 4), and `S+0x424` = (`S+0x424`·2.2046 − weight lb)·0.45359, each only
when it stays ≥ 0. Original bugs (kept by default): (a) one store per station (3 MK-83 weigh as one; each release
subtracts one, clamped at 0); (b) pounds in the kg field at the start, while the updates convert as if kg; (c) the
tanks' weight never counts as stores weight (it becomes fuel, §2.6). The Physics option **"Stores weight fix"** counts
every store, in kg (the updates then stay consistent), and the tank fuel in kg (§2.6).

### 2.6 Fuel tanks (stores whose name contains "LB", type 660)
- **Start**: `FUN_00454010` puts the tanks' bdb weight (one per station, e.g. "2700LB" = 2700) into `out[3]` and sets
  `W+0xc0`. `FUN_005a8980` sets the fuel ramp's maximum `S+0x448` = FuelWeight (kg) + `out[3]` (the pounds number) and
  the controller's fuel display to (FuelWeight + `out[3]`)·2.2046. `FUN_004a9100` calls it before the motion start, and
  the start (`FUN_005a5820` @5a6145: `lea ecx,[S+0x430]`, pushes max, 0, 0) fills the fuel to that maximum. So the
  tanks **do** give fuel in the original, but pounds counted as kg: an F-16 with a 2700LB centre tank starts with
  3175 + 2700 = 5875 kg (12 950 lb) instead of 3175 + 1225 kg.
- **One pool**: the fuel is one ramp; the part above FuelWeight is the tanks' fuel, so the external fuel is burnt
  first. The MFD "Fuel : %5dLB", the Betty fuel warnings and the mass all use the total. (The stores page's
  "int%d" is the bomb release interval, not internal fuel.)
- **Weight**: the tank's fuel weighs as fuel; the empty tank's own weight is not in the data (never counted). Its drag
  counts until it is released.
- **Jettison** (Shift+C, event 0x48): nothing with the gear handle down; the first press (`FUN_00458760`, once,
  `W+0xb8`, only with the release permission `FUN_0045ee10`, §9.2) releases one store from every pylon whose name
  contains "LB" (count −1 even with Unlimited ammo, drag update, no weight update): the tank falls as a ballistic
  object (class 0x16, §9.5) aimed at its `_fireEndVec` (0, 500, 0) from the jet, on the terrain, and bursts there
  (power 0: the explosion only, SFX_WEAPON_EXPLODED / OST_SHELL); then, when the fuel is at or above FuelWeight
  (`FuelWeight·2.2046 ≤ fuel lb`), motion 0x18 (`FUN_005a2270`) sets the fuel and its maximum to FuelWeight: the
  tanks' remaining fuel is gone. Later presses drop the bombs (`FUN_00458d10`, §9.6). Tanks are never selectable, so
  the jettison is their only release.
- **Stores weight fix**: the tank fuel is added in kg (count × bdb weight × 0.45359), same pool and jettison rule.

## 3. The gun

### 3.1 Trigger (Tab 0x42 / up 0x43, or Space with the gun)
Tab with the gear handle down needs Safety off (`ctl+0x970`, the Shift+S cheat, default on). `FUN_004579f0`: refused
with flags 20 / 21 (`W+0xa0`), gun damage (flag 13, `W+0x9c`) or while firing; `W+0xb0` = 1 (firing, also the muzzle
flash); **the first round at once** (`FUN_00456d40`), then a timer every **0.2 s of sim time** (`DAT_0082f4e8`; the
scheduler catches up in long frames, catch-up shots share the timestamp), and the gun sound loop (§3.6). Quirk: if the
first round fails (pool round still flying), firing stays on without a timer until the release. Stop (`FUN_00457b40`):
release, weapon change, gun damage, out of rounds (silently).
One shot (`FUN_00456d40`): no rounds → stop; the next pooled round (ring of `_maxNumInAir` 20) still flying → skipped,
no round used; else aim, launch, count −1 (never with Unlimited ammo).

### 3.2 Aim (`FUN_00456ff0`, `FUN_00450450`)
Shot line d = the nose **rotated 1° up** about the right wing (v1.1, player only). Aim point A: HUD mode 4 (AG gun)
A = P + (V + 1200·d)·t − (0, 0, 4.903·t²), t = `_limitDist / _limitVel` = 3.75 s; any other mode A = P + **2781**·d
(v1.0 1854). P = the jet's origin (not the muzzle). Firing is mode-independent (it fires in NAV too).

### 3.3 Candidates (`FUN_004577c0`)
At most one list per 0.5 s (gate `FUN_004d4100`; with 0.2 s shots about every third round gets one, the others none):
the locked radar target first (when within 2·|A − P|), then every unit within 10·|A − P| other than the shooter (**friendlies
included**), at most 10. Ours: nearest first (the original's spatial-query order is UNCERTAIN).

### 3.4 Flight (`FUN_005605c0`, `FUN_0047a491`, analytic)
Speed s = |V| + `_velocityJump` along u = (A − muzzle)/|A − muzzle| (A pulled to 30 km), decelerating at 10 m/s²:
p(t) = muzzle + u·(s·dt − 5·dt²) until t_end = (s − √(s² − 20·dist))/10, then A. Straight line, no gravity, no
dispersion. Hit radius = `_spiralAccel` 50 × **0.5** = **25 m**, **50 m with Easy aiming** (v1.1; the only Easy-aiming
effect on the gun). Every 0.1 s (`FUN_00560710`): the round within 25 m of a candidate's origin (no target size) →
detonation at the round; at or below the terrain → detonation; at t_end → detonation at A in the air. The round moves
~145 m per check: the sphere can be stepped over (original).

### 3.5 Detonation (`FUN_004d6130`, `FUN_004d7c80`)
Sphere hit: the blast (power 100, radius 50 for "20 MM" / DEFA) reaches the round's candidate list only; ground / end:
every unit around. Damage per docs/damage.md. Impact effect only on a hit (at the hit unit) or on the ground: a small
fireball (0x10000000, 1.5, 1.2 s) and SFX_WEAPON_EXPLODED / OST_GUNBULLET (WpnMiss); over water a splash + SFX_SPLASH
(ours: a white puff, look UNCERTAIN). A round ending in the air: no effect, no sound.

### 3.6 Look and sound
Each pooled round is drawn as the bdb model 116 (`weapons\gun\gunsh`) along its line. Muzzle flash (`FUN_00411d90`,
every frame while firing): two crossed quads at StationGun along the gun line, length (0.85 + 0.01·(rand % 31))·s,
half-width 0.3·s, gunFire.tga, no z-write (ours: s = 1 m, additive; scale and blend UNCERTAIN; hidden in the cockpit
view with the jet model). Sound: one loop per trigger press, by gun name: "20 MM" → SFX_AIRCRAFT_FIRED_WEAPON /
OST_GUNBULLET (Msl_gblt), else SFX_ENTITY_FIRED_WEAPON / OST_GUNBULLET (MSL_GBLT_BRAIN — the Mirage / Kfir player
hears it); no sound per round.

### 3.7 Gun HUD
Gun cross in every mode (docs/cockpit.md). Pipper: the 32×32 sprite of mfds.bmp (132,792)–(164,824), colour key
0xffff00 (`FUN_00530040`). **Mode 3 LCOS** (`FUN_0045f410`, unchanged from v1.0, no +1°), feet, every 0.05 s but
integrated with dt = 0.15 (quirk kept): R = locked range else 1476.378 ft (450 m), ≤ 3148.8 ft; the filtered pitch /
heading rates w28 / w2c (int16 fixed point), tf = R / (3300 − (V + 1650)·R·0.00024667423), gd = π·tf²·16.087/R,
D = 0.2 + 1.35·tf, x* = gd·cos θ·sin φ − tf·Q, y* = tf·P + (g − 1)·gd − ((3300·tf − R)·V·α/R)/(V + 3300) + 5.0617/R,
x += dt·(x* − x)/D, y likewise; drawn at the gun cross + (x, y)·57.29578·12 px. (Ours: the rate filters start from
the attitude at mode entry; the original's first values are untraced, from 0 the first heading step would throw the
pipper off for about a second.) **Mode 4** (`FUN_0045ef10`, new in
v1.1): the projection of the mode-4 aim point A.

## 4. Master mode keys (summary)
'[' / ']' / Shift+[ / Shift+] select, M cycles NAV / AA / AG, N → NAV, Space releases, Tab fires the gun, Shift+C
jettisons. Keys and commands: docs/controls.md (records 45, 54, 64–69, 72).

## 5. IR missiles (570 heat, 580 limited heat)

### 5.1 Seeker (SRM HUD mode 1; `FUN_00461210` object, `FUN_00461290` update)
Per generation of the selected store (`FUN_00462460`): gen 1 15° / 6 NM, gen 2 21° / 8 NM, gen 3 35° / 10 NM, gen 4
70° / 15 NM (NM = 1854 m); the cone is the gimbal limit of the radar-slaved and the helmet-slaved seeker (§5.4).
Search (`FUN_00461680`) at most every 0.5 s: the unit whose screen point (viewport 0, the 3D camera, `FUN_0045a790` →
TgenAPI slot 0x38) is nearest the **HUD centre** (cx, cy) = R+0x2768 / +0x276c (`FUN_004dc790` → `FUN_00520be0`; not the
boresight symbol) within **6000 px²** (≈ 77 px) that passes can-track — **no side test** (friendlies too). Can-track
(`FUN_00461d10`): 580 only within ±60° of the own heading (a bearing test, not the "tail" of the comment); range
≤ R; beyond **R/2 only a target with its afterburner on** (AI jets have no afterburner state yet, so for now R/2).
Visible (`FUN_00461f10`): **with an A-A radar lock** (`FUN_004625f0`) the target within the generation cone of the
nose; **else in the free-look (0x12) or padlock (0x16) view** the helmet test of §5.4; **else** within 6° of the nose.
Every 0.05 s: tone seek /
lock (SFX_IR_SEEK Wpn_IRCHIRP / SFX_IR_LOCK WPN_IRCHIRPON; none without rounds on the **selected station**, `FUN_0053bcd0`;
entering IR on an empty station chirps the seek tone once, `FUN_00461b00`, stopped by the next update); lock = a visible trackable target (no
lock timer; lost at once). The seeker diamond (±7 px, `FUN_00536ff0`, S+0xe6c) eases 0.3 / 0.7 toward the target's
screen point (snaps within 5 px), back to the HUD centre without one, and is held inside the symbology field along the
line from the HUD centre (`FUN_0052db30`). Missile circle (`FUN_00537120`) r = 5·12 px (min 10) on the **HUD centre**.
Ours: screen offsets are angles at 12 px/deg from the camera ray through the HUD centre (the camera's 686.2 px focal
length = 11.98 px/deg; tan vs angle differs < 1 % inside the 6° field).

### 5.2 Launch (`FUN_004545e0` → `FUN_00454b70`, q `FUN_00457f70`)
Needs HUD mode 1, 2 or 8. Without Easy aiming: the seeker target inside the 6000 px² circle, q = (lock ? 1 : 0.1)
× **0.8** (v1.1); with Easy aiming: any seeker target, q = 1. q ≥ 0.1. No target → the missile flies at the point
`_fireEndVec` (0, 10000, 0) in body axes (10 km ahead). Launch sound SFX_AIRCRAFT_FIRED_WEAPON / OST_HEATMISSILE (or
OST_LIMITEDHEATMISSILE) = WPN_IRMIS_RLS; flight loop SFX_OBJECT_SPECIFIC (UNCERTAIN: code 0x8337e4). No rate limit
for the player's missiles.

### 5.3 Chase (`FUN_00563b70`, `FUN_00561ef0`, `FUN_005627e0`)
q clamped [0.1, 1]; chase 2 (proportional) becomes chase 1 (dog) when q < 0.7; gain A = `_spiralAccel`·q. Launch
velocity = the jet's (≥ 5 m/s, else 100.1·nose). Between updates p = p0 + v0·dt + ½a·dt² (no gravity, no cap); every
0.1 s re-based, and a += G·(a_abs − β·|v|·(G·û)) with G = û until `_timeConstOrientation` (straight), then
G = norm(dist·D − A·v⊥D), D = the line of sight (dog) or the collision course (proportional: D = norm(u·√(S² − P²) +
V_t⊥)). Terminal speed ≈ a_abs / β. Ends (`age ≥ tCO` with a target): within 1.5 m, at / below the ground (burst at
the target height when within √60 m horizontally and 15 m above it, else ≥ ground − 1), overshoot (cos < −0.01; the
burst moves to the closest point of the last 0.1 s segment), or after burn + 6 s (22 s AIM-9L). No random Pk: the
blast (AIM-9L power 400, radius 15) at the burst point reaches every unit around. The seeker is not consulted after
launch.

### 5.4 Helmet sight: DASH (off-boresight IR lock)
The exe has no "helmet" string; the helmet is the cockpit key `[HUD] Dash` (Elbit's DASH, Display And Sight Helmet;
docs/cockpit.md "HUD dash repeater") plus a view-dependent branch of the seeker. Traced (v1.1, objdump):
* **Seeker, `FUN_00461f10` @461fb0**: when the radar has no A-A lock and the current view (`DAT_00699304` camera
  slot +0x458 → +8) is **free look 0x12 or padlock 0x16**: A = the 3D camera's forward axis (`FUN_00582880`: the
  head yaw / pitch with the 5.5° look-down, docs/views.md §4.3), B = the jet's nose; **B·A ≥ cos(generation cone)**
  (`0x82f6e8`) and the target direction from the eye · A ≥ **cos 6°** (`0x82f6c8`), else not visible. No aircraft or
  weapon test: every jet, every IR missile; only the generation cone differs (gen 1 15°: AIM-9D, Shafrir 2, AA-2,
  AA-6; gen 2 21°: AA-8; gen 3 35°: AIM-9L / M, Python 3; gen 4 70°: Python 4, AA-11).
* **Acquisition** is the unchanged search (§5.1): a unit within ≈ 77 px of the HUD centre on the screen. In those
  views the HUD centre moves with the panel (cx = 320 − pan), so in a `Dash 0` cockpit (Mirage, Kfir, F-4E) a turned
  head carries the circle off the screen with the HUD and the seeker can only take a unit near the nose, which the
  camera-axis test then rejects; in a `Dash 1` cockpit (F-15, F-16, F-4 2000, Lavi, MiG-23, MiG-29) the HUD becomes the
  helmet display at the fixed screen point (320, 220) once the panel is panned ≥ 250 px aside or ≥ 200 px down
  (`FUN_00530b70`), so the circle sits near the middle of the view and the seeker takes what the pilot looks at.
* **Padlock (F3 / Shift+F3)** puts the target on the head line: the camera looks 5.5° below it (or max(·, 0.1·(|yaw|
  − 90°))), so the target is 4–5.5° from A (inside 6°) and ≈ 30–50 px above (320, 220) on the full-height viewport
  of a turned head (docs/cockpit.md "3D view"); with the head ≤ cone off the nose the seeker locks. The padlock does
  not hand its target to the seeker; the screen search does.
* **Symbols**: the helmet display's missile circle on (320, 220), the seeker diamond eased onto the target's screen
  point (held in the field), the DASH aircraft symbol and attitude bar (docs/cockpit.md). **Sounds**: the same seek /
  lock tones. **Launch** (§5.2): unchanged — the seeker target inside the 6000 px² circle around the HUD centre, q =
  (lock ? 1 : 0.1)·0.8; the missile chases that target (no seeker after launch).
* **Radar-slaved** (any view): the A-A lock's unit at once, visible within the generation cone of the **nose** (the
  first branch of `FUN_00461f10`).

## 6. HUD and MFD
Weapon text (`FUN_0052ef20` pass 3, left column at HUD centre − TxtOffX, rows 7 px from centre + TxtOffY; row 2):
"%1d %s %s" = total of the selected store (same type and name), name, RDY / MAL (MAL with flags 20 / 21, or 13 with
the gun), "NAV" in HUD mode 0; drawn on the glass, outside the symbology field's clip. The whole text block (six rows) is
in docs/cockpit.md "HUD symbology". Stores page
(`FUN_0052c740`): per pylon count / name at the docs/mfd.md positions, MRM / SRM totals, gun rounds "%03d" at (68,85),
fuel, the selected station boxed (gun 36×10 at (48,82)), the ripple quantity "%dQnt" at (1,94) and interval "int%d"
right-aligned at (131,94) (state +0x374 / +0x378 = W+0xd4 / W+0xd8; OSBs 0xe / 0xf quantity +1 / −1, 0x13 / 0x14
interval +10 / −10, §9.1). The HUD weapon line has no quantity / interval (the two strings are used only here).

## 7. Weapon data: Real (Extras)
Preferences > Extras > Weapon data = Real overlays public numbers (docs/real-weapons.md): missile weights, top speed
(β) and range (burn), rear-aspect seekers, seeker cones and g limits, radar detection ranges, gun rounds per jet, rate
of fire and muzzle velocity. Original by default. The Arming screen's
CURRENT LOAD and weights use the same numbers as the flight (so Real shows the real weights).

## 8. Corrections to earlier docs
- damage.md §4.4 named `FUN_004604c0` as the LCOS solver: it is a seeker for weapon 0x27b. The gun pippers are
  `FUN_0045f410` (AA, mode 3) and `FUN_0045ef10` (AG, mode 4).
- `FUN_005611b0` / `FUN_00468470` (the ±`_debugParam016` clamp) are the bomb / shell ballistics (class 0x16), not gun
  code: nothing steers a gun round.
- The `_spiralAccel` ×0.5 of `FUN_005604a0` / `FUN_005605c0` is the fixed-weapon (gun round, rocket) hit sphere, not
  the missiles.
- The bdb Weapons parser is `FUN_00593ee0` (not `FUN_004c37c2`).
- controls.md §4 already has the right meanings of (110,27) Shift+S = Safety toggle, (110,4) Shift+R = reload stores,
  (110,26) Ctrl+W = re-read Weapons.ibx (the keys.trx labels are wrong).

## 9. Bombs and rockets (500, 510, 560, 650)
Built (`game/weapons/bombs.gd`, `player_weapons.gd`, HUD `hud.gd _draw_ag`; test_bombs.gd, test_bomb_missions.gd).
Types 500 / 510 / 560 / 650 share the release path ("bomb types", `FUN_00457bc0`); rockets too, except the jettison.
Master mode 1 (5 for 650), HUD mode 5 (6 for 650 with a FLIR pod: the FLIR page and camera start, the same mode-5 symbols), the stores MFD page (§2.3).

### 9.1 Ripple quantity / interval (`FUN_004585f0`, events 0x4a / 0x4b → `FUN_004562a0` → `FUN_004562f0`)
Defaults quantity `W+0xd4` 2, interval `W+0xd8` 10, period `W+0xdc` 0.3 s (0x600eb0). Stores page OSB 0xe / 0xf send
0x4a with 1 / 0 (quantity +1 / −1), 0x13 / 0x14 send 0x4b (interval +10 / −10) (`FUN_005219e0`); no key does. Clamps:
quantity 1..14, interval 10..200, period = max(0.1, interval·0.001) (0x600f48, 0x600f0c) — once changed the period is
0.1 s up to 100 (quirk). "int" is both the spacing on the ground (m) and the period (ms). No check while releasing.

### 9.2 Release (Space 0x40 / up 0x41)
- **Space** (`FUN_00454270(target, ai)`; player (0, 0), AI `FUN_00452680(T)` → (T, 1)): refused with `W+0xa0`,
  outside HUD mode 1..8 (player), while releasing (`W+0xac`) or without rounds; then `W+0xac` = 1. Bomb types, player:
  HUD mode 5 or 6 only (else `W+0xac` stays set until Space up); without a running ripple timer (`W+0x288`):
  remaining `W+0xd0` = quantity, the mode-5 object updates once and freezes (`FUN_0045d130`: +0x3c), timer
  `FUN_004cf270(cb 0x601020 / FUN_0045a680, start now, period W+0xdc)` → the first store on the next scheduler tick,
  then one per period. AI: `W+0xe4` / `W+0xe8`, period `W+0xf0`.
- **Space up** (`FUN_00456100`): timer killed, `W+0xd0` = `W+0xe4` = 0, in HUD mode 5 / 6 the freeze cleared
  (`FUN_0045d150(1)`): the ripple runs only while Space is held.
- **One release** (`FUN_004545e0`, the timer callback): no rounds or `W+0xa0` → timer killed, the symbols blink
  (`FUN_0045d150(0)`); the station (`FUN_0053b680`, the farthest same weapon after a shot: §2.4) — its pool object
  still flying (+0x48) → wait for the next tick (a station's pool holds `count` objects when count ≤ 6, else
  `_maxNumInAir`: bombs never wait, rockets with 20 in the air do); `FUN_00454b70` sets the aim (§9.3); then the
  release permission **`FUN_0045ee10`**: the entity's selector 0 (the load factor) ≥ 0 and |roll| ≤ 90° (0x82f63c
  = π/2), else no release this tick; the **delayed release**: when the mode-5 pipper is off the HUD (+0x2c) and this is
  the first store (`W+0xd0 == W+0xd4`), only once the time-to-go +0x30 ≤ **0.9 s** (`_DAT_0082f528`, set by
  `FUN_00453880`); then `--W+0xd0`, at 0 the timer ends, the symbols blink and `W+0xac` clears; force feedback
  "BombRelease" (not ported); the release point / velocity / count / drag / weight as §2.4. Sounds:
  SFX_AIRCRAFT_FIRED_WEAPON / OST_BOMB (WPN_BGBMB_RLS), OST_CLUSTERBOMB (WPN_SMLBMB_RLS), OST_ROCKET, OST_LASERBOMB
  (WPN_RDRMIS_RLS); a falling store loops SFX_OBJECT_SPECIFIC / its OST (WPN_BGMB_FLY, WPN_SMLBNB_FLY, WPN_RDRMIS_FLY).
- No master arm, no minimum release altitude, no arming / fuse time: a store released at any height bursts at the
  ground (or at its aim). The gear rule is Space's (§2.4: gear handle down → only the gun with Safety off).

### 9.3 The aim and the ripple line (`FUN_00454b70` cases 500 / 510 / 560 and 650 without a designation)
Player: P = the mode-5 object's target +0x18 when its pipper is off the HUD (+0x2c = 1), else its impact +0xc.
`FUN_00457c20(P, remaining, quantity, interval)`: at the first store (remaining == quantity) the line is frozen in
`W+0xf4..`: aim[k] = P + (k − ⌊qty/2⌋)·interval·(sin h, cos h, 0), h the jet's heading, each on the terrain; store n
aims at aim[qty − remaining]. AI: P = T + V·t + ½A·t² (t = |T − own| / own speed) with a target, else `FUN_0045ed10`
(`FUN_0045e400`, the impact without the drag term). 650: `ctl+0x960` (the FLIR designation, `FUN_00450430`) set →
the guided path toward the designated point; else the same as a bomb. **The radar's GMT / MAP designation
(radar.gd `designate`) is not an input**: neither the mode-5 update nor the aim reads it (no true CCRP).

### 9.4 The mode-5 HUD object (`FUN_0045d0a0`, update vtable +0x10 `FUN_0045d470` → `FUN_0045d1d0`)
Fields: +0xc impact I, +0x18 target T, +0x24 / +0x28 the pipper's screen point, +0x2c off the HUD, +0x30 time-to-go
(double), +0x38 the distance, +0x3c frozen, +0x40 blinking, +0x48 a time cap (1e7 for every type: the rockets'
`_limitDist / _limitVel` of `FUN_0045d4d0` is overwritten, dead store), +0x50 the extra speed (rockets: `_limitVel`
1000). To the cockpit state by `FUN_00445db0`: +0x620 off, +0x624 point, +0x638 time-to-go (above 1000 → 1000),
+0x62c frozen, +0x630 blinking.
- **Impact** (`FUN_0045e7f0`, v1.1): P = the jet's origin, V = its velocity − the selected store's bdb drag (0x73a,
  MK-82 23) as m/s along the nose (+ 1000 m/s along the nose for rockets); h = P.z − terrain(P); t = (vz + √(vz² +
  19.612·h)) / 9.806 (`FUN_0045e330`); I = P + V·t − (0, 0, 4.903·t²) (`FUN_0045e3b0`); when the terrain at I is
  below I: once more with h = P.z − terrain(I), and I.z = min(I.z, terrain(I)); then a terrain ray P → I
  (`FUN_0045ed40`; ours: not done). The drag term puts the pipper short of the drag-free fall; the bomb's solver
  (§9.5) then pulls it onto that point. Level release from 1000 m at 200 m/s: drag-free 2856 m ahead, the MK-82
  prediction 2528 m.
- **Not frozen**: I → its screen point (`FUN_0045a790`, the 3-D view's projection: docs/cockpit.md "3D view");
  +0x2c = not `FUN_004dc6d0` (PtInRect on the HUD clip R+0x2770, **only in the cockpit views 1 / 5 / 0x12 / 0x16**;
  other views count as inside). Off the HUD: T = the terrain under the pipper point the HUD drew last frame, i.e.
  the projection clipped to the HUD edge along the line from the flight path marker (`FUN_005302d0` with p4 = 1 →
  the cached point; `FUN_00401fc0`, the renderer's screen-point ground query), +0x38 = horizontal |I − T|, time-to-go
  = that / speed (selector 6; ours: the ground speed).
- **Frozen** (Space): off the HUD I and the time-to-go are recomputed against the frozen T and the pipper is T's
  projection; on the HUD +0x30 = −1, +0x38 = 1 and the pipper stays on the frozen I.
- **Symbols** (`FUN_005302d0`, GDI on the HUD, 640×480 px): A = the flight path marker held inside the HUD rectangle
  (R+0x2760 + R+0x2780); P = the pipper point clipped to the HUD edge along A → P (`FUN_0052db30`).
  - on the HUD (CCIP): the fall line from the circle's edge (P − 9·û, û = (P − A)/|P − A|) to A, a circle r 8 at P, a
    one-pixel dot at P;
  - off the HUD, not frozen (delayed): the same plus a 20 px cue bar across the line at A + n·û, n = |P − A|·clamp((10
    − ttg)·0.1, 0, 1): it runs from A to P as the time-to-go goes 10 → 0 s;
  - off the HUD, frozen: the circle at P, a steering line from P − 9·ĉ to P − 400·ĉ and a 20 px release cue across it
    at P − L·ĉ, L = (P − A)·ĉ + 100·clamp(0.1·ttg, 0, 1), clipped to the HUD; ĉ = (R+0x272c, R+0x2730), the roll vector
    the pitch ladder uses (docs/cockpit.md), i.e. the rolled screen-down direction: the line goes up from the target
    and the cue comes down onto the marker's level as the time-to-go runs out; then the dot;
  - blinking (+0x630, for 1.0 s after the last store: `_DAT_0082f620`, cleared by `FUN_0045d6e0`): drawn only every
    other 300 ms.
  - HUD text (`FUN_0052ef20` case 5): row 3 "R %2.1f" with a lock, row 4 "W%02d %02.1f" (waypoint), and only off the
    HUD row 5 "%2d SEC" of the time-to-go, "XX SEC" from 90 s (0x65d4ac, 0x65d4bc).
- So the original's A-G modes are CCIP and a "delayed CCIP" (the target under the HUD-edge pipper, release on the
  0.9 s cue), with the 12 px/deg 3-D projection of the cockpit view. Ours: the HUD rectangle is our HUD Control, the
  ray through the clipped point comes from our camera (docs/deviations.md).

### 9.5 The falling store (500 / 510 / 660 → class 0x16, BallisticMotion 0x1c, ctor `FUN_00467ed0`, vtable 0x601b40)
- **Launch** (`FUN_004d6c10` → `FUN_00561b40` sets the aim; the launch variants `FUN_00560c20` / `FUN_00560e80` /
  `FUN_00560f60` then run the solver `FUN_005611b0` on the release state): the horizontal velocity is turned toward the
  aim (speed kept: the cross-track error is fully corrected); t = (vz + √(vz² + 19.612·(p.z − A.z))) / 9.806, the end
  time +0x68 = now + t (none: now); along-track a = 2·(dist − vh·t)/t², clamped ±`_debugParam016` (15 m/s²) when
  the owner is the player in single player; acc = (û·a, −9.806). The aim above the arc → t = a = 0.
- **Motion** (`FUN_00468470`, `FUN_004684d0`): p = p0 + v0·dt + ½acc·dt², no drag, attitude from the velocity. v1.0
  `FUN_00467910` capped dt at the impact (a sure hit); v1.1 does not.
- **Impact check** (`FUN_00561750`, at launch then every 0.5 s: 0x60ce20): the state is re-based (p0, v0 = now; same
  curve); 510 opens `_velocityJump` 1000 m above the terrain (+0x2c, `FUN_00463ec0`, a visual: not drawn); within
  `_debugParam010` 800 m of the aim the pre-explosion event 0x4e (`FUN_004012c0`, broadcast once; no detonation
  receiver found); within 2 m of the aim (0x60cddc) or at / below terrain + 1 (0x60ce18) → the detonation
  `FUN_004d6130` **at the check point**: up to ~0.5·|vz| under the ground (a level release from 1000 m: up to 70 m),
  where the blast's z term (docs/damage.md §4.1) weakens or cancels the damage (MK-82 radius 50) — a direct hit often
  does nothing (test_bomb_missions: 3 of 7 targets needed a second MK-83). **Original bug, kept by default**; Physics "Bombs burst at the ground" moves the burst to where
  the last step met the terrain (docs/deviations.md).
- **Detonation** (`FUN_004d6130`): one area blast (bdb power 0x744 / radius 0x74e) over every unit around (MK-82
  5000 / 50, MK-83 7000 / 80, MK-84 20000 / 100, M117 10000 / 75, CBU-87 2000 / 150, CBU-97 3000 / 150, ZUNNI 500 /
  50; T-55 strength 200), no submunition units; the explosion `FUN_0059df20` (weapon event class 0xa000000, the
  weapon's class and type): a burst below terrain + 10.5 m is drawn at the terrain;
  | class | where | flags | sound |
  |---|---|---|---|
  | 0x16 / 0x19 (bombs, tanks, laser bombs) | water | 0x60000 splash + ring, scale 3 | class 0xd (splash) |
  | 0x16 / 0x19, 510 | land / air | **0x2000** cluster, radius 100, 3 s | SFX_WEAPON_EXPLODED / OST |
  | 0x16 / 0x19, others | land / air | 0x4008 flash + 12 smoke streamers and column, scale 4, 95 s; a crater 1 s later when low (pool empty) | SFX_WEAPON_EXPLODED / OST (EXT_WPN_GRNDBGEPLSN) |
  | 0x17 rocket 560 | low / air | 0x98 (fireball, kick, streamers) / 0x10 | OST_ROCKET (WpnMiss) |
  | 0x17 gun 565 | | 0x10000000, 1 s | §3.5 |
  | 0x18 missiles | water / air | splash / 0x10 | |
- **Cluster bursts** (flag 0x2000, `FUN_00418000` at the start, `FUN_004181c0` per frame): 48 sub-bursts in 3 rings of
  16, 10 m below the burst; ring k radius r·0.65^k (r = max(radius, 5) = 100: 100, 65, 42 m), each at r ± j (rand %
  2j + r − j, j = max(1, ⌊0.15·r⌋)), the angle stepping −π/8 (−π/16 more per ring); each goes off after (rand & 7)·0.1
  s as a small fire (0x10000000) and every odd one adds a smoke column (0x800, 5 s); the flag ends when age /
  duration ≥ 1 (`_DAT_005ff288`). Visual only: the damage is the one blast.

### 9.6 Bombs jettison (Shift+C after the tanks, `FUN_00458d10`, once, `W+0xbc`)
Only with the release permission (§9.2); Unlimited ammo off during the loop; stations 0..8 with a bomb type other
than 560 (500 / 510 / 650) release every round toward the `_fireEndVec` (0, 500, 0) point from the jet dropped to the
terrain, each with the drag / weight updates and the count −1; they fall and burst like released bombs (armed: the
blast hits what is there).

### 9.7 Rockets (560)
Released like the bombs (§9.2, the ripple included), aimed at the ripple point of the mode-5 impact (whose prediction
adds `_limitVel` 1000 m/s along the nose). Motion: the fixed-weapon motion 0x18 of the gun rounds (§3.4) with
weapons.ibx 000560: speed |V| + `_velocityJump` 100 along the line to the aim, accelerating at `_absAcceleration`
100 m/s² up to `_limitVel` 1000 (ours: the gun formula's accelerating branch, UNCERTAIN), no hit sphere (no
`_spiralAccel`), so the rocket ends at the terrain or at its aim: the blast there (ZUNNI 500 / 50). `_maxNumInAir`
20 per pod. UNCERTAIN: the setter writes the ballistic layout into a rocket's fixed-motion state (aim (0, 6000, 100));
ours aims at the ripple point. Pods: one "Rocket box" per rocket pylon (`FUN_0053c1f0`: object 0x753d =
`weapons\Lau61\Lau61_m`, `[Weapons] RocketBoxScale` default 4.0, not in the shipped iaf.ibx) at the attach point
(ours: kept when empty, UNCERTAIN).

### 9.8 Laser bombs (650)
With the FLIR designation (`ctl+0x960`) the guided motion 0x1a (weapons.ibx 000650) flies to the designated point;
without one the aim is the bomb's (§9.3). Ours: always the bomb path and the ballistic motion (the FLIR designation is
not built; docs/deviations.md).

### 9.9 AI bomb runs (not built)
Through `FUN_00440440` (gate `FUN_004d4100`) from `FUN_005cd0d0` (impact within the tolerance or 1000 m, 0x612fc0),
`FUN_005d8590` (miss < 400 m, 600 m for kinds 0xd2 / 0xdc, angle < 15°, state 9 → 0xb), `FUN_005d9290`; release
`FUN_00454270(T, 1)`, quantity `W+0xe8`, period `W+0xf0`, aim §9.3.

## 10. Chaff and flares
**Built** (player): keys, release, counters, the decoy flight and look. **Not yet**: the decoy effect on missiles (no enemy
missiles exist yet), ECM.
- **Keys** (`FUN_0044a240`): Insert = event 0x44 chaff, Delete = 0x45 flare. Refused with the gear handle down (no
  Safety override) or weapon systems damage (flag 20); then `FUN_004545e0(0x21c / 0x226, 0, 0)`. One press = one
  decoy: no repeat, no program, no busy timer (the AI uses the same call with p4 = 1 and its brain busy flag).
- **Release**: station 10 (chaff, bdb 33) / 11 (flares, bdb 34), counts from the type's loadout slots 10 / 11 (F-16 90
  / 60), never ×2 / ×4, decremented even with Unlimited ammo; count 0 → nothing (no message, no sound). The next object
  of the station's ring pool (`_maxNumInAir` 15) must not be alive (until its end, below), so at most 15 decoys per
  type in the air; a refused press is silent. Release point: the station (StationCha / StationFla) through the
  attitude.
- **Flight** (fixed-weapon class, `FUN_004d7630` → `FUN_005605c0` → `FUN_0047a1e2`, the gun round's model): aim point
  A = release point + attitude·`_fireEndVec` (0, −200, −10): 200 m aft, 10 m below (composition UNCERTAIN); speed |V|
  + `_velocityJump` 10 along the line to A, decelerating at 50 m/s² (`_limitVel` 5): ≈ 0.85 s at 250 m/s. No hit
  sphere (`_spiralAccel` 0). **End** (`FUN_004d7690` @4d7797..4d77de): the motion's time left (vtable +0x80 =
  `FUN_00467760`: +0x78 (the time at A) − now) capped at **4.0 s** (`_DAT_00605120`, types 0x21c / 0x226 only):
  a decoy ends **when it reaches A**, at most 4 s after the release (≈ 0.85 s at 250 m/s; the full 4 s only below
  |V| ≈ 130 m/s, where the 5 m/s crawl never reaches A). There is no motion after A (`FUN_00466fc0` past +0x78 moves
  nothing). Not built: before that, for a weapon with no target (+0xb8 = 0, decoys included) `FUN_004d7690` cuts A
  at the terrain (`FUN_004020d0`, the segment from the weapon to A).
- **Sounds**: SFX_AIRCRAFT_FIRED_WEAPON / OST_CHAFF, OST_FLARE (WPN_RDRMIS_RLS); the end sound SFX_WEAPON_EXPLODED
  (WpnMiss) is in the table but its call site is UNCERTAIN (not played).
- **Look** (the bdb model is 0; the renderer's own sprites). At load (`FUN_0058a420`, [Animations] in IAF.ibx via
  `FUN_004d3b50`, the install sets none) weapon type 0x226 gets model **0x753e** and 0x21c **0x753f** (`FUN_004b3316`);
  0x753e = render type 5 with sprite 0xcd **missFLR.tga** (64×64 RGBA, `[Animations] Flare` 0.5, slot 8 @0x7d2e08),
  0x753f = type 6 with sprite 0xce **chaff.bmp** (64×64 8-bit, `[Animations] Chaff` 0.3, slot 9 @0x7d2e14); both
  sizes are stored but neither drawing reads them. The flare's smoke is slot 7: the smoke3.pal animation with
  lifetime 0.3 s and `[Animations] smokeFlare` 0.25 (`FUN_00402410(sprite, 7, 0.3, size)`). Sprites load centred
  (6th argument 1 → +0x178). Every rendered frame, per live decoy in the display list (`FUN_00412c60`):
  - **flare** (type 5): `FUN_00411f80` "drawFlare" draws missFLR at the decoy, size 0.8 + (rand % 41)·0.01
    (flicker), colour 0xff (white), frame 0 — width = 0.2 · size · 64 ≈ 10–15 m (docs/damage.md §6.1; the 0.2 is the
    hardware path: `0x6284d8` = width / tan(fov/2)); and, on the 3D-card path (`DAT_007d1960`), an event **0x8400**
    (`FUN_00416880`, lifetime 10 s): one smoke3 puff, **white** (0x400), 0.3 s, width 3.2 m growing ×3, drifting
    like the 0x100 puff (`FUN_00416e20`, `FUN_00416a70`). One puff per frame = the flare's smoke trail.
  - **chaff** (type 6, not drawn itself): an event **0x10004** (scale 2, lifetime 10 s) per frame: 20 pieces
    (`FUN_00417bb0`, flag 0x10000; without it 10 dark debris pieces), each a triangle (0x4163df: (0.25, 0.4, −0.25),
    (0.6, 0.15, 0.5), (−0.15, −0.1, 0.3) m, uv (0,0) (1,0) (1,1), drawn both sides) textured with chaff.bmp
    (black / white / grey noise), pre-lit grey 0xdcdcdc, no blend state of its own (`FUN_00417d40`). Per piece:
    from the decoy's spot, velocity (rand % 15 − 7)·2 m/s on each axis (nothing from the jet), spin (rand % 65 − 32)·0.1 rad/s on
    each axis, start delay (rand % 30)·0.01 s, then 3.0 s at p0 + v·t − 15·t² (g = 30). A falling stream of glitter
    along the decoy's path that outlives the decoy by up to 3.3 s.
  - `MissileFlareDistance` ([SFX], default 1.0) is not a decoy setting: how far behind a missile (types 0x230,
    0x23a..0x27b) its trail starts; missFLR is also the missile motor glow at the trail's head ("renderTrailFlare",
    `FUN_00415a60`).

  **Port** (`decoy_fx.gd`): the same sprites (iaf-convert, 4× Lanczos: converted/objects/missflr.png, chaff.png),
  sizes, timing and motion; the flare additive, its smoke = damage_effects.gd white puffs; the chaff pieces one
  shader-driven MultiMesh; emission at a fixed 30 Hz instead of per frame (docs/deviations.md).
- **Panel counters** (`FUN_0052eab0`): "%03d" of stations 10 / 11 at `[CHAFF]` / `[FLARE]` OffX / OffY, Arial h10
  w5, pale yellow RGB(255, 255, 179) (docs/cockpit.md).
- **Decoy rule** (`FUN_00454b70`, cases 0x21c @455775 / 0x226 @455968; decided once at the release): candidates = the
  releasing jet's RWR list of missiles launched at it (`FUN_00452160`; a missile is added at its launch unless RWR
  damage flag 14 is set — with RWR damage decoys fool nothing). For each missile in list order: skip one already
  chasing a decoy; chaff only fools 600 / 610 / 630, flares 570 / 580 / 620; r = rand()/32767; chaff p = (g > 4.0 ?
  0.3 : 0.1) (0x600f18, 0x600f28, 0x600f0c); flare p = afterburner on ? 0 : (g > 4.0 ? 0.5 : 0.33) (0x600f04,
  0x600f44); r > p **ends the whole scan** (quirk: one resisting missile protects the later ones); else the missile
  chases the decoy (`FUN_004d83c0` → `FUN_005622e0`, q 1.0). No generation or range test. Bearing gates against
  doubles 6302.5 / 4010.7 / 5156.6 are dead (the bearing is in radians). When the decoy ends (`FUN_004d8160`) the RWR
  entry is dropped; what the missile does then is UNCERTAIN.
- **ECM** (event 0x46, LIGHT006, ctl+0x1b8; refused with ECM damage flag 1): switching on (`FUN_004582f0`, needs an
  ECM fitted: W+0xcc or a station named "ECM") jams, once, each missile of type 600 / 610 in the RWR list, not decoyed,
  still flying, with rand < 0.6 (0x600f68): its motion +0x148 = 1 (guidance off, UNCERTAIN). No effect on SAMs.

## 11. Homing weapons and the radar missiles (600, 610)

### 11.1 One homing motion (class 0x18)
Every homing weapon flies the chase motion of §5.3 (`missile.gd`, launcher independent: the player's or an AI's
`launch_homing`): 570 / 580 IR, 590 HARM, 600 / 610 radar, 620 / 630 SAMs and **635 Maverick** (the other guided
class, 640 / 650, flies another model). Two additions over §5.3, both in `FUN_005627e0`:
- **Release drop** (@563358): while age < `_timeRelease` (+0xb0, 0.3 s for the radar missiles) the motor is not lit;
  the weapon only accelerates by `_absReleaseAcceleration` (+0x9c, 30 m/s²) along +0xd4, set at the start
  (`FUN_00561ef0`) from the launcher's attitude (taken as the body's down axis: UNCERTAIN which matrix row).
- **Guidance off** (+0x148 = 1; `FUN_00458130` → `FUN_004d8420`, ECM `FUN_004582f0`): no more steering, the motor
  still pushes along the velocity; the overshoot end then keeps the weapon's own point.
- **Retarget** (`FUN_005622e0`, from a decoy's `FUN_004d83c0`): a new target key; q, chase law and gain stay.
- **Time left** (vfunc +0x80, `FUN_00468db0`): burn − age (the end time stays 1e8 for `_endType` 2 while it flies).
Launch / flight / explosion sounds use the weapon's OST (570 OST_HEATMISSILE, 580 OST_LIMITEDHEATMISSILE, 590
OST_HARM, 600 OST_RADARMISSILE, 610 OST_SEMIRADARMISSILE, 635 OST_MAVRICK). A missile launched at the player enters
its RWR (`FUN_004d8130` → `FUN_0044e160`) and leaves it at its end (`FUN_004d8160`).

### 11.2 DLZ (vfunc +0x74, `FUN_005624f0`)
flown(s, t) = s·t + ½·a·(1 − 4β)·t² (`FUN_005627b0`, the motion's a = `_absAcceleration`, β = `_spiralAccelBeta`).
burn = `_timeAcceleration` + `_timeConstVel` + `_timeDecceleration` (Real: its own burn). Without a target: [max, min]
= [flown(|V|, burn), flown(|V|, 1 s)]. With one: max = flown(|V| − the target's speed away from the launcher, burn −
2 s) (0x60ce78), min = flown(|V|, `_timeConstOrientation` + 2 s) (0x60ce80); both 0 when the target is 90° or more off
the nose (acos ≥ π/2, 0x84162c) or min > max. Example, AMRAAM generation 3 (a 120, β 0.1, burn 35 s, tCO 3 s)
head-on at 250 m/s against a 250 m/s target: **max 55.7 km, min 2.15 km**. The cockpit keeps the selected store's DLZ
at the radar's target in S+0x348 (max) / S+0x350 (min) every frame while the radar has a lock / TWS selection or the
HARM sensor a target (`FUN_00456520`), else the last values.

### 11.3 MRM HUD sight (mode 2, `FUN_00460ea0`; HARM mode 8 `FUN_00460a90`; base `FUN_00462ab0`, `mrm_sight.gd`)
- **Target** (vfunc +0x28): the radar's A-A lock or TWS selection (mode 8: the HARM page's selected emitter);
  locked = vfunc +0x2c.
- **Circle** (vfunc +0x3c `FUN_00462c10`): size 5 without a lock (×12 px, at least 10 px, at most the field's
  extent from the HUD centre); with one, 5·(1 − (dist − min)/(max − min)) inside the DLZ, at least 5/3, and 5/3 at or
  outside it. On the HUD centre (`FUN_00537120`). With a radar lock a caret outside it at the target's bearing
  (state+0x4c, `FUN_0044e770`; 4 px deep, 4 px wide, at bearing + π from up: UNCERTAIN sign).
- **Predicted point** (`FUN_00462f70`, state+0xe74): the target led by dist / 2000 s (√(dist²·2.5e-7)) at its
  velocity; a 5×5 blob (`FUN_00536ea0`), blinking (300 ms) when held at the HUD edge.
- **Launch** (`FUN_00457f70`): without Easy aiming the sight's target counts only when its screen point is within
  **240 px** of the HUD centre with a lock (**60 px** without; vfunc +0x30 `FUN_00462ad0`), and q = vfunc +0x38
  (`FUN_00463160`: 1 with the predicted point inside the circle, else R / d) **× 0.8** (v1.1); with Easy aiming any
  target, q = 1. A target with its ECM on, against a radar seeker: q − rand. q ≥ 0.1. In the HUD-only view the
  in-circle test uses 2·R² (the original's compare).
- **Shoot cue** (state+0x1010, modes 1 / 2): the predicted point inside the circle, rounds left, the radar in A-A,
  min ≤ dist ≤ max: a triangle under the target box (apex 2h − 6 px below its centre, base 2h, ±3 px). Mode 1's cue
  from the IR seeker is not ported yet.
- **"%2d SEC"** (HUD row 5 in modes 1, 2, 8; S+0x380): the last launched weapon's time left (`FUN_0053bec0` → its
  motion's vfunc +0x80, clamped by `FUN_004d6ac0`: below 0 → 0, above 300 → 60).
- **STT envelope ticks** (MFD, `FUN_00534160`): three black ticks at y 39 / 65 / 91 and the DLZ max / min as ticks
  x 121..117 at y = 122 − ⌊v·112/(R·1853)⌋ while inside the scale (docs/mfd.md).
- Ours: the screen offsets come from the camera ray through the HUD centre built from the camera's projection matrix
  (Godot's `project_ray_normal` ignores the cockpit camera's frustum offset: the sight was ≈ 5° low before).

### 11.4 Semi-active (610)
A 610 launched at a target makes the radar lock it (`FUN_004ad880(2)`, STT) and joins W+0x274. The radar dropping or
changing its track (`FUN_00458130`: Q, R, S, Return / Shift+Return, a blip click, Backspace with a lock, STT lost, any
mode change leaving STT) turns the guidance of every 610 in the list off and empties it. Radar damage does **not**
call it (original quirk, kept: the Sparrow keeps guiding after the radar dies). The 600 (active) never depends on the
radar after launch.

### 11.5 HARM (590: AGM88, SHRIKE)
The same launch (`FUN_00454b70` case 0x24e, HUD mode 8) and the same homing motion (weapons.ibx 590: dog chase,
a 120, β 0.08, burn 23 s, tCO 2 s, `_fireEndVec` 7 km ahead). Selecting a 590 puts HUD mode 8, the HARM sensor on
(`FUN_0045c2b0`) and the HARM page (10) up (`FUN_00449810`). The HARM HUD object (`FUN_00460a90`, vtable 0x601560)
differs from the MRM's only in vfunc +0x10 (`FUN_00460ac0`: no circle; "In Range" = the selected emitter nearer than
the selected store's DLZ max, the seeker diamond at its screen point) and +0x28 / +0x2c (`FUN_00460e10` /
`FUN_00460e40`: the HARM sensor's selected target and whether it has one). So the launch takes the HARM page's
selected emitter when its screen point is within 240 px of the HUD centre (Easy aiming: anywhere), q = vfunc +0x38 ×
0.8; without one the missile flies at its `_fireEndVec` point. After the launch nothing ties the HARM to the emitter
staying on (no type test in the flight code): it chases the unit like any homing weapon and its blast (AGM88 power
5000, radius 20; SHRIKE 5000 / 50) hits what is around. The emitters come from the RWR (docs/deviations.md "HARM page
source"); until the AI / SAM sensors lock the jet (not built), nothing in a mission fills the HARM page.

### 11.6 Validation
`tests/godot/test_radar_missiles.gd`: the DLZ (AMRAAM example, receding target, target behind, no target), the circle,
lead and in-circle q; per jet in mission 231 (F-16, Lavi, F-35I AMRAAM; F-15, F-4E, Kurnass 2000 Sparrows) radar lock
of a MiG 8 km ahead, the MRM HUD (circle inside the DLZ, lead point, shoot cue, DLZ ticks), the launch, the hit, and
Backspace dropping the Sparrow's guidance but not the AMRAAM's; Real AMRAAM 157 kg, Mach 4, 70 km.
`tests/godot/test_harm.gd`: per jet (the seven Jet list jets and the F-35I) in mission 231, a ground unit 15 km ahead
locking the jet (an RWR emitter): '[' selects the AGM88 (master 4, HUD mode 8, the HARM page), the page lists and
preselects it, the HUD diamond and In Range, the launch at it and the kill; a SHRIKE with no emitter flies at its
end point.

## 12. TV weapons (635, 640) and the guided motion (640, 650)

### 12.1 Classes
The **Maverick 635** flies the homing motion (class 0x18, §11.1). The **TV missile 640** (AGM-62, POPEYE, GBU15) and
the **laser bomb 650** fly the **guided motion** (class 0x19; motion vtable 0x601f70, the TV / laser variant 0x601ed0
differs only in the destructor; ctor `FUN_00469aa0`, size 0x130). The weapon class (vtable 0x605178) configures the
motion with the launch data's point (+0x14 `FUN_004d7ed0`: the target unit is ignored), sets a new aim with +0x2c
(`FUN_00469f00`, ignored in mode 2) and reports +0x30 the status (`FUN_004d8030`: (mode ≠ 0) + 2 = 2 TRA / 3 TER).
Explosion class 0x19: the falling store's (flash + streamers, no trail). `game/weapons/guided.gd`.

### 12.2 Guided motion
- **Config** (`FUN_00563d30`; weapons.ibx field → its use, the ibx comments name it): `_absAcceleration` +0x78 the
  engine, `_timeAcceleration` +0x88 its time, `_timeConstVel` +0x74 the **squared** horizontal distance of the switch to
  mode 1, `_absDeceleration` +0x7c the turn gain, `_timeDecceleration` +0xa0 the up acceleration, `_spiralAccelBeta`
  +0xa8 the down acceleration, `_spiralAccel` +0x118 the end time, `_absReleaseAcceleration` +0x120 the maximum
  velocity, `_timeRelease` +0x11c the velocity damp, `_timeConstOrientation` +0x98 tCO, `_rollRate` +0xc8 the maximum
  up angle. 640: 10 / 2 / 3e7 / 150 / 20 / 70 / 420 / 300 / 8 / 2 / 0.018; 650: 10 / 2 / 3e37 / 170 / 165 / 165 / 420
  / 200 / 30 / 2 / 0.34; 1640 (POPEYE): 5 / 10 / 3e37 / 100 / 100 / 100 / 180 / 350 / 30 / 5 / 0.8.
- **Start** (`FUN_00563f90`): p0 = the release point, v0 = the launcher's velocity; one update, then mode 0.
- **Update** (`FUN_005643a0`, every 0.5 s, 0x60cf48): re-base p0 / v0 from the current motion, the acceleration
  reset; the pose = the position and the velocity's heading / pitch. At or below the terrain: z held at the terrain,
  no steering. Else (from age +0x90, UNCERTAIN: the release push via +0x80 / +0x90 reads fields nothing sets, taken as
  none): the errors (`FUN_00564fe0`): heading = atan2(dx, dy) − heading, wrapped only above π (original quirk: below −π
  it turns the long way, kept); pitch target = asin(LOS z), in mode 0 the maximum up angle, never above it. Then
  - lateral: right (D × U, roll 0) · turn gain · heading error;
  - mode 0: (0, 0, −9.806) + up · (x > 0 ? up accel : down accel) · x, x = min(pitch error + 24°, 40°) (0x60cf58 /
    0x60cf5c); modes 1 / 2: up · 2 · down accel · pitch error, no gravity;
  - engine: age < tAcc → + D · engine; else if (max velocity − speed) · damp < 0 → + the **unit** D. **Original bug**
    (kept): the damping product is computed and dropped, so above the maximum velocity the weapon gains 1 m/s².
- From age 0.001 s (0x60cf60), on the squared horizontal distance d² to the aim: d² < _debugParam010 (800, not
  squared) → the weapon's pre-explosion event (vfunc +4, not ported: no receiver traced); the mode for the **next**
  update: d² > switch → 0, switch > d² > _debugParam014² (200 m) → 1, d² < _debugParam014² → 2. End: (age > end time
  or below the terrain) and age ≥ tCO; the burst at the aim if within _debugParam013 (200 m, 3D) of it, else where it
  is (`FUN_004d6130`). The 650's switch distance (3e37) is never passed: after the start's mode 0 its first updates
  run in mode 1, its 0.5–1 s step in mode 0 (pulled up toward 0.34 rad at up to 165 · 0.698 ≈ 115 m/s²; traced).
- **Time left** (`FUN_00564f10`): |aim − position| / speed, at most 280 s (0x60cf70).
- **DLZ** (`FUN_005641c0`, max = min): h = the height above the terrain (≥ 0); a = 9.806 − _debugParam011 (70) · π/180
  · up accel, at least 1 (0x60cf38: so 1 for every shipped record); t = the larger root (−vz_down ± √(vz_down² + 2ah))
  / (2a) (UNCERTAIN: 2a, not a); T = min(t, tAcc), d1 = T · |v_xy|, range = d1 + ½ · engine · T²; when t > tAcc: d1 =
  min(d1, max velocity), range += min(t − tAcc, end time − tAcc) · d1 (**original bug**, kept: d1 is a distance used as
  a speed). AGM-62 level at 1000 m and 250 m/s: ≈ 6.6 km.

### 12.3 TV release and the camera (`FUN_00454b70` cases 0x27b / 0x280, `FUN_0045db70`, `FUN_004604c0`, `FUN_00460940`)
- **Launch data** (8 dwords): the camera not started on a unit (mcp+0x10 = 0): the EO centre point (`FUN_00450480`),
  no unit, q 1. Started on one (mcp+0x10 set by `FUN_00450280` → `FUN_0045dde0`: only the Maverick, on the radar's
  target): the radar's target (radar not damaged, a lock / a TWS selection) and the point UNCERTAIN (uninitialised;
  ours: the EO centre). The Maverick flies the homing motion at the unit or the point, the 640 the guided motion at the
  point. The release needs no HUD-mode test beyond §2's; the selected store gives master 6 / HUD 7.
- **The camera rides the weapon** (`FUN_004604c0`): while the launched store flies (+0x48 = 1) the camera's eye and base
  are the weapon's pose; after its end, the jet's. For a launched non-Maverick in TRA / TER with the cockpit drawn
  (views 1 / 0x12 / 0x16) or ctl+0x938, each TV update sets the weapon's aim to the EO centre point (vfunc +0x2c): the
  pilot steers it with the camera. With the slew keys released a flying TV weapon's camera locks on the EO centre
  (docs/mfd.md).
- **Status** (`FUN_00460940`): 0 unless the TV weapon (the flying one, else the store) is 635 / 640 / 650; 1 RDY before
  launch and for a launched Maverick, else the weapon's 2 TRA / 3 TER; 0 when the selected store has no rounds left and
  (nothing flies or a Maverick flies).
- **TV page "%3d"** (111, 110): the TV weapon's time left through `FUN_004d6ac0` (< 0 → 0, > 300 → 60); before a launch
  0 (UNCERTAIN: the original reads the store's motion then).
- **HUD mode 7** (`FUN_0052fa10` case 7): the seeker diamond (`FUN_00536ff0`) on the EO centre point's projection while
  the status ≠ 0, held inside the field along the line from the HUD centre. No "SEC" row in mode 7.

### 12.4 HUD range scale (not built)
`FUN_005397a0`, drawn in HUD modes 1, 2 (via `FUN_0052ffb0` / `FUN_0052ff30`) and 7 while the radar has a lock
(S+0xa20); s = the HUD scale: X = HUD x + (RightBorder R+0x2228 − 4)·s, Y = param_5 − 50·s (param_5 taken as the HUD
centre y, UNCERTAIN), H = 66·s, k = H / (the radar range R+0x2748 NM × 1853). Pen polyline (X−2, Y) → (X, Y) → (X, Y+H)
→ (X−3, Y+H). DLZ bracket: ym = clamp(H − ⌊S+0x350·k⌋, 0, H), yM likewise from S+0x348; lines (X+s, Y+ym) → (X−2s,
Y+ym) → (X−2s, Y+yM) → (X+1+s, Y+yM). Range caret at c = H − ⌊H·S+0x388 (lock range NM) / R+0x2748⌋: (X−3s−3, Y+c−2)
→ (X−3s−1, Y+c) → (X−3s−4, Y+c+3). Text (sprite font, right-aligned, `FUN_00525920`): "%3dK" (0x65d6b4) of ⌊2·S+0x3a0⌋
(the closure ×2) ending at (X−3s−4, Y+c−2); "%3d" (0x65d754) of the range scale ending at (X, Y−8).

### 12.5 Validation
`tests/godot/test_tv_weapons.gd`: the guided DLZ formula, the start in TRA, the terminal TER, the burst snapped to the
aim; per jet (the seven Jet list jets and the F-35I) in mission 231 with an AGM-62 on station 0 and an AGM-65 on
station 8: '[' gives master 6, HUD mode 7 and the TV page; the camera on a ground unit 8 km ahead: RDY, the HUD diamond,
the DLZ; the launch: TRA, the time left, the camera riding the missile; the hit; NO SOURCE with no rounds left; the
Maverick at the camera's point and its hit.

## UNCERTAIN
Candidate order of the spatial query; event 0x4e (pre-explosion) receiver; the bomb time-to-go speed (selector 6);
the rockets' accelerating motion; the rocket box when empty; hit effects look; tracer look; muzzle flash
scale / blend / cockpit visibility; the MFD page placement for weapon modes (taken as event 0x5a's rule); the missile
flight loop sound and explosion look; `FUN_0045ee10`'s selector 0 (taken as the load factor); the snap views' camera
type for the seeker's helmet branch (§5.4); what a missile aims at when its target is gone (`FUN_0045a180`, taken as the origin); the HUD text
font; the store-selected box placement; the release drop's direction (§11.1) and the MRM caret's sign (§11.3).
