//! City lights at night (Night lights = Detailed, docs/rendering.md §5.1): light points placed from the scenery's
//! building footprints (`scenery::Cell`, docs/scenery.md). Ours: the original has no city lights beyond its few `LT_`
//! sets (Damascus's streets).
//!
//! - **Street lamps**: along each facade, 5 m out into the street, 9 m up, at most one per 26 m square, so a street
//!   lined by buildings gets a row of lamps. High-pressure sodium orange; white LED more often in dense centres.
//! - **Lit windows**: on the facades of buildings 6 m and taller, a share of their window bays, warm or cool white.
//! - **Porch lights**: about a third of the low houses, one warm light by a wall.
//! - **Obstruction lights**: red, on the roof of buildings 60 m and taller.
//!
//! - **Road lamps** (`road_lamps`, with Graphics → MORE "Roads" Detailed): along the OpenStreetMap roads tagged lit,
//!   and the untagged motorway to secondary roads inside towns, a row of poles by the road's class.
//!
//! Density follows the built-up share of each 100 m square (footprint area / square area): the dense centres get
//! brighter lamps and more white. Each light has a seeded rank in [0, 1): the renderer keeps the lights of rank below
//! a share that falls with distance, so a far town thins out instead of turning into a solid carpet of points.

use crate::roads::{self, Roads};
use crate::scenery::{Building, Seed};

/// A light: world X / Y (m, east / north), its height above the ground (m), colour × brightness (each 0..1) and its
/// rank (0 = drawn farthest; a multiple of 1/255).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Light {
    pub at: [f32; 2],
    pub up: f32,
    pub color: [f32; 3],
    pub rank: f32,
}

/// High-pressure sodium, white LED, lit windows (warm, cool), aviation obstruction red (linear-ish display colours:
/// the glow shader adds them).
const SODIUM: [f32; 3] = [1.0, 0.44, 0.09];
const LED: [f32; 3] = [0.82, 0.88, 1.0];
const WARM: [f32; 3] = [1.0, 0.74, 0.42];
const COOL: [f32; 3] = [0.8, 0.86, 1.0];
const RED: [f32; 3] = [1.0, 0.06, 0.03];

/// Street lamps: out from the facade, up, at most one per square of this side, and a facade gets one every this far.
const LAMP_OUT: f32 = 5.0;
const LAMP_UP: f32 = 9.0;
const LAMP_GAP: f32 = 34.0;
const LAMP_EVERY: f32 = 40.0;
/// Facades shorter than this get no lamp.
const LAMP_EDGE: f32 = 8.0;
/// A window bay (m wide, m high) and the share of bays lit.
const BAY: f32 = 3.5;
const LEVEL: f32 = 3.0;
const LIT: f32 = 0.015;
/// At most this many lit windows per building (a tower's are far apart in the dark anyway).
const WINDOWS_MAX: usize = 16;
/// Buildings this tall carry obstruction lights.
const TALL: f32 = 60.0;
/// The built-up share is counted in squares of this side.
const SQUARE: f32 = 100.0;

