# IAF 2026 flight model, step FM-0: own data for the existing model

**Terms:** FM = flight model; FM-0 = this step: our own data in the 1998 model's file formats, read by today's
`crates/iaf-flight`; 6-DoF = the own six-degrees-of-freedom model (item C2, later); AB = afterburner; CD0 = drag
coefficient at zero lift; CL = lift coefficient; K = lift-dependent drag factor (CD = CD0 + K·CL²); α = angle of
attack; lef = the F-16's leading-edge flap; REAL row = a jet's row of public figures in
`crates/iaf-flight/src/data_set.rs`; "inferred" = our own reasoning; "open" = a figure still to find; "model constant" = a
gain of the 1998 model's own channels, the loader's built-in value.

FM-0 is item C1 of [plan.md](plan.md). It gives the sim's four jets flight data made from NASA TP-1538[^tp1538] and
from the public figures already collected for the game's Real data set. The original game keeps its own data and
behaviour.

```sh
python3 -I -B tools/iaf-2026/fm0.py                    # writes assets/converted/own/resource/md/{bd.ibx,f16.dat,f15.dat}
IAF_INSTALL=$PWD/assets/converted/own cargo test --release -p iaf-flight --test validation -- --nocapture
IAF_JET=F-16I IAF_INSTALL=$PWD/assets/converted/own cargo test --release -p iaf-flight --test validation -- --nocapture
```

## 1. How the sim's jets get their data

`tools/iaf-2026/fm0.py` writes a `bd.ibx` with two sections and one envelope file each, in the formats of
[docs/flight-model.md](../../docs/flight-model.md) §1 and §3. `iaf_flight::load` reads them unchanged. The file sets
every key the loader reads, each with its source as a comment.

| sim jet | flies as (type, `data_set::TYPES`) | own section | on top: REAL row |
|---|---|---|---|
| F-16D Barak | `F-16` | `[F-16]` (`f16.dat`) | "F-16" (F-16D Block 30/40, F110-GE-100) with the Real data set |
| F-16I Sufa | `F-16I` (an F-16 with Extras "F-16 version" = Sufa) | `[F-16]` | "F-16I", always |
| F-35I Adir | `F-35I` | `[F-16]` | "F-35I", always: derived from the F-16 set and its published performance |
| F-15I Ra'am | `F-15I` (an F-15 with "F-15 version" = Ra'am) | `[F-15]` (`f15.dat`) | "F-15I", always |

`[F-16]` is the F-16D Block 40 (the Barak) with TP-1538's aerodynamics. `[F-15]` is the F-15I with the F-15E's
figures. A REAL row replaces the fields it sets (weights, thrust level, fuel flow, CD0, wave drag, roll, g limits,
stall floor, ceiling, nose-wheel steering; [docs/real-aircraft.md](../../docs/real-aircraft.md) §2) and keeps the
section's other keys.

The game reads `<assets>/install/resource/md`. Until item A1 gives the sim its own install path, a run on the own data
uses an assets folder whose `install/resource/md` is `converted/own/resource/md` (§7). Item A1's
`install_dir()` hook replaces that: the sim's install path holds `resource/md` from `converted/own`.

## 2. What TP-1538 gives

TP-1538 (Nguyen et al., NASA Langley, 1979) is a piloted simulator study of the F-16 at high α. Its tables come from
low-speed wind-tunnel tests of F-16 models. Used here:

| table | what FM-0 takes |
|---|---|
| I, mass and dimensions | span 30 ft (9.144 m), wing area 300 ft² (27.87 m²) |
| III, `CX(α, β, δh = 0°)` and `CZ(α, β, δh = 0°)` | lift and drag with the lef down (25°), at β = 0: CL at the α limit |
| III, `CX,lef(α, β)` and `CZ,lef(α, β)` | lift and drag with the lef up (0°), at β = 0: the cruise drag polar |
| III, `ΔCX,sb(α)` | the speed brake's drag (60°) |
| VI, thrust values | idle, military and maximum installed thrust, Mach 0.2–1.0, sea level to 50,000 ft |
| text and appendix A | the α limiter at 25°; control system A commands up to 308 deg/s of roll |
| appendix C | buffet from α ≈ 15° |

Appendix B weights the lef increment by `(1 − δlef / 25)`: so the base tables are the flap fully down, and the
`,lef` tables are the flap up. The values used (β = 0):

