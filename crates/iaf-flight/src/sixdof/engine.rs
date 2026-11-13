//! The jets' engines: TP-1538's powerplant model (figure 66, printed pp. 218–220) over its thrust table (Table VI,
//! printed p. 93), each engine scaled to its public ratings and spool time (modern-iaf/docs/flight-model.md §9.7).

use super::body::{MAX_FRAME, MAX_STEP};
use crate::atmosphere::air;
use crate::units::{FT, LBF, SLUG_FT2};

/// TP-1538 Table VI (U.S. customary units): installed thrust (lbf) of the simulation's F-16 engine (the
/// F100-PW-200) at Mach 0.2…1.0 (rows) and 0…50,000 ft (columns): idle, military, maximum.
const MACH: [f64; 5] = [0.2, 0.4, 0.6, 0.8, 1.0];
const ALT_FT: [f64; 6] = [0.0, 10_000.0, 20_000.0, 30_000.0, 40_000.0, 50_000.0];
const T_IDLE: [[f64; 6]; 5] = [
    [635.0, 425.0, 690.0, 1010.0, 1330.0, 1700.0],
    [60.0, 25.0, 345.0, 755.0, 1130.0, 1525.0],
    [-1020.0, -710.0, -300.0, 350.0, 910.0, 1360.0],
    [-2700.0, -1900.0, -1300.0, -247.0, 600.0, 1100.0],
    [-3600.0, -1400.0, -595.0, -342.0, -200.0, 700.0],
];
const T_MIL: [[f64; 6]; 5] = [
    [12680.0, 9150.0, 6313.0, 4040.0, 2470.0, 1400.0],
    [12610.0, 9312.0, 6610.0, 4290.0, 2600.0, 1560.0],
    [12640.0, 9839.0, 7090.0, 4660.0, 2840.0, 1660.0],
    [12390.0, 10176.0, 7750.0, 5320.0, 3250.0, 1930.0],
    [11680.0, 9848.0, 8050.0, 6100.0, 3800.0, 2310.0],
];
const T_MAX: [[f64; 6]; 5] = [
    [21420.0, 15700.0, 11225.0, 7323.0, 4435.0, 2600.0],
    [22700.0, 16860.0, 12250.0, 8154.0, 5000.0, 2835.0],
    [24240.0, 18910.0, 13760.0, 9285.0, 5700.0, 3215.0],
    [26070.0, 21075.0, 15975.0, 11115.0, 6860.0, 3950.0],
    [28886.0, 23319.0, 18300.0, 13484.0, 8642.0, 5057.0],
];

/// A Table VI value (lbf) at `mach`, `alt_ft`: bilinear; below Mach 0.2 the line through Mach 0.2 and 0.4 carried
/// to Mach 0, above Mach 1.0 the line through Mach 0.8 and 1.0 carried to Mach 2.0 (the ram rise continued) and held
/// beyond; above 50,000 ft the 50,000 ft value × the density ratio (all three inferred: the table's range ends
/// there).
fn table(t: &[[f64; 6]; 5], mach: f64, alt_ft: f64) -> f64 {
    let at_alt = |row: &[f64; 6]| {
        if alt_ft >= ALT_FT[5] {
            let ratio = air((alt_ft * FT) as f32).rho as f64 / air((ALT_FT[5] * FT) as f32).rho as f64;
            return row[5] * ratio;
        }
        let a = alt_ft.max(0.0);
        let j = ((a / 10_000.0) as usize).min(4);
        let f = (a - ALT_FT[j]) / 10_000.0;
        row[j] * (1.0 - f) + row[j + 1] * f
    };
    let m = mach.clamp(0.0, 2.0);
    let i = if m < 0.4 { 0 } else { (((m - 0.2) / 0.2) as usize).min(3) };
    let f = (m - MACH[i]) / 0.2;
    at_alt(&t[i]) * (1.0 - f) + at_alt(&t[i + 1]) * f
}

