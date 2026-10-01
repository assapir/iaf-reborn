//! The AI autopilot (docs/ai.md §7–§8) flying the original data: route following (mode 7), close
//! formation (mode 1) and the take-off sequence (mode 9) at Ramat David. Needs `assets/install`.

use std::path::PathBuf;

use iaf_flight::airbase::Airbase;
use iaf_flight::autopilot::{Autopilot, Config, Leader, Waypoint};
use iaf_flight::{Aircraft, DataSet, Start};

fn install() -> Option<PathBuf> {
    let p = std::env::var_os("IAF_INSTALL")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/install"));
    p.join("resource/md").is_dir().then_some(p)
}

fn jet(install: &PathBuf, name: &str, pos: [f64; 3], heading_deg: f32, airborne: bool) -> Aircraft {
    let (p, e) = iaf_flight::load_with(install, name, DataSet::Original).unwrap();
    let h = heading_deg.to_radians();
    let v = if airborne { 282.84 } else { 0.0 };
    let st = Start {
        position: pos,
        pitch: 0.0,
        roll: 0.0,
        heading: h,
        velocity: [(v * h.sin()) as f64, (v * h.cos()) as f64, 0.0],
        airborne,
        engine_on: true,
    };
    let mut a = Aircraft::start(p, e, st);
    a.ground_height = 0.0;
    a
}

const DT: f64 = 1.0 / 60.0;

fn fly(ac: &mut Aircraft, ap: &mut Autopilot, seconds: f64, ground: f32) {
    let g = |_: f64, _: f64| ground;
    for _ in 0..(seconds / DT) as usize {
        ac.ground_height = ground;
        ap.step(ac, &g);
        ac.step(DT);
    }
}

#[test]
fn follows_its_route() {
    let Some(inst) = install() else { return };
    let mut ac = jet(&inst, "MIG29", [0.0, 0.0, 3000.0], 0.0, true);
    let mut ap = Autopilot::new(Config::load(&inst));
    // North 30 km, then east 30 km, climbing to 4000 m.
    ap.route = vec![
        Waypoint {
            x: 0.0,
            y: 30000.0,
            z: 3000.0,
            t: 0.0,
            action: 3,
        },
        Waypoint {
            x: 30000.0,
            y: 30000.0,
            z: 4000.0,
            t: 0.0,
            action: 3,
        },
        Waypoint {
            x: 30000.0,
            y: 60000.0,
            z: 4000.0,
            t: 0.0,
            action: 3,
        },
    ];
    ap.set_mode(&mut ac, 7);
    assert_eq!(ac.ai_mode, 7);
    let mut closest = [f64::MAX; 3];
    for t in 0..600 {
        fly(&mut ac, &mut ap, 1.0, 0.0);
        let p = ac.state().position;
        if t % 15 == 0 {
            let st = ac.state();
            println!("{t}: {} pos {:.0} {:.0} {:.0} v {:.0} hdg {:.0} pitch {:.1} roll {:.0}", ap.stage(), p[0], p[1], p[2], st.speed, st.heading.to_degrees(), st.pitch.to_degrees(), st.roll.to_degrees());
        }
        for (i, w) in ap.route.iter().enumerate() {
            closest[i] = closest[i].min((p[0] - w.x).hypot(p[1] - w.y));
        }
        assert!(ac.state().crashed.is_none(), "crashed at {:?}", p);
    }
    let s = ac.state();
    println!(
        "closest {closest:?}, index {}, alt {:.0}, speed {:.0}",
        ap.wp_index, s.position[2], s.speed
    );
    for c in closest {
        assert!(
            c < 2500.0,
            "passed every waypoint within the capture radius: {closest:?}"
        );
    }
    assert_eq!(ap.wp_index, 2);
    assert!(
        (s.speed - 275.0).abs() < 40.0,
        "cruise 275 m/s without ETAs ({})",
        s.speed
    );
}

