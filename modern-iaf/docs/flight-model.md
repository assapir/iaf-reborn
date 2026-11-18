# Modern IAF flight model, step FM-0: own data for the existing model

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
cargo run --release -p iaf-setup --bin iaf-sim -- fm    # writes assets/converted/own/resource/md/{bd.ibx,f16.dat,f15.dat}
IAF_INSTALL=$PWD/assets/converted/own cargo test --release -p iaf-flight --test validation -- --nocapture
IAF_JET=F-16I IAF_INSTALL=$PWD/assets/converted/own cargo test --release -p iaf-flight --test validation -- --nocapture
```

## 1. How the sim's jets get their data

`iaf-sim fm` (`crates/iaf-tools/src/sim_fm0.rs`; the setup step `sim-fm`, and part of `iaf-sim all`) writes a
`bd.ibx` with two sections and one envelope file each, in the formats of
[docs/flight-model.md](../../docs/flight-model.md) §1 and §3. `iaf_flight::load` reads them unchanged. The file sets
every key the loader reads, each with its source as a comment.

The Rust module is the port of the first version, the Python script `fm0.py` (2026-11-02, removed), and
keeps its arithmetic: its sums are Python's compensated `sum()`, its rounding ties to even. Until commit 1c610001 the
output equalled the script's last output (9 November 2026, Python 3.14.9) byte for byte. Since then the files'
comments name `iaf-sim fm`. The test `sim_fm0::tests::output_matches_fixture` holds the SHA-256 of the output.

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

The game reads `<own_dir()>/resource/md`: `converted/own/resource/md` in the sim (item A1). The player's jet picks its
type by its bdb type code on the own `bd.ibx` (`Settings.fm_section`, `iaf_flight::fm_name_in`: 100 the F-16, 110 the
F-15, 1000 the F-35I), then the F-16 / F-15 switches the Sufa or the Ra'am, as in the table above. A code whose
section the own `bd.ibx` lacks (the 1998 jets) flies as the F-16, with a warning.

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

Table VI, maximum thrust (lbf; idle and military in `sim_fm0.rs`):

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

Both sections; `sim_fm0.rs` writes the same list with the source beside each value.

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
| max roll rate | 308 deg/s | 180–240 deg/s (docs/real-aircraft.md §8.2) | OFF |
| max level speed, SL / 40,000 ft | Mach 2.34 / Mach 3.41 | Mach 1.2 / Mach 2.0 | OFF / OFF |
| roll 0→90° | 0.52 s | ~0.55 s (inferred) | ok |
| instantaneous turn, 420 kt, 10,000 ft | 24.6 deg/s at 9.0 g | ~20–26 deg/s at 9 g | ok |
| climb (Ps), SL, 350 kt, full AB | 49,408 ft/min | ~50,000 ft/min | ok |
| fuel flow military / full AB | 10,989 / 59,399 lb/h | 9,000–12,000 / 50,000–65,000 lb/h | ok / ok |

**F-16D Barak with its REAL row (the sim's Barak with real data)**

| test | FM-0 | public figure | verdict |
|---|---|---|---|
| thrust SL static, military / full AB | 17,941 / 28,996 lbf | ~17,000 / 28,900 lbf | close / ok |
| 1 g stall speed / ceiling | 125 kt / 50,000 ft | ~120–130 kt / above 50,000 ft | ok / ok |
| max roll rate, roll 0→90° | 240 deg/s, 0.63 s (280, 0.55 s before 2026-11-14) | 180–240 deg/s, ~0.55 s (§8.2 of docs/real-aircraft.md) | close / ok |
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
| max roll rate, roll 0→90° | 240 deg/s, 0.63 s (280, 0.55 s before 2026-11-14) | 180–240 deg/s, ~0.55 s (§8.2 of docs/real-aircraft.md) | close / ok |
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
| 1 g stall speed / ceiling | 134 kt / 50,000 ft | 121–147 kt (134 kt inferred, §9.19) / 50,000 ft | ok / ok |
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

## 9. C2: the own 6-DoF

Stage (a) of item C2 is the core of the sim's own six-degrees-of-freedom model: TP-1538's aerodynamic tables, the
report's coefficient build-up and a quaternion rigid body, with trim tests (§9.1–9.5). Stage (b) adds the engines,
the gear and the four jets' data (§9.7–9.10). Stage (c) adds the control system and puts it behind `IafFlight`: the
sim's jets fly it (§9.6, §9.11–9.14). The original game's model and its tests are
unchanged.

```sh
cargo test -p iaf-flight --lib sixdof                     # the rigid body and the interpolation
cargo test -p iaf-flight --test sixdof -- --nocapture     # the trim points, printed against their sources
```

| file | what it holds |
|---|---|
| `crates/iaf-flight/src/sixdof/tables/data.rs` | TP-1538 Table III, every table, in units of 10⁻⁵, laid out like the printed page |
| `crates/iaf-flight/src/sixdof/tables.rs` | the breakpoints and the interpolation |
| `crates/iaf-flight/src/sixdof/aero.rs` | appendix B's total coefficients; appendix A's flap schedule |
| `crates/iaf-flight/src/sixdof/body.rs` | the airframe (Table I), the quaternion rigid body, the RK4 integrator |
| `crates/iaf-flight/tests/sixdof.rs` | the trim tests |

### 9.1 The tables and how they were transcribed

TP-1538's Table III[^tp1538] fills printed pages 45–91 (PDF pages 51–97 of the NTRS scan). Every table in it is in
`data.rs`, each with a comment naming the table and its printed page:

| coefficient | tables (printed page) |
|---|---|
| CX | CX(α, β, δh) at δh −25, −10, 0, 10, 25° (45–49); CX,lef(α, β) (50); ΔCX,sb(α), CXq(α), ΔCXq,lef(α) (51) |
| CZ | CZ(α, β, δh) at the same five δh (52–56); CZ,lef (57); ΔCZ,sb, CZq, ΔCZq,lef (58) |
| Cm | Cm(α, β, δh) at the five δh (59–63); Cm,lef (64); ΔCm,sb(α), ΔCm(α), ηδh(δh) (65); Cmq, ΔCmq,lef (66); ΔCm,ds(α, δh) (67) |
| CY | CY(α, β) (68); CY,lef (69); CY,δa=20° (70); CY,δa=20°,lef (71); CY,δr=30° (72); CYr, ΔCYr,lef, CYp, ΔCYp,lef (73) |
| Cn | Cn(α, β, δh) at δh −25, 0, 25° (74–76); Cn,lef (77); Cn,δa=20° (78); Cn,δa=20°,lef (79); Cn,δr=30° (80); Cnr, ΔCnβ, ΔCnδa (81); ΔCnr,lef, Cnp, ΔCnp,lef (82) |
| Cl | Cl(α, β, δh) at δh −25, 0, 25° (83–85); Cl,lef (86); Cl,δa=20° (87); Cl,δa=20°,lef (88); Cl,δr=30° (89); Clr, ΔClβ, ΔClr,lef (90); Clp, ΔClp,lef (91) |

Breakpoints: α −20…90° (−20…45° for the `,lef` tables), β −30…30°, δh as listed. About 13,000 values.

**How.** The scan is a line printer's output, legible at 200 dpi, but its text layer (OCR) is unusable. The values
were taken from a typed copy of the same tables, the University of Minnesota F-16 package[^umn], and every value was
then compared with the scan, digit by digit, by reading enlarged crops of each page. Three changed digits were planted
in the candidates of each page as a control: every one of them was found. Where the scan and the typed copy differ,
the scan wins:
* **The lateral tables (CY, Cn, Cl and their flap, aileron and rudder versions).** The typed copy adds a constant per
  α to every value of a row: the base table's value at β = 0 (an asymmetry term). The report prints these tables with
  0 at β = 0 (CY, Cn, Cl and their `,lef` tables), and its aileron and rudder tables without the shift. The model
  takes the printed values; the asymmetry, which the report models separately in some of its deep-stall runs
  (figures 51 and 52), is left out.
* **Damping derivatives at high α.** The typed copy's Cmq (α ≥ 25°), Cnr (α ≥ 15°), Cnp (α ≥ 10°) and Clp
  (α ≥ 30°) are other data; the report's printed values are used.
* **One digit** in the big tables: CX(α −15°, β +8°, δh −25°) is −.18460 on the page (the typed copy −.18480).
* **Five tables are not in the typed copy** (ΔCX,sb, ΔCZ,sb, ΔCm,sb, ΔCm,ds, ΔCnδa): transcribed from the scan,
  read twice independently.

The checks: pages 45–64 and 68–80 (CX, CZ, Cm, CY, Cn) by reading against the candidate, Cn and CY also by a full second
transcription, which matched the shift-corrected copy in every cell; the Cl pages (83–89) by one reading, which found 19
of its 21 planted digits (the two it missed are right in the data: checked on the scan). One cell is crossed by a
printed rule: Cl,δa=20°,lef(α 30°, β 0°) reads −.02220 (−.02290 not ruled out). Otherwise no page was illegible. Values
that look odd but are printed so, kept as printed: Cm,lef(α 25°, β −6°) = −.16070 (its neighbours −.06480 and −.05580:
probably a typo in the report), CX(α 80°, β +10°, δh 0°) = .07090, CZ(α −10°, β −8°, δh −25°) = .88880, Clr(α 35°) =
.10000 between .68000 and .44700.

**Interpolation.** The report gives the tables, not how to read between their points. The model interpolates
linearly in α, β and δh and holds the end values outside the tables (inferred).

### 9.2 The build-up (appendix B)

`aero::coefficients` sums the tables as appendix B's equations (printed pp. 37–40) do: each coefficient is its
(α, β, δh) table, plus the flap increment weighted by (1 − δlef/25), the speed brake by δsb/60, the aileron
increments by δa/20 and the rudder's by δr/30, the rate terms with c̄/2V (pitch) and b/2V (roll, yaw), the c.g.
shift from the data's 0.35 c̄ (CZ into Cm, CY into Cn) and ΔCm(α), ΔCm,ds(α, δh), ΔCnβ(α)·β, ΔClβ(α)·β. Choices the
report leaves open (inferred): the `,lef` tables end at α 45°, so above 45° their increments hold the 45° values
(the flap is fully down there and the increments' weight is 0); ΔCnβ and ΔClβ multiply β in degrees (the tables'
unit). Table III's ΔCnδa(α) is in `data.rs`, but appendix B's equations do not use it, so the model leaves it out.
The speed brake's ΔCX,sb and ΔCZ,sb are in `data.rs` but not flown: a drag along the flow replaces them (§9.17).
The flap schedule of appendix A (printed p. 34) is `lef_schedule`: δlef = 1.38 α − 9.05 q̄/ps + 1.45, limited to
0–25°, without its lag filters (they are stage (c)'s flight control system).

TP-1538's data are low-speed wind-tunnel data: no Mach effects. Compressibility is open for stage (c).

### 9.3 The rigid body

`body.rs` integrates appendix B's equations of motion in body axes (x forward, y right, z down) over a flat earth in
north-east-down axes:
* forces: m (u̇, v̇, ẇ) = F + m·g_body − m·ω × v;
* moments: J ω̇ = M − ω × (J ω + H), with J holding the xz product of inertia and H the engine's angular momentum
  along the body x axis (the report's 160 slug-ft²/s). Its gyroscopic terms are appendix B's − H r / Iy in pitch and
  + H q / Iz in the yaw equation; that equation also holds Ixz ṗ, so solved for the rates the yaw term is
  ṙ = Ix H q / Γ and the roll term ṗ = Ixz H q / Γ, with Γ = Ix Iz − Ixz²;
* attitude: a unit quaternion, q̇ = ½ q ⊗ (0, ω), renormalised after each step. No attitude is singular; only the
  Euler angles read out of it are, at θ = ±90°. The report itself "used quaternions to allow continuity of attitude
  motions".

The mass data are TP-1538 Table I's (printed p. 43): 20,500 lb, Ix 9,496, Iy 55,814, Iz 63,100, Ixz 982 slug-ft²,
span 30 ft, area 300 ft², chord 11.32 ft, reference c.g. 0.35 c̄, converted to SI.

**Integrator.** The game steps its flight model once per rendered frame with the frame's time (variable, about 1/60 s;
`shared/terrain/terrain_view.gd` calls `flight.step(delta)`). `Body::step` cuts a frame into equal fourth-order
Runge-Kutta steps of at most 1/120 s, so the result does not depend on a carried remainder. A frame longer than 0.25 s
(a hitch) is cut to 0.25 s, as `IafFlight::step` does for the original model; a frame time that is not a positive number
changes nothing. 1/120 s is inferred: well inside RK4's stability for the fastest modes (the roll mode, about 0.15 s at
high dynamic pressure, and the report's 0.0495 s surface actuators that stage (c) adds).

Its tests (`cargo test -p iaf-flight --lib sixdof`): free fall (½ g t²), a steady turn back to its start after one
circle, a loop through the vertical back to the start attitude, a torque-free tumble that keeps its energy and
angular momentum to 10⁻⁷ over 60 s, the gyroscopic moment against appendix B's formula, and a frame split equal to
its steps one by one.

### 9.4 Trim results

TP-1538 tabulates no trim points. It states its trims in the text (printed p. 19, from figure 10 at c.g. 0.35 c̄),
and the Stevens & Lewis F-16 model[^stevens-lewis], built on a reduced set of the same NASA data (no leading-edge
flap), publishes a wings-level trim. The tolerances were set before the first run.

| trim point | the model | source | tolerance |
|---|---|---|---|
| static margin, α 0–10°, configuration fixed (flap up) | −3.9 % c̄ | about −4 % (TP-1538 p. 19) | −2 … −6 % |
| trim α at δh = −25° (full nose up), flap down | 65.8° | 66° (TP-1538 p. 19) | ±3° |
| stable deep-stall trim α at δh = +25° (full nose down) | 58.6°, dCm/dα −0.0084/deg (stable) | 60°, "weak but stable" (TP-1538 p. 19) | ±3°, slope < 0 |
| α of maximum CL, δh = 0, flap down | 36° (CL 1.894) | near 35° (TP-1538 p. 19) | ±5° |
| wings-level trim, 502 ft/s, sea level, c.g. 0.35 c̄: α | 2.161° | 2.115° (Stevens & Lewis) | ±0.5° |
| the same: stabilator | −0.598° | −0.759° (Stevens & Lewis's elevator) | ±1.5° |
| the same: thrust | 2,196 lbf | (throttle 0.1385 in their engine model) | — |
| the trim flown 2 s open loop | α within 0.0001°, height within 1 mm | (equilibrium) | 0.01°, 5 cm |

The 502 ft/s trim flies the flap on appendix A's schedule (3.1° there). The trim is checked on the full rigid body:
all accelerations zero.

**Tested and corrected (2026-11-03): the static margin's measurement.** The first run measured −dCm/dCL with the
flap moving on its schedule (1° to 15° over α 0–10°): −0.4 %. That mixes the flap's own pitching moment into the
slope; static stability holds the configuration fixed. With the flap held at 0°, 10° or 25° the margin is −3.9 %,
−3.3 % and −2.4 % (α 0–10°), −3.8 % at α −5…5° for all three: the test holds the flap up.

### 9.5 Inferred figures, all in one list

Linear interpolation and end-value hold outside the tables; the `,lef` increments held at α 45° above 45°; ΔCnβ and
ΔClβ per degree of β; ΔCnδa left out (appendix B does not use it); the asymmetry term of the typed copy left out (the
report prints the tables without it); the flap schedule without its lag filters (stage (c) adds them); the integrator
step of 1/120 s; the inertia, chord and weights in SI from the report's U.S. values (its own SI values are these,
rounded).

### 9.6 Stage (c), and what is open

Stage (c) is done (§9.11–9.15): the control system, the switch, the state in the game's frame, fuel burn, Mach effects
(inferred) with the wave drag fit to the published top speeds, the validation rows on the 6-DoF, the frame-cost
budget, a real flight. Open:
* **A sourced drag rise**: the wave drag is a fit to public performance, not a sourced table (§9.15); a public F-16
  drag-rise and high-Mach thrust table replaces it when one turns up.
* **The flaps' aerodynamics**: TP-1538 has no trailing-edge flap data; the flaps' increments are inferred (§9.16).
* **The player's autopilot on the 6-DoF** (2026-11-14, test `player_autopilot_flies_the_sims_three_jets`, the own
  data and the own airbases): on the Barak, the Sufa and the Adir, level holds the height within 1.3 m for 60 s, NAV
  passes a waypoint 90° off the nose 1,000 m higher within 1.1–1.3 km (its pass radius is 1,852 m) at 8–10 m of its
  height, and NAV to a landing waypoint lands on Ramat David's centreline and stops, sinking 2.0–2.6 m/s at the
  touchdown (2026-11-16: Barak 2.6, Sufa 2.5, Adir 2.0; the test asserts under 3 m/s).
  **The real final** (2026-11-16, `autopilot::REAL_FINAL`): on the 6-DoF (its `ApView::final_speed` set with the gear
  down) the autopilot flies a 3° glide path (inferred: the usual ILS glide slope[^aim-gs]; the F-16 manual gives no
  angle) at the speed of 13° α, the manual's on-speed α ("arrive on final at 11 or 13 degrees AOA", T.O. GR1F-16CJ-1
  p. 2-23, figure 2-3[^to-f16cj]; the F-35A's 13° in the Eglin accident report[^asf20]), computed from the jet's own
  aerodynamics at its weight, height, flaps and speed brake (`sixdof::flight::approach_speed`, the function the
  approach-speed test checks against figure 2-3). The speed law's error is summed (0.2 /s), the path held by a
  gain the same both sides of it (0.1° of flight path per m, damping 1.0 per deg/s) and the flare starts at
  6 s × (sink − 1.5 m/s), about 15 m (the original's 2 s). The Barak's final: 146 kt, α 12.8°, 3.9 m/s of sink. The
  original model keeps the original's 6° final.
  Before (2026-11-15): the original's 6° final at 185–195 kt, 8–12 m/s of sink, touched at 9.6 / 4.3 / 6.8 m/s: at
  that speed with the gear down the 6-DoF's g takes about a second to follow the flare's command. Tested and dropped
  then (2026-11-15/16): the flare acting on the height 0.3–1.0 s ahead (7.7–8.7 m/s, 1.0 s ballooned and crashed), the
  flare started at 3.5 s of sink (4.6 m/s), a constant-deceleration flare (1.8–2.4 m/s next to crashes). Swept on the
  real final (2026-11-16, Barak / Sufa / Adir, the diag flight of the test): the flare's time 2–5 s gave 2.7–4.1 m/s,
  6 s 1.9–2.2, 7–8 s ballooned the Adir 300 m short; the original's path gains (0.3 above / 0.03 below, damping 0.5)
  cycled ±2 m/s about the path and touched at 3.4–9 m/s; damping 0.5 with a symmetric gain 3.3–6.8 m/s.
  That touchdown passes because the game keeps
  the original's landing limits while the autopilot lands, on both models (`set_ap_landing`). "No stalls" and "No
  spins" reach only reborn's model: the 6-DoF has no scripted stall or spin to block, and the sim fixes both off.
* **Not modelled, one plain log line per run when the game asks** (`IafFlight`, no warning): the drag chute. No F-16
  or F-35 has a drag chute: their definitions say `"drag_chute": false`, so the flight never asks for one
  (`terrain_view.gd`). Also not
  modelled: Better physics' flight-model options other than ground effect, the gusts, the stores' moment and the roll
  trim (§9.12): they change the original model, which the sim's player never flies (the sim sets `wind` and the
  original's bug fixes on, [weapons.md](weapons.md) §4);
  Stevens & Lewis's turn trims (the book's tables were not available).

### 9.7 The engines (stage (b))

`sixdof/engine.rs` is TP-1538's own powerplant model, scaled per engine:
* **Thrust.** Table VI (printed p. 93): installed idle, military and maximum thrust of the simulation's F-16 engine (the
  F100-PW-200), Mach 0.2–1.0, sea level to 50,000 ft, interpolated bilinearly. Below Mach 0.2 the line through Mach 0.2
  and 0.4 is carried to Mach 0; above Mach 1.0 the Mach 1.0 value holds; above 50,000 ft the 50,000 ft value falls with
  the density (all three inferred: the table ends there). The report has no Mach 0 row (checked on the scan, printed p.
  93). Stevens & Lewis's version of the table has one, as the code review quoted it (12,680 / 20,000 / 1,060 lbf
  military / maximum / idle at sea level), from another source (the book not read); ours carries the report's Mach 0.2
  and 0.4 rows down to Mach 0 (12,750 / 20,140 / 1,210 lbf). Each engine scales the table so its sea-level static values
  (Mach 0) are its public ratings: idle and military by the military ratio, maximum by the maximum ratio (inferred, as
  FM-0's fit).
* **Spool.** Figure 66 (printed pp. 218–220): the throttle's travel gives a commanded power (military at 77 % of
  the travel, 50 % power; maximum 100 %); the power follows through a first-order lag whose rate is 1/s for steps up
  to 25 % and falls to 0.1/s for steps of 50 % or more, and 5/s inside the afterburner range; for a command above military from below
  it the target is 60 % until military is reached. Military itself (the game's lever 0.74, a joystick's afterburner
  detent) is dry: its command is exactly 50 % and the power settles on it from below (fixed 2026-11-13: the figure's
  64.94·0.77 = 50.004 had put military in the afterburner range, the burner lit with the lever in its detent). Thrust is idle → military over 0–50 % power, military → maximum over
  50–100 %. Each engine stretches the lag so its idle → military time (to 95 % of military thrust, the way the public
  figures are taken, docs/flight-model.md §10.2) is its public one; figure 66's own is 3.88 s (to maximum 4.78 s).
* **Angular momentum.** Appendix B's 160 slug-ft²/s, taken as the value at military (inferred), × the engine's
  military scale, × the spool speed: 60 % at idle to 100 % at military, the 1998 gauge's line (inferred). It feeds
  the rigid body's gyroscopic term through `Jet::airframe(&engine)`, a per-flight copy (the jet's definition stays
  unchanged).
* **Shutdown.** The throttle to OFF (training.md §7.2) cuts the fuel: no thrust and no fuel flow at once (the power
  winds down to idle and stays there, as a stopped engine's), and the RPM shown is the start sequence's run-down
  (`start.rs` `Phase::Rundown`): e^(−t / 15 s) from the RPM at the cut, stopped below 1 % (61 s from idle, inferred).
  In the air the RPM falls to 0 as on the ground (open: the windmill RPM).
* **Flame-out.** An empty tank flames out an engine that is lit or running (`SixDof::step`, `Start::flame_out`,
  2026-11-18): the same run-down as the fuel cut, with the throttle where it is, so the ENGINE light, the generators'
  lamps and the dark displays follow as after a shutdown (training.md §7.2). A start with an empty tank cranks to
  light-off and runs down again. Test: `sixdof.rs` `an_empty_tank_flames_the_engine_out`.
* **Frames.** `Engine::step` follows the rigid body's frame rules: a frame time that is not a positive number changes
  nothing, a frame is cut to 0.25 s and taken in steps of at most 1/120 s, each step the lag's exact solution at its
  rate (no overshoot, even at the F100-PW-229's 6.8/s in the afterburner range).

| engine (jets) | military / maximum, lbf | idle → military | source |
|---|---|---|---|
| F100-PW-200, TP-1538's own (the reference F-16A) | Table VI (static 12,750 / 20,140 installed) | 3.88 s | TP-1538 Table VI, figure 66 |
| F110-GE-100 (F-16D Barak) | 17,110 / 29,000 | 3.0 s | ratings: docs/real-aircraft.md §2 as FM-0; time: the F100's (`spool::ENGINES` type 100, inferred) |
| F100-PW-229 (F-16I Sufa, F-15I Ra'am × 2) | 17,800 / 29,160 | 3.0 s | ratings: Pratt & Whitney[^pw-f100]; time: the -220's 3 s[^tm4320] (inferred for the -229); to maximum 3.5 s against the F-15E's "less than 4 s"[^usaf-f15e] |
| F135-PW-100 (F-35I Adir) | 28,000 / 43,000 | 4.9 s | ratings: the F-35I row[^w-f135]; idle → maximum 6.0 s, Pratt & Whitney's "about 6 s"[^pw135], figure 66's shape stretched to it |

**A correction of the brief:** the brief names the F110-GE-129 for the Barak. The Barak is an F-16D Block 40, whose
engine is the F110-GE-100 (FM-0's choice, docs/real-aircraft.md §2); the -129 is the Block 50's. The model takes the
-100 (agreed with the orchestrator, 2026-11-03).

### 9.8 The gear (stage (b))

`sixdof/gear.rs`: three struts (nose, two mains). Each is a spring and damper along the world vertical at its
wheel's contact point; the tyre's forces lie in the runway plane: rolling friction 0.02 (inferred), braking friction 0.51 × the
pedal on the mains, side grip 0.55 (the tyre's peak, below), each growing linearly
from zero over a slip band of 0.03 m/s so nothing chatters; above walking pace the side force grows with the tyre's
slip angle and reaches the grip at 8° (a tyre's cornering stiffness; inferred). A braked tyre that stops sticks to its spot through a stiff
tangential spring until the pull exceeds its braking friction, so a braked jet stands against its idle thrust
(`Anchors`, kept by the flight with its engine and updated once per frame; a braked jet moves less than 1 mm in 10 s).
The forces act at the compressed wheel (the strut gives along its body z axis, inferred). A wheel pointing straight
up or down (a nose- or tail-first impact) gets the runway's push and no tyre force. The nose wheel steers (±32°, the
F-15I ±45°: the 1998 Real rows) at any speed: the F-16's steering has no speed schedule. The pilot engages it with a
button, "Use NWS until rudder is effective (approximately 70 knots)", "NWS should not be engaged above taxi speed
unless required"[^to-f16a]; the game has no NWS button, so the pedals engage it, and below taxi speed (30 kt,
inferred) it stays engaged: there centred pedals steer the nose wheel straight. Above 30 kt, with the pedals centred
(under 2 % of their travel) the nose wheel castors, rolling along its path with no side force (inferred). With the steering held
straight under full antiskid braking (the main tyres keep 0.15 of side grip, below) the jet yawed away into a ground
loop; the castoring nose wheel leaves it running straight on its mains (2026-11-16).

Springs: an oleo strut is an air spring, stiffest at its static point. Serviced to the common rule of thumb (its gas
compresses 4:1 from fully extended to static[^avweb]), its gas column at static is a third of its static compression,
and its stiffness there n·F / column (n = 1.1). With 0.15 m of static compression that is a linear sag of 0.15 / 3.3
= 0.045 m at the jet's reference weight (`jets::STRUT_SAG`), damping ratio 0.6; 12 % of the weight on the nose wheel
(all inferred: no public strut data). Until 2026-11-16 the sag was a linear 0.15 m: the soft struts let the body lean
out about 7° in a hard ground turn, and full pedal at 40–140 kt rolled the F-16 over its outer main wheel.

**Hops on Nevatim's runway** (2026-11-16, `test_mvp` F-35I take-off: "sink rate" at 161 kt, Mac headless). The
sim's terrain under the runway is the elevation data as it is, not a graded runway: its slope changes between 0.6 %
and 1.8 % within a few metres. At 118 kt and at 161 kt such a crest throws the Adir off its wheels for one frame
(0.1 g), and the roll sees up to 2.9 g; Ramon's runway gives the Sufa at most 1.6 g. The test's scripted pilot started
its 2 s gear-up wait at the first hop, so the gear moved during the second hop and the jet met the runway again with
the gear in transit: the limit is then a quarter of 4 m/s, and 1.6 m/s crashed it. The jet had not rotated yet; the
F-35I figures (α limit, stall speed) play no part. Fixed in the test: the wait restarts on every ground contact (gear
up with a positive climb), and the take-off now fails on any wheel back on the ground after gear up or on any
descent from 1 s to 8 s after it (all three jets; the least climb there: the F-35I about 1,000 fpm, the Sufa 84–140
fpm, where the test's pitch hold lets the nose sag to 5°). Fixed in the terrain on 2026-11-16: the bases are graded
([terrain.md](terrain.md) §16), and the test is strict again: the gear-up wait starts at the first airborne frame,
and the take-off fails on an airborne frame below the rotation speed or any wheel back on the ground after lift-off. The
scripted pitch hold's gain went from 0.05 to 0.1 per degree: off Ramon's graded runway the Sufa's nose sagged to 4°
after gear up and it sank 120 fpm; at 0.1 its least climb there is 370–590 fpm.
Tested and dropped (2026-11-16): the strut as the air spring itself (F·(column / gas length)^1.1, 0.15 m of stroke to
static, a fifth of the load fully extended) kept the wheels on the 118 kt crest but not the 161 kt one, and full pedal
at 50 kt then rolled the Barak over (74°): the inner strut stays loaded, the lean doubles to about 4°. Counting a
touching tyre as on the ground (not only a loaded one) changed nothing: the hops leave the runway.

**Full pedal on the runway** (2026-11-16, the user's report: full pedal skidded the jet from about 60 kt). Test
`full_pedal_steers_at_taxi_speed_and_never_tips` (`sixdof/flight.rs`): at 6 kt full pedal turns the Barak, the Sufa
and the Adir on the nose wheel's 32° within 25 % of the kinematic rate (29 / 28 / 20 deg/s against 27.5 / 27.5 /
18.4 deg/s); at 30–140 kt it yaws hard (the rudder and the steered nose wheel, up to 0.55 g of side grip: sideslip
7–16°), and the jet leans at most 2° (the F-16s) and 0.7° (the Adir), never over (bound 10°). On the 6-DoF the
keyboard's rudder keys move the pedals to full over 1 s instead of at once (`terrain_view.gd` `PEDAL_RAMP_S`,
docs/controls.md); a rudder axis stays direct.

**Taxi steering and braking pitch** (2026-11-17, the user on the Sufa at Ramon: the jet "keeps moving after I
release" the pedals, turning, and it "lean to much forward and backward on the ground when pressing the breaks").
Measured in the 6-DoF (Mac, `cargo test`), full pedal 2 s then released, and the brake switch on to a full stop at
idle:

* **The turn ran on.** Centred pedals let the nose wheel castor at every speed. A castoring nose wheel gives no side
  force, and the main wheels stand only 0.5 m behind the c.g., so nothing stopped the jet's yaw: at 10 kt the Sufa
  still turned at 13 deg/s 2 s after the release and 2.6 deg/s 6 s after. The keyboard's rudder keys also took 1 s to
  bring the pedals back. Fixed: below 30 kt the steering stays engaged and the nose wheel follows the pedals back to
  straight at once (`flight.rs` `NWS_TAXI_KT`); the keys spring the pedals back over 0.25 s (`PEDAL_CENTRE_S`,
  [controls.md](../../docs/controls.md)). The trim is untouched: the steering never writes it. The yaw now falls as
  fast as the nose tyre's side grip turns the jet's yaw momentum (the grip grows with the slip angle up to 8°, above):

  | jet | 10 kt: yaw at release, +1 s, +2 s, +5 s | 20 kt: the same |
  |---|---|---|
  | F-16D Barak | 29.1, 8.3, 1.7, 0.03 deg/s | 23.4, 9.9, 4.3, 0.43 deg/s |
  | F-16I Sufa | 29.1, 8.3, 1.5, 0.02 deg/s | 23.5, 9.9, 4.2, 0.40 deg/s |
  | F-35I Adir | 22.9, 3.3, 0.2, 0.00 deg/s | 23.0, 5.9, 1.5, 0.04 deg/s |
  | F-15I Ra'am | 17.5, 5.2, 1.0, 0.02 deg/s | 15.1, 6.9, 3.2, 0.38 deg/s |

  At 20 kt the slower fall is the tyres' own: with less slip angle per deg/s of yaw the nose tyre pushes less. Why not
  30 kt and above: held straight under full braking, the jet ground-loops from 40 kt (the braked mains keep 0.15 of
  side grip); from 30 kt and below it stops straight. Test `centred_pedals_stop_the_ground_turn`.
* **The rock.** The brake switch stepped the brakes from none to full, and the struts damped extension as softly as
  compression (damping ratio 0.6 per strut, about 0.3 in the jet's pitch). The F-16s' nose dipped 1.22–1.24° (the
  braked attitude is 0.88°: a 40 % overshoot); at the stop the braking force vanished and the nose came back up 0.4°
  past level and rocked three times, 1.3 s to settle within 0.1°; the Adir 0.61° and 0.17°, the Ra'am 0.85° and
  0.29°. The reborn model's inferred figure is about a degree under firm braking (8° per g limited to 2°,
  [docs/flight-model.md](../../docs/flight-model.md) "Brake pitch"); the dip itself was in range, the overshoot and
  the rock were not. Fixed: the brakes ramp from off to full and back over 0.5 s (`BRAKE_RAMP_S`, inferred: a pilot's
  press on the pedals), and an extending strut damps four times harder than a compressing one (`gear.rs` `REBOUND`,
  inferred: an oleo's smaller return orifice). Now from 10, 20 and 40 kt the Barak and Sufa dip 0.98–1.01°, the Adir
  0.50°, the Ra'am 0.69°; none comes back up past level (0.00°), and each is within 0.01° of its standing attitude 1 s
  after the stop. Test `braking_dips_the_nose_and_settles_without_rocking`.
* **Side effects on take-off and landing.** A brake held through touchdown builds up over 0.5 s, and a bounce starts
  that build-up again; brake release at full power starts the roll 0.3–0.5 s later; the harder extension damping
  also acts at rotation, lift-off and touchdown bounces; below 30 kt with the pedals centred the nose wheel holds
  straight on the take-off roll and the end of the landing roll. The take-off, landing, crosswind and full-pedal
  tests still pass unchanged.

**The drawn wheels** (since 2026-11-15, the user: "the wheels of the plane are not strictly above ground but half on
it"). The struts' lengths come from the jet's model: the game passes the model's `height` helper (its tyres' bottoms
below the c.g.; `IafFlight.set_gear_clearance`), and the gear stands there at the flight's weight on level ground
(`Gear::set_static_height`: each strut extended by its static sag, the loads shared by the wheels' places along the
body; set again each frame as fuel burns and stores leave). Before, the struts stood at the jets.rs c.g. height less
the sag at a heavier weight: the F-16s' tyres 11 cm into the apron. The ground under each wheel is the terrain's plane
under the c.g. (`IafFlight.set_ground_slope`, the height's rise per metre east and north from the terrain's heights
3 m to each side; `Gear::ground_slope`): on a sloping apron the wheels each meet the ground under themselves (the
F-35I at Nevatim stood 14 cm off the ground on one wheel). Guard: `modern-iaf/tests/test_wheels.gd`, each jet at its
base, parked, taxiing and lined up on the runway, every tyre within 6 cm of the ground.

**Weight on wheels** (2026-11-18, the Mac's headless `test_mvp`: the Adir's take-off check "off once" failed every run,
the Barak's once; the on-ground state dropped and came back during the roll). Cause: the game gives the ground height
under the c.g. once a frame, and the gear kept that height under the c.g. as the jet rolled on until the next frame.
On a sloping runway the ground then moved in steps: at 130 kt on Nevatim's runway (falling 1.3 %) it dropped 2 cm
each frame, more than the struts' compression there, so every frame the wheels left the runway and fell back on it;
the damper also read the jet's sink along the slope as the strut compressing. One roll counted up to 168 touchdowns.
The extension damping of 2026-11-17 (`REBOUND`) plays no part: at × 1 the same roll counts 167. Fixed in `gear.rs`:
* the ground is a plane through the spot where its height was taken (`Gear::ground_at`), so it stays in place between
  two readings;
* a strut's damper works on the strut's own compression rate, the wheel's sink against the sloping ground;
* weight on wheels is a compressed strut (`Gear::on_ground`), not a strut load above zero: the damper takes the load
  off an extending strut before its wheel leaves the runway.

Test `weight_on_wheels_changes_once_at_lift_off`: every jet at its reference weight and with a mission's stores
(+ 24 %), on a level, a falling and a rising 1.3 % runway, at 24 and 60 frames a second, leaves the runway once and
counts no touchdown. The ground-handling tests above also run at the mission weight: the released turn stops a
little sooner (the Sufa 1.3 deg/s at 10 kt and 4.1 at 20 kt, 2 s after release), and the nose dips in proportion to
the weight on the same struts (the F-16s 1.3°; a window run on the Mac at 16.5 t measured 1.24–1.31°). That run's
yaw rates (1.8 and 4.9 deg/s) are higher than the test's because the rudder keys take 0.25 s to centre
(`PEDAL_CENTRE_S`), where the test centres the pedals at once (inferred from the test's decay between 1 s and 2 s).

**Tyre friction and the antiskid (2026-11-15).** No public figure gives the F-16's or the F-35's tyre friction; the
model takes NASA's antiskid tests on a DC-9 main-gear tyre (inferred for a fighter's): on the dry runway the tyre's
peak drag-force friction coefficient is about 0.55, and the antiskid holds the braked tyre near that peak, averaging
0.91–0.93 of it[^tp1051]. Full brakes give 0.92 × 0.55 = 0.51 (was 0.4, FM-0's). Braking and cornering share the
peak (a friction circle): a fully braked tyre keeps at most √(0.55² − 0.53²) ≈ 0.15 of side grip, as the side force
falls during antiskid braking in the same tests. No wet or icy runway: the missions fly in dry weather.

**Crosswind.** The flight manual leaves the crosswind limits to its performance supplement (T.O. 1F-16A-1-1, not
public); the F-16's commonly quoted limit is 25 kt on a dry runway (secondary: Falcon BMS forum, citing Joe Bill
Dryden's "Semper Viper" crosswind tests)[^bms-xwind]. Test `crosswind_take_off_and_landing_track_the_centreline`
(`sixdof/flight.rs`): the Barak and the Sufa in 25 kt straight across, a maximum-power take-off and a landing roll
from 140 kt to a stop, a pilot on the pedals (rudder and nose-wheel steering) and the stick: at most 1.8 / 1.4 m off
the centreline on the take-off and 3.6 / 3.4 m on the landing roll (bound 5 m, a quarter of a 45 m runway's half
width; with the stiffer struts of 2026-11-16 the test's pilot needed twice the pedal gains).

**The autopilot's taxi turns** (`SixDof::set_pivot`, motion 0x16). The original model flies a scripted 30 m arc at
the speed it has. The 6-DoF turns on its wheels: the nose wheel steers toward the target heading on that 30 m
radius, wider where half the side grip cannot hold it at the speed, and the brakes slow it, straight, to the speed
the radius allows (9.0 m/s, 17 kt; all inferred): a braked main tyre keeps little side grip, and turning under full
brakes ground-looped the jet backwards onto its tail (2026-11-16). Test `taxi_pivot_turns_on_the_wheels`: from
10 m/s a 90° turn ends in 7.0 s on about a 32 m radius, the heading and the position smooth. The AI jets on the original model keep their arc.

### 9.9 The jets' data (stage (b))

`sixdof/jets.rs`. The aerodynamics are TP-1538's F-16 tables for every jet, on each jet's own wing area, span and
chord (labelled, as FM-0).

| jet | reference weight | wing, span | inertia | gear: wheelbase, track, c.g. height | engines |
|---|---|---|---|---|---|
| F-16 (TP-1538) | 20,500 lb (Table I) | 300 ft², 30 ft | Table I | 13.2 ft, 7.75 ft, 1.75 m | F100-PW-200 |
| F-16D Barak | 24,900 lb: 19,100 empty + 5,800 fuel (FM-0) | 300 ft², 30 ft | Table I × weight | as the F-16 | F110-GE-100 |
| F-16I Sufa | 29,350 lb: 20,500 + 8,850 (FM-0) | 300 ft², 30 ft | Table I × weight | as the F-16 | F100-PW-229 |
| F-35I Adir | 47,550 lb: 29,300 + 18,250 (FM-0) | 460 ft², 35 ft[^lm-f35] | Table I × weight × (35/30)² | 19.75 ft, 14.24 ft[^mason-f35], 2.0 m | F135-PW-100 |
| F-15I Ra'am | 59,665 lb: 37,000 + 22,665 (FM-0) | 608 ft², 42.8 ft (FM-0) | Table I × weight × (42.8/30)² | 17.78 ft[^sac-f15], 9 ft[^to-f15e], 2.1 m | 2 × F100-PW-229 |

The F-16's wheelbase 13.2 ft is the 1998 Real row's (`data_set.rs`). Inferred: the F-16's track 7.75 ft (open), every
c.g. height, every jet's inertia but TP-1538's (scaled by weight and span²), the chord of the F-35I (14.9 ft) and the
F-15I (16.1 ft) from the F-16's ratio of chord to area / span, the thrust line through the c.g., twin engines
turning the same way.

### 9.10 Stage (b) results

`cargo test -p iaf-flight --test sixdof -- --nocapture` (2026-11-03). Tolerances set before the first run.

| test | the model | source | tolerance | verdict |
|---|---|---|---|---|
| static thrust, all three rated engines | the ratings to 0.1 % | the ratings above | 0.1 % | ok |
| idle → military, F110 / F100-PW-229 | 3.00 / 3.00 s | 3 s (above) | 0.05 s | ok |
| idle → maximum, F100-PW-229 | 3.50 s | "less than 4 s" (F-15E, USAF) | below 4 s | ok |
| idle → maximum, F135 | 6.00 s | "about 6 s" (Pratt & Whitney) | 0.05 s | ok |
| standing on the gear, brakes on, idle, 3 s after the drop (all five jets) | at rest, sag 0.045 m (`STRUT_SAG`), nose wheel 13.8–15.3 %, then under 1 mm in 10 s | `STRUT_SAG` and 12 % + the idle thrust's moment (design) | 0.03 m, 1 %, 5 mm | ok |
| take-off roll, TP-1538's F-16A at 29,253 lb, maximum power, rotation at 150 kt[^ni-f16] (2026-11-03; since 2026-11-15 the rotation at 170 kt, §9.13) | 1,759 ft, lift-off at 164 kt then; 2,201 ft since 2026-11-15 | 2,380 ft (USAF SAC F-16A, at that weight with two tanks and two AIM-9J[^sac-migflug]) |±20 % (±10 % since 2026-11-15) | failed −26 % then; passes since 2026-11-15 (§9.13) |
| braking from 100 kt, Barak, idle, full brakes | 487 m, straight | 440 m from the friction and the idle thrust | ±25 % | ok |

**The take-off roll is 26 % short (2026-11-03).** Looked at: the stores' drag the test leaves out (two tanks, two
missiles, ΔCD about 0.025, inferred) is about 2–3 % of the thrust at take-off speeds, too little. The roll follows
the thrust: Table VI's maximum, carried to Mach 0, is 20,140 lbf installed, and at 29,253 lb the mean acceleration
over the roll is about 0.65 g, which gives this distance. Open: the SAC's lift-off speed and its conditions (runway
temperature, the power setting's definition, the take-off technique). The rotation here is a fixed full nose-up
stabilator at 150 kt then. Since 2026-11-15 the rotation is at 170 kt (§9.13) and the source test
`take_off_roll_against_the_sac` runs within ±10 % of both SAC rolls (2,201 / 3,623 ft against 2,380 / 3,725 ft); the
1,759 ft pin is gone.

### 9.11 The control system (stage (c))

`sixdof/fcs.rs` is TP-1538's control system A, read off appendix A's text and its block diagrams (figures 62–65,
printed pp. 210–217), stepped with the rigid body (at most 1/120 s):
* **Pitch** (figure 62): the stick force through a 60/(s + 60) prefilter and figure 62(e)'s gradient gives an
  incremental g command, limited to +8 g and to figure 62(b)'s negative limit (−1 to −4 g by q̄); 8.3/(s + 8.3);
  feedback of washed-out pitch rate (0.334), filtered (an − 1) and the α limiter (0.322 g/deg above 15° with
  pitch-rate lead, 1 g/deg more above 20.4°: appendix A's "0.322 g/deg between 15° and 20.4° and 1.322 g/deg above"),
  shaped by (3s + 12)/(s + 12); the loop gain 1.5 × figure 62(d)'s q̄ schedule into a proportional and an integral
  path (5 and 5/s, ±25° each), plus 0.5 × α for the artificial stability; the actuator 20.2/(s + 20.2), 60 deg/s,
  ±25°. Figure 63's maximum commandable g by α follows from the limiter. It is the production F-16's CAT I limit:
  T.O. 1F-16A-1 figure 1-44 draws 9 g up to 15°, 7.3 g at 20.4° and 1 g at 25.2°[^to-f16a].
* **The g command region** (2026-11-15, finish list F3): below the limiter the integrator takes the g error alone
  (n_cmd − (an − 1)) at 2.5 × the loop gain (inferred). The manual: "Commanded pitch responses are in g increments
  per stick force for AOA below 15 degrees"[^to-f16a]. TP-1538's integrator, 5/s on the whole shaped error with its
  washed-out pitch rate, stopped 0.5 g short while the speed bled (8.4 g at 550 kt) and reached 7.4 g after 1.5 s;
  on the g error alone at 5/s it overshot to 10 g. Now a full pull at 550 kt, 10,000 ft reaches 9 g after 1.9 s
  (Barak, Sufa) and 2.1 s (Adir), peak 9.3 g. Sources: a modern fly-by-wire fighter reaches "a bit over nine Gs in
  about one and a half seconds"[^vanpatten], and on the limiter the F-16 stays under the 9.5 g the manual counts as an
  over-g[^to-f16a]. At 440 KIAS, 10,000 ft (the top of the F-16A's "330 KIAS to 440 KIAS" corner[^plaehn]) the Barak
  pulls 9.3 g. On the limiter, TP-1538's integrator as before.
* **STORES CONFIG, CAT I / CAT III** (F7): the pilot's switch, as in the jet ("The CAT III position shall be
  selected when the aircraft is configured with a category III loading"[^to-f16a]); key Alt + S,
  `IafFlight.set_fcs_switches`; it starts at CAT I. CAT III adds a limiter on figure 1-44's CAT III line for the
  jet's weight (α at 1 g / where it meets CAT I: 25,000 lb 15.5° / 16.25° at 8.6 g, 30,000 lb 15.65° / 17.05° at 8.35
  g, 35,000 lb 15.8° / 18.0° at 8.0 g; "maximum AOA varies from approximately 16-18 degrees as a function of GW and
  g"), 20 g per degree over it with the pitch-rate lead (inferred); the stick's roll command × 0.6 ("reduced by
  approximately 40 percent of CAT I authority", `data_set::F16_CAT3_ROLL`, beside the F-16's other roll figures); pedal rudder
  faded out from 5° to none at 15° ("Zero rudder authority available at 15° AOA"; the 5° start inferred). Open: figure 1-43's CAT III "g command
  system until 7° AOA at 100 knots to 15° AOA at 420 knots" (the model keeps CAT I's 15° for that boundary).
* **MANUAL PITCH override** (F15): held (key Alt + M), it removes figure 62(b)'s negative g limit (the jet's −3 g
  stays, inferred); above α 29° the stick moves the stabilator directly (full stick ±25°, centred stick streamlines it) and the
  pedals the rudder without the α fade[^to-f16a]. `State.stalled` is set in the air outside α −5…29° (the manual's
  recovery is "AOA within −5 to +25 degrees", and above 29° the limiters give way to the yaw-rate limiter);
  `spinning` when stalled and turning about the vertical faster than 35 deg/s (inferred: half the manual's 70–100
  deg/s upright spin).
* **Roll** (figure 64): figure 64(b)'s gradient (up to 308 deg/s), 10/(s + 10), against the filtered roll rate,
  × 0.12 to the ailerons (±21.5°, 80 deg/s, 20.2/(s + 20.2)); above α 29° the spin prevention drives them against the
  yaw rate (8.34). The Barak and the Sufa fly the production F-16's roll instead (2026-11-14, finish list F2; the
  user's decision "Use the real data in both"): the figure reborn's Real F-16 rows read, `data_set::F16_ROLL`
  (sources: docs/real-aircraft.md §8.2). Figure 64(b)'s stick shape scaled to 240 deg/s at full stick, followed as a
  first-order command that starts at 688 deg/s² (time constant 240 / 688 = 0.35 s); the flaperons at 62 deg/s within
  20° down / 23° up, so the aileron's ±21.5° is TP-1538's. The command also goes forward as the aileron that rolls the
  jet steadily at that rate, |Clp|·(p·b/2V) / Cl_δa with TP-1538's Clp −0.40 and 0.0025/° (`aircraft::F16_CLP`, the
  constants reborn's "Asymmetric stores" uses; inferred: figure 64(a)'s proportional loop alone settles at 218 deg/s
  against its 308 deg/s command); the 0.12 loop corrects the rest, so unbalanced stores still roll the jet. The
  autopilot's rate command keeps the 10/(s + 10) path without the feedforward (with it the Sufa's autopilot landing
  crashed, `player_autopilot_flies_the_sims_three_jets`). The Adir flies the same figure (`data_set::F35I.roll`,
  inferred, §9.19). The Ra'am and TP-1538's jet keep control system A's roll (308 deg/s, 80 deg/s).
* **Yaw** (figure 65): figure 65(b)'s pedal gradient (±30°), faded out between α 20° and 30°; the stability-axis yaw
  damper (r − p α, (3s + 15)/(s + 15), 1.5 s/(s + 1), × 0.5) and lateral acceleration (19.32); the aileron-rudder
  interconnect 0.075 α minus figure 65(a)'s q̄/ps term; above α 29° 0.75 × yaw rate; 120 deg/s, ±30°.
* **Leading-edge flap** (appendix A): 1.38 α through (2s + 7.25)/(s + 7.25) − 9.05 q̄/ps + 1.45, a 0.136 s lag, 25
  deg/s, 0–25°.

Left out or inferred: the roll command's rate-limiting branches and the roll-rate notch filter (structural), the
differential tail (the δa = 20° tables are taken as the whole roll control), the trims; the integrator held at zero
with weight on the wheels (the F-16's switch; TP-1538 flies no ground phase); the full stick = the gradients' ends
(180 N pull, 80 N push, 75 N lateral, 480 N pedal); the speed brake opening at 30 deg/s. Signs (§9.2, the
`control_signs` test): a right stick rolls right through −δa, a right pedal yaws right through −δr.

The game's controls map onto it: the stick (pull positive) is the g command, the throttle lever (0.74 military) is
figure 66(b)'s travel (military at 77 %), the rudder is the pedal and, on the ground, the nose-wheel steering; the
brake key is the wheel brakes on the ground and the speed brake in the air; the gear lever moves the gear in 3 s.

### 9.12 The flight (stage (c))

`sixdof/flight.rs` (`SixDof`) is one flight: the jet, its control system, engines, gear, fuel and mass. `fm.rs`
(`Fm { Original, SixDof }`) holds either model behind `IafFlight`; `Fm::start` takes the 6-DoF when the type's
`bd.ibx` section has `Model = 6dof` (`iaf-sim fm` writes it into the sim's two sections) and the 6-DoF has
the jet (`jets::by_type`: F-16 → Barak, F-16I → Sufa, F-35I → Adir, F-15I → Ra'am). The original game's sections have
no `Model` key: `crates/iaf-flight/tests/fm.rs` checks every original type on both data sets flies the original model, bit for bit as
before. The autopilot drives either through the `autopilot::Host` trait (the `Aircraft` calls it made before, unchanged).

* **Frames.** NED inside, the game's ENU outside: (east, north, up) = (y, x, −z). `State` and `ApView` as the original
  gives them (position, velocity, body axes, Euler angles, α, β, g, Mach, RPM 60–100 % with the spool, afterburner
  stages, thrust, fuel, mass); the autopilot's attitude is the flight path's, as the original's.
* **Starts.** In the air: a level trim at the start's speed (α and stabilator from the 1 g balance, the engine's power
  from the drag), the control system settled on it. On the ground: gear down, brakes on, set on its struts at the first
  terrain height the game passes.
* **Fuel.** Fuel flow = thrust × TSFC (military's up to military, blending to maximum's over the afterburner range:
  F100-PW-229 0.76 / 1.94, F110-GE-100 0.64 / 2.05, F135 0.79 / 2.0 lb/lbf/h, the REAL rows' fuel flows over the
  ratings), never below the idle flow (military's TSFC × the static idle thrust × the density ratio, inferred); the
  mass and the inertia fall with the fuel (fuel and stores at the c.g., inferred). The game's stores add their mass,
  and their drag index × 10⁻⁴ as ΔCD on the F-16's 300 ft² wing (§9.18). Drop tanks fill at the start and the jettison sets the fuel
  and its maximum, as `Aircraft::set_fuel_capacity` / `set_fuel`. A dead engine gives no thrust.
* **Mach** (inferred: TP-1538 is low-speed data and no public F-16 table covers high Mach): the normal force × the
  lift-curve slope's Mach factor of a wing of the jet's aspect ratio (DATCOM's subsonic 2πA / (2 + √(4 + A²(1 − M²)))
  relative to Mach 0, up to Mach 1.0; Ackeret's 4 / √(M² − 1) from Mach 1.4; linear between); the wave drag rising
  from 0 at Mach 0.9 to w at Mach 1.2, then w × (M / 1.2)^k, fit per jet (§9.15); the gear's ΔCD 0.02 (FM-0's);
  thrust above Mach 1.0 the line through Table VI's Mach 0.8 and 1.0 carried to Mach 2.0, held beyond.
* **The control system's limits**: each jet's g limits (the F-16s and the Adir +9 / −3, the Ra'am +8.1 / −2). The
  autopilot reads the stick as linear in g (its `ApView`: 1 g at the centre, MaxG / MinG at the ends); while an
  autopilot loop flies, the 6-DoF takes the stick as that g command instead of figure 62(e)'s gradient, and the
  lateral stick as a roll-rate command (full stick the flight data's MaxRollRate, as the original's roll channel)
  instead of figure 64's gradient: through the gradient the autopilot's small bank corrections rolled at a few deg/s
  and NAV circled its waypoints 4–5 km out.
* **Wind**: the mission's wind (`set_wind`, the original's vector) moves the air: the aerodynamics see the velocity
  through the air. In the air its light turbulence is added each substep (`near_ground::gust`, the function reborn's
  Better physics `wind` uses, docs/flight-model.md: vertical rms 0.1 × the wind speed below 300 m, 30 % of that from
  1,500 m; inferred); on the wheels the steady wind alone. The AoA probe reads the steady wind's flow (the gusts
  stay off the needle).
* **Ground effect** (2026-11-14): the functions reborn's Better physics `ground_effect` uses (`near_ground`,
  docs/flight-model.md): the lift × Helmbold's factor at A/φ, and the induced drag CL²/(πA) (Oswald factor 1,
  inferred) of the free-air lift replaced by McCormick's φ × that of the new lift. The wing's height is taken as the
  c.g.'s above the terrain (inferred: reborn's takes the wheels' height plus the gear clearance). The Barak at 1.7 m:
  lift ×1.06 (`ground_effect_and_gusts_from_the_shared_functions`).
* **Systems damage** (2026-11-14): the pilot's damage flags (docs/damage.md §5.2) read as the original reads them,
  through its functions (`aircraft::damage_bits`, `aircraft::stick_authority`): the engine (2, 16, 22; a twin's right
  engine 3, 17, 23) stops it, one engine of a twin halves the thrust; both afterburners (8, 9) stop the throttle at
  military; the fuel leak (10) burns a quarter of the type's FuelFlowAtMaxThrust on top, engine running or not;
  hydraulics (18) leave a quarter of the stick (the rudder keeps its authority); with total flight-control damage (24)
  the control system stops moving the surfaces and they stay where they were (inferred: the original forces a spin). Gear
  damage (7) freezes the gear lever in the shared `terrain_view.gd`, so the 6-DoF's gear stays where it is. Test
  `systems_damage_as_the_original_reads_it`.
* **Asymmetric stores and roll trim** (2026-11-14): the game's stores moment (`stores.rs` `roll_moment`, kg·m, the
  same call reborn's Better physics "Asymmetric stores" takes; a fuel tank × the external fuel left,
  `aircraft::tank_share`, as reborn's) rolls the jet with its weight × the load factor; the
  roll-rate command meets it as the real control system does, so hands-off the jet rolls slowly toward the heavy
  wing. The roll trim (`aircraft::step_roll_trim`, the same rocker, rate and ±66.8 deg/s authority of TP-1538
  figure 64 as reborn's) adds its roll rate to the roll-rate error, and is left out while an autopilot loop flies.
  Every 6-DoF jet takes the F-16's trim authority (they all fly TP-1538's control law). The stores' left / right drag
  index difference (the input reborn's original model turns into a sideslip bias) yaws the jet toward the draggier
  side at a quarter span out (inferred: the F-16's stations 3 / 7). Tests `one_heavy_wing_rolls_and_the_trim_holds_it`,
  `a_tank_rolls_while_it_holds_fuel_and_its_drag_yaws`.
  In the game a release reaches the 6-DoF through the shared `player_weapons.gd` `_push_stores` (the call reborn's
  model takes): `modern-iaf/tests/test_sim_release.gd` releases one of two MK-84 (SGL) from the Sufa in flight; the
  6-DoF's mass drops 925 kg at once, the left / right drag index differs by the bomb's 11.8 × 10⁻⁴, and hands off
  the jet rolls toward the bomb left (finish list W19).
* **The ground.** The touchdown check is reborn's (`aircraft::landing_limits`, reborn's Better physics "landing
  limits", docs/flight-model.md §10): a gear-down touchdown sinking slower than 4 m/s (≈ 13 ft/s, inferred: the
  F-16 manual gives no figure) with the wings within 10°, the nose above −5° and below 15° counts as a landing. The
  15° is the F-16's: "Nozzle, speedbrakes, and ventral fins may contact runway if 15-degree pitch angle is
  exceeded"[^to-f16a]. Faster is a sink-rate crash, banked or nose-down a landing crash, nose-up a tail strike; Easy
  landing doubles the limits, the gear in transit cuts them (×0.2, sink ×0.25), and the autopilot's landing keeps the
  original's 40 m/s as on reborn's model (test `touchdowns_meet_the_shared_landing_limits`). The c.g. within 0.5 m of
  the runway, or the belly with the gear up, is a crash. As the original's: water
  under the wheels and rough ground above 25.7 m/s are crashes, a touchdown on more than 10° of slope a landing crash,
  scenery under the jet (a roof, a tree top) a crash at any speed; "no crashes" and "invulnerable" pass everything.

### 9.13 Stage (c) results

`cargo test -p iaf-flight --test sixdof -- --nocapture` (2026-11-03):

| test | the model | source | tolerance | verdict |
|---|---|---|---|---|
| neutral stick, Barak, 350 kt, 10,000 ft, 60 s (the control system's 1 g hold) | +16 m, 1.00 g | (design) | 60 m | ok |
| full pull at 550 kt, Barak / Sufa / Adir (2026-11-15) | 9 g after 1.92 / 1.90 / 2.13 s, peak 9.33 / 9.27 / 9.04 g | "about one and a half seconds"[^vanpatten]; under 9.5 g[^to-f16a] | 1.5 s + 50 %; < 9.5 g | ok |
| full pull at 440 KCAS (the source's KIAS taken as KCAS), 10,000 ft, Barak | 9.31 g | the corner's top end, 440 KIAS[^plaehn] | ≥ 9 g | ok |
| CAT III, 30,000 lb, full pull at 300 kt | α peaks 17.3°, settles within 0.32° of figure 1-44's line | 16–18°[^to-f16a] | < 18°, 0.6° | ok |
| full roll stick at 350 kt, CAT III / CAT I | 144 / 243 deg/s (0.59) | 0.6[^to-f16a] | ±0.06 | ok |
| deep stall (put in at α 60°, 20,000 ft), MPO rocking in phase | stays at α 59° hands-off; out after 9.4 s, 1,764 ft lost rocking; flying at 354 kt 20 s on | "one or two" cycles, "1000-1500 feet per pitch rock cycle"[^to-f16a] | < 30 s, < 4,500 ft | ok |
| full pull at 200 kt, Barak | α peaks at 26.6° | figure 63, appendix A: the limiter holds about 25° | ±3° | ok |
| roll from 1 g at α 25°, 30,000 ft, full stick (TP-1538's jet, at 186 kt, α 24.7°) | 90° in 2.32 s, 180° in 3.63 s | TP-1538 Table V, control system A: 2.6 s, 3.8 s | ±30 % | ok (−11 %, −4 %) |
| fuel flow, Sufa, military, sea level | 13,492 lb/h | 13,500 lb/h (the F-16I REAL row) | 3 % | ok |
| take-off roll through the control system (TP-1538's jet, 29,253 lb, maximum power, rotation at 170 kt to 12°, flaps down; 2026-11-15) | 2,201 ft, lift-off at 182 kt | 2,380 ft (SAC) | ±10 % | ok, −7.5 % |
| the same at military power (2026-11-15) | 3,623 ft, lift-off at 176 kt | 3,725 ft (SAC, intermediate) | ±10 % | ok, −2.7 % |

**The take-off roll, found (2026-11-15).** The roll was 23 % short because the test rotated at 150 kt, a clean jet's
afterburner rotation[^ni-f16], with the SAC's 29,253 lb. The model itself lifts off 6–12 kt after the pull starts,
as the manual's technique says (rotate 10–15 kt below the take-off speed to 8–12° of pitch, T.O. 1F-16A-1
p. 2-20[^to-f16a]). Both SAC rolls, at maximum and at intermediate power, fit one lift-off speed of about 180 kt
with the model's thrust; the thrust carried below Mach 0.2 (Table VI), the rolling friction and the stores' drag
move them by a few per cent only. So the take-off now rotates at 170 kt, the rotation speed quoted for an
air-to-air load (Falcon BMS forum, secondary)[^bms]; both rolls are within 10 %. A regression found on the same
forum ("70 kt plus 3 kt per 1,000 lb of gross weight", 158 kt here, its chart unnamed) gives a roll 30 % shorter
than both SAC figures and is not used. The F-16C/D's and F-16I's take-off speeds by weight are open (their
performance supplements are not public).

**Tested and corrected (2026-11-03): two test setups.** The g test was first written as "9 ± 0.5 g at 450 kt"; there a
9 g pull needs α ≈ 21°, the α limiter takes 2 g away and the jet pulls 7.6 g, which is figure 63's design: the test
moved to 550 kt and states the limit. The roll test first trimmed by a pilot loop that settled at α 21–28° (roll times
from 1.9 to 3.5 s as α varied); it now starts from the computed 1 g trim at α 25° with the stick that holds it (figure
62(e) at 7.82 g, 0.78 of the pull).

**The validation rows on the 6-DoF** (`cargo test --release -p iaf-flight --test validation sixdof -- --nocapture`;
the same public figures as §5; "ok" inside, "close" within 10 %, "OFF" further; not tuned):

| test | Barak | Sufa | Adir | Ra'am |
|---|---|---|---|---|
| thrust SL static, military / full AB | 17,110 / 29,000 lbf ok / ok | 17,800 / 29,160 ok / ok | 28,000 / 43,000 ok / ok | 35,600 / 58,320 ok / ok |
| 1 g stall at the α limit, SL (`flight::stall_speed`, 2026-11-16) | 125 kt ok | 136 kt close | 128 kt ok (121–147) | 136 kt **OFF** (155 KCAS) |
| neutral stick, 60 s, 10,000 ft, military | +818 ft, to 643 kt **OFF** | +1,066 ft **OFF** | +1,164 ft **OFF** | +1,063 ft **OFF** |
| max level speed, SL | 785 kt, Mach 1.19 ok (1.2) | Mach 1.19 ok | 750 kt, Mach 1.14 close (700 kt) | Mach 1.19 (-) |
| max level speed, 40,000 ft | Mach 1.99 ok (2.0) | Mach 1.99 ok (1.89–2.05) | Mach 1.60 ok (1.6) | Mach 1.99 ok (2.0) |
| max roll rate, roll 0 → 90° at 350 kt (2026-11-16: the command ramped) | 266 deg/s **OFF**, 0.80 s **OFF** (0.55) | 261 close, 0.85 s **OFF** | 258 (-), 0.93 s (-) (the F-16's roll since 2026-11-16) | 178 (-), 0.98 s (-) |
| instantaneous turn, 420 kt, 10,000 ft | 21.4 deg/s at 7.7 g ok | 20.3 at 7.0 g ok | 20.0 at 6.7 g (-) | 19.2 at 6.8 g (-) |
| climb (Ps), SL, full AB | 57,456 ft/min close | 47,572 (-) | 40,149 (-) | 46,583 (-) |
| fuel flow military / full AB, SL | 10,911 / 63,618 lb/h ok / ok | 13,484 / 59,947 ok / ok | 22,066 / 89,458 ok / ok | 26,968 / 119,775 ok / ok |

Why the OFF rows are OFF: the "neutral stick" row holds 1 g (the control system's design), so the height follows
the speed: at military the jets accelerate from 350 kt to 630–640 kt (the wave drag starts at Mach 0.9; no public
figure for the military top speed at 10,000 ft). The Adir's stall: TP-1538's lift curve on the F-35's wing area
(inferred) at 47,550 lb. The roll: see "The F-16's roll" below.

**The F-16's roll** (2026-11-14, finish list F2; `f16s_roll_at_the_shared_figure` in
`crates/iaf-flight/tests/sixdof.rs`: full right stick from wings level at 10,000 ft, military, 2 s; the figure
240 deg/s at 688 deg/s², docs/real-aircraft.md §8.2):

| jet, speed | steady rate (1.5–2 s) | peak | largest roll acceleration, first 0.5 s | 0 → 90° |
|---|---|---|---|---|
| Barak, 350 kt | 249 deg/s | 250 | 472 deg/s² | 0.80 s |
| Barak, 480 kt | 247 | 249 | 801 | 0.65 s |
| Sufa, 350 kt | 247 | 249 | 419 | 0.85 s |
| Sufa, 480 kt | 247 | 247 | 727 | 0.68 s |
| Adir, 350 kt | 246 | 247 | 344 | 0.93 s |
| Adir, 480 kt | 248 | 248 | 599 | 0.72 s |

Since 2026-11-16 (finish list, roll onset) the stick's rate command ramps at 688 deg/s² to the stick's rate, through
reborn's roll channel (`channels::Angle`, the original's `FUN_005adc70`, the rule reborn's Real F-16 rolls by:
240/688/2 + 90/240 = 0.55 s to 90°). Before, a first-order command of time constant 240/688 = 0.35 s started at
688 deg/s² and slowed (Barak 0.87 / 0.78 s, Sufa 0.88 / 0.80 s, Adir 0.92 s at 350 kt). The jet lags the command: the
flaperons move at 62 deg/s (Stepaniak, AFIT 1995) and reach the aileron that rolls 240 deg/s at 350 kt only after
about 0.3 s, so the onset is 420–470 deg/s² at 350 kt and 730–800 at 480 kt: within the measured 8–12 rad/s²
(460–690 deg/s², docs/real-aircraft.md §8.2) at 350 kt, above it at 480 kt. Tested and dropped (2026-11-16): an
aileron for the ramp's roll acceleration (Ix·ṗ / (q̄·S·b·Cl_δa)) added to the feedforward, 0.78 s at 350 kt (−0.02 s):
the loop already drives the flaperons at their rate. The test asserts the steady rate and the peak within 5 % of
240 deg/s and 90° within 0.82 / 0.87 / 0.95 s at 350 kt and 0.67 / 0.70 / 0.75 s at 480 kt (Barak / Sufa / Adir). Before F2 the Barak rolled at 218 deg/s and banked 90° in 0.80 s at 350 kt (the
Sufa 218, 0.83 s). The table above it reads 265–267 deg/s: its "max roll rate" is the largest frame-to-frame change
of the bank angle over 3 s, which the Euler angles inflate once the jet is past inverted. The steady rate is 2–3 %
above the figure: the loop leaves the moments the feedforward does not model (the rudder interconnect's roll, the
sideslip). Tested and dropped (2026-11-14): the feedforward on TP-1538's 10/(s + 10) command (0.80 s at 350 kt,
0.68 s at 450 kt) made the validation's bank-holding pilot oscillate ±50° about 80° (the flaperons hit their rate
limit at each reversal), so its turn row fell from 21.4 to 16.7 deg/s, and with the autopilot's command it crashed
the Sufa's landing; the tables' own Clp and Cl_δa at α instead of the two constants gave 254 deg/s steady, no
closer. Pitch and yaw are unchanged: full pull 8.44 g at 550 kt, α 26.6° at 200 kt, the turn rows 21.5 deg/s at
7.7 g (Barak, before 21.4) and 20.3 at 7.0 g (Sufa, the same), TP-1538's Table V roll 2.32 / 3.63 s, the stores'
roll and trim tests as before.

**The frame cost**: a budget, not parity (the orchestrator's decision of 2026-11-03): at most 20 µs per jet per 1/60 s
frame on this laptop (i7-1185G7), release build, enforced by `frame_cost_within_budget` in
`crates/iaf-flight/tests/fm.rs` (the median of 9 runs of 2,000 frames, so a busy machine's spikes do not count;
`cargo test --release -p iaf-flight --test fm`). Measured 2026-11-03 under the bench lock with other sessions' work
running: the 6-DoF 4.1 µs, FM-0 1.2 µs (two RK4 steps of four force evaluations and one control-system step per frame;
the atmosphere and the airframe built once per substep and frame). `tests/godot/_flight_bench.gd` stops the flight
model (`fm_stopped`) and measures the rendering; it flies the original data, which never reaches the 6-DoF.

### 9.14 A real flight on the 6-DoF

The sim has no flying scene of its own yet (no terrain or missions: items B1, E2), so the flight ran as FM-0's did
(§7): the original game's scene (`--path iaf-reborn`, headless, `IAF_DEFAULT_SETTINGS=1`) with `IAF_ASSETS_DIR`
pointing at an overlay whose `install/resource/md` is the sim's own data, whose `[F-16]` section says `Model = 6dof`.
Mission 311 at Ramat David with Extras "F-16 version" = Sufa: the 6-DoF Sufa with the mission's stores (45,210 lb).
A scratch script flew it (`tv.scripted_stick` and the throttle, gear and brakes; the stick is the control system's g
command); the numbers are from its prints and the blackbox. 2026-11-03, on the fitted wave drag (§9.15):

| item | flight | public figure / test |
|---|---|---|
| lift-off | 174 kt, 17.0 s, 656 m (2,153 ft) of roll at full AB, rotation at 150 kt to 12° | FM-0's flight 169 kt, 2,150 ft (§7); F-16I open |
| top speed, full AB, 4,000 ft MSL (a second run) | 742 kt, Mach 1.14, at 123 s | ~Mach 1.2 at low level: close (−5 %; the fit is at its reference weight, clean; this jet carries 45,210 lb with stores) |
| level 450 kt at 4,000 ft | throttle 0.40 (below military) | (no public figure) |
| instantaneous turn, from 450 kt, 80° bank, full pull | 17.5 deg/s at 5.3 g, at 386 kt | the F-16I REAL row's ~20.9 deg/s at 7.8 g (22,000 lb, clean; uncertain): this jet carries 45,210 lb |
| climb, 450 kt, full AB, 30 s from 4,000 ft | 11,870 ft/min | (no public figure at this weight) |
| approach and touchdown | gear down at 260 kt, a 3° approach at 200 kt, touchdown at 195 kt sinking 482 ft/min (2.5 m/s) | the touchdown checks (3 m/s, inferred) pass |
| the rollout | a rough-ground crash: the script lands on the start point's line, and mission 311 starts on a taxiway whose approach end is rough ground (the original's rule: rough ground above 25.7 m/s) | open: a scripted landing on Ramat David's runway |

Before the ground-surface checks (commit 417993a6), the same approach ended in a landing: touchdown at 196 kt sinking
481 ft/min, stopped in 1,377 m (4,517 ft) on the brakes in 30 s (1 landing counted).

Pictures (in the session's scratchpad, for the "IAF 2026 Progress" page): the flight's timeline
(`tools/flight_timeline.py`: take-off, the turn, the climb, the approach and the touchdown), the earlier landing's,
the top-speed run's, Cm(α) at three stabilator settings against TP-1538's two trims, and the Table V roll against
TP-1538's times.

### 9.15 The wave drag: fit to public performance

**Not a sourced table** (the orchestrator's decision of 2026-11-03, within "real data only, inferred labelled"): no
public F-16 drag-rise table was found, and TP-1538's low-speed data with the 1998 Real rows' wave drag gave the Sufa
Mach 1.86 at 4,000 ft. Each jet's wave drag is two numbers, fit so its level top speed at its reference weight, full
afterburner, meets its published figures: ΔCD rises from 0 at Mach 0.9 to w at Mach 1.2 (the 1998 Real rows' shape),
then w × (M / 1.2)^k (`fit_wave_drag` in `crates/iaf-flight/tests/sixdof.rs`, ignored; the top speed is
`flight::top_speed`, the first speed where full-afterburner thrust no longer meets the level-trim drag). w comes from
the sea-level figure (only w acts below Mach 1.2), k from the 40,000 ft one. The Adir's sea-level 700 kt is the
F-35A's placard (inferred), not a thrust limit, and the Ra'am has no sea-level figure: both take the Barak's k and w
from 40,000 ft. A sourced table replaces the fit when one turns up.

| jet | w | k | fit to | top speed, sea level | top speed, 40,000 ft |
|---|---|---|---|---|---|
| F-16D Barak (and TP-1538's F-16) | 0.0509 | 0.195 | Mach 1.2 SL, 2.0 at 40,000 ft (tests/validation.rs REFS) | Mach 1.20 | Mach 2.00 |
| F-16I Sufa | 0.0513 | 0.212 | Mach 1.2 SL, 2.0 at 40,000 ft (the F-16's; Block 50/52 1.89–2.05) | Mach 1.20 | Mach 2.00 |
| F-35I Adir | 0.0682 | 0.195 (the Barak's) | Mach 1.6 at 40,000 ft | Mach 1.14 (700 kt placard: not fitted) | Mach 1.60 |
| F-15I Ra'am | 0.0509 | 0.195 (the Barak's) | Mach 2.0 at 40,000 ft (F-15E with CFTs, secondary) | Mach 1.20 | Mach 2.00 |

`top_speeds_meet_the_published_figures` pins these within 5 %. The validation rows fly the same jets to their top
speeds (§9.13): within 1 % of the fit.

### 9.16 The trailing-edge flaps (2026-11-11)

The F-16's flaperons are its trailing-edge flaps (TEFs): with the gear handle down they droop together, and the roll
command rides on top. The 6-DoF flies them on every F-16 (Barak, Sufa, TP-1538's) and the Adir; the Ra'am has none: its
δtef stays 0 and its model's flaps follow the flap key (open: an F-15E flap schedule; its flaps have no aerodynamics
on the 6-DoF). On the F-16s and the Adir the game's flap key does nothing: the real jets have no flap lever.

**The schedule** (`jets::tef_schedule`), from the F-16 flight manual[^to-f16cj]:
* gear handle down: 20° down "at all airspeeds below 240 knots"; above 240 kt less, "nearly/fully retracted at 370
  knots" (p. 1-120). Linear between 240 and 370 kt (inferred: the manual gives no shape). The airspeed is the
  equivalent airspeed from q̄ (inferred: calibrated airspeed at the approach heights);
* gear handle up: 0°. The manual says the TEFs are also scheduled by Mach with the handle up (p. 1-120), but gives no
  values: streamlined (inferred). "TEF's retract when the LG handle is raised" (p. 2-21);
* the rate: 20° in 3.1 s, the gear's travel time, since the manual says "LG and TEF retraction occurs simultaneously"
  (p. 2-21; the rate itself inferred). A ground start sets them at 20° (the handle is down; the TO/LDG CONFIG light
  "illuminates on the ground if TEF's are not full down", p. 1-106);
* the Adir: the same schedule (inferred: no public F-35 flap schedule was found; its flaperons droop at low speed).

**The leading-edge flap** stays on TP-1538's appendix A schedule with α and q̄/ps (§9.11), the manual's own
description ("a function of mach number, AOA, and altitude", p. 1-118). Left out: the manual's 2° up with weight on
both main wheels (the tables start at 0°).

**The aerodynamics**: TP-1538 has no δtef data, so the increments come from elsewhere, linear in δtef, at 20°
(`aero::TEF_CL`, `TEF_CD`, `TEF_CM`):

| increment at 20° | value | how |
|---|---|---|
| ΔCL (normal to the flow) | +0.122 | the JSBSim / FlightGear F-16 model's CLtef[^fg-f16] (its source unstated); checked against the manual's approach speeds (§9.17) |
| ΔCD | +0.015 | FM-0's FlapsDragIndex 150 (§4), the same as the JSBSim model's CDtef |
| ΔCm (about 0.35 c̄) | −0.018 (nose down) | the added lift acting 0.15 c̄ behind the reference, less the tail's change in downwash (inferred) |

The control system trims the moment out: a g command, it holds 1 g, and the manual calls the "pitch transients
resulting from LG and TEF changes … mild" (p. 7-2).

**Test** (`flaps_with_the_gear_handle` in `crates/iaf-flight/tests/sixdof.rs`; `tef_increments` in `aero.rs`): a
steady 3° approach at 13° α, sea level, gear down, speed brakes at 43° (the manual's landing configuration), the
Barak at 19,600 lb:

| | flaps up | flaps 20° |
|---|---|---|
| calibrated speed | 138.1 kt | 131.2 kt |
| trimmed CL | 0.974 | 1.083 (+0.109: the stabilator's trim takes 0.013 of the 0.122) |
| stabilator | +1.47° | −0.24° (the flaps' nose-down moment) |

In flight the flaps reach 20° 3.1 s after the handle goes down and are up again 3.1 s after it is raised.

**The manual's approach speed** is checked in §9.17.

### 9.17 The approach speed against the manual (2026-11-11)

**The finding: TP-1538's speed-brake force tables give the speed brake lift.** Table III's ΔCZ,sb (printed p. 58) is
−0.39 at α 0°, −0.27 to −0.42 over α 0–15°: with the speed brake fully open the jet gains more lift than its wing
makes at 5° α. Its ΔCX,sb (p. 51) gives the same speed brake a drag of only 0.01 at α 0°. A split speed brake at the
tail adds drag, not lift. The JSBSim / FlightGear F-16 model[^fg-f16], built on the same tables and the cross-check the
plan names, takes both tables out ("TP 1538 is unreliable in this regard, these numbers makes no sense"; "Mistake in
TP 1538") and flies NASA TN D-8176's speed brake: a drag of 0.05 along the flow, × 0.9333 for the reference area (TN
D-8176 itself not read). The 6-DoF now does the same (`aero::SB_CD` = 0.0467 at 60°, × δsb/60); TP-1538's ΔCm,sb
stays, as in the JSBSim model. The transcription is right: the JSBSim model's copy of the two tables has the same
values.

The approach test flies the speed brake at 43° (the manual's limit with the gear down), so the false lift was +0.25
in CL at 13° α, of the 1.22 the flaps-up approach flew. That was 12 kt of the 23 kt miss (a one-off run at 19,600 lb with the DATCOM flaps: 114.0 kt with the tables,
125.9 kt with the drag).

**The second part: the flaps' lift.** With the speed brake fixed, the DATCOM estimate of the flaps' lift (+0.24,
§9.16 before this change) still left the approach about 9 kt slow at the manual's weights. The JSBSim model's +0.122 (half
of it) is used instead. The other candidates were checked and are not the cause: the leading-edge flap's increment at
13° α (on its schedule, 19°; against the flap up it changes CL by −0.007 at 13° α, a one-off run), the wing area (300 ft², TP-1538 Table I, on both sides of the
equation), the dynamic pressure (sea level, true = calibrated speed), the c.g. (TP-1538's 0.35 c̄, the data's own
reference) and the α definition (TP-1538's α is the body α, and the 6-DoF reads the manual's AOA as body α: inferred).

**The check** (`approach_speed_against_the_manual`): T.O. GR1F-16CJ-1 figure 2-3 (p. 2-25)[^to-f16cj] gives the
13° α final approach for the GE129 engine as C 136 kt, D 138 kt at the basic operating weight plus full ammunition,
+ 4 kt per 1,000 lb of fuel / stores, + 8 kt at 11° α, ±5 kt by c.g. Its gross weights with pilot, oil, full
ammunition and two tip AIM-120 (p. 1-7) are the test's three weights; the two AIM-120 (157 kg each[^aim120]) add
2.8 kt (inferred: the basic operating weight taken without the tip missiles). The test asserts ±5 kt at 13° and at 11° α:

| weight | manual 13° / 11° α | before (speed brake lift, DATCOM flaps) 13° α | now 13° / 11° α |
|---|---|---|---|
| F-16C, 21,000 lb | 138.8 / 146.8 kt | 118.0 kt | 135.8 / 146.3 kt |
| F-16D PX II, 21,600 lb | 140.8 / 148.8 kt | 119.7 kt | 137.7 / 148.4 kt |
| F-16D PX III, 21,900 lb | 140.8 / 148.8 kt | 120.5 kt | 138.6 / 149.4 kt |

(The "before" column scales the 19,600 lb run's 114.0 kt by √(W / 19,600).) In flight the approach at 13° α is
about 20 kt faster than before, and opening the speed brake no longer adds lift: it only slows the jet.

Open: FM-0 (§3) still takes TP-1538's ΔCX,sb at α 5° (0.036) as the speed brake's drag index; the speed brake's 43°
limit with the gear down (§9.6).

### 9.18 Stores drag (2026-11-14)

Every store, rack and tank carries a drag index (`drag` in `modern-iaf/data/db/weapons/*.json`, `rack_drag` in the
units' `allowed` racks). A drag index is 10⁴ × the drag coefficient referenced to the F-16's wing area, and a store's
index is referenced to that area too[^f16net-di]. The game sums them per side (`stores.rs` `init_weight_drag`) and the
6-DoF adds the sum × 10⁻⁴ × 300 ft² / the jet's own wing area as ΔCD along the flow (`Jet::stores_dcd`): a store
costs every jet the same drag force at the same speed. Stores inside the F-35I's bays add none (the unit's
`internal` stations, `loadout::sim_load`'s fifth value).

The F-16 manual's published indices were not at hand, so each index is inferred from the store's sourced diameter:
10⁴ × C × its frontal area / 300 ft², C the installed drag of its shape on that area (inferred): 0.15 a streamlined
tank on its pylon, 0.20 a finned low-drag bomb on its pylon, 0.25 a body with a guidance kit, 0.40 a finned missile on
its rail. A rack counts as one of its stores. The index holds at every Mach (as the original's); a store's own wave
drag above Mach 1 is not modelled. The same `drag` field also feeds the HUD's bomb impact prediction (`bombs.rs`
`predict_impact`, as m/s off the nose, the original's rule), and the falling bomb is solved to meet that point, so
the pipper and the impact stay together.

| store | index | store | index |
|---|---|---|---|
| AIM-9M / AIM-9X | 1.8 | GBU-38 | 5.3 |
| AIM-120 | 3.6 | GBU-39 | 2.5 |
| Python 5 | 2.9 | SPICE 1000 | 8.6 |
| Mk 82 | 4.2 | SPICE 2000 | 14.8 |
| Mk 83 | 6.9 | Delilah | 7.7 |
| Mk 84 | 11.8 | 370 gal tank | 19.1 |
| GBU-31 | 14.9 | 600 gal tank | 26.4 |

Result (`stores_drag_follows_the_drag_index`, tests/sixdof.rs): two 370 gal tanks add the same drag force to all three
jets at 400 kt and 10,000 ft (within 3 %), cut the Sufa's sea-level top speed and raise its cruise fuel flow.

### 9.19 The F-35I's own aerodynamics (finish list F23; plan 2026-11-15, run and tuned 2026-11-16)

The user decided on 2026-11-14: "Infer the f35 (in both games)". No F-35 aerodynamic tables are public, so the Adir
keeps TP-1538's tables on the F-35A's wing (460 ft², 35 ft) and takes what differs from one set,
`iaf_flight::data_set::F35I`, which reborn's F-35I Real row reads too (sources and the full table: docs/f35i.md
§2.1). The source column says sourced (with its footnote), inferred (with the reasoning) or open.

| part | the F-35I set | source | how the 6-DoF uses it |
|---|---|---|---|
| α limit | 50° | sourced: "its 50 degree limit"[^lm-aoa] | `Jet::alpha_max` → `Fcs::with_alpha_max`: the limiter's two branches (15° and 20.4°), the α filter's range (30°), the departure prevention (29°) and the pedals' fade (20–30°) all move up by 50 − 25.2 = 24.8°; the AoA warning (`drag_x`) and the deep-stall flag move with them. The F-16s keep 25.2° (T.O. 1F-16A-1 figure 1-44), so their numbers are unchanged to the bit |
| α feedforward | 0.5 α to the stabilator, α held at 30° | inferred | TP-1538's 0.5 α offsets the F-16's own pitching moment over its α range; carried to 50° it would ask the integrator for 39° of stabilator (its limit is 25°) |
| high-α pitching moment | ΔCm 0 at 30° → −0.20 at 60° and above | inferred | TP-1538's tables lose their nose-down stabilator at 45° (Cm +0.025 at 50° with full nose-down δh +25°: the F-16's deep stall); the F-35A is controllable at its limit. Chosen 2026-11-16 from a sweep (from 20–40°, to 50–70°, −0.10…−0.40, full pulls at 150–400 kt): the first plan, 40° → −0.10 at 50°, overshot to 68° and at 300 kt stayed above 15° for 10 s under full push. This ramp (−0.13 at 50°) holds 50° within the stabilator's nose-up travel and recovers in 3.7–5.5 s. Below 30° the tables are untouched, so the approach keeps TP-1538's lift. Added in `Jet::forces` after `compressibility` |
| α-rate lead | 0.6 s on the limiter's second branch (1 g/deg above 20.4° + shift) | inferred | TP-1538's limiter leads α by the washed-out pitch rate (s/(s + 1)): it fades before the jet has climbed the 35° from 15° to 50°. Without the lead a full pull peaked at 63–68°; with it 50.7–52.2° (sweep of 0–1 s on both branches, 2026-11-16). Only on a jet whose limit is shifted: the F-16s' numbers are unchanged to the bit |
| lift | TP-1538's, no factor | inferred | checked against the approach (next row): within its weight's uncertainty, so no lift factor is fitted. Tried on paper the same day: a c.g. 5 % c̄ forward (the same nose-down margin at 50°) moved the trim at every α and needed the integrator past its limit at 50°: dropped |
| final approach | 152 KCAS at 13° α; 202 KCAS at 5.2° α; at 36,000 lb | sourced: speeds and α[^asf20]; inferred: the weight | `adir_flies_the_f35_figures`: both within 5 % (estimated on paper from the tables: about 147 and 208 kt) |
| 1 g stall | 134 kt at 47,550 lb | inferred: the approach / 1.3, × √(47,550 / 36,000) | `flight::stall_speed` (the slowest trimmed 1 g level flight within the α limit, power off, clean): 128 kt, within the test's 10 % (the lift peaks near 38°, before the 50° limit). The same function measures every 6-DoF jet's stall row in validation since 2026-11-16 (Barak 125, Sufa 136, Ra'am 136 kt; the Ra'am is OFF against its 155 KCAS, open: the F-15E's own lift is not modelled): the 1 s pull it replaced started at 0 m and, since the ground and gear (F1), met the ground (every jet read 60 kt) |
| g limits | +9 / −3 | sourced: +9 (docs/f35i.md §2.1); inferred: −3 (the F-16's) | `Jet::g_limits` |
| roll | 240 deg/s at 688 deg/s², flaperons 62 deg/s | inferred: the F-16's; open: no public F-35 figure | `Jet::roll`: the F-16's production command with its feedforward (§9.11); `f16s_roll_at_the_shared_figure` now flies the Adir too (steady and peak within 5 %, 90° within 1.1 s at 350 kt, 1.0 s at 480 kt: inferred bounds for its inertia) |
| speed brake | the F-16's drag at 60°, no gear-down limit | sourced: the function (docs/f35i.md §2.1); inferred: the drag | finish list F12's `F35_SPEED_BRAKE` (`jets.rs`) |
| top speeds | Mach 1.6 at 40,000 ft | sourced (docs/f35i.md §2.1) | unchanged: the wave-drag fit (§9.15) |
| sustained turn 4.6 g, climb | — | open: the turn's Mach and altitude; no climb figure | not asserted |

Checks the test makes beyond the figures: full pulls at 150, 200, 300 and 400 kt, 10,000 ft, peak, and after 8 s
hold, within 3° of 50°, with |β| under 5° (no departure: TP-1538's Cnβ,dyn stays positive to 55°, worked out
from the tables); a full push then brings α below 15° within 6 s (a centred stick is a 1 g command, so at ~100 kt it rightly
stays near the limit), and a full pull at 550 kt peaks between 8 and 9.5 g. Reborn's model has
no α: it takes the set's g limits, roll and stall floor (the unit test `f35_set_feeds_both_games`).

[^lm-aoa]: Lockheed Martin press release, 19 November 2012, quoted by SLDInfo, "The F-35 and High Angle of Attack
    Flight Testing" ("rapidly expanded its high angle of attack (AOA) test envelope to its 50 degree limit in only four
    flights"), https://sldinfo.com/2012/11/the-f-35-and-high-angle-of-attack-flight-testing/
[^aim-gs]: FAA, *Aeronautical Information Manual*, 1-1-9 "Instrument Landing System (ILS)": the glide path is
    normally set at 3° (cited from memory, not re-read for this change; no download was allowed),
    <https://www.faa.gov/air_traffic/publications/atpubs/aim_html/chap1_section_1.html>
[^asf20]: Air & Space Forces Magazine, "Eglin F-35 Crash Blamed on Landing Speed, but Software, Helmet, Oxygen Also
    Faulted" (2020: "a shallow angle of attack of 5.2 degrees, instead of the desired 13 degrees"; the 202-knot speed
    hold "50 knots too fast"), https://www.airandspaceforces.com/eglin-f-35-crash-blamed-on-landing-speed-but-software-helmet-oxygen-also-faulted/
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
[^umn]: University of Minnesota, Aerospace Engineering and Mechanics, F-16 nonlinear simulation package
    (R. S. Russell, 2003; `F16Simulation.tar.gz`, its high-fidelity data files typed from TP-1538), used only as the
    candidate transcription checked against the scan: https://dept.aem.umn.edu/~balas/darpa_sec/SEC.Software.html
[^stevens-lewis]: B. L. Stevens, F. L. Lewis, *Aircraft Control and Simulation*, 2nd ed., Wiley, 2003, the F-16
    model's trim at 502 ft/s, sea level, c.g. 0.35 c̄ (α 2.1148°, elevator −0.7588°, throttle 0.1385); the book was
    not read, the values as reproduced by SirPicklee/f16-flight-dynamics (GPL-3.0; no code or data taken):
    https://github.com/SirPicklee/f16-flight-dynamics
[^mason-f35]: W. H. Mason, Virginia Tech, AOE 4065 aircraft data, F-35A (wheel track 14.24 ft, wheelbase 19.75 ft;
    the units unlabelled, feet by the overall length 51.41): https://archive.aoe.vt.edu/mason/Mason_f/F35ASpr11.pdf
[^sac-migflug]: USAF Standard Aircraft Characteristics, F-16A Block 1–15 (March 1984): ground roll 3,725 ft at
    intermediate and 2,380 ft at maximum power, 29,253 lb with two AIM-9J and two 370 US gal tanks; as quoted by
    migflug.com, "Fighter Jet Takeoff and Landing: The Real Numbers" (the SAC itself not read):
    https://migflug.com/afterburner/fighter-jet-takeoff-landing-distances-speeds-afterburner-drag-chute/
[^ni-f16]: The National Interest, "What It's Like To Hit the Afterburner in an F-16 for the First Time" (a 150-knot
    rotation in an afterburner take-off; secondary): https://nationalinterest.org/node/175815
[^pw-f100]: Wikipedia, "Pratt & Whitney F100", F100-PW-229 specifications (17,800 lbf military, 29,160 lbf with
    afterburner; citing Pratt & Whitney): https://en.wikipedia.org/wiki/Pratt_%26_Whitney_F100
[^tm4320]: NASA TM-4320 (1991), F-15 with F100 engines: "The engine response is fast, 3 sec from idle to intermediate
    power": https://ntrs.nasa.gov/api/citations/19910020816/downloads/19910020816.pdf
[^w-f135]: Wikipedia, "Pratt & Whitney F135" (28,000 lbf military, 43,000 lbf with afterburner):
    https://en.wikipedia.org/wiki/Pratt_%26_Whitney_F135
[^pw135]: Pratt & Whitney, "Five facts about the most advanced fighter engine in the world" (2019): "The F135 engine
    can go from flight idle to maximum power in about six seconds":
    https://www.rtx.com/prattwhitney/newsroom/news/2019/07/18/five-facts-about-the-most-advanced-fighter-engine-in-the-world
[^lm-f35]: Lockheed Martin, F-35A fact sheet (span 35 ft):
    https://www.lockheedmartin.com/content/dam/lockheed-martin/aero/documents/F-35/f35A.pdf
[^sac-f15]: USAF Standard Aircraft Characteristics, "F-15C Eagle, two F100-PW-220", February 1992 (AFG 2 Vol-1 Addn
    61), wheelbase 17.78 ft, from the alternatewars.com SAC collection (as docs/real-aircraft.md §3).
[^to-f16cj]: T.O. GR1F-16CJ-1, *Flight Manual, HAF Series F-16C/D Block 52+ Aircraft* (Hellenic Air Force): the
    leading-edge flaps p. 1-118, the trailing-edge flaps and the ALT FLAPS switch p. 1-120, the airframe's dimensions
    p. 1-9, the gear handle and the TO/LDG CONFIG light p. 1-106, the take-off p. 2-21, the landing pattern's approach
    speeds figure 2-3 p. 2-25, flight with the gear down pp. 6-3–6-4, the missed approach p. 7-2. <https://falcon.blu3wolf.com/Docs/HAF-F16.pdf>
[^fg-f16]: N. V. Chr., E. Hofman et al., FlightGear F-16 (JSBSim), `Systems/jsb-aerodynamics-block15-subtle.xml`
    (dCx_sb, dCZ_sb from NASA TN D-8176; CLtef, CDtef), GPL-2.0, commit ef4f192f (read from a local clone; only the
    two figures taken): https://github.com/NikolaiVChr/f16
[^aim120]: designation-systems.net, "Raytheon AIM-120 AMRAAM" (AIM-120A/B 157 kg), as cited in docs/real-weapons.md:
    https://www.designation-systems.net/dusrm/m-120.html
[^f16net-di]: F-16.net forum, "Drag index calculation", posts by johnwill, 8 and 10 January 2011 ("A drag index for a
    clean F-16 is the drag coefficient at 0.8 mach using the reference area of the F-16"; "a store drag index is also
    referenced to wing area"): https://www.f-16.net/forum/viewtopic.php?p=188297
[^to-f16a]: T.O. 1F-16A-1, *Flight Manual, F-16A/B Block 10 and 15*, August 2003, p. 2-20 (take-off), p. 2-25 (landing), p. 1-120 /
  1-125 / 1-127 (flight controls), "FLCS limiters" and figures 1-43 / 1-44 (the AOA/g limiter, CAT I / CAT III),
  "MANUAL PITCH Override", "STORES CONFIG Switch", p. 5-3 (over-g), section III / VI (deep stall recovery),
  "Normal flight characteristics", https://archive.org/details/to-1-f-16-a-1-flight-manual-f-16-a-b-block-10-15-august-2003
[^vanpatten]: R. E. van Patten, "G-Lock and the Fighter Jock", *Air Force Magazine*, 1 October 1991 (a modern
  fighter's g limiter lets the pilot "reach a maneuver limit of a bit over nine Gs in about one and a half seconds"):
  https://www.airandspaceforces.com/article/1091glock/
[^plaehn]: T. Plaehn, "Turning and burning", *Land, Fly or Die*, 19 December 2023 (a fighter pilot's account: "the
  F-16A corner velocity expanded to a range of 330 KIAS to 440 KIAS"): https://landflyordie.substack.com/p/turning-and-burning
[^avweb]: M. Busch, "The Savvy Aviator #31: Know Your Oleo", AVweb ("a widely-used rule-of-thumb is that the
  compression ratio of a main-gear oleo strut should be about 4:1 between the fully-extended and static (taxi)
  position, and about 3:1 between the static and fully-compressed position"):
  https://avweb.com/ownership/the-savvy-aviator-31-know-your-oleo/
[^tp1051]: S. M. Stubbs, J. A. Tanner, E. G. Smith, *Behavior of Aircraft Antiskid Braking Systems on Dry and Wet
  Runway Surfaces*, NASA TP-1051, December 1979 (dry runway: maximum drag-force friction coefficient about 0.55,
  fig. 24; braking-behaviour indexes 0.91–0.93; the side force reduced during antiskid braking):
  https://ntrs.nasa.gov/citations/19800003834
[^bms-xwind]: Falcon BMS forum, "Crosswind landings" thread (25 kt, the limit Joe Bill Dryden's tests reached,
  as recalled there by a forum member; secondary): https://forum.falcon-bms.com/post/21564
[^bms]: Falcon BMS forum, "Rotation speed" (rotate at 170 kt with an air-to-air load, 180 kt heavy; the take-off
  speed 70 kt plus 3 kt per 1,000 lb of gross weight), https://forum.falcon-bms.com/post/314659
