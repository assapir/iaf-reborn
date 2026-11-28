//! An AI lead with the player in its flight (a lesson's `start.seat`, modern-iaf/docs/training.md §16.8): its tactical
//! turns (CNATRA P-1221's tac turn and in-place turn, `iaf_ai::LeadStep::Turn`) with an AI wingman in line abreast,
//! the plan's orders by waypoint, and its wait on the ground for the player's engine. Skips with a message when
//! `assets/converted/own` is not built.

use std::path::{Path, PathBuf};

use iaf_ai::{Flight, LeadStep, apply};
use iaf_flight::autopilot::{Autopilot, Config, Host, MODE_TAKE_OFF, Waypoint};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

fn jet(dir: &Path, pos: Vec3, speed: f64, airborne: bool) -> (Fm, Autopilot) {
    let (prm, env) = iaf_flight::load_with(dir, "F-16I", DataSet::Original).unwrap();
    let st = Start {
        position: pos,
        pitch: 0.0,
        roll: 0.0,
        heading: 0.0,
        velocity: Vec3::NORTH * speed,
        airborne,
        engine_on: airborne,
    };
    (Fm::start("F-16I", prm, env, st), Autopilot::new(Config::load(dir)))
}

/// Two jets and their flight; #1 the AI lead on its route, #2 `ai` (else the player's, flown here by its own slot
/// loop as a stand-in for the student).
struct Pair {
    jets: Vec<(Fm, Autopilot)>,
    flight: Flight,
    t: f64,
    /// The ground's height, m.
    ground: f32,
}

impl Pair {
    fn step(&mut self, seconds: f64) {
        for _ in 0..(seconds / DT) as usize {
            for (i, (fm, ap)) in self.jets.iter().enumerate() {
                self.flight.sense(i as u8 + 1, true, fm, ap);
            }
            self.flight.step(self.t);
            for (i, (fm, ap)) in self.jets.iter_mut().enumerate() {
                if self.flight.members[i].ai {
                    apply(&self.flight.members[i].order, ap, fm);
                }
                let g = self.ground;
                if let Fm::SixDof(s) = fm {
                    s.set_ground_height(g);
                }
                ap.step(fm, &|_, _| g);
                fm.step(DT);
                assert!(fm.state().crashed.is_none(), "#{} crashed at {:.1} s", i + 1, self.t);
            }
            self.t += DT;
        }
    }

    fn track(&self, i: usize) -> f64 {
        let v = self.jets[i].0.ap_view().vel;
        v[0].atan2(v[1]).to_degrees().rem_euclid(360.0)
    }

    /// #2's place right of #1 across #1's track, m.
    fn right(&self) -> f64 {
        let (a, b) = (self.jets[0].0.ap_view().pos, self.jets[1].0.ap_view().pos);
        let h = self.track(0).to_radians();
        let d = b - a;
        d[0] * h.cos() - d[1] * h.sin()
    }
}

fn airborne_pair(dir: &Path, route: Vec<Waypoint>) -> Pair {
    let z = 3000.0;
    let mut jets =
        vec![jet(dir, Vec3::new(0.0, 0.0, z), 160.0, true), jet(dir, Vec3::new(-1500.0, 0.0, z), 160.0, true)];
    let mut flight = Flight::default();
    for (i, (fm, ap)) in jets.iter_mut().enumerate() {
        ap.route = route.clone();
        flight.add(i as u8 + 1, true, fm, ap);
    }
    Pair { jets, flight, t: 0.0, ground: 0.0 }
}

fn off(a: f64, b: f64) -> f64 {
    (a - b + 180.0).rem_euclid(360.0) - 180.0
}

