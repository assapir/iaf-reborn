//! Our wingmen in a fight (docs/ai.md §8.9; modern-iaf/docs/ai-plan.md F5, F13, K4): the player's four-ship of Sufas
//! on the 6-DoF (#1 scripted, flying straight) against MiG-29As, the wingmen flying the enemy fighters' leaves on
//! their foe: the engage on the lead's target, the cover, their own defence, the shot, the crank, the dogfight and the
//! gun, the lock's call, winchester, splash and the rejoin. Skips with a message when `assets/converted/own` is not
//! built.

use std::path::{Path, PathBuf};

use iaf_ai::{Bandit, Bogey, Call, Flight, Skill, Tactic, Threat, apply};
use iaf_flight::autopilot::{Autopilot, Config, MODE_STEER, Steer};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;
const ALT: f64 = 6000.0;
/// The envelope the host would give (m: max, min).
const DLZ: (f64, f64) = (40_000.0, 2_000.0);
/// A missile shot in this test "flies" this long (the host's missile, s).
const FLY_S: f64 = 25.0;
/// The BFM leaf's move names (bfm.rs).
const BFM: [&str; 12] = [
    "pursuit",
    "lead",
    "lag",
    "high yo-yo",
    "low yo-yo",
    "break",
    "break down",
    "jink",
    "turn",
    "vertical",
    "rate",
    "radius",
];

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

fn start(dir: &Path, ty: &str, pos: Vec3, heading: f64, speed: f64) -> (Fm, Autopilot) {
    let (prm, env) = iaf_flight::load_with(dir, ty, DataSet::Original).unwrap();
    let h = heading.to_radians();
    let st = Start {
        position: pos,
        pitch: 0.0,
        roll: 0.0,
        heading: h as f32,
        velocity: Vec3::new(h.sin(), h.cos(), 0.0) * speed,
        airborne: true,
        engine_on: true,
    };
    let mut fm = Fm::start(ty, prm, env, st);
    if let Fm::SixDof(s) = &mut fm {
        s.set_ground_height(0.0);
    }
    (fm, Autopilot::new(Config::load(dir)))
}

fn truth(fm: &Fm) -> Bogey {
    let s = fm.state();
    let v = s.velocity;
    Bogey { pos: s.position, vel: Vec3::new(v[0] as f64, v[1] as f64, v[2] as f64) }
}

/// The four-ship, the MiGs (bandits 1, 2, … by index; enemy pairs under their trees, or scripted jets flying their
/// steer order) and the host.
struct Battle {
    ours: Vec<(Fm, Autopilot)>,
    flight: Flight,
    migs: Vec<(Fm, Autopilot)>,
    /// A MiG shot down (the host's: out of the bandits).
    down: Vec<bool>,
    /// The enemy pairs: their flight and their MiGs' indices.
    pairs: Vec<(Flight, Vec<usize>)>,
    armed: [bool; 4],
    /// Each jet's missiles left (its gun's rounds always: armed while `armed`).
    missiles: [u32; 4],
    /// Each of our jets' missile in the air until then (s); its first shot (time, range, the bandit), its gun bursts.
    flying: [f64; 4],
    shot: [Option<(f64, f64, u32)>; 4],
    guns: [u32; 4],
    /// The threat on each of our jets, the lead's (#1) included.
    threat: [Option<Threat>; 4],
    /// Each jet's phases in order.
    phases: [Vec<&'static str>; 4],
    calls: Vec<(f64, Call)>,
    t: f64,
    /// The least distance between two of our jets, m.
    sep: f64,
}

impl Battle {
    /// Four Sufas at `ALT` heading north at 230 m/s in fingertip, #1 at the origin flying straight; `migs` MiG-29As
    /// at (position, heading), flying straight; then `pair` makes MiGs enemy pairs.
    fn new(dir: &Path, migs: &[(Vec3, f64)]) -> Battle {
        let mut flight = Flight::default();
        let mut ours = Vec::new();
        for n in 0..4 {
            let s = if n == 0 { [0.0; 3] } else { iaf_ai::SHAPES[0].1[n - 1] };
            let (mut fm, mut ap) = start(dir, "F-16I", Vec3::new(s[1] as f64, s[0] as f64, ALT), 0.0, 230.0);
            flight.add(n as u8 + 1, n > 0, &fm, &mut ap);
            if n == 0 {
                straight(&mut fm, &mut ap);
            }
            ours.push((fm, ap));
        }
        let mut jets = Vec::new();
        for (p, h) in migs {
            let (mut fm, mut ap) = start(dir, "MiG-29A", *p, *h, 250.0);
            straight(&mut fm, &mut ap);
            jets.push((fm, ap));
        }
        Battle {
            ours,
            flight,
            down: vec![false; jets.len()],
            migs: jets,
            pairs: Vec::new(),
            armed: [true; 4],
            missiles: [2; 4],
            flying: [f64::MIN; 4],
            shot: [None; 4],
            guns: [0; 4],
            threat: [None; 4],
            phases: Default::default(),
            calls: Vec::new(),
            t: 0.0,
            sep: f64::MAX,
        }
    }

