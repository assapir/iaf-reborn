//! World scale Real 1:1: each airbase at its real place (docs/world-scale.md §3.3, "the base move").
//!
//! One similarity per base puts the game's main runway (the runway through the iaf.ibx lineup point, on the line at
//! RunwayNumber's heading) on the real one from `data/real_runways.csv` (© OpenStreetMap contributors, ODbL). Zone A
//! (the base's box) takes the similarity; zone B (6 km beyond it, at the bases moved more than 5 km) moves and turns
//! with the base without scaling. Coordinates: engine metres, X east, Y north; headings clockwise from north.

use crate::airbase::{Airbase, TaxiPt};
use iaf_formats::terrain_types::RUNWAY;

/// terraintype.dat's land bit: with it, ground off a runway is rough (flight-model.md §15.6.2).
const LAND: i32 = 0x1;

/// The real runway table (tools/real_runways.py).
pub const REAL_RUNWAYS_CSV: &str = include_str!("../data/real_runways.csv");
/// The width of a real runway without an OSM width tag (decided by the agent, docs/world-scale.md §5).
pub const DEFAULT_WIDTH: f64 = 45.0;
/// Zone A: the box around the base's runway ends and iaf.ibx points, plus this (m, game frame).
pub const BOX_MARGIN: f64 = 500.0;
/// Zone B reaches this far beyond zone A (m), at the bases moved farther than `FAR`.
pub const ZONE_B: f64 = 6000.0;
pub const FAR: f64 = 5000.0;
/// The flattened site blends into the original ground over this ring (m) around the moved zone A.
pub const RING: f64 = 1200.0;
/// The old site's fine art warped onto the new site fades in over this far inside the new zone A's edge (m).
pub const INSET_FADE: f64 = 250.0;

/// A real runway: its ends (engine metres) and width (m).
#[derive(Debug, Clone, PartialEq)]
pub struct RealRunway {
    pub base: String,
    pub a: [f64; 2],
    pub b: [f64; 2],
    pub width: f64,
    /// The runway's designator ("07L/25R"): the OSM ref, else from the magnetic heading (tools/real_runways.py).
    pub designator: String,
}

/// Every row of the table.
pub fn real_runways() -> Vec<RealRunway> {
    REAL_RUNWAYS_CSV
        .lines()
        .filter(|l| !l.starts_with('#') && !l.starts_with("base,") && !l.trim().is_empty())
        .filter_map(|l| {
            let c: Vec<&str> = l.split(',').collect();
            let f = |i: usize| c.get(i)?.trim().parse::<f64>().ok();
            Some(RealRunway {
                base: c.first()?.to_string(),
                a: [f(9)?, f(10)?],
                b: [f(11)?, f(12)?],
                width: f(4).unwrap_or(DEFAULT_WIDTH),
                designator: c.get(13).map_or(String::new(), |d| d.trim().to_string()),
            })
        })
        .collect()
}

/// The game's base as the setup measured it (airbases.json): its runways' ends, and iaf.ibx's points.
#[derive(Debug, Clone, Default)]
pub struct GameBase {
    pub name: String,
    pub lineup: [f64; 3],
    pub runway_deg: f64,
    /// The runways' ends; the first is the runway through the lineup point.
    pub runways: Vec<[[f64; 2]; 2]>,
    /// Points the base's box must hold (tower, taxi paths, hangars).
    pub points: Vec<[f64; 2]>,
}

impl GameBase {
    /// From an iaf.ibx base and its measured runways.
    pub fn new(b: &Airbase, runways: Vec<[[f64; 2]; 2]>) -> Self {
        let mut points = vec![[b.tower[0] as f64, b.tower[1] as f64]];
        for t in
            b.to_taxi.iter().chain(&b.from_taxi).chain(&b.hangars).chain(&b.to_hangar_turn).chain(&b.from_hangar_turn)
        {
            points.push([t.x as f64, t.y as f64]);
        }
        GameBase {
            name: b.name.clone(),
            lineup: b.lineup.map(f64::from),
            runway_deg: b.runway_deg as f64,
            runways,
            points,
        }
    }
}

/// Where a point went: its new position, the turn (deg, clockwise), the scale it took (k in zone A, 1 in zone B)
/// and the height to add.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Moved {
    pub p: [f64; 2],
    pub turn: f64,
    pub scale: f64,
    pub dz: f64,
}

/// A base's paved-surface mask (airbases.json `mask`, the `airbases/<base>.png` pixels): RGB, R = paved, G = concrete,
/// B = the distance to a taxi path; `origin` = the north-west corner (engine metres).
#[derive(Debug, Clone, Default)]
pub struct Mask {
    pub origin: [f64; 2],
    pub w: usize,
    pub h: usize,
    pub px_m: f64,
    pub rgb: Vec<u8>,
}

impl Mask {
    /// The (paved, concrete) coverage 0..1 at a point, nearest pixel; 0 outside.
    pub fn at(&self, p: [f64; 2]) -> [f64; 2] {
        let x = (p[0] - self.origin[0]) / self.px_m;
        let y = (self.origin[1] - p[1]) / self.px_m;
        if x < 0.0 || y < 0.0 || x >= self.w as f64 || y >= self.h as f64 || self.rgb.len() < 3 * self.w * self.h {
            return [0.0; 2];
        }
        let i = 3 * (y as usize * self.w + x as usize);
        [self.rgb[i] as f64 / 255.0, self.rgb[i + 1] as f64 / 255.0]
    }

    fn contains(&self, p: [f64; 2], margin: f64) -> bool {
        p[0] >= self.origin[0] - margin
            && p[0] <= self.origin[0] + self.w as f64 * self.px_m + margin
            && p[1] <= self.origin[1] + margin
            && p[1] >= self.origin[1] - self.h as f64 * self.px_m - margin
    }
}

fn dir(deg: f64) -> [f64; 2] {
    let r = deg.to_radians();
    [r.sin(), r.cos()]
}

fn heading(d: [f64; 2]) -> f64 {
    d[0].atan2(d[1]).to_degrees().rem_euclid(360.0)
}

fn sub(a: [f64; 2], b: [f64; 2]) -> [f64; 2] {
    [a[0] - b[0], a[1] - b[1]]
}

fn dot(a: [f64; 2], b: [f64; 2]) -> f64 {
    a[0] * b[0] + a[1] * b[1]
}

/// The heading difference b − a in (−180, 180].
fn wrap180(a: f64) -> f64 {
    let r = a.rem_euclid(360.0);
    if r > 180.0 { r - 360.0 } else { r }
}

