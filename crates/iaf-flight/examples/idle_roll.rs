//! Idle ground roll: each jet left at idle on the runway with no brakes, its speed after 30 s / 1 / 2 / 10 min, for
//! the Original and Real flight data, with or without the better-physics `ground_idle` option
//! (docs/flight-model.md §10). Needs the extracted game data in assets/install.
//!   cargo run --release -p iaf-flight --example idle_roll [-- off]     (off: the original, without ground_idle)
use iaf_flight::{data_set::DataSet, Aircraft, Controls, Start, Vec3};

fn main() {
    let install = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../assets/install");
    let ground_idle = std::env::args().nth(1).as_deref() != Some("off");
    println!("ground_idle {}", if ground_idle { "on" } else { "off" });
    for set in [DataSet::Original, DataSet::Real] {
        for jet in ["F-4", "F-15", "F-16", "Mirage", "Kfir", "Lavi", "F-35I"] {
            let Ok((p, e)) = iaf_flight::load_with(&install, jet, set) else {
                println!("{jet}: no data");
                continue;
            };
            let st = Start { position: Vec3::new(0.0, 0.0, 10.0), pitch: 0.0, roll: 0.0, heading: 0.0, velocity: Vec3::ZERO, airborne: false, engine_on: true };
            let mut a = Aircraft::start(p, e, st);
            a.better.ground_idle = ground_idle;
            a.ground_height = 10.0;
            a.set_controls(Controls { throttle: 0.0, flaps: 0.0, gear_down: true, brakes: false, ..Default::default() });
            let mut out = String::new();
            for s in 1..=600 {
                for _ in 0..100 {
                    a.step(0.01);
                }
                if [30, 60, 120, 600].contains(&s) {
                    out += &format!("{s}s {:.0} kt  ", a.state().speed / 0.514444);
                }
            }
            println!("{set:?} {jet:7} {:.0} kg: {out}", a.state().mass_kg);
        }
    }
}
