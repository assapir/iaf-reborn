//! Flies every flyable jet's data (original and real set) through standard test points and compares
//! the results with public figures for the real aircraft (docs/real-aircraft.md). Prints a report per
//! jet; only gross failures (NaN, crashes) fail the test — deviations are for review. Rows without a
//! public reference print "-".
//!
//! `cargo test --release -p iaf-flight --test validation -- --nocapture`
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

/// A public reference: accepted range and its label.
type R = Option<(f32, f32, &'static str)>;

/// Public figures per aircraft (docs/real-aircraft.md has the sources).
struct Ref {
    section: &'static str,
    name: &'static str,
    empty: R,
    fuel: R,
    thrust_mil: R,
    thrust_ab: R,
    stall: R,
    roll_rate: R,
    vmax_sl: R,
    vmax_40k: R,
    roll90: R,
    turn: R,
    climb: R,
    ff_mil: R,
    ff_ab: R,
}

const REFS: &[Ref] = &[
    Ref {
        section: "F-16",
        name: "F-16C Block 30/40",
        empty: Some((18500.0, 19500.0, "~19,000 lb (Block 30/40)")),
        fuel: Some((6900.0, 7200.0, "~7,000 lb")),
        thrust_mil: Some((14600.0, 17200.0, "14,600 (F100-220) .. 17,000 (F110-100) lbf")),
        thrust_ab: Some((23800.0, 29000.0, "23,800 (F100-220) .. 28,900 (F110-100) lbf")),
        stall: Some((115.0, 135.0, "~120-130 kt (FLCS AoA limit, landing weight)")),
        roll_rate: Some((240.0, 308.0, "~240-308 deg/s (FLCS limit 308)")),
        vmax_sl: Some((780.0, 800.0, "~795 kt (Mach 1.2)")),
        vmax_40k: Some((1100.0, 1180.0, "~1,150 kt (Mach 2.0)")),
        roll90: Some((0.35, 0.6, "~0.5 s (240-300 deg/s)")),
        turn: Some((18.0, 26.0, "~20-26 deg/s at 9 g")),
        climb: Some((45000.0, 55000.0, "~50,000 ft/min")),
        ff_mil: Some((9000.0, 12000.0, "~9,000-12,000 lb/h")),
        ff_ab: Some((50000.0, 65000.0, "~50,000-65,000 lb/h")),
    },
    Ref {
        section: "F-15",
        name: "F-15C Baz (2x F100-PW-220)",
        empty: Some((28000.0, 29000.0, "28,476 lb (SAC)")),
        fuel: Some((13400.0, 13900.0, "13,455 lb JP-4 (SAC)")),
        thrust_mil: Some((28000.0, 29500.0, "2 x 14,370 lbf (SAC)")),
        thrust_ab: Some((46500.0, 47900.0, "2 x 23,450 lbf (SAC)")),
        stall: Some((125.0, 140.0, "135 kt at 45,713 lb (SAC, power off)")),
        roll_rate: Some((180.0, 220.0, "~180-220 deg/s (uncertain)")),
        vmax_sl: Some((780.0, 810.0, "~800 KCAS (M1.2, SAC q limit)")),
        vmax_40k: Some((1300.0, 1340.0, "1,309-1,340 kt (M2.3, 35-45k ft, SAC)")),
        roll90: None,
        turn: Some((20.0, 28.0, "~20-28 deg/s near corner (uncertain)")),
        climb: Some((50000.0, 56000.0, "55,960 ft/min at 41,286 lb (SAC)")),
        ff_mil: Some((19000.0, 23000.0, "~2 x 10,500 lb/h (TSFC 0.73)")),
        ff_ab: Some((90000.0, 105000.0, "~2 x 47,000-52,000 lb/h (uncertain)")),
    },
    Ref {
        section: "F-4",
        name: "F-4E Kurnass (2x J79-GE-17)",
        empty: Some((29500.0, 31000.0, "~30,330 lb (Jane's)")),
        fuel: Some((12000.0, 13000.0, "1,855-1,994 US gal, 12,060-12,960 lb")),
        thrust_mil: Some((23500.0, 24000.0, "2 x 11,870 lbf")),
        thrust_ab: Some((35500.0, 36000.0, "2 x 17,900 lbf")),
        stall: Some((150.0, 165.0, "~150-165 kt at 40,000 lb (uncertain)")),
        roll_rate: Some((120.0, 180.0, "~120-180 deg/s (uncertain)")),
        vmax_sl: Some((740.0, 790.0, "~750 KIAS placard (M1.13-1.19)")),
        vmax_40k: Some((1240.0, 1290.0, "M2.17 at 36k .. M2.23 at 40k ft")),
        roll90: None,
        turn: Some((18.0, 21.0, "~18-21 deg/s at 420-450 kt (uncertain)")),
        climb: Some((41000.0, 61500.0, "41,300-61,400 ft/min")),
        ff_mil: Some((19000.0, 21000.0, "~2 x 10,000 lb/h")),
        ff_ab: Some((70000.0, 72000.0, "~2 x 35,000-36,000 lb/h")),
    },
    Ref {
        section: "KFIR",
        name: "Kfir C7 (J79-J1E)",
        empty: Some((16000.0, 16400.0, "16,060-16,345 lb")),
        fuel: Some((4760.0, 5700.0, "2,700-3,243 l, 4,760-5,670 lb")),
        thrust_mil: Some((11850.0, 11900.0, "11,870-11,890 lbf")),
        thrust_ab: Some((17850.0, 18750.0, "17,900 (18,750 combat plus) lbf")),
        stall: Some((120.0, 135.0, "approach ~160-175 kt (est.) / 1.3")),
        roll_rate: Some((150.0, 220.0, "not public; est. 150-220 deg/s")),
        vmax_sl: Some((740.0, 760.0, "~750 kt (M1.13)")),
        vmax_40k: Some((1150.0, 1320.0, "M2.0 sustained .. M2.3 dash")),
        roll90: None,
        turn: None,
        climb: Some((42000.0, 50000.0, "45,930 ft/min (light, peak)")),
        ff_mil: Some((9500.0, 10500.0, "~9,970 lb/h (TSFC 0.84)")),
        ff_ab: Some((34000.0, 38000.0, "~35,200 lb/h (TSFC 1.965)")),
    },
    Ref {
        section: "LAVI",
        name: "Lavi (PW1120)",
        empty: Some((15300.0, 15700.0, "15,500 lb (Jane's)")),
        fuel: Some((5900.0, 6100.0, "3,330 l, ~6,000 lb")),
        thrust_mil: Some((13500.0, 13600.0, "13,530-13,550 lbf")),
        thrust_ab: Some((20500.0, 20700.0, "20,585-20,700 lbf")),
        stall: Some((105.0, 120.0, "110 kt lowest speed flown (flight test)")),
        roll_rate: None,
        vmax_sl: Some((730.0, 790.0, "not public; est. M1.1-1.2")),
        vmax_40k: Some((1030.0, 1100.0, "M1.8-1.85 (1,061 kt at 36k ft)")),
        roll90: None,
        turn: Some((22.0, 25.0, "23-24.3 deg/s at M0.8, 15,600 ft")),
        climb: Some((45000.0, 55000.0, ">50,000 ft/min (254 m/s)")),
        ff_mil: Some((10300.0, 11300.0, "~10,800 lb/h (TSFC 0.80)")),
        ff_ab: Some((36000.0, 40000.0, "~38,200 lb/h (TSFC 1.86)")),
    },
    Ref {
        section: "MIRAGE",
        name: "Mirage IIICJ Shahak (Atar 09C)",
        empty: Some((12350.0, 13450.0, "12,350-13,450 lb")),
        fuel: Some((4500.0, 5100.0, "~2,550-2,900 l, 4,500-5,100 lb (uncertain)")),
        thrust_mil: Some((9430.0, 9440.0, "9,430-9,440 lbf")),
        thrust_ab: Some((13228.0, 13670.0, "13,240-13,670 lbf")),
        stall: Some((130.0, 155.0, "approach 170-200 kt / 1.3")),
        roll_rate: Some((150.0, 200.0, "not public; est. 150-200 deg/s")),
        vmax_sl: Some((725.0, 755.0, "~Mach 1.1-1.14")),
        vmax_40k: Some((1200.0, 1270.0, "M2.1-2.2 at 39k ft")),
        roll90: None,
        turn: None,
        climb: Some((16400.0, 30000.0, "16,400 ft/min (average; understated)")),
        ff_mil: Some((9000.0, 10000.0, "~9,500 lb/h (TSFC 1.01)")),
        ff_ab: Some((26500.0, 28000.0, "~26,900-27,700 lb/h (TSFC 2.03)")),
    },
];

struct Row {
    item: &'static str,
    iaf: String,
    real: &'static str,
    verdict: &'static str,
}

fn verdict(value: f32, r: R) -> &'static str {
    let Some((lo, hi, _)) = r else { return "-" };
    if value < lo * 0.9 || value > hi * 1.1 {
        "OFF"
    } else if value < lo || value > hi {
        "close"
    } else {
        "ok"
    }
}

