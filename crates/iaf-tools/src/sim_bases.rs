//! `iaf-sim airbases` (modern-iaf/docs/airbases.md §"In the game"): the airbases of `modern-iaf/data/airbases/`
//! (lat / lon, item B2a) compiled into the sim's UTM 36N frame (modern-iaf/docs/terrain.md §2), in the shapes the
//! shared readers take:
//! - `converted/terrain/israel/airbases.json` and one paved-surface mask per base (`airbases/<name>.png`), as
//!   `iaf-terrain airbases` writes for the original (docs/rendering.md §7): Detailed airbases draws them;
//! - `converted/own/iaf.ibx`: one section per base (tower, lineup, take-off heading, the AI's taxi paths, the parking
//!   spots), read by `iaf_flight::airbase::Airbase` and the radio (modern-iaf/docs/data-formats.md §12);
//! - `converted/own/terraintype.dat`: the surface flags' BSP tree (iaf_formats::terrain_types): the runways, the sea
//!   from the coast, land elsewhere.
//!
//! Nothing is read from the original game's files.

use std::collections::{BinaryHeap, HashMap};
use std::path::Path;
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};

use crate::airbases::ring_area;
use crate::log;
use crate::mission_edit::Heights;
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
/// modern-iaf/docs/data-formats.md §5; inferred: a jet's length and a margin).
pub const LINEUP_IN_M: f64 = 100.0;
/// The wheels count as on the pavement this far past its edges, in the training missions (`training.rs`) (inferred:
/// OSM draws centrelines and outlines, not the paved fillets where a taxiway meets a runway or a turn, and its
/// positions are good to a few metres).
pub const PAVEMENT_MARGIN_M: f64 = 5.0;
/// A taxiway without an OSM width (m; inferred: the usual 23 m of a fighter base's taxiway, ICAO code D–E).
const TAXIWAY_WIDTH_M: f64 = 23.0;
/// Mask pixel (m) and the margin around a base's outline.
const MASK_PX_M: f64 = 2.0;
const MASK_MARGIN_M: f64 = 300.0;
// The taxi-line distance the mask's blue channel holds (0 … TAXI_FIELD_M, m): `airbases.gd` draws the line from it;
// the original game's masks hold the same.
use crate::airbases::TAXI_FIELD_M;
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

pub use iaf_avionics::frame::{utm36n, utm36n_geo};

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
    pub fn dir(&self, k: usize) -> [f64; 2] {
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
    /// The end whose take-off a taxiway joining the runway at `p` starts: p lies before that end's declared start or
    /// within END_ENTRY_M past it (along the centreline); None for a join partway along the runway (an intersection).
    pub fn entry_end(&self, p: [f64; 2]) -> Option<usize> {
        (0..2).find(|&k| {
            let u = self.dir(k);
            (p[0] - self.ends[k][0]) * u[0] + (p[1] - self.ends[k][1]) * u[1] < self.starts[k] + END_ENTRY_M
        })
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

/// One thing standing on a base (base-furniture.md §3): its kind, place, grid heading and footprint (m, along the
/// heading × across), or for a fence the line it runs along.
#[derive(Debug, Clone)]
pub struct Item {
    pub kind: String,
    pub at: [f64; 2],
    pub heading: f64,
    pub size: Option<[f64; 2]>,
    pub line: Vec<[f64; 2]>,
}

/// The concrete before a shelter's door (m, inferred: the door's apron reaches the loop taxiway 20–35 m out).
const SHELTER_APRON_M: f64 = 20.0;

/// A furniture row this near a parking spot (m) is the parked jet of the spot's shelter: it gives way to the jet that
/// starts there (inferred: the survey puts a shelter's jet at its middle, as the spot).
const SPOT_CLEAR_M: f64 = 5.0;

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
    /// What stands on the base (`data/furniture/<icao>.json`, base-furniture.md): shelters, hangars, buildings, the
    /// tower, parked jets, ramp props, the fence.
    pub furniture: Vec<Item>,
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
        self.paved_dist(p) <= margin
    }
    /// Metres from p to the nearest runway's or stopway's edge (negative on it).
    pub fn runway_dist(&self, p: [f64; 2]) -> f64 {
        let widest = self.runways.iter().map(|r| r.width).fold(0.0, f64::max);
        let stopways = self.stopways.iter().map(|s| line_dist(p, s) - widest / 2.0);
        self.runways.iter().map(|r| r.dist(p) - r.width / 2.0).chain(stopways).fold(f64::INFINITY, f64::min)
    }
    /// Metres from p to the nearest paved surface of `paved` (≤ 0 on it).
    pub fn paved_dist(&self, p: [f64; 2]) -> f64 {
        let taxiways = self.taxiways.iter().map(|(l, w)| line_dist(p, l) - w / 2.0);
        let pads = self
            .aprons
            .iter()
            .chain(&self.shelters)
            .map(|poly| if inside(poly, p) { 0.0 } else { line_dist(p, &[poly, &poly[..1]].concat()) });
        taxiways.chain(pads).fold(self.runway_dist(p), f64::min)
    }
}

