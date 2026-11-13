//! `iaf-scenery`'s work (docs/scenery.md §1): the buildings and trees over the Survey of Israel 2 m layer, one cell
//! file per level-1 node of `mapi2015` (`iaf_avionics::scenery`), from inputs downloaded at setup into
//! `assets/source/scenery` (`thirdparty::SCENERY`, pinned by SHA-256):
//! - OpenStreetMap (Geofabrik's `israel-and-palestine` extract of 2026-01-01): buildings with their tags, forests,
//!   orchards and settlements, single trees and tree rows;
//! - Microsoft's Global ML Building Footprints where OpenStreetMap has no building;
//! - JRC GHS-BUILT-H R2023A (average net building height, 100 m) for buildings without a height tag;
//! - ETH Zürich's global 10 m canopy height (2020) for the trees.
//!
//! Everything is warped from WGS84 into the game frame with the georeference (`georef`), as the imagery is, so the
//! roofs stand on the photo's buildings. Nothing stands where the original has something: the sea, the airbases and
//! the kept target insets (`imagery::Rules`), the missions' units and routes (`airbases::mission_units`), and
//! World scale Real's old and new base sites (`iaf_flight::base_move`); no tree and no Microsoft footprint stands on
//! OpenStreetMap's roads, railways, runways, taxiways and aprons (`road_half_width`). The same pinned inputs give the
//! same bytes on every install (`manifest.json` `release`).

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, bail};
use iaf_avionics::scenery::{Building, Cell, Roof, SOURCE_MS, SOURCE_OSM, Tree, TreeKind};
use image::RgbImage;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

use crate::georef::Georef;
use crate::imagery::{Cache, Rules, Theatre};
use crate::progress::{Progress, check, par_map, par_map_all, utf8};
use crate::thirdparty::{self, Download, SCENERY, SCENERY_THEATRE};
use crate::{airbases, bbox, log, sim_bases};
pub use iaf_avionics::frame::{Frame, GAME};

/// The generator's version: part of the release, so a change to the rules below makes new ids.
pub const GENERATOR: u32 = 7;
/// A level-1 node's side in terrain units (1024 pixels of 2 units).
const NODE_UNITS: f64 = 2.0 * GAME.node_pixels;
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
/// In mapped orchards (`AREA_ORCHARD`) a lower canopy counts: citrus, avocado and olive groves are 2–4 m. Fields keep
/// `CANOPY_MIN_M`: the canopy map reads about 2 m over crops.
pub(crate) const ORCHARD_CANOPY_MIN_M: u8 = 2;
pub(crate) const CANOPY_STEP: f64 = 0.0001;
const ROW_STEP_M: f64 = 6.0;
const TREE_DEFAULT_M: f32 = 8.0;
const ROW_DEFAULT_M: f32 = 10.0;
/// The tree-kind grid (m) and how far a settlement reaches around a building (cells).
const KIND_CELL_M: f64 = 10.0;
const SETTLEMENT_CELLS: i64 = 3;
/// Jerusalem's centre (lon, lat) and the radius (km) inside which walls are stone (docs/scenery.md §1.3).
const JERUSALEM: [f64; 2] = [35.2137, 31.7683];
const JERUSALEM_KM: f64 = 10.0;
/// Trees keep this far (m) beyond a road's half-width; a Microsoft footprint within this of a road or railway's centre
/// line is taken to cross it.
const ROAD_TREE_MARGIN_M: f64 = 1.0;
const ROAD_CROSS_M: f64 = 0.5;
/// How far (m) a road or apron reaches past a node's edge into its list: a footprint may reach into the next node.
const ROAD_NODE_PAD_M: f64 = 50.0;

/// The level-1 node holding an engine point in `frame` (`iaf_avionics::frame`: the 1998 game's, or Modern IAF's UTM
/// theatre); a point west or north of the theatre counts in its first column / row, as the original always did
/// (`build_cell` drops a footprint whose centre is outside its node).
pub fn node_of(frame: Frame, p: [f64; 2]) -> (u32, u32) {
    let (i, j) = frame.node_of(1, p);
    (i.max(0) as u32, j.max(0) as u32)
}

/// Level-1 node (i, j)'s engine rect in `frame`.
pub fn rect_in(frame: Frame, i: u32, j: u32) -> [f64; 4] {
    frame.node_rect(1, i64::from(i), i64::from(j))
}

/// The 1998 game's level-1 node rect.
pub fn node_rect(i: u32, j: u32) -> [f64; 4] {
    rect_in(GAME, i, j)
}

// ---------------------------------------------------------------------------------------------------------------------
// Geometry

fn signed_area(p: &[[f64; 2]]) -> f64 {
    let n = p.len();
    (0..n).map(|i| p[i][0] * p[(i + 1) % n][1] - p[(i + 1) % n][0] * p[i][1]).sum::<f64>() * 0.5
}

pub(crate) fn centroid(p: &[[f64; 2]]) -> [f64; 2] {
    let n = p.len().max(1) as f64;
    let s = p.iter().fold([0.0, 0.0], |s, q| [s[0] + q[0], s[1] + q[1]]);
    [s[0] / n, s[1] / n]
}

