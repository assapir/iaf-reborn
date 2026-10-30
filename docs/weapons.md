# Weapons — the player's gun, IR missiles, stores (v1.1)

This doc describes how Jane's IAF v1.1 arms the player's jet and how ours ports it (`game/weapons/`, logic in
`crates/iaf-avionics`): the data records, the stores, the gun, the missiles, the bombs and rockets, the decoys and
the TV weapons. The radar and its lock are in docs/radar.md, the RWR in docs/rwr.md, the Real numbers in
docs/real-weapons.md.

Key facts:
- All addresses are v1.1 (`assets/ghidra_v11/iafjets.c`); docs/v1.1.md maps them to v1.0.
- World frame: X east, Y north, Z up, in metres and sim seconds.
- Short names for the original's objects:
  - `ctl` = the player controller (`this` of the GEV handler `FUN_0044a240`).
  - `W` = its weapon system, `ctl+0xf0`.
  - `C` = the station container, `ctl+0xfc` (= `W+0xc`).
  - `S` = the flight-model state.
- There is no master arm and no "out of ammo" message or sound.
- AI units have no ECM (only a unit with a controller jams: docs/ai.md §13). The AI's weapons are in
  `game/ai/combat.gd` (docs/ai.md §13–14).

Terms used in this doc:

| term      | meaning                                                                                         |
|-----------|-------------------------------------------------------------------------------------------------|
| AA / AG   | air-to-air / air-to-ground                                                                      |
| bdb       | the game's binary database (the Weapons and Objects tables)                                     |
| CCIP      | continuously computed impact point: the bomb pipper shows where a store released now lands      |
| CCRP      | continuously computed release point: release on a designated target (the game has none)         |
| DLZ       | dynamic launch zone: the missile's minimum and maximum range against the current target         |
| ECM       | electronic countermeasures (the jammer)                                                         |
| EO        | electro-optical (the TV camera of the TV weapons)                                               |
| FLIR      | forward-looking infrared (the targeting pod and its MFD page)                                   |
| FM        | the flight model                                                                                |
| HARM      | high-speed anti-radiation missile (type 590: AGM88, SHRIKE)                                     |
| HUD       | head-up display                                                                                 |
| LCOS      | lead-computing optical sight: the AA gun pipper (HUD mode 3)                                    |
| MER / TER | multiple / triple ejector rack (store slots on one pylon, §2.2)                                 |
| MFD       | multi-function display                                                                          |
| MRM / SRM | medium-range (radar) / short-range (IR) missile                                                 |
| NAV       | the navigation master mode (no weapon)                                                          |
| OSB       | option select button: a button around an MFD                                                    |
| q         | launch quality, 0.1..1: scales the missile's steering gain (§5.2, §5.3)                         |
| RWR       | radar warning receiver                                                                          |
| STT / TWS | the radar's single-target track / track-while-scan (docs/radar.md)                              |
| tCO       | `_timeConstOrientation`: the time a missile flies straight before it steers                     |
| TRA / TER | the TV weapon's status codes on the TV page: 2 TRA (guided mode 0), 3 TER (modes 1 / 2) (§12.1) |
| JDAM      | joint direct attack munition: a GPS / INS tail kit on a plain bomb (ours, §13.2)               |
| LAR       | launch acceptability region: where a released GPS bomb reaches its aim (§13.3)                  |
| LOAL      | lock-on after launch: the missile finds its target after it leaves the rail (§13.1)             |
| SDB       | small diameter bomb, the GBU-39 (§13.2)                                                         |
| TD        | target designator: the HUD box on the radar's designated point (docs/radar.md §8)              |

