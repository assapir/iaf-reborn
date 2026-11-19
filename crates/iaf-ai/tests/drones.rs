//! The one-way attack drones (`iaf_ai::drone`, docs/ai.md §16): the route flown in order within the height band, the
//! turn and climb limits, the dive onto the end point, the salvo's spacing, and the player's radar finding one by its
//! cross-section and the terrain.

use iaf_ai::drone::{Phase, SHAHED_136, Salvo};
use iaf_avionics::radar::{Input, Own, Radar, Unit};
use iaf_flight::Vec3;

const S: &iaf_ai::drone::Spec = &SHAHED_136;
const DT: f64 = 0.1;

/// Ground at 100 m with a 300 m ridge across y = 20–22 km.
fn ridge(p: Vec3) -> Option<f64> {
    Some(if (20_000.0..22_000.0).contains(&p.y) { 400.0 } else { 100.0 })
}

fn flat(_: Vec3) -> Option<f64> {
    Some(0.0)
}

fn heading(v: Vec3) -> f64 {
    v.x.atan2(v.y)
}

#[test]
fn flies_its_route_in_order_within_the_band_and_limits() {
    let route = [
        Vec3::new(0.0, 0.0, 0.0),
        Vec3::new(0.0, 30_000.0, 0.0),
        Vec3::new(20_000.0, 30_000.0, 0.0),
        Vec3::new(20_000.0, 10_000.0, 0.0),
    ];
    let s = Salvo::new(S, &route, 1, 0.0, 0.0).unwrap();
    assert_eq!(s.agl, S.agl_min, "a height below the band is raised to it");
    let mut s = Salvo { agl: S.agl, ..s };
    let rate = 9.81 * S.bank_deg.to_radians().tan() / S.cruise;
    let radius = S.cruise / rate;
    let mut legs = vec![1];
    let mut near = [f64::MAX; 2];
    let mut was = None;
    let mut dived = false;
    for _ in 0..30_000 {
        s.step(DT, &ridge);
        let d = s.drones[0];
        if d.phase == Phase::Impact {
            break;
        }
        assert!((d.vel.length() - S.cruise).abs() < 1e-6, "cruise speed: {}", d.vel.length());
        if *legs.last().unwrap() != d.leg {
            legs.push(d.leg);
        }
        for (i, n) in near.iter_mut().enumerate() {
            let to = route[i + 1] - d.pos;
            *n = n.min(to.x.hypot(to.y));
        }
        if d.phase == Phase::Cruise {
            let agl = d.pos.z - ridge(d.pos).unwrap();
            assert!((S.agl_min..=S.agl_max).contains(&agl), "in the band: {agl:.0} m at {:?}", d.pos);
            assert!(d.vel.z <= S.climb + 1e-9 && d.vel.z >= -S.sink - 1e-9, "climb / sink: {}", d.vel.z);
            if let Some(h) = was {
                let turned = iaf_flight::vec3::wrap_pi(heading(d.vel) - h).abs();
                assert!(turned <= rate * DT + 1e-9, "the turn rate: {turned}");
            }
            was = Some(heading(d.vel));
        } else {
            dived = true;
        }
    }
    let d = s.drones[0];
    assert_eq!(legs, [1, 2, 3], "the waypoints in order");
    for (i, n) in near.iter().enumerate() {
        assert!(*n <= radius + 1.0, "waypoint {} passed within the turn's radius: {n:.0} m", i + 1);
    }
    assert!(dived, "it dives");
    assert_eq!(d.phase, Phase::Impact);
    assert!(d.pos.distance(Vec3::new(20_000.0, 10_000.0, 100.0)) < 1e-6, "on the end point: {:?}", d.pos);
}

#[test]
fn holds_its_height_over_the_ridge() {
    let route = [Vec3::new(0.0, 0.0, 0.0), Vec3::new(0.0, 40_000.0, 0.0)];
    let mut s = Salvo::new(S, &route, 1, S.agl, 0.0).unwrap();
    let mut over = f64::MAX;
    while s.drones[0].pos.y < 23_000.0 {
        s.step(DT, &ridge);
        let p = s.drones[0].pos;
        if (20_000.0..22_000.0).contains(&p.y) {
            over = over.min(p.z - 400.0);
        }
    }
    assert!(over > 250.0 && over < S.agl, "it climbs for the ridge ahead, its least height over it {over:.0} m");
    for _ in 0..1200 {
        s.step(DT, &ridge);
    }
    let agl = s.drones[0].pos.z - 100.0;
    assert!((agl - S.agl).abs() < 5.0, "back at its height past the ridge: {agl:.0} m");
}

#[test]
fn dives_onto_the_end_point() {
    let route = [Vec3::new(0.0, 0.0, 0.0), Vec3::new(0.0, 10_000.0, 0.0)];
    let mut s = Salvo::new(S, &route, 1, S.agl, 0.0).unwrap();
    let mut start = None;
    let mut pitch = Vec::new();
    while s.drones[0].phase != Phase::Impact {
        s.step(DT, &flat);
        let d = s.drones[0];
        if d.phase == Phase::Dive {
            start.get_or_insert(d.pos);
            pitch.push(d.pitch());
        }
    }
    let start = start.expect("a dive");
    let want = S.agl / S.dive_deg.to_radians().tan();
    assert!((10_000.0 - start.y - want).abs() < 2.0 * S.cruise * DT, "the dive starts {:.0} m out", 10_000.0 - start.y);
    assert!(pitch.iter().all(|p| (p + S.dive_deg).abs() < 1.0), "{} degrees down: {pitch:?}", S.dive_deg);
    assert!(s.drones[0].pos.distance(Vec3::new(0.0, 10_000.0, 0.0)) < 1e-6, "it ends on the end point");
}