/// Figure 66(c): 1/τ (1/s) for an incremental power command `dp` (percent power).
fn rtau(dp: f64) -> f64 {
    if dp <= 25.0 {
        1.0
    } else if dp >= 50.0 {
        0.1
    } else {
        1.9 - 0.036 * dp
    }
}

/// Figure 66(b): commanded power (percent: 0 idle, 50 military, 100 maximum) at a throttle position 0…1 (military
/// at 77 % of the travel: exactly 50 there, so the game's military lever is dry thrust).
pub fn power_command(throttle: f64) -> f64 {
    let t = throttle.clamp(0.0, 1.0);
    if t <= 0.77 { t / 0.77 * 50.0 } else { 217.38 * t - 117.38 }
}

/// The throttle travel whose commanded power is `power` (the inverse of [`power_command`]).
pub fn travel_for(power: f64) -> f64 {
    let p = power.clamp(0.0, 100.0);
    if p <= 50.0 { p / 50.0 * 0.77 } else { (p + 117.38) / 217.38 }
}

/// Figure 66's own idle → military time, s: from idle to 95 % of the way to military thrust (the moment public
/// spool times are taken at, docs/flight-model.md §10.2), throttle snapped to military. Computed by the
/// `figure_66_spool_time` test.
pub const FIG66_IDLE_MIL: f64 = 3.880;
/// Figure 66's idle → maximum time, s: to 95 % of maximum power (P3 = 95), throttle snapped to maximum.
pub const FIG66_IDLE_MAX: f64 = 4.777;

/// The F100-PW-229's thrust-specific fuel consumption, military 0.76 and maximum 1.94 lb/(lbf·h): the F-16I REAL
/// row's fuel flows over its thrust (`data_set.rs`, inferred there).
pub const TSFC_F100: (f64, f64) = (0.76, 1.94);

/// One engine type.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct EngineSpec {
    pub name: &'static str,
    /// Table VI's idle and military thrust × `mil_scale`, its maximum × `max_scale`: the sea-level static values
    /// (Table VI carried to Mach 0) become the engine's public ratings.
    pub mil_scale: f64,
    pub max_scale: f64,
    /// Figure 66's rates ÷ `time_scale`: its idle → military time becomes the engine's public one.
    pub time_scale: f64,
    /// Angular momentum of the rotors at military, kg·m²/s (the gyroscopic term; scaled by the spool speed).
    pub h_mil: f64,
    /// Thrust-specific fuel consumption at military and at maximum, lb/(lbf·h).
    pub tsfc: (f64, f64),
}

/// Table VI's sea-level static (Mach 0) military and maximum thrust, lbf.
fn static_sl() -> (f64, f64) {
    (table(&T_MIL, 0.0, 0.0), table(&T_MAX, 0.0, 0.0))
}

impl EngineSpec {
    /// An engine rated `mil_lbf` / `max_lbf` (sea-level static) that spools idle → military in `idle_mil_s`. Its
    /// rotors' momentum is TP-1538's 160 slug-ft²/s × the military thrust's scale (inferred).
    pub fn rated(name: &'static str, mil_lbf: f64, max_lbf: f64, idle_mil_s: f64, tsfc: (f64, f64)) -> EngineSpec {
        let (mil, max) = static_sl();
        let mil_scale = mil_lbf / mil;
        EngineSpec {
            name,
            mil_scale,
            max_scale: max_lbf / max,
            time_scale: idle_mil_s / FIG66_IDLE_MIL,
            h_mil: 160.0 * SLUG_FT2 * mil_scale,
            tsfc,
        }
    }

    /// TP-1538's own engine (the F100-PW-200 as installed in the F-16A): Table VI and figure 66 unscaled; 160
    /// slug-ft²/s (appendix B, "Engine Simulation", taken as the military value: inferred).
    pub fn tp1538() -> EngineSpec {
        EngineSpec {
            name: "F100-PW-200 (TP-1538)",
            mil_scale: 1.0,
            max_scale: 1.0,
            time_scale: 1.0,
            h_mil: 160.0 * SLUG_FT2,
            tsfc: TSFC_F100,
        }
    }
}

