//! `iaf-sim airbases` (iaf-2026/docs/airbases.md §"In the game"): the airbases of `iaf-2026/data/airbases/`
//! (lat / lon, item B2a) compiled into the sim's UTM 36N frame (iaf-2026/docs/terrain.md §2), in the shapes the
//! shared readers take:
//! - `converted/terrain/israel/airbases.json` and one paved-surface mask per base (`airbases/<name>.png`), as
//!   `iaf-terrain airbases` writes for the original (docs/rendering.md §7): Detailed airbases draws them;
//! - `converted/own/iaf.ibx`: one section per base (tower, lineup, take-off heading, the AI's taxi paths, the parking
//!   spots), read by `iaf_flight::airbase::Airbase` and the radio (iaf-2026/docs/data-formats.md §12);
//! - `converted/own/terraintype.dat`: the surface flags' BSP tree (iaf_formats::terrain_types): the runways, the sea
//!   from the coast, land elsewhere.
//!
//! Nothing is read from the original game's files.

use std::collections::{BinaryHeap, HashMap};
use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};

use crate::log;
use crate::progress::{Progress, check};

/// The bases' iaf.ibx sections in `iaf_flight::airbase::SECTIONS`' order (the original's Ramon, David and TelNof, ours
/// appended) and the runway end each takes off from (inferred: the missions' runways; Hatzerim's longest runway and
/// Tel Nof's 33L into the prevailing westerly wind).
pub const BASES: [(&str, &str, &str); 5] = [
    ("LLRM", "Ramon", "25R"),
    ("LLRD", "David", "27"),
    ("LLEK", "TelNof", "33L"),
    ("LLHB", "Hatzerim", "28L"),
    ("LLNV", "Nevatim", "26L"),
];
/// The lineup point this far down the centreline from the declared runway start (m; the missions' runway start,
/// iaf-2026/docs/data-formats.md §5; inferred: a jet's length and a margin).
pub const LINEUP_IN_M: f64 = 100.0;
/// A taxiway without an OSM width (m; inferred: the usual 23 m of a fighter base's taxiway, ICAO code D–E).
const TAXIWAY_WIDTH_M: f64 = 23.0;
/// Mask pixel (m) and the margin around a base's outline.
const MASK_PX_M: f64 = 2.0;
const MASK_MARGIN_M: f64 = 300.0;
/// The taxi-line distance the mask's blue channel holds (0 … this, m): `airbases.gd` draws the line from it.
const TAXI_FIELD_M: f64 = 10.0;
/// terraintype.dat flags (iaf_formats::terrain_types; the original's runway leaves are 0x10 alone).
const LAND: i32 = 0x1;
const INLAND_WATER: i32 = 0x2;
const SEA: i32 = 0x4;
const RUNWAY: i32 = 0x10;
/// The bases' taxiways, aprons and shelters' pads: no flag (not LAND, so not the rough ground that destroys a jet
/// rolling over 25.7 m/s; not RUNWAY, which the runways alone carry).
const PAVED: i32 = 0x0;
/// The paved surface's cell in terraintype.dat (m; four mask pixels, a cell paved when any of its pixels is: a 23 m
/// taxiway is three or four cells, its edge up to a cell wider; 4 m cells made the file 200,000 nodes larger).
const PAVED_CELL_M: f64 = 8.0;
/// The water raster's cell (m): the DEM's height texel.
const WATER_CELL_M: f64 = 64.0;
/// The smallest sea or land part along the coastline in terraintype.dat (m): a point 20 m off the coastline is always
/// on its side (a leaf's half diagonal is 11 m); 8 m made the file 37 MB, 16 m about half (inferred: the water
/// shader's mask is 96 m).
const COAST_LEAF_M: f64 = 16.0;

// --- UTM 36N --------------------------------------------------------------------------------------------------------

/// WGS84 (lon, lat) degrees → UTM zone 36N (easting, northing) metres: the transverse Mercator (Krüger series to
/// n⁴, < 1 mm in the zone) with k₀ 0.9996, central meridian 33° E, false easting 500 km.
pub fn utm36n(lon: f64, lat: f64) -> [f64; 2] {
    const A: f64 = 6_378_137.0;
    const F: f64 = 1.0 / 298.257_223_563;
    let n = F / (2.0 - F);
    let a = A / (1.0 + n) * (1.0 + n * n / 4.0 + n.powi(4) / 64.0);
    let al = [
        n / 2.0 - 2.0 * n * n / 3.0 + 5.0 * n.powi(3) / 16.0 + 41.0 * n.powi(4) / 180.0,
        13.0 * n * n / 48.0 - 3.0 * n.powi(3) / 5.0 + 557.0 * n.powi(4) / 1440.0,
        61.0 * n.powi(3) / 240.0 - 103.0 * n.powi(4) / 140.0,
        49561.0 * n.powi(4) / 161_280.0,
    ];
    let c = 2.0 * n.sqrt() / (1.0 + n);
    let s = lat.to_radians().sin();
    let t = (s.atanh() - c * (c * s).atanh()).sinh();
    let dl = (lon - 33.0).to_radians();
    let (xi1, eta1) = (t.atan2(dl.cos()), (dl.sin() / (1.0 + t * t).sqrt()).atanh());
    let (mut xi, mut eta) = (xi1, eta1);
    for (j, a) in al.iter().enumerate() {
        let k = 2.0 * (j + 1) as f64;
        xi += a * (k * xi1).sin() * (k * eta1).cosh();
        eta += a * (k * xi1).cos() * (k * eta1).sinh();
    }
    [500_000.0 + 0.9996 * a * eta, 0.9996 * a * xi]
}

/// UTM zone 36N (easting, northing) → WGS84 (lon, lat): `utm36n` inverted by Newton steps (a few, to well under a
/// millimetre).
pub fn utm36n_geo(e: f64, n: f64) -> [f64; 2] {
    let lat = n / 110_900.0;
    let mut g = [33.0 + (e - 500_000.0) / (111_320.0 * lat.to_radians().cos()), lat];
    for _ in 0..5 {
        let (p, d) = (utm36n(g[0], g[1]), 1e-6);
        let (px, py) = (utm36n(g[0] + d, g[1]), utm36n(g[0], g[1] + d));
        let (a, b, c, k) = ((px[0] - p[0]) / d, (py[0] - p[0]) / d, (px[1] - p[1]) / d, (py[1] - p[1]) / d);
        let (r0, r1, det) = (e - p[0], n - p[1], a * k - b * c);
        g = [g[0] + (k * r0 - b * r1) / det, g[1] + (a * r1 - c * r0) / det];
    }
    g
}

/// A true heading at (lat, lon) as the frame's grid heading (clockwise from grid north; the grid turns by the
/// meridian convergence, ≈ 1° over Israel).
pub fn grid_heading(lon: f64, lat: f64, heading: f64) -> f64 {
    let r = heading.to_radians();
    let step = 100.0;
    let (dlat, dlon) = (r.cos() * step / 111_320.0, r.sin() * step / (111_320.0 * lat.to_radians().cos()));
    let (p, q) = (utm36n(lon, lat), utm36n(lon + dlon, lat + dlat));
    bearing(p, q)
}

/// Grid bearing from p to q (degrees, 0..360).
fn bearing(p: [f64; 2], q: [f64; 2]) -> f64 {
    (q[0] - p[0]).atan2(q[1] - p[1]).to_degrees().rem_euclid(360.0)
}

fn lat_lon(v: &Value) -> Option<[f64; 2]> {
    // A place is {"lat", "lon"} or [lat, lon].
    let (lat, lon) = match v.as_array() {
        Some(a) => (a.first()?.as_f64()?, a.get(1)?.as_f64()?),
        None => (v["lat"].as_f64()?, v["lon"].as_f64()?),
    };
    Some(utm36n(lon, lat))
}

fn line(v: &Value) -> Vec<[f64; 2]> {
    v.as_array().into_iter().flatten().filter_map(lat_lon).collect()
}

// --- the bases ------------------------------------------------------------------------------------------------------

/// A runway in the frame. End k is where `designators[k]` takes off from (ends[0]: the low number's end).
#[derive(Debug, Clone)]
pub struct Runway {
    pub designators: [String; 2],
    pub ends: [[f64; 2]; 2],
    pub width: f64,
    /// The declared runway's start from each end (m along the centreline).
    pub starts: [f64; 2],
}

impl Runway {
    pub fn length(&self) -> f64 {
        (self.ends[1][0] - self.ends[0][0]).hypot(self.ends[1][1] - self.ends[0][1])
    }
    /// Unit vector from end k toward the other end.
    fn dir(&self, k: usize) -> [f64; 2] {
        let (a, b) = (self.ends[k], self.ends[1 - k]);
        let l = self.length();
        [(b[0] - a[0]) / l, (b[1] - a[1]) / l]
    }
    /// The take-off grid heading from end k.
    pub fn heading(&self, k: usize) -> f64 {
        bearing(self.ends[k], self.ends[1 - k])
    }
    /// The point `m` metres in from end k on the centreline.
    pub fn at(&self, k: usize, m: f64) -> [f64; 2] {
        let d = self.dir(k);
        [self.ends[k][0] + d[0] * m, self.ends[k][1] + d[1] * m]
    }
    /// The lineup point of end k: LINEUP_IN_M past the declared runway's start.
    pub fn lineup(&self, k: usize) -> [f64; 2] {
        self.at(k, self.starts[k] + LINEUP_IN_M)
    }
    /// The painted number of end k ("25R" → 25) and its letter.
    fn number(&self, k: usize) -> (i64, String) {
        let d = &self.designators[k];
        let digits: String = d.chars().take_while(char::is_ascii_digit).collect();
        (digits.parse().unwrap_or(0), d[digits.len()..].to_string())
    }
    /// Distance from p to the centreline segment.
    pub fn dist(&self, p: [f64; 2]) -> f64 {
        seg_dist(p, self.ends[0], self.ends[1])
    }
}

/// A parking spot: the start point of a unit's missions.
#[derive(Debug, Clone)]
pub struct Spot {
    pub unit: String,
    pub at: [f64; 2],
    /// The nose's grid heading.
    pub heading: f64,
}

#[derive(Debug, Clone)]
pub struct Base {
    pub icao: String,
    /// The iaf.ibx section and airbases.json name.
    pub section: String,
    pub name_en: String,
    pub elevation: f64,
    pub reference: [f64; 2],
    pub tower: Option<[f64; 2]>,
    pub boundary: Vec<[f64; 2]>,
    pub runways: Vec<Runway>,
    /// Centrelines with their widths (m).
    pub taxiways: Vec<(Vec<[f64; 2]>, f64)>,
    pub stopways: Vec<Vec<[f64; 2]>>,
    pub aprons: Vec<Vec<[f64; 2]>>,
    pub shelters: Vec<Vec<[f64; 2]>>,
    pub parking: Vec<Spot>,
    /// The take-off end: (runway index, end index).
    pub main: (usize, usize),
}

impl Base {
    /// The runway end named `designator` ("25R"): (runway, end).
    pub fn end(&self, designator: &str) -> Option<(usize, usize)> {
        self.runways
            .iter()
            .enumerate()
            .find_map(|(i, r)| r.designators.iter().position(|d| d == designator).map(|k| (i, k)))
    }
    /// The tower, else the reference point (most towers are open in OSM, airbases.md §5).
    pub fn tower_or_reference(&self) -> [f64; 2] {
        self.tower.unwrap_or(self.reference)
    }
    /// Paved at p, `margin` m past the edges: the mask's paved coverage (`mask`) as a test: within half the width of
    /// a runway's, stopway's or taxiway's centreline, or inside an apron or a shelter's pad.
    pub fn paved(&self, p: [f64; 2], margin: f64) -> bool {
        let near = |l: &[[f64; 2]], half: f64| l.windows(2).any(|s| seg_dist(p, s[0], s[1]) <= half + margin);
        let widest = self.runways.iter().map(|r| r.width).fold(0.0, f64::max);
        self.runways.iter().any(|r| r.dist(p) <= r.width / 2.0 + margin)
            || self.stopways.iter().any(|s| near(s, widest / 2.0))
            || self.taxiways.iter().any(|(l, w)| near(l, w / 2.0))
            || self
                .aprons
                .iter()
                .chain(&self.shelters)
                .any(|poly| inside(poly, p) || near(&[poly, &poly[..1]].concat(), 0.0))
    }
}

/// p inside `poly` (even-odd).
fn inside(poly: &[[f64; 2]], p: [f64; 2]) -> bool {
    let mut odd = false;
    for k in 0..poly.len() {
        let (a, b) = (poly[k], poly[(k + 1) % poly.len()]);
        if (a[1] > p[1]) != (b[1] > p[1]) && p[0] < a[0] + (p[1] - a[1]) / (b[1] - a[1]) * (b[0] - a[0]) {
            odd = !odd;
        }
    }
    odd
}

