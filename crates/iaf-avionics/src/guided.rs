//! One guided weapon in flight (class 0x19: the TV missile 640, the laser bomb 650; docs/weapons.md §12): the
//! original's guided motion (motion vtable 0x601f70 / 0x601ed0, config `FUN_00563d30`, start `FUN_00563f90`, update
//! `FUN_005643a0` every 0.5 s, errors `FUN_00564fe0`, aim `FUN_00469f00`, status `FUN_004d8030`, time left
//! `FUN_00564f10`, DLZ `FUN_005641c0`). It flies to an aim POINT (the target unit is ignored).
//!
//! World frame X east, Y north, Z up, metres, sim seconds. Between updates p0 + v0·dt + ½a·dt²; each update re-bases
//! and sets a new acceleration.

use crate::vec3::Vec3;
use std::f64::consts::{PI, TAU};

/// Update period (0x60cf48 = −0.5).
pub const PERIOD: f64 = 0.5;
/// Far phase pitch law (0x60cf58 = −24°, 0x60cf5c = 40°) and gravity (0xc11ce560).
const PITCH_BIAS: f64 = 0.41887903;
const PITCH_CAP: f64 = 0.69813168;
const G: f64 = 9.806;
/// The end / phase checks start at age 0.001 s (0x60cf60); time left is capped at 280 s (0x60cf70).
const CHECK_AGE: f64 = 0.001;
const TIME_LEFT_MAX: f64 = 280.0;
/// The DLZ's dive angle per degree (0x60cf28).
const DEG: f64 = 0.01745329;
/// Without terrain the ground is at 0.1 m.
const NO_TERRAIN_Z: f64 = 0.1;

/// The weapons.ibx fields (`FUN_00563d30`; the ibx comments name their real use) and the _debugParam values.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GuidedMotion {
    /// _absAcceleration (+0x78): the engine, for _timeAcceleration (+0x88).
    pub engine: f64,
    pub t_acc: f64,
    /// _timeConstVel (+0x74): the squared horizontal distance of the switch to the near phase.
    pub switch_near2: f64,
    /// _absDeceleration (+0x7c): the turn gain.
    pub turn: f64,
    /// _timeDecceleration (+0xa0) / _spiralAccelBeta (+0xa8): the up / down acceleration.
    pub up_acc: f64,
    pub down_acc: f64,
    /// _spiralAccel (+0x118): the end time.
    pub end_time: f64,
    /// _absReleaseAcceleration (+0x120) / _timeRelease (+0x11c): the maximum velocity and its damp.
    pub max_vel: f64,
    pub damp: f64,
    /// _timeConstOrientation (+0x98).
    pub t_co: f64,
    /// _rollRate (+0xc8): the maximum up angle (rad).
    pub max_up: f64,
    /// _debugParam013: the burst snaps to the aim point within it.
    pub burst_dist: f64,
    /// _debugParam014: the terminal phase inside it.
    pub terminal_dist: f64,
    /// _debugParam011: the DLZ's dive angle (degrees).
    pub dive_deg: f64,
}

impl Default for GuidedMotion {
    fn default() -> Self {
        GuidedMotion {
            engine: 10.0,
            t_acc: 2.0,
            switch_near2: 3.0e7,
            turn: 150.0,
            up_acc: 20.0,
            down_acc: 70.0,
            end_time: 420.0,
            max_vel: 300.0,
            damp: 8.0,
            t_co: 2.0,
            max_up: 0.0179065,
            burst_dist: 200.0,
            terminal_dist: 200.0,
            dive_deg: 70.0,
        }
    }
}