#[test]
fn tac_turn_and_in_place_turn_swap_the_sides() {
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let far = |x: f64, y: f64| Waypoint { x, y, z: 3000.0, t: 0.0, action: 0 };
    let mut p = airborne_pair(&dir, vec![far(0.0, 200_000.0)]);
    assert!(p.flight.lead_order(0.0, LeadStep::Shape(1)), "line abreast");
    p.step(60.0);
    println!("line abreast: #2 {:.0} m right, slot error {:.0} m", p.right(), p.flight.members[1].slot_error);
    assert!((p.right() + 1500.0).abs() < 300.0, "#2 abeam on the left before the turn: {:.0} m", p.right());

    // Tac right: #2 (on the left: outside) turns first; the lead waits for #2's nose on it.
    let h0 = p.track(0);
    p.jets[0].1.route = vec![far(200_000.0, 1500.0)];
    assert!(p.flight.lead_order(p.t, LeadStep::Turn { right: true, in_place: false }));
    p.step(6.0);
    let (lead_turned, wing_turned) = (off(p.track(0), h0), off(p.track(1), h0));
    println!("tac right after 6 s: the lead {lead_turned:.0}°, #2 {wing_turned:.0}°");
    assert!(wing_turned > 15.0 && lead_turned.abs() < 5.0, "the outside jet first, the inside waits");
    let t0 = p.t;
    while p.flight.turning() && p.t - t0 < 120.0 {
        p.step(0.5);
    }
    p.step(40.0);
    println!(
        "tac right over after {:.0} s: tracks {:.0}° and {:.0}°, #2 {:.0} m right, slot error {:.0} m",
        p.t - t0,
        p.track(0),
        p.track(1),
        p.right(),
        p.flight.members[1].slot_error
    );
    assert!(
        off(p.track(0), h0 + 90.0).abs() < 15.0 && off(p.track(1), h0 + 90.0).abs() < 15.0,
        "both on the new heading"
    );
    assert!((p.right() - 1500.0).abs() < 500.0, "#2 now abeam on the lead's right: {:.0} m", p.right());
    assert!(p.flight.shape().1, "the slots mirrored");

    // In-place left: both at once, 180°; #2 back on the left.
    let h1 = p.track(0);
    p.jets[0].1.route = vec![far(-200_000.0, 1500.0)];
    assert!(p.flight.lead_order(p.t, LeadStep::Turn { right: false, in_place: true }));
    p.step(6.0);
    assert!(off(p.track(0), h1) < -10.0 && off(p.track(1), h1) < -10.0, "both turn at once");
    let t0 = p.t;
    while p.flight.turning() && p.t - t0 < 120.0 {
        p.step(0.5);
    }
    p.step(40.0);
    println!("in-place left over: tracks {:.0}° and {:.0}°, #2 {:.0} m right", p.track(0), p.track(1), p.right());
    assert!(off(p.track(0), h1 + 180.0).abs() < 15.0, "the lead on the reciprocal");
    assert!(p.right() < -800.0, "#2 on the lead's left again: {:.0} m", p.right());

    // A tac turn swaps the sides again (one turn more: mirrored); fingertip then flies as drawn, #2 on the left.
    let at = p.jets[0].0.ap_view().pos;
    p.jets[0].1.route = vec![far(at[0], at[1] + 200_000.0)];
    assert!(p.flight.lead_order(p.t, LeadStep::Turn { right: true, in_place: false }));
    let t0 = p.t;
    while p.flight.turning() && p.t - t0 < 120.0 {
        p.step(0.5);
    }
    assert!(p.flight.shape().1, "three turns: mirrored");
    assert!(p.flight.lead_order(p.t, LeadStep::Shape(0)));
    p.step(60.0);
    println!("fingertip after three turns: #2 {:.0} m right", p.right());
    assert!(!p.flight.shape().1 && p.right() < 0.0, "fingertip as drawn: #2 on the left ({:.0} m)", p.right());
}

#[test]
fn the_plan_gives_its_orders_past_their_waypoints() {
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let w = |y: f64| Waypoint { x: 0.0, y, z: 3000.0, t: 0.0, action: 0 };
    let mut p = airborne_pair(&dir, vec![w(5_000.0), w(15_000.0), w(200_000.0)]);
    p.flight.set_plan(vec![(0, LeadStep::Shape(2)), (1, LeadStep::Rejoin)]);
    p.step(10.0);
    assert_eq!(p.flight.shape().0, 0, "fingertip before the first point");
    p.step(40.0);
    assert_eq!(p.flight.shape().0, 2, "trail past the first point");
    p.step(70.0);
    assert_eq!(p.flight.shape().0, 0, "the rejoin past the second");
}

#[test]
fn an_ai_lead_waits_for_the_players_engine() {
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let bases = iaf_flight::airbase::Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let ramon = bases.iter().find(|b| b.name == "Ramon").unwrap();
    let r = Vec3::new(ramon.lineup[0] as f64, ramon.lineup[1] as f64, ramon.lineup[2] as f64);
    let home = Waypoint { x: r[0], y: r[1] + 30_000.0, z: r[2] + 3000.0, t: 0.0, action: 0 };
    let mut jets = vec![
        jet(&dir, Vec3::new(r[0] - 300.0, r[1] - 300.0, r[2]), 0.0, false),
        jet(&dir, Vec3::new(r[0] - 350.0, r[1] - 300.0, r[2]), 0.0, false),
    ];
    let mut flight = Flight::default();
    for (i, (fm, ap)) in jets.iter_mut().enumerate() {
        ap.bases = bases.clone();
        ap.route = vec![home];
        flight.add(i as u8 + 1, i == 0, fm, ap);
    }
    let mut p = Pair { jets, flight, t: 0.0, ground: r[2] as f32 };
    p.flight.start_up(0.0);
    p.step(90.0);
    assert!(p.jets[0].0.engine_on(), "the lead starts on the flight's clearance");
    assert_ne!(p.jets[0].1.mode(), MODE_TAKE_OFF, "it waits for the player's engine");
    p.jets[1].0.set_engine_on(true);
    p.step(60.0);
    assert_ne!(p.jets[0].1.mode(), MODE_TAKE_OFF, "the player's engine has run only 60 s");
    p.step(70.0);
    assert_eq!(p.jets[0].1.mode(), MODE_TAKE_OFF, "it taxis once the player's engine has run two minutes");
}