/// The lights of a cell's buildings; `seed` makes them differ per cell (the node key).
pub fn lights(buildings: &[Building], seed: u32) -> Vec<Light> {
    let density = Density::new(buildings);
    let mut taken = std::collections::HashSet::new();
    let mut out = Vec::new();
    for (k, b) in buildings.iter().enumerate() {
        let p = &b.points;
        if p.len() < 3 {
            continue;
        }
        let mut s = Seed(seed.wrapping_mul(0x9e37_79b9) ^ (k as u32).wrapping_mul(0x85eb_ca6b));
        let c = b.centroid();
        let dense = density.at(c);
        let edges: Vec<([f32; 2], [f32; 2], f32)> = (0..p.len())
            .map(|i| {
                let (a, e) = (p[i], p[(i + 1) % p.len()]);
                let d = [e[0] - a[0], e[1] - a[1]];
                (a, d, d[0].hypot(d[1]))
            })
            .collect();
        // Street lamps along the facades (counter-clockwise: the outward normal is (dy, −dx)).
        for &(a, d, len) in edges.iter().filter(|e| e.2 >= LAMP_EDGE) {
            let n = (len / LAMP_EVERY).ceil().max(1.0);
            let out_n = [d[1] / len * LAMP_OUT, -d[0] / len * LAMP_OUT];
            for t in 0..n as usize {
                let f = (t as f32 + 0.3 + 0.4 * s.next()) / n;
                let at = [a[0] + d[0] * f + out_n[0], a[1] + d[1] * f + out_n[1]];
                if !taken.insert(((at[0] / LAMP_GAP).floor() as i32, (at[1] / LAMP_GAP).floor() as i32)) {
                    continue;
                }
                let white = s.next() < 0.12 + 0.23 * dense;
                let bright = 0.6 + 0.4 * dense - 0.15 * s.next();
                let col = if white { LED } else { SODIUM };
                out.push(Light { at, up: LAMP_UP, color: col.map(|v| v * bright), rank: rank(&mut s) });
            }
        }
        let perimeter: f32 = edges.iter().map(|e| e.2).sum();
        if b.height >= 6.0 {
            // Lit windows: a share of the bays, on a facade picked by its length, just out of the wall.
            let bays = perimeter / BAY * (b.height / LEVEL).floor();
            let n = ((bays * LIT * (0.6 + 0.8 * s.next())).round() as usize).min(WINDOWS_MAX);
            for _ in 0..n {
                let (a, d, len) = pick(&edges, perimeter * s.next());
                let f = s.next();
                let at = [a[0] + d[0] * f + d[1] / len * 0.4, a[1] + d[1] * f - d[0] / len * 0.4];
                let up = 1.6 + LEVEL * (s.next() * (b.height / LEVEL - 1.0)).floor();
                let col = if s.next() < 0.7 { WARM } else { COOL };
                let bright = 0.3 + 0.25 * s.next();
                out.push(Light { at, up, color: col.map(|v| v * bright), rank: rank(&mut s) });
            }
        } else if s.next() < 0.2 {
            // A porch light by a wall of a low house.
            let (a, d, len) = pick(&edges, perimeter * s.next());
            let at = [a[0] + d[0] * 0.5 + d[1] / len, a[1] + d[1] * 0.5 - d[0] / len];
            out.push(Light { at, up: 2.5, color: WARM.map(|v| v * 0.45), rank: rank(&mut s) });
        }
        if b.height >= TALL {
            out.push(Light { at: c, up: b.height + 1.0, color: RED, rank: 0.0 });
        }
    }
    out
}

/// Road lamps per class (motorway … track): mounting height (m) and spacing (m). Heights from the nominal 6 m
/// (residential) to 12 m (motorway) columns; spacing about 3.5–4.5 × the height (inferred: a road luminaire's usual
/// spacing-to-height ratio).
const ROAD_POLE: [(f32, f32); 8] =
    [(12.0, 42.0), (12.0, 42.0), (10.0, 36.0), (10.0, 36.0), (8.0, 32.0), (6.0, 26.0), (6.0, 26.0), (6.0, 26.0)];
/// A road lamp stands this far out from the road's edge, on the right of the way's direction.
const ROAD_OUT: f32 = 1.5;
/// No road lamp within this of a facade lamp (the street already has its row).
const ROAD_NEAR_FACADE: f32 = 12.0;
/// Inside a town: a facade lamp within this square's 3 × 3 neighbourhood.
const TOWN_SQUARE: f32 = 150.0;
/// A road's lamps are of one kind within squares of this side (m).
const ROAD_KIND: f32 = 3000.0;
/// The share of roads with white LED lamps (inferred, as the facades' 12–35 %).
const ROAD_LED: f32 = 0.3;

