//! The MiG-29 9.12's ИЛС-31 HUD (СЕИ-31) and its Щель-3УМ helmet sight (docs/mig-cockpits.md §6, docs/real-hud.md
//! "MiG-29"). The layout follows the simulator manuals built on the real jet [SIM]: indicated airspeed in km/h and the
//! height in m as numbers, the heading tape in tens of degrees, a pitch scale on the right, the horizon line and a bank
//! scale, the fixed aircraft cross and the steering circle, the waypoint range in km and the mode name. A-A: the
//! range scale with Rmax / Rmin, «ПР» / «ОТВ», the vertical scan, Ф0, the IR seeker's lock strobe; the gun's ring and
//! cross or the funnel; A-G «ОПТ ЗЕМЛЯ» with the impact pipper.

use super::*;

const ROW: f64 = 9.0;
/// The range scale's steps (km; inferred from [EA]'s 54 / 27 / 13.5 / 5.4 nm).
const SCALES_KM: [f64; 4] = [10.0, 25.0, 50.0, 100.0];
/// The gun ring's range bar: a full turn at this range (m; inferred).
const GUN_FULL_M: f64 = 1200.0;
/// The right-hand pitch scale: px per degree and its half height (px).
const PITCH_K: f64 = 1.5;
const PITCH_HALF: f64 = 24.0;
/// The helmet sight's seeker limits (°): either side, up, down.
const HELMET_SIDE: f64 = 60.0;
const HELMET_UP: f64 = 60.0;
const HELMET_DOWN: f64 = 14.0;