What is built:
- Chaff and flares (§10).
- The stores: the loadout (with the Arming screen's), pylons, selection, release, weight / drag, fuel tanks and their
  jettison.
- The master / HUD modes.
- The gun: trigger, rounds, hits, muzzle flash, sounds, LCOS / strafe pippers.
- The IR seeker and the IR missiles (types 570 / 580).
- The bombs (500, 510 with the cluster bursts, 650 as a free bomb) and rockets (560) with the ripple quantity /
  interval, the mode-5 HUD (CCIP and the delayed release) and the bombs jettison (§9).
- The weapon HUD text and symbols, the stores MFD page.
- The FLIR pod / TV-weapon camera and the FLIR / TV / HARM MFD pages (docs/mfd.md).
- The radar missiles (600 AMRAAM-like, 610 Sparrow-like) with the DLZ, the MRM HUD sight and the semi-active rule.
- The HARM / Shrike (§11).
- The TV weapons (635 Maverick, 640 TV missile) with the guided motion, the camera riding the weapon and the TV
  page's TRA / TER and time (§12).
- The laser bombs with the FLIR designation (§9.8).
- Ours, the modern weapons (the F-16I Sufa and the F-35I; with Extras "Weapons" on Modern also the Barak and the
  F-15): the AIM-9X and Python 5 (high off-boresight
  shots through the helmet, lock-on after launch), the JDAMs and the GBU-39 (GPS bombs to a designated point, with an
  in-range cue) (§13).

## 1. Data

Each weapon has a bdb record (what it is) and a weapons.ibx record (how it moves).

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

The weapon object (`FUN_004d5c70`) copies these fields: +0x70 power, +0x74 weight, +0x78 drag, +0x7c generation,
+0x80 radius, +0x84 = radius + 20 (the blast query pad).

The category (`FUN_004d72a0`):
- 0 gun (565);
- 1 AA (540, 550, 570, 580, 600, 610);
- 2 AG (500, 510, 560, 590, 635, 640, 650);
- 3 other (660).

### 1.2 weapons.ibx (motion parameters)
The file is `[Weapons] weaponsPath` (default WeaponsMotion) + `Weapons.ibx`, read by `FUN_0055fa00` → `FUN_0055f420`.
- `[WEAPONnnn]` sections are keyed by `type` = generation·1000 + sub type.
- `[DEBUGDATA]` holds `_debugParam000..019`.

Lookup (`FUN_0055f170`):
1. `_debugParam002` = 1 → every weapon uses type 800.
2. Else the record for type + gen·1000.
3. Else the record for the sub type alone.

| key | weapons | chase | absAcc | burn (tA+tCV+tD) | tConstOrientation | spiral / β |
|---|---|---|---|---|---|---|
| 003570 | AIM-9L, AIM-9M, PYTH-3 | 2 | 100 | 16 | 2 | 1000 / 0.08 |
| 004570 | PYTH-4, AA-11 | 2 | 140 | 22 | 1 | 1000 / 0.08 |
| 001580 | AIM-9D, SHFR 2, AA-2, AA-6 | 2 | 150 | 10 | 2 | 800 / 0.08 |
| 000565 | gun rounds | — | −10 | — | 0.1 (hit check period) | 50 (hit distance) |

Gun record: `_limitVel` 1200, `_limitDist` 4500 (read only by the AG lead), `_velocityJump` 1200, `_maxNumInAir` 20
(the round pool). Only the AI weapon timer reads `_fireReleaseInterval` / `_reactionTime`.

## 2. Stores

A jet carries up to 12 stations. This section covers what is loaded, how it is drawn, selected and released, and
what it weighs.

### 2.1 Loadout (`FUN_0058f110`, stations `FUN_004b7ea3` → `FUN_0053b580` → `FUN_0053c1f0`)
The loadout has 12 slots of {weapon id, count}:
- 0..8: the pylons StationA..I;
- 9: the gun (StationGun);
- 10: chaff;
- 11: flares.

Where the slots come from:
- Pylons 0..8 come from the mission entity's `CArmament` when any of its 0..8 ids is set, else from the object type's.
- Slots 9..11 always come from the type.
- A count of 0 or an unknown id means the station is empty.

The Arming screen (docs/front-end.md §15) replaces pylons 0..8 of both aircraft of a flight with its table
(`FUN_004f00f0` → `FUN_004f0140` → `FUN_004541d0`; then `FUN_00459410` redoes the weight / drag). Ours puts
`Settings.arm_loadouts[flight]` on the player's pylons before the stores are built (`player_weapons.gd _arm`). The
models, counts and §2.5 weight / drag then follow. The Arming screen sets pylons only: the gun, chaff and flares keep
the type's slots.

Displayed gun count (`FUN_0053cfd0`): the count ×4 when the gun's name contains "20 MM" (`W+0xc4`), else ×2 (DEFA).
Example: the F-16's 235 shows as 940; at 5 shots/s the gun is empty after 47 s.

Gun counts per jet: F-16 / F-15 / Lavi 235, F-4 160, Mirage DEFA 125, Kfir DEFA 150, MiG-29 140, MiG-21 550, MiG-23
DEFA 175.

### 2.2 On the model
Types 500, 510, 570, 580, 590, 600, 610, 635, 640, 650, 660 show their store model on pylons 0..8. Rockets (560) show
a rocket box (§9.7). The gun, chaff and flares are never drawn.

The store slots on a pylon (`FUN_0053c990`, computed once) are in the original's E frame: x = −glTF x, y = glTF z
(aft), z = up. They come from the attach point P and the store model's `pilon` helper (px, py, pz), default (0, 0,
PilonDefaultZ 5):
- TER (non-bombs, bombs ≤ 3): A = P+(pz,0,0), B = P+(−pz,0,0), C = P+(px,py,−pz); stations with index > 5 swap A / B
  (station 5 is not mirrored: the original's `> 5.0`); a count of 1 at the start → slot 0 = C.
- MER (500 / 510, count ≥ 4): (±pz, ±L, 0), (0, ±L, −pz), L = `[Misc] BombStationLength` 2.0.
Drawing (`FUN_0053e430`) applies to any aircraft whose entity +0x34 object is set: every flown jet, the AI jets too
(docs/damage.md §5.3).
- It draws `count` stores at slot[0..count−1]. A released store disappears from the highest slot.
- It draws only with Preferences > Graphics EXTERNAL STORES on and within 9000 m of the camera.
- Ours draws the AI jets the same way (`combat.gd` `_show_stores`, `player_weapons.gd` `attach_stores`).
- A station whose model lacks a `Station*` helper (Su-24, Su-22, MiG-21, MiG-25, …) has no attach point. Ours draws
  nothing there (UNCERTAIN: the original's attach point without the helper); its weight / drag still count.

**Pylons** are **part of each jet's model**. The code only draws the stores (`FUN_0053e430`) and attaches them
(`FUN_0053c1f0`: the store, weapon record +0x1c, and the 560 rocket box). The bdb Weapons and Objects records carry
no pylon / rail field ("Pilon" in the code is the pilot eye or the store's lug helper).
- The geometry: thin vertical double-sided quads (F-16: material `f16_2side1`, alpha mask, UV v 1.07–1.11 with repeat)
  under stations B..D / F..H, from the wing to ≈ 0.1 model units below the attach point. The wingtip rails A / I have
  none.
- So the pylons are always drawn, loaded or empty, after a release and with EXTERNAL STORES off.
- The store's lug (its `pilon` helper) sits at the attach point, inside the pylon's lower edge. From ahead, behind or
  below the quads are edge-on and nearly invisible, so the stores look detached, as in the original.
- Ported as is: the converted models carry the quads; `test_pylons.gd` checks the geometry under every wing station
  of the six models of the seven flyable jets.

### 2.3 Selection (`FUN_0053b8b0`)
Keys: ']' (event 0x3e) selects the next AA store, '[' (0x3c) the next AG store. **Shift+[ / Shift+] send the same
events (they also step forward).** Selection works only while nothing is being released or fired.

The cycle:
- It walks stations 0..9 by distinct name. It restarts after 9 or when the kind changes.
- It prefers a store with rounds left. The player may select an empty one when no station of that weapon has any.
- Tanks / pods are never selected. **The gun belongs to both cycles.** Chaff / flares belong to neither.
- In NAV with an AA missile already selected, ']' only enters the mode (no step). '[' does the same for a selected
  non-AA store.
- The MFD stores page station buttons (0x4c) select that station (with a button click).

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
- M (0x63) cycles NAV → AA → AG → NAV (`ctl+0x7c`) with SFX_BUTTON, then sets every MFD's page (docs/mfd.md §5).
- Changing to NAV leaves the EO mode on (`FUN_00449810` case 0 skips `FUN_0044e6e0`).
- N (0x62, p 0) goes to NAV.
- '[' / ']' / N play no button click.

### 2.4 Release (Space 0x40 / up 0x41)
Space works in HUD mode 1..8. With the gear handle down it works only with Safety off **and** the gun selected.
Weapon systems damage (flag 20) refuses it.

`FUN_00454270` then:
1. Refuses with `W+0xa0` (flags 20 / 21), while releasing, or with no rounds of the selected store.
2. Gun → the trigger (§3). Missiles 570–640 → one release, `FUN_004545e0`.
3. Picks the station that fires (`FUN_0053b680`): after a shot from the current station, the station of the same
   weapon with rounds left farthest from it (AIM-9: 0 → 8 → 0 …).
4. Releases from the store's slot[count−1] (else the pylon) through the attitude, at the jet's velocity.
5. Decrements the count (`FUN_0053c8b0`; skipped with Unlimited ammo) and updates drag / weight (§2.5).

### 2.5 Weight and drag (`FUN_00454010` from the FM init `FUN_005a8980`)
The sum runs over pylons 0..8 and counts **one store per station whatever the count**.
- Weight: the weight (pounds) of non-tank stores is summed into `S+0x424`, **the kg field, as is**.
- Drag (×1e-4): stations 0..3 → left `S+0x42c`, 5..8 → right `S+0x428`, station 4 half to each.

The flight model uses them (docs/flight-model.md): m = EmptyWeight + `S+0x424` + fuel, CD += left + right, β_cmd =
(rudder + 10·(right − left))·MaxBeta.

After each release (`FUN_004583a0`, `FUN_00458510`; skipped with Unlimited ammo), each only when the result stays ≥ 0:
- that side's drag −= drag (half at station 4);
- `S+0x424` = (`S+0x424`·2.2046 − weight lb)·0.45359.

Original bugs (kept by default):
- (a) One store per station: 3 MK-83 weigh as one; each release subtracts one, clamped at 0.
- (b) Pounds go into the kg field at the start, while the updates convert as if it held kg.
- (c) The tanks' weight never counts as stores weight (it becomes fuel, §2.6).

The Physics option **"Stores weight fix"** counts every store, in kg (the updates then stay consistent), and the tank
fuel in kg (§2.6).

### 2.6 Fuel tanks (stores whose name contains "LB", type 660)
- **Start**:
  1. `FUN_00454010` puts the tanks' bdb weight (one per station, e.g. "2700LB" = 2700) into `out[3]` and sets
     `W+0xc0`.
  2. `FUN_005a8980` sets the fuel ramp's maximum `S+0x448` = FuelWeight (kg) + `out[3]` (the pounds number), and the
     controller's fuel display to (FuelWeight + `out[3]`)·2.2046. `FUN_004a9100` calls it before the motion start.
  3. The start (`FUN_005a5820` @5a6145: `lea ecx,[S+0x430]`, pushes max, 0, 0) fills the fuel to that maximum.

  So the tanks **do** give fuel in the original, but their pounds count as kg. An F-16 with a 2700LB centre tank starts
  with 3175 + 2700 = 5875 kg (12 950 lb); the correct figure is 3175 + 1225 kg.
- **One pool**: the fuel is one ramp. The part above FuelWeight is the tanks' fuel, so the external fuel burns first.
  The MFD "Fuel : %5dLB", the Betty fuel warnings and the mass all use the total. The stores page's "int%d" is the
  bomb release interval (§9.1).
- **Weight**: the tank's fuel weighs as fuel. The data holds no empty-tank weight, so it never counts. The tank's drag
  counts until it is released.
- **Jettison** (Shift+C, event 0x48): with the gear handle down nothing happens. Otherwise:
  1. The first press (`FUN_00458760`, once, `W+0xb8`, only with the release permission `FUN_0045ee10`, §9.2) releases
     one store from every pylon whose name contains "LB": count −1 even with Unlimited ammo, a drag update, no weight
     update.
  2. The tank falls as a ballistic object (class 0x16, §9.5) aimed at its `_fireEndVec` (0, 500, 0) from the jet, on
     the terrain. It bursts there with power 0: the explosion only, SFX_WEAPON_EXPLODED / OST_SHELL.
  3. When the fuel is at or above FuelWeight (`FuelWeight·2.2046 ≤ fuel lb`), motion 0x18 (`FUN_005a2270`) sets the
     fuel and its maximum to FuelWeight: the tanks' remaining fuel is gone.
  4. Later presses drop the bombs (`FUN_00458d10`, §9.6).

  Tanks are never selectable, so the jettison is their only release.
- **Stores weight fix**: the tank fuel is added in kg (count × bdb weight × 0.45359), same pool and jettison rule.

## 3. The gun

The gun fires one pooled round every 0.2 s. Each round flies a straight line and hits anything within 25 m of it.

### 3.1 Trigger (Tab 0x42 / up 0x43, or Space with the gun)
With the gear handle down, Tab needs Safety off (`ctl+0x970`, the Shift+S cheat, default on).

Firing (`FUN_004579f0`):
1. Refused with flags 20 / 21 (`W+0xa0`), gun damage (flag 13, `W+0x9c`), or while firing.
2. `W+0xb0` = 1 (firing; it also shows the muzzle flash).
3. **The first round fires at once** (`FUN_00456d40`).
4. A timer then fires every **0.2 s of sim time** (`DAT_0082f4e8`). The scheduler catches up in long frames; the
   catch-up shots share the timestamp.
5. The gun sound loop starts (§3.6).

Quirk: if the first round fails (its pool round is still flying), firing stays on without a timer until the release.

Stop (`FUN_00457b40`): the trigger released, a weapon change, gun damage, or out of rounds (silently).

One shot (`FUN_00456d40`):
- no rounds → stop;
- the next pooled round (a ring of `_maxNumInAir` 20) is still flying → skip the shot, no round used;
- else aim, launch, count −1 (never with Unlimited ammo).

### 3.2 Aim (`FUN_00456ff0`, `FUN_00450450`)
The shot line d is the nose **rotated 1° up** about the right wing (v1.1, player only). P is the jet's origin (the
muzzle plays no part). The aim point A:
- HUD mode 4 (AG gun): A = P + (V + 1200·d)·t − (0, 0, 4.903·t²), t = `_limitDist / _limitVel` = 3.75 s.
- Any other mode: A = P + **2781**·d (v1.0 1854).

The gun fires in every mode, NAV included.

### 3.3 Candidates (`FUN_004577c0`)
The game builds at most one candidate list per 0.5 s (gate `FUN_004d4100`). With 0.2 s shots about every third round
gets a list; the others get none. The list holds at most 10 units:
1. the locked radar target, when within 2·|A − P|;
2. then every unit within 10·|A − P| other than the shooter (**friendlies included**).

Ours orders them nearest first (the original's spatial-query order is UNCERTAIN).

### 3.4 Flight (`FUN_005605c0`, `FUN_0047a491`, analytic)
The round flies at speed s = |V| + `_velocityJump` along u = (A − muzzle)/|A − muzzle| (A pulled to 30 km) and slows
at 10 m/s²:
p(t) = muzzle + u·(s·dt − 5·dt²) until t_end = (s − √(s² − 20·dist))/10, then A.

The path is a straight line: gravity and dispersion play no part. The hit radius is `_spiralAccel` 50 × **0.5** =
**25 m**, and **50 m with Easy aiming** (v1.1; this is the only Easy-aiming effect on the gun).

Every 0.1 s (`FUN_00560710`) the round detonates:
- at the round, when it is within 25 m of a candidate's origin (target size plays no part);
- at or below the terrain;
- at A in the air, at t_end.

The round moves ~145 m per check, so it can step over the sphere (original).

Weapon data Real sweeps the segment flown since the last check against the target's half-span (docs/real-weapons.md
§1.4).

### 3.5 Detonation (`FUN_004d6130`, `FUN_004d7c80`)
- Sphere hit: the blast (power 100, radius 50 for "20 MM" / DEFA) reaches the round's candidate list only.
- Ground or end: the blast reaches every unit around.
- Damage: docs/damage.md.
- Impact effect, on a hit (at the hit unit) or on the ground: a small fireball (0x10000000, 1.5, 1.2 s) and
  SFX_WEAPON_EXPLODED / OST_GUNBULLET (WpnMiss). Over water: the splash and ring (0x60000, scale 1, docs/damage.md
  §6.1) and SFX_SPLASH.
- A round that ends in the air shows nothing and plays no sound.

### 3.6 Look and sound
- Rounds: each pooled round is drawn as the bdb model 116 (`weapons\gun\gunsh`) along its line.
- Muzzle flash (`FUN_00411d90`, every frame while firing): two crossed quads at StationGun along the gun line, length
  (0.85 + 0.01·(rand % 31))·s, half-width 0.3·s, gunFire.tga, no z-write. Ours: s = 1 m, additive (scale and blend
  UNCERTAIN), hidden in the cockpit view with the jet model.
- Sound: one loop per trigger press, by gun name; single rounds make no sound.
  - "20 MM" → SFX_AIRCRAFT_FIRED_WEAPON / OST_GUNBULLET (Msl_gblt).
  - Else → SFX_ENTITY_FIRED_WEAPON / OST_GUNBULLET (MSL_GBLT_BRAIN — the Mirage / Kfir player hears it).

### 3.7 Gun HUD
The gun cross shows in every mode (docs/cockpit.md). The pipper is the 32×32 sprite of mfds.bmp (132,792)–(164,824),
colour key 0xffff00 (`FUN_00530040`).

**Mode 3 LCOS** (`FUN_0045f410`, the v1.0 code, without the +1°) works in feet. It runs every 0.05 s but integrates
with dt = 0.15 (quirk kept). Inputs: R = the locked range, else 1476.378 ft (450 m), at most 3148.8 ft; the filtered
pitch / heading rates w28 / w2c (int16 fixed point). The solution:
- tf = R / (3300 − (V + 1650)·R·0.00024667423), gd = π·tf²·16.087/R, D = 0.2 + 1.35·tf;
- x* = gd·cos θ·sin φ − tf·Q;
- y* = tf·P + (g − 1)·gd − ((3300·tf − R)·V·α/R)/(V + 3300) + 5.0617/R;
- x += dt·(x* − x)/D, y likewise.

The pipper is drawn at the gun cross + (x, y)·57.29578·12 px (truncated).

In modes 3 and 4 the pipper's centre is held inside the field: x in [left, right], y in [top, bottom − 2] (the sprite
corner clamped, `FUN_00530040`). The sprite itself is clipped to the screen only (`FUN_0052da80`).

With a radar lock (S+0xa20) the **range arc** shows:
- r = the lock range in NM (S+0x388, the live distance × 0.00053937, at least 0);
- drawn when r < 1.95 and r·π > 0.05236 (3°);
- a 2 px pen arc of radius 11 px about the pipper centre, from 12 o'clock clockwise by r·π (a full turn at 2 NM). The
  GDI `Arc` draws it counterclockwise from the end at r·π back to 12 o'clock.

Ours starts the rate filters from the attitude at mode entry (the original's first values are untraced; from 0 the
first heading step throws the pipper off for about a second).

**Mode 4** (`FUN_0045ef10`, new in v1.1): the pipper is the projection of the mode-4 aim point A.

## 4. Master mode keys (summary)
'[' / ']' / Shift+[ / Shift+] select, M cycles NAV / AA / AG, N → NAV, Space releases, Tab fires the gun, Shift+C
jettisons. Keys and commands: docs/controls.md (records 45, 54, 64–69, 72).

## 5. IR missiles (570 heat, 580 limited heat)

An IR missile locks the unit nearest the HUD centre that its seeker can track, then chases it on its own. The seeker
plays no part after launch.

### 5.1 Seeker (SRM HUD mode 1; `FUN_00461210` object, `FUN_00461290` update)
Cone and range R per generation of the selected store (`FUN_00462460`), NM = 1854 m:

| generation | cone | range R |
|------------|------|---------|
| 1          | 15°  | 6 NM    |
| 2          | 21°  | 8 NM    |
| 3          | 35°  | 10 NM   |
| 4          | 70°  | 15 NM   |

The cone is the gimbal limit of the radar-slaved and the helmet-slaved seeker (§5.4).
Every update reads the cone and R again, from the generation of the store that fires next (`FUN_00462460` is
vfunc +0x48 of the IR mode, the first call of `FUN_00461290`; `FUN_0053b680`). Generation 0 keeps the last values. So
']' from a Python 4 to a Python 3 shortens R from 15 NM to 10 NM at once.

**Search** (`FUN_00461680`, at most every 0.5 s): the seeker takes the unit whose screen point is nearest the **HUD
centre** within **6000 px²** (≈ 77 px) and that passes can-track.
- The screen point is in viewport 0, the 3D camera (`FUN_0045a790` → TgenAPI slot 0x38).
- The HUD centre is (cx, cy) = R+0x2768 / +0x276c (`FUN_004dc790` → `FUN_00520be0`); the boresight symbol plays no
  part.
- **Any side**: friendlies count too.

**Can-track** (`FUN_00461d10`):
- 580 only: within ±60° of the own heading. This is a bearing test; the code comment calls it the "tail".
- Range ≤ R.
- Beyond **R/2: only a target with its afterburner on**: a unit with a flight model (+0x34) whose stage
  `FUN_00594c00` (+0x28) is > 0. Ours: an AI jet's FM `afterburner` stage (`player_weapons.gd` `_units`).
- Weapon data Real replaces R and the R/2 rule with lock ranges by aspect and afterburner (docs/real-weapons.md §1.2).

**Visible** (`FUN_00461f10`), the first case that applies:
1. **With an A-A radar lock** (`FUN_004625f0`): the target within the generation cone of the nose.
2. **In the free-look (0x12) or padlock (0x16) view**: the helmet test of §5.4.
3. **Otherwise**: within 6° of the nose.

**Tone and lock** (every 0.05 s):
- Tones: seek SFX_IR_SEEK (Wpn_IRCHIRP), lock SFX_IR_LOCK (WPN_IRCHIRPON).
- Silent without rounds on the **selected station** (`FUN_0053bcd0`). Entering IR on an empty station chirps the seek
  tone once (`FUN_00461b00`); the next update stops it.
- Lock = a visible trackable target. There is no lock timer, and the lock drops at once.

**Symbols**:
- The seeker diamond (±7 px, `FUN_00536ff0`, S+0xe6c) eases 0.3 / 0.7 toward the target's screen point and snaps
  within 5 px. Without a target it returns to the HUD centre. It is held inside the symbology field along the line
  from the HUD centre (`FUN_0052db30`). It is drawn only with rounds on the selected station (+0xe7c, `FUN_0052ffb0`).
- The missile circle (`FUN_00537120`): r = 5·12 px (min 10) on the **HUD centre**. With a radar lock and a seeker
  target it shrinks inside the DLZ like the MRM's (vfunc +0x3c `FUN_00462c10`, §11.3). Here the IR object's +0x28 is
  the seeker's target and +0x2c (`FUN_00463330`) the radar's lock.
- Shoot cue: §11.3.

Ours: screen offsets are angles at 12 px/deg from the camera ray through the HUD centre. The camera's 686.2 px focal
length = 11.98 px/deg; tan and angle differ by < 1 % inside the 6° field.

### 5.2 Launch (`FUN_004545e0` → `FUN_00454b70`, q `FUN_00457f70`)
The launch needs HUD mode 1, 2 or 8. The target and launch quality q:
- Without Easy aiming: the seeker target inside the 6000 px² circle; q = (lock ? 1 : 0.1) × **0.8** (v1.1).
- With Easy aiming: any seeker target; q = 1.
- Always q ≥ 0.1.
- No target → the missile flies at the point `_fireEndVec` (0, 10000, 0) in body axes (10 km ahead).

Sounds: launch SFX_AIRCRAFT_FIRED_WEAPON / OST_HEATMISSILE (or OST_LIMITEDHEATMISSILE) = WPN_IRMIS_RLS; flight loop
SFX_OBJECT_SPECIFIC (UNCERTAIN: code 0x8337e4). The player may launch missiles at any rate.

### 5.3 Chase (`FUN_00563b70`, `FUN_00561ef0`, `FUN_005627e0`)
Setup:
- q is clamped to [0.1, 1]. Chase 2 (proportional) becomes chase 1 (dog) when q < 0.7.
- Gain A = `_spiralAccel`·q.
- Launch velocity = the jet's (≥ 5 m/s, else 100.1·nose).

Motion:
- Between updates: p = p0 + v0·dt + ½a·dt² (no gravity, no cap).
- Every 0.1 s the state is re-based and a += G·(a_abs − β·|v|·(G·û)).
- G = û until `_timeConstOrientation` (it flies straight). Then G = norm(dist·D − A·v⊥D), where D is the line of
  sight (dog) or the collision course (proportional: D = norm(u·√(S² − P²) + V_t⊥)).
- Terminal speed ≈ a_abs / β.

The flight ends (with a target, once `age ≥ tCO`) at the first of:
- within 1.5 m of the target;
- at / below the ground: the burst is at the target height when within √60 m horizontally and 15 m above it, else at
  ≥ ground − 1;
- overshoot (cos < −0.01): the burst moves to the closest point of the last 0.1 s segment;
- burn + 6 s (22 s for the AIM-9L).

The hit is deterministic (no random kill probability): the blast (AIM-9L power 400, radius 15) at the burst point
reaches every unit around. After launch the missile flies on its own: the seeker plays no part.

### 5.4 Helmet sight: DASH (off-boresight IR lock)
DASH (Elbit's Display And Sight Helmet) lets the IR seeker lock where the pilot looks. In the exe the helmet is two
things (it has no "helmet" string): the cockpit key `[HUD] Dash` (docs/cockpit.md "HUD dash repeater") and a
view-dependent branch of the seeker:
* **Seeker, `FUN_00461f10` @461fb0**: when the radar has no A-A lock and the current view (`DAT_00699304` camera
  slot +0x458 → +8) is **free look 0x12 or padlock 0x16**: A = the 3D camera's forward axis (`FUN_00582880`: the
  head yaw / pitch with the 5.5° look-down, docs/views.md §4.3), B = the jet's nose; **B·A ≥ cos(generation cone)**
  (`0x82f6e8`) and the target direction from the eye · A ≥ **cos 6°** (`0x82f6c8`), else not visible. It applies to
  every jet and every IR missile; only the generation cone differs (gen 1 15°: AIM-9D, Shafrir 2, AA-2,
  AA-6; gen 2 21°: AA-8; gen 3 35°: AIM-9L / M, Python 3; gen 4 70°: Python 4, AA-11).
* **Acquisition** is the unchanged search (§5.1): a unit within ≈ 77 px of the HUD centre on the screen. In those
  views the HUD centre moves with the panel (cx = 320 − pan).
  - `Dash 0` cockpit (Mirage, Kfir, F-4E): a turned head carries the circle off the screen with the HUD. The seeker
    can then only take a unit near the nose, which the camera-axis test rejects.
  - `Dash 1` cockpit (F-15, F-16, F-4 2000, Lavi, MiG-23, MiG-29): once the panel is panned ≥ 250 px aside or
    ≥ 200 px down (`FUN_00530b70`), the HUD becomes the helmet display at the fixed screen point (320, 220). The
    circle then sits near the middle of the view and the seeker takes what the pilot looks at.
* **Padlock (F3 / Shift+F3)** puts the target on the head line: the camera looks 5.5° below it (or max(·, 0.1·(|yaw|
  − 90°))), so the target is 4–5.5° from A (inside 6°) and ≈ 30–50 px above (320, 220) on the full-height viewport
  of a turned head (docs/cockpit.md "3D view"). With the head ≤ cone off the nose the seeker locks. The seeker's
  target comes from the screen search; the padlock only turns the head.
* **Symbols**: the helmet display's missile circle on (320, 220), the seeker diamond eased onto the target's screen
  point (held in the field), the DASH aircraft symbol and attitude bar (docs/cockpit.md). **Sounds** and **launch**
  are §5.1 / §5.2's.
* **Radar-slaved** (any view): the A-A lock's unit at once, visible within the generation cone of the **nose** (the
  first branch of `FUN_00461f10`).

