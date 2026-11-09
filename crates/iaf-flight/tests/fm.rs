//! The flight-model choice (`iaf_flight::fm`): the original game's data never reaches the Modern IAF 6-DoF, and its
//! flights through `Fm` are the original model's to the bit.

use std::path::PathBuf;

use iaf_flight::autopilot::Host;
use iaf_flight::fm::Fm;
use iaf_flight::{Aircraft, Controls, DataSet, Start, Vec3, data_set};

fn install() -> Option<PathBuf> {
    let p = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/install");
    p.join("resource/md/bd.ibx").is_file().then_some(p)
}

fn start() -> Start {
    Start {
        position: Vec3::new(0.0, 0.0, 3000.0),
        pitch: 0.0,
        roll: 0.0,
        heading: 0.5,
        velocity: Vec3::new(0.0, 180.0, 0.0),
        airborne: true,
        engine_on: true,
    }
}

#[test]
fn original_data_flies_the_original_model() {
    let Some(dir) = install() else {
        return println!("skipped: no assets/install (the original game's data)");
    };
    for set in [DataSet::Original, DataSet::Real] {
        for t in data_set::TYPES {
            let Ok((p, e)) = iaf_flight::load_with(&dir, t.name, set) else { continue };
            assert!(!p.model_6dof, "{} ({set:?}) asks for the 6-DoF", t.name);
            let mut fm = Fm::start(t.name, p.clone(), e.clone(), start());
            let mut ac = Aircraft::start(p, e, start());
            assert!(fm.original().is_some(), "{}", t.name);
            let c = Controls { stick_x: 0.3, stick_y: 0.4, throttle: 1.0, ..Controls::default() };
            fm.set_controls(c);
            ac.set_controls(c);
            for _ in 0..600 {
                fm.step(1.0 / 60.0);
                ac.step(1.0 / 60.0);
            }
            let (a, b) = (fm.state(), ac.state());
            assert_eq!(format!("{a:?}"), format!("{b:?}"), "{} ({set:?})", t.name);
        }
    }
}

#[test]
fn model_key_picks_the_sixdof() {
    // `Model = 6dof` in a section: the F-16 types fly the 6-DoF; without the key, the original. The choice is read
    // with the section (Params), so starting a flight reads no file.
    let ini =
        iaf_formats::ini::Ini::parse(b"[A]\nModel = 6dof\t; comment\nEmptyWeight = 19100\n[B]\nEmptyWeight = 37000\n");
    let (a, b) = (
        iaf_flight::Params::from_section(ini.section("A").unwrap()),
        iaf_flight::Params::from_section(ini.section("B").unwrap()),
    );
    assert!(a.model_6dof && !b.model_6dof);
    let env = || iaf_flight::Envelope::parse(b"");
    for name in ["F-16", "F-16I", "F-35I", "F-15I"] {
        assert!(matches!(Fm::start(name, a.clone(), env(), start()), Fm::SixDof(_)), "{name}");
        assert!(matches!(Fm::start(name, b.clone(), env(), start()), Fm::Original(_)), "{name}");
    }
    // A type the 6-DoF has no jet for keeps the original model even with the key.
    assert!(matches!(Fm::start("MIG29", a.clone(), env(), start()), Fm::Original(_)));
    let fm = Fm::start("F-16I", a, env(), start());
    assert!((fm.ap_view().speed - 180.0).abs() < 1.0);
}

#[test]
fn the_sims_own_data_flies_the_sixdof() {
    // iaf-sim fm's own sections (iaf-tools sim_fm0.rs) carry Model = 6dof: the sim's four jets fly the 6-DoF.
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    if !dir.join("resource/md/bd.ibx").is_file() {
        return println!("skipped: no assets/converted/own (iaf-sim fm)");
    }
    for name in ["F-16", "F-16I", "F-35I", "F-15I"] {
        let (p, e) = iaf_flight::load_with(&dir, name, DataSet::Original).unwrap();
        assert!(p.model_6dof, "{name}");
        assert!(matches!(Fm::start(name, p, e, start()), Fm::SixDof(_)), "{name}");
    }
}