pub(super) fn frame(f: Field, i: &Input) -> Frame {
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let b = i.boresight;
    let o = &mut fr.outer;
    let y0 = f.centre_y();
    // The heading tape in tens of degrees; the numbers: km/h upper left, the height upper right (the radar height to
    // 1 m below 1,000 m, else the barometric height to 10 m).
    super::kfir::heading(o, f, i.heading_deg, None);
    let top = f.top + 2.5 * ROW;
    o.push(text((f.left + 2.0, top), format!("{:.0}", i.kcas * KT_KMH), Align::Left));
    let radar_m = i.agl_ft.map(|a| a * FT).filter(|m| *m < 1000.0);
    let height = match radar_m {
        Some(m) => format!("{:.0}", m.max(0.0)),
        None => format!("{:.0}", (i.alt_ft * FT / 10.0).round() * 10.0),
    };
    o.push(text((f.right - 2.0, top), height, Align::Right));
    pitch_scale(o, f.right - 6.0, y0, i.pitch_deg);
    bank_scale(o, (0.0, y0), 0.33 * (f.bottom - f.top), i.roll_deg);

    // The mode name lower left; the waypoint range bottom centre in NAV; «ПР» / «ОТВ» above it.
    let bottom = f.bottom - 2.0;
    let name = match mode {
        0 if i.gear_down => "ПОС",
        0 => "МРШ",
        1 if i.radar_mode == 6 => "БВБ",
        1 if i.radar_mode == 3 => "Ф0",
        1 => "ТП",
        2 => "ДВБ",
        4..=6 => "ОПТ ЗЕМЛЯ",
        _ => "",
    };
    if !name.is_empty() {
        o.push(text((f.left + 2.0, bottom), name, Align::Left));
    }
    if mode == 0
        && let Some(s) = i.steerpoint
    {
        o.push(text((0.0, bottom), km(s.dist_m), Align::Centre));
    }
    let aa = matches!(mode, 1 | 2);
    let inside_min = matches!((i.target, i.dlz), (Some(t), Some(z)) if t.range_m < z.min);
    if aa && inside_min {
        o.push(text((0.0, bottom - ROW), "ОТВ", Align::Centre));
    } else if aa && w.shoot {
        o.push(text((0.0, bottom - ROW), "ПР", Align::Centre));
    }
    if aa && let Some(t) = i.target {
        km_scale(o, f.left + 12.0, y0 + 4.0, 20.0, t, i.dlz, &SCALES_KM);
    }
    if i.radar_mode == 6 {
        o.push(text((f.left + 2.0, bottom - ROW), "РЛ", Align::Left));
    }

    // The field: the horizon line, the aircraft cross, the steering circle, the targets and the aiming marks.
    let p = &mut fr.field;
    let (sn, cs) = i.roll_deg.to_radians().sin_cos();
    let h = i.horizon;
    let fw = f.right - f.left;
    for side in [-1.0, 1.0] {
        let at = |u: f64| (h.0 + side * u * cs, h.1 - side * u * sn);
        p.push(line(at(0.08 * fw), at(0.33 * fw)));
    }
    let l = i.mr(10.0);
    p.push(line((b.0 - l, b.1), (b.0 + l, b.1)));
    p.push(line((b.0, b.1 - 0.5 * l), (b.0, b.1 + 0.5 * l)));
    let r = i.mr(30.0);
    match mode {
        0 => {
            if let Some(s) = i.steerpoint {
                let d = (s.bearing_deg - i.heading_deg + 180.0).rem_euclid(360.0) - 180.0;
                let reach = (0.5 * (f.right - f.left) - r).max(0.0);
                p.push(Prim::Circle { c: (b.0 + i.deg(d).clamp(-reach, reach), b.1), r });
            }
        }
        2 => {
            if let Some(c) = w.steering {
                p.push(Prim::Circle { c, r });
            }
        }
        _ => {}
    }
    if let Some(at) = i.target.and_then(|t| t.at) {
        let (q, limited) = f.clamp_from(b, at);
        diamond(p, q, i.mr(8.0));
        if limited {
            x_over(p, q, i.mr(8.0));
        }
    }
    // The vertical scan (ACM): two lines from 10° below to 50° above the boresight.
    if i.radar_mode == 6 {
        for dx in [-i.deg(1.0), i.deg(1.0)] {
            p.push(line((b.0 + dx, b.1 + i.deg(10.0)), (b.0 + dx, b.1 - i.deg(50.0))));
        }
    }
    // Ф0 (BORE): the 2.5° circle round the BORE cross the HUD draws.
    if i.radar_mode == 3 {
        p.push(Prim::Circle { c: (0.0, 0.0), r: i.deg(1.25) });
    }
    match mode {
        1 => {
            if let Some(c) = w.seeker {
                p.push(Prim::Circle { c, r: i.mr(10.0) });
            }
        }
        3 => match (w.lcos, i.target) {
            (Some(c), Some(t)) => {
                let (ro, x) = (i.mr(25.0), i.mr(4.0));
                p.push(Prim::Circle { c, r: ro });
                p.push(line((c.0 - x, c.1), (c.0 + x, c.1)));
                p.push(line((c.0, c.1 - x), (c.0, c.1 + x)));
                let sweep = (t.range_m / GUN_FULL_M).clamp(0.0, 1.0) * std::f64::consts::TAU;
                p.push(Prim::Arc { c, r: ro - 1.5, from: 0.0, sweep: sweep.max(0.02) });
            }
            // The funnel for the rounds the game fires (the 20 MM record's, MUZZLE), not the real GSh-30-1's 860 m/s:
            // a funnel that misses its own rounds would mislead.
            _ => funnel_v(p, i, 3000.0, MUZZLE),
        },
        4..=6 => {
            if let Some(c) = w.pipper {
                if mode != 4 {
                    p.push(line(b, c));
                }
                pipper(p, c, i.mr(1.0).max(0.8), i.mr(10.0));
            }
        }
        _ => {}
    }
    fr
}

/// The pitch scale on the right: 5° ticks moving past a fixed caret right of them, labels every 10° left of them.
fn pitch_scale(p: &mut Vec<Prim>, x: f64, y0: f64, pitch: f64) {
    for (t, dy) in ticks(pitch, 5.0, PITCH_K, PITCH_HALF, true) {
        let major = (t.round() as i64).rem_euclid(10) == 0;
        let y = y0 + dy;
        p.push(line((x, y), (x - if major { 5.0 } else { 3.0 }, y)));
        if major {
            p.push(text((x - 7.0, y + 3.0), format!("{:.0}", t), Align::Right));
        }
    }
    p.push(line((x + 1.0, y0), (x + 4.0, y0 - 2.0)));
    p.push(line((x + 1.0, y0), (x + 4.0, y0 + 2.0)));
}

