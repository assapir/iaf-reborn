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
}

impl Aircraft {
    /// Airborne start at `position` (ENU), `heading` (rad, clockwise from north), `speed` (m/s).
    pub fn new(params: Params, envelope: Envelope, position: V3, heading: f32, speed: f32) -> Self {
        let p = &params;
        // Load-time derived lift slope (§1): CL at α=0 and dCL/dα from the 1 g / max g minimum speeds.
        let alt = 330.0;
        let v1 = envelope.vmin(alt, 1.0);
        let vg = envelope.vmin(alt, p.max_g_m1 + 1.0);
        let (qs1, qs2) = (q_s(alt, v1, p.wing_area), q_s(alt, vg, p.wing_area));
        let w = p.empty_mass * G;
        let cl0 = w / qs2;
        let cl_alpha = (w - qs1 * cl0) / (qs1 * p.max_pos_alpha);
        // Stick-centre shift line (P.170 / P.174).
        let stick_centre_v = envelope.vmin(3048.0, p.start_move_stick_center_g);
        let stick_centre_a = (p.map_center_stick - 1.0) / (10.0 - stick_centre_v);
        let stick_centre_b = p.map_center_stick - stick_centre_a * 10.0;

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
            params,
            envelope,
        };
        ac.aero_update();
        ac.accel_update();
        ac.next_aero = AERO_PERIOD;
        ac.next_accel = ACCEL_PERIOD;
        ac
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
        self.ground_contact();
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
    fn thrust_at(&self, alt: f32, mach: f32) -> (f32, f32, f32, u8) {
        let p = &self.params;
        let thr = self.controls.throttle;
        if self.fuel.sample(self.t) <= 1e-5 {
            return (0.0, 0.0, 0.0, 0);
        }
        let (k, stage) = if p.has_afterburner {
            if thr < 0.75 {
                (0.05 + 0.743_243_2 * thr, 0)
            } else if thr < 0.875 {
                (0.875, 1)
            } else {
                (1.0, 2)
            }
        } else {
            ((thr - 0.2) * 1.25, 0)
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
        (thrust.max(0.0), rpm, ff, stage)
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
        let (thrust, rpm, ff, stage) = self.thrust_at(alt, mach);
        let fuel = self.fuel.sample(t);
        let mass = p.empty_mass + fuel;
        let (fwd, right, _) = self.attitude(t);
        let (_, roll, _) = Self::euler(fwd, right);
        let (vel, _) = self.speed_at(t);
        let gamma = if v > 1.0 { (vel[2] / v as f64).clamp(-1.0, 1.0).asin() as f32 } else { 0.0 };
        let alpha_now = self.alpha.sample(t).0 as f32;

        // Commanded load factor (§4.2).
        let latched = t - self.stall_time < STALL_LATCH;
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
        if p.use_flight_limits && !latched && !self.on_ground {
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
                    self.buffet = lim <= p.start_vibs_g && g > 0.0;
                }
            }
        }
        if stalled {
            self.stall_time = t;
        }
        let lift_noflap = g * mass * G;
        let mut lift = lift_noflap;
        let flaps = self.flaps.sample(t);
        if v < 125.0 {
            lift += lift_noflap.abs() * p.flaps_lift_coef * flaps * 3.415_883_8;
        }
        if self.on_ground {
            lift *= 0.5;
            if !((v > 74.53 || c.stick_y > 0.5) && c.gear_down) {
                lift = 0.0;
            }
        }

        // Drag (§4.3).
        let alpha = if stalled { 0.0 } else { self.lift_coefficient_alpha(lift_noflap, qs) };
        let n = lift / (mass * G);
        let cl = if qs > 0.0 { alpha.cos() * mass * n * G / qs } else { 0.0 };
        let k = 1.0 / (std::f32::consts::PI * p.wing_span * p.wing_span / p.wing_area * 0.85);
        let brakes = self.speed_brakes.sample(t);
        let mut cd = p.plane_di + k * cl * cl + p.flaps_di * flaps * 3.415_883_8;
        if c.gear_down {
            cd += p.gear_di;
        }
        let mut drag = if self.on_ground { cd * qs } else { (cd + p.speed_brakes_di * brakes) * qs };
        if self.on_ground {
            let mu = if c.gear_down { brakes * p.wheel_brake_di } else { 20.0 };
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

        let beta_cmd = c.rudder * p.max_beta;
        let beta_rate = if v >= 375.0 { p.beta_rate } else { (p.beta_rate * 0.0025 * v).max(0.25 * p.beta_rate) };
        self.beta.set(t, beta_cmd, beta_rate);
    }

    /// 5 Hz update: α target, forces, new constant accelerations (§5).
    fn accel_update(&mut self) {
        let t = self.t;
        let p = &self.params;
        let pos = self.position_at(t);
        let alt = pos[2] as f32;
        let (_, v) = self.speed_at(t);
        let qs = q_s(alt, v, p.wing_area);
        let lift = self.lift.sample(t);
        let lift_aoa = self.lift_aoa.sample(t);

        // Alpha dynamics toward the target implied by lift.
        let alpha_target = if qs > 0.0 {
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
        if self.on_ground && acc[2] < 0.0 {
            acc[2] = 0.0;
        }
        for (axis, a) in self.axes.iter_mut().zip(acc) {
            axis.set(t, a as f32);
        }
        if self.on_ground {
            let (p, _) = self.axes[2].sample(t);
            self.axes[2].set_state(t, p, 0.0, acc[2] as f32);
        }

        // Re-base the wing vector on the current attitude (§5, §6).
        self.wing = right;
        self.wing_roll = self.roll.sample(t).0;
    }

    fn ground_contact(&mut self) {
        let t = self.t;
        let (z, vz) = self.axes[2].sample(t);
        if z <= self.ground_height as f64 {
            if !self.on_ground {
                self.on_ground = true;
                let (x, vx) = self.axes[0].sample(t);
                let (y, vy) = self.axes[1].sample(t);
                self.axes[0].set_state(t, x, vx, 0.0);
                self.axes[1].set_state(t, y, vy, 0.0);
                self.aero_update();
            }
            self.axes[2].set_state(t, self.ground_height as f64, vz.max(0.0), 0.0);
        } else if self.on_ground && z > self.ground_height as f64 + 1.0 {
            self.on_ground = false;
            self.aero_update();
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
        let g = self.lift.sample(t) / (mass * G);
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
