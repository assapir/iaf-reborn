//! One homing weapon in flight (class 0x18: IR 570 / 580, HARM 590, radar 600 / 610, Maverick 635, the SAMs
//! 620 / 630; docs/weapons.md §5, §11): the original's chase motion (`FUN_00561c30` fields, `FUN_00561ef0` start,
//! `FUN_005627e0` update every 0.1 s, `FUN_00563b70` / `FUN_00563ad0` aim, `FUN_005622e0` retarget, `FUN_005624f0`
//! DLZ). Launcher independent (the player's or an AI's).
//!
//! World frame X east, Y north, Z up, metres, sim seconds. Between updates the motion is p0 + v0·dt + ½a·dt² (no
//! gravity, no speed cap); each update re-bases and adds the steering acceleration.
//!
//! A record with a motor (`ChaseMotion::phys`, ours: Modern IAF's missiles, docs/real-weapons.md §2.1) flies the
//! physical model instead: thrust, drag, gravity and proportional navigation, held to its g limit.

use crate::vec3::Vec3;
use iaf_flight::units::G;
use std::f64::consts::{FRAC_PI_2, PI};

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

/// The zero-lift drag coefficient on the body's cross-section by Mach (inferred: a generic finned missile's shape,
/// the transonic rise to Mach 1.2 and the fall above it; each missile scales it by its `drag_scale`).
const CD0: [(f64, f64); 8] =
    [(0.0, 0.30), (0.8, 0.30), (1.05, 0.65), (1.2, 0.70), (2.0, 0.55), (3.0, 0.45), (4.0, 0.38), (5.0, 0.33)];
/// The normal-force coefficient at the angle-of-attack limit (inferred: the AIM-120 study's 30 g at 700 m/s at its
/// 30° limit, docs/real-weapons.md §2.1).
pub const CN_MAX: f64 = 7.0;
/// The induced drag: K · CN² on the cross-section (inferred, the same study's 30 g held 4.5 s from Mach 4).
pub const K_INDUCED: f64 = 0.1;
/// After the burn the flight ends below this speed (m/s; inferred: too slow to steer).
pub const MIN_SPEED: f64 = 200.0;
/// Further off the line of sight than this (cos 60°), or opening, the missile turns straight at it (pursuit) before
/// proportional navigation takes over (inferred: wider than the lead a crossing target asks).
const PURSUIT_COS: f64 = 0.5;
/// The guidance takes the target's acceleration as at most this many g (inferred: a fighter's limit).
const TARGET_G_MAX: f64 = 12.0;
/// The pursuit turns the velocity onto the line of sight in this time (s; inferred).
const PURSUIT_TURN_S: f64 = 0.5;
/// The straight fly-out's step (s): the DLZ and the post-launch times.
const FLY_STEP: f64 = 0.1;

/// The physical missile (ours; docs/real-weapons.md §2.1): a motor of steady thrust that burns its propellant at a
/// steady rate, the drag of its body, gravity, and proportional navigation within its g limit.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Physics {
    /// Launch mass (kg).
    pub mass: f64,
    /// Propellant (kg), burnt at a steady rate over `burn`.
    pub propellant: f64,
    /// The motor's burn (s) and its thrust (N).
    pub burn: f64,
    pub thrust: f64,
    /// The body's diameter (m): the drag's reference area.
    pub diameter: f64,
    /// Times the generic zero-lift drag (`CD0`; §2.1).
    pub drag_scale: f64,
    /// The longest flight (s): the guidance's life, fitted so the missile flies its published range (§2.1).
    pub max_time: f64,
    /// The structural limit (g).
    pub max_g: f64,
    /// The proportional navigation constant.
    pub nav: f64,
    /// Thrust-vector control: while the motor burns the structural limit holds at any dynamic pressure.
    pub tvc: bool,
}

/// ISA density (kg/m³) and speed of sound (m/s) at height `z`.
fn air(z: f64) -> (f64, f64) {
    let a = iaf_flight::atmosphere::air(z as f32);
    (f64::from(a.rho), f64::from(a.sound))
}

impl Physics {
    pub fn mass_at(&self, age: f64) -> f64 {
        self.mass - self.propellant * (age / self.burn).clamp(0.0, 1.0)
    }

    pub fn thrust_at(&self, age: f64) -> f64 {
        if (0.0..self.burn).contains(&age) { self.thrust } else { 0.0 }
    }

    fn q_s(&self, sp: f64, z: f64) -> f64 {
        0.5 * air(z).0 * sp * sp * PI * 0.25 * self.diameter * self.diameter
    }

