//! Low level (docs/ai.md §20; modern-iaf/docs/ai-plan.md K17) on the 6-DoF over hilly terrain: the terrain following
//! at a set height, every AI jet's ground collision avoidance (here in the BFM loop's dive at the ground) and the
//! attack's low run-in with the pop-up. The jets' orders go through `iaf_ai::apply`, which sets the floor. Skips with
//! a message when `assets/converted/own` is not built.

use std::path::{Path, PathBuf};

use iaf_ai::flight::{FLOOR_M, Order};
use iaf_ai::{Bogey, Call, Flight, apply};
use iaf_avionics::bombs::Bomb;
use iaf_flight::autopilot::{Autopilot, Config, MODE_BFM, MODE_STEER, Steer};
use iaf_flight::fm::Fm;
use iaf_flight::{DataSet, Start, Vec3};

const DT: f64 = 1.0 / 60.0;
/// 200 ft (m).
const AGL_200FT: f32 = 61.0;
/// combat.gd's AI stores: the steered fall's along-track clamp (m/s²); the MK-82's blast radius (m).
const CLAMP: f64 = 15.0;
const BLAST_M: f64 = 50.0;

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    (dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file()).then_some(dir)
}

/// Rolling hills 20 to 380 m high, slopes up to about 6° (the Negev's hills between Be'er Sheva and Dimona, inferred).
fn hills(x: f64, y: f64) -> f64 {
    200.0 + 120.0 * (y / 2500.0).sin() * (x / 3000.0).cos() + 60.0 * (y / 1200.0 + x / 1800.0).sin()
}

fn start(dir: &Path, ty: &str, pos: Vec3, speed: f64) -> (Fm, Autopilot) {
    let (prm, env) = iaf_flight::load_with(dir, ty, DataSet::Original).unwrap();
    let st = Start {
        position: pos,
        pitch: 0.0,
        roll: 0.0,
        heading: 0.0,
        velocity: Vec3::NORTH * speed,
        airborne: true,
        engine_on: true,
    };
    (Fm::start(ty, prm, env, st), Autopilot::new(Config::load(dir)))
}

/// One frame of a jet over the hills: its autopilot, its flight model on the ground under it; its height above it.
fn step(fm: &mut Fm, ap: &mut Autopilot) -> f64 {
    step_on(fm, ap, &hills)
}

/// [`step`] over the terrain `h`.
fn step_on(fm: &mut Fm, ap: &mut Autopilot, h: &dyn Fn(f64, f64) -> f64) -> f64 {
    let p = fm.state().position;
    if let Fm::SixDof(s) = fm {
        s.set_ground_height(h(p[0], p[1]) as f32);
    }
    ap.step(fm, &|x, y| h(x, y) as f32);
    fm.step(DT);
    let s = fm.state();
    assert!(s.crashed.is_none(), "crashed at {:?}: {:?}", s.position, s.crashed);
    s.position[2] - h(s.position[0], s.position[1])
}

/// Flat ground at 400 m with a knoll every 5 km: 50 m high, 300 m across (the Negev's test run, test_low_level.gd).
fn knolls(_x: f64, y: f64) -> f64 {
    let d = (y.rem_euclid(5000.0) - 2500.0).abs();
    400.0 + (50.0 * (1.0 - d / 150.0)).max(0.0)
}

