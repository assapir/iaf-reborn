//! The Kfir C7's HUD (El-Op HUD on the Elbit System 82 / WDNS-341; docs/real-hud.md "Kfir C2/C7"). Public: the modes
//! (A-A LCOS and hotline, A-G CCIP / direct / toss), the data shown (airspeed, altitude, Mach, AoA, armament status), a
//! pitch ladder, the Python 3 seeker diamond that spins until it locks. The layout is not public: an Elbit early-80s
//! reconstruction [R] — digital airspeed / altitude, a heading scale on top with the steering bug to the waypoint, a
//! waypoint marker on the ground (no F-16 tapes, funnel or SHOOT window).

use super::*;

/// The heading scale: a 30° window, 5° ticks, labels every 10°.
const HDG_WINDOW: f64 = 30.0;
const ROW: f64 = 9.0;

pub(super) fn frame(f: Field, i: &Input) -> Frame {
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let o = &mut fr.outer;
    let y0 = f.centre_y();
    // Airspeed (left) and altitude (right) as numbers, Mach under the airspeed.
    o.push(text((f.left, y0), format!("{:.0}", i.kcas), Align::Right));
    o.push(text((f.left, y0 + ROW), format!("M{:.2}", i.mach), Align::Right));
    o.push(text((f.right, y0), format!("{:.0}", i.alt_ft.round()), Align::Left));
    let bearing = i.steerpoint.map(|s| s.bearing_deg);
    heading(o, f, i.heading_deg, bearing);
    // Lower left: g, AoA (gear down), the mode and the rounds of the selected store; lower right: the waypoint.
    let (lx, ly) = (f.left, f.bottom - 3.0 * ROW);
    o.push(text((lx, ly), format!("{:.1}G", i.g), Align::Right));
    if i.gear_down {
        o.push(text((lx, ly + ROW), format!("AOA {:.0}", i.aoa_deg), Align::Right));
    } else if mode > 0 && w.selected > 0 {
        o.push(text((lx, ly + ROW), format!("{}", w.selected), Align::Right));
    }
    o.push(text((lx, ly + 2.0 * ROW), mode_text(mode, i.target.is_some()), Align::Right));
    if let Some(s) = i.steerpoint {
        o.push(text((f.right, ly + ROW), format!("D{:.1}", s.dist_m / NM), Align::Left));
        o.push(text((f.right, ly + 2.0 * ROW), format!("WP{}", s.number), Align::Left));
    }

    // The field.
    let p = &mut fr.field;
    if mode > 0 {
        let (gx, gy) = i.gun_cross;
        let l = i.mr(6.0);
        p.push(line((gx - l, gy), (gx + l, gy)));
        p.push(line((gx, gy - l), (gx, gy + l)));
    }
    if let Some(fpm) = i.fpm {
        let style = LadderStyle {
            gap: i.deg(1.0),
            len: i.deg(1.8),
            horizon_gap: i.deg(1.0),
            horizon_len: i.deg(3.0),
            tip: i.deg(0.35),
            inner_tips: false,
            bend: false,
            both_labels: true,
            signed: false,
            bottom_band: 3.0 * ROW,
            top_band: 22.0,
            zenith: Zenith::None,
        };
        ladder(p, i, fpm, f, style);
        marker(p, fpm, i.mr(6.0), i.mr(8.0), i.mr(4.0));
        if matches!(mode, 5 | 6) && let Some(c) = w.pipper {
            p.push(line(fpm, c));
        }
    }
    // The waypoint on the ground: a circle on a short post; held on the field's edge (X) when outside it.
    if mode == 0 && let Some(at) = i.steerpoint.and_then(|s| s.at) {
        let (q, limited) = f.clamp_from((0.0, 0.0), at);
        let r = i.mr(5.0);
        p.push(Prim::Circle { c: q, r });
        p.push(line((q.0, q.1 + r), (q.0, q.1 + 2.5 * r)));
        if limited {
            x_over(p, q, r);
        }
    }
    if let Some(t) = i.target
        && let Some(at) = t.at.filter(|a| f.contains(*a))
    {
        let h = i.mr(12.0);
        p.extend(box_poly(at.0 - h, at.1 - h, at.0 + h, at.1 + h));
    }
    match mode {
        1 => seeker(p, i),
        3 => match (w.lcos, i.target) {
            (Some(c), Some(_)) => super::f15::lcos(p, i, c),
            _ => hotline(p, i),
        },
        4..=6 => {
            if let Some(c) = w.pipper {
                pipper(p, c, i.mr(1.0).max(0.8), i.mr(10.0));
            }
        }
        _ => {}
    }
    fr
}