/// The bases from `<dir>/<icao>.json`, in BASES' order.
pub fn load(dir: &Path) -> Result<Vec<Base>> {
    BASES
        .iter()
        .map(|(icao, ..)| {
            let path = dir.join(format!("{}.json", icao.to_lowercase()));
            let v: Value =
                serde_json::from_slice(&std::fs::read(&path).with_context(|| format!("{}", path.display()))?)?;
            base(&v, &path.display().to_string())
        })
        .collect()
}

/// One base of BASES from its airbase file `v` (`what` names it in errors).
pub fn base(v: &Value, what: &str) -> Result<Base> {
    let icao = v["icao"].as_str().unwrap_or("");
    let (_, section, main) =
        BASES.iter().find(|b| b.0 == icao).with_context(|| format!("{what}: {icao:?} is none of the bases"))?;
    let mut runways = Vec::new();
    for r in v["runways"].as_array().with_context(|| format!("{what}: no runways"))? {
        let e = r["ends"]
            .as_array()
            .filter(|e| e.len() == 2)
            .with_context(|| format!("{what}: a runway needs two ends"))?;
        let at = |k: usize| lat_lon(&e[k]).with_context(|| format!("{what}: a runway end has no place"));
        runways.push(Runway {
            designators: [0, 1].map(|k| e[k]["designator"].as_str().unwrap_or("").to_string()),
            ends: [at(0)?, at(1)?],
            width: r["width_m"].as_f64().with_context(|| format!("{what}: a runway needs width_m"))?,
            starts: [0, 1].map(|k| e[k]["runway_start_m"].as_f64().unwrap_or(0.0)),
        });
    }
    let polys = |k: &str| -> Vec<Vec<[f64; 2]>> {
        v[k].as_array().into_iter().flatten().map(|a| line(&a["polygon"])).filter(|p| p.len() >= 3).collect()
    };
    let parking = v["parking"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|p| -> Result<Spot> {
            let (lat, lon) = (p["lat"].as_f64().context("parking lat")?, p["lon"].as_f64().context("parking lon")?);
            Ok(Spot {
                unit: p["unit"].as_str().unwrap_or("").to_string(),
                at: utm36n(lon, lat),
                heading: grid_heading(lon, lat, p["heading"].as_f64().context("parking heading")?),
            })
        })
        .collect::<Result<Vec<_>>>()?;
    let mut b = Base {
        icao: v["icao"].as_str().unwrap_or("").to_string(),
        section: section.to_string(),
        name_en: v["name"]["en"].as_str().unwrap_or("").to_string(),
        elevation: v["elevation_m"].as_f64().with_context(|| format!("{what}: no elevation_m"))?,
        reference: lat_lon(&v["reference"]).with_context(|| format!("{what}: no reference"))?,
        tower: lat_lon(&v["tower"]),
        boundary: line(&v["boundary"]),
        runways,
        taxiways: v["taxiways"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|t| (line(&t["points"]), t["width_m"].as_f64().unwrap_or(TAXIWAY_WIDTH_M)))
            .filter(|(p, _)| p.len() >= 2)
            .collect(),
        stopways: v["stopways"]
            .as_array()
            .into_iter()
            .flatten()
            .map(|t| line(&t["points"]))
            .filter(|p| p.len() >= 2)
            .collect(),
        aprons: polys("aprons"),
        shelters: polys("shelters"),
        parking,
        main: (0, 0),
    };
    b.main = b.end(main).with_context(|| format!("{what}: no runway end {main}"))?;
    ensure!(!b.parking.is_empty(), "{what}: no parking spot");
    Ok(b)
}

/// The base a mission names (`start.base`: its English name without " Airbase", e.g. "Ramat David").
pub fn by_name<'a>(bases: &'a [Base], name: &str) -> Option<&'a Base> {
    bases.iter().find(|b| b.name_en.trim_end_matches(" Airbase") == name || b.section == name)
}

// --- the AI's taxi paths --------------------------------------------------------------------------------------------

/// The taxiway network: the centrelines' points, joined where two ways share a point (rounded to the metre), and
/// along each runway between the points that lie on it (a jet crosses or backtracks there; at Ramat David the
/// taxiways meet only through the runways).
struct Graph {
    pts: Vec<[f64; 2]>,
    adj: Vec<Vec<(usize, f64)>>,
}

impl Graph {
    fn new(lines: &[(Vec<[f64; 2]>, f64)], runways: &[Runway]) -> Self {
        let mut g = Graph { pts: Vec::new(), adj: Vec::new() };
        let mut index: HashMap<(i64, i64), usize> = HashMap::new();
        let mut id = |g: &mut Graph, p: [f64; 2]| -> usize {
            let key = (p[0].round() as i64, p[1].round() as i64);
            *index.entry(key).or_insert_with(|| {
                g.pts.push(p);
                g.adj.push(Vec::new());
                g.pts.len() - 1
            })
        };
        for (l, _) in lines {
            for w in l.windows(2) {
                let (a, b) = (id(&mut g, w[0]), id(&mut g, w[1]));
                g.link(a, b);
            }
        }
        for r in runways {
            let mut on: Vec<(f64, usize)> = (0..g.pts.len())
                .filter(|&k| r.dist(g.pts[k]) <= r.width / 2.0 + 5.0)
                .map(|k| (dist(g.pts[k], r.ends[0]), k))
                .collect();
            on.sort_by(|a, b| a.0.total_cmp(&b.0));
            for w in on.windows(2) {
                g.link(w[0].1, w[1].1);
            }
        }
        g
    }

    fn link(&mut self, a: usize, b: usize) {
        if a != b {
            let d = dist(self.pts[a], self.pts[b]);
            self.adj[a].push((b, d));
            self.adj[b].push((a, d));
        }
    }

    fn nearest(&self, p: [f64; 2]) -> Option<usize> {
        (0..self.pts.len()).min_by(|&a, &b| dist(self.pts[a], p).total_cmp(&dist(self.pts[b], p)))
    }

    /// The shortest path from `a` to `b` (Dijkstra), its points; None when they are not joined.
    fn path(&self, a: usize, b: usize) -> Option<Vec<[f64; 2]>> {
        let mut best = vec![f64::INFINITY; self.pts.len()];
        let mut prev = vec![usize::MAX; self.pts.len()];
        let mut heap = BinaryHeap::new();
        best[a] = 0.0;
        // Non-negative f64s order as their bits.
        heap.push(std::cmp::Reverse((0f64.to_bits(), a)));
        while let Some(std::cmp::Reverse((d, k))) = heap.pop() {
            let d = f64::from_bits(d);
            if d > best[k] {
                continue;
            }
            if k == b {
                break;
            }
            for &(n, w) in &self.adj[k] {
                if d + w < best[n] {
                    best[n] = d + w;
                    prev[n] = k;
                    heap.push(std::cmp::Reverse(((d + w).to_bits(), n)));
                }
            }
        }
        if !best[b].is_finite() {
            return None;
        }
        let mut out = vec![self.pts[b]];
        let mut k = b;
        while k != a {
            k = prev[k];
            out.push(self.pts[k]);
        }
        out.reverse();
        Some(out)
    }
}

fn dist(a: [f64; 2], b: [f64; 2]) -> f64 {
    (a[0] - b[0]).hypot(a[1] - b[1])
}

