//! The lead's orders to its AI wingmen (docs/ai.md §8.10, §8.11): an order on targets ([`Tactic`]) and a ground attack
//! are one job at a time. Each new order ends the other (`Member::end_order`), the end of an order (rejoin, rtb, the
//! engaged bandit gone) ends both. The tanker is apart: "refuel" ends neither, and the tree flies the tanker first.
//! Skips with a message when `assets/converted/own` is not built.

use std::path::{Path, PathBuf};

use iaf_ai::{Bandit, Bogey, Flight, Tactic};
use iaf_flight::autopilot::{Autopilot, Config};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

fn jet(dir: &Path, pos: Vec3) -> (Fm, Autopilot) {
    let (prm, env) = iaf_flight::load_with(dir, "F-16I", DataSet::Original).unwrap();
    let st = Start {
        position: pos,
        pitch: 0.0,
        roll: 0.0,
        heading: 0.0,
        velocity: Vec3::NORTH * 230.0,
        airborne: true,
        engine_on: true,
    };
    (Fm::start("F-16I", prm, env, st), Autopilot::new(Config::load(dir)))
}

/// Each wingman's (tactic, attack phase name, refuelling).
fn jobs(f: &Flight) -> Vec<(Tactic, &'static str, bool)> {
    (2..=4).map(|n| f.member(n).unwrap()).map(|m| (m.tactic, m.strike.phase.name(), m.refuelling)).collect()
}

/// No jet has an order on targets and an attack at once.
fn one_job(f: &Flight) {
    for (n, (tactic, phase, _)) in (2..=4).zip(jobs(f)) {
        assert!(tactic == Tactic::None || phase.is_empty(), "#{n}: {tactic:?} and {phase}");
    }
}

#[test]
fn an_order_ends_the_other() {
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut flight = Flight::default();
    for i in 0..4 {
        let s = if i == 0 { [0.0; 3] } else { iaf_ai::SHAPES[0].1[i - 1] };
        let (fm, mut ap) = jet(&dir, Vec3::new(s[1] as f64, s[0] as f64, 4000.0));
        flight.add(i as u8 + 1, i > 0, &fm, &mut ap);
    }
    for n in 2..=4 {
        flight.ground_weapon(n, Some(false));
    }
    let bandit = Bogey { pos: Vec3::new(0.0, 30_000.0, 4000.0), vel: Vec3::NORTH * -250.0 };
    flight.bandits(vec![Bandit::new(7, bandit, 0.0)]);
    let target = Bogey { pos: Vec3::new(0.0, 30_000.0, 0.0), vel: Vec3::ZERO };
    let (n, e, s, f) = (Tactic::None, Tactic::Engage, Tactic::Cover, Tactic::Free);

    // The attack: every wingman waits its turn, no tactic.
    assert_eq!(flight.attack(0.0, 0, Some(target)), Some(true));
    assert_eq!(jobs(&flight), [(n, "wait", false), (n, "wait", false), (n, "wait", false)]);
    // Engage (#2), cover (#3), weapons free (#4): each ends that jet's attack.
    assert_eq!(flight.engage(0.0, 2, Some(7)), Some(true));
    assert!(flight.command(0.0, 3, "cover"));
    assert_eq!(flight.free(0.0, 4, Vec3::new(0.0, 5000.0, 4000.0)), Some(true));
    assert_eq!(jobs(&flight), [(e, "", false), (s, "", false), (f, "", false)]);
    one_job(&flight);
    // A new attack ends each tactic.
    assert_eq!(flight.attack(0.0, 0, Some(target)), Some(true));
    assert_eq!(jobs(&flight), [(n, "wait", false), (n, "wait", false), (n, "wait", false)]);
    // The tanker ends neither: refuelling with its attack kept.
    assert!(flight.command(0.0, 2, "refuel"));
    assert_eq!(jobs(&flight)[0], (n, "wait", true));
    // Rejoin ends all three for #2; engage #3 again, then the bandit gone ends its order at the next decision.
    assert!(flight.command(0.0, 2, "rejoin"));
    assert_eq!(flight.engage(0.0, 3, Some(7)), Some(true));
    assert_eq!(jobs(&flight), [(n, "", false), (e, "", false), (n, "wait", false)]);
    flight.bandits(Vec::new());
    flight.step(0.0);
    assert_eq!(jobs(&flight)[1], (n, "", false));
    // RTB (#4): its attack ends at the next decision.
    assert!(flight.command(0.0, 4, "rtb"));
    flight.step(1.0);
    assert_eq!(jobs(&flight)[2], (n, "", false));
    assert!(flight.member(4).unwrap().rtb);
    one_job(&flight);
}
