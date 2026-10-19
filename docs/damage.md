# Damage and destruction

This page describes how the original game damages and destroys units. It covers:
- how a hit becomes damage (§4), and when a unit counts as hit or destroyed (§3);
- what the player sees and hears (§2.2, §6) and which of the player's systems break (§5);
- how unit collisions work (§7);
- how all of this feeds the mission's win / lose rules (§3.2).

The rules are the same for every unit class and every aircraft.

Key facts:
- A unit has a **strength** (hit points) and a **damage** fraction from 0 to 1.
- A hit that leaves damage ≥ 0.8 makes the unit fatally hit ("going down"). Damage ≥ 1.0 destroys it (§3.1).
- A gun hit does 100 damage. An F-16 has strength 300, so it takes three direct gun hits.

**Sources.** Addresses are `IAFJets.exe` **v1.1** (the reference version). [v1.1.md](v1.1.md) maps them to v1.0 and
lists what the patch changed. The Ghidra C is in `assets/ghidra_v11/iafjets.c`. Functions missing there were
decompiled at their address.

**Port.**
- `game/mission/damage_model.gd`: the rules.
- `mission_runtime.gd`: unit status, events, roles.
- `player_damage.gd`: the player's systems.
- `damage_effects.gd`: explosions, smoke, debris.
- `terrain_view.gd`: the host (models, the player's jet, collisions).
- Tests: `tests/godot/test_damage.gd`.

**Terms used on this page.**

| term | meaning |
|---|---|
| bdb | the game's binary database (`default6_1.bdb`); "bdb Objects `0x56e`" is a field of the Objects table |
| FM | flight model |
| AI | computer-controlled (a unit no human flies) |
| AB | afterburner |
| ECM | electronic countermeasures (the jammer) |
| RWR | radar warning receiver |
| MFD | multi-function display |
| GEV | game event (a key or control input the game dispatches) |
| AA / AG | air-to-air / air-to-ground |
| LCOS | lead-computing optical sight (the air-to-air gun pipper) |
| DLZ | dynamic launch zone (the missile's launch range) |
| Betty | the cockpit's recorded voice warnings |
| U | a random number from 0 to 1 (rand / 32767) |

## 1. Runtime objects

Each unit (entity) holds four objects for damage:

| object | where | fields |
|---|---|---|
| Unit status (`MStatus`, MStatus.cpp) | entity+0x1c | +0x0c **state**: 1 alive, 3 fatally hit ("going down"), 4 destroyed, 5 exploded; +0x10 **damage** fraction 0..1; +0x14 control mode (docs/mission-runtime.md §1); +0x18 role; +0x20 kill counter; +0x28 **requested level** (kept between calls); +0x2c the key of the last hitting weapon; +0x48 the smoke timer |
| Damage object | entity+0x10 (ctor `FUN_00464280`) | +0 entity, +4 **strength** (hit points), +8 **shield** flag |
| Collider | entity+0x18 (`FUN_0043b1c0`) | group, mask, radius² (§7) |
| Visual | entity+4 | [5] normal, [6] damaged, [7] destroyed, [8] cockpit-exterior model; +8 display 1..4 (§2.2) |

## 2. Per-unit data (bdb Objects)

### 2.1 Strength, size, shield
Each unit type sets three values in the bdb Objects table.
- **Strength** = bdb Objects **`0x56e`** (type record +0x28, `FUN_0058d390`). The spawner `FUN_004b7ea3` sets it
  (@4b7ec4). When `0x56e` is 0, the class init's value of **10.0** stays (`FUN_0059b730`, `FUN_0059c240`).
- **Size** R (entity+8 → +0x4c) = **0.5 · `0x564`**. `0x564` is the spawn radius (type record +0x30,
  `FUN_004b7634`). A radius ≤ 0 becomes 5.0 (R = 2.5). Fire sensors (class 0x12) always use 5.0. Only the blast
  formula uses R (§4.1).
- **Shield** starts off. Trigger ops 11 / 12 set / clear it (docs/mission-runtime.md §4). A shielded unit takes no
  damage, loses any damage it had (`FUN_005865c0`) and ignores collisions.
- The damage code does not read `0x55a` (7000 / 6000 / 12000 on some jets) or `0x550` (UNCERTAIN meaning).

Strength and size per class (`0x5aa`):

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

`FUN_0058d390` also forces two types by name: "Parachute" → class 4 / type 500, "Crater" → class 0x1f / type 0xe1.

### 2.2 Damaged and destroyed models (`FUN_004b7c4d`, `FUN_004a89d0`)
The data holds only normal models. The game builds the damaged and destroyed looks in code:
- **Classes 1, 2, 3, 4, 8, 9, 0xf, 0x10, 0x1c and the default:** the damaged model is the normal one. The
  destroyed model is an empty dummy, so the unit **vanishes** when it explodes (state 5).
- **Buildings (classes 0xc, 0xd, 0x1d):** `FUN_0053e2a0` → `FUN_0041f980` "createBurnedCopy" makes the models.
  Each vertex, with probability p, moves by (rand%200 − 100) · max extent · 1e-4 per axis and turns dark grey
  (diffuse 0xFF141414). Damaged (state 3): p = 0.25. Destroyed (state 5): p = 0.5, **only for types 400 and 410**.
  The other building types vanish.
- **Classes 0x11, 0x12 (fire sensors), 0x1b** are never drawn.
- **Display:** state 1 → [5], state 3 → [6], state 5 → [7]. State 4 leaves the display as it is.
- **[8]** = `0x546` is the `*_BC.X` model: **the jet's exterior as seen from its own cockpit** (texture `bcf16.bmp`
  = seat back). Only the flyable jets and the MiG-23 / MiG-29 have one. docs/formats/x.md's "damaged / burnt" guess
  for `_bc` is wrong.
- **v1.0 vs v1.1:** v1.0 showed [8] on the player's own jet in the cockpit views (1, 0x12, 0x16, 5) when entering
  state 1. **v1.1 removed that branch** (part of the eject fix): entering state 1 always shows [5] and clears the
  crew's cockpit flag (docs/part-animation.md "Ejection").
- The data has no damaged or destroyed meshes. The converter already exports every Present model.
- **Port:** `terrain_view.gd` `_entity_fatally_hit` / `_entity_final` / `_burned_copy` (vertex colours on duplicated
  materials). The port skips spawning the hidden classes.

## 3. Unit state machine

A unit has four states: 1 alive, 3 fatally hit, 4 destroyed, 5 exploded (§1). A caller asks for a new state by
setting a **level**; the unit then moves to that state.

### 3.1 Setting a level (`FUN_004a8ae0(damage, level, key)`, `FUN_004a8da0`)
1. If the unit is in state 5, stop.
2. Single player: store the request.
   - With a level 1..5 given: store it as the request (+0x28). Store `damage` (+0x10) if 0 ≤ d ≤ 1.
   - Without a level (−1): d ≥ **1.0** → request 5; d ≥ **0.8** (0x63f454) → request 3; otherwise only store d.
   - The request persists between calls.
3. Move by the request:
   - **3**: from state 1 → state 3, `FUN_004a8100`.
   - **4**: from 1 or 3 → state 4, `FUN_004a8280`.
   - **5**: from 1 or 3 → state 5, `FUN_004a8420`.
4. If the unit is still alive (state 1), run the alive-hit reaction `FUN_004a9c60` (§5, §6.3).
5. `FUN_004a9e70` makes the radio calls after a kill. **Not ported** (radio).
   - Known killer: `FUN_0054c2a0(killer, victim)` 5 s later (kill calls).
   - An aircraft (class 0x1c) with no killer: `FUN_0054e0e0` 2.5 s later ("… is down").

Who sets levels:
- the hit handler (§4);
- trigger op 5 Explode (level 5);
- the flight model's crash (`FUN_005bb9f0` → level 5 at a failed landing check, water, rough ground);
- collisions (§7);
- the destruction motion (§3.3);
- weapons (`FUN_004d6130`): a weapon with +0x100 == 2 forces its target to 5 unless the target is a shielded player
  (UNCERTAIN meaning).

**Level 4** comes only from a request of 4, and no damage path makes one. State 4 is practically unused.

### 3.2 Transitions
- **1 → 3 `FUN_004a8100`:**
  - the **hit event** (slot 0, sensor on; docs/mission-runtime.md §2);
  - control mode 0 (`FUN_004a8e70(0)`: a mission-controlled unit's scenario is killed, a brain stops);
  - the damaged model;
  - the **destruction motion** (§3.3), if it is not already running;
  - for the player: `WINGMAN_EJECT_EJECT` ("Eject! Eject!"), the outside view 0x10 on the jet, canopy and pilot
    drawn.
- **→ 4 `FUN_004a8280` / → 5 `FUN_004a8420`:**
  - the **destroy event** (slot 1, sensor on) and killScenario;
  - control mode 0;
  - for 5: the kill counter +0x20, and for an aircraft killed by the player's side, the killer's kill count;
  - the view 0x10 when the unit is the player;
  - then the final status.
- **Final `FUN_004a86b0`:**
  - the explosion at the unit's position (`FUN_0059df20`, §6);
  - the destroyed model;
  - the unit's sounds stop (`FUN_004c4310`) and its smoke stops (`FUN_004d1ff0`);
  - the brain ends;
  - the role accounting `FUN_00599da0` (docs/mission-runtime.md §5.1);
  - for the player, unless every player is dead: game event 0x7f (FlyTSD) 6.5 s later (0x8321a8). In single player
    the player is the only player, so this never fires. Rule 1 ends the flight (ours does the same).

### 3.3 The destruction motion (motion 0x14, DestructionMotion.cpp)
`FUN_00465c19` creates it at 1 → 3 (`FUN_00464a43(0x14)`, vtable 0x602520). It replaces the unit's motion. For the
player, the flight model freezes (`FUN_005a6510`) and the jet stops answering the controls.
- Mover kind (`FUN_00465f83`): 1 = classes 5, 6, 8–11; **2 = 3, 0x1c** (fixed wing); **3 = 1, 2** (helicopters);
  4 = boats 0xf, 0x10; 5 = 0x16–0x1a; 6 = 7; 7 = the rest.
- **Init** `FUN_004971ae`: s = (U − 0.5)·2.
  - Kinds 1, 4, 6: velocity 0, T = 0.5 + 0.5·U.
  - Kinds 2, 3: v0 = the current velocity (kind 3: vz clamped ±10); h = z + 10. If h > 0 (or over water for 3 / 4),
    kind 2 has T = 1e8 and kind 3 has T = (vz + √(vz² + 19.612·h)) / 9.806. Otherwise T = 0.1.
  - Other kinds: T = 0.1, v0 kept.
- **Position** p = p0 + v0·τ + ½·a·τ². a_z = **−39.224 (4 g) for fixed wing**, 0 for boats, −9.806 for the rest.
  There is no drag. z stays ≥ the terrain where the terrain is above 0.1 m.
- **Attitude, fixed wing:**
  - roll = φ0 + s·180°/s·τ;
  - the nose goes to −(90° − 5°) (FlightModel/pitchEpsilon) at 18°/s. s = −1 when −85° < θ0 < 90°; otherwise
    s > 0 snaps it to −95°;
  - **heading = 0**. The code writes the heading output only on the helicopter path: an original bug, kept.
    Preferences > Physics "Falling jets keep their heading" (`bp_fix_fall_heading`) keeps the heading (opt-in,
    deviations.md §2).
- **Attitude, helicopters:** pitch = θ0 + s·ω·τ, ω = (n·2π − s·θ0)/T, n ∈ {0,1,2}. Roll levels linearly. Heading
  turns at s·U·π rad/s.
- **End check** (`FUN_00496c12`, **every 0.5 s**, kinds 2 and 3 only):
  - past T → state 5;
  - at **≤ 2 m above the ground** → the wreck snaps to the terrain, its smoke trail stops, it explodes, state 5;
  - the first check higher up starts the smoke trail (type 2, §6.3).
- Ground units, boats and buildings get the motion but no end check. They stay at state 3 where they are until
  more damage comes.
- **Effect 0x18 at the start.** The motion's start (vtable 0x602520 slot 2, `FUN_0046b2b0`) sends effect 0x18 at
  the unit's position: `FUN_0059ddb0` → `FUN_0059dad0` → `FUN_0057da50`. The effect is a **fireball** (Tgen flag
  0x10, §6.1) whose event lasts **0.8 s** (`0x843cc0`), so it shows 0.8 s of the fireball's 1.2 s. It has no sound
  (sound key 0). Within 10.5 m of the ground it also asks for a crater (`FUN_0054a980`); the crater pool is empty
  (§6.2).
- **Two explosions at impact.** The end check's ground contact explodes the wreck (`FUN_0059df20`, the class
  explosion of §6.2) and then asks for level 5. The final status (`FUN_004a86b0`) then makes the same class
  explosion again at the same spot. So a falling unit leaves two sets of debris and two `SFX_AIRCRAFT_EXPLODED`.
