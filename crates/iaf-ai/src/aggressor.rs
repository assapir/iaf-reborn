//! Modern IAF's aggressor round (modern-iaf/docs/training-plan.md §3, phase 7; docs/ai.md §26): the player against an
//! aggressor F-16 flown by the enemy fighter's trees (`fighter`, `bfm`) at the High skill's tactics, with simulated
//! shots as in real training. A round is a list of set-ups flown in turn; each engagement starts in the air from its
//! set-up ([`place`]): "you at his six o'clock, 3,000 ft" ([`SetUp::Offensive`]), the defensive mirror of it, the
//! high-aspect pass and the BVR head-on start. A shot at the other jet is not fired as a live weapon: the host flies
//! the missile unseen and harmless on the existing physical missile (seeker, decoys, jamming) and asks [`missile_kill`]
//! at its burst; the gun's rounds fly against the shielded jets and [`GUN_HITS`] hits on the other jet are a kill.
//! [`Round`] keeps the calls (the shooter's "Fox" or "guns" at the shot, "kill" when the shot kills), takes the killed
//! jet out of the fight, calls "knock it off" and starts the next set-up. Every figure is inferred unless its comment
//! names a source; the calls are NATO brevity (modern-iaf/docs/research/radio-terms.md).

use iaf_flight::Vec3;

/// One foot, m.
const FT: f64 = 0.3048;
/// The BFM set-ups' height (m above sea level: 15,000 ft) and speed (m/s true, about 450 kt).
pub const BFM_ALT: f64 = 15_000.0 * FT;
pub const BFM_SPEED: f64 = 230.0;
/// The offensive and defensive set-ups' range: the attacker 3,000 ft behind the other jet (the user's example, 28 Nov
/// 2026: "you at his six o'clock, 3,000 ft").
pub const PERCH: f64 = 3_000.0 * FT;
/// The high-aspect set-up: head-on this far apart (m, about 3.2 NM), each this far off the other's line (m) so they
/// pass side by side.
const PASS_RANGE: f64 = 6_000.0;
const PASS_SIDE: f64 = 450.0;
/// The BVR set-up: head-on 40 NM apart at 20,000 ft and about 490 kt.
const BVR_RANGE: f64 = 40.0 * 1852.0;
pub const BVR_ALT: f64 = 20_000.0 * FT;
pub const BVR_SPEED: f64 = 250.0;
/// A fighter takes this many gun hits (the 20 mm's power 100 against a fighter's strength 300 on the sim's damage
/// scale, modern-iaf/data/db/weapons/20mm.json).
pub const GUN_HITS: u32 = 3;
/// After the kill: "kill" this long after the shot's end (s), "knock it off" this long after "kill" (s).
const KILL_S: f64 = 1.0;
const KIO_S: f64 = 3.0;
/// The next set-up this long after "knock it off" (s).
const NEXT_S: f64 = 6.0;
/// "Guns" is called once a burst: a new call this long after the last round (s).
const BURST_S: f64 = 1.5;
/// Knock it off without a kill: the two jets farther apart than this (m; BFM, BVR), the engagement older than this
/// (s; BFM, BVR), or either jet below the training floor (m above the ground: 5,000 ft).
const APART: (f64, f64) = (20_000.0, 150_000.0);
const LONGEST: (f64, f64) = (180.0, 300.0);
pub const FLOOR: f64 = 5_000.0 * FT;

/// A set-up of an engagement.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SetUp {
    /// The player 3,000 ft behind the aggressor, both flying the same way.
    Offensive,
    /// The aggressor 3,000 ft behind the player.
    Defensive,
    /// Head-on, passing side by side.
    HighAspect,
    /// Head-on, 40 NM apart: the radar's fight.
    Bvr,
}

impl SetUp {
    pub const ALL: [SetUp; 4] = [SetUp::Offensive, SetUp::Defensive, SetUp::HighAspect, SetUp::Bvr];

    pub fn name(self) -> &'static str {
        match self {
            SetUp::Offensive => "offensive",
            SetUp::Defensive => "defensive",
            SetUp::HighAspect => "high_aspect",
            SetUp::Bvr => "bvr",
        }
    }

    pub fn from_name(s: &str) -> Option<SetUp> {
        SetUp::ALL.into_iter().find(|u| u.name() == s)
    }

    fn bvr(self) -> usize {
        usize::from(self == SetUp::Bvr)
    }
}

/// Where a jet starts: position (world: x east, y north, z up, m), heading (deg from north) and true speed (m/s).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Start {
    pub pos: Vec3,
    pub heading: f64,
    pub speed: f64,
}