## 6. HUD and MFD
**HUD weapon text** (`FUN_0052ef20` pass 3; left column at HUD centre − TxtOffX, rows 7 px apart from centre +
TxtOffY; row 2):
- "%1d %s %s" = the total of the selected store (same type and name), its name, and RDY / MAL. MAL shows with flags
  20 / 21, or 13 with the gun.
- "NAV" in HUD mode 0.
- Drawn on the glass, outside the symbology field's clip.

The whole text block (six rows) is in docs/cockpit.md "HUD symbology".

**Stores page** (`FUN_0052c740`):
- per pylon: count / name at the docs/mfd.md positions;
- MRM / SRM totals, gun rounds "%03d" at (68,85), fuel;
- the selected station boxed (gun: 36×10 at (48,82));
- the ripple quantity "%dQnt" at (1,94) and interval "int%d" right-aligned at (131,94) (state +0x374 / +0x378 =
  W+0xd4 / W+0xd8). OSBs 0xe / 0xf set quantity +1 / −1, 0x13 / 0x14 interval +10 / −10 (§9.1).

The quantity and interval strings appear on the stores page only; the HUD weapon line omits them.

## 7. Weapon data: Real (Extras)
Preferences > Extras > Weapon data = Real (default Original) overlays public numbers: docs/real-weapons.md. The
Arming screen's CURRENT LOAD and weights use the flight's numbers, so Real shows the real weights.

## 8. Function identities
- `FUN_004604c0` is the TV seeker / camera of weapon 0x27b (635, §12.3), not an LCOS solver. The gun pippers are
  `FUN_0045f410` (AA, mode 3) and `FUN_0045ef10` (AG, mode 4).
- `FUN_005611b0` / `FUN_00468470` (the ±`_debugParam016` clamp) are the bomb / shell ballistics (class 0x16). Nothing
  steers a gun round.
- The `_spiralAccel` ×0.5 of `FUN_005604a0` / `FUN_005605c0` is the hit sphere of the fixed weapons (gun round,
  rocket). The missiles use another rule (§5.3).
- The bdb Weapons parser is `FUN_00593ee0`, not `FUN_004c37c2`.
- The keys.trx labels of (110,27) Shift+S, (110,4) Shift+R and (110,26) Ctrl+W are wrong; their meanings (Safety
  toggle, reload stores, re-read Weapons.ibx) are in docs/controls.md §4.

## 9. Bombs and rockets (500, 510, 560, 650)
Built: `crates/iaf-avionics/src/bombs.rs` via `game/weapons/bombs.gd`, `player_weapons.gd`, HUD `hud.gd _draw_ag`;
tests test_bombs.gd, test_bomb_missions.gd.

- Types 500 / 510 / 560 / 650 share the release path ("bomb types", `FUN_00457bc0`). Rockets share it too, except the
  jettison.
- Master mode 1 (5 for 650).
- HUD mode 5 (6 for 650 with a FLIR pod: the FLIR page and camera start, with the same mode-5 symbols).
- The stores MFD page (§2.3).

### 9.1 Ripple quantity / interval (`FUN_004585f0`, events 0x4a / 0x4b → `FUN_004562a0` → `FUN_004562f0`)
A ripple releases `quantity` stores, `interval` metres apart on the ground, one per period.
- Defaults: quantity `W+0xd4` 2, interval `W+0xd8` 10, period `W+0xdc` 0.3 s (0x600eb0).
- Controls (`FUN_005219e0`): stores page OSB 0xe / 0xf send 0x4a with 1 / 0 (quantity +1 / −1); 0x13 / 0x14 send 0x4b
  (interval +10 / −10). Only these buttons change them; no key is bound.
- Clamps: quantity 1..14, interval 10..200, period = max(0.1, interval·0.001) (0x600f48, 0x600f0c). Quirk: once
  changed, the period is 0.1 s for any interval up to 100.
