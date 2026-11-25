//! The enemy pair's scramble from a base (docs/ai.md §18.3; modern-iaf/docs/ai-plan.md K3): two MiG-29As on the
//! 6-DoF parked in Ramon's shelters (the sim has no enemy base: Ramon stands in), under the enemy trees. Its radar is off
//! on the ground: a bogey near it starts nothing. The ground's vector inside the commit range scrambles the pair after
//! the lead's reaction time; both taxi and take off by the autopilot's ground loops and the lead commits. The bogey
//! gone, the pair goes home, lands and parks in its shelters. Skips with a message when `assets/converted/own` is not
//! built.

use std::path::PathBuf;

use iaf_ai::fighter::COMMIT_M;
use iaf_ai::{Bandit, Bogey, Flight, Skill, apply};
use iaf_flight::airbase::Airbase;
use iaf_flight::autopilot::{self, Autopilot, Config, Waypoint};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;
const ALT: f64 = 7000.0;

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

#[test]
fn scramble_intercept_and_land() {
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    autopilot::reset_hangars();
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let rb = bases.iter().find(|b| b.name == "Ramon").unwrap().clone();
    let g = rb.lineup[2];
    let l = Vec3::new(rb.lineup[0] as f64, rb.lineup[1] as f64, g as f64);
    let (s, c) = (rb.runway_deg as f64).to_radians().sin_cos();
    let at = |along: f64, up: f64| Vec3::new(l[0] + along * s, l[1] + along * c, l[2] + up);
    // The route: the take-off point, the landing waypoint 15 km out on the approach (action 7).
    let wp = |p: Vec3, action: i32| Waypoint { x: p[0], y: p[1], z: p[2], t: 0.0, action };
    let route = vec![wp(at(15_000.0, 1500.0), 2), wp(at(-15_000.0, 1500.0), 7)];
    let (prm, env) = iaf_flight::load_with(&dir, "MiG-29A", DataSet::Original).unwrap();
    let mut flight = Flight::default();
    let mut jets: Vec<(Fm, Autopilot)> = Vec::new();
    for (h, p) in rb.hangars.iter().take(2).enumerate() {
        let st = Start {
            position: Vec3::new(p.x as f64, p.y as f64, g as f64),
            pitch: 0.0,
            roll: 0.0,
            heading: p.hdg,
            velocity: Vec3::ZERO,
            airborne: false,
            engine_on: false,
        };
        let mut fm = Fm::start("MiG-29A", prm.clone(), env.clone(), st);
        if let Fm::SixDof(s) = &mut fm {
            s.set_ground_height(g);
        }
        let mut ap = Autopilot::new(Config::load(&dir));
        ap.bases = bases.clone();
        ap.route = route.clone();
        flight.add(h as u8 + 1, true, &fm, &mut ap);
        jets.push((fm, ap));
    }
    let station = Vec3::new(l[0], l[1], ALT);
    flight.enemy(Skill::MEDIUM, station);
    assert!(flight.members.iter().all(|m| m.enemy.based), "based at Ramon");
    let frame =
        |t: &mut f64, gci: bool, bogey: &mut Option<Bogey>, flight: &mut Flight, jets: &mut [(Fm, Autopilot)]| {
            for (i, (fm, ap)) in jets.iter().enumerate() {
                flight.sense(i as u8 + 1, true, fm, ap);
            }
            flight.bandits(bogey.iter().map(|b| Bandit::new(1, *b, 0.0)).collect());
            flight.gci(bogey.filter(|_| gci), 1);
            for n in 1..=2 {
                flight.weapons(n, (40_000.0, 2_000.0), true, false);
            }
            flight.step(*t);
            for (i, (fm, ap)) in jets.iter_mut().enumerate() {
                apply(&flight.members[i].order, ap, fm);
                if let Fm::SixDof(s) = fm {
                    s.set_ground_height(g);
                }
                ap.step(fm, &|_, _| g);
                fm.step(DT);
                assert!(fm.state().crashed.is_none(), "#{} crashed in {}", i + 1, ap.stage());
            }
            *t += DT;
            if let Some(b) = bogey {
                b.pos += b.vel * DT;
            }
        };
    // A jet 40 km off, no vector: its radar is off on the ground; nothing starts.
    let (mut t, mut gci) = (0.0, false);
    let mut bogey = Some(Bogey { pos: station + Vec3::new(0.0, 40_000.0, 0.0), vel: Vec3::ZERO });
    let mut started = [None; 2];
    while t < 20.0 {
        frame(&mut t, gci, &mut bogey, &mut flight, &mut jets);
        assert!(flight.members.iter().all(|m| !m.order.start_engine), "no scramble on its own radar");
    }
    // The ground's vector: a jet 110 km north flying south at 250 m/s, inside the commit range 80 s later.
    gci = true;
    bogey = Some(Bogey { pos: station + Vec3::new(0.0, 110_000.0, 0.0), vel: Vec3::new(0.0, -250.0, 0.0) });
    let inside = t + (110_000.0 - COMMIT_M) / 250.0;
    let mut airborne = [None; 2];
    let mut committed = None;
    while t < 900.0 && (committed.is_none() || airborne[1].is_none()) {
        frame(&mut t, gci, &mut bogey, &mut flight, &mut jets);
        for i in 0..2 {
            if flight.members[i].order.start_engine && started[i].is_none() {
                started[i] = Some(t);
            }
            if jets[i].1.airborne && airborne[i].is_none() {
                airborne[i] = Some(t);
            }
        }
        let m = &flight.members[0];
        if m.enemy.committed && m.airborne && committed.is_none() {
            committed = Some(t);
        }
    }
    println!(
        "inside the commit range at {inside:.1} s; engine starts {started:?}; airborne {airborne:?}; committed {committed:?}"
    );
    let s0 = started[0].expect("the lead starts");
    let react = Skill::MEDIUM.reaction_s;
    assert!(s0 >= inside + react && s0 < inside + react + 1.1, "scramble after its reaction: {s0:.1} s");
    assert!(started[1].expect("the wingman starts") > s0, "the wingman after the lead");
    let (a0, a1) = (airborne[0].expect("the lead takes off"), airborne[1].expect("the wingman takes off"));
    assert!(a0 < a1, "take-off in order");
    let c = committed.expect("the lead commits in the air");
    assert!(c - a0 < 30.0, "the intercept after the take-off ({:.0} s)", c - a0);
    // (Its phase now: the intercept, or the crank, the dogfight by the geometry.)
    println!("the lead: {}", flight.members[0].enemy.phase.name());
    // The bogey gone (shot down): the sortie is over, home.
    bogey = None;
    let parked = |jets: &[(Fm, Autopilot)]| jets.iter().all(|(fm, ap)| ap.landed && !fm.engine_on());
    let mut home = None;
    let t0 = t;
    while t < t0 + 3000.0 && !parked(&jets) {
        frame(&mut t, gci, &mut bogey, &mut flight, &mut jets);
        if home.is_none() && jets[0].1.mode() == 8 {
            home = Some(t - t0);
        }
    }
    println!("home after {home:?} s; parked after {:.0} s", t - t0);
    assert!(home.is_some_and(|h| h < 2.0) && flight.members[0].enemy.phase.name() == "home", "the lead goes home");
    for (i, (fm, ap)) in jets.iter().enumerate() {
        let p = fm.state().position;
        let h = rb.hangars[i];
        let off = (p.x - h.x as f64).hypot(p.y - h.y as f64);
        println!("#{}: {}, engine {}, {off:.0} m from its shelter", i + 1, ap.stage(), fm.engine_on());
        assert!(ap.landed && !fm.engine_on() && off < 40.0, "#{} parked in its shelter", i + 1);
    }
}