/// The two jets' starts of `setup` round `at` (world; its height is ignored: the set-up's own), the player heading
/// `heading` (deg).
pub fn place(setup: SetUp, at: Vec3, heading: f64) -> (Start, Start) {
    let h = heading.to_radians();
    let fwd = Vec3::new(h.sin(), h.cos(), 0.0);
    let right = Vec3::new(h.cos(), -h.sin(), 0.0);
    let back = (heading + 180.0).rem_euclid(360.0);
    let (alt, speed) = if setup == SetUp::Bvr { (BVR_ALT, BVR_SPEED) } else { (BFM_ALT, BFM_SPEED) };
    let p = |v: Vec3| Vec3::new(at.x + v.x, at.y + v.y, alt);
    let s = |pos, heading| Start { pos, heading, speed };
    match setup {
        SetUp::Offensive => (s(p(fwd * -PERCH), heading), s(p(Vec3::ZERO), heading)),
        SetUp::Defensive => (s(p(Vec3::ZERO), heading), s(p(fwd * -PERCH), heading)),
        SetUp::HighAspect => {
            let half = fwd * (PASS_RANGE / 2.0);
            (s(p(half * -1.0 + right * PASS_SIDE), heading), s(p(half - right * PASS_SIDE), back))
        }
        SetUp::Bvr => (s(p(fwd * (-BVR_RANGE / 2.0)), heading), s(p(fwd * (BVR_RANGE / 2.0)), back)),
    }
}

/// A simulated missile kills when it bursts within its blast radius (m) of the other jet and its fuze had armed (a
/// physical missile ended before its fuze armed is a dud: modern-iaf/docs/weapons.md).
pub fn missile_kill(burst: Vec3, target: Vec3, radius: f64, dud: bool) -> bool {
    !dud && burst.distance(target) <= radius
}

/// The two jets of a round.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    Player,
    Aggressor,
}

impl Side {
    fn i(self) -> usize {
        self as usize
    }

    pub fn other(self) -> Side {
        match self {
            Side::Player => Side::Aggressor,
            Side::Aggressor => Side::Player,
        }
    }
}

/// A radio call of the round: who says it, and its word ("fox_1", "fox_2", "fox_3", "guns", "kill", "kio").
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Call {
    pub from: Side,
    pub id: &'static str,
}

/// The round: its set-ups in turn (round again after the last), the engagement's state and the calls due.
#[derive(Clone, Debug)]
pub struct Round {
    setups: Vec<SetUp>,
    index: usize,
    /// When the engagement started (s).
    since: f64,
    /// The jet killed in this engagement.
    dead: Option<Side>,
    /// The gun hits each side scored in this engagement.
    hits: [u32; 2],
    /// The last gun round each side fired (s).
    last_round: [f64; 2],
    /// When "knock it off" was called.
    kio: Option<f64>,
    calls: Vec<(f64, Call)>,
    /// The engagements flown to their end, and the kills each side scored over the round.
    pub engagements: u32,
    pub kills: [u32; 2],
}

impl Round {
    /// A round of `setups` (none: every BFM set-up in turn), its first engagement started at `now`.
    pub fn new(setups: Vec<SetUp>, now: f64) -> Round {
        let setups = if setups.is_empty() { SetUp::ALL[..3].to_vec() } else { setups };
        Round {
            setups,
            index: 0,
            since: now,
            dead: None,
            hits: [0; 2],
            last_round: [f64::NEG_INFINITY; 2],
            kio: None,
            calls: Vec::new(),
            engagements: 0,
            kills: [0; 2],
        }
    }

    /// The engagement's set-up.
    pub fn setup(&self) -> SetUp {
        self.setups[self.index]
    }

    /// The jet `side` is out of the fight: killed, or the engagement knocked off.
    pub fn out(&self, side: Side) -> bool {
        self.dead == Some(side) || self.kio.is_some()
    }

    /// Whether "knock it off" was called in this engagement.
    pub fn knocked_off(&self) -> bool {
        self.kio.is_some()
    }

    /// `by` launched a missile whose call is `fox` ("fox_1".."fox_3") at `now`: the call, unless `by` is out.
    pub fn fox(&mut self, now: f64, by: Side, fox: &'static str) -> bool {
        if self.out(by) {
            return false;
        }
        self.calls.push((now, Call { from: by, id: fox }));
        true
    }

    /// `by` fired a gun round at `now`: "guns" at a burst's first round.
    pub fn round_fired(&mut self, now: f64, by: Side) {
        if self.out(by) {
            return;
        }
        if now - self.last_round[by.i()] > BURST_S {
            self.calls.push((now, Call { from: by, id: "guns" }));
        }
        self.last_round[by.i()] = now;
    }