#[test]
fn keeps_close_formation() {
    let Some(inst) = install() else { return };
    let mut lead = jet(&inst, "F-16", [0.0, 0.0, 3000.0], 90.0, true);
    let mut wing = jet(&inst, "F-16", [-1500.0, -1200.0, 2500.0], 90.0, true);
    let cfg = Config::load(&inst);
    let mut lap = Autopilot::new(cfg);
    lap.route = vec![Waypoint {
        x: 200000.0,
        y: 0.0,
        z: 3000.0,
        t: 0.0,
        action: 3,
    }];
    lap.set_mode(&mut lead, 7);
    let mut wap = Autopilot::new(cfg);
    wap.set_mode(&mut wing, 1);
    let g = |_: f64, _: f64| 0.0;
    let mut err = 0.0;
    for i in 0..(240.0 / DT) as usize {
        let ls = lead.state();
        wap.leader = Some(Leader {
            pos: ls.position,
            vel: [
                ls.velocity[0] as f64,
                ls.velocity[1] as f64,
                ls.velocity[2] as f64,
            ],
            att: [ls.pitch, ls.roll, ls.heading],
            active: true,
        });
        lap.step(&mut lead, &g);
        wap.step(&mut wing, &g);
        lead.step(DT);
        wing.step(DT);
        if i % 1200 == 0 {
            let (l, w) = (lead.state(), wing.state());
            println!(
                "t {:.0}: offset {:.0} {:.0} {:.0}  v {:.0}/{:.0}",
                i as f64 * DT,
                w.position[0] - l.position[0],
                w.position[1] - l.position[1],
                w.position[2] - l.position[2],
                w.speed,
                l.speed
            );
        }
        if i as f64 * DT > 180.0 {
            // The slot: 20 m behind, 100 m right of the leader (UNCERTAIN side, docs/ai.md §8.4).
            let (l, w) = (lead.state(), wing.state());
            let d = [w.position[0] - l.position[0], w.position[1] - l.position[1]];
            err = f64::max(err, (d[0] + 20.0).hypot(d[1] + 100.0));
        }
    }
    let (l, w) = (lead.state(), wing.state());
    println!(
        "wingman offset {:.0} {:.0} {:.0}, max error {err:.0}",
        w.position[0] - l.position[0],
        w.position[1] - l.position[1],
        w.position[2] - l.position[2]
    );
    assert!(err < 450.0, "the wingman holds its slot ({err:.0} m)");
}

#[test]
fn takes_off_from_ramat_david() {
    let Some(inst) = install() else { return };
    let bases = Airbase::load_all(&std::fs::read(inst.join("iaf.ibx")).unwrap());
    let rd = bases.iter().find(|b| b.name == "David").unwrap().clone();
    // A jet parked at its hangar (the first departure turn point's hangar).
    let h = rd.hangars[0];
    let z = rd.lineup[2] as f64;
    let mut ac = jet(
        &inst,
        "F-16",
        [h.x as f64, h.y as f64, z],
        h.hdg.to_degrees(),
        false,
    );
    ac.ground_height = z as f32;
    let mut ap = Autopilot::new(Config::load(&inst));
    ap.bases = bases;
    ap.route = vec![Waypoint {
        x: 340000.0,
        y: 602383.0,
        z: 1500.0,
        t: 20.0,
        action: 2,
    }];
    ap.set_mode(&mut ac, 9);
    let mut reached_lineup = false;
    let mut airborne_at = None;
    for s in 0..400 {
        fly(&mut ac, &mut ap, 1.0, z as f32);
        let st = ac.state();
        assert!(st.crashed.is_none(), "no crash ({:?})", st.crashed);
        if (st.position[0] - rd.lineup[0] as f64).hypot(st.position[1] - rd.lineup[1] as f64)
            < 150.0
        {
            reached_lineup = true;
        }
        if airborne_at.is_none() && st.position[2] > z + 100.0 {
            airborne_at = Some(s);
        }
    }
    let st = ac.state();
    println!(
        "airborne after {airborne_at:?} s; now {:.0} {:.0} alt {:.0} gear {:.2}",
        st.position[0], st.position[1], st.position[2], st.gear
    );
    assert!(reached_lineup, "taxied to the runway");
    assert!(airborne_at.is_some(), "took off");
    assert!(st.gear > 1.0, "gear up");
}

