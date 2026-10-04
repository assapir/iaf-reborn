//! The F-16C/D HUD (T.O. GR1F-16CJ-34-1-1 figs. 1-110 / 1-111 / 1-115 and the A-A / A-G chapters; docs/real-hud.md
//! "F-16C/D"). Also drawn for the Lavi and, as marked reconstructions, the Kurnass 2000 and the Kfir.

use super::*;

/// Scales: airspeed 0.6 px per kt (10 kt ticks, labels every 50 kt in tens), altitude 0.06 px per ft (100 ft ticks,
/// labels every 500 ft in hundreds with a thousands comma), heading 2 px per degree (5° ticks, labels every 10° in
/// tens); their half heights / widths.
const KT_PX: f64 = 0.6;
const FT_PX: f64 = 0.06;
const HDG_PX: f64 = 2.0;
const TAPE_HALF: f64 = 36.0;
const HDG_HALF: f64 = 34.0;
/// The DLZ scale: half height, 10 px inboard of the altitude scale, which moves 12 px outward while it shows.
const DLZ_HALF: f64 = 24.0;
const DLZ_IN: f64 = 10.0;
const ALT_OUT: f64 = 12.0;
/// Data rows 9 px apart.
const ROW: f64 = 9.0;

pub(super) fn frame(f: Field, i: &Input, max_g: f64) -> Frame {
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let o = &mut fr.outer;
    let tape_y = f.centre_y() - 6.0;
    let dlz = matches!(mode, 1 | 2).then_some(()).and(i.target.zip(i.dlz));
    // Scales.
    airspeed(o, f.left, tape_y, i.kcas);
    o.push(text((f.left + 3.0, tape_y - TAPE_HALF - 4.0), format!("{:.1}", i.g), Align::Left));
    let alt_x = f.right + if dlz.is_some() { ALT_OUT } else { 0.0 };
    altitude(o, alt_x, tape_y, i.alt_ft);
    if let Some((t, z)) = dlz {
        dlz_scale(o, f.right - DLZ_IN, tape_y, DLZ_HALF, t, z);
    }
    // The heading scale: the lower position (below the scales) in NAV, A-A and strafe; the upper one in the A-G modes
    // and gear down.
    let hdg_y = if i.gear_down || matches!(mode, 5..=7) { f.top + 10.0 } else { tape_y + TAPE_HALF + 6.0 };
    heading(o, hdg_y, i.heading_deg, i.steerpoint.map(|s| s.bearing_deg));
    if mode != 3 {
        roll_indicator(o, i);
    }
    // The left column: ARM, Mach, max g, the mode / weapon.
    let (lx, ly) = (f.left + 4.0, tape_y + TAPE_HALF + 12.0);
    let mut row = 0.0;
    if mode > 0 {
        o.push(text((lx, ly), "ARM", Align::Right));
        row += ROW;
    }
    o.push(text((lx, ly + row), format!("{:.2}", i.mach), Align::Right));
    o.push(text((lx, ly + row + ROW), format!("{max_g:.1}"), Align::Right));
    o.push(text((lx, ly + row + 2.0 * ROW), mode_text(w), Align::Right));
    // The right column: radar altitude, slant range, time, steerpoint.
    let (rx, ry) = (alt_x + 2.0, tape_y + TAPE_HALF + 12.0);
    let mut rows = Vec::new();
    if let Some(a) = i.agl_ft.filter(|a| *a < 50_000.0) {
        rows.push(format!("R {}", thousands(a)));
    }
    match (i.target, i.steerpoint) {
        (Some(t), _) => rows.push(slant('F', t.range_m)),
        (None, Some(s)) => rows.push(slant('B', s.dist_m)),
        _ => {}
    }
    if mode == 3 && let Some(t) = i.target {
        rows.push(format!("{}", (t.closure * MS_TO_KT).round() as i64));
    } else if let Some(t) = i.steerpoint.and_then(|s| s.eta_s) {
        let t = t.max(0.0).round() as i64;
        rows.push(format!("{:02}:{:02}", (t / 60).min(99), t % 60));
    }
    if let Some(s) = i.steerpoint {
        rows.push(format!("{:03}>{:02}", ((s.dist_m / NM).round() as i64).min(999), s.number));
    }
    for (n, r) in rows.into_iter().enumerate() {
        o.push(text((rx, ry + n as f64 * ROW), r, Align::Left));
    }
    if i.fuel_lbs < BINGO_LBS {
        o.push(text((0.0, i.gun_cross.1 + i.mr(70.0)), "FUEL", Align::Centre));
    }

    // The field: boresight cross, ladder, marker, AoA bracket, steerpoint, target, weapon symbols.
    let p = &mut fr.field;
    boresight_cross(p, i);
    if let Some(fpm) = i.fpm {
        let style = LadderStyle {
            gap: i.deg(1.4),
            len: i.deg(2.6),
            horizon_gap: i.deg(1.4),
            horizon_len: i.deg(4.2),
            tip: i.deg(0.35),
            inner_tips: false,
            bend: true,
            both_labels: true,
            signed: false,
            bottom_band: f.bottom - hdg_y + 12.0,
            top_band: 0.0,
        };
        ladder(p, i, fpm, f, style);
        marker(p, fpm, i.mr(5.0), i.mr(10.0), i.mr(5.0));
        if i.gear_down {
            aoa_bracket(p, i, fpm);
        }
        if matches!(mode, 5 | 6) && let Some(c) = w.pipper {
            p.push(line(fpm, c));
        }
    }
    if let Some(s) = i.steerpoint.filter(|_| !matches!(mode, 1..=3))
        && let Some(at) = s.at
    {
        let (q, limited) = f.clamp_from(i.boresight, at);
        diamond(p, q, i.mr(3.0));
        if limited {
            x_over(p, q, i.mr(3.0));
        }
    }
    if let Some(t) = i.target
        && let Some(at) = t.at
    {
        target_box(p, i, f, at, mode == 3, t);
    }
    match mode {
        1 => {
            let c = add(i.gun_cross, (0.0, i.deg(3.0)));
            p.push(Prim::Circle { c, r: i.mr(32.5) });
            if let Some(s) = w.seeker {
                diamond(p, s, i.mr(5.0));
            }
        }
        2 => {
            let c = add(i.gun_cross, (0.0, i.deg(6.0)));
            p.push(Prim::Circle { c, r: i.mr(56.0) * (w.circle / 5.0).clamp(0.3, 1.0) });
            if let Some(s) = w.steering {
                let (q, limited) = f.clamp_from(c, s);
                p.push(Prim::Circle { c: q, r: i.mr(4.0) });
                if limited {
                    x_over(p, q, i.mr(4.0));
                }
            }
        }
        3 => funnel(p, i),
        4..=6 => {
            if let Some(c) = w.pipper {
                pipper(p, c, i.mr(0.5).max(0.8), i.mr(6.0));
            }
        }
        _ => {}
    }
    fr
}

