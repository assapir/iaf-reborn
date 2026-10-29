//! Roads: OpenStreetMap's roads and railways of the theatre that setup converts into the engine frame
//! (docs/scenery.md §6), written by `iaf-tools` (`roads::build`) and read here: the briefing map draws them, the
//! ground graphics place lamps along them, the mission editor routes on them. Files in `assets/converted/roads/`:
//! - `main.bin`: the motorways, trunk, primary and secondary roads (`MAIN_CLASS`) of the whole theatre, whole ways;
//! - `L3/r_<i>_<j>.bin`: every class in block (i, j): a level-3 node of the terrain (8192 units, about 10 km; the 4 × 4
//!   scenery cells `s_<4i..4i+3>_<4j..4j+3>`). A way is cut where it crosses a block's edge, at a vertex on the edge
//!   that both pieces hold (the same coordinates), so every segment lies in one block.
//!
//! Each file, little-endian:
//! - `b"IAFR"`, u32 version (`VERSION`), u32 point count p, u32 way count w, u32 index count n;
//! - p × (f32 x, f32 y): the vertices in engine metres (X east, Y north). Two ways that share an OpenStreetMap node
//!   share the vertex: a junction is one index;
//! - w × way: u64 OpenStreetMap way id, u32 vertex count, u8 class (`CLASS_*`), u8 flags (`FLAG_*`), i8 layer (OSM
//!   `layer`, 0 untagged), u8 pad, u16 width (decimetres);
//! - n × u32: the ways' vertex indices, way after way, in drawing order (a oneway way runs in its direction of travel).

use std::collections::{BinaryHeap, HashMap};
use std::sync::OnceLock;

pub const VERSION: u32 = 1;

/// Classes, most important first: `class <= max_class` filters by importance.
pub const CLASS_MOTORWAY: u8 = 0;
pub const CLASS_TRUNK: u8 = 1;
pub const CLASS_PRIMARY: u8 = 2;
pub const CLASS_SECONDARY: u8 = 3;
pub const CLASS_TERTIARY: u8 = 4;
/// residential, unclassified, living_street.
pub const CLASS_MINOR: u8 = 5;
pub const CLASS_SERVICE: u8 = 6;
pub const CLASS_TRACK: u8 = 7;
/// railway=rail; never part of the road graph.
pub const CLASS_RAIL: u8 = 8;
pub const CLASS_NAMES: [&str; 9] =
    ["motorway", "trunk", "primary", "secondary", "tertiary", "minor", "service", "track", "rail"];

/// A `*_link` ramp of its class.
pub const FLAG_LINK: u8 = 1;
pub const FLAG_BRIDGE: u8 = 2;
pub const FLAG_TUNNEL: u8 = 4;
pub const FLAG_UNPAVED: u8 = 8;
pub const FLAG_ONEWAY: u8 = 16;
/// OSM `lit`: yes, no; neither = untagged.
pub const FLAG_LIT: u8 = 32;
pub const FLAG_UNLIT: u8 = 64;
/// Off the game's open land: over an airbase, World scale Real's base sites or the 1998 sea. The map draws it; the
/// ground does not.
pub const FLAG_OFF_GROUND: u8 = 128;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Way {
    pub osm_id: u64,
    /// Its vertex indices: `Roads::index[first..first + count]`.
    pub first: u32,
    pub count: u32,
    pub class: u8,
    pub flags: u8,
    pub layer: i8,
    /// Metres.
    pub width: f32,
}

/// A point on a road (`Roads::nearest`): on segment `seg` (vertices seg, seg + 1) of way `way`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Nearest {
    pub way: u32,
    pub seg: u32,
    pub point: [f64; 2],
    pub dist: f64,
}

