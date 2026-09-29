//! The aircraft: state, controls and the original's update schedule
//! (docs/flight-model.md §4–§7).
//!
//! World frame is ENU: X east, Y north, Z up (metres). Positive roll = right wing down.

use crate::atmosphere::{air, q_s};
use crate::channels::{Angle, Axis, Ramp};
use crate::envelope::{Envelope, GLimit};
use crate::params::Params;

pub const G: f32 = 9.806;
const LBF: f32 = 4.4479;
/// Aero data refresh (plus every control event).
const AERO_PERIOD: f64 = 1.0;
/// Acceleration / rate refresh.
const ACCEL_PERIOD: f64 = 0.2;
/// Departure latch after a stall.
const STALL_LATCH: f64 = 3.0;
/// Rolling friction, IAF.ibx `[TAXI] fric1` (load-time initialiser 0x5b7720 → DAT_0084083c).
const FRIC1: f32 = 0.05;
/// Nose-wheel yaw limit K (DAT_00840864 = 1° · 20, set at load by 0x5b7960).
const NOSE_K: f32 = 0.349_065_9;

type V3 = [f64; 3];

fn add(a: V3, b: V3) -> V3 {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}
fn scale(a: V3, s: f64) -> V3 {
    [a[0] * s, a[1] * s, a[2] * s]
}
fn dot(a: V3, b: V3) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn cross(a: V3, b: V3) -> V3 {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}
fn norm(a: V3) -> V3 {
    let l = dot(a, a).sqrt();
    if l > 1e-12 { scale(a, 1.0 / l) } else { [0.0, 1.0, 0.0] }
}
/// Rotate `v` about unit `axis` by `angle` (right-hand rule, Rodrigues).
fn rotate(v: V3, axis: V3, angle: f64) -> V3 {
    let (s, c) = angle.sin_cos();
    add(add(scale(v, c), scale(cross(axis, v), s)), scale(axis, dot(axis, v) * (1.0 - c)))
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Controls {
    /// Stick roll −1..1 (right positive).
    pub stick_x: f32,
    /// Stick pitch −1..1 (**pull positive**, i.e. nose up).
    pub stick_y: f32,
    /// Rudder −1..1 (right positive).
    pub rudder: f32,
    /// 0..1: 0.74 = military, 0.75..0.875 = AB1, ≥0.875 = AB2.
    pub throttle: f32,
    /// 0..1.
    pub flaps: f32,
    pub gear_down: bool,
    /// Speed brakes in the air, wheel brakes on the ground (one key in the original).
    pub brakes: bool,
}

impl Default for Controls {
    fn default() -> Self {
        Self { stick_x: 0.0, stick_y: 0.0, rudder: 0.0, throttle: 0.74, flaps: 0.0, gear_down: false, brakes: false }
    }
}

/// Everything the cockpit, HUD and renderer need, sampled at the current time.
#[derive(Debug, Clone, Copy)]
pub struct State {
    pub time: f64,
    pub position: V3,
    pub velocity: [f32; 3],
    pub speed: f32,
    pub mach: f32,
    /// Body axes in world (ENU) coordinates.
    pub forward: V3,
    pub right: V3,
    pub up: V3,
    pub pitch: f32,
    pub roll: f32,
    /// Radians clockwise from north.
    pub heading: f32,
    pub alpha: f32,
    pub beta: f32,
    /// Load factor (lift / weight).
    pub g: f32,
    /// Engine RPM, percent.
    pub rpm: f32,
    pub throttle: f32,
    pub afterburner: u8,
    pub thrust_n: f32,
    pub fuel_kg: f32,
    pub mass_kg: f32,
    pub stalled: bool,
    pub buffet: bool,
    pub over_g: bool,
    pub on_ground: bool,
}

pub struct Aircraft {
    pub params: Params,
    pub envelope: Envelope,
    t: f64,
    controls: Controls,
    axes: [Axis; 3],
    roll: Angle,
    roll_target_rate: f32,
    alpha: Angle,
    beta: Ramp,
    lift: Ramp,
    lift_aoa: Ramp,
    rpm: Ramp,
    fuel: Ramp,
    flaps: Ramp,
    speed_brakes: Ramp,
    /// Right-wing unit vector and the roll angle it corresponds to (saved every 5 Hz tick).
    wing: V3,
    wing_roll: f64,
    thrust: f32,
    afterburner: u8,
    drag: f32,
    mass: f32,
    fuel_flow: f32,
    stall_time: f64,
    buffet: bool,
    /// Engine running (`S+0x1d0`): off at a ground start, turned on by any throttle change
    /// (§8, `FUN_0059cb60`); on at an airborne start (`FUN_005a2a10`).
    pub engine_on: bool,
    // Load-time derived constants.
    cl0: f32,
    cl_alpha: f32,
    stick_centre_v: f32,
    stick_centre_a: f32,
    stick_centre_b: f32,
    next_aero: f64,
    next_accel: f64,
    pub on_ground: bool,
    /// Terrain elevation under the aircraft, supplied by the host every frame.
    pub ground_height: f32,
    /// Height of the aircraft origin above the wheels' contact point (the model's `height`
    /// helper, F-16 1.69 m), so the jet rests on its gear.
    pub gear_clearance: f32,
    /// Horizontal direction the aircraft points on the ground (unit, ENU).
    ground_dir: V3,
}

impl Aircraft {
    /// Airborne start at `position` (ENU), `heading` (rad, clockwise from north), `speed` (m/s).
    pub fn new(params: Params, envelope: Envelope, position: V3, heading: f32, speed: f32) -> Self {
        let p = &params;
        let (cl0, cl_alpha, stick_centre_v, stick_centre_a, stick_centre_b) = Self::derive(p, &envelope);

        let (s, c) = (heading as f64).sin_cos();
        let v = [(speed as f64 * s) as f32, (speed as f64 * c) as f32, 0.0];
        let mass = p.empty_mass + p.fuel_mass;
        let lift_lo = p.max_mass * p.min_g_m1 * G;
        let lift_hi = p.max_mass * p.max_g_m1 * G;
        let mut ac = Self {
            t: 0.0,
            controls: Controls::default(),
            axes: [Axis::new(position[0], v[0]), Axis::new(position[1], v[1]), Axis::new(position[2], v[2])],
            roll: Angle::new(0.0, p.roll_accel, p.stop_accel, p.max_roll_rate),
            roll_target_rate: 0.0,
            alpha: Angle::new(0.0, p.alpha_start_accel, p.alpha_stop_accel, p.max_alpha_rate),
            beta: Ramp::new(0.0, -p.max_beta, p.max_beta),
            lift: Ramp::new(mass * G, lift_lo, lift_hi),
            lift_aoa: Ramp::new(mass * G, lift_lo, lift_hi),
            rpm: Ramp::new(100.0, 0.0, 110.0),
            fuel: Ramp::new(p.fuel_mass, 0.0, p.fuel_mass),
            flaps: Ramp::new(0.0, 0.0, 1.0),
            speed_brakes: Ramp::new(0.0, 0.0, 1.0),
            wing: [c, -s, 0.0],
            wing_roll: 0.0,
            thrust: 0.0,
            afterburner: 0,
            drag: 0.0,
            mass,
            fuel_flow: 0.0,
            engine_on: true,
            stall_time: f64::NEG_INFINITY,
            buffet: false,
            cl0,
            cl_alpha,
            stick_centre_v,
            stick_centre_a,
            stick_centre_b,
            next_aero: 0.0,
            next_accel: 0.0,
            on_ground: false,
            ground_height: f32::NEG_INFINITY,
            gear_clearance: 0.0,
            ground_dir: [s, c, 0.0],
            params,
            envelope,
        };
        ac.aero_update();
        ac.accel_update();
        ac.next_aero = AERO_PERIOD;
        ac.next_accel = ACCEL_PERIOD;
        ac
    }

    /// Load-time derived constants (§1): CL at α=0 and dCL/dα from the 1 g / max g minimum
    /// speeds, and the stick-centre shift line (P.170 / P.174).
    fn derive(p: &Params, envelope: &Envelope) -> (f32, f32, f32, f32, f32) {
        let alt = 330.0;
        let v1 = envelope.vmin(alt, 1.0);
        let vg = envelope.vmin(alt, p.max_g_m1 + 1.0);
        let (qs1, qs2) = (q_s(alt, v1, p.wing_area), q_s(alt, vg, p.wing_area));
        let w = p.empty_mass * G;
        let cl0 = w / qs2;
        let cl_alpha = (w - qs1 * cl0) / (qs1 * p.max_pos_alpha);
        let stick_centre_v = envelope.vmin(3048.0, p.start_move_stick_center_g);
        let stick_centre_a = (p.map_center_stick - 1.0) / (10.0 - stick_centre_v);
        let stick_centre_b = p.map_center_stick - stick_centre_a * 10.0;
        (cl0, cl_alpha, stick_centre_v, stick_centre_a, stick_centre_b)
    }

    /// Engine on/off. Switching it off (a ground start) stops the engine at once: no thrust, RPM 0.
    pub fn set_engine(&mut self, on: bool) {
        self.engine_on = on;
        if !on {
            self.rpm.reset(self.t, 0.0);
            self.aero_update();
        }
    }

    pub fn controls(&self) -> Controls {
        self.controls
    }

    /// Applies new controls; like the original, any change triggers an immediate aero update.
    pub fn set_controls(&mut self, c: Controls) {
        let c = Controls {
            stick_x: c.stick_x.clamp(-1.0, 1.0),
            stick_y: c.stick_y.clamp(-1.0, 1.0),
            rudder: c.rudder.clamp(-1.0, 1.0),
            throttle: c.throttle.clamp(0.0, 1.0),
            flaps: c.flaps.clamp(0.0, 1.0),
            ..c
        };
        if c.throttle != self.controls.throttle {
            self.engine_on = true;
        }
        if c != self.controls {
            self.controls = c;
            self.flaps.set(self.t, c.flaps, 0.25);
            self.speed_brakes.set(self.t, if c.brakes { 1.0 } else { 0.0 }, 1.0);
            self.aero_update();
        }
    }

    /// Advances the simulation to `t + dt`, running the 1 Hz / 5 Hz updates on schedule.
    pub fn step(&mut self, dt: f64) {
        let end = self.t + dt;
        while self.next_accel.min(self.next_aero) <= end {
            if self.next_aero <= self.next_accel {
                self.t = self.next_aero;
                self.aero_update();
                self.next_aero += AERO_PERIOD;
            } else {
                self.t = self.next_accel;
                self.accel_update();
                self.next_accel += ACCEL_PERIOD;
            }
        }
        self.t = end;
        let _ = dt;
    }

    /// Nose-wheel yaw (§7, §14.2): clamp(stickX · V · K / 74.53, ±K), 0 with the gear up or below
    /// 1e-4. V = |v|. The rudder is ignored on the ground in the original.
    fn nose_wheel_yaw(&self, v: f32) -> f32 {
        if !self.controls.gear_down {
            return 0.0;
        }
        let yaw = (self.controls.stick_x * v * NOSE_K / 74.53).clamp(-NOSE_K, NOSE_K);
        if yaw.abs() < 1e-4 { 0.0 } else { yaw }
    }

    /// The 0/1 brake flag `cfg[6]`: the brakes ramp has finished at its maximum (§14.1).
    fn brake_flag(&self, t: f64) -> f32 {
        if self.speed_brakes.sample(t) >= 1.0 { 1.0 } else { 0.0 }
    }

    fn speed_at(&self, t: f64) -> (V3, f32) {
        let v = [self.axes[0].sample(t).1, self.axes[1].sample(t).1, self.axes[2].sample(t).1];
        let v = [v[0] as f64, v[1] as f64, v[2] as f64];
        let speed = dot(v, v).sqrt() as f32;
        (v, speed.min(1200.0))
    }

    fn position_at(&self, t: f64) -> V3 {
        [self.axes[0].sample(t).0, self.axes[1].sample(t).0, self.axes[2].sample(t).0]
    }

    /// Body axes from velocity, roll channel, α and β (§6).
    fn attitude(&self, t: f64) -> (V3, V3, V3) {
        if self.on_ground {
            // Ground mode: level; the heading follows the velocity (§14.5), else the last heading.
            let (v, speed) = self.speed_at(t);
            let f = if speed > 0.5 { norm([v[0], v[1], 0.0]) } else { self.ground_dir };
            let right = norm(cross(f, [0.0, 0.0, 1.0]));
            return (f, right, [0.0, 0.0, 1.0]);
        }
        let (v, speed) = self.speed_at(t);
        let f = if speed > 0.5 { norm(v) } else { norm(cross([0.0, 0.0, 1.0], self.wing)) };
        let (phi, _) = self.roll.sample(t);
        let w = rotate(self.wing, f, phi - self.wing_roll);
        let w = norm(add(w, scale(f, -dot(w, f))));
        let (alpha, _) = self.alpha.sample(t);
        let fwd = rotate(f, w, alpha);
        let up = cross(w, fwd);
        let beta = self.beta.sample(t) as f64;
        let fwd = rotate(fwd, up, -beta);
        let right = norm(cross(fwd, up));
        (fwd, right, up)
    }

    fn euler(fwd: V3, right: V3) -> (f32, f32, f32) {
        let pitch = fwd[2].clamp(-1.0, 1.0).asin();
        let heading = fwd[0].atan2(fwd[1]).rem_euclid(std::f64::consts::TAU);
        let horizontal_right = norm(cross(fwd, [0.0, 0.0, 1.0]));
        let mut roll = dot(right, horizontal_right).clamp(-1.0, 1.0).acos();
        if right[2] > 0.0 {
            roll = -roll;
        }
        (pitch as f32, roll as f32, heading as f32)
    }

    /// Thrust (N), RPM (0..1), fuel flow (kg/s), afterburner stage (§4.1).
    /// `no_ab`: the original passes !HasAfterBurner in the air but "AI" (false for the player) on
    /// the ground (§14.2, mismatch 13), so the player's ground roll always uses the AB curve.
    fn thrust_at(&self, alt: f32, mach: f32, no_ab: bool) -> (f32, f32, f32, u8) {
        let p = &self.params;
        let thr = self.controls.throttle;
        if !self.engine_on || self.fuel.sample(self.t) <= 1e-5 {
            return (0.0, 0.0, 0.0, 0);
        }
        let stage_of = |thr: f32| if thr < 0.75 { 0 } else if thr < 0.875 { 1 } else { 2 };
        let (k, stage) = if !no_ab {
            if thr < 0.75 {
                (0.05 + 0.743_243_2 * thr, 0)
            } else if thr < 0.875 {
                (0.875, 1)
            } else {
                (1.0, 2)
            }
        } else {
            ((thr - 0.2) * 1.25, stage_of(thr))
        };
        let a = (alt * 5e-5).clamp(0.0, 1.0);
        let m = (mach / 1.2).clamp(0.0, 1.0);
        let lerp = |t: f32, x: f32, y: f32| x + (y - x) * t;
        let tk = |mach_i: usize, alt_i: usize| lerp(k, p.thrust[mach_i][alt_i][0], p.thrust[mach_i][alt_i][1]);
        let thrust = lerp(a, lerp(m, tk(0, 0), tk(1, 0)), lerp(m, tk(0, 1), tk(1, 1))) * LBF;
        let rpm = 0.6 + 0.4 * thr * 1.351_351_4;
        let mut ff = thr * p.fuel_flow_max;
        if k <= 0.6 {
            ff *= 0.25;
        }
        (thrust, rpm, ff, stage)
    }

    fn lift_coefficient_alpha(&self, lift: f32, qs: f32) -> f32 {
        let p = &self.params;
        if qs <= 0.0 {
            return 0.0;
        }
        ((lift - self.cl0 * qs) / (self.cl_alpha * qs)).clamp(p.max_neg_alpha, p.max_pos_alpha)
    }

    /// 1 Hz / event update: thrust, drag, mass, lift targets, roll-rate target (§4).
    fn aero_update(&mut self) {
        let t = self.t;
        let p = self.params.clone();
        let c = self.controls;
        let pos = self.position_at(t);
        let alt = pos[2] as f32;
        let (_, v) = self.speed_at(t);
        let air = air(alt);
        let mach = v / air.sound;
        let qs = q_s(alt, v, p.wing_area);
        let lift_before = self.lift.sample(t);
        let (mut thrust, rpm, ff, stage) = self.thrust_at(alt, mach, if self.on_ground { false } else { !p.has_afterburner });
        if self.on_ground {
            thrust = thrust.max(0.0);
        }
        let fuel = self.fuel.sample(t);
        let mass = p.empty_mass + fuel;
        let (fwd, right, _) = self.attitude(t);
        let (_, roll, _) = Self::euler(fwd, right);
        let (vel, _) = self.speed_at(t);
        let gamma = if v > 1.0 { (vel[2] / v as f64).clamp(-1.0, 1.0).asin() as f32 } else { 0.0 };
        let alpha_now = self.alpha.sample(t).0 as f32;

        // Commanded load factor (§4.2, Lift 5b13a0). The ground call passes latched = 0 (§14.3).
        let latched = !self.on_ground && t - self.stall_time < STALL_LATCH;
        let mut stalled = false;
        let mut g = if latched {
            0.0
        } else {
            let centre = if v < self.stick_centre_v { self.stick_centre_a * v + self.stick_centre_b } else { 1.0 };
            let sp = c.stick_y;
            let mut g = if sp > 0.0 { centre + sp * p.max_g_m1 } else { centre + (-sp) * ((p.min_g_m1 + 1.0) - centre) };
            if (g - 1.0).abs() < 1e-5 && roll.abs() < 10f32.to_radians() {
                // Neutral stick: hold the flight path. The original uses the nose pitch
                // (cos(pitch)/cos(roll)); we use the flight-path angle and subtract the thrust's
                // lift component, otherwise the jet slowly dives at high speed where the
                // original's alpha goes negative (deviation, see docs/flight-model.md).
                g = gamma.cos() / roll.cos() - self.thrust * alpha_now.sin() / (mass * G);
            }
            g
        };
        self.buffet = false;
        let g_cmd = g;
        if p.use_flight_limits && !latched {
            match self.envelope.g_limit(alt, v, g) {
                GLimit::Stall | GLimit::TooHigh => {
                    g = 0.0;
                    stalled = true;
                }
                GLimit::None => {}
                GLimit::Max(lim) => {
                    if g <= 0.0 {
                        g = g.max(lim);
                    } else if g >= lim {
                        g = lim;
                    }
                    self.buffet = lim <= p.start_vibs_g && g_cmd > 0.0;
                }
            }
        }
        let mut lift_noflap = g * mass * G;
        let mut lift = lift_noflap;
        let flaps = self.flaps.sample(t);
        let c_f = p.flaps_lift_coef * flaps * 3.415_883_8;
        if v < 125.0 {
            lift += lift_noflap.abs() * c_f;
        }
        if self.on_ground {
            // Ground (FUN_005b7a20): half the lift, flaps added again, gated by speed / pull and gear.
            lift *= 0.5;
            lift += lift.abs() * c_f;
            if !((v > 74.53 || c.stick_y > 0.5) && c.gear_down) {
                lift = 0.0;
                lift_noflap = 0.0;
                stalled = false;
            }
        }
        // A stall sets the departure latch, on the ground too (5a7050).
        if stalled {
            self.stall_time = t;
        }

        // Drag (§4.3, 5b1730); the ground call passes alpha = 0.
        let alpha = if stalled || self.on_ground { 0.0 } else { self.lift_coefficient_alpha(lift_noflap, qs) };
        let n = lift / (mass * G);
        let cl = if qs > 0.0 { alpha.cos() * mass * n * G / qs } else { 0.0 };
        let k = 1.0 / (std::f32::consts::PI * p.wing_span * p.wing_span / p.wing_area * 0.85);
        let brakes = self.brake_flag(t);
        let mut cd = p.plane_di + brakes * p.speed_brakes_di + k * cl * cl + p.flaps_di * flaps * 3.415_883_8;
        if p.wave_drag > 0.0 && mach > 0.9 {
            cd += p.wave_drag * ((mach - 0.9) / 0.3).min(1.0);
        }
        if c.gear_down {
            cd += p.gear_di;
        }
        let mut drag = cd * qs;
        if self.on_ground {
            let mu = if c.gear_down { brakes * p.wheel_brake_di + FRIC1 } else { 20.0 };
            drag = (drag + 0.5 * mu * (mass * G - lift)).max(0.0);
            if v > 1.0 {
                drag *= 0.7;
            }
        }

        self.thrust = thrust;
        self.afterburner = stage;
        self.drag = drag;
        self.mass = mass;
        self.fuel_flow = ff;

        let rate = |r: f32| if v >= 220.0 { r } else { r * (0.01 + 0.99 * (v - 20.0) / 200.0).max(0.01) };
        self.lift.set(t, lift, rate(p.g_rate) * mass * G);
        self.lift_aoa.set(t, lift_noflap, rate(p.g_rate_for_aoa) * mass * G);
        self.rpm.set(t, 100.0 * rpm, 15.0);
        self.fuel.set(t, 0.0, ff);

        // Roll rate target, scaled down at low speed (§4).
        let veff = ((-1.305e-5 + 3.1825e-9 * v) * alt + 1.0017) * v - 3.122;
        let kroll = if veff < 220.0 { 0.00475 * veff - 0.045 } else { 1.0 };
        self.roll_target_rate = if self.on_ground { 0.0 } else { p.max_roll_rate * c.stick_x * kroll.max(0.0) };
        let (phi, _) = self.roll.sample(t);
        self.roll.set(t, phi, self.roll_target_rate);

        // Beta is not updated on the ground (the nose-wheel yaw is used there).
        if !self.on_ground {
            let beta_cmd = c.rudder * p.max_beta;
            let beta_rate = if v >= 375.0 { p.beta_rate } else { (p.beta_rate * 0.0025 * v).max(0.25 * p.beta_rate) };
            self.beta.set(t, beta_cmd, beta_rate);
        }
        // The aero update also recomputes the acceleration at once, with the lift ramp sampled
        // before its new target (5a42e0 @5a4a17, §14.1).
        self.apply_forces(t, lift_before, false);
    }

    /// 5 Hz update: α target, forces, new constant accelerations (§5).
    fn accel_update(&mut self) {
        let t = self.t;
        // Air / ground transitions are checked once per 5 Hz tick, before the forces (5b87d0).
        self.transitions(t);
        let p = &self.params;
        let pos = self.position_at(t);
        let alt = pos[2] as f32;
        let (_, v) = self.speed_at(t);
        let qs = q_s(alt, v, p.wing_area);
        let lift = self.lift.sample(t);
        let lift_aoa = self.lift_aoa.sample(t);

        // Alpha dynamics toward the target implied by lift.
        let alpha_target = if self.on_ground {
            0.0 // 5b1b90 returns 0 on the ground
        } else if qs > 0.0 {
            ((lift_aoa - self.cl0 * qs) / (self.cl_alpha * qs)).clamp(p.max_neg_alpha, p.max_pos_alpha.min(p.limit_alpha_visual))
        } else {
            0.0
        };
        let f = if v >= 220.0 { 1.0 } else { (0.004995 * v - 0.0989).max(0.001) };
        self.alpha.start_accel = p.alpha_start_accel * f;
        self.alpha.stop_accel = p.alpha_stop_accel * f;
        self.alpha.max_rate = p.max_alpha_rate * f;
        let (a_now, a_rate) = self.alpha.sample(t);
        let err = (alpha_target as f64 - a_now) as f32;
        let damp = p.alpha_beta * f * a_rate * self.alpha.max_rate;
        let target_rate = (err / std::f32::consts::PI * p.alpha_k * f / self.alpha.max_rate - damp).clamp(-1.0, 1.0) * self.alpha.max_rate;
        self.alpha.set(t, a_now, target_rate);

        self.apply_forces(t, lift, true);
    }

    /// Forces → constant accelerations, re-basing the axes (§5; ground §14.5). `tick` = the 5 Hz
    /// update (the only place the ground stop rule runs).
    fn apply_forces(&mut self, t: f64, lift: f32, tick: bool) {
        let (_, v) = self.speed_at(t);
        if self.on_ground {
            self.ground_forces(t, lift, v, tick);
            return;
        }
        let (fwd, right, up) = self.attitude(t);
        let alpha = self.alpha.sample(t).0 as f32;
        let beta = self.beta.sample(t);
        let (thrust, drag, mass) = (self.thrust, self.drag, self.mass);
        let fy = thrust + lift * alpha.sin() - drag * alpha.cos() * beta.cos();
        let fz = lift * alpha.cos() + drag * alpha.sin() * beta.cos();
        let fx = drag * beta.sin() + 5.0 * v * v * beta;
        let force = add(add(scale(fwd, fy as f64), scale(up, fz as f64)), scale(right, fx as f64));
        let mut acc = scale(force, 1.0 / mass as f64);
        acc[2] -= G as f64;
        for (axis, a) in self.axes.iter_mut().zip(acc) {
            axis.set(t, a as f32);
        }
        if tick {
            // Re-base the wing vector on the current attitude (§5, §6).
            self.wing = right;
            self.wing_roll = self.roll.sample(t).0;
        }
    }

    /// Ground acceleration (FUN_005b7e40, §14.5): level attitude along the heading; the nose wheel
    /// pushes sideways (Fc), which scrubs speed and can multiply the vertical lift by 4.
    fn ground_forces(&mut self, t: f64, lift: f32, v: f32, tick: bool) {
        let (fwd, right, up) = self.attitude(t);
        let m = self.mass;
        let fc = match self.params.nose_wheel {
            // Real data set: geometric steering from the pedals, limited by the tyres' grip.
            Some(nw) if self.controls.gear_down && v > 0.1 => {
                let rate = v * (self.controls.rudder * nw.max_angle).tan() / nw.wheelbase;
                m * (v * rate).clamp(-nw.max_lateral, nw.max_lateral)
            }
            Some(_) => 0.0,
            None => {
                let yaw = self.nose_wheel_yaw(v);
                let mut r = if yaw == 0.0 { 5.0 } else { v / (G * yaw.tan()) };
                if r.abs() < 2.0 {
                    r = 2.0 * r.signum();
                }
                let mut fc = if v > 2.0 && yaw != 0.0 { v * v * m / r } else { 0.0 };
                fc *= if v < 25.736 { 1.0 } else { (0.1 - 0.000_777_118 * v).abs() };
                fc
            }
        };
        let mut lz = lift;
        if fc.abs() > 0.1 * lz && v > 20.5889 {
            lz *= 4.0;
        }
        let (thrust, drag) = (self.thrust, self.drag);
        let fx = if v < 0.01 && thrust < drag { 0.0 } else { thrust - drag - fc.abs() * 0.0625 };
        let f = add(add(scale(right, fc as f64), scale(fwd, fx as f64)), scale(up, lz as f64));
        let mut acc = [f[0] / m as f64, f[1] / m as f64, ((f[2] - (m * G) as f64).max(0.0)) / m as f64];
        let mut stop = false;
        if tick {
            // Stop rule (5 Hz only): a deceleration that would reverse the motion within 0.2 s
            // stops the jet (all three velocities 0).
            let (vel, _) = self.speed_at(t);
            let a_fwd = dot(acc, fwd);
            if a_fwd < 0.0 && dot(vel, fwd) + 0.2 * a_fwd < 0.0 {
                acc = add(acc, scale(fwd, -a_fwd));
                stop = true;
            }
            if v > 0.5 {
                self.ground_dir = fwd;
            }
            self.wing = right;
            self.wing_roll = self.roll.sample(t).0;
        }
        for (i, axis) in self.axes.iter_mut().enumerate() {
            if stop {
                let (p, _) = axis.sample(t);
                axis.set_state(t, p, 0.0, acc[i] as f32);
            } else {
                axis.set(t, acc[i] as f32);
            }
        }
    }

    /// Touchdown / lift-off (FUN_005b87d0, §14.6), at the start of every 5 Hz tick.
    fn transitions(&mut self, t: f64) {
        let clear = (self.ground_height + self.gear_clearance) as f64;
        let (z, vz) = self.axes[2].sample(t);
        if !self.on_ground {
            if z > clear {
                return;
            }
            // Touchdown: vz := 0 (acceleration kept), Z onto the ground, aero update (ground branch).
            let (fwd, _, _) = self.attitude(t);
            self.ground_dir = norm([fwd[0], fwd[1], 0.0]);
            self.on_ground = true;
            let a = self.axes[2].accel();
            self.axes[2].set_state(t, clear, 0.0, a);
            self.aero_update();
            return;
        }
        if z > clear && vz > 0.001 {
            // Lift-off: airborne branch; roll angle 0, its rate and target kept.
            self.on_ground = false;
            self.roll.reset_angle(t, 0.0);
            self.aero_update();
            return;
        }
        // Still rolling: keep the wheels on the terrain as it rises or falls under us (the original's
        // runways are flat; our streamed terrain is not — deviation, UNCERTAIN).
        if (z - clear).abs() > 0.01 && vz <= 0.001 {
            let a = self.axes[2].accel();
            self.axes[2].set_state(t, clear, 0.0, a);
        }
    }

    pub fn state(&self) -> State {
        let t = self.t;
        let position = self.position_at(t);
        let (v, speed) = self.speed_at(t);
        let (fwd, right, up) = self.attitude(t);
        let (pitch, roll, heading) = Self::euler(fwd, right);
        let alt = position[2] as f32;
        let mass = self.params.empty_mass + self.fuel.sample(t);
        // On the wheels the load factor is 1 (the ground carries the weight); in the air it is L / (m·g).
        // Display only; the original's ground readout is not traced (UNCERTAIN).
        let g = if self.on_ground { 1.0 } else { self.lift.sample(t) / (mass * G) };
        State {
            time: t,
            position,
            velocity: [v[0] as f32, v[1] as f32, v[2] as f32],
            speed,
            mach: speed / air(alt).sound,
            forward: fwd,
            right,
            up,
            pitch,
            roll,
            heading,
            alpha: self.alpha.sample(t).0 as f32,
            beta: self.beta.sample(t),
            g,
            rpm: self.rpm.sample(t),
            throttle: self.controls.throttle,
            afterburner: self.afterburner,
            thrust_n: self.thrust,
            fuel_kg: self.fuel.sample(t),
            mass_kg: mass,
            stalled: t - self.stall_time < STALL_LATCH,
            buffet: self.buffet,
            over_g: g > self.params.over_g_thresh,
            on_ground: self.on_ground,
        }
    }
}