/// The bank scale: ticks at 0, ±15, ±30, ±45° on a lower arc and the index at the roll angle (inferred spacing).
fn bank_scale(p: &mut Vec<Prim>, c: P, r: f64, roll: f64) {
    let at = |deg: f64, rr: f64| {
        let a = std::f64::consts::PI - deg.to_radians();
        (c.0 + rr * a.sin(), c.1 - rr * a.cos())
    };
    for d in [-45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0] {
        p.push(line(at(d, r), at(d, r + if d == 0.0 { 5.0 } else { 3.0 })));
    }
    let roll = roll.clamp(-60.0, 60.0);
    let (tip, l, rr) = (at(roll, r - 1.0), at(roll - 4.0, r - 5.0), at(roll + 4.0, r - 5.0));
    p.push(line(tip, l));
    p.push(line(l, rr));
    p.push(line(rr, tip));
}

/// The Щель-3УМ helmet sight while looking aside: the aiming cross on the head's line of sight (the DASH's), «ШЛЕМ», a
/// flashing «ПР», an X when the head is outside the seeker's limits; the IR seeker on its target.
pub(super) fn helmet(i: &Input) -> Frame {
    let mut fr = Frame::default();
    let o = &mut fr.outer;
    let c = i.head_view;
    super::dash::aiming_cross(o, i);
    o.push(text(add(c, (0.0, i.mr(20.0) + ROW + 2.0)), "ШЛЕМ", Align::Centre));
    if i.weapons.shoot && i.time_s.rem_euclid(0.5) < 0.25 {
        o.push(text(add(c, (0.0, -i.mr(20.0) - 4.0)), "ПР", Align::Centre));
    }
    let (az, el) = i.head_rel_deg;
    if az.abs() > HELMET_SIDE || el > HELMET_UP || el < -HELMET_DOWN {
        x_over(o, c, i.mr(12.0));
    }
    if i.weapons.hud_mode == 1
        && let Some(s) = i.weapons.seeker
    {
        diamond(o, s, i.mr(8.0));
    }
    fr
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    fn with(mode: i64) -> Input {
        let mut i = input(Jet::MiG29);
        i.weapons.hud_mode = mode;
        i
    }

    fn text_at(ps: &[Prim], want: &str) -> Option<P> {
        ps.iter().find_map(|p| match p {
            Prim::Text { at, text, .. } if text == want => Some(*at),
            _ => None,
        })
    }

    #[test]
    fn nav_numbers_in_kmh_and_m_heading_in_tens() {
        let fr = RealHud::default().frame(FIELD, &with(0));
        let t = texts(&fr.outer);
        // 352.4 kt = 653 km/h; 10,450 ft = 3,185 m → 3,190; 333°: "33" on the tape; 12 NM = 22 km; МРШ.
        for want in ["653", "3190", "33", "22", "МРШ"] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        assert!(text_at(&fr.outer, "653").unwrap().0 < 0.0 && text_at(&fr.outer, "3190").unwrap().0 > 0.0);
        assert!(text_at(&fr.outer, "22").unwrap().0 == 0.0, "the waypoint range at the bottom centre");
        assert!(!t.iter().any(|s| s.contains("NAV") || s.contains('M')), "no Western legends: {t:?}");
    }

    #[test]
    fn radar_height_below_1000_m() {
        let mut i = with(0);
        i.agl_ft = Some(2000.0);
        assert!(texts(&frame(FIELD, &i).outer).contains(&"610"));
        i.agl_ft = Some(4000.0);
        assert!(texts(&frame(FIELD, &i).outer).contains(&"3190"), "1,219 m radar: the barometric height");
        i.gear_down = true;
        assert!(texts(&frame(FIELD, &i).outer).contains(&"ПОС"));
    }

    #[test]
    fn the_steering_circle_moves_toward_the_waypoint() {
        let circle_x = |bearing: f64| {
            let mut i = with(0);
            i.steerpoint.as_mut().unwrap().bearing_deg = bearing;
            frame(FIELD, &i).field.iter().find_map(|p| if let Prim::Circle { c, .. } = p { Some(c.0) } else { None })
        };
        assert_eq!(circle_x(333.0), Some(0.0));
        assert!(circle_x(336.0).unwrap() > 30.0);
        assert!(circle_x(200.0).unwrap() < 0.0, "left of the nose, held inside the field");
    }

    #[test]
    fn pitch_scale_labels_and_bank_index() {
        let mut i = with(0);
        i.pitch_deg = 12.0;
        let t = texts(&frame(FIELD, &i).outer).into_iter().map(String::from).collect::<Vec<_>>();
        assert!(t.contains(&"10".into()) && t.contains(&"20".into()) && t.contains(&"0".into()), "{t:?}");
    }

    #[test]
    fn long_range_scale_in_km_with_launch_and_breakaway() {
        let mut i = with(2);
        i.target = Some(Target { range_m: 20_000.0, closure: 300.0, at: Some((10.0, -5.0)), aspect: None });
        i.dlz = Some(Dlz { max: 30_000.0, min: 3000.0 });
        i.weapons.shoot = true;
        let fr = frame(FIELD, &i);
        let t = texts(&fr.outer);
        for want in ["ДВБ", "50", "20", "ПР"] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        i.target.as_mut().unwrap().range_m = 2000.0;
        let t = texts(&frame(FIELD, &i).outer).into_iter().map(String::from).collect::<Vec<_>>();
        assert!(t.contains(&"ОТВ".into()) && !t.contains(&"ПР".into()) && t.contains(&"2.0".into()), "{t:?}");
    }

    #[test]
    fn close_combat_vertical_scan_and_boresight() {
        let mut i = with(1);
        i.radar_mode = 6;
        let fr = frame(FIELD, &i);
        assert!(texts(&fr.outer).contains(&"БВБ") && texts(&fr.outer).contains(&"РЛ"));
        let up = i.deg(50.0);
        assert_eq!(
            fr.field.iter().filter(|p| matches!(p, Prim::Line { b, .. } if (b.1 + up).abs() < 1e-9)).count(),
            2,
            "two vertical lines to 50° up"
        );
        i.radar_mode = 3;
        let fr = frame(FIELD, &i);
        assert!(texts(&fr.outer).contains(&"Ф0"));
        assert!(fr.field.contains(&Prim::Circle { c: (0.0, 0.0), r: i.deg(1.25) }), "the 2.5° circle");
    }

    #[test]
    fn gun_funnel_for_the_games_rounds_and_ring_with_a_lock() {
        let i = Input { g: 4.0, ..with(3) };
        let fr = frame(FIELD, &i);
        let mut m61 = Vec::new();
        funnel(&mut m61, &i, 3000.0);
        let lines = |ps: &[Prim]| ps.iter().filter(|p| matches!(p, Prim::Line { .. })).cloned().collect::<Vec<_>>();
        let ours = lines(&fr.field);
        assert!(m61.iter().all(|l| ours.contains(l)), "the funnel for the rounds the game fires (as the F-16's)");
        let mut j = i.clone();
        j.weapons.lcos = Some((0.0, 25.0));
        j.target = Some(Target { range_m: 600.0, closure: 0.0, at: Some((0.0, 25.0)), aspect: None });
        let fr = frame(FIELD, &j);
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Arc { c, sweep, .. } if *c == (0.0, 25.0) && (*sweep - std::f64::consts::PI).abs() < 1e-9)));
    }

    #[test]
    fn ccip_pipper_and_ground_legend() {
        let mut i = with(5);
        i.weapons.pipper = Some((0.0, 40.0));
        let fr = frame(FIELD, &i);
        assert!(texts(&fr.outer).contains(&"ОПТ ЗЕМЛЯ"));
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Dot { c, .. } if *c == (0.0, 40.0))));
    }

    #[test]
    fn the_helmet_sight_looking_aside() {
        let mut i = Input { off_boresight: true, ..with(1) };
        i.head_view = (40.0, -10.0);
        i.head_rel_deg = (-45.0, 10.0);
        i.weapons.shoot = true;
        let fr = RealHud::default().frame(FIELD, &i);
        let t = texts(&fr.outer);
        assert!(t.contains(&"ШЛЕМ") && t.contains(&"ПР") && fr.field.is_empty(), "{t:?}");
        let lines = fr.outer.iter().filter(|p| matches!(p, Prim::Line { .. })).count();
        i.head_rel_deg = (-75.0, 10.0);
        let fr = RealHud::default().frame(FIELD, &i);
        assert_eq!(fr.outer.iter().filter(|p| matches!(p, Prim::Line { .. })).count(), lines + 2, "the X");
    }
}
