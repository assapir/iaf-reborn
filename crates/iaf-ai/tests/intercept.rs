//! The enemy fighter's intercept (docs/ai.md §18; modern-iaf/docs/ai-plan.md K3): a MiG-29A pair on the 6-DoF and the
//! sim's own data under the enemy trees, against a scripted bogey (a point flown straight). One test per leaf: the CAP
//! orbit, the commit after the reaction time, the shot inside the skill's share of the envelope, the crank, the
//! defence by the tactics, the return to station. Skips with a message when `assets/converted/own` is not built.

use std::path::PathBuf;

use iaf_ai::fighter::{CAP_R, DRAG_M};
use iaf_ai::site::FIGHTER;
use iaf_ai::{Bandit, Bogey, Flight, Skill, Threat, apply};
use iaf_flight::airframe::Rcs;
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
    /// Its jammer's burn-through share (0 none).
    jam: f64,
    /// Its cross-section; a ridge (8 km high, its sides 1 in 2) across the north at this y (m), None: sea level.
    rcs: Rcs,
    ridge: Option<f64>,
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
            jam: 0.0,
            rcs: FIGHTER,
            ridge: None,
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
        let rcs = self.rcs;
        self.flight.bandits(b.iter().map(|b| Bandit { rcs, ..Bandit::new(1, *b, self.jam) }).collect());
        self.flight.gci(b.filter(|_| self.gci), 1);
        for n in 0..2 {
            self.flight.weapons(n as u8 + 1, DLZ, self.armed, self.in_air[n]);
            self.flight.threat(n as u8 + 1, self.threat[n]);
        }
        let ridge = self.ridge;
        self.flight.step_on(self.t, &|p: Vec3| ridge.map(|y| (8000.0 - 0.5 * (p.y - y).abs()).max(0.0)));
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
        // A crossing bogey: 80 km north-east flying west (seen from its side: 25 m², the radar's reach 110 km).
        w.bogey = Some(Bogey { pos: p + Vec3::new(40_000.0, 69_000.0, 0.0), vel: Vec3::new(-250.0, 0.0, 0.0) });
        let t = w.until(10.0, &|w| w.flight.members[0].enemy.committed).expect("commits");
        println!("committed after {t:.2} s (reaction {react} s)");
        assert!(t >= react && t <= react + 0.6, "after its reaction: {t:.2} s");
        assert_eq!(w.phase(0), "intercept");
        let start = w.bogey.unwrap().pos.distance(w.pos(0));
        w.until(120.0, &|w| w.flight.members[0].enemy.contact).expect("its radar finds the bogey");
        let now = w.bogey.unwrap().pos.distance(w.pos(0));
        assert!(now < 110_000.0 && now <= start, "closing: {start:.0} → {now:.0} m");
        // (The wingman takes the lead's commit at its next decision.)
        w.until(1.0, &|w| w.flight.members[1].enemy.committed).expect("the wingman commits with its lead");
    }
}