    /// MiGs `idx` fly as an enemy pair (Medium) on station where the first is.
    fn pair(&mut self, idx: &[usize]) {
        let mut f = Flight::default();
        for (k, &i) in idx.iter().enumerate() {
            let (fm, ap) = &mut self.migs[i];
            f.add(k as u8 + 1, true, fm, ap);
        }
        f.enemy(Skill::MEDIUM, self.migs[idx[0]].0.state().position);
        self.pairs.push((f, idx.to_vec()));
    }

    fn frame(&mut self) {
        for (i, (fm, ap)) in self.ours.iter().enumerate() {
            self.flight.sense(i as u8 + 1, true, fm, ap);
        }
        let live = |i: usize, w: &Battle| !w.down[i] && w.migs[i].0.state().crashed.is_none();
        let bandits = (0..self.migs.len())
            .filter(|&i| live(i, self))
            .map(|i| Bandit::new(i as u32 + 1, truth(&self.migs[i].0), 0.0));
        self.flight.bandits(bandits.collect());
        for n in 0..4 {
            self.flight.threat(n as u8 + 1, self.threat[n]);
            if n > 0 {
                // (No missile left: no envelope, the gun only; ai_flights.gd _pick_aa.)
                let dlz = if self.missiles[n] > 0 { DLZ } else { (0.0, 0.0) };
                self.flight.weapons(n as u8 + 1, dlz, self.armed[n], self.t < self.flying[n]);
            }
        }
        for c in self.flight.step(self.t) {
            self.calls.push((self.t, c));
        }
        for n in 1..4 {
            let m = &self.flight.members[n];
            if m.order.shoot && self.t >= self.flying[n] && self.missiles[n] > 0 {
                self.missiles[n] -= 1;
                let id = m.bandit.unwrap_or(0);
                let r = self.migs.get(id as usize - 1).map_or(0.0, |j| j.0.state().position.distance(m.v.pos));
                self.shot[n].get_or_insert((self.t, r, id));
                self.flying[n] = self.t + FLY_S;
            }
            if m.order.gun {
                self.guns[n] += 1;
            }
            let ph = if m.enemy.committed { m.enemy.phase } else { "slot" };
            if self.phases[n].last() != Some(&ph) {
                self.phases[n].push(ph);
            }
            let (fm, ap) = &mut self.ours[n];
            apply(&m.order, ap, fm);
        }
        // The enemy pairs: our four jets their bandits (no ground's vector: the lead on the nearest).
        let ours: Vec<Bandit> = (0..4).map(|n| Bandit::new(n as u32 + 1, truth(&self.ours[n].0), 0.0)).collect();
        for (f, idx) in &mut self.pairs {
            for (k, &i) in idx.iter().enumerate() {
                let (fm, ap) = &self.migs[i];
                f.sense(k as u8 + 1, !self.down[i], fm, ap);
                f.weapons(k as u8 + 1, DLZ, true, false);
            }
            f.bandits(ours.clone());
            f.step(self.t);
            for (k, &i) in idx.iter().enumerate() {
                let (fm, ap) = &mut self.migs[i];
                apply(&f.members[k].order, ap, fm);
            }
        }
        for (fm, ap) in self.ours.iter_mut().chain(self.migs.iter_mut()) {
            ap.step(fm, &|_, _| 0.0);
            fm.step(DT);
        }
        for i in 0..4 {
            let s = self.ours[i].0.state();
            assert!(
                s.crashed.is_none() && s.position.z > 300.0,
                "#{} crashed at {:.1} s: {:?}; phases {:?}",
                i + 1,
                self.t,
                s.crashed,
                self.phases[i]
            );
            for j in i + 1..4 {
                self.sep = self.sep.min(s.position.distance(self.ours[j].0.state().position));
            }
        }
        self.t += DT;
    }