/// Metres from p to the polyline `l`.
fn line_dist(p: [f64; 2], l: &[[f64; 2]]) -> f64 {
    l.windows(2).map(|s| seg_dist(p, s[0], s[1])).fold(f64::INFINITY, f64::min)
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

/// The airbase files of `dir` (every `.json`), each with its parking spots from `<dir>/../parking.json` by ICAO code
/// (airbases.md §5; their own file: the theatre's stamp hashes the airbase files, `sim_terrain::stamp`, and a moved
/// spot leaves the theatre as built).
pub fn files(dir: &Path) -> Result<Vec<Value>> {
    let read = |p: &Path| -> Result<Value> {
        serde_json::from_slice(&std::fs::read(p).with_context(|| format!("{}", p.display()))?)
            .with_context(|| format!("{}", p.display()))
    };
    let spots = dir.with_file_name("parking.json");
    let spots = if spots.exists() { read(&spots)? } else { Value::Null };
    let furniture = dir.with_file_name("furniture");
    let mut paths: Vec<_> = std::fs::read_dir(dir)
        .with_context(|| format!("{}", dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "json"))
        .collect();
    paths.sort();
    let mut out = Vec::new();
    for p in paths {
        let mut v = read(&p)?;
        if !spots.is_null() {
            let icao = v["icao"].as_str().unwrap_or("");
            ensure!(spots[icao].is_array(), "parking.json: no spots for {icao:?} ({})", p.display());
            v["parking"] = spots[icao].clone();
        }
        let f = furniture.join(format!("{}.json", v["icao"].as_str().unwrap_or("").to_lowercase()));
        if f.exists() {
            v["furniture"] = read(&f)?["rows"].clone();
        }
        out.push(v);
    }
    Ok(out)
}

/// The bases of `files(dir)`, in BASES' order.
pub fn load(dir: &Path) -> Result<Vec<Base>> {
    let files = files(dir)?;
    BASES
        .iter()
        .map(|(icao, ..)| {
            let path = dir.join(format!("{}.json", icao.to_lowercase()));
            let v = files.iter().find(|v| v["icao"] == *icao).with_context(|| format!("{}", path.display()))?;
            base(v, &path.display().to_string())
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
    // A spot in a shelter (`shelter`: the ref of a furniture row of kind shelter) stands at its middle, nose to the door
    // (airbases.md §5).
    let rows = v["furniture"].as_array().map_or(&[][..], |a| a.as_slice());
    let parking = v["parking"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|p| -> Result<Spot> {
            let place = match p["shelter"].as_str() {
                Some(s) => rows
                    .iter()
                    .find(|r| r["ref"] == s && r["kind"] == "shelter")
                    .with_context(|| format!("{what}: the parking spot's shelter {s:?} is no shelter of the base"))?,
                None => p,
            };
            let (lat, lon) =
                (place["lat"].as_f64().context("parking lat")?, place["lon"].as_f64().context("parking lon")?);
            Ok(Spot {
                unit: p["unit"].as_str().unwrap_or("").to_string(),
                at: utm36n(lon, lat),
                heading: grid_heading(lon, lat, place["heading"].as_f64().context("parking heading")?),
            })
        })
        .collect::<Result<Vec<_>>>()?;
    let mut furniture = Vec::new();
    for r in v["furniture"].as_array().into_iter().flatten() {
        let kind = r["kind"].as_str().with_context(|| format!("{what}: a furniture row needs a kind"))?.to_string();
        if r["along"] == "boundary" {
            furniture.push(Item { kind, at: [0.0; 2], heading: 0.0, size: None, line: line(&v["boundary"]) });
            continue;
        }
        let (lat, lon) = (r["lat"].as_f64(), r["lon"].as_f64());
        let ((Some(lat), Some(lon)), Some(h)) = ((lat, lon), r["heading"].as_f64()) else {
            anyhow::bail!("{what}: furniture {} needs lat, lon and heading", r["ref"]);
        };
        let size = r["size_m"].as_array().and_then(|a| Some([a.first()?.as_f64()?, a.get(1)?.as_f64()?]));
        let at = utm36n(lon, lat);
        // A parked jet in a start spot's shelter gives way to the jet that starts there.
        if kind != "shelter" && parking.iter().any(|s| dist(s.at, at) < SPOT_CLEAR_M) {
            continue;
        }
        furniture.push(Item { kind, at, heading: grid_heading(lon, lat, h), size, line: vec![] });
    }
    // A shelter's pad and the concrete before its door are paved (the mask draws them as an apron).
    let mut shelters = polys("shelters");
    for f in furniture.iter().filter(|f| f.kind == "shelter") {
        let [l, w] = f.size.unwrap_or([30.0, 24.0]);
        let d = [f.heading.to_radians().sin(), f.heading.to_radians().cos()];
        let n = [d[1], -d[0]];
        let at = |a: f64, c: f64| [f.at[0] + d[0] * a + n[0] * c, f.at[1] + d[1] * a + n[1] * c];
        let (back, front) = (-l / 2.0, l / 2.0 + SHELTER_APRON_M);
        shelters.push(vec![at(back, -w / 2.0), at(front, -w / 2.0), at(front, w / 2.0), at(back, w / 2.0)]);
    }
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
        shelters,
        parking,
        furniture,
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
/// taxiways meet only through the runways), a metre along a runway costing RUNWAY_TAXI_COST.
/// A metre taxied along a runway counts as this many on a taxiway (inferred): the departure takes the taxiways to the
/// runway's start and crosses a runway rather than back-taxi on it (until 2026-11-15 Ramon's joined 07L/25R 1 km from
/// 07L and back-taxied 1.7 km to 25R's start, the user: "not to the middle of the runway, it's confusing"); a back-taxi
/// stays where no taxiway leads to the start.
const RUNWAY_TAXI_COST: f64 = 4.0;
/// Taxiway junctions nearer each other than this (m) count as one (inferred: a jet passes both in a length).
const JOIN_M: f64 = 12.0;

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
                g.link(a, b, 1.0);
            }
        }
        // Junctions nearer each other than JOIN_M are one (a jet reads one sign for them; Hatzerim's fillets join the
        // parallel taxiway 5–10 m apart): the later one's ways go from the first.
        for a in 0..g.pts.len() {
            if g.adj[a].len() < 3 {
                continue;
            }
            while let Some(&(b, _)) = g.adj[a].iter().find(|&&(b, w)| w < JOIN_M && b != a && g.adj[b].len() >= 3) {
                g.merge(a, b);
            }
        }
        // So are two taxiways' points on a runway (Nevatim's crossing of 08R/26L, its two sides 11 m apart along the
        // runway: a jet crosses straight on).
        for r in runways {
            let on: Vec<usize> = (0..g.pts.len()).filter(|&k| r.dist(g.pts[k]) <= r.width / 2.0 + 5.0).collect();
            for (i, &a) in on.iter().enumerate() {
                for &b in &on[i + 1..] {
                    if !g.adj[a].is_empty() && !g.adj[b].is_empty() && dist(g.pts[a], g.pts[b]) < JOIN_M {
                        g.merge(a, b);
                    }
                }
            }
        }
        for r in runways {
            let mut on: Vec<(f64, usize)> = (0..g.pts.len())
                .filter(|&k| !g.adj[k].is_empty() && r.dist(g.pts[k]) <= r.width / 2.0 + 5.0)
                .map(|k| (dist(g.pts[k], r.ends[0]), k))
                .collect();
            on.sort_by(|a, b| a.0.total_cmp(&b.0));
            for w in on.windows(2) {
                g.link(w[0].1, w[1].1, RUNWAY_TAXI_COST);
            }
        }
        g
    }

    /// Makes point `b` one with `a`: its ways go from `a`.
    fn merge(&mut self, a: usize, b: usize) {
        let ways = std::mem::take(&mut self.adj[b]);
        self.adj[a].retain(|x| x.0 != b);
        for (n, _) in ways {
            self.adj[n].retain(|x| x.0 != b);
            if n != a && !self.adj[a].iter().any(|x| x.0 == n) {
                self.link(a, n, 1.0);
            }
        }
    }

    fn link(&mut self, a: usize, b: usize, cost: f64) {
        if a != b {
            let d = dist(self.pts[a], self.pts[b]) * cost;
            self.adj[a].push((b, d));
            self.adj[b].push((a, d));
        }
    }

    fn nearest(&self, p: [f64; 2]) -> Option<usize> {
        (0..self.pts.len())
            .filter(|&k| !self.adj[k].is_empty())
            .min_by(|&a, &b| dist(self.pts[a], p).total_cmp(&dist(self.pts[b], p)))
    }

    /// The shortest ways to `to` (Dijkstra from it): each point's next point toward `to` (usize::MAX for `to` and the
    /// points not joined to it).
    fn toward(&self, to: usize) -> Vec<usize> {
        let mut best = vec![f64::INFINITY; self.pts.len()];
        let mut next = vec![usize::MAX; self.pts.len()];
        let mut heap = BinaryHeap::new();
        best[to] = 0.0;
        // Non-negative f64s order as their bits.
        heap.push(std::cmp::Reverse((0f64.to_bits(), to)));
        while let Some(std::cmp::Reverse((d, k))) = heap.pop() {
            let d = f64::from_bits(d);
            if d > best[k] {
                continue;
            }
            for &(n, w) in &self.adj[k] {
                if d + w < best[n] {
                    best[n] = d + w;
                    next[n] = k;
                    heap.push(std::cmp::Reverse(((d + w).to_bits(), n)));
                }
            }
        }
        next
    }

    /// The shortest path from `a` to `b`, its points; None when they are not joined.
    fn path(&self, a: usize, b: usize) -> Option<Vec<[f64; 2]>> {
        let next = self.toward(b);
        let mut out = vec![self.pts[a]];
        let mut k = a;
        while k != b {
            k = *next.get(k).filter(|&&n| n != usize::MAX)?;
            out.push(self.pts[k]);
        }
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

/// The AI's routes of a base (iaf.ibx): `hub` is where the first parking spot's way out meets its lane; `from` the
/// hub → the take-off lineup (departure), `to` the landing roll's end → the hub (arrival, from the far end's runway
/// start, where a jet that landed on the take-off runway leaves it). `out` and `back` are the same for each parking
/// spot from and to its own way out (its point on its lane): a spot in a shelter has its own way along the taxiways
/// (airbases.md §5); `out[0]` is `from`, `back[0]` is `to`.
pub struct Routes {
    pub hub: [f64; 2],
    pub from: Vec<[f64; 2]>,
    pub to: Vec<[f64; 2]>,
    pub out: Vec<Vec<[f64; 2]>>,
    pub back: Vec<Vec<[f64; 2]>>,
}

impl Routes {
    /// The taxi from the parking spot at `at` to the lineup: the spot, then its departure (the first spot's for a
    /// place that is no spot).
    pub fn departure_from(&self, b: &Base, at: [f64; 2]) -> Vec<[f64; 2]> {
        let i = b.parking.iter().position(|p| dist(p.at, at) < 0.5);
        std::iter::once(at).chain(i.map_or(&self.from, |i| &self.out[i]).iter().copied()).collect()
    }
}

/// The taxiways with each parking spot joined to them: a way from the spot along its nose to the first taxiway it meets
/// within SPOT_EXIT_M (the lane the spots stand square to, airbases.md §5), else to the nearest taxiway point; the
/// point is added to that taxiway. A jet leaves its spot by that way (a sign faces it there; the departure starts on it).
pub fn taxi_lines(b: &Base) -> Vec<(Vec<[f64; 2]>, f64)> {
    let mut lines = b.taxiways.clone();
    for s in &b.parking {
        let n = [s.heading.to_radians().sin(), s.heading.to_radians().cos()];
        let ahead = [s.at[0] + n[0] * SPOT_EXIT_M, s.at[1] + n[1] * SPOT_EXIT_M];
        // (line, segment, the point): the nose's nearest hit, else the nearest point of any taxiway.
        let mut hit: Option<(usize, usize, [f64; 2])> = None;
        let mut near: Option<(usize, usize, [f64; 2])> = None;
        // The base's taxiways only: an earlier spot's way out is no lane.
        for (li, (l, _)) in lines.iter().enumerate().take(b.taxiways.len()) {
            for (si, w) in l.windows(2).enumerate() {
                if let Some(t) = cross_at(s.at, ahead, w[0], w[1]) {
                    let q = [w[0][0] + (w[1][0] - w[0][0]) * t, w[0][1] + (w[1][1] - w[0][1]) * t];
                    if hit.is_none_or(|h| dist(s.at, q) < dist(s.at, h.2)) {
                        hit = Some((li, si, q));
                    }
                }
                let (dx, dy) = (w[1][0] - w[0][0], w[1][1] - w[0][1]);
                let t = (((s.at[0] - w[0][0]) * dx + (s.at[1] - w[0][1]) * dy) / (dx * dx + dy * dy).max(1e-9))
                    .clamp(0.0, 1.0);
                let q = [w[0][0] + dx * t, w[0][1] + dy * t];
                if near.is_none_or(|h| dist(s.at, q) < dist(s.at, h.2)) {
                    near = Some((li, si, q));
                }
            }
        }
        let Some((li, si, q)) = hit.or(near) else { continue };
        let l = &mut lines[li].0;
        let q = if dist(q, l[si]) <= 1.0 {
            l[si]
        } else if dist(q, l[si + 1]) <= 1.0 {
            l[si + 1]
        } else {
            l.insert(si + 1, q);
            q
        };
        lines.push((vec![s.at, q], TAXIWAY_WIDTH_M));
    }
    lines
}

/// The farthest a parking spot's nose looks for its lane (m; inferred: the spots stand 20–30 m from it).
const SPOT_EXIT_M: f64 = 60.0;

/// Where segment ab crosses segment cd: the fraction along cd; None when they do not cross.
fn cross_at(a: [f64; 2], b: [f64; 2], c: [f64; 2], d: [f64; 2]) -> Option<f64> {
    let (r, s) = ([b[0] - a[0], b[1] - a[1]], [d[0] - c[0], d[1] - c[1]]);
    let den = r[0] * s[1] - r[1] * s[0];
    if den.abs() < 1e-12 {
        return None;
    }
    let (qx, qy) = (c[0] - a[0], c[1] - a[1]);
    let (t, u) = ((qx * s[1] - qy * s[0]) / den, (qx * r[1] - qy * r[0]) / den);
    ((0.0..=1.0).contains(&t) && (0.0..=1.0).contains(&u)).then_some(u)
}

pub fn routes(b: &Base) -> Result<Routes> {
    let g = Graph::new(&taxi_lines(b), &b.runways);
    let (ri, k) = b.main;
    let r = &b.runways[ri];
    let node = |p: [f64; 2]| g.nearest(p).with_context(|| format!("{}: no taxiways", b.icao));
    // The arrival leaves the runway at the other end's start.
    let exit = node(r.at(1 - k, r.starts[1 - k]))?;
    let (mut out, mut back) = (Vec::new(), Vec::new());
    for s in &b.parking {
        // Where the spot's way out meets its lane.
        let way = g.adj[node(s.at)?][0].0;
        let mut from = taxi_out(b, &g, ri, k, way)?;
        from.push(r.lineup(k));
        let mut to = vec![r.at(1 - k, r.starts[1 - k] + LINEUP_IN_M)];
        to.extend(
            g.path(exit, way).with_context(|| {
                format!("{}: the taxiways do not join {:?} and the {} spot", b.icao, r.ends, s.unit)
            })?,
        );
        out.push(simplify(&from, 8.0));
        back.push(simplify(&to, 8.0));
    }
    Ok(Routes { hub: out[0][0], from: out[0].clone(), to: back[0].clone(), out, back })
}

/// The departure from the first parking spot to end k of runway ri as a jet taxis it: the spot, taxi_out, the lineup;
/// None where the taxiways do not join them.
#[cfg(test)]
fn departure(b: &Base, g: &Graph, ri: usize, k: usize) -> Option<Vec<[f64; 2]>> {
    let out = taxi_out(b, g, ri, k, g.adj[g.nearest(b.parking[0].at)?][0].0).ok()?;
    let r = &b.runways[ri];
    // At an intersection take-off (`takeoff`) the jet lines up where it joins.
    let lineup = if r.entry_end(*out.last()?) == Some(k) { r.lineup(k) } else { *out.last()? };
    Some(std::iter::once(b.parking[0].at).chain(out).chain([lineup]).collect())
}

/// The departure's taxi from node `from` of `g` (where a parking spot's way out meets its lane) to end k of runway
/// ri, joining the runway at its declared start (the first taxiway entry, airbases.md §4): the points of `g` (a Graph
/// of taxi_lines with the runways), unsimplified.
fn taxi_out(b: &Base, g: &Graph, ri: usize, k: usize, from: usize) -> Result<Vec<[f64; 2]>> {
    let r = &b.runways[ri];
    let entry = takeoff(b, g, ri, k).with_context(|| format!("{}: no taxiway joins {}", b.icao, r.designators[k]))?;
    g.path(from, entry)
        .with_context(|| format!("{}: the taxiways do not join a parking spot and {}", b.icao, r.designators[k]))
}

// --- taxiway signs --------------------------------------------------------------------------------------------------

/// A runway-holding sign's distance from the runway's centreline (m; ICAO Annex 14 Table 3-2: 90 m for a code 4
/// instrument runway, the bases' class).
const HOLD_M: f64 = 90.0;
/// A direction sign's distance before its junction (m; inferred: the boards stand before the turn, ICAO Annex 14
/// 5.4.3.30 and the Aerodrome Design Manual's 30–60 m).
const DIRECTION_BACK_M: f64 = 40.0;
/// A taxiway meeting a runway this near its end (m along the runway, or past it) enters at that take-off end
/// (inferred).
const END_ENTRY_M: f64 = 400.0;
/// A sign's offset from the taxiway's edge (m; Annex 14 Table 5-5: 11–21 m from the edge for code D–F taxiways).
const SIGN_EDGE_M: f64 = 12.0;
/// A sign's least distance from a runway's edge (m; Annex 14 Table 5-5: 8–15 m for code 3 and 4 runways. On
/// 2026-11-17 a direction sign after Ramon's crossing of 07R/25L stood 5 m from the runway).
const SIGN_RUNWAY_M: f64 = 8.0;

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
/// way toward the jet that reads it), its boards left to right; `road` the point on the taxiway's centreline beside it.
#[derive(Debug, Clone)]
pub struct Sign {
    pub at: [f64; 2],
    pub facing: f64,
    pub panels: Vec<Panel>,
    pub road: [f64; 2],
    /// How far back from `road` along its taxiway a jet reads it (m; READ_FROM_M's farthest, or the way's length where
    /// a shorter way leads there: a parking spot's way out).
    pub read: f64,
}

/// Two signs for the same taxiing jet nearer than this (m) stand as one array (inferred: 2026-11-13 a holding sign
/// 5–10 m before a direction sign hid it at Ramon 25L and Nevatim 26L).
pub const SIGN_GAP_M: f64 = 25.0;
/// Signs facing different ways (other taxiways' signs at a junction) stand at least this far apart (m; inferred: two
/// 3 m boards and room between them).
pub const SIGN_APART_M: f64 = 8.0;
/// A board in the line of sight hides a sign's legend only this near it, as a share of the eye's distance (inferred: an
/// eye 2.5 m up, the boards' tops 1.1 m up and the legend's middle 0.65 m, sign_boards.gd: (2.5 − 1.1) / (2.5 − 0.65)).
const HIDE_SHARE: f64 = 0.75;
/// The stretch of centreline (m before a sign) from which a jet reads it (inferred: a 0.45 m legend reads at 150 m).
const READ_FROM_M: [f64; 2] = [15.0, 150.0];

impl Sign {
    /// The board's width (m), as `sign_boards.gd board()` builds it (0.3 m + 0.34 m a character + 0.6 m an arrow).
    pub fn width(&self) -> f64 {
        0.1 + self.panels.iter().map(|p| 0.3 + 0.34 * p.text.len() as f64 + p.arrow.map_or(0.0, |_| 0.6)).sum::<f64>()
    }

    /// The board's two ends.
    fn ends(&self) -> [[f64; 2]; 2] {
        let f = self.facing.to_radians();
        let (h, a) = (self.width() / 2.0, self.at);
        // Across the face: perpendicular to the facing vector (sin f, cos f).
        [[a[0] - f.cos() * h, a[1] + f.sin() * h], [a[0] + f.cos() * h, a[1] - f.sin() * h]]
    }

    /// Whether `self` stands in a jet's line of sight to any part of `other`, the jet on the taxiway's centreline
    /// READ_FROM_M (up to `other.read`) before `other` (taxiing along −facing, the sign facing it). The pilot looks
    /// down over a nearer board: only one in the last HIDE_SHARE of the way to `other` covers its legend (until
    /// 2026-11-17 any board on the line seen from above, which left signs out where junctions crowd).
    pub fn hides(&self, other: &Sign) -> bool {
        let f = other.facing.to_radians();
        let [e0, e1] = self.ends();
        let far = other.read.max(READ_FROM_M[0] + 1.0);
        (0..=27).map(|i| READ_FROM_M[0] + (far - READ_FROM_M[0]) * i as f64 / 27.0).any(|s| {
            let eye = [other.road[0] + f.sin() * s, other.road[1] + f.cos() * s];
            other.ends().into_iter().chain([other.at]).any(|t| cross_at(e0, e1, eye, t).is_some_and(|u| u > HIDE_SHARE))
        })
    }

    /// Whether the two signs stand too near each other (SIGN_GAP_M for one jet's signs, along the same way; else
    /// SIGN_APART_M: other ways' signs, or the signs of neighbouring parking spots' ways out, side by side) or one
    /// hides the other.
    pub fn crowds(&self, other: &Sign) -> bool {
        let gap = if self.same_lane(other) { SIGN_GAP_M } else { SIGN_APART_M };
        dist(self.at, other.at) < gap || self.hides(other) || other.hides(self)
    }

    /// Whether the two are signs for one taxiing jet: facing the same way, their centreline points within 15 m across
    /// that way.
    pub fn same_lane(&self, other: &Sign) -> bool {
        let f = self.facing.to_radians();
        let across = (other.road[0] - self.road[0]) * f.cos() - (other.road[1] - self.road[1]) * f.sin();
        self.same_way(other) && across.abs() < 15.0
    }

    /// Whether the two face the same way (within 45°): signs for the same taxiing jet.
    pub fn same_way(&self, other: &Sign) -> bool {
        ((self.facing - other.facing + 180.0).rem_euclid(360.0) - 180.0).abs() < 45.0
    }
}

/// Adds a sign at the first of `spots` (its place, and the centreline point beside it, `Sign::road`) for a jet taxiing
/// along `d`, or folds it into
/// one already there. A sign that crowds a sign facing the same way joins it as one array where one of the two is a
/// holding sign (two junctions' direction signs stay apart: each names where its own junction leads): the holding position stays where it is (FAA AIM 2-3-8: the holding
/// marking in line with the sign), its direction boards left to right by their turn ("arranged clockwise starting from
/// the first taxiway on the pilot's left", AIM 2-3-10), the mandatory board inboard, on the taxiway's side (as a
/// location sign collocated with a holding sign stands outboard of it, AIM 2-3-9; inferred for direction boards).
/// Otherwise it takes the first of `spots` that crowds none, else it is left out.
fn place(out: &mut Vec<Sign>, d: [f64; 2], spots: Vec<([f64; 2], [f64; 2], f64)>, panels: Vec<Panel>) -> bool {
    let facing = grid_deg([-d[0], -d[1]]);
    let Some(&(at, road, read)) = spots.first() else { return false };
    let new = Sign { at, facing, panels, road, read };
    let directions = |s: &Sign| s.panels.iter().any(|p| p.style == "direction");
    let joins = |o: &Sign| o.same_lane(&new) && dist(o.at, new.at) < SIGN_GAP_M && !(directions(o) && directions(&new));
    if let Some(o) = out.iter_mut().find(|o| joins(o)) {
        let mut all: Vec<Panel> = Vec::new();
        for q in o.panels.iter().chain(new.panels.iter()) {
            if !all.iter().any(|a| a.style == q.style && a.text == q.text) {
                all.push(q.clone());
            }
        }
        all.sort_by(|a, b| {
            (a.style == "mandatory")
                .cmp(&(b.style == "mandatory"))
                .then(a.arrow.unwrap_or(0.0).total_cmp(&b.arrow.unwrap_or(0.0)))
                .then(a.text.cmp(&b.text))
        });
        o.panels = all;
        return true;
    }
    for &(at, road, read) in &spots {
        let s = Sign { at, road, read, ..new.clone() };
        if !out.iter().any(|o| o.crowds(&s)) {
            out.push(s);
            return true;
        }
    }
    // Where junctions crowd (Hatzerim's sunshade rows), the first place SIGN_APART_M from every sign: a sign that may
    // stand in another's line of sight beats a junction without one.
    for (at, road, read) in spots {
        let s = Sign { at, road, read, ..new.clone() };
        if !out.iter().any(|o| dist(o.at, s.at) < SIGN_APART_M) {
            out.push(s);
            return true;
        }
    }
    false
}

fn grid_deg(d: [f64; 2]) -> f64 {
    d[0].atan2(d[1]).to_degrees().rem_euclid(360.0)
}

fn unit(a: [f64; 2], b: [f64; 2]) -> [f64; 2] {
    let l = dist(a, b).max(1e-9);
    [(b[0] - a[0]) / l, (b[1] - a[1]) / l]
}

/// The places for a sign beside a jet at `p` taxiing along the unit `d`, in order: SIGN_EDGE_M past the taxiway's
/// edge on its left, then farther out, then on its right (Annex 14 5.4.1.4), those off the paved surface (`paved`).
fn sign_spots(p: [f64; 2], d: [f64; 2], half: f64, paved: &dyn Fn([f64; 2]) -> bool) -> Vec<[f64; 2]> {
    [1.0, -1.0]
        .iter()
        .flat_map(|side| [0.0, 8.0, 18.0].map(|more| side * (half + SIGN_EDGE_M + more)))
        .map(|off| [p[0] - d[1] * off, p[1] + d[0] * off])
        // The board's ends too (a 3 m sign).
        .filter(|q| [-2.0, 0.0, 2.0].iter().all(|k| !paved([q[0] + d[1] * k, q[1] - d[0] * k])))
        .collect()
}

/// The base's taxiway signs (ICAO Annex 14 §5.4), each naming only where it leads (the user, 2026-11-17: "how
/// possible 25L and 07R are on the same sign"):
/// - a runway-holding sign (mandatory) where each taxiway comes within HOLD_M of a runway's centreline, with the one
///   end a jet takes off from there: at a runway's start that end (FAA AIM 2-3-8), partway along the end with the
///   more runway ahead (the one nearer the join; inferred);
/// - at each junction of three or more ways, for a jet arriving on each branch where it has a choice (two or more of
///   the other branches lead on to a runway), a direction sign with a board for each runway start whose shortest taxi
///   leaves the junction by another branch: its designator and the arrow of that branch. Every board of every sign
///   on the way sends a jet along the same shortest taxi, so a jet that follows one end's boards from anywhere reaches
///   that end's start (`sim_bases::tests::following_the_signs_reaches_every_runway_start`).
///
/// The sign stands DIRECTION_BACK_M before the junction on the jet's left, or, where the branch is shorter (a parking
/// spot's way out, a short link), across the junction facing the jet (inferred). The parking spots' ways out
/// (taxi_lines) are branches too. OpenStreetMap names none of the bases' taxiways, so no location sign.
pub fn signs(b: &Base) -> Vec<Sign> {
    let lines = taxi_lines(b);
    let routed = Graph::new(&lines, &b.runways);
    let m = mask(b);
    // Where no sign stands: the paved surface, and beside a runway nearer than SIGN_RUNWAY_M from its edge.
    let paved = |q: [f64; 2]| {
        let (x, y) = ((q[0] - m.origin[0]) / MASK_PX_M, (m.origin[1] - q[1]) / MASK_PX_M);
        (x >= 0.0
            && y >= 0.0
            && (x as usize) < m.w
            && (y as usize) < m.h
            && m.img.get_pixel(x as u32, y as u32)[0] >= 64)
            || b.runways.iter().any(|r| r.dist(q) < r.width / 2.0 + SIGN_RUNWAY_M)
    };
    let half = |p: [f64; 2]| {
        b.taxiways
            .iter()
            .filter(|(l, _)| l.windows(2).any(|s| seg_dist(p, s[0], s[1]) < 1.0))
            .map(|(_, w)| w / 2.0)
            .chain(b.runways.iter().filter(|r| r.dist(p) <= r.width / 2.0 + 5.0).map(|r| r.width / 2.0))
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
                let nearer = if dist(p, r.ends[0]) < dist(p, r.ends[1]) { 0 } else { 1 };
                let text = r.designators[r.entry_end(p).unwrap_or(nearer)].clone();
                // The same holding position once (two ways drawn over each other); another taxiway's, 37 m away at
                // Nevatim's 08R, has its own sign.
                if out.iter().any(|o| dist(o.road, p) < JOIN_M && o.panels.iter().any(|q| q.text == text)) {
                    continue;
                }
                let spots = sign_spots(p, d, w / 2.0, &paved).into_iter().map(|q| (q, p, READ_FROM_M[1])).collect();
                place(&mut out, d, spots, vec![Panel { style: "mandatory", text, arrow: None }]);
            }
        }
    }
    // Each runway end's take-off point (`takeoff`) and every point's next point on the shortest taxi there.
    let starts: Vec<(&String, Vec<usize>)> = b
        .runways
        .iter()
        .enumerate()
        .flat_map(|(ri, r)| (0..2).map(move |k| (ri, r, k)))
        .filter_map(|(ri, r, k)| Some((&r.designators[k], routed.toward(takeoff(b, &routed, ri, k)?))))
        .collect();
    // The junctions the taxis from the parking spots to the starts pass, by the branch they arrive on: the ends
    // whose taxi passes there. Only these get direction signs (the user, 2026-11-17: "I need something that isn't
    // confusing"): a jet that leaves the shortest taxi has left the signs' way.
    let mut used: std::collections::BTreeMap<(usize, usize), Vec<usize>> = Default::default();
    for (e, (_, next)) in starts.iter().enumerate() {
        for s in &b.parking {
            let Some(mut cur) = routed.nearest(s.at) else { continue };
            let mut prev = usize::MAX;
            while next[cur] != usize::MAX {
                // On a runway only where the taxi turns off the straightest way (a back-taxi, an offset crossing): a
                // jet crosses a runway straight on.
                let turns = on_runway(routed.pts[cur]).is_none() || straightest(&routed, prev, cur) != Some(next[cur]);
                if prev != usize::MAX && routed.adj[cur].len() >= 3 && turns {
                    let ends = used.entry((cur, prev)).or_default();
                    if !ends.contains(&e) {
                        ends.push(e);
                    }
                }
                (prev, cur) = (cur, next[cur]);
            }
        }
    }
    for (&(j, arrive), ends) in &used {
        let mut branches: Vec<usize> = routed.adj[j].iter().map(|a| a.0).collect();
        branches.sort();
        branches.dedup();
        let live: Vec<usize> = branches.iter().copied().filter(|&n| leads_on(&routed, j, n, &on_runway)).collect();
        let others: Vec<usize> = live.iter().copied().filter(|&n| n != arrive).collect();
        if branches.len() < 3 || others.len() < 2 {
            continue;
        }
        // Before the junction: DIRECTION_BACK_M back on the jet's left, else nearer or farther, either side;
        // where the branch is shorter (a spot's way out, a short link), across the junction facing the jet, else
        // beside the branch's last metres (inferred).
        let d = unit(routed.pts[arrive], routed.pts[j]);
        let mut spots: Vec<([f64; 2], [f64; 2], f64)> = Vec::new();
        // Where the taxi turns on a runway, before the holding position (beside the holding sign).
        let backs = if on_runway(routed.pts[j]).is_some() {
            [HOLD_M + 15.0, HOLD_M + 30.0, HOLD_M + 45.0, HOLD_M + 5.0, HOLD_M + 60.0]
        } else {
            [DIRECTION_BACK_M, 30.0, 50.0, 20.0, 60.0]
        };
        for back_m in backs {
            if let Some((p, d)) = back(&routed, j, arrive, back_m) {
                spots.extend(sign_spots(p, d, half(p), &paved).into_iter().map(|q| (q, p, READ_FROM_M[1])));
            }
        }
        if spots.is_empty() {
            let j0 = routed.pts[j];
            // The way's length back to its last junction or end.
            let branch_m = (1..=40)
                .map(|m| m as f64 * 5.0)
                .take_while(|&m| back(&routed, j, arrive, m).is_some())
                .last()
                .unwrap_or(0.0)
                + 5.0;
            let far = [j0[0] + d[0] * (half(j0) + SIGN_EDGE_M), j0[1] + d[1] * (half(j0) + SIGN_EDGE_M)];
            spots.extend(
                [0.0, 6.0, -6.0, 12.0, -12.0]
                    .map(|s| [far[0] - d[1] * s, far[1] + d[0] * s])
                    .into_iter()
                    .filter(|q| [-2.0, 0.0, 2.0].iter().all(|k| !paved([q[0] + d[1] * k, q[1] - d[0] * k])))
                    .map(|q| (q, j0, branch_m)),
            );
            for back_m in [10.0, 15.0, 6.0].into_iter().filter(|&m| m < branch_m - 6.0) {
                let near = [j0[0] - d[0] * back_m, j0[1] - d[1] * back_m];
                let read = branch_m - back_m;
                spots.extend(sign_spots(near, d, half(near), &paved).into_iter().map(|q| (q, near, read)));
            }
        }
        if spots.is_empty() {
            // Paved all round (an apron's middle): beside the way all the same, farthest out on the left.
            let j0 = routed.pts[j];
            let off = half(j0) + SIGN_EDGE_M + 18.0;
            let p = [j0[0] - d[0] * 15.0, j0[1] - d[1] * 15.0];
            spots.push(([p[0] - d[1] * off, p[1] + d[0] * off], p, READ_FROM_M[1]));
        }
        let mut panels: Vec<Panel> = ends
            .iter()
            .map(|&e| &starts[e])
            .map(|(end, next)| Panel {
                style: "direction",
                text: end.to_string(),
                arrow: Some(arrow(&routed.pts, j, d, next[j], &others)),
            })
            .collect();
        // Left to right, as the turns.
        panels.sort_by(|a, b| a.arrow.unwrap_or(0.0).total_cmp(&b.arrow.unwrap_or(0.0)).then(a.text.cmp(&b.text)));
        if !panels.is_empty() {
            place(&mut out, d, spots, panels);
        }
    }
    out
}

