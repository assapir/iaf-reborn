# Weapon data "Real"

This doc lists the real-world weapon numbers that the *Real weapons* option puts on the original weapon records, and
how each number maps onto the original model.

- **Switch:** Preferences > Extras > **Weapon data**: *Original (1998)* (default) or *Real weapons*. It is a separate
  switch from Flight data.
- **What it changes:** Real overlays public real-world numbers on the original weapon records
  (`game/weapons/real_weapons.gd`). A value that no public source gives keeps its 1998 value.
- **What stays the same:** the rules (chase law, gun timer, hit spheres) stay the original's (docs/weapons.md). The IR
  seeker's lock ranges follow §1.2.

## 1. Values

### 1.1 IR missiles
IR (infrared) missiles home on heat.

| bdb name | weight kg (orig. lb → kg) | top speed | range | sources |
|---|---|---|---|---|
| AIM-9D | 88.5 (192 → 87.1) | Mach 2.5 | 18 km | [1], [2] |
| AIM-9L | 86 (192 → 87.1) | Mach 2.5 | 17.7 km | [1], [^f16net], [^navair] |
| AIM-9M | 86 (192 → 87.1) | Mach 2.5 | 17.7 km | [1], [^f16net], [^navair] |
| PYTH-3 | 120 (264 → 119.7) | Mach 3.5 | 15 km | [3] |
| PYTH-4 | 120 (340 → 154.2) | Mach 3.5 | 15 km | [3] |
| SHFR 2 | 93 (209 → 94.8) | Mach 2.1 | 5 km | [3], [4] |

The AIM-9L / M range is the published 10–18 miles[^navair] at its F-16.net value, 17.7 km[^f16net]. The 35.4 km
(22 mi) maximum that Wikipedia gives is marked "not verified in body"[^wiki9]; inferred: it is a head-on maximum at
high altitude, not the zone a medium-altitude HUD shows. The AIM-9D's turn limit is 12 g [1].

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
| AIM-9D | 11 km | – | – | 40° | rear-aspect[^dsys]; cone[^edf] |
| AIM-9L / M | 11 km | 3 km | 8.5 km | 40° | ranges[^wt][^edf]; cone[^hb14] |
| PYTH-3 | 11 km | 3 km | 8.5 km | 30° | ranges inferred: the AIM-9L's; cone [12][^wsP3] |
| PYTH-4 | 16 km | 4.5 km | 12.7 km | 60° | ranges inferred: 1.5 × the AIM-9L's, "significantly better acquisition range than the AIM-9M"[^apa97]; cone [13][^fl96] |
| SHFR 2 | 6 km | – | – | 10° | rear-aspect, cone[^wsS]; range inferred from its 6.4 km maximum[^wsS] |

Open: the rear-sector range against an afterburning target past the rear range.

A real jet shows SHOOT only when the seeker tracks the target and the range is between Rmin and Rmax (simulator
documentation[^vrs][^hoggit]; no primary F-16 source was found). So a target inside the zone but outside the lock
range shows no SHOOT, as in the game.

These values keep the original, because no public figure was found:
- the other missiles' g limits;
- warhead power / radius (game damage units);
- drag index.

### 1.1b Radar, anti-radiation and TV missiles (600, 610, 590, 635)
| bdb name | weight kg | top speed | range | sources |
|---|---|---|---|---|
| AMRAAM (AIM-120A/B) | 157 | Mach 4 | 70 km (50–70 km) | [15] |
| AIM-7M | 230 | Mach 4 | 70 km | [16] |
| AIM-7F | 230 | Mach 4 | 70 km | [16] |
| AIM-7B | 176 (UNCERTAIN) | Mach 2.5 | 7 km (UNCERTAIN) | [16] |
| AGM88 (AGM-88A/B/C HARM) | 360 | Mach 2 (Mach 2+) | 150 km | [17] |
| SHRIKE (AGM-45B) | 177 | Mach 2 | 40 km | [18] |
| AGM-65 (AGM-65A/B) | 209 | the original top speed (sources say only "supersonic") | 27 km (">27 km") | [19] |