    fn until(&mut self, limit: f64, done: &dyn Fn(&Battle) -> bool) -> Option<f64> {
        let t0 = self.t;
        while self.t - t0 < limit {
            self.frame();
            if done(self) {
                return Some(self.t - t0);
            }
        }
        None
    }

    fn run(&mut self, secs: f64) {
        self.until(secs, &|_| false);
    }

    fn said(&self, from: u8, id: &str) -> Option<f64> {
        self.calls.iter().rev().find(|(_, c)| c.from == from && c.id == id).map(|(t, _)| *t)
    }

    fn m(&self, n: u8) -> &iaf_ai::Member {
        self.flight.member(n).unwrap()
    }

    /// The bandit jet `n` fights (or, holding, has sorted), None in the shape.
    fn foe(&self, n: u8) -> Option<u32> {
        self.m(n).bandit
    }

    fn committed(&self, n: u8) -> bool {
        self.m(n).enemy.committed
    }
}

/// A scripted jet: straight and level at its speed (the steer loop at a far point ahead).
fn straight(fm: &mut Fm, ap: &mut Autopilot) {
    let s = fm.state();
    let v = s.velocity;
    let ahead = Vec3::new(v[0] as f64, v[1] as f64, 0.0).try_normalize().unwrap_or(Vec3::NORTH) * 200_000.0;
    ap.steer = Some(Steer { to: s.position + ahead, g: 2.0, speed: s.speed, thr_max: 1.0, fighter: false });
    ap.set_mode(fm, MODE_STEER);
}

#[test]
fn no_order_holds_calls_contacts_and_fights_back() {
    // Level (a), no order: a MiG-29A pair 70 km ahead flying straight at the flight: each MiG is called "contact" once
    // (by the first AI jet whose radar finds it) and the wingmen keep their slots. A MiG 1.5 km behind #3, nose on: #3
    // fights it in its own defence (a defensive move), uncommanded.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let migs = [(Vec3::new(-1500.0, 70_000.0, ALT), 180.0), (Vec3::new(1500.0, 70_000.0, ALT), 180.0)];
    let mut w = Battle::new(&dir, &migs);
    w.run(20.0);
    let contacts = w.calls.iter().filter(|(_, c)| c.id == "contact").count();
    println!("no order: {contacts} contact calls: {:?}", w.calls);
    assert_eq!(contacts, 2, "one contact a bandit");
    assert!((2..=4).all(|n| w.foe(n).is_none() && w.m(n).slot_error < 100.0), "in the shape");

    // Its own defence: a MiG 1.5 km from #3 (60 m right and 60 m back of #1), 45° off its tail (outside the blind
    // cone), nose on.
    let mut w = Battle::new(&dir, &[(Vec3::new(1160.0, -1160.0, ALT), 315.0)]);
    let took = w.until(5.0, &|w| w.foe(3) == Some(1));
    w.run(3.0);
    println!("self-defence: #3 {:?}", w.phases[2]);
    assert!(took.is_some() && w.said(3, "engaged").is_some());
    assert!(w.phases[2].iter().any(|p| ["break", "break down", "jink"].contains(p)), "{:?}", w.phases[2]);
}

#[test]
fn engage_a_mig29_pair() {
    // Level (b): "engage my target" to the flight against a MiG-29A pair 60 km ahead flying the enemy trees: #2 and #3
    // take the lead MiG (#4 stays on #3), commit on the collision course, shoot inside their share of the envelope,
    // crank while the missile flies, merge and fight it with the BFM leaf and the gun; a kill by their weapons is
    // called "splash"; the bandit gone, they rejoin and call "in position".
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let migs = [(Vec3::new(0.0, 60_000.0, ALT), 180.0), (Vec3::new(1500.0, 60_000.0, ALT), 180.0)];
    let mut w = Battle::new(&dir, &migs);
    w.pair(&[0, 1]);
    w.run(3.0);
    assert_eq!(w.flight.engage(w.t, 0, Some(1)), Some(true));
    w.run(3.0);
    assert!([2, 3, 4].iter().all(|&n| w.said(n, "ack").is_some()), "{:?}", w.calls);
    assert_eq!((w.foe(2), w.foe(3), w.foe(4)), (Some(1), Some(1), None), "#4 on #3");
    assert_eq!(w.flight.leader(4), 3);
    assert_eq!(w.m(2).enemy.phase, "intercept");
    // The shot inside the wingmen's (Medium) share of the envelope: 2 + 0.9 · 38 = 36.2 km, deeper by the reaction.
    let shot = w.until(60.0, &|w| w.shot[1].is_some() && w.shot[2].is_some());
    println!("engage: shots {:?} after {shot:?} s", w.shot);
    assert!(shot.is_some());
    for n in [1, 2] {
        let (_, r, id) = w.shot[n].unwrap();
        assert!((DLZ.1..=36_200.0).contains(&r) && id == 1, "#{} shot at {r:.0} m at {id}", n + 1);
    }
    w.run(4.0);
    assert!(w.phases[1].contains(&"crank") || w.phases[2].contains(&"crank"), "crank: {:?}", w.phases);
    // The merge: a dogfight move and the gun within three minutes.
    let fought = w.until(180.0, &|w| {
        [1, 2].iter().any(|&n| w.guns[n] > 0) && [1, 2].iter().any(|&n| w.phases[n].iter().any(|p| BFM.contains(p)))
    });
    println!("engage: #2 {:?}\n        #3 {:?}; gun orders {:?}; sep {:.0} m", w.phases[1], w.phases[2], w.guns, w.sep);
    assert!(fought.is_some(), "a dogfight move and a gun burst");
    assert!(w.sep > 30.0, "our jets kept apart: {:.1} m", w.sep);
    // Shot down with #2's missile flying: "splash" from #2.
    w.flying[1] = w.t + 10.0;
    w.frame();
    let t0 = w.t;
    w.flight.splash(w.t, 1);
    w.down = vec![true; 2];
    w.pairs.clear();
    let back = w.until(400.0, &|w| [2, 3].iter().all(|&n| w.said(n, "in_position").is_some_and(|t| t > t0)));
    println!("engage: rejoined after {back:?} s");
    assert!(w.said(2, "splash").is_some_and(|t| t >= t0));
    assert!(back.is_some() && w.foe(2).is_none() && w.m(2).tactic == Tactic::None);
}

#[test]
fn engage_named_bandits() {
    // Level (b): the lead names a bandit for each: bandit 1 to Kidon 1-2, then bandit 2 to the element. #2 keeps its
    // bandit, #3 takes the second with #4 on its wing, and each closes on its own.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let migs = [(Vec3::new(-8_000.0, 50_000.0, ALT), 180.0), (Vec3::new(8_000.0, 50_000.0, ALT), 180.0)];
    let mut w = Battle::new(&dir, &migs);
    w.run(1.0);
    assert_eq!(w.flight.engage(w.t, 2, Some(1)), Some(true));
    assert_eq!(w.flight.engage(w.t, 5, Some(2)), Some(true));
    assert_eq!(w.flight.engage(w.t, 3, Some(9)), Some(false), "no bandit 9: unable");
    w.run(2.0);
    assert_eq!((w.foe(2), w.foe(3), w.foe(4)), (Some(1), Some(2), None));
    let d = |w: &Battle, n: usize, i: usize| w.ours[n].0.state().position.distance(w.migs[i].0.state().position);
    let (a, b) = (d(&w, 1, 0), d(&w, 2, 1));
    w.run(15.0);
    println!("named: #2 {a:.0} → {:.0} m from bandit 1, #3 {b:.0} → {:.0} m from bandit 2", d(&w, 1, 0), d(&w, 2, 1));
    assert!(w.committed(2) && w.committed(3) && w.flight.leader(4) == 3);
    // Each turned onto its own: the closure on its bandit beats the one on the other.
    assert!(d(&w, 1, 0) < d(&w, 1, 1) && d(&w, 2, 1) < d(&w, 2, 0));
    // A rejoin inside the dogfight's reach ends the fight (it is no fight of its own).
    let close = w.until(120.0, &|w| d(w, 1, 0) < 8_000.0);
    assert!(close.is_some() && w.foe(2) == Some(1));
    assert!(w.flight.command(w.t, 2, "rejoin"));
    w.run(1.0);
    assert!(w.foe(2).is_none() && !w.committed(2), "the rejoin ends the fight: {:?}", w.foe(2));
}

#[test]
fn sort_by_azimuth_and_by_range() {
    // Level (c): two MiG pairs 60 km ahead, 20 km apart side by side (AZIMUTH): element 2 (#3 east of #1 in
    // fingertip) takes the east pair, #3 and #4 one MiG each; #2 one of the west pair. #3 commits and calls "targeted";
    // #2 and #4 answer "ack" and hold in their slots, their radars on their share, until their element lead shoots.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let migs = [
        (Vec3::new(-10_000.0, 60_000.0, ALT), 180.0),
        (Vec3::new(-11_500.0, 60_000.0, ALT), 180.0),
        (Vec3::new(10_000.0, 60_000.0, ALT), 180.0),
        (Vec3::new(11_500.0, 60_000.0, ALT), 180.0),
    ];
    let mut w = Battle::new(&dir, &migs);
    w.run(1.0);
    assert!(w.flight.sort(w.t));
    w.run(2.0);
    println!("sort: foes {:?} {:?} {:?}; calls {:?}", w.foe(2), w.foe(3), w.foe(4), w.calls);
    assert!(w.said(3, "targeted").is_some() && w.said(2, "ack").is_some() && w.said(4, "ack").is_some());
    let (f2, f3, f4) = (w.foe(2).unwrap(), w.foe(3).unwrap(), w.foe(4).unwrap());
    assert!([1, 2].contains(&f2) && [3, 4].contains(&f3) && [3, 4].contains(&f4) && f3 != f4, "{f2} {f3} {f4}");
    assert!(w.committed(3) && !w.committed(2) && !w.committed(4) && w.m(2).holding && w.m(4).holding);
    // #3's shot clears #4; the lead's shot (the host's word) clears #2.
    let shot = w.until(90.0, &|w| w.shot[2].is_some());
    w.run(1.0);
    println!("sort: #3 shot after {shot:?} s: {:?}", w.shot[2]);
    assert!(shot.is_some() && w.shot[2].unwrap().2 == f3);
    assert!(w.committed(4) && !w.m(4).holding && w.foe(4) == Some(f4), "#4 cleared by #3's shot");
    assert!(!w.committed(2) && w.m(2).holding);
    w.flight.fired(1);
    w.run(1.0);
    assert!(w.committed(2) && w.foe(2) == Some(f2), "#2 cleared by the lead's shot");

