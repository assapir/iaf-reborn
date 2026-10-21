# Real aircraft data set

This doc compares the flight data Jane's IAF shipped with public real-world figures, type by type, and lists the
values the **Real** data set uses. It is for anyone who checks or changes those numbers.

The flight model has two data sets (docs/flight-model.md §11, `crates/iaf-flight/src/data_set.rs`):

* **Original**: the numbers Jane's IAF shipped. The reference version is **v1.1**: its flight data files are used
  when present (§1), else v1.0's.
* **Real**: one table row per aircraft type, with public real-world values: the seven flyable jets in six rows (the
  F-4E and the Kurnass 2000 share one), the F-35I (its data in [f35i.md](f35i.md) §2) and every AI type (§9).
  Anything a row leaves out keeps the original value.

The research for the planned F-16I Sufa option (not built) is in [f16i.md](f16i.md).

**Terms**
- **AI**: computer-flown aircraft. **AB**: afterburner. **mil**: military (full dry) power. **SL**: sea level.
- **TSFC**: thrust-specific fuel consumption (lb of fuel per lbf of thrust per hour). **Ps**: specific excess power,
  here the climb rate it gives. **CD**, **CD0**: drag coefficient, zero-lift drag coefficient.
- **KIAS** / **KCAS**: knots indicated / calibrated airspeed. **MLW**: maximum landing weight. **OEW**: operating
  empty weight. **VMO** / **MMO**: maximum operating speed / Mach number.
- **FBW**: fly-by-wire. **FLCS**: the F-16's flight control system. **NWS**: nose-wheel steering. **OWS**: the F-15's
  overload warning system.
- **SAC**: USAF Standard Aircraft Characteristics chart. **T.O.**: USAF technical order (flight manual; Dash-1).
- **[NAME]**: a section of the flight data file (`bd.ibx`), such as `[TU22]`.

Validation, per type and data set (rows without a public figure print `-`; `IAF_JET=F-15` or `IAF_JET=SU22` runs one
type):

```sh
cargo test --release -p iaf-flight --test validation -- --nocapture
```

Verdicts in this document and in the report: **ok** = inside the public range, **close** = within 10 %,
**off** = further out.

Sources: each public figure carries a footnote to its source (§10). A table's "Sources" line covers its figures
without their own footnote. **uncertain** marks a public value that is loose or disputed. **inferred** marks our
own estimate or derivation (fuel flow from TSFC, stall from landing speed); **fitted, inferred** marks a value fitted
to a published speed. **open** marks a value no source gives.

## 1. v1.1 flight data

The v1.1 patch (docs/formats/rtpatch.md) adds `Resource\Md\bdgen.dat` and `<n>gen.skp` (15 envelopes). The v1.1
exe keeps a table of pairs (`\bd.ibx` / `\bdgen.dat`, `\16.dat` / `\16gen.skp`, … at file offset 0x244e9c) and
reads the new files. They are the same text files, encoded: **byte i XOR (0x67 + i)** (mod 256). `iaf_flight::read_md`
reads a v1.1 file when it is in the install's `resource/md` or in the `iaf-patch` output next to the install
(`assets/v1.1/resource/md`, README), and falls back to v1.0.

Decoded, the 15 envelopes are **identical** to v1.0. `bdgen.dat` changes only these (release note[^v11]: "Lavi's
engine power is decreased at high altitude and has more drag … Rudder response is increased … Airbrakes are more
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

`RudderK` ("rudder jumpiness") is a new key read by the v1.1 exe: the gain of the v1.1 β channel (flight-model.md
§16; exe default 5 for v1.0 data). The other jets (MIG25/17/21, TU22, C130, SU24) are unchanged. The Lavi
change is large at altitude: v1.0 reached Mach 2.11 at 40k ft, v1.1 Mach 1.80.

## 2. What the Real set can change, and the model's limits

Per row (`data_set.rs`, `Real`; the field names in adding-a-plane.md §3): empty weight, internal fuel, thrust (whole
table scaled so the SL static full-AB value is the real one), military / full-AB ratio, a factor on the table's
20 km corners, clean drag coefficient, transonic wave drag (ΔCD from Mach 0.9 to 1.2, an addition to the original),
wing area, roll rate and roll accelerations, fuel flow at full AB and at military, 1 g stall speed
(`Envelope::stall_floor`), g limits, the service ceiling (`Envelope::with_ceiling`, §2.1), the drag chute (§2.2) and
rudder-pedal nose-wheel steering (max wheel angle, wheelbase, tyre grip). Two `Params` fields serve only the Real
set; their original values are neutral: `dry_thrust` (1.0) and `dry_fuel_frac` (0.25).

The original thrust and fuel model limits what a row can match:

* **Military thrust.** Below the AB the original runs `k = 0.05 + 0.743·thr`, so military (0.74) is always 60 % of the
  full-AB curve. Real engines: F110 0.59, F100-220 0.61, J79 0.66, PW1120 0.66, Atar 9C 0.71 (inferred).
  `dry_thrust` scales the dry range to the real ratio (idle moves by the same factor, still ~5 %).
* **Fuel flow** is `thr · FuelFlowAtMaxThrust`, × 0.25 below the AB, and stays the same at every altitude and
  speed. The row sets full AB and military from the engine's TSFC, so cruise at altitude burns too much.
* **Thrust vs Mach / altitude** is a 2 × 2 table: Mach 0 and 1.2 (clamped above), SL and 20 km, linear in both.
  Thrust stays flat above Mach 1.2 (the model has no ram rise). The published max speeds are **fitted** with the
  drag coefficient, the wave drag and the 20 km factor, so those three fields hold fitted values (fitted, inferred),
  not real aerodynamic data.
* **Top speed at 40k ft** is reached only after minutes at full AB. Several jets run out of internal fuel first
  (the report shows the time); their row is then "close".
* **Mass** is empty + fuel; stores add drag only. Real weights and wing areas therefore change turn and stall.
* **Climb (Ps)** is measured at 350 kt. Published "initial climb rates" are peak values at the best speed (~Mach 0.9)
  and light weight, so this row reads low for every jet.
* **Sections.** The F-4E and the Kurnass 2000 (types 120 / 200) share `[F-4]`; the Kurnass 2000 kept the J79s and
  the airframe (avionics, wiring, structure)[^gs-kurnass], so one row serves both. The original Kfir and Mirage data
  are nearly the same (identical envelopes `kf.dat` = `mr.dat`, same weights, drag, roll, fuel); the Real set
  separates them.
* **MaxWeight** (max take-off weight, row field `max_lb`) only sets the lift-ramp limits
  `MaxWeight·(MinG−1 .. MaxG−1)·g`.
  It is set for the AI types. A heavy transport or bomber on a lighter section's value makes less than 1 g of lift.
* **Jets without afterburner** (row field `afterburner`): full throttle gives the table's k = 1 (the rated dry
  thrust), and the fuel flow at full throttle is the row's `ff_ab`.
