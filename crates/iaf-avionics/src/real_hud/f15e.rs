//! The F-15E HUD (TO 1F-15E-1 pp. 1-68 to 1-81, figs. 1-22 and 1-23; docs/real-hud.md "F-15E (F-15I Ra'am)"), drawn
//! for the F-15I Ra'am: its aircraft definition's `hud` is "f15e" (the F-15I's own HUD software is open; the F-15E's
//! is used, labelled). Digital windows in place of the F-15A/C's tapes: the boxed calibrated airspeed (window 1) and
//! barometric altitude (13), AoA (2), the weapon count (5), Mach (6), current and allowable g (7) on the left, the
//! steering, range, time and mode windows (17 to 20) on the right; the heading scale on top, the radar altimeter
//! thermometer at the right edge, the bank scale at the bottom (NAV), the flight-path pitch ladder with bent rungs.
//!
//! Places: fig. 1-23 sheet 1 puts every window on a drawn HUD frame. Ours keeps that arrangement as fractions of the
//! cockpit's HUD field from its centre, the rows spread to the game's HUD font (9 px) where the figure's are closer
//! (inferred: the figure is not to scale, and the font is larger against the glass than the real HUD's).

use super::*;

/// Window places as fractions of the field's half width (x) and half height (y) from its centre, measured on fig.
/// 1-23 sheet 1 and fig. 1-22 (inferred from a schematic drawing; see the module comment).
/// The left column's right edge (windows 1, 2, 5 to 7) and the right column's left edge (13, 14, 17 to 20).
const LEFT_X: f64 = -0.37;
const RIGHT_X: f64 = 0.36;
/// The boxed windows 1 and 13 (their centre row).
const BOX_Y: f64 = -0.38;
/// Windows 5 to 7 and 17 to 20: the first row's baseline.
const LOW_Y: f64 = 0.33;
/// The A-A range scale: its x and its top / bottom.
const RANGE_X: f64 = 0.27;
const RANGE_TOP: f64 = -0.47;
const RANGE_BOTTOM: f64 = 0.33;
/// The radar altimeter thermometer (fig. 1-22): its x, the 1,500 ft top and the zero.
const RALT_X: f64 = 0.92;
const RALT_TOP: f64 = -0.72;
const RALT_ZERO: f64 = 0.87;
/// The bank scale's centre (y) and radius (x fraction).
const BANK_Y: f64 = 0.24;
const BANK_R: f64 = 0.35;
/// Rows 9 px apart (the HUD font).
const ROW: f64 = 9.0;
/// The heading scale: 30° (window 12A: "the displayed 30° scale") over this many px either side, 2° ticks, labels
/// every 10° (inferred: widened from the figure's third of the frame so that the two-digit labels stay apart).
const HDG_HALF: f64 = 45.0;
const HDG_WINDOW: f64 = 30.0;
/// Break X (p. 1-71): dive steeper than 3°, the pull-out on a 4.0 g pull attained in 2 s (ours: one second at the
/// present sink stands for the onset), shown when the recovery ends below 200 ft of radar altitude.
const BREAK_DIVE_DEG: f64 = 3.0;
const BREAK_PULL_G: f64 = 4.0;
const BREAK_ONSET_S: f64 = 1.0;
const BREAK_FLOOR_FT: f64 = 200.0;

/// The field's centre and half sizes.
struct Fit {
    c: P,
    hw: f64,
    hh: f64,
}

impl Fit {
    fn at(&self, fx: f64, fy: f64) -> P {
        (self.c.0 + fx * self.hw, self.c.1 + fy * self.hh)
    }
}

