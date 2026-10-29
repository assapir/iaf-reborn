# Weapon data "Real"

This doc lists the real-world weapon numbers that the *Real weapons* option puts on the original weapon records
(`game/weapons/real_weapons.gd`), and how each number maps onto the original model.

- **Switch:** Preferences > Extras > **Weapon data**: *Original (1998)* (default) or *Real weapons*, separate from
  Flight data.
- **What stays the original's:** a value that no public source gives, and the rules (chase law, gun timer;
  docs/weapons.md). The exceptions are the IR seeker's lock ranges (§1.2), the gun's hit test and the sourced blast
  radii (§1.4).

## 1. Values

### 1.1 Missiles
IR (infrared) missiles, which home on heat:

| bdb name | weight kg (orig. lb → kg) | top speed | range | sources |
|---|---|---|---|---|
| AIM-9D | 88.5 (192 → 87.1) | Mach 2.5 | 18 km | [^1], [^2] |
| AIM-9L | 86 (192 → 87.1) | Mach 2.5 | 17.7 km | [^1], [^f16net], [^navair] |
| AIM-9M | 86 (192 → 87.1) | Mach 2.5 | 17.7 km | [^1], [^f16net], [^navair] |
| PYTH-3 | 120 (264 → 119.7) | Mach 3.5 | 15 km | [^3] |
| PYTH-4 | 120 (340 → 154.2) | Mach 3.5 | 15 km | [^3] |
| SHFR 2 | 93 (209 → 94.8) | Mach 2.1 | 5 km | [^3], [^4] |

The AIM-9L / M range is the published 10–18 miles[^navair] at its F-16.net value, 17.7 km[^f16net]. The 35.4 km
(22 mi) maximum that Wikipedia gives is marked "not verified in body"[^2]; inferred: it is a head-on maximum at
high altitude, not the zone a medium-altitude HUD shows. The AIM-9D's turn limit is 12 g[^1].

Radar, anti-radiation and TV missiles (600, 610, 590, 635):

| bdb name | weight kg | top speed | range | sources |
|---|---|---|---|---|
| AMRAAM (AIM-120A/B) | 157 | Mach 4 | 70 km (50–70 km) | [^15] |
| AIM-7M | 230 | Mach 4 | 70 km | [^16] |
| AIM-7F | 230 | Mach 4 | 70 km | [^16] |
| AIM-7B | 176 (UNCERTAIN) | Mach 2.5 | 7 km (UNCERTAIN) | [^16] |
| AGM88 (AGM-88A/B/C HARM) | 360 | Mach 2 (Mach 2+) | 150 km | [^17] |
| SHRIKE (AGM-45B) | 177 | Mach 2 | 40 km | [^18] |
| AGM-65 (AGM-65A/B) | 209 | the original top speed (sources say only "supersonic") | 27 km (">27 km") | [^19] |

These values keep the original, because no public figure was found:
- the other missiles' g limits;
- warhead power (game damage units), and the radius of a weapon without a published lethal radius (§1.4);
- drag index.