#[test]
fn shot_inside_the_skill_window() {
    // Head-on from 70 km with the envelope 40–2 km: Low reacts to its edge (40 km), High deep inside (0.8: 32.4 km);
    // each shoots after its reaction time inside the window (Low 3 s, High 0.5 s); both jets shoot (each once its own
    // radar holds it).
    for (skill, edge) in [(Skill::LOW, 40_000.0), (Skill::HIGH, 2_000.0 + 0.8 * 38_000.0)] {
        let p = Vec3::new(0.0, 0.0, ALT);
        let Some(mut w) = Pair::new(p, p, skill) else { return };
        w.bogey = Some(head_on(p, 70.0));
        w.until(120.0, &|w| w.shot.iter().all(|s| s.is_some())).expect("both shoot");
        for (n, s) in w.shot.iter().enumerate() {
            let (t, r) = s.unwrap();
            let react = skill.reaction_s;
            println!("#{} shot at {r:.0} m, t {t:.1} s (window edge {edge:.0} m, reaction {react} s)", n + 1);
            // The reaction plus up to two decisions (0.5 s each) at a closing speed of 480–600 m/s inside the edge.
            let (deep, shallow) = (edge - (react + 1.0) * 600.0, edge - react * 480.0);
            assert!(r <= shallow && r > deep, "#{}: {r:.0} m, not {deep:.0}–{shallow:.0} m", n + 1);
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
    let radar = |km: f64| Threat {
        pos: p + Vec3::new(0.0, km * 1000.0, 0.0),
        vel: Vec3::ZERO,
        launch: true,
        ir: false,
        ground: false,
    };
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
        // The notch and the drag go down while they turn (90° to the beam, 180° away), as a missile may be over in a
        // few seconds.
        let z0 = w.pos(0).z;
        let (mut top, mut low) = (z0, z0);
        for _ in 0..16 {
            w.run(0.5);
            (top, low) = (top.max(w.pos(0).z), low.min(w.pos(0).z));
        }
        let dz8 = w.pos(0).z - z0;
        println!("{want}: in the first 8 s at most {:+.0} m, {dz8:+.0} m at 8 s", top - z0);
        if want == "notch" || want == "drag" {
            assert!(top - z0 < 20.0 && dz8 < -50.0, "{want}: {:+.0}, {dz8:+.0} m", top - z0);
        } else {
            // A level hard turn inside 30 m of its height (docs/ai.md §8.8).
            assert!(top - z0 < 30.0 && low - z0 > -30.0, "{want}: {:+.0} / {:+.0} m", low - z0, top - z0);
        }
        w.run(32.0);
        let (dz, v) = (w.pos(0).z - z0, w.flight.members[0].v.vel);
        let vz = v.z;
        let off = (v.x * (t.pos.y - w.pos(0).y) - v.y * (t.pos.x - w.pos(0).x))
            .atan2(v.x * (t.pos.x - w.pos(0).x) + v.y * (t.pos.y - w.pos(0).y))
            .abs()
            .to_degrees();
        println!("{want}: the missile's launch point {off:.0}° off the nose, {dz:+.0} m in 40 s, {vz:+.1} m/s");
        match want {
            "beam" => {
                assert!((60.0..120.0).contains(&off) && vz.abs() < 10.0 && dz.abs() < 30.0, "{off:.0}°, {dz:+.0} m")
            }
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

#[test]
fn fighter_laws_only_when_asked() {
    // The steer loop's turn laws are the enemy fighter's alone (`Steer::fighter`). A 6.5 g turn 90° right to a point
    // at its height, and one to a point 500 m below. Without them the loop flies as before (the wingmen's: the 75°
    // bank and the full load factor climb it). With them the level turn holds its height and the other goes down while
    // it turns.
    use iaf_flight::autopilot::{MODE_STEER, Steer};
    let mut dz = Vec::new();
    for (fighter, below) in [(false, 0.0), (false, 500.0), (true, 0.0), (true, 500.0)] {
        let p = Vec3::new(0.0, 0.0, ALT);
        let Some(mut w) = Pair::new(p, p, Skill::MEDIUM) else { return };
        let (fm, ap) = &mut w.jets[0];
        let to = p + Vec3::new(50_000.0, 0.0, -below);
        ap.steer = Some(Steer { to, g: 6.5, speed: 260.0, thr_max: 1.0, fighter });
        ap.set_mode(fm, MODE_STEER);
        let (mut lo, mut hi) = (ALT, ALT);
        for _ in 0..(8.0 / DT) as usize {
            ap.step(fm, &|_, _| 0.0);
            fm.step(DT);
            (lo, hi) = (lo.min(fm.state().position.z), hi.max(fm.state().position.z));
        }
        let end = fm.state().position.z - ALT;
        println!("fighter {fighter}, {below} m below: {:+.3} / {:+.3} m, {end:+.3} m at 8 s", lo - ALT, hi - ALT);
        dz.push((lo - ALT, hi - ALT, end));
    }
    // The wingmen's loop unchanged: the same climb to the metre as before the fighter's laws (22 Nov 2026, 9bc342c0).
    assert!((dz[0].1 - OLD_CLIMB[0]).abs() < 1.0 && (dz[1].1 - OLD_CLIMB[1]).abs() < 1.0, "{dz:?}");
    // The level turn inside 30 m (the FAA's steep-turn standard, ±100 ft; docs/ai.md §8.8).
    assert!(dz[2].0 > -30.0 && dz[2].1 < 30.0, "level: {:?}", dz[2]);
    assert!(dz[3].1 < 20.0 && dz[3].2 < -50.0, "going down: {:?}", dz[3]);
}

/// The steer loop's highest point in its first 8 s before the fighter's laws (m above the start; 9bc342c0's
/// `dive_only_when_asked` without the dive, and the same turn to a level point).
const OLD_CLIMB: [f64; 2] = [252.086, 187.486];

#[test]
fn a_jamming_bogey_is_held_inside_the_burn_through() {
    // A bogey head on from 60 km, no ground's vector: clear, the lead's radar holds it at once (inside 74 km);
    // jamming at 0.3, only inside 74 · 0.3 = 22.2 km (docs/ai.md §15.6), but its strobe (home on jam's angle) shows
    // it at once: the pair commits on the strobe and closes, so the jammer does not keep it orbiting.
    let p = Vec3::new(0.0, 0.0, ALT);
    for (jam, near) in [(0.0, 60_000.0), (0.3, 22_200.0)] {
        let Some(mut w) = Pair::new(p, p, Skill::HIGH) else { return };
        w.gci = false;
        w.bogey = Some(head_on(p, 60.0));
        w.jam = jam;
        w.run(0.5);
        let e = &w.flight.members[0].enemy;
        assert!(e.bogey.is_some() && e.strobe == (jam > 0.0) && e.contact == (jam == 0.0), "{jam}: {e:?}");
        w.until(150.0, &|w| w.flight.members[0].enemy.committed).expect("committed");
        w.until(150.0, &|w| w.flight.members[0].enemy.contact).expect("contact");
        let d = w.bogey.unwrap().pos.distance(w.pos(0));
        println!("jam {jam}: contact at {d:.0} m");
        assert!(d <= near && d > near - 8_000.0, "{d:.0} m");
        // Its own jammer answers a threat on its RWR, not the commit alone.
        assert!(!w.flight.jams(1), "committed, no threat: its jammer off");
        let lock = Threat { pos: w.bogey.unwrap().pos, vel: Vec3::ZERO, launch: false, ir: false, ground: false };
        w.threat[0] = Some(lock);
        w.run(0.1);
        assert!(w.flight.jams(1), "locked: its jammer on");
    }
}

#[test]
fn its_radar_sees_the_cross_section_the_clutter_and_the_terrain() {
    // The radar's rule is the sites' (docs/ai.md §18.1): the reach for the bogey's cross-section seen from the radar,
    // the ground's clutter in look-down, the terrain's sight. One decision each, no ground's vector.
    let p = Vec3::new(0.0, 0.0, ALT);
    let contact = |bogey: Bogey, rcs: Rcs, ridge: Option<f64>| {
        let mut w = Pair::new(p, p, Skill::HIGH)?;
        (w.gci, w.bogey, w.rcs, w.ridge) = (false, Some(bogey), rcs, ridge);
        w.run(0.1);
        Some(w.flight.members[0].enemy.contact)
    };
    // The Adir head on: 74 km · (0.0015 / 5)^¼ = 9.7 km against an untreated fighter's 74 km.
    let adir = Rcs { front_m2: 0.0015, side_m2: 0.05, rear_m2: 0.01, bays_open_m2: 1.0, store_m2: 0.5 };
    let Some(fighter_30) = contact(head_on(p, 30.0), FIGHTER, None) else { return };
    assert!(fighter_30, "an untreated fighter at 30 km");
    assert_eq!(contact(head_on(p, 30.0), adir, None), Some(false), "the Adir at 30 km");
    assert_eq!(contact(head_on(p, 9.0), adir, None), Some(true), "the Adir at 9 km");
    // A jet on the beam 3 km below: lost in look-down; the same one 3 km above, and one closing below, held.
    let beam = |dz: f64, vel: Vec3| Bogey { pos: p + Vec3::new(0.0, 30_000.0, dz), vel };
    let across = Vec3::new(250.0, 0.0, 0.0);
    assert_eq!(contact(beam(-3000.0, across), FIGHTER, None), Some(false), "on the beam below");
    assert_eq!(contact(beam(3000.0, across), FIGHTER, None), Some(true), "on the beam above");
    assert_eq!(contact(beam(-3000.0, Vec3::new(0.0, -250.0, 0.0)), FIGHTER, None), Some(true), "closing below");
    // A ridge between: masked.
    assert_eq!(contact(head_on(p, 30.0), FIGHTER, Some(15_000.0)), Some(false), "behind a ridge");
}
