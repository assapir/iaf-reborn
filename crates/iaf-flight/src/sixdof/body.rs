//! A rigid body in six degrees of freedom: TP-1538 appendix B's equations of motion (body axes, the xz product of
//! inertia, the engine's angular momentum) with the attitude kept as a unit quaternion, so no attitude is singular
//! (the report itself "used quaternions to allow continuity of attitude motions"). Flat earth, NED world frame.

use super::{FT, G, LB, SLUG_FT2};
use crate::Vec3;

/// Mass, inertia and reference geometry of a jet, SI units.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Airframe {
    /// Mass, kg.
    pub mass: f64,
    /// Moments of inertia about the body x, y, z axes and the xz product of inertia (∫xz dm), kg·m².
    pub ix: f64,
    pub iy: f64,
    pub iz: f64,
    pub ixz: f64,
    /// Wing area (m²), span (m), mean aerodynamic chord (m).
    pub s: f64,
    pub b: f64,
    pub cbar: f64,
    /// The data's reference centre of gravity and the flight's, fractions of the chord.
    pub xcg_ref: f64,
    pub xcg: f64,
    /// The engine's angular momentum along the body x axis, kg·m²/s.
    pub h_engine: f64,
}

impl Airframe {
    /// TP-1538 Table I (p. 43): 20,500 lb; inertia 9,496 / 55,814 / 63,100 / 982 slug-ft²; span 30 ft, area 300 ft²,
    /// chord 11.32 ft; reference c.g. 0.35 c̄ (also the report's nominal flight c.g.). Engine angular momentum
    /// 160 slug-ft²/s: appendix B, "Engine Simulation" (p. 40). The report's own SI values are these, rounded.
    pub const TP1538: Airframe = Airframe {
        mass: 20_500.0 * LB,
        ix: 9_496.0 * SLUG_FT2,
        iy: 55_814.0 * SLUG_FT2,
        iz: 63_100.0 * SLUG_FT2,
        ixz: 982.0 * SLUG_FT2,
        s: 300.0 * FT * FT,
        b: 30.0 * FT,
        cbar: 11.32 * FT,
        xcg_ref: 0.35,
        xcg: 0.35,
        h_engine: 160.0 * SLUG_FT2,
    };

    /// J⁻¹·m for the inertia tensor J = [[Ix, 0, −Ixz], [0, Iy, 0], [−Ixz, 0, Iz]].
    fn inv_inertia(&self, m: Vec3) -> Vec3 {
        let gamma = self.ix * self.iz - self.ixz * self.ixz;
        Vec3::new((self.iz * m.x + self.ixz * m.z) / gamma, m.y / self.iy, (self.ixz * m.x + self.ix * m.z) / gamma)
    }

    /// J·ω.
    pub fn angular_momentum(&self, w: Vec3) -> Vec3 {
        Vec3::new(self.ix * w.x - self.ixz * w.z, self.iy * w.y, self.iz * w.z - self.ixz * w.x)
    }
}

/// A unit quaternion (w, x, y, z) rotating body vectors into the world frame.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Quat {
    pub w: f64,
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

impl Quat {
    pub const IDENTITY: Quat = Quat { w: 1.0, x: 0.0, y: 0.0, z: 0.0 };

    /// From the Euler angles bank φ, pitch θ, heading ψ (rad; the aerospace z-y-x order).
    pub fn from_euler(phi: f64, theta: f64, psi: f64) -> Quat {
        let (sr, cr) = (phi / 2.0).sin_cos();
        let (sp, cp) = (theta / 2.0).sin_cos();
        let (sy, cy) = (psi / 2.0).sin_cos();
        Quat {
            w: cr * cp * cy + sr * sp * sy,
            x: sr * cp * cy - cr * sp * sy,
            y: cr * sp * cy + sr * cp * sy,
            z: cr * cp * sy - sr * sp * cy,
        }
    }

