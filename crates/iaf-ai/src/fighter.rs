//! Modern IAF's enemy fighters (docs/ai.md §18; modern-iaf/docs/ai-plan.md K3): the trees of an enemy pair flown as a
//! [`Flight`](crate::Flight) ([`Flight::enemy`](crate::Flight::enemy)). On station (a CAP orbit, or where it was
//! spawned in the air) the lead waits for the ground's vector ([`crate::net::Gci`]); a bogey inside the commit range
//! commits the pair after the lead's reaction time; it flies the collision course, shoots inside its share of the
//! missile's envelope (the host's DLZ and launch, `combat.gd`), cranks while its missile flies, and defends against a
//! missile launched at it (the notch, the drag, the break) as its skill's tactics allow. The wingman holds line abreast
//! on the lead and shoots at the same bogey once its own radar holds it. A pair parked at a base ([`Enemy::based`])
//! scrambles on the ground's vector: the lead starts its engine after its reaction time, the wingman after the
//! clearance, both taxi and take off under the autopilot's ground loops, then the intercept; done (the bogey gone,
//! nothing left to shoot, or bingo) it goes home and lands, the wingman in the flight's landing sequence. Every figure
//! here is inferred: no open source gives the opposing force's numbers (modern-iaf/docs/research/enemies.md §5.1).

use iaf_flight::Vec3;
use iaf_flight::autopilot::{MODE_STEER, Steer};
use iaf_flight::vec3::wrap_pi;

use crate::bt::Node::{self, *};
use crate::bt::Status;
use crate::flight::{Member, defence, defend};
use crate::wingman::{before_takeoff, fly_task, flying, idle, keep_slot, set_mode};
use crate::{bfm, strike};

/// The commit: a bogey this near the station (m, horizontal; inferred: the MiG-29's 700 km range at a combat radius
/// with a fight's fuel, about a third of the way out).
pub const COMMIT_M: f64 = 90_000.0;
/// The pair goes back to its station once the bogey is this far from it (m).
pub const ABORT_M: f64 = 150_000.0;
/// The collision course: its load factor and speed (m/s, about Mach 0.95 at 6 km); the lead point's farthest look ahead
/// (s).
const INTERCEPT: (f32, f32) = (4.0, 300.0);
const LEAD_MAX_S: f64 = 120.0;
/// The crank while its missile flies: the bogey this far off the nose (deg; inside the radar's ±60°), at this speed.
const CRANK_DEG: f64 = 50.0;
const CRANK_SPEED: f32 = 250.0;
/// A radar missile launched from farther than this is dragged (outrun), nearer it is notched (m).
pub const DRAG_M: f64 = 20_000.0;
/// The drag's turn away (g: the missile far, the energy kept) and its speed (m/s).
const DRAG_G: f32 = 4.0;
const DRAG_SPEED: f32 = 400.0;
/// The notch and the drag go down into the radar's look-down: the steer point this far below the jet (m; the steer
/// loop's descent near 10° at 270 m/s, and its turn going down from 200 m below), down to this height above the ground
/// (m).
const DESCENT_M: f64 = 500.0;
const FLOOR_M: f64 = 500.0;
/// The CAP orbit: its radius (m); the turn (g) and speed (m/s, an endurance speed); the point it steers at, this far
/// round the circle ahead (deg, clockwise).
pub const CAP_R: f64 = 15_000.0;
const CAP: (f32, f32) = (2.0, 220.0);
const CAP_AHEAD_DEG: f64 = 30.0;
/// A steer point this far along a heading (m).
const FAR: f64 = 50_000.0;

/// A jet the pair knows of: where and how fast (the frame of the flight).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Bogey {
    pub pos: Vec3,
    pub vel: Vec3,
}

