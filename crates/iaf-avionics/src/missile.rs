//! One homing weapon in flight (class 0x18: IR 570 / 580, HARM 590, radar 600 / 610, Maverick 635, the SAMs
//! 620 / 630; docs/weapons.md §5, §11): the original's chase motion (`FUN_00561c30` fields, `FUN_00561ef0` start,
//! `FUN_005627e0` update every 0.1 s, `FUN_00563b70` / `FUN_00563ad0` aim, `FUN_005622e0` retarget, `FUN_005624f0`
//! DLZ). Launcher independent (the player's or an AI's).
//!
//! World frame X east, Y north, Z up, metres, sim seconds. Between updates the motion is p0 + v0·dt + ½a·dt² (no
//! gravity, no speed cap); each update re-bases and adds the steering acceleration.

use crate::vec3::Vec3;
use std::f64::consts::FRAC_PI_2;

/// Update period (0x60ced8 = −0.1).
pub const PERIOD: f64 = 0.1;
/// The flight ends burn + 6 s after launch (0x60ce98).
const END_AFTER_BURN: f64 = 6.0;
/// Hit distance (0x60ceb0).
const HIT_DIST: f64 = 1.5;
/// Overshoot: cos(velocity, line of sight) below this (0x60cec0).
const OVERSHOOT_COS: f64 = -0.01;
/// Chase init: q is clamped to [0.1, 1] (0x60cef4 / 0x60cef0); below 0.7 (0x60cef8) the proportional chase becomes
/// the dog chase.
const Q_MIN: f64 = 0.1;
const Q_PROP: f64 = 0.7;
/// Ground impact near the target: within 60 m² horizontally (0x60cea8) and 15 m above it (0x60ceac) the burst is
/// put at the target's height, else at most 1 m below the ground (`FUN_0049a7c0`).
const NEAR_TARGET_XY2: f64 = 60.0;
const NEAR_TARGET_DZ: f64 = 15.0;
/// Launch speed below which the weapon leaves along the nose at the tuned speed (0x60ce54).
const MIN_LAUNCH_SPEED: f64 = 5.0;
/// DLZ (`FUN_005624f0`): the burn shortened by 2 s against a target (0x60ce78), the minimum range the distance flown
/// in tCO + 2 s (0x60ce80 = −2), 1 s without a target.
const DLZ_BURN_CUT: f64 = 2.0;
const DLZ_MIN_EXTRA: f64 = 2.0;
/// Weapon data Real: the launch speed at which the motion flies the published range (m/s, ≈ Mach 0.75).
pub const REAL_LAUNCH_SPEED: f64 = 250.0;
/// Without terrain the ground is at 0.1 m.
const NO_TERRAIN_Z: f64 = 0.1;
const G: f64 = 9.80665;

/// The chase law (+0x88, `_chaseType`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Chase {
    /// 1: straight at the target.
    Dog,
    /// 2: on the collision course.
    Proportional,
}

impl Chase {
    pub fn from_type(t: i64) -> Self {
        if t == 2 { Chase::Proportional } else { Chase::Dog }
    }
}

/// A weapon's chase motion (weapons.ibx, with its Real overrides).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ChaseMotion {
    /// _absAcceleration (+0x94).
    pub accel: f64,
    /// _spiralAccelBeta (+0x13c): the drag along the velocity.
    pub beta: f64,
    /// _spiralAccel: the steering gain at q = 1.
    pub spiral: f64,
    /// _timeConstOrientation (+0xb8): flies straight until then.
    pub t_co: f64,
    /// tAcc + tConstVel + tDecel (+0x108), or the Real burn.
    pub burn: f64,
    pub chase: Chase,
    pub high_angle_turn: bool,
    /// The release (`FUN_005627e0` @563358): while younger than _timeRelease (+0xb0) the motor is not lit and the
    /// weapon only accelerates by _absReleaseAcceleration (+0x9c) along the launcher's down axis (UNCERTAIN: which
    /// row of the attitude matrix: the drop off the rail).
    pub release_time: f64,
    pub release_accel: f64,
    /// Weapon data Real (ours, docs/real-weapons.md §2): the DLZ max is the distance the motion really flies
    /// (`travelled`) instead of the original's `flown`, which is tuned for the 1998 records.
    pub real: bool,
    /// The high off-boresight missiles (ours: AIM-9X, Python 5; docs/weapons.md §13.1): the overshoot ends the flight
    /// only once the target has been ahead of the missile at an update, so a missile launched at a target beside or
    /// behind the beam turns toward it instead of ending at once.
    pub off_boresight: bool,
}