/// The operating mode / weapon window (8): NAV, "6 SRM", "3 MRM", EEGS, STRF, CCIP, PRE (Maverick / TV), HARM.
fn mode_text(w: &Weapons) -> String {
    match w.hud_mode {
        1 => format!("{} SRM", w.srm),
        2 => format!("{} MRM", w.mrm),
        3 => "EEGS".into(),
        4 => "STRF".into(),
        5 | 6 => "CCIP".into(),
        7 => "PRE".into(),
        8 => "HARM".into(),
        _ => "NAV".into(),
    }
}

/// "19,500".
fn thousands(ft: f64) -> String {
    let a = (ft / 10.0).round() as i64 * 10;
    if a.abs() >= 1000 { format!("{},{:03}", a / 1000, (a % 1000).abs()) } else { format!("{a}") }
}

/// The slant range window (10): the sensor letter and NM in tenths ("B115.0", "F02.5"); below 1 NM hundreds of feet
/// ("F 060").
fn slant(letter: char, m: f64) -> String {
    if m < NM { format!("{letter} {:03}", (m / FT / 100.0).round() as i64) } else { format!("{letter}{:04.1}", m / NM) }
}

/// The airspeed scale (left edge): ticks inward, labels every 50 kt in tens outside, the boxed readout with its caret
/// at the index and the "C" (calibrated) mnemonic beside it.
fn airspeed(p: &mut Vec<Prim>, x: f64, y0: f64, kcas: f64) {
    p.push(line((x, y0 - TAPE_HALF), (x, y0 + TAPE_HALF)));
    for (t, dy) in ticks(kcas, 10.0, KT_PX, TAPE_HALF, true) {
        if t < 0.0 {
            continue;
        }
        let major = (t as i64) % 50 == 0;
        p.push(line((x, y0 + dy), (x + if major { 5.0 } else { 3.0 }, y0 + dy)));
        if major && dy.abs() > 8.0 {
            p.push(text((x - 2.0, y0 + dy + 3.0), format!("{}", t as i64 / 10), Align::Right));
        }
    }
    let (bx, by) = (x - 2.0, y0);
    p.extend(box_poly(bx - 26.0, by - 5.0, bx - 4.0, by + 5.0));
    p.push(line((bx - 4.0, by - 5.0), (bx, by)));
    p.push(line((bx, by), (bx - 4.0, by + 5.0)));
    p.push(text((bx - 6.0, by + 3.0), format!("{}", kcas.max(0.0).round() as i64), Align::Right));
    p.push(text((x + 7.0, y0 + 3.0), "C", Align::Left));
}

