//! The Lavi's HUD (docs/real-hud.md "Lavi"): a Hughes wide-angle diffractive HUD driven by Elbit's display system
//! [S]; its symbology was never published, so the layout is our reconstruction [R] of a late-1980s US / Israeli
//! wide-angle HUD (MIL-STD-1787 conventions, digital boxes as the F/A-18's): boxed airspeed left and altitude right,
//! the heading scale on top with the steering bug, straight climb / dive bars, LCOS for the gun, CCIP for bombs.

use super::*;

/// The heading scale: a 30° window, 5° ticks, labels every 10°; the data rows' spacing.
const HDG_WINDOW: f64 = 30.0;
const ROW: f64 = 9.0;
/// The boxes and data blocks this far in from the field's sides (`Field::inset`).
const INSET: f64 = 6.0;
/// The A-A launch-zone scale inboard of the altitude box.
const RANGE_HALF: f64 = 26.0;
const RANGE_IN: f64 = 14.0;

pub(super) fn frame(f: Field, i: &Input) -> Frame {
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let o = &mut fr.outer;
    let sc = f.inset(INSET);
    let y0 = f.centre_y();
    // Boxed airspeed (KCAS) left, barometric altitude right; under them Mach / G / AoA and the radar altitude.
    o.extend(box_poly(sc.left - 30.0, y0 - 6.0, sc.left - 2.0, y0 + 5.0));
    o.push(text((sc.left - 4.0, y0 + 3.0), format!("{}", i.kcas.round() as i64), Align::Right));
    o.extend(box_poly(sc.right + 2.0, y0 - 6.0, sc.right + 36.0, y0 + 5.0));
    o.push(text((sc.right + 34.0, y0 + 3.0), format!("{}", i.alt_ft.round() as i64), Align::Right));
    let (lx, rx, ry) = (sc.left - 2.0, sc.right + 2.0, y0 + 5.0 + ROW + 2.0);
    let mut left = vec![format!("M {:.2}", i.mach), format!("G {:.1}", i.g)];
    if i.gear_down {
        left.push(format!("AOA {:.1}", i.aoa_deg));
    }
    left.push(mode_text(mode, w));
    if w.shoot {
        left.push("SHOOT".into());
    }
    for (n, r) in left.into_iter().enumerate() {
        o.push(text((lx, ry + n as f64 * ROW), r, Align::Right));
    }
    let mut right = Vec::new();
    if let Some(a) = i.agl_ft.filter(|a| *a < 5000.0) {
        right.push(format!("R {}", a.round() as i64));
    }
    // The steerpoint block: number, distance (NM), time to go.
    if let Some(s) = i.steerpoint {
        right.push(format!("WP {}", s.number));
        right.push(format!("{:.1} NM", s.dist_m / NM));
        if let Some(t) = s.eta_s {
            let t = t.max(0.0).round() as i64;
            right.push(format!("{:02}:{:02}", (t / 60).min(99), t % 60));
        }
    }
    for (n, r) in right.into_iter().enumerate() {
        o.push(text((rx, ry + n as f64 * ROW), r, Align::Left));
    }
    heading(o, f, i.heading_deg, i.steerpoint.map(|s| s.bearing_deg));
    if matches!(mode, 1 | 2) && let (Some(t), Some(z)) = (i.target, i.dlz) {
        dlz_scale(o, sc.right - RANGE_IN, y0, RANGE_HALF, t, z);
    }

    // The field: the ladder and the flight path marker, the steerpoint, the weapon symbols.
    let p = &mut fr.field;
    // The gun cross for strafing (in A-A the LCOS reticle is the reference).
    if mode == 4 {
        let (gx, gy) = i.gun_cross;
        let l = i.mr(6.0);
        p.push(line((gx - l, gy), (gx + l, gy)));
        p.push(line((gx, gy - l), (gx, gy + l)));
    }
    if let Some(fpm) = i.fpm {
        let style = LadderStyle {
            gap: i.deg(1.5),
            len: i.deg(2.5),
            horizon_gap: i.deg(1.5),
            horizon_len: i.deg(5.0),
            tip: i.deg(0.4),
            inner_tips: false,
            bend: false,
            both_labels: true,
            signed: true,
            bottom_band: 0.0,
            top_band: 22.0,
            zenith: Zenith::None,
        };
        ladder(p, i, fpm, f, style);
        marker(p, fpm, i.mr(7.0), i.mr(9.0), i.mr(6.0));
        if matches!(mode, 5 | 6) && let Some(c) = w.pipper {
            // CCIP: the bomb fall line from the marker to the pipper.
            p.push(line(fpm, c));
            pipper(p, c, i.mr(1.0).max(0.8), i.mr(8.0));
        }
    }
    // The steerpoint on the ground in NAV and A-G; an X when held at the field's edge.
    if !matches!(mode, 1..=3) && let Some(s) = i.steerpoint.and_then(|s| s.at) {
        let (q, held) = f.clamp_from(i.boresight, s);
        diamond(p, q, i.mr(5.0));
        if held {
            x_over(p, q, i.mr(5.0));
        }
    }
    if mode > 0 && let Some(at) = i.target.and_then(|t| t.at).filter(|a| f.contains(*a)) {
        let h = i.mr(12.0);
        p.extend(box_poly(at.0 - h, at.1 - h, at.0 + h, at.1 + h));
    }
    match mode {
        1 => {
            p.push(Prim::Circle { c: (0.0, 0.0), r: i.mr(50.0) });
            if let Some(s) = w.seeker {
                diamond(p, s, i.mr(5.0));
            }
        }
        2 => {
            p.push(Prim::Circle { c: (0.0, 0.0), r: i.mr(50.0) * (w.circle / 5.0).clamp(0.3, 1.0) });
            if let Some(s) = w.steering {
                let (q, _) = f.clamp_from((0.0, 0.0), s);
                p.push(Prim::Dot { c: q, r: i.mr(3.0) });
            }
        }
        3 => {
            if let Some(c) = w.lcos {
                f15::lcos(p, i, c);
            }
        }
        4 => {
            if let Some(c) = w.pipper {
                pipper(p, c, i.mr(1.0).max(0.8), i.mr(6.0));
            }
        }
        _ => {}
    }
    fr
}

