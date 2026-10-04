//! The "Real HUD" (ours, Extras > HUD: docs/deviations.md, docs/cockpit.md "Real HUD"): an F-16 Block 30/40 style
//! head-up display from public references instead of the original's simplified 1998 symbology. This module lays it out
//! as drawing primitives in the original's HUD pixels (x right, y down, from the HUD centre); the cockpit draws them.
//!
//! Phase 1, the navigation symbology: the airspeed (KCAS) and altitude (barometric) scales with their digital boxes,
//! the heading scale with the steering caret, the conformal pitch ladder centred on the flight path marker (solid
//! climb rungs, dashed dive rungs, tips toward the horizon), the flight path marker, the AoA bracket with the gear
//! down, and the data windows (Mach, g, max g, the master mode; the steerpoint's distance and time).
//!
//! Phase 2, the weapon cues: the DLZ scale (Rmax / Rmin ticks, the target's range caret with the closure) beside the
//! altitude scale while a target is locked, the target's range in the right window ("F 12.3"), the CCIP bomb fall line
//! from the marker to the pipper, and the bingo cue ("FUEL" below the bingo fuel).

/// Scales: the airspeed 0.6 px per kt (10 kt ticks, labels every 50 kt as kt / 10), the altitude 0.06 px per ft (100 ft
/// ticks, labels every 500 ft in thousands), the heading 2 px per degree (5° ticks, labels every 10° in tens).
const KT_PX: f64 = 0.6;
const FT_PX: f64 = 0.06;
const HDG_PX: f64 = 2.0;
/// Half heights / widths of the scales.
const TAPE_HALF: f64 = 36.0;
const HDG_HALF: f64 = 40.0;
/// The ladder: rungs every 5°, each half 20 px long beyond a 9 px gap from the ladder's centre line, 4 px tips, labels
/// 4 px beyond the tips; the horizon line twice as long.
const RUNG_STEP: i64 = 5;
const RUNG_GAP: f64 = 9.0;
const RUNG_LEN: f64 = 20.0;
const TIP: f64 = 4.0;
/// The band along the field's bottom the heading scale takes (no ladder rungs there).
const HEADING_BAND: f64 = 26.0;
/// The flight path marker: a 4 px circle, 8 px wings, a 4 px fin.
const FPM_R: f64 = 4.0;
/// The AoA bracket (gear down): the marker inside it from 11° to 15° AoA, 13° on its centre.
const AOA_LOW: f64 = 11.0;
const AOA_HIGH: f64 = 15.0;
/// m → NM; m/s → kt.
const NM: f64 = 1852.0;
const MS_TO_KT: f64 = 1.943844;
/// The DLZ scale: 48 px tall, 18 px left of the altitude scale; its top the range scale (10, 20, 40 or 80 NM: the
/// smallest above Rmax and the target's range).
const DLZ_HALF: f64 = 24.0;
const DLZ_X: f64 = 18.0;
const DLZ_SCALES_NM: [f64; 4] = [10.0, 20.0, 40.0, 80.0];
/// Ours: the bingo fuel (lb) below which "FUEL" shows.
pub const BINGO_LBS: f64 = 1500.0;

/// Text alignment at its anchor (the anchor is the baseline's left, centre or right end).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Align {
    Left,
    Centre,
    Right,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Prim {
    Line { a: (f64, f64), b: (f64, f64) },
    Circle { c: (f64, f64), r: f64 },
    Text { at: (f64, f64), text: String, align: Align },
}

fn line(a: (f64, f64), b: (f64, f64)) -> Prim {
    Prim::Line { a, b }
}

fn text(at: (f64, f64), t: impl Into<String>, align: Align) -> Prim {
    Prim::Text { at, text: t.into(), align }
}

/// The symbology field in HUD pixels from the HUD centre.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Field {
    pub left: f64,
    pub top: f64,
    pub right: f64,
    pub bottom: f64,
}