impl GuidedMotion {
    /// The DLZ range (`FUN_005641c0`) from `agl` above the terrain (at least 0) at velocity `vel`: the fall time t of
    /// a = 9.806 − dive·(π/180)·up accel (at least 1) from the height, the larger root of (−vz_down ± √(vz_down² +
    /// 2ah)) / (2a) (UNCERTAIN: 2a, not a); the engine's distance over min(t, tAcc), then the glide at d1 = the
    /// distance flown so far capped at the maximum velocity (original bug: a distance used as a speed) for min(t −
    /// tAcc, end time − tAcc). The DLZ is [range, range].
    pub fn dlz_range(&self, agl: f64, vel: Vec3) -> f64 {
        let h = agl.max(0.0);
        let vd = -vel.z;
        let a = (G - self.dive_deg * DEG * self.up_acc).max(1.0);
        let disc = vd * vd + 2.0 * a * h;
        let t = if disc >= 0.0 {
            let r = disc.sqrt();
            (-(vd + r) / (2.0 * a)).max((r - vd) / (2.0 * a))
        } else {
            h
        };
        let tt = t.min(self.t_acc);
        let mut d1 = tt * vel.x.hypot(vel.y);
        let mut range = d1 + 0.5 * tt * tt * self.engine;
        if t > self.t_acc {
            d1 = d1.min(self.max_vel);
            range += (t - self.t_acc).min(self.end_time - self.t_acc) * d1;
        }
        range
    }
}

/// The flight phase (+0x70).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    /// 0: climb / glide law with gravity.
    Far,
    /// 1: near.
    Near,
    /// 2: terminal, the aim is frozen.
    Terminal,
}

#[derive(Clone, Debug)]
pub struct Guided {
    motion: GuidedMotion,
    /// +0xb0.
    aim: Vec3,
    phase: Phase,
    t_start: f64,
    t0: f64,
    p0: Vec3,
    v0: Vec3,
    acc: Vec3,
    last_pos: Vec3,
    ended: bool,
    next_update: f64,
}

impl Guided {
    /// `FUN_00563d30` + `FUN_00563f90` from the release point / velocity toward `aim`. The first update runs with the
    /// phase the constructor left (UNCERTAIN, uninitialised; taken Far) and no terrain; the start sets Far after it.
    /// UNCERTAIN: the release push (+0x80 along +0xbc, while age < +0x90) reads fields nothing sets: taken as none.
    pub fn launch(motion: GuidedMotion, now: f64, pos: Vec3, vel: Vec3, aim: Vec3) -> Self {
        let mut g = Guided {
            motion,
            aim,
            phase: Phase::Far,
            t_start: now,
            t0: now,
            p0: pos,
            v0: vel,
            acc: Vec3::ZERO,
            last_pos: pos,
            ended: false,
            next_update: now,
        };
        g.update(now, &|_| None);
        g.phase = Phase::Far;
        g
    }

    pub fn aim(&self) -> Vec3 {
        self.aim
    }
    pub fn phase(&self) -> Phase {
        self.phase
    }
    pub fn ended(&self) -> bool {
        self.ended
    }
    pub fn last_pos(&self) -> Vec3 {
        self.last_pos
    }
    pub fn next_update(&self) -> f64 {
        self.next_update
    }

    pub fn position(&self, now: f64) -> Vec3 {
        let dt = now - self.t0;
        self.p0 + self.v0 * dt + self.acc * (0.5 * dt * dt)
    }

    pub fn velocity(&self, now: f64) -> Vec3 {
        self.v0 + self.acc * (now - self.t0)
    }

    /// `FUN_00469f00`: a new aim point, ignored in the terminal phase.
    pub fn set_aim(&mut self, p: Vec3) {
        if self.phase != Phase::Terminal {
            self.aim = p;
        }
    }

    /// `FUN_00564f10`: |aim − position| / speed, at most 280 s.
    pub fn time_left(&self, now: f64) -> f64 {
        let s = self.velocity(now).length();
        if s > 0.0 { (self.position(now).distance(self.aim) / s).min(TIME_LEFT_MAX) } else { TIME_LEFT_MAX }
    }

    /// The heading / pitch errors toward the aim (`FUN_00564fe0`): heading = atan2(dx, dy) − the velocity's heading,
    /// wrapped only above π (original quirk: below −π it turns the long way); the pitch target asin(LOS z), in the
    /// far phase the maximum up angle, never above it; its error wrapped the same way.
    pub fn errors(&self, p: Vec3, v: Vec3) -> (f64, f64) {
        let u = (self.aim - p).try_normalize().unwrap_or(Vec3::NORTH);
        let wrap = |e: f64| if e > PI { e - TAU } else { e };
        let pitch = v.try_normalize().map_or(0.0, |d| d.z.clamp(-1.0, 1.0).asin());
        let target_pitch = if self.phase == Phase::Far { self.motion.max_up } else { u.z.clamp(-1.0, 1.0).asin() };
        (wrap(u.x.atan2(u.y) - v.x.atan2(v.y)), wrap(target_pitch.min(self.motion.max_up) - pitch))
    }