impl ChaseMotion {
    /// `FUN_005627b0`: the distance flown in `t` seconds from speed `s`: s·t + ½·a·(1 − 4β)·t².
    pub fn flown(&self, s: f64, t: f64) -> f64 {
        (s - (self.accel - self.beta * self.accel * 4.0) * t * -0.5) * t
    }

    /// The distance the motion really flies straight ahead in `t` seconds from speed `s` (ours): the motor pushes
    /// a − β·v until the flight ends, so the speed tends to the top speed V = a / β and the distance is
    /// V·t + (s − V)·(1 − e^(−βt)) / β (with β = 0: s·t + ½·a·t²).
    pub fn travelled(&self, s: f64, t: f64) -> f64 {
        let t = t.max(0.0);
        if self.beta <= 0.0 {
            return s * t + 0.5 * self.accel * t * t;
        }
        let v = self.accel / self.beta;
        v * t + (s - v) * (1.0 - (-self.beta * t).exp()) / self.beta
    }

    /// Weapon data Real: the burn with which the motion flies `range` metres from `REAL_LAUNCH_SPEED` before its
    /// flight ends (burn + 6 s), at least 1 s.
    pub fn real_burn(&self, range: f64) -> f64 {
        let (mut lo, mut hi) = (0.0, 600.0);
        for _ in 0..60 {
            let t = 0.5 * (lo + hi);
            if self.travelled(REAL_LAUNCH_SPEED, t) < range { lo = t } else { hi = t }
        }
        (hi - END_AFTER_BURN).max(1.0)
    }

    /// The DLZ (vfunc +0x74, `FUN_005624f0`) from `launcher` at `target`. Without a target: [flown(burn),
    /// flown(1 s)]. With one: max = flown(|V| − the target's speed away, burn − 2), min = flown(|V|, tCO + 2); none
    /// when the target is 90° or more off the nose (acos ≥ π/2, 0x84162c), min > max, or it sits on the launcher.
    pub fn dlz(&self, launcher: &Launcher, target: Option<&Kinematics>) -> Dlz {
        let s = launcher.vel.length();
        let Some(target) = target else {
            let max = if self.ours() { self.travelled(s, self.real_dlz_time()) } else { self.flown(s, self.burn) };
            return Dlz { max, min: self.min_flown(s, 1.0) };
        };
        let d = target.pos - launcher.pos;
        let r = d.length();
        if r <= 0.0 || (d.dot(launcher.fwd) / r).clamp(-1.0, 1.0).acos() >= FRAC_PI_2 {
            return Dlz::NONE;
        }
        let away = d.dot(target.vel) / r;
        let max = if self.ours() {
            let t = self.real_dlz_time();
            self.travelled(s, t) - away * t
        } else {
            self.flown(s - away, self.burn - DLZ_BURN_CUT)
        };
        let min = self.min_flown(s, self.t_co + DLZ_MIN_EXTRA);
        if min > max { Dlz::NONE } else { Dlz { max, min } }
    }

    /// The DLZ min's distance: the original's `flown` for the 1998 records, else the distance really flown (as the
    /// max, `ours`).
    fn min_flown(&self, s: f64, t: f64) -> f64 {
        if self.ours() { self.travelled(s, t) } else { self.flown(s, t) }
    }

    /// The DLZ from the distance really flown (`travelled`): Weapon data Real and our off-boresight missiles, whose
    /// agility the original's `flown` can't carry (its ½·a·(1 − 4β)·t² goes negative for β > ¼: the AIM-9X's 0.44 gave
    /// a −1.78 km min and, with Weapon data Original, no zone at all).
    fn ours(&self) -> bool {
        self.real || self.off_boresight
    }

    /// Weapon data Real: the DLZ max looks at the whole flight (burn + 6 s) less the original's 2 s margin.
    fn real_dlz_time(&self) -> f64 {
        self.burn + END_AFTER_BURN - DLZ_BURN_CUT
    }
}

/// A launch zone in metres.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Dlz {
    pub max: f64,
    pub min: f64,
}

impl Dlz {
    pub const NONE: Dlz = Dlz { max: 0.0, min: 0.0 };
}