/// One frame's values.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Input {
    pub kcas: f64,
    pub alt_ft: f64,
    pub heading_deg: f64,
    pub roll_deg: f64,
    pub mach: f64,
    pub g: f64,
    pub aoa_deg: f64,
    pub gear_down: bool,
    /// The flight path marker in HUD pixels (None: off the view).
    pub fpm: Option<(f64, f64)>,
    /// The horizon straight ahead (the level direction along the heading) in HUD pixels and the view's HUD pixels per
    /// degree: the conformal ladder.
    pub horizon: (f64, f64),
    pub px_per_deg: f64,
    /// The master mode's label ("NAV", "AA", "AG"...).
    pub master: String,
    /// The steerpoint: its number, bearing (°), distance (m) and the time to it (s; None when not closing).
    pub steerpoint: Option<Steerpoint>,
    /// The radar's locked target.
    pub target: Option<Target>,
    /// The selected store's launch zone at it (metres).
    pub dlz: Option<crate::missile::Dlz>,
    /// The CCIP pipper in HUD pixels (HUD modes 5 / 6).
    pub ccip: Option<(f64, f64)>,
    pub fuel_lbs: f64,
}

/// The locked target: range (m) and closure (m/s, positive closing).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Target {
    pub range_m: f64,
    pub closure: f64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Steerpoint {
    pub number: i64,
    pub bearing_deg: f64,
    pub dist_m: f64,
    pub eta_s: Option<f64>,
}

/// The two layers: `field` is clipped to the symbology field (the ladder, the marker, the bracket), `outer` is not
/// (the scales and the data windows).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Frame {
    pub field: Vec<Prim>,
    pub outer: Vec<Prim>,
}

/// The Real HUD's own state: the max g latch.
#[derive(Clone, Debug, Default)]
pub struct RealHud {
    max_g: f64,
}

impl RealHud {
    pub fn max_g(&self) -> f64 {
        self.max_g
    }

    /// The max g resets (the pilot's reset).
    pub fn reset_max_g(&mut self) {
        self.max_g = 0.0;
    }

    pub fn frame(&mut self, f: Field, i: &Input) -> Frame {
        self.max_g = self.max_g.max(i.g);
        let mut out = Frame::default();
        // The scales on the field's edges (their numbers and boxes outside, as the original HUD's), the heading scale
        // along the bottom, the data windows under the scales.
        let tape_y = 0.5 * (f.top + f.bottom) - 10.0;
        airspeed(&mut out.outer, f.left, tape_y, i.kcas);
        altitude(&mut out.outer, f.right, tape_y, i.alt_ft);
        heading(&mut out.outer, f.bottom - 6.0, i.heading_deg, i.steerpoint.map(|s| s.bearing_deg));
        data(&mut out.outer, f, i, self.max_g);
        if let (Some(t), Some(z)) = (i.target, i.dlz) {
            dlz_scale(&mut out.outer, f.right - DLZ_X, tape_y, t, z);
        }
        if let (Some(c), Some(fpm)) = (i.ccip, i.fpm) {
            out.field.push(line(fpm, c));
        }
        if let Some(fpm) = i.fpm {
            ladder(&mut out.field, i.horizon, fpm, i.roll_deg, i.px_per_deg, f);
            marker(&mut out.field, fpm);
            if i.gear_down {
                aoa_bracket(&mut out.field, fpm, i.aoa_deg, i.px_per_deg);
            }
        }
        out
    }
}

/// A vertical scale's ticks: values `step` apart within ±half px of `v` at `k` px per unit, higher values up.
fn ticks(v: f64, step: f64, k: f64, half: f64) -> impl Iterator<Item = (f64, f64)> {
    let first = ((v - half / k) / step).ceil() as i64;
    let last = ((v + half / k) / step).floor() as i64;
    (first..=last).map(move |n| {
        let t = n as f64 * step;
        (t, -(t - v) * k)
    })
}

/// The airspeed scale (left): ticks pointing right, labels every 50 kt, the digital box pointing at the scale.
fn airspeed(p: &mut Vec<Prim>, x: f64, y0: f64, kcas: f64) {
    p.push(line((x, y0 - TAPE_HALF), (x, y0 + TAPE_HALF)));
    for (t, dy) in ticks(kcas, 10.0, KT_PX, TAPE_HALF) {
        if t < 0.0 {
            continue;
        }
        let major = (t as i64) % 50 == 0;
        p.push(line((x, y0 + dy), (x + if major { 5.0 } else { 3.0 }, y0 + dy)));
        if major && dy.abs() > 8.0 {
            p.push(text((x - 2.0, y0 + dy + 3.0), format!("{}", t as i64 / 10), Align::Right));
        }
    }
    let k = kcas.max(0.0).round() as i64;
    let (bx, by) = (x - 2.0, y0);
    p.extend(box_poly(bx - 26.0, by - 5.0, bx - 4.0, by + 5.0));
    p.push(line((bx - 4.0, by - 5.0), (bx, by)));
    p.push(line((bx, by), (bx - 4.0, by + 5.0)));
    p.push(text((bx - 6.0, by + 3.0), format!("{k}"), Align::Right));
}