    /// (φ, θ, ψ), rad. Only this read-out is singular at θ = ±90°; the quaternion itself is not.
    pub fn euler(self) -> (f64, f64, f64) {
        let Quat { w, x, y, z } = self;
        let phi = (2.0 * (w * x + y * z)).atan2(1.0 - 2.0 * (x * x + y * y));
        let theta = (2.0 * (w * y - x * z)).clamp(-1.0, 1.0).asin();
        let psi = (2.0 * (w * z + x * y)).atan2(1.0 - 2.0 * (y * y + z * z));
        (phi, theta, psi)
    }

    /// Body → world.
    pub fn rotate(self, v: Vec3) -> Vec3 {
        let u = Vec3::new(self.x, self.y, self.z);
        let t = u.cross(v) * 2.0;
        v + t * self.w + u.cross(t)
    }

    /// World → body.
    pub fn rotate_inv(self, v: Vec3) -> Vec3 {
        Quat { w: self.w, x: -self.x, y: -self.y, z: -self.z }.rotate(v)
    }

    pub fn norm(self) -> f64 {
        (self.w * self.w + self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
    }

    fn scaled(self, k: f64) -> Quat {
        Quat { w: self.w * k, x: self.x * k, y: self.y * k, z: self.z * k }
    }

    fn plus(self, o: Quat) -> Quat {
        Quat { w: self.w + o.w, x: self.x + o.x, y: self.y + o.y, z: self.z + o.z }
    }

    /// q̇ = ½ q ⊗ (0, ω), ω in body axes.
    fn rate(self, w: Vec3) -> Quat {
        Quat {
            w: -0.5 * (self.x * w.x + self.y * w.y + self.z * w.z),
            x: 0.5 * (self.w * w.x + self.y * w.z - self.z * w.y),
            y: 0.5 * (self.w * w.y + self.z * w.x - self.x * w.z),
            z: 0.5 * (self.w * w.z + self.x * w.y - self.y * w.x),
        }
    }
}

/// The rigid body's state.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Body {
    /// Position, world NED, m.
    pub pos: Vec3,
    /// Velocity in body axes (u, v, w), m/s.
    pub vel: Vec3,
    /// Attitude, body → world.
    pub att: Quat,
    /// Angular velocity in body axes (p, q, r), rad/s.
    pub omega: Vec3,
}

/// The integrator's largest step, s: the game steps the model once per rendered frame (variable, ~1/60 s), so a
/// frame is cut into equal steps of at most this (inferred: well inside RK4's stability for the jet's fastest
/// modes, the roll mode's ~0.15 s and the report's 0.0495 s actuators).
pub const MAX_STEP: f64 = 1.0 / 120.0;

/// The longest frame [`Body::step`] integrates, s: a longer hitch is cut to this, as `IafFlight::step` does for the
/// original model (`dt.clamp(0.0, 0.25)`, crates/iaf-godot/src/flight.rs).
pub const MAX_FRAME: f64 = 0.25;

impl Body {
    /// At `pos` with attitude `att`, moving at `vel` (body axes), with no rotation.
    pub fn new(pos: Vec3, vel: Vec3, att: Quat) -> Body {
        Body { pos, vel, att, omega: Vec3::ZERO }
    }

    pub fn speed(&self) -> f64 {
        self.vel.length()
    }

    /// Angle of attack tan⁻¹(w/u), rad (appendix B).
    pub fn alpha(&self) -> f64 {
        self.vel.z.atan2(self.vel.x)
    }

    /// Sideslip sin⁻¹(v/V), rad (appendix B).
    pub fn beta(&self) -> f64 {
        let v = self.speed();
        if v > 0.0 { (self.vel.y / v).clamp(-1.0, 1.0).asin() } else { 0.0 }
    }