fn seg_dist(p: [f64; 2], a: [f64; 2], b: [f64; 2]) -> f64 {
    let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
    let l2 = dx * dx + dy * dy;
    let t = if l2 > 0.0 { (((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2).clamp(0.0, 1.0) } else { 0.0 };
    dist(p, [a[0] + t * dx, a[1] + t * dy])
}

/// Ramer–Douglas–Peucker: the points within `tol` m of the line through the kept ones go.
fn simplify(p: &[[f64; 2]], tol: f64) -> Vec<[f64; 2]> {
    if p.len() < 3 {
        return p.to_vec();
    }
    let (a, b) = (p[0], p[p.len() - 1]);
    let (k, d) =
        (1..p.len() - 1).map(|k| (k, seg_dist(p[k], a, b))).fold((0, 0.0), |m, x| if x.1 > m.1 { x } else { m });
    if d <= tol {
        return vec![a, b];
    }
    let mut out = simplify(&p[..=k], tol);
    out.pop();
    out.extend(simplify(&p[k..], tol));
    out
}

/// The AI's routes of a base (iaf.ibx): `hub` is where every parking spot meets the taxiways (the first spot's
/// nearest taxiway point); `from` the hub → the take-off lineup (departure), `to` the landing roll's end → the hub
/// (arrival, from the far end's runway start, where a jet that landed on the take-off runway leaves it).
pub struct Routes {
    pub hub: [f64; 2],
    pub from: Vec<[f64; 2]>,
    pub to: Vec<[f64; 2]>,
}

pub fn routes(b: &Base) -> Result<Routes> {
    let g = Graph::new(&b.taxiways, &b.runways);
    let (ri, k) = b.main;
    let r = &b.runways[ri];
    let node = |p: [f64; 2]| g.nearest(p).with_context(|| format!("{}: no taxiways", b.icao));
    let hub = node(b.parking[0].at)?;
    // The departure joins the runway at its declared start (the first taxiway entry, airbases.md §4); the arrival
    // leaves it at the other end's start.
    let entry = node(r.at(k, r.starts[k]))?;
    let exit = node(r.at(1 - k, r.starts[1 - k]))?;
    let path = |a: usize, z: usize| {
        g.path(a, z).with_context(|| format!("{}: the taxiways do not join {:?} and {:?}", b.icao, g.pts[a], g.pts[z]))
    };
    let mut from = path(hub, entry)?;
    from.push(r.lineup(k));
    let mut to = vec![r.at(1 - k, r.starts[1 - k] + LINEUP_IN_M)];
    to.extend(path(exit, hub)?);
    Ok(Routes { hub: g.pts[hub], from: simplify(&from, 8.0), to: simplify(&to, 8.0) })
}

// --- taxiway signs --------------------------------------------------------------------------------------------------

/// A runway-holding sign's distance from the runway's centreline (m; ICAO Annex 14 Table 3-2: 90 m for a code 4
/// instrument runway, the bases' class).
const HOLD_M: f64 = 90.0;
/// A direction sign's distance before its junction (m; inferred: the boards stand before the turn, ICAO Annex 14
/// 5.4.3.30 and the Aerodrome Design Manual's 30–60 m).
const DIRECTION_BACK_M: f64 = 40.0;
/// A sign's offset from the taxiway's edge (m; Annex 14 Table 5-5: 11–21 m from the edge for code D–F taxiways).
const SIGN_EDGE_M: f64 = 12.0;

/// One board of a sign: `style` "mandatory" (white on red: a runway-holding position's runway designations, the
/// threshold on the left first) or "direction" (black on yellow: a runway designator and its arrow, `arrow` the turn
/// in degrees, positive to the right, 0 straight on).
#[derive(Debug, Clone, PartialEq)]
pub struct Panel {
    pub style: &'static str,
    pub text: String,
    pub arrow: Option<f64>,
}

/// A taxiway sign at `at` (UTM 36N) on the taxiing jet's left, its face looking along `facing` (grid degrees: the
/// way toward the jet that reads it), its boards left to right.
#[derive(Debug, Clone)]
pub struct Sign {
    pub at: [f64; 2],
    pub facing: f64,
    pub panels: Vec<Panel>,
}

fn grid_deg(d: [f64; 2]) -> f64 {
    d[0].atan2(d[1]).to_degrees().rem_euclid(360.0)
}

fn unit(a: [f64; 2], b: [f64; 2]) -> [f64; 2] {
    let l = dist(a, b).max(1e-9);
    [(b[0] - a[0]) / l, (b[1] - a[1]) / l]
}

/// The sign beside a jet at `p` taxiing along the unit `d`, facing it: SIGN_EDGE_M past the taxiway's edge on its
/// left, else farther out, else on its right (Annex 14 5.4.1.4), the first place off the paved surface (`paved`);
/// None when all are paved.
fn sign_at(p: [f64; 2], d: [f64; 2], half: f64, panels: Vec<Panel>, paved: &dyn Fn([f64; 2]) -> bool) -> Option<Sign> {
    let facing = grid_deg([-d[0], -d[1]]);
    [1.0, -1.0]
        .iter()
        .flat_map(|side| [0.0, 8.0, 18.0].map(|more| side * (half + SIGN_EDGE_M + more)))
        .map(|off| [p[0] - d[1] * off, p[1] + d[0] * off])
        // The board's ends too (a 3 m sign).
        .find(|q| [-2.0, 0.0, 2.0].iter().all(|k| !paved([q[0] + d[1] * k, q[1] - d[0] * k])))
        .map(|at| Sign { at, facing, panels })
}

/// The base's taxiway signs (ICAO Annex 14 §5.4): a runway-holding sign (mandatory) where each taxiway comes within
/// HOLD_M of a runway's centreline, and at each junction of three or more taxiways a direction sign before it on each
/// arriving taxiway, one board per other branch that leads to a runway (the designator of the end nearer where it
/// joins: the take-off away from it). OpenStreetMap names none of the bases' taxiways, so no location sign.
pub fn signs(b: &Base) -> Vec<Sign> {
    let g = Graph::new(&b.taxiways, &[]);
    let m = mask(b);
    let paved = |q: [f64; 2]| {
        let (x, y) = ((q[0] - m.origin[0]) / MASK_PX_M, (m.origin[1] - q[1]) / MASK_PX_M);
        x >= 0.0 && y >= 0.0 && (x as usize) < m.w && (y as usize) < m.h && m.img.get_pixel(x as u32, y as u32)[0] >= 64
    };
    let half = |p: [f64; 2]| {
        b.taxiways
            .iter()
            .filter(|(l, _)| l.windows(2).any(|s| seg_dist(p, s[0], s[1]) < 1.0))
            .map(|(_, w)| w / 2.0)
            .fold(TAXIWAY_WIDTH_M / 2.0, f64::max)
    };
    let on_runway = |p: [f64; 2]| b.runways.iter().position(|r| r.dist(p) <= r.width / 2.0 + 5.0);
    let mut out: Vec<Sign> = Vec::new();
    // Holding: walking each taxiway toward a runway, the point where it comes within HOLD_M of the centreline.
    for (l, w) in &b.taxiways {
        for line in [l.clone(), l.iter().rev().copied().collect::<Vec<_>>()] {
            for s in line.windows(2) {
                let Some(ri) = b.runways.iter().position(|r| r.dist(s[0]) > HOLD_M && r.dist(s[1]) <= HOLD_M) else {
                    continue;
                };
                let r = &b.runways[ri];
                // The crossing: bisect the segment.
                let (mut lo, mut hi) = (0.0, 1.0);
                for _ in 0..30 {
                    let m = (lo + hi) / 2.0;
                    let p = [s[0][0] + (s[1][0] - s[0][0]) * m, s[0][1] + (s[1][1] - s[0][1]) * m];
                    if r.dist(p) > HOLD_M { lo = m } else { hi = m }
                }
                let p = [s[0][0] + (s[1][0] - s[0][0]) * lo, s[0][1] + (s[1][1] - s[0][1]) * lo];
                let d = unit(s[0], s[1]);
                // The threshold on the jet's left first (left of d: d × (e − p) > 0).
                let left = |k: usize| {
                    let e = r.ends[k];
                    d[0] * (e[1] - p[1]) - d[1] * (e[0] - p[0]) > 0.0
                };
                let k = if left(0) { 0 } else { 1 };
                let text = format!("{}-{}", r.designators[k], r.designators[1 - k]);
                if out.iter().any(|o| dist(o.at, p) < 60.0 && o.panels[0].text == text) {
                    continue;
                }
                out.extend(sign_at(p, d, w / 2.0, vec![Panel { style: "mandatory", text, arrow: None }], &paved));
            }
        }
    }
    // The runway each branch leads to: from `next`, never back through `from`, the nearest point on a runway.
    let leads_to = |from: usize, next: usize| -> Option<String> {
        let mut best = vec![f64::INFINITY; g.pts.len()];
        let mut heap = BinaryHeap::new();
        best[next] = dist(g.pts[from], g.pts[next]);
        heap.push(std::cmp::Reverse((best[next].to_bits(), next)));
        while let Some(std::cmp::Reverse((d, k))) = heap.pop() {
            let d = f64::from_bits(d);
            if d > best[k] {
                continue;
            }
            if let Some(ri) = on_runway(g.pts[k]) {
                let r = &b.runways[ri];
                let e = if dist(g.pts[k], r.ends[0]) < dist(g.pts[k], r.ends[1]) { 0 } else { 1 };
                return Some(r.designators[e].clone());
            }
            for &(n, w) in &g.adj[k] {
                if n != from && d + w < best[n] {
                    best[n] = d + w;
                    heap.push(std::cmp::Reverse(((d + w).to_bits(), n)));
                }
            }
        }
        None
    };
    // The point DIRECTION_BACK_M back from the junction `j` along the branch through `n` (bends followed), and the
    // way a jet taxis there toward `j`; None when the branch ends sooner.
    let back = |j: usize, n: usize| -> Option<([f64; 2], [f64; 2])> {
        let (mut prev, mut cur, mut left) = (j, n, DIRECTION_BACK_M);
        loop {
            let seg = dist(g.pts[prev], g.pts[cur]);
            if seg >= left {
                let d = unit(g.pts[cur], g.pts[prev]);
                return Some(([g.pts[prev][0] - d[0] * left, g.pts[prev][1] - d[1] * left], d));
            }
            left -= seg;
            let nexts: Vec<usize> = g.adj[cur].iter().map(|a| a.0).filter(|&a| a != prev).collect();
            if nexts.len() != 1 {
                return None;
            }
            (prev, cur) = (cur, nexts[0]);
        }
    };
    for j in 0..g.pts.len() {
        let mut branches: Vec<usize> = g.adj[j].iter().map(|a| a.0).collect();
        branches.sort();
        branches.dedup();
        if branches.len() < 3 || on_runway(g.pts[j]).is_some() {
            continue;
        }
        let dests: Vec<(usize, Option<String>)> = branches.iter().map(|&n| (n, leads_to(j, n))).collect();
        for &arrive in &branches {
            let Some((p, d)) = back(j, arrive) else { continue };
            if on_runway(p).is_some() {
                continue;
            }
            let mut panels: Vec<Panel> = dests
                .iter()
                .filter(|(n, t)| *n != arrive && t.is_some())
                .map(|(n, t)| {
                    let o = unit(g.pts[j], g.pts[*n]);
                    // The turn from d to o, positive right (clockwise), to 45° steps.
                    let turn = (d[0] * o[1] - d[1] * o[0]).atan2(d[0] * o[0] + d[1] * o[1]).to_degrees();
                    Panel {
                        style: "direction",
                        text: t.clone().unwrap_or_default(),
                        arrow: Some((-turn / 45.0).round() * 45.0 + 0.0),
                    }
                })
                .collect();
            // Left to right, as the turns; one board per runway and turn.
            panels.sort_by(|a, b| a.arrow.unwrap_or(0.0).total_cmp(&b.arrow.unwrap_or(0.0)).then(a.text.cmp(&b.text)));
            panels.dedup();
            if !panels.is_empty() {
                out.extend(sign_at(p, d, half(p), panels, &paved));
            }
        }
    }
    out
}

// --- heights --------------------------------------------------------------------------------------------------------

/// The theatre's ground heights (its level-6 height nodes, sampled as the game's height_at), loaded per node.
pub struct Ground {
    dir: std::path::PathBuf,
    meta: iaf_avionics::heights::Meta,
    field: iaf_avionics::heights::HeightField,
    loaded: std::collections::HashSet<(i64, i64)>,
}

impl Ground {
    /// The theatre at `dir` (its meta.json); None without one.
    pub fn open(dir: &Path) -> Option<Self> {
        let m: Value = serde_json::from_slice(&std::fs::read(dir.join("meta.json")).ok()?).ok()?;
        let f = |k: &str| m[k].as_f64().unwrap_or(0.0);
        let meta = iaf_avionics::heights::Meta {
            node_pixels: f("node_pixels") as usize,
            span: f("node_pixels") * 2f64.powi(f("height_level") as i32),
            sea_level_raw: f("sea_level_raw"),
            height_scale: f("height_scale"),
            m_per_unit: f("units_to_metres"),
            x_shift: f("x_shift"),
            y_shift: f("y_shift"),
        };
        let mut field = iaf_avionics::heights::HeightField::default();
        field.set_meta(meta);
        Some(Self { dir: dir.to_path_buf(), meta, field, loaded: Default::default() })
    }

    /// Frees the loaded nodes of the node rows north of the one holding northing `y` (a sweep southward needs them
    /// no more: each node is 2 MB).
    pub fn forget_north_of(&mut self, y: f64) {
        let row = ((self.meta.y_shift - y) / self.meta.m_per_unit / self.meta.span).floor() as i64;
        let gone: Vec<(i64, i64)> = self.loaded.iter().copied().filter(|k| k.1 < row).collect();
        for k in gone {
            self.loaded.remove(&k);
            self.field.remove(k.0, k.1);
        }
    }

    /// The ground (m) at world (x, y); None outside the theatre's height nodes.
    pub fn at(&mut self, x: f64, y: f64) -> Option<f64> {
        let m = self.meta;
        let (tx, ty) = ((x - m.x_shift) / m.m_per_unit, (m.y_shift - y) / m.m_per_unit);
        let k = ((tx / m.span).floor() as i64, (ty / m.span).floor() as i64);
        if self.loaded.insert(k) {
            let img = image::open(self.dir.join(format!("L6/h_{}_{}.png", k.0, k.1))).ok()?.to_rgb8();
            let rg8: Vec<u8> = img.pixels().flat_map(|p| [p[0], p[1]]).collect();
            self.field.add(k.0, k.1, img.width() as usize, &rg8);
        }
        self.field.height(iaf_avionics::Vec3::new(x, y, 0.0))
    }
}

// --- the paved-surface mask -----------------------------------------------------------------------------------------

/// A base's mask: R = paved coverage (runways, stopways, taxiways, aprons, shelters' pads), G = concrete (aprons and
/// shelters) blurred over ≈ 5 m, B = the distance to the nearest taxiway centreline (0 … TAXI_FIELD_M → 0 … 255).
pub struct Mask {
    pub origin: [f64; 2],
    pub w: usize,
    pub h: usize,
    pub img: image::RgbImage,
}

pub fn mask(b: &Base) -> Mask {
    let pts = b.boundary.iter().chain(b.runways.iter().flat_map(|r| r.ends.iter()));
    let bb = pts.fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |a, p| {
        [a[0].min(p[0]), a[1].min(p[1]), a[2].max(p[0]), a[3].max(p[1])]
    });
    let origin = [bb[0] - MASK_MARGIN_M, bb[3] + MASK_MARGIN_M];
    let (w, h) = (
        ((bb[2] - bb[0] + 2.0 * MASK_MARGIN_M) / MASK_PX_M).ceil() as usize,
        ((bb[3] - bb[1] + 2.0 * MASK_MARGIN_M) / MASK_PX_M).ceil() as usize,
    );
    let centre =
        |x: usize, y: usize| [origin[0] + (x as f64 + 0.5) * MASK_PX_M, origin[1] - (y as f64 + 0.5) * MASK_PX_M];
    // Straight into the image's bytes (R, G, B per pixel): float planes over a whole base took 250 MB at Nevatim.
    let mut img = image::RgbImage::from_pixel(w as u32, h as u32, image::Rgb([0, 0, 255]));
    let px = img.as_mut();
    let byte = |v: f64| (v * 255.0).round().clamp(0.0, 255.0) as u8;
    // A thick line: coverage from the distance to its centreline (a pixel's width of soft edge), and the distance.
    let stroke = |px: &mut [u8], l: &[[f64; 2]], half: f64, taxi_line: bool| {
        let reach = half.max(if taxi_line { TAXI_FIELD_M } else { 0.0 }) + MASK_PX_M;
        for s in l.windows(2) {
            let x0 = (((s[0][0].min(s[1][0]) - reach - origin[0]) / MASK_PX_M).floor().max(0.0) as usize).min(w);
            let x1 = (((s[0][0].max(s[1][0]) + reach - origin[0]) / MASK_PX_M).ceil().max(0.0) as usize).min(w);
            let y0 = (((origin[1] - s[0][1].max(s[1][1]) - reach) / MASK_PX_M).floor().max(0.0) as usize).min(h);
            let y1 = (((origin[1] - s[0][1].min(s[1][1]) + reach) / MASK_PX_M).ceil().max(0.0) as usize).min(h);
            for y in y0..y1 {
                for x in x0..x1 {
                    let d = seg_dist(centre(x, y), s[0], s[1]);
                    let i = (y * w + x) * 3;
                    px[i] = px[i].max(byte((half - d) / MASK_PX_M + 0.5));
                    if taxi_line {
                        px[i + 2] = px[i + 2].min(byte(d / TAXI_FIELD_M));
                    }
                }
            }
        }
    };
    for r in &b.runways {
        stroke(px, &r.ends, r.width / 2.0, false);
    }
    let widest = b.runways.iter().map(|r| r.width).fold(0.0, f64::max);
    for s in &b.stopways {
        stroke(px, s, widest / 2.0, false);
    }
    for (l, wd) in &b.taxiways {
        stroke(px, l, wd / 2.0, true);
    }
    for p in b.aprons.iter().chain(&b.shelters) {
        fill_spans(w, h, origin, MASK_PX_M, &[p], |y, x0, x1| {
            for x in x0..x1 {
                px[(y * w + x) * 3] = 255;
                px[(y * w + x) * 3 + 1] = 255;
            }
        });
    }
    // Concrete over ≈ 5 m: two 3-pixel box passes on the green channel.
    for _ in 0..2 {
        box3(px, w, h, 1, 3);
    }
    Mask { origin, w, h, img }
}

/// A 3-pixel box blur of channel `c` of an interleaved image with `n` channels (rows, then columns).
fn box3(px: &mut [u8], w: usize, h: usize, c: usize, n: usize) {
    let get = |px: &[u8], x: usize, y: usize| u16::from(px[(y * w + x) * n + c]);
    let mut tmp = vec![0u8; w * h];
    for y in 0..h {
        for x in 0..w {
            let (a, b) = (get(px, x.saturating_sub(1), y), get(px, (x + 1).min(w - 1), y));
            tmp[y * w + x] = ((a + get(px, x, y) + b + 1) / 3) as u8;
        }
    }
    for y in 0..h {
        for x in 0..w {
            let t = |y: usize| u16::from(tmp[y * w + x]);
            px[(y * w + x) * n + c] = ((t(y.saturating_sub(1)) + t(y) + t((y + 1).min(h - 1)) + 1) / 3) as u8;
        }
    }
}

/// Sets to 1 the pixels whose centre lies inside `poly` (even-odd), on a grid of `cell` m whose north-west corner is
/// `origin` (rows run south).
pub fn fill_polygon(m: &mut [f32], w: usize, h: usize, origin: [f64; 2], cell: f64, poly: &[[f64; 2]]) {
    fill_spans(w, h, origin, cell, &[poly], |y, x0, x1| m[y * w + x0..y * w + x1].fill(1.0));
}

/// Calls `span(y, x0, x1)` for each row's run of pixels whose centre lies inside the rings (even-odd over all of
/// them: a hole is a ring inside another), over the rows of their box.
pub fn fill_spans(
    w: usize,
    h: usize,
    origin: [f64; 2],
    cell: f64,
    rings: &[&[[f64; 2]]],
    mut span: impl FnMut(usize, usize, usize),
) {
    let (lo, hi) =
        rings.iter().flat_map(|r| r.iter()).fold((f64::MAX, f64::MIN), |(l, u), p| (l.min(p[1]), u.max(p[1])));
    let y0 = (((origin[1] - hi) / cell - 0.5).floor().max(0.0) as usize).min(h);
    let y1 = (((origin[1] - lo) / cell + 0.5).ceil().max(0.0) as usize).min(h);
    for y in y0..y1 {
        let northing = origin[1] - (y as f64 + 0.5) * cell;
        let mut xs = Vec::new();
        for poly in rings {
            for k in 0..poly.len() {
                let (a, b) = (poly[k], poly[(k + 1) % poly.len()]);
                if (a[1] > northing) != (b[1] > northing) {
                    xs.push(a[0] + (northing - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
                }
            }
        }
        xs.sort_by(f64::total_cmp);
        for s in xs.as_chunks::<2>().0 {
            let x0 = (((s[0] - origin[0]) / cell - 0.5).ceil().max(0.0) as usize).min(w);
            let x1 = (((s[1] - origin[0]) / cell - 0.5).floor() as isize + 1).clamp(0, w as isize) as usize;
            span(y, x0, x1.max(x0));
        }
    }
}

// --- terraintype.dat ------------------------------------------------------------------------------------------------

/// A BSP node: a leaf's flags, or a split `a·x + b·y < c` (child0) / else (child1) in the lookup's shifted frame.
enum Node {
    Leaf(i32),
    Split([f64; 3], Box<Node>, Box<Node>),
}

/// terraintype.dat's lookup shifts world metres by (+0x151, −0x19a) and truncates (iaf_formats::terrain_types::at).
const SHIFT: [f64; 2] = [337.0, -410.0];

/// The pre-order bytes (i32 count, mask, has1, has0, the plane as 4 f64 when it splits, child1, then child0).
fn write_node(n: &Node, out: &mut Vec<u8>) {
    match n {
        Node::Leaf(m) => {
            for v in [0, *m, 0, 0] {
                out.extend(v.to_le_bytes());
            }
        }
        Node::Split(p, c0, c1) => {
            for v in [0i32, 0, 1, 1] {
                out.extend(v.to_le_bytes());
            }
            for v in [p[0], p[1], p[2], 0.0] {
                out.extend(v.to_le_bytes());
            }
            write_node(c1, out);
            write_node(c0, out);
        }
    }
}

/// child0 where x < v (world metres); one leaf when both sides are the same leaf.
fn split_x(v: f64, west: Node, east: Node) -> Node {
    split([1.0, 0.0, v + SHIFT[0]], west, east)
}

/// child0 where y < v (world metres); one leaf when both sides are the same leaf.
fn split_y(v: f64, south: Node, north: Node) -> Node {
    split([0.0, 1.0, v + SHIFT[1]], south, north)
}

fn split(p: [f64; 3], c0: Node, c1: Node) -> Node {
    match (&c0, &c1) {
        (Node::Leaf(a), Node::Leaf(b)) if a == b => c0,
        _ => Node::Split(p, Box::new(c0), Box::new(c1)),
    }
}

/// The runways' rectangles (each a convex quad: centreline ends ± half the width) over the `ground` leaf (LAND or
/// PAVED), as nested half-plane tests; a point outside one goes on to the next.
fn runway_chain(rects: &[[[f64; 2]; 4]], ground: i32) -> Node {
    let Some((q, rest)) = rects.split_first() else { return Node::Leaf(ground) };
    let mut n = Node::Leaf(RUNWAY);
    // Each edge a→b of the counter-clockwise quad: inside is to its left.
    for k in (0..4).rev() {
        let (a, b) = (q[k], q[(k + 1) % 4]);
        // left of a→b: (b−a) × (p−a) > 0 ⇔ −dy·x + dx·y > −dy·ax + dx·ay; child0 (<) is outside.
        let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
        let c = -dy * (a[0] + SHIFT[0]) + dx * (a[1] + SHIFT[1]);
        n = Node::Split([-dy, dx, c], Box::new(runway_chain(rest, ground)), Box::new(n));
    }
    n
}

/// The water of a theatre per WATER_CELL_M square (`cells[j * nx + i]` from the north-west corner, rows run south):
/// 0 land, else its terraintype.dat flag (SEA or INLAND_WATER).
pub struct WaterGrid<'a> {
    nx: usize,
    ny: usize,
    cells: &'a [u8],
}

impl<'a> WaterGrid<'a> {
    pub fn new(nx: usize, ny: usize, cells: &'a [u8]) -> Self {
        Self { nx, ny, cells }
    }
    /// The block [i0, i1) × [j0, j1)'s value when all of it has one; None when mixed. The scan stops at the first
    /// cell that differs, so the tree's build reads each cell about once per level.
    fn uniform(&self, i0: usize, i1: usize, j0: usize, j1: usize) -> Option<u8> {
        let first = self.cells[j0 * self.nx + i0];
        (j0..j1).all(|j| self.cells[j * self.nx + i0..j * self.nx + i1].iter().all(|&c| c == first)).then_some(first)
    }
}

/// The surface tree over the theatre rect `r` (E0, N0, E1, N1): the water as a quadtree of axis splits, the runways
/// in the land blocks they touch.
fn surface_tree(r: [f64; 4], s: &Surface, rects: &[[[f64; 2]; 4]]) -> Node {
    struct Ctx<'a> {
        w: &'a WaterGrid<'a>,
        paved: &'a [Paved],
        coast: &'a crate::sim_coast::Coast,
        rects: &'a [[[f64; 2]; 4]],
        r: [f64; 4],
    }
    // A land or sea block near the coastline: split down to COAST_LEAF_M where the coastline crosses it, each part
    // the sea or land by its side.
    fn shore(b: [f64; 4], grid: u8, c: &Ctx) -> Node {
        let leaf = |sea: bool| if sea { Node::Leaf(SEA) } else { land_tree(b, c.paved, c.rects) };
        let m = [(b[0] + b[2]) / 2.0, (b[1] + b[3]) / 2.0];
        let (w, h) = (b[2] - b[0], b[3] - b[1]);
        let Some(side) = c.coast.sea(m) else { return leaf(grid == SEA as u8) };
        if w.max(h) <= COAST_LEAF_M || !c.coast.near(m, 0.5 * w.hypot(h)) {
            return leaf(side);
        }
        if w >= h {
            split_x(m[0], shore([b[0], b[1], m[0], b[3]], grid, c), shore([m[0], b[1], b[2], b[3]], grid, c))
        } else {
            split_y(m[1], shore([b[0], b[1], b[2], m[1]], grid, c), shore([b[0], m[1], b[2], b[3]], grid, c))
        }
    }
    // Cells [i0, i1) × [j0, j1): one leaf when uniform, else split the longer side.
    fn build(i0: usize, i1: usize, j0: usize, j1: usize, c: &Ctx) -> Node {
        let Ctx { w, paved, coast, rects, r } = *c;
        let cx = |i: usize| (r[0] + i as f64 * WATER_CELL_M).min(r[2]);
        let cy = |j: usize| (r[3] - j as f64 * WATER_CELL_M).max(r[1]);
        let b = [cx(i0), cy(j1), cx(i1), cy(j0)];
        let g = w.uniform(i0, i1, j0, j1);
        // A uniform land or sea block the coastline reaches: split to 8 × 8 cells, then along the coastline.
        let shore_side = g.is_some_and(|g| g == 0 || g == SEA as u8) && coast.touches(b);
        match g {
            Some(g) if shore_side && (i1 - i0) * (j1 - j0) <= 64 => shore(b, g, c),
            Some(0) if !shore_side => land_tree(b, paved, rects),
            Some(f) if !shore_side => Node::Leaf(f as i32),
            _ if i1 - i0 >= j1 - j0 && i1 - i0 > 1 => {
                let m = (i0 + i1) / 2;
                split_x(cx(m), build(i0, m, j0, j1, c), build(m, i1, j0, j1, c))
            }
            _ => {
                let m = (j0 + j1) / 2;
                // Rows run south: j ≥ m is the south part.
                split_y(cy(m), build(i0, i1, m, j1, c), build(i0, i1, j0, m, c))
            }
        }
    }
    build(0, s.water.nx, 0, s.water.ny, &Ctx { w: s.water, paved: s.paved, coast: s.coast, rects, r })
}

/// A runway's rectangle, counter-clockwise.
fn rect(r: &Runway) -> [[f64; 2]; 4] {
    let d = r.dir(0);
    let n = [-d[1] * r.width / 2.0, d[0] * r.width / 2.0];
    let (a, b) = (r.ends[0], r.ends[1]);
    [[a[0] - n[0], a[1] - n[1]], [b[0] - n[0], b[1] - n[1]], [b[0] + n[0], b[1] + n[1]], [a[0] + n[0], a[1] + n[1]]]
}

/// What terraintype.dat is made of besides the runways: the water per WATER_CELL_M cell, the coastline (the sea's
/// boundary within its reach, to COAST_LEAF_M) and the bases' paved surface.
pub struct Surface<'a> {
    pub water: &'a WaterGrid<'a>,
    pub coast: &'a crate::sim_coast::Coast,
    pub paved: &'a [Paved],
}

