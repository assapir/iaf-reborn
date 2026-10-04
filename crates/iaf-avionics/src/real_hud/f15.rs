//! The F-15A/C HUD (TO 1F-15A-1 figs. 1-14 / 1-15, NADC-75267-40; docs/real-hud.md "F-15A/C"): moving tapes read
//! against fixed carets (no digital boxes), the airspeed increasing downward, the heading scale on top, the "-W-"
//! aircraft symbol, the three-line NAV window; LCOS gunsight (no funnel), TD box / ASE circle / range scale in A-A.

use super::*;

/// Airspeed: a 160 kt window, 10 kt ticks, labels every 50 kt; altitude: a 1,500 ft window, 100 ft ticks, labels
/// every 500 ft; heading: a 30° window, 2° ticks, labels every 10° in tens.
const TAPE_HALF: f64 = 36.0;
const KT_WINDOW: f64 = 160.0;
const FT_WINDOW: f64 = 1500.0;
const HDG_WINDOW: f64 = 30.0;
const ROW: f64 = 9.0;
/// The A-A range scale inboard of the altitude scale.
const RANGE_HALF: f64 = 26.0;
const RANGE_IN: f64 = 12.0;

pub(super) fn frame(f: Field, i: &Input) -> Frame {
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let aa = matches!(mode, 1..=3);
    let o = &mut fr.outer;
    let tape_y = f.centre_y() + if i.gear_down { 10.0 } else { 0.0 };
    // Airspeed (left, increasing downward), altitude (right, increasing upward), heading (top).
    let k_kt = 2.0 * TAPE_HALF / KT_WINDOW;
    let x = f.left;
    o.push(line((x, tape_y - TAPE_HALF), (x, tape_y + TAPE_HALF)));
    for (t, dy) in ticks(i.kcas, 10.0, k_kt, TAPE_HALF, false) {
        if t < 0.0 {
            continue;
        }
        o.push(line((x, tape_y + dy), (x + 3.0, tape_y + dy)));
        if (t as i64) % 50 == 0 {
            o.push(text((x - 2.0, tape_y + dy + 3.0), format!("{}", t as i64), Align::Right));
        }
    }
    o.push(line((x, tape_y), (x + 5.0, tape_y - 3.0)));
    o.push(line((x, tape_y), (x + 5.0, tape_y + 3.0)));
    let k_ft = 2.0 * TAPE_HALF / FT_WINDOW;
    let ax = f.right;
    o.push(line((ax, tape_y - TAPE_HALF), (ax, tape_y + TAPE_HALF)));
    for (t, dy) in ticks(i.alt_ft, 100.0, k_ft, TAPE_HALF, true) {
        o.push(line((ax, tape_y + dy), (ax - 3.0, tape_y + dy)));
        if (t as i64).rem_euclid(500) == 0 {
            o.push(text((ax + 2.0, tape_y + dy + 3.0), format!("{}", t as i64), Align::Left));
        }
    }
    o.push(line((ax, tape_y), (ax - 5.0, tape_y - 3.0)));
    o.push(line((ax, tape_y), (ax - 5.0, tape_y + 3.0)));
    heading(o, f, i.heading_deg);
    // Lower left: G (and Mach in A-A); lower right: the NAV window.
    let (lx, ly) = (f.left, tape_y + TAPE_HALF + 12.0);
    o.push(text((lx, ly), format!("{:.1}G", i.g), Align::Right));
    if aa {
        o.push(text((lx, ly + ROW), format!("{:.2}", i.mach), Align::Right));
    }
    if let Some(s) = i.steerpoint {
        let rx = f.right;
        o.push(text((rx, ly), format!("{}   NAV", s.number), Align::Left));
        o.push(text((rx, ly + ROW), format!("N {:.1}", s.dist_m / NM), Align::Left));
        if let Some(t) = s.eta_s {
            o.push(text((rx, ly + 2.0 * ROW), format!("{} MIN", ((t / 60.0).round() as i64).min(99)), Align::Left));
        }
    }
    if aa && let (Some(t), Some(z)) = (i.target, i.dlz) {
        dlz_scale(o, f.right - RANGE_IN, tape_y, RANGE_HALF, t, z);
        if t.range_m <= z.max && t.range_m >= z.min {
            o.push(text((f.right - RANGE_IN, tape_y + RANGE_HALF + 10.0), "IN RNG", Align::Centre));
        }
    }

    // The field.
    let p = &mut fr.field;
    if mode != 3 {
        waterline(p, i.boresight, i.mr(14.0));
    }
    if mode > 0 {
        let (gx, gy) = i.gun_cross;
        let l = i.mr(8.0);
        p.push(line((gx - l, gy), (gx + l, gy)));
        p.push(line((gx, gy - l), (gx, gy + l)));
    }
    if let Some(fpm) = i.fpm {
        let style = LadderStyle {
            gap: i.deg(1.2),
            len: i.deg(2.4),
            horizon_gap: i.deg(1.2),
            horizon_len: i.deg(4.0),
            tip: i.deg(0.35),
            inner_tips: false,
            bend: false,
            both_labels: true,
            signed: false,
            bottom_band: 0.0,
            top_band: 0.0,
        };
        ladder(p, i, fpm, f, style);
        marker(p, fpm, i.mr(6.0), i.mr(8.0), i.mr(5.0));
        if matches!(mode, 5 | 6) && let Some(c) = w.pipper {
            // No CCIP on the F-15A/C: the bomb fall line to the target square.
            p.push(line(fpm, c));
            let h = i.mr(4.0);
            p.extend(box_poly(c.0 - h, c.1 - h, c.0 + h, c.1 + h));
        }
    }
    if let Some(t) = i.target
        && let Some(at) = t.at.filter(|a| f.contains(*a))
    {
        let h = i.mr(15.0);
        p.extend(box_poly(at.0 - h, at.1 - h, at.0 + h, at.1 + h));
    }
    match mode {
        2 => {
            let c = (0.0, 0.0);
            p.push(Prim::Circle { c, r: i.mr(60.0) * (w.circle / 5.0).clamp(0.3, 1.0) });
            if let Some(s) = w.steering {
                let (q, _) = f.clamp_from(c, s);
                p.push(Prim::Dot { c: q, r: i.mr(3.0) });
            }
        }
        1 => {
            p.push(Prim::Circle { c: (0.0, 0.0), r: i.mr(60.0) });
            if let Some(s) = w.seeker {
                p.push(Prim::Circle { c: s, r: i.mr(6.0) });
            }
        }
        3 => {
            if let Some(c) = w.lcos {
                lcos(p, i, c);
            }
        }
        4 => {
            if let Some(c) = w.pipper {
                lcos(p, i, c);
            }
        }
        _ => {}
    }
    fr
}

