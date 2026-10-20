//! World scale Real 1:1, the base move (docs/world-scale.md §3.3) on the original data: every base's main runway on
//! its real one, and the autopilot's take-off and landing at the moved Ramat David and Ramon. Needs `assets/install`
//! and `assets/converted/terrain/airbases.json`.

use std::path::PathBuf;

use iaf_flight::airbase::Airbase;
use iaf_flight::autopilot::{Autopilot, Config, Waypoint};
use iaf_flight::base_move::{BaseMoves, GameBase, real_runways};
use iaf_flight::{Aircraft, DataSet, Start, Vec3};
use iaf_formats::terrain_types::{RUNWAY, TerrainTypes};

fn assets() -> Option<PathBuf> {
    let p = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets");
    (p.join("install/resource/md").is_dir() && p.join("converted/terrain/airbases.json").is_file()).then_some(p)
}

/// The game bases (iaf.ibx + airbases.json's runways) and their moves.
fn load(a: &std::path::Path) -> (Vec<Airbase>, BaseMoves) {
    let ibx = Airbase::load_all(&std::fs::read(a.join("install/iaf.ibx")).unwrap());
    let j: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(a.join("converted/terrain/airbases.json")).unwrap()).unwrap();
    let pt = |v: &serde_json::Value| [v[0].as_f64().unwrap(), v[1].as_f64().unwrap()];
    let games: Vec<GameBase> = ibx
        .iter()
        .map(|b| {
            let jb = j["bases"].as_array().unwrap().iter().find(|x| x["name"] == b.name.as_str()).unwrap();
            let rw = jb["runways"].as_array().unwrap().iter().map(|r| [pt(&r["ends"][0]), pt(&r["ends"][1])]).collect();
            GameBase::new(b, rw)
        })
        .collect();
    (ibx, BaseMoves::new(&games))
}

#[test]
fn every_base_sits_on_its_real_runway() {
    let Some(a) = assets() else { return };
    let (ibx, ms) = load(&a);
    assert_eq!(ms.bases.len(), 10);
    let real = real_runways();
    println!("| base | turn | k | real runway | moved by |");
    for m in &ms.bases {
        println!(
            "| {} | {:+.1}° | {:.2} | {:.0}° {:.0} × {:.0} m | {:.1} km |",
            m.name,
            m.turn,
            m.k,
            m.heading,
            m.real_len,
            m.width,
            m.offset() / 1000.0
        );
        // The moved runway's ends are a real runway's ends.
        let a0 = m.map(m.game_c).unwrap().p;
        let ok = real.iter().filter(|r| r.base == m.name).any(|r| {
            [r.a, r.b].iter().any(|e| (e[0] - a0[0]).hypot(e[1] - a0[1]) < 1.0)
                && ((r.b[0] - r.a[0]).hypot(r.b[1] - r.a[1]) - m.real_len).abs() < 1.0
        });
        assert!(ok, "{}: on a real runway", m.name);
        assert!((0.6..1.4).contains(&m.k), "{} k {}", m.name, m.k);
        let mut b = ibx.iter().find(|b| b.name == m.name).unwrap().clone();
        let game_rn = b.runway_deg;
        m.map_airbase(&mut b);
        assert!(((b.runway_deg - game_rn - m.turn as f32).rem_euclid(360.0) + 0.5).rem_euclid(360.0) < 1.0);
    }
    let get = |n: &str| ms.get(n).unwrap();
    assert!(get("David").zone_b > 0.0 && get("Ramon").zone_b > 0.0 && get("Ryak").zone_b > 0.0);
    assert!(get("Damescuss").zone_b == 0.0 && get("Aman").zone_b == 0.0 && get("Kuzeir").zone_b == 0.0);
}

