//! An AI jet's landing on the 6-DoF over ground shaped like Nevatim's (docs/ai.md §18.4): the ground under the final
//! stands up to 12 m above the runway and the runway falls 0.8 % past the lineup. A MiG-29A sent home from 15 km out
//! lands without a crash, its sink at the touchdown under 3 m/s. Skips with a message when `assets/converted/own` is not
//! built.

use std::path::PathBuf;

use iaf_flight::airbase::Airbase;
use iaf_flight::autopilot::{self, Autopilot, Config, Waypoint};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

#[test]
fn mig29_lands_over_a_rise_onto_a_falling_runway() {
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm, airbases)") };
    autopilot::reset_hangars();
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let nb = bases.iter().find(|b| b.name == "Nevatim").unwrap().clone();
    let l = Vec3::new(nb.lineup[0] as f64, nb.lineup[1] as f64, nb.lineup[2] as f64);
    let (s, c) = (nb.runway_deg as f64).to_radians().sin_cos();
    let at = |along: f64, up: f64| Vec3::new(l[0] + along * s, l[1] + along * c, l[2] + up);
    // The ground along the runway's line: a rise of 12 m from 2.5 km to 0.5 km short of the lineup, the runway
    // falling 0.8 % past it.
    let ground = move |x: f64, y: f64| {
        let along = (x - l[0]) * s + (y - l[1]) * c;
        let rise = if (-2500.0..-500.0).contains(&along) {
            12.0 * (std::f64::consts::PI * (along + 500.0) / -2000.0).sin()
        } else {
            0.0
        };
        (l[2] + rise - 0.008 * along.max(0.0)) as f32
    };
    let (prm, env) = iaf_flight::load_with(&dir, "MiG-29A", DataSet::Original).unwrap();
    let start = at(-20_000.0, 1500.0);
    let h = (nb.runway_deg as f64).to_radians();
    let st = Start {
        position: start,
        pitch: 0.0,
        roll: 0.0,
        heading: h as f32,
        velocity: Vec3::new(h.sin() * 180.0, h.cos() * 180.0, 0.0),
        airborne: true,
        engine_on: true,
    };
    let mut fm = Fm::start("MiG-29A", prm, env, st);
    let mut ap = Autopilot::new(Config::load(&dir));
    ap.bases = bases.clone();
    let wp = at(-15_000.0, 1500.0);
    ap.route = vec![Waypoint { x: wp[0], y: wp[1], z: wp[2], t: 0.0, action: 7 }];
    ap.set_mode(&mut fm, 8);
    let mut t = 0.0;
    let mut touchdown = None;
    while t < 900.0 && !(ap.landed && fm.state().speed < 1.0) {
        let p = fm.state().position;
        fm.set_ground_height(ground(p.x, p.y));
        ap.step(&mut fm, &ground);
        let vz = fm.state().velocity[2] as f64;
        fm.step(DT);
        t += DT;
        let s = fm.state();
        assert!(s.crashed.is_none(), "crashed ({:?}) in {} at {:.0} s", s.crashed, ap.stage(), t);
        if s.on_ground && touchdown.is_none() {
            touchdown = Some((-vz, s.position.distance(l)));
        }
    }
    println!("touchdown (sink m/s, m from the lineup) {touchdown:?}; {} at {t:.0} s", ap.stage());
    let (sink, _) = touchdown.expect("touched down");
    assert!(sink < 3.0, "sink at the touchdown {sink:.1} m/s");
    assert!(ap.landed, "landed");
}