* **Roll acceleration** changes only for the F-16 (FLCS) and the F-35I (which uses the F-16's values). The other
  jets keep the original start / stop values, so their 0 → 90° roll takes ~1 s.

### 2.1 Service ceilings

The Real set moves the envelope's 1 g ceiling to the public service ceiling. The 1 g ceiling (`Ceiling(1)`) is
the highest altitude where 1 g can be pulled; above it the g limit falls along the high-altitude line and the jet
sinks.

`Envelope::with_ceiling` scales **every altitude** of the envelope file by one factor, so every g's ceiling and the
minimum speeds against altitude stretch with it (sea level is unchanged). The public figures give one ceiling (no per-g
ceilings), so the file's shape is kept. Thrust can still stop the climb lower (the original thrust table, §2).

All values are from online sources. The game's own Jane's extracts[^janes97] served only as a cross-check: their
F-4 10,975 m and Su-24 17,500 m are wrong.

| type (variant) | original 1 g ceiling | real | source | factor |
|---|---|---|---|---|
| F-16C | 54,000 ft | above 50,000 ft | [^usaf-f16] | 0.93 |
| F-15C | 55,000 | 65,000 | [^usaf-f15] | 1.18 |
| F-4E (and Kurnass 2000) | 72,000 | 58,750 (max power, 100 ft/min) | SAC figure via [^airfighters] | 0.82 |
| Kfir C7 | 45,001 | above 58,000 (17,680 m) | [^milavia-kfir] | 1.29 |
| Lavi | 54,000 (the F-16's file) | 50,000 (design, unproven) | [^jvl-lavi] [^wp-lavi] | 0.93 |
| Mirage IIICJ | 45,001 | 17,000 m (55,770) | [^flugzeuginfo] [^jvl-lavi] | 1.24 |
| MiG-21MF | 50,000 | 18,200 m (59,710) | [^airwar] | 1.19 |
| MiG-23ML | 60,000 | 18,500 m (60,700) | [^victorymuseum] | 1.01 |
| MiG-25PD | 70,000 | 20,700 m (67,910) | [^airwar] | 0.97 |
| MiG-29 9.12 | 55,000 | 18,000 m (59,060) | [^ruwiki] [^milru] | 1.07 |
| MiG-17F | 45,001 | 16,600 m (54,460) | [^airwar] | 1.21 |
| Su-22M4 | 45,000 ([TU22]) | 14,200 m (46,590; Su-17M4 15,200 m) | [^ruwiki] | 1.04 |
| Su-24MK | 45,000 ([TU22]) | 11,000 m (36,090) | [^milru] (Su-24M) | 0.80 |
| Tu-22M3 | 45,000 | 13,300 m (43,640) | [^gre] [^ria] | 0.97 |
| A-4N | 45,000 ([TU22]) | 42,250 (uncertain) | [^airfighters] | 0.94 |
| C-130H | 54,000 (the F-16's data) | 33,000 light; 23,000 at the max 42,000 lb payload | [^fas-c130] [^usaf-c130] | 0.97 of [C130] |
| 707-320C | 54,000 (the F-16's data) | 42,000 (max operating altitude) | [^flugzeuginfo] [^wp-specs] | 1.24 of [C130] |
| Il-76MD | 54,000 (the F-16's data) | 12,000 m (39,370) | [^airwar] | 1.16 of [C130] |

The transports' Real rows start from `[C130]` (34,000 ft envelope). The C-130's 33,000 ft is the light-weight
figure: the game's aircraft fly at empty + fuel (§2 "Mass"). Validation prints the "1 g ceiling (envelope)" row.

### 2.2 Drag chute

The original's drag chute (Shift+B, docs/controls.md) is visual only: the loader reads `ParachuteDragIndex`, and no
code uses the value (docs/flight-model.md §1). With Flight data = Real, a deployed chute adds `Params::chute_cd` =
CD · area / wing area to the drag coefficient (`Aircraft::drag_chute`, set by the flight scene while the chute is
out). Rows set `chute: (area m², CD)`; rows without one keep the visual-only chute.

| type | chute | area | CD | ΔCD | sources |
|---|---|---|---|---|---|
| F-4E / Kurnass 2000 | 16 ft ring-slot deceleration chute (4 slot rings) | 18.68 m² | 0.63 | 0.24 | chute[^mills] [^pprune]; ring-slot brake chutes CD 0.56–0.65[^springer] |

Left empty (aircraft-specific CD open; AI-only types): MiG-29 17 m², MiG-23 21 m² cross chute[^ruwiki]
[^sovetarmy]. Kfir / Mirage III sizes: open. The F-4E chute's limit is 200 KIAS[^to-f4e] [^heatblur]; the port models
no chute shear or failure. Measured (tests/godot/test_player_aircraft.gd): from ~90 kt at idle the Kurnass 2000 loses
0.74 m/s in 2 s with the chute, 0.07 m/s without.

### 2.3 Instrument fixes

With Flight data = Real, for every type (`Params::ias_low_speed_fix`, set by `data_set::apply`):
* **Indicated airspeed below 50 kt.** The original's indicated airspeed (FM query 0x10, docs/cockpit.md "Speeds")
  returns the airspeed in kt where m/s is due whenever its formula gives under 50 kt. So while taxiing, the HUD
  (air-to-air modes) and the MFD ADI page read 1.94 × the speed. Real returns the airspeed in m/s
  (`iaf_flight::instruments::ias`). From 50 kt up both sets are the same. (FM: flight model; HUD: head-up display;
  MFD: multi-function display; ADI: attitude director indicator.)

## 3. F-15C Baz (2 × F100-PW-220)

Variant: the IAF flew F-15A/B from 1976 and F-15C/D from 1981 (F100-PW-100, later -220). The game's F-15 is a
single-seat C: its model has one seat, and its Reference text is "F-15C/D Eagle", IDF name Baz. The row uses the F-15C
with -220 engines from the SAC chart[^sac-f15], the only primary document found for these jets.

| item | original (v1.1) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 30,000 lb | 28,476 lb[^sac-f15] | close | 28,476 |
| internal fuel | 13,500 lb | 13,455 lb JP-4[^sac-f15] | ok | 13,455 |
| thrust SL static mil / AB | 23,076 / 38,460 lbf | 2 × 14,370 / 2 × 23,450 = 28,740 / 46,900[^sac-f15] | off | 28,740 / 46,900 |
| wing area / span | 608 ft² / 42.8 ft | 608 / 42.81[^sac-f15] | ok | — |
| 1 g stall | 78 kt | 135 kt at 45,713 lb, power off[^sac-f15] | off | 130 kt (at full internal fuel) |
| max roll rate | 180 deg/s | ~180-220 (inferred) | ok | — |
| g limits | +9 / −3 | +7.33 at 37,400 lb; OWS up to +9 light; −3[^sac-f15] [^bms-f15] | ok | — |
| max speed SL | 814 kt (M1.23) | ~800 KCAS (q limit)[^sac-f15] | ok | 805 kt (fitted, inferred) |
| max speed 40k ft | 1,120 kt (M1.95) | 1,309 kt M2.28 at 35k, 1,340 kt at 45k[^sac-f15] | off | 1,238 kt (M2.16, fuel runs out; fitted, inferred) |
| climb SL | 30,400 ft/min (Ps at 350 kt) | 55,960 ft/min at 41,286 lb[^sac-f15] | off | 42,000 (Ps at 350 kt) |
| fuel flow mil / AB | 10,700 / 57,600 lb/h | ~21,000 (TSFC 0.73[^wp-f100]) / ~98,000 (inferred) | off | 21,000 / 98,000 |
| nose-wheel steering | stick formula | ±15° normal, ±45° manoeuvre[^bms-f15]; wheelbase 17.78 ft[^sac-f15] | — | pedals, ±45°, 17.78 ft |

Fit (fitted, inferred): CD0 0.040, wave drag 0.016, 20 km thrust × 2.4. Biggest original errors: thrust −18 %,
stall 78 kt, fuel flow half the real one.

## 4. F-4E Kurnass (2 × J79-GE-17), also the Kurnass 2000

Sources: Jane's via globalsecurity.org[^janes-gs] (weights, speed), GE engine data[^ge-j79], the Heatblur manual
(fuel system, ground handling)[^heatblur].

| item | original (v1.1) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 30,000 lb | ~30,330 lb[^janes-gs] | ok | 30,330 |
| internal fuel | 12,500 lb | 1,855 gal = 12,060 lb (block 41+); 1,994 gal = 12,960 lb (≤ 40)[^heatblur] | ok | 12,060 |
| thrust SL static mil / AB | 15,000 / 25,000 lbf | 2 × 11,870 / 2 × 17,900 = 23,740 / 35,800[^ge-j79] | off (−37 % / −30 %) | 23,740 / 35,800 |
| wing area / span | 530 ft² / 38.42 ft | 530 / 38.4 | ok | — |
| 1 g stall | 145 kt | ~150-165 kt at 40,000 lb (uncertain) | close | — (original kept) |
| max roll rate | 80 deg/s | ~120-180 at 350-450 kt (uncertain) | off | 150 (inferred) |
| g limits | +7 / −1 | +7.33 (≤ 37,500 lb) / −3[^to-f4e] | close / off | +7.33 / −3 |
| max speed SL | 643 kt (M0.97) | ~750 KIAS placard (M1.13-1.19) | off | 780 kt (M1.18; fitted, inferred) |
| max speed 40k ft | 954 kt (M1.66) | M2.17 at 36k ft[^janes-gs], M2.2-2.23 at 40k | off | 1,239 kt (M2.16; fitted, inferred) |
| climb SL | 15,700 ft/min (Ps) | 41,300 ft/min; ~61,400 light (uncertain) | off | 28,300 (Ps at 350 kt) |
| fuel flow mil / AB | 10,000 / 54,000 lb/h | ~20,000 / ~71,000 (TSFC ~0.85 / ~1.98; inferred) | off | 20,000 / 71,000 |
| nose-wheel steering | stick formula | ±70°, button, below ~70 kt[^heatblur]; wheelbase ~23.3 ft (uncertain) | — | pedals, ±70°, 23.3 ft |

Fit (fitted, inferred): CD0 0.037, wave drag 0.010, 20 km thrust × 1.9. The original F-4 is badly underpowered
(subsonic at SL) and rolls at half the real rate.

## 5. Kfir C7 (IAI J79-J1E)

Variant: C7 (by the late 1990s the IAF's C2s were converted or retired). The C7's 18,750 lbf "combat plus" is a
temporary overboost; the row uses the normal 17,900 lbf.

Sources: Jane's via milavia.net[^milavia-kfir], Wikipedia[^wp-kfir], airforce-technology.com (g limits)[^aft-kfir].

| item | original (v1.1) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 20,000 lb | 16,060 lb[^milavia-kfir]; 16,345 in another source | off (+25 %) | 16,060 |
| internal fuel | 8,000 lb | 2,572 kg = 5,670 lb[^milavia-kfir]; 2,700 l = 4,760 lb[^wp-kfir] (uncertain) | off | 5,670 |
| thrust SL static mil / AB | 9,600 / 16,000 lbf | 11,870 / 17,900 (18,750 combat plus) | off | 11,870 / 17,900 |
| wing area / span | 280 ft² / 30.58 ft | 375 ft² / 26.97 ft | off | 375 ft² (span kept) |
| 1 g stall | 93 kt | approach ~160-175 kt (uncertain) / 1.3 ≈ 125 kt (inferred) | off | 127 kt (inferred) |
| max roll rate | 150 deg/s | open; 150-220 (inferred) | ok (inferred) | — |
| g limits | +7 / −1 | +7.5 / −3.5[^aft-kfir] | close / off | +7.5 / −3.5 |
| max speed SL | 734 kt (M1.11) | ~750 kt (M1.13) | ok | 771 kt (fitted, inferred) |
| max speed 40k ft | 1,033 kt (M1.80) | M2.0 sustained, M2.3 dash (~1,317 kt) | off | 1,139 kt (M1.99, fuel runs out; fitted, inferred) |
| climb SL | 16,300 ft/min (Ps) | 45,930 ft/min (peak, light) | off | 27,900 (Ps at 350 kt) |
| fuel flow mil / AB | 5,300 / 28,800 lb/h | ~9,970 / ~35,200 (TSFC 0.84 / 1.965; inferred) | off | 9,970 / 35,200 |
| nose-wheel steering | stick formula | yes (hydraulic); angle open; wheelbase ~15.96 ft (uncertain) | — | pedals, ±30° (inferred), 15.96 ft (uncertain) |

Fit (fitted, inferred): CD0 0.020, wave drag 0.012, 20 km thrust × 1.7.

## 6. Lavi (PW1120)

Variant: the production design figures (Jane's 1987-88[^jvl-lavi]). The prototypes flew only to Mach 1.45 before
the cancellation (August 1987); Mach 1.85 and +9 g are design numbers.

Sources: Jane's 1987-88 via the Jewish Virtual Library[^jvl-lavi] and aerospaceweb.org[^aerospaceweb-lavi],
Wikipedia[^wp-lavi], the PW1120 page (thrust, TSFC)[^wp-pw1120].

| item | original (v1.1; v1.0) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 16,000 lb | 15,500 lb | ok (+3 %) | 15,500 |
| internal fuel | 7,000 lb | 3,330 l ≈ 6,000 lb | off (+17 %) | 6,000 |
| thrust SL static mil / AB | 14,941 / 24,900 lbf (v1.0 25,000) | 13,530-13,550 / 20,585-20,700[^wp-pw1120] | close / off (+21 %) | 13,550 / 20,600 |
| wing area / span | 400 ft² / 28.81 ft | 355.8 ft² wing, 414 ft² with canards / 28.8 ft | ok | — |
| 1 g stall | 86 kt | 110 kt lowest speed flown in the tests | off | 110 kt |
| max roll rate | 220 deg/s | open (FBW; 250-300 inferred) | — | — |
| g limits | +9 / −3 | +9 (design) / −3 (uncertain) | ok | — |
| max speed SL | 750 kt (M1.13) (v1.0: 838 kt) | clean open (M1.1-1.2 inferred); 538 kt with 8 bombs | ok (inferred) | 769 kt (M1.16; fitted, inferred) |
| max speed 40k ft | 1,033 kt (M1.80) (v1.0: 1,207 kt, M2.11) | M1.85, 1,061 kt at 36k ft[^jvl-lavi]; M1.8[^wp-lavi] | ok | 1,059 kt (M1.85; fitted, inferred) |
| instantaneous / sustained turn | 21.8 deg/s at 420 kt, 10k ft | 23-24.3 / 12.5-13.2 deg/s at M0.8, 15,000 ft[^agard] | close | 21.9 |
| climb SL | 36,700 ft/min (Ps) | > 50,000 ft/min (254 m/s) | off | 37,400 (Ps at 350 kt) |
| fuel flow mil / AB | 5,000 / 27,000 lb/h | ~10,800 / ~38,200 (TSFC 0.80 / 1.86[^wp-pw1120]; inferred) | off | 10,800 / 38,200 |
| nose-wheel steering | stick formula | angle open; wheelbase 3.86 m = 12.66 ft[^jvl-lavi] | — | pedals, ±32° (F-16 value, inferred), 12.66 ft |

Fit (fitted, inferred): CD0 0.028, wave drag 0.018, 20 km thrust × 1.4. v1.1 already moved the Lavi towards the real
aircraft at altitude (Mach 2.11 → 1.80); the original is still ~20 % over-powered at SL and 1,000 lb heavy on fuel.

## 7. Mirage IIICJ Shahak (SNECMA Atar 09C)

Variant: the IIICJ without the SEPR rocket (the IAF flew them jet-only). Most "Mirage III" tables on the web are the
longer, heavier IIIE; the IIIC is ~2,000-3,000 lb lighter with less fuel.

Sources: Wikipedia (Atar 09C, Mirage III)[^wp-mirage], thisdayinaviation.com[^tdia], migflug.com[^migflug],
aatlse.org[^aatlse].

| item | original (v1.1) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 20,000 lb | 12,350-13,450 lb | off (+54 %) | 13,000 |
| internal fuel | 8,000 lb | ~2,550-2,900 l ≈ 4,500-5,100 lb (uncertain) | off | 4,800 (inferred) |
| thrust SL static mil / AB | 9,660 / 16,100 lbf | 9,430-9,440 / 13,240-13,670[^wp-mirage] | ok / off (+22 %) | 9,436 / 13,228 |
| wing area / span | 280 ft² / 30.58 ft | 375 ft² / 26.97 ft | off | 375 ft² (span kept) |
| 1 g stall | 93 kt | approach 170-200 kt (Dassault 170[^fg-mirage], pilots ~185[^hushkit]) / 1.3 ≈ 130-155 kt (inferred) | off | 140 kt |
| max roll rate | 150 deg/s | open; 150-200 (inferred) | ok (inferred) | — |
| g limits | +7 / −1 | +7 / ~−3 (uncertain) | ok / uncertain | — |
| max speed SL | 734 kt (M1.11) | ~M1.1-1.14 (~750 kt) | ok | 758 kt (fitted, inferred) |
| max speed 40k ft | 1,033 kt (M1.80) | M2.1-2.2 at 39k ft | off | 1,134 kt (M1.98; fitted, inferred) |
| climb SL | 16,400 ft/min (Ps) | 16,400 ft/min (average, understated); 36k ft in ~3 min | ok (uncertain) | 24,900 (Ps at 350 kt) |
| fuel flow mil / AB | 5,300 / 28,800 lb/h | ~9,500 / ~26,900-27,700 (TSFC 1.01 / 2.03; inferred) | off / ok | 9,500 / 26,900 |
| nose-wheel steering | stick formula | steerable on the IIIE / 5[^saaf]; IIIC open; angle open; wheelbase ~15.96 ft (uncertain) | — | pedals, ±30° (inferred), 15.96 ft (uncertain) |

Fit (fitted, inferred): CD0 0.015, wave drag 0.010, 20 km thrust × 2.0. The original Mirage is the Kfir's data (a
20,000 lb jet), so its weight is the largest single error in the game's data.

## 8. F-16D

The game's F-16 is the two-seat F-16D (its model; the Reference text: "F-16D Brakeet"). The row (Block 30/40,
F110-GE-100): thrust × 1.5 (≈ 29,000 lbf), wave drag 0.02 (Mach 1.2 SL, ~1.9 at 40k ft), roll 280 deg/s at
900 deg/s² (FLCS), fuel flow 16.5 lb/s at full AB, stall floor 118 kt, NWS ±32° / 13.2 ft, ceiling 50,000 ft (§2.1).
Sources for these: the comments in `data_set.rs` and docs/flight-model.md §11. The D's own values:
* **Internal fuel**: 870.4 US gal (the C 1,053.1, the smaller aft cell)[^f16net-fuel] ≈ 5,800 lb of JP-8 (inferred;
  the original 7,000 lb).
* **Empty weight** 19,100 lb: the one figure published for the D[^aeroweb] (18,900[^airfighters]; the two-seat B
  was +675 lb over the A[^aerospaceweb-b]), from secondary sources only (no Dash-1 figure is public).

## 9. AI types

Every AI aircraft has its own Real row, keyed by **type** (`data_set::TYPES`). The original keys by section: it
gives several types one section, and a transport flies the F-16's data. The in-game switch covers every aircraft in
the mission, so the AI jets fly on the Real rows too (docs/ai.md; `ai_flights.gd` passes the Flight data choice).
Validation: `IAF_JET=SU22 cargo test --release -p iaf-flight --test validation -- --nocapture`. The reference rows
are filled only where public data exists.

Sources for the AI tables: "Jane's" is the game's own Jane's 1997 extracts[^janes97]. Figures without their own
footnote come from the en / ru Wikipedia spec tables and their cited books[^wp-specs], airwar.ru[^airwar] and the
engine sheets[^engines]; which of these gives each figure is open.

**Which section each type flies.** `FUN_005a8980` (v1.0 `5a5bb0`) maps the type code (`default6_1.bdb` object
`0x5b4`) to a section:

| type | model | code | original section | Real set starts from | variant chosen (missions: side) |
|---|---|---|---|---|---|
| MIG21 | mig21 | 150 | MIG21 | MIG21 | MiG-21MF (Arab side) |
| MIG23 | mig23 | 160 | MIG23 | MIG23 | MiG-23ML |
| MIG25 | mig25 | 170 | MIG25 | MIG25 | MiG-25PD |
| MIG29 | mig29 | 180 | MIG29 | MIG29 | MiG-29 9.12 |
| MIG17 | mig17 | 210 | MIG17 | MIG17 | MiG-17F |
| SU22 | su22 | 220 | TU22 | TU22 | Su-22M4 |
| SU24 | su24 | 220 | TU22 | **SU24** | Su-24MK |
| TU22 | tu22 | 220 | TU22 | TU22 | Tu-22M3 (see below) |
| A-4 | a4 | 220 | TU22 | TU22 | A-4N Ayit (Israeli side in 9 of 10 missions) |
| C-130 | c130 | 230 / 240 | — (F-16's data) | **C130** | C-130H Karnaf (Israeli) |
| 707 | boing | 230 / 240 | — (F-16's data) | **C130** | 707-320C Re'em (both sides) |
| IL-76 | il76 | 230 / 240 | — (F-16's data) | **C130** | Il-76MD (Arab side) |

Notes on the table:
* Types 230 / 240 load no section and keep the F-16's parameter block. Type 225 would load `[C130]`, but no object
  has that type. No type loads `[SU24]`.
* The Real set starts the Su-24 from `[SU24]` and the transports from `[C130]`: the designers' own data for these
  aircraft, which the original never loads. Its envelopes are `s.dat` and `130.dat`, and `[C130]` has no afterburner.
  Everything a row leaves out comes from that section (row field `base`).
* `load_with` also gives the type its own code, so a transport is type 230, as in the original (the F-16 is 100).
* Helicopters (type −1) have no section. As far as is known this flight model leaves them out (docs/aircraft.md
  §2.1; inferred), so they have no row.
* **Tu-22.** The original's `[TU22]` numbers (40 t empty, 162 m² wing, 70,500 lbf) are the **Tu-22 Blinder** that
  Libya and Iraq flew. Its span of 112.5 ft is the Backfire's, and the game's 3D model and its Jane's reference card
  (`resource/ref/tu22`) are the **Tu-22M3 Backfire**. The row follows the model the player sees (Tu-22M3). The Blinder
  values are given below in case we switch.

**Common rules for the rows:**
* Stall figures are the published landing (touchdown) speed ÷ 1.1, or approach ÷ 1.3 (inferred).
* `stall_floor` can only raise the envelope's minimum speed. Where the original envelope is already higher (MiG-23,
  MiG-25, Su-24, A-4), the envelope stays and the verdict shows it.
* The roll rate of every AI type is open, so the original's value stays. This matters for the Su-22 and A-4,
  which roll at the Tu-22's 30 deg/s.
* A negative g limit is only changed where one is published.
* Fuel flows from a TSFC are inferred.
* The speed fits (CD0, wave drag, 20 km thrust factor) are **fitted values** (fitted, inferred), not aerodynamic data
  (§2). The MiG-25's 20 km factor of 12.4 is an extreme case: the 2 × 2 thrust table stops at Mach 1.2, so the R-15's
  ram thrust at Mach 2.8 can only be fitted this way.

Verdicts compare the original set with the public value. The last column is the Real set as flown by the
validation test.

### 9.1 MiG-21MF (R-13-300)
| item | original [MIG21] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 11,464 lb | 12,882 lb[^janes97]; 11,795[^airwar] (uncertain) | close | 12,882 |
| internal fuel | 7,000 lb | 2,600 l = 4,586 lb (≈1,800 l usable at low speed) | off (+53 %) | 4,586 |
| thrust mil / AB | 7,380 / 12,300 lbf | 9,340 / 14,550[^janes97]; 8,970 / 14,310 | off | 9,340 / 14,550 |
| max g | +9 / −3 | +8.5[^airwar]; bis manual +8 below M0.8, +7 above (uncertain) | close | +8.5 |
| stall | 134 kt | landing 146 kt → ~133 | ok | 134 (envelope) |
| max speed SL | 577 kt (M0.87) | 702 kt (M1.06) | off | 705 (fitted, inferred) |
| max speed 40k ft | 848 kt (M1.48) | M2.05 above 36k ft | off | 1,181 (M2.06; fitted, inferred) |
| climb SL | 15,400 (Ps) | 21,000 (Jane's table[^janes97]) .. 40,160[^airwar] ft/min (uncertain) | off | 25,300 |
| fuel flow mil / AB | 5,500 / 30,000 lb/h | ~8,970 / ~32,700 (TSFC 0.96 / 2.25) | off / ok | 8,970 / 32,700 |
| roll | 70 deg/s | open | — | — |
| nose-wheel steering | — | none (castoring, differential brakes) | — | — |

Fit: CD0 0.039, wave 0.012, 20 km × 3.17. MiG-21bis for reference: R-25 9,040 / 15,640 lbf (21,830 emergency),
2,880 l, 12,996 lb empty. Low-altitude buffet: Have Doughnut[^doughnut].

### 9.2 MiG-23ML (R-35-300)
| item | original [MIG23] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 22,485 lb | 22,487-22,553 lb | ok | 22,500 |
| internal fuel | 12,500 lb | 4,250 l = 7,496 lb (8,157[^airwar]) | off (+67 %) | 7,496 |
| thrust mil / AB | 13,200 / 22,000 lbf | 18,850 / 28,660 (the original's Mach 1.2 corner is 28,660) | off (−23 %) | 18,850 / 28,660 |
| max g | +8 / −3 | +8.5 below M0.85, +7.5 above | close | +8.5 |
| stall | 157 kt | landing 140-151 kt → ~132 | off | 157 (envelope) |
| max speed SL | 563 kt | 756 kt (M1.14) | off | 757 (fitted, inferred) |
| max speed 40k ft | 806 kt (M1.41) | M2.35 (72° sweep) | off | 1,349 (fitted, inferred) |
| inst. turn | 13.9 deg/s at 420 kt | 16.7 deg/s at 486 kt, 3,300 ft (ML manual via Wikipedia[^wp-specs]) | off | 15.4 |
| climb SL | 14,300 | 42,300-47,250 ft/min | off | 30,500 |
| fuel flow mil / AB | 8,000 / 43,200 | ~17,340 / ~55,600 (TSFC 0.92 / 1.94) | off | 17,340 / 55,600 |
| nose-wheel steering | — | yes (angle open) | — | — |

Fit: CD0 0.041, wave 0.008, 20 km × 4.54. MiG-23BN (R-29B-300): 17,640 / 25,350 lbf, 24,692 lb empty, Mach 1.7.

### 9.3 MiG-25PD (2 × R-15BD-300)
| item | original [MIG25] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 44,029 lb | 41,450 (PD[^airwar]) .. 44,090 lb | ok | 41,450 |
| internal fuel | 20,500 lb | 16,580 l = 32,120 lb[^gordon] | off (−36 %) | 32,120 |
| thrust mil / AB | 26,040 / 43,400 lbf | 2 × 16,535[^gordon] or 19,400[^janes97] (uncertain) / 2 × 24,690 | close | 33,070 / 49,380 |
| max g | +4 / −2 | P +4.5, PD +5 (aileron reversal) | close | +5 |
| stall | 176 kt | landing 146-157 kt → ~137 | off | 176 (envelope) |
| max speed SL | 582 kt (M0.88) | M0.98, ~647 kt (limit) | close | 646 (fitted, inferred) |
| max speed 40k ft | 811 kt (M1.41) | **M2.83** at 42,650 ft | off (−43 %) | 1,616 (M2.82; fitted, inferred) |
| climb SL | 15,000 | 40,900 ft/min (one source, uncertain) | off | 16,300 |
| fuel flow mil / AB | 6,700 / 36,000 | ~41,000 (uncertain) / ~133,000 (TSFC 2.70) | off | 41,300 / 133,300 |

Fit: CD0 0.0585, wave 0, 20 km × 12.4 (see above). The original MiG-25 is a Mach 1.4 aircraft; the real one's
defining figure is its speed.

### 9.4 MiG-29 9.12 (2 × RD-33)

Sources: also globalsecurity.org's MiG-29 specs[^gs-ai].

| item | original [MIG29] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 20,000 lb | 24,030 lb[^janes97] | off (−17 %) | 24,030 |
| internal fuel | 7,000 lb | 4,200-4,365 l = 7,500-8,000 lb | close | 7,720 |
| thrust mil / AB | 15,000 / 25,000 lbf | 2 × 11,110 / 2 × 18,300 = 22,220 / 36,600 | off (−32 %) | 22,220 / 36,600 |
| wing area | 447 ft² | 410 ft² | close | 410 |
| max g | +9 / −3 | +9 below M0.85, +7 above | ok | — |
| stall | 132 kt | landing 127 kt → ~115 | off | 132 (envelope) |
| max speed SL | 775 kt (M1.17) | 700[^janes97] .. 810 kt (uncertain) | ok | 781 (fitted, inferred) |
| max speed 40k ft | 1,108 kt (M1.93) | M2.3 at 11 km | off | 1,322 (fitted, inferred) |
| climb SL | 31,500 | 49,600-65,000 ft/min | off | 42,600 |
| fuel flow mil / AB | 5,300 / 28,800 | ~17,100 / ~75,000 (TSFC 0.77 / 2.05) | off | 17,100 / 75,000 |
| nose-wheel steering | — | ±8° take-off / landing, ±30° taxi[^janes97] | — | — (AI) |

Fit: CD0 0.057, wave 0.015, 20 km × 3.0.

### 9.5 MiG-17F (VK-1F)
| item | original [MIG17] ("Kf 80 %") | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | **20,000 lb** | 8,640-8,684 lb | off (×2.3) | 8,664 |
| internal fuel | 7,000 lb | 1,410 l = 2,487 lb (2,579[^airwar]) | off (×2.8) | 2,487 |
| max take-off | 45,000 lb | 13,380 lb | off | 13,380 |
| thrust mil / AB | 7,500 / 12,500 lbf | 5,730-5,960 / 7,450-7,605 | off (+68 % AB) | 5,730 / 7,450 |
| max g | +5 / −1 | +8 | off | +8 |
| max speed SL | 618 kt (M0.94) | 594 kt (M0.89) | close | 593 (fitted, inferred) |
| max speed 10k ft | — | 617 kt | — | 616 (fitted, inferred) |
| climb SL | 17,500 | 12,795 ft/min | off | 17,500 (Ps) |
| fuel flow mil / AB | 5,500 / 30,000 | ~6,100 (uncertain) / ~19,400 (TSFC 1.07 / 2.61) | close / off | 6,100 / 19,400 |

Fit: CD0 0.0356, wave 0.02, 20 km × 1.2. The section's own comment ("Kf 80 %") shows it was scaled from the Kfir:
this is the largest weight error in the game.

### 9.6 Su-22M4 (AL-21F-3), flown by the original with [TU22]

Sources: also armedconflicts.com (Markovsky & Prikhodchenko, Su-17M4)[^armedconflicts].

| item | original [TU22] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 88,185 lb | 26,810 lb | off (×3.3) | 26,810 |
| internal fuel | 55,000 lb | 4,550 l = 8,311 lb | off (×6.6) | 8,311 |
| thrust mil / AB | 27,000 / 45,000 lbf | 17,200 / 24,700 | off | 17,200 / 24,700 |
| wing area | 1,744 ft² | 414 ft² (30°) / 371 (63°) | off | 414 |
| max g | +5 / −2 | +7 | off | +7 |
| stall | 145 kt | landing 154 kt → ~140 | close | 145 (envelope) |
| max speed SL | < 500 kt (decelerates) | 729-756 kt (M1.1-1.13) | off | 744 (fitted, inferred) |
| max speed 40k ft | 566 kt (M0.99) | ~M1.7 clean (uncertain) | off | 974 (fitted, inferred) |
| climb SL | 2,500 | 45,280 ft/min | off | 24,900 |
| roll | 30 deg/s | open | — | — (still 30) |
| fuel flow mil / AB | 20,000 / 108,000 | ~14,800 / ~45,900 (TSFC 0.86 / 1.86) | off | 14,800 / 45,900 |

Fit: CD0 0.0374, wave 0.015, 20 km × 0.66. Syria's and Libya's earlier Su-22 / Su-22M3 had the R-29BS-300
(25,350 lbf AB). The Su-20 (AL-7F-1, 22,050 lbf) flew with Syria in 1973.

### 9.7 Su-24MK (2 × AL-21F-3A), flown by the original with [TU22]; Real set from [SU24]

Sources: also the Su-24MK brochure table on globalsecurity.org ("MK brochure")[^gs-ai].

| item | original [TU22] ([SU24]) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 88,185 (41,888) lb | 49,160 lb (22.3 t); Jane's[^janes97] 41,890 "empty equipped" (uncertain) | off | 49,160 |
| internal fuel | 55,000 (20,500) lb | 11,700-13,000 l = 21,600-24,470 lb | off (ok) | 21,600 |
| thrust mil / AB | 27,000 / 45,000 (— / 43,400) lbf | 2 × 17,200 / 2 × 24,690 | off (close) | 34,400 / 49,380 |
| wing area | 1,744 (452) ft² | 594 (16°) / 549 (69°) ft² | off | 594 |
| max g | +5 (+6) | +6 (MK brochure[^gs-ai]); +6.5[^janes97] | close | +6 |
| stall | 145 kt | 151 kt, flaps and gear down[^janes97] | close | 202 (the s.dat envelope) |
| max speed SL | < 500 kt | 710-756 kt | off | 706 (fitted, inferred) |
| max speed 40k ft | 566 kt | M1.35 (MK[^gs-ai]) .. M1.6 (M) | off | 860 (M1.5; fitted, inferred) |
| climb SL | 2,500 | 29,530 ft/min | off | 21,600 |
| fuel flow mil / AB | 20,000 / 108,000 | ~29,600 / ~91,800 (inferred) | off | 29,600 / 91,800 |

Fit: CD0 0.030, wave 0.045, 20 km unchanged. The `[SU24]` section is close to the real aircraft, but the original
loads `[TU22]`.

### 9.8 Tu-22M3 Backfire-C (2 × NK-25) — Tu-22 Blinder for comparison

Sources: also milavia.net (Tu-22)[^milavia-tu22]; the Blinder's limits from its flight manual via airwar.ru[^airwar].

| item | original [TU22] | Tu-22M3 (real) | verdict | Real set | Tu-22 Blinder (RD-7M-2) |
|---|---|---|---|---|---|
| empty weight | 88,185 lb | 58-78 t = 127,900-172,000 lb (uncertain) | off | 149,910 (68 t) | 88,180 (40 t) .. 110,230 |
| internal fuel | 55,000 lb | 53,550 kg = 118,060 lb (Jane's[^janes97] ~110,000) | off | 118,060 | up to 97,670 (typ. 81,700-107,000) |
| max take-off | 185,188 lb | 277,780 lb | off | 277,780 | 187,400-207,200 |
| thrust mil / AB | 27,000 / 45,000 lbf | 2 × 31,970 / 2 × 55,120 | off (−59 % AB) | 63,940 / 110,240 | 2 × 24,250 / 2 × 36,380 |
| wing area / span | 1,744 ft² / 112.5 ft | 1,976 ft² / 112.5 ft (20°) | close | 1,976 | 1,746 ft² / 76 ft |
| max g | +5 / −2 | +2.5 (Jane's[^janes97]; 2.2 operational) | off | +2.5 | +2.0 operational, 2.5 recovery |
| stall | 145 kt | landing 154-165 kt at 78-88 t → ~140 | close | 145 (envelope) | min speed 232 kt at 92 t (low alt) |
| max speed SL | < 500 kt | 513-567 kt (M0.78-0.86) | off | 566 (fitted, inferred) | ~481-550 kt |
| max speed 40k ft | 566 kt (M0.99) | M1.88 (Jane's[^janes97]) .. 1,242 kt (Russian sources) | off | 1,077 (fitted, inferred) | M1.42 (815 kt) .. 869 kt |
| fuel flow mil / AB | 20,000 / 108,000 | ~48,600 (cruise SFC, uncertain) / ~231,500 (uncertain) | off | 48,600 / 231,500 | — |

Fit: CD0 0.0714, wave 0.01, 20 km × 6.6. The original's Tu-22 cannot hold 500 kt at sea level and never goes
supersonic.

### 9.9 A-4N Ayit (J52-P-408A), flown by the original with [TU22]

Sources: also FAS (A-4)[^fas-a4].

| item | original [TU22] | real (A-4N; A-4M data) | verdict | Real set |
|---|---|---|---|---|
| empty weight | 88,185 lb | 10,465-10,800 lb | off (×8) | 10,800 |
| internal fuel | 55,000 lb | 800 US gal = 5,440 lb | off (×10) | 5,440 |
| thrust | 45,000 lbf with AB | 11,200 lbf, **no afterburner** | off | 11,200, no AB |
| wing area | 1,744 ft² | 260 ft² | off | 260 |
| max g | +5 / −2 | +8 / −3 (uncertain) | off | +8 / −3 |
| stall | 145 kt | A-4E 121 kt (uncertain) | off | 145 (envelope) |
| max speed SL | < 400 kt | 597 kt clean (A-4M SAC[^wt-a4m]); 561 kt with 4,000 lb of bombs[^janes97] | off | 596 (fitted, inferred) |
| max speed 40k ft | 566 kt | open (subsonic) | — | 549 kt (M0.96) |
| climb SL | 2,500 | 10,300[^janes97] .. 15,650 ft/min (SAC[^wt-a4m], 14,700 lb) | off | 18,800 |
| roll | 30 deg/s | open (claims of 400-760 deg/s, not reliable) | — | — (still 30) |
| fuel flow | 108,000 lb/h (AB) | ~8,850 lb/h (TSFC 0.79) | off | 8,850 |

The IAI extended tailpipe's thrust loss is open. The A-4H (J52-P-8A, 9,300 lbf, ~9,900 lb empty) is the 1973
variant. Fit: CD0 0.05, wave 0.3, 20 km × 0.5. The wave drag here stands in for a subsonic airframe's drag rise.

### 9.10 C-130H Karnaf (4 × T56-A-15), flown by the original with the F-16's data

Sources: also the C-130H operating limits on baseops.net[^baseops].

| item | original (F-16 data) | real | verdict | Real set (from [C130]) |
|---|---|---|---|---|
| empty weight | 16,000 lb | 75,800 lb[^usaf-c130] | off | 75,800 |
| internal fuel | 7,000 lb | 6,960 US gal = 46,600 lb | off | 46,600 |
| max take-off | 32,000 lb | 155,000 lb (175,000 wartime) | off | 155,000 |
| thrust | 19,330 lbf with AB | 4 × 4,508 shp; static ~4 × 10,600-11,500 lbf (inferred) | off | 44,000, no AB |
| max g | +9 | open; 14 CFR 25 minimum +2.5 / −1 (inferred) | off | +2.5 / −1 |
| stall | 86 kt | 100 kt at max normal T-O weight[^janes97] | off | 100 |
| max speed | 881 kt at 20k ft (M1.44) | 320 kt at 20,000 ft | off | 320 (fitted, inferred) |
| climb SL | 21,000 | 1,830-1,900 ft/min | off | 1,060 (Ps at 250 kt) |
| fuel flow | 28,800 lb/h | ~9,000 lb/h (uncertain) | off | 9,000 |
| nose-wheel steering | — | ±60° | — | — (AI) |

Fit: CD0 0.114, no wave drag. The thrust table rises with Mach, where a propeller's thrust falls, so CD0 absorbs
this. The C-130H landing speed is from airandspaceforces.com[^afmag-c130].

### 9.11 Boeing 707-320C Re'em (4 × JT3D-7), flown by the original with the F-16's data

Sources: also Jenkinson's *Civil Jet Aircraft Design* data[^jenkinson].

| item | original (F-16 data) | real | verdict | Real set (from [C130]) |
|---|---|---|---|---|
| empty weight | 16,000 lb | 141,100-148,300 lb OEW | off | 146,000 |
| internal fuel | 7,000 lb | 23,855 US gal = 159,800 lb | off | 159,800 |
| max take-off | 32,000 lb | 333,600 lb | off | 333,600 |
| thrust | 19,330 lbf with AB | 4 × 19,000 lbf | off | 76,000, no AB |
| wing area | 300 ft² | 3,050 ft² | off | 3,050 |
| stall | 86 kt | approach 135 kt at MLW → ~104 | off | 104 |
| max speed | 912 kt at 25k ft (M1.52) | 545 kt max level[^janes97]; VMO 339-378 KIAS, MMO 0.887[^tcds] | off | 546 at 25k ft (fitted, inferred) |
| climb SL | 24,400 | 4,000 ft/min | off | 3,700 (Ps at 300 kt) |
| g | +9 | open; +2.5 / −1 (14 CFR 25; inferred) | off | +2.5 / −1 |

Fit: CD0 0.0456, wave 0.02. Fuel flow at take-off power is open, so `[C130]`'s is kept.

### 9.12 Il-76MD (4 × D-30KP), flown by the original with the F-16's data
| item | original (F-16 data) | real | verdict | Real set (from [C130]) |
|---|---|---|---|---|
| empty weight | 16,000 lb | 88-92 t = 194,000-202,800 lb | off | 196,200 |
| internal fuel | 7,000 lb | 109,480 l = 187,040 lb | off | 187,040 |
| max take-off | 32,000 lb | 418,880 lb (Il-76M 374,790) | off | 418,880 |
| thrust | 19,330 lbf with AB | 4 × 26,455 lbf[^engines] | off | 105,820, no AB |
| wing area | 300 ft² | 3,229 ft² | off | 3,229 |
| max speed | 948 kt at 30k ft (M1.62) | 459 kt (850 km/h[^airwar]; Jane's card[^janes97] says 323 kt, likely an error) (uncertain) | off | 459 at 30k ft (fitted, inferred) |
| g | +9 | open (Il-76LL testbed: +2 / −0.3) | off | +2.5 / −1 (inferred) |
| stall / approach | 86 kt | open | — | 92 (130.dat envelope) |
| nose-wheel steering | — | ±48° tiller, ±7° pedals | — | — (AI) |

Fit: CD0 0.0834, no wave drag.

**Largest original errors**:
* The four types on `[TU22]`: the Su-22 and A-4 fly a 90,000 lb bomber with 1,744 ft² of wing and 30 deg/s of roll.
* The transports: supersonic on F-16 data.
* The MiG-17: 20,000 lb empty, "Kf 80 %".
* The MiG-25: Mach 1.4 (real: Mach 2.8).
* The MiG-21 and MiG-23: subsonic at sea level, and too much fuel.

## 10. Sources

[^v11]: Jane's IAF v1.1 patch release notes.
[^janes97]: The Jane's 1997 extracts the game ships (`resource/ref/<model>/<model>_0.rtf`), cited as "Jane's" in §9.
[^sac-f15]: USAF Standard Aircraft Characteristics, "F-15C Eagle, two F100-PW-220", Feb 1992 (AFG 2 Vol-1 Addn 61),
    alternatewars.com SAC collection.
[^usaf-f15]: USAF F-15 fact sheet.
[^usaf-f16]: USAF F-16 fact sheet.
[^usaf-c130]: USAF C-130 fact sheet.
[^bms-f15]: Falcon BMS "TO 1F-15C-1" (NWS modes; based on the T.O.).
[^wp-f100]: Wikipedia, "Pratt & Whitney F100" (TSFC).
[^janes-gs]: Jane's All the World's Aircraft via globalsecurity.org (F-4E weights, speed).
[^ge-j79]: GE J79-GE-17 engine data.
[^heatblur]: Heatblur F-4E manual (fuel system, ground handling, chute limit; based on T.O. 1F-4E-1).
[^to-f4e]: USAF T.O. 1F-4E-1, F-4E flight manual.
[^gs-kurnass]: globalsecurity.org, "Kurnass 2000".
[^milavia-kfir]: Jane's via milavia.net (Kfir).
[^wp-kfir]: Wikipedia, "IAI Kfir" (citing Amos Dor, *From Mirage to Kfir*).
[^aft-kfir]: airforce-technology.com (F-21 Kfir, g limits).
[^jvl-lavi]: Jane's All the World's Aircraft 1987-88 via the Jewish Virtual Library (Lavi; also the Mirage III
    ceiling).
[^aerospaceweb-lavi]: Jane's All the World's Aircraft 1987-88 via aerospaceweb.org (Lavi).
[^wp-lavi]: Wikipedia, "IAI Lavi" (citing Wilson 2000).
[^wp-pw1120]: Wikipedia, "Pratt & Whitney PW1120" (thrust, TSFC).
[^agard]: AGARD CP-560 (1995), IAI flight control system paper, as quoted on f-16.net (turn rates).
[^wp-mirage]: Wikipedia, "SNECMA Atar 09C" and "Dassault Mirage III".
[^tdia]: thisdayinaviation.com (Mirage III).
[^migflug]: migflug.com (Mirage III).
[^aatlse]: aatlse.org (Mirage III).
[^fg-mirage]: FlightGear wiki, Mirage III (Dassault approach speed).
[^hushkit]: Hush-Kit, Mirage III pilot interview.
[^saaf]: SAAF history (Mirage III nose-wheel steering).
[^f16net-fuel]: f-16.net forum, F-16D fuel capacity: https://www.f-16.net/forum/viewtopic.php?p=10079
[^aeroweb]: aero-web.org (F-16D empty weight).
[^airfighters]: airfighters.com (F-4E SAC ceiling, A-4N ceiling, F-16D empty weight).
[^aerospaceweb-b]: Aerospaceweb (F-16B weight over the A).
[^flugzeuginfo]: flugzeuginfo.net (Mirage III, 707 ceilings).
[^airwar]: airwar.ru (Ugolok Neba) type pages, including the Tu-22 flight-manual limits.
[^victorymuseum]: victorymuseum.ru (MiG-23ML).
[^ruwiki]: ru.wikipedia (MiG-29 and Su-22M4 ceilings; MiG-29 and MiG-23 drag chutes).
[^milru]: Russian Ministry of Defence, mil.ru (MiG-29, Su-24M).
[^gre]: Great Russian Encyclopedia (Tu-22M3).
[^ria]: RIA Novosti (Tu-22M3).
[^fas-c130]: FAS, C-130 (ceiling).
[^mills]: Mills Manufacturing, deceleration parachutes (F-4 chute).
[^pprune]: PPRuNe forum (F-4 chute).
[^springer]: Journal of The Institution of Engineers (India), Springer, 2022 (ring-slot brake chute CD).
[^sovetarmy]: sovetarmy forum (MiG-23 drag chute).
[^wp-specs]: en.wikipedia and ru.wikipedia spec tables and their cited books: Green & Swanborough; Wilson 2000;
    Frawley 2002; Jane's 1992-93 (MiG-21bis); Brassey's 1996/97 (MiG-23); Burdin & Dawes 2006 (Tu-22); Francillon
    1988 (A-4); also the 707 ceiling.
[^gordon]: Yefim Gordon, MiG-25 monograph (via Wikipedia).
[^engines]: Engine sheets: leteckemotory.cz, perm-motors.ru (D-30KP); engine pages on Wikipedia (R-13/25/29/35, R-15,
    RD-33, AL-21, NK-25, RD-7, J52, T56, JT3D, D-30).
[^gs-ai]: globalsecurity.org: MiG-29 specs; Su-24MK brochure table.
[^armedconflicts]: armedconflicts.com (valka), citing Markovsky & Prikhodchenko (Su-17M4).
[^milavia-tu22]: milavia.net (Tu-22).
[^fas-a4]: FAS, A-4.
[^wt-a4m]: A-4M SAC / NATOPS figures as quoted on the War Thunder forum (low confidence).
[^baseops]: baseops.net, C-130H operating limits.
[^afmag-c130]: airandspaceforces.com (C-130H landing speed).
[^jenkinson]: Jenkinson, *Civil Jet Aircraft Design*, data (707).
[^tcds]: FAA Type Certificate Data Sheet 4A26 (707 VMO / MMO, from a search excerpt).
[^doughnut]: Have Doughnut (Lowery, Air Force Magazine): the MiG-21's low-altitude buffet.