/// One axis of zone A / B: k inside [lo, hi], unscaled beyond (continuous).
fn axis(t: f64, lo: f64, hi: f64, k: f64) -> f64 {
    if t < lo {
        k * lo + (t - lo)
    } else if t > hi {
        k * hi + (t - hi)
    } else {
        k * t
    }
}

fn smoothstep(e0: f64, e1: f64, x: f64) -> f64 {
    let t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// One base's move.
#[derive(Debug, Clone)]
pub struct BaseMove {
    pub name: String,
    /// The game runway's start end P0 (on the lineup line) and its direction (RunwayNumber).
    pub game_c: [f64; 2],
    pub game_d: [f64; 2],
    /// The real runway's start end A and direction.
    pub real_c: [f64; 2],
    pub real_d: [f64; 2],
    /// Real length / game length.
    pub k: f64,
    pub game_len: f64,
    pub real_len: f64,
    /// The real runway's width (m) and take-off heading (deg).
    pub width: f64,
    pub heading: f64,
    /// Real heading − RunwayNumber (deg, clockwise).
    pub turn: f64,
    /// Zone A in the game runway's frame (u along from P0, v to the right), metres.
    pub lo: [f64; 2],
    pub hi: [f64; 2],
    /// Zone B's reach beyond zone A (0: none).
    pub zone_b: f64,
    /// The old lineup's z and the new site's elevation (m).
    pub old_z: f64,
    pub elev: f64,
    /// The game runways (their ends), for the drawing.
    pub game_runways: Vec<[[f64; 2]; 2]>,
    /// The real runways' true headings (a → b) and designators.
    pub designators: Vec<(f64, String)>,
    pub mask: Option<Mask>,
    /// The old site's fill colour from a coarse level (`BaseMoves::add_fill_source`); None: each node's own.
    pub fill: Option<Fill>,
}

/// The colour around an old site on one world-aligned grid (a coarse terrain level's pixels, docs/world-scale.md
/// §4.3): the surroundings' mean per cell, so every node and level paints the old paved surface alike (no seams at
/// the node edges, where each node's own blur ran out of pixels).
#[derive(Debug, Clone, Default)]
pub struct Fill {
    /// The north-west corner (engine metres) and the cell size (m).
    pub nw: [f64; 2],
    pub px_m: f64,
    pub w: usize,
    pub h: usize,
    rgb: Vec<u8>,
    /// The fill colour per cell (the surroundings' mean plus the texture of unpaved ground 400 m away); empty until
    /// `BaseMoves::finish_fill`.
    mean: Vec<[f64; 3]>,
}

impl Fill {
    /// The fill colour at a point, bilinear; None outside or unfinished.
    fn mean_at(&self, p: [f64; 2]) -> Option<[f64; 3]> {
        if self.mean.is_empty() {
            return None;
        }
        let x = (p[0] - self.nw[0]) / self.px_m - 0.5;
        let y = (self.nw[1] - p[1]) / self.px_m - 0.5;
        if x < 0.0 || y < 0.0 || x > (self.w - 1) as f64 || y > (self.h - 1) as f64 {
            return None;
        }
        let (x0, y0) = (x as usize, y as usize);
        let (x1, y1) = ((x0 + 1).min(self.w - 1), (y0 + 1).min(self.h - 1));
        let (fx, fy) = (x - x0 as f64, y - y0 as f64);
        let m = |x: usize, y: usize| self.mean[y * self.w + x];
        let (a, b, c, d) = (m(x0, y0), m(x1, y0), m(x0, y1), m(x1, y1));
        Some(std::array::from_fn(|k| {
            (a[k] * (1.0 - fx) + b[k] * fx) * (1.0 - fy) + (c[k] * (1.0 - fx) + d[k] * fx) * fy
        }))
    }
}

impl BaseMove {
    /// The move of `g` onto its real runways (`real` rows of any base; those named like `g` are used); None without.
    pub fn new(g: &GameBase, real: &[RealRunway]) -> Option<Self> {
        let rows: Vec<&RealRunway> = real.iter().filter(|r| r.base == g.name).collect();
        let first = g.runways.first()?;
        let l = [g.lineup[0], g.lineup[1]];
        let d = dir(g.runway_deg);
        let r = [d[1], -d[0]];
        let (u0, u1) = {
            let (a, b) = (dot(sub(first[0], l), d), dot(sub(first[1], l), d));
            (a.min(b), a.max(b))
        };
        let game_c = [l[0] + u0 * d[0], l[1] + u0 * d[1]];
        let game_len = u1 - u0;
        // The real runway and direction nearest RunwayNumber's heading; within 1° the longer.
        type Pick = ([f64; 2], [f64; 2], f64, f64, f64); // a, b, heading diff, length, width
        let mut best: Option<Pick> = None;
        for row in &rows {
            for (a, b) in [(row.a, row.b), (row.b, row.a)] {
                let len = sub(b, a);
                let len = len[0].hypot(len[1]);
                let diff = wrap180(heading(sub(b, a)) - g.runway_deg).abs();
                let better = match best {
                    None => true,
                    Some((_, _, bd, bl, _)) => diff < bd - 1.0 || (diff <= bd + 1.0 && len > bl),
                };
                if better {
                    best = Some((a, b, diff, len, row.width));
                }
            }
        }
        let (a, b, _, real_len, width) = best?;
        let real_d = {
            let v = sub(b, a);
            [v[0] / real_len, v[1] / real_len]
        };
        let k = real_len / game_len;
        // Zone A: the runways' ends, the lineup and iaf.ibx's points, plus the margin.
        let uv = |p: [f64; 2]| [dot(sub(p, game_c), d), dot(sub(p, game_c), r)];
        let mut lo = [f64::MAX; 2];
        let mut hi = [f64::MIN; 2];
        let pts = g.runways.iter().flat_map(|e| e.iter().copied()).chain(g.points.iter().copied()).chain([l]);
        for p in pts {
            let q = uv(p);
            for i in 0..2 {
                lo[i] = lo[i].min(q[i] - BOX_MARGIN);
                hi[i] = hi[i].max(q[i] + BOX_MARGIN);
            }
        }
        let real_h = heading(real_d);
        let mut m = BaseMove {
            name: g.name.clone(),
            game_c,
            game_d: d,
            real_c: a,
            real_d,
            k,
            game_len,
            real_len,
            width,
            heading: real_h,
            turn: wrap180(real_h - g.runway_deg),
            lo,
            hi,
            zone_b: 0.0,
            old_z: g.lineup[2],
            elev: g.lineup[2],
            game_runways: g.runways.clone(),
            designators: rows.iter().map(|r| (heading(sub(r.b, r.a)), r.designator.clone())).collect(),
            mask: None,
            fill: None,
        };
        if m.offset() > FAR {
            m.zone_b = ZONE_B;
        }
        Some(m)
    }

    /// How far the base's middle moves (m).
    pub fn offset(&self) -> f64 {
        let c = [(self.lo[0] + self.hi[0]) * 0.5, (self.lo[1] + self.hi[1]) * 0.5];
        let a = self.game_xy(c);
        let b = self.real_xy([c[0] * self.k, c[1] * self.k]);
        let v = sub(b, a);
        v[0].hypot(v[1])
    }

    fn game_uv(&self, p: [f64; 2]) -> [f64; 2] {
        let d = self.game_d;
        let q = sub(p, self.game_c);
        [dot(q, d), dot(q, [d[1], -d[0]])]
    }

    fn game_xy(&self, uv: [f64; 2]) -> [f64; 2] {
        let d = self.game_d;
        [self.game_c[0] + uv[0] * d[0] + uv[1] * d[1], self.game_c[1] + uv[0] * d[1] - uv[1] * d[0]]
    }

    fn real_uv(&self, p: [f64; 2]) -> [f64; 2] {
        let d = self.real_d;
        let q = sub(p, self.real_c);
        [dot(q, d), dot(q, [d[1], -d[0]])]
    }

    fn real_xy(&self, uv: [f64; 2]) -> [f64; 2] {
        let d = self.real_d;
        [self.real_c[0] + uv[0] * d[0] + uv[1] * d[1], self.real_c[1] + uv[0] * d[1] - uv[1] * d[0]]
    }

    /// True inside the old zone A grown by `margin`.
    pub fn in_old(&self, p: [f64; 2], margin: f64) -> bool {
        let q = self.game_uv(p);
        (0..2).all(|i| q[i] >= self.lo[i] - margin && q[i] <= self.hi[i] + margin)
    }

    /// The point's move, None outside zone A / B.
    pub fn map(&self, p: [f64; 2]) -> Option<Moved> {
        let q = self.game_uv(p);
        let reach = self.zone_b;
        if !(0..2).all(|i| q[i] >= self.lo[i] - reach && q[i] <= self.hi[i] + reach) {
            return None;
        }
        let inside = (0..2).all(|i| q[i] >= self.lo[i] && q[i] <= self.hi[i]);
        let m = [axis(q[0], self.lo[0], self.hi[0], self.k), axis(q[1], self.lo[1], self.hi[1], self.k)];
        Some(Moved {
            p: self.real_xy(m),
            turn: self.turn,
            scale: if inside { self.k } else { 1.0 },
            dz: self.elev - self.old_z,
        })
    }

    /// The new zone A's point back in the game frame (the similarity's inverse); None outside it grown by `margin`.
    pub fn to_game(&self, p: [f64; 2], margin: f64) -> Option<[f64; 2]> {
        let q = self.real_uv(p);
        let k = self.k;
        let ok = (0..2).all(|i| q[i] >= k * self.lo[i] - margin && q[i] <= k * self.hi[i] + margin);
        ok.then(|| self.to_game_any(p))
    }

    /// The inverse similarity as an affine map: the game point of a new-site point is
    /// (a[0]·X + a[1]·Y + a[2], b[0]·X + b[1]·Y + b[2]).
    pub fn game_affine(&self) -> [[f64; 3]; 2] {
        let o = self.to_game_any([0.0, 0.0]);
        let ex = self.to_game_any([1.0, 0.0]);
        let ey = self.to_game_any([0.0, 1.0]);
        [[ex[0] - o[0], ey[0] - o[0], o[0]], [ex[1] - o[1], ey[1] - o[1], o[1]]]
    }

    fn to_game_any(&self, p: [f64; 2]) -> [f64; 2] {
        let q = self.real_uv(p);
        self.game_xy([q[0] / self.k, q[1] / self.k])
    }

    /// The new site's fine art (docs/world-scale.md §4.3): the old site's point that a new-site point shows (the
    /// similarity's inverse) and its weight, 1 deeper than `INSET_FADE` inside the new zone A, 0 at its edge; None
    /// outside.
    pub fn inset_source(&self, p: [f64; 2]) -> Option<([f64; 2], f64)> {
        let q = self.real_uv(p);
        let (k, lo, hi) = (self.k, self.lo, self.hi);
        let d = (q[0] - k * lo[0]).min(k * hi[0] - q[0]).min(q[1] - k * lo[1]).min(k * hi[1] - q[1]);
        (d > 0.0).then(|| (self.to_game_any(p), smoothstep(0.0, INSET_FADE, d)))
    }

    /// Zone A's box (engine metres [x0, y0, x1, y1]): the old site's (`new` false) or the new site's.
    pub fn zone_box(&self, new: bool) -> [f64; 4] {
        let (lo, hi, k) = (self.lo, self.hi, self.k);
        [[lo[0], lo[1]], [hi[0], lo[1]], [hi[0], hi[1]], [lo[0], hi[1]]]
            .iter()
            .map(|q| if new { self.real_xy([q[0] * k, q[1] * k]) } else { self.game_xy(*q) })
            .fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |r, p| {
                [r[0].min(p[0]), r[1].min(p[1]), r[2].max(p[0]), r[3].max(p[1])]
            })
    }

    /// Draws the old site's fine art over a new-site image (RGBA8; `px(x, y)` = the pixel centre's engine position,
    /// `sample` = the old art's colour at an engine point): colour and alpha = `inset_source`'s weight, where it is
    /// above the alpha already there. True when any pixel took it.
    pub fn bake_inset(
        &self,
        rgba: &mut [u8],
        w: usize,
        h: usize,
        px: impl Fn(usize, usize) -> [f64; 2],
        mut sample: impl FnMut([f64; 2]) -> Option<[f64; 3]>,
    ) -> bool {
        let mut any = false;
        for y in 0..h {
            for x in 0..w {
                let i = 4 * (y * w + x);
                let Some((q, wt)) = self.inset_source(px(x, y)) else { continue };
                let a = (wt * 255.0).round() as u8;
                if i + 3 >= rgba.len() || a <= rgba[i + 3] {
                    continue;
                }
                let Some(c) = sample(q) else { continue };
                for ch in 0..3 {
                    rgba[i + ch] = c[ch].round().clamp(0.0, 255.0) as u8;
                }
                rgba[i + 3] = a;
                any = true;
            }
        }
        any
    }

    /// The flattening's weight at a point: 1 on the new zone A, falling to 0 over `RING`.
    pub fn pad_weight(&self, p: [f64; 2]) -> f64 {
        let q = self.real_uv(p);
        let k = self.k;
        let du = (k * self.lo[0] - q[0]).max(q[0] - k * self.hi[0]).max(0.0);
        let dv = (k * self.lo[1] - q[1]).max(q[1] - k * self.hi[1]).max(0.0);
        1.0 - smoothstep(0.0, RING, du.hypot(dv))
    }

    /// The real designator's number (1–36) of a runway direction at the new site, `heading` true (deg): the half of
    /// the real runway within 15° of it whose number is nearest the heading; else from the heading (36 for 0).
    pub fn designator(&self, heading: f64) -> i64 {
        let mut best: Option<(f64, i64)> = None;
        for (h, d) in &self.designators {
            if wrap180(h - heading).abs().min(wrap180(h + 180.0 - heading).abs()) > 15.0 {
                continue;
            }
            for half in d.split('/') {
                let Ok(n) = half.trim_end_matches(|c: char| c.is_ascii_alphabetic()).parse::<i64>() else { continue };
                let e = wrap180(n as f64 * 10.0 - heading).abs();
                if best.is_none_or(|(be, _)| e < be) {
                    best = Some((e, n));
                }
            }
        }
        match best {
            Some((e, n)) if e < 30.0 => n,
            _ => match (heading.rem_euclid(360.0) / 10.0).round() as i64 % 36 {
                0 => 36,
                n => n,
            },
        }
    }

    /// iaf.ibx's base at the new site: its points mapped (z + dz), headings turned, RunwayNumber the real heading.
    pub fn map_airbase(&self, b: &mut Airbase) {
        let mp = |p: [f32; 3]| -> [f32; 3] {
            let m = self.map([p[0] as f64, p[1] as f64]);
            m.map_or(p, |m| [m.p[0] as f32, m.p[1] as f32, (p[2] as f64 + m.dz) as f32])
        };
        b.tower = mp(b.tower);
        b.lineup = mp(b.lineup);
        let turn = (self.turn as f32).to_radians();
        let pi = std::f32::consts::PI;
        let tp = |t: &mut TaxiPt| {
            if let Some(m) = self.map([t.x as f64, t.y as f64]) {
                t.x = m.p[0] as f32;
                t.y = m.p[1] as f32;
                let mut h = t.hdg + turn;
                if h > pi {
                    h -= 2.0 * pi;
                } else if h <= -pi {
                    h += 2.0 * pi;
                }
                t.hdg = h;
            }
        };
        for v in [&mut b.to_taxi, &mut b.from_taxi, &mut b.hangars, &mut b.to_hangar_turn, &mut b.from_hangar_turn] {
            v.iter_mut().for_each(tp);
        }
        b.runway_deg = self.heading as f32;
    }
}

