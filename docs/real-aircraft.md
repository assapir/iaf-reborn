# Real aircraft data set

This doc compares the flight data Jane's IAF shipped with public real-world figures, type by type, and lists the
values the **Real** data set uses. It is for anyone who checks or changes those numbers.

The flight model has two data sets (docs/flight-model.md §11, `crates/iaf-flight/src/data_set.rs`):

* **Original**: the numbers Jane's IAF shipped. The reference version is **v1.1**: its flight data files are used
  when present (§1), else v1.0's.
* **Real**: one table row per aircraft type, with public real-world values. The rows cover the seven flyable jets in
  six rows (the F-4E and the Kurnass 2000 share one), the F-35I (docs/f35i.md) and every AI type (§9). Anything a
  row leaves out keeps the original value.
* §11 holds the research for the planned F-16I Sufa option (not built).

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

`RudderK` ("rudder jumpiness") is a new key read by the v1.1 exe: the gain of the v1.1 β channel (flight-model.md
§16; exe default 5 for v1.0 data). The other jets (MIG25/17/21, TU22, C130, SU24) are unchanged. The Lavi
change is large at altitude: v1.0 reached Mach 2.11 at 40k ft, v1.1 Mach 1.80.

## 2. What the Real set can change, and the model's limits

Per row (`data_set.rs`, `Real`): empty weight, internal fuel, thrust (whole table scaled so the SL static full-AB
value is the real one), military / full-AB ratio, a factor on the table's 20 km corners, clean drag coefficient,
transonic wave drag (ΔCD from Mach 0.9 to 1.2, an addition to the original), wing area, roll rate and roll
accelerations,
fuel flow at full AB and at military, 1 g stall speed (`Envelope::stall_floor`), g limits, the service ceiling
(`Envelope::with_ceiling`, §2.1), and rudder-pedal nose-wheel steering (max wheel angle, wheelbase, tyre grip).
Two fields are new in `Params` for this; their original-set values are neutral: `dry_thrust` (1.0) and
`dry_fuel_frac` (0.25).

The original thrust and fuel model limits what a row can match:

* **Military thrust.** Below the AB the original runs `k = 0.05 + 0.743·thr`, so military (0.74) is always 60 % of the
  full-AB curve. Real engines: F110 0.59, F100-220 0.61, J79 0.66, PW1120 0.66, Atar 9C 0.71. `dry_thrust` scales
  the dry range to the real ratio (idle moves by the same factor, still ~5 %).
* **Fuel flow** is `thr · FuelFlowAtMaxThrust`, × 0.25 below the AB, and stays the same at every altitude and
  speed. The row sets full AB and military from the engine's TSFC, so cruise at altitude burns too much.
* **Thrust vs Mach / altitude** is a 2 × 2 table: Mach 0 and 1.2 (clamped above), SL and 20 km, linear in both.
  Thrust stays flat above Mach 1.2 (the model has no ram rise). The published max speeds are **fitted** with the
  drag coefficient, the wave drag and the 20 km factor, so those three fields hold fitted values, not real
  aerodynamic data.
* **Top speed at 40k ft** is reached only after minutes at full AB. Several jets run out of internal fuel first
  (the report shows the time); their row is then "close".
* **Mass** is empty + fuel; stores add drag only. Real weights and wing areas therefore change turn and stall.
* **Climb (Ps)** is measured at 350 kt. Published "initial climb rates" are peak values at the best speed (~Mach 0.9)
  and light weight, so this row reads low for every jet.
* **Sections.** The F-4E and the Kurnass 2000 (types 120 / 200) share `[F-4]`; the Kurnass 2000 kept the J79s and
  the airframe (avionics, wiring, structure), so one row serves both. The original Kfir and Mirage data are nearly
  the same (identical envelopes `kf.dat` = `mr.dat`, same weights, drag, roll, fuel); the Real set separates them.
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

All values are from online sources. The game's own Jane's extracts served only as a cross-check: their F-4 10,975 m
and Su-24 17,500 m are wrong.

