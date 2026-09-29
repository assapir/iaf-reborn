//! The original's analytic state "channels" (docs/flight-model.md §0): each
//! stores a base time and a closed-form curve that can be sampled at any time.

use std::f64::consts::PI;

/// Rate-limited ramp toward a target (type A: `FUN_0059fe30` / `FUN_0059feb0`).
#[derive(Debug, Clone, Copy)]
pub struct Ramp {
    t0: f64,
    v0: f32,
    target: f32,
    rate: f32,
    t_end: f32,
    pub min: f32,
    pub max: f32,
}

impl Ramp {
    pub fn new(value: f32, min: f32, max: f32) -> Self {
        Self { t0: 0.0, v0: value, target: value, rate: 0.0, t_end: 0.0, min, max }
    }

    pub fn set(&mut self, now: f64, target: f32, rate: f32) {
        let v = self.sample(now);
        let d = target - v;
        self.t0 = now;
        self.v0 = v;
        self.target = target;
        self.rate = rate.abs() * d.signum();
        self.t_end = if self.rate != 0.0 { d / self.rate } else { f32::INFINITY };
    }

    /// Jump straight to a value.
    pub fn reset(&mut self, now: f64, value: f32) {
        *self = Self { t0: now, v0: value, target: value, rate: 0.0, t_end: 0.0, ..*self };
    }

    pub fn sample(&self, t: f64) -> f32 {
        let tau = ((t - self.t0) as f32).clamp(0.0, 3.5);
        let v = if tau < self.t_end { self.v0 + self.rate * tau } else { self.target };
        v.clamp(self.min, self.max)
    }

    pub fn target(&self) -> f32 {
        self.target
    }
}

fn wrap(a: f64) -> f64 {
    let mut a = (a + PI).rem_euclid(2.0 * PI) - PI;
    if a <= -PI {
        a += 2.0 * PI;
    }
    a
}

/// Acceleration-limited angle (type B: `FUN_005aac90`): the rate accelerates
/// toward a target rate, then the angle continues at that rate.
#[derive(Debug, Clone, Copy)]
pub struct Angle {
    t0: f64,
    pos0: f64,
    rate0: f32,
    target_rate: f32,
    t_end: f32,
    pos_end: f64,
    accel: f32,
    pub start_accel: f32,
    pub stop_accel: f32,
    pub max_rate: f32,
}

impl Angle {
    pub fn new(pos: f64, start_accel: f32, stop_accel: f32, max_rate: f32) -> Self {
        Self { t0: 0.0, pos0: pos, rate0: 0.0, target_rate: 0.0, t_end: 0.0, pos_end: pos, accel: 0.0, start_accel, stop_accel, max_rate }
    }

    /// (angle, rate) at time `t`.
    pub fn sample(&self, t: f64) -> (f64, f32) {
        let tau = ((t - self.t0) as f32).clamp(0.0, 1.1);
        if tau <= self.t_end {
            let pos = self.pos0 + (self.rate0 * tau + 0.5 * self.accel * tau * tau) as f64;
            (wrap(pos), self.rate0 + self.accel * tau)
        } else {
            (wrap(self.pos_end + (self.target_rate * (tau - self.t_end)) as f64), self.target_rate)
        }
    }

    /// Re-base at `now` with angle `pos`, keeping the current rate and target rate.
    pub fn reset_angle(&mut self, now: f64, pos: f64) {
        let target = self.target_rate;
        self.set(now, pos, target);
    }

    /// Re-base at `now` with position `pos` and aim for `target_rate`.
    pub fn set(&mut self, now: f64, pos: f64, target_rate: f32) {
        let (_, rate) = self.sample(now);
        let rate = rate.clamp(-self.max_rate, self.max_rate);
        let target_rate = target_rate.clamp(-self.max_rate, self.max_rate);
        let d = target_rate - rate;
        let mag = if target_rate.abs() > 0.02 * self.max_rate { self.start_accel } else { self.stop_accel };
        let accel = mag * d.signum();
        let t_end = if accel != 0.0 { d / accel } else { 0.0 };
        *self = Self {
            t0: now,
            pos0: pos,
            rate0: rate,
            target_rate,
            t_end,
            pos_end: wrap(pos + (rate * t_end + 0.5 * accel * t_end * t_end) as f64),
            accel,
            ..*self
        };
    }
}

/// Constant-acceleration axis (type C: `FUN_005aab30` / `FUN_005aab50`).
#[derive(Debug, Clone, Copy, Default)]
pub struct Axis {
    p0: f64,
    t0: f64,
    v: f32,
    a: f32,
}

impl Axis {
    pub fn new(p: f64, v: f32) -> Self {
        Self { p0: p, t0: 0.0, v, a: 0.0 }
    }

    /// (position, velocity) at time `t`.
    pub fn sample(&self, t: f64) -> (f64, f32) {
        let tau = ((t - self.t0) as f32).clamp(0.0, 1.1);
        (self.p0 + (self.v * tau + 0.5 * self.a * tau * tau) as f64, self.v + self.a * tau)
    }

    pub fn set(&mut self, now: f64, a: f32) {
        let (p, v) = self.sample(now);
        *self = Self { p0: p, t0: now, v, a };
    }

    /// Current (constant) acceleration.
    pub fn accel(&self) -> f32 {
        self.a
    }

    pub fn set_state(&mut self, now: f64, p: f64, v: f32, a: f32) {
        *self = Self { p0: p, t0: now, v, a };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ramp_reaches_target() {
        let mut r = Ramp::new(0.0, -10.0, 10.0);
        r.set(0.0, 5.0, 2.0);
        assert!((r.sample(1.0) - 2.0).abs() < 1e-5);
        assert!((r.sample(3.0) - 5.0).abs() < 1e-5);
    }

    #[test]
    fn angle_accelerates_then_holds_rate() {
        let mut a = Angle::new(0.0, 4.0, 4.0, 2.0);
        a.set(0.0, 0.0, 2.0);
        let (_, rate) = a.sample(0.25);
        assert!((rate - 1.0).abs() < 1e-5);
        let (_, rate) = a.sample(1.0);
        assert!((rate - 2.0).abs() < 1e-5);
    }
}
