//! The enemy fighter's intercept (docs/ai.md §18; modern-iaf/docs/ai-plan.md K3): a MiG-29A pair on the 6-DoF and the
//! sim's own data under the enemy trees, against a scripted bogey (a point flown straight). One test per leaf: the CAP
//! orbit, the commit after the reaction time, the shot inside the skill's share of the envelope, the crank, the
//! defence by the tactics, the return to station. Skips with a message when `assets/converted/own` is not built.

use std::path::PathBuf;

use iaf_ai::fighter::{CAP_R, DRAG_M};
use iaf_ai::{Bogey, Flight, Skill, Threat, apply};
use iaf_flight::autopilot::{Autopilot, Config};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;
const ALT: f64 = 6000.0;
/// The envelope the host would give (m: max, min).
const DLZ: (f64, f64) = (40_000.0, 2_000.0);

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

/// The pair, the scripted bogey and the host's facts.
struct Pair {
    jets: Vec<(Fm, Autopilot)>,
    flight: Flight,
    t: f64,
    /// The bogey: where, how fast; the ground's vector of it on or off.
    bogey: Option<Bogey>,
    gci: bool,
    armed: bool,
    in_air: [bool; 2],
    threat: [Option<Threat>; 2],
    /// The first shot order of each jet: (time, range to the bogey).
    shot: [Option<(f64, f64)>; 2],
    frames: u64,
    busy: std::time::Duration,
}

impl Pair {
    /// Two MiG-29As in the air at `ALT`, 250 m/s heading north, #2 1.5 km to the left of #1 at `p`, on station at
    /// `station`, at `skill`.
    fn new(p: Vec3, station: Vec3, skill: Skill) -> Option<Pair> {
        let Some(dir) = own() else {
            println!("skipped: no assets/converted/own (iaf-sim fm, airbases)");
            return None;
        };
        let (prm, env) = iaf_flight::load_with(&dir, "MiG-29A", DataSet::Original).unwrap();
        let mut flight = Flight::default();
        let mut jets = Vec::new();
        for (i, pos) in [p, p - Vec3::new(1500.0, 0.0, 0.0)].into_iter().enumerate() {
            let st = Start {
                position: pos,
                pitch: 0.0,
                roll: 0.0,
                heading: 0.0,
                velocity: Vec3::new(0.0, 250.0, 0.0),
                airborne: true,
                engine_on: true,
            };
            let mut fm = Fm::start("MiG-29A", prm.clone(), env.clone(), st);
            if let Fm::SixDof(s) = &mut fm {
                s.set_ground_height(0.0);
            }
            let mut ap = Autopilot::new(Config::load(&dir));
            flight.add(i as u8 + 1, true, &fm, &mut ap);
            jets.push((fm, ap));
        }
        flight.enemy(skill, station);
        Some(Pair {
            jets,
            flight,
            t: 0.0,
            bogey: None,
            gci: true,
            armed: true,
            in_air: [false; 2],
            threat: [None; 2],
            shot: [None; 2],
            frames: 0,
            busy: Default::default(),
        })
    }

    fn frame(&mut self) {
        let clock = std::time::Instant::now();
        for (i, (fm, ap)) in self.jets.iter().enumerate() {
            self.flight.sense(i as u8 + 1, true, fm, ap);
        }
        let b = self.bogey;
        self.flight.bogey(b.filter(|_| self.gci), b);
        for n in 0..2 {
            self.flight.weapons(n as u8 + 1, DLZ, self.armed, self.in_air[n]);
            self.flight.threat(n as u8 + 1, self.threat[n]);
        }
        self.flight.step(self.t);
        for (i, (fm, ap)) in self.jets.iter_mut().enumerate() {
            apply(&self.flight.members[i].order, ap, fm);
            ap.step(fm, &|_, _| 0.0);
            fm.step(DT);
        }
        self.busy += clock.elapsed();
        self.frames += 1;
        for n in 0..2 {
            let m = &self.flight.members[n];
            if m.order.shoot && self.shot[n].is_none() {
                self.shot[n] = Some((self.t, b.map_or(0.0, |b| b.pos.distance(m.v.pos))));
            }
        }
        self.t += DT;
        if let Some(b) = &mut self.bogey {
            b.pos += b.vel * DT;
        }
    }

    fn run(&mut self, secs: f64) {
        for _ in 0..(secs / DT) as usize {
            self.frame();
        }
    }

    fn until(&mut self, limit: f64, done: &dyn Fn(&Pair) -> bool) -> Option<f64> {
        let t0 = self.t;
        while self.t - t0 < limit {
            self.frame();
            if done(self) {
                return Some(self.t - t0);
            }
        }
        None
    }

    fn pos(&self, n: usize) -> Vec3 {
        self.jets[n].0.state().position
    }