    /// The zero-lift drag coefficient at `mach`.
    pub fn cd0(&self, mach: f64) -> f64 {
        let i = CD0.iter().position(|p| p.0 > mach).unwrap_or(CD0.len() - 1).max(1);
        let ((m0, c0), (m1, c1)) = (CD0[i - 1], CD0[i]);
        self.drag_scale * (c0 + (c1 - c0) * ((mach - m0) / (m1 - m0)).clamp(0.0, 1.0))
    }

    /// The drag (N) at speed `sp` and height `z`, mass `m`, turning at `lat` m/s².
    pub fn drag(&self, sp: f64, z: f64, m: f64, lat: f64) -> f64 {
        let qs = self.q_s(sp, z);
        if qs <= 0.0 {
            return 0.0;
        }
        let cn = m * lat / qs;
        qs * (self.cd0(sp / air(z).1) + K_INDUCED * cn * cn)
    }

    /// The most acceleration across the velocity (m/s²): the fins' at `CN_MAX`, at most the structural limit; with
    /// thrust-vector control the structural limit while the motor burns.
    pub fn max_lateral(&self, sp: f64, z: f64, m: f64, age: f64) -> f64 {
        let lim = self.max_g * G;
        if self.tvc && self.thrust_at(age) > 0.0 { lim } else { (self.q_s(sp, z) * CN_MAX / m).min(lim) }
    }

    /// The flight goes on: before `max_time` and, once the motor is out, above `MIN_SPEED`.
    pub fn alive(&self, age: f64, sp: f64) -> bool {
        age <= self.max_time && (age < self.burn || sp >= MIN_SPEED)
    }

    /// Straight level flight (its lift holding its weight) at height `z` from speed `s`, `age` s after launch: `f(t, distance, speed)` every
    /// `FLY_STEP` while the flight goes on, until it returns true (then true).
    pub fn fly_straight(&self, s: f64, age: f64, z: f64, mut f: impl FnMut(f64, f64, f64) -> bool) -> bool {
        let (mut t, mut d, mut v) = (0.0, 0.0, s);
        while self.alive(age + t, v) {
            if f(t, d, v) {
                return true;
            }
            let m = self.mass_at(age + t);
            let v1 = (v + (self.thrust_at(age + t) - self.drag(v, z, m, G)) / m * FLY_STEP).max(0.0);
            d += 0.5 * (v + v1) * FLY_STEP;
            v = v1;
            t += FLY_STEP;
        }
        false
    }

