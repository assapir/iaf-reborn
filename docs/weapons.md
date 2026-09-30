# Weapons — the player's gun, IR missiles, stores (v1.1)

How Jane's IAF v1.1 arms the player's jet and how iaf-reborn ports it (`game/weapons/`). All addresses v1.1
(`assets/ghidra_v11/iafjets.c`; docs/v1.1.md maps them to v1.0). World frame X east, Y north, Z up, metres, sim
seconds. `ctl` = the player controller (`this` of the GEV handler `FUN_0044a240`), `W` = its weapon system
`ctl+0xf0`, `C` = the station container `ctl+0xfc` (= `W+0xc`), `S` = the flight-model state.

Built: the stores (loadout, pylons, selection, release, weight / drag, fuel tanks and their jettison), the master /
HUD modes, the gun (trigger, rounds, hits, muzzle flash, sounds, LCOS / strafe pippers), the IR seeker and the IR
missiles (types 570 / 580), the weapon HUD text and symbols, the stores MFD page. Not built yet: bombs (CCIP / CCRP,
ripple quantity / interval, the bombs jettison), rockets, radar missiles and the radar lock (so the seeker is never
"slaved", no DLZ), HARM, TV / laser weapons, chaff / flares (and so the flare decoy), the AI's weapons, AAA.

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
The Arming screen would override the pylons (not built). Count 0 or an unknown id = no station.
Displayed count (`FUN_0053cfd0`): the gun's count ×4 when its name contains "20 MM" (`W+0xc4`), else ×2 (DEFA); F-16
235 → 940, 5 shots/s → empty after 47 s. Gun counts per jet: F-16 / F-15 / Lavi 235, F-4 160, Mirage DEFA 125, Kfir
DEFA 150, MiG-29 140, MiG-21 550, MiG-23 DEFA 175.

### 2.2 On the model
Types 500, 510, 570, 580, 590, 600, 610, 635, 640, 650, 660 get their store model on pylons 0..8 (rockets 560 a rocket
box: not built); gun, chaff and flares are never drawn. Slots (`FUN_0053c990`, once, in the original's E frame
x = −glTF x, y = glTF z (aft), z = up) from the attach point P and the store model's `pilon` helper (px, py, pz)
(default (0, 0, PilonDefaultZ 5)):
- TER (non-bombs, bombs ≤ 3): A = P+(pz,0,0), B = P+(−pz,0,0), C = P+(px,py,−pz); stations with index > 5 swap A / B
  (station 5 is not mirrored: the original's `> 5.0`); a count of 1 at the start → slot 0 = C.
- MER (500 / 510, count ≥ 4): (±pz, ±L, 0), (0, ±L, −pz), L = `[Misc] BombStationLength` 2.0.
Drawn (`FUN_0053e430`, any aircraft with a controller): `count` stores at slot[0..count−1] — a released store
disappears (the highest slot) — only with Preferences > Graphics EXTERNAL STORES on and within 9000 m of the camera.

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
| 650 | 5 | 5 (6 with a FLIR pod) | stores / FLIR |
| 635, 640 | 6 | 7 | TV |
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
  `W+0xb8`) releases one store from every pylon whose name contains "LB" (count −1 even with Unlimited ammo, drag
  update, no weight update), then, when the fuel is at or above FuelWeight (`FuelWeight·2.2046 ≤ fuel lb`), motion
  0x18 (`FUN_005a2270`) sets the fuel and its maximum to FuelWeight: the tanks' remaining fuel is gone. Later presses
  drop the bombs (500 / 510 / 650, `FUN_00458d10`, once, `W+0xbc`): with the bombs. Tanks are never selectable, so
  the jettison is their only release. (Ours: the dropped tank is not drawn falling.)
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
the locked radar target first (none yet), then every unit within 10·|A − P| other than the shooter (**friendlies
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
70° / 15 NM (NM = 1854 m); the cone only matters when radar-slaved (not built). Search (`FUN_00461680`) at most every
0.5 s: the unit nearest the boresight within **6000 px²** (≈ 77 px) of the HUD boresight that passes can-track —
**no side test** (friendlies too). Can-track (`FUN_00461d10`): 580 only within ±60° of the own heading (a bearing
test, not the "tail" of the comment); range ≤ R; beyond **R/2 only a target with its afterburner on** (AI jets have
no afterburner state yet, so for now R/2). Visible (`FUN_00461f10`): within 6° of the nose. Every 0.05 s: tone seek /
lock (SFX_IR_SEEK Wpn_IRCHIRP / SFX_IR_LOCK WPN_IRCHIRPON; none without rounds); lock = a visible trackable target (no
lock timer; lost at once). The seeker diamond (±7 px) eases 0.3 / 0.7 toward the target's HUD point (snaps within
5 px), back to the boresight without one. Missile circle r = 5·12 px (min 10) on the boresight. Ours: the HUD
screen offsets are 12 px/deg from the boresight (the original projector is not traced).

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

## 6. HUD and MFD
Weapon text (`FUN_0052ef20` pass 3, left column at HUD centre − TxtOffX, rows 7 px from centre + TxtOffY; row 2):
"%1d %s %s" = total of the selected store (same type and name), name, RDY / MAL (MAL with flags 20 / 21, or 13 with
the gun), "NAV" in HUD mode 0; drawn on the glass, outside the symbology field's clip. (Ours: the HUD font; the
original uses the MFD sprite font. Our own G / Mach readouts of the HUD sit near it.) Stores page
(`FUN_0052c740`): per pylon count / name at the docs/mfd.md positions, MRM / SRM totals, gun rounds "%03d" at (68,85),
fuel, the selected station boxed (gun 36×10 at (48,82)); ours leaves out "%dQnt" / "int%d" (bomb quantity / interval,
with the bombs).

## 7. Weapon data: Real (Extras)
Preferences > Extras > Weapon data = Real overlays public numbers (docs/real-weapons.md): missile weights, top speed
(β) and range (burn), gun rounds per jet, rate of fire and muzzle velocity. Original by default.

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

## UNCERTAIN
Candidate order of the spatial query; event 0x4e (pre-explosion) receiver; hit effects look; tracer look; muzzle flash
scale / blend / cockpit visibility; the MFD page placement for weapon modes (taken as event 0x5a's rule); the missile
flight loop sound and explosion look; `FUN_0045ee10` (release permission, not ported); views 0x12 / 0x16 of the seeker
field of view; what a missile aims at when its target is gone (`FUN_0045a180`, taken as the origin); the HUD text
font; the store-selected box placement.