/// The altitude scale (right): ticks pointing left, labels every 500 ft as thousands ("10,5"), the digital box with
/// the altitude as "10,450".
fn altitude(p: &mut Vec<Prim>, x: f64, y0: f64, alt_ft: f64) {
    p.push(line((x, y0 - TAPE_HALF), (x, y0 + TAPE_HALF)));
    for (t, dy) in ticks(alt_ft, 100.0, FT_PX, TAPE_HALF) {
        let major = (t as i64).rem_euclid(500) == 0;
        p.push(line((x, y0 + dy), (x - if major { 5.0 } else { 3.0 }, y0 + dy)));
        if major && dy.abs() > 8.0 {
            let h = (t / 100.0).round() as i64;
            p.push(text((x + 2.0, y0 + dy + 3.0), format!("{},{}", h.div_euclid(10), h.rem_euclid(10)), Align::Left));
        }
    }
    let a = alt_ft.round() as i64;
    let s = if a.abs() >= 1000 { format!("{},{:03}", a / 1000, (a % 1000).abs()) } else { format!("{a}") };
    let (bx, by) = (x + 2.0, y0);
    p.extend(box_poly(bx + 4.0, by - 5.0, bx + 34.0, by + 5.0));
    p.push(line((bx + 4.0, by - 5.0), (bx, by)));
    p.push(line((bx, by), (bx + 4.0, by + 5.0)));
    p.push(text((bx + 32.0, by + 3.0), s, Align::Right));
}

/// The heading scale (bottom): 5° ticks, labels every 10° in tens ("33"), the fixed caret on the centre, the steering
/// caret at the steerpoint's bearing (held at the scale's ends).
fn heading(p: &mut Vec<Prim>, y: f64, hdg: f64, bearing: Option<f64>) {
    p.push(line((-HDG_HALF, y), (HDG_HALF, y)));
    let first = ((hdg - HDG_HALF / HDG_PX) / 5.0).ceil() as i64;
    let last = ((hdg + HDG_HALF / HDG_PX) / 5.0).floor() as i64;
    for n in first..=last {
        let t = n * 5;
        let x = (t as f64 - hdg) * HDG_PX;
        let major = t.rem_euclid(10) == 0;
        p.push(line((x, y), (x, y - if major { 4.0 } else { 2.0 })));
        if major {
            p.push(text((x, y - 6.0), format!("{:02}", t.rem_euclid(360) / 10), Align::Centre));
        }
    }
    p.push(line((0.0, y), (-2.0, y + 3.0)));
    p.push(line((0.0, y), (2.0, y + 3.0)));
    if let Some(b) = bearing {
        let d = (b - hdg + 180.0).rem_euclid(360.0) - 180.0;
        let x = (d * HDG_PX).clamp(-HDG_HALF, HDG_HALF);
        p.push(line((x, y + 1.0), (x, y + 5.0)));
    }
}

/// The data windows under the scales: left the master mode, Mach, g and max g; right the steerpoint's distance (NM,
/// and its number) and the time to it (mm:ss).
fn data(p: &mut Vec<Prim>, f: Field, i: &Input, max_g: f64) {
    let (x, y) = (f.left - 30.0, 0.5 * (f.top + f.bottom) - 10.0 + TAPE_HALF + 14.0);
    p.push(text((x, y), i.master.clone(), Align::Left));
    if i.fuel_lbs < BINGO_LBS {
        p.push(text((x, y - 9.0), "FUEL", Align::Left));
    }
    p.push(text((x, y + 9.0), format!("{:.2}", i.mach).trim_start_matches('0').to_owned(), Align::Left));
    p.push(text((x, y + 18.0), format!("{:.1}", i.g), Align::Left));
    p.push(text((x, y + 27.0), format!("{max_g:.1}"), Align::Left));
    if let Some(t) = i.target {
        p.push(text((f.right + 36.0, y + 9.0), format!("F {:04.1}", t.range_m / NM), Align::Right));
    }
    if let Some(s) = i.steerpoint {
        let x = f.right + 36.0;
        p.push(text((x, y + 18.0), format!("{:03}>{:02}", (s.dist_m / NM).round() as i64, s.number), Align::Right));
        if let Some(t) = s.eta_s {
            let t = t.max(0.0).round() as i64;
            p.push(text((x, y + 27.0), format!("{:02}:{:02}", (t / 60).min(99), t % 60), Align::Right));
        }
    }
}