#[test]
fn lands_at_ramat_david() {
    let Some(inst) = install() else { return };
    let bases = Airbase::load_all(&std::fs::read(inst.join("iaf.ibx")).unwrap());
    let rd = bases.iter().find(|b| b.name == "David").unwrap().clone();
    let z = rd.lineup[2] as f64;
    // Home = a last waypoint 15 km west of the base at 1500 m; the jet starts 40 km further west.
    let home = Waypoint { x: rd.lineup[0] as f64 - 15000.0, y: rd.lineup[1] as f64, z: 1500.0, t: 0.0, action: 7 };
    let mut ac = jet(&inst, "F-16", [home.x - 40000.0, home.y + 5000.0, 2000.0], 90.0, true);
    let mut ap = Autopilot::new(Config::load(&inst));
    ap.bases = bases;
    ap.route = vec![home];
    ap.set_mode(&mut ac, 8);
    let mut touchdown = None;
    let mut t = 0;
    while t < 1500 && !ap.landed {
        fly(&mut ac, &mut ap, 1.0, z as f32);
        let st = ac.state();
        assert!(st.crashed.is_none(), "crashed ({:?}) at {:?}", st.crashed, st.position);
        if t % 60 == 0 {
            println!("{t}: {} pos {:.0} {:.0} {:.0} v {:.0}", ap.stage(), st.position[0], st.position[1], st.position[2], st.speed);
        }
        if touchdown.is_none() && st.on_ground {
            touchdown = Some((st.position, t));
        }
        t += 1;
    }
    let st = ac.state();
    println!("touchdown {touchdown:?}; landed {} after {t} s at {:.0} {:.0}, speed {:.1}", ap.landed, st.position[0], st.position[1], st.speed);
    let (p, _) = touchdown.expect("touched down");
    // On the runway: within 100 m of the 270° centreline through the lineup point, west of it.
    assert!((p[1] - rd.lineup[1] as f64).abs() < 100.0, "on the runway centreline ({:.0} m off)", p[1] - rd.lineup[1] as f64);
    assert!(ap.landed, "stopped on the runway");
    // Then taxis to a hangar and parks with the engine off.
    fly(&mut ac, &mut ap, 600.0, z as f32);
    let st = ac.state();
    let parked = rd.hangars.iter().any(|h| (st.position[0] - h.x as f64).hypot(st.position[1] - h.y as f64) < 100.0);
    println!("after taxi: {:.0} {:.0} speed {:.1} engine {}", st.position[0], st.position[1], st.speed, ac.engine_on);
    assert!(parked && !ac.engine_on, "parked at a hangar, engine off");
}


/// The player's autopilot (docs/autopilot.md) runs in FM mode 0 and returns the commands it posted.
fn fly_player(ac: &mut Aircraft, ap: &mut Autopilot, seconds: f64, ground: f32) -> Vec<iaf_flight::autopilot::Out> {
    let g = |_: f64, _: f64| ground;
    let mut outs = Vec::new();
    for _ in 0..(seconds / DT) as usize {
        ac.ground_height = ground;
        outs.push(ap.step(ac, &g));
        ac.step(DT);
    }
    outs
}

#[test]
fn player_level_mode_holds_heading_and_altitude() {
    let Some(inst) = install() else { return };
    // Engaged in a 20° bank, nose 5° up: LevelWingsPitch0, then KeepOrientation.
    let (p, e) = iaf_flight::load_with(&inst, "F-16", DataSet::Original).unwrap();
    let mut ac = Aircraft::start(
        p,
        e,
        Start {
            position: [0.0, 0.0, 3000.0],
            pitch: 5f32.to_radians(),
            roll: 20f32.to_radians(),
            heading: 0.0,
            velocity: [0.0, 250.0, 0.0],
            airborne: true,
            engine_on: true,
        },
    );
    ac.ground_height = 0.0;
    let mut c = ac.controls();
    c.throttle = 0.74;
    ac.set_controls(c);
    let mut ap = Autopilot::new(Config::load(&inst));
    ap.player_mode(&mut ac, 1, 0);
    assert!(ap.player_active());
    assert_eq!(ac.ai_mode, 0, "the FM keeps the player's rules");
    fly_player(&mut ac, &mut ap, 30.0, 0.0);
    let s0 = ac.state();
    println!("after 30 s: {} roll {:.1} pitch {:.1} hdg {:.1} alt {:.0}", ap.stage(), s0.roll.to_degrees(), s0.pitch.to_degrees(), s0.heading.to_degrees(), s0.position[2]);
    assert!(ap.stage().contains("keep orientation"), "levelled, then keeps orientation ({})", ap.stage());
    let outs = fly_player(&mut ac, &mut ap, 60.0, 0.0);
    let s1 = ac.state();
    println!("after 90 s: roll {:.1} hdg {:.1} alt {:.0} speed {:.0}", s1.roll.to_degrees(), s1.heading.to_degrees(), s1.position[2], s1.speed);
    assert!(s1.roll.to_degrees().abs() < 3.0, "wings level");
    assert!(wrap_deg(s1.heading.to_degrees() - s0.heading.to_degrees()).abs() < 2.0, "heading held");
    assert!((s1.position[2] - s0.position[2]).abs() < 150.0, "altitude held");
    assert!(outs.iter().all(|o| o.thr.is_none()), "no autothrottle in level mode");
    ap.player_mode(&mut ac, 0, 0);
    assert!(!ap.player_active());
}

