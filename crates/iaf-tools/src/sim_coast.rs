//! Modern IAF's OpenStreetMap sources (iaf-2026/docs/terrain.md §12): the extracts over the theatre (the Israel and
//! Palestine one and the neighbours' that meet it), fetched into the shared cache when missing, and the coastline cut
//! from them, the one boundary of the sea for the colour (`sim_terrain`) and the surface flags (`sim_bases`).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use anyhow::{Context, Result};
use serde_json::Value;

use crate::progress::Progress;
use crate::sim_bases::utm36n;
use crate::thirdparty::{self, Download};

/// The Israel and Palestine OpenStreetMap extract (`thirdparty::SCENERY`, in `assets/source/scenery`).
pub fn osm_extract() -> Download {
    *thirdparty::SCENERY.iter().find(|d| d.file.starts_with("israel-and-palestine")).expect("SCENERY lists it")
}

/// The OpenStreetMap extracts the inland water is cut from, with their folder under `assets`: Israel and Palestine's
/// and the other countries' road extracts whose country meets the box `geo` (lon / lat). The same files the sim's
/// road layer reads (`iaf-sim scenery`), in the same shared cache.
pub fn water_extracts(geo: [f64; 4]) -> Vec<(Download, &'static str)> {
    std::iter::once((osm_extract(), "source/scenery"))
        .chain(road_downloads(geo).into_iter().map(|d| (d, "source/roads")))
        .collect()
}

/// The other countries' road extracts (`thirdparty::ROADS`) whose country meets the box `geo` (lon / lat).
pub fn road_downloads(geo: [f64; 4]) -> Vec<Download> {
    thirdparty::ROADS
        .iter()
        .filter(|d| {
            let b = country_geo(d.file);
            b[0] < geo[2] && geo[0] < b[2] && b[1] < geo[3] && geo[1] < b[3]
        })
        .copied()
        .collect()
}

/// A road extract's country box [lon0, lat0, lon1, lat1], a little wider than the country (inferred from its
/// borders); the whole world for one not listed (always used).
fn country_geo(file: &str) -> [f64; 4] {
    match file.split('-').next().unwrap_or("") {
        "lebanon" => [35.0, 33.0, 36.7, 34.8],
        "syria" => [35.5, 32.2, 42.5, 37.4],
        "jordan" => [34.8, 29.1, 39.4, 33.5],
        "egypt" => [24.6, 21.7, 37.1, 31.8],
        "cyprus" => [32.2, 34.5, 34.7, 35.8],
        _ => [-180.0, -90.0, 180.0, 90.0],
    }
}

/// The extracts of `water_extracts(geo)` under `assets`, each downloaded when it is not there (one that fails is an
/// error); their paths.
pub fn fetch_extracts(assets: &Path, geo: [f64; 4], pr: &dyn Progress, cancel: &AtomicBool) -> Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    for (d, dir) in water_extracts(geo) {
        let dir = assets.join(dir);
        if !thirdparty::file_done(&dir, &d) {
            thirdparty::fetch_files(std::slice::from_ref(&d), &dir, pr, cancel)
                .with_context(|| format!("the OpenStreetMap extract {} ({})", d.file, d.url))?;
        }
        out.push(dir.join(d.file));
    }
    Ok(out)
}

/// The extracts' pinned hashes, one line each: what a coastline or water cut is made from.
pub fn extracts_stamp(geo: [f64; 4]) -> Vec<String> {
    water_extracts(geo).iter().map(|(d, _)| format!("{} {}", d.file, d.sha256)).collect()
}

/// How far from the coastline (m) `Coast::sea` answers; farther the DEM's sea (its 0 m cells) decides.
pub const COAST_REACH_M: f64 = 300.0;
/// The coastline index's cell (m).
const COAST_CELL_M: f64 = 500.0;

/// OpenStreetMap's coastline (`natural=coastline`) in UTM 36N: segments with the land on their left and the water on
/// their right (the OSM rule), indexed by COAST_CELL_M cells.
#[derive(Default)]
pub struct Coast {
    segs: Vec<[[f64; 2]; 2]>,
    cells: HashMap<(i64, i64), Vec<u32>>,
}

impl Coast {
    /// From coastline ways (each a list of UTM points), a segment in two extracts kept once.
    pub fn new(ways: &[Vec<[f64; 2]>]) -> Self {
        let mut c = Coast::default();
        let mut seen = std::collections::HashSet::new();
        for w in ways {
            for s in w.windows(2) {
                if !seen.insert([s[0], s[1]].map(|p| p.map(f64::to_bits))) {
                    continue;
                }
                let i = c.segs.len() as u32;
                c.segs.push([s[0], s[1]]);
                let r = COAST_REACH_M;
                let cell = |v: f64| (v / COAST_CELL_M).floor() as i64;
                for x in cell(s[0][0].min(s[1][0]) - r)..=cell(s[0][0].max(s[1][0]) + r) {
                    for y in cell(s[0][1].min(s[1][1]) - r)..=cell(s[0][1].max(s[1][1]) + r) {
                        c.cells.entry((x, y)).or_default().push(i);
                    }
                }
            }
        }
        c
    }

