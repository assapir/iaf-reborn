//! `iaf-sim fm`: Modern IAF FM-0, the sim's own flight data for the existing flight model
//! (iaf-2026/docs/flight-model.md). Writes `bd.ibx` (`[F-16]` and `[F-15]`) and their envelope files (`f16.dat`,
//! `f15.dat`) into `converted/own/resource/md/`, in the shapes `iaf_flight::load` reads (docs/flight-model.md §1 and
//! §3). Every key is written, so no loader default stands in for airplane data; each line carries its source as a
//! trailing comment. Inputs are only:
//!   * NASA TP-1538 (Nguyen et al. 1979, public domain): Table I (geometry), Table III (CX, CZ at beta = 0, the
//!     leading-edge flap tables, the speed brake), Table VI (thrust), the alpha limiter (25 deg) and the roll-rate
//!     command (308 deg/s) of control system A;
//!   * the public figures already in crates/iaf-flight/src/data_set.rs REAL and docs/f16i.md, f15i.md,
//!     real-aircraft.md;
//!   * "inferred" values, each with its reasoning; "model constant" for the 1998 model's channel gains that have no
//!     airplane counterpart (the loader's built-in value in params.rs, written out).
//!
//! Nothing is read from the original game. The sim's jets fly these sections through data_set.rs: the Barak is
//! "F-16", the Sufa "F-16I" and the F-35I "F-35I" (both on `[F-16]` with their REAL rows), the F-15I "F-15I" (on
//! `[F-15]` with its REAL row).
//!
//! The port of the former `tools/iaf-2026/fm0.py`: its sums are Python's (Neumaier compensated, the [`psum`]), its
//! rounding Python's (ties to even). The test's fixture hashes pin the output.

use std::f64::consts::PI;
use std::path::Path;

use anyhow::{Context, Result};

use crate::progress::Progress;

/// Under the assets root.
pub const MD_DIR: &str = "converted/own/resource/md";

const LBF: f64 = 4.44822; // N
const LB: f64 = 0.45359; // kg
const FT: f64 = 0.3048; // m
const KT: f64 = 0.514722; // m/s
const G0: f64 = 9.806;

// --- NASA TP-1538 -----------------------------------------------------------------------------------------------
// Table VI (U.S. customary units): installed thrust, lbf, at Mach 0.2..1.0 (rows) and 0..50,000 ft (columns).
const TP_MACH: [f64; 5] = [0.2, 0.4, 0.6, 0.8, 1.0];
const TP_ALT_FT: [f64; 6] = [0.0, 10000.0, 20000.0, 30000.0, 40000.0, 50000.0];
type Table = [[f64; 6]; 5];
const TP_IDLE: Table = [
    [635.0, 425.0, 690.0, 1010.0, 1330.0, 1700.0],
    [60.0, 25.0, 345.0, 755.0, 1130.0, 1525.0],
    [-1020.0, -710.0, -300.0, 350.0, 910.0, 1360.0],
    [-2700.0, -1900.0, -1300.0, -247.0, 600.0, 1100.0],
    [-3600.0, -1400.0, -595.0, -342.0, -200.0, 700.0],
];
const TP_MIL: Table = [
    [12680.0, 9150.0, 6313.0, 4040.0, 2470.0, 1400.0],
    [12610.0, 9312.0, 6610.0, 4290.0, 2600.0, 1560.0],
    [12640.0, 9839.0, 7090.0, 4660.0, 2840.0, 1660.0],
    [12390.0, 10176.0, 7750.0, 5320.0, 3250.0, 1930.0],
    [11680.0, 9848.0, 8050.0, 6100.0, 3800.0, 2310.0],
];
const TP_MAX: Table = [
    [21420.0, 15700.0, 11225.0, 7323.0, 4435.0, 2600.0],
    [22700.0, 16860.0, 12250.0, 8154.0, 5000.0, 2835.0],
    [24240.0, 18910.0, 13760.0, 9285.0, 5700.0, 3215.0],
    [26070.0, 21075.0, 15975.0, 11115.0, 6860.0, 3950.0],
    [28886.0, 23319.0, 18300.0, 13484.0, 8642.0, 5057.0],
];
// Table III at beta = 0: alpha (deg), CX, CZ. The base tables CX/CZ(alpha, beta, dh = 0) hold the leading-edge flap at
// 25 deg (Appendix B: the lef increment is weighted by 1 - dlef/25); CX,lef / CZ,lef are the flap retracted.
const LEF_DOWN_25: (f64, f64) = (0.13000, -1.65800);
const LEF_DOWN_15: (f64, f64) = (0.10720, -1.11200);
const LEF_DOWN_M10: (f64, f64) = (-0.09820, 0.69200);
const TP_LEF_UP: [(f64, (f64, f64)); 3] =
    [(0.0, (-0.02020, -0.10000)), (5.0, (-0.00330, -0.42800)), (10.0, (0.00990, -0.77400))];