/// The mode window: NAV; A-A LCOS (radar ranging) or HOTL (no range); the missiles; A-G gun, CCIP; TV / HARM.
fn mode_text(mode: i64, ranging: bool) -> &'static str {
    match mode {
        1 | 2 => "MSL",
        3 if ranging => "LCOS",
        3 => "HOTL",
        4 => "STRF",
        5 | 6 => "CCIP",
        7 => "TV",
        8 => "ARM",
        _ => "NAV",
    }
}

/// The heading scale on the field's top, the centre caret and, under it, the steering bug at the waypoint's bearing: a filled triangle under the scale, held at its end with an arrow pointing the way when outside it.
fn heading(p: &mut Vec<Prim>, f: Field, hdg: f64, bearing: Option<f64>) {
    let y = f.top + 6.0;
    let half = 0.5 * (f.right - f.left) - 14.0;
    let k = 2.0 * half / HDG_WINDOW;
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
    p.push(line((0.0, y + 1.0), (-2.5, y + 5.0)));
    p.push(line((0.0, y + 1.0), (2.5, y + 5.0)));
    let Some(b) = bearing else { return };
    let d = (b - hdg + 180.0).rem_euclid(360.0) - 180.0;
    let x = (d * k).clamp(-half, half);
    let (t, s) = (y + 5.0, 4.0);
    p.push(line((x, t), (x - s, t + s)));
    p.push(line((x - s, t + s), (x + s, t + s)));
    p.push(line((x + s, t + s), (x, t)));
    p.push(line((x, t + 1.0), (x, t + s)));
    if d.abs() * k > half {
        let dir = d.signum();
        let ax = x + dir * (s + 6.0);
        p.push(line((ax - dir * 4.0, t + s / 2.0), (ax, t + s / 2.0)));
        p.push(line((ax, t + s / 2.0), (ax - dir * 2.0, t + s / 2.0 - 2.0)));
        p.push(line((ax, t + s / 2.0), (ax - dir * 2.0, t + s / 2.0 + 2.0)));
    }
}

/// The IR seeker diamond: on the target it tracks; searching, it spins at the boresight (Colombian C7 HUD footage of a
/// Python 3 launch [S]).
fn seeker(p: &mut Vec<Prim>, i: &Input) {
    let h = i.mr(8.0);
    match i.weapons.seeker {
        Some(c) => diamond(p, c, h),
        None => {
            let a = i.time_s * std::f64::consts::TAU;
            let c = i.boresight;
            let pts: Vec<P> = (0..4)
                .map(|k| {
                    let (s, co) = (a + f64::from(k) * std::f64::consts::FRAC_PI_2).sin_cos();
                    (c.0 + h * s, c.1 - h * co)
                })
                .collect();
            for k in 0..4 {
                p.push(line(pts[k], pts[(k + 1) % 4]));
            }
        }
    }
}

