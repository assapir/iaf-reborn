//! The dogfight (docs/ai.md §18.2; modern-iaf/docs/ai-plan.md K4): an energy-aware BFM leaf for a fighter within sight
//! of its bogey. Each decision it reads the geometry (range, its own nose's angle to the bogey, the bogey's aspect),
//! the two jets' energy heights, its own turn from the 6-DoF's real limits (the corner speed: the wing's lift at the α
//! limit against the g limit, [`Member::corner`]) and the bogey's turn as seen (its velocity's swing between two
//! decisions), and picks a move after Shaw's "Fighter Combat" (1985): pursuit (lead, pure, lag) and the yo-yos when
//! offensive; the break, the reversal into a scissors and the guns jink when defensive; the rate fight, the radius
//! fight, the vertical, the scissors or the extension when neutral. The skill's tactics pick the branches
//! ([`Skill::tactics`]): 0 the plain ones (pure pursuit, a level turn at full g and full power, the break), 1 also the
//! lag, the low yo-yo, the speed held at the corner, the choice between the rate and the radius fight, the break down,
//! the flat scissors and the extension, 2 also the high yo-yo, the vertical, the rolling scissors and the jink. The
//! autopilot's BFM loop ([`MODE_BFM`]) flies the move's point in any plane; the point follows the bogey every frame
//! ([`aim_point`]). The gun fires when the lead point is on the nose inside the gun's range, off by the skill's laying
//! error ([`Skill::lay`]). Every figure here is inferred unless its comment names a source.

use iaf_flight::Vec3;
use iaf_flight::autopilot::{MODE_BFM, MODE_STEER, Steer};

use crate::bt::Status;
use crate::fighter::Bogey;
use crate::flight::Member;
use crate::skill::Skill;

/// The fight begins with the bogey this near (m; about 3 NM, inside a fighter's visual range) and ends past 1.5 times
/// it (the intercept again).
pub const BFM_M: f64 = 6000.0;
/// A pilot sees a jet this far (m), except in the cone behind its tail (deg off the tail; the MiG-29's "poor view to
/// the rear", modern-iaf/docs/research/enemies.md §4.2).
pub const VISUAL_M: f64 = 8000.0;
pub const BLIND_DEG: f64 = 30.0;
/// The gun: its range (m; inside it the shot; the 30 mm's, inferred), the round's speed (m/s, the GSh-301's muzzle
/// velocity, about 860 m/s, inferred), the lead point this near the nose for a burst (deg).
pub const GUN_M: (f64, f64) = (330.0, 900.0);
const ROUND_V: f64 = 860.0;
const GUN_DEG: f64 = 2.0;
/// combat.gd's gun cone (`CONE_GUN`, deg): the launch's check on the bogey itself.
const GUN_CONE_DEG: f64 = 5.0;
/// Offensive: the bogey within this angle off the nose and this angle off its tail (deg).
const OFFENSIVE_DEG: (f64, f64) = (90.0, 90.0);
/// Defensive: the bogey behind its own beam with its nose within this angle of us (deg), this near (m).
const DEFENSIVE_DEG: f64 = 60.0;
const DEFENSIVE_M: f64 = 5000.0;
/// The lag pursuit's point, this long behind the bogey on its path (s); taken when closing faster than this (m/s)
/// inside this range (m), or when its turn circle is wider than the bogey's.
const LAG_S: f64 = 1.5;
const OVERSHOOT: (f64, f64) = (60.0, 2500.0);
/// The closure control when offensive (Shaw's closure control, flown here by the throttle and the speed brake): the
/// closure wanted is this share (1/s) of the range past the gun's resting range (m: inside the gun's), at
/// most this much (m/s) either way, so it settles there behind the bogey (inferred).
const CLOSE_K: f64 = 0.1;
const REST_M: f64 = 600.0;
const CLOSE_MAX: f64 = 100.0;
/// The yo-yos: the high one (closing at twice the lag's rate, far off the bogey's tail: up out of its plane, deg off
/// its tail), the low one (out of the gun's range and not closing: down inside its turn, m); the point's height off
/// the bogey, as a share of the range.
const HIGH_YOYO_DEG: f64 = 45.0;
const LOW_YOYO_M: f64 = 2000.0;
const YOYO: f64 = 0.4;
/// The energy that decides the vertical (m of energy height ahead; less behind: the break down).
const ENERGY_M: f64 = 600.0;
/// The guns jink: a new direction this often (s), the point this far up or down off the bogey (share of the range).
const JINK_S: f64 = 2.0;
const JINK: f64 = 1.0;
/// The speeds: the radius fight's (share of the corner speed); the rate fight's least before it unloads to gain
/// speed (share), and the load factor it then pulls; the plain tactics' (m/s: full power, no speed held).
const RADIUS_SPEED: f32 = 0.75;
const UNLOAD: (f32, f32) = (0.85, 3.0);
const FULL: f32 = 600.0;
/// The scissors (Shaw: two jets close and slow, side by side, each reversing to get behind the other; the slower one
/// wins): the bogey within this range (m), off its wing (its nose this far off the bogey, deg), both flying the same
/// way (the paths within [`SCISSORS_DEG`]'s first angle) and the bogey slower than the corner speed; flown at this
/// share of the corner speed, the speed brake out. Defensive, an attacker closing faster than [`OVERSHOOT`]'s rate
/// inside the gun's range is made to overshoot by the same slow reversal.
const SCISSORS_M: f64 = 1500.0;
const SCISSORS_DEG: (f64, f64) = (45.0, 135.0);
const SCISSORS_SPEED: f32 = 0.6;
/// The extension (Shaw's separation: unloaded at full power, out of the fight, to come back with the energy): neutral,
/// this much energy height behind (m), farther than this (m), the bogey's nose this far or more off it (deg: 180 less
/// its aspect angle: it is in the bogey's rear quarter, its nose a long turn away); the turn it keeps (g) and the
/// dive's point below (share of the range).
const EXTEND_M: (f64, f64) = (600.0, 3000.0);
const EXTEND_NOSE_DEG: f64 = 120.0;
const EXTEND_G: f32 = 2.0;
const EXTEND_DIVE: f64 = 0.1;
/// The corner speed when the flight model gives none (the original model; m/s, about 330 kt, inferred).
const CORNER: f32 = 170.0;
/// The fight's floor: no point below this height above the ground (m; the intercept's notch floor).
pub const FLOOR_M: f64 = 500.0;
const G: f64 = 9.80665;

