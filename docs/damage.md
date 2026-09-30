# Damage and destruction

How the original applies damage to a unit, when the unit is hit / destroyed, what the player sees and hears,
and how it feeds the mission's win / lose rules. Generic for every unit class and every aircraft. Addresses are
in `iafjets.exe` (Ghidra C in `assets/ghidra/iafjets.c`; functions missing there were decompiled at their
address). Port: `game/mission/damage_model.gd` (rules), `mission_runtime.gd` (unit status, events, roles),
`player_damage.gd` (the player's systems), `damage_effects.gd` (explosions, smoke, debris),
`terrain_view.gd` (host: models, the player's jet, collisions). Tests: `tests/godot/test_damage.gd`.

## 1. Runtime objects

| object | where | fields |
|---|---|---|
| Unit status (`MStatus`, MStatus.cpp) | entity+0x1c | +0x0c **state**: 1 alive, 3 fatally hit ("going down"), 4 destroyed, 5 exploded; +0x10 **damage** fraction 0..1; +0x14 control mode (docs/mission-runtime.md §1); +0x18 role; +0x20 kill counter; +0x28 **requested level** (kept between calls); +0x2c the key of the last hitting weapon; +0x48 the smoke timer |
| Damage object | entity+0x10 (ctor `FUN_004635f0`) | +0 entity, +4 **strength** (hit points), +8 **shield** flag |
| Collider | entity+0x18 (`FUN_0043b250`) | group, mask, radius² (§7) |
| Visual | entity+4 | [5] normal, [6] damaged, [7] destroyed, [8] cockpit-exterior model; +8 display 1..4 (§2.2) |

## 2. Per-unit data (bdb Objects)

### 2.1 Strength, size, shield
- **Strength** = bdb Objects **`0x56e`** (type record +0x28, `FUN_0058add0`; set by the spawner `FUN_004b7586`
  @4b75a7); when `0x56e` is 0 the class init's **10.0** stays (`FUN_00598bc0`, `FUN_005996d0`).
- **Size** R (entity+8 → +0x4c) = **0.5 · `0x564`** (the spawn radius, type record +0x30, `FUN_004b6d17`); a radius
  ≤ 0 becomes 5.0 (R = 2.5). Fire sensors (class 0x12) always use 5.0. Only the blast formula uses R (§4.1).
- **Shield** starts off; trigger ops 11 / 12 set / clear it (docs/mission-runtime.md §4). A shielded unit takes no
  damage, any damage it had is cleared (`FUN_00583f70`), and it ignores collisions.
- `0x55a` (7000 / 6000 / 12000 on some jets) and `0x550` are not read by the damage code (UNCERTAIN meaning).

| class `0x5aa` | units | strength | R | examples (strength / `0x564`) |
|---|---|---|---|---|
| 28 controlled aircraft | 23 | 100–100000 | 2.5 (MiG-29 7.5) | f16 300, F15 300, mig29 300/15, mig21 150, mirage 250, F4inst (instructor) 100000 |
| 2 helicopter | 4 | 100–200 | 2.5 | blackhawk 200, mi24 100 |
| 3 aircraft | 6 | 300–500 | 2.5 | 707 400, il76 350, c-130 300 |
| 5 armed vehicle | 8 | 50–300 | 2.5 | t72 200, mercava 300, ArmedBMP 50 |
| 6 vehicle | 9 | 100–300 | 2.5 | scud 300, jeep 100 |
| 8 radar SAM | 13 | 100–300 | 2.5 | sa6launcher 100, RADARsa5a 300 |
| 9 IR SAM / 10 gun dish | 1 / 1 | 200 / 100 | 2.5 | RADARsa13, zsu-53 |
| 11 ground radar | 8 | 150–3000 | 2.5 | p40 200, Anttena2 3000 |
| 12 building | 63 | 500–5 000 000 | 2.5–200000 | civilhouse 10000, factory1 100000, RUNWAY1 5M / 400000, Damesek 200000 / 2000 |
| 13 target building | 18 | 1000–3 000 000 | 2.5–2000 | tower 22000, bridge1 10000 / 2000, newBridge 1000 / 50, RWdavid 3M / 4000 |
| 14 tree | 22 | 0–3 000 000 | 2.5–50000 | Crater 3M / 20, burned plane 500 |
| 15 / 16 boats | 1 / 2 | 300–1000 | 2.5–40 | satil 1000, osa 1000 / 80 |
| 18 fire sensor | 2 | 1000–1500 | 2.5 | sensor 1000, Counter16 1500 |

`FUN_0058add0` also forces two types by name: "Parachute" → class 4 / type 500, "Crater" → class 0x1f / type 0xe1.

### 2.2 Damaged and destroyed models (`FUN_004b7330`, `FUN_004a8150`)
- Classes 1, 2, 3, 4, 8, 9, 0xf, 0x10, 0x1c and the default: damaged model = the normal one (no change);
  destroyed model = an empty dummy, so the unit **vanishes** when it explodes (state 5).
- Buildings (classes 0xc, 0xd, 0x1d): the models are made in code by `FUN_0053c8d0` → `FUN_0041f950`
  "createBurnedCopy": each vertex, with probability p, moves by (rand%200 − 100) · max extent · 1e-4 per axis
  and turns dark grey (diffuse 0xFF141414). Damaged (state 3): p = 0.25. Destroyed (state 5): p = 0.5, **only for
  types 400 and 410**; other building types vanish.
- Classes 0x11, 0x12 (fire sensors), 0x1b are never drawn.
- Display: state 1 → [5], state 3 → [6], state 5 → [7] (state 4 changes nothing). The player's own jet in the cockpit
  views (1, 0x12, 0x16, 5) shows [8] = `0x546`, the `*_BC.X` model: **the jet's exterior as seen from its own
  cockpit** (texture `bcf16.bmp` = seat back), set only on the flyable jets and MiG-23 / MiG-29. docs/formats/x.md's
  "damaged / burnt" guess for `_bc` is wrong.
- No damaged or destroyed meshes exist in the data; the converter exports every Present model already.
- **Port:** `terrain_view.gd` `_entity_fatally_hit` / `_entity_final` / `_burned_copy` (vertex colours on duplicated
  materials); hidden classes are not spawned.

## 3. Unit state machine

### 3.1 Setting a level (`FUN_004a8280(damage, level, key)`, `FUN_004a8530`)
1. State 5 → nothing.
2. Single player: with a level 1..5 given, store it as the request (+0x28) and store `damage` (+0x10) if 0 ≤ d ≤ 1.
   Without a level (−1): d ≥ **1.0** → request 5; d ≥ **0.8** (0x63b20c) → request 3; else only stored. The request
   persists between calls.
3. Transition by the request: **3** from state 1 → state 3, `FUN_004a7880`. **4** from 1 or 3 → state 4, `FUN_004a7a00`.
   **5** from 1 or 3 → state 5, `FUN_004a7ba0`.
4. Still alive (state 1) → the alive-hit reaction `FUN_004a93f0` (§5, §6.3).
5. `FUN_004a9600`: after a kill, radio calls: with a known killer `FUN_0054a110(killer, victim)` 5 s later (kill
   calls); an aircraft (class 0x1c) with no killer, `FUN_0054bf50` 2.5 s later ("… is down"). **Not ported** (radio).

Who sets levels: the hit handler (§4), trigger op 5 Explode (level 5), the flight model's crash (`FUN_005b87d0` →
level 5 at a failed landing check, water, rough ground), collisions (§7), the destruction motion (§3.3) and weapons
(`FUN_004d4a40`: a weapon with +0x100 == 2 forces its target to 5 unless it is a shielded player, UNCERTAIN meaning).
**Level 4** only comes from a request of 4, which no damage path produces; state 4 is practically unused.

### 3.2 Transitions
- **1 → 3 `FUN_004a7880`:** the **hit event** (slot 0, sensor on; docs/mission-runtime.md §2); control mode 0
  (`FUN_004a8600(0)`: a mission-controlled unit's scenario is killed, a brain stops); the damaged model; the
  **destruction motion** (§3.3) unless it already runs. For the player: `WINGMAN_EJECT_EJECT` ("Eject! Eject!"),
  the outside view 0x10 on the jet, canopy and pilot drawn.
- **→ 4 `FUN_004a7a00` / → 5 `FUN_004a7ba0`:** the **destroy event** (slot 1, sensor on) and killScenario; control
  mode 0; for 5 the kill counter +0x20 and, for an aircraft killed by the player's side, the killer's kill count;
  the view 0x10 when it is the player; then the final status.
- **Final `FUN_004a7e30`:** the explosion at the unit's position (`FUN_0059b3b0`, §6); the destroyed model; the
  unit's sounds stop (`FUN_004c3ae0`); its smoke stops (`FUN_004d18e0`); the brain ends; the role accounting
  `FUN_00597730` (docs/mission-runtime.md §5.1). For the player, unless every player is dead, game event 0x7f
  (FlyTSD) 6.5 s later (0x82d750; the in-flight TSD is not built).

### 3.3 The destruction motion (motion 0x14, DestructionMotion.cpp)
Created by `FUN_00464f89` at 1 → 3 (`FUN_00463db3(0x14)`, vtable 0x5fe658); it replaces the unit's motion — for the
player the flight model is frozen (`FUN_005a3700`) and the jet no longer answers the controls.
- Mover kind (`FUN_004652f3`): 1 = classes 5, 6, 8–11; **2 = 3, 0x1c** (fixed wing); **3 = 1, 2** (helicopters);
  4 = boats 0xf, 0x10; 5 = 0x16–0x1a; 6 = 7; 7 = the rest.
- Init `FUN_004966fe`: s = (U − 0.5)·2 (U = rand/32767). Kinds 1, 4, 6: velocity 0, T = 0.5 + 0.5·U. Kinds 2, 3:
  v0 = the current velocity (kind 3: vz clamped ±10); h = z + 10; if h > 0 (or over water for 3 / 4) kind 2 has
  T = 1e8 and kind 3 T = (vz + √(vz² + 19.612·h)) / 9.806; else T = 0.1. Other kinds: T = 0.1, v0 kept.
- Position p = p0 + v0·τ + ½·a·τ² with a_z = **−39.224 (4 g) for fixed wing**, 0 for boats, −9.806 else; no drag;
  z ≥ terrain where the terrain is above 0.1 m.
- Attitude, fixed wing: roll = φ0 + s·180°/s·τ; the nose goes to −(90° − 5°) (FlightModel/pitchEpsilon) at 18°/s
  (s = −1 when −85° < θ0 < 90°; otherwise s > 0 snaps it to −95°). **Heading = 0** (the output is written only on
  the helicopter path: an original bug, kept; `DamageModel.FALL_KEEP_HEADING` = true keeps the heading instead —
  to decide with the user). Helicopters: pitch = θ0 + s·ω·τ, ω = (n·2π − s·θ0)/T, n ∈ {0,1,2}; roll levels
  linearly; heading turns at s·U·π rad/s.
- End (`FUN_00496162`, **every 0.5 s**, kinds 2 and 3 only): past T → state 5; at **≤ 2 m above the ground** → the
  wreck is snapped to the terrain, its smoke trail stops, explosion, state 5; the first tick higher up starts the
  smoke trail (type 2, §6.3). Ground units, boats and buildings get the motion but no end check: they stay at
  state 3 where they are until more damage.
- `FUN_0046a7c0` also spawns effect 0x18 at the hit point (UNCERTAIN what it looks like; not ported).
- **Port:** `DamageModel.fall_start` / `fall_at`; the runtime moves units, `terrain_view.mission_player_fall` the
  jet. The original makes an explosion at impact and another in the final status; ours makes one (UNCERTAIN).

## 4. Hits

### 4.1 The blast formula (`FUN_00463660`, thiscall on the damage object)
Called by the hit handler with the impact point, the weapon's power P and radius R:
```
shielded                         -> 0 (clears the stored damage), no hit
d_axis = max(|target_axis − impact_axis| − size, 0)      for x, y, z (the player: its flight-model position)
any d_axis > R                   -> no damage
dmg = |(dx − R)(dy − R)(dz − R)| · P / R³                (P at the centre, falling off per axis)
target not on the player's side, single player: dmg ×= 0.8 (Rookie) / 0.9 (Normal) / 1.0 (Expert)
dmg ≥ strength                   -> destroyed (fraction 1.0)
damage += dmg / strength; ≥ 1.0  -> destroyed
```
The skill factors are `[DifficultyLevel] RookieDamagePercent` / `RegularDamagePercent` of `iaf.ibx` (defaults 0.8 /
0.9, 0x634dac / 0x634db0; the shipped file has no such section), read by the damage-object ctor. "Not on the
player's side" = `FUN_004a41e0(target side, player side)` (with no player: sides 2 / 3). **So at Rookie and Normal
the enemies are tougher** — backwards for an "easier" setting; kept as the original (to decide with the user).

### 4.2 The hit handler (`FUN_004a8f40` → `FUN_004a9100`)
1. The player's jet with **Invulnerable** (pref +0x1c; always applies in single player) takes no hits.
2. A unit is not hit by its own weapon (owner key = self).
3. Blast (§4.1). The hit counts only if it destroys or adds **≥ 0.01** (0x5ff240).
4. The shooter (from the weapon key) must still exist, else nothing happens. The weapon key goes to MStatus+0x2c;
   score (`FUN_004a9290`) and, when the player hit something, the hit feedback (`FUN_004a9860`, `FUN_0054f3e0`)
   are not ported.
5. Destroyed → level 5; else the new fraction without a level (§3.1); a brain reacts to the shooter
   (`FUN_0043ff00`, not ported).

### 4.3 Weapons (for the weapons port)
The only caller of the hit handler is the weapon detonation `FUN_004d4a40` (@4d4f5d), which loops over the units the
weapon's vtable +0x1c returns and passes S = {impact position, time, **power = weapon+0x70**, **radius =
weapon+0x80**}. From the bdb Weapons record (`FUN_004c2eb7`): power = **`0x744`**, radius = **`0x74e`**, +0x74 weight
`0x758` (lb), +0x78 `0x73a`, +0x7c `0x762`, model `0x730`, type `0x780`; +0x84 = radius + 20.

| weapon | power | radius (m) |
|---|---|---|
| 20 MM / DEFA gun | 100 | 50 |
| AAA | 15 | 30 |
| AIM-9L / 9M / 9D | 400 / 500 / 300 | 15 / 15 / 30 |
| MK-82 / 83 / 84 | 5000 / 7000 / 20000 | 50 / 80 / 100 |

A direct gun hit does 100: an F-16 (300) takes three. Gun rounds (type 0x235) fired by a non-player hit the target's
centre (UNCERTAIN).

**Port API** (`mission_runtime.gd`): `area_damage(point, power, radius, source, kind)` (the detonation over every
unit), `apply_damage(target, amount, kind, source)` (a blast at distance 0), `set_damage_level(target, level,
source)`; `kind` "gun" selects the gun-rounds thump for the player.

## 5. The player's jet: systems damage
A hit that leaves a controlled aircraft (class 0x1c) alive runs its controller's reaction `FUN_0044c8c0`:
- The player: gun rounds → `SFX_AIRCRAFT_DAMAGED / DAMAGED_GUN_BULLETS` (Cock_Dmgd_03), at most every **2 s**
  (controller timer +0x840). Other hits → a view shake (flight-model motion 0xd, amplitude 2·(damage increase), or
  a random 0..1 when it did not grow, random sign, clamped ±1) and `DAMAGED_MISSILE_HIT` (Cock_Dmgd_05). The shake's
  effect in the flight model is not traced; ours shakes the camera up to 2° for 0.5 s.
- Single player, 0 < damage < 1: a system may break: `FUN_0045c300(damage)` picks, `FUN_0044ca90(n)` applies.

### 5.1 The pick (`FUN_0045c300`, allowed = `FUN_0045c4a0`)
Up to 10 tries until a code: tries 1–8 pick by the damage: < 0.33 → rand%6 (0..5), < 0.66 → rand%9 + 5 (5..13),
else rand%12 + 13 (13..24); tries 9–10 rand%24. A code already set or not allowed steps ±1 (random) while
2 ≤ n ≤ 22. Not allowed: right-engine codes 3, 9, 17, 23 on a single-engine jet; 2, 3, 5, 7 on an AI jet; 1 without
ECM; 3 always; 2 once an engine cut-out was picked (+0x70) or with 9 / 17 / 23 set. Quirk kept: picking 2 or 3 sets
+0x70 before the test, so **an engine cut-out never happens**.

### 5.2 The codes (`FUN_0044ca90`; console text via `FUN_004491c0` for the player)

| n | console text (twin-engine variant) | also sets | other effects | damage page row |
|---|---|---|---|---|
| 1 | ECM damage | – | ECM light (6) off, ECM off | ECM |
| 2 / 3 | Engine cut out - restart throttle (Left / Right …) | 8 / 9 | Betty "Engine" | ENG / ENG R |
| 4 | Flaps damage | – | flaps lever refused | FLAP |
| 5 | Air brakes damage | – | – | BRAK |
| 6 | – | – | autopilot off (light 8, FM motion 0xf) | A/P |
| 7 | Gear damage | – | the three gear lamps stay red (legs = 1), the lever cannot move them | GEAR |
| 8 / 9 | After burner damage (Left / Right …) | – | – | AB / AB R |
| 10 | Fuel leak - reduce throttle | – | – | FUEL |
| 11 | Instuments damage | – | – | INS |
| 12 | Hud damage | – | – | HUD |
| 13 | Gun damage | – | `FUN_00455e60` (gun, UNCERTAIN) | GUN |
| 14 | RWR damage | – | `FUN_00451590` (RWR, UNCERTAIN), lights 3 / 4 off | RWR |
| 15 | Radar damage | – | `FUN_004ad260` (radar, UNCERTAIN) | RDR |
| 16 / 17 | Engine on fire - use extinguisher (Left / Right …) | 8 / 9 | fire light 1 / 2 on, Betty "Fire" | ENG / ENG R |
| 18 | Hydraulic control | – | – | AILN |
| 19 | Main generator failure | 15, 14 | radar and RWR off, `DAMAGED_ELECTRICITY` | ELCT |
| 20 | Weapon systems damage | – | `FUN_00456920` (weapons, UNCERTAIN) | WPNS |
| 21 | Total generator failure | 15, 20, 14, 1, 11, 12 | radar, weapons, RWR, ECM off, `DAMAGED_ELECTRICITY` | GNRT |
| 22 / 23 | Engine permanent damage (Left / Right …) | 8 / 9 | Betty "Engine" | ENG / ENG R |
| 24 | Total flight control | – | forces the spin mode (docs/flight-model.md §15.5) | FLTC |

Then the flag itself (`FUN_0045c250`, controller +0x3d8+0xc+4n), the **master caution** light (0, `FUN_0045aa00`) and
Betty "Caution" (`VOC_BBETTY / BTY_CAUTION`; `SFX_WARNING / WRN_MASTER` on jets without Betty, file not shipped).
The damage page (MFD page 4, `FUN_0052a0d0`) shows "NAME GO" / "NAME NOGO" per row from the cockpit copy of the flags
(+0x550+4n); ENG is NOGO with 2, 16 or 22, ENG R with 3, 17 or 23.
**Port:** `player_damage.gd`; wired: console text, flags → damage page, lights (master caution, fire, ECM, A/P,
RWR), gear lamps and lever, flaps lever, thumps, Betty calls. **Not wired** (the flight model has no damage inputs
yet): engine cut-out / fire / permanent damage, afterburner, fuel leak, hydraulics, total flight control (the
flight model's damage bits `FUN_005b9140`), instruments / HUD / radar / RWR / gun / weapons shutdown, the
extinguisher (GEV 0x49).

## 6. Explosions, smoke, debris

### 6.1 The explosion object (Tgen `FUN_00416850`, per-frame `FUN_00416780` / `FUN_00416a40`)
Parameters: flags, position, radius [4], model [5], **duration** [6] (lifetime of the event; < 0.001 → 3.5 s),
**scale** [7]. `FUN_0059b3b0` builds it with scale 4 and duration **95 s**. Sprite sizes: full width
= 0.2 · size · texture width (`FUN_00410660`; UNCERTAIN, the formula gives a 256 m fireball), bottom-anchored.

| flag | effect | size / timing |
|---|---|---|
| 0x10 | fireball (airexp1, 15 frames) | 1.2 s, size 10 (≈ 256 m wide) |
| 0x10000000 | small fireball | size 1.5 (≈ 38 m), 1.2 s |
| 0x4000 | lens flash | one frame |
| 0x2 | the model shatters: one piece per polygon | velocity (offset + base)·k·scale, k ∈ {0.5,1,1.5}; spin ±0.96 rad/s; g = 30; life (1 + U)·duration/2 = 47–94 s; delay 0–0.3 s |
| 0x40 | no piece delay | |
| 0x80 | upward kick (base 5) | |
| 0x1000 | pieces rest at origin − 0.5 m (else vanish at the ground) | |
| 0x8 (+0x2) | large flying pieces trail smoke puffs | one puff per frame |
| 0x20 | large flying pieces may flare (1/32 per frame) into a small fire | |
| 0x8 (no 0x2) | 12 smoke streamers (5·scale sideways, 3·scale up, g 30) then a 9 s column | weapons |
| 0x100 | smoke puff (smoke3) | 2.5 s, 12.8 → 38 m wide, grey 40, rising 5.6–10.1 m/s, ±2.4 m/s drift |
| 0x400 | white instead of dark smoke | |
| 0x800 | smoke column | 33 / (4 − detail) puffs, one per 1.6 s, each visible 0.3 s … 36 / (4 − detail) s, width 12.8·(1 + 0.32·age) m, rising 2.5–5.8 m/s, grey 10–79 |
| 0x2000 | cluster: 48 sub-bursts in 3 rings | weapons |
| 0x20000 / 0x40000 | water splash / ring | 1.2 s / 2.4 s |
| 0x1, 0x200, 0x4 | dead (animation never registered) / unused | |

### 6.2 By class (`FUN_0059b3b0`; "low" = below ground + 10.5 m)

| class | flags | seen |
|---|---|---|
| aircraft 1, 2, 3, 0x1c, in the air | 0x407a | flash, fireball, shatter (no delay), smoking / flaring pieces |
| aircraft, low, on land | 0x58ba | + pieces rest, kick, smoke column; a crater 1 s later |
| aircraft, low, on water | 0x640ba | splash, ring, fireball, shatter |
| 5, 10 | 0x58ba | as a low aircraft, no crater |
| 6, 8, 9, 0xb | 0x188a | shatter with kick, resting smoking pieces, column (no fireball) |
| 0xc / 0xd type 410 (reactor) | 0x4810 | flash, fireball, column |
| 0xc / 0xd type 420 (bridges) | 0x1892, scale 2 | shatter, fireball, column |
| other 0xc / 0xd | 0x800 | column only |
| boats 0xf, 0x10 | 0x640ba, scale 1.5 | splash, ring, fireball, shatter |

Sound: code 0x11 **`SFX_AIRCRAFT_EXPLODED`** (AerialExp.wav, 3-D 500 / 1000 m) for **every** unit class (weapons use
others). Craters: the "CreateCraterEv" moves the next object of a pool of class-0x1f units ("Crater") to the spot;
no mission places one, so no crater ever appears in the shipped data.

### 6.3 Damage smoke (`FUN_004d1880` list 0x69497c, emitter `FUN_004d1990`)
A controlled aircraft (class 0x1c) hit to **≥ 0.25** trails smoke; 20 s later (0x82d748) it stops unless the damage
reached **0.5** (`FUN_004a7560`). A falling aircraft (§3.3) trails smoke from the first 0.5 s check. One 0x100 puff
per rendered frame at model hot point 0x3a (0x3b for some models); at most 100 emitters.

**Port** (`damage_effects.gd`): the same flags, sizes, speeds and lifetimes with soft procedural billboards (one
MultiMesh per material), box chunks for the shattered polygons (24 per explosion, from within the unit's size), a
0.1 s light for the flash. Our choices: puffs at a fixed 30 Hz instead of per frame (the original's density follows
the frame rate), the column at detail 3 (default not traced), no wind (the mission weather is not decoded), no water
(our terrain has no types).

## 7. Collisions between units (`FUN_0043c1f0` → `FUN_0043b3d0`)
Colliders (`FUN_0043b250`): radius = 0.25 · (sx + sy + sz) of the normal model's extents (UNCERTAIN: full or half).

| class | group | mask |
|---|---|---|
| aircraft 1, 2, 3, 0x1c | 2 | 0x1b |
| vehicles 5, 6 | 8 | 0 |
| sites 8–0xb, buildings 0xc / 0xd (not type 450: runways, runway lights) | 1 | 0 |
| boats 0xf, 0x10 | 0x10 | 0 |
| weapons 0x16–0x1a | 4 | 0x19 |
| crater 0x1f | 0x20 | 2 |

Trees, sensors and parachutes have none. A collides with B when (B.group & A.mask) ≠ 0 and the centres are closer
than **B's** radius. Reaction on each side: a weapon detonates; a shielded unit ignores it; an AI aircraft, a
vehicle, site, building or boat is destroyed (level 5); the player's jet is destroyed unless Invulnerable. So a jet
hitting a building, a vehicle or another aircraft destroys both.
**Port:** the player's jet is tested every frame against the visible units (UNCERTAIN: whether hidden units keep
their collider; the shipped missions use hidden houses as audio markers on taxiways).

## 8. Uncertain / not ported
- Sprite world size (the 256 m fireball), the lens-flash texture, the column detail default, wind.
- Effect 0x18 at a fatal hit; the double explosion at a crash-motion impact; state 4.
- Radio kill / "is down" calls, score and hit feedback, the brain's reaction to hits, FlyTSD 6.5 s after the
  player's death (campaign), network play.
- The flight model's reaction to systems damage (§5.2) and to the hit shake.
- Collision: full vs half extents, hidden units.
- Original-vs-better decisions for the user: the heading-0 fall (§3.3), the Rookie / Normal enemy damage factor
  (§4.1), puffs per frame (§6.3).