- **Port:** `DamageModel.fall_start` / `fall_at`. The runtime moves units; `terrain_view.mission_player_fall` moves
  the player's jet. `terrain_view.gd` `_fatal_hit_effect` draws effect 0x18; `mission_entity_impact` makes the
  impact explosion.

## 4. Hits

### 4.1 The blast formula (`FUN_004642f0`, thiscall on the damage object)
The hit handler calls it with the impact point, the weapon's power P and the weapon's radius R. Damage is P at the
centre and falls off along each axis to 0 at distance R from the target's edge:
```
shielded                         -> 0 (clears the stored damage), no hit
d_axis = max(|target_axis − impact_axis| − size, 0)      for x, y, z (the player: its flight-model position)
any d_axis > R                   -> no damage
dmg = |(dx − R)(dy − R)(dz − R)| · P / R³                (P at the centre, falling off per axis)
target not on the player's side, single player: dmg ×= 0.8 (Rookie) / 0.9 (Normal) / 1.0 (Expert)
dmg ≥ strength                   -> destroyed (fraction 1.0)
damage += dmg / strength; ≥ 1.0  -> destroyed
```
- **Skill factors:** `[DifficultyLevel] RookieDamagePercent` / `RegularDamagePercent` of `iaf.ibx` (defaults 0.8 /
  0.9, 0x63900c / 0x639010). The shipped file has no such section. The damage-object constructor reads them.
