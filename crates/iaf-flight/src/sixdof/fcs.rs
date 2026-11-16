//! TP-1538's flight control system A (appendix A, figures 62–65, printed pp. 34–35 and 210–217): a pitch g command
//! with the α limiter, a roll-rate command, the yaw damper and aileron-rudder interconnect, the surfaces' actuators
//! and the leading-edge flap's schedule with its filters. Read off the block diagrams; what was simplified or
//! inferred: modern-iaf/docs/flight-model.md §9.11.
//!
//! Signs here are physical: a positive g command pulls the nose up (stabilator trailing edge up, δh < 0), a positive
//! roll command rolls right (δa < 0 in the tables' convention, `aero::Surfaces`), a positive pedal yaws right
//! (δr < 0).

use super::aero::{Surfaces, lef_schedule};
use crate::aircraft::{F16_CL_DA, F16_CLP};
use crate::data_set::{F16_CAT3_ROLL, Roll};

/// The pilot's controls, −1…1: stick right, stick pulled (nose up), right pedal.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Pilot {
    pub stick_x: f64,
    pub stick_y: f64,
    pub pedal: f64,
    /// Speed brake out.
    pub speed_brake: bool,
    /// A load factor commanded directly (g, the autopilot's), instead of the stick's pitch.
    pub g_command: Option<f64>,
    /// A roll rate commanded directly (deg/s, the autopilot's), instead of the stick's roll.
    pub roll_rate_command: Option<f64>,
    /// The roll trim, stick units (full stick 1): figure 64(a) adds it to the roll-rate error as a roll rate, at most
    /// ±40 × 1.67 = ±66.8 deg/s (`aircraft::step_roll_trim`).
    pub roll_trim: f64,
    /// The MANUAL PITCH override switch held at OVRD: the negative g limit off; above α 29° the stick moves the
    /// stabilator directly and the pedals the rudder.
    pub mpo: bool,
    /// The STORES CONFIG switch at CAT III: figure 1-44's CAT III α limit, the roll command × 0.6 and no pedal
    /// rudder from α 15°.
    pub cat3: bool,
}

/// What the control system senses.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Sensors {
    /// Angle of attack, deg.
    pub alpha: f64,
    /// Body rates, deg/s.
    pub p: f64,
    pub q: f64,
    pub r: f64,
    /// Normal and lateral acceleration, g (specific force: 1 in level flight; lateral positive right).
    pub an: f64,
    pub ay: f64,
    /// Dynamic and static pressure, Pa.
    pub qbar: f64,
    pub ps: f64,
    /// Weight on the wheels.
    pub on_ground: bool,
    /// The jet's weight, lb (CAT III's α limit depends on it).
    pub weight_lb: f64,
    /// True airspeed, m/s.
    pub tas: f64,
}

/// A first-order lag a/(s + a), stepped by its exact solution.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Lag {
    y: f64,
}

impl Lag {
    fn step(&mut self, a: f64, u: f64, dt: f64) -> f64 {
        self.y += (u - self.y) * (1.0 - (-a * dt).exp());
        self.y
    }
}

/// A surface actuator: a lag a/(s + a) with a rate limit (deg/s) and deflection limits (deg).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Actuator {
    y: f64,
}

impl Actuator {
    fn step(&mut self, a: f64, rate: f64, (lo, hi): (f64, f64), cmd: f64, dt: f64) -> f64 {
        let d = (cmd.clamp(lo, hi) - self.y) * (1.0 - (-a * dt).exp());
        self.y = (self.y + d.clamp(-rate * dt, rate * dt)).clamp(lo, hi);
        self.y
    }
}

/// Linear interpolation over the breakpoints `pts` (x ascending), held outside.
fn table(pts: &[(f64, f64)], x: f64) -> f64 {
    let n = pts.len();
    if x <= pts[0].0 {
        return pts[0].1;
    }
    if x >= pts[n - 1].0 {
        return pts[n - 1].1;
    }
    let i = pts.windows(2).position(|w| x <= w[1].0).unwrap_or(n - 2);
    let ((x0, y0), (x1, y1)) = (pts[i], pts[i + 1]);
    y0 + (y1 - y0) * (x - x0) / (x1 - x0)
}

/// Figure 62(e): stick force (N, pull positive) → incremental g command.
const PITCH_GRADIENT: [(f64, f64); 6] =
    [(-80.0, -4.0), (-30.0, -0.8), (-4.0, 0.0), (10.0, 0.0), (35.0, 0.4), (180.0, 10.6)];