### 1.2 Guns
| gun (bdb) | rate | muzzle velocity | rounds per jet | sources |
|---|---|---|---|---|
| "20 MM" (M61A1) | 6000 rpm | 1030 m/s (M56 HEI) | F-16 511, F-15 940, F-4E / Kurnass 2000 639 | [5], [6], [7], [8] |
| "DEFA" (552 / 553, 2 guns) | 2 × 1300 rpm | 815 m/s | Kfir C7 2 × 140, Mirage IIICJ 2 × 125 | [9], [10] |
| "20 MM" standing in for the GAU-22/A 25 mm | the 20 MM record | the 20 MM record | F-35I 180 (ours) | docs/f35i.md |

The Lavi's real gun was a 30 mm DEFA [11]; the game gives it the "20 MM". Its round count is unpublished, so the Lavi
keeps the original gun and count.

### 1.3 Radar
| jet | radar | detection range | sources |
|---|---|---|---|
| F-16 (Barak) | AN/APG-68 | 80 km (43.1 NM, LRS / STT) | [14] |
| F-15 (Baz) | AN/APG-63 | 135 km (U: 110–160 km tracking a small fighter; ~100 NM velocity search) | forecastinternational.com APG-63 report, cmano-db |
| F-4E (Kurnass) | AN/APQ-120 | 61 km (33 NM: average 30–35 NM, max 40 NM at 15–30k ft) | flyandwire.com, secretprojects.co.uk (test reports) |
| Kurnass 2000 | AN/APG-76 | 44 km (U: 22–25 NM frontal, one forum source) | key.aero forum |
| Lavi | EL/M-2035 (from the EL/M-2021B) | 46 km (tracks several targets at 46 km in five air-to-air modes) | aviationsmilitaires.net (EL/M-2035), Jewish Virtual Library (IAI Lavi) |
| Kfir C7 | EL/M-2001B ranging radar (no search mode) | 14.8 km (U: one database) | Wikipedia "IAI Kfir" (radar type), cmano-db.com (range) |
| Mirage IIICJ | Cyrano I bis | 27 km (U: nominal air-to-air lock, one game wiki; the later Cyrano II ~30 km) | War Thunder wiki (Mirage IIIC), migflug.com (Cyrano II) |
| F-35I (Adir, ours) | AN/APG-81 | 148 km (U: multiple-target track beyond 80 NM) | docs/f35i.md |

U marks an uncertain figure. LRS is long-range search; STT is single-target track. The table is keyed by aircraft type
(`RADAR_KM`, like `GUN_ROUNDS`), so a new jet needs only its own row.

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
  tuned for the 1998 records. With the Real top speeds and burns it is wrong both ways: it gave the Python 3 / 4 about
  1.8 km against a still target and the AIM-7B and Shafrir 2 no zone at all, and it gave the AIM-9L and AMRAAM more
  range than the missile flies. With Real the maximum is the distance the missile really flies over its flight less
  the original's 2 s margin, minus the target's travel away from you in that time: travelled(|V|, burn + 4) −
  away·(burn + 4). The minimum keeps the original rule. Against a still target from 250 m/s: AIM-9D 16.3 km, AIM-9L
  16.1 km, Python 3 13.0 km, Python 4 12.9 km, Shafrir 2 3.7 km, AIM-7B 5.7 km, AIM-7M / AMRAAM 67.3 km. The AI's
  launch range uses the same zone.
- **Lock ranges** (ours; the original tracks from any aspect within R): §1.2, `Seeker::can_track` with `RealLock`
  (crates/iaf-avionics/src/sight.rs).
- **Seeker cone:** replaces the per-generation cone. This is the half-angle used when the seeker is slaved to a radar
  lock (docs/radar.md §6) or to the helmet (docs/weapons.md §5.4). The 6° view keeps its original value.