/// The turn (degrees, positive to the right) of a jet taxiing along the unit `d` onto the unit `o`.
fn turn(d: [f64; 2], o: [f64; 2]) -> f64 {
    -(d[0] * o[1] - d[1] * o[0]).atan2(d[0] * o[0] + d[1] * o[1]).to_degrees()
}

/// A direction board's arrow toward `to` among the ways `ways` from a junction at `j`, for a jet arriving along the
/// unit `d`: the turn in 45° steps, or in 15° steps where another way rounds to the same 45° (a narrow fork).
fn arrow(pts: &[[f64; 2]], j: usize, d: [f64; 2], to: usize, ways: &[usize]) -> f64 {
    let t = |n: usize| turn(d, unit(pts[j], pts[n]));
    let step = |n: usize, s: f64| (t(n) / s).round() * s + 0.0;
    if ways.iter().any(|&n| n != to && step(n, 45.0) == step(to, 45.0)) { step(to, 15.0) } else { step(to, 45.0) }
}

/// Where a jet joins runway ri to take off from end k (a point of `g`, a Graph of taxi_lines with the runways): the
/// taxiway's join at the declared start (Runway::entry_end); where none joins there, the first join from that end, an
/// intersection take-off (Nevatim's 07, 1212 m in: before 2026-11-17 no sign or route led to 07). None where no
/// taxiway joins the runway (Hatzerim's 10/28: OpenStreetMap joins none of its taxiways to the base's).
fn takeoff(b: &Base, g: &Graph, ri: usize, k: usize) -> Option<usize> {
    let r = &b.runways[ri];
    let entry = g.nearest(r.at(k, r.starts[k]))?;
    if r.entry_end(g.pts[entry]) == Some(k) {
        return Some(entry);
    }
    let u = r.dir(k);
    let along = |p: [f64; 2]| (p[0] - r.ends[k][0]) * u[0] + (p[1] - r.ends[k][1]) * u[1];
    // The runway's points that a taxiway reaches: on it, with a way off it.
    (0..g.pts.len())
        .filter(|&n| r.dist(g.pts[n]) <= r.width / 2.0 + 5.0)
        .filter(|&n| g.adj[n].iter().any(|a| r.dist(g.pts[a.0]) > r.width / 2.0 + 5.0))
        .min_by(|&a, &c| along(g.pts[a]).total_cmp(&along(g.pts[c])))
}