/// An enemy fighter's facts and memory ([`Member::enemy`]).
#[derive(Debug, Clone, Default)]
pub struct Enemy {
    /// Its station: the CAP orbit's centre at its height.
    pub station: Vec3,
    /// It started parked at a base ([`crate::Flight::enemy`]): it scrambles from there and lands there after.
    pub based: bool,
    /// A based jet's sortie is over (its intercept ended): it goes home.
    pub(crate) done: bool,
    /// The host's, this frame: the selected missile's envelope against the bogey (m: max, min; 0 none), a missile left,
    /// its own missile flying at the bogey.
    pub dlz: (f64, f64),
    pub armed: bool,
    /// The selected missile homes on infrared (the R-73): the pilot's helmet sight cues it on a bogey in sight, no
    /// radar needed ("a lock on any target the pilot could see ... almost 45 degrees off boresight", Wikipedia, the
    /// MiG-29; combat.gd's launch cone still holds).
    pub ir: bool,
    pub in_air: bool,
    /// What it knows of the bogey this decision: its own radar's contact, else the ground's vector, else its radar's
    /// jamming strobe.
    pub bogey: Option<Bogey>,
    pub contact: bool,
    /// Its radar sees the bogey's jammer beyond the burn-through: the strobe on its bearing (home on jam's angle
    /// track; no range, so no shot).
    pub strobe: bool,
    /// The pair committed (the lead's decision; the wingman reads it).
    pub committed: bool,
    /// When the bogey came inside the commit range (its reaction runs from then).
    pub(crate) seen: Option<f64>,
    /// When the bogey came inside its shot window (its reaction to the launch runs from then).
    pub(crate) aimed: Option<f64>,
    /// The bogey in its pilot's sight this decision (inside [`crate::bfm::VISUAL_M`], not behind its tail).
    pub visual: bool,
    /// The dogfight's move this decision (its point and the gun's laying error, [`crate::bfm::fight`]); its move's
    /// point the decision before, if it fought; the bogey's velocity at the last decision (its turn as seen); the gun's
    /// bursts.
    pub(crate) aim: Option<(crate::bfm::Aim, [f64; 2])>,
    pub(crate) fought: Option<crate::bfm::Aim>,
    pub(crate) last: Option<(f64, Vec3)>,
    /// The bogey's turn rate as seen this decision (rad/s; from `last`).
    pub(crate) rate: f64,
    pub(crate) bursts: u64,
    /// What it flies: cap, intercept, crank, slot, beam, notch, drag, break, or a dogfight's move (for tests and logs).
    pub phase: &'static str,
}

fn flat(a: Vec3, b: Vec3) -> f64 {
    (a[0] - b[0]).hypot(a[1] - b[1])
}

/// A heading (rad, clockwise from north) as a unit vector.
fn dir(h: f64) -> Vec3 {
    Vec3::new(h.sin(), h.cos(), 0.0)
}

fn bearing(from: Vec3, to: Vec3) -> f64 {
    (to[0] - from[0]).atan2(to[1] - from[1])
}

/// The point where a jet at `p` flying `speed` m/s meets `b` flying on straight (the collision course): `b` itself when
/// it cannot be caught, never more than [`LEAD_MAX_S`] ahead.
pub fn collision(p: Vec3, speed: f64, b: &Bogey) -> Vec3 {
    // |d + v·t| = s·t: (v·v − s²)·t² + 2·d·v·t + d·d = 0, the least positive root.
    let d = b.pos - p;
    let (qa, qb, qc) = (b.vel.dot(b.vel) - speed * speed, 2.0 * d.dot(b.vel), d.dot(d));
    let disc = qb * qb - 4.0 * qa * qc;
    let t = if qa.abs() < 1e-9 {
        if qb < 0.0 { -qc / qb } else { 0.0 }
    } else if disc < 0.0 {
        0.0
    } else {
        let r = [(-qb - disc.sqrt()) / (2.0 * qa), (-qb + disc.sqrt()) / (2.0 * qa)];
        r.into_iter().filter(|t| *t > 0.0).fold(f64::INFINITY, f64::min)
    };
    b.pos + b.vel * if t.is_finite() { t.min(LEAD_MAX_S) } else { 0.0 }
}

/// The CAP orbit's steer point for a jet at `p` round `station`: on the circle [`CAP_AHEAD_DEG`] ahead of it,
/// clockwise; the station itself from farther than two radii.
pub fn cap_point(p: Vec3, station: Vec3) -> Vec3 {
    let to = if flat(p, station) > 2.0 * CAP_R {
        station
    } else {
        station + dir(bearing(station, p) + CAP_AHEAD_DEG.to_radians()) * CAP_R
    };
    Vec3::new(to[0], to[1], station[2])
}

/// The crank's heading (rad) for a jet at `p` tracking `track` (rad) with the bogey at `b`: the bogey [`CRANK_DEG`]
/// off the nose on the side it is already on.
pub fn crank_heading(p: Vec3, track: f64, b: Vec3) -> f64 {
    let brg = bearing(p, b);
    let side = if wrap_pi(brg - track) >= 0.0 { 1.0 } else { -1.0 };
    brg - side * CRANK_DEG.to_radians()
}