- **"Not on the player's side"** = `FUN_004a4cf0(target side, player side)` (with no player: sides 2 / 3).
- **Original bug: at Rookie and Normal the enemies are tougher.** This is backwards for an "easier" setting
  (verified at 464636–46467c: the call returns 1 for a different side). v1.1 left this block unchanged, so v1.1 has
  the bug too. Ours keeps it by default. Preferences > Physics "No tougher enemies on easy AI levels"
  (`bp_fix_skill_damage`) turns the scaling off.
- Other AI-level readers: `4404d0`, and the AI fire decision `4440d0` (§4.4). `443f60`, once listed here as a skill
  reader, reads no skill value.

### 4.2 The hit handler (`FUN_004a97b0` → `FUN_004a9970`)
1. If the target is the player's jet with **Invulnerable** on (pref +0x1c; always applies in single player), stop.
2. If the weapon belongs to the target (owner key = self), stop: a unit's own weapon never hits it.
3. Apply the blast (§4.1). The hit counts only if it destroys the unit or adds **≥ 0.01** (0x603108).
4. If the shooter (from the weapon key) no longer exists, stop. Otherwise store the weapon key at MStatus+0x2c.
   Then `FUN_004a9b00` plays the force-feedback effects when the player's jet is hit (missiles 0x230..0x262, the
   gun 0x235, the crash effect `4dec00`; no force feedback in ours).
5. Set the level: destroyed → level 5; otherwise the new fraction without a level (§3.1).
6. A brain stores the shooter as its **last hitter** (brain +0x80, `FUN_0043ff50`). A timed event (vtable
   0x6007f8, `FUN_00440030`) clears it 5 s later (`0x600748` = −5). Nothing reads it: in the exe only the brain's
   constructor and reset (`FUN_0043eda0`, `FUN_0043eef0`) write it, and `FUN_0043ff50` reads it back only to format
   the shooter's key into a temporary string that it throws away (debug). So it is not ported.
7. The **friendly-hit voice** (`FUN_00551560` → `FUN_005515d0`), after the level is set, when the damage grew:
   - The shooter is the player and the hit unit is on the player's side (`FUN_004a4cd0`: same side; with no unit,
     side 1).
   - The hit unit's class is 1, 2, 3, 5, 6, 8, 9, 10, 0xf, 0x10 or 0x1c. Weapons, buildings, trees, ground radars,
     parachutes, sensors and craters say nothing.
   - The voice window is free: `FUN_004d4020` on the timer `DAT_0083ffb0` (built by `FUN_00551540`: 0..10 s, not
     random; start 1e7). It is busy from a call until 10 s later, so a call comes at most once per 10 s.
   - Who says it (`FUN_004c4ea0`): the hit unit while it still flies (not state 4 / 5, control mode not 0; a fatal
     hit sets 0) → `VOC_TARGET_SAY_FRIENDLY_HIT` (0x33, Friendly2); else the player's brain partner (brain +0x44)
     by the same test → `VOC_WINGMAN_SAY_FRIENDLY_HIT` (0x34, Friendly3); else `VOC_TOWER_SAY_FRIENDLY_HIT` (0x35,
     Friendly4).
   - Port: `mission_runtime.gd` `_friendly_hit`, `DamageModel.friendly_voice`.

### 4.3 Weapons (for the weapons port)
The weapon detonation `FUN_004d6130` (@4d664d) is the only caller of the hit handler. It loops over the units that
the weapon's vtable +0x1c returns and passes S = {impact position, time, **power = weapon+0x70**, **radius =
weapon+0x80**}.