    // Two pairs on one line of sight, 45 and 70 km ahead (RANGE): the lead's element the near pair, element 2 the far.
    let migs = [
        (Vec3::new(0.0, 45_000.0, ALT), 180.0),
        (Vec3::new(1_500.0, 45_000.0, ALT), 180.0),
        (Vec3::new(0.0, 70_000.0, ALT), 180.0),
        (Vec3::new(1_500.0, 70_000.0, ALT), 180.0),
    ];
    let mut w = Battle::new(&dir, &migs);
    w.run(1.0);
    assert!(w.flight.sort(w.t));
    w.run(1.0);
    println!("range sort: foes {:?} {:?} {:?}", w.foe(2), w.foe(3), w.foe(4));
    assert!([1, 2].contains(&w.foe(2).unwrap()) && [3, 4].contains(&w.foe(3).unwrap()));
    // Nothing in the picture: "unable".
    let mut w = Battle::new(&dir, &[]);
    w.run(1.0);
    assert!(w.flight.sort(w.t));
    w.run(2.0);
    assert!((2..=4).all(|n| w.said(n, "unable").is_some() && w.m(n).tactic == Tactic::None));
}

#[test]
fn free_hunts_in_its_area_until_joker() {
    // Level (d): weapons free to the element round a point 35 km ahead: #3 hunts the MiG inside the area (#4 with it,
    // on the same), never the one outside; that one shot down, #3 circles the point with #4 on its wing; at joker fuel
    // the hunt ends and they rejoin.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let area = Vec3::new(0.0, 35_000.0, ALT);
    let migs = [(Vec3::new(5_000.0, 40_000.0, ALT), 180.0), (Vec3::new(-40_000.0, 50_000.0, ALT), 180.0)];
    let mut w = Battle::new(&dir, &migs);
    w.run(1.0);
    assert_eq!(w.flight.free(w.t, 5, area), Some(true));
    assert_eq!(w.flight.free(w.t, 2, Vec3::new(0.0, 90_000.0, ALT)), Some(false), "too far: unable");
    w.run(2.0);
    assert!(w.said(3, "ack").is_some() && w.said(4, "ack").is_some() && w.said(2, "unable").is_some());
    assert_eq!((w.foe(3), w.foe(4)), (Some(1), Some(1)));
    assert!(w.committed(3) && w.said(3, "engaged").is_some());
    let never = w.until(30.0, &|w| (2..=4).any(|n| w.foe(n) == Some(2)));
    assert!(never.is_none(), "the MiG outside the area is not hunted");
    w.down[0] = true;
    w.run(20.0);
    let p3 = w.ours[2].0.state().position;
    println!("free: #3 {:.0} m from the point, task {}", (p3 - area).length(), w.m(3).task.is_some());
    assert!(w.foe(3).is_none() && w.m(3).task.is_some() && w.m(3).tactic == Tactic::Free);
    assert_eq!(w.flight.leader(4), 3);
    let bingo = w.m(3).bingo_kg;
    w.ours[2].0.set_fuel(bingo + 900.0);
    w.run(2.0);
    assert!(w.m(3).tactic == Tactic::None && w.said(3, "joker").is_some(), "joker ends the hunt");
}