#[test]
fn follows_over_a_knoll_without_a_balloon() {
    // A Sufa at 200 ft over flat ground with sharp 50 m knolls: it climbs over each in time, so the fly-up stays out,
    // and comes back down; never 120 m above the ground or under the floor.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let (mut fm, mut ap) = start(&dir, "F-16I", Vec3::new(0.0, 0.0, 461.0), 230.0);
    let order = Order {
        mode: Some(MODE_STEER),
        steer: Some(Steer { to: Vec3::new(0.0, 60_000.0, 461.0), g: 3.0, speed: 230.0, thr_max: 1.0, fighter: false }),
        follow: Some(AGL_200FT),
        low: true,
        ..Order::default()
    };
    let (mut t, mut lo, mut hi) = (0.0, f64::MAX, 0.0f64);
    while fm.state().position[1] < 30_000.0 {
        apply(&order, &mut ap, &mut fm);
        let agl = step_on(&mut fm, &mut ap, &knolls);
        t += DT;
        assert!(t < 300.0, "too slow");
        if fm.state().position[1] > 1_000.0 {
            (lo, hi) = (lo.min(agl), hi.max(agl));
        }
    }
    println!("over the knolls: {lo:.0}..{hi:.0} m");
    assert!(lo > FLOOR_M as f64 && hi < 120.0, "{lo:.0}..{hi:.0} m");
}

#[test]
fn follows_200_ft_over_the_hills() {
    // A Sufa and a MiG-29A at 1,000 m ordered north at 200 ft above the terrain for 40 km: down to the height, then on
    // it over the hills, never under the floor.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    for ty in ["F-16I", "MiG-29A"] {
        let (mut fm, mut ap) = start(&dir, ty, Vec3::new(0.0, 0.0, 1000.0), 250.0);
        let to = Vec3::new(0.0, 60_000.0, 1000.0);
        let order = Order {
            mode: Some(MODE_STEER),
            steer: Some(Steer { to, g: 3.0, speed: 250.0, thr_max: 1.0, fighter: ty == "MiG-29A" }),
            follow: Some(AGL_200FT),
            low: true,
            ..Order::default()
        };
        let (mut t, mut low, mut on, mut sum, mut n) = (0.0, f64::MAX, None, 0.0, 0);
        while fm.state().position[1] < 40_000.0 {
            apply(&order, &mut ap, &mut fm);
            let agl = step(&mut fm, &mut ap);
            t += DT;
            assert!(t < 300.0, "{ty}: too slow");
            if on.is_none() && agl < 1.5 * AGL_200FT as f64 {
                on = Some(fm.state().position[1]);
            }
            if on.is_some() {
                (low, sum, n) = (low.min(agl), sum + agl, n + 1);
            }
        }
        let mean = sum / n as f64;
        println!("{ty}: on the height after {:.0} m; least {low:.0} m, mean {mean:.0} m", on.unwrap_or(f64::NAN));
        assert!(on.is_some_and(|y| y < 15_000.0), "{ty}: down to the height");
        assert!(low > FLOOR_M as f64, "{ty}: {low:.0} m, under the floor");
        assert!((45.0..120.0).contains(&mean), "{ty}: mean {mean:.0} m");
    }
}

#[test]
fn bfm_dive_at_the_ground_pulls_out() {
    // A MiG-29A in the BFM loop at 1,200 m chasing a point deep under the hills (a bogey's dive to the deck): it dives
    // steeply and pulls out over the floor. One started on its back in a 45° dive at 1,500 m does too. Each with the
    // watch-ground and the fly-up over it, and flying low (the fly-up alone).
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    for (inverted, flying_low) in [(false, false), (true, false), (false, true), (true, true)] {
        let (prm, env) = iaf_flight::load_with(&dir, "MiG-29A", DataSet::Original).unwrap();
        let (pitch, roll, z) = if inverted { (-45f64, 180f64, 1500.0) } else { (0.0, 0.0, 1200.0) };
        let p = pitch.to_radians();
        let st = Start {
            position: Vec3::new(0.0, 0.0, z),
            pitch: p as f32,
            roll: roll.to_radians() as f32,
            heading: 0.0,
            velocity: Vec3::new(0.0, p.cos(), p.sin()) * 260.0,
            airborne: true,
            engine_on: true,
        };
        let mut fm = Fm::start("MiG-29A", prm, env, st);
        let mut ap = Autopilot::new(Config::load(&dir));
        let order = Order {
            mode: Some(MODE_BFM),
            steer: Some(Steer {
                to: Vec3::new(0.0, 3_000.0, -3_000.0),
                g: 7.0,
                speed: 260.0,
                thr_max: 1.0,
                fighter: true,
            }),
            low: flying_low,
            ..Order::default()
        };
        let (mut low, mut dive, mut t) = (f64::MAX, 0.0f64, 0.0);
        while t < 40.0 {
            apply(&order, &mut ap, &mut fm);
            low = low.min(step(&mut fm, &mut ap));
            dive = dive.min(fm.state().velocity[2] as f64);
            t += DT;
        }
        let s = fm.state();
        println!(
            "inverted {inverted}, low {flying_low}: dived at {dive:.0} m/s, least {low:.0} m over the hills, now {:.0} m",
            s.position[2]
        );
        assert!(dive < -100.0, "it dived");
        assert!(low > 0.5 * FLOOR_M as f64, "{low:.0} m");
    }
}