/// The moved base's runway leaves: the original terraintype.dat through the move.
#[test]
fn the_moved_lineup_is_on_runway_ground() {
    let Some(a) = assets() else { return };
    let (mut ibx, ms) = load(&a);
    let tt = TerrainTypes::parse(&std::fs::read(a.join("install/terraintype.dat")).unwrap()).unwrap();
    let old: Vec<Airbase> = ibx.clone();
    ms.map_airbases(&mut ibx);
    for (b, o) in ibx.iter().zip(&old) {
        let s = |p: [f32; 3]| ms.surface([p[0] as f64, p[1] as f64], |x, y| tt.at(x, y));
        // Along the runway from the lineup: 1 km of runway ground (Inshas, Ryak and Aman have no runway leaves).
        if tt.at(o.lineup[0] as f64, o.lineup[1] as f64) & RUNWAY == 0 {
            continue;
        }
        let d = b.runway_deg.to_radians();
        for t in [0.0f32, 300.0, 1000.0] {
            let p = [b.lineup[0] + t * d.sin(), b.lineup[1] + t * d.cos(), 0.0];
            assert_eq!(s(p) & RUNWAY, RUNWAY, "{} at {t} m", b.name);
        }
        if ms.get(&b.name).unwrap().offset() > 5000.0 {
            assert_eq!(s(o.lineup) & RUNWAY, 0, "{}: the old lineup is rough ground", b.name);
        }
    }
}

const DT: f64 = 1.0 / 60.0;
const F16_CLEARANCE_REAL: f32 = 1.691;

fn jet(a: &std::path::Path, pos: Vec3, heading_deg: f32, airborne: bool) -> Aircraft {
    let (p, e) = iaf_flight::load_with(&a.join("install"), "F-16", DataSet::Original).unwrap();
    let h = heading_deg.to_radians();
    let v = if airborne { 282.84 } else { 0.0 };
    let st = Start {
        position: pos,
        pitch: 0.0,
        roll: 0.0,
        heading: h,
        velocity: Vec3::new((v * h.sin()) as f64, (v * h.cos()) as f64, 0.0),
        airborne,
        engine_on: true,
    };
    let mut ac = Aircraft::start(p, e, st);
    ac.gear_clearance = F16_CLEARANCE_REAL;
    ac
}

/// Flies with flat ground at `z` and the moved surface flags under the jet (the player's rough-ground rule on).
fn fly(ac: &mut Aircraft, ap: &mut Autopilot, seconds: f64, z: f32, surf: &dyn Fn(f64, f64) -> i32) {
    let g = |_: f64, _: f64| z;
    for _ in 0..(seconds / DT) as usize {
        ac.ground_height = z;
        let p = ac.state().position;
        ac.ground_flags = Some(surf(p[0], p[1]) as u32);
        ap.step(ac, &g);
        ac.step(DT);
    }
}

fn setup(name: &str, elev: f64) -> Option<(PathBuf, Airbase, Vec<Airbase>, BaseMoves, TerrainTypes)> {
    let a = assets()?;
    let (mut ibx, mut ms) = load(&a);
    for m in &mut ms.bases {
        m.elev = elev;
    }
    ms.map_airbases(&mut ibx);
    let tt = TerrainTypes::parse(&std::fs::read(a.join("install/terraintype.dat")).unwrap()).unwrap();
    let b = ibx.iter().find(|b| b.name == name).unwrap().clone();
    Some((a, b, ibx, ms, tt))
}

fn take_off(name: &str, elev: f64) {
    let Some((a, b, ibx, ms, tt)) = setup(name, elev) else { return };
    let surf = |x: f64, y: f64| ms.surface([x, y], |x, y| tt.at(x, y));
    let h = b.hangars[0];
    let z = b.lineup[2];
    let mut ac = jet(&a, Vec3::new(h.x as f64, h.y as f64, (z + F16_CLEARANCE_REAL) as f64), h.hdg.to_degrees(), false);
    let mut ap = Autopilot::new(Config::load(&a.join("install")));
    ap.bases = ibx;
    let d = b.runway_deg.to_radians();
    let wp = [b.lineup[0] as f64 + 15000.0 * d.sin() as f64, b.lineup[1] as f64 + 15000.0 * d.cos() as f64];
    ap.route = vec![Waypoint { x: wp[0], y: wp[1], z: 1500.0, t: 20.0, action: 2 }];
    ap.set_mode(&mut ac, 9);
    let (mut lined_up, mut airborne) = (false, false);
    for _ in 0..400 {
        fly(&mut ac, &mut ap, 1.0, z, &surf);
        let st = ac.state();
        assert!(st.crashed.is_none(), "{name}: crashed ({:?}) at {:?}", st.crashed, st.position);
        lined_up |= (st.position[0] - b.lineup[0] as f64).hypot(st.position[1] - b.lineup[1] as f64) < 150.0;
        airborne |= st.position[2] > z as f64 + 100.0;
    }
    assert!(lined_up && airborne, "{name}: taxied to the moved runway ({lined_up}) and took off ({airborne})");
}

