//! The dogfight (docs/ai.md §18.2; modern-iaf/docs/ai-plan.md K4): MiG-29As on the 6-DoF and the sim's own data under
//! the enemy trees' BFM leaf, one against one from three starting geometries (offensive, defensive, neutral), against a
//! scripted jet turning or against another fighter flying the same leaf. Skips with a message when
//! `assets/converted/own` is not built.

use std::path::PathBuf;

use iaf_ai::{Bandit, Bogey, Flight, Skill, apply};
use iaf_flight::autopilot::{Autopilot, Config, MODE_STEER, Steer};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;
const ALT: f64 = 5000.0;

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

/// One jet: its flight model, its autopilot, and its own enemy flight (None: the scripted jet, flying its steer order).
struct Jet {
    fm: Fm,
    ap: Autopilot,
    flight: Option<Flight>,
    /// Its gun bursts (an order 0.4 s after the last is a new one): (time, range).
    bursts: Vec<(f64, f64)>,
}

/// Two jets, each the other's bogey.
struct Duel {
    jets: [Jet; 2],
    t: f64,
    frames: u64,
    busy: std::time::Duration,
    /// Jet 0's angle off its BFM point from 10 to 40 s: (sum of degrees, frames).
    err: (f64, f64),
}

/// A MiG-29A in the air at `pos` heading `heading` (deg) at `speed` m/s; flown by an enemy flight at `skill`, or
/// scripted (None).
fn jet(dir: &std::path::Path, pos: Vec3, heading: f64, speed: f64, skill: Option<Skill>) -> Jet {
    let (prm, env) = iaf_flight::load_with(dir, "MiG-29A", DataSet::Original).unwrap();
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
    let mut fm = Fm::start("MiG-29A", prm, env, st);
    if let Fm::SixDof(s) = &mut fm {
        s.set_ground_height(0.0);
    }
    let mut ap = Autopilot::new(Config::load(dir));
    let flight = skill.map(|skill| {
        let mut f = Flight::default();
        f.add(1, true, &fm, &mut ap);
        f.enemy(skill, pos);
        // A missile left (its R-73s; no envelope given: only the gun shoots here).
        f.weapons(1, (0.0, 0.0), true, false);
        f
    });
    Jet { fm, ap, flight, bursts: Vec::new() }
}

impl Duel {
    fn frame(&mut self) {
        let clock = std::time::Instant::now();
        let truth = |j: &Jet| {
            let s = j.fm.state();
            let v = s.velocity;
            Bogey { pos: s.position, vel: Vec3::new(v[0] as f64, v[1] as f64, v[2] as f64) }
        };
        let b = [truth(&self.jets[1]), truth(&self.jets[0])];
        for (i, j) in self.jets.iter_mut().enumerate() {
            if let Some(f) = &mut j.flight {
                f.sense(1, true, &j.fm, &j.ap);
                f.bandits(vec![Bandit::new(1, b[i], 0.0)]);
                f.weapons(1, (0.0, 0.0), true, false);
                f.step(self.t);
                apply(&f.members[0].order, &mut j.ap, &mut j.fm);
                if f.members[0].order.gun && j.bursts.last().is_none_or(|(t, _)| self.t - t > 0.4) {
                    j.bursts.push((self.t, b[i].pos.distance(j.fm.state().position)));
                }
            }
            j.ap.step(&mut j.fm, &|_, _| 0.0);
            j.fm.step(DT);
        }
        self.busy += clock.elapsed();
        self.frames += 1;
        if self.t > 10.0
            && self.t < 40.0
            && let Some(st) = self.jets[0].ap.steer
        {
            let d = st.to - self.pos(0);
            let v = self.vel(0);
            self.err.0 += (d.dot(v) / (d.length() * v.length())).clamp(-1.0, 1.0).acos().to_degrees();
            self.err.1 += 1.0;
        }
        self.t += DT;
    }

    fn run(&mut self, secs: f64, each: &mut dyn FnMut(&Duel)) {
        for _ in 0..(secs / DT) as usize {
            self.frame();
            each(self);
        }
    }