/// The shot: inside its share (the skill's launch range) of the envelope from the minimum range out.
pub fn in_window(dist: f64, dlz: (f64, f64), share: f64) -> bool {
    let (max, min) = dlz;
    max > 0.0 && dist >= min && dist <= min + share * (max - min)
}

/// The steer point's height for the notch and the drag: [`DESCENT_M`] below the jet, not below [`FLOOR_M`] above the
/// ground.
fn down(m: &Member) -> f64 {
    let p = m.v.pos;
    (p[2] - DESCENT_M).max(m.v.ground_height as f64 + FLOOR_M).min(p[2])
}

/// The order `s` flown by the steer loop with the fighter's turn laws ([`Steer::fighter`]: rolled in at once, the
/// height held in a level turn), as `phase`; at its own heights, never the low level's terrain following (docs/ai.md
/// §20).
fn steer(m: &mut Member, s: Steer, phase: &'static str) -> Status {
    m.order.steer = Some(Steer { fighter: true, ..s });
    m.order.follow = None;
    m.order.mode = Some(MODE_STEER);
    m.enemy.phase = phase;
    Status::Running
}

/// The defence after a shot at it: a lock alone does not stop the attack (inferred; it is called, "spike" or "mud"); a
/// missile is answered as the wingmen answer it ([`defend`]: the call, the reaction, the turn, the decoys, the 5 s
/// clear), the turn by the skill's tactics: an infrared one the break into it; a radar one the wingmen's beam at its
/// height (tactics 0), the notch, the beam down into the radar's look-down (1), or from farther than [`DRAG_M`] the
/// drag, a 4 g turn away from it, then at full power going down (2).
pub(crate) fn evade(m: &mut Member) -> Status {
    if let Some(t) = m.threat.filter(|t| !t.launch) {
        // The lock is called once (our wingmen's call is heard; an enemy's is not), and the attack goes on.
        if m.called_level == 0 {
            m.calls.push(if t.ground { "mud" } else { "spike" });
        }
        m.threat = None;
        if !m.defending {
            m.called_level = 1;
            return Status::Failure;
        }
    }
    // A level defence (the break, the beam) holds the height it began at: its point's while it flies one (the steer
    // loop's; the dogfight's break flies the BFM loop).
    let level = m.defending && m.mode == MODE_STEER && ["beam", "break"].contains(&m.enemy.phase);
    let held = m.order.steer.filter(|_| level).map(|s| s.to[2]);
    let s = defend(m);
    // (Running without a threat: the turn held after the missile is gone.)
    let Some(t) = m.threat.filter(|_| s == Status::Running) else { return s };
    let h = held.unwrap_or(m.v.pos[2]);
    if t.ir {
        // The wingmen's break, flown with the fighter's turn laws.
        if let Some(st) = m.order.steer.as_mut() {
            (st.fighter, st.to[2]) = (true, h);
        }
        m.enemy.phase = "break";
        return s;
    }
    let (mut st, _) = defence(m, &t);
    let p = m.v.pos;
    let phase = if m.skill.tactics == 0 {
        "beam"
    } else if m.skill.tactics >= 2 && t.pos.distance(p) > DRAG_M {
        st.to = p + dir(bearing(t.pos, p)) * FAR;
        (st.g, st.speed) = (DRAG_G, DRAG_SPEED);
        "drag"
    } else {
        "notch"
    };
    st.to[2] = if phase == "beam" { h } else { down(m) };
    steer(m, st, phase)
}

/// Its missile at the bogey (the host's launch, `Order::shoot`): committed, its radar holding the bogey (an infrared
/// missile: or its pilot seeing it, [`Enemy::ir`]), a missile left and none of its own flying at it, the bogey inside
/// its window ([`in_window`]) for its reaction time (the launch's timing: the bogey goes deeper while it reacts). A
/// side effect: the tree goes on.
pub(crate) fn shoot(m: &mut Member) -> Status {
    let e = &m.enemy;
    let ready = e.bogey.filter(|_| e.committed && (e.contact || e.visual && e.ir) && e.armed && !e.in_air);
    if !ready.is_some_and(|b| in_window(b.pos.distance(m.v.pos), e.dlz, m.skill.launch_range)) {
        m.enemy.aimed = None;
    } else if m.now >= *m.enemy.aimed.get_or_insert(m.now) + m.skill.reaction_s {
        m.order.shoot = true;
    }
    Status::Failure
}