    /// The DLZ from speed `s` at height `z` at a target `away` m/s away from the launcher (§2.1): the most the
    /// missile gains on it in a straight flight less its last 2 s (the original's margin), and the original's minimum
    /// (the distance flown in `min_t`).
    fn dlz(&self, s: f64, z: f64, away: f64, min_t: f64) -> Dlz {
        let mut gained = Vec::new();
        self.fly_straight(s, 0.0, z, |t, d, _| {
            gained.push((t, d));
            false
        });
        let end = gained.last().map_or(0.0, |g| g.0) - DLZ_BURN_CUT;
        let max = gained.iter().filter(|g| g.0 <= end).map(|&(t, d)| d - away * t).fold(0.0, f64::max);
        match gained.iter().find(|g| g.0 >= min_t) {
            Some(&(_, min)) if min <= max => Dlz { max, min },
            _ => Dlz::NONE,
        }
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
    /// The physical missile (ours): the motion's motor, drag and guidance in place of the chase motion.
    pub phys: Option<Physics>,
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
        if let Some(p) = self.phys {
            let Some(target) = target else { return p.dlz(s, launcher.pos.z, 0.0, 1.0) };
            let d = target.pos - launcher.pos;
            let r = d.length();
            if r <= 0.0 || d.dot(launcher.fwd) <= 0.0 {
                return Dlz::NONE;
            }
            let z = 0.5 * (launcher.pos.z + target.pos.z);
            return p.dlz(s, z, d.dot(target.vel) / r, self.t_co + DLZ_MIN_EXTRA);
        }
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

/// The post-launch cues' times in seconds (`Missile::times`).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Times {
    pub active: Option<f64>,
    pub impact: Option<f64>,
}

/// The post-launch cues' search step along the flight (s).
const CUE_STEP: f64 = 0.5;

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
    /// The physical missile: the target's velocity at the last update (its acceleration for the guidance).
    target_vel: Option<(f64, Vec3)>,
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
            target_vel: None,
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
        self.target_vel = None; // the new target's velocity is no manoeuvre of the old one
    }

    /// The motion's time left (vfunc +0x80, `FUN_00468db0`): burn − age; the physical missile's flight time limit
    /// less its age.
    pub fn time_left(&self, now: f64) -> f64 {
        self.motion.phys.map_or(self.motion.burn, |p| p.max_time) - (now - self.t_start)
    }

    /// The motor's time left (the smoke trail): the physical missile's burn less its age, else `time_left`.
    pub fn motor_left(&self, now: f64) -> f64 {
        self.motion.phys.map_or_else(|| self.time_left(now), |p| p.burn - (now - self.t_start))
    }

    /// Seconds until the missile is `left` metres from `target` (ours, the post-launch cues; modern-iaf/docs/weapons.md
    /// §8.2): it flies straight from where it is at its speed now on its motion (`ChaseMotion::travelled`) while the
    /// target goes on at its velocity along the line of sight. 0 when already that close; None when its flight ends
    /// first.
    pub fn time_to(&self, now: f64, target: Kinematics, left: f64) -> Option<f64> {
        let d = target.pos - self.position(now);
        let r = d.length();
        if r <= left {
            return Some(0.0);
        }
        let away = target.vel.dot(d) / r;
        let s = self.velocity(now).length();
        if let Some(p) = self.motion.phys {
            let mut out = None;
            p.fly_straight(s, now - self.t_start, self.position(now).z, |t, d, _| {
                out = (d - away * t >= r - left).then_some(t);
                out.is_some()
            });
            return out;
        }
        let flight_left = self.motion.burn + END_AFTER_BURN - (now - self.t_start);
        let short = |t: f64| self.motion.travelled(s, t) - away * t - (r - left);
        let mut t = 0.0;
        while t < flight_left {
            let next = (t + CUE_STEP).min(flight_left);
            if short(next) >= 0.0 {
                let (mut lo, mut hi) = (t, next);
                for _ in 0..20 {
                    let mid = 0.5 * (lo + hi);
                    if short(mid) >= 0.0 { hi = mid } else { lo = mid }
                }
                return Some(hi);
            }
            t = next;
        }
        None
    }

    /// The post-launch cues' times (G27): to the seeker going active at `active_range` metres from the target (None:
    /// a missile without one, or already active) and to impact (None: the flight ends first).
    pub fn times(&self, now: f64, target: Kinematics, active_range: Option<f64>) -> Times {
        Times {
            active: active_range.and_then(|a| self.time_to(now, target, a)).filter(|t| *t > 0.0),
            impact: self.time_to(now, target, HIT_DIST),
        }
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
        let flying = m.phys.map_or(age < t_end, |ph| ph.alive(age, sp));
        if !hit {
            let steering = age > m.t_co && flying && !self.ended && !self.guidance_off;
            self.acc = match m.phys {
                Some(ph) => {
                    let at = match self.target_vel {
                        Some((t, prev)) if now - t > 1e-3 => (tv - prev) * (1.0 / (now - t)),
                        _ => Vec3::ZERO,
                    };
                    // A jump in the host's velocity (a frame stall) is no manoeuvre: at most a fighter's 12 g.
                    let at = if at.length() > TARGET_G_MAX * G { at * (TARGET_G_MAX * G / at.length()) } else { at };
                    self.target_vel = Some((now, tv));
                    self.phys_acc(&ph, age, p, v, (los, tv, at), steering)
                }
                None => self.thrust(age, if steering { self.steer(u, v, dist, tv) } else { uv }, uv, sp),
            };
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
        let timeout = if m.phys.is_some() { !flying } else { age > t_end };
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

    /// The physical missile's acceleration (§2.1) at `p` with velocity `v`, the target at `los` from it moving at `tv`
    /// and turning at `at`: the release push on the rail; then the thrust less the drag along the velocity, gravity,
    /// and when `steering` augmented proportional navigation (pursuit far off the line of sight or opening) with
    /// gravity held off, across the velocity within the g limit.
    fn phys_acc(&self, ph: &Physics, age: f64, p: Vec3, v: Vec3, target: (Vec3, Vec3, Vec3), steering: bool) -> Vec3 {
        let (los, tv, at) = target;
        let gravity = Vec3::UP * -G;
        if age < self.motion.release_time {
            return self.release_dir * self.motion.release_accel + gravity;
        }
        let sp = v.length();
        let uv = v.try_normalize().unwrap_or(Vec3::NORTH);
        let m = ph.mass_at(age);
        let mut lat = Vec3::ZERO;
        let dist = los.length();
        if steering && dist > 0.0 {
            let u = los * (1.0 / dist);
            let vr = tv - v;
            let vc = -vr.dot(u);
            let cmd = if uv.dot(u) < PURSUIT_COS || vc <= 0.0 {
                // Turn the velocity onto the line of sight within about 0.5 s, at most the limit.
                let off = uv.dot(u).clamp(-1.0, 1.0).acos();
                (u - uv * u.dot(uv)).try_normalize().map_or(Vec3::ZERO, |d| d * (sp * off / PURSUIT_TURN_S))
            } else {
                // Augmented: half the constant times the target's acceleration across the line of sight.
                los.cross(vr).cross(u) * (ph.nav * vc / (dist * dist)) + (at - u * at.dot(u)) * (0.5 * ph.nav)
            } - gravity;
            lat = cmd - uv * cmd.dot(uv);
            let lim = ph.max_lateral(sp, p.z, m, age).min(self.tuning.max_g.map_or(f64::MAX, |g| g * G));
            if lat.length() > lim {
                lat = lat * (lim / lat.length());
            }
        }
        uv * ((ph.thrust_at(age) - ph.drag(sp, p.z, m, lat.length())) / m) + lat + gravity
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
            phys: None,
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
    fn post_launch_times_count_down_to_the_real_flight() {
        // At 3 km: below NO_TERRAIN_Z the flight ends as a ground hit at tCO.
        let jet = Launcher { pos: Vec3::new(0.0, 0.0, 3000.0), ..JET };
        let target = Kinematics { pos: Vec3::new(0.0, 8000.0, 3000.0), vel: Vec3::ZERO };
        let mut mi = Missile::launch(amraam(), Tuning::default(), 0.0, jet.pos, &jet, Aim::Unit("t".into()), 1.0);
        let at_launch = mi.times(0.0, target, Some(4000.0));
        let (active, impact) = (at_launch.active.unwrap(), at_launch.impact.unwrap());
        assert!(active > 0.0 && active < impact, "{at_launch:?}");
        let mut t = 0.0;
        let mut went_active = None;
        while !mi.update(t, target, &|_| None) {
            if went_active.is_none() && mi.position(t).distance(target.pos) <= 4000.0 {
                went_active = Some(t);
            }
            t = mi.next_update();
        }
        assert!((impact - t).abs() < 1.0, "impact predicted {impact:.1} s, flown {t:.1} s");
        assert!((active - went_active.unwrap()).abs() < 1.0, "active predicted {active:.1} s, {went_active:?}");
        // Inside the active range only the time to impact remains; none when the flight cannot reach.
        assert_eq!(mi.times(t, target, Some(1.0e6)).active, None);
        let far = Kinematics { pos: Vec3::new(0.0, 1.0e6, 3000.0), vel: Vec3::ZERO };
        assert_eq!(mi.times(t, far, None), Times::default());
    }

    #[test]
    fn closest_point_on_the_path() {
        let (a, b) = (Vec3::ZERO, Vec3::new(0.0, 100.0, 0.0));
        assert_eq!(closest_on_segment(Vec3::new(5.0, 50.0, 0.0), a, b), Vec3::new(0.0, 50.0, 0.0));
        assert_eq!(closest_on_segment(Vec3::new(5.0, -50.0, 0.0), a, b), Vec3::new(5.0, -50.0, 0.0), "behind a: p");
    }

    /// The air-to-air chase records (weapons.ibx: a, β, tAcc + tConstVel + tDecel, tCO, release time) and the Real
    /// data (Mach, km; shared/weapons/real_weapons.gd) with the original DLZ against a still target from 250 m/s
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

    /// Modern IAF's physical missiles (docs/real-weapons.md §2.1; the values of modern-iaf/data/db/weapons and
    /// shared/weapons/modern_weapons.gd): (name, physics, the published range in km and whether it is the head-on
    /// shot 12,000 m up (else the still target 6,000 m up), both at Mach 0.9).
    fn modern() -> [(&'static str, Physics, f64, bool); 4] {
        let ph = |mass, propellant, burn, thrust, diameter, max_time, max_g, tvc| Physics {
            mass,
            propellant,
            burn,
            thrust,
            diameter,
            drag_scale: 1.217,
            max_time,
            max_g,
            nav: 4.0,
            tvc,
        };
        [
            ("AIM-9M", ph(86.0, 27.2, 5.0, 12810.0, 0.127, 24.7, 40.0, false), 17.7, false),
            ("AIM-9X", ph(85.0, 27.2, 5.0, 12810.0, 0.127, 24.7, 60.0, true), 17.7, false),
            ("PYTH-5", ph(105.0, 34.0, 5.0, 16671.0, 0.16, 31.1, 60.0, false), 20.0, false),
            ("AIM-120", ph(161.5, 51.3, 7.75, 17188.0, 0.178, 120.0, 35.0, false), 90.0, true),
        ]
    }

    /// The reference shot (§2.1) at Mach 0.9: head-on 12,000 m up, or at a still target 6,000 m up.
    fn reference(p: &Physics, head_on: bool) -> Dlz {
        let z = if head_on { 12000.0 } else { 6000.0 };
        let s = 0.9 * air(z).1;
        p.dlz(s, z, if head_on { -s } else { 0.0 }, 2.5)
    }

    /// The highest Mach of a straight flight from Mach 0.9 at height `z`.
    fn top_mach(p: &Physics, z: f64) -> f64 {
        let mut top = 0.0f64;
        p.fly_straight(0.9 * air(z).1, 0.0, z, |_, _, v| {
            top = top.max(v);
            false
        });
        top / air(z).1
    }

    #[test]
    fn physical_missiles_fly_their_published_figures() {
        for (name, p, km, head_on) in modern() {
            let z = reference(&p, head_on);
            let m = top_mach(&p, 12000.0);
            assert!((z.max / 1e3 / km - 1.0).abs() < 0.02, "{name}: {:.1} km against {km}", z.max / 1e3);
            println!("{name}: reference {:.1} km, top Mach {m:.2}", z.max / 1e3);
            match name {
                "AIM-120" | "PYTH-5" => assert!((m - 4.0).abs() < 0.15, "{name}: Mach {m:.2}"),
                _ => assert!(m > 2.5, "{name}: Mach {m:.2} (\"Mach 2.5+\")"),
            }
            // Lower and in a tail chase the zone shrinks; at sea level the drag holds the top speed lower.
            let at = |h: f64, away: f64| p.dlz(0.9 * air(h).1, h, away * 0.9 * air(h).1, 2.5).max;
            assert!(at(0.0, 0.0) < at(6000.0, 0.0) && at(6000.0, 0.0) < at(12000.0, 0.0), "{name}: height");
            assert!(at(6000.0, -1.0) > at(6000.0, 0.0), "{name}: head-on");
            assert!(at(6000.0, 1.0) < 0.7 * at(6000.0, 0.0), "{name}: tail chase");
            assert!(top_mach(&p, 0.0) < m, "{name}");
            if name == "AIM-120" {
                // The CFD study's straight shot: Mach 0.83 5 km up at a still point, about 35 km.
                let r = p.dlz(0.83 * air(5000.0).1, 5000.0, 0.0, 2.5).max;
                assert!((r / 35e3 - 1.0).abs() < 0.15, "AIM-120 at 5 km: {r:.0} m");
            }
        }
    }

    #[test]
    fn physical_post_launch_times_match_the_flight() {
        let (_, p, _, _) = modern()[3];
        let jet = Launcher { pos: Vec3::new(0.0, 0.0, 6000.0), vel: Vec3::new(0.0, 284.0, 0.0), ..JET };
        let target = Kinematics { pos: Vec3::new(0.0, 20000.0, 6000.0), vel: Vec3::ZERO };
        let mi = Missile::launch(physical(p), Tuning::default(), 0.0, jet.pos, &jet, Aim::Unit("t".into()), 1.0);
        let predicted = mi.times(0.0, target, None).impact.unwrap();
        let (miss, flown) = fly(p, target);
        assert!(
            miss < 5.0 && (predicted - flown).abs() < 0.1 * flown,
            "predicted {predicted:.1} s, flown {flown:.1} s"
        );
        assert!((mi.motor_left(1.0) - (p.burn - 1.0)).abs() < 1e-9, "the trail burns with the motor");
        assert!((mi.time_left(1.0) - (p.max_time - 1.0)).abs() < 1e-9, "the HUD counts the flight");
    }

    fn physical(p: Physics) -> ChaseMotion {
        ChaseMotion { t_co: 0.5, chase: Chase::Proportional, phys: Some(p), ..amraam() }
    }

    /// Flies `p` from a jet 6,000 m up at Mach 0.9 at `target`: the miss distance and the flight time.
    fn fly(p: Physics, target: Kinematics) -> (f64, f64) {
        fly_at(p, &|t| Kinematics { pos: target.pos + target.vel * t, ..target })
    }

    /// As `fly`, at a target whose state at time t is `path(t)`.
    fn fly_at(p: Physics, path: &dyn Fn(f64) -> Kinematics) -> (f64, f64) {
        let jet = Launcher { pos: Vec3::new(0.0, 0.0, 6000.0), vel: Vec3::new(0.0, 284.0, 0.0), ..JET };
        let mut mi = Missile::launch(physical(p), Tuning::default(), 0.0, jet.pos, &jet, Aim::Unit("t".into()), 1.0);
        let mut t = 0.0;
        let mut miss = f64::MAX;
        loop {
            let ended = mi.update(t, path(t), &|_| None);
            if ended {
                return (miss.min(mi.last_pos().distance(path(t).pos)), t);
            }
            // The closest pass along the segment to the next update.
            let next = mi.next_update();
            for k in 0..=20 {
                let tt = t + (next - t) * f64::from(k) / 20.0;
                miss = miss.min(mi.position(tt).distance(path(tt).pos));
            }
            t = next;
        }
    }

    /// A target `r` m ahead flying away at 250 m/s that breaks into a level `g` turn at once.
    fn breaking(r: f64, g: f64) -> impl Fn(f64) -> Kinematics {
        move |t: f64| {
            let (v, w) = (250.0, g * G / 250.0);
            let a = w * t;
            let c = Vec3::new(v / w, r, 6000.0);
            Kinematics {
                pos: c + Vec3::new(-a.cos() * v / w, a.sin() * v / w, 0.0),
                vel: Vec3::new(a.sin() * v, a.cos() * v, 0.0),
            }
        }
    }

    #[test]
    fn a_short_shot_hits_a_breaking_target() {
        // The range's drone breaks 90° when a fighter closes (modern-iaf/data/db/brains/drone_evade.json): a 2.5 km
        // shot at a 6 g break ends inside the blast (9 m).
        for (name, p, _, _) in modern() {
            let (miss, t) = fly_at(p, &breaking(2500.0, 6.0));
            println!("{name}: {miss:.1} m after {t:.1} s");
            assert!(miss < 9.0, "{name}: {miss:.1} m");
        }
    }

    #[test]
    fn a_physical_missile_reaches_its_dlz_and_no_further() {
        let jet = Launcher { pos: Vec3::new(0.0, 0.0, 6000.0), vel: Vec3::new(0.0, 284.0, 0.0), ..JET };
        for (name, p, _, _) in modern() {
            for vy in [0.0, 200.0, -200.0] {
                let at = |r: f64| Kinematics { pos: Vec3::new(0.0, r, 6000.0), vel: Vec3::new(0.0, vy, 0.0) };
                let z = physical(p).dlz(&jet, Some(&at(5000.0)));
                assert!(z.min > 0.0 && z.min < z.max, "{name} {vy}: {z:?}");
                assert!(fly(p, at(0.9 * z.max)).0 < 20.0, "{name} {vy}: misses inside its zone {z:?}");
                assert!(fly(p, at(1.15 * z.max)).0 > 20.0, "{name} {vy}: reaches past its zone {z:?}");
            }
            // Proportional navigation leads a crossing target.
            let crossing = Kinematics { pos: Vec3::new(-2000.0, 6000.0, 6000.0), vel: Vec3::new(250.0, 0.0, 0.0) };
            let (miss, t) = fly(p, crossing);
            assert!(miss < 15.0, "{name}: crossing miss {miss:.1} m after {t:.1} s");
        }
    }

    #[test]
    fn turning_bleeds_speed_and_height_takes_the_turn() {
        let (_, p, _, _) = modern()[3];
        let m = p.mass_at(10.0);
        assert!(p.drag(800.0, 6000.0, m, 20.0 * G) > 2.0 * p.drag(800.0, 6000.0, m, 0.0), "induced drag");
        let (low, high) = (p.max_lateral(800.0, 0.0, m, 10.0), p.max_lateral(800.0, 12000.0, m, 10.0));
        assert!(low == 35.0 * G && high < 0.5 * low, "{low} {high}");
        // Thrust-vector control: the AIM-9X's 60 g at any height while the motor burns, the fins' after.
        let (_, x, _, _) = modern()[1];
        assert_eq!(x.max_lateral(300.0, 12000.0, 80.0, 1.0), 60.0 * G);
        assert!(x.max_lateral(300.0, 12000.0, 60.0, 6.0) < 10.0 * G);
    }
}