/// Every base's move.
#[derive(Debug, Clone, Default)]
pub struct BaseMoves {
    pub bases: Vec<BaseMove>,
}

impl BaseMoves {
    /// The moves of `games` onto the committed real runways.
    pub fn new(games: &[GameBase]) -> Self {
        let real = real_runways();
        BaseMoves { bases: games.iter().filter_map(|g| BaseMove::new(g, &real)).collect() }
    }

    /// Sets each new site's elevation: the mean of `height` along its real runway (unchanged without heights).
    pub fn set_elevations(&mut self, height: impl Fn(f64, f64) -> Option<f64>) {
        for b in &mut self.bases {
            let hs: Vec<f64> = (0..=10)
                .filter_map(|i| {
                    let t = b.real_len * i as f64 / 10.0;
                    height(b.real_c[0] + t * b.real_d[0], b.real_c[1] + t * b.real_d[1])
                })
                .collect();
            if !hs.is_empty() {
                b.elev = hs.iter().sum::<f64>() / hs.len() as f64;
            }
        }
    }

    pub fn get(&self, name: &str) -> Option<&BaseMove> {
        self.bases.iter().find(|b| b.name == name)
    }

    /// A point's move by the first base whose zones hold it.
    pub fn map(&self, p: [f64; 2]) -> Option<Moved> {
        self.bases.iter().find_map(|b| b.map(p))
    }

