//! The "Real HUD" (ours, Extras > HUD): each jet's real head-up display, gunsight or helmet display instead of the
//! original's simplified 1998 symbology, laid out as drawing primitives in the original's HUD pixels (x right, y down,
//! from the HUD centre); the cockpit draws them. The per-aircraft reference, its sources and how sure each element is:
//! docs/real-hud.md.
//!
//! - `f16`: the F-16C/D Block 30/40/50 HUD (dash-34); also the Lavi's (its symbology is not public) and, as marked
//!   reconstructions, the Kurnass 2000's and the Kfir's.
//! - `f15`: the F-15A/C HUD (TO 1F-15A-1, NADC 1976): moving tapes, no digital boxes.
//! - `f35`: the F-35's helmet display (the forward "virtual HUD"; LM slides and flight-test video).
//! - `sights`: the F-4E's AN/ASG-26 LCOSS and the Mirage IIICJ's CSF gyro gunsight (no HUD: a reticle only).

mod f15;
mod f16;
mod f35;
mod sights;

use crate::missile::Dlz;

/// A point in HUD pixels.
pub type P = (f64, f64);

/// Degrees per milliradian.
const MR_DEG: f64 = 0.0572958;
/// m → NM, m → ft, m/s → kt.
const NM: f64 = 1852.0;
const FT: f64 = 0.3048;
const MS_TO_KT: f64 = 1.943844;
/// Ours: the bingo fuel (lb) below which the bingo cue shows (the real one is set by the pilot).
pub const BINGO_LBS: f64 = 1500.0;

/// The jet whose display is drawn.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Jet {
    #[default]
    F16,
    F15,
    F35,
    /// The F-4E's optical sight.
    Phantom,
    /// The Mirage IIICJ's gyro gunsight.
    Mirage,
}

impl Jet {
    /// The display of a cockpit directory: f16 / lavi / f4-2000 / cfir (and anything else) the F-16's.
    pub fn of_cockpit(dir: &str) -> Self {
        let d = dir.to_ascii_lowercase();
        if d.contains("f35") {
            Jet::F35
        } else if d.ends_with("f15") {
            Jet::F15
        } else if d.ends_with("phantom") {
            Jet::Phantom
        } else if d.ends_with("mirage") {
            Jet::Mirage
        } else {
            Jet::F16
        }
    }
}

/// Text alignment at its anchor (the baseline's left, centre or right end).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Align {
    Left,
    Centre,
    Right,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Prim {
    Line { a: P, b: P },
    Circle { c: P, r: f64 },
    /// A filled dot.
    Dot { c: P, r: f64 },
    /// An arc from `from` clockwise through `sweep` (radians, 0 = 12 o'clock).
    Arc { c: P, r: f64, from: f64, sweep: f64 },
    Text { at: P, text: String, align: Align },
}

fn line(a: P, b: P) -> Prim {
    Prim::Line { a, b }
}

fn text(at: P, t: impl Into<String>, align: Align) -> Prim {
    Prim::Text { at, text: t.into(), align }
}

fn add(a: P, b: P) -> P {
    (a.0 + b.0, a.1 + b.1)
}

fn box_poly(x0: f64, y0: f64, x1: f64, y1: f64) -> [Prim; 4] {
    [line((x0, y0), (x1, y0)), line((x1, y0), (x1, y1)), line((x1, y1), (x0, y1)), line((x0, y1), (x0, y0))]
}

/// The symbology field in HUD pixels from the HUD centre.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Field {
    pub left: f64,
    pub top: f64,
    pub right: f64,
    pub bottom: f64,
}

impl Field {
    fn contains(&self, p: P) -> bool {
        p.0 >= self.left && p.0 <= self.right && p.1 >= self.top && p.1 <= self.bottom
    }

    fn centre_y(&self) -> f64 {
        0.5 * (self.top + self.bottom)
    }

