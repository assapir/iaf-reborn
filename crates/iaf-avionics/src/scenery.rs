//! Scenery: the buildings and trees that setup generates over the Survey of Israel 2 m photo (docs/scenery.md). One
//! cell per level-1 node of the `mapi2015` layer (`assets/converted/scenery/L1/s_<i>_<j>.bin`, the layer's own keys).
//! This module holds the cell file (written by `iaf-tools`, read by `iaf-godot`) and the queries on it.
//!
//! Cell file, little-endian:
//! - `b"IAFS"`, u32 version (`VERSION`), u32 building count, u32 tree count;
//! - per building: u16 point count n, u8 roof (`Roof`), u8 wall material, f32 height (m), u8×3 roof colour on the
//!   1998-colour photo, u8×3 on the modern photo, u8 source (`SOURCE_*`), u8 levels (0 = untagged), then n × (f32 x,
//!   f32 y) world metres (X east, Y north), counter-clockwise, not closed;
//! - per tree: f32 x, f32 y, f32 height (m), u8 kind (`TreeKind`), 3 pad bytes.
//!
//! Buildings and trees are sorted by (y, x) of their centroid / position; a building's id is `<i>_<j>:<index>`,
//! stable for one scenery release (`manifest.json` `release`).

use std::collections::{HashMap, HashSet};

use crate::Vec3;