#[test]
fn cover_defends_the_lead() {
    // "Cover me" (defend the lead): a MiG-29A flying straight at the flight is not taken, near as it comes; once its
    // radar locks the lead (the lead's RWR), the covering wingman fights it ("engaged"); a rejoin ends the cover.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut w = Battle::new(&dir, &[(Vec3::new(0.0, 40_000.0, ALT), 180.0)]);
    w.run(1.0);
    assert!(w.flight.command(w.t, 2, "cover"));
    w.run(20.0);
    assert!(w.said(2, "ack").is_some() && w.m(2).tactic == Tactic::Cover && w.foe(2).is_none());
    let at = w.migs[0].0.state().position;
    w.threat[0] = Some(Threat { pos: at, vel: Vec3::ZERO, launch: false, ir: false, ground: false });
    let took = w.until(3.0, &|w| w.foe(2) == Some(1));
    w.threat[0] = None;
    w.run(2.0);
    assert!(took.is_some() && w.said(2, "engaged").is_some() && w.committed(2), "the lead's attacker taken");
    assert!(w.foe(3).is_none() && w.foe(4).is_none(), "the others keep their slots");
    assert_eq!(w.foe(2), Some(1), "kept near the lead");
    assert!(w.flight.command(w.t, 2, "rejoin"));
    w.run(1.0);
    assert!(w.foe(2).is_none() && w.m(2).tactic == Tactic::None);
}