pub(super) fn frame(f: Field, i: &Input, gs_captured: bool) -> Frame {
    let mut fr = Frame::default();
    let w = &i.weapons;
    let mode = w.hud_mode;
    let aa = matches!(mode, 1..=3);
    let ag = matches!(mode, 4..=8);
    let ils = i.ils.filter(|_| mode == 0 && i.gear_down);
    let gps = w.gps.filter(|_| matches!(mode, 5 | 6));
    let fit =
        Fit { c: (0.5 * (f.left + f.right), f.centre_y()), hw: 0.5 * (f.right - f.left), hh: 0.5 * (f.bottom - f.top) };
    let o = &mut fr.outer;

    heading(o, f, i);
    // Left: window 1 (boxed CAS), 2 (AoA); 5 (rounds / missiles), 6 (Mach, gear up), 7 (g, gear up).
    let (lx, by) = fit.at(LEFT_X, BOX_Y);
    boxed(o, lx - 30.0, by, lx, &format!("{}", i.kcas.max(0.0).round() as i64), Align::Right);
    // Its source letter left of the box (fig. 1-22): C, calibrated (T / G, true / ground speed: UFC selections the
    // game has not).
    o.push(text((lx - 32.0, by + 3.0), "C", Align::Right));
    o.push(text((lx, by + 5.0 + ROW + 1.0), format!("α {:.1}", i.aoa_deg), Align::Right));
    let (_, ly) = fit.at(0.0, LOW_Y);
    let mut rows = Vec::new();
    match mode {
        1 => rows.push(format!("S{}{}", w.srm, letter(&w.name))),
        2 => rows.push(format!("M{}{}", w.mrm, letter(&w.name))),
        3 | 4 => rows.push(format!("{}", w.selected)),
        _ => {}
    }
    if !i.gear_down {
        rows.push(format!("{:.3}", i.mach));
        // Current g / maximum allowable g (window 7): the game has no overload warning system's weight curve; the
        // jet's own limit (the F-15I row's +8.1) stands for it (inferred).
        rows.push(format!("{:.1}  {:.1}G", i.g, i.g_limit));
    }
    for (k, t) in rows.into_iter().enumerate() {
        o.push(text((lx, ly + k as f64 * ROW), t, Align::Right));
    }

    // Right: window 13 (boxed baro altitude, to 10 ft), 14 (vertical velocity: NAV, gear down), 14A (radar altitude,
    // outside A-A: the UFC selection, inferred on); 17 to 20.
    let (rx, _) = fit.at(RIGHT_X, 0.0);
    boxed(o, rx + 4.0, by, rx + 38.0, &format!("{}", (i.alt_ft / 10.0).round() as i64 * 10), Align::Right);
    // Its source letter left of the box (fig. 1-22): B, barometric (R, radar: a UFC selection; the radar altitude is
    // window 14A).
    o.push(text((rx + 2.0, by + 3.0), "B", Align::Right));
    let mut ry = by + 5.0 + ROW + 1.0;
    if mode == 0 && i.gear_down {
        o.push(text((rx, ry), format!("VV {}", (i.vs_fpm / 100.0).round() as i64 * 100), Align::Left));
        ry += ROW;
    }
    if let Some(agl) = i.agl_ft.filter(|_| !aa) {
        o.push(text((rx, ry), format!("R {}", (agl / 10.0).round() as i64 * 10), Align::Left));
    }
    let mut right = Vec::new();
    // 17: the steering mode and destination (NAV, also the A-G default: note 14).
    if let Some(s) = i.steerpoint.filter(|_| !aa) {
        right.push(format!("{} {}", if ils.is_some() { "ILSN" } else { "NAV" }, s.number));
    }
    // 18: range with its source letter.
    match (aa, i.target, i.steerpoint) {
        (true, Some(t), _) => right.push(format!("R{:.1}", t.range_m / NM)),
        (false, _, Some(s)) => right.push(format!("N{:.1}", s.dist_m / NM)),
        _ => {}
    }
    // 19: time to go (NAV h:mm:ss), to release (the delayed CDIP), to impact (a released GPS bomb).
    if let Some(t) = w.tti {
        right.push(format!("{} TIMPCT", mmss(t)));
    } else if let Some(d) = w.delay.filter(|_| matches!(mode, 5 | 6) && gps.is_none()) {
        right.push(format!("{} TREL", mmss(d.ttg)));
    } else if let Some(t) = i.steerpoint.filter(|_| mode == 0).and_then(|s| s.eta_s) {
        let t = t.clamp(0.0, 359_999.0).round() as i64;
        right.push(format!("{:02}:{:02}:{:02}", t / 3600, t / 60 % 60, t % 60));
    }
    // A GPS bomb's range cue (`IN RNG` / `TMR m:ss`, ours: the F-16's, under the staple there): a row of its own
    // under window 19, clear of the other windows (inferred).
    if let Some(c) = gps.and_then(|g| gps_cue(&g.lar)) {
        right.push(c);
    }
    // 20: the target's aspect (A-A), the A-G delivery mode and the height-above-target sensor.
    if aa && let Some(a) = i.target.and_then(|t| t.aspect) {
        right.push(aspect(a));
    } else if ag {
        let m = match mode {
            4 => "GUN",
            5 | 6 => gps.map_or("CDIP", |g| if g.pre { "PRE" } else { "VIS" }),
            7 => "GUIDED",
            _ => "",
        };
        if !m.is_empty() {
            right.push(format!("{m:<7}{}", if i.agl_ft.is_some() { "RALT" } else { "BARO" }));
        }
    }
    for (k, t) in right.into_iter().enumerate() {
        o.push(text((rx, ly + k as f64 * ROW), t, Align::Left));
    }
    // The radar altimeter thermometer (NAV and A-G, a valid radar altitude up to its 1,500 ft top: ours, above it the
    // full bar would say nothing).
    if !aa && let Some(agl) = i.agl_ft.filter(|a| *a <= 1500.0) {
        thermometer(o, &fit, agl);
    }
    // The A-A range scale (windows 10, 11, 12) on the target with a launch zone; the GPS bomb's LAR in its place.
    let (sx, top) = fit.at(RANGE_X, RANGE_TOP);
    let (_, bottom) = fit.at(RANGE_X, RANGE_BOTTOM);
    let (sy, half) = (0.5 * (top + bottom), 0.5 * (bottom - top));
    if aa && let (Some(t), Some(z)) = (i.target, i.dlz) {
        let top_nm = dlz_scale(o, sx, sy, half, t, z);
        o.push(text((sx + 3.0, sy + 3.0), format!("{}", (top_nm / 2.0) as i64), Align::Left));
    }
    if mode == 0 && !i.gear_down {
        bank_scale(o, &fit, i.roll_deg);
    }

    // The field.
    let p = &mut fr.field;
    let (bx, by) = i.boresight;
    if let Some((x, y)) = ils {
        p.push(line((bx + x, by - 12.0), (bx + x, by + 12.0)));
        if gs_captured {
            p.push(line((bx - 12.0, by + y), (bx + 12.0, by + y)));
        }
    } else if mode == 0
        && let Some(s) = i.steerpoint
    {
        let err = ((s.bearing_deg - i.heading_deg + 180.0).rem_euclid(360.0) - 180.0).clamp(-20.0, 20.0);
        let x = bx + 2.0 * err;
        p.push(line((x, by - 12.0), (x, by + 12.0)));
    }
    // The aircraft waterline symbol: NAV and the A-A missile modes (fig. 1-23 sheet 6).
    if matches!(mode, 0..=2) {
        waterline(p, i.boresight, i.mr(14.0));
    }
    // The gun cross with Master Arm on (p. 1-71).
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
            horizon_len: i.deg(5.0),
            tip: i.deg(0.35),
            inner_tips: false,
            bend: true,
            both_labels: true,
            signed: false,
            bottom_band: 0.0,
            top_band: 16.0,
            zenith: Zenith::F15E,
            horizon_tabs: true,
        };
        ladder(p, i, fpm, f, style);
        marker(p, fpm, i.mr(6.0), i.mr(8.0), i.mr(5.0));
    }
    if aa
        && let Some(t) = i.target
        && let Some(at) = t.at.filter(|a| f.contains(*a))
    {
        let h = i.mr(15.0);
        p.extend(box_poly(at.0 - h, at.1 - h, at.0 + h, at.1 + h));
    }
    match mode {
        1 | 2 => {
            let (c, r) = super::mrm_circle(i).unwrap_or_default();
            p.push(Prim::Circle { c, r });
            if mode == 2
                && let Some(s) = w.steering
            {
                let (q, _) = f.clamp_from(c, s);
                p.push(Prim::Dot { c: q, r: i.mr(3.0) });
            }
            if mode == 1
                && let Some(s) = w.seeker
            {
                p.push(Prim::Circle { c: s, r: i.mr(6.0) });
            }
            if w.shoot {
                p.push(text((c.0, c.1 + r + 10.0), "SHOOT", Align::Centre));
            }
        }
        3 => {
            if let Some(c) = w.lcos {
                f15::lcos(p, i, c);
            }
        }
        5 | 6 if gps.is_some() => gps_cues(p, o, i, f, (sx, sy, half), i.mr(4.0), false),
        4..=6 => {
            if let Some(c) = w.pipper {
                reticle(p, i, c);
            }
            if let Some(t) = w.delay.and_then(|d| d.target) {
                diamond(p, t, i.mr(5.0));
            }
        }
        // An EO guided weapon: the reticle on the weapon's boresight (p. 1-71).
        7 => reticle(p, i, i.boresight),
        _ => {}
    }
    if ag && break_x(i) {
        p.push(line((f.left + 10.0, f.top + 20.0), (f.right - 10.0, f.bottom - 10.0)));
        p.push(line((f.left + 10.0, f.bottom - 10.0), (f.right - 10.0, f.top + 20.0)));
    }
    fr
}