/// The DLZ scale (vertical, 0 at the bottom, the range scale at the top): Rmax and Rmin ticks to the left, the target's
/// range caret to the right with the closure in knots beside it.
fn dlz_scale(p: &mut Vec<Prim>, x: f64, y0: f64, t: Target, z: crate::missile::Dlz) {
    let top_nm = DLZ_SCALES_NM.iter().copied().find(|&n| n * NM > z.max.max(t.range_m)).unwrap_or(80.0);
    let y = |m: f64| y0 + DLZ_HALF - (m / (top_nm * NM)).clamp(0.0, 1.0) * 2.0 * DLZ_HALF;
    p.push(line((x, y0 - DLZ_HALF), (x, y0 + DLZ_HALF)));
    p.push(text((x, y0 - DLZ_HALF - 2.0), format!("{}", top_nm as i64), Align::Centre));
    for m in [z.max, z.min] {
        p.push(line((x - 4.0, y(m)), (x, y(m))));
    }
    let r = y(t.range_m);
    p.push(line((x, r), (x + 3.0, r - 2.0)));
    p.push(line((x, r), (x + 3.0, r + 2.0)));
    p.push(text((x - 6.0, r + 3.0), format!("{}", (t.closure * MS_TO_KT).round() as i64), Align::Right));
}

/// The conformal pitch ladder centred on the marker: rungs every 5° within the field, rolled about the boresight; the
/// horizon line long and plain; climb rungs solid with their tips down, dive rungs dashed with their tips up; labels
/// (|pitch|) at both ends.
fn ladder(p: &mut Vec<Prim>, horizon: (f64, f64), fpm: (f64, f64), roll: f64, k: f64, f: Field) {
    if k <= 0.0 {
        return;
    }
    // The rolled axes on the HUD (x right, y down): along the rungs and up the ladder (a right roll turns the
    // horizon anticlockwise). The rungs hang on the horizon point and slide along their own axis to the marker.
    let (s, c) = roll.to_radians().sin_cos();
    let (eu, ev) = ((c, -s), (-s, -c));
    let hv = horizon.0 * ev.0 + horizon.1 * ev.1;
    let mu = (fpm.0 - horizon.0) * eu.0 + (fpm.1 - horizon.1) * eu.1;
    let at = |u: f64, v: f64| (horizon.0 + (u + mu) * eu.0 + v * ev.0, horizon.1 + (u + mu) * eu.1 + v * ev.1);
    // The rungs whose lines can cross the field: the field's centre is −hv / k degrees up the ladder.
    let (centre, reach) = (-hv / k, (f.bottom - f.top).max(f.right - f.left) / k);
    let first = ((centre - reach) / RUNG_STEP as f64).ceil() as i64;
    let last = ((centre + reach) / RUNG_STEP as f64).floor() as i64;
    for n in first.max(-90 / RUNG_STEP)..=last.min(90 / RUNG_STEP) {
        let deg = n * RUNG_STEP;
        let v = deg as f64 * k;
        // Not over the heading scale along the bottom.
        if at(0.0, v).1 > f.bottom - HEADING_BAND {
            continue;
        }
        if deg == 0 {
            for side in [-1.0, 1.0] {
                p.push(line(at(side * RUNG_GAP * 2.0, v), at(side * (RUNG_GAP * 2.0 + RUNG_LEN * 2.0), v)));
            }
            continue;
        }
        let tip = if deg > 0 { -TIP } else { TIP };
        for side in [-1.0, 1.0] {
            let (u0, u1) = (side * RUNG_GAP, side * (RUNG_GAP + RUNG_LEN));
            if deg > 0 {
                p.push(line(at(u0, v), at(u1, v)));
            } else {
                for d in 0..3 {
                    let a = u0 + side * RUNG_LEN * d as f64 / 3.0;
                    p.push(line(at(a, v), at(a + side * RUNG_LEN * 0.2, v)));
                }
            }
            p.push(line(at(u0, v), at(u0, v + tip)));
            let (lx, ly) = at(u1 + side * 4.0, v);
            p.push(text((lx, ly + 3.0), format!("{}", deg.abs()), if side < 0.0 { Align::Right } else { Align::Left }));
        }
    }
}