    /// A point held on the field's edge along the line from `from` (inside), and whether it was limited.
    fn clamp_from(&self, from: P, p: P) -> (P, bool) {
        if self.contains(p) {
            return (p, false);
        }
        let d = (p.0 - from.0, p.1 - from.1);
        let mut k: f64 = 1.0;
        if d.0 < 0.0 {
            k = k.min((self.left - from.0) / d.0);
        }
        if d.0 > 0.0 {
            k = k.min((self.right - from.0) / d.0);
        }
        if d.1 < 0.0 {
            k = k.min((self.top - from.1) / d.1);
        }
        if d.1 > 0.0 {
            k = k.min((self.bottom - from.1) / d.1);
        }
        ((from.0 + d.0 * k, from.1 + d.1 * k), true)
    }
}

/// The locked target: range (m), closure (m/s, positive closing), its HUD point (None: behind the view).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Target {
    pub range_m: f64,
    pub closure: f64,
    pub at: Option<P>,
}

/// The current steerpoint: its number, bearing (°), distance (m), the time to it (s; None when not closing) and its HUD
/// point on the ground (None: behind the view).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Steerpoint {
    pub number: i64,
    pub bearing_deg: f64,
    pub dist_m: f64,
    pub eta_s: Option<f64>,
    pub at: Option<P>,
}

/// The weapon state the display needs.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Weapons {
    /// The original's HUD mode: 0 NAV, 1 SRM, 2 MRM, 3 A-A gun, 4 A-G gun, 5 bombs, 6 laser bombs, 7 TV, 8 HARM.
    pub hud_mode: i64,
    /// Rounds of the selected store; the SRM and MRM rounds aboard.
    pub selected: i64,
    pub srm: i64,
    pub mrm: i64,
    /// HUD points: the IR seeker (mode 1), the AA gun's lead-computing pipper (mode 3), the strafe / CCIP pipper
    /// (modes 4..6), the MRM steering point (mode 2).
    pub seeker: Option<P>,
    pub lcos: Option<P>,
    pub pipper: Option<P>,
    pub steering: Option<P>,
    /// The MRM launch circle's size (the original's 5 / 3 .. 5).
    pub circle: f64,
    pub shoot: bool,
}

/// One frame's values.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Input {
    pub jet: Jet,
    /// Sim seconds (the animated symbols).
    pub time_s: f64,
    /// The F-35's helmet looking off the nose (the head-stabilised set) and the head's heading (°).
    pub off_boresight: bool,
    pub head_heading_deg: f64,
    pub kcas: f64,
    pub ground_kt: f64,
    pub tas_ms: f64,
    pub alt_ft: f64,
    /// Radar altitude (ft), None when invalid.
    pub agl_ft: Option<f64>,
    pub vs_fpm: f64,
    pub heading_deg: f64,
    pub roll_deg: f64,
    pub mach: f64,
    pub g: f64,
    pub aoa_deg: f64,
    pub gear_down: bool,
    pub fuel_lbs: f64,
    /// The flight path marker (None: off the view), the boresight / waterline and the gun cross in HUD pixels.
    pub fpm: Option<P>,
    pub boresight: P,
    pub gun_cross: P,
    /// The horizon straight ahead (the level direction along the heading) in HUD pixels and the view's HUD pixels per
    /// degree: the conformal ladder.
    pub horizon: P,
    pub px_per_deg: f64,
    pub steerpoint: Option<Steerpoint>,
    pub target: Option<Target>,
    /// The selected store's launch zone at the target (m).
    pub dlz: Option<Dlz>,
    pub weapons: Weapons,
}

impl Input {
    /// Milliradians → HUD pixels.
    fn mr(&self, mr: f64) -> f64 {
        mr * MR_DEG * self.px_per_deg
    }

    /// Degrees → HUD pixels.
    fn deg(&self, d: f64) -> f64 {
        d * self.px_per_deg
    }
}

/// A frame: `field` is clipped to the symbology field, `outer` is not; `colour` overrides the HUD's colour (the
/// sights' lamp-lit reticles) and `sight` means the jet has no HUD (the original HUD is not drawn at all).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Frame {
    pub field: Vec<Prim>,
    pub outer: Vec<Prim>,
    pub colour: Option<[f32; 3]>,
    pub sight: bool,
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
        match i.jet {
            Jet::F16 => f16::frame(f, i, self.max_g),
            Jet::F15 => f15::frame(f, i),
            Jet::F35 => f35::frame(f, i, self.max_g),
            Jet::Phantom => sights::lcoss(i),
            Jet::Mirage => sights::csf(i),
        }
    }
}