- "int" is both the spacing on the ground (m) and the period (ms).
- The values can change during a release (no check).
- The order of the stores: one per tick, from `FUN_0053b680`'s station (§2.4). 6 MK-82 singles on stations 1–3 /
  5–7 with quantity 2 go (1, 7), (2, 6), (3, 5) per press, the two stores of each press one period apart, the jet
  lopsided in between. Extras "Bomb release" Real changes this (§9.10).

### 9.2 Release (Space 0x40 / up 0x41)
- **Space** (`FUN_00454270(target, ai)`; the player passes (0, 0), the AI `FUN_00452680(T)` → (T, 1)):
  1. Refused with `W+0xa0`, outside HUD mode 1..8 (player), while releasing (`W+0xac`), or without rounds.
  2. `W+0xac` = 1.
  3. Bomb types, player: HUD mode 5 or 6 only (else `W+0xac` stays set until Space up).
  4. Without a running ripple timer (`W+0x288`): remaining `W+0xd0` = quantity; the mode-5 object updates once and
     freezes (`FUN_0045d130`: +0x3c); the timer `FUN_004cf270(cb 0x601020 / FUN_0045a680, start now, period W+0xdc)`
     starts. The first store goes on the next scheduler tick, then one per period.

  The AI uses `W+0xe4` / `W+0xe8` and period `W+0xf0`.
- **Space up** (`FUN_00456100`): the timer is killed, `W+0xd0` = `W+0xe4` = 0, and in HUD mode 5 / 6 the freeze clears
  (`FUN_0045d150(1)`). So the ripple runs only while Space is held.
- **One release** (`FUN_004545e0`, the timer callback):
  1. No rounds or `W+0xa0` → the timer is killed and the symbols blink (`FUN_0045d150(0)`).
  2. The station (`FUN_0053b680`, the farthest same weapon after a shot: §2.4). If its pool object is still flying
     (+0x48), wait for the next tick. A station's pool holds `count` objects when count ≤ 6, else `_maxNumInAir`: so
     bombs never wait, and rockets with 20 in the air do.
  3. `FUN_00454b70` sets the aim (§9.3).
  4. The release permission **`FUN_0045ee10`**: the entity's selector 0 (the load factor) ≥ 0 and |roll| ≤ 90°
     (0x82f63c = π/2). Else no release this tick.
  5. The **delayed release**: when the mode-5 pipper is off the HUD (+0x2c) and this is the first store
     (`W+0xd0 == W+0xd4`), release only once the time-to-go +0x30 ≤ **0.9 s** (`_DAT_0082f528`, set by `FUN_00453880`).
  6. `--W+0xd0`. At 0 the timer ends, the symbols blink and `W+0xac` clears.
  7. Force feedback "BombRelease" (not ported).
  8. The release point / velocity / count / drag / weight as §2.4.

  Sounds: SFX_AIRCRAFT_FIRED_WEAPON / OST_BOMB (WPN_BGBMB_RLS), OST_CLUSTERBOMB (WPN_SMLBMB_RLS), OST_ROCKET,
  OST_LASERBOMB (WPN_RDRMIS_RLS). A falling store loops SFX_OBJECT_SPECIFIC / its OST (WPN_BGMB_FLY, WPN_SMLBNB_FLY,
  WPN_RDRMIS_FLY).
- Any height works: there is no minimum release altitude and no arming / fuse time. A store bursts at
  the ground (or at its aim). The gear rule is Space's (§2.4: gear handle down → only the gun with Safety off).

### 9.3 The aim and the ripple line (`FUN_00454b70` cases 500 / 510 / 560 and 650 without a designation)
The centre point P:
- Player: the mode-5 object's target +0x18 when its pipper is off the HUD (+0x2c = 1), else its impact +0xc.
- AI with a target: P = T + V·t + ½A·t² (t = |T − own| / own speed). Without one: `FUN_0045ed10` (`FUN_0045e400`, the
  impact without the drag term).
- 650: with `ctl+0x960` (the FLIR designation, `FUN_00450430`) set, the guided path toward the designated point; else
  the same as a bomb.

The ripple line (`FUN_00457c20(P, remaining, quantity, interval)`): at the first store (remaining == quantity) the line
is frozen in `W+0xf4..`: aim[k] = P + (k − ⌊qty/2⌋)·interval·(sin h, cos h, 0), h the jet's heading, each on the
terrain. Store n aims at aim[qty − remaining].

**The radar's GMT (ground moving target) / MAP designation (radar.gd `designate`) plays no part**: the mode-5 update
and the aim ignore it. Only the MAP cross and the HUD's TD box read the designated point (docs/radar.md §8), so the
game has no CCRP.

### 9.4 The mode-5 HUD object (`FUN_0045d0a0`, update vtable +0x10 `FUN_0045d470` → `FUN_0045d1d0`)
This object predicts the impact point, draws the CCIP / delayed-release symbols and feeds the release cue.

Fields: +0xc impact I, +0x18 target T, +0x24 / +0x28 the pipper's screen point, +0x2c off the HUD, +0x30 time-to-go
(double), +0x38 the distance, +0x3c frozen, +0x40 blinking, +0x48 a time cap (1e7 for every type: the rockets'
`_limitDist / _limitVel` of `FUN_0045d4d0` is overwritten, dead store), +0x50 the extra speed (rockets: `_limitVel`
1000). To the cockpit state by `FUN_00445db0`: +0x620 off, +0x624 point, +0x638 time-to-go (above 1000 → 1000),
+0x62c frozen, +0x630 blinking.
- **Impact** (`FUN_0045e7f0`, v1.1):
  1. P = the jet's origin. V = its velocity − the selected store's bdb drag (0x73a, MK-82 23) as m/s along the nose
     (+ 1000 m/s along the nose for rockets).
  2. h = P.z − terrain(P); t = (vz + √(vz² + 19.612·h)) / 9.806 (`FUN_0045e330`); I = P + V·t − (0, 0, 4.903·t²)
     (`FUN_0045e3b0`).
  3. When the terrain at I is below I: once more with h = P.z − terrain(I), and I.z = min(I.z, terrain(I)).
  4. A terrain ray P → I (`FUN_0045ed40`):
     - in the cockpit views 1 / 5 / 0x12 / 0x16: the pick of the picture at I's screen point (TgenAPI slot 0x2c
       `0x404e90`: projection, then the screen pick slot 0x20). Ours: the first terrain on the line of sight from P
       toward I, 1 % steps then bisection;
     - in the other views: a march between P and I, both lifted 1.5 m (0x601420; slot 0x28 `0x404ae0`), from the lower
       end toward the higher one, in steps of clearance / 8 + clamp(length / 300, 80, 300) terrain units
       (1.2411389 m). The hit is the first sample more than 5 height units under the terrain; none above 4500 m
       (0x5fda90).
  5. On a hit H: t = the fall time to terrain(H), the impact = H. A second ray P → I(t), if it hits too, moves the
     impact to that hit, on the terrain.

  So a hill between the jet and the impact takes the pipper (`crates/iaf-avionics/src/bombs.rs` `terrain_ray` /
  `sight_ray`). The drag term puts the pipper short of the drag-free fall; the bomb's solver (§9.5) then pulls the bomb
  onto that point. Example, level release from 1000 m at 200 m/s: drag-free 2856 m ahead, the MK-82 prediction 2528 m.
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
- So the A-G modes are CCIP and a "delayed CCIP" (the target under the HUD-edge pipper, release on the 0.9 s cue),
  with the 12 px/deg 3-D projection of the cockpit view. Ours: the HUD rectangle is our HUD Control, and the ray
  through the clipped point comes from our camera (docs/deviations.md).

### 9.5 The falling store (500 / 510 / 660 → class 0x16, BallisticMotion 0x1c, ctor `FUN_00467ed0`, vtable 0x601b40)
- **Launch** (`FUN_004d6c10` → `FUN_00561b40` sets the aim; the launch variants `FUN_00560c20` / `FUN_00560e80` /
  `FUN_00560f60` then run the solver `FUN_005611b0` on the release state): the horizontal velocity is turned toward the
  aim (speed kept: the cross-track error is fully corrected); t = (vz + √(vz² + 19.612·(p.z − A.z))) / 9.806, the end
  time +0x68 = now + t (none: now); along-track a = 2·(dist − vh·t)/t², clamped ±`_debugParam016` (15 m/s²) when
  the owner is the player in single player; acc = (û·a, −9.806). The aim above the arc → t = a = 0.
- **Motion** (`FUN_00468470`, `FUN_004684d0`): p = p0 + v0·dt + ½acc·dt², no drag, attitude from the velocity. v1.0
  `FUN_00467910` capped dt at the impact (a sure hit); v1.1 leaves dt uncapped.
- **Impact check** (`FUN_00561750`, at launch then every 0.5 s: 0x60ce20):
  - The state is re-based (p0, v0 = now; same curve).
  - 510 opens `_velocityJump` 1000 m above the terrain (+0x2c, `FUN_00463ec0`). This is a visual flag, and nothing
    draws it.
  - Within `_debugParam010` 800 m of the aim: the pre-explosion event 0x4e (`FUN_004012c0`, broadcast once; no
    detonation receiver found).
  - Within 2 m of the aim (0x60cddc) or at / below terrain + 1 (0x60ce18): the detonation `FUN_004d6130` **at the
    check point**.

  The check point can be up to ~0.5·|vz| under the ground (a level release from 1000 m: up to 70 m). There the blast's
  z term (docs/damage.md §4.1) weakens or cancels the damage (MK-82 radius 50), so a direct hit often does nothing
  (test_bomb_missions: 3 of 7 targets needed a second MK-83). **Original bug, kept by default.** Physics "Bombs burst
  at the ground" moves the burst to where the last step met the terrain (docs/deviations.md).
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

- **Wind** (Better physics `wind`, ours; flight-model.md §10). The store drifts by Didion's lag rule
  (`iaf_avionics::air::drift`): it lags t − x/s₀ behind its drag-free self, and the wind times that lag is its
  drift. For the falling store the along-track deceleration a gives a constant drift acceleration −a / |v_h| · wind.
  The bombing computer knows the wind: the HUD impact (`predict_impact`) moves downwind by that drift, and the
  release (`Bomb::launch`) aims the still-air solution upwind, so the store lands on the aim and its fall bends
  downwind (test `the_wind_drifts_the_bomb_and_ccip_follows`). The AI's drops use the same solver. `bombs.gd`
  `wind` carries it (set by `terrain_view.gd` `apply_wind`, zero with the switch off).

### 9.6 Bombs jettison (Shift+C after the tanks, `FUN_00458d10`, once, `W+0xbc`)
It works only with the release permission (§9.2), and Unlimited ammo is off during the loop.
- Stations 0..8 with a bomb type 500 / 510 / 650 (rockets 560 stay) release every round.
- Each falls toward the `_fireEndVec` (0, 500, 0) point from the jet, dropped to the terrain.
- Each release updates drag / weight and decrements the count.
- They fall and burst like released bombs: they are armed, and the blast hits what is there.

### 9.7 Rockets (560)
- Release: like the bombs (§9.2, the ripple included), aimed at the ripple point of the mode-5 impact. That prediction
  adds `_limitVel` 1000 m/s along the nose.