#[test]
fn an_enemy_pair_sorts() {
    // An AI-led flight sorts by the same rule: a MiG-29A pair committed on the four-ship takes two of its jets, not
    // one.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let migs = [(Vec3::new(-750.0, 50_000.0, ALT), 180.0), (Vec3::new(750.0, 50_000.0, ALT), 180.0)];
    let mut w = Battle::new(&dir, &migs);
    w.pair(&[0, 1]);
    let committed = w.until(30.0, &|w| w.pairs[0].0.members[0].enemy.committed);
    w.run(1.0);
    let f = &w.pairs[0].0;
    let (a, b) = (f.members[0].bandit, f.members[1].bandit);
    println!("enemy pair: committed after {committed:?} s on {a:?} and {b:?}");
    assert!(committed.is_some() && a.is_some() && b.is_some() && a != b);
}

#[test]
fn lock_called_winchester_and_rejoin() {
    // Engaging, a lock on #2 from the MiG is called ("spike") and the attack goes on; with nothing left to shoot (and
    // no missile flying) #2 calls "winchester" and rejoins; it then answers a new engage "unable".
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut w = Battle::new(&dir, &[(Vec3::new(0.0, 70_000.0, ALT), 180.0)]);
    w.run(2.0);
    assert_eq!(w.flight.engage(w.t, 2, Some(1)), Some(true));
    w.run(3.0);
    let at = w.migs[0].0.state().position;
    w.threat[1] = Some(Threat { pos: at, vel: Vec3::ZERO, launch: false, ir: false, ground: false });
    w.run(3.0);
    let m = w.m(2);
    assert!(w.said(2, "spike").is_some() && !m.defending && m.enemy.phase == "intercept", "{}", m.enemy.phase);
    w.threat[1] = None;
    w.armed[1] = false;
    w.flying[1] = f64::MIN;
    let t0 = w.t;
    let back = w.until(300.0, &|w| w.said(2, "in_position").is_some_and(|t| t > t0));
    println!("winchester: back after {back:?} s");
    assert!(w.said(2, "winchester").is_some() && back.is_some() && w.foe(2).is_none());
    assert_eq!(w.flight.engage(w.t, 2, Some(1)), Some(false));
}