/// Text in a box `x0`..`x1` centred on `y`, aligned to the box's inner edge.
fn boxed(p: &mut Vec<Prim>, x0: f64, y: f64, x1: f64, t: &str, align: Align) {
    p.extend(box_poly(x0, y - 5.0, x1, y + 5.0));
    let x = if align == Align::Right { x1 - 2.0 } else { x0 + 2.0 };
    p.push(text((x, y + 3.0), t, align));
}

/// The missile count's type letter (window 5): A for the AIM-120A, F / M for the AIM-7F / M, J / P / L / M for the
/// AIM-9s; none for a missile the F-15E's manual does not list (the Pythons, the AIM-9X: open).
fn letter(name: &str) -> &'static str {
    match name {
        "AMRAAM" => "A",
        "AIM-7F" => "F",
        "AIM-7M" => "M",
        "AIM-9L" => "L",
        "AIM-9M" => "M",
        _ => "",
    }
}

/// The target aspect (window 20): tens of degrees from its tail and the side toward us ("17L"), T at the tail, H on
/// the nose.
fn aspect(a: f64) -> String {
    let tens = (a.abs().to_degrees() / 10.0).round() as i64;
    match tens {
        0 => "T".into(),
        18 => "H".into(),
        _ => format!("{tens:02}{}", if a > 0.0 { "L" } else { "R" }),
    }
}

