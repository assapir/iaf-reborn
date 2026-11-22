//! The AI jets' air-to-ground attack (docs/ai.md §8.10; modern-iaf/docs/ai-plan.md F15, K15) on the 6-DoF: the player's
//! four-ship of Sufas (#1 scripted, flying straight) on the lead's "attack my target", and a MiG-29A pair on its AI
//! lead's own order. Each jet's run by its weapon (a 30° dive for bombs, a level run for a guided bomb), the release (the host's AI ripple: here the steered fall of `iaf_avionics::bombs::Bomb`, as combat.gd's AI
//! stores fall, aimed at the target), the egress, the calls (in, alpha, done) and the rejoin. Skips with a message
//! when `assets/converted/own` is not built.

use std::path::{Path, PathBuf};

use iaf_ai::strike::{DIVE_IN_AGL, STAGGER_S};
use iaf_ai::{Bogey, Call, Flight, Skill, apply};
use iaf_avionics::bombs::Bomb;
use iaf_flight::autopilot::{Autopilot, Config, MODE_BFM, MODE_STEER, Steer};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;
/// combat.gd's AI stores: the steered fall's along-track clamp (m/s², player_weapons.gd BOMB_CLAMP_PARAM).
const CLAMP: f64 = 15.0;
/// The MK-82's blast radius (its record's blast_m, m).
const BLAST_M: f64 = 50.0;

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

fn start(dir: &Path, ty: &str, pos: Vec3, speed: f64) -> (Fm, Autopilot) {
    let (prm, env) = iaf_flight::load_with(dir, ty, DataSet::Original).unwrap();
    let st = Start {
        position: pos,
        pitch: 0.0,
        roll: 0.0,
        heading: 0.0,
        velocity: Vec3::NORTH * speed,
        airborne: true,
        engine_on: true,
    };
    let mut fm = Fm::start(ty, prm, env, st);
    if let Fm::SixDof(s) = &mut fm {
        s.set_ground_height(0.0);
    }
    (fm, Autopilot::new(Config::load(dir)))
}

/// Where the store released at `p` with velocity `v`, aimed at `aim`, meets the ground (z 0).
fn impact(p: Vec3, v: Vec3, aim: Vec3) -> Vec3 {
    let b = Bomb::launch(0.0, p, v, aim, CLAMP, Vec3::ZERO);
    let mut t = 0.0;
    while b.position(t)[2] > 0.0 && t < 120.0 {
        t += 0.01;
    }
    b.position(t)
}

/// A flight of AI jets (#1 scripted when `player`) attacking a ground target at the origin's north.
struct Strike {
    jets: Vec<(Fm, Autopilot)>,
    flight: Flight,
    player: bool,
    target: Option<Vec3>,
    /// Each jet's release: (time, miss m, height m), the least height in its egress, its stages in order.
    releases: Vec<Option<(f64, f64, f64)>>,
    low: Vec<f64>,
    modes: Vec<Vec<u8>>,
    calls: Vec<(f64, Call)>,
    t: f64,
    sep: f64,
}

impl Strike {
    fn new(dir: &Path, ty: &str, n: usize, player: bool, alt: f64) -> Strike {
        let mut flight = Flight::default();
        let mut jets = Vec::new();
        for i in 0..n {
            let s = if i == 0 { [0.0; 3] } else { iaf_ai::SHAPES[0].1[i - 1] };
            let (mut fm, mut ap) = start(dir, ty, Vec3::new(s[1] as f64, s[0] as f64, alt), 230.0);
            flight.add(i as u8 + 1, !(player && i == 0), &fm, &mut ap);
            if player && i == 0 {
                let p = fm.state().position;
                // The lead orbits a point 15 km on (the steer loop's turns round its point).
                let to = p + Vec3::NORTH * 15_000.0;
                ap.steer = Some(Steer { to, g: 2.0, speed: 230.0, thr_max: 1.0, fighter: false });
                ap.set_mode(&mut fm, MODE_STEER);
            }
            jets.push((fm, ap));
        }
        Strike {
            jets,
            flight,
            player,
            target: None,
            releases: vec![None; n],
            low: vec![f64::MAX; n],
            modes: vec![Vec::new(); n],
            calls: Vec::new(),
            t: 0.0,
            sep: f64::MAX,
        }
    }

