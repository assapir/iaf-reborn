//! The gun (docs/weapons.md §3): the shot line, the fixed-weapon motion and its ring pool of rounds (the aim, the
//! candidate list, the analytic trajectory, the 0.1 s hit checks and the detonation: `FUN_00456d40`,
//! `FUN_00456ff0`, `FUN_004577c0`, `FUN_005605c0`, `FUN_0047a491`, `FUN_00560710`, `FUN_004d6130`) and the AA gun
//! LCOS pipper (`FUN_0045f3b0` → `FUN_0045f410`). The same motion flies rockets and decoys.
//!
//! World frame X east, Y north, Z up, metres, sim seconds.

use crate::vec3::Vec3;
use std::f64::consts::PI;

/// v1.1 (`FUN_00456ff0`): the player's shot line is the nose pitched 1° up (v1.0: the nose).
const GUN_ELEVATION_DEG: f64 = 1.0;
/// Aim distance without the AG lead (2781.0 @0x600f5c; v1.0 1854.0).
const AIM_DISTANCE: f64 = 2781.0;
/// AG gun (HUD mode 4) lead: gravity ½g (4.903 @0x601414) over _limitDist / _limitVel.
const HALF_G: f64 = 4.903;
/// Candidate query radius = 10·|A − P| (0x600f60); a locked target counts within 2·|A − P| (4.0 @0x600f18).
const QUERY_FACTOR: f64 = 10.0;
const LOCK_FACTOR_SQ: f64 = 4.0;
/// At most 10 candidates per round (aim buffer +0x24..).
const MAX_CANDIDATES: usize = 10;
/// The candidate gate (`FUN_004d3fa0(0, 0.5, 0)` @453ccf): no list within 0.5 s after the last one.
const LIST_GATE: f64 = 0.5;
/// Hit sphere = _spiralAccel × 0.5 (0x60cdb4) unless Easy aiming (v1.1; v1.0 always the full value).
const EASY_OFF_FACTOR: f64 = 0.5;
/// Aim points farther than 30 km are pulled in (0x602a90).
const MAX_RANGE: f64 = 30000.0;
/// Without terrain a round detonates at 0.1 m.
const NO_TERRAIN_Z: f64 = 0.1;

/// The shot line (`FUN_00456ff0`): the nose rotated 1° up about the right wing (K = N × U), for the player only.
pub fn shot_dir(nose: Vec3, up: Vec3, elevate: bool) -> Vec3 {
    match nose.cross(up).try_normalize() {
        Some(k) if elevate => nose.rotated(k, GUN_ELEVATION_DEG.to_radians()),
        _ => nose,
    }
}

/// Motion data of weapons.ibx (the gun: [WEAPON019], type 565).
#[derive(Clone, Copy, Debug)]
pub struct Motion {
    /// _absAcceleration (the gun decelerates at −10, a rocket accelerates at +100).
    pub abs_accel: f64,
    pub limit_vel: f64,
    pub limit_dist: f64,
    pub velocity_jump: f64,
    /// _timeConstOrientation: the hit check period.
    pub check_period: f64,
    /// _spiralAccel: the hit distance.
    pub hit_distance: f64,
    /// _maxNumInAir.
    pub pool_size: usize,
}

impl Default for Motion {
    fn default() -> Self {
        Motion {
            abs_accel: -10.0,
            limit_vel: 1200.0,
            limit_dist: 4500.0,
            velocity_jump: 1200.0,
            check_period: 0.1,
            hit_distance: 50.0,
            pool_size: 20,
        }
    }
}

/// A round's flight: from `p0` along `u` at speed `s` (from `t0`), at `a` from `t_end`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Flight {
    pub p0: Vec3,
    pub u: Vec3,
    pub s: f64,
    pub t0: f64,
    pub t_end: f64,
    pub a: Vec3,
}

impl Motion {
    /// The aim point A: HUD mode 4 (AG gun) leads with the round's flight time _limitDist / _limitVel and gravity;
    /// any other mode aims 2781 m down the shot line.
    pub fn aim_point(&self, p: Vec3, vel: Vec3, d: Vec3, ag_mode: bool) -> Vec3 {
        if !ag_mode {
            return p + d * AIM_DISTANCE;
        }
        let t = self.limit_dist / self.limit_vel;
        (p + (vel + d * self.velocity_jump) * t).raised(-HALF_G * t * t)
    }