/// Where the move's point lies: on the bogey's path `lead_s` ahead (behind when negative), `up` × the range above it
/// (below when negative); `level` at that height (m; a level turn: the height it began at); `away`: the bogey's
/// point mirrored through its own position (the extension: straight away from it), `up` then off its own height.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Aim {
    pub lead_s: f64,
    pub up: f64,
    pub level: Option<f64>,
    pub away: bool,
}

/// A move: its name, its point, the load factor (g) and the speed (m/s) it flies.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Move {
    pub name: &'static str,
    pub aim: Aim,
    pub g: f32,
    pub speed: f32,
}

/// One jet as the leaf sees it: where, how fast, its turn rate (rad/s; its own the most it can turn at its corner
/// speed, the bogey's as seen).
#[derive(Debug, Clone, Copy)]
pub struct Jet {
    pub pos: Vec3,
    pub vel: Vec3,
    pub rate: f64,
}

impl Jet {
    /// The energy height, m: its height and its speed's.
    fn energy(&self) -> f64 {
        self.pos[2] + self.vel.dot(self.vel) / (2.0 * G)
    }
}

/// The angle between two vectors, deg.
fn angle(a: Vec3, b: Vec3) -> f64 {
    let d = a.length() * b.length();
    if d < 1e-9 { 0.0 } else { (a.dot(b) / d).clamp(-1.0, 1.0).acos().to_degrees() }
}

/// The geometry: the range, its nose's angle to the bogey (the antenna train angle), and its own angle off the bogey's
/// tail (the aspect angle: 0 behind it, 180 head-on), deg.
pub fn geometry(own: &Jet, b: &Jet) -> (f64, f64, f64) {
    let los = b.pos - own.pos;
    (los.length(), angle(own.vel, los), angle(b.vel, los))
}

/// The turn rate at the corner speed `corner` with the g limit `max_g` (rad/s): g √(n² − 1) / V.
pub fn corner_rate(corner: f32, max_g: f32) -> f64 {
    G * ((max_g * max_g) as f64 - 1.0).max(0.0).sqrt() / corner.max(1.0) as f64
}

/// Defensive: the bogey behind its beam with its nose within [`DEFENSIVE_DEG`] of us, inside [`DEFENSIVE_M`] (the
/// geometry's range, antenna train and aspect angles, [`geometry`]).
pub fn defensive(range: f64, ata: f64, aa: f64) -> bool {
    aa > 180.0 - DEFENSIVE_DEG && ata > 90.0 && range < DEFENSIVE_M
}