/// The classes `main.bin` holds: motorway to secondary.
pub const MAIN_CLASS: u8 = CLASS_SECONDARY;
/// A block's side in terrain units (a level-3 node) and the engine frame's terrain units (docs/georef.md):
/// X = tx · UNITS_TO_METRES − X0, Y = Y0 − ty · UNITS_TO_METRES.
pub const BLOCK_UNITS: f64 = 8192.0;
const UNITS_TO_METRES: f64 = 1.2411389;
const X0: f64 = 166850.0;
const Y0: f64 = 1043780.0;

/// The block holding an engine point (i east, j south).
pub fn block_of(p: [f64; 2]) -> (i32, i32) {
    let tx = (p[0] + X0) / UNITS_TO_METRES;
    let ty = (Y0 - p[1]) / UNITS_TO_METRES;
    ((tx / BLOCK_UNITS).floor() as i32, (ty / BLOCK_UNITS).floor() as i32)
}

/// Block (i, j)'s engine rect [x0, y0, x1, y1] (y0 south).
pub fn block_rect(i: i32, j: i32) -> [f64; 4] {
    let s = BLOCK_UNITS * UNITS_TO_METRES;
    [i as f64 * s - X0, Y0 - (j + 1) as f64 * s, (i + 1) as f64 * s - X0, Y0 - j as f64 * s]
}

/// A way's attributes and its points (`Roads::from_lines`).
pub type Line = (Way, Vec<[f32; 2]>);
/// The road graph: per vertex the start of its edges, then the edges (neighbour, way).
type Graph = (Vec<u32>, Vec<(u32, u32)>);

/// The spatial grid's cell (m).
const GRID_M: f64 = 1000.0;

#[derive(Debug, Default)]
pub struct Roads {
    pub points: Vec<[f32; 2]>,
    pub ways: Vec<Way>,
    pub index: Vec<u32>,
    grid: HashMap<(i32, i32), Vec<u32>>,
    /// The road graph (CSR over the vertices), made on the first route.
    graph: OnceLock<Graph>,
}

fn grid_key(x: f64, y: f64) -> (i32, i32) {
    ((x / GRID_M).floor() as i32, (y / GRID_M).floor() as i32)
}

fn closest(p: [f64; 2], a: [f64; 2], b: [f64; 2]) -> [f64; 2] {
    let d = [b[0] - a[0], b[1] - a[1]];
    let l2 = d[0] * d[0] + d[1] * d[1];
    let t = if l2 > 0.0 { (((p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1]) / l2).clamp(0.0, 1.0) } else { 0.0 };
    [a[0] + t * d[0], a[1] + t * d[1]]
}

fn dist(a: [f64; 2], b: [f64; 2]) -> f64 {
    (a[0] - b[0]).hypot(a[1] - b[1])
}

impl Roads {
    /// From vertices and ways (`first` set from the counts), with the grid built.
    pub fn new(points: Vec<[f32; 2]>, mut ways: Vec<Way>, index: Vec<u32>) -> Self {
        let mut first = 0;
        for w in &mut ways {
            w.first = first;
            first += w.count;
        }
        let mut r = Roads { points, ways, index, ..Default::default() };
        for k in 0..r.ways.len() {
            let b = r.bbox(k as u32);
            let (a, c) = (grid_key(b[0], b[1]), grid_key(b[2], b[3]));
            for gy in a.1..=c.1 {
                for gx in a.0..=c.0 {
                    r.grid.entry((gx, gy)).or_default().push(k as u32);
                }
            }
        }
        r
    }