    /// The time the speed reaches _limitVel at _absAcceleration (None: never, it starts there or beyond).
    fn time_to_limit(&self, s: f64) -> Option<f64> {
        let a = self.abs_accel;
        Some((self.limit_vel - s) / a).filter(|&t| a != 0.0 && t > 0.0)
    }

    /// Time to cover `dist` from speed `s` at _absAcceleration (`FUN_0047a491`) until the speed reaches _limitVel,
    /// then at _limitVel. (The rocket's accelerating branch follows the same formula: UNCERTAIN.)
    pub fn flight_time(&self, s: f64, dist: f64) -> f64 {
        let a = self.abs_accel;
        match self.time_to_limit(s) {
            Some(t_c) => {
                let d_c = s * t_c + 0.5 * a * t_c * t_c;
                if d_c >= dist {
                    ((s * s + 2.0 * a * dist).max(0.0).sqrt() - s) / a
                } else {
                    t_c + (dist - d_c) / self.limit_vel
                }
            }
            None => dist / s.max(1.0),
        }
    }

    /// The flight from `p0` with speed `s` to `a`, starting at `t0` (`FUN_005605c0` → `FUN_0047a1e2`).
    pub fn flight(&self, t0: f64, p0: Vec3, s: f64, a: Vec3) -> Flight {
        let d = a - p0;
        let u = d.try_normalize().unwrap_or(Vec3::NORTH);
        Flight { p0, u, s, t0, t_end: t0 + self.flight_time(s, d.length()), a }
    }

    /// Position on a flight at `t` (`FUN_00466fc0`): p0 + v0·dt + ½a·dt² along u until t_end, then A.
    pub fn position(&self, f: &Flight, t: f64) -> Vec3 {
        if t >= f.t_end {
            return f.a;
        }
        let dt = t - f.t0;
        let a = self.abs_accel;
        let along = match self.time_to_limit(f.s) {
            None => f.s * dt,
            Some(t_c) if dt <= t_c => f.s * dt + 0.5 * a * dt * dt,
            Some(t_c) => f.s * t_c + 0.5 * a * t_c * t_c + self.limit_vel * (dt - t_c),
        };
        f.p0 + f.u * along
    }
}

/// A unit a round can hit: its key and origin.
#[derive(Clone, Debug, PartialEq)]
pub struct Body {
    pub key: String,
    pub pos: Vec3,
}

/// One shot (`FUN_00456d40` after the ammo checks).
#[derive(Clone, Copy, Debug)]
pub struct Shot<'a> {
    /// The jet's origin (the candidate query's centre).
    pub origin: Vec3,
    pub muzzle: Vec3,
    pub velocity: Vec3,
    pub aim: Vec3,
    /// The radar-locked unit.
    pub locked: Option<&'a str>,
    pub shooter: &'a str,
    pub easy_aiming: bool,
}

/// A round in the air.
#[derive(Clone, Debug, PartialEq)]
pub struct Round {
    pub flight: Flight,
    /// The units it can hit (`FUN_004577c0`).
    pub candidates: Vec<String>,
    pub hit_radius: f64,
    next_check: f64,
}

/// What ended a round.
#[derive(Clone, Debug, PartialEq)]
pub enum Hit {
    /// A candidate: the blast goes to the candidates.
    Unit { key: String, candidates: Vec<String> },
    /// The terrain (the area query).
    Ground,
    /// The end of its flight at A (the area query).
    End,
}

/// A round's detonation: pool slot, position and what it hit.
#[derive(Clone, Debug, PartialEq)]
pub struct Detonation {
    pub slot: usize,
    pub pos: Vec3,
    pub hit: Hit,
}

/// The ring pool of a fixed weapon (`FUN_004d8760`).
#[derive(Clone, Debug)]
pub struct Rounds {
    pub motion: Motion,
    pool: Vec<Option<Round>>,
    next: usize,
    last_list: Option<f64>,
}