/// The altitude scale (right edge): ticks inward, labels every 500 ft ("20,5") outside, the boxed readout "20,000"
/// with its caret.
fn altitude(p: &mut Vec<Prim>, x: f64, y0: f64, alt_ft: f64) {
    p.push(line((x, y0 - TAPE_HALF), (x, y0 + TAPE_HALF)));
    for (t, dy) in ticks(alt_ft, 100.0, FT_PX, TAPE_HALF, true) {
        let major = (t as i64).rem_euclid(500) == 0;
        p.push(line((x, y0 + dy), (x - if major { 5.0 } else { 3.0 }, y0 + dy)));
        if major && dy.abs() > 8.0 {
            let h = (t / 100.0).round() as i64;
            p.push(text((x + 2.0, y0 + dy + 3.0), format!("{},{}", h.div_euclid(10), h.rem_euclid(10)), Align::Left));
        }
    }
    let (bx, by) = (x + 2.0, y0);
    p.extend(box_poly(bx + 4.0, by - 5.0, bx + 34.0, by + 5.0));
    p.push(line((bx + 4.0, by - 5.0), (bx, by)));
    p.push(line((bx, by), (bx + 4.0, by + 5.0)));
    p.push(text((bx + 32.0, by + 3.0), thousands(alt_ft), Align::Right));
}

/// The heading scale: 5° ticks, labels every 10° in tens either side of the boxed heading ("06 [070] 08"); the
/// steering tick at the steerpoint's bearing.
fn heading(p: &mut Vec<Prim>, y: f64, hdg: f64, bearing: Option<f64>) {
    let first = ((hdg - HDG_HALF / HDG_PX) / 5.0).ceil() as i64;
    let last = ((hdg + HDG_HALF / HDG_PX) / 5.0).floor() as i64;
    for n in first..=last {
        let t = n * 5;
        let x = (t as f64 - hdg) * HDG_PX;
        if x.abs() < 14.0 {
            continue; // under the box
        }
        let major = t.rem_euclid(10) == 0;
        p.push(line((x, y - 8.0), (x, y - if major { 12.0 } else { 10.0 })));
        if major {
            p.push(text((x, y), format!("{:02}", t.rem_euclid(360) / 10), Align::Centre));
        }
    }
    p.extend(box_poly(-12.0, y - 8.0, 12.0, y + 2.0));
    p.push(text((0.0, y), format!("{:03}", (hdg.round() as i64).rem_euclid(360)), Align::Centre));
    if let Some(b) = bearing {
        let d = (b - hdg + 180.0).rem_euclid(360.0) - 180.0;
        let x = (d * HDG_PX).clamp(-HDG_HALF, HDG_HALF);
        p.push(line((x, y + 3.0), (x, y + 7.0)));
    }
}

/// The roll indicator: tics on a 70 mr arc centred 50 mr below the HUD centre, every 10° to ±30° and at ±45°, and the
/// pointer at the bank angle (limited to ±45°).
fn roll_indicator(p: &mut Vec<Prim>, i: &Input) {
    let c = (0.0, i.mr(50.0));
    let r = i.mr(70.0);
    let at = |deg: f64, rr: f64| {
        let a = deg.to_radians();
        (c.0 - rr * a.sin(), c.1 + rr * a.cos())
    };
    for d in [-45.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 45.0] {
        p.push(line(at(d, r), at(d, r + if d == 0.0 { 4.0 } else { 2.5 })));
    }
    let b = i.roll_deg.clamp(-45.0, 45.0);
    let tip = at(b, r - 1.0);
    let (l, rr) = (at(b - 3.0, r - 5.0), at(b + 3.0, r - 5.0));
    p.push(line(tip, l));
    p.push(line(l, rr));
    p.push(line(rr, tip));
}