/// terraintype.dat's bytes for the theatre rect `r`: the water (the coastline's side near it), the bases' paved
/// surface (PAVED) and the runways (RUNWAY).
pub fn terraintype(r: [f64; 4], s: &Surface, runways: &[&Runway]) -> Vec<u8> {
    let rects: Vec<_> = runways.iter().map(|r| rect(r)).collect();
    let mut out = Vec::new();
    write_node(&surface_tree(r, s, &rects), &mut out);
    out
}

/// A base's paved surface (runways, stopways, taxiways, aprons, shelters' pads) on a PAVED_CELL_M grid from its mask:
/// a cell is paved when any of its mask pixels is half covered or more. Rows run south from `origin` (north-west).
pub struct Paved {
    origin: [f64; 2],
    nx: usize,
    ny: usize,
    cells: Vec<bool>,
}

impl Paved {
    pub fn new(m: &Mask) -> Self {
        let k = (PAVED_CELL_M / MASK_PX_M) as usize;
        let (nx, ny) = (m.w.div_ceil(k), m.h.div_ceil(k));
        let mut cells = vec![false; nx * ny];
        for (x, y, p) in m.img.enumerate_pixels() {
            if p[0] >= 128 {
                cells[y as usize / k * nx + x as usize / k] = true;
            }
        }
        Self { origin: m.origin, nx, ny, cells }
    }