/// Lamps along the roads of `r`: the ways tagged lit everywhere, and the untagged motorway to secondary roads inside
/// towns (a facade lamp of `facade` near). Never on a way tagged unlit, a tunnel, a piece off the ground or a railway.
/// A lamp near one of the facade lamps is left out. A road class has one kind of lamp (sodium or LED) per 3 km square.
pub fn road_lamps(r: &Roads, facade: &[Light]) -> Vec<Light> {
    use std::collections::{HashMap, HashSet};
    let key = |p: [f32; 2], s: f32| ((p[0] / s).floor() as i32, (p[1] / s).floor() as i32);
    let mut near: HashMap<(i32, i32), Vec<[f32; 2]>> = HashMap::new();
    let mut town = HashSet::new();
    for l in facade.iter().filter(|l| l.up == LAMP_UP) {
        near.entry(key(l.at, ROAD_NEAR_FACADE)).or_default().push(l.at);
        town.insert(key(l.at, TOWN_SQUARE));
    }
    let around = |k: (i32, i32), f: &mut dyn FnMut((i32, i32)) -> bool| {
        (-1..=1).any(|dy| (-1..=1).any(|dx| f((k.0 + dx, k.1 + dy))))
    };
    let mut out = Vec::new();
    for (k, w) in r.ways.iter().enumerate() {
        let f = |b: u8| w.flags & b != 0;
        if w.class > roads::CLASS_TRACK || f(roads::FLAG_UNLIT | roads::FLAG_TUNNEL | roads::FLAG_OFF_GROUND) {
            continue;
        }
        let pts: Vec<[f32; 2]> = r.way_points(k as u32).map(|p| [p[0] as f32, p[1] as f32]).collect();
        let tagged = f(roads::FLAG_LIT);
        if pts.len() < 2 {
            continue;
        }
        if !tagged && (w.class > roads::CLASS_SECONDARY || !pts.iter().any(|&p| town.contains(&key(p, TOWN_SQUARE)))) {
            continue;
        }
        let mut s = Seed((w.osm_id as u32).wrapping_mul(0x85eb_ca6b) ^ (w.osm_id >> 32) as u32);
        let (up, every) = ROAD_POLE[w.class as usize];
        // One kind of lamp per class within a ROAD_KIND square (OSM cuts a road into many ways): by the way's start.
        let k = key(pts[0], ROAD_KIND);
        let mut kind =
            Seed((k.0 as u32).wrapping_mul(0x9e37_79b9) ^ (k.1 as u32).wrapping_mul(0x85eb_ca6b) ^ w.class as u32);
        let col = if kind.next() < ROAD_LED { LED } else { SODIUM };
        let bright = match w.class {
            0 | 1 => 1.0,
            2 | 3 => 0.9,
            _ => 0.75,
        };
        let out_m = w.width * 0.5 + ROAD_OUT;
        // The first lamp a seeded part of the spacing in, then one every `every` m along the way.
        let mut next = every * s.next();
        let mut walked = 0.0;
        for seg in pts.windows(2) {
            let d = [seg[1][0] - seg[0][0], seg[1][1] - seg[0][1]];
            let len = d[0].hypot(d[1]);
            if len <= 0.0 {
                continue;
            }
            while next <= walked + len {
                let t = (next - walked) / len;
                let at = [seg[0][0] + d[0] * t + d[1] / len * out_m, seg[0][1] + d[1] * t - d[0] / len * out_m];
                next += every;
                let close = around(key(at, ROAD_NEAR_FACADE), &mut |q| {
                    near.get(&q)
                        .is_some_and(|v| v.iter().any(|p| (p[0] - at[0]).hypot(p[1] - at[1]) < ROAD_NEAR_FACADE))
                });
                if !close && (tagged || around(key(at, TOWN_SQUARE), &mut |q| town.contains(&q))) {
                    out.push(Light { at, up, color: col.map(|v| v * bright), rank: rank(&mut s) });
                }
            }
            walked += len;
        }
    }
    out
}

/// The towns' glow: the lights' brightness summed per square, for the ground's own glow at night (the terrain shader
/// lights the streets between the points and a far town's carpet). Row 0 is the north edge.
pub struct Glow {
    /// West and north edges (world m), the square's side (m), the size in squares.
    pub x0: f64,
    pub y1: f64,
    pub m: f64,
    pub w: usize,
    pub h: usize,
    sum: Vec<f32>,
}

/// The summed brightness that reads full (≈ a lamp every 30 m both ways, the dense centres).
const GLOW_FULL: f32 = 0.9 / (30.0 * 30.0);

impl Glow {
    /// A grid of `m` m squares over the box (world m) west, south, east, north.
    pub fn new(b: [f64; 4], m: f64) -> Glow {
        let (w, h) = (((b[2] - b[0]) / m).ceil().max(1.0) as usize, ((b[3] - b[1]) / m).ceil().max(1.0) as usize);
        Glow { x0: b[0], y1: b[3], m, w, h, sum: vec![0.0; w * h] }
    }