    fn frame(&mut self) {
        for (i, (fm, ap)) in self.jets.iter().enumerate() {
            self.flight.sense(i as u8 + 1, true, fm, ap);
        }
        self.flight.ground_target(self.target.map(|pos| Bogey { pos, vel: Vec3::ZERO }));
        for c in self.flight.step(self.t) {
            self.calls.push((self.t, c));
        }
        let first = usize::from(self.player);
        for i in first..self.jets.len() {
            let order = self.flight.members[i].order;
            let (fm, ap) = &mut self.jets[i];
            if order.release && self.releases[i].is_none() {
                // The host's AI ripple: the store aimed at the target, its weapons spent.
                let s = fm.state();
                let v = Vec3::new(s.velocity[0] as f64, s.velocity[1] as f64, s.velocity[2] as f64);
                let aim = self.target.unwrap_or(Vec3::ZERO);
                let hit = impact(s.position, v, aim);
                self.releases[i] = Some((self.t, (hit - aim).length(), s.position[2]));
                self.flight.released(self.t, i as u8 + 1);
                self.flight.ground_weapon(i as u8 + 1, None);
            }
            apply(&order, ap, fm);
        }
        for i in 0..self.jets.len() {
            let (fm, ap) = &mut self.jets[i];
            ap.step(fm, &|_, _| 0.0);
            fm.step(DT);
            let s = fm.state();
            assert!(s.crashed.is_none(), "#{} crashed at {:.1} s: {:?}", i + 1, self.t, s.crashed);
            self.low[i] = self.low[i].min(s.position[2]);
            if self.modes[i].last() != Some(&ap.mode()) {
                self.modes[i].push(ap.mode());
            }
        }
        for i in 0..self.jets.len() {
            for j in i + 1..self.jets.len() {
                let d = self.jets[i].0.state().position.distance(self.jets[j].0.state().position);
                self.sep = self.sep.min(d);
            }
        }
        self.t += DT;
    }

    fn until(&mut self, limit: f64, done: &dyn Fn(&Strike) -> bool) -> Option<f64> {
        let t0 = self.t;
        while self.t - t0 < limit {
            self.frame();
            if done(self) {
                return Some(self.t - t0);
            }
        }
        None
    }

    fn said(&self, from: u8, id: &str) -> Option<f64> {
        self.calls.iter().find(|(_, c)| c.from == from && c.id == id).map(|(t, _)| *t)
    }
}

#[test]
fn four_ship_attacks_my_target() {
    // "Attack my target" to the flight on a ground target 30 km ahead: #2 and #3 with bombs dive, #4 with a guided bomb
    // runs level, one after the other 20 s apart, each calling "in", "alpha" at its release and
    // "done" once 8 km clear; the steered store lands within the blast radius; all rejoin ("in position").
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut w = Strike::new(&dir, "F-16I", 4, true, 4000.0);
    for (n, guided) in [(2, Some(false)), (3, Some(false)), (4, Some(true))] {
        w.flight.ground_weapon(n, guided);
    }
    w.until(2.0, &|_| false);
    let at = Vec3::new(0.0, 30_000.0, 0.0);
    w.target = Some(at);
    assert_eq!(w.flight.attack(w.t, 0, Some(Bogey { pos: at, vel: Vec3::ZERO })), Some(true));
    let done = w.until(900.0, &|w| [2, 3, 4].iter().all(|&n| w.said(n, "done").is_some()));
    for n in 2..=4u8 {
        let i = n as usize - 1;
        println!(
            "#{n}: in {:?} alpha {:?} done {:?} release {:?} low {:.0} m modes {:x?}",
            w.said(n, "in"),
            w.said(n, "alpha"),
            w.said(n, "done"),
            w.releases[i],
            w.low[i],
            w.modes[i]
        );
    }
    println!("calls {:?}", w.calls.iter().map(|(t, c)| format!("{t:.0} {} {}", c.from, c.id)).collect::<Vec<_>>());
    assert!(done.is_some(), "every jet done");
    assert!([2, 3, 4].iter().all(|&n| w.said(n, "ack").is_some()));
    let ins: Vec<f64> = (2..=4).map(|n| w.said(n, "in").unwrap()).collect();
    assert!(ins[1] - ins[0] >= STAGGER_S - 0.6 && ins[2] - ins[1] >= STAGGER_S - 0.6, "a trail of runs: {ins:?}");
    for n in 2..=4u8 {
        let i = n as usize - 1;
        let (tr, miss, _) = w.releases[i].expect("released");
        let alpha = w.said(n, "alpha").unwrap();
        assert!(alpha >= tr && alpha > w.said(n, "in").unwrap() && w.said(n, "done").unwrap() > alpha);
        assert!(miss < BLAST_M, "#{n}'s store {miss:.0} m off");
        assert!(w.low[i] > 300.0, "#{n} at {:.0} m", w.low[i]);
        // The dives on the BFM loop, released below the run-in's 2,500 m; the level run on the steer loop at its height.
        let (_, _, h) = w.releases[i].unwrap();
        assert!(n == 4 || w.modes[i].contains(&MODE_BFM), "#{n}: {:x?}", w.modes[i]);
        assert!(if n == 4 { h > 3900.0 } else { h < DIVE_IN_AGL }, "#{n} released at {h:.0} m");
        assert_eq!(w.flight.member(n).unwrap().strike.phase, iaf_ai::strike::Phase::None);
    }
    // While #2 ran, #3 and #4 kept their slots on the lead (the player: no Hold).
    assert!(!w.modes[2].contains(&10) && !w.modes[3].contains(&10), "{:x?} {:x?}", w.modes[2], w.modes[3]);
    let t0 = w.t;
    let back = w.until(600.0, &|w| {
        [2, 3, 4].iter().all(|&n| w.calls.iter().any(|(t, c)| c.from == n && c.id == "in_position" && *t >= t0 - 60.0))
    });
    println!("rejoined after {back:?} s; least separation {:.0} m", w.sep);
    assert!(back.is_some(), "all back in position");
    assert!(w.sep > 30.0, "our jets kept apart: {:.1} m", w.sep);
}