    /// The mask's paved surface and the AI's taxi paths of `rt` from every parking spot of `b` (each spot to the hub,
    /// the hub to the lineup, the landing roll's end to the hub) at TAXIWAY_WIDTH_M: where OpenStreetMap maps no
    /// taxiway along a computed path (Hatzerim's Sufa spot to its hub, 140 m of sand), the jet still rolls on paved
    /// ground.
    pub fn with_paths(m: &Mask, b: &Base, rt: &Routes) -> Self {
        let mut p = Self::new(m);
        let half = TAXIWAY_WIDTH_M / 2.0;
        let mut lines: Vec<Vec<[f64; 2]>> = b.parking.iter().map(|s| vec![s.at, rt.hub]).collect();
        lines.push(rt.from.clone());
        lines.push(rt.to.clone());
        for l in &lines {
            for s in l.windows(2) {
                let (lo, hi) = (
                    [s[0][0].min(s[1][0]) - half, s[0][1].min(s[1][1]) - half],
                    [s[0][0].max(s[1][0]) + half, s[0][1].max(s[1][1]) + half],
                );
                let (i0, i1, j0, j1) = p.range([lo[0], lo[1], hi[0], hi[1]]);
                for j in j0.saturating_sub(1)..(j1 + 1).min(p.ny) {
                    for i in i0.saturating_sub(1)..(i1 + 1).min(p.nx) {
                        let c = [p.x(i) + PAVED_CELL_M / 2.0, p.y(j) - PAVED_CELL_M / 2.0];
                        if seg_dist(c, s[0], s[1]) <= half {
                            p.cells[j * p.nx + i] = true;
                        }
                    }
                }
            }
        }
        p
    }

    /// The grid's cells [i0, i1) × [j0, j1) that meet the world rect `b` (W, S, E, N), clamped; empty when outside. A
    /// cell cut by the rect's edge is in it, so each side of a cut through the grid keeps its part of the cell.
    fn range(&self, b: [f64; 4]) -> (usize, usize, usize, usize) {
        let at = |v: f64, n: usize| (v.max(0.0) as usize).min(n);
        let (x0, x1) = ((b[0] - self.origin[0]) / PAVED_CELL_M, (b[2] - self.origin[0]) / PAVED_CELL_M);
        let (y0, y1) = ((self.origin[1] - b[3]) / PAVED_CELL_M, (self.origin[1] - b[1]) / PAVED_CELL_M);
        (at(x0.floor(), self.nx), at(x1.ceil(), self.nx), at(y0.floor(), self.ny), at(y1.ceil(), self.ny))
    }

    fn x(&self, i: usize) -> f64 {
        self.origin[0] + i as f64 * PAVED_CELL_M
    }

    fn y(&self, j: usize) -> f64 {
        self.origin[1] - j as f64 * PAVED_CELL_M
    }
}

/// The runways' rectangles that meet the world rect `b` (W, S, E, N), or the one that holds all of it.
enum Near {
    Some(Vec<[[f64; 2]; 4]>),
    Inside,
}

fn runways_near(rects: &[[[f64; 2]; 4]], b: [f64; 4]) -> Near {
    let corners = [[b[0], b[1]], [b[2], b[1]], [b[2], b[3]], [b[0], b[3]]];
    let mut out = Vec::new();
    for q in rects {
        // Left of a→b (inside the counter-clockwise quad) for each edge.
        let side = |k: usize, p: [f64; 2]| {
            let (a, e) = (q[k], q[(k + 1) % 4]);
            (e[0] - a[0]) * (p[1] - a[1]) - (e[1] - a[1]) * (p[0] - a[0])
        };
        if corners.iter().all(|&c| (0..4).all(|k| side(k, c) >= 0.0)) {
            return Near::Inside;
        }
        // Separated: the box beside the quad's box, or wholly outside one of its edges.
        let bx = q.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, p| {
            [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
        });
        let apart = !(bx[0] < b[2] && b[0] < bx[2] && bx[1] < b[3] && b[1] < bx[3])
            || (0..4).any(|k| corners.iter().all(|&c| side(k, c) < 0.0));
        if !apart {
            out.push(*q);
        }
    }
    Near::Some(out)
}

/// A land block `b` (W, S, E, N): LAND, with the bases' paved cells in it as PAVED leaves (a quadtree on their grid)
/// and the runways over both.
fn land_tree(b: [f64; 4], paved: &[Paved], rects: &[[[f64; 2]; 4]]) -> Node {
    let hits: Vec<&Paved> = paved
        .iter()
        .filter(|p| {
            let (i0, i1, j0, j1) = p.range(b);
            i0 < i1 && j0 < j1
        })
        .collect();
    let leaf = |g: i32| match runways_near(rects, b) {
        Near::Inside => Node::Leaf(RUNWAY),
        Near::Some(near) => runway_chain(&near, g),
    };
    let Some(p) = hits.first() else { return leaf(LAND) };
    let (i0, i1, j0, j1) = p.range(b);
    let (x0, x1, y0, y1) = (p.x(i0), p.x(i1), p.y(j1), p.y(j0));
    // Off the grid's part (or another base's grid in the block): cut it off first.
    if b[0] < x0 - 0.01 {
        return split_x(
            x0,
            land_tree([b[0], b[1], x0, b[3]], paved, rects),
            land_tree([x0, b[1], b[2], b[3]], paved, rects),
        );
    }
    if x1 < b[2] - 0.01 {
        return split_x(
            x1,
            land_tree([b[0], b[1], x1, b[3]], paved, rects),
            land_tree([x1, b[1], b[2], b[3]], paved, rects),
        );
    }
    if b[1] < y0 - 0.01 {
        return split_y(
            y0,
            land_tree([b[0], b[1], b[2], y0], paved, rects),
            land_tree([b[0], y0, b[2], b[3]], paved, rects),
        );
    }
    if y1 < b[3] - 0.01 {
        return split_y(
            y1,
            land_tree([b[0], b[1], b[2], y1], paved, rects),
            land_tree([b[0], y1, b[2], b[3]], paved, rects),
        );
    }
    let n = (j0..j1).map(|j| p.cells[j * p.nx + i0..j * p.nx + i1].iter().filter(|&&c| c).count()).sum::<usize>();
    if n == 0 {
        return leaf(LAND);
    }
    if n == (i1 - i0) * (j1 - j0) {
        return leaf(PAVED);
    }
    if i1 - i0 >= j1 - j0 {
        let xm = p.x((i0 + i1) / 2);
        split_x(xm, land_tree([b[0], b[1], xm, b[3]], paved, rects), land_tree([xm, b[1], b[2], b[3]], paved, rects))
    } else {
        // Rows run south: the row m's north edge.
        let ym = p.y((j0 + j1) / 2);
        split_y(ym, land_tree([b[0], b[1], b[2], ym], paved, rects), land_tree([b[0], ym, b[2], b[3]], paved, rects))
    }
}

/// The sea on the theatre's WATER_CELL_M grid: the cells at 0 m (`zero`: GLO-30's sea surface; its missing tiles
/// are 0 m in the terrain's height nodes too) joined to the theatre's edge, so a lake below or above sea level is not
/// sea (the inland water is OpenStreetMap's, `water_polygons`). A breadth-first fill, cells marked as they are queued: the queue holds
/// the fill's front (a few thousand cells), not the sea.
pub fn sea_cells(nx: usize, ny: usize, zero: &[bool]) -> Vec<bool> {
    let edge = (0..nx).flat_map(|i| [i, (ny - 1) * nx + i]).chain((0..ny).flat_map(|j| [j * nx, j * nx + nx - 1]));
    flood(nx, ny, zero, edge)
}

/// The cells of an `nx` × `ny` grid that `pass` lets through and that join a cell of `seeds` (one that `pass` lets
/// through) by their sides.
pub fn flood(nx: usize, ny: usize, pass: &[bool], seeds: impl IntoIterator<Item = usize>) -> Vec<bool> {
    let mut sea = vec![false; nx * ny];
    let mut queue = std::collections::VecDeque::new();
    let push = |k: usize, sea: &mut Vec<bool>, queue: &mut std::collections::VecDeque<u32>| {
        if pass[k] && !sea[k] {
            sea[k] = true;
            queue.push_back(k as u32);
        }
    };
    for k in seeds {
        push(k, &mut sea, &mut queue);
    }
    while let Some(k) = queue.pop_front() {
        let k = k as usize;
        let (i, j) = (k % nx, k / nx);
        if i > 0 {
            push(k - 1, &mut sea, &mut queue);
        }
        if i + 1 < nx {
            push(k + 1, &mut sea, &mut queue);
        }
        if j > 0 {
            push(k - nx, &mut sea, &mut queue);
        }
        if j + 1 < ny {
            push(k + nx, &mut sea, &mut queue);
        }
    }
    sea
}

// --- iaf.ibx --------------------------------------------------------------------------------------------------------

/// A base's iaf.ibx section (keys: iaf-2026/docs/data-formats.md §12).
fn ibx_section(b: &Base, rt: &Routes, z: &mut dyn FnMut([f64; 2]) -> f64) -> String {
    let (ri, k) = b.main;
    let r = &b.runways[ri];
    let tower = b.tower_or_reference();
    let lineup = r.lineup(k);
    let mut s = format!(
        "[{}]\n; {} ({}), iaf-sim airbases from iaf-2026/data/airbases/{}.json\n",
        b.section,
        b.name_en,
        b.icao,
        b.icao.to_lowercase()
    );
    s += &format!("TowerLocX={:.1}\nTowerLocY={:.1}\nTowerLocZ={:.1}\n", tower[0], tower[1], z(tower));
    s += &format!("LineupLocX={:.1}\nLineupLocY={:.1}\nLineupLocZ={:.1}\n", lineup[0], lineup[1], z(lineup));
    // The reader truncates RunwayNumber to whole degrees (Section::i32): rounded here.
    s += &format!("RunwayNumber={}\n", r.heading(k).round().rem_euclid(360.0));
    let path = |s: &mut String, prefix: &str, count: &str, p: &[[f64; 2]], last: f64| {
        *s += &format!("{count}={}\n", p.len());
        for (i, q) in p.iter().enumerate() {
            let h = p.get(i + 1).map_or(last, |n| bearing(*q, *n));
            *s += &format!("{prefix}X{i}={:.1}\n{prefix}Y{i}={:.1}\n{prefix}Hdg{i}={:.0}\n", q[0], q[1], h.round());
        }
    };
    // The arrival ends at the hub, its last leg toward the first spot.
    path(&mut s, "ToTaxiPt", "TaxiWayPtsTo", &rt.to, bearing(rt.hub, b.parking[0].at));
    path(&mut s, "FromTaxiPt", "TaxiWayPtsFrom", &rt.from, r.heading(k));
    s += &format!("HangarsNum={}\n", b.parking.len());
    for (i, p) in b.parking.iter().enumerate() {
        let to_spot = bearing(rt.hub, p.at);
        // The departure's first point is the hub itself: leave it toward the next one.
        let from_spot = rt.from.get(1).map_or(to_spot, |f| bearing(rt.hub, *f));
        s += &format!(
            "ToHangarTurnPtX{i}={:.1}\nToHangarTurnPtY{i}={:.1}\nToHangarTurnPtHdg{i}={:.0}\n",
            rt.hub[0],
            rt.hub[1],
            to_spot.round()
        );
        s += &format!(
            "HangarPtX{i}={:.1}\nHangarPtY{i}={:.1}\nHangarPtHdg{i}={:.0}\n",
            p.at[0],
            p.at[1],
            p.heading.round()
        );
        s += &format!(
            "FromHangarTurnPtX{i}={:.1}\nFromHangarTurnPtY{i}={:.1}\nFromHangarTurnPtHdg{i}={:.0}\n",
            rt.hub[0],
            rt.hub[1],
            from_spot.round()
        );
    }
    s + "\n"
}

// --- the run --------------------------------------------------------------------------------------------------------