// --- shared pieces ----------------------------------------------------------------------------------------------

/// A vertical scale's ticks: values `step` apart within ±half px of `v` at `k` px per unit; `up`: higher values up.
fn ticks(v: f64, step: f64, k: f64, half: f64, up: bool) -> impl Iterator<Item = (f64, f64)> {
    let first = ((v - half / k) / step).ceil() as i64;
    let last = ((v + half / k) / step).floor() as i64;
    (first..=last).map(move |n| {
        let t = n as f64 * step;
        (t, (t - v) * k * if up { -1.0 } else { 1.0 })
    })
}

/// How the ladder's rungs look.
#[derive(Clone, Copy, Debug)]
struct LadderStyle {
    /// Rung half: gap from the centre line and length (px); the horizon's.
    gap: f64,
    len: f64,
    horizon_gap: f64,
    horizon_len: f64,
    tip: f64,
    /// The tips at the rungs' inner ends (F-35) instead of the outer ends (F-15, F-16).
    inner_tips: bool,
    /// Rungs bend toward the horizon by half their angle (F-16 "bendy bars").
    bend: bool,
    /// Labels at both ends (else the left only); signed ("-5") or not.
    both_labels: bool,
    signed: bool,
    /// Rungs whose centre falls within these bands of the field's bottom / top are left out (the heading scale's).
    bottom_band: f64,
    top_band: f64,
}

/// The conformal pitch ladder: rung e sits e degrees up from the level point ahead, rolled with the jet, slid along
/// the rungs to the marker; climb rungs solid with their tips toward the horizon, dive rungs dashed.
fn ladder(p: &mut Vec<Prim>, i: &Input, fpm: P, f: Field, s: LadderStyle) {
    let k = i.px_per_deg;
    if k <= 0.0 {
        return;
    }
    let (sn, cs) = i.roll_deg.to_radians().sin_cos();
    let (eu, ev) = ((cs, -sn), (-sn, -cs));
    let h = i.horizon;
    let hv = h.0 * ev.0 + h.1 * ev.1;
    let mu = (fpm.0 - h.0) * eu.0 + (fpm.1 - h.1) * eu.1;
    let at = |u: f64, v: f64| (h.0 + (u + mu) * eu.0 + v * ev.0, h.1 + (u + mu) * eu.1 + v * ev.1);
    let (centre, reach) = (-hv / k, (f.bottom - f.top).max(f.right - f.left) / k);
    let first = ((centre - reach) / 5.0).ceil() as i64;
    let last = ((centre + reach) / 5.0).floor() as i64;
    for n in first.max(-18)..=last.min(18) {
        let deg = n * 5;
        let v = deg as f64 * k;
        let y = at(0.0, v).1;
        if y > f.bottom - s.bottom_band || y < f.top + s.top_band {
            continue;
        }
        if deg == 0 {
            for side in [-1.0, 1.0] {
                p.push(line(at(side * s.horizon_gap, v), at(side * (s.horizon_gap + s.horizon_len), v)));
            }
            continue;
        }
        // The rung's outer end drops toward the horizon by half its angle when bent.
        let slope = if s.bend { -(deg as f64 / 2.0).to_radians().tan() } else { 0.0 };
        let tip = if deg > 0 { -s.tip } else { s.tip };
        for side in [-1.0, 1.0] {
            let pt = |u: f64| at(side * u, v + slope * (u - s.gap));
            if deg > 0 {
                p.push(line(pt(s.gap), pt(s.gap + s.len)));
            } else {
                for d in 0..3 {
                    let a = s.gap + s.len * d as f64 / 3.0;
                    p.push(line(pt(a), pt(a + s.len * 0.2)));
                }
            }
            let u = if s.inner_tips { s.gap } else { s.gap + s.len };
            let base = pt(u);
            p.push(line(base, (base.0 + tip * ev.0, base.1 + tip * ev.1)));
            if s.both_labels || side < 0.0 {
                let label = if s.signed { format!("{deg}") } else { format!("{}", deg.abs()) };
                let (lx, ly) = pt(s.gap + s.len + 4.0);
                p.push(text((lx, ly + 3.0), label, if side < 0.0 { Align::Right } else { Align::Left }));
            }
        }
    }
}