const TP_DCX_SB_A5: f64 = -0.03580; // Table III, delta CX,sb(alpha = 5 deg), speed brake 60 deg
const TP_SPAN_FT: f64 = 30.0; // Table I
const TP_AREA_FT2: f64 = 300.0;
const TP_ALPHA_LIMIT: f64 = 25.0; // the alpha limiter (text, "limit the angle of attack to below 25 deg")
const TP_ROLL_CMD: f64 = 308.0; // deg/s, control system A's maximum commanded roll rate

const STEP_FT: i64 = 5000;
const CEIL_CAP_FT: i64 = 65000; // the model's atmosphere and thrust table stop at 20 km (65,617 ft)

/// Python's `sum()` of floats (3.12 on): Neumaier's compensated sum.
fn psum(it: impl IntoIterator<Item = f64>) -> f64 {
    let (mut f, mut c) = (0.0f64, 0.0f64);
    for x in it {
        let t = f + x;
        c += if f.abs() >= x.abs() { (f - t) + x } else { (x - t) + f };
        f = t;
    }
    if c != 0.0 && c.is_finite() { f + c } else { f }
}

/// Body-axis (CX forward, CZ down) to wind-axis lift and drag.
fn cl_cd((cx, cz): (f64, f64), alpha_deg: f64) -> (f64, f64) {
    let a = alpha_deg * (PI / 180.0);
    (cx * a.sin() - cz * a.cos(), -cx * a.cos() - cz * a.sin())
}

// --- the flight model's own formulas (docs/flight-model.md §2, §4.1, §4.3) ---------------------------------------
/// Density and speed of sound at `alt_m`.
fn air(alt_m: f64) -> (f64, f64) {
    let alt = alt_m.clamp(-500.0, 20000.0);
    let h = (1.0 - alt * 1.5731270e-7) * alt;
    let (t, p) = if h <= 11000.0 {
        let t = 288.15 - 0.0065 * h;
        (t, (t / 288.15).powf(5.255876) * 10332.27)
    } else {
        let t: f64 = 216.65;
        (t, (t / 288.15).powf(5.255876) * 10332.27 * ((alt - 11000.0) * (-0.03404 / t)).exp())
    };
    (1.225 * (p / 10332.27) / (t / 288.15), (401.8743 * t).sqrt())
}

/// The model's thrust table: corners c = [SL M0, 20 km M0, SL M1.2, 20 km M1.2], a = alt / 20 km, m = Mach / 1.2.
fn bilinear(c: &[f64; 4], a: f64, m: f64) -> f64 {
    let (a, m) = (a.clamp(0.0, 1.0), m.clamp(0.0, 1.0));
    (c[0] * (1.0 - a) + c[1] * a) * (1.0 - m) + (c[2] * (1.0 - a) + c[3] * a) * m
}

type Row = ([f64; 2], f64);

/// Least squares of t = x0 c0 + x1 c1 over rows ((x0, x1), t), with c0 >= lo[0] and c1 >= lo[1]: the unconstrained
/// solution if it is inside the bounds, else the best of the solutions with one or both on their bound.
fn lsq2(rows: &[Row], lo: [f64; 2]) -> [f64; 2] {
    let sse = |c: [f64; 2]| psum(rows.iter().map(|(x, t)| (x[0] * c[0] + x[1] * c[1] - t).powi(2)));
    // The best c_i with the other coefficient fixed.
    let one = |i: usize, fixed: f64| {
        let j = 1 - i;
        let den = psum(rows.iter().map(|(x, _)| x[i] * x[i]));
        psum(rows.iter().map(|(x, t)| x[i] * (t - x[j] * fixed))) / den
    };
    let s = |f: &dyn Fn(&Row) -> f64| psum(rows.iter().map(f));
    let (s00, s01, s11) = (s(&|(x, _)| x[0] * x[0]), s(&|(x, _)| x[0] * x[1]), s(&|(x, _)| x[1] * x[1]));
    let (b0, b1) = (s(&|(x, t)| x[0] * t), s(&|(x, t)| x[1] * t));
    let det = s00 * s11 - s01 * s01;
    let free = [(b0 * s11 - b1 * s01) / det, (s00 * b1 - s01 * b0) / det];
    let cands = [free, [lo[0], one(1, lo[0])], [one(0, lo[1]), lo[1]], lo];
    // Python's min(key=): the first of the smallest (a NaN key never wins over an earlier one).
    let mut best: Option<([f64; 2], f64)> = None;
    for c in cands.into_iter().filter(|c| c[0] >= lo[0] - 1e-9 && c[1] >= lo[1] - 1e-9) {
        let e = sse(c);
        if best.is_none_or(|(_, b)| e < b) {
            best = Some((c, e));
        }
    }
    best.expect("a candidate").0
}

