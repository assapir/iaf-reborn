# Real aircraft data set

The flight model has two data sets (docs/flight-model.md §11, `crates/iaf-flight/src/data_set.rs`):

* **Original**: the numbers Jane's IAF shipped. The reference version is **v1.1**: its flight data files are used
  when present (§1), else v1.0's.
* **Real**: one table row per flyable jet with public real-world values. Anything a row leaves out keeps the
  original value. The AI types have no row and fly their original data in both sets (§8).

Validation, per jet and data set (rows without a public figure print `-`; `IAF_JET=F-15` runs one jet):

```sh
cargo test --release -p iaf-flight --test validation -- --nocapture
```

Verdicts in this document and in the report: **ok** = inside the public range, **close** = within 10 %,
**off** = further out. **(U)** marks an uncertain or estimated public value.

## 1. v1.1 flight data

The v1.1 patch (docs/formats/rtpatch.md) adds `Resource\Md\bdgen.dat` and `<n>gen.skp` (15 envelopes). The v1.1
exe keeps a table of pairs (`\bd.ibx` / `\bdgen.dat`, `\16.dat` / `\16gen.skp`, … at file offset 0x244e9c) and
reads the new files. They are the same text files, encoded: **byte i XOR (0x67 + i)** (mod 256). `iaf_flight::read_md`
reads a v1.1 file when it is in the install's `resource/md` or in the `iaf-patch` output next to the install
(`assets/v1.1/resource/md`, README), and falls back to v1.0.