/// An engine's state: figure 66's power P3 (percent: 0 idle, 50 military, 100 maximum).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Engine {
    pub power: f64,
}

impl Engine {
    /// Advances `dt` s (a frame) toward the throttle (0…1): figure 66(a)'s logic, with the rigid body's frame
    /// rules (a frame time that is not a positive number changes nothing, a frame is cut to [`MAX_FRAME`] and
    /// taken in steps of at most [`MAX_STEP`]). Each step moves the power by the lag's exact solution at that
    /// step's rate, so it never overshoots its target.
    pub fn step(&mut self, spec: &EngineSpec, throttle: f64, dt: f64) {
        if dt.is_nan() || dt <= 0.0 {
            return;
        }
        let dt = dt.min(MAX_FRAME);
        let n = (dt / MAX_STEP).ceil().max(1.0);
        let p1 = power_command(throttle);
        // Military itself (P1 = 50, the lever at the detent) is dry: the afterburner branch takes P1 above it, so the
        // power settles on 50 from below instead of overshooting into the afterburner range.
        for _ in 0..n as usize {
            let p3 = self.power;
            let (p2, r) = match (p1 > 50.0, p3 >= 50.0) {
                (true, true) => (p1, 5.0),
                (true, false) => (60.0, rtau(60.0 - p3)),
                (false, true) => (40.0, 5.0),
                (false, false) => (p1, rtau(p1 - p3)),
            };
            let k = 1.0 - (-r / spec.time_scale * dt / n).exp();
            self.power = (p3 + (p2 - p3) * k).clamp(0.0, 100.0);
        }
    }

    /// Net thrust, N, at `mach` and altitude `alt_m`: figure 66(a)'s blend of Table VI's idle, military and
    /// maximum, scaled to the engine.
    pub fn thrust(&self, spec: &EngineSpec, mach: f64, alt_m: f64) -> f64 {
        let alt_ft = alt_m / FT;
        let mil = table(&T_MIL, mach, alt_ft) * spec.mil_scale;
        let lbf = if self.power < 50.0 {
            let idle = table(&T_IDLE, mach, alt_ft) * spec.mil_scale;
            idle + (mil - idle) * self.power / 50.0
        } else {
            mil + (table(&T_MAX, mach, alt_ft) * spec.max_scale - mil) * (self.power - 50.0) / 50.0
        };
        lbf * LBF
    }

    /// Fuel flow, kg/s, at `thrust_n` (this engine's) at `alt_m`: military's TSFC up to military, blending to
    /// maximum's over the afterburner range; never below the idle flow, military's TSFC × the sea-level static idle
    /// thrust (Table VI carried to Mach 0, scaled) × the density ratio (inferred: an engine burns fuel at idle, where
    /// the net thrust at speed is near zero or below).
    pub fn fuel_flow(&self, spec: &EngineSpec, thrust_n: f64, alt_m: f64) -> f64 {
        let k = ((self.power - 50.0) / 50.0).clamp(0.0, 1.0);
        let tsfc = spec.tsfc.0 + (spec.tsfc.1 - spec.tsfc.0) * k;
        let idle = table(&T_IDLE, 0.0, 0.0) * spec.mil_scale * spec.tsfc.0 * air(alt_m as f32).rho as f64 / 1.225;
        ((thrust_n.max(0.0) / LBF * tsfc).max(idle) / 3600.0) * crate::units::LB
    }

