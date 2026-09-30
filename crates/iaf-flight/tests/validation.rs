//! Flies the original F-16 data through standard test points and compares the
//! results with public figures for the real aircraft. Prints a report; only
//! gross failures (NaN, crashes) fail the test — deviations are for review.
//!
//! `cargo test -p iaf-flight --test validation -- --nocapture`
//! Needs the extracted game data (`assets/install`, or `IAF_INSTALL`).

use std::path::PathBuf;

use iaf_flight::atmosphere::air;
use iaf_flight::{Aircraft, Controls, DataSet, State};

const KT: f32 = 1.943844; // m/s → kt
const FT: f32 = 3.28084; // m → ft

fn install() -> Option<PathBuf> {
    let p = std::env::var_os("IAF_INSTALL")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/install"));
    p.join("resource/md/bd.ibx").is_file().then_some(p)
}

thread_local! {
    static SET: std::cell::Cell<DataSet> = const { std::cell::Cell::new(DataSet::Original) };
}

fn f16(alt_ft: f32, speed_kt: f32) -> Option<Aircraft> {
    let (params, envelope) = iaf_flight::load_with(&install()?, "F-16", SET.get()).ok()?;
    Some(Aircraft::new(params, envelope, [0.0, 0.0, (alt_ft / FT) as f64], 0.0, speed_kt / KT))
}

fn fly(ac: &mut Aircraft, controls: Controls, seconds: f64) -> State {
    ac.set_controls(controls);
    let dt = 1.0 / 60.0;
    for _ in 0..(seconds / dt) as usize {
        ac.step(dt);
    }
    ac.state()
}

struct Row {
    item: &'static str,
    iaf: String,
    real: &'static str,
    verdict: &'static str,
}

fn verdict(value: f32, lo: f32, hi: f32) -> &'static str {
    if value < lo * 0.9 || value > hi * 1.1 {
        "OFF"
    } else if value < lo || value > hi {
        "close"
    } else {
        "ok"
    }
}

#[test]
fn f16_against_public_data() {
    for set in [DataSet::Original, DataSet::Real] {
        SET.set(set);
        report(set);
    }
}