impl Rounds {
    pub fn new(motion: Motion) -> Self {
        Rounds { motion, pool: vec![None; motion.pool_size], next: 0, last_list: None }
    }

    /// The pool's slots; None = free.
    pub fn slots(&self) -> &[Option<Round>] {
        &self.pool
    }

    /// The next pooled round is free (a busy one skips the shot, no ammo used).
    pub fn next_free(&self) -> bool {
        matches!(self.pool.get(self.next), Some(None))
    }

    /// Fires the next pooled round: its slot, or None when it is still in the air.
    pub fn fire(&mut self, now: f64, shot: &Shot, bodies: &[Body]) -> Option<usize> {
        if !self.next_free() {
            return None;
        }
        let slot = self.next;
        self.next = (self.next + 1) % self.pool.len();
        let candidates = self.candidates(now, shot, bodies);
        // Solver FUN_0047a491: speed = |own velocity| + velocityJump along the line to A, decelerating at
        // _absAcceleration; ends at A (at most 30 km out).
        let to_aim = shot.aim - shot.muzzle;
        let aim = match to_aim.try_normalize() {
            Some(u) if to_aim.length() > MAX_RANGE => shot.muzzle + u * MAX_RANGE,
            _ => shot.aim,
        };
        let flight = self.motion.flight(now, shot.muzzle, shot.velocity.length() + self.motion.velocity_jump, aim);
        self.pool[slot] = Some(Round {
            flight,
            candidates,
            hit_radius: self.motion.hit_distance * if shot.easy_aiming { 1.0 } else { EASY_OFF_FACTOR },
            next_check: now + self.motion.check_period,
        });
        Some(slot)
    }

    /// The candidate list (`FUN_004577c0`): none within 0.5 s of the last list; else the locked target (within
    /// 2·|A − P|) first, then the units inside 10·|A − P| other than the shooter, at most 10. UNCERTAIN: the
    /// original's query order (a spatial list); ours is nearest first.
    fn candidates(&mut self, now: f64, shot: &Shot, bodies: &[Body]) -> Vec<String> {
        if self.last_list.is_some_and(|t| (t..=t + LIST_GATE).contains(&now)) {
            return Vec::new();
        }
        self.last_list = Some(now);
        let reach = shot.aim.distance(shot.origin);
        let d2 = |b: &Body| (b.pos - shot.origin).length_squared();
        let mut out: Vec<String> = bodies
            .iter()
            .filter(|b| shot.locked == Some(b.key.as_str()) && d2(b) < LOCK_FACTOR_SQ * reach * reach)
            .map(|b| b.key.clone())
            .collect();
        let mut near: Vec<&Body> = bodies
            .iter()
            .filter(|b| b.key != shot.shooter && !out.contains(&b.key) && d2(b).sqrt() < QUERY_FACTOR * reach)
            .collect();
        near.sort_by(|x, y| d2(x).total_cmp(&d2(y)));
        let room = MAX_CANDIDATES.saturating_sub(out.len());
        out.extend(near.into_iter().take(room).map(|b| b.key.clone()));
        out
    }

    /// Advances the rounds to `now` up to the first detonation, which it returns; call again until None, with the
    /// units after its damage. The 0.1 s checks (`FUN_00560710`): the round within the hit sphere of a candidate's
    /// origin, or at / below the terrain; the end of flight at t_end detonates at A.
    pub fn step(&mut self, now: f64, bodies: &[Body], terrain: &dyn Fn(Vec3) -> Option<f64>) -> Option<Detonation> {
        let m = self.motion;
        for (slot, entry) in self.pool.iter_mut().enumerate() {
            let Some(round) = entry else { continue };
            while round.next_check <= now.min(round.flight.t_end) {
                let t = round.next_check;
                round.next_check += m.check_period;
                if let Some((pos, hit)) = check(&m, round, t, bodies, terrain) {
                    *entry = None;
                    return Some(Detonation { slot, pos, hit });
                }
            }
            if now >= round.flight.t_end {
                let pos = round.flight.a;
                *entry = None;
                return Some(Detonation { slot, pos, hit: Hit::End });
            }
        }
        None
    }
}