/// `iaf-sim airbases`: the bases into `<assets>/converted/terrain/israel/` (airbases.json, masks) and
/// `<assets>/converted/own/` (iaf.ibx, terraintype.dat). Needs the theatre (`iaf-sim terrain`) for the heights.
pub fn airbases(data: &Path, assets: &Path, pr: &dyn Progress, cancel: &AtomicBool) -> Result<()> {
    let bases = load(&data.join("airbases"))?;
    let theatre = assets.join("converted/terrain/israel");
    let mut ground =
        Ground::open(&theatre).with_context(|| format!("{}: no theatre (iaf-sim terrain)", theatre.display()))?;
    let own = assets.join("converted/own");
    std::fs::create_dir_all(theatre.join("airbases"))?;
    std::fs::create_dir_all(&own)?;
    let r1 = |v: f64| (v * 10.0).round() / 10.0;
    let pt = |p: [f64; 2]| json!([r1(p[0]), r1(p[1])]);
    let mut list = Vec::new();
    let mut ibx = String::from(
        "; Modern IAF's airbases (iaf-sim airbases; iaf-2026/docs/data-formats.md §12). World metres: UTM 36N.\n\n",
    );
    let mut paved = Vec::new();
    for b in &bases {
        check(cancel)?;
        let rt = routes(b)?;
        let mut z = |p: [f64; 2]| ground.at(p[0], p[1]).unwrap_or(b.elevation);
        ibx += &ibx_section(b, &rt, &mut z);
        let m = mask(b);
        let file = format!("israel/airbases/{}.png", b.section.to_lowercase());
        m.img.save(assets.join("converted/terrain").join(&file))?;
        paved.push(Paved::with_paths(&m, b, &rt));
        // The take-off runway first (the tower's wind turn takes airbases.json's first runway).
        let mut order: Vec<usize> = (0..b.runways.len()).collect();
        order.sort_by_key(|&i| i != b.main.0);
        let runways: Vec<Value> = order
            .iter()
            .map(|&i| {
                let r = &b.runways[i];
                let ((n0, l0), (n1, l1)) = (r.number(0), r.number(1));
                json!({
                    "ends": [pt(r.ends[0]), pt(r.ends[1])], "width": r1(r.width), "heading": (r.heading(0) * 100.0).round() / 100.0,
                    "length": r1(r.length()), "numbers": [n0, n1], "letters": [l0, l1], "thresholds": [r1(r.starts[0]), r1(r.starts[1])],
                    "designators": r.designators, "lineups": [pt(r.lineup(0)), pt(r.lineup(1))],
                })
            })
            .collect();
        let (ri, k) = b.main;
        list.push(json!({
            "name": b.section, "icao": b.icao, "lineup": pt(b.runways[ri].lineup(k)),
            "runway_deg": b.runways[ri].heading(k).round().rem_euclid(360.0), "runways": runways,
            "taxi": b.taxiways.iter().map(|(l, _)| l.iter().map(|p| pt(*p)).collect::<Vec<_>>()).collect::<Vec<_>>(),
            "parking": b.parking.iter().map(|p| json!({"unit": p.unit, "at": pt(p.at), "heading": p.heading.round()})).collect::<Vec<_>>(),
            "tower": pt(b.tower_or_reference()),
            "signs": signs(b).iter().map(|s| json!({
                "at": pt(s.at), "facing": s.facing.round(),
                "panels": s.panels.iter().map(|p| json!({"style": p.style, "text": p.text, "arrow": p.arrow})).collect::<Vec<_>>(),
            })).collect::<Vec<_>>(),
            "mask": {"file": file, "origin": pt(m.origin), "px_m": MASK_PX_M, "w": m.w, "h": m.h},
        }));
        log!(
            pr,
            "{:9} {}: lineup {} {:.0}°, {} taxi points out, {} in, {} spots",
            b.section,
            b.icao,
            b.runways[ri].designators[k],
            b.runways[ri].heading(k),
            rt.from.len(),
            rt.to.len(),
            b.parking.len()
        );
    }
    std::fs::write(theatre.join("airbases.json"), serde_json::to_string(&json!({ "bases": list }))?)?;
    std::fs::write(own.join("iaf.ibx"), ibx)?;
    // The surface: the sea from the DEM's 0 m cells joined to the edge, the bases' paved surface, the runways.
    let r = crate::sim_terrain::Meta::load(&theatre)?.rect;
    let (e0, n1, w, h) = (r[0], r[3], r[2] - r[0], r[3] - r[1]);
    let (nx, ny) = ((w / WATER_CELL_M).ceil() as usize, (h / WATER_CELL_M).ceil() as usize);
    // One bool per cell (43 M at 64 m: 43 MB), then the sea's 43 MB; a cell without a height node is land.
    let mut zero = vec![false; nx * ny];
    for j in 0..ny {
        check(cancel)?;
        ground.forget_north_of(n1 - (j as f64 + 0.5) * WATER_CELL_M);
        for i in 0..nx {
            let h = ground.at(e0 + (i as f64 + 0.5) * WATER_CELL_M, n1 - (j as f64 + 0.5) * WATER_CELL_M);
            zero[j * nx + i] = h.is_some_and(|h| h.abs() < 0.05);
        }
    }
    drop(ground);
    let sea = sea_cells(nx, ny, &zero);
    drop(zero);
    let mut cells: Vec<u8> = sea.iter().map(|&s| if s { SEA as u8 } else { 0 }).collect();
    drop(sea);
    // The OpenStreetMap extracts (downloaded when missing): the coastline decides the sea near it (the DEM's 0 m cells
    // farther out), as it cuts the Survey photo (iaf-2026/docs/terrain.md §12).
    let geo = theatre_geo(r);
    let pbfs = crate::sim_coast::fetch_extracts(assets, geo, pr, cancel)?;
    let coast = crate::sim_coast::Coast::load(&pbfs, geo, &theatre.join(".work"))?;
    for j in 0..ny {
        for i in 0..nx {
            let c = [e0 + (i as f64 + 0.5) * WATER_CELL_M, n1 - (j as f64 + 0.5) * WATER_CELL_M];
            if let Some(s) = coast.sea(c) {
                cells[j * nx + i] = if s { SEA as u8 } else { 0 };
            }
        }
    }
    // The inland water: OpenStreetMap's lakes and reservoirs (the sea keeps its flag where both are).
    let water = water_polygons(&pbfs, geo, &theatre.join(".work"))?;
    // The polygons themselves for the scenery (a tree tests them, not the 64 m grid: iaf-2026/docs/scenery.md §4).
    save_water(&theatre.join(WATER_FILE), &water)?;
    let mut inland = vec![false; nx * ny];
    for wb in &water {
        let rings: Vec<&[[f64; 2]]> = wb.rings.iter().map(Vec::as_slice).collect();
        fill_spans(nx, ny, [e0, n1], WATER_CELL_M, &rings, |y, x0, x1| inland[y * nx + x0..y * nx + x1].fill(true));
    }
    for (c, w) in cells.iter_mut().zip(&inland) {
        if *w && *c == 0 {
            *c = INLAND_WATER as u8;
        }
    }
    drop(inland);
    // The large lakes' surface as the DEM has it (iaf-2026/docs/terrain.md "Inland water").
    if let Some(mut g) = Ground::open(&theatre) {
        for wb in water.iter().filter(|w| w.area >= LEVEL_REPORT_M2) {
            if let Some(level) = wb.dem_level(&mut g) {
                log!(pr, "inland water: {} ({:.0} km²) at {level:.1} m (the DEM's median)", wb.name, wb.area / 1e6);
            }
        }
    }
    let rws: Vec<&Runway> = bases.iter().flat_map(|b| b.runways.iter()).collect();
    let dat = terraintype(r, &Surface { water: &WaterGrid::new(nx, ny, &cells), coast: &coast, paved: &paved }, &rws);
    std::fs::write(own.join("terraintype.dat"), &dat)?;
    let km2 = |f: i32| cells.iter().filter(|c| **c as i32 == f).count() as f64 * WATER_CELL_M * WATER_CELL_M / 1e6;
    log!(
        pr,
        "airbases: {} bases -> {}, iaf.ibx, terraintype.dat ({} KB, {:.0} km² of sea, {:.0} km² of inland water in {} bodies)",
        bases.len(),
        theatre.join("airbases.json").display(),
        dat.len() / 1024,
        km2(SEA),
        km2(INLAND_WATER),
        water.len()
    );
    Ok(())
}

// --- inland water ---------------------------------------------------------------------------------------------------

/// The smallest water body kept (m²): 10 ha, about 24 of the 64 m cells (a smaller one shows as a cell or two;
/// inferred). The lakes from this size up get their DEM level logged.
const WATER_MIN_M2: f64 = 100_000.0;
const LEVEL_REPORT_M2: f64 = 50_000_000.0;
/// OpenStreetMap `water` values that are not standing water: a river's outline is its bed.
const NOT_STANDING: [&str; 5] = ["river", "stream", "canal", "ditch", "drain"];

/// A lake, reservoir or salt pond of OpenStreetMap: its rings in UTM 36N (the first the outer one, the rest islands)
/// and its area (m², islands out).
#[derive(Debug)]
pub struct Water {
    pub id: String,
    pub name: String,
    pub rings: Vec<Vec<[f64; 2]>>,
    pub area: f64,
}

fn ring_area(r: &[[f64; 2]]) -> f64 {
    let n = r.len();
    ((0..n).map(|i| r[i][0] * r[(i + 1) % n][1] - r[(i + 1) % n][0] * r[i][1]).sum::<f64>() * 0.5).abs()
}

impl Water {
    /// The median ground height (m) over a 500 m grid inside the outer ring; None without a sample.
    fn dem_level(&self, g: &mut Ground) -> Option<f64> {
        let o = &self.rings[0];
        let b = o.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, p| {
            [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
        });
        let mut v = Vec::new();
        let mut y = b[1] + 250.0;
        while y < b[3] {
            let mut x = b[0] + 250.0;
            while x < b[2] {
                let inside = self.rings.iter().filter(|r| crate::scenery::contains(r, [x, y])).count() % 2 == 1;
                if let Some(h) = g.at(x, y).filter(|_| inside) {
                    v.push(h);
                }
                x += 500.0;
            }
            y += 500.0;
        }
        v.sort_by(f64::total_cmp);
        v.get(v.len() / 2).copied()
    }
}

/// The standing water of one GeoJSON feature (ogr2ogr's `multipolygons`, lon / lat): one `Water` per polygon of
/// WATER_MIN_M2 or more; none for a river, stream or canal outline, nor for water that is there only part of the year
/// (`intermittent` or `seasonal`: the desert's salt pans, dry in the satellite's pictures).
pub fn water_from(v: &Value) -> Vec<Water> {
    let p = &v["properties"];
    let tags = crate::scenery::other_tags(p["other_tags"].as_str().unwrap_or(""));
    let yes = |k: &str| tags.get(k).is_some_and(|v| v == "yes");
    if tags.get("water").is_some_and(|w| NOT_STANDING.contains(&w.as_str())) || yes("intermittent") || yes("seasonal") {
        return Vec::new();
    }
    let id = p["osm_id"].as_str().or(p["osm_way_id"].as_str()).unwrap_or("").to_string();
    let name = tags.get("name:en").map_or(p["name"].as_str().unwrap_or(""), String::as_str).to_string();
    let ring = |r: &Value| -> Vec<[f64; 2]> {
        r.as_array().into_iter().flatten().filter_map(|q| Some(utm36n(q[0].as_f64()?, q[1].as_f64()?))).collect()
    };
    let g = &v["geometry"];
    let polys: Vec<&Value> = match g["type"].as_str() {
        Some("Polygon") => vec![&g["coordinates"]],
        Some("MultiPolygon") => g["coordinates"].as_array().into_iter().flatten().collect(),
        _ => Vec::new(),
    };
    polys
        .into_iter()
        .filter_map(|poly| {
            let rings: Vec<Vec<[f64; 2]>> = poly.as_array()?.iter().map(ring).filter(|r| r.len() >= 3).collect();
            let area = ring_area(rings.first()?) - rings[1..].iter().map(|r| ring_area(r)).sum::<f64>();
            (area >= WATER_MIN_M2).then(|| Water { id: id.clone(), name: name.clone(), rings, area })
        })
        .collect()
}

/// The inland water's polygons beside the theatre (`save_water`): `{"bodies": [{"name", "rings": [[[x, y], ...], ...]}]}`,
/// UTM metres to 0.1 m, the first ring the outer one.
pub const WATER_FILE: &str = "water.json";

pub fn save_water(path: &Path, water: &[Water]) -> Result<()> {
    let r1 = |v: f64| (v * 10.0).round() / 10.0;
    let bodies: Vec<Value> = water
        .iter()
        .map(|w| {
            let rings: Vec<Vec<[f64; 2]>> = w.rings.iter().map(|r| r.iter().map(|p| p.map(r1)).collect()).collect();
            json!({"name": w.name, "rings": rings})
        })
        .collect();
    std::fs::write(path, serde_json::to_string(&json!({ "bodies": bodies }))?)?;
    Ok(())
}

/// The inland water's polygons as `save_water` wrote them, for point tests: each body's rings, its box and a 1 km
/// grid of the bodies whose box meets each square.
/// A body's rings (the first the outer one).
pub type Rings = Vec<Vec<[f64; 2]>>;

#[derive(Default)]
pub struct WaterIndex {
    bodies: Vec<(Rings, [f64; 4])>,
    grid: HashMap<(i64, i64), Vec<u32>>,
}

const WATER_INDEX_M: f64 = 1000.0;

impl WaterIndex {
    /// The file's bodies; empty without it.
    pub fn load(path: &Path) -> Result<Self> {
        let Ok(b) = std::fs::read(path) else { return Ok(Self::default()) };
        let v: Value = serde_json::from_slice(&b).with_context(|| format!("{}", path.display()))?;
        let rings = |w: &Value| -> Rings {
            w["rings"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|r| {
                    r.as_array().into_iter().flatten().filter_map(|p| Some([p[0].as_f64()?, p[1].as_f64()?])).collect()
                })
                .collect()
        };
        Ok(Self::new(v["bodies"].as_array().into_iter().flatten().map(rings).filter(|r| !r.is_empty()).collect()))
    }