/// The heading scale on the field's top: a 30° window, 2° ticks, two-digit labels every 10°, the caret below the line
/// pointing up at the centre.
fn heading(p: &mut Vec<Prim>, f: Field, hdg: f64) {
    let y = f.top + 10.0;
    let half = 0.5 * (f.right - f.left) - 8.0;
    let k = 2.0 * half / HDG_WINDOW;
    p.push(line((-half, y), (half, y)));
    let first = ((hdg - HDG_WINDOW / 2.0) / 2.0).ceil() as i64;
    let last = ((hdg + HDG_WINDOW / 2.0) / 2.0).floor() as i64;
    for n in first..=last {
        let t = n * 2;
        let x = (t as f64 - hdg) * k;
        let major = t.rem_euclid(10) == 0;
        p.push(line((x, y), (x, y - if major { 4.0 } else { 2.0 })));
        if major {
            p.push(text((x, y - 6.0), format!("{:02}", t.rem_euclid(360) / 10), Align::Centre));
        }
    }
    p.push(line((0.0, y + 1.0), (-2.5, y + 5.0)));
    p.push(line((0.0, y + 1.0), (2.5, y + 5.0)));
}

/// The LCOS reticle: a 50 mr outer ring with 12 ticks, a dashed 25 mr inner circle, the pipper; with a lock the range
/// arc on the outer ring, 1,000 ft per tick from 12 o'clock.
fn lcos(p: &mut Vec<Prim>, i: &Input, c: P) {
    let (ro, ri) = (i.mr(25.0), i.mr(12.5));
    p.push(Prim::Circle { c, r: ro });
    for k in 0..12 {
        let a = k as f64 * std::f64::consts::TAU / 12.0;
        let (s, co) = a.sin_cos();
        p.push(line((c.0 + ro * s, c.1 - ro * co), (c.0 + (ro + 2.0) * s, c.1 - (ro + 2.0) * co)));
    }
    for k in 0..4 {
        let from = k as f64 * std::f64::consts::FRAC_PI_2 + 0.2;
        p.push(Prim::Arc { c, r: ri, from, sweep: std::f64::consts::FRAC_PI_2 - 0.4 });
    }
    p.push(Prim::Dot { c, r: i.mr(1.0).max(0.8) });
    if let Some(t) = i.target {
        let sweep = ((t.range_m / FT) / 12_000.0).clamp(0.0, 1.0) * std::f64::consts::TAU;
        p.push(Prim::Arc { c, r: ro - 1.5, from: 0.0, sweep });
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    #[test]
    fn nav_as_the_flight_manual() {
        let fr = frame(FIELD, &input(Jet::F15));
        let t = texts(&fr.outer);
        for want in ["350", "300", "10000", "10500", "2.3G", "3   NAV", "N 12.0", "5 MIN", "33", "34"] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        // Airspeed increasing downward: 400 below the index.
        let y_of = |s: &str| {
            fr.outer.iter().find_map(|p| match p {
                Prim::Text { at, text, .. } if text == s => Some(at.1),
                _ => None,
            })
        };
        assert!(y_of("400").unwrap() > y_of("300").unwrap());
    }
}