/// Minutes and seconds ("1:15").
fn mmss(t: f64) -> String {
    let t = t.clamp(0.0, 5999.0).ceil() as i64;
    format!("{}:{:02}", t / 60, t % 60)
}

/// The heading scale (p. 1-70): it moves against a fixed caret, two-digit labels in tens of degrees, 2° ticks; the
/// command heading marker (the steerpoint's bearing) on it, held at its end with the bearing's digits (window 12A)
/// when outside.
fn heading(p: &mut Vec<Prim>, f: Field, i: &Input) {
    let y = f.top + 10.0;
    let k = 2.0 * HDG_HALF / HDG_WINDOW;
    p.push(line((-HDG_HALF, y), (HDG_HALF, y)));
    let hdg = i.heading_deg;
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
    if let Some(s) = i.steerpoint {
        let d = (s.bearing_deg - hdg + 180.0).rem_euclid(360.0) - 180.0;
        let x = (d * k).clamp(-HDG_HALF, HDG_HALF);
        for dx in [-1.0, 1.0] {
            p.push(line((x + dx, y + 1.0), (x + dx, y + 5.0)));
        }
        if (d * k).abs() > HDG_HALF {
            let b = (s.bearing_deg.round() as i64).rem_euclid(360);
            p.push(text((x, y + 13.0), format!("{b:03}"), Align::Centre));
        }
    }
}

/// The radar altimeter thermometer (fig. 1-22): 0 to 500 ft with 100 ft ticks over the lower part, 500 to 1,500 ft
/// with 250 ft ticks compressed above, labels 5, 10, 15 (hundreds of feet) left of the ticks; the bar filled up from
/// the zero foot to the radar altitude.
fn thermometer(p: &mut Vec<Prim>, fit: &Fit, agl: f64) {
    let (x, top) = fit.at(RALT_X, RALT_TOP);
    let (_, zero) = fit.at(RALT_X, RALT_ZERO);
    // 500 ft at 64 % of the way up (the figure: 290 of its 452 units).
    let mid = zero - 0.64 * (zero - top);
    let y = |ft: f64| {
        if ft <= 500.0 {
            zero - (zero - mid) * ft / 500.0
        } else {
            mid - (mid - top) * (ft.min(1500.0) - 500.0) / 1000.0
        }
    };
    p.push(line((x, zero), (x, top)));
    p.push(line((x - 4.0, zero), (x + 2.0, zero)));
    for ft in [100.0, 200.0, 300.0, 400.0, 500.0, 750.0, 1000.0, 1250.0, 1500.0] {
        let t = y(ft);
        p.push(line((x - 3.0, t), (x, t)));
        if (ft as i64) % 500 == 0 {
            p.push(text((x - 5.0, t + 3.0), format!("{}", ft as i64 / 100), Align::Right));
        }
    }
    let v = y(agl.max(0.0));
    for dx in [0.8, 1.6, 2.4] {
        p.push(line((x + dx, zero), (x + dx, v)));
    }
}