    /// iaf.ibx's bases at their new sites.
    pub fn map_airbases(&self, bases: &mut [Airbase]) {
        for a in bases {
            if let Some(m) = self.get(&a.name) {
                m.map_airbase(a);
            }
        }
    }

    /// A runway sign at `p` (its new site) showing runway `n` in the game: the real designator of that runway
    /// direction (n · 10° turned with the base); None off the moved bases.
    pub fn sign_number(&self, p: [f64; 2], n: i64) -> Option<i64> {
        let b = self.bases.iter().find(|b| b.to_game(p, 0.0).is_some())?;
        Some(b.designator(n as f64 * 10.0 + b.turn))
    }

    /// The surface flags at `p` with `lookup` = terraintype.dat's: on a new site the original's runway leaves (their
    /// flags at the inverse-mapped point); on an old site the runway leaves are land (rough ground off a runway).
    pub fn surface(&self, p: [f64; 2], lookup: impl Fn(f64, f64) -> i32) -> i32 {
        let here = lookup(p[0], p[1]);
        for b in &self.bases {
            if let Some(q) = b.to_game(p, 0.0) {
                let g = lookup(q[0], q[1]);
                if g & RUNWAY != 0 {
                    return g;
                }
                return if here & RUNWAY != 0 { (here & !RUNWAY) | LAND } else { here };
            }
        }
        if here & RUNWAY != 0 && self.bases.iter().any(|b| b.in_old(p, 0.0)) {
            return (here & !RUNWAY) | LAND;
        }
        here
    }

    /// The terrain height `h` at `p` with the new sites flattened to their elevation.
    pub fn height(&self, p: [f64; 2], h: f64) -> f64 {
        self.bases.iter().fold(h, |h, b| {
            let w = b.pad_weight(p);
            if w > 0.0 { h + (b.elev - h) * w } else { h }
        })
    }