    /// The coastline over the box `geo` (lon / lat) from the extracts (ogr2ogr's `lines`, into `work`).
    pub fn load(pbfs: &[PathBuf], geo: [f64; 4], work: &Path) -> Result<Self> {
        std::fs::create_dir_all(work)?;
        let out = work.join("coast.geojsonl");
        let mut ways = Vec::new();
        for pbf in pbfs {
            let _ = std::fs::remove_file(&out);
            let mut cmd = std::process::Command::new("ogr2ogr");
            cmd.args(["-f", "GeoJSONSeq", "-where", "other_tags LIKE '%\"natural\"=>\"coastline\"%'"])
                .args(["-select", "osm_id", "-spat"])
                .args(geo.map(|v| v.to_string()))
                .arg(&out)
                .arg(pbf)
                .arg("lines");
            let o = cmd.output().context("ogr2ogr (GDAL) not found")?;
            anyhow::ensure!(o.status.success(), "ogr2ogr: {}", String::from_utf8_lossy(&o.stderr));
            let text = std::fs::read_to_string(&out).unwrap_or_default();
            for v in text.lines().filter_map(|l| serde_json::from_str::<Value>(l).ok()) {
                let g = &v["geometry"];
                let lines: Vec<&Value> = match g["type"].as_str() {
                    Some("LineString") => vec![&g["coordinates"]],
                    Some("MultiLineString") => g["coordinates"].as_array().into_iter().flatten().collect(),
                    _ => continue,
                };
                for l in lines {
                    let pts: Vec<[f64; 2]> = l
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(|p| Some(utm36n(p[0].as_f64()?, p[1].as_f64()?)))
                        .collect();
                    if pts.len() >= 2 {
                        ways.push(pts);
                    }
                }
            }
        }
        let _ = std::fs::remove_file(&out);
        Ok(Coast::new(&ways))
    }

    pub fn segments(&self) -> &[[[f64; 2]; 2]] {
        &self.segs
    }

    pub fn is_empty(&self) -> bool {
        self.segs.is_empty()
    }

    /// True when a coastline segment comes within COAST_REACH_M of the rect `r` (W, S, E, N).
    pub fn touches(&self, r: [f64; 4]) -> bool {
        let cell = |v: f64| (v / COAST_CELL_M).floor() as i64;
        (cell(r[0])..=cell(r[2])).any(|x| (cell(r[1])..=cell(r[3])).any(|y| self.cells.contains_key(&(x, y))))
    }

    /// True when a coastline segment lies within `r` (≤ COAST_REACH_M) of `p`.
    pub fn near(&self, p: [f64; 2], r: f64) -> bool {
        self.nearest(p).is_some_and(|(d, _)| d <= r)
    }

    fn nearest(&self, p: [f64; 2]) -> Option<(f64, usize)> {
        let key = ((p[0] / COAST_CELL_M).floor() as i64, (p[1] / COAST_CELL_M).floor() as i64);
        let mut best: Option<(f64, usize)> = None;
        for &i in self.cells.get(&key)? {
            let s = self.segs[i as usize];
            let d = seg_dist(p, s[0], s[1]);
            // At a shared vertex both segments are as near: the one whose line is farther from p decides the side
            // (the point lies outside the corner's wedge on that segment's side).
            let better = match best {
                None => true,
                Some((bd, bi)) => {
                    d < bd - 1e-9 || (d < bd + 1e-9 && line_dist(p, s).abs() > line_dist(p, self.segs[bi]).abs())
                }
            };
            if better {
                best = Some((d, i as usize));
            }
        }
        best.filter(|b| b.0 <= COAST_REACH_M)
    }

    /// Within COAST_REACH_M of the coastline: true on its water side, false on its land side; None farther.
    pub fn sea(&self, p: [f64; 2]) -> Option<bool> {
        let (_, i) = self.nearest(p)?;
        Some(line_dist(p, self.segs[i]) < 0.0)
    }
}

/// A segment's length.
pub fn len(s: &[[f64; 2]; 2]) -> f64 {
    (s[1][0] - s[0][0]).hypot(s[1][1] - s[0][1])
}

fn seg_dist(p: [f64; 2], a: [f64; 2], b: [f64; 2]) -> f64 {
    let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
    let l2 = dx * dx + dy * dy;
    let t = if l2 > 0.0 { (((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2).clamp(0.0, 1.0) } else { 0.0 };
    (p[0] - a[0] - t * dx).hypot(p[1] - a[1] - t * dy)
}

/// The signed distance of `p` from the line through segment `s`: positive on its left.
fn line_dist(p: [f64; 2], s: [[f64; 2]; 2]) -> f64 {
    let (dx, dy) = (s[1][0] - s[0][0], s[1][1] - s[0][1]);
    (dx * (p[1] - s[0][1]) - dy * (p[0] - s[0][0])) / dx.hypot(dy).max(1e-9)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A coast running north with the sea to the west (land on the left of a northward way is west... so the way runs
    /// south): the water side and the land side, a corner, and nothing beyond the reach.
    #[test]
    fn coast_sides() {
        // Running south along x = 1000: its right is the west (the sea), its left the east (the land).
        let c = Coast::new(&[vec![[1000.0, 5000.0], [1000.0, 3000.0], [1500.0, 2000.0]]]);
        assert_eq!(c.sea([980.0, 4000.0]), Some(true));
        assert_eq!(c.sea([1020.0, 4000.0]), Some(false));
        // Near the corner (1000, 3000): south-west of it is sea, east of it land.
        assert_eq!(c.sea([990.0, 2990.0]), Some(true));
        assert_eq!(c.sea([1020.0, 3000.0]), Some(false));
        assert_eq!(c.sea([2000.0, 4000.0]), None);
        assert!(c.near([1010.0, 4000.0], 20.0) && !c.near([1100.0, 4000.0], 20.0));
    }
}
