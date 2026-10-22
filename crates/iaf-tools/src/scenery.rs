//! `iaf-scenery`'s work (docs/scenery.md §1): the buildings and trees over the Survey of Israel 2 m layer, one cell
//! file per level-1 node of `mapi2015` (`iaf_avionics::scenery`), from inputs downloaded at setup into
//! `assets/source/scenery` (`thirdparty::SCENERY`, pinned by SHA-256):
//! - OpenStreetMap (Geofabrik's `israel-and-palestine` extract of 2026-01-01): buildings with their tags, forests,
//!   orchards and settlements, single trees and tree rows;
//! - Microsoft's Global ML Building Footprints where OpenStreetMap has no building;
//! - JRC GHS-BUILT-H R2023A (average net building height, 100 m) for buildings without a height tag;
//! - Meta / WRI's global 1 m canopy height for the trees.
//!
//! Everything is warped from WGS84 into the game frame with the georeference (`georef`), as the imagery is, so the
//! roofs stand on the photo's buildings. Nothing stands where the original has something: the sea, the airbases and
//! the kept target insets (`imagery::Rules`), the missions' units and routes (`airbases::mission_units`), and
//! World scale Real's old and new base sites (`iaf_flight::base_move`). The same pinned inputs give the same bytes on
//! every install (`manifest.json` `release`).

use std::collections::{BTreeMap, BTreeSet};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_avionics::scenery::{Building, Cell, Roof, SOURCE_MS, SOURCE_OSM, Tree, TreeKind};
use image::RgbImage;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

use crate::georef::{Georef, UNITS_TO_METRES};
use crate::imagery::{Cache, Rules, Theatre};
use crate::progress::{Progress, check, par_map, par_map_all, utf8};
use crate::thirdparty::{self, Download, SCENERY};
use crate::{airbases, log};

/// The generator's version: part of the release, so a change to the rules below makes new ids.
pub const GENERATOR: u32 = 3;
/// A level-1 node's side in terrain units (1024 pixels of 2 units).
const NODE_UNITS: f64 = 2048.0;
const PIXEL_UNITS: f64 = 2.0;
/// The photo test: blocks of this many pixels (40 m) whose mean difference to the 1998 rendition is above `PHOTO_DIFF`
/// (0..255 per channel) show the photo.
const PHOTO_BLOCK: usize = 16;
const PHOTO_DIFF: f32 = 6.0;
/// Clearances (m): around a static object (stationary model, SAM, radar, bridge) beyond its radius; around a vehicle
/// and its route for buildings; the lane along a vehicle's route for trees (half-width).
pub const STATIC_CLEAR_M: f64 = 60.0;
pub const VEHICLE_BUILDING_M: f64 = 40.0;
pub const ROUTE_TREE_M: f64 = 6.0;
/// A building's height per level (m).
pub const LEVEL_M: f32 = 3.0;
/// Trees: the canopy height that counts as a tree (m), the canopy grid (degrees, ≈ 10 m), the spacing of a tree row
/// (m), the default heights (m).
const CANOPY_MIN_M: u8 = 4;
const CANOPY_STEP: f64 = 0.0001;
const ROW_STEP_M: f64 = 6.0;
const TREE_DEFAULT_M: f32 = 8.0;
const ROW_DEFAULT_M: f32 = 10.0;
/// The tree-kind grid (m) and how far a settlement reaches around a building (cells).
const KIND_CELL_M: f64 = 10.0;
const SETTLEMENT_CELLS: i64 = 3;
/// Jerusalem's centre (lon, lat) and the radius (km) inside which walls are stone (docs/scenery.md §1.3).
const JERUSALEM: [f64; 2] = [35.2137, 31.7683];
const JERUSALEM_KM: f64 = 10.0;

/// Terrain units → engine metres (X east, Y north).
fn engine(tx: f64, ty: f64) -> [f64; 2] {
    [tx * UNITS_TO_METRES - 166850.0, 1043780.0 - ty * UNITS_TO_METRES]
}

/// The engine-metre rect [x0, y0, x1, y1] (y0 south) of level-1 node (i, j).
pub fn node_rect(i: u32, j: u32) -> [f64; 4] {
    let a = engine(i as f64 * NODE_UNITS, (j + 1) as f64 * NODE_UNITS);
    let b = engine((i + 1) as f64 * NODE_UNITS, j as f64 * NODE_UNITS);
    [a[0], a[1], b[0], b[1]]
}

/// The level-1 node holding an engine point.
fn node_of(p: [f64; 2]) -> (u32, u32) {
    let [tx, ty] = airbases::units(p[0], p[1]);
    ((tx / NODE_UNITS).floor().max(0.0) as u32, (ty / NODE_UNITS).floor().max(0.0) as u32)
}

// ---------------------------------------------------------------------------------------------------------------------
// Geometry

fn signed_area(p: &[[f64; 2]]) -> f64 {
    let n = p.len();
    (0..n).map(|i| p[i][0] * p[(i + 1) % n][1] - p[(i + 1) % n][0] * p[i][1]).sum::<f64>() * 0.5
}

fn centroid(p: &[[f64; 2]]) -> [f64; 2] {
    let n = p.len().max(1) as f64;
    let s = p.iter().fold([0.0, 0.0], |s, q| [s[0] + q[0], s[1] + q[1]]);
    [s[0] / n, s[1] / n]
}

/// Even-odd point in polygon.
fn contains(p: &[[f64; 2]], q: [f64; 2]) -> bool {
    let mut inside = false;
    let mut j = p.len().wrapping_sub(1);
    for i in 0..p.len() {
        let ([xi, yi], [xj, yj]) = (p[i], p[j]);
        if (yi > q[1]) != (yj > q[1]) && q[0] < (xj - xi) * (q[1] - yi) / (yj - yi) + xi {
            inside = !inside;
        }
        j = i;
    }
    inside
}

fn bbox(p: &[[f64; 2]]) -> [f64; 4] {
    p.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, q| {
        [b[0].min(q[0]), b[1].min(q[1]), b[2].max(q[0]), b[3].max(q[1])]
    })
}

