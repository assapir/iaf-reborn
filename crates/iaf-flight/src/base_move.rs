//! World scale Real 1:1: each airbase at its real place (docs/world-scale.md §3.3, "the base move").
//!
//! One similarity per base puts the game's main runway (the runway through the iaf.ibx lineup point, on the line at
//! RunwayNumber's heading) on the real one from `data/real_runways.csv` (© OpenStreetMap contributors, ODbL). Zone A
//! (the base's box) takes the similarity; zone B (6 km beyond it, at the bases moved more than 5 km) moves and turns
//! with the base without scaling. Coordinates: engine metres, X east, Y north; headings clockwise from north.

use crate::airbase::{Airbase, TaxiPt};
use iaf_formats::terrain_types::RUNWAY;

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

/// A real runway: its ends (engine metres) and width (m).
#[derive(Debug, Clone, PartialEq)]
pub struct RealRunway {
    pub base: String,
    pub a: [f64; 2],
    pub b: [f64; 2],
    pub width: f64,
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
    pub mask: Option<Mask>,
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
            mask: None,
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
        ok.then(|| self.game_xy([q[0] / k, q[1] / k]))
    }

    /// The flattening's weight at a point: 1 on the new zone A, falling to 0 over `RING`.
    pub fn pad_weight(&self, p: [f64; 2]) -> f64 {
        let q = self.real_uv(p);
        let k = self.k;
        let du = (k * self.lo[0] - q[0]).max(q[0] - k * self.hi[0]).max(0.0);
        let dv = (k * self.lo[1] - q[1]).max(q[1] - k * self.hi[1]).max(0.0);
        1.0 - smoothstep(0.0, RING, du.hypot(dv))
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

    /// The surface flags at `p` with `lookup` = terraintype.dat's: on a new site the runway bit comes from the
    /// original's point (the inverse map); on an old site the runway leaves are rough ground.
    pub fn surface(&self, p: [f64; 2], lookup: impl Fn(f64, f64) -> i32) -> i32 {
        let here = lookup(p[0], p[1]);
        for b in &self.bases {
            if let Some(q) = b.to_game(p, 0.0) {
                return (here & !RUNWAY) | (lookup(q[0], q[1]) & RUNWAY);
            }
        }
        if here & RUNWAY != 0 && self.bases.iter().any(|b| b.in_old(p, 0.0)) {
            return here & !RUNWAY;
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

    /// True when any base's old or new site (grown by `margin`) touches the box [x0, x1] × [y0, y1].
    pub fn touches(&self, x0: f64, y0: f64, x1: f64, y1: f64, margin: f64) -> bool {
        let corners = |b: &BaseMove| -> Vec<[f64; 2]> {
            let k = b.k;
            let (lo, hi) = (b.lo, b.hi);
            let m = margin + RING;
            let c = [[lo[0] - m, lo[1] - m], [hi[0] + m, lo[1] - m], [hi[0] + m, hi[1] + m], [lo[0] - m, hi[1] + m]];
            let mut out: Vec<[f64; 2]> = c.iter().map(|q| b.game_xy(*q)).collect();
            out.extend(c.iter().map(|q| b.real_xy([q[0] * k, q[1] * k])));
            if let Some(mk) = &b.mask {
                let (w, h) = (mk.w as f64 * mk.px_m, mk.h as f64 * mk.px_m);
                let o = mk.origin;
                out.extend([[o[0], o[1]], [o[0] + w, o[1]], [o[0], o[1] - h], [o[0] + w, o[1] - h]]);
            }
            out
        };
        self.bases.iter().any(|b| {
            let c = corners(b);
            let (cx0, cx1) = c.iter().fold((f64::MAX, f64::MIN), |a, p| (a.0.min(p[0]), a.1.max(p[0])));
            let (cy0, cy1) = c.iter().fold((f64::MAX, f64::MIN), |a, p| (a.0.min(p[1]), a.1.max(p[1])));
            cx0 <= x1 && cx1 >= x0 && cy0 <= y1 && cy1 >= y0
        })
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

    /// Patches a colour image (RGB8; `px(x, y)` = the pixel centre's engine position, `px_m` = its size): each old
    /// site's paved surface painted over with the colour of its unpaved surroundings (a normalised box blur), then
    /// each new site's paved surface painted asphalt / concrete grey.
    pub fn bake_colour(&self, rgb: &mut [u8], w: usize, h: usize, px: impl Fn(usize, usize) -> [f64; 2], px_m: f64) {
        if rgb.len() < 3 * w * h {
            return;
        }
        // The old sites: paved weight per pixel.
        let mut paved = vec![0f32; w * h];
        let mut any = false;
        for y in 0..h {
            for x in 0..w {
                let p = px(x, y);
                for b in &self.bases {
                    if let Some(m) = b.mask.as_ref().filter(|m| m.contains(p, 0.0)) {
                        let c = m.at(p);
                        let v = ((c[0].max(c[1]) - 0.15) / 0.3).clamp(0.0, 1.0) as f32;
                        if v > 0.0 {
                            paved[y * w + x] = paved[y * w + x].max(v);
                            any = true;
                        }
                    }
                }
            }
        }
        if any {
            fill_from_surroundings(rgb, w, h, &paved, ((150.0 / px_m).round() as usize).max(2));
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

/// Replaces the pixels by their weight `paved` (0..1) with the mean colour of the unpaved pixels within `r` (two
/// box passes; where none is near, the image's unpaved mean).
fn fill_from_surroundings(rgb: &mut [u8], w: usize, h: usize, paved: &[f32], r: usize) {
    let n = w * h;
    let mut acc = vec![[0f64; 4]; n]; // r, g, b, weight
    for i in 0..n {
        let wt = 1.0 - paved[i] as f64;
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
    for i in 0..n {
        let p = paved[i];
        if p <= 0.0 {
            continue;
        }
        let a = &acc[i];
        let fill = if a[3] > 1e-3 {
            [a[0] / a[3], a[1] / a[3], a[2] / a[3]]
        } else if mean[3] > 0.0 {
            [mean[0] / mean[3], mean[1] / mean[3], mean[2] / mean[3]]
        } else {
            continue;
        };
        for c in 0..3 {
            let v = rgb[3 * i + c] as f64;
            rgb[3 * i + c] = (v + (fill[c] - v) * p as f64).round().clamp(0.0, 255.0) as u8;
        }
    }
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
        let old = |x: f64, y: f64| if (y - 602387.0).abs() < 50.0 && x > 352891.0 && x < 357155.0 { 0x11 } else { 1 };
        let mid_old = [355000.0, 602387.0];
        let mid_new = m.map(mid_old).unwrap().p;
        assert_eq!(ms.surface(mid_new, old) & RUNWAY, RUNWAY);
        assert_eq!(ms.surface(mid_old, old) & RUNWAY, 0, "the old site is rough ground");
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
                paved[i] = if p { 1.0 } else { 0.0 };
            }
        }
        fill_from_surroundings(&mut rgb, w, h, &paved, 3);
        let i = 3 * (10 * w + 10);
        assert_eq!(&rgb[i..i + 3], &[40, 120, 30]);
    }
}