#[test]
fn mig29_pair_strikes_on_its_leads_order() {
    // An enemy pair on station with bombs: its lead's own order on a ground target 25 km ahead; the lead runs first, the
    // wingman holds where it is (mode 10) while the lead runs, then its own run; both release on the target and go back
    // to the station's CAP.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut w = Strike::new(&dir, "MiG-29A", 2, false, 5000.0);
    w.flight.enemy(Skill::MEDIUM, Vec3::new(0.0, 0.0, 5000.0));
    for n in [1, 2] {
        w.flight.ground_weapon(n, Some(false));
    }
    w.until(2.0, &|_| false);
    let at = Vec3::new(0.0, 25_000.0, 0.0);
    w.target = Some(at);
    assert!(w.flight.strike(w.t, Bogey { pos: at, vel: Vec3::ZERO }));
    assert!(w.until(900.0, &|w| w.said(1, "done").is_some() && w.said(2, "done").is_some()).is_some(), "{:?}", w.calls);
    for i in 0..2 {
        println!("#{}: release {:?} low {:.0} m modes {:x?}", i + 1, w.releases[i], w.low[i], w.modes[i]);
        let (_, miss, _) = w.releases[i].expect("released");
        assert!(miss < BLAST_M && w.low[i] > 300.0);
        assert!(w.modes[i].contains(&MODE_BFM));
    }
    assert!(w.said(2, "in").unwrap() - w.said(1, "in").unwrap() >= STAGGER_S - 0.6);
    assert!(w.modes[1].contains(&10), "the wingman held while the lead ran: {:x?}", w.modes[1]);
    w.until(5.0, &|_| false);
    assert_eq!(w.flight.member(1).unwrap().enemy.phase, "cap", "back on station");
}

#[test]
fn unable_target_gone_and_rejoin() {
    // #2 with no air-to-ground weapon answers "unable"; #3 and #4 take it. The target destroyed before #4's turn: #4
    // ends its attack without a call and keeps its slot. A new attack, then "rejoin": the attack ends.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut w = Strike::new(&dir, "F-16I", 4, true, 4000.0);
    for (n, guided) in [(3, Some(false)), (4, Some(false))] {
        w.flight.ground_weapon(n, guided);
    }
    w.until(1.0, &|_| false);
    let at = Vec3::new(0.0, 30_000.0, 0.0);
    w.target = Some(at);
    assert_eq!(w.flight.attack(w.t, 0, Some(Bogey { pos: at, vel: Vec3::ZERO })), Some(true));
    assert_eq!(w.flight.attack(w.t, 2, None), Some(false), "no target: unable");
    w.until(3.0, &|_| false);
    assert!(w.said(2, "unable").is_some() && w.said(3, "ack").is_some() && w.said(4, "ack").is_some());
    assert_eq!(w.flight.member(4).unwrap().strike.phase.name(), "wait");
    w.target = None;
    w.until(2.0, &|_| false);
    assert_eq!(w.flight.member(4).unwrap().strike.phase.name(), "");
    assert!(w.said(4, "done").is_none() && w.said(4, "in").is_none());
    w.target = Some(at);
    assert_eq!(w.flight.attack(w.t, 4, Some(Bogey { pos: at, vel: Vec3::ZERO })), Some(true));
    w.until(2.0, &|_| false);
    assert!(w.flight.command(w.t, 4, "rejoin"));
    w.until(1.0, &|_| false);
    assert_eq!(w.flight.member(4).unwrap().strike.phase.name(), "");
}