/// A point mass: position and velocity.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Kinematics {
    pub pos: Vec3,
    pub vel: Vec3,
}

/// The launcher at the release: position, velocity and attitude (nose, up).
#[derive(Clone, Copy, Debug, Default)]
pub struct Launcher {
    pub pos: Vec3,
    pub vel: Vec3,
    pub fwd: Vec3,
    pub up: Vec3,
}

/// The _debugParam values a launch reads and the Real turn limit.
#[derive(Clone, Copy, Debug)]
pub struct Tuning {
    /// _debugParam001 (015 with _highAngleTurn): overshoots end the flight only within this distance.
    pub overshoot_dist: f64,
    /// _debugParam005 == 1: the flight never ends.
    pub no_end: bool,
    /// _debugParam000: the launch speed along the nose of a launcher slower than 5 m/s.
    pub slow_launch_speed: f64,
    /// Weapon data Real: the acceleration across the velocity is clamped to this many g.
    pub max_g: Option<f64>,
}

impl Default for Tuning {
    fn default() -> Self {
        Tuning { overshoot_dist: 1.0e7, no_end: false, slow_launch_speed: 100.1, max_g: None }
    }
}

/// What a homing weapon flies at.
#[derive(Clone, Debug, PartialEq)]
pub enum Aim {
    /// A unit (+0x84); its key.
    Unit(String),
    /// A point (+0xc8).
    Point(Vec3),
}

/// `FUN_0046ca82`: the point of segment a → b closest to p (p itself when it lies on the line or behind a; a when the
/// segment is shorter than 0.1 m).
pub fn closest_on_segment(p: Vec3, a: Vec3, b: Vec3) -> Vec3 {
    let l = a.distance(b);
    if l <= 0.1 {
        return a;
    }
    let d = (b - a) * (1.0 / l);
    let ap = p - a;
    let along = ap.dot(d);
    if (ap - d * along).length() <= 0.1 || along <= 0.0 {
        return p;
    }
    a + d * along.min(l)
}

#[derive(Clone, Debug)]
pub struct Missile {
    motion: ChaseMotion,
    tuning: Tuning,
    aim: Aim,
    chase: Chase,
    /// +0x138: _spiralAccel · q.
    gain: f64,
    /// +0xd4: the launcher's down axis.
    release_dir: Vec3,
    /// +0x148: guidance off (the semi-active missiles losing the radar, `FUN_00458130` → `FUN_004d8420`; ECM,
    /// `FUN_004582f0`): no more steering, the motor still pushes along the velocity.
    pub guidance_off: bool,
    t_start: f64,
    t0: f64,
    p0: Vec3,
    v0: Vec3,
    /// +0x48.
    acc: Vec3,
    /// +0xe4: the burst point at the end.
    last_pos: Vec3,
    /// +0x128.
    cos_prev: f64,
    /// +0x118.
    ended: bool,
    next_update: f64,
    /// The target was ahead at an update (cos > 0; `ChaseMotion::off_boresight`).
    seen_ahead: bool,
}

impl Missile {
    /// Launch (`FUN_004d5d10` → `FUN_00561ef0` after `FUN_00563b70` / `FUN_00563ad0`) from `pos`, at `aim`, with q
    /// (`FUN_00457f70`). The first update runs at launch time.
    pub fn launch(
        motion: ChaseMotion,
        tuning: Tuning,
        now: f64,
        pos: Vec3,
        launcher: &Launcher,
        aim: Aim,
        q: f64,
    ) -> Self {
        let (chase, gain) = match aim {
            Aim::Unit(_) => {
                let q = q.clamp(Q_MIN, 1.0);
                let chase = if motion.chase == Chase::Proportional && q < Q_PROP { Chase::Dog } else { motion.chase };
                (chase, motion.spiral * q)
            }
            Aim::Point(_) => (motion.chase, motion.spiral), // FUN_00563ad0: q not applied
        };
        let v0 = if launcher.vel.length() >= MIN_LAUNCH_SPEED {
            launcher.vel
        } else {
            launcher.fwd * tuning.slow_launch_speed
        };
        Missile {
            motion,
            tuning,
            aim,
            chase,
            gain,
            release_dir: -launcher.up,
            guidance_off: false,
            t_start: now,
            t0: now,
            p0: pos,
            v0,
            acc: Vec3::ZERO,
            last_pos: pos,
            cos_prev: 0.0,
            ended: false,
            next_update: now,
            seen_ahead: false,
        }
    }

