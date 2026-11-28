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

#[test]
fn player_autopilot_flies_the_sims_three_jets() {
    // The player's autopilot (docs/autopilot.md) on the Barak, the Sufa and the Adir, their own data on the 6-DoF:
    // level holds the height, NAV flies to a waypoint 90° off the nose and 1,000 m higher, and NAV to a landing
    // waypoint (GoHomeCL) lands at Ramat David (the own iaf.ibx) with the flare the sim turns on, under the game's
    // rule that the autopilot's landing keeps the original's limits (terrain_view.gd `set_ap_landing`).
    use iaf_flight::airbase::Airbase;
    use iaf_flight::autopilot::{Autopilot, Config, Waypoint};
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    if !dir.join("resource/md/bd.ibx").is_file() || !dir.join("iaf.ibx").is_file() {
        return println!("skipped: no assets/converted/own");
    }
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    let rd = bases.iter().find(|b| b.name == "David").unwrap().clone();
    let cfg = || Config::from_section(iaf_formats::ini::Ini::parse(b"[Autopilot]\n").section("Autopilot").unwrap());
    for name in ["F-16", "F-16I", "F-35I"] {
        let (p, e) = iaf_flight::load_with(&dir, name, DataSet::Original).unwrap();
        let ground = |_: f64, _: f64| 0.0f32;
        // Level.
        let mut fm = Fm::start(name, p.clone(), e.clone(), start());
        let mut ap = Autopilot::new(cfg());
        ap.player_mode(&mut fm, 1, 0);
        let h0 = fm.state().position.z;
        let mut worst: f64 = 0.0;
        for _ in 0..60 * 60 {
            ap.step(&mut fm, &ground);
            fm.step(1.0 / 60.0);
            worst = worst.max((fm.state().position.z - h0).abs());
        }
        // NAV: 20 km east (the start heads north), 1,000 m up.
        let mut fm = Fm::start(name, p.clone(), e.clone(), start());
        let mut ap = Autopilot::new(cfg());
        ap.route = vec![Waypoint { x: 20000.0, y: 5000.0, z: 4000.0, t: 0.0, action: 3 }];
        ap.player_mode(&mut fm, 2, 0);
        let mut closest = f64::MAX;
        let mut alt_err = f64::MAX;
        for _ in 0..240 * 60 {
            ap.step(&mut fm, &ground);
            fm.step(1.0 / 60.0);
            let s = fm.state();
            let d = (s.position.x - 20000.0).hypot(s.position.y - 5000.0);
            if d < closest {
                closest = d;
                alt_err = (s.position.z - 4000.0).abs();
            }
        }
        // NAV to a landing waypoint 15 km west of Ramat David's lineup, from 40 km further west.
        let z = rd.lineup[2] as f64;
        let home = Waypoint { x: rd.lineup[0] as f64 - 15000.0, y: rd.lineup[1] as f64, z: 1500.0, t: 0.0, action: 7 };
        let st = Start {
            position: Vec3::new(home.x - 40000.0, home.y + 5000.0, 2000.0),
            heading: 90f32.to_radians(),
            velocity: Vec3::new(180.0, 0.0, 0.0),
            ..start()
        };
        let mut fm = Fm::start(name, p.clone(), e.clone(), st);
        let mut ap = Autopilot::new(cfg());
        ap.bases = bases.clone();
        ap.route = vec![home];
        ap.player_flare = true;
        ap.player_mode(&mut fm, 2, 0);
        let mut touchdown = None;
        let mut sink: f32 = 0.0;
        let mut stopped = false;
        for _ in 0..1500 * 60 {
            let landing = ap.stage().starts_with("landing");
            if let Fm::SixDof(s) = &mut fm {
                s.set_ground_height(z as f32);
                s.ap_landing = landing;
            }
            ap.step(&mut fm, &|_: f64, _: f64| z as f32);
            fm.step(1.0 / 60.0);
            let s = fm.state();
            assert!(s.crashed.is_none(), "{name}: crashed ({:?}) at {:?} in {}", s.crashed, s.position, ap.stage());
            if touchdown.is_none() {
                if s.on_ground {
                    touchdown = Some(s.position);
                } else {
                    sink = -s.velocity[2];
                }
            } else if s.speed < 2.0 {
                stopped = true;
                break;
            }
        }
        println!(
            "{name}: level worst {worst:.1} m; NAV closest {closest:.0} m, alt error {alt_err:.0} m; touchdown {touchdown:?} \
             sink {sink:.2} m/s, stopped {stopped}"
        );
        assert!(worst < 10.0, "{name}: level {worst}");
        assert!(closest < 1852.0 && alt_err < 200.0, "{name}: NAV {closest} {alt_err}");
        let p = touchdown.unwrap_or_else(|| panic!("{name}: touched down"));
        assert!((p.y - rd.lineup[1] as f64).abs() < 30.0, "{name}: centreline ({:.0} m)", p.y - rd.lineup[1] as f64);
        assert!(stopped, "{name}: stopped on the runway");
        // The real final (`autopilot::REAL_FINAL`: 3° at 13° α, ~145 kt) and its 15 m flare: about 2 m/s (2026-11-16:
        // 2.6 / 2.5 / 2.0). The original's 6° final at 185–195 kt touched at 9.6 / 4.3 / 6.8 m/s.
        assert!(sink < 3.0, "{name}: touchdown sink {sink}");
    }
}