/// The lead committed: the collision course at the bogey, or the crank while its missile flies (tactics 1 and up); back
/// to the station (fails) once the bogey is lost, past [`ABORT_M`] from the station, or with nothing left to shoot.
pub(crate) fn intercept(m: &mut Member) -> Status {
    let e = &m.enemy;
    let Some(b) = e.bogey.filter(|b| flat(b.pos, e.station) <= ABORT_M && (e.armed || e.in_air)) else {
        (m.enemy.committed, m.enemy.seen, m.enemy.done) = (false, None, e.based);
        return Status::Failure;
    };
    let p = m.v.pos;
    if e.in_air && e.contact && m.skill.tactics >= 1 {
        let track = m.v.vel[0].atan2(m.v.vel[1]);
        let to = p + dir(crank_heading(p, track, b.pos)) * FAR;
        let s = Steer {
            to: Vec3::new(to[0], to[1], p[2]),
            g: INTERCEPT.0,
            speed: CRANK_SPEED,
            thr_max: 1.0,
            fighter: true,
        };
        return steer(m, s, "crank");
    }
    let to = collision(p, INTERCEPT.1 as f64, &b);
    steer(m, Steer { to, g: INTERCEPT.0, speed: INTERCEPT.1, thr_max: 1.0, fighter: true }, "intercept")
}

/// The commit: armed, a bogey inside [`COMMIT_M`] of the station for the lead's reaction time.
fn commit(m: &mut Member) -> Status {
    let e = &m.enemy;
    if !e.bogey.is_some_and(|b| e.armed && flat(b.pos, e.station) <= COMMIT_M) {
        m.enemy.seen = None;
        return Status::Failure;
    }
    if m.now < *m.enemy.seen.get_or_insert(m.now) + m.skill.reaction_s {
        return Status::Failure;
    }
    m.enemy.committed = true;
    intercept(m)
}

/// Parked at its base, its engine off: the scramble on the ground's vector (its radar is off on the ground): a bogey
/// inside [`COMMIT_M`] of the station for the lead's reaction time starts its engine (the crews on cockpit alert,
/// inferred); the wingmen start after it ([`crate::Flight`]'s clearance: the lead's engine running on the ground).
fn scramble(m: &mut Member) -> Status {
    let e = &m.enemy;
    if !e.bogey.is_some_and(|b| flat(b.pos, e.station) <= COMMIT_M) {
        m.enemy.seen = None;
    } else if m.now >= *m.enemy.seen.get_or_insert(m.now) + m.skill.reaction_s && !m.start_sent {
        (m.start_sent, m.order.start_engine) = (true, true);
    }
    Status::Running
}

/// A based jet goes home: its intercept over, nothing left to shoot with none of its missiles flying, or at bingo.
fn going_home(m: &Member) -> bool {
    let e = &m.enemy;
    e.based && (m.rtb || e.done || !e.armed && !e.in_air || m.fuel_kg <= m.bingo_kg)
}

/// Home: GoHomeCL (mode 8) to its route's landing waypoint and the landing; the flight's landing sequence sends the
/// wingmen after it.
fn home(m: &mut Member) -> Status {
    m.rtb = true;
    m.enemy.phase = "home";
    set_mode(m, 8)
}

/// On station: the CAP orbit ([`cap_point`]).
fn cap(m: &mut Member) -> Status {
    let to = cap_point(m.v.pos, m.enemy.station);
    steer(m, Steer { to, g: CAP.0, speed: CAP.1, thr_max: 1.0, fighter: true }, "cap")
}

fn slot(m: &mut Member) -> Status {
    m.enemy.phase = "slot";
    keep_slot(m)
}

/// The enemy lead: parked, the scramble, the take-off (a based lead), then its trees in the air; home after.
pub fn lead() -> Node<Member> {
    Sel(vec![
        Seq(vec![Cond(|m| !m.alive), Act(idle)]),
        Seq(vec![Cond(|m| m.landed && !m.engine_on), Act(idle)]),
        Seq(vec![
            Cond(|m| m.v.on_ground && !m.airborne),
            Sel(vec![Seq(vec![Cond(|m| !m.engine_on), Act(scramble)]), Act(|m| set_mode(m, 9))]),
        ]),
        Seq(vec![Cond(|m| m.mode == 9 && !m.airborne), Act(idle)]),
        Seq(vec![Cond(flying), Act(evade)]),
        Seq(vec![Cond(going_home), Act(home)]),
        Seq(vec![Cond(|m| m.mode == 8), Act(idle)]),
        Act(shoot),
        Seq(vec![Cond(bfm::fighting), Act(bfm::fight)]),
        Seq(vec![Cond(|m| m.enemy.committed), Act(intercept)]),
        // An attack ordered (strike.rs, `Flight::strike`): pressed before a commit; done, a based pair goes home.
        Seq(vec![Cond(strike::striking), Act(strike::fly)]),
        Act(commit),
        Act(cap),
    ])
}

