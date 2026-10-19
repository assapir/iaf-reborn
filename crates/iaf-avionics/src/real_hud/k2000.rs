//! The Kurnass 2000's HUD (docs/real-hud.md "F-4E 2000"): the Kaiser / El-Op wide-angle holographic HUD driven by the
//! Elbit ACE-3 mission computer [S]. No symbology figure is public, so the layout is our reconstruction [R] in the
//! MIL-STD-1787 manner of the Elbit era: boxed digital airspeed / altitude (no tapes), the heading scale on top with the
//! steering caret to the waypoint, the flight path marker and a straight-rung ladder, an LCOS gunsight, the missile
//! circle / launch-range scale and a CCIP pipper with its fall line.

use super::*;

/// The heading scale: a 30° window on the field's top; text rows below the boxes.
const HDG_WINDOW: f64 = 30.0;
const ROW: f64 = 9.0;
/// The missile launch-range scale inboard of the altitude box.
const RANGE_HALF: f64 = 26.0;

pub(super) fn frame(f: Field, i: &Input) -> Frame {
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let o = &mut fr.outer;
    let y = f.centre_y() + if i.gear_down { 10.0 } else { 0.0 };
    // Airspeed (left) and altitude (right) in boxes; the radar altitude under the altitude below 5,000 ft.
    boxed(o, f.left, y, format!("{}", i.kcas.round() as i64), Align::Right);
    boxed(o, f.right, y, format!("{}", (i.alt_ft / 10.0).round() as i64 * 10), Align::Left);
    let (lx, rx, ly) = (f.left, f.right, y + 14.0);
    if let Some(a) = i.agl_ft.filter(|a| *a < 5000.0) {
        o.push(text((rx, ly), format!("R{}", (a / 10.0).round() as i64 * 10), Align::Left));
    }
    // Left column: g, Mach, the mode; gear down the AoA.
    o.push(text((lx, ly), format!("{:.1}G", i.g), Align::Right));
    o.push(text((lx, ly + ROW), format!("M{:.2}", i.mach), Align::Right));
    o.push(text((lx, ly + 2.0 * ROW), mode_text(mode), Align::Right));
    if i.gear_down {
        o.push(text((lx, ly + 3.0 * ROW), format!("AOA{:.0}", i.aoa_deg), Align::Right));
    }
    // Right column: the waypoint, its distance and time; the target's range in A-A.
    let mut row = ly + ROW;
    if let Some(s) = i.steerpoint {
        o.push(text((rx, row), format!("WP{} {:.1}", s.number, s.dist_m / NM), Align::Left));
        row += ROW;
        if let Some(t) = s.eta_s {
            let t = t.max(0.0).round() as i64;
            o.push(text((rx, row), format!("{:02}:{:02}", (t / 60).min(99), t % 60), Align::Left));
            row += ROW;
        }
    }
    if matches!(mode, 1..=3)
        && let Some(t) = i.target
    {
        o.push(text((rx, row), format!("{:.1}NM", t.range_m / NM), Align::Left));
    }
    heading(o, f, i.heading_deg, i.steerpoint.map(|s| s.bearing_deg));
    if matches!(mode, 1 | 2)
        && let (Some(t), Some(z)) = (i.target, i.dlz)
    {
        dlz_scale(o, f.right - 10.0, y, RANGE_HALF, t, z);
    }
    if w.shoot {
        o.push(text((0.0, f.bottom - 8.0), "SHOOT", Align::Centre));
    } else if i.fuel_lbs < BINGO_LBS {
        o.push(text((0.0, f.bottom - 8.0), "FUEL", Align::Centre));
    }

    // The field.
    let p = &mut fr.field;
    if mode > 0 {
        let (gx, gy) = i.gun_cross;
        let l = i.mr(8.0);
        p.push(line((gx - l, gy), (gx + l, gy)));
        p.push(line((gx, gy - l), (gx, gy + l)));
    }
    if let Some(fpm) = i.fpm {
        let style = LadderStyle {
            gap: i.deg(1.2),
            len: i.deg(2.6),
            horizon_gap: i.deg(1.2),
            horizon_len: i.deg(5.0),
            tip: i.deg(0.35),
            inner_tips: false,
            bend: false,
            both_labels: true,
            signed: true,
            bottom_band: 0.0,
            top_band: 22.0,
            zenith: Zenith::None,
        };
        ladder(p, i, fpm, f, style);
        marker(p, fpm, i.mr(6.0), i.mr(10.0), i.mr(5.0));
        if matches!(mode, 5 | 6)
            && let Some(c) = w.pipper
        {
            // CCIP: the fall line from the marker to the pipper (a dot in a ring).
            p.push(line(fpm, c));
            pipper(p, c, i.mr(1.0).max(0.8), i.mr(6.0));
        }
    }
    // The waypoint on the ground (a small diamond, an X when held at the field's edge) outside the A-A modes.
    if !matches!(mode, 1..=3)
        && let Some(at) = i.steerpoint.and_then(|s| s.at)
    {
        let (q, limited) = f.clamp_from((0.0, 0.0), at);
        diamond(p, q, i.mr(4.0));
        if limited {
            x_over(p, q, i.mr(3.0));
        }
    }
    if let Some(at) = i.target.and_then(|t| t.at).filter(|a| f.contains(*a)) {
        let h = i.mr(12.0);
        p.extend(box_poly(at.0 - h, at.1 - h, at.0 + h, at.1 + h));
    }
    match mode {
        1 => {
            p.push(Prim::Circle { c: (0.0, 0.0), r: i.mr(60.0) });
            if let Some(s) = w.seeker {
                diamond(p, s, i.mr(5.0));
            }
        }
        2 => {
            p.push(Prim::Circle { c: (0.0, 0.0), r: i.mr(60.0) * (w.circle / 5.0).clamp(0.3, 1.0) });
            if let Some(s) = w.steering {
                let (q, _) = f.clamp_from((0.0, 0.0), s);
                p.push(Prim::Dot { c: q, r: i.mr(3.0) });
            }
        }
        3 => {
            if let Some(c) = w.lcos {
                lcos(p, i, c);
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

fn mode_text(mode: i64) -> &'static str {
    match mode {
        0 => "NAV",
        1 => "SRM",
        2 => "MRM",
        3 => "GUN",
        4 => "STRF",
        5 => "CCIP",
        6 => "LGB",
        7 => "TV",
        8 => "HARM",
        _ => "",
    }
}

/// A boxed readout at the field's edge `x` (its inner side), centred on `y`.
fn boxed(p: &mut Vec<Prim>, x: f64, y: f64, s: String, align: Align) {
    let w = 30.0;
    let (x0, x1) = if align == Align::Right { (x - w, x) } else { (x, x + w) };
    p.extend(box_poly(x0, y - 6.0, x1, y + 5.0));
    let tx = if align == Align::Right { x1 - 2.0 } else { x0 + 2.0 };
    p.push(text((tx, y + 3.0), s, align));
}

/// The heading scale on the field's top: a 30° window, 5° ticks, two-digit labels every 10°, the boxed heading under
/// its centre; the steering caret to the waypoint, a filled triangle above the scale, held at the scale's end with the
/// bearing error when the waypoint is outside the window.
fn heading(p: &mut Vec<Prim>, f: Field, hdg: f64, bearing: Option<f64>) {
    let y = f.top + 10.0;
    let half = 0.5 * (f.right - f.left) - 12.0;
    let k = 2.0 * half / HDG_WINDOW;
    p.push(line((-half, y), (half, y)));
    let first = ((hdg - HDG_WINDOW / 2.0) / 5.0).ceil() as i64;
    let last = ((hdg + HDG_WINDOW / 2.0) / 5.0).floor() as i64;
    for n in first..=last {
        let t = n * 5;
        let x = (t as f64 - hdg) * k;
        let major = t.rem_euclid(10) == 0;
        p.push(line((x, y), (x, y + if major { 4.0 } else { 2.0 })));
        if major && x.abs() > 10.0 {
            p.push(text((x, y + 12.0), format!("{:02}", t.rem_euclid(360) / 10), Align::Centre));
        }
    }
    p.extend(box_poly(-10.0, y + 4.0, 10.0, y + 14.0));
    p.push(text((0.0, y + 12.0), format!("{:03}", (hdg.round() as i64).rem_euclid(360)), Align::Centre));
    if let Some(b) = bearing {
        let err = (b - hdg + 180.0).rem_euclid(360.0) - 180.0;
        let x = (err * k).clamp(-half, half);
        for d in 0..4 {
            let d = d as f64;
            p.push(line((x - 4.0 + d, y - 6.0 + d * 1.5), (x + 4.0 - d, y - 6.0 + d * 1.5)));
        }
        if (err * k).abs() > half {
            let side = if err < 0.0 { Align::Right } else { Align::Left };
            let tx = if err < 0.0 { x - 6.0 } else { x + 6.0 };
            p.push(text((tx, y - 2.0), format!("{:.0}", err.abs()), side));
        }
    }
}

/// The LCOS gunsight: a 25 mr ring around the pipper dot; with a radar range the range arc inside it (12,000 ft = a
/// full turn).
fn lcos(p: &mut Vec<Prim>, i: &Input, c: P) {
    let r = i.mr(25.0);
    p.push(Prim::Circle { c, r });
    p.push(Prim::Dot { c, r: i.mr(1.0).max(0.8) });
    if let Some(t) = i.target {
        let sweep = ((t.range_m / FT) / 12_000.0).clamp(0.0, 1.0) * std::f64::consts::TAU;
        p.push(Prim::Arc { c, r: r - 2.0, from: 0.0, sweep });
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    fn at(mode: i64) -> Input {
        let mut i = input(Jet::Kurnass2000);
        i.weapons.hud_mode = mode;
        i
    }

    #[test]
    fn nav_boxes_and_the_waypoint() {
        let fr = frame(FIELD, &at(0));
        let t = texts(&fr.outer);
        for want in ["352", "10450", "2.3G", "M0.85", "NAV", "WP3 12.0", "05:23", "333"] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Circle { .. })), "the flight path marker");
    }

    #[test]
    fn the_steering_caret_is_held_with_the_bearing_error() {
        let mut i = at(0);
        i.heading_deg = 270.0;
        i.steerpoint.as_mut().unwrap().bearing_deg = 10.0;
        let t = texts(&frame(FIELD, &i).outer).join(" ");
        assert!(t.contains("100"), "100° to the right shown at the scale's end: {t}");
        i.heading_deg = 5.0;
        let t = texts(&frame(FIELD, &i).outer).join(" ");
        assert!(!t.contains(" 5 "), "in the window: no error text: {t}");
    }

    #[test]
    fn weapon_modes() {
        let tgt = Target { range_m: 3000.0, closure: 100.0, at: Some((10.0, -5.0)), aspect: None };
        let mut gun = at(3);
        gun.weapons.lcos = Some((0.0, 20.0));
        gun.target = Some(tgt);
        let f = frame(FIELD, &gun);
        assert!(f.field.iter().any(|p| matches!(p, Prim::Arc { .. })), "LCOS range arc");
        assert!(texts(&f.outer).contains(&"GUN"));
        let mut ccip = at(5);
        ccip.weapons.pipper = Some((0.0, 50.0));
        let f = frame(FIELD, &ccip);
        assert!(f.field.contains(&line((0.0, 10.0), (0.0, 50.0))), "the fall line from the marker");
        let mut mrm = at(2);
        mrm.target = Some(tgt);
        mrm.dlz = Some(Dlz { max: 9000.0, min: 1500.0 });
        mrm.weapons.shoot = true;
        let t = texts(&frame(FIELD, &mrm).outer).join(" ");
        assert!(t.contains("SHOOT") && t.contains("MRM") && t.contains("1.6NM"), "{t}");
    }

    #[test]
    fn gear_down_aoa() {
        let mut i = at(0);
        i.gear_down = true;
        i.aoa_deg = 13.0;
        assert!(texts(&frame(FIELD, &i).outer).contains(&"AOA13"));
    }
}
