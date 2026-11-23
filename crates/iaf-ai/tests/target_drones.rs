//! The target drones' decisions (docs/ai.md §21): the kind from the brain record's actions, the period, and the
//! loop each kind flies.

use iaf_ai::target::{Drone, EVADE_M, Kind, MODE_BREAK_90, MODE_ROUTE, MODE_RUN_AWAY, PERIOD_S};

#[test]
fn the_kind_comes_from_the_brain_records_actions() {
    // data/db/brains: drone (navigate), drone_radar (+ select_air_target), drone_evade (+ break_90, run_away).
    assert_eq!(Kind::of_actions(&[240]), Some(Kind::Route));
    assert_eq!(Kind::of_actions(&[400, 240]), Some(Kind::Radar));
    assert_eq!(Kind::of_actions(&[400, 170, 160, 240]), Some(Kind::Evade));
    // Not a target drone's brain: a weapon action, or no route.
    assert_eq!(Kind::of_actions(&[400, 300, 240]), None);
    assert_eq!(Kind::of_actions(&[400]), None);
    assert_eq!(Kind::of_actions(&[]), None);
}

#[test]
fn a_decision_at_once_then_every_period() {
    let mut d = Drone::new(Kind::Route);
    assert!(d.due(10.0));
    assert!(!d.due(10.0 + PERIOD_S - 0.01));
    assert!(d.due(10.0 + PERIOD_S));
}

#[test]
fn the_route_and_radar_drones_never_manoeuvre() {
    for kind in [Kind::Route, Kind::Radar] {
        let d = Drone::new(kind);
        for r in [None, Some(100.0), Some(EVADE_M - 1.0)] {
            for roll in [0, 49, 50, 100] {
                assert_eq!(d.mode(r, roll), MODE_ROUTE, "{kind:?} at {r:?}, roll {roll}");
            }
        }
    }
    assert!(!Drone::new(Kind::Route).scans());
    assert!(Drone::new(Kind::Radar).scans());
}

#[test]
fn the_evading_drone_breaks_or_runs_inside_its_range() {
    let d = Drone::new(Kind::Evade);
    assert!(d.scans());
    assert_eq!(d.mode(None, 0), MODE_ROUTE);
    assert_eq!(d.mode(Some(EVADE_M), 0), MODE_ROUTE);
    assert_eq!(d.mode(Some(EVADE_M - 1.0), 49), MODE_BREAK_90);
    assert_eq!(d.mode(Some(EVADE_M - 1.0), 50), MODE_RUN_AWAY);
    assert_eq!(d.mode(Some(500.0), 100), MODE_RUN_AWAY);
}