/// The own data's four jets, or None with a note when the sim's data is not built.
fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

#[test]
fn sixdof_g_follows_a_command() {
    // The lag the circuit's path law is made for (`autopilot::PATH_TAU` = twice the slowest): the time the 6-DoF's g
    // takes to reach 63 % of a 0.3 g step of the autopilot's g command, at full internal fuel.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own") };
    for name in ["F-16", "F-16I", "F-35I", "F-15I"] {
        let (p, e) = iaf_flight::load_with(&dir, name, DataSet::Original).unwrap();
        for (kt, gear) in [(220.0, true), (300.0, false), (450.0, false)] {
            let st =
                Start { velocity: Vec3::new(0.0, kt * 0.5144, 0.0), position: Vec3::new(0.0, 0.0, 600.0), ..start() };
            let mut fm = Fm::start(name, p.clone(), e.clone(), st);
            fm.set_stores_trim(true);
            let mut c = Controls { gear_down: gear, ..fm.controls() };
            let fly = |c: Controls, fm: &mut Fm, until: &dyn Fn(f32) -> bool| {
                (0..600).find(|_| {
                    fm.set_controls(c);
                    fm.step(1.0 / 60.0);
                    until(fm.state().g)
                })
            };
            fly(c, &mut fm, &|_| false);
            let g0 = fm.state().g;
            c.stick_y = 0.3 / (fm.ap_view().max_g - 1.0);
            let t63 = fly(c, &mut fm, &|g| g - g0 >= 0.63 * 0.3).map(|i| i as f32 / 60.0);
            println!("{name} {kt} kt, gear down {gear}: 63 % of the g step in {t63:?} s");
            assert!(t63.is_some_and(|t| (0.5..=2.5).contains(&t)), "{name} {kt}: {t63:?}");
        }
    }
}