- **Turn limit:** each 0.1 s chase update clamps the acceleration across the velocity to g · 9.80665 m/s².
- **Radar:** the LRS (and so STT) detection NM = km · 1000 / 1854.
- **Guns:** the station holds the real rounds and shows them 1:1 (orig. ×4 / ×2). The 0.2 s shot tick fires
  rate · 0.2 s rounds (M61A1 20, two DEFA 8.67). The round's `_velocityJump` / `_limitVel` = the muzzle velocity.

## 3. Validation
| test | checks |
|---|---|
| `tests/godot/test_weapons.gd` | AIM-9L 86 kg; F-16 511 rounds shown; one M61A1 tick = 20 rounds; the derived chase values (stored in the record's `motion`): AIM-9L top speed a/β = 851 m/s = Mach 2.5, the distance flown in burn + 6 s from 250 m/s = 17.7 km; its DLZ against a still target between 15 and 17.7 km; the AIM-9D / Python 4 flags; the AIM-9D seeker refuses a head-on target; the AIM-9L locks head-on at 2 km, not at 5 km without afterburner; the AIM-9D 12 g clamp |
| `tests/godot/test_radar.gd` | the F-16's 80 km |
| `tests/godot/test_radar_missiles.gd` | the AMRAAM's 157 kg, a/β = Mach 4 and the distance flown in burn + 6 s from 250 m/s = 70 km; the AIM-7B's DLZ against a still target about 5.7 km (not empty) |
| `crates/iaf-avionics/src/sight.rs` `real_rear_sector`, `real_front_mil_ab_and_none`, `original_range_and_aspect` | the §1.2 rules: rear range and its R/2 afterburner rule, the 60° sector, front with / without afterburner, no front lock, the original unchanged |
| `crates/iaf-avionics/src/missile.rs` `dlz_per_missile_original_and_real` | the original DLZ of each air-to-air missile; with Real: the burn flies the published range, the zone is not empty, a launch at its maximum reaches a still target and none flies past 1.05 × its range |

## Sources
1. designation-systems.net, "Raytheon AIM-9 Sidewinder", https://www.designation-systems.net/dusrm/m-9.html (AIM-9D
   88 kg, 18 km, Mach 2.5+, rear-aspect, 12 g; AIM-9L / M 86 kg).
2. Wikipedia, "AIM-9 Sidewinder", https://en.wikipedia.org/wiki/AIM-9_Sidewinder (AIM-9D 88.5 kg; AIM-9L / M 86 kg,
   Mach 2.5+, range 1.0–35.4 km).
3. Wikipedia, "Python (missile)", https://en.wikipedia.org/wiki/Python_(missile) (Shafrir 2 93 kg, Mach 2.1, 5 km;
   Python 3 120 kg, Mach 3.5, 15 km; Python 4 120 kg, Mach 3.5+, 15 km).
4. Wikipedia, "Shafrir (missile)", https://en.wikipedia.org/wiki/Shafrir_(missile).
5. Wikipedia, "M61 Vulcan", https://en.wikipedia.org/wiki/M61_Vulcan (6000 rpm; M56 1030 m/s).
6. General Dynamics OTS, "F-16 20mm Gatling gun system", https://www.gd-ots.com/wp-content/uploads/2017/11/F-16.pdf
   (511 rounds).
7. US Air Force, F-15 Eagle fact sheet (M61A1 with 940 rounds),
   https://www.airmanmagazine.af.mil/ImageGallery/igphoto/2002820144/.
8. aerospaceweb.org, "F-4 Phantom II", https://aerospaceweb.org/aircraft/fighter/f4 (M61A1 with 639 rounds).
9. Wikipedia, "DEFA cannon", https://en.wikipedia.org/wiki/DEFA_cannon (DEFA 553 1300 rpm, 765–815 m/s; Mirage III
   125–135 rounds per gun).
10. Wikipedia, "IAI Kfir" (C.7: 2 × DEFA 553 with 140 rounds per gun), https://en.wikipedia.org/wiki/IAI_Kfir.
11. Wikipedia, "IAI Lavi" (1 × 30 mm DEFA), https://en.wikipedia.org/wiki/IAI_Lavi.
12. Hebrew Wikipedia, Python 3 article (up to 30° off the firing line).
13. Air Power Australia, "Fourth Generation AAMs", https://www.ausairpower.net/TE-Gen-4-AAM-97.html (Python 4 > 60°
    off-boresight).