    pub fn new(bodies: Vec<Rings>) -> Self {
        let mut ix = Self::default();
        for (k, rings) in bodies.into_iter().enumerate() {
            let b = rings[0].iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, p| {
                [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
            });
            let c = |v: f64| (v / WATER_INDEX_M).floor() as i64;
            for j in c(b[1])..=c(b[3]) {
                for i in c(b[0])..=c(b[2]) {
                    ix.grid.entry((i, j)).or_default().push(k as u32);
                }
            }
            ix.bodies.push((rings, b));
        }
        ix
    }

    /// Whether the point (UTM metres) lies within `r` m of a body's box.
    pub fn near(&self, p: [f64; 2], r: f64) -> bool {
        let c = |v: f64| (v / WATER_INDEX_M).floor() as i64;
        (c(p[1] - r)..=c(p[1] + r)).any(|j| {
            (c(p[0] - r)..=c(p[0] + r)).any(|i| {
                self.grid.get(&(i, j)).into_iter().flatten().any(|&k| {
                    let b = self.bodies[k as usize].1;
                    p[0] >= b[0] - r && p[0] <= b[2] + r && p[1] >= b[1] - r && p[1] <= b[3] + r
                })
            })
        })
    }

    /// Whether the point (UTM metres) lies in a body (an island is land).
    pub fn contains(&self, p: [f64; 2]) -> bool {
        let key = ((p[0] / WATER_INDEX_M).floor() as i64, (p[1] / WATER_INDEX_M).floor() as i64);
        self.grid.get(&key).into_iter().flatten().any(|&k| {
            let (rings, b) = &self.bodies[k as usize];
            p[0] >= b[0]
                && p[0] <= b[2]
                && p[1] >= b[1]
                && p[1] <= b[3]
                && rings.iter().filter(|r| crate::scenery::contains(r, p)).count() % 2 == 1
        })
    }
}

/// The theatre rect's box [lon0, lat0, lon1, lat1] (its edges through `utm36n_geo`).
pub fn theatre_geo(r: [f64; 4]) -> [f64; 4] {
    let mut b = [f64::MAX, f64::MAX, f64::MIN, f64::MIN];
    for k in 0..=16 {
        let f = k as f64 / 16.0;
        let (x, y) = (r[0] + f * (r[2] - r[0]), r[1] + f * (r[3] - r[1]));
        for [e, n] in [[x, r[1]], [x, r[3]], [r[0], y], [r[2], y]] {
            let p = utm36n_geo(e, n);
            b = [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])];
        }
    }
    b
}

/// OpenStreetMap's standing water over the box `geo` (lon / lat) from the extracts `pbfs` (`sim_coast::fetch_extracts`): `natural=water`, `landuse=reservoir` and
/// `landuse=salt_pond` polygons of WATER_MIN_M2 or more (`water_from`), a body in two extracts kept once. ogr2ogr writes
/// each cut into `work`.
pub fn water_polygons(pbfs: &[std::path::PathBuf], geo: [f64; 4], work: &Path) -> Result<Vec<Water>> {
    std::fs::create_dir_all(work)?;
    let out = work.join("water.geojsonl");
    let mut all = Vec::new();
    for pbf in pbfs {
        let _ = std::fs::remove_file(&out);
        let mut cmd = std::process::Command::new("ogr2ogr");
        cmd.args(["-f", "GeoJSONSeq", "-where", "natural = 'water' OR landuse IN ('reservoir','salt_pond')"])
            .args(["-select", "osm_id,osm_way_id,name,other_tags", "-spat"])
            .args(geo.map(|v| v.to_string()))
            .arg(&out)
            .arg(pbf)
            .arg("multipolygons");
        crate::scenery::run(cmd)?;
        all.extend(crate::scenery::geojsonl(&out)?.flat_map(|v| water_from(&v)));
    }
    let _ = std::fs::remove_file(&out);
    Ok(drop_twin_waters(all))
}