    /// From lines of points (each with its way's attributes): equal points (the same bits) become one vertex.
    pub fn from_lines<'a>(lines: impl IntoIterator<Item = (Way, &'a [[f32; 2]])>) -> Self {
        let mut ids: HashMap<(u32, u32), u32> = HashMap::new();
        let (mut points, mut ways, mut index) = (Vec::new(), Vec::new(), Vec::new());
        for (mut w, pts) in lines {
            let before = index.len();
            for p in pts {
                let id = *ids.entry((p[0].to_bits(), p[1].to_bits())).or_insert_with(|| {
                    points.push(*p);
                    points.len() as u32 - 1
                });
                if index.len() == before || index.last() != Some(&id) {
                    index.push(id);
                }
            }
            if index.len() - before < 2 {
                index.truncate(before);
                continue;
            }
            w.count = (index.len() - before) as u32;
            ways.push(w);
        }
        Roads::new(points, ways, index)
    }

    /// Several files as one (their ways in order; a point in two becomes one vertex): blocks for a route.
    pub fn merge(parts: &[&Roads]) -> Self {
        let lines: Vec<Line> = parts
            .iter()
            .flat_map(|r| {
                (0..r.ways.len() as u32)
                    .map(move |w| (r.ways[w as usize], r.way_index(w).iter().map(|&i| r.points[i as usize]).collect()))
            })
            .collect();
        Roads::from_lines(lines.iter().map(|(w, p)| (*w, p.as_slice())))
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut o = Vec::with_capacity(20 + self.points.len() * 8 + self.ways.len() * 18 + self.index.len() * 4);
        o.extend_from_slice(b"IAFR");
        for v in [VERSION, self.points.len() as u32, self.ways.len() as u32, self.index.len() as u32] {
            o.extend_from_slice(&v.to_le_bytes());
        }
        for p in &self.points {
            o.extend_from_slice(&p[0].to_le_bytes());
            o.extend_from_slice(&p[1].to_le_bytes());
        }
        for w in &self.ways {
            o.extend_from_slice(&w.osm_id.to_le_bytes());
            o.extend_from_slice(&w.count.to_le_bytes());
            o.extend_from_slice(&[w.class, w.flags, w.layer as u8, 0]);
            o.extend_from_slice(&((w.width * 10.0).round().clamp(0.0, 65535.0) as u16).to_le_bytes());
        }
        for i in &self.index {
            o.extend_from_slice(&i.to_le_bytes());
        }
        o
    }

    pub fn decode(d: &[u8]) -> Option<Roads> {
        let u32_at = |o: usize| Some(u32::from_le_bytes(d.get(o..o + 4)?.try_into().ok()?));
        if d.get(..4)? != b"IAFR" || u32_at(4)? != VERSION {
            return None;
        }
        let (np, nw, ni) = (u32_at(8)? as usize, u32_at(12)? as usize, u32_at(16)? as usize);
        let (pw, ww) = (20, 20 + np * 8);
        let iw = ww + nw * 18;
        if d.len() != iw + ni * 4 {
            return None;
        }
        let f = |o: usize| f32::from_le_bytes(d[o..o + 4].try_into().unwrap());
        let points = (0..np).map(|k| [f(pw + k * 8), f(pw + k * 8 + 4)]).collect();
        let ways: Vec<Way> = d[ww..iw]
            .as_chunks::<18>()
            .0
            .iter()
            .map(|c| Way {
                osm_id: u64::from_le_bytes(c[0..8].try_into().unwrap()),
                first: 0,
                count: u32::from_le_bytes(c[8..12].try_into().unwrap()),
                class: c[12],
                flags: c[13],
                layer: c[14] as i8,
                width: u16::from_le_bytes([c[16], c[17]]) as f32 / 10.0,
            })
            .collect();
        let index: Vec<u32> = d[iw..].as_chunks::<4>().0.iter().map(|c| u32::from_le_bytes(*c)).collect();
        if ways.iter().map(|w| w.count as usize).sum::<usize>() != ni || index.iter().any(|&i| i as usize >= np) {
            return None;
        }
        Some(Roads::new(points, ways, index))
    }

    pub fn load(path: &std::path::Path) -> Option<Roads> {
        Roads::decode(&std::fs::read(path).ok()?)
    }

    /// Way `w`'s vertex indices.
    pub fn way_index(&self, w: u32) -> &[u32] {
        let w = &self.ways[w as usize];
        &self.index[w.first as usize..(w.first + w.count) as usize]
    }

    /// Way `w`'s points in engine metres.
    pub fn way_points(&self, w: u32) -> impl Iterator<Item = [f64; 2]> + '_ {
        self.way_index(w).iter().map(|&i| self.point(i))
    }

    pub fn point(&self, i: u32) -> [f64; 2] {
        let p = self.points[i as usize];
        [p[0] as f64, p[1] as f64]
    }

    fn bbox(&self, w: u32) -> [f64; 4] {
        self.way_points(w).fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, p| {
            [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
        })
    }

    /// The ways of class `max_class` or more important whose box meets the rect [min, max] (engine metres), sorted.
    /// Whole ways: a way reaching out of the rect is not cut.
    pub fn in_rect(&self, min: [f64; 2], max: [f64; 2], max_class: u8) -> Vec<u32> {
        let (a, c) = (grid_key(min[0], min[1]), grid_key(max[0], max[1]));
        let mut out = Vec::new();
        for gy in a.1..=c.1 {
            for gx in a.0..=c.0 {
                out.extend(self.grid.get(&(gx, gy)).into_iter().flatten().copied());
            }
        }
        out.sort_unstable();
        out.dedup();
        out.retain(|&w| {
            let b = self.bbox(w);
            self.ways[w as usize].class <= max_class
                && b[0] <= max[0]
                && b[2] >= min[0]
                && b[1] <= max[1]
                && b[3] >= min[1]
        });
        out
    }

    /// The nearest point on a road of class `max_class` or more important; railways are left out. None when there is
    /// no such road.
    pub fn nearest(&self, p: [f64; 2], max_class: u8) -> Option<Nearest> {
        let mut best: Option<Nearest> = None;
        let mut r = GRID_M;
        // Grows the search square until the best is closer than its edge (or the square holds every way).
        loop {
            for w in self.in_rect([p[0] - r, p[1] - r], [p[0] + r, p[1] + r], max_class.min(CLASS_TRACK)) {
                let idx = self.way_index(w);
                for (s, pair) in idx.windows(2).enumerate() {
                    let q = closest(p, self.point(pair[0]), self.point(pair[1]));
                    let d = dist(p, q);
                    if best.is_none_or(|b| d < b.dist) {
                        best = Some(Nearest { way: w, seg: s as u32, point: q, dist: d });
                    }
                }
            }
            if best.is_some_and(|b| b.dist <= r) || r > 2e6 {
                return best;
            }
            r *= 2.0;
        }
    }

    /// The road graph: per vertex its edges (neighbour, way), both ways (vehicles on the map ignore oneway).
    fn graph(&self) -> &Graph {
        self.graph.get_or_init(|| {
            let mut deg = vec![0u32; self.points.len() + 1];
            let segs = || {
                (0..self.ways.len() as u32)
                    .filter(|&w| self.ways[w as usize].class != CLASS_RAIL)
                    .flat_map(move |w| self.way_index(w).windows(2).map(move |s| (s[0], s[1], w)))
            };
            for (a, b, _) in segs() {
                deg[a as usize + 1] += 1;
                deg[b as usize + 1] += 1;
            }
            for k in 1..deg.len() {
                deg[k] += deg[k - 1];
            }
            let mut fill = deg.clone();
            let mut edges = vec![(0, 0); *deg.last().unwrap() as usize];
            for (a, b, w) in segs() {
                edges[fill[a as usize] as usize] = (b, w);
                fill[a as usize] += 1;
                edges[fill[b as usize] as usize] = (a, w);
                fill[b as usize] += 1;
            }
            (deg, edges)
        })
    }

    /// The shortest route on roads of class `max_class` or more important from the road point nearest `a` to the one
    /// nearest `b` (A* over the junctions): the snapped start, the vertices between, the snapped end. None when either
    /// end has no road or the two are not connected.
    pub fn route(&self, a: [f64; 2], b: [f64; 2], max_class: u8) -> Option<Vec<[f64; 2]>> {
        let (sa, sb) = (self.nearest(a, max_class)?, self.nearest(b, max_class)?);
        let ends = |n: &Nearest| {
            let i = self.way_index(n.way);
            [i[n.seg as usize], i[n.seg as usize + 1]]
        };
        let (ea, eb) = (ends(&sa), ends(&sb));
        if ea == eb || ea == [eb[1], eb[0]] {
            return Some(vec![sa.point, sb.point]);
        }
        let (starts, edges) = self.graph();
        let n = self.points.len();
        let goal = n as u32; // a virtual vertex: the snapped end
        let mut g = vec![f64::INFINITY; n + 1];
        let mut prev = vec![u32::MAX; n + 1];
        let mut heap = BinaryHeap::new();
        // Costs are non-negative: their bits order as the values do.
        let push = |heap: &mut BinaryHeap<std::cmp::Reverse<(u64, u32)>>, f: f64, v: u32| {
            heap.push(std::cmp::Reverse((f.to_bits(), v)))
        };
        for v in ea {
            g[v as usize] = dist(sa.point, self.point(v));
            push(&mut heap, g[v as usize] + dist(self.point(v), sb.point), v);
        }
        while let Some(std::cmp::Reverse((_, v))) = heap.pop() {
            if v == goal {
                break;
            }
            let gv = g[v as usize];
            let pv = self.point(v);
            let mut relax = |heap: &mut BinaryHeap<_>, u: u32, cost: f64| {
                let to = if u == goal { sb.point } else { self.point(u) };
                if gv + cost < g[u as usize] {
                    g[u as usize] = gv + cost;
                    prev[u as usize] = v;
                    push(heap, g[u as usize] + dist(to, sb.point), u);
                }
            };
            if eb.contains(&v) {
                relax(&mut heap, goal, dist(pv, sb.point));
            }
            for &(u, w) in &edges[starts[v as usize] as usize..starts[v as usize + 1] as usize] {
                if self.ways[w as usize].class <= max_class {
                    relax(&mut heap, u, dist(pv, self.point(u)));
                }
            }
        }
        if prev[goal as usize] == u32::MAX {
            return None;
        }
        let mut path = vec![sb.point];
        let mut v = prev[goal as usize];
        while v != u32::MAX {
            path.push(self.point(v));
            v = prev[v as usize];
        }
        path.push(sa.point);
        path.reverse();
        Some(path)
    }
}