| α | CX lef up | CZ lef up | CX lef down | CZ lef down |
|---|---|---|---|---|
| −10° | | | −0.09820 | 0.69200 |
| 0° | −0.02020 | −0.10000 | −0.04890 | −0.02500 |
| 5° | −0.00330 | −0.42800 | −0.00660 | −0.36700 |
| 10° | 0.00990 | −0.77400 | 0.04900 | −0.75000 |
| 15° | | | 0.10720 | −1.11200 |
| 25° | | | 0.13000 | −1.65800 |

Table VI, maximum thrust (lbf; idle and military in `fm0.py`):

| Mach | SL | 10,000 ft | 20,000 ft | 30,000 ft | 40,000 ft | 50,000 ft |
|---|---|---|---|---|---|---|
| 0.2 | 21,420 | 15,700 | 11,225 | 7,323 | 4,435 | 2,600 |
| 0.4 | 22,700 | 16,860 | 12,250 | 8,154 | 5,000 | 2,835 |
| 0.6 | 24,240 | 18,910 | 13,760 | 9,285 | 5,700 | 3,215 |
| 0.8 | 26,070 | 21,075 | 15,975 | 11,115 | 6,860 | 3,950 |
| 1.0 | 28,886 | 23,319 | 18,300 | 13,484 | 8,642 | 5,057 |

## 3. How the numbers are made

**Lift and drag** (CL = CX·sin α − CZ·cos α, CD = −CX·cos α − CZ·sin α):
* CL at the α limit, lef down: 1.558 at 25°. At −10°: −0.664 (the negative limit: inferred, open). At 15° (buffet
  onset): 1.102, so `StartVibsG` = 1.558 / 1.102 = 1.41: the shake starts when less than 1.41 g is left.
* The model's drag is CD0 + K·CL² with K = 1 / (π·b²/S·0.85) = 0.125 from the span and area. CD0 = 0.0184: the mean
  of CD − K·CL² at α 0° and 5°, lef up. The fit at 10°: model 0.091, TP-1538 0.125 (the model's K is too low at
  high CL; the 6-DoF uses the tables).
* The F-15I: CL 1.205 from the F-15E's power-off stall, 155 KCAS at 59,665 lb, flaps up (TO 1F-15E-1[^to-f15e], the F-15I
  REAL row). CD0 0.042 is the F-15I REAL row's (a value fitted to top speed; an F-15 drag polar is open).

**Thrust.** The model's table has four corners: Mach 0 and 1.2, sea level and 20 km, linear in both. Each corner
holds two values, "0" and "1"; the throttle's k picks a point on the line between them: idle k = 0.05, military
k = 0.6, full AB k = 1 ([docs/flight-model.md](../../docs/flight-model.md) §4.1). TP-1538's maximum and military
tables are fitted to it in two steps:
1. the sea-level corners by least squares on the sea-level row (2 % worst, so take-off and climb follow TP-1538);
2. the 20 km corners by least squares of the relative error over 10,000–50,000 ft, each at least zero.

Without the bound the fit puts the 20 km corners below zero (a line through sea level and 50,000 ft crosses zero
before 20 km), and above ~55,000 ft full AB would give less than idle, then negative thrust. With the bound all four
20 km values are zero: thrust falls linearly to zero at 20 km (65,600 ft), and full AB ≥ military ≥ idle everywhere.
The price is too much thrust aloft:

| altitude | SL | 10,000 ft | 20,000 ft | 30,000 ft | 40,000 ft | 50,000 ft |
|---|---|---|---|---|---|---|
| max thrust, worst error | +2 % | +15 % | +30 % | +56 % | +85 % | +92 % |
| military thrust, worst error | +2 % | +19 % | +41 % | +73 % | +103 % | +118 % |

The worst errors are at Mach 0.2–0.4; at Mach 1.0 they are smaller (40,000 ft: max +28 %, military +23 %). The fitted shape is scaled
so the sea-level static corner is the engine's published rating (the F-16D: 29,000 lbf with AB, military 0.59 of it,
the F110-GE-100 in docs/real-aircraft.md §2; the F-15I: 2 × 29,160 / 2 × 17,800 lbf, the F100-PW-229). The F-15I
uses the F-16's (F100-class) shape (inferred).