- Motion: the fixed-weapon motion 0x18 of the gun rounds (§3.4) with weapons.ibx 000560. Speed |V| + `_velocityJump`
  100 along the line to the aim, accelerating at `_absAcceleration` 100 m/s² up to `_limitVel` 1000 (ours: the gun
  formula's accelerating branch, UNCERTAIN).
- End: the record has no `_spiralAccel`, so no hit sphere. The rocket ends at the terrain or at its aim, and the blast
  goes off there (ZUNNI 500 / 50).
- `_maxNumInAir` 20 per pod.
- UNCERTAIN: the setter writes the ballistic layout into a rocket's fixed-motion state (aim (0, 6000, 100)); ours aims
  at the ripple point.
- Pods: one "Rocket box" per rocket pylon at the attach point (`FUN_0053c1f0`: object 0x753d =
  `weapons\Lau61\Lau61_m`; `[Weapons] RocketBoxScale` default 4.0, absent from the shipped iaf.ibx). Ours keeps the
  box when empty (UNCERTAIN).

### 9.8 Laser bombs (650)
A laser bomb always flies the guided motion (§12.2, weapons.ibx 000650). The ripple releases it like a bomb (§9.2).

The aim (`FUN_00454b70` case 0x28a), recomputed per store:
- With the laser on (`ctl+0x960`, `FUN_00450430`): the designation (`FUN_00450410` → `FUN_0045db70`: the FLIR camera's
  centre point, or the unit it started on, at its position now). It is the aim when it lies within 60° of the line to
  the bomb's point P (cos 60°, 0x82f4e0) and at most 2 m above the terrain (0x600f08).
- Else: the ripple aim (§9.3, `FUN_00457c20`).
- Jettisoned: the jettison point.

Test: `tests/godot/test_laser_bombs.gd` (all jets incl. the F-35I: designated hit, laser off, a designation behind
refused).

### 9.9 AI bomb runs (built: `game/ai/combat.gd` `release` / `_ripple_tick`)
1. **Trigger**: the AI calls `FUN_00440440` (gate `FUN_004d4100`) from `FUN_005cd0d0` (impact within the tolerance or
   1000 m, 0x612fc0), `FUN_005d8590` (miss < 400 m, 600 m for kinds 0xd2 / 0xdc, angle < 15°, state 9 → 0xb) or
   `FUN_005d9290`.
2. **Release** `FUN_00454270(T, 1)`: bombs (500 / 510 / 560 / 650) start the ripple unless one runs (`W+0xac`,
   `W+0x288`). `W+0xe4` = the quantity `W+0xe8`, and a timer runs every `W+0xf0` s (cb 0x601020 → `FUN_004545e0` with
   p4 = 1). The AI path skips the release permission `FUN_0045ee10` and the delayed release. `W+0xe4` − 1 per store;
   at 0 the timer ends and `W+0xac` clears; with no rounds it ends.
3. **Quantity / interval / period** come from the weapon-change actions 350 / 360 / 380 (`FUN_00452710` →
   `FUN_004562f0` on the action's bdb 0x82 / 0x96), with the player's clamps: quantity 1..14, interval 10..200,
   period max(0.1, interval·0.001). default6_1.bdb: 380 = 2 bombs, 20 m (period 0.1 s); 350 / 360 = 1. The
   handler's constructor (`FUN_00453ab0`) sets only the player's `W+0xd4..0xdc`, so before a 350 / 360 / 380 ours
   ripples 1 store (UNCERTAIN).
4. **Aim** (§9.3, AI): the target led by its velocity over |T − own| / own speed (ours omits the ½A·t² term), spread
   on the ripple line `FUN_00457c20` (`W+0xec` m) frozen at the first store.
5. An emptied station hands over to another with the same weapon.

**Rockets (560) and laser bombs (650)** ripple the same way (their `FUN_00454270` case), each store through the
player's release (`player_weapons.release_store`):
- `FUN_00454b70` aims a rocket as a bomb (case 0x230 shares the bombs' branch: the led ripple point), and it flies the
  fixed-weapon motion.
- A laser bomb (case 0x28a, AI path) aims at the **target's position now, without lead**, on the ripple line, and flies
  the guided motion to that point. The laser test `FUN_00450430` is the player's, so an AI jet has no designator.
- Rocket hits are credited to the releasing jet. The AI's rockets share the player's rocket pool (ours).

Test: `test_ai_ground_attack.gd` (ZUNNI rockets and an AS-14 from the Su-24's ripple reach the target).

### 9.10 Real release (Extras "Bomb release: Real", ours)
Preferences > Extras > **Bomb release** = Real (Settings `bomb_release`, default Original) makes the player's bombs
(500, 510, 650) leave the jet the way a real stores management system releases them. Rockets (560) and the AI's
releases stay original.

**The real rules found:**
- **F-16 SMS.** The release option is SGL or PAIR. SGL releases one store per release signal; PAIR releases stores
  symmetrically in pairs, two at a time[^bms34], from both opposite stations: 4 and 6, or 3 and 7[^dcs-f16].
- **What the quantity counts (F-16).** RP is the number of release pulses sent when the pilot presses the weapon
  release button: RP 1 releases one bomb or one pair, RP 4 releases four bombs or four pairs (a "ripple
  release")[^dcs-f16]. The page shows the count left of SGL / PAIR beside OSB 8[^bms34].
- **Interval (F-16).** The pilot enters the impact spacing (0–999 ft); the aircraft computes the time between
  pulses from it[^dcs-f16]. The shortest interval is 60 ms on a MAU-12 pylon or a TER-9/A, 200 ms on a SUU-20[^bms34].
- **Station sequence (F-16).** A former crew chief writes that with SGL and RP 1 the bombs come off one at a time
  starting on the left wing, and that SGL / PAIR puts one off each wing per pickle[^f16net]; another poster writes
  that the SMS drops symmetrically when like stores are on both wings[^f16net]. Outboard or inboard first is open.
- **TER order.** A TER-9/A fires its centre station, then left, then right[^marvin]. Ours keeps the original slot
  order on a rack (the bottom store first, §2.2).
- **F-4E AWRU.** The quantity knob counts munitions, not pulses: Single-Manual drops one per press,
  Single-Ripple 2–18 drop at the interval while the button is held, Pairs-Manual drops one store from each station
  per press, Salvo repeats that at the interval. Single releases go left-right-left. The interval is 0.05–1 s
  (×10 with the INTRVL switch)[^hb-awru].
- **F-15, Lavi, Kfir, Mirage, F-35I, Kurnass 2000:** no public source found (open).

**What ours does with Real** (`crates/iaf-avionics/src/stores.rs` `Stores::real_pulse`, `release.rs`
`Ripple::pulses`, wired in `game/weapons/player_weapons.gd` `_ripple_tick`):
- **PAIRS / SGL.** Stores page OSB 7 (bottom, second from the left) toggles PAIRS and SGL, PAIRS at the start. The
  page then shows "1 PAIR" / "1 SGL" (the quantity and the mode) in the quantity's place ("%dQnt"); the art is unchanged.
- **The quantity counts release pulses** (F-16 rule, used for every jet but the F-4s, inferred). Each pulse is one
  store (SGL) or one pair (PAIRS). It starts at RP 1, so one press in PAIRS drops one pair; 6 MK-82s go in one
  press with quantity 3. With the switch off the original's default 2 stays. The F-4E and the Kurnass 2000 (inferred
  from the F-4E) keep the AWRU rule: PAIRS drops one pair per press, the quantity counting stores in SGL.
- **One pulse in PAIRS:** the outboard-most symmetric pair (stations i and 8 − i) that both hold the selected
  weapon, one store from each at the same instant. Both counts drop before one push to the flight model, so Better
  physics "Asymmetric stores" sees no moment between them.
- **One pulse in SGL**, or in PAIRS with no full pair left: after a store, its mirror station on the other wing when
  that holds the weapon; else the left station of the outboard-most full pair; else the station whose store leaves
  the lateral moment nearest 0 (an odd store left, the centreline last). Inferred from the sources above.
- **Interval:** the original's period and ripple line (§9.1, §9.3) with one line point per pulse; both stores of a
  pair share the point.
- The probe load (6 MK-82 singles) at RP 1: Real PAIRS releases (1, 7), (2, 6), (3, 5), one pair per press, each
  pair in one step, the moment about 0 after each (the model's attach points are mirrored to about 1 cm). Real SGL
  releases 1, 7, 2, 6, 3, 5, one per press.

Tests: `stores.rs` / `release.rs` unit tests (pairs, alternating singles, a TER pair and an odd store, AWRU
pulses); `test_bomb_release.gd` (mission 231: Original 1 7 2 6 3 5 one per tick, two per press; Real PAIRS (1, 7)
(2, 6) (3, 5), one pair per press; Real SGL alternating, one per press).

## 10. Chaff and flares
Each press drops one decoy. At the release the game rolls once per missile launched at the jet: a success sends that
missile after the decoy.

**Built**: keys, release, counters, the decoy flight and look, the AI jets' releases (actions 310 / 320, the same path,
one pool per jet: `player_weapons.release_decoy`) and the decoy rule (below).
- **Keys** (`FUN_0044a240`): Insert = event 0x44 chaff, Delete = 0x45 flare.
  - Refused with the gear handle down (even with Safety off) or weapon systems damage (flag 20).
  - Then `FUN_004545e0(0x21c / 0x226, 0, 0)`.
  - One press = one decoy: there is no repeat, program or busy timer. The AI uses the same call with p4 = 1 and its
    brain busy flag.
- **Release**:
  - Station 10 (chaff, bdb 33) / 11 (flares, bdb 34). The counts come from the type's loadout slots 10 / 11 (F-16 90
    / 60), shown 1:1 (never ×2 / ×4), and drop even with Unlimited ammo.
  - Count 0 → nothing happens (no message, no sound).
  - The next object of the station's ring pool (`_maxNumInAir` 15) must be free (its decoy ended, below). So at most
    15 decoys per type are in the air. A refused press is silent.
  - Release point: the station (StationCha / StationFla) through the attitude.
- **Flight** (fixed-weapon class, `FUN_004d7630` → `FUN_005605c0` → `FUN_0047a1e2`, the gun round's model):
  - Aim point A = release point + attitude·`_fireEndVec` (0, −200, −10): 200 m aft, 10 m below (composition
    UNCERTAIN).
  - Speed |V| + `_velocityJump` 10 along the line to A, slowing at 50 m/s² (`_limitVel` 5): ≈ 0.85 s at 250 m/s.
  - `_spiralAccel` 0: no hit sphere.
  - **End** (`FUN_004d7690` @4d7797..4d77de): the motion's time left (vtable +0x80 = `FUN_00467760`: +0x78 (the time
    at A) − now) is capped at **4.0 s** (`_DAT_00605120`, types 0x21c / 0x226 only). So a decoy ends **when it
    reaches A**, at most 4 s after the release: ≈ 0.85 s at 250 m/s; the full 4 s only below |V| ≈ 130 m/s, where the
    5 m/s crawl never reaches A. Past A the decoy stays still (`FUN_00466fc0` past +0x78 moves nothing).
  - **Terrain cut** (at the launch): `FUN_004d7690` (vfunc +0xc of the fixed-weapon class, vtable 0x605128) cuts A at
    the terrain for every fixed weapon other than the gun (type 565) whose candidate count +0x130 is 0. (`FUN_004d75c0`
    stores the list's count there; the single-target launch `FUN_004d7630` stores target ≠ 0.) That covers the
    decoys always, rockets with an empty list (§9.7) and an AI rocket without a target. The first terrain point on the
    segment from the weapon (+0x58) to A (`FUN_004020d0`; return 0 = hit) becomes A, and the flight restarts to it
    (`FUN_005604a0`). So a decoy released low ends on the ground.
  - Ours: `gun.rs` `launch_aim` / `terrain_cut` (steps of 2 % of the distance, at least 25 m, then 8 halvings; the
    original's sampling is untraced).
- **Sounds**: SFX_AIRCRAFT_FIRED_WEAPON / OST_CHAFF, OST_FLARE (WPN_RDRMIS_RLS). The end sound SFX_WEAPON_EXPLODED
  (WpnMiss) is in the table, but its call site is UNCERTAIN, so ours does not play it.
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
  - `MissileFlareDistance` ([SFX], default 1.0) is a missile setting: how far behind a missile (types 0x230,
    0x23a..0x27b) its trail starts; missFLR is also the missile motor glow at the trail's head ("renderTrailFlare",
    `FUN_00415a60`).

  **Port** (`decoy_fx.gd`): the same sprites (iaf-convert, 4× Lanczos: converted/objects/missflr.png, chaff.png),
  sizes, timing and motion; the flare additive, its smoke = damage_effects.gd white puffs; the chaff pieces one
  shader-driven MultiMesh; emission at a fixed 30 Hz, where the original emits per frame (docs/deviations.md).
- **Panel counters** (`FUN_0052eab0`): "%03d" of stations 10 / 11 at `[CHAFF]` / `[FLARE]` OffX / OffY, Arial h10
  w5, pale yellow RGB(255, 255, 179) (docs/cockpit.md).
- **Decoy rule** (`FUN_00454b70`, chaff case 0x21c @455775 / flares case 0x226 @455968; decided once at the release):
  1. Candidates: the releasing jet's RWR list of missiles launched at it (`FUN_00452160`), in list order (by launch
     distance). Every aircraft has a controller and so an RWR. A missile is added at its launch unless RWR damage
     flag 14 is set, so with RWR damage decoys fool nothing.
  2. For each missile: skip one already chasing a decoy. Chaff fools only 600 / 610 / 630; flares only 570 / 580 /
     620.
  3. r = rand()/32767 against p:
     - chaff p = (g > 4.0 ? 0.3 : 0.1) (0x600f18, 0x600f28, 0x600f0c);
     - flare p = afterburner on ? 0 : (g > 4.0 ? 0.5 : 0.33) (0x600f04, 0x600f44).
  4. r > p **ends the whole scan** (quirk: one resisting missile protects the later ones).
  5. Else the missile chases the decoy (`FUN_004d83c0` → `FUN_005622e0`, q 1.0).

  Only the kind, g and afterburner matter: range, aspect, generation, AI level and Real data play no part. The bearing
  gates (doubles 6302.5 / 4010.7 / 5156.6 = 110° / 70° / 90° × 57.3) compare a bearing in radians, so they are never
  taken (dead code). When the decoy ends (`FUN_004d8160`) the RWR entry is dropped; what the missile does then is
  UNCERTAIN.
- **ECM** (event 0x46, LIGHT006, ctl+0x1b8; refused with ECM damage flag 1):
  - Switching on (`FUN_004582f0`) needs an ECM fitted: W+0xcc or a station named "ECM". F-16 / Lavi (types 100 / 140)
    have it built in.
  - It jams, once, each missile of type 600 / 610 in the RWR list that is still flying and chasing its target (not a
    decoy), with rand < 0.6 (0x600f68): its motion +0x148 = 1 (guidance off, UNCERTAIN). SAMs are unaffected.
  - Switching off (light on): the light only (and a network message).
  - Ours: `player_weapons.gd` `ecm_key` (J). The gate on +0x98 in `FUN_004582f0` is unknown (UNCERTAIN) and not
    ported. The AI sensors see a jamming player at any range, and an AI jet's homing launch at it loses q
    (docs/ai.md §13).

## 11. Homing weapons and the radar missiles (600, 610)

### 11.1 One homing motion (class 0x18)
Every homing weapon flies the chase motion of §5.3: 570 / 580 IR, 590 HARM, 600 / 610 radar, 620 / 630 SAMs and
**635 Maverick**. The other guided class, 640 / 650, flies the guided motion (§12.2). The code is
`crates/iaf-avionics/src/missile.rs` via `missile.gd`; the player and the AI launch through the same
`launch_homing`.

Additions over §5.3, all in `FUN_005627e0` except where noted:
- **Release drop** (@563358): while age < `_timeRelease` (+0xb0, 0.3 s for the radar missiles) the motor is off;
  the weapon only accelerates by `_absReleaseAcceleration` (+0x9c, 30 m/s²) along +0xd4, set at the start
  (`FUN_00561ef0`) from the launcher's attitude (taken as the body's down axis: UNCERTAIN which matrix row).
- **Guidance off** (+0x148 = 1; `FUN_00458130` → `FUN_004d8420`, ECM `FUN_004582f0`): steering stops, and the motor
  still pushes along the velocity. The overshoot end then keeps the weapon's own point.
- **Retarget** (`FUN_005622e0`, from a decoy's `FUN_004d83c0`): a new target key; q, chase law and gain stay.
- **Time left** (vfunc +0x80, `FUN_00468db0`): burn − age (the end time stays 1e8 for `_endType` 2 while it flies).
Launch, flight and explosion sounds use the weapon's OST (570 OST_HEATMISSILE, 580 OST_LIMITEDHEATMISSILE, 590
OST_HARM, 600 OST_RADARMISSILE, 610 OST_SEMIRADARMISSILE, 635 OST_MAVRICK). A missile launched at the player enters
its RWR (`FUN_004d8130` → `FUN_0044e160`) and leaves it at its end (`FUN_004d8160`).

### 11.2 DLZ (vfunc +0x74, `FUN_005624f0`)
The DLZ gives the maximum and minimum range at which the selected store can reach the target. It uses the distance
flown in time t from speed s:

flown(s, t) = s·t + ½·a·(1 − 4β)·t² (`FUN_005627b0`, the motion's a = `_absAcceleration`, β = `_spiralAccelBeta`).
burn = `_timeAcceleration` + `_timeConstVel` + `_timeDecceleration` (Real: its own burn). Without a target: [max, min]
= [flown(|V|, burn), flown(|V|, 1 s)]. With one: max = flown(|V| − the target's speed away from the launcher, burn −
2 s) (0x60ce78), min = flown(|V|, `_timeConstOrientation` + 2 s) (0x60ce80); both 0 when the target is 90° or more off
the nose (acos ≥ π/2, 0x84162c) or min > max. Example, AMRAAM generation 3 (a 120, β 0.1, burn 35 s, tCO 3 s)
head-on at 250 m/s against a 250 m/s target: **max 55.7 km, min 2.15 km**. The cockpit keeps the selected store's DLZ
at the radar's target in S+0x348 (max) / S+0x350 (min) every frame while the radar has a lock / TWS selection or the
HARM sensor a target (`FUN_00456520`), else the last values.
With Weapon data Real the maximum comes from the distance the missile really flies instead (ours,
docs/real-weapons.md §2); the Original data keeps this rule.

### 11.3 MRM HUD sight (mode 2, `FUN_00460ea0`; HARM mode 8 `FUN_00460a90`; base `FUN_00462ab0`, `crates/iaf-avionics/src/sight.rs`)
- **Target** (vfunc +0x28): the radar's A-A lock or TWS selection (mode 8: the HARM sensor's selected target);
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
  min ≤ dist ≤ max: a triangle under the target box (apex 2h − 6 px below its centre, base 2h, ±3 px). **Mode 1**
  (`FUN_00461290` → `FUN_00446610`): the seeker's lock (0x82f6ec, set by the tone `FUN_00461bf0`, off without rounds),
  rounds on the selected station (`FUN_00456cd0`) and min ≤ dist ≤ max of the statics the mode-1 circle writes
  (0x82f6a8 max, 0x82f6b0 min, 0x82f6f0 dist): only with a radar lock and a seeker target, kept otherwise (0 at start:
  the cue then follows the lock alone). No in-circle and no radar A-A test. The cue is drawn under the target box
  (`FUN_00537330`, only with a radar lock or designated point), so it shows with a radar lock. Ours keeps the statics
  per flight (`player_weapons.gd` `_srm_dlz`; the original's last a whole session). `hud.rs` `srm_shoot_cue`.
- **Break X** (S+0x1024, `FUN_0044fe30`; docs/cockpit.md): with a radar lock outside HUD modes 3 / 4, the target
  closer than the DLZ min of the store about to fire (570–610, refreshed once a second) draws an X on the HUD centre
  and hides the circle and the caret.
- **"%2d SEC"** (HUD row 5 in modes 1, 2, 8; S+0x380): the last launched weapon's time left (`FUN_0053bec0` → its
  motion's vfunc +0x80, clamped by `FUN_004d6ac0`: below 0 → 0, above 300 → 60).
- **STT envelope ticks** (MFD, `FUN_00534160`): three black ticks at y 39 / 65 / 91 and the DLZ max / min as ticks
  x 121..117 at y = 122 − ⌊v·112/(R·1853)⌋ while inside the scale (docs/mfd.md).
- Ours: the screen offsets come from the camera ray through the HUD centre, built from the camera's projection
  matrix (Godot's `project_ray_normal` ignores the cockpit camera's frustum offset, ≈ 5°).

### 11.4 Semi-active (610)
A semi-active missile (610) needs the launcher's radar to keep its lock.
- At launch the 610 makes the radar lock its target (`FUN_004ad880(2)`, STT) and joins W+0x274.
- When the radar drops or changes its track (`FUN_00458130`), the guidance of every 610 in the list turns off and the
  list empties. Triggers: Q, R, S, Return / Shift+Return, a blip click, Backspace with a lock, STT lost, any mode
  change leaving STT.
- Radar damage skips this call (original quirk, kept): the Sparrow keeps guiding after the radar dies.
- The 600 (active) guides on its own after launch.

### 11.5 HARM (590: AGM88, SHRIKE)
The same launch (`FUN_00454b70` case 0x24e, HUD mode 8) and the same homing motion (weapons.ibx 590: dog chase,
a 120, β 0.08, burn 23 s, tCO 2 s, `_fireEndVec` 7 km ahead). Selecting a 590 puts HUD mode 8, the HARM sensor on
(`FUN_0045c2b0`) and the HARM page (10) up (`FUN_00449810`), keeping the page it replaced (`ctl+0x92c`). Leaving
HUD mode 8 turns the sensor off (`FUN_0045c2f0`) and puts that page back (docs/mfd.md §5).

The HARM HUD object (`FUN_00460a90`, vtable 0x601560)
differs from the MRM's only in vfunc +0x10 (`FUN_00460ac0`: no circle; "In Range" = the selected emitter nearer than
the selected store's DLZ max, the seeker diamond at its screen point) and +0x28 / +0x2c (`FUN_00460e10` /
`FUN_00460e40`: the HARM sensor's selected target and whether it has one).

- **Launch**: the missile takes the HARM page's selected emitter when its screen point is within 240 px of the HUD
  centre (Easy aiming: anywhere); q = vfunc +0x38 × 0.8. Without one the missile flies at its `_fireEndVec` point.
- **Flight**: the HARM chases the unit like any homing weapon, whether the emitter stays on or not (the flight code
  has no type test). Its blast (AGM88 power 5000, radius 20; SHRIKE 5000 / 50) hits what is around.
- **Targets**: the HARM sensor's own scan (the RWR plays no part): the radar classes (9, 10, 11 and class 8 units
  named "RADAR…") within 20 NM in a ±15° cone, emitting or silent, friendlies too (docs/mfd.md "HARM (10)").
  Ctrl+Return steps to the next one.
- Extras "HARM targets: Real" (ours) lists the RWR's active emitters as the targets, plus the hostile scanned sites
  without a brain (they never lock, so the RWR never lists them; ours counts them as searching, inferred). Mission
  322's HARM target, the "dummy SA-2" radar (brain −1), is one. 28 missions have "RADAR…" sites with brain −1 (in
  most, all their radar sites), so the rule matters beyond the lessons.