/// The flight path marker: the circle, the wings and the fin.
fn marker(p: &mut Vec<Prim>, (x, y): (f64, f64)) {
    p.push(Prim::Circle { c: (x, y), r: FPM_R });
    p.push(line((x - FPM_R, y), (x - 2.0 * FPM_R - 4.0, y)));
    p.push(line((x + FPM_R, y), (x + 2.0 * FPM_R + 4.0, y)));
    p.push(line((x, y - FPM_R), (x, y - 2.0 * FPM_R)));
}

/// The AoA bracket left of the marker (gear down): its ends at 15° and 11° AoA, so the marker sits inside it from 11°
/// to 15° (more AoA: the bracket moves down past the marker).
fn aoa_bracket(p: &mut Vec<Prim>, (x, y): (f64, f64), aoa: f64, k: f64) {
    let bx = x - 2.0 * FPM_R - 8.0;
    let top = y + (aoa - AOA_HIGH) * k;
    let bottom = y + (aoa - AOA_LOW) * k;
    p.push(line((bx, top), (bx, bottom)));
    p.push(line((bx, top), (bx + 3.0, top)));
    p.push(line((bx, bottom), (bx + 3.0, bottom)));
}

fn box_poly(x0: f64, y0: f64, x1: f64, y1: f64) -> [Prim; 4] {
    [line((x0, y0), (x1, y0)), line((x1, y0), (x1, y1)), line((x1, y1), (x0, y1)), line((x0, y1), (x0, y0))]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::missile::Dlz;

    const FIELD: Field = Field { left: -80.0, top: -70.0, right: 80.0, bottom: 70.0 };

    fn texts(ps: &[Prim]) -> Vec<&str> {
        ps.iter()
            .filter_map(|p| match p {
                Prim::Text { text, .. } => Some(text.as_str()),
                _ => None,
            })
            .collect()
    }

    fn input() -> Input {
        Input {
            kcas: 352.4,
            alt_ft: 10450.0,
            heading_deg: 333.0,
            mach: 0.85,
            g: 2.3,
            fpm: Some((0.0, 10.0)),
            px_per_deg: 6.0,
            master: "NAV".into(),
            steerpoint: Some(Steerpoint { number: 3, bearing_deg: 10.0, dist_m: 12.0 * NM, eta_s: Some(323.0) }),
            fuel_lbs: 5000.0,
            ..Input::default()
        }
    }

    #[test]
    fn boxes_scales_and_data() {
        let mut h = RealHud::default();
        let fr = h.frame(FIELD, &input());
        let t = texts(&fr.outer);
        for want in ["352", "10,450", "40", "11,0", "33", ".85", "2.3", "012>03", "05:23", "NAV"] {
            assert!(t.contains(&want), "{want} in {t:?}");
        }
        h.frame(FIELD, &Input { g: 1.0, ..input() });
        assert_eq!(h.max_g(), 2.3, "max g latches");
    }

    #[test]
    fn ladder_rungs_and_bracket() {
        let mut h = RealHud::default();
        let fr = h.frame(FIELD, &Input { horizon: (0.0, 12.0), gear_down: true, aoa_deg: 13.0, ..input() });
        let t = texts(&fr.field);
        assert!(t.contains(&"5") && t.contains(&"10"), "{t:?}");
        // The bracket's ends 2° above and below the marker at 13° AoA.
        assert!(fr.field.contains(&Prim::Line { a: (-16.0, -2.0), b: (-16.0, 22.0) }));
    }

    #[test]
    fn weapon_cues() {
        let mut h = RealHud::default();
        let t = Target { range_m: 15.0 * NM, closure: 200.0 };
        let i = Input {
            target: Some(t),
            dlz: Some(Dlz { max: 18.0 * NM, min: 2.0 * NM }),
            ccip: Some((5.0, 40.0)),
            fuel_lbs: 1000.0,
            ..input()
        };
        let fr = h.frame(FIELD, &i);
        let tx = texts(&fr.outer);
        for want in ["F 15.0", "389", "20", "FUEL"] {
            assert!(tx.contains(&want), "{want} in {tx:?}");
        }
        assert!(fr.field.contains(&Prim::Line { a: (0.0, 10.0), b: (5.0, 40.0) }), "the bomb fall line");
    }
}