/// Even-odd point in polygon.
pub(crate) fn contains(p: &[[f64; 2]], q: [f64; 2]) -> bool {
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
pub const AREA_FIELD: u8 = 2;
pub const AREA_ORCHARD: u8 = 3;
pub const AREA_FOREST: u8 = 4;

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

/// The city lights' stand-ins where the footprints are sparse in a town (docs/scenery.md §1.7): Microsoft's footprints
/// miss most of a dense old centre (central Damascus: about 4 200 in 7 km²). Per GHS-BUILT-H square (0.001°) of the
/// node whose average net building height is FILL_MIN_H or more, squares of FILL_SIDE_M at seeded places until the
/// square holds FILL_PER_CELL footprints (counting the sources' own, kept or not), each on open ground, its height
/// the square's. Lights only: they go into the light cell.
pub fn fill_lights(
    n: &NodeIn,
    heights: &Heights,
    g: [f64; 4],
    warp: &(dyn Fn(f64, f64) -> [f64; 2] + Sync),
    open: &(dyn Fn([f64; 2]) -> bool + Sync),
) -> Vec<Building> {
    let st = Heights::STEP;
    let cell =
        |p: [f64; 2]| (((p[0] - heights.geo[0]) / st).floor() as i64, ((heights.geo[3] - p[1]) / st).floor() as i64);
    let mut have: HashMap<(i64, i64), usize> = HashMap::new();
    for f in n.osm.iter().chain(&n.ms) {
        *have.entry(cell(f.geo)).or_default() += 1;
    }
    let ((c0, r1), (c1, r0)) = (cell([g[0], g[1]]), cell([g[2], g[3]]));
    let rect = n.rect;
    let mut out = Vec::new();
    for r in r0.max(0)..=r1.min(heights.h as i64 - 1) {
        for c in c0.max(0)..=c1.min(heights.w as i64 - 1) {
            let h = heights.v[r as usize * heights.w + c as usize];
            if !(FILL_MIN_H..250.0).contains(&h) {
                continue;
            }
            for k in have.get(&(c, r)).copied().unwrap_or(0)..FILL_PER_CELL {
                let s = [n.key.0 as u64, n.key.1 as u64, c as u64, r as u64, k as u64];
                let (fx, fy) = (unit(&[&s[..], &[7]].concat()), unit(&[&s[..], &[8]].concat()));
                let lon = heights.geo[0] + (c as f64 + fx) * st;
                let lat = heights.geo[3] - (r as f64 + fy) * st;
                let p = warp(lon, lat);
                if p[0] < rect[0] || p[0] >= rect[2] || p[1] < rect[1] || p[1] >= rect[3] || !open(p) {
                    continue;
                }
                let a = FILL_SIDE_M * 0.5;
                let pts = [[-a, -a], [a, -a], [a, a], [-a, a]];
                out.push(Building {
                    points: pts.iter().map(|d| [(p[0] + d[0]) as f32, (p[1] + d[1]) as f32]).collect(),
                    roof: Roof::Flat,
                    wall: 2,
                    height: h,
                    roof_1998: [0; 3],
                    roof_modern: [0; 3],
                    source: SOURCE_MS,
                    levels: (h / LEVEL_M) as u8,
                });
            }
        }
    }
    out
}

/// The light stand-ins (`fill_lights`): the least average building height of a town's square (m; inferred: a
/// village's houses average 3–6 m, a town's blocks of flats more), the footprints a square should hold (a dense
/// centre's footprint every 30–35 m; inferred) and the stand-in's side (m).
const FILL_MIN_H: f32 = 7.0;
const FILL_PER_CELL: usize = 8;
const FILL_SIDE_M: f64 = 12.0;

/// Drops the second of two OpenStreetMap buildings with the same corners and of two mapped trees at the same point
/// (an object in two countries' extracts).
fn drop_twins(n: &mut NodeIn) {
    let mut seen = HashSet::new();
    n.osm.retain(|f| seen.insert(f.pts.iter().map(|p| p.map(f64::to_bits)).collect::<Vec<_>>()));
    let mut seen = HashSet::new();
    n.trees.retain(|t| seen.insert(t.p.map(f64::to_bits)));
}

impl Canopy {
    /// An empty grid of `step` over the box [lon0, lat0, lon1, lat1], its edges on whole steps.
    pub fn grid(b: [f64; 4], step: f64) -> Canopy {
        let (c0, r0) = ((b[0] / step).floor(), (b[3] / step).ceil());
        let (w, h) = (((b[2] / step).ceil() - c0) as usize, (r0 - (b[1] / step).floor()) as usize);
        Canopy { lon0: c0 * step, lat1: r0 * step, step, w, h, v: Vec::new() }
    }

    /// The part over the box (inside this grid), on the same steps.
    pub fn part(&self, b: [f64; 4]) -> Canopy {
        let mut p = Canopy::grid(b, self.step);
        let x0 = ((p.lon0 - self.lon0) / self.step).round() as usize;
        let y0 = ((self.lat1 - p.lat1) / self.step).round() as usize;
        p.v = (0..p.h).flat_map(|y| &self.v[(y0 + y) * self.w + x0..][..p.w]).copied().collect();
        p
    }
}

/// One node's inputs.
#[derive(Clone, Debug, Default)]
pub struct NodeIn {
    pub key: (u32, u32),
    /// The node's engine rect (`Frame::node_rect`).
    pub rect: [f64; 4],
    pub osm: Vec<Footprint>,
    pub ms: Vec<Footprint>,
    pub areas: Vec<Area>,
    pub trees: Vec<MappedTree>,
    pub canopy: Option<Canopy>,
    /// Road, railway, runway and taxiway segments (`road_half_width`): `tree` the half-width + ROAD_TREE_MARGIN_M,
    /// `building` the reach that drops a Microsoft footprint.
    pub roads: Vec<Clear>,
    /// Aprons, runway and taxiway areas: no tree, no Microsoft footprint on them.
    pub paved: Vec<Vec<[f64; 2]>>,
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

/// A footprint the node keeps: its centre inside the node (one beyond the theatre's west or north edge is gathered into
/// the first column / row, `node_of`), 6–200 000 m², every corner and the centre open, clear of the units.
fn building_ok(f: &Footprint, rect: [f64; 4], env: &Env) -> bool {
    let a = signed_area(&f.pts);
    let c = centroid(&f.pts);
    (rect[0]..rect[2]).contains(&c[0])
        && (rect[1]..rect[3]).contains(&c[1])
        && (6.0..=200_000.0).contains(&a)
        && f.pts.iter().chain([&centroid(&f.pts)]).all(|&p| (env.open)(p))
        && !env.clears.iter().any(|c| c.hits_building(&f.pts))
}

/// One node's cell: OpenStreetMap's buildings, then Microsoft's whose centre is in no OpenStreetMap footprint; then the
/// mapped trees and one tree per canopy cell of `CANOPY_MIN_M` or more; nothing where `env` says no.
pub fn build_cell(n: &NodeIn, env: &Env) -> Cell {
    let rect = n.rect;
    let seed = [n.key.0 as u64, n.key.1 as u64];
    let mut osm_b = Buckets::new(rect, 32.0);
    for (k, f) in n.osm.iter().enumerate() {
        osm_b.insert(bbox(&f.pts), k as u32);
    }
    let in_osm = |p: [f64; 2]| osm_b.near(p, 0.0).any(|k| contains(&n.osm[k as usize].pts, p));
    let mut roads = Buckets::new(rect, 32.0);
    for (k, c) in n.roads.iter().enumerate() {
        roads.insert(c.bbox(), k as u32);
    }
    let mut paved = Buckets::new(rect, 64.0);
    for (k, a) in n.paved.iter().enumerate() {
        paved.insert(bbox(a), k as u32);
    }
    let on_paved = |p: [f64; 2]| paved.near(p, 0.0).any(|k| contains(&n.paved[k as usize], p));
    // A Microsoft footprint is machine-traced: one across a road, a railway or a runway is a misreading.
    let ms_ok = |f: &Footprint| {
        let b = bbox(&f.pts);
        let c = [(b[0] + b[2]) * 0.5, (b[1] + b[3]) * 0.5];
        !roads.near(c, (b[2] - b[0]).max(b[3] - b[1]) * 0.5).any(|k| n.roads[k as usize].hits_building(&f.pts))
            && !f.pts.iter().chain([&centroid(&f.pts)]).any(|&p| on_paved(p))
    };
    let chosen: Vec<&Footprint> = n
        .osm
        .iter()
        .chain(n.ms.iter().filter(|f| !in_osm(centroid(&f.pts)) && ms_ok(f)))
        .filter(|f| building_ok(f, rect, env))
        .collect();
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
            && !roads.near(p, 0.0).any(|k| n.roads[k as usize].hits_tree(p))
            && !on_paved(p)
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
                if v < ORCHARD_CANOPY_MIN_M {
                    continue;
                }
                let s = [seed[0], seed[1], r as u64, col as u64];
                let (jx, jy) = (unit(&[s[0], s[1], s[2], s[3], 2]) - 0.5, unit(&[s[0], s[1], s[2], s[3], 3]) - 0.5);
                let lon = c.lon0 + (col as f64 + 0.5 + 0.7 * jx) * c.step;
                let lat = c.lat1 - (r as f64 + 0.5 + 0.7 * jy) * c.step;
                let p = (env.warp)(lon, lat);
                if v < CANOPY_MIN_M && kinds.area(p) != AREA_ORCHARD
                    || !tree_ok(p)
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
    /// The area (`AREA_*`) at `p`, 0 for none.
    fn area(&self, p: [f64; 2]) -> u8 {
        let (i, j) = self.cell(p);
        if i >= 0 && j >= 0 && (i as usize) < self.w && (j as usize) < self.h {
            self.v[j as usize * self.w + i as usize]
        } else {
            0
        }
    }
    /// The kind of a tree at `p`: pine in a forest, broadleaf (olive-like) in an orchard or field, in a settlement a
    /// palm one time in four, else broadleaf.
    fn kind(&self, p: [f64; 2], seed: &[u64]) -> TreeKind {
        match self.area(p) {
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
pub(crate) fn tag_number(v: Option<&String>) -> Option<f32> {
    let v = v?.trim();
    let end = v.find(|c: char| !(c.is_ascii_digit() || c == '.')).unwrap_or(v.len());
    let rest = v[end..].trim();
    if !(rest.is_empty() || rest == "m") {
        return None;
    }
    v[..end].parse::<f32>().ok().filter(|x| x.is_finite() && *x > 0.0)
}

/// A road's, railway's, runway's or taxiway's half-width (m) and the reach (m) that drops a Microsoft footprint
/// (crossing the centre line for roads and rails, anywhere on a runway or taxiway); None for other lines and for
/// tunnels (nothing stands on them).
pub fn road_half_width(highway: &str, railway: &str, tags: &BTreeMap<String, String>) -> Option<(f64, f64)> {
    if tags.get("tunnel").or(tags.get("covered")).is_some_and(|v| v != "no") {
        return None;
    }
    let half = match (highway.trim_end_matches("_link"), railway) {
        ("motorway", _) => 12.0,
        ("trunk", _) => 10.0,
        ("primary", _) => 8.0,
        ("secondary", _) => 6.0,
        ("tertiary" | "unclassified", _) => 5.0,
        ("residential", _) => 4.0,
        ("service", _) => 3.0,
        (_, "rail" | "light_rail" | "subway" | "tram") => 3.0,
        _ => {
            let default = match tags.get("aeroway").map(String::as_str) {
                Some("runway") => 30.0,
                Some("taxiway") => 12.0,
                _ => return None,
            };
            let half = tag_number(tags.get("width")).map_or(default, |w| (w as f64 * 0.5).clamp(5.0, 60.0));
            return Some((half, half));
        }
    };
    Some((half, ROAD_CROSS_M))
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
    /// The grid over `geo` [lon0, lat0, lon1, lat1] of `to_engine` (the georeference's exact inverse, or UTM 36N).
    pub fn new(to_engine: &(dyn Fn(f64, f64) -> [f64; 2] + Sync), geo: [f64; 4], step: f64) -> Self {
        let w = ((geo[2] - geo[0]) / step).ceil() as usize + 2;
        let h = ((geo[3] - geo[1]) / step).ceil() as usize + 2;
        let rows: Vec<usize> = (0..h).collect();
        let xy = par_map_all(&rows, |&r| {
            (0..w).map(|c| to_engine(geo[0] + c as f64 * step, geo[1] + r as f64 * step)).collect::<Vec<_>>()
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
pub(crate) fn gdal_warp(
    srcs: &[String],
    geo: [f64; 4],
    w: usize,
    h: usize,
    resampling: &str,
    out: &Path,
) -> Result<Vec<u8>> {
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
pub(crate) fn run(mut cmd: Command) -> Result<()> {
    let name = format!("{:?}", cmd.get_program());
    // No .aux.xml statistics beside or inside the sources: GDAL wrote one into a pinned zip, which then failed its
    // checksum on every other install.
    cmd.env("GDAL_PAM_ENABLED", "NO");
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
pub struct Heights {
    geo: [f64; 4],
    w: usize,
    h: usize,
    v: Vec<f32>,
}

impl Heights {
    const STEP: f64 = 0.001;
    pub(crate) fn at(&self, g: [f64; 2]) -> Option<f32> {
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
    frame: Frame,
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
        if let Some(n) = self.nodes.get_mut(&node_of(self.frame, centroid(&f.pts))) {
            if f.source == SOURCE_OSM { n.osm.push(f) } else { n.ms.push(f) }
        }
    }

    fn area(&mut self, a: Area) {
        let b = bbox(&a.pts);
        let (i0, j1) = node_of(self.frame, [b[0], b[1]]);
        let (i1, j0) = node_of(self.frame, [b[2], b[3]]);
        for j in j0..=j1 {
            for i in i0..=i1 {
                if let Some(n) = self.nodes.get_mut(&(i, j)) {
                    n.areas.push(a.clone());
                }
            }
        }
    }

    /// The nodes whose rect, grown by ROAD_NODE_PAD_M, meets the box.
    fn nodes_in(&mut self, b: [f64; 4]) -> impl Iterator<Item = &mut NodeIn> {
        let pad = ROAD_NODE_PAD_M;
        let (i0, j1) = node_of(self.frame, [b[0] - pad, b[1] - pad]);
        let (i1, j0) = node_of(self.frame, [b[2] + pad, b[3] + pad]);
        self.nodes.range_mut((i0, j0)..=(i1, j1)).filter(move |(k, _)| k.1 >= j0 && k.1 <= j1).map(|(_, n)| n)
    }

    fn road(&mut self, c: Clear) {
        for n in self.nodes_in(c.bbox()) {
            n.roads.push(c);
        }
    }

    fn paved(&mut self, pts: Vec<[f64; 2]>) {
        for n in self.nodes_in(bbox(&pts)) {
            n.paved.push(pts.clone());
        }
    }

    fn tree(&mut self, t: MappedTree) {
        if let Some(n) = self.nodes.get_mut(&node_of(self.frame, t.p)) {
            n.trees.push(t);
        }
    }
}

/// ogr2ogr's cut of `pbf`'s `layer` into the GeoJSONSeq file `out`: the features matching `filter` in the box `geo`
/// (lon / lat), with the fields `select`. The command for `run`.
pub(crate) fn ogr_cut(pbf: &Path, layer: &str, filter: &str, select: &str, geo: [f64; 4], out: &Path) -> Command {
    let mut cmd = Command::new("ogr2ogr");
    cmd.args(["-f", "GeoJSONSeq", "-where", filter])
        .args(["-select", select, "-spat"])
        .args(geo.map(|v| v.to_string()))
        .arg(out)
        .arg(pbf)
        .arg(layer);
    cmd
}

/// Lines of a GeoJSONSeq file as JSON values.
pub(crate) fn geojsonl(p: &Path) -> Result<impl Iterator<Item = Value>> {
    let f = std::fs::File::open(p).with_context(|| format!("{}", p.display()))?;
    Ok(BufReader::new(f).lines().map_while(std::result::Result::ok).filter_map(|l| serde_json::from_str(&l).ok()))
}

/// OpenStreetMap's layers cut to the box (ogr2ogr → GeoJSONSeq in `work`).
fn osm_extract(pbf: &Path, geo: [f64; 4], work: &Path, pr: &dyn Progress) -> Result<[PathBuf; 3]> {
    let tag = |k: &str, v: &str| format!("other_tags LIKE '%\"{k}\"=>\"{v}\"%'");
    let jobs = [
        (
            "multipolygons",
            "building IS NOT NULL OR landuse IN ('forest','orchard','farmland','vineyard','plant_nursery','residential') OR natural = 'wood' OR aeroway IN ('apron','runway','taxiway')",
            "building,landuse,natural,aeroway,other_tags",
        ),
        ("points", &*tag("natural", "tree"), "other_tags"),
        (
            "lines",
            &*format!(
                "{} OR {} OR {} OR highway IN ({}) OR railway IN ('rail','light_rail','subway','tram')",
                tag("natural", "tree_row"),
                tag("aeroway", "runway"),
                tag("aeroway", "taxiway"),
                ["motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "service"]
                    .iter()
                    .flat_map(|h| [format!("'{h}'"), format!("'{h}_link'")])
                    .collect::<Vec<_>>()
                    .join(",")
            ),
            "highway,railway,other_tags",
        ),
    ];
    // The extract is kept for the next run with the same box and filter (named by them).
    let mut out = Vec::new();
    for (layer, filter, fields) in jobs {
        let key: Vec<u64> = geo.map(f64::to_bits).into_iter().chain(filter.bytes().map(u64::from)).collect();
        let tag = hash(&key) as u32;
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
            ("orchard" | "plant_nursery", _) => Some(AREA_ORCHARD),
            ("farmland" | "vineyard", _) => Some(AREA_FIELD),
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
            } else if matches!(s("aeroway"), "apron" | "runway" | "taxiway") {
                g.paved(pts);
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
        let pr = &v["properties"];
        let tags = other_tags(pr["other_tags"].as_str().unwrap_or(""));
        let s = |k: &str| pr[k].as_str().unwrap_or("");
        if let Some((half, building)) = road_half_width(s("highway"), s("railway"), &tags) {
            let line: Vec<[f64; 2]> = v["geometry"]["coordinates"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|p| Some([p[0].as_f64()?, p[1].as_f64()?]))
                .filter(|p| g.in_geo(*p))
                .map(|p| g.warp.at(p[0], p[1]))
                .collect();
            for w in line.windows(2) {
                g.road(Clear { a: w[0], b: w[1], building, tree: half + ROAD_TREE_MARGIN_M });
            }
            continue;
        }
        if tags.get("natural").map(String::as_str) != Some("tree_row") {
            continue;
        }
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

/// The kinds `build` makes (setup's choice, docs/scenery.md §1.6): buildings, trees or both.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Kinds {
    pub buildings: bool,
    pub trees: bool,
}

impl Default for Kinds {
    fn default() -> Self {
        Self::BOTH
    }
}

impl Kinds {
    pub const BOTH: Kinds = Kinds { buildings: true, trees: true };

    /// "both", "buildings" or "trees".
    pub fn parse(s: &str) -> Option<Kinds> {
        match s {
            "both" => Some(Self::BOTH),
            "buildings" => Some(Kinds { buildings: true, trees: false }),
            "trees" => Some(Kinds { buildings: false, trees: true }),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match (self.buildings, self.trees) {
            (true, false) => "buildings",
            (false, true) => "trees",
            _ => "both",
        }
    }

    /// Whether the kinds need the download `file` of `SCENERY`: OpenStreetMap always; the Microsoft footprints and
    /// GHS-BUILT-H for buildings; ETH's canopy for trees.
    pub fn needs(self, file: &str) -> bool {
        if file.starts_with("ms-") || file.starts_with("GHS_") {
            self.buildings
        } else if file.starts_with("eth-") {
            self.trees
        } else {
            true
        }
    }

    /// The downloads of `SCENERY` the kinds need.
    pub fn downloads(self) -> Vec<Download> {
        SCENERY.iter().filter(|d| self.needs(d.file)).copied().collect()
    }

    /// The downloads of `SCENERY_THEATRE` the kinds need (the rest of the theatre, `build_theatre`; each optional).
    pub fn theatre_downloads(self) -> Vec<Download> {
        SCENERY_THEATRE.iter().filter(|d| self.needs(d.file)).copied().collect()
    }
}

/// Downloads the rest of the theatre's sources the kinds need (`thirdparty::SCENERY_THEATRE`) into
/// `assets/source/scenery`: four at once; the files that failed then once more each, and a file that fails again is
/// logged and left out (its area has no buildings or trees). The count downloaded now.
pub fn fetch_theatre(assets: &Path, kinds: Kinds, pr: &dyn Progress, cancel: &AtomicBool) -> Result<usize> {
    let (dir, list) = (assets.join("source/scenery"), kinds.theatre_downloads());
    if let Ok(n) = thirdparty::fetch_files(&list, &dir, pr, cancel) {
        return Ok(n);
    }
    // A file failed (logged): the others are done or keep their parts; each is tried once more on its own.
    let mut n = 0;
    for d in list.iter().filter(|d| !thirdparty::file_done(&dir, d)) {
        match thirdparty::fetch_files(std::slice::from_ref(d), &dir, pr, cancel) {
            Ok(k) => n += k,
            Err(e) => {
                check(cancel)?;
                log!(pr, "scenery: {} not downloaded, its area has no buildings or trees: {e:#}", d.file);
            }
        }
    }
    Ok(n)
}

/// What `build` is asked to do.
pub struct Run {
    /// The assets folder.
    pub assets: PathBuf,
    /// Only the nodes whose centre is within `km` of the engine point (x, y): a quick look at one place.
    pub near: Option<([f64; 2], f64)>,
    /// What to make.
    pub kinds: Kinds,
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
fn node_geo(frame: Frame, to_geo: &dyn Fn(f64, f64) -> [f64; 2], k: (u32, u32), pad: f64) -> [f64; 4] {
    let r = rect_in(frame, k.0, k.1);
    let pts: Vec<[f64; 2]> = [0.0, 0.5, 1.0]
        .iter()
        .flat_map(|&fx| [0.0, 0.5, 1.0].map(|fy| to_geo(r[0] + fx * (r[2] - r[0]), r[1] + fy * (r[3] - r[1]))))
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
        let b = node_geo(GAME, &|x, y| g.engine_to_geo(x, y), k, 0.0);
        for p in [[b[0], b[1]], [b[2], b[1]], [b[0], b[3]], [b[2], b[3]]] {
            out.insert(quadkey(p[0], p[1], 9));
        }
    }
    Ok(out)
}

/// The release: the checksums of the pinned inputs the kinds need, the generator's version and the kinds (when not
/// both), hashed (hex SHA-256).
pub fn release(kinds: Kinds) -> String {
    let mut h = Sha256::new();
    for d in kinds.downloads() {
        h.update(d.sha256.as_bytes());
        h.update(b"\n");
    }
    h.update(format!("generator {GENERATOR}\n").as_bytes());
    if kinds != Kinds::BOTH {
        h.update(format!("kinds {}\n", kinds.name()).as_bytes());
    }
    format!("{:x}", h.finalize())
}

/// What the cells are made from besides the release: the nodes, the converted missions and airbases, the area.
fn made_from(r: &Run, keys: &[(u32, u32)]) -> String {
    let a = &r.assets;
    let mut h = Sha256::new();
    h.update(release(r.kinds).as_bytes());
    for k in keys {
        for l in ["mapi2015", "mapi2015_modern"] {
            let p = a.join(format!("converted/imagery/{l}/L1/c_{}_{}.jpg", k.0, k.1));
            h.update(format!("{k:?} {}\n", std::fs::metadata(&p).map_or(0, |m| m.len())).as_bytes());
        }
    }
    converted_inputs(&mut h, a, true);
    h.update(format!("{:?}", r.near).as_bytes());
    format!("{:x}", h.finalize())
}

/// The converted files the scenery and the roads read (the missions' units and object lists, the objects' models
/// list, the airbases, the theatre's nodes), into `h`: the small ones by content, the theatre by its files' sizes
/// (2.3 GB). Not the setup steps' stamps: those hold the converters' code fingerprint, so any pull that touched a
/// converter made the scenery again (about 10 min) from the same files. `objects`: the objects' list too (the roads
/// leave it out).
pub(crate) fn converted_inputs(h: &mut Sha256, a: &Path, objects: bool) {
    let c = a.join("converted");
    // Modern IAF's object database (iaf-sim) lies beside the original's and changes no scenery.
    let sim = Path::new(crate::sim_files::BDB_FILE).file_name();
    let mut files: Vec<PathBuf> = crate::walk_files(&c.join("missions"))
        .unwrap_or_default()
        .into_iter()
        .filter(|f| f.file_name() != sim)
        .collect();
    files.push(c.join("terrain/airbases.json"));
    files.push(c.join("terrain/theatre/meta.json"));
    if objects {
        files.push(c.join("objects/objects.json"));
    }
    files.sort();
    for f in &files {
        h.update(format!("{}\n", f.strip_prefix(&c).unwrap_or(f).display()).as_bytes());
        let bytes = std::fs::read(f).unwrap_or_default();
        h.update(if f.ends_with("objects/objects.json") { without_sim(bytes) } else { bytes });
    }
    let mut theatre = crate::walk_files(&c.join("terrain/theatre")).unwrap_or_default();
    theatre.sort();
    for f in &theatre {
        let len = std::fs::metadata(f).map_or(0, |m| m.len());
        h.update(format!("{} {len}\n", f.strip_prefix(&c).unwrap_or(f).display()).as_bytes());
    }
}

/// `objects.json`'s bytes without Modern IAF's key (iaf-sim's `"sim.bdb"`): re-serialised as `iaf-convert objects`
/// writes it (pretty, keys sorted), which gives back the original's bytes; any other file as it is.
fn without_sim(bytes: Vec<u8>) -> Vec<u8> {
    let Ok(mut m) = serde_json::from_slice::<serde_json::Map<String, serde_json::Value>>(&bytes) else { return bytes };
    if m.remove(crate::sim_files::BDB).is_none() {
        return bytes;
    }
    serde_json::to_vec_pretty(&m).unwrap_or(bytes)
}

/// The clearances that reach within 50 m of the engine rect.
pub(crate) fn clears_near(all: &[Clear], rect: [f64; 4]) -> Vec<Clear> {
    all.iter()
        .filter(|c| {
            let b = c.bbox();
            b[0] < rect[2] + 50.0 && b[2] > rect[0] - 50.0 && b[1] < rect[3] + 50.0 && b[3] > rect[1] - 50.0
        })
        .copied()
        .collect()
}

/// The downloaded inputs of the list, or an error naming the first missing one.
pub(crate) fn input(dir: &Path, d: &Download) -> Result<PathBuf> {
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
    let mut keys = coverage(&a.join("converted/imagery"))?;
    // The towns' names for the town labels (docs/scenery.md §3.5), over the whole coverage, in the 1998 frame,
    // whenever the file is missing (the manifest leaves it out) and the extracts are there. Optional: a failure is
    // logged and the step goes on.
    let places_p = a.join("converted/terrain/theatre/places.json");
    let osm: Vec<Download> = r.kinds.downloads().into_iter().filter(|d| d.file.ends_with(".osm.pbf")).collect();
    if !places_p.is_file() && !keys.is_empty() && !osm.is_empty() && osm.iter().all(|d| thirdparty::file_done(&src, d))
    {
        let pbfs: Vec<PathBuf> = osm.iter().map(|d| src.join(d.file)).collect();
        let written = Georef::load().and_then(|georef| {
            let geo = keys
                .iter()
                .map(|&k| node_geo(GAME, &|x, y| georef.engine_to_geo(x, y), k, 0.0))
                .fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, g| {
                    [b[0].min(g[0]), b[1].min(g[1]), b[2].max(g[2]), b[3].max(g[3])]
                });
            crate::sim_scenery::places_in(&pbfs, geo, &|lon, lat| georef.geo_to_engine(lon, lat), &places_p)
        });
        match written {
            Ok(n) => log!(pr, "places: {n} towns and villages"),
            Err(e) => log!(pr, "places: not written ({e:#})"),
        }
    }
    if let Some((c, km)) = r.near {
        keys.retain(|k| {
            let n = node_rect(k.0, k.1);
            ((n[0] + n[2]) * 0.5 - c[0]).hypot((n[1] + n[3]) * 0.5 - c[1]) <= km * 1000.0
        });
    }
    if keys.is_empty() {
        bail!("no node of the Survey 2 m layer within the given distance");
    }
    let made = made_from(r, &keys);
    let manifest_p = out.join("manifest.json");
    if let Ok(m) = std::fs::read(&manifest_p).map(|b| serde_json::from_slice::<Value>(&b).unwrap_or(Value::Null))
        && m["made_from"] == made.as_str()
    {
        return Ok(Summary { up_to_date: true, ..Summary::default() });
    }
    let kinds = r.kinds;
    let files: Vec<PathBuf> = kinds.downloads().iter().map(|d| input(&src, d)).collect::<Result<_>>()?;
    std::fs::create_dir_all(&work)?;
    log!(pr, "scenery ({}): {} nodes of the Survey 2 m layer", kinds.name(), keys.len());
    let Sources { warp, nodes, node_geos, heights, chm } = sources(GAME, &keys, kinds, &files, &work, pr, cancel)?;

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
    let items: Vec<(usize, &NodeIn)> = nodes.values().enumerate().collect();
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
            let near = clears_near(&all_clears, rect);
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
                if !kinds.buildings {
                    return Default::default();
                }
                let q: Vec<[f64; 2]> = pts.iter().map(|&p| px(p)).collect();
                (median_inside(&old, &q), median_inside(&modern, &q))
            };
            let mut node = n.clone();
            let ng = node_geos[idx];
            let (cw, ch) =
                (((ng[2] - ng[0]) / CANOPY_STEP).ceil() as usize, ((ng[3] - ng[1]) / CANOPY_STEP).ceil() as usize);
            let cgeo = [ng[0], ng[3] - ch as f64 * CANOPY_STEP, ng[0] + cw as f64 * CANOPY_STEP, ng[3]];
            if let Some(chm) = &chm {
                let tmp = work.join(format!("chm_{i}_{j}.bin"));
                let cv = gdal_warp(std::slice::from_ref(chm), cgeo, cw, ch, "max", &tmp)?;
                node.canopy = Some(Canopy { lon0: cgeo[0], lat1: cgeo[3], step: CANOPY_STEP, w: cw, h: ch, v: cv });
            }
            let built = |g: [f64; 2]| heights.at(g);
            let w = |lon: f64, lat: f64| warp.at(lon, lat);
            let env = Env { open: &open, clears: &near, built_height: &built, roof: &roof, warp: &w };
            let mut cell = build_cell(&node, &env);
            if !kinds.buildings {
                cell.buildings.clear();
            }
            if !kinds.trees {
                cell.trees.clear();
            }
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
    let downloaded: BTreeSet<String> =
        kinds.downloads().iter().filter_map(|d| thirdparty::file_date(&src, d)).collect();
    let downloaded = match (downloaded.first(), downloaded.last()) {
        (Some(a), Some(b)) if a != b => format!("{a}..{b}"),
        (Some(a), _) => a.clone(),
        _ => String::new(),
    };
    let attribution: Vec<&str> = [
        ("israel", "© OpenStreetMap contributors (openstreetmap.org/copyright), Geofabrik extract of 2026-01-01"),
        ("ms-", "Microsoft Global ML Building Footprints"),
        ("GHS_", "GHS-BUILT-H R2023A, European Commission, Joint Research Centre (JRC)"),
        ("eth-", "Global Canopy Height 2020, Lang et al., ETH Zürich (EcoVision Lab)"),
    ]
    .iter()
    .filter(|(f, _)| kinds.needs(f))
    .map(|(_, a)| *a)
    .collect();
    let manifest = json!({
        "name": "scenery",
        "release": release(kinds),
        "generator": GENERATOR,
        "kinds": kinds.name(),
        "made_from": made,
        "attribution": attribution,
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

/// The sources gathered per node (`sources`).
pub(crate) struct Sources {
    pub warp: Warp,
    pub nodes: BTreeMap<(u32, u32), NodeIn>,
    pub node_geos: Vec<[f64; 4]>,
    pub heights: Heights,
    pub chm: Option<String>,
}

/// The warp over the nodes `keys`, every source the kinds need cut to them and gathered per node, the building
/// heights and the canopy (trees).
pub(crate) fn sources(
    frame: Frame,
    keys: &[(u32, u32)],
    kinds: Kinds,
    files: &[PathBuf],
    work: &Path,
    pr: &dyn Progress,
    cancel: &AtomicBool,
) -> Result<Sources> {
    // The projection: the georeference's for the 1998 frame, UTM 36N's for Modern IAF's.
    let georef = if frame == GAME { Some(Georef::load()?) } else { None };
    let to_engine =
        |lon: f64, lat: f64| georef.as_ref().map_or_else(|| sim_bases::utm36n(lon, lat), |g| g.geo_to_engine(lon, lat));
    let to_geo =
        |x: f64, y: f64| georef.as_ref().map_or_else(|| sim_bases::utm36n_geo(x, y), |g| g.engine_to_geo(x, y));
    let pick = |pre: &str| -> Vec<PathBuf> {
        files.iter().filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with(pre))).cloned().collect()
    };

    // The warp over the coverage.
    let node_geos: Vec<[f64; 4]> = par_map_all(keys, |&k| node_geo(frame, &to_geo, k, 0.0005));
    let geo = node_geos.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, g| {
        [b[0].min(g[0]), b[1].min(g[1]), b[2].max(g[2]), b[3].max(g[3])]
    });
    let geo = [geo[0] - 0.01, geo[1] - 0.01, geo[2] + 0.01, geo[3] + 0.01];
    let warp = Warp::new(&to_engine, geo, 0.005);
    pr.fraction(0.02);

    // The sources, gathered per node.
    let nodes = {
        let mut g = Gather {
            frame,
            warp: &warp,
            nodes: keys
                .iter()
                .map(|&k| (k, NodeIn { key: k, rect: rect_in(frame, k.0, k.1), ..NodeIn::default() }))
                .collect(),
            geo,
        };
        // Israel and Palestine's extract; with the other countries' (the theatre's cells), each in a work folder of
        // its own (an extract's cut files replace the earlier ones in their folder).
        let pbfs: Vec<PathBuf> = files.iter().filter(|p| p.to_string_lossy().ends_with(".osm.pbf")).cloned().collect();
        for pbf in &pbfs {
            let dir = if pbfs.len() == 1 {
                work.to_path_buf()
            } else {
                work.join(pbf.file_name().unwrap_or_default().to_string_lossy().replace(".osm.pbf", ""))
            };
            std::fs::create_dir_all(&dir)?;
            let osm = osm_extract(pbf, geo, &dir, pr)?;
            check(cancel)?;
            read_osm(&osm, &mut g, cancel)?;
        }
        // The extracts overlap at the borders: a building or tree in two of them is kept once.
        if pbfs.len() > 1 {
            g.nodes.values_mut().for_each(drop_twins);
        }
        pr.fraction(0.15);
        log!(pr, "Microsoft footprints: {} files", pick("ms-").len());
        let ms = par_map(&pick("ms-"), cancel, |f| read_ms(f, &g))?;
        for f in ms.into_iter().flatten() {
            g.building(f);
        }
        g.nodes
    };
    pr.fraction(0.25);
    let heights = if kinds.buildings {
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
        Heights { geo: hgeo, w: hw, h: hh, v: raw.as_chunks::<4>().0.iter().map(|b| f32::from_le_bytes(*b)).collect() }
    } else {
        Heights { geo, w: 0, h: 0, v: Vec::new() }
    };
    // Trees only: OpenStreetMap's buildings still keep the trees off (as with both), but none is written.
    let chm = if kinds.trees { Some(canopy_vrt(&pick("eth-"), work)?) } else { None };
    pr.fraction(0.35);
    Ok(Sources { warp, nodes, node_geos, heights, chm })
}

/// The version of the light cells' rules (`build_lights`): part of their `made_from`.
const LIGHTS_VERSION: u32 = 2;

/// The city lights' extra buildings (docs/rendering.md §5.1) into `assets/converted/scenery/lights`: per level-1 node
/// of the Survey layer, the buildings the scenery cell of that node does not hold because the Survey photo or the
/// scenery stops there (the kept target insets, Tel Aviv's coast among them), by the same rules as the scenery's
/// otherwise (`Rules::lights_open`: off the airbases, on land; the units' clearances; World scale Real's sites).
/// Buildings only, no roof colour; the game draws only their lights. The other nodes' light cells are
/// `build_theatre`'s. Up to date when its manifest says it was made from the same scenery and inputs.
pub fn build_lights(r: &Run, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Summary> {
    let started = std::time::Instant::now();
    let a = &r.assets;
    if !r.kinds.buildings {
        return Ok(Summary { up_to_date: true, ..Summary::default() });
    }
    let scenery_made = std::fs::read(a.join("converted/scenery/manifest.json"))
        .ok()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
        .and_then(|m| m["made_from"].as_str().map(str::to_string))
        .context("the scenery is not made (iaf-scenery build)")?;
    let made = format!("{scenery_made} lights {LIGHTS_VERSION} {:?}", r.near);
    let out = a.join("converted/scenery/lights");
    let manifest_p = out.join("manifest.json");
    if let Ok(m) = std::fs::read(&manifest_p).map(|b| serde_json::from_slice::<Value>(&b).unwrap_or(Value::Null))
        && m["made_from"] == made.as_str()
    {
        return Ok(Summary { up_to_date: true, ..Summary::default() });
    }
    let install = a.join("install");
    let theatre = Theatre::load(&a.join("converted/terrain/theatre"))?;
    let rules = Rules::load(&install, false, &theatre)?;
    let mut keys = coverage(&a.join("converted/imagery"))?;
    if let Some((c, km)) = r.near {
        keys.retain(|k| {
            let n = node_rect(k.0, k.1);
            ((n[0] + n[2]) * 0.5 - c[0]).hypot((n[1] + n[3]) * 0.5 - c[1]) <= km * 1000.0
        });
    }
    let kinds = Kinds { buildings: true, trees: false };
    let src = a.join("source/scenery");
    let files: Vec<PathBuf> = kinds.downloads().iter().map(|d| input(&src, d)).collect::<Result<_>>()?;
    let work = a.join("converted/scenery/.work");
    std::fs::create_dir_all(&work)?;
    log!(pr, "city lights: {} nodes of the Survey 2 m layer", keys.len());
    let Sources { warp, nodes, heights, .. } = sources(GAME, &keys, kinds, &files, &work, pr, cancel)?;
    let units = airbases::mission_units(&a.join("converted/missions"));
    let lineups = airbases::ibx_lineups(&std::fs::read(install.join("iaf.ibx")).unwrap_or_default());
    let all_clears =
        clears(&units, &lineups, &Models::load(&a.join("converted/objects"), &a.join("converted/missions")));
    let moves = base_moves(&install, &a.join("converted/terrain"));
    let ring = iaf_flight::base_move::RING;
    let l1 = out.join("L1");
    if l1.is_dir() {
        std::fs::remove_dir_all(&l1)?;
    }
    std::fs::create_dir_all(&l1)?;
    let open = |p: [f64; 2]| {
        let t = airbases::units(p[0], p[1]);
        rules.lights_open(t[0], t[1]) && !moves.bases.iter().any(|b| b.in_old(p, 0.0) || b.to_game(p, ring).is_some())
    };
    let built = |g: [f64; 2]| heights.at(g);
    let w = |lon: f64, lat: f64| warp.at(lon, lat);
    let roof = |_: &[[f64; 2]]| ([0; 3], [0; 3]);
    let items: Vec<&NodeIn> = nodes.values().filter(|n| !n.osm.is_empty() || !n.ms.is_empty()).collect();
    let counts = par_map(&items, cancel, |n| {
        let (i, j) = n.key;
        let near = clears_near(&all_clears, node_rect(i, j));
        let env = Env { open: &open, clears: &near, built_height: &built, roof: &roof, warp: &w };
        let mut cell = build_cell(n, &env);
        cell.trees.clear();
        // The scenery cell's own buildings stay there: the same footprint (its first corner and corner count).
        let key = |b: &Building| (b.points[0][0].to_bits(), b.points[0][1].to_bits(), b.points.len());
        if let Some(have) = Cell::read_buildings(&a.join(format!("converted/scenery/L1/s_{i}_{j}.bin"))) {
            let have: BTreeSet<_> = have.iter().map(key).collect();
            cell.buildings.retain(|b| !have.contains(&key(b)));
        }
        if !cell.buildings.is_empty() {
            std::fs::write(l1.join(format!("s_{i}_{j}.bin")), cell.encode())?;
        }
        Ok(cell.buildings.len())
    })?;
    let s = Summary {
        cells: counts.iter().filter(|&&n| n > 0).count(),
        buildings: counts.iter().sum(),
        ..Summary::default()
    };
    let manifest = json!({
        "name": "scenery lights",
        "made_from": made,
        "cells": s.cells,
        "buildings": s.buildings,
    });
    std::fs::write(&manifest_p, serde_json::to_string_pretty(&manifest)? + "\n")?;
    log!(
        pr,
        "city lights: {} cells, {} buildings beyond the scenery, in {}",
        s.cells,
        s.buildings,
        crate::progress::duration(started.elapsed())
    );
    Ok(s)
}

/// The version of the theatre cells' rules (`build_theatre`): part of their `made_from`.
const THEATRE_VERSION: u32 = 4;
/// The theatre's canopy grid (degrees, about 20 m): one tree per four of the Survey layer's cells, the tallest. On the
/// 10 m grid the theatre held 348 M trees (5.6 GB, 2026-10-30): the Nile delta's groves and Cyprus' forests.
pub(crate) const THEATRE_CANOPY_STEP: f64 = 0.0002;
/// The theatre's cells are made in blocks of this many level-1 nodes a side (a level-5 node, about 40 km): one canopy
/// warp and one set of ground images per block.
pub(crate) const THEATRE_BLOCK: u32 = 16;
/// The level of the ground images the theatre's roof colours come from: the Sentinel-2 layer's (9.9 m a pixel).
const GROUND_LEVEL: u32 = 3;

/// A level-3 node's ground: (1998 look, modern look).
type Ground = Option<(std::sync::Arc<RgbImage>, std::sync::Arc<RgbImage>)>;

/// The scenery of the rest of the theatre (docs/scenery.md §1.7): every level-1 node of the theatre that the Survey 2 m
/// layer lacks, from every OpenStreetMap extract (Israel and Palestine's and the other countries' of the road layer),
/// the Microsoft footprints, GHS-BUILT-H and ETH's canopy of `SCENERY` and `SCENERY_THEATRE` that are downloaded.
/// Into the scenery's `L1` (no node of the Survey layer is among them), by the same rules:
/// - in the Israel region, where the ground is the 1998 art: off the kept target insets (`Rules::open`); the roofs'
///   colour from the 1998 rendition;
/// - outside it, where the Sentinel-2 layer replaces the 1998 art (`Rules::open` of an outside layer and a level-3
///   node of `sentinel2`): the roofs' colours from `sentinel2` and `sentinel2_modern`.
///
/// The buildings that stand nowhere else (the kept insets, the nodes without Sentinel-2) go into the city lights'
/// cells (`lights/L1`). Writes `theatre.json`: the cells by region (the game shows the outside ones over Sentinel-2
/// only), the counts and `made_from` (up to date when it matches: the city lights', the inputs, the Sentinel-2 node
/// lists).
pub fn build_theatre(r: &Run, pr: &dyn Progress, cancel: &AtomicBool) -> Result<Summary> {
    let started = std::time::Instant::now();
    let a = &r.assets;
    let out = a.join("converted/scenery");
    let made_of = |p: &str| {
        std::fs::read(out.join(p))
            .ok()
            .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
            .and_then(|m| m["made_from"].as_str().map(str::to_string))
    };
    // After the scenery and the city lights' cells: their runs empty L1 and lights/L1.
    let before = made_of("lights/manifest.json")
        .filter(|_| r.kinds.buildings)
        .or_else(|| made_of("manifest.json"))
        .context("the scenery is not made (iaf-scenery build)")?;
    let src = a.join("source/scenery");
    let mut files: Vec<PathBuf> = r.kinds.downloads().iter().map(|d| input(&src, d)).collect::<Result<_>>()?;
    let extra: Vec<Download> =
        r.kinds.theatre_downloads().into_iter().filter(|d| thirdparty::file_done(&src, d)).collect();
    files.extend(extra.iter().map(|d| src.join(d.file)));
    let roads: Vec<&Download> =
        thirdparty::ROADS.iter().filter(|d| thirdparty::file_done(&a.join("source/roads"), d)).collect();
    files.extend(roads.iter().map(|d| a.join("source/roads").join(d.file)));
    let s2 = |l: &str| -> BTreeSet<(u32, u32)> {
        let m: Value = std::fs::read(a.join(format!("converted/imagery/{l}/manifest.json")))
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or(Value::Null);
        m["nodes"][GROUND_LEVEL.to_string()]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|ij| Some((ij[0].as_u64()? as u32, ij[1].as_u64()? as u32)))
            .collect()
    };
    let (s2_old, s2_modern) = (s2("sentinel2"), s2("sentinel2_modern"));
    let made = {
        let mut h = Sha256::new();
        h.update(format!("{before}\ntheatre {THEATRE_VERSION} {} {:?}\n", r.kinds.name(), r.near).as_bytes());
        for d in extra.iter().chain(roads.iter().copied()) {
            h.update(format!("{}\n", d.sha256).as_bytes());
        }
        h.update(format!("{s2_old:?}\n{s2_modern:?}\n").as_bytes());
        format!("{:x}", h.finalize())
    };
    let manifest_p = out.join("theatre.json");
    if let Ok(m) = std::fs::read(&manifest_p).map(|b| serde_json::from_slice::<Value>(&b).unwrap_or(Value::Null))
        && m["made_from"] == made.as_str()
    {
        return Ok(Summary { up_to_date: true, ..Summary::default() });
    }

    // Every level-1 node of the theatre the Survey layer lacks.
    let install = a.join("install");
    let theatre = Theatre::load(&a.join("converted/terrain/theatre"))?;
    let survey: BTreeSet<(u32, u32)> = coverage(&a.join("converted/imagery")).unwrap_or_default().into_iter().collect();
    let n1 = [theatre.rect[2], theatre.rect[3]].map(|v| v.div_ceil(NODE_UNITS as u32));
    let mut keys: Vec<(u32, u32)> =
        (0..n1[0]).flat_map(|i| (0..n1[1]).map(move |j| (i, j))).filter(|k| !survey.contains(k)).collect();
    if let Some((c, km)) = r.near {
        keys.retain(|k| {
            let n = node_rect(k.0, k.1);
            ((n[0] + n[2]) * 0.5 - c[0]).hypot((n[1] + n[3]) * 0.5 - c[1]) <= km * 1000.0
        });
    }
    // The old run's cells (a node may have nothing now).
    if let Ok(m) = std::fs::read(&manifest_p).map(|b| serde_json::from_slice::<Value>(&b).unwrap_or(Value::Null)) {
        for ij in ["israel", "outside", "lights"].iter().flat_map(|k| m[*k].as_array().cloned().unwrap_or_default()) {
            let (i, j) = (ij[0].as_u64().unwrap_or(0), ij[1].as_u64().unwrap_or(0));
            let _ = std::fs::remove_file(out.join(format!("L1/s_{i}_{j}.bin")));
            let _ = std::fs::remove_file(out.join(format!("lights/L1/s_{i}_{j}.bin")));
        }
    }
    let _ = std::fs::remove_file(&manifest_p);
    let work = out.join(".work/theatre");
    std::fs::create_dir_all(&work)?;
    std::fs::create_dir_all(out.join("L1"))?;
    std::fs::create_dir_all(out.join("lights/L1"))?;
    log!(
        pr,
        "scenery of the theatre ({}): {} nodes, {} of the other countries' files, {} OpenStreetMap extracts",
        r.kinds.name(),
        keys.len(),
        extra.len(),
        roads.len() + 1
    );
    let Sources { warp, nodes, node_geos, heights, chm } = sources(GAME, &keys, r.kinds, &files, &work, pr, cancel)?;
    let geos: HashMap<(u32, u32), [f64; 4]> = keys.iter().copied().zip(node_geos).collect();

    let rules = Rules::load(&install, false, &theatre)?;
    let rules_out = Rules::load(&install, true, &theatre)?;
    let units = airbases::mission_units(&a.join("converted/missions"));
    let lineups = airbases::ibx_lineups(&std::fs::read(install.join("iaf.ibx")).unwrap_or_default());
    let all_clears =
        clears(&units, &lineups, &Models::load(&a.join("converted/objects"), &a.join("converted/missions")));
    let moves = base_moves(&install, &a.join("converted/terrain"));
    let ring = iaf_flight::base_move::RING;
    let g_span = (NODE_UNITS as u32) << (GROUND_LEVEL - 1);
    let isr = rules.israel;
    let in_israel =
        |t: [f64; 2]| t[0] >= isr[0] as f64 && t[0] < isr[2] as f64 && t[1] >= isr[1] as f64 && t[1] < isr[3] as f64;
    let g_key = |t: [f64; 2]| ((t[0].max(0.0) as u32) / g_span, (t[1].max(0.0) as u32) / g_span);
    let off_sites = |p: [f64; 2]| !moves.bases.iter().any(|b| b.in_old(p, 0.0) || b.to_game(p, ring).is_some());
    let open = |p: [f64; 2]| {
        let t = airbases::units(p[0], p[1]);
        (if in_israel(t) { rules.open(t[0], t[1]) } else { rules_out.open(t[0], t[1]) && s2_old.contains(&g_key(t)) })
            && off_sites(p)
    };
    let lights_open = |p: [f64; 2]| {
        let t = airbases::units(p[0], p[1]);
        rules.ground_open(t[0], t[1]) && off_sites(p)
    };
    let built = |g: [f64; 2]| heights.at(g);
    let w = |lon: f64, lat: f64| warp.at(lon, lat);

    // Per block of nodes, on every core.
    let mut blocks: BTreeMap<(u32, u32), Vec<&NodeIn>> = BTreeMap::new();
    for n in nodes.values() {
        blocks.entry((n.key.0 / THEATRE_BLOCK, n.key.1 / THEATRE_BLOCK)).or_default().push(n);
    }
    let blocks: Vec<Vec<&NodeIn>> = blocks.into_values().collect();
    let done = std::sync::atomic::AtomicUsize::new(0);
    let results = par_map(&blocks, cancel, |block| {
        check(cancel)?;
        let mut cache = Cache::default();
        let mut grounds: HashMap<(u32, u32), Ground> = HashMap::new();
        let mut ground = |k: (u32, u32)| -> Result<Ground> {
            if let Some(g) = grounds.get(&k) {
                return Ok(g.clone());
            }
            let t = [(k.0 * g_span) as f64, (k.1 * g_span) as f64];
            let img = |l: &str| -> Result<std::sync::Arc<RgbImage>> {
                let p = a.join(format!("converted/imagery/{l}/L{GROUND_LEVEL}/c_{}_{}.jpg", k.0, k.1));
                Ok(std::sync::Arc::new(image::open(&p).with_context(|| format!("{}", p.display()))?.to_rgb8()))
            };
            let g = if in_israel(t) {
                theatre.rendition((GROUND_LEVEL, k.0, k.1), &mut cache)?.map(|i| (i.clone(), i))
            } else if s2_old.contains(&k) {
                let old = img("sentinel2")?;
                Some((old.clone(), if s2_modern.contains(&k) { img("sentinel2_modern")? } else { old }))
            } else {
                None
            };
            grounds.insert(k, g.clone());
            Ok(g)
        };
        // The canopy over the block's nodes once, on the THEATRE_CANOPY_STEP grid (each node takes its part).
        let canopy = match &chm {
            Some(chm) => {
                let b = block.iter().map(|n| geos[&n.key]).fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, g| {
                    [b[0].min(g[0]), b[1].min(g[1]), b[2].max(g[2]), b[3].max(g[3])]
                });
                let mut c = Canopy::grid(b, THEATRE_CANOPY_STEP);
                let geo = [c.lon0, c.lat1 - c.h as f64 * c.step, c.lon0 + c.w as f64 * c.step, c.lat1];
                let tmp = work.join(format!("chm_{}_{}.bin", block[0].key.0, block[0].key.1));
                c.v = gdal_warp(std::slice::from_ref(chm), geo, c.w, c.h, "max", &tmp)?;
                Some(c)
            }
            None => None,
        };
        let mut v = Vec::new();
        for n in block {
            let (i, j) = n.key;
            let mut node = (*n).clone();
            node.canopy = canopy
                .as_ref()
                .map(|c| c.part(geos[&n.key]))
                .filter(|c| c.v.iter().any(|&v| v >= ORCHARD_CANOPY_MIN_M));
            if node.osm.is_empty() && node.ms.is_empty() && node.trees.is_empty() && node.canopy.is_none() {
                continue;
            }
            // The roofs' colours: the ground image under the footprint's centre.
            let mut roofs: HashMap<(u32, u32), Ground> = HashMap::new();
            for f in node.osm.iter().chain(&node.ms) {
                let k = g_key(airbases::units(centroid(&f.pts)[0], centroid(&f.pts)[1]));
                if let std::collections::hash_map::Entry::Vacant(e) = roofs.entry(k) {
                    e.insert(ground(k)?);
                }
            }
            let roof = |pts: &[[f64; 2]]| {
                let t = airbases::units(centroid(pts)[0], centroid(pts)[1]);
                let k = g_key(t);
                let Some(Some((old, modern))) = roofs.get(&k) else { return ([0; 3], [0; 3]) };
                let s = g_span as f64 / 1024.0;
                let q: Vec<[f64; 2]> = pts
                    .iter()
                    .map(|&p| {
                        let t = airbases::units(p[0], p[1]);
                        [(t[0] - (k.0 * g_span) as f64) / s, (t[1] - (k.1 * g_span) as f64) / s]
                    })
                    .collect();
                (median_inside(old, &q), median_inside(modern, &q))
            };
            let near = clears_near(&all_clears, node_rect(i, j));
            let env = Env { open: &open, clears: &near, built_height: &built, roof: &roof, warp: &w };
            let mut cell = build_cell(&node, &env);
            if !r.kinds.buildings {
                cell.buildings.clear();
            }
            if !r.kinds.trees {
                cell.trees.clear();
            }
            // The city lights' buildings: those the cell lacks where the ground is open.
            let mut lights = Cell::default();
            if r.kinds.buildings {
                let bare = NodeIn { trees: Vec::new(), canopy: None, areas: Vec::new(), ..(*n).clone() };
                let no_roof = |_: &[[f64; 2]]| ([0; 3], [0; 3]);
                let env = Env { open: &lights_open, clears: &near, built_height: &built, roof: &no_roof, warp: &w };
                lights = build_cell(&bare, &env);
                let key = |b: &Building| (b.points[0][0].to_bits(), b.points[0][1].to_bits(), b.points.len());
                let have: HashSet<_> = cell.buildings.iter().map(key).collect();
                lights.buildings.retain(|b| !have.contains(&key(b)));
                lights.trees.clear();
                lights.buildings.extend(fill_lights(&node, &heights, geos[&n.key], &w, &lights_open));
            }
            let t = airbases::units(
                (node_rect(i, j)[0] + node_rect(i, j)[2]) * 0.5,
                (node_rect(i, j)[1] + node_rect(i, j)[3]) * 0.5,
            );
            let mut bytes = 0;
            let (nb, nt, nl) = (cell.buildings.len(), cell.trees.len(), lights.buildings.len());
            if nb + nt > 0 {
                let data = cell.encode();
                bytes += data.len() as u64;
                std::fs::write(out.join(format!("L1/s_{i}_{j}.bin")), data)?;
            }
            if nl > 0 {
                let data = lights.encode();
                bytes += data.len() as u64;
                std::fs::write(out.join(format!("lights/L1/s_{i}_{j}.bin")), data)?;
            }
            let osm = cell.buildings.iter().filter(|b| b.source == SOURCE_OSM).count();
            v.push((n.key, in_israel(t), nb, osm, nt, nl, bytes));
        }
        let k = done.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
        pr.fraction(0.35 + 0.65 * k as f32 / blocks.len().max(1) as f32);
        Ok(v)
    })?;
    let (mut s, mut light_cells, mut light_buildings) = (Summary::default(), 0, 0);
    let (mut in_isr, mut outside, mut lit) = (Vec::new(), Vec::new(), Vec::new());
    for (k, isr, nb, osm, nt, nl, bytes) in results.into_iter().flatten() {
        if nb + nt > 0 {
            s.cells += 1;
            if isr { in_isr.push([k.0, k.1]) } else { outside.push([k.0, k.1]) }
        }
        if nl > 0 {
            light_cells += 1;
            lit.push([k.0, k.1]);
        }
        (s.buildings, s.osm, s.trees, s.bytes) = (s.buildings + nb, s.osm + osm, s.trees + nt, s.bytes + bytes);
        light_buildings += nl;
    }
    let manifest = json!({
        "name": "scenery theatre",
        "made_from": made,
        "kinds": r.kinds.name(),
        "attribution": [
            format!("© OpenStreetMap contributors (openstreetmap.org/copyright), Geofabrik extracts of 2026-01-01 ({})",
                std::iter::once("Israel and Palestine").chain(roads.iter().map(|d| crate::roads::country(d.file))).collect::<Vec<_>>().join(", ")),
            "Microsoft Global ML Building Footprints",
            "GHS-BUILT-H R2023A, European Commission, Joint Research Centre (JRC)",
            "Global Canopy Height 2020, Lang et al., ETH Zürich (EcoVision Lab)",
        ],
        "cells": s.cells,
        "buildings": s.buildings,
        "trees": s.trees,
        "light_cells": light_cells,
        "light_buildings": light_buildings,
        "israel": in_isr,
        "outside": outside,
        "lights": lit,
    });
    std::fs::write(&manifest_p, serde_json::to_string(&manifest)? + "\n")?;
    // The countries' cut extracts (1.8 GB) are not kept: they save about 2 minutes of a run that only new inputs ask.
    let _ = std::fs::remove_dir_all(&work);
    log!(
        pr,
        "scenery of the theatre: {} cells, {} buildings ({} OpenStreetMap), {} trees; city lights: {} cells, {} buildings; {:.1} MB in {}",
        s.cells,
        s.buildings,
        s.osm,
        s.trees,
        light_cells,
        light_buildings,
        s.bytes as f64 / 1e6,
        crate::progress::duration(started.elapsed())
    );
    Ok(s)
}

/// The canopy tiles (ETH's 10 m, already the cell grid's size) under one VRT; 255 is ETH's no-data.
pub(crate) fn canopy_vrt(tiles: &[PathBuf], work: &Path) -> Result<String> {
    let vrt = work.join("canopy.vrt");
    let mut cmd = Command::new("gdalbuildvrt");
    cmd.args(["-q", "-overwrite", "-srcnodata", "255", "-vrtnodata", "0"]).arg(&vrt).args(tiles);
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
pub(crate) fn median_inside(img: &RgbImage, q: &[[f64; 2]]) -> [u8; 3] {
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

/// The per-channel median of the pixels outside the polygon (pixel coordinates) within `ring` pixels of its edge (the
/// wall tops and the street beside a footprint); the inside median when none is.
pub(crate) fn median_ring(img: &RgbImage, q: &[[f64; 2]], ring: f64) -> [u8; 3] {
    let (w, h) = (img.width() as i64, img.height() as i64);
    let b = bbox(q);
    let mut s: [Vec<u8>; 3] = Default::default();
    let seg = |p: [f64; 2], a: [f64; 2], c: [f64; 2]| {
        let (dx, dy) = (c[0] - a[0], c[1] - a[1]);
        let t = (((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy).max(1e-12)).clamp(0.0, 1.0);
        (p[0] - a[0] - t * dx).hypot(p[1] - a[1] - t * dy)
    };
    for y in ((b[1] - ring).floor() as i64).max(0)..=((b[3] + ring).ceil() as i64).min(h - 1) {
        for x in ((b[0] - ring).floor() as i64).max(0)..=((b[2] + ring).ceil() as i64).min(w - 1) {
            let p = [x as f64 + 0.5, y as f64 + 0.5];
            if contains(q, p) {
                continue;
            }
            let d = (0..q.len()).map(|k| seg(p, q[k], q[(k + 1) % q.len()])).fold(f64::MAX, f64::min);
            if d <= ring {
                let c = img.get_pixel(x as u32, y as u32).0;
                (0..3).for_each(|k| s[k].push(c[k]));
            }
        }
    }
    if s[0].is_empty() {
        return median_inside(img, q);
    }
    s.map(|mut v| {
        v.sort_unstable();
        v[v.len() / 2]
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 4 × 4 px dark square on a light 12 × 12 image with a red frame 1 px around it: the ring's median is the frame's,
    /// the inside's the square's.
    #[test]
    fn median_ring_reads_around_the_footprint() {
        let mut img = RgbImage::from_pixel(12, 12, image::Rgb([200, 200, 200]));
        for y in 3..9 {
            for x in 3..9 {
                let edge = x == 3 || x == 8 || y == 3 || y == 8;
                img.put_pixel(x, y, image::Rgb(if edge { [180, 40, 30] } else { [20, 20, 20] }));
            }
        }
        let q = [[4.0, 4.0], [8.0, 4.0], [8.0, 8.0], [4.0, 8.0]];
        assert_eq!(median_inside(&img, &q), [20, 20, 20]);
        assert_eq!(median_ring(&img, &q, 1.0), [180, 40, 30]);
    }

    /// The fingerprint follows the converted files, not the setup stamps (a converter's code change alone no longer
    /// makes the scenery again).
    #[test]
    fn converted_inputs_follow_the_files() {
        let a = std::env::temp_dir().join(format!("iaf-scenery-inputs-{}", std::process::id()));
        let c = a.join("converted");
        std::fs::create_dir_all(c.join("missions")).unwrap();
        std::fs::create_dir_all(c.join("terrain/theatre/L1")).unwrap();
        std::fs::write(c.join("missions/m.json"), "{}").unwrap();
        std::fs::write(c.join("terrain/theatre/L1/c_0_0.jpg"), "abc").unwrap();
        let fp = || {
            let mut h = Sha256::new();
            converted_inputs(&mut h, &a, true);
            h.finalize()
        };
        // Modern IAF's output (iaf-sim) leaves the fingerprint as it is: its bdb, and its key in objects.json.
        std::fs::create_dir_all(c.join("objects")).unwrap();
        let index = serde_json::json!({"default6_1.bdb": {"1": "a/b.gltf", "10": "c.gltf"}});
        std::fs::write(c.join("objects/objects.json"), serde_json::to_string_pretty(&index).unwrap()).unwrap();
        let first = fp();
        std::fs::write(c.join("missions/sim.bdb.json"), "{}").unwrap();
        let mut with = index.clone();
        with["sim.bdb"] = serde_json::json!({"3": "f16i.gltf"});
        std::fs::write(c.join("objects/objects.json"), serde_json::to_string_pretty(&with).unwrap()).unwrap();
        assert_eq!(fp(), first, "Modern IAF's output");
        std::fs::write(c.join("missions.stamp"), "iaf-setup 1234").unwrap();
        assert_eq!(fp(), first, "a stamp alone");
        std::fs::write(c.join("missions/m.json"), "{\"a\":1}").unwrap();
        let second = fp();
        assert_ne!(second, first, "a mission's content");
        std::fs::write(c.join("terrain/theatre/L1/c_0_0.jpg"), "abcd").unwrap();
        assert_ne!(fp(), second, "a theatre file's size");
        std::fs::remove_dir_all(&a).unwrap();
    }

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
            rect: node_rect(KEY.0, KEY.1),
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
        // A footprint gathered into the node but centred outside it (beyond the theatre's edge) stands nowhere.
        let off = NodeIn { osm: vec![square(at(-300.0, 100.0), 10.0, SOURCE_OSM)], ms: vec![], ..n.clone() };
        assert_eq!(cell(&off, &[], &|_| true).buildings.len(), 0);
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
    fn kinds_pick_their_downloads_and_release() {
        let [b, t] = ["buildings", "trees"].map(|k| Kinds::parse(k).unwrap());
        let names = |k: Kinds| k.downloads().iter().map(|d| d.file).collect::<Vec<_>>();
        assert_eq!(names(Kinds::BOTH).len(), SCENERY.len());
        let osm = |f: &&str| f.ends_with(".osm.pbf");
        assert!(names(b).iter().all(|f| osm(f) || f.starts_with("ms-") || f.starts_with("GHS_")));
        assert!(names(t).iter().all(|f| osm(f) || f.starts_with("eth-")));
        assert!(names(b).iter().any(osm) && names(t).iter().any(osm), "OpenStreetMap for both");
        assert_eq!(names(b).len() + names(t).len(), SCENERY.len() + 1);
        assert_eq!(Kinds::parse(Kinds::BOTH.name()), Some(Kinds::BOTH));
        // Each kind its own release; both keeps the release made before the kinds.
        let mut h = Sha256::new();
        for d in SCENERY {
            h.update(d.sha256.as_bytes());
            h.update(b"\n");
        }
        h.update(format!("generator {GENERATOR}\n").as_bytes());
        let old: String = format!("{:x}", h.finalize());
        assert_eq!(release(Kinds::BOTH), old);
        assert!(release(b) != old && release(t) != old && release(b) != release(t));
    }

    #[test]
    fn canopy_trees_are_deterministic() {
        let mut v = vec![0u8; 100 * 100];
        for (k, x) in v.iter_mut().enumerate() {
            *x = (k % 7) as u8 * 2;
        }
        let n = NodeIn {
            key: KEY,
            rect: node_rect(KEY.0, KEY.1),
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
    fn roads_and_runways_keep_scenery_off() {
        let none = BTreeMap::new();
        let (half, cross) = road_half_width("motorway", "", &none).unwrap();
        let road = Clear { a: at(0.0, 500.0), b: at(2000.0, 500.0), building: cross, tree: half + ROAD_TREE_MARGIN_M };
        let (rh, rb) = road_half_width("", "", &other_tags(r#""aeroway"=>"runway","width"=>"45""#)).unwrap();
        assert_eq!((rh, rb), (22.5, 22.5));
        let runway = Clear { a: at(0.0, 1500.0), b: at(2000.0, 1500.0), building: rb, tree: rh + ROAD_TREE_MARGIN_M };
        assert!(road_half_width("motorway", "", &other_tags(r#""tunnel"=>"yes""#)).is_none());
        let n = NodeIn {
            key: KEY,
            rect: node_rect(KEY.0, KEY.1),
            // An OSM building across the road (mapped: kept); Microsoft's across the road, on the runway's edge, on
            // the apron (dropped) and beside the road (kept).
            osm: vec![square(at(300.0, 500.0), 8.0, SOURCE_OSM)],
            ms: vec![
                square(at(600.0, 505.0), 8.0, SOURCE_MS),
                square(at(600.0, 1520.0), 6.0, SOURCE_MS),
                square(at(1100.0, 1100.0), 6.0, SOURCE_MS),
                square(at(600.0, 540.0), 8.0, SOURCE_MS),
            ],
            trees: vec![
                MappedTree { p: at(900.0, 510.0), kind: None, height: 8.0 }, // on the road (12 + 1 m)
                MappedTree { p: at(900.0, 515.0), kind: None, height: 8.0 }, // beside it
                MappedTree { p: at(900.0, 1520.0), kind: None, height: 8.0 }, // on the runway
                MappedTree { p: at(1050.0, 1050.0), kind: None, height: 8.0 }, // on the apron
            ],
            roads: vec![road, runway],
            paved: vec![vec![at(1000.0, 1000.0), at(1200.0, 1000.0), at(1200.0, 1200.0), at(1000.0, 1200.0)]],
            ..NodeIn::default()
        };
        let open = |_: [f64; 2]| true;
        let c = cell(&n, &[], &open);
        assert_eq!(c, cell(&n, &[], &open));
        let mut kept: Vec<(u8, f32)> = c.buildings.iter().map(|b| (b.source, b.points[0][1])).collect();
        kept.sort_by(|a, b| a.partial_cmp(b).unwrap());
        assert_eq!(kept, [(SOURCE_OSM, at(0.0, 492.0)[1] as f32), (SOURCE_MS, at(0.0, 532.0)[1] as f32)]);
        let ys: Vec<f32> = c.trees.iter().map(|t| t.y).collect();
        assert_eq!(ys, [at(0.0, 515.0)[1] as f32]);
    }

    #[test]
    fn theatre_canopy_parts_and_twins() {
        let mut block = Canopy::grid([34.00004, 31.99996, 34.01, 32.01], CANOPY_STEP);
        assert_eq!((block.w, block.h), (100, 101));
        assert!((block.lon0 - 34.0).abs() < 1e-9 && (block.lat1 - 32.01).abs() < 1e-9);
        block.v = (0..block.w * block.h).map(|k| (k % 251) as u8).collect();
        let p = block.part([34.00512, 32.00303, 34.00733, 32.00495]);
        let (x0, y0) = (51, 50);
        assert_eq!((p.w, p.h), (23, 20));
        assert_eq!(p.v[0], block.v[y0 * block.w + x0]);
        assert_eq!(p.v[p.w * 3 + 7], block.v[(y0 + 3) * block.w + x0 + 7]);

        let mut n = NodeIn { key: KEY, rect: node_rect(KEY.0, KEY.1), ..NodeIn::default() };
        let c = [origin()[0] + 500.0, origin()[1] + 500.0];
        n.osm = vec![square(c, 5.0, SOURCE_OSM), square(c, 5.0, SOURCE_OSM), square(c, 6.0, SOURCE_OSM)];
        let t = MappedTree { p: c, kind: None, height: 8.0 };
        n.trees = vec![t.clone(), t.clone(), MappedTree { p: [c[0] + 1.0, c[1]], ..t }];
        drop_twins(&mut n);
        assert_eq!((n.osm.len(), n.trees.len()), (2, 2), "one of each pair is kept");
    }

    #[test]
    fn light_stand_ins_fill_sparse_town_squares() {
        // A node with an affine warp (1° = 100 km from its south-west corner) and a 4 × 4 height grid over it: one
        // town square (12 m), one village square (4 m).
        let o = origin();
        let warp = move |lon: f64, lat: f64| [o[0] + (lon - 34.0) * 100_000.0, o[1] + (lat - 32.0) * 100_000.0];
        let mut v = vec![0.0f32; 16];
        v[5] = 12.0;
        v[6] = 4.0;
        let heights = Heights { geo: [34.0, 32.0, 34.004, 32.004], w: 4, h: 4, v };
        let g = [34.0, 32.0, 34.004, 32.004];
        let mut n = NodeIn { key: KEY, rect: node_rect(KEY.0, KEY.1), ..NodeIn::default() };
        let fill = fill_lights(&n, &heights, g, &warp, &|_| true);
        assert_eq!(fill.len(), FILL_PER_CELL, "the town square filled, the village left alone");
        assert!(fill.iter().all(|b| b.height == 12.0 && b.points.len() == 4));
        // Its centre (lon 34.0015, lat 32.0025) as engine metres; the stand-ins inside the square.
        let c = warp(34.0015, 32.0025);
        assert!(
            fill.iter()
                .all(|b| (b.points[0][0] as f64 - c[0]).abs() < 60.0 && (b.points[0][1] as f64 - c[1]).abs() < 60.0)
        );
        let mut f = square(c, 5.0, SOURCE_MS);
        f.geo = [34.0015, 32.0025];
        n.ms = vec![f; 3];
        assert_eq!(fill_lights(&n, &heights, g, &warp, &|_| true).len(), FILL_PER_CELL - 3, "up to the count");
        assert!(fill_lights(&n, &heights, g, &warp, &|_| false).is_empty(), "only on open ground");
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