/// The bodies minus the second copy of one that two extracts both hold (they overlap at the borders): the same outer
/// ring, point for point. A multipolygon's members are different rings and all stay.
pub fn drop_twin_waters(all: Vec<Water>) -> Vec<Water> {
    let mut seen = std::collections::HashSet::new();
    all.into_iter()
        .filter(|w| seen.insert(w.rings[0].iter().map(|p| p.map(f64::to_bits)).collect::<Vec<_>>()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The take-off ends' designators by base section.
    fn main_ends() -> std::collections::BTreeMap<&'static str, &'static str> {
        BASES.iter().map(|(_, s, e)| (*s, *e)).collect()
    }

    fn data() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../iaf-2026/data/airbases")
    }

    #[test]
    fn utm_matches_gdal() {
        // gdaltransform -s_srs EPSG:4326 -t_srs EPSG:32636 (GDAL 3.13).
        for (lon, lat, e, n) in [
            (34.666, 30.776, 659_427.796_112_835, 3_405_963.754_670_05),
            (35.179, 32.665, 704_339.576_213_308, 3_616_247.580_636_78),
        ] {
            let [x, y] = utm36n(lon, lat);
            assert!((x - e).abs() < 0.01 && (y - n).abs() < 0.01, "{lon} {lat}: {x} {y}");
            let g = utm36n_geo(e, n);
            assert!((g[0] - lon).abs() < 1e-8 && (g[1] - lat).abs() < 1e-8, "inverse of {e} {n}: {g:?}");
        }
        // The theatre's far corners (iaf-2026/docs/terrain.md §2) round-trip too.
        for (e, n) in [(507_904.0, 3_255_296.0), (855_040.0, 3_766_272.0)] {
            let g = utm36n_geo(e, n);
            let p = utm36n(g[0], g[1]);
            assert!((p[0] - e).abs() < 0.001 && (p[1] - n).abs() < 0.001, "{e} {n}: {p:?}");
        }
    }

    /// Each base's lineup points lie on their runway's centreline, 100 m past the declared start; the take-off end is
    /// the one named.
    #[test]
    fn lineups_lie_on_the_centreline() {
        for b in load(&data()).unwrap() {
            for r in &b.runways {
                for k in 0..2 {
                    let l = r.lineup(k);
                    assert!(r.dist(l) < 0.01, "{} {}: off the centreline", b.icao, r.designators[k]);
                    let along = dist(l, r.ends[k]);
                    assert!(
                        (along - r.starts[k] - LINEUP_IN_M).abs() < 0.01,
                        "{} {}: {along} m in",
                        b.icao,
                        r.designators[k]
                    );
                }
            }
            let (ri, k) = b.main;
            assert_eq!(b.runways[ri].designators[k], main_ends()[b.section.as_str()]);
        }
    }

    /// terraintype.dat's paved surface: every parking spot (on its apron) and the departure's taxi path from the first
    /// spot to the take-off lineup (each 2 m) are not rough ground (no crash rolling over 25.7 m/s), the lineup is
    /// RUNWAY, and the ground 40 m beside the taxi path is paved exactly where the mask is (at Ramon at least a quarter
    /// of it sand, LAND).
    #[test]
    fn terraintype_paves_the_taxiways_and_aprons() {
        for b in load(&data()).unwrap() {
            let m = mask(&b);
            let p0 = b.parking[0].at;
            let (e0, n1) = ((p0[0] / 64.0).floor() * 64.0 - 6400.0, (p0[1] / 64.0).floor() * 64.0 + 6400.0);
            let r = [e0, n1 - 12_800.0, e0 + 12_800.0, n1];
            let cells = vec![0u8; 200 * 200];
            let rws: Vec<&Runway> = b.runways.iter().collect();
            let dat = terraintype(
                r,
                &Surface {
                    water: &WaterGrid::new(200, 200, &cells),
                    coast: &Default::default(),
                    paved: &[Paved::with_paths(&m, &b, &routes(&b).unwrap())],
                },
                &rws,
            );
            let t = iaf_formats::terrain_types::TerrainTypes::parse(&dat).unwrap();
            let rough = |p: [f64; 2]| t.at(p[0], p[1]) as u32 & iaf_flight::aircraft::SURFACE_ROUGH != 0;
            let rt = routes(&b).unwrap();
            for p in &b.parking {
                assert!(!rough(p.at), "{} {}: the parking spot is rough ground", b.icao, p.unit);
                // Every spot reaches the lineup on pavement: to the hub, then the departure.
                let path: Vec<[f64; 2]> = [p.at, rt.hub].into_iter().chain(rt.from.iter().copied()).collect();
                for s in path.windows(2) {
                    let d = dist(s[0], s[1]);
                    for k in 0..=(d / 2.0) as usize {
                        let f = (k as f64 * 2.0 / d.max(1e-9)).min(1.0);
                        let q = [s[0][0] + (s[1][0] - s[0][0]) * f, s[0][1] + (s[1][1] - s[0][1]) * f];
                        assert!(!rough(q), "{} {}: its taxi path at {q:?} is rough ground", b.icao, p.unit);
                    }
                }
            }
            let path: Vec<[f64; 2]> = std::iter::once(b.parking[0].at).chain(rt.from.iter().copied()).collect();
            let (mut beside, mut sand) = (0, 0);
            for s in path.windows(2) {
                let (d, n) = (dist(s[0], s[1]), [s[1][0] - s[0][0], s[1][1] - s[0][1]]);
                for k in 0..=(d / 2.0) as usize {
                    let f = (k as f64 * 2.0 / d).min(1.0);
                    let p = [s[0][0] + n[0] * f, s[0][1] + n[1] * f];
                    assert!(!rough(p), "{}: the taxi path at {p:?} is rough ground", b.icao);
                    if k % 25 == 12 {
                        for side in [-1.0, 1.0] {
                            let q = [p[0] - n[1] / d * 40.0 * side, p[1] + n[0] / d * 40.0 * side];
                            let (x, y) = ((q[0] - m.origin[0]) / MASK_PX_M, (m.origin[1] - q[1]) / MASK_PX_M);
                            // The mask within 10 m of q (a paved cell of 8 m reaches past the edge): skip the edges.
                            let px: Vec<bool> = (-5..=5)
                                .flat_map(|dy| (-5..=5).map(move |dx| (dx, dy)))
                                .map(|(dx, dy)| {
                                    m.img.get_pixel((x as i64 + dx) as u32, (y as i64 + dy) as u32)[0] >= 128
                                })
                                .collect();
                            if px.iter().all(|&v| v) {
                                assert!(!rough(q), "{}: paved {q:?} is rough", b.icao);
                            } else if px.iter().all(|&v| !v) {
                                assert_eq!(t.at(q[0], q[1]), LAND, "{}: sand {q:?} is not LAND", b.icao);
                                sand += 1;
                            }
                            beside += 1;
                        }
                    }
                }
            }
            let (ri, k) = b.main;
            let l = b.runways[ri].lineup(k);
            assert_eq!(t.at(l[0], l[1]), RUNWAY, "{}: the lineup", b.icao);
            if b.section == "Ramon" {
                assert!(sand * 4 >= beside, "Ramon: {sand} of {beside} points beside the taxi path on sand");
            }
        }
    }

    /// A land block cut off the paved grid's lines (the 64 m water grid's blocks) keeps its part of a paved cell.
    #[test]
    fn a_cut_through_a_paved_cell_keeps_it_paved() {
        let p = Paved { origin: [1000.0, 2064.0], nx: 8, ny: 8, cells: vec![true; 64] };
        for b in [[1000.0, 2000.0, 1003.0, 2064.0], [1003.0, 2000.0, 1061.0, 2064.0], [1061.0, 2000.0, 1064.0, 2064.0]]
        {
            let mut out = Vec::new();
            write_node(&land_tree(b, std::slice::from_ref(&p), &[]), &mut out);
            let t = iaf_formats::terrain_types::TerrainTypes::parse(&out).unwrap();
            let x = (b[0] + b[2]) / 2.0;
            assert_eq!(t.at(x, 2032.0), PAVED, "the block {b:?} at x = {x}");
        }
    }

    /// The taxiway signs: Ramon's taxi path from its spot to 25R's lineup passes (within 60 m) a sign naming 25R, a
    /// runway-holding one among them; every sign stands off the paved surface, beside a taxiway, facing it.
    #[test]
    fn signs_guide_the_taxi_to_the_runway() {
        for b in load(&data()).unwrap() {
            let all = signs(&b);
            assert!(!all.is_empty(), "{}: no sign", b.icao);
            let m = mask(&b);
            for s in &all {
                let (x, y) = ((s.at[0] - m.origin[0]) / MASK_PX_M, (m.origin[1] - s.at[1]) / MASK_PX_M);
                let r = m.img.get_pixel(x as u32, y as u32)[0];
                assert!(r < 128, "{} sign {:?} {:?} on the paved surface", b.icao, s.at, s.panels);
                let near =
                    b.taxiways.iter().any(|(l, w)| l.windows(2).any(|t| seg_dist(s.at, t[0], t[1]) < w / 2.0 + 45.0));
                assert!(near, "{} sign {:?}: no taxiway near", b.icao, s.at);
            }
            if b.section != "Ramon" {
                continue;
            }
            let rt = routes(&b).unwrap();
            let path: Vec<[f64; 2]> = std::iter::once(b.parking[0].at).chain(rt.from.iter().copied()).collect();
            let passed: Vec<&Sign> = all
                .iter()
                .filter(|s| path.windows(2).any(|t| seg_dist(s.at, t[0], t[1]) < 60.0))
                .filter(|s| s.panels.iter().any(|p| p.text.split('-').any(|t| t == "25R")))
                .collect();
            assert!(
                passed.iter().any(|s| s.panels[0].style == "mandatory"),
                "Ramon: no holding sign for 25R: {passed:?}"
            );
            assert!(
                passed.iter().any(|s| s.panels[0].style == "direction"),
                "Ramon: no direction sign to 25R: {passed:?}"
            );
        }
    }

    /// Every parking spot stands on an apron of its base.
    #[test]
    fn parking_spots_are_on_aprons() {
        for b in load(&data()).unwrap() {
            for p in &b.parking {
                let on = b.aprons.iter().any(|a| {
                    let mut m = vec![0f32; 1];
                    fill_polygon(&mut m, 1, 1, [p.at[0] - 0.5, p.at[1] + 0.5], 1.0, a);
                    m[0] > 0.0
                });
                assert!(on, "{} {}: not on an apron", b.icao, p.unit);
            }
        }
    }

    /// The AI's departure joins every base's parking spots to the take-off lineup along the taxiways, and the
    /// compiled iaf.ibx parses with the flight model's reader back to the same points.
    #[test]
    fn iaf_ibx_reads_back() {
        let bases = load(&data()).unwrap();
        let mut ibx = String::new();
        for b in &bases {
            let rt = routes(b).unwrap();
            assert!(rt.from.len() >= 2 && rt.to.len() >= 2, "{}: {} / {} points", b.icao, rt.from.len(), rt.to.len());
            assert!(dist(rt.hub, b.parking[0].at) < 400.0, "{}: hub {:?} far from the spot", b.icao, rt.hub);
            ibx += &ibx_section(b, &rt, &mut |_| b.elevation);
        }
        let read = iaf_flight::airbase::Airbase::load_all(ibx.as_bytes());
        assert_eq!(
            read.iter().map(|a| a.name.as_str()).collect::<Vec<_>>(),
            ["Ramon", "David", "TelNof", "Hatzerim", "Nevatim"]
        );
        for (a, b) in read.iter().zip(&bases) {
            let (ri, k) = b.main;
            let l = b.runways[ri].lineup(k);
            assert!((f64::from(a.lineup[0]) - l[0]).abs() < 0.1 && (f64::from(a.lineup[1]) - l[1]).abs() < 0.1);
            assert_eq!(a.runway_deg, b.runways[ri].heading(k).round() as f32);
            assert_eq!(a.hangars.len(), b.parking.len());
            assert!((f64::from(a.hangars[0].x) - b.parking[0].at[0]).abs() < 0.1);
            let last = a.from_taxi.last().unwrap();
            assert!(
                (f64::from(last.x) - l[0]).abs() < 0.1 && (f64::from(last.y) - l[1]).abs() < 0.1,
                "departure ends at the lineup"
            );
            assert_eq!(f64::from(a.tower[2]), b.elevation);
            // The jet leaves its spot along the departure's first taxiway leg (not north: a heading of 0).
            for t in &a.from_hangar_turn {
                assert_eq!(t.hdg, a.from_taxi[0].hdg, "{}: the turn point's heading", b.icao);
                assert!(t.hdg != 0.0, "{}", b.icao);
            }
        }
    }

    /// The departure taxi (each parking spot → the hub → the taxi path → the lineup) runs on the pavement (`paved`
    /// with the training missions' margin): every metre of it, at the bases the training missions fly from
    /// (Hatzerim's Sufa spot joins the taxiways across 140 m that OSM does not mark paved: airbases.md §9).
    #[test]
    fn the_departure_is_paved() {
        for b in load(&data()).unwrap().into_iter().filter(|b| b.icao != "LLHB") {
            let rt = routes(&b).unwrap();
            for spot in &b.parking {
                let mut path = vec![spot.at];
                path.extend(&rt.from);
                for w in path.windows(2) {
                    let n = dist(w[0], w[1]).ceil() as usize;
                    for i in 0..=n {
                        let f = i as f64 / n.max(1) as f64;
                        let p = [w[0][0] + (w[1][0] - w[0][0]) * f, w[0][1] + (w[1][1] - w[0][1]) * f];
                        assert!(
                            b.paved(p, crate::training::PAVEMENT_MARGIN_M),
                            "{} {}: {p:?} on the leg {:?} → {:?} is off the pavement",
                            b.icao,
                            spot.unit,
                            w[0],
                            w[1]
                        );
                    }
                }
            }
        }
    }

    /// terraintype.dat flags a runway's centre RUNWAY, the sea SEA, a lake INLAND_WATER and other ground LAND, through
    /// the reader; the flight model and the water shader take both waters as water. Near a coastline its side decides
    /// (to COAST_LEAF_M), farther out the grid.
    #[test]
    fn terraintype_flags_runways_sea_and_lakes() {
        let bases = load(&data()).unwrap();
        let rws: Vec<&Runway> = bases.iter().flat_map(|b| b.runways.iter()).collect();
        // A 64 km box from Ramon's east: the west 16 km sea; a lake 6.4 km square in the north-east.
        let r = [600_000.0, 3_380_000.0, 664_000.0, 3_444_000.0];
        let mut cells: Vec<u8> = (0..1000 * 1000).map(|k| if k % 1000 < 250 { SEA as u8 } else { 0 }).collect();
        // Rows 100..200 (north of 3,431,200 N), columns 800..900 (east of 651,200 E): the lake; an island in its middle.
        let ring =
            |x0: f64, y0: f64, side: f64| vec![[x0, y0], [x0 + side, y0], [x0 + side, y0 + side], [x0, y0 + side]];
        let w = Water {
            id: "1".into(),
            name: "lake".into(),
            rings: vec![ring(651_200.0, 3_424_800.0, 6400.0), ring(654_000.0, 3_427_600.0, 800.0)],
            area: 0.0,
        };
        let rings: Vec<&[[f64; 2]]> = w.rings.iter().map(Vec::as_slice).collect();
        fill_spans(1000, 1000, [r[0], r[3]], 64.0, &rings, |y, x0, x1| {
            cells[y * 1000 + x0..y * 1000 + x1].fill(INLAND_WATER as u8)
        });
        // A coastline 30 m east of the grid's sea edge (x = 616,000), running south: the sea to its west.
        let coast = crate::sim_coast::Coast::new(&[vec![[616_030.0, 3_420_000.0], [616_030.0, 3_400_000.0]]]);
        let s = Surface { water: &WaterGrid::new(1000, 1000, &cells), coast: &coast, paved: &[] };
        let t = iaf_formats::terrain_types::TerrainTypes::parse(&terraintype(r, &s, &rws)).unwrap();
        assert_eq!(t.at(616_020.0, 3_410_000.0), SEA, "10 m west of the coastline");
        assert_eq!(t.at(616_040.0, 3_410_000.0), LAND, "10 m east of it");
        assert_eq!(t.at(615_900.0, 3_430_000.0), SEA, "beyond its reach: the grid");
        assert_eq!(t.at(652_000.0, 3_430_000.0), INLAND_WATER, "the lake");
        assert!(iaf_formats::terrain_types::TerrainTypes::is_water(t.at(652_000.0, 3_430_000.0)));
        assert_eq!(t.at(654_400.0, 3_428_000.0), LAND, "its island");
        assert_eq!(t.at(650_000.0, 3_430_000.0), LAND, "west of it");
        let ramon = &bases[0];
        for rw in &ramon.runways {
            let c = rw.at(0, rw.length() / 2.0);
            assert_eq!(t.at(c[0], c[1]), RUNWAY, "{} centre", rw.designators[0]);
            let side = [c[0] + rw.dir(0)[1] * (rw.width / 2.0 + 30.0), c[1] - rw.dir(0)[0] * (rw.width / 2.0 + 30.0)];
            assert_eq!(t.at(side[0], side[1]), LAND, "{} beside it", rw.designators[0]);
        }
        assert_eq!(t.at(605_000.0, 3_400_000.0), SEA);
        assert_eq!(t.at(640_000.0, 3_400_000.0), LAND);
    }

    /// OpenStreetMap's standing water: a lake with an island (its area without it); a river's outline, a seasonal salt
    /// pan and a pond under WATER_MIN_M2 left out; each polygon of a multipolygon one body.
    #[test]
    fn water_polygons_from_osm() {
        // 0.012° squares near the Sea of Galilee; an island of 0.0012°.
        let sq = |lon: f64, lat: f64, d: f64| {
            json!([[lon, lat], [lon + d, lat], [lon + d, lat + d], [lon, lat + d], [lon, lat]])
        };
        let f = |tags: &str, geometry: Value| json!({"properties": {"osm_id": "7", "name": "Kinneret", "other_tags": tags}, "geometry": geometry});
        let lake = f(
            "\"water\"=>\"lake\"",
            json!({"type": "Polygon", "coordinates": [sq(35.55, 32.8, 0.012), sq(35.555, 32.805, 0.0012)]}),
        );
        let w = water_from(&lake);
        assert_eq!(w.len(), 1);
        assert_eq!((w[0].name.as_str(), w[0].rings.len()), ("Kinneret", 2));
        // 1123 m × 1331 m less the island's 112 m × 133 m.
        assert!((w[0].area - 1.48e6).abs() < 1.0e4, "{}", w[0].area);
        for tags in ["\"water\"=>\"river\"", "\"intermittent\"=>\"yes\",\"water\"=>\"lake\""] {
            let g = json!({"type": "Polygon", "coordinates": [sq(35.55, 32.8, 0.012)]});
            assert!(water_from(&f(tags, g)).is_empty(), "{tags}");
        }
        let ponds = f(
            "",
            json!({"type": "MultiPolygon", "coordinates": [[sq(35.5, 32.5, 0.012)], [sq(35.6, 32.5, 0.012)], [sq(35.7, 32.5, 0.001)]]}),
        );
        assert_eq!(water_from(&ponds).len(), 2, "the 100 m pond is under the limit");
        // Two same-sized evaporation pans of one relation stay two; the same relation from a second extract is one copy.
        let pans = f(
            "",
            json!({"type": "MultiPolygon", "coordinates": [[sq(35.40, 31.10, 0.012)], [sq(35.42, 31.10, 0.012)]]}),
        );
        let twice: Vec<Water> = water_from(&pans).into_iter().chain(water_from(&pans)).collect();
        assert_eq!(twice.len(), 4);
        let kept = drop_twin_waters(twice);
        assert_eq!(kept.len(), 2, "both members, once each");
        assert_ne!(kept[0].rings[0], kept[1].rings[0]);
    }

    /// The saved polygons read back for the scenery's point test: in the lake, on its island, beside it.
    #[test]
    fn water_index_reads_the_saved_polygons() {
        let sq = |x: f64, y: f64, d: f64| vec![[x, y], [x + d, y], [x + d, y + d], [x, y + d]];
        let w = Water {
            id: "1".into(),
            name: "lake".into(),
            rings: vec![sq(0.0, 0.0, 3000.0), sq(1000.0, 1000.0, 500.0)],
            area: 0.0,
        };
        let p = std::env::temp_dir().join(format!("iaf-water-{}.json", std::process::id()));
        save_water(&p, &[w]).unwrap();
        let ix = WaterIndex::load(&p).unwrap();
        std::fs::remove_file(&p).unwrap();
        assert!(ix.contains([2500.0, 2500.0]), "in the lake");
        assert!(!ix.contains([1200.0, 1200.0]), "on its island");
        assert!(!ix.contains([3100.0, 100.0]), "beside it");
        assert!(!WaterIndex::load(Path::new("/nonexistent/water.json")).unwrap().contains([1.0, 1.0]));
    }

    #[test]
    fn the_sea_is_joined_to_the_edge() {
        // 5 × 3 cells: 0 m on the west column and in a closed pocket in the middle (a lake below sea level stays land).
        let h = [[0.0, 5.0, 5.0, 5.0, 5.0], [0.0, 5.0, 0.0, 5.0, 5.0], [0.0, 5.0, 5.0, 5.0, 5.0]];
        let zero: Vec<bool> = h.iter().flatten().map(|v| *v == 0.0).collect();
        let sea = sea_cells(5, 3, &zero);
        assert!(sea[0] && sea[5] && sea[10], "the west column");
        assert!(!sea[7], "the closed pocket");
        assert!(!sea[1]);
    }

    #[test]
    fn simplify_keeps_corners() {
        let l: Vec<[f64; 2]> =
            (0..=10).map(|k| [k as f64 * 10.0, 0.0]).chain((1..=10).map(|k| [100.0, k as f64 * 10.0])).collect();
        assert_eq!(simplify(&l, 1.0), vec![[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]]);
    }
}