The "0" value serves both idle (k = 0.05) and military (k = 0.6): at each corner it is the least-squares value of the
two settings (idle from TP-1538's idle table, scaled like maximum). At 20 km idle is held at zero with the others.
The remaining errors at sea level, F-16D (TP-1538 × the same scales):

| F-16D at sea level, lbf | Mach 0 | 0.2 | 0.4 | 0.6 | 0.8 | 1.0 |
|---|---|---|---|---|---|---|
| idle, model | +2,741 | +621 | −1,499 | −3,619 | −5,739 | −7,859 |
| idle, TP-1538 | | +960 | +91 | −1,543 | −4,084 | −5,445 |
| military, model | 17,943 | 18,654 | 19,364 | 20,074 | 20,784 | 21,494 |
| military, TP-1538 | 17,110 (the rating) | 16,605 | 16,513 | 16,552 | 16,225 | 15,295 |

Military is 5 % high standing still, 12 % at Mach 0.2, 21 % at Mach 0.6 and 41 % at Mach 1.0, and rises with Mach
where TP-1538's falls a little. Idle is close at take-off and approach speeds (about +100 lbf at 165 kt against
TP-1538's +700) and up to 2,400 lbf too low at Mach 0.6–1.0. The model's two values per corner cannot hold idle,
military and maximum all three; C2's engine model replaces the table.

**Tested and dropped (2026-11-02): military exact at every corner.** The "0" value set from military and maximum
alone ("0" = (military − 0.6 · max) / 0.4) makes military follow TP-1538 exactly, and leaves idle far too low:

| F-16D idle at sea level, lbf | Mach 0.2 | 0.6 | 1.0 | 165 kt |
|---|---|---|---|---|
| exact-military fit | −3,736 | −12,729 | −21,723 | about −4,900 |
| TP-1538 | +960 | −1,543 | −5,445 | about +700 |

Idle then brakes the jet in flight, which the MVP's start-up, take-off and landing missions feel (an idle approach
loses speed fast). The joint fit's transonic military error matters only above the MVP's speeds and waits for C2. So
the joint fit stays; this fit is not to be retried.