fn report(set: DataSet) {
    let Some(mut probe) = f16(10000.0, 350.0) else {
        eprintln!("skipped: no extracted game data (assets/install)");
        return;
    };
    let p = probe.params.clone();
    let mut rows = Vec::new();
    let mil = Controls { throttle: 0.74, ..Default::default() };
    let ab = Controls { throttle: 1.0, ..Default::default() };

    // Static data.
    rows.push(Row { item: "empty weight", iaf: format!("{:.0} lb", p.empty_mass / 0.45359), real: "~19,000 lb (Block 30/40)", verdict: verdict(p.empty_mass / 0.45359, 18500.0, 19500.0) });
    rows.push(Row { item: "internal fuel", iaf: format!("{:.0} lb", p.fuel_mass / 0.45359), real: "~7,000 lb", verdict: verdict(p.fuel_mass / 0.45359, 6900.0, 7200.0) });
    let t_sl_mil = p.thrust[0][0][0] + (p.thrust[0][0][1] - p.thrust[0][0][0]) * (0.05 + 0.7432432 * 0.74);
    let t_sl_ab = p.thrust[0][0][1];
    rows.push(Row { item: "thrust SL static, military", iaf: format!("{t_sl_mil:.0} lbf"), real: "14,600 (F100-220) .. 17,000 (F110-100) lbf", verdict: verdict(t_sl_mil, 14600.0, 17200.0) });
    rows.push(Row { item: "thrust SL static, full AB", iaf: format!("{t_sl_ab:.0} lbf"), real: "23,800 (F100-220) .. 28,900 (F110-100) lbf", verdict: verdict(t_sl_ab, 23800.0, 29000.0) });
    let stall = probe.envelope.vmin(0.0, 1.0) * KT;
    rows.push(Row { item: "1 g stall speed, SL", iaf: format!("{stall:.0} kt"), real: "~120-130 kt (FLCS AoA limit, landing weight)", verdict: verdict(stall, 115.0, 135.0) });
    rows.push(Row { item: "max roll rate", iaf: format!("{:.0} deg/s", p.max_roll_rate.to_degrees()), real: "~240-308 deg/s (FLCS limit 308)", verdict: verdict(p.max_roll_rate.to_degrees(), 240.0, 308.0) });

    // Level flight hold with neutral stick.
    let s0 = probe.state();
    let s = fly(&mut probe, mil, 60.0);
    assert!(s.position[2].is_finite() && s.speed.is_finite());
    let dz = (s.position[2] - s0.position[2]) as f32 * FT;
    rows.push(Row { item: "neutral stick, 60 s @10k ft", iaf: format!("alt change {dz:+.0} ft, {:.0} kt", s.speed * KT), real: "holds altitude (1 g hold)", verdict: if dz.abs() < 300.0 { "ok" } else { "OFF" } });
    // Same with the "better physics" 1 g hold (flight path instead of nose pitch).
    let mut better = f16(10000.0, 400.0).unwrap();
    better.set_better_physics(true);
    let b0 = better.state();
    let b = fly(&mut better, mil, 60.0);
    let dzb = (b.position[2] - b0.position[2]) as f32 * FT;
    rows.push(Row { item: "  same, better physics", iaf: format!("alt change {dzb:+.0} ft, {:.0} kt", b.speed * KT), real: "holds altitude (1 g hold)", verdict: if dzb.abs() < 300.0 { "ok" } else { "OFF" } });

    // Maximum level speed (full AB, neutral stick holds the flight path): peak while fuel lasts.
    for (alt, lo, hi, real) in [(0.0, 780.0, 800.0, "~795 kt (Mach 1.2)"), (40000.0, 1100.0, 1180.0, "~1,150 kt (Mach 2.0)")] {
        let mut ac = f16(alt, 500.0).unwrap();
        ac.set_better_physics(true); // level flight needs the flight-path hold
        ac.set_controls(ab);
        let mut best = ac.state();
        for _ in 0..(600 * 60) {
            ac.step(1.0 / 60.0);
            let s = ac.state();
            if s.fuel_kg <= 0.0 {
                break;
            }
            if s.speed > best.speed {
                best = s;
            }
        }
        let mach = best.speed / air(best.position[2] as f32).sound;
        rows.push(Row { item: if alt == 0.0 { "max level speed, SL" } else { "max level speed, 40k ft" }, iaf: format!("{:.0} kt (Mach {mach:.2}) after {:.0} s, alt {:+.0} ft", best.speed * KT, best.time, best.position[2] as f32 * FT - alt), real, verdict: verdict(best.speed * KT, lo, hi) });
    }

    // Roll: time to 90° from wings level, full stick, 350 kt @ 10k ft.
    let mut ac = f16(10000.0, 350.0).unwrap();
    ac.set_controls(Controls { stick_x: 1.0, ..mil });
    let (mut t90, mut peak) = (f32::NAN, 0.0f32);
    let mut last = ac.state().roll;
    for i in 1..=180 {
        ac.step(1.0 / 60.0);
        let r = ac.state().roll;
        peak = peak.max(((r - last).rem_euclid(std::f32::consts::TAU)).to_degrees() * 60.0);
        last = r;
        if t90.is_nan() && r.to_degrees() >= 90.0 {
            t90 = i as f32 / 60.0;
        }
    }
    rows.push(Row { item: "roll 0→90°, 350 kt @10k ft", iaf: format!("{t90:.2} s, peak {peak:.0} deg/s"), real: "~0.5 s (240-300 deg/s)", verdict: verdict(t90, 0.35, 0.6) });

    // Instantaneous turn: full pull at ~390 KCAS (420 kt true) @ 10k ft, heading rate over 2..3 s.
    let mut ac = f16(10000.0, 420.0).unwrap();
    // Hold ~80° of bank with a simple bank controller (like a pilot would), full pull.
    let hold_bank = |ac: &mut Aircraft, pull: f32, seconds: f64| {
        for _ in 0..(seconds * 60.0) as usize {
            let roll = ac.state().roll.to_degrees();
            ac.set_controls(Controls { stick_x: ((80.0 - roll) / 40.0).clamp(-1.0, 1.0), stick_y: pull, ..mil });
            ac.step(1.0 / 60.0);
        }
        ac.state()
    };
    hold_bank(&mut ac, 0.0, 3.0);
    let a = hold_bank(&mut ac, 1.0, 2.0);
    let b = hold_bank(&mut ac, 1.0, 1.0);
    let turn = ((b.heading - a.heading).rem_euclid(std::f32::consts::TAU)).to_degrees();
    rows.push(Row { item: "instantaneous turn, 420 kt TAS @10k ft", iaf: format!("{turn:.1} deg/s at {:.1} g, bank {:.0}°", b.g, b.roll.to_degrees()), real: "~20-26 deg/s at 9 g", verdict: verdict(turn, 18.0, 26.0) });

    // Specific excess power at SL, 350 kt, full AB (instant climb rate).
    let mut ac = f16(0.0, 350.0).unwrap();
    let s = fly(&mut ac, ab, 1.5);
    let v0 = s.speed;
    let s2 = fly(&mut ac, ab, 1.0);
    let ps = (s2.speed * s2.speed - v0 * v0) / (2.0 * 9.806) + (s2.position[2] - s.position[2]) as f32;
    rows.push(Row { item: "climb (Ps) SL, 350 kt, full AB", iaf: format!("{:.0} ft/min", ps * FT * 60.0), real: "~50,000 ft/min", verdict: verdict(ps * FT * 60.0, 45000.0, 55000.0) });

    // Fuel flow.
    let ff = |thr: f32| {
        let mut ac = f16(0.0, 350.0).unwrap();
        let a = fly(&mut ac, Controls { throttle: thr, ..Default::default() }, 2.0);
        let b = fly(&mut ac, Controls { throttle: thr, ..Default::default() }, 10.0);
        (a.fuel_kg - b.fuel_kg) / 10.0 / 0.45359 * 3600.0
    };
    let (f_mil, f_ab) = (ff(0.74), ff(1.0));
    rows.push(Row { item: "fuel flow military, SL", iaf: format!("{f_mil:.0} lb/h"), real: "~9,000-12,000 lb/h", verdict: verdict(f_mil, 9000.0, 12000.0) });
    rows.push(Row { item: "fuel flow full AB, SL", iaf: format!("{f_ab:.0} lb/h"), real: "~50,000-65,000 lb/h", verdict: verdict(f_ab, 50000.0, 65000.0) });

    println!("\n F-16 ({set:?} data set) vs public references");
    println!(" {:<36} {:<44} {:<46} {}", "test", "IAF model", "real F-16 (approx., public sources)", "");
    for r in &rows {
        println!(" {:<36} {:<44} {:<46} {}", r.item, r.iaf, r.real, r.verdict);
    }
}

