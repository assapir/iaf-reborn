//! The F-16C/D HUD (T.O. GR1F-16CJ-34-1-1 figs. 1-110 / 1-111 / 1-115 and the A-A / A-G chapters; docs/real-hud.md
//! "F-16C/D"). Drawn for the F-16 only: the F-35, Lavi, Kurnass 2000 and Kfir have their own layouts (mod.rs `frame`).

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
/// The scales and data blocks this far in from the field's sides (`Field::inset`), the right block in A-A included.
const INSET: f64 = 14.0;

pub(super) fn frame(f: Field, i: &Input, max_g: f64) -> Frame {
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let o = &mut fr.outer;
    let sc = f.inset(INSET);
    let tape_y = f.centre_y() - 6.0;
    let dlz = matches!(mode, 1 | 2).then_some(()).and(i.target.zip(i.dlz));
    // Scales.
    airspeed(o, sc.left, tape_y, i.kcas);
    o.push(text((sc.left + 3.0, tape_y - TAPE_HALF - 4.0), format!("{:.1}", i.g), Align::Left));
    let alt_x = sc.right + if dlz.is_some() { ALT_OUT } else { 0.0 };
    altitude(o, alt_x, tape_y, i.alt_ft);
    if let Some((t, z)) = dlz {
        dlz_scale(o, sc.right - DLZ_IN, tape_y, DLZ_HALF, t, z);
    }
    // The heading scale: the lower position (below the scales) in NAV, A-A and strafe; the upper one in the A-G modes
    // and gear down.
    let hdg_y = if i.gear_down || matches!(mode, 5..=7) { f.top + 10.0 } else { tape_y + TAPE_HALF + 6.0 };
    // EEGS has neither the heading scale nor the roll indicator (fig. 1-257).
    if mode != 3 {
        heading(o, hdg_y, i.heading_deg, i.steerpoint.map(|s| s.bearing_deg));
        roll_indicator(o, i, f.bottom);
    }
    // The left column: ARM, Mach, max g, the mode / weapon.
    let (lx, ly) = (sc.left + 4.0, tape_y + TAPE_HALF + 12.0);
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
    if mode == 3
        && let Some(t) = i.target
    {
        rows.push(format!("{}", (t.closure * MS_TO_KT).round() as i64));
    } else if let Some(d) = w.delay.filter(|d| d.designated && matches!(mode, 5 | 6)) {
        // Designated delayed CCIP: the time to release (fig. 1-283 "TIME DELAY") in place of the steerpoint's.
        let t = (d.ttg - RELEASE_TTG).clamp(0.0, 5999.0).ceil() as i64;
        rows.push(format!("{:02}:{:02}", t / 60, t % 60));
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
    // The centre window: SHOOT (MLU) before FUEL.
    if w.shoot || i.fuel_lbs < BINGO_LBS {
        let cue = if w.shoot { "SHOOT" } else { "FUEL" };
        o.push(text((0.0, i.gun_cross.1 + i.mr(70.0)), cue, Align::Centre));
    }

    // The field: boresight cross, ladder, marker, AoA bracket, steerpoint, target, weapon symbols.
    let p = &mut fr.field;
    let delayed = w.delay.and_then(|d| d.target.map(|t| (d, t)));
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
            zenith: Zenith::StarEarth,
        };
        ladder(p, i, fpm, f, style);
        marker(p, fpm, i.mr(5.0), i.mr(10.0), i.mr(5.0));
        if i.gear_down {
            aoa_bracket(p, i, fpm);
        }
        if matches!(mode, 5 | 6)
            && delayed.is_none()
            && let Some(c) = w.pipper
        {
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
            if let Some(a) = i.target.and_then(|t| t.aspect) {
                aspect_triangle(p, c, i.mr(32.5), a, i.mr(5.0));
            }
            if let Some(s) = w.seeker {
                diamond(p, s, i.mr(5.0));
            }
        }
        2 => {
            let c = add(i.gun_cross, (0.0, i.deg(6.0)));
            let r = i.mr(56.0) * (w.circle / 5.0).clamp(0.3, 1.0);
            p.push(Prim::Circle { c, r });
            if let Some(a) = i.target.and_then(|t| t.aspect) {
                aspect_triangle(p, c, r, a, i.mr(5.0));
            }
            if let Some(s) = w.steering {
                let (q, limited) = f.clamp_from(c, s);
                p.push(Prim::Circle { c: q, r: i.mr(4.0) });
                if limited {
                    x_over(p, q, i.mr(4.0));
                }
            }
        }
        3 => eegs(p, i, f),
        5 | 6 if let Some((d, t)) = delayed => delayed_ccip(p, i, f, d, t),
        4..=6 => {
            if let Some(c) = w.pipper {
                pipper(p, c, i.mr(0.5).max(0.8), i.mr(6.0));
            }
        }
        _ => {}
    }
    // The break X (p. 1-173, fig. 1-212): flashing at the GAAF advisory (every master mode); steady in the A-A missile
    // modes inside Rmin. Ours: half its size = 0.3 of the field, on the field's centre, flashing at 2 Hz.
    let gaaf = i.agl_ft.is_some_and(|h| {
        crate::gaaf::advisory(h, i.kcas, i.tas_ms, i.vs_fpm, i.roll_deg, i.gear_down, matches!(mode, 4..=7))
    });
    let rmin = dlz.is_some_and(|(t, z)| t.range_m < z.min);
    if rmin || (gaaf && (i.time_s * 4.0).floor() as i64 % 2 == 0) {
        x_over(p, (0.5 * (f.left + f.right), f.centre_y()), 0.3 * (f.right - f.left).min(f.bottom - f.top));
    }
    fr
}