/// The boresight cross: an incomplete plus (a centre gap) at the gun cross.
fn boresight_cross(p: &mut Vec<Prim>, i: &Input) {
    let (x, y) = i.gun_cross;
    let (g, l) = (i.mr(2.0), i.mr(8.0));
    p.push(line((x - l, y), (x - g, y)));
    p.push(line((x + g, y), (x + l, y)));
    p.push(line((x, y - l), (x, y - g)));
    p.push(line((x, y + g), (x, y + l)));
}

/// The AoA bracket left of the marker (gear down): the marker at its top at 11°, centred at 13°, at its bottom at 15°.
fn aoa_bracket(p: &mut Vec<Prim>, i: &Input, (x, y): P) {
    let bx = x - i.mr(5.0) - i.mr(10.0) - 3.0;
    let (top, bottom) = (y + i.deg(i.aoa_deg - 15.0), y + i.deg(i.aoa_deg - 11.0));
    p.push(line((bx, top), (bx, bottom)));
    p.push(line((bx, top), (bx + 3.0, top)));
    p.push(line((bx, bottom), (bx + 3.0, bottom)));
}

/// The target designator: a 25 mr box (A-A gun: the TD circle with its range arc, 1,000 ft per clock hour, full beyond
/// 2 NM); off the field a 40 mr locator line from the gun cross toward it.
fn target_box(p: &mut Vec<Prim>, i: &Input, f: Field, at: P, gun: bool, t: Target) {
    if !f.contains(at) {
        let d = (at.0 - i.gun_cross.0, at.1 - i.gun_cross.1);
        let l = (d.0 * d.0 + d.1 * d.1).sqrt().max(1e-6);
        p.push(line(i.gun_cross, add(i.gun_cross, (d.0 / l * i.mr(40.0), d.1 / l * i.mr(40.0)))));
        return;
    }
    let h = i.mr(12.5);
    if gun {
        p.push(Prim::Circle { c: at, r: h });
        let ft = t.range_m / FT;
        let sweep = if t.range_m > 2.0 * NM { std::f64::consts::TAU } else { (ft / 12_000.0).min(1.0) * std::f64::consts::TAU };
        p.push(Prim::Arc { c: at, r: h + 1.5, from: 0.0, sweep });
    } else {
        p.extend(box_poly(at.0 - h, at.1 - h, at.0 + h, at.1 + h));
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    #[test]
    fn nav_windows_as_the_dash_34() {
        let mut i = input(Jet::F16);
        i.agl_ft = Some(19_500.0);
        let fr = frame(FIELD, &i, 4.1);
        let t = texts(&fr.outer);
        for want in ["352", "C", "10,450", "2.3", "0.85", "4.1", "NAV", "R 19,500", "B12.0", "05:23", "012>03", "333", "32", "34"] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        assert!(!t.contains(&"ARM"), "NAV: no ARM");
    }

    #[test]
    fn weapon_modes() {
        let mut i = input(Jet::F16);
        i.weapons = Weapons { hud_mode: 2, mrm: 3, circle: 4.0, ..Weapons::default() };
        i.target = Some(Target { range_m: 15.0 * NM, closure: 200.0, at: Some((5.0, -5.0)) });
        i.dlz = Some(Dlz { max: 18.0 * NM, min: 2.0 * NM });
        let t = frame(FIELD, &i, 2.3);
        let tx = texts(&t.outer);
        for want in ["ARM", "3 MRM", "F15.0", "390>", "20"] {
            assert!(tx.contains(&want), "{want} in {tx:?}");
        }
        i.weapons.hud_mode = 3;
        i.target = Some(Target { range_m: 600.0, closure: 100.0, at: Some((5.0, -5.0)) });
        let g = frame(FIELD, &i, 2.3);
        let gt = texts(&g.outer);
        assert!(gt.contains(&"EEGS") && gt.contains(&"F 020") && gt.contains(&"194"), "{gt:?}");
        assert!(g.field.iter().any(|p| matches!(p, Prim::Arc { .. })), "the TD circle's range arc");
    }

    #[test]
    fn slant_formats() {
        assert_eq!(slant('B', 115.0 * NM), "B115.0");
        assert_eq!(slant('F', 2.5 * NM), "F02.5");
        assert_eq!(slant('F', 6000.0 * FT), "F 060");
    }
}