    /// The state's time derivative under the body-axis force `f` (N, without gravity) and moment `m` (N·m).
    pub fn derivative(&self, af: &Airframe, f: Vec3, m: Vec3) -> Body {
        let w = self.omega;
        let g_body = self.att.rotate_inv(Vec3::new(0.0, 0.0, G));
        let vel_dot = f * (1.0 / af.mass) + g_body - w.cross(self.vel);
        let h = af.angular_momentum(w) + Vec3::new(af.h_engine, 0.0, 0.0);
        let omega_dot = af.inv_inertia(m - w.cross(h));
        let q = self.att.rate(w);
        Body { pos: self.att.rotate(self.vel), vel: vel_dot, att: q, omega: omega_dot }
    }

    fn plus(&self, d: &Body, k: f64) -> Body {
        Body {
            pos: self.pos + d.pos * k,
            vel: self.vel + d.vel * k,
            att: self.att.plus(d.att.scaled(k)),
            omega: self.omega + d.omega * k,
        }
    }

    /// One classic fourth-order Runge-Kutta step of `dt` s. `forces` gives the body-axis force (without gravity) and
    /// moment at a state. The quaternion is renormalised after the step.
    pub fn rk4(&mut self, af: &Airframe, dt: f64, forces: &mut impl FnMut(&Body) -> (Vec3, Vec3)) {
        let d = |b: &Body, forces: &mut dyn FnMut(&Body) -> (Vec3, Vec3)| {
            let (f, m) = forces(b);
            b.derivative(af, f, m)
        };
        let k1 = d(self, forces);
        let k2 = d(&self.plus(&k1, dt / 2.0), forces);
        let k3 = d(&self.plus(&k2, dt / 2.0), forces);
        let k4 = d(&self.plus(&k3, dt), forces);
        let mut next = self.plus(&k1, dt / 6.0);
        next = next.plus(&k2, dt / 3.0);
        next = next.plus(&k3, dt / 3.0);
        next = next.plus(&k4, dt / 6.0);
        next.att = next.att.scaled(1.0 / next.att.norm());
        *self = next;
    }