/// The way on from `cur` (arriving from `prev`) with the least turn, None at the start or a dead end.
fn straightest(g: &Graph, prev: usize, cur: usize) -> Option<usize> {
    if prev == usize::MAX {
        return None;
    }
    let d = unit(g.pts[prev], g.pts[cur]);
    let t = |n: &usize| turn(d, unit(g.pts[cur], g.pts[*n])).abs();
    g.adj[cur].iter().map(|a| a.0).filter(|&n| n != prev).min_by(|a, c| t(a).total_cmp(&t(c)))
}

/// Whether the branch from junction `j` through `n` leads on to a runway (not only to parking spots or a dead end).
fn leads_on(g: &Graph, j: usize, n: usize, on_runway: &dyn Fn([f64; 2]) -> Option<usize>) -> bool {
    let mut seen = vec![false; g.pts.len()];
    seen[j] = true;
    seen[n] = true;
    let mut todo = vec![n];
    while let Some(k) = todo.pop() {
        if on_runway(g.pts[k]).is_some() {
            return true;
        }
        for &(m, _) in &g.adj[k] {
            if !seen[m] {
                seen[m] = true;
                todo.push(m);
            }
        }
    }
    false
}

/// The point `m` metres back from junction `j` along the branch through `n` (bends followed), and the way a jet taxis
/// there toward `j`; None when the branch ends or meets another junction sooner.
fn back(g: &Graph, j: usize, n: usize, m: f64) -> Option<([f64; 2], [f64; 2])> {
    let (mut prev, mut cur, mut left) = (j, n, m);
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
    let bb = crate::bbox(pts);
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
    let polys: Vec<&[[f64; 2]]> = b.aprons.iter().chain(&b.shelters).map(|p| p.as_slice()).collect();
    let before: Vec<u8> = px.iter().step_by(3).copied().collect();
    for p in &polys {
        fill_spans(w, h, origin, MASK_PX_M, &[p], |y, x0, x1| {
            for x in x0..x1 {
                px[(y * w + x) * 3] = 255;
                px[(y * w + x) * 3 + 1] = 255;
            }
        });
    }
    // The outlines' coverage as the runways' and taxiways' (a pixel's width of soft edge, from the signed distance to
    // the outline): a pixel either in or out left the aprons' slanted edges saw-toothed against the sand (Ramon,
    // Nevatim, 2026-11-13). A pixel within a pixel of an outline takes its best coverage over the polygons near it.
    let boxes: Vec<[f64; 4]> = polys
        .iter()
        .map(|p| {
            p.iter().fold([f64::MAX, f64::MAX, f64::MIN, f64::MIN], |a, q| {
                [a[0].min(q[0]), a[1].min(q[1]), a[2].max(q[0]), a[3].max(q[1])]
            })
        })
        .collect();
    let mut edge = vec![false; w * h];
    for p in &polys {
        for k in 0..p.len() {
            let (a, c) = (p[k], p[(k + 1) % p.len()]);
            let x0 = (((a[0].min(c[0]) - MASK_PX_M - origin[0]) / MASK_PX_M).floor().max(0.0) as usize).min(w);
            let x1 = (((a[0].max(c[0]) + MASK_PX_M - origin[0]) / MASK_PX_M).ceil().max(0.0) as usize).min(w);
            let y0 = (((origin[1] - a[1].max(c[1]) - MASK_PX_M) / MASK_PX_M).floor().max(0.0) as usize).min(h);
            let y1 = (((origin[1] - a[1].min(c[1]) + MASK_PX_M) / MASK_PX_M).ceil().max(0.0) as usize).min(h);
            for y in y0..y1 {
                for x in x0..x1 {
                    edge[y * w + x] |= seg_dist(centre(x, y), a, c) < MASK_PX_M;
                }
            }
        }
    }
    for i in (0..w * h).filter(|&i| edge[i]) {
        let q = centre(i % w, i / w);
        let cover = polys
            .iter()
            .zip(&boxes)
            .filter(|(_, bb)| q[0] > bb[0] - MASK_PX_M && q[0] < bb[2] + MASK_PX_M)
            .filter(|(_, bb)| q[1] > bb[1] - MASK_PX_M && q[1] < bb[3] + MASK_PX_M)
            .map(|(p, _)| {
                let d = (0..p.len()).map(|k| seg_dist(q, p[k], p[(k + 1) % p.len()])).fold(f64::MAX, f64::min);
                let signed = if inside(p, q) { d } else { -d };
                0.5 + signed / MASK_PX_M
            })
            .fold(0.0, f64::max);
        px[i * 3] = before[i].max(byte(cover));
        px[i * 3 + 1] = byte(cover);
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

    /// The mask's paved surface and the AI's taxi paths of `rt` for every parking spot of `b` (each spot to the
    /// lineup, the landing roll's end to each spot's way out) at TAXIWAY_WIDTH_M: where OpenStreetMap maps no taxiway
    /// along a computed path (a spot's way out to its lane), the jet still rolls on paved ground.
    pub fn with_paths(m: &Mask, b: &Base, rt: &Routes) -> Self {
        let mut p = Self::new(m);
        let half = TAXIWAY_WIDTH_M / 2.0;
        let mut lines: Vec<Vec<[f64; 2]>> = b.parking.iter().map(|s| rt.departure_from(b, s.at)).collect();
        lines.extend(rt.back.iter().cloned());
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
        let bx = crate::bbox(q.iter());
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

/// A base's iaf.ibx section (keys: modern-iaf/docs/data-formats.md §12).
fn ibx_section(b: &Base, rt: &Routes, z: &mut dyn FnMut([f64; 2]) -> f64) -> String {
    let (ri, k) = b.main;
    let r = &b.runways[ri];
    let tower = b.tower_or_reference();
    let lineup = r.lineup(k);
    let mut s = format!(
        "[{}]\n; {} ({}), iaf-sim airbases from modern-iaf/data/airbases/{}.json\n",
        b.section,
        b.name_en,
        b.icao,
        b.icao.to_lowercase()
    );
    s += &format!("TowerLocX={:.1}\nTowerLocY={:.1}\nTowerLocZ={:.1}\n", tower[0], tower[1], z(tower));
    s += &format!("LineupLocX={:.1}\nLineupLocY={:.1}\nLineupLocZ={:.1}\n", lineup[0], lineup[1], z(lineup));
    // The reader truncates RunwayNumber to whole degrees (Section::i32): rounded here.
    s += &format!("RunwayNumber={}\n", r.heading(k).round().rem_euclid(360.0));
    // Ours: the take-off end's designator and the other end's, as painted and signed (the tower says these, not
    // RunwayNumber / 10: Nevatim's 256° is "26L", not "25").
    s += &format!("RunwayDesignator={}\nRunwayDesignatorOpposite={}\n", r.designators[k], r.designators[1 - k]);
    let path = |s: &mut String, prefix: &str, count: &str, p: &[[f64; 2]], last: f64| {
        *s += &format!("{count}={}\n", p.len());
        for (i, q) in p.iter().enumerate() {
            let h = p.get(i + 1).map_or(last, |n| bearing(*q, *n));
            *s += &format!("{prefix}X{i}={:.1}\n{prefix}Y{i}={:.1}\n{prefix}Hdg{i}={:.0}\n", q[0], q[1], h.round());
        }
    };
    // The first spot's paths, for the readers of one path (the original's keys): the arrival ends at its way out (the
    // hub), its last leg toward the spot.
    path(&mut s, "ToTaxiPt", "TaxiWayPtsTo", &rt.to, bearing(rt.hub, b.parking[0].at));
    path(&mut s, "FromTaxiPt", "TaxiWayPtsFrom", &rt.from, r.heading(k));
    s += &format!("HangarsNum={}\n", b.parking.len());
    for (i, p) in b.parking.iter().enumerate() {
        // The spot's way out: where it meets its lane; the departure leaves it along its first leg.
        let way = rt.out[i][0];
        let to_spot = bearing(way, p.at);
        let from_spot = rt.out[i].get(1).map_or(to_spot, |f| bearing(way, *f));
        s += &format!(
            "ToHangarTurnPtX{i}={:.1}\nToHangarTurnPtY{i}={:.1}\nToHangarTurnPtHdg{i}={:.0}\n",
            way[0],
            way[1],
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
            way[0],
            way[1],
            from_spot.round()
        );
        // Ours: the spot's own departure and arrival along the taxiways (data-formats.md §12).
        path(&mut s, &format!("FromHangar{i}Pt"), &format!("HangarPtsFrom{i}"), &rt.out[i], r.heading(k));
        path(&mut s, &format!("ToHangar{i}Pt"), &format!("HangarPtsTo{i}"), &rt.back[i], to_spot);
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
        Heights::open(&theatre).with_context(|| format!("{}: no theatre (iaf-sim terrain)", theatre.display()))?;
    let own = assets.join("converted/own");
    std::fs::create_dir_all(theatre.join("airbases"))?;
    std::fs::create_dir_all(&own)?;
    let r1 = |v: f64| (v * 10.0).round() / 10.0;
    let pt = |p: [f64; 2]| json!([r1(p[0]), r1(p[1])]);
    let mut list = Vec::new();
    let mut ibx = String::from(
        "; Modern IAF's airbases (iaf-sim airbases; modern-iaf/docs/data-formats.md §12). World metres: UTM 36N.\n\n",
    );
    let mut paved = Vec::new();
    for b in &bases {
        check(cancel)?;
        let rt = routes(b)?;
        let mut z = |p: [f64; 2]| ground.ground_height(p[0], p[1]).unwrap_or(b.elevation);
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
            "furniture": b.furniture.iter().map(|f| {
                let mut o = json!({"kind": f.kind, "at": pt(f.at), "heading": (f.heading * 10.0).round() / 10.0});
                if let Some(s) = f.size {
                    o["size"] = json!(s);
                }
                if !f.line.is_empty() {
                    o["line"] = f.line.iter().map(|p| pt(*p)).collect();
                }
                o
            }).collect::<Vec<_>>(),
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
            let h = ground.ground_height(e0 + (i as f64 + 0.5) * WATER_CELL_M, n1 - (j as f64 + 0.5) * WATER_CELL_M);
            zero[j * nx + i] = h.is_some_and(|h| h.abs() < 0.05);
        }
    }
    drop(ground);
    let sea = sea_cells(nx, ny, &zero);
    drop(zero);
    let mut cells: Vec<u8> = sea.iter().map(|&s| if s { SEA as u8 } else { 0 }).collect();
    drop(sea);
    // The OpenStreetMap extracts (downloaded when missing): the coastline decides the sea near it (the DEM's 0 m cells
    // farther out), as it cuts the Survey photo (modern-iaf/docs/terrain.md §12).
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
    // The polygons themselves for the scenery (a tree tests them, not the 64 m grid: modern-iaf/docs/scenery.md §4).
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
    // The large lakes' surface as the DEM has it (modern-iaf/docs/terrain.md "Inland water").
    if let Some(mut g) = Heights::open(&theatre) {
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

impl Water {
    /// The median ground height (m) over a 500 m grid inside the outer ring; None without a sample.
    fn dem_level(&self, g: &mut Heights) -> Option<f64> {
        let o = &self.rings[0];
        let b = crate::bbox(o.iter());
        let mut v = Vec::new();
        let mut y = b[1] + 250.0;
        while y < b[3] {
            let mut x = b[0] + 250.0;
            while x < b[2] {
                let inside = self.rings.iter().filter(|r| crate::scenery::contains(r, [x, y])).count() % 2 == 1;
                if let Some(h) = g.ground_height(x, y).filter(|_| inside) {
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
            let area = ring_area(rings.first()?).abs() - rings[1..].iter().map(|r| ring_area(r).abs()).sum::<f64>();
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
            let b = crate::bbox(&rings[0]);
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
        let filter = "natural = 'water' OR landuse IN ('reservoir','salt_pond')";
        let select = "osm_id,osm_way_id,name,other_tags";
        crate::scenery::run(crate::scenery::ogr_cut(pbf, "multipolygons", filter, select, geo, &out))?;
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
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data/airbases")
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
        // The theatre's far corners (modern-iaf/docs/terrain.md §2) round-trip too.
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
                // Every spot reaches the lineup on pavement along its own departure.
                let path = rt.departure_from(&b, p.at);
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
                let off = b.runways.iter().map(|r| r.dist(s.at) - r.width / 2.0).fold(f64::INFINITY, f64::min);
                assert!(off >= SIGN_RUNWAY_M, "{} sign {:?}: {off:.0} m from a runway's edge", b.icao, s.panels);
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
                passed.iter().any(|s| s.panels.iter().any(|p| p.style == "mandatory")),
                "Ramon: no holding sign for 25R: {passed:?}"
            );
            assert!(
                passed.iter().any(|s| s.panels.iter().any(|p| p.style == "direction")),
                "Ramon: no direction sign to 25R: {passed:?}"
            );
        }
    }

    /// The aprons' outlines are soft as the runways' (2026-11-13: saw-toothed against the sand at Ramon and Nevatim):
    /// at every base a third or more of the pixels on a slanted apron edge hold a partial coverage (a hard 0 or 255 before), and the coverage follows the signed
    /// distance (0.5 on the outline).
    #[test]
    fn apron_edges_are_smooth() {
        for b in load(&data()).unwrap() {
            let m = mask(&b);
            let (mut on, mut soft) = (0, 0);
            for p in &b.aprons {
                for k in 0..p.len() {
                    let (a, c) = (p[k], p[(k + 1) % p.len()]);
                    let (dx, dy) = ((c[0] - a[0]).abs(), (c[1] - a[1]).abs());
                    if dx.min(dy) < 0.2 * dx.max(dy) || dist(a, c) < 20.0 {
                        continue; // only slanted edges stair-step
                    }
                    for t in 1..20 {
                        let q = [a[0] + (c[0] - a[0]) * t as f64 / 20.0, a[1] + (c[1] - a[1]) * t as f64 / 20.0];
                        let (x, y) = ((q[0] - m.origin[0]) / MASK_PX_M, (m.origin[1] - q[1]) / MASK_PX_M);
                        let v = m.img.get_pixel(x as u32, y as u32)[0];
                        on += 1;
                        soft += usize::from((10..=245).contains(&v));
                    }
                }
            }
            assert!(on == 0 || soft * 3 >= on, "{}: {soft} of {on} apron-edge pixels soft", b.icao);
        }
    }

    /// No two signs crowd each other: each pair stands SIGN_APART_M apart; no sign hides a holding sign, and no holding
    /// sign hides another sign (2026-11-13: a holding sign 5–10 m before a direction sign hid it at Ramon 25L and
    /// Nevatim 26L). Direction signs where junctions crowd may stand in each other's line of sight (`place`). Where a
    /// holding position and a junction meet, one array holds both, the mandatory board inboard (last).
    #[test]
    fn signs_stand_apart() {
        for b in load(&data()).unwrap() {
            let all = signs(&b);
            for (i, s) in all.iter().enumerate() {
                for o in &all[i + 1..] {
                    let at = dist(s.at, o.at);
                    assert!(at >= SIGN_APART_M, "{}: {:?} and {:?} {at:.0} m apart", b.icao, s.panels, o.panels);
                    let hold = |x: &Sign| x.panels.iter().any(|p| p.style == "mandatory");
                    assert!(
                        !((hold(o) || hold(s)) && (s.hides(o) || o.hides(s))),
                        "{}: {:?} hides {:?}",
                        b.icao,
                        s.panels,
                        o.panels
                    );
                }
                let m = s.panels.iter().position(|p| p.style == "mandatory");
                assert!(
                    m.is_none_or(|m| s.panels[m..].iter().all(|p| p.style == "mandatory")),
                    "{}: {:?}",
                    b.icao,
                    s.panels
                );
            }
        }
    }

    /// Each sign names only where it leads: a holding board one end of the runway it stands at (that end's start
    /// there, else the end nearer the join: the take-off from that point), never two ("25L-07R" until 2026-11-17); a
    /// direction sign names each end once, and one leads to the base's take-off end.
    #[test]
    fn signs_name_the_runway_ends_near_them() {
        for b in load(&data()).unwrap() {
            let mut named = std::collections::BTreeSet::new();
            for s in signs(&b) {
                let texts: Vec<String> =
                    s.panels.iter().filter(|p| p.style == "direction").map(|p| p.text.clone()).collect();
                let mut u = texts.clone();
                u.sort();
                u.dedup();
                assert_eq!(u.len(), texts.len(), "{} sign {:?}: an end named twice", b.icao, s.at);
                named.extend(texts);
                for p in s.panels.iter().filter(|p| p.style == "mandatory") {
                    let (ri, k) = b.end(&p.text).unwrap_or_else(|| panic!("{} {:?}: no runway end", b.icao, p.text));
                    let r = &b.runways[ri];
                    let off = r.dist(s.road);
                    assert!((off - HOLD_M).abs() < 1.0, "{} {:?} {:?}: {off} m from its runway", b.icao, p.text, s.at);
                    let nearer = if dist(s.road, r.ends[0]) < dist(s.road, r.ends[1]) { 0 } else { 1 };
                    assert_eq!(r.entry_end(s.road).unwrap_or(nearer), k, "{} {:?} at {:?}", b.icao, p.text, s.road);
                }
            }
            let main = main_ends()[b.section.as_str()];
            assert!(named.contains(main), "{}: no direction sign to {main} ({named:?})", b.icao);
        }
    }

    /// A join counts as a runway's start up to END_ENTRY_M past the declared start (or before it), from either end;
    /// a join partway along is an intersection.
    #[test]
    fn entry_end_is_the_start_only() {
        let r = Runway {
            designators: ["09".into(), "27".into()],
            ends: [[0.0, 0.0], [3000.0, 0.0]],
            width: 45.0,
            starts: [300.0, 0.0],
        };
        assert_eq!(r.entry_end([-50.0, 0.0]), Some(0));
        assert_eq!(r.entry_end([650.0, 30.0]), Some(0));
        assert_eq!(r.entry_end([750.0, 0.0]), None);
        assert_eq!(r.entry_end([1500.0, 0.0]), None);
        assert_eq!(r.entry_end([2650.0, 0.0]), Some(1));
    }

    /// A jet that leaves parking spot `from` and follows the signs for runway end `end`: at each junction where it has
    /// a choice (two or more ways on that lead to a runway, `leads_on`), the direction sign facing it before the
    /// junction (or across it) must name `end`, and its arrow must match one way alone; elsewhere it rolls on (across
    /// a runway, straight). The points it taxis, to that end's start, where a holding sign naming `end` alone must
    /// face it; Err says where it gets stuck.
    fn follow(b: &Base, all: &[Sign], from: [f64; 2], end: &str) -> Result<Vec<[f64; 2]>, String> {
        let lines = taxi_lines(b);
        let routed = Graph::new(&lines, &b.runways);
        let on_runway = |p: [f64; 2]| b.runways.iter().position(|r| r.dist(p) <= r.width / 2.0 + 5.0);
        let (ri, k) = b.end(end).ok_or("no such end")?;
        let entry = takeoff(b, &routed, ri, k).ok_or("no taxiway joins it")?;
        let tree = routed.toward(entry);
        let (mut cur, mut prev) = (routed.nearest(from).unwrap(), usize::MAX);
        if tree[cur] == usize::MAX {
            return Err("no taxiway joins it to the spot".into());
        }
        let mut path = vec![routed.pts[cur]];
        // Where the jet passed its last junction (the signs it reads stand after it).
        let mut since = 0;
        for _ in 0..20_000 {
            if cur == entry {
                // The holding sign for `end`, facing the jet on its last taxiway leg.
                let held = all.iter().any(|s| {
                    let f = s.facing.to_radians();
                    let d = [-f.sin(), -f.cos()];
                    s.panels.iter().any(|p| p.style == "mandatory" && p.text == end)
                        && path.windows(2).rev().take(40).any(|t| {
                            seg_dist(s.road, t[0], t[1]) < JOIN_M && {
                                let u = unit(t[0], t[1]);
                                u[0] * d[0] + u[1] * d[1] > 0.7
                            }
                        })
                });
                return if held { Ok(path) } else { Err(format!("no holding sign {end} before its start")) };
            }
            let mut nexts: Vec<usize> = routed.adj[cur].iter().map(|a| a.0).filter(|&n| n != prev).collect();
            nexts.sort();
            nexts.dedup();
            let here = routed.pts[cur];
            let next = if prev == usize::MAX {
                *nexts.first().ok_or("a spot without a way out")?
            } else {
                let mut branches: Vec<usize> = routed.adj[cur].iter().map(|a| a.0).collect();
                branches.sort();
                branches.dedup();
                let runway = on_runway(here).is_some();
                let live: Vec<usize> =
                    nexts.iter().copied().filter(|&n| runway || leads_on(&routed, cur, n, &on_runway)).collect();
                // The boards for `end` a jet here reads: facing it (within 45°), on its way since the last junction.
                let d = unit(routed.pts[prev], here);
                let last = path[since];
                let read: Vec<(f64, [f64; 2])> = all
                    .iter()
                    .filter(|s| {
                        let f = s.facing.to_radians();
                        let sd = [-f.sin(), -f.cos()];
                        sd[0] * d[0] + sd[1] * d[1] > 0.7
                            && dist(s.road, last) > 1.0
                            && path[since..].windows(2).any(|t| seg_dist(s.road, t[0], t[1]) < 1.0)
                    })
                    .flat_map(|s| {
                        let f = s.facing.to_radians();
                        s.panels
                            .iter()
                            .filter(|p| p.style == "direction" && p.text == end)
                            .map(move |p| (p.arrow.unwrap_or(0.0), [-f.sin(), -f.cos()]))
                    })
                    .collect();
                if runway && read.is_empty() {
                    // Across the runway: straight on.
                    straightest(&routed, prev, cur).ok_or("stuck on a runway")?
                } else if branches.len() < 3 || live.len() < 2 {
                    *live.first().or(nexts.first()).ok_or_else(|| format!("a dead end at {here:?}"))?
                } else {
                    // Each board's way: the one nearest its arrow, clearly (10°) nearer than the next; boards read
                    // here must agree.
                    let pick = |a: f64, sd: [f64; 2]| -> Option<usize> {
                        let mut by: Vec<(f64, usize)> =
                            live.iter().map(|&n| ((turn(sd, unit(here, routed.pts[n])) - a).abs(), n)).collect();
                        by.sort_by(|x, y| x.0.total_cmp(&y.0));
                        (by.len() < 2 || by[1].0 - by[0].0 >= 10.0).then_some(by[0].1)
                    };
                    let picks: Vec<Option<usize>> = read.iter().map(|&(a, sd)| pick(a, sd)).collect();
                    if !read.is_empty() && picks.iter().all(|p| p.is_some() && *p == picks[0]) {
                        picks[0].unwrap()
                    } else {
                        return Err(format!(
                            "{} boards for {end} at {here:?} arriving {:.0}° disagree or fit two ways",
                            read.len(),
                            grid_deg(d)
                        ));
                    }
                }
            };
            if next != tree[cur] {
                return Err(format!("left the shortest taxi at {here:?}"));
            }
            if routed.adj[cur].len() >= 3 {
                since = path.len() - 1;
            }
            (prev, cur) = (cur, next);
            path.push(routed.pts[cur]);
        }
        Err("a loop".into())
    }

    /// The user's rule (2026-11-17, "where do I go with my fucking plane where it say 25R"): from every parking spot
    /// of every base, a jet that follows only the signs for a runway end reaches that end's start, a sign at every
    /// junction where it has a choice; from the first spot it taxis the departure the briefing draws. The ends no
    /// taxiway joins at their start are listed (no board names them).
    #[test]
    fn following_the_signs_reaches_every_runway_start() {
        let (mut no_start, mut stuck) = (Vec::new(), Vec::new());
        for b in load(&data()).unwrap() {
            let all = signs(&b);
            let g = Graph::new(&taxi_lines(&b), &b.runways);
            for (ri, r) in b.runways.iter().enumerate() {
                for (k, end) in r.designators.iter().enumerate() {
                    for (i, spot) in b.parking.iter().enumerate() {
                        match follow(&b, &all, spot.at, end) {
                            Ok(path) if i == 0 => {
                                let dep = departure(&b, &g, ri, k).expect("a departure");
                                assert_eq!(&path[..], &dep[..dep.len() - 1], "{} {end}: not the departure", b.icao);
                            }
                            Ok(_) => {}
                            Err(e) if e.starts_with("no taxiway joins") => {
                                if i == 0 {
                                    no_start.push(format!("{} {end}", b.icao));
                                }
                                let named = |p: &Panel| &p.text == end && p.style == "direction";
                                let named = all.iter().any(|s| s.panels.iter().any(named));
                                assert!(!named, "{} {end}: a direction board names an end no taxiway joins", b.icao);
                            }
                            Err(e) => stuck.push(format!("{} spot {i} ({}) to {end}: {e}", b.icao, spot.unit)),
                        }
                    }
                }
            }
        }
        // OpenStreetMap joins none of the base's taxiways to Hatzerim's 10/28 (airbases.md §9).
        assert_eq!(no_start, ["LLHB 10", "LLHB 28"]);
        assert!(stuck.is_empty(), "{} stuck:\n{}", stuck.len(), stuck.join("\n"));
    }

    /// Prints each base's signs as JSON lines (lat, lon, facing, panels) for the overview pictures, and the poses for
    /// cockpit pictures along its departure:
    /// `cargo test -p iaf-tools --lib sim_bases::tests::dump_signs -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn dump_signs() {
        for b in load(&data()).unwrap() {
            for s in signs(&b) {
                let g = utm36n_geo(s.at[0], s.at[1]);
                let f = s.facing - grid_heading(g[0], g[1], 0.0);
                let panels: Vec<Value> =
                    s.panels.iter().map(|p| json!({"style": p.style, "text": p.text, "arrow": p.arrow})).collect();
                println!("SIGN {}", json!({"icao": b.icao, "lat": g[1], "lon": g[0], "facing": f, "panels": panels}));
            }
            // The cockpit pictures' poses (x, y, grid heading): the first spot, then 60 m before each sign the taxi from
            // it to the take-off end passes (nearer where the way to the sign is shorter).
            let (all, spot) = (signs(&b), &b.parking[0]);
            println!("POSE {} {:.1},{:.1},{:.0} spot", b.icao, spot.at[0], spot.at[1], spot.heading);
            let path = follow(&b, &all, spot.at, main_ends()[b.section.as_str()]).unwrap();
            for t in path.windows(2) {
                let u = unit(t[0], t[1]);
                for s in all.iter().filter(|s| seg_dist(s.road, t[0], t[1]) < JOIN_M) {
                    let f = s.facing.to_radians();
                    if -f.sin() * u[0] - f.cos() * u[1] > 0.7 {
                        let m = (s.read - 2.0).clamp(10.0, 60.0);
                        let texts: Vec<&String> = s.panels.iter().map(|p| &p.text).collect();
                        let (x, y) = (s.road[0] - u[0] * m, s.road[1] - u[1] * m);
                        println!("POSE {} {x:.1},{y:.1},{:.0} {texts:?}", b.icao, grid_deg(u));
                    }
                }
            }
        }
    }

    /// Prints each shelter of each base as a start spot for its unit (parking.json `shelter`, airbases.md §5): its
    /// way out (the angle off its nose, the distance), its taxi to the lineup (m), the metres of it off the pavement and
    /// the least room to spare between it and anything else standing (m, `room_needed` taken off): `cargo test -p iaf-tools --lib sim_bases::tests::dump_shelter_starts -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn dump_shelter_starts() {
        for b in load(&data()).unwrap() {
            for f in b.furniture.iter().filter(|f| f.kind == "shelter") {
                let mut t = b.clone();
                t.parking = vec![Spot { unit: String::new(), at: f.at, heading: f.heading }];
                let g = utm36n_geo(f.at[0], f.at[1]);
                let Ok(rt) = routes(&t) else {
                    println!("SHELTER {} {:.7},{:.7} no route", b.icao, g[1], g[0]);
                    continue;
                };
                let way = rt.out[0][0];
                let off = (bearing(f.at, way) - f.heading + 540.0).rem_euclid(360.0) - 180.0;
                let path = rt.departure_from(&t, f.at);
                let len: f64 = path.windows(2).map(|w| dist(w[0], w[1])).sum();
                let mut rough = 0;
                for w in path.windows(2) {
                    for k in 0..dist(w[0], w[1]) as usize {
                        let u = k as f64 / dist(w[0], w[1]);
                        let p = [w[0][0] + (w[1][0] - w[0][0]) * u, w[0][1] + (w[1][1] - w[0][1]) * u];
                        rough += usize::from(!b.paved(p, PAVEMENT_MARGIN_M));
                    }
                }
                // The least room to spare between the taxi and anything else standing (the_furniture_stands_clear's
                // room_needed); below 0 the shelter cannot be a start spot.
                let spare = b
                    .furniture
                    .iter()
                    .filter(|o| o.line.is_empty() && dist(o.at, f.at) >= SPOT_CLEAR_M)
                    .map(|o| room(o, &path) - room_needed(o))
                    .fold(f64::MAX, f64::min);
                println!(
                    "SHELTER {} {:.7},{:.7} off {off:.0} way {:.0} m taxi {len:.0} m unpaved {rough} m room {spare:.0} m",
                    b.icao,
                    g[1],
                    g[0],
                    dist(f.at, way)
                );
            }
        }
    }

    /// One designator per runway end for the paint, the signs, the tower and the missions: the tower's iaf.ibx
    /// RunwayDesignator is the base's take-off end, and every mission's "runway" is an end of its own base (Nevatim's
    /// tower said "25" for the runway painted and signed "26L", 2026-11-13).
    #[test]
    fn one_designator_per_runway_end() {
        let bases = load(&data()).unwrap();
        for b in &bases {
            let rt = routes(b).unwrap();
            let s = ibx_section(b, &rt, &mut |_| b.elevation);
            let (ri, k) = b.main;
            let r = &b.runways[ri];
            assert!(s.contains(&format!("RunwayDesignator={}\n", r.designators[k])), "{}", b.icao);
            assert!(s.contains(&format!("RunwayDesignatorOpposite={}\n", r.designators[1 - k])), "{}", b.icao);
            assert_eq!(r.designators[k], main_ends()[b.section.as_str()], "{}", b.icao);
        }
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../modern-iaf/data/missions");
        for f in std::fs::read_dir(dir).unwrap() {
            let p = f.unwrap().path();
            let v: Value = serde_json::from_str(&std::fs::read_to_string(&p).unwrap()).unwrap();
            let Some(rwy) = v["runway"].as_str() else { continue };
            let base = v["start"]["base"].as_str().unwrap_or("");
            let b = bases.iter().find(|b| b.name_en.trim_end_matches(" Airbase") == base);
            let b = b.unwrap_or_else(|| panic!("{p:?}: no base {base}"));
            assert!(b.end(rwy).is_some(), "{p:?}: {base} has no runway end {rwy}");
        }
    }

    /// Every parking spot stands on an apron or a shelter's pad of its base.
    #[test]
    fn parking_spots_are_on_aprons() {
        for b in load(&data()).unwrap() {
            for p in &b.parking {
                let on = b.aprons.iter().chain(&b.shelters).any(|a| {
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
            // Each spot has its own departure, which ends at the lineup; the jet leaves its way out along the
            // departure's first taxiway leg (not north: a heading of 0). The first spot's is the shared one.
            assert_eq!(a.from_hangar_path.len(), b.parking.len());
            assert_eq!(a.from_hangar_path[0], a.from_taxi, "{}", b.icao);
            assert_eq!(a.to_hangar_path[0], a.to_taxi, "{}", b.icao);
            for (h, t) in a.from_hangar_turn.iter().enumerate() {
                let own = &a.from_hangar_path[h];
                assert_eq!(t.hdg, own[0].hdg, "{}: the turn point's heading", b.icao);
                assert!(t.hdg != 0.0, "{}", b.icao);
                let end = own.last().unwrap();
                assert!((f64::from(end.x) - l[0]).abs() < 0.1 && (f64::from(end.y) - l[1]).abs() < 0.1, "{}", b.icao);
                let back = a.arrival(Some(h));
                assert_eq!(back.last(), Some(&a.hangars[h]), "{}: the arrival ends at the spot", b.icao);
                assert_eq!((back[back.len() - 2].x, back[back.len() - 2].y), (t.x, t.y), "{}", b.icao);
            }
        }
    }

    /// The departure taxi (each parking spot → its way out → its taxi path → the lineup) runs on the pavement (`paved`
    /// with the training missions' margin): every metre of it, at every base.
    #[test]
    fn the_departure_is_paved() {
        for b in load(&data()).unwrap() {
            let rt = routes(&b).unwrap();
            for spot in &b.parking {
                let path = rt.departure_from(&b, spot.at);
                for w in path.windows(2) {
                    let n = dist(w[0], w[1]).ceil() as usize;
                    for i in 0..=n {
                        let f = i as f64 / n.max(1) as f64;
                        let p = [w[0][0] + (w[1][0] - w[0][0]) * f, w[0][1] + (w[1][1] - w[0][1]) * f];
                        assert!(
                            b.paved(p, PAVEMENT_MARGIN_M),
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

    /// The room between a taxi `path` and furniture `f` (m): to its footprint where it has a size, else to its place.
    fn room(f: &Item, path: &[[f64; 2]]) -> f64 {
        let Some([l, w]) = f.size else {
            return path.windows(2).map(|q| seg_dist(f.at, q[0], q[1])).fold(f64::MAX, f64::min);
        };
        let d = [f.heading.to_radians().sin(), f.heading.to_radians().cos()];
        let n = [d[1], -d[0]];
        let at = |a: f64, c: f64| [f.at[0] + d[0] * a + n[0] * c, f.at[1] + d[1] * a + n[1] * c];
        let box_ = [at(-l / 2.0, -w / 2.0), at(l / 2.0, -w / 2.0), at(l / 2.0, w / 2.0), at(-l / 2.0, w / 2.0)];
        let mut best = f64::MAX;
        for q in path.windows(2) {
            for k in 0..4 {
                let (a, b) = (box_[k], box_[(k + 1) % 4]);
                let gap = if cross_at(q[0], q[1], a, b).is_some() {
                    0.0
                } else {
                    [seg_dist(a, q[0], q[1]), seg_dist(b, q[0], q[1]), seg_dist(q[0], a, b), seg_dist(q[1], a, b)]
                        .into_iter()
                        .fold(f64::MAX, f64::min)
                };
                best = best.min(gap);
            }
        }
        best
    }

    /// The least room between a taxi and a building's footprint (m; inferred: an F-15's 6.5 m half span and Annex 14's
    /// 7.5 m stand clearance), between a taxi and a parked jet or vehicle's middle (m; inferred: a span and margin), and
    /// between a taxi and a ramp prop (m).
    const ROOM_FOOTPRINT_M: f64 = 14.0;
    const ROOM_POINT_M: f64 = 25.0;
    const ROOM_PROP_M: f64 = 5.0;

    fn room_needed(f: &Item) -> f64 {
        if ["gpu", "fuel_truck", "extinguisher"].contains(&f.kind.as_str()) {
            ROOM_PROP_M
        } else if f.size.is_some() {
            ROOM_FOOTPRINT_M
        } else {
            ROOM_POINT_M
        }
    }

    /// Every base's furniture (base-furniture.md §4) loads into the frame, stands clear of the runways (a footprint's
    /// corner over 40 m from a runway's edge, Annex 14's strip for a building, inferred) and of the departure from each
    /// parking spot (`room_needed`: until 2026-11-19 25 m from a circle round the footprint, which barred the taxi past a
    /// row of shelters' doors), and its shelters' pads are paved.
    #[test]
    fn the_furniture_stands_clear() {
        let bases = load(&data()).unwrap();
        for (icao, shelters) in [("LLRM", 40), ("LLHB", 12), ("LLNV", 10), ("LLRD", 50), ("LLEK", 10)] {
            let b = bases.iter().find(|b| b.icao == icao).unwrap();
            assert!(b.furniture.iter().filter(|f| f.kind == "shelter").count() >= shelters, "{icao}'s shelters");
            let rt = routes(b).unwrap();
            for f in b.furniture.iter().filter(|f| f.line.is_empty()) {
                let [l, w] = f.size.unwrap_or([0.0, 0.0]);
                let r = (l * l + w * w).sqrt() / 2.0;
                assert!(b.runway_dist(f.at) - r > 40.0, "{icao}: {} at {:?} is on a runway's strip", f.kind, f.at);
                if f.kind == "shelter" {
                    assert!(b.paved(f.at, 0.0), "{icao}: the shelter at {:?} has no pad", f.at);
                }
                // The spot's own shelter stands round its jet.
                for s in b.parking.iter().filter(|s| dist(s.at, f.at) >= SPOT_CLEAR_M) {
                    let near = room(f, &rt.departure_from(b, s.at));
                    assert!(
                        near > room_needed(f),
                        "{icao}: {} at {:?} is {near:.0} m from the departure",
                        f.kind,
                        f.at
                    );
                }
            }
        }
    }

    /// A spot in a shelter (parking.json `shelter`, airbases.md §5) stands at the shelter's middle, nose to its door, the
    /// shelter's parked jet gone; the jet leaves straight out of the door to its way out on the taxiway (within 10° of
    /// the nose, 15–60 m ahead: the door's apron, inferred). Every base with shelters starts its jets in them.
    #[test]
    fn a_shelter_start_leaves_by_its_door() {
        let bases = load(&data()).unwrap();
        let mut n = 0;
        for b in &bases {
            let rt = routes(b).unwrap();
            for (i, s) in b.parking.iter().enumerate() {
                let Some(f) = b.furniture.iter().find(|f| f.kind == "shelter" && dist(f.at, s.at) < 0.5) else {
                    continue;
                };
                n += 1;
                assert!((s.heading - f.heading).abs() < 0.5, "{} spot {i}: not nose to the door", b.icao);
                let near = b.furniture.iter().filter(|g| g.kind != "shelter" && dist(g.at, s.at) < SPOT_CLEAR_M);
                assert_eq!(near.count(), 0, "{} spot {i}: a parked jet in its shelter", b.icao);
                let way = rt.out[i][0];
                let off = (bearing(s.at, way) - s.heading + 540.0).rem_euclid(360.0) - 180.0;
                assert!(off.abs() < 10.0, "{} spot {i}: the way out {off:.0}° off the nose", b.icao);
                assert!(
                    (15.0..60.0).contains(&dist(s.at, way)),
                    "{} spot {i}: way out {:.0} m",
                    b.icao,
                    dist(s.at, way)
                );
            }
        }
        // The user's rule (2026-11-17): every spot of a base with shelters is in one, but Hatzerim's (open,
        // airbases.md §5: the taxis from its shelters break the signs' rules).
        let want: usize = bases
            .iter()
            .filter(|b| b.icao != "LLHB" && b.furniture.iter().any(|f| f.kind == "shelter"))
            .map(|b| b.parking.len())
            .sum();
        assert_eq!(n, want, "a base with shelters has a spot outside them");
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