    /// One update (`FUN_005643a0`). True when the weapon ends: it bursts at `last_pos()`.
    pub fn update(&mut self, now: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
        let m = self.motion;
        let age = now - self.t_start;
        let mut p = self.position(now);
        let v = self.velocity(now);
        self.v0 = v;
        self.t0 = now;
        self.acc = Vec3::ZERO;
        let gh = terrain(p).unwrap_or(NO_TERRAIN_Z);
        let below = p.z <= gh;
        if below {
            p.z = gh;
        } else {
            self.acc = self.steer(p, v, age);
        }
        self.p0 = p;
        self.last_pos = p;
        if age < CHECK_AGE {
            self.next_update = now + PERIOD;
            return false;
        }
        let d2 = (self.aim.x - p.x).powi(2) + (self.aim.y - p.y).powi(2);
        if d2 > m.switch_near2 {
            self.phase = Phase::Far;
        } else if d2 < m.switch_near2 && d2 > m.terminal_dist * m.terminal_dist {
            self.phase = Phase::Near;
        }
        if d2 < m.terminal_dist * m.terminal_dist {
            self.phase = Phase::Terminal;
        }
        if (age > m.end_time || below) && age >= m.t_co {
            self.ended = true;
            if p.distance(self.aim) < m.burst_dist {
                self.last_pos = self.aim;
            }
            return true;
        }
        self.next_update = now + PERIOD;
        false
    }

    /// The acceleration: the turn toward the aim along the right axis (D × U, roll 0); the far phase's climb / glide
    /// with gravity, the near / terminal pitch correction; the engine for tAcc, then (original bug) the damping
    /// product dropped and the unit axis added (+1 m/s²) above the maximum velocity.
    fn steer(&self, p: Vec3, v: Vec3, age: f64) -> Vec3 {
        let m = self.motion;
        let sp = v.length();
        let h = v.x.atan2(v.y);
        let d = v.try_normalize().unwrap_or(Vec3::new(h.sin(), h.cos(), 0.0));
        let (eh, ep) = self.errors(p, v);
        let mut acc = Vec3::new(h.cos(), -h.sin(), 0.0) * (m.turn * eh);
        acc += match self.phase {
            Phase::Far => {
                let x = (ep + PITCH_BIAS).min(PITCH_CAP);
                let climb = if x > 0.0 { m.up_acc } else { m.down_acc };
                Vec3::UP * (climb * x - G)
            }
            Phase::Near | Phase::Terminal => Vec3::UP * (2.0 * m.down_acc * ep),
        };
        if age < m.t_acc {
            acc += d * m.engine;
        } else if (m.max_vel - sp) * m.damp < 0.0 {
            acc += d;
        }
        acc
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dlz_level_at_1000_m() {
        // a = 9.806 − 70·(π/180)·20 < 1 → 1; t = √2000 / 2; the glide's "speed" d1 = 2 s · 250 = 500.
        let r = GuidedMotion::default().dlz_range(1000.0, Vec3::new(0.0, 250.0, 0.0));
        let t = 2000f64.sqrt() / 2.0;
        assert!((r - (520.0 + (t - 2.0) * 300.0)).abs() < 1.0, "{r}");
    }

    #[test]
    fn flies_to_the_aim_and_bursts_there() {
        let aim = Vec3::new(0.0, 8000.0, 0.0);
        let mut g = Guided::launch(GuidedMotion::default(), 0.0, Vec3::new(0.0, 0.0, 1000.0), Vec3::new(0.0, 250.0, 0.0), aim);
        assert_eq!(g.phase(), Phase::Far);
        let mut t = 0.0;
        while !g.update(t, &|_| Some(0.0)) {
            t = g.next_update();
            assert!(t < 120.0, "never ended");
        }
        assert!(g.last_pos().distance(aim) < 1.0, "burst {:?} at {t} s", g.last_pos());
    }
}