/// The game releases the first bomb of a delayed CCIP at this time to go (s; docs/weapons.md §9.2 step 5).
const RELEASE_TTG: f64 = 0.9;
/// Ours: the solution cue's height above the marker per second to release and its longest time (inferred: the
/// dash-34 gives no scale; the original's cue moves 100 px over 10 s, which leaves our glass).
const CUE_MR_PER_S: f64 = 10.0;
const CUE_MAX_S: f64 = 10.0;

/// The delayed CCIP (dash-34 pp. 1-429..1-430, fig. 1-283; on the HUD the CCIP pipper is a 1 mr dot in a 12 mr circle
/// with the bomb fall line from the marker). With the impact point below the HUD (the game's delayed CCIP,
/// docs/weapons.md §9.4):
/// - before designation: the pipper on the target under the HUD-edge pipper (the real one is held about 14° below the
///   boresight cross; ours where the game holds it, kept on the glass), the fall line to it and the time delay cue
///   across the line, running from the marker to the pipper as the time to go falls from 10 to 0 s (the game's cue;
///   the real cue's motion is not stated);
/// - Space held (designated): the steering line through the target along the rolled vertical (its offset from the
///   marker is the azimuth error) and the solution cue on it, left of the line, coming down onto the marker's level at
///   the release (time to go 0.9 s), held at the glass's edge while further out.
fn delayed_ccip(p: &mut Vec<Prim>, i: &Input, f: Field, d: Delay, t: P) {
    let from = i.fpm.unwrap_or(i.gun_cross);
    if d.designated {
        let roll = i.roll_deg.to_radians();
        let down = (roll.sin(), roll.cos());
        let long = (f.right - f.left).hypot(f.bottom - f.top);
        p.push(line((t.0 - down.0 * long, t.1 - down.1 * long), (t.0 + down.0 * long, t.1 + down.1 * long)));
        if let Some(fpm) = i.fpm {
            let along = (fpm.0 - t.0) * down.0 + (fpm.1 - t.1) * down.1;
            let l = along - i.mr(CUE_MR_PER_S) * (d.ttg - RELEASE_TTG).clamp(0.0, CUE_MAX_S);
            let level = (t.0 + down.0 * along, t.1 + down.1 * along);
            // Pegged at the glass's edge while further out (as the CCRP's cue in its uppermost position, p. 1-428).
            let (q, _) = f.clamp_from(level, (t.0 + down.0 * l, t.1 + down.1 * l));
            let left = (-down.1, down.0);
            p.push(line(q, (q.0 + left.0 * i.mr(10.0), q.1 + left.1 * i.mr(10.0))));
        }
        return;
    }
    let (c, _) = f.clamp_from(from, t);
    let (dx, dy) = (c.0 - from.0, c.1 - from.1);
    let len = dx.hypot(dy);
    let ring = i.mr(6.0);
    if len > ring {
        let u = (dx / len, dy / len);
        p.push(line(from, (c.0 - u.0 * ring, c.1 - u.1 * ring)));
        let n = len * ((10.0 - d.ttg) / 10.0).clamp(0.0, 1.0);
        let (m, h) = ((from.0 + u.0 * n, from.1 + u.1 * n), i.mr(6.0));
        p.push(line((m.0 - u.1 * h, m.1 + u.0 * h), (m.0 + u.1 * h, m.1 - u.0 * h)));
    }
    pipper(p, c, i.mr(0.5).max(0.8), ring);
}