| type (variant) | original 1 g ceiling | real | source | factor |
|---|---|---|---|---|
| F-16C | 54,000 ft | above 50,000 ft | USAF fact sheet | 0.93 |
| F-15C | 55,000 | 65,000 | USAF fact sheet | 1.18 |
| F-4E (and Kurnass 2000) | 72,000 | 58,750 (max power, 100 ft/min) | airfighters.com (SAC figure) | 0.82 |
| Kfir C7 | 45,001 | above 58,000 (17,680 m) | milavia.net | 1.29 |
| Lavi | 54,000 (the F-16's file) | 50,000 (design, unproven) | Jewish Virtual Library, Wikipedia | 0.93 |
| Mirage IIICJ | 45,001 | 17,000 m (55,770) | flugzeuginfo.net, Jewish Virtual Library | 1.24 |
| MiG-21MF | 50,000 | 18,200 m (59,710) | airwar.ru | 1.19 |
| MiG-23ML | 60,000 | 18,500 m (60,700) | victorymuseum.ru | 1.01 |
| MiG-25PD | 70,000 | 20,700 m (67,910) | airwar.ru | 0.97 |
| MiG-29 9.12 | 55,000 | 18,000 m (59,060) | ru.wikipedia, Russian MoD | 1.07 |
| MiG-17F | 45,001 | 16,600 m (54,460) | airwar.ru | 1.21 |
| Su-22M4 | 45,000 ([TU22]) | 14,200 m (46,590; Su-17M4 15,200 m) | ru.wikipedia | 1.04 |
| Su-24MK | 45,000 ([TU22]) | 11,000 m (36,090) | Russian MoD (Su-24M) | 0.80 |
| Tu-22M3 | 45,000 | 13,300 m (43,640) | Great Russian Encyclopedia, RIA | 0.97 |
| A-4N | 45,000 ([TU22]) | 42,250 (U) | airfighters.com | 0.94 |
| C-130H | 54,000 (the F-16's data) | 33,000 light; 23,000 at the max 42,000 lb payload | FAS, USAF fact sheet | 0.97 of [C130] |
| 707-320C | 54,000 (the F-16's data) | 42,000 (max operating altitude) | flugzeuginfo.net, Wikipedia | 1.24 of [C130] |
| Il-76MD | 54,000 (the F-16's data) | 12,000 m (39,370) | airwar.ru | 1.16 of [C130] |

The transports' Real rows start from `[C130]` (34,000 ft envelope). The C-130's 33,000 ft is the light-weight
figure: the game's aircraft fly at empty + fuel (§2 "Mass"). Validation prints the "1 g ceiling (envelope)" row.

### 2.2 Drag chute

The original's drag chute (Shift+B, docs/controls.md) is visual only: the loader reads `ParachuteDragIndex`, and no
code uses the value (docs/flight-model.md §1). With Flight data = Real, a deployed chute adds `Params::chute_cd` =
CD · area / wing
area to the drag coefficient (`Aircraft::drag_chute`, set by the flight scene while the chute is out). Rows set
`chute: (area m², CD)`; rows without one keep the visual-only chute.

| type | chute | area | CD | ΔCD | sources |
|---|---|---|---|---|---|
| F-4E / Kurnass 2000 | 16 ft ring-slot deceleration chute (4 slot rings) | 18.68 m² | 0.63 | 0.24 | Mills Manufacturing (deceleration parachutes), PPRuNe; ring-slot brake chutes CD 0.56–0.65 (Springer, J. Inst. Eng. India 2022) |

Left empty (aircraft-specific CD unpublished; AI-only types): MiG-29 17 m², MiG-23 21 m² cross chute
(ru.wikipedia, sovetarmy forum). Kfir / Mirage III sizes not found. The F-4E chute's limit is 200 KIAS (T.O.,
Heatblur F-4E manual); the port models no chute shear or failure. Measured (tests/godot/test_player_aircraft.gd): from
~90 kt at idle the Kurnass 2000 loses 0.74 m/s in 2 s with the chute, 0.07 m/s without.

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

## 8. F-16D

The game's F-16 is the two-seat F-16D (its model; the Reference text: "F-16D Brakeet"). The row (Block 30/40,
F110-GE-100) is the previous F-16C set moved into the table, value for value, with these D values:
* **Internal fuel**: 870.4 US gal (the C 1,053.1, the smaller aft cell;
  [f-16.net](https://www.f-16.net/forum/viewtopic.php?p=10079)) ≈ 5,800 lb of JP-8 (the original 7,000 lb).
* **Empty weight** 19,100 lb: the one figure published for the D (aero-web.org; airfighters.com 18,900; the two-seat
  B was +675 lb over the A, Aerospaceweb), from secondary sources only (no Dash-1 figure is public).

Before, the row was the C's (validation output identical; since then also the service ceiling, §2.1): empty
19,000 lb, thrust × 1.5, wave drag 0.02, roll 280 deg/s at 900 deg/s², fuel flow 16.5 lb/s, stall floor 118 kt,
NWS ±32° / 13.2 ft.

## 9. AI types

Every AI aircraft has its own Real row, keyed by **type** (`data_set::TYPES`). The original keys by section: it
gives several types one section, and a transport flies the F-16's data. The in-game switch covers every aircraft in
the mission, so the AI jets fly on the Real rows too (docs/ai.md; `ai_flights.gd` passes the Flight data choice).
Validation: `IAF_JET=SU22 cargo test --release -p iaf-flight --test validation -- --nocapture`. The reference rows
are filled only where public data exists.

**Which section each type flies.** `FUN_005a5bb0` (v1.1 `5a8980`) maps the type code (`default6_1.bdb` object `0x5b4`)
to a section:

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
  §2.1, UNCERTAIN), so they have no row.
* **Tu-22.** The original's `[TU22]` numbers (40 t empty, 162 m² wing, 70,500 lbf) are the **Tu-22 Blinder** that
  Libya and Iraq flew. Its span of 112.5 ft is the Backfire's, and the game's 3D model and its Jane's reference card
  (`resource/ref/tu22`) are the **Tu-22M3 Backfire**. The row follows the model the player sees (Tu-22M3). The Blinder
  values are given below in case we switch.

**Common rules for the rows:**
* Stall figures are the published landing (touchdown) speed ÷ 1.1, or approach ÷ 1.3.
* `stall_floor` can only raise the envelope's minimum speed. Where the original envelope is already higher (MiG-23,
  MiG-25, Su-24, A-4), the envelope stays and the verdict shows it.
* No public roll rate was found for any AI type, so the original's value stays. This matters for the Su-22 and A-4,
  which roll at the Tu-22's 30 deg/s.
* A negative g limit is only changed where one is published.
* The speed fits (CD0, wave drag, 20 km thrust factor) are **fitted values**, not aerodynamic data
  (§2). The MiG-25's 20 km
  factor of 12.4 is an extreme case: the 2 × 2 thrust table stops at Mach 1.2, so the R-15's ram thrust at Mach 2.8
  can only be fitted this way.

Verdicts compare the original set with the public value. The last column is the Real set as flown by the
validation test.

### 9.1 MiG-21MF (R-13-300)
| item | original [MIG21] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 11,464 lb | 12,882 lb (Jane's); 11,795 (airwar) (U) | close | 12,882 |
| internal fuel | 7,000 lb | 2,600 l = 4,586 lb (≈1,800 l usable at low speed) | off (+53 %) | 4,586 |
| thrust mil / AB | 7,380 / 12,300 lbf | 9,340 / 14,550 (Jane's); 8,970 / 14,310 | off | 9,340 / 14,550 |
| max g | +9 / −3 | +8.5 (airwar); bis manual +8 below M0.8, +7 above (U) | close | +8.5 |
| stall | 134 kt | landing 146 kt → ~133 | ok | 134 (envelope) |
| max speed SL | 577 kt (M0.87) | 702 kt (M1.06) | off | fit 705 |
| max speed 40k ft | 848 kt (M1.48) | M2.05 above 36k ft | off | fit 1,181 (M2.06) |
| climb SL | 15,400 (Ps) | 21,000 (Jane's table) .. 40,160 (airwar) ft/min (U) | off | 25,300 |
| fuel flow mil / AB | 5,500 / 30,000 lb/h | ~8,970 / ~32,700 (TSFC 0.96 / 2.25) | off / ok | 8,970 / 32,700 |
| roll | 70 deg/s | not public | — | — |
| nose-wheel steering | — | none (castoring, differential brakes) | — | — |

Fit: CD0 0.039, wave 0.012, 20 km × 3.17. MiG-21bis for reference: R-25 9,040 / 15,640 lbf (21,830 emergency),
2,880 l, 12,996 lb empty.

### 9.2 MiG-23ML (R-35-300)
| item | original [MIG23] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 22,485 lb | 22,487-22,553 lb | ok | 22,500 |
| internal fuel | 12,500 lb | 4,250 l = 7,496 lb (8,157 airwar) | off (+67 %) | 7,496 |
| thrust mil / AB | 13,200 / 22,000 lbf | 18,850 / 28,660 (the original's Mach 1.2 corner is 28,660) | off (−23 %) | 18,850 / 28,660 |
| max g | +8 / −3 | +8.5 below M0.85, +7.5 above | close | +8.5 |
| stall | 157 kt | landing 140-151 kt → ~132 | off | 157 (envelope) |
| max speed SL | 563 kt | 756 kt (M1.14) | off | fit 757 |
| max speed 40k ft | 806 kt (M1.41) | M2.35 (72° sweep) | off | fit 1,349 |
| inst. turn | 13.9 deg/s at 420 kt | 16.7 deg/s at 486 kt, 3,300 ft (ML manual via Wikipedia) | off | 15.4 |
| climb SL | 14,300 | 42,300-47,250 ft/min | off | 30,500 |
| fuel flow mil / AB | 8,000 / 43,200 | ~17,340 / ~55,600 (TSFC 0.92 / 1.94) | off | 17,340 / 55,600 |
| nose-wheel steering | — | yes (angle not public) | — | — |

Fit: CD0 0.041, wave 0.008, 20 km × 4.54. MiG-23BN (R-29B-300): 17,640 / 25,350 lbf, 24,692 lb empty, Mach 1.7.

### 9.3 MiG-25PD (2 × R-15BD-300)
| item | original [MIG25] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 44,029 lb | 41,450 (airwar PD) .. 44,090 lb | ok | 41,450 |
| internal fuel | 20,500 lb | 16,580 l = 32,120 lb (Gordon) | off (−36 %) | 32,120 |
| thrust mil / AB | 26,040 / 43,400 lbf | 2 × 16,535 (Gordon) or 19,400 (Jane's) (U) / 2 × 24,690 | close | 33,070 / 49,380 |
| max g | +4 / −2 | P +4.5, PD +5 (aileron reversal) | close | +5 |
| stall | 176 kt | landing 146-157 kt → ~137 | off | 176 (envelope) |
| max speed SL | 582 kt (M0.88) | M0.98, ~647 kt (limit) | close | fit 646 |
| max speed 40k ft | 811 kt (M1.41) | **M2.83** at 42,650 ft | off (−43 %) | fit 1,616 (M2.82) |
| climb SL | 15,000 | 40,900 ft/min (one source, U) | off | 16,300 |
| fuel flow mil / AB | 6,700 / 36,000 | ~41,000 (U) / ~133,000 (TSFC 2.70) | off | 41,300 / 133,300 |

Fit: CD0 0.0585, wave 0, 20 km × 12.4 (see above). The original MiG-25 is a Mach 1.4 aircraft; the real one's
defining figure is its speed.

### 9.4 MiG-29 9.12 (2 × RD-33)
| item | original [MIG29] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 20,000 lb | 24,030 lb (Jane's) | off (−17 %) | 24,030 |
| internal fuel | 7,000 lb | 4,200-4,365 l = 7,500-8,000 lb | close | 7,720 |
| thrust mil / AB | 15,000 / 25,000 lbf | 2 × 11,110 / 2 × 18,300 = 22,220 / 36,600 | off (−32 %) | 22,220 / 36,600 |
| wing area | 447 ft² | 410 ft² | close | 410 |
| max g | +9 / −3 | +9 below M0.85, +7 above | ok | — |
| stall | 132 kt | landing 127 kt → ~115 | off | 132 (envelope) |
| max speed SL | 775 kt (M1.17) | 700 (Jane's) .. 810 kt (U) | ok | fit 781 |
| max speed 40k ft | 1,108 kt (M1.93) | M2.3 at 11 km | off | fit 1,322 |
| climb SL | 31,500 | 49,600-65,000 ft/min | off | 42,600 |
| fuel flow mil / AB | 5,300 / 28,800 | ~17,100 / ~75,000 (TSFC 0.77 / 2.05) | off | 17,100 / 75,000 |
| nose-wheel steering | — | ±8° take-off / landing, ±30° taxi (Jane's) | — | — (AI) |

Fit: CD0 0.057, wave 0.015, 20 km × 3.0.

### 9.5 MiG-17F (VK-1F)
| item | original [MIG17] ("Kf 80 %") | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | **20,000 lb** | 8,640-8,684 lb | off (×2.3) | 8,664 |
| internal fuel | 7,000 lb | 1,410 l = 2,487 lb (2,579 airwar) | off (×2.8) | 2,487 |
| max take-off | 45,000 lb | 13,380 lb | off | 13,380 |
| thrust mil / AB | 7,500 / 12,500 lbf | 5,730-5,960 / 7,450-7,605 | off (+68 % AB) | 5,730 / 7,450 |
| max g | +5 / −1 | +8 | off | +8 |
| max speed SL | 618 kt (M0.94) | 594 kt (M0.89) | close | fit 593 |
| max speed 10k ft | — | 617 kt | — | fit 616 |
| climb SL | 17,500 | 12,795 ft/min | off | 17,500 (Ps) |
| fuel flow mil / AB | 5,500 / 30,000 | ~6,100 (U) / ~19,400 (TSFC 1.07 / 2.61) | close / off | 6,100 / 19,400 |

Fit: CD0 0.0356, wave 0.02, 20 km × 1.2. The section's own comment ("Kf 80 %") shows it was scaled from the Kfir:
this is the largest weight error in the game.

### 9.6 Su-22M4 (AL-21F-3), flown by the original with [TU22]
| item | original [TU22] | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 88,185 lb | 26,810 lb | off (×3.3) | 26,810 |
| internal fuel | 55,000 lb | 4,550 l = 8,311 lb | off (×6.6) | 8,311 |
| thrust mil / AB | 27,000 / 45,000 lbf | 17,200 / 24,700 | off | 17,200 / 24,700 |
| wing area | 1,744 ft² | 414 ft² (30°) / 371 (63°) | off | 414 |
| max g | +5 / −2 | +7 | off | +7 |
| stall | 145 kt | landing 154 kt → ~140 | close | 145 (envelope) |
| max speed SL | < 500 kt (decelerates) | 729-756 kt (M1.1-1.13) | off | fit 744 |
| max speed 40k ft | 566 kt (M0.99) | ~M1.7 clean (U) | off | fit 974 |
| climb SL | 2,500 | 45,280 ft/min | off | 24,900 |
| roll | 30 deg/s | not public | — | — (still 30) |
| fuel flow mil / AB | 20,000 / 108,000 | ~14,800 / ~45,900 (TSFC 0.86 / 1.86) | off | 14,800 / 45,900 |

Fit: CD0 0.0374, wave 0.015, 20 km × 0.66. Syria's and Libya's earlier Su-22 / Su-22M3 had the R-29BS-300
(25,350 lbf AB). The Su-20 (AL-7F-1, 22,050 lbf) flew with Syria in 1973.

### 9.7 Su-24MK (2 × AL-21F-3A), flown by the original with [TU22]; Real set from [SU24]
| item | original [TU22] ([SU24]) | real | verdict | Real set |
|---|---|---|---|---|
| empty weight | 88,185 (41,888) lb | 49,160 lb (22.3 t); Jane's 41,890 "empty equipped" (U) | off | 49,160 |
| internal fuel | 55,000 (20,500) lb | 11,700-13,000 l = 21,600-24,470 lb | off (ok) | 21,600 |
| thrust mil / AB | 27,000 / 45,000 (— / 43,400) lbf | 2 × 17,200 / 2 × 24,690 | off (close) | 34,400 / 49,380 |
| wing area | 1,744 (452) ft² | 594 (16°) / 549 (69°) ft² | off | 594 |
| max g | +5 (+6) | +6 (MK brochure); +6.5 (Jane's) | close | +6 |
| stall | 145 kt | 151 kt, flaps and gear down (Jane's) | close | 202 (the s.dat envelope) |
| max speed SL | < 500 kt | 710-756 kt | off | fit 706 |
| max speed 40k ft | 566 kt | M1.35 (MK) .. M1.6 (M) | off | fit 860 (M1.5) |
| climb SL | 2,500 | 29,530 ft/min | off | 21,600 |
| fuel flow mil / AB | 20,000 / 108,000 | ~29,600 / ~91,800 | off | 29,600 / 91,800 |

Fit: CD0 0.030, wave 0.045, 20 km unchanged. The `[SU24]` section is close to the real aircraft, but the original
loads `[TU22]`.

### 9.8 Tu-22M3 Backfire-C (2 × NK-25) — Tu-22 Blinder for comparison
| item | original [TU22] | Tu-22M3 (real) | verdict | Real set | Tu-22 Blinder (RD-7M-2) |
|---|---|---|---|---|---|
| empty weight | 88,185 lb | 58-78 t = 127,900-172,000 lb (U) | off | 149,910 (68 t) | 88,180 (40 t) .. 110,230 |
| internal fuel | 55,000 lb | 53,550 kg = 118,060 lb (Jane's ~110,000) | off | 118,060 | up to 97,670 (typ. 81,700-107,000) |
| max take-off | 185,188 lb | 277,780 lb | off | 277,780 | 187,400-207,200 |
| thrust mil / AB | 27,000 / 45,000 lbf | 2 × 31,970 / 2 × 55,120 | off (−59 % AB) | 63,940 / 110,240 | 2 × 24,250 / 2 × 36,380 |
| wing area / span | 1,744 ft² / 112.5 ft | 1,976 ft² / 112.5 ft (20°) | close | 1,976 | 1,746 ft² / 76 ft |
| max g | +5 / −2 | +2.5 (Jane's; 2.2 operational) | off | +2.5 | +2.0 operational, 2.5 recovery |
| stall | 145 kt | landing 154-165 kt at 78-88 t → ~140 | close | 145 (envelope) | min speed 232 kt at 92 t (low alt) |
| max speed SL | < 500 kt | 513-567 kt (M0.78-0.86) | off | fit 566 | ~481-550 kt |
| max speed 40k ft | 566 kt (M0.99) | M1.88 (Jane's) .. 1,242 kt (Russian) | off | fit 1,077 | M1.42 (815 kt) .. 869 kt |
| fuel flow mil / AB | 20,000 / 108,000 | ~48,600 (cruise SFC, U) / ~231,500 (U) | off | 48,600 / 231,500 | — |

Fit: CD0 0.0714, wave 0.01, 20 km × 6.6. The original's Tu-22 cannot hold 500 kt at sea level and never goes
supersonic.

### 9.9 A-4N Ayit (J52-P-408A), flown by the original with [TU22]
| item | original [TU22] | real (A-4N; A-4M data) | verdict | Real set |
|---|---|---|---|---|
| empty weight | 88,185 lb | 10,465-10,800 lb | off (×8) | 10,800 |
| internal fuel | 55,000 lb | 800 US gal = 5,440 lb | off (×10) | 5,440 |
| thrust | 45,000 lbf with AB | 11,200 lbf, **no afterburner** | off | 11,200, no AB |
| wing area | 1,744 ft² | 260 ft² | off | 260 |
| max g | +5 / −2 | +8 / −3 (U) | off | +8 / −3 |
| stall | 145 kt | A-4E 121 kt (U) | off | 145 (envelope) |
| max speed SL | < 400 kt | 597 kt clean (A-4M SAC); 561 kt with 4,000 lb of bombs (Jane's) | off | fit 596 |
| max speed 40k ft | 566 kt | not public (subsonic) | — | 549 kt (M0.96) |
| climb SL | 2,500 | 10,300 (Jane's) .. 15,650 ft/min (SAC, 14,700 lb) | off | 18,800 |
| roll | 30 deg/s | not reliably public (claims of 400-760 deg/s) | — | — (still 30) |
| fuel flow | 108,000 lb/h (AB) | ~8,850 lb/h (TSFC 0.79) | off | 8,850 |

The IAI extended tailpipe's thrust loss is not public. The A-4H (J52-P-8A, 9,300 lbf, ~9,900 lb empty) is the 1973
variant.
Fit: CD0 0.05, wave 0.3, 20 km × 0.5. The wave drag here stands in for a subsonic airframe's drag rise.

### 9.10 C-130H Karnaf (4 × T56-A-15), flown by the original with the F-16's data
| item | original (F-16 data) | real | verdict | Real set (from [C130]) |
|---|---|---|---|---|
| empty weight | 16,000 lb | 75,800 lb (USAF) | off | 75,800 |
| internal fuel | 7,000 lb | 6,960 US gal = 46,600 lb | off | 46,600 |
| max take-off | 32,000 lb | 155,000 lb (175,000 wartime) | off | 155,000 |
| thrust | 19,330 lbf with AB | 4 × 4,508 shp; static ~4 × 10,600-11,500 lbf (derived, U) | off | 44,000, no AB |
| max g | +9 | not found; 14 CFR 25 minimum +2.5 / −1 (U) | off | +2.5 / −1 |
| stall | 86 kt | 100 kt at max normal T-O weight (Jane's) | off | 100 |
| max speed | 881 kt at 20k ft (M1.44) | 320 kt at 20,000 ft | off | fit 320 |
| climb SL | 21,000 | 1,830-1,900 ft/min | off | 1,060 (Ps at 250 kt) |
| fuel flow | 28,800 lb/h | ~9,000 lb/h (U) | off | 9,000 |
| nose-wheel steering | — | ±60° | — | — (AI) |

Fit: CD0 0.114, no wave drag. The thrust table rises with Mach, where a propeller's thrust falls, so CD0 absorbs
this.

### 9.11 Boeing 707-320C Re'em (4 × JT3D-7), flown by the original with the F-16's data
| item | original (F-16 data) | real | verdict | Real set (from [C130]) |
|---|---|---|---|---|
| empty weight | 16,000 lb | 141,100-148,300 lb OEW | off | 146,000 |
| internal fuel | 7,000 lb | 23,855 US gal = 159,800 lb | off | 159,800 |
| max take-off | 32,000 lb | 333,600 lb | off | 333,600 |
| thrust | 19,330 lbf with AB | 4 × 19,000 lbf | off | 76,000, no AB |
| wing area | 300 ft² | 3,050 ft² | off | 3,050 |
| stall | 86 kt | approach 135 kt at MLW → ~104 | off | 104 |
| max speed | 912 kt at 25k ft (M1.52) | 545 kt max level (Jane's); VMO 339-378 KIAS, MMO 0.887 | off | fit 546 at 25k ft |
| climb SL | 24,400 | 4,000 ft/min | off | 3,700 (Ps at 300 kt) |
| g | +9 | not found; +2.5 / −1 (14 CFR 25, U) | off | +2.5 / −1 |

Fit: CD0 0.0456, wave 0.02. Fuel flow is not public at take-off power, so `[C130]`'s is kept.

### 9.12 Il-76MD (4 × D-30KP), flown by the original with the F-16's data
| item | original (F-16 data) | real | verdict | Real set (from [C130]) |
|---|---|---|---|---|
| empty weight | 16,000 lb | 88-92 t = 194,000-202,800 lb | off | 196,200 |
| internal fuel | 7,000 lb | 109,480 l = 187,040 lb | off | 187,040 |
| max take-off | 32,000 lb | 418,880 lb (Il-76M 374,790) | off | 418,880 |
| thrust | 19,330 lbf with AB | 4 × 26,455 lbf | off | 105,820, no AB |
| wing area | 300 ft² | 3,229 ft² | off | 3,229 |
| max speed | 948 kt at 30k ft (M1.62) | 459 kt (850 km/h, airwar; Jane's card says 323 kt, likely an error) (U) | off | fit 459 at 30k ft |
| g | +9 | not found (Il-76LL testbed: +2 / −0.3) | off | +2.5 / −1 (U) |
| stall / approach | 86 kt | not found | — | 92 (130.dat envelope) |
| nose-wheel steering | — | ±48° tiller, ±7° pedals | — | — (AI) |

Fit: CD0 0.0834, no wave drag.

**Largest original errors**:
* The four types on `[TU22]`: the Su-22 and A-4 fly a 90,000 lb bomber with 1,744 ft² of wing and 30 deg/s of roll.
* The transports: supersonic on F-16 data.
* The MiG-17: 20,000 lb empty, "Kf 80 %".
* The MiG-25: Mach 1.4 (real: Mach 2.8).
* The MiG-21 and MiG-23: subsonic at sea level, and too much fuel.

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
* Service ceilings (§2.1): USAF fact sheets (F-16, F-15, C-130H); airfighters.com (F-4E, A-4N); milavia.net (Kfir);
  Jewish Virtual Library and Wikipedia (Lavi); flugzeuginfo.net (Mirage III, 707); airwar.ru (MiG-21MF, MiG-25PD,
  MiG-17F, Il-76MD); victorymuseum.ru (MiG-23ML); ru.wikipedia (MiG-29, Su-22M4); mil.ru (Su-24M); Great Russian
  Encyclopedia and RIA (Tu-22M3); FAS (C-130).
* AI types:
  * The Jane's 1997 extracts the game ships (`resource/ref/<model>/<model>_0.rtf`, cited as "Jane's").
  * en.wikipedia and ru.wikipedia spec tables and their cited books:
    * Gordon's MiG-25 monograph; Green & Swanborough; Wilson 2000; Frawley 2002.
    * Jane's 1992-93 (MiG-21bis); Brassey's 1996/97 (MiG-23).
    * Burdin & Dawes 2006 (Tu-22); Francillon 1988 (A-4).
  * airwar.ru (Ugolok Neba) type pages, including the Tu-22 flight-manual limits.
  * Engine sheets: leteckemotory.cz, perm-motors.ru (D-30KP); engine pages on Wikipedia (R-13/25/29/35, R-15,
    RD-33, AL-21, NK-25, RD-7, J52, T56, JT3D, D-30).
  * globalsecurity.org: MiG-29 specs; Su-24MK brochure table.
  * armedconflicts.com (valka; Markovsky & Prikhodchenko for the Su-17M4); milavia.net (Tu-22); FAS (A-4).
  * A-4M SAC / NATOPS figures as quoted on the War Thunder forum (low confidence).
  * USAF C-130 fact sheet; C-130H operating limits (baseops.net); airandspaceforces.com (C-130H landing speed).
  * Jenkinson, *Civil Jet Aircraft Design* data (707); FAA TCDS 4A26 (707 VMO / MMO, from a search excerpt).
  * Have Doughnut (Lowery, Air Force Magazine) for the MiG-21's low-altitude buffet.

## 11. F-16I Sufa (research for the Sufa option; not built)

This section collects the public data for the IAF's F-16I Sufa ("Storm"), the jet of the planned Extras switch
"F-16: Barak (1990s) / Sufa (F-16I)" (docs/roadmap.md "F-16I Sufa option"). It says, part by part, what the game
would change and where the number comes from. Research date: 2026-10-19.

- **Sources:** a footnote names the source of each fact. "Inferred" marks our own reasoning from the sources; "open"
  means no public source was found.
- **Terms:** CFT = conformal fuel tank (a tank shaped to the fuselage's upper sides). WSO = weapon systems officer
  (the back seat). AIFF = advanced IFF (identification friend or foe): an interrogator as well as a transponder.
  LOAL = lock-on after launch. SAR = synthetic-aperture radar (a photo-like ground map). EW = electronic warfare.
  MAW = missile approach warner. FS = US Federal Standard 595 colour number.

**Key facts**
- A two-seat F-16D Block 52+ built for Israel: 102 jets ordered in 2000 and 2001 (Peace Marble V), first flight
  23 December 2003, deliveries from 19 February 2004[^sufa-wiki-var].
- About half the avionics are Israeli[^sufa-wiki-var]: Elbit helmet, HUD (head-up display) software, mission and
  display computers, digital map[^sufa-wiki-var][^sufa-at]; an Elisra EW suite[^sufa-at].
- Visible differences from the game's F-16D Barak: the CFTs over the wing roots, the P&W engine's nozzle, a
  different set of antennas[^sufa-isradecals]. Like the Barak, it has the large dorsal spine, which holds avionics
  and chaff / flare dispensers[^sufa-f16net-first].
- It takes the F-16D's slot (type code 100), so the missions, AI F-16s and loadouts stay as they are (§11.9).

### 11.1 Flight data

The game's Real row for the F-16 is the F-16D Block 30/40 with the F110-GE-100 (§8, `crates/iaf-flight/src/data_set.rs`).
A Sufa row would change these fields (docs/adding-a-plane.md §3 names them):

| field | F-16D row (§8) | F-16I public figure | Sufa row (proposed) |
|---|---|---|---|
| `thrust` | `Scale(1.5)` ≈ 29,000 lbf (F110-GE-100) | F100-PW-229: 29,160 lbf with AB, 17,800 lbf military[^sufa-f100] | `StaticAb(29_160)` |
| `mil_ratio` | none (the original's 60 %) | 17,800 / 29,160 = 0.61[^sufa-f100] | 0.61 |
| `ff_ab_lb_s`, `ff_mil_lb_h` | 16.5 lb/s; military from the ×0.25 rule | TSFC 1.94 with AB, 0.76 military[^sufa-f100] → 56,600 lb/h and 13,500 lb/h (inferred) | 15.7 lb/s, 13,500 lb/h |
| `empty_lb` | 19,100 lb | 8,809 kg = 19,420 lb[^sufa-at]; 9,000 kg = 19,840 lb[^sufa-mf]; both secondary, without saying whether the CFTs are on. The CFT pair weighs 900 lb empty[^sufa-warhistory] | 20,500 lb: 19,600 (between the two) + 900 for the CFTs, which IAF jets normally carry (inferred) |
| `fuel_lb` | 5,800 lb (870.4 US gal) | internal: the F-16D tankage (inferred); CFTs: 450 US gal, about 3,050 lb[^sufa-lm-cft02] (the 2001 release said 440 gal, 3,000 lb[^sufa-lm-cft01]) | 8,850 lb (5,800 + 3,050), one pool as today (docs/weapons.md §2.6) |
| `max_lb` | not set | 23,582 kg = 52,000 lb, with heavyweight landing gear[^sufa-at]; the Block 50/52 42,300 lb[^sufa-f16net-b50]; one site gives 37,479 lb[^sufa-mf] (the light Block 40 figure, inferred) | 52,000 lb |
| `g` | original +9 | +9 with the CFTs: "The aircraft retains its full 9-g capability and flight envelope with the CFTs installed"[^sufa-lm-cft01] | not set (+9 / original negative) |
| `cd0` | original, fitted | CFTs: "less than one percent" more drag "in combat configuration at cruise"[^sufa-lm-cft01]; 12 % of the drag of the 300 US gal centreline tank, for 50 % more fuel[^sufa-lm-cft02] | the F-16D value + 1 % (inferred); refit both top speeds |
| `wave_drag` | 0.02 (fitted) | CFT effect above Mach 0.9: open | 0.02 until a figure is found |
| top speeds | Mach 1.2 SL, ~1.9 at 40k ft (fit) | "Mach 2 at altitude"[^sufa-at]; with CFTs: open | fit as the F-16D (Mach 1.2 / ~1.9), inferred |
| `ceiling_ft` | 50,000 ft | 16,000 m = 52,490 ft[^sufa-mf] (secondary; the USAF F-16 "above 50,000 ft") | 50,000 ft (no change) |
| `stall_kt` | 118 kt | open | 118 · √(29,350 / 24,900) ≈ 128 kt, if the F-16D's 118 kt is at full fuel (inferred) |
| `roll_deg_s`, `roll_accel` | 280 deg/s, 900 deg/s² (FLCS) | open | as the F-16D (same FLCS, inferred) |
| `nose_wheel` | ±32°, 13.2 ft | open (the airframe is the D's) | as the F-16D |

Notes:
- Thrust is nearly the F-16D row's, but the jet is about 18 % heavier at full fuel (29,350 lb against 24,900 lb), so
  the Sufa turns and climbs less well and flies further (inferred).
- The game counts no store weight for tanks (docs/weapons.md §2.5 bug c); as internal fuel, the CFTs' fuel does
  weigh. The 900 lb of empty CFTs go into `empty_lb`, since the game has no CFT store.
- The CFTs carry no stores: "nothing is suspended from them"[^sufa-lm-cft01].

### 11.2 Radar: AN/APG-68(V)9

- **What it adds** over the APG-68(V)5 / (V)7 / (V)8: 30 % more air-to-air detection range, 5× processing speed and
  10× memory[^sufa-lm-radar]; Lockheed puts the range gain against the (V)7/8.
- **Modes** (each named in a source):
  - air-to-air: range-while-search, air combat, track-while-scan, single-target track, cluster resolution, target
    illumination[^sufa-at]; situation-awareness mode with four tracked targets (two before)[^sufa-lm-radar];
  - air-to-ground: SAR with 2 ft resolution, ground moving target, sea surveillance, terrain following[^sufa-at][^sufa-lm-radar].
- **Ranges:** no public figure in nautical miles (open). Applied to the game's tables (inferred):
  - Weapon data = Real: `RADAR_KM` F-16 80 km × 1.3 ≈ 104 km (docs/real-weapons.md §1.3);
  - the mode table (docs/radar.md §1, F-16 row): LRS 45 → 58 NM, TWS 35 → 45 NM; ACM, BORE, MAP and GMT unchanged.
    The range scale stays at most 80 NM (index 5).
- **New for the game:** the SAR map and the four-target situation mode have no counterpart in the original's nine
  modes. They belong to the Real MFDs (docs/roadmap.md), not to this switch.

### 11.3 AIFF

- The Block 52+ AIFF for other users is the BAE (formerly Marconi) AN/APX-113 combined interrogator / transponder.
  Lockheed lists it in F-16s of Belgium, Denmark, Greece, the Netherlands, Norway and Taiwan; Israel is not
  listed[^sufa-f16net-apx113]. Which set the Sufa carries: open (an Israeli set is possible).
- Proposed: the decision of docs/real-hud.md "IFF" for the modern F-16, that is the MLU behaviour. TMS left starts an
  interrogation. A green circle (friend) or a yellow square (unknown) shows on the FCR (fire-control radar) page at
  the reply's own position, for 3 s (the only figure found, from a simulator guide). The Israeli symbols are open, so
  these are inferred from the F-16 MLU guide.

### 11.4 Helmet, HUD and MFDs

| item | F-16D Barak in the game | F-16I Sufa |
|---|---|---|
| helmet | Elbit DASH III (docs/real-hud.md "DASH helmet") | Elbit DASH IV, in both cockpits[^sufa-at][^sufa-dash4]; its symbology: open |
| HUD | Block 30/40/50 HUD, the dash-34 symbology | an El-Op (Elbit) wide-angle HUD[^sufa-at]; symbology from the Israeli mission computer: open |
| head-down displays | the original's three monochrome MFD pages | colour 4 × 4 in MFDs, 120 pixels per inch (Astronautics)[^sufa-at]; six colour LCDs of 484 × 484 pixels across both cockpits, driven by Elbit's display processor, with the digital map built in[^sufa-du] |
| map | the original's TSD page | a colour moving map[^sufa-at][^sufa-du] |
| rear seat | a second pilot | a WSO station; one switch reconfigures it for an instructor pilot[^sufa-du] |

- **DASH IV:** built by VSI (Elbit and Rockwell Collins), from the DASH line[^sufa-dash4]. Differences from DASH III:
  open. The game's DASH layout (docs/real-hud.md) serves for both (inferred).
- **HUD:** the Real HUD's F-16 symbology (docs/real-hud.md "F-16C/D (Block 30/40/50)") stays, as the closest public
  layout (inferred). Additions the weapons need: the AIM-120 / Derby DLZ (dynamic launch zone; the game's MRM sight
  has one, docs/weapons.md §11.2) and the Python 5 cue off boresight (§11.5).
- **Cockpit art:** colour MFD pages are new art. They come with the Real MFDs (docs/roadmap.md), drawn in the real
  formats; the original's pages stay the default.

### 11.5 Weapons and stations

Stations: the F-16's nine (1 and 9 the wingtip rails, 5 the centreline), the game's StationA..I. The CFTs free
stations 4 and 6, rated 4,500 lb each and normally used for wing tanks, for weapons[^sufa-at]. The CFTs have no
stations of their own[^sufa-lm-cft01].

| weapon | public data | in the game (docs/weapons.md type) |
|---|---|---|
| Python 5 | IIR (imaging infrared) and electro-optical seeker, LOAL, up to 100° off boresight; 105 kg, > 20 km, Mach 4[^sufa-python] | new record, type 570; the wide cone and LOAL are new rules |
| Python 4 | carried[^sufa-at] | `PYTH-4` (exists) |
| Derby | active radar, ~50 km, 118 kg, Mach 4[^sufa-derby]; carried[^sufa-at] | new record, type 600 (active radar, as AMRAAM) |
| AIM-120C | AMRAAM carried[^sufa-warhistory]; 200 AIM-120C-7 requested in 2007[^sufa-dsca]; C range 90 km, 161.5 kg[^sufa-aim120] | `AMRAAM` with the C's numbers (Weapon data = Real) |
| AIM-9M | carried[^sufa-wt] | `AIM-9M` (exists) |
| JDAM (GBU-31) | carried[^sufa-wt]; a BLU-109 JDAM on an F-16I in an IDF photo[^sufa-photo-jdam] | new: GPS-guided, no seeker; nearest the guided motion of type 650 without a laser (inferred) |
| GBU-10 / 12 / 15 / 16 | carried[^sufa-wt] | `MK-84L` / `MK-82L` / `GBU15` / `MK-83L` (exist) |
| SPICE 1000 / 2000 | EO / GPS kit, 453 / 907 kg, 100 / 60 km, in service 2003, on F-16s[^sufa-spice] | new record, type 640 (TV, guided glide) |
| Popeye, Delilah | carried[^sufa-wt] | `POPEYE` (exists); Delilah new |
| Rampage | first used April 2019 by F-16Is; 570 kg, 4.7 m[^sufa-rampage] | new (stand-off missile) |
| Litening targeting pod | Rafael Litening II; also the LANTIRN navigation pod[^sufa-at] | `FLIR` / `TV POD` stores (exist) |
| gun | M61A1 20 mm[^sufa-mf] | `20 MM`; rounds as the F-16D (inferred) |

The weapons the game lacks belong to "Modern aircraft and weapons" in docs/roadmap.md. A Sufa switch can start with
the existing records (`AMRAAM`, `PYTH-4`, `AIM-9M`, the laser bombs, `POPEYE`) and add Python 5, Derby, JDAM and
SPICE one at a time (inferred).

### 11.6 RWR and EW suite

- **Delivered suite** (Elisra): radar warning receivers, missile approach warners and the SPS-3000 self-protection
  jammer; chaff and flare dispensers by Rokar[^sufa-at]. The jammer sits in the dorsal spine[^sufa-periscope].
  Military Periscope instead names the SPS-3000 as Elisra's 0.5–18 GHz radar warning receiver, and the jammer as the
  SPJ-40[^sufa-periscope]; which is right: open.
- An Israeli towed decoy replaces the ALE-50[^sufa-wiki-var].
- **2025 upgrade:** Elbit's self-protection suite (about USD 80 million, January 2025): an EW system, the PAWS
  passive infrared warner ("the direction, missile type, and time to impact"), launch detection, and new chaff /
  flare dispensers[^sufa-janes].
- **In the game:** the RWR's logic stays (docs/rwr.md). The F-16 type already has a built-in ECM (docs/weapons.md
  §10), which stands for the internal jammer. A missile-approach warning is new: the RWR list already holds the
  missiles launched at the jet (docs/rwr.md §1), so a MAW cue could read it (inferred). The towed decoy: open.

### 11.7 Voice warnings

The F-16's VMS phrases and their sources are in docs/real-betty.md. For the Sufa, the VMS lineage is inferred, and
both the language (English or Hebrew) and any Israeli phrases are open there.

### 11.8 How it looks

- **Airframe:** the F-16D two-seat canopy and fuselage. CFTs on the upper fuselage sides over the wing roots, their
  lower surface shaped to the fuselage[^sufa-lm-cft02]. The F100-PW-229 engine[^sufa-wiki-var], so the Pratt & Whitney
  nozzle (inferred).
- **Dorsal spine:** the large avionics compartment behind the canopy, with avionics and chaff / flare
  dispensers[^sufa-f16net-first]. Whether its outline differs from the Barak's spine in the Detailed F-16D: open,
  compare the photos below.
- **Antennas:** they differ from earlier IAF F-16s: IsraDecals sells a correction set "to replace a number of the
  antenna fairings" for F-16I kits[^sufa-isradecals]. Which and where: open (from the photos).
- **Colours:** three-tone desert camouflage, FS 30219 brown, FS 33531 sand and FS 34424 green, over FS 36375 light
  ghost grey underneath; radome FS 36270 medium grey (model paint guides, secondary)[^sufa-cyber].
- **Squadrons:**

  | squadron | name | base | F-16I from |
  |---|---|---|---|
  | 253 | Negev | Ramon[^sufa-sqns] | 2004 (aircraft 253 in a decal set)[^sufa-cyber]; exact date open |
  | 119 | The Bat | Ramon[^sufa-sqns] | 28 December 2004[^sufa-119] |
  | 107 | Knights of the Orange Tail (the orange tail marking gives the name) | Hatzerim[^sufa-sqns][^sufa-107] | 5 July 2006[^sufa-107] |
  | 201 | The One | Ramon[^sufa-sqns] | 2008 (decal-set aircraft)[^sufa-cyber]; date open |

- **Markings:** three-digit tail numbers; seen in sources: 107, 201, 253, 421, 459, 494, 848 and 868[^sufa-cyber],
  803[^sufa-c803]. Each squadron's tail badge: open (from the photos). The wing roundels as on the
  Barak (tools/f16d/rig.py places them from an F-16I photo).
- **Cockpits:** both NVG-compatible, with the colour displays of §11.4 and the DASH IV in each[^sufa-du].
- **Photo references** (to study shapes and colours only; nothing is copied into the repo; licences as stated on
  Wikimedia Commons):
  - side and rear views, aircraft 803: Zachi Evenor, CC BY 2.0[^sufa-c803];
  - 119 Squadron at Blue Flag 2015: U.S. Embassy Tel Aviv, CC BY 4.0[^sufa-cbf];
  - 107 Squadron, Hatzerim museum: Oren Rozen, CC BY-SA 4.0[^sufa-c107];
  - 201 Squadron, Ramat David 2017: Oren Rozen, CC BY-SA 4.0[^sufa-c201];
  - F-16I next to an F-15C and an F-16 at Red Flag 09-4 (size comparison): U.S. Air Force, public domain[^sufa-crf];
  - F-16I with a BLU-109 JDAM: IDF Spokesperson's Unit, CC BY-SA 3.0[^sufa-photo-jdam];
  - the whole category: Commons "F-16I (Israeli Air Force)", about 85 files[^sufa-ccat].

### 11.9 What the game's F-16 slot fixes, and what the Detailed F-16D gives

**The slot.** The Sufa replaces the F-16D everywhere the type code 100 is read (inferred):
- one model (`f16`), one cockpit dir and cockpit index 1 (the radar row, docs/radar.md §1), one FM section (`F-16`);
- the bdb object of type 100: its nine station flags and the mission loadouts stay valid, as the stations are the
  same;
- the Arming screen's F-16 art (`.trx` base and maximum weight, the nine boxes): the base and maximum weights
  change (§11.1); the front view gains the CFTs;
- per-type tables keyed on 100 or "F-16" need the switch: `REAL` (a second row, e.g. aircraft "F-16I" with base
  "F-16"), `RADAR_KM`, `GUN_ROUNDS`, the radar `TABLES`, `BETTY_TYPES`.
- Open: whether the AI's F-16s and the parked F-16s also become Sufas with the switch (the Detailed model switch
  changes them all).

**Reuse from tools/f16d/rig.py** (the Detailed F-16D, game/extra/models/f16/SOURCES.md):
- reused as is: the FlightGear F-16 source, the two-seat canopy, the second cockpit, the placement on the original's
  frame, the parts and hinges, the closed gear doors, the pylons on the original's stations, the wing roundels, the
  PBR maps, the KTX2 output;
- reused, perhaps changed: the IAF dorsal spine loft (after the photo comparison in §11.8);
- new:
  - the CFTs: FlightGear has a CFT mesh (`Models/Armament/External-stores/Fueltanks/CFT.ac`) and a CFT UV paint kit,
    under the same GPL as the rest of the source;
  - the P&W nozzle: FlightGear's `Models/nozzle.ac` (its `PW_nozzle` at x 4.617 m in `Models/F-16.xml`) in place of
    the GE nozzle;
  - the antennas that differ (§11.8);
  - a new livery: FlightGear has no IAF Sufa livery (its Block 60 "IAF" livery is fictional, monotone grey). Our own
    texture in the FS colours, with squadron badges and tail numbers;
  - the cockpits' colour displays (§11.4).
- FlightGear also ships a two-seat `Models/F-16D.ac`; whether it is better than the stretched single-seater: open.

### 11.10 Open questions

- The F-16I empty weight from a primary source, and whether the published figures include the CFTs.
- Top speed with CFTs, and the CFTs' drag above Mach 0.9.
- APG-68(V)9 ranges in NM per mode.
- The Sufa's IFF set, and how the Israeli software shows replies.
- DASH IV against DASH III, and the Sufa's HUD symbology (Israeli mission computer).
- The front and rear panel layouts: which of the six colour displays sit in which cockpit.
- SPS-3000: jammer or RWR.
- The language of the Sufa's voice warnings (docs/real-betty.md).
- The antenna changes, the spine outline and each squadron's tail badge, from the photos.
- Whether AI and parked F-16s become Sufas with the switch.

### 11.11 Build outline

1. A REAL row "F-16I" on the F-16 section with the §11.1 values; the validation test gets its reference row; the
   switch picks that row for type 100.
2. The radar row and `RADAR_KM` for the (V)9 (§11.2); AIFF as docs/real-hud.md "IFF" decides.
3. Existing weapons on the freed stations 4 / 6 and the AIM-120C numbers; then Python 5, Derby, JDAM and SPICE as
   new records (with "Modern aircraft and weapons").
4. The Sufa model: rig.py plus the CFTs, the P&W nozzle, antennas and the Sufa livery (§11.9).
5. The cockpit: the F-16 panel at first; colour MFDs with the Real MFDs.
6. The Extras row "F-16: Barak (1990s) / Sufa (F-16I)", docs/deviations.md §2, docs/status.md, and the pilot guide.

[^sufa-wiki-var]: Wikipedia, "General Dynamics F-16 Fighting Falcon variants", F-16I section:
    https://en.wikipedia.org/wiki/General_Dynamics_F-16_Fighting_Falcon_variants
[^sufa-at]: Airforce Technology, "F-16I Soufa Multirole Fighter, Israel": https://www.airforce-technology.com/projects/f-16i-soufa/
[^sufa-f16net-first]: f-16.net, "First F-16I Sufa ready for delivery to Israel": https://www.f-16.net/f-16-news-article912.html
[^sufa-isradecals]: Cybermodeler, IsraDecals F-16I sheet review (mentions the antenna correction set):
    https://cybermodeler.com/hobby/decals/isra/decal_isra_iaf88.shtml
[^sufa-cyber]: Cybermodeler, IsraDecals F-16I sheet (aircraft and squadrons) and the IAF F-16 colours (FS numbers):
    https://cybermodeler.com/hobby/decals/isra/decal_isra_iaf88.shtml
[^sufa-f100]: Wikipedia, "Pratt & Whitney F100", F100-PW-229 specifications (citing Pratt & Whitney):
    https://en.wikipedia.org/wiki/Pratt_%26_Whitney_F100
[^sufa-mf]: Military Factory, "Lockheed F-16I Sufa (Storm)": https://www.militaryfactory.com/aircraft/detail.php?aircraft_id=2191
[^sufa-warhistory]: WarHistory.org, "F-16I Sufa (Storm)": https://warhistory.org/article/f-16i-sufa-storm
[^sufa-lm-cft01]: Lockheed Martin, "Lockheed Martin Completes First Phase of Flight Testing of the F-16 Conformal Fuel
    Tanks", 6 September 2001:
    https://news.lockheedmartin.com/2001-09-06-Lockheed-Martin-Completes-First-Phase-of-Flight-Testing-of-the-F-16-Conformal-Fuel-Tanks
[^sufa-lm-cft02]: Lockheed Martin, "Lockheed Martin and U.S. Air Force Complete Flight Testing of F-16 Conformal Fuel
    Tanks", 27 November 2002:
    https://news.lockheedmartin.com/2002-11-27-Lockheed-Martin-and-U-S-Air-Force-Complete-Flight-Testing-of-F-16-Conformal-Fuel-Tanks
[^sufa-f16net-b50]: f-16.net, "F-16C/D Block 50/52": https://www.f-16.net/f-16_versions_article9.html
[^sufa-lm-radar]: Lockheed Martin, "Performance Flight Testing of Updated Radar Under Way for Lockheed Martin F-16",
    25 June 2002:
    https://news.lockheedmartin.com/2002-06-25-Performance-Flight-Testing-of-Updated-Radar-Under-Way-for-Lockheed-Martin-F-16-New-Technology-Expected-to-Significantly-Increase-Radar-Performance
[^sufa-f16net-apx113]: f-16.net news, Lockheed Martin selects the AN/APX-113 AIFF: https://www.f-16.net/f-16-news-article163.html
[^sufa-dash4]: Defense Update, "Helmet Mounted Display and Sight Systems" (DASH IV by VSI, integrated in the F-16I):
    https://defense-update.com/?p=24924
[^sufa-du]: Defense Update, "Israel Air Force F-16I Soufa" (the page refuses automatic fetching; the figures are from
    its search-engine excerpt): https://defense-update.com/?p=11422
[^sufa-python]: Wikipedia, "Python (missile)", Python-5: https://en.wikipedia.org/wiki/Python_(missile)
[^sufa-derby]: Wikipedia, "Derby (missile)": https://en.wikipedia.org/wiki/Derby_(missile)
[^sufa-dsca]: DefenceTalk, "Israel – Advanced Medium Range Air-to-Air (AMRAAM) Missiles" (DSCA notice, 28 August 2007):
    https://defencetalk.com/israel-–-advanced-medium-range-air-to-air-amraam-missiles-12821
[^sufa-aim120]: Wikipedia, "AIM-120 AMRAAM": https://en.wikipedia.org/wiki/AIM-120_AMRAAM
[^sufa-wt]: War Thunder wiki, "F-16I Sufa" (a game's reference page; weapons list only): https://wiki.warthunder.com/unit/f_16i_sufa
[^sufa-spice]: Wikipedia, "Spice (bomb)": https://en.wikipedia.org/wiki/Spice_(bomb)
[^sufa-rampage]: Airforce Technology, "Rampage" missile: https://www.airforce-technology.com/?p=255074
[^sufa-periscope]: Military Periscope, "Advanced Self-Protection System (ASPS)":
    https://www.militaryperiscope.com/weapons/electronics/electronic-warfare/advanced-self-protection/overview/
[^sufa-janes]: Janes, "Elbit Systems to equip Israel's F-16Is with self-protection suite", 27 January 2025:
    https://www.janes.com/defence-intelligence-insights/defence-news/defence/elbit-systems-to-equip-israels-f-16is-with-self-protection-suite
[^sufa-sqns]: Wikipedia, "List of Israeli Air Force aircraft squadrons":
    https://en.wikipedia.org/wiki/List_of_Israeli_Air_Force_aircraft_squadrons
[^sufa-119]: Wikipedia, "119 Squadron (Israel)": https://en.wikipedia.org/wiki/119_Squadron_(Israel)
[^sufa-107]: Wikipedia, "107 Squadron (Israel)": https://en.wikipedia.org/wiki/107_Squadron_(Israel)
[^sufa-c803]: https://commons.wikimedia.org/wiki/File:F-16I-Sufa-803-pic01.jpg and
    https://commons.wikimedia.org/wiki/File:F-16I-Sufa-803-pic02.jpg
[^sufa-cbf]: https://commons.wikimedia.org/wiki/File:F-16I_at_Blue_Flag_2015_-_pic01.jpg and
    https://commons.wikimedia.org/wiki/File:F-16I_at_Blue_Flag_2015_-_pic03.jpg
[^sufa-c107]: https://commons.wikimedia.org/wiki/File:Hatzerm_131022_Sufa_01.jpg
[^sufa-c201]: https://commons.wikimedia.org/wiki/File:RamatDavid_020517_Sufa_01.jpg
[^sufa-crf]: https://commons.wikimedia.org/wiki/File:F-15C_Eagle,_Israeli_F-16I_and_F-16_Fighting_Falcon_wait_at_the_end_of_the_runway_at_Nellis_AFB_during_Red_Flag_09-4.jpg
[^sufa-photo-jdam]: https://commons.wikimedia.org/wiki/File:F-16I_(IAF).jpg
[^sufa-ccat]: https://commons.wikimedia.org/wiki/Category:F-16I_(Israeli_Air_Force)