    pub fn aim(&self) -> &Aim {
        &self.aim
    }
    /// The current segment's start, velocity and acceleration.
    pub fn segment(&self) -> (Vec3, Vec3, Vec3) {
        (self.p0, self.v0, self.acc)
    }
    pub fn last_pos(&self) -> Vec3 {
        self.last_pos
    }
    pub fn next_update(&self) -> f64 {
        self.next_update
    }
    /// The current segment's start time.
    pub fn t0(&self) -> f64 {
        self.t0
    }
    pub fn ended(&self) -> bool {
        self.ended
    }

    pub fn position(&self, now: f64) -> Vec3 {
        let dt = now - self.t0;
        self.p0 + self.v0 * dt + self.acc * (0.5 * dt * dt)
    }

    pub fn velocity(&self, now: f64) -> Vec3 {
        self.v0 + self.acc * (now - self.t0)
    }

    /// `FUN_005622e0` (from `FUN_004d83c0`, a decoy taking the missile): a new target; q, the chase law and the
    /// gain stay as launched.
    pub fn retarget(&mut self, key: String) {
        self.aim = Aim::Unit(key);
    }

    /// The motion's time left (vfunc +0x80, `FUN_00468db0`): burn − age.
    pub fn time_left(&self, now: f64) -> f64 {
        self.motion.burn - (now - self.t_start)
    }

    /// One update (`FUN_005627e0`) with the target now (ignored when aiming at a point). True when the weapon ends:
    /// it bursts at `last_pos()`.
    pub fn update(&mut self, now: f64, target: Kinematics, terrain: &dyn Fn(Vec3) -> Option<f64>) -> bool {
        let m = self.motion;
        let age = now - self.t_start;
        let t_end = m.burn + END_AFTER_BURN;
        let v = self.velocity(now);
        let p = self.position(now);
        let p_old = self.last_pos;
        let has_target = matches!(self.aim, Aim::Unit(_));
        let (tp, tv) = match self.aim {
            Aim::Unit(_) => (target.pos, target.vel),
            Aim::Point(a) => (a, Vec3::ZERO),
        };
        self.p0 = p;
        self.v0 = v;
        self.t0 = now;
        self.acc = Vec3::ZERO;
        self.last_pos = p;
        let gh = terrain(p).unwrap_or(NO_TERRAIN_Z);
        let hit_ground = p.z <= gh;
        if hit_ground {
            self.last_pos = snap(closest_on_segment(tp, p_old, p), tp, gh);
        }
        let los = tp - p;
        let dist = los.length();
        let sp = v.length();
        let uv = v.try_normalize().unwrap_or(Vec3::NORTH);
        let hit = dist <= HIT_DIST || hit_ground;
        let u = if hit { Vec3::NORTH } else { los * (1.0 / dist) };
        if !hit {
            let steering = age > m.t_co && age < t_end && !self.ended && !self.guidance_off;
            let dir = if steering { self.steer(u, v, dist, tv) } else { uv };
            self.acc = self.thrust(age, dir, uv, sp);
        }
        // End of flight.
        let cos_old = self.cos_prev;
        let cos_new = uv.dot(u);
        self.cos_prev = cos_new;
        self.seen_ahead |= cos_new > 0.0;
        if age < 0.001 {
            self.next_update = now + PERIOD;
            return false;
        }
        let timeout = age > t_end;
        let overshoot =
            cos_new < OVERSHOOT_COS && dist <= self.tuning.overshoot_dist && (!m.off_boresight || self.seen_ahead);
        let end = !self.tuning.no_end && (hit || timeout || overshoot) && (!has_target || age >= m.t_co);
        if !end {
            self.next_update = now + PERIOD;
            return false;
        }
        self.ended = true;
        if cos_old > 0.0 && cos_new < 0.0 && has_target && !timeout && !hit_ground && !self.guidance_off {
            self.last_pos = snap(closest_on_segment(tp, p_old, p), tp, gh);
        }
        true
    }