/// Where the store released at `p` with velocity `v`, aimed at `aim`, meets the target's height.
fn impact(p: Vec3, v: Vec3, aim: Vec3) -> Vec3 {
    let b = Bomb::launch(0.0, p, v, aim, CLAMP, Vec3::ZERO);
    let mut t = 0.0;
    while b.position(t)[2] > aim[2] && t < 120.0 {
        t += 0.01;
    }
    b.position(t)
}

#[test]
fn low_run_in_pops_up_into_the_dive() {
    // The four-ship at 1,500 m over the hills, the flight low at 200 ft; "attack my target" for #2 with bombs on a
    // target 30 km ahead: #2 comes down to 200 ft, runs in on the terrain following, pops up 4 nm out at 30°, dives
    // and releases on the target, egresses low again; never under the floor.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut flight = Flight::default();
    let mut jets = Vec::new();
    for i in 0..4 {
        let s = if i == 0 { [0.0; 3] } else { iaf_ai::SHAPES[0].1[i - 1] };
        let (mut fm, mut ap) = start(&dir, "F-16I", Vec3::new(s[1] as f64, s[0] as f64, 1500.0), 230.0);
        flight.add(i as u8 + 1, i > 0, &fm, &mut ap);
        if i == 0 {
            let to = Vec3::new(0.0, 15_000.0, 1500.0);
            ap.steer = Some(Steer { to, g: 2.0, speed: 230.0, thr_max: 1.0, fighter: false });
            ap.set_mode(&mut fm, MODE_STEER);
        }
        jets.push((fm, ap));
    }
    flight.ground_weapon(2, Some(false));
    flight.low(Some(AGL_200FT));
    let at = Vec3::new(0.0, 30_000.0, hills(0.0, 30_000.0));
    let (mut t, mut calls, mut release) = (0.0, Vec::<(f64, Call)>::new(), None);
    let mut track: Vec<(f64, f64, f64)> = Vec::new(); // #2's (time, distance to the target, height above the hills)
    let mut low_all = f64::MAX;
    let said = |calls: &[(f64, Call)], id: &str| calls.iter().find(|(_, c)| c.from == 2 && c.id == id).map(|c| c.0);
    while t < 600.0 && said(&calls, "done").is_none() {
        for (i, (fm, ap)) in jets.iter().enumerate() {
            flight.sense(i as u8 + 1, true, fm, ap);
        }
        flight.ground_target(Some(Bogey { pos: at, vel: Vec3::ZERO }));
        if t == 0.0 {
            assert_eq!(flight.attack(t, 2, Some(Bogey { pos: at, vel: Vec3::ZERO })), Some(true));
        }
        calls.extend(flight.step(t).into_iter().map(|c| (t, c)));
        for i in 1..4 {
            let order = flight.members[i].order;
            let (fm, ap) = &mut jets[i];
            if i == 1 && order.release && release.is_none() {
                let s = fm.state();
                let v = Vec3::new(s.velocity[0] as f64, s.velocity[1] as f64, s.velocity[2] as f64);
                release = Some(((impact(s.position, v, at) - at).length(), s.position[2] - at[2]));
                flight.released(t, 2);
                flight.ground_weapon(2, None);
            }
            apply(&order, ap, fm);
        }
        for (i, (fm, ap)) in jets.iter_mut().enumerate() {
            let agl = step(fm, ap);
            if i == 1 {
                let p = fm.state().position;
                track.push((t, (p[0] - at[0]).hypot(p[1] - at[1]), agl));
                low_all = low_all.min(agl);
            }
        }
        t += DT;
    }
    let phase = |from: f64, to: f64| track.iter().filter(move |(_, d, _)| *d < from && *d > to).map(|x| x.2);
    // The run-in from 20 to 9 km out: on the terrain following.
    let (lo, hi) = phase(20_000.0, 9_000.0).fold((f64::MAX, 0.0f64), |(a, b), h| (a.min(h), b.max(h)));
    let apex = phase(7_408.0, 0.0).fold(0.0f64, f64::max);
    println!(
        "#2: in {:?} alpha {:?} done {:?}; run-in {lo:.0}..{hi:.0} m, apex {apex:.0} m, release {release:?}, least {low_all:.0} m",
        said(&calls, "in"),
        said(&calls, "alpha"),
        said(&calls, "done")
    );
    assert!(said(&calls, "done").is_some(), "#2 done: {calls:?}");
    assert!(lo > FLOOR_M as f64 && hi < 150.0, "low run-in: {lo:.0}..{hi:.0} m");
    assert!(apex > 1_400.0, "the pop-up: {apex:.0} m");
    let (miss, _) = release.expect("released");
    assert!(miss < BLAST_M, "the store {miss:.0} m off");
    assert!(low_all > FLOOR_M as f64, "#2 at {low_all:.0} m");
    // The egress low again: the last 2 km before "done" under 150 m.
    let tail = track.iter().rev().take_while(|x| x.1 > 6_000.0).map(|x| x.2).fold(0.0f64, f64::max);
    assert!(tail < 150.0, "egress low: {tail:.0} m");
}