/// The flight path marker: a circle of radius `r` with wings `wing` long and a fin `fin` long (px).
fn marker(p: &mut Vec<Prim>, (x, y): P, r: f64, wing: f64, fin: f64) {
    p.push(Prim::Circle { c: (x, y), r });
    p.push(line((x - r, y), (x - r - wing, y)));
    p.push(line((x + r, y), (x + r + wing, y)));
    p.push(line((x, y - r), (x, y - r - fin)));
}

/// An X over a symbol limited at the field's edge.
fn x_over(p: &mut Vec<Prim>, (x, y): P, h: f64) {
    p.push(line((x - h, y - h), (x + h, y + h)));
    p.push(line((x - h, y + h), (x + h, y - h)));
}

fn diamond(p: &mut Vec<Prim>, (x, y): P, h: f64) {
    p.push(line((x, y - h), (x + h, y)));
    p.push(line((x + h, y), (x, y + h)));
    p.push(line((x, y + h), (x - h, y)));
    p.push(line((x - h, y), (x, y - h)));
}

/// The "-W-" waterline symbol at `c`, `w` px half wide.
fn waterline(p: &mut Vec<Prim>, (x, y): P, w: f64) {
    let q = w / 4.0;
    p.push(line((x - w, y), (x - 2.0 * q, y)));
    p.push(line((x - 2.0 * q, y), (x - q, y + q)));
    p.push(line((x - q, y + q), (x, y)));
    p.push(line((x, y), (x + q, y + q)));
    p.push(line((x + q, y + q), (x + 2.0 * q, y)));
    p.push(line((x + 2.0 * q, y), (x + w, y)));
}

/// The EEGS funnel's wingspan (ours: set by the pilot in the real jet) and the M61A1's muzzle speed.
const WINGSPAN_FT: f64 = 35.0;
const MUZZLE: f64 = 1036.0;

/// The EEGS funnel's centre at range `r_ft` for a load factor `g` (HUD px): where the rounds fired one time of flight
/// ago are now — the gun line moved by the jet's pitch rate (n − cos φ)·g / V, and gravity — and the funnel's half
/// width there (the wingspan at that range).
fn funnel_at(i: &Input, r_ft: f64, g: f64) -> (P, f64) {
    const G: f64 = 9.80665;
    let v = i.tas_ms.max(50.0);
    let roll = i.roll_deg.to_radians();
    let omega = (g - roll.cos()) * G / v;
    let r = r_ft * FT;
    let t = r / (MUZZLE + v);
    let drop = gravity_drop(t, r);
    let down = (omega * t + drop * roll.cos()).to_degrees();
    let side = (drop * roll.sin()).to_degrees();
    let half = ((WINGSPAN_FT * FT / 2.0) / r).atan().to_degrees();
    (add(i.gun_cross, (i.deg(side), i.deg(down))), i.deg(half))
}

/// The A-A gun's funnel (EEGS, F-16, dash-34 fig. 1-257): two lines whose midpoint at each range from 600 ft (top) to
/// `max_ft` (3,000 ft without a lock; longer, toward the HUD's bottom, once the radar tracks the target) is the aim
/// point at that range and whose width is the wingspan there.
fn funnel(p: &mut Vec<Prim>, i: &Input, max_ft: f64) {
    let mut left = Vec::new();
    let mut right = Vec::new();
    let mut r = 600.0;
    while r <= max_ft {
        let (c, half) = funnel_at(i, r, i.g);
        left.push((c.0 - half, c.1));
        right.push((c.0 + half, c.1));
        r += 200.0;
    }
    for l in [left, right] {
        for w in l.windows(2) {
            p.push(line(w[0], w[1]));
        }
    }
}

/// The angle (rad) a round falls below its line at range `r` after `t` seconds.
fn gravity_drop(t: f64, r: f64) -> f64 {
    9.80665 * t * t / 2.0 / r
}