### 11.6 Validation
`tests/godot/test_radar_missiles.gd`: the DLZ (AMRAAM example, receding target, target behind, no target), the circle,
lead and in-circle q; per jet in mission 231 (F-16, Lavi, F-35I AMRAAM; F-15, F-4E, Kurnass 2000 Sparrows) radar lock
of a MiG 8 km ahead, the MRM HUD (circle inside the DLZ, lead point, shoot cue, DLZ ticks), the launch, the hit, and
Backspace dropping the Sparrow's guidance but not the AMRAAM's; Real AMRAAM 157 kg, Mach 4, 70 km.
`tests/godot/test_harm.gd`: per jet (the seven Jet list jets and the F-35I) in mission 231, two radar-class units 15
and 25 km ahead: '[' selects the AGM88 (master 4, HUD mode 8, the HARM page), the scan lists both and preselects the
nearer, Ctrl+Return steps to the other and wraps back, the HUD diamond and In Range, the launch at it and the kill; a
SHRIKE with nothing listed flies at its end point; with Extras "HARM targets: Real" only the locking unit is listed,
both after the other locks too (selection kept), and Ctrl+Return steps that list; mission 322 with "HARM targets:
Real": the SA-2 radar stays off the RWR, the HARM page lists it and the HARM goes at it. Rust: `harm.rs` (the class filter, range, cone, line of sight, own
jammer, kept selection, the step).