fn land(name: &str, elev: f64) {
    let Some((a, b, ibx, ms, tt)) = setup(name, elev) else { return };
    let surf = |x: f64, y: f64| ms.surface([x, y], |x, y| tt.at(x, y));
    let m = ms.get(name).unwrap().clone();
    let z = b.lineup[2];
    let d = b.runway_deg.to_radians() as f64;
    // Home 15 km before the runway at 1500 m; the jet starts 40 km further out.
    let (lx, ly) = (b.lineup[0] as f64, b.lineup[1] as f64);
    let home =
        Waypoint { x: lx - 15000.0 * d.sin(), y: ly - 15000.0 * d.cos(), z: 1500.0 + z as f64, t: 0.0, action: 7 };
    let mut ac =
        jet(&a, Vec3::new(lx - 55000.0 * d.sin(), ly - 55000.0 * d.cos(), 2000.0 + z as f64), b.runway_deg, true);
    let mut ap = Autopilot::new(Config::load(&a.join("install")));
    ap.bases = ibx;
    ap.route = vec![home];
    ap.set_mode(&mut ac, 8);
    let mut touchdown = None;
    let mut t = 0;
    while t < 1500 && !ap.landed {
        fly(&mut ac, &mut ap, 1.0, z, &surf);
        let st = ac.state();
        assert!(st.crashed.is_none(), "{name}: crashed ({:?}) at {:?} ({})", st.crashed, st.position, ap.stage());
        if touchdown.is_none() && st.on_ground {
            touchdown = Some(st.position);
        }
        t += 1;
    }
    let p = touchdown.expect("touched down");
    // On the moved base's runway ground (the original's leaves through the move), on the real runway's length. The
    // original pattern's base turn can leave the final approach tens of metres off the centreline (any heading;
    // docs/world-scale.md §4.1 risks), so the side offset is printed, not bound to the real width.
    let q = [p[0] - m.real_c[0], p[1] - m.real_c[1]];
    let (along, across) = (q[0] * m.real_d[0] + q[1] * m.real_d[1], q[0] * m.real_d[1] - q[1] * m.real_d[0]);
    println!("{name}: touchdown {along:.0} m along, {across:.1} m across; landed {} after {t} s", ap.landed);
    assert!(along > 0.0 && along < m.real_len, "{name}: touchdown along the runway ({along:.0} m)");
    assert_eq!(surf(p[0], p[1]) & RUNWAY, RUNWAY, "{name}: touchdown on runway ground");
    let st = ac.state();
    assert_eq!(surf(st.position[0], st.position[1]) & RUNWAY, RUNWAY, "{name}: stopped on runway ground");
    assert!(ap.landed, "{name}: stopped on the runway");
    fly(&mut ac, &mut ap, 600.0, z, &surf);
    let st = ac.state();
    let parked = b.hangars.iter().any(|h| (st.position[0] - h.x as f64).hypot(st.position[1] - h.y as f64) < 100.0);
    assert!(parked && !ac.engine_on, "{name}: parked at a moved hangar, engine off");
}

#[test]
fn takes_off_from_the_moved_ramat_david() {
    take_off("David", 52.0);
}

#[test]
fn lands_at_the_moved_ramat_david() {
    land("David", 52.0);
}

#[test]
fn takes_off_from_the_moved_ramon() {
    take_off("Ramon", 480.0);
}

#[test]
fn lands_at_the_moved_ramon() {
    land("Ramon", 480.0);
}