    /// Each base's old and new site with the flattening's ring, as one engine-metre box [x0, y0, x1, y1]: the
    /// images there need the patches.
    pub fn bounds(&self) -> Vec<[f64; 4]> {
        self.bases
            .iter()
            .map(|b| {
                let (lo, hi, k, m) = (b.lo, b.hi, b.k, RING);
                let c =
                    [[lo[0] - m, lo[1] - m], [hi[0] + m, lo[1] - m], [hi[0] + m, hi[1] + m], [lo[0] - m, hi[1] + m]];
                let mut pts: Vec<[f64; 2]> = c.iter().map(|q| b.game_xy(*q)).collect();
                pts.extend(c.iter().map(|q| b.real_xy([q[0] * k, q[1] * k])));
                if let Some(mk) = &b.mask {
                    let (w, h, o) = (mk.w as f64 * mk.px_m, mk.h as f64 * mk.px_m, mk.origin);
                    pts.extend([[o[0], o[1]], [o[0] + w, o[1] - h]]);
                }
                pts.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |r, p| {
                    [r[0].min(p[0]), r[1].min(p[1]), r[2].max(p[0]), r[3].max(p[1])]
                })
            })
            .collect()
    }

    /// Patches a height image (RG8: raw = r·256 + g; `texel(x, y)` = the texel's engine position): the new sites
    /// flattened. `to_m` / `to_raw` convert raw heights to metres and back.
    pub fn bake_heights(
        &self,
        rg8: &mut [u8],
        w: usize,
        h: usize,
        texel: impl Fn(usize, usize) -> [f64; 2],
        to_m: impl Fn(f64) -> f64,
        to_raw: impl Fn(f64) -> f64,
    ) {
        for y in 0..h {
            for x in 0..w {
                let p = texel(x, y);
                if !self.bases.iter().any(|b| b.pad_weight(p) > 0.0) {
                    continue;
                }
                let i = 2 * (y * w + x);
                if i + 1 >= rg8.len() {
                    return;
                }
                let raw = (u16::from(rg8[i]) << 8 | u16::from(rg8[i + 1])) as f64;
                let r = to_raw(self.height(p, to_m(raw))).round().clamp(0.0, 65535.0) as u16;
                rg8[i] = (r >> 8) as u8;
                rg8[i + 1] = r as u8;
            }
        }
    }

    /// The old sites' paved weight (0..1) per pixel of a colour image: the mask's paved surface, the grey around it
    /// on the old base, grown by ≈ 20 m, fading out over 60 m (the painted edges and the light shoulders).
    fn old_paved(&self, rgb: &[u8], w: usize, h: usize, px: &impl Fn(usize, usize) -> [f64; 2], px_m: f64) -> Vec<f32> {
        let mut paved = vec![0f32; w * h];
        let mut grey = vec![0f32; w * h];
        let mut any = false;
        for y in 0..h {
            for x in 0..w {
                let p = px(x, y);
                let i = y * w + x;
                for b in &self.bases {
                    if let Some(m) = b.mask.as_ref().filter(|m| m.contains(p, 0.0)) {
                        let c = m.at(p);
                        let v = ((c[0].max(c[1]) - 0.05) / 0.2).clamp(0.0, 1.0) as f32;
                        if v > 0.0 {
                            paved[i] = paved[i].max(v);
                            any = true;
                        }
                        if b.in_old(p, 0.0) {
                            grey[i] = 1.0 - smoothstep(0.03, 0.08, chroma(&rgb[3 * i..3 * i + 3])) as f32;
                        }
                    }
                }
            }
        }
        // The grey next to the paved surface on the old base (shoulders, worn grey, grey roofs) goes too: within
        // ≈ 100 m of it, fading out (the grey fields farther out stay, so zone A's edge does not show).
        let rn = (100.0 / px_m).round() as usize;
        if any && rn >= 1 {
            let near = box_blur(&paved.iter().map(|&v| [v as f64, 0.0, 0.0, 0.0]).collect::<Vec<_>>(), w, h, rn);
            for ((v, g), n) in paved.iter_mut().zip(&grey).zip(&near) {
                *v = v.max(g * smoothstep(0.02, 0.15, n[0]) as f32);
            }
        }
        let rd = (60.0 / px_m).round() as usize;
        if any && rd >= 1 {
            let grown = box_blur(&paved.iter().map(|&v| [v as f64, 0.0, 0.0, 0.0]).collect::<Vec<_>>(), w, h, rd);
            for (v, g) in paved.iter_mut().zip(&grown) {
                *v = v.max((g[0] * 3.0).min(1.0) as f32);
            }
        }
        paved
    }

    /// The box each old site's fill covers (engine metres [x0, y0, x1, y1]): the mask and zone A, plus 1 km.
    pub fn fill_boxes(&self) -> Vec<[f64; 4]> {
        self.bases
            .iter()
            .map(|b| {
                let c = [[b.lo[0], b.lo[1]], [b.hi[0], b.lo[1]], [b.hi[0], b.hi[1]], [b.lo[0], b.hi[1]]];
                let mut pts: Vec<[f64; 2]> = c.iter().map(|q| b.game_xy(*q)).collect();
                if let Some(mk) = &b.mask {
                    let (w, h, o) = (mk.w as f64 * mk.px_m, mk.h as f64 * mk.px_m, mk.origin);
                    pts.extend([[o[0], o[1]], [o[0] + w, o[1] - h]]);
                }
                let r = pts.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |r, p| {
                    [r[0].min(p[0]), r[1].min(p[1]), r[2].max(p[0]), r[3].max(p[1])]
                });
                [r[0] - 1000.0, r[1] - 1000.0, r[2] + 1000.0, r[3] + 1000.0]
            })
            .collect()
    }

    /// Copies a coarse colour image (RGB8, north-west corner `nw`, `px_m` per pixel) into the fills it touches (a new
    /// cell size starts the fill afresh); then `finish_fill`.
    pub fn add_fill_source(&mut self, rgb: &[u8], w: usize, h: usize, nw: [f64; 2], px_m: f64) {
        if rgb.len() < 3 * w * h {
            return;
        }
        let boxes = self.fill_boxes();
        for (b, bx) in self.bases.iter_mut().zip(boxes) {
            let f = b.fill.get_or_insert_with(Fill::default);
            if f.px_m != px_m {
                let (fw, fh) = (((bx[2] - bx[0]) / px_m).ceil() as usize, ((bx[3] - bx[1]) / px_m).ceil() as usize);
                *f = Fill { nw: [bx[0], bx[3]], px_m, w: fw, h: fh, rgb: vec![0; 3 * fw * fh], mean: Vec::new() };
            }
            f.mean.clear();
            for y in 0..f.h {
                for x in 0..f.w {
                    let p = [f.nw[0] + (x as f64 + 0.5) * px_m, f.nw[1] - (y as f64 + 0.5) * px_m];
                    let (sx, sy) = ((p[0] - nw[0]) / px_m, (nw[1] - p[1]) / px_m);
                    if sx < 0.0 || sy < 0.0 || sx >= w as f64 || sy >= h as f64 {
                        continue;
                    }
                    let (i, j) = (3 * (y * f.w + x), 3 * (sy as usize * w + sx as usize));
                    f.rgb[i..i + 3].copy_from_slice(&rgb[j..j + 3]);
                }
            }
        }
    }

    /// Computes each fill's surroundings' mean from its sources.
    pub fn finish_fill(&mut self) {
        for k in 0..self.bases.len() {
            let Some(f) = self.bases[k].fill.as_ref() else { continue };
            let (nw, px_m, w, h) = (f.nw, f.px_m, f.w, f.h);
            let px = |x: usize, y: usize| [nw[0] + (x as f64 + 0.5) * px_m, nw[1] - (y as f64 + 0.5) * px_m];
            let paved = self.old_paved(&f.rgb, w, h, &px, px_m);
            let mut rgb = f.rgb.clone();
            fill_from_surroundings(
                &mut rgb,
                w,
                h,
                &vec![1.0; w * h],
                &paved,
                ((400.0 / px_m).round() as usize).max(2),
                &|_| None,
            );
            let mean = (0..w * h).map(|i| [rgb[3 * i] as f64, rgb[3 * i + 1] as f64, rgb[3 * i + 2] as f64]).collect();
            self.bases[k].fill.as_mut().unwrap().mean = mean;
        }
    }

    /// Patches a colour image (RGB8; `px(x, y)` = the pixel centre's engine position, `px_m` = its size): each old
    /// site's paved surface painted over with the colour of its unpaved surroundings (a normalised box blur), then
    /// each new site's paved surface painted asphalt / concrete grey.
    pub fn bake_colour(&self, rgb: &mut [u8], w: usize, h: usize, px: impl Fn(usize, usize) -> [f64; 2], px_m: f64) {
        if rgb.len() < 3 * w * h {
            return;
        }
        let paved = self.old_paved(rgb, w, h, &px, px_m);
        if paved.iter().any(|&v| v > 0.0) {
            let fill = |i: usize| self.bases.iter().find_map(|b| b.fill.as_ref()?.mean_at(px(i % w, i / w)));
            fill_from_surroundings(rgb, w, h, &paved, &paved, ((400.0 / px_m).round() as usize).max(2), &fill);
        }
        // The new sites.
        for y in 0..h {
            for x in 0..w {
                let p = px(x, y);
                for b in &self.bases {
                    let (Some(m), Some(q)) = (b.mask.as_ref(), b.to_game(p, 0.0)) else { continue };
                    let c = m.at(q);
                    if c[0] <= 0.0 {
                        continue;
                    }
                    let a = (((c[0] - 0.2) / 0.3).clamp(0.0, 1.0) * 0.9) as f32;
                    let grey = if c[1] > 0.5 { [128.0, 126.0, 121.0] } else { [92.0, 92.0, 90.0] };
                    let i = 3 * (y * w + x);
                    for ch in 0..3 {
                        rgb[i + ch] = (rgb[i + ch] as f32 * (1.0 - a) + grey[ch] * a).round() as u8;
                    }
                }
            }
        }
    }
}