/// The move for `own` against the bogey `b` at `skill`, its corner speed `corner` and g limit `max_g`; `now` (s) times
/// the jink. No move asks more than the wing gives at its speed (no pull into the α limit's drag).
pub fn choose(own: &Jet, b: &Jet, corner: f32, max_g: f32, skill: &Skill, now: f64) -> Move {
    let t = skill.tactics;
    let (range, ata, aa) = geometry(own, b);
    let closure = -(b.vel - own.vel).dot((b.pos - own.pos) / range.max(1.0));
    let de = own.energy() - b.energy();
    let speed = own.vel.length() as f32;
    // The most the wing gives now: below the corner speed (V / corner)² of the g limit.
    let max_g = max_g.min(max_g * (speed / corner.max(1.0)).powi(2)).max(1.0);
    let full = |name, aim| Move { name, aim, g: max_g, speed: FULL };
    let corner_move = |name, aim, speed_to| {
        let unload = speed < UNLOAD.0 * corner;
        Move { name, aim, g: if unload { UNLOAD.1.min(max_g) } else { max_g }, speed: speed_to }
    };
    let at = Aim::default();
    if ata < OFFENSIVE_DEG.0 && aa < OFFENSIVE_DEG.1 {
        let tof = range / (ROUND_V + speed as f64);
        let lead = Aim { lead_s: tof, ..at };
        // The speed that brings the closure to the one wanted, never below the corner speed (its best turn).
        let want = (CLOSE_K * (range - REST_M)).clamp(-CLOSE_MAX, CLOSE_MAX);
        let close = ((speed as f64 + want - closure) as f32).max(corner);
        let chase = |name, aim| Move { name, aim, g: max_g, speed: close };
        if t == 0 {
            return chase("pursuit", if range <= GUN_M.1 { lead } else { at });
        }
        // Its turn circle wider than the bogey's: it would fly outside it (rate over speed, its corner's against the
        // bogey's as seen).
        let wide = speed as f64 / own.rate > b.vel.length() / b.rate.max(1e-3);
        if t >= 2 && closure > 2.0 * OVERSHOOT.0 && range < OVERSHOOT.1 && aa > HIGH_YOYO_DEG {
            return corner_move("high yo-yo", Aim { lead_s: -LAG_S, up: YOYO, ..at }, close);
        }
        if range < OVERSHOOT.1 && closure > OVERSHOOT.0 || wide && range > GUN_M.1 && range < OVERSHOOT.1 {
            return corner_move("lag", Aim { lead_s: -LAG_S, ..at }, close);
        }
        // Out of the gun's range and falling back, or slow: down inside the bogey's turn for speed.
        if range > LOW_YOYO_M && closure < 0.0 || range > GUN_M.1 && speed < UNLOAD.0 * corner {
            return full("low yo-yo", Aim { up: -YOYO, ..at });
        }
        let (name, aim) = if range <= GUN_M.1 { ("lead", lead) } else { ("pursuit", at) };
        return chase(name, aim);
    }
    // Slow, pulling into the bogey with the speed brake out: it flies past (the overshoot) or falls behind.
    let scissors = |name| Move {
        name,
        aim: Aim { up: if t >= 2 { YOYO } else { 0.0 }, ..at },
        g: max_g,
        speed: SCISSORS_SPEED * corner,
    };
    if defensive(range, ata, aa) {
        if t >= 1 && range < GUN_M.1 && closure > OVERSHOOT.0 {
            return scissors("reversal");
        }
        if t >= 2 && range < GUN_M.1 * 1.5 {
            let up = if (now / JINK_S).floor() as i64 % 2 == 0 { JINK } else { -JINK };
            return full("jink", Aim { up, ..at });
        }
        if t >= 1 && de < -ENERGY_M {
            return full("break down", Aim { up: -YOYO, ..at });
        }
        return full("break", Aim { level: (t == 0).then_some(own.pos[2]), ..at });
    }
    if t == 0 {
        return full("turn", Aim { level: Some(own.pos[2]), ..at });
    }
    let together = angle(own.vel, b.vel) < SCISSORS_DEG.0 && (b.vel.length() as f32) < corner;
    if range < SCISSORS_M && (SCISSORS_DEG.0..=SCISSORS_DEG.1).contains(&ata) && together {
        return scissors(if t >= 2 { "rolling scissors" } else { "flat scissors" });
    }
    if de < -EXTEND_M.0 && range > EXTEND_M.1 && 180.0 - aa >= EXTEND_NOSE_DEG {
        let aim = Aim { up: -EXTEND_DIVE, away: true, ..at };
        return Move { name: "extend", aim, g: EXTEND_G.min(max_g), speed: FULL };
    }
    if t >= 2 && de > ENERGY_M && speed > corner {
        return corner_move("vertical", Aim { up: YOYO, ..at }, FULL);
    }
    if own.rate >= b.rate {
        return corner_move("rate", at, corner);
    }
    Move { name: "radius", aim: at, g: max_g, speed: RADIUS_SPEED * corner }
}

