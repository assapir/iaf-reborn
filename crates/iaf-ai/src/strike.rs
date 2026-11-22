//! The AI jets' air-to-ground attack (docs/ai.md §8.10; modern-iaf/docs/ai-plan.md F15, K15): our wingmen on the lead's
//! "attack my target" ([`crate::Flight::attack`]) and an AI-led flight on its lead's own order ([`crate::Flight::strike`],
//! the enemy pairs). Each jet waits its turn in its slot, then flies its run by its weapon ([`Profile`]): a guided bomb
//! from a level run, a bomb or rockets from a 30° dive with the aim-off for the drop. The release is the bombs' vacuum
//! impact (`iaf_avionics::bombs::fall_time`, the CCIP's fall) on the target, within the release permission
//! (`iaf_avionics::release::release_allowed`); the host releases the stores through its AI ripple (combat.gd,
//! [`crate::Order::release`]) and reports it ([`crate::Flight::released`]). Then the egress away from the target,
//! climbing, and the rejoin. The calls: "in" at the run-in, "alpha" at the release, "done" once clear (IAF Hebrew נכנס,
//! אלפא, ביצעתי). Every figure here is inferred unless it says otherwise.
//!
//! The original's own bombing manoeuvres (LevelBomb, DiveBomb; docs/ai.md §13.3) were tried first and dropped on 23
//! November 2026: on the 6-DoF DiveBomb ran in at 357 m/s, overshot its dive and flew into the ground without a release;
//! LevelBomb's release (the vacuum impact within twice its height of the target) let go 7 km short at 4,000 m, beyond
//! what the AI stores' steered fall corrects.

use iaf_avionics::bombs::fall_time;
use iaf_avionics::master::{Master, Modes};
use iaf_avionics::release::release_allowed;
use iaf_flight::Vec3;
use iaf_flight::aircraft::ApView;
use iaf_flight::autopilot::{MODE_BFM, MODE_STEER, Steer};

use crate::bt::Status;
use crate::fighter::Bogey;
use crate::flight::Member;

/// HoldPositionCL (docs/ai.md §8.1): a waiting jet holds where it is while the flight lead flies its run.
const HOLD: u8 = 10;
/// Each next jet's run starts this long after the one before (s), and not while another jet of the flight flies its
/// run: a trail of runs, clear of the bombs of the jet ahead.
pub const STAGGER_S: f64 = 20.0;
/// A run with no release this long is given up (s).
pub const RUN_MAX_S: f64 = 300.0;
/// The runs' speed (m/s, about 490 kt) and turns (g).
const RUN: (f32, f32) = (250.0, 3.0);
/// The level run: at its height, at least this high above the target (m).
pub const LEVEL_AGL: f64 = 1_500.0;
/// The level run's release: the impact past the target along the track (the first decision after it: at most this
/// beyond it, m), within this across it (m).
const PAST_M: f64 = 500.0;
const ACROSS_M: f64 = 300.0;
/// The dive: run in at least this high above the target (m), rolled in at this angle below the horizon (deg),
/// released below the run-in's height with the impact within this of the target (m: DiveBomb's own figure, `5d8590`),
/// pulled out without a release below this height (m) and run again; its pull (g).
pub const DIVE_IN_AGL: f64 = 2_500.0;
const DIVE_DEG: f64 = 30.0;
const DIVE_MISS_M: f64 = 400.0;
/// The roll-in: the target within this of the nose (deg); steeper below the horizon than `.0` (deg) the jet extends
/// out on its track until the target is less than `.1` below it, then turns back.
const AHEAD_DEG: f64 = 30.0;
const EXTEND_DEG: (f64, f64) = (35.0, 20.0);
const DIVE_FLOOR_AGL: f64 = 900.0;
const DIVE_G: f32 = 4.0;
/// The egress: on along its track until this far from the target (m, horizontal), climbing at this angle (deg, the
/// BFM loop at [`DIVE_G`]) to at least this high above it (m), then level on the steer loop.
pub const EGRESS_M: f64 = 8_000.0;
const CLIMB_DEG: f64 = 20.0;
/// A jet going down faster than this (m/s: a dive's) pulls out on the BFM loop first.
const DESCENT_MS: f64 = 10.0;
pub const EGRESS_AGL: f64 = 1_500.0;
/// A steer point this far along a heading (m).
const FAR: f64 = 50_000.0;
const G: f64 = 9.80665;