/// The bank angle scale (p. 1-70) at the bottom: ticks at 0, 10, 20, 30, 45 and 60° either side, 0° and 45° double
/// width, 30° and 60° double length; the pointer at the bank (inferred: the F-16's lower roll scale's sense).
fn bank_scale(p: &mut Vec<Prim>, fit: &Fit, roll: f64) {
    let (cx, cy) = fit.at(0.0, BANK_Y);
    let r = BANK_R * fit.hw;
    let at = |deg: f64, rr: f64| {
        let a = deg.to_radians();
        (cx - rr * a.sin(), cy + rr * a.cos())
    };
    for d in [0.0, 10.0, 20.0, 30.0, 45.0, 60.0] {
        let sides: &[f64] = if d == 0.0 { &[1.0] } else { &[-1.0, 1.0] };
        for s in sides {
            let deg = s * d;
            let len = if d == 30.0 || d == 60.0 { 6.0 } else { 3.0 };
            p.push(line(at(deg, r), at(deg, r + len)));
            if d == 0.0 || d == 45.0 {
                p.push(line(at(deg + 1.2, r), at(deg + 1.2, r + len)));
            }
        }
    }
    let b = roll.clamp(-60.0, 60.0);
    p.push(line(at(b, r - 6.0), at(b, r)));
}

/// The A-G reticle (p. 1-71): a 50 mil circle and a 2 mil pipper.
fn reticle(p: &mut Vec<Prim>, i: &Input, c: P) {
    p.push(Prim::Circle { c, r: i.mr(25.0) });
    p.push(Prim::Dot { c, r: i.mr(1.0).max(0.8) });
}

/// Break X (p. 1-71): diving more than 3° with a radar altitude, and the pull-out (a 4 g pull; `BREAK_ONSET_S`) ends
/// below 200 ft.
fn break_x(i: &Input) -> bool {
    let Some(agl) = i.agl_ft else { return false };
    if i.tas_ms <= 0.0 || i.gear_down {
        return false;
    }
    let sink = -i.vs_fpm * FT / 60.0;
    let dive = (sink / i.tas_ms).clamp(-1.0, 1.0).asin();
    if dive.to_degrees() <= BREAK_DIVE_DEG {
        return false;
    }
    let radius = i.tas_ms * i.tas_ms / (9.80665 * (BREAK_PULL_G - 1.0));
    let loss_ft = (sink * BREAK_ONSET_S + radius * (1.0 - dive.cos())) / FT;
    agl - loss_ft < BREAK_FLOOR_FT
}

#[cfg(test)]
mod tests {
    use super::super::tests::{FIELD, input, texts};
    use super::*;
    use crate::missile::Dlz;

    fn nav() -> Input {
        input(Jet::F15E)
    }