/// The move's point against the bogey as it is now, from `p` (its own position), off by `lay` (rad: across the line
/// of sight, up) at the range, not below `floor` (m).
pub fn aim_point(p: Vec3, b: &Bogey, aim: &Aim, lay: [f64; 2], floor: f64) -> Vec3 {
    let mut to = b.pos + b.vel * aim.lead_s;
    let range = (to - p).length();
    if aim.away {
        to = p * 2.0 - to;
        to[2] = p[2];
    }
    to[2] += aim.up * range;
    let los = (to - p).try_normalize().unwrap_or(Vec3::NORTH);
    let across = los.cross(Vec3::UP).try_normalize().unwrap_or(Vec3::new(1.0, 0.0, 0.0));
    to += (across * lay[0] + across.cross(los) * lay[1]) * range;
    if let Some(h) = aim.level {
        to[2] = h;
    }
    to[2] = to[2].max(floor);
    to
}

/// The fight's floor under `m`: [`FLOOR_M`] above the ground.
pub fn floor(m: &Member) -> f64 {
    m.v.ground_height as f64 + FLOOR_M
}

/// The bogey's turn rate as seen (rad/s): the swing of its velocity since the last decision.
pub(crate) fn seen_rate(last: Option<(f64, Vec3)>, now: f64, vel: Vec3) -> f64 {
    last.filter(|(t, _)| now > *t).map_or(0.0, |(t, v)| angle(v, vel).to_radians() / (now - t))
}

/// The fight's condition: committed with the bogey in sight inside [`BFM_M`] (1.5 times it once fighting), and
/// something to shoot.
pub fn fighting(m: &Member) -> bool {
    let e = &m.enemy;
    let reach = if e.fought.is_some() { 1.5 * BFM_M } else { BFM_M };
    let near = e.visual && e.bogey.is_some_and(|b| b.pos.distance(m.v.pos) <= reach);
    near && e.committed && (e.armed || e.in_air)
}

/// The leaf: the move ([`choose`]) flown by the BFM loop, its point at the bogey now ([`aim_point`], the gun's laying
/// error on the lead point), and the gun's burst when the gun's lead point is on the nose inside the gun's range.
pub fn fight(m: &mut Member) -> Status {
    let Some(b) = m.enemy.bogey else { return Status::Failure };
    let corner = m.corner.unwrap_or(CORNER);
    let own = Jet { pos: m.v.pos, vel: m.v.vel, rate: corner_rate(corner, m.v.max_g) };
    let rate = m.enemy.rate;
    let mut mv = choose(&own, &Jet { pos: b.pos, vel: b.vel, rate }, corner, m.v.max_g, &m.skill, m.now);
    // A level move goes on at the height it began at (the steer loop's height law brings it back there).
    if let (Some(_), Some(Aim { level: Some(h), .. })) = (mv.aim.level, m.enemy.fought) {
        mv.aim.level = Some(h);
    }
    let range = b.pos.distance(m.v.pos);
    let lay = m.skill.lay(m.number as u64, m.enemy.bursts);
    let to = aim_point(m.v.pos, &b, &mv.aim, if mv.aim.lead_s > 0.0 { lay } else { [0.0; 2] }, floor(m));
    // The burst on the gun's own lead point, whatever the move (a lag behind a bogey flying straight has it on the
    // nose); the host's launch also wants the bogey itself inside its 5° gun cone, combat.gd.
    let tof = range / (ROUND_V + m.v.vel.length());
    let gun = aim_point(m.v.pos, &b, &Aim { lead_s: tof, ..Aim::default() }, lay, f64::NEG_INFINITY);
    let on = angle(m.v.vel, gun - m.v.pos) < GUN_DEG && angle(m.v.vel, b.pos - m.v.pos) < GUN_CONE_DEG;
    if on && (GUN_M.0..=GUN_M.1).contains(&range) && m.enemy.armed {
        m.order.gun = true;
        m.enemy.bursts += 1;
    }
    m.enemy.aim = Some((mv.aim, lay));
    // A level move (the plain tactics' break and turn) is the steer loop's level turn with the fighter's laws: the BFM
    // loop's turn toward a point behind took the path's own pitch for its plane and climbed (1.6 km in 12 s).
    m.order.steer = Some(Steer { to, g: mv.g, speed: mv.speed, thr_max: 1.0, fighter: true });
    m.order.mode = Some(if mv.aim.level.is_some() { MODE_STEER } else { MODE_BFM });
    // An air fight flies its own heights, never the low level's terrain following (docs/ai.md §20).
    m.order.follow = None;
    m.enemy.phase = crate::fighter::DefPhase::Bfm(mv.name);
    Status::Running
}

