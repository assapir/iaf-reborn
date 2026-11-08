//! `iaf-sim airbases` (iaf-2026/docs/airbases.md §"In the game"): the four airbases of `iaf-2026/data/airbases/`
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

use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};

use crate::log;
use crate::progress::{Progress, check};

/// The bases' iaf.ibx sections (`iaf_flight::airbase::SECTIONS`: the original's Ramon and David, ours appended) and the
/// runway end each takes off from (inferred: the missions' runways; Hatzerim's longest runway into the prevailing
/// westerly wind).
pub const BASES: [(&str, &str, &str); 4] =
    [("LLRM", "Ramon", "25R"), ("LLRD", "David", "27"), ("LLHB", "Hatzerim", "28L"), ("LLNV", "Nevatim", "26L")];
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
const SEA: i32 = 0x4;
const RUNWAY: i32 = 0x10;
/// The water raster's cell (m): the DEM's height texel.
const WATER_CELL_M: f64 = 64.0;

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
    fn dist(&self, p: [f64; 2]) -> f64 {
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
    /// The tower, else the reference point (three of the four towers are open in OSM, airbases.md §5).
    pub fn tower_or_reference(&self) -> [f64; 2] {
        self.tower.unwrap_or(self.reference)
    }
}

/// The four bases from `<dir>/<icao>.json`, in BASES' order.
pub fn load(dir: &Path) -> Result<Vec<Base>> {
    BASES
        .iter()
        .map(|(icao, section, main)| load_base(&dir.join(format!("{}.json", icao.to_lowercase())), section, main))
        .collect()
}