    fn phase(&self, n: usize) -> &'static str {
        self.flight.members[n].enemy.phase
    }

    /// The bogey's angle off jet `n`'s track (deg).
    fn off(&self, n: usize) -> f64 {
        let (p, v) = (self.pos(n), self.flight.members[n].v.vel);
        let d = self.bogey.unwrap().pos - p;
        (v.x * d.y - v.y * d.x).atan2(v.x * d.x + v.y * d.y).abs().to_degrees()
    }
}

fn flat(a: Vec3, b: Vec3) -> f64 {
    (a.x - b.x).hypot(a.y - b.y)
}

/// A bogey `km` north of `p` at `ALT`, flying south at 250 m/s.
fn head_on(p: Vec3, km: f64) -> Bogey {
    Bogey { pos: p + Vec3::new(0.0, km * 1000.0, 0.0), vel: Vec3::new(0.0, -250.0, 0.0) }
}

#[test]
fn cap_orbit() {
    // No bogey: the lead flies the orbit round its station, the wingman holds line abreast on it.
    let st = Vec3::new(0.0, 0.0, ALT);
    let Some(mut w) = Pair::new(Vec3::new(0.0, -CAP_R, ALT), st, Skill::MEDIUM) else { return };
    w.run(30.0);
    let (mut near, mut far) = (f64::MAX, 0.0f64);
    let mut sep = f64::MAX;
    for _ in 0..(300.0 / 0.5) as usize {
        w.run(0.5);
        let r = flat(w.pos(0), st);
        (near, far) = (near.min(r), far.max(r));
        sep = sep.min(w.pos(0).distance(w.pos(1)));
    }
    println!("cap: {near:.0}–{far:.0} m from the station, the pair at least {sep:.0} m apart");
    assert_eq!((w.phase(0), w.phase(1)), ("cap", "slot"));
    assert!(near > 0.3 * CAP_R && far < 1.6 * CAP_R, "the orbit: {near:.0}–{far:.0} m");
    assert!(sep > 500.0, "line abreast: {sep:.0} m");
    assert!((w.pos(0).z - ALT).abs() < 300.0, "at the station's height: {:.0} m", w.pos(0).z);
}

#[test]
fn commit_after_the_reaction_and_intercept() {
    // The ground's vector: a bogey 80 km out, inside the commit range. The lead commits after its reaction time (Low
    // 3 s, High 0.5 s; the first decision on the 0.5 s tick), flies the collision course and finds it on its own radar.
    for (skill, react) in [(Skill::LOW, 3.0), (Skill::HIGH, 0.5)] {
        let p = Vec3::new(0.0, 0.0, ALT);
        let Some(mut w) = Pair::new(p, p, skill) else { return };
        // A crossing bogey: 80 km north-east flying west.
        w.bogey = Some(Bogey { pos: p + Vec3::new(40_000.0, 69_000.0, 0.0), vel: Vec3::new(-250.0, 0.0, 0.0) });
        let t = w.until(10.0, &|w| w.flight.members[0].enemy.committed).expect("commits");
        println!("committed after {t:.2} s (reaction {react} s)");
        assert!(t >= react && t <= react + 0.6, "after its reaction: {t:.2} s");
        assert_eq!(w.phase(0), "intercept");
        let start = w.bogey.unwrap().pos.distance(w.pos(0));
        w.until(120.0, &|w| w.flight.members[0].enemy.contact).expect("its radar finds the bogey");
        let now = w.bogey.unwrap().pos.distance(w.pos(0));
        assert!(now < 74_000.0 && now < start, "closing: {start:.0} → {now:.0} m");
        assert!(w.flight.members[1].enemy.committed, "the wingman commits with its lead");
    }
}

#[test]
fn shot_inside_the_skill_window() {
    // Head-on from 70 km with the envelope 40–2 km: Low shoots at its edge (40 km), High deep inside (0.8: 32.4 km);
    // both jets shoot (each once its own radar holds it).
    for (skill, edge) in [(Skill::LOW, 40_000.0), (Skill::HIGH, 2_000.0 + 0.8 * 38_000.0)] {
        let p = Vec3::new(0.0, 0.0, ALT);
        let Some(mut w) = Pair::new(p, p, skill) else { return };
        w.bogey = Some(head_on(p, 70.0));
        w.until(120.0, &|w| w.shot.iter().all(|s| s.is_some())).expect("both shoot");
        for (n, s) in w.shot.iter().enumerate() {
            let (t, r) = s.unwrap();
            println!("#{} shot at {r:.0} m, t {t:.1} s (window edge {edge:.0} m)", n + 1);
            // One decision (0.5 s) at a closing speed near 550 m/s inside the edge at most.
            assert!(r <= edge && r > edge - 600.0, "#{}: {r:.0} m against {edge:.0} m", n + 1);
        }
    }
}