#[test]
fn landing_circuit_on_the_sixdof() {
    // The autopilot's landing circuit (NAV to a landing waypoint, GoHomeCL) on the 6-DoF's four jets at Ramat David
    // (the own iaf.ibx, and the 1998 game's with its three modern jets), calm: at a landing weight (30 % of the
    // internal fuel) from 55 km out at 2,000 m, at full internal fuel from 3 km out at 300 m, and at full fuel with 3 t
    // of stores (drag index 60 a side). Each lands on the runway and stops on it, touches at less than the
    // gear's design sink of 10 ft/s (3.05 m/s, docs/damage.md §5.2), no faster than its final's speed (13° α at its
    // weight) and under the 15° of the tail strike (`aircraft::landing_limits`). Before: 12 of
    // a 24-flight sweep (these weights, entries from 55 km at 2,000 m and 20 km at 300 m) crashed (the Sufa at full
    // fuel on the final at 22 m/s, the Adir in CH1's 80° bank in a deep stall at α 43–50°).
    use iaf_flight::airbase::Airbase;
    use iaf_flight::autopilot::{Autopilot, Config, Waypoint};
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own") };
    // Modern IAF: its own bases and the default laws; runway 09/27 is 2,934 m by 44 m (`data/real_runways.csv`) and
    // the lineup stands 100 m past its start (`sim_bases::LINEUP_IN_M`). The 1998 game with Physics "Flight model" on
    // 6-DoF (docs/deviations.md §2): the player's modern jet on the same 6-DoF data, the install's bases and
    // [Autopilot]; its runway 27 starts 672 m behind the lineup and ends 3,592 m past it (`autopilot.rs` RD_ENDS).
    // Each world: (name, iaf.ibx, the laws, the jets, the runway's start and end from the lineup in m).
    let all = &["F-16", "F-16I", "F-35I", "F-15I"][..];
    let mut worlds = vec![("Modern IAF", dir.join("iaf.ibx"), Config::default(), all, (-100.0, 2834.0))];
    match install() {
        Some(i) => worlds.push(("1998", i.join("iaf.ibx"), Config::load(&i), &all[1..], (-672.0, 3592.0))),
        None => println!("the 1998 game's bases skipped: no assets/install"),
    }
    for (world, ibx, cfg, names, runway) in worlds {
        let bases = Airbase::load_all(&std::fs::read(ibx).unwrap());
        let rd = bases.iter().find(|b| b.name == "David").unwrap().clone();
        let z = rd.lineup[2] as f64;
        let (rs, rc) = (rd.runway_deg as f64).to_radians().sin_cos();
        // (fuel share, stores kg, their ΔCD a side, start height above the field m, speed m/s, km west of the waypoint)
        let cases = [
            (0.3, 0.0, 0.0, 2000.0, 180.0, 55.0),
            (1.0, 0.0, 0.0, 300.0, 130.0, 3.0),
            (1.0, 3000.0, 0.006, 2000.0, 180.0, 55.0),
        ];
        for name in names {
            let (p, e) = iaf_flight::load_with(&dir, name, DataSet::Original).unwrap();
            let name = &format!("{world} {name}");
            for (ci, &(fuel, stores, dcd, h0, v0, west)) in cases.iter().enumerate() {
                let home =
                    Waypoint { x: rd.lineup[0] as f64 - 15000.0, y: rd.lineup[1] as f64, z: z + h0, t: 0.0, action: 7 };
                let st = Start {
                    position: Vec3::new(home.x - west * 1000.0, home.y + 5000.0, z + h0),
                    heading: 90f32.to_radians(),
                    velocity: Vec3::new(v0, 0.0, 0.0),
                    ..start()
                };
                let mut fm = Fm::start(name.rsplit(' ').next().unwrap(), p.clone(), e.clone(), st);
                let Fm::SixDof(s) = &mut fm else { panic!("{name}: the 6-DoF") };
                s.set_fuel(s.fuel_capacity_kg() * fuel);
                s.set_stores(stores, dcd, dcd);
                let mass = s.mass();
                let mut ap = Autopilot::new(cfg);
                ap.bases = bases.clone();
                ap.route = vec![home];
                ap.player_flare = true;
                ap.player_mode(&mut fm, 2, 0);
                // At the touchdown: (speed kt, sink m/s, pitch deg, m along the runway from the lineup); the final's speed.
                let (mut last, mut touch, mut final_kt, mut stop) = ((0.0, 0.0, 0.0), None, 0.0, None);
                let on_runway = |p: Vec3| {
                    let (dx, dy) = (p.x - rd.lineup[0] as f64, p.y - rd.lineup[1] as f64);
                    (dx * rs + dy * rc, dx * rc - dy * rs)
                };
                for _ in 0..1500 * 60 {
                    let landing = ap.stage().starts_with("landing");
                    if let Fm::SixDof(s) = &mut fm {
                        s.set_ground_height(z as f32);
                        s.ap_landing = landing;
                    }
                    ap.step(&mut fm, &|_: f64, _: f64| z as f32);
                    fm.step(1.0 / 60.0);
                    let s = fm.state();
                    assert!(s.crashed.is_none(), "{name} case {ci}: crashed ({:?}) in {}", s.crashed, ap.stage());
                    if touch.is_none() && s.on_ground {
                        touch = Some((last.0, last.1, last.2, on_runway(s.position).0));
                    } else if touch.is_none() {
                        last = (s.speed * 1.943_844, -s.velocity[2], s.pitch.to_degrees());
                        final_kt = fm.ap_view().final_speed.map_or(final_kt, |v| v * 1.943_844);
                    } else if s.speed < 2.0 {
                        stop = Some(on_runway(s.position));
                        break;
                    }
                }
                let (kt, sink, pitch, at) = touch.unwrap_or_else(|| panic!("{name} case {ci}: touched down"));
                let (along, cross) = stop.unwrap_or_else(|| panic!("{name} case {ci}: stopped"));
                println!(
                    "{name} case {ci} ({mass:.0} kg): touchdown {kt:.0} kt (final {final_kt:.0}), sink {sink:.2} m/s, pitch \
                 {pitch:.1}°, {at:.0} m past the lineup; stopped at {along:.0} m, {cross:.1} m off the centreline"
                );
                // Case 2 too (2026-11-19): the flare's sum wound up over the 6-DoF's g lag, and the 1998 game's Adir
                // with 3 t of stores ballooned 2.6 m and touched at 4.05 m/s (`autopilot::FLARE_LAG_6DOF`).
                assert!(sink < 3.05, "{name} case {ci}: sink {sink}");
                assert!(kt <= final_kt, "{name} case {ci}: {kt} kt, final {final_kt}");
                // Every case since 2026-11-25: the heavier final's lower α and the flare's pitch ceiling (`autopilot::FLARE_PITCH_MAX`,
                // `Jet::final_alpha_at`); above the landing weights the flare had ended at 15–19°.
                assert!(pitch < 15.0, "{name} case {ci}: pitch {pitch}");
                let on = at > runway.0 && along < runway.1 && cross.abs() < 22.0;
                assert!(on, "{name} case {ci}: {at} {along} {cross}");
            }
        }
    }
}