/// The enemy wingman: its slot on the lead (the far rejoin from afar), its own defence, its shot at the pair's bogey; a
/// based one starts, taxies and takes off after the lead and lands when the flight sends it home.
pub fn wingman() -> Node<Member> {
    Sel(vec![
        Seq(vec![Cond(|m| !m.alive), Act(idle)]),
        Seq(vec![Cond(|m| m.landed && !m.engine_on), Act(idle)]),
        Seq(vec![Cond(flying), Act(evade)]),
        Seq(vec![Cond(|m| m.mode == 8 && m.released), Act(idle)]),
        before_takeoff(),
        Seq(vec![Cond(|m| m.released), Act(|m| set_mode(m, 8))]),
        Seq(vec![Cond(|m| m.rtb && m.lead_low), Act(|m| set_mode(m, 10))]),
        Act(shoot),
        Seq(vec![Cond(bfm::fighting), Act(bfm::fight)]),
        Seq(vec![Cond(strike::striking), Act(strike::fly)]),
        Seq(vec![Cond(|m| m.task.is_some()), Act(fly_task)]),
        Act(slot),
    ])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn collision_course() {
        let p = Vec3::ZERO;
        // A bogey 10 km north flying east at 200 m/s, met at 300 m/s: |(200t, 10000)| = 300t → t = 10000/√50000.
        let b = Bogey { pos: Vec3::new(0.0, 10_000.0, 0.0), vel: Vec3::new(200.0, 0.0, 0.0) };
        let c = collision(p, 300.0, &b);
        let t = 10_000.0 / (300.0f64.powi(2) - 200.0f64.powi(2)).sqrt();
        assert!((c[0] - 200.0 * t).abs() < 1.0 && (c[1] - 10_000.0).abs() < 1e-6, "{c:?}");
        // Faster than the fighter, going away: pure pursuit.
        let away = Bogey { pos: Vec3::new(0.0, 50_000.0, 0.0), vel: Vec3::new(0.0, 400.0, 0.0) };
        assert_eq!(collision(p, 300.0, &away), away.pos);
        // Far ahead: capped.
        let slow = Bogey { pos: Vec3::new(0.0, 200_000.0, 0.0), vel: Vec3::new(100.0, 0.0, 0.0) };
        assert!((collision(p, 101.0, &slow)[0] - 100.0 * LEAD_MAX_S).abs() < 1e-6);
    }

    #[test]
    fn cap_crank_and_window() {
        let st = Vec3::new(0.0, 0.0, 6000.0);
        // On the circle due north of the station: the point 30° clockwise round it, at the station's height.
        let q = cap_point(Vec3::new(0.0, CAP_R, 3000.0), st);
        let a = q[0].atan2(q[1]).to_degrees();
        assert!((a - CAP_AHEAD_DEG).abs() < 1e-9 && (flat(q, st) - CAP_R).abs() < 1e-6 && q[2] == 6000.0);
        // Far out: straight back to the station.
        assert_eq!(cap_point(Vec3::new(0.0, 3.0 * CAP_R, 0.0), st), st);
        // The bogey 20° right of a northbound track: the crank puts it 50° right (the nose 30° left).
        let b = dir(20f64.to_radians()) * 30_000.0;
        assert!((crank_heading(Vec3::ZERO, 0.0, b).to_degrees() + 30.0).abs() < 1e-9);
        let b = dir(-20f64.to_radians()) * 30_000.0;
        assert!((crank_heading(Vec3::ZERO, 0.0, b).to_degrees() - 30.0).abs() < 1e-9);
        // The window: from 5 km to 5 + 0.8 · 45 = 41 km of a 50 km envelope.
        assert!(in_window(41_000.0, (50_000.0, 5000.0), 0.8) && !in_window(41_100.0, (50_000.0, 5000.0), 0.8));
        assert!(!in_window(4_000.0, (50_000.0, 5000.0), 0.8) && !in_window(1.0, (0.0, 0.0), 1.0));
    }
}