The values come from the bdb Weapons record (parser `FUN_00593ee0`): power = **`0x744`**, radius = **`0x74e`**, +0x74
weight `0x758` (lb), +0x78 `0x73a`, +0x7c `0x762`, model `0x730`, type `0x780`; +0x84 = radius + 20.

| weapon | power | radius (m) |
|---|---|---|
| 20 MM / DEFA gun | 100 | 50 |
| AAA | 15 | 30 |
| AIM-9L / 9M / 9D | 400 / 500 / 300 | 15 / 15 / 30 |
| MK-82 / 83 / 84 | 5000 / 7000 / 20000 | 50 / 80 / 100 |

A direct gun hit does 100, so an F-16 (strength 300) takes three. Gun rounds (type 0x235) fired by any unit other than
the player hit the target's centre (UNCERTAIN).

**Port API** (`mission_runtime.gd`):
- `area_damage(point, power, radius, source, kind)`: the detonation over every unit;
- `apply_damage(target, amount, kind, source)`: a blast at distance 0;
- `set_damage_level(target, level, source)`;
- `kind` "gun" selects the gun-rounds thump for the player.

### 4.4 v1.1 weapon and AI rules (gun and missile rules ported: docs/weapons.md; AI rules: `game/ai/combat.gd`)
The v1.1 patch changed these rules. The v1.0 behaviour appears only for comparison (docs/v1.1.md).
- **Gun** (fire `FUN_00456ff0`):
  - The player's shot direction turns **+1° about the lateral axis** before the lead is applied. The bullets fly 1°
    higher, onto the gun cross (docs/cockpit.md).
  - With no lock, the aim distance is **2781 m** (1.5 mi; v1.0 1854 m). The AI's auto-hit sphere scales with it.
- **Gun pippers** (corrected, docs/weapons.md §3.7):
  - AA LCOS `FUN_0045f410`: the same as v1.0, without the +1°.
  - The new AG pipper `FUN_0045ef10`: the projection of the +1° aim point.
  - `FUN_004604c0` is a seeker for weapon 0x27b.
- **Ballistic correction** (`FUN_005611b0`, `FUN_00468470`; corrected: it applies to the bomb / shell class 0x16, and
  gun rounds are outside it, docs/weapons.md §8). Single player, the player's rounds only:
  - the homing correction is clamped to **±`weapons.ibx [DEBUGDATA] _debugParam016`** m/s² (15 in v1.1);
  - the flight time has no cap at impact (v1.0 capped it there).
  - v1.0 data has `_debugParam016` = `_debugParam018` = 1. Ours then uses the v1.1 value 15 (v1.1 logic with any
    data, user decision).
- **Missiles** (`FUN_005604a0`, `FUN_005605c0`, `FUN_00457f70`; corrected, docs/weapons.md §3.4 / §5.2):
  - The value scaled "`_spiralAccel` ×0.5 unless Easy aiming" is the **gun round / fixed weapon hit sphere**
    (25 / 50 m).
  - The player's missile launch q is ×0.8 without Easy aiming. The chase init reads it (gain, and dog vs
    proportional chase).
- **AI fire decision** (`FUN_004440d0`): the AI fires when the angle between the shooter's nose and the target (acos
  of the clamped dot product) is ≤ the cone. The cone is **30°** for missiles and **5°** for guns (v1.0 7°), ×**0.5**
  Rookie / ×1 Normal / ×**1.5** Expert. v1.0 compared the cosine with a threshold scaled 0.75 / 1 / 1.5, so an Expert
  enemy (threshold > 1) could never fire.
- **Missile after guns** (`FUN_00452710`): the heat request 570 also accepts 580. The new BDB brain rule "Over 2000m
  and out of DLZ - change missile" (brains 29 / 45 / 67 in `default6_1.bdb`) is data. v1.0 data lacks the rule; do
  not synthesise it.
- **Relative bearing** (`FUN_0044e770`): the result is wrapped to (−π, π] (v1.0 returned it unwrapped). It feeds the
  RWR emitter test (`FUN_004521c0`), the AI and the HUD bearing. Wrap it wherever we compute it.
- **Multiplayer**: the last shooter is kept when the pilot ejects, for the kill credit (`FUN_004a8ae0`, eject event
  `FUN_00548f00`).

## 5. The player's jet: systems damage
A hit that leaves a controlled aircraft (class 0x1c) alive runs its controller's reaction `FUN_0044d590`:
- **The player, gun rounds:** `SFX_AIRCRAFT_DAMAGED / DAMAGED_GUN_BULLETS` (Cock_Dmgd_03), at most every **2 s**
  (controller timer +0x840).
- **The player, other hits:** a view shake and `DAMAGED_MISSILE_HIT` (Cock_Dmgd_05). The shake is flight-model
  motion 0xd. Its amplitude is 2·(damage increase), or a random 0..1 when the damage did not grow, with a random
  sign, clamped ±1. The shake's effect in the flight model is not traced; ours shakes the camera up to 2° for 0.5 s.
- **Single player, 0 < damage < 1:** a system may break. `FUN_0045cd80(damage)` picks it and `FUN_0044d760(n)`
  applies it.

### 5.1 The pick (`FUN_0045cd80`, allowed = `FUN_0045cf20`)
The pick makes up to 10 tries until it finds a code:
1. Tries 1–8 pick by the damage: < 0.33 → rand%6 (0..5); < 0.66 → rand%9 + 5 (5..13); otherwise rand%12 + 13
   (13..24).
2. Tries 9–10 pick rand%24.
3. A code that is already set or not allowed steps ±1 (random) while 2 ≤ n ≤ 22.

Codes not allowed:
- the right-engine codes 3, 9, 17, 23 on a single-engine jet;
- 2, 3, 5, 7 on an AI jet;
- 1 on a jet without ECM;
- 3 always;
- 2 once an engine cut-out was picked (+0x70), or with 9 / 17 / 23 set.

Quirk, kept: picking 2 or 3 sets +0x70 before the test, so **an engine cut-out never happens**.