/// The mean colour of the unpaved, coloured pixels within `r` of each pixel (two box passes; where none is near,
/// the image's unpaved mean).
fn surroundings_mean(rgb: &[u8], w: usize, h: usize, paved: &[f32], r: usize) -> Vec<[f64; 3]> {
    let n = w * h;
    let mut acc = vec![[0f64; 4]; n]; // r, g, b, weight
    for i in 0..n {
        // The surroundings' colour: unpaved, coloured ground (grey roads and roofs left out).
        let wt = (1.0 - paved[i] as f64) * smoothstep(0.03, 0.08, chroma(&rgb[3 * i..3 * i + 3]));
        acc[i] = [rgb[3 * i] as f64 * wt, rgb[3 * i + 1] as f64 * wt, rgb[3 * i + 2] as f64 * wt, wt];
    }
    let mut mean = [0f64; 4];
    for a in &acc {
        for c in 0..4 {
            mean[c] += a[c];
        }
    }
    for _ in 0..2 {
        acc = box_blur(&acc, w, h, r);
    }
    let all = if mean[3] > 0.0 { [mean[0] / mean[3], mean[1] / mean[3], mean[2] / mean[3]] } else { [128.0; 3] };
    acc.iter().map(|a| if a[3] > 1e-3 { [a[0] / a[3], a[1] / a[3], a[2] / a[3]] } else { all }).collect()
}

/// Replaces the pixels by their weight `wt` (0..1) with the colour of the ground around the `paved` surface:
/// `outer`'s where it has one (the coarse fill, used as it is), else the image's own mean within `r` plus the texture
/// of an unpaved pixel `r` away.
fn fill_from_surroundings(
    rgb: &mut [u8],
    w: usize,
    h: usize,
    wt: &[f32],
    paved: &[f32],
    r: usize,
    outer: &dyn Fn(usize) -> Option<[f64; 3]>,
) {
    let n = w * h;
    let local = surroundings_mean(rgb, w, h, paved, r);
    let src = rgb.to_vec();
    let d = r as isize;
    for i in 0..n {
        let p = wt[i];
        if p <= 0.0 {
            continue;
        }
        let mut fill = local[i];
        if let Some(c) = outer(i) {
            for k in 0..3 {
                let v = rgb[3 * i + k] as f64;
                rgb[3 * i + k] = (v + (c[k] - v) * p as f64).round().clamp(0.0, 255.0) as u8;
            }
            continue;
        }
        // The texture: an unpaved pixel `r` away (the first of four directions), its difference from its own mean.
        let (x, y) = ((i % w) as isize, (i / w) as isize);
        for (dx, dy) in [(d, d / 2), (-d / 2, d), (-d, -d / 2), (d / 2, -d)] {
            let (sx, sy) = (x + dx, y + dy);
            if sx < 0 || sy < 0 || sx >= w as isize || sy >= h as isize {
                continue;
            }
            let j = sy as usize * w + sx as usize;
            if paved[j] > 0.1 {
                continue;
            }
            let mj = local[j];
            for c in 0..3 {
                fill[c] += (src[3 * j + c] as f64 - mj[c]).clamp(-50.0, 50.0);
            }
            break;
        }
        for c in 0..3 {
            let v = rgb[3 * i + c] as f64;
            rgb[3 * i + c] = (v + (fill[c] - v) * p as f64).round().clamp(0.0, 255.0) as u8;
        }
    }
}