/// Figure 64(b): stick force (N, right positive) → roll-rate command, deg/s.
const ROLL_GRADIENT: [(f64, f64); 8] = [
    (-75.0, -308.0),
    (-48.0, -80.0),
    (-26.0, -20.0),
    (-5.0, 0.0),
    (5.0, 0.0),
    (26.0, 20.0),
    (48.0, 80.0),
    (75.0, 308.0),
];
/// Figure 65(b): pedal force (N, right positive) → rudder command, deg of yaw to the right.
const RUDDER_GRADIENT: [(f64, f64); 4] = [(-480.0, -30.0), (-70.0, 0.0), (70.0, 0.0), (480.0, 30.0)];
/// Figure 62(b): negative g limit by q̄ (kN/m²).
const NEG_G: [(f64, f64); 2] = [(1.6, -1.0), (8.9, -4.0)];
/// Figure 62(c): pitch-rate gain by q̄ (kN/m²).
const Q_GAIN: [(f64, f64); 2] = [(4.4, 1.0), (15.5, 0.37)];
/// Figure 62(d): pitch-loop gain by q̄ (kN/m²).
const LOOP_GAIN: [(f64, f64); 2] = [(12.3, 1.0), (43.4, 0.5)];

/// T.O. 1F-16A-1 figure 1-44, CAT III: per gross weight (lb), the α limit at 1 g and the point (α, g) where the CAT III
/// line meets the CAT I limit (read off the chart, ±0.1°).
const CAT3_LIMIT: [(f64, f64, f64, f64); 3] =
    [(25_000.0, 15.5, 16.25, 8.6), (30_000.0, 15.65, 17.05, 8.35), (35_000.0, 15.8, 18.0, 8.0)];
/// The CAT III limiter's gain, g per degree of α over the line (inferred: high enough to hold the steep line within
/// about half a degree with the stick full aft).
const CAT3_GAIN: f64 = 20.0;
/// The integrator's gain in the g command region (below the α limiter), per s (inferred: TP-1538's 5 on the g error
/// alone overshoots to 10 g; 2.5 meets the onset source, modern-iaf/docs/flight-model.md §9.11).
const G_INTEGRATOR: f64 = 2.5;

/// CAT III's α limit (deg) at load factor `n` (g) for a jet of `weight_lb`: figure 1-44's line for that weight,
/// interpolated between the chart's weights and held outside them.
pub fn cat3_alpha_limit(weight_lb: f64, n: f64) -> f64 {
    let w = weight_lb.clamp(CAT3_LIMIT[0].0, CAT3_LIMIT[2].0);
    let i = if w <= CAT3_LIMIT[1].0 { 0 } else { 1 };
    let (a, b) = (CAT3_LIMIT[i], CAT3_LIMIT[i + 1]);
    let k = (w - a.0) / (b.0 - a.0);
    let lerp = |x: f64, y: f64| x + (y - x) * k;
    let (a1, a2, g2) = (lerp(a.1, b.1), lerp(a.2, b.2), lerp(a.3, b.3));
    a1 + (n - 1.0) / (g2 - 1.0) * (a2 - a1)
}

/// The full stick's and pedals' forces, N: the ends of the gradients above (inferred: the game's stick and pedals
/// cover each gradient's whole range; a push reaches −80 N, a pull 180 N).
const PULL_N: f64 = 180.0;
const PUSH_N: f64 = 80.0;
const LAT_N: f64 = 75.0;
const PEDAL_N: f64 = 480.0;

/// The control system's state.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Fcs {
    /// The jet's load-factor limits, g (figure 62(a)'s +8 incremental is the F-16's 9 g).
    max_g: f64,
    min_g: f64,
    // Pitch.
    f_long: Lag,
    n_cmd: Lag,
    alpha_f: Lag,
    q_wash: Lag,
    an_f: Lag,
    lead_x: f64,
    integ: f64,
    dh: Actuator,
    // Roll.
    f_lat: Lag,
    p_cmd: Lag,
    p_f: Lag,
    /// The production F-16's roll (`data_set::F16_ROLL`) and the jet's span, m; None: TP-1538's figure 64.
    roll: Option<(Roll, f64)>,
    da: Actuator,
    // Yaw.
    f_ped: Lag,
    r_f: Lag,
    yaw_lead_x: f64,
    yaw_wash: Lag,
    dr: Actuator,
    // Leading-edge flap.
    lef_alpha_x: f64,
    lef: Actuator,
    // Speed brake.
    sb: Actuator,
}