    /// `by`'s simulated missile killed the other jet at `now` ([`missile_kill`]): whether it counts (neither out).
    pub fn missile_hit(&mut self, now: f64, by: Side) -> bool {
        if self.out(by) || self.out(by.other()) {
            return false;
        }
        self.kill(now, by);
        true
    }

    /// One of `by`'s gun rounds hit the other jet at `now`: the [`GUN_HITS`]th is the kill (true).
    pub fn gun_hit(&mut self, now: f64, by: Side) -> bool {
        if self.out(by) || self.out(by.other()) {
            return false;
        }
        self.hits[by.i()] += 1;
        if self.hits[by.i()] < GUN_HITS {
            return false;
        }
        self.kill(now, by);
        true
    }

    fn kill(&mut self, now: f64, by: Side) {
        self.dead = Some(by.other());
        self.kills[by.i()] += 1;
        self.calls.push((now + KILL_S, Call { from: by, id: "kill" }));
        self.calls.push((now + KILL_S + KIO_S, Call { from: Side::Aggressor, id: "kio" }));
    }

    /// `by` calls "knock it off" at `now` (the player's key): the engagement ends, the next set-up follows.
    pub fn knock_it_off(&mut self, now: f64, by: Side) -> bool {
        if self.kio.is_some() {
            return false;
        }
        self.calls.retain(|(_, c)| c.id != "kio");
        self.calls.push((now, Call { from: by, id: "kio" }));
        self.kio = Some(now);
        true
    }

