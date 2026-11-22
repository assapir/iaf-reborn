# Weapon data "Real"

This doc lists the real-world weapon numbers that the *Real weapons* option puts on the original weapon records
(`shared/weapons/real_weapons.gd`), and how each number maps onto the original model.

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

**The round's flight** (`Motion::real_flight`, gun.rs; since 2026-11-14). The round leaves the muzzle with the jet's
velocity plus the muzzle velocity along the shot line, slows by quadratic drag and falls under gravity:

  p(t) = muzzle + u · ln(1 + k·s·t) / k − ½·g·t² · up,  k = 7.43 × 10⁻⁴ /m × ρ(h) / ρ₀

k is fitted to the M50-series chart (M56 HEI): 3,450 ft/s at the muzzle, 1,677 ft/s at 1,000 m at sea level (read off
the velocity-vs-range chart; test: 5 %)[^m50]. The same k gives 2,145 ft/s at 662 m (chart 2,359) and 1,158 ft/s at
1,493 m (chart 841): the round slows more than constant drag says below Mach 1 (inferred: the transonic drag rise), so
the model is closest out to about 1,000 m, the gun's working range. Constant Cd (≈ 0.39 for the 100 g, 20 mm
projectile), the density scaling with height (ISA) and every other calibre flying the M56's k are inferred. The round
ends where it has flown the path to its aim point (2,781 m), at its own ballistic point. The A-G gun's pipper becomes
the real round's point at the original's lead time `_limitDist` / `_limitVel`, and the shot aims down the shot line.
The AAA and the AI's fixed guns lead their target by the real time of flight and aim above it by the drop
(`combat.gd`); the AI jets' guns fire down their shot line as the player's. The EEGS
funnel (real_hud `funnel_at`) takes its time of flight from the same function, so the funnel and the rounds agree:
test `the_funnel_and_the_real_rounds_agree` (within 4 mrad at 1,000 m); `real_rounds_slow_and_fall_as_the_m56`
(1,000 m in 1.41 s at sea level from a still jet, against 0.97 s for the 1998 round). Before: the round flew a straight
line with no gravity (docs/weapons.md §3.4) while the funnel predicted a drop, about 5 m low-side at 1,000 m.

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
| "20 MM" standing in for the GAU-22/A 25 mm (the F-35I's definition `gun`) | 3300 rpm | 1040 m/s | F-35I 180 (ours) | docs/f35i.md |
| GSh-30-1 (the MiG-29 fires the "20 MM" record) | 1650 rpm (1500–1800; the middle, inferred) | 860 m/s | MiG-29 150 | [^gsh30], [^mig29] |
| GSh-23L (the MiG-23 fires the "20 MM" record) | 3400 rpm (3400–3600) | 715 m/s | MiG-23 200 | [^gsh23], [^mig23] |

The MiGs fly the F-16's "20 MM" record. With Weapon data Real they fire their own gun's rate and speed instead
(`real_weapons.gd` `JET_GUNS`, per jet type code), so the MiG-29's Real HUD funnel (860 m/s, real-hud.md) lies on its
rounds' path. The record's damage stays: no per-round value is published.

The Lavi's real gun was a 30 mm DEFA[^11]; the game gives it the "20 MM". Its round count is unpublished, so the Lavi
keeps the original gun and count.

### 1.6 The modern weapons (ours)

New records (docs/weapons.md §13) for the F-16I Sufa, the F-15I Ra'am and the F-35I, and with Extras "Weapons" on Modern for the jets of
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
| SPICE1 (SPICE 1000, Mk 83) | 453 kg (the 1,000 lb class; the exact weight open) | – | 100 km | INS / GPS, an electro-optical scene-matching seeker, deployable wings | [^spicebro], [^wpspice], [^twzspice] |
| SPICE2 (SPICE 2000, Mk 84) | 907 kg (the 2,000 lb class; the exact weight open) | – | 60 km (no wings) | INS / GPS, the SPICE 1000's seeker | [^spicebro], [^wpspice] |
| DELILA (Delilah, Modern IAF) | 187 kg | Mach 0.7 cruise (Mach 0.3–0.7), Mach 0.85 in the dive | 250 km | GPS / INS mid-course, a CCD / IIR end seeker; turbojet | [^wpdelilah] |
| GBU-28 (BLU-113) | 2,130 kg | – | the laser bombs' glide (inferred) | laser (Paveway III, the GBU-27's kit) | [^gbu28kopp], [^gbu28fas], [^gbu28wp] |

- **Weights** are the records' bdb weight (0x758) in whole pounds.
- **Missiles**: they fly the physical missile of §2.1 (since 2026-11-19; before, speed and range set β and the burn
  as §2 does), steering 0.05 s after the launch (inferred). The lock ranges (§1.2) the Python 4's for the AIM-9X (rear 16 km, front 4.5 / 12.7 km), and
  1.25 × that for the Python 5 (20 / 6 / 16 km), as no seeker range is published. The blast is the AIM-9M's (the AIM-9X
  keeps its 9.4 kg WDU-17/B warhead[^ds9x]); the Python 5's is the Python 4's (its warhead 11 kg[^3]; inferred: the
  same class).
- **JDAM range**: designation-systems gives 8–24 km "from typical operating altitudes"[^dsjdam]; Wikipedia "up to 15
  nautical miles (28 km)" and 13 nmi (24 km) in its table[^jdam]. The kit's glide ratio 1.6 makes the 24 km from
  40,000 ft at Mach 0.9 (inferred conditions; docs/weapons.md §13.2). The 3 g turn, the 150 m/s slowest and 300 m/s
  fastest speeds: inferred.
- **GBU-39 range**: "over 60 nmi" air-dropped[^sdb]: glide ratio 7.6 from the same release. Weight: the spec box's
  129 kg (the lead says 250 lb, 110 kg[^sdb]).
- **SPICE 2000 range**: 60 km[^wpspice] from the SPICE 1000's release (40,000 ft at Mach 0.9, inferred): glide ratio
  4.1. Blast and weight: the Mk 84's class (inferred).