fn load_base(path: &Path, section: &str, main: &str) -> Result<Base> {
    let v: Value = serde_json::from_slice(&std::fs::read(path).with_context(|| format!("{}", path.display()))?)?;
    let what = path.display().to_string();
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
        fill_spans(w, h, origin, MASK_PX_M, p, |y, x0, x1| {
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
    fill_spans(w, h, origin, cell, poly, |y, x0, x1| m[y * w + x0..y * w + x1].fill(1.0));
}

/// Calls `span(y, x0, x1)` for each row's run of pixels whose centre lies inside `poly` (even-odd).
fn fill_spans(
    w: usize,
    h: usize,
    origin: [f64; 2],
    cell: f64,
    poly: &[[f64; 2]],
    mut span: impl FnMut(usize, usize, usize),
) {
    for y in 0..h {
        let northing = origin[1] - (y as f64 + 0.5) * cell;
        let mut xs = Vec::new();
        for k in 0..poly.len() {
            let (a, b) = (poly[k], poly[(k + 1) % poly.len()]);
            if (a[1] > northing) != (b[1] > northing) {
                xs.push(a[0] + (northing - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
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

/// child0 where x < v (world metres).
fn split_x(v: f64, west: Node, east: Node) -> Node {
    Node::Split([1.0, 0.0, v + SHIFT[0]], Box::new(west), Box::new(east))
}

/// child0 where y < v (world metres).
fn split_y(v: f64, south: Node, north: Node) -> Node {
    Node::Split([0.0, 1.0, v + SHIFT[1]], Box::new(south), Box::new(north))
}

/// The runways' rectangles (each a convex quad: centreline ends ± half the width) over the land leaf, as nested
/// half-plane tests; a point outside one goes on to the next.
fn runway_chain(rects: &[[[f64; 2]; 4]]) -> Node {
    let Some((q, rest)) = rects.split_first() else { return Node::Leaf(LAND) };
    let mut n = Node::Leaf(RUNWAY);
    // Each edge a→b of the counter-clockwise quad: inside is to its left.
    for k in (0..4).rev() {
        let (a, b) = (q[k], q[(k + 1) % 4]);
        // left of a→b: (b−a) × (p−a) > 0 ⇔ −dy·x + dx·y > −dy·ax + dx·ay; child0 (<) is outside.
        let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
        let c = -dy * (a[0] + SHIFT[0]) + dx * (a[1] + SHIFT[1]);
        n = Node::Split([-dy, dx, c], Box::new(runway_chain(rest)), Box::new(n));
    }
    n
}

/// The sea cells of a theatre (`sea[j * nx + i]`, WATER_CELL_M squares from the north-west corner; rows run south).
pub struct SeaGrid<'a> {
    nx: usize,
    ny: usize,
    sea: &'a [bool],
}

impl<'a> SeaGrid<'a> {
    pub fn new(nx: usize, ny: usize, sea: &'a [bool]) -> Self {
        Self { nx, ny, sea }
    }
    /// The block [i0, i1) × [j0, j1) when all of it is sea (Some(true)) or all land (Some(false)); None when mixed.
    /// The scan stops at the first cell that differs, so the tree's build reads each cell about once per level.
    fn uniform(&self, i0: usize, i1: usize, j0: usize, j1: usize) -> Option<bool> {
        let first = self.sea[j0 * self.nx + i0];
        (j0..j1).all(|j| self.sea[j * self.nx + i0..j * self.nx + i1].iter().all(|&c| c == first)).then_some(first)
    }
}

/// The surface tree over the theatre rect `r` (E0, N0, E1, N1): the sea as a quadtree of axis splits, the runways in
/// the land blocks they touch.
fn surface_tree(r: [f64; 4], sea: &SeaGrid, rects: &[[[f64; 2]; 4]]) -> Node {
    // Cells [i0, i1) × [j0, j1): one leaf when uniform, else split the longer side.
    fn build(i0: usize, i1: usize, j0: usize, j1: usize, sea: &SeaGrid, rects: &[[[f64; 2]; 4]], r: [f64; 4]) -> Node {
        let cx = |i: usize| (r[0] + i as f64 * WATER_CELL_M).min(r[2]);
        let cy = |j: usize| (r[3] - j as f64 * WATER_CELL_M).max(r[1]);
        let u = sea.uniform(i0, i1, j0, j1);
        if u == Some(true) {
            return Node::Leaf(SEA);
        }
        if u == Some(false) {
            let (x0, x1, y0, y1) = (cx(i0), cx(i1), cy(j1), cy(j0));
            let near: Vec<_> = rects
                .iter()
                .filter(|q| {
                    let bx = q.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |b, p| {
                        [b[0].min(p[0]), b[1].min(p[1]), b[2].max(p[0]), b[3].max(p[1])]
                    });
                    bx[0] < x1 && x0 < bx[2] && bx[1] < y1 && y0 < bx[3]
                })
                .copied()
                .collect();
            return runway_chain(&near);
        }
        if i1 - i0 >= j1 - j0 {
            let m = (i0 + i1) / 2;
            split_x(cx(m), build(i0, m, j0, j1, sea, rects, r), build(m, i1, j0, j1, sea, rects, r))
        } else {
            let m = (j0 + j1) / 2;
            // Rows run south: j ≥ m is the south part.
            split_y(cy(m), build(i0, i1, m, j1, sea, rects, r), build(i0, i1, j0, m, sea, rects, r))
        }
    }
    build(0, sea.nx, 0, sea.ny, sea, rects, r)
}

/// A runway's rectangle, counter-clockwise.
fn rect(r: &Runway) -> [[f64; 2]; 4] {
    let d = r.dir(0);
    let n = [-d[1] * r.width / 2.0, d[0] * r.width / 2.0];
    let (a, b) = (r.ends[0], r.ends[1]);
    [[a[0] - n[0], a[1] - n[1]], [b[0] - n[0], b[1] - n[1]], [b[0] + n[0], b[1] + n[1]], [a[0] + n[0], a[1] + n[1]]]
}

/// terraintype.dat's bytes for the theatre rect `r`.
pub fn terraintype(r: [f64; 4], sea: &SeaGrid, runways: &[&Runway]) -> Vec<u8> {
    let rects: Vec<_> = runways.iter().map(|r| rect(r)).collect();
    let mut out = Vec::new();
    write_node(&surface_tree(r, sea, &rects), &mut out);
    out
}

/// The sea on the theatre's WATER_CELL_M grid: the cells at 0 m (`zero`: GLO-30's sea surface; its missing tiles
/// are 0 m in the terrain's height nodes too) joined to the theatre's edge, so the Dead Sea and the Sea of Galilee below
/// sea level stay land (open: inland water). A breadth-first fill, cells marked as they are queued: the queue holds
/// the fill's front (a few thousand cells), not the sea.
pub fn sea_cells(nx: usize, ny: usize, zero: &[bool]) -> Vec<bool> {
    let mut sea = vec![false; nx * ny];
    let mut queue = std::collections::VecDeque::new();
    let push = |k: usize, sea: &mut Vec<bool>, queue: &mut std::collections::VecDeque<u32>| {
        if zero[k] && !sea[k] {
            sea[k] = true;
            queue.push_back(k as u32);
        }
    };
    for i in 0..nx {
        push(i, &mut sea, &mut queue);
        push((ny - 1) * nx + i, &mut sea, &mut queue);
    }
    for j in 0..ny {
        push(j * nx, &mut sea, &mut queue);
        push(j * nx + nx - 1, &mut sea, &mut queue);
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

/// `iaf-sim airbases`: the four bases into `<assets>/converted/terrain/israel/` (airbases.json, masks) and
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
    for b in &bases {
        check(cancel)?;
        let rt = routes(b)?;
        let mut z = |p: [f64; 2]| ground.at(p[0], p[1]).unwrap_or(b.elevation);
        ibx += &ibx_section(b, &rt, &mut z);
        let m = mask(b);
        let file = format!("israel/airbases/{}.png", b.section.to_lowercase());
        m.img.save(assets.join("converted/terrain").join(&file))?;
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
    std::fs::write(theatre.join("airbases.json"), serde_json::to_string_pretty(&json!({ "bases": list }))?)?;
    std::fs::write(own.join("iaf.ibx"), ibx)?;
    // The surface: the sea from the DEM's 0 m cells joined to the edge, the runways.
    let meta: Value = serde_json::from_slice(&std::fs::read(theatre.join("meta.json"))?)?;
    let (e0, n1) = (meta["x_shift"].as_f64().unwrap_or(0.0), meta["y_shift"].as_f64().unwrap_or(0.0));
    let t = &meta["theatre"];
    let (w, h) = (t[2].as_f64().unwrap_or(0.0), t[3].as_f64().unwrap_or(0.0));
    if w <= 0.0 || h <= 0.0 {
        bail!("{}: no theatre size", theatre.display());
    }
    let r = [e0, n1 - h, e0 + w, n1];
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
    let rws: Vec<&Runway> = bases.iter().flat_map(|b| b.runways.iter()).collect();
    let dat = terraintype(r, &SeaGrid::new(nx, ny, &sea), &rws);
    std::fs::write(own.join("terraintype.dat"), &dat)?;
    log!(
        pr,
        "airbases: {} bases -> {}, iaf.ibx, terraintype.dat ({} KB, {:.0} km² of sea)",
        bases.len(),
        theatre.join("airbases.json").display(),
        dat.len() / 1024,
        sea.iter().filter(|s| **s).count() as f64 * WATER_CELL_M * WATER_CELL_M / 1e6
    );
    Ok(())
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
        assert_eq!(read.iter().map(|a| a.name.as_str()).collect::<Vec<_>>(), ["Ramon", "David", "Hatzerim", "Nevatim"]);
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

    /// terraintype.dat flags a runway's centre RUNWAY, the sea SEA and other ground LAND, through the reader.
    #[test]
    fn terraintype_flags_runways_and_sea() {
        let bases = load(&data()).unwrap();
        let rws: Vec<&Runway> = bases.iter().flat_map(|b| b.runways.iter()).collect();
        // A 64 km box from Ramon's east: the west 16 km sea.
        let r = [600_000.0, 3_380_000.0, 664_000.0, 3_444_000.0];
        let sea: Vec<bool> = (0..1000 * 1000).map(|k| k % 1000 < 250).collect();
        let t = iaf_formats::terrain_types::TerrainTypes::parse(&terraintype(r, &SeaGrid::new(1000, 1000, &sea), &rws))
            .unwrap();
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
