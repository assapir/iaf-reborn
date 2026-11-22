//! Our wingmen in a fight (docs/ai.md §8.9; modern-iaf/docs/ai-plan.md F5, F13, K4): the player's four-ship of Sufas
//! on the 6-DoF (#1 scripted, flying straight) against MiG-29As, the wingmen flying the enemy fighters' leaves on
//! their foe: the engage on the lead's target, the cover, their own defence, the shot, the crank, the dogfight and the
//! gun, the lock's call, winchester, splash and the rejoin. Skips with a message when `assets/converted/own` is not
//! built.

use std::path::{Path, PathBuf};

use iaf_ai::{Bogey, Call, Flight, Foe, Skill, Threat, apply};
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

/// The four-ship, the MiGs (an enemy pair under its trees, or scripted jets flying their steer order) and the host.
struct Battle {
    ours: Vec<(Fm, Autopilot)>,
    flight: Flight,
    migs: Vec<(Fm, Autopilot)>,
    enemy: Option<Flight>,
    /// The lead's target: a MiG's index (the host's radar lock).
    target: Option<usize>,
    armed: [bool; 4],
    /// Each jet's missiles left (its gun's rounds always: armed while `armed`).
    missiles: [u32; 4],
    /// Each of our jets' missile in the air until then (s); its first shot (time, range), its gun bursts.
    flying: [f64; 4],
    shot: [Option<(f64, f64)>; 4],
    guns: [u32; 4],
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
    /// at (position, heading); `pair` true: they fly the enemy trees on station where they start (Medium).
    fn new(dir: &Path, migs: &[(Vec3, f64)], pair: bool) -> Battle {
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
        let mut enemy = pair.then(Flight::default);
        let mut jets = Vec::new();
        for (i, (p, h)) in migs.iter().enumerate() {
            let (mut fm, mut ap) = start(dir, "MiG-29A", *p, *h, 250.0);
            match &mut enemy {
                Some(f) => f.add(i as u8 + 1, true, &fm, &mut ap),
                None => straight(&mut fm, &mut ap),
            }
            jets.push((fm, ap));
        }
        if let Some(f) = &mut enemy {
            f.enemy(Skill::MEDIUM, migs[0].0);
        }
        Battle {
            ours,
            flight,
            migs: jets,
            enemy,
            target: None,
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

    /// The hostile jet nearest the flight (the host's `bogey`), its index.
    fn nearest(&self) -> Option<usize> {
        let d = |i: usize| {
            let p = self.migs[i].0.state().position;
            self.ours.iter().map(|o| o.0.state().position.distance(p)).fold(f64::MAX, f64::min)
        };
        (0..self.migs.len())
            .filter(|&i| self.migs[i].0.state().crashed.is_none())
            .min_by(|&a, &b| d(a).total_cmp(&d(b)))
    }

    fn frame(&mut self) {
        for (i, (fm, ap)) in self.ours.iter().enumerate() {
            self.flight.sense(i as u8 + 1, true, fm, ap);
        }
        let near = self.nearest();
        self.flight.bogey(None, near.map(|i| truth(&self.migs[i].0)));
        if let Some(k) = self.target {
            self.flight.target(Some(truth(&self.migs[k].0)), 0.0);
        }
        for n in 1..4 {
            // (No missile left: no envelope, the gun only; ai_flights.gd _pick_aa.)
            let dlz = if self.missiles[n] > 0 { DLZ } else { (0.0, 0.0) };
            self.flight.weapons(n as u8 + 1, dlz, self.armed[n], self.t < self.flying[n]);
            self.flight.threat(n as u8 + 1, self.threat[n]);
        }
        for c in self.flight.step(self.t) {
            self.calls.push((self.t, c));
        }
        for n in 1..4 {
            let m = &self.flight.members[n];
            if m.order.shoot && self.t >= self.flying[n] && self.missiles[n] > 0 {
                self.missiles[n] -= 1;
                let foe = match m.foe {
                    Some(Foe::Target) => self.target,
                    _ => near,
                };
                let r = foe.map_or(0.0, |k| self.migs[k].0.state().position.distance(m.v.pos));
                self.shot[n].get_or_insert((self.t, r));
                self.flying[n] = self.t + FLY_S;
            }
            if m.order.gun {
                self.guns[n] += 1;
            }
            let ph = if m.foe.is_some() { m.enemy.phase } else { "slot" };
            if self.phases[n].last() != Some(&ph) {
                self.phases[n].push(ph);
            }
            let (fm, ap) = &mut self.ours[n];
            apply(&m.order, ap, fm);
        }
        // The MiGs: an enemy pair against the Sufa nearest them.
        if let Some(f) = &mut self.enemy {
            for (i, (fm, ap)) in self.migs.iter().enumerate() {
                f.sense(i as u8 + 1, true, fm, ap);
            }
            let p = self.migs[0].0.state().position;
            let b =
                self.ours.iter().map(|o| truth(&o.0)).min_by(|a, b| a.pos.distance(p).total_cmp(&b.pos.distance(p)));
            f.bogey(None, b);
            for i in 0..self.migs.len() {
                f.weapons(i as u8 + 1, DLZ, true, false);
            }
            f.step(self.t);
            for (i, (fm, ap)) in self.migs.iter_mut().enumerate() {
                apply(&f.members[i].order, ap, fm);
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
                "#{} crashed at {:.1} s: {:?}",
                i + 1,
                self.t,
                s.crashed
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

    fn foe(&self, n: u8) -> Option<Foe> {
        self.flight.member(n).unwrap().foe
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
fn engage_a_mig29_pair() {
    // "Engage my target" to the flight against a MiG-29A pair 60 km ahead flying the enemy trees: #2 and #3 take the
    // lead MiG (#4 stays on #3), commit on the collision course, shoot inside their share of the envelope, crank while
    // the missile flies, merge and fight it with the BFM leaf and the gun; a kill by their weapons is called "splash";
    // the target gone, they rejoin and call "in position".
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let migs = [(Vec3::new(0.0, 60_000.0, ALT), 180.0), (Vec3::new(1500.0, 60_000.0, ALT), 180.0)];
    let mut w = Battle::new(&dir, &migs, true);
    w.run(3.0);
    w.target = Some(0);
    let at = truth(&w.migs[0].0);
    assert_eq!(w.flight.engage(w.t, 0, Some(at)), Some(true));
    w.run(3.0);
    assert!([2, 3, 4].iter().all(|&n| w.said(n, "ack").is_some()), "{:?}", w.calls);
    assert_eq!((w.foe(2), w.foe(3), w.foe(4)), (Some(Foe::Target), Some(Foe::Target), None), "#4 on #3");
    assert_eq!(w.flight.leader(4), 3);
    assert_eq!(w.flight.member(2).unwrap().enemy.phase, "intercept");
    // The shot inside the wingmen's (Medium) share of the envelope: 2 + 0.9 · 38 = 36.2 km, deeper by the reaction.
    let shot = w.until(60.0, &|w| w.shot[1].is_some() && w.shot[2].is_some());
    println!("engage: shots {:?} after {shot:?} s", w.shot);
    assert!(shot.is_some());
    for n in [1, 2] {
        let (_, r) = w.shot[n].unwrap();
        assert!((DLZ.1..=36_200.0).contains(&r), "#{} shot at {r:.0} m", n + 1);
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
    w.flight.splash(w.t, Foe::Target);
    w.target = None;
    w.flight.target(None, 0.0);
    w.migs.clear();
    w.enemy = None;
    let back = w.until(400.0, &|w| [2, 3].iter().all(|&n| w.said(n, "in_position").is_some_and(|t| t > t0)));
    println!("engage: rejoined after {back:?} s");
    assert!(w.said(2, "splash").is_some_and(|t| t >= t0));
    assert!(back.is_some() && w.foe(2).is_none() && !w.flight.member(2).unwrap().engaging);
}

#[test]
fn cover_and_self_defence() {
    // A MiG-29A flying straight at the flight from 80 km: a wingman told "cover" engages it once it is within 37 km
    // of the lead ("engaged"), the others keep their slots. A MiG 1.5 km behind #3, nose on: #3 fights it in its own
    // defence (a defensive move), uncommanded.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut w = Battle::new(&dir, &[(Vec3::new(0.0, 80_000.0, ALT), 180.0)], false);
    w.run(2.0);
    assert!(w.flight.command(w.t, 2, "cover"));
    w.run(2.0);
    assert!(w.said(2, "ack").is_some() && w.flight.member(2).unwrap().covering);
    w.run(20.0);
    assert!(w.foe(2).is_none(), "the bogey still far");
    let took = w.until(120.0, &|w| w.foe(2) == Some(Foe::Bogey));
    let p = w.migs[0].0.state().position;
    let d = (p.x.powi(2) + (p.y - w.ours[0].0.state().position.y).powi(2)).sqrt();
    println!("cover: took the bogey after {took:?} s at {d:.0} m from the lead");
    assert!(took.is_some() && d <= iaf_ai::flight::COVER_M + 600.0);
    w.run(2.0);
    assert!(w.said(2, "engaged").is_some());
    assert!(w.foe(3).is_none() && w.foe(4).is_none(), "the others keep their slots");
    // Rejoin ends the cover.
    assert!(w.flight.command(w.t, 2, "rejoin"));
    w.run(1.0);
    assert!(w.foe(2).is_none() && !w.flight.member(2).unwrap().covering);

    // Its own defence: a MiG 1.5 km from #3 (60 m right and 60 m back of #1), 45° off its tail (outside the blind
    // cone), nose on.
    let mut w = Battle::new(&dir, &[(Vec3::new(1160.0, -1160.0, ALT), 315.0)], false);
    let took = w.until(5.0, &|w| w.foe(3) == Some(Foe::Bogey));
    w.run(3.0);
    println!("self-defence: #3 {:?}", w.phases[2]);
    assert!(took.is_some() && w.said(3, "engaged").is_some());
    assert!(w.phases[2].iter().any(|p| ["break", "break down", "jink"].contains(p)), "{:?}", w.phases[2]);
}

#[test]
fn lock_called_winchester_and_rejoin() {
    // Engaging, a lock on #2 from the MiG is called ("spike") and the attack goes on; with nothing left to shoot (and
    // no missile flying) #2 calls "winchester" and rejoins; it then answers a new engage "unable".
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut w = Battle::new(&dir, &[(Vec3::new(0.0, 70_000.0, ALT), 180.0)], false);
    w.run(2.0);
    w.target = Some(0);
    assert_eq!(w.flight.engage(w.t, 2, Some(truth(&w.migs[0].0))), Some(true));
    w.run(3.0);
    let at = w.migs[0].0.state().position;
    w.threat[1] = Some(Threat { pos: at, vel: Vec3::ZERO, launch: false, ir: false, ground: false });
    w.run(3.0);
    let m = w.flight.member(2).unwrap();
    assert!(w.said(2, "spike").is_some() && !m.defending && m.enemy.phase == "intercept", "{}", m.enemy.phase);
    w.threat[1] = None;
    w.armed[1] = false;
    w.flying[1] = f64::MIN;
    let t0 = w.t;
    let back = w.until(300.0, &|w| w.said(2, "in_position").is_some_and(|t| t > t0));
    println!("winchester: back after {back:?} s");
    assert!(w.said(2, "winchester").is_some() && back.is_some() && w.foe(2).is_none());
    assert_eq!(w.flight.engage(w.t, 2, Some(truth(&w.migs[0].0))), Some(false));
}