14. Wikipedia, "AN/APG-68", https://en.wikipedia.org/wiki/AN/APG-68 (80 km maximum detection).
15. designation-systems.net, "Raytheon AIM-120 AMRAAM", https://www.designation-systems.net/dusrm/m-120.html (AIM-120A/B
    157 kg, Mach 4, 50–70 km).
16. Wikipedia, "AIM-7 Sparrow", https://en.wikipedia.org/wiki/AIM-7_Sparrow (AIM-7F / M 230 kg, Mach 4, 70 km; AIM-7B
    176 kg, Mach 2.5, 7 km: both UNCERTAIN, early-variant figures).
17. designation-systems.net, "Texas Instruments AGM-88 HARM", https://www.designation-systems.net/dusrm/m-88.html
    (AGM-88A/B/C 360 kg, Mach 2+, 150 km).
18. designation-systems.net, "Texas Instruments AGM-45 Shrike", https://www.designation-systems.net/dusrm/m-45.html
    (AGM-45B 177 kg, Mach 2, 40 km).
19. designation-systems.net, "Hughes AGM-65 Maverick", https://www.designation-systems.net/dusrm/m-65.html (AGM-65A/B
    209 kg, > 27 km, "supersonic").

[^navyff]: US Navy, "AIM-9 Sidewinder Missile" fact file (range "classified"), https://www.navy.mil/Resources/Fact-Files/Display-FactFiles/Article/2168989/aim-9-sidewinder-missile
[^navair]: NAVAIR, "AIM-9M Sidewinder" (range 10–18 miles), https://www.navair.navy.mil/product/AIM-9M-Sidewinder
[^f16net]: F-16.net, "AIM-9 Sidewinder" (AIM-9L / M / P 17.7 km), https://www.f-16.net/f-16_armament_article1.html
[^wiki9]: Wikipedia, "AIM-9 Sidewinder" (range 0.6–22 mi, "not verified in body"), https://en.wikipedia.org/wiki/AIM-9_Sidewinder
[^dsys]: designation-systems.net, "Raytheon AIM-9 Sidewinder" (AIM-9D rear-aspect), https://www.designation-systems.net/dusrm/m-9.html
[^apa97]: Air Power Australia, "Fourth Generation AAMs" (Python 4 acquisition range), https://www.ausairpower.net/TE-Gen-4-AAM-97.html
[^fl96]: Flight International, "Rafael's agile constrictor", 9 October 1996 (Python 4 60° and more), https://flightglobal.com/rafaels-agile-constrictor/4030.article
[^wsP3]: weaponsystems.net, "Python 3" (30° acquisition, 40° tracking), https://weaponsystems.net/system/1194-Python+3
[^wsS]: weaponsystems.net, "Shafrir" (10°, 6.4 km, rear aspect), https://weaponsystems.net/system/1193-Shafrir
[^wt]: War Thunder wiki, "AIM-9L Sidewinder" (about 11 km rear, 3 km front; a game), https://old-wiki.warthunder.com/AIM-9L_Sidewinder
[^edf]: ED Forums, "The AIM-9 Sidewinder missile – technology, history and performance" (3 km frontal, 8.5 km against afterburner, AIM-9D 40°; a forum), https://forum.dcs.world/topic/267478-the-aim-9-sidewinder-missile-technology-history-and-performance/
[^hb14]: Heatblur, F-14 manual, AIM-9 page (40° seeker limit; a simulator; the page now returns 404), https://f14.manuals.heatblur.se/stores/air_to_air/aim_9.html
[^vrs]: VRS Superbug wiki, "AIM-9 Sidewinder" (a simulator), https://forums.vrsimulations.com/support/index.php/AIM-9_Sidewinder
[^hoggit]: Hoggit wiki, "F/A-18C" (a simulator), https://wiki.hoggitworld.com/view/F/A-18C