### 5.2 The codes (`FUN_0044d760`; console text via `FUN_0044a060` for the player)

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
| 13 | Gun damage | – | `FUN_00456200` (gun, UNCERTAIN) | GUN |
| 14 | RWR damage | – | `FUN_00451b90` (the RWR list cleared; flag 14 then blocks it, docs/rwr.md), lights 3 / 4 off | RWR |
| 15 | Radar damage | – | `FUN_004adb20` (radar, UNCERTAIN) | RDR |
| 16 / 17 | Engine on fire - use extinguisher (Left / Right …) | 8 / 9 | fire light 1 / 2 on, Betty "Fire" | ENG / ENG R |
| 18 | Hydraulic control | – | – | AILN |
| 19 | Main generator failure | 15, 14 | radar and RWR off, `DAMAGED_ELECTRICITY` | ELCT |
| 20 | Weapon systems damage | – | `FUN_00456cc0` (weapons, UNCERTAIN) | WPNS |
| 21 | Total generator failure | 15, 20, 14, 1, 11, 12 | radar, weapons, RWR, ECM off, `DAMAGED_ELECTRICITY` | GNRT |
| 22 / 23 | Engine permanent damage (Left / Right …) | 8 / 9 | Betty "Engine" | ENG / ENG R |
| 24 | Total flight control | – | forces the spin mode (docs/flight-model.md §15.5) | FLTC |

After the effects in the table, every code sets:
- the flag itself (`FUN_0045ccd0`, controller +0x3d8+0xc+4n);
- the **master caution** light (0, `FUN_0045b4b0`);
- Betty "Caution" (`VOC_BBETTY / BTY_CAUTION`). Jets without Betty use `SFX_WARNING / WRN_MASTER` (file not shipped).

The damage page (MFD page 4, `FUN_0052bc00`) shows "NAME GO" / "NAME NOGO" per row. It reads the cockpit copy of the
flags (S+0x558+4n, §5.3). ENG is NOGO with 2, 16 or 22; ENG R with 3, 17 or 23.

**Port:** `player_damage.gd`. Wired: console text, flags → damage page, lights (master caution, fire, ECM, A/P
(autopilot), RWR), gear lamps and lever, flaps lever, thumps, Betty calls, and every consumer of §5.3.

### 5.3 Who reads the flags (every `FUN_0045cc90` call, 67 in the exe, and the cockpit copy)
The flags live at controller `+0x3d8+0xc+4n`. The cockpit state keeps a copy at `S+0x558+4n`. (The damage page reads
ENG at +0x560 / +0x598 / +0x5b0 = flags 2 / 16 / 22, so the copy starts at +0x558, not at +0x550.)

| flags | reader | effect |
|---|---|---|
| 2, 16, 22 / 3, 17, 23 (engines) | FM `5bc350` (in the 1 Hz aero update, §15.1 step 4 of flight-model.md) | FM bit 4 (left) / 8 (right); a **single-engine** jet (controller +0x24 = 0) sets **4 and 8** from the left flags and never reads the right ones. Thrust `5b4120`: both bits → no thrust, RPM 0, no fuel flow (as engine off); one bit (a twin) → k ×0.5 (half thrust; the dry fuel-flow test `k ≤ 0.6` sees the halved k) |
| 8 / 9 (afterburner) | `5bc350` | 0x80 / 0x100 (a single engine: 0x180 from flag 8). Both bits and throttle ≥ 0.75 → throttle 0.74 (no AB, military RPM / fuel flow). A twin with one AB damaged keeps full AB thrust |
| 8 / 9 | `5abc90` / `5abdc0` | that side's afterburner flame stays out (docs/aircraft.md §2.2) |
| 10 (fuel leak) | `5bc350` → 0x40 | fuel flow += **0.25 · FuelFlowAtMaxThrust** (`0x612148` = −0.25 subtracted), also with the engine off / dead; Unlimited fuel still zeroes it |
| 18 (hydraulics) | stick motion 1 `59f3d0` | stick pitch and roll **×0.25** (`0x611b08`) at every stick event; rudder unchanged. (`5bc350` also sets FM bit 0x10, which nothing reads) |
| 24 (total flight control) | `59f3d0`; spin `5aab90` | stick pitch and roll **0**; the spin entry test passes whatever β, dragX, "No spins" (not for the F-16 / Lavi, which return first; flight-model.md §15.5). Bit 0x20 of `5bc350` is not read |
| 2, 3 (cut out) | throttle events GEV 4 / 9 (≤ 5 %) and 5 / 6 (`44a240`) | the "restart throttle": idle clears 2 (unless 8, 22, 16) / 3 (unless 9, 23, 17); RPM ± clears 2 + 8 / 3 + 9. **Unreachable**: a cut-out is never picked (§5.1), so not ported |
| 2 / 3, 16 / 17, 22 / 23 | engine panel `45ac00` | gauges (docs/cockpit.md "Engine values"; ported in `instruments.rs`) |
| 16, 17 | GEV 0x49 extinguisher (X, `44a240` @44b4cf) | with a fire and the panel's one charge (`+0x3c`, set by `45af00`; `45ae10` uses it up and plays `SFX_FIRE_EXTINGUISHER` 0x27 for the player): clears 17, 16, 3, 2 and the fire lights 2, 1. Flags 8 / 9 that the fire set stay. Without a fire nothing happens (the charge is kept) |
| 4 / 5 / 6 / 7 | GEV 0xc / 0x11 / 0x10 / 0xe and the gear legs `44f970` | flaps lever, **air brakes key** (@44c821) and autopilot key refused; gear legs stuck |
| 7 | per frame `448b20` @448fe2–4490a1 | **gear overspeed**: FM getter 5 (speed, capped 1200 m/s) · 1.9428 > **450 kt** (`0x600af0`), not Invulnerable, gear handle down (ind[9]), no flag 7 yet, leg 1 (`ctl+0x53c`) == 2 (down and locked) → `FUN_0044d760(7)` (corrects flight-model.md §12, which said none exists) |
| 1, 20 | GEV 0x46 ECM, 0x40 / 0x42 / 0x44 / 0x45 weapons | refused (docs/weapons.md) |
| 13, 15, 20 | `44d760` once: `456200` (gun +0x9c), `4adb20` (radar off for good), `456cc0` (weapons +0xa0) | gun / weapons: docs/weapons.md; radar: `radar.rs set_damaged` |
| 14 | RWR (`44deb0` …, cockpit `S+0x590`) | docs/rwr.md |
| 11 (instruments), 19, 21 | — | **only the damage page** (and 19 / 21 through the flags they set): no gauge reads them |
| 12 (HUD) | `45cd30` → `446830`: S+0x5c0 | the HUD pass `FUN_00530b70` returns at once while it is set: no HUD symbols and no I-mode marks (docs/cockpit.md "I-mode"). Ported: `hud.gd` `hud_failed` |