/// Where a jet is in its attack.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Phase {
    #[default]
    None,
    /// Ordered: in its slot (or on its route) until its turn.
    Wait,
    /// The run-in, the dive and the release.
    Run,
    /// Away from the target, climbing.
    Egress,
}

impl Phase {
    pub fn name(self) -> &'static str {
        match self {
            Phase::None => "",
            Phase::Wait => "wait",
            Phase::Run => "run",
            Phase::Egress => "egress",
        }
    }
}

/// The run by the weapon.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Profile {
    /// A guided bomb (GPS, laser): a level run at its height.
    #[default]
    Level,
    /// A bomb or rockets: a 30° dive.
    Dive,
}

impl Profile {
    /// The run for a weapon: a guided bomb from the level run, a bomb or rockets from the dive.
    pub fn of(guided: bool) -> Profile {
        if guided { Profile::Level } else { Profile::Dive }
    }

    pub fn name(self) -> &'static str {
        match self {
            Profile::Level => "level",
            Profile::Dive => "dive",
        }
    }
}

/// A jet's attack: its phase and the facts the host gives.
#[derive(Debug, Clone, Default)]
pub struct Strike {
    pub phase: Phase,
    /// The host's, each frame: its air-to-ground weapon left, Some(true) a guided bomb, Some(false) a bomb or rockets,
    /// None nothing.
    pub weapon: Option<bool>,
    /// The flight's ground target this decision (the host's; None: gone).
    pub target: Option<Bogey>,
    /// Its run starts at this time (s).
    pub(crate) turn: f64,
    /// When its phase began (s).
    pub(crate) since: f64,
    /// The host reported its release ([`crate::Flight::released`]).
    pub released: bool,
    /// The run (fixed at its start).
    pub profile: Profile,
    /// The dive's run: rolled in; too near for the dive, extending away on its track.
    pub diving: bool,
    pub(crate) extending: bool,
}

impl Strike {
    /// No attack (its weapon kept: the host's).
    pub fn clear(&mut self) {
        *self = Strike { weapon: self.weapon, ..Strike::default() };
    }
}

/// "Attack my target" on a point takes the hostile ground unit nearest it within this (m, horizontal), else the point.
pub const SNAP_M: f64 = 500.0;
/// One release: every store of its weapon, at most this many (IafRipple's), this far apart (m; inferred).
pub const RIPPLE_MAX: u32 = 14;
pub const RIPPLE_M: u32 = 30;

/// The player's ground target for "attack my target" (docs/ai.md §8.10) among the hostile ground units alive at
/// `units` (world positions): the one the radar has locked (`locked`, an index), else the one nearest the SPI `spi`
/// within [`SNAP_M`]; None: the SPI itself (a point).
pub fn pick(locked: Option<usize>, spi: Vec3, units: &[Vec3]) -> Option<usize> {
    if locked.is_some_and(|i| i < units.len()) {
        return locked;
    }
    let d = |u: &Vec3| Vec3::new(u[0] - spi[0], u[1] - spi[1], 0.0).length();
    (0..units.len()).filter(|&i| d(&units[i]) < SNAP_M).min_by(|&a, &b| d(&units[a]).total_cmp(&d(&units[b])))
}

/// One of a jet's pylons as the host gives it: its weapon's type (the records' 500 bomb, 510 cluster, 560 rockets, 650
/// laser bomb), whether it is GPS-guided, the stores left and the weapon's id.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Pylon {
    pub kind: i64,
    pub gps: bool,
    pub count: i64,
    pub id: i64,
}