impl Fcs {
    /// The control system of a jet limited to `max_g` / `min_g` (g): the g command stops at `max_g` − 1 incremental
    /// and at figure 62(b)'s negative limit or `min_g` − 1, whichever is less negative. `roll`: the production F-16's
    /// roll and the jet's span (m), or None for TP-1538's control system A.
    pub fn new((max_g, min_g): (f64, f64), roll: Option<(Roll, f64)>) -> Fcs {
        Fcs { max_g, min_g, roll, ..Fcs::default() }
    }

    /// One step of `dt` s (the rigid body's integrator step, at most 1/120 s): the surfaces' positions.
    pub fn step(&mut self, pilot: &Pilot, s: &Sensors, dt: f64) -> Surfaces {
        let qbar_k = s.qbar / 1000.0;
        // α filter (figure 62: limited −5…30°, 10/(s + 10)), shared by the three axes.
        let alpha_f = self.alpha_f.step(10.0, s.alpha.clamp(-5.0, 30.0), dt);

        // --- Pitch (figure 62(a)) ---
        let force = if pilot.stick_y >= 0.0 { pilot.stick_y * PULL_N } else { pilot.stick_y * PUSH_N };
        let f = self.f_long.step(60.0, force, dt);
        let n = pilot.g_command.map_or_else(|| table(&PITCH_GRADIENT, f), |g| g - 1.0);
        // The MPO overrides the negative g limiter (T.O. 1F-16A-1, "MANUAL PITCH Override"): the jet's own limit
        // stays (inferred).
        let neg = if pilot.mpo { self.min_g - 1.0 } else { table(&NEG_G, qbar_k).max(self.min_g - 1.0) };
        let cmd = n.clamp(neg, self.max_g - 1.0);
        let n_f = self.n_cmd.step(8.3, cmd, dt);
        // Pitch rate washed out, s/(s + 1).
        let q_wo = s.q - self.q_wash.step(1.0, s.q, dt);
        // The α limiter: 0.322 g/deg above 15° (with pitch-rate lead), 1 g/deg more above 20.4°.
        let l1 = (0.322 * (alpha_f + 0.7 * table(&Q_GAIN, qbar_k) * q_wo - 15.0)).max(0.0);
        let l2 = (alpha_f - 20.4).max(0.0);
        // Feedback: (3s + 12)/(s + 12) of the limiter's first branch, pitch rate and filtered (an − 1).
        let an = self.an_f.step(50.0, s.an - 1.0, dt);
        // CAT III (figure 1-44): the α limit of the jet's weight at its load factor, with the same pitch-rate lead.
        let l3 = if pilot.cat3 {
            let lim = cat3_alpha_limit(s.weight_lb, an + 1.0);
            CAT3_GAIN * (alpha_f + 0.7 * table(&Q_GAIN, qbar_k) * q_wo - lim).max(0.0)
        } else {
            0.0
        };
        let fb_in = l1 + l3 + 0.334 * q_wo + an;
        // (3s + 12)/(s + 12) = 3 − 24/(s + 12): x' = u − 12 x, y = 3u − 24x.
        self.lead_x += (fb_in / 12.0 - self.lead_x) * (1.0 - (-12.0 * dt).exp());
        let fb = 3.0 * fb_in - 24.0 * self.lead_x;
        let u = 1.5 * table(&LOOP_GAIN, qbar_k) * (n_f - fb - l2);
        // The integrator (±25°), held at zero with weight on the wheels (inferred: the F-16's weight-on-wheels
        // switch; TP-1538 flies no ground phase), and the proportional path (5, ±25°). Below the α limiter the
        // production F-16 is a g command system ("Commanded pitch responses are in g increments per stick force for
        // AOA below 15 degrees", T.O. 1F-16A-1): there the integrator takes the g error alone (`G_INTEGRATOR`), so
        // the jet holds the commanded g while its speed and pitch rate change; TP-1538's integrator (5/s on the whole
        // shaped error, its washed-out pitch rate included) stopped 0.5 g short and reached it slowly. On the
        // limiter, TP-1538's.
        let ui = if l1 + l2 + l3 > 0.0 { 5.0 * u } else { G_INTEGRATOR * 1.5 * table(&LOOP_GAIN, qbar_k) * (n_f - an) };
        // MPO above α 29° (T.O. 1F-16A-1: "enable manual control of the horizontal tails"): full stick is full
        // stabilator, centred stick streamlines it; the integrator follows (the proportional path returns at once
        // when the MPO lets go; the actuator's 60 deg/s limits the step).
        let manual = pilot.mpo && s.alpha > 29.0;
        let dh_cmd = if manual {
            let dh = -25.0 * pilot.stick_y.clamp(-1.0, 1.0);
            self.integ = (0.5 * alpha_f - dh).clamp(-25.0, 25.0);
            dh
        } else {
            self.integ = if s.on_ground { 0.0 } else { (self.integ + ui * dt).clamp(-25.0, 25.0) };
            -(self.integ + (5.0 * u).clamp(-25.0, 25.0)) + 0.5 * alpha_f
        };
        let dh = self.dh.step(20.2, 60.0, (-25.0, 25.0), dh_cmd, dt);

        // --- Roll (figure 64(a); the notch filter and the command shaping left out, inferred) ---
        let f = self.f_lat.step(60.0, pilot.stick_x * LAT_N, dt);
        let full = ROLL_GRADIENT[ROLL_GRADIENT.len() - 1].1;
        // The production F-16 (`data_set::F16_ROLL`): figure 64(b)'s stick shape scaled to its full-stick rate and
        // followed at its onset (a first-order command of time constant rate / accel: a full-stick step starts at
        // `accel`), its flaperons' rate and travel (the aileron is half their difference: (20° down + 23° up) / 2 =
        // 21.5°, as TP-1538's). The stick's command also goes forward as the aileron that rolls the jet steadily at
        // that rate (the roll damping met by the roll control: δa = Clp·(p·b/2V) / Cl_δa, TP-1538's derivatives,
        // `aircraft::F16_CLP`; inferred: figure 64(a)'s proportional loop alone stops short of its command); the loop
        // corrects the rest, so a steady moment (unbalanced stores) still rolls the jet. TP-1538's control system A
        // otherwise, and for the autopilot's rate command: 308 deg/s, 10/(s + 10), 80 deg/s, ±21.5°, no feedforward.
        // CAT III: the stick's roll command × `F16_CAT3_ROLL` (T.O. 1F-16A-1 figure 1-43).
        let stick = table(&ROLL_GRADIENT, f) * if pilot.cat3 { F16_CAT3_ROLL } else { 1.0 };
        let (da_rate, da_max) =
            self.roll.map_or((80.0, 21.5), |(r, _)| (r.flaperon_rate, (r.flaperon.0 + r.flaperon.1) / 2.0));
        let (p_cmd, ff_span) = match (self.roll, pilot.roll_rate_command) {
            (Some((r, span)), None) => (self.p_cmd.step(r.accel / r.rate, stick * r.rate / full, dt), span),
            (_, c) => (self.p_cmd.step(10.0, c.unwrap_or(stick), dt), 0.0),
        };
        let p_f = self.p_f.step(50.0, s.p, dt);
        let r_f = self.r_f.step(50.0, s.r, dt);
        // Above α 29° the departure / spin prevention drives the ailerons against the yaw rate instead.
        let trim = pilot.roll_trim * full;
        let (roll_cmd, ff) = if alpha_f >= 29.0 {
            (-8.34 * r_f, 0.0)
        } else {
            (p_cmd + trim - p_f, F16_CLP * p_cmd.to_radians() * ff_span / (2.0 * s.tas.max(30.0)) / F16_CL_DA)
        };
        let da_c = (ff + 0.12 * roll_cmd).clamp(-da_max, da_max);
        let da = -self.da.step(20.2, da_rate, (-da_max, da_max), da_c, dt);

        // --- Yaw (figure 65(a)) ---
        let f = self.f_ped.step(60.0, pilot.pedal * PEDAL_N, dt);
        // The pedals fade out to none at α 30° (TP-1538); CAT III: none from α 15° (T.O. 1F-16A-1 figure 1-43: "Zero
        // rudder authority available at 15° AOA", faded from 5°, inferred); MPO above α 29°: full (figure 1-43 note 2).
        let fade = if pilot.mpo && s.alpha > 29.0 {
            1.0
        } else if pilot.cat3 {
            ((15.0 - alpha_f) / 10.0).clamp(0.0, 1.0)
        } else {
            ((30.0 - alpha_f) / 10.0).clamp(0.0, 1.0)
        };
        let pedal = table(&RUDDER_GRADIENT, f) * fade;
        // Stability-axis yaw rate r − p·α, (3s + 15)/(s + 15), washed out 1.5 s/(s + 1).
        let r_stab = r_f - p_f * alpha_f / 57.3;
        self.yaw_lead_x += (r_stab / 15.0 - self.yaw_lead_x) * (1.0 - (-15.0 * dt).exp());
        let lead = 3.0 * r_stab - 30.0 * self.yaw_lead_x;
        let damper = 1.5 * (lead - self.yaw_wash.step(1.0, lead, dt));
        // The aileron-rudder interconnect: 0.075 α minus a term that fades in with q̄/ps (figure 65(a)).
        let tri = (1.0 - alpha_f.abs() / 10.0).max(0.0);
        let ramp = ((s.qbar / s.ps.max(1.0) - 0.187) / (1.129 - 0.187)).clamp(0.0, 1.0);
        let ari = (0.075 * alpha_f - tri * ramp) * da_c;
        let yaw_right = if alpha_f >= 29.0 { pedal - 0.75 * r_f } else { pedal + ari - 0.5 * (damper + 19.32 * s.ay) };
        let dr = -self.dr.step(20.2, 120.0, (-30.0, 30.0), yaw_right, dt);

        // --- Leading-edge flap (appendix A): 1.38 (2s + 7.25)/(s + 7.25) α − 9.05 q̄/ps + 1.45, its actuator a
        // 0.136 s lag, 25 deg/s, 0…25° ---
        // (2s + 7.25)/(s + 7.25) = 2 − 7.25/(s + 7.25).
        self.lef_alpha_x += (s.alpha - self.lef_alpha_x) * (1.0 - (-7.25 * dt).exp());
        let alpha_lead = 2.0 * s.alpha - self.lef_alpha_x;
        let lef_cmd = lef_schedule(alpha_lead, s.qbar, s.ps.max(1.0));
        let dlef = self.lef.step(1.0 / 0.136, 25.0, (0.0, 25.0), lef_cmd, dt);

        // Speed brake: 0…60° at 30 deg/s (inferred: two seconds to open).
        let dsb = self.sb.step(100.0, 30.0, (0.0, 60.0), if pilot.speed_brake { 60.0 } else { 0.0 }, dt);

        Surfaces { dh, da, dr, dlef, dsb, dtef: 0.0 }
    }