    /// The rotors' angular momentum, kg·m²/s: the military value × the spool speed, 60 % at idle to 100 % at
    /// military (the 1998 gauge's line, docs/flight-model.md §10.2; inferred), held above military.
    pub fn angular_momentum(&self, spec: &EngineSpec) -> f64 {
        spec.h_mil * (0.6 + 0.4 * (self.power / 50.0).min(1.0))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Seconds from idle to `stop` percent power with the throttle at `throttle`.
    fn time_to(spec: &EngineSpec, throttle: f64, stop: f64) -> f64 {
        let (mut e, mut t, dt) = (Engine::default(), 0.0, 1e-4);
        while e.power < stop {
            e.step(spec, throttle, dt);
            t += dt;
        }
        t
    }

    #[test]
    fn figure_66_spool_time() {
        // 95 % of military thrust is P3 = 47.5.
        let t = time_to(&EngineSpec::tp1538(), 0.77, 47.5);
        assert!((t - FIG66_IDLE_MIL).abs() < 1e-3, "{t}");
        let t = time_to(&EngineSpec::tp1538(), 1.0, 95.0);
        assert!((t - FIG66_IDLE_MAX).abs() < 1e-3, "{t}");
        // A scaled engine takes its own time.
        let e = EngineSpec::rated("x", 17_800.0, 29_160.0, 3.0, TSFC_F100);
        assert!((time_to(&e, 0.77, 47.5) - 3.0).abs() < 2e-3);
    }

    #[test]
    fn long_and_bad_frames() {
        // A 0.25 s frame into the afterburner range (the F100-PW-229's 6.8/s) lands on the target without a swing;
        // a NaN or negative frame changes nothing; a 30 s frame is a 0.25 s one.
        let spec = EngineSpec::rated("x", 17_800.0, 29_160.0, 3.0, TSFC_F100);
        let mut e = Engine { power: 50.0 };
        let mut last = e.power;
        for _ in 0..40 {
            e.step(&spec, 1.0, 0.25);
            assert!(e.power >= last && e.power <= 100.0, "{}", e.power);
            last = e.power;
        }
        assert!(e.power > 99.9);
        for dt in [f64::NAN, -1.0, 0.0] {
            let mut e = Engine { power: 20.0 };
            e.step(&spec, 1.0, dt);
            assert_eq!(e.power, 20.0);
        }
        let (mut a, mut b) = (Engine::default(), Engine::default());
        a.step(&spec, 1.0, 30.0);
        b.step(&spec, 1.0, MAX_FRAME);
        assert_eq!(a, b);
    }

    #[test]
    fn military_lever_is_dry() {
        // The game's military lever (0.74: a joystick's detent, the 6 key) settles on 50 from idle or from maximum,
        // never in the afterburner range; the detent's first afterburner value (0.78) lights it.
        let spec = EngineSpec::tp1538();
        for (lever, ab) in [(0.70, false), (0.74, false), (0.78, true), (1.0, true)] {
            for start in [0.0, 100.0] {
                let mut e = Engine { power: start };
                for _ in 0..240 {
                    e.step(&spec, crate::sixdof::flight::lever_to_travel(lever), 0.25);
                }
                assert_eq!(e.power > 50.0, ab, "lever {lever} from {start}: power {}", e.power);
            }
        }
    }

    #[test]
    fn idle_burns_fuel() {
        // At idle and speed the net thrust is below zero; the engine still burns its idle flow.
        let spec = EngineSpec::rated("x", 17_800.0, 29_160.0, 3.0, TSFC_F100);
        let e = Engine::default();
        let t = e.thrust(&spec, 0.9, 0.0);
        assert!(t < 0.0);
        let pph = e.fuel_flow(&spec, t, 0.0) * 3600.0 / crate::units::LB;
        assert!((pph - 1_210.0 * spec.mil_scale * 0.76).abs() < 1.0, "{pph}");
    }

    #[test]
    fn gearing_and_table() {
        assert!((power_command(0.77) - 50.0).abs() < 0.01 && (power_command(1.0) - 100.0).abs() < 1e-9);
        assert!((table(&T_MAX, 0.6, 20_000.0) - 13_760.0).abs() < 1e-9);
        // Above Mach 1.0 the 0.8–1.0 line, to Mach 2.0.
        assert!((table(&T_MIL, 1.2, 0.0) - (11_680.0 + (11_680.0 - 12_390.0))).abs() < 1e-9);
        assert!((table(&T_MIL, 3.0, 0.0) - table(&T_MIL, 2.0, 0.0)).abs() < 1e-9);
        // Mach 0: the line through Mach 0.2 and 0.4.
        assert!((table(&T_MAX, 0.0, 0.0) - 20_140.0).abs() < 1e-9);
    }
}