    fn pos(&self, n: usize) -> Vec3 {
        self.jets[n].fm.state().position
    }

    fn vel(&self, n: usize) -> Vec3 {
        let v = self.jets[n].fm.state().velocity;
        Vec3::new(v[0] as f64, v[1] as f64, v[2] as f64)
    }

    fn phase(&self, n: usize) -> &'static str {
        self.jets[n].flight.as_ref().map_or("scripted", |f| f.members[0].enemy.phase)
    }

    /// Jet `n`'s geometry against the other: the range, its nose's angle to it, its angle off the other's tail (deg).
    fn geometry(&self, n: usize) -> (f64, f64, f64) {
        let o = 1 - n;
        let a = |x: Vec3, y: Vec3| (x.dot(y) / (x.length() * y.length())).clamp(-1.0, 1.0).acos().to_degrees();
        let los = self.pos(o) - self.pos(n);
        (los.length(), a(self.vel(n), los), a(self.vel(o), los))
    }

    fn alive(&self) -> bool {
        self.jets.iter().all(|j| j.fm.state().crashed.is_none() && j.fm.state().position.z > 300.0)
    }
}

/// The scripted bogey: a level turn to the right at `g`, at its speed.
fn turning(j: &mut Jet, g: f32) {
    let s = j.fm.state();
    let right = s.right;
    j.ap.steer = Some(Steer {
        to: s.position + Vec3::new(right.x, right.y, 0.0) * 1500.0,
        g,
        speed: 230.0,
        thr_max: 1.0,
        fighter: false,
    });
    j.ap.set_mode(&mut j.fm, MODE_STEER);
}

#[test]
fn offensive_gun_solution() {
    // 1.5 km behind a jet in a 5 g turn: each skill tracks it to a gun solution within the minute, and from Medium up
    // stays behind its 3-9 line (the lag against the overshoot).
    let Some(dir) = own() else {
        println!("skipped: no assets/converted/own (iaf-sim fm)");
        return;
    };
    for skill in [Skill::LOW, Skill::MEDIUM, Skill::HIGH] {
        let target = jet(&dir, Vec3::new(0.0, 1500.0, ALT), 0.0, 230.0, None);
        let mut w = Duel {
            jets: [jet(&dir, Vec3::new(0.0, 0.0, ALT), 0.0, 250.0, Some(skill)), target],
            t: 0.0,
            frames: 0,
            busy: Default::default(),
            err: (0.0, 0.0),
        };
        turning(&mut w.jets[1], 5.0);
        let (mut front, mut phases) = (0.0, Vec::new());
        w.run(60.0, &mut |w| {
            let (_, _, aa) = w.geometry(0);
            if aa > 90.0 {
                front += DT;
            }
            if phases.last() != Some(&w.phase(0)) {
                phases.push(w.phase(0));
            }
        });
        let first = w.jets[0].bursts.first().copied();
        let err = w.err.0 / w.err.1.max(1.0);
        println!(
            "tactics {}: first burst {first:?}, {} bursts, {front:.1} s ahead of its 3-9 line, {err:.1}° off its point; \
             {phases:?}",
            skill.tactics,
            w.jets[0].bursts.len()
        );
        assert!(w.alive(), "both fly");
        assert!(first.is_some_and(|(_, r)| (330.0..=900.0).contains(&r)), "a gun solution: {first:?}");
        if skill.tactics == 0 {
            // Pure pursuit: the BFM loop's tracking (10–40 s), its gain's measure.
            assert!(err < 4.0, "tracking {err:.1}°");
        } else {
            assert!(front < 3.0, "stays behind: {front:.1} s in front");
        }
    }
}