/// The model's bilinear corners from a TP-1538 thrust table in two steps: the sea-level corners by least squares on
/// the sea-level row (take-off and climb exact), then the 20 km corners by least squares of the relative error over
/// the other altitudes (each point divided by its thrust, so 50,000 ft counts as much as 10,000 ft; idle, which
/// crosses zero, by the absolute error), each 20 km corner at least `floor` (Mach 0, Mach 1.2).
fn fit_corners(table: &Table, relative: bool, floor: Option<[f64; 2]>) -> [f64; 4] {
    let free = [f64::NEG_INFINITY; 2];
    let m_of = TP_MACH.map(|mach| mach / 1.2);
    let sl: Vec<Row> = m_of.iter().enumerate().map(|(i, &m)| ([1.0 - m, m], table[i][0])).collect();
    let [c0, c2] = lsq2(&sl, free);
    let mut rows = Vec::new();
    for (i, &m) in m_of.iter().enumerate() {
        for (j, alt_ft) in TP_ALT_FT.iter().enumerate().skip(1) {
            let (a, t) = (alt_ft * FT / 20000.0, table[i][j]);
            let fixed = (1.0 - a) * ((1.0 - m) * c0 + m * c2);
            let w = if relative { t } else { 1.0 };
            rows.push(([a * (1.0 - m) / w, a * m / w], (t - fixed) / w));
        }
    }
    let [c1, c3] = lsq2(&rows, floor.unwrap_or(free));
    [c0, c1, c2, c3]
}

/// Worst relative error of corners c against a TP-1538 table, per altitude (0..50,000 ft).
fn fit_errors(c: &[f64; 4], table: &Table) -> Vec<f64> {
    (0..TP_ALT_FT.len())
        .map(|j| {
            TP_MACH
                .iter()
                .zip(table)
                .map(|(m, row)| (bilinear(c, TP_ALT_FT[j] * FT / 20000.0, m / 1.2) / row[j] - 1.0).abs())
                .fold(f64::NEG_INFINITY, f64::max)
        })
        .collect()
}

/// The three fits: max, military, idle (unscaled corners).
struct Fits {
    max: [f64; 4],
    mil: [f64; 4],
    idle: [f64; 4],
}

impl Fits {
    /// The 20 km corners may not go below zero: a table linear in altitude that follows TP-1538 to 50,000 ft would
    /// need negative thrust at 20 km. At the bound (zero for both max and military) the model's idle there is zero
    /// too, so thrust stays >= 0 and full AB >= military >= idle at every altitude, at the cost of too much thrust
    /// aloft (logged). Idle's own fit puts positive values at 20 km; they are held at the max corners' (zero) so full
    /// AB never gives less than idle there.
    fn new() -> Self {
        let max = fit_corners(&TP_MAX, true, Some([0.0, 0.0]));
        let mil = fit_corners(&TP_MIL, true, Some([0.0, 0.0]));
        let mut idle = fit_corners(&TP_IDLE, false, None);
        for i in [1, 3] {
            if max[i] < idle[i] {
                idle[i] = max[i];
            }
        }
        Fits { max, mil, idle }
    }
}

/// The lift coefficients: TP-1538's at the alpha limit, flap down (the F-16 schedules the leading-edge flap fully
/// down at high alpha), and the F-15E's at its published stall: 155 KCAS, power off, flaps up, 59,665 lb
/// (TO 1F-15E-1 via data_set.rs REAL).
struct Lift {
    cl25: f64,
    cl15: f64,
    clneg: f64,
    f15: f64,
}

impl Lift {
    fn new() -> Self {
        Lift {
            cl25: cl_cd(LEF_DOWN_25, 25.0).0,
            cl15: cl_cd(LEF_DOWN_15, 15.0).0,
            clneg: cl_cd(LEF_DOWN_M10, -10.0).0,
            f15: 2.0 * 59665.0 * LB * G0 / (1.225 * 608.0 * FT * FT * (155.0 * KT).powi(2)),
        }
    }
}