- **Delilah** (Modern IAF's own record, `DELILA`, 2026-11-11): 187 kg, a 30 kg warhead, 250 km, Mach 0.3–0.7 in
  cruise and Mach 0.85 in the dive, flight altitude 28,000 ft, CCD / IIR sensors with GPS / INS[^wpdelilah]. The game
  has no cruise-missile class, so it flies as the GPS class (`gps.rs`) with its turbojet taken as a glide: ratio 23
  reaches 250 km from 8,500 m at Mach 0.7 (238 m/s, sea level's Mach; about 236 km at that height's 213 m/s), its slowest Mach 0.3, its fastest the Mach 0.85 dive, the JDAM's 3 g turn
  (inferred). Its end seeker is not modelled: it lands on the point set at the release, as the SPICE. Its loiter: open.
- **Blast**: the bomb's own record (Mk 84 / 83 / 82). The BLU-109 holds 250 kg of tritonal[^blu109], the GBU-39 16 kg
  of AFX-757[^sdb], the GBU-28's BLU-113 630 lb (286 kg)[^gbu28fas][^gbu28kopp], against the Mk 84's 429 kg[^mk84]:
  their power is the MK-84's × fill / 429, the radius × the cube root of that (inferred).
- **GBU-28**: "4,700 lb (2,130 kg)", "over 19 ft (5.8 m)", 630 lb of explosive in a 13 ft case with 2.25 in walls
  (Kopp[^gbu28kopp]); FAS: "weigh 4,637 pounds, and contain 630 pounds of high explosives", "14.5 inches in diameter
  and almost 19 feet long", laser guided, carried by the F-15E and F-111F[^gbu28fas]; Wikipedia: 5.824 m overall, the
  body 4.04 m, 4,000–5,000 lb, 306 kg of tritonal[^gbu28wp]. The game's record weighs Kopp's 2,130 kg and fills
  FAS's and Kopp's 286 kg. Its guidance is the game's laser bomb (type 650, docs/weapons.md §9.8): with the FLIR pod's
  laser on it flies to the designated point, else to the ripple's aim. The F-15 cannot carry the game's FLIR pod (the
  F-15E's LANTIRN pods hang on their own intake pylons, not on a game station); the Ra'am has a built-in targeting pod
  instead (`flir` in its definition, 2026-11-08), as Israel bought the Sharpshooter targeting pod for its
  F-15Is[^awst96], so it designates for its GBU-28 (docs/f15i.md §3). The GPS-aided versions
  (EGBU-28/B, EGBU-28C/B with the BLU-122[^gbu28kopp][^gbu28wp]) are not modelled: no source says Israel has them.
- **Accuracy**: a JDAM with GPS has a 5 m CEP[^jdam] (13 m official, about 10 m in use[^dsjdam]), the GBU-39 1 m[^sdb];
  with Weapon data Real (the sim always) each bomb flies to its aim moved by a random miss of that CEP (a circular
  normal miss, σ = CEP / 1.177; JDAM 5 m, GBU-39 1 m, SPICE 3 m; `gps.rs` `cep_miss`, test: half of 20,000 misses
  inside the CEP within 1.5 points); with Original data it lands on its aim.
- **SPICE 1000** (research of 2 November 2026):
  - **What it is**: Rafael's kit for 1,000 lb bodies (Mk 83, BLU-110, I-1000, RAP-1000), with "unique deployable
    wings that substantially increase its range"[^spicebro]. Weight: "a 1,000-pound-class bomb"[^twzspice]; the record
    takes 453 kg, Wikipedia's 1,000 lb figure[^wpspice] (the exact
    weight with the kit is open; searched again 2026-11-08: "about 500 kg" in one article, which may be the 1,000 lb
    class rounded, docs/f15i.md §9). Blast: the MK-83's (a Mk 83 body, inferred).
  - **Range**: 100 km, from Rafael's SPICE 1000 / 2000 page as Wikipedia cites it[^wpspice]; The War Zone gives a
    "manufacturer-stated range of approximately 125 kilometers"[^twzspice]; the older brochure "over 60 km" for the
    family[^spicebro]. The record takes 100 km. The release conditions are not published: from 40,000 ft at Mach 0.9,
    as the JDAM's and the SDB's (inferred), that is glide ratio 6.8. The 3 g turn, the 150 m/s slowest and 300 m/s
    fastest speeds are the JDAM's (inferred).
  - **Guidance**: mid-course "autonomously by means of INS/GPS"; near the target "Spice's unique scene-matching
    algorithm compares the electro-optical image received in real-time via the weapon seeker with mission reference
    data stored in the weapon computer", then "acquires the target automatically" and homes "to the exact target
    location in the pre-defined impact angle and azimuth". It "overcomes GPS jamming and Target Location Error". Each
    weapon holds up to 100 missions, planned "in the air or on the ground" from target coordinates, impact angle and
    azimuth, imagery and terrain data; the pilot allocates one to each weapon before release. Day, night and adverse
    weather; target acquisition probability 95%[^spicebro]. Fire and forget; it "can also be programmed to approach a
    target from a particular azimuth and impact angle"[^twzspice].
  - **Accuracy**: CEP "less than 3 meters"[^spicebro] ("around three meters"[^twzspice]).
  - **In the game** (docs/weapons.md §13.2): the game has no GPS jamming and its targets' coordinates have no error,
    so the scene matching ends where the GPS / INS leads: the bomb lands on its stored point (inferred). Not modelled:
    the 3 m CEP (inside the Mk 83's blast), the 5% failed acquisitions, the impact angle and azimuth.

Not added (docs/f16i.md §5):
- **SPICE 1000 on the Sufa**: integrated on the F-16I[^twzspice] (planned for the Ramon squadrons in 2017[^spice1000]),
  but no source shows its stations on the F-16I: open, not loaded (§1.7).
- **SPICE 2000** on the Sufa: no source shows its stations on the F-16I; Modern IAF's loadout editor offers it on
  inferred stations (modern-iaf/docs/data-formats.md §3). The **Delilah**: dropped from Modern IAF's loadouts
  2026-11-14 (no cruise-missile flight class; modern-iaf/docs/weapons.md §5).
- **GBU-28**: no source puts it on the F-16I; Israel bought it for its F-15s (§1.7, the F-15I).
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
| BLU109 (GBU-31(V)3) | open | open | no source | no source | no source | no source | open |
| GBU-32 | open: listed for the F-16C/D by one source[^afmjdam], not by another | no source | no source | no source | no source | no source | yes: F-35A[^afmjdam] |
| GBU-38 | yes: USAF F-16[^afmjdam] | no source (the F-15E's) | no source | no source | no source | no source | open: a 2011 Lockheed chart only |
| GBU-39 | yes: USAF F-16 (Block 30/40/50 integration, 8 on BRU-61 racks)[^ar39] | no source (the F-15E's) | no source | no source | no source | no source | yes: F-35A internal, RNLAF and RAAF[^raaf39] |
| SPICE1 | open: IAF F-16C/D since 2017[^spice1000][^twzspice], no source for its stations | yes: IAF Baz, "each carrying a pair" (an OSINT post), a photo of a Baz with a SPICE pair on the underwing pylons[^twzspice] | no source | no source | no source | no source | open: integration announced 2026[^spice35][^twzspice] |

**F-15I Ra'am** (its definition's `weapons.loads`, docs/f15i.md §3; searched 2 November 2026, again 8 November 2026:
docs/f15i.md §9):
- **GBU-28**: yes. Israel ordered "100 advanced GBU-28 bombs", "designed for use by F-15 warplanes used by Israel"
  (2005)[^globes05]; "The IAF is also equipping its F-15I squadron with the GBU-28 2.2-ton hard target penetrator
  bomb" (2010)[^globes10]; the IAF's "US-supplied 5,000-pound class GBU-28 series" (2026)[^fpri26]. Station: no source
  for the F-15E or F-15I. The F-15E's CFT racks are "stressed for up to 1000 lb" (outer) and "2000 lb" (inner fore and
  aft)[^kopp85], too little for it, so the game puts it on the wing pylons B / H and the centreline E (inferred; the
  2003 USAF photo of an F-15E releasing one[^gbu28photo] shows it leaving from under the fuselage: the centreline or
  the far wing, a side view cannot tell). Since 2026-11-08 the Ra'am's built-in targeting pod designates for it
  (§1.6).
- **GBU-39**: yes. "Israel will shortly bring the GBU-39 bomb into operational use with the F-15I "Thunder"
  squadron" (2010)[^globes10]; "footage released by the IDF also shows SDB-armed BRU-61/As being loaded onto F-15I
  Ra'am aircraft",
  and the F-15I carries "up to 20 SDBs or seven GBU-31 series weapons" (2026)[^fpri26]. Stations: the game puts a
  BRU-61/A of four on five stations for the 20: the wing pylons B / H, the centreline E and the CFTs' inner (2,000 lb)
  racks D / F[^kopp85] (inferred; the F-15E's 12 on "the centerline and two conformal tank stations" is a 2004 press
  snippet not read in full, open).
- **AIM-9X**: open. Israel bought "up to 600 AIM–9X–2 Sidewinder Block II" missiles (US notice of July 2014, no jet
  named)[^isr9x]; an IAF F-35I fired one in 2023[^twz35x]. No photo or statement shows an F-15I with one (searched:
  "F-15I AIM-9X", IAF AIM-9X photos, later US notices for Israel). Not offered.
- **GBU-38**: open. Israel bought 4,000 JDAM kits for the Mk 82 in 2015[^fr1536]; the Ra'am carries JDAMs (the IAF's
  JDAM jets "include, among others, Baz, Ra'am, Sufa"[^fpri26]) but no source names the 500 lb GBU-38 on the F-15I
  (searched: F-15I GBU-38 / Mk 82 JDAM photos 2023–2025; on 2026-11-08 the US notices of 2012, 2024 and 2025 for
  GBU-38 kits and of 2025 for GBU-32 kits, none naming a jet). Not offered, nor the GBU-32.
- **AMRAAM**: Israel bought the AIM-120C-7 (2015)[^fr1536] and the AIM-120C-8 (2024, 2025); no notice names a jet
  (docs/f15i.md §9). The game's AMRAAM record stays: no source gives either version's range.
- **GBU-31 (Mk 84 body)**: the IAF uses "GBU-31(V)1/B and GBU-31(V)3/B" and the F-15I carries "seven GBU-31 series
  weapons"[^fpri26]: offered on the F-15I since 2026-11-02 (the user's decision), on the BLU109's seven stations
  B, C, D, E, F, G, H (inferred), as is the seventh BLU109 on the centreline.

Stations (`modern_weapons.gd` `LOADS`; letters A–I are the Arming screen's stations 1–9):
- **Barak**: AIM-9X and Python 5 on A, B, C, G, H, I, where the F-16 carries its AIM-9L (inferred: no official
  station list). GBU-31 and GBU-38 on C, D, F, G: the IAF's F-16s load JDAMs on the inner wing pylons as well as the
  standard heavy ones[^avi23]. GBU-39 four to a rack on C / G (inferred from the eight on two racks[^ar39]).
- **F-15**: AIM-9X two to a wing pylon on A / I, as its AIM-9L; GBU-31 on B, E, H, the wing pylons and the centreline
  ("three GBU-31(V)1 JDAM bombs, loaded on the centerline and wing stations"[^avi23]); SPICE1 a pair on the wing
  pylons B / H[^twzspice] (the photo's caption calls the pair 2,000 lb SPICEs, the article's text 1,000 lb ones).
- **F-15I Ra'am** (its own loads, docs/f15i.md §3): the SPICE1 on B / H as the Baz's pair (the F-15I's own stations:
  no source, inferred).
- **F-35I** (docs/f35i.md §3.1): AIM-9X on the outboard pylons A / I[^dt35]; GBU-31 and GBU-32 in the bays C / G and on
  the heavy pylons B / H; GBU-39 four to a bay on C / G[^raaf39].

### 1.8 Spike and SPICE: the SPICE 1000 and 2000 built, the Spike NLOS a model only (open)

The SPICE 1000, the SPICE 2000 and the Spike NLOS have detailed models (ours, docs/aircraft-models.md §5.6). The SPICE
1000 is a weapon record since 2 November 2026 (`SPICE1`, §1.6), the SPICE 2000 since 11 November 2026 (`SPICE2`); the
Spike NLOS has none. Research of 30 October 2026.

**Which ones the IAF fields:**
- **SPICE 2000**: on the IAF's F-16s since 2005 (a search snippet citing GlobalSecurity; open). A kit on the Mk 84,
  BLU-109 and other 2000 lb bodies[^spicebro].
- **SPICE 1000**: IOC on the F-16C/D in 2017, the F-16I and F-15I next[^spice1000]; integrated on the F-16I, F-16C/D,
  F-15I and F-15 Baz by 2026[^twzspice]. Integration on the F-35I was announced in
  September 2026[^spice35]. A kit on the Mk 83, BLU-110 and other 1000 lb bodies, with "deployable wings"[^spicebro].
- **SPICE 250**: four to a Smart Quad Rack, up to 16 on an F-16[^spice250rack]; 113 kg[^spice250]. Its IAF use and
  carriers: open. No model: its length, span and wing layout are open.
- **Spike NLOS** (IAF name Tamuz, table §1.9): on the IAF's AH-64 Apaches for years, under the stub wing[^twznlos]; about
  70 kg, up to 25 km[^avinlos]; 1.7 m long, 71 kg (the sixth generation)[^janesnlos]. Its diameter: open. No source shows
  it on the F-16I, F-15I or F-35I. The game has no player helicopter, so it has no station to load it.

**What adding them as weapons needs** (open, a follow-up; `modern_weapons.gd` belongs to the weapons work):
- **SPICE 2000**: built (§1.6); its IAF carriers and stations: open (only Modern IAF's loadout editor loads it).
- **SPICE 1000** on the Barak, the Sufa and the F-35I: their stations (§1.7).
- **Spike NLOS**: none until the game has a helicopter station; its record would be an electro-optical guided missile
  (type 600 as the AGM-65, inferred) with 25 km range[^avinlos].
- Their models: `spice1000.glb`, `spice2000.glb`, `spikenlos.glb` in `shared/extra/models/stores/`; a record names them
  as the Sufa's records do (`model_path` under `weapons/sufa/`, `util/gltf.gd` STAND_INS and STORES).

### 1.9 The IAF's Hebrew names

The Israeli names of the modern weapons and stores. "Code name": the IAF's own name. "Transliteration": the English
name in Hebrew letters. Most sources are the Hebrew Wikipedia and Hamichlol (which often mirrors it), so the two are
not independent; no IAF page confirming them was found. "Open": no source found. Research of 30 October 2026.

| English name | Hebrew | transliteration (meaning) | kind | source |
|---|---|---|---|---|
| Shafrir 2 | שפריר 2 | Shafrir | Israeli name | [^hepython] |
| Python 3 | צפריר | Tzafrir (morning breeze) | code name | [^hepython] |
| Python 4 | פיתון 4 | Piton | Israeli name; code name open | [^hepython] |
| Python 5 | פיתון 5 | Piton | Israeli name; code name open | [^hepython] |
| Derby | דרבי | Derbi | transliteration; code name open | [^hederby] |
| AIM-9L / AIM-9M | לולב / מחט | Lulav (palm frond) / Mahat (needle) | code names | [^he9] |
| AIM-9X | – | – | open | [^he9] |
| AIM-120 AMRAAM | אשוח | Ashuah (fir tree) | code name | [^he120] |
| AIM-7E Sparrow | לביד | Lavid | code name (the 7E; later models open) | [^he7] |
| JDAM (GBU-31 / 32 / 38) | ברד כבד | Barad Kaved (heavy hail) | code name | [^hejdam] |
| GBU-39 SDB | ברד חד | Barad Had (sharp hail) | code name | [^hesdb] |
| SPICE 2000 | ברד פלדה | Barad Plada (steel hail) | code name | [^hespice] |
| SPICE 1000 | ברד קל | Barad Kal (light hail) | code name | [^hespice] |
| SPICE 250 | ברד קטן | Barad Katan (small hail) | code name | [^hespice] |
| Spike NLOS | תמוז | Tamuz (a month) | code name | [^hetamuz] |
| Spike MR / LR / ER | גיל / גומד / פרח בר | Gil / Gomed / Perah Bar (wildflower) | code names (ground forces; the Apache carries Gil) | [^hetamuz] |
| Popeye (AGM-142) | פופאי, חנית נאה | Popay; Hanit Na'ah (handsome spear) | code name | [^hepopeye] |
| Delilah | דלילה, חנית | Delila; Hanit (spear) | code name (clashes with the Popeye's; unverified) | [^hedelilah] |
| AGM-114 Hellfire | קרדום | Kardom (hatchet) | code name | [^hehellfire] |
| Rampage, Rocks, Air LORA | רמפייג', רוקס, לורה | Rampeij, Roks, Lora | transliterations; code names open | [^herampage] |
| GBU-28, Mk 82 / 83 / 84, Paveway, AGM-65, Sniper pod | – | – | open | – |
| Litening pod | לייטנינג | Laitning | transliteration | [^helitening] |
| drop tanks | מכלי דלק פריקים | Mekhalei delek prikim (detachable fuel tanks) | plain term | [^hesufa] |
| F-16I | סופה | Sufa (storm) | IAF name | [^hesufa] |
| F-16C/D | ברק | Barak (lightning) | IAF name | [^hef16] |
| F-15I | רעם | Ra'am (thunder) | IAF name | [^hef15] |
| F-15A–D | בז | Baz (falcon) | IAF name | [^hef15] |
| F-35I | אדיר | Adir (mighty) | IAF name | [^hef35] |

The satellite-guided bombs share the "Barad" (hail) family: JDAM, SDB and SPICE.

### 1.10 Bomb fall (2026-11-14)
With Weapon data Real the player's unguided bombs (`bombs.rs` `Bomb::launch_real`, `real_fall`) leave with the jet's
velocity and fall under gravity and their own drag, β·ρ·|v − w|·(v − w) with β = C_D·A / 2m, through the air mass w
(Better physics `wind`; the sim always). Nothing steers them. The original steers each store onto its aim point and
has no drag (docs/weapons.md §9.5), so its CCIP is right by construction.

- **C_D 0.45** on the body's frontal area for the Mk 80 series and the M117: the MK-82 Snakeye's low-drag mode, whose
  ballistic coefficient C_D·A/W is 0.0005 ft²/lb (C_D ≈ 0.45)[^snakeye]. Test: the MK-82's β gives that coefficient
  within 10 %. The low-drag MK-82, MK-83, MK-84 and M117 flying the Snakeye's closed-fin coefficient is inferred
  (the same low-drag shape family); C_D stays constant with Mach (inferred: no public C_D(M) table at hand).
- **Diameters:** MK-82 0.273 m[^mk82], MK-83 0.357 m[^mk83], MK-84 0.458 m[^w-mk84d], M117 0.408 m[^m117]; any other
  store: the MK-84's scaled by the cube root of its mass (inferred). The mass is the store's bdb weight.
- **Air density:** ISA by height (`atmosphere.rs`).
- **CCIP** (`real_impact`) runs the same fall from the jet's position and velocity to the first terrain point, so the
  pipper is where the bomb lands. Test `real_bombs_fall_by_their_drag_and_ccip_predicts_it`: a MK-84 released on
  the pipper at 0°, 20° and 45° of dive lands within 1 m of it; a MK-82 from 1,000 m at 250 m/s lands 3,000–3,500 m
  ahead against 3,570 m drag-free; a 20 kt crosswind drifts it and CCIP follows. As a plausibility check (the
  store is not named): a bomb dropped at 450 kt in a 40° dive falls 8,000 ft in 13 s by the ballistics tables
  against 9,076 ft drag-free[^ewhb]; the model's MK-82 falls about 8,450 ft (6 % more, inferred: transonic drag).
- **The AI's bombs** keep the original's steered fall: the AI has no release computer to fly to a CCIP point (ours).

[^snakeye]: US patent 4,112,843, "Modular practice bomb" (the MK-82 Snakeye's ballistic coefficient in its low-drag
    mode 0.0005 ft²/lb, C_D·A/W; "released in the low drag mode (C_D ≃ 0.45)"),
    https://patents.google.com/patent/US4112843A/en
[^mk82]: Wikipedia, "Mark 82 bomb" (10.75 in across), https://en.wikipedia.org/wiki/Mark_82_bomb
[^mk83]: Wikipedia, "Mark 83 bomb" (14 in across), https://en.wikipedia.org/wiki/Mark_83_bomb
[^w-mk84d]: Wikipedia, "Mark 84 bomb" (18 in across), https://en.wikipedia.org/wiki/Mark_84_bomb
[^m117]: Wikipedia, "M117 bomb" (16 in across), https://en.wikipedia.org/wiki/M117_bomb
[^ewhb]: Naval Air Warfare Center Weapons Division, *Electronic Warfare and Radar Systems Engineering Handbook*
    (NAWCWD TP 8347), §8-1 "Free fall / aircraft drag", sample calculation,
    https://pe2bz.philpem.me.uk/Comm/-%20Transmitters/-%20Jammers/B-101-ElectWarfare-RadarBook/freefall.pdf

### 1.11 Release limits, jettisons and bay doors (2026-11-15)
With Weapon data Real the player's stores follow these limits and procedures (`release.rs` `real_release_allowed`,
`player_weapons.gd` `release_allowed`, `emergency_jettison`, `selective_jettison`). The original's rules stay with
Original (docs/weapons.md §9.5, §9.6).

- **Release limits.** A release outside them is refused: the store stays on its station and the ripple waits.
  - Bombs (500, 510, 650): at most **600 KCAS**. Low-drag deliveries are limited to 600 KCAS because the bomb's fall
    turns unstable and scatters above it[^to34]. The limit is calibrated airspeed: the jet's true airspeed and height
    give it through the standard atmosphere (isentropic pitot pressure below Mach 1, Rayleigh's pitot formula above;
    `atmosphere::cas`). The HUD's airspeed is the 1998 gauge formula, so it can read a few knots off this figure.
    The source names the low-drag bombs; the cluster and GPS bombs on the same bodies keep it too (inferred).
  - The AGM-65 (635): at most **Mach 1.2**, **30° of bank** and **60° of dive**[^to34]. Its 30°/s roll-rate limit is
    not applied: the flight model's state gives no roll rate to the weapons.
  - Bombs: at most **60° of dive** (inferred: the AGM-65's limit; no public F-16 bomb dive limit was found).
  - Load factor ≥ 0 and bank ≤ 90° stay as the original's permission (`FUN_0045ee10`). The F-16's store carriage
    limits (speed and g per store, T.O. 1F-16C-1-2) are open: that volume is not public, and the flight manual refers
    to it for every store limit[^to16].
- **Emergency jettison** (Shift+C): "a one-step operation which clears all expendable stores and racks except
  air-to-air missiles"; the weapons leave unarmed or unguided[^to16]. One press drops every bomb, tank, pod and rack
  but the A-A missiles (570, 580, 600, 610); the tanks' fuel goes with them (the internal fuel stays); each store
  falls unsteered and does not burst. No attitude limit applies. On the ground it is refused (the real jet needs GND
  JETT ENABLE[^to16], which the sim does not model). The F-35I follows the same rule, its bay stores once the doors are
  open (inferred: no public F-35 jettison procedure).
- **Selective jettison** (the F-16 SMS's S-J, OSB 11, then the weapon release): it releases selected stores
  "(except air-to-air missiles) or suspension equipment in an unarmed or unguided condition"[^to16]. S-J turns the
  page's selective mode on (the label shown inverse) and off; while it is on, Space jettisons every station of the
  selected store with its rack (the manual's RACK selection), instead of releasing it. The stations are the selected
  store's (ours: the page has no station-by-station choice).
- **F-35I bay doors.** A release from a bay waits for the doors to open (0.47 s, the model's door rate; inferred);
  they shut 0.5 s after the release, so the doors open, release and shut in about 1.4 s, inside the "under two
  seconds" a press report gives[^wion] (the time itself inferred). While open the doors and bays add **50** to the
  drag index, in proportion to their opening (inferred: an open cavity's drag taken as 0.02 of its opening's
  dynamic-pressure force, two bays of 3.9 × 0.9 m, the GBU-31's 3.879 m length with room, on the 300 ft² drag
  reference, modern-iaf/docs/flight-model.md §9.18; no public open-bay drag figure was found).
- **Tests:** `cargo test -p iaf-avionics --lib release::` (`real_release_limits`: 595 / 605 KCAS at sea level, the
  calibrated speed at 10,000 ft, 59° / 61° dive, the AGM-65's Mach 1.2 and 30°), `stores::` (the rack leaves with its
  weight, drag and moment), and `modern-iaf/tests/test_sim_jettison.gd` (the limits, both jettisons and the bay doors
  in the sim's flight model; modern-iaf/docs/weapons.md §6).

[^to34]: US Air Force, T.O. 1-1M-34, *Aircrew Weapons Delivery Manual (Nonnuclear)*, Section I (MK 82 / MK 84 AIR:
    "LD deliveries should be limited to a maximum of 600 KCAS as testing has found excessive dispersion caused by
    ballistic instability at delivery speeds above 600 KCAS"; "AGM-65 operational limitations": launch speed Mach
    1.2, dive 60°, bank 30°, roll rate 30°/s), https://www.bulletpicker.com/pdf/TO-1-1M-34.pdf
[^to16]: US Air Force, T.O. 1F-16A-1, *Flight Manual, F-16A/B Blocks 10 and 15*, 2003, Section III "Jettison"
    (selective and emergency jettison), Section I figure 1-37 (GND JETT ENABLE on the ground), Section V "Stores
    limitations" (refers to T.O. 1F-16A-1-3 / -1-4),
    https://archive.org/details/to-1-f-16-a-1-flight-manual-f-16-a-b-block-10-15-august-2003
[^wion]: WION, "Why the F-35's internal weapons bays open so quickly", 23 August 2026 ("the doors open, release the
    payload, and close in under two seconds"),
    https://www.wionews.com/photos/why-the-f-35-internal-weapons-bays-open-so-quickly-1787440984317

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

### 2.1 The physical missile (Modern IAF's, 2026-11-19)

Modern IAF's air-to-air missiles (the AIM-9M and AIM-120 records of modern-iaf/data/db/weapons, the AIM-9X and
Python 5 of `modern_weapons.gd`, also with Extras Weapons on Modern in the 1998 game) fly a physical model in place of
the chase motion (`missile.rs` `Physics`). The record's motion holds its fields (modern-iaf/docs/data-formats.md §3).
The player's and the AI's missiles fly the same code.

**The model**, every 0.1 s update:
- **Motor:** a steady thrust for its burn, its propellant burnt off at a steady rate.
- **Drag:** q·S·(Cd0(M) + K·CN²) on the body's cross-section S, with the ISA density and speed of sound at the
  missile's height. Cd0(M) is one generic curve (0.30 subsonic, 0.70 at Mach 1.2, 0.38 at Mach 4; inferred) times the
  record's drag scale; CN is the normal force the fins carry for the turn (at most 7, the rest the thrust vector's),
  K = 0.1. A turn bleeds speed.
- **Turn limit:** the fins give at most CN = 7 (inferred), so the limit falls with the air's density and the speed; at
  most the structural g. With thrust-vector control (the AIM-9X's jet vanes[^ds9x]) the structural g holds while the
  motor burns.
- **Guidance:** augmented proportional navigation, N = 4 (the usual 3–5[^pn]): N times the closing speed times the line
  of sight's turn rate, across the missile's velocity, plus half N times the target's acceleration across the line of
  sight (taken from its velocity between the game's samples, at their own times, at most 12 g; inferred), with gravity
  held off. More than 60° off the line of sight, or opening, the missile turns its velocity onto the line of sight
  within about 0.5 s, within its limit, first (inferred). Gravity acts on the whole flight.
- **End:** the flight ends at its time limit, or once the motor is out below 200 m/s (inferred: too slow to steer).
  The burst is where the original's is: on a hit, at the closest pass, or on the ground.
- **The same at any frame rate** (2026-11-19): the closest pass is that of the missile and the moving target over
  the 0.1 s step. The original holds the target still at the step's end, so its burst point moved with where the
  step fell against the pass: a Python 5 burst 11–14 m off a breaking drone in a visible window on a Mac and at 30
  frames a second, within 6 m at 60 and 120. The game's units are a frame old when the missile updates (they move
  after the weapons); the update carries the target on at its velocity to its own time and puts the burst (also one
  on the ground) at its offset from the target as the game has it, where the blast's damage is reckoned. Test:
  `missile.rs`
  `the_burst_is_the_same_at_any_frame_rate`; `tools/test.sh` flies `test_sim_missiles.gd` at 30 and 120 frames a
  second.
- **DLZ:** a straight level fly-out at the mean height of the jet and the target, from the jet's speed: the maximum
  is the most the missile gains on the target in its flight less the last 2 s (the original's margin), the minimum the
  original's (the distance flown in tCO + 2 s). The post-launch times (modern-iaf/docs/weapons.md §8.2) run the same
  fly-out from the missile's state, and the AI's launch range reads the same zone.

**The values:**

| missile | launch kg | motor | propellant | body | g limit | flight time | sources |
|---|---|---|---|---|---|---|---|
| AIM-9M | 86 | Mk 36: 12,810 N (2,880 lb) for 5.0 s | 27.2 kg (inferred: the impulse at 240 s specific impulse) | 0.127 m | 40 (inferred; one forum's AIM-9 figure) | 24.7 s (fitted) | [^navymk36] (second-hand), [^1] |
| AIM-9X | 85 | the AIM-9M's Mk 36[^ds9x] | the same | the same | 60, thrust-vector control[^2] | the AIM-9M's (inferred) | [^ds9x], [^2] |
| Python 5 | 105 | 16,671 N for 5.0 s (inferred: sized for Mach 4) | 34 kg (inferred) | 0.16 m | 60 (inferred: the AIM-9X's) | 31.1 s (fitted) | [^3] |
| AIM-120 | 161.5 | 17,188 N for 7.75 s (51.3 kg at 265 s) | 51.3 kg | 0.178 m | 35 (weak: a forum's table; 28–40 quoted) | 120 s (inferred) | [^iasg], [^wt120] |

- **The drag scale** (1.217 for all four, inferred): fitted so the AIM-120 flies its published 90 km head-on, both
  jets at Mach 0.9 12,000 m up. A check against the CFD study[^iasg]: from Mach 0.83 5 km up at a still point it flies
  about 35 km in both. One scale for every body is inferred: no public drag figure for the Sidewinder or the Python
  was found.
- **The flight times** (fitted): the AIM-9M's 24.7 s makes its 17.7 km at a still target from Mach 0.9 6,000 m up
  (the medium-altitude reading of §1.1); the Python 5's 31.1 s its 20 km. No missile's battery life is published.
- **The Python 5's motor**: Rafael keeps the Python 4's motor[^p5bro], whose figures are not published; its propellant
  is set so it reaches Mach 4[^3] from Mach 0.9 12,000 m up (inferred).
- **What the model gives** (Mach 0.9 launches, test `physical_missiles_fly_their_published_figures`; the model's
  results, not published figures): the AIM-9M reaches Mach 3.8 12,000 m up (published: "Mach 2.5+"[^1]); at sea level it reaches 14 km at a still target, 7 km chasing a Mach 0.9 target; the
  AIM-120 36 km at a still target 6,000 m up, 16 km in a tail chase.
- **Open:** each missile's real drag, flight time and g limit; the motors' thrust curves (one steady thrust here; the
  AIM-120's boost and sustain are disputed[^iasg]).

### 2.2 The seeker in flight and the data link (2026-11-19)

The physical missile carries its own seeker (`missile.rs` `Missile::set_seeker`, `sees`):
- **Gimbal:** the seeker sees the target only within its cone off the missile's axis (its velocity): the record's
  Real cone (AIM-9M 40°, AIM-9X 90°, Python 5 100°; §1.2), else its generation's (AIM-120 70°; docs/weapons.md §5.1).
  A target that has been inside the cone and leaves it is lost (a launch off the missile's axis, still the jet's, is
  no loss): the missile stops steering, flies on and bursts as one with its guidance off (no snap to the closest pass,
  whose closest point can be the target itself on a wide pass). Inside 300 m the cone no longer counts (inferred: the
  end-game, the fuze's part).
- **The AIM-120's mid-course:** until its seeker goes active it flies on the jet's data link: while the launcher's
  radar locks its target (the player: a lock or a TWS selection on it; an AI launcher: always, inferred) it steers at
  the target itself; once the lock drops it flies to where the target would be on its last known velocity. At the
  active range (half the generation's lock range, 7.5 NM for the AIM-120; modern-iaf/docs/weapons.md §8.2) it goes
  active and takes the target if it is inside its cone, else it is lost. From then on it needs the jet no more.
- **Inferred:** the cones as the seeker's limits in flight; the AIM-120's real active range and its seeker's
  acquisition basket are not published (open).

### 2.3 Decoys against the seeker (Modern IAF's, 2026-11-22)

In Modern IAF (`Settings.modern_ew`; modern-iaf/docs/ai-plan.md K8) a flare or a chaff bundle acts on each missile's
own seeker in place of the 1998 decoy rule (docs/weapons.md §10, which the 1998 game keeps). At the release each
missile flying at the releasing jet rolls on its own chance (`ecm.rs` `decoy_chance`; no first-failure stop), and a
missile taken chases the decoy:

- **The kind:** flares take only infrared seekers (570, 580, 620), chaff only radar seekers (600, 610, 630).
- **The seeker's rejection** (the record's `_decoyReject`, 0 to 1): newer infrared seekers tell flares from the jet by
  their spectrum and their path[^w-flare], so a flare's chance is 0.5 · (1 − rejection). A Doppler radar seeker tells
  the slowing chaff from a jet moving along its line of sight; a jet on the beam has the chaff's Doppler[^w-chaff], so
  chaff's chance is 0.4 · (1 − rejection · (1 − beam)), the beam 1 − |cos| of the angle between the jet's velocity
  and the line of sight.
- **Timing:** full inside 6 s of the missile's arrival (its time to go at the closure); earlier, 6 s / time to go (a
  decoy burns 4 s: one released early has burnt out while the missile is still far). An opening missile is not taken.
- **The jet:** above 4 g every chance × 1.5 (the 1998 rule's threshold); a flare beside a lit afterburner × 0.25 (the
  1998 rule: none).

| missile | seeker | rejection | basis |
|---|---|---|---|
| AIM-9M | infrared | 0.5 | "better background rejection and infrared countermeasures discrimination" over the AIM-9L[^2] |
| AIM-9X | imaging infrared | 0.85 | the imaging seeker and its reprogrammable IRCCM[^2] |
| Python 5 | electro-optical and imaging infrared | 0.85 | as the AIM-9X[^3] |
| R-73 | cooled infrared (1984) | 0.3 | no counter-countermeasure claim found |
| AIM-120 (also the SAMs' stand-in) | active pulse-Doppler radar | 0.8 | the Doppler rule above |
| R-27R | semi-active radar (1987) | 0.5 | an older Doppler seeker |
| any other | — | 0 | — |

Every figure is inferred (no seeker's decoy rejection is published); the sources give only what each seeker adds.
What a flare and chaff then give, head on 2 km out: an old IR seeker 0.5, the AIM-9M 0.25, the AIM-9X 0.075; chaff
against the AIM-120 0.4 on the beam, 0.08 from a jet flying straight away. Tests: `ecm.rs` (`rejection_by_generation`,
`afterburner_and_g`, `chaff_works_on_the_beam`, `early_decoys_burn_out`), `modern-iaf/tests/test_countermeasures.gd`.

## 3. Validation
| test | checks |
|---|---|
| `tests/godot/test_weapons.gd` | AIM-9L 86 kg; F-16 511 rounds shown; one M61A1 tick = 20 rounds; the derived chase values (stored in the record's `motion`): AIM-9L top speed a/β = 851 m/s = Mach 2.5, the distance flown in burn + 6 s from 250 m/s = 17.7 km; its DLZ against a still target between 15 and 17.7 km; the AIM-9D / Python 4 flags; the AIM-9D seeker refuses a head-on target; the AIM-9L locks head-on at 2 km, not at 5 km without afterburner; the AIM-9D 12 g clamp; the §1.4 blast radii (only the sourced ones, only with Real); the real gun hit test (a 5 m half-span 8 m off the line at 1070 m hit, a 2 m one missed); the MiG-23's drawn half-span in 231 |
| `crates/iaf-avionics/src/gun.rs` `real_hits_sweep_the_path_between_checks` | a fighter 5 m off the line between two checks is hit, 10 m off missed, 10 m with Easy aiming hit; a point test steps over it |
| `tests/godot/test_radar.gd` | the F-16's 80 km |
| `tests/godot/test_radar_missiles.gd` | the AMRAAM's 157 kg, a/β = Mach 4 and the distance flown in burn + 6 s from 250 m/s = 70 km; the AIM-7B's DLZ against a still target about 5.7 km (not empty) |
| `crates/iaf-avionics/src/sight.rs` `real_rear_sector`, `real_front_mil_ab_and_none`, `original_range_and_aspect` | the §1.2 rules: rear range and its R/2 afterburner rule, the 60° sector, front with / without afterburner, no front lock, the original unchanged |
| `crates/iaf-avionics/src/missile.rs` `physical_missiles_fly_their_published_figures`, `a_physical_missile_reaches_its_dlz_and_no_further`, `turning_bleeds_speed_and_height_takes_the_turn`, `physical_post_launch_times_match_the_flight`, `a_short_shot_hits_a_breaking_target`, `the_data_link_and_the_active_seeker`, `an_ir_seeker_loses_a_target_outside_its_gimbal`; `modern-iaf/tests/test_sim_missiles.gd` (each jet kills a range drone with each missile: the IR missiles from 2.5 km behind, the AIM-120 head-on from 20 km) | §2.1: the published ranges and speeds, the CFD study's 35 km, the zone shrinking low and in a tail chase; a launch inside the zone hits, past it misses (still, closing, opening), a crossing target is led, a 6 g break from 2.5 km is hit; §2.2: with the link the AIM-120 follows a turning target, without it it finds the target inside its cone at the active range, a narrow cone loses it, an IR seeker loses a target outside its gimbal, the AIM-9X turns 70° off the rail onto a still target 3 km off and hits it; induced drag, the fins' limit falling with height, the AIM-9X's thrust vectoring; the post-launch time to impact within 10 % of the flight |
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
    squadrons next, later the F-15I), https://www.airforce-technology.com/news/iafs-spice-1000-munition-attains-ioc-use-f-16c-d-aircraft/
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
[^spicebro]: Rafael, "SPICE" brochure (SPICE 2000 a kit for the Mk 84, BLU-109, APW and RAP-2000; SPICE 1000 for the
    Mk 83, BLU-110, I-1000 and RAP-1000, with deployable wings; over 60 km, CEP under 3 m; INS / GPS navigation and
    scene matching against stored reference images; 95% target acquisition; 100 missions per weapon),
    https://omnirole-rafale.com/wp-content/uploads/2019/10/Spice.pdf
[^wpspice]: Wikipedia, "Spice (bomb)" (Spice 1000: a kit for 450 kg bodies, deployable wings, 100 km, citing Rafael's
[^wpdelilah]: Wikipedia, "Delilah (missile)" (187 kg, 2.71 m, 0.33 m; 30 kg warhead; 250 km; Mach 0.3–0.7, Mach 0.85 in the dive; flight altitude 28,000 ft; CCD and IIR sensors, GPS / INS), https://en.wikipedia.org/wiki/Delilah_(missile)
    "Spice 2000/1000 Family" page, https://www.rafael.co.il/system/spice-family-1000-2000/, which refuses automatic
    fetches; Spice 2000 60 km; CEP 3 m; 453 kg in the family's infobox), https://en.wikipedia.org/wiki/Spice_(bomb)
[^twzspice]: T. Newdick, The War Zone, "Israel Is Bringing SPICE 1000 Standoff Weapon To The F-35", 16 September 2026
    (1,000 lb class; pop-out wings, about 125 km; CEP about 3 m; INS / GPS and an electro-optical seeker with scene
    matching; integrated on the F-16I, F-16C/D, F-15I and F-15 Baz; a Baz with a pair on the underwing pylons),
    https://www.twz.com/air/israel-is-bringing-spice-1000-standoff-weapon-to-the-f-35
[^spice35]: Defense News, "Israel's SPICE 1000 bombs can soon drop from F-35 fighters", 16 September 2026,
    https://defensenews.com/global/mideast-africa/2026/09/16/israels-spice-1000-bombs-can-soon-drop-from-f-35-fighters
[^spice250rack]: AIN Online, "Rafael unveils new SPICE rack", 17 June 2013 (four SPICE 250 per station, up to 16 on
    an F-16), https://ainonline.com/aviation-news/2013-06-17/rafael-unveils-new-spice-rack
[^spice250]: Airforce Technology, "SPICE 250 precision-guided munition" (113 kg),
    https://www.airforce-technology.com/projects/spice-250-precision-guided-munition/
[^twznlos]: The War Zone, "U.S. Army AH-64 Apaches armed with Israeli Spike missiles now flying in Iraq" (Israeli
    Apaches have used the Spike NLOS for years), https://twz.com/air/u-s-army-ah-64-apaches-armed-with-israeli-spike-missiles-now-flying-in-iraq
[^avinlos]: The Aviationist, "Photos of AH-64D Apache armed with Spike missiles", 26 July 2017 (about 70 kg, up to
    25 km), https://theaviationist.com/2017/07/26/photos-of-ah-64d-apache-armed-with-spike-missiles-proves-that-the-weapon-is-operational-for-the-israeli-attack-helicopters/
[^janesnlos]: Janes, "Rafael unveils sixth-generation Spike NLOS" (1.7 m, 71 kg),
    https://www.janes.com/defence-news/rafael-unveils-sixth-generation-spike-nlos
[^hepython]: Hebrew Wikipedia, "פיתון (טיל)" (the Python 3 "בחיל האוויר הישראלי מכונה הטיל צפריר"; Shafrir 2, Python
    4 and 5), https://he.wikipedia.org/wiki/פיתון_(טיל)
[^hederby]: Hebrew Wikipedia, "דרבי (טיל)", https://he.wikipedia.org/wiki/דרבי_(טיל)
[^he9]: Hebrew Wikipedia, "AIM-9 סיידוויינדר" (the IAF's names per model), https://he.wikipedia.org/wiki/AIM-9_סיידוויינדר
[^he120]: Hebrew Wikipedia, "AIM-120 AMRAAM" ("מכונה בו "אשוח""), https://he.wikipedia.org/wiki/AIM-120_AMRAAM
[^he7]: Hebrew Wikipedia, "AIM-7 ספארו" (the AIM-7E "בשם "לביד""), https://he.wikipedia.org/wiki/AIM-7_ספארו
[^hejdam]: Hebrew Wikipedia, "JDAM" ("המכונה בישראל "ברד כבד""), https://he.wikipedia.org/wiki/JDAM
[^hesdb]: Hamichlol, "פצצת SDB" ("מדגמי GBU-39/B ("ברד חד")"), https://www.hamichlol.org.il/פצצת_SDB
[^hespice]: Hamichlol, "ספייס (אמצעי לחימה)" (ברד פלדה, ברד קל, ברד קטן), https://hamichlol.org.il/ספייס_(אמצעי_לחימה)
[^hetamuz]: Hebrew Wikipedia, "תמוז (טיל)" (the Tamuz, the Spike NLOS; the Spike family's IDF names),
    https://he.wikipedia.org/wiki/תמוז_(טיל)
[^hepopeye]: Hebrew Wikipedia, "פופאי (טיל)" ("מכונה בו חנית נאה"), https://he.wikipedia.org/wiki/פופאי_(טיל)
[^hedelilah]: Hebrew Wikipedia, "דלילה (טיל)" ("המכונים בחיל האוויר "חנית""), https://he.wikipedia.org/wiki/דלילה_(טיל)
[^hehellfire]: Hebrew Wikipedia, "AGM-114 הלפייר" ("מכונה בחיל האוויר "קרדום""), https://he.wikipedia.org/wiki/AGM-114_הלפייר
[^herampage]: Hamichlol, "רמפייג'", https://www.hamichlol.org.il/רמפייג'; "רוקס (טיל)",
    https://www.hamichlol.org.il/רוקס_(טיל); "AIR LORA", https://www.hamichlol.org.il/AIR_LORA
[^helitening]: Hamichlol, "לייטנינג (פוד)", https://www.hamichlol.org.il/לייטנינג_(פוד)
[^hesufa]: Hebrew Wikipedia, "F-16I סופה" (the Sufa; its drop tanks), https://he.wikipedia.org/wiki/F-16I_סופה
[^hef16]: Hebrew Wikipedia, "F-16 פייטינג פלקון" (Barak, Netz), https://he.wikipedia.org/wiki/F-16_פייטינג_פלקון
[^hef15]: Hebrew Wikipedia, "F-15 איגל" ("שמם שונה ל-F-15I "רעם""; "הכינוי "בז""), https://he.wikipedia.org/wiki/F-15_איגל
[^hef35]: Hebrew Wikipedia, "F-35 לייטנינג II" ("ושמו העברי "אדיר""), https://he.wikipedia.org/wiki/F-35_לייטנינג_II
[^gbu28kopp]: C. Kopp, "Raytheon / Texas Instruments GBU-28 Bunker Buster", Air Power Australia APA-TR-2005-0501
    (4,700 lb, over 19 ft, 630 lb of explosive; EGBU-28/B, EGBU-28C/B), https://ausairpower.net/GBU-28.html
[^gbu28fas]: FAS, "Guided Bomb Unit-28 (GBU-28) Bunker Buster", 22 February 1998 (4,637 lb, 630 lb, 14.5 in, almost
    19 ft; laser; F-15E, F-111F), https://man.fas.org/dod-101/sys/smart/gbu-28.htm
[^gbu28wp]: Wikipedia, "GBU-28" (5.824 m, body 4.04 m, 306 kg tritonal; GBU-28C/B with the BLU-122),
    https://en.wikipedia.org/wiki/GBU-28
[^gbu28photo]: USAF, Tech. Sgt. M. Ammons, an F-15E of the 492nd Fighter Squadron releasing a GBU-28 over the Utah
    Test and Training Range, 5 August 2003, https://commons.wikimedia.org/wiki/File:F-15E_gbu-28_release.jpg
[^awst96]: Aviation Week, "Israel receives first F-15 LANTIRN pod", 11 October 1996 (the LANTIRN navigation pod and
    the Sharpshooter targeting pod for Israel's F-15Is): https://aviationweek.com/israel-receives-first-f-15-lantirn-pod
[^globes05]: Globes, "Pentagon: We'll sell bunker bombs to Israel", 27 April 2005,
    https://en.globes.co.il/en/article-908453
[^globes10]: R. Dagoni, Globes, "US to upgrade Israel Air Force precision munitions", 4 May 2010,
    https://en.globes.co.il/en/article-1000557096
[^fpri26]: G. Plopsky, FPRI, "Rising Lion's Air Offensive: Part I", 12 March 2026,
    https://www.fpri.org/article/2026/03/rising-lions-air-offensive-part-i/
[^kopp85]: C. Kopp, "F-15E – Anatomy of Strike Fighter", Australian Aviation, March 1985 (the CFTs' six tangential
    hardpoints each: outboard up to 1000 lb, inboard fore and aft up to 2000 lb),
    https://www.ausairpower.net/TE-F-15E-Strike-Eagle.html
[^twz35x]: T. Newdick, The War Zone, "Israeli F-35 Shoots Down Cruise Missile", 2 November 2023,
    https://www.twz.com/israeli-f-35-shoots-down-cruise-missile
[^fr1536]: US Federal Register 80 FR 31582, 3 June 2015, Transmittal No. 15-36 (Israel: JDAM kits "4,000 for Mk–82";
    "4,100 GBU–39"; "50 BLU–113 bombs"), https://www.govinfo.gov/content/pkg/FR-2015-06-03/pdf/2015-13478.pdf
[^m50]: General Dynamics OTS, "20mm M50 Series (M53 API, M55 TP, M56 HEI)" data sheet, velocity vs. range chart and
    muzzle velocity 3,450 ft/s at 78 ft: https://www.gd-ots.com/wp-content/uploads/2024/04/400002555-20mm-M50-Series-MED-CAL.pdf
[^navymk36]: US Navy flight manual P-825, "Fuse" (the Sidewinder's Mk 36 rocket motor: 2,880 lb of thrust for a 5.0 s
    burn), https://navyflightmanuals.tpub.com/P-825/Fuse-105.htm; second-hand: a search engine's quote, the site refuses
    automated access.
[^iasg]: T. Tyrell, C. Funk, N. Marton, "AIM-120C-5 Performance Assessment for Digital Combat Simulation Enhancement",
    revision 2, September 2014 (a hobbyist CFD study: 51.26 kg of propellant, 265 s specific impulse, a 7.75 s burn;
    the AIM-120A's boost 6 s and sustain 5 s in other estimates; a straight shot from Mach 0.83 5 km up at a stationary
    point about 35 km), https://www.generalstaff.org/BBOW/Progs/FlySIM/AIM120C5-Performance-Assessment-rev2.pdf
[^wt120]: War Thunder forum, "The AIM-120 'AMRAAM' - History, Design, Performance & Discussion" (a Korean comparison
    table: G-limit 35 for the AIM-120B; other posts 28–40 g, the real figure classified), a forum, weak:
    https://forum.warthunder.com/t/the-aim-120-amraam-history-design-performance-discussion/2584
[^pn]: Wikipedia, "Proportional navigation" (N "generally having an integer value 3-5"),
    https://en.wikipedia.org/wiki/Proportional_navigation
[^p5bro]: Rafael, "Python-5" brochure, as a document-sharing copy shows it (the Python 5 keeps "Python-4s unique
    aerodynamic airframe, INS, powerful rocket motor, warhead and proximity fuze"; second-hand: a search engine's quote),
    https://www.scribd.com/document/230260894/Python-5-Rafael
[^w-flare]: Wikipedia, "Flare (countermeasure)" (newer IR seekers' "sophisticated on-board electronics and secondary electro-optical sensors help discriminate between flares and targets"; spectral and trajectory discrimination, "the so-called CCM") (read 2026-11-22): https://en.wikipedia.org/wiki/Flare_(countermeasure)
[^w-chaff]: Wikipedia, "Chaff (countermeasure)" ("Modern radars use the Doppler effect to measure the line-of-sight velocity of objects, and can thus distinguish chaff from an aircraft"; a jet moving across the beam is "more difficult to separate from the effectively stationary chaff") (read 2026-11-22): https://en.wikipedia.org/wiki/Chaff_(countermeasure)