/// The pylon an attack releases from: the first with stores of a guided bomb (GPS, laser; Some(true): the level run) or
/// a bomb or rockets (Some(false): the dive) left; None: no air-to-ground weapon ([`Profile::of`]).
pub fn pylon(pylons: &[Pylon]) -> Option<(usize, bool)> {
    pylons.iter().enumerate().filter(|(_, p)| p.count > 0).find_map(|(i, p)| {
        if p.gps {
            return Some((i, true));
        }
        match Modes::for_store(p.kind, false, false)?.0 {
            Master::LaserBomb => Some((i, true)),
            Master::Bombs => Some((i, false)),
            _ => None,
        }
    })
}

/// The stores of one release from pylon `i`: every store of its weapon on all pylons, 1 to [`RIPPLE_MAX`].
pub fn ripple(pylons: &[Pylon], i: usize) -> u32 {
    let id = pylons.get(i).map(|p| p.id);
    let n: i64 = pylons.iter().filter(|p| Some(p.id) == id).map(|p| p.count.max(0)).sum();
    n.clamp(1, RIPPLE_MAX as i64) as u32
}

/// The vacuum impact of a store released now from `p` at `v` on the height `z` (`bombs::fall_time`, the CCIP's fall).
pub fn impact(p: Vec3, v: Vec3, z: f64) -> Vec3 {
    let t = fall_time(v[2], (p[2] - z).max(0.0));
    Vec3::new(p[0] + v[0] * t, p[1] + v[1] * t, z)
}

/// The dive's point for the flight path: the target `t` moved on by the drop of a store released from `p` at `speed`
/// m/s along the line to the target (that line meets the ground at the target, the store short of it), so a path at the
/// point puts the vacuum impact on the target. A jet not above the target: the target itself.
pub fn aim_off(p: Vec3, speed: f64, t: Vec3) -> Vec3 {
    let Some(d) = (t - p).try_normalize().filter(|d| d[2] < -0.01) else { return t };
    let i = impact(p, d * speed, t[2]);
    t + (t - i)
}

/// The load factor along the jet's lift (its acceleration and gravity's share across the path, over the bank).
fn load_factor(v: &ApView) -> f64 {
    let d = v.vel.try_normalize().unwrap_or(Vec3::NORTH);
    let up = (Vec3::UP - d * d[2]).try_normalize().unwrap_or(Vec3::UP);
    (v.acc + Vec3::UP * G).dot(up) / G / (v.att.roll as f64).cos().max(0.1)
}

pub(crate) fn striking(m: &Member) -> bool {
    m.strike.phase != Phase::None
}

/// The attack over: `call` made, back to its slot ("in position"); a jet based on the enemy's side goes home.
fn end(m: &mut Member, call: Option<&'static str>) -> Status {
    m.calls.extend(call);
    m.strike.clear();
    (m.transit, m.report) = (true, true);
    m.enemy.done |= m.enemy.based;
    Status::Failure
}

fn fly_to(m: &mut Member, mode: u8, to: Vec3, g: f32) -> Status {
    m.order.steer = Some(Steer { to, g, speed: RUN.0, thr_max: 1.0, fighter: false });
    m.order.mode = Some(mode);
    Status::Running
}