/// The ground's road mask (docs/rendering.md §1.8): the signed distance of each texel centre to the nearest road's
/// edge stored as `MASK_ZERO + d · MASK_STEPS` (d in metres, negative on the road), up to MASK_RANGE m either way.
pub const MASK_RANGE: f32 = 8.0;
pub const MASK_ZERO: f32 = 128.0;
pub const MASK_STEPS: f32 = 16.0;

/// The road mask over `n` × `n` texels of `m` metres, west edge `x0`, north edge `y1` (row 0 north), RG8: R the signed
/// distance (MASK_*), G the nearest road's attributes: bit 7 paved, bits 0–6 its width in half metres. The roads drawn
/// on the ground: classes up to track, not tunnels, not pieces off the ground (`FLAG_OFF_GROUND`).
pub fn mask(parts: &[&Roads], x0: f64, y1: f64, m: f64, n: usize) -> Vec<u8> {
    let mut d = vec![MASK_RANGE; n * n];
    let mut g = vec![0u8; n * n];
    let hi = (n as f32) - 0.5;
    for r in parts {
        for (k, w) in r.ways.iter().enumerate() {
            if w.class > CLASS_TRACK || w.flags & (FLAG_TUNNEL | FLAG_OFF_GROUND) != 0 {
                continue;
            }
            let hw = w.width * 0.5;
            let attr = (if w.flags & FLAG_UNPAVED == 0 { 0x80 } else { 0 }) | (w.width * 2.0).round().min(127.0) as u8;
            let pad = (hw + MASK_RANGE) / m as f32;
            // Texel coordinates (x east, y south from the north-west corner); texel (i, j)'s centre is (i + ½, j + ½).
            let t = |p: [f64; 2]| [((p[0] - x0) / m) as f32, ((y1 - p[1]) / m) as f32];
            for s in r.way_index(k as u32).windows(2) {
                let (a, b) = (t(r.point(s[0])), t(r.point(s[1])));
                let (lo_x, hi_x) = (a[0].min(b[0]) - pad, a[0].max(b[0]) + pad);
                let (lo_y, hi_y) = (a[1].min(b[1]) - pad, a[1].max(b[1]) + pad);
                if hi_x < -0.5 || hi_y < -0.5 || lo_x > hi || lo_y > hi {
                    continue;
                }
                let ab = [b[0] - a[0], b[1] - a[1]];
                let l2 = (ab[0] * ab[0] + ab[1] * ab[1]).max(1e-12);
                let (i0, i1) = ((lo_x - 0.5).max(0.0).ceil() as usize, ((hi_x - 0.5).min(hi - 0.5)).floor() as usize);
                let (j0, j1) = ((lo_y - 0.5).max(0.0).ceil() as usize, ((hi_y - 0.5).min(hi - 0.5)).floor() as usize);
                for j in j0..=j1 {
                    let py = j as f32 + 0.5 - a[1];
                    for i in i0..=i1 {
                        let px = i as f32 + 0.5 - a[0];
                        let u = ((px * ab[0] + py * ab[1]) / l2).clamp(0.0, 1.0);
                        let e = (px - u * ab[0]).hypot(py - u * ab[1]) * m as f32 - hw;
                        let o = i + j * n;
                        if e < d[o] {
                            d[o] = e;
                            g[o] = attr;
                        }
                    }
                }
            }
        }
    }
    let mut out = Vec::with_capacity(2 * n * n);
    for (e, a) in d.iter().zip(&g) {
        out.push((MASK_ZERO + e * MASK_STEPS).round().clamp(0.0, 255.0) as u8);
        out.push(*a);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn way(class: u8, count: u32) -> Way {
        Way { osm_id: 7, first: 0, count, class, flags: FLAG_LIT, layer: -1, width: 7.5 }
    }

    /// A plus-shaped junction at (0, 0): a primary road west–east, a minor road south–north; a motorway far off.
    fn sample() -> Roads {
        let points = vec![
            [-1000.0, 0.0],
            [0.0, 0.0],
            [1000.0, 0.0],
            [0.0, -1000.0],
            [0.0, 1000.0],
            [5000.0, 5000.0],
            [6000.0, 5000.0],
        ];
        let ways = vec![way(CLASS_PRIMARY, 3), way(CLASS_MINOR, 3), way(CLASS_MOTORWAY, 2)];
        Roads::new(points, ways, vec![0, 1, 2, 3, 1, 4, 5, 6])
    }

    #[test]
    fn round_trip() {
        let r = sample();
        let d = Roads::decode(&r.encode()).unwrap();
        assert_eq!(d.points, r.points);
        assert_eq!(d.ways, r.ways);
        assert_eq!(d.index, r.index);
        assert!(Roads::decode(&r.encode()[..30]).is_none());
    }

    #[test]
    fn queries() {
        let r = sample();
        assert_eq!(r.in_rect([-50.0, 500.0], [50.0, 600.0], CLASS_TRACK), [1]);
        assert!(r.in_rect([-50.0, 500.0], [50.0, 600.0], CLASS_PRIMARY).is_empty(), "minor filtered out");
        assert_eq!(r.in_rect([4000.0, 4000.0], [9000.0, 9000.0], CLASS_MOTORWAY), [2]);
        let n = r.nearest([300.0, 40.0], CLASS_TRACK).unwrap();
        assert_eq!((n.way, n.seg, n.point), (0, 1, [300.0, 0.0]));
        let n = r.nearest([30.0, 700.0], CLASS_TRACK).unwrap();
        assert_eq!((n.way, n.seg, n.point), (1, 1, [0.0, 700.0]));
        let n = r.nearest([30.0, 700.0], CLASS_PRIMARY).unwrap();
        assert_eq!(n.way, 0, "the minor road is filtered out");
        assert_eq!(r.nearest([5500.0, 5100.0], CLASS_TRACK).unwrap().way, 2);
    }

    #[test]
    fn blocks_and_merge() {
        let r = block_rect(20, 30);
        assert_eq!(block_of([r[0] + 1.0, r[3] - 1.0]), (20, 30));
        assert_eq!(block_of([r[2] + 1.0, r[1] - 1.0]), (21, 31));
        // Two halves of the west–east road in two files meet at (0, 0): merged, one vertex, routable.
        let west = Roads::from_lines([(way(CLASS_PRIMARY, 0), &[[-1000.0f32, 0.0], [0.0, 0.0]][..])]);
        let east = Roads::from_lines([(way(CLASS_PRIMARY, 0), &[[0.0f32, 0.0], [0.0, 0.0], [1000.0, 0.0]][..])]);
        assert_eq!(east.way_index(0).len(), 2, "a repeated point is dropped");
        let m = Roads::merge(&[&west, &east]);
        assert_eq!(m.points.len(), 3);
        assert_eq!(m.route([-900.0, 0.0], [900.0, 0.0], CLASS_TRACK).unwrap().len(), 3);
    }

    #[test]
    fn routes_through_the_junction() {
        let r = sample();
        let p = r.route([-800.0, 10.0], [10.0, 800.0], CLASS_TRACK).unwrap();
        assert_eq!(p, [[-800.0, 0.0], [0.0, 0.0], [0.0, 800.0]]);
        // Same segment: straight.
        assert_eq!(r.route([100.0, 5.0], [400.0, 5.0], CLASS_TRACK).unwrap(), [[100.0, 0.0], [400.0, 0.0]]);
        // The motorway is not connected.
        assert!(r.route([-800.0, 0.0], [5500.0, 5000.0], CLASS_TRACK).is_none());
        // Primary only: both ends snap onto the primary road.
        assert_eq!(
            r.route([-800.0, 10.0], [10.0, 800.0], CLASS_PRIMARY).unwrap(),
            [[-800.0, 0.0], [0.0, 0.0], [10.0, 0.0]]
        );
    }

    #[test]
    fn mask_marks_the_road_and_skips_tunnels() {
        // A 7.5 m primary west–east along y = 0 and a tunnel north–south, on a 64 × 64 mask of 2 m from (-64, 64).
        let mut r = sample();
        r.ways[1].flags |= FLAG_TUNNEL;
        let m = mask(&[&r], -64.0, 64.0, 2.0, 64);
        let at = |x: f64, y: f64| {
            let o = 2 * (((x + 64.0) / 2.0) as usize + ((64.0 - y) / 2.0) as usize * 64);
            ((m[o] as f32 - MASK_ZERO) / MASK_STEPS, m[o + 1])
        };
        let (d, g) = at(10.0, 1.0);
        assert!((d - (1.0 - 3.75)).abs() < 0.1, "{d}");
        assert_eq!(g, 0x80 | 15, "paved, 7.5 m");
        assert!((at(10.0, 5.0).0 - (5.0 - 3.75)).abs() < 0.1);
        assert_eq!(at(10.0, 40.0).0, (255.0 - MASK_ZERO) / MASK_STEPS, "out of range: the most");
        assert_eq!(at(1.0, 40.0).1, 0, "the tunnel is not drawn");
    }
}