pub const VERSION: u32 = 1;
pub const SOURCE_OSM: u8 = 0;
pub const SOURCE_MS: u8 = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Roof {
    Flat = 0,
    Gabled = 1,
    Dome = 2,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum TreeKind {
    Pine = 0,
    Broadleaf = 1,
    Palm = 2,
    Cypress = 3,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Building {
    pub points: Vec<[f32; 2]>,
    pub roof: Roof,
    pub wall: u8,
    pub height: f32,
    pub roof_1998: [u8; 3],
    pub roof_modern: [u8; 3],
    pub source: u8,
    pub levels: u8,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Tree {
    pub x: f32,
    pub y: f32,
    pub height: f32,
    pub kind: TreeKind,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Cell {
    pub buildings: Vec<Building>,
    pub trees: Vec<Tree>,
}

impl Building {
    pub fn centroid(&self) -> [f32; 2] {
        let n = self.points.len().max(1) as f32;
        let (sx, sy) = self.points.iter().fold((0.0, 0.0), |(sx, sy), p| (sx + p[0], sy + p[1]));
        [sx / n, sy / n]
    }

    /// Whether a point (X east, Y north) is inside the footprint (even-odd rule).
    pub fn contains(&self, x: f32, y: f32) -> bool {
        let p = &self.points;
        let mut inside = false;
        let mut j = p.len().wrapping_sub(1);
        for i in 0..p.len() {
            let ([xi, yi], [xj, yj]) = (p[i], p[j]);
            if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi {
                inside = !inside;
            }
            j = i;
        }
        inside
    }
}

impl Cell {
    /// Sorts buildings and trees by (y, x), the order the ids count in.
    pub fn sort(&mut self) {
        let key = |p: [f32; 2]| (p[1], p[0]);
        self.buildings.sort_by(|a, b| key(a.centroid()).partial_cmp(&key(b.centroid())).unwrap());
        self.trees.sort_by(|a, b| key([a.x, a.y]).partial_cmp(&key([b.x, b.y])).unwrap());
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut o = Vec::new();
        o.extend_from_slice(b"IAFS");
        for v in [VERSION, self.buildings.len() as u32, self.trees.len() as u32] {
            o.extend_from_slice(&v.to_le_bytes());
        }
        for b in &self.buildings {
            o.extend_from_slice(&(b.points.len() as u16).to_le_bytes());
            o.extend_from_slice(&[b.roof as u8, b.wall]);
            o.extend_from_slice(&b.height.to_le_bytes());
            o.extend_from_slice(&b.roof_1998);
            o.extend_from_slice(&b.roof_modern);
            o.extend_from_slice(&[b.source, b.levels]);
            for p in &b.points {
                o.extend_from_slice(&p[0].to_le_bytes());
                o.extend_from_slice(&p[1].to_le_bytes());
            }
        }
        for t in &self.trees {
            for v in [t.x, t.y, t.height] {
                o.extend_from_slice(&v.to_le_bytes());
            }
            o.extend_from_slice(&[t.kind as u8, 0, 0, 0]);
        }
        o
    }

    pub fn decode(data: &[u8]) -> Option<Cell> {
        let mut r = Reader { data, at: 0 };
        if r.take(4)? != b"IAFS" || r.u32()? != VERSION {
            return None;
        }
        let (nb, nt) = (r.u32()? as usize, r.u32()? as usize);
        let mut cell = Cell::default();
        for _ in 0..nb {
            let n = r.u16()? as usize;
            let roof = match r.u8()? {
                1 => Roof::Gabled,
                2 => Roof::Dome,
                _ => Roof::Flat,
            };
            let wall = r.u8()?;
            let height = r.f32()?;
            let roof_1998 = [r.u8()?, r.u8()?, r.u8()?];
            let roof_modern = [r.u8()?, r.u8()?, r.u8()?];
            let (source, levels) = (r.u8()?, r.u8()?);
            let points = (0..n).map(|_| Some([r.f32()?, r.f32()?])).collect::<Option<_>>()?;
            cell.buildings.push(Building { points, roof, wall, height, roof_1998, roof_modern, source, levels });
        }
        for _ in 0..nt {
            let (x, y, height) = (r.f32()?, r.f32()?, r.f32()?);
            let kind = match r.u8()? {
                0 => TreeKind::Pine,
                2 => TreeKind::Palm,
                3 => TreeKind::Cypress,
                _ => TreeKind::Broadleaf,
            };
            r.take(3)?;
            cell.trees.push(Tree { x, y, height, kind });
        }
        Some(cell)
    }
}

/// The edge of the grid buckets a cell's buildings and trees are indexed in (m).
const BUCKET: f64 = 16.0;
/// A tree's crown radius as a share of its height.
pub const CROWN: f32 = 0.3;
/// A damaged building's height as a share of its own.
pub const DAMAGED: f32 = 0.25;

type Key = (i32, i32);

fn bucket(x: f64, y: f64) -> Key {
    ((x / BUCKET).floor() as i32, (y / BUCKET).floor() as i32)
}

/// The world-metre box of a footprint or a crown: [x0, y0, x1, y1].
type Box2 = [f64; 4];

fn grow(a: Box2, b: Box2) -> Box2 {
    [a[0].min(b[0]), a[1].min(b[1]), a[2].max(b[2]), a[3].max(b[3])]
}

fn footprint_box(b: &Building) -> Box2 {
    b.points.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |a, p| {
        let (x, y) = (f64::from(p[0]), f64::from(p[1]));
        grow(a, [x, y, x, y])
    })
}

fn crown_box(t: &Tree) -> Box2 {
    let r = f64::from(CROWN * t.height);
    let (x, y) = (f64::from(t.x), f64::from(t.y));
    [x - r, y - r, x + r, y + r]
}

/// Every bucket a box touches gets the item.
fn index(map: &mut HashMap<Key, Vec<u32>>, b: Box2, item: u32) {
    let ((i0, j0), (i1, j1)) = (bucket(b[0], b[1]), bucket(b[2], b[3]));
    for i in i0..=i1 {
        for j in j0..=j1 {
            map.entry((i, j)).or_default().push(item);
        }
    }
}

/// A loaded cell with its bucket index.
struct CellIndex {
    cell: Cell,
    centroids: Vec<[f64; 2]>,
    /// The box around every footprint and crown.
    bounds: Box2,
    buildings: HashMap<Key, Vec<u32>>,
    trees: HashMap<Key, Vec<u32>>,
}

impl CellIndex {
    fn new(cell: Cell) -> CellIndex {
        let mut ix = CellIndex {
            centroids: cell.buildings.iter().map(|b| b.centroid().map(f64::from)).collect(),
            bounds: [f64::MAX, f64::MAX, f64::MIN, f64::MIN],
            buildings: HashMap::new(),
            trees: HashMap::new(),
            cell: Cell::default(),
        };
        for (k, b) in cell.buildings.iter().enumerate() {
            let bx = footprint_box(b);
            ix.bounds = grow(ix.bounds, bx);
            index(&mut ix.buildings, bx, k as u32);
        }
        for (k, t) in cell.trees.iter().enumerate() {
            let bx = crown_box(t);
            ix.bounds = grow(ix.bounds, bx);
            index(&mut ix.trees, bx, k as u32);
        }
        ix.cell = cell;
        ix
    }

    fn near(&self, x: f64, y: f64, r: f64) -> bool {
        let b = self.bounds;
        x >= b[0] - r && x <= b[2] + r && y >= b[1] - r && y <= b[3] + r
    }
}

/// A building found by `Scenery::nearest`.
#[derive(Clone, Debug, PartialEq)]
pub struct Found {
    pub id: String,
    pub centroid: [f64; 2],
    pub height: f64,
    pub area: f64,
    /// The footprint (world X, Y), counter-clockwise.
    pub points: Vec<[f32; 2]>,
}

/// The loaded scenery cells and the buildings' damage, for the whole process (docs/scenery.md §2).
#[derive(Default)]
pub struct Scenery {
    cells: HashMap<(i64, i64), CellIndex>,
    /// Damaged buildings by (cell i, cell j, index); kept when their cell unloads.
    damage: HashSet<(i64, i64, u32)>,
}

/// `"<i>_<j>:<index>"` → (i, j, index).
fn parse_id(id: &str) -> Option<(i64, i64, u32)> {
    let (cell, k) = id.split_once(':')?;
    let (i, j) = cell.split_once('_')?;
    Some((i.parse().ok()?, j.parse().ok()?, k.parse().ok()?))
}

/// The polygon's area (m², positive).
pub fn area(points: &[[f32; 2]]) -> f64 {
    signed_area(points).abs()
}

fn signed_area(p: &[[f32; 2]]) -> f64 {
    let n = p.len();
    (0..n)
        .map(|k| {
            let (a, b) = (p[k], p[(k + 1) % n]);
            f64::from(a[0]) * f64::from(b[1]) - f64::from(b[0]) * f64::from(a[1])
        })
        .sum::<f64>()
        / 2.0
}

/// The t where the ray's value `z0 + dz·t` lies in [lo, hi].
fn span(z0: f64, dz: f64, lo: f64, hi: f64) -> (f64, f64) {
    if dz.abs() < 1e-12 {
        return if (lo..=hi).contains(&z0) { (f64::MIN, f64::MAX) } else { (f64::MAX, f64::MIN) };
    }
    let (a, b) = ((lo - z0) / dz, (hi - z0) / dz);
    (a.min(b), a.max(b))
}

/// The first t of [a0, a1] ∩ [b0, b1] ∩ [c0, c1], if any.
fn first(a: (f64, f64), b: (f64, f64), c: (f64, f64)) -> Option<f64> {
    let (lo, hi) = (a.0.max(b.0).max(c.0), a.1.min(b.1).min(c.1));
    (lo <= hi).then_some(lo)
}

impl Scenery {
    pub fn insert(&mut self, i: i64, j: i64, cell: Cell) {
        self.cells.insert((i, j), CellIndex::new(cell));
    }

    pub fn remove(&mut self, i: i64, j: i64) {
        self.cells.remove(&(i, j));
    }

    pub fn is_empty(&self) -> bool {
        self.cells.is_empty()
    }

    pub fn cell(&self, i: i64, j: i64) -> Option<&Cell> {
        self.cells.get(&(i, j)).map(|c| &c.cell)
    }

    pub fn set_damaged(&mut self, id: &str, damaged: bool) {
        if let Some(k) = parse_id(id) {
            if damaged {
                self.damage.insert(k);
            } else {
                self.damage.remove(&k);
            }
        }
    }

    pub fn is_damaged(&self, id: &str) -> bool {
        parse_id(id).is_some_and(|k| self.damage.contains(&k))
    }

    pub fn building(&self, id: &str) -> Option<&Building> {
        let (i, j, k) = parse_id(id)?;
        self.cell(i, j)?.buildings.get(k as usize)
    }

    /// One byte per building of a loaded cell, 1 = damaged.
    pub fn damage_index(&self, i: i64, j: i64) -> Vec<u8> {
        self.cell(i, j).map_or_else(Vec::new, |c| {
            (0..c.buildings.len() as u32).map(|k| u8::from(self.damage.contains(&(i, j, k)))).collect()
        })
    }

    /// A building's height as it stands (m): lower when damaged.
    pub fn height(&self, i: i64, j: i64, k: u32, b: &Building) -> f32 {
        if self.damage.contains(&(i, j, k)) { b.height * DAMAGED } else { b.height }
    }

    /// The height above ground (m) of the scenery at a world point (X east, Y north): the roof of the building whose
    /// footprint holds it (standing on the lowest terrain under its corners, as drawn, so on a slope the roof stays
    /// level), the top of a tree whose crown covers it, else 0.
    pub fn top(&self, x: f64, y: f64, ground: &dyn Fn(Vec3) -> Option<f64>) -> f64 {
        let key = bucket(x, y);
        let (xf, yf) = (x as f32, y as f32);
        let mut top = 0.0f32;
        for (&(i, j), c) in &self.cells {
            if !c.near(x, y, 0.0) {
                continue;
            }
            for &k in c.buildings.get(&key).into_iter().flatten() {
                let b = &c.cell.buildings[k as usize];
                if b.contains(xf, yf) {
                    let here = ground(Vec3::new(x, y, 0.0));
                    let lift = base(b, ground).zip(here).map_or(0.0, |(b, h)| (b - h) as f32);
                    top = top.max(self.height(i, j, k, b) + lift);
                }
            }
            for &k in c.trees.get(&key).into_iter().flatten() {
                let t = &c.cell.trees[k as usize];
                let r = CROWN * t.height;
                if (t.x - xf).powi(2) + (t.y - yf).powi(2) <= r * r {
                    top = top.max(t.height);
                }
            }
        }
        f64::from(top)
    }

    /// The distance along a ray (world frame, Z up) to the first building or tree it meets within `max`, a
    /// building standing on the lowest terrain under its corners (as drawn), a tree on the terrain under it.
    pub fn ray(&self, from: Vec3, dir: Vec3, max: f64, ground: &dyn Fn(Vec3) -> Option<f64>) -> Option<f64> {
        let d = dir.try_normalize()?;
        let mut best: Option<f64> = None;
        for (&(i, j), c) in &self.cells {
            let Some((t0, t1)) = clip(from, d, max, c.bounds) else { continue };
            let (mut bs, mut ts) = (Vec::new(), Vec::new());
            along(from, d, t0, t1, |key| {
                bs.extend(c.buildings.get(&key).into_iter().flatten());
                ts.extend(c.trees.get(&key).into_iter().flatten());
            });
            for v in [&mut bs, &mut ts] {
                v.sort_unstable();
                v.dedup();
            }
            let range = (0.0, max);
            for k in bs {
                let b = &c.cell.buildings[k as usize];
                let Some(base) = base(b, ground) else { continue };
                let z = span(from.z, d.z, base, base + f64::from(self.height(i, j, k, b)));
                for inside in inside_spans(b, from, d) {
                    if let Some(t) = first(range, z, inside) {
                        best = Some(best.map_or(t, |b: f64| b.min(t)));
                    }
                }
            }
            for k in ts {
                let t = &c.cell.trees[k as usize];
                let (cx, cy) = (f64::from(t.x), f64::from(t.y));
                let Some(base) = ground(Vec3::new(cx, cy, 0.0)) else { continue };
                let r = f64::from(CROWN * t.height);
                let z = span(from.z, d.z, base, base + f64::from(t.height));
                let (px, py) = (from.x - cx, from.y - cy);
                let (a, bq, cq) = (d.x * d.x + d.y * d.y, 2.0 * (px * d.x + py * d.y), px * px + py * py - r * r);
                let inside = if a < 1e-12 {
                    if cq <= 0.0 { (f64::MIN, f64::MAX) } else { continue }
                } else {
                    let disc = bq * bq - 4.0 * a * cq;
                    if disc < 0.0 {
                        continue;
                    }
                    ((-bq - disc.sqrt()) / (2.0 * a), (-bq + disc.sqrt()) / (2.0 * a))
                };
                if let Some(t) = first(range, z, inside) {
                    best = Some(best.map_or(t, |b: f64| b.min(t)));
                }
            }
        }
        best
    }

    /// The building nearest a world point within `r` m: one whose footprint holds the point, else the nearest
    /// centroid.
    pub fn nearest(&self, x: f64, y: f64, r: f64) -> Option<Found> {
        let mut best: Option<(f64, (i64, i64), usize)> = None;
        for (&ij, c) in &self.cells {
            if !c.near(x, y, r) {
                continue;
            }
            for (k, b) in c.cell.buildings.iter().enumerate() {
                let [cx, cy] = c.centroids[k];
                let d = if b.contains(x as f32, y as f32) { 0.0 } else { (cx - x).hypot(cy - y) };
                if d <= r && best.is_none_or(|(bd, _, _)| d < bd) {
                    best = Some((d, ij, k));
                }
            }
        }
        let (_, (i, j), k) = best?;
        let c = &self.cells[&(i, j)];
        let b = &c.cell.buildings[k];
        Some(Found {
            id: format!("{i}_{j}:{k}"),
            centroid: c.centroids[k],
            height: f64::from(b.height),
            area: area(&b.points),
            points: b.points.clone(),
        })
    }

    /// The outlines of the buildings whose centroid is in the box [x0, x1] × [y0, y1], as segment pairs (a, b, a, b…).
    pub fn outlines(&self, x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f32; 2]> {
        let mut out = vec![];
        for c in self.cells.values() {
            let b = c.bounds;
            if b[2] < x0 || b[0] > x1 || b[3] < y0 || b[1] > y1 {
                continue;
            }
            for (k, bl) in c.cell.buildings.iter().enumerate() {
                let [cx, cy] = c.centroids[k];
                if cx < x0 || cx > x1 || cy < y0 || cy > y1 {
                    continue;
                }
                let p = &bl.points;
                for i in 0..p.len() {
                    out.extend([p[i], p[(i + 1) % p.len()]]);
                }
            }
        }
        out
    }

    /// Whether no building's footprint lies within `r` m of a world point (inside one, or an edge that close).
    // ponytail: every building of the cells near the point, not the bucket index; fine for the editor's checks.
    pub fn clear(&self, x: f64, y: f64, r: f64) -> bool {
        let (xf, yf) = (x as f32, y as f32);
        self.cells.values().filter(|c| c.near(x, y, r)).all(|c| {
            c.cell.buildings.iter().all(|b| {
                let bx = footprint_box(b);
                x < bx[0] - r
                    || x > bx[2] + r
                    || y < bx[1] - r
                    || y > bx[3] + r
                    || (!b.contains(xf, yf) && edge_distance(&b.points, x, y) > r)
            })
        })
    }

    /// The buildings whose centroid is within `r` m of a world point.
    pub fn count_within(&self, x: f64, y: f64, r: f64) -> usize {
        self.cells
            .values()
            .filter(|c| c.near(x, y, r))
            .map(|c| c.centroids.iter().filter(|p| (p[0] - x).hypot(p[1] - y) <= r).count())
            .sum()
    }
}

/// The distance (m) from a point to a polygon's nearest edge.
fn edge_distance(p: &[[f32; 2]], x: f64, y: f64) -> f64 {
    (0..p.len())
        .map(|i| {
            let (a, b) = (p[i].map(f64::from), p[(i + 1) % p.len()].map(f64::from));
            let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
            let l2 = dx * dx + dy * dy;
            let t = if l2 > 0.0 { (((x - a[0]) * dx + (y - a[1]) * dy) / l2).clamp(0.0, 1.0) } else { 0.0 };
            (a[0] + t * dx - x).hypot(a[1] + t * dy - y)
        })
        .fold(f64::MAX, f64::min)
}

/// The lowest terrain under a footprint's corners: the building's base as drawn.
pub fn base(b: &Building, ground: &dyn Fn(Vec3) -> Option<f64>) -> Option<f64> {
    b.points.iter().try_fold(f64::MAX, |m, p| Some(m.min(ground(Vec3::new(p[0].into(), p[1].into(), 0.0))?)))
}

/// The t range [0, max] of the ray inside a box (2D), if it crosses it.
fn clip(p: Vec3, d: Vec3, max: f64, b: Box2) -> Option<(f64, f64)> {
    let (mut t0, mut t1) = (0.0f64, max);
    for (o, v, lo, hi) in [(p.x, d.x, b[0], b[2]), (p.y, d.y, b[1], b[3])] {
        if v.abs() < 1e-12 {
            if o < lo || o > hi {
                return None;
            }
        } else {
            let (a, c) = ((lo - o) / v, (hi - o) / v);
            t0 = t0.max(a.min(c));
            t1 = t1.min(a.max(c));
        }
    }
    (t0 <= t1).then_some((t0, t1))
}

/// Every bucket the ray's ground track crosses from t0 to t1 (a grid walk).
fn along(p: Vec3, d: Vec3, t0: f64, t1: f64, mut f: impl FnMut(Key)) {
    let (x, y) = (p.x + d.x * t0, p.y + d.y * t0);
    let mut key = bucket(x, y);
    let (end_i, end_j) = bucket(p.x + d.x * t1, p.y + d.y * t1);
    let axis = |o: f64, v: f64, k: i32| -> (i32, f64, f64) {
        if v.abs() < 1e-12 {
            return (0, f64::MAX, f64::MAX);
        }
        let step = if v > 0.0 { 1 } else { -1 };
        let edge = (f64::from(k) + if v > 0.0 { 1.0 } else { 0.0 }) * BUCKET;
        (step, (edge - o) / v, BUCKET / v.abs())
    };
    let (si, mut ti, di) = axis(x, d.x, key.0);
    let (sj, mut tj, dj) = axis(y, d.y, key.1);
    // ponytail: bounded walk; the clipped span holds at most |Δi| + |Δj| + 1 buckets.
    for _ in 0..=(end_i - key.0).abs() + (end_j - key.1).abs() {
        f(key);
        if ti < tj {
            key.0 += si;
            ti += di;
        } else {
            key.1 += sj;
            tj += dj;
        }
    }
}

/// The t spans where the ray's ground track is inside a footprint (the whole line when the ray is vertical over it).
fn inside_spans(b: &Building, p: Vec3, d: Vec3) -> Vec<(f64, f64)> {
    if d.x.abs() < 1e-12 && d.y.abs() < 1e-12 {
        return if b.contains(p.x as f32, p.y as f32) { vec![(f64::MIN, f64::MAX)] } else { Vec::new() };
    }
    let pts = &b.points;
    let mut ts: Vec<f64> = (0..pts.len())
        .filter_map(|k| {
            let (a, c) = (pts[k].map(f64::from), pts[(k + 1) % pts.len()].map(f64::from));
            let e = [c[0] - a[0], c[1] - a[1]];
            let den = d.x * e[1] - d.y * e[0];
            if den.abs() < 1e-12 {
                return None;
            }
            let (wx, wy) = (a[0] - p.x, a[1] - p.y);
            let t = (wx * e[1] - wy * e[0]) / den;
            let s = (wx * d.y - wy * d.x) / den;
            (0.0..1.0).contains(&s).then_some(t)
        })
        .collect();
    ts.sort_by(f64::total_cmp);
    ts.as_chunks::<2>().0.iter().map(|w| (w[0], w[1])).collect()
}

/// A cell's buildings as a Godot triangle mesh (X east, Y up, Z south, metres from `origin`, the world X/Y the mesh
/// is placed at): the arrays `ArrayMesh.add_surface_from_arrays` takes.
#[derive(Default, Debug)]
pub struct Mesh {
    pub vertex: Vec<[f32; 3]>,
    pub normal: Vec<[f32; 3]>,
    /// Walls: metres along the wall, metres up; roofs: world X and Godot Z over 32 m.
    pub uv: Vec<[f32; 2]>,
    /// x = the building's index in the cell, y = 0 wall / 1 roof.
    pub uv2: Vec<[f32; 2]>,
    /// rgb = the roof colour of the chosen look (walls lightened toward plaster), a = the wall material / 255.
    pub color: Vec<[f32; 4]>,
    pub index: Vec<i32>,
}

/// A near building's parapet above a flat roof (m).
pub const PARAPET: f32 = 0.8;
/// The plaster the walls' colour lightens toward.
const PLASTER: [f32; 3] = [0.86, 0.83, 0.76];
/// How far the walls' colour goes from the roof's toward the plaster.
const PLASTER_MIX: f32 = 0.6;
/// The roof UVs' tile (m).
const ROOF_TILE: f64 = 32.0;
const DOME_RINGS: usize = 4;
const DOME_SEGMENTS: usize = 12;

fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn cross(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}

fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn unit(a: [f32; 3]) -> [f32; 3] {
    let l = dot(a, a).sqrt().max(1e-9);
    a.map(|v| v / l)
}

/// The face normal Godot sees in front of a triangle: its front is clockwise.
pub fn front(v: [[f32; 3]; 3]) -> [f32; 3] {
    cross(sub(v[2], v[0]), sub(v[1], v[0]))
}

struct Builder {
    m: Mesh,
    origin: [f64; 2],
    building: f32,
    roof: [f32; 4],
    wall: [f32; 4],
}

impl Builder {
    /// World (X, Y) at height z → the mesh frame.
    fn at(&self, x: f64, y: f64, z: f64) -> [f32; 3] {
        [(x - self.origin[0]) as f32, z as f32, -(y - self.origin[1]) as f32]
    }

    /// A planar polygon of 3 or 4 vertices facing `n` (the winding is set to face it); `roof` picks the colour and
    /// UV2.y.
    fn face(&mut self, v: &[[f32; 3]], uv: &[[f32; 2]], n: [f32; 3], roof: bool) {
        let base = self.m.vertex.len() as i32;
        let n = unit(n);
        for (p, t) in v.iter().zip(uv) {
            self.m.vertex.push(*p);
            self.m.normal.push(n);
            self.m.uv.push(*t);
            self.m.uv2.push([self.building, f32::from(u8::from(roof))]);
            self.m.color.push(if roof { self.roof } else { self.wall });
        }
        let tris: &[[i32; 3]] = if v.len() == 4 { &[[0, 1, 2], [0, 2, 3]] } else { &[[0, 1, 2]] };
        for t in tris {
            let flip = dot(front([v[t[0] as usize], v[t[1] as usize], v[t[2] as usize]]), n) < 0.0;
            let t = if flip { [t[0], t[2], t[1]] } else { *t };
            self.m.index.extend(t.map(|k| base + k));
        }
    }

    fn roof_uv(&self, p: [f32; 3]) -> [f32; 2] {
        [
            ((f64::from(p[0]) + self.origin[0]) / ROOF_TILE) as f32,
            ((f64::from(p[2]) - self.origin[1]) / ROOF_TILE) as f32,
        ]
    }

    /// The walls from z0 to z1, facing out (`out` = 1) or in (−1); `run` = metres along the walls at each corner.
    fn walls(&mut self, pts: &[[f64; 2]], z0: f64, z1: f64, base: f64, out: f32) {
        let mut run = 0.0f32;
        for k in 0..pts.len() {
            let (a, b) = (pts[k], pts[(k + 1) % pts.len()]);
            let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
            let len = dx.hypot(dy) as f32;
            if len < 1e-3 {
                continue;
            }
            // Counter-clockwise footprint: the outside is on the right of each edge.
            let n = [dy as f32 * out, 0.0, dx as f32 * out];
            let (u0, u1, v0, v1) = (run, run + len, (z0 - base) as f32, (z1 - base) as f32);
            let v =
                [self.at(a[0], a[1], z0), self.at(b[0], b[1], z0), self.at(b[0], b[1], z1), self.at(a[0], a[1], z1)];
            self.face(&v, &[[u0, v0], [u1, v0], [u1, v1], [u0, v1]], n, false);
            run += len;
        }
    }

    fn flat_roof(&mut self, pts: &[[f64; 2]], z: f64) {
        let ring: Vec<[f32; 2]> = pts.iter().map(|p| [p[0] as f32, p[1] as f32]).collect();
        let tris = iaf_formats::emf::fill_triangles(&[ring], true);
        for t in tris.as_chunks::<3>().0 {
            let v: Vec<[f32; 3]> = t.iter().map(|p| self.at(p[0].into(), p[1].into(), z)).collect();
            let uv: Vec<[f32; 2]> = v.iter().map(|p| self.roof_uv(*p)).collect();
            self.face(&v, &uv, [0.0, 1.0, 0.0], true);
        }
    }

    /// Two slopes over a four-cornered footprint, the ridge along its longer sides; the gable ends close the walls.
    fn gabled(&mut self, p: &[[f64; 2]], base: f64, top: f64) {
        let len = |a: [f64; 2], b: [f64; 2]| (b[0] - a[0]).hypot(b[1] - a[1]);
        // Rotate so that edges 0-1 and 2-3 are the eaves.
        let p: Vec<[f64; 2]> =
            if len(p[0], p[1]) >= len(p[1], p[2]) { p.to_vec() } else { vec![p[1], p[2], p[3], p[0]] };
        let mid = |a: [f64; 2], b: [f64; 2]| [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0];
        let (r1, r0) = (mid(p[1], p[2]), mid(p[3], p[0]));
        // A 30° pitch, at most half the building.
        let width = len(p[1], p[2]).min(len(p[3], p[0]));
        let rise = (0.5 * width * (30f64).to_radians().tan()).min(0.5 * (top - base));
        let eave = top - rise;
        self.walls(&p, base, eave, base, 1.0);
        let c = self.at(r0[0] / 2.0 + r1[0] / 2.0, r0[1] / 2.0 + r1[1] / 2.0, eave);
        for (a, b, ra, rb) in [(p[0], p[1], r0, r1), (p[2], p[3], r1, r0)] {
            let v = [
                self.at(a[0], a[1], eave),
                self.at(b[0], b[1], eave),
                self.at(rb[0], rb[1], top),
                self.at(ra[0], ra[1], top),
            ];
            let mut n = unit(front([v[0], v[1], v[2]]));
            if n[1] < 0.0 {
                n = n.map(|x| -x);
            }
            let uv: Vec<[f32; 2]> = v.iter().map(|q| self.roof_uv(*q)).collect();
            self.face(&v, &uv, n, true);
        }
        for (a, b, r) in [(p[1], p[2], r1), (p[3], p[0], r0)] {
            let v = [self.at(a[0], a[1], eave), self.at(b[0], b[1], eave), self.at(r[0], r[1], top)];
            let out = sub(v[2], c);
            let w = len(a, b) as f32;
            let (e, t) = ((eave - base) as f32, (top - base) as f32);
            self.face(&v, &[[0.0, e], [w, e], [w / 2.0, t]], [out[0], 0.0, out[2]], false);
        }
    }

    /// A flat roof with a dome on the inscribed circle around the centroid.
    fn dome(&mut self, p: &[[f64; 2]], c: [f64; 2], base: f64, top: f64) {
        // The distance from the centroid to the nearest edge.
        let inner = (0..p.len())
            .map(|k| {
                let (a, b) = (p[k], p[(k + 1) % p.len()]);
                let (ex, ey) = (b[0] - a[0], b[1] - a[1]);
                let s = (((c[0] - a[0]) * ex + (c[1] - a[1]) * ey) / (ex * ex + ey * ey).max(1e-9)).clamp(0.0, 1.0);
                (a[0] + ex * s - c[0]).hypot(a[1] + ey * s - c[1])
            })
            .fold(f64::MAX, f64::min);
        let r = 0.9 * inner;
        let rise = r.min(0.5 * (top - base));
        let eave = top - rise;
        self.walls(p, base, eave, base, 1.0);
        self.flat_roof(p, eave);
        let centre = self.at(c[0], c[1], eave);
        let ring = |k: usize, s: usize| {
            let phi = k as f64 / DOME_RINGS as f64 * std::f64::consts::FRAC_PI_2;
            let th = s as f64 / DOME_SEGMENTS as f64 * std::f64::consts::TAU;
            (c[0] + r * phi.cos() * th.cos(), c[1] + r * phi.cos() * th.sin(), eave + rise * phi.sin())
        };
        for k in 0..DOME_RINGS {
            for s in 0..DOME_SEGMENTS {
                let q = [ring(k, s), ring(k, s + 1), ring(k + 1, s + 1), ring(k + 1, s)];
                let mut v: Vec<[f32; 3]> = q.iter().map(|&(x, y, z)| self.at(x, y, z)).collect();
                if k + 1 == DOME_RINGS {
                    v.pop(); // the top ring is one point
                }
                let mut n = unit(front([v[0], v[1], v[2]]));
                let mid = v.iter().fold([0.0; 3], |a, q| [a[0] + q[0], a[1] + q[1], a[2] + q[2]]);
                if dot(n, sub(mid.map(|x| x / v.len() as f32), centre)) < 0.0 {
                    n = n.map(|x| -x);
                }
                let uv: Vec<[f32; 2]> = v.iter().map(|q| self.roof_uv(*q)).collect();
                self.face(&v, &uv, n, true);
            }
        }
    }
}

/// A cell's buildings as one mesh: near = walls, a flat roof with a parapet (gabled / dome roofs as tagged), far = bare
/// prisms. Each stands on the lowest terrain under its corners; None while the terrain there is not loaded.
pub fn mesh(
    cell: &Cell,
    origin: [f64; 2],
    near: bool,
    modern: bool,
    ground: &dyn Fn(Vec3) -> Option<f64>,
) -> Option<Mesh> {
    Some(mesh_chunks(cell, origin, near, modern, ground, usize::MAX)?.pop().unwrap_or_default())
}

/// `mesh` split into meshes of at most about `max_vertices` each (whole buildings; the (y, x) order keeps each a strip
/// of the cell), so the main thread can upload a dense cell over several frames.
pub fn mesh_chunks(
    cell: &Cell,
    origin: [f64; 2],
    near: bool,
    modern: bool,
    ground: &dyn Fn(Vec3) -> Option<f64>,
    max_vertices: usize,
) -> Option<Vec<Mesh>> {
    let mut chunks = Vec::new();
    let mut bld = Builder { m: Mesh::default(), origin, building: 0.0, roof: [0.0; 4], wall: [0.0; 4] };
    for (k, b) in cell.buildings.iter().enumerate() {
        if b.points.len() < 3 {
            continue;
        }
        if bld.m.vertex.len() >= max_vertices {
            chunks.push(std::mem::take(&mut bld.m));
        }
        let base = base(b, ground)?;
        let top = base + f64::from(b.height);
        let mut pts: Vec<[f64; 2]> = b.points.iter().map(|p| p.map(f64::from)).collect();
        if signed_area(&b.points) < 0.0 {
            pts.reverse();
        }
        let rgb = if modern { b.roof_modern } else { b.roof_1998 }.map(|c| f32::from(c) / 255.0);
        bld.building = k as f32;
        let wall = [0, 1, 2].map(|c| rgb[c] + (PLASTER[c] - rgb[c]) * PLASTER_MIX);
        let material = f32::from(b.wall) / 255.0;
        bld.roof = [rgb[0], rgb[1], rgb[2], material];
        bld.wall = [wall[0], wall[1], wall[2], material];
        match (near, b.roof) {
            (true, Roof::Gabled) if pts.len() == 4 => bld.gabled(&pts, base, top),
            (true, Roof::Dome) => bld.dome(&pts, b.centroid().map(f64::from), base, top),
            (true, _) if b.height >= 3.0 * PARAPET => {
                let roof = top - f64::from(PARAPET);
                bld.walls(&pts, base, top, base, 1.0);
                bld.walls(&pts, roof, top, base, -1.0);
                bld.flat_roof(&pts, roof);
            }
            _ => {
                bld.walls(&pts, base, top, base, 1.0);
                bld.flat_roof(&pts, top);
            }
        }
    }
    if !bld.m.index.is_empty() || chunks.is_empty() {
        chunks.push(bld.m);
    }
    Some(chunks)
}

/// The trees of a cell as MultiMesh `TRANSFORM_3D` rows (12 floats each, Godot frame from `origin`), one list per
/// `TreeKind`: the model is 10 m tall, scaled to the tree's height, turned by a yaw seeded by its position, standing
/// on the terrain. None while the terrain there is not loaded.
pub fn tree_rows(cell: &Cell, origin: [f64; 2], ground: &dyn Fn(Vec3) -> Option<f64>) -> Option<[Vec<f32>; 4]> {
    let mut rows: [Vec<f32>; 4] = Default::default();
    for t in &cell.trees {
        let z = ground(Vec3::new(t.x.into(), t.y.into(), 0.0))? as f32;
        let s = t.height / 10.0;
        let seed = t.x.to_bits() ^ t.y.to_bits().rotate_left(16);
        let yaw = (seed.wrapping_mul(2_654_435_761) as f32 / u32::MAX as f32) * std::f32::consts::TAU;
        let (sn, cs) = yaw.sin_cos();
        let (ox, oz) = ((f64::from(t.x) - origin[0]) as f32, -(f64::from(t.y) - origin[1]) as f32);
        rows[t.kind as usize].extend([s * cs, 0.0, s * sn, ox, 0.0, s, 0.0, z, -s * sn, 0.0, s * cs, oz]);
    }
    Some(rows)
}

struct Reader<'a> {
    data: &'a [u8],
    at: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let s = self.data.get(self.at..self.at + n)?;
        self.at += n;
        Some(s)
    }
    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }
    fn u16(&mut self) -> Option<u16> {
        Some(u16::from_le_bytes(self.take(2)?.try_into().ok()?))
    }
    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }
    fn f32(&mut self) -> Option<f32> {
        Some(f32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cell_round_trip_and_contains() {
        let square = Building {
            points: vec![[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]],
            roof: Roof::Gabled,
            wall: 2,
            height: 9.5,
            roof_1998: [1, 2, 3],
            roof_modern: [4, 5, 6],
            source: SOURCE_MS,
            levels: 3,
        };
        let mut cell = Cell {
            buildings: vec![Building { points: vec![[0.0, 50.0], [5.0, 50.0], [5.0, 55.0]], ..square.clone() }, square],
            trees: vec![Tree { x: 1.0, y: 2.0, height: 7.0, kind: TreeKind::Palm }],
        };
        cell.sort();
        assert_eq!(cell.buildings[0].centroid(), [5.0, 5.0]);
        assert_eq!(Cell::decode(&cell.encode()), Some(cell.clone()));
        assert!(cell.buildings[0].contains(5.0, 5.0) && !cell.buildings[0].contains(11.0, 5.0));
        assert_eq!(Cell::decode(b"IAFS\x09\0\0\0"), None);
    }

    fn house(x: f32, y: f32, w: f32, h: f32, roof: Roof) -> Building {
        Building {
            points: vec![[x, y], [x + w, y], [x + w, y + w / 2.0], [x, y + w / 2.0]],
            roof,
            wall: 1,
            height: h,
            roof_1998: [200, 100, 50],
            roof_modern: [10, 20, 30],
            source: SOURCE_OSM,
            levels: 0,
        }
    }

    /// Two flat buildings at (0..20, 0..10) 12 m and (40..60, 0..10) 6 m, a 10 m tree at (100, 100); flat ground 5 m.
    fn town() -> Scenery {
        let mut s = Scenery::default();
        let cell = Cell {
            buildings: vec![house(0.0, 0.0, 20.0, 12.0, Roof::Flat), house(40.0, 0.0, 20.0, 6.0, Roof::Flat)],
            trees: vec![Tree { x: 100.0, y: 100.0, height: 10.0, kind: TreeKind::Pine }],
        };
        s.insert(3, 4, cell);
        s
    }

    const FLAT: &dyn Fn(Vec3) -> Option<f64> = &|_| Some(5.0);

    #[test]
    fn roof_level_on_a_slope() {
        // Ground rising 0.2 m per m east: the 12 m house (x 0..20) stands on its lowest corner (x = 0, 0 m), so its
        // roof is at 12 m everywhere, 8 m above the ground at x = 20.
        let slope: &dyn Fn(Vec3) -> Option<f64> = &|p| Some(0.2 * p.x);
        let s = town();
        assert!((s.top(1.0, 5.0, slope) - 11.8).abs() < 1e-4);
        assert!((s.top(19.0, 5.0, slope) - 8.2).abs() < 1e-4);
    }

    #[test]
    fn top_reads_roofs_crowns_and_damage() {
        let mut s = town();
        assert_eq!(s.top(10.0, 5.0, FLAT), 12.0);
        assert_eq!(s.top(30.0, 5.0, FLAT), 0.0);
        assert_eq!(s.top(102.5, 100.0, FLAT), 10.0, "inside the 3 m crown");
        assert_eq!(s.top(104.0, 100.0, FLAT), 0.0);
        s.set_damaged("3_4:0", true);
        assert!(s.is_damaged("3_4:0") && !s.is_damaged("3_4:1"));
        assert_eq!(s.top(10.0, 5.0, FLAT), 3.0);
        assert_eq!(s.damage_index(3, 4), vec![1, 0]);
        s.remove(3, 4);
        assert_eq!(s.top(102.5, 100.0, FLAT), 0.0);
        s.insert(3, 4, town().cell(3, 4).unwrap().clone());
        assert!(s.is_damaged("3_4:0"), "damage outlives the cell's unload");
    }

    #[test]
    fn ray_hits_the_first_wall_roof_or_crown() {
        let s = town();
        // East along y = 5 at 10 m (5 m above the ground): the first building's west wall at x = 0.
        let t = s.ray(Vec3::new(-50.0, 5.0, 10.0), Vec3::new(1.0, 0.0, 0.0), 1000.0, FLAT).unwrap();
        assert!((t - 50.0).abs() < 1e-6, "{t}");
        // At 18 m it clears both roofs (5 m base + 12 m).
        assert!(s.ray(Vec3::new(-50.0, 5.0, 18.0), Vec3::new(1.0, 0.0, 0.0), 1000.0, FLAT).is_none());
        // Straight down onto the roof: 30 m − 17 m.
        let t = s.ray(Vec3::new(10.0, 5.0, 30.0), Vec3::new(0.0, 0.0, -1.0), 100.0, FLAT).unwrap();
        assert!((t - 13.0).abs() < 1e-6, "{t}");
        // Diagonal through the tree's crown: radius 3 m around (100, 100).
        let t = s.ray(Vec3::new(60.0, 60.0, 8.0), Vec3::new(1.0, 1.0, 0.0), 1000.0, FLAT).unwrap();
        assert!((t - (40.0 * 2f64.sqrt() - 3.0)).abs() < 1e-6, "{t}");
        assert!(s.ray(Vec3::new(-50.0, 5.0, 10.0), Vec3::new(1.0, 0.0, 0.0), 40.0, FLAT).is_none(), "beyond max");
        assert!(s.ray(Vec3::new(-50.0, 5.0, 10.0), Vec3::new(1.0, 0.0, 0.0), 1000.0, &|_| None).is_none());
    }

    #[test]
    fn nearest_and_count() {
        let s = town();
        let f = s.nearest(45.0, 5.0, 30.0).unwrap();
        assert_eq!((f.id.as_str(), f.centroid, f.height, f.area), ("3_4:1", [50.0, 5.0], 6.0, 200.0));
        assert_eq!(s.nearest(10.0, 300.0, 30.0), None);
        assert_eq!(s.count_within(30.0, 5.0, 25.0), 2);
        assert_eq!(s.count_within(30.0, 5.0, 15.0), 0);
        assert_eq!(s.building("3_4:1").map(|b| b.height), Some(6.0));
        assert_eq!(s.building("9_9:0"), None);
        assert_eq!(f.points.len(), 4);
        // The 20 x 10 house at (40, 0): its four edges; the centroid box leaves it out.
        assert_eq!(s.outlines(45.0, 0.0, 55.0, 10.0).len(), 8);
        assert!(s.outlines(200.0, 200.0, 300.0, 300.0).is_empty());
        assert!(!s.clear(45.0, 5.0, 0.0), "inside");
        assert!(!s.clear(65.0, 5.0, 6.0) && s.clear(65.0, 5.0, 4.0), "5 m east of its wall");
    }

    /// Every triangle faces its stored normal (Godot's clockwise front), and walls face away from the footprint.
    fn check_faces(m: &Mesh, centre: [f32; 3]) {
        for t in m.index.as_chunks::<3>().0 {
            let v = [0, 1, 2].map(|k| m.vertex[t[k] as usize]);
            let n = m.normal[t[0] as usize];
            assert!(dot(front(v), n) > 0.0, "winding {v:?} vs {n:?}");
            if n[1].abs() < 1e-6 {
                let out = sub(v[0], centre);
                assert!(dot([out[0], 0.0, out[2]], n) > 0.0 || is_inner(m, t), "wall faces in");
            }
        }
    }

    /// A parapet's inner face: stands above the roof.
    fn is_inner(m: &Mesh, t: &[i32]) -> bool {
        t.iter().all(|&k| m.vertex[k as usize][1] >= 5.0 + 12.0 - PARAPET - 1e-3)
    }

    #[test]
    fn mesh_extrudes_walls_roofs_and_parapets() {
        let one = |roof, near| {
            let cell = Cell { buildings: vec![house(0.0, 0.0, 20.0, 12.0, roof)], trees: vec![] };
            mesh(&cell, [0.0, 0.0], near, false, FLAT).unwrap()
        };
        let centre = [10.0, 0.0, -5.0];
        // Far: 4 walls (8 triangles) + a 2-triangle roof.
        let far = one(Roof::Flat, false);
        assert_eq!(far.index.len() / 3, 10);
        check_faces(&far, centre);
        let top = far.vertex.iter().map(|v| v[1]).fold(f32::MIN, f32::max);
        assert_eq!(top, 17.0, "base 5 m + 12 m");
        // Near flat: + 4 inner parapet faces; the roof 0.8 m down.
        let near = one(Roof::Flat, true);
        assert_eq!(near.index.len() / 3, 18);
        check_faces(&near, centre);
        let roof_y: Vec<f32> = near
            .index
            .iter()
            .filter(|&&k| near.uv2[k as usize][1] == 1.0)
            .map(|&k| near.vertex[k as usize][1])
            .collect();
        assert!(roof_y.iter().all(|&y| (y - (17.0 - PARAPET)).abs() < 1e-5));
        // Gabled: 4 walls + 2 slopes + 2 gable triangles; the ridge along the 20 m side at 17 m.
        let gab = one(Roof::Gabled, true);
        assert_eq!(gab.index.len() / 3, 8 + 4 + 2);
        check_faces(&gab, centre);
        assert!(gab.vertex.iter().any(|v| v[1] == 17.0 && (v[2] + 5.0).abs() < 1e-5));
        // Dome: walls + flat roof + rings.
        let dome = one(Roof::Dome, true);
        assert_eq!(dome.index.len() / 3, 8 + 2 + DOME_SEGMENTS * (2 * DOME_RINGS - 1));
        check_faces(&dome, centre);
        // Colours: rgb the look's roof, a the wall material; walls lighter toward plaster.
        assert_eq!(far.color[0][3], 1.0 / 255.0);
        let (wall, roof) = (far.color[0], *far.color.last().unwrap());
        assert_eq!(roof[..3], [200.0 / 255.0, 100.0 / 255.0, 50.0 / 255.0]);
        assert!(wall[2] > roof[2]);
        assert!(
            mesh(
                &Cell { buildings: vec![house(0.0, 0.0, 20.0, 12.0, Roof::Flat)], trees: vec![] },
                [0.0, 0.0],
                false,
                false,
                &|_| None
            )
            .is_none()
        );
    }

    #[test]
    fn tree_rows_scale_and_stand_on_the_ground() {
        let s = town();
        let rows = tree_rows(s.cell(3, 4).unwrap(), [90.0, 110.0], FLAT).unwrap();
        let r = &rows[TreeKind::Pine as usize];
        assert_eq!(r.len(), 12);
        assert_eq!((r[3], r[5], r[7], r[11]), (10.0, 1.0, 5.0, 10.0));
        assert!((r[0] * r[0] + r[2] * r[2] - 1.0).abs() < 1e-5, "a pure yaw at scale 1");
    }
}
