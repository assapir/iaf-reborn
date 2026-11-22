//! Modern IAF's moving ground vehicles (docs/ai.md §19): the route by road or across country, the column's spacing and
//! march speed by type and surface, the terrain under it, the scatter on an alarm and the rejoin after the quiet.

use iaf_ai::convoy::{ALARM_M, Convoy, MARCH, Phase, QUIET_S, Route, SPACING_M, T72, URAL};
use iaf_flight::Vec3;

const DT: f64 = 0.1;

fn flat(_: Vec3) -> Option<f64> {
    Some(0.0)
}

fn run(c: &mut Convoy, t: &mut f64, secs: f64, terrain: &dyn Fn(Vec3) -> Option<f64>) {
    for _ in 0..(secs / DT).round() as usize {
        *t += DT;
        c.step(*t, DT, terrain);
    }
}

#[test]
fn route_by_road_or_across_country() {
    // A road 100 m east of the line: taken, with the short legs to and from it off the road.
    let road = [[100.0, 0.0], [100.0, 5000.0], [100.0, 10_000.0]];
    let r = Route::plan([0.0, 0.0], [0.0, 10_000.0], &road);
    assert_eq!(r.points.len(), 5);
    assert_eq!(r.road, vec![false, true, true, false]);
    assert!((r.length() - 10_200.0).abs() < 1e-6);
    assert!(r.at(5000.0).2 && !r.at(50.0).2);
    // The road 6 km away: straight across country.
    let far = [[6000.0, 0.0], [6000.0, 10_000.0]];
    let r = Route::plan([0.0, 0.0], [0.0, 10_000.0], &far);
    assert_eq!((r.points.len(), r.road.clone()), (2, vec![false]));
    // No road at all: the same.
    assert_eq!(Route::plan([0.0, 0.0], [0.0, 10_000.0], &[]).road, vec![false]);
}

#[test]
fn column_marches_on_the_road_and_stops_at_the_end() {
    let road = [[0.0, 0.0], [0.0, 3000.0]];
    let r = Route::plan([0.0, 0.0], [0.0, 3000.0], &road);
    let mut c = Convoy::new(&[&URAL, &T72, &URAL], r).unwrap();
    // Formed at the start: the tail there, each SPACING_M behind the one ahead.
    assert!((c.vehicles[0].pos.y - 2.0 * SPACING_M).abs() < 1e-9 && c.vehicles[2].pos.y.abs() < 1e-9);
    // The T-72 sets the pace: 60 km/h × MARCH on the road.
    let v = 60.0 * MARCH / 3.6;
    assert!((c.march_speed(true) - v).abs() < 1e-9);
    let mut t = 0.0;
    c.step(t, 0.0, &flat); // the host's first frame
    assert_eq!(c.phase, Phase::Move);
    let hill = |p: Vec3| Some(p.y * 0.1); // a 10 % slope up to the north
    run(&mut c, &mut t, 10.0, &hill);
    assert!((c.vehicles[0].pos.y - (2.0 * SPACING_M + 10.0 * v)).abs() < 1e-6, "{:?}", c.vehicles[0].pos);
    assert!((c.vehicles[0].vel.y - v).abs() < 1e-6 && c.vehicles[0].heading.abs() < 1e-9);
    // On the terrain, nose up on the slope.
    let h = &c.vehicles[1];
    assert!((h.pos.z - h.pos.y * 0.1).abs() < 1e-9 && (h.pitch - 0.1f64.atan().to_degrees()).abs() < 1e-6);
    // Where the terrain is not loaded: the last ground.
    let z = c.vehicles[1].pos.z;
    run(&mut c, &mut t, 1.0, &|_| None);
    assert_eq!(c.vehicles[1].pos.z, z);
    run(&mut c, &mut t, 400.0, &flat);
    assert_eq!(c.phase, Phase::Arrived);
    let ys: Vec<f64> = c.vehicles.iter().map(|v| v.pos.y).collect();
    assert!((ys[0] - 3000.0).abs() < 1e-6 && (ys[1] - 2900.0).abs() < 1e-6 && (ys[2] - 2800.0).abs() < 1e-6, "{ys:?}");
    assert!(c.vehicles.iter().all(|v| v.vel == Vec3::ZERO));
}

#[test]
fn slower_across_country() {
    let mut c = Convoy::new(&[&T72], Route::plan([0.0, 0.0], [0.0, 5000.0], &[])).unwrap();
    let mut t = 0.0;
    run(&mut c, &mut t, 10.0, &flat);
    assert!((c.vehicles[0].pos.y - 10.0 * 35.0 * MARCH / 3.6).abs() < 1e-6);
}

#[test]
fn scatters_when_attacked_and_drives_on_after() {
    let road = [[0.0, 0.0], [0.0, 20_000.0]];
    let mut c = Convoy::new(&[&T72, &URAL, &URAL, &T72], Route::plan([0.0, 0.0], [0.0, 20_000.0], &road)).unwrap();
    let mut t = 0.0;
    run(&mut c, &mut t, 30.0, &flat);
    // A bomb far off: nothing.
    assert!(!c.alarm(t, Vec3::new(ALARM_M + 2000.0, c.vehicles[0].pos.y, 0.0)));
    assert_eq!(c.phase, Phase::Move);
    // A bomb by the head: every vehicle off the road, alternating sides, then stopped.
    let head = c.vehicles[0].pos;
    assert!(c.alarm(t, head + Vec3::new(30.0, 30.0, 0.0)));
    assert_eq!(c.phase, Phase::Scatter);
    let on_road: Vec<f64> = c.vehicles.iter().map(|v| v.pos.y).collect();
    c.down(1); // the hit took a truck
    run(&mut c, &mut t, 20.0, &flat);
    for (i, v) in c.vehicles.iter().enumerate().filter(|(i, _)| *i != 1) {
        assert!(v.vel == Vec3::ZERO, "{i} stopped");
        assert!(v.pos.x.abs() > 50.0 && (v.pos.x > 0.0) == (i % 2 == 0), "{i} off the road to its side: {:?}", v.pos);
    }
    // The wreck stays where it was hit.
    assert_eq!(c.vehicles[1].pos.y, on_road[1]);
    // Another blast restarts the quiet; QUIET_S after the last one they rejoin, closed up behind the head.
    run(&mut c, &mut t, QUIET_S - 25.0, &flat);
    c.alarm(t, c.vehicles[0].pos);
    run(&mut c, &mut t, QUIET_S - 5.0, &flat);
    assert_eq!(c.phase, Phase::Scatter);
    run(&mut c, &mut t, 10.0, &flat);
    assert_eq!(c.phase, Phase::Rejoin);
    run(&mut c, &mut t, 60.0, &flat);
    assert_eq!(c.phase, Phase::Move, "back on the road");
    let (a, b, d) = (c.vehicles[0], c.vehicles[2], c.vehicles[3]);
    assert!(a.pos.x.abs() < 1e-6 && b.pos.x.abs() < 1e-6 && d.pos.x.abs() < 1e-6);
    assert!((a.pos.y - b.pos.y - SPACING_M).abs() < 1e-6 && (b.pos.y - d.pos.y - SPACING_M).abs() < 1e-6);
    assert!(a.vel.y > 0.0 && a.pos.y > head.y);
}