**Envelope** (minimum speed per g and altitude, `f16.dat` / `f15.dat`): Vmin = √(2·g·W / (ρ·S·CL)), with W = empty +
internal fuel (24,900 lb; the F-15I 59,665 lb) and ρ from the model's atmosphere ([docs/flight-model.md](../../docs/flight-model.md)
§2); a row every 5,000 ft. Each g's ceiling is the highest altitude where full-AB thrust equals the drag at that g,
found by bisection over altitude, searched over Mach ≤ 1.0 (TP-1538's thrust range). The g = 0 row holds the 0.1 g speed, because the format needs
rising speeds (inferred), and a ceiling of 65,000 ft (the model's 20 km top).

| g | −3 | −2 | −1 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| F-16 ceiling, ft | 33,500 | 41,900 | 56,400 | 65,000 | 60,800 | 53,400 | 46,300 | 40,100 | 34,700 | 29,800 | 25,300 | 21,100 | 17,200 |
| F-15I ceiling, ft | | 33,100 | 47,500 | 65,000 | 58,500 | 49,400 | 41,200 | 34,100 | 27,700 | 21,700 | 16,100 | 10,600 | |

The REAL rows then move the 1 g ceiling to the published service ceiling (50,000 / 60,000 ft) and set a stall floor.

## 4. Every key, with its source

Both sections; `fm0.py` writes the same list with the source beside each value.

| key | `[F-16]` | `[F-15]` | source |
|---|---|---|---|
| EmptyWeight | 19,100 lb | 37,000 lb | REAL rows: F-16D[^aeroweb]; F-15E with CFTs[^to-f15e] |
| MaxWeight | 42,300 lb | 81,000 lb | Block 50/52[^f16net-b50]; the Block 40 shares it (inferred). F-15E[^to-f15e] |
| FuelWeight | 5,800 lb | 22,665 lb | REAL rows: F-16D 870.4 US gal[^f16net-fuel]; F-15E 12,915 + 2 × 4,875 lb[^to-f15e] |
| FuelFlowAtMaxThrust | 16.5 lb/s | 31.42 lb/s | REAL rows (F-15I: TSFC 1.94, inferred) |
| WingArea | 300 ft² | 608 ft² | TP-1538 table I; Wikipedia F-15E[^wp-f15e] |
| WingSpan | 30 ft | 42.8 ft | TP-1538 table I; USAF F-15E fact sheet[^usaf-f15e] |
| MaxRollRate | 308 deg/s | 200 deg/s | TP-1538 control system A; F-15: inferred (the middle of the 180–220 in docs/real-aircraft.md; open) |
| RollAccel, StopAccel | 900 deg/s² | 670 deg/s² | REAL F-16 row (FLCS time constant ~0.3 s); F-15: inferred, the same 0.3 s |
| MaxG, MinG | +9 / −3 | +8.1 / −2.0 | +9: the USAF F-16 fact sheet[^usaf-f16]; −3: inferred (open). F-15E with CFTs, OWS off, fig. 5-7[^to-f15e] |
| PlaneDragIndex | 184 | 420 | TP-1538 (§3); REAL F-15I row (fitted) |
| SpeedBrakesDragIndex | 358 | 358 | TP-1538 ΔCX,sb at α 5°, 60°; the F-15 takes the F-16's (inferred) |
| LandingGearDragIndex | 200 | 200 | inferred: ΔCD 0.02 (open) |
| FlapsDragIndex | 150 | 150 | inferred: ΔCD 0.015 (open) |
| FlapsLiftCoef | 0.1 | 0.1 | inferred: +10 % lift (open) |
| LandingHookDragIndex | 10 | 10 | inferred: ΔCD 0.001 |
| WheelsBrakeDragIndex | 4,000 | 4,000 | inferred: braking friction 0.4 on a dry runway |
| MaxPosAlpha | 25° | 25° | TP-1538 α limiter; the F-15 takes it (inferred) |
| LimitAlphaVisual | 15° | 15° | model constant: the shown α's limit (below) |
| MaxNegAlpha | −10° | −10° | inferred (open) |
| StartVibsG | 1.41 | 1.41 | TP-1538 buffet onset (§3); the F-15 takes it (inferred) |
| OverGThresh | 8.5 | 7.6 | inferred: Betty's "over G" 0.5 g before the limit (the call needs g above it, and g stops at MaxG) |
| HasAfterBurner, UseFlightLimits | 1 | 1 | facts |
| Thrust…0 / Thrust…1 (8 keys) | §3 | §3 | TP-1538 table VI, scaled to the ratings |
| MaxBeta 10, BetaRate 10, G_Rate 5, G_RateForAoa 1, MaxAlphaRate 2.5, AlphaStopAccel 0.1, AlphaStartAccel 0.5, AlphaK 8, AlphaBeta 0.1, RudderK 5, RudderBeta 0, RudderStartAccel 0.5, RudderStopAccel 0.5, StartMoveStickCenterG 2, MapCenterStick 0 | | | model constants: the loader's built-in values (`crates/iaf-flight/src/params.rs`), written out. The real g onset rate and maximum sideslip are open |

**LimitAlphaVisual.** The α the model shows (nose attitude) is clamped to min(MaxPosAlpha, LimitAlphaVisual); lift
comes from the commanded g either way. In the Sufa's validation turn (420 kt, 10,000 ft, 6.3 g) α reads 14.8° with 15
and 24.5° with 25; TP-1538's lift curve puts that point at about 21° (CL ≈ 1.40, inferred). The loader's 15 is kept;
raising it is open (§8).

**Inferred figures, all in one list:** MinG −3 (F-16); the Block 40's 42,300 lb; the F-15's roll rate 200 deg/s and
roll acceleration 670 deg/s²; the F-15's speed brake, α limit, buffet ratio and thrust shape from the F-16; gear,
flap, flap-lift, hook and wheel-brake values; MaxNegAlpha −10°; OverGThresh 0.5 g below the limit; the g = 0 envelope row
and its 65,000 ft ceiling; the F-15I's negative CL (TP-1538's ratio); the F-35I's whole airframe from the F-16
section under its REAL row.

## 5. Validation results

`IAF_INSTALL=$PWD/assets/converted/own cargo test --release -p iaf-flight --test validation` (2026-11-02). The test
measures each jet against the public ranges in `crates/iaf-flight/tests/validation.rs`; "ok" is inside, "close"
within 10 %, "OFF" further. The F-16 rows' reference is the F-16C Block 30/40, so the D's smaller fuel tank reads
OFF there. Picture: the same tables as an HTML page (the C1 section of the "IAF 2026 Progress" page).

**F-16D Barak, the own `[F-16]` alone (Original data set)**

| test | FM-0 | public figure | verdict |
|---|---|---|---|
| empty weight | 19,100 lb | ~19,000 lb | ok |
| internal fuel | 5,800 lb | ~7,000 lb (the F-16C) | OFF |
| thrust SL static, military / full AB | 17,943 / 29,000 lbf | ~17,000 / 28,900 lbf (F110-GE-100) | close / ok |
| 1 g stall speed, SL | 125 kt | ~120–130 kt | ok |
| 1 g ceiling (envelope) | 60,800 ft | above 50,000 ft | OFF |
| max roll rate | 308 deg/s | ~240–308 deg/s | close |
| max level speed, SL / 40,000 ft | Mach 2.34 / Mach 3.41 | Mach 1.2 / Mach 2.0 | OFF / OFF |
| roll 0→90° | 0.52 s | ~0.5 s | ok |
| instantaneous turn, 420 kt, 10,000 ft | 24.6 deg/s at 9.0 g | ~20–26 deg/s at 9 g | ok |
| climb (Ps), SL, 350 kt, full AB | 49,408 ft/min | ~50,000 ft/min | ok |
| fuel flow military / full AB | 10,989 / 59,399 lb/h | 9,000–12,000 / 50,000–65,000 lb/h | ok / ok |

**F-16D Barak with its REAL row (the sim's Barak with real data)**

| test | FM-0 | public figure | verdict |
|---|---|---|---|
| thrust SL static, military / full AB | 17,941 / 28,996 lbf | ~17,000 / 28,900 lbf | close / ok |
| 1 g stall speed / ceiling | 125 kt / 50,000 ft | ~120–130 kt / above 50,000 ft | ok / ok |
| max roll rate, roll 0→90° | 280 deg/s, 0.55 s | ~240–308 deg/s, ~0.5 s | ok / ok |
| max level speed, SL / 40,000 ft | Mach 1.63 / Mach 2.36 | Mach 1.2 / Mach 2.0 | OFF / OFF |
| instantaneous turn | 24.3 deg/s at 8.0 g | ~20–26 deg/s | ok |
| climb (Ps), SL | 49,397 ft/min | ~50,000 ft/min | ok |
| fuel flow military / full AB | 10,989 / 59,399 lb/h | in range | ok / ok |

**F-16I Sufa**

| test | FM-0 | public figure | verdict |
|---|---|---|---|
| empty weight / internal fuel | 20,500 / 8,850 lb | 19,420–19,840 + 900 / 5,800 + 3,050 lb | ok / ok |
| thrust SL static, military / full AB | 18,332 / 29,160 lbf | 17,800 / 29,160 lbf (F100-PW-229) | close / ok |
| 1 g stall speed / ceiling | 128 kt / 50,000 ft | ~128 kt (inferred) / above 50,000 ft | ok / ok |
| max roll rate, roll 0→90° | 280 deg/s, 0.55 s | ~240–308 deg/s, ~0.5 s | ok / ok |
| max level speed, SL | Mach 1.17 | ~Mach 1.2 | ok |
| max level speed, 40,000 ft | Mach 1.69 | Mach 1.89 sustained .. 2.05 | OFF |
| instantaneous turn | 20.4 deg/s at 6.7 g | ~20.9 deg/s at 7.8 g (uncertain) | ok |
| climb (Ps), SL | 35,531 ft/min | (no public figure) | - |
| fuel flow military / full AB | 13,500 / 56,599 lb/h | ~13,500 / ~56,600 lb/h (inferred) | ok / ok |

**F-35I Adir**

| test | FM-0 | public figure | verdict |
|---|---|---|---|
| empty weight / internal fuel | 29,300 / 18,250 lb | 29,300 / 18,250 lb | ok / ok |
| thrust SL static, military / full AB | 28,703 / 43,000 lbf | 25,000–28,000 / 40,000–43,000 lbf | close / ok |
| 1 g stall speed / ceiling | 125 kt / 50,000 ft | ~120–125 kt / 50,000 ft | ok / ok |
| max level speed, SL | Mach 1.07 (705 kt) | ~700 kt (Mach 1.06) | ok |
| max level speed, 40,000 ft | Mach 1.35 | Mach 1.6 | OFF |
| fuel flow military / full AB | 21,996 / 86,001 lb/h | ~20,000–25,000 / ~86,000 lb/h | ok / ok |

**F-15I Ra'am**

| test | FM-0 | public figure | verdict |
|---|---|---|---|
| empty weight / internal fuel | 37,000 / 22,665 lb | 37,000 / 22,267–22,665 lb | ok / ok |
| thrust SL static, military / full AB | 36,839 / 58,320 lbf | 2 × 17,800 / 2 × 29,160 lbf | close / ok |
| 1 g stall speed / ceiling | 155 kt / 60,000 ft | 155 KCAS[^to-f15e] / 60,000 ft | ok / ok |
| max level speed, 40,000 ft | Mach 1.61 | ~Mach 2.0 (secondary) | OFF |
| roll 0→90° | 0.72 s | (no public figure) | - |
| fuel flow military / full AB | 27,003 / 113,098 lb/h | ~27,000 / ~113,100 lb/h (inferred) | ok / ok |

Every jet also reads OFF on "neutral stick, 60 s at 10,000 ft" without better physics: the 1998 model's 1 g hold
climbs with neutral stick, on the original data too (+1,400 to +4,300 ft). With better physics every jet holds
altitude ("ok").

**Why the OFF rows are OFF** (the data is as derived; none of it was fitted to the test):
* **Top speed at 40,000 ft, too low (Sufa, F-35I, F-15I).** The REAL rows' fitted fields belong to the 1998 table's
  shape: `alt_thrust` (F-35I × 1.4, F-15I × 2.4) multiplies the 20 km corners, which are zero on the own table, so it
  leaves them at zero; `cd0` and `wave_drag` are fits as well. The Sufa's `cd0` 0.0555 is the 1998 PlaneDragIndex + 1 %
  (docs/f16i.md §1), three times TP-1538's 0.0184. TP-1538's thrust ends at Mach 1.0 and the model's table stays
  flat above Mach 1.2, so supersonic thrust aloft stays at its Mach 1.2 value.
* **Top speed too high (Barak).** TP-1538's low-speed CD0 with the F-16 row's wave drag 0.02 (fitted on the 1998
  CD0 0.055) leaves too little drag above Mach 1, and the bounded table gives too much thrust at 40,000 ft: Mach 1.63
  at sea level, Mach 2.36 at 40,000 ft. The own section alone holds CD0 only (the transonic drag rise is a REAL-row
  field): Mach 2.34 / 3.41.
* **1 g ceiling 60,800 ft (Barak, own section alone).** The thrust aloft is too high (§3); the REAL row sets 50,000 ft.
* **Internal fuel (Barak).** The reference row is the F-16C; the D's 5,800 lb is right.
* **Military thrust "close" (every jet).** One "0" value serves idle and military (§3).

## 6. The one change to shared code

`data_set.rs`: the F-16 REAL row's `Thrust::Scale(1.5)` became `Thrust::StaticAb(28_995.6)`, the original's
19,330.4 lbf × 1.5 written as an absolute value. On the 1998 data (v1.0 and v1.1 hold the same 19,330.4) the scale is
1.5 bit for bit: the validation report of the original data is identical before and after. On the own `[F-16]` the
relative scale would have given 43,500 lbf. On the own data (an install path ending in `converted/own`) the
validation harness skips the types the own `bd.ibx` lacks; any other install must load every type.

## 7. A real flight on the own data

The game reads the own data through an environment switch: `IAF_ASSETS_DIR` points it at an assets folder whose
`install/resource/md` is a link to `converted/own/resource/md` and whose other entries link to the real `assets/`.
One flight (2026-11-02, on the data as shipped, real render, `IAF_DEFAULT_SETTINGS=1`, so better physics off,
`--path iaf-reborn`): the Sufa (Extras "F-16 version" = Sufa) in mission 311 at Ramat David, full afterburner from
its start point, the stick pulled at 150 kt, the gear up 3 s after lift-off, level at 4,000 ft to the top speed, then
military. A scratch script flew it; the numbers are from the blackbox (`tools/flight_timeline.py`).

| item | flight | public figure / validation |
|---|---|---|
| mass at start | 20,509 kg (45,210 lb with the mission's load), fuel 8,850 lb | the F-16I row |
| lift-off | 169 kt, 17.2 s after brake release, 656 m (2,150 ft) of roll | F-16I figure open; 1.3 × the 128 kt stall floor = 166 kt (inferred) |
| climb-out | up to 8,000 ft/min at 170–250 kt, 30° pitch | (no public figure at this speed) |
| top speed, full AB, 4,000 ft | 666 kt, Mach 1.02, steady after ~170 s | ~Mach 1.2; the validation (better physics) 777 kt, Mach 1.17 at sea level |
| level speed, military, 4,000 ft | 476 kt, Mach 0.73 | (no public figure) |

The flight's top speed is lower than the validation's. The validation flies with better physics (its flight-path
hold), the flight without, at 4,000 ft and with the mission's load (15,860 lb above the clean jet); which of these
makes the difference is open. The mission's training setup kept the fuel constant, so the fuel burn is open. The
script's 450 kt climb waited for the jet to slow to 450 kt at military, which it does not (476 kt). The flight on the
dropped exact-military fit (§3) climbed 17,900 ft/min at 450 kt from 4,000 ft.

## 8. Open

* The F-35I's and F-15I's REAL rows hold fits for the 1998 thrust shape (`alt_thrust`, `cd0`, `wave_drag`) and the
  Sufa's `cd0` is the 1998 value + 1 %; on the own data the top speeds at altitude miss (§5). The rows also serve
  the original game, so FM-0 leaves them. The 6-DoF (C2) replaces the 2 × 2 thrust table and the CD0 + K·CL²
  drag with TP-1538's tables and an engine model, which removes these fits from the sim.
* The thrust table: zero at 20 km and too much thrust aloft; military high in the transonic range (§3). C2.
* The Barak's REAL row on the own data: Mach 1.63 at sea level and Mach 2.36 at 40,000 ft (public 1.2 / 2.0). Its
  wave drag 0.02 was fitted on the 1998 CD0 0.055. The row is not refitted: it also serves the original game's Real
  flight data, where it is in range. Open for C2.
* LimitAlphaVisual stays 15 (the loader's): the shown α stops at 15° where TP-1538's lift curve puts a 6.3 g, 420 kt
  turn at about 21° (inferred, §4).
* The 1998 handling gains (MaxBeta, BetaRate, G_Rate, G_RateForAoa, the α and rudder channel gains,
  StartMoveStickCenterG, MapCenterStick) are the loader's built-in values: open for the user to decide.
* Figures still to find: the F-16's negative g and α limits, the gear / flap / hook / brake drag, the g onset rate, the
  maximum sideslip, the F-15's roll rate, speed brake and α limit.
* `[Autopilot]` (the AI's and the player's autopilot gains): the autopilot runs on its built-in values
  ([docs/autopilot.md](../../docs/autopilot.md)).
* The AI types (MiGs, transports): the own `bd.ibx` holds the four jets only, so another AI aircraft fails to load on
  the own data (the threat set is item D1 / D2).

[^tp1538]: L. T. Nguyen, M. E. Ogburn, W. P. Gilbert, K. S. Kibler, P. W. Brown, P. L. Deal, "Simulator Study of
    Stall/Post-Stall Characteristics of a Fighter Airplane With Relaxed Longitudinal Static Stability", NASA
    TP-1538, December 1979 (public domain, a work of the U.S. Government): https://ntrs.nasa.gov/citations/19800005879
[^wp-f15e]: Wikipedia, "McDonnell Douglas F-15E Strike Eagle", specifications (wing area 608 ft²):
    https://en.wikipedia.org/wiki/McDonnell_Douglas_F-15E_Strike_Eagle
[^usaf-f15e]: USAF, "F-15E Strike Eagle" fact sheet (wingspan 42.8 ft):
    https://www.af.mil/About-Us/Fact-Sheets/Display/Article/104499/f-15e-strike-eagle/
[^aeroweb]: aero-web.org, F-16D empty weight 19,100 lb, as cited in docs/real-aircraft.md §8 (that doc records no
    address, and the site's old F-16D page answers 404 on 2026-11-02): https://aero-web.org
[^f16net-fuel]: f-16.net forum, F-16D fuel capacity: https://www.f-16.net/forum/viewtopic.php?p=10079
[^f16net-b50]: f-16.net, "F-16C/D Block 50/52": https://www.f-16.net/f-16_versions_article9.html
[^usaf-f16]: USAF, "F-16 Fighting Falcon" fact sheet:
    https://www.af.mil/About-Us/Fact-Sheets/Display/Article/104505/f-16-fighting-falcon/
[^to-f15e]: USAF, TO 1F-15E-1, *Flight Manual, USAF Series F-15E Aircraft*, 15 August 1990, change 2 (weights §I,
    limits fig. 5-7, CFT fuel p. A9-4, stall speeds figs. A1-4 to A1-7; as read for docs/f15i.md §1):
    https://archive.org/details/f-15-e