#[test]
fn a_low_drone_dives_for_an_end_point_inside_its_turn() {
    // Past the first waypoint the end point lies inside its turn's circle and nearer than a 40° dive from 100 m.
    let route = [Vec3::new(0.0, 0.0, 0.0), Vec3::new(0.0, 5_000.0, 0.0), Vec3::new(200.0, 4_700.0, 0.0)];
    let mut s = Salvo::new(S, &route, 1, 100.0, 0.0).unwrap();
    for _ in 0..3000 {
        s.step(DT, &flat);
    }
    assert_eq!(s.drones[0].phase, Phase::Impact, "no circling: {:?}", s.drones[0]);
    assert!(s.drones[0].pos.distance(route[2]) < 1e-6);
}

#[test]
fn holds_its_height_where_the_terrain_is_unknown() {
    let unknown = |_: Vec3| None;
    let route = [Vec3::new(0.0, 0.0, 300.0), Vec3::new(0.0, 5_000.0, 300.0)];
    let mut s = Salvo::new(S, &route, 1, S.agl, 0.0).unwrap();
    while s.drones[0].phase != Phase::Impact {
        s.step(DT, &unknown);
        let d = s.drones[0];
        if d.phase == Phase::Cruise {
            assert!((d.pos.z - 300.0 - S.agl).abs() < 1e-6, "over the route's height: {}", d.pos.z);
        }
    }
    assert!(s.drones[0].pos.distance(route[1]) < 1e-6, "on the end point at its given height");
}

#[test]
fn a_salvo_launches_one_after_another() {
    let route = [Vec3::new(0.0, 0.0, 0.0), Vec3::new(0.0, 100_000.0, 0.0)];
    let mut s = Salvo::new(S, &route, 3, S.agl, S.interval).unwrap();
    for _ in 0..50 {
        s.step(DT, &flat);
    }
    let phases: Vec<Phase> = s.drones.iter().map(|d| d.phase).collect();
    assert_eq!(phases, [Phase::Cruise, Phase::Wait, Phase::Wait], "5 s in: the first only");
    for _ in 0..550 {
        s.step(DT, &flat);
    }
    assert!(s.drones.iter().all(|d| d.phase == Phase::Cruise));
    for w in s.drones.windows(2) {
        let gap = w[0].pos.y - w[1].pos.y;
        assert!((gap - S.cruise * S.interval).abs() < 1e-6, "{} s apart along the route: {gap} m", S.interval);
    }
    s.down(1);
    s.step(DT, &flat);
    assert_eq!(s.drones[1].phase, Phase::Down, "a drone the game destroyed flies no more");
}

/// An F-16's radar (the 1998 table: LRS 45 NM) at 5,000 m flying north; a jet and a drone ahead at `nm`.
fn scan(nm: f64, terrain: &dyn Fn(Vec3) -> Option<f64>, own_z: f64) -> Vec<String> {
    let at = |x: f64| Vec3::new(x, nm * 1852.0, 5000.0_f64.min(own_z + 100.0));
    let jet = Unit {
        key: "jet".into(),
        pos: at(-200.0),
        vel: Vec3::new(0.0, -250.0, 0.0),
        class: 0x1c,
        state: 1,
        ..Default::default()
    };
    let drone = Unit {
        key: "drone".into(),
        pos: at(200.0),
        vel: Vec3::new(0.0, -S.cruise, 0.0),
        class: 3,
        state: 1,
        rcs: Some(S.rcs),
        ..Default::default()
    };
    let own = Own { pos: Vec3::new(0.0, 0.0, own_z), fwd: Vec3::NORTH, up: Vec3::UP, ..Default::default() };
    let units = [jet, drone];
    let input = Input { own, units: &units, terrain, bare: None };
    let mut r = Radar::new(1, None, None, false);
    r.toggle_aa_ag(0.0, &input);
    let mut keys: Vec<String> = r.contacts().iter().map(|c| c.key.clone()).collect();
    keys.sort();
    keys
}

#[test]
fn the_radar_finds_a_drone_closer_than_a_jet() {
    // 45 NM × (0.01 / 5)^¼ = 9.5 NM.
    assert_eq!(scan(40.0, &flat, 5000.0), ["jet"], "40 NM: the jet only");
    assert_eq!(scan(10.0, &flat, 5000.0), ["jet"], "10 NM: still the jet only");
    assert_eq!(scan(9.0, &flat, 5000.0), ["drone", "jet"], "9 NM: the drone too");
}

#[test]
fn the_terrain_hides_a_drone() {
    // Both 100 m above a jet at 600 m, with a 2 km ridge 4–5 km ahead of the jet.
    let ridge = |p: Vec3| Some(if (4000.0..5000.0).contains(&p.y) { 2000.0 } else { 0.0 });
    assert_eq!(scan(4.0, &flat, 600.0), ["drone", "jet"], "in the open: both");
    assert!(scan(4.0, &ridge, 600.0).is_empty(), "behind the ridge: neither");
}