/// One hit check of `round` at `t`.
fn check(m: &Motion, round: &Round, t: f64, bodies: &[Body], terrain: &dyn Fn(Vec3) -> Option<f64>) -> Option<(Vec3, Hit)> {
    let p = m.position(&round.flight, t);
    // The last body of a key wins (the original's lookup by id).
    let hit = round.candidates.iter().find(|k| {
        bodies.iter().rev().find(|b| &b.key == *k).is_some_and(|b| p.distance(b.pos) < round.hit_radius)
    });
    if let Some(key) = hit {
        return Some((p, Hit::Unit { key: key.clone(), candidates: round.candidates.clone() }));
    }
    (p.z <= terrain(p).unwrap_or(NO_TERRAIN_Z)).then_some((p, Hit::Ground))
}

/// The jet as the LCOS reads it: attitude (degrees), speed (m/s), load factor and the flight model's `alpha`.
#[derive(Clone, Copy, Debug, Default)]
pub struct JetState {
    pub pitch: f64,
    pub roll: f64,
    pub heading: f64,
    pub speed: f64,
    pub load_factor: f64,
    pub alpha: f64,
}

/// The AA gun LCOS pipper (`FUN_0045f3b0` → `FUN_0045f410`, feet): every 0.05 s, integrated with dt 0.15 (quirk
/// kept). `offset` is in radians off the gun cross (x right, y down; the HUD draws ×57.29578·12 px).
#[derive(Clone, Copy, Debug, Default)]
pub struct Lcos {
    pub offset: (f64, f64),
    /// The filtered pitch / heading rates (w+0x28 / +0x2c).
    rates: (f64, f64),
    /// The last pitch / heading (÷π); None restarts the filters from the attitude.
    last: Option<(f64, f64)>,
    next: f64,
}

/// The int16 fixed point of the rate filters: ×65536 truncated, wrapped to ±32768.
fn int16(e: f64) -> f64 {
    f64::from((e * 65536.0) as i64 as i16)
}

impl Lcos {
    /// Out of HUD mode 3: the rate filters restart from the attitude at the next mode entry. (Ours: the original's
    /// first values are untraced; from 0 the first heading step would throw the pipper off for ~1 s.)
    pub fn reset(&mut self) {
        self.last = None;
    }