#[test]
fn frame_cost_within_budget() {
    // The 6-DoF's budget (the orchestrator's decision of 2026-11-03, plan.md's C2 row): at most 20 µs per jet per
    // 1/60 s frame on this laptop, release build. The median of 9 runs of 2,000 frames each, so a busy machine's
    // spikes do not count; a debug build is not measured.
    if cfg!(debug_assertions) {
        return println!("skipped: a debug build (cargo test --release -p iaf-flight --test fm frame_cost)");
    }
    let ini = iaf_formats::ini::Ini::parse(b"[A]\nModel = 6dof\n");
    let p = iaf_flight::Params::from_section(ini.section("A").unwrap());
    let mut runs = Vec::new();
    for _ in 0..9 {
        let mut fm = Fm::start("F-16I", p.clone(), iaf_flight::Envelope::parse(b""), start());
        let t = std::time::Instant::now();
        for i in 0..2_000 {
            let c = Controls { stick_x: ((i as f32) * 0.01).sin() * 0.3, stick_y: 0.1, ..Controls::default() };
            fm.set_controls(c);
            fm.step(1.0 / 60.0);
        }
        runs.push(t.elapsed().as_secs_f64() * 1e6 / 2_000.0);
    }
    runs.sort_by(f64::total_cmp);
    let median = runs[runs.len() / 2];
    println!("6-DoF frame cost: median {median:.2} µs per 1/60 s frame (runs {:.2} … {:.2})", runs[0], runs[8]);
    assert!(median <= 20.0, "{median} µs");
}

#[test]
#[ignore = "a timing, not a check: cargo test --release -p iaf-flight --test fm -- --ignored --nocapture"]
fn frame_cost_sixdof_against_fm0() {
    // The flight model's cost per game frame (1/60 s) on the sim's own data: FM-0 (the original model on the own
    // section) against the 6-DoF, the Sufa at 350 kt, 10,000 ft, a gentle stick input. The 6-DoF's frame is two
    // RK4 steps, each four force evaluations and one control-system step.
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    if !dir.join("resource/md/bd.ibx").is_file() {
        return println!("skipped: no assets/converted/own");
    }
    let (p, e) = iaf_flight::load_with(&dir, "F-16I", DataSet::Original).unwrap();
    let st = Start { velocity: Vec3::new(0.0, 180.0, 0.0), ..start() };
    let mut fm0 = Aircraft::start(p.clone(), e.clone(), st);
    let mut six = Fm::start("F-16I", p, e, st);
    let n = 20_000;
    let time = |f: &mut dyn FnMut(usize)| {
        let t = std::time::Instant::now();
        for i in 0..n {
            f(i);
        }
        t.elapsed().as_secs_f64() * 1e6 / n as f64
    };
    let c = |i: usize| Controls { stick_x: ((i as f32) * 0.01).sin() * 0.3, stick_y: 0.1, ..Controls::default() };
    let a = time(&mut |i| {
        fm0.set_controls(c(i));
        fm0.step(1.0 / 60.0);
    });
    let b = time(&mut |i| {
        six.set_controls(c(i));
        six.step(1.0 / 60.0);
    });
    println!("per 1/60 s frame: FM-0 {a:.2} µs, 6-DoF {b:.2} µs");
}

#[test]
fn autopilot_flies_the_sixdof() {
    // The autopilot's stick is a linear g command (its ApView); on the 6-DoF the control system takes it as one.
    // The player's level mode holds the Sufa's height for 60 s; a held stick for 2 g gives 2 g (a flare is such a
    // command).
    use iaf_flight::autopilot::{Autopilot, Config};
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    if !dir.join("resource/md/bd.ibx").is_file() {
        return println!("skipped: no assets/converted/own");
    }
    let (p, e) = iaf_flight::load_with(&dir, "F-16I", DataSet::Original).unwrap();
    let mut fm = Fm::start("F-16I", p.clone(), e.clone(), start());
    let ini = iaf_formats::ini::Ini::parse(b"[Autopilot]\n");
    let mut ap = Autopilot::new(Config::from_section(ini.section("Autopilot").unwrap()));
    ap.player_mode(&mut fm, 1, 0);
    let h0 = fm.state().position.z;
    let ground = |_: f64, _: f64| 0.0f32;
    let mut worst: f64 = 0.0;
    for _ in 0..60 * 60 {
        ap.step(&mut fm, &ground);
        fm.step(1.0 / 60.0);
        worst = worst.max((fm.state().position.z - h0).abs());
    }
    println!("autopilot level on the 6-DoF: worst height error {worst:.1} m in 60 s");
    assert!(worst < 60.0, "{worst}");

    let mut fm = Fm::start("F-16I", p, e, start());
    fm.set_stores_trim(true);
    // The autopilot's map: stick = (g − 1) / (MaxG − 1) for a pull.
    let c = Controls { stick_y: 1.0 / 8.0, ..fm.controls() };
    for _ in 0..4 * 60 {
        fm.set_controls(c);
        fm.step(1.0 / 60.0);
    }
    let g = fm.state().g;
    println!("autopilot stick for 2 g: {g:.2} g");
    assert!((g - 2.0).abs() < 0.15, "{g}");
}