    /// Starts the control system settled at `alpha` (deg) with the stabilator at `dh` (deg): the filters at their
    /// steady values, the integrator holding the stabilator.
    pub fn settle(&mut self, alpha: f64, dh: f64, qbar: f64, ps: f64) {
        let a = alpha.clamp(-5.0, 30.0);
        self.alpha_f.y = a;
        self.lef_alpha_x = alpha;
        self.lef.y = lef_schedule(alpha, qbar, ps.max(1.0));
        self.dh.y = dh;
        self.integ = (0.5 * a - dh).clamp(-25.0, 25.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gradients() {
        assert_eq!(table(&PITCH_GRADIENT, 0.0), 0.0);
        assert!((table(&PITCH_GRADIENT, 180.0) - 10.6).abs() < 1e-12);
        assert_eq!(table(&ROLL_GRADIENT, 75.0), 308.0);
        assert_eq!(table(&RUDDER_GRADIENT, -480.0), -30.0);
        assert_eq!(table(&NEG_G, 0.0), -1.0);
    }

    #[test]
    fn g_limits_per_jet() {
        // The Ra'am's +8.1 g: a full pull commands 7.1 g incremental, not 8; its −2 g: −3 incremental at most.
        let mut f = Fcs::new((8.1, -2.0), None);
        let s = Sensors { an: 1.0, qbar: 30_000.0, ps: 100_000.0, ..Sensors::default() };
        for _ in 0..200 {
            f.step(&Pilot { stick_y: 1.0, ..Pilot::default() }, &s, 0.01);
        }
        assert!((f.n_cmd.y - 7.1).abs() < 1e-6, "{}", f.n_cmd.y);
        for _ in 0..400 {
            f.step(&Pilot { stick_y: -1.0, ..Pilot::default() }, &s, 0.01);
        }
        assert!((f.n_cmd.y + 3.0).abs() < 1e-6, "{}", f.n_cmd.y);
    }

    #[test]
    fn actuator_limits() {
        // The stabilator moves at most 60 deg/s and stops at 25°.
        let mut a = Actuator::default();
        let y = a.step(20.2, 60.0, (-25.0, 25.0), 25.0, 0.1);
        assert!((y - 6.0).abs() < 1e-9);
        for _ in 0..100 {
            a.step(20.2, 60.0, (-25.0, 25.0), 90.0, 0.1);
        }
        assert_eq!(a.y, 25.0);
    }
}
