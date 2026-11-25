//! The Eitam (docs/ai.md §24.3) on its 6-DoF (the G550, modern-iaf/docs/flight-model.md §9.22) under the steer loop:
//! its standoff orbit, its turns at an airliner's bank and its height, the retreat at the high-speed cruise with the
//! call for help. Skips with a message when `assets/converted/own` is not built.

use std::path::PathBuf;

use iaf_ai::awacs::{self, Contact, Ident};
use iaf_ai::eitam::{ALT_M, BANK_DEG, Eitam, LEG_M, ORBIT_MPS, PULL_M, RETREAT_MPS, station};
use iaf_avionics::fctrl;
use iaf_flight::Vec3;

const KM: f64 = 1000.0;
const DT: f64 = 1.0 / 30.0;

fn own() -> Option<PathBuf> {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/converted/own");
    if dir.join("resource/md/bd.ibx").is_file() && dir.join("iaf.ibx").is_file() {
        Some(dir)
    } else {
        println!("skipped: no assets/converted/own (iaf-sim fm, airbases)");
        None
    }
}

fn flat(a: Vec3, b: Vec3) -> f64 {
    (a.x - b.x).hypot(a.y - b.y)
}

fn mig(key: &str, pos: Vec3, heading: f64) -> Contact {
    Contact { key: key.into(), pos, ground: 0.0, heading, ident: Ident::Hostile, tanker: false }
}

/// The distance from `p` to the segment a–b (horizontal).
fn to_segment(p: Vec3, a: Vec3, b: Vec3) -> f64 {
    let ab = Vec3::new(b.x - a.x, b.y - a.y, 0.0);
    let t = (Vec3::new(p.x - a.x, p.y - a.y, 0.0).dot(ab) / ab.dot(ab)).clamp(0.0, 1.0);
    flat(p, a + ab * t)
}

#[test]
fn the_station_stands_off_the_route_and_covers_the_fight() {
    let Some(dir) = own() else { return };
    let area = Vec3::new(0.0, 150.0 * KM, 0.0);
    let home = Vec3::ZERO;
    for start in [Vec3::new(0.0, 90.0 * KM, 6000.0), Vec3::new(0.0, -20.0 * KM, 6000.0)] {
        let o = station(area, home, start);
        let mut e = Eitam::new(o, &dir).unwrap();
        let (mut far, mut near) = (0.0f64, f64::MAX);
        let (mut bank, mut off_alt, mut off_speed) = (0.0f64, 0.0f64, 0.0f64);
        let clock = std::time::Instant::now();
        let steps = (3600.0 / DT) as usize;
        for i in 0..steps {
            e.step(i as f64 * DT, DT, &[], "Alpha", start);
            far = far.max(flat(e.pos, area));
            near = near.min(to_segment(e.pos, start, area)).min(to_segment(e.pos, home, area));
            if i as f64 * DT > 120.0 {
                bank = bank.max(e.roll.abs());
                off_alt = off_alt.max((e.pos.z - ALT_M).abs());
                off_speed = off_speed.max((e.speed - ORBIT_MPS).abs());
            }
        }
        println!(
            "an hour on station: bank ≤ {bank:.1}°, height ± {off_alt:.0} m, speed ± {off_speed:.1} m/s; {:.1} µs a \
             frame",
            clock.elapsed().as_secs_f64() * 1e6 / steps as f64
        );
        // Never within 15 km of the flight's way, the fight always inside its radar, round its station.
        assert!(near > 15.0 * KM, "near the route: {near}");
        assert!(far < awacs::EITAM_RANGE_M * 0.6, "far from the fight: {far}");
        assert!(flat(e.pos, o.centre) < LEG_M);
        // Flown: an airliner's bank in the racetrack's turns, its height and cruise held as an autopilot does.
        assert!(bank > BANK_DEG - 5.0 && bank < BANK_DEG + 5.0, "bank {bank}");
        assert!(off_alt < 150.0, "height off by {off_alt}");
        assert!(off_speed < 8.0, "speed off by {off_speed}");
    }
}