**"No malfunctions"** (Gameplay, pref `+0x24`) and **"No wind"** (`+0x28`) have no effect. The exe touches them only
in the copy from the menu (`4fe5f8`, `4fe676`) and in save / load; none of the 37 pref-getter (`43b5d0`) calls reads
them. So systems still break with "No malfunctions" on, as in the original. The exe has no wind at all (no
weather / wind code or strings), so there is nothing to port.

**Port:**
- `iaf_flight::damage_bits` / `Aircraft::set_damage`: thrust, stick, spin. The host passes the flags every frame.
- `player_damage.gd`: `extinguish`, `gear_overspeed`.
- `terrain_view.gd`: brakes key, X, parts input (the FM's stick and the AB flags).
- `player_weapons.gd`: radar.

**AI jets** break systems the same way:
- `FUN_004a9c60` calls `FUN_0044d590` on entity `+0x34` for every class-0x1c unit (a direct call:
  `mov ecx, [edx+0x34]` @4a9ca5). So an AI jet hit alive at 0 < damage < 1 picks a system as the player's jet does.
- `FUN_0045d020` refuses 2, 3, 5, 7. ECM damage 1 needs an ECM, and no AI jet carries one.
- `FUN_0044d760` sets the flag and the flags it implies. The console text, lights and calls are for the player only
  (`bVar2`).
- The flight model reads the flags as it does the player's.
- Port: `ai_flights.gd` `hit` (from `mission_runtime.gd` `_damaged_alive`); the pilot's `systems` flags →
  `IafFlight.set_damage`; twin-engine or not from the player's type table.

**Tests:** `aircraft.rs` (`damage_bits_follow_5bc350`, `engine_damage_cuts_thrust`,
`afterburner_damage_and_fuel_leak`, `hydraulics_and_flight_control_damage`), `tests/godot/test_systems_damage.gd`,
`tests/godot/test_ai_damage_sound.gd` (AI jets).

## 6. Explosions, smoke, debris

This section gives the original's rules. Graphics → MORE → Particle effects = Detailed draws the same spawns as GPU particles
(docs/rendering.md §6).

### 6.1 The explosion object (Tgen `FUN_00416880`, per-frame `FUN_004167b0` / `FUN_00416a70`)
An explosion is one object whose flags pick the effects (table below).
- **Parameters:** flags, position, radius [4], model [5], **duration** [6] (lifetime of the event; < 0.001 → 3.5 s),
  **scale** [7]. `FUN_0059df20` builds it with scale 4 and duration **95 s**.
- **Sprite size** (`FUN_00410690`): half-width px = W′ · size · F · 0.1 / z (min 1 px). F = viewport width /
  tan(fov/2) (twice the focal length). W′ = W / 2 (the loader halves the texture). So **full width = 0.2 · size ·
  texture width** in world units. The height follows the same rule with the texture height. Examples: smoke3 at
  size 1 is 12.8 m wide; the fireball is 256 m.
- In the low-video-memory "shrink textures" mode (0x7d1cb8), W′ = W and sprites are twice as big (original bug, not
  ported).
- **Sprites are centred** on the position. Every effect sprite (AirExp1, smoke3, smokeseg, trail, missFLR, chaff,
  splash / ring, lens, afterburn, gun) loads with the 6th loader argument +0x178 = 1 (`FUN_0058a420` →
  `FUN_004102a0` @41062b). `FUN_00410690` then spans ±h. (With 0 it would span −2h..0, bottom-anchored; no effect
  uses that. Earlier versions of this page said bottom-anchored: wrong.)
- Sprites are drawn for 4 ≤ z ≤ 30000, depth-tested, without z-write.

In the table, t = age / the sprite's time (0..1) and S = the event's scale [7]. Splash and ring are fixed in the
world (they do not turn to the camera) and drawn without z-write. Their sprite times are slots 10 / 11 of
`FUN_0058a420` (w_splash.TGA 1.2 s, w_circle.TGA 2.4 s).

| flag | effect | size / timing |
|---|---|---|
| 0x10 | fireball (airexp1, 15 frames) | 1.2 s, size 10 (≈ 256 m wide) |
| 0x10000000 | small fireball | size 1.5 (≈ 38 m), 1.2 s |
| 0x4000 | lens flash | one frame |
| 0x2 | the model shatters: one piece per polygon | velocity (offset + base)·k·scale, k ∈ {0.5,1,1.5}; spin ±0.96 rad/s; g = 30; life (1 + U)·duration/2 = 47–94 s; delay 0–0.3 s |
| 0x40 | no piece delay | |
| 0x80 | upward kick (base 5) | |
| 0x1000 | pieces rest at origin − 0.5 m (else vanish at the ground) | ours: on the terrain under each piece (deviations.md) |
| 0x8 (+0x2) | large flying pieces trail smoke puffs | one puff per frame |
| 0x20 | large flying pieces may flare (1/32 per frame) into a small fire | |
| 0x8 (no 0x2) | 12 smoke streamers (5·scale sideways, 3·scale up, g 30) then a 9 s column | weapons |
| 0x100 | smoke puff (smoke3) | 2.5 s, 12.8 → 38 m wide, grey 40, rising 5.6–10.1 m/s, ±2.4 m/s drift |
| 0x400 | white smoke (default dark) | |
| 0x800 | smoke column | 33 / (4 − L) puffs (L = the VISUAL EFFECTS level 1..3, the only reader of that level), one per 1.6 s, each visible 0.3 s … 36 / (4 − detail) s, width 12.8·(1 + 0.32·age) m, rising 2.5–5.8 m/s, grey 10–79 |
| 0x2000 | cluster: 48 sub-bursts in 3 rings (small fires, every second one with a 5 s column) | CBU (510) bursts, weapons.md §9.5 |
| 0x20000 | water splash: two crossed vertical quads of w_splash.TGA standing on the burst point, height 14·S·sin(πt), half-width 1.6·S·(t + 0.2), colour 0xFFFAFAFA (`FUN_00418530`) | 1.2 s |
| 0x40000 | water ring: one level quad of w_circle.TGA 0.1 m above the point, half-size 9.6·S·t, colour 0xFAFAFA, alpha 255·(1 − t) (`FUN_004188b0`) | 2.4 s |
| 0x1, 0x200, 0x4 | dead (animation never registered) / unused | |

### 6.2 By class (`FUN_0059df20`; "low" = below ground + 10.5 m)

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

- **Sound:** code 0x11 **`SFX_AIRCRAFT_EXPLODED`** (AerialExp.wav, 3-D 500 / 1000 m) for **every** unit class.
  Weapons use other sounds.
- **Craters:** "CreateCraterEv" moves the next object of a pool of class-0x1f units ("Crater") to the spot. No
  mission places one, so no crater ever appears in the shipped data.

### 6.3 Damage smoke (`FUN_004d1f90` list 0x69933c, emitter `FUN_004d20a0`)
- A controlled aircraft (class 0x1c) hit to **≥ 0.25** trails smoke. 20 s later (0x8321a0) the smoke stops, unless
  the damage reached **0.5** (`FUN_004a7de0`).
- A falling aircraft (§3.3) trails smoke from the first 0.5 s check.
- The emitter makes one 0x100 puff per rendered frame at model hot point 0x3a (0x3b for some models). At most 100
  emitters exist.

**Port** (`damage_effects.gd`):
- The same flags, sizes, speeds and lifetimes, drawn as soft procedural billboards (one MultiMesh per material).
- The shattered polygons are the unit model's own (textured; one shader-driven mesh per material). Our triangulated /
  subdivided models fly up to 600 pieces; above that, neighbouring triangles fly together. The original's "large"
  polygons of > 6 vertices are our largest 10 % by area. A flaring piece stops smoking but stays drawn.
- Box chunks only when there is no model.
- A 0.1 s light for the flash.

Our choices:
- Puffs at a fixed 30 Hz. The original makes one per frame, so its density follows the frame rate.
- The column follows the VISUAL EFFECTS level.
- No wind: the exe has none (the mission weather is not decoded).
- An event's duration [6] cuts its fireball short, as `FUN_004167b0` frees the event (effect 0x18: 0.8 s).
- The splash and ring are the original quads with the install's textures. Weapons on water use them too: gun
  rounds and rockets at scale 1, bombs and missiles at scale 3 (docs/weapons.md).

### 6.4 Smoke trails (Graphics SMOKE TRAILS, pref +0x48 read only by `FUN_004da090`)
`4da090` draws two kinds of trail, once per rendered frame while the owner is drawn:
- **Missiles and rockets** (entity types 0x230 and 0x23a..0x27b, i.e. 560 and 570..635): a type-5 trail (sprite
  slot 5: trail.tga, lifetime 3.5 s, size [Animations] trail = 0.6, create args (1, 0, 0.15)). Its head is at model
  (0, −(MissileFlareDistance [SFX] 1.0 + 0.5 · model length), 0), i.e. 1 m behind the tail.
- **Wingtip vortices:** aircraft whose model has EndWingL / R (obj+0x50), while the flight model's S+0x420 is set
  (75 < V < 150 m/s and stick pull > 0.7, flight-model.md §15.1 step 16). Two type-6 trails (slot 6: trail.tga,
  1.0 s, [Animations] wingtip = 0.1, args (0, 0, 0.01)) at obj+0x38 / +0x44.

Details:
- **Trail record** (Trails.cpp, create `4156a0`): a ring of 256 points (position, age). addPoint `415890` adds one
  point per frame, with no spacing test.
- **Ageing** `415970`, each frame:
  - ages += dt; points past the lifetime drop from the tail;
  - the glow goes out on a frame without a new point;
  - a trail with no points is freed after 3 s idle.
- **Restarts:** an owner not drawn for more than 3 frames drops its trail (it ages out) and starts a new one. A full
  missile trail starts a new one; a full wingtip trail just stops adding (quirk).
- **Limit:** at most 99 trails. Create refuses at count + 1 ≥ 100, and the owner retries.
- **Drawing** `415b30`: each segment is **two crossed quads**, fixed in the world (they do not turn to face the
  camera):
  - one horizontal, offset ± w perpendicular to the averaged horizontal heading of the neighbouring segments;
  - one vertical, ± w along world up.
- **Width:** w is a half-width in world units. w = size at the newest point. The newest ≈ 15 % of the points widen by
  growth · size · 4.5 each. The older 85 % (k = ftol(0.85 · n)) taper linearly to 0 at the oldest.
- **Texture** trail.tga: 64 × 128, four frames of 64 × 32, white with a soft alpha profile across the width; frame 3
  is the faintest. Frame = ftol(4 · min(age / lifetime, 0.9999)) of the segment's newer point. u runs 0 → 1 along
  each segment, v across. White vertex colour, no z-write. trail.bmp is unused.
- **Motor glow** `415a60` (missiles only, while the trail still grows): missFLR centred at the newest point, size
  (0.85 + (rand % 31) · 0.01) · 1.35 · trail size → 8.8–11.9 m wide, flickering.
- The preference does not gate the damage smoke (§6.3), decoy smoke or explosion smoke.

**Port:**
- `game/mission/trails.gd`: an ImmediateMesh of the crossed quads; the glow is a billboard MultiMesh.
- Owners: `player_weapons.gd` (missiles, rockets), `terrain_view.gd` (the player's wingtips), `ai_flights.gd` (AI
  jets). The flight model exports `vortex`.
- With the preference off, trails are not drawn.
- Blend mode: alpha (UNCERTAIN, the original's is global).

### 6.5 Tgen `.pal` textures
Loader `FUN_00426850` / `FUN_004268d0`:

| offset | content |
|---|---|
| 0..1 | 08 01 (checked) |
| 2..3 | not read (smoke3 0x17 / airexp1 0x0f = their frame counts) |
| +4 | u16 width |
| +6 | u16 height |
| +8 | width × height 16-bit pixels, copied into an alpha surface |

The pixels are ARGB4444 (sprite borders 0x0fff = transparent; UNCERTAIN that the surface is exactly 4444). Converter:
`iaf_tools::gltf::load_pal` (the cloud textures).

## 7. Collisions between units (`FUN_0043c140` → `FUN_0043b340`)
Only **active** colliders test for contact: the player's jet and some weapons. On contact a weapon detonates, and
other units go to level 5 (exploded). So the player's jet and whatever it hits are both destroyed.

**Registration.** The collision manager (`DAT_0069934c`) keeps two hash tables of colliders (entity+0x18,
`FUN_0043bd90`): **active** (+4) and **passive** (+0x20). `FUN_0043b1c0(active)` fills the collider and inserts it.
With `active` = 0 the mask is forced to 0.
- **Every unit at its spawn** (`FUN_004b7634` → `FUN_004b8118` @4b7938) gets a **passive** collider **only when its
  bdb Objects `0x58c` is set**.
  - Source of the flag: `FUN_004be470` reads +0x28 of the type record that `FUN_004c09e0` hands the spawner (its
    +0x24 is the strength). `FUN_00591fd0` / `FUN_0058d390` copy it from the bdb.
  - With `0x58c` = 0 the unit gets no collider (`FUN_0043b330` removes it).
  - `0x58c` = 0 in default6_1.bdb: the shelters **schacha**, hangars **HGR_UL_1 / HGR_UL_2**, **SHK_UL_1**, the
    revetments **datak1 / datak2**, the runways **RWdavid / RWtelnof / RWramon**, the runway lights, bridge2,
    Damesek, the sensor, Crater and the runway signs.
  - So a jet that starts in a shelter (mission 315: 2.1 m from schacha3's centre, inside its 36 m radius) or a
    hangar has nothing to hit and taxis out.
- **The player's jet** becomes **active** at the switch to PLAYER_CONTROLLED (`FUN_004a8e70` @4a8fd7; `FUN_004a9470`
  when the player takes over a jet). Switching away makes it passive again.
- **Active weapons:** the player's missiles (type 0x230, `FUN_004d7690`) and some other weapons (`FUN_004d7f30`,
  `FUN_0043bc30`, `FUN_0054a660`).
- **Removal** (`FUN_0043b330`): an aircraft (classes 1–3, 0x1c) at its final status (`FUN_004a86b0`), and weapons at
  their end. **Nothing else unregisters.** A destroyed building or vehicle (even one whose model vanished, §2.2)
  keeps its collider. So does a hidden unit: trigger op 14 `FUN_00463ec0` only changes the model.

**Collider size** (`FUN_0043b1c0`): radius = 0.25 · (sx + sy + sz) of the normal model's extents (renderer vtable
+0xb0, `DAT_006005b8` = 0.25), stored squared (+0x14).