#[test]
fn closure_control_settles_behind() {
    // 2 km behind a jet flying straight at 280 m/s, each skill closes on afterburner and then controls its closure
    // (the throttle, the speed brake): it never passes the jet's 3-9 line and settles in its gun's range, firing.
    let Some(dir) = own() else { return };
    for skill in [Skill::LOW, Skill::MEDIUM, Skill::HIGH] {
        let mut target = jet(&dir, Vec3::new(0.0, 2000.0, ALT), 0.0, 250.0, None);
        target.ap.steer =
            Some(Steer { to: Vec3::new(0.0, 400_000.0, ALT), g: 3.0, speed: 280.0, thr_max: 1.0, fighter: false });
        target.ap.set_mode(&mut target.fm, MODE_STEER);
        let mut w = Duel {
            jets: [jet(&dir, Vec3::new(0.0, 0.0, ALT), 0.0, 250.0, Some(skill)), target],
            t: 0.0,
            frames: 0,
            busy: Default::default(),
            err: (0.0, 0.0),
        };
        let (mut front, mut settled) = (0.0, (f64::MAX, 0.0f64));
        w.run(90.0, &mut |w| {
            let (r, _, aa) = w.geometry(0);
            if aa > 90.0 {
                front += DT;
            }
            if w.t > 60.0 {
                settled = (settled.0.min(r), settled.1.max(r));
            }
        });
        println!(
            "tactics {}: {:.1} s ahead of its 3-9 line; the last 30 s {:.0}–{:.0} m behind, {} bursts",
            skill.tactics,
            front,
            settled.0,
            settled.1,
            w.jets[0].bursts.len()
        );
        assert!(w.alive(), "both fly");
        assert!(front == 0.0, "overran: {front:.1} s in front");
        assert!(settled.0 >= 330.0 && settled.1 <= 900.0, "settled {settled:?}");
        assert!(!w.jets[0].bursts.is_empty(), "fires");
    }
}

/// A scripted jet flying straight at `speed` along `heading` (deg) at its height.
fn straight(j: &mut Jet, heading: f64, speed: f32) {
    let p = j.fm.state().position;
    let h = heading.to_radians();
    let to = p + Vec3::new(h.sin(), h.cos(), 0.0) * 400_000.0;
    j.ap.steer = Some(Steer { to, g: 3.0, speed, thr_max: 1.0, fighter: false });
    j.ap.set_mode(&mut j.fm, MODE_STEER);
}

/// Jet `n`'s moves in order (each once per run of decisions).
fn moves(w: &mut Duel, n: usize, secs: f64) -> Vec<&'static str> {
    let mut out = Vec::new();
    w.run(secs, &mut |w| {
        if out.last() != Some(&w.phase(n)) {
            out.push(w.phase(n));
        }
    });
    out
}

