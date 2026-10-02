# Weapon data "Real"

Preferences > Extras > **Weapon data**: *Original (1998)* (default) or *Real weapons*. Separate from Flight data. Real
overlays public real-world numbers on the original weapon records (`game/weapons/real_weapons.gd`); everything a
public source does not give keeps its 1998 value. The rules (seeker, chase law, gun timer, hit spheres) stay the
original's (docs/weapons.md).

## 1. Values

### 1.1 IR missiles
| bdb name | weight kg (orig. lb → kg) | top speed | range | sources |
|---|---|---|---|---|
| AIM-9D | 88.5 (192 → 87.1) | Mach 2.5 | 18 km | [1], [2] |
| AIM-9L | 86 (192 → 87.1) | Mach 2.5 | 35.4 km | [1], [2] |
| AIM-9M | 86 (192 → 87.1) | Mach 2.5 | 35.4 km | [1], [2] |
| PYTH-3 | 120 (264 → 119.7) | Mach 3.5 | 15 km | [3] |
| PYTH-4 | 120 (340 → 154.2) | Mach 3.5 | 15 km | [3] |
| SHFR 2 | 93 (209 → 94.8) | Mach 2.1 | 5 km | [3], [4] |

Seeker and turn (where sourced):
| bdb name | seeker | turn limit | sources |
|---|---|---|---|
| AIM-9D | rear-aspect | 12 g | [1] |
| SHFR 2 | rear-aspect | – | [3] |
| PYTH-3 | off-boresight 30° | – | [12] |
| PYTH-4 | off-boresight 60° | – | [13] |

Not changed (no public figure found): lock range (the generation table of `FUN_00462460`), the other missiles' cones
and g limits, warhead power / radius (game damage units), drag index.

### 1.2 Guns
| gun (bdb) | rate | muzzle velocity | rounds per jet | sources |
|---|---|---|---|---|
| "20 MM" (M61A1) | 6000 rpm | 1030 m/s (M56 HEI) | F-16 511, F-15 940, F-4E / Kurnass 2000 639 | [5], [6], [7], [8] |
| "DEFA" (552 / 553, 2 guns) | 2 × 1300 rpm | 815 m/s | Kfir C7 2 × 140, Mirage IIICJ 2 × 125 | [9], [10] |
The Lavi's real gun was a 30 mm DEFA [11] (the game gives it the "20 MM"); its rounds are not published, so it keeps
the original gun and count.

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
The table is per type (`RADAR_KM`, like `GUN_ROUNDS`): a new jet needs only its row.

## 2. Mapping onto the original's model
- **Weight**: bdb `0x758` (lb) = kg / 0.45359. It feeds the stores weight (docs/weapons.md §2.5), so with the original
  stores-weight rules it still goes into the kg field; the Physics option "Stores weight fix" makes it right.
- **Top speed**: the chase motion's steady speed is `_absAcceleration / _spiralAccelBeta` (docs/weapons.md §5.3); Real
  keeps a (no public g limit) and sets β = a / (Mach · 340.3 m/s, sea level). AIM-9L: 100 / 851 = 0.1175 (orig.
  0.08 → 1250 m/s).
- **Range**: the flight ends burn + 6 s after launch; Real sets burn = range / top speed − 6 (≥ 1 s): AIM-9L 35.6 s
  (orig. 16), Python 3 / 4 6.6 s, Shafrir 2 1 s (flight 7 s).
- **Rear-aspect** (ours: the original has no aspect test): the seeker's can-track also needs the target's velocity
  to point away from the launcher (v · line of sight > 0), so a head-on or a stationary target gives no tone.
- **Seeker cone**: replaces the per-generation cone, the half-angle used when the seeker is slaved to a radar lock
  (docs/radar.md §6) or to the helmet (docs/weapons.md §5.4). The 6° view is not changed.
- **Turn limit**: each 0.1 s chase update clamps the acceleration across the velocity to g · 9.80665 m/s².
- **Radar**: the LRS (and so STT) detection NM = km · 1000 / 1854.
- **Guns**: the station holds the real rounds and shows them 1:1 (orig. ×4 / ×2); the 0.2 s shot tick uses
  rate · 0.2 s rounds (M61A1 20, two DEFA 8.67); the round's `_velocityJump` / `_limitVel` = the muzzle velocity.

## 3. Validation
`tests/godot/test_weapons.gd`: AIM-9L 86 kg, F-16 511 rounds shown, one M61A1 tick = 20 rounds, and the derived
chase values (stored in the record's `motion`): AIM-9L top speed a/β = 851 m/s = Mach 2.5, flight time (burn + 6 s) ×
top speed = 35.4 km; the AIM-9D / Python 4 flags, the AIM-9D seeker refusing a head-on target (the AIM-9L
accepting it) and its 12 g clamp. `tests/godot/test_radar.gd`: the F-16's 80 km.

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