| class | group | mask (active only) |
|---|---|---|
| aircraft 1, 2, 3, 0x1c | 2 | 0x1b |
| vehicles 5, 6 | 8 | 0 |
| sites 8–0xb, buildings 0xc / 0xd (not type 450: runways, runway lights) | 1 | 0 |
| boats 0xf, 0x10 | 0x10 | 0 |
| weapons 0x16–0x1a | 4 | 0x19 |
| crater 0x1f | 0x20 | 2 |

Other classes (trees, sensors, parachutes) have none, whatever `0x58c` says.

**The test** (`FUN_0043c140`, every frame). For each **active** collider A, check every collider B after it in the
active table and every passive one. A contact needs all of:
- B ≠ A;
- (B.group & A.mask) ≠ 0;
- the **3D** distance of the centres (motion positions, `FUN_0043cb00`) < **B's** radius.

Passive pairs are never tested, so AI aircraft, vehicles and buildings never collide with each other. The player's
jet meets every registered unit in its mask. On contact, A reacts once per frame and each B it touches reacts
(`FUN_0043b340(time, other)`).

**Reaction** (`FUN_0043b340`):
1. Do nothing when the other is a weapon (0x16–0x1a), when this unit is shielded (damage object, `FUN_0058a350`), or
   in network play for a remote unit.