#[test]
fn scissors_reversal_and_extension() {
    // (1) Two Medium fighters line abreast 800 m apart, slow (170 m/s, below the corner): both fly the flat scissors.
    // (2) A scripted jet 860 m behind a Medium one (outside its blind cone) closing at 80 m/s: it reverses, and the jet
    // overshoots (passes its 3-9 line) within 15 s. (3) A Medium fighter 1.5 km lower and slower in the rear quarter of
    // a jet flying away: it extends (unloaded, away), then comes back (the intercept). Shaw's moves (docs/ai.md §18.2).
    let Some(dir) = own() else { return };
    let duel = |a, b| Duel { jets: [a, b], t: 0.0, frames: 0, busy: Default::default(), err: (0.0, 0.0) };
    let m = Some(Skill::MEDIUM);
    let mut w =
        duel(jet(&dir, Vec3::new(0.0, 0.0, ALT), 0.0, 170.0, m), jet(&dir, Vec3::new(800.0, 0.0, ALT), 0.0, 170.0, m));
    let mut both = [Vec::new(), Vec::new()];
    w.run(30.0, &mut |w| {
        for (n, b) in both.iter_mut().enumerate() {
            if b.last() != Some(&w.phase(n)) {
                b.push(w.phase(n));
            }
        }
    });
    println!("abreast: {both:?}");
    assert!(w.alive(), "both fly");
    assert!(both.iter().all(|b| b.contains(&"flat scissors")), "{both:?}");

    let mut attacker = jet(&dir, Vec3::new(-500.0, -700.0, ALT), 0.0, 350.0, None);
    straight(&mut attacker, 0.0, 350.0);
    let mut w = duel(jet(&dir, Vec3::new(0.0, 0.0, ALT), 0.0, 250.0, m), attacker);
    let mut passed = None;
    let mut seq = Vec::new();
    w.run(15.0, &mut |w| {
        if seq.last() != Some(&w.phase(0)) {
            seq.push(w.phase(0));
        }
        // The attacker's angle off the defender's tail past 90°: it is in front of the defender's 3-9 line.
        let (_, _, aa) = w.geometry(1);
        if aa > 90.0 && passed.is_none() {
            passed = Some(w.t);
        }
    });
    // After the overshoot the defender turns the tables: offensive on the jet (within 60° of its nose, behind its 3-9
    // line, inside 3 km) within 20 s.
    let mut turned = None;
    w.run(20.0, &mut |w| {
        let (r, ata, aa) = w.geometry(0);
        if r < 3000.0 && ata < 60.0 && aa < 90.0 && turned.is_none() {
            turned = Some(w.t);
        }
    });
    println!("overshoot: {seq:?}, passed at {passed:?}, offensive at {turned:?}");
    assert!(w.alive(), "both fly");
    assert!(seq.contains(&"reversal") && passed.is_some() && turned.is_some(), "{seq:?} {passed:?} {turned:?}");

    let mut away = jet(&dir, Vec3::new(4000.0, 0.0, ALT + 1500.0), 90.0, 250.0, None);
    straight(&mut away, 90.0, 250.0);
    let mut w = duel(jet(&dir, Vec3::new(0.0, 0.0, ALT), 0.0, 200.0, m), away);
    let seq = moves(&mut w, 0, 90.0);
    println!("extension: {seq:?}");
    assert!(w.alive(), "both fly");
    let ext = seq.iter().position(|p| *p == "extend");
    assert!(ext.is_some_and(|i| seq[i + 1..].iter().any(|p| *p != "extend")), "{seq:?}");
}

#[test]
fn defensive_break() {
    // A fighter at High 1.2 km behind, nose on: the defender breaks (turns hard into it) at once and is out of its gun
    // solution within seconds; the same with its flight ordered low (an air fight flies its own heights, docs/ai.md
    // §20: the level break holds its height).
    let Some(dir) = own() else { return };
    for (skill, low) in [Skill::LOW, Skill::MEDIUM, Skill::HIGH].into_iter().flat_map(|s| [(s, false), (s, true)]) {
        let mut me = jet(&dir, Vec3::new(0.0, 0.0, ALT), 0.0, 250.0, Some(skill));
        if let Some(f) = me.flight.as_mut().filter(|_| low) {
            f.low(Some(iaf_ai::flight::LOW_ORDER_M));
        }
        let bandit = jet(&dir, Vec3::new(-700.0, -1000.0, ALT), 0.0, 270.0, Some(Skill::HIGH));
        let mut w = Duel { jets: [me, bandit], t: 0.0, frames: 0, busy: Default::default(), err: (0.0, 0.0) };
        w.run(skill.reaction_s + 1.5, &mut |_| {});
        let first = w.phase(0);
        let h0 = w.vel(0);
        let z0 = w.pos(0).z;
        let mut dz = (0.0f64, 0.0f64);
        w.run(8.0, &mut |w| dz = (dz.0.min(w.pos(0).z - z0), dz.1.max(w.pos(0).z - z0)));
        let turned = (h0.x * w.vel(0).y - h0.y * w.vel(0).x).atan2(h0.dot(w.vel(0))).abs().to_degrees();
        let (r, _, aa) = w.geometry(1);
        println!(
            "tactics {} low {low}: {first}, turned {turned:.0}° in 8 s ({:+.0} / {:+.0} m); the bandit {r:.0} m, {aa:.0}° off its \
             tail; {} bursts at it",
            skill.tactics,
            dz.0,
            dz.1,
            w.jets[1].bursts.len()
        );
        assert!(["break", "jink", "break down"].contains(&first), "{first}");
        assert!(turned > 60.0 || first == "jink", "turned {turned:.0}°");
        if first == "break" && skill.tactics == 0 {
            // The plain tactics' level break inside 30 m of its height (docs/ai.md §8.8).
            assert!(dz.0 > -30.0 && dz.1 < 30.0, "level break: {dz:?}");
        }
    }
}