#[test]
fn a_threat_sends_it_away_with_a_call_for_help() {
    let Some(dir) = own() else { return };
    let o = station(Vec3::new(0.0, 150.0 * KM, 0.0), Vec3::ZERO, Vec3::ZERO);
    let mut e = Eitam::new(o, &dir).unwrap();
    let player = Vec3::new(0.0, 60.0 * KM, 6000.0);
    // A MiG pair 120 km off, pointing at it: not yet (beyond 100 km).
    let here = e.pos;
    let toward = |p: Vec3| fctrl::bearing(p, here) as f64;
    let far = e.pos + Vec3::new(0.0, 120.0 * KM, 7000.0 - ALT_M);
    assert!(e.step(0.0, DT, &[mig("a", far, toward(far))], "Alpha", player).is_empty());
    // At 90 km, cold: no threat; hot: the call and the retreat.
    let at = e.pos + Vec3::new(0.0, 90.0 * KM, 7000.0 - ALT_M);
    assert!(e.step(1.0, DT, &[mig("a", at, (toward(at) + 180.0) % 360.0)], "Alpha", player).is_empty());
    let pair = [mig("a", at, toward(at)), mig("b", at + Vec3::new(900.0, 0.0, 300.0), toward(at))];
    let calls = e.step(2.0, DT, &pair, "Alpha", player);
    assert_eq!(calls.len(), 1);
    let (t, args, named) = &calls[0];
    assert!(named.hostile && named.miles == awacs::miles(flat(player, at)));
    assert_eq!(*t, "AWX_HELP");
    assert_eq!(args[0], "Alpha_r");
    assert_eq!(args[3], "AWX_ALT25");
    assert!(flat(e.orbit.centre, at) > flat(o.centre, at) + PULL_M * 0.9, "the station pulled back");
    // It turns away (no harder than its bank) and runs; the call comes again only after a minute.
    let start = flat(e.pos, at);
    let mut bank = 0.0f64;
    let mut now = 2.0;
    while now < 61.9 {
        now += DT;
        assert!(e.step(now, DT, &pair, "Alpha", player).is_empty(), "a call at {now}");
        bank = bank.max(e.roll.abs());
    }
    assert!(bank < BANK_DEG + 5.0, "bank {bank}");
    assert_eq!(e.step(62.5, DT, &pair, "Alpha", player).len(), 1);
    // Running until it is clear (out of the threat's range, then 30 s): turned away, at the high-speed cruise within
    // the G550's thrust up there, never past it.
    now = 62.5;
    let (mut fastest, mut ran) = (0.0f64, 0.0f64);
    while e.threat.is_some() && now < 400.0 {
        now += DT;
        e.step(now, DT, &pair, "Alpha", player);
        fastest = fastest.max(e.speed);
        ran = ran.max(flat(e.pos, at) - start);
    }
    println!(
        "retreat: clear at {now:.0} s, {:.0} km away, fastest {fastest:.1} m/s (M0.85 {RETREAT_MPS:.1})",
        ran / KM
    );
    assert!(e.threat.is_none(), "still threatened at {now}");
    // (The autothrottle overshoots by a few m/s as it reaches it; never past the G550's Mmo, Mach 0.885.)
    assert!(fastest > RETREAT_MPS - 3.0 && fastest < 0.885 * 295.07, "the high-speed cruise: {fastest}");
    assert!(ran > 15.0 * KM, "running away: {ran}");
    // Clear for 30 s: back on (the pulled-back) station, at the long-range cruise.
    let back = now + 120.0;
    while now < back {
        now += DT;
        e.step(now, DT, &[], "Alpha", player);
    }
    assert!((e.speed - ORBIT_MPS).abs() < 3.0, "back at the long-range cruise: {}", e.speed);
    // A second threat: the station pulled from the planned one again, never further.
    let pulled = e.orbit.centre;
    let at2 = e.pos + Vec3::new(0.0, 40.0 * KM, 0.0);
    assert_eq!(e.step(now + 1.0, DT, &[mig("c", at2, 0.0)], "Alpha", player).len(), 1);
    assert!((flat(e.orbit.centre, o.centre) - PULL_M).abs() < 1.0 && flat(pulled, o.centre) <= PULL_M + 1.0);
    // Down: no sensor, no calls.
    e.alive = false;
    assert_eq!(e.sensor(), awacs::Sensor::Lost);
    assert!(e.step(now + 2.0, DT, &pair, "Alpha", player).is_empty());
}