#[cfg(test)]
mod tests {
    use super::*;

    fn jet(x: f64, y: f64, h: f64, vx: f64, vy: f64) -> Jet {
        Jet { pos: Vec3::new(x, y, 5000.0), vel: Vec3::new(vx, vy, 0.0), rate: h }
    }

    #[test]
    fn moves_by_geometry_energy_and_tactics() {
        let s = |t| Skill { tactics: t, ..Skill::MEDIUM };
        let pick = |own: &Jet, b: &Jet, t| choose(own, b, 220.0, 9.0, &s(t), 0.0).name;
        // 600 m behind a bogey flying north at the same speed: the gun's lead.
        let own = jet(0.0, 0.0, 0.3, 0.0, 250.0);
        assert_eq!(pick(&own, &jet(0.0, 600.0, 0.2, 0.0, 250.0), 1), "lead");
        // Slow 1.5 km behind: the low yo-yo.
        assert_eq!(pick(&jet(0.0, 0.0, 0.3, 0.0, 150.0), &jet(0.0, 1500.0, 0.2, 0.0, 150.0), 1), "low yo-yo");
        // 2 km behind, closing at 150 m/s: the lag (1), the high yo-yo far off its tail (2), pure pursuit (0).
        let b = jet(1000.0, 1700.0, 0.2, 100.0, 0.0);
        let fast = jet(0.0, 0.0, 0.3, 0.0, 250.0);
        assert_eq!(pick(&fast, &b, 0), "pursuit");
        assert_eq!(pick(&fast, &b, 1), "lag");
        assert_eq!(pick(&fast, &b, 2), "high yo-yo");
        // 3 km behind and falling back: the low yo-yo.
        assert_eq!(pick(&jet(0.0, 0.0, 0.3, 0.0, 200.0), &jet(0.0, 3000.0, 0.2, 0.0, 260.0), 1), "low yo-yo");
        // The bogey 1 km behind, nose on: the break (level for 0), the jink (2); behind on energy: the break down.
        let behind = jet(0.0, -1000.0, 0.2, 0.0, 250.0);
        let me = jet(0.0, 0.0, 0.3, 0.0, 250.0);
        assert_eq!(choose(&me, &behind, 220.0, 9.0, &s(0), 0.0).aim, Aim { level: Some(5000.0), ..Aim::default() });
        assert_eq!(pick(&me, &behind, 1), "break");
        assert_eq!(pick(&me, &behind, 2), "jink");
        let fast_behind = Jet { pos: Vec3::new(0.0, -3000.0, 6000.0), ..behind };
        assert_eq!(pick(&me, &fast_behind, 1), "break down");
        // Head-on: a level turn (0); the rate fight when it out-turns the bogey, else the radius fight (1); the
        // vertical with the energy (2).
        let head = jet(0.0, 4000.0, 0.2, 0.0, -250.0);
        assert_eq!(pick(&me, &head, 0), "turn");
        assert_eq!(pick(&me, &head, 1), "rate");
        assert_eq!(pick(&jet(0.0, 0.0, 0.1, 0.0, 250.0), &head, 1), "radius");
        let high = Jet { pos: Vec3::new(0.0, 0.0, 6000.0), ..me };
        assert_eq!(pick(&high, &head, 2), "vertical");
        // Side by side 800 m apart, abeam, the bogey slow: the flat scissors (1), the rolling one (2), the plain turn
        // (0); slow. Passing head-on: no scissors.
        let abeam = jet(800.0, 0.0, 0.2, 0.0, 200.0);
        assert_eq!(pick(&me, &abeam, 0), "turn");
        assert_eq!(pick(&me, &abeam, 1), "flat scissors");
        let mv = choose(&me, &abeam, 220.0, 9.0, &s(2), 0.0);
        assert_eq!((mv.name, mv.speed, mv.aim.up), ("rolling scissors", SCISSORS_SPEED * 220.0, YOYO));
        assert!(!pick(&me, &jet(800.0, 0.0, 0.2, 0.0, -200.0), 1).contains("scissors"));
        // The bogey 700 m behind closing at 100 m/s: the reversal (1, 2) before the jink; the break (0).
        let closing = jet(0.0, -700.0, 0.2, 0.0, 350.0);
        assert_eq!(pick(&me, &closing, 0), "break");
        assert_eq!(pick(&me, &closing, 1), "reversal");
        assert_eq!(pick(&me, &closing, 2), "reversal");
        // 4 km off (abeam: not offensive), 1 km of energy height lower, the bogey flying away: the extension (1, 2),
        // unloaded at full power; its nose on it: no extension.
        let low = Jet { pos: Vec3::new(0.0, 0.0, 4000.0), ..me };
        let crossing = Jet { pos: Vec3::new(4000.0, 0.0, 5000.0), vel: Vec3::new(250.0, 0.0, 0.0), rate: 0.2 };
        assert_eq!(pick(&low, &crossing, 0), "turn");
        let mv = choose(&low, &crossing, 220.0, 9.0, &s(1), 0.0);
        assert_eq!((mv.name, mv.g, mv.speed, mv.aim.away), ("extend", EXTEND_G, FULL, true));
        let pointing = Jet { vel: Vec3::new(-250.0, 0.0, 0.0), ..crossing };
        assert_ne!(pick(&low, &pointing, 1), "extend");
        // Below the corner speed the rate fight unloads.
        let slow = jet(0.0, 0.0, 0.3, 0.0, 150.0);
        let mv = choose(&slow, &head, 220.0, 9.0, &s(1), 0.0);
        assert_eq!((mv.name, mv.g), ("rate", UNLOAD.1));
    }