/// EEGS (dash-34 pp. 1-387..1-390, fig. 1-257). Without a lock, level 2: the funnel (600-3,000 ft) and the MRGS lines
/// at the bottom of the HUD sweeping toward the centre. With a radar track (range, velocity, acceleration: level 5):
/// the lengthened funnel, the T-symbol at the target's range — a long horizontal bar across the funnel (at most
/// 100 mr), the 1 g pipper "+" between its halves and the 9 g pipper tic in the funnel's centre — and the 4 mr
/// pipper on the lead-computed solution; the TD circle with its range arc and the maximum-effective-range dot is drawn
/// by `target_box`.
fn eegs(p: &mut Vec<Prim>, i: &Input, f: Field) {
    let Some(t) = i.target else {
        funnel(p, i, 3000.0);
        mrgs(p, i, f);
        return;
    };
    funnel(p, i, 6000.0);
    let r_ft = (t.range_m / FT).clamp(600.0, 6000.0);
    let (c, half) = funnel_at(i, r_ft, i.g);
    let bar = i.mr(50.0);
    p.push(line((c.0 - bar, c.1), (c.0 - half - 1.0, c.1)));
    p.push(line((c.0 + half + 1.0, c.1), (c.0 + bar, c.1)));
    let a = i.mr(2.0);
    p.push(line((c.0 - a, c.1), (c.0 + a, c.1)));
    p.push(line((c.0, c.1 - a), (c.0, c.1 + a)));
    let (c9, _) = funnel_at(i, r_ft, 9.0);
    p.push(line((c9.0 - a, c9.1), (c9.0 + a, c9.1)));
    if let Some(l) = i.weapons.lcos {
        p.push(Prim::Circle { c: l, r: i.mr(2.0) });
    }
}