    /// The steering direction toward the line of sight `u` (dog chase) or the collision course with a target moving
    /// at `tv` (proportional), less the velocity across it times the gain.
    fn steer(&self, u: Vec3, v: Vec3, dist: f64, tv: Vec3) -> Vec3 {
        let sp = v.length();
        let d = match self.chase {
            Chase::Dog => u,
            Chase::Proportional => {
                let across = tv - u * tv.dot(u);
                let pp = across.length();
                if pp < sp {
                    (u * (sp * sp - pp * pp).sqrt() + across).try_normalize().unwrap_or(u)
                } else {
                    across * (1.0 / pp)
                }
            }
        };
        let v_perp = v - d * d.dot(v);
        (d * dist - v_perp * self.gain).try_normalize().unwrap_or(d)
    }

    /// The acceleration along `dir` at speed `sp`: the release push while on the rail, then the motor less the drag;
    /// the Real turn limit across the velocity `uv`.
    fn thrust(&self, age: f64, dir: Vec3, uv: Vec3, sp: f64) -> Vec3 {
        let m = self.motion;
        let mut acc = if age < m.release_time {
            self.release_dir * m.release_accel
        } else {
            dir * (m.accel - m.beta * sp * dir.dot(uv))
        };
        if let Some(max_g) = self.tuning.max_g {
            let lat = acc - uv * acc.dot(uv);
            let lim = max_g * G;
            if lat.length() > lim {
                acc += lat * (lim / lat.length() - 1.0);
            }
        }
        acc
    }
}

/// The burst point near the target: at the target's height within 60 m² horizontally and 15 m above it, else at most
/// 1 m below the ground.
fn snap(mut q: Vec3, tp: Vec3, gh: f64) -> Vec3 {
    let (dx, dy) = (q.x - tp.x, q.y - tp.y);
    q.z = if dx * dx + dy * dy <= NEAR_TARGET_XY2 && q.z - tp.z <= NEAR_TARGET_DZ { tp.z } else { q.z.max(gh - 1.0) };
    q
}

#[cfg(test)]
mod tests {
    use super::*;

    fn amraam() -> ChaseMotion {
        ChaseMotion {
            accel: 120.0,
            beta: 0.1,
            spiral: 1000.0,
            t_co: 3.0,
            burn: 35.0,
            chase: Chase::Proportional,
            high_angle_turn: false,
            release_time: 0.0,
            release_accel: 0.0,
            real: false,
            off_boresight: false,
        }
    }

    const JET: Launcher = Launcher { pos: Vec3::ZERO, vel: Vec3::new(0.0, 250.0, 0.0), fwd: Vec3::NORTH, up: Vec3::UP };

    #[test]
    fn dlz_head_on_tail_and_behind() {
        let m = amraam();
        let at = |vy: f64| Kinematics { pos: Vec3::new(0.0, 20000.0, 0.0), vel: Vec3::new(0.0, vy, 0.0) };
        let head_on = m.dlz(&JET, Some(&at(-250.0)));
        assert!((head_on.max - (500.0 * 33.0 + 0.5 * 120.0 * 0.6 * 33.0 * 33.0)).abs() < 0.5);
        assert!((head_on.min - (250.0 * 5.0 + 0.5 * 120.0 * 0.6 * 25.0)).abs() < 0.5);
        let tail = m.dlz(&JET, Some(&at(250.0)));
        assert!(tail.max < head_on.max && tail.min == head_on.min);
        let behind = Kinematics { pos: Vec3::new(0.0, -5000.0, 0.0), vel: Vec3::ZERO };
        assert_eq!(m.dlz(&JET, Some(&behind)), Dlz::NONE);
        assert_eq!(m.dlz(&JET, None).min, m.flown(250.0, 1.0));
    }

    #[test]
    fn off_boresight_dlz_min_is_never_negative() {
        let m = ChaseMotion { accel: 600.0, beta: 0.44, t_co: 0.05, burn: 20.0, off_boresight: true, ..amraam() };
        assert!(m.flown(250.0, 2.05) < 0.0, "the original's formula fails for these numbers");
        let l =
            Launcher { pos: Vec3::ZERO, vel: Vec3::new(0.0, 250.0, 0.0), fwd: Vec3::new(0.0, 1.0, 0.0), up: Vec3::UP };
        let t = Kinematics { pos: Vec3::new(0.0, 3000.0, 0.0), vel: Vec3::new(0.0, 200.0, 0.0) };
        for z in [m.dlz(&l, Some(&t)), m.dlz(&l, None)] {
            assert!(z.min > 0.0 && z.min < z.max, "{z:?}");
        }
    }