/// The hotline (A-A gun without a range): the bullet stream's path from the gun cross, ticks at 1,000 / 2,000 / 3,000 ft
/// ([R]: the lead-computing line of the era's sights).
fn hotline(p: &mut Vec<Prim>, i: &Input) {
    let pts: Vec<P> = (0..=12).map(|k| funnel_at(i, 600.0 + 200.0 * f64::from(k), i.g).0).collect();
    p.push(line(i.gun_cross, pts[0]));
    for w in pts.windows(2) {
        p.push(line(w[0], w[1]));
    }
    for r in [1000.0, 2000.0, 3000.0] {
        let (c, _) = funnel_at(i, r, i.g);
        p.push(line((c.0 - 3.0, c.1), (c.0 + 3.0, c.1)));
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    fn frame_in(mode: i64) -> (Input, Frame) {
        let mut i = input(Jet::Kfir);
        i.weapons.hud_mode = mode;
        let fr = frame(FIELD, &i);
        (i, fr)
    }

    #[test]
    fn nav_shows_the_numbers_and_the_way_to_the_waypoint() {
        let (_, fr) = frame_in(0);
        let t = texts(&fr.outer);
        for want in ["352", "M0.85", "10450", "2.3G", "NAV", "D12.0", "WP3", "33", "34"] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        assert!(!t.iter().any(|s| s.contains("EEGS") || *s == "SHOOT" || *s == "C"), "no F-16 symbology: {t:?}");
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Circle { c, .. } if *c == (30.0, 20.0))), "the waypoint marker");
    }

    #[test]
    fn the_steering_bug_holds_at_the_scale_end_with_an_arrow() {
        let bug_lines = |bearing: f64| {
            let mut i = input(Jet::Kfir);
            i.steerpoint.as_mut().unwrap().bearing_deg = bearing;
            frame(FIELD, &i).outer.iter().filter(|p| matches!(p, Prim::Line { .. })).count()
        };
        // 10° right: in the window; 120° right: held at the end, plus the 3-line arrow.
        assert_eq!(bug_lines(120.0 + 333.0), bug_lines(343.0) + 3);
    }

    #[test]
    fn gun_hotline_without_range_lcos_with_it() {
        let (_, fr) = frame_in(3);
        assert!(texts(&fr.outer).contains(&"HOTL"));
        assert!(!fr.field.iter().any(|p| matches!(p, Prim::Arc { .. })), "no LCOS reticle without a range");
        let mut i = input(Jet::Kfir);
        i.weapons.hud_mode = 3;
        i.weapons.lcos = Some((0.0, 20.0));
        i.target = Some(Target { range_m: 600.0, closure: 50.0, at: Some((0.0, 15.0)), aspect: None });
        let fr = frame(FIELD, &i);
        assert!(texts(&fr.outer).contains(&"LCOS"));
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Arc { .. })), "the LCOS reticle and its range arc");
    }

    #[test]
    fn seeker_diamond_spins_until_it_tracks() {
        let (i, fr) = frame_in(1);
        let first_line = |fr: &Frame| fr.field.iter().rev().find_map(|p| if let Prim::Line { a, .. } = p { Some(*a) } else { None });
        let a = first_line(&fr);
        let mut j = i.clone();
        j.time_s = 0.1;
        assert_ne!(a, first_line(&frame(FIELD, &j)), "searching: spinning");
        j.weapons.seeker = Some((10.0, -5.0));
        let fr = frame(FIELD, &j);
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Line { a, .. } if *a == (10.0, -5.0 - j.mr(8.0)))), "tracking");
    }

    #[test]
    fn ccip_pipper_and_fall_line_gear_down_aoa() {
        let mut i = input(Jet::Kfir);
        i.weapons.hud_mode = 5;
        i.weapons.pipper = Some((0.0, 40.0));
        let fr = frame(FIELD, &i);
        assert!(fr.field.contains(&line((0.0, 10.0), (0.0, 40.0))), "the fall line from the marker");
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Dot { c, .. } if *c == (0.0, 40.0))));
        i.weapons.hud_mode = 0;
        i.gear_down = true;
        i.aoa_deg = 13.0;
        assert!(texts(&frame(FIELD, &i).outer).contains(&"AOA 13"));
    }
}