    /// Advances `dt` s (a frame, at most [`MAX_FRAME`]) in equal RK4 steps of at most [`MAX_STEP`]. A frame time that
    /// is not a positive number leaves the state as it is.
    pub fn step(&mut self, af: &Airframe, dt: f64, mut forces: impl FnMut(&Body) -> (Vec3, Vec3)) {
        if dt.is_nan() || dt <= 0.0 {
            return;
        }
        let dt = dt.min(MAX_FRAME);
        let n = (dt / MAX_STEP).ceil().max(1.0);
        for _ in 0..n as usize {
            self.rk4(af, dt / n, &mut forces);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const AF: Airframe = Airframe::TP1538;

    /// `t` s as equal frames of at most [`MAX_FRAME`].
    fn fly(b: &mut Body, t: f64, f: impl Fn(&Body) -> (Vec3, Vec3) + Copy) {
        let n = (t / MAX_FRAME).ceil();
        for _ in 0..n as usize {
            b.step(&AF, t / n, f);
        }
    }

    fn close(a: f64, b: f64, tol: f64) -> bool {
        (a - b).abs() <= tol
    }

    #[test]
    fn euler_round_trip() {
        for &(p, t, y) in &[(0.3, -0.4, 2.0), (-2.5, 1.2, -0.7), (0.0, 0.0, 3.0)] {
            let (p2, t2, y2) = Quat::from_euler(p, t, y).euler();
            assert!(close(p, p2, 1e-12) && close(t, t2, 1e-12) && close(y, y2, 1e-12), "{p2} {t2} {y2}");
        }
        // Pitched 30° up, heading east: the nose points east and up (NED: +y, −z).
        let n = Quat::from_euler(0.0, 30f64.to_radians(), 90f64.to_radians()).rotate(Vec3::new(1.0, 0.0, 0.0));
        assert!(close(n.x, 0.0, 1e-12) && close(n.y, 0.866_025, 1e-6) && close(n.z, -0.5, 1e-12), "{n:?}");
    }

    #[test]
    fn free_fall() {
        let mut b = Body::new(Vec3::ZERO, Vec3::ZERO, Quat::from_euler(0.4, 0.2, 1.0));
        fly(&mut b, 3.0, |_| (Vec3::ZERO, Vec3::ZERO));
        assert!(close(b.pos.z, 0.5 * G * 9.0, 1e-9), "{:?}", b.pos);
        assert!(close(b.pos.x, 0.0, 1e-9) && close(b.pos.y, 0.0, 1e-9));
        assert!(close(b.att.rotate(b.vel).z, G * 3.0, 1e-9));
    }

    #[test]
    fn steady_turn_kinematics() {
        // Constant yaw rate r with the velocity along the nose and a centripetal side force: a circle of radius V/r.
        let (v, r) = (100.0, 0.1);
        let mut b = Body::new(Vec3::ZERO, Vec3::new(v, 0.0, 0.0), Quat::IDENTITY);
        b.omega = Vec3::new(0.0, 0.0, r);
        // Gravity cancelled by an up force; the turn's centripetal force m·V·r to the right (+y).
        let f = Vec3::new(0.0, AF.mass * v * r, -AF.mass * G);
        // Constant yaw rate: the moment that holds r against the engine's gyroscopic and the xz coupling.
        let m = b.omega.cross(AF.angular_momentum(b.omega) + Vec3::new(AF.h_engine, 0.0, 0.0));
        let period = std::f64::consts::TAU / r;
        fly(&mut b, period, |_| (f, m));
        assert!(b.pos.length() < 1e-3, "back at the start after one turn: {:?}", b.pos);
        let (_, _, psi) = b.att.euler();
        assert!(close(psi.sin(), 0.0, 1e-6), "{psi}");
    }

    #[test]
    fn loop_through_vertical() {
        // A constant pitch rate takes the attitude through ±90° (no gimbal lock) and back to level after 2π / q.
        let q = 0.5;
        let mut b = Body::new(Vec3::ZERO, Vec3::new(100.0, 0.0, 0.0), Quat::from_euler(0.0, 0.0, 0.3));
        b.omega = Vec3::new(0.0, q, 0.0);
        let start = b.att;
        let hold = |b: &Body| {
            let g = b.att.rotate_inv(Vec3::new(0.0, 0.0, G));
            (g * -AF.mass, b.omega.cross(AF.angular_momentum(b.omega) + Vec3::new(AF.h_engine, 0.0, 0.0)))
        };
        fly(&mut b, std::f64::consts::FRAC_PI_2 / q, hold);
        let (_, theta, _) = b.att.euler();
        assert!(close(theta, std::f64::consts::FRAC_PI_2, 1e-6), "vertical: {theta}");
        fly(&mut b, 3.0 * std::f64::consts::FRAC_PI_2 / q, hold);
        // q and −q are the same attitude (a full turn flips the quaternion's sign).
        let dot = b.att.w * start.w + b.att.x * start.x + b.att.y * start.y + b.att.z * start.z;
        assert!(close(dot.abs(), 1.0, 1e-9), "{:?} vs {start:?}", b.att);
    }

    #[test]
    fn torque_free_tumble_conserves() {
        // No force, no moment: kinetic energy and the world-frame angular momentum stay constant, the quaternion
        // stays unit, through 60 s of tumbling with the xz coupling and the engine's momentum.
        let mut b = Body::new(Vec3::ZERO, Vec3::ZERO, Quat::from_euler(0.2, -0.3, 0.5));
        b.omega = Vec3::new(2.0, 0.7, -0.4);
        let energy = |b: &Body| 0.5 * b.omega.dot(AF.angular_momentum(b.omega));
        let momentum = |b: &Body| b.att.rotate(AF.angular_momentum(b.omega) + Vec3::new(AF.h_engine, 0.0, 0.0));
        let (e0, h0) = (energy(&b), momentum(&b));
        let no_g = |b: &Body| (b.att.rotate_inv(Vec3::new(0.0, 0.0, -G)) * AF.mass, Vec3::ZERO);
        for _ in 0..3600 {
            b.step(&AF, 1.0 / 60.0, no_g);
        }
        let (e1, h1) = (energy(&b), momentum(&b));
        assert!(((e1 - e0) / e0).abs() < 1e-7, "energy {e0} → {e1}");
        assert!((h1 - h0).length() / h0.length() < 1e-7, "momentum {h0:?} → {h1:?}");
        assert!(close(b.att.norm(), 1.0, 1e-12));
        assert!(b.pos.length() < 1e-9, "{:?}", b.pos);
    }

    #[test]
    fn spin_about_principal_axis_is_steady() {
        // Pure pitch rate: y is a principal axis; without the engine's momentum the rate stays put.
        let af = Airframe { h_engine: 0.0, ..AF };
        let mut b = Body::new(Vec3::ZERO, Vec3::ZERO, Quat::IDENTITY);
        b.omega = Vec3::new(0.0, 1.0, 0.0);
        let no_g = |b: &Body| (b.att.rotate_inv(Vec3::new(0.0, 0.0, -G)) * af.mass, Vec3::ZERO);
        for _ in 0..40 {
            b.step(&af, 0.25, no_g);
        }
        assert!((b.omega - Vec3::new(0.0, 1.0, 0.0)).length() < 1e-12, "{:?}", b.omega);
        // With it, pitching makes the engine's gyroscopic moment yaw the jet: appendix B's + H q / Iz in its yaw
        // equation, which also holds Ixz ṗ; solved for both, ṙ = Ix H q / Γ and ṗ = Ixz H q / Γ (Γ = Ix Iz − Ixz²).
        let mut b = Body::new(Vec3::ZERO, Vec3::ZERO, Quat::IDENTITY);
        b.omega = Vec3::new(0.0, 1.0, 0.0);
        let d = b.derivative(&AF, Vec3::ZERO, Vec3::ZERO);
        let gamma = AF.ix * AF.iz - AF.ixz * AF.ixz;
        assert!(close(d.omega.z, AF.ix * AF.h_engine / gamma, 1e-12), "{:?}", d.omega);
        assert!(close(d.omega.x, AF.ixz * AF.h_engine / gamma, 1e-12));
    }

    #[test]
    fn bad_and_long_frames() {
        let mk = || Body::new(Vec3::ZERO, Vec3::new(150.0, 0.0, 0.0), Quat::IDENTITY);
        let f = |_: &Body| (Vec3::ZERO, Vec3::ZERO);
        for dt in [f64::NAN, f64::NEG_INFINITY, -1.0, 0.0] {
            let mut b = mk();
            b.step(&AF, dt, f);
            assert_eq!(b, mk(), "{dt}");
        }
        // A 30 s hitch or an infinite frame is one 0.25 s frame.
        let (mut long, mut inf, mut quarter) = (mk(), mk(), mk());
        long.step(&AF, 30.0, f);
        inf.step(&AF, f64::INFINITY, f);
        quarter.step(&AF, MAX_FRAME, f);
        assert_eq!(long, quarter);
        assert_eq!(inf, quarter);
    }

    #[test]
    fn frame_split() {
        // One 0.05 s frame is six 1/120 s steps; equal to stepping them one by one.
        let mk = || {
            let mut b = Body::new(Vec3::ZERO, Vec3::new(150.0, 3.0, 10.0), Quat::from_euler(0.1, 0.05, 0.0));
            b.omega = Vec3::new(0.3, 0.1, -0.05);
            b
        };
        let f = |b: &Body| (b.vel * -50.0, b.omega * -1e4);
        let (mut a, mut c) = (mk(), mk());
        a.step(&AF, 0.05, f);
        let mut g = f;
        for _ in 0..6 {
            c.rk4(&AF, 0.05 / 6.0, &mut g);
        }
        assert_eq!(a, c);
    }
}