    #[test]
    fn off_boresight_missile_turns_to_a_target_behind_the_beam() {
        // A target 100° off the nose (Python 5): the original's overshoot ends the flight at the first steering
        // update; the off-boresight missile turns and reaches it.
        let at = Vec3::new(3000f64 * 100f64.to_radians().sin(), 3000.0 * 100f64.to_radians().cos(), 3000.0);
        let still = Kinematics { pos: at, vel: Vec3::ZERO };
        let fly = |off_boresight: bool| {
            let m = ChaseMotion { accel: 600.0, beta: 0.44, t_co: 0.05, burn: 20.0, off_boresight, ..amraam() };
            let mut mis =
                Missile::launch(m, Tuning::default(), 0.0, Vec3::UP * 3000.0, &JET, Aim::Unit("t".into()), 1.0);
            let mut t = 0.0;
            while !mis.update(t, still, &|_| None) {
                t += PERIOD;
            }
            mis.last_pos().distance(at)
        };
        assert!(fly(false) > 2000.0, "the original ends near the launch");
        assert!(fly(true) < 50.0, "off-boresight: {}", fly(true));
    }

    #[test]
    fn low_q_falls_back_to_the_dog_chase() {
        let m = Missile::launch(amraam(), Tuning::default(), 0.0, Vec3::ZERO, &JET, Aim::Unit("t".into()), 0.5);
        assert_eq!(m.chase, Chase::Dog);
        assert_eq!(m.gain, 500.0);
    }

    #[test]
    fn the_real_turn_limit_caps_the_lateral_acceleration() {
        let m =
            ChaseMotion { accel: 300.0, spiral: 0.0, t_co: 0.0, burn: 10.0, beta: 0.0, chase: Chase::Dog, ..amraam() };
        let tuning = Tuning { max_g: Some(12.0), ..Tuning::default() };
        let from = Launcher { vel: Vec3::new(0.0, 300.0, 0.0), ..JET };
        let mut mi = Missile::launch(m, tuning, 0.0, Vec3::new(0.0, 0.0, 1000.0), &from, Aim::Unit("x".into()), 1.0);
        let target = Kinematics { pos: Vec3::new(3000.0, 0.0, 1000.0), vel: Vec3::ZERO };
        mi.update(0.0, target, &|_| None);
        mi.update(0.1, target, &|_| None);
        let (_, v0, acc) = mi.segment();
        let uv = v0.try_normalize().unwrap();
        assert!(((acc - uv * acc.dot(uv)).length() - 12.0 * G).abs() < 0.01);
    }

    #[test]
    fn it_hits_a_target_ahead() {
        let mut mi = Missile::launch(amraam(), Tuning::default(), 0.0, Vec3::ZERO, &JET, Aim::Unit("t".into()), 1.0);
        let target = Kinematics { pos: Vec3::new(0.0, 4000.0, 0.0), vel: Vec3::ZERO };
        let mut t = 0.0;
        while !mi.update(t, target, &|_| None) {
            t = mi.next_update();
            assert!(t < 60.0, "never ended");
        }
        assert!(mi.last_pos().distance(target.pos) < 50.0, "burst {:?}", mi.last_pos());
    }

    #[test]
    fn closest_point_on_the_path() {
        let (a, b) = (Vec3::ZERO, Vec3::new(0.0, 100.0, 0.0));
        assert_eq!(closest_on_segment(Vec3::new(5.0, 50.0, 0.0), a, b), Vec3::new(0.0, 50.0, 0.0));
        assert_eq!(closest_on_segment(Vec3::new(5.0, -50.0, 0.0), a, b), Vec3::new(5.0, -50.0, 0.0), "behind a: p");
    }