    #[test]
    fn nav_windows_as_fig_1_23() {
        let fr = frame(FIELD, &nav(), false);
        let t = texts(&fr.outer);
        for want in ["C", "352", "B", "10450", "α 0.0", "0.850", "2.3  8.1G", "NAV 3", "N12.0", "00:05:23", "33", "34"]
        {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        // Gear down: no Mach / g, the vertical velocity.
        let i = Input { gear_down: true, vs_fpm: -720.0, ..nav() };
        let t = texts(&frame(FIELD, &i, false).outer).into_iter().map(String::from).collect::<Vec<_>>();
        assert!(t.contains(&"VV -700".to_string()) && !t.iter().any(|s| s.ends_with('G')), "{t:?}");
    }

    /// A GPS bomb's range cue is a row of the right column under window 19, clear of the LAR staple and range text;
    /// with a bomb in flight both the time to impact and the cue.
    #[test]
    fn gps_range_cue_in_window_19() {
        use crate::gps::Lar;
        let mut i = nav();
        i.weapons.hud_mode = 5;
        let lar = Lar { range: 8000.0, rmin: 2000.0, rmax: 12_000.0, in_range: true, tmr: None };
        i.weapons.gps = Some(GpsCue { pre: true, at: Some((20.0, 40.0)), lar });
        let fr = frame(FIELD, &i, false);
        let at = |s: &str| {
            fr.outer.iter().find_map(|p| match p {
                Prim::Text { at, text, align } if text.starts_with(s) => Some((*at, *align)),
                _ => None,
            })
        };
        let (cue, range) = (at("IN RNG").expect("IN RNG"), at("N12.0").expect("N12.0"));
        assert_eq!((cue.0.0, cue.1), (range.0.0, Align::Left), "{cue:?} {range:?}");
        assert!(cue.0.1 > range.0.1, "under window 18");
        i.weapons.tti = Some(188.0);
        let t = texts(&frame(FIELD, &i, false).outer).into_iter().map(String::from).collect::<Vec<_>>();
        assert!(t.contains(&"IN RNG".to_string()) && t.iter().any(|s| s.ends_with("TIMPCT")), "{t:?}");
    }

    #[test]
    fn airspeed_left_altitude_right_and_inside_the_field() {
        let fr = frame(FIELD, &nav(), false);
        let x_of = |s: &str| {
            fr.outer.iter().find_map(|p| match p {
                Prim::Text { at, text, .. } if text == s => Some(at.0),
                _ => None,
            })
        };
        assert!(x_of("352").unwrap() < 0.0 && x_of("10450").unwrap() > 0.0);
        for p in &fr.outer {
            if let Prim::Line { a, b } = p {
                for q in [a, b] {
                    assert!(q.0 >= FIELD.left && q.0 <= FIELD.right, "{p:?} outside the field");
                }
            }
        }
    }

    #[test]
    fn missile_counts_aspect_and_range() {
        let mut i = nav();
        i.weapons.hud_mode = 2;
        i.weapons.mrm = 4;
        i.weapons.name = "AMRAAM".into();
        i.target = Some(Target { range_m: 15.0 * NM, closure: 300.0, at: Some((5.0, 5.0)), aspect: Some(-0.3) });
        i.dlz = Some(Dlz { max: 20.0 * NM, min: 2.0 * NM });
        let fr = frame(FIELD, &i, false);
        let t = texts(&fr.outer);
        for want in ["M4A", "R15.0", "02R", "40", "20"] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        assert_eq!(aspect(0.01), "T");
        assert_eq!(aspect(std::f64::consts::PI), "H");
        assert_eq!(aspect(2.97), "17L");
        i.weapons.hud_mode = 1;
        i.weapons.srm = 2;
        i.weapons.name = "PYTH-5".into();
        assert!(texts(&frame(FIELD, &i, false).outer).contains(&"S2"), "no letter for the Python");
    }

    #[test]
    fn ag_reticle_mode_and_break_x() {
        let v = 450.0 * 0.514444;
        let mut i = Input { agl_ft: Some(1300.0), tas_ms: v, vs_fpm: -v * 0.5 / FT * 60.0, ..nav() };
        i.weapons.hud_mode = 5;
        i.weapons.pipper = Some((0.0, 30.0));
        let fr = frame(FIELD, &i, false);
        assert!(texts(&fr.outer).contains(&"CDIP   RALT"), "{:?}", texts(&fr.outer));
        assert!(fr.field.iter().any(|p| matches!(p, Prim::Circle { c, .. } if *c == (0.0, 30.0))));
        let long = |fr: &Frame| {
            fr.field.iter().filter(|p| matches!(p, Prim::Line { a, b } if (b.0 - a.0).abs() > 100.0)).count()
        };
        assert_eq!(long(&fr), 2, "a 30° dive at 450 kt from 1,300 ft: break X");
        i.agl_ft = Some(8000.0);
        assert_eq!(long(&frame(FIELD, &i, false)), 0);
        i.weapons.hud_mode = 0;
        i.agl_ft = Some(1300.0);
        assert_eq!(long(&frame(FIELD, &i, false)), 0, "A-G only");
    }

    #[test]
    fn released_gps_bomb_time_to_impact() {
        let mut i = nav();
        i.weapons.tti = Some(74.2);
        assert!(texts(&frame(FIELD, &i, false).outer).contains(&"1:15 TIMPCT"));
    }
}