    pub fn add(&mut self, l: &Light) {
        let (i, j) = ((l.at[0] as f64 - self.x0) / self.m, (self.y1 - l.at[1] as f64) / self.m);
        if i >= 0.0 && j >= 0.0 && (i as usize) < self.w && (j as usize) < self.h {
            self.sum[i as usize + j as usize * self.w] += l.color.iter().fold(0.0f32, |a, &c| a.max(c));
        }
    }

    /// One byte per square: 255 = the full glow, a square root curve so the suburbs' sparse lamps still show.
    pub fn bytes(&self) -> Vec<u8> {
        let full = GLOW_FULL * (self.m * self.m) as f32;
        self.sum.iter().map(|&s| ((s / full).min(1.0).sqrt() * 255.0).round() as u8).collect()
    }
}

/// A seeded rank in steps of 1/255: the vertex colour's alpha holds it exactly (8 bits).
fn rank(s: &mut Seed) -> f32 {
    (s.next() * 255.0).floor() / 255.0
}

/// The facade at `walk` metres along the perimeter.
fn pick(edges: &[([f32; 2], [f32; 2], f32)], mut walk: f32) -> ([f32; 2], [f32; 2], f32) {
    for &e in edges {
        if walk < e.2 {
            return e;
        }
        walk -= e.2;
    }
    edges[edges.len() - 1]
}

/// The built-up share per 100 m square, scaled so a dense centre (≥ 40 % covered) reads 1.
struct Density {
    x0: f32,
    y0: f32,
    w: usize,
    h: usize,
    share: Vec<f32>,
}

impl Density {
    fn new(buildings: &[Building]) -> Density {
        let cs: Vec<[f32; 2]> = buildings.iter().map(|b| b.centroid()).collect();
        let (mut x0, mut y0, mut x1, mut y1) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
        for c in &cs {
            (x0, y0, x1, y1) = (x0.min(c[0]), y0.min(c[1]), x1.max(c[0]), y1.max(c[1]));
        }
        if cs.is_empty() {
            return Density { x0: 0.0, y0: 0.0, w: 0, h: 0, share: vec![] };
        }
        let w = ((x1 - x0) / SQUARE) as usize + 1;
        let h = ((y1 - y0) / SQUARE) as usize + 1;
        let mut share = vec![0.0; w * h];
        for (b, c) in buildings.iter().zip(&cs) {
            let i = ((c[0] - x0) / SQUARE) as usize + ((c[1] - y0) / SQUARE) as usize * w;
            share[i] += crate::scenery::area(&b.points) as f32 / (SQUARE * SQUARE);
        }
        Density { x0, y0, w, h, share }
    }