/// One section's public figures and sources.
struct Spec {
    name: &'static str,
    section: &'static str,
    file: &'static str,
    /// The note added to the values a jet takes from the F-16's TP-1538 data ("" for the F-16 itself).
    borrowed: &'static str,
    empty_lb: f64,
    fuel_lb: f64,
    span_ft: f64,
    area_ft2: f64,
    cd0: Option<f64>,
    ab_lbf: f64,
    mil_lbf: f64,
    cl_max: f64,
    cl_neg: f64,
    g_min: i64,
    g_max: i64,
    cl_src: &'static str,
    area_src: &'static str,
    span_src: &'static str,
    cd0_src: &'static str,
}

/// One section: the thrust table, K, CD0 and the envelope derived from its [`Spec`].
struct Jet {
    s: Spec,
    t_max: [f64; 4],
    t_mil: [f64; 4],
    t0: [f64; 4],
    k: f64,
    cd0: f64,
    w: f64,
    area: f64,
}

impl Jet {
    fn new(s: Spec, fits: &Fits) -> Self {
        // Thrust: TP-1538's shape, scaled so the SL static corners are the engine's public ratings.
        let t_max = fits.max.map(|c| c * s.ab_lbf / fits.max[0]);
        let t_mil = fits.mil.map(|c| c * s.mil_lbf / fits.mil[0]);
        // Idle: no public rating; the engine's max scale (inferred).
        let t_idle = fits.idle.map(|c| c * s.ab_lbf / fits.max[0]);
        // The model's "0" corner: idle is k = 0.05 and military k = 0.6 of the way from "0" to "1" (flight-model.md
        // §4.1); one value serves both: least squares of the two settings (the exact-military fit, tested and dropped
        // 2026-11-02, made idle a brake in flight: iaf-2026/docs/flight-model.md §3).
        let t0: [f64; 4] = std::array::from_fn(|n| {
            let (i, mil, mx) = (t_idle[n], t_mil[n], t_max[n]);
            (0.95 * (i - 0.05 * mx) + 0.4 * (mil - 0.6 * mx)) / (0.95f64.powi(2) + 0.4f64.powi(2))
        });
        assert!(t0.iter().zip(&t_max).all(|(t0, t1)| 0.95 * t0 + 0.05 * t1 <= *t1), "idle above full AB");
        let k = 1.0 / (PI * s.span_ft.powi(2) / s.area_ft2 * 0.85);
        // CD0 with the model's K: the mean of CD - K CL^2 over TP-1538's flap-up points at 0 and 5 deg.
        let cd0 = s.cd0.unwrap_or_else(|| {
            psum(TP_LEF_UP[..2].iter().map(|&(a, cxz)| {
                let (cl, cd) = cl_cd(cxz, a);
                cd - k * cl * cl
            })) / 2.0
        });
        let w = (s.empty_lb + s.fuel_lb) * LB * G0;
        let area = s.area_ft2 * FT * FT;
        Jet { s, t_max, t_mil, t0, k, cd0, w, area }
    }

    /// The model's idle thrust (lbf): k = 0.05 on each corner's line.
    fn idle(&self, alt_m: f64, mach: f64) -> f64 {
        let c = std::array::from_fn(|n| 0.95 * self.t0[n] + 0.05 * self.t_max[n]);
        bilinear(&c, alt_m / 20000.0, mach / 1.2)
    }

    fn vmin(&self, alt_m: f64, g: f64) -> f64 {
        let cl = if g >= 0.0 { self.s.cl_max } else { -self.s.cl_neg };
        (2.0 * g.abs() * self.w / (air(alt_m).0 * self.area * cl)).sqrt()
    }

    /// Best thrust - drag (N) at full AB for load factor g over Vmin..Mach 1.0 (TP-1538's thrust range).
    fn excess(&self, alt_m: f64, g: f64) -> f64 {
        let (rho, a) = air(alt_m);
        let mut best = -1e30;
        for i in 0..=100 {
            let mach = 0.1 + 0.9 * i as f64 / 100.0;
            let v = mach * a;
            if v < self.vmin(alt_m, g) {
                continue;
            }
            let qs = 0.5 * rho * v * v * self.area;
            let cl = g.abs() * self.w / qs;
            let drag = (self.cd0 + self.k * cl * cl) * qs;
            let e = bilinear(&self.t_max, alt_m / 20000.0, mach / 1.2) * LBF - drag;
            if e > best {
                best = e;
            }
        }
        best
    }