fn dist_seg(p: [f64; 2], a: [f64; 2], b: [f64; 2]) -> f64 {
    let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
    let l2 = dx * dx + dy * dy;
    let t = if l2 > 0.0 { (((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2).clamp(0.0, 1.0) } else { 0.0 };
    (p[0] - a[0] - t * dx).hypot(p[1] - a[1] - t * dy)
}

fn cross(o: [f64; 2], a: [f64; 2], b: [f64; 2]) -> f64 {
    (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
}

fn segments_cross(a: [f64; 2], b: [f64; 2], c: [f64; 2], d: [f64; 2]) -> bool {
    let (d1, d2) = (cross(c, d, a), cross(c, d, b));
    let (d3, d4) = (cross(a, b, c), cross(a, b, d));
    (d1 > 0.0) != (d2 > 0.0) && (d3 > 0.0) != (d4 > 0.0)
}

/// A ring cleaned for the cell file: no closing point, no points closer than 0.2 m, counter-clockwise; None when
/// fewer than three points are left.
fn clean_ring(ring: impl Iterator<Item = [f64; 2]>) -> Option<Vec<[f64; 2]>> {
    let mut p: Vec<[f64; 2]> = Vec::new();
    for q in ring {
        if p.last().is_none_or(|l| (l[0] - q[0]).hypot(l[1] - q[1]) >= 0.2) {
            p.push(q);
        }
    }
    while p.len() > 1 && (p[0][0] - p[p.len() - 1][0]).hypot(p[0][1] - p[p.len() - 1][1]) < 0.2 {
        p.pop();
    }
    if p.len() < 3 || p.len() > u16::MAX as usize {
        return None;
    }
    if signed_area(&p) < 0.0 {
        p.reverse();
    }
    Some(p)
}

/// A small integer hash (splitmix64): the seed of every choice that looks random, so it is the same on every run.
fn hash(v: &[u64]) -> u64 {
    let mut h = 0x9e37_79b9_7f4a_7c15u64;
    for &x in v {
        h = (h ^ x).wrapping_add(0x9e37_79b9_7f4a_7c15);
        h = (h ^ (h >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        h = (h ^ (h >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        h ^= h >> 31;
    }
    h
}

/// `hash` as 0..1.
fn unit(v: &[u64]) -> f64 {
    (hash(v) >> 11) as f64 / (1u64 << 53) as f64
}

/// Indices of items by grid cell, over a rect.
struct Buckets {
    x0: f64,
    y0: f64,
    cell: f64,
    w: usize,
    h: usize,
    v: Vec<Vec<u32>>,
}

impl Buckets {
    fn new(r: [f64; 4], cell: f64) -> Self {
        let w = ((r[2] - r[0]) / cell).ceil().max(1.0) as usize;
        let h = ((r[3] - r[1]) / cell).ceil().max(1.0) as usize;
        Buckets { x0: r[0], y0: r[1], cell, w, h, v: vec![Vec::new(); w * h] }
    }
    fn range(&self, b: [f64; 4]) -> Option<[usize; 4]> {
        let c = |v: f64, o: f64, n: usize| ((v - o) / self.cell).floor().clamp(-1.0, n as f64) as i64;
        let (i0, j0) = (c(b[0], self.x0, self.w).max(0), c(b[1], self.y0, self.h).max(0));
        let (i1, j1) =
            (c(b[2], self.x0, self.w).min(self.w as i64 - 1), c(b[3], self.y0, self.h).min(self.h as i64 - 1));
        (i0 <= i1 && j0 <= j1).then_some([i0 as usize, j0 as usize, i1 as usize, j1 as usize])
    }
    fn insert(&mut self, b: [f64; 4], k: u32) {
        if let Some([i0, j0, i1, j1]) = self.range(b) {
            for j in j0..=j1 {
                for i in i0..=i1 {
                    self.v[j * self.w + i].push(k);
                }
            }
        }
    }
    fn near(&self, p: [f64; 2], r: f64) -> impl Iterator<Item = u32> + '_ {
        let rg = self.range([p[0] - r, p[1] - r, p[0] + r, p[1] + r]);
        let mut out: Vec<u32> = Vec::new();
        if let Some([i0, j0, i1, j1]) = rg {
            for j in j0..=j1 {
                for i in i0..=i1 {
                    out.extend(&self.v[j * self.w + i]);
                }
            }
        }
        out.sort_unstable();
        out.dedup();
        out.into_iter()
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// Inputs as the cells see them (engine metres)

/// A building footprint from a source, its attributes decided from the tags (`osm_building`, `ms_building`).
#[derive(Clone, Debug, PartialEq)]
pub struct Footprint {
    /// Engine metres, counter-clockwise, not closed.
    pub pts: Vec<[f64; 2]>,
    /// Longitude, latitude of its centre (the height raster's lookup).
    pub geo: [f64; 2],
    /// From the tags: `height`, else `building:levels` × LEVEL_M.
    pub height: Option<f32>,
    pub levels: u8,
    pub roof: Roof,
    pub wall: u8,
    pub source: u8,
}

/// A land-use area deciding the kind of the trees in it (`AREA_*`), engine metres.
#[derive(Clone, Debug, PartialEq)]
pub struct Area {
    pub kind: u8,
    pub pts: Vec<[f64; 2]>,
}
pub const AREA_SETTLEMENT: u8 = 1;
pub const AREA_ORCHARD: u8 = 2;
pub const AREA_FOREST: u8 = 3;

/// A mapped tree (OpenStreetMap `natural=tree`, or a point of a `natural=tree_row`).
#[derive(Clone, Debug, PartialEq)]
pub struct MappedTree {
    pub p: [f64; 2],
    pub kind: Option<TreeKind>,
    pub height: f32,
}

/// The canopy height around a node: WGS84 grid, `lon0` / `lat1` the north-west corner, `step` degrees, metres.
#[derive(Clone, Debug, Default)]
pub struct Canopy {
    pub lon0: f64,
    pub lat1: f64,
    pub step: f64,
    pub w: usize,
    pub h: usize,
    pub v: Vec<u8>,
}

/// Where nothing may stand around an original unit: the segment a–b (a point when a = b) grown by `building` metres
/// for buildings and by `tree` metres for trees.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Clear {
    pub a: [f64; 2],
    pub b: [f64; 2],
    pub building: f64,
    pub tree: f64,
}

impl Clear {
    fn bbox(&self) -> [f64; 4] {
        let r = self.building.max(self.tree);
        [
            self.a[0].min(self.b[0]) - r,
            self.a[1].min(self.b[1]) - r,
            self.a[0].max(self.b[0]) + r,
            self.a[1].max(self.b[1]) + r,
        ]
    }
    fn hits_tree(&self, p: [f64; 2]) -> bool {
        dist_seg(p, self.a, self.b) < self.tree
    }
    fn hits_building(&self, pts: &[[f64; 2]]) -> bool {
        let r = self.building;
        if r <= 0.0 {
            return false;
        }
        let n = pts.len();
        pts.iter().any(|&p| dist_seg(p, self.a, self.b) < r)
            || contains(pts, self.a)
            || contains(pts, self.b)
            || (0..n).any(|i| {
                let (p, q) = (pts[i], pts[(i + 1) % n]);
                dist_seg(self.a, p, q) < r || dist_seg(self.b, p, q) < r || segments_cross(self.a, self.b, p, q)
            })
    }
}

/// One node's inputs.
#[derive(Clone, Debug, Default)]
pub struct NodeIn {
    pub key: (u32, u32),
    pub osm: Vec<Footprint>,
    pub ms: Vec<Footprint>,
    pub areas: Vec<Area>,
    pub trees: Vec<MappedTree>,
    pub canopy: Option<Canopy>,
}

/// A footprint's roof colours: (1998 look, modern look).
pub type RoofFn<'a> = dyn Fn(&[[f64; 2]]) -> ([u8; 3], [u8; 3]) + Sync + 'a;

/// What a node asks of the world.
pub struct Env<'a> {
    /// True where scenery may stand (engine metres): the photo shows, `Rules::open`, off World scale Real's sites.
    pub open: &'a (dyn Fn([f64; 2]) -> bool + Sync),
    /// The units' clearances near the node.
    pub clears: &'a [Clear],
    /// GHS-BUILT-H's average net building height at (lon, lat), None without buildings there.
    pub built_height: &'a (dyn Fn([f64; 2]) -> Option<f32> + Sync),
    /// The roof colours (1998 look, modern look) of a footprint.
    pub roof: &'a RoofFn<'a>,
    /// (lon, lat) → engine metres.
    pub warp: &'a (dyn Fn(f64, f64) -> [f64; 2] + Sync),
}

/// The height of a building without a height tag or a GHS-BUILT-H value, by its footprint area (m², inferred: a shed,
/// a house, a block of flats, a hall).
pub fn default_height(area: f64) -> f32 {
    match area {
        a if a < 40.0 => 3.0,
        a if a < 150.0 => 6.0,
        a if a < 600.0 => 9.0,
        _ => 12.0,
    }
}

fn building_ok(f: &Footprint, env: &Env) -> bool {
    let a = signed_area(&f.pts);
    (6.0..=200_000.0).contains(&a)
        && f.pts.iter().chain([&centroid(&f.pts)]).all(|&p| (env.open)(p))
        && !env.clears.iter().any(|c| c.hits_building(&f.pts))
}

/// One node's cell: OpenStreetMap's buildings, then Microsoft's whose centre is in no OpenStreetMap footprint; then the
/// mapped trees and one tree per canopy cell of `CANOPY_MIN_M` or more; nothing where `env` says no.
pub fn build_cell(n: &NodeIn, env: &Env) -> Cell {
    let rect = node_rect(n.key.0, n.key.1);
    let seed = [n.key.0 as u64, n.key.1 as u64];
    let mut osm_b = Buckets::new(rect, 32.0);
    for (k, f) in n.osm.iter().enumerate() {
        osm_b.insert(bbox(&f.pts), k as u32);
    }
    let in_osm = |p: [f64; 2]| osm_b.near(p, 0.0).any(|k| contains(&n.osm[k as usize].pts, p));
    let chosen: Vec<&Footprint> =
        n.osm.iter().chain(n.ms.iter().filter(|f| !in_osm(centroid(&f.pts)))).filter(|f| building_ok(f, env)).collect();
    let mut cell = Cell::default();
    let mut kept = Buckets::new(rect, 32.0);
    for f in &chosen {
        let height = f
            .height
            .or_else(|| (env.built_height)(f.geo))
            .unwrap_or_else(|| default_height(signed_area(&f.pts)))
            .clamp(2.5, 400.0);
        let (roof_1998, roof_modern) = (env.roof)(&f.pts);
        kept.insert(bbox(&f.pts), cell.buildings.len() as u32);
        cell.buildings.push(Building {
            points: f.pts.iter().map(|p| [p[0] as f32, p[1] as f32]).collect(),
            roof: f.roof,
            wall: f.wall,
            height,
            roof_1998,
            roof_modern,
            source: f.source,
            levels: f.levels,
        });
    }
    let on_building = |p: [f64; 2]| {
        kept.near(p, 0.0).any(|k| {
            let b = &chosen[k as usize];
            contains(&b.pts, p)
        })
    };
    // Tree kinds: a 10 m grid of the areas (forest over orchard over settlement), settlements also around buildings.
    let kinds = KindGrid::new(rect, &n.areas, chosen.iter().map(|f| centroid(&f.pts)));
    let tree_ok = |p: [f64; 2]| {
        p[0] >= rect[0]
            && p[0] < rect[2]
            && p[1] >= rect[1]
            && p[1] < rect[3]
            && (env.open)(p)
            && !on_building(p)
            && !env.clears.iter().any(|c| c.hits_tree(p))
    };
    let mut mapped = Buckets::new(rect, 16.0);
    for (k, t) in n.trees.iter().enumerate() {
        mapped.insert([t.p[0], t.p[1], t.p[0], t.p[1]], k as u32);
        if tree_ok(t.p) {
            let kind = t.kind.unwrap_or_else(|| kinds.kind(t.p, &[&seed[..], &[k as u64, 1]].concat()));
            cell.trees.push(Tree { x: t.p[0] as f32, y: t.p[1] as f32, height: t.height, kind });
        }
    }
    if let Some(c) = &n.canopy {
        for r in 0..c.h {
            for col in 0..c.w {
                let v = c.v[r * c.w + col];
                if v < CANOPY_MIN_M {
                    continue;
                }
                let s = [seed[0], seed[1], r as u64, col as u64];
                let (jx, jy) = (unit(&[s[0], s[1], s[2], s[3], 2]) - 0.5, unit(&[s[0], s[1], s[2], s[3], 3]) - 0.5);
                let lon = c.lon0 + (col as f64 + 0.5 + 0.7 * jx) * c.step;
                let lat = c.lat1 - (r as f64 + 0.5 + 0.7 * jy) * c.step;
                let p = (env.warp)(lon, lat);
                if !tree_ok(p)
                    || mapped.near(p, ROW_STEP_M).any(|k| {
                        let q = n.trees[k as usize].p;
                        (q[0] - p[0]).hypot(q[1] - p[1]) < ROW_STEP_M
                    })
                {
                    continue;
                }
                let kind = kinds.kind(p, &s);
                cell.trees.push(Tree { x: p[0] as f32, y: p[1] as f32, height: v.min(40) as f32, kind });
            }
        }
    }
    cell.sort();
    cell
}

/// The tree-kind grid of a node (`AREA_*` per 10 m cell, 0 = none).
struct KindGrid {
    x0: f64,
    y0: f64,
    w: usize,
    h: usize,
    v: Vec<u8>,
}

impl KindGrid {
    fn new(rect: [f64; 4], areas: &[Area], buildings: impl Iterator<Item = [f64; 2]>) -> Self {
        let w = ((rect[2] - rect[0]) / KIND_CELL_M).ceil() as usize;
        let h = ((rect[3] - rect[1]) / KIND_CELL_M).ceil() as usize;
        let mut g = KindGrid { x0: rect[0], y0: rect[1], w, h, v: vec![0; w * h] };
        for c in buildings {
            let (i, j) = g.cell(c);
            for dj in -SETTLEMENT_CELLS..=SETTLEMENT_CELLS {
                for di in -SETTLEMENT_CELLS..=SETTLEMENT_CELLS {
                    let (a, b) = (i + di, j + dj);
                    if a >= 0 && b >= 0 && (a as usize) < w && (b as usize) < h {
                        g.v[b as usize * w + a as usize] = AREA_SETTLEMENT;
                    }
                }
            }
        }
        // Scanline fill: per row, the cells whose centre lies between a pair of edge crossings.
        for a in areas {
            let b = bbox(&a.pts);
            let (_, j0) = g.cell([b[0], b[1]]);
            let (_, j1) = g.cell([b[2], b[3]]);
            let n = a.pts.len();
            for j in j0.max(0)..=j1.min(h as i64 - 1) {
                let y = g.y0 + (j as f64 + 0.5) * KIND_CELL_M;
                let mut xs: Vec<f64> = (0..n)
                    .filter_map(|e| {
                        let (p, q) = (a.pts[e], a.pts[(e + 1) % n]);
                        ((p[1] > y) != (q[1] > y)).then(|| p[0] + (y - p[1]) / (q[1] - p[1]) * (q[0] - p[0]))
                    })
                    .collect();
                xs.sort_by(f64::total_cmp);
                for pair in xs.as_chunks::<2>().0 {
                    let c = |x: f64| ((x - g.x0) / KIND_CELL_M - 0.5).ceil() as i64;
                    for i in c(pair[0]).max(0)..c(pair[1]).min(w as i64) {
                        let k = j as usize * w + i as usize;
                        g.v[k] = g.v[k].max(a.kind);
                    }
                }
            }
        }
        g
    }
    fn cell(&self, p: [f64; 2]) -> (i64, i64) {
        (((p[0] - self.x0) / KIND_CELL_M).floor() as i64, ((p[1] - self.y0) / KIND_CELL_M).floor() as i64)
    }
    /// The kind of a tree at `p`: pine in a forest, broadleaf (olive-like) in an orchard or field, in a settlement a
    /// palm one time in four, else broadleaf.
    fn kind(&self, p: [f64; 2], seed: &[u64]) -> TreeKind {
        let (i, j) = self.cell(p);
        let a = if i >= 0 && j >= 0 && (i as usize) < self.w && (j as usize) < self.h {
            self.v[j as usize * self.w + i as usize]
        } else {
            0
        };
        match a {
            AREA_FOREST => TreeKind::Pine,
            AREA_SETTLEMENT if hash(seed).is_multiple_of(4) => TreeKind::Palm,
            _ => TreeKind::Broadleaf,
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// Tags

/// GDAL's OSM `other_tags` (`"k"=>"v","k2"=>"v2"`) as pairs.
pub fn other_tags(s: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let mut parts = Vec::new();
    let mut cur = String::new();
    let mut quoted = false;
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' if quoted => cur.extend(chars.next()),
            '"' => {
                if quoted {
                    parts.push(std::mem::take(&mut cur));
                }
                quoted = !quoted;
            }
            _ if quoted => cur.push(c),
            _ => {}
        }
    }
    for kv in parts.chunks(2) {
        if let [k, v] = kv {
            out.insert(k.clone(), v.clone());
        }
    }
    out
}

/// A number at the start of a tag value ("12", "12.5 m"); None for anything else (feet, ranges).
fn tag_number(v: Option<&String>) -> Option<f32> {
    let v = v?.trim();
    let end = v.find(|c: char| !(c.is_ascii_digit() || c == '.')).unwrap_or(v.len());
    let rest = v[end..].trim();
    if !(rest.is_empty() || rest == "m") {
        return None;
    }
    v[..end].parse::<f32>().ok().filter(|x| x.is_finite() && *x > 0.0)
}

fn in_jerusalem(geo: [f64; 2]) -> bool {
    let dx = (geo[0] - JERUSALEM[0]) * 111.32 * JERUSALEM[1].to_radians().cos();
    let dy = (geo[1] - JERUSALEM[1]) * 110.57;
    dx.hypot(dy) < JERUSALEM_KM
}

/// An OpenStreetMap building's height, levels, roof and wall from its tags (`building` = the building tag's value).
pub fn osm_building(
    building: &str,
    tags: &BTreeMap<String, String>,
    area: f64,
    geo: [f64; 2],
) -> (Option<f32>, u8, Roof, u8) {
    let levels = tag_number(tags.get("building:levels")).map_or(0, |l| l.round().clamp(0.0, 200.0) as u8);
    let height = tag_number(tags.get("height")).or((levels > 0).then_some(levels as f32 * LEVEL_M));
    let roof = match tags.get("roof:shape").map(String::as_str) {
        Some("gabled" | "hipped" | "pyramidal" | "half-hipped" | "gambrel" | "mansard" | "saltbox" | "side_hipped") => {
            Roof::Gabled
        }
        Some("dome" | "onion") => Roof::Dome,
        _ => Roof::Flat,
    };
    let metal = [
        "industrial",
        "warehouse",
        "shed",
        "hangar",
        "farm_auxiliary",
        "barn",
        "greenhouse",
        "garage",
        "garages",
        "roof",
        "service",
        "cowshed",
        "stable",
        "manufacture",
        "storage_tank",
    ];
    let stone = ["church", "mosque", "synagogue", "cathedral", "chapel", "temple", "religious", "castle", "ruins"];
    let concrete = [
        "apartments",
        "office",
        "commercial",
        "retail",
        "hospital",
        "school",
        "university",
        "public",
        "hotel",
        "civic",
        "government",
        "college",
        "train_station",
        "transportation",
    ];
    let wall = match tags.get("building:material").map(String::as_str) {
        Some("stone" | "sandstone" | "limestone" | "brick") => 1,
        Some("concrete" | "reinforced_concrete" | "cement_block") => 2,
        Some("metal" | "steel" | "aluminium") => 3,
        Some("plaster") => 0,
        _ if metal.contains(&building) => 3,
        _ if stone.contains(&building) || tags.contains_key("historic") || in_jerusalem(geo) => 1,
        _ if concrete.contains(&building) || levels >= 5 || area >= 2000.0 => 2,
        _ => 0,
    };
    (height, levels, roof, wall)
}

/// A Microsoft footprint's wall: stone in Jerusalem, corrugated metal for a large single footprint (sheds and
/// halls, inferred), else plaster.
pub fn ms_wall(area: f64, geo: [f64; 2]) -> u8 {
    if in_jerusalem(geo) {
        1
    } else if area >= 1500.0 {
        3
    } else {
        0
    }
}

/// A mapped tree's kind from its tags (genus, species, taxon, leaf type), None when they say nothing.
pub fn tagged_kind(tags: &BTreeMap<String, String>) -> Option<TreeKind> {
    let t: String = tags
        .iter()
        .filter(|(k, _)| {
            ["genus", "species", "taxon", "leaf_type", "species:en", "name:en"].iter().any(|p| k.starts_with(p))
        })
        .map(|(_, v)| v.to_lowercase() + " ")
        .collect();
    if ["phoenix", "washingtonia", "palm", "arecaceae"].iter().any(|w| t.contains(w)) {
        Some(TreeKind::Palm)
    } else if ["cupressus", "cypress"].iter().any(|w| t.contains(w)) {
        Some(TreeKind::Cypress)
    } else if ["pinus", "pine", "needleleaved"].iter().any(|w| t.contains(w)) {
        Some(TreeKind::Pine)
    } else {
        None
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// Original units → clearances

/// The models of the objects database (`objects/objects.json`): per bdb and type id, the model's path under `objects/`.
pub struct Models {
    dir: PathBuf,
    map: Value,
    /// Per bdb (lower-case): entity type (object `0x1e`) → its Present record (`0x53c`), the key of `map`.
    presents: BTreeMap<String, BTreeMap<i64, i64>>,
}

impl Models {
    /// `objects`: `converted/objects`; `missions`: `converted/missions` (the `.bdb.json` object lists).
    pub fn load(objects: &Path, missions: &Path) -> Self {
        let read = |p: PathBuf| -> Value {
            std::fs::read(p).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or(Value::Null)
        };
        let map = read(objects.join("objects.json"));
        let presents = map
            .as_object()
            .into_iter()
            .flat_map(|m| m.keys())
            .map(|bdb| {
                let v = read(missions.join(format!("{bdb}.json")));
                let ids = v["objects"]["items"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(|o| Some((o["0x1e"].as_i64()?, o["0x53c"].as_i64()?)))
                    .collect();
                (bdb.to_lowercase(), ids)
            })
            .collect();
        Models { dir: objects.to_path_buf(), map, presents }
    }

    /// The model path of type `kind` in `bdb` ("stationary/ofice/ofice1_h.gltf"), lower-case.
    pub fn path(&self, bdb: &str, kind: i64) -> Option<String> {
        let db = self.map.as_object()?.iter().find(|(k, _)| k.eq_ignore_ascii_case(bdb))?.1;
        let present = self.presents.get(&bdb.to_lowercase())?.get(&kind)?;
        Some(db[present.to_string()].as_str()?.to_lowercase())
    }

    /// The model's horizontal radius (m) from its glTF bounds; 10 m when unknown.
    pub fn radius(&self, path: &str) -> f64 {
        let g: Option<Value> = std::fs::read(self.dir.join(path)).ok().and_then(|b| serde_json::from_slice(&b).ok());
        let r = g
            .iter()
            .flat_map(|g| g["accessors"].as_array().cloned().unwrap_or_default())
            .filter(|a| a["type"] == "VEC3")
            .filter_map(|a| {
                let v = |k: &str, i: usize| a[k][i].as_f64().map(f64::abs);
                Some(v("min", 0)?.max(v("max", 0)?).hypot(v("min", 2)?.max(v("max", 2)?)))
            })
            .fold(0.0, f64::max);
        if r > 0.0 { r } else { 10.0 }
    }
}

/// True for a model that never moves: stationary models, SAM sites and radars (by the model folder), parked planes.
pub fn is_static(path: &str) -> bool {
    let mut it = path.split('/');
    match (it.next(), it.next()) {
        (Some("groundforces"), Some(m)) => {
            ["sa2", "sa3", "sa5", "sa6", "hkrad", "hwk", "p14", "p35", "p40", "scd"].iter().any(|p| m.starts_with(p))
        }
        (Some("seaforces"), _) => false,
        _ => true,
    }
}

/// The clearances of the missions' units on the ground (ground forces and stationary models anywhere, the rest by
/// `airbases::on_ground`): a static unit clears its radius +
/// STATIC_CLEAR_M for everything; a vehicle clears VEHICLE_BUILDING_M around itself and its routes for buildings, its
/// radius for trees, and ROUTE_TREE_M along its routes for trees.
pub fn clears(units: &[airbases::Unit], lineups: &[[f64; 3]], models: &Models) -> Vec<Clear> {
    let mut radius: BTreeMap<String, f64> = BTreeMap::new();
    let mut out = Vec::new();
    for u in units {
        let p = [u.pos[0], u.pos[1]];
        let path = models.path(&u.bdb, u.kind).unwrap_or_default();
        // Ground forces and stationary models stand on the ground wherever they are (a radar on a hill is far above
        // the nearest base); the rest (planes, markers) only when at a base's height (parked).
        let ground_model = path.starts_with("groundforces/") || path.starts_with("stationary/");
        if !ground_model && !airbases::on_ground(lineups, &u.pos) {
            continue;
        }
        let r = *radius.entry(path.clone()).or_insert_with(|| models.radius(&path));
        if is_static(&path) {
            out.push(Clear { a: p, b: p, building: r + STATIC_CLEAR_M, tree: r + STATIC_CLEAR_M });
            continue;
        }
        out.push(Clear { a: p, b: p, building: VEHICLE_BUILDING_M.max(r), tree: r });
        for route in &u.routes {
            for w in route.windows(2) {
                out.push(Clear { a: w[0], b: w[1], building: VEHICLE_BUILDING_M, tree: ROUTE_TREE_M });
            }
        }
    }
    out.sort_by(|a, b| a.a.partial_cmp(&b.a).unwrap().then(a.b.partial_cmp(&b.b).unwrap()));
    out.dedup();
    out
}

/// World scale Real's base moves (docs/world-scale.md §3.3) from iaf.ibx and airbases.json, as the game builds them
/// (without the masks and elevations, which do not move a site).
pub fn base_moves(install: &Path, terrain: &Path) -> iaf_flight::base_move::BaseMoves {
    use iaf_flight::airbase::Airbase;
    use iaf_flight::base_move::{BaseMoves, GameBase};
    let ibx = Airbase::load_all(&std::fs::read(install.join("iaf.ibx")).unwrap_or_default());
    let j: Value = std::fs::read(terrain.join("airbases.json"))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or(Value::Null);
    let pt = |v: &Value| [v[0].as_f64().unwrap_or(0.0), v[1].as_f64().unwrap_or(0.0)];
    let empty = Vec::new();
    let jbases = j["bases"].as_array().unwrap_or(&empty);
    let games: Vec<GameBase> = ibx
        .iter()
        .filter_map(|b| {
            let jb = jbases.iter().find(|x| x["name"] == b.name.as_str())?;
            let rws = jb["runways"].as_array()?;
            let rw = rws.iter().map(|r| [pt(&r["ends"][0]), pt(&r["ends"][1])]).collect();
            let widths = rws.iter().map(|r| r["width"].as_f64().unwrap_or(0.0)).collect();
            Some(GameBase { widths, ..GameBase::new(b, rw) })
        })
        .collect();
    BaseMoves::new(&games)
}

// ---------------------------------------------------------------------------------------------------------------------
// Rasters and the warp

/// (lon, lat) → engine metres, bilinear on a grid of the georeference's exact inverse (the warp is smooth: a 0.005°
/// grid is far below a centimetre off).
pub struct Warp {
    lon0: f64,
    lat0: f64,
    step: f64,
    w: usize,
    h: usize,
    xy: Vec<[f64; 2]>,
}

impl Warp {
    pub fn new(g: &Georef, geo: [f64; 4], step: f64) -> Self {
        let w = ((geo[2] - geo[0]) / step).ceil() as usize + 2;
        let h = ((geo[3] - geo[1]) / step).ceil() as usize + 2;
        let rows: Vec<usize> = (0..h).collect();
        let xy = par_map_all(&rows, |&r| {
            (0..w).map(|c| g.geo_to_engine(geo[0] + c as f64 * step, geo[1] + r as f64 * step)).collect::<Vec<_>>()
        })
        .concat();
        Warp { lon0: geo[0], lat0: geo[1], step, w, h, xy }
    }

    pub fn at(&self, lon: f64, lat: f64) -> [f64; 2] {
        let x = ((lon - self.lon0) / self.step).clamp(0.0, (self.w - 1) as f64 - 1e-9);
        let y = ((lat - self.lat0) / self.step).clamp(0.0, (self.h - 1) as f64 - 1e-9);
        let (c, r) = (x as usize, y as usize);
        let (fx, fy) = (x - c as f64, y - r as f64);
        let p = |c: usize, r: usize| self.xy[r * self.w + c];
        let (a, b, d, e) = (p(c, r), p(c + 1, r), p(c, r + 1), p(c + 1, r + 1));
        [0, 1].map(|k| (a[k] * (1.0 - fx) + b[k] * fx) * (1.0 - fy) + (d[k] * (1.0 - fx) + e[k] * fx) * fy)
    }
}

/// A single-band raster warped by gdalwarp into WGS84 over `geo` [lon0, lat0, lon1, lat1] at `w` × `h`, read back
/// raw (ENVI, little-endian).
fn gdal_warp(srcs: &[String], geo: [f64; 4], w: usize, h: usize, resampling: &str, out: &Path) -> Result<Vec<u8>> {
    let mut cmd = Command::new("gdalwarp");
    cmd.args(["-q", "-overwrite", "-t_srs", "EPSG:4326", "-r", resampling, "-of", "ENVI", "-te"])
        .args(geo.map(|v| format!("{v:.7}")))
        .arg("-ts")
        .args([w.to_string(), h.to_string()])
        .args(srcs)
        .arg(out);
    run(cmd)?;
    let raw = std::fs::read(out).with_context(|| format!("{}", out.display()))?;
    let aux = PathBuf::from(format!("{}.aux.xml", out.display()));
    for p in [out.to_path_buf(), out.with_extension("hdr"), aux] {
        let _ = std::fs::remove_file(p);
    }
    Ok(raw)
}

/// Runs a GDAL / gzip command: an error with its stderr (without GDAL's plugin load noise) when it fails.
fn run(mut cmd: Command) -> Result<()> {
    let name = format!("{:?}", cmd.get_program());
    let o = cmd.stdin(Stdio::null()).output().with_context(|| format!("running {name}"))?;
    if !o.status.success() {
        let err: String = String::from_utf8_lossy(&o.stderr)
            .lines()
            .filter(|l| !l.contains("cannot open shared object file"))
            .collect::<Vec<_>>()
            .join("\n");
        bail!("{name} failed ({}): {err}", o.status);
    }
    Ok(())
}

/// The GHS-BUILT-H average net building height over the coverage (WGS84, 0.001°).
struct Heights {
    geo: [f64; 4],
    w: usize,
    h: usize,
    v: Vec<f32>,
}

impl Heights {
    const STEP: f64 = 0.001;
    fn at(&self, g: [f64; 2]) -> Option<f32> {
        let c = ((g[0] - self.geo[0]) / Self::STEP).floor();
        let r = ((self.geo[3] - g[1]) / Self::STEP).floor();
        if c < 0.0 || r < 0.0 || c >= self.w as f64 || r >= self.h as f64 {
            return None;
        }
        Some(self.v[r as usize * self.w + c as usize]).filter(|v| *v > 0.5 && *v < 250.0)
    }
}

// ---------------------------------------------------------------------------------------------------------------------
// Reading the sources

/// Outer rings of a GeoJSON Polygon / MultiPolygon geometry.
fn outer_rings(g: &Value) -> Vec<Vec<[f64; 2]>> {
    let ring = |r: &Value| -> Vec<[f64; 2]> {
        r.as_array().into_iter().flatten().filter_map(|p| Some([p[0].as_f64()?, p[1].as_f64()?])).collect()
    };
    match g["type"].as_str() {
        Some("Polygon") => vec![ring(&g["coordinates"][0])],
        Some("MultiPolygon") => g["coordinates"].as_array().into_iter().flatten().map(|p| ring(&p[0])).collect(),
        _ => vec![],
    }
}

/// The nodes' inputs being gathered.
struct Gather<'a> {
    warp: &'a Warp,
    nodes: BTreeMap<(u32, u32), NodeIn>,
    geo: [f64; 4],
}

impl Gather<'_> {
    fn in_geo(&self, p: [f64; 2]) -> bool {
        p[0] >= self.geo[0] && p[0] <= self.geo[2] && p[1] >= self.geo[1] && p[1] <= self.geo[3]
    }

    /// A ring (lon, lat) in engine metres, cleaned, with its geo centre; None outside the coverage.
    fn ring(&self, r: &[[f64; 2]]) -> Option<(Vec<[f64; 2]>, [f64; 2])> {
        if !r.first().is_some_and(|p| self.in_geo(*p)) {
            return None;
        }
        let pts = clean_ring(r.iter().map(|p| self.warp.at(p[0], p[1])))?;
        Some((pts, centroid(r)))
    }

    fn building(&mut self, f: Footprint) {
        if let Some(n) = self.nodes.get_mut(&node_of(centroid(&f.pts))) {
            if f.source == SOURCE_OSM { n.osm.push(f) } else { n.ms.push(f) }
        }
    }

    fn area(&mut self, a: Area) {
        let b = bbox(&a.pts);
        let (i0, j1) = node_of([b[0], b[1]]);
        let (i1, j0) = node_of([b[2], b[3]]);
        for j in j0..=j1 {
            for i in i0..=i1 {
                if let Some(n) = self.nodes.get_mut(&(i, j)) {
                    n.areas.push(a.clone());
                }
            }
        }
    }

    fn tree(&mut self, t: MappedTree) {
        if let Some(n) = self.nodes.get_mut(&node_of(t.p)) {
            n.trees.push(t);
        }
    }
}

/// Lines of a GeoJSONSeq file as JSON values.
fn geojsonl(p: &Path) -> Result<impl Iterator<Item = Value>> {
    let f = std::fs::File::open(p).with_context(|| format!("{}", p.display()))?;
    Ok(BufReader::new(f).lines().map_while(std::result::Result::ok).filter_map(|l| serde_json::from_str(&l).ok()))
}

/// OpenStreetMap's layers cut to the box (ogr2ogr → GeoJSONSeq in `work`).
fn osm_extract(pbf: &Path, geo: [f64; 4], work: &Path, pr: &dyn Progress) -> Result<[PathBuf; 3]> {
    let tag = |k: &str, v: &str| format!("other_tags LIKE '%\"{k}\"=>\"{v}\"%'");
    let jobs = [
        (
            "multipolygons",
            "building IS NOT NULL OR landuse IN ('forest','orchard','farmland','vineyard','plant_nursery','residential') OR natural = 'wood'",
            "building,landuse,natural,other_tags",
        ),
        ("points", &*tag("natural", "tree"), "other_tags"),
        ("lines", &*tag("natural", "tree_row"), "other_tags"),
    ];
    // The extract is kept for the next run with the same box (named by it).
    let tag = hash(&geo.map(f64::to_bits)) as u32;
    let mut out = Vec::new();
    for (layer, filter, fields) in jobs {
        let p = work.join(format!("osm-{layer}-{tag:08x}.geojsonl"));
        if !p.is_file() {
            for e in std::fs::read_dir(work)?.flatten() {
                if e.file_name().to_string_lossy().starts_with(&format!("osm-{layer}-")) {
                    std::fs::remove_file(e.path())?;
                }
            }
            log!(pr, "OpenStreetMap: extracting {layer}");
            let part = p.with_extension("part");
            let _ = std::fs::remove_file(&part);
            let mut cmd = Command::new("ogr2ogr");
            cmd.env("CPL_TMPDIR", work)
                .args(["-f", "GeoJSONSeq", "-spat"])
                .args(geo.map(|v| v.to_string()))
                .args(["-where", filter, "-select", fields])
                .arg(&part)
                .arg(pbf)
                .arg(layer);
            run(cmd)?;
            std::fs::rename(&part, &p)?;
        }
        out.push(p);
    }
    Ok([out[0].clone(), out[1].clone(), out[2].clone()])
}

fn read_osm(files: &[PathBuf; 3], g: &mut Gather, cancel: &AtomicBool) -> Result<()> {
    for (k, v) in geojsonl(&files[0])?.enumerate() {
        if k % 100_000 == 0 {
            check(cancel)?;
        }
        let pr = &v["properties"];
        let tags = other_tags(pr["other_tags"].as_str().unwrap_or(""));
        let s = |k: &str| pr[k].as_str().unwrap_or("");
        let building = s("building");
        let area_kind = match (s("landuse"), s("natural")) {
            ("forest", _) | (_, "wood") => Some(AREA_FOREST),
            ("orchard" | "farmland" | "vineyard" | "plant_nursery", _) => Some(AREA_ORCHARD),
            ("residential", _) => Some(AREA_SETTLEMENT),
            _ => None,
        };
        for r in outer_rings(&v["geometry"]) {
            let Some((pts, geo)) = g.ring(&r) else { continue };
            if !building.is_empty() && building != "no" {
                let (height, levels, roof, wall) = osm_building(building, &tags, signed_area(&pts), geo);
                g.building(Footprint { pts, geo, height, levels, roof, wall, source: SOURCE_OSM });
            } else if let Some(kind) = area_kind {
                g.area(Area { kind, pts });
            }
        }
    }
    for v in geojsonl(&files[1])? {
        let tags = other_tags(v["properties"]["other_tags"].as_str().unwrap_or(""));
        let c = &v["geometry"]["coordinates"];
        let (Some(lon), Some(lat)) = (c[0].as_f64(), c[1].as_f64()) else { continue };
        if g.in_geo([lon, lat]) {
            let height = tag_number(tags.get("height")).unwrap_or(TREE_DEFAULT_M).min(40.0);
            g.tree(MappedTree { p: g.warp.at(lon, lat), kind: tagged_kind(&tags), height });
        }
    }
    for v in geojsonl(&files[2])? {
        let tags = other_tags(v["properties"]["other_tags"].as_str().unwrap_or(""));
        let kind = tagged_kind(&tags).unwrap_or(TreeKind::Cypress);
        let height = tag_number(tags.get("height")).unwrap_or(ROW_DEFAULT_M).min(40.0);
        let line: Vec<[f64; 2]> = v["geometry"]["coordinates"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|p| Some([p[0].as_f64()?, p[1].as_f64()?]))
            .filter(|p| g.in_geo(*p))
            .map(|p| g.warp.at(p[0], p[1]))
            .collect();
        for p in row_points(&line) {
            g.tree(MappedTree { p, kind: Some(kind), height });
        }
    }
    Ok(())
}

/// Points every ROW_STEP_M along a line, from its start.
fn row_points(line: &[[f64; 2]]) -> Vec<[f64; 2]> {
    let mut out = Vec::new();
    let mut carry = 0.0;
    for w in line.windows(2) {
        let (a, b) = (w[0], w[1]);
        let len = (b[0] - a[0]).hypot(b[1] - a[1]);
        let mut t = carry;
        while t <= len {
            let f = if len > 0.0 { t / len } else { 0.0 };
            out.push([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]);
            t += ROW_STEP_M;
        }
        carry = t - len;
    }
    out
}

/// Microsoft's footprints of one `.csv.gz` (GeoJSON lines, gzip) inside the coverage.
fn read_ms(file: &Path, g: &Gather) -> Result<Vec<Footprint>> {
    let mut c = Command::new("gzip").arg("-dc").arg(file).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
    let out = c.stdout.take().context("gzip stdout")?;
    let mut v = Vec::new();
    for line in BufReader::new(out).lines() {
        let line = line?;
        // A cheap look at the first point before parsing the line.
        let first = line.split("[[[").nth(1).and_then(|s| {
            let mut it = s.split([',', ']']);
            Some([it.next()?.trim().parse::<f64>().ok()?, it.next()?.trim().parse::<f64>().ok()?])
        });
        if !first.is_some_and(|p| g.in_geo(p)) {
            continue;
        }
        let Ok(f) = serde_json::from_str::<Value>(&line) else { continue };
        for r in outer_rings(&f["geometry"]) {
            if let Some((pts, geo)) = g.ring(&r) {
                let wall = ms_wall(signed_area(&pts), geo);
                v.push(Footprint { pts, geo, height: None, levels: 0, roof: Roof::Flat, wall, source: SOURCE_MS });
            }
        }
    }
    if !c.wait()?.success() {
        bail!("{}: gzip failed", file.display());
    }
    Ok(v)
}

// ---------------------------------------------------------------------------------------------------------------------
// The run

/// What `build` is asked to do.
pub struct Run {
    /// The assets folder.
    pub assets: PathBuf,
    /// Only the nodes whose centre is within `km` of the engine point (x, y): a quick look at one place.
    pub near: Option<([f64; 2], f64)>,
}

/// What `build` made.
#[derive(Debug, Default)]
pub struct Summary {
    pub cells: usize,
    pub buildings: usize,
    pub osm: usize,
    pub trees: usize,
    pub bytes: u64,
    pub up_to_date: bool,
}

/// The level-1 nodes of the `mapi2015` layer (`c_<i>_<j>.jpg`), sorted.
pub fn coverage(imagery: &Path) -> Result<Vec<(u32, u32)>> {
    let dir = imagery.join("mapi2015/L1");
    let mut out = Vec::new();
    for e in std::fs::read_dir(&dir).with_context(|| format!("{}: the Survey 2 m layer is needed", dir.display()))? {
        let name = e?.file_name().to_string_lossy().to_string();
        if let Some((i, j)) =
            name.strip_prefix("c_").and_then(|s| s.strip_suffix(".jpg")).and_then(|s| s.split_once('_'))
            && let (Ok(i), Ok(j)) = (i.parse(), j.parse())
        {
            out.push((i, j));
        }
    }
    out.sort();
    Ok(out)
}

/// The WGS84 box [lon0, lat0, lon1, lat1] of a node (its corners and edge midpoints through the warp), padded.
fn node_geo(g: &Georef, k: (u32, u32), pad: f64) -> [f64; 4] {
    let r = node_rect(k.0, k.1);
    let pts: Vec<[f64; 2]> = [0.0, 0.5, 1.0]
        .iter()
        .flat_map(|&fx| [0.0, 0.5, 1.0].map(|fy| g.engine_to_geo(r[0] + fx * (r[2] - r[0]), r[1] + fy * (r[3] - r[1]))))
        .collect();
    let b = bbox(&pts);
    [b[0] - pad, b[1] - pad, b[2] + pad, b[3] + pad]
}

/// Bing / Microsoft quadkey of (lon, lat) at `zoom` (the tiles of Microsoft's footprints and Meta's canopy).
pub fn quadkey(lon: f64, lat: f64, zoom: u32) -> String {
    let n = (1u64 << zoom) as f64;
    let x = ((lon + 180.0) / 360.0 * n).floor() as u64;
    let s = lat.to_radians().sin();
    let y = ((0.5 - ((1.0 + s) / (1.0 - s)).ln() / (4.0 * std::f64::consts::PI)) * n).floor() as u64;
    (0..zoom).rev().map(|b| char::from(b'0' + (((x >> b) & 1) + 2 * ((y >> b) & 1)) as u8)).collect()
}

/// The zoom-9 quadkeys the coverage touches (to keep `thirdparty::SCENERY` complete).
pub fn quadkeys(assets: &Path) -> Result<BTreeSet<String>> {
    let g = Georef::load()?;
    let mut out = BTreeSet::new();
    for k in coverage(&assets.join("converted/imagery"))? {
        let b = node_geo(&g, k, 0.0);
        for p in [[b[0], b[1]], [b[2], b[1]], [b[0], b[3]], [b[2], b[3]]] {
            out.insert(quadkey(p[0], p[1], 9));
        }
    }
    Ok(out)
}

/// The release: the pinned inputs' checksums and the generator's version, hashed (hex SHA-256).
pub fn release() -> String {
    let mut h = Sha256::new();
    for d in SCENERY {
        h.update(d.sha256.as_bytes());
        h.update(b"\n");
    }
    h.update(format!("generator {GENERATOR}\n").as_bytes());
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// What the cells are made from besides the release: the nodes, the converted missions and airbases, the area.
fn made_from(r: &Run, keys: &[(u32, u32)]) -> String {
    let a = &r.assets;
    let mut h = Sha256::new();
    h.update(release().as_bytes());
    for k in keys {
        for l in ["mapi2015", "mapi2015_modern"] {
            let p = a.join(format!("converted/imagery/{l}/L1/c_{}_{}.jpg", k.0, k.1));
            h.update(format!("{k:?} {}\n", std::fs::metadata(&p).map_or(0, |m| m.len())).as_bytes());
        }
    }
    for s in ["missions.stamp", "terrain/airbases.json.stamp", "terrain/theatre.stamp", "objects.stamp"] {
        h.update(std::fs::read(a.join("converted").join(s)).unwrap_or_default());
    }
    h.update(format!("{:?}", r.near).as_bytes());
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// The downloaded inputs of the list, or an error naming the first missing one.
fn input(dir: &Path, d: &Download) -> Result<PathBuf> {
    if !thirdparty::file_done(dir, d) {
        bail!("{} is not downloaded (setup step scenery-fetch)", d.file);
    }
    Ok(dir.join(d.file))
}

/// The scenery cells (module doc) into `assets/converted/scenery`: up to date when its manifest says it was made from
/// the same inputs.
pub fn build(r: &Run, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Summary> {
    let started = std::time::Instant::now();
    let a = &r.assets;
    let src = a.join("source/scenery");
    let out = a.join("converted/scenery");
    let work = out.join(".work");
    let geo_f = Georef::load()?;
    let mut keys = coverage(&a.join("converted/imagery"))?;
    if let Some((c, km)) = r.near {
        keys.retain(|k| {
            let n = node_rect(k.0, k.1);
            ((n[0] + n[2]) * 0.5 - c[0]).hypot((n[1] + n[3]) * 0.5 - c[1]) <= km * 1000.0
        });
    }
    let made = made_from(r, &keys);
    let manifest_p = out.join("manifest.json");
    if let Ok(m) = std::fs::read(&manifest_p).map(|b| serde_json::from_slice::<Value>(&b).unwrap_or(Value::Null))
        && m["made_from"] == made.as_str()
    {
        return Ok(Summary { up_to_date: true, ..Summary::default() });
    }
    let files: Vec<PathBuf> = SCENERY.iter().map(|d| input(&src, d)).collect::<Result<_>>()?;
    let pick = |pre: &str| -> Vec<PathBuf> {
        files.iter().filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with(pre))).cloned().collect()
    };
    std::fs::create_dir_all(&work)?;
    log!(pr, "scenery: {} nodes of the Survey 2 m layer", keys.len());

    // The warp over the coverage.
    let node_geos: Vec<[f64; 4]> = par_map_all(&keys, |&k| node_geo(&geo_f, k, 0.0005));
    let geo = node_geos.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, g| {
        [b[0].min(g[0]), b[1].min(g[1]), b[2].max(g[2]), b[3].max(g[3])]
    });
    let geo = [geo[0] - 0.01, geo[1] - 0.01, geo[2] + 0.01, geo[3] + 0.01];
    let warp = Warp::new(&geo_f, geo, 0.005);
    pr.fraction(0.02);

    // The sources, gathered per node.
    let mut g =
        Gather { warp: &warp, nodes: keys.iter().map(|&k| (k, NodeIn { key: k, ..NodeIn::default() })).collect(), geo };
    let osm = osm_extract(&pick("israel-and-palestine")[0], geo, &work, pr)?;
    check(cancel)?;
    read_osm(&osm, &mut g, cancel)?;
    pr.fraction(0.15);
    log!(pr, "Microsoft footprints: {} files", pick("ms-").len());
    let ms = par_map(&pick("ms-"), cancel, |f| read_ms(f, &g))?;
    for f in ms.into_iter().flatten() {
        g.building(f);
    }
    pr.fraction(0.25);
    let ghs: Vec<String> = pick("GHS_BUILT_H")
        .iter()
        .map(|z| {
            let name = z.file_name().unwrap_or_default().to_string_lossy().replace(".zip", ".tif");
            Ok(format!("/vsizip/{}/{name}", utf8(z)?))
        })
        .collect::<Result<_>>()?;
    let (hw, hh) =
        (((geo[2] - geo[0]) / Heights::STEP).ceil() as usize, ((geo[3] - geo[1]) / Heights::STEP).ceil() as usize);
    let hgeo = [geo[0], geo[3] - hh as f64 * Heights::STEP, geo[0] + hw as f64 * Heights::STEP, geo[3]];
    let raw = gdal_warp(&ghs, hgeo, hw, hh, "near", &work.join("ghs.bin"))?;
    let heights =
        Heights { geo: hgeo, w: hw, h: hh, v: raw.as_chunks::<4>().0.iter().map(|b| f32::from_le_bytes(*b)).collect() };
    let chm = chm_vrt(&pick("chm-"), &work, pr, cancel)?;
    pr.fraction(0.35);

    // The places nothing may stand.
    let install = a.join("install");
    let theatre = Theatre::load(&a.join("converted/terrain/theatre"))?;
    let rules = Rules::load(&install, false, &theatre)?;
    let units = airbases::mission_units(&a.join("converted/missions"));
    let lineups = airbases::ibx_lineups(&std::fs::read(install.join("iaf.ibx")).unwrap_or_default());
    let all_clears =
        clears(&units, &lineups, &Models::load(&a.join("converted/objects"), &a.join("converted/missions")));
    let moves = base_moves(&install, &a.join("converted/terrain"));
    let ring = iaf_flight::base_move::RING;
    log!(
        pr,
        "{} clearances around the missions' units, {} World scale Real sites",
        all_clears.len(),
        moves.bases.len()
    );

    // Per node.
    let l1 = out.join("L1");
    if l1.is_dir() {
        std::fs::remove_dir_all(&l1)?;
    }
    std::fs::create_dir_all(&l1)?;
    let done = std::sync::atomic::AtomicUsize::new(0);
    let items: Vec<(usize, &NodeIn)> = g.nodes.values().enumerate().collect();
    // Runs of neighbouring nodes per worker: they share the 1998 rendition's ancestors (`Cache`).
    let chunks: Vec<&[(usize, &NodeIn)]> =
        items.chunks(items.len().div_ceil(crate::progress::threads() * 4).max(1)).collect();
    let results = par_map(&chunks, cancel, |chunk| {
        let mut cache = Cache::default();
        let mut v = Vec::new();
        for &(idx, n) in chunk.iter() {
            check(cancel)?;
            let (i, j) = n.key;
            let img =
                |l: &str| image::open(a.join(format!("converted/imagery/{l}/L1/c_{i}_{j}.jpg"))).map(|m| m.to_rgb8());
            let (old, modern) = (img("mapi2015")?, img("mapi2015_modern")?);
            let orig = theatre.rendition((1, i, j), &mut cache)?;
            let photo = photo_mask(&old, orig.as_deref());
            let rect = node_rect(i, j);
            let near: Vec<Clear> = all_clears
                .iter()
                .filter(|c| {
                    let b = c.bbox();
                    b[0] < rect[2] + 50.0 && b[2] > rect[0] - 50.0 && b[1] < rect[3] + 50.0 && b[3] > rect[1] - 50.0
                })
                .copied()
                .collect();
            let px = |p: [f64; 2]| {
                let t = airbases::units(p[0], p[1]);
                [(t[0] - i as f64 * NODE_UNITS) / PIXEL_UNITS, (t[1] - j as f64 * NODE_UNITS) / PIXEL_UNITS]
            };
            // The photo test of the nearest block in this node (a footprint's corners may reach into the next one).
            let open = |p: [f64; 2]| {
                let q = px(p);
                let nb = 1024 / PHOTO_BLOCK;
                let b = |v: f64| ((v / PHOTO_BLOCK as f64).floor().max(0.0) as usize).min(nb - 1);
                let t = airbases::units(p[0], p[1]);
                photo[b(q[1]) * nb + b(q[0])]
                    && rules.open(t[0], t[1])
                    && !moves.bases.iter().any(|b| b.in_old(p, 0.0) || b.to_game(p, ring).is_some())
            };
            let roof = |pts: &[[f64; 2]]| {
                let q: Vec<[f64; 2]> = pts.iter().map(|&p| px(p)).collect();
                (median_inside(&old, &q), median_inside(&modern, &q))
            };
            let mut node = n.clone();
            let ng = node_geos[idx];
            let (cw, ch) =
                (((ng[2] - ng[0]) / CANOPY_STEP).ceil() as usize, ((ng[3] - ng[1]) / CANOPY_STEP).ceil() as usize);
            let cgeo = [ng[0], ng[3] - ch as f64 * CANOPY_STEP, ng[0] + cw as f64 * CANOPY_STEP, ng[3]];
            let tmp = work.join(format!("chm_{i}_{j}.bin"));
            let cv = gdal_warp(std::slice::from_ref(&chm), cgeo, cw, ch, "max", &tmp)?;
            node.canopy = Some(Canopy { lon0: cgeo[0], lat1: cgeo[3], step: CANOPY_STEP, w: cw, h: ch, v: cv });
            let built = |g: [f64; 2]| heights.at(g);
            let w = |lon: f64, lat: f64| warp.at(lon, lat);
            let env = Env { open: &open, clears: &near, built_height: &built, roof: &roof, warp: &w };
            let cell = build_cell(&node, &env);
            let (nb, nosm, nt) = (
                cell.buildings.len(),
                cell.buildings.iter().filter(|b| b.source == SOURCE_OSM).count(),
                cell.trees.len(),
            );
            let mut bytes = 0;
            if nb + nt > 0 {
                let data = cell.encode();
                bytes = data.len() as u64;
                std::fs::write(l1.join(format!("s_{i}_{j}.bin")), data)?;
            }
            let k = done.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
            pr.fraction(0.35 + 0.65 * k as f32 / items.len().max(1) as f32);
            v.push((nb, nosm, nt, bytes));
        }
        Ok(v)
    })?;
    let mut s = Summary::default();
    for (nb, nosm, nt, bytes) in results.into_iter().flatten() {
        s.cells += (nb + nt > 0) as usize;
        s.buildings += nb;
        s.osm += nosm;
        s.trees += nt;
        s.bytes += bytes;
    }
    let downloaded: BTreeSet<String> = SCENERY.iter().filter_map(|d| thirdparty::file_date(&src, d)).collect();
    let downloaded = match (downloaded.first(), downloaded.last()) {
        (Some(a), Some(b)) if a != b => format!("{a}..{b}"),
        (Some(a), _) => a.clone(),
        _ => String::new(),
    };
    let manifest = json!({
        "name": "scenery",
        "release": release(),
        "generator": GENERATOR,
        "made_from": made,
        "attribution": [
            "© OpenStreetMap contributors (openstreetmap.org/copyright), Geofabrik extract of 2026-01-01",
            "Microsoft Global ML Building Footprints",
            "GHS-BUILT-H R2023A, European Commission, Joint Research Centre (JRC)",
            "Meta and World Resources Institute (WRI), High Resolution Canopy Height Maps",
        ],
        "licence": "OpenStreetMap: ODbL 1.0; Microsoft footprints: CDLA-Permissive-2.0; GHSL: free re-use with credit (CC BY 4.0); canopy height: CC BY 4.0",
        "cells": s.cells,
        "buildings": s.buildings,
        "trees": s.trees,
        "downloaded": downloaded,
    });
    std::fs::write(&manifest_p, serde_json::to_string_pretty(&manifest)? + "\n")?;
    log!(
        pr,
        "scenery: {} cells, {} buildings ({} OpenStreetMap), {} trees, {:.1} MB in {}",
        s.cells,
        s.buildings,
        s.osm,
        s.trees,
        s.bytes as f64 / 1e6,
        crate::progress::duration(started.elapsed())
    );
    Ok(s)
}

/// The canopy tiles reduced to ≈ 10 m (the highest metre of each 8 × 8 block; gdalwarp, kept in `work`) under one VRT.
fn chm_vrt(tiles: &[PathBuf], work: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<String> {
    let dir = work.join("chm");
    std::fs::create_dir_all(&dir)?;
    let small: Vec<PathBuf> = par_map(tiles, cancel, |t| {
        let p = dir.join(t.file_name().context("canopy tile name")?);
        if !p.is_file() {
            log!(pr, "canopy: reducing {}", t.display());
            let part = p.with_extension("part.tif");
            let mut cmd = Command::new("gdalwarp");
            cmd.args(["-q", "-overwrite", "-r", "max", "-tr", "9.554628535647", "9.554628535647"])
                .args(["-co", "TILED=YES", "-co", "COMPRESS=DEFLATE", "--config", "GDAL_CACHEMAX", "512"])
                .arg(t)
                .arg(&part);
            run(cmd)?;
            std::fs::rename(&part, &p)?;
        }
        Ok(p)
    })?;
    let vrt = work.join("chm.vrt");
    let mut cmd = Command::new("gdalbuildvrt");
    cmd.arg("-q").arg("-overwrite").arg(&vrt).args(&small);
    run(cmd)?;
    Ok(utf8(&vrt)?.to_string())
}

/// Per PHOTO_BLOCK block of a node: true where the layer shows the photo (it differs from the 1998 rendition, which
/// it equals outside the photographed area). Without a rendition, everything.
fn photo_mask(layer: &RgbImage, orig: Option<&RgbImage>) -> Vec<bool> {
    let nb = 1024 / PHOTO_BLOCK;
    let Some(orig) = orig else { return vec![true; nb * nb] };
    let mut v = vec![false; nb * nb];
    for (k, out) in v.iter_mut().enumerate() {
        let (bx, by) = ((k % nb) * PHOTO_BLOCK, (k / nb) * PHOTO_BLOCK);
        let mut s = 0.0f32;
        for y in by..by + PHOTO_BLOCK {
            for x in bx..bx + PHOTO_BLOCK {
                let (p, q) = (layer.get_pixel(x as u32, y as u32).0, orig.get_pixel(x as u32, y as u32).0);
                s += (0..3).map(|c| (p[c] as f32 - q[c] as f32).abs()).sum::<f32>() / 3.0;
            }
        }
        *out = s / (PHOTO_BLOCK * PHOTO_BLOCK) as f32 > PHOTO_DIFF;
    }
    v
}

/// The per-channel median of the pixels whose centres are inside the polygon (pixel coordinates); the pixel under
/// its centre when none is.
fn median_inside(img: &RgbImage, q: &[[f64; 2]]) -> [u8; 3] {
    let (w, h) = (img.width() as i64, img.height() as i64);
    let b = bbox(q);
    let mut s: [Vec<u8>; 3] = Default::default();
    for y in (b[1].floor() as i64).max(0)..=(b[3].ceil() as i64).min(h - 1) {
        for x in (b[0].floor() as i64).max(0)..=(b[2].ceil() as i64).min(w - 1) {
            if contains(q, [x as f64 + 0.5, y as f64 + 0.5]) {
                let p = img.get_pixel(x as u32, y as u32).0;
                (0..3).for_each(|c| s[c].push(p[c]));
            }
        }
    }
    if s[0].is_empty() {
        let c = centroid(q);
        return img.get_pixel(c[0].clamp(0.0, (w - 1) as f64) as u32, c[1].clamp(0.0, (h - 1) as f64) as u32).0;
    }
    s.map(|mut v| {
        v.sort_unstable();
        v[v.len() / 2]
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A node far from everything with an affine warp (1° = 100 km, origin at its south-west corner).
    const KEY: (u32, u32) = (200, 200);

    fn origin() -> [f64; 2] {
        let r = node_rect(KEY.0, KEY.1);
        [r[0], r[1]]
    }

    fn square(c: [f64; 2], half: f64, source: u8) -> Footprint {
        let pts = vec![
            [c[0] - half, c[1] - half],
            [c[0] + half, c[1] - half],
            [c[0] + half, c[1] + half],
            [c[0] - half, c[1] + half],
        ];
        Footprint { pts, geo: [34.8, 32.0], height: None, levels: 0, roof: Roof::Flat, wall: 0, source }
    }

    fn at(dx: f64, dy: f64) -> [f64; 2] {
        let o = origin();
        [o[0] + dx, o[1] + dy]
    }

    fn cell(n: &NodeIn, clears: &[Clear], open: &(dyn Fn([f64; 2]) -> bool + Sync)) -> Cell {
        let o = origin();
        let built = |g: [f64; 2]| (g[0] > 35.0).then_some(21.0);
        let roof = |_: &[[f64; 2]]| ([1, 2, 3], [4, 5, 6]);
        let warp = |lon: f64, lat: f64| [o[0] + lon * 100_000.0, o[1] + lat * 100_000.0];
        build_cell(n, &Env { open, clears, built_height: &built, roof: &roof, warp: &warp })
    }

    #[test]
    fn merge_heights_and_exclusions() {
        let mut tall = square(at(100.0, 100.0), 10.0, SOURCE_OSM);
        tall.height = Some(30.0);
        let mut ghs = square(at(300.0, 100.0), 10.0, SOURCE_OSM);
        ghs.geo = [35.2, 31.0];
        let n = NodeIn {
            key: KEY,
            osm: vec![tall, ghs, square(at(500.0, 100.0), 5.0, SOURCE_OSM)],
            // Inside an OSM footprint (dropped), clear of it (kept), on a unit (dropped), off the photo (dropped).
            ms: vec![
                square(at(101.0, 99.0), 6.0, SOURCE_MS),
                square(at(700.0, 100.0), 20.0, SOURCE_MS),
                square(at(1000.0, 1000.0), 6.0, SOURCE_MS),
                square(at(2000.0, 100.0), 6.0, SOURCE_MS),
            ],
            trees: vec![
                MappedTree { p: at(100.0, 100.0), kind: None, height: 8.0 }, // on a roof
                MappedTree { p: at(900.0, 900.0), kind: Some(TreeKind::Palm), height: 9.0 },
                MappedTree { p: at(1010.0, 1000.0), kind: None, height: 8.0 }, // a static unit
            ],
            ..NodeIn::default()
        };
        let unit = at(1000.0, 1040.0);
        let clears = [Clear { a: unit, b: unit, building: 50.0, tree: 50.0 }];
        let open = |p: [f64; 2]| p[0] < origin()[0] + 1500.0;
        let c = cell(&n, &clears, &open);
        let hs: Vec<(f32, u8)> = c.buildings.iter().map(|b| (b.height, b.source)).collect();
        assert_eq!(hs, [(30.0, SOURCE_OSM), (21.0, SOURCE_OSM), (6.0, SOURCE_OSM), (12.0, SOURCE_MS)]);
        assert_eq!(c.buildings[0].roof_1998, [1, 2, 3]);
        assert_eq!(c.trees.len(), 1);
        assert_eq!(c.trees[0].kind, TreeKind::Palm);
    }

    #[test]
    fn vehicles_keep_trees_off_their_lane_only() {
        let a = at(500.0, 500.0);
        let b = at(900.0, 500.0);
        let lane = Clear { a, b, building: VEHICLE_BUILDING_M, tree: ROUTE_TREE_M };
        assert!(lane.hits_tree(at(700.0, 503.0)) && !lane.hits_tree(at(700.0, 510.0)));
        // A long building the route crosses with every corner far away.
        let long = vec![at(690.0, 300.0), at(710.0, 300.0), at(710.0, 700.0), at(690.0, 700.0)];
        assert!(lane.hits_building(&long));
        assert!(!lane.hits_building(&square(at(700.0, 560.0), 10.0, 0).pts));
        assert!(lane.hits_building(&square(at(700.0, 530.0), 10.0, 0).pts));
    }

    #[test]
    fn canopy_trees_are_deterministic() {
        let mut v = vec![0u8; 100 * 100];
        for (k, x) in v.iter_mut().enumerate() {
            *x = (k % 7) as u8 * 2;
        }
        let n = NodeIn {
            key: KEY,
            osm: vec![square(at(250.0, 250.0), 30.0, SOURCE_OSM)],
            areas: vec![Area {
                kind: AREA_FOREST,
                pts: vec![at(0.0, 0.0), at(500.0, 0.0), at(500.0, 500.0), at(0.0, 500.0)],
            }],
            canopy: Some(Canopy { lon0: 0.0, lat1: 0.01, step: 0.0001, w: 100, h: 100, v }),
            ..NodeIn::default()
        };
        let open = |_: [f64; 2]| true;
        let (a, b) = (cell(&n, &[], &open), cell(&n, &[], &open));
        assert_eq!(a.encode(), b.encode());
        assert!(a.trees.len() > 3000, "{}", a.trees.len());
        assert!(a.trees.iter().all(|t| t.height >= 4.0 && !a.buildings[0].contains(t.x, t.y)));
        assert!(
            a.trees
                .iter()
                .filter(|t| t.x < at(500.0, 0.0)[0] as f32 && t.y < at(0.0, 500.0)[1] as f32)
                .all(|t| t.kind == TreeKind::Pine)
        );
    }

    #[test]
    fn tags() {
        let t = other_tags(r#""building:levels"=>"4","height"=>"13.5 m","roof:shape"=>"gabled","name"=>"a \"b\"""#);
        assert_eq!(t["name"], "a \"b\"");
        let (h, l, roof, wall) = osm_building("apartments", &t, 300.0, [34.78, 32.08]);
        assert_eq!((h, l, roof, wall), (Some(13.5), 4, Roof::Gabled, 2));
        let t = other_tags(r#""building:levels"=>"2""#);
        assert_eq!(osm_building("yes", &t, 100.0, [35.21, 31.77]), (Some(6.0), 2, Roof::Flat, 1));
        assert_eq!(osm_building("shed", &BTreeMap::new(), 20.0, [34.8, 32.0]).3, 3);
        assert_eq!(tag_number(Some(&"40'".to_string())), None);
        assert_eq!(tagged_kind(&other_tags(r#""genus"=>"Phoenix""#)), Some(TreeKind::Palm));
        assert_eq!(quadkey(34.8, 32.0, 9), "122112223");
        assert_eq!(row_points(&[[0.0, 0.0], [10.0, 0.0], [10.0, 5.0]]).len(), 3);
        assert!(is_static("stationary/ofice/ofice1_h.gltf") && is_static("groundforces/sa6rdr/sa6rdr_h.gltf"));
        assert!(!is_static("groundforces/t72/t72_h.gltf"));
    }
}