fn wrap_deg(a: f32) -> f32 {
    (a + 540.0).rem_euclid(360.0) - 180.0
}

#[test]
fn player_nav_flies_to_the_selected_waypoint() {
    let Some(inst) = install() else { return };
    let mut ac = jet(&inst, "F-16", [0.0, 0.0, 3000.0], 90.0, true);
    let mut ap = Autopilot::new(Config::load(&inst));
    ap.route = vec![
        Waypoint { x: 0.0, y: 40000.0, z: 4000.0, t: 0.0, action: 3 },
        Waypoint { x: 40000.0, y: 40000.0, z: 4000.0, t: 0.0, action: 3 },
    ];
    ap.player_mode(&mut ac, 2, 0);
    let mut closest = f64::MAX;
    let mut thr = false;
    for _ in 0..300 {
        thr |= fly_player(&mut ac, &mut ap, 1.0, 0.0).iter().any(|o| o.thr.is_some());
        let p = ac.state().position;
        closest = closest.min(p[0].hypot(p[1] - 40000.0));
    }
    println!("closest {closest:.0} m, {}", ap.stage());
    assert!(closest < 1852.0, "reached waypoint 0 ({closest:.0} m)");
    assert!(thr, "NAV holds the throttle");
    assert_eq!(ap.stage(), "nav (passed)");
}

#[test]
fn player_approach_mission_312() {
    // Landing 312 "Eagle Baby": the player starts at 2000 m heading 270° east of Ramat David; the route's
    // only waypoint "Approach" (action 7) makes the NAV autopilot GoHomeCL: over the runway to the waypoint,
    // then the left-hand circuit (the mission's markers sit on its corners) and the final approach.
    let Some(inst) = install() else { return };
    let bases = Airbase::load_all(&std::fs::read(inst.join("iaf.ibx")).unwrap());
    let rd = bases.iter().find(|b| b.name == "David").unwrap().clone();
    let z = rd.lineup[2] as f64;
    let mut ac = jet(&inst, "F-16", [366755.0, 602361.0, 2000.0], 270.0, true);
    let mut c = ac.controls();
    c.throttle = 0.74;
    ac.set_controls(c);
    let mut ap = Autopilot::new(Config::load(&inst));
    ap.bases = bases;
    ap.route = vec![Waypoint { x: 351083.0, y: 602383.0, z: 1500.0, t: 60.0, action: 7 }];
    ap.player_mode(&mut ac, 2, 0);
    // The markers of landing.mis: crosswind end ("Point 2"), downwind end ("Point 3"), base end ("Point 4").
    let markers = [(351083.0, 596983.0), (363683.0, 596983.0), (363683.0, 602382.0)];
    let mut closest = [f64::MAX; 3];
    let (mut gear, mut final_at) = (false, None);
    for t in 0..600 {
        for o in fly_player(&mut ac, &mut ap, 1.0, z as f32) {
            gear |= o.gear == Some(true);
        }
        let st = ac.state();
        for (i, m) in markers.iter().enumerate() {
            closest[i] = closest[i].min((st.position[0] - m.0).hypot(st.position[1] - m.1));
        }
        if t % 30 == 0 {
            println!("{t}: {} pos {:.0} {:.0} {:.0} v {:.0}", ap.stage(), st.position[0], st.position[1], st.position[2], st.speed);
        }
        if ap.stage() == "landing step 13" {
            final_at = Some(st.position);
            break;
        }
        assert!(st.crashed.is_none(), "crashed ({:?}) at {:?} in {}", st.crashed, st.position, ap.stage());
    }
    println!("closest to the markers {closest:?}; final approach from {final_at:?}");
    assert!(closest.iter().all(|d| *d < 2500.0), "flew the circuit over the markers ({closest:?})");
    assert!(gear, "gear lowered on the downwind");
    let p = final_at.expect("reached the final approach");
    assert!((p[1] - rd.lineup[1] as f64).abs() < 100.0 && p[0] > rd.lineup[0] as f64, "on the extended centreline");
    assert!(!ap.landed, "no AI landed handler for the player");
}