fn mode_text(mode: i64, w: &Weapons) -> String {
    match mode {
        1 => format!("SRM {}", w.srm),
        2 => format!("MRM {}", w.mrm),
        3 => "GUN".into(),
        4 => "STRF".into(),
        5 | 6 => "CCIP".into(),
        7 => "TV".into(),
        8 => "ARM".into(),
        _ => "NAV".into(),
    }
}

/// The heading scale on the field's top: a 30° window, 5° ticks, two-digit labels every 10°, the boxed heading under
/// the centre. The steering bug (a V) sits at the steerpoint's bearing; outside the window it is held at the scale's
/// end as an arrow pointing the way to turn, with the bearing beside it.
fn heading(p: &mut Vec<Prim>, f: Field, hdg: f64, bearing: Option<f64>) {
    let y = f.top + 8.0;
    let half = 0.5 * (f.right - f.left) - 10.0;
    let k = 2.0 * half / HDG_WINDOW;
    p.push(line((-half, y), (half, y)));
    let first = ((hdg - HDG_WINDOW / 2.0) / 5.0).ceil() as i64;
    let last = ((hdg + HDG_WINDOW / 2.0) / 5.0).floor() as i64;
    for n in first..=last {
        let t = n * 5;
        let x = (t as f64 - hdg) * k;
        let major = t.rem_euclid(10) == 0;
        p.push(line((x, y), (x, y - if major { 4.0 } else { 2.0 })));
        if major {
            p.push(text((x, y - 6.0), format!("{:02}", t.rem_euclid(360) / 10), Align::Centre));
        }
    }
    p.extend(box_poly(-12.0, y + 2.0, 12.0, y + 12.0));
    p.push(text((0.0, y + 10.0), format!("{:03}", (hdg.round() as i64).rem_euclid(360)), Align::Centre));
    let Some(b) = bearing else { return };
    let d = (b - hdg + 180.0).rem_euclid(360.0) - 180.0;
    if d.abs() <= HDG_WINDOW / 2.0 {
        // Above the labels, pointing down at the scale.
        let x = d * k;
        p.push(line((x - 3.5, y - 22.0), (x, y - 16.0)));
        p.push(line((x + 3.5, y - 22.0), (x, y - 16.0)));
        p.push(line((x, y - 16.0), (x, y - 14.0)));
    } else {
        let s = d.signum();
        let x = s * (half + 3.0);
        p.push(line((x, y), (x + s * 6.0, y)));
        p.push(line((x + s * 6.0, y), (x + s * 2.0, y - 3.0)));
        p.push(line((x + s * 6.0, y), (x + s * 2.0, y + 3.0)));
        let label = format!("{:03}", (b.round() as i64).rem_euclid(360));
        p.push(text((x + s * 8.0, y + 3.0), label, if s > 0.0 { Align::Left } else { Align::Right }));
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    #[test]
    fn nav_boxes_and_steering() {
        let fr = frame(FIELD, &input(Jet::Lavi));
        let t = texts(&fr.outer);
        for want in ["352", "10450", "M 0.85", "G 2.3", "NAV", "WP 3", "12.0 NM", "05:23", "333", "33", "34"] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        // The steerpoint at bearing 10° is 37° right of 333°: the bug held at the right end with "010".
        assert!(t.contains(&"010"), "{t:?}");
        let mut i = input(Jet::Lavi);
        i.heading_deg = 5.0;
        let t = texts(&frame(FIELD, &i).outer).into_iter().map(String::from).collect::<Vec<_>>();
        assert!(!t.contains(&"010".to_string()), "inside the window: the V bug, no label");
        assert!(frame(FIELD, &input(Jet::Lavi)).field.iter().any(|p| matches!(p, Prim::Line { .. })));
    }

    #[test]
    fn weapons_per_mode() {
        let mut i = input(Jet::Lavi);
        i.weapons.hud_mode = 3;
        i.weapons.lcos = Some((0.0, 30.0));
        let gun = frame(FIELD, &i);
        assert!(texts(&gun.outer).contains(&"GUN"));
        assert!(gun.field.iter().any(|p| matches!(p, Prim::Circle { c, .. } if *c == (0.0, 30.0))), "the LCOS reticle");
        i.weapons.hud_mode = 5;
        i.weapons.pipper = Some((4.0, 50.0));
        let ccip = frame(FIELD, &i);
        assert!(texts(&ccip.outer).contains(&"CCIP"));
        assert!(ccip.field.iter().any(|p| matches!(p, Prim::Line { a, b } if *a == (0.0, 10.0) && *b == (4.0, 50.0))), "the fall line");
        i.weapons.hud_mode = 1;
        i.weapons.srm = 2;
        i.weapons.shoot = true;
        let srm = frame(FIELD, &i);
        assert!(texts(&srm.outer).contains(&"SRM 2") && texts(&srm.outer).contains(&"SHOOT"));
        let mut g = input(Jet::Lavi);
        g.gear_down = true;
        g.aoa_deg = 13.0;
        g.agl_ft = Some(420.0);
        let t = texts(&frame(FIELD, &g).outer).into_iter().map(String::from).collect::<Vec<_>>();
        assert!(t.contains(&"AOA 13.0".to_string()) && t.contains(&"R 420".to_string()), "{t:?}");
    }
}