## 12. TV weapons (635, 640) and the guided motion (640, 650)

TV weapons fly to the point the pilot holds in the TV camera. The camera rides the weapon after launch.

### 12.1 Classes
- The **Maverick 635** flies the homing motion (class 0x18, §11.1).
- The **TV missile 640** (AGM-62, POPEYE, GBU15) and the **laser bomb 650** fly the **guided motion** (class 0x19;
  motion vtable 0x601f70; the TV / laser variant 0x601ed0 differs only in the destructor; ctor `FUN_00469aa0`, size
  0x130).

The weapon class (vtable 0x605178):
- configures the motion with the launch data's point (+0x14 `FUN_004d7ed0`; it ignores the target unit);
- sets a new aim with +0x2c (`FUN_00469f00`, ignored in mode 2);
- reports the status with +0x30 (`FUN_004d8030`: (mode ≠ 0) + 2 = 2 TRA / 3 TER).

Explosion class 0x19: the falling store's (flash + streamers, no trail). Code: `crates/iaf-avionics/src/guided.rs` via
`game/weapons/guided.gd`.

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
  The camera sits inside the weapon's model. The original culls back faces, so the inside never shows (inferred);
  the detailed stores (Models: Detailed) are double-sided, and the Maverick's seeker dome filled the TV picture
  (fixed 2026-10-28). Ours puts the flying TV weapon's model on render layer `EoSensor.SELF_LAYER` (20), which the
  EO camera's cull mask leaves out.
- **Which weapon** (`FUN_00450280` sets mcp+0xc to the store that fires next, `FUN_0053b680`; the launch, store
  event 5 in `FUN_004d6930`, sets its +0x48 = 1, event 6 at its end back to 0): the camera rides the store it was
  started on. Only master mode 6 and the radar step (0x26 / 0x27 with a Maverick) restart it, so in the original a
  second launch without a re-selection leaves the camera on the jet (UNCERTAIN: the station's store ring,
  `FUN_004d8760`, may hand back the same object). Ours rides every launched TV weapon.
- **Status** (`FUN_00460940`): 0 unless the TV weapon (the flying one, else the store) is 635 / 640 / 650; 1 RDY before
  launch and for a launched Maverick, else the weapon's 2 TRA / 3 TER; 0 when the selected store has no rounds left and
  (nothing flies or a Maverick flies).