/// A pixel's chroma 0..1 (max − min channel).
fn chroma(c: &[u8]) -> f64 {
    (c.iter().max().copied().unwrap_or(0) - c.iter().min().copied().unwrap_or(0)) as f64 / 255.0
}

/// A (2r + 1)² box mean, clamped at the edges (separable running sums).
fn box_blur(src: &[[f64; 4]], w: usize, h: usize, r: usize) -> Vec<[f64; 4]> {
    let pass = |src: &[[f64; 4]], len: usize, lines: usize, at: &dyn Fn(usize, usize) -> usize| {
        let mut out = vec![[0f64; 4]; src.len()];
        for line in 0..lines {
            let mut sum = [0f64; 4];
            let mut cnt = 0f64;
            // The window [i − r, i + r] within the line.
            for j in 0..=r.min(len - 1) {
                let s = &src[at(line, j)];
                (0..4).for_each(|c| sum[c] += s[c]);
                cnt += 1.0;
            }
            for i in 0..len {
                let o = &mut out[at(line, i)];
                (0..4).for_each(|c| o[c] = sum[c] / cnt);
                if i + r + 1 < len {
                    let s = &src[at(line, i + r + 1)];
                    (0..4).for_each(|c| sum[c] += s[c]);
                    cnt += 1.0;
                }
                if i >= r {
                    let s = &src[at(line, i - r)];
                    (0..4).for_each(|c| sum[c] -= s[c]);
                    cnt -= 1.0;
                }
            }
        }
        out
    };
    let rows = pass(src, w, h, &|line, i| line * w + i);
    pass(&rows, h, w, &|line, i| i * w + line)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn game(name: &str) -> GameBase {
        // A base like the game's Ramat David: runway 270°, 4264 m, from the lineup east of it.
        GameBase {
            name: name.into(),
            lineup: [356483.0, 602383.0, 63.0],
            runway_deg: 270.0,
            runways: vec![[[357155.0, 602373.0], [352891.0, 602401.0]]],
            points: vec![[353954.0, 601500.0], [354934.0, 602088.0]],
        }
    }

    #[test]
    fn the_table_holds_every_base() {
        let t = real_runways();
        for b in crate::airbase::SECTIONS {
            assert!(t.iter().any(|r| r.base == b), "{b}");
        }
        assert!(t.iter().all(|r| r.width >= 45.0 && r.width <= 61.0));
        assert_eq!(t.iter().find(|r| r.base == "Aman").unwrap().width, 61.0);
    }

    #[test]
    fn the_main_runway_lands_on_the_real_one() {
        let m = BaseMove::new(&game("David"), &real_runways()).unwrap();
        // The real 09/27 (2934 m), taken westward (267°).
        assert!((m.heading - 267.0).abs() < 1.5, "{}", m.heading);
        assert!((m.real_len - 2934.0).abs() < 15.0, "{}", m.real_len);
        assert!((m.k - m.real_len / 4264.0).abs() < 0.01, "{}", m.k);
        let p0 = m.map(m.game_c).unwrap();
        assert!((p0.p[0] - m.real_c[0]).hypot(p0.p[1] - m.real_c[1]) < 1e-6);
        let far = [m.game_c[0] + m.game_len * m.game_d[0], m.game_c[1] + m.game_len * m.game_d[1]];
        let b = m.map(far).unwrap().p;
        let rb = [m.real_c[0] + m.real_len * m.real_d[0], m.real_c[1] + m.real_len * m.real_d[1]];
        assert!((b[0] - rb[0]).hypot(b[1] - rb[1]) < 1e-6);
        // The lineup point on the real centreline.
        let l = m.map([356483.0, 602383.0]).unwrap().p;
        assert!(m.real_uv(l)[1].abs() < 1e-6);
        assert_eq!(p0.scale, m.k);
        assert!(m.zone_b > 0.0, "David moves {} m", m.offset());
    }

    #[test]
    fn zones_are_continuous_and_end() {
        let m = BaseMove::new(&game("David"), &real_runways()).unwrap();
        // Across zone A's edge (u = hi) and zone B's.
        for v in [-300.0, 0.0, 800.0] {
            let a = m.map(m.game_xy([m.hi[0] - 1e-6, v])).unwrap().p;
            let b = m.map(m.game_xy([m.hi[0] + 1e-6, v])).unwrap().p;
            assert!((a[0] - b[0]).hypot(a[1] - b[1]) < 1e-3);
        }
        // Zone B keeps distances: two points 1 km apart beyond the box stay 1 km apart.
        let a = m.map(m.game_xy([m.hi[0] + 1000.0, 0.0])).unwrap().p;
        let b = m.map(m.game_xy([m.hi[0] + 2000.0, 0.0])).unwrap().p;
        assert!(((a[0] - b[0]).hypot(a[1] - b[1]) - 1000.0).abs() < 1e-6);
        assert_eq!(m.map(m.game_xy([m.hi[0] + 2000.0, 0.0])).unwrap().scale, 1.0);
        assert!(m.map(m.game_xy([m.hi[0] + ZONE_B + 1.0, 0.0])).is_none());
        // A near base has no zone B.
        let mut near = game("Kuzeir");
        near.lineup = [487086.0, 820615.0, 500.0];
        near.runway_deg = 280.0;
        near.runways = vec![[[487237.0, 820587.0], [483589.0, 821214.0]]];
        near.points.clear();
        let n = BaseMove::new(&near, &real_runways()).unwrap();
        assert!(n.offset() < FAR && n.zone_b == 0.0, "{}", n.offset());
        assert!(n.map(n.game_xy([n.hi[0] + 10.0, 0.0])).is_none());
    }

    #[test]
    fn the_inverse_round_trips() {
        let m = BaseMove::new(&game("David"), &real_runways()).unwrap();
        for p in [[354000.0, 602000.0], [356900.0, 601600.0], [353100.0, 602800.0]] {
            let q = m.map(p).unwrap().p;
            let back = m.to_game(q, 0.0).unwrap();
            assert!((back[0] - p[0]).hypot(back[1] - p[1]) < 1e-3, "{p:?} {back:?}");
        }
        assert!(m.to_game([0.0, 0.0], 0.0).is_none());
    }

    #[test]
    fn the_airbase_moves_with_its_runway() {
        let real = real_runways();
        let mut ab = Airbase {
            name: "David".into(),
            tower: [353954.0, 601500.0, 63.0],
            lineup: [356483.0, 602383.0, 63.0],
            runway_deg: 270.0,
            hangars: vec![TaxiPt { x: 354934.0, y: 602088.0, hdg: 0.0 }],
            ..Default::default()
        };
        let mut m = BaseMove::new(&game("David"), &real).unwrap();
        m.elev = 50.0;
        m.map_airbase(&mut ab);
        assert_eq!(ab.runway_deg, m.heading as f32);
        assert_eq!(ab.lineup[2], 50.0);
        assert!((ab.hangars[0].hdg.to_degrees() - m.turn as f32).abs() < 1e-3);
        let l = m.real_uv([ab.lineup[0] as f64, ab.lineup[1] as f64]);
        assert!(l[1].abs() < 0.01 && l[0] > 0.0 && l[0] < m.real_len, "{l:?}");
    }

    #[test]
    fn surface_and_heights_follow_the_move() {
        let ms = BaseMoves { bases: vec![BaseMove::new(&game("David"), &real_runways()).unwrap()] };
        let m = &ms.bases[0];
        // The old runway: a strip of the runway bit along the game runway.
        let old = |x: f64, y: f64| if (y - 602387.0).abs() < 50.0 && x > 352891.0 && x < 357155.0 { 0x10 } else { 1 };
        let mid_old = [355000.0, 602387.0];
        let mid_new = m.map(mid_old).unwrap().p;
        assert_eq!(ms.surface(mid_new, old), 0x10, "the runway leaf's own flags");
        assert_eq!(ms.surface(mid_old, old), 1, "the old site is rough ground");
        assert_eq!(ms.surface([0.0, 0.0], old), 1);
        // Flat on the site, the ground beyond the ring unchanged.
        assert_eq!(ms.height(mid_new, 300.0), m.elev);
        assert_eq!(ms.height([0.0, 0.0], 300.0), 300.0);
    }

    #[test]
    fn the_fill_takes_the_surroundings() {
        // 20 × 20 green with a grey 6 × 6 square in the middle, paved.
        let (w, h) = (20, 20);
        let mut rgb = vec![0u8; 3 * w * h];
        let mut paved = vec![0f32; w * h];
        for y in 0..h {
            for x in 0..w {
                let i = y * w + x;
                let p = (7..13).contains(&x) && (7..13).contains(&y);
                rgb[3 * i..3 * i + 3].copy_from_slice(if p { &[100, 100, 100] } else { &[40, 120, 30] });
                // A grey road outside: not part of the surroundings' colour.
                if y == 2 {
                    rgb[3 * i..3 * i + 3].copy_from_slice(&[90, 90, 90]);
                }
                paved[i] = if p { 1.0 } else { 0.0 };
            }
        }
        fill_from_surroundings(&mut rgb, w, h, &paved, &paved, 3, &|_| None);
        let i = 3 * (10 * w + 10);
        assert_eq!(&rgb[i..i + 3], &[40, 120, 30]);
    }

    #[test]
    fn the_designator_is_the_real_one() {
        let m = BaseMove::new(
            &GameBase {
                name: "X".into(),
                lineup: [0.0, 0.0, 0.0],
                runway_deg: 230.0,
                runways: vec![[[0.0, 0.0], [-2000.0, -1700.0]]],
                points: Vec::new(),
            },
            &[RealRunway {
                base: "X".into(),
                a: [0.0, 0.0],
                b: [-2700.0, -1150.0],
                width: 45.0,
                designator: "07L/25R".into(),
            }],
        )
        .unwrap();
        // True 247° flies runway 25 (the magnetic number), the other way 07; off any runway: from the heading.
        assert_eq!(m.designator(247.0), 25);
        assert_eq!(m.designator(67.0), 7);
        assert_eq!(m.designator(150.0), 15);
        assert_eq!(m.designator(2.0), 36);
    }

    #[test]
    fn the_new_site_takes_the_old_art() {
        let m = BaseMove::new(&game("David"), &real_runways()).unwrap();
        // The old art: its colour is its game x (mod 256); 1 m pixels along the new runway's middle.
        let mid = m.map([355000.0, 602387.0]).unwrap().p;
        let (w, h) = (8, 1);
        let mut rgba = vec![0u8; 4 * w * h];
        let px = |x: usize, _| [mid[0] + x as f64, mid[1]];
        assert!(m.bake_inset(&mut rgba, w, h, px, |q| Some([q[0].rem_euclid(256.0); 3])));
        let back = m.to_game(px(3, 0), 0.0).unwrap();
        assert_eq!(
            rgba[4 * 3..4 * 4],
            [back[0].rem_euclid(256.0).round() as u8; 3].into_iter().chain([255]).collect::<Vec<_>>()[..]
        );
        // Zone A's edge fades; outside, nothing.
        let b = m.zone_box(true);
        let corner_in = m.real_xy([m.k * m.lo[0] + 10.0, m.k * m.lo[1] + 400.0]);
        assert!(m.inset_source(corner_in).unwrap().1 < 0.2);
        assert!(m.inset_source([b[0] - 1.0, b[1] - 1.0]).is_none());
        assert!(!m.bake_inset(&mut rgba, w, h, |_, _| [0.0, 0.0], |_| Some([0.0; 3])));
    }

    #[test]
    fn the_fill_is_one_world_grid() {
        // Cell centres at x = 5, 15 (m); the colour between them bilinear, the same for any node asking.
        let f = Fill {
            nw: [0.0, 20.0],
            px_m: 10.0,
            w: 2,
            h: 2,
            rgb: Vec::new(),
            mean: vec![[0.0; 3], [100.0; 3], [0.0; 3], [100.0; 3]],
        };
        assert_eq!(f.mean_at([10.0, 10.0]), Some([50.0; 3]));
        assert_eq!(f.mean_at([5.0, 15.0]), Some([0.0; 3]));
        assert_eq!(f.mean_at([30.0, 10.0]), None);
        assert_eq!(Fill { mean: Vec::new(), ..f }.mean_at([10.0, 10.0]), None);
    }
}