    /// The air-to-air chase records (weapons.ibx: a, β, tAcc + tConstVel + tDecel, tCO, release time) and the Real
    /// data (Mach, km; game/weapons/real_weapons.gd) with the original DLZ against a still target from 250 m/s
    /// straight ahead (max, min km).
    /// (name, a, β, tAcc + tConstVel + tDecel, tCO, release time, Real (Mach, km), original DLZ (max, min km)).
    type ChaseRecord = (&'static str, f64, f64, f64, f64, f64, Option<(f64, f64)>, (f64, f64));
    const AA: &[ChaseRecord] = &[
        ("AIM-9D", 150.0, 0.08, 10.0, 2.0, 0.0, Some((2.5, 18.0)), (5.264, 1.816)),
        ("AIM-9L", 100.0, 0.08, 16.0, 2.0, 0.0, Some((2.5, 17.7)), (10.164, 1.544)),
        ("PYTH-3", 100.0, 0.08, 16.0, 2.0, 0.0, Some((3.5, 15.0)), (10.164, 1.544)),
        ("PYTH-4", 140.0, 0.08, 22.0, 1.0, 0.0, Some((3.5, 15.0)), (24.04, 1.178)),
        ("SHFR 2", 150.0, 0.08, 10.0, 2.0, 0.0, Some((2.1, 5.0)), (5.264, 1.816)),
        ("AA-8", 150.0, 0.08, 13.0, 2.0, 0.0, None, (8.921, 1.816)),
        ("AMRAAM", 120.0, 0.1, 35.0, 3.0, 0.3, Some((4.0, 70.0)), (47.454, 2.15)),
        ("AIM-7M", 80.0, 0.06, 39.0, 2.0, 0.3, Some((4.0, 70.0)), (50.868, 1.486)),
        ("AIM-7B", 80.0, 0.06, 25.0, 2.0, 0.3, Some((2.5, 7.0)), (21.832, 1.486)),
    ];

    fn motion(a: f64, beta: f64, burn: f64, t_co: f64, release: f64) -> ChaseMotion {
        let release_accel = 30.0;
        ChaseMotion { accel: a, beta, burn, t_co, release_time: release, release_accel, ..amraam() }
    }

    fn from_up() -> Launcher {
        Launcher { pos: Vec3::new(0.0, 0.0, 1000.0), ..JET }
    }

    fn still_at(r: f64) -> Kinematics {
        Kinematics { pos: Vec3::new(0.0, r, 1000.0), vel: Vec3::ZERO }
    }

    /// Flies `m` from JET (1000 m up, as the target) at a still target `r` m ahead: true when it bursts within 20 m of it.
    fn reaches(m: ChaseMotion, r: f64) -> bool {
        let from = from_up();
        let mut mi = Missile::launch(m, Tuning::default(), 0.0, from.pos, &from, Aim::Unit("t".into()), 1.0);
        let mut t = 0.0;
        while !mi.update(t, still_at(r), &|_| None) {
            t = mi.next_update();
        }
        mi.last_pos().distance(still_at(r).pos) < 20.0
    }

    #[test]
    fn dlz_per_missile_original_and_real() {
        for &(name, a, beta, burn, t_co, rel, real, (max_km, min_km)) in AA {
            let z = motion(a, beta, burn, t_co, rel).dlz(&from_up(), Some(&still_at(5000.0)));
            assert!(
                (z.max / 1e3 - max_km).abs() < 0.01 && (z.min / 1e3 - min_km).abs() < 0.01,
                "{name} original {z:?}"
            );
            let Some((mach, km)) = real else { continue };
            let beta = a / (mach * 340.3);
            let burn = motion(a, beta, 0.0, t_co, rel).real_burn(km * 1e3);
            let m = ChaseMotion { real: true, ..motion(a, beta, burn, t_co, rel) };
            // The burn flies the published range from 250 m/s.
            assert!(
                (m.travelled(REAL_LAUNCH_SPEED, burn + END_AFTER_BURN) - km * 1e3).abs() < 1.0 || burn == 1.0,
                "{name}"
            );
            let z = m.dlz(&from_up(), Some(&still_at(5000.0)));
            println!("{name}: real burn {burn:.1} s, DLZ {:.2}-{:.2} km", z.max / 1e3, z.min / 1e3);
            // A zone that the missile really reaches, most of the published range.
            assert!(z.max > z.min && z.max > 0.7 * km * 1e3 && z.max < km * 1e3, "{name} real {z:?}");
            assert!(reaches(m, z.max), "{name} misses at its DLZ max {:.0} m", z.max);
            assert!(!reaches(m, 1.05 * km * 1e3), "{name} flies beyond its published range");
            // Head-on adds, tail chase takes off the target's travel.
            let head = m.dlz(&from_up(), Some(&Kinematics { vel: Vec3::new(0.0, -250.0, 0.0), ..still_at(5000.0) }));
            let tail = m.dlz(&from_up(), Some(&Kinematics { vel: Vec3::new(0.0, 250.0, 0.0), ..still_at(5000.0) }));
            assert!(head.max > z.max && (tail.max < z.max || tail == Dlz::NONE), "{name} aspects");
        }
    }
}