#[test]
fn neutral_merge_skill_decides() {
    // Head-on passes 0.5, 1 and 2 km apart, High against Low, both ends: High is offensive longer in sum.
    let Some(dir) = own() else { return };
    let mut score = [[0.0f64; 2]; 2];
    for (flip, side) in [false, true].into_iter().flat_map(|f| [500.0, 1000.0, 2000.0].map(|x| (f, x))) {
        let skills = if flip { [Skill::LOW, Skill::HIGH] } else { [Skill::HIGH, Skill::LOW] };
        let a = jet(&dir, Vec3::new(0.0, 0.0, ALT), 0.0, 250.0, Some(skills[0]));
        let b = jet(&dir, Vec3::new(side, 8000.0, ALT), 180.0, 250.0, Some(skills[1]));
        let mut w = Duel { jets: [a, b], t: 0.0, frames: 0, busy: Default::default(), err: (0.0, 0.0) };
        let mut off = [0.0f64; 2];
        let mut low = f64::MAX;
        w.run(120.0, &mut |w| {
            for (n, o) in off.iter_mut().enumerate() {
                let (r, ata, aa) = w.geometry(n);
                if r < 3000.0 && ata < 30.0 && aa < 60.0 {
                    *o += DT;
                }
            }
            low = low.min(w.pos(0).z.min(w.pos(1).z));
        });
        for n in 0..2 {
            let hi = usize::from(skills[n] == Skill::HIGH);
            score[hi][0] += off[n];
            score[hi][1] += w.jets[n].bursts.len() as f64;
        }
        println!(
            "{:?}: offensive {:.1} / {:.1} s, bursts {} / {}, lowest {low:.0} m",
            skills.map(|s| s.tactics),
            off[0],
            off[1],
            w.jets[0].bursts.len(),
            w.jets[1].bursts.len()
        );
        assert!(w.alive(), "both fly");
        let us = w.busy.as_secs_f64() * 1e6 / w.frames as f64 / 2.0;
        println!(
            "X5: {us:.2} µs per jet per frame (6-DoF, autopilot, enemy tree with the BFM leaf; {} frames)",
            w.frames
        );
    }
    println!(
        "High: {:.1} s offensive, {} bursts; Low: {:.1} s, {} bursts",
        score[1][0], score[1][1], score[0][0], score[0][1]
    );
    assert!(score[1][0] > score[0][0], "High offensive longer");
}

#[test]
fn r73_on_the_helmet_sight() {
    // A bogey 4 km ahead jamming the MiG's radar beyond its burn-through (the strobe: no range, no radar shot): with
    // the R-73 selected its pilot, seeing the bogey, shoots on the helmet sight; with the R-27R it does not.
    let Some(dir) = own() else { return };
    for ir in [false, true] {
        let mut j = jet(&dir, Vec3::new(0.0, 0.0, ALT), 0.0, 250.0, Some(Skill::MEDIUM));
        let f = j.flight.as_mut().unwrap();
        let (mut t, mut shot) = (0.0, false);
        while t < 5.0 && !shot {
            let b = Bogey { pos: Vec3::new(1000.0, 4000.0 + 50.0 * t, ALT), vel: Vec3::new(0.0, 200.0, 0.0) };
            f.sense(1, true, &j.fm, &j.ap);
            f.bandits(vec![Bandit::new(1, b, 0.01)]);
            f.weapons(1, (8000.0, 300.0), true, false);
            f.weapon_ir(1, ir);
            f.step(t);
            let e = &f.members[0].enemy;
            assert!(e.strobe && !e.contact && e.visual, "jammed, seen: {e:?}");
            shot = f.members[0].order.shoot;
            apply(&f.members[0].order, &mut j.ap, &mut j.fm);
            j.ap.step(&mut j.fm, &|_, _| 0.0);
            j.fm.step(DT);
            t += DT;
        }
        println!("ir {ir}: shot {shot} at {t:.2} s");
        assert_eq!(shot, ir);
    }
}