#[test]
fn crank_while_its_missile_flies() {
    // After the shot: Medium and High crank (the bogey about 50° off the nose, the radar holding it); Low keeps its
    // nose on.
    for (skill, crank) in [(Skill::LOW, false), (Skill::MEDIUM, true)] {
        let p = Vec3::new(0.0, 0.0, ALT);
        let Some(mut w) = Pair::new(p, p, skill) else { return };
        w.bogey = Some(head_on(p, 60.0));
        w.until(120.0, &|w| w.shot[0].is_some()).expect("shoots");
        w.in_air = [true, true];
        w.run(15.0);
        let off = w.off(0);
        println!("{} after its shot: the bogey {off:.0}° off the nose", w.phase(0));
        if crank {
            assert_eq!(w.phase(0), "crank");
            assert!((40.0..58.0).contains(&off) && w.flight.members[0].enemy.contact, "{off:.0}°");
        } else {
            assert_eq!(w.phase(0), "intercept");
            assert!(off < 15.0, "{off:.0}°");
        }
    }
}

#[test]
fn defence_by_the_tactics() {
    // A radar missile launched at the lead: Low beams at its height, Medium notches down into the look-down, High drags
    // one from far and notches one near; an infrared missile is broken into; a lock alone does not stop the attack.
    let p = Vec3::new(0.0, 0.0, ALT);
    let radar = |km: f64| Threat { pos: p + Vec3::new(0.0, km * 1000.0, 0.0), launch: true, ir: false, ground: false };
    let cases = [
        (Skill::LOW, radar(30.0), "beam"),
        (Skill::MEDIUM, radar(30.0), "notch"),
        (Skill::HIGH, radar(DRAG_M / 1000.0 + 10.0), "drag"),
        (Skill::HIGH, radar(DRAG_M / 1000.0 - 10.0), "notch"),
        (Skill::HIGH, Threat { ir: true, ..radar(5.0) }, "break"),
    ];
    for (skill, t, want) in cases {
        let Some(mut w) = Pair::new(p, p, skill) else { return };
        w.bogey = Some(head_on(p, 60.0));
        w.run(2.0);
        w.threat[0] = Some(t);
        w.run(skill.reaction_s + 1.0);
        assert!(w.flight.members[0].defending, "{want}: defending");
        assert_eq!(w.phase(0), want);
        let z0 = w.pos(0).z;
        w.run(40.0);
        let (dz, v) = (w.pos(0).z - z0, w.flight.members[0].v.vel);
        let vz = v.z;
        let off = (v.x * (t.pos.y - w.pos(0).y) - v.y * (t.pos.x - w.pos(0).x))
            .atan2(v.x * (t.pos.x - w.pos(0).x) + v.y * (t.pos.y - w.pos(0).y))
            .abs()
            .to_degrees();
        println!("{want}: the missile's launch point {off:.0}° off the nose, {dz:+.0} m in 40 s, {vz:+.1} m/s");
        match want {
            "beam" => assert!((60.0..120.0).contains(&off) && vz.abs() < 10.0, "{off:.0}°, {vz:.1} m/s"),
            "notch" => assert!((60.0..120.0).contains(&off) && vz < -10.0, "{off:.0}°, {vz:.1} m/s"),
            "drag" => assert!(off > 140.0 && vz < -10.0, "{off:.0}°, {vz:.1} m/s"),
            _ => {} // the break: past the launch point by then
        }
    }
    // A lock alone: it presses on.
    let Some(mut w) = Pair::new(p, p, Skill::HIGH) else { return };
    w.bogey = Some(head_on(p, 60.0));
    w.threat[0] = Some(Threat { launch: false, ..radar(60.0) });
    w.run(5.0);
    assert!(!w.flight.members[0].defending && w.phase(0) == "intercept", "{}", w.phase(0));
}

#[test]
fn back_to_station_with_nothing_to_shoot() {
    // Committed, then out of missiles with none flying: back to the CAP; the CPU per jet per frame (X5) printed.
    let p = Vec3::new(0.0, 0.0, ALT);
    let Some(mut w) = Pair::new(p, p, Skill::MEDIUM) else { return };
    w.bogey = Some(head_on(p, 80.0));
    w.until(10.0, &|w| w.flight.members[0].enemy.committed).expect("commits");
    w.run(20.0);
    w.armed = false;
    w.run(1.0);
    assert!(!w.flight.members[0].enemy.committed && w.phase(0) == "cap", "{}", w.phase(0));
    let us = w.busy.as_secs_f64() * 1e6 / w.frames as f64 / 2.0;
    println!("X5: {us:.2} µs per jet per frame (6-DoF, autopilot, enemy tree; {} frames)", w.frames);
}