### 1.2 IR seeker lock
Real lock ranges are classified[^navyff]; the ranges below come from game and simulator sources. With Real, the seeker
locks a target by its aspect and its afterburner, in place of the generation's range R (docs/weapons.md §5.1):
- **Rear sector:** the target's velocity within 60° of the line of sight from you (inferred), so it flies away from
  you. The seeker locks within the rear range; beyond half of it, only a target with its afterburner lit (the
  original's R/2 rule). A target that holds still counts as front.
- **Front:** within the front range; the AB range when the target's afterburner is lit. "–" = no front lock, a
  rear-aspect seeker.
- **Cone:** the gimbal limit, in place of the generation's cone.

| bdb name | rear | front | front, AB | cone | sources |
|---|---|---|---|---|---|
| AIM-9D | 11 km | – | – | 40° | rear-aspect[^1]; cone[^edf] |
| AIM-9L / M | 11 km | 3 km | 8.5 km | 40° | ranges[^wt][^edf]; cone[^hb14] |
| PYTH-3 | 11 km | 3 km | 8.5 km | 30° | ranges inferred: the AIM-9L's; cone[^12][^wsP3] |
| PYTH-4 | 16 km | 4.5 km | 12.7 km | 60° | ranges inferred: 1.5 × the AIM-9L's, "significantly better acquisition range than the AIM-9M"[^13]; cone[^13][^fl96] |
| SHFR 2 | 6 km | – | – | 10° | rear-aspect, cone[^wsS]; range inferred from its 6.4 km maximum[^wsS] |

Open: the rear-sector range against an afterburning target past the rear range.

A real jet shows SHOOT only when the seeker tracks the target and the range is between Rmin and Rmax (simulator
documentation[^vrs][^hoggit]; no primary F-16 source was found). So a target inside the zone but outside the lock
range shows no SHOOT, as in the game.

### 1.3 Radar
| jet | radar | detection range | sources |
|---|---|---|---|
| F-16 (Barak) | AN/APG-68 | 80 km (43.1 NM, LRS / STT) | [^14] |
| F-15 (Baz) | AN/APG-63 | 135 km (U: 110–160 km tracking a small fighter; ~100 NM velocity search) | forecastinternational.com APG-63 report, cmano-db |
| F-4E (Kurnass) | AN/APQ-120 | 61 km (33 NM: average 30–35 NM, max 40 NM at 15–30k ft) | flyandwire.com, secretprojects.co.uk (test reports) |
| Kurnass 2000 | AN/APG-76 | 44 km (U: 22–25 NM frontal, one forum source) | key.aero forum |
| Lavi | EL/M-2035 (from the EL/M-2021B) | 46 km (tracks several targets at 46 km in five air-to-air modes) | aviationsmilitaires.net (EL/M-2035), Jewish Virtual Library (IAI Lavi) |
| Kfir C7 | EL/M-2001B ranging radar (no search mode) | 14.8 km (U: one database) | Wikipedia "IAI Kfir" (radar type), cmano-db.com (range) |
| Mirage IIICJ | Cyrano I bis | 27 km (U: nominal air-to-air lock, one game wiki; the later Cyrano II ~30 km) | War Thunder wiki (Mirage IIIC), migflug.com (Cyrano II) |
| F-35I (Adir, ours) | AN/APG-81 | 148 km (U: multiple-target track beyond 80 NM) | docs/f35i.md |

U marks an uncertain figure. LRS is long-range search; STT is single-target track. The table is keyed by aircraft type
(`RADAR_KM`, like `GUN_ROUNDS`), so a new jet needs only its own row.

### 1.4 Hit volumes
**Gun** (`real_hit`, crates/iaf-avionics/src/gun.rs; every gun round, type 565: the player's, the AI jets' and the
AAA's). A round hits a candidate when the segment it flew since the last 0.1 s check passes within

  r = (the target's half-span + 0.004 · range) · (2 with Easy aiming)

of the candidate's origin. The blast then goes off at that origin (a contact hit), with the original power and radius.
The original tests the round's point against a 25 m sphere (50 m with Easy aiming) at each check (docs/weapons.md
§3.4).

- **0.004 · range:** the M61A1 puts 80 % of its rounds inside an 8 mrad circle (diameter)[^gdots], a 4 mrad radius:
  2 m at 500 m, 4 m at 1000 m. The DEFA's dispersion is open; it uses the same value (inferred).
- **Half-span:** US 20 mm HEI uses the M505 point-detonating fuze, which fires on impact[^m505], so a round damages
  only by striking the airframe. The target's half-span is half the X extent (across the wings) of its drawn model
  (`gun_rounds.gd` `half_span_of`): in World scale Real the true size (an F-16 4.98 m[^f16], a MiG-21 3.58 m[^mig21],
  a MiG-29 5.68 m[^mig29], a MiG-23 6.99 m spread / 3.89 m swept[^mig23]); in World scale Original the model at its
  Present scale, ×2 for most jets (the MiG-23's model: 6.0 m, drawn 12.0 m). The hit volume follows what the player
  sees, so a round that visibly passes through a wing hits (inferred). A ground unit's half-span is half its width.
- **The swept segment:** a round flies about 145 m per check, so a point test would step over a 5–8 m target almost
  always.
- **Easy aiming ×2:** ours, as the original doubles its sphere with Easy aiming.
- At 500 m an F-16 is hit within 7.0 m of its origin, a MiG-21 within 5.6 m (the original: 25 m).

**Blast radii** (`LETHAL_M`, `blast_radius` in real_weapons.gd). The blast formula's radius R (bdb `0x74e`) is the
zero-damage edge, not a lethal radius (docs/damage.md §4.1): on one axis the damage is P · (1 − d / R), with
d = the distance less the unit's size s (2.5 m for almost every unit). Real keeps the power P and sets R so that one
hit destroys a fighter (strength S = 300, the F-16's) within the real lethal radius L of its origin on one axis:

  R = (L − s) / (1 − S / P); R = L when P ≤ S (one hit never destroys a fighter on its own, in the original too)

This rule is ours (inferred). Only the weapons with a published lethal radius change:

| bdb | P | lethal radius L | R (orig.) | source |
|---|---|---|---|---|
| SA2 (S-75 V-750) | 300 | 65 m at low altitude, up to 250 m high | 65 (40) | [^s75] |
| SA3 (S-125 V-601) | 250 | 12.5 m (one secondary source, weak) | 12.5 (30) | [^armsnet] |
| SA8 (9K33 Osa) | 200 | 5 m at low altitude against an F-4-size target | 5 (40) | [^osa] |
| AA-2 (R-3S) | 200 | hits within 10 m (fuze detection 9 m) | 10 (10) | [^polot] |
| AA-8 (R-60) | 200 | about 2.5 m (news sources) | 2.5 (15) | [^liga] |
| AIM-7B | 400 | kill radius 40 ft (12 m), variant not given | 38 (30) | [^fw] |
| AIM-7F | 300 | as AIM-7B | 12 (30) | [^fw] |
| AIM-7M | 500 | as AIM-7B | 23.75 (20) | [^fw] |

- The AIM-7 rows show the rule's step at P = S: the same 12 m gives 12 m for the AIM-7F (P 300) and 23.75 m for the
  AIM-7M (P 500), since only a warhead stronger than the fighter destroys it in one hit.
- The AIM-9A / B's "effective kill radius about 9 m"[^1] is for a 4.5 kg warhead; the game has the AIM-9D / L / M,
  which keep the original's radius, as do every other missile and SAM without a published value (Python, Shafrir,
  R-73, R-40, R-27, AMRAAM, SA-5, SA-6, SA-13, Hawk) and the bombs (their original radii are already near the real
  ones).

### 1.5 Guns
| gun (bdb) | rate | muzzle velocity | rounds per jet | sources |
|---|---|---|---|---|
| "20 MM" (M61A1) | 6000 rpm | 1030 m/s (M56 HEI) | F-16 511, F-15 940, F-4E / Kurnass 2000 639 | [^5], [^6], [^7], [^8] |
| "DEFA" (552 / 553, 2 guns) | 2 × 1300 rpm | 815 m/s | Kfir C7 2 × 140, Mirage IIICJ 2 × 125 | [^9], [^10] |
| "20 MM" standing in for the GAU-22/A 25 mm | the 20 MM record | the 20 MM record | F-35I 180 (ours) | docs/f35i.md |
| GSh-30-1 (the MiG-29 fires the "20 MM" record) | 1650 rpm (1500–1800; the middle, inferred) | 860 m/s | MiG-29 150 | [^gsh30], [^mig29] |
| GSh-23L (the MiG-23 fires the "20 MM" record) | 3400 rpm (3400–3600) | 715 m/s | MiG-23 200 | [^gsh23], [^mig23] |

The MiGs fly the F-16's "20 MM" record. With Weapon data Real they fire their own gun's rate and speed instead
(`real_weapons.gd` `JET_GUNS`, per jet type code), so the MiG-29's Real HUD funnel (860 m/s, real-hud.md) lies on its
rounds' path. The record's damage stays: no per-round value is published.

The Lavi's real gun was a 30 mm DEFA[^11]; the game gives it the "20 MM". Its round count is unpublished, so the Lavi
keeps the original gun and count.

### 1.6 The modern weapons (ours)

New records (docs/weapons.md §13) for the F-16I Sufa and the F-35I, and with Extras "Weapons" on Modern for the jets of
§1.7, with these values under both Weapon data settings: the 1998
data has none. Israel bought 600 AIM-9X-2 Block II missiles (US notice of July 2014)[^isr9x]; the Sufa's JDAMs and
Python 5: docs/f16i.md §5; the F-16I has carried the SDB since August 2015 (107 Squadron, the first F-16I unit)[^sdbf16i].

| record | weight | top speed | range | seeker / kit | sources |
|---|---|---|---|---|---|
| AIM-9X (Block II) | 85 kg | Mach 2.5 (inferred: the Sidewinder family's "Mach 2.5+") | 17.7 km (inferred: the AIM-9M's; open) | imaging IR, 90° off boresight, thrust-vector control for 60 g, LOAL | [^ds9x], [^2] |
| PYTH-5 | 105 kg | Mach 4 | 20 km ("> 20 km") | imaging IR and electro-optical, LOAL up to 100° off boresight | [^3] |
| GBU-31 (Mk 84) | 946 kg | – | 24 km | GPS / INS | [^dsjdam], [^jdam] |
| GBU-31(V)3 (BLU-109) | 981 kg | – | 24 km | GPS / INS | [^dsjdam] |
| GBU-32 (Mk 83) | 468 kg | – | 24 km | GPS / INS | [^dsjdam] |
| GBU-38 (Mk 82) | 253 kg | – | 24 km | GPS / INS | [^dsjdam] |
| GBU-39 SDB | 129 kg | – | 111 km ("over 60 nmi") | GPS / INS, wings; four on a BRU-61 rack | [^sdb] |

- **Weights** are the records' bdb weight (0x758) in whole pounds.
- **Missiles**: speed and range set β and the burn as §2 does. Inferred: the motor's acceleration 600 m/s² (so a
  steady 61 g across the velocity; the AIM-9X is held to its published 60 g) and 0.05 s before it steers, for the
  thrust-vector control; the lock ranges (§1.2) the Python 4's for the AIM-9X (rear 16 km, front 4.5 / 12.7 km), and
  1.25 × that for the Python 5 (20 / 6 / 16 km), as no seeker range is published. The blast is the AIM-9M's (the AIM-9X
  keeps its 9.4 kg WDU-17/B warhead[^ds9x]); the Python 5's is the Python 4's (its warhead 11 kg[^3]; inferred: the
  same class).
- **JDAM range**: designation-systems gives 8–24 km "from typical operating altitudes"[^dsjdam]; Wikipedia "up to 15
  nautical miles (28 km)" and 13 nmi (24 km) in its table[^jdam]. The kit's glide ratio 1.6 makes the 24 km from
  40,000 ft at Mach 0.9 (inferred conditions; docs/weapons.md §13.2). The 3 g turn, the 150 m/s slowest and 300 m/s
  fastest speeds: inferred.
- **GBU-39 range**: "over 60 nmi" air-dropped[^sdb]: glide ratio 7.6 from the same release. Weight: the spec box's
  129 kg (the lead says 250 lb, 110 kg[^sdb]).
- **Blast**: the bomb's own record (Mk 84 / 83 / 82). The BLU-109 holds 250 kg of tritonal[^blu109], the GBU-39 16 kg
  of AFX-757[^sdb], against the Mk 84's 429 kg[^mk84]: their power is the MK-84's × fill / 429, the radius × the cube
  root of that (inferred).
- **Accuracy**: a JDAM with GPS has a 5 m CEP[^jdam] (13 m official, about 10 m in use[^dsjdam]), the GBU-39 1 m[^sdb];
  the game's bomb lands on its aim (not modelled).

Not added (docs/f16i.md §5):
- **SPICE 1000 / 2000**: the IAF fielded the SPICE 1000 on the F-16C/D first; its F-16I use was planned for the Ramon
  squadrons in 2017[^spice1000]; no source shows the SPICE 2000 on the F-16I. Its electro-optical scene matching would
  be a new seeker rule. Open, a follow-up.
- **GBU-28**: no source puts it on the F-16I (Israel's carrier is the F-15I, inferred).
- **Laser JDAM (GBU-54)**: Israel co-developed the laser seeker with Elbit[^jdam]; its use on the F-16I: open.

### 1.7 Which jet carried which modern weapon

With Extras "Weapons" on Modern a jet lists a modern weapon when a public source shows the jet carrying it: the IAF's
jet, or the same jet type in another air force. No source: not offered. "Open": only weak sources, or the source does
not name the variant; not offered either. The F-16I Sufa always has all seven (§1.6, docs/f16i.md §5) and the F-35I
always has its own, whatever the switch. Research of 29 October 2026.

| weapon | F-16D Barak (100) | F-15 Baz (110) | F-4E / Kurnass 2000 (120 / 200) | Kfir (130) | Lavi (140) | Mirage (190) | F-35I (1000) |
|---|---|---|---|---|---|---|---|
| AIM-9X | yes: USAF F-16C/D[^afm9x][^kunsan] | yes: USAF F-15C, first operational shot 2004[^afm9x][^acc9x] | no source | no source | no source | no source | yes: IAF F-35I[^janes35]; F-35A outboard pylons[^dt35] |
| PYTH-5 | yes: IAF F-16 (first combat kill 2006)[^f16py5] | open: Python 4 or 5 unclear[^twzbaz] | open: Turkish F-4E 2020, a forum only | open: Colombian Kfir C10 / C12, weak sources | no source | no source | open: integration not complete[^janes35] |
| GBU-31 | yes: IAF F-16C/D (Boeing integrated the JDAM on Peace Marble II / III, the Block 30 Barak and Block 40 Brakeet, from 2000, the first export JDAM sale[^boe00]; the IAF fielded it in 2003[^iaf03]; four per jet in 2023[^avi23]); USAF Block 30s in 2003[^aftc03] | yes: IAF Baz[^avi23][^twzbaz] | no source | no source | no source | no source | yes: F-35A internal[^dt35]; IAF F-35I[^avi23] |
| GBU-31V3 | open | open | no source | no source | no source | no source | open |
| GBU-32 | open: listed for the F-16C/D by one source[^afmjdam], not by another | no source | no source | no source | no source | no source | yes: F-35A[^afmjdam] |
| GBU-38 | yes: USAF F-16[^afmjdam] | no source (the F-15E's) | no source | no source | no source | no source | open: a 2011 Lockheed chart only |
| GBU-39 | yes: USAF F-16 (Block 30/40/50 integration, 8 on BRU-61 racks)[^ar39] | no source (the F-15E's) | no source | no source | no source | no source | yes: F-35A internal, RNLAF and RAAF[^raaf39] |

Stations (`modern_weapons.gd` `LOADS`; letters A–I are the Arming screen's stations 1–9):
- **Barak**: AIM-9X and Python 5 on A, B, C, G, H, I, where the F-16 carries its AIM-9L (inferred: no official
  station list). GBU-31 and GBU-38 on C, D, F, G: the IAF's F-16s load JDAMs on the inner wing pylons as well as the
  standard heavy ones[^avi23]. GBU-39 four to a rack on C / G (inferred from the eight on two racks[^ar39]).
- **F-15**: AIM-9X two to a wing pylon on A / I, as its AIM-9L; GBU-31 on B, E, H, the wing pylons and the centreline
  ("three GBU-31(V)1 JDAM bombs, loaded on the centerline and wing stations"[^avi23]).
- **F-35I** (docs/f35i.md §3.1): AIM-9X on the outboard pylons A / I[^dt35]; GBU-31 and GBU-32 in the bays C / G and on
  the heavy pylons B / H; GBU-39 four to a bay on C / G[^raaf39].

## 2. Mapping onto the original's model
Each real value lands in one field or rule of the original model:

- **Weight:** bdb `0x758` (lb) = kg / 0.45359. It feeds the stores weight (docs/weapons.md §2.5). Under the original
  stores-weight rules the value still goes into the kg field; the Physics option "Stores weight fix" makes it right.
- **Top speed:** the chase motion's steady speed is `_absAcceleration / _spiralAccelBeta` (docs/weapons.md §5.3).
  Real keeps a, because there is no public g limit, and sets β = a / (Mach · 340.3 m/s, sea level). AIM-9L:
  100 / 851 = 0.1175 (orig. 0.08 → 1250 m/s). A record without a public speed (AGM-65) keeps its a / β; only the
  range sets its burn.
- **Range:** the flight ends burn + 6 s after launch, for every homing weapon (docs/weapons.md §11). The motor pushes
  a − β·v for the whole flight, so the missile starts at the launch speed and only approaches its top speed V = a / β.
  The distance it flies in t seconds from speed s is V·t + (s − V)·(1 − e^(−βt)) / β (`ChaseMotion::travelled`).
  Real sets the burn so that this distance, from a 250 m/s launch, equals the published range (`real_burn`, at
  least 1 s): AIM-9L 20.5 s (orig. 16), Python 3 14.3 s, Python 4 12.6 s, Shafrir 2 3.7 s, AIM-7B 7.7 s,
  AMRAAM 54.6 s.
- **Launch zone (DLZ):** the original's maximum, flown(|V| − away, burn − 2) (docs/weapons.md §11.2), is a quadratic
  tuned for the 1998 records. With the Real speeds and burns it errs both ways (Python 3 / 4 about 1.8 km against a
  still target, AIM-7B and Shafrir 2 no zone; AIM-9L and AMRAAM beyond what they fly). With Real the maximum is the
  distance the missile flies in its flight less the original's 2 s margin, minus the target's travel away from you:
  travelled(|V|, burn + 4) − away·(burn + 4). The minimum keeps the original rule. Against a still target from
  250 m/s: AIM-9D 16.3 km, AIM-9L 16.1 km, Python 3 13.0 km, Python 4 12.9 km, Shafrir 2 3.7 km, AIM-7B 5.7 km,
  AIM-7M / AMRAAM 67.3 km. The AI's launch range uses the same zone.
- **Lock ranges** (ours; the original tracks from any aspect within R): §1.2, `Seeker::can_track` with `RealLock`
  (crates/iaf-avionics/src/sight.rs).
- **Seeker cone:** replaces the per-generation cone, the half-angle of the seeker slaved to a radar lock
  (docs/radar.md §6) or to the helmet (docs/weapons.md §5.4). The 6° view keeps its original value.
- **Turn limit:** each 0.1 s chase update clamps the acceleration across the velocity to g · 9.80665 m/s².
- **Radar:** the LRS (and so STT) detection NM = km · 1000 / 1854.
- **Guns:** the station holds the real rounds and shows them 1:1 (orig. ×4 / ×2). The 0.2 s shot tick fires
  rate · 0.2 s rounds (M61A1 20, two DEFA 8.67). The round's `_velocityJump` / `_limitVel` = the muzzle velocity.
  The hit test is §1.4's.
- **Blast radius:** bdb `0x74e` from the lethal radius (§1.4).

## 3. Validation
| test | checks |
|---|---|
| `tests/godot/test_weapons.gd` | AIM-9L 86 kg; F-16 511 rounds shown; one M61A1 tick = 20 rounds; the derived chase values (stored in the record's `motion`): AIM-9L top speed a/β = 851 m/s = Mach 2.5, the distance flown in burn + 6 s from 250 m/s = 17.7 km; its DLZ against a still target between 15 and 17.7 km; the AIM-9D / Python 4 flags; the AIM-9D seeker refuses a head-on target; the AIM-9L locks head-on at 2 km, not at 5 km without afterburner; the AIM-9D 12 g clamp; the §1.4 blast radii (only the sourced ones, only with Real); the real gun hit test (a 5 m half-span 8 m off the line at 1070 m hit, a 2 m one missed); the MiG-23's drawn half-span in 231 |
| `crates/iaf-avionics/src/gun.rs` `real_hits_sweep_the_path_between_checks` | a fighter 5 m off the line between two checks is hit, 10 m off missed, 10 m with Easy aiming hit; a point test steps over it |
| `tests/godot/test_radar.gd` | the F-16's 80 km |
| `tests/godot/test_radar_missiles.gd` | the AMRAAM's 157 kg, a/β = Mach 4 and the distance flown in burn + 6 s from 250 m/s = 70 km; the AIM-7B's DLZ against a still target about 5.7 km (not empty) |
| `crates/iaf-avionics/src/sight.rs` `real_rear_sector`, `real_front_mil_ab_and_none`, `original_range_and_aspect` | the §1.2 rules: rear range and its R/2 afterburner rule, the 60° sector, front with / without afterburner, no front lock, the original unchanged |
| `crates/iaf-avionics/src/missile.rs` `dlz_per_missile_original_and_real` | the original DLZ of each air-to-air missile; with Real: the burn flies the published range, the zone is not empty, a launch at its maximum reaches a still target and none flies past 1.05 × its range |

## Sources
[^1]: designation-systems.net, "Raytheon AIM-9 Sidewinder", https://www.designation-systems.net/dusrm/m-9.html (AIM-9D 88 kg, 18 km, Mach 2.5+, rear-aspect, 12 g; AIM-9L / M 86 kg; AIM-9A / B effective kill radius about 9 m).
[^2]: Wikipedia, "AIM-9 Sidewinder", https://en.wikipedia.org/wiki/AIM-9_Sidewinder (AIM-9D 88.5 kg; AIM-9L / M 86 kg, Mach 2.5+, range 1.0–35.4 km, "not verified in body"; AIM-9X: "claimed 90° off-boresight capability", two-axis thrust-vector control for 60 g, an imaging IR seeker, Block II lock-on after launch).
[^3]: Wikipedia, "Python (missile)", https://en.wikipedia.org/wiki/Python_(missile) (Shafrir 2 93 kg, Mach 2.1, 5 km; Python 3 120 kg, Mach 3.5, 15 km; Python 4 120 kg, Mach 3.5+, 15 km; Python 5 105 kg, Mach 4, > 20 km, lock-on after launch up to 100° off boresight, an electro-optical and imaging IR seeker, 11 kg warhead).
[^4]: Wikipedia, "Shafrir (missile)", https://en.wikipedia.org/wiki/Shafrir_(missile).
[^5]: Wikipedia, "M61 Vulcan", https://en.wikipedia.org/wiki/M61_Vulcan (6000 rpm; M56 1030 m/s).
[^6]: General Dynamics OTS, "F-16 20mm Gatling gun system", https://www.gd-ots.com/wp-content/uploads/2017/11/F-16.pdf (511 rounds).
[^7]: US Air Force, F-15 Eagle fact sheet (M61A1 with 940 rounds), https://www.airmanmagazine.af.mil/ImageGallery/igphoto/2002820144/.
[^8]: aerospaceweb.org, "F-4 Phantom II", https://aerospaceweb.org/aircraft/fighter/f4 (M61A1 with 639 rounds).
[^9]: Wikipedia, "DEFA cannon", https://en.wikipedia.org/wiki/DEFA_cannon (DEFA 553 1300 rpm, 765–815 m/s; Mirage III 125–135 rounds per gun).
[^10]: Wikipedia, "IAI Kfir" (C.7: 2 × DEFA 553 with 140 rounds per gun), https://en.wikipedia.org/wiki/IAI_Kfir.
[^11]: Wikipedia, "IAI Lavi" (1 × 30 mm DEFA), https://en.wikipedia.org/wiki/IAI_Lavi.
[^12]: Hebrew Wikipedia, Python 3 article (up to 30° off the firing line).
[^13]: Air Power Australia, "Fourth Generation AAMs", https://www.ausairpower.net/TE-Gen-4-AAM-97.html (Python 4 > 60° off-boresight, "significantly better acquisition range than the AIM-9M").
[^14]: Wikipedia, "AN/APG-68", https://en.wikipedia.org/wiki/AN/APG-68 (80 km maximum detection).
[^15]: designation-systems.net, "Raytheon AIM-120 AMRAAM", https://www.designation-systems.net/dusrm/m-120.html (AIM-120A/B 157 kg, Mach 4, 50–70 km).
[^16]: Wikipedia, "AIM-7 Sparrow", https://en.wikipedia.org/wiki/AIM-7_Sparrow (AIM-7F / M 230 kg, Mach 4, 70 km; AIM-7B 176 kg, Mach 2.5, 7 km: both UNCERTAIN, early-variant figures).
[^17]: designation-systems.net, "Texas Instruments AGM-88 HARM", https://www.designation-systems.net/dusrm/m-88.html (AGM-88A/B/C 360 kg, Mach 2+, 150 km).
[^18]: designation-systems.net, "Texas Instruments AGM-45 Shrike", https://www.designation-systems.net/dusrm/m-45.html (AGM-45B 177 kg, Mach 2, 40 km).
[^19]: designation-systems.net, "Hughes AGM-65 Maverick", https://www.designation-systems.net/dusrm/m-65.html (AGM-65A/B 209 kg, > 27 km, "supersonic").

[^navyff]: US Navy, "AIM-9 Sidewinder Missile" fact file (range "classified"), https://www.navy.mil/Resources/Fact-Files/Display-FactFiles/Article/2168989/aim-9-sidewinder-missile
[^navair]: NAVAIR, "AIM-9M Sidewinder" (range 10–18 miles), https://www.navair.navy.mil/product/AIM-9M-Sidewinder
[^f16net]: F-16.net, "AIM-9 Sidewinder" (AIM-9L / M / P 17.7 km), https://www.f-16.net/f-16_armament_article1.html
[^fl96]: Flight International, "Rafael's agile constrictor", 9 October 1996 (Python 4 60° and more), https://flightglobal.com/rafaels-agile-constrictor/4030.article
[^wsP3]: weaponsystems.net, "Python 3" (30° acquisition, 40° tracking), https://weaponsystems.net/system/1194-Python+3
[^wsS]: weaponsystems.net, "Shafrir" (10°, 6.4 km, rear aspect), https://weaponsystems.net/system/1193-Shafrir
[^wt]: War Thunder wiki, "AIM-9L Sidewinder" (about 11 km rear, 3 km front; a game), https://old-wiki.warthunder.com/AIM-9L_Sidewinder
[^edf]: ED Forums, "The AIM-9 Sidewinder missile – technology, history and performance" (3 km frontal, 8.5 km against afterburner, AIM-9D 40°; a forum), https://forum.dcs.world/topic/267478-the-aim-9-sidewinder-missile-technology-history-and-performance/
[^hb14]: Heatblur, F-14 manual, AIM-9 page (40° seeker limit; a simulator; the page now returns 404), https://f14.manuals.heatblur.se/stores/air_to_air/aim_9.html
[^vrs]: VRS Superbug wiki, "AIM-9 Sidewinder" (a simulator), https://forums.vrsimulations.com/support/index.php/AIM-9_Sidewinder
[^hoggit]: Hoggit wiki, "F/A-18C" (a simulator), https://wiki.hoggitworld.com/view/F/A-18C

[^gdots]: General Dynamics OTS, "20mm M61A1/M61A2 Gatling Gun" data sheet (dispersion 8 mrad diameter, 80 % circle):
    https://gd-ots.com/wp-content/uploads/2024/11/400003097-20mm-M61A1-M61A2-Gatling-Gun.pdf
[^m505]: Bulletpicker, "PD M505A3" (point-detonating, functions on impact; for 20 mm HEI against aircraft):
    https://bulletpicker.com/pd_-m505a3.html
[^f16]: Wikipedia, "General Dynamics F-16 Fighting Falcon": https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon
[^mig21]: Wikipedia, "Mikoyan-Gurevich MiG-21" (span 7.15 m): https://en.wikipedia.org/wiki/Mikoyan-Gurevich_MiG-21
[^mig29]: Wikipedia, "Mikoyan MiG-29" (span 11.36 m): https://en.wikipedia.org/wiki/Mikoyan_MiG-29
[^mig23]: Wikipedia, "Mikoyan-Gurevich MiG-23" (span 13.97 m spread, 7.78 m swept): https://en.wikipedia.org/wiki/Mikoyan-Gurevich_MiG-23
[^fw]: Fly and Wire, "Unsung hero: the AIM-7 Sparrow, part I" (citing P-825; kill radius 40 ft):
    https://flyandwire.com/2022/10/05/unsung-hero-the-aim-7-sparrow-part-i/
[^polot]: Polot.net, "R-3, R-13M guided missile" (1000 fragments, hit radius 10 m; fuze detection 9 m): https://polot.net/?p=3936
[^liga]: LIGA.net, on R-60 dummies (non-contact fuze, destruction within ≈2.5 m):
    https://news.liga.net/en/amp/war/news/russia-starts-firing-drones-with-dummy-close-combat-missiles---photos
[^s75]: Wikipedia, "S-75 Dvina": https://en.wikipedia.org/wiki/S-75_Dvina
[^armsnet]: Armsnet, S-125 data (kill radius 12.5 m): https://armsnet.duckdns.org/equipment/f689b32c-5770-4c4c-e5d6-08de6e3c1543
[^osa]: Wikipedia, "9K33 Osa": https://en.wikipedia.org/wiki/9K33_Osa
[^gsh30]: Wikipedia, "Gryazev-Shipunov GSh-30-1" (1500–1800 rpm, muzzle velocity 860 m/s),
    https://en.wikipedia.org/wiki/Gryazev-Shipunov_GSh-30-1
[^mig29]: Wikipedia, "Mikoyan MiG-29" (1 × GSh-30-1 with 150 rounds), https://en.wikipedia.org/wiki/Mikoyan_MiG-29
[^gsh23]: Wikipedia, "Gryazev-Shipunov GSh-23" (GSh-23L 3400–3600 rpm, muzzle velocity 715 m/s),
    https://en.wikipedia.org/wiki/Gryazev-Shipunov_GSh-23
[^mig23]: Wikipedia, "Mikoyan-Gurevich MiG-23" (1 × GSh-23L with 200 rounds),
    https://en.wikipedia.org/wiki/Mikoyan-Gurevich_MiG-23
[^isr9x]: Federal Register, 23 July 2014, arms sales notification 14-21 (Israel, up to 600 AIM-9X-2 Sidewinder Block II
    all-up-round missiles), https://www.govinfo.gov/content/pkg/FR-2014-07-23/pdf/2014-17308.pdf
[^sdbf16i]: Army Recognition, "Israeli Air Force F-16I fighter aircraft start using advanced Small Diameter Bombs",
    August 2015 (the IAF's announcement of 18 August 2015; 107 Squadron),
    https://www.armyrecognition.com/archives/archives-aerospace-defense/aerospace-defense-2015/israeli-air-force-f-16i-fighter-aircraft-start-using-advanced-small-diameter-bombs
[^ds9x]: designation-systems.net, "Raytheon AIM-9 Sidewinder" (AIM-9X 85 kg, WDU-17/B 9.4 kg warhead, the jet-vane
    steering of the WPU-17/B), https://www.designation-systems.net/dusrm/m-9.html
[^dsjdam]: designation-systems.net, "JDAM" (GBU-31(V)2/B 946 kg, (V)4/B with the BLU-109 981 kg, GBU-32(V)2/B 468 kg,
    GBU-38(V)1/B 253 kg; 8–24 km; CEP 13 m official, about 10 m), https://www.designation-systems.net/dusrm/app5/jdam.html
[^jdam]: Wikipedia, "Joint Direct Attack Munition" (up to 15 nmi; 5 m CEP with GPS; Israel an operator; the laser JDAM's
    seeker co-developed with Elbit), https://en.wikipedia.org/wiki/Joint_Direct_Attack_Munition
[^sdb]: Wikipedia, "GBU-39 Small Diameter Bomb" (129 kg, 16 kg AFX-757, over 60 nmi, 1 m CEP, four on a BRU-61/A),
    https://en.wikipedia.org/wiki/GBU-39_Small_Diameter_Bomb
[^blu109]: Wikipedia, "BLU-109 bomb" (550 lb, 250 kg of tritonal), https://en.wikipedia.org/wiki/BLU-109_bomb
[^mk84]: Wikipedia, "Mark 84 bomb" (945 lb, 429 kg of tritonal), https://en.wikipedia.org/wiki/Mark_84_bomb
[^spice1000]: Airforce Technology, "IAF's SPICE 1000 munition attains IOC for use on F-16C/D aircraft" (the Ramon F-16I
    squadrons next), https://www.airforce-technology.com/news/iafs-spice-1000-munition-attains-ioc-use-f-16c-d-aircraft/
[^afm9x]: Air & Space Forces Magazine, "AIM-9 Sidewinder" (AIM-9X on the F-15C/D/E, F-16C/D, F-22A),
    https://www.airandspaceforces.com/weapons-platforms/aim-9/
[^kunsan]: PACAF, "Kunsan receives great capability with AIM-9X missile" (8th Fighter Wing Block 40 F-16s),
    https://www.pacaf.af.mil/News/Article-Display/Article/596474/
[^acc9x]: Air Combat Command, "AIM-9X makes operational debut" (an F-15C at Tyndall AFB, 17 March 2004),
    https://www.acc.af.mil/News/Article-Display/Article/203198/aim-9x-makes-operational-debut/
[^janes35]: Janes, "Iran conflict 2026: Israeli F-35 claims type's first combat kill against manned aircraft", 4 March
    2026 (the F-35I carries the AIM-9X; Python 5 integration not completed),
    https://www.janes.com/osint-insights/defence-news/defence/iran-conflict-2026-israeli-f-35-claims-types-first-combat-kill-against-manned-aircraft
[^dt35]: DefenceTalk, "F-35A conducts first external weapons test mission", 21 February 2012 (two GBU-31 internal,
    AIM-9X on the outboard wing stations), https://defencetalk.com/f-35a-conducts-first-external-weapons-test-mission-40599
[^f16py5]: F-16.net news, 17 September 2006 (an Israeli F-16's Python 5 kill, 7 August 2006),
    https://www.f-16.net/f-16-news-article1983.html
[^twzbaz]: The War Zone, "These are the best photos of Israeli F-15 Baz Eagles we've ever seen" (a Baz with three
    GBU-31s; Python 4 or 5 not clear), https://www.twz.com/these-are-the-best-photos-of-israeli-f-15-baz-eagles-weve-ever-seen
[^avi23]: The Aviationist, "IAF aircraft in the war with Hamas", 12 October 2023 (F-16 Barak with four GBU-31(V)1, also
    on the inner pylons; F-15 Baz with three GBU-31(V)1 on the centreline and wing stations; F-35I with two GBU-31(V)1),
    https://theaviationist.com/2023/10/12/iaf-aircraft-war-with-hamas/
[^aftc03]: Air Force Test Center, "March 21, 2003: JDAM Urgent Operational Need Testing" (Block 30 F-16 GBU-31 drops),
    https://www.aftc.af.mil/News/On-This-Day-in-Test-History/Article-Display-Test-History/Article/2510618/
[^afmjdam]: Air & Space Forces Magazine, "GBU-31/32/38 JDAM" (carriers by variant),
    https://www.airandspaceforces.com/weapons-platforms/gbu-31-32-38-jdam/
[^ar39]: Army Recognition, "U.S. Central Command reveals how eight GBU-39s give one F-16 greater precision strike
    mass", 2026 (F-16CMs with four or eight GBU-39 on BRU-61/A racks),
    https://www.armyrecognition.com/news/aerospace-news/2026/u-s-central-command-reveals-how-eight-gbu-39-bs-give-one-f-16-greater-precision-strike-mass
[^raaf39]: Australian Defence Magazine, "RAAF F-35As receive Small Diameter Bombs",
    https://australiandefence.com.au/news/raaf-f-35as-receive-small-diameter-bombs
[^boe00]: Boeing news release, "First International JDAM Sale: Boeing to Integrate Weapon on Israeli Aircraft", 1 June
    2000 (a USAF FMS contract to integrate the JDAM on Israeli F-16 Peace Marble II and III aircraft; test kits for the
    Mk 84 warhead), https://boeing.mediaroom.com/2000-06-01-First-International-JDAM-Sale-Boeing-to-Integrate-Weapon-on-Israeli-Aircraft
[^iaf03]: Israeli Air Force, "חיל-האוויר סיים את קליטתן של פצצות מונחות חדשות מסוג JDAM" (the IAF completes the
    introduction of the JDAM), 2003, https://www.iaf.org.il/440-21281-he/IAF.aspx (cited from Hebrew Wikipedia "JDAM",
    which adds that the F-16s were adapted by a software block update; the page refuses automatic fetches)