/// The attack's leaf: before its turn, and while another jet of the flight flies its run, it fails (the slot, the
/// route; the Hold while the flight lead flies its run);
/// then the run ("in"), the egress after the release ("alpha", the host's) or after [`RUN_MAX_S`] without one, and
/// "done" once [`EGRESS_M`] away (a run given up: "unable"). The target gone (destroyed, lost) ends it: "done" after
/// its release.
pub(crate) fn fly(m: &mut Member) -> Status {
    let now = m.now;
    let Some(t) = m.strike.target else {
        let call = m.strike.released.then_some("done");
        return end(m, call);
    };
    let s = &mut m.strike;
    match s.phase {
        // (The flight lead on its own run: the Hold where it is; its slot would take it down the lead's dive.)
        Phase::Wait if now < s.turn && m.lead_striking => {
            m.order.mode = Some(HOLD);
            return Status::Running;
        }
        Phase::Wait if now < s.turn || m.run_busy => return Status::Failure,
        Phase::Wait => {
            let Some(guided) = s.weapon else { return end(m, Some("unable")) };
            (s.phase, s.since, s.profile, s.diving) = (Phase::Run, now, Profile::of(guided), false);
            m.calls.push("in");
        }
        Phase::Run if s.released || now > s.since + RUN_MAX_S => (s.phase, s.since) = (Phase::Egress, now),
        _ => {}
    }
    let (p, v) = (m.v.pos, m.v.vel);
    let agl = p[2] - t.pos[2];
    if m.strike.phase == Phase::Run {
        return run(m, &t, agl);
    }
    let off = Vec3::new(p[0] - t.pos[0], p[1] - t.pos[1], 0.0);
    if off.length() > EGRESS_M {
        let call = if m.strike.released { "done" } else { "unable" };
        return end(m, Some(call));
    }
    // (Straight on along its track: a turn back from a dive's release short of the target looped it down to 977 m.)
    let away = Vec3::new(v[0], v[1], 0.0).try_normalize().or(off.try_normalize()).unwrap_or(Vec3::NORTH);
    if agl < EGRESS_AGL || v[2] < -DESCENT_MS {
        // The pull-out and the climb away (the BFM loop flies the line in any plane, its ground watch on).
        let c = CLIMB_DEG.to_radians();
        return fly_to(m, MODE_BFM, p + (away * c.cos() + Vec3::UP * c.sin()) * 10_000.0, DIVE_G);
    }
    let mut to = p + away * FAR;
    to[2] = p[2];
    fly_to(m, MODE_STEER, to, RUN.1)
}