    /// Highest altitude (100 ft steps) with thrust >= drag at g: bisection, as the excess falls with height.
    fn ceiling_ft(&self, g: i64) -> i64 {
        let g = g as f64;
        if g == 0.0 || self.excess(CEIL_CAP_FT as f64 * FT, g) >= 0.0 {
            return CEIL_CAP_FT;
        }
        let (mut lo, mut hi) = (0, CEIL_CAP_FT / 100); // excess >= 0 at lo (sea level), < 0 at hi
        while hi - lo > 1 {
            let mid = (lo + hi) / 2;
            if self.excess((mid * 100) as f64 * FT, g) >= 0.0 {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        lo * 100
    }

    /// The envelope file and the ceiling per g.
    fn envelope(&self) -> (String, Vec<(i64, i64)>) {
        let s = &self.s;
        let mut lines = vec![
            "[Params]".to_string(),
            format!("; {}: own envelope (iaf-sim fm). Units are knots and feet.", s.name),
            "; Vmin = sqrt(2 g W / (rho S CL)),".into(),
            format!("; W = {:.0} lb (empty + internal fuel),", s.empty_lb + s.fuel_lb),
            format!("; CL {:.3} / {:.3} ({});", s.cl_max, s.cl_neg, s.cl_src),
            "; g = 0: the 0.1 g speed (the format needs rising speeds; inferred).".into(),
            "; Ceiling per g: thrust = drag at full AB, Mach <= 1.0 (TP-1538's range).".into(),
            format!("NumberOfG-Graphs={}", s.g_max - s.g_min + 1),
            format!("AltitudeStep = {STEP_FT}"),
            String::new(),
            "[Min Velocity Table]".into(),
            "; g\tVel\tAlt".into(),
        ];
        let mut ceilings = Vec::new();
        for g in s.g_min..=s.g_max {
            let top = self.ceiling_ft(g);
            ceilings.push((g, top));
            for alt in (0..top).step_by(STEP_FT as usize).chain([top]) {
                let v = self.vmin(alt as f64 * FT, if g != 0 { g as f64 } else { 0.1 }) / KT;
                lines.push(format!("{g}\t{}\t{alt}", v.round_ties_even().max(1.0)));
            }
            lines.push(String::new());
        }
        (lines.join("\r\n") + "\r\n", ceilings)
    }
}

/// Python's `:g` for the figures written here (none needs an exponent).
fn g(v: f64) -> String {
    format!("{v}")
}

fn section(j: &Jet, keys: &[(&str, String, String)]) -> Vec<String> {
    let mut out = vec![
        format!("[{}]", j.s.section),
        format!("; {} -- Modern IAF FM-0, sources in iaf-2026/docs/flight-model.md", j.s.name),
        "Model = 6dof\t; the sim flies its own 6-DoF (crates/iaf-flight/src/sixdof, iaf-2026/docs/flight-model.md §9); \
         the keys below serve its instruments, the autopilot's envelope and the original model as a fallback"
            .into(),
    ];
    for (key, value, src) in keys {
        out.push(format!("{key} = {value}\t; {src}"));
    }
    for (n, name) in ["MinMachMinAlt", "MinMachMaxAlt", "MaxMachMinAlt", "MaxMachMaxAlt"].iter().enumerate() {
        out.push(format!(
            "Thrust{name}0 = {:.1}\t; TP-1538 Table VI fit (k = 0: idle / military least squares), scaled",
            j.t0[n]
        ));
        out.push(format!(
            "Thrust{name}1 = {:.1}\t; TP-1538 Table VI fit (max), scaled to {:.0} lbf SL static",
            j.t_max[n], j.s.ab_lbf
        ));
    }
    out.push(format!("FlightEnvelopeFile = {}\t; iaf-sim fm", j.s.file));
    out
}

/// A jet's roll rate, roll acceleration and g limits, each with its source.
struct Handling {
    roll: f64,
    roll_src: &'static str,
    accel: f64,
    accel_src: &'static str,
    g: (f64, f64),
    g_src: &'static str,
}

fn common(j: &Jet, h: &Handling, lift: &Lift) -> Vec<(&'static str, String, String)> {
    let model = "model constant";
    let b = j.s.borrowed;
    let kv = |k: &'static str, v: &str, s: &str| (k, v.to_string(), s.to_string());
    vec![
        kv("WingArea", &g(j.s.area_ft2), j.s.area_src),
        kv("WingSpan", &g(j.s.span_ft), j.s.span_src),
        kv("MaxRollRate", &g(h.roll), h.roll_src),
        kv("RollAccel", &g(h.accel), h.accel_src),
        kv("StopAccel", &g(h.accel), h.accel_src),
        kv("MaxBeta", "10", model),
        kv("BetaRate", "10", model),
        kv("MaxG", &g(h.g.0), h.g_src),
        kv("MinG", &g(h.g.1), h.g_src),
        kv("G_Rate", "5", &format!("{model} (the real g onset rate: open)")),
        kv("G_RateForAoa", "1", model),
        kv("PlaneDragIndex", &format!("{:.0}", j.cd0 * 1e4), j.s.cd0_src),
        kv(
            "SpeedBrakesDragIndex",
            &format!("{:.0}", -TP_DCX_SB_A5 * 1e4),
            &format!("TP-1538 Table III dCX,sb at alpha 5 deg, 60 deg brake{b}"),
        ),
        kv("LandingGearDragIndex", "200", "inferred: gear dCD 0.02 (no public figure)"),
        kv("FlapsDragIndex", "150", "inferred: trailing-edge flap dCD 0.015 (no public figure)"),
        kv("FlapsLiftCoef", "0.1", "inferred: flaps add ~10 % lift (no public figure)"),
        kv("LandingHookDragIndex", "10", "inferred: hook dCD 0.001"),
        kv("WheelsBrakeDragIndex", "4000", "inferred: braking friction 0.4, a dry runway"),
        kv("HasAfterBurner", "1", "fact"),
        kv(
            "StartVibsG",
            &format!("{:.2}", lift.cl25 / lift.cl15),
            &format!("TP-1538: buffet from alpha 15 deg; CL(25) / CL(15){b}"),
        ),
        kv("UseFlightLimits", "1", "fact (the envelope limits g)"),
        kv("MaxNegAlpha", "-10", "inferred (open; TP-1538's data reach -20)"),
        kv("MaxPosAlpha", &g(TP_ALPHA_LIMIT), &format!("TP-1538 alpha limiter{b}")),
        kv("LimitAlphaVisual", "15", &format!("{model} (the shown alpha's limit)")),
        kv("MaxAlphaRate", "2.5", model),
        kv("AlphaStopAccel", "0.1", model),
        kv("AlphaStartAccel", "0.5", model),
        kv("AlphaK", "8", model),
        kv("AlphaBeta", "0.1", model),
        kv("RudderK", "5", model),
        kv("RudderBeta", "0", model),
        kv("RudderStartAccel", "0.5", model),
        kv("RudderStopAccel", "0.5", model),
        kv("StartMoveStickCenterG", "2", model),
        kv("MapCenterStick", "0", model),
        // The call needs g > OverGThresh, and g stops at MaxG.
        kv("OverGThresh", &g(h.g.0 - 0.5), "inferred: Betty's over-G call 0.5 g before the limit"),
    ]
}

fn jets(fits: &Fits, lift: &Lift) -> (Jet, Jet) {
    let f16 = Spec {
        name: "F-16D Block 40 Barak (F110-GE-100), TP-1538 aerodynamics",
        section: "F-16",
        file: "f16.dat",
        borrowed: "",
        empty_lb: 19100.0,
        fuel_lb: 5800.0,
        span_ft: TP_SPAN_FT,
        area_ft2: TP_AREA_FT2,
        cd0: None,
        ab_lbf: 29000.0,
        mil_lbf: 29000.0 * 0.59,
        cl_max: lift.cl25,
        cl_neg: lift.clneg,
        g_min: -3,
        g_max: 9,
        cl_src: "TP-1538 at alpha 25 / -10 deg, flap down",
        area_src: "TP-1538 Table I",
        span_src: "TP-1538 Table I",
        cd0_src: "TP-1538 Table III flap up, mean CD - K CL^2 at alpha 0 / 5 deg (K from span / area)",
    };
    let f15 = Spec {
        name: "F-15I Ra'am (F-15E figures, 2 x F100-PW-229)",
        section: "F-15",
        file: "f15.dat",
        borrowed: " (the F-16's TP-1538 value; the F-15's is open, inferred)",
        empty_lb: 37000.0,
        fuel_lb: 22665.0,
        span_ft: 42.8,
        area_ft2: 608.0,
        cd0: Some(0.042),
        ab_lbf: 2.0 * 29160.0,
        mil_lbf: 2.0 * 17800.0,
        cl_max: lift.f15,
        cl_neg: lift.f15 * lift.clneg / lift.cl25,
        g_min: -2,
        g_max: 8,
        cl_src: "F-15E stall 155 KCAS at 59,665 lb; negative: TP-1538's ratio, inferred",
        area_src: "Wikipedia F-15E (608 ft2)",
        span_src: "USAF F-15E fact sheet (42.8 ft)",
        cd0_src: "data_set.rs REAL F-15I cd0 (fitted value: the F-15C row's 0.040 + the CFTs' drag number 20.1)",
    };
    (Jet::new(f16, fits), Jet::new(f15, fits))
}

fn bd_ibx(f16: &Jet, f15: &Jet, lift: &Lift) -> String {
    let kv = |k: &'static str, v: &str, s: &str| (k, v.to_string(), s.to_string());
    let mut a = vec![
        kv("EmptyWeight", "19100", "F-16D, aero-web.org (data_set.rs REAL F-16)"),
        kv("MaxWeight", "42300", "Block 50/52 42,300 lb (f-16.net, docs/f16i.md); the Block 40 shares it (inferred)"),
        kv("FuelWeight", "5800", "F-16D 870.4 US gal (f-16.net, data_set.rs REAL F-16)"),
        kv("FuelFlowAtMaxThrust", "16.5", "~60,000 lb/h at full AB (data_set.rs REAL F-16)"),
    ];
    let h16 = Handling {
        roll: TP_ROLL_CMD,
        roll_src: "TP-1538 control system A's roll command",
        accel: 900.0,
        accel_src: "FLCS roll time constant ~0.3 s (data_set.rs REAL F-16)",
        g: (9.0, -3.0),
        g_src: "+9 (USAF F-16 fact sheet); -3 inferred (open)",
    };
    a.extend(common(f16, &h16, lift));
    let mut b = vec![
        kv("EmptyWeight", "37000", "F-15E operating weight with CFTs, TO 1F-15E-1 (data_set.rs REAL F-15I)"),
        kv("MaxWeight", "81000", "F-15E, TO 1F-15E-1 / USAF fact sheet (data_set.rs REAL F-15I)"),
        kv("FuelWeight", "22665", "F-15E 12,915 + 2 x 4,875 lb CFTs (data_set.rs REAL F-15I)"),
        kv(
            "FuelFlowAtMaxThrust",
            &format!("{:.2}", 113100.0 / 3600.0),
            "2 x F100-PW-229 at TSFC 1.94, inferred (data_set.rs REAL)",
        ),
    ];
    let h15 = Handling {
        roll: 200.0,
        roll_src: "inferred: the middle of 180-220 deg/s (docs/real-aircraft.md; open)",
        accel: 670.0,
        accel_src: "inferred: the F-16 row's 0.3 s roll time constant",
        g: (8.1, -2.0),
        g_src: "F-15E with CFTs, OWS off, TO 1F-15E-1 fig. 5-7 (data_set.rs REAL F-15I)",
    };
    b.extend(common(f15, &h15, lift));
    let mut lines = vec![
        "; Modern IAF FM-0 flight data, written by iaf-sim fm from NASA TP-1538 and public figures".into(),
        "; (iaf-2026/docs/flight-model.md). Units: lb, ft, deg.".into(),
        String::new(),
    ];
    lines.extend(section(f16, &a));
    lines.push(String::new());
    lines.extend(section(f15, &b));
    lines.join("\r\n") + "\r\n"
}

/// The files (name, Latin-1 bytes) and the report lines.
pub fn build() -> (Vec<(&'static str, Vec<u8>)>, Vec<String>) {
    let latin1 = |s: String| s.chars().map(|c| u8::try_from(c as u32).expect("a Latin-1 character")).collect();
    let (fits, lift) = (Fits::new(), Lift::new());
    let (f16, f15) = jets(&fits, &lift);
    let mut files = vec![("bd.ibx", latin1(bd_ibx(&f16, &f15, &lift)))];
    let list = |v: &[f64]| v.iter().map(|c| format!("{}", c.round_ties_even())).collect::<Vec<_>>().join(", ");
    let mut log = vec![format!(
        "TP-1538 thrust fit (unscaled corners SL M0, 20 km M0, SL M1.2, 20 km M1.2): max [{}], military [{}]",
        list(&fits.max),
        list(&fits.mil)
    )];
    for (name, fit, table) in [("max", &fits.max, &TP_MAX), ("military", &fits.mil, &TP_MIL)] {
        let e: Vec<_> = fit_errors(fit, table).iter().map(|e| format!("{:+.0}%", e * 100.0)).collect();
        log.push(format!("  {name}, worst error per altitude 0..50,000 ft: {}", e.join(", ")));
    }
    let row = |f: &dyn Fn(f64, usize) -> f64| {
        TP_MACH.iter().enumerate().map(|(i, &m)| format!("{:.0}", f(m, i))).collect::<Vec<_>>().join(", ")
    };
    let scale = f16.s.ab_lbf / fits.max[0];
    let mil: [f64; 4] = std::array::from_fn(|n| 0.4 * f16.t0[n] + 0.6 * f16.t_max[n]);
    log.push(format!(
        "  idle at sea level, Mach 0.2..1.0, F-16 (lbf): model {}; TP-1538 x the max scale {}",
        row(&|m, _| f16.idle(0.0, m)),
        row(&|_, i| TP_IDLE[i][0] * scale)
    ));
    log.push(format!(
        "  military at sea level, Mach 0.2..1.0, F-16 (lbf): model {}; TP-1538 x the military scale {}",
        row(&|m, _| bilinear(&mil, 0.0, m / 1.2)),
        row(&|_, i| TP_MIL[i][0] * f16.s.mil_lbf / fits.mil[0])
    ));
    for &(a, cxz) in &TP_LEF_UP {
        let (cl, cd) = cl_cd(cxz, a);
        let model = f16.cd0 + f16.k * cl * cl;
        log.push(format!("TP-1538 flap up alpha {a:2}: CL {cl:.3} CD {cd:.4}; model CD0 + K CL^2 = {model:.4}"));
    }
    log.push(format!(
        "CL at alpha 25 (flap down) {:.3}, at 15 {:.3}, at -10 {:.3}; F-15E stall CL {:.3}",
        lift.cl25, lift.cl15, lift.clneg, lift.f15
    ));
    for j in [&f16, &f15] {
        let (text, ceil) = j.envelope();
        files.push((j.s.file, latin1(text)));
        let corners: Vec<_> = (0..4)
            .map(|n| {
                let (t0, t1) = (j.t0[n], j.t_max[n]);
                format!("{:.0} / {:.0} / {:.0}", 0.95 * t0 + 0.05 * t1, 0.4 * t0 + 0.6 * t1, t1)
            })
            .collect();
        let ceil: Vec<_> = ceil.iter().map(|(g, c)| format!("{g}g {c}")).collect();
        log.push(format!(
            "[{}] CD0 {:.4}, K {:.3}, 1 g stall {:.0} kt, thrust SL static {:.0} / {:.0} lbf, model idle / military / \
             max at the corners {}, ceilings (ft) {}",
            j.s.section,
            j.cd0,
            j.k,
            j.vmin(0.0, 1.0) / KT,
            j.t_mil[0],
            j.t_max[0],
            corners.join(", "),
            ceil.join(", ")
        ));
    }
    (files, log)
}

/// `iaf-sim fm`: the files into `<assets>/MD_DIR`, the derived numbers into the log.
pub fn fm(assets: &Path, pr: &dyn Progress) -> Result<()> {
    let out = assets.join(MD_DIR);
    std::fs::create_dir_all(&out).with_context(|| format!("{}", out.display()))?;
    let (files, log) = build();
    for line in &log {
        pr.log(line);
    }
    for (name, bytes) in files {
        let p = out.join(name);
        std::fs::write(&p, bytes).with_context(|| format!("{}", p.display()))?;
    }
    pr.log(&format!("wrote {}/bd.ibx, f16.dat, f15.dat", out.display()));
    Ok(())
}

#[cfg(test)]
mod tests {
    use sha2::{Digest, Sha256};

    /// The SHA-256 of the output. Until commit 1c610001 the output equalled Python 3.14.9's output of the former
    /// fm0.py byte for byte; then the files' comments changed from naming fm0.py to naming `iaf-sim fm`.
    const FIXTURE: [(&str, &str); 3] = [
        ("bd.ibx", "00d39709919ab37590765d51c068be706ca06f90ccf6eb42013b85517b5bb6e7"),
        ("f16.dat", "7b9e749a72d6acdd600e44c16c73eedfd8b15a0606c4b956417eea7efce7b582"),
        ("f15.dat", "7d38a9dc784f552cae638f22113a141bc490011ab6a0b92b6ab5df6579586837"),
    ];

    #[test]
    fn output_matches_fixture() {
        let (files, _) = super::build();
        let got: Vec<_> = files.iter().map(|(n, b)| (*n, format!("{:x}", Sha256::digest(b)))).collect();
        for ((name, want), (n, hash)) in FIXTURE.iter().zip(&got) {
            assert_eq!((name, *want), (n, hash.as_str()), "{name} differs from the fixture");
        }
        // Both sections (the Barak, Sufa and F-35I fly [F-16], the F-15I [F-15]).
        let bd = String::from_utf8_lossy(&files[0].1);
        assert!(bd.contains("[F-16]\r\n") && bd.contains("[F-15]\r\n"));
    }
}