- **TV page "%3d"** (111, 110): the TV weapon's time left through `FUN_004d6ac0` (< 0 → 0, > 300 → 60); before a launch
  0 (UNCERTAIN: the original reads the store's motion then).
- **HUD mode 7** (`FUN_0052fa10` case 7): the seeker diamond (`FUN_00536ff0`) on the EO centre point's projection while
  the status ≠ 0, held inside the field along the line from the HUD centre. No "SEC" row in mode 7.

### 12.4 HUD range scale
`FUN_005397a0`, drawn in HUD modes 1, 2 (via `FUN_0052ffb0` / `FUN_0052ff30`) and 7 while the radar has a lock
(S+0xa20); s = the HUD scale: X = HUD x + (RightBorder R+0x2228 − 4)·s, Y = param_5 − 50·s (param_5 taken as the HUD
centre y, UNCERTAIN), H = 66·s, k = H / (the radar range R+0x2748 NM × 1853). Pen polyline (X−2, Y) → (X, Y) → (X, Y+H)
→ (X−3, Y+H). DLZ bracket: ym = clamp(H − ⌊S+0x350·k⌋, 0, H), yM likewise from S+0x348; lines (X+s, Y+ym) → (X−2s,
Y+ym) → (X−2s, Y+yM) → (X+1+s, Y+yM). Range caret at c = H − ⌊H·S+0x388 (lock range NM) / R+0x2748⌋: (X−3s−3, Y+c−2)
→ (X−3s−1, Y+c) → (X−3s−4, Y+c+3). Text (sprite font, right-aligned, `FUN_00525920`): "%3dK" (0x65d6b4) of ⌊2·S+0x3a0⌋
(the closure ×2) ending at (X−3s−4, Y+c−2); "%3d" (0x65d754) of the range scale ending at (X, Y−8). Ours: X is the
HUD centre + (RightBorder − 4)·s (the exe adds 0x140, the 640-wide screen's centre); the rows in `hud.rs`
`range_scale` (the bracket held on the scale, the caret not), drawn by `hud.gd` `_draw_range_scale` (original HUD
only; the Real HUD has its own DLZ).

### 12.5 Validation
`tests/godot/test_tv_weapons.gd`: the guided DLZ formula, the start in TRA, the terminal TER, the burst snapped to the
aim; per jet (the seven Jet list jets and the F-35I) in mission 231 with an AGM-62 on station 0 and an AGM-65 on
station 8: '[' gives master 6, HUD mode 7 and the TV page; the camera on a ground unit 8 km ahead: RDY, the HUD diamond,
the DLZ; the launch: TRA, the time left, the camera riding the missile; the hit; NO SOURCE with no rounds left; the
Maverick at the camera's point and its hit. `tests/godot/test_maverick_mfd.gd` (Models: Detailed): two Mavericks; the
camera rides the first in every update until the hit, with the page on RDY, the picture shown and the weapon's model
on the EO self layer; then the camera is back on the jet; the last one launched gives NO SOURCE.

## 13. The modern weapons (ours)

Seven weapons the 1998 game does not have: the AIM-9X, Python 5, GBU-31, GBU-31(V)3, GBU-32, GBU-38 and GBU-39. They are
ours: new records built from public data whatever Weapon data says (values and sources: docs/real-weapons.md §1.6).
- **The modern jets** always list theirs: the F-16I Sufa (Extras "F-16 version" = Sufa, `Settings.sufa(100)`,
  docs/f16i.md) all seven, the F-35I (docs/f35i.md §3) the AIM-9X, GBU-31, GBU-32 and GBU-39.
- **Extras "Weapons"** (`Settings.modern_weapons`): on Original (the default) every other jet's Arming list is the
  original's. On Modern a jet also lists each weapon a public source shows it carrying (docs/real-weapons.md §1.7):

  | jet | weapons with Weapons on Modern |
  |---|---|
  | F-16D Barak | AIM-9X, Python 5, GBU-31, GBU-38, GBU-39 |
  | F-15 Baz | AIM-9X, GBU-31 |
  | F-4E, Kurnass 2000, Kfir, Lavi, Mirage, MiG-23, MiG-29 | none |

- The AI never gets them.

- **Records** (`game/weapons/modern_weapons.gd`, ids 1001–1007, added to every weapon database by `weapon_db.gd`): each
  copies an original record for its blast, drag and model and overrides the rest. A record built on a bomb with less
  explosive (GBU-31(V)3, GBU-39) scales the base's power by its fill over the Mk 84's 429 kg and the radius by the
  cube root of that (inferred). Stations as numbered 1–9 on the Arming screen:

  | record | type | built on (blast) | model (Original / Detailed) | Sufa | Barak | F-15 | F-35I | count |
  |---|---|---|---|---|---|---|---|---|
  | `AIM-9X` | 570, gen. 4 | AIM-9M | AIM-9 / FlightGear AIM-9X | 1–3, 7–9 | 1–3, 7–9 | 1, 9 (two each) | 1, 9 | 1 |
  | `PYTH-5` | 570, gen. 4 | PYTH-4 | Python 4 / ours (aircraft-models.md §5.6) | 1–3, 7–9 | 1–3, 7–9 | – | – | 1 |
  | `GBU-31` | 650 + GPS | MK-84 | MK-84L / FlightGear GBU-31 | 3, 4, 6, 7 | 3, 4, 6, 7 | 2, 5, 8 | 2, 3, 7, 8 | 1 |
  | `GBU-31V3` (BLU-109) | 650 + GPS | MK-84 × 250 / 429 | MK-84L / FlightGear GBU-31, slimmer (the BLU-109's 370 mm) | 3, 4, 6, 7 | – | – | – | 1 |
  | `GBU-32` | 650 + GPS | MK-83 | MK-83L / FlightGear GBU-31 at the GBU-32's length | 3, 4, 6, 7 | – | – | 2, 3, 7, 8 | 1 |
  | `GBU-38` | 650 + GPS | MK-82 | MK-82L / FlightGear GBU-54 (the laser JDAM's look) | 3, 4, 6, 7 | 3, 4, 6, 7 | – | – | 1 |
  | `GBU-39` | 650 + GPS | MK-84 × 16 / 429 | MK-82 at 0.8 scale / ours, on its BRU-61/A rack (aircraft-models.md §5.6) | 3, 4, 6, 7 | 3, 7 | – | 3, 7 (bays) | 4 (one rack) |

- **Arming**: `mission_weapons.gd` lists them after the bdb's weapons and adds their load items (`ModernWeapons.loads`)
  to the jet's. A jet picked on the Jet list takes the modern items of the jet flown, with the mission jet's original
  items (docs/front-end.md §15). Their icons are ours (`game/extra/weapons/arm/`, renders of the detailed stores by
  `tools/stores/icons.gd`); the Python 5 shows the install's Python 4 icon. A GPS bomb takes the bomb rack layout
  (§2.2), so four GBU-39s sit on one station.
- **On every jet**: the guidance, the release and the HUD cues below are the same on every jet that
  lists a weapon. Without a helmet sight (the F-4E, Kfir and Mirage cockpits,
  §5.4) an AIM-9X would lock within its cone of the nose only through a radar lock, else within 6° of the nose; none
  of those jets lists one.

### 13.1 AIM-9X and Python 5

Listed only with Weapon data on Real (`modern_weapons.gd` `REAL_ONLY`, decided 2026-10-29): with Original the
Arming lists keep the 1998 IR missiles, also on the Sufa and the F-35I. Both are IR missiles (type 570): the seeker, the tone, the launch and the chase of §5 apply, with these changes:
- **Seeker cone** 90° (AIM-9X) / 100° (Python 5) instead of the generation's 70°: the helmet (§5.4) and a radar lock
  slave the seeker that far off the nose. The lock ranges are the Real ones of the record (`real_*`), used with either
  Weapon data.
- **Agility** (`_offBoresight`, `missile.rs` `ChaseMotion::off_boresight`): the motor's acceleration is 600 m/s² and
  the missile steers after 0.05 s (the original's IR missiles: 100–150 m/s², 1–2 s straight). The original ends a
  flight when the target falls behind the missile's beam (the overshoot, §5.3); these missiles end that way only after
  the target has been ahead of them once, so a missile fired at a target beside or behind the wing line turns to it.
  The AIM-9X's turn is held to 60 g.
- **Launch zone** (`missile.rs` `ChaseMotion::dlz`): both ends from the distance the missile really flies
  (`travelled`, as Weapon data Real), with either Weapon data. The original's `flown`, s·t + ½·a·(1 − 4β)·t², goes
  negative for β > ¼: with these missiles' agility it gave a minimum range of −1.78 km and, with Weapon data Original,
  no zone at all (fixed 2026-10-29). The min stays the original's rule, the distance flown in tCO + 2 s.
- **LOAL** (`sight.rs` `Seeker::loal`): launched without a seeker lock, the missile flies at a point 10 km along the
  cued line, the helmet's line of sight in the free-look and padlock views, else the nose. Each frame it takes the
  unit nearest the line to that point within its cone that its lock rule accepts (any side, as the original's
  search), then chases it.
- **Helmet cues** (Real HUD, real-hud.md "DASH helmet"): the DASH (F-16, F-15) and the F-35I's head set draw the
  seeker diamond on its target or on the aiming cross, the seeker limit beyond the cone, SHOOT, and LOAL while a
  missile launched without a lock searches (`hobs_cue()` in `player_weapons.gd`).

### 13.2 GPS bombs (JDAM, GBU-39)

A GPS bomb has no seeker and never follows a laser: it flies to the coordinates the jet hands it at its release
(`crates/iaf-avionics/src/gps.rs`, `IafGpsBomb`). The jet takes those coordinates in one of two modes, as the real F-16
does[^dcs-jdam][^bms-jdam]; the F-35I's are inferred to work the same.
- **Mode** per GPS weapon (`player_weapons.gd` `gps_modes`, by weapon name): PRE by default. Key **K** switches the
  selected GPS bomb between PRE and VIS (docs/controls.md "Own keys"); a subtitle shows the new mode.
- **PRE (pre-planned)**: each station's target is set before the flight on the briefing TSD (docs/front-end.md §8.2):
  a unit, a waypoint of the flight or a map point, stored as its coordinates (`Settings.gps_targets`, {flight:
  {station: [x, y, label]}}, cleared when a mission loads). The bombs of a rack (the GBU-39's four on one station) can
  each have their own target, the real SDB being targeted bomb by bomb (inferred): stored under
  `Vector2i(station, bomb)`, bomb 0 being the first to leave in the stores' release order (the last slot first,
  `player_weapons.gd` `next_bomb`). A bomb without its own takes its station's (`gps.rs` `rack_targets`); a station
  without one takes the route's target waypoint (action 5, `gps.rs` `default_target`), else it has none. Key
  **Shift+K** steps the next bomb's target (`gps.rs` `pre_targets`, `pre_pick`): the bomb's own first, then the other
  bombs' and stations' and the route's steerpoints, each point once, round again; a bomb without its own target starts
  on none. A subtitle shows "PRE 2/5". The step goes back to the own targets when a release ends. The heights come
  from the terrain under the points.
- **VIS (visual / target of opportunity)**: the point designated in flight, its coordinates taken at the release: the
  targeting pod's point with the laser on (in any direction: there is no seeker cone; the bomb does not follow the
  laser spot), when it lies on the ground; else the radar's designated point, the HUD's TD box (MAP / GMT
  designation, docs/radar.md §8).
- **Aim** (`release.rs` `gps_aim`), per store: the mode's point; without one (PRE with no target, VIS with no
  designation) the bomb's own aim: the CCIP impact or the delayed-CCIP target (§9.3).
- **Pages** (ours): selecting a GPS bomb opens the stores page as a falling bomb, never the FLIR (it needs no pod;
  the original's laser-bomb rule, page 6 and the FLIR on with a pod aboard, would apply by its record's type 650).
  For VIS with the pod, open the FLIR page yourself.
- **Release**: the ripple of §9.2. The first bomb goes at once: a GPS bomb skips the 0.9 s delayed-release wait. With
  Bomb release Real (§9.10) the two bombs of a pair leave together, each with its own coordinates.
- **Flight** (an energy model, inferred): the bomb's energy per kg, g·height + ½·speed², drains by g / LD per metre
  flown over the ground, LD being the kit's glide ratio. Its speed is what that energy leaves at its height, at most
  the kit's dive speed (300 m/s). It flies straight at the aim while faster than its slowest speed (150 m/s); at the
  slowest it glides at 1 : LD toward the aim and lands short. Its path turns toward the wanted direction at 3 g
  (inferred). It bursts where its path crosses the aim's height (or the ground), with the falling store's explosion
  (§9.5). The real kits' error (5 m CEP for a JDAM with GPS) is not modelled: the bomb lands on its aim.
- **Reach**: from height h above the aim at speed s, LD · (h + (s² − 150²) / 2g) over the ground, whatever the path.
  JDAM: LD 1.6, about 24 km from 40,000 ft at Mach 0.9, 8 km from 3,000 m at 250 m/s. GBU-39: LD 7.6, about 110 km
  from 40,000 ft.

### 13.3 The launch acceptability region (LAR) and the HUD cues

There is no single release point: the bomb may go anywhere inside its LAR[^dcs-jdam]. In HUD modes 5 / 6 with a GPS
bomb selected (`gps.rs` `Kit::lar`; the rules are ours, inferred from the energy model):
- **Rmax**: 0.9 × the reach (the margin is inferred), less the arc of the turn toward an aim off the track at 3 g.
- **Rmin**: the bomb turns down at 3 g on a circle of radius r = s² / 3g below its path; an aim inside it cannot be
  met. Rmin = √(r² − (h − r)²), 0 from h ≥ 2r up (3,000 m at 250 m/s: about 1.9 km).
- **In range**: Rmin ≤ the ground distance ≤ Rmax.
- **TMR**: the time to Rmax at the speed closing on the aim, while outside it and closing.
- **Original-style HUD** (`hud.gd` `_draw_gps`), with an aim from PRE or VIS: a ±7 px diamond on the point (held at the
  HUD edge along the line from the centre, as the TV / HARM diamond) and a steering line to it from the flight path
  marker; a dot inside the diamond while in range. Row 5 `IN RNG` while in range (instead of the bomb time-to-go); row
  3 the range to the point, `R %2.1f` NM, when no radar lock fills it. The CCIP symbols are not drawn then. Without
  an aim the CCIP symbols of §9.4 stay and the bomb goes to their aim.
- **Real HUD** (docs/real-hud.md "GPS bombs"): the F-16's JDAM symbology on the F-16, the F-15 and the F-35I's helmet:
  the TD box on the aim, the azimuth steering line, the LAR staple with the range caret, `TMR m:ss` counting down, then
  `IN RNG`; PRE or VIS in the weapon window. The jets that carry no GPS bomb draw none.
- **Time to impact (TTI)**, after the release: the player's last released GPS bomb still in flight shows `TTI m:ss`,
  its time to impact rounded up to whole seconds, until it bursts (`gps.rs` `GpsBomb::time_to_impact`: a copy of the
  bomb flown on by the same energy and turn rules until its path crosses the aim's height; `player_weapons.gd`
  `gps_tti`). It shows in every HUD mode, so the pilot can follow the bomb from the cockpit. The real F-16 shows the
  released weapon's time to impact in a HUD window (secondary[^dcs-tti]). With several bombs in flight the countdown
  is the last released one's: the bomb the pilot just let go, the countdown he expects (with a pair the bombs leave
  together and land within a second of each other). When it bursts, the countdown passes to the next bomb still in
  flight. AI jets' bombs show none. Where it shows:
  - original-style HUD (`hud.gd`): a fourth row under the right text column (TxtOffY + 21 px), the original's three
    rows unmoved;
  - Real HUD (docs/real-hud.md "GPS bombs"): the time's row of the F-16's right data column, in place of the time to
    the steerpoint; the F-15's and the F-35I helmet's time rows the same (inferred).
- Open: the impact-angle setting and the shorter in-zone bar it brings, and the GBU-39's attack azimuth with its
  second LAR (LAR2)[^bms-jdam]: no setting for them is built.
- Open: with Models Detailed the GBU-31(V)3 is the GBU-31's model made slimmer to the BLU-109's 370 mm
  (aircraft-models.md §5.6). The real bomb also has a narrower ogive nose and the BLU-109's yellow band (photo: IDF
  Spokesperson's Unit, Commons "F-16I (IAF).jpg"); with Models Original it shows the MK-84L.

### 13.4 Validation

- Rust: `gps.rs` (a bomb inside the LAR lands on a point 30° off the track; outside it falls short; the reach from
  40,000 ft), `missile.rs` `off_boresight_missile_turns_to_a_target_behind_the_beam` (100° off the nose: the original
  rule ends the flight, the off-boresight one hits), `sight.rs` `loal_takes_the_unit_nearest_the_cued_axis`,
  `release.rs` `gps_aim_pre_or_pod_then_td_then_ccip`; `gps.rs` `lar_min_range_is_the_turn_circle` (inside Rmin
  the bomb overflies, just past it hits), `time_to_max_range_counts_down_then_in_range`, `time_to_impact_matches_the_flight_and_counts_down` (the TTI at
  the release within 1 s of the flight, 10 s later 10 s less, 0 after the burst),
  `pre_targets_own_first_each_once` (the list, the steps, the default target waypoint); `real_hud`
  `gps_cues_on_the_gps_jets` (F-16, F-15, F-35: TMR, IN RNG, PRE / VIS, the steering line, no CCIP pipper),
  `tti_replaces_the_time_row_on_the_gps_jets` (`TTI 0:42` in place of the steerpoint's time; the F-35I also looking
  aside).
- `tests/godot/test_modern_weapons.gd`: the Arming list of every Jet list jet, the Sufa and the F-35I with Weapons on
  Original and on Modern (the table above; the F-35I's default GBU-31 in each bay); mission 231, the F-15 3000 m up:
  the padlock view turns the head onto a MiG 70° off the nose, the AIM-9X locks it, launches and kills it; a GBU-31
  in VIS at a radar-designated ground unit 6 km ahead is in range (out of range at four times the distance), flies to
  the point and destroys the unit; the cockpit's `gps_tti` at the release is within 1 s of the flight time, 2 s later
  2 s less, and gone after the burst. PRE: on the briefing TSD a click on station 5's row of the GPS panel, then on the
  map, stores that point; in flight a unit stands there 50° off the nose with the radar designating elsewhere: 20 km
  out out of range with a TMR, 6 km out IN RNG; the bomb flies to the briefing's point and destroys the unit. With
  Bomb release Real a pair leaves at once, each bomb to its own station's target.

## UNCERTAIN
Open points:
- the candidate order of the spatial query;
- the receiver of event 0x4e (pre-explosion);
- the bomb time-to-go speed (selector 6);
- the rockets' accelerating motion;
- the rocket box when empty;
- the hit effects look; the tracer look;
- the muzzle flash scale / blend / cockpit visibility;
- the missile flight loop sound and explosion look;
- `FUN_0045ee10`'s selector 0 (taken as the load factor);
- the snap views' camera type for the seeker's helmet branch (§5.4);
- what a missile aims at when its target is gone (`FUN_0045a180`, taken as the origin);
- the HUD text font;
- the store-selected box placement;
- the release drop's direction (§11.1) and the MRM caret's sign (§11.3).

[^bms34]: Falcon BMS, *TO 1F-16CMAM-34-1-1 BMS* (the BMS reproduction of the F-16 -34 weapons manual), Change 4.38,
    §4.2.7.6.6–§4.2.7.6.9, pp. 513–514: <https://cdn.falcon-bms.com/docs/4.38/TO%201F-16CMAM-34-1-1%20BMS.pdf>
[^dcs-f16]: Eagle Dynamics, *DCS: F-16C Viper Early Access Guide*, "Unguided bombs", steps 5–7, pp. 621–622:
    <https://www.digitalcombatsimulator.com/en/downloads/documentation/dcs-viper_early_access_manual_en/>
[^f16net]: F-16.net forum, "LGBs on TER: Bomb release?", posts of 15 and 24 March 2004:
    <https://www.f-16.net/forum/viewtopic.php?p=9407>
[^marvin]: Marvin Engineering, "TER-9/A Triple Ejector Rack": <https://marvineng.com/product/ter-9a-triple-ejector-rack/>
[^hb-awru]: Heatblur Simulations, *DCS: F-4E Phantom II manual*, "AWRU": <https://f4.manuals.heatblur.se/systems/weapon_systems/awru.html>
[^dcs-jdam]: DCS forum, "JDAM help" (2022), secondary (a simulator's users): the pre-planned / visual modes, the right
    side's time to max range then `IN RNG`, release anywhere while the caret sits inside the LAR's long bar:
    <https://forum.dcs.world/topic/291870-jadam-help/>; the attached F-16 JDAM card:
    <https://forum.dcs.world/applications/core/interface/file/attachment.php?id=114047>
[^dcs-tti]: DCS forum, "CBU-105 HUD symbology question" (2022), secondary (a simulator's users): the F-16's HUD
    window for the JDAM, JSOW, WCMD and Paveway III shows the time to impact after the release:
    <https://forum.dcs.world/topic/304597-cbu-105-hud-symbology-question>
[^bms-jdam]: Falcon BMS forum, manual errata (pages 497–500), secondary: LAR2 with an impact or attack azimuth set, its
    tick the range that still lets the bomb follow the azimuth: <https://forum.falcon-bms.com/post/390232>; the range
    cue as "that scale / bracket on the right side of the HUD":
    <https://forum.falcon-bms.com/topic/25722/disappearing-and-appearing-bombing-range-cue>