/// The pipper of a lead-computing / CCIP sight: a dot of `dot` px inside a circle of `ring` px.
fn pipper(p: &mut Vec<Prim>, c: P, dot: f64, ring: f64) {
    p.push(Prim::Dot { c, r: dot });
    p.push(Prim::Circle { c, r: ring });
}

/// A vertical launch-zone / range scale: 0 at the bottom, the radar range (10 / 20 / 40 / 80 NM, the smallest above
/// Rmax and the range) at the top; Rmax / Rmin ticks; the target's range caret with the closure (kt) left of it.
fn dlz_scale(p: &mut Vec<Prim>, x: f64, y0: f64, half: f64, t: Target, z: Dlz) {
    const SCALES_NM: [f64; 4] = [10.0, 20.0, 40.0, 80.0];
    let top_nm = SCALES_NM.iter().copied().find(|&n| n * NM > z.max.max(t.range_m)).unwrap_or(80.0);
    let y = |m: f64| y0 + half - (m / (top_nm * NM)).clamp(0.0, 1.0) * 2.0 * half;
    p.push(line((x, y0 - half), (x, y0 + half)));
    p.push(text((x, y0 - half - 2.0), format!("{}", top_nm as i64), Align::Centre));
    for m in [z.max, z.min] {
        p.push(line((x, y(m)), (x + 4.0, y(m))));
    }
    let r = y(t.range_m);
    p.push(line((x, r), (x - 3.0, r - 2.0)));
    p.push(line((x, r), (x - 3.0, r + 2.0)));
    p.push(text((x - 5.0, r + 3.0), format!("{}>", (t.closure * MS_TO_KT / 10.0).round() as i64 * 10), Align::Right));
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(super) const FIELD: Field = Field { left: -80.0, top: -70.0, right: 80.0, bottom: 70.0 };

    pub(super) fn texts(ps: &[Prim]) -> Vec<&str> {
        ps.iter()
            .filter_map(|p| match p {
                Prim::Text { text, .. } => Some(text.as_str()),
                _ => None,
            })
            .collect()
    }

    pub(super) fn input(jet: Jet) -> Input {
        Input {
            jet,
            kcas: 352.4,
            ground_kt: 380.0,
            tas_ms: 200.0,
            alt_ft: 10450.0,
            heading_deg: 333.0,
            mach: 0.85,
            g: 2.3,
            fuel_lbs: 5000.0,
            fpm: Some((0.0, 10.0)),
            horizon: (0.0, 10.0),
            px_per_deg: 12.0,
            steerpoint: Some(Steerpoint {
                number: 3,
                bearing_deg: 10.0,
                dist_m: 12.0 * NM,
                eta_s: Some(323.0),
                at: Some((30.0, 20.0)),
            }),
            ..Input::default()
        }
    }

    #[test]
    fn cockpits_pick_their_display() {
        assert_eq!(Jet::of_cockpit("converted/cockpits/f15"), Jet::F15);
        assert_eq!(Jet::of_cockpit("converted/cockpits/lavi"), Jet::F16);
        assert_eq!(Jet::of_cockpit("res://extra/planes/f35i/cockpit"), Jet::F35);
        assert_eq!(Jet::of_cockpit("converted/cockpits/phantom"), Jet::Phantom);
        assert_eq!(Jet::of_cockpit("converted/cockpits/mirage"), Jet::Mirage);
    }

    #[test]
    fn the_funnel_narrows_and_sags_with_range() {
        let mut p = Vec::new();
        let i = Input { g: 4.0, ..input(Jet::F16) };
        funnel(&mut p, &i, 3000.0);
        let lines: Vec<(P, P)> = p.iter().filter_map(|x| if let Prim::Line { a, b } = x { Some((*a, *b)) } else { None }).collect();
        let (near, far) = (lines[0].0, lines[lines.len() / 2 - 1].1);
        assert!(far.1 > near.1, "pulling 4 g: the far end of the funnel lower");
        assert!(far.0 > near.0, "the left line narrows toward the centre");
    }

    #[test]
    fn edge_clamp() {
        let (p, lim) = FIELD.clamp_from((0.0, 0.0), (160.0, 0.0));
        assert!(lim && p == (80.0, 0.0));
    }
}