    fn at(&self, c: [f32; 2]) -> f32 {
        let (i, j) = (((c[0] - self.x0) / SQUARE) as usize, ((c[1] - self.y0) / SQUARE) as usize);
        if i >= self.w || j >= self.h {
            return 0.0;
        }
        ((self.share[i + j * self.w] - 0.08) / 0.32).clamp(0.0, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scenery::{Roof, SOURCE_OSM};

    fn block(x: f32, y: f32, w: f32, h: f32) -> Building {
        Building {
            points: vec![[x, y], [x + w, y], [x + w, y + w], [x, y + w]],
            roof: Roof::Flat,
            wall: 0,
            height: h,
            roof_1998: [0; 3],
            roof_modern: [0; 3],
            source: SOURCE_OSM,
            levels: 0,
        }
    }

    #[test]
    fn lamps_stand_in_the_street_and_towers_get_red() {
        // A row of 20 m blocks 30 m apart along y = 0, and one 80 m tower.
        let mut bs: Vec<Building> = (0..10).map(|i| block(i as f32 * 30.0, 0.0, 20.0, 12.0)).collect();
        bs.push(block(500.0, 500.0, 30.0, 80.0));
        let l = lights(&bs, 7);
        assert_eq!(l, lights(&bs, 7), "seeded");
        let lamps: Vec<&Light> = l.iter().filter(|l| l.up == LAMP_UP).collect();
        assert!(lamps.len() >= 10, "{} lamps", lamps.len());
        // Every lamp stands outside every footprint.
        assert!(lamps.iter().all(|l| bs.iter().all(|b| !b.contains(l.at[0], l.at[1]))));
        // No two lamps share a square.
        let mut sq: Vec<_> =
            lamps.iter().map(|l| ((l.at[0] / LAMP_GAP).floor() as i32, (l.at[1] / LAMP_GAP).floor() as i32)).collect();
        sq.sort();
        sq.dedup();
        assert_eq!(sq.len(), lamps.len());
        assert!(l.iter().any(|l| l.color == RED && l.up == 81.0 && l.rank == 0.0));
        assert!(l.iter().all(|l| (0.0..1.0).contains(&l.rank) && l.color.iter().all(|c| (0.0..=1.0).contains(c))));
        // The glow: the dense row reads, the empty square around the tower's beacon does not.
        let mut g = Glow::new([0.0, -100.0, 600.0, 600.0], 100.0);
        l.iter().for_each(|x| g.add(x));
        let b = g.bytes();
        assert_eq!((g.w, g.h), (6, 7));
        assert!(b[1 + 6 * 6] > 100 && b[3 + 3 * 6] == 0, "{b:?}");
        // Windows only up the walls.
        assert!(l.iter().filter(|l| l.up != LAMP_UP && l.color != RED).all(|l| l.up < 80.0));
    }

    #[test]
    fn road_lamps_on_lit_roads_and_town_mains_only() {
        use crate::roads::*;
        let way =
            |id: u64, class: u8, flags: u8| Way { osm_id: id, first: 0, count: 0, class, flags, layer: 0, width: 8.0 };
        let line = |y: f32| vec![[0.0f32, y], [2000.0, y]];
        let (a, b, c, d, e, f) = (line(0.0), line(500.0), line(1000.0), line(1500.0), line(2000.0), line(2500.0));
        let r = Roads::from_lines([
            (way(1, CLASS_MINOR, FLAG_LIT), &a[..]),
            (way(2, CLASS_PRIMARY, 0), &b[..]),
            (way(3, CLASS_PRIMARY, FLAG_UNLIT), &c[..]),
            (way(4, CLASS_MINOR, 0), &d[..]),
            (way(5, CLASS_MOTORWAY, FLAG_LIT | FLAG_TUNNEL), &e[..]),
            (way(6, CLASS_PRIMARY, FLAG_LIT | FLAG_OFF_GROUND), &f[..]),
        ]);
        // A town: facade lamps along x 0..400 at y = 520 (by the untagged primary) and y = 1520 (the untagged minor).
        let facade: Vec<Light> = (0..10)
            .flat_map(|i| {
                [520.0, 1520.0].map(|y| Light { at: [i as f32 * 40.0, y], up: LAMP_UP, color: SODIUM, rank: 0.5 })
            })
            .collect();
        let l = road_lamps(&r, &facade);
        let on = |y: f32| l.iter().filter(|l| (l.at[1] - y).abs() < 10.0).collect::<Vec<_>>();
        // Lit minor road: the whole 2 km at 26 m, 5.5 m right of the eastward way (south).
        let lit = on(0.0);
        assert!((70..=78).contains(&lit.len()), "{}", lit.len());
        assert!(lit.iter().all(|l| l.at[1] == -5.5 && l.up == 6.0));
        // Untagged primary: only in the town (x up to ≈ 400 + 2 squares), not next to a facade lamp.
        let main = on(500.0);
        assert!(!main.is_empty() && main.iter().all(|l| l.at[0] < 750.0), "{main:?}");
        assert!(main.iter().all(|m| facade.iter().all(|f| (f.at[0] - m.at[0]).hypot(f.at[1] - m.at[1]) >= 12.0)));
        // Unlit, an untagged minor road, a tunnel, a piece off the ground: none.
        for y in [1000.0, 1500.0, 2000.0, 2500.0] {
            assert!(on(y).is_empty(), "{y}");
        }
        // One kind of lamp per class and square.
        assert!(lit.iter().all(|l| l.color == lit[0].color));
    }
}