#[test]
fn overhead_pattern_on_the_sixdof() {
    // Modern IAF's instructor (`Autopilot::overhead`, modern-iaf/docs/training.md "The instructor flies"): the overhead
    // pattern on the 6-DoF, from 12 km out on the centreline at 1,500 ft and 300 kt, the landing waypoint at the
    // initial point 5 NM out. The player's autopilot flies the Barak at Ramat David and the Sufa at Ramon (the F-16
    // instructor's demonstration); the AI flies the Adir at Nevatim (the F-35I instructor's lead). Each flies the
    // steps in order: the initial on the centreline, the break over the touchdown zone, the downwind about 1 NM to the
    // left with the gear down under 300 kt, descending to the perch, the base turn down to the final 1–3.5 km out under
    // 250 m, flies the final at the jet's on-speed α ± 1°, then lands on the runway and stops on it, touching at less
    // than the gear's 3.05 m/s.
    use iaf_flight::airbase::Airbase;
    use iaf_flight::autopilot::{Autopilot, Config, OVERHEAD, Waypoint};
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own") };
    let bases = Airbase::load_all(&std::fs::read(dir.join("iaf.ibx")).unwrap());
    // (jet, base, the player's autopilot, fuel share, stores kg and their ΔCD a side)
    let jets = [
        ("F-16", "David", true, 0.5, 0.0, 0.0),
        ("F-16I", "Ramon", true, 0.5, 0.0, 0.0),
        ("F-16I", "Ramon", true, 1.0, 2000.0, 0.004),
        ("F-35I", "Nevatim", false, 0.5, 0.0, 0.0),
        ("F-35I", "Nevatim", false, 1.0, 0.0, 0.0),
    ];
    for (name, base, player, fuel, stores, dcd) in jets {
        let b = bases.iter().find(|b| b.name == base).unwrap().clone();
        let z = b.lineup[2] as f64;
        let (rs, rc) = (b.runway_deg as f64).to_radians().sin_cos();
        let at =
            |along: f64, up: f64| Vec3::new(b.lineup[0] as f64 + along * rs, b.lineup[1] as f64 + along * rc, z + up);
        // (m along the runway from the lineup, m right of the centreline, m above the field)
        let frame = |p: Vec3| {
            let (dx, dy) = (p.x - b.lineup[0] as f64, p.y - b.lineup[1] as f64);
            (dx * rs + dy * rc, dx * rc - dy * rs, p.z - z)
        };
        let i = at(-OVERHEAD.initial as f64, OVERHEAD.height);
        let st = Start {
            position: at(-12_000.0, OVERHEAD.height),
            heading: (b.runway_deg as f32).to_radians(),
            velocity: Vec3::new(rs * 154.3, rc * 154.3, 0.0),
            ..start()
        };
        let (p, e) = iaf_flight::load_with(&dir, name, DataSet::Original).unwrap();
        let mut fm = Fm::start(name, p, e, st);
        if let Fm::SixDof(s) = &mut fm {
            s.set_fuel(s.fuel_capacity_kg() * fuel);
            s.set_stores(stores, dcd, dcd);
        }
        let mut ap = Autopilot::new(Config::default());
        ap.bases = vec![b.clone()];
        ap.route = vec![Waypoint { x: i.x, y: i.y, z: i.z, t: 0.0, action: 7 }];
        ap.overhead = true;
        if player {
            ap.player_flare = true;
            ap.player_mode(&mut fm, 2, 0);
        } else {
            ap.set_mode(&mut fm, 8);
        }
        let (mut steps, mut entered) = (Vec::new(), std::collections::HashMap::new());
        let (mut last_sink, mut touch, mut stop, mut down_left) = (0.0, None, None, f64::MAX);
        let mut gear_kt = f32::NAN;
        // The final's indicated α, as the lesson's `final_aoa_error` measures it (on final with the gear down, 50 to
        // 1,000 ft up), and the jet's on-speed α at its mass (`Jet::final_alpha_at`), deg.
        let (mut aoa, mut on_speed) = (Vec::new(), f64::NAN);
        // The way left to the lineup (`Autopilot::to_go`, the flight's spacing) the tick before the landing begins and
        // the tick after: the same pattern, so within 5 % (the light jets' 1 NM downwind is a laden jet's 2.6 km).
        let (mut go_before, mut go_jump) = (None, None);
        for _ in 0..900 * 60 {
            let landing = ap.stage().starts_with("landing");
            if let Fm::SixDof(s) = &mut fm {
                s.set_ground_height(z as f32);
                s.ap_landing = landing;
            }
            ap.step(&mut fm, &|_: f64, _: f64| z as f32);
            fm.step(1.0 / 60.0);
            let s = fm.state();
            assert!(s.crashed.is_none(), "{name}: crashed ({:?}) in {}", s.crashed, ap.stage());
            let go = ap.to_go(s.position);
            if go_jump.is_none() && ap.stage().starts_with("landing") {
                go_jump = go_before.zip(go);
            } else if !ap.stage().starts_with("landing") {
                go_before = go;
            }
            if let Some(n) = ap.phase().filter(|_| landing) {
                if steps.last() != Some(&n) {
                    steps.push(n);
                    entered.insert(n, frame(s.position));
                    if n == 7 {
                        gear_kt = s.speed * 1.943_844;
                    }
                }
                if n == 7 {
                    down_left = down_left.min(-frame(s.position).1);
                }
            }
            if let Fm::SixDof(x) = &fm
                && ap.phase() == Some(13)
                && (15.0..305.0).contains(&(s.position.z - z))
            {
                aoa.push(x.indicated_aoa());
                on_speed = x.jet.final_alpha_at(x.mass());
            }
            if touch.is_none() && s.on_ground {
                touch = Some((last_sink, frame(s.position)));
            } else if touch.is_none() {
                last_sink = -s.velocity[2];
            } else if s.speed < if player { 2.0 } else { 26.0 } {
                stop = Some(frame(s.position));
                break;
            }
        }
        println!("{name} at {base}: steps {steps:?}, entered {entered:?}, touch {touch:?}, stop {stop:?}");
        let ord: Vec<usize> = steps.iter().copied().filter(|n| [3, 4, 7, 11, 13, 14].contains(n)).collect();
        assert_eq!(ord, [3, 4, 7, 11, 13, 14], "{name}: the steps in order ({steps:?})");
        let brk = entered[&4];
        assert!((0.0..900.0).contains(&brk.0) && brk.1.abs() < 150.0, "{name}: the break over the runway {brk:?}");
        assert!((brk.2 - OVERHEAD.height).abs() < 60.0, "{name}: the break's height {brk:?}");
        let perch = entered[&11];
        assert!((1300.0..4500.0).contains(&-perch.1), "{name}: the downwind 1-2 NM left {perch:?}");
        assert!((perch.2 - OVERHEAD.perch_height).abs() < 80.0, "{name}: the perch's height {perch:?}");
        assert!(down_left > 1000.0, "{name}: the downwind stays left of the runway ({down_left:.0} m)");
        let (a, b) = go_jump.unwrap_or_else(|| panic!("{name}: the way left before and in the landing"));
        assert!((a - b).abs() < 0.05 * b, "{name}: the way left {a:.0} m before the landing, {b:.0} m in it");
        // The gear comes down on entering step 7: under the game's 300 kt limit (terrain_view.gd GEAR_DOWN_MAX_KT).
        assert!(gear_kt < 300.0, "{name}: the gear at {gear_kt:.0} kt");
        let fin = entered[&13];
        assert!(
            (-3500.0..-800.0).contains(&fin.0) && fin.1.abs() < 150.0 && fin.2 < 250.0,
            "{name}: the final {fin:?}"
        );
        // The final flies the on-speed α (modern-iaf/docs/training.md §16.6): the base turn ends at the final's speed.
        let mean = aoa.iter().sum::<f64>() / aoa.len().max(1) as f64;
        println!("{name}: the final's α {mean:.1}° over {} ticks, on-speed {on_speed:.1}°", aoa.len());
        assert!(
            aoa.len() > 300 && (mean - on_speed).abs() < 1.0,
            "{name}: the final's α {mean:.1}°, on-speed {on_speed:.1}°"
        );
        let (sink, t) = touch.unwrap_or_else(|| panic!("{name}: touched down"));
        assert!(sink < 3.05, "{name}: sink {sink:.2} m/s");
        let s = stop.unwrap_or_else(|| panic!("{name}: stopped"));
        assert!(t.0 > -100.0 && s.0 < 2800.0 && s.1.abs() < 22.0, "{name}: on the runway {t:?} {s:?}");
    }
}