    #[test]
    fn aim_points() {
        let b = Bogey { pos: Vec3::new(0.0, 1000.0, 5000.0), vel: Vec3::new(200.0, 0.0, 0.0) };
        let p = Vec3::new(0.0, 0.0, 4000.0);
        // Lead 0.5 s, lag 1.5 s, the high yo-yo 0.4 of the range above, level at its own height.
        assert_eq!(
            aim_point(p, &b, &Aim { lead_s: 0.5, ..Aim::default() }, [0.0; 2], 0.0),
            Vec3::new(100.0, 1000.0, 5000.0)
        );
        let lag = aim_point(p, &b, &Aim { lead_s: -LAG_S, up: YOYO, ..Aim::default() }, [0.0; 2], 0.0);
        let r = (Vec3::new(-300.0, 1000.0, 5000.0) - p).length();
        assert!((lag[0] + 300.0).abs() < 1e-9 && (lag[2] - 5000.0 - YOYO * r).abs() < 1e-9, "{lag:?}");
        // The extension: the bogey's point mirrored through its own, a share of the range below its own height.
        let ext = aim_point(p, &b, &Aim { up: -EXTEND_DIVE, away: true, ..Aim::default() }, [0.0; 2], 0.0);
        let r = (b.pos - p).length();
        assert!(ext[1] == -1000.0 && ext[0] == 0.0 && (ext[2] - 4000.0 + EXTEND_DIVE * r).abs() < 1e-9, "{ext:?}");
        assert_eq!(aim_point(p, &b, &Aim { level: Some(4000.0), ..Aim::default() }, [0.0; 2], 0.0)[2], 4000.0);
        // A laying error of 2 mrad across moves the point 2 m per km sideways.
        let off =
            aim_point(Vec3::ZERO, &Bogey { pos: Vec3::new(0.0, 1000.0, 0.0), ..b }, &Aim::default(), [2e-3, 0.0], -1e9);
        assert!((off[0].abs() - 2.0).abs() < 1e-6 && off[2].abs() < 1e-6, "{off:?}");
        // The corner rate: 9 g at 220 m/s turns 22.8°/s.
        assert!((corner_rate(220.0, 9.0).to_degrees() - 22.8).abs() < 0.1);
        assert!((seen_rate(Some((0.0, Vec3::NORTH)), 0.5, Vec3::new(1.0, 1.0, 0.0)).to_degrees() - 90.0).abs() < 1e-9);
    }
}