2. Otherwise act by this unit's class:
   - a weapon detonates (`FUN_004d6130`);
   - an AI aircraft, a vehicle, site, building or boat goes to level 5 (a unit already at state 5 stays);
   - the player's jet goes to level 5 unless Invulnerable.

So a jet hitting a building, a vehicle or another aircraft destroys both — and every registered unit within range in
that frame.

**Port** (`terrain_view.gd` `_check_collisions`):
- The player's jet tests every unit with `0x58c` set (`ent.collidable`) whose group is in 0x1b and that is closer
  than its radius (0.25 · the scaled model's full extents).
- Hidden units and wrecks are included; aircraft wrecks are excluded.
- Physics "No collisions with hidden units / wrecks" (`fix_ghost_collision`, ours) skips hidden units and wrecks
  whose model vanished — the original's invisible obstacles.
- The weapons' own colliders are not ported. Weapons use their fuse rules (docs/weapons.md).

## 8. Uncertain / not ported
- The lens-flash texture.
- State 4.
- Radio kill / "is down" calls, FlyTSD 6.5 s after the player's death (campaign), network play.
- The flight model's reaction to the hit shake.
- Collision: full vs half extents (the renderer call behind vtable +0xb0 is not traced).
- Original-vs-better decision for the user: puffs per frame (§6.3). The heading-0 fall and the Rookie / Normal factor
  are already Physics opt-ins (deviations.md §2).