    /// One frame in HUD mode 3; `lock_range` = the radar lock's range in metres (None: 450 m).
    pub fn step(&mut self, t: f64, jet: &JetState, lock_range: Option<f64>) {
        if t < self.next {
            return;
        }
        self.next = t + 0.05;
        const DT: f64 = 0.15;
        let (a0, a1, a2) = (jet.pitch.to_radians(), jet.roll.to_radians(), jet.heading.to_radians());
        let (p0, p2) = self.last.unwrap_or((a0 / PI, a2 / PI));
        self.last = Some((a0 / PI, a2 / PI));
        let v = jet.speed * 3.2808;
        // R (ft): the locked range ×3.28084 (0x601478), else 1476.378; at most 3148.8.
        let r = lock_range.map_or(1476.378, |m| m * 3.28084).min(3148.8);
        let (w28, w2c) = &mut self.rates;
        *w28 += 4.0 * (int16(a0 / PI - p0) / 65536.0 - DT * *w28);
        *w2c += 4.0 * (int16(a2 / PI - p2) / 65536.0 - DT * *w2c);
        let (w28, w2c) = self.rates;
        let pp = PI * (a1.cos() * w28 + a0.cos() * a1.sin() * w2c);
        let qq = PI * (a0.cos() * a1.cos() * w2c - a1.sin() * w28);
        let tf = r / (3300.0 - (v + 1650.0) * r * 0.00024667423);
        let gd = PI * tf * tf * 16.087 / r;
        let damp = 0.2 + 1.35 * tf;
        let xs = gd * a0.cos() * a1.sin() - tf * qq;
        let ys = tf * pp + (jet.load_factor - 1.0) * gd - ((3300.0 * tf - r) * v * jet.alpha / r) / (v + 3300.0) + 5.0617 / r;
        let (x, y) = &mut self.offset;
        *x += DT * (xs - *x) / damp;
        *y += DT * (ys - *y) / damp;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gun() -> Motion {
        // The F-16's 20 MM: 200 m/s + 1200 = 1400 m/s, decelerating at 10 m/s² towards 800.
        Motion { limit_vel: 800.0, ..Motion::default() }
    }

    fn body(key: &str, x: f64, y: f64, z: f64) -> Body {
        Body { key: key.into(), pos: Vec3::new(x, y, z) }
    }

    fn shot<'a>(aim: Vec3, easy: bool) -> Shot<'a> {
        let p = Vec3::new(0.0, 0.0, 100.0);
        Shot { origin: p, muzzle: p, velocity: Vec3::new(0.0, 200.0, 0.0), aim, locked: None, shooter: "me", easy_aiming: easy }
    }

    #[test]
    fn shot_line_is_one_degree_up() {
        let d = shot_dir(Vec3::NORTH, Vec3::UP, true);
        assert!((d.z - 1f64.to_radians().sin()).abs() < 1e-12 && d.x.abs() < 1e-12);
        assert_eq!(shot_dir(Vec3::NORTH, Vec3::UP, false), Vec3::NORTH);
    }

    #[test]
    fn a_round_hits_the_unit_on_its_line() {
        let mut g = Rounds::new(gun());
        let bodies = [body("u", 0.0, 1000.0, 100.0)];
        let aim = g.motion.aim_point(Vec3::new(0.0, 0.0, 100.0), Vec3::ZERO, Vec3::NORTH, false);
        assert_eq!(g.fire(0.0, &shot(aim, false), &bodies), Some(0));
        let r = g.slots()[0].as_ref().expect("in the air");
        assert_eq!(r.hit_radius, 25.0, "Easy aiming off: half the hit sphere");
        let want = (1400.0 - (1400.0f64 * 1400.0 - 20.0 * 2781.0).sqrt()) / 10.0;
        assert!((r.flight.t_end - want).abs() < 1e-9);
        let det = g.step(2.0, &bodies, &|_| Some(0.0)).expect("a hit");
        assert!(matches!(det.hit, Hit::Unit { ref key, .. } if key == "u"));
        assert_eq!(g.step(2.0, &bodies, &|_| Some(0.0)), None);
        assert!(g.slots()[0].is_none());
    }

    #[test]
    fn candidate_gate_and_ground() {
        let mut g = Rounds::new(gun());
        let bodies = [body("u", 0.0, 500.0, 100.0), body("me", 0.0, 0.0, 0.0)];
        let aim = Vec3::new(0.0, 2781.0, 100.0);
        g.fire(0.0, &shot(aim, true), &bodies);
        g.fire(0.3, &shot(aim, true), &bodies);
        let cands = |i: usize| g.slots()[i].as_ref().map(|r| r.candidates.clone());
        assert_eq!(cands(0), Some(vec!["u".to_string()]));
        assert_eq!(cands(1), Some(vec![]), "no list within 0.5 s of the last");
        let mut g = Rounds::new(gun());
        g.fire(0.0, &shot(Vec3::new(0.0, 1000.0, -100.0), true), &[]);
        let det = g.step(5.0, &[], &|_| Some(0.0)).expect("the ground");
        assert_eq!(det.hit, Hit::Ground);
        assert!(det.pos.z <= 0.0);
    }

    #[test]
    fn lcos_settles_near_the_cross_in_level_flight() {
        let mut l = Lcos::default();
        let jet = JetState { heading: 90.0, speed: 200.0, load_factor: 1.0, ..JetState::default() };
        for i in 0..200 {
            l.step(f64::from(i) * 0.05, &jet, None);
        }
        // 1 g, no rates, no AoA, no lock: only 5.0617 / R is left (R = 450 m in feet), ~2.4 px down.
        assert!(l.offset.0.abs() < 1e-12 && (l.offset.1 - 5.0617 / 1476.378).abs() < 1e-9, "{:?}", l.offset);
        assert_eq!(int16(-1.0 / 65536.0), -1.0);
        assert_eq!(int16(0.5), -32768.0);
    }
}