/// The run. Level: on the steer loop at the target at its height (at least [`LEVEL_AGL`] above it), released once the
/// vacuum impact passes the target (within [`PAST_M`] beyond it and [`ACROSS_M`] of the track). Dive: on the steer
/// loop at the target at least [`DIVE_IN_AGL`] above it (climbing there at [`CLIMB_DEG`] when lower), rolled in once
/// the target lies [`DIVE_DEG`] below the horizon within [`AHEAD_DEG`] of the nose (too near, too steep or not ahead:
/// out on its track first, [`EXTEND_DEG`]), then the BFM loop on the aim-off point, released below
/// [`DIVE_IN_AGL`] with the impact within [`DIVE_MISS_M`] of the target; below [`DIVE_FLOOR_AGL`] without a
/// release it pulls out and runs again. Both within the release permission.
fn run(m: &mut Member, t: &Bogey, agl: f64) -> Status {
    let (p, v) = (m.v.pos, m.v.vel);
    let to_t = Vec3::new(t.pos[0] - p[0], t.pos[1] - p[1], 0.0);
    let dir = to_t.try_normalize().unwrap_or(Vec3::NORTH);
    let miss = impact(p, v, t.pos[2]) - t.pos;
    let allowed = release_allowed(load_factor(&m.v), (m.v.att.roll as f64).to_degrees());
    let level = |m: &mut Member, agl_min: f64| {
        let at = Vec3::new(t.pos[0], t.pos[1], p[2].max(t.pos[2] + agl_min));
        fly_to(m, MODE_STEER, at, RUN.1)
    };
    if m.strike.profile == Profile::Level {
        let track = Vec3::new(v[0], v[1], 0.0).try_normalize().unwrap_or(dir);
        let along = miss.dot(track);
        m.order.release = allowed && (0.0..PAST_M).contains(&along) && (miss - track * along).length() < ACROSS_M;
        return level(m, LEVEL_AGL);
    }
    let below = agl.atan2(to_t.length()).to_degrees();
    let track = Vec3::new(v[0], v[1], 0.0).try_normalize().unwrap_or(dir);
    let s = &mut m.strike;
    if s.diving && agl < DIVE_FLOOR_AGL {
        s.diving = false; // pulled out: run again
    } else if s.extending && below < EXTEND_DEG.1 {
        s.extending = false;
    } else if !s.diving && !s.extending && below >= DIVE_DEG {
        // Rolled in with the target ahead and the height for the dive; else out on its track and back.
        let ahead = track.dot(dir) >= AHEAD_DEG.to_radians().cos();
        if ahead && agl >= DIVE_IN_AGL - 500.0 && below <= EXTEND_DEG.0 {
            s.diving = true;
        } else {
            s.extending = true;
        }
    }
    if m.strike.extending {
        let mut to = p + track * FAR;
        to[2] = p[2].max(t.pos[2] + DIVE_IN_AGL);
        return fly_to(m, MODE_STEER, to, RUN.1);
    }
    if m.strike.diving {
        m.order.release = allowed && agl < DIVE_IN_AGL && miss.length() < DIVE_MISS_M;
        return fly_to(m, MODE_BFM, aim_off(p, v.length(), t.pos), DIVE_G);
    }
    if agl < DIVE_IN_AGL {
        let c = CLIMB_DEG.to_radians();
        return fly_to(m, MODE_BFM, p + (dir * c.cos() + Vec3::UP * c.sin()) * 10_000.0, DIVE_G);
    }
    level(m, DIVE_IN_AGL)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn impact_and_aim_off() {
        // Level at 1,000 m and 100 m/s: 14.28 s of fall, 1,428 m ahead.
        let i = impact(Vec3::new(0.0, 0.0, 1000.0), Vec3::new(0.0, 100.0, 0.0), 0.0);
        assert!((i[1] - 100.0 * (1000.0f64 / 4.903).sqrt()).abs() < 1.0 && i[2] == 0.0, "{i:?}");
        // A 30° line to the target at 250 m/s from 1,500 m: it meets the ground at the target, the store short of it;
        // the aim-off point lies beyond the target by that drop.
        let (p, d) = (Vec3::new(0.0, 0.0, 1500.0), 30f64.to_radians());
        let t = Vec3::new(0.0, 1500.0 / d.tan(), 0.0);
        let a = aim_off(p, 250.0, t);
        let v = Vec3::new(0.0, d.cos(), -d.sin()) * 250.0;
        let short = t[1] - impact(p, v, 0.0)[1];
        assert!(short > 50.0 && (a[1] - (t[1] + short)).abs() < 1e-6 && a[0].abs() < 1e-9, "{a:?}");
        // Not above it: the target itself.
        assert_eq!(aim_off(Vec3::new(0.0, 0.0, 0.0), 200.0, t), t);
        assert_eq!((Profile::of(true), Profile::of(false)), (Profile::Level, Profile::Dive));
    }

    #[test]
    fn target_and_weapon() {
        let units = [Vec3::new(400.0, 0.0, 0.0), Vec3::new(0.0, 300.0, 50.0), Vec3::new(5_000.0, 0.0, 0.0)];
        // The radar's lock wins; else the nearest within 500 m; else the point.
        assert_eq!(pick(Some(2), Vec3::ZERO, &units), Some(2));
        assert_eq!(pick(None, Vec3::ZERO, &units), Some(1));
        assert_eq!(pick(Some(7), Vec3::ZERO, &units), Some(1), "a lock not among them");
        assert_eq!(pick(None, Vec3::new(0.0, -2_000.0, 0.0), &units), None);
        let p = |kind, gps, count, id| Pylon { kind, gps, count, id };
        // An AIM-9 (570), an empty bomb pylon, then two pylons of MK-82s and one of GBU-31 (GPS, type 500).
        let mut ps = [p(570, false, 1, 1), p(500, false, 0, 2), p(500, false, 4, 3), p(500, false, 4, 3)];
        assert_eq!(pylon(&ps), Some((2, false)));
        assert_eq!(ripple(&ps, 2), 8);
        ps[1] = p(500, true, 1, 4);
        assert_eq!(pylon(&ps), Some((1, true)));
        assert_eq!(ripple(&ps, 1), 1);
        assert_eq!(pylon(&[p(650, false, 2, 5)]), Some((0, true)));
        assert_eq!(pylon(&[p(560, false, 19, 6)]), Some((0, false)));
        assert_eq!(ripple(&[p(560, false, 19, 6)], 0), RIPPLE_MAX);
        assert_eq!(pylon(&ps[..1]), None);
    }
}
