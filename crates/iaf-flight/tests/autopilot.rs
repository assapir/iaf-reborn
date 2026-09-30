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