#[test]
fn the_leads_low_level_order() {
    // The lead's radio order to the flight: "low" sets the low level (each wingman acks, its order flies low), "high"
    // ends it; to one wingman it is unable.
    let Some(dir) = own() else { return println!("skipped: no assets/converted/own (iaf-sim fm)") };
    let mut flight = Flight::default();
    let mut jets = Vec::new();
    for i in 0..4 {
        let s = if i == 0 { [0.0; 3] } else { iaf_ai::SHAPES[0].1[i - 1] };
        let (fm, mut ap) = start(&dir, "F-16I", Vec3::new(s[1] as f64, s[0] as f64, 1500.0), 230.0);
        flight.add(i as u8 + 1, i > 0, &fm, &mut ap);
        jets.push((fm, ap));
    }
    let run = |flight: &mut Flight, t: f64| {
        for (i, (fm, ap)) in jets.iter().enumerate() {
            flight.sense(i as u8 + 1, true, fm, ap);
        }
        let mut calls = Vec::new();
        for k in 0..120 {
            calls.extend(flight.step(t + k as f64 * DT));
        }
        calls
    };
    run(&mut flight, 0.0);
    let ids = |calls: &[Call], id: &str| calls.iter().filter(|c| c.id == id).count();
    assert!(!flight.command(2.0, 2, "low"));
    assert_eq!(ids(&run(&mut flight, 2.0), "unable"), 1);
    assert!(!flight.members[1].order.low);
    assert!(flight.command(4.0, 0, "low"));
    assert_eq!(ids(&run(&mut flight, 4.0), "ack"), 3);
    assert!((1..4).all(|i| flight.members[i].order.low));
    assert!(flight.command(6.0, 0, "high"));
    assert_eq!(ids(&run(&mut flight, 6.0), "ack"), 3);
    assert!((1..4).all(|i| !flight.members[i].order.low));
}