/// The multiple reference gunsight lines: short lines near the HUD's bottom drawn for a target 1.5 wingspans long,
/// sweeping repeatedly from the outer edge toward the centre (one sweep a second; ours: five lines).
fn mrgs(p: &mut Vec<Prim>, i: &Input, f: Field) {
    let (y0, y1) = (f.bottom - 30.0, f.bottom - 18.0);
    let span = i.mr(36.0);
    let phase = i.time_s.rem_euclid(1.0);
    p.push(line((i.gun_cross.0, y0), (i.gun_cross.0, y1)));
    for k in 0..2 {
        let x = span * (1.0 - (phase + k as f64 * 0.5).rem_euclid(1.0));
        for side in [-1.0, 1.0] {
            let cx = i.gun_cross.0 + side * x;
            p.push(line((cx - side * 1.5, y0), (cx, y1)));
        }
    }
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
/// Its centre 50 mr below the FOV centre, raised so its lowest tic stays above `bottom` (ours: the cockpit art's glass
/// is shorter than the real HUD's field of view, and the glareshield hides what falls below it).
fn roll_indicator(p: &mut Vec<Prim>, i: &Input, bottom: f64) {
    let r = i.mr(70.0);
    // TODO(real FOV): back to (0, mr(50)) once the view fits the real field of view in the glass (docs/roadmap.md
    // "Real HUD" option).
    let c = (0.0, i.mr(50.0).min(bottom - r - 4.0));
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
        let ft = t.range_m / FT;
        let sweep =
            if t.range_m > 2.0 * NM { std::f64::consts::TAU } else { (ft / 12_000.0).min(1.0) * std::f64::consts::TAU };
        p.push(Prim::Arc { c: at, r: h, from: 0.0, sweep });
        // The maximum effective range (3,000 ft: 3 o'clock) as a dot outside the circle.
        p.push(Prim::Dot { c: (at.0 + h + 3.0, at.1), r: 1.0 });
    } else {
        p.extend(box_poly(at.0 - h, at.1 - h, at.0 + h, at.1 + h));
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;

    #[test]
    fn zenith_star_and_nadir_earth() {
        let spokes = |pitch: f64| {
            let mut i = input(Jet::F16);
            i.fpm = Some((0.0, 0.0));
            i.horizon = (0.0, pitch * i.px_per_deg);
            let fr = frame(FIELD, &i, 1.0);
            let ring = fr
                .field
                .iter()
                .any(|p| matches!(p, Prim::Circle { c, r } if c.1.abs() < 1.0 && (*r - i.mr(6.0)).abs() < 1e-9));
            let on = |q: &P| (0.99 * i.mr(6.0)..=1.81 * i.mr(6.0)).contains(&q.0.hypot(q.1));
            let n = fr.field.iter().filter(|p| matches!(p, Prim::Line { a, b } if on(a) && on(b))).count();
            (ring, n)
        };
        assert_eq!(spokes(90.0), (true, 8), "straight up: the star");
        assert_eq!(spokes(-90.0), (true, 2), "straight down: the earth's cross");
    }

    #[test]
    fn the_roll_indicator_stays_above_the_field_bottom() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 0;
        let fr = frame(FIELD, &i, 1.0);
        let low = fr.outer.iter().filter_map(|p| match p {
            Prim::Line { a, b } => Some(a.1.max(b.1)),
            _ => None,
        });
        assert!(low.fold(f64::MIN, f64::max) <= FIELD.bottom, "a line below the glass");
    }

    #[test]
    fn shoot_takes_the_centre_window() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 2;
        i.weapons.shoot = true;
        let fr = frame(FIELD, &i, 1.0);
        assert!(texts(&fr.outer).contains(&"SHOOT"));
        i.weapons.shoot = false;
        let fr = frame(FIELD, &i, 1.0);
        assert!(!texts(&fr.outer).contains(&"SHOOT"));
    }

    #[test]
    fn nav_windows_as_the_dash_34() {
        let mut i = input(Jet::F16);
        i.agl_ft = Some(19_500.0);
        let fr = frame(FIELD, &i, 4.1);
        let t = texts(&fr.outer);
        for want in [
            "352", "C", "10,450", "2.3", "0.85", "4.1", "NAV", "R 19,500", "B12.0", "05:23", "012>03", "333", "32",
            "34",
        ] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        assert!(!t.contains(&"ARM"), "NAV: no ARM");
    }

    #[test]
    fn weapon_modes() {
        let mut i = input(Jet::F16);
        i.weapons = Weapons { hud_mode: 2, mrm: 3, circle: 4.0, ..Weapons::default() };
        i.target = Some(Target { range_m: 15.0 * NM, closure: 200.0, at: Some((5.0, -5.0)), aspect: None });
        i.dlz = Some(Dlz { max: 18.0 * NM, min: 2.0 * NM });
        let t = frame(FIELD, &i, 2.3);
        let tx = texts(&t.outer);
        for want in ["ARM", "3 MRM", "F15.0", "390>", "20"] {
            assert!(tx.contains(&want), "{want} in {tx:?}");
        }
        i.weapons.hud_mode = 3;
        i.target = Some(Target { range_m: 600.0, closure: 100.0, at: Some((5.0, -5.0)), aspect: None });
        let g = frame(FIELD, &i, 2.3);
        let gt = texts(&g.outer);
        assert!(gt.contains(&"EEGS") && gt.contains(&"F 020") && gt.contains(&"194"), "{gt:?}");
        assert!(g.field.iter().any(|p| matches!(p, Prim::Arc { .. })), "the TD circle's range arc");
    }

    #[test]
    fn break_x() {
        let f = Field { left: -100.0, top: -80.0, right: 100.0, bottom: 80.0 };
        let long = |fr: &Frame| {
            fr.field
                .iter()
                .filter(|p| matches!(p, Prim::Line { a, b } if (a.0 - b.0).abs() > 90.0 && (a.1 - b.1).abs() > 90.0))
                .count()
        };
        // A 45° dive at 413 kt, 2,000 ft above the ground: the GAAF X, flashing.
        let v = 413.0 * 0.514444;
        let mut i = Input {
            agl_ft: Some(2000.0),
            tas_ms: v,
            kcas: 413.0,
            vs_fpm: -v * std::f64::consts::FRAC_1_SQRT_2 * 196.85,
            ..input(Jet::F16)
        };
        i.weapons.hud_mode = 5;
        assert_eq!(long(&frame(f, &i, 1.0)), 2, "the break X");
        i.time_s = 0.3;
        assert_eq!(long(&frame(f, &i, 1.0)), 0, "flashing");
        i.agl_ft = Some(3000.0);
        i.time_s = 0.0;
        assert_eq!(long(&frame(f, &i, 1.0)), 0, "above the advisory height");
        // A-A: the target inside Rmin.
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 2;
        i.target = Some(Target { range_m: 1000.0, ..Default::default() });
        i.dlz = Some(Dlz { max: 20_000.0, min: 1500.0 });
        assert_eq!(long(&frame(f, &i, 1.0)), 2, "inside Rmin");
        i.target = Some(Target { range_m: 5000.0, ..Default::default() });
        assert_eq!(long(&frame(f, &i, 1.0)), 0, "inside the DLZ");
    }

    #[test]
    fn eegs_levels() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 3;
        let low = |fr: &Frame| {
            fr.field
                .iter()
                .filter(|p| matches!(p, Prim::Line { a, .. } if (a.1 - (FIELD.bottom - 30.0)).abs() < 1e-9))
                .count()
        };
        let l2 = frame(FIELD, &i, 2.3);
        assert_eq!(low(&l2), 5, "level 2: the five MRGS lines");
        i.target = Some(Target { range_m: 1500.0 * FT, closure: 50.0, at: Some((0.0, 20.0)), aspect: None });
        i.weapons.lcos = Some((1.0, 18.0));
        let l5 = frame(FIELD, &i, 2.3);
        assert_eq!(low(&l5), 0, "with a track the MRGS lines go");
        let long_bar = l5
            .field
            .iter()
            .any(|p| matches!(p, Prim::Line { a, b } if (a.1 - b.1).abs() < 1e-9 && (b.0 - a.0) > i.mr(30.0)));
        assert!(long_bar, "the T-symbol's bars");
        assert!(l5.field.iter().any(|p| matches!(p, Prim::Dot { .. })), "the maximum-effective-range dot");
    }

    #[test]
    fn delayed_ccip() {
        let mut i = input(Jet::F16);
        i.weapons.hud_mode = 5;
        i.fpm = Some((0.0, 0.0));
        i.weapons.pipper = Some((0.0, 200.0)); // the impact point, below the glass
        let pip = |fr: &Frame| fr.field.iter().find_map(|p| if let Prim::Dot { c, .. } = p { Some(*c) } else { None });
        // The delay cue: a 12 mr line across the fall line at height y.
        let h = i.mr(6.0);
        let ticks = |fr: &Frame, y: f64| {
            fr.field.iter().filter(|p| matches!(p, Prim::Line { a, b } if (a.1 - y).abs() < 1e-6 && (b.1 - y).abs() < 1e-6 && (a.0 + b.0).abs() < 1e-6 && ((a.0 - b.0).abs() - 2.0 * h).abs() < 1e-6)).count()
        };
        // CCIP: the pipper on the impact point (clipped by the field).
        assert_eq!(pip(&frame(FIELD, &i, 1.0)), Some((0.0, 200.0)));
        // Delayed: the pipper on the target under the HUD-edge point, kept on the glass; the delay cue across the
        // fall line from the marker toward it (5 s to go: half way).
        i.weapons.delay = Some(Delay { ttg: 5.0, target: Some((0.0, 100.0)), designated: false });
        let fr = frame(FIELD, &i, 1.0);
        assert_eq!(pip(&fr), Some((0.0, FIELD.bottom)), "held on the glass");
        assert_eq!(ticks(&fr, 0.5 * FIELD.bottom), 1, "the time delay cue half way");
        i.weapons.delay = Some(Delay { ttg: 12.0, target: Some((0.0, 60.0)), designated: false });
        assert_eq!(ticks(&frame(FIELD, &i, 1.0), 0.0), 1, "10 s or more: the cue at the marker");
        // Designated: no pipper; the steering line through the target, the solution cue above the marker.
        i.weapons.delay = Some(Delay { ttg: 4.9, target: Some((20.0, 60.0)), designated: true });
        let fr = frame(FIELD, &i, 1.0);
        assert_eq!(pip(&fr), None);
        let steer = fr.field.iter().any(
            |p| matches!(p, Prim::Line { a, b } if a.0 == 20.0 && b.0 == 20.0 && a.1 < FIELD.top && b.1 > FIELD.bottom),
        );
        assert!(steer, "the steering line through the target");
        let cue_y = -i.mr(CUE_MR_PER_S) * 4.0;
        let cue = fr.field.iter().any(|p| matches!(p, Prim::Line { a, b } if (a.0 - 20.0).abs() < 1e-9 && b.0 < 20.0 && (a.1 - cue_y).abs() < 1e-9 && (b.1 - cue_y).abs() < 1e-9));
        assert!(cue, "the solution cue 4 s above the marker, left of the line");
        assert!(texts(&fr.outer).contains(&"00:04"), "the time to release");
        // Far out: pegged at the glass's top.
        i.weapons.delay = Some(Delay { ttg: 30.0, target: Some((20.0, 60.0)), designated: true });
        let low = Field { top: -40.0, ..FIELD };
        let fr = frame(low, &i, 1.0);
        let pegged = |q: &P| (q.1 - low.top).abs() < 1e-9;
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Line { a, b } if (a.0 - 20.0).abs() < 1e-9 && b.0 < 20.0 && pegged(a) && pegged(b))), "pegged");
        // At the release the cue reaches the marker's level; rolled 90° right the line runs across the HUD.
        i.weapons.delay = Some(Delay { ttg: 0.9, target: Some((20.0, 60.0)), designated: true });
        let fr = frame(FIELD, &i, 1.0);
        assert!(
            fr.field
                .iter()
                .any(|p| matches!(p, Prim::Line { a, b } if a.0 == 20.0 && a.1.abs() < 1e-9 && b.1.abs() < 1e-9)),
            "the cue on the marker"
        );
        i.roll_deg = 90.0;
        let fr = frame(FIELD, &i, 1.0);
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Line { a, b } if (a.1 - 60.0).abs() < 1e-9 && (b.1 - 60.0).abs() < 1e-9 && a.0 < FIELD.left && b.0 > FIELD.right)));
    }

    #[test]
    fn slant_formats() {
        assert_eq!(slant('B', 115.0 * NM), "B115.0");
        assert_eq!(slant('F', 2.5 * NM), "F02.5");
        assert_eq!(slant('F', 6000.0 * FT), "F 060");
    }
}