fn label(r: R) -> &'static str {
    r.map_or("(no public figure)", |r| r.2)
}

fn fly(ac: &mut Aircraft, controls: Controls, seconds: f64) -> State {
    ac.set_controls(controls);
    let dt = 1.0 / 60.0;
    for _ in 0..(seconds / dt) as usize {
        ac.step(dt);
    }
    ac.state()
}

#[test]
fn flyable_jets_against_public_data() {
    let Some(dir) = install() else {
        eprintln!("skipped: no extracted game data (assets/install)");
        return;
    };
    let only = std::env::var("IAF_JET").ok();
    for r in REFS {
        if only.as_deref().is_some_and(|o| !o.eq_ignore_ascii_case(r.section)) {
            continue;
        }
        for set in [DataSet::Original, DataSet::Real] {
            report(&dir, r, set);
        }
    }
}

fn report(dir: &std::path::Path, r: &Ref, set: DataSet) {
    let (params, envelope) = iaf_flight::load_with(dir, r.section, set).unwrap();
    let jet = |alt_ft: f32, speed_kt: f32| Aircraft::new(params.clone(), envelope.clone(), [0.0, 0.0, (alt_ft / FT) as f64], 0.0, speed_kt / KT);
    let probe = jet(10000.0, 350.0);
    let p = probe.params.clone();
    let mut rows = Vec::new();
    let mil = Controls { throttle: 0.74, ..Default::default() };
    let ab = Controls { throttle: 1.0, ..Default::default() };

    // Static data.
    rows.push(Row { item: "empty weight", iaf: format!("{:.0} lb", p.empty_mass / 0.45359), real: label(r.empty), verdict: verdict(p.empty_mass / 0.45359, r.empty) });
    rows.push(Row { item: "internal fuel", iaf: format!("{:.0} lb", p.fuel_mass / 0.45359), real: label(r.fuel), verdict: verdict(p.fuel_mass / 0.45359, r.fuel) });
    let t_sl_mil = p.thrust[0][0][0] + (p.thrust[0][0][1] - p.thrust[0][0][0]) * (0.05 + 0.7432432 * 0.74) * p.dry_thrust;
    let t_sl_ab = p.thrust[0][0][1];
    rows.push(Row { item: "thrust SL static, military", iaf: format!("{t_sl_mil:.0} lbf"), real: label(r.thrust_mil), verdict: verdict(t_sl_mil, r.thrust_mil) });
    rows.push(Row { item: "thrust SL static, full AB", iaf: format!("{t_sl_ab:.0} lbf"), real: label(r.thrust_ab), verdict: verdict(t_sl_ab, r.thrust_ab) });
    let stall = probe.envelope.vmin(0.0, 1.0) * KT;
    rows.push(Row { item: "1 g stall speed, SL", iaf: format!("{stall:.0} kt"), real: label(r.stall), verdict: verdict(stall, r.stall) });
    let rr = p.max_roll_rate.to_degrees();
    rows.push(Row { item: "max roll rate", iaf: format!("{rr:.0} deg/s"), real: label(r.roll_rate), verdict: verdict(rr, r.roll_rate) });

    // Level flight hold with neutral stick, military power, from 350 kt. Measured after 5 s so the start
    // transient (the original's MaxWeight·g lift ramps give a short up-jolt, §15.6.4) is not counted.
    for bp in [false, true] {
        let mut ac = jet(10000.0, 350.0);
        ac.set_better_physics(bp);
        let s0 = fly(&mut ac, mil, 5.0);
        let s = fly(&mut ac, mil, 60.0);
        assert!(s.position[2].is_finite() && s.speed.is_finite());
        let dz = (s.position[2] - s0.position[2]) as f32 * FT;
        let item = if bp { "  same, better physics" } else { "neutral stick, 60 s @10k ft, 350 kt" };
        rows.push(Row { item, iaf: format!("alt change {dz:+.0} ft, vz {:+.0} ft/min, {:.0} kt", s.velocity[2] * FT * 60.0, s.speed * KT), real: "holds altitude (1 g hold)", verdict: if dz.abs() < 300.0 { "ok" } else { "OFF" } });
    }

    // Maximum level speed (full AB, neutral stick holds the flight path): peak while fuel lasts.
    for (alt, rf) in [(0.0, r.vmax_sl), (40000.0, r.vmax_40k)] {
        let mut ac = jet(alt, 500.0);
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
        rows.push(Row { item: if alt == 0.0 { "max level speed, SL" } else { "max level speed, 40k ft" }, iaf: format!("{:.0} kt (Mach {mach:.2}) after {:.0} s, alt {:+.0} ft", best.speed * KT, best.time, best.position[2] as f32 * FT - alt), real: label(rf), verdict: verdict(best.speed * KT, rf) });
    }

    // Roll: time to 90° from wings level, full stick, 350 kt @ 10k ft.
    let mut ac = jet(10000.0, 350.0);
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
    rows.push(Row { item: "roll 0→90°, 350 kt @10k ft", iaf: format!("{t90:.2} s, peak {peak:.0} deg/s"), real: label(r.roll90), verdict: verdict(t90, r.roll90) });

    // Rudder: full pedal for 4 s, then neutral, 350 kt @ 10k ft. The v1.1 β channel (2nd-order, RudderK; v1.0 data:
    // the exe's defaults) — time to 90 % of MaxBeta, β at the end of the hold, and the overshoot past 0 after release
    // (RudderBeta = 0 in all data: no damping term). No public reference (the model's sideslip is a visual/force angle).
    let mut ac = jet(10000.0, 350.0);
    let mb = p.max_beta.to_degrees();
    let (mut t90, mut hold, mut under) = (f32::NAN, 0.0f32, 0.0f32);
    for i in 1..=(8 * 60) {
        let t = i as f32 / 60.0;
        ac.set_controls(Controls { rudder: if t <= 4.0 { 1.0 } else { 0.0 }, ..mil });
        ac.step(1.0 / 60.0);
        let b = ac.state().beta.to_degrees();
        assert!(b.is_finite());
        if t <= 4.0 {
            hold = b;
            if t90.is_nan() && b >= 0.9 * mb {
                t90 = t;
            }
        } else {
            under = under.min(b);
        }
    }
    rows.push(Row { item: "rudder step, 350 kt @10k ft", iaf: format!("K {:.2}: 90% in {t90:.2} s, {hold:.1}/{mb:.0}°, overshoot {under:.1}°", p.rudder_k), real: "(no public figure)", verdict: "-" });

    // Instantaneous turn: full pull at ~390 KCAS (420 kt true) @ 10k ft, heading rate over 2..3 s.
    let mut ac = jet(10000.0, 420.0);
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
    rows.push(Row { item: "instantaneous turn, 420 kt TAS @10k ft", iaf: format!("{turn:.1} deg/s at {:.1} g, bank {:.0}°", b.g, b.roll.to_degrees()), real: label(r.turn), verdict: verdict(turn, r.turn) });

    // Specific excess power at SL, 350 kt, full AB (instant climb rate). The throttle goes to full AB first;
    // the original lights the afterburner only when the RPM would reach 100 % (2 s from the airborne start's
    // 70 %, §15.8), so the measurement starts once the AB is lit and the jet has accelerated to 350 kt
    // (from 320 kt); neutral stick (1 g).
    for bp in [false, true] {
        let mut ac = jet(0.0, 320.0);
        ac.set_better_physics(bp);
        ac.set_controls(ab);
        let mut s = ac.state();
        while (s.afterburner < 2 || s.speed * KT < 350.0) && s.time < 30.0 {
            s = fly(&mut ac, ab, 1.0 / 60.0);
        }
        let s = fly(&mut ac, ab, 0.1);
        let s2 = fly(&mut ac, ab, 1.0);
        let ps = (s2.speed * s2.speed - s.speed * s.speed) / (2.0 * 9.806) + (s2.position[2] - s.position[2]) as f32;
        let item = if bp { "  same, better physics" } else { "climb (Ps) SL, ~350 kt, full AB" };
        rows.push(Row { item, iaf: format!("{:.0} ft/min at {:.0} kt", ps * FT * 60.0, s.speed * KT), real: label(r.climb), verdict: verdict(ps * FT * 60.0, r.climb) });
    }

    // Fuel flow.
    let ff = |thr: f32| {
        let mut ac = jet(0.0, 350.0);
        let a = fly(&mut ac, Controls { throttle: thr, ..Default::default() }, 2.0);
        let b = fly(&mut ac, Controls { throttle: thr, ..Default::default() }, 10.0);
        (a.fuel_kg - b.fuel_kg) / 10.0 / 0.45359 * 3600.0
    };
    let (f_mil, f_ab) = (ff(0.74), ff(1.0));
    rows.push(Row { item: "fuel flow military, SL", iaf: format!("{f_mil:.0} lb/h"), real: label(r.ff_mil), verdict: verdict(f_mil, r.ff_mil) });
    rows.push(Row { item: "fuel flow full AB, SL", iaf: format!("{f_ab:.0} lb/h"), real: label(r.ff_ab), verdict: verdict(f_ab, r.ff_ab) });

    println!("\n {} [{}] ({set:?} data set) vs public references", r.name, r.section);
    println!(" {:<36} {:<44} {:<46}", "test", "IAF model", "real aircraft (approx., public sources)");
    for r in &rows {
        println!(" {:<36} {:<44} {:<46} {}", r.item, r.iaf, r.real, r.verdict);
    }
}