Decoded, the 15 envelopes are **identical** to v1.0. `bdgen.dat` changes only these (release note: "Lavi's engine
power is decreased at high altitude and has more drag … Rudder response is increased … Airbrakes are more
effective"):

| section | new `RudderK` | SpeedBrakesDragIndex | WheelsBrakeDragIndex | other |
|---|---|---|---|---|
| F-4 | 7.5 | 300 → 600 | 10000 → 5000 | |
| F-15 | 5.5 | 243 → 500 | 15000 → 9000 | |
| F-16 | 5.5 | 275 → 550 | 15000 → 7000 | |
| MIRAGE | 7.5 | 300 → 600 | 8000 → 4500 | |
| KFIR | 7.5 | 310 → 620 | 8000 → 4000 | |
| MIG23 | 6.25 | 225 → 450 | 15000 → 8000 | |
| MIG29 | 5.5 | 227 → 450 | 15000 → 7500 | |
| LAVI | 7.5 | 250 → 500 | 15000 → 10000 | PlaneDragIndex 450 → 550; thrust full AB: static SL 25000.4 → 24900.4, static 20 km 4000 → 3100, Mach 1.2 at 20 km 8000 → 4550 |
| Autopilot | | | | NoChangeRollCone 4 → 1.75; `SmallConeRollK = 60` → `SlowConeRollK = 90` (renamed key) |

`RudderK` ("rudder jumpiness") is a new key read by the v1.1 exe; our loader does not use it yet (its meaning is
part of the v1.0 → v1.1 exe analysis). The other jets (MIG25/17/21, TU22, C130, SU24) are unchanged. The Lavi
change is large at altitude: v1.0 reached Mach 2.11 at 40k ft, v1.1 Mach 1.80.

## 2. What the Real set can change, and the model's limits

Per row (`data_set.rs`, `Real`): empty weight, internal fuel, thrust (whole table scaled so the SL static full-AB
value is the real one), military / full-AB ratio, a factor on the table's 20 km corners, clean drag coefficient,
transonic wave drag (ΔCD from Mach 0.9 to 1.2, not in the original), wing area, roll rate and roll accelerations,
fuel flow at full AB and at military, 1 g stall speed (`Envelope::stall_floor`), g limits, and rudder-pedal
nose-wheel steering (max wheel angle, wheelbase, tyre grip). Two fields are new in `Params` for this and are
neutral in the original set: `dry_thrust` (1.0) and `dry_fuel_frac` (0.25).

The original thrust and fuel model limits what a row can match:

* **Military thrust.** Below the AB the original runs `k = 0.05 + 0.743·thr`, so military (0.74) is always 60 % of the
  full-AB curve. Real engines: F110 0.59, F100-220 0.61, J79 0.66, PW1120 0.66, Atar 9C 0.71. `dry_thrust` scales
  the dry range to the real ratio (idle moves by the same factor, still ~5 %).
* **Fuel flow** is `thr · FuelFlowAtMaxThrust`, × 0.25 below the AB, and does not change with altitude or speed.
  The row sets full AB and military from the engine's TSFC; cruise at altitude therefore burns too much.
* **Thrust vs Mach / altitude** is a 2 × 2 table: Mach 0 and 1.2 (clamped above), SL and 20 km, linear in both.
  There is no ram rise above Mach 1.2. The published max speeds are **fitted** with the drag coefficient, the wave
  drag and the 20 km factor: the values in those three fields are not real aerodynamic data.
* **Top speed at 40k ft** is reached only after minutes at full AB. Several jets run out of internal fuel first
  (the report shows the time); their row is then "close".
* **Mass** is empty + fuel; stores add drag only. Real weights and wing areas therefore change turn and stall.
* **Climb (Ps)** is measured at 350 kt. Published "initial climb rates" are peak values at the best speed (~Mach 0.9)
  and light weight, so this row reads low for every jet.
* **Sections.** The F-4E and the Kurnass 2000 (types 120 / 200) share `[F-4]`; the Kurnass 2000 kept the J79s and
  the airframe (avionics, wiring, structure), so one row serves both. The original Kfir and Mirage data are nearly
  the same (identical envelopes `kf.dat` = `mr.dat`, same weights, drag, roll, fuel); the Real set separates them.
* Roll acceleration is only changed for the F-16 (FLCS); the other jets keep the original start / stop values, so
  their 0 → 90° roll takes ~1 s.

## 3. F-15C Baz (2 × F100-PW-220)

Variant: the IAF flew F-15A/B from 1976 and F-15C/D from 1981 (F100-PW-100, later -220). The row uses the F-15C
with -220 engines from the USAF Standard Aircraft Characteristics chart (SAC, "F-15C Eagle, two F100-PW-220,
Feb 92"), the only primary document found for these jets.

| item | original (v1.1) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 30,000 lb | 28,476 lb (SAC) | close | 28,476 |
| internal fuel | 13,500 lb | 13,455 lb JP-4 (SAC) | ok | 13,455 |
| thrust SL static mil / AB | 23,076 / 38,460 lbf | 2 × 14,370 / 2 × 23,450 = 28,740 / 46,900 (SAC) | off | 28,740 / 46,900 |
| wing area / span | 608 ft² / 42.8 ft | 608 / 42.81 (SAC) | ok | — |
| 1 g stall | 78 kt | 135 kt at 45,713 lb, power off (SAC) | off | 130 kt (at full internal fuel) |
| max roll rate | 180 deg/s | ~180-220 (U) | ok | — |
| g limits | +9 / −3 | +7.33 at 37,400 lb; OWS up to +9 light; −3 (SAC, T.O.) | ok | — |
| max speed SL | 814 kt (M1.23) | ~800 KCAS (q limit, SAC) | ok | fit: 805 kt |
| max speed 40k ft | 1,120 kt (M1.95) | 1,309 kt M2.28 at 35k, 1,340 kt at 45k (SAC) | off | fit: 1,238 kt (M2.16, fuel runs out) |
| climb SL | 30,400 ft/min (Ps at 350 kt) | 55,960 ft/min at 41,286 lb (SAC) | off | 42,000 (Ps at 350 kt) |
| fuel flow mil / AB | 10,700 / 57,600 lb/h | ~21,000 (TSFC 0.73) / ~98,000 (U) | off | 21,000 / 98,000 |
| nose-wheel steering | stick formula | ±15° normal, ±45° manoeuvre (BMS T.O.-based manual); wheelbase 17.78 ft (SAC) | — | pedals, ±45°, 17.78 ft |

Fit: CD0 0.040, wave drag 0.016, 20 km thrust × 2.4. Biggest original errors: thrust −18 %, stall 78 kt, fuel flow
half the real one.

## 4. F-4E Kurnass (2 × J79-GE-17), also the Kurnass 2000

| item | original (v1.1) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 30,000 lb | ~30,330 lb (Jane's) | ok | 30,330 |
| internal fuel | 12,500 lb | 1,855 gal = 12,060 lb (block 41+); 1,994 gal = 12,960 lb (≤ 40) | ok | 12,060 |
| thrust SL static mil / AB | 15,000 / 25,000 lbf | 2 × 11,870 / 2 × 17,900 = 23,740 / 35,800 (GE) | off (−37 % / −30 %) | 23,740 / 35,800 |
| wing area / span | 530 ft² / 38.42 ft | 530 / 38.4 | ok | — |
| 1 g stall | 145 kt | ~150-165 kt at 40,000 lb (U) | close | — (original kept) |
| max roll rate | 80 deg/s | ~120-180 at 350-450 kt (U) | off | 150 (U) |
| g limits | +7 / −1 | +7.33 (≤ 37,500 lb) / −3 (T.O. 1F-4E-1) | close / off | +7.33 / −3 |
| max speed SL | 643 kt (M0.97) | ~750 KIAS placard (M1.13-1.19) | off | fit: 780 kt (M1.18) |
| max speed 40k ft | 954 kt (M1.66) | M2.17 at 36k ft (Jane's), M2.2-2.23 at 40k | off | fit: 1,239 kt (M2.16) |
| climb SL | 15,700 ft/min (Ps) | 41,300 ft/min; ~61,400 light (U) | off | 28,300 (Ps at 350 kt) |
| fuel flow mil / AB | 10,000 / 54,000 lb/h | ~20,000 / ~71,000 (TSFC ~0.85 / ~1.98) | off | 20,000 / 71,000 |
| nose-wheel steering | stick formula | ±70°, button, below ~70 kt (Heatblur manual, T.O.-based); wheelbase ~23.3 ft (U) | — | pedals, ±70°, 23.3 ft |

Fit: CD0 0.037, wave drag 0.010, 20 km thrust × 1.9. The original F-4 is badly underpowered (subsonic at SL) and
rolls at half the real rate.

## 5. Kfir C7 (IAI J79-J1E)

Variant: C7 (by the late 1990s the IAF's C2s were converted or retired). The C7's 18,750 lbf "combat plus" is a
temporary overboost; the row uses the normal 17,900 lbf.

| item | original (v1.1) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 20,000 lb | 16,060 lb (Jane's; 16,345 in another source) | off (+25 %) | 16,060 |
| internal fuel | 8,000 lb | 2,572 kg = 5,670 lb (Jane's); 2,700 l = 4,760 lb (Wikipedia) (U) | off | 5,670 |
| thrust SL static mil / AB | 9,600 / 16,000 lbf | 11,870 / 17,900 (18,750 combat plus) | off | 11,870 / 17,900 |
| wing area / span | 280 ft² / 30.58 ft | 375 ft² / 26.97 ft | off | 375 ft² (span kept) |
| 1 g stall | 93 kt | approach ~160-175 kt (U) / 1.3 ≈ 125 kt | off | 127 kt (U) |
| max roll rate | 150 deg/s | not public; est. 150-220 | ok (U) | — |
| g limits | +7 / −1 | +7.5 / −3.5 | close / off | +7.5 / −3.5 |
| max speed SL | 734 kt (M1.11) | ~750 kt (M1.13) | ok | fit: 771 kt |
| max speed 40k ft | 1,033 kt (M1.80) | M2.0 sustained, M2.3 dash (~1,317 kt) | off | fit: 1,139 kt (M1.99, fuel runs out) |
| climb SL | 16,300 ft/min (Ps) | 45,930 ft/min (peak, light) | off | 27,900 (Ps at 350 kt) |
| fuel flow mil / AB | 5,300 / 28,800 lb/h | ~9,970 / ~35,200 (TSFC 0.84 / 1.965) | off | 9,970 / 35,200 |
| nose-wheel steering | stick formula | yes (hydraulic); angle not public; wheelbase ~15.96 ft (U) | — | pedals, ±30° (U), 15.96 ft (U) |

Fit: CD0 0.020, wave drag 0.012, 20 km thrust × 1.7.

## 6. Lavi (PW1120)

Variant: the production design figures (Jane's 1987-88). The prototypes flew only to Mach 1.45 before the
cancellation (August 1987); Mach 1.85 and +9 g are design numbers.

| item | original (v1.1; v1.0) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 16,000 lb | 15,500 lb | ok (+3 %) | 15,500 |
| internal fuel | 7,000 lb | 3,330 l ≈ 6,000 lb | off (+17 %) | 6,000 |
| thrust SL static mil / AB | 14,941 / 24,900 lbf (v1.0 25,000) | 13,530-13,550 / 20,585-20,700 | close / off (+21 %) | 13,550 / 20,600 |
| wing area / span | 400 ft² / 28.81 ft | 355.8 ft² wing, 414 ft² with canards / 28.8 ft | ok | — |
| 1 g stall | 86 kt | 110 kt lowest speed flown in the tests | off | 110 kt |
| max roll rate | 220 deg/s | not public (FBW; est. 250-300) | — | — |
| g limits | +9 / −3 | +9 (design) / −3 (U) | ok | — |
| max speed SL | 750 kt (M1.13) (v1.0: 838 kt) | clean not public (est. M1.1-1.2); 538 kt with 8 bombs | ok (U) | fit: 769 kt (M1.16) |
| max speed 40k ft | 1,033 kt (M1.80) (v1.0: 1,207 kt, M2.11) | M1.85, 1,061 kt at 36k ft (Jane's); M1.8 (Wikipedia) | ok | fit: 1,059 kt (M1.85) |
| instantaneous / sustained turn | 21.8 deg/s at 420 kt, 10k ft | 23-24.3 / 12.5-13.2 deg/s at M0.8, 15,000 ft | close | 21.9 |
| climb SL | 36,700 ft/min (Ps) | > 50,000 ft/min (254 m/s) | off | 37,400 (Ps at 350 kt) |
| fuel flow mil / AB | 5,000 / 27,000 lb/h | ~10,800 / ~38,200 (TSFC 0.80 / 1.86) | off | 10,800 / 38,200 |
| nose-wheel steering | stick formula | angle not public; wheelbase 3.86 m = 12.66 ft (Jane's) | — | pedals, ±32° (F-16 value, U), 12.66 ft |

Fit: CD0 0.028, wave drag 0.018, 20 km thrust × 1.4. v1.1 already moved the Lavi towards the real aircraft at
altitude (Mach 2.11 → 1.80); the original is still ~20 % over-powered at SL and 1,000 lb heavy on fuel.

## 7. Mirage IIICJ Shahak (SNECMA Atar 09C)

Variant: the IIICJ without the SEPR rocket (the IAF flew them jet-only). Most "Mirage III" tables on the web are the
longer, heavier IIIE; the IIIC is ~2,000-3,000 lb lighter with less fuel.

| item | original (v1.1) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 20,000 lb | 12,350-13,450 lb | off (+54 %) | 13,000 |
| internal fuel | 8,000 lb | ~2,550-2,900 l ≈ 4,500-5,100 lb (U) | off | 4,800 (U) |
| thrust SL static mil / AB | 9,660 / 16,100 lbf | 9,430-9,440 / 13,240-13,670 | ok / off (+22 %) | 9,436 / 13,228 |
| wing area / span | 280 ft² / 30.58 ft | 375 ft² / 26.97 ft | off | 375 ft² (span kept) |
| 1 g stall | 93 kt | approach 170-200 kt (Dassault 170, pilots ~185) / 1.3 ≈ 130-155 kt | off | 140 kt |
| max roll rate | 150 deg/s | not public; est. 150-200 | ok (U) | — |
| g limits | +7 / −1 | +7 / ~−3 (U) | ok / (U) | — |
| max speed SL | 734 kt (M1.11) | ~M1.1-1.14 (~750 kt) | ok | fit: 758 kt |
| max speed 40k ft | 1,033 kt (M1.80) | M2.1-2.2 at 39k ft | off | fit: 1,134 kt (M1.98) |
| climb SL | 16,400 ft/min (Ps) | 16,400 ft/min (average, understated); 36k ft in ~3 min | ok (U) | 24,900 (Ps at 350 kt) |
| fuel flow mil / AB | 5,300 / 28,800 lb/h | ~9,500 / ~26,900-27,700 (TSFC 1.01 / 2.03) | off / ok | 9,500 / 26,900 |
| nose-wheel steering | stick formula | steerable on the IIIE / 5; IIIC not confirmed; angle not public; wheelbase ~15.96 ft (U) | — | pedals, ±30° (U), 15.96 ft (U) |

Fit: CD0 0.015, wave drag 0.010, 20 km thrust × 2.0. The original Mirage is the Kfir's data (a 20,000 lb jet), so
its weight is the largest single error in the game's data.

## 8. F-16 (unchanged)

The F-16C Block 30/40 row (F110-GE-100) is the previous F-16 set moved into the table, value for value
(validation output identical): empty 19,000 lb, thrust × 1.5, wave drag 0.02, roll 280 deg/s at 900 deg/s²,
fuel flow 16.5 lb/s, stall floor 118 kt, NWS ±32° / 13.2 ft.

## 9. AI types (not in the Real set)

Not implemented: several models share one section (`[TU22]` flies the Su-22, Su-24, Tu-22 and A-4; transports use
the F-16's data, docs/aircraft.md §3), the AI brain is not ported, and there is no test flight to validate against.
Public reference values (from memory of standard references — Jane's, Gordon monographs — not checked this time; medium
confidence) against the original:

| aircraft (section) | empty lb orig / real | fuel lb orig / real | thrust AB SL lbf orig / real (dry) | max g orig / real | wing ft² orig / real |
|---|---|---|---|---|---|
| MiG-21MF/bis (MIG21) | 11,464 / ~11,800-12,050 | 7,000 / ~4,850-5,250 | 12,300 / 14,300-15,650 (9,000) | 9 / 8.5 | 247.6 / 247.6 |
| MiG-23MF/ML (MIG23) | 22,485 / ~22,500 | 12,500 / ~9,500 (U) | 22,000 / 27,540-28,660 (17,600-18,850) | 8 / 8 | 402 / 403 (16°) |
| MiG-25PD (MIG25) | 44,029 / ~44,100 | 20,500 / ~32,000 | 43,400 / 45,000 (33,000) | 4 / 4.5 | 660.9 / 661 |
| MiG-29 9.12 (MIG29) | 20,000 / ~24,000 | 7,000 / ~7,700 | 25,000 / 36,600 (22,200) | 9 / 9 | 447 / 409 |
| MiG-17F (MIG17) | 20,000 / ~8,650 | 7,000 / ~2,560 | 12,500 / 7,450 (5,950) | 5 / 8 | 243.3 / 243 |
| Su-24M (SU24, unused) | 41,888 / ~49,200 | 20,500 / ~24,500 | 43,400 / 49,600 (34,400) | 6 / 6.5 | 452 / 549-594 |
| Tu-22 (TU22) | 88,185 / ~88,000 (U) | 55,000 / ~80,000 (U) | 45,000 / 72,750 (48,500) | 5 / ~2.5 (U) | 1,744 / 1,744 |
| C-130H (C130) | 59,328 / ~75,800 | 35,000 / ~45,000 | 25,000, no AB / 4 × 4,591 shp turboprop | 3 / 2.5 | 1,745 / 1,745 |

Largest AI errors: the MiG-17 (a 20,000 lb, 12,500 lbf jet; real ~8,650 lb, 7,450 lbf) and the MiG-21 fuel.

## 10. Sources

* F-15C: USAF Standard Aircraft Characteristics, "F-15C Eagle, two F100-PW-220", Feb 1992 (AFG 2 Vol-1 Addn 61),
  alternatewars.com SAC collection; USAF F-15 fact sheet; Falcon BMS "TO 1F-15C-1" (NWS modes); Wikipedia F100 (TSFC).
* F-4E: Jane's All the World's Aircraft (weights, speed) via globalsecurity.org; GE J79-GE-17 data; Heatblur F-4E
  manual (fuel system, ground handling; based on T.O. 1F-4E-1); globalsecurity.org "Kurnass 2000".
* Kfir: Jane's via milavia.net; Wikipedia (Amos Dor, *From Mirage to Kfir*); airforce-technology.com (F-21, g limits).
* Lavi: Jane's All the World's Aircraft 1987-88 via Jewish Virtual Library and aerospaceweb.org; Wikipedia (Wilson
  2000); Wikipedia PW1120 (thrust, TSFC); AGARD CP-560 (1995, IAI FCS paper) as quoted on f-16.net (turn rates).
* Mirage IIICJ: Wikipedia (Atar 09C, Mirage III), thisdayinaviation.com, migflug.com, aatlse.org, FlightGear wiki
  (Dassault approach speed), hushkit (pilot interview), SAAF history (nose-wheel steering).
* F-16: see the comments in `data_set.rs` and docs/flight-model.md §11.