    /// One frame at `now`, the jets `apart` m apart, `low` either below the [`FLOOR`]: the calls due, in order, and the
    /// next set-up when its engagement starts now (the host puts both jets there).
    pub fn step(&mut self, now: f64, apart: f64, low: bool) -> (Vec<Call>, Option<SetUp>) {
        let b = self.setup().bvr();
        let fighting = self.dead.is_none() && self.kio.is_none();
        if fighting && (apart > APART.0.max(APART.1 * b as f64) || now - self.since > [LONGEST.0, LONGEST.1][b] || low)
        {
            self.knock_it_off(now, Side::Aggressor);
        }
        let mut due = Vec::new();
        self.calls.retain(|&(t, c)| {
            let now_due = t <= now;
            if now_due {
                due.push((t, c));
            }
            !now_due
        });
        due.sort_by(|a, b| a.0.total_cmp(&b.0));
        for (t, c) in &due {
            if c.id == "kio" && self.kio.is_none() {
                self.kio = Some(*t);
            }
        }
        let next = match self.kio {
            Some(t) if now - t >= NEXT_S => {
                self.engagements += 1;
                self.index = (self.index + 1) % self.setups.len();
                self.since = now;
                self.dead = None;
                self.hits = [0; 2];
                self.last_round = [f64::NEG_INFINITY; 2];
                self.kio = None;
                self.calls.clear();
                Some(self.setup())
            }
            _ => None,
        };
        (due.into_iter().map(|(_, c)| c).collect(), next)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn near(a: Vec3, b: Vec3) -> bool {
        a.distance(b) < 1e-6
    }

    #[test]
    fn set_ups_place_both_jets() {
        let at = Vec3::new(1000.0, 2000.0, 0.0);
        // Offensive, heading north: the player 3,000 ft behind the aggressor at 15,000 ft, both north.
        let (p, a) = place(SetUp::Offensive, at, 0.0);
        assert!(
            near(a.pos, Vec3::new(1000.0, 2000.0, BFM_ALT)) && near(p.pos, Vec3::new(1000.0, 2000.0 - PERCH, BFM_ALT))
        );
        assert_eq!((p.heading, a.heading, p.speed), (0.0, 0.0, BFM_SPEED));
        // Defensive, heading east: the aggressor 914 m west of the player.
        let (p, a) = place(SetUp::Defensive, at, 90.0);
        assert!(near(p.pos, Vec3::new(1000.0, 2000.0, BFM_ALT)));
        assert!((a.pos.x - (1000.0 - PERCH)).abs() < 1e-6 && (a.pos.y - 2000.0).abs() < 1e-6);
        // High aspect: head-on 6 km apart, 900 m apart sideways, each flying at the other.
        let (p, a) = place(SetUp::HighAspect, at, 0.0);
        assert!((a.pos.y - p.pos.y - PASS_RANGE).abs() < 1e-6 && (p.pos.x - a.pos.x - 2.0 * PASS_SIDE).abs() < 1e-6);
        assert_eq!((p.heading, a.heading), (0.0, 180.0));
        // BVR: 40 NM head-on at 20,000 ft.
        let (p, a) = place(SetUp::Bvr, at, 270.0);
        assert!((p.pos.distance(a.pos) - BVR_RANGE).abs() < 1e-6 && p.pos.z == BVR_ALT && a.heading == 90.0);
        assert_eq!(SetUp::from_name("high_aspect"), Some(SetUp::HighAspect));
    }

    #[test]
    fn missile_kills_inside_its_blast_only() {
        let t = Vec3::new(0.0, 0.0, 5000.0);
        assert!(missile_kill(Vec3::new(10.0, 0.0, 5000.0), t, 15.0, false));
        assert!(!missile_kill(Vec3::new(20.0, 0.0, 5000.0), t, 15.0, false));
        assert!(!missile_kill(t, t, 15.0, true), "a dud");
    }

    #[test]
    fn a_kill_calls_kill_then_knock_it_off_then_the_next_set_up() {
        let mut r = Round::new(vec![], 0.0);
        assert_eq!(r.setup(), SetUp::Offensive);
        assert!(r.fox(1.0, Side::Player, "fox_2"));
        let (calls, next) = r.step(1.0, 1000.0, false);
        assert_eq!(calls, vec![Call { from: Side::Player, id: "fox_2" }]);
        assert!(next.is_none());
        // The missile bursts on the aggressor at 5 s: out of the fight; "kill" at 6 s, "knock it off" at 9 s.
        assert!(r.missile_hit(5.0, Side::Player));
        assert!(r.out(Side::Aggressor) && !r.out(Side::Player));
        assert!(!r.fox(5.5, Side::Aggressor, "fox_2"), "a killed jet's shot is no shot");
        assert!(!r.missile_hit(5.5, Side::Aggressor));
        assert!(r.step(5.9, 1000.0, false).0.is_empty());
        assert_eq!(r.step(6.0, 1000.0, false).0, vec![Call { from: Side::Player, id: "kill" }]);
        assert_eq!(r.step(9.0, 1000.0, false).0, vec![Call { from: Side::Aggressor, id: "kio" }]);
        assert!(r.knocked_off() && r.out(Side::Player));
        assert_eq!(r.step(14.9, 1000.0, false).1, None);
        assert_eq!(r.step(15.0, 1000.0, false).1, Some(SetUp::Defensive));
        assert_eq!((r.engagements, r.kills), (1, [1, 0]));
        assert!(!r.out(Side::Aggressor) && !r.knocked_off());
    }

    #[test]
    fn guns_once_a_burst_and_three_hits_kill() {
        let mut r = Round::new(vec![SetUp::Defensive], 0.0);
        r.round_fired(1.0, Side::Aggressor);
        r.round_fired(1.2, Side::Aggressor);
        r.round_fired(4.0, Side::Aggressor);
        let ids: Vec<_> = r.step(4.0, 500.0, false).0.into_iter().map(|c| c.id).collect();
        assert_eq!(ids, ["guns", "guns"]);
        assert!(!r.gun_hit(4.1, Side::Aggressor) && !r.gun_hit(4.2, Side::Aggressor));
        assert!(r.gun_hit(4.3, Side::Aggressor), "the third hit");
        assert!(r.out(Side::Player));
        assert_eq!(r.step(5.3, 500.0, false).0, vec![Call { from: Side::Aggressor, id: "kill" }]);
        // One set-up: the next engagement is the same one.
        r.step(8.3, 500.0, false);
        assert_eq!(r.step(14.3, 500.0, false).1, Some(SetUp::Defensive));
    }

    #[test]
    fn knock_it_off_without_a_kill() {
        // The player's call.
        let mut r = Round::new(vec![], 0.0);
        assert!(r.knock_it_off(10.0, Side::Player));
        assert!(!r.knock_it_off(11.0, Side::Aggressor), "once");
        assert_eq!(r.step(10.0, 1000.0, false).0, vec![Call { from: Side::Player, id: "kio" }]);
        assert_eq!(r.step(16.0, 1000.0, false).1, Some(SetUp::Defensive));
        // Too far apart, too long, below the floor: the aggressor calls it.
        let ko = |apart: f64, t: f64, low: bool, s: SetUp| {
            let mut r = Round::new(vec![s], 0.0);
            r.step(t, apart, low).0 == vec![Call { from: Side::Aggressor, id: "kio" }]
        };
        assert!(ko(25_000.0, 10.0, false, SetUp::Offensive));
        assert!(!ko(25_000.0, 10.0, false, SetUp::Bvr), "a BVR start is 74 km apart");
        assert!(ko(160_000.0, 10.0, false, SetUp::Bvr));
        assert!(ko(1000.0, 181.0, false, SetUp::HighAspect));
        assert!(!ko(1000.0, 181.0, false, SetUp::Bvr));
        assert!(ko(1000.0, 10.0, true, SetUp::Offensive));
        assert!(!ko(1000.0, 10.0, false, SetUp::Offensive));
    }
}
